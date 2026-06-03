import re

file_path = "lib/sql_database.dart"
with open(file_path, "r", encoding="utf-8") as f:
    content = f.read()

# The incorrect snippet
incorrect_snippet = """    }
  }

  
    if (oldVersion < 7) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS SeriesColorPrices (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          series_id INTEGER NOT NULL,
          color_id INTEGER NOT NULL,
          price REAL NOT NULL DEFAULT 0.0,
          UNIQUE(series_id, color_id)
        )
      ''');
    }

  void _onCreate(Database db, int version) async {"""

# The correct snippet
correct_snippet = """      } catch (e) {
        print('Column price already exists or error: $e');
      }
    }
    if (oldVersion < 7) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS SeriesColorPrices (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          series_id INTEGER NOT NULL,
          color_id INTEGER NOT NULL,
          price REAL NOT NULL DEFAULT 0.0,
          UNIQUE(series_id, color_id)
        )
      ''');
    }
  }

  void _onCreate(Database db, int version) async {"""

# We need to target the larger block to replace it reliably
content = re.sub(r'      \} catch \(e\) \{\n        print\(\'Column price already exists or error: \$e\'\);\n      \}\n    \}\n  \}\n\n  \n    if \(oldVersion < 7\) \{\n      await db\.execute\(\'\'\'\n        CREATE TABLE IF NOT EXISTS SeriesColorPrices \(\n          id INTEGER PRIMARY KEY AUTOINCREMENT,\n          series_id INTEGER NOT NULL,\n          color_id INTEGER NOT NULL,\n          price REAL NOT NULL DEFAULT 0\.0,\n          UNIQUE\(series_id, color_id\)\n        \)\n      \'\'\'\);\n    \}\n\n  void _onCreate\(Database db, int version\) async \{', correct_snippet, content)

with open(file_path, "w", encoding="utf-8") as f:
    f.write(content)
