import re

file_path = "lib/sql_database.dart"
with open(file_path, "r", encoding="utf-8") as f:
    content = f.read()

# Modify readColors to delete 'رمادي داكن'
target = "var result = await myDb!.query('Colors');"
replacement = """await myDb!.delete('Colors', where: "name = ?", whereArgs: ['رمادي داكن']);
    var result = await myDb.query('Colors');"""

if replacement not in content:
    content = content.replace(target, replacement, 1)

with open(file_path, "w", encoding="utf-8") as f:
    f.write(content)

print("sql_database.dart updated to delete 'رمادي داكن'")
