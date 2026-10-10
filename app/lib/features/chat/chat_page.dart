import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:dio/dio.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/notice.dart';
import '../../core/constants.dart';
import '../../core/api_client.dart';
import '../../core/theme.dart';
import '../../shared/media_image.dart';
import '../../shared/widgets.dart';
import '../shell/shell_page.dart';
import 'chat_controller.dart';
import '../auth/auth_controller.dart';
import 'chat_info_page.dart';
import 'chat_message_content.dart';
import 'companion_moment_page.dart';
import 'companion_transfer_sheet.dart';
import 'experience_sheet.dart';
import 'gift_reveal_page.dart';
import 'gift_visual.dart';

/// Conversation within a companion's world.
class ChatPage extends StatefulWidget {
  const ChatPage(
      {super.key,
      required this.companionId,
      required this.name,
      this.companion,
      this.journeyVisitId,
      this.journeyContext,
      this.journeyDraft});

  final String companionId;
  final String name;

  /// Full companion profile map (from the list) — shown in the "more" sheet.
  final Map<String, dynamic>? companion;
  final String? journeyVisitId;
  final String? journeyContext;
  final String? journeyDraft;

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  static const _messageEmojis = <String>[
    '😊',
    '😂',
    '🥰',
    '😍',
    '🥹',
    '😢',
    '😭',
    '😡',
    '😳',
    '🤔',
    '😏',
    '😴',
    '🤗',
    '🫡',
    '🥳',
    '😎',
    '👍',
    '👏',
    '🙌',
    '🤝',
    '🙏',
    '💪',
    '👋',
    '🫶',
    '❤️',
    '🩷',
    '💕',
    '✨',
    '🎉',
    '🌟',
    '🔥',
    '🌸',
  ];

  late final ChatController ctrl = Get.put(
    ChatController(companionId: widget.companionId, companionName: widget.name),
    tag: widget.companionId,
  );
  final _input = TextEditingController();
  final _scroll = ScrollController();
  int _scrollRequest = 0;
  final _recorder = AudioRecorder();
  final _player = AudioPlayer();
  late final Worker _messageWorker;
  late final Worker _replyStatusWorker;
  String _previousReplyStatus = 'none';
  Timer? _slowReplyTimer;
  static const _slowReplyThreshold = Duration(seconds: 200);
  static final Set<String> _notifiedSlowReplies = <String>{};
  Timer? _recordingTimer;
  bool _recording = false;
  bool _journeyContextSent = false;
  String? _lifeEventContextId;
  String? _lifeEventContextTitle;
  final ValueNotifier<String?> _panel = ValueNotifier(null);
  static const double _panelHeight = 210;

