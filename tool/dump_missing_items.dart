import 'dart:io';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() async {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  final dbPath = r'C:\Users\hp\AppData\Roaming\com.example\database_data\databases\test.db';
  final db = await openDatabase(dbPath, readOnly: true);

  final accs = await db.query('Accessories');
  print('=== ALL ACCESSORIES (${accs.length}) ===');
  for (var a in accs) {
    print('ID: ${a['id']} | Name: "${a['name']}" | Type: "${a['type']}"');
  }

  final secs = await db.query('Sections');
  final missingCodes = <String, Map<String, dynamic>>{};
  for (var s in secs) {
    final rawCode = (s['code'] ?? '').toString().trim();
    final cleanCode = rawCode.replaceAll(' ', '');
    final f1 = File('assets/sections/$rawCode.png');
    final f2 = File('assets/sections/$cleanCode.png');
    final f3 = File('assets/sections/$rawCode.svg');
    final f4 = File('assets/sections/$cleanCode.svg');
    if (!f1.existsSync() && !f2.existsSync() && !f3.existsSync() && !f4.existsSync()) {
      if (!missingCodes.containsKey(rawCode)) {
        missingCodes[rawCode] = s;
      }
    }
  }

  print('\n=== DISTINCT SECTION CODES MISSING IMAGES (${missingCodes.length}) ===');
  missingCodes.forEach((code, s) {
    print('Code: "$code" | Name: "${s['name']}"');
  });

  await db.close();
}
