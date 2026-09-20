import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/settings_controller.dart';
import '../../core/supported_locales.dart';
import '../../core/theme.dart';
import '../../shared/widgets.dart';
import '../auth/auth_controller.dart';

/// Settings — language, theme and sign out. Reached from the Me page.
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = VitaSettingsController.to;
    final vita = context.vita;
    return Scaffold(
      backgroundColor: vita.pageBg,
      appBar: AppBar(title: Text('settings.title'.tr)),
      body: ListView(
        padding: const EdgeInsets.only(top: 8, bottom: 24),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text('settings.general'.tr, style: vita.sectionTitle),
          ),
          const SizedBox(height: 12),
          // General group: language + theme.
          VitaCard(
            radius: 0,
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              children: [
                Obx(
                  () => VitaListTile(
                    icon: Icons.language,
                    title: 'lang.title'.tr,
                    subtitle: _langLabel(context, settings.locale.value),
                    borderRadius: BorderRadius.zero,
                    onTap: () => Get.to(
                      () => const LanguagePage(),
                      transition: Transition.cupertino,
                      duration: const Duration(milliseconds: 300),
                    ),
                  ),
                ),
                const Divider(indent: 52, height: 0.5),
                Obx(
                  () => VitaListTile(
                    icon: Icons.dark_mode_outlined,
                    title: 'theme.title'.tr,
                    subtitle: _themeLabel(context, settings.themeMode.value),
                    borderRadius: BorderRadius.zero,
                    onTap: () => Get.to(
                      () => const ThemePage(),
                      transition: Transition.cupertino,
                      duration: const Duration(milliseconds: 300),
                    ),
                  ),
                ),
                const Divider(indent: 52, height: 0.5),
                VitaListTile(
                  icon: Icons.notifications_outlined,
                  title: 'settings.notifications'.tr,
                  subtitle: 'settings.notifications.subtitle'.tr,
                  borderRadius: BorderRadius.zero,
                  onTap: openAppSettings,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text('settings.account'.tr, style: vita.sectionTitle),
          ),
          const SizedBox(height: 12),
          // Account group: sign out.
          VitaCard(
            radius: 0,
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: VitaListTile(
              icon: Icons.logout,
              title: 'common.signout'.tr,
              iconColor: vita.red,
              borderRadius: BorderRadius.zero,
              onTap: () => _confirmSignOut(context),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'me.version'.tr,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: vita.subText),
          ),
        ],
      ),
    );
  }

  void _confirmSignOut(BuildContext context) {
    final auth = AuthController.to;
    final vita = context.vita;
    showModalBottomSheet(
      context: context,
      backgroundColor: vita.surface,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFDDDDDD),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: vita.red.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.logout, size: 26, color: vita.red),
              ),
              const SizedBox(height: 14),
              Text(
                'signout.title'.tr,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: vita.text,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'signout.message'.tr,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: vita.subText),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: vita.red),
                  onPressed: () {
                    Get.back();
                    auth.logout();
                  },
                  child: Text('common.signout'.tr),
                ),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Get.back(),
                child: Text(
                  'common.cancel'.tr,
                  style: TextStyle(color: vita.subText),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Current language display name (each language shown in its own language).
String _langLabel(BuildContext context, Locale? selected) {
  if (selected == null) return 'lang.system'.tr;
  return _languageLabelKey(vitaLocaleTag(selected)).tr;
}

String _languageLabelKey(String tag) => switch (tag) {
      'ar' => 'lang.arabic',
      'es' => 'lang.spanish',
      'ja' => 'lang.japanese',
      'ko' => 'lang.korean',
      'pt' => 'lang.portuguese',
      'zh-Hans' => 'lang.chineseSimplified',
      'zh-Hant' => 'lang.chineseTraditional',
      _ => 'lang.english',
    };

/// Current theme display name.
String _themeLabel(BuildContext context, ThemeMode? mode) {
  switch (mode ?? ThemeMode.system) {
    case ThemeMode.system:
      return 'theme.system'.tr;
    case ThemeMode.light:
      return 'theme.light'.tr;
    case ThemeMode.dark:
      return 'theme.dark'.tr;
  }
}

/// Single-column option list (language / theme pickers), iOS-settings style.
class _OptionListPage extends StatelessWidget {
  const _OptionListPage({required this.title, required this.options});

  final String title;
  final List<_Option> options;

  @override
  Widget build(BuildContext context) {
    final vita = context.vita;
    return Scaffold(
      backgroundColor: vita.pageBg,
      appBar: AppBar(title: Text(title.tr)),
      body: ListView(
        padding: const EdgeInsets.only(top: 8, bottom: 24),
        children: [
          VitaCard(
            radius: 0,
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              children: [
                for (var i = 0; i < options.length; i++) ...[
                  if (i > 0) const Divider(indent: 20, height: 0.5),
                  _OptionRow(option: options[i]),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Option {
  const _Option({
    required this.labelKey,
    required this.selected,
    required this.onTap,
  });

  final String labelKey;
  final bool selected;
  final VoidCallback onTap;
}

class _OptionRow extends StatelessWidget {
  const _OptionRow({required this.option});

  final _Option option;

  @override
  Widget build(BuildContext context) {
    final vita = context.vita;
    return InkWell(
      onTap: option.onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        child: Row(
          children: [
            Expanded(
              child: Text(
                option.labelKey.tr,
                style: TextStyle(
                  fontSize: 15.5,
                  fontWeight: FontWeight.w500,
                  color: vita.text,
                ),
              ),
            ),
            if (option.selected)
              Icon(Icons.check, size: 20, color: vita.green)
            else
              const SizedBox(width: 20),
          ],
        ),
      ),
    );
  }
}

/// Language picker — system default plus all eight App languages.
class LanguagePage extends StatelessWidget {
  const LanguagePage({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = VitaSettingsController.to;
    return _OptionListPage(
      title: 'lang.title',
      options: [
        _Option(
          labelKey: 'lang.system',
          selected: settings.locale.value == null,
          onTap: () {
            settings.setLocale(null);
            Get.back();
          },
        ),
        for (final locale in VitaSettingsController.supportedLocales)
          _Option(
            labelKey: _languageLabelKey(vitaLocaleTag(locale)),
            selected: settings.locale.value != null &&
                vitaLocaleTag(settings.locale.value!) == vitaLocaleTag(locale),
            onTap: () {
              settings.setLocale(locale);
              Get.back();
            },
          ),
      ],
    );
  }
}

/// Theme picker — follow the phone, light, dark.
class ThemePage extends StatelessWidget {
  const ThemePage({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = VitaSettingsController.to;
    return _OptionListPage(
      title: 'theme.title',
      options: [
        _Option(
          labelKey: 'theme.system',
          selected: settings.themeMode.value == null,
          onTap: () {
            settings.setThemeMode(null);
            Get.back();
          },
        ),
        _Option(
          labelKey: 'theme.light',
          selected: settings.themeMode.value == ThemeMode.light,
          onTap: () {
            settings.setThemeMode(ThemeMode.light);
            Get.back();
          },
        ),
        _Option(
          labelKey: 'theme.dark',
          selected: settings.themeMode.value == ThemeMode.dark,
          onTap: () {
            settings.setThemeMode(ThemeMode.dark);
            Get.back();
          },
        ),
      ],
    );
  }
}
