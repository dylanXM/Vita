import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vita/core/settings_controller.dart';
import 'package:vita/features/ai_pets/ai_pet_desktop_controller.dart';
import 'package:vita/features/ai_pets/ai_pet_desktop_overlay.dart';
import 'package:vita/features/auth/auth_controller.dart';

void main() {
  testWidgets('floating adopted pet stays above arbitrary app content',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    addTearDown(Get.reset);
    final settings = Get.put(VitaSettingsController());
    await settings.ready.future;
    Get.put(AuthController());
    final desktop = Get.put(AIPetDesktopController());
    desktop.pet.value = {
      'adopted_companion_id': 'pet-1',
      'adopted_companion_name': 'Mochi',
      'avatar_url': '',
      'species': 'Cat',
    };

    await tester.pumpWidget(GetMaterialApp(
      builder: (context, child) =>
          AIPetDesktopOverlay(child: child ?? const SizedBox.shrink()),
      home: const Scaffold(body: Text('Any page')),
    ));
    await tester.pump();

    expect(find.text('Any page'), findsOneWidget);
    expect(find.bySemanticsLabel('Mochi'), findsOneWidget);
    await tester.drag(find.bySemanticsLabel('Mochi'), const Offset(-40, -60));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
