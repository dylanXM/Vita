import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/theme.dart';
import '../../shared/widgets.dart';
import '../companion/companion_create_page.dart';
import '../billing/billing_controller.dart';
import 'chat_list_controller.dart';
import 'chat_list_presentation.dart';
import 'chat_page.dart';

/// Chat tab — a continuous conversation list with familiar message-app rhythm.
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
              showDivider: false,
              actions: IconButton(
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
                icon: Icon(Icons.add, color: context.vita.text, size: 26),
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
        title: 'chat.empty.title'.tr,
        subtitle: 'chat.empty.sub'.tr,
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(0, 4, 0, 90),
      itemCount: ctrl.companions.length,
      separatorBuilder: (context, _) => Divider(
        height: 0.5,
        indent: 82,
        color: context.vita.divider,
      ),
      itemBuilder: (context, i) {
        final c = ctrl.companions[i];
        final id = c['id'] as String? ?? '';
        final name = c['name'] as String? ?? 'chat.companion'.tr;
        final profileSubtitle = [
          c['city'] as String?,
          c['occupation'] as String?,
        ].where((e) => e != null && e.isNotEmpty).join(' · ');
        final friendshipActive = c['friendship_active'] != false;
        final presentation = ChatListPresentation.from(c);
        final subtitle = !friendshipActive
            ? 'chat.notFriends'.tr
            : presentation.preview(
                fallback: profileSubtitle.isEmpty
                    ? 'chat.distant'.tr
                    : profileSubtitle,
                voiceLabel: 'chat.voiceMessage'.tr,
                photoLabel: 'chat.photoMessage'.tr,
              );
        final time =
            presentation.timeLabel(DateTime.now(), 'common.yesterday'.tr);
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () async {
            await Get.to(
              () => ChatPage(companionId: id, name: name, companion: c),
              transition: Transition.cupertino,
              duration: const Duration(milliseconds: 300),
            );
            await ctrl.load();
          },
          child: Container(
            color: context.vita.surface,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
                        subtitle,
                        style: TextStyle(
                            fontSize: 13, color: context.vita.subText),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                if (time.isNotEmpty || presentation.unreadCount > 0) ...[
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      if (time.isNotEmpty)
                        Text(time,
                            style: TextStyle(
                                fontSize: 11, color: context.vita.subText)),
                      if (presentation.unreadCount > 0) ...[
                        const SizedBox(height: 6),
                        Container(
                          constraints:
                              const BoxConstraints(minWidth: 18, minHeight: 18),
                          padding: const EdgeInsets.symmetric(horizontal: 5),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: context.vita.red,
                            borderRadius: BorderRadius.circular(9),
                          ),
                          child: Text(
                            presentation.unreadCount > 99
                                ? '99+'
                                : '${presentation.unreadCount}',
                            style: const TextStyle(
                                color: Colors.white, fontSize: 10, height: 1.1),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}
