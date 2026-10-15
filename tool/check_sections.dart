import 'dart:io';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() async {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  final dbPath = r'C:\Users\hp\AppData\Roaming\com.example\database_data\databases\test.db';
  final db = await openDatabase(dbPath, readOnly: true);

  final secIds = [12, 13, 14, 136, 137, 139, 171, 211];
  print('=== SECTIONS IN RULE 4554 ===');
  final secs = await db.rawQuery("SELECT id, name, code, type, series_id FROM Sections WHERE id IN (${secIds.join(',')})");
  for (var s in secs) {
    print(s);
  }

  print('\n=== ALL SECTIONS FOR SERIES 11 (Tpr 40000) ===');
  final all11 = await db.rawQuery("SELECT id, name, code, type FROM Sections WHERE series_id = 11");
  for (var s in all11) {
    print(s);
  }

  await db.close();
}
