import 'package:dio/dio.dart' as dio;
import 'package:vita/core/api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:vita/core/i18n/translations.dart';
import 'package:vita/core/theme.dart';
import 'package:vita/features/auth/auth_controller.dart';
import 'package:vita/features/world/world_page.dart';
import 'package:vita/features/shell/shell_page.dart';
import 'package:vita/features/chat/chat_list_controller.dart';
import 'package:vita/features/chat/message_notification_overlay.dart';

class _ChatList extends ChatListController {
  @override
  void onInit() {}
  @override
  void onClose() {}
  @override
  Future<void> load({bool silent = false}) async {}
}

void main() {
  tearDown(() => Get.reset());

  testWidgets('unread banner is visible above secondary pages', (tester) async {
    Get.testMode = true;
    final auth = Get.put(AuthController());
    auth.profile.value = {'id': 'user'};
    final list = Get.put<ChatListController>(_ChatList());
    list.currentRoute.value = '/settings';
    list.companions.assignAll([
      {
        'id': 'companion',
        'name': 'Mimi',
        'last_message': 'New message',
        'unread_count': 1
      }
    ]);
    await tester.pumpWidget(GetMaterialApp(
      theme: VitaTheme.light,
      builder: (context, child) => MessageNotificationOverlay(child: child!),
      home: const Scaffold(body: Text('Settings')),
    ));
    await tester.pump();
    expect(find.text('New message'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
    list.currentRoute.value = '/ChatPage';
    await tester.pump();
    expect(find.text('New message'), findsNothing);
    list.currentRoute.value = '/settings';
    auth.profile.value = null;
    await tester.pump();
    expect(find.text('New message'), findsNothing);
  });

  testWidgets(
      'opening world below an existing banner does not mutate during build',
      (tester) async {
    Get.testMode = true;
    Get.put(AuthController()).profile.value = {'id': 'user'};
    Get.put(ShellController());
    final list = Get.put<ChatListController>(_ChatList());
    list.companions.assignAll([
      {
        'id': 'companion',
        'name': 'Mimi',
        'last_message': 'New message',
        'unread_count': 1
      }
    ]);
    final sceneStub = dio.InterceptorsWrapper(onRequest: (options, handler) {
      handler.resolve(dio.Response(requestOptions: options, data: null));
    });
    ApiClient.instance.dio.interceptors.insert(0, sceneStub);
    addTearDown(() => ApiClient.instance.dio.interceptors.remove(sceneStub));
    final showWorld = ValueNotifier(false);
    await tester.pumpWidget(GetMaterialApp(
      theme: VitaTheme.light,
      builder: (context, child) => MessageNotificationOverlay(child: child!),
      home: ValueListenableBuilder<bool>(
        valueListenable: showWorld,
        builder: (context, visible, child) => visible
            ? const WorldPage()
            : const Scaffold(body: Text('Before world')),
      ),
    ));
    expect(find.text('New message'), findsOneWidget);
    showWorld.value = true;
    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
    showWorld.dispose();
  });

  test('card action labels exist in every locale', () {
    for (final locale in VitaTranslations().keys.values) {
      for (final key in [
        'world.cardChat',
        'world.cardGift',
        'world.cardJourney'
      ]) {
        expect(locale[key], isNotEmpty);
      }
    }
  });
}
