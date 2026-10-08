import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/api_client.dart';
import '../../core/theme.dart';
import '../../shared/widgets.dart';
import 'chat_controller.dart';

/// The purchased date is a live conversation during its scheduled window.
/// Both sides' lines and their shared keepsake remain available afterward.
class CompanionMomentPage extends StatefulWidget {
  const CompanionMomentPage(
      {super.key,
      required this.companionId,
      required this.eventId,
      required this.name,
      this.controller,
      this.avatarUrl});

  final String companionId;
  final String eventId;
  final String name;
  final String? avatarUrl;
  final ChatController? controller;

  @override
  State<CompanionMomentPage> createState() => _CompanionMomentPageState();
}

class _CompanionMomentPageState extends State<CompanionMomentPage> {
  final _message = TextEditingController();
  final _artifact = TextEditingController();
  Map<String, dynamic>? _moment;
  Timer? _timer;
  bool _loading = true;
  bool _starting = false;
  bool _saving = false;
  bool _sending = false;
  bool _artifactDirty = false;
  late final ChatController _chat;
  bool _ownsChat = false;
  late final String _chatTag;

  @override
  void initState() {
    super.initState();
    _chatTag = 'moment-${widget.eventId}-${identityHashCode(this)}';
    _ownsChat = widget.controller == null;
    _chat = widget.controller ??
        Get.put(
            ChatController(
                companionId: widget.companionId, companionName: widget.name),
            tag: _chatTag);
    _load();
    _timer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (!mounted) return;
      setState(() {});
      _chat.poll();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _message.dispose();
    _artifact.dispose();
    if (_ownsChat) Get.delete<ChatController>(tag: _chatTag);
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final data = await ApiClient.instance.get(
          '/v1/companions/${widget.companionId}/moments/${widget.eventId}');
      if (!mounted || data is! Map) return;
      final moment = Map<String, dynamic>.from(data);
      if (!_artifactDirty) _artifact.text = '${moment['user_text'] ?? ''}';
      setState(() {
        _moment = moment;
        _loading = false;
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _loading = false);
      Get.snackbar('experience.failed'.tr, error.message);
    }
  }

  DateTime? _time(String key) =>
      DateTime.tryParse('${_moment?[key] ?? ''}')?.toLocal();
  bool get _scheduled => _time('starts_at')?.isAfter(DateTime.now()) ?? false;
  bool get _ended => _time('ends_at')?.isBefore(DateTime.now()) ?? false;
  bool get _active => !_scheduled && !_ended && _moment != null;
  bool get _started => '${_moment?['opening'] ?? ''}'.isNotEmpty;

