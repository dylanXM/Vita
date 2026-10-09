import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/notice.dart';
import '../../core/api_client.dart';
import '../../core/analytics_service.dart';
import '../../core/theme.dart';
import '../../shared/widgets.dart';
import '../chat/chat_list_controller.dart';

/// Companion creation — a single scrollable form grouped into sections.
class CompanionCreatePage extends StatefulWidget {
  const CompanionCreatePage({super.key});

  @override
  State<CompanionCreatePage> createState() => _CompanionCreatePageState();
}

class _CompanionCreatePageState extends State<CompanionCreatePage> {
  final _name = TextEditingController();
  final _city = TextEditingController();
  final _occupation = TextEditingController();
  final _interests = TextEditingController();
  String _gender = 'girlfriend';
  String _relationship = 'stranger';
  bool _busy = false;
  bool _loadingOptions = true;
  final Set<String> _personalityTags = {};
  List<String> _availableTags = const [
    'warm',
    'independent',
    'witty',
    'gentle',
    'curious',
    'calm',
    'outgoing',
    'thoughtful',
    'ambitious',
    'playful',
  ];
  List<Map<String, dynamic>> _portraits = const [];
  String? _portraitId;

  static const _genders = ['girlfriend', 'boyfriend', 'friend', 'custom'];
  static const _stages = ['stranger', 'acquaintance', 'close', 'partner'];

  @override
  void initState() {
    super.initState();
    AnalyticsService.to.track('companion_create_viewed', category: 'companion');
    _loadOptions();
  }