  @override
  void initState() {
    super.initState();
    if (widget.journeyDraft case final draft?) {
      _input.text = draft;
      _input.selection = TextSelection.collapsed(offset: draft.length);
    }
    _messageWorker = ever(ctrl.messages, (_) {
      if (!mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    });
    _replyStatusWorker = ever(ctrl.replyStatus, (status) {
      if (!mounted) return;
      _slowReplyTimer?.cancel();
      if (status == 'pending' || status == 'processing') {
        _scheduleSlowReplyNotice();
      }
      if (status == 'failed' &&
          (ctrl.sending.value ||
              _previousReplyStatus == 'pending' ||
              _previousReplyStatus == 'processing')) {
        VitaNotice.info('chat.message'.tr, 'chat.replyFailed'.tr);
      }
      _previousReplyStatus = status;
    });
    if (widget.companion?['friendship_active'] == false) {
      ctrl.accessError.value = 'friendship_inactive';
    }
  }

  @override
  void dispose() {
    _recorder.dispose();
    _player.dispose();
    _messageWorker.dispose();
    _replyStatusWorker.dispose();
    _slowReplyTimer?.cancel();
    _recordingTimer?.cancel();
    _input.dispose();
    _scroll.dispose();
    _panel.dispose();
    Get.delete<ChatController>(tag: widget.companionId);
    super.dispose();
  }

  Future<void> _toggleRecording() async {
    if (_recording) {
      _recordingTimer?.cancel();
      final path = await _recorder.stop();
      if (mounted) setState(() => _recording = false);
      if (path != null) {
        final queued = await ctrl.sendVoice(path);
        if (mounted) _reportSendResult(queued);
      }
      return;
    }
    if (!await _recorder.hasPermission()) return;
    final directory = await getTemporaryDirectory();
    final path =
        '${directory.path}/vita_voice_${DateTime.now().microsecondsSinceEpoch}.m4a';
    await _recorder.start(
        const RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 64000),
        path: path);
    if (mounted) setState(() => _recording = true);
    _recordingTimer = Timer(const Duration(seconds: 60), () {
      if (_recording && mounted) _toggleRecording();
    });
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
        '${directory.path}/vita_audio_${Uri.parse(resolved).pathSegments.last}.m4a',
      );
      await file.writeAsBytes(bytes, flush: true);
      await _player.play(DeviceFileSource(file.path));
      return;
    }
    await _player.play(UrlSource(resolved));
  }

  Future<void> _send() async {
    if (ctrl.accessError.value != null) {
      Get.toNamed('/subscription');
      return;
    }
    final text = _input.text.trim();
    if (text.isEmpty) return;
    _input.clear();
    final send = ctrl.send(text,
        journeyVisitId: _journeyContextSent ? null : widget.journeyVisitId,
        lifeEventContextId: _lifeEventContextId);
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    final queued = await send;
    if (!mounted) return;
    // Nothing reached the conversation: put the draft back so it is not lost.
    if (!queued) _restoreDraft(text);
    if (queued && ctrl.sendError.value == null) {
      _journeyContextSent = true;
      setState(() {
        _lifeEventContextId = null;
        _lifeEventContextTitle = null;
      });
    }
    _reportSendResult(queued);
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
  }

  /// Puts [text] back in the input when a send could not even be queued. Never
  /// overwrites something the user typed in the meantime.
  void _restoreDraft(String text) {
    if (_input.text.isNotEmpty) return;
    _input.text = text;
    _input.selection = TextSelection.collapsed(offset: text.length);
  }

  Future<void> _openLifeEvent(Map<String, dynamic> message) async {
    final eventId = '${message['life_event_id'] ?? ''}';
    final payload = message['payload'] is Map
        ? Map<String, dynamic>.from(message['payload'] as Map)
        : const <String, dynamic>{};
    final selected = await showModalBottomSheet<Map<String, String>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: context.vita.surface,
      builder: (_) => _LifeEventSheet(
        companionId: widget.companionId,
        eventId: eventId,
        fallback: payload,
      ),
    );
    if (!mounted || selected == null) return;
    final title = selected['title'] ?? '';
    setState(() {
      _lifeEventContextId =
          (selected['event_id'] ?? '').isEmpty ? null : selected['event_id'];
      _lifeEventContextTitle = title;
    });
    if (_input.text.trim().isEmpty) {
      _input.text = 'chat.event.prompt'.trParams({'title': title});
      _input.selection = TextSelection.collapsed(offset: _input.text.length);
    }
  }

  /// True while the IME is composing (e.g. pinyin candidates), when Enter
  /// should confirm the composition instead of sending.
  bool _isComposing() {
    final composing = _input.value.composing;
    return composing.isValid && composing.end > composing.start;
  }

  /// Sends on Enter (desktop); Shift+Enter keeps inserting a line break.
  KeyEventResult _onInputKey(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.enter &&
        !HardwareKeyboard.instance.isShiftPressed &&
        !_isComposing()) {
      _send();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// Reports a send that did not go through: either nothing was queued (the
  /// draft is kept) or the queued message failed to deliver (it is already
  /// visible as a failed bubble in the list).
  void _reportSendResult(bool queued) {
    final reason = ctrl.sendError.value;
    if (!queued) {
      VitaNotice.error('chat.message'.tr, 'chat.sendFailed'.tr);
    } else if (reason != null && reason.isNotEmpty) {
      VitaNotice.error('chat.message'.tr, reason);
    }
  }

  void _scheduleSlowReplyNotice() {
    final messageId = ctrl.replyPendingMessageId;
    if (messageId == null || _notifiedSlowReplies.contains(messageId)) return;
    final remaining =
        _slowReplyThreshold - Duration(seconds: ctrl.replyPendingAgeSeconds);
    _slowReplyTimer =
        Timer(remaining > Duration.zero ? remaining : Duration.zero, () async {
      if (!await ctrl.refreshReplyStatus() ||
          !mounted ||
          ctrl.replyPendingMessageId != messageId ||
          (ctrl.replyStatus.value != 'pending' &&
              ctrl.replyStatus.value != 'processing') ||
          !_notifiedSlowReplies.add(messageId)) {
        return;
      }
      VitaNotice.info('chat.message'.tr, 'chat.replyPending'.tr);
    });
  }

  Future<void> _scrollToBottom() async {
    final request = ++_scrollRequest;
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted || !_scroll.hasClients || request != _scrollRequest) return;
    try {
      await _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    } catch (_) {
      // The page can close while the scroll animation is in flight.
      return;
    }
    // Long bubbles can change the list extent while the animation is running.
    // Correct the final position after layout, without overriding a user drag.
    for (var pass = 0; pass < 3; pass++) {
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted || !_scroll.hasClients || request != _scrollRequest) return;
      final remaining =
          _scroll.position.maxScrollExtent - _scroll.position.pixels;
      if (remaining <= 1) return;
      _scroll.jumpTo(_scroll.position.maxScrollExtent);
    }
  }

  void _insertEmoji(String emoji) {
    final selection = _input.selection;
    final start = selection.isValid ? selection.start : _input.text.length;
    final end = selection.isValid ? selection.end : _input.text.length;
    final updated = _input.text.replaceRange(start, end, emoji);
    _input.value = TextEditingValue(
      text: updated,
      selection: TextSelection.collapsed(offset: start + emoji.length),
    );
  }

  Widget _buildEmojiPanel() {
    return Container(
      color: context.vita.pageBg,
      height: _panelHeight,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: GridView.builder(
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 8,
          mainAxisSpacing: 4,
          crossAxisSpacing: 4,
        ),
        itemCount: _messageEmojis.length,
        itemBuilder: (_, index) {
          final emoji = _messageEmojis[index];
          return InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => _insertEmoji(emoji),
            child: Center(
                child: Text(emoji, style: const TextStyle(fontSize: 26))),
          );
        },
      ),
    );
  }

  Future<void> _openChatInfo() async {
    final companion = Map<String, dynamic>.from(
      widget.companion ??
          <String, dynamic>{'id': widget.companionId, 'name': widget.name},
    );
    final deleted = await Get.to<bool>(
      () => ChatInfoPage(
        companion: companion,
        onExperienceCompleted: ctrl.poll,
        onExperienceResult: ctrl.experienceCompleted,
      ),
      transition: Transition.cupertino,
      duration: const Duration(milliseconds: 300),
    );
    if (deleted == true) Get.back(result: true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.vita.pageBg,
      appBar: AppBar(
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new,
              size: 20, color: context.vita.text),
          onPressed: () => Get.back(),
        ),
        title: Text(widget.name),
        actions: [
          IconButton(
            icon: Icon(Icons.more_horiz, color: context.vita.subText),
            onPressed: _openChatInfo,
          ),
        ],
      ),
      body: Column(
        children: [
          Obx(() {
            final status = ctrl.trialStatus.value;
            if (status != 'not_started' && status != 'active') {
              return const SizedBox.shrink();
            }
            final expiry =
                DateTime.tryParse(ctrl.trialExpiresAt.value ?? '')?.toLocal();
            final message = status == 'not_started' || expiry == null
                ? 'chat.trialNotStarted'.tr
                : 'chat.trialUntil'.trParams({
                    'time': '${formatDate(expiry)} ${formatClock(expiry)}',
                  });
            return Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
              color: context.vita.greenTint,
              child: Row(children: [
                Icon(Icons.schedule_rounded,
                    size: 17, color: context.vita.green),
                const SizedBox(width: 9),
                Expanded(
                    child: Text(message,
                        style:
                            TextStyle(fontSize: 12, color: context.vita.text))),
              ]),
            );
          }),
          Obx(() => ctrl.accessError.value == null
              ? const SizedBox.shrink()
              : Container(
                  width: double.infinity,
                  color: context.vita.greenTint,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: Row(children: [
                    Expanded(
                        child: Text(
                      ctrl.accessError.value == 'friendship_inactive'
                          ? 'chat.notFriendsDetail'.tr
                          : 'chat.trialExpired'.tr,
                      style: TextStyle(fontSize: 13, color: context.vita.text),
                    )),
                    TextButton(
                        onPressed: () => Get.toNamed('/subscription'),
                        child: Text('subscription.continue'.tr)),
                  ]),
                )),
          if (widget.journeyVisitId != null)
            SizedBox(
              height: 42,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: Row(children: [
                  Icon(Icons.history_rounded,
                      size: 16, color: context.vita.subText),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.journeyContext ?? 'journey.visitMoment'.tr,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          TextStyle(color: context.vita.subText, fontSize: 12),
                    ),
                  ),
                ]),
              ),
            ),
          Expanded(
            child: Obx(
              () => _buildMessages(ctrl),
            ),
          ),
          SafeArea(
            top: false,
            child: ValueListenableBuilder<String?>(
              valueListenable: _panel,
              builder: (context, panel, _) {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_lifeEventContextId != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(14, 0, 14, 6),
                        child: Row(children: [
                          Icon(Icons.auto_stories_outlined,
                              size: 16, color: context.vita.green),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(_lifeEventContextTitle ?? '',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    color: context.vita.subText, fontSize: 12)),
                          ),
                          IconButton(
                            onPressed: () => setState(() {
                              _lifeEventContextId = null;
                              _lifeEventContextTitle = null;
                            }),
                            icon: const Icon(Icons.close_rounded, size: 17),
                            tooltip: 'common.cancel'.tr,
                          ),
                        ]),
                      ),
                    Obx(() => _buildInputBar(
                        locked: ctrl.accessError.value != null, panel: panel)),
                    if (panel == 'emoji') _buildEmojiPanel(),
                    if (panel == 'more') _buildMorePanel(),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessages(ChatController ctrl) {
    if (ctrl.loading.value && ctrl.messages.isEmpty) {
      return const Center(
          child: VitaSkeleton(width: 220, height: 44, radius: 14));
    }
    if (ctrl.messages.isEmpty) {
      return VitaEmpty(
        icon: Icons.chat_bubble_outline,
        title: 'chat.sayHello'.tr,
        subtitle: 'chat.sayHelloSub'.tr,
      );
    }

    // Flatten messages with date separators and per-group timestamps.
    final items = <Widget>[];
    Map<String, dynamic>? latestCompanionReply;
    for (final message in ctrl.messages.reversed) {
      if (message['sender_type'] == 'assistant' &&
          message['source'] == 'reply') {
        latestCompanionReply = message;
        break;
      }
    }
    DateTime? prevDate;
    for (var i = 0; i < ctrl.messages.length; i++) {
      final m = ctrl.messages[i];
      final dt =
          DateTime.tryParse(m['created_at'] as String? ?? '') ?? DateTime.now();
      if (prevDate == null || !isSameDay(dt, prevDate)) {
        items.add(VitaDateChip(label: formatDateSeparator(dt)));
      } else {
        final prev = ctrl.messages[i - 1];
        final prevDt =
            DateTime.tryParse(prev['created_at'] as String? ?? '') ?? dt;
        final sameSender = _isUserMessage(prev) == _isUserMessage(m);
        final closeInTime = dt.difference(prevDt) < const Duration(minutes: 10);
        if (!sameSender || !closeInTime) {
          items.add(Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(formatClock(dt),
                  style:
                      const TextStyle(fontSize: 11, color: Color(0xFF999999))),
            ),
          ));
        }
      }
      prevDate = dt;

      final isUser = _isUserMessage(m);
      final payload = m['payload'] is Map ? m['payload'] as Map : const {};
      final liveReply = m['id'] == latestCompanionReply?['id'] &&
          payload['interaction_stage'] == 'chat';
      final parsed = ChatMessageContent.from(m);
      final isGift = parsed.isGift;
      final isTransfer = parsed.type == 'transfer';
      final isSceneCard =
          parsed.type == 'scene_card' && parsed.payload['event_id'] is String;
      final deliveryStatus = m['delivery_status'] as String? ?? 'delivered';
      final bubbleColor = isGift
          ? Colors.transparent
          : isUser
              ? context.vita.greenTint
              : liveReply
                  ? context.vita.greenTint
                  : context.vita.surface;
      items.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            mainAxisAlignment:
                isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!isUser) ...[
                liveReply
                    ? _CompanionGestureAvatar(
                        name: widget.name,
                        imageUrl: widget.companion?['portrait_url'] as String?,
                        gesture: '${payload['gesture'] ?? 'smile'}')
                    : VitaAvatar(
                        name: widget.name,
                        radius: 22,
                        imageUrl: widget.companion?['portrait_url'] as String?,
                        borderRadius: BorderRadius.circular(10)),
                const SizedBox(width: 8),
              ],
              Flexible(
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 400),
                      constraints: BoxConstraints(
                        maxWidth: MediaQuery.of(context).size.width *
                            (isGift || isTransfer || isSceneCard ? 0.75 : 0.66),
                      ),
                      padding: isGift || isTransfer || isSceneCard
                          ? EdgeInsets.zero
                          : const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 10),
                      decoration: isGift || isTransfer || isSceneCard
                          ? null
                          : BoxDecoration(
                              color: bubbleColor,
                              border: Border.all(
                                color: liveReply
                                    ? context.vita.green.withValues(alpha: .32)
                                    : isUser
                                        ? context.vita.green
                                            .withValues(alpha: .18)
                                        : context.vita.text
                                            .withValues(alpha: .06),
                              ),
                              borderRadius: BorderRadius.only(
                                topLeft: const Radius.circular(20),
                                topRight: const Radius.circular(20),
                                bottomLeft: Radius.circular(isUser ? 20 : 7),
                                bottomRight: Radius.circular(isUser ? 7 : 20),
                              ),
                            ),
                      child: _ChatMessageBody(
                        message: m,
                        companionId: widget.companionId,
                        avatarUrl: widget.companion?['portrait_url'] as String?,
                        onPlayVoice: _playVoice,
                        onOpenLifeEvent: _openLifeEvent,
                      ),
                    ),
                    if (isUser && deliveryStatus != 'delivered')
                      Positioned(
                        right:
                            -(8 + (deliveryStatus == 'sending' ? 14.0 : 17.0)),
                        bottom: 0,
                        child: deliveryStatus == 'sending'
                            ? SizedBox.square(
                                dimension: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 1.5,
                                  color: context.vita.subText,
                                ),
                              )
                            : Icon(Icons.error_outline_rounded,
                                size: 17, color: context.vita.red),
                      ),
                  ],
                ),
              ),
              if (isUser) ...[
                const SizedBox(width: 8),
                Obx(() {
                  final auth = AuthController.to;
                  return VitaAvatar(
                      name: auth.nickname.isEmpty ? '?' : auth.nickname,
                      radius: 22,
                      imageUrl: auth.avatarUrl,
                      borderRadius: BorderRadius.circular(10));
                }),
              ],
            ],
          ),
        ),
      );
    }

    return Listener(
      onPointerDown: (_) => ++_scrollRequest,
      child: ListView(
        controller: _scroll,
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        children: items,
      ),
    );
  }

  bool _isUserMessage(Map<String, dynamic> message) =>
      message['sender_type'] == 'user' ||
      (message['source'] == 'paid_date' &&
          message['message_type'] == 'scene_card');

  Widget _buildInputBar({required bool locked, required String? panel}) {
    return Container(
      decoration: BoxDecoration(
        color: context.vita.pageBg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // TODO: voice recording button temporarily hidden
          // _RoundIconButton(
          //   icon: _recording ? Icons.keyboard : Icons.graphic_eq,
          //   onTap: locked ? null : _toggleRecording,
          //   active: _recording,
          // ),
          // const SizedBox(width: 8),
          Expanded(
            child: Container(
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: context.vita.surface,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Focus(
                canRequestFocus: false,
                skipTraversal: true,
                onKeyEvent: _onInputKey,
                child: TextField(
                  controller: _input,
                  enabled: !locked,
                  onTap: () {
                    if (_panel.value != null) _panel.value = null;
                  },
                  minLines: 1,
                  maxLines: 5,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _send(),
                  style: TextStyle(
                      fontSize: 16, color: context.vita.text, height: 1.4),
                  decoration: InputDecoration(
                    hintText: locked ? 'chat.cannotSend'.tr : 'chat.message'.tr,
                    hintStyle: TextStyle(
                        color: context.vita.hint, fontSize: 16, height: 1.4),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    errorBorder: InputBorder.none,
                    disabledBorder: InputBorder.none,
                    isCollapsed: true,
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          _RoundIconButton(
            icon: panel == 'emoji'
                ? Icons.keyboard
                : Icons.sentiment_satisfied_alt_outlined,
            onTap: locked
                ? null
                : () {
                    FocusScope.of(context).unfocus();
                    _panel.value = panel == 'emoji' ? null : 'emoji';
                  },
            showBorder: false,
            iconSize: 30,
          ),
          const SizedBox(width: 0),
          _RoundIconButton(
            icon: Icons.add_circle_outline,
            onTap: locked
                ? null
                : () {
                    FocusScope.of(context).unfocus();
                    _panel.value = panel == 'more' ? null : 'more';
                  },
            showBorder: false,
            iconSize: 30,
          ),
        ],
      ),
    );
  }

  Widget _buildMorePanel() {
    return Container(
      color: context.vita.pageBg,
      height: _panelHeight,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _MorePanelButton(
            icon: Icons.swap_horiz_rounded,
            label: 'chat.transfer'.tr,
            onTap: () {
              _panel.value = null;
              showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                backgroundColor: context.vita.surface,
                showDragHandle: true,
                builder: (_) => CompanionTransferSheet(
                  companionId: widget.companionId,
                  companionName: widget.name,
                  onCompleted: ctrl.poll,
                ),
              );
            },
          ),
          const SizedBox(width: 20),
          _MorePanelButton(
            icon: Icons.card_giftcard_rounded,
            label: '礼物',
            onTap: () {
              _panel.value = null;
              showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: context.vita.surface,
                  showDragHandle: true,
                  builder: (_) => ExperienceSheet(
                      companionId: widget.companionId,
                      onCompleted: ctrl.poll,
                      onResult: (response) async {
                        await ctrl.experienceCompleted(response);
                        final result = response['result'];
                        final product = response['product'];
                        final eventId =
                            result is Map ? result['event_id'] : null;
                        if (mounted &&
                            product is Map &&
                            product['category'] == 'gift') {
                          Navigator.of(context).pop();
                          final action = await Get.to<String>(
                              () => GiftRevealPage(
                                    name: widget.name,
                                    portraitUrl: widget
                                        .companion?['portrait_url'] as String?,
                                    response: response,
                                  ),
                              transition: Transition.cupertino);
                          if (mounted && action == 'world') {
                            ShellController.to.selectedCompanionId.value =
                                widget.companionId;
                            ShellController.to.switchTo(0);
                            Get.back();
                          }
                          return;
                        }
                        if (mounted &&
                            product is Map &&
                            product['category'] == 'date' &&
                            eventId is String) {
                          Navigator.of(context).pop();
                          Get.to(() => CompanionMomentPage(
                                companionId: widget.companionId,
                                eventId: eventId,
                                name: widget.name,
                                avatarUrl: widget.companion?['portrait_url']
                                    as String?,
                                controller: ctrl,
                              ));
                        }
                      }));
            },
          ),
        ],
      ),
    );
  }
}

