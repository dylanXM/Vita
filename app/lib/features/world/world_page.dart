import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/notice.dart';
import '../../core/api_client.dart';
import '../../core/theme.dart';
import '../../shared/media_image.dart';
import '../../shared/widgets.dart';
import '../billing/billing_controller.dart';
import '../billing/subscription_page.dart';
import '../chat/chat_list_controller.dart';
import '../chat/chat_list_presentation.dart';
import '../chat/chat_page.dart';
import '../companion/companion_create_method_page.dart';
import '../shell/shell_page.dart';

/// A relationship-first entrance with equal space for every companion.
class WorldPage extends StatefulWidget {
  const WorldPage({super.key});

  @override
  State<WorldPage> createState() => _WorldPageState();
}

class _WorldPageState extends State<WorldPage> with WidgetsBindingObserver {
  PageController? _pages;
  int _visiblePage = 0;
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

  Map<String, dynamic> _companionAt(
      List<Map<String, dynamic>> items, int page) {
    return items[page.clamp(0, items.length - 1)];
  }

  void _refreshVisibleScene() {
    if (ShellController.to.index.value != 0) return;
    final companions = ChatListController.to.companions;
    final current =
        companions.isEmpty ? null : _companionAt(companions, _visiblePage);
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
    _pages?.dispose();
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
    if (mounted && _sceneCompanionId == id) await _loadScene(id);
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
          if (companions.isNotEmpty && _pages == null) {
            final selectedId = _selectedCompanion(companions)?['id'];
            _visiblePage =
                companions.indexWhere((item) => item['id'] == selectedId);
            if (_visiblePage < 0) _visiblePage = 0;
            _pages = PageController(
              initialPage: _visiblePage,
              viewportFraction: .84,
            );
          }
          final current = companions.isEmpty
              ? null
              : _companionAt(companions, _visiblePage);
          final currentId = current?['id'] as String? ?? '';
          final selectedId = ShellController.to.selectedCompanionId.value;
          if (companions.length > 1 &&
              selectedId != null &&
              selectedId != currentId &&
              companions.any((item) => item['id'] == selectedId)) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted || _pages?.hasClients != true) return;
              final selectedIndex =
                  companions.indexWhere((item) => item['id'] == selectedId);
              if (selectedIndex >= 0) {
                _pages!.jumpToPage(selectedIndex);
              }
            });
          }
          final activeScene = _sceneCompanionId == currentId ? _scene : null;
          if (currentId != _sceneCompanionId) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              if (currentId.isEmpty) {
                _sceneRequestId++;
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
          return Column(children: [
            VitaTabHeader(
              title: 'tab.world'.tr,
              showDivider: false,
              actions: IconButton.filledTonal(
                tooltip: 'world.create'.tr,
                onPressed: _createCompanion,
                icon: const Icon(Icons.add),
              ),
            ),
            Expanded(
              child: current == null
                  ? Center(
                      child: _EmptyRelationship(onCreate: _createCompanion))
                  : Padding(
                      padding: EdgeInsets.only(
                        top: 14,
                        bottom: VitaTabBar.reservedHeight + 50,
                      ),
                      child: companions.length == 1
                          ? FractionallySizedBox(
                              widthFactor: .84,
                              child: _RelationshipCard(
                                companion: current,
                                scene: activeScene,
                                onChat: () => _openChat(current),
                                onVisit: () => _visit(currentId),
                              ),
                            )
                          : PageView.builder(
                              controller: _pages,
                              itemCount: companions.length,
                              physics: const PageScrollPhysics(),
                              onPageChanged: (page) {
                                final next = _companionAt(companions, page);
                                final id = next['id'] as String? ?? '';
                                setState(() {
                                  _visiblePage = page;
                                  _scene = null;
                                });
                                ShellController.to.selectedCompanionId.value =
                                    id;
                                _loadScene(id);
                              },
                              itemBuilder: (context, page) {
                                final item = _companionAt(companions, page);
                                final id = item['id'] as String? ?? '';
                                return AnimatedBuilder(
                                  animation: _pages!,
                                  builder: (context, child) {
                                    final position = _pages!.hasClients
                                        ? (_pages!.page ??
                                            _visiblePage.toDouble())
                                        : _visiblePage.toDouble();
                                    final distance =
                                        (page - position).clamp(-1.0, 1.0);
                                    final depth = distance.abs();
                                    return Transform(
                                      alignment: Alignment.center,
                                      transform: Matrix4.identity()
                                        ..setEntry(3, 2, .001)
                                        ..translateByDouble(0, depth * 24, 0, 1)
                                        ..rotateY(-distance * .24)
                                        ..scaleByDouble(1 - depth * .11,
                                            1 - depth * .11, 1, 1),
                                      child: child,
                                    );
                                  },
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 5),
                                    child: _RelationshipCard(
                                      companion: item,
                                      scene:
                                          id == currentId ? activeScene : null,
                                      onChat: () => _openChat(item),
                                      onVisit: id == currentId
                                          ? () => _visit(id)
                                          : null,
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
            ),
          ]);
        }),
      ),
    );
  }
}

