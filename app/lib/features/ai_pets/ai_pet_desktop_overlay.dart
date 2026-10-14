import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'animation/pet/pixel_pet.dart';
import 'ai_pet_desktop_controller.dart';
import 'ai_pet_home_page.dart';
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
                  pet: pet,
                  availableSize: constraints.biggest,
                ),
            ],
          ),
        );
      });
}

class _DraggablePet extends StatefulWidget {
  const _DraggablePet({required this.pet, required this.availableSize});

  final Map<String, dynamic> pet;
  final Size availableSize;

  @override
  State<_DraggablePet> createState() => _DraggablePetState();
}

class _DraggablePetState extends State<_DraggablePet>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  static const _size = 84.0;
  Offset? _position;
  late final AnimationController _controller;
  bool _reduced = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    )..repeat();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduced = MediaQuery.disableAnimationsOf(context);
    if (_reduced) { _controller.stop(); }
    else if (!_controller.isAnimating) { _controller.repeat(); }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_reduced) {
      _controller.repeat();
    } else { _controller.stop(); }
  }

  void _openHome() {
    final companionID = '${widget.pet['adopted_companion_id'] ?? ''}';
    if (companionID.isEmpty) return;
    Get.to(() => AIPetHomePage(
          companionId: companionID,
          name:
              '${widget.pet['adopted_companion_name'] ?? widget.pet['name'] ?? ''}',
          avatarUrl: '${widget.pet['avatar_url'] ?? ''}',
          species: '${widget.pet['species'] ?? ''}',
        ));
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
        onTap: _openHome,
        onPanUpdate: (details) => setState(() {
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
            animation: _controller,
            builder: (context, _) {
              return PixelPet(
                identity: '${widget.pet['avatar_url'] ?? ''} ${widget.pet['name'] ?? ''}',
                species: '${widget.pet['species'] ?? ''}',
                seconds: _controller.value * 6,
              );
            },
          ),
        ),
      ),
    );
  }
}
