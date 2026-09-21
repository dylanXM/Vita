import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:vita/core/i18n/translations.dart';
import 'package:vita/core/theme.dart';
import 'package:vita/features/stories/stories_page.dart';

void main() {
  setUp(() {
    Get.testMode = true;
    Get.reset();
  });

  tearDown(Get.reset);

  Widget app(Widget home) => GetMaterialApp(
        theme: VitaTheme.light,
        translations: VitaTranslations(),
        locale: const Locale('en'),
        home: home,
      );

  testWidgets('story hub exposes backgrounds and finite custom quota',
      (tester) async {
    final controller = StoriesController();
    controller.catalog.assignAll({
      'subscribed': true,
      'custom_backgrounds_remaining': 2,
      'backgrounds': [
        {
          'id': 'moon',
          'title': 'Moonlit Train',
          'synopsis': 'A train that appears only under a full moon.',
          'cover_url': '',
          'custom': false,
        },
      ],
    });

    await tester.pumpWidget(app(StoriesPage(controller: controller)));

    expect(find.text('Story Hub'), findsOneWidget);
    expect(find.text('Moonlit Train'), findsOneWidget);
    expect(find.text('2 custom backgrounds remaining'), findsOneWidget);
  });

  testWidgets('storyboard offers external system sharing', (tester) async {
    await tester.pumpWidget(app(const StoryboardPage(board: {
      'summary': 'A shared journey.',
      'panels': [
        {
          'title': 'Departure',
          'dialogue': 'Let us go.',
          'image_url': '',
        },
      ],
    })));

    expect(find.text('Share to another app'), findsOneWidget);
    expect(find.text('A shared journey.'), findsOneWidget);
  });
}
