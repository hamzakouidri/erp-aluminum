/// The canonical order lifecycle used by order lists, filters and charts.
int orderStatusWeight(String status) {
  final value = status.trim().toLowerCase();

  if (value == 'nouveau' ||
      value == 'new' ||
      value == 'جديدة' ||
      value == 'جديد' ||
      value == 'draft') {
    return 10;
  }
  if (value == 'confirmed' ||
      value.contains('مؤكد') ||
      value.contains('confirme')) {
    return 20;
  }
  if (value == 'pending' ||
      value == 'en attente' ||
      value == 'en_attente' ||
      value.contains('انتظار')) {
    return 30;
  }
  if (value == 'in progress' ||
      value.contains('قياسات') ||
      value.contains('جارية') ||
      value.contains('cours')) {
    return 40;
  }
  if (value == 'partial manufacturing' ||
      value.contains('تصنيع جزئي') ||
      value.contains('fabrication partielle')) {
    return 50;
  }
  if (value == 'full manufacturing' ||
      value.contains('تصنيع كامل') ||
      value.contains('تصنيع كلي') ||
      value.contains('fabrication totale') ||
      value.contains('fabrication complète')) {
    return 60;
  }
  if (value == 'partial distribution' ||
      value.contains('توزيع جزئي') ||
      value.contains('livraison partielle')) {
    return 70;
  }
  if (value == 'full distribution' ||
      value.contains('توزيع كامل') ||
      value.contains('توزيع كلي') ||
      value.contains('livraison totale') ||
      value.contains('livraison complète')) {
    return 80;
  }
  if (value == 'installation' || value.contains('تركيب')) return 90;
  if (value == 'reserve' ||
      value.contains('تحفظ') ||
      value.contains('réserve')) {
    return 95;
  }
  if (value == 'done' ||
      value == 'livré' ||
      value == 'livre' ||
      value.contains('منتهي') ||
      value.contains('مكتمل')) {
    return 100;
  }
  if (value == 'cancelled' ||
      value.contains('ملغاة') ||
      value.contains('annulé')) {
    return 999;
  }
  return 45;
}

int compareOrdersByLifecycle(
  Map<String, dynamic> first,
  Map<String, dynamic> second,
) {
  final firstWeight = orderStatusWeight((first['status'] ?? '').toString());
  final secondWeight = orderStatusWeight((second['status'] ?? '').toString());
  final statusComparison = firstWeight.compareTo(secondWeight);
  if (statusComparison != 0) return statusComparison;

  final firstUpdated =
      DateTime.tryParse(
        (first['updated_at'] ?? first['created_at'] ?? '').toString(),
      ) ??
      DateTime.fromMillisecondsSinceEpoch(0);
  final secondUpdated =
      DateTime.tryParse(
        (second['updated_at'] ?? second['created_at'] ?? '').toString(),
      ) ??
      DateTime.fromMillisecondsSinceEpoch(0);
  final dateComparison = secondUpdated.compareTo(firstUpdated);
  if (dateComparison != 0) return dateComparison;

  final firstId = int.tryParse((first['id'] ?? '').toString()) ?? 0;
  final secondId = int.tryParse((second['id'] ?? '').toString()) ?? 0;
  return secondId.compareTo(firstId);
}
