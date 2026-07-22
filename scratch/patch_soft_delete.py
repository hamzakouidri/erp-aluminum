import re

with open('lib/sql_database.dart', 'r', encoding='utf-8') as f:
    code = f.read()

# 1. readProfile
code = re.sub(r"(readProfile\(\).*?rawQuery\('SELECT \* FROM Profile)('\);)", r"\1 WHERE is_active = 1\2", code, flags=re.DOTALL)

# 2. deleteProfile
code = re.sub(r"(deleteProfile\(int id\).*?await myDb!.)rawDelete\('DELETE FROM Profile WHERE id = \?', \[id\]\);", r"\1update('Profile', {'is_active': 0}, where: 'id = ?', whereArgs: [id]);", code, flags=re.DOTALL)

# 3. readSeriesByProfile
code = re.sub(r"(readSeriesByProfile\(int profileId\).*?where: 'profile_id = \?)(',)", r"\1 AND is_active = 1\2", code, flags=re.DOTALL)

# 4. deleteSeries
code = re.sub(r"(deleteSeries\(int id\).*?await myDb!.)delete\('Series', where: 'id = \?', whereArgs: \[id\]\);", r"\1update('Series', {'is_active': 0}, where: 'id = ?', whereArgs: [id]);", code, flags=re.DOTALL)

# 5. readSectionsBySeries
code = re.sub(r"(readSectionsBySeries\(int seriesId\).*?where: 'series_id = \?)(',)", r"\1 AND is_active = 1\2", code, flags=re.DOTALL)

# 6. searchSectionsWithProfile
code = re.sub(r"(JOIN Profile p ON ser.profile_id = p.id\s+WHERE )(LOWER\(s.name\))", r"\1s.is_active = 1 AND ser.is_active = 1 AND p.is_active = 1 AND (\2", code, flags=re.DOTALL)
code = re.sub(r"(LIKE \? OR LOWER\(p.name\) LIKE \?)(\s+''')", r"\1)\2", code, flags=re.DOTALL)

# 7. deleteSection
code = re.sub(r"(deleteSection\(int id\).*?await myDb!.)delete\('Sections', where: 'id = \?', whereArgs: \[id\]\);", r"\1update('Sections', {'is_active': 0}, where: 'id = ?', whereArgs: [id]);", code, flags=re.DOTALL)

# 8. readColors
code = re.sub(r"(readColors\(\).*?await myDb!\.query\('Colors)('\);)", r"\1', where: 'is_active = 1\2", code, flags=re.DOTALL)
code = re.sub(r"(result = await myDb\.query\('Colors)('\);)", r"\1', where: 'is_active = 1\2", code, flags=re.DOTALL)

# 9. deleteColor
code = re.sub(r"(deleteColor\(int id\).*?await myDb!.)delete\('Colors', where: 'id = \?', whereArgs: \[id\]\);", r"\1update('Colors', {'is_active': 0}, where: 'id = ?', whereArgs: [id]);", code, flags=re.DOTALL)

# 10. getColorsForProfile
code = re.sub(r"(WHERE pc.profile_id = \?)(\s+GROUP BY c.id)", r"\1 AND c.is_active = 1\2", code, flags=re.DOTALL)

# 11. readAccessories
code = re.sub(r"(readAccessories\(\).*?await myDb!\.query\('Accessories)('\);)", r"\1', where: 'is_active = 1\2", code, flags=re.DOTALL)

# 12. deleteAccessory
code = re.sub(r"(deleteAccessory\(int id\).*?await myDb!.)delete\(\s*'Accessories',\s*where: 'id = \?',\s*whereArgs: \[id\],\s*\);", r"\1update('Accessories', {'is_active': 0}, where: 'id = ?', whereArgs: [id]);", code, flags=re.DOTALL)

# 13. readGlass
code = re.sub(r"(readGlass\(\).*?await myDb!\.query\('Glass)('\);)", r"\1', where: 'is_active = 1\2", code, flags=re.DOTALL)

# 14. deleteGlass
code = re.sub(r"(deleteGlass\(int id\).*?await myDb!.)delete\('Glass', where: 'id = \?', whereArgs: \[id\]\);", r"\1update('Glass', {'is_active': 0}, where: 'id = ?', whereArgs: [id]);", code, flags=re.DOTALL)

# 15. readShutterComponents
code = re.sub(r"(readShutterComponents\(\).*?await myDb!\.query\('ShutterComponents)('\);)", r"\1', where: 'is_active = 1\2", code, flags=re.DOTALL)

# 16. deleteShutterComponent
code = re.sub(r"(deleteShutterComponent\(int id\).*?await myDb!.)delete\(\s*'ShutterComponents',\s*where: 'id = \?',\s*whereArgs: \[id\],\s*\);", r"\1update('ShutterComponents', {'is_active': 0}, where: 'id = ?', whereArgs: [id]);", code, flags=re.DOTALL)

with open('lib/sql_database.dart', 'w', encoding='utf-8') as f:
    f.write(code)

print('Done applying sql_database changes.')
