import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:database_data/Commande/Systeme/model.dart';
import 'package:database_data/sql_database.dart';

void main() {
  test('catalog defaults and dimensions alone are not a drawing', () {
    final model = WindowModel(db: SqlDatabase(), width: 1200, height: 1000);
    expect(model.hasDrawnGeometry, isFalse);
  });

  test('an actual frame counts even before adding a sash', () {
    final model = WindowModel(db: SqlDatabase(), width: 1200, height: 1000);
    model.zones.add(WindowZone(
      id: 'frame',
      boundary: const Rect.fromLTWH(0, 0, 1200, 1000),
    ));
    expect(model.hasDrawnGeometry, isTrue);
    model.zones.clear();
    expect(model.hasDrawnGeometry, isFalse);
  });

  test('a standalone shutter requires positive dimensions', () {
    final model = WindowModel(db: SqlDatabase())..isShutterOnly = true;
    expect(model.hasDrawnGeometry, isFalse);
    model.width = 1200;
    model.height = 1000;
    expect(model.hasDrawnGeometry, isTrue);
  });
}