  Future<void> _start() async {
    if (_starting) return;
    setState(() => _starting = true);
    try {
      final data = await ApiClient.instance.post(
          '/v1/companions/${widget.companionId}/moments/${widget.eventId}/start');
      if (!mounted || data is! Map) return;
      setState(() => _moment = Map<String, dynamic>.from(data));
      await _chat.poll();
    } on ApiException catch (error) {
      Get.snackbar('experience.failed'.tr, error.message);
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  Future<void> _send() async {
    final text = _message.text.trim();
    if (text.isEmpty || _sending || !_active || !_started) return;
    setState(() => _sending = true);
    final queued = await _chat.send(text, momentEventId: widget.eventId);
    if (mounted) {
      if (queued) _message.clear();
      setState(() => _sending = false);
      if (!queued)
        Get.snackbar('experience.failed'.tr,
            _chat.sendError.value ?? 'experience.failed'.tr);
    }
  }

  Future<void> _saveArtifact() async {
    final content = _artifact.text.trim();
    if (content.isEmpty || _saving || !_started) return;
    setState(() => _saving = true);
    try {
      final data = await ApiClient.instance.put(
          '/v1/companions/${widget.companionId}/moments/${widget.eventId}/artifact',
          data: {'text': content});
      if (!mounted || data is! Map) return;
      setState(() {
        _moment = {...?_moment, ...Map<String, dynamic>.from(data)};
        _artifactDirty = false;
      });
    } on ApiException catch (error) {
      Get.snackbar('experience.failed'.tr, error.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _scene(BuildContext context, String title, String location) {
    final vita = context.vita;
    final accent = switch (location) {
      'cafe' => const Color(0xFFD4A57B),
      'cinema' => const Color(0xFF7772B8),
      'restaurant' => const Color(0xFFC47F78),
      _ => vita.green,
    };
    final icon = switch (location) {
      'cafe' => Icons.local_cafe_outlined,
      'cinema' => Icons.movie_outlined,
      'restaurant' => Icons.restaurant_outlined,
      _ => Icons.auto_awesome_outlined,
    };
    return Container(
      height: 166,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [accent.withValues(alpha: .83), accent],
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Stack(children: [
          Positioned(
              right: -20,
              top: -40,
              child: Container(
                  width: 180,
                  height: 180,
                  decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withValues(alpha: .10)))),
          Positioned(
              right: 26,
              top: 27,
              child: Icon(icon,
                  size: 96, color: Colors.white.withValues(alpha: .24))),
          Positioned(
            left: 20,
            right: 20,
            bottom: 22,
            child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Expanded(
                  child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.name,
                      style: TextStyle(
                          fontSize: 13,
                          color: Colors.white.withValues(alpha: .85))),
                  const SizedBox(height: 5),
                  Text(title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                          color: Colors.white)),
                ],
              )),
              const SizedBox(width: 12),
              VitaAvatar(
                  name: widget.name,
                  radius: 27,
                  imageUrl: widget.avatarUrl,
                  background: Colors.white.withValues(alpha: .22),
                  textColor: Colors.white),
            ]),
          ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final vita = context.vita;
    final title = '${_moment?['title_key'] ?? ''}'.tr;
    final location = '${_moment?['location'] ?? ''}';
    final locationLabel = switch (location) {
      'cafe' => 'world.place.cafe'.tr,
      'cinema' => 'moment.place.cinema'.tr,
      'restaurant' => 'moment.place.restaurant'.tr,
      _ => location,
    };
    return Scaffold(
      backgroundColor: vita.pageBg,
      appBar: AppBar(leading: const VitaBackButton(), title: Text(widget.name)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _moment == null
              ? Center(child: Text('experience.failed'.tr))
              : SafeArea(
                  child: Column(children: [
                  Expanded(
                      child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
                    children: [
                      _scene(context, title, location),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(22),
                        decoration: BoxDecoration(
                          color: vita.surface,
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: vita.divider),
                        ),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('${_moment?['description_key'] ?? ''}'.tr,
                                  style: TextStyle(
                                      color: vita.subText, height: 1.45)),
                              if (location.isNotEmpty) ...[
                                const SizedBox(height: 12),
                                Text(locationLabel,
                                    style: TextStyle(color: vita.green)),
                              ],
                              const SizedBox(height: 14),
                              Text(
                                  _scheduled
                                      ? 'moment.scheduled'.trParams({
                                          'time':
                                              MaterialLocalizations.of(context)
                                                      .formatMediumDate(
                                                          _time('starts_at')!) +
                                                  ' ' +
                                                  TimeOfDay.fromDateTime(
                                                          _time('starts_at')!)
                                                      .format(context)
                                        })
                                      : _ended
                                          ? 'moment.ended'.tr
                                          : 'moment.live'.tr,
                                  style: TextStyle(
                                      color: vita.subText, fontSize: 13)),
                              if (_active && !_started) ...[
                                const SizedBox(height: 16),
                                SizedBox(
                                    width: double.infinity,
                                    child: ElevatedButton(
                                      onPressed: _starting ? null : _start,
                                      child: Text(_starting
                                          ? 'moment.starting'.tr
                                          : 'moment.start'.tr),
                                    )),
                              ],
                            ]),
                      ),
                      if (_started) ...[
                        const SizedBox(height: 26),
                        Text('moment.together'.tr,
                            style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                                color: vita.text)),
                        const SizedBox(height: 12),
                        Obx(() {
                          final lines = _chat.messages
                              .where((m) =>
                                  m['life_event_id'] == widget.eventId &&
                                  (m['message_type'] == 'text' ||
                                      m['message_type'] == 'voice' ||
                                      m['source'] == 'moment_opening'))
                              .toList();
                          if (lines.isEmpty) {
                            return Text('${_moment?['opening'] ?? ''}',
                                style:
                                    TextStyle(color: vita.text, height: 1.5));
                          }
                          return Column(
                              children: lines.map((m) {
                            final isUser = m['sender_type'] == 'user';
                            return Align(
                              alignment: isUser
                                  ? Alignment.centerRight
                                  : Alignment.centerLeft,
                              child: Container(
                                margin: const EdgeInsets.only(bottom: 10),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 12),
                                constraints: BoxConstraints(
                                    maxWidth:
                                        MediaQuery.of(context).size.width *
                                            .78),
                                decoration: BoxDecoration(
                                  color: isUser ? vita.greenTint : vita.surface,
                                  borderRadius: BorderRadius.circular(18),
                                ),
                                child: Text('${m['content'] ?? ''}',
                                    style: TextStyle(
                                        color: vita.text, height: 1.4)),
                              ),
                            );
                          }).toList());
                        }),
                        const SizedBox(height: 20),
                        Text('moment.create'.tr,
                            style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                                color: vita.text)),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _artifact,
                          maxLines: 3,
                          onChanged: (_) => _artifactDirty = true,
                          decoration: InputDecoration(
                            hintText: 'moment.createHint'.tr,
                            filled: true,
                            fillColor: vita.surface,
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16),
                                borderSide: BorderSide(color: vita.divider)),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                                onPressed: _saving ? null : _saveArtifact,
                                child: Text(_saving
                                    ? 'moment.saving'.tr
                                    : 'moment.save'.tr))),
                        if ('${_moment?['companion_text'] ?? ''}'.isNotEmpty)
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                                color: vita.greenTint,
                                borderRadius: BorderRadius.circular(16)),
                            child: Text(
                                '${widget.name}: ${_moment?['companion_text']}',
                                style:
                                    TextStyle(color: vita.text, height: 1.45)),
                          ),
                      ],
                    ],
                  )),
                  if (_active && _started)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                      child: Row(children: [
                        Expanded(
                            child: TextField(
                          controller: _message,
                          decoration: InputDecoration(
                              hintText: 'moment.messageHint'.tr,
                              filled: true,
                              fillColor: vita.surface,
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(20),
                                  borderSide: BorderSide(color: vita.divider))),
                          onSubmitted: (_) => _send(),
                        )),
                        const SizedBox(width: 8),
                        IconButton.filled(
                            onPressed: _sending ? null : _send,
                            icon: const Icon(Icons.arrow_upward_rounded)),
                      ]),
                    ),
                ])),
    );
  }
}
