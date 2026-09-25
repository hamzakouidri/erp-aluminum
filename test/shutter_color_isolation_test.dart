import 'package:flutter_test/flutter_test.dart';
import 'package:database_data/Commande/Systeme/model.dart';
import 'package:database_data/Commande/Systeme/model_serialization.dart';
import 'package:database_data/sql_database.dart';

void main() {
  test('accessory changes do not drive the default shutter colour', () {
    final model = WindowModel(db: SqlDatabase());
    model.selectedAccessoryColor = {'id': 7, 'name': 'Black'};
    expect(model.effectiveShutterColor, isNull);
    model.selectedShutterColor = {'id': 8, 'name': 'Gris'};
    model.selectedAccessoryColor = {'id': 9, 'name': 'White'};
    expect(model.effectiveShutterColor?['id'], 8);
  });
  test('shutter selection is independent and survives serialization', () {
    final model = WindowModel(db: SqlDatabase());
    model.selectedShutterColor = {'id': 8, 'name': 'Gris'};
    expect(model.selectedDbColor, isNull);
    expect(model.selectedAccessoryColor, isNull);
    final saved = model.toMap();
    expect(saved['selectedShutterColor']['id'], 8);
    final restored = WindowModel(db: SqlDatabase());
    applyWindowModelFromMap(restored, saved);
    expect(restored.selectedShutterColor?['id'], 8);
    expect(restored.effectiveShutterColor?['name'], 'Gris');
  });
}
