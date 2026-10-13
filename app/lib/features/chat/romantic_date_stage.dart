import 'dart:math' as math;
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../core/constants.dart';
import '../../core/theme.dart';
import '../../shared/media_image.dart';
import 'shared_experience_stage.dart';

/// Environment first: no portrait, no mandatory chat transcript, no extra charge.
class RomanticDateStage extends StatefulWidget {
  const RomanticDateStage(
      {super.key,
      required this.title,
      required this.location,
      required this.backgroundUrl,
      required this.audioUrl,
      this.portraitUrl,
      required this.companionName,
      required this.messages,
      required this.input,
      required this.busy,
      required this.onSend,
      required this.onAction,
      this.onKeepsake,
      this.journey});
  final String title, location, backgroundUrl, audioUrl, companionName;
  final String? portraitUrl;
  final List<Map<String, dynamic>> messages;
  final TextEditingController input;
  final bool busy;
  final Future<void> Function(String) onSend;
  final Future<bool> Function(String, String) onAction;
  final VoidCallback? onKeepsake;
  final Widget? journey;
  @override
  State<RomanticDateStage> createState() => _RomanticDateStageState();
}

class _RomanticDateStageState extends State<RomanticDateStage>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _motion =
      AnimationController(vsync: this, duration: const Duration(seconds: 8));
  final AudioPlayer _audio = AudioPlayer();
  final FocusNode _inputFocus = FocusNode();
  final ValueNotifier<List<Map<String, dynamic>>> _history = ValueNotifier([]);
  bool _sending = false, _sound = false, _chat = false, _active = true;
  ModalRoute<dynamic>? _route;
  bool _historyUpdateScheduled = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _history.value = widget.messages;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _route = ModalRoute.of(context);
    _sync();
  }

  @override
  void didUpdateWidget(covariant RomanticDateStage old) {
    super.didUpdateWidget(old);
    _scheduleHistoryUpdate();
    if (old.audioUrl != widget.audioUrl) {
      _audio.stop();
      _sound = false;
    }
    _sync();
  }

  // The history sheet is a separate route; notifying during the parent
  // route's build would mark that sheet dirty outside the building subtree.
  void _scheduleHistoryUpdate() {
    if (_historyUpdateScheduled) return;
    _historyUpdateScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _historyUpdateScheduled = false;
      if (!mounted) return;
      _history.value = List<Map<String, dynamic>>.of(widget.messages);
    });
  }

  void _sync() {
    final visible = _route?.isCurrent == true &&
        WidgetsBinding.instance.lifecycleState != AppLifecycleState.paused;
    if (visible && !MediaQuery.of(context).disableAnimations) {
      if (!_motion.isAnimating) _motion.repeat(reverse: true);
    } else {
      _motion.stop();
    }
    if (!visible && _sound) {
      _audio.pause();
      _sound = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      _audio.pause();
      _sound = false;
      _motion.stop();
    } else if (mounted) {
      _sync();
      setState(() {});
    }
  }

  @override
  void deactivate() {
    _active = false;
    _motion.stop();
    _audio.pause();
    _sound = false;
    super.deactivate();
  }

  @override
  void activate() {
    super.activate();
    _active = true;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _motion.dispose();
    _inputFocus.dispose();
    _audio.dispose();
    _history.dispose();
    super.dispose();
  }

  String? get _action {
    for (final m in widget.messages.reversed) {
      final p = m['payload'];
      if (m['sender_type'] == 'user' &&
          p is Map &&
          p['scene_action'] is String &&
          m['delivery_status'] != 'failed' &&
          m['delivery_status'] != 'sending') return p['scene_action'] as String;
    }
    return null;
  }

  String get _prop {
    for (final message in widget.messages.reversed) {
      final payload = message['payload'];
      if (message['sender_type'] != 'user' ||
          payload is! Map ||
          ['failed', 'sending'].contains(message['delivery_status'])) continue;
      final action = payload['scene_action'];
      if (action == 'tea') return 'tea';
      if (action == 'coffee') return 'coffee';
      if (action == 'dessert') return 'dessert';
      if (action == 'dinner') return 'meal';
    }
    return widget.location == 'restaurant' ? 'meal' : 'coffee';
  }

  Future<void> _perform(String action) async {
    if (_sending || widget.busy) return;
    setState(() => _sending = true);
    try {
      final ok = await widget.onAction(action, 'date.scene.action.$action'.tr);
      if (!ok && mounted && _active && _route?.isCurrent == true)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('chat.sendFailed'.tr)));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _toggleSound() async {
    try {
      if (_sound) {
        await _audio.pause();
      } else {
        final url = widget.audioUrl.startsWith('/')
            ? '$vitaApiBaseUrl${widget.audioUrl}'
            : widget.audioUrl;
        await _audio.setReleaseMode(ReleaseMode.loop);
        await _audio.play(UrlSource(url), volume: .35);
      }
      if (!mounted || !_active || _route?.isCurrent != true) {
        await _audio.pause();
        return;
      }
      setState(() => _sound = !_sound);
    } catch (_) {
      if (mounted && _active && _route?.isCurrent == true) {
        setState(() => _sound = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('date.scene.audioError'.tr)));
      }
    }
  }

  void _openHistory() => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: context.vita.surface,
      builder: (ctx) => SafeArea(
          top: false,
          child: SizedBox(
              height: MediaQuery.sizeOf(ctx).height * .65,
              child: ValueListenableBuilder<List<Map<String, dynamic>>>(
                  valueListenable: _history,
                  builder: (ctx, messages, _) => ListView.builder(
                      padding: const EdgeInsets.all(20),
                      itemCount: messages.length,
                      itemBuilder: (ctx, i) {
                        final m = messages[i];
                        final user = m['sender_type'] == 'user';
                        return Align(
                            alignment: user
                                ? AlignmentDirectional.centerEnd
                                : AlignmentDirectional.centerStart,
                            child: Container(
                                margin: const EdgeInsets.only(bottom: 12),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 10),
                                constraints: BoxConstraints(
                                    maxWidth:
                                        MediaQuery.sizeOf(ctx).width * .75),
                                decoration: BoxDecoration(
                                    color: user
                                        ? ctx.vita.greenTint
                                        : ctx.vita.pageBg,
                                    borderRadius: BorderRadius.circular(18)),
                                child: SelectableText('${m['content'] ?? ''}',
                                    style: TextStyle(
                                        color: ctx.vita.text,
                                        fontSize: 16,
                                        height: 1.4))));
                      })))));
  void _hideComposer() {
    _inputFocus.unfocus();
    setState(() => _chat = false);
  }

  void _toggleComposer() {
    if (_chat) {
      _hideComposer();
    } else {
      setState(() => _chat = true);
    }
  }

  Widget _choice(String label, VoidCallback onTap) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: SizedBox(
          width: double.infinity,
          height: 44,
          child: TextButton(
              onPressed: widget.busy || _sending ? null : onTap,
              style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFFFFFAF0),
                  backgroundColor: const Color(0xB3322923),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                      side: const BorderSide(color: Color(0x66D9C9B1)))),
              child: Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 15)))));

  void _openKeepsakePanel() {
    if (widget.journey == null) {
      widget.onKeepsake?.call();
      return;
    }
    showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        backgroundColor: const Color(0xFF29221D),
        builder: (ctx) => SafeArea(
            top: false,
            child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  widget.journey!,
                  TextButton(
                      onPressed: () {
                        Navigator.pop(ctx);
                        widget.onKeepsake?.call();
                      },
                      child: Text('moment.create'.tr,
                          style: const TextStyle(color: Colors.white)))
                ]))));
  }

  @override
  Widget build(BuildContext context) {
    final asset = switch (widget.location) {
      'restaurant' => 'dinner',
      'ballroom' => 'ballroom',
      'cinema' => 'cinema',
      _ => 'cafe'
    };
    final actions = switch (widget.location) {
      'restaurant' => ['dinner', 'dessert', 'toast'],
      'ballroom' => ['dance', 'slow_dance', 'terrace'],
      'cinema' => ['romance', 'mystery', 'pause'],
      _ => ['coffee', 'tea', 'toast']
    };
    final latest = widget.messages
        .where((m) => m['sender_type'] == 'assistant')
        .lastOrNull;
    final reply = '${latest?['content'] ?? ''}';
    final keyboard = MediaQuery.viewInsetsOf(context).bottom > 0;
    final latestIsAssistant = widget.messages.isNotEmpty &&
        widget.messages.last['sender_type'] == 'assistant';
    final suggestions = latestIsAssistant
        ? sharedSceneActions(latest)
        : <Map<String, String>>[];
    final availableActions =
        actions.where((action) => action != _action).toList();
    return Stack(children: [
      Positioned.fill(
          child: ExcludeSemantics(
              child: RepaintBoundary(
                  child: AnimatedBuilder(
                      animation: _motion,
                      child: widget.backgroundUrl.isEmpty
                          ? Image.asset('assets/scenes/$asset.png',
                              fit: BoxFit.cover)
                          : VitaMediaImage(
                              url: widget.backgroundUrl,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Image.asset(
                                  'assets/scenes/$asset.png',
                                  fit: BoxFit.cover)),
                      builder: (ctx, child) {
                        final dancing = widget.location == 'ballroom' &&
                            ['dance', 'slow_dance'].contains(_action);
                        final sway = dancing
                            ? math.sin(_motion.value * math.pi * 2)
                            : 0.0;
                        return Transform.scale(
                            scale: _action == 'terrace' ? 1.13 : 1.02,
                            alignment: Alignment.topCenter,
                            child: Transform.translate(
                                offset: Offset(sway * 4, 0),
                                child: Transform.rotate(
                                    angle: sway * .006, child: child)));
                      })))),
      Positioned.fill(
          child: IgnorePointer(
              child: AnimatedBuilder(
                  animation: _motion,
                  builder: (ctx, _) => DecoratedBox(
                          decoration: BoxDecoration(
                              gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                            Colors.black.withValues(alpha: .08),
                            Colors.transparent,
                            const Color(0xEE17130F)
                          ])))))),
      if (!keyboard)
        Positioned.fill(
            child: IgnorePointer(
                child: AnimatedBuilder(
                    animation: _motion,
                    builder: (ctx, _) => CustomPaint(
                        painter: _DateForeground(
                            widget.location, _action, _motion.value))))),
      if (!keyboard &&
          !['ballroom', 'cinema'].contains(widget.location) &&
          _action != null)
        Positioned(
            left: 24,
            right: 24,
            top: MediaQuery.sizeOf(context).height * .46,
            child: IgnorePointer(
                child: ExcludeSemantics(
                    child: AnimatedBuilder(
                        animation: _motion,
                        child: Image.asset('assets/scenes/${_prop}.png',
                            height: 160, fit: BoxFit.contain),
                        builder: (ctx, child) => Transform.translate(
                            offset: Offset(0,
                                _action == 'toast' ? -12 * _motion.value : 0),
                            child: child))))),
      SafeArea(
          top: true,
          child: Column(children: [
            Padding(
                padding:
                    const EdgeInsets.fromLTRB(16, kToolbarHeight + 8, 16, 8),
                child: Row(children: [
                  const Spacer(),
                  if (widget.audioUrl.isNotEmpty)
                    IconButton(
                        onPressed: _toggleSound,
                        tooltip: 'date.scene.sound'.tr,
                        icon: Icon(
                            _sound
                                ? Icons.volume_up_outlined
                                : Icons.volume_off_outlined,
                            color: Colors.white)),
                  TextButton(
                      onPressed: _openHistory,
                      child: Text('moment.scene.history'.tr,
                          style: const TextStyle(color: Colors.white))),
                ])),
            const Spacer(),
            if (reply.isNotEmpty && !keyboard)
              Padding(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
                  child: GestureDetector(
                      onTap: _openHistory,
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              if (widget.portraitUrl?.isNotEmpty == true) ...[
                                ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: SizedBox.square(
                                        dimension: 44,
                                        child: VitaMediaImage(
                                            url: widget.portraitUrl!,
                                            fit: BoxFit.cover))),
                                const SizedBox(width: 8),
                              ],
                              Expanded(
                                  child: Text(widget.companionName,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          color: Color(0xFFF1DCC0),
                                          fontSize: 15,
                                          fontWeight: FontWeight.w600))),
                            ]),
                            const SizedBox(height: 8),
                            Text(reply,
                                maxLines: 4,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.start,
                                style: const TextStyle(
                                    color: Color(0xFFFFFBF5),
                                    fontSize: 17,
                                    height: 1.55,
                                    shadows: [
                                      Shadow(
                                          color: Colors.black87, blurRadius: 8)
                                    ])),
                          ]))),
            if (!keyboard)
              Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                      children: suggestions.isNotEmpty
                          ? suggestions
                              .take(2)
                              .map((choice) => _choice(choice['label'] ?? '',
                                  () => widget.onSend(choice['message'] ?? '')))
                              .toList()
                          : availableActions
                              .take(2)
                              .map((action) => _choice('date.scene.$action'.tr,
                                  () => _perform(action)))
                              .toList())),
            if (widget.busy || _sending)
              Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text('moment.scene.responding'.tr,
                      style: const TextStyle(color: Colors.white70))),
            Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(children: [
                  TextButton.icon(
                      onPressed: _toggleComposer,
                      icon: const Icon(Icons.chat_bubble_outline, size: 16),
                      label: Text('date.scene.respond'.tr),
                      style:
                          TextButton.styleFrom(foregroundColor: Colors.white)),
                  if (widget.onKeepsake != null)
                    Expanded(
                        child: TextButton(
                            onPressed: _openKeepsakePanel,
                            child: Text('moment.create'.tr,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style:
                                    const TextStyle(color: Colors.white70)))),
                ])),
            if (_chat)
              Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Row(children: [
                    Expanded(
                        child: TextField(
                            controller: widget.input,
                            focusNode: _inputFocus,
                            enabled: !widget.busy,
                            maxLength: 2000,
                            maxLines: 3,
                            minLines: 1,
                            textInputAction: TextInputAction.send,
                            style: TextStyle(color: context.vita.text),
                            decoration: InputDecoration(
                                suffixIcon: IconButton(
                                    tooltip: 'common.cancel'.tr,
                                    onPressed: _hideComposer,
                                    icon: const Icon(Icons.close_rounded,
                                        size: 18)),
                                counterText: '',
                                hintText: 'chat.message'.tr,
                                filled: true,
                                fillColor: context.vita.surface,
                                border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(20),
                                    borderSide: BorderSide.none)),
                            onSubmitted: widget.onSend)),
                    IconButton(
                        onPressed: widget.busy
                            ? null
                            : () => widget.onSend(widget.input.text),
                        icon:
                            const Icon(Icons.north_east, color: Colors.white)),
                  ])),
          ])),
    ]);
  }
}

