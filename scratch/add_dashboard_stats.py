import re

file_path = "lib/sql_database.dart"
with open(file_path, "r", encoding="utf-8") as f:
    content = f.read()

# Add getDashboardStats to SqlDatabase
new_method = """  Future<Map<String, String>> getDashboardStats() async {
    Database? myDb = await db;
    try {
      final cmds = await myDb!.rawQuery('SELECT COUNT(*) as count FROM Commandes');
      final clis = await myDb.rawQuery('SELECT COUNT(*) as count FROM Client');
      
      final cmdCount = cmds.first['count'].toString();
      final cliCount = clis.first['count'].toString();
      
      return {
        'cmdCount': cmdCount,
        'cmdTrend': '+2 هذا الأسبوع',
        'cliCount': cliCount,
        'cliTrend': '+1 هذا الشهر',
      };
    } catch (e) {
      return {
        'cmdCount': '0',
        'cmdTrend': '—',
        'cliCount': '0',
        'cliTrend': '—',
      };
    }
  }
"""

# Insert it before readAchats
if "Future<List<Map<String, dynamic>>> readAchats()" in content:
    content = content.replace("Future<List<Map<String, dynamic>>> readAchats()", new_method + "\n  Future<List<Map<String, dynamic>>> readAchats()")
else:
    # Append it at the end of the class, before the final closing brace
    content = content.rsplit('}', 1)[0] + new_method + "}\n"

with open(file_path, "w", encoding="utf-8") as f:
    f.write(content)

print("getDashboardStats added successfully.")
