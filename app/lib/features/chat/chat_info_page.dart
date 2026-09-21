import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/analytics_service.dart';
import '../../core/api_client.dart';
import '../../core/constants.dart';
import '../../core/theme.dart';
import '../../shared/media_image.dart';
import '../../shared/widgets.dart';
import '../billing/credits_page.dart';
import '../billing/subscription_page.dart';
import '../life/life_detail_page.dart';
import '../memories/memories_page.dart';
import 'experience_sheet.dart';

class ChatInfoPage extends StatelessWidget {
  const ChatInfoPage({
    super.key,
    required this.companion,
    required this.onExperienceCompleted,
    this.onExperienceResult,
  });

  final Map<String, dynamic> companion;
  final Future<void> Function() onExperienceCompleted;
  final Future<void> Function(Map<String, dynamic> response)?
      onExperienceResult;

  String get companionId => companion['id'] as String? ?? '';
  String get name => companion['name'] as String? ?? 'chat.companion'.tr;

  @override
  Widget build(BuildContext context) {
    final vita = context.vita;
    return Scaffold(
      backgroundColor: vita.pageBg,
      appBar: AppBar(
        title: Text('chatInfo.title'.tr),
        shape: const Border(),
      ),
      body: ListView(
        padding: const EdgeInsets.only(top: 0, bottom: 28),
        children: [
          _group([
            _ProfileRow(
              companion: companion,
              onTap: () => _openLifeDetail(),
            ),
          ]),
          _group([
            _InfoRow(
              icon: Icons.auto_awesome_outlined,
              title: 'experience.title'.tr,
              onTap: () => _showExperiences(context),
            ),
            _InfoRow(
              icon: Icons.star_outline,
              title: 'memories.title'.tr,
              onTap: () => Get.to(
                () => MemoryDetailPage(companion: companion),
                transition: Transition.cupertino,
              ),
            ),
          ]),
          _group([
            _InfoRow(
              icon: Icons.photo_library_outlined,
              title: 'chatInfo.media'.tr,
              onTap: () => Get.to(
                () => ChatMediaPage(
                  companionId: companionId,
                  companionName: name,
                ),
                transition: Transition.cupertino,
              ),
            ),
          ]),
          _group([
            _InfoRow(
              icon: Icons.workspace_premium_outlined,
              title: 'chatInfo.subscription'.tr,
              onTap: () => Get.to(
                () => const SubscriptionPage(),
                transition: Transition.cupertino,
              ),
            ),
            _InfoRow(
              icon: Icons.toll_outlined,
              title: 'chatInfo.credits'.tr,
              onTap: () => Get.to(
                () => const CreditsPage(),
                transition: Transition.cupertino,
              ),
            ),
          ]),
          if (companion['is_default'] != true) ...[
            const SizedBox(height: 2),
            Material(
              color: vita.surface,
              child: InkWell(
                onTap: () => _confirmDelete(context),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 16,
                  ),
                  child: Center(
                    child: Text(
                      'chatInfo.delete'.tr,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: vita.red,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _group(List<Widget> rows) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        children: [
          for (var index = 0; index < rows.length; index++) ...[
            if (index > 0) const Divider(height: 0.5, indent: 56),
            rows[index],
          ],
        ],
      ),
    );
  }

  void _openLifeDetail() {
    Get.to(
      () => LifeDetailPage(companion: companion),
      transition: Transition.cupertino,
    );
  }

  void _showExperiences(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.vita.surface,
      showDragHandle: true,
      builder: (_) => ExperienceSheet(
        companionId: companionId,
        onCompleted: onExperienceCompleted,
        onResult: onExperienceResult,
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final first = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('chatInfo.deleteConfirmTitle'.tr),
        content: Text('chatInfo.deleteConfirmMessage'.trParams({'name': name})),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text('common.cancel'.tr),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text('chatInfo.deleteContinue'.tr),
          ),
        ],
      ),
    );
    if (first != true || !context.mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('chatInfo.deleteFinalTitle'.tr),
        content: Text('chatInfo.deleteFinalMessage'.tr),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text('common.cancel'.tr),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: dialogContext.vita.red,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text('chatInfo.delete'.tr),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      final result = await ApiClient.instance.delete(
        '/v1/companions/$companionId',
      );
      AnalyticsService.to.track(
        'companion_soft_deleted',
        category: 'companion',
        properties: {'companion_id': companionId},
      );
      if (!context.mounted) return;
      final running = result is Map && result['life_engine_running'] == true;
      Get.snackbar(
        'chatInfo.deleted'.tr,
        running ? 'chatInfo.deletedRunning'.tr : 'chatInfo.deletedPaused'.tr,
      );
      Get.back(result: true);
    } on ApiException catch (error) {
      Get.snackbar('chatInfo.deleteFailed'.tr, error.message);
    }
  }
}

class _ProfileRow extends StatelessWidget {
  const _ProfileRow({required this.companion, required this.onTap});

  final Map<String, dynamic> companion;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final name = companion['name'] as String? ?? 'chat.companion'.tr;
    return Material(
      color: context.vita.surface,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
          child: Row(
            children: [
              VitaAvatar(
                name: name,
                radius: 28,
                imageUrl: companion['portrait_url'] as String?,
                borderRadius: BorderRadius.circular(12),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  name,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: context.vita.text,
                  ),
                ),
              ),
              Icon(Icons.chevron_right, color: context.vita.chevron),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.title,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.vita.surface,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
          child: Row(
            children: [
              Icon(icon, size: 21, color: context.vita.green),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(fontSize: 16, color: context.vita.text),
                ),
              ),
              Icon(Icons.chevron_right, color: context.vita.chevron),
            ],
          ),
        ),
      ),
    );
  }
}

