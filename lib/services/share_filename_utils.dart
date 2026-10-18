String shareSafeFilenamePart(String value, {String fallback = 'Client'}) {
  const arabicToLatin = <String, String>{
    'ا': 'a', 'أ': 'a', 'إ': 'i', 'آ': 'a', 'ء': 'a', 'ؤ': 'ou', 'ئ': 'i',
    'ب': 'b', 'ت': 't', 'ث': 'th', 'ج': 'j', 'ح': 'h', 'خ': 'kh',
    'د': 'd', 'ذ': 'dh', 'ر': 'r', 'ز': 'z', 'س': 's', 'ش': 'ch',
    'ص': 's', 'ض': 'd', 'ط': 't', 'ظ': 'dh', 'ع': 'a', 'غ': 'gh',
    'ف': 'f', 'ق': 'q', 'ك': 'k', 'ل': 'l', 'م': 'm', 'ن': 'n',
    'ه': 'h', 'ة': 'a', 'و': 'ou', 'ى': 'a', 'ي': 'i', 'ﻻ': 'la',
    'ً': '', 'ٌ': '', 'ٍ': '', 'َ': '', 'ُ': '', 'ِ': '', 'ّ': '', 'ْ': '',
  };
  const latinVariants = <String, String>{
    'à': 'a', 'á': 'a', 'â': 'a', 'ä': 'a', 'ç': 'c', 'è': 'e',
    'é': 'e', 'ê': 'e', 'ë': 'e', 'î': 'i', 'ï': 'i', 'ô': 'o',
    'ö': 'o', 'ù': 'u', 'û': 'u', 'ü': 'u', 'À': 'A', 'Á': 'A',
    'Â': 'A', 'Ä': 'A', 'Ç': 'C', 'È': 'E', 'É': 'E', 'Ê': 'E',
    'Ë': 'E', 'Î': 'I', 'Ï': 'I', 'Ô': 'O', 'Ö': 'O', 'Ù': 'U',
    'Û': 'U', 'Ü': 'U',
  };

  final converted = StringBuffer();
  for (final rune in value.runes) {
    final character = String.fromCharCode(rune);
    converted.write(arabicToLatin[character] ?? latinVariants[character] ?? character);
  }
  final safe = converted
      .toString()
      .replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_')
      .replaceAll(RegExp(r'_+'), '_')
      .replaceAll(RegExp(r'^_|_$'), '');
  return safe.isEmpty ? fallback : safe;
}

String sharedPdfFilename({
  required String documentType,
  required Object? orderNumber,
  required String clientName,
}) {
  final type = shareSafeFilenamePart(documentType, fallback: 'Document');
  final order = shareSafeFilenamePart('$orderNumber', fallback: 'Order');
  final client = shareSafeFilenamePart(clientName, fallback: 'Client');
  return '${type}_${order}_${client}.pdf';
}
