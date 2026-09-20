import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/api_client.dart';
import '../../core/analytics_service.dart';
import '../../core/theme.dart';
import '../../shared/widgets.dart';

/// Memories tab — shared memories and long-term memory of the user.
class MemoriesController extends GetxController {
  static MemoriesController get to => Get.find();

  final loading = false.obs;
  final companions = <Map<String, dynamic>>[].obs;
  final selectedId = RxnString();
  final memories = <Map<String, dynamic>>[].obs;

  @override
  void onInit() {
    super.onInit();
    loadCompanions();
  }

  Future<void> loadCompanions() async {
    loading.value = true;
    try {
      final data = await ApiClient.instance.get('/v1/companions');
      if (data is List) {
        companions.assignAll(
          data
              .whereType<Map<String, dynamic>>()
              .map((e) => Map<String, dynamic>.from(e)),
        );
      }
      if (companions.isNotEmpty && selectedId.value == null) {
        selectedId.value = companions.first['id'] as String;
        await loadMemories();
      }
    } catch (_) {
    } finally {
      loading.value = false;
    }
  }

  Future<void> loadMemories() async {
    final id = selectedId.value;
    if (id == null) return;
    loading.value = true;
    AnalyticsService.to.track('memory_list_viewed',
        category: 'life', properties: {'companion_id': id});
    try {
      final data = await ApiClient.instance.get('/v1/companions/$id/memories');
      final list = data is Map ? data['memories'] : data;
      if (list is List) {
        memories.assignAll(
          list
              .whereType<Map<String, dynamic>>()
              .map((e) => Map<String, dynamic>.from(e)),
        );
      }
    } catch (_) {
    } finally {
      loading.value = false;
    }
  }

  Future<void> updateMemory(String id, String content) async {
    final companionId = selectedId.value;
    if (companionId == null) return;
    await ApiClient.instance.put('/v1/companions/$companionId/memories/$id',
        data: {'content': content});
    await loadMemories();
  }

  Future<void> deleteMemory(String id) async {
    final companionId = selectedId.value;
    if (companionId == null) return;
    await ApiClient.instance.delete('/v1/companions/$companionId/memories/$id');
    memories.removeWhere((item) => item['id'] == id);
  }
}

class MemoriesPage extends StatelessWidget {
  const MemoriesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final ctrl = MemoriesController.to;
    return Scaffold(
      backgroundColor: context.vita.pageBg,
      body: SafeArea(
        bottom: false,
        child: Column(children: [
          VitaTabHeader(
            title: 'memories.title'.tr,
            subtitle: 'memories.subtitle'.tr,
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Obx(() {
                  if (ctrl.companions.isEmpty) return const SizedBox.shrink();
                  return VitaCompanionChips(
                    companions: ctrl.companions,
                    selectedId: ctrl.selectedId.value,
                    onChanged: (v) {
                      ctrl.selectedId.value = v;
                      ctrl.loadMemories();
                    },
                  );
                }),
                Expanded(child: Obx(() => _buildBody(ctrl))),
              ],
            ),
          ),
        ]),
      ),
    );
  }

  Widget _buildBody(MemoriesController ctrl) {
    if (ctrl.companions.isEmpty) {
      return VitaEmpty(
        icon: Icons.star_border,
        title: 'memories.createFirst'.tr,
        subtitle: 'memories.createFirstSub'.tr,
      );
    }
    if (ctrl.loading.value && ctrl.memories.isEmpty) {
      return ListView.builder(
        padding: const EdgeInsets.only(bottom: 90),
        itemCount: 4,
        itemBuilder: (_, __) => const VitaSkeletonCard(withAvatar: false),
      );
    }
    if (ctrl.memories.isEmpty) {
      return VitaEmpty(
        icon: Icons.star_border,
        title: 'memories.empty'.tr,
        subtitle: 'memories.emptySub'.tr,
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(0, 8, 0, 90),
      itemCount: ctrl.memories.length,
      separatorBuilder: (context, _) =>
          Divider(height: 0.5, indent: 60, color: context.vita.divider),
      itemBuilder: (context, i) {
        final m = ctrl.memories[i];
        final content = m['content'] as String? ?? '';
        final type = m['type'] as String? ?? 'memory';
        final when = m['event_time'] as String?;
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: context.vita.surface),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: context.vita.green.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.star, size: 17, color: context.vita.green),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(content.tr,
                        style: TextStyle(
                            fontSize: 15,
                            color: context.vita.text,
                            height: 1.45)),
                    const SizedBox(height: 6),
                    Text(
                      [
                        type,
                        when != null
                            ? formatDate(
                                DateTime.tryParse(when) ?? DateTime.now())
                            : null
                      ].where((e) => e != null && e.isNotEmpty).join(' · '),
                      style:
                          TextStyle(fontSize: 12, color: context.vita.subText),
                    ),
                  ],
                ),
              ),
              if (m['readonly'] != true)
                PopupMenuButton<String>(
                  onSelected: (action) {
                    if (action == 'edit') {
                      _editMemory(context, ctrl, m);
                    } else if (action == 'delete') {
                      _deleteMemory(context, ctrl, m);
                    }
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(
                        value: 'edit', child: Text('memories.edit'.tr)),
                    PopupMenuItem(
                        value: 'delete', child: Text('memories.delete'.tr)),
                  ],
                ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _editMemory(BuildContext context, MemoriesController ctrl,
      Map<String, dynamic> memory) async {
    final input =
        TextEditingController(text: memory['content'] as String? ?? '');
    final value = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('memories.edit'.tr),
        content: TextField(
            controller: input, minLines: 2, maxLines: 5, maxLength: 500),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text('common.cancel'.tr)),
          FilledButton(
              onPressed: () => Navigator.pop(dialogContext, input.text.trim()),
              child: Text('common.save'.tr)),
        ],
      ),
    );
    input.dispose();
    if (value != null && value.isNotEmpty) {
      await ctrl.updateMemory(memory['id'] as String, value);
    }
  }

  Future<void> _deleteMemory(BuildContext context, MemoriesController ctrl,
      Map<String, dynamic> memory) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('memories.delete'.tr),
        content: Text('memories.deleteConfirm'.tr),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text('common.cancel'.tr)),
          FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text('memories.delete'.tr)),
        ],
      ),
    );
    if (confirmed == true) await ctrl.deleteMemory(memory['id'] as String);
  }
}