class _RelationshipCard extends StatelessWidget {
  const _RelationshipCard({
    required this.companion,
    required this.scene,
    required this.onChat,
    required this.onVisit,
  });

  final Map<String, dynamic> companion;
  final Map<String, dynamic>? scene;
  final VoidCallback onChat;
  final VoidCallback? onVisit;

  @override
  Widget build(BuildContext context) {
    final vita = context.vita;
    final name = '${companion['name'] ?? 'chat.companion'.tr}';
    final imageUrl = companion['portrait_url'] as String? ?? '';
    final presentation = ChatListPresentation.from(companion);
    final event = scene?['event'] is Map ? scene!['event'] as Map : null;
    final place = scene?['place'] is Map ? scene!['place'] as Map : null;
    final eventTitle = '${event?['title'] ?? ''}'.trim();
    final placeTitle = '${place?['title'] ?? ''}'.trim();
    final waiting = presentation.unreadCount > 0;
    final phase = scene?['phase'] as String?;
    final phaseLabel = switch (phase) {
      'active' ||
      'celebration' ||
      'together' ||
      'quiet' =>
        'world.phase.$phase'.tr,
      _ => 'world.ready'.tr,
    };
    final preview = !waiting && eventTitle.isNotEmpty
        ? eventTitle.tr
        : presentation.message.isNotEmpty
            ? presentation.preview(
                fallback: 'world.ready'.tr,
                voiceLabel: 'chat.voiceMessage'.tr,
                photoLabel: 'chat.photoMessage'.tr,
              )
            : 'world.ready'.tr;
    final canVisit = !waiting &&
        onVisit != null &&
        scene != null &&
        scene!['visited_today'] != true;
    final hour = scene?['local_hour'] is num
        ? (scene!['local_hour'] as num).toInt()
        : DateTime.now().hour;
    final night = hour < 6 || hour >= 19;
    final sky = night ? const Color(0xFF252446) : const Color(0xFFB988A5);
    final glow = night ? const Color(0xFF7265A2) : const Color(0xFFE9AF88);
    return ClipRRect(
      borderRadius: BorderRadius.circular(30),
      child: ColoredBox(
        color: vita.surface,
        child: Column(children: [
          Expanded(
            child: Stack(fit: StackFit.expand, children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [sky, glow],
                  ),
                ),
              ),
              if (imageUrl.isNotEmpty)
                VitaMediaImage(
                  url: imageUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const SizedBox.expand(),
                ),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      sky.withValues(alpha: .20),
                      Colors.transparent,
                      const Color(0xFF17141F).withValues(alpha: .85),
                    ],
                    stops: const [0, .47, 1],
                  ),
                ),
              ),
              Positioned(
                top: 18,
                left: 18,
                right: 18,
                child: Row(children: [
                  const Icon(Icons.circle, size: 7, color: Colors.white),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      placeTitle.isEmpty ? 'world.ready'.tr : placeTitle.tr,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Text(
                    '${hour.toString().padLeft(2, '0')}:00',
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ]),
              ),
              Positioned(
                left: 20,
                right: 20,
                bottom: 18,
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 30,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(19, 13, 19, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  height: 18,
                  child: Text(
                    waiting ? 'world.waiting'.tr : phaseLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: waiting ? vita.green : vita.subText,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                SizedBox(
                  height: 44,
                  child: Text(preview,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: vita.text, fontSize: 16, height: 1.35)),
                ),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(
                    child: FilledButton(
                      onPressed: onChat,
                      child: Text('world.talk'.tr),
                    ),
                  ),
                  if (canVisit) ...[
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: onVisit,
                        child: Text('world.visit'.tr,
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                    ),
                  ],
                ]),
              ],
            ),
          ),
        ]),
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
