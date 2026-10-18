import 'package:database_data/services/system_publication_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  test('keys identify profiles by code, or by name without one', () {
    expect(SystemPublicationService.modeKey('mixed'), 'mode:mixed');
    expect(
      SystemPublicationService.profileKey(code: ' TPR ', name: 'Tpr 77'),
      'profile:TPR',
    );
    expect(
      SystemPublicationService.profileKey(code: '', name: ' Batmo PVC '),
      'profile:batmo pvc',
    );
  });

  test('a hidden profile and its series are switched off', () async {
    sqfliteFfiInit();
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    addTearDown(db.close);
    await db.execute(
      'CREATE TABLE Profile (id INTEGER PRIMARY KEY, code TEXT, name TEXT, '
      'is_active INTEGER)',
    );
    await db.execute(
      'CREATE TABLE Series (id INTEGER PRIMARY KEY, profile_id INTEGER, '
      'name TEXT, is_active INTEGER)',
    );
    await db.insert('Profile', {
      'id': 1,
      'code': 'TPR',
      'name': 'TPR',
      'is_active': 1,
    });
    await db.insert('Profile', {
      'id': 2,
      'code': '',
      'name': 'Batmo',
      'is_active': 1,
    });
    await db.insert('Profile', {
      'id': 3,
      'code': 'ALU40',
      'name': 'Alu 40',
      'is_active': 1,
    });
    for (final (id, profile) in const [(10, 1), (11, 1), (20, 2), (30, 3)]) {
      await db.insert('Series', {
        'id': id,
        'profile_id': profile,
        'name': 'S$id',
        'is_active': 1,
      });
    }

    final changed = await SystemPublicationService.applyHiddenProfiles(db, {
      'profile:TPR',
      'profile:batmo',
      'mode:mixed',
    });

    expect(changed, 2);
    Future<Map<int, int>> active(String table) async => {
      for (final row in await db.query(table))
        row['id'] as int: row['is_active'] as int,
    };
    expect(await active('Profile'), {1: 0, 2: 0, 3: 1});
    expect(await active('Series'), {10: 0, 11: 0, 20: 0, 30: 1});
  });
}
