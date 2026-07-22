import 'package:intl/intl.dart';

/// يعيد أفضل تاريخ متاح للطلبية (إنشاء ثم تحديث).
dynamic resolveOrderDate(Map<String, dynamic> order) {
  for (final key in ['created_at', 'updated_at']) {
    final value = order[key];
    if (value != null &&
        value.toString().trim().isNotEmpty &&
        value.toString() != 'null') {
      return value;
    }
  }
  return null;
}

/// تنسيق تاريخ الطلبية للعرض في الواجهة أو PDF.
String formatOrderDate(
  dynamic date, {
  dynamic fallback,
  String emptyLabel = 'تاريخ غير متوفر',
  bool includeTime = true,
}) {
  final resolved = _firstValidDate(date, fallback);
  if (resolved == null) return emptyLabel;

  final text = resolved.toString().trim();
  DateTime? parsed;

  final formats = [
    DateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS"),
    DateFormat("yyyy-MM-dd'T'HH:mm:ss"),
    DateFormat('yyyy-MM-dd HH:mm:ss'),
    DateFormat('yyyy-MM-dd HH:mm'),
    DateFormat('yyyy/MM/dd HH:mm'),
    DateFormat('yyyy/MM/dd'),
    DateFormat('yyyy-MM-dd'),
  ];

  for (final format in formats) {
    try {
      parsed = format.parse(text);
      break;
    } catch (_) {}
  }

  parsed ??= DateTime.tryParse(text);

  if (parsed != null) {
    final localDate = parsed.isUtc ? parsed.toLocal() : parsed;
    if (includeTime && (localDate.hour != 0 || localDate.minute != 0)) {
      final hour = localDate.hour.toString().padLeft(2, '0');
      final minute = localDate.minute.toString().padLeft(2, '0');
      return '${DateFormat('yyyy-MM-dd').format(localDate)}  $hour:$minute';
    }
    return DateFormat('yyyy-MM-dd').format(localDate);
  }

  if (text.contains('T')) return text.replaceFirst('T', ' ');
  return text;
}

dynamic _firstValidDate(dynamic primary, dynamic fallback) {
  for (final value in [primary, fallback]) {
    if (value != null &&
        value.toString().trim().isNotEmpty &&
        value.toString() != 'null') {
      return value;
    }
  }
  return null;
}
