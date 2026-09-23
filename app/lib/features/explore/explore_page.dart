import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/analytics_service.dart';
import '../../core/api_client.dart';
import '../../core/theme.dart';
import '../../shared/widgets.dart';
import '../../shared/media_image.dart';
import '../ai_pets/ai_pets_page.dart';
import '../stories/stories_page.dart';

class ExploreController extends GetxController {
  static ExploreController get to => Get.find();

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
}

/// Explore tab — a grouped menu (same pattern as the Me page): each tile
/// pushes a full second page instead of switching content in place.
class ExplorePage extends StatelessWidget {
  const ExplorePage({super.key});

  @override
  Widget build(BuildContext context) {
    final vita = context.vita;
    return Scaffold(
      backgroundColor: vita.pageBg,
      // Bottom is open so the list scrolls behind the floating glass tab bar.
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 90),
          children: [
            VitaTabHeader(title: 'explore.title'.tr, showDivider: false),
            const SizedBox(height: 10),
            VitaCard(
              radius: 0,
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: VitaListTile(
                customIcon: VitaMenuIcon(
                  icon: Icons.camera_alt_outlined,
                  color: vita.green,
                ),
                title: 'explore.moments'.tr,
                borderRadius: BorderRadius.zero,
                onTap: () => Get.to(
                  () => const MomentsPage(),
                  transition: Transition.cupertino,
                  duration: const Duration(milliseconds: 300),
                ),
              ),
            ),
            VitaCard(
              radius: 0,
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: VitaListTile(
                customIcon: const VitaMenuIcon(
                  icon: Icons.auto_stories_outlined,
                  color: Color(0xFF576B95),
                ),
                title: 'storyHub.title'.tr,
                borderRadius: BorderRadius.zero,
                onTap: () => Get.to(
                  () => const StoriesPage(),
                  transition: Transition.cupertino,
                  duration: const Duration(milliseconds: 300),
                ),
              ),
            ),
            VitaCard(
              radius: 0,
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: VitaListTile(
                customIcon: const VitaMenuIcon(
                  icon: Icons.pets_outlined,
                  color: Color(0xFFF29C38),
                ),
                title: 'aiPets.title'.tr,
                borderRadius: BorderRadius.zero,
                onTap: () => Get.to(
                  () => const AIPetsPage(),
                  transition: Transition.cupertino,
                  duration: const Duration(milliseconds: 300),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Moments second page — companions' public posts, pushed from the Explore
/// menu.
class MomentsPage extends StatelessWidget {
  const MomentsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = ExploreController.to;
    return Scaffold(
      backgroundColor: context.vita.pageBg,
      appBar: AppBar(title: Text('explore.moments'.tr)),
      body: SafeArea(
        bottom: false,
        child: _MomentsFeed(controller: controller),
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
                icon: Icons.photo_camera_back_outlined,
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
                Icons.broken_image_outlined,
                color: context.vita.subText,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
