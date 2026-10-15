import 'package:database_data/sql_database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _SharingDatabase extends SqlDatabase {
  _SharingDatabase(this.connection);

  final Database connection;

  @override
  Future<Database?> get db async => connection;
}

void main() {
  test(
    'a shared profile is visible only in its explicit target series',
    () async {
      sqfliteFfiInit();
      final connection = await databaseFactoryFfi.openDatabase(
        inMemoryDatabasePath,
      );
      addTearDown(connection.close);
      await connection.execute('''
      CREATE TABLE Profile (
        id INTEGER PRIMARY KEY,
        name TEXT,
        is_active INTEGER
      )
    ''');
      await connection.execute('''
      CREATE TABLE Series (
        id INTEGER PRIMARY KEY,
        profile_id INTEGER,
        name TEXT,
        is_active INTEGER
      )
    ''');
      await connection.execute('''
      CREATE TABLE Sections (
        id INTEGER PRIMARY KEY,
        series_id INTEGER,
        code TEXT,
        name TEXT,
        type TEXT,
        visible_width REAL DEFAULT 0,
        thickness REAL DEFAULT 0,
        is_active INTEGER
      )
    ''');
      await connection.insert('Profile', {
        'id': 1,
        'name': 'Aluminium',
        'is_active': 1,
      });
      for (final series in const [
        {'id': 77000, 'name': 'TPR 77000'},
        {'id': 40000, 'name': 'TPR 40000'},
        {'id': 90, 'name': 'BS90'},
      ]) {
        await connection.insert('Series', {
          ...series,
          'profile_id': 1,
          'is_active': 1,
        });
      }
      await connection.insert('Sections', {
        'id': 77,
        'series_id': 77000,
        'code': 'TPR77-F',
        'name': 'TPR 77000 Frame',
        'type': 'frame',
        'is_active': 1,
      });
      await connection.insert('Sections', {
        'id': 40,
        'series_id': 40000,
        'code': 'TPR40-F',
        'name': 'TPR 40000 Frame',
        'type': 'frame',
        'is_active': 1,
      });

      final database = _SharingDatabase(connection);
      await database.readAvailableSectionsBySeries(40000);
      await connection.insert('SectionSharingRules', {
        'source_section_id': 77,
        'target_scope': 'profile',
        'target_id': 1,
        'role_key': 'frame',
        'usage_scope': 'global',
        'is_active': 1,
      });

      expect(
        (await database.readAvailableSectionsBySeries(
          40000,
        )).map((row) => row['id']),
        [40],
      );
      expect(await database.readAvailableSectionsBySeries(90), isEmpty);

      await connection.insert('SectionSharingRules', {
        'source_section_id': 77,
        'target_scope': 'series',
        'target_id': 40000,
        'role_key': 'frame',
        'usage_scope': 'global',
        'is_active': 1,
      });

      expect(
        (await database.readAvailableSectionsBySeries(
          40000,
        )).map((row) => row['id']),
        [40, 77],
      );
      expect(await database.readAvailableSectionsBySeries(90), isEmpty);

      await database.getSeriesDesignRoles(40000);
      await connection.insert('SeriesDesignRoles', {
        'series_id': 40000,
        'role_key': 'frame',
        'section_id': 77,
      });
      await connection.insert('SeriesDesignRoles', {
        'series_id': 90,
        'role_key': 'frame',
        'section_id': 77,
      });

      expect(
        (await database.getSeriesDesignRoles(
          40000,
        )).map((row) => row['section_id']),
        [77],
      );
      expect(await database.getSeriesDesignRoles(90), isEmpty);
    },
  );

  test('profile-wide sharing can no longer be saved', () async {
    sqfliteFfiInit();
    final connection = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
    );
    addTearDown(connection.close);
    final database = _SharingDatabase(connection);

    expect(
      () => database.saveSectionSharingRule(
        sourceSectionId: 77,
        targetScope: 'profile',
        targetId: 1,
        roleKey: 'frame',
      ),
      throwsArgumentError,
    );
  });
}
