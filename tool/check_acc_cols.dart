import 'dart:io';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() async {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  final dbPath = r'C:\Users\hp\AppData\Roaming\com.example\database_data\databases\test.db';
  final db = await openDatabase(dbPath);
  final cols = await db.rawQuery('PRAGMA table_info(Accessories)');
  print('Accessories columns:');
  for (var c in cols) {
    print(' - ${c["name"]} (${c["type"]})');
  }
  await db.close();
}
