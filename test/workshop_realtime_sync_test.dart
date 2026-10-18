import 'dart:io';

import 'package:database_data/services/supabase_workshop_sync_service.dart';
import 'package:database_data/sql_database.dart';
import 'package:flutter_test/flutter_test.dart';

/// Guards for the live workshop sync (Realtime row apply + server cursor).
///
/// The cursor and Realtime logic lives in private methods that talk to the
/// Supabase client, so the wiring is checked against the source. A failure
/// here means one of the fixes was reverted or renamed.
void main() {
  final service = File(
    'lib/services/supabase_workshop_sync_service.dart',
  ).readAsStringSync();
  final cloudSync = File(
    'lib/services/cloud_sync_service.dart',
  ).readAsStringSync();

  String body(String source, String signature) {
    final start = source.indexOf(signature);
    expect(start, isNonNegative, reason: '$signature not found');
    final next = source.indexOf(
      RegExp(r'\n  (Future|bool|void|String) '),
      start + signature.length,
    );
    return source.substring(start, next < 0 ? source.length : next);
  }

  group('price tables travel with the workshop sync', () {
    test('every price table is a workshop table', () {
      expect(
        SqlDatabase.workshopTables,
        containsAll(SupabaseWorkshopSyncService.priceTables),
      );
    });

    test('price tables are never overwritten by the global catalogue', () {
      for (final table in SupabaseWorkshopSyncService.priceTables) {
        expect(
          SqlDatabase.catalogTables,
          isNot(contains(table)),
          reason: '$table must have one synchronization owner only',
        );
      }
    });

    test('price screens reporting a catalogue change also upload', () {
      final notify = body(cloudSync, 'Future<void> notifyCatalogChange(');
      expect(
        notify,
        contains('SupabaseWorkshopSyncService().notifyLocalChange()'),
      );
    });
  });

  group('Realtime events apply the changed row directly', () {
    test('workshop_sync_rows events go through the row queue first', () {
      final subscribe = body(service, 'void _subscribeToWorkshopDataChanges(');
      expect(subscribe, contains('if (_queueRealtimeRow(payload)) return;'));
    });

    test('own uploads echoed back are ignored', () {
      final queue = body(service, 'bool _queueRealtimeRow(');
      expect(queue, contains('deviceId == _deviceId'));
      // Profile/catalog metadata rows still use the cursor download.
      expect(queue, contains('_workshopProfileTable'));
      expect(queue, contains('_workshopCatalogConfigurationTable'));
    });

    test('a server hard delete becomes a local tombstone', () {
      final flush = body(service, 'Future<void> _flushRealtimeRows(');
      expect(flush, contains("entry.value['event'] != 'delete'"));
      expect(flush, contains("'deleted_at': now"));
      expect(flush, contains('explicitRows: rows'));
    });

    test('rows fetched for an event never move the cursors', () {
      final download = body(service, 'Future<void> _downloadChanges(');
      expect(
        download,
        contains('explicitRows == null && await _hasServerCursor()'),
      );
      expect(download, contains('if (explicitRows == null) {'));
    });
  });

  group('incremental cursor', () {
    test('uses the server stamp once it has been stored', () {
      final download = body(service, 'Future<void> _downloadChanges(');
      expect(download, contains("? 'server_updated_at'"));
      expect(download, contains('.gt(cursorColumn, cursorValue)'));
      expect(download, contains('.order(cursorColumn, ascending: true)'));
      expect(download, contains('_saveLastServerSyncAt(serverCursor)'));
    });

    test('falls back to updated_at when the migration was not run', () {
      final probe = body(service, 'Future<bool> _hasServerCursor(');
      expect(probe, contains("'42703'"));
      expect(probe, contains('_serverCursorSupported = false'));
    });

    test('a change arriving during a download queues one more pass', () {
      final download = body(service, 'Future<void> downloadWorkshopData(');
      expect(download, contains('_incrementalDownloadQueued = true'));
    });

    test('the migration stamps rows with the database clock', () {
      final sql = File('supabase/realtime_sync_cursor.sql').readAsStringSync();
      expect(sql, contains('server_updated_at timestamptz'));
      expect(sql, contains('new.server_updated_at := clock_timestamp()'));
      expect(
        sql,
        contains('before insert or update on public.workshop_sync_rows'),
      );
      expect(
        sql,
        contains('supabase_realtime add table public.workshop_sync_rows'),
      );
    });
  });
}
