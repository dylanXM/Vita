import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:vita/core/i18n/translations.dart';
import 'package:vita/core/theme.dart';
import 'package:vita/features/billing/billing_controller.dart';
import 'package:vita/features/billing/credits_page.dart';
import 'package:vita/features/billing/subscription_page.dart';

class _PresentationBillingController extends BillingController {
  @override
  Future<void> init() async {}
}

void main() {
  setUp(() {
    Get.testMode = true;
    Get.reset();
    Get.put<BillingController>(_PresentationBillingController());
  });

  tearDown(Get.reset);

  Widget app(Widget home) => GetMaterialApp(
        theme: VitaTheme.light,
        translations: VitaTranslations(),
        locale: const Locale('en'),
        home: home,
      );

  testWidgets('subscription page leads with value and plan choice',
      (tester) async {
    await tester.pumpWidget(app(const SubscriptionPage()));

    expect(find.text('Choose a plan'), findsOneWidget);
    expect(find.text('A life that continues'), findsOneWidget);
    expect(find.text('Monthly coins'), findsOneWidget);
    expect(find.text('More experiences'), findsOneWidget);
  });

  testWidgets('coin page uses wallet-style balance and grouped sections',
      (tester) async {
    await tester.pumpWidget(app(const CreditsPage()));

    expect(find.text('Your balance'), findsOneWidget);
    expect(find.text('Buy more'), findsOneWidget);
    expect(find.text('History'), findsOneWidget);
    expect(find.byIcon(Icons.account_balance_wallet_outlined), findsOneWidget);
  });
}
