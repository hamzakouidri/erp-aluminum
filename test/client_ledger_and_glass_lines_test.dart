import 'package:database_data/Commande/Systeme/calculate_component.dart';
import 'package:database_data/Screen/client_ledger_view.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _line(
  String type,
  String scope,
  int day, {
  double debit = 0,
  double credit = 0,
}) => {
  'type': type,
  'scope': scope,
  'date': DateTime(2026, 1, day),
  'debit': debit,
  'credit': credit,
};

void main() {
  group('client statement', () {
    final all = [
      _line('Order', 'workshop', 1, debit: 1000),
      _line('Sale', 'store', 2, debit: 300),
      _line('Payment', 'workshop', 3, credit: 400),
      _line('Payment', 'store', 4, credit: 100),
      _line('Return', 'store', 5, credit: 50),
    ];

    test('the workshop alone', () {
      final view = clientLedgerForScope(all, ClientLedgerScope.workshop);
      expect(view.items, hasLength(2));
      expect(view.debit, 1000);
      expect(view.credit, 400);
      expect(view.balance, 600);
    });

    test('the store alone', () {
      final view = clientLedgerForScope(all, ClientLedgerScope.store);
      expect(view.items.map((i) => i['type']), ['Sale', 'Payment', 'Return']);
      expect(view.balance, 150);
    });

    test('both together, with a running balance in date order', () {
      final view = clientLedgerForScope(all, ClientLedgerScope.both);
      expect(view.balance, 750);
      expect(
        view.items.map((i) => i['runningBalance']),
        [1000.0, 1300.0, 900.0, 800.0, 750.0],
      );
      // The source lines are left as they were.
      expect(all.first.containsKey('runningBalance'), isFalse);
    });

    test('purchases and payments tabs', () {
      expect(all.where(isClientLedgerPurchase), hasLength(3));
      expect(all.where(isClientLedgerPayment), hasLength(2));
    });

    test('only real store sales count', () {
      expect(
        isClientStoreLedgerDocument({'doc_type': 'bon_livraison', 'status': 'confirmed'}),
        isTrue,
      );
      expect(
        isClientStoreLedgerDocument({'doc_type': 'retour', 'status': 'confirmed', 'source_sale_id': 3}),
        isTrue,
      );
      expect(isClientStoreLedgerDocument({'doc_type': 'devis'}), isFalse);
      expect(
        isClientStoreLedgerDocument({'doc_type': 'facture', 'status': 'draft'}),
        isFalse,
      );
    });

    test('a commande -> delivery note -> invoice chain counts once', () {
      final vs = {'id': 1, 'doc_type': 'bon_commande', 'status': 'confirmed', 'converted_to_sale_id': 2};
      final bl = {'id': 2, 'doc_type': 'bon_livraison', 'status': 'delivered', 'source_sale_id': 1, 'converted_to_sale_id': 3};
      final fv = {'id': 3, 'doc_type': 'facture', 'status': 'confirmed', 'source_sale_id': 2};
      final byId = {1: vs, 2: bl, 3: fv};
      expect(isClientStoreLedgerDocument(vs, byId), isFalse);
      expect(isClientStoreLedgerDocument(bl, byId), isFalse);
      expect(isClientStoreLedgerDocument(fv, byId), isTrue);
      // While the invoice is still a draft, the delivery note is what is owed.
      final draftFv = {...fv, 'status': 'draft'};
      final draftById = {1: vs, 2: bl, 3: draftFv};
      expect(isClientStoreLedgerDocument(bl, draftById), isTrue);
      expect(isClientStoreLedgerDocument(draftFv, draftById), isFalse);
    });
  });

  group('glass composition lines', () {
    String fr(String w) => w == 'شفاف' ? 'Clair' : w;

    test('French: the French label, materials and units translated', () {
      expect(
        BomItem.localizeGlassLine(
          '- Face intérieure / الوجه الداخلي: شفاف شفاف (1800.00 دج/م²)',
          'fr',
          translateWord: fr,
        ),
        '- Face intérieure: Clair Clair (1800.00 DA/m²)',
      );
      expect(
        BomItem.localizeGlassLine('- Gaz / الغاز (300.00 دج/م²)', 'fr'),
        '- Gaz (300.00 DA/m²)',
      );
    });

    test('Arabic: the Arabic label, units kept', () {
      expect(
        BomItem.localizeGlassLine(
          '- Intercalaire / الفاصل: 12 مم (500.00 دج/م²)',
          'ar',
        ),
        '- الفاصل: 12 مم (500.00 دج/م²)',
      );
    });
  });
}
