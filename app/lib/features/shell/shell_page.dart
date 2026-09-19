import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/theme.dart';
import '../chat/chat_list_page.dart';
import '../life/life_page.dart';
import '../me/me_page.dart';
import '../memories/memories_page.dart';

/// Main shell — WeChat-style bottom tabs: Chat | Life | Memories | Me.
class ShellController extends GetxController {
  static ShellController get to => Get.find();

  final index = 0.obs;

  void switchTo(int i) => index.value = i;
}

class ShellPage extends StatelessWidget {
  const ShellPage({super.key});

  @override
  Widget build(BuildContext context) {
    final ctrl = Get.find<ShellController>();
    return Scaffold(
      backgroundColor: VitaColors.pageBg,
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
        () => VitaBottomNav(
          index: ctrl.index.value,
          onTap: ctrl.switchTo,
          items: const [
            _NavItem(icon: Icons.chat_bubble_outline, activeIcon: Icons.chat_bubble, label: 'Chat'),
            _NavItem(icon: Icons.photo_library_outlined, activeIcon: Icons.photo_library, label: 'Life'),
            _NavItem(icon: Icons.star_border, activeIcon: Icons.star, label: 'Memories'),
            _NavItem(icon: Icons.person_outline, activeIcon: Icons.person, label: 'Me'),
          ],
        ),
      ),
    );
  }
}

class _NavItem {
  const _NavItem({required this.icon, required this.activeIcon, required this.label});

  final IconData icon;
  final IconData activeIcon;
  final String label;
}

/// Modern bottom navigation: pill highlight behind the active icon.
class VitaBottomNav extends StatelessWidget {
  const VitaBottomNav({super.key, required this.index, required this.onTap, required this.items});

  final int index;
  final ValueChanged<int> onTap;
  final List<_NavItem> items;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: VitaColors.divider, width: 0.5)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 60,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              for (var i = 0; i < items.length; i++)
                _NavButton(item: items[i], selected: i == index, onTap: () => onTap(i)),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({required this.item, required this.selected, required this.onTap});

  final _NavItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        width: 72,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
              width: 54,
              height: 28,
              decoration: BoxDecoration(
                color: selected ? VitaColors.green.withValues(alpha: 0.12) : Colors.transparent,
                borderRadius: BorderRadius.circular(VitaRadius.pill),
              ),
              child: Icon(
                selected ? item.activeIcon : item.icon,
                color: selected ? VitaColors.green : VitaColors.tabInactive,
                size: 23,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              item.label,
              style: TextStyle(
                fontSize: 10.5,
                color: selected ? VitaColors.text : VitaColors.tabInactive,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
