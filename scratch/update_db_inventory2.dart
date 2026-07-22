import 'dart:io';

void main() {
  String path = 'lib/sql_database.dart';
  String content = File(path).readAsStringSync();
  
  String inventoryTables = '''
  CREATE TABLE Workshop_Stock (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    item_type TEXT NOT NULL, 
    item_id INTEGER NOT NULL,
    color_id INTEGER,
    quantity REAL NOT NULL DEFAULT 0.0,
    bar_length REAL
  );

  CREATE TABLE Iron_Chutes (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    length REAL NOT NULL
  );

  CREATE TABLE Purchase_Lists (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    commande_id INTEGER,
    created_at TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'pending',
    details_json TEXT NOT NULL
  );
''';

  if (content.contains('CREATE TABLE Workshop_Stock')) {
    print('Inventory tables already exist');
    return;
  }
  
  int createIndex = content.indexOf('  CREATE TABLE Commandes_details (');
  if (createIndex != -1) {
    content = content.replaceRange(createIndex, createIndex, inventoryTables + '\n');
    File(path).writeAsStringSync(content);
    print("Added inventory tables to sql_database.dart");
  } else {
    print("Could not find insertion point.");
  }
}
