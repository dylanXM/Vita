import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/notice.dart';
import '../../core/api_client.dart';
import '../../core/theme.dart';

/// The user's IANA time zone and country scope for World Engine campaigns.
class WorldPreferencesPage extends StatefulWidget {
  const WorldPreferencesPage({super.key});

  @override
  State<WorldPreferencesPage> createState() => _WorldPreferencesPageState();
}

class _WorldPreferencesPageState extends State<WorldPreferencesPage> {
  final _timezone = TextEditingController();
  final _region = TextEditingController();
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await ApiClient.instance.get('/v1/me/world-preferences');
      if (!mounted) return;
      if (data is Map) {
        _timezone.text = '${data['timezone'] ?? 'UTC'}';
        _region.text = '${data['region_code'] ?? 'global'}';
      }
    } on ApiException catch (error) {
      if (mounted) VitaNotice.error('world.preferences'.tr, error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    final timezone = _timezone.text.trim();
    final region = _region.text.trim().toUpperCase();
    if (timezone.isEmpty ||
        (region != 'GLOBAL' && !RegExp(r'^[A-Z]{2}$').hasMatch(region))) {
      VitaNotice.warning('world.preferences'.tr, 'world.preferencesInvalid'.tr);
      return;
    }
    setState(() => _saving = true);
    try {
      await ApiClient.instance.put('/v1/me/world-preferences', data: {
        'timezone': timezone,
        'region_code': region,
      });
      if (mounted) {
        VitaNotice.success('world.preferences'.tr, 'world.preferencesSaved'.tr);
        Get.back();
      }
    } on ApiException catch (error) {
      if (mounted) VitaNotice.error('world.preferences'.tr, error.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _timezone.dispose();
    _region.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: context.vita.pageBg,
        appBar: AppBar(title: Text('world.preferences'.tr)),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  Text('world.preferencesHint'.tr,
                      style: TextStyle(color: context.vita.subText)),
                  const SizedBox(height: 22),
                  TextField(
                    controller: _timezone,
                    decoration: InputDecoration(
                      labelText: 'world.timezone'.tr,
                      hintText: 'Asia/Shanghai',
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _region,
                    maxLength: 6,
                    decoration: InputDecoration(
                      labelText: 'world.region'.tr,
                      hintText: 'CN / US / global',
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: _saving ? null : _save,
                    child: Text('world.save'.tr),
                  ),
                ],
              ),
      );
}
