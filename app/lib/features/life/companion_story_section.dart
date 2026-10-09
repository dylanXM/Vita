import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/notice.dart';
import '../../core/api_client.dart';
import '../../core/theme.dart';
import '../chat/companion_moment_page.dart';

String _storyDescription(dynamic raw) {
  final value = raw is String ? raw : '';
  return value.startsWith('experience.') ? value.tr : value;
}

/// Displays only persisted, user-owned records returned by /story.
class CompanionStorySection extends StatefulWidget {
  const CompanionStorySection({
    super.key,
    required this.companionId,
    required this.companionName,
    required this.avatarUrl,
    required this.onChat,
    required this.onExperience,
  });

  final String companionId;
  final String companionName;
  final String? avatarUrl;
  final VoidCallback onChat;
  final Future<void> Function(String productKey) onExperience;

  @override
  State<CompanionStorySection> createState() => _CompanionStorySectionState();
}

class _CompanionStorySectionState extends State<CompanionStorySection> {
  Map<String, dynamic>? _story;
  List<Map<String, dynamic>> _products = const [];
  bool _loading = true;
  bool _showAll = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await ApiClient.instance
          .get('/v1/companions/${widget.companionId}/story');
      if (!mounted) return;
      if (data is! Map) {
        setState(() {
          _loading = false;
          _error = 'story.retry'.tr;
        });
        return;
      }
      List<Map<String, dynamic>> products = const [];
      try {
        final catalog = await ApiClient.instance
            .get('/v1/companions/${widget.companionId}/experiences');
        if (catalog is Map && catalog['products'] is List) {
          products = (catalog['products'] as List)
              .whereType<Map>()
              .map((item) => Map<String, dynamic>.from(item))
              .toList();
        }
      } on ApiException {
        // The story remains available when the experience catalog is gated.
      }
      if (!mounted) return;
      setState(() {
        _story = Map<String, dynamic>.from(data);
        _products = products;
        _loading = false;
        _error = null;
      });
    } on ApiException catch (error) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = error.message;
        });
      }
    }
  }

  List<Map<String, dynamic>> get _items => (_story?['items'] as List? ?? [])
      .whereType<Map>()
      .map((item) => Map<String, dynamic>.from(item))
      .toList();

  String _date(dynamic raw) {
    final value = raw is String ? DateTime.tryParse(raw)?.toLocal() : null;
    if (value == null) return '';
    return '${value.year}.${value.month.toString().padLeft(2, '0')}.${value.day.toString().padLeft(2, '0')}';
  }

  String _title(Map<String, dynamic> item) {
    if (item['kind'] == 'first_chat') return 'story.firstChat'.tr;
    if (item['kind'] == 'memory') return 'story.memory'.tr;
    final title = (item['title'] as String? ?? '').trim();
    return title.isEmpty ? 'story.event'.tr : title.tr;
  }

  Future<void> _openItem(Map<String, dynamic> item) async {
    final kind = item['kind'];
    if (kind == 'first_chat') {
      widget.onChat();
      return;
    }
    if (kind == 'memory') {
      await _editMemory(item);
      return;
    }
    if (kind == 'event' && item['source'] == 'user_purchase') {
      await Get.to(() => CompanionMomentPage(
            companionId: widget.companionId,
            eventId: '${item['id']}',
            name: widget.companionName,
            avatarUrl: widget.avatarUrl,
          ));
      return;
    }
    if (!mounted) return;
    final description = _storyDescription(item['description']);
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(_title(item)),
        content: description.trim().isEmpty ? null : Text(description),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text('common.cancel'.tr),
          ),
        ],
      ),
    );
  }

  Future<void> _editMemory(Map<String, dynamic> memory) async {
    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: context.vita.surface,
      builder: (_) => _MemoryEditorSheet(
        companionId: widget.companionId,
        memory: memory,
      ),
    );
    if (changed == true && mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final vita = context.vita;
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 28),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null) {
      return TextButton.icon(
        onPressed: () {
          setState(() => _loading = true);
          _load();
        },
        icon: const Icon(Icons.refresh),
        label: Text('story.retry'.tr),
      );
    }
    final items = _items;
    final events = items
        .where((item) =>
            item['kind'] == 'event' && item['source'] != 'user_purchase')
        .take(2)
        .toList();
    final memories = items.where((item) => item['kind'] == 'memory').toList()
      ..sort((a, b) => (b['is_favorite'] == true ? 1 : 0)
          .compareTo(a['is_favorite'] == true ? 1 : 0));
    final experienced = (_story?['experienced_keys'] as List? ?? [])
        .whereType<String>()
        .toSet();
    final dateProducts =
        _products.where((item) => item['category'] == 'date').toList();
    final preferredKey = switch (_story?['relationship_stage']) {
      'partner' => 'date_dinner',
      'close' => 'date_movie',
      _ => 'date_coffee',
    };
    final preferredIndex =
        dateProducts.indexWhere((item) => item['key'] == preferredKey);
    if (preferredIndex > 0) {
      dateProducts.insert(0, dateProducts.removeAt(preferredIndex));
    }
    final unseen =
        dateProducts.where((item) => !experienced.contains(item['key']));
    final recommended = unseen.isNotEmpty
        ? unseen.first
        : (dateProducts.isNotEmpty ? dateProducts.first : null);
    final visible = _showAll ? items : items.take(4).toList();

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SizedBox(height: 30),
      _Heading('story.timeline'.tr),
      const SizedBox(height: 12),
      if (items.isEmpty)
        Text('story.empty'.tr, style: TextStyle(color: vita.subText))
      else
        for (final item in visible)
          _StoryTile(
            title: _title(item),
            subtitle:
                '${_date(item['occurred_at'])}  ${item['kind'] == 'memory' ? 'story.memory'.tr : item['kind'] == 'first_chat' ? 'story.firstChat'.tr : 'story.event'.tr}',
            description: _storyDescription(item['description']),
            icon: item['kind'] == 'memory'
                ? Icons.bookmark_outline_rounded
                : item['kind'] == 'first_chat'
                    ? Icons.chat_bubble_outline_rounded
                    : Icons.auto_stories_outlined,
            onTap: () => _openItem(item),
          ),
      if (items.length > 4)
        TextButton(
          onPressed: () => setState(() => _showAll = !_showAll),
          child: Text(_showAll ? 'story.showLess'.tr : 'story.showAll'.tr),
        ),
      if (events.isNotEmpty) ...[
        const SizedBox(height: 22),
        _Heading('story.recent'.tr),
        const SizedBox(height: 6),
        Text('story.recentSource'.tr,
            style: TextStyle(color: vita.subText, fontSize: 12)),
        const SizedBox(height: 12),
        for (final event in events)
          _StoryTile(
            title: _title(event),
            subtitle: _date(event['occurred_at']),
            description: _storyDescription(event['description']),
            icon: Icons.bolt_rounded,
            onTap: () => _openItem(event),
          ),
      ],
      if (memories.isNotEmpty) ...[
        const SizedBox(height: 22),
        _Heading('story.keepsakes'.tr),
        const SizedBox(height: 12),
        for (final memory in memories.take(3))
          _StoryTile(
            title: memory['is_favorite'] == true
                ? 'story.favorite'.tr
                : 'story.memory'.tr,
            subtitle: _date(memory['occurred_at']),
            description: _storyDescription(memory['description']),
            icon: memory['is_favorite'] == true
                ? Icons.bookmark_rounded
                : Icons.bookmark_outline_rounded,
            onTap: () => _editMemory(memory),
          ),
      ],
      if (recommended != null) ...[
        const SizedBox(height: 22),
        _Heading('story.invitation'.tr),
        const SizedBox(height: 12),
        Material(
          color: vita.greenTint,
          borderRadius: BorderRadius.circular(18),
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: () async {
              await widget.onExperience('${recommended['key']}');
              await _load();
            },
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Row(children: [
                Text('${recommended['emoji'] ?? '✨'}',
                    style: const TextStyle(fontSize: 29)),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${recommended['name_key'] ?? ''}'.tr,
                            style: TextStyle(
                                color: vita.text, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 5),
                        Text(
                          events.isNotEmpty
                              ? 'story.invitationAfter'
                                  .trParams({'event': _title(events.first)})
                              : experienced.isEmpty
                                  ? 'story.invitationFirst'.tr
                                  : 'story.invitationNext'.tr,
                          style: TextStyle(
                              color: vita.subText, fontSize: 12, height: 1.4),
                        ),
                      ]),
                ),
                Icon(Icons.arrow_outward_rounded, color: vita.green),
              ]),
            ),
          ),
        ),
      ],
    ]);
  }
}

