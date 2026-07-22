import re

file_path = "lib/sql_database.dart"
with open(file_path, "r", encoding="utf-8") as f:
    content = f.read()

# Bump version to 22
content = content.replace("version: 21,", "version: 22,")

# Add missing columns to Sections in _onCreate (if they don't exist yet)
old_create_sections = """        CREATE TABLE Sections (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          series_id INTEGER NOT NULL,
          code TEXT NOT NULL,
          name TEXT NOT NULL,
          type TEXT NOT NULL,
          thickness REAL NOT NULL,
          glass_deduction REAL NOT NULL,
          weight_per_meter REAL NOT NULL,
          couvre_joint_width REAL NOT NULL DEFAULT 0.0,
          bar_length REAL NOT NULL DEFAULT 5.8,
          FOREIGN KEY (series_id) REFERENCES Series(id) ON DELETE CASCADE
        )"""

new_create_sections = """        CREATE TABLE Sections (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          series_id INTEGER NOT NULL,
          code TEXT NOT NULL,
          name TEXT NOT NULL,
          type TEXT NOT NULL,
          thickness REAL NOT NULL,
          glass_deduction REAL NOT NULL,
          weight_per_meter REAL NOT NULL,
          couvre_joint_width REAL NOT NULL DEFAULT 0.0,
          bar_length REAL NOT NULL DEFAULT 5.8,
          linked_renfort_id INTEGER,
          renfort_deduction REAL NOT NULL DEFAULT 140.0,
          cutting_deduction REAL NOT NULL DEFAULT 0.0,
          visible_width REAL NOT NULL DEFAULT 0.0,
          sash_overlap REAL NOT NULL DEFAULT 0.0,
          FOREIGN KEY (series_id) REFERENCES Series(id) ON DELETE CASCADE
        )"""

content = content.replace(old_create_sections, new_create_sections)

# In onUpgrade, add an upgrade for < 22 to ALTER TABLE Sections
# Find the end of onUpgrade which is:
#     if (oldVersion < 5) {
#       await db.execute('''

old_onupgrade = """    if (oldVersion < 22) {
      try {
        await db.execute(
          'ALTER TABLE Accessories ADD COLUMN screw_count INTEGER NOT NULL DEFAULT 0;',
        );
      } catch (_) {}
    }
    if (oldVersion < 5) {"""

new_onupgrade = """    if (oldVersion < 22) {
      try {
        await db.execute(
          'ALTER TABLE Accessories ADD COLUMN screw_count INTEGER NOT NULL DEFAULT 0;',
        );
      } catch (_) {}
      
      // Add missing section columns
      try { await db.execute('ALTER TABLE Sections ADD COLUMN linked_renfort_id INTEGER;'); } catch (_) {}
      try { await db.execute('ALTER TABLE Sections ADD COLUMN renfort_deduction REAL NOT NULL DEFAULT 140.0;'); } catch (_) {}
      try { await db.execute('ALTER TABLE Sections ADD COLUMN cutting_deduction REAL NOT NULL DEFAULT 0.0;'); } catch (_) {}
      try { await db.execute('ALTER TABLE Sections ADD COLUMN visible_width REAL NOT NULL DEFAULT 0.0;'); } catch (_) {}
      try { await db.execute('ALTER TABLE Sections ADD COLUMN sash_overlap REAL NOT NULL DEFAULT 0.0;'); } catch (_) {}
    }
    if (oldVersion < 5) {"""

content = content.replace(old_onupgrade, new_onupgrade)

# Update insertSection signature and body
old_insert_section = """  Future<int> insertSection({
    required int seriesId,
    required String code,
    required String name,
    required String type,
    required double thickness,
    required double glassDeduction,
    required double weightPerMeter,
    double couvreJointWidth = 0.0,
    double barLength = 5.8,
  }) async {
    Database? myDb = await db;
    var res = await myDb!.insert('Sections', {
      'series_id': seriesId,
      'code': code,
      'name': name,
      'type': type,
      'thickness': thickness,
      'glass_deduction': glassDeduction,
      'weight_per_meter': weightPerMeter,
      'couvre_joint_width': couvreJointWidth,
      'bar_length': barLength,
    });"""

new_insert_section = """  Future<int> insertSection({
    required int seriesId,
    required String code,
    required String name,
    required String type,
    required double thickness,
    required double glassDeduction,
    required double weightPerMeter,
    double couvreJointWidth = 0.0,
    double barLength = 5.8,
    int? linkedRenfortId,
    double renfortDeduction = 140.0,
    double cuttingDeduction = 0.0,
    double visibleWidth = 0.0,
    double sashOverlap = 0.0,
  }) async {
    Database? myDb = await db;
    var res = await myDb!.insert('Sections', {
      'series_id': seriesId,
      'code': code,
      'name': name,
      'type': type,
      'thickness': thickness,
      'glass_deduction': glassDeduction,
      'weight_per_meter': weightPerMeter,
      'couvre_joint_width': couvreJointWidth,
      'bar_length': barLength,
      'linked_renfort_id': linkedRenfortId,
      'renfort_deduction': renfortDeduction,
      'cutting_deduction': cuttingDeduction,
      'visible_width': visibleWidth,
      'sash_overlap': sashOverlap,
    });"""

content = content.replace(old_insert_section, new_insert_section)

with open(file_path, "w", encoding="utf-8") as f:
    f.write(content)

print("sql_database.dart updated.")
