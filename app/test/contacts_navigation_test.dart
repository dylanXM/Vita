import 'package:dio/dio.dart' as dio;
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:vita/core/api_client.dart';
import 'package:vita/core/analytics_service.dart';
import 'package:vita/core/i18n/translations.dart';
import 'package:vita/core/theme.dart';
import 'package:vita/features/chat/chat_list_controller.dart';
import 'package:vita/features/chat/chat_list_page.dart';
import 'package:vita/features/chat/chat_page.dart';
import 'package:vita/features/memories/memories_page.dart';
import 'package:vita/features/life/life_detail_page.dart';
import 'package:vita/features/shell/shell_page.dart';

class _Analytics extends AnalyticsService {
  @override
  void onInit() {}
  @override
  void track(String name,
      {String? category, Map<String, Object?> properties = const {}}) {}
}

class _Contacts extends ChatListController {
  @override
  void onInit() {}
  @override
  void onClose() {}
  @override
  Future<void> load({bool silent = false}) async {}
}

class _Memories extends MemoriesController {
  String? loadedId;
  @override
  Future<void> loadCompanions() async {}
  @override
  Future<void> loadJourney({String? companionId, String query = ''}) async {
    loadedId = companionId;
    journey.assignAll([
      {
        'id': 'memory',
        'type': 'memory',
        'content': 'Our memory',
        'event_time': '2026-10-11T08:00:00Z',
        'companion': {'id': companionId, 'name': 'Mimi'}
      }
    ]);
  }
}

void main() {
  setUp(() {
    Get.testMode = true;
    FlutterSecureStorage.setMockInitialValues(const {});
    Get.put<AnalyticsService>(_Analytics());
    Get.put(ShellController());
  });
  tearDown(() => Get.reset());
  Widget host(Widget page) => GetMaterialApp(
      theme: VitaTheme.light,
      translations: VitaTranslations(),
      locale: const Locale('en'),
      home: page);

  testWidgets('contacts show message and unread count and open chat',
      (tester) async {
    final contacts = Get.put<ChatListController>(_Contacts());
    contacts.companions.assignAll([
      {
        'id': 'mimi',
        'name': 'Mimi',
        'last_message': 'Hello 🌸',
        'unread_count': 2
      }
    ]);
    final stub = dio.InterceptorsWrapper(
        onRequest: (options, handler) => handler.resolve(dio.Response(
            requestOptions: options,
            statusCode: 503,
            data: {'error': 'offline'})));
    ApiClient.instance.dio.interceptors.insert(0, stub);
    addTearDown(() => ApiClient.instance.dio.interceptors.remove(stub));
    await tester.pumpWidget(host(const ChatListPage()));
    expect(find.text('Contacts'), findsOneWidget);
    expect(find.text('Hello 🌸'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    await tester.tap(find.text('Mimi'));
    await tester.pumpAndSettle();
    expect(find.byType(ChatPage), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('companion detail opens a scoped journey without switching tabs',
      (tester) async {
    final memories = Get.put<MemoriesController>(_Memories());
    await tester.pumpWidget(
        host(const LifeDetailPage(companion: {'id': 'mimi', 'name': 'Mimi'})));
    await tester.tap(find.text('View moments'));
    await tester.pumpAndSettle();
    expect(find.byType(MemoriesPage), findsOneWidget);
    expect((memories as _Memories).loadedId, 'mimi');
    expect(ShellController.to.index.value, 0);
    expect(find.text('Our memory'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  test('contacts label exists in every locale', () {
    for (final entries in VitaTranslations().keys.values) {
      expect(entries['tab.contacts'], isNotEmpty);
    }
  });
}
