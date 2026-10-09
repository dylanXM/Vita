import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';

import '../../core/analytics_service.dart';
import '../../core/api_client.dart';
import '../../core/theme.dart';
import '../../shared/widgets.dart';
import '../../shared/media_image.dart';
import '../ai_pets/ai_pets_page.dart';
import '../stories/stories_page.dart';

List<Map<String, dynamic>> _previewMoments() {
  final now = DateTime.now();
  String published(Duration ago) => now.subtract(ago).toUtc().toIso8601String();
  return [
    {
      'id': 'preview-mia',
      'post_type': 'text',
      'content': '下班路过那家小咖啡馆，窗边的位置还空着。突然想起上次我们聊到很晚，今天的晚霞也刚刚好。',
      'media_urls': <String>[],
      'published_at': published(const Duration(minutes: 18)),
      'author': {
        'name': 'Mia',
        'portrait_url': 'asset://assets/companions/mia.png',
      },
      'is_preview': true,
    },
    {
      'id': 'preview-nora',
      'post_type': 'image',
      'content': '今天的心情，适合留一张照片。',
      'media_urls': ['asset://assets/companions/nora.png'],
      'published_at': published(const Duration(hours: 2)),
      'author': {
        'name': 'Nora',
        'portrait_url': 'asset://assets/companions/nora.png',
      },
      'is_preview': true,
    },
    {
      'id': 'preview-kai',
      'post_type': 'text',
      'content': '我们约好下次一起去看海。计划还没定下来，但已经开始期待了。',
      'media_urls': <String>[],
      'published_at': published(const Duration(days: 1, hours: 3)),
      'author': {
        'name': 'Kai',
        'portrait_url': 'asset://assets/companions/kai.png',
      },
      'related_companion': {'name': 'Mia'},
      'is_preview': true,
    },
    {
      'id': 'preview-leo',
      'post_type': 'text',
      'content':
          '整理旧照片时发现一张很久以前的车票。那天没有发生什么惊天动地的事，只是在回程的路上，忽然觉得有人愿意听我说这些琐碎的小事，是件很幸运的事。后来我把车票夹进了书里，想等某天再翻出来看看。',
      'media_urls': <String>[],
      'published_at': published(const Duration(days: 2)),
      'author': {'name': 'Leo', 'portrait_url': ''},
      'is_preview': true,
    },
  ];
}

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
        final fetched = list
            .whereType<Map<String, dynamic>>()
            .map((item) => Map<String, dynamic>.from(item));
        posts.assignAll(
            kDebugMode ? [..._previewMoments(), ...fetched] : fetched);
        postsLoadFailed.value = false;
      } else {
        postsLoadFailed.value = true;
        if (kDebugMode) posts.assignAll(_previewMoments());
      }
    } catch (_) {
      postsLoadFailed.value = true;
      if (kDebugMode) posts.assignAll(_previewMoments());
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
class MomentsPage extends StatefulWidget {
  const MomentsPage({super.key});

  @override
  State<MomentsPage> createState() => _MomentsPageState();
}

class _MomentsPageState extends State<MomentsPage> {
  bool _showTimeline = false;

  @override
  Widget build(BuildContext context) {
    final controller = ExploreController.to;
    return Scaffold(
      backgroundColor: context.vita.pageBg,
      appBar: AppBar(
        leading: const VitaBackButton(),
        title: Text('explore.moments'.tr),
        actions: [
          IconButton(
            tooltip: _showTimeline
                ? 'explore.universeView'.tr
                : 'explore.timelineView'.tr,
            icon: Icon(_showTimeline
                ? Icons.blur_on_rounded
                : Icons.view_timeline_outlined),
            onPressed: () => setState(() => _showTimeline = !_showTimeline),
          ),
          IconButton(
            tooltip: 'common.retry'.tr,
            icon: const Icon(Icons.refresh_rounded),
            onPressed: controller.loadPosts,
          ),
        ],
      ),
      body: SafeArea(
        bottom: false,
        child: _showTimeline
            ? _MomentsFeed(controller: controller)
            : _MomentsUniverse(controller: controller),
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
          padding: const EdgeInsets.fromLTRB(24, 70, 24, 90),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: context.vita.greenTint,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  controller.postsLoadFailed.value
                      ? Icons.wifi_off_outlined
                      : Icons.auto_awesome_outlined,
                  color: context.vita.green,
                  size: 30,
                ),
              ),
            ),
            const SizedBox(height: 22),
            Text(
              controller.postsLoadFailed.value
                  ? 'common.loadFailed'.tr
                  : 'explore.empty'.tr,
              style: TextStyle(
                  color: context.vita.text,
                  fontSize: 20,
                  fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              controller.postsLoadFailed.value
                  ? 'common.pullToRetry'.tr
                  : 'explore.emptySub'.tr,
              style: TextStyle(
                  color: context.vita.subText, fontSize: 14, height: 1.5),
            ),
            if (controller.postsLoadFailed.value) ...[
              const SizedBox(height: 14),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: controller.loadPosts,
                  icon: const Icon(Icons.refresh_rounded),
                  label: Text('common.retry'.tr),
                ),
              ),
            ],
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: controller.loadPosts,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 90),
        itemCount: controller.posts.length + 1,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          if (index == 0) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                      color: context.vita.green, shape: BoxShape.circle),
                ),
                const SizedBox(width: 9),
                Text(
                  'discover.momentCount'
                      .trParams({'count': '${controller.posts.length}'}),
                  style: TextStyle(
                      color: context.vita.subText,
                      fontSize: 12,
                      fontWeight: FontWeight.w600),
                ),
              ]),
            );
          }
          return _MomentPost(post: controller.posts[index - 1]);
        },
      ),
    );
  }
}

