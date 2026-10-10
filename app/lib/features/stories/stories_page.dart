import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart' hide Response;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/notice.dart';
import '../../core/api_client.dart';
import '../../core/theme.dart';
import '../../shared/media_image.dart';
import '../../shared/widgets.dart';
import '../auth/auth_controller.dart';

String _requestKey() =>
    '${DateTime.now().microsecondsSinceEpoch}-${Random().nextInt(1 << 32)}';
Map<String, dynamic> _map(dynamic value) =>
    value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};
List<Map<String, dynamic>> _maps(dynamic value) => value is List
    ? value.whereType<Map>().map((x) => Map<String, dynamic>.from(x)).toList()
    : <Map<String, dynamic>>[];

class StoriesController extends GetxController {
  final loading = false.obs;
  final catalog = <String, dynamic>{}.obs;
  final stories = <Map<String, dynamic>>[].obs;
  final companions = <Map<String, dynamic>>[].obs;

  @override
  void onInit() {
    super.onInit();
    load();
  }

  Future<void> load() async {
    loading.value = true;
    try {
      final values = await Future.wait([
        ApiClient.instance.get('/v1/stories/catalog'),
        ApiClient.instance.get('/v1/stories/'),
        ApiClient.instance.get('/v1/companions'),
      ]);
      catalog.assignAll(_map(values[0]));
      stories.assignAll(_maps(_map(values[1])['items']));
      companions.assignAll(_maps(values[2])
          .where((item) => item['creation_source'] != 'ai_pet'));
    } catch (error) {
      _showError(error);
    } finally {
      loading.value = false;
    }
  }

  Future<Map<String, dynamic>?> start(
      Map<String, dynamic> background, Map<String, dynamic>? companion) async {
    if (loading.value) return null;
    loading.value = true;
    try {
      final data = <String, dynamic>{
        'background_id': background['id'],
        'idempotency_key': _requestKey(),
      };
      if (companion != null) data['companion_id'] = companion['id'];
      final result = await ApiClient.instance.post('/v1/stories/', data: data);
      await load();
      return _map(result);
    } catch (error) {
      _showError(error);
      return null;
    } finally {
      loading.value = false;
    }
  }
}

void _showError(Object error) {
  final message = error is ApiException ? error.message : error.toString();
  VitaNotice.error('storyHub.title'.tr, message);
}

class StoriesPage extends StatefulWidget {
  const StoriesPage({super.key, this.controller});

  final StoriesController? controller;

  @override
  State<StoriesPage> createState() => _StoriesPageState();
}

