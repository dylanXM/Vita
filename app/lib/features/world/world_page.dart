import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/notice.dart';
import '../../core/api_client.dart';
import '../../core/analytics_service.dart';
import '../../core/theme.dart';
import '../../shared/media_image.dart';
import '../../shared/widgets.dart';
import '../billing/billing_controller.dart';
import '../billing/subscription_page.dart';
import '../chat/chat_list_controller.dart';
import '../chat/chat_list_presentation.dart';
import '../chat/chat_page.dart';
import '../chat/experience_sheet.dart';
import '../chat/gift_reveal_page.dart';
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
  String? _lastSceneAnalyticsKey;
  int _sceneRequestId = 0;
  bool _visitBusy = false;
  final Map<String, Map<String, dynamic>> _visitResults = {};

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
      final parsed = data is Map ? Map<String, dynamic>.from(data) : null;
      if (_visitResults[id]?['_local_date'] != parsed?['local_date']) {
        _visitResults.remove(id);
      }
      setState(() => _scene = parsed);
      final analyticsKey =
          '$id:${_scene?['local_date']}:${_scene?['visited_today']}';
      if (_lastSceneAnalyticsKey != analyticsKey) {
        _lastSceneAnalyticsKey = analyticsKey;
        AnalyticsService.to
            .track('world_scene_viewed', category: 'life', properties: {
          'has_event': _scene?['event'] is Map,
          'visited_today': _scene?['visited_today'] == true,
        });
      }
    } catch (_) {
      if (mounted && _sceneCompanionId == id && _sceneRequestId == requestId) {
        setState(() => _scene = null);
      }
    }
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
      AnalyticsService.to.track('world_note_sent', category: 'life');
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

  Future<void> _openGift(Map<String, dynamic> companion) async {
    final id = '${companion['id'] ?? ''}';
    AnalyticsService.to.track('world_gift_opened', category: 'life');
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
        onResult: (response) async {
          await ChatListController.to.load();
          if (mounted && _sceneCompanionId == id) await _loadScene(id);
          if (!mounted) return;
          final product = response['product'];
          if (product is Map && product['category'] == 'gift') {
            Navigator.of(context).pop();
            final action = await Get.to<String>(
                () => GiftRevealPage(
                      name: '${companion['name'] ?? ''}',
                      portraitUrl: companion['portrait_url'] as String?,
                      response: response,
                    ),
                transition: Transition.cupertino);
            if (mounted && action == 'chat') await _openChat(companion);
          }
        },
      ),
    );
  }

  void _centerCard(int page) {
    if (page != _visiblePage && _pages?.hasClients == true) {
      _pages!.animateToPage(page,
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOutCubic);
    }
  }

  Future<void> _chooseVisit(
      Map<String, dynamic> companion, String choice) async {
    if (_visitBusy) return;
    final id = '${companion['id'] ?? ''}';
    setState(() => _visitBusy = true);
    AnalyticsService.to.track('world_visit_started',
        category: 'life', properties: {'choice': choice});
    try {
      final data = await ApiClient.instance
          .post('/v1/companions/$id/world/visit', data: {'choice': choice});
      if (!mounted || data is! Map) return;
      setState(() => _visitResults[id] = {
            ...Map<String, dynamic>.from(data),
            '_local_date': _scene?['local_date'],
          });
      AnalyticsService.to
          .track('world_visit_completed', category: 'life', properties: {
        'choice': choice,
        'new_visit': data['new_visit'] == true,
      });
      await _loadScene(id);
    } on ApiException catch (error) {
      if (error.action == 'open_subscription') {
        if (mounted)
          await showSubscriptionPrompt(context, 'world.visitSubscription'.tr);
      } else {
        VitaNotice.error('world.visit'.tr, error.message);
      }
    } catch (_) {
      VitaNotice.error('world.visit'.tr, 'world.actionFailed'.tr);
    } finally {
      if (mounted) setState(() => _visitBusy = false);
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
      await showSubscriptionPrompt(context, 'subscription.required.create'.tr);
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
                                onJourney: () {
                                  AnalyticsService.to.track(
                                      'world_journey_opened',
                                      category: 'life');
                                  ShellController.to
                                      .showJourneyForCompanion(currentId);
                                },
                                onGift: () => _openGift(current),
                                onNote: () => _leaveNote(current),
                                visitBusy: _visitBusy,
                                visitResult: _visitResults[currentId],
                                onVisitChoice: (choice) =>
                                    _chooseVisit(current, choice),
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
                                  child: GestureDetector(
                                    behavior: HitTestBehavior.translucent,
                                    onTap: page == _visiblePage
                                        ? null
                                        : () => _centerCard(page),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 5),
                                      child: _RelationshipCard(
                                        companion: item,
                                        scene: id == currentId
                                            ? activeScene
                                            : null,
                                        onChat: () => _openChat(item),
                                        onJourney: () {
                                          AnalyticsService.to.track(
                                              'world_journey_opened',
                                              category: 'life');
                                          ShellController.to
                                              .showJourneyForCompanion(id);
                                        },
                                        onGift: () => _openGift(item),
                                        onNote: () => _leaveNote(item),
                                        visitBusy: _visitBusy,
                                        visitResult: _visitResults[id],
                                        onVisitChoice: (choice) =>
                                            _chooseVisit(item, choice),
                                      ),
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
    required this.onJourney,
    required this.onGift,
    required this.onNote,
    required this.visitBusy,
    required this.visitResult,
    required this.onVisitChoice,
  });

  final Map<String, dynamic> companion;
  final Map<String, dynamic>? scene;
  final VoidCallback onChat;
  final VoidCallback onJourney;
  final VoidCallback onGift;
  final VoidCallback onNote;
  final bool visitBusy;
  final Map<String, dynamic>? visitResult;
  final ValueChanged<String> onVisitChoice;

  @override
  Widget build(BuildContext context) {
    final vita = context.vita;
    final name = '${companion['name'] ?? 'chat.companion'.tr}';
    final imageUrl = companion['portrait_url'] as String? ?? '';
    final place = scene?['place'] is Map ? scene!['place'] as Map : null;
    final event = scene?['event'] is Map ? scene!['event'] as Map : null;
    final eventTitle = '${event?['title'] ?? ''}'.trim();
    final placeTitle = '${place?['title'] ?? ''}'.trim();
    final hour = scene?['local_hour'] is num
        ? (scene!['local_hour'] as num).toInt()
        : DateTime.now().hour;
    final night = hour < 6 || hour >= 19;
    final sky = night ? const Color(0xFF252446) : const Color(0xFFB988A5);
    final glow = night ? const Color(0xFF7265A2) : const Color(0xFFE9AF88);
    final savedVisit = scene?['today_visit'];
    final effectiveVisit = visitResult ??
        (savedVisit is Map ? Map<String, dynamic>.from(savedVisit) : null);
    final visited = scene?['visited_today'] == true || effectiveVisit != null;
    final selectedChoice = '${effectiveVisit?['choice'] ?? ''}';
    final gesture = '${effectiveVisit?['gesture'] ?? ''}';
    final asking = gesture == 'turn_toward' || selectedChoice == 'ask';
    final recentGift = scene?['recent_gift'] is Map
        ? Map<String, dynamic>.from(scene!['recent_gift'] as Map)
        : null;
    final giftAt = DateTime.tryParse('${recentGift?['created_at'] ?? ''}');
    final recentGiftEmoji = '${recentGift?['emoji'] ?? ''}'.trim();
    final giftEmoji =
        giftAt != null && DateTime.now().difference(giftAt).inHours < 48
            ? (recentGiftEmoji.isEmpty ? '🎁' : recentGiftEmoji)
            : '';
    final reaction = '${effectiveVisit?['reaction'] ?? ''}'.trim();
    final momentLine = visited
        ? reaction.isNotEmpty
            ? reaction
            : (asking
                ? 'world.choiceAskResult'.tr
                : 'world.choiceStayResult'.tr)
        : eventTitle.isNotEmpty
            ? eventTitle
            : 'world.phase.quiet'.tr;
    return ClipRRect(
      borderRadius: BorderRadius.circular(30),
      child: ColoredBox(
        color: vita.surface,
        child: Column(children: [
          Expanded(
            child: ClipRect(
                child: Stack(fit: StackFit.expand, children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 900),
                curve: Curves.easeInOutCubic,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: visited
                        ? [glow.withValues(alpha: .85), sky]
                        : [sky, glow],
                  ),
                ),
              ),
              if (imageUrl.isNotEmpty)
                AnimatedSlide(
                  duration: const Duration(milliseconds: 850),
                  curve: Curves.easeOutCubic,
                  offset: !visited
                      ? Offset.zero
                      : asking
                          ? const Offset(-.035, 0)
                          : const Offset(.025, 0),
                  child: AnimatedScale(
                    duration: const Duration(milliseconds: 1100),
                    curve: Curves.easeOutCubic,
                    scale: !visited
                        ? 1
                        : asking
                            ? 1.18
                            : 1.10,
                    child: AnimatedRotation(
                      turns: !visited
                          ? 0
                          : asking
                              ? -.006
                              : .006,
                      duration: const Duration(milliseconds: 1100),
                      curve: Curves.easeOutCubic,
                      child: VitaMediaImage(
                        url: imageUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const SizedBox.expand(),
                      ),
                    ),
                  ),
                ),
              AnimatedOpacity(
                duration: const Duration(milliseconds: 850),
                opacity: visited ? 1 : 0,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: asking
                          ? const Alignment(.85, -.35)
                          : const Alignment(-.8, .25),
                      radius: 1.15,
                      colors: [
                        (asking ? const Color(0xFFB6A0FF) : glow)
                            .withValues(alpha: .28),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
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
              if (giftEmoji.isNotEmpty)
                Positioned(
                  top: 56,
                  right: 18,
                  child: Semantics(
                    label: '${recentGift?['name_key'] ?? 'world.giveGift'}'.tr,
                    child: Container(
                      width: 40,
                      height: 40,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: const Color(0xCC17141F),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.white24),
                      ),
                      child:
                          Text(giftEmoji, style: const TextStyle(fontSize: 22)),
                    ),
                  ),
                ),
              Positioned(
                left: 20,
                right: 20,
                bottom: 19,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      height: 23,
                      child: visited
                          ? Row(children: [
                              Icon(
                                  asking
                                      ? Icons.record_voice_over_rounded
                                      : Icons.favorite_rounded,
                                  size: 15,
                                  color: Colors.white),
                              const SizedBox(width: 6),
                              Expanded(
                                  child: Text(
                                asking
                                    ? 'world.sceneAsk'.tr
                                    : 'world.sceneStay'.tr,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600),
                              )),
                            ])
                          : const SizedBox.shrink(),
                    ),
                    Text(name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 30,
                            fontWeight: FontWeight.w700)),
                    const SizedBox(height: 6),
                    SizedBox(
                      height: 36,
                      child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 350),
                          child: Text(momentLine,
                              key: ValueKey(momentLine),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  height: 1.3,
                                  fontWeight: FontWeight.w500))),
                    ),
                  ],
                ),
              ),
            ])),
          ),
          SizedBox(
            height: 164,
            child: ColoredBox(
              color: vita.surface,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(19, 12, 19, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                        height: 20,
                        child: Row(children: [
                          Expanded(
                            child: Text(
                              visited
                                  ? 'world.visited'.tr
                                  : placeTitle.isEmpty
                                      ? 'world.visit'.tr
                                      : 'world.visitAt'.trParams({
                                          'place': placeTitle.isEmpty
                                              ? 'world.place.home'.tr
                                              : placeTitle.tr,
                                        }),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  color: vita.green,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700),
                            ),
                          ),
                          if (visitBusy)
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: SizedBox.square(
                                dimension: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: vita.green,
                                ),
                              ),
                            ),
                        ])),
                    const SizedBox(height: 8),
                    Row(children: [
                      Expanded(
                          child: _VisitChoice(
                        label: visited
                            ? 'world.sceneContinue'.tr
                            : 'world.choiceStay'.tr,
                        icon: visited
                            ? Icons.chat_bubble_outline_rounded
                            : Icons.favorite_outline_rounded,
                        primary: true,
                        onTap: visited
                            ? onChat
                            : visitBusy
                                ? null
                                : () => onVisitChoice('stay'),
                      )),
                      const SizedBox(width: 8),
                      Expanded(
                          child: _VisitChoice(
                        label: visited
                            ? 'world.openJourney'.tr
                            : 'world.choiceAsk'.tr,
                        icon: visited
                            ? Icons.auto_stories_outlined
                            : Icons.question_answer_outlined,
                        onTap: visited
                            ? onJourney
                            : visitBusy
                                ? null
                                : () => onVisitChoice('ask'),
                      )),
                    ]),
                    const SizedBox(height: 8),
                    Row(children: [
                      if (!visited)
                        Expanded(
                            child: _WorldUtilityAction(
                          label: 'world.talk'.tr,
                          icon: Icons.chat_bubble_outline_rounded,
                          onTap: onChat,
                        )),
                      Expanded(
                          child: _WorldUtilityAction(
                        label: 'world.giveGift'.tr,
                        icon: Icons.card_giftcard_outlined,
                        onTap: onGift,
                      )),
                      Expanded(
                          child: _WorldUtilityAction(
                        label: 'world.leaveNote'.tr,
                        icon: Icons.edit_note_rounded,
                        onTap: onNote,
                      )),
                    ]),
                  ],
                ),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

class _VisitChoice extends StatelessWidget {
  const _VisitChoice(
      {required this.label,
      required this.icon,
      required this.onTap,
      this.primary = false});

  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final vita = context.vita;
    final primaryText = Theme.of(context).colorScheme.onPrimary;
    return Material(
      color: primary ? vita.green : vita.greenTint,
      borderRadius: BorderRadius.circular(13),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(13),
        child: Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(13),
            border: primary
                ? null
                : Border.all(color: vita.green.withValues(alpha: .28)),
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, size: 16, color: primary ? primaryText : vita.green),
            const SizedBox(width: 5),
            Flexible(
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: primary ? primaryText : vita.text,
                        fontSize: 11,
                        fontWeight: FontWeight.w700))),
          ]),
        ),
      ),
    );
  }
}

class _WorldUtilityAction extends StatelessWidget {
  const _WorldUtilityAction(
      {required this.label, required this.icon, required this.onTap});

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          height: 48,
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, size: 17, color: context.vita.subText),
            const SizedBox(height: 2),
            Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: context.vita.subText, fontSize: 10)),
          ]),
        ),
      );
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
