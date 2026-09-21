import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:vita/core/i18n/translations.dart';
import 'package:vita/core/theme.dart';
import 'package:vita/features/companion/companion_create_method_page.dart';

void main() {
  setUp(() {
    Get.testMode = true;
    Get.reset();
  });

  tearDown(Get.reset);

  testWidgets('character creation offers all three creation paths',
      (tester) async {
    await tester.pumpWidget(GetMaterialApp(
      theme: VitaTheme.light,
      translations: VitaTranslations(),
      locale: const Locale('en'),
      home: const CompanionCreateMethodPage(),
    ));

    expect(find.text('Create from template'), findsOneWidget);
    expect(find.text('Create from description'), findsOneWidget);
    expect(find.text('Meet TA'), findsOneWidget);
  });
}
