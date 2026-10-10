import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/analytics_service.dart';
import '../../core/api_client.dart';
import '../../core/theme.dart';
import '../../shared/media_image.dart';
import '../../shared/widgets.dart';
import '../life/life_detail_page.dart';
import '../chat/chat_page.dart';
import '../chat/companion_moment_page.dart';
import '../shell/shell_page.dart';

class MemoriesController extends GetxController {
  static MemoriesController get to => Get.find();

  final companionsLoading = false.obs;
  final memoriesLoading = false.obs;
  final companions = <Map<String, dynamic>>[].obs;
  final memories = <Map<String, dynamic>>[].obs;
  final journey = <Map<String, dynamic>>[].obs;
  final journeyLoading = false.obs;
  final journeyLoadingMore = false.obs;
  final journeyFailed = false.obs;
  final journeyHasMore = false.obs;
  final activeCompanionId = RxnString();
  String? _journeyCompanionId;
  String _journeyQuery = '';
  int _journeyOffset = 0;
  int _journeyRequest = 0;

  @override
  void onInit() {
    super.onInit();
    loadCompanions();
    loadJourney();
  }

  Future<void> loadJourney({String? companionId, String query = ''}) async {
    _journeyCompanionId = companionId;
    _journeyQuery = query.trim();
    final request = ++_journeyRequest;
    journey.clear();
    journeyHasMore.value = false;
    _journeyOffset = 0;
    journeyLoading.value = true;
    journeyFailed.value = false;
    try {
      final data = await ApiClient.instance.get('/v1/journey', query: {
        'limit': 30,
        if (companionId != null) 'companion_id': companionId,
        if (_journeyQuery.isNotEmpty) 'q': _journeyQuery,
      });
      if (request != _journeyRequest) return;
      final payload = data is Map ? data : const {};
      journey.assignAll((payload['items'] as List? ?? const [])
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item)));
      _journeyOffset =
          (payload['next_offset'] as num?)?.toInt() ?? journey.length;
      journeyHasMore.value = payload['has_more'] == true;
    } catch (_) {
      if (request == _journeyRequest) journeyFailed.value = true;
    } finally {
      if (request == _journeyRequest) journeyLoading.value = false;
    }
  }

  Future<void> loadMoreJourney() async {
    if (journeyLoading.value ||
        journeyLoadingMore.value ||
        !journeyHasMore.value) {
      return;
    }
    final request = _journeyRequest;
    journeyLoadingMore.value = true;
    try {
      final data = await ApiClient.instance.get('/v1/journey', query: {
        'limit': 30,
        'offset': _journeyOffset,
        if (_journeyCompanionId != null) 'companion_id': _journeyCompanionId,
        if (_journeyQuery.isNotEmpty) 'q': _journeyQuery,
      });
      if (request != _journeyRequest) return;
      final payload = data is Map ? data : const {};
      final next = (payload['items'] as List? ?? const [])
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item));
      journey.addAll(next);
      _journeyOffset =
          (payload['next_offset'] as num?)?.toInt() ?? journey.length;
      journeyHasMore.value = payload['has_more'] == true;
    } catch (_) {
      if (request == _journeyRequest) journeyFailed.value = true;
    } finally {
      journeyLoadingMore.value = false;
    }
  }

  Future<void> loadCompanions() async {
    companionsLoading.value = true;
    try {
      final data = await ApiClient.instance.get('/v1/companions');
      if (data is List) {
        companions.assignAll(
          data
              .whereType<Map<String, dynamic>>()
              .where((item) => item['creation_source'] != 'ai_pet')
              .map((item) => Map<String, dynamic>.from(item)),
        );
      }
    } catch (_) {
    } finally {
      companionsLoading.value = false;
    }
  }

  Future<void> loadMemories(String companionId) async {
    activeCompanionId.value = companionId;
    memories.clear();
    memoriesLoading.value = true;
    AnalyticsService.to.track(
      'memory_list_viewed',
      category: 'life',
      properties: {'companion_id': companionId},
    );
    try {
      final data =
          await ApiClient.instance.get('/v1/companions/$companionId/memories');
      if (activeCompanionId.value != companionId) return;
      final list = data is Map ? data['memories'] : data;
      if (list is List) {
        memories.assignAll(
          list
              .whereType<Map<String, dynamic>>()
              .map((item) => Map<String, dynamic>.from(item)),
        );
      }
    } catch (_) {
    } finally {
      if (activeCompanionId.value == companionId) {
        memoriesLoading.value = false;
      }
    }
  }

  Future<void> updateMemory(
    String companionId,
    String memoryId,
    String content,
  ) async {
    await ApiClient.instance.put(
      '/v1/companions/$companionId/memories/$memoryId',
      data: {'content': content},
    );
    await loadMemories(companionId);
  }

  Future<void> deleteMemory(String companionId, String memoryId) async {
    await ApiClient.instance
        .delete('/v1/companions/$companionId/memories/$memoryId');
    if (activeCompanionId.value == companionId) {
      memories.removeWhere((item) => item['id'] == memoryId);
    }
  }
}

