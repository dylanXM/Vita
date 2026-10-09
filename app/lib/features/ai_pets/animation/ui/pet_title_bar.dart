import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../../../../core/theme.dart';
import '../world_clock.dart';

/// 宠物页面顶部只显示返回按钮和宠物名称。
class PetTitleBar extends StatelessWidget {
  const PetTitleBar({
    super.key,
    required this.name,
    required this.clock,
    required this.onBack,
  });

  final String name;
  final WorldClock clock;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: clock,
      builder: (context, _) {
        final worldTime = clock.worldTime;
        final float = math.sin(worldTime * math.pi * 2 * 3) * 3;
        return Transform.translate(
          offset: Offset(0, float),
          child: Row(children: [
            _GlassButton(
                onTap: onBack, child: const Icon(Icons.arrow_back, size: 22)),
            const SizedBox(width: 12),
            Expanded(child: _ShimmerName(name: name, worldTime: worldTime)),
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
          width: 44,
          height: 44,
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
