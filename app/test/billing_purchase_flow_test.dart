import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vita/core/analytics_service.dart';
import 'package:vita/core/api_client.dart';
import 'package:vita/core/i18n/translations.dart';
import 'package:vita/core/theme.dart';
import 'package:vita/features/billing/billing_controller.dart';

const _date = '2026-10-12T14:00:00Z';
const _customer = CustomerInfo(
    EntitlementInfos({}, {}), {}, [], [], [], _date, 'u', {}, _date);

Package _package(String product) => Package(
    'package-$product',
    PackageType.custom,
    StoreProduct(product, 'Description', 'Product', 2.99, r'$2.99', 'USD'),
    const PresentedOfferingContext('default', null, null));

class _Analytics extends AnalyticsService {
  final events = <String>[];
  @override
  void onInit() {}
  @override
  void onClose() {}
  @override
  void track(String name,
          {String? category, Map<String, Object?> properties = const {}}) =>
      events.add(name);
}

class _Billing extends BillingController {
  String user = 'u';
  bool identityFails = false;
  Object? purchaseError;
  int purchases = 0;
  CustomerInfo restored = _customer;
  Object? restoreError;
  @override
  Future<CustomerInfo> restoreStorePurchases() async {
    if (restoreError != null) throw restoreError!;
    return restored;
  }

  @override
  String get currentUserID => user;
  @override
  Future<void> init() async {
    rcReady.value = true;
  }

  @override
  Future<void> identifyStoreUser(String userID) async {
    if (identityFails) throw StateError('identity unavailable');
  }

  @override
  Future<PurchaseResult> buyStorePackage(Package package) async {
    purchases++;
    if (purchaseError != null) throw purchaseError!;
    return PurchaseResult(_customer,
        StoreTransaction('store-id', package.storeProduct.identifier, _date));
  }
}