String _journeyContent(Map<String, dynamic> item) {
  final raw = '${item['content'] ?? ''}';
  if (item['type'] == 'shared_experience' ||
      item['type'] == 'experience_appointment') {
    final stage = _journeyExperienceStage(item);
    if (stage == 'booked') {
      final metadata = item['metadata'] as Map?;
      final start =
          DateTime.tryParse('${metadata?['starts_at'] ?? ''}')?.toLocal();
      return start == null
          ? 'journey.booked'.tr
          : 'journey.bookedAt'.trParams({
              'date': formatDate(start),
              'time': formatClock(start),
            });
    }
    if (stage == 'active') {
      return raw.isEmpty ? 'journey.inProgress'.tr : raw.tr;
    }
    if (stage == 'finished') {
      return raw.isEmpty ? 'journey.finished'.tr : raw.tr;
    }
    if (raw.startsWith('experience.date.') && raw.endsWith('.desc')) {
      return 'journey.legacyMoment'.tr;
    }
  }
  if (item['type'] == 'world_visit') {
    if (raw == 'The user visited me today.') return 'journey.visitMoment'.tr;
    if (raw == 'The user stayed with me during a visit.') {
      return 'journey.visitStay'.tr;
    }
    if (raw == 'The user asked about my day during a visit.') {
      return 'journey.visitAsk'.tr;
    }
  }
  return raw.tr;
}

String _journeyExperienceStage(Map<String, dynamic> item) {
  if (item['type'] != 'shared_experience' &&
      item['type'] != 'experience_appointment') {
    return '';
  }
  final metadata = item['metadata'];
  if (metadata is! Map || '${metadata['event_id'] ?? ''}'.isEmpty) {
    return '';
  }
  final stage = '${metadata['stage'] ?? ''}';
  return const {'booked', 'active', 'finished'}.contains(stage) ? stage : '';
}

String _journeyActionLabel(Map<String, dynamic> item) {
  if (item['type'] == 'world_visit') return 'journey.viewMoment'.tr;
  switch (_journeyExperienceStage(item)) {
    case 'booked':
      return 'journey.prepareExperience'.tr;
    case 'active':
      return 'journey.continueExperience'.tr;
    case 'finished':
      return 'journey.revisitExperience'.tr;
    default:
      return 'journey.openCompanion'.tr;
  }
}

/// A searchable collection of companion journeys.
class MemoriesPage extends StatefulWidget {
  const MemoriesPage({super.key});

  @override
  State<MemoriesPage> createState() => _MemoriesPageState();
}

