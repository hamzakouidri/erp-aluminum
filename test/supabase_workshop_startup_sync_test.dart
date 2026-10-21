import 'package:database_data/services/supabase_workshop_sync_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Supabase workshop startup sync policy', () {
    test('recognizes realtime rows echoed from the current device', () {
      expect(
        SupabaseWorkshopSyncService.isOwnDeviceSyncRow(
          row: {
            'device_id': 'desktop-1',
            'payload': {'id': 42},
          },
          currentDeviceId: 'desktop-1',
        ),
        isTrue,
      );
      expect(
        SupabaseWorkshopSyncService.isOwnDeviceSyncRow(
          row: {'device_id': 'phone-1'},
          currentDeviceId: 'desktop-1',
        ),
        isFalse,
      );
      expect(
        SupabaseWorkshopSyncService.isOwnDeviceSyncRow(
          row: {'device_id': 'desktop-1'},
          currentDeviceId: '',
        ),
        isFalse,
      );
    });

    test('drops own incremental echoes but keeps full recovery rows', () {
      final row = <String, dynamic>{'device_id': 'desktop-1'};
      expect(
        SupabaseWorkshopSyncService.shouldApplyDownloadedSyncRow(
          fullDownload: false,
          row: row,
          currentDeviceId: 'desktop-1',
        ),
        isFalse,
      );
      expect(
        SupabaseWorkshopSyncService.shouldApplyDownloadedSyncRow(
          fullDownload: true,
          row: row,
          currentDeviceId: 'desktop-1',
        ),
        isTrue,
      );
      expect(
        SupabaseWorkshopSyncService.shouldApplyDownloadedSyncRow(
          fullDownload: false,
          row: {'device_id': 'phone-1'},
          currentDeviceId: 'desktop-1',
        ),
        isTrue,
      );
    });

    test('uses a full download only before bootstrap completes', () {
      expect(
        SupabaseWorkshopSyncService.shouldDownloadFullOnStartup(
          bootstrapComplete: false,
          hasSyncCursor: false,
        ),
        isTrue,
      );
      expect(
        SupabaseWorkshopSyncService.shouldDownloadFullOnStartup(
          bootstrapComplete: true,
          hasSyncCursor: true,
        ),
        isFalse,
      );
    });

    test('repairs a missing incremental cursor once', () {
      expect(
        SupabaseWorkshopSyncService.shouldDownloadFullOnStartup(
          bootstrapComplete: true,
          hasSyncCursor: false,
        ),
        isTrue,
      );
    });

    test('catalog-only download never completes the business bootstrap', () {
      expect(
        SupabaseWorkshopSyncService.shouldCompleteFullBootstrap(
          downloadedBusinessRows: 0,
        ),
        isFalse,
      );
      expect(
        SupabaseWorkshopSyncService.shouldCompleteFullBootstrap(
          downloadedBusinessRows: 1,
        ),
        isTrue,
      );
    });

    test(
      'does not overwrite workshop rules while a local upload is pending',
      () {
        expect(
          SupabaseWorkshopSyncService.shouldApplyWorkshopCatalogConfiguration(
            hasPendingLocalChanges: true,
          ),
          isFalse,
        );
        expect(
          SupabaseWorkshopSyncService.shouldApplyWorkshopCatalogConfiguration(
            hasPendingLocalChanges: false,
          ),
          isTrue,
        );
      },
    );
  });
}
