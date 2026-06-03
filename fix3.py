import sys

with open('lib/sql_database.dart', 'r', encoding='utf-8') as f:
    content = f.read()

methods = '''
  //////////////////////////////////// Employees //////////////////////////////////////
  Future<List<Map<String, dynamic>>> readEmployees() async {
    Database? myDb = await db;
    return await myDb!.query('Employees');
  }

  Future<int> insertEmployee(String uid, String email, String name, String permissionsJson) async {
    Database? myDb = await db;
    var res = await myDb!.insert('Employees', {
      'uid': uid,
      'email': email,
      'name': name,
      'permissions_json': permissionsJson
    });
    CloudSyncService().notifyChange();
    return res;
  }

  Future<int> updateEmployeePermissions(String uid, String permissionsJson) async {
    Database? myDb = await db;
    var res = await myDb!.update('Employees', {
      'permissions_json': permissionsJson
    }, where: 'uid = ?', whereArgs: [uid]);
    CloudSyncService().notifyChange();
    return res;
  }

  Future<int> deleteEmployee(String uid) async {
    Database? myDb = await db;
    var res = await myDb!.delete('Employees', where: 'uid = ?', whereArgs: [uid]);
    CloudSyncService().notifyChange();
    return res;
  }
'''

content = content.replace('  Future<Map<String, dynamic>> exportAllData() async {', methods + '\n  Future<Map<String, dynamic>> exportAllData() async {')

with open('lib/sql_database.dart', 'w', encoding='utf-8') as f:
    f.write(content)
