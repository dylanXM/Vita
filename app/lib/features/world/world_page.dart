import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/notice.dart';
import '../../core/api_client.dart';
import '../../core/theme.dart';
import '../../shared/widgets.dart';
import '../billing/billing_controller.dart';
import '../billing/subscription_page.dart';
import '../chat/chat_list_controller.dart';
import '../chat/chat_list_presentation.dart';
import '../chat/chat_page.dart';
import '../companion/companion_create_method_page.dart';
import '../shell/shell_page.dart';

/// A relationship-first entrance: one companion's current context and a
/// compact list of the other relationships.
class WorldPage extends StatefulWidget {
  const WorldPage({super.key});

  @override
  State<WorldPage> createState() => _WorldPageState();
}

class _WorldPageState extends State<WorldPage> with WidgetsBindingObserver {
  Timer? _sceneTimer;
  String? _sceneCompanionId;
  Map<String, dynamic>? _scene;
  int _sceneRequestId = 0;

  Future<void> _loadScene(String id) async {
    if (id.isEmpty) return;
    final requestId = ++_sceneRequestId;
    _sceneCompanionId = id;
    try {
      final data =
          await ApiClient.instance.get('/v1/companions/$id/world/scene');
      if (!mounted || _sceneCompanionId != id || _sceneRequestId != requestId) {
        return;
      }
      setState(
          () => _scene = data is Map ? Map<String, dynamic>.from(data) : null);
    } catch (_) {
      if (mounted && _sceneCompanionId == id && _sceneRequestId == requestId) {
        setState(() => _scene = null);
      }
    }
  }

  Future<void> _visit(String id) async {
    try {
      await ApiClient.instance.post('/v1/companions/$id/world/visit');
      await _loadScene(id);
    } on ApiException catch (error) {
      VitaNotice.error('world.visit'.tr, error.message);
    }
  }

  Map<String, dynamic>? _selectedCompanion(List<Map<String, dynamic>> items) {
    if (items.isEmpty) return null;
    final selectedId = ShellController.to.selectedCompanionId.value;
    if (selectedId != null) {
      for (final item in items) {
        if (item['id'] == selectedId) return item;
      }
    }
    for (final item in items) {
      if (ChatListPresentation.from(item).unreadCount > 0) return item;
    }
    return items.first;
  }

  void _refreshVisibleScene() {
    if (ShellController.to.index.value != 0) return;
    final current = _selectedCompanion(ChatListController.to.companions);
    final id = current?['id'] as String? ?? '';
    if (id.isNotEmpty) _loadScene(id);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _sceneTimer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => _refreshVisibleScene(),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refreshVisibleScene();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sceneTimer?.cancel();
    super.dispose();
  }

  Future<void> _createCompanion() async {
    if (!BillingController.to.isSubscribed) {
      await showSubscriptionPrompt('subscription.required.create'.tr);
      return;
    }
    await Get.to(() => const CompanionCreateMethodPage(),
        transition: Transition.cupertino);
    await ChatListController.to.load();
  }

  Future<void> _openChat(Map<String, dynamic> companion) async {
    final id = companion['id'] as String? ?? '';
    if (id.isEmpty) return;
    await Get.to(() => ChatPage(
          companionId: id,
          name: '${companion['name'] ?? 'chat.companion'.tr}',
          companion: companion,
        ));
    await ChatListController.to.load();
    if (mounted) await _loadScene(id);
  }

  @override
  Widget build(BuildContext context) {
    final controller = ChatListController.to;
    return Scaffold(
      backgroundColor: context.vita.pageBg,
      body: SafeArea(
        bottom: false,
        child: Obx(() {
          final companions = controller.companions.toList();
          final current = _selectedCompanion(companions);
          final currentId = current?['id'] as String? ?? '';
          final activeScene = _sceneCompanionId == currentId ? _scene : null;
          if (currentId != _sceneCompanionId) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              if (currentId.isEmpty) {
                setState(() {
                  _sceneCompanionId = null;
                  _scene = null;
                });
              } else {
                setState(() => _scene = null);
                _loadScene(currentId);
              }
            });
          }
          final others = companions
              .where((item) => item['id'] != currentId)
              .toList(growable: false);
          return RefreshIndicator(
            onRefresh: () async {
              await controller.load();
              _refreshVisibleScene();
            },
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.only(bottom: VitaTabBar.reservedHeight + 34),
              children: [
                VitaTabHeader(
                  title: 'tab.world'.tr,
                  showDivider: false,
                  actions: IconButton.filledTonal(
                    tooltip: 'world.create'.tr,
                    onPressed: _createCompanion,
                    icon: const Icon(Icons.add),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (current == null)
                        _EmptyRelationship(onCreate: _createCompanion)
                      else ...[
                        _CurrentRelationship(
                          key: ValueKey(currentId),
                          companion: current,
                          scene: activeScene,
                          onChat: () => _openChat(current),
                          onVisit: () => _visit(currentId),
                        ),
                        if (others.isNotEmpty) ...[
                          const SizedBox(height: 28),
                          Text('world.otherCompanions'.tr,
                              style: TextStyle(
                                color: context.vita.text,
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              )),
                          const SizedBox(height: 10),
                          for (final item in others)
                            _OtherRelationship(
                              companion: item,
                              onTap: () => _openChat(item),
                            ),
                        ],
                      ],
                    ],
                  ),
                ),
              ],
            ),
          );
        }),
      ),
    );
  }
}

