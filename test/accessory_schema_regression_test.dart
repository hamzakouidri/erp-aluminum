import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:database_data/Commande/Systeme/bom_engine_v2.dart';
import 'package:database_data/Commande/Systeme/calculate_component.dart';
import 'package:database_data/Commande/Systeme/model.dart';
import 'accessory_assembly_rules_test.dart' show RuleDatabase;

class SchemaDatabase extends RuleDatabase {
  SchemaDatabase(this.connection) { rules.clear(); }
  final Database connection;
  @override
  Future<Database?> get db async => connection;
}

void main() {
  test('screw resolution works with Accessories schema without is_default', () async {
    sqfliteFfiInit();
    final connection = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    addTearDown(connection.close);
    await connection.execute('''CREATE TABLE Accessories (
      id INTEGER PRIMARY KEY, is_active INTEGER,
      is_bouchon_batmo_screw INTEGER, is_batmo_screw INTEGER,
      is_renfort_screw INTEGER)''');
    final database = SchemaDatabase(connection);
    // Resolve several series consecutively, as in order aggregation. An
    // empty role is valid and must not abort the product's remaining BOM.
    for (final seriesId in [11, 19, 41]) {
      final model = WindowModel(db: database)
        ..activeSeries = AluminumSeries(id: seriesId, profileId: 1,
          name: 'Series $seriesId', type: 'opening');
      await BomEngineV2(database: database).stabilizeSelections(
        window: model,
        items: [for (final role in ['bouchon_batmo_screw', 'batmo_screw', 'renfort_screw'])
          BomItem(category: 'accessory', originalName: role, name: role,
            quantity: 2, unit: 'pcs', unitPrice: 0, roleKey: role,
            selectorCategory: 'accessory', selectorType: 'is_$role',
            sourceSeriesId: seriesId)],
      );
    }
  });
}
