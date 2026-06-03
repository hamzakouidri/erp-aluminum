import re

file_path = "lib/sql_database.dart"
with open(file_path, "r", encoding="utf-8") as f:
    content = f.read()

# Bump version to 7
content = content.replace("version: 6,", "version: 7,")

# Add _onUpgrade logic for version 7
upgrade_logic = """
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
"""

# Insert it at the end of _onUpgrade
content = content.replace(
    "void _onCreate(Database db, int version) async {",
    upgrade_logic + "\n  void _onCreate(Database db, int version) async {"
)

with open(file_path, "w", encoding="utf-8") as f:
    f.write(content)
