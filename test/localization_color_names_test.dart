import 'package:database_data/settings/app_settings.dart';
import 'package:database_data/settings/localization.dart';
import 'package:flutter_test/flutter_test.dart';

/// Colour names stored in Arabic (catalogue seeds and fixed lists) must not
/// reach a French or English screen in Arabic.
void main() {
  const names = [
    'أبيض',
    'بني',
    'رمادي',
    'أسود',
    'بيج',
    'خام',
    'شامبانيا',
    'شمبانيا',
    'ديزرت اوك',
    'شامبانيا',
    'بدون لون',
    'ذهبي',
    'فضي',
    'خشبي',
    'رمادي (السعر الأساسي)',
  ];
  final arabic = RegExp(r'[؀-ۿ]');
  for (final lang in [AppLanguage.french, AppLanguage.english]) {
    test('catalogue colour names are translated in ${lang.name}', () {
      final untranslated = [
        for (final name in names)
          if (arabic.hasMatch(Localization.colorName(name, lang))) name,
      ];
      expect(untranslated, isEmpty);
    });
  }

  test('an unknown "عربي (Latin)" name shows its Latin part', () {
    expect(
      Localization.colorName('أزرق ملكي (Bleu royal)', AppLanguage.french),
      'Bleu royal',
    );
    expect(Localization.colorName('أبيض', AppLanguage.arabic), 'أبيض');
  });
}
