import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../pet/companion_pet_art.dart';
import '../pet/pet_motion_spec.dart';
import '../pet/pet_state_machine.dart';
import '../world_clock.dart';

/// A fixed room canvas keeps every prop, contact shadow and pet on the same
/// coordinate system even when the full-screen viewport crops the room edges.
class CompanionPetRoom extends StatefulWidget {
  const CompanionPetRoom({super.key, required this.name, required this.imageUrl,
    required this.machine, required this.clock, required this.onTap,
    required this.onBack, required this.onFeed, required this.onDrink,
    required this.onRest, required this.onSit, required this.onWalk,
    required this.busy});
  final String name, imageUrl;
  final PetStateMachine machine;
  final WorldClock clock;
  final VoidCallback onTap, onBack, onFeed, onDrink, onRest, onSit, onWalk;
  final bool busy;

  @override
  State<CompanionPetRoom> createState() => _CompanionPetRoomState();
}

class _CompanionPetRoomState extends State<CompanionPetRoom> {
  static const _rug = Offset(.55, .81);
  // Actual food/water surfaces in the authored 1024 x 1536 room, not the
  // front wall/base of each bowl.
  static const _food = Offset(144.0 / 1024, 1045.0 / 1536);
  static const _water = Offset(295.0 / 1024, 1046.0 / 1536);
  static const _bed = Offset(.84, .65);
  Offset _position = _rug;
  Offset _velocity = Offset.zero;
  double _last = 0;
  double _departureAt = 0;
  double _turnUntil = 0;
  bool _facingLeft = true;
  int _walkIndex = 0;
  PetState _requested = PetState.standing;
  PetState _display = PetState.standing;
  List<Offset> _route = const [];
  Offset _mouthDelta = const Offset(.24, .08);
  static const _walkRoute = [Offset(.40, .79), Offset(.25, .74),
    Offset(.47, .86), Offset(.70, .81)];

  String get _season {
    final month = DateTime.now().month;
    return month >= 3 && month <= 5 ? 'spring' : month >= 6 && month <= 8
      ? 'summer' : month >= 9 && month <= 11 ? 'autumn' : 'winter';
  }

  double _extentAt(double y) => 210.0 + (y - .65).clamp(0.0, .2).toDouble() * 150;

  Offset _bowlStand(Offset surface) {
    // Solve the depth-dependent size and mouth-to-paws offset together.
    final y = (surface.dy + _mouthDelta.dy * 112.5 / 1536) /
      (1 - _mouthDelta.dy * 150 / 1536);
    final extent = _extentAt(y);
    return Offset(surface.dx + _mouthDelta.dx * extent / 1024,
      surface.dy + _mouthDelta.dy * extent / 1536);
  }

  void _mouthReady(Offset delta) {
    if (!mounted || (_mouthDelta - delta).distance < .001) return;
    setState(() {
      _mouthDelta = delta;
      if (_requested == PetState.feeding || _requested == PetState.drinking) {
        _route = [_destination(_requested)];
      }
    });
  }

  Offset _destination(PetState state) => switch (state) {
    PetState.feeding => _bowlStand(_food),
    PetState.drinking => _bowlStand(_water),
    PetState.sleeping => _bed,
    PetState.walking => _walkRoute[_walkIndex],
    PetState.happy || PetState.levelUp || PetState.thinking ||
      PetState.tired || PetState.sick => _position,
    _ => _rug,
  };

  void _advance(bool reduced) {
    final now = widget.clock.elapsedSeconds;
    final dt = (now - _last).clamp(0.0, .05).toDouble();
    _last = now;
    final requested = widget.machine.state;
    if (requested != _requested) {
      final previous = _display;
      _requested = requested;
      final target = _destination(requested);
      _route = [
        // Leave the bed via the open floor; do not walk through its back rim.
        if ((_position - target).distance > .03 &&
            _position.dx > .75 && _position.dy < .72) const Offset(.70, .76),
        if (requested == PetState.sleeping) const Offset(.70, .76),
        target,
      ];
      _departureAt = now + (previous == PetState.sleeping ? .96 :
        previous == PetState.sitting || previous == PetState.feeding ||
        previous == PetState.drinking || previous == PetState.tired ||
        previous == PetState.sick || previous == PetState.thinking ? .48 : 0);
      _display = (_position - target).distance > .018 ? PetState.walking : requested;
    }
    if (reduced) {
      _position = _destination(requested);
      _velocity = Offset.zero;
      _route = const [];
      _display = requested;
      _facingLeft = true;
      return;
    }
    if (dt == 0 || now < _departureAt) return;
    if (now < _turnUntil) {
      _velocity = Offset.zero;
      _display = PetState.standing;
      return;
    }
    if (_route.isEmpty) {
      if (requested == PetState.walking) _route = [_walkRoute[_walkIndex]];
      else { _display = requested; return; }
    }
    final delta = _route.first - _position;
    final distance = delta.distance;
    if (distance < .009) {
      _route = _route.skip(1).toList();
      if (_route.isEmpty) {
        _velocity = Offset.zero;
        if (requested == PetState.walking) {
          _walkIndex = (_walkIndex + 1) % _walkRoute.length;
        } else {
          if (!_facingLeft) {
            _facingLeft = true;
            _turnUntil = now + .54;
            _display = PetState.standing;
          } else { _display = requested; }
        }
      }
      return;
    }
    final left = delta.dx < 0;
    if (delta.dx.abs() > .012 && left != _facingLeft) {
      // Brake before the authored pivot; never glide while turning.
      _velocity = Offset.lerp(_velocity, Offset.zero, 1 - math.exp(-dt * 12))!;
      _position += _velocity * dt;
      _display = PetState.standing;
      if (_velocity.distance > .025) return;
      _velocity = Offset.zero;
      _facingLeft = left;
      _turnUntil = now + .54;
      return;
    }
    final speed = math.min(.30, distance * 5);
    final desired = delta / distance * speed;
    _velocity = Offset.lerp(_velocity, desired, 1 - math.exp(-dt * 10))!;
    _position += _velocity * dt;
    _display = PetState.walking;
  }

