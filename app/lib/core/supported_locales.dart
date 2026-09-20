import 'dart:ui';

const vitaSupportedLocales = <Locale>[
  Locale('ar'),
  Locale('en'),
  Locale('es'),
  Locale('ja'),
  Locale('ko'),
  Locale('pt'),
  Locale('zh', 'CN'),
  Locale('zh', 'TW'),
];

String vitaLocaleTag(Locale locale) {
  if (locale.languageCode == 'zh') {
    return locale.countryCode == 'TW' ? 'zh-Hant' : 'zh-Hans';
  }
  return locale.languageCode;
}

String vitaTranslationLocaleKey(Locale locale) {
  if (locale.languageCode == 'zh') {
    return locale.countryCode == 'TW' ? 'zh_TW' : 'zh_CN';
  }
  return locale.languageCode;
}

Locale? vitaLocaleFromTag(String? raw) {
  final value = (raw ?? '').trim().toLowerCase().replaceAll('_', '-');
  if (value == 'zh-hant' || value == 'zh-tw' || value == 'zh-hk') {
    return const Locale('zh', 'TW');
  }
  if (value == 'zh' || value == 'zh-hans' || value == 'zh-cn') {
    return const Locale('zh', 'CN');
  }
  final language = value.split('-').first;
  for (final locale in vitaSupportedLocales) {
    if (locale.languageCode == language && language != 'zh') return locale;
  }
  return null;
}

Locale vitaLocaleForDevice(Locale? device) {
  if (device == null) return const Locale('en');
  if (device.languageCode == 'zh') {
    final traditional = device.scriptCode == 'Hant' ||
        const {'TW', 'HK', 'MO'}.contains(device.countryCode);
    return Locale('zh', traditional ? 'TW' : 'CN');
  }
  return vitaLocaleFromTag(device.languageCode) ?? const Locale('en');
}
