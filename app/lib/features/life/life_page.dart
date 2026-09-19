import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/api_client.dart';
import '../../core/theme.dart';
import '../../shared/widgets.dart';

/// Life tab — the companion's timeline for today ("what she experienced"),
/// distinct from Chat ("what she chose to tell you").
class LifeController extends GetxController {
  static LifeController get to => Get.find();

  final loading = false.obs;
  final companions = <Map<String, dynamic>>[].obs;
  final selectedId = RxnString();
  final events = <Map<String, dynamic>>[].obs;

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
        await loadEvents();
      }
    } catch (_) {
    } finally {
      loading.value = false;
    }
  }

  Future<void> loadEvents() async {
    final id = selectedId.value;
    if (id == null) return;
    loading.value = true;
    try {
      final data = await ApiClient.instance.get('/v1/companions/$id/life/today');
      if (data is List) {
        events.assignAll(
          data.whereType<Map<String, dynamic>>().map((e) => Map<String, dynamic>.from(e)),
        );
      }
    } catch (_) {
    } finally {
      loading.value = false;
    }
  }
}

class LifePage extends StatelessWidget {
  const LifePage({super.key});

  @override
  Widget build(BuildContext context) {
    final ctrl = LifeController.to;
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text(
                'Life',
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
                      ctrl.loadEvents();
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

  Widget _buildBody(LifeController ctrl) {
    if (ctrl.companions.isEmpty) {
      return const VitaEmpty(
        icon: Icons.photo_library_outlined,
        title: 'Create a companion first',
        subtitle: 'Life shows the day of someone who lives somewhere else',
      );
    }
    if (ctrl.loading.value && ctrl.events.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (ctrl.events.isEmpty) {
      return const VitaEmpty(
        icon: Icons.schedule,
        title: 'No life events yet today',
        subtitle: 'The Life Engine will fill this timeline soon',
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: ctrl.events.length,
      itemBuilder: (context, i) {
        final e = ctrl.events[i];
        final title = e['title'] as String? ?? '';
        final desc = e['description'] as String? ?? '';
        final loc = e['location'] as String? ?? '';
        final rawTime = e['start_time'] as String?;
        final when = rawTime != null ? formatClock(DateTime.tryParse(rawTime) ?? DateTime.now()) : '';
        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: 56,
                child: Column(
                  children: [
                    Text(when, style: const TextStyle(fontSize: 12, color: VitaColors.subText)),
                    const SizedBox(height: 4),
                    const Icon(Icons.circle, size: 10, color: VitaColors.green),
                    if (i != ctrl.events.length - 1)
                      Expanded(child: Container(width: 2, color: VitaColors.divider)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Container(
                  margin: const EdgeInsets.only(bottom: 14),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: VitaColors.pageBg,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: VitaColors.text)),
                      if (desc.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(desc, style: const TextStyle(fontSize: 13, color: VitaColors.subText)),
                      ],
                      if (loc.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            const Icon(Icons.place_outlined, size: 14, color: VitaColors.subText),
                            const SizedBox(width: 2),
                            Text(loc, style: const TextStyle(fontSize: 12, color: VitaColors.subText)),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
