import 'package:database_data/sql_database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _GuardDatabase extends SqlDatabase {
  _GuardDatabase(this.connection);

  final Database connection;

  @override
  Future<Database?> get db async => connection;
}

List<Map<String, dynamic>> _roles(Iterable<int> ids) => [
  for (final id in ids)
    {'id': id, 'series_id': 1, 'role_key': 'role_$id', 'section_id': id},
];

List<Map<String, dynamic>> _rules(Iterable<int> ids) => [
  for (final id in ids)
    {
      'id': id,
      'item_table': 'Accessories',
      'item_id': id,
      'series_id': 1,
      'role_key': 'role_$id',
    },
];

Future<int> _count(Database connection, String table) async {
  final rows = await connection.rawQuery('SELECT COUNT(*) AS n FROM $table');
  return (rows.first['n'] as num).toInt();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database connection;
  late _GuardDatabase db;

  setUp(() async {
    SharedPreferences.setMockInitialValues({'workshop_code': '9DAC0E'});
    sqfliteFfiInit();
    SqlDatabase.resetDb();
    connection = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await connection.execute(
      'CREATE TABLE SeriesDesignRoles (id INTEGER PRIMARY KEY, '
      'series_id INTEGER, role_key TEXT, section_id INTEGER)',
    );
    await connection.execute(
      'CREATE TABLE CatalogItemRules (id INTEGER PRIMARY KEY, '
      'item_table TEXT NOT NULL, item_id INTEGER NOT NULL, '
      'series_id INTEGER, role_key TEXT NOT NULL)',
    );
    for (final row in _roles(List.generate(40, (i) => i + 1))) {
      await connection.insert('SeriesDesignRoles', row);
    }
    for (final row in _rules(List.generate(60, (i) => i + 1))) {
      await connection.insert('CatalogItemRules', row);
    }
    db = _GuardDatabase(connection);
  });

  tearDown(() => connection.close());

  group('shrink threshold', () {
    test('one deleted rule always passes', () {
      expect(
        SqlDatabaseCatalogConfigGuard.losesTooMany(localRows: 2, lostRows: 1),
        isFalse,
      );
    });

    test('more than 10 rows or a fifth of the table needs the manager', () {
      expect(
        SqlDatabaseCatalogConfigGuard.losesTooMany(
          localRows: 237,
          lostRows: 11,
        ),
        isTrue,
      );
      expect(
        SqlDatabaseCatalogConfigGuard.losesTooMany(
          localRows: 237,
          lostRows: 10,
        ),
        isFalse,
      );
      expect(
        SqlDatabaseCatalogConfigGuard.losesTooMany(localRows: 10, lostRows: 3),
        isTrue,
      );
      expect(
        SqlDatabaseCatalogConfigGuard.losesTooMany(localRows: 10, lostRows: 2),
        isFalse,
      );
    });
  });

  test('a remote copy that drops many rules is held back', () async {
    var signals = 0;
    void listener() => signals++;
    SqlDatabaseCatalogConfigGuard.conflictSignal.addListener(listener);
    addTearDown(
      () =>
          SqlDatabaseCatalogConfigGuard.conflictSignal.removeListener(listener),
    );

    final result = await db.importWorkshopCatalogConfiguration({
      'SeriesDesignRoles': _roles(List.generate(5, (i) => i + 1)),
      'CatalogItemRules': _rules(List.generate(60, (i) => i + 1)),
    });

    expect(result, CatalogConfigImportResult.conflict);
    expect(await _count(connection, 'SeriesDesignRoles'), 40);
    expect(await _count(connection, 'CatalogItemRules'), 60);
    expect(signals, 1);

    final conflict = await db.readPendingCatalogConfigConflict();
    expect(conflict, isNotNull);
    expect(conflict!.localCounts['SeriesDesignRoles'], 40);
    expect(conflict.remoteCounts['SeriesDesignRoles'], 5);
    expect(conflict.lostRows['SeriesDesignRoles'], 35);
    expect(conflict.lostRows['CatalogItemRules'], 0);
  });

  test('a copy with the same count but other rule ids is held back', () async {
    final result = await db.importWorkshopCatalogConfiguration({
      'SeriesDesignRoles': _roles(List.generate(40, (i) => i + 101)),
    });

    expect(result, CatalogConfigImportResult.conflict);
    expect(await _count(connection, 'SeriesDesignRoles'), 40);
    final ids = await connection.query('SeriesDesignRoles', columns: ['id']);
    expect(ids.map((row) => row['id']), contains(1));
  });

  test('a single deleted rule is applied and snapshotted', () async {
    final result = await db.importWorkshopCatalogConfiguration({
      'SeriesDesignRoles': _roles(List.generate(39, (i) => i + 1)),
    });

    expect(result, CatalogConfigImportResult.applied);
    expect(await _count(connection, 'SeriesDesignRoles'), 39);
    expect(await db.readPendingCatalogConfigConflict(), isNull);

    final snapshots = await db.readCatalogConfigSnapshots();
    expect(snapshots, hasLength(1));
    expect(snapshots.first.reason, 'remote_configuration');
    expect(snapshots.first.workshopCode, '9DAC0E');
    expect(snapshots.first.counts['SeriesDesignRoles'], 40);
    expect(snapshots.first.counts['CatalogItemRules'], 60);
  });

  test('the manager can apply the held-back copy', () async {
    await db.importWorkshopCatalogConfiguration({
      'SeriesDesignRoles': _roles([1, 2, 3]),
    });
    expect(await _count(connection, 'SeriesDesignRoles'), 40);

    await db.applyPendingCatalogConfigConflict();

    expect(await _count(connection, 'SeriesDesignRoles'), 3);
    expect(await db.readPendingCatalogConfigConflict(), isNull);
    final snapshots = await db.readCatalogConfigSnapshots();
    expect(snapshots.first.counts['SeriesDesignRoles'], 40);
  });

  test('keeping local rules drops the held-back copy', () async {
    await db.importWorkshopCatalogConfiguration({
      'CatalogItemRules': _rules([1]),
    });
    await db.discardPendingCatalogConfigConflict();

    expect(await db.readPendingCatalogConfigConflict(), isNull);
    expect(await _count(connection, 'CatalogItemRules'), 60);
  });

  group('snapshots', () {
    test('identical or empty rules are not saved twice', () async {
      expect(await db.saveCatalogConfigSnapshot(reason: 'manual'), isNotNull);
      expect(await db.saveCatalogConfigSnapshot(reason: 'manual'), isNull);

      await connection.delete('SeriesDesignRoles');
      await connection.delete('CatalogItemRules');
      expect(await db.saveCatalogConfigSnapshot(reason: 'manual'), isNull);
      expect(await db.readCatalogConfigSnapshots(), hasLength(1));
    });

    test('only the last five are kept, newest first', () async {
      for (var i = 0; i < 7; i++) {
        await connection.insert('CatalogItemRules', _rules([1000 + i]).first);
        await db.saveCatalogConfigSnapshot(reason: 'manual');
      }

      final snapshots = await db.readCatalogConfigSnapshots();
      expect(snapshots, hasLength(SqlDatabaseCatalogConfigGuard.snapshotLimit));
      expect(snapshots.first.counts['CatalogItemRules'], 67);
      expect(snapshots.last.counts['CatalogItemRules'], 63);
    });

    test('a restore writes every table back in one go', () async {
      await connection.execute(
        'CREATE TABLE SyncTombstones (table_name TEXT NOT NULL, '
        'row_id TEXT NOT NULL, deleted_at TEXT NOT NULL, '
        'PRIMARY KEY (table_name, row_id))',
      );
      final id = await db.saveCatalogConfigSnapshot(reason: 'manual');

      // The incident: both tables emptied, with deletion markers left behind.
      await connection.delete('SeriesDesignRoles');
      await connection.delete('CatalogItemRules', where: 'id > 10');
      await connection.insert('SyncTombstones', {
        'table_name': 'SeriesDesignRoles',
        'row_id': '7',
        'deleted_at': '2026-10-20T07:00:00Z',
      });

      await db.restoreCatalogConfigSnapshot(id!);

      expect(await _count(connection, 'SeriesDesignRoles'), 40);
      expect(await _count(connection, 'CatalogItemRules'), 60);
      expect(await _count(connection, 'SyncTombstones'), 0);

      // The damaged state was saved before the restore, so it can be undone.
      final snapshots = await db.readCatalogConfigSnapshots();
      expect(snapshots.first.reason, 'before_restore');
      expect(snapshots.first.counts['CatalogItemRules'], 10);
    });

    test('a restore clears a held-back remote copy', () async {
      final id = await db.saveCatalogConfigSnapshot(reason: 'manual');
      await db.importWorkshopCatalogConfiguration({
        'SeriesDesignRoles': _roles([1]),
      });
      expect(await db.readPendingCatalogConfigConflict(), isNotNull);

      await db.restoreCatalogConfigSnapshot(id!);

      expect(await db.readPendingCatalogConfigConflict(), isNull);
    });

    test('snapshot tables are never exported or uploaded', () {
      for (final table in [
        SqlDatabaseCatalogConfigGuard.snapshotsTable,
        SqlDatabaseCatalogConfigGuard.pendingTable,
      ]) {
        expect(table, startsWith('_sync_'));
        expect(SqlDatabase.workshopTables, isNot(contains(table)));
        expect(
          SqlDatabase.workshopCatalogConfigurationTables,
          isNot(contains(table)),
        );
      }
    });
  });
}
