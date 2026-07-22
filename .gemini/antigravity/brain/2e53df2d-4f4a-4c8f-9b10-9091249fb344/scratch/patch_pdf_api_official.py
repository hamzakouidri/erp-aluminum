import re

path_pdf = r'c:\Users\hp\Desktop\Noraleur\erp-aluminum-main\lib\Commande\pdf_invoice_api.dart'

with open(path_pdf, 'r', encoding='utf-8') as f:
    code = f.read()

# 1. Update _buildTopHeader titleKey in pdf_invoice_api.dart
OLD_TOP_HEADER = """  static pw.Widget _buildTopHeader(DevisData data) {
    final titleKey = data.isPartial ? 'DEVIS_PARTIAL' : 'DEVIS';"""

NEW_TOP_HEADER = """  static pw.Widget _buildTopHeader(DevisData data) {
    final titleKey = data.isProForma
        ? 'فاتورة رسمية / أولية'
        : (data.isPartial ? 'DEVIS_PARTIAL' : 'DEVIS');"""

assert OLD_TOP_HEADER in code, "_buildTopHeader not found in pdf_invoice_api.dart"
code = code.replace(OLD_TOP_HEADER, NEW_TOP_HEADER, 1)

# 2. Update _buildParties to include official supplier fields in pdf_invoice_api.dart
OLD_PARTIES_PDF = """  static pw.Widget _buildParties(DevisData data) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Expanded(
          child: _partyBlock(_ar(t('FOURNISSEUR')), [
            data.workshop.name,
            if (data.workshop.phone.isNotEmpty) data.workshop.phone,
            if (data.workshop.address.isNotEmpty) data.workshop.address,
          ]),
        ),"""

NEW_PARTIES_PDF = """  static pw.Widget _buildParties(DevisData data) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Expanded(
          child: _partyBlock(_ar(t('FOURNISSEUR')), [
            data.workshop.name,
            if (data.workshop.phone.isNotEmpty) data.workshop.phone,
            if (data.workshop.address.isNotEmpty) data.workshop.address,
            if (data.isProForma) ...[
              if (data.workshop.rc.isNotEmpty) 'RC: ${data.workshop.rc}',
              if (data.workshop.nif.isNotEmpty) 'NIF: ${data.workshop.nif}',
              if (data.workshop.nis.isNotEmpty) 'NIS: ${data.workshop.nis}',
              if (data.workshop.ai.isNotEmpty) 'AI: ${data.workshop.ai}',
              if (data.workshop.rib.isNotEmpty) 'RIB: ${data.workshop.rib}',
            ],
          ]),
        ),"""

assert OLD_PARTIES_PDF in code, "_buildParties not found in pdf_invoice_api.dart"
code = code.replace(OLD_PARTIES_PDF, NEW_PARTIES_PDF, 1)

# 3. Update _tableHeader signature and layout in pdf_invoice_api.dart
OLD_TABLE_HEADER_PDF = """  /// صف رأس الجدول
  static pw.Widget _tableHeader(bool hidePrices) {
    pw.Widget hCell(
      double w,
      String text, {
      pw.Alignment align = pw.Alignment.centerLeft,
    }) => pw.Container(
      width: w,
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      alignment: align,
      decoration: pw.BoxDecoration(
        color: _blue,
        border: pw.Border.all(color: PdfColors.grey300, width: 0.5),
      ),
      child: pw.Text(
        _ar(text),
        textDirection: _dir(text),
        style: pw.TextStyle(
          color: PdfColors.white,
          fontWeight: pw.FontWeight.bold,
          fontSize: 9,
        ),
      ),
    );
    return pw.Row(
      children: [
        hCell(_col0w, t('Image')),
        hCell(hidePrices ? (_tableW - _col0w - _col3w) : _col1w, t('Désignation')),
        if (!hidePrices)
          hCell(_col2w, t('Prix Unit.'), align: pw.Alignment.centerRight),
        hCell(_col3w, t('Qté'), align: pw.Alignment.centerRight),
        if (!hidePrices)
          hCell(_col4w, t('Total'), align: pw.Alignment.centerRight),
      ],
    );
  }"""

NEW_TABLE_HEADER_PDF = """  /// صف رأس الجدول
  static pw.Widget _tableHeader(bool hidePrices, bool isProForma) {
    pw.Widget hCell(
      double w,
      String text, {
      pw.Alignment align = pw.Alignment.centerLeft,
    }) => pw.Container(
      width: w,
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      alignment: align,
      decoration: pw.BoxDecoration(
        color: _blue,
        border: pw.Border.all(color: PdfColors.grey300, width: 0.5),
      ),
      child: pw.Text(
        _ar(text),
        textDirection: _dir(text),
        style: pw.TextStyle(
          color: PdfColors.white,
          fontWeight: pw.FontWeight.bold,
          fontSize: 9,
        ),
      ),
    );
    return pw.Row(
      children: [
        if (!isProForma) hCell(_col0w, t('Image')),
        hCell(isProForma
            ? (hidePrices ? _tableW : (_tableW - _col2w - _col3w - _col4w))
            : (hidePrices ? (_tableW - _col0w - _col3w) : _col1w), t('Désignation')),
        if (!hidePrices)
          hCell(_col2w, t('Prix Unit.'), align: pw.Alignment.centerRight),
        hCell(_col3w, t('Qté'), align: pw.Alignment.centerRight),
        if (!hidePrices)
          hCell(_col4w, t('Total'), align: pw.Alignment.centerRight),
      ],
    );
  }"""

assert OLD_TABLE_HEADER_PDF in code, "_tableHeader not found in pdf_invoice_api.dart"
code = code.replace(OLD_TABLE_HEADER_PDF, NEW_TABLE_HEADER_PDF, 1)

