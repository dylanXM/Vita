import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'dart:convert';

import '../../core/api_client.dart';
import '../../core/analytics_service.dart';
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
          data
              .whereType<Map<String, dynamic>>()
              .map((e) => Map<String, dynamic>.from(e)),
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
    AnalyticsService.to.track('life_timeline_viewed',
        category: 'life', properties: {'companion_id': id});
    try {
      final data =
          await ApiClient.instance.get('/v1/companions/$id/life/today');
      if (data is List) {
        events.assignAll(
          data
              .whereType<Map<String, dynamic>>()
              .map((e) => Map<String, dynamic>.from(e)),
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
      backgroundColor: context.vita.pageBg,
      // Bottom is open so the timeline scrolls behind the glass tab bar.
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            VitaTabHeader(
              title: 'life.title'.tr,
              subtitle: 'life.subtitle'.tr,
            ),
            Obx(() {
              if (ctrl.companions.isEmpty) return const SizedBox.shrink();
              return VitaCompanionChips(
                companions: ctrl.companions,
                selectedId: ctrl.selectedId.value,
                onChanged: (v) {
                  ctrl.selectedId.value = v;
                  ctrl.loadEvents();
                },
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
      return VitaEmpty(
        icon: Icons.photo_library_outlined,
        title: 'life.createFirst'.tr,
        subtitle: 'life.createFirstSub'.tr,
      );
    }
    if (ctrl.loading.value && ctrl.events.isEmpty) {
      return ListView.builder(
        padding: const EdgeInsets.only(bottom: 90),
        itemCount: 4,
        itemBuilder: (_, __) => const VitaSkeletonCard(withAvatar: false),
      );
    }
    if (ctrl.events.isEmpty) {
      return VitaEmpty(
        icon: Icons.schedule,
        title: 'life.empty'.tr,
        subtitle: 'life.emptySub'.tr,
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 0, 90),
      itemCount: ctrl.events.length,
      itemBuilder: (context, i) {
        final e = ctrl.events[i];
        final title = e['title'] as String? ?? '';
        final desc = e['description'] as String? ?? '';
        final loc = e['location'] as String? ?? '';
        final payload = e['payload'] is Map
            ? Map<String, dynamic>.from(e['payload'] as Map)
            : const <String, dynamic>{};
        final relatedName = payload['related_companion_name'] as String? ?? '';
        final media = (payload['media_urls'] as List? ?? const [])
            .whereType<String>()
            .where((url) => url.isNotEmpty)
            .toList();
        final rawTime = e['start_time'] as String?;
        final when = rawTime != null
            ? formatClock(DateTime.tryParse(rawTime) ?? DateTime.now())
            : '';
        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: 48,
                child: Column(
                  children: [
                    Text(when,
                        textAlign: TextAlign.right,
                        style: TextStyle(
                            fontSize: 11.5, color: context.vita.subText)),
                    const SizedBox(height: 6),
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                          color: context.vita.green, shape: BoxShape.circle),
                    ),
                    if (i != ctrl.events.length - 1)
                      Expanded(
                          child: Container(
                              width: 2,
                              margin: const EdgeInsets.only(top: 4),
                              color: context.vita.divider)),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: VitaCard(
                  margin: EdgeInsets.only(
                      bottom: i == ctrl.events.length - 1 ? 0 : 1),
                  padding: const EdgeInsets.fromLTRB(16, 13, 16, 13),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title.tr,
                          style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: context.vita.text)),
                      if (desc.isNotEmpty) ...[
                        const SizedBox(height: 5),
                        Text(desc.tr,
                            style: TextStyle(
                                fontSize: 13,
                                color: context.vita.subText,
                                height: 1.5)),
                      ],
                      if (media.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        _LifePhoto(url: media.first),
                      ],
                      if (loc.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.place_outlined,
                                size: 13, color: context.vita.subText),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                loc,
                                style: TextStyle(
                                    fontSize: 12, color: context.vita.subText),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                      if (relatedName.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.people_outline,
                                size: 13, color: context.vita.green),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                'explore.with'.trParams({'name': relatedName}),
                                style: TextStyle(
                                    fontSize: 12, color: context.vita.green),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
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

class _LifePhoto extends StatelessWidget {
  const _LifePhoto({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    ImageProvider provider;
    if (url.startsWith('data:image/') && url.contains(',')) {
      provider = MemoryImage(base64Decode(url.substring(url.indexOf(',') + 1)));
    } else {
      provider = NetworkImage(url);
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: AspectRatio(
        aspectRatio: 4 / 3,
        child: Image(
          image: provider,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => ColoredBox(
            color: context.vita.pageBg,
            child: Icon(Icons.broken_image_outlined, color: context.vita.hint),
          ),
        ),
      ),
    );
  }
}
