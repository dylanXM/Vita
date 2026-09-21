import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart' hide Response;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

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
      companions.assignAll(_maps(values[2]));
    } catch (error) {
      _showError(error);
    } finally {
      loading.value = false;
    }
  }

  Future<void> start(
      Map<String, dynamic> background, Map<String, dynamic>? companion) async {
    loading.value = true;
    try {
      final data = <String, dynamic>{
        'background_id': background['id'],
        'idempotency_key': _requestKey(),
      };
      if (companion != null) data['companion_id'] = companion['id'];
      final result = await ApiClient.instance.post('/v1/stories/', data: data);
      await load();
      Get.to(() => StoryDetailPage(initial: _map(result)),
          transition: Transition.cupertino);
    } catch (error) {
      _showError(error);
    } finally {
      loading.value = false;
    }
  }
}

void _showError(Object error) {
  final message = error is ApiException ? error.message : error.toString();
  Get.snackbar('storyHub.title'.tr, message,
      snackPosition: SnackPosition.BOTTOM, margin: const EdgeInsets.all(12));
}

class StoriesPage extends StatelessWidget {
  const StoriesPage({super.key, this.controller});

  final StoriesController? controller;

  @override
  Widget build(BuildContext context) {
    final StoriesController activeController =
        controller ?? Get.put<StoriesController>(StoriesController());
    return Scaffold(
      backgroundColor: context.vita.pageBg,
      appBar: AppBar(title: Text('storyHub.title'.tr)),
      body: Obx(() {
        final backgrounds = _maps(activeController.catalog['backgrounds']);
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
            padding: const EdgeInsets.only(top: 12, bottom: 32),
            children: [
              _SectionHeader(
                  title: 'storyHub.backgrounds'.tr,
                  action: subscribed
                      ? TextButton.icon(
                          onPressed: remaining > 0
                              ? () => Get.to(() => CustomStoryBackgroundPage(
                                  controller: activeController))
                              : null,
                          icon: const Icon(Icons.add, size: 18),
                          label: Text('storyHub.custom'.tr))
                      : null),
              if (subscribed)
                Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                    child: Text(
                        'storyHub.quota'.trParams({'remaining': '$remaining'}),
                        style: TextStyle(
                            color: context.vita.subText, fontSize: 12))),
              ...backgrounds.map((background) => _BackgroundTile(
                  background: background,
                  onTap: () =>
                      _chooseCompanion(context, activeController, background))),
              const SizedBox(height: 10),
              _SectionHeader(title: 'storyHub.myStories'.tr),
              if (activeController.stories.isEmpty)
                Padding(
                    padding: const EdgeInsets.all(32),
                    child: VitaEmpty(
                        icon: Icons.auto_stories_outlined,
                        title: 'storyHub.empty'.tr,
                        subtitle: 'storyHub.emptySub'.tr)),
              ...activeController.stories.map((story) => VitaCard(
                  radius: 0,
                  padding: EdgeInsets.zero,
                  child: Material(
                    color: Colors.transparent,
                    child: ListTile(
                        leading: const Icon(Icons.menu_book_outlined,
                            color: Color(0xFF576B95)),
                        title: Text('${story['title'] ?? ''}'),
                        subtitle: Text('storyHub.chapterCount'.trParams(
                            {'count': '${story['current_chapter_no'] ?? 0}'})),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => Get.to(
                            () => StoryDetailPage(storyId: '${story['id']}'),
                            transition: Transition.cupertino)),
                  ))),
            ],
          ),
        );
      }),
    );
  }

  void _chooseCompanion(BuildContext context, StoriesController controller,
      Map<String, dynamic> background) {
    showModalBottomSheet<void>(
        context: context,
        backgroundColor: context.vita.surface,
        builder: (_) => SafeArea(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
              Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text('storyHub.chooseCompanion'.tr,
                      style: const TextStyle(
                          fontSize: 17, fontWeight: FontWeight.w600))),
              // Self-as-protagonist entry: no AI companion, the user themselves
              // is the lead character.
              ListTile(
                  leading: Obx(() {
                    final auth = AuthController.to;
                    final name = auth.nickname.isNotEmpty
                        ? auth.nickname
                        : (auth.email.isEmpty ? 'storyHub.self'.tr : auth.email);
                    return VitaAvatar(
                        name: name,
                        imageUrl: auth.avatarUrl,
                    );
                  }),
                  title: Text('storyHub.self'.tr),
                  onTap: () {
                    Get.back();
                    controller.start(background, null);
                  }),
              const Divider(height: 0.5, indent: 72),
              ...controller.companions.map((companion) => ListTile(
                  leading: VitaAvatar(
                      name: '${companion['name'] ?? ''}',
                      imageUrl: '${companion['avatar_url'] ?? ''}'),
                  title: Text('${companion['name'] ?? ''}'),
                  onTap: () {
                    Get.back();
                    controller.start(background, companion);
                  })),
              const SizedBox(height: 8)
            ])));
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, this.action});
  final String title;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 12, 8),
      child: Row(children: [
        Expanded(
            child: Text(title,
                style: TextStyle(color: context.vita.subText, fontSize: 14))),
        if (action != null) action!
      ]));
}