class _MemoriesPageState extends State<MemoriesPage> {
  final TextEditingController _search = TextEditingController();
  final ScrollController _scroll = ScrollController();
  bool _showSearch = false;
  String? _selectedCompanionId;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.hasClients &&
          _scroll.position.extentAfter < 500 &&
          Get.isRegistered<MemoriesController>()) {
        MemoriesController.to.loadMoreJourney();
      }
    });
  }

  @override
  void dispose() {
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    final controller = MemoriesController.to;
    await Future.wait([
      controller.loadCompanions(),
      controller.loadJourney(companionId: _selectedCompanionId, query: _query),
    ]);
  }

  Future<void> _chooseCompanion(BuildContext context) async {
    final controller = MemoriesController.to;
    final selected = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      backgroundColor: context.vita.surface,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              title: Text('journey.allCompanions'.tr),
              trailing: _selectedCompanionId == null
                  ? Icon(Icons.check, color: context.vita.green)
                  : null,
              onTap: () => Navigator.pop(sheetContext, ''),
            ),
            for (final companion in controller.companions)
              ListTile(
                leading: VitaAvatar(
                  name: '${companion['name'] ?? ''}',
                  radius: 20,
                  imageUrl: companion['portrait_url'] as String?,
                ),
                title: Text('${companion['name'] ?? ''}',
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                trailing: _selectedCompanionId == '${companion['id']}'
                    ? Icon(Icons.check, color: context.vita.green)
                    : null,
                onTap: () => Navigator.pop(sheetContext, '${companion['id']}'),
              ),
          ],
        ),
      ),
    );
    if (selected == null || !mounted) return;
    setState(() => _selectedCompanionId = selected.isEmpty ? null : selected);
    await controller.loadJourney(
        companionId: _selectedCompanionId, query: _query);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: context.vita.pageBg,
        body: SafeArea(
          bottom: false,
          child: Obx(() => _buildBody(context, MemoriesController.to)),
        ),
      );

  Widget _buildBody(BuildContext context, MemoriesController controller) {
    final selected = controller.companions.firstWhereOrNull(
        (companion) => '${companion['id']}' == _selectedCompanionId);
    final label = selected == null
        ? 'journey.allCompanions'.tr
        : '${selected['name'] ?? ''}';
    return RefreshIndicator(
      onRefresh: _reload,
      child: CustomScrollView(
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
              child: VitaTabHeader(
            title: 'tab.journey'.tr,
            showDivider: false,
            actions: IconButton(
              tooltip: 'contacts.search'.tr,
              icon: Icon(_showSearch ? Icons.close : Icons.search_rounded),
              onPressed: () {
                setState(() {
                  _showSearch = !_showSearch;
                  if (!_showSearch) {
                    _search.clear();
                    _query = '';
                    controller.loadJourney(companionId: _selectedCompanionId);
                  }
                });
              },
            ),
          )),
          SliverToBoxAdapter(
              child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 2, 18, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => _chooseCompanion(context),
                icon: const Icon(Icons.tune_rounded, size: 18),
                label:
                    Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
            ),
          )),
          if (_showSearch)
            SliverToBoxAdapter(
                child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
              child: TextField(
                controller: _search,
                autofocus: true,
                textInputAction: TextInputAction.search,
                onSubmitted: (value) {
                  _query = value.trim();
                  controller.loadJourney(
                      companionId: _selectedCompanionId, query: _query);
                },
                decoration: InputDecoration(
                  hintText: 'contacts.search'.tr,
                  prefixIcon: const Icon(Icons.search_rounded),
                  filled: true,
                  fillColor: context.vita.surface,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(color: context.vita.divider),
                  ),
                ),
              ),
            )),
          if ((controller.journeyLoading.value ||
                  controller.companionsLoading.value) &&
              controller.journey.isEmpty)
            SliverList.builder(
              itemCount: 3,
              itemBuilder: (_, __) => const VitaSkeletonCard(withAvatar: true),
            )
          else if (controller.journey.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: VitaEmpty(
                icon: controller.journeyFailed.value
                    ? Icons.wifi_off_outlined
                    : Icons.auto_stories_outlined,
                title: controller.journeyFailed.value
                    ? 'common.loadFailed'.tr
                    : _query.isNotEmpty
                        ? 'contacts.noResults'.tr
                        : controller.companions.isEmpty
                            ? 'memories.createFirst'.tr
                            : 'memories.empty'.tr,
                subtitle: controller.journeyFailed.value
                    ? 'common.pullToRetry'.tr
                    : _query.isNotEmpty
                        ? 'contacts.noResultsSub'.tr
                        : controller.companions.isEmpty
                            ? 'memories.createFirstSub'.tr
                            : 'memories.emptySub'.tr,
              ),
            )
          else ...[
            ..._journeyMonthSlivers(controller.journey),
            if (controller.journeyHasMore.value ||
                controller.journeyLoadingMore.value)
              SliverToBoxAdapter(
                  child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 110),
                child: Center(
                    child: controller.journeyLoadingMore.value
                        ? const CircularProgressIndicator()
                        : TextButton(
                            onPressed: controller.loadMoreJourney,
                            child: Text('journey.loadMore'.tr),
                          )),
              ))
            else
              const SliverToBoxAdapter(child: SizedBox(height: 110)),
          ],
        ],
      ),
    );
  }

  List<Widget> _journeyMonthSlivers(List<Map<String, dynamic>> items) {
    final groups = <({String? month, List<Map<String, dynamic>> items})>[];
    for (final item in items) {
      final date = DateTime.tryParse('${item['event_time'] ?? ''}')?.toLocal();
      final month = date == null
          ? null
          : '${date.year}.${date.month.toString().padLeft(2, '0')}';
      if (groups.isEmpty || groups.last.month != month) {
        groups.add((month: month, items: [item]));
      } else {
        groups.last.items.add(item);
      }
    }
    return [
      for (final group in groups) ...[
        if (group.month != null)
          SliverPersistentHeader(
            pinned: true,
            delegate: _JourneyMonthHeader(
              group.month!,
              background: context.vita.pageBg,
              foreground: context.vita.subText,
            ),
          ),
        SliverList.builder(
          itemCount: group.items.length,
          itemBuilder: (context, index) {
            final item = group.items[index];
            return Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 8),
              child: _JourneyEventTile(
                item: item,
                onTap: () => _openEvent(context, item),
              ),
            );
          },
        ),
      ],
    ];
  }

  void _openEvent(BuildContext context, Map<String, dynamic> item) {
    AnalyticsService.to
        .track('journey_item_opened', category: 'life', properties: {
      'type': '${item['type'] ?? ''}',
      'experience_stage': _journeyExperienceStage(item),
    });
    final companion =
        Map<String, dynamic>.from(item['companion'] as Map? ?? {});
    final companionId = '${companion['id'] ?? ''}';
    final metadata = item['metadata'] is Map
        ? Map<String, dynamic>.from(item['metadata'] as Map)
        : const <String, dynamic>{};
    final eventId = '${metadata['event_id'] ?? ''}';
    if (_journeyExperienceStage(item).isNotEmpty &&
        companionId.isNotEmpty &&
        eventId.isNotEmpty) {
      Get.to(
          () => CompanionMomentPage(
                companionId: companionId,
                eventId: eventId,
                name: '${companion['name'] ?? ''}',
                avatarUrl: companion['portrait_url'] as String?,
              ),
          transition: Transition.cupertino);
      return;
    }
    if (item['type'] == 'world_visit' && companionId.isNotEmpty) {
      Get.to(() => _JourneyVisitPage(item: item),
          transition: Transition.cupertino);
      return;
    }
    final time = DateTime.tryParse('${item['event_time'] ?? ''}')?.toLocal();
    final content = _journeyContent(item);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: context.vita.surface,
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 4, 24, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('${companion['name'] ?? ''}',
                  style: TextStyle(color: context.vita.subText, fontSize: 13)),
              if (time != null) ...[
                const SizedBox(height: 6),
                Text(formatDateSeparator(time),
                    style:
                        TextStyle(color: context.vita.subText, fontSize: 12)),
              ],
              if ('${item['title'] ?? ''}'.isNotEmpty) ...[
                const SizedBox(height: 14),
                Text('${item['title']}'.tr,
                    style: TextStyle(
                        color: context.vita.text,
                        fontSize: 21,
                        fontWeight: FontWeight.w700)),
              ],
              const SizedBox(height: 18),
              Text(content,
                  style: TextStyle(
                      color: context.vita.text, fontSize: 16, height: 1.6)),
              const SizedBox(height: 24),
              SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () {
                      Navigator.pop(sheetContext);
                      Get.to(() => MemoryDetailPage(companion: companion),
                          transition: Transition.cupertino);
                    },
                    child: Text('journey.openCompanion'.tr),
                  )),
              if (companionId.isNotEmpty) ...[
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () {
                      Navigator.pop(sheetContext);
                      Get.to(
                          () => ChatPage(
                                companionId: companionId,
                                name: '${companion['name'] ?? ''}',
                                companion: companion,
                              ),
                          transition: Transition.cupertino);
                    },
                    icon: const Icon(Icons.chat_bubble_outline_rounded),
                    label: Text('world.talk'.tr),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// A past visit is a specific shared scene, not a generic memory action sheet.
class _JourneyVisitPage extends StatelessWidget {
  const _JourneyVisitPage({required this.item});

  final Map<String, dynamic> item;

  @override
  Widget build(BuildContext context) {
    final vita = context.vita;
    final companion =
        Map<String, dynamic>.from(item['companion'] as Map? ?? {});
    final metadata = item['metadata'] is Map
        ? Map<String, dynamic>.from(item['metadata'] as Map)
        : const <String, dynamic>{};
    final name = '${companion['name'] ?? ''}';
    final companionId = '${companion['id'] ?? ''}';
    final imageUrl =
        '${metadata['portrait_url'] ?? companion['portrait_url'] ?? ''}';
    final eventTitle = '${metadata['event_title'] ?? ''}'.trim();
    final date = DateTime.tryParse('${item['event_time'] ?? ''}')?.toLocal();
    final asking = metadata['choice'] == 'ask';
    return Scaffold(
      backgroundColor: vita.pageBg,
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 18, 10),
            child: Row(children: [
              IconButton(
                onPressed: () => Get.back(),
                icon: const Icon(Icons.arrow_back_ios_new_rounded),
              ),
              Expanded(
                child: Text('journey.viewMoment'.tr,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: vita.text,
                        fontSize: 17,
                        fontWeight: FontWeight.w700)),
              ),
            ]),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(28),
                child: Stack(fit: StackFit.expand, children: [
                  ColoredBox(color: vita.surface),
                  if (imageUrl.isNotEmpty)
                    TweenAnimationBuilder<double>(
                      tween: Tween(begin: 1.06, end: 1),
                      duration: const Duration(milliseconds: 700),
                      curve: Curves.easeOutCubic,
                      builder: (_, scale, child) =>
                          Transform.scale(scale: scale, child: child),
                      child: VitaMediaImage(url: imageUrl, fit: BoxFit.cover),
                    ),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Color(0x66000000),
                          Color(0x11000000),
                          Color(0xE6000000)
                        ],
                        stops: [0, .42, 1],
                      ),
                    ),
                  ),
                  Positioned(
                    left: 20,
                    right: 20,
                    top: 20,
                    child: Text(
                        date == null
                            ? name
                            : '$name  ·  ${formatDateSeparator(date)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style:
                            const TextStyle(color: Colors.white, fontSize: 13)),
                  ),
                  Positioned(
                    left: 22,
                    right: 22,
                    bottom: 28,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                            asking
                                ? Icons.record_voice_over_rounded
                                : Icons.favorite_rounded,
                            color: Colors.white,
                            size: 24),
                        const SizedBox(height: 10),
                        Text(
                            asking ? 'world.sceneAsk'.tr : 'world.sceneStay'.tr,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 24,
                                fontWeight: FontWeight.w700)),
                        if (eventTitle.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(eventTitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: Colors.white70, fontSize: 13)),
                        ],
                        const SizedBox(height: 12),
                        Text(_journeyContent(item),
                            maxLines: 5,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                height: 1.5)),
                      ],
                    ),
                  ),
                ]),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
            child: Row(children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () {
                    Get.back();
                    ShellController.to.selectedCompanionId.value = companionId;
                    ShellController.to.switchTo(0);
                  },
                  child: Text('journey.enterWorld'.tr,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  onPressed: () => Get.to(
                      () => ChatPage(
                          companionId: companionId,
                          name: name,
                          companion: companion),
                      transition: Transition.cupertino),
                  child: Text('world.talk'.tr,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _JourneyMonthHeader extends SliverPersistentHeaderDelegate {
  const _JourneyMonthHeader(this.label,
      {required this.background, required this.foreground});

  final String label;
  final Color background;
  final Color foreground;

  @override
  double get minExtent => 48;

  @override
  double get maxExtent => 48;

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    return ColoredBox(
      color: background,
      child: Align(
        alignment: Alignment.centerLeft,
        child: Padding(
          padding: const EdgeInsets.only(left: 30, right: 20),
          child: Text(label,
              style: TextStyle(
                  color: foreground,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 2)),
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _JourneyMonthHeader oldDelegate) =>
      label != oldDelegate.label ||
      background != oldDelegate.background ||
      foreground != oldDelegate.foreground;
}

class _JourneyEventTile extends StatelessWidget {
  const _JourneyEventTile({required this.item, required this.onTap});

  final Map<String, dynamic> item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final companion =
        Map<String, dynamic>.from(item['companion'] as Map? ?? {});
    final name = '${companion['name'] ?? ''}';
    final imageUrl = '${companion['portrait_url'] ?? ''}';
    final time = DateTime.tryParse('${item['event_time'] ?? ''}')?.toLocal();
    final title = '${item['title'] ?? ''}'.trim();
    final content = _journeyContent(item);
    final isKeepsake = item['type'] == 'keepsake';
    final accent = context.vita.green;
    return SizedBox(
      height: 144,
      child: Row(children: [
        SizedBox(
            width: 19,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Positioned(
                    top: 0,
                    bottom: 0,
                    child: Container(
                        width: 1, color: accent.withValues(alpha: .36))),
                Positioned(
                    top: 25,
                    child: Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                            color: accent,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                  color: accent.withValues(alpha: .5),
                                  blurRadius: 10,
                                  spreadRadius: 2)
                            ]))),
              ],
            )),
        const SizedBox(width: 7),
        Expanded(
            child: Material(
          color: context.vita.surface,
          borderRadius: BorderRadius.circular(23),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Stack(fit: StackFit.expand, children: [
              DecoratedBox(
                  decoration: BoxDecoration(
                      gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  accent.withValues(alpha: .66),
                  context.vita.surface,
                  context.vita.surface
                ],
                stops: const [0, .6, 1],
              ))),
              if (imageUrl.isNotEmpty)
                Positioned(
                    right: 0,
                    top: 0,
                    bottom: 0,
                    width: 145,
                    child: VitaMediaImage(
                        url: imageUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const SizedBox.expand())),
              Positioned.fill(
                  child: DecoratedBox(
                      decoration: BoxDecoration(
                          gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  context.vita.surface,
                  context.vita.surface.withValues(alpha: .96),
                  context.vita.surface.withValues(alpha: .48)
                ],
                stops: const [0, .54, 1],
              )))),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 14, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Icon(
                          isKeepsake
                              ? Icons.bookmark_rounded
                              : item['type'] == 'world_visit'
                                  ? Icons.waving_hand_rounded
                                  : Icons.auto_awesome_rounded,
                          size: 15,
                          color: accent),
                      const SizedBox(width: 7),
                      Expanded(
                          child: Text(name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  color: context.vita.text,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700))),
                      if (time != null)
                        Text(formatClock(time),
                            style: TextStyle(
                                color: context.vita.subText, fontSize: 11)),
                    ]),
                    const Spacer(),
                    if (title.isNotEmpty) ...[
                      FractionallySizedBox(
                          alignment: Alignment.centerLeft,
                          widthFactor: .78,
                          child: Text(title.tr,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  color: context.vita.text,
                                  fontSize: 17,
                                  fontWeight: FontWeight.w700))),
                      const SizedBox(height: 6),
                    ],
                    FractionallySizedBox(
                        alignment: Alignment.centerLeft,
                        widthFactor: .78,
                        child: Text(content,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: context.vita.text,
                                fontSize: title.isEmpty ? 17 : 13,
                                fontWeight: title.isEmpty
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                                height: 1.35))),
                    const SizedBox(height: 7),
                    Row(children: [
                      Expanded(
                          child: Text(
                        _journeyActionLabel(item),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: accent,
                            fontSize: 12,
                            fontWeight: FontWeight.w600),
                      )),
                      Icon(Icons.arrow_forward_rounded,
                          size: 16, color: accent),
                    ]),
                  ],
                ),
              ),
            ]),
          ),
        )),
      ]),
    );
  }
}

