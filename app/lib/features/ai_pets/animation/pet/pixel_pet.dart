import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'pet_motion_spec.dart';

/// One skeletal pixel renderer shared by the cottage and desktop pet.
/// Every limb is animated continuously; changing state never swaps a photo.
class PixelPet extends StatelessWidget {
  const PixelPet({super.key, required this.identity, required this.species,
    required this.seconds, this.weights = const {PetState.standing: 1},
    this.look = Offset.zero, this.moving = false, this.facingLeft = false});
  final String identity, species;
  final double seconds;
  final Map<PetState, double> weights;
  final Offset look;
  final bool moving, facingLeft;

  @override
  Widget build(BuildContext context) => RepaintBoundary(child: CustomPaint(
    painter: _PixelPetPainter(identity, species, seconds, weights, look, moving, facingLeft),
    size: Size.infinite));
}

class _PixelPetPainter extends CustomPainter {
  _PixelPetPainter(this.identity, this.species, this.time, this.weights, this.look,
      this.moving, this.facingLeft);
  final String identity, species;
  final double time;
  final Map<PetState, double> weights;
  final Offset look;
  final bool moving, facingLeft;
  double weight(PetState state) => weights[state] ?? 0;

  @override
  void paint(Canvas canvas, Size size) {
    final key = '$identity $species'.toLowerCase();
    final dog = key.contains('dog') || key.contains('corgi') || key.contains('shiba') || key.contains('retriever') || key.contains('犬') || key.contains('狗');
    final tuxedo = key.contains('tuxedo') || key.contains('oreo') || key.contains('奶牛');
    final ragdoll = key.contains('ragdoll') || key.contains('布偶');
    final golden = key.contains('retriever') || key.contains('golden') || key.contains('金毛');
    final corgi = key.contains('corgi') || key.contains('柯基');
    final coat = tuxedo ? const Color(0xFF403E48) : ragdoll ? const Color(0xFFE6D6BD) : golden ? const Color(0xFFD8AB5F) : const Color(0xFFD88D46);
    final shade = ragdoll ? const Color(0xFF7B685C) : tuxedo ? const Color(0xFF30313B) : const Color(0xFFAA663A);
    const cream = Color(0xFFFFEBD0);
    const outline = Color(0xFF4C352E);
    final eye = ragdoll ? const Color(0xFF477E95) : const Color(0xFF302A2A);
    final sleep = weight(PetState.sleeping);
    final sit = weight(PetState.sitting) + weight(PetState.tired) * .4 + weight(PetState.sick) * .4;
    final feed = weight(PetState.feeding) + weight(PetState.drinking);
    final joy = weight(PetState.happy) + weight(PetState.levelUp);
    final walk = moving ? 1.0 : weight(PetState.walking);
    final breath = math.sin(time * math.pi * 2 / 3) * .28;
    final stride = math.sin(time * math.pi * 4);
    final unit = math.min(size.width, size.height) / 40;
    canvas.save();
    canvas.translate((size.width - 40 * unit) / 2, (size.height - 40 * unit) / 2);
    canvas.scale(unit);
    if (facingLeft) { canvas.translate(40, 0); canvas.scale(-1, 1); }
    final paint = Paint()..isAntiAlias = false;
    void block(double x, double y, double w, double h, Color color) {
      paint.color = color;
      canvas.drawRect(Rect.fromLTWH(x, y, w, h), paint);
    }
    void outlined(double x, double y, double w, double h, Color color) {
      block(x - 1, y - 1, w + 2, h + 2, outline);
      block(x, y, w, h, color);
    }
    // Contact shadow remains on the floor while the body breathes or hops.
    block(10, 35, 22, 1, const Color(0x243B2A20));
    block(13, 36, 17, 1, const Color(0x143B2A20));
    canvas.save();
    canvas.translate(0, breath - math.max(0, math.sin(time * math.pi * 2)) * joy * 1.6);
    final bodyY = 23 + sit * 2 + sleep * 5;
    final bodyH = 9 - sleep * 3;
    // Tail has a joint and a separate tip rather than moving the whole pet.
    canvas.save();
    canvas.translate(29, bodyY + 2);
    canvas.rotate(math.sin(time * math.pi * 2 / 3) * (.18 + joy * .25) - sleep * .35);
    outlined(0, -2, dog ? 7 : 3, dog ? 3 : 8, shade);
    if (!dog) { outlined(1, -5, 3, 4, coat); }
    if (dog && !golden) { outlined(4, -4, 3, 3, cream); }
    if (golden) { block(5, 1, 3, 2, coat); }
    canvas.restore();
    // Four paws move in diagonal pairs; sit/sleep folds the legs gradually.
    for (var i = 0; i < 4; i++) {
      final phase = i.isEven ? stride : -stride;
      final legH = (corgi ? 5.0 : 7.0) * (1 - sleep * .75 - sit * .3);
      canvas.save();
      canvas.translate(12 + i * 4.3, bodyY + bodyH - 1);
      canvas.rotate(phase * walk * .35 * (1 - sleep));
      outlined(-1, 0, 3, legH, i < 2 ? shade : coat);
      block(-1, legH - 1, 4, 2, cream);
      canvas.restore();
    }
    outlined(10, bodyY, 19, bodyH, coat);
    block(10, bodyY + bodyH - 3, 13, 3, cream);
    if (!dog && !tuxedo && !ragdoll) {
      for (var i = 0; i < 3; i++) { block(18 + i * 3, bodyY, 1, 4, shade); }
    }
    if (tuxedo) { block(11, bodyY + 2, 5, bodyH - 2, cream); }
    // Head lowers smoothly at bowls and nests into the sleeping body.
    canvas.save();
    canvas.translate(14 + look.dx * .8, 19 + feed * (3 + math.sin(time * math.pi * 2) * .7) + sleep * 7 + sit + look.dy * .4);
    canvas.rotate(feed * .14 + sleep * .18);
    final earColor = ragdoll ? shade : coat;
    if (golden) {
      outlined(-6, -8, 3, 8, shade); outlined(5, -8, 3, 8, shade);
    } else {
      outlined(-5, -12 + sleep, 3, 5, earColor); outlined(4, -12 + sleep, 3, 5, earColor);
      block(-4, -10 + sleep, 1, 2, const Color(0xFFCD8E85));
      block(5, -10 + sleep, 1, 2, const Color(0xFFCD8E85));
    }
    outlined(-5, -8, 12, 11, coat);
    if (ragdoll) { block(-5, -6, 12, 6, shade); }
    if (tuxedo || dog || ragdoll) { block(-1, -3, 5, 6, cream); }
    final blinkPhase = time % 6;
    final blink = blinkPhase > 5.65 ? math.sin((blinkPhase - 5.65) / .35 * math.pi) : 0.0;
    final droop = math.max(sleep, weight(PetState.tired) * .4 + weight(PetState.sick) * .5);
    final eyeH = math.max(.35, 2 * (1 - math.max(blink, droop)));
    block(-3, -4, 2, eyeH, eye); block(4, -4, 2, eyeH, eye);
    block(1, -1, 2, 1, outline);
    block(1, 1, 1, 1 + feed * .8, const Color(0xFFB97473));
    if (!dog) { block(-7, 0, 3, .7, outline); block(6, 0, 3, .7, outline); }
    canvas.restore();
    canvas.restore();
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _PixelPetPainter old) => true;
}
