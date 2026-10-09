import 'package:country_picker/country_picker.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../../core/api_client.dart';
import '../../core/notice.dart';
import '../../core/theme.dart';
import '../../shared/widgets.dart';

/// The user's IANA time zone and country scope for World Engine campaigns.
class WorldPreferencesPage extends StatefulWidget {
  const WorldPreferencesPage({super.key});

  @override
  State<WorldPreferencesPage> createState() => _WorldPreferencesPageState();
}

class _WorldPreferencesPageState extends State<WorldPreferencesPage> {
  String _timezone = 'UTC';
  String _region = 'global';
  bool _loading = true;
  bool _saving = false;

  static final List<_WorldChoice> _timezones = () {
    tz_data.initializeTimeZones();
    final names = <String>{'UTC', ...tz.timeZoneDatabase.locations.keys}
        .toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return [for (final name in names) _WorldChoice(name, name)];
  }();

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
        setState(() {
          _timezone = '${data['timezone'] ?? 'UTC'}';
          _region = '${data['region_code'] ?? 'global'}';
        });
      }
    } on ApiException catch (error) {
      if (mounted) VitaNotice.error('world.preferences'.tr, error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<_WorldChoice> _regions(BuildContext context) {
    final locale = Localizations.localeOf(context);
    final countryLocale = CountryLocalizations(
      locale.languageCode == 'zh' && locale.countryCode == 'TW'
          ? const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant')
          : locale,
    );
    final byCode = <String, _WorldChoice>{};
    for (final country in CountryService().getAll()) {
      final code = country.countryCode.toUpperCase();
      if (!RegExp(r'^[A-Z]{2}$').hasMatch(code)) continue;
      final name = countryLocale.countryName(countryCode: code) ?? country.name;
      byCode[code] = _WorldChoice(code, '$name · $code');
    }
    final countries = byCode.values.toList()
      ..sort((a, b) => a.label.compareTo(b.label));
    return [_WorldChoice('global', 'world.regionGlobal'.tr), ...countries];
  }

  Future<void> _pickTimezone() async {
    final selected = await Get.to<String>(
      () => _WorldChoicePage(
        title: 'world.timezone'.tr,
        selected: _timezone,
        choices: _timezones,
      ),
      transition: Transition.cupertino,
    );
    if (mounted && selected != null) setState(() => _timezone = selected);
  }

  Future<void> _pickRegion() async {
    final selected = await Get.to<String>(
      () => _WorldChoicePage(
        title: 'world.region'.tr,
        selected: _region,
        choices: _regions(context),
      ),
      transition: Transition.cupertino,
    );
    if (mounted && selected != null) setState(() => _region = selected);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await ApiClient.instance.put('/v1/me/world-preferences', data: {
        'timezone': _timezone,
        'region_code': _region,
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
  Widget build(BuildContext context) {
    final regions = _regions(context);
    final regionName = regions
        .where((choice) => choice.value.toUpperCase() == _region.toUpperCase())
        .map((choice) => choice.label)
        .firstOrNull;
    return Scaffold(
      backgroundColor: context.vita.pageBg,
      appBar: AppBar(title: Text('world.preferences'.tr)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text('world.preferencesHint'.tr,
                      style: TextStyle(color: context.vita.subText)),
                ),
                const SizedBox(height: 16),
                VitaCard(
                  radius: 12,
                  margin: EdgeInsets.zero,
                  padding: EdgeInsets.zero,
                  child: Column(children: [
                    _PreferenceChoiceRow(
                      title: 'world.timezone'.tr,
                      value: _timezone,
                      onTap: _pickTimezone,
                    ),
                    const Divider(height: 0.5, indent: 16),
                    _PreferenceChoiceRow(
                      title: 'world.region'.tr,
                      value: regionName ?? _region,
                      onTap: _pickRegion,
                    ),
                  ]),
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _saving ? null : _save,
                  child: Text('world.save'.tr),
                ),
              ],
            ),
    );
  }
}

class _WorldChoice {
  const _WorldChoice(this.value, this.label);
  final String value;
  final String label;
}

class _PreferenceChoiceRow extends StatelessWidget {
  const _PreferenceChoiceRow({
    required this.title,
    required this.value,
    required this.onTap,
  });

  final String title;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 64,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(children: [
              Expanded(
                child: Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: context.vita.text, fontSize: 15)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Text(value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.right,
                      style:
                          TextStyle(color: context.vita.subText, fontSize: 13)),
                ),
              ),
              const SizedBox(width: 6),
              Icon(Icons.chevron_right_rounded,
                  size: 20, color: context.vita.chevron),
            ]),
          ),
        ),
      );
}

class _WorldChoicePage extends StatefulWidget {
  const _WorldChoicePage({
    required this.title,
    required this.selected,
    required this.choices,
  });

  final String title;
  final String selected;
  final List<_WorldChoice> choices;

  @override
  State<_WorldChoicePage> createState() => _WorldChoicePageState();
}

class _WorldChoicePageState extends State<_WorldChoicePage> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final query = _query.trim().toLowerCase();
    final choices = query.isEmpty
        ? widget.choices
        : widget.choices
            .where((choice) =>
                choice.label.toLowerCase().contains(query) ||
                choice.value.toLowerCase().contains(query))
            .toList();
    return Scaffold(
      backgroundColor: context.vita.pageBg,
      appBar: AppBar(title: Text(widget.title)),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: TextField(
            onChanged: (value) => setState(() => _query = value),
            decoration: InputDecoration(
              hintText: 'world.searchChoices'.tr,
              prefixIcon: const Icon(Icons.search_rounded),
            ),
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: choices.length,
            itemExtent: 56,
            itemBuilder: (context, index) {
              final choice = choices[index];
              return InkWell(
                onTap: () => Get.back(result: choice.value),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(children: [
                    Expanded(
                      child: Text(choice.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: context.vita.text, fontSize: 15)),
                    ),
                    if (choice.value.toUpperCase() ==
                        widget.selected.toUpperCase())
                      Icon(Icons.check_rounded,
                          size: 20, color: context.vita.green),
                  ]),
                ),
              );
            },
          ),
        ),
      ]),
    );
  }
}
