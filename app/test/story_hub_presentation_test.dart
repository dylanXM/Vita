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
      'image_url': '',
      'panel_count': 4,
      'panels': [
        {
          'title': 'Departure',
          'dialogue': 'Let us go.',
        },
        {'title': 'Crossing', 'dialogue': ''},
        {'title': 'Discovery', 'dialogue': ''},
        {'title': 'Return', 'dialogue': ''},
      ],
    })));

    expect(find.text('Share to another app'), findsOneWidget);
    expect(find.text('A shared journey.'), findsOneWidget);
    expect(find.byType(AspectRatio), findsOneWidget);
  });

  testWidgets('user chooses 4, 6, 8, or 9 panels before generation',
      (tester) async {
    await tester.pumpWidget(app(const StoryDetailPage(initial: {
      'id': 'story-1',
      'title': 'Moonlit Train',
      'storyboard_unlocked': true,
      'can_continue': true,
      'chapters': [
        {
          'title': 'Chapter 8',
          'content': 'The train reaches the final station.',
          'selected_choice_id': '',
          'choices': [],
        },
      ],
      'storyboards': [],
    })));

    await tester.tap(find.text('Generate storyboard'));
    await tester.pumpAndSettle();

    expect(find.text('Choose storyboard layout'), findsOneWidget);
    for (final count in [4, 6, 8, 9]) {
      expect(find.text('$count panels'), findsOneWidget);
    }
  });
}
