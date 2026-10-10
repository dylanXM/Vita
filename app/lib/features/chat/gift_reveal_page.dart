import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/theme.dart';
import '../../shared/media_image.dart';
import 'gift_visual.dart';

/// The paid gift is opened in a scene; the recorded chat message is only one
/// trace of this interaction, not its entire outcome.
class GiftRevealPage extends StatefulWidget {
  const GiftRevealPage(
      {super.key,
      required this.name,
      required this.response,
      this.portraitUrl});

  final String name;
  final String? portraitUrl;
  final Map<String, dynamic> response;

  @override
  State<GiftRevealPage> createState() => _GiftRevealPageState();
}

class _GiftRevealPageState extends State<GiftRevealPage> {
  bool _opened = false;

  @override
  Widget build(BuildContext context) {
    final product = widget.response['product'] is Map
        ? widget.response['product'] as Map
        : const {};
    final result = widget.response['result'] is Map
        ? widget.response['result'] as Map
        : const {};
    final giftIcon =
        giftVisualIcon('${product['key'] ?? result['product_key'] ?? ''}');
    final reaction = '${result['reaction'] ?? ''}'.trim();
    final giftName = '${product['name_key'] ?? 'gift.sent.title'}'.tr;
    final portrait = widget.portraitUrl ?? '';
    return Scaffold(
      backgroundColor: const Color(0xFF221B24),
      body: SafeArea(
          child: Stack(children: [
        Positioned.fill(
            child: AnimatedContainer(
          duration: const Duration(milliseconds: 750),
          decoration: BoxDecoration(
              gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: _opened
                ? [const Color(0xFF955A67), const Color(0xFF221B24)]
                : [const Color(0xFF66506C), const Color(0xFF221B24)],
          )),
        )),
        if (portrait.isNotEmpty)
          Positioned.fill(
              child: AnimatedSlide(
            duration: const Duration(milliseconds: 950),
            curve: Curves.easeOutCubic,
            offset: _opened ? const Offset(-.035, 0) : Offset.zero,
            child: AnimatedScale(
              duration: const Duration(milliseconds: 950),
              curve: Curves.easeOutCubic,
              scale: _opened ? 1.14 : 1,
              child: VitaMediaImage(
                  url: portrait,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const SizedBox.expand()),
            ),
          )),
        Positioned.fill(
            child: AnimatedContainer(
          duration: const Duration(milliseconds: 700),
          decoration: BoxDecoration(
              gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.black.withValues(alpha: .58),
              Colors.black.withValues(alpha: _opened ? .04 : .32),
              const Color(0xFF221B24).withValues(alpha: .98)
            ],
            stops: const [0, .39, .81],
          )),
        )),
        Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 20, 0),
            child: Row(children: [
              IconButton(
                  onPressed: () => Get.back(),
                  icon: const Icon(Icons.close_rounded, color: Colors.white)),
              const SizedBox(width: 4),
              Expanded(
                  child: Text(giftName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w700))),
            ]),
          ),
          const Spacer(),
          if (!_opened)
            GestureDetector(
              onTap: () => setState(() => _opened = true),
              child: Column(children: [
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: .82, end: 1),
                  duration: const Duration(milliseconds: 950),
                  curve: Curves.elasticOut,
                  builder: (context, scale, child) =>
                      Transform.scale(scale: scale, child: child),
                  child: Container(
                      width: 150,
                      height: 150,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withValues(alpha: .13),
                          border: Border.all(
                              color: Colors.white.withValues(alpha: .34)),
                          boxShadow: [
                            BoxShadow(
                                color: context.vita.green.withValues(alpha: .3),
                                blurRadius: 40)
                          ]),
                      child: const SizedBox.shrink()),
                ),
                const SizedBox(height: 24),
                Text('gift.reveal.open'.tr,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600)),
              ]),
            ),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.fromLTRB(26, 0, 26, 28),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 400),
              child: _opened
                  ? Column(
                      key: const ValueKey('opened'),
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                          Row(children: [
                            Icon(giftIcon, color: Colors.white, size: 28),
                            const SizedBox(width: 10),
                            Expanded(
                                child: Text(widget.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 30,
                                        fontWeight: FontWeight.w700))),
                          ]),
                          const SizedBox(height: 12),
                          Text(
                              reaction.isEmpty
                                  ? 'gift.reveal.fallback'.tr
                                  : reaction,
                              maxLines: 5,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  color: Colors.white.withValues(alpha: .94),
                                  fontSize: 17,
                                  height: 1.5)),
                          const SizedBox(height: 25),
                          _GiftAction(
                              label: 'gift.reveal.chat'.tr,
                              icon: Icons.chat_bubble_outline_rounded,
                              onTap: () => Get.back(result: 'chat')),
                          const SizedBox(height: 10),
                          _GiftAction(
                              label: 'gift.reveal.world'.tr,
                              icon: Icons.public_rounded,
                              onTap: () => Get.back(result: 'world')),
                        ])
                  : Text('gift.reveal.before'.tr,
                      key: const ValueKey('closed'),
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: .82),
                          fontSize: 17,
                          height: 1.5)),
            ),
          ),
        ]),
        Positioned.fill(
          child: IgnorePointer(
            child: AnimatedAlign(
              duration: const Duration(milliseconds: 1050),
              curve: Curves.easeInOutCubic,
              alignment: _opened
                  ? const Alignment(.68, -.38)
                  : const Alignment(0, .02),
              child: AnimatedScale(
                duration: const Duration(milliseconds: 1050),
                curve: Curves.easeOutBack,
                scale: _opened ? .63 : 1,
                child: Icon(giftIcon, color: const Color(0xFFFFD5DA), size: 80),
              ),
            ),
          ),
        ),
      ])),
    );
  }
}

class _GiftAction extends StatelessWidget {
  const _GiftAction(
      {required this.label, required this.icon, required this.onTap});
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.white.withValues(alpha: .14),
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            height: 58,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withValues(alpha: .27))),
            child: Row(children: [
              Icon(icon, color: Colors.white, size: 20),
              const SizedBox(width: 12),
              Expanded(
                  child: Text(label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w600))),
              const Icon(Icons.arrow_outward_rounded,
                  color: Colors.white70, size: 18),
            ]),
          ),
        ),
      );
}
