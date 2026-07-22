import re

def patch_pdf_invoice():
    path = 'lib/Commande/pdf_invoice_api.dart'
    with open(path, 'r', encoding='utf-8') as f:
        content = f.read()

    # Add imports if not present
    if "import 'package:erp_aluminum/arabic_reshaper/arabic_reshaper.dart';" not in content:
        content = content.replace("import 'package:pdf/widgets.dart' as pw;", "import 'package:pdf/widgets.dart' as pw;\nimport 'package:erp_aluminum/arabic_reshaper/arabic_reshaper.dart';")

    # Add helper methods if not present
    helpers = '''
  static bool _hasArabic(String text) {
    return text.runes.any((r) => r >= 0x0600 && r <= 0x06FF);
  }

  static String _reshapeArabic(String text) {
    if (!_hasArabic(text)) return text;
    final reshaped = ArabicReshaper.instance.reshape(text);
    return reshaped.split('').reversed.join('');
  }

  static pw.Widget _wrapWithCross(pw.Widget child, bool isReplaced) {
    if (!isReplaced) return child;
    return pw.Stack(
      fit: pw.StackFit.passthrough,
      children: [
        child,
        pw.Positioned.fill(
          child: pw.CustomPaint(
            painter: (pw.PdfGraphics canvas, pw.PdfPoint size) {
              canvas
                ..setColor(PdfColors.red)
                ..setLineWidth(1.5)
                ..drawLine(0, size.y / 2, size.x, size.y / 2)
                ..strokePath();
            },
          ),
        ),
      ],
    );
  }

  static pw.Widget _buildTable('''
    
    if "_reshapeArabic" not in content:
        content = content.replace("  static pw.Widget _buildTable(", helpers)

    # Now replace the items mapping in _buildTable
    # From: ...data.items.asMap().entries.map((entry) {
    # To: ...data.items.asMap().entries.expand((entry) { ... }).toList()
    
    old_map_start = "...data.items.asMap().entries.map((entry) {"
    
    # We'll use a regex to replace the entire map block
    # It ends with `        }),`
    
    pattern = r"\.\.\.data\.items\.asMap\(\)\.entries\.map\(\(entry\) \{.*?\n        \}\),"
    
    new_map = '''...data.items.asMap().entries.expand((entry) {
          final index = entry.key;
          final item = entry.value;
          final bg = index.isEven ? PdfColors.white : PdfColors.grey100;

          final mainRow = pw.TableRow(
            decoration: pw.BoxDecoration(color: bg),
            verticalAlignment: pw.TableCellVerticalAlignment.top,
            children: [
              _wrapWithCross(
                pw.Container(
                  padding: const pw.EdgeInsets.all(4),
                  height: 50,
                  alignment: pw.Alignment.center,
                  child: imageWidgets.containsKey(index)
                      ? pw.Image(imageWidgets[index]!, fit: pw.BoxFit.contain)
                      : pw.Text(
                          '-',
                          style: const pw.TextStyle(color: PdfColors.grey500),
                        ),
                ),
                item.isReplaced
              ),
              _wrapWithCross(
                pw.Container(
                  padding: const pw.EdgeInsets.all(6),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        _reshapeArabic(item.title),
                        textDirection: _hasArabic(item.title) ? pw.TextDirection.rtl : pw.TextDirection.ltr,
                        style: pw.TextStyle(
                          fontWeight: pw.FontWeight.bold,
                          fontSize: 10,
                          color: item.isReplaced ? PdfColors.red : null,
                        ),
                      ),
                      pw.SizedBox(height: 2),
                      ...item.details.map((detail) => pw.Text(
                            _reshapeArabic(detail),
                            textDirection: _hasArabic(detail) ? pw.TextDirection.rtl : pw.TextDirection.ltr,
                            style: const pw.TextStyle(
                              fontSize: 8.5,
                              color: PdfColors.grey800,
                            ),
                          )),
                    ],
                  ),
                ),
                item.isReplaced
              ),
              _wrapWithCross(
                pw.Container(
                  padding: const pw.EdgeInsets.all(6),
                  alignment: pw.Alignment.centerRight,
                  child: pw.Text(
                    _formatMoney(item.unitPrice),
                    style: pw.TextStyle(
                      fontSize: 9,
                      fontWeight: pw.FontWeight.bold,
                      color: item.isReplaced ? PdfColors.red : null,
                    ),
                  ),
                ),
                item.isReplaced
              ),
              _wrapWithCross(
                pw.Container(
                  padding: const pw.EdgeInsets.all(6),
                  alignment: pw.Alignment.centerRight,
                  child: pw.Text(
                    '${item.quantity}',
                    style: pw.TextStyle(
                      fontSize: 9,
                      color: item.isReplaced ? PdfColors.red : null,
                    ),
                  ),
                ),
                item.isReplaced
              ),
              _wrapWithCross(
                pw.Container(
                  padding: const pw.EdgeInsets.all(6),
                  alignment: pw.Alignment.centerRight,
                  child: pw.Text(
                    _formatMoney(item.unitPrice * item.quantity),
                    style: pw.TextStyle(
                      fontSize: 9,
                      fontWeight: pw.FontWeight.bold,
                      color: item.isReplaced ? PdfColors.red : null,
                    ),
                  ),
                ),
                item.isReplaced
              ),
            ],
          );

          if (item.isReplaced && item.replacementReason.isNotEmpty) {
            final reasonText = 'سبب التعديل: ${item.replacementReason}';
            final reasonRow = pw.TableRow(
              decoration: const pw.BoxDecoration(color: PdfColors.red50),
              children: [
                pw.Container(),
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  child: pw.Text(
                    _reshapeArabic(reasonText),
                    textDirection: _hasArabic(reasonText) ? pw.TextDirection.rtl : pw.TextDirection.ltr,
                    style: const pw.TextStyle(color: PdfColors.red900, fontSize: 9),
                  ),
                ),
                pw.Container(),
                pw.Container(),
                pw.Container(),
              ],
            );
            return [mainRow, reasonRow];
          }

          return [mainRow];
        }),'''
        
    content = re.sub(pattern, new_map, content, flags=re.DOTALL)
    
    with open(path, 'w', encoding='utf-8') as f:
        f.write(content)

if __name__ == '__main__':
    patch_pdf_invoice()
