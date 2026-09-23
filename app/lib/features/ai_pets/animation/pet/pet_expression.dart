import 'package:flutter/material.dart';

import 'pet_motion_spec.dart';

/// 状态特效叠加层：♥ / Zzz / 星星 / 汗水 / 音符 / 食盆 / AI 气泡。
class PetFxLayer extends StatelessWidget {
  const PetFxLayer({super.key, required this.state, this.speech});

  final PetState state;
  final String? speech;

  @override
  Widget build(BuildContext context) {
    final fx = PetMotionSpec.table[state]?.fx ?? const <PetFx>[];
    return Stack(children: [
      if (fx.contains(PetFx.hearts))
        const Positioned(
          top: 58,
          right: 54,
          child: Text('♥',
              style: TextStyle(fontSize: 42, color: Color(0xFFF06A89))),
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
      if (fx.contains(PetFx.bowl))
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
                        borderRadius:
                            BorderRadius.all(Radius.circular(100))))),
          ]),
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
}

class _FxStar extends StatelessWidget {
  const _FxStar({this.size = 28});
  final double size;

  @override
  Widget build(BuildContext context) => Icon(Icons.star_rounded,
      size: size, color: const Color(0xFFFFB930));
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
                color: Color(0x22000000),
                blurRadius: 8,
                offset: Offset(0, 3))
          ],
        ),
        child: Text(text,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, color: Color(0xFF333333))),
      );
}
