import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/analytics_service.dart';
import '../../core/api_client.dart';
import '../../core/theme.dart';
import '../../shared/widgets.dart';
import '../../shared/media_image.dart';
import '../memories/memories_page.dart';

class ExploreController extends GetxController {
  static ExploreController get to => Get.find();

  final section = 0.obs;
  final loading = false.obs;
  final posts = <Map<String, dynamic>>[].obs;

  @override
  void onInit() {
    super.onInit();
    loadPosts();
  }

  Future<void> loadPosts() async {
    loading.value = true;
    AnalyticsService.to.track('explore_moments_viewed', category: 'life');
    try {
      final data = await ApiClient.instance.get('/v1/explore/posts');
      final list = data is Map ? data['posts'] : null;
      if (list is List) {
        posts.assignAll(
          list
              .whereType<Map<String, dynamic>>()
              .map((item) => Map<String, dynamic>.from(item)),
        );
      }
    } catch (_) {
    } finally {
      loading.value = false;
    }
  }

  void selectSection(int value) {
    if (section.value == value) {
      if (value == 0) loadPosts();
      return;
    }
    section.value = value;
    AnalyticsService.to.track(
      value == 0 ? 'explore_moments_viewed' : 'memory_list_viewed',
      category: 'life',
    );
    if (value == 0) {
      loadPosts();
    } else if (MemoriesController.to.companions.isEmpty) {
      MemoriesController.to.loadCompanions();
    }
  }
}

class ExplorePage extends StatelessWidget {
  const ExplorePage({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = ExploreController.to;
    return Scaffold(
      backgroundColor: context.vita.pageBg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            VitaTabHeader(title: 'explore.title'.tr),
            Obx(
              () => _ExploreSections(
                selected: controller.section.value,
                onChanged: controller.selectSection,
              ),
            ),
            Expanded(
              child: Obx(
                () => controller.section.value == 0
                    ? _MomentsFeed(controller: controller)
                    : const MemoriesPage(embedded: true),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ExploreSections extends StatelessWidget {
  const _ExploreSections({required this.selected, required this.onChanged});

  final int selected;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 45,
      color: context.vita.surface,
      child: Row(
        children: [
          _SectionButton(
            label: 'explore.moments'.tr,
            selected: selected == 0,
            onTap: () => onChanged(0),
          ),
          _SectionButton(
            label: 'explore.memories'.tr,
            selected: selected == 1,
            onTap: () => onChanged(1),
          ),
        ],
      ),
    );
  }
}

class _SectionButton extends StatelessWidget {
  const _SectionButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Expanded(
              child: Center(
                child: Text(
                  label,
                  style: TextStyle(
                    color: selected ? context.vita.text : context.vita.subText,
                    fontSize: 14,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
            ),
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: selected ? 24 : 0,
              height: 2,
              color: context.vita.green,
            ),
          ],
        ),
      ),
    );
  }
}

class _MomentsFeed extends StatelessWidget {
  const _MomentsFeed({required this.controller});

  final ExploreController controller;

  @override
  Widget build(BuildContext context) {
    if (controller.loading.value && controller.posts.isEmpty) {
      return ListView.builder(
        padding: const EdgeInsets.only(top: 8, bottom: 90),
        itemCount: 4,
        itemBuilder: (_, __) => const VitaSkeletonCard(withAvatar: true),
      );
    }
    if (controller.posts.isEmpty) {
      return RefreshIndicator(
        onRefresh: controller.loadPosts,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: 90),
          children: [
            SizedBox(
              height: MediaQuery.sizeOf(context).height * 0.58,
              child: VitaEmpty(
                icon: Icons.dynamic_feed_outlined,
                title: 'explore.empty'.tr,
                subtitle: 'explore.emptySub'.tr,
              ),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: controller.loadPosts,
      child: ListView.separated(
        padding: const EdgeInsets.only(top: 8, bottom: 90),
        itemCount: controller.posts.length,
        separatorBuilder: (_, __) =>
            Divider(height: 0.5, indent: 76, color: context.vita.divider),
        itemBuilder: (context, index) =>
            _MomentPost(post: controller.posts[index]),
      ),
    );
  }
}

class _MomentPost extends StatelessWidget {
  const _MomentPost({required this.post});

  final Map<String, dynamic> post;

  @override
  Widget build(BuildContext context) {
    final author = Map<String, dynamic>.from(post['author'] as Map? ?? {});
    final related = post['related_companion'] is Map
        ? Map<String, dynamic>.from(post['related_companion'] as Map)
        : null;
    final name = author['name'] as String? ?? '';
    final content = post['content'] as String? ?? '';
    final media = (post['media_urls'] as List? ?? const [])
        .whereType<String>()
        .where((url) => url.isNotEmpty)
        .toList();
    final published = DateTime.tryParse(post['published_at'] as String? ?? '');
    return Container(
      color: context.vita.surface,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          VitaAvatar(
            name: name,
            radius: 22,
            imageUrl: author['portrait_url'] as String?,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: TextStyle(
                    color: context.vita.green,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (related != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    'explore.with'.trParams({
                      'name': related['name'] as String? ?? '',
                    }),
                    style: TextStyle(fontSize: 12, color: context.vita.subText),
                  ),
                ],
                if (content.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    content,
                    style: TextStyle(
                      color: context.vita.text,
                      fontSize: 15,
                      height: 1.45,
                    ),
                  ),
                ],
                if (media.isNotEmpty) ...[
                  const SizedBox(height: 9),
                  _MomentMedia(urls: media),
                ],
                const SizedBox(height: 8),
                Text(
                  published == null ? '' : formatDate(published.toLocal()),
                  style: TextStyle(fontSize: 12, color: context.vita.subText),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MomentMedia extends StatelessWidget {
  const _MomentMedia({required this.urls});

  final List<String> urls;

  @override
  Widget build(BuildContext context) {
    final visible = urls.take(9).toList();
    final columns = visible.length == 1 ? 1 : (visible.length == 2 ? 2 : 3);
    final width = visible.length == 1 ? 220.0 : 252.0;
    return SizedBox(
      width: width,
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columns,
          crossAxisSpacing: 4,
          mainAxisSpacing: 4,
        ),
        itemCount: visible.length,
        itemBuilder: (context, index) => ClipRect(
          child: VitaMediaImage(
            url: visible[index],
            errorBuilder: (_, __, ___) => Container(
              color: context.vita.pageBg,
              child: Icon(
                Icons.image_not_supported_outlined,
                color: context.vita.subText,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
