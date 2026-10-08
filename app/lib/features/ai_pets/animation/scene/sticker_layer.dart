import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 贴纸装饰层：心形 / 星星 / 爪印 / 云朵 / 叶子等矢量贴纸，
/// 由世界时钟驱动缓慢浮动、旋转与明暗呼吸，营造轻快的贴纸背景。
class StickerLayer extends StatelessWidget {
  const StickerLayer({
    super.key,
    required this.worldTime,
    required this.dayProgress,
    this.opacity = 1,
  });

  /// 0..1 世界时钟循环时间。
  final double worldTime;

  /// 0..1 昼夜进度（影响贴纸明暗）。
  final double dayProgress;

  /// 整体透明度（夜间可调暗）。
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        painter: _StickerPainter(worldTime, dayProgress, opacity),
        size: Size.infinite,
      ),
    );
  }
}

enum _StickerKind { heart, star, paw, cloud, leaf, bone }

class _Sticker {
  const _Sticker(this.kind, this.x, this.y, this.size, this.phase, this.speed);

  final _StickerKind kind;
  final double x; // 0..1
  final double y; // 0..1
  final double size;
  final double phase;
  final double speed; // 浮动速度因子
}

class _StickerPainter extends CustomPainter {
  _StickerPainter(this.worldTime, this.dayProgress, this.opacity)
      : _stickers = _buildStickers();

  final double worldTime;
  final double dayProgress;
  final double opacity;
  final List<_Sticker> _stickers;

  static const int _count = 16;

  static List<_Sticker> _buildStickers() {
    final rng = math.Random(20261008);
    const kinds = [
      _StickerKind.heart,
      _StickerKind.star,
      _StickerKind.paw,
      _StickerKind.cloud,
      _StickerKind.leaf,
      _StickerKind.bone,
    ];
    return List.generate(_count, (i) {
      final kind = kinds[i % kinds.length];
      return _Sticker(
        kind,
        .02 + rng.nextDouble() * .96,
        .04 + rng.nextDouble() * .88,
        14 + rng.nextDouble() * 22,
        rng.nextDouble() * math.pi * 2,
        .5 + rng.nextDouble() * .9,
      );
    });
  }

  @override
  void paint(Canvas canvas, Size size) {
    final t = worldTime * 60; // 秒
    final night = (1 - (1 - ((dayProgress * 2 - 1).abs()).clamp(0.0, 1.0)))
        .clamp(0.0, 1.0);
    final baseAlpha = .55 - night * .3;
    for (final s in _stickers) {
      // 缓慢上下浮动 + 横向漂移。
      final bob = math.sin(t * .7 * s.speed + s.phase) * 10;
      final sway = math.sin(t * .5 * s.speed + s.phase * 2) * 8;
      final cx = (s.x * size.width + sway) % size.width;
      final cy = ((s.y * size.height + bob) % (size.height * 1.1)) - size.height * .05;
      final breathe = .75 + .25 * math.sin(t * 1.2 * s.speed + s.phase);
      canvas.save();
      canvas.translate(cx, cy);
      canvas.rotate(math.sin(t * .4 * s.speed + s.phase) * .25);
      final paint = Paint()
        ..color = _colorOf(s.kind).withValues(alpha: (baseAlpha * breathe * opacity).clamp(0.0, 1.0));
      _drawSticker(canvas, s.kind, s.size, paint);
      canvas.restore();
    }
  }

  Color _colorOf(_StickerKind kind) => switch (kind) {
        _StickerKind.heart => const Color(0xFFF06A89),
        _StickerKind.star => const Color(0xFFFFB930),
        _StickerKind.paw => const Color(0xFF8A6BCF),
        _StickerKind.cloud => const Color(0xFFFFFFFF),
        _StickerKind.leaf => const Color(0xFF7FAF5C),
        _StickerKind.bone => const Color(0xFFD9A066),
      };

  void _drawSticker(Canvas canvas, _StickerKind kind, double size, Paint paint) {
    switch (kind) {
      case _StickerKind.heart:
        _drawHeart(canvas, size, paint);
        break;
      case _StickerKind.star:
        _drawStar(canvas, size, paint);
        break;
      case _StickerKind.paw:
        _drawPaw(canvas, size, paint);
        break;
      case _StickerKind.cloud:
        _drawCloud(canvas, size, paint);
        break;
      case _StickerKind.leaf:
        _drawLeaf(canvas, size, paint);
        break;
      case _StickerKind.bone:
        _drawBone(canvas, size, paint);
        break;
    }
  }

  void _drawHeart(Canvas canvas, double size, Paint paint) {
    final path = Path()
      ..moveTo(0, size * .3)
      ..cubicTo(-size, -size * .18, -size * .5, -size * .62, 0, -size * .18)
      ..cubicTo(size * .5, -size * .62, size, -size * .18, 0, size * .3);
    canvas.drawPath(path, paint);
  }

  void _drawStar(Canvas canvas, double size, Paint paint) {
    final path = Path();
    for (var i = 0; i < 10; i++) {
      final r = i.isEven ? size : size * .45;
      final a = -math.pi / 2 + i * math.pi / 5;
      final p = Offset(math.cos(a) * r, math.sin(a) * r);
      if (i == 0) {
        path.moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  void _drawPaw(Canvas canvas, double size, Paint paint) {
    final main = size * .52;
    final toe = size * .22;
    canvas.drawOval(
        Rect.fromCenter(center: Offset(0, size * .32), width: main, height: main * .9),
        paint);
    for (var i = -1; i <= 1; i++) {
      canvas.drawCircle(
          Offset(i * size * .34, -size * .28), toe, paint);
    }
  }

  void _drawCloud(Canvas canvas, double size, Paint paint) {
    canvas.drawOval(
        Rect.fromCenter(center: Offset(-size * .22, size * .05),
            width: size * .8,
            height: size * .5),
        paint);
    canvas.drawOval(
        Rect.fromCenter(center: Offset(size * .14, -size * .08),
            width: size * .62,
            height: size * .44),
        paint);
    canvas.drawOval(
        Rect.fromCenter(center: Offset(size * .3, size * .08),
            width: size * .55,
            height: size * .4),
        paint);
  }

  void _drawLeaf(Canvas canvas, double size, Paint paint) {
    final path = Path()
      ..moveTo(0, -size * .5)
      ..quadraticBezierTo(size * .55, -size * .12, 0, size * .5)
      ..quadraticBezierTo(-size * .55, -size * .12, 0, -size * .5)
      ..close();
    canvas.drawPath(path, paint);
    canvas.drawLine(
        Offset(0, -size * .45),
        Offset(0, size * .45),
        Paint()
          ..color = Colors.white.withValues(alpha: .35)
          ..strokeWidth = size * .06
          ..strokeCap = StrokeCap.round);
  }

  void _drawBone(Canvas canvas, double size, Paint paint) {
    final knob = size * .26;
    final w = size * 1.1;
    final h = size * .34;
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromCenter(center: Offset.zero, width: w, height: h),
            Radius.circular(h / 2)),
        paint);
    for (final s in const [-1.0, 1.0]) {
      canvas.drawCircle(Offset(-w / 2, s * h * .42), knob, paint);
      canvas.drawCircle(Offset(w / 2, s * h * .42), knob, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _StickerPainter old) =>
      old.worldTime != worldTime ||
      old.dayProgress != dayProgress ||
      old.opacity != opacity;
}
