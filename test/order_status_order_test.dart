import 'package:database_data/Commande/order_status_order.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('order statuses follow the same lifecycle in every language', () {
    expect(
      orderStatusWeight('Nouveau'),
      lessThan(orderStatusWeight('Confirmed')),
    );
    expect(
      orderStatusWeight('Confirmed'),
      lessThan(orderStatusWeight('En attente')),
    );
    expect(
      orderStatusWeight('En attente'),
      lessThan(orderStatusWeight('In Progress')),
    );
    expect(
      orderStatusWeight('In Progress'),
      lessThan(orderStatusWeight('Partial Manufacturing')),
    );
    expect(
      orderStatusWeight('تصنيع جزئي'),
      lessThan(orderStatusWeight('تصنيع كامل')),
    );
    expect(
      orderStatusWeight('Full Manufacturing'),
      lessThan(orderStatusWeight('Partial Distribution')),
    );
    expect(
      orderStatusWeight('توزيع جزئي'),
      lessThan(orderStatusWeight('توزيع كامل')),
    );
    expect(orderStatusWeight('Done'), lessThan(orderStatusWeight('Cancelled')));
  });

  test('orders are grouped by lifecycle then newest first', () {
    final orders = <Map<String, dynamic>>[
      {'id': 1, 'status': 'Confirmed', 'updated_at': '2026-01-01'},
      {'id': 2, 'status': 'Nouveau', 'updated_at': '2026-01-01'},
      {'id': 3, 'status': 'Confirmed', 'updated_at': '2026-02-01'},
    ]..sort(compareOrdersByLifecycle);

    expect(orders.map((order) => order['id']), [2, 3, 1]);
  });

  test('equivalent new-order labels share one status filter group', () {
    expect(orderStatusGroupKey('Nouveau'), 'new');
    expect(orderStatusGroupKey('New'), 'new');
    expect(orderStatusGroupKey('جديدة'), 'new');
    expect(orderStatusCanonicalLabel('New'), 'Nouveau');
  });

  test(
    'dashboard merges every legacy new-order label into one Nouveau row',
    () {
      final counts = canonicalizeOrderStatusCounts({
        'Nouveau': 2,
        'New': 3,
        'Draft': 1,
        'جديدة': 4,
      });

      expect(counts, {'Nouveau': 10});
    },
  );

  test('canonical stages include measurements and installation in order', () {
    expect(
      canonicalOrderStatuses.indexOf('In Progress'),
      lessThan(canonicalOrderStatuses.indexOf('Partial Manufacturing')),
    );
    expect(
      canonicalOrderStatuses.indexOf('Partial Manufacturing'),
      lessThan(canonicalOrderStatuses.indexOf('Full Manufacturing')),
    );
    expect(
      canonicalOrderStatuses.indexOf('Full Distribution'),
      lessThan(canonicalOrderStatuses.indexOf('Installation')),
    );
  });

  test('open-order rule excludes every terminal status spelling', () {
    expect(isOpenOrderStatus('Nouveau'), isTrue);
    expect(isOpenOrderStatus('In Progress'), isTrue);
    expect(isOpenOrderStatus('Done'), isFalse);
    expect(isOpenOrderStatus('Cancelled'), isFalse);
    expect(isOpenOrderStatus('Completed'), isFalse);
    expect(isOpenOrderStatus('Archived'), isFalse);
    expect(isOpenOrderStatus('أرشيف'), isFalse);
  });
}
