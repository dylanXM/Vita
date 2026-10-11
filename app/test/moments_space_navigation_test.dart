import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:vita/core/api_client.dart';
import 'package:vita/core/i18n/translations.dart';
import 'package:vita/core/theme.dart';
import 'package:vita/features/explore/explore_page.dart';
import 'package:vita/features/life/life_detail_page.dart';

class _ExploreController extends ExploreController {
  @override
  void onInit() {}
}

class _EmptyAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    return ResponseBody.fromString('{}', 200, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType]
    });
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  tearDown(Get.reset);

  testWidgets('moment space action opens author detail and returns to universe',
      (tester) async {
    Get.testMode = true;
    Get.reset();
    FlutterSecureStorage.setMockInitialValues({});
    ApiClient.instance.dio.httpClientAdapter = _EmptyAdapter();
    final controller = Get.put<ExploreController>(_ExploreController());
    const author = {'id': 'companion-1', 'name': 'Mimi', 'city': 'Tokyo'};
    controller.posts.add({
      'author': author,
      'content': 'A quiet afternoon',
      'published_at': '2026-09-30T08:00:00Z',
      'is_own_companion': true,
    });
    await tester.pumpWidget(GetMaterialApp(
      theme: VitaTheme.light,
      translations: VitaTranslations(),
      locale: const Locale('en'),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: true),
        child: child!,
      ),
      home: const MomentsPage(),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mimi'));
    await tester.pumpAndSettle();
    expect(find.text('Go to their space'), findsOneWidget);
    expect(find.text('Talk together'), findsOneWidget);
    await tester.tap(find.text('Go to their space'));
    await tester.pumpAndSettle();
    expect(tester.widget<LifeDetailPage>(find.byType(LifeDetailPage)).companion,
        author);
    Get.back();
    await tester.pumpAndSettle();
    expect(find.byType(MomentsPage), findsOneWidget);
    expect(find.text('Go to their space'), findsNothing);
  });

  test('space action is translated in every supported locale', () {
    final locales = VitaTranslations().keys;
    expect(locales.length, 8);
    for (final locale in locales.entries) {
      expect(locale.value['explore.openSpace'], isNotEmpty, reason: locale.key);
    }
  });
}
