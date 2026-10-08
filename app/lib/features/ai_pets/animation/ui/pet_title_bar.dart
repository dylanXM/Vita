import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../../core/theme.dart';
import '../pet/pet_motion_spec.dart';
import '../pet/pet_state_machine.dart';
import '../world_clock.dart';

/// 全页动画标题栏：返回按钮 + 宠物名流光 + 等级徽章 + 生活状态徽章，
/// 整体随世界时钟轻微浮动。
class PetTitleBar extends StatelessWidget {
  const PetTitleBar({
    super.key,
    required this.name,
    required this.level,
    required this.species,
    required this.machine,
    required this.clock,
    required this.onBack,
  });

  final String name;
  final int level;
  final String species;
  final PetStateMachine machine;
  final WorldClock clock;
  final VoidCallback onBack;

  /// 状态标签（i18n 键）。
  static String stateLabelKey(PetState state) => switch (state) {
        PetState.standing || PetState.idle => 'aiPets.stateStanding',
        PetState.sitting => 'aiPets.stateSitting',
        PetState.walking => 'aiPets.stateWalking',
        PetState.sleeping => 'aiPets.stateSleeping',
        PetState.tired => 'aiPets.stateTired',
        PetState.hungry => 'aiPets.stateHungry',
        PetState.feeding => 'aiPets.stateFeeding',
        PetState.happy => 'aiPets.stateHappy',
        PetState.levelUp => 'aiPets.stateLevelUp',
        PetState.thinking => 'aiPets.stateThinking',
        PetState.sick => 'aiPets.stateSick',
      };

  /// 状态徽章颜色。
  static Color stateColor(PetState state, VitaThemeData vita) =>
      switch (state) {
        PetState.standing || PetState.idle => vita.green,
        PetState.sitting => const Color(0xFF0FB5AE),
        PetState.walking => const Color(0xFF4A90E2),
        PetState.sleeping => const Color(0xFF776A9E),
        PetState.tired => const Color(0xFFF5A623),
        PetState.hungry => const Color(0xFFE05A47),
        PetState.feeding => const Color(0xFFF5A623),
        PetState.happy => const Color(0xFFF06A89),
        PetState.levelUp => const Color(0xFFFFB930),
        PetState.thinking => const Color(0xFF8E8E93),
        PetState.sick => vita.red,
      };

  @override
  Widget build(BuildContext context) {
    final vita = context.vita;
    return AnimatedBuilder(
      animation: Listenable.merge([clock, machine]),
      builder: (context, _) {
        final worldTime = clock.worldTime;
        final state = machine.state;
        final float = math.sin(worldTime * math.pi * 2 * 3) * 3;
        final stateChipColor = stateColor(state, vita);
        return Transform.translate(
          offset: Offset(0, float),
          child: Row(children: [
            _GlassButton(onTap: onBack, child: const Icon(Icons.arrow_back, size: 22)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _ShimmerName(name: name, worldTime: worldTime),
                  const SizedBox(height: 4),
                  Row(children: [
                    _Chip(
                      color: vita.greenTint,
                      child: Text('aiPets.level'.trParams({'level': '$level'}),
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: vita.greenDark)),
                    ),
                    const SizedBox(width: 6),
                    _Chip(
                      color: stateChipColor.withValues(alpha: .14),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                              color: stateChipColor, shape: BoxShape.circle),
                        ),
                        const SizedBox(width: 5),
                        Text(stateLabelKey(state).tr,
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: stateChipColor)),
                      ]),
                    ),
                    if (species.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      _Chip(
                        color: vita.surface.withValues(alpha: .6),
                        child: Text(species,
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: vita.subText)),
                      ),
                    ],
                  ]),
                ],
              ),
            ),
          ]),
        );
      },
    );
  }
}

class _ShimmerName extends StatelessWidget {
  const _ShimmerName({required this.name, required this.worldTime});

  final String name;
  final double worldTime;

  @override
  Widget build(BuildContext context) {
    final vita = context.vita;
    // 流光扫过：渐变位置随世界时钟移动。
    final sweep = (worldTime * 1.5) % 1.0;
    return ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: (bounds) => LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [
          vita.text,
          vita.text,
          vita.green,
          vita.text,
          vita.text,
        ],
        stops: [
          (sweep - .3).clamp(0.0, 1.0),
          (sweep - .12).clamp(0.0, 1.0),
          sweep,
          (sweep + .12).clamp(0.0, 1.0),
          (sweep + .3).clamp(0.0, 1.0),
        ],
      ).createShader(bounds),
      child: Text(
        name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w800,
          color: vita.text,
          height: 1.1,
        ),
      ),
    );
  }
}

class _GlassButton extends StatelessWidget {
  const _GlassButton({required this.onTap, required this.child});

  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final vita = context.vita;
    return Material(
      color: vita.glass,
      shape: const CircleBorder(),
      elevation: 0,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: vita.glassRing, width: .8),
            boxShadow: [
              BoxShadow(
                  color: vita.glassShadow,
                  blurRadius: 10,
                  offset: const Offset(0, 3)),
            ],
          ),
          alignment: Alignment.center,
          child: DefaultTextStyle.merge(
            style: TextStyle(color: vita.text),
            child: child,
          ),
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.color,
    required this.child,
  });

  final Color color;
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(999),
        ),
        child: child,
      );
}
