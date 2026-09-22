import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/theme.dart';
import 'ai_pet_avatar.dart';
import 'ai_pet_desktop_controller.dart';
import 'ai_pets_page.dart';

class AIPetDesktopOverlay extends StatelessWidget {
  const AIPetDesktopOverlay({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Obx(() {
        final pet = AIPetDesktopController.to.pet.value;
        return LayoutBuilder(
          builder: (context, constraints) => Stack(
            fit: StackFit.expand,
            children: [
              child,
              if (pet != null)
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
    with SingleTickerProviderStateMixin {
  static const _size = 84.0;
  Offset? _position;
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 4200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  double _blinkAmount(double progress) {
    if (progress < .86 || progress > .96) return 0;
    if (progress < .91) return (progress - .86) / .05;
    return 1 - ((progress - .91) / .05);
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
              final float = math.sin(_controller.value * math.pi * 2) * 3;
              final blink = _blinkAmount(_controller.value);
              return Transform.translate(
                offset: Offset(0, float),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: context.vita.surface.withValues(alpha: .9),
                    shape: BoxShape.circle,
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x24000000),
                        blurRadius: 14,
                        offset: Offset(0, 5),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(5),
                    child: AIPetAvatar(
                      name:
                          '${widget.pet['adopted_companion_name'] ?? widget.pet['name'] ?? ''}',
                      imageUrl: '${widget.pet['avatar_url'] ?? ''}',
                      blinkAmount: blink,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
