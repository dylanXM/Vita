import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vita/core/config_sync_controller.dart';
import 'package:vita/core/settings_controller.dart';
import 'package:vita/features/auth/auth_controller.dart';

Map<String, dynamic> manifest({String billing = '1'}) => {
      'versions': {
        'content': '1',
        'billing': billing,
        'ads': '1',
        'companion': '1',
        'experiences': '1'
      },
    };

Future<void> prepareSession() async {
  Get.testMode = true;
  SharedPreferences.setMockInitialValues({'vita_locale': 'en'});
  final settings = Get.put(VitaSettingsController());
  await settings.ready.future;
  Get.put(AuthController()).profile.value = {'user_id': 'user'};
}

void main() {
  tearDown(() async {
    await Get.reset();
  });

  testWidgets(
      'merges concurrent probes, throttles entry and loads only changed groups',
      (tester) async {
    await prepareSession();
    var now = DateTime.utc(2026, 10, 13);
    var probes = 0;
    final gate = Completer<dynamic>();
    final applied = <String>[];
    final controller = Get.put(ConfigSyncController(
      clock: () => now,
      fetchVersions: () {
        probes++;
        return probes == 1 ? gate.future : Future.value(manifest(billing: '2'));
      },
      synchronizeResource: (resource, _) async {
        applied.add(resource);
        return true;
      },
    ));
    final first = controller.refresh();
    final second = controller.refresh();
    await tester.pump();
    expect(probes, 1);
    gate.complete(manifest());
    await Future.wait([first, second]);
    expect(applied.length, 5);
    await controller.refresh();
    expect(probes, 1);
    now = now.add(const Duration(seconds: 31));
    applied.clear();
    await controller.refresh();
    expect(probes, 2);
    expect(applied, ['billing']);
    controller.didChangeAppLifecycleState(AppLifecycleState.paused);
  });

  testWidgets(
      'background stops polling and foreground probes without full reload',
      (tester) async {
    await prepareSession();
    var now = DateTime.utc(2026, 10, 13);
    var probes = 0;
    var payloads = 0;
    final controller = Get.put(ConfigSyncController(
      clock: () => now,
      fetchVersions: () async {
        probes++;
        return manifest();
      },
      synchronizeResource: (_, __) async {
        payloads++;
        return true;
      },
    ));
    await controller.refresh();
    controller.didChangeAppLifecycleState(AppLifecycleState.paused);
    now = now.add(const Duration(minutes: 5));
    await tester.pump(const Duration(minutes: 5));
    expect(probes, 1);
    controller.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await tester.pump();
    await controller.refresh();
    expect(probes, 2);
    expect(payloads, 5);
    controller.didChangeAppLifecycleState(AppLifecycleState.paused);
  });

  testWidgets(
      'locale changes refresh benefits without fetching store catalog again',
      (tester) async {
    await prepareSession();
    final catalogRequests = <bool>[];
    final controller = Get.put(ConfigSyncController(
      fetchVersions: () async => manifest(),
      synchronizeResource: (resource, catalog) async {
        if (resource == 'billing') catalogRequests.add(catalog);
        return true;
      },
    ));
    await controller.refresh();
    Get.locale = const Locale('zh', 'CN');
    VitaSettingsController.to.locale.value = const Locale('zh', 'CN');
    await controller.refresh();
    expect(catalogRequests, [true, false]);
    controller.didChangeAppLifecycleState(AppLifecycleState.paused);
  });
  testWidgets(
      'offline version failures back off instead of retrying on each entry',
      (tester) async {
    await prepareSession();
    var now = DateTime.utc(2026, 10, 13);
    var probes = 0;
    final controller = Get.put(ConfigSyncController(
      clock: () => now,
      fetchVersions: () async {
        probes++;
        if (probes == 1) throw StateError('offline');
        return manifest();
      },
      synchronizeResource: (_, __) async => true,
    ));
    await controller.refresh();
    now = now.add(const Duration(seconds: 10));
    await controller.refresh(force: true);
    expect(probes, 1);
    now = now.add(const Duration(seconds: 21));
    await controller.refresh();
    expect(probes, 2);
    controller.didChangeAppLifecycleState(AppLifecycleState.paused);
  });
  testWidgets(
      'signed-out startup fetches public content once without periodic polling',
      (tester) async {
    await prepareSession();
    AuthController.to.profile.value = null;
    var probes = 0;
    final applied = <String>[];
    final controller = Get.put(ConfigSyncController(
      fetchVersions: () async {
        probes++;
        return manifest();
      },
      synchronizeResource: (resource, _) async {
        applied.add(resource);
        return true;
      },
    ));
    await controller.refresh();
    await tester.pump(const Duration(minutes: 3));
    expect(probes, 1);
    expect(applied, ['content']);
  });

  testWidgets(
      'failed page payload can retry even when the server version is unchanged',
      (tester) async {
    await prepareSession();
    var now = DateTime.utc(2026, 10, 13);
    final applied = <String>[];
    final controller = Get.put(ConfigSyncController(
      clock: () => now,
      fetchVersions: () async => manifest(),
      synchronizeResource: (resource, _) async {
        applied.add(resource);
        return true;
      },
    ));
    await controller.refresh();
    final previous = controller.revisions['experiences'];
    applied.clear();
    controller.invalidate('experiences');
    now = now.add(const Duration(seconds: 31));
    await controller.refresh();
    expect(applied, ['experiences']);
    expect(controller.revisions['experiences'], isNot(previous));
    controller.didChangeAppLifecycleState(AppLifecycleState.paused);
  });
}
