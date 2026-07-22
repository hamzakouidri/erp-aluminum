import re

path_pdf = r'c:\Users\hp\Desktop\Noraleur\erp-aluminum-main\lib\Commande\pdf_invoice_api.dart'

with open(path_pdf, 'r', encoding='utf-8') as f:
    code = f.read()

# 1. Update buildPdfBytes to run on main thread using cached fonts
OLD_BUILD_PDF_BYTES = """  static Future<Uint8List> buildPdfBytes(DevisData data) async {
    final prefs = await SharedPreferences.getInstance();
    final langIndex = prefs.getInt('app_language') ?? 0;
    final lang = AppLanguage.values[langIndex];

    await preloadFonts();
    final regularBytes = _fontBytes!;
    final boldBytes = _fontBoldBytes!;

    return await compute(
      _buildPdfIsolate,
      _PdfIsolateParams(
        data: data,
        language: lang,
        regularBytes: regularBytes,
        boldBytes: boldBytes,
      ),
    );
  }"""

NEW_BUILD_PDF_BYTES = """  static Future<Uint8List> buildPdfBytes(DevisData data) async {
    final prefs = await SharedPreferences.getInstance();
    final langIndex = prefs.getInt('app_language') ?? 0;
    _currentLang = AppLanguage.values[langIndex];

    await preloadFonts();
    final font = _cachedFont!;
    final fontBold = _cachedFontBold!;

    final pdf = pw.Document();

    final imageWidgets = <int, pw.MemoryImage>{};
    if (!data.isProForma) {
      for (int i = 0; i < data.items.length; i++) {
        final path = data.items[i].imagePath;
        if (path != null && path.isNotEmpty) {
          try {
            final file = File(path);
            if (file.existsSync()) {
              imageWidgets[i] = pw.MemoryImage(file.readAsBytesSync());
            }
          } catch (_) {}
        }
      }
    }

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        textDirection: pw.TextDirection.ltr,
        theme: pw.ThemeData.withFont(base: font, bold: fontBold),
        build: (context) => [
          _buildTopHeader(data),
          pw.SizedBox(height: 12),
          pw.Divider(color: PdfColors.grey400),
          pw.SizedBox(height: 12),
          _buildParties(data),
          pw.SizedBox(height: 14),
          _buildTable(data, imageWidgets),
          if (!data.hidePrices) ...[
            pw.SizedBox(height: 16),
            pw.Text(
              'Arrêtée la présente facture à la somme de: ${data.amountInWords}.',
              style: const pw.TextStyle(fontSize: 10),
            ),
            pw.SizedBox(height: 10),
            _buildTotals(data),
          ] else ...[
            pw.SizedBox(height: 16),
            _buildTotalQtyBlock(data),
          ],
        ],
      ),
    );

    return pdf.save();
  }"""

assert OLD_BUILD_PDF_BYTES in code, "buildPdfBytes method not found in pdf_invoice_api.dart"
code = code.replace(OLD_BUILD_PDF_BYTES, NEW_BUILD_PDF_BYTES, 1)

# Remove isolate class and function from the end of the file
ISOLATE_CODE = """

class _PdfIsolateParams {
  final DevisData data;
  final AppLanguage language;
  final Uint8List regularBytes;
  final Uint8List boldBytes;

  _PdfIsolateParams({
    required this.data,
    required this.language,
    required this.regularBytes,
    required this.boldBytes,
  });
}

Future<Uint8List> _buildPdfIsolate(_PdfIsolateParams params) async {
  PdfInvoiceApi._currentLang = params.language;
  final font = pw.Font.ttf(ByteData.sublistView(params.regularBytes));
  final fontBold = pw.Font.ttf(ByteData.sublistView(params.boldBytes));

  final pdf = pw.Document();

  final imageWidgets = <int, pw.MemoryImage>{};
  for (int i = 0; i < params.data.items.length; i++) {
    final path = params.data.items[i].imagePath;
    if (path != null && path.isNotEmpty) {
      try {
        final file = File(path);
        if (file.existsSync()) {
          imageWidgets[i] = pw.MemoryImage(file.readAsBytesSync());
        }
      } catch (_) {}
    }
  }

  pdf.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(28),
      textDirection: pw.TextDirection.ltr,
      theme: pw.ThemeData.withFont(base: font, bold: fontBold),
      build: (context) => [
        PdfInvoiceApi._buildTopHeader(params.data),
        pw.SizedBox(height: 12),
        pw.Divider(color: PdfColors.grey400),
        pw.SizedBox(height: 12),
        PdfInvoiceApi._buildParties(params.data),
        pw.SizedBox(height: 14),
        PdfInvoiceApi._buildTable(params.data, imageWidgets),
        if (!params.data.hidePrices) ...[
          pw.SizedBox(height: 16),
          pw.Text(
            'Arrêtée la présente facture à la somme de: ${params.data.amountInWords}.',
            style: const pw.TextStyle(fontSize: 10),
          ),
          pw.SizedBox(height: 10),
          PdfInvoiceApi._buildTotals(params.data),
        ] else ...[
          pw.SizedBox(height: 16),
          PdfInvoiceApi._buildTotalQtyBlock(params.data),
        ],
      ],
    ),
  );

  return pdf.save();
}"""

assert ISOLATE_CODE in code, "Isolate code block not found in pdf_invoice_api.dart"
code = code.replace(ISOLATE_CODE, "")

with open(path_pdf, 'w', encoding='utf-8') as f:
    f.write(code)
print("pdf_invoice_api.dart reverted to fast cached main thread PDF generation.")