class _FilmPerforations extends StatelessWidget {
  const _FilmPerforations();

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 13,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: List.generate(
            12,
            (_) => Container(
              width: 13,
              height: 5,
              decoration: BoxDecoration(
                color: context.vita.pageBg,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ),
      );
}

class _PortraitFallback extends StatelessWidget {
  const _PortraitFallback({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(gradient: context.vita.brandGradient),
        child: Center(
          child: Text(
            name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase(),
            style: TextStyle(
              fontSize: 56,
              fontWeight: FontWeight.w300,
              color: Colors.white.withValues(alpha: .9),
            ),
          ),
        ),
      );
}

/// Second level: all memories belonging to one companion.
class MemoryDetailPage extends StatefulWidget {
  const MemoryDetailPage({super.key, required this.companion});

  final Map<String, dynamic> companion;

  @override
  State<MemoryDetailPage> createState() => _MemoryDetailPageState();
}

class _MemoryDetailPageState extends State<MemoryDetailPage> {
  MemoriesController get controller => MemoriesController.to;
  String get companionId => widget.companion['id'] as String? ?? '';

  @override
  void initState() {
    super.initState();
    controller.loadMemories(companionId);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.vita.pageBg,
      appBar: AppBar(
        leading: const VitaBackButton(),
        title: Text('tab.journey'.tr),
      ),
      body: SafeArea(
        bottom: false,
        child: Obx(() => _buildBody(context)),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (controller.memoriesLoading.value && controller.memories.isEmpty) {
      return ListView(
        children: [
          _JourneyDetailHeader(companion: widget.companion, onTap: _openLife),
          for (var i = 0; i < 3; i++) const VitaSkeletonCard(withAvatar: false),
        ],
      );
    }

    return RefreshIndicator(
      onRefresh: () => controller.loadMemories(companionId),
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: _JourneyDetailHeader(
                companion: widget.companion, onTap: _openLife),
          ),
          if (controller.memories.isEmpty)
            SliverToBoxAdapter(
              child: SizedBox(
                height: 260,
                child: VitaEmpty(
                  icon: Icons.star_border,
                  title: 'memories.empty'.tr,
                  subtitle: 'memories.emptySub'.tr,
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.only(top: 4, bottom: 32),
              sliver: SliverList(
                delegate: SliverChildListDelegate(_buildGroupedTiles(context)),
              ),
            ),
        ],
      ),
    );
  }

