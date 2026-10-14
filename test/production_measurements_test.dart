import 'dart:convert';

import 'package:database_data/Commande/production_measurements.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('confirmed measurements replace the compact commercial dimensions', () {
    final rows = productionMeasurementInstances({
      'quantity': 6,
      'largeur': 1200,
      'hauteur': 1040,
      'instances_json': jsonEncode([
        {'width': 1200, 'height': 1040, 'qty': 6},
      ]),
      'confirmed_mesures_json': jsonEncode([
        {'width': 1190, 'height': 1040},
        {'width': 1190, 'height': 1040},
        {'width': 1200, 'height': 1040},
        {'width': 1200, 'height': 1040},
        {'width': 1320, 'height': 1040},
        {'width': 1320, 'height': 1040},
      ]),
    });

    expect(rows, hasLength(3));
    expect(rows.map((row) => row['qty']), everyElement(2));
    expect(
      rows.fold<int>(0, (sum, row) => sum + (row['qty'] as int)),
      6,
    );
    expect(rows.map((row) => row['width']), containsAll([1190, 1200, 1320]));
  });

  test('close but non-identical measurements remain separate', () {
    final rows = productionMeasurementInstances({
      'quantity': 2,
      'largeur': 1200,
      'hauteur': 1040,
      'confirmed_mesures_json': jsonEncode([
        {'width': 1199.5, 'height': 1040},
        {'width': 1200, 'height': 1040},
      ]),
    });

    expect(rows, hasLength(2));
  });

  test('identical production sizes merge even when positions differ', () {
    final rows = productionMeasurementInstances({
      'quantity': 2,
      'largeur': 1200,
      'hauteur': 1040,
      'confirmed_mesures_json': jsonEncode([
        {'width': 1200, 'height': 1040, 'position': 'A'},
        {'width': 1200, 'height': 1040, 'position': 'B'},
      ]),
    });

    expect(rows, hasLength(1));
    expect(rows.single['qty'], 2);
  });

  test('production batch is capped without exceeding ordered quantity', () {
    final rows = productionMeasurementInstances(
      {
        'quantity': 20,
        'largeur': 1200,
        'hauteur': 1040,
        'confirmed_mesures_json': jsonEncode([
          {'width': 1190, 'height': 1040, 'qty': 4},
          {'width': 1200, 'height': 1040, 'qty': 6},
          {'width': 1320, 'height': 1040, 'qty': 10},
        ]),
      },
      quantityLimit: 7,
    );

    expect(
      rows.fold<int>(0, (sum, row) => sum + (row['qty'] as int)),
      7,
    );
    expect(rows[0]['qty'], 4);
    expect(rows[1]['qty'], 3);
  });
}
