import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/theme.dart';
import '../../shared/widgets.dart';
import '../companion/companion_create_page.dart';
import '../billing/billing_controller.dart';
import 'chat_list_controller.dart';
import 'chat_page.dart';

/// Chat tab — the conversation list as modern cards.
class ChatListPage extends StatelessWidget {
  const ChatListPage({super.key});

  @override
  Widget build(BuildContext context) {
    final ctrl = ChatListController.to;
    return Scaffold(
      backgroundColor: context.vita.pageBg,
      // Bottom is open so the list scrolls behind the floating glass tab bar.
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            VitaTabHeader(
              title: 'Vita',
              subtitle: 'chat.subtitle'.tr,
              actions: Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: context.vita.green.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  onPressed: () {
                    if (!BillingController.to.isSubscribed) {
                      Get.snackbar('subscription.required.title'.tr,
                          'subscription.required.create'.tr);
                      Get.toNamed('/subscription');
                      return;
                    }
                    Get.to(
                      () => const CompanionCreatePage(),
                      transition: Transition.cupertino,
                      duration: const Duration(milliseconds: 300),
                    );
                  },
                  icon: Icon(Icons.person_add_alt_1,
                      color: context.vita.green, size: 21),
                ),
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
      return ListView.builder(
        padding: const EdgeInsets.only(bottom: 90),
        itemCount: 4,
        itemBuilder: (_, __) => const VitaSkeletonCard(),
      );
    }
    if (ctrl.companions.isEmpty) {
      return VitaEmpty(
        icon: Icons.favorite_border,
        title: 'No companion yet',
        subtitle: 'Create your companion to start the conversation',
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(0, 4, 0, 90),
      itemCount: ctrl.companions.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final c = ctrl.companions[i];
        final id = c['id'] as String? ?? '';
        final name = c['name'] as String? ?? 'chat.companion'.tr;
        final subtitle = [
          c['city'] as String?,
          c['occupation'] as String?,
        ].where((e) => e != null && e.isNotEmpty).join(' · ');
        final friendshipActive = c['friendship_active'] != false;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => Get.to(
            () => ChatPage(companionId: id, name: name, companion: c),
            transition: Transition.cupertino,
            duration: const Duration(milliseconds: 300),
          ),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 20),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: context.vita.surface,
              borderRadius: BorderRadius.circular(VitaRadius.md),
              boxShadow: VitaShadow.card,
            ),
            child: Row(
              children: [
                VitaAvatar(
                    name: name,
                    radius: 26,
                    imageUrl: c['portrait_url'] as String?),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name,
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: context.vita.text)),
                      const SizedBox(height: 3),
                      Text(
                        !friendshipActive
                            ? 'chat.notFriends'.tr
                            : subtitle.isEmpty
                                ? 'chat.distant'.tr
                                : subtitle,
                        style: TextStyle(
                            fontSize: 13, color: context.vita.subText),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right,
                    size: 20, color: context.vita.chevron),
              ],
            ),
          ),
        );
      },
    );
  }
}
