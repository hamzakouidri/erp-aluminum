import 'package:database_data/Commande/devis_builder.dart';
import 'package:database_data/settings/app_settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('glass work devis details are entirely French', () {
    final line = DevisBuilder.buildLineItemFromDetail({
      'game': 'فير ترومبي',
      'largeur': 2000,
      'hauteur': 2000,
      'partitions_json': {
        'isGlassWork': true,
        'manualNameOverride': 'فير ترومبي - Cabine de douche coulissante',
        'width': 2000,
        'height': 2000,
        'glassWorkPayload': {
          'workTypeLabel': 'Cabine de douche coulissante',
          'glassTypeLabel': 'Transparent',
          'glassThicknessMm': 10,
          'sablageMode': 'decorative',
          'items': [
            {'role': 'door', 'widthMm': 800, 'heightMm': 2030},
            {'role': 'fixed', 'widthMm': 1230, 'heightMm': 2000},
          ],
        },
      },
    }, overrideLang: AppLanguage.french);

    expect(line.title, 'Verre trempé - Cabine de douche coulissante');
    expect(line.details, contains('Propriété : Cabine de douche coulissante'));
    expect(
      line.details,
      contains('Verre : Transparent 10 mm | Sablage décoratif'),
    );
    expect(line.details, contains('Dimensions hors tout : 2000 × 2000 mm'));
    expect(
      line.details,
      contains('Panneaux (2) : Porte : 800 × 2030 mm | Fixe : 1230 × 2000 mm'),
    );
    expect(
      '${line.title}\n${line.details.join('\n')}',
      isNot(matches(RegExp(r'[\u0600-\u06ff]'))),
    );
  });
}
