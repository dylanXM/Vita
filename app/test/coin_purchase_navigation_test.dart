import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:vita/core/i18n/translations.dart';
import 'package:vita/core/theme.dart';
import 'package:vita/features/billing/billing_controller.dart';
import 'package:vita/features/billing/coin_purchase_page.dart';
import 'package:vita/features/billing/subscription_page.dart';

class _Billing extends BillingController {
  @override
  Future<void> init() async {}
  @override
  Future<void> refreshCredits() async {}
  @override
  Future<void> refreshPlanBenefits() async {}
}

void main() {
  setUp(() {
    Get.testMode = true;
    Get.put<BillingController>(_Billing());
  });
  tearDown(Get.reset);

  Widget host(Widget home) => GetMaterialApp(
        theme: VitaTheme.light,
        translations: VitaTranslations(),
        locale: const Locale('en'),
        home: home,
        getPages: [
          GetPage(name: '/credits/buy', page: () => const CoinPurchasePage())
        ],
      );

  testWidgets('dedicated coin store shows balance and packs without history',
      (tester) async {
    await tester.pumpWidget(host(const CoinPurchasePage()));
    await tester.pumpAndSettle();
    expect(find.text('Buy coins'), findsOneWidget);
    expect(find.text('Your balance'), findsOneWidget);
    expect(find.text('Buy more'), findsOneWidget);
    expect(find.text('History'), findsNothing);
  });

  testWidgets('subscription page opens the standalone coin store',
      (tester) async {
    await tester.pumpWidget(host(const SubscriptionPage()));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Buy coins'));
    await tester.tap(find.text('Buy coins'));
    await tester.pumpAndSettle();
    expect(find.byType(CoinPurchasePage), findsOneWidget);
  });
}
