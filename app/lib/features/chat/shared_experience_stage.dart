import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/theme.dart';
import '../../shared/media_image.dart';

/// One continuous scene: the person, the latest response and the user's next
/// action share a surface. Choices send real messages; they never auto-purchase.
class SharedExperienceStage extends StatelessWidget {
  const SharedExperienceStage(
      {super.key,
      required this.name,
      this.portrait,
      required this.title,
      required this.reply,
      required this.input,
      required this.onSend,
      required this.busy,
      this.actions = const [],
      this.lastAction = '',
      this.attachment,
      this.onHistory,
      this.onKeepsake});
  final String name, title, reply, lastAction;
  final String? portrait;
  final TextEditingController input;
  final Future<void> Function(String) onSend;
  final bool busy;
  final List<Map<String, String>> actions;
  final VoidCallback? onHistory, onKeepsake;
  final Widget? attachment;

  @override
  Widget build(BuildContext context) => Stack(children: [
        Positioned.fill(
            child: portrait?.isNotEmpty == true
                ? VitaMediaImage(
                    url: portrait!,
                    errorBuilder: (_, __, ___) =>
                        ColoredBox(color: context.vita.greenTint))
                : ColoredBox(color: context.vita.greenTint)),
        Positioned.fill(
            child: DecoratedBox(
                decoration: BoxDecoration(
                    gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
              Colors.black.withValues(alpha: .18),
              Colors.black.withValues(alpha: .45),
              Colors.black.withValues(alpha: .84)
            ])))),
        SafeArea(
            top: false,
            child: Column(children: [
              Padding(
                  padding: const EdgeInsets.all(20),
                  child: Row(children: [
                    Expanded(
                        child: Text(title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.w600))),
                    if (onHistory != null)
                      IconButton(
                          tooltip: 'moment.scene.history'.tr,
                          onPressed: onHistory,
                          icon: const Icon(Icons.history_outlined,
                              color: Colors.white)),
                    if (onKeepsake != null)
                      IconButton(
                          tooltip: 'moment.create'.tr,
                          onPressed: onKeepsake,
                          icon: const Icon(Icons.bookmark_border,
                              color: Colors.white)),
                  ])),
              Expanded(
                  child: SingleChildScrollView(
                      reverse: false,
                      padding: const EdgeInsets.fromLTRB(20, 80, 20, 16),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (lastAction.isNotEmpty)
                              Text(lastAction,
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      color: Colors.white.withValues(alpha: .7),
                                      height: 1.5)),
                            const SizedBox(height: 20),
                            if (attachment != null) ...[
                              attachment!,
                              const SizedBox(height: 16)
                            ],
                            Text(name,
                                style: TextStyle(
                                    color: Colors.white.withValues(alpha: .75),
                                    fontSize: 13)),
                            const SizedBox(height: 8),
                            SelectableText(reply,
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 21,
                                    height: 1.6,
                                    fontWeight: FontWeight.w500)),
                            if (busy)
                              Padding(
                                  padding: const EdgeInsets.only(top: 14),
                                  child: Text('moment.scene.responding'.tr,
                                      style: TextStyle(
                                          color: Colors.white
                                              .withValues(alpha: .7)))),
                            const SizedBox(height: 22),
                            for (final action in actions.take(2))
                              Padding(
                                  padding: const EdgeInsets.only(bottom: 10),
                                  child: OutlinedButton(
                                      onPressed: busy
                                          ? null
                                          : () =>
                                              onSend(action['message'] ?? ''),
                                      style: OutlinedButton.styleFrom(
                                          foregroundColor: Colors.white,
                                          disabledForegroundColor: Colors.white
                                              .withValues(alpha: .4),
                                          side: BorderSide(
                                              color: Colors.white
                                                  .withValues(alpha: .35)),
                                          minimumSize:
                                              const Size(double.infinity, 48),
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 16, vertical: 14)),
                                      child: Align(
                                          alignment: Alignment.centerLeft,
                                          child: Text(action['label'] ?? '',
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis)))),
                          ]))),
              Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: Row(children: [
                    Expanded(
                        child: TextField(
                            controller: input,
                            enabled: !busy,
                            maxLength: 2000,
                            minLines: 1,
                            maxLines: 3,
                            style: const TextStyle(color: Colors.white),
                            decoration: InputDecoration(
                                counterText: '',
                                hintText: 'moment.messageHint'.tr,
                                hintStyle: TextStyle(
                                    color: Colors.white.withValues(alpha: .6)),
                                filled: true,
                                fillColor: Colors.white.withValues(alpha: .12),
                                border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(20),
                                    borderSide: BorderSide.none)),
                            onSubmitted: (text) => onSend(text))),
                    const SizedBox(width: 8),
                    IconButton.filled(
                        tooltip: 'moment.scene.send'.tr,
                        onPressed: busy ? null : () => onSend(input.text),
                        icon: const Icon(Icons.north_east))
                  ])),
            ])),
      ]);
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