class _StoriesPageState extends State<StoriesPage> {
  @override
  Widget build(BuildContext context) {
    final StoriesController activeController =
        widget.controller ?? Get.put<StoriesController>(StoriesController());
    return Scaffold(
      backgroundColor: context.vita.pageBg,
      appBar: AppBar(
        leading: const VitaBackButton(),
        title: Text('storyHub.title'.tr),
        actions: [
          Obx(() {
            final hasActive = activeController.stories
                .any((story) => story['status'] == 'active');
            if (hasActive) {
              return IconButton(
                tooltip: 'storyHub.create'.tr,
                onPressed: () => _chooseNewScene(context, activeController),
                icon: const Icon(Icons.add_rounded),
              );
            }
            if (activeController.catalog['subscribed'] != true) {
              return const SizedBox.shrink();
            }
            final remaining = activeController
                    .catalog['custom_backgrounds_remaining'] as int? ??
                0;
            return TextButton.icon(
              onPressed: remaining > 0
                  ? () => Get.to(() =>
                      CustomStoryBackgroundPage(controller: activeController))
                  : null,
              icon: const Icon(Icons.add, size: 18),
              label: Text('storyHub.custom'.tr),
            );
          }),
          const SizedBox(width: 8),
        ],
      ),
      body: Obx(() {
        final backgrounds = _maps(activeController.catalog['backgrounds']);
        final activeStories = activeController.stories
            .where((story) => story['status'] == 'active')
            .toList();
        final subscribed = activeController.catalog['subscribed'] == true;
        final remaining =
            activeController.catalog['custom_backgrounds_remaining'] as int? ??
                0;
        if (activeController.loading.value &&
            backgrounds.isEmpty &&
            activeController.stories.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }
        return RefreshIndicator(
          onRefresh: activeController.load,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.only(top: 8, bottom: 32),
            children: activeStories.isNotEmpty
                ? [
                    _SectionHeader(title: 'storyHub.productions'.tr),
                    for (final story in activeStories)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                        child: _StoryBookTile(
                          story: story,
                          onTap: () async {
                            await Get.to(
                                () =>
                                    StoryDetailPage(storyId: '${story['id']}'),
                                transition: Transition.cupertino);
                            await activeController.load();
                          },
                        ),
                      ),
                  ]
                : [
                    _SectionHeader(title: 'storyHub.scenes'.tr),
                    if (subscribed)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                        child: Text(
                          'storyHub.quota'
                              .trParams({'remaining': '$remaining'}),
                          style: TextStyle(
                              color: context.vita.subText, fontSize: 12),
                        ),
                      ),
                    if (backgrounds.isEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        child: Text('storyHub.emptySub'.tr,
                            style: TextStyle(
                                color: context.vita.subText, fontSize: 13)),
                      ),
                    for (final background in backgrounds)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                        child: _BackgroundTile(
                          background: background,
                          onTap: () => Get.to(
                            () => _StoryCastPage(
                              controller: activeController,
                              background: background,
                            ),
                            transition: Transition.cupertino,
                          ),
                          onInfo: () => _showSceneInfo(context, background),
                        ),
                      ),
                  ],
          ),
        );
      }),
    );
  }

  void _showSceneInfo(BuildContext context, Map<String, dynamic> background) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: context.vita.surface,
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${background['title'] ?? ''}',
                  style: TextStyle(
                      color: sheetContext.vita.text,
                      fontSize: 22,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              Text(
                  '${background['synopsis'] ?? background['world_setting'] ?? ''}',
                  style: TextStyle(
                      color: sheetContext.vita.subText,
                      fontSize: 15,
                      height: 1.5)),
            ],
          ),
        ),
      ),
    );
  }

  void _chooseNewScene(BuildContext context, StoriesController controller) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: context.vita.pageBg,
      builder: (sheetContext) => SafeArea(
        top: false,
        child: SizedBox(
          height: MediaQuery.sizeOf(sheetContext).height * .72,
          child: Obx(() {
            final backgrounds = _maps(controller.catalog['backgrounds']);
            final remaining =
                controller.catalog['custom_backgrounds_remaining'] as int? ?? 0;
            return Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 16, 12),
                child: Row(children: [
                  Expanded(
                      child: Text('storyHub.scenes'.tr,
                          style: TextStyle(
                              color: sheetContext.vita.text,
                              fontSize: 20,
                              fontWeight: FontWeight.w700))),
                  if (controller.catalog['subscribed'] == true && remaining > 0)
                    TextButton.icon(
                      onPressed: () {
                        Navigator.pop(sheetContext);
                        Get.to(() =>
                            CustomStoryBackgroundPage(controller: controller));
                      },
                      icon: const Icon(Icons.add, size: 18),
                      label: Text('storyHub.custom'.tr),
                    ),
                ]),
              ),
              Expanded(
                  child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                itemCount: backgrounds.length,
                itemBuilder: (_, index) {
                  final background = backgrounds[index];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _BackgroundTile(
                      background: background,
                      onTap: () {
                        Navigator.pop(sheetContext);
                        Get.to(
                            () => _StoryCastPage(
                                  controller: controller,
                                  background: background,
                                ),
                            transition: Transition.cupertino);
                      },
                      onInfo: () => _showSceneInfo(sheetContext, background),
                    ),
                  );
                },
              )),
            ]);
          }),
        ),
      ),
    );
  }
}

class _StoryCastPage extends StatefulWidget {
  const _StoryCastPage({required this.controller, required this.background});

  final StoriesController controller;
  final Map<String, dynamic> background;

  @override
  State<_StoryCastPage> createState() => _StoryCastPageState();
}

