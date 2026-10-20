import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../shared/media_image.dart';

/// Lives outside the resizing chat Scaffold, so the cover and blur transition
/// stay anchored to the full screen when the keyboard opens.
class EncounterChatBackdrop extends StatefulWidget {
  const EncounterChatBackdrop({super.key, required this.cover});

  final String cover;

  @override
  State<EncounterChatBackdrop> createState() => _EncounterChatBackdropState();
}

class _EncounterChatBackdropState extends State<EncounterChatBackdrop> {
  late Widget _portrait;

  @override
  void initState() {
    super.initState();
    _portrait = _buildPortrait();
  }

  @override
  void didUpdateWidget(covariant EncounterChatBackdrop oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.cover != widget.cover) _portrait = _buildPortrait();
  }

  // Keep the image widgets stable across keyboard and message updates.
  Widget _buildPortrait() => widget.cover.trim().isEmpty
        ? const ColoredBox(color: Color(0xFF151016))
        : VitaMediaImage(
            url: widget.cover,
            fit: BoxFit.cover,
            placeholderBuilder: (_) => const ColoredBox(color: Color(0xFF151016)),
            errorBuilder: (_, __, ___) => const ColoredBox(color: Color(0xFF151016)),
          );

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(child: RepaintBoundary(child: ClipRect(
      child: Stack(fit: StackFit.expand, children: [
        _portrait,
        ShaderMask(
          blendMode: BlendMode.dstIn,
          shaderCallback: (rect) => const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.transparent, Colors.transparent, Colors.white, Colors.white],
            stops: [0, .5, .86, 1],
          ).createShader(rect),
          child: ImageFiltered(
            imageFilter: ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24, tileMode: TileMode.clamp),
            child: _portrait,
          ),
        ),
        const DecoratedBox(decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0x550D0810), Color(0x220D0810), Color(0x880D0810)],
            stops: [0, .5, 1],
          ),
        )),
      ]),
    )));
  }
}
