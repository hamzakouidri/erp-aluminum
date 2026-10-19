import 'package:database_data/Commande/devis_builder.dart';
import 'package:flutter_test/flutter_test.dart';

DevisData _quote(String status) => DevisData(
  orderId: 1,
  orderDate: '2026-10-18',
  validUntil: '2026-11-18',
  workshop: DevisWorkshopInfo.empty,
  clientName: 'Client',
  clientPhone: '',
  items: const [],
  totalBrut: 1000,
  remise: 100,
  totalBeforeTax: 900,
  totalHT: 900,
  tvaPercent: 19,
  tvaAmount: 171,
  totalTTC: 1071,
  amountPaid: 500,
  amountInWords: '',
  rawOrder: {'status': status},
);

void main() {
  test('payments are shown only once the order is confirmed', () {
    for (final pending in ['Nouveau', 'en attente', 'في الانتظار', 'draft']) {
      expect(_quote(pending).showsPayments, isFalse, reason: pending);
    }
    for (final confirmed in ['Confirmed', 'مؤكدة', 'delivered']) {
      expect(_quote(confirmed).showsPayments, isTrue, reason: confirmed);
    }
  });
}