class _CompanionGestureAvatar extends StatelessWidget {
  const _CompanionGestureAvatar(
      {required this.name, required this.imageUrl, required this.gesture});

  final String name;
  final String? imageUrl;
  final String gesture;

  @override
  Widget build(BuildContext context) {
    final icon = switch (gesture) {
      'curious' => Icons.question_mark_rounded,
      'thoughtful' => Icons.auto_awesome_rounded,
      _ => Icons.favorite_rounded,
    };
    return Semantics(
      label: 'chat.gesture.$gesture'.tr,
      child: SizedBox.square(
        dimension: 44,
        child: Stack(clipBehavior: Clip.none, children: [
          TweenAnimationBuilder<double>(
            tween: Tween(begin: .87, end: 1),
            duration: const Duration(milliseconds: 650),
            curve: Curves.easeOutBack,
            builder: (context, scale, child) =>
                Transform.scale(scale: scale, child: child),
            child: VitaAvatar(
                name: name,
                radius: 22,
                imageUrl: imageUrl,
                borderRadius: BorderRadius.circular(10)),
          ),
          Positioned(
              right: -3,
              bottom: -3,
              child: Container(
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                      color: context.vita.green,
                      borderRadius: BorderRadius.circular(6)),
                  child: Icon(icon, color: Colors.white, size: 12))),
        ]),
      ),
    );
  }
}

