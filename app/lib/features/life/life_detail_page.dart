import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/theme.dart';
import '../../shared/widgets.dart';
import '../chat/chat_page.dart';
import '../chat/companion_moment_page.dart';
import '../chat/experience_sheet.dart';
import 'companion_story_section.dart';

class LifeDetailPage extends StatelessWidget {
  const LifeDetailPage({super.key, required this.companion});

  final Map<String, dynamic> companion;

  String get _id => companion['id'] as String? ?? '';
  String get _name => companion['name'] as String? ?? 'chat.companion'.tr;

  String? _value(String key) {
    final value = companion[key];
    if (value is String && value.trim().isNotEmpty) return value.trim();
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final vita = context.vita;
    final facts = <(String, String)>[
      if (_value('city') case final city?) ('chat.city'.tr, city),
      if (_value('occupation') case final job?) ('chat.occupation'.tr, job),
      if (_value('relationship_stage') case final stage?)
        ('chat.relationship'.tr, stage),
    ];
    final personality = <(String, String)>[
      if (_value('appearance') case final value?)
        ('contactDetail.appearance'.tr, value),
      if (_value('speaking_style') case final value?)
        ('contactDetail.speakingStyle'.tr, value),
      if (_value('likes') case final value?) ('contactDetail.likes'.tr, value),
      if (_value('dislikes') case final value?)
        ('contactDetail.dislikes'.tr, value),
      if (_value('interests') case final value?) ('chat.interests'.tr, value),
    ];
    final life = <(String, String)>[
      if (_value('life_habits') case final value?)
        ('contactDetail.lifeHabits'.tr, value),
      if (_value('life_goal') case final value?)
        ('contactDetail.lifeGoal'.tr, value),
      if (_value('backstory') case final value?)
        ('contactDetail.backstory'.tr, value),
    ];
    final tags = (companion['personality_tags'] as List?)
            ?.whereType<String>()
            .map((tag) => tag.trim())
            .where((tag) => tag.isNotEmpty)
            .toList() ??
        const <String>[];

    return Scaffold(
      backgroundColor: vita.pageBg,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            backgroundColor: vita.pageBg,
            surfaceTintColor: Colors.transparent,
            leading: const VitaBackButton(),
            title: Text(_name),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 32),
            sliver: SliverList.list(children: [
              _Portrait(companion: companion, name: _name),
              const SizedBox(height: 20),
              if (_value('persona') case final persona?) ...[
                Text(persona,
                    style: TextStyle(
                        color: vita.text,
                        fontSize: 18,
                        fontWeight: FontWeight.w500,
                        height: 1.5)),
                const SizedBox(height: 18),
              ],
              if (facts.isNotEmpty) ...[
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final (label, value) in facts)
                      _FactChip(label: label, value: value),
                  ],
                ),
                const SizedBox(height: 22),
              ],
              Row(children: [
                Expanded(
                  child: _ActionCard(
                    icon: Icons.chat_bubble_outline_rounded,
                    label: 'contactDetail.chat'.tr,
                    filled: true,
                    onTap: _id.isEmpty ? null : _openChat,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _ActionCard(
                    icon: Icons.auto_awesome_outlined,
                    label: 'experience.title'.tr,
                    filled: false,
                    onTap: _id.isEmpty ? null : () => _showExperiences(context),
                  ),
                ),
              ]),
              if (tags.isNotEmpty) ...[
                const SizedBox(height: 30),
                _SectionHeading(title: 'contactDetail.tags'.tr),
                const SizedBox(height: 12),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final tag in tags)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 13, vertical: 8),
                      decoration: BoxDecoration(
                        color: vita.greenTint,
                        borderRadius: BorderRadius.circular(100),
                      ),
                      child: Text(tag.tr,
                          style: TextStyle(color: vita.green, fontSize: 13)),
                    ),
                ]),
              ],
              if (personality.isNotEmpty) ...[
                const SizedBox(height: 30),
                _SectionHeading(title: 'contactDetail.personality'.tr),
                const SizedBox(height: 12),
                _StoryCards(items: personality),
              ],
              if (life.isNotEmpty) ...[
                const SizedBox(height: 30),
                _SectionHeading(title: 'contactDetail.life'.tr),
                const SizedBox(height: 12),
                _StoryCards(items: life),
              ],
              if (_id.isNotEmpty)
                CompanionStorySection(
                  companionId: _id,
                  companionName: _name,
                  avatarUrl: companion['portrait_url'] as String?,
                  onChat: _openChat,
                  onExperience: (key) =>
                      _showExperiences(context, recommendedKey: key),
                ),
            ]),
          ),
        ],
      ),
    );
  }

  void _openChat() {
    Get.to(
      () => ChatPage(companionId: _id, name: _name, companion: companion),
      transition: Transition.cupertino,
      duration: const Duration(milliseconds: 300),
    );
  }

  Future<void> _showExperiences(BuildContext context,
      {String? recommendedKey}) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.vita.surface,
      showDragHandle: true,
      builder: (_) => ExperienceSheet(
        companionId: _id,
        recommendedProductKey: recommendedKey,
        onCompleted: () async {},
        onResult: (response) async {
          final result = response['result'];
          final product = response['product'];
          final eventId = result is Map ? result['event_id'] : null;
          if (context.mounted &&
              product is Map &&
              product['category'] == 'date' &&
              eventId is String) {
            Navigator.of(context).pop();
            Get.to(() => CompanionMomentPage(
                  companionId: _id,
                  eventId: eventId,
                  name: _name,
                  avatarUrl: companion['portrait_url'] as String?,
                ));
          }
        },
      ),
    );
  }
}

