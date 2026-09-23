import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../ai_pet_avatar.dart';
import 'pet_motion_spec.dart';
import 'pet_state_machine.dart';

/// 宠物本体渲染：由状态机 + 世界时钟驱动姿态变换。
/// 纯表现层，不感知 AI 来源。
class PetRenderer extends StatelessWidget {
  const PetRenderer({
    super.key,
    required this.name,
    required this.imageUrl,
    required this.machine,
    required this.worldTime,
  });

  final String name;
  final String imageUrl;
  final PetStateMachine machine;
  final double worldTime;

  double _blinkAmount(double progress) {
    if (progress < .86 || progress > .96) return 0;
    if (progress < .91) return (progress - .86) / .05;
    return 1 - ((progress - .91) / .05);
  }

  @override
  Widget build(BuildContext context) {
    final state = machine.state;
    final spec = PetMotionSpec.table[state]!;
    final cycle = machine.controller.value;
    // 呼吸：约 2.2 秒一个周期（世界时钟 60 秒循环 × 27 ≈ 2.22 秒）。
    final idle = math.sin(worldTime * math.pi * 2 * 27);
    final actionWave = math.sin(cycle * math.pi);
    final repeatingWave = math.sin(cycle * math.pi * 2);
    // 眨眼：约 4.2 秒一个周期（60 / 14.28 ≈ 4.2 秒）。
    final blink = state == PetState.sleeping
        ? 1.0
        : state == PetState.feeding
            ? 0.0
            : _blinkAmount((worldTime * 14.28) % 1.0);
    final hasBlinkFrame = aiPetClosedEyeAssetPath(imageUrl) != null;

    var dy = idle * spec.driftY;
    var dx = 0.0;
    var scale = 1.0;
    var scaleY = 1.0 - (hasBlinkFrame ? 0 : blink * .09);
    var angle = 0.0;
    var faceLeft = false;
    switch (state) {
      case PetState.walking:
        final travel = .5 - .5 * math.cos(cycle * math.pi * 2);
        dx = -spec.driftX + travel * (2 * spec.driftX);
        dy = -repeatingWave.abs() * spec.driftY;
        angle = repeatingWave * spec.sway;
        scaleY -= repeatingWave.abs() * spec.squash;
        faceLeft = cycle >= .5;
        break;
      case PetState.happy:
        dy -= actionWave.abs() * spec.bounce;
        scale += actionWave * spec.scale;
        break;
      case PetState.feeding:
        dy += spec.driftY + repeatingWave.abs() * 12;
        angle = -spec.sway + repeatingWave * .018;
        scaleY = .94 - repeatingWave.abs() * spec.squash;
        break;
      case PetState.sleeping:
        dy = 27 + idle * spec.driftY;
        scale = spec.scale + idle * .008;
        scaleY = .84 + idle * .012;
        angle = -spec.sway + idle * .008;
        break;
      case PetState.levelUp:
        dy -= actionWave.abs() * spec.bounce;
        scale += actionWave.abs() * spec.scale;
        break;
      case PetState.thinking:
        dy = -10 + idle * spec.driftY;
        angle = idle * spec.sway;
        scaleY = .96 + idle * .02;
        break;
      case PetState.sick:
        dy = 10 + idle * spec.driftY;
        angle = idle * spec.sway;
        scaleY = .9 - idle.abs() * spec.squash;
        break;
      case PetState.idle:
        break;
    }
    return Transform.translate(
      offset: Offset(dx, dy),
      child: Transform.rotate(
        angle: angle,
        child: Transform.scale(
          scaleX: (faceLeft ? -1.0 : 1.0) * scale,
          scaleY: scale * scaleY,
          alignment: const Alignment(0, .55),
          child: Align(
            alignment: const Alignment(0, .35),
            child: SizedBox(
              width: 245,
              height: 245,
              child: AIPetAvatar(
                name: name,
                imageUrl: imageUrl,
                blinkAmount: blink,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
