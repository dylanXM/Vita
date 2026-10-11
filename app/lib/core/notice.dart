import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'theme.dart';
import '../shared/notification_surface.dart';

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
    return Positioned(
      top: 0,
      left: 22,
      right: 22,
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
                child: DefaultTextStyle(
                  style: (Theme.of(context).textTheme.bodyMedium ??
                          const TextStyle())
                      .copyWith(decoration: TextDecoration.none),
                  child: Semantics(
                    container: true,
                    liveRegion: true,
                    label: '${widget.title}. ${widget.message}',
                    child: VitaNotificationSurface(
                      child: SizedBox(
                        height: 62,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Row(children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Image.asset(
                                'assets/branding/vita_app_icon_1024.png',
                                width: 40,
                                height: 40,
                                cacheWidth: 120,
                                cacheHeight: 120,
                                fit: BoxFit.cover,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Flexible(
                                      child: Text(widget.title,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                              color: vita.text,
                                              fontSize: 13,
                                              fontWeight: FontWeight.w700))),
                                  if (widget.message.isNotEmpty) ...[
                                    const SizedBox(height: 3),
                                    Flexible(
                                        child: Text(widget.message,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                                color: vita.subText,
                                                fontSize: 12))),
                                  ],
                                ],
                              ),
                            ),
                          ]),
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