class ChatMediaPage extends StatefulWidget {
  const ChatMediaPage({
    super.key,
    required this.companionId,
    required this.companionName,
  });

  final String companionId;
  final String companionName;

  @override
  State<ChatMediaPage> createState() => _ChatMediaPageState();
}

class _ChatMediaPageState extends State<ChatMediaPage> {
  static const _pageSize = 30;
  final _items = <Map<String, dynamic>>[];
  final _player = AudioPlayer();
  bool _loading = false;
  bool _hasMore = true;
  int _page = 1;
  String? _conversationId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _load({bool refresh = false}) async {
    if (_loading || (!refresh && !_hasMore)) return;
    setState(() => _loading = true);
    try {
      if (refresh) {
        _page = 1;
        _hasMore = true;
        _items.clear();
      }
      if (_conversationId == null) {
        final conversation = await ApiClient.instance.post(
          '/v1/conversations/',
          data: {'companion_id': widget.companionId},
        );
        _conversationId = conversation is Map
            ? conversation['conversation_id'] as String?
            : null;
      }
      if (_conversationId == null) return;
      final data = await ApiClient.instance.get(
        '/v1/conversations/$_conversationId/media',
        query: {'page': _page, 'page_size': _pageSize},
      );
      if (!mounted || data is! Map) return;
      final next = (data['items'] as List? ?? const [])
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
      setState(() {
        _items.addAll(next);
        final totalPages = data['total_pages'] as int? ?? 0;
        _hasMore = _page < totalPages;
        if (_hasMore) _page++;
      });
    } on ApiException catch (error) {
      if (mounted) Get.snackbar('chatInfo.media'.tr, error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _playVoice(String url) async {
    final resolved = url.startsWith('http')
        ? url
        : '${vitaApiBaseUrl.replaceFirst(RegExp(r'/+$'), '')}${url.startsWith('/') ? url : '/$url'}';
    if (Uri.tryParse(resolved)?.path.startsWith('/v1/media/') == true) {
      final response = await ApiClient.instance.dio.get<List<int>>(
        resolved,
        options: Options(responseType: ResponseType.bytes),
      );
      final bytes = response.data;
      if (bytes == null || bytes.isEmpty) return;
      final directory = await getTemporaryDirectory();
      final file = File(
        '${directory.path}/vita_media_${Uri.parse(resolved).pathSegments.last}.m4a',
      );
      await file.writeAsBytes(bytes, flush: true);
      await _player.play(DeviceFileSource(file.path));
      return;
    }
    await _player.play(UrlSource(resolved));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.vita.pageBg,
      appBar: AppBar(title: Text('chatInfo.media'.tr)),
      body: RefreshIndicator(
        onRefresh: () => _load(refresh: true),
        child: _items.isEmpty && !_loading
            ? ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  SizedBox(
                    height: MediaQuery.sizeOf(context).height * 0.65,
                    child: VitaEmpty(
                      icon: Icons.photo_library_outlined,
                      title: 'chatInfo.mediaEmpty'.tr,
                      subtitle: 'chatInfo.mediaEmptySub'.tr,
                    ),
                  ),
                ],
              )
            : ListView.builder(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                itemCount: _items.length + ((_loading || _hasMore) ? 1 : 0),
                itemBuilder: (context, index) {
                  if (index == _items.length) {
                    if (!_loading) {
                      WidgetsBinding.instance
                          .addPostFrameCallback((_) => _load());
                    }
                    return const Padding(
                      padding: EdgeInsets.all(20),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  final item = _items[index];
                  final url = item['media_url'] as String? ?? '';
                  if (item['kind'] == 'voice') {
                    return _VoiceMediaRow(
                      item: item,
                      onTap: () => _playVoice(url),
                    );
                  }
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: AspectRatio(
                      aspectRatio: 4 / 3,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: VitaMediaImage(url: url),
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }
}

class _VoiceMediaRow extends StatelessWidget {
  const _VoiceMediaRow({required this.item, required this.onTap});

  final Map<String, dynamic> item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final date = DateTime.tryParse(item['created_at'] as String? ?? '');
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: context.vita.surface,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            child: Row(
              children: [
                Icon(Icons.play_circle_fill,
                    size: 32, color: context.vita.green),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    item['content'] as String? ?? 'chat.voiceMessage'.tr,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 14, color: context.vita.text),
                  ),
                ),
                if (date != null)
                  Text(
                    formatDate(date.toLocal()),
                    style: TextStyle(fontSize: 12, color: context.vita.subText),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
