import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'animation/pet/companion_pet_art.dart';
import 'animation/pet/pet_motion_spec.dart';
import 'animation/world_clock.dart';
import 'ai_pet_desktop_controller.dart';
import '../shell/shell_page.dart';

class AIPetDesktopOverlay extends StatelessWidget {
  const AIPetDesktopOverlay({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Obx(() {
        final desktop = AIPetDesktopController.to;
        final pet = desktop.pet.value;
        final petHomeVisible = desktop.petHomeVisible.value;
        final worldHomeVisible = desktop.currentRoute.value == '/shell' &&
            ShellController.to.index.value == 0;
        return LayoutBuilder(
          builder: (context, constraints) => Stack(
            fit: StackFit.expand,
            children: [
              child,
              if (pet != null && !petHomeVisible && !worldHomeVisible)
                _DraggablePet(
                  key: ValueKey('${pet['adopted_companion_id'] ?? pet['id'] ?? ''}'),
                  pet: pet,
                  availableSize: constraints.biggest,
                ),
            ],
          ),
        );
      });
}

class _DraggablePet extends StatefulWidget {
  const _DraggablePet({super.key, required this.pet, required this.availableSize});

  final Map<String, dynamic> pet;
  final Size availableSize;

  @override
  State<_DraggablePet> createState() => _DraggablePetState();
}

class _DraggablePetState extends State<_DraggablePet>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  static const _size = 84.0;
  Offset? _position;
  late final WorldClock _clock;
  bool _reduced = false;
  bool _foreground = true;
  bool _dragging = false;
  bool _facingLeft = true;
  Timer? _pettingTimer;
  bool _petting = false;
  double _pettingStarted = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _clock = WorldClock(vsync: this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pettingTimer?.cancel();
    _clock.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduced = MediaQuery.disableAnimationsOf(context);
    if (_reduced || !_foreground) { _clock.pause(); }
    else { _clock.resume(); }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground && !_reduced) { _clock.resume(); }
    else { _clock.pause(); }
  }

  void _pet() {
    _pettingTimer?.cancel();
    setState(() {
      _petting = true;
      _pettingStarted = _clock.elapsedSeconds;
    });
    _pettingTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _petting = false);
    });
  }

  void _startDrag() {
    _pettingTimer?.cancel();
    setState(() {
      _petting = false;
      _dragging = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.paddingOf(context);
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    final maxX = math.max(8.0, widget.availableSize.width - _size - 8);
    final maxY = math.max(
      padding.top + 8,
      widget.availableSize.height - _size - keyboard - padding.bottom - 76,
    );
    final fallback = Offset(maxX, maxY);
    final current = _position ?? fallback;
    final position = Offset(
      current.dx.clamp(8.0, maxX),
      current.dy.clamp(padding.top + 8, maxY),
    );
    return Positioned(
      left: position.dx,
      top: position.dy,
      width: _size,
      height: _size,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _pet,
        onPanStart: (_) => _startDrag(),
        onPanEnd: (_) => setState(() => _dragging = false),
        onPanCancel: () => setState(() => _dragging = false),
        onPanUpdate: (details) => setState(() {
          if (details.delta.dx.abs() > 1) _facingLeft = details.delta.dx < 0;
          _position = Offset(
            (position.dx + details.delta.dx).clamp(8.0, maxX),
            (position.dy + details.delta.dy).clamp(padding.top + 8, maxY),
          );
        }),
        child: Semantics(
          button: true,
          label:
              '${widget.pet['adopted_companion_name'] ?? widget.pet['name'] ?? ''}',
          child: AnimatedBuilder(
            animation: _clock,
            builder: (context, _) {
              final progress = ((_clock.elapsedSeconds - _pettingStarted) / 2)
                  .clamp(0.0, 1.0);
              return Stack(fit: StackFit.expand, children: [
                Positioned(left: 18, right: 18, bottom: 0, height: 7,
                  child: DecoratedBox(decoration: BoxDecoration(
                    color: const Color(0x19000000),
                    borderRadius: BorderRadius.circular(24)))),
                CompanionPetArt(
                  name: '${widget.pet['adopted_companion_name'] ?? widget.pet['name'] ?? ''}',
                  imageUrl: '${widget.pet['avatar_url'] ?? ''}',
                  seconds: _clock.elapsedSeconds,
                  state: _dragging
                      ? PetState.walking
                      : _petting ? PetState.happy : PetState.standing,
                  facingLeft: _facingLeft,
                  reducedMotion: _reduced,
                ),
                if (_petting)
                  Positioned(
                    right: 7,
                    top: _reduced ? 5 : 17 - progress * 14,
                    child: IgnorePointer(
                      child: ExcludeSemantics(
                        child: Opacity(
                          opacity: _reduced ? 1 : math.sin(progress * math.pi),
                          child: const Icon(Icons.favorite_rounded,
                              size: 17, color: Color(0xFFEBA1AE)),
                        ),
                      ),
                    ),
                  ),
              ]);
            },
          ),
        ),
      ),
    );
  }
}
