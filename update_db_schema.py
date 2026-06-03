import sys

with open('lib/sql_database.dart', 'r', encoding='utf-8') as f:
    content = f.read()

# Modify Accessories Table
old_accessories = '''          CREATE TABLE IF NOT EXISTS Accessories (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            type TEXT NOT NULL,
            price REAL NOT NULL
          )
'''
new_accessories = '''          CREATE TABLE IF NOT EXISTS Accessories (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            material_type TEXT NOT NULL DEFAULT 'Aluminium',
            scope TEXT NOT NULL DEFAULT 'Global',
            series_id INTEGER,
            type TEXT NOT NULL,
            price REAL NOT NULL DEFAULT 0.0
          )
'''
content = content.replace(old_accessories, new_accessories)

# Modify Sections Table
old_sections = '''          CREATE TABLE IF NOT EXISTS Sections (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            nom TEXT NOT NULL,
            type TEXT NOT NULL,
            quantite INTEGER NOT NULL,
            reference TEXT NOT NULL
          )
'''
new_sections = '''          CREATE TABLE IF NOT EXISTS Sections (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            nom TEXT NOT NULL,
            type TEXT NOT NULL,
            quantite INTEGER NOT NULL,
            reference TEXT NOT NULL,
            price REAL NOT NULL DEFAULT 0.0
          )
'''
content = content.replace(old_sections, new_sections)

# Add AccessoryColorPrices
old_tables_end = '''          CREATE TABLE IF NOT EXISTS Achats (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            total REAL NOT NULL,
            versement REAL NOT NULL,
            date TEXT NOT NULL
          )
        ''');'''

new_tables_end = '''          CREATE TABLE IF NOT EXISTS Achats (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            total REAL NOT NULL,
            versement REAL NOT NULL,
            date TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE IF NOT EXISTS AccessoryColorPrices (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            accessory_id INTEGER NOT NULL,
            color_id INTEGER NOT NULL,
            price REAL NOT NULL DEFAULT 0.0,
            UNIQUE(accessory_id, color_id)
          )
        ''');
'''
content = content.replace(old_tables_end, new_tables_end)

# Add AccessoryColorPrices to the list of tables in exportAllData
old_export_list = "'SeriesColorPrices', 'ShutterComponents', 'Glass', 'Joints',"
new_export_list = "'SeriesColorPrices', 'AccessoryColorPrices', 'ShutterComponents', 'Glass', 'Joints',"
content = content.replace(old_export_list, new_export_list)

# Add methods for AccessoryColorPrices
methods = '''
  // Accessory Color Prices Methods
  Future<int> setAccessoryColorPrice(int accessoryId, int colorId, double price) async {
    Database? myDb = await db;
    var existing = await myDb!.query('AccessoryColorPrices',
        where: 'accessory_id = ? AND color_id = ?',
        whereArgs: [accessoryId, colorId]);

    if (existing.isNotEmpty) {
      return await myDb.update(
        'AccessoryColorPrices',
        {'price': price},
        where: 'accessory_id = ? AND color_id = ?',
        whereArgs: [accessoryId, colorId],
      );
    } else {
      return await myDb.insert('AccessoryColorPrices', {
        'accessory_id': accessoryId,
        'color_id': colorId,
        'price': price,
      });
    }
  }

  Future<List<Map<String, dynamic>>> getAccessoryColorPrices(int accessoryId) async {
    Database? myDb = await db;
    return await myDb!.query('AccessoryColorPrices',
        where: 'accessory_id = ?', whereArgs: [accessoryId]);
  }
'''
if 'setAccessoryColorPrice' not in content:
    idx = content.rfind('}')
    if idx != -1:
        content = content[:idx] + methods + content[idx:]

with open('lib/sql_database.dart', 'w', encoding='utf-8') as f:
    f.write(content)
