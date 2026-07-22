import 'dart:convert';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'order_date_utils.dart';

class PdfFicheCoupeApi {
  static Future<void> generateAndPrintFicheCoupe({
    required Map<String, dynamic> order,
    required List<Map<String, dynamic>> items,
    required String workshopName,
  }) async {
    final pdf = pw.Document();
    final font = await PdfGoogleFonts.cairoRegular();
    final fontBold = await PdfGoogleFonts.cairoBold();
    final prefs = await SharedPreferences.getInstance();
    final logoBase64 = prefs.getString('workshop_logo_base64') ?? '';

    final activeItems = items.where((item) {
      try {
        final jsonRaw = item['partitions_json'];
        Map<String, dynamic> map = {};
        if (jsonRaw != null) {
          if (jsonRaw is Map<String, dynamic>) {
            map = jsonRaw;
          } else if (jsonRaw is Map) {
            map = Map<String, dynamic>.from(jsonRaw);
          } else {
            final str = jsonRaw.toString().trim();
            if (str.length >= 5) {
              map = jsonDecode(str) as Map<String, dynamic>;
            }
          }
        }
        final isReplaced = (map['isReplaced'] == true || map['isReplaced']?.toString().toLowerCase() == 'true') ||
            ((item['price'] as num?)?.toDouble() == 0.0);
        if (isReplaced) {
          return false;
        }
      } catch (_) {}
      return true;
    }).toList();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        textDirection: pw.TextDirection.rtl,
        theme: pw.ThemeData.withFont(base: font, bold: fontBold),
        build: (context) => [
          _buildHeader(order, workshopName, logoBase64),
          pw.SizedBox(height: 20),
          pw.Text(
            'ورقة التقطيع (Fiche de Coupe)',
            style: pw.TextStyle(
              fontSize: 20,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.red800,
            ),
          ),
          pw.SizedBox(height: 10),
          ...activeItems.map((item) => _buildItemCutList(item)),
        ],
      ),
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
      name: 'Fiche_Coupe_${order['id']}.pdf',
    );
  }

  static pw.Widget _buildHeader(
    Map<String, dynamic> order,
    String workshopName,
    String logoBase64,
  ) {
    pw.Widget? logoWidget;
    if (logoBase64.isNotEmpty) {
      try {
        final imageBytes = base64Decode(logoBase64);
        logoWidget = pw.Image(pw.MemoryImage(imageBytes), width: 50, height: 50);
      } catch (_) {}
    }

    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            if (logoWidget != null) ...[
              logoWidget,
              pw.SizedBox(width: 12),
            ],
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  workshopName,
                  style: pw.TextStyle(
                    fontSize: 24,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.blue,
                  ),
                ),
                pw.SizedBox(height: 1 * PdfPageFormat.mm),
                pw.Text(
                  'قسم التصنيع - Atelier',
                  style: const pw.TextStyle(fontSize: 16),
                ),
              ],
            ),
          ],
        ),
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Text(
              'العميل: ${order['firstname'] ?? ''} ${order['lastname'] ?? ''}',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            ),
            pw.Text('رقم الطلبية: ${order['id']}'),
            pw.Text(
              'التاريخ: ${formatOrderDate(order['created_at'], fallback: order['updated_at'], emptyLabel: 'غير محدد')}',
            ),
          ],
        ),
      ],
    );
  }

  static pw.Widget _buildItemCutList(Map<String, dynamic> item) {
    final String type = item['window_type'] ?? 'نافذة';
    final double width = item['largeur']?.toDouble() ?? 0.0;
    final double height = item['hauteur']?.toDouble() ?? 0.0;
    final int qty = item['quantity'] ?? 1;

    // --- Mock Cutting Logic for Demonstration ---
    // In the future, this should be replaced with exact mathematical deductions based on the specific System/Profile used.
    final double frameCutWidth = width;
    final double frameCutHeight = height;

    // Sash is usually half the width minus some overlap/clearance, and height minus rails.
    // This is a generic estimation just to show the format.
    final double sashCutWidth = (width / 2) + 20;
    final double sashCutHeight = height - 60;

    final headers = ['القطاع (Profile)', 'نوع القطع', 'الكمية', 'الطول (ملم)'];

    final data = [
      [
        'إطار علوي/سفلي (Cadre)',
        '45° / 45°',
        '${2 * qty}',
        '${frameCutWidth.toInt()}',
      ],
      [
        'إطار يمين/يسار (Cadre)',
        '45° / 45°',
        '${2 * qty}',
        '${frameCutHeight.toInt()}',
      ],
      [
        'ضلفة أفقية (Ouvrant)',
        '45° / 45°',
        '${4 * qty}',
        '${sashCutWidth.toInt()}',
      ],
      [
        'ضلفة عمودية (Ouvrant)',
        '45° / 45°',
        '${4 * qty}',
        '${sashCutHeight.toInt()}',
      ],
      if (item['volet'] == 'Yes')
        [
          'شفرات الستار (Lames)',
          '90° / 90°',
          'حسب الطول',
          '${(width - 50).toInt()}',
        ],
    ];

    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 20),
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey400),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(5)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'المنتج: $type | الأبعاد الأصلية: $width x $height | العدد: $qty',
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 14),
          ),
          pw.SizedBox(height: 10),
          pw.TableHelper.fromTextArray(
            headers: headers,
            data: data,
            border: pw.TableBorder.all(color: PdfColors.grey300),
            headerStyle: pw.TextStyle(
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.white,
            ),
            headerDecoration: const pw.BoxDecoration(
              color: PdfColors.blueGrey600,
            ),
            cellHeight: 25,
            cellAlignments: {
              0: pw.Alignment.centerRight,
              1: pw.Alignment.center,
              2: pw.Alignment.center,
              3: pw.Alignment.center,
            },
          ),
          pw.SizedBox(height: 10),
          pw.Text(
            'الأكسسوارات:',
            style: pw.TextStyle(
              fontWeight: pw.FontWeight.bold,
              decoration: pw.TextDecoration.underline,
            ),
          ),
          pw.Text(
            '- عجلات سحاب: ${4 * qty} حبة\n- أقفال: ${1 * qty} حبة\n- زوايا تجميع 45°: ${8 * qty} حبة',
            style: const pw.TextStyle(color: PdfColors.grey700),
          ),
        ],
      ),
    );
  }
}