class _ChatMessageBody extends StatelessWidget {
  const _ChatMessageBody({
    required this.message,
    required this.companionId,
    this.avatarUrl,
    required this.onPlayVoice,
    required this.onOpenLifeEvent,
  });

  final Map<String, dynamic> message;
  final String companionId;
  final String? avatarUrl;
  final ValueChanged<String> onPlayVoice;
  final Future<void> Function(Map<String, dynamic>) onOpenLifeEvent;

  @override
  Widget build(BuildContext context) {
    final parsed = ChatMessageContent.from(message);
    final type = parsed.type;
    final payload = parsed.payload;
    final mediaURL = parsed.mediaUrl;
    final displayContent =
        parsed.contentIsTranslationKey ? parsed.text.tr : parsed.text;
    final children = <Widget>[];
    if (parsed.isGift) {
      return _AnimatedGiftCard(
        key: ValueKey(message['id']),
        content: parsed,
        animate: message['_animate_gift'] == true,
      );
    }
    if (type == 'transfer') {
      return _TransferCard(coins: payload['coins']);
    }
    if (type == 'scene_card' && payload['event_id'] is String) {
      final scheduled =
          DateTime.tryParse('${payload['scheduled_at'] ?? ''}')?.toLocal();
      final endsAt =
          DateTime.tryParse('${payload['ends_at'] ?? ''}')?.toLocal();
      final timeLabel = scheduled == null
          ? 'moment.open'.tr
          : endsAt != null && !DateTime.now().isBefore(endsAt)
              ? 'moment.ended'.tr
              : endsAt == null && !DateTime.now().isBefore(scheduled)
                  ? 'moment.open'.tr
                  : !DateTime.now().isBefore(scheduled)
                      ? 'moment.live'.tr
                      : 'moment.scheduled'.trParams({
                          'time': '${MaterialLocalizations.of(context).formatMediumDate(scheduled)} '
                              '${TimeOfDay.fromDateTime(scheduled).format(context)}'
                        });
      return Material(
        color: context.vita.surface,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => Get.to(() => CompanionMomentPage(
                companionId: companionId,
                eventId: payload['event_id'] as String,
                name: Get.find<ChatController>(tag: companionId).companionName,
                controller: Get.find<ChatController>(tag: companionId),
                avatarUrl: avatarUrl,
              )),
          borderRadius: BorderRadius.circular(18),
          child: Container(
            width: 250,
            padding: const EdgeInsets.fromLTRB(15, 14, 14, 14),
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(
                    color: context.vita.green.withValues(alpha: .48), width: 2),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Icon(Icons.auto_awesome_rounded,
                      color: context.vita.green, size: 17),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('moment.open'.tr,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: context.vita.text)),
                  ),
                  Icon(Icons.arrow_outward_rounded,
                      size: 17, color: context.vita.subText),
                ]),
                if (displayContent.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(displayContent,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 12,
                          height: 1.4,
                          color: context.vita.subText)),
                ],
                if (scheduled != null) ...[
                  const SizedBox(height: 9),
                  Text(timeLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: context.vita.green)),
                ],
              ],
            ),
          ),
        ),
      );
    }
    if (parsed.mediaKind == ChatMediaKind.voice) {
      children.add(InkWell(
        onTap: () => onPlayVoice(mediaURL),
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.play_circle_fill, color: context.vita.green, size: 28),
            const SizedBox(width: 7),
            Text('chat.voiceMessage'.tr,
                style: TextStyle(color: context.vita.text)),
          ]),
        ),
      ));
    } else if (parsed.mediaKind == ChatMediaKind.image) {
      children.add(ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: AspectRatio(
          aspectRatio: 4 / 3,
          child: VitaMediaImage(url: mediaURL),
        ),
      ));
    }
    if (displayContent.isNotEmpty) {
      if (children.isNotEmpty) children.add(const SizedBox(height: 7));
      children.add(_LinkedMessageText(displayContent,
          style: TextStyle(
              fontSize: type == 'voice' ? 13 : 16,
              color: type == 'voice' ? context.vita.subText : context.vita.text,
              height: 1.4)));
    }
    if (type == 'life_card' ||
        (type == 'image_text' &&
            (payload['event_location'] as String? ?? '').isNotEmpty)) {
      if (children.isNotEmpty) children.add(const SizedBox(height: 8));
      children.add(InkWell(
        onTap: () => onOpenLifeEvent(message),
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
              color: context.vita.pageBg,
              borderRadius: BorderRadius.circular(6)),
          child: Row(children: [
            Icon(Icons.access_time, size: 18, color: context.vita.green),
            const SizedBox(width: 8),
            Expanded(
                child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(payload['event_title'] as String? ?? '',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: context.vita.text)),
                if ((payload['event_location'] as String? ?? '').isNotEmpty)
                  Text(payload['event_location'] as String,
                      style:
                          TextStyle(fontSize: 11, color: context.vita.subText)),
              ],
            )),
            Icon(Icons.chevron_right, size: 18, color: context.vita.hint),
          ]),
        ),
      ));
    }
    return Column(
        crossAxisAlignment: CrossAxisAlignment.start, children: children);
  }
}

