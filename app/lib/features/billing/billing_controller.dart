import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:get/get.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import '../../core/notice.dart';
import '../../core/api_client.dart';
import '../../core/analytics_service.dart';
import '../../core/constants.dart';
import 'billing_products.dart';
import '../chat/chat_list_controller.dart';
import '../ads/admob_controller.dart';
import '../auth/auth_controller.dart';

/// Billing state: RevenueCat (mobile subscriptions + credit packs), Stripe
/// (web/admin side) and the server-side credit balance / entitlement sync.
class BillingController extends GetxController {
  static BillingController get to => Get.find();

  final rcReady = false.obs;
  final busy = false.obs;

  final balance = 0.obs;
  final transactions = <Map<String, dynamic>>[].obs;

  final subscription = Rxn<Map<String, dynamic>>();
  final entitlements = <String>[].obs;
  final offerings = Rxn<Offerings>();
  final planBenefits = <String, List<String>>{}.obs;
  String? _identifiedUserID;
  Future<void>? _initializing;
  Future<void>? _identitySync;
  final fulfillmentPending = false.obs;
  final checkingFulfillment = false.obs;
  final subscribed = false.obs;
  final List<Map<String, String>> _pendingPurchases = [];
  bool _pendingLoaded = false;
  Timer? _fulfillmentTimer;
  Future<void>? _fulfillmentCheck;
  bool _closed = false;
  int _sessionGeneration = 0;
  void Function(CustomerInfo)? _customerInfoListener;
  static const _pendingKey = 'vita.billing.pending_purchases.v1';

  String get currentUserID => Get.isRegistered<AuthController>()
      ? '${AuthController.to.profile.value?['user_id'] ?? ''}'
      : '';

  Future<PurchaseResult> buyStorePackage(Package package) =>
      Purchases.purchase(PurchaseParams.package(package));

  Future<CustomerInfo> restoreStorePurchases() => Purchases.restorePurchases();

  Future<void> identifyStoreUser(String userID) async {
    await Purchases.logIn(userID);
    if (await Purchases.appUserID != userID) {
      throw StateError('RevenueCat identity did not match the Vita user');
    }
  }

  @override
  void onInit() {
    super.onInit();
    ApiClient.onPaidActionSuccess = refreshCredits;
    _initializing = init();
  }

  @override
  void onClose() {
    _closed = true;
    _sessionGeneration++;
    _fulfillmentTimer?.cancel();
    if (_customerInfoListener != null)
      Purchases.removeCustomerInfoUpdateListener(_customerInfoListener!);
    ApiClient.onPaidActionSuccess = null;
    super.onClose();
  }

  Future<void> init() async {
    if (kDebugMode) {
      debugPrint('[Billing] RevenueCat init: '
          'keyPresent=${revenueCatApiKey.isNotEmpty}, '
          'testStore=${revenueCatApiKey.startsWith('test_')}');
    }
    if (revenueCatApiKey.isNotEmpty) {
      try {
        if (kDebugMode) await Purchases.setLogLevel(LogLevel.debug);
        await Purchases.configure(PurchasesConfiguration(revenueCatApiKey));
        _customerInfoListener = (_) {
          unawaited(refreshSubscription());
          unawaited(refreshCredits());
        };
        Purchases.addCustomerInfoUpdateListener(_customerInfoListener!);
        rcReady.value = true;
        await _loadOfferings('init');
      } catch (error, stackTrace) {
        if (kDebugMode) {
          debugPrint('[Billing] RevenueCat init failed: $error\n$stackTrace');
        }
        rcReady.value = false;
      }
    }
    if (currentUserID.isNotEmpty) {
      await refreshSubscription();
      await refreshCredits();
      await refreshPlanBenefits();
    }
  }

