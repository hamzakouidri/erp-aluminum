import 'package:database_data/services/supabase_workshop_sync_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('server sync cursor', () {
    test('the overlap window starts two minutes before the cursor', () {
      final from = SupabaseWorkshopSyncService.withServerCursorOverlap(
        '2026-10-17T10:00:00.000+00:00',
      );
      expect(
        DateTime.parse(from),
        DateTime.utc(2026, 10, 17, 9, 58),
      );
    });

    test('an unparsable cursor is kept as is', () {
      expect(
        SupabaseWorkshopSyncService.withServerCursorOverlap('not-a-date'),
        'not-a-date',
      );
    });

    test('timestamps compare by instant, not by text', () {
      // Same instant written with different offsets / precision.
      expect(
        SupabaseWorkshopSyncService.isLaterSyncTimestamp(
          '2026-10-17T12:00:00.000001+02:00',
          '2026-10-17T10:00:00Z',
        ),
        isTrue,
      );
      expect(
        SupabaseWorkshopSyncService.isLaterSyncTimestamp(
          '2026-10-17T11:00:00+02:00',
          '2026-10-17T10:00:00Z',
        ),
        isFalse,
      );
    });

    test('an unparsable candidate never moves the cursor', () {
      expect(
        SupabaseWorkshopSyncService.isLaterSyncTimestamp(
          '',
          '2026-10-17T10:00:00Z',
        ),
        isFalse,
      );
      expect(
        SupabaseWorkshopSyncService.isLaterSyncTimestamp(
          '2026-10-17T10:00:00Z',
          '',
        ),
        isTrue,
      );
    });
  });
}
