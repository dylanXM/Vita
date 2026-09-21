import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:vita/core/i18n/translations.dart';
import 'package:vita/core/theme.dart';
import 'package:vita/features/chat/chat_info_page.dart';

void main() {
  setUp(() {
    Get.testMode = true;
    Get.reset();
  });

  tearDown(Get.reset);

  testWidgets('chat info lists the supported companion actions',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      GetMaterialApp(
        theme: VitaTheme.light,
        translations: VitaTranslations(),
        locale: const Locale('en'),
        home: ChatInfoPage(
          companion: const {
            'id': 'companion-1',
            'name': 'Ava',
            'city': 'Tokyo',
            'occupation': 'Designer',
            'is_default': false,
          },
          onExperienceCompleted: _done,
        ),
      ),
    );

    expect(find.text('Chat info'), findsOneWidget);
    expect(find.text('Ava'), findsOneWidget);
    expect(find.text('Shared experiences'), findsOneWidget);
    expect(find.text('Memories'), findsOneWidget);
    expect(find.text('Companion life'), findsOneWidget);
    expect(find.text('Photos & voice'), findsOneWidget);
    expect(find.text('Delete companion'), findsOneWidget);
  });

  testWidgets('system default companion cannot be deleted', (tester) async {
    await tester.pumpWidget(
      GetMaterialApp(
        theme: VitaTheme.light,
        translations: VitaTranslations(),
        locale: const Locale('en'),
        home: ChatInfoPage(
          companion: const {
            'id': 'default-1',
            'name': 'Mia',
            'is_default': true,
          },
          onExperienceCompleted: _done,
        ),
      ),
    );

    expect(find.text('Delete companion'), findsNothing);
  });
}

Future<void> _done() async {}
