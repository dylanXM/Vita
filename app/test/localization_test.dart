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

  test('explore uses the Little Universe product name', () {
    final translations = VitaTranslations().keys;
    expect(translations['en']!['explore.moments'], 'Little Universe');
    expect(translations['zh_CN']!['explore.moments'], '小宇宙');
    expect(translations['zh_TW']!['explore.moments'], '小宇宙');
  });

  test('legal document parses the backend English version and update time', () {
    final document = LegalDocument.from({
      'id': 'privacy-v2',
      'document_type': 'privacy',
      'version': 'v2',
      'title': 'Privacy Policy',
      'summary': 'Summary',
      'content': 'English content',
      'updated_at': '2026-09-20T10:30:00Z',
    });
    expect(document.type, LegalDocumentType.privacy);
    expect(document.version, 'v2');
    expect(document.body, 'English content');
    expect(document.isUsable, isTrue);
  });
}
