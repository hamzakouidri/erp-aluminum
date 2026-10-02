import 'package:database_data/services/supabase_workshop_sync_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Supabase workshop startup sync policy', () {
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
  });
}
