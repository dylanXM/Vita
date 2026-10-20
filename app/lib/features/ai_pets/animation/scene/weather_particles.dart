import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 天气类型（预留 AI 控制入口）。
enum Weather { none, rain, snow, leaves }

/// 天气粒子层：雨/雪/落叶，由世界时钟驱动。
class WeatherParticles extends StatelessWidget {
  const WeatherParticles({
    super.key,
    required this.weather,
    required this.worldTime,
  });

  final Weather weather;
  final double worldTime;

  @override
  Widget build(BuildContext context) {
    if (weather == Weather.none) return const SizedBox.shrink();
    return RepaintBoundary(
      child: CustomPaint(
        painter: _WeatherPainter(weather, worldTime),
        size: Size.infinite,
      ),
    );
  }
}

class _Particle {
  const _Particle(this.x, this.y, this.speed, this.size, this.phase);
  final double x; // 0..1
  final double y; // 0..1
  final double speed; // 每秒下落比例
  final double size;
  final double phase;
}

class _WeatherPainter extends CustomPainter {
  _WeatherPainter(this.weather, this.worldTime)
      : _particles = _buildParticles(weather);

  final Weather weather;
  final double worldTime;
  final List<_Particle> _particles;

  static List<_Particle> _buildParticles(Weather weather) {
    final rng = math.Random(20260923);
    final count = switch (weather) {
      Weather.rain => 40,
      Weather.snow => 26,
      Weather.leaves => 12,
      Weather.none => 0,
    };
    return List.generate(count, (i) {
      final speed = switch (weather) {
        Weather.rain => .5 + rng.nextDouble() * .4,
        Weather.snow => .06 + rng.nextDouble() * .08,
        Weather.leaves => .12 + rng.nextDouble() * .1,
        Weather.none => 0.0,
      };
      return _Particle(rng.nextDouble(), rng.nextDouble(), speed,
          1.0 + rng.nextDouble() * 2, rng.nextDouble() * math.pi * 2);
    });
  }

  @override
  void paint(Canvas canvas, Size size) {
    final t = worldTime * 60; // 秒
    for (final p in _particles) {
      final y = ((p.y + t * p.speed) % 1.2) - .1;
      final x = (p.x + math.sin(t * 1.5 + p.phase) * .02 + 1) % 1;
      final px = x * size.width;
      final py = y * size.height;
      switch (weather) {
        case Weather.rain:
          final paint = Paint()
            ..color = const Color(0x66BBD3E8)
            ..strokeWidth = 1.4;
          canvas.drawLine(Offset(px, py), Offset(px - 4, py + 14), paint);
          break;
        case Weather.snow:
          canvas.drawCircle(
              Offset(px, py),
              p.size * .8,
              Paint()..color = Colors.white.withValues(alpha: .8));
          break;
        case Weather.leaves:
          canvas.save();
          canvas.translate(px, py);
          canvas.rotate(math.sin(t + p.phase) * .8);
          canvas.drawOval(
              Rect.fromCenter(center: Offset.zero, width: 7, height: 3.6),
              Paint()..color = const Color(0xFF7FAF5C).withValues(alpha: .85));
          canvas.restore();
          break;
        case Weather.none:
          break;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _WeatherPainter old) =>
      old.weather != weather || old.worldTime != worldTime;
}
