import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/theme.dart';
import '../../shared/media_image.dart';
import '../billing/billing_controller.dart';
import '../chat/chat_list_controller.dart';
import '../chat/chat_list_presentation.dart';
import '../chat/chat_page.dart';
import '../companion/companion_create_method_page.dart';
import '../shell/shell_page.dart';

/// The landing place for companions. The chat list remains in the controller,
/// but the user's first view is a character and a place instead of an inbox.
class WorldPage extends StatefulWidget {
  const WorldPage({super.key});

  @override
  State<WorldPage> createState() => _WorldPageState();
}

class _WorldPageState extends State<WorldPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _breathing;

  @override
  void initState() {
    super.initState();
    _breathing = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3200),
    )..repeat(reverse: true);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _breathing.stop();
    } else if (!_breathing.isAnimating) {
      _breathing.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _breathing.dispose();
    super.dispose();
  }

  Future<void> _createCompanion() async {
    if (!BillingController.to.isSubscribed) {
      Get.snackbar(
          'subscription.required.title'.tr, 'subscription.required.create'.tr);
      await Get.toNamed('/subscription');
      return;
    }
    await Get.to(() => const CompanionCreateMethodPage(),
        transition: Transition.cupertino);
    await ChatListController.to.load();
  }

  @override
  Widget build(BuildContext context) {
    final controller = ChatListController.to;
    return Scaffold(
      backgroundColor: context.vita.pageBg,
      body: SafeArea(
        bottom: false,
        child: Obx(() {
          final companions = controller.companions;
          final selectedId = ShellController.to.selectedCompanionId.value;
          final current = companions.isEmpty
              ? null
              : companions.firstWhere(
                  (item) => item['id'] == selectedId,
                  orElse: () => companions.first,
                );
          return RefreshIndicator(
            onRefresh: () => controller.load(),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.fromLTRB(
                  20, 18, 20, VitaTabBar.reservedHeight + 34),
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('world.title'.tr,
                              style: TextStyle(
                                  color: context.vita.text,
                                  fontSize: 28,
                                  fontWeight: FontWeight.w700)),
                          Text('world.subtitle'.tr,
                              style: TextStyle(
                                  color: context.vita.subText, fontSize: 13)),
                        ],
                      ),
                    ),
                    IconButton.filledTonal(
                      tooltip: 'world.create'.tr,
                      onPressed: _createCompanion,
                      icon: const Icon(Icons.add),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                _WorldStage(companion: current, breathing: _breathing),
                if (companions.length > 1) ...[
                  const SizedBox(height: 18),
                  SizedBox(
                    height: 48,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: companions.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (context, index) {
                        final item = companions[index];
                        final selected = item['id'] == current?['id'];
                        final unread =
                            ChatListPresentation.from(item).unreadCount;
                        return ChoiceChip(
                          label: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text('${item['name'] ?? 'chat.companion'.tr}'),
                              if (unread > 0) ...[
                                const SizedBox(width: 6),
                                Text(unread > 99 ? '99+' : '$unread',
                                    style: TextStyle(
                                        color: context.vita.red,
                                        fontWeight: FontWeight.w700)),
                              ],
                            ],
                          ),
                          selected: selected,
                          onSelected: (_) => ShellController
                              .to
                              .selectedCompanionId
                              .value = item['id'] as String?,
                        );
                      },
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                if (current == null)
                  FilledButton.icon(
                    onPressed: _createCompanion,
                    icon: const Icon(Icons.auto_awesome),
                    label: Text('world.create'.tr),
                  )
                else ...[
                  _WorldAction(
                    icon: Icons.chat_bubble_outline,
                    title: 'world.talk'.tr,
                    subtitle: 'world.talkHint'.tr,
                    onTap: () async {
                      final id = current['id'] as String? ?? '';
                      if (id.isEmpty) return;
                      await Get.to(() => ChatPage(
                            companionId: id,
                            name: '${current['name'] ?? 'chat.companion'.tr}',
                            companion: current,
                          ));
                      await controller.load();
                    },
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _WorldAction(
                          icon: Icons.auto_stories_outlined,
                          title: 'world.journey'.tr,
                          onTap: () => ShellController.to.switchTo(1),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _WorldAction(
                          icon: Icons.explore_outlined,
                          title: 'world.discover'.tr,
                          onTap: () => ShellController.to.switchTo(2),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          );
        }),
      ),
    );
  }
}

class _WorldStage extends StatelessWidget {
  const _WorldStage({required this.companion, required this.breathing});

  final Map<String, dynamic>? companion;
  final Animation<double> breathing;

  @override
  Widget build(BuildContext context) {
    final hour = DateTime.now().hour;
    final night = hour < 6 || hour >= 18;
    final name = '${companion?['name'] ?? 'world.emptyTitle'.tr}';
    final portrait = companion?['portrait_url'] as String? ?? '';
    final latest = companion == null
        ? null
        : ChatListPresentation.from(companion!).preview(
            fallback: 'world.ready'.tr,
            voiceLabel: 'chat.voiceMessage'.tr,
            photoLabel: 'chat.photoMessage'.tr,
          );
    return Container(
      height: 420,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: night
              ? const [Color(0xFF242048), Color(0xFF594776), Color(0xFF967796)]
              : const [Color(0xFFB6B5F5), Color(0xFFE4C3D5), Color(0xFFFFD7B3)],
        ),
      ),
      child: Stack(
        children: [
          const Positioned(
            top: 54,
            right: 38,
            child: Icon(Icons.auto_awesome, size: 38, color: Color(0x88FFFFFF)),
          ),
          Positioned(
            right: -62,
            bottom: -170,
            child: Container(
              width: 330,
              height: 330,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.2),
              ),
            ),
          ),
          Positioned(
            left: -70,
            bottom: -170,
            child: Container(
              width: 310,
              height: 310,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF8D78B7).withValues(alpha: 0.22),
              ),
            ),
          ),
          Align(
            alignment: const Alignment(0, -0.1),
            child: AnimatedBuilder(
              animation: breathing,
              builder: (context, child) => Transform.translate(
                offset: Offset(
                    0,
                    MediaQuery.disableAnimationsOf(context)
                        ? 0
                        : (breathing.value - 0.5) * 10),
                child: child,
              ),
              child: portrait.isEmpty
                  ? Icon(Icons.auto_awesome,
                      size: 132, color: Colors.white.withValues(alpha: 0.82))
                  : Container(
                      width: 230,
                      height: 280,
                      clipBehavior: Clip.antiAlias,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(110),
                        boxShadow: const [
                          BoxShadow(
                              color: Color(0x33000000),
                              blurRadius: 30,
                              offset: Offset(0, 18)),
                        ],
                      ),
                      child: VitaMediaImage(url: portrait, fit: BoxFit.cover),
                    ),
            ),
          ),
          Positioned(
            left: 22,
            right: 22,
            bottom: 20,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              decoration: BoxDecoration(
                color: const Color(0xAA201C37),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text(
                    companion == null
                        ? 'world.emptyHint'.tr
                        : companion?['friendship_active'] == false
                            ? 'chat.notFriends'.tr
                            : latest ?? 'world.ready'.tr,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style:
                        const TextStyle(color: Color(0xFFE7DEF3), fontSize: 13),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WorldAction extends StatelessWidget {
  const _WorldAction({
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: context.vita.surface,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.all(17),
            child: Row(
              children: [
                Icon(icon, color: context.vita.green),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: TextStyle(
                              color: context.vita.text,
                              fontWeight: FontWeight.w700)),
                      if (subtitle != null)
                        Text(subtitle!,
                            style: TextStyle(
                                color: context.vita.subText, fontSize: 12)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}
