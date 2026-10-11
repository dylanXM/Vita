import 'package:dio/dio.dart' as dio;
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:vita/core/api_client.dart';
import 'package:vita/core/i18n/translations.dart';
import 'package:vita/core/theme.dart';
import 'package:vita/features/chat/experience_sheet.dart';

void main() {
  late dio.Interceptor stub;
  bool launched = true;
  bool subscriptionOnly = true;
  bool subscribed = false;
  String category = 'photo';
  int balance = 100;
  late List<String> purchases;
  setUp(() {
    Get.testMode = true;
    FlutterSecureStorage.setMockInitialValues({});
    launched = true;
    subscriptionOnly = true;
    subscribed = false;
    category = 'photo';
    balance = 100;
    purchases = [];
    stub = dio.InterceptorsWrapper(onRequest: (options, handler) {
      if (options.method == 'POST') purchases.add(options.path);
      handler.resolve(
          dio.Response(requestOptions: options, statusCode: 200, data: {
        'balance': balance,
        'is_subscribed': subscribed,
        'products': [
          {
            'key': 'life_photo',
            'category': category,
            'coins': 20,
            'name_key': 'experience.photo',
            'description_key': 'experience.photo.desc',
            'subscription_only': subscriptionOnly,
            'is_launched': launched,
          }
        ],
      }));
    });
    ApiClient.instance.dio.interceptors.insert(0, stub);
  });
  tearDown(() {
    ApiClient.instance.dio.interceptors.remove(stub);
    Get.reset();
  });
  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(GetMaterialApp(
      theme: VitaTheme.light,
      translations: VitaTranslations(),
      locale: const Locale('en'),
      getPages: [
        GetPage(
            name: '/credits/buy',
            page: () =>
                const Scaffold(body: Text('Coin purchase destination'))),
        GetPage(
            name: '/subscription',
            page: () => const Scaffold(body: Text('Subscription destination')))
      ],
      home: Scaffold(
          body: Builder(
              builder: (context) => TextButton(
                    onPressed: () => showModalBottomSheet<void>(
                        context: context,
                        isScrollControlled: true,
                        builder: (_) => ExperienceSheet(
                            companionId: 'friend', onCompleted: () async {})),
                    child: const Text('Open experiences'),
                  ))),
    ));
    await tester.tap(find.text('Open experiences'));
    await tester.pumpAndSettle();
  }

  test('availability labels exist in all eight locales', () {
    final translations = VitaTranslations().keys;
    for (final locale in translations.entries) {
      for (final key in [
        'credits.purchaseTitle',
        'experience.insufficientCoins',
        'experience.comingSoon',
        'experience.subscriptionOnly',
        'experience.subscribeToUse'
      ]) {
        expect(locale.value[key], isNotEmpty, reason: '${locale.key}: $key');
      }
    }
  });
  testWidgets(
      'insufficient date coins redirects to coin purchase without inviting',
      (tester) async {
    category = 'date';
    subscriptionOnly = false;
    balance = 19;
    await open(tester);
    expect(find.text('Not enough coins'), findsOneWidget);
    await tester.tap(find.byType(ElevatedButton));
    await tester.pumpAndSettle();
    expect(find.text('Coin purchase destination'), findsOneWidget);
    expect(purchases, isEmpty);
  });
  testWidgets('date invitation is enabled when balance equals price',
      (tester) async {
    category = 'date';
    subscriptionOnly = false;
    balance = 20;
    await open(tester);
    expect(tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed,
        isNotNull);
  });
  testWidgets('unlaunched experiences remain visible and cannot be purchased',
      (tester) async {
    launched = false;
    await open(tester);
    final button = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
    expect(button.onPressed, isNull);
    expect(find.text('Coming soon'), findsWidgets);
    expect(purchases, isEmpty);
  });
  testWidgets('exclusive experience redirects non-subscriber before purchase',
      (tester) async {
    await open(tester);
    await tester.tap(find.byType(ElevatedButton));
    await tester.pumpAndSettle();
    expect(find.text('Subscription destination'), findsOneWidget);
    expect(purchases, isEmpty);
  });
  testWidgets(
      'non-exclusive experience opens confirmation without subscription',
      (tester) async {
    subscriptionOnly = false;
    await open(tester);
    await tester.tap(find.byType(ElevatedButton));
    await tester.pumpAndSettle();
    expect(find.byType(CupertinoAlertDialog), findsOneWidget);
    expect(find.text('Subscription destination'), findsNothing);
    expect(purchases, isEmpty);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
  });
}
