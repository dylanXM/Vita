import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/theme.dart';
import '../../shared/widgets.dart';
import '../companion/companion_create_page.dart';
import 'chat_list_controller.dart';
import 'chat_page.dart';

/// Chat tab — the conversation list, WeChat-style rows.
class ChatListPage extends StatelessWidget {
  const ChatListPage({super.key});

  @override
  Widget build(BuildContext context) {
    final ctrl = ChatListController.to;
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
              child: Row(
                children: [
                  const Text(
                    'Vita',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: VitaColors.text),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Get.to(() => const CompanionCreatePage()),
                    icon: const Icon(Icons.person_add_alt, color: VitaColors.green),
                  ),
                ],
              ),
            ),
            Expanded(child: Obx(() => _buildBody(ctrl))),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(ChatListController ctrl) {
    if (ctrl.loading.value && ctrl.companions.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (ctrl.companions.isEmpty) {
      return VitaEmpty(
        icon: Icons.favorite_border,
        title: 'No companion yet',
        subtitle: 'Create your companion to start the conversation',
      );
    }
    return ListView.separated(
      itemCount: ctrl.companions.length,
      separatorBuilder: (_, __) => const Divider(indent: 76),
      itemBuilder: (context, i) {
        final c = ctrl.companions[i];
        final id = c['id'] as String? ?? '';
        final name = c['name'] as String? ?? 'Companion';
        final subtitle = [
          c['city'] as String?,
          c['occupation'] as String?,
        ].where((e) => e != null && e.isNotEmpty).join(' · ');
        return InkWell(
          onTap: () => Get.to(
            () => ChatPage(companionId: id, name: name),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                VitaAvatar(name: name, radius: 26),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name, style: const TextStyle(fontSize: 16, color: VitaColors.text)),
                      const SizedBox(height: 2),
                      Text(
                        subtitle.isEmpty ? 'in a distant city' : subtitle,
                        style: const TextStyle(fontSize: 13, color: VitaColors.subText),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
