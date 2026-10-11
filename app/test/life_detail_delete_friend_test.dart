import 'package:dio/dio.dart' as dio;
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:vita/core/api_client.dart';
import 'package:vita/core/i18n/translations.dart';
import 'package:vita/core/theme.dart';
import 'package:vita/features/chat/chat_list_controller.dart';
import 'package:vita/features/life/life_detail_page.dart';

class _Contacts extends ChatListController {
  int reloads = 0;
  @override
  void onInit() {}
  @override
  void onClose() {}
  @override
  Future<void> load({bool silent = false}) async => reloads++;
}

void main() {
  late dio.Interceptor stub;
  late List<String> deletions;
  late _Contacts contacts;

  setUp(() {
    Get.testMode = true;
    FlutterSecureStorage.setMockInitialValues({});
    contacts = Get.put<ChatListController>(_Contacts()) as _Contacts;
    deletions = [];
    stub = dio.InterceptorsWrapper(onRequest: (options, handler) {
      if (options.method == 'DELETE') deletions.add(options.path);
      handler.resolve(dio.Response(
        requestOptions: options,
        statusCode: 200,
        data: options.path.endsWith('/experiences')
            ? {'products': []}
            : <String, dynamic>{},
      ));
    });
    ApiClient.instance.dio.interceptors.insert(0, stub);
  });

  tearDown(() {
    ApiClient.instance.dio.interceptors.remove(stub);
    Get.reset();
  });

  Future<void> openDetail(WidgetTester tester, {bool isDefault = false}) async {
    await tester.binding.setSurfaceSize(const Size(390, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(GetMaterialApp(
      theme: VitaTheme.light,
      translations: VitaTranslations(),
      locale: const Locale('en'),
      home: Scaffold(body: Builder(builder: (context) {
        return TextButton(
          onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (_) => LifeDetailPage(companion: {
              'id': 'friend-1',
              'name': 'Ava',
              'is_default': isDefault,
            }),
          )),
          child: const Text('Open detail'),
        );
      })),
    ));
    await tester.tap(find.text('Open detail'));
    await tester.pumpAndSettle();
  }

  testWidgets('canceling friend deletion does not call the API',
      (tester) async {
    await openDetail(tester);
    await tester.ensureVisible(find.byType(OutlinedButton));
    await tester.tap(find.byType(OutlinedButton));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(deletions, isEmpty);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(deletions, isEmpty);
    expect(find.byType(LifeDetailPage), findsOneWidget);
  });

  testWidgets('confirmed deletion refreshes contacts and leaves the detail',
      (tester) async {
    await openDetail(tester);
    await tester.ensureVisible(find.byType(OutlinedButton));
    await tester.tap(find.byType(OutlinedButton));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find
        .descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Delete friend'),
        )
        .last);
    await tester.pumpAndSettle();
    expect(deletions, ['/v1/companions/friend-1']);
    expect(contacts.reloads, 1);
    expect(find.byType(LifeDetailPage), findsNothing);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });

  testWidgets('default companions have no delete action', (tester) async {
    await openDetail(tester, isDefault: true);
    expect(find.byType(OutlinedButton), findsNothing);
    expect(deletions, isEmpty);
  });
}
