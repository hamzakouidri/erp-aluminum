import 'dart:io';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() async {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  final dbPath = r'C:\Users\hp\AppData\Roaming\com.example\database_data\databases\test.db';
  print('Opening $dbPath...');
  final db = await openDatabase(dbPath, readOnly: true);

  // 1. Accessories
  final accRows = await db.rawQuery('SELECT COUNT(*) as count FROM Accessories');
  print('\n=== TOTAL ACCESSORIES: ${accRows.first['count']} ===');
  final accs = await db.query('Accessories');
  
  // Check which accessories have matching image in assets/sections or assets/images or Icon
  int accWithImage = 0;
  int accWithoutImage = 0;
  final missingAccs = <Map<String, dynamic>>[];

  for (var a in accs) {
    final name = (a['name'] ?? '').toString();
    final type = (a['type'] ?? '').toString();
    final id = a['id'];
    
    // Check possible image filenames
    bool found = false;
    // Check direct files in assets/sections or assets/images or Icon
    final candidates = [
      'assets/sections/$name.png',
      'assets/sections/$name.svg',
      'assets/images/$name.png',
      'assets/Icon/$name.png',
      'assets/Icon/$name.jpg',
    ];
    for (var c in candidates) {
      if (File(c).existsSync()) {
        found = true;
        break;
      }
    }

    if (found) {
      accWithImage++;
    } else {
      accWithoutImage++;
      missingAccs.add(a);
    }
  }

  print('Accessories with image: $accWithImage');
  print('Accessories without image: $accWithoutImage');
  print('\n--- Accessories WITHOUT image (first 50) ---');
  for (var m in missingAccs.take(50)) {
    print('ID: ${m['id']} | Name: "${m['name']}" | Type: "${m['type']}"');
  }

  // 2. Sections (Profiles)
  final secRows = await db.rawQuery('SELECT COUNT(*) as count FROM Sections');
  print('\n=== TOTAL SECTIONS: ${secRows.first['count']} ===');
  final secs = await db.query('Sections');
  int secWithImage = 0;
  int secWithoutImage = 0;
  final missingSecs = <Map<String, dynamic>>[];

  for (var s in secs) {
    final code = (s['code'] ?? '').toString().trim();
    final name = (s['name'] ?? '').toString().trim();
    final id = s['id'];

    bool found = false;
    final candidates = [
      'assets/sections/$code.png',
      'assets/sections/$code.svg',
      'assets/sections/$code.jpg',
    ];
    for (var c in candidates) {
      if (File(c).existsSync()) {
        found = true;
        break;
      }
    }

    if (found) {
      secWithImage++;
    } else {
      secWithoutImage++;
      missingSecs.add(s);
    }
  }

  print('Sections with image: $secWithImage');
  print('Sections without image: $secWithoutImage');
  print('\n--- Sections WITHOUT image (first 50) ---');
  for (var s in missingSecs.take(50)) {
    print('ID: ${s['id']} | Code: "${s['code']}" | Name: "${s['name']}" | SeriesID: ${s['series_id']}');
  }

  // 3. Profiles table
  print('\n=== PROFILES TABLE ===');
  final profs = await db.query('Profile');
  for (var p in profs) {
    print('Profile ID: ${p['id']} | Name: "${p['name']}" | Type: "${p['type']}"');
  }

  await db.close();
}
