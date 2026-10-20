part of '../sql_database.dart';

/// One local copy of the workshop's rule tables, taken before a remote copy
/// or a workshop change could replace them.
class CatalogConfigSnapshot {
  const CatalogConfigSnapshot({
    required this.id,
    required this.createdAt,
    required this.reason,
    required this.workshopCode,
    required this.counts,
  });

  final int id;
  final DateTime createdAt;
  final String reason;
  final String workshopCode;
  final Map<String, int> counts;

  int get totalRows => counts.values.fold(0, (sum, count) => sum + count);
}

/// A remote configuration that would have removed many local rules. It is
/// kept aside until the manager applies it or keeps the local rules.
class CatalogConfigConflict {
  const CatalogConfigConflict({
    required this.detectedAt,
    required this.localCounts,
    required this.remoteCounts,
    required this.lostRows,
  });

  final DateTime detectedAt;
  final Map<String, int> localCounts;
  final Map<String, int> remoteCounts;

  /// Local rows of each guarded table that the remote copy does not contain.
  final Map<String, int> lostRows;
}

enum CatalogConfigImportResult { applied, unchanged, conflict }

/// Local-only protection of the workshop rule tables: snapshots, the shrink
/// guard for remote copies, and the restore used by the snapshots screen.
/// Both tables start with `_sync_`, so they are never exported, uploaded or
/// given tombstone triggers.
extension SqlDatabaseCatalogConfigGuard on SqlDatabase {
  static const String snapshotsTable = '_sync_catalog_config_snapshots';
  static const String pendingTable = '_sync_catalog_config_pending';
  static const int snapshotLimit = 5;

  /// Tables whose rows decide which profiles and accessories reach the
  /// quantity tables. A remote copy that drops many of them is not applied
  /// without the manager.
  static const List<String> guardedTables = [
    'SeriesDesignRoles',
    'CatalogItemRules',
  ];

  /// Bumped whenever a remote copy is held back, so the app can ask the
  /// manager.
  static final ValueNotifier<int> conflictSignal = ValueNotifier<int>(0);

  /// A single deleted rule always passes; losing more than 10 rows or more
  /// than a fifth of the table needs the manager.
  static bool losesTooMany({required int localRows, required int lostRows}) {
    if (lostRows < 2) return false;
    return lostRows > 10 || lostRows * 5 > localRows;
  }

  Future<void> _ensureCatalogConfigGuardSchema(
    DatabaseExecutor executor,
  ) async {
    await executor.execute('''
      CREATE TABLE IF NOT EXISTS $snapshotsTable (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        created_at TEXT NOT NULL,
        reason TEXT NOT NULL DEFAULT '',
        workshop_code TEXT NOT NULL DEFAULT '',
        counts TEXT NOT NULL DEFAULT '{}',
        payload TEXT NOT NULL
      )
    ''');
    await executor.execute('''
      CREATE TABLE IF NOT EXISTS $pendingTable (
        id INTEGER PRIMARY KEY CHECK (id = 1),
        detected_at TEXT NOT NULL,
        summary TEXT NOT NULL DEFAULT '{}',
        payload TEXT NOT NULL
      )
    ''');
  }

  Future<bool> _configTableExists(
    DatabaseExecutor executor,
    String table,
  ) async {
    final rows = await executor.rawQuery(
      "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ? LIMIT 1",
      [table],
    );
    return rows.isNotEmpty;
  }

  Future<Map<String, List<Map<String, dynamic>>>> _readCatalogConfigRows(
    DatabaseExecutor executor,
  ) async {
    final result = <String, List<Map<String, dynamic>>>{};
    for (final table in SqlDatabase.workshopCatalogConfigurationTables) {
      if (!await _configTableExists(executor, table)) continue;
      final rows = await executor.query(table);
      result[table] = [for (final row in rows) Map<String, dynamic>.from(row)];
    }
    return result;
  }

  static Map<String, int> _countRows(Map<String, dynamic> tables) => {
    for (final entry in tables.entries)
      if (entry.value is List) entry.key: (entry.value as List).length,
  };

  static Map<String, int> _decodeCounts(Object? raw) {
    try {
      final decoded = jsonDecode(raw?.toString() ?? '{}');
      if (decoded is! Map) return const {};
      return {
        for (final entry in decoded.entries)
          entry.key.toString(): (entry.value as num?)?.toInt() ?? 0,
      };
    } catch (_) {
      return const {};
    }
  }