class _CurrentRelationship extends StatelessWidget {
  const _CurrentRelationship({
    super.key,
    required this.companion,
    required this.scene,
    required this.onChat,
    required this.onVisit,
  });

  final Map<String, dynamic> companion;
  final Map<String, dynamic>? scene;
  final VoidCallback onChat;
  final VoidCallback onVisit;

  @override
  Widget build(BuildContext context) {
    final name = '${companion['name'] ?? 'chat.companion'.tr}';
    final presentation = ChatListPresentation.from(companion);
    final event = scene?['event'] is Map ? scene!['event'] as Map : null;
    final place = scene?['place'] is Map ? scene!['place'] as Map : null;
    final eventTitle = '${event?['title'] ?? ''}'.trim();
    final placeTitle = '${place?['title'] ?? ''}'.trim();
    final waiting = presentation.unreadCount > 0;
    final preview = !waiting && eventTitle.isNotEmpty
        ? eventTitle
        : presentation.message.isNotEmpty
            ? presentation.preview(
                fallback: 'world.ready'.tr,
                voiceLabel: 'chat.voiceMessage'.tr,
                photoLabel: 'chat.photoMessage'.tr,
              )
            : 'world.ready'.tr;
    final canVisit =
        !waiting && scene != null && scene!['visited_today'] != true;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: context.vita.surface,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              VitaAvatar(
                name: name,
                imageUrl: companion['portrait_url'] as String?,
                radius: 34,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: context.vita.text,
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                        )),
                    if (placeTitle.isNotEmpty)
                      Text(placeTitle.tr,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: context.vita.subText,
                            fontSize: 12,
                          )),
                  ],
                ),
              ),
              if (waiting)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                  decoration: BoxDecoration(
                    color: context.vita.greenTint,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text('world.waiting'.tr,
                      style:
                          TextStyle(color: context.vita.green, fontSize: 12)),
                ),
            ],
          ),
          const SizedBox(height: 22),
          Text(preview,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: context.vita.text,
                fontSize: 16,
                height: 1.5,
              )),
          const SizedBox(height: 22),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: canVisit ? onVisit : onChat,
              child: Text(canVisit ? 'world.visit'.tr : 'world.talk'.tr),
            ),
          ),
          if (canVisit)
            Align(
              alignment: Alignment.center,
              child: TextButton(
                onPressed: onChat,
                child: Text('world.talk'.tr),
              ),
            ),
        ],
      ),
    );
  }
}

class _OtherRelationship extends StatelessWidget {
  const _OtherRelationship({required this.companion, required this.onTap});

  final Map<String, dynamic> companion;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final name = '${companion['name'] ?? 'chat.companion'.tr}';
    final presentation = ChatListPresentation.from(companion);
    final preview = presentation.preview(
      fallback: 'world.ready'.tr,
      voiceLabel: 'chat.voiceMessage'.tr,
      photoLabel: 'chat.photoMessage'.tr,
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: context.vita.surface,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                VitaAvatar(
                  name: name,
                  imageUrl: companion['portrait_url'] as String?,
                  radius: 24,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: context.vita.text,
                            fontWeight: FontWeight.w700,
                          )),
                      Text(preview,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: context.vita.subText,
                            fontSize: 12,
                          )),
                    ],
                  ),
                ),
                if (presentation.unreadCount > 0)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                    decoration: BoxDecoration(
                      color: context.vita.greenTint,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      presentation.unreadCount > 99
                          ? '99+'
                          : '${presentation.unreadCount}',
                      style: TextStyle(color: context.vita.green, fontSize: 12),
                    ),
                  )
                else
                  Icon(Icons.chevron_right, color: context.vita.subText),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyRelationship extends StatelessWidget {
  const _EmptyRelationship({required this.onCreate});

  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 90),
        child: Column(
          children: [
            Icon(Icons.auto_awesome_outlined,
                size: 48, color: context.vita.green),
            const SizedBox(height: 16),
            Text('world.emptyTitle'.tr,
                style: TextStyle(color: context.vita.text, fontSize: 20)),
            const SizedBox(height: 8),
            Text('world.emptyHint'.tr,
                style: TextStyle(color: context.vita.subText)),
            const SizedBox(height: 24),
            FilledButton(onPressed: onCreate, child: Text('world.create'.tr)),
          ],
        ),
      );
}