class _LifeEventSheet extends StatefulWidget {
  const _LifeEventSheet({
    required this.companionId,
    required this.eventId,
    required this.fallback,
  });

  final String companionId;
  final String eventId;
  final Map<String, dynamic> fallback;

  @override
  State<_LifeEventSheet> createState() => _LifeEventSheetState();
}

class _LifeEventSheetState extends State<_LifeEventSheet> {
  late final Future<Map<String, dynamic>?> _event = _loadEvent();

  Future<Map<String, dynamic>?> _loadEvent() async {
    if (widget.eventId.isEmpty) return null;
    try {
      final data = await ApiClient.instance.get(
          '/v1/companions/${widget.companionId}/life/events/${widget.eventId}');
      return data is Map ? Map<String, dynamic>.from(data) : null;
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Map<String, dynamic>?>(
        future: _event,
        builder: (context, snapshot) {
          final event = snapshot.data;
          final title =
              '${event?['title'] ?? widget.fallback['event_title'] ?? ''}'
                  .trim();
          final description =
              '${event?['description'] ?? widget.fallback['event_description'] ?? ''}'
                  .trim();
          final location =
              '${event?['location'] ?? widget.fallback['event_location'] ?? ''}'
                  .trim();
          final start =
              DateTime.tryParse('${event?['start_time'] ?? ''}')?.toLocal();
          final end =
              DateTime.tryParse('${event?['end_time'] ?? ''}')?.toLocal();
          final now = DateTime.now();
          final isActive = start != null &&
              end != null &&
              !now.isBefore(start) &&
              now.isBefore(end);
          final stage = start == null || end == null
              ? 'chat.event.shared'.tr
              : now.isBefore(start)
                  ? 'chat.event.upcoming'.tr
                  : isActive
                      ? 'chat.event.now'.tr
                      : 'chat.event.past'.tr;
          final payload = event?['payload'] is Map
              ? event!['payload'] as Map
              : widget.fallback;
          final media = payload['media_urls'];
          final imageUrl =
              media is List && media.isNotEmpty && media.first is String
                  ? media.first as String
                  : '';
          return SafeArea(
            top: false,
            child: SizedBox(
              height: MediaQuery.sizeOf(context).height * .68,
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(22, 4, 22, 22),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (imageUrl.isNotEmpty) ...[
                      ClipRRect(
                        borderRadius: BorderRadius.circular(18),
                        child: SizedBox(
                          height: 185,
                          width: double.infinity,
                          child:
                              VitaMediaImage(url: imageUrl, fit: BoxFit.cover),
                        ),
                      ),
                      const SizedBox(height: 18),
                    ],
                    Text(stage,
                        style: TextStyle(
                            color: context.vita.green,
                            fontSize: 12,
                            fontWeight: FontWeight.w700)),
                    const SizedBox(height: 10),
                    Text(title,
                        style: TextStyle(
                            color: context.vita.text,
                            fontSize: 23,
                            fontWeight: FontWeight.w700)),
                    if (start != null || location.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Text(
                        [
                          if (start != null)
                            '${formatDate(start)} ${formatClock(start)}',
                          if (location.isNotEmpty) location,
                        ].join(' · '),
                        style: TextStyle(
                            color: context.vita.subText, fontSize: 12),
                      ),
                    ],
                    if (description.isNotEmpty) ...[
                      const SizedBox(height: 20),
                      Text(description,
                          style: TextStyle(
                              color: context.vita.text,
                              fontSize: 15,
                              height: 1.55)),
                    ],
                    if (snapshot.connectionState ==
                        ConnectionState.waiting) ...[
                      const SizedBox(height: 18),
                      const LinearProgressIndicator(minHeight: 2),
                    ],
                    const SizedBox(height: 26),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: title.isEmpty
                            ? null
                            : () => Navigator.of(context).pop({
                                  'title': title,
                                  'event_id': widget.eventId,
                                }),
                        icon: const Icon(Icons.chat_bubble_outline_rounded,
                            size: 17),
                        label: Text(isActive
                            ? 'chat.event.discussNow'.tr
                            : 'chat.event.discuss'.tr),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );
}

class _LinkedMessageText extends StatefulWidget {
  const _LinkedMessageText(this.text, {required this.style});

  final String text;
  final TextStyle style;

  @override
  State<_LinkedMessageText> createState() => _LinkedMessageTextState();
}

class _LinkedMessageTextState extends State<_LinkedMessageText> {
  static final _urlPattern = RegExp(r'https?://[^\s<>]+', caseSensitive: false);
  final _recognizers = <String, TapGestureRecognizer>{};

  @override
  void dispose() {
    for (final recognizer in _recognizers.values) {
      recognizer.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final spans = <InlineSpan>[];
    var offset = 0;
    for (final match in _urlPattern.allMatches(widget.text)) {
      var end = match.end;
      while (
          end > match.start && '.,!?;:，。！？；：'.contains(widget.text[end - 1])) {
        end--;
      }
      if (end == match.start) continue;
      if (match.start > offset) {
        spans.add(TextSpan(text: widget.text.substring(offset, match.start)));
      }
      final url = widget.text.substring(match.start, end);
      final uri = Uri.tryParse(url);
      if (uri != null && uri.host.isNotEmpty) {
        final recognizer = _recognizers.putIfAbsent(
            url,
            () => TapGestureRecognizer()
              ..onTap = () async {
                if (!await launchUrl(uri,
                    mode: LaunchMode.externalApplication)) {
                  VitaNotice.error('experience.failed'.tr, url);
                }
              });
        spans.add(TextSpan(
            text: url,
            style: TextStyle(
                color: context.vita.green,
                decoration: TextDecoration.underline),
            recognizer: recognizer));
      } else {
        spans.add(TextSpan(text: url));
      }
      offset = end;
    }
    if (offset < widget.text.length) {
      spans.add(TextSpan(text: widget.text.substring(offset)));
    }
    return Text.rich(TextSpan(children: spans), style: widget.style);
  }
}

class _TransferCard extends StatelessWidget {
  const _TransferCard({required this.coins});

  final Object? coins;

  @override
  Widget build(BuildContext context) {
    final amount = coins is num ? (coins as num).toInt().toString() : '—';
    return Semantics(
      label:
          '${'chat.transfer'.tr}, $amount ${'transfer.coinUnit'.tr}, ${'transfer.sent'.tr}',
      child: Container(
        width: 250,
        height: 132,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              context.vita.green,
              Color.lerp(context.vita.greenDark, const Color(0xFF17152F), .64)!,
            ],
          ),
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: context.vita.green.withValues(alpha: .28),
              blurRadius: 18,
              offset: Offset(0, 7),
            ),
          ],
        ),
        child: Stack(children: [
          Positioned(
            right: -28,
            top: -37,
            child: Container(
              width: 138,
              height: 138,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0x45FFFFFF)),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(17, 14, 17, 13),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  const Icon(Icons.north_east_rounded,
                      size: 17, color: Color(0xFFFFD989)),
                  const SizedBox(width: 6),
                  Text('chat.transfer'.tr,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Color(0xE6FFFFFF))),
                ]),
                const Spacer(),
                Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Flexible(
                    child: SizedBox(
                      height: 42,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.bottomLeft,
                        child: Text(amount,
                            maxLines: 1,
                            style: const TextStyle(
                                fontSize: 37,
                                height: 1,
                                fontWeight: FontWeight.w800,
                                color: Colors.white)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text('transfer.coinUnit'.tr,
                        maxLines: 1,
                        style: const TextStyle(
                            fontSize: 13, color: Color(0xD9FFFFFF))),
                  ),
                  const Spacer(),
                  const Icon(Icons.toll_rounded,
                      size: 34, color: Color(0xFFFFD989)),
                ]),
                const SizedBox(height: 8),
                Container(height: 1, color: const Color(0x42FFFFFF)),
                const SizedBox(height: 8),
                Row(children: [
                  const Icon(Icons.check_circle_rounded,
                      size: 13, color: Color(0xFFFFD989)),
                  const SizedBox(width: 5),
                  Text('transfer.sent'.tr,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 11, color: Color(0xE6FFFFFF))),
                ]),
              ],
            ),
          ),
        ]),
      ),
    );
  }
}