class _Portrait extends StatelessWidget {
  const _Portrait({required this.companion, required this.name});

  final Map<String, dynamic> companion;
  final String name;

  @override
  Widget build(BuildContext context) {
    final vita = context.vita;
    final url = companion['portrait_url'] as String?;
    final active = companion['can_chat'] != false &&
        companion['friendship_active'] != false;
    return ClipRRect(
      borderRadius: BorderRadius.circular(26),
      child: SizedBox(
        height: 286,
        child: Stack(fit: StackFit.expand, children: [
          if (url != null && url.isNotEmpty)
            Image.network(url,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _PortraitFallback(name: name))
          else
            _PortraitFallback(name: name),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.transparent, Color(0xCC11101B)],
                stops: [.42, 1],
              ),
            ),
          ),
          Positioned(
            left: 22,
            right: 22,
            bottom: 20,
            child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Expanded(
                child: Text(name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 32,
                        fontWeight: FontWeight.w700,
                        height: 1.08)),
              ),
              const SizedBox(width: 10),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .16),
                  border:
                      Border.all(color: Colors.white.withValues(alpha: .28)),
                  borderRadius: BorderRadius.circular(100),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: active ? vita.green : Colors.white70,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                      active
                          ? 'contactDetail.active'.tr
                          : 'contactDetail.paused'.tr,
                      style:
                          const TextStyle(color: Colors.white, fontSize: 11)),
                ]),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _PortraitFallback extends StatelessWidget {
  const _PortraitFallback({required this.name});
  final String name;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: context.vita.greenTint,
      alignment: Alignment.center,
      child: VitaAvatar(name: name, radius: 80),
    );
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.icon,
    required this.label,
    required this.filled,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final bool filled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final vita = context.vita;
    final color = filled ? Colors.white : vita.text;
    return Material(
      color: filled ? vita.green : vita.surface,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 17),
          child: Row(children: [
            Icon(icon, color: color, size: 21),
            const SizedBox(width: 9),
            Expanded(
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style:
                        TextStyle(color: color, fontWeight: FontWeight.w600))),
            Icon(Icons.arrow_outward_rounded, color: color, size: 16),
          ]),
        ),
      ),
    );
  }
}

class _FactChip extends StatelessWidget {
  const _FactChip({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final vita = context.vita;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: vita.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text.rich(TextSpan(children: [
        TextSpan(text: '$label  ', style: TextStyle(color: vita.subText)),
        TextSpan(
            text: value,
            style: TextStyle(color: vita.text, fontWeight: FontWeight.w600)),
      ])),
    );
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    final vita = context.vita;
    return Row(children: [
      Container(
        width: 3,
        height: 18,
        decoration: BoxDecoration(
          color: vita.green,
          borderRadius: BorderRadius.circular(3),
        ),
      ),
      const SizedBox(width: 10),
      Text(title,
          style: TextStyle(
              color: vita.text, fontSize: 17, fontWeight: FontWeight.w700)),
    ]);
  }
}

class _StoryCards extends StatelessWidget {
  const _StoryCards({required this.items});
  final List<(String, String)> items;

  @override
  Widget build(BuildContext context) {
    final vita = context.vita;
    return Column(children: [
      for (final (label, value) in items)
        Padding(
          padding: const EdgeInsets.only(bottom: 9),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(17, 15, 17, 17),
            decoration: BoxDecoration(
              color: vita.surface,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(color: vita.green, fontSize: 12)),
                const SizedBox(height: 8),
                Text(value,
                    style: TextStyle(
                        color: vita.text, fontSize: 15, height: 1.55)),
              ],
            ),
          ),
        ),
    ]);
  }
}
