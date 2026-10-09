import 'package:database_data/Commande/devis_builder.dart';
import 'package:database_data/settings/app_settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('shutter only devis line displays Gamme: Volet in French and has no window series', () {
    final lineFr = DevisBuilder.buildLineItemFromDetail({
      'game': 'Volet roulant',
      'largeur': 1200,
      'hauteur': 1400,
      'partitions_json': {
        'isShutterOnly': true,
        'hasShutter': true,
        'slidingSeriesName': 'Prolex Coulissant',
        'seriesName': 'Petit Modèle Prolex battant',
        'width': 1200,
        'height': 1400,
      },
    }, overrideLang: AppLanguage.french);

    expect(lineFr.title, 'Volet roulant');
    expect(lineFr.details, contains('Gamme: Volet'));
    expect(lineFr.details.any((d) => d.contains('Prolex')), isFalse);
    expect(lineFr.details.any((d) => d.contains('battant')), isFalse);
    expect(lineFr.details.any((d) => d.contains('Coulissant')), isFalse);
  });

  test('shutter only devis line displays السلسلة: ستار in Arabic and has no window series', () {
    final lineAr = DevisBuilder.buildLineItemFromDetail({
      'game': 'ستار رولان',
      'largeur': 1200,
      'hauteur': 1400,
      'partitions_json': {
        'isShutterOnly': true,
        'hasShutter': true,
        'slidingSeriesName': 'Prolex Coulissant',
        'seriesName': 'Petit Modèle Prolex battant',
        'width': 1200,
        'height': 1400,
      },
    }, overrideLang: AppLanguage.arabic);

    expect(lineAr.details, contains('السلسلة: ستار'));
    expect(lineAr.details.any((d) => d.contains('Prolex')), isFalse);
    expect(lineAr.details.any((d) => d.contains('battant')), isFalse);
    expect(lineAr.details.any((d) => d.contains('Coulissant')), isFalse);
  });
}
