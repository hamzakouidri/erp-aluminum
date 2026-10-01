import 'package:flutter_test/flutter_test.dart';
import 'package:database_data/settings/app_settings.dart';
import 'package:database_data/settings/localization.dart';
import 'package:database_data/settings/locales/shortcut_keys.dart';
import 'package:database_data/settings/shortcut_bindings.dart';

void main() {
  test('shortcut and division labels resolve in French and English', () {
    for (final entry in shortcutKeys.entries) {
      for (final language in [AppLanguage.french, AppLanguage.english]) {
        expect(
          Localization.translate(entry.key, language),
          entry.value[language],
        );
        expect(entry.value[language], isNot(entry.key));
      }
    }
  });

  test('shortcut catalog commands are categorized and translated', () {
    expect(
      ShortcutBindings.defaultCommands,
      everyElement(isIn(ShortcutBindings.commands.keys)),
    );
    expect(
      ShortcutBindings.commandCategories.keys,
      containsAll(ShortcutBindings.commands.keys),
    );

    for (final command in ShortcutBindings.commands.entries) {
      final category = ShortcutBindings.commandCategories[command.key];
      expect(
        category,
        isNotNull,
        reason: 'Missing category for ${command.key}',
      );
      for (final language in [AppLanguage.french, AppLanguage.english]) {
        expect(
          Localization.translate(command.value, language),
          isNot(command.value),
          reason: 'Missing ${language.name} label for ${command.key}',
        );
        expect(
          Localization.translate(category!, language),
          isNot(category),
          reason: 'Missing ${language.name} category for ${command.key}',
        );
      }
    }
  });
}
