/// Keeps the text exactly as entered (Arabic, French or English), removing
/// only the characters a file name cannot hold.
String shareSafeFilenamePart(String value, {String fallback = 'Client'}) {
  final safe = value
      .replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1F]'), '_')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim()
      .replaceAll(RegExp(r'^[ ._]+|[ ._]+$'), '');
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
  return '${type}_${order}_$client.pdf';
}

/// A quote is named after its client, as the client was entered; without a
/// client name it falls back to `devis_<order>`.
String devisPdfBaseName({
  required String clientName,
  required Object? orderNumber,
}) {
  return shareSafeFilenamePart(clientName, fallback: 'devis_$orderNumber');
}