class _StoryCastPageState extends State<_StoryCastPage> {
  bool _chosen = false;
  bool _starting = false;
  String? _actorId;

  Future<void> _startStory(Map<String, dynamic>? actor) async {
    if (_starting) return;
    setState(() => _starting = true);
    final story = await widget.controller.start(widget.background, actor);
    if (!mounted) return;
    if (story != null && story.isNotEmpty) {
      Get.off(() => StoryDetailPage(initial: story),
          transition: Transition.cupertino);
      return;
    }
    setState(() => _starting = false);
  }

  @override
  Widget build(BuildContext context) => PopScope(
      canPop: !_starting,
      child: Scaffold(
        backgroundColor: context.vita.pageBg,
        appBar: AppBar(
          leading: VitaBackButton(onPressed: _starting ? () {} : null),
          title: Text('storyHub.cast'.tr),
        ),
        body: Stack(children: [
          Obx(() {
            final actors = widget.controller.companions
                .where((item) => item['creation_source'] != 'ai_pet')
                .toList();
            final selectedActor =
                actors.firstWhereOrNull((item) => '${item['id']}' == _actorId);
            return Column(children: [
              Expanded(
                  child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                children: [
                  Text('${widget.background['title'] ?? ''}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: context.vita.text,
                          fontSize: 21,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  Text('storyHub.chooseCompanion'.tr,
                      style:
                          TextStyle(color: context.vita.subText, fontSize: 13)),
                  const SizedBox(height: 20),
                  _ProtagonistOption(
                    name: AuthController.to.nickname.isNotEmpty
                        ? AuthController.to.nickname
                        : 'storyHub.self'.tr,
                    subtitle: 'storyHub.self'.tr,
                    imageUrl: AuthController.to.avatarUrl,
                    selected: _chosen && _actorId == null,
                    onTap: () => setState(() {
                      _chosen = true;
                      _actorId = null;
                    }),
                  ),
                  for (final actor in actors)
                    _ProtagonistOption(
                      name: '${actor['name'] ?? ''}',
                      subtitle: '',
                      imageUrl: actor['portrait_url'] as String?,
                      selected: _chosen && _actorId == '${actor['id']}',
                      onTap: () => setState(() {
                        _chosen = true;
                        _actorId = '${actor['id']}';
                      }),
                    ),
                ],
              )),
              SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                    child: SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: !_chosen ||
                                  (_actorId != null && selectedActor == null) ||
                                  widget.controller.loading.value
                              ? null
                              : () => _startStory(selectedActor),
                          icon: const Icon(Icons.movie_creation_outlined),
                          label: Text('storyHub.action'.tr),
                        )),
                  )),
            ]);
          }),
          if (_starting) ...[
            const Positioned.fill(
              child: ModalBarrier(dismissible: false, color: Color(0xCC000000)),
            ),
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 30),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: context.vita.green),
                    const SizedBox(height: 22),
                    Text('storyHub.loadingPlot'.tr,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ),
          ],
        ]),
      ));
}

class _ProtagonistOption extends StatelessWidget {
  const _ProtagonistOption({
    required this.name,
    required this.subtitle,
    required this.imageUrl,
    required this.onTap,
    this.selected = false,
  });

  final String name;
  final String subtitle;
  final String? imageUrl;
  final VoidCallback? onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Material(
          color: selected ? context.vita.greenTint : context.vita.pageBg,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: selected
                ? BorderSide(color: context.vita.green, width: 1.5)
                : BorderSide.none,
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: SizedBox(
              height: 76,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 13),
                child: Row(children: [
                  VitaAvatar(
                    name: name,
                    radius: 25,
                    imageUrl: imageUrl,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: context.vita.text,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            )),
                        if (subtitle.isNotEmpty) ...[
                          const SizedBox(height: 3),
                          Text(subtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  color: context.vita.subText, fontSize: 12)),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                      selected ? Icons.check_circle_rounded : Icons.add_rounded,
                      size: 18,
                      color: context.vita.green),
                ]),
              ),
            ),
          ),
        ),
      );
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});
  final String title;
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 12, 8),
      child: Row(children: [
        Expanded(
            child: Text(title,
                style: TextStyle(color: context.vita.subText, fontSize: 14))),
      ]));
}

