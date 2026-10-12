import 'dart:convert';
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
import 'package:vita/features/companion/companion_create_page.dart';
import 'package:vita/features/companion/companion_relation_rules.dart';

class _OptionsAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(RequestOptions options,
          Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async =>
      ResponseBody.fromString(
          jsonEncode({
            'personality_tags': [],
            'portraits': [],
            'relationships': [
              {
                'key': 'custom',
                'stages': ['stranger', 'acquaintance', 'close', 'partner'],
                'default_stage': 'stranger'
              },
              {
                'key': 'wife',
                'gender_hint': 'female',
                'paired_role': 'husband',
                'stages': ['partner'],
                'default_stage': 'partner'
              },
              {
                'key': 'family',
                'stages': ['acquaintance', 'close'],
                'default_stage': 'close'
              },
            ],
          }),
          200,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType]
          });
  @override
  void close({bool force = false}) {}
}

class _QuietAnalytics extends AnalyticsService {
  @override
  void onInit() {}
  @override
  void onClose() {}
  @override
  void track(String name,
      {String? category, Map<String, Object?> properties = const {}}) {}
}

void main() {
  testWidgets(
      'creation retains initial relationship choice and restricts closeness by backend type',
      (tester) async {
    Get.testMode = true;
    Get.reset();
    addTearDown(Get.reset);
    FlutterSecureStorage.setMockInitialValues({});
    Get.put<AnalyticsService>(_QuietAnalytics());
    ApiClient.instance.dio.httpClientAdapter = _OptionsAdapter();
    await tester.binding.setSurfaceSize(const Size(900, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(GetMaterialApp(
        theme: VitaTheme.light,
        translations: VitaTranslations(),
        locale: const Locale('en'),
        home: const CompanionCreatePage()));
    await tester.pumpAndSettle();
    expect(find.text('Wife'), findsOneWidget);
    await tester.ensureVisible(find.text('Wife'));
    await tester.tap(find.text('Wife'));
    await tester.pumpAndSettle();
    expect(find.text('Partner'), findsOneWidget);
    expect(find.text('Stranger'), findsNothing);
    await tester.tap(find.text('Family'));
    await tester.pumpAndSettle();
    expect(find.text('Partner'), findsNothing);
    expect(find.text('Close'), findsOneWidget);
  });
  test('creation presents backend relationship stages and gender eligibility',
      () {
    final options = CompanionRelationshipOptions.from([
      {
        'key': 'wife',
        'gender_hint': 'female',
        'paired_role': 'husband',
        'stages': ['partner'],
        'default_stage': 'partner'
      },
      {
        'key': 'husband',
        'gender_hint': 'male',
        'paired_role': 'wife',
        'stages': ['partner'],
        'default_stage': 'partner'
      },
      {
        'key': 'mentor',
        'gender_hint': '',
        'stages': ['stranger', 'acquaintance', 'close'],
        'default_stage': 'acquaintance'
      },
    ]);
    expect(options.rolesForGender('male'), ['husband', 'mentor']);
    expect(options.rolesForGender('female'), ['wife', 'mentor']);
    expect(options.compatibleRole('wife', 'male'), 'husband');
    expect(
        options.stagesForRole('mentor'), ['stranger', 'acquaintance', 'close']);
    expect(options.compatibleStage('partner', 'mentor'), 'acquaintance');
    expect(options.compatibleStage('close', 'mentor'), 'close');
  });

  test('malformed relationship catalogs do not create invalid choices', () {
    expect(CompanionRelationshipOptions.from(null).roles, isEmpty);
    expect(
        CompanionRelationshipOptions.from([
          {
            'key': 'broken',
            'stages': ['close'],
            'default_stage': 'partner'
          },
        ]).roles,
        isEmpty);
  });

  test('all eight languages include every new relationship and retry label',
      () {
    final translations = VitaTranslations().keys;
    for (final locale in translations.entries) {
      for (final key in [
        'relation.wife',
        'relation.husband',
        'relation.crush',
        'relation.confidant',
        'relation.family',
        'relation.mentor',
        'relation.colleague',
        'companion.create.optionsUnavailable',
        'companion.create.retryOptions',
      ]) {
        expect(locale.value[key], isNotEmpty, reason: '${locale.key}: $key');
      }
    }
  });
}
