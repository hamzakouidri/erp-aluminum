import 'dart:convert';
import 'dart:typed_data';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:database_data/services/pdf_branding.dart';
import 'package:printing/printing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/pdf_font_cache.dart';

/// PDF generation service for the Material Sales module.
/// Supports all document types: bon_livraison, bon_commande, facture,
/// bon_route, devis — with Arabic/French bilingual labels.
class MaterialSalePdfService {
  // ---------------------------------------------------------------------------
  // Constants
  // ---------------------------------------------------------------------------

  static const PdfColor _primaryColor = PdfColor.fromInt(0xFF1E3A8A);
  static final PdfColor _lightBg = PdfColor.fromHex('#EFF6FF');
  static final PdfColor _rowAlt = PdfColor.fromHex('#F8FAFC');
  static final PdfColor _white = PdfColors.white;
  static final PdfColor _grey = PdfColor.fromHex('#64748B');
  static final PdfColor _dark = PdfColor.fromHex('#1E293B');

  static final NumberFormat _numFmt = NumberFormat('#,##0.00');

  /// Maps doc_type codes to their bilingual display title.
  static const Map<String, String> _docTitles = {
    'bon_livraison': 'BON DE LIVRAISON MATÉRIAUX / وصل تسليم مواد',
    'bon_commande': 'COMMANDE MATÉRIAUX / طلب مواد',
    'facture': 'FACTURE MATÉRIAUX / فاتورة مواد',
    'bon_route': 'BON DE ROUTE MATÉRIAUX / وصل طريق المواد',
    'devis': 'PROFORMA MATÉRIAUX / فاتورة أولية للمواد',
  };

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Generates a PDF document for a material sale and returns its raw bytes.
  ///
  /// [sale]          – Map containing all sale-level fields.
  /// [items]         – List of line-item maps.
  /// [workshopName]  – Override for workshop name (loaded from prefs if empty).
  /// [logoBase64]    – Override for logo (loaded from prefs if empty).
  static Future<Uint8List> generate({
    required Map<String, dynamic> sale,
    required List<Map<String, dynamic>> items,
    String workshopName = '',
    String logoBase64 = '',
  }) async {
    // ── Fonts ────────────────────────────────────────────────────────────────
    final fonts = await PdfFontCache.load();
    final pw.Font regular = fonts.regular;
    final pw.Font bold = fonts.bold;

    // ── Prefs fallback ───────────────────────────────────────────────────────
    if (workshopName.isEmpty || logoBase64.isEmpty) {
      final prefs = await SharedPreferences.getInstance();
      if (workshopName.isEmpty) {
        workshopName = prefs.getString('workshop_name') ?? '';
      }
      if (logoBase64.isEmpty) {
        logoBase64 = prefs.getString('workshop_logo') ?? '';
      }
    }

    // ── Sale fields ──────────────────────────────────────────────────────────
    final String saleCode = _s(sale['sale_code']);
    final String clientName = _s(sale['client_name']);
    final String clientPhone = _s(sale['client_phone']);
    final String docType = _s(sale['doc_type']);
    final String status = _s(sale['status']);
    final String notes = _s(sale['notes']);
    final String saleDate = _formatDate(_s(sale['sale_date']));

    final double subtotal = _d(sale['subtotal']);
    final double discountAmount = _d(sale['discount_amount']);
    final double netTotal = _d(sale['net_total']);
    final double paidAmount = _d(sale['paid_amount']);
    final double remainingAmount = _d(sale['remaining_amount']);

    final String docTitle =
        _docTitles[docType] ?? 'DOCUMENT DE VENTE / وثيقة بيع';

    // ── Logo image ───────────────────────────────────────────────────────────
    pw.ImageProvider? logoImage;
    if (logoBase64.isNotEmpty) {
      try {
        final Uint8List logoBytes = base64Decode(logoBase64);
        logoImage = pw.MemoryImage(logoBytes);
      } catch (_) {
        logoImage = null;
      }
    }

    // ── Build PDF ────────────────────────────────────────────────────────────
    final pdf = pw.Document(
      theme: pw.ThemeData.withFont(base: regular, bold: bold),
    );

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.symmetric(horizontal: 32, vertical: 28),
        footer: (context) => _buildFooter(context, regular),
        build: (context) => [
          // ── Header ──────────────────────────────────────────────────────
          _buildHeader(
            workshopName: workshopName,
            docTitle: docTitle,
            logoImage: logoImage,
            bold: bold,
            regular: regular,
          ),
          pw.SizedBox(height: 12),

          // ── Info row ─────────────────────────────────────────────────────
          _buildInfoRow(
            saleCode: saleCode,
            saleDate: saleDate,
            clientName: clientName,
            clientPhone: clientPhone,
            status: status,
            bold: bold,
            regular: regular,
          ),
          pw.SizedBox(height: 14),

          // ── Items table ──────────────────────────────────────────────────
          _buildItemsTable(items, bold: bold, regular: regular),
          pw.SizedBox(height: 14),

          // ── Totals ───────────────────────────────────────────────────────
          _buildTotals(
            subtotal: subtotal,
            discountAmount: discountAmount,
            netTotal: netTotal,
            paidAmount: paidAmount,
            remainingAmount: remainingAmount,
            bold: bold,
            regular: regular,
          ),
          pw.SizedBox(height: 18),

          // ── Notes ────────────────────────────────────────────────────────
          if (notes.isNotEmpty) ...[
            _buildNotes(notes, bold: bold, regular: regular),
            pw.SizedBox(height: 14),
          ],

          // ── Signatures ───────────────────────────────────────────────────
          _buildSignatures(bold: bold, regular: regular),
        ],
      ),
    );

    return pdf.save();
  }

  /// Opens the system print / share dialog for the given PDF bytes.
  static Future<void> printOrShare(Uint8List bytes, String filename) async {
    await Printing.layoutPdf(
      name: filename,
      onLayout: (_) async => bytes,
    );
  }

  // ---------------------------------------------------------------------------
  // Private builders
  // ---------------------------------------------------------------------------

  /// Workshop logo + name + document title banner.
  static pw.Widget _buildHeader({
    required String workshopName,
    required String docTitle,
    required pw.ImageProvider? logoImage,
    required pw.Font bold,
    required pw.Font regular,
  }) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        // Logo (if available)
        if (logoImage != null) ...[
          pw.Image(logoImage, height: 60, fit: pw.BoxFit.contain),
          pw.SizedBox(height: 6),
        ],

        // Workshop name
        if (workshopName.isNotEmpty)
          pw.Text(
            workshopName,
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(
              font: bold,
              fontSize: 20,
              color: _dark,
            ),
          ),

        pw.SizedBox(height: 6),

        // Divider line
        pw.Container(
          height: 2,
          color: _primaryColor,
        ),
        pw.SizedBox(height: 6),

        // Document title
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          decoration: pw.BoxDecoration(
            color: _primaryColor,
            borderRadius: pw.BorderRadius.circular(4),
          ),
          child: pw.Text(
            docTitle,
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(
              font: bold,
              fontSize: 13,
              color: _white,
            ),
          ),
        ),
      ],
    );
  }

  /// Two-column row: doc reference / date on left, client info on right.
  static pw.Widget _buildInfoRow({
    required String saleCode,
    required String saleDate,
    required String clientName,
    required String clientPhone,
    required String status,
    required pw.Font bold,
    required pw.Font regular,
  }) {
    return pw.Container(
      decoration: pw.BoxDecoration(
        color: _lightBg,
        borderRadius: pw.BorderRadius.circular(6),
        border: pw.Border.all(color: _primaryColor, width: 0.5),
      ),
      padding: const pw.EdgeInsets.all(10),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          // Left column – document reference
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                _infoLine(
                  label: 'N° Document / رقم الوثيقة',
                  value: saleCode,
                  bold: bold,
                  regular: regular,
                ),
                pw.SizedBox(height: 4),
                _infoLine(
                  label: 'Date / التاريخ',
                  value: saleDate,
                  bold: bold,
                  regular: regular,
                ),
                pw.SizedBox(height: 4),
                _infoLine(
                  label: 'Statut / الحالة',
                  value: _translateStatus(status),
                  bold: bold,
                  regular: regular,
                ),
              ],
            ),
          ),

          // Vertical divider
          pw.Container(width: 1, height: 60, color: _primaryColor),
          pw.SizedBox(width: 10),

          // Right column – client
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                _infoLine(
                  label: 'Client / العميل',
                  value: clientName,
                  bold: bold,
                  regular: regular,
                ),
                pw.SizedBox(height: 4),
                _infoLine(
                  label: 'Téléphone / الهاتف',
                  value: clientPhone.isNotEmpty ? clientPhone : '—',
                  bold: bold,
                  regular: regular,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Items table with alternating row colours.
  static pw.Widget _buildItemsTable(
    List<Map<String, dynamic>> items, {
    required pw.Font bold,
    required pw.Font regular,
  }) {
    // Column headers: # | Désignation | Couleur | Unité | Qté | Prix Unit. | Total
    final headers = [
      '#',
      'Désignation\nالبيان',
      'Couleur\nاللون',
      'Unité\nالوحدة',
      'Qté\nالكمية',
      'Prix Unit.\nسعر الوحدة',
      'Total\nالمجموع',
    ];

    final columnWidths = {
      0: const pw.FlexColumnWidth(0.5),
      1: const pw.FlexColumnWidth(2.8),
      2: const pw.FlexColumnWidth(1.2),
      3: const pw.FlexColumnWidth(0.9),
      4: const pw.FlexColumnWidth(0.8),
      5: const pw.FlexColumnWidth(1.3),
      6: const pw.FlexColumnWidth(1.3),
    };

    return pw.Table(
      columnWidths: columnWidths,
      border: pw.TableBorder(
        left: pw.BorderSide(color: _primaryColor, width: 0.5),
        right: pw.BorderSide(color: _primaryColor, width: 0.5),
        top: pw.BorderSide(color: _primaryColor, width: 0.5),
        bottom: pw.BorderSide(color: _primaryColor, width: 0.5),
        horizontalInside: pw.BorderSide(color: _grey, width: 0.3),
        verticalInside: pw.BorderSide(color: _grey, width: 0.3),
      ),
      children: [
        // Header row
        pw.TableRow(
          decoration: pw.BoxDecoration(color: _primaryColor),
          children: headers
              .map(
                (h) => pw.Padding(
                  padding:
                      const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 5),
                  child: pw.Text(
                    h,
                    textAlign: pw.TextAlign.center,
                    style: pw.TextStyle(
                      font: bold,
                      fontSize: 8,
                      color: _white,
                    ),
                  ),
                ),
              )
              .toList(),
        ),

        // Data rows
        ...List.generate(items.length, (index) {
          final item = items[index];
          final isAlt = index % 2 == 1;

          final String designation = _buildDesignation(item);
          final String color = _s(item['color_name']);
          final String unit = _s(item['unit']);
          final double qty = _d(item['quantity']);
          final double unitPrice = _d(item['unit_price']);
          final double total = _d(item['total_price']);

          return pw.TableRow(
            decoration:
                pw.BoxDecoration(color: isAlt ? _rowAlt : _white),
            children: [
              _tableCell('${index + 1}', regular, align: pw.TextAlign.center),
              _tableCell(designation, regular,
                  align: pw.TextAlign.left, fontSize: 8),
              _tableCell(color.isNotEmpty ? color : '—', regular,
                  align: pw.TextAlign.center),
              _tableCell(unit, regular, align: pw.TextAlign.center),
              _tableCell(_numFmt.format(qty), regular,
                  align: pw.TextAlign.center),
              _tableCell('${_numFmt.format(unitPrice)} DA', regular,
                  align: pw.TextAlign.right),
              _tableCell('${_numFmt.format(total)} DA', bold,
                  align: pw.TextAlign.right),
            ],
          );
        }),
      ],
    );
  }

  /// Right-aligned totals block.
  static pw.Widget _buildTotals({
    required double subtotal,
    required double discountAmount,
    required double netTotal,
    required double paidAmount,
    required double remainingAmount,
    required pw.Font bold,
    required pw.Font regular,
  }) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.end,
      children: [
        pw.Container(
          width: 260,
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: _primaryColor, width: 0.5),
            borderRadius: pw.BorderRadius.circular(6),
          ),
          child: pw.Column(
            children: [
              _totalRow(
                label: 'Sous-total / المجموع الفرعي',
                value: '${_numFmt.format(subtotal)} DA',
                bold: bold,
                regular: regular,
              ),
              pw.Divider(height: 1, color: _grey),
              _totalRow(
                label: 'Remise / الخصم',
                value: '- ${_numFmt.format(discountAmount)} DA',
                bold: bold,
                regular: regular,
                valueColor: PdfColors.red,
              ),
              pw.Divider(height: 1, color: _primaryColor),
              _totalRow(
                label: 'Net à payer / المبلغ الصافي',
                value: '${_numFmt.format(netTotal)} DA',
                bold: bold,
                regular: bold, // intentionally bold for value
                isLarge: true,
                bgColor: _lightBg,
              ),
              pw.Divider(height: 1, color: _grey),
              _totalRow(
                label: 'Versé / المدفوع',
                value: '${_numFmt.format(paidAmount)} DA',
                bold: bold,
                regular: regular,
                valueColor: PdfColors.green,
              ),
              pw.Divider(height: 1, color: _grey),
              _totalRow(
                label: 'Reste / المتبقي',
                value: '${_numFmt.format(remainingAmount)} DA',
                bold: bold,
                regular: regular,
                valueColor: remainingAmount > 0 ? PdfColors.red : PdfColors.green,
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Notes section.
  static pw.Widget _buildNotes(
    String notes, {
    required pw.Font bold,
    required pw.Font regular,
  }) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(8),
      decoration: pw.BoxDecoration(
        color: _rowAlt,
        border: pw.Border.all(color: _grey, width: 0.5),
        borderRadius: pw.BorderRadius.circular(4),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'Remarques / ملاحظات',
            style: pw.TextStyle(font: bold, fontSize: 9, color: _primaryColor),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            notes,
            style: pw.TextStyle(font: regular, fontSize: 9, color: _dark),
          ),
        ],
      ),
    );
  }

  /// Two signature boxes at the bottom.
  static pw.Widget _buildSignatures({
    required pw.Font bold,
    required pw.Font regular,
  }) {
    return pw.Row(
      children: [
        pw.Expanded(
          child: _signatureBox(
            title: 'Signature client / توقيع العميل',
            bold: bold,
            regular: regular,
          ),
        ),
        pw.SizedBox(width: 20),
        pw.Expanded(
          child: _signatureBox(
            title: 'Tampon & signature / الختم والتوقيع',
            bold: bold,
            regular: regular,
          ),
        ),
      ],
    );
  }

  /// Page X / Y footer.
  static pw.Widget _buildFooter(
      pw.Context context, pw.Font regular) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        PdfBranding.footerMark(regular, color: _grey, fontSize: 7),
        pw.Text(
          'Page ${context.pageNumber} / ${context.pagesCount}',
          style: pw.TextStyle(font: regular, fontSize: 7, color: _grey),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Small reusable widgets
  // ---------------------------------------------------------------------------

  static pw.Widget _infoLine({
    required String label,
    required String value,
    required pw.Font bold,
    required pw.Font regular,
  }) {
    return pw.RichText(
      text: pw.TextSpan(
        children: [
          pw.TextSpan(
            text: '$label: ',
            style: pw.TextStyle(font: bold, fontSize: 8, color: _grey),
          ),
          pw.TextSpan(
            text: value,
            style: pw.TextStyle(font: regular, fontSize: 9, color: _dark),
          ),
        ],
      ),
    );
  }

  static pw.Widget _tableCell(
    String text,
    pw.Font font, {
    pw.TextAlign align = pw.TextAlign.left,
    double fontSize = 8.5,
    PdfColor? color,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: pw.Text(
        text,
        textAlign: align,
        style: pw.TextStyle(
          font: font,
          fontSize: fontSize,
          color: color ?? _dark,
        ),
      ),
    );
  }

  static pw.Widget _totalRow({
    required String label,
    required String value,
    required pw.Font bold,
    required pw.Font regular,
    PdfColor? valueColor,
    bool isLarge = false,
    PdfColor? bgColor,
  }) {
    return pw.Container(
      color: bgColor,
      padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            label,
            style: pw.TextStyle(
              font: bold,
              fontSize: isLarge ? 10 : 8.5,
              color: _dark,
            ),
          ),
          pw.Text(
            value,
            style: pw.TextStyle(
              font: bold,
              fontSize: isLarge ? 11 : 9,
              color: valueColor ?? _dark,
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _signatureBox({
    required String title,
    required pw.Font bold,
    required pw.Font regular,
  }) {
    return pw.Container(
      height: 70,
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: _primaryColor, width: 0.5),
        borderRadius: pw.BorderRadius.circular(4),
      ),
      child: pw.Column(
        children: [
          pw.Container(
            width: double.infinity,
            padding:
                const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            decoration: pw.BoxDecoration(
              color: _primaryColor,
              borderRadius: const pw.BorderRadius.only(
                topLeft: pw.Radius.circular(4),
                topRight: pw.Radius.circular(4),
              ),
            ),
            child: pw.Text(
              title,
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(font: bold, fontSize: 8, color: _white),
            ),
          ),
          pw.Expanded(child: pw.SizedBox()),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  /// Builds a designation string from item fields.
  static String _buildDesignation(Map<String, dynamic> item) {
    final name = _s(item['item_name']);
    final code = _s(item['item_code']);
    final type = _s(item['item_type']);
    final parts = <String>[name];
    if (code.isNotEmpty) parts.add('[$code]');
    if (type.isNotEmpty) parts.add('($type)');
    return parts.join(' ');
  }

  /// Safely converts a map value to String.
  static String _s(dynamic v) => v?.toString() ?? '';

  /// Safely converts a map value to double.
  static double _d(dynamic v) {
    if (v == null) return 0.0;
    if (v is double) return v;
    if (v is int) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0.0;
  }

  /// Formats an ISO date string to a readable French/Arabic format.
  static String _formatDate(String raw) {
    if (raw.isEmpty) return '—';
    try {
      final dt = DateTime.parse(raw);
      return DateFormat('dd/MM/yyyy').format(dt);
    } catch (_) {
      return raw;
    }
  }

  /// Translates status codes to bilingual labels.
  static String _translateStatus(String status) {
    const map = {
      'draft': 'Brouillon / مسودة',
      'confirmed': 'Confirmé / مؤكد',
      'delivered': 'Livré / تم التسليم',
      'cancelled': 'Annulé / ملغى',
      'paid': 'Payé / مدفوع',
      'partial': 'Partiel / جزئي',
    };
    return map[status] ?? status;
  }
}
