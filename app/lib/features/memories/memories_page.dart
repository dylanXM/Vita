import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/analytics_service.dart';
import '../../core/api_client.dart';
import '../../core/theme.dart';
import '../../shared/media_image.dart';
import '../../shared/widgets.dart';
import '../life/life_detail_page.dart';
import '../shell/shell_page.dart';

class MemoriesController extends GetxController {
  static MemoriesController get to => Get.find();

  final companionsLoading = false.obs;
  final memoriesLoading = false.obs;
  final companions = <Map<String, dynamic>>[].obs;
  final memories = <Map<String, dynamic>>[].obs;
  final activeCompanionId = RxnString();

  @override
  void onInit() {
    super.onInit();
    loadCompanions();
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

/// A searchable collection of companion journeys.
class MemoriesPage extends StatefulWidget {
  const MemoriesPage({super.key});

  @override
  State<MemoriesPage> createState() => _MemoriesPageState();
}

class _MemoriesPageState extends State<MemoriesPage> {
  final TextEditingController _search = TextEditingController();
  bool _showSearch = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.vita.pageBg,
      body: SafeArea(
        bottom: false,
        child: Obx(() => _buildBody(context, MemoriesController.to)),
      ),
    );
  }

  Widget _buildBody(BuildContext context, MemoriesController controller) {
    if (controller.companionsLoading.value && controller.companions.isEmpty) {
      return ListView(
        children: [
          VitaTabHeader(title: 'tab.journey'.tr, showDivider: false),
          const VitaSkeletonCard(withAvatar: true),
        ],
      );
    }
    if (controller.companions.isEmpty) {
      return RefreshIndicator(
        onRefresh: controller.loadCompanions,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            VitaTabHeader(title: 'tab.journey'.tr, showDivider: false),
            SizedBox(
              height: MediaQuery.sizeOf(context).height * 0.62,
              child: VitaEmpty(
                icon: Icons.star_border,
                title: 'memories.createFirst'.tr,
                subtitle: 'memories.createFirstSub'.tr,
              ),
            ),
          ],
        ),
      );
    }

    final companions = controller.companions.toList()
      ..sort((a, b) => '${a['name'] ?? ''}'
          .toLowerCase()
          .compareTo('${b['name'] ?? ''}'.toLowerCase()));
    final query = _search.text.trim().toLowerCase();
    final visible = query.isEmpty
        ? companions
        : companions.where((companion) {
            final name = '${companion['name'] ?? ''}'.toLowerCase();
            final city = '${companion['city'] ?? ''}'.toLowerCase();
            final occupation = '${companion['occupation'] ?? ''}'.toLowerCase();
            return name.contains(query) ||
                city.contains(query) ||
                occupation.contains(query);
          }).toList();
    return RefreshIndicator(
      onRefresh: controller.loadCompanions,
      child: CustomScrollView(
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
                    if (!_showSearch) _search.clear();
                  });
                },
              ),
            ),
          ),
          if (_showSearch)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                child: TextField(
                  controller: _search,
                  autofocus: true,
                  onChanged: (_) => setState(() {}),
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: 'contacts.search'.tr,
                    prefixIcon: Icon(Icons.search, color: context.vita.subText),
                    filled: true,
                    fillColor: context.vita.surface,
                    isDense: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(18),
                      borderSide: BorderSide(color: context.vita.divider),
                    ),
                  ),
                ),
              ),
            ),
          if (visible.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: VitaEmpty(
                icon: Icons.search_off,
                title: 'contacts.noResults'.tr,
                subtitle: 'contacts.noResultsSub'.tr,
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 110),
              sliver: SliverList.builder(
                itemCount: visible.length,
                itemBuilder: (context, index) {
                  final companion = visible[index];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _JourneyCompanionTile(
                      companion: companion,
                      onTap: () {
                        if (Get.isRegistered<ShellController>()) {
                          ShellController.to.selectedCompanionId.value =
                              companion['id'] as String?;
                        }
                        Get.to(() => MemoryDetailPage(companion: companion),
                            transition: Transition.cupertino);
                      },
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _JourneyCompanionTile extends StatelessWidget {
  const _JourneyCompanionTile({
    required this.companion,
    required this.onTap,
  });

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
    final persona = (companion['persona'] as String?)?.trim() ?? '';
    final interests = (companion['interests'] as String?)?.trim() ?? '';
    final summary = details.isNotEmpty
        ? details
        : (persona.isNotEmpty ? persona : interests);
    final vita = context.vita;
    return Material(
      color: const Color(0xFF222127),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: vita.divider.withValues(alpha: .35)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: 132,
          child: Column(children: [
            const _FilmPerforations(),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 5, 13, 5),
                child: Row(children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: SizedBox(
                      width: 88,
                      height: double.infinity,
                      child: portraitUrl.isEmpty
                          ? _PortraitFallback(name: name)
                          : VitaMediaImage(
                              url: portraitUrl,
                              errorBuilder: (_, __, ___) =>
                                  _PortraitFallback(name: name),
                            ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            )),
                        const SizedBox(height: 4),
                        Text(summary.isEmpty ? 'journey.subtitle'.tr : summary,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 12,
                                height: 1.35,
                                color: Colors.white70)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 5),
                  const Icon(Icons.arrow_forward_rounded,
                      size: 18, color: Colors.white70),
                ]),
              ),
            ),
            const _FilmPerforations(),
          ]),
        ),
      ),
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
        actions: [
          IconButton(
            icon: const Icon(Icons.auto_stories_outlined),
            color: context.vita.green,
            tooltip: 'journey.life'.tr,
            onPressed: () => Get.to(
              () => LifeDetailPage(companion: widget.companion),
              transition: Transition.cupertino,
            ),
          ),
        ],
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
          _JourneyDetailHeader(companion: widget.companion),
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
            child: _JourneyDetailHeader(companion: widget.companion),
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
}

class _JourneyDetailHeader extends StatelessWidget {
  const _JourneyDetailHeader({required this.companion});

  final Map<String, dynamic> companion;

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
    final content = memory['content'] as String? ?? '';
    final title = (memory['title'] as String? ?? '').trim();
    final type = (memory['type'] as String? ?? 'memory').trim();
    final readonly = memory['readonly'] == true;
    final eventTime = DateTime.tryParse(
      memory['event_time'] as String? ?? memory['created_at'] as String? ?? '',
    )?.toLocal();
    final visibleContent =
        type == 'world_visit' ? 'world.visitMemory'.tr : content.tr;

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
