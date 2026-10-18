import 'package:database_data/Commande/Systeme/model.dart';
import 'package:database_data/Screen/moustiquaire_screen.dart';
import 'package:database_data/sql_database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _PriceDatabase extends SqlDatabase {
  _PriceDatabase(this.connection);

  final Database connection;

  @override
  Future<Database?> get db async => connection;
}

void main() {
  test('each mosquito-net type has its own price key', () {
    expect(
      MoustiquaireType.values.map(moustiquaireTypePriceKey),
      moustiquaireTypePriceKeys.map((entry) => entry.$1),
    );
  });

  test('mosquito-net prices are never taken as a shutter blade price', () {
    final price = WindowModel.resolveShutterSqmPrice(
      bladeName: 'Enroulable',
      bladeSubtype: 'normal',
      colorId: null,
      prices: const [
        {'blade_type': 'Moustiquaire_enroulable', 'color_id': 0, 'price_per_sqm': 6000},
        {'blade_type': 'Enroulable', 'color_id': 0, 'price_per_sqm': 8500},
      ],
    );
    expect(price, 8500);
  });

  test('a mosquito net is priced in its colour, else for every colour', () async {
    sqfliteFfiInit();
    final connection = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
    );
    addTearDown(connection.close);
    await connection.execute(
      'CREATE TABLE ShutterSqmPrices (id INTEGER PRIMARY KEY, '
      'blade_type TEXT, color_id INTEGER, price_per_sqm REAL, '
      'UNIQUE(blade_type, color_id))',
    );
    for (final row in [
      {'blade_type': 'Moustiquaire_Sqm', 'color_id': 0, 'price_per_sqm': 4000},
      {'blade_type': 'Moustiquaire_Sqm', 'color_id': 7, 'price_per_sqm': 5200},
      // A colour added without its price yet keeps the general price.
      {'blade_type': 'Moustiquaire_Sqm', 'color_id': 9, 'price_per_sqm': 0},
    ]) {
      await connection.insert('ShutterSqmPrices', row);
    }
    final db = _PriceDatabase(connection);

    expect(await db.getShutterSqmPriceForColor('Moustiquaire_Sqm', 7), 5200);
    expect(await db.getShutterSqmPriceForColor('Moustiquaire_Sqm', 9), 4000);
    expect(await db.getShutterSqmPriceForColor('Moustiquaire_Sqm', 3), 4000);
    expect(await db.getShutterSqmPriceForColor('Moustiquaire_Sqm', null), 4000);
  });
}
