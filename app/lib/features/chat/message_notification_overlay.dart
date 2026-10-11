import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../core/theme.dart';
import '../../shared/widgets.dart';
import '../../shared/notification_surface.dart';
import '../auth/auth_controller.dart';
import 'chat_list_controller.dart';
import 'chat_list_presentation.dart';
import 'chat_page.dart';

class MessageNotificationOverlay extends StatelessWidget {
  const MessageNotificationOverlay({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Stack(fit: StackFit.expand, children: [
        child,
        Positioned(
          left: 22,
          right: 22,
          top: MediaQuery.paddingOf(context).top + 8,
          child: Material(
              color: Colors.transparent,
              child: Obx(() {
                if (!Get.isRegistered<ChatListController>()) {
                  return const SizedBox.shrink();
                }
                if (AuthController.to.profile.value == null ||
                    ChatListController.to.currentRoute.value
                        .contains('ChatPage')) {
                  return const SizedBox.shrink();
                }
                final unread = ChatListController.to.companions
                    .where((item) =>
                        ChatListPresentation.from(item).unreadCount > 0)
                    .toList();
                if (unread.isEmpty) {
                  return const AnimatedSwitcher(
                    duration: Duration(milliseconds: 240),
                    child: SizedBox.shrink(),
                  );
                }
                unread.sort((a, b) {
                  final aTime = ChatListPresentation.from(a).messageAt;
                  final bTime = ChatListPresentation.from(b).messageAt;
                  return (bTime ?? DateTime(0)).compareTo(aTime ?? DateTime(0));
                });
                final companion = unread.first;
                final presentation = ChatListPresentation.from(companion);
                return AnimatedSwitcher(
                  duration: const Duration(milliseconds: 240),
                  transitionBuilder: (child, animation) => FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0, -.15),
                        end: Offset.zero,
                      ).animate(animation),
                      child: child,
                    ),
                  ),
                  child: _UnreadMessageEntry(
                    key: ValueKey(
                        '${companion['id']}:${companion['last_message_at']}'),
                    companion: companion,
                    presentation: presentation,
                    onTap: () async {
                      final id = '${companion['id'] ?? ''}';
                      if (id.isEmpty) return;
                      await Get.to(() => ChatPage(
                            companionId: id,
                            name: '${companion['name'] ?? 'chat.companion'.tr}',
                            companion: companion,
                          ));
                      await ChatListController.to.load(silent: true);
                    },
                  ),
                );
              })),
        ),
      ]);
}

class _UnreadMessageEntry extends StatelessWidget {
  const _UnreadMessageEntry({
    super.key,
    required this.companion,
    required this.presentation,
    required this.onTap,
  });

  final Map<String, dynamic> companion;
  final ChatListPresentation presentation;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final name = '${companion['name'] ?? 'chat.companion'.tr}';
    return VitaNotificationSurface(
      child: InkWell(
        onTap: onTap,
        splashFactory: NoSplash.splashFactory,
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          height: 62,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(children: [
            VitaAvatar(
              name: name,
              radius: 20,
              imageUrl: companion['portrait_url'] as String?,
              borderRadius: BorderRadius.circular(12),
            ),
            const SizedBox(width: 10),
            Expanded(
                child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: context.vita.text,
                        fontWeight: FontWeight.w700,
                        fontSize: 13)),
                const SizedBox(height: 3),
                Text(
                    presentation.preview(
                        fallback: 'chat.message'.tr,
                        voiceLabel: 'chat.voiceMessage'.tr,
                        photoLabel: 'chat.photoMessage'.tr),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style:
                        TextStyle(color: context.vita.subText, fontSize: 12)),
              ],
            )),
            const SizedBox(width: 8),
            Center(
              child: Container(
                height: 24,
                width: 24,
                padding: const EdgeInsets.all(3),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                    color: context.vita.green, shape: BoxShape.circle),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                      presentation.unreadCount > 99
                          ? '99+'
                          : '${presentation.unreadCount}',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w700)),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
