/// Converts generated profile roles to the Arabic labels shown in the
/// required-goods table while preserving real catalogue product names.
String requiredGoodsRoleLabel(String original) {
  final trimmed = original.trim();
  if (trimmed.startsWith('Cadre doublé') ||
      trimmed.startsWith('Cadre double') ||
      trimmed.startsWith('كادر دوبلي') ||
      trimmed.startsWith('كادر دبل')) {
    return 'إطار مزدوج';
  }
  final arabicLabel = trimmed.split('(').first.trim();
  if (RegExp(r'[\u0600-\u06FF]').hasMatch(arabicLabel)) {
    return arabicLabel;
  }
  if (trimmed == 'Sash Central Renforcé') return 'قائم وسطي معزز';
  if (trimmed == 'Sash Lateral Renforcé') return 'قائم جانبي معزز';
  if (trimmed == 'Sash Central') return 'قائم وسطي';
  if (trimmed == 'Sash Lateral') return 'قائم جانبي';
  if (trimmed.contains('الإطار (Frame)') ||
      trimmed == 'الإطار' ||
      trimmed == 'Frame' ||
      trimmed == 'Cadre' ||
      trimmed == 'Dormant') {
    return 'الإطار';
  }
  if (trimmed.contains('إطار منزلق') || trimmed.contains('Cadre Coulissant')) {
    return 'إطار منزلق';
  }
  if (trimmed.contains('تقسيم الزجاج') ||
      trimmed.contains('Mullion') ||
      trimmed.contains('Traverse') ||
      trimmed == 'Montant' ||
      trimmed.contains('تقسيم')) {
    return 'التقسيم';
  }
  if (trimmed.contains('ضلفة') ||
      trimmed.contains('دلفة') ||
      trimmed.contains('Sash') ||
      trimmed.contains('Ouvrant') ||
      trimmed == 'Vantail') {
    return 'الضلفة';
  }
  if (trimmed.contains('باركلوز') || trimmed.contains('Parclose')) {
    return 'الباركلوز';
  }
  return trimmed;
}
