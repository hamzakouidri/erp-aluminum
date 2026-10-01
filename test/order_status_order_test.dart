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
}
