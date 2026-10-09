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
  final postsLoadFailed = false.obs;
  final posts = <Map<String, dynamic>>[].obs;
  final storyChapter = RxnInt();
  final petName = RxnString();

  @override
  void onInit() {
    super.onInit();
    loadPosts();
    loadHighlights();
  }

  Future<void> loadHighlights() async {
    try {
      final data = await ApiClient.instance.get('/v1/stories/');
      final items = data is Map ? data['items'] : null;
      if (items is List) {
        final stories = items.whereType<Map>().toList();
        storyChapter.value = stories.isEmpty
            ? null
            : (stories.first['current_chapter_no'] as num?)?.toInt();
      }
    } catch (_) {
      // The entry remains available when the optional preview cannot load.
    }
    try {
      final data = await ApiClient.instance.get('/v1/ai-pets/breeds');
      final items = data is Map ? data['items'] : null;
      if (items is List) {
        final adopted = items.whereType<Map>().where(
            (breed) => '${breed['adopted_companion_id'] ?? ''}'.isNotEmpty);
        petName.value = adopted.isEmpty
            ? null
            : '${adopted.first['adopted_companion_name'] ?? adopted.first['name'] ?? ''}';
      }
    } catch (_) {
      // Keep the normal pet entry visible.
    }
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
        postsLoadFailed.value = false;
      } else {
        postsLoadFailed.value = true;
      }
    } catch (_) {
      postsLoadFailed.value = true;
    } finally {
      loading.value = false;
    }
  }
}

/// Places in the companion world, each opening an existing feature.
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
            VitaTabHeader(title: 'tab.discover'.tr, showDivider: false),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: Text('discover.subtitle'.tr,
                  style: TextStyle(color: vita.subText, fontSize: 13)),
            ),
            Obx(() => _PlaceCard(
                  icon: Icons.auto_stories_outlined,
                  title: 'storyHub.title'.tr,
                  subtitle: ExploreController.to.storyChapter.value == null
                      ? 'discover.stories'.tr
                      : 'discover.continueStory'.trParams({
                          'count': '${ExploreController.to.storyChapter.value}'
                        }),
                  onTap: () async {
                    await Get.to(() => const StoriesPage(),
                        transition: Transition.cupertino);
                    ExploreController.to.loadHighlights();
                  },
                )),
            Obx(() => _PlaceCard(
                  icon: Icons.pets_outlined,
                  title: 'aiPets.title'.tr,
                  subtitle:
                      ExploreController.to.petName.value?.isNotEmpty == true
                          ? 'discover.myPet'.trParams(
                              {'name': ExploreController.to.petName.value!})
                          : 'discover.pets'.tr,
                  onTap: () async {
                    await Get.to(() => const AIPetsPage(),
                        transition: Transition.cupertino);
                    ExploreController.to.loadHighlights();
                  },
                )),
            Obx(() {
              final posts = ExploreController.to.posts;
              final content = posts.isEmpty
                  ? ''
                  : 'discover.momentCount'
                      .trParams({'count': '${posts.length}'});
              return _PlaceCard(
                icon: Icons.camera_alt_outlined,
                title: 'explore.moments'.tr,
                subtitle: content.isEmpty ? 'discover.moments'.tr : content,
                onTap: () => Get.to(() => const MomentsPage(),
                    transition: Transition.cupertino),
              );
            }),
          ],
        ),
      ),
    );
  }
}

class _PlaceCard extends StatelessWidget {
  const _PlaceCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
        child: Material(
          borderRadius: BorderRadius.circular(18),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Ink(
              color: context.vita.surface,
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Row(children: [
                  Icon(icon, size: 30, color: context.vita.text),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title,
                            style: TextStyle(
                                color: context.vita.text,
                                fontSize: 17,
                                fontWeight: FontWeight.w700)),
                        const SizedBox(height: 5),
                        Text(subtitle,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: context.vita.subText, fontSize: 13)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(Icons.chevron_right, color: context.vita.subText),
                ]),
              ),
            ),
          ),
        ),
      );
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
      appBar: AppBar(
          leading: const VitaBackButton(), title: Text('explore.moments'.tr)),
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
  Widget build(BuildContext context) => Obx(() => _buildFeed(context));

  Widget _buildFeed(BuildContext context) {
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
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  VitaEmpty(
                    icon: controller.postsLoadFailed.value
                        ? Icons.wifi_off_outlined
                        : Icons.photo_camera_back_outlined,
                    title: controller.postsLoadFailed.value
                        ? 'common.loadFailed'.tr
                        : 'explore.empty'.tr,
                    subtitle: controller.postsLoadFailed.value
                        ? 'common.pullToRetry'.tr
                        : 'explore.emptySub'.tr,
                  ),
                  if (controller.postsLoadFailed.value)
                    TextButton(
                      onPressed: controller.loadPosts,
                      child: Text('common.retry'.tr),
                    ),
                ],
              ),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: controller.loadPosts,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 90),
        itemCount: controller.posts.length,
        separatorBuilder: (_, __) => const SizedBox(height: 18),
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
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF25213C), Color(0xFF181D31), Color(0xFF142830)],
        ),
        borderRadius: BorderRadius.circular(26),
        border:
            Border.all(color: const Color(0xFF9A91CB).withValues(alpha: 0.32)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned(
            right: -28,
            top: -65,
            child: Container(
              width: 180,
              height: 180,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                    color: Colors.white.withValues(alpha: 0.07), width: 24),
              ),
            ),
          ),
          const Positioned(
              right: 32,
              top: 35,
              child:
                  Icon(Icons.auto_awesome, size: 13, color: Color(0xFFB9ADEE))),
          const Positioned(
              right: 84,
              top: 82,
              child: Icon(Icons.circle, size: 4, color: Color(0xFF8ACDD0))),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(2),
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                            colors: [Color(0xFFB9ADEE), Color(0xFF77C7C3)]),
                      ),
                      child: VitaAvatar(
                        name: name,
                        radius: 20,
                        imageUrl: author['portrait_url'] as String?,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                        child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w700)),
                        if (related != null) ...[
                          const SizedBox(height: 3),
                          Text(
                              'explore.with'.trParams({
                                'name': related['name'] as String? ?? '',
                              }),
                              style: const TextStyle(
                                  fontSize: 12, color: Color(0xFFC2BCD9))),
                        ],
                      ],
                    )),
                  ],
                ),
                if (content.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  Text(
                    content,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      height: 1.55,
                    ),
                  ),
                ],
                if (media.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  _MomentMedia(urls: media),
                ],
                const SizedBox(height: 18),
                Container(
                    height: 1, color: Colors.white.withValues(alpha: 0.10)),
                const SizedBox(height: 12),
                Text(
                  published == null ? '' : formatDate(published.toLocal()),
                  style:
                      const TextStyle(fontSize: 12, color: Color(0xFFB3BED2)),
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
    return SizedBox(
      width: double.infinity,
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columns,
          crossAxisSpacing: 6,
          mainAxisSpacing: 6,
          childAspectRatio: visible.length == 1 ? 1.5 : 1,
        ),
        itemCount: visible.length,
        itemBuilder: (context, index) => ClipRRect(
          borderRadius: BorderRadius.circular(12),
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
