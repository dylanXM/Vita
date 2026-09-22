import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/theme.dart';
import '../../shared/widgets.dart';
import '../chat/chat_page.dart';
import '../chat/experience_sheet.dart';

class LifeDetailPage extends StatelessWidget {
  const LifeDetailPage({super.key, required this.companion});

  final Map<String, dynamic> companion;

  String get _id => companion['id'] as String? ?? '';
  String get _name => companion['name'] as String? ?? 'chat.companion'.tr;

  @override
  Widget build(BuildContext context) {
    final vita = context.vita;
    return Scaffold(
      backgroundColor: vita.pageBg,
      appBar: AppBar(
        leading: const VitaBackButton(),
        title: Text('contactDetail.title'.tr),
        shape: const Border(),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 28),
        children: [
          _ProfileHeader(
            companion: companion,
            onChat: () => _openChat(),
            onExperiences: () => _showExperiences(context),
          ),
          const SizedBox(height: 12),
          _Section(
            title: 'contactDetail.profile'.tr,
            rows: [
              _DetailRow(label: 'chat.city'.tr, value: _text('city')),
              _DetailRow(label: 'chat.occupation'.tr, value: _text('occupation')),
              _DetailRow(label: 'chat.relationship'.tr, value: _text('relationship_stage')),
              _DetailRow(label: 'chat.interests'.tr, value: _text('interests')),
            ],
          ),
          _Section(
            title: 'contactDetail.personality'.tr,
            rows: [
              _DetailRow(label: 'contactDetail.persona'.tr, value: _text('persona'), multiline: true),
              _DetailRow(label: 'contactDetail.appearance'.tr, value: _text('appearance'), multiline: true),
              _DetailRow(label: 'contactDetail.speakingStyle'.tr, value: _text('speaking_style'), multiline: true),
              _DetailRow(label: 'contactDetail.likes'.tr, value: _text('likes'), multiline: true),
              _DetailRow(label: 'contactDetail.dislikes'.tr, value: _text('dislikes'), multiline: true),
            ],
          ),
          _Section(
            title: 'contactDetail.life'.tr,
            rows: [
              _DetailRow(label: 'contactDetail.lifeHabits'.tr, value: _text('life_habits'), multiline: true),
              _DetailRow(label: 'contactDetail.lifeGoal'.tr, value: _text('life_goal'), multiline: true),
              _DetailRow(label: 'contactDetail.backstory'.tr, value: _text('backstory'), multiline: true),
            ],
          ),
          _TagsSection(tags: _tags()),
        ],
      ),
    );
  }

  String _text(String key) {
    final value = companion[key];
    if (value is String && value.trim().isNotEmpty) return value.trim();
    return 'contactDetail.notSet'.tr;
  }

  List<String> _tags() {
    final raw = companion['personality_tags'];
    if (raw is List) {
      return raw.whereType<String>().where((item) => item.trim().isNotEmpty).toList();
    }
    return const [];
  }

  void _openChat() {
    if (_id.isEmpty) return;
    Get.to(
      () => ChatPage(companionId: _id, name: _name, companion: companion),
      transition: Transition.cupertino,
      duration: const Duration(milliseconds: 300),
    );
  }

  void _showExperiences(BuildContext context) {
    if (_id.isEmpty) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.vita.surface,
      showDragHandle: true,
      builder: (_) => ExperienceSheet(
        companionId: _id,
        onCompleted: () async {},
      ),
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({
    required this.companion,
    required this.onChat,
    required this.onExperiences,
  });

  final Map<String, dynamic> companion;
  final VoidCallback onChat;
  final VoidCallback onExperiences;

  @override
  Widget build(BuildContext context) {
    final name = companion['name'] as String? ?? 'chat.companion'.tr;
    final city = (companion['city'] as String? ?? '').trim();
    final occupation = (companion['occupation'] as String? ?? '').trim();
    final subtitle = [city, occupation].where((item) => item.isNotEmpty).join(' · ');
    final persona = (companion['persona'] as String? ?? '').trim();
    final canChat = companion['can_chat'] != false;
    final friendshipActive = companion['friendship_active'] != false;

    return Container(
      color: context.vita.surface,
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
      child: Column(
        children: [
          VitaAvatar(
            name: name,
            radius: 42,
            imageUrl: companion['portrait_url'] as String?,
            borderRadius: BorderRadius.circular(18),
          ),
          const SizedBox(height: 12),
          Text(
            name,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: context.vita.text,
            ),
          ),
          if (subtitle.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(subtitle, style: context.vita.sub),
          ],
          const SizedBox(height: 10),
          _StatusPill(active: canChat && friendshipActive),
          if (persona.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(
              persona,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                height: 1.5,
                color: context.vita.text,
              ),
            ),
          ],
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: onChat,
                  icon: const Icon(Icons.chat_bubble_outline, size: 18),
                  label: Text('contactDetail.chat'.tr),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onExperiences,
                  icon: const Icon(Icons.auto_awesome_outlined, size: 18),
                  label: Text('experience.title'.tr),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.active});

  final bool active;

  @override
  Widget build(BuildContext context) {
    final color = active ? context.vita.green : context.vita.hint;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        active ? 'contactDetail.active'.tr : 'contactDetail.paused'.tr,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.rows});

  final String title;
  final List<Widget> rows;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(title, style: context.vita.sectionTitle),
          ),
          Container(
            color: context.vita.surface,
            child: Column(
              children: [
                for (var i = 0; i < rows.length; i++) ...[
                  if (i > 0) const Divider(height: 0.5, indent: 116),
                  rows[i],
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.label,
    required this.value,
    this.multiline = false,
  });

  final String label;
  final String value;
  final bool multiline;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        crossAxisAlignment: multiline ? CrossAxisAlignment.start : CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 88,
            child: Text(
              label,
              style: TextStyle(fontSize: 14, color: context.vita.subText),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(fontSize: 15, height: 1.45, color: context.vita.text),
            ),
          ),
        ],
      ),
    );
  }
}

class _TagsSection extends StatelessWidget {
  const _TagsSection({required this.tags});

  final List<String> tags;

  @override
  Widget build(BuildContext context) {
    if (tags.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text('contactDetail.tags'.tr, style: context.vita.sectionTitle),
          ),
          Container(
            width: double.infinity,
            color: context.vita.surface,
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: tags
                  .map(
                    (tag) => Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: context.vita.greenTint,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        tag.tr,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: context.vita.green,
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }
}