# 4. Update _dataRow signature and layout in pdf_invoice_api.dart
OLD_DATA_ROW_PDF = """  /// بناء صف بيانات — إذا كان مشطوباً يُلف بـ Stack لرسم X على كامل الصف
  static pw.Widget _dataRow({
    required DevisLineItem item,
    required int index,
    required pw.MemoryImage? image,
    required bool hidePrices,
  }) {
    final PdfColor bg = index.isEven ? PdfColors.white : PdfColors.grey100;
    final PdfColor? txtColor = item.isReplaced ? PdfColors.red : null;

    final pw.Widget rowContent = pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        // عمود 0: الصورة
        _cell(
          _col0w,
          image != null
              ? pw.Image(image, fit: pw.BoxFit.contain)
              : pw.Text(
                  '-',
                  style: const pw.TextStyle(color: PdfColors.grey500),
                ),
          alignment: pw.Alignment.center,
          bg: bg,
          padding: const pw.EdgeInsets.all(4),
        ),
        // عمود 1: الاسم والتفاصيل
        _cell(
          hidePrices ? (_tableW - _col0w - _col3w) : _col1w,
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                _ar(item.title),
                textDirection: _dir(item.title),
                style: pw.TextStyle(
                  fontWeight: pw.FontWeight.bold,
                  fontSize: 10,
                  color: txtColor,
                ),
              ),
              pw.SizedBox(height: 2),
              ...item.details.map(
                (d) => pw.Text(
                  _ar(d),
                  textDirection: _dir(d),
                  style: const pw.TextStyle(
                    fontSize: 8.5,
                    color: PdfColors.grey800,
                  ),
                ),
              ),
            ],
          ),
          bg: bg,
        ),"""

NEW_DATA_ROW_PDF = """  /// بناء صف بيانات — إذا كان مشطوباً يُلف بـ Stack لرسم X على كامل الصف
  static pw.Widget _dataRow({
    required DevisLineItem item,
    required int index,
    required pw.MemoryImage? image,
    required bool hidePrices,
    required bool isProForma,
  }) {
    final PdfColor bg = index.isEven ? PdfColors.white : PdfColors.grey100;
    final PdfColor? txtColor = item.isReplaced ? PdfColors.red : null;

    final displayDetails = isProForma
        ? item.details.where((line) {
            final lower = line.toLowerCase();
            return lower.contains('largeur') ||
                lower.contains('width') ||
                lower.contains('العرض') ||
                lower.contains('الارتفاع') ||
                lower.contains('hauteur') ||
                lower.contains('height');
          }).toList()
        : item.details;

    final pw.Widget rowContent = pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        // عمود 0: الصورة
        if (!isProForma)
          _cell(
            _col0w,
            image != null
                ? pw.Image(image, fit: pw.BoxFit.contain)
                : pw.Text(
                    '-',
                    style: const pw.TextStyle(color: PdfColors.grey500),
                  ),
            alignment: pw.Alignment.center,
            bg: bg,
            padding: const pw.EdgeInsets.all(4),
          ),
        // عمود 1: الاسم والتفاصيل
        _cell(
          isProForma
              ? (hidePrices ? _tableW : (_tableW - _col2w - _col3w - _col4w))
              : (hidePrices ? (_tableW - _col0w - _col3w) : _col1w),
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                _ar(item.title),
                textDirection: _dir(item.title),
                style: pw.TextStyle(
                  fontWeight: pw.FontWeight.bold,
                  fontSize: 10,
                  color: txtColor,
                ),
              ),
              pw.SizedBox(height: 2),
              ...displayDetails.map(
                (d) => pw.Text(
                  _ar(d),
                  textDirection: _dir(d),
                  style: const pw.TextStyle(
                    fontSize: 8.5,
                    color: PdfColors.grey800,
                  ),
                ),
              ),
            ],
          ),
          bg: bg,
        ),"""

assert OLD_DATA_ROW_PDF in code, "_dataRow not found in pdf_invoice_api.dart"
code = code.replace(OLD_DATA_ROW_PDF, NEW_DATA_ROW_PDF, 1)

# 5. Update _buildTable inside pdf_invoice_api.dart
OLD_BUILD_TABLE_PDF = """  static pw.Widget _buildTable(
    DevisData data,
    Map<int, pw.MemoryImage> imageWidgets,
  ) {
    final bool hidePrices = data.hidePrices;
    final List<pw.Widget> rows = [_tableHeader(hidePrices)];

    for (var entry in data.items.asMap().entries) {
      final index = entry.key;
      final item = entry.value;

      rows.add(_dataRow(item: item, index: index, image: imageWidgets[index], hidePrices: hidePrices));"""

NEW_BUILD_TABLE_PDF = """  static pw.Widget _buildTable(
    DevisData data,
    Map<int, pw.MemoryImage> imageWidgets,
  ) {
    final bool hidePrices = data.hidePrices;
    final List<pw.Widget> rows = [_tableHeader(hidePrices, data.isProForma)];

    for (var entry in data.items.asMap().entries) {
      final index = entry.key;
      final item = entry.value;

      rows.add(_dataRow(item: item, index: index, image: imageWidgets[index], hidePrices: hidePrices, isProForma: data.isProForma));"""

assert OLD_BUILD_TABLE_PDF in code, "_buildTable not found in pdf_invoice_api.dart"
code = code.replace(OLD_BUILD_TABLE_PDF, NEW_BUILD_TABLE_PDF, 1)

with open(path_pdf, 'w', encoding='utf-8') as f:
    f.write(code)
print("pdf_invoice_api.dart updated successfully.")