  Future<void> _loadOfferings(String source) async {
    try {
      final loaded = await Purchases.getOfferings();
      offerings.value = loaded;
      if (kDebugMode) {
        debugPrint('[Billing] Offerings loaded ($source): '
            'current=${loaded.current?.identifier}, count=${loaded.all.length}');
        for (final offering in loaded.all.values) {
          debugPrint('[Billing] Offering ${offering.identifier}: '
              'packages=${offering.availablePackages.length}');
          for (final package in offering.availablePackages) {
            debugPrint('[Billing] Package ${package.identifier}: '
                'product=${package.storeProduct.identifier}');
          }
        }
      }
    } catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint('[Billing] Offerings failed ($source): $error\n$stackTrace');
      }
      rethrow;
    }
  }

  final coinProductCoins = <String, int>{}.obs;
  final subscriptionProductIDs = <String, bool>{}.obs;
  final catalogLoaded = false.obs;

  int coinsForProduct(String id) => catalogLoaded.value
      ? coinProductCoins[id.toLowerCase()] ?? 0
      : vitaCoinProductIds[id.toLowerCase()] ?? 0;
  bool includesCoin(String id) => catalogLoaded.value
      ? coinProductCoins.containsKey(id.toLowerCase())
      : vitaCoinProductIds.containsKey(id.toLowerCase());
  bool includesSubscription(String packageID, String productID) =>
      catalogLoaded.value
          ? subscriptionProductIDs.containsKey(productID.toLowerCase())
          : isSubscriptionProduct(packageID, productID);

  Future<bool>? _benefitsFlight;
  Future<bool>? _configurationFlight;
  String? _configurationUserID;

  Future<void> refreshPlanBenefits() async {
    await synchronizeBenefits();
  }

  Future<bool> synchronizeBenefits() {
    if (_benefitsFlight != null) return _benefitsFlight!;
    final next = _refreshPlanBenefits();
    _benefitsFlight = next;
    return next.whenComplete(() => _benefitsFlight = null);
  }

  Future<bool> synchronizeConfiguration({bool refreshCatalog = true}) {
    if (_configurationFlight != null) return _configurationFlight!;
    final next = _synchronizeConfiguration(refreshCatalog);
    _configurationFlight = next;
    return next.whenComplete(() => _configurationFlight = null);
  }

  Future<bool> _synchronizeConfiguration(bool refreshCatalog) async {
    await _initializing;
    final user = currentUserID;
    if (user.isEmpty) return false;
    if (_configurationUserID != user) {
      await refreshSubscription();
      await refreshCredits();
      if (currentUserID != user) return false;
      _configurationUserID = user;
    }
    final benefitsOK = await synchronizeBenefits();
    if (!refreshCatalog) return benefitsOK;
    bool catalogOK = false;
    try {
      final raw = await ApiClient.instance.get('/v1/billing/catalog',
          receiveTimeout: const Duration(seconds: 5));
      final items = raw is Map ? raw['items'] : null;
      if (items is List && currentUserID == user) {
        final coins = <String, int>{};
        final plans = <String, bool>{};
        for (final item in items.whereType<Map>()) {
          final id = '${item['product_id'] ?? ''}'.toLowerCase();
          if (id.isEmpty) continue;
          if (item['kind'] == 'coin')
            coins[id] = (item['coins'] as num?)?.toInt() ?? 0;
          if (item['kind'] == 'subscription') plans[id] = true;
        }
        coinProductCoins.assignAll(coins);
        subscriptionProductIDs.assignAll(plans);
        catalogLoaded.value = true;
        catalogOK = true;
      }
    } catch (_) {}
    if (currentUserID != user) return false;
    if (!rcReady.value) return benefitsOK && catalogOK;
    try {
      if (_identifiedUserID != user) {
        await syncUser(user);
        if (_identifiedUserID != user) return false;
      } else {
        await _loadOfferings('config_sync');
      }
      return benefitsOK && catalogOK;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _refreshPlanBenefits() async {
    final user = currentUserID;
    final locale = Get.locale;
    try {
      final data = await ApiClient.instance.get(
          '/v1/subscription-plans/benefits',
          receiveTimeout: const Duration(seconds: 5));
      final items = data is Map ? data['items'] : null;
      if (items is! List) return false;
      final benefits = <String, List<String>>{};
      for (final item in items.whereType<Map>()) {
        final productID = '${item['product_id'] ?? ''}';
        if (productID.isEmpty) continue;
        benefits[productID] = (item['benefits'] as List? ?? const [])
            .whereType<String>()
            .where((value) => value.trim().isNotEmpty)
            .toList();
      }
      if (_closed || user != currentUserID || locale != Get.locale)
        return false;
      planBenefits.assignAll(benefits);
      return true;
    } catch (_) {
      // Preserve the last valid benefits and allow a later retry.
      return false;
    }
  }

  Future<void> syncUser(String userID) async {
    if (_closed) return;
    await _initializing;
    if (!rcReady.value || userID.isEmpty) return;
    await _identitySync;
    if (_identifiedUserID != userID) {
      final sync = () async {
        try {
          await identifyStoreUser(userID);
          if (_closed || currentUserID != userID) return;
          _identifiedUserID = userID;
          await _loadOfferings('syncUser');
        } catch (error) {
          _identifiedUserID = null;
          if (kDebugMode) debugPrint('[Billing] User sync failed: $error');
        }
      }();
      _identitySync = sync;
      try {
        await sync;
      } finally {
        if (identical(_identitySync, sync)) _identitySync = null;
      }
    }
    await _loadPendingPurchases();
    _updatePendingState();
    _startFulfillmentTimer();
    if (_identifiedUserID == userID && fulfillmentPending.value)
      await retryPendingPurchases();
  }

  Future<void> _preparePurchase() async {
    final userID = currentUserID;
    await syncUser(userID);
    if (userID.isEmpty ||
        currentUserID != userID ||
        !rcReady.value ||
        _identifiedUserID != userID) {
      throw StateError('Purchase identity is not ready');
    }
  }

  Future<void> clearUser() async {
    _sessionGeneration++;
    _fulfillmentTimer?.cancel();
    fulfillmentPending.value = false;
    subscribed.value = false;
    subscription.value = null;
    entitlements.clear();
    balance.value = 0;
    transactions.clear();
    coinProductCoins.clear();
    subscriptionProductIDs.clear();
    catalogLoaded.value = false;
    planBenefits.clear();
    _configurationUserID = null;
    if (Get.isRegistered<AdmobController>()) {
      AdmobController.to.config.value = null;
    }
    if (!rcReady.value || _identifiedUserID == null) return;
    try {
      await Purchases.logOut();
    } catch (_) {
      // The local Vita session must still be cleared if RevenueCat is offline.
    } finally {
      _identifiedUserID = null;
    }
  }

  Future<void> refreshCredits() async {
    final userID = currentUserID;
    final session = _sessionGeneration;
    try {
      final data = await ApiClient.instance.get('/v1/me/credits');
      if (_closed || session != _sessionGeneration || currentUserID != userID)
        return;
      balance.value = (data['balance'] as num?)?.toInt() ?? 0;
      transactions.assignAll(
        (data['transactions'] as List? ?? [])
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e)),
      );
    } catch (_) {
      // server unreachable — keep last known values
    }
  }

  Future<void> refreshSubscription() async {
    final userID = currentUserID;
    final session = _sessionGeneration;
    try {
      final data = await ApiClient.instance.get('/v1/me/subscription');
      if (_closed || session != _sessionGeneration || currentUserID != userID)
        return;
      subscribed.value = data['is_subscribed'] == true ||
          (data['entitlements'] is List &&
              (data['entitlements'] as List).isNotEmpty);
      subscription.value = data['subscription'] == null
          ? null
          : Map<String, dynamic>.from(data['subscription'] as Map);
      entitlements
          .assignAll(List<String>.from(data['entitlements'] as List? ?? []));
    } catch (_) {
      // keep last known values
    }
  }

  bool get isSubscribed => subscribed.value || entitlements.isNotEmpty;

  Future<void> _loadPendingPurchases() async {
    if (_pendingLoaded) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_pendingKey);
    if (raw != null) {
      try {
        for (final item in (jsonDecode(raw) as List).whereType<Map>()) {
          final value = Map<String, String>.from(item);
          if (value['user_id']?.isNotEmpty == true &&
              value['product_id']?.isNotEmpty == true &&
              DateTime.tryParse(value['purchased_at'] ?? '') != null)
            _pendingPurchases.add(value);
        }
      } catch (_) {
        if (kDebugMode)
          debugPrint('[Billing] Invalid pending purchase storage');
      }
    }
    _pendingLoaded = true;
  }

  Future<void> _savePendingPurchases() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_pendingKey, jsonEncode(_pendingPurchases));
    } catch (error) {
      if (kDebugMode)
        debugPrint('[Billing] Pending purchase storage failed: $error');
    }
  }

  void _updatePendingState() => fulfillmentPending.value =
      _pendingPurchases.any((p) => p['user_id'] == currentUserID);

  void _startFulfillmentTimer() {
    if (_pendingPurchases.isEmpty || _fulfillmentTimer?.isActive == true)
      return;
    _fulfillmentTimer = Timer.periodic(
        const Duration(seconds: 15), (_) => unawaited(retryPendingPurchases()));
  }

  Future<void> _rememberPurchase(
      String userID, StoreTransaction transaction) async {
    final value = <String, String>{
      'user_id': userID,
      'product_id': transaction.productIdentifier,
      'transaction_id': transaction.transactionIdentifier,
      'purchased_at': transaction.purchaseDate
    };
    if (!_pendingPurchases.any((p) =>
        p['user_id'] == userID &&
        p['product_id'] == value['product_id'] &&
        p['transaction_id'] == value['transaction_id'] &&
        p['purchased_at'] == value['purchased_at'])) {
      _pendingPurchases.add(value);
    }
    _updatePendingState();
    _startFulfillmentTimer();
    await _savePendingPurchases();
  }

  Future<void> _refreshConfirmedState(String userID) async {
    final session = _sessionGeneration;
    final values = await Future.wait([
      ApiClient.instance.get('/v1/me/credits'),
      ApiClient.instance.get('/v1/me/subscription'),
    ]);
    if (_closed || session != _sessionGeneration || currentUserID != userID)
      throw StateError('The purchase belongs to a different session');
    final credits = values[0] as Map;
    final plan = values[1] as Map;
    balance.value = (credits['balance'] as num).toInt();
    transactions.assignAll((credits['transactions'] as List)
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e)));
    subscription.value = plan['subscription'] is Map
        ? Map<String, dynamic>.from(plan['subscription'] as Map)
        : null;
    entitlements
        .assignAll(List<String>.from(plan['entitlements'] as List? ?? []));
    subscribed.value = plan['is_subscribed'] == true || entitlements.isNotEmpty;
  }

  Future<void> retryPendingPurchases() {
    final current = _fulfillmentCheck;
    if (current != null) return current;
    late final Future<void> check;
    check = () async {
      try {
        await _checkPendingPurchases();
      } finally {
        if (identical(_fulfillmentCheck, check)) _fulfillmentCheck = null;
      }
    }();
    _fulfillmentCheck = check;
    return check;
  }

  Future<void> _checkPendingPurchases() async {
    final userID = currentUserID;
    final session = _sessionGeneration;
    if (_closed ||
        checkingFulfillment.value ||
        userID.isEmpty ||
        _identifiedUserID != userID) return;
    checkingFulfillment.value = true;
    var completed = false;
    try {
      for (final purchase
          in List<Map<String, String>>.from(_pendingPurchases)) {
        if (_closed || session != _sessionGeneration) return;
        if (purchase['user_id'] != userID || currentUserID != userID) continue;
        try {
          final result =
              await ApiClient.instance.post('/v1/me/billing/confirm', data: {
            'product_id': purchase['product_id'],
            'transaction_id': purchase['transaction_id'],
            'purchased_at': purchase['purchased_at'],
          });
          if (_closed ||
              session != _sessionGeneration ||
              currentUserID != userID) return;
          if (result is Map && result['fulfilled'] == true) {
            await _refreshConfirmedState(userID);
            _pendingPurchases.remove(purchase);
            if (Get.isRegistered<AnalyticsService>())
              AnalyticsService.to.track('purchase_succeeded',
                  category: 'billing',
                  properties: {'product_id': purchase['product_id']});
            completed = true;
          }
        } catch (error) {
          if (kDebugMode) debugPrint('[Billing] Fulfillment pending: $error');
        }
      }
      if (_closed || session != _sessionGeneration) return;
      await _savePendingPurchases();
      _updatePendingState();
      if (_pendingPurchases.isEmpty) _fulfillmentTimer?.cancel();
      if (completed &&
          !_closed &&
          session == _sessionGeneration &&
          currentUserID == userID) {
        VitaNotice.success('Vita', 'billing.purchaseSuccess'.tr);
        // Auxiliary refresh failures must never turn a fulfilled payment into a failed one.
        try {
          if (Get.isRegistered<AdmobController>())
            await AdmobController.to.refreshConfig();
          if (Get.isRegistered<ChatListController>())
            await ChatListController.to.load();
        } catch (error) {
          if (kDebugMode)
            debugPrint('[Billing] Post-purchase refresh failed: $error');
        }
      }
    } finally {
      checkingFulfillment.value = false;
    }
  }

  /// Both coin packs and subscriptions wait for server-confirmed fulfillment.
  Future<void> purchasePackage(Package pkg) async {
    if (busy.value) return;
    busy.value = true;
    final userID = currentUserID;
    var paid = false;
    var prepared = false;
    try {
      await _preparePurchase();
      prepared = true;
      if (_pendingPurchases.any((p) =>
          p['user_id'] == userID &&
          p['product_id'] == pkg.storeProduct.identifier)) {
        VitaNotice.info('Vita', 'billing.fulfillmentPending'.tr);
        await retryPendingPurchases();
        return;
      }
      AnalyticsService.to.track('purchase_started',
          category: 'billing',
          properties: {'product_id': pkg.storeProduct.identifier});
      final result = await buyStorePackage(pkg);
      paid = true;
      await _rememberPurchase(userID, result.storeTransaction);
      AnalyticsService.to.track('purchase_paid',
          category: 'billing',
          properties: {'product_id': pkg.storeProduct.identifier});
      await retryPendingPurchases();
      if (_pendingPurchases.any((p) =>
          p['user_id'] == userID &&
          p['product_id'] == pkg.storeProduct.identifier)) {
        VitaNotice.info('Vita', 'billing.fulfillmentPending'.tr);
      }
    } on PlatformException catch (error) {
      final cancelled = int.tryParse(error.code) ==
          PurchasesErrorCode.purchaseCancelledError.index;
      AnalyticsService.to.track(
          cancelled ? 'purchase_canceled' : 'purchase_failed',
          category: 'billing',
          properties: {'product_id': pkg.storeProduct.identifier});
      if (paid)
        VitaNotice.info('Vita', 'billing.fulfillmentPending'.tr);
      else if (cancelled)
        VitaNotice.info('Vita', 'billing.purchaseCancelled'.tr);
      else
        VitaNotice.error(
            'billing.purchaseFailed'.tr, 'billing.purchaseErrorMessage'.tr);
    } catch (error) {
      if (kDebugMode) debugPrint('[Billing] Purchase error: $error');
      if (paid)
        VitaNotice.info('Vita', 'billing.fulfillmentPending'.tr);
      else
        VitaNotice.error(
            'billing.purchaseFailed'.tr,
            (prepared
                    ? 'billing.purchaseErrorMessage'
                    : 'billing.identityNotReady')
                .tr);
    } finally {
      busy.value = false;
    }
  }

  Future<void> restorePurchases() async {
    if (busy.value) return;
    busy.value = true;
    AnalyticsService.to.track('purchase_restore_started', category: 'billing');
    var prepared = false;
    try {
      await _preparePurchase();
      final userID = currentUserID;
      prepared = true;
      final restored = await restoreStorePurchases();
      for (final transaction in restored.nonSubscriptionTransactions) {
        await _rememberPurchase(userID, transaction);
      }
      for (final productID in restored.activeSubscriptions) {
        final date = restored.allPurchaseDates[productID];
        if (date != null)
          await _rememberPurchase(
              userID, StoreTransaction('', productID, date));
      }
      await retryPendingPurchases();
      await _refreshConfirmedState(userID);
      if (fulfillmentPending.value)
        VitaNotice.info('Vita', 'billing.fulfillmentPending'.tr);
      else if (!isSubscribed && restored.nonSubscriptionTransactions.isEmpty)
        VitaNotice.info('Vita', 'billing.nothingToRestore'.tr);
      else
        VitaNotice.success('Vita', 'billing.restored'.tr);
    } catch (e) {
      AnalyticsService.to.track('purchase_restore_failed', category: 'billing');
      if (kDebugMode) debugPrint('[Billing] Restore failed: $e');
      VitaNotice.error(
          'billing.restoreFailed'.tr,
          (prepared
                  ? 'billing.purchaseErrorMessage'
                  : 'billing.identityNotReady')
              .tr);
    } finally {
      busy.value = false;
    }
  }
}
