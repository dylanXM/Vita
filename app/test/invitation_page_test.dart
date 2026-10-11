import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:vita/core/api_client.dart';
import 'package:vita/core/i18n/translations.dart';
import 'package:vita/core/theme.dart';
import 'package:vita/features/auth/auth_controller.dart';
import 'package:vita/features/me/invitation_page.dart';

class _InvitationAdapter implements HttpClientAdapter {
  _InvitationAdapter({this.bound = ''});
  String bound;
  Map<String, dynamic>? binding;

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    if (options.method == 'POST') {
      binding = Map<String, dynamic>.from(options.data as Map);
      bound = binding!['invite_code'] as String;
    }
    return ResponseBody.fromString(
        jsonEncode({
          'invite_code': 'MYCODE1234',
          'bound_invite_code': bound,
          'invitation_reward_percent': 12.5,
        }),
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType]
        });
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  setUp(() {
    Get.testMode = true;
    Get.reset();
    FlutterSecureStorage.setMockInitialValues({});
    Get.put(AuthController());
  });
  tearDown(Get.reset);

  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(GetMaterialApp(
      theme: VitaTheme.light,
      translations: VitaTranslations(),
      locale: const Locale('en'),
      home: const InvitationPage(),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('shows own and bound codes and backend reward rate',
      (tester) async {
    ApiClient.instance.dio.httpClientAdapter =
        _InvitationAdapter(bound: 'OTHER12345');
    await open(tester);
    expect(find.text('MYCODE1234'), findsOneWidget);
    expect(find.text('OTHER12345'), findsOneWidget);
    expect(find.textContaining('12.5%'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('binds once and updates displayed and cached profile',
      (tester) async {
    final adapter = _InvitationAdapter();
    ApiClient.instance.dio.httpClientAdapter = adapter;
    await open(tester);
    final button = find.widgetWithText(FilledButton, 'Bind invitation code');
    expect(tester.widget<FilledButton>(button).onPressed, isNull);
    await tester.enterText(find.byType(TextField), '  other12345  ');
    await tester.pump();
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(adapter.binding, {'invite_code': 'OTHER12345'});
    expect(find.text('OTHER12345'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(AuthController.to.profile.value?['bound_invite_code'], 'OTHER12345');
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
  });

  test('all invitation texts exist in eight locales', () {
    final locales = VitaTranslations().keys;
    expect(locales.length, 8);
    for (final locale in locales.entries) {
      for (final key in [
        'me.subscriptionSection',
        'invitation.title',
        'invitation.boundCode',
        'invitation.notBound',
        'invitation.enterCode',
        'invitation.bind',
        'invitation.once',
        'invitation.rewardInfo',
        'invitation.boundSuccess',
        'invitation.bindFailed',
        'invitation.copy'
      ]) {
        expect(locale.value[key], isNotEmpty, reason: '${locale.key}: $key');
      }
      expect(locale.value['invitation.rewardInfo'], contains('@percent'));
    }
  });
}
