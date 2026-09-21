import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:vita/core/analytics_service.dart';
import 'package:vita/core/i18n/translations.dart';
import 'package:vita/core/theme.dart';
import 'package:vita/features/memories/memories_page.dart';

class _FakeAnalyticsService extends AnalyticsService {
  @override
  // Intentionally skip the production timer and persistence wiring in tests.
  // ignore: must_call_super
  void onInit() {}

  @override
  void track(
    String name, {
    String? category,
    Map<String, Object?> properties = const {},
  }) {}
}

class _FakeMemoriesController extends MemoriesController {
  @override
  // Test data is injected below, so no real API request should start here.
  // ignore: must_call_super
  void onInit() {}

  @override
  Future<void> loadMemories(String companionId) async {
    activeCompanionId.value = companionId;
    memories.assignAll([
      {
        'id': 'memory-1',
        'type': 'shared',
        'content': 'The day we met',
        'created_at': '2026-09-20T10:00:00Z',
      },
    ]);
  }
}

void main() {
  setUp(() {
    Get.testMode = true;
    Get.reset();
  });

  tearDown(Get.reset);

  testWidgets('memory contact opens that companion memory detail',
      (tester) async {
    final controller = _FakeMemoriesController();
    controller.companions.assignAll([
      {
        'id': 'companion-1',
        'name': 'Ava',
        'city': 'Tokyo',
        'occupation': 'Designer',
      },
    ]);
    Get.put<AnalyticsService>(_FakeAnalyticsService());
    Get.put<MemoriesController>(controller);

    await tester.pumpWidget(
      GetMaterialApp(
        theme: VitaTheme.light,
        translations: VitaTranslations(),
        locale: const Locale('en'),
        home: const MemoriesPage(),
      ),
    );

    expect(find.text('Tokyo · Designer'), findsOneWidget);
    await tester.tap(find.text('Ava'));
    await tester.pumpAndSettle();

    expect(find.text('The day we met'), findsOneWidget);
    expect(find.text('Moments you keep together'), findsOneWidget);
  });
}
