bool isOrderPinned(Map<String, dynamic> order) {
  final value = order['is_pinned'];
  if (value is bool) return value;
  if (value is num) return value != 0;
  final normalized = value?.toString().trim().toLowerCase();
  return normalized == '1' || normalized == 'true';
}

/// Moves pinned orders to the front. Pinned orders use their pin time (newest
/// first), so the table's selected sort affects only regular orders. Search
/// and filters must run before this partition.
List<Map<String, dynamic>> putPinnedOrdersFirst(
  List<Map<String, dynamic>> orders,
) {
  final pinned = <Map<String, dynamic>>[];
  final regular = <Map<String, dynamic>>[];
  for (final order in orders) {
    (isOrderPinned(order) ? pinned : regular).add(order);
  }
  pinned.sort((a, b) {
    final aTime = DateTime.tryParse(a['pinned_at']?.toString() ?? '');
    final bTime = DateTime.tryParse(b['pinned_at']?.toString() ?? '');
    if (aTime == null && bTime == null) return 0;
    if (aTime == null) return 1;
    if (bTime == null) return -1;
    return bTime.compareTo(aTime);
  });
  return [...pinned, ...regular];
}
