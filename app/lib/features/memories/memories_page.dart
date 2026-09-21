import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/analytics_service.dart';
import '../../core/api_client.dart';
import '../../core/theme.dart';
import '../../shared/widgets.dart';

class MemoriesController extends GetxController {
  static MemoriesController get to => Get.find();

  final companionsLoading = false.obs;
  final memoriesLoading = false.obs;
  final companions = <Map<String, dynamic>>[].obs;
  final memories = <Map<String, dynamic>>[].obs;
  final activeCompanionId = RxnString();
  final searchQuery = ''.obs;

  /// Companions filtered by name / city / occupation for the search box.
  List<Map<String, dynamic>> get filteredCompanions {
    final q = searchQuery.value.trim().toLowerCase();
    if (q.isEmpty) return List.of(companions);
    return companions.where((companion) {
      final name = (companion['name'] as String? ?? '').toLowerCase();
      final city = (companion['city'] as String? ?? '').toLowerCase();
      final occupation =
          (companion['occupation'] as String? ?? '').toLowerCase();
      return name.contains(q) || city.contains(q) || occupation.contains(q);
    }).toList();
  }

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

/// First level: a contact-style list. Memories from different companions are
/// deliberately kept separate instead of sharing an in-page selector.
///
/// It is a root dock tab, so it carries the same borderless top header as the
/// other tabs and its list scrolls behind the floating glass tab bar.
class MemoriesPage extends StatelessWidget {
  const MemoriesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = MemoriesController.to;
    return Scaffold(
      backgroundColor: context.vita.pageBg,
      // Bottom is open so the list scrolls behind the glass tab bar.
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            VitaTabHeader(title: 'memories.title'.tr, showDivider: false),
            const _MemorySearchBox(),
            Expanded(child: Obx(() => _buildBody(context, controller))),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, MemoriesController controller) {
    if (controller.companionsLoading.value && controller.companions.isEmpty) {
      return ListView.builder(
        padding: const EdgeInsets.only(bottom: 90),
        itemCount: 6,
        itemBuilder: (_, __) => const VitaSkeletonCard(withAvatar: true),
      );
    }
    if (controller.companions.isEmpty) {
      return RefreshIndicator(
        onRefresh: controller.loadCompanions,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
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

    final list = controller.filteredCompanions;
    if (list.isEmpty) {
      return VitaEmpty(
        icon: Icons.search,
        title: 'memories.noResults'.tr,
        subtitle: 'memories.noResultsSub'.tr,
      );
    }

    return RefreshIndicator(
      onRefresh: controller.loadCompanions,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(top: 8, bottom: 90),
        itemCount: list.length,
        separatorBuilder: (_, __) => Divider(
          height: 0.5,
          indent: 72,
          color: context.vita.divider,
        ),
        itemBuilder: (context, index) => _MemoryContactTile(
          companion: list[index],
        ),
      ),
    );
  }
}

/// WeChat-style rounded search field filtering the companion list.
class _MemorySearchBox extends StatelessWidget {
  const _MemorySearchBox();

  @override
  Widget build(BuildContext context) {
    final controller = MemoriesController.to;
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 4, 0, 8),
      child: TextField(
        onChanged: (v) => controller.searchQuery.value = v,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: 'memories.search'.tr,
          hintStyle: TextStyle(color: context.vita.hint, fontSize: 14),
          prefixIcon: Icon(Icons.search, size: 18, color: context.vita.hint),
          filled: true,
          fillColor: context.vita.surface,
          contentPadding: const EdgeInsets.symmetric(vertical: 0),
          isDense: true,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.zero,
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.zero,
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.zero,
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }
}

class _MemoryContactTile extends StatelessWidget {
  const _MemoryContactTile({required this.companion});

  final Map<String, dynamic> companion;