class _StoryBookTile extends StatelessWidget {
  const _StoryBookTile({required this.story, required this.onTap});

  final Map<String, dynamic> story;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cover = '${story['cover_url'] ?? ''}'.trim();
    final title = '${story['title'] ?? ''}'.trim();
    return SizedBox(
      height: 128,
      child: Material(
        color: const Color(0xFF3E3654),
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Row(children: [
            SizedBox(
              width: 96,
              height: double.infinity,
              child: Stack(fit: StackFit.expand, children: [
                if (cover.isNotEmpty)
                  VitaMediaImage(
                    url: cover,
                    errorBuilder: (_, __, ___) => const SizedBox.expand(),
                  ),
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  child: Container(
                    width: 8,
                    color: const Color(0xAA21192F),
                    alignment: Alignment.centerRight,
                    child: Container(width: 1, color: Colors.white24),
                  ),
                ),
              ]),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 13, 14, 13),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title.isEmpty ? 'storyHub.story'.tr : title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          height: 1.2,
                          fontWeight: FontWeight.w700,
                        )),
                    const SizedBox(height: 5),
                    Text(
                      'storyHub.chapterCount'.trParams(
                          {'count': '${story['current_chapter_no'] ?? 0}'}),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          const TextStyle(color: Colors.white70, fontSize: 11),
                    ),
                    const Spacer(),
                    Row(children: [
                      Flexible(
                        child: Text('storyHub.continue'.tr,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: Colors.white, fontSize: 12)),
                      ),
                      const SizedBox(width: 4),
                      const Icon(Icons.arrow_forward_rounded,
                          size: 13, color: Colors.white),
                    ]),
                  ],
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

class _BackgroundTile extends StatelessWidget {
  const _BackgroundTile(
      {required this.background, required this.onTap, required this.onInfo});
  final Map<String, dynamic> background;
  final VoidCallback onTap;
  final VoidCallback onInfo;
  @override
  Widget build(BuildContext context) {
    final cover = '${background['cover_url'] ?? ''}';
    return SizedBox(
      height: 112,
      child: Material(
        color: const Color(0xFF51456E),
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Stack(fit: StackFit.expand, children: [
            if (cover.isNotEmpty)
              VitaMediaImage(
                url: cover,
                errorBuilder: (_, __, ___) => const SizedBox.expand(),
              ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0x00000000), Color(0xE8191525)],
                  stops: [.25, 1],
                ),
              ),
            ),
            if (background['custom'] == true)
              const Positioned(
                top: 12,
                left: 14,
                child: Icon(Icons.lock_outline, size: 18, color: Colors.white),
              ),
            Positioned(
              top: 0,
              right: 0,
              child: IconButton(
                onPressed: onInfo,
                icon:
                    const Icon(Icons.info_outline_rounded, color: Colors.white),
              ),
            ),
            Positioned(
              left: 16,
              right: 16,
              bottom: 18,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('${background['title'] ?? ''}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 17,
                          height: 1.15,
                          fontWeight: FontWeight.w700,
                          color: Colors.white)),
                  const SizedBox(height: 8),
                  Text(
                      '${background['synopsis'] ?? background['world_setting'] ?? ''}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 12, height: 1.35, color: Colors.white70)),
                  const SizedBox(height: 4),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Icon(Icons.add_circle_outline_rounded,
                        size: 20, color: Colors.white),
                  ),
                ],
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

class CustomStoryBackgroundPage extends StatefulWidget {
  const CustomStoryBackgroundPage({super.key, required this.controller});
  final StoriesController controller;
  @override
  State<CustomStoryBackgroundPage> createState() =>
      _CustomStoryBackgroundPageState();
}

class _CustomStoryBackgroundPageState extends State<CustomStoryBackgroundPage> {
  final title = TextEditingController(),
      synopsis = TextEditingController(),
      world = TextEditingController(),
      opening = TextEditingController(),
      genre = TextEditingController(),
      constraints = TextEditingController(),
      goal = TextEditingController();
  bool saving = false;
  @override
  void dispose() {
    for (final x in [
      title,
      synopsis,
      world,
      opening,
      genre,
      constraints,
      goal
    ]) {
      x.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      backgroundColor: context.vita.pageBg,
      appBar: AppBar(
          leading: const VitaBackButton(),
          title: Text('storyHub.createCustom'.tr)),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        _field(title, 'storyHub.name'.tr),
        _field(genre, 'storyHub.genre'.tr),
        _field(synopsis, 'storyHub.synopsis'.tr, max: 3),
        _field(world, 'storyHub.world'.tr, max: 5),
        _field(opening, 'storyHub.opening'.tr, max: 5),
        _field(constraints, 'storyHub.constraints'.tr, max: 3),
        _field(goal, 'storyHub.goal'.tr, max: 3),
        const SizedBox(height: 10),
        FilledButton(
            onPressed: saving ? null : _save,
            child: saving
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : Text('storyHub.create'.tr))
      ]));
  Widget _field(TextEditingController c, String label, {int max = 1}) =>
      Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: TextField(
              controller: c,
              maxLines: max,
              decoration: InputDecoration(
                  labelText: label,
                  filled: true,
                  fillColor: context.vita.surface,
                  border: InputBorder.none)));
  Future<void> _save() async {
    if (title.text.trim().isEmpty ||
        world.text.trim().isEmpty ||
        opening.text.trim().isEmpty) {
      _showError(ApiException('storyHub.required'.tr));
      return;
    }
    setState(() => saving = true);
    try {
      await ApiClient.instance.post('/v1/story-backgrounds/', data: {
        'title': title.text,
        'synopsis': synopsis.text,
        'world_setting': world.text,
        'opening': opening.text,
        'genre': genre.text,
        'character_constraints': constraints.text,
        'story_goal': goal.text
      });
      await widget.controller.load();
      Get.back();
    } catch (e) {
      _showError(e);
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }
}

