import 'package:database_data/Screen/material_sales_stats.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Map<String, dynamic> doc(int id, String type, {int? next, double paid = 0}) => {
    'id': id,
    'doc_type': type,
    'status': 'confirmed',
    'converted_to_sale_id': next,
    'net_total': 22600.0,
    'paid_amount': paid,
    'remaining_amount': 22600.0 - paid,
  };

  test('a commande -> delivery note -> invoice chain counts once', () {
    final all = [
      doc(1, 'bon_commande', next: 2),
      doc(2, 'bon_livraison', next: 3),
      doc(3, 'facture'),
    ];
    final totals = materialSalesTotals(all, all);
    expect(totals.revenue, 22600);
    expect(totals.paid, 0);
    expect(totals.remaining, 22600);
  });

  test('a payment on an earlier document lowers what is owed', () {
    final all = [doc(1, 'bon_commande', next: 2, paid: 5000), doc(2, 'facture')];
    final totals = materialSalesTotals(all, all);
    expect(totals.paid, 5000);
    expect(totals.remaining, 17600);
  });

  test('a filtered list still follows the chain to its last document', () {
    final all = [doc(1, 'bon_commande', next: 2), doc(2, 'facture')];
    final totals = materialSalesTotals([all.first], all);
    expect(totals.revenue, 22600);
  });

  test('separate documents add up', () {
    final all = [doc(1, 'facture'), doc(2, 'facture')];
    expect(materialSalesTotals(all, all).revenue, 45200);
  });
}