class _AnimatedGiftCard extends StatefulWidget {
  const _AnimatedGiftCard({
    super.key,
    required this.content,
    required this.animate,
  });

  final ChatMessageContent content;
  final bool animate;

  @override
  State<_AnimatedGiftCard> createState() => _AnimatedGiftCardState();
}

class _AnimatedGiftCardState extends State<_AnimatedGiftCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
      value: widget.animate ? 0 : 1,
    );
    if (widget.animate) _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String get _nameKey {
    final configured = widget.content.payload['name_key'];
    if (configured is String && configured.isNotEmpty) return configured;
    return switch (widget.content.payload['product_key']) {
      'gift_coffee' => 'experience.gift.coffee',
      'gift_flowers' => 'experience.gift.flowers',
      'gift_cake' => 'experience.gift.cake',
      'gift_keepsake' => 'experience.gift.keepsake',
      _ => 'gift.sent.title',
    };
  }

  @override
  Widget build(BuildContext context) {
    final giftIcon =
        giftVisualIcon('${widget.content.payload['product_key'] ?? ''}');
    final coins = widget.content.payload['coins'];
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final entrance = Curves.elasticOut.transform(_controller.value);
        return Opacity(
          opacity: _controller.value.clamp(0, 1),
          child: Transform.translate(
            offset: Offset(0, (1 - _controller.value) * 18),
            child: Transform.scale(
              scale: .68 + entrance * .32,
              child: child,
            ),
          ),
        );
      },
      child: Container(
        width: 190,
        padding: const EdgeInsets.fromLTRB(14, 13, 14, 12),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFFFB45C), Color(0xFFF47C57)],
          ),
          borderRadius: BorderRadius.circular(12),
          boxShadow: const [
            BoxShadow(
              color: Color(0x33E56A3C),
              blurRadius: 12,
              offset: Offset(0, 5),
            ),
          ],
        ),
        child: Stack(children: [
          const Positioned(
            right: 2,
            top: 0,
            child: Icon(Icons.auto_awesome_rounded,
                size: 20, color: Color(0xCCFFF0B8)),
          ),
          Row(children: [
            Container(
              width: 56,
              height: 56,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: .22),
                shape: BoxShape.circle,
              ),
              child: Icon(giftIcon, color: Colors.white, size: 34),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _nameKey.tr,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (coins is num) ...[
                    const SizedBox(height: 3),
                    Text(
                      'gift.coins'.trParams({'coins': '${coins.toInt()}'}),
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: .86),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ]),
        ]),
      ),
    );
  }
}

/// Circular icon button matching the WeChat-style composer.
class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({
    required this.icon,
    required this.onTap,
    this.active = false,
    this.showBorder = true,
    this.iconSize = 22,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final bool active;
  final bool showBorder;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 38,
        height: 38,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: !showBorder
              ? Colors.transparent
              : (active ? context.vita.green : context.vita.surface),
          border: showBorder
              ? Border.all(
                  color: active ? context.vita.green : context.vita.divider,
                  width: 1,
                )
              : null,
        ),
        child: Icon(
          icon,
          size: iconSize,
          color: active
              ? Colors.white
              : enabled
                  ? context.vita.text
                  : context.vita.hint,
        ),
      ),
    );
  }
}

/// Grid button inside the "+" more panel (white rounded square + label).
class _MorePanelButton extends StatelessWidget {
  const _MorePanelButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 60,
            height: 60,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: context.vita.surface,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, size: 30, color: context.vita.text),
          ),
          const SizedBox(height: 8),
          Text(label,
              style: TextStyle(fontSize: 12, color: context.vita.subText)),
        ],
      ),
    );
  }
}

/// Chat avatar fallback when a character has no portrait.
