import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/api_client.dart';
import '../../core/notice.dart';
import '../../core/theme.dart';
import '../../shared/media_image.dart';

/// An in-world interaction, rather than a confirmation dialog for a visit.
class WorldVisitPage extends StatefulWidget {
  const WorldVisitPage(
      {super.key,
      required this.companion,
      required this.scene,
      required this.onVisited});

  final Map<String, dynamic> companion;
  final Map<String, dynamic> scene;
  final Future<void> Function() onVisited;

  @override
  State<WorldVisitPage> createState() => _WorldVisitPageState();
}

class _WorldVisitPageState extends State<WorldVisitPage> {
  bool _submitting = false;
  Map<String, dynamic>? _result;

  Future<void> _choose(String choice) async {
    if (_submitting || _result != null) return;
    setState(() => _submitting = true);
    try {
      final id = '${widget.companion['id'] ?? ''}';
      final data = await ApiClient.instance
          .post('/v1/companions/$id/world/visit', data: {'choice': choice});
      if (!mounted || data is! Map) return;
      setState(() => _result = Map<String, dynamic>.from(data));
      await widget.onVisited();
    } on ApiException catch (error) {
      VitaNotice.error('world.visit'.tr, error.message);
    } catch (_) {
      VitaNotice.error('world.visit'.tr, 'world.actionFailed'.tr);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final place =
        widget.scene['place'] is Map ? widget.scene['place'] as Map : const {};
    final event =
        widget.scene['event'] is Map ? widget.scene['event'] as Map : null;
    final gift = widget.scene['recent_gift'] is Map
        ? widget.scene['recent_gift'] as Map
        : null;
    final kind = '${place['kind'] ?? 'home'}';
    final name = '${widget.companion['name'] ?? ''}';
    final portrait = '${widget.companion['portrait_url'] ?? ''}';
    final visited = widget.scene['visited_today'] == true;
    final completed = _result != null || visited;
    final choice = '${_result?['choice'] ?? ''}';
    final reaction = '${_result?['reaction'] ?? ''}'.trim();
    final colors = switch (kind) {
      'cafe' => [const Color(0xFF8C5D48), const Color(0xFF211923)],
      'work' => [const Color(0xFF526477), const Color(0xFF171A29)],
      'outdoors' => [const Color(0xFF6A806D), const Color(0xFF182624)],
      'story' => [const Color(0xFF80637B), const Color(0xFF231C31)],
      _ => [const Color(0xFF726388), const Color(0xFF1D1A2B)],
    };
    final background = _result == null ? colors.first : context.vita.green;
    return Scaffold(
      backgroundColor: colors.last,
      body: SafeArea(
          child: Stack(children: [
        Positioned.fill(
            child: AnimatedContainer(
          duration: const Duration(milliseconds: 650),
          decoration: BoxDecoration(
              gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [background, colors.last],
          )),
        )),
        if (portrait.isNotEmpty)
          Positioned.fill(
              child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 1, end: _result == null ? 1 : 1.08),
            duration: const Duration(milliseconds: 850),
            curve: Curves.easeOutCubic,
            builder: (context, scale, child) => Transform.scale(
                alignment: Alignment.topCenter, scale: scale, child: child),
            child: VitaMediaImage(
                url: portrait,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const SizedBox.expand()),
          )),
        Positioned.fill(
            child: DecoratedBox(
                decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.black.withValues(alpha: .44),
              Colors.transparent,
              Colors.black.withValues(alpha: .4),
              colors.last.withValues(alpha: .98)
            ],
            stops: const [0, .28, .52, .83],
          ),
        ))),
        Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 20, 0),
            child: Row(children: [
              IconButton(
                  onPressed: () => Get.back(),
                  icon: const Icon(Icons.arrow_back_ios_new_rounded,
                      size: 19, color: Colors.white)),
              const SizedBox(width: 4),
              Expanded(
                  child: Text('${place['title'] ?? 'world.place.home'}'.tr,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w700))),
              if (gift != null && '${gift['emoji'] ?? ''}'.isNotEmpty)
                Text('${gift['emoji']}', style: const TextStyle(fontSize: 25)),
            ]),
          ),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.fromLTRB(26, 0, 26, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 350),
                  child: completed
                      ? Row(key: const ValueKey('after'), children: [
                          AnimatedContainer(
                              duration: const Duration(milliseconds: 500),
                              width: 37,
                              height: 37,
                              decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.white.withValues(alpha: .18)),
                              child: Icon(
                                  choice == 'ask'
                                      ? Icons.record_voice_over_rounded
                                      : Icons.favorite_rounded,
                                  color: Colors.white,
                                  size: 19)),
                          const SizedBox(width: 10),
                          Expanded(
                              child: Text(name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 28,
                                      fontWeight: FontWeight.w700))),
                        ])
                      : Text(name,
                          key: const ValueKey('before'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 32,
                              fontWeight: FontWeight.w700)),
                ),
                const SizedBox(height: 12),
                Text(
                    completed
                        ? reaction.isNotEmpty
                            ? reaction
                            : visited && _result == null
                                ? 'world.alreadyVisited'.tr
                                : choice == 'ask'
                                    ? 'world.choiceAskResult'.tr
                                    : 'world.choiceStayResult'.tr
                        : '${event?['title'] ?? place['description'] ?? 'world.ready'}'
                            .tr,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: .94),
                        fontSize: 17,
                        height: 1.5)),
                const SizedBox(height: 23),
                if (!completed) ...[
                  _SceneChoice(
                      label: 'world.choiceStay'.tr,
                      detail: 'world.choiceStayHint'.tr,
                      icon: Icons.chair_alt_rounded,
                      onTap: _submitting ? null : () => _choose('stay')),
                  const SizedBox(height: 9),
                  _SceneChoice(
                      label: 'world.choiceAsk'.tr,
                      detail: 'world.choiceAskHint'.tr,
                      icon: Icons.question_answer_rounded,
                      onTap: _submitting ? null : () => _choose('ask')),
                ] else
                  _SceneChoice(
                      label: 'world.openChat'.tr,
                      detail: 'world.sceneContinue'.tr,
                      icon: Icons.arrow_forward_rounded,
                      onTap: () => Get.back(result: 'chat')),
                const SizedBox(height: 12),
                Row(children: [
                  TextButton(
                      onPressed: () => Get.back(result: 'gift'),
                      child: Text('world.giveGift'.tr,
                          style: const TextStyle(color: Colors.white))),
                  const SizedBox(width: 12),
                  TextButton(
                      onPressed: () => Get.back(result: 'note'),
                      child: Text('world.leaveNote'.tr,
                          style: const TextStyle(color: Colors.white))),
                ]),
              ],
            ),
          ),
        ]),
        if (_submitting)
          Positioned(
              top: 66,
              right: 24,
              child: const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))),
      ])),
    );
  }
}

class _SceneChoice extends StatelessWidget {
  const _SceneChoice(
      {required this.label,
      required this.detail,
      required this.icon,
      required this.onTap});
  final String label;
  final String detail;
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.white.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(17),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(17),
          child: Container(
            height: 74,
            padding: const EdgeInsets.symmetric(horizontal: 17),
            decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(17),
                border: Border.all(color: Colors.white.withValues(alpha: .28))),
            child: Row(children: [
              Icon(icon, color: Colors.white, size: 22),
              const SizedBox(width: 15),
              Expanded(
                  child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w700)),
                    const SizedBox(height: 3),
                    Text(detail,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: Colors.white.withValues(alpha: .72),
                            fontSize: 12)),
                  ])),
              const Icon(Icons.arrow_outward_rounded,
                  color: Colors.white70, size: 18),
            ]),
          ),
        ),
      );
}
