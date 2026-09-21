import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/api_client.dart';
import '../../core/analytics_service.dart';
import '../../core/theme.dart';
import '../../shared/widgets.dart';
import 'life_detail_page.dart';

/// Contacts tab — WeChat-style contacts list of all the user's AI companions,
/// with a rounded search field. Tapping a contact opens the chat thread.
class LifeController extends GetxController {
  static LifeController get to => Get.find();

  final loading = false.obs;
  final companions = <Map<String, dynamic>>[].obs;
  final searchQuery = ''.obs;

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
    } catch (_) {
    } finally {
      loading.value = false;
    }
  }

  /// Filtered list by name / city / occupation / interests.
  List<Map<String, dynamic>> get filtered {
    final q = searchQuery.value.trim().toLowerCase();
    if (q.isEmpty) return List.of(companions);
    return companions.where((c) {
      final name = (c['name'] as String? ?? '').toLowerCase();
      final city = (c['city'] as String? ?? '').toLowerCase();
      final occupation = (c['occupation'] as String? ?? '').toLowerCase();
      final interests = (c['interests'] as String? ?? '').toLowerCase();
      return name.contains(q) ||
          city.contains(q) ||
          occupation.contains(q) ||
          interests.contains(q);
    }).toList();
  }
}

class LifePage extends StatelessWidget {
  const LifePage({super.key});

  @override
  Widget build(BuildContext context) {
    final ctrl = LifeController.to;
    return Scaffold(
      backgroundColor: context.vita.pageBg,
      // Bottom is open so the list scrolls behind the glass tab bar.
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            VitaTabHeader(
              title: 'contacts.title'.tr,
              showDivider: false,
            ),
            _SearchBox(),
            Expanded(child: Obx(() => _buildBody(context, ctrl))),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, LifeController ctrl) {
    if (ctrl.loading.value && ctrl.companions.isEmpty) {
      return ListView.builder(
        padding: const EdgeInsets.only(bottom: 90),
        itemCount: 6,
        itemBuilder: (_, __) => const VitaSkeletonCard(withAvatar: true),
      );
    }
    if (ctrl.companions.isEmpty) {
      return VitaEmpty(
        icon: Icons.contacts_outlined,
        title: 'contacts.empty'.tr,
        subtitle: 'contacts.emptySub'.tr,
      );
    }
    final list = ctrl.filtered;
    if (list.isEmpty) {
      return VitaEmpty(
        icon: Icons.search,
        title: 'contacts.noResults'.tr,
        subtitle: 'contacts.noResultsSub'.tr,
      );
    }
    return Column(
      children: [
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.only(top: 1, bottom: 12),
            itemCount: list.length,
            separatorBuilder: (_, __) => Divider(
              indent: 68,
              height: 0.5,
              color: context.vita.divider,
            ),
            itemBuilder: (context, i) => _ContactTile(companion: list[i]),
          ),
        ),
        // WeChat-style footer: total contact count.
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            '${list.length}',
            style: TextStyle(fontSize: 12, color: context.vita.hint),
          ),
        ),
      ],
    );
  }
}

class _SearchBox extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final ctrl = LifeController.to;
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 4, 0, 8),
      child: TextField(
        onChanged: (v) => ctrl.searchQuery.value = v,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: 'contacts.search'.tr,
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

class _ContactTile extends StatelessWidget {
  const _ContactTile({required this.companion});

  final Map<String, dynamic> companion;

  @override
  Widget build(BuildContext context) {
    final name = companion['name'] as String? ?? 'Companion';
    final city = (companion['city'] as String? ?? '').trim();
    final occupation = (companion['occupation'] as String? ?? '').trim();
    final infoParts = [
      if (city.isNotEmpty) city,
      if (occupation.isNotEmpty) occupation,
    ];
    final info = infoParts.join(' · ');
    final id = companion['id'] as String;

    return Material(
      color: context.vita.surface,
      child: InkWell(
        onTap: () {
          AnalyticsService.to.track('life_detail_opened',
              category: 'navigation', properties: {'companion_id': id});
          Get.to(
            () => LifeDetailPage(companion: companion),
            transition: Transition.cupertino,
            duration: const Duration(milliseconds: 300),
          );
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          child: Row(
            children: [
              // WeChat-sized rounded-square avatar: 40x40.
              VitaAvatar(
                name: name,
                radius: 20,
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
                    if (info.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        info,
                        style: TextStyle(
                          fontSize: 12,
                          color: context.vita.subText,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
