import 'package:database_data/Commande/order_pinning.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('pinned orders use pin time while regular orders keep sorting', () {
    final sorted = [
      {'id': 4, 'is_pinned': 0},
      {'id': 3, 'is_pinned': 1, 'pinned_at': '2026-10-04T12:00:00Z'},
      {'id': 2, 'is_pinned': 1, 'pinned_at': '2026-10-05T12:00:00Z'},
      {'id': 1, 'is_pinned': 0},
    ];

    expect(putPinnedOrdersFirst(sorted).map((order) => order['id']), [
      2,
      3,
      4,
      1,
    ]);
  });

  test('pinning is applied only to the already filtered search result', () {
    final searchResult = [
      {'id': 8, 'is_pinned': true},
      {'id': 6, 'is_pinned': false},
    ];

    final result = putPinnedOrdersFirst(searchResult);

    expect(result.map((order) => order['id']), [8, 6]);
    expect(result.any((order) => order['id'] == 9), isFalse);
  });
}
