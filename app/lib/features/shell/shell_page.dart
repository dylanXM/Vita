import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import '../../core/push_notification_service.dart';
import '../../core/app_content_controller.dart';
import '../../core/analytics_service.dart';
import '../../core/theme.dart';
import '../world/world_page.dart';
import '../me/me_page.dart';
import '../memories/memories_page.dart';
import '../explore/explore_page.dart';
import '../whats_new/whats_new_sheet.dart';
import '../ads/admob_controller.dart';

/// Main shell for the world, journey, discover and account destinations.
class ShellController extends GetxController {
  static ShellController get to => Get.find();

  final index = 0.obs;
  final selectedCompanionId = RxnString();

  void switchTo(int i) {
    if (i == index.value) return;
    const tabs = ['world', 'journey', 'discover', 'me'];
    AnalyticsService.to.track('tab_selected',
        category: 'navigation',
        properties: {'from': tabs[index.value], 'to': tabs[i]});
    index.value = i;
    if (i == 1) {
      MemoriesController.to.loadCompanions();
    } else if (i == 2) {
      ExploreController.to.loadPosts();
      ExploreController.to.loadHighlights();
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
    AdmobController.to.refreshConfig();
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
            // Tab pages receive an extra bottom inset for the floating dock
            // while their backgrounds continue behind it.
            data: mq.copyWith(
              padding: mq.padding.copyWith(
                bottom: safeBottom + VitaTabBar.reservedHeight,
              ),
            ),
            child: Obx(
              () => IndexedStack(
                index: ctrl.index.value,
                children: [
                  TickerMode(
                    enabled: ctrl.index.value == 0,
                    child: const WorldPage(),
                  ),
                  const MemoriesPage(),
                  const ExplorePage(),
                  const MePage(),
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

/// Tab definition: localized label with outlined and filled icon states.
class _NavItem {
  const _NavItem({
    required this.labelKey,
    required this.icon,
    required this.selectedIcon,
  });

  final String labelKey;
  final IconData icon;
  final IconData selectedIcon;
}

const List<_NavItem> _kTabs = [
  _NavItem(
    labelKey: 'tab.world',
    icon: Icons.auto_awesome_outlined,
    selectedIcon: Icons.auto_awesome,
  ),
  _NavItem(
    labelKey: 'tab.journey',
    icon: Icons.route_outlined,
    selectedIcon: Icons.route,
  ),
  _NavItem(
    labelKey: 'tab.discover',
    icon: Icons.explore_outlined,
    selectedIcon: Icons.explore,
  ),
  _NavItem(
    labelKey: 'tab.me',
    icon: Icons.person_outline,
    selectedIcon: Icons.person,
  ),
];

/// The same liquid-glass dock used by ToVideo, with Vita's four destinations.
class VitaTabBar extends StatefulWidget {
  const VitaTabBar({super.key, required this.index, required this.onTap});

  final int index;
  final ValueChanged<int> onTap;

  static const double pillHeight = 60;
  static const double edgeInset = 8;
  static const double reservedHeight = pillHeight + edgeInset * 2;

  @override
  State<VitaTabBar> createState() => _VitaTabBarState();
}

class _VitaTabBarState extends State<VitaTabBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _movement = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
    value: 1,
  );
  late double _animationStartIndex = widget.index.toDouble();

  @override
  void didUpdateWidget(VitaTabBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.index != widget.index) {
      final progress = Curves.easeOutCubic.transform(_movement.value);
      _animationStartIndex +=
          (oldWidget.index - _animationStartIndex) * progress;
      _movement.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _movement.dispose();
    super.dispose();
  }

  Alignment _tabAlignment(double index, TextDirection direction) {
    final visualIndex =
        direction == TextDirection.rtl ? _kTabs.length - 1 - index : index;
    return Alignment(-1 + 2 * visualIndex / (_kTabs.length - 1), 0);
  }

  @override
  Widget build(BuildContext context) {
    final vita = context.vita;
    final dark = vita.brightness == Brightness.dark;
    final direction = Directionality.of(context);
    final rimColor =
        dark ? Colors.white.withValues(alpha: .35) : vita.glassRing;
    const outerRadius = 30.0;
    const indicatorInset = 4.0;
    const innerRadius = outerRadius - indicatorInset;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: VitaTabBar.edgeInset,
        ),
        child: SizedBox(
          height: VitaTabBar.pillHeight,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: AdaptiveGlass(
                  shape: const LiquidRoundedRectangle(
                    borderRadius: outerRadius,
                  ),
                  settings: LiquidGlassSettings(
                    glassColor:
                        vita.surface.withValues(alpha: dark ? .44 : .58),
                    blur: 8,
                  ),
                  child: const SizedBox.expand(),
                ),
              ),
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: ShapeDecoration(
                      shape: LiquidRoundedRectangle(
                        borderRadius: outerRadius,
                        side: BorderSide(color: rimColor, width: 1),
                      ),
                    ),
                  ),
                ),
              ),
              Positioned.fill(
                  child: AnimatedBuilder(
                animation: _movement,
                builder: (context, _) {
                  final progress =
                      Curves.easeOutCubic.transform(_movement.value);
                  final alignment = Alignment.lerp(
                    _tabAlignment(_animationStartIndex, direction),
                    _tabAlignment(widget.index.toDouble(), direction),
                    progress,
                  )!;
                  final thickness =
                      math.sin(math.pi * _movement.value).clamp(0.0, 1.0);
                  final restOpacity = (1 - thickness / .15).clamp(0.0, 1.0);
                  return Stack(
                    clipBehavior: Clip.none,
                    children: [
                      AnimatedGlassIndicator(
                        velocity: 0,
                        itemCount: _kTabs.length,
                        alignment: alignment,
                        thickness: thickness,
                        quality: GlassQuality.standard,
                        indicatorColor:
                            vita.glass.withValues(alpha: dark ? .38 : .62),
                        isBackgroundIndicator: false,
                        padding: const EdgeInsets.all(indicatorInset),
                        borderRadius: innerRadius,
                        innerBlur: 1.5,
                        settings: LiquidGlassSettings(
                          glassColor:
                              vita.glass.withValues(alpha: dark ? .18 : .28),
                          ambientRim: .18,
                        ),
                      ),
                      Positioned.fill(
                        child: Padding(
                          padding: const EdgeInsets.all(indicatorInset),
                          child: FractionallySizedBox(
                            widthFactor: 1 / _kTabs.length,
                            alignment: alignment,
                            child: IgnorePointer(
                              child: Opacity(
                                opacity: restOpacity,
                                child: DecoratedBox(
                                  decoration: ShapeDecoration(
                                    shape: LiquidRoundedRectangle(
                                      borderRadius: innerRadius,
                                      side: BorderSide(
                                        color: rimColor,
                                        width: 1,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      Row(
                        children: [
                          for (var i = 0; i < _kTabs.length; i++)
                            Expanded(
                              child: Semantics(
                                button: true,
                                selected: widget.index == i,
                                label: _kTabs[i].labelKey.tr,
                                child: GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTap: () => widget.onTap(i),
                                  child: Center(
                                    child: FittedBox(
                                      fit: BoxFit.scaleDown,
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            widget.index == i
                                                ? _kTabs[i].selectedIcon
                                                : _kTabs[i].icon,
                                            size: 24,
                                            color: widget.index == i
                                                ? vita.green
                                                : vita.subText,
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            _kTabs[i].labelKey.tr,
                                            style: TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.w600,
                                              color: widget.index == i
                                                  ? vita.green
                                                  : vita.subText,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  );
                },
              )),
            ],
          ),
        ),
      ),
    );
  }
}
