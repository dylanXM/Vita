import 'dart:async';
import 'dart:ui' as ui;

import 'package:flame/components.dart' show Vector2;
import 'package:flame/sprite.dart';
import 'package:flame/widgets.dart';
import 'package:flutter/material.dart';

import '../../ai_pet_avatar.dart';
import 'pet_motion_spec.dart';
import 'pet_state_machine.dart';

/// Flame displays authored pet poses; the portrait is never warped into a
/// silhouette that the artwork does not contain.
class PetPoseSheet extends StatefulWidget {
  const PetPoseSheet({
    super.key,
    required this.name,
    required this.avatarUrl,
    required this.sheetUrl,
    required this.actionSheetUrl,
    required this.machine,
  });

  final String name;
  final String avatarUrl;
  final String sheetUrl;
  final String actionSheetUrl;
  final PetStateMachine machine;

  @override
  State<PetPoseSheet> createState() => _PetPoseSheetState();
}

class _PetPoseSheetState extends State<PetPoseSheet> {
  Map<PetState, Sprite>? _poses;
  Map<PetState, SpriteAnimation>? _actions;
  Map<PetState, SpriteAnimationTicker>? _actionTickers;
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(PetPoseSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sheetUrl != widget.sheetUrl ||
        oldWidget.actionSheetUrl != widget.actionSheetUrl) {
      _load();
    }
  }

  Future<void> _load() async {
    final generation = ++_loadGeneration;
    setState(() {
      _poses = null;
      _actions = null;
      _actionTickers = null;
    });
    final image = await _loadImage(widget.sheetUrl);
    if (!mounted || generation != _loadGeneration) return;
    if (image == null || !_validSheet(image)) return;
    final poses = <PetState, Sprite>{
      PetState.standing: _cell(image, 0),
      PetState.sitting: _cell(image, 1),
      PetState.walking: _cell(image, 2),
      PetState.feeding: _cell(image, 3),
      PetState.drinking: _cell(image, 4),
      PetState.sleeping: _cell(image, 5),
    };
    setState(() => _poses = poses);

    final actionImage = await _loadImage(widget.actionSheetUrl);
    if (!mounted || generation != _loadGeneration) return;
    if (actionImage == null || !_validSheet(actionImage)) return;
    final frames = List.generate(6, (index) => _cell(actionImage, index));
    final animations = <PetState, SpriteAnimation>{
      PetState.walking: SpriteAnimation.spriteList(
        [frames[0], frames[1], frames[2], frames[1]],
        stepTime: .24,
      ),
      PetState.feeding: SpriteAnimation.spriteList(
        [frames[3], frames[4], frames[4], frames[3]],
        stepTime: .34,
      ),
      PetState.drinking: SpriteAnimation.spriteList(
        [poses[PetState.drinking]!, frames[5], frames[5]],
        stepTime: .38,
      ),
    };
    setState(() {
      _actions = animations;
      _actionTickers = animations.map(
        (state, animation) => MapEntry(state, animation.createTicker()),
      );
    });
  }

  bool _validSheet(ui.Image image) =>
      image.width >= 3 &&
      image.height >= 2 &&
      (image.width / image.height - 1.5).abs() < .02;

  Sprite _cell(ui.Image image, int index) {
    final width = image.width / 3.0;
    final height = image.height / 2.0;
    // Authored top-row paws can cross the atlas midpoint. Keep the lower-row
    // source inside its own artwork so feeding/drinking never show a stray paw.
    final lowerRowInset = index >= 3 ? height * .06 : 0.0;
    return Sprite(
      image,
      srcPosition:
          Vector2((index % 3) * width, (index ~/ 3) * height + lowerRowInset),
      srcSize: Vector2(width, height - lowerRowInset),
    );
  }

  Future<ui.Image?> _loadImage(String url) async {
    final ImageProvider provider;
    if (url.startsWith('asset://')) {
      provider = AssetImage(url.substring('asset://'.length));
    } else if (url.startsWith('https://') || url.startsWith('http://')) {
      provider = NetworkImage(url);
    } else {
      return null;
    }
    final stream = provider.resolve(ImageConfiguration.empty);
    final completer = Completer<ui.Image?>();
    late final ImageStreamListener listener;
    listener = ImageStreamListener((info, _) {
      if (!completer.isCompleted) completer.complete(info.image);
      stream.removeListener(listener);
    }, onError: (_, __) {
      if (!completer.isCompleted) completer.complete(null);
      stream.removeListener(listener);
    });
    stream.addListener(listener);
    return completer.future;
  }

  PetState _displayState() {
    // Two complete silhouettes cannot be blended without drawing two pets.
    var state = PetState.standing;
    var weight = -1.0;
    for (final entry in widget.machine.stateWeights.entries) {
      if (entry.value > weight) {
        state = entry.key;
        weight = entry.value;
      }
    }
    return state;
  }

  @override
  Widget build(BuildContext context) {
    final poses = _poses;
    if (poses == null) {
      return AIPetAvatar(name: widget.name, imageUrl: widget.avatarUrl);
    }
    final state = _displayState();
    final animation = _actions?[state];
    if (animation != null) {
      return SpriteAnimationWidget(
        key: ValueKey('${widget.sheetUrl}:${widget.actionSheetUrl}:$state'),
        animation: animation,
        animationTicker: _actionTickers![state]!,
        playing: !widget.machine.reducedMotion,
      );
    }
    return SpriteWidget(sprite: poses[state] ?? poses[PetState.standing]!);
  }
}