  Widget _hotspot(Offset point, VoidCallback action, IconData icon, String label) => Positioned(
    left: point.dx * 1024 - 80, top: point.dy * 1536 - 80,
    width: 160, height: 160,
    child: Semantics(button: true, label: label.tr,
      child: GestureDetector(behavior: HitTestBehavior.opaque,
        onTap: widget.busy ? null : action,
        child: Align(alignment: Alignment.bottomCenter,
          child: DecoratedBox(decoration: BoxDecoration(
            color: const Color(0x995B4030), borderRadius: BorderRadius.circular(18)),
            child: Padding(padding: const EdgeInsets.all(6),
              child: Icon(icon, color: const Color(0xFFFFEBCD), size: 26)))))));

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([widget.clock, widget.machine]),
    builder: (context, _) {
      final reduced = MediaQuery.disableAnimationsOf(context);
      _advance(reduced);
      final hour = widget.clock.dayProgress * 24;
      final night = hour < 6 ? 1.0 : hour < 8 ? (8 - hour) / 2
        : hour < 18 ? 0.0 : hour < 20 ? (hour - 18) / 2 : 1.0;
      final extent = _extentAt(_position.dy);
      final contact = Offset(_position.dx * 1024, _position.dy * 1536);
      final surface = _display == PetState.feeding ? _food :
        _display == PetState.drinking ? _water : null;
      final mouthTarget = surface == null ? null :
        Offset(surface.dx * 1024 - (contact.dx - extent / 2),
          surface.dy * 1536 - (contact.dy - extent));
      final tint = <double>[
        1.0 - night * .15, 0, 0, 0, 0,
        0, .96 - night * .12, 0, 0, 0,
        0, 0, .88 + night * .02, 0, 0,
        0, 0, 0, 1, 0,
      ];
      return ColoredBox(color: const Color(0xFF483629), child: Stack(children: [
        Positioned.fill(child: Center(child: FittedBox(fit: BoxFit.cover,
          clipBehavior: Clip.hardEdge,
          child: SizedBox(width: 1024, height: 1536, child: Stack(children: [
            Positioned.fill(child: AnimatedSwitcher(
              duration: reduced ? Duration.zero : const Duration(seconds: 2),
              child: Stack(key: ValueKey(_season), fit: StackFit.expand, children: [
                Image.asset('assets/ai_pets/cottage_v2/${_season}_day.png',
                  filterQuality: FilterQuality.none, fit: BoxFit.fill),
                Opacity(opacity: night, child: Image.asset(
                  'assets/ai_pets/cottage_v2/${_season}_night.png',
                  filterQuality: FilterQuality.none, fit: BoxFit.fill)),
              ]))),
            _hotspot(_food, widget.onFeed, Icons.restaurant, 'aiPets.feeding'),
            _hotspot(_water, widget.onDrink, Icons.water_drop_outlined, 'aiPets.drink'),
            _hotspot(_bed, widget.onRest, Icons.bedtime_outlined, 'aiPets.rest'),
            _hotspot(const Offset(.56, .86), widget.onSit, Icons.pets, 'aiPets.sit'),
            _hotspot(const Offset(.13, .51), widget.onWalk, Icons.directions_walk, 'aiPets.walk'),
            Positioned.fill(child: IgnorePointer(child: CustomPaint(
              painter: _RoomContactPainter(contact: contact, extent: extent,
                state: _display, time: widget.clock.elapsedSeconds,
                night: night, reduced: reduced, water: _water)))),
            Positioned(left: contact.dx - extent / 2,
              top: contact.dy - extent, width: extent, height: extent,
              child: Semantics(button: true, label: widget.name,
                child: GestureDetector(behavior: HitTestBehavior.opaque,
                  onTap: widget.busy ? null : widget.onTap,
                  onPanUpdate: (details) => widget.machine.lookAt(details.delta / 12),
                  onPanEnd: (_) => widget.machine.lookAt(Offset.zero),
                  onPanCancel: () => widget.machine.lookAt(Offset.zero),
                  child: ColorFiltered(colorFilter: ColorFilter.matrix(tint),
                    child: CompanionPetArt(name: widget.name, imageUrl: widget.imageUrl,
                      seconds: widget.clock.elapsedSeconds, state: _display,
                      look: widget.machine.look, facingLeft: _facingLeft,
                      reducedMotion: reduced, mouthTarget: mouthTarget,
                      onMouthOffsetReady: _mouthReady))))),
            // The near rim belongs in front of the lowered muzzle. Reuse the
            // exact room pixels so the bowl is neither redrawn nor duplicated.
            if (surface != null)
              Positioned.fill(child: IgnorePointer(child: ClipPath(
                clipper: _BowlFrontClipper(surface: surface),
                child: Stack(fit: StackFit.expand, children: [
                  Image.asset('assets/ai_pets/cottage_v2/${_season}_day.png',
                    filterQuality: FilterQuality.none, fit: BoxFit.fill),
                  Opacity(opacity: night, child: Image.asset(
                    'assets/ai_pets/cottage_v2/${_season}_night.png',
                    filterQuality: FilterQuality.none, fit: BoxFit.fill)),
                ])))),
          ]))))),
        SafeArea(child: Padding(padding: const EdgeInsets.all(16), child: Row(children: [
          IconButton(onPressed: widget.onBack, icon: const Icon(Icons.arrow_back),
            color: const Color(0xFFFFEBCD), style: IconButton.styleFrom(
              backgroundColor: const Color(0xCC483629))),
          const SizedBox(width: 12),
          Expanded(child: Text(widget.name, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Color(0xFFFFEBCD), fontSize: 24,
              fontWeight: FontWeight.w700, shadows: [Shadow(blurRadius: 5, color: Colors.black54)]))),
        ]))),
      ]));
    });
}

