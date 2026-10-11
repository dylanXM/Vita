import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:vita/core/analytics_service.dart';
import 'package:vita/core/api_client.dart';
import 'package:vita/features/chat/chat_controller.dart';

class _Analytics extends AnalyticsService {
  @override
  // ignore: must_call_super
  void onInit() {}
  @override
  void track(String name,
      {String? category, Map<String, Object?> properties = const {}}) {}
}

class _Adapter implements HttpClientAdapter {
  final postStarted = Completer<void>();
  final postResponse = Completer<Object>();
  final pollStarted = Completer<void>();
  final pollResponse = Completer<Object>();
  int reads = 0;
  final message = <String, dynamic>{
    'id': 'server-1',
    'content': 'Hello',
    'sender_type': 'user',
    'created_at': '2026-01-01T00:00:00Z',
  };
  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    Object body;
    if (options.path.endsWith('/v1/conversations/')) {
      body = {'conversation_id': 'conversation-1'};
    } else if (options.path.endsWith('/reply-status')) {
      body = {'status': 'none'};
    } else if (options.method == 'POST') {
      postStarted.complete();
      body = await postResponse.future;
    } else {
      reads++;
      if (reads == 1) {
        body = [];
      } else if (reads == 2) {
        pollStarted.complete();
        body = await pollResponse.future;
      } else {
        body = [message];
      }
    }
    return ResponseBody.fromString(jsonEncode(body), 200, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    });
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  late _Adapter adapter;
  late ChatController controller;
  setUp(() async {
    Get.testMode = true;
    FlutterSecureStorage.setMockInitialValues(const {});
    Get.put<AnalyticsService>(_Analytics());
    adapter = _Adapter();
    ApiClient.instance.dio.httpClientAdapter = adapter;
    controller =
        ChatController(companionId: 'companion-1', companionName: 'Ava');
    await controller.load();
  });
  test('covered chat does not fetch or mark new messages read', () async {
    controller.isVisible = () => false;
    await controller.poll();
    expect(adapter.reads, 1);
  });

  tearDown(() {
    controller.onClose();
    Get.reset();
  });
  test('poll waits while a message POST is pending', () async {
    final send = controller.send('Hello');
    await adapter.postStarted.future;
    await controller.poll();
    expect(adapter.reads, 1);
    expect(controller.messages, hasLength(1));
    adapter.postResponse.complete({'user_message': adapter.message});
    await send;
    final poll = controller.poll();
    await adapter.pollStarted.future;
    adapter.pollResponse.complete([adapter.message]);
    await poll;
    expect(controller.messages, hasLength(1));
    expect(controller.messages.single['id'], 'server-1');
  });
  test('in-flight poll does not append a pending send server row', () async {
    final poll = controller.poll();
    await adapter.pollStarted.future;
    final send = controller.send('Hello');
    await adapter.postStarted.future;
    final reply = {
      'id': 'reply-1',
      'content': 'Hi',
      'sender_type': 'assistant',
      'source': 'reply',
      'created_at': '2025-12-31T23:59:59Z',
    };
    adapter.pollResponse.complete([reply, adapter.message]);
    await poll;
    expect(controller.messages, hasLength(1));
    expect(controller.messages.single['delivery_status'], 'sending');
    adapter.postResponse.complete({'user_message': adapter.message});
    await send;
    await controller.poll();
    expect(controller.messages, hasLength(2));
    expect(
        controller.messages.where((m) => m['id'] == 'server-1'), hasLength(1));
    expect(
        controller.messages.where((m) => m['id'] == 'reply-1'), hasLength(1));
  });
}
