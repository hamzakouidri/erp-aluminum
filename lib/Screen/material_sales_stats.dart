/// The money totals of the sales list, where a chain of documents
/// (commande -> delivery note -> invoice) counts once: the amount of its
/// last document, and what was paid on any document of the chain.
/// [rows] are the documents shown, [all] every document, to follow a chain
/// past the ones the filters hide.
({double revenue, double paid, double remaining, double internal})
materialSalesTotals(
  List<Map<String, dynamic>> rows,
  List<Map<String, dynamic>> all,
) {
  final byId = {
    for (final sale in all)
      if (sale['id'] is num) (sale['id'] as num).toInt(): sale,
  };
  double number(Object? value) => (value as num?)?.toDouble() ?? 0.0;

  // Each shown document joins the chain of its last document.
  final chains = <Object, List<Map<String, dynamic>>>{};
  for (final sale in rows) {
    var last = sale;
    for (var depth = 0; depth < 10; depth++) {
      final next = byId[(last['converted_to_sale_id'] as num?)?.toInt()];
      final status = (next?['status'] ?? '').toString().toLowerCase();
      if (next == null || status == 'cancelled') break;
      last = next;
    }
    chains.putIfAbsent(last['id'] ?? sale, () => [last]).add(sale);
  }

  var revenue = 0.0, paid = 0.0, remaining = 0.0, internal = 0.0;
  for (final chain in chains.values) {
    // chain.first is the last document, followed by the shown ones.
    final last = chain.first;
    final net = number(last['net_total']);
    if (last['is_internal'] == 1) {
      internal += net;
      continue;
    }
    final lastPaid = number(last['paid_amount']);
    final chainPaid = chain
        .map((sale) => number(sale['paid_amount']))
        .reduce((a, b) => a > b ? a : b);
    revenue += net;
    paid += chainPaid;
    // A payment left on an earlier document still lowers what is owed.
    remaining += (number(last['remaining_amount']) - (chainPaid - lastPaid))
        .clamp(0.0, double.infinity);
  }
  return (revenue: revenue, paid: paid, remaining: remaining, internal: internal);
}
