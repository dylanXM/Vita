import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/push_notification_service.dart';
import '../../core/app_content_controller.dart';
import '../../core/analytics_service.dart';
import '../../core/theme.dart';
import '../chat/chat_list_page.dart';
import '../life/life_page.dart';
import '../me/me_page.dart';
import '../explore/explore_page.dart';
import '../whats_new/whats_new_sheet.dart';

/// Main shell — iOS default style: content scrolls edge to edge behind a
/// flush, full-width frosted UITabBar (Chat | Life | Explore | Me).
class ShellController extends GetxController {
  static ShellController get to => Get.find();

  final index = 0.obs;

  void switchTo(int i) {
    if (i == index.value) return;
    const tabs = ['chat', 'life', 'explore', 'me'];
    AnalyticsService.to.track('tab_selected',
        category: 'navigation',
        properties: {'from': tabs[index.value], 'to': tabs[i]});
    index.value = i;
    if (i == 1) {
      LifeController.to.loadCompanions();
    } else if (i == 2) {
      ExploreController.to.loadPosts();
    }
  }
}

class ShellPage extends StatefulWidget {
  const ShellPage({super.key});

  @override
  State<ShellPage> createState() => _ShellPageState();
}

class _ShellPageState extends State<ShellPage> {
  @override
  void initState() {
    super.initState();
    PushNotificationService.instance.activateForSignedInUser();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final campaign = await AppContentController.to.campaignToShow();
      if (!mounted || campaign == null) return;
      await WhatsNewSheet.show(context, campaign);
    });
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
            ExplorePage(),
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
    icon: Icons.forum_outlined,
    activeIcon: Icons.forum_rounded,
  ),
  _NavItem(
    labelKey: 'tab.life',
    icon: Icons.access_time_outlined,
    activeIcon: Icons.access_time_filled,
  ),
  _NavItem(
    labelKey: 'tab.explore',
    icon: Icons.explore_outlined,
    activeIcon: Icons.explore,
  ),
  _NavItem(
    labelKey: 'tab.me',
    icon: Icons.person_outline_rounded,
    activeIcon: Icons.person_rounded,
  ),
];

/// iOS default bottom navigation — a flush, full-width frosted strip.
///
/// Matches the native UITabBar appearance: ultra-thin material blur, a single
/// 0.5pt hairline on top, evenly-spaced icon-over-label cells, no floating
/// capsule, no selection pill, no drop shadow.
class VitaTabBar extends StatelessWidget {
  const VitaTabBar({super.key, required this.index, required this.onTap});

  final int index;
  final ValueChanged<int> onTap;

  // Native UITabBar metrics (pt).
  static const double _barHeight = 49;
  static const double _iconSize = 24;

  @override
  Widget build(BuildContext context) {
    final vita = context.vita;
    final dark = vita.brightness == Brightness.dark;
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: vita.glass.withValues(alpha: dark ? 0.72 : 0.82),
            border: Border(
              top: BorderSide(
                color: vita.divider.withValues(alpha: dark ? 0.6 : 0.8),
                width: 0.5,
              ),
            ),
          ),
          child: SafeArea(
            top: false,
            child: SizedBox(
              height: _barHeight,
              child: Row(
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
    final label = widget.item.labelKey.tr;
    final color = widget.selected ? vita.green : vita.tabInactive;
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
          scale: _pressed ? 0.92 : 1,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                widget.selected ? widget.item.activeIcon : widget.item.icon,
                size: VitaTabBar._iconSize,
                color: color,
              ),
              const SizedBox(height: 2),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10,
                  height: 1.0,
                  fontWeight: FontWeight.w500,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
