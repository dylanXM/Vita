import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 动态背景：天空/日月/星星/云/远山/前景草，全部由世界时钟驱动。
class BackgroundLayer extends StatelessWidget {
  const BackgroundLayer({
    super.key,
    required this.dayProgress,
    required this.worldTime,
  });

  /// 0..1 昼夜进度（0 = 子夜，0.5 = 正午）。
  final double dayProgress;

  /// 0..1 世界时钟循环时间。
  final double worldTime;

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: Stack(
        fit: StackFit.expand,
        children: [
          RepaintBoundary(
              child: CustomPaint(painter: _SkyPainter(dayProgress))),
          RepaintBoundary(
              child: CustomPaint(painter: _SunMoonPainter(dayProgress))),
          RepaintBoundary(
              child: CustomPaint(painter: _StarsPainter(dayProgress, worldTime))),
          RepaintBoundary(
              child: CustomPaint(painter: _CloudPainter(dayProgress, worldTime))),
          RepaintBoundary(
              child: CustomPaint(painter: _HillsPainter(dayProgress, worldTime))),
          RepaintBoundary(child: CustomPaint(painter: _GrassPainter(worldTime))),
        ],
      ),
    );
  }
}

/// 昼夜因子：1 = 正午，0 = 子夜。
double _dayFactor(double dayProgress) =>
    1 - ((dayProgress * 2 - 1).abs()).clamp(0.0, 1.0);

Color _lerpColor(Color a, Color b, double t) =>
    Color.lerp(a, b, t.clamp(0.0, 1.0))!;

class _SkyPainter extends CustomPainter {
  _SkyPainter(this.dayProgress);
  final double dayProgress;

  @override
  void paint(Canvas canvas, Size size) {
    final t = _dayFactor(dayProgress);
    const dayTop = Color(0xFF7EC8F2);
    const nightTop = Color(0xFF10182F);
    const dayBottom = Color(0xFFFFF1DE);
    const nightBottom = Color(0xFF232C45);
    final top = _lerpColor(nightTop, dayTop, t);
    final bottom = _lerpColor(nightBottom, dayBottom, t);
    final rect = Offset.zero & size;
    canvas.drawRect(
        rect,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [top, bottom],
          ).createShader(rect));
  }

  @override
  bool shouldRepaint(covariant _SkyPainter old) =>
      old.dayProgress != dayProgress;
}

class _SunMoonPainter extends CustomPainter {
  _SunMoonPainter(this.dayProgress);
  final double dayProgress;

  @override
  void paint(Canvas canvas, Size size) {
    final t = _dayFactor(dayProgress);
    // 太阳：白天从左到右划过；月亮：夜晚出现。
    final sunX = size.width * (.12 + .76 * t);
    final sunY = size.height * (.22 + .12 * (1 - t));
    final sunOpacity = t.clamp(0.0, 1.0);
    if (sunOpacity > .02) {
      canvas.drawCircle(
          Offset(sunX, sunY),
          22,
          Paint()
            ..color = const Color(0xFFFFD27A).withValues(alpha: .45 * sunOpacity)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14));
      canvas.drawCircle(
          Offset(sunX, sunY), 15, Paint()..color = const Color(0xFFFFE9A8));
    }
    final moonT = 1 - t;
    final moonX = size.width * (.72 + .18 * (1 - moonT));
    final moonY = size.height * (.2 + .1 * moonT);
    final moonOpacity = moonT.clamp(0.0, 1.0);
    if (moonOpacity > .02) {
      canvas.drawCircle(
          Offset(moonX, moonY),
          13,
          Paint()
            ..color = const Color(0xFFE8EEFF).withValues(alpha: .4 * moonOpacity)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12));
      canvas.drawCircle(
          Offset(moonX, moonY), 10, Paint()..color = const Color(0xFFF4F7FF));
    }
  }

  @override
  bool shouldRepaint(covariant _SunMoonPainter old) =>
      old.dayProgress != dayProgress;
}

class _StarsPainter extends CustomPainter {
  _StarsPainter(this.dayProgress, this.worldTime);
  final double dayProgress;
  final double worldTime;