  List<Widget> _buildGroupedTiles(BuildContext context) {
    final tiles = <Widget>[];
    final ordered = controller.memories.toList()
      ..sort((a, b) => (_memoryTime(b) ?? DateTime(1970))
          .compareTo(_memoryTime(a) ?? DateTime(1970)));
    DateTime? prevDay;
    for (final m in ordered) {
      final localTime = _memoryTime(m)?.toLocal();
      if (localTime != null) {
        final day = DateTime(localTime.year, localTime.month, localTime.day);
        if (prevDay == null || day != prevDay) {
          tiles.add(_DateSectionHeader(label: formatDateSeparator(localTime)));
        }
        prevDay = day;
      }
      tiles.add(_MemoryTile(
        companionId: companionId,
        memory: m,
      ));
    }
    return tiles;
  }

  DateTime? _memoryTime(Map<String, dynamic> memory) => DateTime.tryParse(
        memory['event_time'] as String? ??
            memory['created_at'] as String? ??
            '',
      );

  void _openLife() => Get.to(
        () => LifeDetailPage(companion: widget.companion),
        transition: Transition.cupertino,
      );
}

class _JourneyDetailHeader extends StatelessWidget {
  const _JourneyDetailHeader({required this.companion, required this.onTap});

  final Map<String, dynamic> companion;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final name = '${companion['name'] ?? 'chat.companion'.tr}';
    final portraitUrl = (companion['portrait_url'] as String?)?.trim() ?? '';
    final details = [companion['city'], companion['occupation']]
        .whereType<String>()
        .where((value) => value.trim().isNotEmpty)
        .join(' · ');
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
      child: Semantics(
        button: true,
        label: 'journey.life'.tr,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Container(
            height: 182,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: const Color(0xFF222127),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Stack(
              children: [
                Positioned.fill(
                  child: portraitUrl.isEmpty
                      ? _PortraitFallback(name: name)
                      : VitaMediaImage(
                          url: portraitUrl,
                          errorBuilder: (_, __, ___) =>
                              _PortraitFallback(name: name),
                        ),
                ),
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withValues(alpha: .06),
                          Colors.black.withValues(alpha: .14),
                          Colors.black.withValues(alpha: .75),
                        ],
                        stops: const [0, .42, 1],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 22,
                  right: 22,
                  bottom: 24,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'tab.journey'.tr.toUpperCase(),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 2,
                          color: Colors.white.withValues(alpha: .8),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 27,
                            height: 1.1,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          )),
                      const SizedBox(height: 8),
                      Text(
                        details.isEmpty ? 'journey.subtitle'.tr : details,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.35,
                          color: Colors.white.withValues(alpha: .86),
                        ),
                      ),
                    ],
                  ),
                ),
                Positioned(
                  top: 23,
                  right: 20,
                  child: Icon(Icons.arrow_outward_rounded,
                      size: 21, color: Colors.white.withValues(alpha: .9)),
                ),
                const Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: ColoredBox(
                    color: Color(0xFF222127),
                    child: _FilmPerforations(),
                  ),
                ),
                const Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: ColoredBox(
                    color: Color(0xFF222127),
                    child: _FilmPerforations(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DateSectionHeader extends StatelessWidget {
  const _DateSectionHeader({required this.label});
  final String label;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(26, 8, 24, 16),
      child: Row(
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: context.vita.green,
              shape: BoxShape.circle,
              border: Border.all(
                color: context.vita.greenTint,
                width: 3,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: context.vita.text,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(child: Divider(color: context.vita.divider)),
        ],
      ),
    );
  }
}

