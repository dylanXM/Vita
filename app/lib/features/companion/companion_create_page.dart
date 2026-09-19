import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/api_client.dart';
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

  Widget _field({required TextEditingController controller, required String hint}) {
    return TextField(
      controller: controller,
      style: TextStyle(fontSize: 15, color: context.vita.text),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: context.vita.hint, fontSize: 14.5),
        filled: true,
        fillColor: context.vita.pageBg,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: context.vita.green, width: 1.5),
        ),
      ),
    );
  }

  Widget _chipRow(List<String> options, String selected, ValueChanged<String> onSelected) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: options.map((o) {
        final isSelected = selected == o;
        return ChoiceChip(
          label: Text(o[0].toUpperCase() + o.substring(1)),
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
      appBar: AppBar(title: const Text('New companion')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Who would you like to meet?', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: context.vita.text)),
              const SizedBox(height: 6),
              Text('A few details help her settle in.', style: TextStyle(fontSize: 13, color: context.vita.subText)),
              const SizedBox(height: 20),

              Text('BASICS', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: context.vita.subText, letterSpacing: 0.8)),
              const SizedBox(height: 10),
              VitaCard(
                child: Column(
                  children: [
                    _field(controller: _name, hint: 'Name'),
                    const SizedBox(height: 12),
                    _field(controller: _city, hint: 'City (e.g. Tokyo)'),
                    const SizedBox(height: 12),
                    _field(controller: _occupation, hint: 'Occupation'),
                    const SizedBox(height: 12),
                    _field(controller: _interests, hint: 'Interests'),
                  ],
                ),
              ),
              const SizedBox(height: 8),

              Text('RELATIONSHIP', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: context.vita.subText, letterSpacing: 0.8)),
              const SizedBox(height: 10),
              VitaCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Who is she to you?', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: context.vita.text)),
                    const SizedBox(height: 10),
                    _chipRow(_genders, _gender, (g) => setState(() => _gender = g)),
                    const SizedBox(height: 18),
                    Text('How close are you?', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: context.vita.text)),
                    const SizedBox(height: 10),
                    _chipRow(_stages, _relationship, (s) => setState(() => _relationship = s)),
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