class StoryDetailPage extends StatefulWidget {
  const StoryDetailPage({super.key, this.storyId, this.initial});
  final String? storyId;
  final Map<String, dynamic>? initial;
  @override
  State<StoryDetailPage> createState() => _StoryDetailPageState();
}

class _StoryDetailPageState extends State<StoryDetailPage> {
  Map<String, dynamic> data = {};
  bool loading = false;
  String get id => widget.storyId ?? '${data['id'] ?? ''}';
  @override
  void initState() {
    super.initState();
    data = widget.initial ?? {};
    if (widget.storyId != null) _load();
  }

  Future<void> _load() async {
    setState(() => loading = true);
    try {
      data = _map(await ApiClient.instance.get('/v1/stories/$id'));
    } catch (e) {
      _showError(e);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _choose(String choiceId) async {
    setState(() => loading = true);
    try {
      data = _map(await ApiClient.instance.post('/v1/stories/$id/choices',
          data: {'choice_id': choiceId, 'idempotency_key': _requestKey()}));
    } catch (e) {
      _showError(e);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _chooseStoryboardCount() async {
    final count = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: context.vita.surface,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text('storyHub.choosePanelCount'.tr,
                  style: const TextStyle(
                      fontSize: 17, fontWeight: FontWeight.w600)),
            ),
            for (final value in const [4, 6, 8, 9])
              ListTile(
                title: Text('storyHub.panelsCount'
                    .trParams({'count': value.toString()})),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(sheetContext).pop(value),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (count != null && mounted) await _storyboard(count);
  }

  Future<void> _storyboard(int panelCount) async {
    setState(() => loading = true);
    try {
      data = _map(
          await ApiClient.instance.post('/v1/stories/$id/storyboards', data: {
        'idempotency_key': _requestKey(),
        'panel_count': panelCount,
      }));
      for (var attempt = 0; attempt < 50; attempt++) {
        final boards = _maps(data['storyboards']);
        final status = boards.isEmpty ? '' : '${boards.first['status'] ?? ''}';
        if (status != 'pending' && status != 'generating') break;
        await Future<void>.delayed(const Duration(seconds: 2));
        data = _map(await ApiClient.instance.get('/v1/stories/$id'));
        if (mounted) setState(() {});
      }
    } catch (e) {
      _showError(e);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final chapters = _maps(data['chapters']);
    final boards = _maps(data['storyboards']);
    final canContinue = data['can_continue'] != false;
    final unlocked = data['storyboard_unlocked'] == true;
    final latestOpen = chapters.isNotEmpty &&
        '${chapters.last['selected_choice_id'] ?? ''}'.isEmpty;
    return Scaffold(
      backgroundColor: context.vita.pageBg,
      appBar: AppBar(
        title: Text('${data['title'] ?? 'storyHub.story'.tr}'),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh))
        ],
      ),
      body: loading && chapters.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.only(top: 12, bottom: 30),
              children: [
                ...chapters.map(
                  (chapter) => _ChapterReadingPage(chapter: chapter),
                ),
                if (latestOpen) ...[
                  _SectionHeader(title: 'storyHub.chooseNext'.tr),
                  if (!canContinue)
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text('storyHub.subscribeContinue'.tr,
                          style: TextStyle(color: context.vita.subText)),
                    ),
                  if (canContinue)
                    ..._maps(chapters.last['choices']).map(
                      (choice) => Padding(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                        child: Material(
                          color: context.vita.surface,
                          borderRadius: BorderRadius.circular(16),
                          clipBehavior: Clip.antiAlias,
                          child: InkWell(
                            onTap: loading
                                ? null
                                : () => _choose('${choice['id']}'),
                            child: SizedBox(
                              height: 76,
                              child: Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 16),
                                child: Row(children: [
                                  Expanded(
                                    child: Text('${choice['text'] ?? ''}',
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                            color: context.vita.text,
                                            fontSize: 15,
                                            height: 1.35)),
                                  ),
                                  const SizedBox(width: 8),
                                  Icon(Icons.arrow_forward_rounded,
                                      size: 18, color: context.vita.green),
                                ]),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  if (unlocked)
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: OutlinedButton.icon(
                        onPressed: loading ? null : _chooseStoryboardCount,
                        icon: const Icon(Icons.movie_creation_outlined),
                        label: Text('storyHub.generateStoryboard'.tr),
                      ),
                    ),
                ],
                if (boards.isNotEmpty) ...[
                  _SectionHeader(title: 'storyHub.storyboards'.tr),
                  ...boards.map(
                    (board) {
                      final status = '${board['status'] ?? ''}';
                      final ready = status == 'completed';
                      final summary = '${board['summary'] ?? ''}'.trim();
                      return Padding(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                        child: Material(
                          color: context.vita.surface,
                          borderRadius: BorderRadius.circular(16),
                          clipBehavior: Clip.antiAlias,
                          child: InkWell(
                            onTap: ready
                                ? () => Get.to(
                                    () => StoryboardPage(board: board),
                                    transition: Transition.cupertino)
                                : null,
                            child: SizedBox(
                              height: 88,
                              child: Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 16),
                                child: Row(children: [
                                  const Icon(Icons.movie_outlined,
                                      color: Color(0xFF576B95)),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Text(
                                            summary.isNotEmpty
                                                ? summary
                                                : status == 'failed'
                                                    ? 'storyHub.storyboardFailed'
                                                        .tr
                                                    : 'storyHub.storyboardGenerating'
                                                        .tr,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis),
                                        Text(
                                            'storyHub.panelsCount'.trParams({
                                              'count':
                                                  '${board['panel_count'] ?? 0}'
                                            }),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                                color: context.vita.subText,
                                                fontSize: 12)),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  if (ready)
                                    const Icon(Icons.chevron_right)
                                  else if (status == 'failed')
                                    const Icon(Icons.error_outline,
                                        color: Colors.redAccent)
                                  else
                                    const SizedBox.square(
                                      dimension: 18,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2),
                                    ),
                                ]),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ],
                if (loading)
                  const Padding(
                      padding: EdgeInsets.all(16),
                      child: Center(child: CircularProgressIndicator())),
              ],
            ),
    );
  }
}

class _ChapterReadingPage extends StatelessWidget {
  const _ChapterReadingPage({required this.chapter});

  final Map<String, dynamic> chapter;

  @override
  Widget build(BuildContext context) {
    final dark = context.vita.brightness == Brightness.dark;
    final paper = dark ? const Color(0xFF211E26) : const Color(0xFFFFFBF3);
    final ink = dark ? const Color(0xFFF4EDE3) : const Color(0xFF2C2630);
    final secondary = dark ? const Color(0xFFB6AABD) : const Color(0xFF766A70);
    final selected = '${chapter['selected_choice_text'] ?? ''}'.trim();
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      padding: const EdgeInsets.fromLTRB(23, 26, 23, 30),
      decoration: BoxDecoration(
        color: paper,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('${chapter['title'] ?? ''}',
            style: TextStyle(
                color: ink,
                fontSize: 23,
                height: 1.25,
                fontWeight: FontWeight.w700)),
        const SizedBox(height: 15),
        Container(width: 38, height: 2, color: context.vita.green),
        const SizedBox(height: 24),
        Text('${chapter['content'] ?? ''}',
            style: TextStyle(color: ink, fontSize: 16, height: 1.85)),
        if (selected.isNotEmpty) ...[
          const SizedBox(height: 24),
          Divider(color: secondary.withValues(alpha: .35)),
          const SizedBox(height: 8),
          Text(selected,
              style: TextStyle(color: secondary, fontSize: 14, height: 1.5)),
        ],
      ]),
    );
  }
}

class StoryboardPage extends StatelessWidget {
  const StoryboardPage({super.key, required this.board});
  final Map<String, dynamic> board;

  @override
  Widget build(BuildContext context) {
    final panels = _maps(board['panels']);
    final imageURL = '${board['image_url'] ?? ''}';
    return Scaffold(
      backgroundColor: context.vita.pageBg,
      appBar: AppBar(
          leading: const VitaBackButton(),
          title: Text('storyHub.storyboard'.tr)),
      body: ListView(
        padding: const EdgeInsets.only(top: 12, bottom: 30),
        children: [
          VitaCard(
            radius: 0,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AspectRatio(
                  aspectRatio: 1,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: imageURL.isEmpty
                        ? Container(color: context.vita.pageBg)
                        : VitaMediaImage(url: imageURL),
                  ),
                ),
                const SizedBox(height: 12),
                Text('${board['summary'] ?? ''}',
                    style: const TextStyle(fontSize: 16, height: 1.6)),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: imageURL.isEmpty
                        ? null
                        : () => _share(imageURL, 'storyHub.storyboard'.tr),
                    icon: const Icon(Icons.ios_share, size: 18),
                    label: Text('storyHub.shareExternal'.tr),
                  ),
                ),
              ],
            ),
          ),
          ...panels.asMap().entries.map((entry) {
            final panel = entry.value;
            return VitaCard(
              radius: 0,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${entry.key + 1}. ${panel['title'] ?? ''}',
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 16)),
                  if ('${panel['description'] ?? ''}'.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text('${panel['description']}'),
                    ),
                  if ('${panel['dialogue'] ?? ''}'.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text('${panel['dialogue']}',
                          style: TextStyle(color: context.vita.subText)),
                    ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Future<void> _share(String url, String title) async {
    try {
      final dir = await getTemporaryDirectory();
      final file = File(
          '${dir.path}/vita-story-${DateTime.now().millisecondsSinceEpoch}.jpg');
      if (url.startsWith('data:image/') && url.contains(',')) {
        await file
            .writeAsBytes(base64Decode(url.substring(url.indexOf(',') + 1)));
      } else {
        final response = await ApiClient.instance.dio.get<List<int>>(url,
            options: Options(responseType: ResponseType.bytes));
        await file.writeAsBytes(response.data ?? []);
      }
      await Share.shareXFiles([XFile(file.path)], text: title);
    } catch (error) {
      _showError(error);
    }
  }
}
