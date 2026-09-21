import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_client.dart';
import 'supported_locales.dart';

/// App-wide user preferences: language and theme.
///
/// Both default to "follow the phone": the language resolves to the device
/// language (one of Vita's eight languages, otherwise English) and the
/// theme follows the system light/dark mode. Explicit user choices are
/// persisted and survive relaunches.
class VitaSettingsController extends GetxController {
  static VitaSettingsController get to => Get.find();

  static const _themeKey = 'vita_theme_mode';
  static const _localeKey = 'vita_locale';
  static const _petDesktopKey = 'vita_pet_desktop_enabled';

  /// Languages the app ships.
  static const List<Locale> supportedLocales = vitaSupportedLocales;

  /// null → follow the phone's appearance (default).
  final Rxn<ThemeMode> themeMode = Rxn<ThemeMode>();

  /// null → follow the device language (default).
  final Rxn<Locale> locale = Rxn<Locale>();

  /// Whether the adopted AI pet floats above every app route.
  final petDesktopEnabled = false.obs;

  /// Completes once the persisted preferences have been loaded.
  final Completer<void> ready = Completer<void>();

  /// Invoked by the app root after a preference change so the whole app
  /// rebuilds with the new theme/locale.
  VoidCallback? onPreferenceChanged;

  @override
  void onInit() {
    super.onInit();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final mode = prefs.getString(_themeKey);
    if (mode != null) {
      themeMode.value =
          ThemeMode.values.firstWhereOrNull((m) => m.name == mode);
    }
    final lang = prefs.getString(_localeKey);
    if (lang != null) {
      locale.value = vitaLocaleFromTag(lang);
    }
    petDesktopEnabled.value = prefs.getBool(_petDesktopKey) ?? false;
    // GetX resolves .tr through the static Get.locale, so even in
    // "follow system" mode we pin it to a concrete supported locale.
    Get.locale = effectiveLocale;
    if (!ready.isCompleted) ready.complete();
  }

  /// The concrete UI locale: the user's explicit choice, or the device
  /// language when following the phone.
  Locale get effectiveLocale {
    if (locale.value != null) return locale.value!;
    return vitaLocaleForDevice(Get.deviceLocale);
  }

  /// The theme mode applied to the app: explicit choice or [ThemeMode.system].
  ThemeMode get appliedThemeMode => themeMode.value ?? ThemeMode.system;

  void setThemeMode(ThemeMode? mode) {
    themeMode.value = mode;
    _persist(_themeKey, mode?.name);
    // The app root rebuilds GetMaterialApp with the new themeMode; every
    // `context.vita` (Theme.of) then resolves against the new brightness.
    _changed();
  }

  void setLocale(Locale? value) {
    locale.value = value;
    _persist(_localeKey, value == null ? null : vitaLocaleTag(value));
    // forceAppUpdate() re-runs every `tr` call site with the new locale.
    Get.updateLocale(effectiveLocale);
    _changed();
    unawaited(syncLocale());
  }

  void setPetDesktopEnabled(bool enabled) {
    petDesktopEnabled.value = enabled;
    _persistBool(_petDesktopKey, enabled);
    _changed();
  }

  Future<void> syncLocale() async {
    try {
      await ApiClient.instance.put('/v1/me/locale', data: {
        'locale': vitaLocaleTag(effectiveLocale),
      });
    } catch (_) {
      // Authentication may not be ready yet. AuthController retries after
      // every successful login/registration.
    }
  }

  Future<void> _persist(String key, String? value) async {
    final prefs = await SharedPreferences.getInstance();
    if (value == null) {
      await prefs.remove(key);
    } else {
      await prefs.setString(key, value);
    }
  }

  Future<void> _persistBool(String key, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
  }

  void _changed() => onPreferenceChanged?.call();
}
