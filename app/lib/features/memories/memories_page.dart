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
    final vita = context.vita;
    return Material(
      color: vita.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: vita.divider.withValues(alpha: .8)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: SizedBox(
            height: 112,
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(17),
                  child: SizedBox(
                    width: 104,
                    height: 112,
                    child: portraitUrl.isEmpty
                        ? _PortraitFallback(name: name)
                        : VitaMediaImage(
                            url: portraitUrl,
                            errorBuilder: (_, __, ___) =>
                                _PortraitFallback(name: name),
                          ),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 6, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 19,
                                  fontWeight: FontWeight.w700,
                                  color: vita.text,
                                )),
                            if (details.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Text(
                                details,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontSize: 12,
                                    height: 1.35,
                                    color: vita.subText),
                              ),
                            ],
                          ],
                        ),
                        Align(
                          alignment: Alignment.centerRight,
                          child: Icon(Icons.arrow_forward_rounded,
                              size: 18, color: vita.green),
                        ),
                      ],
                    ),
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
    DateTime? prevDay;
    for (var i = 0; i < controller.memories.length; i++) {
      final m = controller.memories[i];
      final t = DateTime.tryParse(
              m['event_time'] as String? ?? m['created_at'] as String? ?? '') ??
          DateTime.now();
      final localTime = t.toLocal();
      final day = DateTime(localTime.year, localTime.month, localTime.day);
      if (prevDay == null || day != prevDay) {
        tiles.add(_DateSectionHeader(label: formatDateSeparator(localTime)));
      }
      tiles.add(_MemoryTile(
        companionId: companionId,
        memory: m,
      ));
      prevDay = day;
    }
    return tiles;
  }
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
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
      child: Container(
        height: 228,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          gradient: context.vita.brandGradient,
          borderRadius: BorderRadius.circular(28),
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
              bottom: 22,
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
                        fontSize: 31,
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
  const _MemoryTile({required this.companionId, required this.memory});

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
    final vita = context.vita;

    return Padding(
      padding: const EdgeInsets.fromLTRB(44, 0, 20, 12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(17, 14, 8, 18),
        decoration: BoxDecoration(
          color: vita.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: vita.divider.withValues(alpha: .8)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: vita.greenTint,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    type == 'world_visit'
                        ? Icons.travel_explore_rounded
                        : Icons.auto_stories_rounded,
                    size: 17,
                    color: vita.green,
                  ),
                ),
                if (eventTime != null) ...[
                  const SizedBox(width: 10),
                  Text(
                    formatClock(eventTime),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: vita.subText,
                    ),
                  ),
                ],
                const Spacer(),
                if (!readonly)
                  IconButton(
                    onPressed: () => _showActions(context),
                    icon: const Icon(Icons.more_horiz_rounded, size: 21),
                    color: vita.subText,
                    tooltip: 'memories.delete'.tr,
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(2, 12, 12, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (title.isNotEmpty) ...[
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: vita.text,
                      ),
                    ),
                    const SizedBox(height: 7),
                  ],
                  Text(
                    type == 'world_visit' ? 'world.visitMemory'.tr : content.tr,
                    style: TextStyle(
                      fontSize: 15,
                      color: title.isNotEmpty ? vita.subText : vita.text,
                      height: 1.55,
                    ),
                  ),
                ],
              ),
            ),
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
