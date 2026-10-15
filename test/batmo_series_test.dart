import 'dart:ui';

import 'package:database_data/Commande/Systeme/calculate_component.dart';
import 'package:database_data/Commande/Systeme/model.dart';
import 'package:database_data/sql_database.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('opening battements retain their series in a sliding primary drawing', () {
    final window = WindowModel(
      db: SqlDatabase(),
      width: 1200,
      height: 1500,
      profileThickness: 60,
      systemMode: 'sliding',
    );
    addTearDown(window.dispose);
    window.activeSeries = AluminumSeries(
      id: 10,
      profileId: 1,
      name: 'Opening',
      type: 'opening',
      sections: [],
    );
    window.activeSlidingSeries = AluminumSeries(
      id: 20,
      profileId: 1,
      name: 'Sliding',
      type: 'sliding',
      sections: [],
    );
    window.zones = [
      WindowZone(
        id: 'double',
        boundary: const Rect.fromLTWH(60, 60, 1080, 1380),
        content: ZoneContent.doubleSash,
      ),
    ];
    final rows = ComponentCalculator.generateBom(window, {});
    final batmo = rows.singleWhere((row) => row.roleKey == 'batmo');
    expect(batmo.sourceSeriesId, 10);
    expect(rows.where((row) => row.roleKey == 'bouchon_batmo'), isEmpty);
  });
}
