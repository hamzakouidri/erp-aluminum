import 'dart:convert';

double _positiveDouble(Object? value, [double fallback = 0]) {
  final parsed = value is num
      ? value.toDouble()
      : double.tryParse(value?.toString().trim() ?? '');
  return parsed != null && parsed > 0 ? parsed : fallback;
}

int _positiveInt(Object? value, [int fallback = 0]) {
  final parsed = value is num
      ? value.toInt()
      : int.tryParse(value?.toString().trim() ?? '');
  return parsed != null && parsed > 0 ? parsed : fallback;
}

List<Map<String, dynamic>> _readRows(Object? raw) {
  if (raw == null) return const [];
  dynamic decoded = raw;
  if (raw is String) {
    if (raw.trim().isEmpty) return const [];
    try {
      decoded = jsonDecode(raw);
    } catch (_) {
      return const [];
    }
  }
  if (decoded is! List) return const [];
  return decoded.whereType<Map>().map(Map<String, dynamic>.from).toList();
}

/// Returns the real production-size breakdown for an order detail.
///
/// Confirmed measurements are authoritative. Draft instances are used only
/// when confirmation is absent, and the commercial order dimensions fill any
/// unmeasured remainder. Equal measurements are collapsed into one quantity,
/// while even slightly different dimensions remain separate cutting groups.
List<Map<String, dynamic>> productionMeasurementInstances(
  Map<String, dynamic> detail, {
  int? quantityLimit,
}) {
  final orderedQuantity = _positiveInt(
    detail['quantity'] ?? detail['quantite'] ?? detail['nbr'],
    1,
  );
  final targetQuantity = (quantityLimit ?? orderedQuantity)
      .clamp(0, orderedQuantity)
      .toInt();
  if (targetQuantity == 0) return const [];

  final defaultWidth = _positiveDouble(detail['largeur'] ?? detail['width']);
  final defaultHeight = _positiveDouble(
    detail['hauteur'] ?? detail['height'],
  );
  final confirmed = _readRows(detail['confirmed_mesures_json']);
  final drafts = _readRows(detail['instances_json']);
  final source = confirmed.isNotEmpty ? confirmed : drafts;

  final normalized = <Map<String, dynamic>>[];
  for (final row in source) {
    final width = _positiveDouble(
      row['width'] ?? row['largeur'],
      defaultWidth,
    );
    final height = _positiveDouble(
      row['height'] ?? row['hauteur'],
      defaultHeight,
    );
    if (width <= 0 || height <= 0) continue;
    normalized.add({
      'width': width,
      'height': height,
      'qty': _positiveInt(row['qty'] ?? row['quantity'], 1),
      'position': row['position']?.toString().trim() ?? '',
      'confirmed': confirmed.isNotEmpty,
    });
  }

  if (normalized.isEmpty && defaultWidth > 0 && defaultHeight > 0) {
    normalized.add({
      'width': defaultWidth,
      'height': defaultHeight,
      'qty': targetQuantity,
      'position': '',
      'confirmed': false,
    });
  }

  // Consume only the requested production batch and never exceed the order.
  var remaining = targetQuantity;
  final capped = <Map<String, dynamic>>[];
  for (final row in normalized) {
    if (remaining <= 0) break;
    final qty = _positiveInt(row['qty'], 1).clamp(1, remaining).toInt();
    capped.add({...row, 'qty': qty});
    remaining -= qty;
  }
  if (remaining > 0 && defaultWidth > 0 && defaultHeight > 0) {
    capped.add({
      'width': defaultWidth,
      'height': defaultHeight,
      'qty': remaining,
      'position': '',
      'confirmed': false,
    });
  }

  // Millimetre values are keyed at 0.001 mm precision: no tolerance-based
  // merging is allowed for manufacturing cuts.
  final grouped = <String, Map<String, dynamic>>{};
  for (final row in capped) {
    final width = row['width'] as double;
    final height = row['height'] as double;
    final key = '${width.toStringAsFixed(3)}|${height.toStringAsFixed(3)}';
    final existing = grouped[key];
    if (existing == null) {
      grouped[key] = Map<String, dynamic>.from(row);
    } else {
      existing['qty'] = (existing['qty'] as int) + (row['qty'] as int);
      existing['confirmed'] =
          existing['confirmed'] == true && row['confirmed'] == true;
    }
  }
  return grouped.values.toList(growable: false);
}
