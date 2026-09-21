import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../../core/constants.dart';
import '../../core/api_client.dart';
import '../../core/theme.dart';
import '../../shared/media_image.dart';
import '../../shared/widgets.dart';
import '../shell/shell_page.dart';
import 'chat_controller.dart';
import 'chat_info_page.dart';
import 'chat_message_content.dart';
import 'experience_sheet.dart';

/// Chat detail page — message bubbles (user right / companion left),
/// date separators and a WeChat-style input bar.
class ChatPage extends StatefulWidget {
  const ChatPage(
      {super.key,
      required this.companionId,
      required this.name,
      this.companion});

  final String companionId;
  final String name;

  /// Full companion profile map (from the list) — shown in the "more" sheet.
  final Map<String, dynamic>? companion;

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
  final _recorder = AudioRecorder();
  final _player = AudioPlayer();
  late final Worker _messageWorker;
  Timer? _recordingTimer;
  bool _recording = false;

  @override
  void initState() {
    super.initState();
    _messageWorker = ever(ctrl.messages, (_) {
      if (!mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
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
    _recordingTimer?.cancel();
    _input.dispose();
    _scroll.dispose();
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
    final send = ctrl.send(text);
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    final queued = await send;
    if (!mounted) return;
    // Nothing reached the conversation: put the draft back so it is not lost.
    if (!queued) _restoreDraft(text);
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
      Get.snackbar('chat.message'.tr, 'chat.sendFailed'.tr);
    } else if (reason != null && reason.isNotEmpty) {
      Get.snackbar('chat.message'.tr, reason);
    }
  }

  void _scrollToBottom() {
    if (!_scroll.hasClients) return;
    _scroll.animateTo(
      _scroll.position.maxScrollExtent,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
    );
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

  void _showEmojiPicker() {
    FocusScope.of(context).unfocus();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: context.vita.surface,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
          child: GridView.builder(
            shrinkWrap: true,
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
                onTap: () {
                  _insertEmoji(emoji);
                  Navigator.of(sheetContext).pop();
                },
                child: Center(
                    child: Text(emoji, style: const TextStyle(fontSize: 26))),
              );
            },
          ),
        ),
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
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(
                  child: Obx(
                    () => _buildMessages(
                      ctrl,
                      bottomPadding: _inputBarReservedHeight(context),
                    ),
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Obx(() => _buildInputBar(
                        locked: ctrl.accessError.value != null,
                      )),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  double _inputBarReservedHeight(BuildContext context) =>
      72 + MediaQuery.of(context).padding.bottom;

  Widget _buildMessages(ChatController ctrl, {double bottomPadding = 0}) {
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
        final sameSender = prev['sender_type'] == m['sender_type'];
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

      final isUser = m['sender_type'] == 'user';
      final parsed = ChatMessageContent.from(m);
      final isGift = parsed.isGift;
      final deliveryStatus = m['delivery_status'] as String? ?? 'delivered';
      final bubbleColor = isGift
          ? Colors.transparent
          : isUser
              ? context.vita.bubbleGreen
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
                VitaAvatar(
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
                    Container(
                      constraints: BoxConstraints(
                        maxWidth: MediaQuery.of(context).size.width * 0.66,
                      ),
                      padding: isGift
                          ? EdgeInsets.zero
                          : const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 10),
                      decoration: isGift
                          ? null
                          : BoxDecoration(
                              color: bubbleColor,
                              borderRadius: BorderRadius.circular(12),
                            ),
                      child: _ChatMessageBody(
                        message: m,
                        companionId: widget.companionId,
                        onPlayVoice: _playVoice,
                      ),
                    ),
                    if (!isGift)
                      Positioned(
                        right: isUser ? -6 : null,
                        left: isUser ? null : -6,
                        top: 22,
                        child: CustomPaint(
                          size: const Size(6, 8),
                          painter: _BubbleTailPainter(
                            color: bubbleColor,
                            pointRight: isUser,
                          ),
                        ),
                      ),
                    if (isUser && deliveryStatus != 'delivered')
                      Positioned(
                        right: -(8 +
                            (deliveryStatus == 'sending' ? 14.0 : 17.0)),
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
                VitaAvatar(name: '1', radius: 22,
                    borderRadius: BorderRadius.circular(10)),
              ],
            ],
          ),
        ),
      );
    }

    return ListView(
      controller: _scroll,
      padding: EdgeInsets.fromLTRB(14, 10, 14, 10 + bottomPadding),
      children: items,
    );
  }

  Widget _buildInputBar({required bool locked}) {
    return Container(
      decoration: BoxDecoration(
        color: context.vita.pageBg,
        border:
            Border(top: BorderSide(color: context.vita.divider, width: 0.5)),
      ),
      padding: EdgeInsets.fromLTRB(
          8, 8, 8, 8 + MediaQuery.of(context).padding.bottom),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          _RoundIconButton(
            icon: _recording ? Icons.keyboard : Icons.graphic_eq,
            onTap: locked ? null : _toggleRecording,
            active: _recording,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: context.vita.surface,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Focus(
                canRequestFocus: false,
                skipTraversal: true,
                onKeyEvent: _onInputKey,
                child: SizedBox(
                    height: 40,
                    child: TextField(
                controller: _input,
                enabled: !locked,
                minLines: 1,
                maxLines: 5,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _send(),
                style: TextStyle(
                    fontSize: 16, color: context.vita.text, height: 1.4),
                decoration: InputDecoration(
                  hintText: locked ? 'chat.cannotSend'.tr : 'chat.message'.tr,
                  hintStyle:
                      TextStyle(color: context.vita.hint, fontSize: 15),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  errorBorder: InputBorder.none,
                  disabledBorder: InputBorder.none,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                ),
              ),
              ),
            ),
          ),
          ),
          const SizedBox(width: 8),
          _RoundIconButton(
            icon: Icons.sentiment_satisfied_alt_outlined,
            onTap: locked ? null : _showEmojiPicker,
          ),
          const SizedBox(width: 8),
          _RoundIconButton(
            icon: Icons.add,
            onTap: locked ? null : _showMorePanel,
          ),
        ],
      ),
    );
  }

  void _showMorePanel() {
    FocusScope.of(context).unfocus();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: context.vita.pageBg,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          child: Row(
            children: [
              _MorePanelButton(
                icon: Icons.swap_horiz_rounded,
                label: '转账',
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  Get.snackbar('转账', '转账功能即将上线');
                },
              ),
              const SizedBox(width: 20),
              _MorePanelButton(
                icon: Icons.card_giftcard_rounded,
                label: '礼物',
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  showModalBottomSheet<void>(context: context, isScrollControlled: true, backgroundColor: context.vita.surface, showDragHandle: true, builder: (_) => ExperienceSheet(companionId: widget.companionId, onCompleted: ctrl.poll));
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChatMessageBody extends StatelessWidget {
  const _ChatMessageBody({
    required this.message,
    required this.companionId,
    required this.onPlayVoice,
  });

  final Map<String, dynamic> message;
  final String companionId;
  final ValueChanged<String> onPlayVoice;

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
      children.add(Text(displayContent,
          style: TextStyle(
              fontSize: type == 'voice' ? 13 : 16,
              color: type == 'voice' ? context.vita.subText : context.vita.text,
              height: 1.4)));
    }
    if (type == 'life_card') {
      if (children.isNotEmpty) children.add(const SizedBox(height: 8));
      children.add(InkWell(
        onTap: () {
          Get.back();
          ShellController.to.switchTo(1);
        },
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
    final payloadEmoji = widget.content.payload['emoji'];
    final emoji = payloadEmoji is String && payloadEmoji.isNotEmpty
        ? payloadEmoji
        : widget.content.text.isNotEmpty
            ? widget.content.text
            : '🎁';
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
              child: Text(emoji, style: const TextStyle(fontSize: 34)),
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
  });

  final IconData icon;
  final VoidCallback? onTap;
  final bool active;

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
          color: active ? context.vita.green : context.vita.surface,
          border: Border.all(
            color: active ? context.vita.green : context.vita.divider,
            width: 1,
          ),
        ),
        child: Icon(
          icon,
          size: 22,
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

/// Clip path that adds a small WeChat-style tail to a chat bubble.
/// [isUser] = true draws the tail on the right (green bubble); false on the
/// left (white bubble).
class _BubbleTailPainter extends CustomPainter {
  _BubbleTailPainter({required this.color, required this.pointRight});

  final Color color;
  final bool pointRight;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final path = Path();
    if (pointRight) {
      path
        ..moveTo(0, 0)
        ..lineTo(size.width, size.height / 2)
        ..lineTo(0, size.height)
        ..close();
    } else {
      path
        ..moveTo(size.width, 0)
        ..lineTo(0, size.height / 2)
        ..lineTo(size.width, size.height)
        ..close();
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_BubbleTailPainter old) =>
      old.color != color || old.pointRight != pointRight;
}

/// Chat avatar: mint-green circle with green initial (WeChat-style).
