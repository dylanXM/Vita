import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

enum PetNoticeKind { success, warning, error, info }

class PetPageNotice {
  const PetPageNotice(this.id, this.kind, this.text, this.onTap);
  final int id;
  final PetNoticeKind kind;
  final String text;
  final VoidCallback? onTap;
}

/// Page-owned feedback; nothing remains in the app-wide overlay after exit.
class PetDanmakuController extends ChangeNotifier {
  final List<PetPageNotice> _queue = [];
  int _nextID = 0;
  PetPageNotice? get current => _queue.isEmpty ? null : _queue.first;

  void show(PetNoticeKind kind, String title, String message, {VoidCallback? onTap}) {
    final parts = [title.trim(), message.trim()].where((s) => s.isNotEmpty).toSet();
    final text = parts.join(' · ');
    if (text.isEmpty || _queue.any((notice) => notice.text == text)) return;
    // Keep the visible line stable; discard the oldest queued line on bursts.
    if (_queue.length >= 4) _queue.removeAt(1);
    _queue.add(PetPageNotice(++_nextID, kind, text, onTap));
    notifyListeners();
  }

  void dismiss(int id) {
    if (current?.id != id) return;
    _queue.removeAt(0);
    notifyListeners();
  }
}

class PetDanmaku extends StatelessWidget {
  const PetDanmaku({super.key, required this.controller});
  final PetDanmakuController controller;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      final notice = controller.current;
      if (notice == null) return const SizedBox.shrink();
      return Positioned(top: 0, left: 0, right: 0,
        child: SafeArea(bottom: false, child: Padding(
          padding: const EdgeInsets.only(top: 72),
          child: _PetDanmakuLine(key: ValueKey(notice.id), notice: notice,
            onDone: () => controller.dismiss(notice.id)))));
    });
}

class _PetDanmakuLine extends StatefulWidget {
  const _PetDanmakuLine({super.key, required this.notice, required this.onDone});
  final PetPageNotice notice;
  final VoidCallback onDone;
  @override
  State<_PetDanmakuLine> createState() => _PetDanmakuLineState();
}

class _PetDanmakuLineState extends State<_PetDanmakuLine>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  static const _style = TextStyle(fontSize: 13, height: 1.2,
    fontWeight: FontWeight.w600, color: Color(0xFF513E2C));
  late final AnimationController _animation;
  Timer? _timer;
  final Stopwatch _staticWatch = Stopwatch();
  Duration _staticRemaining = const Duration(seconds: 6);
  double _chipWidth = 0;
  bool _reduced = false, _configured = false, _foreground = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _animation = AnimationController(vsync: this, duration: const Duration(seconds: 6));
    _animation.addStatusListener((status) {
      if (!_reduced && mounted && status == AnimationStatus.completed) widget.onDone();
    });
  }

  void _startStaticTimer() {
    if (!_foreground) return;
    _timer?.cancel();
    _staticWatch..reset()..start();
    _timer = Timer(_staticRemaining, () {
      _staticWatch.stop();
      if (mounted) widget.onDone();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduced = MediaQuery.disableAnimationsOf(context);
    final painter = TextPainter(text: TextSpan(text: widget.notice.text, style: _style),
      textDirection: Directionality.of(context), textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1)..layout();
    _chipWidth = painter.width + 58;
    painter.dispose();
    _animation.duration = Duration(milliseconds:
      ((MediaQuery.sizeOf(context).width + _chipWidth) / 75 * 1000).round());
    if (!_configured || reduced != _reduced) {
      _configured = true;
      _reduced = reduced;
      _timer?.cancel();
      _animation.stop();
      if (reduced) {
        _staticRemaining = const Duration(seconds: 6);
        _startStaticTimer();
      } else if (_foreground) { _animation.forward(from: 0); }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground) {
      _animation.stop();
      _timer?.cancel();
      if (_staticWatch.isRunning) {
        _staticWatch.stop();
        _staticRemaining -= _staticWatch.elapsed;
        if (_staticRemaining.isNegative) _staticRemaining = Duration.zero;
      }
    } else if (_reduced) { _startStaticTimer(); }
    else { _animation.forward(); }
  }

  @override
  Widget build(BuildContext context) {
    final warning = widget.notice.kind == PetNoticeKind.warning || widget.notice.kind == PetNoticeKind.error;
    final accent = widget.notice.kind == PetNoticeKind.error ? const Color(0xFFA55D50)
      : warning ? const Color(0xFFAC834D) : const Color(0xFF6B8050);
    final lineHeight = MediaQuery.textScalerOf(context).scale(13) * 1.2;
    final chipHeight = math.max(44.0, lineHeight * (_reduced ? 2.0 : 1.0) + 14);
    final chip = GestureDetector(onTap: widget.notice.onTap == null ? null : () {
      _animation.stop();
      widget.notice.onTap!();
      widget.onDone();
    }, child: Container(height: chipHeight, width: _chipWidth,
      padding: const EdgeInsets.symmetric(horizontal: 13),
      decoration: BoxDecoration(color: const Color(0xF5FFF2D9),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accent.withValues(alpha: .35)),
        boxShadow: const [BoxShadow(color: Color(0x294A301D), blurRadius: 10,
          offset: Offset(0, 3))]),
      child: Row(children: [Icon(warning ? Icons.info_outline_rounded : Icons.pets_rounded,
        size: 18, color: accent), const SizedBox(width: 8),
        Expanded(child: Text(widget.notice.text, maxLines: _reduced ? 2 : 1,
          softWrap: _reduced, overflow: TextOverflow.ellipsis, style: _style))])));
    return IgnorePointer(ignoring: widget.notice.onTap == null,
      child: Semantics(liveRegion: true, excludeSemantics: true,
      button: widget.notice.onTap != null,
      label: widget.notice.text,
      child: SizedBox(height: chipHeight + 12,
        child: LayoutBuilder(builder: (context, constraints) => ClipRect(
          child: AnimatedBuilder(animation: _animation, child: chip,
            builder: (context, child) {
              final width = constraints.maxWidth;
              if (_reduced) {
                return Center(child: SizedBox(width: math.min(math.max(0.0, width - 32), _chipWidth), child: child));
              }
              final rtl = Directionality.of(context) == TextDirection.rtl;
              final left = rtl ? -_chipWidth + (width + _chipWidth) * _animation.value
                : width - (width + _chipWidth) * _animation.value;
              return Stack(clipBehavior: Clip.none, children: [
                Positioned(left: left, top: 4, width: _chipWidth, height: chipHeight, child: child),
              ]);
            }))))));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _animation.dispose();
    super.dispose();
  }
}