class _Backend implements HttpClientAdapter {
  bool fulfilled = false;
  bool refreshFails = false;
  bool subscribed = false;
  int balance = 135;
  final confirmations = <Map<String, dynamic>>[];
  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    Object data;
    var status = 200;
    switch (options.path) {
      case '/v1/me/billing/confirm':
        confirmations.add(Map<String, dynamic>.from(options.data as Map));
        data = {'fulfilled': fulfilled};
      case '/v1/me/credits':
        status = refreshFails ? 503 : 200;
        data = {'balance': balance, 'transactions': []};
      case '/v1/me/subscription':
        data = {
          'subscription': subscribed ? {'status': 'active'} : null,
          'entitlements': [],
          'is_subscribed': subscribed
        };
      default:
        throw StateError('unexpected request ${options.path}');
    }
    return ResponseBody.fromString(jsonEncode(data), status, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType]
    });
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Backend backend;
  late _Analytics analytics;
  late _Billing billing;
  setUp(() {
    Get.testMode = true;
    Get.reset();
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('purchases_flutter'),
            (call) async => {'all': {}, 'current': null});
    backend = _Backend();
    ApiClient.instance.dio.httpClientAdapter = backend;
    analytics = Get.put<AnalyticsService>(_Analytics()) as _Analytics;
    billing = Get.put<BillingController>(_Billing()) as _Billing;
  });
  tearDown(() {
    Get.reset();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('purchases_flutter'), null);
  });
  Future<void> host(WidgetTester tester) async {
    await tester.pumpWidget(GetMaterialApp(
        theme: VitaTheme.light,
        translations: VitaTranslations(),
        locale: const Locale('en'),
        home: const Scaffold(body: Text('Billing'))));
    await tester.pump();
  }

  Future<void> dismissNotice(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  }

  for (final product in ['vita.coins.100', 'vita.plus.monthly']) {
    testWidgets('$product shows failure despite userCancelled:false',
        (tester) async {
      await host(tester);
      billing.purchaseError = PlatformException(
          code: '0',
          message: 'Simulated purchase failure',
          details: {'userCancelled': false});
      await tester.runAsync(() => billing.purchasePackage(_package(product)));
      await tester.pumpAndSettle();
      expect(find.text('Purchase failed'), findsOneWidget);
      expect(
          find.text(
              'The purchase could not be completed. Please try again later.'),
          findsOneWidget);
      expect(analytics.events, contains('purchase_failed'));
      expect(analytics.events, isNot(contains('purchase_canceled')));
      expect(backend.confirmations, isEmpty);
      expect(billing.busy.value, isFalse);
      await dismissNotice(tester);
    });
    testWidgets('$product reports success only after backend fulfillment',
        (tester) async {
      await host(tester);
      final package = _package(product);
      await tester.runAsync(() => billing.purchasePackage(package));
      await tester.pumpAndSettle();
      expect(billing.balance.value, 0);
      expect(billing.fulfillmentPending.value, isTrue);
      expect(find.text('Purchase successful'), findsNothing);
      expect(analytics.events, isNot(contains('purchase_succeeded')));
      await tester.runAsync(() => billing.purchasePackage(package));
      expect(billing.purchases, 1,
          reason: 'pending fulfillment must not buy again');
      backend.fulfilled = true;
      backend.subscribed = product == 'vita.plus.monthly';
      await tester.runAsync(billing.retryPendingPurchases);
      await tester.pumpAndSettle();
      expect(billing.balance.value, 135);
      expect(billing.isSubscribed, backend.subscribed);
      expect(billing.fulfillmentPending.value, isFalse);
      expect(find.text('Purchase successful'), findsOneWidget);
      expect(backend.confirmations.first['transaction_id'], 'store-id');
      expect(analytics.events, contains('purchase_succeeded'));
      await dismissNotice(tester);
    });
  }

  testWidgets('identity failure blocks the store purchase', (tester) async {
    await host(tester);
    billing.identityFails = true;
    await tester
        .runAsync(() => billing.purchasePackage(_package('vita.coins.100')));
    await tester.pumpAndSettle();
    expect(billing.purchases, 0);
    expect(backend.confirmations, isEmpty);
    expect(
        find.text(
            'Your purchase account could not be verified. Please sign in again or retry.'),
        findsOneWidget);
    await dismissNotice(tester);
  });
  testWidgets('cancellation is distinct from a failed purchase',
      (tester) async {
    await host(tester);
    billing.purchaseError = PlatformException(
        code: '1', message: 'Cancelled', details: {'userCancelled': true});
    await tester
        .runAsync(() => billing.purchasePackage(_package('vita.coins.100')));
    await tester.pumpAndSettle();
    expect(find.text('Purchase cancelled.'), findsOneWidget);
    expect(find.text('Purchase failed'), findsNothing);
    expect(analytics.events, contains('purchase_canceled'));
    await dismissNotice(tester);
  });
  testWidgets('confirmed payment stays pending if balance refresh fails',
      (tester) async {
    await host(tester);
    backend.fulfilled = true;
    backend.refreshFails = true;
    await tester
        .runAsync(() => billing.purchasePackage(_package('vita.coins.100')));
    await tester.pumpAndSettle();
    expect(billing.fulfillmentPending.value, isTrue);
    expect(find.text('Purchase successful'), findsNothing);
    backend.refreshFails = false;
    await tester.runAsync(billing.retryPendingPurchases);
    expect(billing.balance.value, 135);
    expect(billing.fulfillmentPending.value, isFalse);
    await dismissNotice(tester);
  });
  testWidgets(
      'pending orders survive controller restart and remain owned by their user',
      (tester) async {
    await host(tester);
    await tester
        .runAsync(() => billing.purchasePackage(_package('vita.coins.100')));
    await dismissNotice(tester);
    Get.delete<BillingController>();
    billing =
        Get.put<BillingController>(_Billing()..user = 'other') as _Billing;
    final before = backend.confirmations.length;
    await tester.runAsync(() => billing.syncUser('other'));
    expect(billing.fulfillmentPending.value, isFalse);
    expect(backend.confirmations.length, before);
    billing.user = 'u';
    backend.fulfilled = true;
    await tester.runAsync(() async {
      await billing.syncUser('u');
      await billing.retryPendingPurchases();
      for (var i = 0; i < 30 && billing.checkingFulfillment.value; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
    });
    expect(billing.balance.value, 135);
    expect(billing.fulfillmentPending.value, isFalse);
    expect(billing.purchases, 0);
    await dismissNotice(tester);
  });
  testWidgets('restored subscription also waits for backend fulfillment',
      (tester) async {
    await host(tester);
    billing.restored = const CustomerInfo(
        EntitlementInfos({}, {}),
        {'vita.plus.monthly': _date},
        ['vita.plus.monthly'],
        ['vita.plus.monthly'],
        [],
        _date,
        'u',
        {},
        _date);
    await tester.runAsync(billing.restorePurchases);
    expect(billing.fulfillmentPending.value, isTrue);
    expect(billing.isSubscribed, isFalse);
    expect(backend.confirmations.first['product_id'], 'vita.plus.monthly');
    expect(backend.confirmations.first['transaction_id'], '');
    backend.fulfilled = true;
    backend.subscribed = true;
    await tester.runAsync(billing.retryPendingPurchases);
    expect(billing.isSubscribed, isTrue);
    expect(billing.fulfillmentPending.value, isFalse);
    await dismissNotice(tester);
  });
  testWidgets(
      'restore failure is visible and an empty restore is not claimed as successful',
      (tester) async {
    await host(tester);
    billing.restoreError = PlatformException(
        code: '0', message: 'Failure', details: {'userCancelled': false});
    await tester.runAsync(billing.restorePurchases);
    await tester.pumpAndSettle();
    expect(find.text('Restore failed'), findsOneWidget);
    await dismissNotice(tester);
    billing.restoreError = null;
    await tester.runAsync(billing.restorePurchases);
    await tester.pumpAndSettle();
    expect(find.text('No restorable purchases were found.'), findsOneWidget);
    await dismissNotice(tester);
  });

  test('every new purchase message exists in all eight locales', () {
    for (final locale in VitaTranslations().keys.entries) {
      for (final key in [
        'billing.fulfillmentPending',
        'billing.purchaseCancelled',
        'billing.purchaseErrorMessage',
        'billing.identityNotReady',
        'billing.retrySync',
        'billing.nothingToRestore'
      ]) {
        expect(locale.value[key], isNotEmpty, reason: '${locale.key}: $key');
      }
    }
  });
}
