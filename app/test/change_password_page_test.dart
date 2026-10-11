import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:vita/core/api_client.dart';
import 'package:vita/core/i18n/translations.dart';
import 'package:vita/core/theme.dart';
import 'package:vita/features/settings/change_password_page.dart';

class _PasswordAdapter implements HttpClientAdapter {
  Map<String, dynamic>? submitted;
  int sends = 0;
  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    if (options.method == 'PUT')
      submitted = Map<String, dynamic>.from(options.data as Map);
    if (options.method == 'POST') sends++;
    return ResponseBody.fromString('{}', 200, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType]
    });
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  late _PasswordAdapter adapter;
  setUp(() {
    Get.testMode = true;
    Get.reset();
    FlutterSecureStorage.setMockInitialValues({});
    adapter = _PasswordAdapter();
    ApiClient.instance.dio.httpClientAdapter = adapter;
  });
  tearDown(Get.reset);
  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(GetMaterialApp(
        theme: VitaTheme.light,
        translations: VitaTranslations(),
        locale: const Locale('en'),
        home: Scaffold(
            body: TextButton(
                onPressed: () => Get.to(() => const ChangePasswordPage()),
                child: const Text('Open')))));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  Future<void> fill(WidgetTester tester, String first) async {
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), first);
    await tester.enterText(fields.at(1), 'newpass123');
    await tester.enterText(fields.at(2), 'newpass123');
  }

  testWidgets('changes password using current password', (tester) async {
    await open(tester);
    await fill(tester, 'oldpass123');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Save'));
    await tester.pumpAndSettle();
    expect(adapter.submitted,
        {'current_password': 'oldpass123', 'new_password': 'newpass123'});
    expect(find.byType(ChangePasswordPage), findsNothing);
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
  });
  testWidgets('reset sends code and submits without current password',
      (tester) async {
    await open(tester);
    await tester.tap(find.text('Forgot password / set a password'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Send verification code'));
    await tester.pumpAndSettle();
    expect(adapter.sends, 1);
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    await fill(tester, '123456');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Save'));
    await tester.pumpAndSettle();
    expect(adapter.submitted, {'code': '123456', 'new_password': 'newpass123'});
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
  });
  testWidgets('invalid input does not send password request', (tester) async {
    await open(tester);
    await tester.tap(find.widgetWithText(ElevatedButton, 'Save'));
    await tester.pumpAndSettle();
    expect(adapter.submitted, isNull);
    expect(find.text('Enter your current password'), findsOneWidget);
  });
  test('password translations are complete', () {
    final locales = VitaTranslations().keys;
    expect(locales.length, 8);
    for (final locale in locales.values) {
      for (final key in [
        'title',
        'current',
        'new',
        'confirm',
        'forgot',
        'useCurrent',
        'resetInfo',
        'code',
        'send',
        'sent',
        'sendFailed',
        'wait',
        'required',
        'length',
        'mismatch',
        'codeError',
        'saved',
        'failed'
      ]) {
        expect(locale['password.$key'], isNotEmpty, reason: key);
      }
    }
  });
}
