import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:vita/core/analytics_service.dart';
import 'package:vita/core/api_client.dart';
import 'package:vita/core/i18n/translations.dart';
import 'package:vita/core/theme.dart';
import 'package:vita/features/chat/chat_page.dart';

/// Fails every request, which is exactly the state the chat must survive: no
/// conversation can be created and nothing can be sent.
class _FailingAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return ResponseBody.fromString(
      '{"error":"offline"}',
      503,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

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

void main() {
  setUp(() {
    Get.testMode = true;
    Get.reset();
    FlutterSecureStorage.setMockInitialValues(const {});
    ApiClient.instance.dio.httpClientAdapter = _FailingAdapter();
  });

  tearDown(Get.reset);

  testWidgets('send stays enabled and keeps the draft when the conversation '
      'cannot be created', (tester) async {
    Get.put<AnalyticsService>(_FakeAnalyticsService());

    await tester.pumpWidget(
      GetMaterialApp(
        theme: VitaTheme.light,
        translations: VitaTranslations(),
        locale: const Locale('en'),
        home: const ChatPage(companionId: 'companion-1', name: 'Ava'),
      ),
    );
    await tester.pumpAndSettle();

    // The conversation request failed, so the controller has no conversation
    // id — the send button still has to be tappable.
    final send = find.widgetWithText(ElevatedButton, 'Send');
    expect(tester.widget<ElevatedButton>(send).onPressed, isNotNull);

    await tester.enterText(find.byType(TextField), 'Hello there');
    await tester.tap(send);
    await tester.pumpAndSettle();

    // The send failed, the user is told about it and the draft is not lost.
    expect(find.text('Message not sent'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller?.text,
      'Hello there',
    );

    // Let the snackbar auto-dismiss, otherwise its timer is still pending when
    // the widget tree is torn down.
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
  });
}
