import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../shared/media_image.dart';

/// Lightweight authored environments, independent of the companion portrait.
/// Repaints only when the location or the recorded scene focus changes.
class ExperienceEnvironment extends StatelessWidget {
  const ExperienceEnvironment(
      {super.key,
      required this.location,
      required this.name,
      this.portrait,
      this.focus = 'ambient',
      this.narration = '',
      this.height = 300});
  final String location, name, focus, narration;
  final String? portrait;
  final double height;

  static String kind(String location) => switch (location) {
        'cafe' || 'cinema' || 'restaurant' => location,
        _ => 'general',
      };
  static Color background(String location) => switch (kind(location)) {
        'cafe' => const Color(0xFF27211F),
        'cinema' => const Color(0xFF181B2D),
        'restaurant' => const Color(0xFF282022),
        _ => const Color(0xFF1F2931),
      };

  @override
  Widget build(BuildContext context) => SizedBox(
      height: height,
      child: Stack(children: [
        Positioned.fill(
            child: RepaintBoundary(
                child: CustomPaint(
                    painter: _EnvironmentPainter(kind(location), focus,
                        Directionality.of(context) == TextDirection.rtl)))),
        PositionedDirectional(
            end: 24,
            top: height < 250 ? 8 : 20,
            bottom: height < 250 ? 18 : 74,
            child: SizedBox(
                width: height < 250 ? (height * .5).clamp(44.0, 110.0) : 126,
                child: Column(children: [
                  Expanded(
                      child: Container(
                          decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(64),
                              boxShadow: [
                                BoxShadow(
                                    color: Colors.black.withValues(alpha: .3),
                                    blurRadius: 26,
                                    offset: const Offset(0, 12))
                              ],
                              border: Border.all(
                                  color: Colors.white.withValues(
                                      alpha: focus == 'ta' ? .5 : .15),
                                  width: 2)),
                          child: ClipRRect(
                              borderRadius: BorderRadius.circular(64),
                              child: portrait?.isNotEmpty == true
                                  ? VitaMediaImage(
                                      url: portrait!,
                                      errorBuilder: (_, __, ___) =>
                                          _missingPerson())
                                  : _missingPerson()))),
                  if (height >= 120) const SizedBox(height: 8),
                  if (height >= 120)
                    Text(name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w600)),
                ]))),
        if (height >= 120)
          PositionedDirectional(
              start: 16,
              bottom: height < 250 ? 12 : 58,
              child: Text('moment.environment.${kind(location)}'.tr,
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: .7),
                      fontSize: 12))),
        if (narration.trim().isNotEmpty)
          Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: 96,
              child: IgnorePointer(
                  child: DecoratedBox(
                      decoration: BoxDecoration(
                          gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                    Colors.transparent,
                    background(location).withValues(alpha: .88)
                  ]))))),
        if (narration.trim().isNotEmpty)
          PositionedDirectional(
              start: 16,
              end: 16,
              bottom: 14,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => showModalBottomSheet<void>(
                    context: context,
                    showDragHandle: true,
                    isScrollControlled: true,
                    builder: (sheetContext) => SafeArea(
                        top: false,
                        child: ConstrainedBox(
                            constraints: BoxConstraints(
                                maxHeight:
                                    MediaQuery.sizeOf(sheetContext).height *
                                        .6),
                            child: SingleChildScrollView(
                                padding:
                                    const EdgeInsets.fromLTRB(20, 0, 20, 24),
                                child: SelectableText(narration,
                                    style: const TextStyle(
                                        fontSize: 16, height: 1.6)))))),
                child: SizedBox(
                    height: 44,
                    child: Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: Text(narration,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: Colors.white.withValues(alpha: .76),
                                fontSize: 13,
                                height: 1.55,
                                shadows: const [
                                  Shadow(color: Colors.black38, blurRadius: 6)
                                ])))),
              )),
      ]));

  Widget _missingPerson() => ColoredBox(
      color: background(location),
      child: const Center(
          child: Icon(Icons.person_outline, size: 50, color: Colors.white54)));
}

class _EnvironmentPainter extends CustomPainter {
  _EnvironmentPainter(this.location, this.focus, this.rtl);
  final bool rtl;
  final String location, focus;

