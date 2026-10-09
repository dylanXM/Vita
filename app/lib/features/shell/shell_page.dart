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

/// Tab definition: localized label and one icon for both selection states.
class _NavItem {
  const _NavItem({
    required this.labelKey,
    required this.icon,
  });

  final String labelKey;
  final IconData icon;
}

const List<_NavItem> _kTabs = [
  _NavItem(
    labelKey: 'tab.world',
    icon: Icons.auto_awesome_outlined,
  ),
  _NavItem(
    labelKey: 'tab.journey',
    icon: Icons.route_outlined,
  ),
  _NavItem(
    labelKey: 'tab.discover',
    icon: Icons.explore_outlined,
  ),
  _NavItem(
    labelKey: 'tab.me',
    icon: Icons.person_outline,
  ),
];

/// The same liquid-glass dock used by ToVideo, with Vita's four destinations.
class VitaTabBar extends StatelessWidget {
  const VitaTabBar({super.key, required this.index, required this.onTap});

  final int index;
  final ValueChanged<int> onTap;

  static const double pillHeight = 60;
  static const double edgeInset = 8;
  static const double reservedHeight = pillHeight + edgeInset * 2;

  @override
  Widget build(BuildContext context) {
    final vita = context.vita;
    final dark = vita.brightness == Brightness.dark;
    return SafeArea(
      top: false,
      child: GlassTabBar.bottom(
        selectedIndex: index,
        onTabSelected: onTap,
        barHeight: pillHeight,
        verticalPadding: edgeInset,
        horizontalPadding: 14,
        spacing: 2,
        tabPadding: const EdgeInsets.symmetric(horizontal: 2),
        iconSize: 24,
        labelFontSize: 10,
        iconLabelSpacing: 2,
        showIndicator: false,
        selectedIconColor: vita.green,
        selectedLabelColor: vita.subText,
        unselectedIconColor: vita.subText,
        unselectedLabelColor: vita.subText,
        unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600),
        settings: LiquidGlassSettings(
          glassColor: vita.surface.withValues(alpha: dark ? 0.44 : 0.58),
          blur: 8,
        ),
        tabs: [
          for (final item in _kTabs)
            GlassTab(
              icon: Icon(item.icon),
              label: item.labelKey.tr,
            ),
        ],
      ),
    );
  }
}