List<String> _momentMediaUrls(Map<String, dynamic> post) =>
    (post['media_urls'] as List? ?? const [])
        .whereType<String>()
        .where((url) => url.isNotEmpty)
        .toList();

class _PreviewBadge extends StatelessWidget {
  const _PreviewBadge();

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: context.vita.greenTint,
          borderRadius: BorderRadius.circular(5),
        ),
        child: Text('explore.preview'.tr,
            style: TextStyle(color: context.vita.green, fontSize: 10)),
      );
}

class _MomentPost extends StatelessWidget {
  const _MomentPost({required this.post});

  final Map<String, dynamic> post;

  @override
  Widget build(BuildContext context) {
    final vita = context.vita;
    final author = Map<String, dynamic>.from(post['author'] as Map? ?? {});
    final related = post['related_companion'] is Map
        ? Map<String, dynamic>.from(post['related_companion'] as Map)
        : null;
    final name = author['name'] as String? ?? '';
    final content = (post['content'] as String? ?? '').trim();
    final media = _momentMediaUrls(post);
    final published = DateTime.tryParse(post['published_at'] as String? ?? '');
    return Material(
      color: vita.surface,
      borderRadius: BorderRadius.circular(8),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Get.to(
          () => _MomentDetailPage(post: post),
          transition: Transition.cupertino,
        ),
        child: Container(
          height: 190,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            border: Border.all(color: vita.divider.withValues(alpha: .75)),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(children: [
            Row(children: [
              VitaAvatar(
                name: name,
                radius: 21,
                imageUrl: author['portrait_url'] as String?,
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Flexible(
                        child: Text(name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: vita.text,
                                fontSize: 15,
                                fontWeight: FontWeight.w700)),
                      ),
                      if (post['is_preview'] == true) ...[
                        const SizedBox(width: 7),
                        const _PreviewBadge(),
                      ],
                    ]),
                    if (related != null)
                      Text(
                        'explore.with'.trParams({
                          'name': related['name'] as String? ?? '',
                        }),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: vita.subText, fontSize: 11),
                      ),
                  ],
                ),
              ),
              Icon(Icons.north_east_rounded, color: vita.green, size: 17),
            ]),
            const SizedBox(height: 13),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 3,
                    height: 38,
                    decoration: BoxDecoration(
                      color: vita.green,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Text(
                      content.isEmpty ? 'chat.photoMessage'.tr : content,
                      maxLines: media.isEmpty ? 4 : 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: vita.text,
                        fontSize: media.isEmpty ? 16 : 14,
                        fontWeight:
                            media.isEmpty ? FontWeight.w500 : FontWeight.w400,
                        height: 1.4,
                      ),
                    ),
                  ),
                  if (media.isNotEmpty) ...[
                    const SizedBox(width: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: SizedBox(
                        width: 70,
                        height: 76,
                        child: VitaMediaImage(
                          url: media.first,
                          errorBuilder: (_, __, ___) => Container(
                            color: vita.greenTint,
                            child:
                                Icon(Icons.image_outlined, color: vita.green),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Row(children: [
              Icon(Icons.auto_awesome_rounded, color: vita.green, size: 13),
              const SizedBox(width: 6),
              Text(
                published == null ? '' : formatDate(published.toLocal()),
                style: TextStyle(color: vita.subText, fontSize: 11),
              ),
              const Spacer(),
              if (media.length > 1)
                Text(
                  '+${media.length - 1}',
                  style: TextStyle(color: vita.subText, fontSize: 11),
                ),
            ]),
          ]),
        ),
      ),
    );
  }
}