class _BackgroundTile extends StatelessWidget {
  const _BackgroundTile({required this.background, required this.onTap});
  final Map<String, dynamic> background;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final cover = '${background['cover_url'] ?? ''}';
    return VitaCard(
        radius: 0,
        padding: EdgeInsets.zero,
        child: Material(
          color: Colors.transparent,
          child: ListTile(
              minVerticalPadding: 12,
              leading: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: SizedBox(
                      width: 58,
                      height: 58,
                      child: cover.isEmpty
                          ? Container(
                              color: context.vita.pageBg,
                              child: const Icon(Icons.auto_stories_outlined,
                                  color: Color(0xFF576B95)))
                          : VitaMediaImage(url: cover))),
              title: Row(children: [
                Expanded(
                    child: Text('${background['title'] ?? ''}',
                        style: const TextStyle(fontWeight: FontWeight.w600))),
                if (background['custom'] == true)
                  Text('storyHub.private'.tr,
                      style: TextStyle(fontSize: 12, color: context.vita.green))
              ]),
              subtitle: Text(
                  '${background['synopsis'] ?? background['world_setting'] ?? ''}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis),
              trailing: const Icon(Icons.chevron_right),
              onTap: onTap),
        ));
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
      appBar: AppBar(title: Text('storyHub.createCustom'.tr)),
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
                  (chapter) => VitaCard(
                    radius: 0,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${chapter['title'] ?? ''}',
                            style: const TextStyle(
                                fontSize: 18, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 10),
                        Text('${chapter['content'] ?? ''}',
                            style: const TextStyle(fontSize: 16, height: 1.7)),
                        if ('${chapter['selected_choice_text'] ?? ''}'
                            .isNotEmpty) ...[
                          const Divider(height: 28),
                          Text('✓ ${chapter['selected_choice_text']}',
                              style: TextStyle(color: context.vita.subText)),
                        ],
                      ],
                    ),
                  ),
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
                      (choice) => VitaCard(
                        radius: 0,
                        padding: EdgeInsets.zero,
                        child: Material(
                          color: Colors.transparent,
                          child: ListTile(
                            title: Text('${choice['text'] ?? ''}'),
                            trailing: const Icon(Icons.chevron_right),
                            enabled: !loading,
                            onTap: () => _choose('${choice['id']}'),
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
                      return VitaCard(
                        radius: 0,
                        padding: EdgeInsets.zero,
                        child: Material(
                          color: Colors.transparent,
                          child: ListTile(
                            leading: const Icon(Icons.movie_outlined,
                                color: Color(0xFF576B95)),
                            title: Text(
                                summary.isNotEmpty
                                    ? summary
                                    : status == 'failed'
                                        ? 'storyHub.storyboardFailed'.tr
                                        : 'storyHub.storyboardGenerating'.tr,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis),
                            subtitle: Text('storyHub.panelsCount'.trParams(
                                {'count': '${board['panel_count'] ?? 0}'})),
                            trailing: ready
                                ? const Icon(Icons.chevron_right)
                                : status == 'failed'
                                    ? const Icon(Icons.error_outline,
                                        color: Colors.redAccent)
                                    : const SizedBox.square(
                                        dimension: 18,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2)),
                            onTap: ready
                                ? () => Get.to(
                                    () => StoryboardPage(board: board),
                                    transition: Transition.cupertino)
                                : null,
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

class StoryboardPage extends StatelessWidget {
  const StoryboardPage({super.key, required this.board});
  final Map<String, dynamic> board;

  @override
  Widget build(BuildContext context) {
    final panels = _maps(board['panels']);
    final imageURL = '${board['image_url'] ?? ''}';
    return Scaffold(
      backgroundColor: context.vita.pageBg,
      appBar: AppBar(title: Text('storyHub.storyboard'.tr)),
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
