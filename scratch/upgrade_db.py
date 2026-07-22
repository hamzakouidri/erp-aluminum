import sys

sys.stdout.reconfigure(encoding='utf-8')

path = 'lib/sql_database.dart'
content = open(path, encoding='utf-8').read()

# 1. Update version to 42
content = content.replace('version: 41,', 'version: 42,')

# 2. Add instances_json to onCreate Table creation for Commandes_details (first place)
old_table_creation1 = """    drawing_image_path TEXT,
    delivered_qty INTEGER DEFAULT 0,
    FOREIGN KEY (id_commandes) REFERENCES Commandes(id) ON DELETE CASCADE"""

new_table_creation1 = """    drawing_image_path TEXT,
    delivered_qty INTEGER DEFAULT 0,
    instances_json TEXT,
    FOREIGN KEY (id_commandes) REFERENCES Commandes(id) ON DELETE CASCADE"""

content = content.replace(old_table_creation1, new_table_creation1)

# 3. Add instances_json to onCreate Table creation for Commandes_details (second place)
old_table_creation2 = """        drawing_image_path TEXT,
        delivered_qty INTEGER DEFAULT 0
      )"""

new_table_creation2 = """        drawing_image_path TEXT,
        delivered_qty INTEGER DEFAULT 0,
        instances_json TEXT
      )"""

content = content.replace(old_table_creation2, new_table_creation2)

# 4. Add migration for oldVersion < 42 in _onUpgrade
old_upgrade_end = """    if (oldVersion < 40) {
      try {
        await db.execute(
          "ALTER TABLE Sections ADD COLUMN max_glass_thickness REAL NOT NULL DEFAULT 0.0;",
        );
      } catch (_) {}
      try {
        await db.execute(
          "ALTER TABLE Sections ADD COLUMN linked_parclose_double_id INTEGER;",
        );
      } catch (_) {}
    }
  }"""

new_upgrade_end = """    if (oldVersion < 40) {
      try {
        await db.execute(
          "ALTER TABLE Sections ADD COLUMN max_glass_thickness REAL NOT NULL DEFAULT 0.0;",
        );
      } catch (_) {}
      try {
        await db.execute(
          "ALTER TABLE Sections ADD COLUMN linked_parclose_double_id INTEGER;",
        );
      } catch (_) {}
    }

    if (oldVersion < 42) {
      try {
        await db.execute(
          "ALTER TABLE Commandes_details ADD COLUMN instances_json TEXT;",
        );
      } catch (_) {}
    }
  }"""

content = content.replace(old_upgrade_end, new_upgrade_end)

open(path, 'w', encoding='utf-8').write(content)
print("Done updating sql_database.dart for version 42 and instances_json column!")
