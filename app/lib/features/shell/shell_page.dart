import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/api_client.dart';
import '../../core/theme.dart';
import '../chat/chat_list_page.dart';
import '../life/life_page.dart';
import '../me/me_page.dart';
import '../memories/memories_page.dart';

/// Main shell — iOS 27 style: content scrolls edge to edge behind a
/// floating Liquid Glass tab capsule (Chat | Life | Memories | Me).
class ShellController extends GetxController {
  static ShellController get to => Get.find();

  final index = 0.obs;

  void switchTo(int i) => index.value = i;
}

class ShellPage extends StatefulWidget {
  const ShellPage({super.key});

  @override
  State<ShellPage> createState() => _ShellPageState();
}

class _ShellPageState extends State<ShellPage> {
  Timer? _initialNotificationTimer;
  Timer? _notificationTimer;
  bool _pollingNotifications = false;

  @override
  void initState() {
    super.initState();
    _notificationTimer = Timer.periodic(
      const Duration(seconds: 20),
      (_) => _pollNotifications(),
    );
    _initialNotificationTimer = Timer(
      const Duration(seconds: 5),
      _pollNotifications,
    );
  }

  Future<void> _pollNotifications() async {
    if (!mounted || _pollingNotifications) return;
    _pollingNotifications = true;
    try {
      final data = await ApiClient.instance.get('/v1/me/agent-notifications');
      final items = data is Map ? data['items'] : null;
      if (!mounted || items is! List) return;
      for (final raw in items.take(3)) {
        if (raw is! Map) continue;
        final payload = raw['payload'];
        if (payload is! Map) continue;
        final title = payload['title']?.toString() ?? 'Vita';
        final body = payload['body']?.toString() ?? '';
        if (body.isEmpty) continue;
        Get.snackbar(
          title,
          body,
          snackPosition: SnackPosition.TOP,
          duration: const Duration(seconds: 5),
          margin: const EdgeInsets.all(12),
        );
      }
    } catch (_) {
      // Logged-out and temporarily offline states are retried on the next tick.
    } finally {
      _pollingNotifications = false;
    }
  }

  @override
  void dispose() {
    _initialNotificationTimer?.cancel();
    _notificationTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = Get.find<ShellController>();
    return Scaffold(
      backgroundColor: context.vita.pageBg,
      extendBody: true,
      body: Obx(
        () => IndexedStack(
          index: ctrl.index.value,
          children: const [
            ChatListPage(),
            LifePage(),
            MemoriesPage(),
            MePage(),
          ],
        ),
      ),
      bottomNavigationBar: Obx(
        () => VitaTabBar(index: ctrl.index.value, onTap: ctrl.switchTo),
      ),
    );
  }
}

/// Tab definition: localized label key + outline/filled icon pair.
class _NavItem {
  const _NavItem({
    required this.labelKey,
    required this.icon,
    required this.activeIcon,
  });

  final String labelKey;
  final IconData icon;
  final IconData activeIcon;
}

const List<_NavItem> _kTabs = [
  _NavItem(
    labelKey: 'tab.chat',
    icon: Icons.chat_bubble_outline,
    activeIcon: Icons.chat_bubble,
  ),
  _NavItem(
    labelKey: 'tab.life',
    icon: Icons.photo_library_outlined,
    activeIcon: Icons.photo_library,
  ),
  _NavItem(
    labelKey: 'tab.memories',
    icon: Icons.star_border,
    activeIcon: Icons.star,
  ),
  _NavItem(
    labelKey: 'tab.me',
    icon: Icons.person_outline,
    activeIcon: Icons.person,
  ),
];

/// iOS 27 bottom navigation — a floating Liquid Glass capsule.
///
/// Measured against Apple's iOS 27 UI kit: 54pt control, glass oversize of
/// 4pt per side, pill corner radius, 10pt semibold labels, and a selection
/// pill (content + 4pt) that morphs between tabs with a snappy spring.
class VitaTabBar extends StatelessWidget {
  const VitaTabBar({super.key, required this.index, required this.onTap});

  final int index;
  final ValueChanged<int> onTap;

