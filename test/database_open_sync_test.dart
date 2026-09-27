import 'dart:io';

import 'package:database_data/sql_database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _TemporaryPaths extends PathProviderPlatform {
  _TemporaryPaths(this.path);
  final String path;

  @override
  Future<String?> getApplicationSupportPath() async => path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('desktop database opens and can write incoming catalog data', () async {
    final directory = await Directory.systemTemp.createTemp('erp_sync_open_');
    final originalPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _TemporaryPaths(directory.path);
    SharedPreferences.setMockInitialValues({});
    addTearDown(() async {
      PathProviderPlatform.instance = originalPaths;
      await directory.delete(recursive: true);
    });

    final connection = await SqlDatabase().initDb();
    addTearDown(connection.close);
    expect(await connection.rawQuery('PRAGMA user_version'), [
      {'user_version': 67},
    ]);
    expect(await connection.rawQuery('PRAGMA quick_check'), [
      {'quick_check': 'ok'},
    ]);
    await connection.transaction((txn) async {
      await txn.insert('Colors', {
        'id': 987654321,
        'name': 'Sync regression color',
        'hex_code': '#123456',
      });
    });
    final rows = await connection.query(
      'Colors',
      where: 'id = ?',
      whereArgs: [987654321],
    );
    expect(rows.single['name'], 'Sync regression color');
  });
}
