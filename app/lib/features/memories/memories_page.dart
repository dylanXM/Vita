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
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text(
                'Memories',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: VitaColors.text),
              ),
            ),
            Obx(() {
              if (ctrl.companions.isEmpty) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: ctrl.selectedId.value,
                    isDense: true,
                    icon: const Icon(Icons.arrow_drop_down, color: VitaColors.green),
                    style: const TextStyle(fontSize: 15, color: VitaColors.text, fontWeight: FontWeight.w600),
                    items: ctrl.companions
                        .map((c) => DropdownMenuItem(
                              value: c['id'] as String?,
                              child: Text('${c['name']} · ${c['city'] ?? ''}'),
                            ))
                        .toList(),
                    onChanged: (v) {
                      ctrl.selectedId.value = v;
                      ctrl.loadMemories();
                    },
                  ),
                ),
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
      return const Center(child: CircularProgressIndicator());
    }
    if (ctrl.memories.isEmpty) {
      return const VitaEmpty(
        icon: Icons.star_border,
        title: 'No memories yet',
        subtitle: 'Shared moments will appear here over time',
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: ctrl.memories.length,
      separatorBuilder: (_, __) => const Divider(),
      itemBuilder: (context, i) {
        final m = ctrl.memories[i];
        final content = m['content'] as String? ?? '';
        final type = m['type'] as String? ?? 'memory';
        final when = m['event_time'] as String?;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.star, size: 18, color: VitaColors.green),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(content, style: const TextStyle(fontSize: 15, color: VitaColors.text)),
                    const SizedBox(height: 4),
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
