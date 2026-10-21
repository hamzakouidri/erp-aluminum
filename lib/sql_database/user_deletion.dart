part of '../sql_database.dart';

/// The workshop's rule for deletions: a row is deleted on the other devices
/// only when someone deleted it here on purpose. A deletion is recorded (a
/// SyncTombstones row plus a 'delete' change) only inside [runUserDeletion];
/// a row that disappears any other way (workshop change, sign-out, restore,
/// automatic clean-up, import) is never sent as a deletion.
extension SqlDatabaseUserDeletion on SqlDatabase {
  static int _activeScopes = 0;

  /// Open delete actions. While one is open the deletion flag stays on.
  static int get activeScopes => _activeScopes;

  /// Runs [body] as an explicit delete action named [source] (for example
  /// `deleteClient`): the rows it deletes are recorded with the signed-in
  /// account and [source], and sent to the other devices. Pass [executor]
  /// when the caller already holds a transaction.
  Future<T> runUserDeletion<T>(
    String source,
    Future<T> Function() body, {
    DatabaseExecutor? executor,
  }) async {
    final target = executor ?? await db;
    final opens = _activeScopes == 0 && target != null;
    _activeScopes++;
    try {
      if (opens) await _setDeletionFlag(target, source);
      return await body();
    } finally {
      _activeScopes--;
      if (opens && _activeScopes == 0) await _setDeletionFlag(target, null);
    }
  }

  Future<void> _setDeletionFlag(DatabaseExecutor target, String? source) async {
    try {
      await _ensureSyncTombstoneInfrastructure(target);
      await target.update('_sync_runtime_flags', {
        'record_deletions': source == null ? 0 : 1,
        'deletion_source': source,
      }, where: 'id = 1');
    } catch (error) {
      debugPrint('Deletion flag not updated: $error');
    }
  }

  /// Empties the workshop tables and the rule tables of this device without
  /// recording any deletion, and drops their unsent changes: the rows belong
  /// to a workshop this device leaves, so nothing may reach the server.
  Future<void> clearLocalWorkshopTables() async {
    final myDb = await db;
    if (myDb == null) return;
    final cleared = [
      ...SqlDatabase.workshopTables,
      ...SqlDatabase.workshopCatalogConfigurationTables,
    ];
    await myDb.transaction((txn) async {
      await _ensureSyncTombstoneInfrastructure(txn);
      await txn.update('_sync_runtime_flags', {
        'suppress_tombstones': 1,
      }, where: 'id = 1');
      for (final table in cleared) {
        try {
          await txn.delete(table);
        } catch (_) {}
      }
      final marks = List.filled(cleared.length, '?').join(',');
      await txn.delete(
        'SyncTombstones',
        where: 'table_name IN ($marks)',
        whereArgs: cleared,
      );
      await txn.delete(
        '_sync_change_log',
        where: 'table_name IN ($marks)',
        whereArgs: cleared,
      );
      await txn.update('_sync_runtime_flags', {
        'suppress_tombstones': 0,
      }, where: 'id = 1');
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(SqlDatabaseBusinessDataGuard.localDataOwnerKey);
  }
}
