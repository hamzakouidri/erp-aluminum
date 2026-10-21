part of '../sql_database.dart';

/// Remote deletions that would remove many local clients, orders or treasury
/// rows. They are kept aside until the manager applies them or keeps the
/// local rows.
class BusinessDataLossConflict {
  const BusinessDataLossConflict({
    required this.detectedAt,
    required this.localCounts,
    required this.lostRows,
    required this.heldDeletions,
  });

  final DateTime detectedAt;
  final Map<String, int> localCounts;

  /// Local rows of each guarded table that the held deletions would remove.
  final Map<String, int> lostRows;

  /// Every held deletion, guarded tables or not.
  final int heldDeletions;
}

/// Local-only protection of the workshop business data against a download
/// that deletes it: a copy of the database file before every full download,
/// and the guard that holds back large remote deletions. The pending table
/// starts with `_sync_`, so it is never exported, uploaded or given tombstone
/// triggers.
extension SqlDatabaseBusinessDataGuard on SqlDatabase {
  static const String pendingTable = '_sync_business_loss_pending';
  static const String fileBackupFolder = 'sync_backups';
  static const int fileBackupLimit = 5;

  /// SharedPreferences key of the Supabase workshop whose rows the local
  /// workshop tables hold. Removed when those tables are cleared.
  static const String localDataOwnerKey = 'supabase_local_data_workshop_uuid';

  /// Tables whose loss the workshop cannot rebuild from anywhere else.
  static const List<String> guardedTables = ['Client', 'Commandes', 'Treasury'];

  /// Bumped whenever remote deletions are held back, so the app can ask the
  /// manager.
  static final ValueNotifier<int> conflictSignal = ValueNotifier<int>(0);

  /// One or two deletions always pass; losing more than 10 rows or more than
  /// a tenth of the table needs the manager.
  static bool losesTooMany({required int localRows, required int lostRows}) {
    if (lostRows < 3) return false;
    return lostRows > 10 || lostRows * 10 > localRows;
  }

  Future<void> _ensureBusinessDataGuardSchema(DatabaseExecutor executor) async {
    await executor.execute('''
      CREATE TABLE IF NOT EXISTS $pendingTable (
        table_name TEXT NOT NULL,
        row_id TEXT NOT NULL,
        deleted_at TEXT NOT NULL,
        detected_at TEXT NOT NULL,
        PRIMARY KEY (table_name, row_id)
      )
    ''');
  }

