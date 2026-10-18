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
    expect(Localization.translate('قطعة', AppLanguage.english), 'piece(s)');
  });

  test('new interface keys never fall back to Arabic', () {
    expect(
      Localization.translate('الدخول باستخدام Google', AppLanguage.french),
      'Se connecter avec Google',
    );
    expect(
      Localization.translate('System Sliding (جرار)', AppLanguage.english),
      'Sliding system',
    );
    expect(
      Localization.translate(
        'أكبر من القيمة ({symbol})',
        AppLanguage.french,
      ).replaceAll('{symbol}', '> X'),
      'Supérieur à la valeur (> X)',
    );
  });
}
