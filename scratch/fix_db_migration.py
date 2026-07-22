import re

file_path = "lib/sql_database.dart"
with open(file_path, "r", encoding="utf-8") as f:
    content = f.read()

# Fix CREATE TABLE Sections
old_create_sections = """      CREATE TABLE Sections (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      series_id INTEGER NOT NULL,
      code TEXT NOT NULL,
      name TEXT NOT NULL,
      type TEXT NOT NULL,
      thickness REAL NOT NULL,
      glass_deduction REAL NOT NULL DEFAULT 0.0,
      weight_per_meter REAL NOT NULL DEFAULT 0.0,
      couvre_joint_width REAL NOT NULL DEFAULT 0.0,
      bar_length REAL NOT NULL DEFAULT 5.8,"""

new_create_sections = """      CREATE TABLE Sections (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      series_id INTEGER NOT NULL,
      code TEXT NOT NULL,
      name TEXT NOT NULL,
      type TEXT NOT NULL,
      thickness REAL NOT NULL,
      glass_deduction REAL NOT NULL DEFAULT 0.0,
      weight_per_meter REAL NOT NULL DEFAULT 0.0,
      couvre_joint_width REAL NOT NULL DEFAULT 0.0,
      bar_length REAL NOT NULL DEFAULT 5.8,
      cutting_deduction REAL NOT NULL DEFAULT 0.0,
      visible_width REAL NOT NULL DEFAULT 0.0,
      sash_overlap REAL NOT NULL DEFAULT 0.0,
      linked_renfort_id INTEGER,
      renfort_deduction REAL NOT NULL DEFAULT 140.0,"""

content = content.replace(old_create_sections, new_create_sections)

# Let's also check if linked_renfort_id and renfort_deduction are handled in insertSection and updateSection.
old_insert_section = """  Future<int> insertSection({
    required int seriesId,
    required String code,
    required String name,
    required String type,
    required double thickness,
    required double glassDeduction,
    required double weightPerMeter,
    double couvreJointWidth = 0.0,
    double cuttingDeduction = 0.0,
    double visibleWidth = 0.0,
    double sashOverlap = 0.0,
    double barLength = 5.8,
  }) async {"""

new_insert_section = """  Future<int> insertSection({
    required int seriesId,
    required String code,
    required String name,
    required String type,
    required double thickness,
    required double glassDeduction,
    required double weightPerMeter,
    double couvreJointWidth = 0.0,
    double cuttingDeduction = 0.0,
    double visibleWidth = 0.0,
    double sashOverlap = 0.0,
    double barLength = 5.8,
    int? linkedRenfortId,
    double renfortDeduction = 140.0,
  }) async {"""

content = content.replace(old_insert_section, new_insert_section)

# Update the map in insertSection
old_insert_map = """      'visible_width': visibleWidth,
      'sash_overlap': sashOverlap,
      'bar_length': barLength,
    });"""

new_insert_map = """      'visible_width': visibleWidth,
      'sash_overlap': sashOverlap,
      'bar_length': barLength,
      'linked_renfort_id': linkedRenfortId,
      'renfort_deduction': renfortDeduction,
    });"""

content = content.replace(old_insert_map, new_insert_map)

# Let's check updateSection
old_update_section = """  Future<int> updateSection(
    int id,
    String code,
    String name,
    double thickness,
    double glassDeduction,
    double weightPerMeter,
    double couvreJointWidth,
    double barLength,
  ) async {"""

new_update_section = """  Future<int> updateSection(
    int id,
    String code,
    String name,
    double thickness,
    double glassDeduction,
    double weightPerMeter,
    double couvreJointWidth,
    double barLength, {
    double cuttingDeduction = 0.0,
    double visibleWidth = 0.0,
    double sashOverlap = 0.0,
    int? linkedRenfortId,
    double renfortDeduction = 140.0,
  }) async {"""

content = content.replace(old_update_section, new_update_section)

old_update_map = """      'glass_deduction': glassDeduction,
      'weight_per_meter': weightPerMeter,
      'couvre_joint_width': couvreJointWidth,
      'bar_length': barLength,
    },"""

new_update_map = """      'glass_deduction': glassDeduction,
      'weight_per_meter': weightPerMeter,
      'couvre_joint_width': couvreJointWidth,
      'bar_length': barLength,
      'cutting_deduction': cuttingDeduction,
      'visible_width': visibleWidth,
      'sash_overlap': sashOverlap,
      'linked_renfort_id': linkedRenfortId,
      'renfort_deduction': renfortDeduction,
    },"""

content = content.replace(old_update_map, new_update_map)

# We also need to add ALTER statements for linked_renfort_id and renfort_deduction in onUpgrade
# Let's just bump version to 28 to ensure it runs!
old_version = "int _version = 27;"
new_version = "int _version = 28;"
content = content.replace(old_version, new_version)

old_onupgrade = """      if (oldVersion < 27) {
        await db.execute('ALTER TABLE Sections ADD COLUMN cutting_deduction REAL NOT NULL DEFAULT 0.0;');
        await db.execute('ALTER TABLE Sections ADD COLUMN visible_width REAL NOT NULL DEFAULT 0.0;');
        await db.execute('ALTER TABLE Sections ADD COLUMN sash_overlap REAL NOT NULL DEFAULT 0.0;');
      }"""

new_onupgrade = """      if (oldVersion < 27) {
        await db.execute('ALTER TABLE Sections ADD COLUMN cutting_deduction REAL NOT NULL DEFAULT 0.0;');
        await db.execute('ALTER TABLE Sections ADD COLUMN visible_width REAL NOT NULL DEFAULT 0.0;');
        await db.execute('ALTER TABLE Sections ADD COLUMN sash_overlap REAL NOT NULL DEFAULT 0.0;');
      }
      if (oldVersion < 28) {
        await db.execute('ALTER TABLE Sections ADD COLUMN linked_renfort_id INTEGER;');
        await db.execute('ALTER TABLE Sections ADD COLUMN renfort_deduction REAL NOT NULL DEFAULT 140.0;');
      }"""

content = content.replace(old_onupgrade, new_onupgrade)

with open(file_path, "w", encoding="utf-8") as f:
    f.write(content)

print("sql_database.dart fixed.")