  /// Copies the database file next to it, in [fileBackupFolder], and keeps
  /// the newest [fileBackupLimit] copies. Returns the copy's path, or null
  /// when no copy could be written.
  Future<String?> backupDatabaseFile({required String reason}) async {
    if (kIsWeb) return null;
    final myDb = await db;
    if (myDb == null) return null;
    final dbPath = await getDatabaseFilePath();
    final folder = Directory(join(dirname(dbPath), fileBackupFolder));
    try {
      if (!await folder.exists()) await folder.create(recursive: true);
    } catch (error) {
      debugPrint('Database copy folder not created: $error');
      return null;
    }
    final stamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    final safeReason = reason.replaceAll(RegExp(r'[^A-Za-z0-9_]'), '_');
    final target = join(folder.path, 'test_${safeReason}_$stamp.db');
    var written = false;
    try {
      // A consistent copy even while the WAL holds recent writes.
      await myDb.execute("VACUUM INTO '${target.replaceAll("'", "''")}'");
      written = await File(target).exists();
    } catch (error) {
      debugPrint('VACUUM INTO copy failed, copying the file: $error');
    }
    if (!written) {
      try {
        await myDb.rawQuery('PRAGMA wal_checkpoint(TRUNCATE)');
      } catch (_) {}
      try {
        await File(dbPath).copy(target);
        written = true;
      } catch (error) {
        debugPrint('Database copy failed: $error');
        return null;
      }
    }
    try {
      final copies =
          folder
              .listSync()
              .whereType<File>()
              .where((file) => basename(file.path).startsWith('test_'))
              .toList()
            ..sort(
              (a, b) => b.statSync().modified.compareTo(a.statSync().modified),
            );
      for (final old in copies.skip(fileBackupLimit)) {
        await old.delete();
      }
    } catch (error) {
      debugPrint('Old database copies not pruned: $error');
    }
    return target;
  }

  static String _guardKey(String table, String rowId) => '$table\u0000$rowId';

  /// Local ids of [table] among [rowIds].
  Future<int> _countLocalRows(
    DatabaseExecutor executor,
    String table,
    Iterable<String> rowIds,
  ) async {
    final ids = rowIds.toList(growable: false);
    if (ids.isEmpty) return 0;
    var found = 0;
    for (var start = 0; start < ids.length; start += 400) {
      final chunk = ids.sublist(start, min(start + 400, ids.length));
      final marks = List.filled(chunk.length, '?').join(',');
      final rows = await executor.rawQuery(
        'SELECT COUNT(*) AS n FROM $table WHERE CAST(id AS TEXT) IN ($marks)',
        chunk,
      );
      found += (rows.first['n'] as num?)?.toInt() ?? 0;
    }
    return found;
  }

  Future<int> _countTable(DatabaseExecutor executor, String table) async {
    final rows = await executor.rawQuery('SELECT COUNT(*) AS n FROM $table');
    return (rows.first['n'] as num?)?.toInt() ?? 0;
  }

  /// Local rows of each guarded table that [deletions] would remove.
  Future<Map<String, int>> _lostBusinessRows(
    DatabaseExecutor executor,
    Iterable<Map<String, dynamic>> deletions,
  ) async {
    final idsByTable = <String, Set<String>>{};
    for (final deletion in deletions) {
      final table = deletion['table_name']?.toString() ?? '';
      final rowId = deletion['row_id']?.toString() ?? '';
      if (!guardedTables.contains(table) || rowId.isEmpty) continue;
      idsByTable.putIfAbsent(table, () => <String>{}).add(rowId);
    }
    final lost = <String, int>{};
    for (final table in guardedTables) {
      final ids = idsByTable[table];
      if (ids == null) continue;
      if (!await _configTableExists(executor, table)) continue;
      lost[table] = await _countLocalRows(executor, table, ids);
    }
    return lost;
  }

  Future<List<Map<String, dynamic>>> _readHeldDeletions(
    DatabaseExecutor executor,
  ) async {
    final rows = await executor.query(
      pendingTable,
      columns: ['table_name', 'row_id', 'deleted_at'],
    );
    return [for (final row in rows) Map<String, dynamic>.from(row)];
  }

  /// Returns the deletions of a download that may be applied now. When they
  /// would remove too many local clients, orders or treasury rows (counted
  /// together with the deletions already waiting), all of them are stored
  /// for the manager and none is returned.
  Future<List<Map<String, dynamic>>> holdBackLargeBusinessDeletions(
    List<Map<String, dynamic>> deletions,
  ) async {
    if (deletions.isEmpty) return deletions;
    final myDb = await db;
    if (myDb == null) return deletions;
    await _ensureBusinessDataGuardSchema(myDb);
    final held = await _readHeldDeletions(myDb);
    final combined = <String, Map<String, dynamic>>{
      for (final row in [...held, ...deletions])
        _guardKey(
          row['table_name']?.toString() ?? '',
          row['row_id']?.toString() ?? '',
        ): row,
    };
    final lost = await _lostBusinessRows(myDb, combined.values);
    var tooMany = false;
    for (final entry in lost.entries) {
      final localRows = await _countTable(myDb, entry.key);
      if (losesTooMany(localRows: localRows, lostRows: entry.value)) {
        tooMany = true;
        break;
      }
    }
    if (!tooMany) return deletions;

    final detectedAt = DateTime.now().toUtc().toIso8601String();
    await myDb.transaction((txn) async {
      for (final deletion in deletions) {
        final table = deletion['table_name']?.toString() ?? '';
        final rowId = deletion['row_id']?.toString() ?? '';
        final deletedAt = deletion['deleted_at']?.toString() ?? '';
        if (table.isEmpty || rowId.isEmpty || deletedAt.isEmpty) continue;
        await txn.insert(pendingTable, {
          'table_name': table,
          'row_id': rowId,
          'deleted_at': deletedAt,
          'detected_at': detectedAt,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
    conflictSignal.value++;
    return const [];
  }

  Future<BusinessDataLossConflict?> readPendingBusinessDataLoss() async {
    final myDb = await db;
    if (myDb == null) return null;
    await _ensureBusinessDataGuardSchema(myDb);
    final held = await _readHeldDeletions(myDb);
    if (held.isEmpty) return null;
    final detected = await myDb.rawQuery(
      'SELECT MIN(detected_at) AS at FROM $pendingTable',
    );
    final localCounts = <String, int>{};
    for (final table in guardedTables) {
      if (!await _configTableExists(myDb, table)) continue;
      localCounts[table] = await _countTable(myDb, table);
    }
    return BusinessDataLossConflict(
      detectedAt:
          DateTime.tryParse(
            detected.first['at']?.toString() ?? '',
          )?.toLocal() ??
          DateTime.now(),
      localCounts: localCounts,
      lostRows: await _lostBusinessRows(myDb, held),
      heldDeletions: held.length,
    );
  }

  /// The manager accepted the remote deletions: they are applied like any
  /// downloaded deletion (no new tombstone is created for them).
  Future<void> applyPendingBusinessDataLoss() async {
    final myDb = await db;
    if (myDb == null) return;
    await _ensureBusinessDataGuardSchema(myDb);
    final held = await _readHeldDeletions(myDb);
    if (held.isNotEmpty) {
      await importWorkshopData({'SyncTombstones': held});
    }
    await myDb.delete(pendingTable);
  }

  /// The manager kept the local rows. Returns the held rows as
  /// `table\x1frow_id` keys so the caller uploads them again over the remote
  /// deletions.
  Future<Set<String>> discardPendingBusinessDataLoss() async {
    final myDb = await db;
    if (myDb == null) return const {};
    await _ensureBusinessDataGuardSchema(myDb);
    final held = await _readHeldDeletions(myDb);
    await myDb.delete(pendingTable);
    return {
      for (final row in held)
        '${row['table_name']}\x1f${row['row_id']}',
    };
  }
}