class _MomentDetailPage extends StatelessWidget {
  const _MomentDetailPage({required this.post});

  final Map<String, dynamic> post;

  @override
  Widget build(BuildContext context) {
    final vita = context.vita;
    final author = Map<String, dynamic>.from(post['author'] as Map? ?? {});
    final related = post['related_companion'] is Map
        ? Map<String, dynamic>.from(post['related_companion'] as Map)
        : null;
    final name = author['name'] as String? ?? '';
    final content = (post['content'] as String? ?? '').trim();
    final media = _momentMediaUrls(post);
    final published = DateTime.tryParse(post['published_at'] as String? ?? '');
    return Scaffold(
      backgroundColor: vita.pageBg,
      appBar: AppBar(
        leading: const VitaBackButton(),
        title: Text('explore.moments'.tr),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
        children: [
          Row(children: [
            VitaAvatar(
              name: name,
              radius: 28,
              imageUrl: author['portrait_url'] as String?,
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Flexible(
                      child: Text(name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: vita.text,
                              fontSize: 18,
                              fontWeight: FontWeight.w700)),
                    ),
                    if (post['is_preview'] == true) ...[
                      const SizedBox(width: 7),
                      const _PreviewBadge(),
                    ],
                  ]),
                  if (related != null)
                    Text(
                      'explore.with'.trParams({
                        'name': related['name'] as String? ?? '',
                      }),
                      style: TextStyle(color: vita.subText, fontSize: 12),
                    ),
                ],
              ),
            ),
          ]),
          const SizedBox(height: 22),
          if (content.isNotEmpty) ...[
            Text(content,
                style: TextStyle(color: vita.text, fontSize: 18, height: 1.6)),
            const SizedBox(height: 20),
          ],
          if (media.isNotEmpty) ...[
            _MomentMedia(urls: media),
            const SizedBox(height: 20),
          ],
          Divider(color: vita.divider),
          const SizedBox(height: 8),
          Text(
            published == null ? '' : formatDate(published.toLocal()),
            style: TextStyle(color: vita.subText, fontSize: 12),
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
    final columns = urls.length == 1 ? 1 : (urls.length == 2 ? 2 : 3);
    return SizedBox(
      width: double.infinity,
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columns,
          crossAxisSpacing: 6,
          mainAxisSpacing: 6,
          childAspectRatio: urls.length == 1 ? 1.5 : 1,
        ),
        itemCount: urls.length,
        itemBuilder: (context, index) => ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: VitaMediaImage(
            url: urls[index],
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
