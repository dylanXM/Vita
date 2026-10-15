import 'package:flutter/material.dart';

/// A six-card pile with one extra card revealed as the front card leaves.
class EncounterDeck extends StatefulWidget {
  const EncounterDeck({super.key, required this.itemCount, required this.itemBuilder});

  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;

  @override
  State<EncounterDeck> createState() => _EncounterDeckState();
}

class _EncounterDeckState extends State<EncounterDeck>
    with SingleTickerProviderStateMixin {
  late final AnimationController _motion;
  int _index = 0;
  double _offset = 0;
  double _from = 0;
  double _to = 0;
  bool _advance = false;

  @override
  void initState() {
    super.initState();
    _motion = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 240),
    )..addListener(() {
      setState(() {
        _offset = _from + (_to - _from) * Curves.easeOutCubic.transform(_motion.value);
      });
    })..addStatusListener((status) {
      if (status != AnimationStatus.completed) return;
      setState(() {
        if (_advance && _index + 1 < widget.itemCount) _index++;
        _offset = 0;
        _advance = false;
      });
    });
  }

  @override
  void didUpdateWidget(covariant EncounterDeck oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_index >= widget.itemCount) {
      _motion.stop();
      _index = widget.itemCount > 0 ? widget.itemCount - 1 : 0;
      _offset = 0;
      _advance = false;
    }
  }

  void _settle(double width, double velocity, {bool cancelled = false}) {
    final dismiss = !cancelled && _index + 1 < widget.itemCount &&
        (_offset.abs() > width * .25 || velocity.abs() > 700);
    final direction = _offset.abs() > 8 ? _offset : velocity;
    _from = _offset;
    _to = dismiss ? (direction < 0 ? -1 : 1) * (width + 80) : 0;
    _advance = dismiss;
    _motion.duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero : const Duration(milliseconds: 240);
    _motion.forward(from: 0);
  }

  @override
  void dispose() {
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.itemCount == 0) return const SizedBox.shrink();
    return LayoutBuilder(builder: (context, constraints) {
      final reduced = MediaQuery.disableAnimationsOf(context);
      final progress = _index + 1 < widget.itemCount
          ? (_offset.abs() / (constraints.maxWidth + 80))
              .clamp(0.0, 1.0).toDouble()
          : 0.0;
      return Stack(fit: StackFit.expand, children: [
        for (var depth = 6; depth >= 0; depth--)
          if (_index + depth < widget.itemCount)
            Positioned.fill(
              key: ValueKey(_index + depth),
              bottom: 40,
              child: IgnorePointer(
                ignoring: depth != 0 || _motion.isAnimating,
                child: ExcludeSemantics(
                  excluding: depth != 0,
                  child: TickerMode(
                    enabled: depth == 0,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onHorizontalDragStart: depth != 0 ? null : (_) {
                        _motion.stop();
                        _advance = false;
                      },
                      onHorizontalDragUpdate: depth != 0 ? null : (details) {
                        setState(() => _offset += details.delta.dx);
                      },
                      onHorizontalDragEnd: depth != 0 ? null : (details) => _settle(
                        constraints.maxWidth, details.primaryVelocity ?? 0,
                      ),
                      onHorizontalDragCancel: depth != 0 ? null : () => _settle(
                        constraints.maxWidth, 0, cancelled: true,
                      ),
                      child: Transform.translate(
                        offset: depth == 0 ? Offset(_offset, 0)
                            : Offset(0, (depth - progress) * 6),
                        child: Transform.rotate(
                          angle: depth == 0 && !reduced
                              ? (_offset / (constraints.maxWidth + 80))
                                  .clamp(-1.0, 1.0).toDouble() * .10
                              : 0,
                          child: Transform.scale(
                            alignment: Alignment.bottomCenter,
                            scale: depth == 0 ? 1 : 1 - (depth - progress) * .035,
                            child: Opacity(
                              opacity: depth == 6 ? progress : 1,
                              child: widget.itemBuilder(context, _index + depth),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
      ]);
    });
  }
}
