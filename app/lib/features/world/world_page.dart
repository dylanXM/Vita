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
import '../chat/experience_sheet.dart';
import '../companion/companion_create_method_page.dart';
import '../memories/memories_page.dart';
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
  bool _visiting = false;

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

  Future<void> _visit(
      Map<String, dynamic> companion, Map<String, dynamic> scene) async {
    if (_visiting) return;
    final id = '${companion['id'] ?? ''}';
    setState(() => _visiting = true);
    try {
      final result =
          await ApiClient.instance.post('/v1/companions/$id/world/visit');
      await _loadScene(id);
      if (mounted && result is Map) {
        await _showVisitReceipt(
            companion, scene, Map<String, dynamic>.from(result));
      }
    } on ApiException catch (error) {
      VitaNotice.error('world.visit'.tr, error.message);
    } catch (_) {
      VitaNotice.error('world.visit'.tr, 'world.actionFailed'.tr);
    } finally {
      if (mounted) setState(() => _visiting = false);
    }
  }

  Future<void> _showVisitReceipt(Map<String, dynamic> companion,
      Map<String, dynamic> scene, Map<String, dynamic> result) async {
    final isNew = result['new_visit'] == true;
    final place = scene['place'] is Map ? scene['place'] as Map : const {};
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: context.vita.surface,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 4, 24, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(isNew ? 'world.visitReceipt'.tr : 'world.alreadyVisited'.tr,
                  style: TextStyle(
                      color: context.vita.text,
                      fontSize: 22,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 10),
              Text(
                  (isNew ? 'world.visitReceiptBody' : 'world.alreadyVisited')
                      .trParams({
                    'name': '${companion['name'] ?? ''}',
                    'place': '${place['title'] ?? 'world.place.home'}'.tr,
                  }),
                  style: TextStyle(
                      color: context.vita.subText, fontSize: 15, height: 1.5)),
              if (isNew) ...[
                const SizedBox(height: 14),
                Text('world.visitEffects'.tr,
                    style: TextStyle(
                        color: context.vita.green,
                        fontSize: 13,
                        fontWeight: FontWeight.w600)),
              ],
              const SizedBox(height: 20),
              SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () {
                      Navigator.pop(sheetContext);
                      Get.to(() => MemoryDetailPage(companion: companion),
                          transition: Transition.cupertino);
                    },
                    child: Text('world.openJourney'.tr),
                  )),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _leaveNote(Map<String, dynamic> companion) async {
    final text = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: context.vita.surface,
      builder: (_) => const _WorldNoteSheet(),
    );
    if (text == null || text.trim().isEmpty || !mounted) return;
    final id = '${companion['id'] ?? ''}';
    try {
      final conversation = await ApiClient.instance
          .post('/v1/conversations/', data: {'companion_id': id});
      final conversationId =
          conversation is Map ? '${conversation['conversation_id'] ?? ''}' : '';
      if (conversationId.isEmpty) {
        throw ApiException('conversation unavailable');
      }
      final response = await ApiClient.instance.post(
        '/v1/conversations/$conversationId/messages',
        data: {'message_type': 'text', 'content': text.trim()},
      );
      await ChatListController.to.load();
      if (!mounted) return;
      final reply = response is Map && response['companion_message'] is Map
          ? '${(response['companion_message'] as Map)['content'] ?? ''}'.trim()
          : '';
      await showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        backgroundColor: context.vita.surface,
        builder: (sheetContext) => SafeArea(
            child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 4, 24, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(reply.isEmpty ? 'world.noteSent'.tr : 'world.noteReply'.tr,
                  style: TextStyle(
                      color: context.vita.text,
                      fontSize: 20,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              Text(reply.isEmpty ? 'world.notePending'.tr : reply,
                  style: TextStyle(
                      color: context.vita.subText, fontSize: 15, height: 1.5)),
              const SizedBox(height: 20),
              SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () {
                      Navigator.pop(sheetContext);
                      _openChat(companion);
                    },
                    child: Text('world.openChat'.tr),
                  )),
            ],
          ),
        )),
      );
      if (mounted && _sceneCompanionId == id) await _loadScene(id);
    } on ApiException catch (error) {
      VitaNotice.error('world.leaveNote'.tr, error.message);
    } catch (_) {
      VitaNotice.error('world.leaveNote'.tr, 'world.actionFailed'.tr);
    }
  }

  Future<void> _openGift(String id) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: context.vita.surface,
      builder: (_) => ExperienceSheet(
        companionId: id,
        onCompleted: () async {
          await ChatListController.to.load();
          if (mounted && _sceneCompanionId == id) await _loadScene(id);
        },
      ),
    );
  }

  Future<void> _openScene(
      Map<String, dynamic> companion, Map<String, dynamic> scene) async {
    final place = scene['place'] is Map ? scene['place'] as Map : const {};
    final event = scene['event'] is Map ? scene['event'] as Map : null;
    final next = scene['next_event'] is Map ? scene['next_event'] as Map : null;
    final nextAt = next == null
        ? null
        : DateTime.tryParse('${next['start_time'] ?? ''}')?.toLocal();
    final visited = scene['visited_today'] == true;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: context.vita.surface,
      builder: (sheetContext) => SafeArea(
          child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(22, 2, 22, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('${place['title'] ?? 'world.place.home'}'.tr,
                style: TextStyle(
                    color: context.vita.text,
                    fontSize: 23,
                    fontWeight: FontWeight.w700)),
            if ('${event?['title'] ?? ''}'.trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('${event!['title']}'.tr,
                  style: TextStyle(color: context.vita.text, fontSize: 16)),
            ] else if ('${place['description'] ?? ''}'.trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('${place['description']}'.tr,
                  style: TextStyle(
                      color: context.vita.subText, fontSize: 14, height: 1.45)),
            ],
            if (nextAt != null) ...[
              const SizedBox(height: 16),
              Text(
                  'world.nextMeeting'.trParams({
                    'time':
                        '${formatDateSeparator(nextAt)} ${formatClock(nextAt)}',
                    'event': '${next!['title'] ?? next['location'] ?? ''}'.tr,
                  }),
                  style: TextStyle(color: context.vita.subText, fontSize: 13)),
            ],
            const SizedBox(height: 22),
            if (!visited)
              SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () {
                      Navigator.pop(sheetContext);
                      _visit(companion, scene);
                    },
                    icon: const Icon(Icons.waving_hand_rounded),
                    label: Text('world.visitAt'.trParams({
                      'place': '${place['title'] ?? 'world.place.home'}'.tr,
                    })),
                  ))
            else
              Text('world.alreadyVisited'.tr,
                  style: TextStyle(color: context.vita.green, fontSize: 13)),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                  child: OutlinedButton.icon(
                onPressed: () {
                  Navigator.pop(sheetContext);
                  _leaveNote(companion);
                },
                icon: const Icon(Icons.edit_outlined, size: 17),
                label: Text('world.leaveNote'.tr,
                    maxLines: 1, overflow: TextOverflow.ellipsis),
              )),
              const SizedBox(width: 8),
              Expanded(
                  child: OutlinedButton.icon(
                onPressed: () {
                  Navigator.pop(sheetContext);
                  _openGift('${companion['id'] ?? ''}');
                },
                icon: const Icon(Icons.card_giftcard_rounded, size: 17),
                label: Text('world.giveGift'.tr,
                    maxLines: 1, overflow: TextOverflow.ellipsis),
              )),
            ]),
          ],
        ),
      )),
    );
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
                                onOpenScene: activeScene == null
                                    ? null
                                    : () => _openScene(current, activeScene),
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
                                      onOpenScene: id == currentId &&
                                              activeScene != null
                                          ? () => _openScene(item, activeScene)
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
    required this.onOpenScene,
  });

  final Map<String, dynamic> companion;
  final Map<String, dynamic>? scene;
  final VoidCallback onChat;
  final VoidCallback? onOpenScene;

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
    final next =
        scene?['next_event'] is Map ? scene!['next_event'] as Map : null;
    final nextAt = next == null
        ? null
        : DateTime.tryParse('${next['start_time'] ?? ''}')?.toLocal();
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
                if (nextAt != null) ...[
                  Text(
                      'world.nextMeeting'.trParams({
                        'time':
                            '${formatDateSeparator(nextAt)} ${formatClock(nextAt)}',
                        'event':
                            '${next!['title'] ?? next['location'] ?? ''}'.tr,
                      }),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: vita.subText, fontSize: 12)),
                  const SizedBox(height: 8),
                ],
                Row(children: [
                  Expanded(
                    child: FilledButton(
                      onPressed: onOpenScene,
                      child: Text('world.openScene'.tr,
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.outlined(
                      onPressed: onChat,
                      tooltip: 'world.talk'.tr,
                      icon: const Icon(Icons.chat_bubble_outline_rounded)),
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

class _WorldNoteSheet extends StatefulWidget {
  const _WorldNoteSheet();

  @override
  State<_WorldNoteSheet> createState() => _WorldNoteSheetState();
}

class _WorldNoteSheetState extends State<_WorldNoteSheet> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SafeArea(
        child: AnimatedPadding(
          duration: const Duration(milliseconds: 180),
          padding: EdgeInsets.fromLTRB(
              22, 4, 22, MediaQuery.viewInsetsOf(context).bottom + 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('world.leaveNote'.tr,
                  style: TextStyle(
                      color: context.vita.text,
                      fontSize: 21,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 16),
              TextField(
                  controller: _controller,
                  autofocus: true,
                  maxLength: 140,
                  maxLines: 3,
                  minLines: 3,
                  decoration: InputDecoration(hintText: 'world.noteHint'.tr),
                  onChanged: (_) => setState(() {})),
              const SizedBox(height: 12),
              SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _controller.text.trim().isEmpty
                        ? null
                        : () => Navigator.pop(context, _controller.text.trim()),
                    child: Text('world.sendNote'.tr),
                  )),
            ],
          ),
        ),
      );
}