  @override
  void paint(Canvas canvas, Size size) {
    final sx = size.width / 360, sy = size.height / 260;
    canvas.save();
    canvas.scale(sx, sy);
    if (rtl) {
      canvas.translate(360, 0);
      canvas.scale(-1, 1);
    }
    final bounds = const Rect.fromLTWH(0, 0, 360, 260);
    final base = ExperienceEnvironment.background(location);
    canvas.drawRect(
        bounds,
        Paint()
          ..shader = LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                switch (location) {
                  'cafe' => const Color(0xFF61534B),
                  'cinema' => const Color(0xFF333858),
                  'restaurant' => const Color(0xFF59434A),
                  _ => const Color(0xFF425A66)
                },
                base
              ]).createShader(bounds));
    void rect(double x, double y, double w, double h, Color color,
            [double radius = 0]) =>
        canvas.drawRRect(
            RRect.fromRectAndRadius(
                Rect.fromLTWH(x, y, w, h), Radius.circular(radius)),
            Paint()..color = color);
    void line(double x, double y, double x2, double y2, Color color,
            double width) =>
        canvas.drawLine(
            Offset(x, y),
            Offset(x2, y2),
            Paint()
              ..color = color
              ..strokeWidth = width);
    final warm = const Color(0xFFE8C99C);
    if (location == 'cinema') {
      rect(24, 24, 194, 100, const Color(0xFF8589B3), 8);
      rect(30, 30, 182, 88, const Color(0xFF444A72), 5);
      final glow = Path()
        ..moveTo(118, 124)
        ..lineTo(0, 234)
        ..lineTo(255, 234)
        ..close();
      canvas.drawPath(
          glow,
          Paint()
            ..color =
                Colors.white.withValues(alpha: focus == 'screen' ? .09 : .04));
      for (var row = 0; row < 3; row++) {
        for (var seat = 0; seat < 4; seat++) {
          rect(16 + seat * 52.0 - row * 4, 151 + row * 34.0, 43, 28,
              const Color(0xFF37314D), 9);
        }
      }
      for (var i = 0; i < 5; i++) {
        canvas.drawCircle(Offset(12, 34 + i * 26.0), 2,
            Paint()..color = warm.withValues(alpha: .65));
      }
    } else if (location == 'cafe' || location == 'restaurant') {
      rect(22, 22, 152, 122, const Color(0xFF98ADAC), 10);
      rect(30, 30, 136, 106, const Color(0xFF829697), 6);
      line(97, 25, 97, 140, const Color(0xFF423E3A), 5);
      line(25, 84, 170, 84, const Color(0xFF423E3A), 5);
      rect(10, 153, 184, 14, const Color(0xFF453D35), 5);
      for (var i = 0; i < 3; i++) {
        rect(29 + i * 45.0, 138, 19, 15, const Color(0xFF3A4940), 3);
        canvas.drawOval(Rect.fromLTWH(22 + i * 45.0, 117, 32, 29),
            Paint()..color = const Color(0xFF566C56));
      }
      line(190, 0, 190, 42, const Color(0xFF342B26), 2);
      canvas.drawOval(const Rect.fromLTWH(165, 34, 50, 18),
          Paint()..color = warm.withValues(alpha: .7));
      canvas.drawOval(const Rect.fromLTWH(0, 190, 335, 100),
          Paint()..color = const Color(0xFF795B48));
      canvas.drawOval(const Rect.fromLTWH(7, 193, 320, 78),
          Paint()..color = const Color(0xFF9A795F));
      if (location == 'cafe') {
        canvas.drawOval(const Rect.fromLTWH(38, 213, 62, 16),
            Paint()..color = const Color(0xFFC6B7A2));
        rect(50, 194, 38, 27, const Color(0xFFE6D9C5), 7);
        canvas.drawOval(const Rect.fromLTWH(53, 191, 32, 9),
            Paint()..color = const Color(0xFF4C3326));
        canvas.drawArc(
            const Rect.fromLTWH(80, 197, 18, 17),
            -1.5,
            3,
            false,
            Paint()
              ..color = const Color(0xFFE6D9C5)
              ..strokeWidth = 4
              ..style = PaintingStyle.stroke);
      } else {
        canvas.drawOval(const Rect.fromLTWH(28, 211, 84, 29),
            Paint()..color = const Color(0xFFDBD0C4));
        canvas.drawOval(const Rect.fromLTWH(37, 217, 66, 16),
            Paint()..color = const Color(0xFFBCAEA1));
        line(17, 207, 17, 240, const Color(0xFFBCB5B1), 2);
        line(124, 207, 124, 240, const Color(0xFFBCB5B1), 2);
        rect(152, 173, 8, 39, warm, 2);
        canvas.drawOval(const Rect.fromLTWH(153, 164, 6, 12),
            Paint()..color = const Color(0xFFF9DEA1));
      }
    } else {
      // A neutral shared space, without inventing a real location or weather.
      rect(22, 24, 154, 129, const Color(0xFF526D79), 18);
      rect(32, 34, 134, 109, const Color(0xFF668692), 14);
      canvas.drawCircle(const Offset(75, 79), 23,
          Paint()..color = const Color(0xFFB4C6CC).withValues(alpha: .3));
      rect(5, 190, 211, 58, const Color(0xFF354B57), 25);
      rect(32, 175, 144, 27, const Color(0xFF46616C), 13);
    }
    if (focus == 'window' || focus == 'table' || focus == 'screen') {
      final center = focus == 'table'
          ? const Offset(85, 218)
          : focus == 'screen'
              ? const Offset(118, 74)
              : const Offset(94, 82);
      canvas.drawCircle(
          center,
          70,
          Paint()
            ..shader = RadialGradient(
                    colors: [warm.withValues(alpha: .16), Colors.transparent])
                .createShader(Rect.fromCircle(center: center, radius: 70)));
    }
    canvas.drawRect(
        bounds,
        Paint()
          ..shader = LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, base.withValues(alpha: 0), base])
              .createShader(bounds));
    canvas.restore();
  }

  @override
  bool shouldRepaint(_EnvironmentPainter old) =>
      old.location != location || old.focus != focus || old.rtl != rtl;
}
