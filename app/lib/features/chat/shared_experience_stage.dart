import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/theme.dart';
import 'experience_environment.dart';
import '../../shared/widgets.dart';
import '../auth/auth_controller.dart';

List<Map<String, dynamic>> chronologicalSceneMessages(
    Iterable<Map<String, dynamic>> messages) {
  final unique = <String, Map<String, dynamic>>{};
  for (final m in messages) {
    final id = '${m['id'] ?? ''}';
    if (id.isNotEmpty) unique[id] = m;
  }
  final result = unique.values.toList();
  result.sort((a, b) {
    final at = DateTime.tryParse('${a['created_at'] ?? ''}');
    final bt = DateTime.tryParse('${b['created_at'] ?? ''}');
    if (at == null && bt == null) return 0;
    if (at == null) return -1;
    if (bt == null) return 1;
    final order = at.compareTo(bt);
    return order == 0 ? '${a['id']}'.compareTo('${b['id']}') : order;
  });
  return result;
}

class SharedExperienceStage extends StatefulWidget {
  const SharedExperienceStage(
      {super.key,
      required this.name,
      this.portrait,
      required this.title,
      required this.reply,
      required this.input,
      required this.onSend,
      required this.busy,
      this.messages = const [],
      this.actions = const [],
      this.lastAction = '',
      this.location = 'general',
      this.situation = '',
      this.focus = 'ambient',
      this.attachment,
      this.journey,
      this.onHistory,
      this.onKeepsake,
      this.backgroundUrl,
      this.compactDate = false});
  final String name, title, reply, lastAction, location, situation, focus;
  final bool compactDate;
  final String? portrait, backgroundUrl;
  final TextEditingController input;
  final Future<void> Function(String) onSend;
  final bool busy;
  final List<Map<String, dynamic>> messages;
  final List<Map<String, String>> actions;
  final VoidCallback? onHistory, onKeepsake;
  final Widget? attachment, journey;
  @override
  State<SharedExperienceStage> createState() => _SharedExperienceStageState();
}

