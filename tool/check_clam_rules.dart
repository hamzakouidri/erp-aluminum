import 'dart:io';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() async {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  final dbPath = r'C:\Users\hp\AppData\Roaming\com.example\database_data\databases\test.db';
  final db = await openDatabase(dbPath, readOnly: true);

  print('=== Series 40000 ===');
  final s = await db.rawQuery("SELECT * FROM Series WHERE name LIKE '%40000%'");
  for (var row in s) {
    print('Series: id=${row['id']}, name=${row['name']}, type=${row['type']}');
  }

  print('\n=== CatalogItemRules related to clam or 40000 ===');
  final rules = await db.rawQuery("""
    SELECT r.*, a.name as acc_name 
    FROM CatalogItemRules r 
    LEFT JOIN Accessories a ON r.item_id = a.id 
    WHERE r.role_key LIKE '%clam%' OR r.series_id IN (SELECT id FROM Series WHERE name LIKE '%40000%')
  """);
  for (var r in rules) {
    print('Rule: id=${r['id']}, item_id=${r['item_id']} (${r['acc_name']}), series_id=${r['series_id']}, role=${r['role_key']}, target=${r['assembly_target']}, top_qty=${r['top_corner_qty']}, bot_qty=${r['bottom_corner_qty']}, section_ids=${r['assembly_section_ids']}, section_qtys=${r['assembly_section_quantities']}');
  }

  print('\n=== Accessories with name like clam ===');
  final accs = await db.rawQuery("SELECT id, name, type FROM Accessories WHERE name LIKE '%clam%' OR name LIKE '%كلام%'");
  for (var a in accs) {
    print(a);
  }

  await db.close();
}
