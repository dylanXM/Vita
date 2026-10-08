// 临时校验脚本：验证 8 种语言的翻译键集合完全一致（等价于 localization_test.dart 的断言）。
import 'package:vita/core/i18n/translations.dart';

void main() {
  final translations = VitaTranslations().keys;
  final englishKeys = translations['en']!.keys.toSet();
  print('locales: ${translations.keys.toSet()}');
  var failed = false;
  for (final entry in translations.entries) {
    final keys = entry.value.keys.toSet();
    final missing = englishKeys.difference(keys);
    final extra = keys.difference(englishKeys);
    final ok = missing.isEmpty && extra.isEmpty;
    if (!ok) failed = true;
    print('${entry.key}: ${keys.length} keys ${ok ? 'OK' : 'MISMATCH'}'
        '${missing.isEmpty ? '' : ' missing=${missing.take(8).toList()}'}'
        '${extra.isEmpty ? '' : ' extra=${extra.take(8).toList()}'}');
  }
  print('aiPets.stateStanding in en: ${translations['en']!['aiPets.stateStanding']}');
  print('aiPets.refresh in zh_CN: ${translations['zh_CN']!['aiPets.refresh']}');
  if (failed) throw StateError('Translation key sets mismatch');
  print('ALL LOCALES CONSISTENT');
}
