import 'dart:math' as math;

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
        final fetched = list
            .whereType<Map<String, dynamic>>()
            .map((item) => Map<String, dynamic>.from(item));
        posts.assignAll(fetched);
        postsLoadFailed.value = false;
      } else {
        postsLoadFailed.value = true;
        posts.removeWhere((post) => post['is_preview'] == true);
      }
    } catch (_) {
      postsLoadFailed.value = true;
      posts.removeWhere((post) => post['is_preview'] == true);
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
            Obx(() {
              final posts = ExploreController.to.posts;
              if (posts.isEmpty) return const SizedBox.shrink();
              return _FeaturedMoment(
                post: posts.first,
                onTap: () {
                  AnalyticsService.to
                      .track('discover_moment_opened', category: 'life');
                  Get.to(() => const MomentsPage(),
                      transition: Transition.cupertino);
                },
              );
            }),
            Obx(() => _PlaceCard(
                  icon: Icons.auto_stories_outlined,
                  title: 'storyHub.title'.tr,
                  subtitle: ExploreController.to.storyChapter.value == null
                      ? 'discover.stories'.tr
                      : 'discover.continueStory'.trParams({
                          'count': '${ExploreController.to.storyChapter.value}'
                        }),
                  onTap: () async {
                    AnalyticsService.to
                        .track('discover_story_opened', category: 'life');
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
                    AnalyticsService.to
                        .track('discover_pet_opened', category: 'life');
                    await Get.to(() => const AIPetsPage(),
                        transition: Transition.cupertino);
                    ExploreController.to.loadHighlights();
                  },
                )),
            Obx(() {
              final posts = ExploreController.to.posts;
              if (posts.isNotEmpty) return const SizedBox.shrink();
              return _PlaceCard(
                icon: Icons.camera_alt_outlined,
                title: 'explore.moments'.tr,
                subtitle: 'discover.moments'.tr,
                onTap: () {
                  AnalyticsService.to
                      .track('discover_moment_opened', category: 'life');
                  Get.to(() => const MomentsPage(),
                      transition: Transition.cupertino);
                },
              );
            }),
          ],
        ),
      ),
    );
  }
}

/// A real recent moment gives Discover a reason to open today.
class _FeaturedMoment extends StatelessWidget {
  const _FeaturedMoment({required this.post, required this.onTap});