class _RoomContactPainter extends CustomPainter {
  const _RoomContactPainter({required this.contact, required this.extent,
    required this.state, required this.time, required this.night, required this.reduced, required this.water});
  final Offset contact, water;
  final double extent, time, night;
  final PetState state;
  final bool reduced;

  @override
  void paint(Canvas canvas, Size size) {
    final shadow = Paint()..color = Color.fromRGBO(47, 28, 18, .18 + night * .10)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
    canvas.drawOval(Rect.fromCenter(center: contact + const Offset(0, -4),
      width: extent * (state == PetState.sleeping ? .72 : .58), height: extent * .10), shadow);
    if (reduced) return;
    if (state == PetState.drinking) {
      final phase = (time * 1.3) % 1;
      final ripple = Paint()..color = Color.fromRGBO(194, 224, 232, (1 - phase) * .5)
        ..style = PaintingStyle.stroke..strokeWidth = 1.8;
      canvas.drawOval(Rect.fromCenter(center: Offset(water.dx * 1024, water.dy * 1536),
        width: 12 + phase * 32, height: 3 + phase * 9), ripple);
    }
    if (state == PetState.happy || state == PetState.levelUp) {
      final phase = time % 1.6 / 1.6;
      final paint = Paint()..color = Color.fromRGBO(247, 188, 137, (1 - phase) * .7);
      for (var i = 0; i < 3; i++) {
        final point = contact + Offset((i - 1) * 28.0, -extent * .9 - phase * 30);
        canvas.drawCircle(point, 2.5, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _RoomContactPainter old) => contact != old.contact ||
    extent != old.extent || state != old.state || time != old.time ||
    night != old.night || reduced != old.reduced || water != old.water;
}

class _BowlFrontClipper extends CustomClipper<Path> {
  const _BowlFrontClipper({required this.surface});
  final Offset surface;
  @override
  Path getClip(Size size) {
    final center = Offset(surface.dx * size.width, surface.dy * size.height);
    final bowl = Path()..addOval(Rect.fromCenter(center: center + const Offset(0, 20),
      width: 128, height: 84));
    final front = Path()..addRect(Rect.fromLTWH(center.dx - 70, center.dy + 10, 140, 64));
    return Path.combine(PathOperation.intersect, bowl, front);
  }
  @override
  bool shouldReclip(covariant _BowlFrontClipper old) => surface != old.surface;
}
