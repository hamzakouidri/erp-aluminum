import 'package:database_data/services/notification_texts.dart';
import 'package:database_data/settings/app_settings.dart';
import 'package:database_data/settings/localization.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('built-in languages', () {
    test('keep the order and positions older versions saved', () {
      expect(AppLanguage.builtIn, [
        AppLanguage.arabic,
        AppLanguage.french,
        AppLanguage.english,
      ]);
      expect(AppLanguage.arabic.index, 0);
      expect(AppLanguage.french.index, 1);
      expect(AppLanguage.english.index, 2);
      expect(AppLanguage.english.name, 'english');
    });

    test('are found by code and are their own fallback', () {
      expect(AppLanguage.fromCode('FR'), same(AppLanguage.french));
      expect(AppLanguage.fromCode('xx'), isNull);
      expect(AppLanguage.arabic.fallback, same(AppLanguage.arabic));
      expect(AppLanguage.arabic.isRtl, isTrue);
      expect(AppLanguage.french.isRtl, isFalse);
    });
  });

  group('a pack language', () {
    late AppLanguage spanish;

    setUp(() {
      spanish = AppLanguage.register(
        code: 'es',
        name: 'spanish',
        nativeName: 'Español',
      );
    });

    tearDown(() => AppLanguage.unregister(spanish));

    test('is registered once and listed after the built-in ones', () {
      expect(
        AppLanguage.register(code: 'ES', name: 'x', nativeName: 'x'),
        same(spanish),
      );
      expect(AppLanguage.fromCode('es'), same(spanish));
      expect(AppLanguage.values.last, same(spanish));
      expect(AppLanguage.values.take(3), AppLanguage.builtIn);
    });

    test('falls back to English', () {
      expect(spanish.fallback, same(AppLanguage.english));
      expect(spanish.index, AppLanguage.english.index);
      expect(spanish.isBuiltIn, isFalse);
      expect(NotificationTexts.languageCode(spanish), 'en');
    });

    test('takes the default branch of a switch, the English text', () {
      String label(AppLanguage lang) => switch (lang) {
        AppLanguage.arabic => 'ar',
        AppLanguage.french => 'fr',
        _ => 'en',
      };
      expect(label(spanish), 'en');
    });

    test('translates from its pack, then from English', () {
      Localization.loadJson(
        spanish,
        '{"meta": {"code": "es"}, "strings": {"language": "Idioma", '
            '"settings": ""}}',
      );
      expect(Localization.translate('language', spanish), 'Idioma');
      expect(Localization.translate(' language ', spanish), ' Idioma ');
      // Empty in the pack, and absent from it: the English text.
      expect(
        Localization.translate('settings', spanish),
        Localization.translate('settings', AppLanguage.english),
      );
      expect(
        Localization.translate('إكسسوارات', spanish),
        Localization.translate('إكسسوارات', AppLanguage.english),
      );
    });
  });

  group('saved language', () {
    Future<AppLanguage> load(Map<String, Object> values) async {
      SharedPreferences.setMockInitialValues(values);
      return AppSettingsProvider.loadSavedLanguage();
    }

    test('is read by code first', () async {
      expect(
        await load({'app_language_code': 'en', 'app_language': 0}),
        AppLanguage.english,
      );
    });

    test('an older install saved only the position', () async {
      expect(
        await load({'app_language': 2, 'app_language_explicit': true}),
        AppLanguage.english,
      );
    });

    test('a removed pack falls back to the saved position', () async {
      expect(
        await load({
          'app_language_code': 'es',
          'app_language': 2,
          'app_language_explicit': true,
        }),
        AppLanguage.english,
      );
    });

    test('a value of the wrong type reads as missing', () async {
      expect(
        await load({'app_language': 'english', 'app_language_code': 3}),
        AppLanguage.french,
      );
    });

    test('a choice is saved by code and by position', () async {
      SharedPreferences.setMockInitialValues({});
      await AppSettingsProvider().setLanguage(AppLanguage.english);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('app_language_code'), 'en');
      expect(prefs.getInt('app_language'), 2);
    });
  });
}
