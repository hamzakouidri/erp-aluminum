import 'package:database_data/settings/app_settings.dart';
import 'package:database_data/settings/localization.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('required-goods shutter labels stay in the selected language', () {
    expect(
      Localization.translate('الصندوق (Caisson)', AppLanguage.french),
      'Caisson',
    );
    expect(
      Localization.translate('سيبور موتور (Support Moteur)', AppLanguage.french),
      'Support moteur',
    );
    expect(
      Localization.translate('الشرائح (Lames)', AppLanguage.english),
      'Slats',
    );
    expect(Localization.translate('قطعة', AppLanguage.english), 'piece');
  });
}
