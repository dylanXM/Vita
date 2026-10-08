import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../ai_pet_avatar.dart';
import 'pet_motion_spec.dart';
import 'pet_state_machine.dart';

/// 一帧的姿态描述：位移 / 缩放 / 旋转 / 朝向 / 眨眼。
/// 状态切换时渲染层对「旧姿态 → 新姿态」做线性插值，保证视觉连贯。
class PetPose {
  const PetPose({
    this.dx = 0,
    this.dy = 0,
    this.scaleX = 1,
    this.scaleY = 1,
    this.angle = 0,
    this.blink = 0,
  });

  final double dx;
  final double dy;

  /// 水平缩放（含朝向：负值 = 朝左）。
  final double scaleX;
  final double scaleY;
  final double angle;
  final double blink;

  PetPose lerp(PetPose other, double t) => PetPose(
        dx: dx + (other.dx - dx) * t,
        dy: dy + (other.dy - dy) * t,
        scaleX: scaleX + (other.scaleX - scaleX) * t,
        scaleY: scaleY + (other.scaleY - scaleY) * t,
        angle: angle + (other.angle - angle) * t,
        blink: blink + (other.blink - blink) * t,
      );
}

/// 宠物本体渲染：由状态机 + 世界时钟驱动姿态变换，切换时平滑混合。
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

  /// 计算某个状态在当前相位下的姿态。
  PetPose _poseFor(
    PetState state,
    double cycle,
    double worldTime,
    bool hasBlinkFrame,
  ) {
    final spec = PetMotionSpec.table[state]!;
    // 呼吸：约 2.6 秒一个周期（世界时钟 60 秒循环 × 23 ≈ 2.6 秒）。
    final idle = math.sin(worldTime * math.pi * 2 * 23);
    final actionWave = math.sin(cycle * math.pi);
    final repeatingWave = math.sin(cycle * math.pi * 2);
    final blink = state == PetState.sleeping
        ? 1.0
        : state == PetState.feeding
            ? 0.0
            : _blinkAmount((worldTime * 14.28) % 1.0);

    var dx = 0.0;
    var dy = idle * spec.driftY;
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
      case PetState.sitting:
        // 坐下：身体下沉、略微压扁、轻摇尾巴。
        dy = 26 + idle * 4;
        scale = .88;
        scaleY = .9 + idle * .015;
        angle = idle * spec.sway;
        break;
      case PetState.tired:
        // 困：耷拉下来，缓慢晃动。
        dy = 16 + idle * spec.driftY;
        scale = .94;
        scaleY = .92 - idle.abs() * spec.squash;
        angle = idle * spec.sway * 1.6;
        break;
      case PetState.hungry:
        // 饿：垂头丧气，小幅度晃动。
        dy = 12 + idle * spec.driftY;
        scaleY = .96 - idle.abs() * spec.squash;
        angle = idle * spec.sway * 1.4;
        break;
      case PetState.idle:
      case PetState.standing:
        // 站起：轻微呼吸起伏 + 眨眼。
        dy = idle * spec.driftY;
        angle = idle * .012;
        break;
    }
    return PetPose(
      dx: dx,
      dy: dy,
      scaleX: (faceLeft ? -1.0 : 1.0) * scale,
      scaleY: scale * scaleY,
      angle: angle,
      blink: blink,
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = machine.state;
    final cycle = machine.controller.value;
    final hasBlinkFrame = aiPetClosedEyeAssetPath(imageUrl) != null;
    final from = _poseFor(machine.previous, cycle, worldTime, hasBlinkFrame);
    final to = _poseFor(state, cycle, worldTime, hasBlinkFrame);
    final pose = from.lerp(to, machine.blendValue);
    return Transform.translate(
      offset: Offset(pose.dx, pose.dy),
      child: Transform.rotate(
        angle: pose.angle,
        child: Transform.scale(
          scaleX: pose.scaleX,
          scaleY: pose.scaleY,
          alignment: const Alignment(0, .55),
          child: Align(
            alignment: const Alignment(0, .35),
            child: SizedBox(
              width: 245,
              height: 245,
              child: AIPetAvatar(
                name: name,
                imageUrl: imageUrl,
                blinkAmount: pose.blink,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
