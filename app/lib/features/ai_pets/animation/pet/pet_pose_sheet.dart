import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../ai_pet_avatar.dart';
import 'pet_motion_spec.dart';
import 'pet_state_machine.dart';

/// Six full-body poses in reading order: stand, sit, walk / eat, drink, sleep.
/// A missing or invalid sheet falls back to the unwarped pet portrait.
class PetPoseSheet extends StatefulWidget {
  const PetPoseSheet({
    super.key,
    required this.name,
    required this.avatarUrl,
    required this.sheetUrl,
    required this.actionSheetUrl,
    required this.machine,
    required this.worldTime,
  });

  final String name;
  final String avatarUrl;
  final String sheetUrl;
  final String actionSheetUrl;
  final PetStateMachine machine;
  final double worldTime;

  @override
  State<PetPoseSheet> createState() => _PetPoseSheetState();
}

class _PetPoseSheetState extends State<PetPoseSheet> {
  ui.Image? _image;
  ui.Image? _actions;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
    _loadActions();
  }

  @override
  void didUpdateWidget(PetPoseSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sheetUrl != widget.sheetUrl) _load();
    if (oldWidget.actionSheetUrl != widget.actionSheetUrl) _loadActions();
  }

  Future<void> _load() async {
    final url = widget.sheetUrl;
    _image = null;
    _failed = false;
    final ImageProvider provider;
    if (url.startsWith('asset://')) {
      provider = AssetImage(url.substring('asset://'.length));
    } else if (url.startsWith('https://') || url.startsWith('http://')) {
      provider = NetworkImage(url);
    } else {
      _failed = true;
      return;
    }
    try {
      final image = await _resolve(provider);
      if (!mounted || url != widget.sheetUrl) return;
      setState(() {
        _image = image;
        _failed = image.width < 3 ||
            image.height < 2 ||
            (image.width / image.height - 1.5).abs() > .02;
      });
    } catch (_) {
      if (mounted && url == widget.sheetUrl) setState(() => _failed = true);
    }
  }

  Future<void> _loadActions() async {
    final url = widget.actionSheetUrl;
    _actions = null;
    if (url.isEmpty) return;
    final ImageProvider provider;
    if (url.startsWith('asset://')) {
      provider = AssetImage(url.substring('asset://'.length));
    } else if (url.startsWith('https://') || url.startsWith('http://')) {
      provider = NetworkImage(url);
    } else {
      return;
    }
    try {
      final image = await _resolve(provider);
      if (!mounted || url != widget.actionSheetUrl) return;
      if (image.width >= 3 &&
          image.height >= 2 &&
          (image.width / image.height - 1.5).abs() <= .02) {
        setState(() => _actions = image);
      }
    } catch (_) {
      // The six-pose sheet remains usable if the loop sheet cannot load.
    }
  }

  Future<ui.Image> _resolve(ImageProvider provider) {
    final stream = provider.resolve(ImageConfiguration.empty);
    final completer = Completer<ui.Image>();
    late final ImageStreamListener listener;
    listener = ImageStreamListener((info, _) {
      if (!completer.isCompleted) completer.complete(info.image);
      stream.removeListener(listener);
    }, onError: (error, stack) {
      if (!completer.isCompleted) completer.completeError(error, stack);
      stream.removeListener(listener);
    });
    stream.addListener(listener);
    return completer.future;
  }

  @override
  Widget build(BuildContext context) {
    final image = _image;
    if (image == null || _failed) {
      return AIPetAvatar(name: widget.name, imageUrl: widget.avatarUrl);
    }
    return CustomPaint(
      painter: _PoseSheetPainter(
        image: image,
        actions: _actions,
        weights: widget.machine.stateWeights,
        worldTime: widget.worldTime,
      ),
      child: const SizedBox.expand(),
    );
  }
}

class _PoseSheetPainter extends CustomPainter {
  _PoseSheetPainter({
    required this.image,
    required this.actions,
    required this.weights,
    required this.worldTime,
  });

  final ui.Image image;
  final ui.Image? actions;
  final Map<PetState, double> weights;
  final double worldTime;

  int _cellFor(PetState state) => switch (state) {
        PetState.sitting => 1,
        PetState.walking => 2,
        PetState.feeding => 3,
        PetState.drinking => 4,
        PetState.sleeping => 5,
        _ => 0,
      };

  @override
  void paint(Canvas canvas, Size size) {
    final edge = math.min(size.width, size.height);
    final dest = Rect.fromLTWH(
      (size.width - edge) / 2,
      (size.height - edge) / 2,
      edge,
      edge,
    );
    // A pose sheet contains complete silhouettes, not layers of one rig.
    // Blending two cells draws both bodies and makes a visible double image.
    // Select one authored silhouette per frame; the state machine still blends
    // position, effects and other scene motion independently.
    var state = PetState.standing;
    var strongest = -1.0;
    for (final entry in weights.entries) {
      if (entry.value > strongest) {
        strongest = entry.value;
        state = entry.key;
      }
    }

    final actionImage = actions;
    if (actionImage != null) {
      if (state == PetState.walking) {
        final frame = ((worldTime * 360).floor()) % 3;
        _drawCell(canvas, actionImage, frame, dest);
        return;
      }
      if (state == PetState.feeding) {
        final frame = ((worldTime * 80).floor()) % 2;
        _drawCell(canvas, actionImage, 3 + frame, dest);
        return;
      }
      if (state == PetState.drinking) {
        final frame = ((worldTime * 100).floor()) % 2;
        _drawCell(
            canvas, frame == 0 ? image : actionImage, frame == 0 ? 4 : 5, dest);
        return;
      }
    }
    final breath = state == PetState.sleeping ? .007 : .004;
    final rise = breath * edge * math.sin(worldTime * math.pi * 2 * 12);
    _drawCell(canvas, image, _cellFor(state), dest.shift(Offset(0, rise)));
  }

  void _drawCell(Canvas canvas, ui.Image sheet, int index, Rect dest) {
    final cellWidth = sheet.width / 3.0;
    final cellHeight = sheet.height / 2.0;
    canvas.drawImageRect(
      sheet,
      Rect.fromLTWH(
        (index % 3) * cellWidth,
        (index ~/ 3) * cellHeight,
        cellWidth,
        cellHeight,
      ),
      dest,
      Paint()..filterQuality = FilterQuality.low,
    );
  }

  @override
  bool shouldRepaint(covariant _PoseSheetPainter oldDelegate) =>
      oldDelegate.image != image ||
      oldDelegate.actions != actions ||
      oldDelegate.worldTime != worldTime ||
      !_sameWeights(oldDelegate.weights, weights);

  bool _sameWeights(Map<PetState, double> a, Map<PetState, double> b) {
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      if (b[entry.key] != entry.value) return false;
    }
    return true;
  }
}
