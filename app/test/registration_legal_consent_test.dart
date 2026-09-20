import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:vita/core/i18n/translations.dart';
import 'package:vita/core/app_content_controller.dart';
import 'package:vita/core/legal_documents.dart';
import 'package:vita/features/auth/auth_controller.dart';
import 'package:vita/features/auth/register_page.dart';
import 'package:vita/features/auth/registration_legal_consent.dart';

void main() {
  tearDown(Get.reset);

  void registerLegalDocuments() {
    final controller = Get.put(AppContentController());
    controller.legalDocuments.assignAll({
      LegalDocumentType.privacy: LegalDocument(
        id: 'privacy',
        type: LegalDocumentType.privacy,
        version: 'v1',
        title: 'Privacy Policy',
        summary: 'Privacy summary',
        body: 'Information we collect',
        updatedAt: DateTime(2026, 9, 20),
      ),
      LegalDocumentType.terms: LegalDocument(
        id: 'terms',
        type: LegalDocumentType.terms,
        version: 'v1',
        title: 'Terms of Service',
        summary: 'Terms summary',
        body: 'By creating a Vita account',
        updatedAt: DateTime(2026, 9, 20),
      ),
    });
  }

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
    registerLegalDocuments();
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
    expect(find.text('Terms of Service'), findsOneWidget);
    expect(find.textContaining('By creating a Vita account'), findsOneWidget);

    Get.back();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('open-privacy')));
    await tester.pumpAndSettle();
    expect(find.text('Privacy Policy'), findsOneWidget);
    expect(find.textContaining('Information we collect'), findsOneWidget);
  });

  testWidgets('registration cannot continue until consent is checked',
      (tester) async {
    Get.put(AuthController());
    registerLegalDocuments();
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
