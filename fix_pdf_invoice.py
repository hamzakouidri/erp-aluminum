import re

def fix_pdf_invoice():
    path = 'lib/Commande/pdf_invoice_api.dart'
    with open(path, 'r', encoding='utf-8') as f:
        content = f.read()

    # We want to replace _wrapWithCross to use a horizontal strike-through
    wrap_pattern = re.compile(r"  static pw\.Widget _wrapWithCross\(pw\.Widget child, bool isReplaced\) \{.*?  \}", re.DOTALL)
    wrap_replacement = '''  static pw.Widget _wrapWithCross(pw.Widget child, bool isReplaced) {
    if (!isReplaced) return child;
    return pw.Stack(
      children: [
        child,
        pw.Positioned.fill(
          child: pw.CustomPaint(
            painter: (PdfGraphics canvas, PdfPoint size) {
              canvas
                ..setLineWidth(1.5)
                ..setStrokeColor(PdfColors.red)
                ..drawLine(0, size.y / 2, size.x, size.y / 2)
                ..strokePath();
            },
          ),
        ),
      ],
    );
  }'''
    content = wrap_pattern.sub(wrap_replacement, content)

    # We want to replace _buildTableWidgets to use pw.Table
    table_pattern = re.compile(r"  static List<pw\.Widget> _buildTableWidgets\(.*?return widgets;\n  \}", re.DOTALL)
    table_replacement = '''  static List<pw.Widget> _buildTableWidgets(
    DevisData data,
    Map<int, pw.MemoryImage> imageWidgets,
  ) {
    final rows = <pw.TableRow>[];

    // 1. Header Row
    rows.add(
      pw.TableRow(
        decoration: const pw.BoxDecoration(
          color: _blue,
        ),
        children: [
          _headerCell('الصورة', align: pw.Alignment.center),
          _headerCell('البيان'),
          _headerCell('س.الوحدة', align: pw.Alignment.centerRight),
          _headerCell('الكمية', align: pw.Alignment.centerRight),
          _headerCell('المجموع', align: pw.Alignment.centerRight),
        ],
      ),
    );

    // 2. Item Rows
    for (int index = 0; index < data.items.length; index++) {
      final item = data.items[index];
      final bg = index.isEven ? PdfColors.white : PdfColors.grey100;
      final textColor = item.isReplaced ? PdfColors.grey500 : PdfColors.black;
      final detailColor = item.isReplaced ? PdfColors.grey400 : PdfColors.grey800;

      rows.add(
        pw.TableRow(
          decoration: pw.BoxDecoration(
            color: bg,
          ),
          children: [
            // Image
            _wrapWithCross(
              pw.Container(
                padding: const pw.EdgeInsets.all(4),
                alignment: pw.Alignment.center,
                child: imageWidgets.containsKey(index)
                    ? pw.Image(imageWidgets[index]!, fit: pw.BoxFit.contain)
                    : pw.Text('—', style: const pw.TextStyle(color: PdfColors.grey500)),
              ),
              item.isReplaced,
            ),
            // Details
            _wrapWithCross(
              pw.Container(
                padding: const pw.EdgeInsets.all(6),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      _reshapeArabic(item.title),
                      style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10, color: textColor),
                      textDirection: _hasArabic(item.title) ? pw.TextDirection.rtl : pw.TextDirection.ltr,
                    ),
                    pw.SizedBox(height: 3),
                    ...item.details.map(
                      (d) => pw.Text(
                        _reshapeArabic(d),
                        style: pw.TextStyle(fontSize: 8.5, color: detailColor),
                        textDirection: _hasArabic(d) ? pw.TextDirection.rtl : pw.TextDirection.ltr,
                      ),
                    ),
                  ],
                ),
              ),
              item.isReplaced,
            ),
            // Unit Price
            _wrapWithCross(
              pw.Container(
                padding: const pw.EdgeInsets.all(6),
                alignment: pw.Alignment.centerRight,
                child: pw.Text(
                  '${_formatMoney(item.unitPrice)} D.A',
                  style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: textColor),
                ),
              ),
              item.isReplaced,
            ),
            // Quantity
            _wrapWithCross(
              pw.Container(
                padding: const pw.EdgeInsets.all(6),
                alignment: pw.Alignment.centerRight,
                child: pw.Text('${item.quantity}', style: pw.TextStyle(fontSize: 9, color: textColor)),
              ),
              item.isReplaced,
            ),
            // Total
            _wrapWithCross(
              pw.Container(
                padding: const pw.EdgeInsets.all(6),
                alignment: pw.Alignment.centerRight,
                child: pw.Text(
                  '${_formatMoney(item.unitPrice * item.quantity)} D.A',
                  style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: textColor),
                ),
              ),
              item.isReplaced,
            ),
          ],
        ),
      );

      // 3. Reason Row
      if (item.isReplaced && item.replacementReason.isNotEmpty) {
        rows.add(
          pw.TableRow(
            decoration: const pw.BoxDecoration(color: PdfColors.white),
            children: [
              pw.SizedBox.shrink(), // Empty cell for image column
              pw.Container(
                padding: const pw.EdgeInsets.only(left: 6, right: 6, bottom: 6, top: 4),
                child: pw.Container(
                  padding: const pw.EdgeInsets.all(4),
                  decoration: const pw.BoxDecoration(
                    color: PdfColors.amber50,
                    border: pw.Border(right: pw.BorderSide(color: PdfColors.amber700, width: 2)),
                  ),
                  child: pw.Text(
                    _reshapeArabic('سبب التعديل: ${item.replacementReason}'),
                    style: pw.TextStyle(fontSize: 8, color: PdfColors.amber900),
                    textDirection: pw.TextDirection.rtl,
                  ),
                ),
              ),
              pw.SizedBox.shrink(),
              pw.SizedBox.shrink(),
              pw.SizedBox.shrink(),
            ],
          ),
        );
      }
    }

    final table = pw.Table(
      columnWidths: {
        0: const pw.FixedColumnWidth(50),
        1: const pw.FlexColumnWidth(40),
        2: const pw.FlexColumnWidth(15),
        3: const pw.FixedColumnWidth(32),
        4: const pw.FlexColumnWidth(16),
      },
      border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
      children: rows,
    );

    return [table];
  }'''
    content = table_pattern.sub(table_replacement, content)

    with open(path, 'w', encoding='utf-8') as f:
        f.write(content)

if __name__ == '__main__':
    fix_pdf_invoice()
