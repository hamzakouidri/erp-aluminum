import 'dart:io';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() async {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  final dbPath = r'C:\Users\hp\AppData\Roaming\com.example\database_data\databases\test.db';
  final db = await openDatabase(dbPath, readOnly: true);
  final items = await db.rawQuery("SELECT id, name, type FROM Accessories WHERE name LIKE '%tasso%' OR name LIKE '%clam%' OR name LIKE '%equerre%' OR name LIKE '%طاسو%' OR name LIKE '%كلام%' OR name LIKE '%إيكار%' OR name LIKE '%fixation%' OR name LIKE '%patte%' OR name LIKE '%calle%'");
  for (var i in items) {
    print('${i["id"]} | ${i["name"]} | ${i["type"]}');
  }
  await db.close();
}
