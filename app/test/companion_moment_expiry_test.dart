import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:vita/core/api_client.dart';
import 'package:vita/core/analytics_service.dart';
import 'package:vita/core/i18n/translations.dart';
import 'package:vita/core/theme.dart';
import 'package:vita/features/chat/companion_moment_page.dart';

class _QuietAnalytics extends AnalyticsService {
  @override
  void onInit() {}
  @override
  void track(String name, {String? category, Map<String, Object?> properties = const {}}) {}
}

class _ExpiredAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream,
      Future<void>? cancelFuture) async {
    final now = DateTime.now().toUtc();
    final data = options.path.contains('/moments/') ? {
      'starts_at': now.subtract(const Duration(hours: 2)).toIso8601String(),
      'ends_at': now.subtract(const Duration(hours: 1)).toIso8601String(),
      'opening': '', 'title_key': 'Coffee',
    } : <String, dynamic>{};
    return ResponseBody.fromString(jsonEncode(data), 200,
      headers: {Headers.contentTypeHeader: [Headers.jsonContentType]});
  }
  @override
  void close({bool force = false}) {}
}

void main() {
  tearDown(Get.reset);
  testWidgets('unopened expired date hides entry and displays ended state', (tester) async {
    Get.testMode = true;
    Get.put<AnalyticsService>(_QuietAnalytics());
    FlutterSecureStorage.setMockInitialValues({});
    ApiClient.instance.dio.httpClientAdapter = _ExpiredAdapter();
    await tester.pumpWidget(GetMaterialApp(theme: VitaTheme.light,
      translations: VitaTranslations(), locale: const Locale('en'),
      home: const CompanionMomentPage(companionId: 'one', eventId: 'expired', name: 'Emma')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('This moment has ended'), findsWidgets);
    expect(find.text('world.appointment.enter'.tr), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 100));
  });
  test('deadline guidance exists in all eight locales', () {
    final locales = VitaTranslations().keys;
    expect(locales.length, 8);
    for (final locale in locales.entries) {
      expect(locale.value['moment.readyHint'], isNotEmpty, reason: locale.key);
      expect(locale.value['moment.ended'], isNotEmpty, reason: locale.key);
    }
  });
}
