import 'package:flutter_test/flutter_test.dart';
import 'package:vita/core/i18n/translations.dart';
import 'package:vita/core/legal_documents.dart';
import 'package:vita/core/supported_locales.dart';

void main() {
  test('app exposes the required eight locales', () {
    expect(
      vitaSupportedLocales.map(vitaLocaleTag).toSet(),
      {'ar', 'en', 'es', 'ja', 'ko', 'pt', 'zh-Hans', 'zh-Hant'},
    );
  });

  test('every locale contains the complete translation key set', () {
    final translations = VitaTranslations().keys;
    final englishKeys = translations['en']!.keys.toSet();
    expect(translations.keys.toSet(),
        {'ar', 'en', 'es', 'ja', 'ko', 'pt', 'zh_CN', 'zh_TW'});
    for (final entry in translations.entries) {
      expect(entry.value.keys.toSet(), englishKeys,
          reason: '${entry.key} must not silently fall back to English');
    }
  });

  test('privacy policy and terms cover every supported locale', () {
    final tags = vitaSupportedLocales.map(vitaLocaleTag).toSet();
    expect(privacyDocuments.keys.toSet(), tags);
    expect(termsDocuments.keys.toSet(), tags);
    for (final tag in tags) {
      expect(privacyDocuments[tag]!.body, isNotEmpty);
      expect(termsDocuments[tag]!.body, isNotEmpty);
    }
  });
}
