import sys
import re

with open('lib/sql_database.dart', 'r', encoding='utf-8') as f:
    content = f.read()

# Fix the Glass table that I accidentally replaced with Sections
# I will just replace the bad sections with Glass AND Sections
bad_sections = """      // Glass Table
      await db.execute('''
          CREATE TABLE IF NOT EXISTS Sections (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            nom TEXT NOT NULL,
            type TEXT NOT NULL,
            quantite INTEGER NOT NULL,
            reference TEXT NOT NULL,
            price REAL NOT NULL DEFAULT 0.0
          )
      ''');"""

good_glass_and_sections = """      // Glass Table
      await db.execute('''
        CREATE TABLE Glass (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          type TEXT NOT NULL,
          thickness REAL NOT NULL,
          price_per_sqm REAL NOT NULL
        )
      ''');
      // Sections Table
      await db.execute('''
        CREATE TABLE IF NOT EXISTS Sections (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          nom TEXT NOT NULL,
          type TEXT NOT NULL,
          quantite INTEGER NOT NULL,
          reference TEXT NOT NULL,
          price REAL NOT NULL DEFAULT 0.0
        )
      ''');"""

content = content.replace(bad_sections, good_glass_and_sections)

# Add AccessoryColorPrices
old_achats_end = """      // Achats Table
      await db.execute('''
        CREATE TABLE Achats (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          total REAL NOT NULL,
          versement REAL NOT NULL,
          date TEXT NOT NULL
        )
      ''');
    });"""

new_achats_end = """      // Achats Table
      await db.execute('''
        CREATE TABLE Achats (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          total REAL NOT NULL,
          versement REAL NOT NULL,
          date TEXT NOT NULL
        )
      ''');
      
      // AccessoryColorPrices Table
      await db.execute('''
        CREATE TABLE IF NOT EXISTS AccessoryColorPrices (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          accessory_id INTEGER NOT NULL,
          color_id INTEGER NOT NULL,
          price REAL NOT NULL DEFAULT 0.0,
          UNIQUE(accessory_id, color_id)
        )
      ''');
    });"""

content = content.replace(old_achats_end, new_achats_end)

# Add AccessoryColorPrices methods
methods = """
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
}
"""
if 'setAccessoryColorPrice' not in content:
    idx = content.rfind('}')
    if idx != -1:
        content = content[:idx] + methods

with open('lib/sql_database.dart', 'w', encoding='utf-8') as f:
    f.write(content)
