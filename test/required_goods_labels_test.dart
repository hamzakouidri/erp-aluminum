import 'package:database_data/Commande/required_goods_labels.dart';
import 'package:database_data/settings/app_settings.dart';
import 'package:database_data/settings/localization.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('profile role labels shown in required goods are Arabic', () {
    expect(requiredGoodsRoleLabel('Frame'), 'الإطار');
    expect(requiredGoodsRoleLabel('Dormant'), 'الإطار');
    expect(requiredGoodsRoleLabel('Cadre doublé — 4001'), 'إطار مزدوج');
    expect(requiredGoodsRoleLabel('Ouvrant'), 'الضلفة');
    expect(requiredGoodsRoleLabel('Montant'), 'التقسيم');
    expect(requiredGoodsRoleLabel('Sash Central'), 'قائم وسطي');
    expect(
      requiredGoodsRoleLabel('قائم جانبي معزز (Latéral Renforcé)'),
      'قائم جانبي معزز',
    );
  });

  test('required-goods generated labels follow the selected language', () {
    expect(Localization.translate('شيكان', AppLanguage.french), 'Chicane');
    expect(
      Localization.translate('الضلفة المنزلقة', AppLanguage.english),
      'Sliding sash',
    );
    expect(
      Localization.translate('باكيت زجاج منزلق مفرد', AppLanguage.french),
      'Parclose simple coulissante',
    );
    expect(
      Localization.translate('باكيت زجاج منزلق مزدوج', AppLanguage.english),
      'Double sliding glazing bead',
    );
    expect(
      Localization.translate('تقطيع موحّد', AppLanguage.english),
      'Grouped cutting',
    );
    expect(
      Localization.translate('طباعة الكمية المطلوبة', AppLanguage.french),
      'Imprimer les quantités requises',
    );
    expect(Localization.translate('القصات', AppLanguage.french), 'Coupes');
  });
}