  /// Saves the current rule tables. Nothing is saved when they are all empty
  /// or identical to the newest snapshot, so a sync running every few minutes
  /// does not push the useful copies out of the last [snapshotLimit].
  /// Returns the new snapshot id, or null when nothing was saved.
  Future<int?> saveCatalogConfigSnapshot({required String reason}) async {
    final myDb = await db;
    if (myDb == null) return null;
    await _ensureCatalogConfigGuardSchema(myDb);
    final tables = await _readCatalogConfigRows(myDb);
    if (tables.values.every((rows) => rows.isEmpty)) return null;
    final payload = jsonEncode(tables);
    final latest = await myDb.query(
      snapshotsTable,
      columns: ['payload'],
      orderBy: 'id DESC',
      limit: 1,
    );
    if (latest.isNotEmpty && latest.first['payload'] == payload) return null;

    var workshopCode = '';
    try {
      final prefs = await SharedPreferences.getInstance();
      workshopCode = prefs.getString('workshop_code') ?? '';
    } catch (_) {}
    final id = await myDb.insert(snapshotsTable, {
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'reason': reason,
      'workshop_code': workshopCode,
      'counts': jsonEncode(_countRows(tables)),
      'payload': payload,
    });
    await myDb.rawDelete(
      'DELETE FROM $snapshotsTable WHERE id NOT IN '
      '(SELECT id FROM $snapshotsTable ORDER BY id DESC LIMIT ?)',
      [snapshotLimit],
    );
    return id;
  }

  Future<List<CatalogConfigSnapshot>> readCatalogConfigSnapshots() async {
    final myDb = await db;
    if (myDb == null) return const [];
    await _ensureCatalogConfigGuardSchema(myDb);
    final rows = await myDb.query(
      snapshotsTable,
      columns: ['id', 'created_at', 'reason', 'workshop_code', 'counts'],
      orderBy: 'id DESC',
    );
    return [
      for (final row in rows)
        CatalogConfigSnapshot(
          id: (row['id'] as num).toInt(),
          createdAt:
              DateTime.tryParse(
                row['created_at']?.toString() ?? '',
              )?.toLocal() ??
              DateTime.fromMillisecondsSinceEpoch(0),
          reason: row['reason']?.toString() ?? '',
          workshopCode: row['workshop_code']?.toString() ?? '',
          counts: _decodeCounts(row['counts']),
        ),
    ];
  }

  /// Writes a snapshot back in one transaction. The rows of every table in
  /// the snapshot replace the local rows; their old deletion markers are
  /// removed so a later sync does not delete them again. The current rules
  /// are saved first, so a restore can itself be undone.
  Future<void> restoreCatalogConfigSnapshot(int snapshotId) async {
    final myDb = await db;
    if (myDb == null) throw StateError('database unavailable');
    await _ensureCatalogConfigGuardSchema(myDb);
    final rows = await myDb.query(
      snapshotsTable,
      columns: ['payload'],
      where: 'id = ?',
      whereArgs: [snapshotId],
      limit: 1,
    );
    if (rows.isEmpty) throw StateError('snapshot $snapshotId not found');
    final decoded = jsonDecode(rows.first['payload'].toString());
    if (decoded is! Map) throw StateError('snapshot $snapshotId is invalid');
    final tables = Map<String, dynamic>.from(decoded);

    await saveCatalogConfigSnapshot(reason: 'before_restore');
    await _writeCatalogConfigTables(myDb, tables);
    await myDb.delete(pendingTable);
    if (tables.containsKey('ShutterCalcRules')) {
      await ShutterCalcRules.load(this);
    }
  }

