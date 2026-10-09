import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'theme.dart';

enum _NoticeKind { success, error, warning, info }

/// Compact feedback for an action, separate from chat and system messages.
class VitaNotice {
  const VitaNotice._();

  static OverlayEntry? _current;
  static int _generation = 0;

  static void success(String title, String message) =>
      _show(_NoticeKind.success, title, message);

  static void error(String title, String message) =>
      _show(_NoticeKind.error, title, message);

  static void warning(String title, String message) =>
      _show(_NoticeKind.warning, title, message);

  static void info(String title, String message) =>
      _show(_NoticeKind.info, title, message);

  static void _show(_NoticeKind kind, String title, String message) {
    final overlay = Get.key.currentState?.overlay;
    if (overlay == null) return;
    _current?.remove();
    _current?.dispose();
    final generation = ++_generation;
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _NoticeBanner(
        kind: kind,
        title: title,
        message: message,
        onDismissed: () {
          if (_generation != generation) return;
          entry.remove();
          entry.dispose();
          _current = null;
        },
      ),
    );
    _current = entry;
    overlay.insert(entry);
  }
}

class _NoticeBanner extends StatefulWidget {
  const _NoticeBanner({
    required this.kind,
    required this.title,
    required this.message,
    required this.onDismissed,
  });

  final _NoticeKind kind;
  final String title;
  final String message;
  final VoidCallback onDismissed;

  @override
  State<_NoticeBanner> createState() => _NoticeBannerState();
}

class _NoticeBannerState extends State<_NoticeBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animation = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
    reverseDuration: const Duration(milliseconds: 180),
  );
  Timer? _timer;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    _animation.addStatusListener((status) {
      if (_closing && status == AnimationStatus.dismissed) {
        widget.onDismissed();
      }
    });
    _animation.forward();
    _timer = Timer(
      Duration(seconds: widget.kind == _NoticeKind.error ? 4 : 3),
      () {
        if (!mounted) return;
        _closing = true;
        _animation.reverse();
      },
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    _animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vita = context.vita;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final color = switch (widget.kind) {
      _NoticeKind.success => vita.green,
      _NoticeKind.error => vita.red,
      _NoticeKind.warning => const Color(0xFFD89527),
      _NoticeKind.info => const Color(0xFF5A91D8),
    };
    final icon = switch (widget.kind) {
      _NoticeKind.success => Icons.check_circle_outline_rounded,
      _NoticeKind.error => Icons.error_outline_rounded,
      _NoticeKind.warning => Icons.warning_amber_rounded,
      _NoticeKind.info => Icons.info_outline_rounded,
    };
    return Positioned(
      top: 0,
      left: 12,
      right: 12,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: IgnorePointer(
            child: FadeTransition(
              opacity: _animation,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, -0.25),
                  end: Offset.zero,
                ).animate(CurvedAnimation(
                    parent: _animation, curve: Curves.easeOutCubic)),
                child: SizedBox(
                  width: double.infinity,
                  child: DefaultTextStyle(
                    style: (Theme.of(context).textTheme.bodyMedium ??
                            const TextStyle())
                        .copyWith(decoration: TextDecoration.none),
                    child: Semantics(
                      container: true,
                      liveRegion: true,
                      label: '${widget.title}. ${widget.message}',
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(18),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: dark
                                  ? const Color(0xE82B2B30)
                                  : const Color(0xF2FFFFFF),
                              border: Border.all(
                                color: dark
                                    ? Colors.white.withValues(alpha: 0.12)
                                    : Colors.black.withValues(alpha: 0.06),
                              ),
                              borderRadius: BorderRadius.circular(18),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 12),
                              child: Row(
                                mainAxisSize: MainAxisSize.max,
                                children: [
                                  Icon(icon, size: 21, color: color),
                                  const SizedBox(width: 11),
                                  Expanded(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          widget.title,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600,
                                            color: dark
                                                ? Colors.white
                                                : const Color(0xFF19191C),
                                          ),
                                        ),
                                        if (widget.message.isNotEmpty) ...[
                                          const SizedBox(height: 3),
                                          Text(
                                            widget.message,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 12,
                                              height: 1.3,
                                              color: dark
                                                  ? Colors.white70
                                                  : const Color(0xFF65656C),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