class _MemoryEditorSheet extends StatefulWidget {
  const _MemoryEditorSheet({
    required this.companionId,
    required this.memory,
  });

  final String companionId;
  final Map<String, dynamic> memory;

  @override
  State<_MemoryEditorSheet> createState() => _MemoryEditorSheetState();
}

class _MemoryEditorSheetState extends State<_MemoryEditorSheet> {
  late final TextEditingController _controller;
  bool _working = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: _storyDescription(widget.memory['description']),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _perform(Future<void> Function() action) async {
    if (_working) return;
    setState(() => _working = true);
    try {
      await action();
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (error) {
      VitaNotice.error('story.memory'.tr, error.message);
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('story.delete'.tr),
        content: Text('story.deleteConfirm'.tr),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text('common.cancel'.tr),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text('story.delete'.tr),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _perform(() async {
      await ApiClient.instance.delete(
        '/v1/companions/${widget.companionId}/memories/${widget.memory['id']}',
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final favorite = widget.memory['is_favorite'] == true;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        20,
        10,
        20,
        20 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text('story.memory'.tr,
            style: TextStyle(
                color: context.vita.text,
                fontSize: 18,
                fontWeight: FontWeight.w700)),
        const SizedBox(height: 14),
        TextField(
          controller: _controller,
          maxLines: 4,
          maxLength: 500,
          decoration: InputDecoration(hintText: 'story.editHint'.tr),
        ),
        const SizedBox(height: 8),
        Row(children: [
          IconButton(
            tooltip: favorite ? 'story.unfavorite'.tr : 'story.favorite'.tr,
            icon: Icon(favorite
                ? Icons.bookmark_rounded
                : Icons.bookmark_outline_rounded),
            onPressed: _working
                ? null
                : () => _perform(() async {
                      await ApiClient.instance.put(
                        '/v1/companions/${widget.companionId}/memories/${widget.memory['id']}/favorite',
                        data: {'favorite': !favorite},
                      );
                    }),
          ),
          IconButton(
            tooltip: 'story.delete'.tr,
            icon: const Icon(Icons.delete_outline_rounded),
            onPressed: _working ? null : _delete,
          ),
          const Spacer(),
          FilledButton(
            onPressed: _working
                ? null
                : () {
                    final content = _controller.text.trim();
                    if (content.isEmpty ||
                        content ==
                            _storyDescription(widget.memory['description'])) {
                      return;
                    }
                    _perform(() async {
                      await ApiClient.instance.put(
                        '/v1/companions/${widget.companionId}/memories/${widget.memory['id']}',
                        data: {'content': content},
                      );
                    });
                  },
            child: Text('story.save'.tr),
          ),
        ]),
      ]),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.title);
  final String title;

  @override
  Widget build(BuildContext context) => Text(title,
      style: TextStyle(
          color: context.vita.text, fontSize: 17, fontWeight: FontWeight.w700));
}

class _StoryTile extends StatelessWidget {
  const _StoryTile({
    required this.title,
    required this.subtitle,
    required this.description,
    required this.icon,
    required this.onTap,
  });
  final String title;
  final String subtitle;
  final String description;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final vita = context.vita;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: vita.surface,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(15),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(icon, color: vita.green, size: 19),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: TextStyle(
                              color: vita.text, fontWeight: FontWeight.w600)),
                      if (description.trim().isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(description,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: vita.subText,
                                fontSize: 13,
                                height: 1.4)),
                      ],
                      const SizedBox(height: 6),
                      Text(subtitle,
                          style: TextStyle(color: vita.hint, fontSize: 11)),
                    ]),
              ),
              Icon(Icons.chevron_right_rounded, color: vita.hint, size: 18),
            ]),
          ),
        ),
      ),
    );
  }
}
