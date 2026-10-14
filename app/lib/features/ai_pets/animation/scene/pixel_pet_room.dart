import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../pet/pixel_pet.dart';
import '../pet/pet_motion_spec.dart';
import '../pet/pet_state_machine.dart';
import '../world_clock.dart';

/// Furniture and pets share one fixed canvas, independent of screen ratio.
class PixelPetRoom extends StatefulWidget {
  const PixelPetRoom({super.key, required this.name, required this.identity,
    required this.species, required this.machine, required this.clock,
    required this.onTap, required this.onBack, required this.onFeed,
    required this.onDrink, required this.onRest, required this.onSit,
    required this.busy});
  final String name, identity, species;
  final PetStateMachine machine;
  final WorldClock clock;
  final VoidCallback onTap, onBack, onFeed, onDrink, onRest, onSit;
  final bool busy;
  @override
  State<PixelPetRoom> createState() => _PixelPetRoomState();
}

class _PixelPetRoomState extends State<PixelPetRoom> {
  Offset _position = const Offset(.55, .81);
  Offset _velocity = Offset.zero;
  double _last = 0, _travel = 0;
  bool _walkRight = true;
  Map<PetState, double> _pose = {PetState.standing: 1};
  String get _season {
    final month = DateTime.now().month;
    return month >= 3 && month <= 5 ? 'spring' : month >= 6 && month <= 8
      ? 'summer' : month >= 9 && month <= 11 ? 'autumn' : 'winter';
  }

  void _advance(bool reduced) {
    final now = widget.clock.elapsedSeconds;
    final dt = (now - _last).clamp(0.0, .05).toDouble();
    _last = now;
    final state = widget.machine.state;
    final target = switch (state) {
      PetState.feeding => const Offset(.16, .735),
      PetState.drinking => const Offset(.29, .735),
      PetState.sleeping => const Offset(.84, .655),
      PetState.walking => Offset(_walkRight ? .70 : .38, .82),
      _ => const Offset(.55, .81),
    };
    if (reduced) {
      _position = target;
      _velocity = Offset.zero;
      _pose = Map.of(widget.machine.stateWeights);
      return;
    }
    if (dt == 0) return;
    final delta = target - _position;
    final distance = delta.distance;
    if (state == PetState.walking && distance < .025) _walkRight = !_walkRight;
    final desired = distance < .006 ? Offset.zero : delta / distance * math.min(.28, distance * 5);
    final blend = 1 - math.exp(-dt * 9);
    _velocity = Offset.lerp(_velocity, desired, blend)!;
    _position += _velocity * dt;
    _travel += ((_velocity.distance / .15).clamp(0.0, 1.0) - _travel) * blend;
    final weights = widget.machine.stateWeights;
    // Delay the bowl/bed pose until the pet reaches the furniture; blend limbs
    // both on arrival and when a new care action interrupts the old one.
    final walking = distance > .025 ? _travel : 0.0;
    for (final pose in PetState.values) {
      final targetWeight = (weights[pose] ?? 0) * (1 - walking)
        + (pose == PetState.walking ? walking : 0);
      _pose[pose] = (_pose[pose] ?? 0) + (targetWeight - (_pose[pose] ?? 0)) * blend;
    }
  }

  Widget _hotspot(Offset point, VoidCallback action, IconData icon, String label) => Positioned(
    left: point.dx * 1024 - 80, top: point.dy * 1536 - 80,
    width: 160, height: 160,
    child: Semantics(button: true, label: label.tr, child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.busy ? null : action,
      child: Align(alignment: Alignment.bottomCenter, child: DecoratedBox(
        decoration: BoxDecoration(color: const Color(0xB35B4030),
          borderRadius: BorderRadius.circular(18)),
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
      return ColoredBox(color: const Color(0xFF483629), child: Stack(children: [
        Positioned.fill(child: Center(child: FittedBox(fit: BoxFit.contain,
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
            _hotspot(const Offset(.145, .71), widget.onFeed, Icons.restaurant, 'aiPets.feeding'),
            _hotspot(const Offset(.29, .71), widget.onDrink, Icons.water_drop_outlined, 'aiPets.drink'),
            _hotspot(const Offset(.84, .65), widget.onRest, Icons.bedtime_outlined, 'aiPets.rest'),
            _hotspot(const Offset(.56, .84), widget.onSit, Icons.pets, 'aiPets.sit'),
            Positioned(left: _position.dx * 1024 - 100,
              top: _position.dy * 1536 - 180, width: 200, height: 200,
              child: GestureDetector(onTap: widget.busy ? null : widget.onTap,
                onPanUpdate: (details) => widget.machine.lookAt(details.delta / 12),
                onPanEnd: (_) => widget.machine.lookAt(Offset.zero),
                onPanCancel: () => widget.machine.lookAt(Offset.zero),
                child: PixelPet(identity: widget.identity, species: widget.species,
                  seconds: widget.clock.elapsedSeconds,
                  weights: reduced ? widget.machine.stateWeights : _pose,
                  look: widget.machine.look))),
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
