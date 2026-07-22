import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:database_data/sql_database.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('Dump DB info', () async {
    final dbPathDir = await databaseFactory.getDatabasesPath();
    print('Databases path: $dbPathDir');
    final dbPath = p.join(dbPathDir, 'test.db');
    print('Full DB path: $dbPath');

    final sqlDb = SqlDatabase();
    final db = await sqlDb.db;
    if (db == null) {
      print('DB is null');
      return;
    }

    print('\n--- ALL TABLES ---');
    final tables = await db.rawQuery("SELECT name FROM sqlite_master WHERE type='table';");
    for (var t in tables) {
      final name = t['name'];
      final countRes = await db.rawQuery("SELECT count(*) as c FROM $name;");
      print('Table: $name, Rows: ${countRes.first['c']}');
    }

    print('\n--- SHUTTER COMPONENTS ---');
    final sc = await db.query('ShutterComponents');
    for (var r in sc) {
      print(r);
    }

    print('\n--- ACCESSORIES ---');
    final acc = await db.query('Accessories');
    for (var r in acc.take(20)) {
      print(r);
    }

    print('\n--- JOINTS ---');
    final joints = await db.query('Joints');
    for (var r in joints) {
      print(r);
    }

    print('\n--- KITS/SERIES/SECTIONS with 67000 or 40000 or 76000 ---');
    final series = await db.query('Series');
    for (var r in series) {
      print('Series: $r');
    }
    await db.close();
  });
}
