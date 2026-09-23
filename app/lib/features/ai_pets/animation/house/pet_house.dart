import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 宠物小屋：屋顶/墙体/门/窗/烟囱，由世界时钟与状态驱动。
class PetHouse extends StatelessWidget {
  const PetHouse({
    super.key,
    required this.dayProgress,
    required this.worldTime,
    required this.doorAmount,
    required this.lightOn,
    required this.smokeOn,
  });

  /// 0..1 昼夜进度。
  final double dayProgress;

  /// 0..1 世界时钟循环时间。
  final double worldTime;

  /// 0..1 门开合程度。
  final double doorAmount;

  /// 夜间窗户亮灯。
  final bool lightOn;

  /// 烟囱冒烟。
  final bool smokeOn;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        painter: _HousePainter(
          dayProgress: dayProgress,
          worldTime: worldTime,
          doorAmount: doorAmount,
          lightOn: lightOn,
          smokeOn: smokeOn,
        ),
        size: Size.infinite,
      ),
    );
  }
}

class _HousePainter extends CustomPainter {
  _HousePainter({
    required this.dayProgress,
    required this.worldTime,
    required this.doorAmount,
    required this.lightOn,
    required this.smokeOn,
  });

  final double dayProgress;
  final double worldTime;
  final double doorAmount;
  final bool lightOn;
  final bool smokeOn;

  @override
  void paint(Canvas canvas, Size size) {
    final t = (1 - ((dayProgress * 2 - 1).abs()).clamp(0.0, 1.0));
    Color lerp(Color a, Color b) => Color.lerp(a, b, t)!;

    // 墙体
    final wall = lerp(const Color(0xFF5B4A68), const Color(0xFFF3D9B1));
    final wallRect = Rect.fromLTWH(
        size.width * .18, size.height * .42, size.width * .68, size.height * .48);
    final wallPaint = Paint()..color = wall;
    canvas.drawRRect(
        RRect.fromRectAndRadius(wallRect, const Radius.circular(6)), wallPaint);

    // 屋顶
    final roof = lerp(const Color(0xFF3D2F4E), const Color(0xFFC98F5F));
    final roofPath = Path()
      ..moveTo(size.width * .08, size.height * .46)
      ..lineTo(size.width * .52, size.height * .12)
      ..lineTo(size.width * .96, size.height * .46)
      ..close();
    canvas.drawPath(roofPath, Paint()..color = roof);

    // 烟囱
    final chimney = lerp(const Color(0xFF463A5A), const Color(0xFFB97A52));
    final chimneyRect = Rect.fromLTWH(size.width * .68, size.height * .16,
        size.width * .14, size.height * .2);
    canvas.drawRect(chimneyRect, Paint()..color = chimney);

    // 窗户
    final windowRect = Rect.fromLTWH(size.width * .6, size.height * .56,
        size.width * .2, size.height * .2);
    final windowColor = lightOn
        ? const Color(0xFFFFD27A)
        : lerp(const Color(0xFF26304A), const Color(0xFFB9D6E8));
    canvas.drawRRect(
        RRect.fromRectAndRadius(windowRect, const Radius.circular(3)),
        Paint()..color = windowColor);
    // 窗框十字
    final framePaint = Paint()
      ..color = lerp(const Color(0xFF3D2F4E), const Color(0xFF8A6B52))
      ..strokeWidth = 1.6;
    final windowCenter = windowRect.center;
    canvas.drawLine(Offset(windowRect.left, windowCenter.dy),
        Offset(windowRect.right, windowCenter.dy), framePaint);
    canvas.drawLine(Offset(windowCenter.dx, windowRect.top),
        Offset(windowCenter.dx, windowRect.bottom), framePaint);

    // 门（doorAmount 控制开合：绕左侧铰链旋转）
    final doorWidth = size.width * .22;
    final doorRect = Rect.fromLTWH(
        size.width * .2, size.height * .66, doorWidth, size.height * .24);
    final doorColor = lerp(const Color(0xFF6B4A3C), const Color(0xFFA9714E));
    canvas.save();
    canvas.translate(doorRect.left, doorRect.top);
    canvas.rotate(-doorAmount * 1.2);
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(0, 0, doorRect.width, doorRect.height),
            const Radius.circular(3)),
        Paint()..color = doorColor);
    canvas.drawCircle(Offset(doorRect.width - 5, doorRect.height * .5), 1.8,
        Paint()..color = const Color(0xFFFFE9A8));
    canvas.restore();

    // 烟囱冒烟（smokeOn 时两朵烟上升消散）
    if (smokeOn) {
      for (var i = 0; i < 2; i++) {
        final progress = ((worldTime * 2 + i * .5) % 1.0);
        final p = Paint()
          ..color = Colors.white
              .withValues(alpha: (.6 * (1 - progress)).clamp(0.0, .6));
        final cx = chimneyRect.center.dx +
            math.sin((worldTime * 6 + i * 3.1)) * 2.4;
        final cy = chimneyRect.top - 6 - progress * size.height * .16;
        canvas.drawCircle(
            Offset(cx, cy), 3.5 + progress * 5, p);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _HousePainter old) =>
      old.dayProgress != dayProgress ||
      old.worldTime != worldTime ||
      old.doorAmount != doorAmount ||
      old.lightOn != lightOn ||
      old.smokeOn != smokeOn;
}
