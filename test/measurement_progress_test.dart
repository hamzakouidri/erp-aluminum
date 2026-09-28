import 'package:flutter_test/flutter_test.dart';
import 'package:database_data/Commande/measurement_progress.dart';

void main() {
  test('later stages count quantities and exclude resolved reservations', () {
    final progress = measurementProgress(
      quantity: 10,
      allocations: [
        {
          'quantity': 2,
          'is_distributed': 1,
          'is_transferred_to_dist': 1,
          'is_installed': 1,
          'has_reserve': 1,
        },
        {
          'quantity': 3,
          'is_transferred_to_dist': 1,
          'is_installed': 1,
          'is_completed': 1,
          'has_reserve': 1,
        },
      ],
    );
    expect(progress.distributed, 5);
    expect(progress.installed, 5);
    expect(progress.reserved, 2);
    expect(progress.completed, 3);
  });
  test('later stages stay attached to the selected measurement', () {
    final progress = measurementProgress(
      quantity: 1,
      unitIndices: {2},
      allocations: [
        {
          'unit_index': 1,
          'quantity': 1,
          'is_distributed': 1,
          'is_installed': 1,
          'is_completed': 1,
        },
        {'unit_index': 2, 'quantity': 1, 'has_reserve': 1},
      ],
    );
    expect(progress.distributed, 0);
    expect(progress.installed, 0);
    expect(progress.completed, 0);
    expect(progress.reserved, 1);
  });
  test(
    'mixed progress is counted by quantity independently for each stage',
    () {
      final progress = measurementProgress(
        quantity: 10,
        allocations: [
          {'quantity': 3, 'is_manufactured': 1, 'is_glass_installed': 1},
          {'quantity': 4, 'is_manufactured': 1, 'is_glass_installed': 0},
        ],
      );
      expect(progress.manufactured, 7);
      expect(progress.glass, 3);
      expect(progress.unknown, false);
    },
  );
  test('each measurement uses only its assigned units', () {
    final progress = measurementProgress(
      quantity: 1,
      unitIndices: {2},
      allocations: [
        {
          'unit_index': 1,
          'quantity': 1,
          'is_manufactured': 1,
          'is_glass_installed': 1,
        },
        {
          'unit_index': 2,
          'quantity': 1,
          'is_manufactured': 1,
          'is_glass_installed': 0,
        },
      ],
    );
    expect(progress.manufactured, 1);
    expect(progress.glass, 0);
  });
  test(
    'legacy grouped assignments do not mark an arbitrary measurement done',
    () {
      final progress = measurementProgress(
        quantity: 1,
        unitIndices: {2},
        allocations: [
          {'quantity': 3, 'is_manufactured': 1, 'is_glass_installed': 1},
        ],
      );
      expect(progress.manufactured, 0);
      expect(progress.glass, 0);
      expect(progress.unknown, true);
    },
  );
  test('unassigned item has no completed quantities', () {
    final progress = measurementProgress(quantity: 10, allocations: []);
    expect(progress.manufactured, 0);
    expect(progress.glass, 0);
  });
}
