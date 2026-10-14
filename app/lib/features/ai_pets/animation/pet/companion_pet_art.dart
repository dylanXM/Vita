import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../ai_pet_avatar.dart';
import 'pet_motion_spec.dart';

/// The authored art contains pets only. Room furniture, lighting and shadows
/// are supplied by the scene, so moving a pet never moves a second bowl/bed.
class CompanionPetArt extends StatefulWidget {
  const CompanionPetArt({super.key, required this.name, required this.imageUrl,
    required this.seconds, this.state = PetState.standing,
    this.look = Offset.zero, this.facingLeft = true, this.reducedMotion = false,
    this.mouthTarget, this.onMouthOffsetReady});
  final String name, imageUrl;
  final double seconds;
  final PetState state;
  final Offset look;
  final bool facingLeft, reducedMotion;
  final Offset? mouthTarget;
  final ValueChanged<Offset>? onMouthOffsetReady;

  @override
  State<CompanionPetArt> createState() => _CompanionPetArtState();
}

String? aiPetRoomMotionAsset(String avatarUrl) {
  const root = 'asset://assets/ai_pets/';
  if (!avatarUrl.startsWith(root)) return null;
  final file = avatarUrl.substring(root.length);
  const breeds = {'cat_orange.png', 'cat_tuxedo.png', 'cat_ragdoll.png',
    'dog_corgi.png', 'dog_shiba.png', 'dog_retriever.png'};
  if (!breeds.contains(file)) return null;
  return 'assets/ai_pets/motion_v3/${file.replaceFirst('.png', '_room_motion.png')}';
}

class _CompanionPetArtState extends State<CompanionPetArt> {
  ui.Image? _atlas;
  ui.Image? _turnAtlas;
  List<double> _baselines = const [];
  List<double> _turnBaselines = const [];
  List<Offset?> _mouths = const [];
  final List<MapEntry<ImageStream, ImageStreamListener>> _streams = [];
  final List<Completer<ui.Image?>> _pending = [];
  int _generation = 0;
  int _frame = 0;
  int _row = 0;
  double _started = 0;
  List<int> _bridge = const [];
  bool? _facingLeft;
  double _turnStarted = 0;
  bool _turning = false;
  bool _turnTargetLeft = true;
  int _turnFrame = 0;
  int _turnFromFrame = 0;

  @override
  void initState() {
    super.initState();
    _started = widget.seconds;
    _load();
  }