  final Map<String, dynamic> post;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final vita = context.vita;
    final author = Map<String, dynamic>.from(post['author'] as Map? ?? {});
    final media = _momentMediaUrls(post);
    final content = '${post['content'] ?? ''}'.trim();
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
      child: Material(
        color: vita.surface,
        borderRadius: BorderRadius.circular(22),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            height: 176,
            child: Stack(fit: StackFit.expand, children: [
              if (media.isNotEmpty)
                VitaMediaImage(url: media.first, fit: BoxFit.cover),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: media.isEmpty
                        ? [vita.surface, vita.surface]
                        : const [Color(0x33000000), Color(0xDD000000)],
                  ),
                ),
              ),
              Positioned(
                left: 18,
                right: 18,
                top: 16,
                child: Row(children: [
                  Icon(Icons.blur_on_rounded,
                      size: 19,
                      color: media.isEmpty ? vita.green : Colors.white),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text('explore.moments'.tr,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: media.isEmpty ? vita.text : Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w700)),
                  ),
                  Icon(Icons.arrow_outward_rounded,
                      size: 18,
                      color: media.isEmpty ? vita.subText : Colors.white),
                ]),
              ),
              Positioned(
                left: 18,
                right: 18,
                bottom: 18,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('${author['name'] ?? ''}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color:
                                media.isEmpty ? vita.subText : Colors.white70,
                            fontSize: 12)),
                    const SizedBox(height: 5),
                    Text(content.isEmpty ? 'discover.moments'.tr : content,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: media.isEmpty ? vita.text : Colors.white,
                            fontSize: 16,
                            height: 1.3,
                            fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ]),
          ),
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
              child: SizedBox(
                height: 104,
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Row(children: [
                    Icon(icon, size: 30, color: context.vita.text),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  color: context.vita.text,
                                  fontSize: 17,
                                  fontWeight: FontWeight.w700)),
                          const SizedBox(height: 5),
                          Flexible(
                              child: Text(subtitle,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      color: context.vita.subText,
                                      fontSize: 13))),
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
      body: SizedBox.expand(
        child: Stack(
          children: [
            Positioned.fill(
              child: _showTimeline
                  ? Padding(
                      padding: EdgeInsets.only(
                          top: MediaQuery.paddingOf(context).top + 56),
                      child: _MomentsFeed(controller: controller),
                    )
                  : _MomentsUniverse(controller: controller),
            ),
            SafeArea(
              bottom: false,
              child: SizedBox(
                height: 56,
                child: Row(
                  children: [
                    IconButton(
                      tooltip:
                          MaterialLocalizations.of(context).backButtonTooltip,
                      icon: Icon(Icons.arrow_back_ios_new,
                          size: 20,
                          color:
                              _showTimeline ? context.vita.text : Colors.white),
                      onPressed: () => Get.back(),
                    ),
                    Expanded(
                      child: Text(
                        'explore.moments'.tr,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color:
                              _showTimeline ? context.vita.text : Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: _showTimeline
                          ? 'explore.universeView'.tr
                          : 'explore.timelineView'.tr,
                      icon: Icon(
                          _showTimeline
                              ? Icons.blur_on_rounded
                              : Icons.view_timeline_outlined,
                          color:
                              _showTimeline ? context.vita.text : Colors.white),
                      onPressed: () =>
                          setState(() => _showTimeline = !_showTimeline),
                    ),
                    IconButton(
                      tooltip: 'common.retry'.tr,
                      icon: Icon(Icons.refresh_rounded,
                          color:
                              _showTimeline ? context.vita.text : Colors.white),
                      onPressed: controller.loadPosts,
                    ),
                    const SizedBox(width: 8),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _UniverseSlice {
  const _UniverseSlice(this.posts, this.date);

  final List<Map<String, dynamic>> posts;
  final DateTime? date;
}

List<_UniverseSlice> _universeSlices(List<Map<String, dynamic>> posts) {
  final sorted = List<Map<String, dynamic>>.from(posts)
    ..sort((a, b) {
      final aTime = DateTime.tryParse('${a['published_at'] ?? ''}');
      final bTime = DateTime.tryParse('${b['published_at'] ?? ''}');
      return (bTime ?? DateTime(1970)).compareTo(aTime ?? DateTime(1970));
    });
  return [
    for (var start = 0; start < sorted.length; start += 4)
      _UniverseSlice(
        sorted.sublist(start, math.min(start + 4, sorted.length)),
        DateTime.tryParse('${sorted[start]['published_at'] ?? ''}')?.toLocal(),
      ),
  ];
}

class _MomentsUniverse extends StatefulWidget {
  const _MomentsUniverse({required this.controller});

  final ExploreController controller;

  @override
  State<_MomentsUniverse> createState() => _MomentsUniverseState();
}

class _MomentsUniverseState extends State<_MomentsUniverse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _breathing = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 3),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _breathing.stop();
      _breathing.value = .5;
    } else if (!_breathing.isAnimating) {
      _breathing.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _breathing.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Obx(() {
        final posts = widget.controller.posts.toList();
        if (posts.isEmpty) {
          return Padding(
            padding:
                EdgeInsets.only(top: MediaQuery.paddingOf(context).top + 56),
            child: _MomentsFeed(controller: widget.controller),
          );
        }
        final slices = _universeSlices(posts);
        return PageView.builder(
          scrollDirection: Axis.vertical,
          itemCount: slices.length,
          itemBuilder: (context, index) => _UniversePage(
            slice: slices[index],
            page: index,
            pageCount: slices.length,
            breathing: _breathing,
          ),
        );
      });
}

const _signalPositions = <List<Offset>>[
  [Offset(.5, .48)],
  [Offset(.30, .38), Offset(.70, .64)],
  [Offset(.28, .32), Offset(.72, .40), Offset(.50, .72)],
  [
    Offset(.28, .29),
    Offset(.72, .29),
    Offset(.28, .67),
    Offset(.72, .67),
  ],
];

class _UniversePage extends StatelessWidget {
  const _UniversePage({
    required this.slice,
    required this.page,
    required this.pageCount,
    required this.breathing,
  });

  final _UniverseSlice slice;
  final int page;
  final int pageCount;
  final Animation<double> breathing;

  @override
  Widget build(BuildContext context) {
    final hour = slice.date?.hour ?? 12;
    final night = hour < 6 || hour >= 19;
    final colors = night
        ? const [Color(0xFF0D1021), Color(0xFF26203C)]
        : const [Color(0xFF171628), Color(0xFF46364D)];
    final positions = _signalPositions[slice.posts.length - 1];
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: colors,
        ),
      ),
      child: LayoutBuilder(builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        final centers = positions
            .map((point) => Offset(
                  size.width <= 136
                      ? size.width / 2
                      : (size.width * point.dx).clamp(68.0, size.width - 68),
                  size.height <= 210
                      ? size.height / 2
                      : (size.height * point.dy)
                          .clamp(105.0, size.height - 105),
                ))
            .toList();
        return AnimatedBuilder(
          animation: breathing,
          builder: (context, _) => Stack(children: [
            Positioned.fill(
              child: CustomPaint(
                painter: _SignalSkyPainter(
                  posts: slice.posts,
                  centers: centers,
                  accent: context.vita.green,
                  phase: breathing.value,
                ),
              ),
            ),
            Positioned(
              top: MediaQuery.paddingOf(context).top + 70,
              left: 24,
              right: 24,
              child: Text(
                slice.date == null
                    ? 'explore.moments'.tr
                    : formatDateSeparator(slice.date!),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            for (var index = 0; index < slice.posts.length; index++)
              Positioned(
                left: centers[index].dx - 64,
                top: centers[index].dy - 76,
                width: 128,
                height: 152,
                child: _SignalNode(
                  post: slice.posts[index],
                  phase: breathing.value,
                  onTap: () => _showSignal(context, slice.posts[index]),
                ),
              ),
            if (slice.posts.length == 1 &&
                '${slice.posts.first['content'] ?? ''}'.trim().isNotEmpty)
              Positioned(
                left: 32,
                right: 32,
                bottom: 76,
                child: Text(
                  '“${slice.posts.first['content']}”',
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 15,
                    height: 1.5,
                  ),
                ),
              ),
            if (page + 1 < pageCount)
              const Positioned(
                left: 0,
                right: 0,
                bottom: 18,
                child: Icon(Icons.keyboard_arrow_down_rounded,
                    color: Colors.white54, size: 28),
              ),
          ]),
        );
      }),
    );
  }
}

class _SignalSkyPainter extends CustomPainter {
  const _SignalSkyPainter({
    required this.posts,
    required this.centers,
    required this.accent,
    required this.phase,
  });

  final List<Map<String, dynamic>> posts;
  final List<Offset> centers;
  final Color accent;
  final double phase;

  @override
  void paint(Canvas canvas, Size size) {
    final random = math.Random(42);
    for (var i = 0; i < 38; i++) {
      final point = Offset(
          random.nextDouble() * size.width, random.nextDouble() * size.height);
      canvas.drawCircle(
        point,
        i % 7 == 0 ? 1.5 : .75,
        Paint()..color = Colors.white.withValues(alpha: .13 + phase * .13),
      );
    }
    final orbitPaint = Paint()
      ..color = Colors.white.withValues(alpha: .065)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(size.width / 2, size.height / 2),
        width: size.width * .86,
        height: size.height * .69,
      ),
      orbitPaint,
    );
    for (var i = 0; i < posts.length; i++) {
      final related = posts[i]['related_companion'];
      if (related is! Map) continue;
      final relatedId = '${related['id'] ?? ''}';
      final relatedName = '${related['name'] ?? ''}';
      final target = posts.indexWhere((candidate) {
        final author = candidate['author'];
        if (author is! Map) return false;
        return relatedId.isNotEmpty && author['id'] == relatedId ||
            relatedName.isNotEmpty && author['name'] == relatedName;
      });
      if (target < 0 || target == i) continue;
      final path = Path()
        ..moveTo(centers[i].dx, centers[i].dy)
        ..quadraticBezierTo(size.width / 2, size.height / 2 - 36,
            centers[target].dx, centers[target].dy);
      canvas.drawPath(
        path,
        Paint()
          ..color = accent.withValues(alpha: .20 + phase * .22)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SignalSkyPainter oldDelegate) =>
      oldDelegate.phase != phase ||
      oldDelegate.posts != posts ||
      oldDelegate.centers != centers;
}

class _SignalNode extends StatelessWidget {
  const _SignalNode({
    required this.post,
    required this.phase,
    required this.onTap,
  });

  final Map<String, dynamic> post;
  final double phase;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final author = Map<String, dynamic>.from(post['author'] as Map? ?? {});
    final name = '${author['name'] ?? ''}';
    final content = '${post['content'] ?? ''}'.trim();
    final media = _momentMediaUrls(post);
    final related = post['related_companion'];
    return Semantics(
      button: true,
      label: '$name: $content',
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Column(children: [
          SizedBox(
            width: 88,
            height: 88,
            child: Stack(alignment: Alignment.center, children: [
              Transform.scale(
                scale: 1 + phase * .08,
                child: Container(
                  width: 82,
                  height: 82,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: context.vita.green
                          .withValues(alpha: .27 + phase * .28),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: context.vita.green.withValues(alpha: .13),
                        blurRadius: 22,
                      ),
                    ],
                  ),
                ),
              ),
              VitaAvatar(
                name: name,
                radius: 29,
                imageUrl: author['portrait_url'] as String?,
              ),
              if (media.isNotEmpty)
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: ClipOval(
                    child: SizedBox(
                      width: 27,
                      height: 27,
                      child: VitaMediaImage(
                        url: media.first,
                        errorBuilder: (_, __, ___) =>
                            const Icon(Icons.image_outlined, size: 17),
                      ),
                    ),
                  ),
                ),
            ]),
          ),
          const SizedBox(height: 4),
          Text(name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text(content.isEmpty ? 'chat.photoMessage'.tr : content,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white70, fontSize: 11)),
          if (related is Map && '${related['name'] ?? ''}'.isNotEmpty)
            Text(
              'explore.with'.trParams({'name': '${related['name']}'}),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white54, fontSize: 10),
            ),
        ]),
      ),
    );
  }
}

