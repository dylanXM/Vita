import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:vita/core/i18n/translations.dart';
import 'package:vita/features/auth/auth_controller.dart';
import 'package:vita/features/auth/register_page.dart';
import 'package:vita/features/auth/registration_legal_consent.dart';

void main() {
  tearDown(Get.reset);

  testWidgets('consent starts unchecked and can be explicitly accepted',
      (tester) async {
    var accepted = false;
    await tester.pumpWidget(GetMaterialApp(
      translations: VitaTranslations(),
      locale: const Locale('zh', 'CN'),
      home: StatefulBuilder(builder: (context, setState) {
        return Scaffold(
          body: RegistrationLegalConsent(
            accepted: accepted,
            onChanged: (value) => setState(() => accepted = value),
          ),
        );
      }),
    ));

    expect(
      tester
          .widget<Checkbox>(
            find.byKey(const ValueKey('registration-legal-checkbox')),
          )
          .value,
      isFalse,
    );
    await tester.tap(find.byKey(const ValueKey('registration-legal-checkbox')));
    await tester.pump();
    expect(accepted, isTrue);
  });

  testWidgets('terms and privacy links open in-app documents', (tester) async {
    await tester.pumpWidget(GetMaterialApp(
      translations: VitaTranslations(),
      locale: const Locale('zh', 'CN'),
      home: Scaffold(
        body: RegistrationLegalConsent(
          accepted: false,
          onChanged: (_) {},
        ),
      ),
    ));

    await tester.tap(find.byKey(const ValueKey('open-terms')));
    await tester.pumpAndSettle();
    expect(find.text('用户协议'), findsWidgets);
    expect(find.textContaining('创建 Vita 账户'), findsOneWidget);

    Get.back();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('open-privacy')));
    await tester.pumpAndSettle();
    expect(find.text('隐私政策'), findsWidgets);
    expect(find.textContaining('我们收集的信息'), findsOneWidget);
  });

  testWidgets('registration cannot continue until consent is checked',
      (tester) async {
    Get.put(AuthController());
    await tester.pumpWidget(GetMaterialApp(
      translations: VitaTranslations(),
      locale: const Locale('zh', 'CN'),
      home: const RegisterPage(),
    ));

    await tester.enterText(
        find.byType(TextField).at(0), 'new-user@example.com');
    await tester.enterText(find.byType(TextField).at(1), 'secret12');
    await tester.pump();
    var button = tester.widget<ElevatedButton>(
      find.byKey(const ValueKey('register-get-code-button')),
    );
    expect(button.onPressed, isNull);
    expect(
      tester
          .widget<OutlinedButton>(
            find.byKey(const ValueKey('register-google-button')),
          )
          .onPressed,
      isNull,
    );

    await tester.tap(find.byKey(const ValueKey('registration-legal-checkbox')));
    await tester.pump();
    button = tester.widget<ElevatedButton>(
      find.byKey(const ValueKey('register-get-code-button')),
    );
    expect(button.onPressed, isNotNull);
    expect(
      tester
          .widget<OutlinedButton>(
            find.byKey(const ValueKey('register-google-button')),
          )
          .onPressed,
      isNotNull,
    );
  });
}