  @override
  void didUpdateWidget(CompanionPetArt oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl != widget.imageUrl) _load();
  }

  void _detach() {
    for (final entry in _streams) entry.key.removeListener(entry.value);
    _streams.clear();
    for (final pending in _pending) {
      if (!pending.isCompleted) pending.complete(null);
    }
    _pending.clear();
  }

  Future<void> _load() async {
    _detach();
    final generation = ++_generation;
    _atlas?.dispose();
    _turnAtlas?.dispose();
    _atlas = null;
    _turnAtlas = null;
    _baselines = const [];
    _turnBaselines = const [];
    _mouths = const [];
    _facingLeft = null;
    _turning = false;
    final path = aiPetRoomMotionAsset(widget.imageUrl);
    if (path == null) return;
    final images = await Future.wait([
      _read(path),
      _read(path.replaceFirst('_room_motion.png', '_room_mask.png')),
      _read(path.replaceFirst('_room_motion.png', '_room_turn.png')),
      _read(path.replaceFirst('_room_motion.png', '_room_turn_mask.png')),
    ]);
    final image = images[0];
    final mask = images[1];
    if (!mounted || generation != _generation || image == null || mask == null ||
        image.width != mask.width || image.height != mask.height ||
        (image.width / image.height - 2 / 3).abs() > .02) {
      image?.dispose();
      mask?.dispose();
      images[2]?.dispose();
      images[3]?.dispose();
      return;
    }
    await _prepare(image, mask, generation);
    final turn = images[2];
    final turnMask = images[3];
    if (turn != null && turnMask != null && turn.width == turnMask.width &&
        turn.height == turnMask.height && (turn.width / turn.height - 1.5).abs() < .02) {
      await _prepare(turn, turnMask, generation, turn: true);
    } else {
      turn?.dispose();
      turnMask?.dispose();
    }
  }

  Future<ui.Image?> _read(String path) {
    final stream = AssetImage(path).resolve(ImageConfiguration.empty);
    final completer = Completer<ui.Image?>();
    _pending.add(completer);
    late final ImageStreamListener listener;
    listener = ImageStreamListener((info, _) {
      stream.removeListener(listener);
      if (!completer.isCompleted) completer.complete(info.image.clone());
      info.dispose();
    }, onError: (_, __) {
      stream.removeListener(listener);
      if (!completer.isCompleted) completer.complete(null);
    });
    _streams.add(MapEntry(stream, listener));
    stream.addListener(listener);
    return completer.future;
  }

  Future<void> _prepare(ui.Image image, ui.Image mask, int generation, {bool turn = false}) async {
    try {
      final bytes = await mask.toByteData(format: ui.ImageByteFormat.rawRgba);
      final colorBytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (!mounted || generation != _generation || bytes == null || colorBytes == null) {
        image.dispose();
        mask.dispose();
        return;
      }
      // Only once per load. Align grounded paws across generated frames without
      // scaling a seated/curled character back up to standing height.
      final pixels = bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes);
      final rgba = colorBytes.buffer.asUint8List(colorBytes.offsetInBytes, colorBytes.lengthInBytes);
      if (pixels[0] > 8) { image.dispose(); mask.dispose(); return; }
      final baselines = <double>[];
      final columns = turn ? 3 : 4;
      final rows = turn ? 2 : 6;
      final mouths = List<Offset?>.filled(columns * rows, null);
      for (var frame = 0; frame < columns * rows; frame++) {
        final left = (frame % columns * image.width / columns).round();
        final right = ((frame % columns + 1) * image.width / columns).round();
        final top = (frame ~/ columns * image.height / rows).round();
        final bottom = ((frame ~/ columns + 1) * image.height / rows).round();
        var ground = bottom - 1;
        var found = false;
        for (var y = bottom - 1; y >= top && !found; y--) {
          var solid = 0;
          for (var x = left; x < right; x++) {
            if (pixels[(y * image.width + x) * 4] > 48) solid++;
          }
          if (solid >= 4) { ground = y; found = true; }
        }
        baselines.add((ground - top + 1) / (bottom - top));
        if (!turn && (frame == 10 || frame == 11)) {
          mouths[frame] = _detectMouth(rgba, pixels, image.width, left, right, top, bottom);
        }
      }
      // Build a real premultiplied RGBA image once. The matte is never painted
      // over the character, and no per-frame color-filter/blend composition is
      // needed on the device renderer.
      for (var i = 0; i < rgba.length; i += 4) {
        final coverage = pixels[i] / 255.0;
        rgba[i] = (rgba[i] * coverage).round();
        rgba[i + 1] = (rgba[i + 1] * coverage).round();
        rgba[i + 2] = (rgba[i + 2] * coverage).round();
        rgba[i + 3] = (rgba[i + 3] * coverage).round();
      }
      final decoded = Completer<ui.Image>();
      ui.decodeImageFromPixels(rgba, image.width, image.height,
        ui.PixelFormat.rgba8888, decoded.complete);
      final transparent = await decoded.future;
      if (!mounted || generation != _generation) {
        transparent.dispose();
        image.dispose();
        mask.dispose();
        return;
      }
      setState(() {
        if (turn) {
          _turnAtlas?.dispose();
          _turnAtlas = transparent;
          _turnBaselines = baselines;
        } else {
          _atlas?.dispose();
          _atlas = transparent;
          _baselines = baselines;
          _mouths = mouths;
        }
      });
      if (!turn && mouths[10] != null && mouths[11] != null) {
        final mouth = (mouths[10]! + mouths[11]!) / 2;
        final baseline = (baselines[10] + baselines[11]) / 2;
        widget.onMouthOffsetReady?.call(Offset(.5 - mouth.dx, baseline - mouth.dy));
      }
      image.dispose();
      mask.dispose();
    } catch (_) {
      image.dispose();
      mask.dispose();
    }
  }

  int _rowFor(PetState state) => switch (state) {
    PetState.walking => 1,
    PetState.feeding || PetState.drinking => 2,
    PetState.sitting || PetState.tired || PetState.sick || PetState.thinking => 3,
    PetState.sleeping => 4,
    PetState.happy || PetState.levelUp => 5,
    _ => 0,
  };

  void _begin(int row) {
    final oldRow = _frame ~/ 4;
    final oldColumn = _frame % 4;
    final frames = <int>[];
    // Play the authored lowering/sitting frames backwards before standing up.
    // No crossfade of two complete silhouettes and no state-boundary photo swap.
    if (oldRow == 2 || oldRow == 3 || oldRow == 4 || oldRow == 5) {
      for (var col = oldColumn; col >= 0; col--) frames.add(oldRow * 4 + col);
      if (oldRow == 4) frames.addAll([15, 14, 13, 12]);
    }
    if (row == 4) frames.addAll([12, 13, 14, 15]);
    if (row != 0) frames.addAll(List.generate(4, (col) => row * 4 + col));
    else frames.add(0);
    _bridge = frames;
    _started = widget.seconds;
    _row = row;
  }

  int _resolveFrame() {
    final row = _rowFor(widget.state);
    if (widget.reducedMotion) {
      _row = row;
      _bridge = const [];
      return row == 0 ? 0 : row * 4 + 3;
    }
    if (row != _row) _begin(row);
    final elapsed = math.max(0.0, widget.seconds - _started);
    final step = (elapsed / .12).floor();
    if (step < _bridge.length) return _bridge[step];
    final loop = elapsed - _bridge.length * .12;
    return switch (row) {
      1 => 4 + (loop / .14).floor() % 4,
      2 => 10 + (loop / .24).floor() % 2,
      3 => 15,
      4 => 19,
      5 => 20 + (loop / .24).floor() % 4,
      _ => loop % 5.4 < 4.68 ? 0 : [1, 2, 3][((loop % 5.4 - 4.68) / .24).floor().clamp(0, 2).toInt()],
    };
  }

  bool _resolveTurn() {
    if (_facingLeft == null || widget.reducedMotion || _turnAtlas == null) {
      _facingLeft = widget.facingLeft;
      _turnFrame = widget.facingLeft ? 0 : 5;
      _turning = false;
      return false;
    }
    if ((!_turning && _facingLeft != widget.facingLeft) ||
        (_turning && _turnTargetLeft != widget.facingLeft)) {
      _turnFromFrame = _turning ? _turnFrame : (_facingLeft! ? 0 : 5);
      _turnTargetLeft = widget.facingLeft;
      _turnStarted = widget.seconds;
      _turning = true;
    }
    if (!_turning) return false;
    final end = _turnTargetLeft ? 0 : 5;
    final step = (math.max(0.0, widget.seconds - _turnStarted) / .09).floor();
    final count = (end - _turnFromFrame).abs() + 1;
    if (step >= count) {
      _facingLeft = _turnTargetLeft;
      _turning = false;
      return false;
    }
    _turnFrame = _turnFromFrame + (end >= _turnFromFrame ? step : -step);
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final atlas = _atlas;
    if (atlas == null) return AIPetAvatar(name: widget.name, imageUrl: widget.imageUrl);
    _frame = _resolveFrame();
    final turning = _resolveTurn();
    final frame = turning ? _turnFrame : _frame;
    return RepaintBoundary(child: CustomPaint(painter: _CompanionPetPainter(
      image: turning ? _turnAtlas! : atlas, frame: frame, seconds: widget.seconds,
      columns: turning ? 3 : 4, rows: turning ? 2 : 6,
      baseline: turning ? _turnBaselines[frame] : _baselines[frame],
      mouth: turning ? null : _mouths[frame], mouthTarget: widget.mouthTarget,
      sleep: _row == 4, facing: turning || _facingLeft! ? 1.0 : -1.0, look: widget.look,
      reduced: widget.reducedMotion), size: Size.infinite));
  }

  @override
  void dispose() {
    ++_generation;
    _detach();
    _atlas?.dispose();
    _turnAtlas?.dispose();
    super.dispose();
  }
}

