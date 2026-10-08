import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/analytics_service.dart';
import '../../core/api_client.dart';
import '../../core/theme.dart';
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

/// A compact, searchable companion directory; each entry opens its timeline.
class MemoriesPage extends StatefulWidget {
  const MemoriesPage({super.key});

  @override
  State<MemoriesPage> createState() => _MemoriesPageState();
}

class _MemoriesPageState extends State<MemoriesPage> {
  final TextEditingController _search = TextEditingController();

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
            child: VitaTabHeader(title: 'tab.journey'.tr, showDivider: false),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 18),
              child: TextField(
                controller: _search,
                onChanged: (_) => setState(() {}),
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: 'contacts.search'.tr,
                  prefixIcon: Icon(Icons.search, color: context.vita.subText),
                  suffixIcon: query.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close, size: 18),
                          onPressed: () {
                            _search.clear();
                            setState(() {});
                          },
                        ),
                  filled: true,
                  fillColor: context.vita.surface,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
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
              padding: const EdgeInsets.only(bottom: 110),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final companion = visible[index];
                    return _JourneyCompanionTile(
                      companion: companion,
                      onTap: () {
                        if (Get.isRegistered<ShellController>()) {
                          ShellController.to.selectedCompanionId.value =
                              companion['id'] as String?;
                        }
                        Get.to(() => MemoryDetailPage(companion: companion),
                            transition: Transition.cupertino);
                      },
                    );
                  },
                  childCount: visible.length,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _JourneyCompanionTile extends StatelessWidget {
  const _JourneyCompanionTile({required this.companion, required this.onTap});

  final Map<String, dynamic> companion;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final name = '${companion['name'] ?? 'chat.companion'.tr}';
    final details = [companion['city'], companion['occupation']]
        .whereType<String>()
        .where((value) => value.trim().isNotEmpty)
        .join(' · ');
    return Material(
      color: context.vita.pageBg,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
          child: Column(children: [
            Row(children: [
              VitaAvatar(
                name: name,
                radius: 23,
                imageUrl: companion['portrait_url'] as String?,
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
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: context.vita.text)),
                    if (details.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(details,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 12.5, color: context.vita.subText)),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right, size: 18, color: context.vita.subText),
            ]),
            const SizedBox(height: 10),
            Divider(height: 1, indent: 60, color: context.vita.divider),
          ]),
        ),
      ),
    );
  }
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
    final name = widget.companion['name'] as String? ?? 'memories.title'.tr;
    return Scaffold(
      backgroundColor: context.vita.pageBg,
      appBar: AppBar(
        leading: const VitaBackButton(),
        title: Text(name),
        actions: [
          IconButton(
            icon: const Icon(Icons.auto_stories_outlined),
            color: context.vita.subText,
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
      return ListView.builder(
        itemCount: 5,
        itemBuilder: (_, __) => const VitaSkeletonCard(withAvatar: false),
      );
    }

    return RefreshIndicator(
      onRefresh: () => controller.loadMemories(companionId),
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          if (controller.memories.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: VitaEmpty(
                icon: Icons.star_border,
                title: 'memories.empty'.tr,
                subtitle: 'memories.emptySub'.tr,
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.only(top: 8, bottom: 32),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 22, 24, 18),
                    child: Text(
                      'journey.subtitle'.tr,
                      style: TextStyle(
                        fontSize: 14,
                        color: context.vita.subText,
                      ),
                    ),
                  ),
                  ..._buildGroupedTiles(context),
                ]),
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

class _DateSectionHeader extends StatelessWidget {
  const _DateSectionHeader({required this.label});
  final String label;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 18, 24, 14),
      child: Row(
        children: [
          Icon(Icons.auto_awesome, size: 15, color: context.vita.green),
          const SizedBox(width: 12),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
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

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
      child: Stack(
        children: [
          Positioned(
            left: 6,
            top: 0,
            bottom: 0,
            child: Container(
              width: 1,
              color: context.vita.green.withValues(alpha: 0.22),
            ),
          ),
          Positioned(
            left: 2,
            top: 26,
            child: Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: context.vita.green,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 26),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 18, 12, 20),
              decoration: BoxDecoration(
                color: context.vita.surface,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: context.vita.divider),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (title.isNotEmpty) ...[
                          Text(title,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: context.vita.green,
                              )),
                          const SizedBox(height: 10),
                        ],
                        Text(
                          type == 'world_visit'
                              ? 'world.visitMemory'.tr
                              : content.tr,
                          style: TextStyle(
                            fontSize: 16,
                            color: context.vita.text,
                            height: 1.55,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (!readonly)
                    IconButton(
                      onPressed: () => _showActions(context),
                      icon: const Icon(Icons.more_vert, size: 19),
                      color: context.vita.subText,
                      tooltip: 'memories.delete'.tr,
                      visualDensity: VisualDensity.compact,
                    ),
                ],
              ),
            ),
          ),
        ],
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
