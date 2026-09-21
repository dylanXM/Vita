import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:vita/core/i18n/translations.dart';
import 'package:vita/core/theme.dart';
import 'package:vita/features/life/life_detail_page.dart';

void main() {
  setUp(() {
    Get.testMode = true;
    Get.reset();
  });

  tearDown(Get.reset);

  testWidgets('contact detail shows profile, personality and life sections',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      GetMaterialApp(
        theme: VitaTheme.light,
        translations: VitaTranslations(),
        locale: const Locale('en'),
        home: const LifeDetailPage(
          companion: {
            'id': 'companion-1',
            'name': 'Ava',
            'city': 'Tokyo',
            'occupation': 'Designer',
            'persona': 'Warm and independent.',
            'interests': 'Coffee, travel',
            'life_goal': 'Open a studio',
            'personality_tags': ['tag.warm', 'tag.independent'],
          },
        ),
      ),
    );

    expect(find.text('Contact details'), findsOneWidget);
    expect(find.text('Ava'), findsOneWidget);
    expect(find.text('Tokyo · Designer'), findsOneWidget);
    expect(find.text('Profile'), findsOneWidget);
    expect(find.text('Personality'), findsOneWidget);
    expect(find.text('Life'), findsOneWidget);
    expect(find.text('Open a studio'), findsOneWidget);
    expect(find.text('Warm'), findsOneWidget);
  });
}