class _CompanionPetPainter extends CustomPainter {
  const _CompanionPetPainter({required this.image, required this.frame,
    required this.seconds, required this.sleep, required this.facing,
    required this.look, required this.reduced, required this.baseline,
    required this.columns, required this.rows, required this.mouth, required this.mouthTarget});
  final ui.Image image;
  final int frame;
  final int columns, rows;
  final double seconds, facing, baseline;
  final bool sleep, reduced;
  final Offset look;
  final Offset? mouth, mouthTarget;

  @override
  void paint(Canvas canvas, Size size) {
    final cellW = image.width / columns;
    final cellH = image.height / rows;
    final source = Rect.fromLTWH(frame % columns * cellW, frame ~/ columns * cellH, cellW, cellH);
    final extent = math.min(size.width, size.height);
    final ground = Offset(size.width / 2, (size.height - extent) / 2 + extent);
    final target = Rect.fromLTWH((size.width - extent) / 2, ground.dy - extent * baseline, extent, extent);
    final breath = reduced ? 0.0 : math.sin(seconds * math.pi * 2 / (sleep ? 3.6 : 2.8)) * .004;
    canvas.save();
    final muzzle = mouth;
    final contact = mouthTarget;
    final eating = muzzle != null && contact != null;
    if (eating) {
      final actual = Offset(target.left + muzzle.dx * extent, target.top + muzzle.dy * extent);
      canvas.translate(contact.dx - actual.dx, contact.dy - actual.dy);
    }
    canvas.translate(ground.dx, ground.dy);
    canvas.rotate(reduced || eating ? 0 : look.dx * .018);
    canvas.scale(facing, eating ? 1.0 : 1 + breath);
    canvas.translate(-ground.dx, -ground.dy);
    canvas.drawImageRect(image, source, target, Paint()..filterQuality = FilterQuality.medium);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _CompanionPetPainter old) => image != old.image ||
    frame != old.frame || seconds != old.seconds || facing != old.facing ||
    look != old.look || reduced != old.reduced || sleep != old.sleep || baseline != old.baseline ||
    columns != old.columns || rows != old.rows || mouth != old.mouth || mouthTarget != old.mouthTarget;
}

/// Locate the pink nose/tongue only in the lowered muzzle region, inside the
/// pet matte. This reads the authored breed's pixels once, not every frame.
Offset? _detectMouth(Uint8List color, Uint8List mask, int width,
    int left, int right, int top, int bottom) {
  final cellW = right - left;
  final cellH = bottom - top;
  var weight = 0.0, sumX = 0.0, sumY = 0.0;
  for (var y = top + (cellH * .70).round(); y < bottom; y++) {
    for (var x = left + (cellW * .08).round(); x < left + (cellW * .45).round(); x++) {
      final i = (y * width + x) * 4;
      final r = color[i], g = color[i + 1], b = color[i + 2];
      if (mask[i] < 180 || r < 130 || b < 70 || r - g < 35 || r - b < 25 || (g - b).abs() > 25) continue;
      final w = (r - (g + b) / 2).toDouble();
      weight += w;
      sumX += (x - left + .5) / cellW * w;
      sumY += (y - top + .5) / cellH * w;
    }
  }
  return weight == 0 ? null : Offset(sumX / weight, sumY / weight);
}
