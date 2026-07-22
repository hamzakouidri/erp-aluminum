import re

file_path = "lib/sql_database.dart"
with open(file_path, "r", encoding="utf-8") as f:
    content = f.read()

# Update DB version to 29
content = content.replace("int _version = 28;", "int _version = 29;")

# Update onUpgrade function
old_onupgrade = """      if (oldVersion < 28) {
        await db.execute('ALTER TABLE Sections ADD COLUMN linked_renfort_id INTEGER;');
        await db.execute('ALTER TABLE Sections ADD COLUMN renfort_deduction REAL NOT NULL DEFAULT 140.0;');
      }"""

new_onupgrade = """      if (oldVersion < 28) {
        await db.execute('ALTER TABLE Sections ADD COLUMN linked_renfort_id INTEGER;');
        await db.execute('ALTER TABLE Sections ADD COLUMN renfort_deduction REAL NOT NULL DEFAULT 140.0;');
      }
      if (oldVersion < 29) {
        // Add Dark Gray color if it doesn't exist
        var colorRes = await db.query('Colors', where: "name = 'رمادي داكن'");
        int darkGrayId;
        if (colorRes.isEmpty) {
          darkGrayId = await db.insert('Colors', {
            'name': 'رمادي داكن',
            'hex_code': '#424242',
            'type': 'Global'
          });
        } else {
          darkGrayId = colorRes.first['id'] as int;
        }
        
        // Link to all profiles
        var profiles = await db.query('Profile');
        for (var p in profiles) {
          int profileId = p['id'] as int;
          var link = await db.query('ProfileColors', where: 'profile_id = ? AND color_id = ?', whereArgs: [profileId, darkGrayId]);
          if (link.isEmpty) {
            await db.insert('ProfileColors', {
              'profile_id': profileId,
              'color_id': darkGrayId
            });
          }
        }
      }"""

content = content.replace(old_onupgrade, new_onupgrade)

with open(file_path, "w", encoding="utf-8") as f:
    f.write(content)

print("sql_database.dart updated for version 29.")
