import 'package:database_data/settings/app_settings.dart';
import 'package:database_data/settings/localization.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('keys ending with a space are translated', () {
    expect(Localization.translate('الحالة: ', AppLanguage.french), 'Statut : ');
    expect(
      Localization.translate('المدفوع: ', AppLanguage.english),
      isNot('المدفوع: '),
    );
  });

  test('a trimmed key keeps the caller spacing', () {
    expect(
      Localization.translate('  تأكيد واستلام ', AppLanguage.french),
      '  Confirmer et réceptionner ',
    );
  });
}
