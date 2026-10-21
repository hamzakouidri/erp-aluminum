import 'package:database_data/services/supabase_workshop_sync_service.dart';
import 'package:database_data/sql_database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _ReviveDatabase extends SqlDatabase {
  _ReviveDatabase(this.connection);

  final Database connection;

  @override
  Future<Database?> get db async => connection;
}

Map<String, dynamic> _client(int id) => {
  'id': id,
  'firstname': 'Client $id',
  'lastname': 'Test',
  'created_at': '2026-10-01T10:00:00.000Z',
  'updated_at': '2026-10-01T10:00:00.000Z',
};

bool _supersedes(String live, String deleted) =>
    SupabaseWorkshopSyncService.liveRowSupersedesDeletion(
      liveUpdatedAt: live,
      deletedAt: deleted,
    );

Future<List<int>> _clientIds(Database connection) async {
  final rows = await connection.query('Client', columns: ['id'], orderBy: 'id');
  return [for (final row in rows) (row['id'] as num).toInt()];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('rows Supabase holds as deleted', () {
    test('only local rows deleted on the server are revived', () {
      final keys = SupabaseWorkshopSyncService.localRowsDeletedOnServer(
        localKeys: ['Client\x1f1', 'Client\x1f2', 'Commandes\x1f7'],
        remoteDeleted: {'Client\x1f2', 'Commandes\x1f7', 'Commandes\x1f9'},
      );
      // Commandes 9 is not on this device: it stays deleted.
      expect(keys, {'Client\x1f2', 'Commandes\x1f7'});
    });

    test('a live row replaces only an older deletion', () {
      expect(
        _supersedes('2026-10-21T13:00:00.000+00:00', '2026-10-20T06:07:07Z'),
        isTrue,
      );
      // A local deletion made after the remote edit stays.
      expect(
        _supersedes('2026-10-20T06:00:00Z', '2026-10-20T06:07:07Z'),
        isFalse,
      );
      expect(_supersedes('2026-10-20T06:07:07Z', '2026-10-20T06:07:07Z'), isFalse);
      expect(_supersedes('', '2026-10-20T06:07:07Z'), isFalse);
      expect(_supersedes('2026-10-21T13:00:00Z', 'not a date'), isFalse);
    });
  });

  group('download after a revival', () {
    late Database connection;
    late _ReviveDatabase db;

    setUp(() async {
      SharedPreferences.setMockInitialValues({'workshop_code': '9DAC0E'});
      sqfliteFfiInit();
      SqlDatabase.resetDb();
      connection = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      db = _ReviveDatabase(connection);
      await db.importWorkshopData({
        'Client': [_client(3)],
      });
      // This phone downloaded the 2026-10-20 deletions of clients 1 and 2.
      await db.importWorkshopData({
        'SyncTombstones': [
          {
            'table_name': 'Client',
            'row_id': '1',
            'deleted_at': '2026-10-20T06:07:07.786+00:00',
          },
          {
            'table_name': 'Client',
            'row_id': '2',
            'deleted_at': '2026-10-22T08:00:00.000Z',
          },
        ],
      });
    });

    tearDown(() => connection.close());

    test('an old local deletion hides a revived row without the fix', () async {
      await db.importWorkshopData({
        'Client': [_client(1)],
      });
      expect(await _clientIds(connection), [3]);
    });

    test('a row revived on the server comes back on this device', () async {
      final dropped = await db.dropDeletionsSupersededByLiveRows({
        'Client': {
          '1': '2026-10-21T13:27:33.000+00:00',
          '2': '2026-10-21T13:27:33.000+00:00',
        },
      }, supersedes: _supersedes);
      await db.importWorkshopData({
        'Client': [_client(1), _client(2)],
      });

      expect(dropped, 1);
      // Client 2 was deleted here after the server copy: it stays deleted.
      expect(await _clientIds(connection), [1, 3]);
      final kept = await connection.query('SyncTombstones');
      expect(kept.map((row) => row['row_id']), ['2']);
    });
  });
}