  // iOS 27 kit metrics (pt).
  static const double _controlHeight = 54;
  static const double _glassInset = 4;
  static const double _sidePadding = 25;
  static const double _topGap = 16;
  static const double _pillWidth = 72;
  static const double _pillHeight = 46;
  static const double _symbolBox = 28;
  static const double _labelHeight = 12;

  @override
  Widget build(BuildContext context) {
    final vita = context.vita;
    final dark = vita.brightness == Brightness.dark;
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: vita.glass.withValues(alpha: dark ? 0.28 : 0.38),
            border: Border(
              top: BorderSide(
                color: vita.glassRing.withValues(alpha: 0.45),
                width: 0.5,
              ),
            ),
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                _sidePadding,
                _topGap,
                _sidePadding,
                0,
              ),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final slot =
                      (constraints.maxWidth - 2 * _glassInset) / _kTabs.length;
                  return Container(
                    decoration: BoxDecoration(
                      color: Colors.transparent,
                      borderRadius: BorderRadius.circular(100),
                      boxShadow: [
                        BoxShadow(
                          color: vita.glassShadow,
                          blurRadius: dark ? 24 : 18,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(100),
                      child: BackdropFilter(
                        // Liquid Glass: strong diffusion of whatever scrolls behind.
                        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                        child: Stack(
                          children: [
                            // Glass fill + edge ring.
                            Positioned.fill(
                              child: Container(
                                decoration: BoxDecoration(
                                  color: vita.glass,
                                  borderRadius: BorderRadius.circular(100),
                                  border: Border.all(
                                    color: vita.glassRing,
                                    width: 0.5,
                                  ),
                                ),
                              ),
                            ),
                            // Specular highlight along the top rim.
                            Positioned(
                              top: 0.5,
                              left: 18,
                              right: 18,
                              height: 1,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      Colors.transparent,
                                      Colors.white.withValues(
                                        alpha: dark ? 0.28 : 0.55,
                                      ),
                                      Colors.transparent,
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            // Tab row (glass oversize of 4pt per side).
                            Padding(
                              padding: const EdgeInsets.all(_glassInset),
                              child: SizedBox(
                                height: _controlHeight,
                                child: Stack(
                                  children: [
                                    // Selection pill — morphs between tabs.
                                    AnimatedPositioned(
                                      duration: const Duration(
                                        milliseconds: 450,
                                      ),
                                      curve: const Cubic(0.34, 1.56, 0.64, 1.0),
                                      top: (_controlHeight - _pillHeight) / 2,
                                      left:
                                          slot * (index + 0.5) - _pillWidth / 2,
                                      width: _pillWidth,
                                      height: _pillHeight,
                                      child: DecoratedBox(
                                        decoration: BoxDecoration(
                                          color: vita.selectionPill,
                                          borderRadius: BorderRadius.circular(
                                            100,
                                          ),
                                        ),
                                      ),
                                    ),
                                    Row(
                                      children: [
                                        for (var i = 0; i < _kTabs.length; i++)
                                          Expanded(
                                            child: _TabButton(
                                              item: _kTabs[i],
                                              selected: i == index,
                                              onTap: () => onTap(i),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TabButton extends StatefulWidget {
  const _TabButton({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final _NavItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_TabButton> createState() => _TabButtonState();
}

class _TabButtonState extends State<_TabButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final vita = context.vita;
    final tint = vita.green;
    final label = widget.item.labelKey.tr;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: Semantics(
        label: label,
        selected: widget.selected,
        child: AnimatedScale(
          scale: _pressed ? 0.9 : 1,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                height: VitaTabBar._symbolBox,
                child: Icon(
                  widget.selected ? widget.item.activeIcon : widget.item.icon,
                  size: 20,
                  color: widget.selected ? tint : vita.tabInactive,
                ),
              ),
              const SizedBox(height: 1),
              SizedBox(
                height: VitaTabBar._labelHeight,
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10,
                    height: 1.2,
                    fontWeight: FontWeight.w600,
                    letterSpacing: widget.selected ? -0.1 : 0,
                    color: widget.selected ? tint : vita.tabInactive,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
