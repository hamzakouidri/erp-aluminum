/// Which activity of a client the account statement shows: the workshop
/// (orders and their payments), the store (sales and their payments), or
/// both together for a client of both.
enum ClientLedgerScope { workshop, store, both }

/// Whether a store document is a sale the client owes (or a return that
/// gives back): quotes and purchase orders are not sales yet, drafts and
/// cancelled documents never counted, and of a chain of documents
/// (commande -> delivery note -> invoice) only the last one that counts is
/// kept, so the same goods are owed once. [salesById] holds the client's
/// other documents, to see whether the one this was converted to counts.
bool isClientStoreLedgerDocument(
  Map<String, dynamic> sale, [
  Map<int, Map<String, dynamic>> salesById = const {},
  int depth = 0,
]) {
  final status = (sale['status'] ?? '').toString().trim().toLowerCase();
  if (status == 'draft' || status == 'cancelled') return false;
  final type = (sale['doc_type'] ?? '').toString().trim().toLowerCase();
  if (type == 'devis' || type == 'bon_commande' || type == 'bon_route') {
    return false;
  }
  if (type == 'retour') return true;
  final next = salesById[(sale['converted_to_sale_id'] as num?)?.toInt()];
  if (next == null || depth > 10) return true;
  return !isClientStoreLedgerDocument(next, salesById, depth + 1);
}

/// The statement lines of [scope], oldest first, each with its running
/// balance (copies; [all] is left unchanged), and the totals.
({
  List<Map<String, dynamic>> items,
  double debit,
  double credit,
  double balance,
})
clientLedgerForScope(List<Map<String, dynamic>> all, ClientLedgerScope scope) {
  final items = [
    for (final item in all)
      if (scope == ClientLedgerScope.both ||
          item['scope'] == (scope == ClientLedgerScope.store ? 'store' : 'workshop'))
        Map<String, dynamic>.from(item),
  ]..sort((a, b) => (a['date'] as DateTime).compareTo(b['date'] as DateTime));
  var balance = 0.0;
  var debit = 0.0;
  var credit = 0.0;
  for (final item in items) {
    final d = (item['debit'] as num?)?.toDouble() ?? 0.0;
    final c = (item['credit'] as num?)?.toDouble() ?? 0.0;
    balance += d - c;
    debit += d;
    credit += c;
    item['runningBalance'] = balance;
  }
  return (items: items, debit: debit, credit: credit, balance: debit - credit);
}

/// Lines of the "purchases" tab (what the client bought or returned) and of
/// the "payments" tab (what they paid or were refunded).
bool isClientLedgerPurchase(Map<String, dynamic> item) => const {
  'Order',
  'Delivery',
  'Sale',
  'Return',
}.contains(item['type']);

bool isClientLedgerPayment(Map<String, dynamic> item) =>
    item['type'] == 'Payment' || item['type'] == 'Refund';
