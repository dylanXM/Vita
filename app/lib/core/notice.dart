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
      _NoticeKind.success => Icons.check_circle_rounded,
      _NoticeKind.error => Icons.error_rounded,
      _NoticeKind.warning => Icons.warning_rounded,
      _NoticeKind.info => Icons.info_rounded,
    };
    final radius = BorderRadius.circular(22);
    return Positioned(
      top: 0,
      left: 10,
      right: 10,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: IgnorePointer(
            child: FadeTransition(
              opacity: _animation,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, -0.25),
                  end: Offset.zero,
                ).animate(CurvedAnimation(
                    parent: _animation, curve: Curves.easeOutCubic)),
                child: DefaultTextStyle(
                  style: (Theme.of(context).textTheme.bodyMedium ??
                          const TextStyle())
                      .copyWith(decoration: TextDecoration.none),
                  child: Semantics(
                    container: true,
                    liveRegion: true,
                    label: '${widget.title}. ${widget.message}',
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: radius,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black
                                .withValues(alpha: dark ? 0.28 : 0.14),
                            blurRadius: 24,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: radius,
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: vita.surface
                                  .withValues(alpha: dark ? 0.84 : 0.88),
                              border: Border.all(
                                color: Colors.white
                                    .withValues(alpha: dark ? 0.12 : 0.75),
                                width: 0.5,
                              ),
                              borderRadius: radius,
                            ),
                            child: Padding(
                              padding:
                                  const EdgeInsets.fromLTRB(14, 12, 14, 14),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Row(children: [
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(5),
                                      child: Image.asset(
                                        'assets/branding/vita_app_icon_1024.png',
                                        width: 22,
                                        height: 22,
                                        cacheWidth: 66,
                                        cacheHeight: 66,
                                        fit: BoxFit.cover,
                                      ),
                                    ),
                                    const SizedBox(width: 7),
                                    Text('Vita',
                                        style: TextStyle(
                                          color: vita.subText,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                        )),
                                    const Spacer(),
                                    Icon(icon, size: 16, color: color),
                                  ]),
                                  const SizedBox(height: 8),
                                  Text(
                                    widget.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: vita.text,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  if (widget.message.isNotEmpty) ...[
                                    const SizedBox(height: 3),
                                    Text(
                                      widget.message,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: vita.text,
                                        fontSize: 13,
                                        height: 1.3,
                                      ),
                                    ),
                                  ],
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
