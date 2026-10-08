import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vita/features/ai_pets/animation/pet/mesh_bone_pet.dart';
import 'package:vita/features/ai_pets/animation/pet/pet_motion_spec.dart';
import 'package:vita/features/ai_pets/animation/pet/pet_state_machine.dart';

/// 网格骨骼动画渲染预览：对每个生活状态逐帧截图（真实 Flutter 渲染）。
/// 运行：flutter test test/mesh_bone_preview_test.dart
void main() {
  testWidgets('mesh bone pet render preview', (tester) async {
    final machine = PetStateMachine(vsync: const TestVSync());
    final outDir = Directory('/tmp/mesh_shots');
    outDir.createSync(recursive: true);

    Widget build() => RepaintBoundary(
          key: const ValueKey('mesh'),
          child: SizedBox(
            width: 400,
            height: 400,
            child: MeshBonePet(
              imageProvider:
                  const AssetImage('assets/ai_pets/cat_orange.png'),
              closedEyeProvider:
                  const AssetImage('assets/ai_pets/cat_orange_blink.png'),
              machine: machine,
              worldTime: 0.35,
            ),
          ),
        );

    await tester.pumpWidget(MaterialApp(home: Center(child: build())));
    // 等待图片异步加载。
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }

    Future<void> shot(String name) async {
      final boundary = tester.renderObject(
          find.byKey(const ValueKey('mesh'))) as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 1);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      File('$outDir/$name.png')
          .writeAsBytesSync(bytes!.buffer.asUint8List());
    }

    // 1. 站起（默认）。
    await shot('1-standing');

    // 2. 坐下：先拍过渡中间帧（blend 进行中），再拍稳定帧。
    machine.transition(PetState.sitting);
    await tester.pump(const Duration(milliseconds: 110));
    await shot('2-sitting-mid-blend');
    await tester.pump(const Duration(milliseconds: 260));
    await shot('3-sitting');

    // 3. 散步。
    machine.transition(PetState.walking);
    await tester.pump(const Duration(milliseconds: 420));
    await shot('4-walking');

    // 4. 睡觉。
    machine.transition(PetState.sleeping);
    await tester.pump(const Duration(milliseconds: 420));
    await shot('5-sleeping');

    // 5. 困。
    machine.transition(PetState.tired);
    await tester.pump(const Duration(milliseconds: 420));
    await shot('6-tired');

    // 6. 饿。
    machine.transition(PetState.hungry);
    await tester.pump(const Duration(milliseconds: 420));
    await shot('7-hungry');

    // 7. 回到站起：拍一次过渡中间帧，证明切换连贯。
    machine.transition(PetState.standing);
    await tester.pump(const Duration(milliseconds: 160));
    await shot('8-return-mid-blend');
    await tester.pump(const Duration(milliseconds: 300));
    await shot('9-return-standing');

    expect(outDir.listSync().length, greaterThan(0));
  });
}
