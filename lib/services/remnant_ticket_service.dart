import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'pdf_font_cache.dart';

class RemnantTicketService {
  static String _value(Map<String, dynamic> row, String key) =>
      row[key]?.toString().trim() ?? '';

  static String storageAddress(Map<String, dynamic> row) {
    final parts = <String>[
      _value(row, 'location_name'),
      if (_value(row, 'rack_code').isNotEmpty)
        'الرف: ${_value(row, 'rack_code')}',
      if (_value(row, 'shelf_code').isNotEmpty)
        'المستوى: ${_value(row, 'shelf_code')}',
      if (_value(row, 'bin_code').isNotEmpty)
        'الصندوق: ${_value(row, 'bin_code')}',
    ].where((part) => part.isNotEmpty).toList();
    return parts.isEmpty ? 'الموقع غير محدد' : parts.join(' • ');
  }

  static Future<void> printTickets(List<Map<String, dynamic>> rows) async {
    if (rows.isEmpty) return;
    final fonts = await PdfFontCache.load();
    final regular = fonts.regular;
    final bold = fonts.bold;
    final document = pw.Document();

    for (final row in rows) {
      final ticket = _value(row, 'ticket_code');
      final code = _value(row, 'item_code');
      final item = _value(row, 'item_name');
      final color = _value(row, 'color_name');
      final series = _value(row, 'series_name');
      final length = (row['length_mm'] as num?)?.round() ?? 0;
      final order = _value(row, 'source_order_id');
      document.addPage(
        pw.Page(
          pageFormat: const PdfPageFormat(
            70 * PdfPageFormat.mm,
            45 * PdfPageFormat.mm,
            marginAll: 2 * PdfPageFormat.mm,
          ),
          theme: pw.ThemeData.withFont(base: regular, bold: bold),
          textDirection: pw.TextDirection.rtl,
          build: (_) => pw.Container(
            padding: const pw.EdgeInsets.all(4),
            decoration: pw.BoxDecoration(border: pw.Border.all(width: 0.8)),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                      'قطعة متبقية',
                      style: pw.TextStyle(
                        fontSize: 11,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.Text(
                      '$length مم',
                      style: pw.TextStyle(
                        fontSize: 14,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                pw.Text(
                  [
                    if (code.isNotEmpty) '[$code]',
                    item,
                  ].where((value) => value.isNotEmpty).join(' '),
                  style: pw.TextStyle(
                    fontSize: 8,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.Text(
                  [
                    if (series.isNotEmpty) 'السلسلة: $series',
                    if (color.isNotEmpty) 'اللون: $color',
                  ].join(' • '),
                  style: const pw.TextStyle(fontSize: 7),
                ),
                pw.Text(
                  storageAddress(row),
                  style: pw.TextStyle(
                    fontSize: 7,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.Text(
                  'المصدر: الطلبية #$order',
                  style: const pw.TextStyle(fontSize: 6.5),
                ),
                pw.SizedBox(
                  height: 12,
                  child: pw.BarcodeWidget(
                    barcode: pw.Barcode.code128(),
                    data: ticket,
                    drawText: true,
                    textStyle: const pw.TextStyle(fontSize: 5),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    await Printing.layoutPdf(
      onLayout: (_) => document.save(),
      name: 'remnant-tickets.pdf',
      format: const PdfPageFormat(70 * PdfPageFormat.mm, 45 * PdfPageFormat.mm),
      dynamicLayout: false,
      usePrinterSettings: true,
    );
  }
}
