import 'dart:convert';
import 'package:database_data/Commande/Systeme/calculate_component.dart';
import 'package:database_data/Commande/Systeme/model.dart';
import 'package:database_data/Commande/Systeme/model_serialization.dart';
import 'package:database_data/sql_database.dart';
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
    required SqlDatabase db,
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
        final isReplaced =
            (map['isReplaced'] == true ||
                map['isReplaced']?.toString().toLowerCase() == 'true') ||
            ((item['price'] as num?)?.toDouble() == 0.0);
        if (isReplaced) {
          return false;
        }
      } catch (_) {}
      return true;
    }).toList();

    final itemCutWidgets = <pw.Widget>[];
    for (final item in activeItems) {
      itemCutWidgets.add(await _buildItemCutList(db, item));
    }

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
          ...itemCutWidgets,
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
        logoWidget = pw.Image(
          pw.MemoryImage(imageBytes),
          width: 50,
          height: 50,
        );
      } catch (_) {}
    }

    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            if (logoWidget != null) ...[logoWidget, pw.SizedBox(width: 12)],
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

  static Future<pw.Widget> _buildItemCutList(
    SqlDatabase db,
    Map<String, dynamic> item,
  ) async {
    final String type = item['window_type']?.toString() ?? 'نافذة';
    final double width = _number(item['largeur']);
    final double height = _number(item['hauteur']);
    final int qty = (_number(item['quantity'], fallback: 1)).round();
    final bomItems = await _bomFromSavedDrawing(db, item);
    final cutRows = _buildCutRowsFromBom(bomItems);
    final accessoryRows = bomItems
        .where(
          (bom) =>
              bom.isActive &&
              bom.purchaseQuantity > 0 &&
              (bom.pieces == null || bom.pieces!.isEmpty),
        )
        .toList();

    final headers = ['القطاع / المكوّن', 'زوايا القطع', 'الكمية', 'الطول'];
    final data = cutRows.isEmpty
        ? [
            [
              'الأبعاد العامة',
              '-',
              '$qty',
              '${width.toStringAsFixed(0)} x ${height.toStringAsFixed(0)} مم',
            ],
          ]
        : cutRows
              .map(
                (row) => [
                  row.name,
                  row.angles,
                  row.quantity.toString(),
                  '${row.lengthMm.round()} مم',
                ],
              )
              .toList();

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
          if (cutRows.isNotEmpty) ...[
            pw.SizedBox(height: 10),
            pw.Wrap(
              spacing: 8,
              runSpacing: 8,
              children: cutRows.take(12).map(_buildCutSketch).toList(),
            ),
          ],
          pw.SizedBox(height: 10),
          pw.Text(
            'الأكسسوارات:',
            style: pw.TextStyle(
              fontWeight: pw.FontWeight.bold,
              decoration: pw.TextDecoration.underline,
            ),
          ),
          if (accessoryRows.isEmpty)
            pw.Text(
              'لا توجد أكسسوارات مفصلة محفوظة لهذا المنتج.',
              style: const pw.TextStyle(color: PdfColors.grey700),
            )
          else
            ...accessoryRows.map(
              (bom) => pw.Text(
                '- ${bom.name}: ${_quantity(bom.purchaseQuantity)} ${bom.unit}',
                style: const pw.TextStyle(color: PdfColors.grey700),
              ),
            ),
        ],
      ),
    );
  }

  static Future<List<BomItem>> _bomFromSavedDrawing(
    SqlDatabase db,
    Map<String, dynamic> item,
  ) async {
    final raw = item['partitions_json'];
    if (raw == null || raw.toString().trim().isEmpty) return const [];
    try {
      final decoded = raw is Map
          ? Map<String, dynamic>.from(raw)
          : Map<String, dynamic>.from(jsonDecode(raw.toString()) as Map);
      final model = WindowModel(db: db);
      await applyWindowModelAndLoadCatalog(model, decoded);
      applyStoredOrderDetailColorToWindowModel(model, item);
      model.quantity = (_number(
        item['quantity'],
        fallback: model.quantity.toDouble(),
      )).round().clamp(1, 999999).toInt();
      await model.updateShutterDefaultsIfNeeded();
      return ComponentCalculator.generateBom(
        model,
        _activeVariants(model),
      ).where((bom) => bom.isActive && bom.purchaseQuantity > 0).toList();
    } catch (_) {
      return const [];
    }
  }

  static Map<String, bool> _activeVariants(WindowModel model) {
    final isTunnel = model.isCaissonTunnel;
    final isMotor = model.shutterMechanism == 'محرك';
    final isCrank =
        model.shutterMechanism == 'منايفال' ||
        model.shutterMechanism == 'مانيفال' ||
        model.shutterMechanism == 'مانيفر';
    return {
      'Verrou Central':
          model.canUseOpeningOnlyOptions && model.useVerrouCentral,
      'System OB': model.effectiveUseSystemOB,
      'Demi System OB': model.effectiveUseDemiOB,
      'كيت (Kit)': false,
      'طانديم (Tandem)': isTunnel,
      'الامبو (Embout)': isMotor,
      'سيبور رولمو (Support Roulement)': isMotor,
      'سيبور موتور (Support Moteur)': isMotor || isTunnel,
      'أغطية الشفرات (Bouchons Lames)': model.componentOverrides.containsKey(
        'أغطية الشفرات (Bouchons Lames)',
      ),
      'كيت فولي موتور (Kit Volet Moteur)': !isTunnel && isMotor,
      'كيت فولي مانيفر (Kit Volet Manivelle)': !isTunnel && isCrank,
      'كيت مانيفر (Kit Manivelle)': !isTunnel && isCrank,
      'كيت فولي (Kit Volet)': !isTunnel && !isMotor && !isCrank,
      'كيت حزام (Kit Sangle)': false,
    };
  }

  static List<_FicheCutRow> _buildCutRowsFromBom(List<BomItem> bomItems) {
    final grouped = <String, _FicheCutRow>{};
    for (final bom in bomItems) {
      final pieces = bom.pieces;
      if (pieces == null || pieces.isEmpty) continue;
      for (final lengthM in pieces) {
        if (lengthM <= 0) continue;
        final lengthMm = lengthM * 1000;
        final angles = _anglesFor(bom);
        final key = '${bom.name}|$angles|${lengthMm.round()}';
        final existing = grouped[key];
        if (existing == null) {
          grouped[key] = _FicheCutRow(
            name: bom.profileCode == null
                ? bom.name
                : '[${bom.profileCode}] ${bom.name}',
            angles: angles,
            quantity: 1,
            lengthMm: lengthMm,
          );
        } else {
          grouped[key] = existing.copyWith(quantity: existing.quantity + 1);
        }
      }
    }
    final rows = grouped.values.toList()
      ..sort((a, b) {
        final byName = a.name.compareTo(b.name);
        if (byName != 0) return byName;
        return b.lengthMm.compareTo(a.lengthMm);
      });
    return rows;
  }

  static String _anglesFor(BomItem item) {
    final text = '${item.originalName} ${item.name}'.toLowerCase();
    if (text.contains('lame') ||
        text.contains('axe') ||
        text.contains('caisson') ||
        text.contains('gliss') ||
        text.contains('الشرائح') ||
        text.contains('المحور') ||
        text.contains('الصندوق')) {
      return '90° / 90°';
    }
    return '45° / 45°';
  }

  static pw.Widget _buildCutSketch(_FicheCutRow row) {
    return pw.Container(
      width: 145,
      padding: const pw.EdgeInsets.all(6),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey500),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Container(
            height: 18,
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.black, width: 0.8),
              color: PdfColors.grey100,
            ),
            alignment: pw.Alignment.center,
            child: pw.Text(row.angles, style: const pw.TextStyle(fontSize: 8)),
          ),
          pw.SizedBox(height: 3),
          pw.Text(
            '${row.quantity} x ${row.lengthMm.round()} مم',
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
          ),
        ],
      ),
    );
  }

  static double _number(Object? value, {double fallback = 0}) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString().replaceAll(',', '.') ?? '') ??
        fallback;
  }

  static String _quantity(double value) {
    if ((value - value.roundToDouble()).abs() < 0.000001) {
      return value.round().toString();
    }
    return value.toStringAsFixed(2);
  }
}

class _FicheCutRow {
  const _FicheCutRow({
    required this.name,
    required this.angles,
    required this.quantity,
    required this.lengthMm,
  });

  final String name;
  final String angles;
  final int quantity;
  final double lengthMm;

  _FicheCutRow copyWith({int? quantity}) => _FicheCutRow(
    name: name,
    angles: angles,
    quantity: quantity ?? this.quantity,
    lengthMm: lengthMm,
  );
}
