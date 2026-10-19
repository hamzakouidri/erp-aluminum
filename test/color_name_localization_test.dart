import 'package:database_data/settings/app_settings.dart';
import 'package:database_data/settings/localization.dart';
import 'package:database_data/utils/color_name_localization.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('catalogue colour names follow the language', () {
    expect(localizedColorName('الابيض', AppLanguage.french), 'Blanc');
    expect(localizedColorName('الأسود', AppLanguage.english), 'Black');
    expect(localizedColorName('أسود مطفي', AppLanguage.french), 'Noir mat');
    expect(localizedColorName('أسود مطفي', AppLanguage.english), 'Matte Black');
    // Kept as typed: in Arabic, and when a word is unknown.
    expect(localizedColorName('الابيض', AppLanguage.arabic), 'الابيض');
    expect(
      localizedColorName('RAL 7016 خاص', AppLanguage.french),
      'RAL 7016 خاص',
    );
  });

  test('translate falls back to the colour name', () {
    expect(Localization.translate('الابيض', AppLanguage.french), 'Blanc');
    expect(
      Localization.translate('محرك مع مانيفال احتياطي', AppLanguage.french),
      'Moteur avec manivelle de secours',
    );
  });
}
