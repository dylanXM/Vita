import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/analytics_service.dart';
import '../../core/api_client.dart';
import '../../core/theme.dart';
import '../../shared/widgets.dart';
import '../chat/chat_list_controller.dart';
import 'companion_create_page.dart';

enum AICompanionCreateMode { description, meet }

class CompanionCreateMethodPage extends StatelessWidget {
  const CompanionCreateMethodPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.vita.pageBg,
      appBar: AppBar(title: Text('companion.create.chooseMethod'.tr)),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 12),
        children: [
          _method(
              context,
              Icons.dashboard_outlined,
              'companion.create.method.template',
              'companion.create.method.templateDesc',
              () => Get.to(() => const CompanionCreatePage())),
          _method(
              context,
              Icons.edit_note,
              'companion.create.method.description',
              'companion.create.method.descriptionDesc',
              () => Get.to(() => const AICompanionCreatePage(
                  mode: AICompanionCreateMode.description))),
          _method(
              context,
              Icons.person_search_outlined,
              'companion.create.method.meet',
              'companion.create.method.meetDesc',
              () => Get.to(() => const AICompanionCreatePage(
                  mode: AICompanionCreateMode.meet))),
        ],
      ),
    );
  }

  Widget _method(BuildContext context, IconData icon, String title,
      String subtitle, VoidCallback onTap) {
    return Material(
      color: context.vita.surface,
      child: ListTile(
        minTileHeight: 76,
        leading: Icon(icon, color: context.vita.green, size: 28),
        title: Text(title.tr,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(subtitle.tr),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}

class AICompanionCreatePage extends StatefulWidget {
  const AICompanionCreatePage({required this.mode, super.key});

  final AICompanionCreateMode mode;

  @override
  State<AICompanionCreatePage> createState() => _AICompanionCreatePageState();
}

class _AICompanionCreatePageState extends State<AICompanionCreatePage> {
  final _description = TextEditingController();
  final _characterName = TextEditingController();
  final Map<String, TextEditingController> _fields = {
    for (final key in const [
      'name',
      'persona',
      'appearance',
      'city',
      'occupation',
      'interests',
      'personality_tags',
      'speaking_style',
      'likes',
      'dislikes',
      'life_habits',
      'life_goal',
      'backstory'
    ])
      key: TextEditingController(),
  };
  String _gender = 'custom';
  String _relationship = 'stranger';
  String? _imagePath;
  String? _documentPath;
  String? _avatarMediaId;
  bool _busy = false;
  bool _hasDraft = false;

  @override
  void dispose() {
    _description.dispose();
    _characterName.dispose();
    for (final controller in _fields.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _pickImage() async {
    final image = await ImagePicker().pickImage(
        source: ImageSource.gallery, imageQuality: 92, maxWidth: 2048);
    if (image != null && mounted) setState(() => _imagePath = image.path);
  }

  Future<void> _pickDocument() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'docx', 'txt'],
      allowMultiple: false,
    );
    final path = result?.files.single.path;
    if (path != null && mounted) setState(() => _documentPath = path);
  }

  Future<void> _generate() async {
    if (_imagePath == null) {
      Get.snackbar('companion.create.imageRequired'.tr,
          'companion.create.imageRequiredMessage'.tr);
      return;
    }
    if (widget.mode == AICompanionCreateMode.description &&
        _description.text.trim().isEmpty) {
      Get.snackbar('companion.create.sourceRequired'.tr,
          'companion.create.descriptionRequired'.tr);
      return;
    }
    if (widget.mode == AICompanionCreateMode.meet &&
        (_documentPath == null || _characterName.text.trim().isEmpty)) {
      Get.snackbar('companion.create.sourceRequired'.tr,
          'companion.create.documentRequired'.tr);
      return;
    }
    setState(() => _busy = true);
    try {
      final mode = widget.mode == AICompanionCreateMode.description
          ? 'user_description'
          : 'meet_file';
      final result = await ApiClient.instance.postMultipart(
        '/v1/companion-drafts',
        fields: {
          'mode': mode,
          if (widget.mode == AICompanionCreateMode.description)
            'description': _description.text.trim(),
          if (widget.mode == AICompanionCreateMode.meet)
            'character_name': _characterName.text.trim(),
        },
        files: {
          'image': _imagePath!,
          if (_documentPath != null) 'document': _documentPath!,
        },
      );
      final payload = Map<String, dynamic>.from(result as Map);
      final profile = Map<String, dynamic>.from(payload['profile'] as Map);
      for (final entry in _fields.entries) {
        final value = profile[entry.key];
        entry.value.text = value is List ? value.join(', ') : '${value ?? ''}';
      }
      _gender = '${profile['gender'] ?? 'custom'}';
      if (!const ['girlfriend', 'boyfriend', 'friend', 'custom']
          .contains(_gender)) {
        _gender = 'custom';
      }
      _avatarMediaId = payload['avatar_media_id'] as String?;
      setState(() => _hasDraft = true);
      AnalyticsService.to.track('companion_draft_generated',
          category: 'companion', properties: {'creation_source': mode});
    } on ApiException catch (error) {
      Get.snackbar('companion.create.generateFailed'.tr, error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submit() async {
    if (_fields['name']!.text.trim().isEmpty || _avatarMediaId == null) return;
    setState(() => _busy = true);
    final source = widget.mode == AICompanionCreateMode.description
        ? 'user_description'
        : 'meet_file';
    try {
      final result = await ApiClient.instance.post('/v1/companions', data: {
        for (final entry in _fields.entries)
          if (entry.key != 'personality_tags')
            entry.key: entry.value.text.trim(),
        'personality_tags': _fields['personality_tags']!
            .text
            .split(RegExp(r'[,，]'))
            .map((value) => value.trim())
            .where((value) => value.isNotEmpty)
            .take(8)
            .toList(),
        'gender': _gender,
        'relationship_stage': _relationship,
        'avatar_media_id': _avatarMediaId,
        'creation_source': source,
      });
      AnalyticsService.to
          .track('companion_created', category: 'companion', properties: {
        'companion_id': result is Map ? '${result['id'] ?? ''}' : '',
        'creation_source': source,
      });
      Get.until((route) => route.settings.name == '/shell' || route.isFirst);
      await ChatListController.to.load();
      Get.snackbar(
          'companion.create.success'.tr, 'companion.create.successMessage'.tr);
    } on ApiException catch (error) {
      Get.snackbar('companion.create.failed'.tr, error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.vita.pageBg,
      appBar: AppBar(
          title: Text((widget.mode == AICompanionCreateMode.meet
                  ? 'companion.create.method.meet'
                  : 'companion.create.method.description')
              .tr)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
          children: _hasDraft ? _draftFields(context) : _sourceFields(context),
        ),
      ),
    );
  }

  List<Widget> _sourceFields(BuildContext context) => [
        Text('companion.create.aiSourceHelp'.tr,
            style: TextStyle(color: context.vita.subText)),
        const SizedBox(height: 16),
        if (widget.mode == AICompanionCreateMode.description)
          _input(_description, 'companion.create.descriptionHint', maxLines: 8)
        else ...[
          _input(_characterName, 'companion.create.characterName'),
          const SizedBox(height: 12),
          _picker(
              Icons.description_outlined,
              _documentPath?.split(RegExp(r'[/\\]')).last ??
                  'companion.create.chooseDocument'.tr,
              _pickDocument),
        ],
        const SizedBox(height: 12),
        _picker(
            Icons.add_photo_alternate_outlined,
            _imagePath == null
                ? 'companion.create.chooseImage'.tr
                : 'companion.create.imageSelected'.tr,
            _pickImage),
        if (_imagePath != null) ...[
          const SizedBox(height: 12),
          ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: Image.file(File(_imagePath!),
                  height: 180, fit: BoxFit.cover)),
        ],
        const SizedBox(height: 24),
        ElevatedButton(
          onPressed: _busy ? null : _generate,
          child: _busy
              ? const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : Text('companion.create.generateDraft'.tr),
        ),
      ];

  List<Widget> _draftFields(BuildContext context) {
    final labels = <String, String>{
      'name': 'companion.create.name',
      'persona': 'companion.create.persona',
      'appearance': 'companion.create.appearanceDetail',
      'city': 'companion.create.city',
      'occupation': 'companion.create.occupation',
      'interests': 'companion.create.interests',
      'personality_tags': 'companion.create.traitsEditable',
      'speaking_style': 'companion.create.speakingStyle',
      'likes': 'companion.create.likes',
      'dislikes': 'companion.create.dislikes',
      'life_habits': 'companion.create.lifeHabits',
      'life_goal': 'companion.create.lifeGoal',
      'backstory': 'companion.create.backstory',
    };
    return [
      Text('companion.create.reviewDraft'.tr,
          style: TextStyle(color: context.vita.subText)),
      const SizedBox(height: 16),
      for (final entry in labels.entries) ...[
        Text(entry.value.tr,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        _input(_fields[entry.key]!, entry.value,
            maxLines:
                const {'persona', 'appearance', 'backstory'}.contains(entry.key)
                    ? 4
                    : 1),
        const SizedBox(height: 12),
      ],
      DropdownButtonFormField<String>(
        initialValue: _gender,
        decoration: InputDecoration(labelText: 'companion.create.who'.tr),
        items: const ['girlfriend', 'boyfriend', 'friend', 'custom']
            .map((value) => DropdownMenuItem(
                value: value, child: Text('relation.$value'.tr)))
            .toList(),
        onChanged: (value) => _gender = value ?? 'custom',
      ),
      const SizedBox(height: 12),
      DropdownButtonFormField<String>(
        initialValue: _relationship,
        decoration: InputDecoration(labelText: 'companion.create.closeness'.tr),
        items: const ['stranger', 'acquaintance', 'close', 'partner']
            .map((value) =>
                DropdownMenuItem(value: value, child: Text('stage.$value'.tr)))
            .toList(),
        onChanged: (value) => _relationship = value ?? 'stranger',
      ),
      const SizedBox(height: 24),
      OutlinedButton(
          onPressed: _busy ? null : () => setState(() => _hasDraft = false),
          child: Text('companion.create.regenerate'.tr)),
      const SizedBox(height: 8),
      ElevatedButton(
          onPressed: _busy ? null : _submit,
          child: Text('companion.create.confirm'.tr)),
    ];
  }

  Widget _input(TextEditingController controller, String hint,
      {int maxLines = 1}) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      decoration: InputDecoration(
        hintText: hint.tr,
        filled: true,
        fillColor: context.vita.surface,
        border: const OutlineInputBorder(),
      ),
    );
  }

  Widget _picker(IconData icon, String label, VoidCallback onTap) {
    return VitaCard(
      child: InkWell(
        onTap: _busy ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            children: [
              Icon(icon, color: context.vita.green),
              const SizedBox(width: 16),
              Expanded(child: Text(label)),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}