  @override
  Widget build(BuildContext context) {
    final id = companion['id'] as String? ?? '';
    final name = companion['name'] as String? ?? 'chat.companion'.tr;
    final city = (companion['city'] as String? ?? '').trim();
    final occupation = (companion['occupation'] as String? ?? '').trim();
    final profile =
        [city, occupation].where((item) => item.isNotEmpty).join(' · ');

    return Material(
      color: context.vita.surface,
      child: InkWell(
        onTap: id.isEmpty
            ? null
            : () {
                AnalyticsService.to.track(
                  'memory_companion_opened',
                  category: 'navigation',
                  properties: {'companion_id': id},
                );
                Get.to(
                  () => MemoryDetailPage(companion: companion),
                  transition: Transition.cupertino,
                  duration: const Duration(milliseconds: 300),
                );
              },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          child: Row(
            children: [
              VitaAvatar(
                name: name,
                radius: 22,
                imageUrl: companion['portrait_url'] as String?,
                borderRadius: BorderRadius.circular(10),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: context.vita.text,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      profile.isEmpty ? 'memories.subtitle'.tr : profile,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: context.vita.subText,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, size: 20, color: context.vita.chevron),
            ],
          ),
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
      appBar: AppBar(title: Text(name)),
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
          SliverToBoxAdapter(
              child: _CompanionMemoryHeader(companion: widget.companion)),
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
              padding: const EdgeInsets.only(top: 12, bottom: 24),
              sliver: SliverList.separated(
                itemCount: controller.memories.length,
                separatorBuilder: (_, __) => Divider(
                  height: 0.5,
                  indent: 60,
                  color: context.vita.divider,
                ),
                itemBuilder: (context, index) => _MemoryTile(
                  companionId: companionId,
                  memory: controller.memories[index],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _CompanionMemoryHeader extends StatelessWidget {
  const _CompanionMemoryHeader({required this.companion});

  final Map<String, dynamic> companion;

  @override
  Widget build(BuildContext context) {
    final name = companion['name'] as String? ?? 'chat.companion'.tr;
    return Container(
      color: context.vita.surface,
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
      child: Row(
        children: [
          VitaAvatar(
            name: name,
            radius: 30,
            imageUrl: companion['portrait_url'] as String?,
            borderRadius: BorderRadius.circular(12),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: context.vita.text,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'memories.subtitle'.tr,
                  style: TextStyle(fontSize: 13, color: context.vita.subText),
                ),
              ],
            ),
          ),
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
    final eventTime = DateTime.tryParse(memory['event_time'] as String? ?? '');
    final createdAt = DateTime.tryParse(memory['created_at'] as String? ?? '');
    final date = eventTime ?? createdAt;
    final readonly = memory['readonly'] == true;

    return Container(
      color: context.vita.surface,
      padding: const EdgeInsets.fromLTRB(16, 14, 10, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: context.vita.green.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              readonly ? Icons.bookmark_outline : Icons.star_outline,
              size: 18,
              color: context.vita.green,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (title.isNotEmpty) ...[
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w600,
                      color: context.vita.text,
                    ),
                  ),
                  const SizedBox(height: 4),
                ],
                Text(
                  content.tr,
                  style: TextStyle(
                    fontSize: 15,
                    color: context.vita.text,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  [
                    type,
                    if (date != null) formatDate(date.toLocal()),
                  ].where((item) => item.isNotEmpty).join(' · '),
                  style: TextStyle(fontSize: 12, color: context.vita.subText),
                ),
              ],
            ),
          ),
          if (!readonly)
            PopupMenuButton<String>(
              onSelected: (action) {
                if (action == 'edit') {
                  _editMemory(context);
                } else if (action == 'delete') {
                  _deleteMemory(context);
                }
              },
              itemBuilder: (_) => [
                PopupMenuItem(value: 'edit', child: Text('memories.edit'.tr)),
                PopupMenuItem(
                  value: 'delete',
                  child: Text('memories.delete'.tr),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Future<void> _editMemory(BuildContext context) async {
    final input =
        TextEditingController(text: memory['content'] as String? ?? '');
    final value = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('memories.edit'.tr),
        content: TextField(
          controller: input,
          minLines: 2,
          maxLines: 5,
          maxLength: 500,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text('common.cancel'.tr),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, input.text.trim()),
            child: Text('common.save'.tr),
          ),
        ],
      ),
    );
    input.dispose();
    if (value != null && value.isNotEmpty) {
      await MemoriesController.to.updateMemory(
        companionId,
        memory['id'] as String,
        value,
      );
    }
  }

  Future<void> _deleteMemory(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('memories.delete'.tr),
        content: Text('memories.deleteConfirm'.tr),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text('common.cancel'.tr),
          ),
          FilledButton(
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
