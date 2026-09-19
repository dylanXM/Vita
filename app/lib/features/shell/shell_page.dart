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
        () => BottomNavigationBar(
          currentIndex: ctrl.index.value,
          onTap: ctrl.switchTo,
          type: BottomNavigationBarType.fixed,
          backgroundColor: Colors.white,
          selectedItemColor: VitaColors.green,
          unselectedItemColor: VitaColors.tabInactive,
          selectedFontSize: 11,
          unselectedFontSize: 11,
          items: const [
            BottomNavigationBarItem(icon: Icon(Icons.chat_bubble_outline), activeIcon: Icon(Icons.chat_bubble), label: 'Chat'),
            BottomNavigationBarItem(icon: Icon(Icons.photo_library_outlined), activeIcon: Icon(Icons.photo_library), label: 'Life'),
            BottomNavigationBarItem(icon: Icon(Icons.star_border), activeIcon: Icon(Icons.star), label: 'Memories'),
            BottomNavigationBarItem(icon: Icon(Icons.person_outline), activeIcon: Icon(Icons.person), label: 'Me'),
          ],
        ),
      ),
    );
  }
}
