import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/api_client.dart';
import '../../core/theme.dart';
import '../chat/chat_list_controller.dart';

/// Companion creation — single scrollable form (kept simple for MVP; the PRD's
/// six-step flow can be split later).
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

  static const _genders = ['girlfriend', 'boyfriend', 'friend', 'custom'];
  static const _stages = ['stranger', 'acquaintance', 'close', 'partner'];

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
      Get.snackbar('Name required', 'Give your companion a name first');
      return;
    }
    setState(() => _busy = true);
    try {
      await ApiClient.instance.post('/v1/companions', data: {
        'name': _name.text.trim(),
        'gender': _gender,
        'city': _city.text.trim(),
        'occupation': _occupation.text.trim(),
        'interests': _interests.text.trim(),
        'relationship_stage': _relationship,
      });
      Get.back();
      ChatListController.to.load();
      Get.snackbar('Companion created', 'She is starting her own life now');
    } catch (e) {
      Get.snackbar('Failed to create companion', '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(title: const Text('New companion')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Who would you like to meet?',
                style: TextStyle(fontSize: 15, color: VitaColors.subText),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _name,
                decoration: const InputDecoration(hintText: 'Name'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _city,
                decoration: const InputDecoration(hintText: 'City (e.g. Tokyo)'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _occupation,
                decoration: const InputDecoration(hintText: 'Occupation'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _interests,
                decoration: const InputDecoration(hintText: 'Interests'),
              ),
              const SizedBox(height: 20),
              const Text('Relationship', style: TextStyle(fontSize: 14, color: VitaColors.text)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: _genders.map((g) {
                  final selected = _gender == g;
                  return ChoiceChip(
                    label: Text(g[0].toUpperCase() + g.substring(1)),
                    selected: selected,
                    onSelected: (_) => setState(() => _gender = g),
                    selectedColor: VitaColors.green.withValues(alpha: 0.15),
                    labelStyle: TextStyle(
                      color: selected ? VitaColors.green : VitaColors.text,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 12),
              const Text('Stage', style: TextStyle(fontSize: 14, color: VitaColors.text)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: _stages.map((s) {
                  final selected = _relationship == s;
                  return ChoiceChip(
                    label: Text(s[0].toUpperCase() + s.substring(1)),
                    selected: selected,
                    onSelected: (_) => setState(() => _relationship = s),
                    selectedColor: VitaColors.green.withValues(alpha: 0.15),
                    labelStyle: TextStyle(
                      color: selected ? VitaColors.green : VitaColors.text,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 32),
              ElevatedButton(
                onPressed: _busy ? null : _submit,
                child: _busy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Create companion'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
