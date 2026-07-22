import 'package:database_data/sql_database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() async {
  // Initialize sqflite ffi
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  print('Initializing database...');
  try {
    final db = await SqlDatabase().db;
    if (db == null) {
      print('Database is null!');
      return;
    }
    print('Database initialized successfully.');

    // Query ShutterComponents
    final list = await db.query('ShutterComponents');
    print('Total components in ShutterComponents: ${list.length}');
    
    final motors = list.where((row) {
      final type = row['component_type']?.toString().toLowerCase() ?? '';
      final name = row['name']?.toString().toLowerCase() ?? '';
      return type == 'moteur' || name.contains('moteur') || name.contains('محرك');
    }).toList();

    print('=== Motors found (${motors.length}) ===');
    for (var m in motors) {
      print(m);
    }
  } catch (e) {
    print('Error: $e');
  }
}
