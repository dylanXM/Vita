import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/notice.dart';
import '../../core/api_client.dart';
import '../../core/theme.dart';
import '../../shared/media_image.dart';
import '../../shared/widgets.dart';
import 'chat_controller.dart';
import 'chat_page.dart';

enum _MomentPhase { booked, ready, together, keepsake }

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
  Timer? _countdownTimer;
  final _clock = ValueNotifier<DateTime>(DateTime.now());
  bool _loading = true;
  bool _starting = false;
  bool _saving = false;
  bool _sending = false;
  bool _artifactDirty = false;
  bool _preparing = false;
  bool _finishing = false;
  bool _finishFailed = false;
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
      if (mounted && _started && !_ended) _chat.poll();
    });
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final previous = _clock.value;
      final now = DateTime.now();
      _clock.value = now;
      final startsAt = _time('starts_at');
      final endsAt = _time('ends_at');
      if ((startsAt != null &&
              previous.isBefore(startsAt) &&
              !now.isBefore(startsAt)) ||
          (endsAt != null &&
              _started &&
              previous.isBefore(endsAt) &&
              !now.isBefore(endsAt))) {
        setState(() {});
        if (_ended) _finish();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _countdownTimer?.cancel();
    _clock.dispose();
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
      if (_ended && '${moment['closing'] ?? ''}'.isEmpty) _finish();
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _loading = false);
      VitaNotice.error('experience.failed'.tr, error.message);
    }
  }

  DateTime? _time(String key) =>
      DateTime.tryParse('${_moment?[key] ?? ''}')?.toLocal();
  bool get _scheduled => _time('starts_at')?.isAfter(DateTime.now()) ?? false;
  bool get _ended =>
      _started && (_time('ends_at')?.isBefore(DateTime.now()) ?? false);
  bool get _active => !_scheduled && !_ended && _moment != null;
  bool get _started => '${_moment?['opening'] ?? ''}'.isNotEmpty;
  _MomentPhase get _phase {
    if (_started) return _ended ? _MomentPhase.keepsake : _MomentPhase.together;
    return _scheduled ? _MomentPhase.booked : _MomentPhase.ready;
  }

  String _remaining(DateTime? until, DateTime now) {
    if (until == null) return '00:00:00';
    final left = until.difference(now);
    final seconds = left.inSeconds.clamp(0, 30 * 24 * 3600);
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    final last = seconds % 60;
    return '${hours.toString().padLeft(2, '0')}:'
        '${minutes.toString().padLeft(2, '0')}:'
        '${last.toString().padLeft(2, '0')}';
  }

  Widget _journey(BuildContext context) {
    final vita = context.vita;
    final phase = _phase;
    final labels = [
      'moment.phase.booked'.tr,
      'moment.phase.ready'.tr,
      'moment.phase.together'.tr,
      'moment.phase.keepsake'.tr,
    ];
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 17, 16, 18),
      decoration: BoxDecoration(
        color: vita.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: vita.divider),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          for (var index = 0; index < labels.length; index++)
            Expanded(
              child: Column(children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  width: index == phase.index ? 13 : 9,
                  height: index == phase.index ? 13 : 9,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: index <= phase.index ? vita.green : vita.divider,
                  ),
                ),
                const SizedBox(height: 9),
                Text(labels[index],
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: index == phase.index ? vita.text : vita.subText,
                      fontSize: 11,
                      fontWeight: index == phase.index
                          ? FontWeight.w700
                          : FontWeight.w400,
                    )),
              ]),
            ),
        ]),
        const SizedBox(height: 15),
        ValueListenableBuilder<DateTime>(
          valueListenable: _clock,
          builder: (context, now, _) {
            final detail = switch (phase) {
              _MomentPhase.booked => 'moment.waitingFor'.trParams({
                  'time': _remaining(_time('starts_at'), now),
                }),
              _MomentPhase.ready => 'moment.readyHint'.tr,
              _MomentPhase.together => 'moment.timeLeft'.trParams({
                  'time': _remaining(_time('ends_at'), now),
                }),
              _MomentPhase.keepsake => '${_moment?['artifact'] ?? ''}'.isEmpty
                  ? 'moment.endCreateHint'.tr
                  : 'moment.endedHint'.tr,
            };
            return Text(detail,
                style: TextStyle(color: vita.text, fontSize: 15, height: 1.4));
          },
        ),
        if (phase == _MomentPhase.booked && _time('starts_at') != null) ...[
          const SizedBox(height: 7),
          Text(
            'moment.scheduled'.trParams({
              'time': '${MaterialLocalizations.of(context).formatMediumDate(_time('starts_at')!)} '
                  '${TimeOfDay.fromDateTime(_time('starts_at')!).format(context)}',
            }),
            style: TextStyle(color: vita.subText, fontSize: 12),
          ),
        ],
      ]),
    );
  }

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
      VitaNotice.error('experience.failed'.tr, error.message);
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  Future<void> _prepare(String choice) async {
    if (_preparing ||
        !_scheduled ||
        '${_moment?['preparation'] ?? ''}'.isNotEmpty) {
      return;
    }
    setState(() => _preparing = true);
    try {
      final data = await ApiClient.instance.post(
          '/v1/companions/${widget.companionId}/moments/${widget.eventId}/prepare',
          data: {'choice': choice});
      if (!mounted || data is! Map) return;
      setState(() => _moment = Map<String, dynamic>.from(data));
      await _chat.poll();
    } on ApiException catch (error) {
      VitaNotice.error('experience.failed'.tr, error.message);
    } finally {
      if (mounted) setState(() => _preparing = false);
    }
  }

  Future<void> _finish() async {
    if (_finishing || !_ended || '${_moment?['closing'] ?? ''}'.isNotEmpty) {
      return;
    }
    setState(() {
      _finishing = true;
      _finishFailed = false;
    });
    try {
      final data = await ApiClient.instance.post(
          '/v1/companions/${widget.companionId}/moments/${widget.eventId}/finish');
      if (!mounted || data is! Map) return;
      setState(() => _moment = Map<String, dynamic>.from(data));
    } on ApiException {
      if (mounted) setState(() => _finishFailed = true);
    } finally {
      if (mounted) setState(() => _finishing = false);
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
      if (!queued) {
        VitaNotice.error('experience.failed'.tr,
            _chat.sendError.value ?? 'experience.failed'.tr);
      }
    }
  }

  Future<void> _sendChoice(String text) async {
    if (_sending || text.trim().isEmpty) return;
    _message.text = text;
    await _send();
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
      VitaNotice.error('experience.failed'.tr, error.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _scene(BuildContext context, String title, String location) {
    final vita = context.vita;
    final colors = switch (location) {
      'cafe' => [const Color(0xFF35241F), const Color(0xFFA26E50)],
      'cinema' => [const Color(0xFF191B35), const Color(0xFF64579A)],
      'restaurant' => [const Color(0xFF352128), const Color(0xFF9D5E66)],
      _ => [vita.pageBg, vita.green],
    };
    final icon = switch (location) {
      'cafe' => Icons.local_cafe_outlined,
      'cinema' => Icons.movie_outlined,
      'restaurant' => Icons.restaurant_outlined,
      _ => Icons.auto_awesome_outlined,
    };
    final phase = _phase;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 650),
      height: 212,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: phase == _MomentPhase.together
              ? [colors.first, vita.green.withValues(alpha: .72)]
              : phase == _MomentPhase.keepsake
                  ? [colors.last, colors.first]
                  : colors,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Stack(children: [
          if (widget.avatarUrl?.isNotEmpty == true)
            Positioned.fill(
                child: AnimatedScale(
              duration: const Duration(milliseconds: 700),
              scale: phase == _MomentPhase.together ? 1.08 : 1,
              alignment: Alignment.center,
              child: VitaMediaImage(
                  url: widget.avatarUrl!,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const SizedBox.expand()),
            ))
          else
            Positioned(
                right: 28,
                top: 24,
                child: Icon(icon,
                    size: 116, color: Colors.white.withValues(alpha: .17))),
          Positioned.fill(
              child: DecoratedBox(
                  decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withValues(alpha: .48),
                Colors.black.withValues(alpha: .12),
                Colors.black.withValues(alpha: .65)
              ],
            ),
          ))),
          Positioned(
            left: 20,
            top: 20,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: .20),
                borderRadius: BorderRadius.circular(100),
                border: Border.all(color: Colors.white.withValues(alpha: .16)),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(icon, size: 14, color: Colors.white),
                const SizedBox(width: 6),
                Text(
                    switch (location) {
                      'cafe' => 'world.place.cafe'.tr,
                      'cinema' => 'moment.place.cinema'.tr,
                      'restaurant' => 'moment.place.restaurant'.tr,
                      _ => location,
                    },
                    style: const TextStyle(color: Colors.white, fontSize: 12)),
              ]),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              height: 120,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withValues(alpha: .28)
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            left: 20,
            right: 20,
            bottom: 24,
            child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Expanded(
                  child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.name,
                      style: TextStyle(
                          fontSize: 14,
                          color: Colors.white.withValues(alpha: .85))),
                  const SizedBox(height: 5),
                  Text(title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 30,
                          fontWeight: FontWeight.w700,
                          color: Colors.white)),
                ],
              )),
              const SizedBox(width: 12),
              AnimatedSlide(
                  duration: const Duration(milliseconds: 650),
                  curve: Curves.easeOutCubic,
                  offset: phase == _MomentPhase.together
                      ? const Offset(-.12, -.08)
                      : Offset.zero,
                  child: VitaAvatar(
                      name: widget.name,
                      radius: 32,
                      imageUrl: widget.avatarUrl,
                      background: Colors.white.withValues(alpha: .22),
                      textColor: Colors.white)),
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
                      _journey(context),
                      const SizedBox(height: 12),
                      if (_phase == _MomentPhase.booked) ...[
                        Text('moment.prepareTitle'.tr,
                            style: TextStyle(
                                color: vita.text,
                                fontSize: 17,
                                fontWeight: FontWeight.w700)),
                        const SizedBox(height: 10),
                        if ('${_moment?['preparation'] ?? ''}'.isEmpty) ...[
                          _MomentChoice(
                              icon: Icons.chat_bubble_outline_rounded,
                              label: 'moment.prepareTalk'.tr,
                              detail: 'moment.prepareTalkHint'.tr,
                              onTap:
                                  _preparing ? null : () => _prepare('talk')),
                          const SizedBox(height: 8),
                          _MomentChoice(
                              icon: Icons.auto_awesome_rounded,
                              label: 'moment.prepareSurprise'.tr,
                              detail: 'moment.prepareSurpriseHint'.tr,
                              onTap: _preparing
                                  ? null
                                  : () => _prepare('surprise')),
                        ] else
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 450),
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                                color: vita.greenTint,
                                borderRadius: BorderRadius.circular(18)),
                            child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(Icons.favorite_rounded,
                                      color: vita.green, size: 21),
                                  const SizedBox(width: 12),
                                  Expanded(
                                      child: Text(
                                          '${_moment?['preparation_reaction'] ?? ''}'
                                                  .isEmpty
                                              ? 'moment.prepareReceived'.tr
                                              : '${_moment?['preparation_reaction']}',
                                          style: TextStyle(
                                              color: vita.text,
                                              fontSize: 14,
                                              height: 1.45))),
                                ]),
                          ),
                        const SizedBox(height: 14),
                      ],
                      if ('${_moment?['invitation'] ?? ''}'.isNotEmpty) ...[
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            color: vita.surface,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: vita.divider),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              VitaAvatar(
                                name: widget.name,
                                radius: 20,
                                imageUrl: widget.avatarUrl,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(widget.name,
                                        style: TextStyle(
                                          fontWeight: FontWeight.w700,
                                          color: vita.text,
                                        )),
                                    const SizedBox(height: 5),
                                    Text('${_moment?['invitation']}',
                                        style: TextStyle(
                                          color: vita.text,
                                          fontSize: 15,
                                          height: 1.5,
                                        )),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Text('${_moment?['description_key'] ?? ''}'.tr,
                            style:
                                TextStyle(color: vita.subText, height: 1.45)),
                      ),
                      if (_phase == _MomentPhase.ready) ...[
                        const SizedBox(height: 14),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: _starting ? null : _start,
                            icon: const Icon(Icons.auto_awesome_rounded),
                            label: Text(_starting
                                ? 'moment.starting'.tr
                                : 'moment.start'.tr),
                          ),
                        ),
                      ],
                      if (_phase == _MomentPhase.keepsake &&
                          '${_moment?['artifact'] ?? ''}'.isNotEmpty) ...[
                        const SizedBox(height: 22),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: vita.greenTint,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(children: [
                                Icon(Icons.auto_awesome_rounded,
                                    size: 18, color: vita.green),
                                const SizedBox(width: 8),
                                Text('moment.phase.keepsake'.tr,
                                    style: TextStyle(
                                        color: vita.text,
                                        fontWeight: FontWeight.w700)),
                              ]),
                              const SizedBox(height: 12),
                              Text('${_moment?['artifact']}',
                                  style: TextStyle(
                                      color: vita.text,
                                      fontSize: 16,
                                      height: 1.55)),
                            ],
                          ),
                        ),
                      ],
                      if (_phase == _MomentPhase.keepsake) ...[
                        const SizedBox(height: 16),
                        if ('${_moment?['closing'] ?? ''}'.isNotEmpty)
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                                gradient: LinearGradient(
                                    colors: [vita.greenTint, vita.surface]),
                                borderRadius: BorderRadius.circular(20)),
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('moment.closingTitle'.tr,
                                      style: TextStyle(
                                          color: vita.green,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700)),
                                  const SizedBox(height: 10),
                                  Text('${_moment?['closing']}',
                                      style: TextStyle(
                                          color: vita.text,
                                          fontSize: 16,
                                          height: 1.5)),
                                  if ('${_moment?['next_topic'] ?? ''}'
                                      .isNotEmpty) ...[
                                    const SizedBox(height: 18),
                                    Text('moment.nextTopic'.tr,
                                        style: TextStyle(
                                            color: vita.subText, fontSize: 12)),
                                    const SizedBox(height: 5),
                                    Text('${_moment?['next_topic']}',
                                        style: TextStyle(
                                            color: vita.text,
                                            fontSize: 14,
                                            height: 1.4)),
                                    const SizedBox(height: 14),
                                    TextButton.icon(
                                        onPressed: () {
                                          if (widget.controller != null) {
                                            Get.back();
                                            return;
                                          }
                                          Get.to(
                                              () => ChatPage(
                                                    companionId:
                                                        widget.companionId,
                                                    name: widget.name,
                                                    companion: {
                                                      'id': widget.companionId,
                                                      'name': widget.name,
                                                      'portrait_url':
                                                          widget.avatarUrl,
                                                    },
                                                  ),
                                              transition: Transition.cupertino);
                                        },
                                        icon: const Icon(
                                            Icons.arrow_forward_rounded),
                                        label: Text('moment.continueChat'.tr)),
                                  ],
                                ]),
                          )
                        else if (_finishing)
                          Center(
                              child: Text('moment.finishing'.tr,
                                  style: TextStyle(color: vita.subText)))
                        else if (_finishFailed)
                          TextButton.icon(
                              onPressed: _finish,
                              icon: const Icon(Icons.refresh_rounded),
                              label: Text('moment.finishRetry'.tr)),
                      ],
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
                        if (_phase == _MomentPhase.together)
                          Obx(() {
                            final alreadyChose = _chat.messages.any((m) =>
                                m['life_event_id'] == widget.eventId &&
                                m['sender_type'] == 'user' &&
                                m['message_type'] == 'text');
                            if (alreadyChose) return const SizedBox.shrink();
                            final scene = switch (location) {
                              'cafe' || 'cinema' || 'restaurant' => location,
                              _ => 'general',
                            };
                            return Column(children: [
                              const SizedBox(height: 10),
                              _MomentChoice(
                                  icon: Icons.question_answer_rounded,
                                  label: 'moment.choice.$scene.first'.tr,
                                  detail: 'moment.choiceTalkHint'.tr,
                                  onTap: _sending
                                      ? null
                                      : () => _sendChoice(
                                          'moment.choice.$scene.firstMessage'
                                              .tr)),
                              const SizedBox(height: 8),
                              _MomentChoice(
                                  icon: Icons.auto_awesome_rounded,
                                  label: 'moment.choice.$scene.second'.tr,
                                  detail: 'moment.choiceNoticeHint'.tr,
                                  onTap: _sending
                                      ? null
                                      : () => _sendChoice(
                                          'moment.choice.$scene.secondMessage'
                                              .tr)),
                            ]);
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

class _MomentChoice extends StatelessWidget {
  const _MomentChoice(
      {required this.icon,
      required this.label,
      required this.detail,
      required this.onTap});

  final IconData icon;
  final String label;
  final String detail;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: context.vita.surface,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            height: 72,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: context.vita.divider)),
            child: Row(children: [
              Icon(icon, color: context.vita.green, size: 21),
              const SizedBox(width: 13),
              Expanded(
                  child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: context.vita.text,
                            fontSize: 14,
                            fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text(detail,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: context.vita.subText, fontSize: 12)),
                  ])),
              Icon(Icons.arrow_outward_rounded,
                  color: context.vita.green, size: 17),
            ]),
          ),
        ),
      );
}