Future<void> _showSignal(
    BuildContext context, Map<String, dynamic> post) async {
  await showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'common.cancel'.tr,
    barrierColor: Colors.black.withValues(alpha: .75),
    transitionDuration: const Duration(milliseconds: 260),
    pageBuilder: (dialogContext, _, __) => _SignalFocusDialog(post: post),
    transitionBuilder: (context, animation, _, child) => FadeTransition(
      opacity: animation,
      child: ScaleTransition(
        scale: Tween<double>(begin: .9, end: 1).animate(
          CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
        ),
        child: child,
      ),
    ),
  );
}

class _SignalFocusDialog extends StatelessWidget {
  const _SignalFocusDialog({required this.post});

  final Map<String, dynamic> post;

  @override
  Widget build(BuildContext context) {
    final author = Map<String, dynamic>.from(post['author'] as Map? ?? {});
    final related = post['related_companion'];
    final media = _momentMediaUrls(post);
    final published = DateTime.tryParse('${post['published_at'] ?? ''}');
    return SafeArea(
      child: Center(
        child: Container(
          width: MediaQuery.sizeOf(context).width - 32,
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * .78,
          ),
          decoration: BoxDecoration(
            color: context.vita.surface,
            borderRadius: BorderRadius.circular(24),
          ),
          clipBehavior: Clip.antiAlias,
          child: Material(
            color: Colors.transparent,
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.all(22),
              children: [
                Row(children: [
                  VitaAvatar(
                    name: '${author['name'] ?? ''}',
                    radius: 25,
                    imageUrl: author['portrait_url'] as String?,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${author['name'] ?? ''}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: context.vita.text,
                                fontSize: 17,
                                fontWeight: FontWeight.w700)),
                        if (related is Map &&
                            '${related['name'] ?? ''}'.isNotEmpty)
                          Text(
                            'explore.with'
                                .trParams({'name': '${related['name']}'}),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: context.vita.subText, fontSize: 12),
                          ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'common.cancel'.tr,
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ]),
                const SizedBox(height: 20),
                if ('${post['content'] ?? ''}'.trim().isNotEmpty) ...[
                  Text('${post['content']}',
                      style: TextStyle(
                          color: context.vita.text, fontSize: 17, height: 1.6)),
                  const SizedBox(height: 18),
                ],
                if (media.isNotEmpty) ...[
                  _MomentMedia(urls: media),
                  const SizedBox(height: 18),
                ],
                if (published != null)
                  Text(formatDate(published.toLocal()),
                      style:
                          TextStyle(color: context.vita.subText, fontSize: 12)),
              ],
            ),
          ),
        ),
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
