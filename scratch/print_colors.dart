import 'dart:io';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart' as p;

void main() async {
  sqfliteFfiInit();
  var databaseFactory = databaseFactoryFfi;
  String dbPath = await databaseFactory.getDatabasesPath();
  String path = p.join(dbPath, 'test.db');
  
  print('Opening database at: $path');
  if (!File(path).existsSync()) {
    print('Database file does not exist!');
    return;
  }
  
  var db = await databaseFactory.openDatabase(path);
  try {
    var colors = await db.query('Colors');
    print('--- Colors in Database ---');
    for (var color in colors) {
      print('ID: ${color['id']} | Name: ${color['name']} | Hex: ${color['hex_code']} | Type: ${color['type']} | Active: ${color['is_active']}');
    }
  } catch (e) {
    print('Error querying Colors: $e');
  } finally {
    await db.close();
  }
}
