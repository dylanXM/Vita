import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'pet_motion_spec.dart';
import 'pet_state_machine.dart';

/// 状态特效叠加层：♥ / Zzz / 星星 / 汗水 / 音符 / 食盆 / AI 气泡。
class PetFxLayer extends StatelessWidget {
  const PetFxLayer({
    super.key,
    required this.machine,
    required this.worldTime,
    this.poseSheet = false,
    this.speech,
  });

  final PetStateMachine machine;
  final double worldTime;
  final bool poseSheet;
  final String? speech;

  @override
  Widget build(BuildContext context) {
    final weights = machine.stateWeights;
    final cycle = (worldTime * 23) % 1;
    return Stack(children: [
      for (final entry in weights.entries)
        if (entry.value > 0 && PetMotionSpec.table[entry.key]!.fx.isNotEmpty)
          Positioned.fill(
            child: IgnorePointer(
              child: Opacity(
                opacity: entry.value.clamp(0.0, 1.0),
                child: Transform.translate(
                  offset: Offset(
                    0,
                    entry.key == PetState.feeding
                        ? 0
                        : -4 * math.sin(cycle * math.pi * 2),
                  ),
                  child: _buildEffects(
                    PetMotionSpec.table[entry.key]!.fx,
                    cycle,
                  ),
                ),
              ),
            ),
          ),
      if (speech != null && speech!.isNotEmpty)
        Positioned(
          top: 12,
          left: 0,
          right: 0,
          child: Center(child: PetSpeechBubble(text: speech!)),
        ),
    ]);
  }

  Widget _buildEffects(List<PetFx> fx, double cycle) {
    return Stack(children: [
      if (fx.contains(PetFx.hearts))
        for (var i = 0; i < 3; i++)
          Positioned(
            top: 78 - i * 27.0,
            right: 62 + i * 22.0,
            child: Transform.translate(
              offset: Offset(0, -12 * math.sin(cycle * math.pi * 2 + i)),
              child: Text('♥',
                  style: TextStyle(
                    fontSize: 23.0 + i * 6,
                    color:
                        const Color(0xFFF06A89).withValues(alpha: .7 + i * .1),
                  )),
            ),
          ),
      if (fx.contains(PetFx.zzz))
        const Positioned(
          top: 58,
          right: 48,
          child: Text('Zzz',
              style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF776A9E))),
        ),
      if (fx.contains(PetFx.stars)) ...const [
        Positioned(top: 50, left: 48, child: _FxStar()),
        Positioned(top: 78, right: 42, child: _FxStar(size: 34)),
        Positioned(bottom: 82, right: 58, child: _FxStar(size: 24)),
      ],
      if (fx.contains(PetFx.sweat))
        const Positioned(
          top: 64,
          right: 60,
          child: Text('💧', style: TextStyle(fontSize: 26)),
        ),
      if (fx.contains(PetFx.notes))
        const Positioned(
          top: 60,
          left: 52,
          child: Text('💭', style: TextStyle(fontSize: 28)),
        ),
      if (fx.contains(PetFx.tired))
        const Positioned(
          top: 64,
          right: 60,
          child: Text('😪', style: TextStyle(fontSize: 26)),
        ),
      if (fx.contains(PetFx.hungry))
        const Positioned(
          top: 64,
          right: 60,
          child: Text('🦴', style: TextStyle(fontSize: 24)),
        ),
      if (!poseSheet && fx.contains(PetFx.bowl))
        const Positioned(
          bottom: 15,
          left: 0,
          right: 0,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('🥣', style: TextStyle(fontSize: 56)),
            SizedBox(
                width: 78,
                height: 8,
                child: DecoratedBox(
                    decoration: BoxDecoration(
                        color: Color(0x22000000),
                        borderRadius: BorderRadius.all(Radius.circular(100))))),
          ]),
        ),
      if (!poseSheet && fx.contains(PetFx.water))
        Positioned(
          bottom: 15,
          left: 0,
          right: 0,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.water_drop_rounded,
                size: 28, color: const Color(0xFF72C8EC)),
            Transform.scale(
              scaleX: 1 + .06 * math.sin(cycle * math.pi * 2),
              child: Container(
                width: 76,
                height: 15,
                decoration: BoxDecoration(
                  color: const Color(0xFF74BDDD),
                  borderRadius: BorderRadius.circular(100),
                  border: Border.all(color: const Color(0xFFD8F4FF), width: 2),
                ),
              ),
            ),
          ]),
        ),
    ]);
  }
}

class _FxStar extends StatelessWidget {
  const _FxStar({this.size = 28});
  final double size;

  @override
  Widget build(BuildContext context) =>
      Icon(Icons.star_rounded, size: size, color: const Color(0xFFFFB930));
}

/// AI 说话气泡（预留：由 AIPetBrain 的 speech 驱动）。
class PetSpeechBubble extends StatelessWidget {
  const PetSpeechBubble({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Container(
        constraints: const BoxConstraints(maxWidth: 220),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: const [
            BoxShadow(
                color: Color(0x22000000), blurRadius: 8, offset: Offset(0, 3))
          ],
        ),
        child: Text(text,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, color: Color(0xFF333333))),
      );
}
