import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/api_client.dart';
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
          data.whereType<Map<String, dynamic>>().map((e) => Map<String, dynamic>.from(e)),
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
    try {
      final data = await ApiClient.instance.get('/v1/companions/$id/memories');
      final list = data is Map ? data['memories'] : data;
      if (list is List) {
        memories.assignAll(
          list.whereType<Map<String, dynamic>>().map((e) => Map<String, dynamic>.from(e)),
        );
      }
    } catch (_) {
    } finally {
      loading.value = false;
    }
  }
}

class MemoriesPage extends StatelessWidget {
  const MemoriesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final ctrl = MemoriesController.to;
    return Scaffold(
      backgroundColor: VitaColors.pageBg,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const VitaTabHeader(
              title: 'Memories',
              subtitle: 'Moments you keep together',
            ),
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
    );
  }

  Widget _buildBody(MemoriesController ctrl) {
    if (ctrl.companions.isEmpty) {
      return const VitaEmpty(
        icon: Icons.star_border,
        title: 'Create a companion first',
        subtitle: 'Memories grow out of shared experiences',
      );
    }
    if (ctrl.loading.value && ctrl.memories.isEmpty) {
      return ListView.builder(
        itemCount: 4,
        itemBuilder: (_, __) => const VitaSkeletonCard(withAvatar: false),
      );
    }
    if (ctrl.memories.isEmpty) {
      return const VitaEmpty(
        icon: Icons.star_border,
        title: 'No memories yet',
        subtitle: 'Shared moments will appear here over time',
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
      itemCount: ctrl.memories.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, i) {
        final m = ctrl.memories[i];
        final content = m['content'] as String? ?? '';
        final type = m['type'] as String? ?? 'memory';
        final when = m['event_time'] as String?;
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: VitaColors.surface,
            borderRadius: BorderRadius.circular(VitaRadius.md),
            boxShadow: VitaShadow.card,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: VitaColors.green.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.star, size: 17, color: VitaColors.green),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(content, style: const TextStyle(fontSize: 15, color: VitaColors.text, height: 1.45)),
                    const SizedBox(height: 6),
                    Text(
                      [type, when != null ? formatDate(DateTime.tryParse(when) ?? DateTime.now()) : null]
                          .where((e) => e != null && e.isNotEmpty)
                          .join(' · '),
                      style: const TextStyle(fontSize: 12, color: VitaColors.subText),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
