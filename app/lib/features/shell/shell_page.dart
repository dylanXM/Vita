import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/push_notification_service.dart';
import '../../core/app_content_controller.dart';
import '../../core/analytics_service.dart';
import '../../core/theme.dart';
import '../chat/chat_list_page.dart';
import '../me/me_page.dart';
import '../memories/memories_page.dart';
import '../explore/explore_page.dart';
import '../whats_new/whats_new_sheet.dart';

/// Main shell — content scrolls edge to edge behind a floating glass dock
/// (Chat | Memories | Explore | Me), matching the reference app chrome.
class ShellController extends GetxController {
  static ShellController get to => Get.find();

  final index = 0.obs;

  void switchTo(int i) {
    if (i == index.value) return;
    const tabs = ['chat', 'memories', 'explore', 'me'];
    AnalyticsService.to.track('tab_selected',
        category: 'navigation',
        properties: {'from': tabs[index.value], 'to': tabs[i]});
    index.value = i;
    if (i == 1) {
      MemoriesController.to.loadCompanions();
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
      body: Builder(
        builder: (context) {
          final mq = MediaQuery.of(context);
          final safeBottom = mq.padding.bottom;
          return MediaQuery(
            // Match the reference app: tab pages receive an extra bottom inset
            // for the floating dock while the background still extends behind it.
            data: mq.copyWith(
              padding: mq.padding.copyWith(
                bottom: safeBottom + VitaTabBar.reservedHeight,
              ),
            ),
            child: Obx(
              () => IndexedStack(
                index: ctrl.index.value,
                children: const [
                  ChatListPage(),
                  MemoriesPage(),
                  ExplorePage(),
                  MePage(),
                ],
              ),
            ),
          );
        },
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
    icon: Icons.textsms_outlined,
    activeIcon: Icons.textsms_rounded,
  ),
  _NavItem(
    labelKey: 'tab.memories',
    icon: Icons.menu_book_outlined,
    activeIcon: Icons.menu_book_rounded,
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

/// Floating glass bottom dock with a liquid-glass selection pill.
///
/// The capsule keeps the reference glass treatment; the active tab gets a
/// frosted, near-transparent pill behind it while its icon and label turn
/// brand green.
///
/// Hosted inside [SafeArea] rather than Scaffold defaults, so the pill
/// always floats above the home indicator/navigation gesture area.
class VitaTabBar extends StatelessWidget {
  const VitaTabBar({super.key, required this.index, required this.onTap});

  final int index;
  final ValueChanged<int> onTap;

  static const double pillHeight = 60;
  static const double edgeInset = 8;
  static const double reservedHeight = pillHeight + edgeInset * 2;
  static const double _iconSize = 24;

  @override
  Widget build(BuildContext context) {
    final vita = context.vita;
    final dark = vita.brightness == Brightness.dark;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, edgeInset, 14, edgeInset),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(VitaRadius.pill),
            boxShadow: [
              BoxShadow(
                color: vita.glassShadow,
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(VitaRadius.pill),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: vita.glass.withValues(alpha: dark ? 0.44 : 0.58),
                  borderRadius: BorderRadius.circular(VitaRadius.pill),
                  border: Border.all(
                    color: vita.glassRing.withValues(alpha: dark ? 0.55 : 0.7),
                    width: 0.5,
                  ),
                ),
                child: SizedBox(
                  height: pillHeight,
                  child: Stack(
                    children: [
                      // Liquid-glass selection pill sliding under the
                      // active tab.
                      AnimatedAlign(
                        alignment: Alignment(
                          -1 + (index * 2 / (_kTabs.length - 1)),
                          0,
                        ),
                        duration: const Duration(milliseconds: 260),
                        curve: Curves.easeOutCubic,
                        child: FractionallySizedBox(
                          widthFactor: 1 / _kTabs.length,
                          heightFactor: 1,
                          child: Padding(
                            padding: const EdgeInsets.all(6),
                            child: const _LiquidGlassPill(),
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
                  fontWeight:
                      widget.selected ? FontWeight.w600 : FontWeight.w500,
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

/// Frosted liquid-glass selection pill that slides under the active tab.
class _LiquidGlassPill extends StatelessWidget {
  const _LiquidGlassPill();

  @override
  Widget build(BuildContext context) {
    final vita = context.vita;
    final dark = vita.brightness == Brightness.dark;
    return ClipRRect(
      borderRadius: BorderRadius.circular(VitaRadius.pill),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: dark
                ? const Color(0x2EFFFFFF)
                : const Color(0x80FFFFFF),
            borderRadius: BorderRadius.circular(VitaRadius.pill),
          ),
        ),
      ),
    );
  }
}
