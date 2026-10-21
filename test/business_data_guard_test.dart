import 'package:database_data/services/supabase_workshop_sync_service.dart';
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

Map<String, dynamic> _client(int id, {String name = 'Client'}) => {
  'id': id,
  'firstname': '$name $id',
  'lastname': 'Test',
  'created_at': '2026-10-01T10:00:00.000Z',
  'updated_at': '2026-10-01T10:00:00.000Z',
};

Map<String, dynamic> _tombstone(String table, int id) => {
  'table_name': table,
  'row_id': '$id',
  'deleted_at': '2026-10-20T20:29:00.000Z',
};

Future<int> _count(Database connection, String table, [String? where]) async {
  final rows = await connection.rawQuery(
    'SELECT COUNT(*) AS n FROM $table${where == null ? '' : ' WHERE $where'}',
  );
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
    db = _GuardDatabase(connection);
    // Creates the workshop tables and the sync triggers.
    await db.importWorkshopData({
      'Client': [for (var id = 1; id <= 20; id++) _client(id)],
    });
    await db.hasPendingCloudChanges();
    await connection.delete('_sync_change_log');
  });

  tearDown(() => connection.close());

  group('loss threshold', () {
    test('one or two deletions always pass', () {
      expect(
        SqlDatabaseBusinessDataGuard.losesTooMany(localRows: 2, lostRows: 2),
        isFalse,
      );
    });

    test('more than 10 rows or a tenth of the table needs the manager', () {
      expect(
        SqlDatabaseBusinessDataGuard.losesTooMany(
          localRows: 500,
          lostRows: 11,
        ),
        isTrue,
      );
      expect(
        SqlDatabaseBusinessDataGuard.losesTooMany(localRows: 52, lostRows: 6),
        isTrue,
      );
      expect(
        SqlDatabaseBusinessDataGuard.losesTooMany(localRows: 52, lostRows: 5),
        isFalse,
      );
    });
  });

  group('full download plan', () {
    test('rows of this workshop or of an unknown owner are uploaded', () {
      expect(
        SupabaseWorkshopSyncService.planFullDownload(
          localDataOwner: '',
          workshopUuid: 'w1',
        ),
        FullDownloadPlan.uploadLocalThenMerge,
      );
      expect(
        SupabaseWorkshopSyncService.planFullDownload(
          localDataOwner: 'w1',
          workshopUuid: 'w1',
        ),
        FullDownloadPlan.uploadLocalThenMerge,
      );
    });

    test('rows of another workshop are cleared, never uploaded', () {
      expect(
        SupabaseWorkshopSyncService.planFullDownload(
          localDataOwner: 'w0',
          workshopUuid: 'w1',
        ),
        FullDownloadPlan.clearOtherWorkshopThenMerge,
      );
    });

    test('a row deleted on the server is not uploaded again', () {
      bool upload(String key, {Set<String> revive = const {}}) =>
          SupabaseWorkshopSyncService.shouldUploadMissingRow(
            key: key,
            remoteLive: {'Client\x1f1'},
            remoteDeleted: {'Client\x1f2'},
            reviveRows: revive,
          );
      expect(upload('Client\x1f1'), isFalse);
      expect(upload('Client\x1f2'), isFalse);
      expect(upload('Client\x1f2', revive: {'Client\x1f2'}), isTrue);
      expect(upload('Client\x1f3'), isTrue);
    });
  });

  group('merge download', () {
    test('local rows missing from the server survive', () async {
      // The server holds only the two rows this device uploaded.
      await db.importWorkshopData({
        'Client': [_client(1, name: 'Server'), _client(2, name: 'Server')],
        'Commandes': <Map<String, dynamic>>[],
      });

      expect(await _count(connection, 'Client'), 20);
      expect(await _count(connection, 'SyncTombstones'), 0);
    });

    test('a pending local row and its change survive', () async {
      await connection.insert('Client', _client(99, name: 'Local'));
      expect(await db.hasPendingCloudChanges(), isTrue);

      await db.importWorkshopData({
        'Client': [_client(1, name: 'Server')],
      });

      expect(await _count(connection, 'Client', 'id = 99'), 1);
      expect(await db.hasPendingCloudChanges(), isTrue);
    });

    test('only a server deletion removes a row, without a new change', () async {
      await db.importWorkshopData({
        'Client': [_client(1, name: 'Server')],
        'SyncTombstones': [_tombstone('Client', 3)],
      });

      expect(await _count(connection, 'Client'), 19);
      expect(await _count(connection, 'Client', 'id = 3'), 0);
      // The deletion came from the server: no deletion is queued for upload
      // and the only tombstone is the server's own.
      expect(
        await _count(connection, '_sync_change_log', "operation = 'delete'"),
        0,
      );
      final tombstones = await connection.query('SyncTombstones');
      expect(tombstones, hasLength(1));
      expect(tombstones.single['deleted_at'], '2026-10-20T20:29:00.000Z');
    });
  });

  group('large deletion guard', () {
    test('a few deletions are applied', () async {
      final allowed = await db.holdBackLargeBusinessDeletions([
        _tombstone('Client', 1),
        _tombstone('Client', 2),
      ]);

      expect(allowed, hasLength(2));
      expect(await db.readPendingBusinessDataLoss(), isNull);
    });

    test('deleting many clients waits for the manager with counts', () async {
      final allowed = await db.holdBackLargeBusinessDeletions([
        for (var id = 1; id <= 6; id++) _tombstone('Client', id),
        _tombstone('Commandes', 7),
      ]);

      expect(allowed, isEmpty);
      final conflict = await db.readPendingBusinessDataLoss();
      expect(conflict, isNotNull);
      expect(conflict!.localCounts['Client'], 20);
      expect(conflict.lostRows['Client'], 6);
      expect(conflict.heldDeletions, 7);
      expect(await _count(connection, 'Client'), 20);
    });

    test('deletions of rows this device lacks do not count', () async {
      final allowed = await db.holdBackLargeBusinessDeletions([
        for (var id = 100; id < 140; id++) _tombstone('Client', id),
      ]);

      expect(allowed, hasLength(40));
    });

    test('the manager applies the held deletions', () async {
      await db.holdBackLargeBusinessDeletions([
        for (var id = 1; id <= 6; id++) _tombstone('Client', id),
      ]);

      await db.applyPendingBusinessDataLoss();

      expect(await _count(connection, 'Client'), 14);
      expect(await db.readPendingBusinessDataLoss(), isNull);
      expect(
        await _count(connection, '_sync_change_log', "operation = 'delete'"),
        0,
      );
    });

    test('the manager keeps the local rows', () async {
      await db.holdBackLargeBusinessDeletions([
        for (var id = 1; id <= 6; id++) _tombstone('Client', id),
      ]);

      final keep = await db.discardPendingBusinessDataLoss();

      expect(keep, contains('Client\x1f1'));
      expect(keep, hasLength(6));
      expect(await _count(connection, 'Client'), 20);
      expect(await db.readPendingBusinessDataLoss(), isNull);
    });
  });
}
