import sys

with open('lib/sql_database.dart', 'r', encoding='utf-8') as f:
    content = f.read()

s1 = '''      // Shutters Table
      await db.execute("""
        CREATE TABLE Shutters (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          type TEXT NOT NULL,
          color_id INTEGER,
          price_per_sqm REAL NOT NULL
        )
      """);'''

s2 = '''      // Shutter Components Table
      await db.execute("""
        CREATE TABLE ShutterComponents (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          component_type TEXT NOT NULL,
          price REAL NOT NULL,
          unit TEXT NOT NULL,
          created_at TEXT DEFAULT CURRENT_TIMESTAMP
        )
      """);'''

s1 = s1.replace('"""', "'''")
s2 = s2.replace('"""', "'''")
content = content.replace(s1, s2)

s3 = '''    await db.execute("""
    CREATE TABLE Shutters (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      type TEXT NOT NULL,
      color_id INTEGER,
      price_per_sqm REAL NOT NULL
    )
    """);'''
s4 = '''    await db.execute("""
    CREATE TABLE ShutterComponents (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      component_type TEXT NOT NULL,
      price REAL NOT NULL,
      unit TEXT NOT NULL,
      created_at TEXT DEFAULT CURRENT_TIMESTAMP
    )
    """);'''
s3 = s3.replace('"""', "'''")
s4 = s4.replace('"""', "'''")
content = content.replace(s3, s4)

content = content.replace("'Shutters', 'SeriesColorPrices'", "'ShutterComponents', 'SeriesColorPrices'")
content = content.replace("'ProfileColors', 'SeriesColorPrices', 'Shutters', 'Glass'", "'ProfileColors', 'SeriesColorPrices', 'ShutterComponents', 'Glass'")

# Methods
methods_old = '''  //////////////////////////////////// Shutters //////////////////////////////////////
  Future<List<Map<String, dynamic>>> readShutters() async {
    Database? myDb = await db;
    return await myDb!.query('Shutters');
  }


  Future<int> insertShutter(String name, String type, int? colorId, double pricePerSqm) async {
    Database? myDb = await db;
    var res = await myDb!.insert('Shutters', {'name': name, 'type': type, 'color_id': colorId, 'price_per_sqm': pricePerSqm});
    CloudSyncService().notifyChange();
    return res;
  }

  Future<int> updateShutter(int id, String name, String type, int? colorId, double pricePerSqm) async {
    Database? myDb = await db;
    var res = await myDb!.update('Shutters', {'name': name, 'type': type, 'color_id': colorId, 'price_per_sqm': pricePerSqm}, where: 'id = ?', whereArgs: [id]);
    CloudSyncService().notifyChange();
    return res;
  }

  Future<int> deleteShutter(int id) async {
    Database? myDb = await db;
    var res = await myDb!.delete('Shutters', where: 'id = ?', whereArgs: [id]);
    CloudSyncService().notifyChange();
    return res;
  }'''

methods_new = '''  //////////////////////////////////// ShutterComponents //////////////////////////////////////
  Future<List<Map<String, dynamic>>> readShutterComponents() async {
    Database? myDb = await db;
    return await myDb!.query('ShutterComponents');
  }

  Future<int> insertShutterComponent(String name, String componentType, double price, String unit) async {
    Database? myDb = await db;
    var res = await myDb!.insert('ShutterComponents', {'name': name, 'component_type': componentType, 'price': price, 'unit': unit});
    CloudSyncService().notifyChange();
    return res;
  }

  Future<int> updateShutterComponent(int id, String name, String componentType, double price, String unit) async {
    Database? myDb = await db;
    var res = await myDb!.update('ShutterComponents', {'name': name, 'component_type': componentType, 'price': price, 'unit': unit}, where: 'id = ?', whereArgs: [id]);
    CloudSyncService().notifyChange();
    return res;
  }

  Future<int> deleteShutterComponent(int id) async {
    Database? myDb = await db;
    var res = await myDb!.delete('ShutterComponents', where: 'id = ?', whereArgs: [id]);
    CloudSyncService().notifyChange();
    return res;
  }'''
content = content.replace(methods_old, methods_new)

with open('lib/sql_database.dart', 'w', encoding='utf-8') as f:
    f.write(content)