class _SharedExperienceStageState extends State<SharedExperienceStage> {
  final _scroll = ScrollController();
  String _signature = '';
  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _followLatest(List<Map<String, dynamic>> messages) {
    final signature = messages
            .map((m) => '${m['id']}:${m['content']}:${m['delivery_status']}')
            .join('|') +
        '${widget.busy}';
    if (signature == _signature) return;
    final first = _signature.isEmpty;
    final nearEnd = !_scroll.hasClients || _scroll.position.extentAfter < 80;
    _signature = signature;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          !_scroll.hasClients ||
          _scroll.position.maxScrollExtent <= 0) return;
      if (first || nearEnd) _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  Widget _line(Map<String, dynamic> message) {
    final user = message['sender_type'] == 'user';
    final vita = context.vita;
    final avatarName = user ? '' : widget.name;
    final avatar = user
        ? (Get.isRegistered<AuthController>()
            ? AuthController.to.avatarUrl
            : null)
        : widget.portrait;
    final bubble = Flexible(
        child: Container(
            constraints: BoxConstraints(
                maxWidth: MediaQuery.sizeOf(context).width * .66),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
                color: user ? vita.greenTint : vita.surface,
                border: Border.all(
                    color: user
                        ? vita.green.withValues(alpha: .18)
                        : vita.text.withValues(alpha: .06)),
                borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(20),
                    topRight: const Radius.circular(20),
                    bottomLeft: Radius.circular(user ? 20 : 7),
                    bottomRight: Radius.circular(user ? 7 : 20))),
            child: SelectableText('${message['content'] ?? ''}',
                style:
                    TextStyle(color: vita.text, fontSize: 16, height: 1.4))));
    final portrait = VitaAvatar(
        name: avatarName,
        radius: 22,
        imageUrl: avatar,
        borderRadius: BorderRadius.circular(10));
    return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
            mainAxisAlignment:
                user ? MainAxisAlignment.end : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!user) ...[portrait, const SizedBox(width: 8)],
              bubble,
              if (user) ...[const SizedBox(width: 8), portrait],
            ]));
  }

  @override
  Widget build(BuildContext context) =>
      LayoutBuilder(builder: (context, constraints) {
        final keyboard = MediaQuery.viewInsetsOf(context).bottom > 0;
        final messages = chronologicalSceneMessages(widget.messages);
        if (messages.isEmpty && widget.reply.isNotEmpty)
          messages.add({
            'id': 'opening',
            'sender_type': 'assistant',
            'content': widget.reply
          });
        _followLatest(messages);
        return DecoratedBox(
            decoration: BoxDecoration(
                gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                  ExperienceEnvironment.background(widget.location),
                  Color.lerp(ExperienceEnvironment.background(widget.location),
                      Colors.black, .30)!
                ])),
            child: SafeArea(
                top: false,
                child: Column(children: [
                  if (!widget.compactDate)
                    Padding(
                        padding: const EdgeInsets.fromLTRB(16, 4, 8, 0),
                        child: Row(children: [
                          Expanded(
                              child: Text(widget.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 18,
                                      fontWeight: FontWeight.w600))),
                          if (widget.onHistory != null)
                            IconButton(
                                tooltip: 'moment.scene.history'.tr,
                                onPressed: widget.onHistory,
                                icon: const Icon(Icons.history_outlined,
                                    color: Colors.white)),
                          if (widget.onKeepsake != null)
                            IconButton(
                                tooltip: 'moment.create'.tr,
                                onPressed: widget.onKeepsake,
                                icon: const Icon(Icons.bookmark_border,
                                    color: Colors.white))
                        ])),
                  if (constraints.maxHeight >= 240)
                    Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: ExperienceEnvironment(
                            height: (constraints.maxHeight *
                                    (widget.compactDate ? .28 : .27))
                                .clamp(48.0, 200.0),
                            location: widget.location,
                            name: widget.name,
                            portrait: widget.portrait,
                            backgroundUrl: widget.backgroundUrl,
                            sceneFirst: widget.compactDate,
                            focus: widget.focus)),
                  if (widget.situation.isNotEmpty &&
                      !keyboard &&
                      constraints.maxHeight >= 400)
                    Padding(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 10),
                        child: Text(widget.situation,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: Colors.white.withValues(alpha: .85),
                                fontSize: 14,
                                height: 1.4))),
                  Expanded(
                      child: ListView(
                          controller: _scroll,
                          reverse: false,
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                          children: [
                        if (widget.attachment != null)
                          Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: widget.attachment!),
                        ...messages.map(_line),
                        if (widget.compactDate &&
                            !keyboard &&
                            widget.journey != null)
                          widget.journey!,
                        if (widget.busy)
                          Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Text('moment.scene.responding'.tr,
                                  style: const TextStyle(
                                      color: Colors.white60, fontSize: 13)))
                      ])),
                  if (!widget.compactDate &&
                      !keyboard &&
                      constraints.maxHeight >= 400 &&
                      widget.journey != null)
                    Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: widget.journey!),
                  if (!widget.busy &&
                      !keyboard &&
                      constraints.maxHeight >= 400 &&
                      widget.actions.isNotEmpty)
                    SizedBox(
                        height: 48,
                        child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            itemCount: widget.actions.take(2).length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(width: 8),
                            itemBuilder: (_, index) => OutlinedButton(
                                onPressed: () => widget.onSend(
                                    widget.actions[index]['message'] ?? ''),
                                style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.white,
                                    side: const BorderSide(
                                        color: Colors.white30)),
                                child: ConstrainedBox(
                                    constraints:
                                        const BoxConstraints(maxWidth: 180),
                                    child: Text(widget.actions[index]['label'] ?? '', maxLines: 1, overflow: TextOverflow.ellipsis))))),
                  if (widget.compactDate && widget.onKeepsake != null)
                    Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Align(
                            alignment: AlignmentDirectional.centerStart,
                            child: TextButton.icon(
                                onPressed: widget.onKeepsake,
                                icon:
                                    const Icon(Icons.bookmark_border, size: 16),
                                label: Text('moment.create'.tr,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis),
                                style: TextButton.styleFrom(
                                    foregroundColor: Colors.white70)))),
                  Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                      child: Row(children: [
                        Expanded(
                            child: TextField(
                                controller: widget.input,
                                enabled: !widget.busy,
                                maxLength: 2000,
                                minLines: 1,
                                maxLines: constraints.maxHeight < 400 ? 1 : 5,
                                textInputAction: TextInputAction.send,
                                style: TextStyle(
                                    color: context.vita.text,
                                    fontSize: 16,
                                    height: 1.4),
                                decoration: InputDecoration(
                                    counterText: '',
                                    hintText: 'chat.message'.tr,
                                    hintStyle: TextStyle(
                                        color: context.vita.hint,
                                        fontSize: 16,
                                        height: 1.4),
                                    isCollapsed: true,
                                    contentPadding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 8),
                                    filled: true,
                                    fillColor: context.vita.surface,
                                    border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(20),
                                        borderSide: BorderSide.none),
                                    enabledBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(20),
                                        borderSide: BorderSide.none),
                                    focusedBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(20),
                                        borderSide: BorderSide.none)),
                                onSubmitted: widget.onSend)),
                        const SizedBox(width: 8),
                        IconButton.filled(
                            tooltip: 'moment.scene.send'.tr,
                            onPressed: widget.busy
                                ? null
                                : () => widget.onSend(widget.input.text),
                            icon: const Icon(Icons.north_east))
                      ])),
                ])));
      });
}

List<Map<String, String>> sharedSceneActions(Map<String, dynamic>? message) {
  final payload = message?['payload'];
  final raw = payload is Map ? payload['scene_actions'] : null;
  if (raw is! List) return [];
  return raw
      .whereType<Map>()
      .where((a) => a['label'] is String && a['message'] is String)
      .take(2)
      .map((a) => <String, String>{
            'label': a['label'] as String,
            'message': a['message'] as String
          })
      .toList();
}

String sharedSceneSituation(Map<String, dynamic>? message) {
  final payload = message?['payload'];
  final situation = payload is Map ? payload['scene_situation'] : null;
  return situation is String ? situation : '';
}

String sharedSceneFocus(Map<String, dynamic>? message) {
  final payload = message?['payload'];
  final focus = payload is Map ? payload['scene_focus'] : null;
  return focus is String &&
          ['ambient', 'ta', 'window', 'table', 'screen'].contains(focus)
      ? focus
      : 'ambient';
}
