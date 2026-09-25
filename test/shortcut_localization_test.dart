import 'package:flutter_test/flutter_test.dart';
import 'package:database_data/settings/app_settings.dart';
import 'package:database_data/settings/localization.dart';
import 'package:database_data/settings/locales/shortcut_keys.dart';

void main() {
  test('shortcut and division labels resolve in French and English', () {
    for (final entry in shortcutKeys.entries) {
      for (final language in [AppLanguage.french, AppLanguage.english]) {
        expect(Localization.translate(entry.key, language), entry.value[language]);
        expect(entry.value[language], isNot(entry.key));
      }
    }
  });
}