class _MemoryTile extends StatelessWidget {
  const _MemoryTile({
    required this.companionId,
    required this.memory,
  });

  final String companionId;
  final Map<String, dynamic> memory;

  @override
  Widget build(BuildContext context) {
    final title = (memory['title'] as String? ?? '').trim();
    final type = (memory['type'] as String? ?? 'memory').trim();
    final readonly = memory['readonly'] == true;
    final eventTime = DateTime.tryParse(
      memory['event_time'] as String? ?? memory['created_at'] as String? ?? '',
    )?.toLocal();
    final visibleContent = _journeyContent(memory);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      child: Material(
        color: const Color(0xFF222127),
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () =>
              _showFullMemory(context, title, visibleContent, eventTime),
          child: SizedBox(
            height: 180,
            child: Column(children: [
              const _FilmPerforations(),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 10, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Icon(
                          type == 'world_visit'
                              ? Icons.travel_explore_rounded
                              : Icons.auto_stories_rounded,
                          size: 16,
                          color: Colors.white70,
                        ),
                        const SizedBox(width: 8),
                        if (eventTime != null)
                          Text(formatClock(eventTime),
                              style: const TextStyle(
                                  color: Colors.white70, fontSize: 12)),
                        const Spacer(),
                        if (!readonly)
                          IconButton(
                            onPressed: () => _showActions(context),
                            icon:
                                const Icon(Icons.more_horiz_rounded, size: 21),
                            color: Colors.white70,
                            tooltip: 'memories.delete'.tr,
                            visualDensity: VisualDensity.compact,
                          ),
                      ]),
                      if (title.isNotEmpty) ...[
                        Text(title.tr,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            )),
                        const SizedBox(height: 7),
                      ],
                      Text(visibleContent,
                          maxLines: title.isEmpty ? 4 : 3,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 15,
                            color: Colors.white70,
                            height: 1.45,
                          )),
                    ],
                  ),
                ),
              ),
              const _FilmPerforations(),
            ]),
          ),
        ),
      ),
    );
  }

  Future<void> _showFullMemory(BuildContext context, String title,
      String content, DateTime? eventTime) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: context.vita.surface,
      builder: (sheetContext) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: .55,
        maxChildSize: .9,
        builder: (context, scrollController) => ListView(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
          children: [
            if (eventTime != null)
              Text(formatDateSeparator(eventTime),
                  style: TextStyle(color: context.vita.subText, fontSize: 13)),
            if (title.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(title.tr,
                  style: TextStyle(
                      color: context.vita.text,
                      fontSize: 22,
                      fontWeight: FontWeight.w700)),
            ],
            const SizedBox(height: 18),
            Text(content,
                style: TextStyle(
                    color: context.vita.text, fontSize: 16, height: 1.6)),
          ],
        ),
      ),
    );
  }

  Future<void> _showActions(BuildContext context) async {
    final selected = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: context.vita.surface,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ListTile(
          leading: const Icon(Icons.delete_outline),
          title: Text('memories.delete'.tr),
          onTap: () => Navigator.pop(sheetContext, true),
        ),
      ),
    );
    if (selected == true && context.mounted) {
      await _deleteMemory(context);
    }
  }

  Future<void> _deleteMemory(BuildContext context) async {
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (dialogContext) => CupertinoAlertDialog(
        title: Text('memories.delete'.tr),
        content: Text('memories.deleteConfirm'.tr),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text('common.cancel'.tr,
                style: const TextStyle(color: CupertinoColors.systemGrey)),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text('memories.delete'.tr),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await MemoriesController.to.deleteMemory(
        companionId,
        memory['id'] as String,
      );
    }
  }
}
