import 'dart:io';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() async {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  final db = await openDatabase('assets/database.db');
  
  final accRows = await db.rawQuery('SELECT COUNT(*) as count FROM Accessories');
  final accCount = accRows.first['count'];
  print('Total Accessories: $accCount');

  final accs = await db.query('Accessories');
  print('\n=== ALL ACCESSORIES ===');
  for (var a in accs) {
    print('${a["id"]} | ${a["name"]} | ${a["type"]} | ${a["material_type"]}');
  }

  final secRows = await db.rawQuery('SELECT COUNT(*) as count FROM Sections');
  final secCount = secRows.first['count'];
  print('\nTotal Sections: $secCount');

  final secs = await db.query('Sections');
  print('\n=== SECTIONS MISSING IMAGES OR SUMMARY ===');
  int missingImg = 0;
  for (var s in secs) {
    final code = s['code']?.toString() ?? '';
    final img = s['image_path']?.toString() ?? '';
    // Check if file exists in assets/sections
    final f = File('assets/sections/$code.png');
    final fSvg = File('assets/sections/$code.svg');
    if (!f.existsSync() && !fSvg.existsSync()) {
      missingImg++;
      print('Section ${s["id"]}: code="$code" | name="${s["name"]}" (image missing on disk: assets/sections/$code.png)');
    }
  }
  print('Total sections missing images on disk: $missingImg / $secCount');

  await db.close();
}