  @override
  void paint(Canvas canvas, Size size) {
    final night = (1 - _dayFactor(dayProgress)).clamp(0.0, 1.0);
    if (night < .02) return;
    final rng = math.Random(7);
    final paint = Paint();
    for (var i = 0; i < 16; i++) {
      final x = rng.nextDouble() * size.width;
      final y = rng.nextDouble() * size.height * .55;
      final twinkle =
          .5 + .5 * math.sin(worldTime * math.pi * 2 * (3 + i % 4) + i * 1.7);
      final alpha = night * (.35 + .65 * twinkle);
      paint.color = Colors.white.withValues(alpha: alpha.clamp(0.0, 1.0));
      canvas.drawCircle(
          Offset(x, y), 1.0 + rng.nextDouble() * 1.2, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _StarsPainter old) =>
      old.dayProgress != dayProgress || old.worldTime != worldTime;
}

class _CloudPainter extends CustomPainter {
  _CloudPainter(this.dayProgress, this.worldTime);
  final double dayProgress;
  final double worldTime;

  @override
  void paint(Canvas canvas, Size size) {
    final t = _dayFactor(dayProgress);
    final base = _lerpColor(const Color(0xFF4A5878), const Color(0xFFFFFFFF), t);
    for (var i = 0; i < 3; i++) {
      final span = size.width + 220;
      final x = ((i * .37 + worldTime * (.05 + i * .03)) % 1) * span - 110;
      final y = size.height * (.1 + i * .13);
      final w = 70.0 + i * 14;
      final paint = Paint()
        ..color = base.withValues(alpha: .5 - i * .08);
      canvas.drawOval(
          Rect.fromCenter(center: Offset(x, y), width: w, height: w * .42),
          paint);
      canvas.drawOval(
          Rect.fromCenter(
              center: Offset(x - w * .22, y + 4), width: w * .55, height: w * .3),
          paint);
      canvas.drawOval(
          Rect.fromCenter(
              center: Offset(x + w * .24, y + 3), width: w * .5, height: w * .28),
          paint);
    }
  }

  @override
  bool shouldRepaint(covariant _CloudPainter old) =>
      old.dayProgress != dayProgress || old.worldTime != worldTime;
}

class _HillsPainter extends CustomPainter {
  _HillsPainter(this.dayProgress, this.worldTime);
  final double dayProgress;
  final double worldTime;

  @override
  void paint(Canvas canvas, Size size) {
    final t = _dayFactor(dayProgress);
    final far = _lerpColor(const Color(0xFF2A3550), const Color(0xFFA9C9A0), t);
    final near = _lerpColor(const Color(0xFF232B42), const Color(0xFF7FAF8B), t);
    final shift = math.sin(worldTime * math.pi * 2) * 8;
    _drawHill(canvas, size, far, size.height * .72, 1.6, shift * .5);
    _drawHill(canvas, size, near, size.height * .8, 1.2, shift);
  }

  void _drawHill(Canvas canvas, Size size, Color color, double baseY,
      double widthFactor, double shift) {
    final paint = Paint()..color = color;
    final path = Path()..moveTo(0, size.height);
    final step = size.width / 3;
    for (var i = 0; i <= 3; i++) {
      final cx = i * step + shift;
      final top = baseY - 30 * (i.isEven ? 1 : .6);
      if (i == 0) {
        path.lineTo(cx, top);
      } else {
        final prevX = (i - 1) * step + shift;
        path.quadraticBezierTo((prevX + cx) / 2, top - 34, cx, top);
      }
    }
    path.lineTo(size.width, size.height);
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _HillsPainter old) =>
      old.dayProgress != dayProgress || old.worldTime != worldTime;
}

class _GrassPainter extends CustomPainter {
  _GrassPainter(this.worldTime);
  final double worldTime;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF5E9E62)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    final baseY = size.height;
    for (var i = 0; i < 22; i++) {
      final x = i / 22 * size.width;
      final sway = math.sin(worldTime * math.pi * 2 + i * .9) * 3;
      final h = 8 + (i % 3) * 4;
      final path = Path()
        ..moveTo(x, baseY)
        ..quadraticBezierTo(x + sway * .4, baseY - h * .6, x + sway, baseY - h);
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _GrassPainter old) =>
      old.worldTime != worldTime;
}
