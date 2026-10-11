import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:vita/core/app_content_controller.dart';
import 'package:vita/core/i18n/translations.dart';
import 'package:vita/core/theme.dart';
import 'package:vita/features/auth/auth_controller.dart';
import 'package:vita/features/billing/billing_controller.dart';
import 'package:vita/features/me/me_page.dart';
import 'package:vita/features/settings/profile_edit_page.dart';

class _Billing extends BillingController {
  @override
  void onInit() {}
}

void main() {
  tearDown(Get.reset);
  testWidgets('profile shows entry and billing values share trailing alignment',
      (tester) async {
    Get.testMode = true;
    Get.reset();
    final auth = Get.put(AuthController());
    auth.profile.value = {'nickname': 'Ava'};
    final billing = Get.put<BillingController>(_Billing());
    billing.balance.value = 40;
    billing.entitlements.add('PLUS_MONTHLY');
    Get.put(AppContentController());
    await tester.pumpWidget(GetMaterialApp(
        theme: VitaTheme.light,
        translations: VitaTranslations(),
        locale: const Locale('en'),
        home: const MePage()));
    await tester.pumpAndSettle();
    final subscription = find.text('PLUS_MONTHLY');
    final credits = find.text('40');
    expect(subscription, findsOneWidget);
    expect(tester.getRect(subscription).right, tester.getRect(credits).right);
    final arrows = find.byIcon(Icons.chevron_right_rounded);
    final subscriptionArrow = arrows.at(1), creditArrow = arrows.at(2);
    expect(tester.getRect(subscriptionArrow).right,
        tester.getRect(creditArrow).right);
    await tester.tap(find.byType(InkWell).first);
    await tester.pumpAndSettle();
    expect(find.byType(ProfileEditPage), findsOneWidget);
  });
}