class _DateForeground extends CustomPainter {
  const _DateForeground(this.location, this.action, this.phase);
  final String location;
  final String? action;
  final double phase;
  @override
  void paint(Canvas canvas, Size size) {
    if (action == null) return;
    if (location == 'cinema') {
      if (action == 'pause') {
        canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height * .65),
            Paint()..color = Colors.black.withValues(alpha: .20));
        return;
      }
      final glow = action == 'romance'
          ? const Color(0xFFE8C99C)
          : const Color(0xFF8CABD2);
      canvas.drawRect(
          Rect.fromLTWH(0, 0, size.width, size.height * .65),
          Paint()
            ..shader = RadialGradient(
                center: const Alignment(0, -.4),
                radius: .8,
                colors: [
                  glow.withValues(alpha: .07 + .04 * phase),
                  Colors.transparent
                ]).createShader(Offset.zero & size));
      return;
    }
    if (location == 'ballroom') {
      if (action == 'terrace') return;
      final x = size.width * (.45 + .08 * math.sin(phase * math.pi));
      canvas.drawOval(
          Rect.fromCenter(
              center: Offset(x, size.height * .55),
              width: size.width * .75,
              height: 100),
          Paint()
            ..color = const Color(0xFFE8C99C).withValues(alpha: .05)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 24));
      return;
    }
  }

  @override
  bool shouldRepaint(covariant _DateForeground old) =>
      old.action != action || old.phase != phase || old.location != location;
}