  Future<void> _writeCatalogConfigTables(
    Database myDb,
    Map<String, dynamic> tables,
  ) async {
    await myDb.transaction((txn) async {
      final hasFlags = await _configTableExists(txn, '_sync_runtime_flags');
      final hasTombstones = await _configTableExists(txn, 'SyncTombstones');
      if (hasFlags) {
        await txn.update('_sync_runtime_flags', {
          'suppress_tombstones': 1,
        }, where: 'id = 1');
      }
      for (final table in SqlDatabase.workshopCatalogConfigurationTables) {
        final tableRows = tables[table];
        if (tableRows is! List) continue;
        if (!await _configTableExists(txn, table)) continue;
        final columns = await _tableColumns(txn, table);
        await txn.delete(table);
        for (final row in tableRows) {
          if (row is! Map) continue;
          final values = Map<String, dynamic>.from(row)
            ..removeWhere((key, _) => !columns.contains(key));
          if (values.isEmpty) continue;
          await txn.insert(
            table,
            values,
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
          final id = values['id'];
          if (hasTombstones && id != null) {
            await txn.delete(
              'SyncTombstones',
              where: 'table_name = ? AND row_id = ?',
              whereArgs: [table, id.toString()],
            );
          }
        }
      }
      if (hasFlags) {
        await txn.update('_sync_runtime_flags', {
          'suppress_tombstones': 0,
        }, where: 'id = 1');
      }
    });
  }

  /// Local rows of each guarded table that [remote] would remove, counted by
  /// row id (a copy that swaps every rule for other ones loses them all).
  Future<Map<String, int>> _lostGuardedRows(
    Database myDb,
    Map<String, dynamic> remote,
  ) async {
    final lost = <String, int>{};
    for (final table in guardedTables) {
      final remoteRows = remote[table];
      if (remoteRows is! List) continue;
      if (!await _configTableExists(myDb, table)) continue;
      final localRows = await myDb.query(table);
      if (localRows.isEmpty) continue;
      final remoteIds = <String>{
        for (final row in remoteRows)
          if (row is Map && row['id'] != null) row['id'].toString(),
      };
      final localIds = [
        for (final row in localRows)
          if (row['id'] != null) row['id'].toString(),
      ];
      final missing = localIds.length == localRows.length
          ? localIds.where((id) => !remoteIds.contains(id)).length
          : max(0, localRows.length - remoteRows.length);
      lost[table] = missing;
    }
    return lost;
  }

  /// Decides whether [remote] would shrink a guarded table too much. When it
  /// does, the copy is stored for the manager and true is returned.
  Future<bool> _holdBackShrinkingConfiguration(
    Database myDb,
    Map<String, dynamic> remote,
  ) async {
    final lost = await _lostGuardedRows(myDb, remote);
    final localCounts = <String, int>{};
    var tooMany = false;
    for (final table in guardedTables) {
      if (!await _configTableExists(myDb, table)) continue;
      final count =
          Sqflite.firstIntValue(
            await myDb.rawQuery('SELECT COUNT(*) FROM $table'),
          ) ??
          0;
      localCounts[table] = count;
      if (losesTooMany(localRows: count, lostRows: lost[table] ?? 0)) {
        tooMany = true;
      }
    }
    if (!tooMany) return false;

    await _ensureCatalogConfigGuardSchema(myDb);
    await myDb.insert(pendingTable, {
      'id': 1,
      'detected_at': DateTime.now().toUtc().toIso8601String(),
      'summary': jsonEncode({
        'local': localCounts,
        'remote': _countRows(remote),
        'lost': lost,
      }),
      'payload': jsonEncode(remote),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    conflictSignal.value++;
    return true;
  }

  Future<CatalogConfigConflict?> readPendingCatalogConfigConflict() async {
    final myDb = await db;
    if (myDb == null) return null;
    await _ensureCatalogConfigGuardSchema(myDb);
    final rows = await myDb.query(
      pendingTable,
      columns: ['detected_at', 'summary'],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    Map<String, dynamic> summary = const {};
    try {
      final decoded = jsonDecode(rows.first['summary']?.toString() ?? '{}');
      if (decoded is Map) summary = Map<String, dynamic>.from(decoded);
    } catch (_) {}
    return CatalogConfigConflict(
      detectedAt:
          DateTime.tryParse(
            rows.first['detected_at']?.toString() ?? '',
          )?.toLocal() ??
          DateTime.now(),
      localCounts: _decodeCounts(jsonEncode(summary['local'] ?? const {})),
      remoteCounts: _decodeCounts(jsonEncode(summary['remote'] ?? const {})),
      lostRows: _decodeCounts(jsonEncode(summary['lost'] ?? const {})),
    );
  }

  /// The manager chose the remote copy: it replaces the local rules (a
  /// snapshot of them is taken first).
  Future<void> applyPendingCatalogConfigConflict() async {
    final myDb = await db;
    if (myDb == null) return;
    await _ensureCatalogConfigGuardSchema(myDb);
    final rows = await myDb.query(pendingTable, columns: ['payload'], limit: 1);
    if (rows.isEmpty) return;
    final decoded = jsonDecode(rows.first['payload'].toString());
    if (decoded is Map) {
      await importWorkshopCatalogConfiguration(
        Map<String, dynamic>.from(decoded),
        force: true,
      );
    }
    await myDb.delete(pendingTable);
  }

  /// The manager kept the local rules. The caller uploads them so the
  /// workshop copy matches again.
  Future<void> discardPendingCatalogConfigConflict() async {
    final myDb = await db;
    if (myDb == null) return;
    await _ensureCatalogConfigGuardSchema(myDb);
    await myDb.delete(pendingTable);
  }
}