  Future<void> _loadOptions() async {
    try {
      final data = await ApiClient.instance.get('/v1/companion-options');
      if (!mounted || data is! Map) return;
      final tags = data['personality_tags'];
      final portraits = data['portraits'];
      setState(() {
        if (tags is List) _availableTags = tags.whereType<String>().toList();
        if (portraits is List) {
          _portraits = portraits
              .whereType<Map>()
              .map((item) => Map<String, dynamic>.from(item))
              .toList();
        }
      });
    } catch (_) {
      // Creation remains available with built-in tags when options cannot load.
    } finally {
      if (mounted) setState(() => _loadingOptions = false);
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _city.dispose();
    _occupation.dispose();
    _interests.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_name.text.trim().isEmpty) {
      VitaNotice.warning('companion.create.nameRequired'.tr,
          'companion.create.nameRequiredMessage'.tr);
      return;
    }
    setState(() => _busy = true);
    try {
      final result = await ApiClient.instance.post('/v1/companions/', data: {
        'name': _name.text.trim(),
        'gender': _gender,
        'city': _city.text.trim(),
        'occupation': _occupation.text.trim(),
        'interests': _interests.text.trim(),
        'relationship_stage': _relationship,
        'personality_tags': _personalityTags.toList(),
        'portrait_id': _portraitId,
      });
      AnalyticsService.to
          .track('companion_created', category: 'companion', properties: {
        'companion_id': result is Map ? '${result['id'] ?? ''}' : '',
        'relationship_stage': _relationship,
        'personality_tag_count': _personalityTags.length,
        'has_portrait': _portraitId != null,
      });
      Get.back();
      ChatListController.to.load();
      VitaNotice.success(
          'companion.create.success'.tr, 'companion.create.successMessage'.tr);
    } on ApiException catch (e) {
      AnalyticsService.to.track('companion_create_failed',
          category: 'companion', properties: {'reason': e.code ?? e.message});
      if (e.action == 'open_subscription') {
        VitaNotice.warning('subscription.required.title'.tr,
            'subscription.required.create'.tr);
        Get.offNamed('/subscription');
      } else {
        VitaNotice.error('companion.create.failed'.tr, e.message);
      }
    } catch (e) {
      AnalyticsService.to.track('companion_create_failed',
          category: 'companion', properties: {'reason': 'unexpected'});
      VitaNotice.error('companion.create.failed'.tr, '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _field(
      {required TextEditingController controller, required String hint}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        style: TextStyle(fontSize: 15, color: context.vita.text),
        decoration: InputDecoration(
          labelText: hint,
          labelStyle: TextStyle(color: context.vita.subText),
          filled: true,
          fillColor: context.vita.surface,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 17),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: context.vita.divider)),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: context.vita.divider)),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: context.vita.green, width: 1.5)),
        ),
      ),
    );
  }

  Widget _sectionTitle(String key) => Padding(
        padding: const EdgeInsets.fromLTRB(0, 22, 0, 12),
        child: Text(key.tr,
            style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: context.vita.text)),
      );

  Widget _chipRow(
      List<String> options, String selected, ValueChanged<String> onSelected) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: options.map((o) {
        final isSelected = selected == o;
        return ChoiceChip(
          label: Text((o.startsWith('girl') ||
                      o.startsWith('boy') ||
                      o == 'friend' ||
                      o == 'custom'
                  ? 'relation.$o'
                  : 'stage.$o')
              .tr),
          selected: isSelected,
          onSelected: (_) => onSelected(o),
          labelStyle: TextStyle(
            fontSize: 14,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
            color: isSelected ? context.vita.green : context.vita.text,
          ),
        );
      }).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.vita.pageBg,
      appBar: AppBar(
          leading: const VitaBackButton(),
          title: Text('companion.create.title'.tr)),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _sectionTitle('companion.create.basics'),
              Column(
                children: [
                  _field(controller: _name, hint: 'companion.create.name'.tr),
                  _field(controller: _city, hint: 'companion.create.city'.tr),
                  _field(
                      controller: _occupation,
                      hint: 'companion.create.occupation'.tr),
                  _field(
                      controller: _interests,
                      hint: 'companion.create.interests'.tr),
                ],
              ),
              _sectionTitle('companion.create.personality'),
              VitaCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('companion.create.traits'.tr,
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: context.vita.text)),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _availableTags.map((tag) {
                        final selected = _personalityTags.contains(tag);
                        return FilterChip(
                          label: Text('tag.$tag'.tr),
                          selected: selected,
                          onSelected: (value) => setState(() {
                            if (value && _personalityTags.length < 8) {
                              _personalityTags.add(tag);
                            } else if (!value) {
                              _personalityTags.remove(tag);
                            }
                          }),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
              _sectionTitle('companion.create.appearance'),
              VitaCard(
                child: _loadingOptions
                    ? const Center(
                        child: Padding(
                            padding: EdgeInsets.all(16),
                            child: CircularProgressIndicator()))
                    : _portraits.isEmpty
                        ? Text('companion.create.noPortraits'.tr,
                            style: TextStyle(color: context.vita.subText))
                        : Wrap(
                            spacing: 12,
                            runSpacing: 12,
                            children: _portraits.map((portrait) {
                              final id = portrait['id'] as String? ?? '';
                              final selected = _portraitId == id;
                              final imageUrl = portrait['image_url'] as String?;
                              return GestureDetector(
                                onTap: () => setState(() {
                                  _portraitId = id;
                                  final suggested =
                                      portrait['personality_tags'];
                                  if (_personalityTags.isEmpty &&
                                      suggested is List) {
                                    _personalityTags.addAll(
                                        suggested.whereType<String>().take(8));
                                  }
                                }),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 180),
                                  width: 92,
                                  padding: const EdgeInsets.all(4),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(18),
                                    color: selected
                                        ? context.vita.greenTint
                                        : context.vita.pageBg,
                                    border: Border.all(
                                        color: selected
                                            ? context.vita.green
                                            : Colors.transparent,
                                        width: 2),
                                  ),
                                  child: Column(
                                    children: [
                                      VitaAvatar(
                                          name:
                                              portrait['name'] as String? ?? '',
                                          radius: 38,
                                          imageUrl: imageUrl),
                                      const SizedBox(height: 6),
                                      Text(portrait['name'] as String? ?? '',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: selected
                                                  ? FontWeight.w700
                                                  : FontWeight.w500,
                                              color: selected
                                                  ? context.vita.green
                                                  : context.vita.text)),
                                    ],
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
              ),
              _sectionTitle('companion.create.relationship'),
              VitaCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('companion.create.who'.tr,
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: context.vita.text)),
                    const SizedBox(height: 10),
                    _chipRow(
                        _genders, _gender, (g) => setState(() => _gender = g)),
                    const SizedBox(height: 18),
                    Text('companion.create.closeness'.tr,
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: context.vita.text)),
                    const SizedBox(height: 10),
                    _chipRow(_stages, _relationship,
                        (s) => setState(() => _relationship = s)),
                  ],
                ),
              ),
              const SizedBox(height: 28),
              ElevatedButton(
                onPressed: _busy ? null : _submit,
                child: _busy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : Text('companion.create.submit'.tr),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
