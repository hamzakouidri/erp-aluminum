import 'dart:convert';

import 'package:database_data/Commande/devis_builder.dart';
import 'package:database_data/settings/app_settings.dart';
import 'package:database_data/utils/shutter_selection.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('selected blade wins over a stale default in every document language', () {
    for (final language in AppLanguage.values) {
      for (final encoded in [false, true]) {
        final drawing = <String, dynamic>{
          'width': 1200,
          'height': 1400,
          'hasShutter': true,
          'shutterLame': 'Old default blade',
          'componentOverrides': {
            'الشرائح (Lames)': {'name': 'Chosen extruded blade'},
          },
        };
        final line = DevisBuilder.buildLineItemFromDetail({
          'id': 1,
          'window_type': 'volet',
          'largeur': 1200,
          'hauteur': 1400,
          'quantity': 1,
          'price': 1000,
          'partitions_json': encoded ? jsonEncode(drawing) : drawing,
        }, overrideLang: language);
        expect(line.details.join('\n'), contains('Chosen extruded blade'));
        expect(line.details.join('\n'), isNot(contains('Old default blade')));
      }
    }
  });

  test('legacy and incomplete selections retain their saved label', () {
    for (final overrides in [
      null,
      <String, dynamic>{},
      {'الشرائح (Lames)': null},
      {'الشرائح (Lames)': {'name': '  '}},
    ]) {
      expect(resolveShutterBladeName(overrides, fallback: 'Saved blade'),
          'Saved blade');
    }
    expect(resolveShutterBladeName(null), '');
  });
}
