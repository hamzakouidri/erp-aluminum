import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart' show rootBundle;
import 'package:database_data/Commande/capture_image.dart';
import 'package:database_data/Commande/devis_builder.dart';
import 'package:database_data/Commande/Systeme/bom_engine_v2.dart';
import 'package:database_data/Commande/Systeme/calculate_component.dart';
import 'package:database_data/Commande/Systeme/model.dart';
import 'package:database_data/Commande/Systeme/model_serialization.dart';
import 'package:database_data/sql_database.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:database_data/Commande/order_date_utils.dart';
import 'package:database_data/settings/app_settings.dart';
import 'package:database_data/settings/localization.dart';
import 'package:database_data/services/pdf_font_cache.dart';

// ─── ألوان التصميم ────────────────────────────────────────────────────────────
const _kBlue = PdfColor(0.051, 0.278, 0.631); // #0D47A1
const _kBlueSub = PdfColor(0.122, 0.467, 0.706); // #1F77B4
const _kRowAlt = PdfColor(0.950, 0.960, 0.980);
const _kBorder = PdfColor(0.788, 0.812, 0.843);

class PdfFicheCoupeApi {
  // ──────────────────────────────────────────────────────────────────────────
  // نقطة الدخول الرئيسية — تُرجع Uint8List
  // ──────────────────────────────────────────────────────────────────────────
  static Future<Uint8List> generateFicheCoupe({
    required Map<String, dynamic> order,
    required List<Map<String, dynamic>> items,
    required String workshopName,
    required SqlDatabase db,
    AppLanguage? language,
  }) async {
    final fonts = await PdfFontCache.load();
    final font = fonts.regular;
    final fontBold = fonts.bold;
    final prefs = await SharedPreferences.getInstance();
    final logoBase64 = prefs.getString('workshop_logo_base64') ?? '';
    final address = prefs.getString('workshop_address') ?? '';
    final phone = prefs.getString('workshop_phone') ?? '';

    final resolvedLanguage = language ?? () {
      final langIndex = prefs.getInt('app_language');
      if (langIndex != null &&
          langIndex >= 0 &&
          langIndex < AppLanguage.values.length) {
        return AppLanguage.values[langIndex];
      }
      final savedLanguage = prefs.getString('app_language');
      if (savedLanguage == 'french') return AppLanguage.french;
      if (savedLanguage == 'english') return AppLanguage.english;
      if (savedLanguage == 'arabic') return AppLanguage.arabic;
      return AppLanguage.french;
    }();

    final tr = _Tr(resolvedLanguage);

    // تصفية المنتجات غير المحذوفة
    final activeItems = items.where((item) {
      try {
        final jsonRaw = item['partitions_json'];
        Map<String, dynamic> map = {};
        if (jsonRaw is Map<String, dynamic>) {
          map = jsonRaw;
        } else if (jsonRaw is Map) {
          map = Map<String, dynamic>.from(jsonRaw);
        } else {
          final str = jsonRaw?.toString().trim() ?? '';
          if (str.length >= 5) map = jsonDecode(str) as Map<String, dynamic>;
        }
        return !(map['isReplaced'] == true ||
            map['isReplaced']?.toString().toLowerCase() == 'true');
      } catch (_) {
        return true;
      }
    }).toList();

    // كاش لصور المقاطع لتجنب إعادة التحميل المتكررة
    final imageCache = <String, pw.Widget?>{};

    // تحميل بيانات كل منتج مع دمج القطع وصور المقاطع
    final articles = <_ArticleData>[];
    for (final item in activeItems) {
      articles.add(await _loadArticle(db, item, resolvedLanguage, imageCache));
    }

    // شعار الورشة
    pw.Widget? logoWidget;
    if (logoBase64.isNotEmpty) {
      try {
        logoWidget = pw.Image(
          pw.MemoryImage(base64Decode(logoBase64)),
          width: 55,
          height: 55,
        );
      } catch (_) {}
    }

    final orderDate = formatOrderDate(
      order['created_at'],
      fallback: order['updated_at'],
      emptyLabel: Localization.translate('غير محدد', resolvedLanguage),
    );
    final clientName =
        '${order['firstname'] ?? ''} ${order['lastname'] ?? ''}'.trim();
    final commandeId = order['id']?.toString() ?? '';
    final enteredBy = order['username']?.toString() ?? '';

    final pdf = pw.Document();
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(20, 20, 20, 24),
        textDirection: tr.isRtl ? pw.TextDirection.rtl : pw.TextDirection.ltr,
        theme: pw.ThemeData.withFont(base: font, bold: fontBold),
        // ── رأس الصفحة ── يظهر اسم المؤسسة وتفاصيلها في بداية الورقة فقط
        header: (ctx) {
          if (ctx.pageNumber > 1) {
            return pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 6),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    ' - ',
                    style: pw.TextStyle(font: font, fontSize: 8, color: PdfColors.grey600),
                  ),
                  pw.Text(
                    tr.page(ctx.pageNumber, ctx.pagesCount),
                    style: pw.TextStyle(font: font, fontSize: 8, color: PdfColors.grey600),
                  ),
                ],
              ),
            );
          }
          return _buildPageHeader(
            workshopName: workshopName,
            address: address,
            phone: phone,
            logoWidget: logoWidget,
            orderDate: orderDate,
            clientName: clientName,
            commandeId: commandeId,
            enteredBy: enteredBy,
            fontBold: fontBold,
            tr: tr,
          );
        },
        // ── ذيل الصفحة ──
        footer: (ctx) => _buildPageFooter(workshopName, ctx, font, tr),
        build: (ctx) {
          final widgets = <pw.Widget>[];
          for (var i = 0; i < articles.length; i++) {
            if (i > 0) widgets.add(pw.NewPage());
            widgets.addAll(
              _buildArticle(
                index: i + 1,
                data: articles[i],
                font: font,
                fontBold: fontBold,
                tr: tr,
              ),
            );
          }
          return widgets;
        },
      ),
    );

    return pdf.save();
  }

  // ──────────────────────────────────────────────────────────────────────────
  // رأس الصفحة
  // ──────────────────────────────────────────────────────────────────────────
  static pw.Widget _buildPageHeader({
    required String workshopName,
    required String address,
    required String phone,
    required pw.Widget? logoWidget,
    required String orderDate,
    required String clientName,
    required String commandeId,
    required String enteredBy,
    required pw.Font fontBold,
    required _Tr tr,
  }) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            if (logoWidget != null) ...[logoWidget, pw.SizedBox(width: 10)],
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  pw.Text(
                    workshopName,
                    style: pw.TextStyle(
                      font: fontBold,
                      fontSize: 18,
                      color: _kBlue,
                    ),
                    textAlign: pw.TextAlign.center,
                  ),
                  pw.Text(
                    tr.ficheDeCoupe,
                    style: pw.TextStyle(
                      font: fontBold,
                      fontSize: 12,
                      color: _kBlue,
                      letterSpacing: 2,
                    ),
                    textAlign: pw.TextAlign.center,
                  ),
                  if (address.isNotEmpty || phone.isNotEmpty)
                    pw.Text(
                      [
                        if (address.isNotEmpty) address,
                        if (phone.isNotEmpty) 'Tél: $phone',
                      ].join(' | '),
                      style: const pw.TextStyle(
                        fontSize: 7.5,
                        color: PdfColors.grey700,
                      ),
                      textAlign: pw.TextAlign.center,
                    ),
                ],
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 5),
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          decoration: const pw.BoxDecoration(
            border: pw.Border(
              top: pw.BorderSide(color: _kBorder, width: 0.5),
              bottom: pw.BorderSide(color: _kBorder, width: 0.5),
            ),
          ),
          child: pw.Row(
            children: [
              pw.Expanded(
                child: pw.Text(
                  '${tr.date} $orderDate',
                  style: const pw.TextStyle(fontSize: 8.5),
                ),
              ),
              if (enteredBy.isNotEmpty)
                pw.Expanded(
                  child: pw.Text(
                    '${tr.saisiPar} $enteredBy',
                    style: const pw.TextStyle(fontSize: 8.5),
                    textAlign: pw.TextAlign.center,
                  ),
                ),
              pw.Expanded(
                child: pw.Text(
                  '${tr.client} $clientName',
                  style: const pw.TextStyle(fontSize: 8.5),
                  textAlign: pw.TextAlign.center,
                ),
              ),
              pw.Expanded(
                child: pw.Text(
                  '${tr.commande}$commandeId',
                  style: const pw.TextStyle(fontSize: 8.5),
                  textAlign: tr.isRtl ? pw.TextAlign.left : pw.TextAlign.right,
                ),
              ),
            ],
          ),
        ),
        pw.SizedBox(height: 8),
      ],
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // ذيل الصفحة
  // ──────────────────────────────────────────────────────────────────────────
  static pw.Widget _buildPageFooter(
    String workshopName,
    pw.Context ctx,
    pw.Font font,
    _Tr tr,
  ) {
    final style = pw.TextStyle(font: font, fontSize: 7.5, color: PdfColors.grey600);
    return pw.Container(
      margin: const pw.EdgeInsets.only(top: 4),
      padding: const pw.EdgeInsets.only(top: 3),
      decoration: const pw.BoxDecoration(
        border: pw.Border(
          top: pw.BorderSide(color: PdfColors.grey400, width: 0.4),
        ),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(workshopName, style: style),
          pw.Text('ERP Aluminum', style: style),
          pw.Text(
            tr.page(ctx.pageNumber, ctx.pagesCount),
            style: style.copyWith(color: _kBlue),
          ),
        ],
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // بناء محتوى منتج واحد (Article)
  // ──────────────────────────────────────────────────────────────────────────
  static List<pw.Widget> _buildArticle({
    required int index,
    required _ArticleData data,
    required pw.Font font,
    required pw.Font fontBold,
    required _Tr tr,
  }) {
    final widgets = <pw.Widget>[];

    // ── 1. شريط عنوان المنتج ──
    widgets.add(_blueBar(tr.article(index), fontBold, fontSize: 10.5));
    widgets.add(pw.SizedBox(height: 3));

    // ── 2. سطر مواصفات المنتج بالترتيب المطلوب:
    // Gamme ثم Type ثم Configuration ثم Shutter ثم Couleur ثم Dimensions ثم Quantité
    final parts = <String>[];
    if (data.gamme.isNotEmpty) parts.add('${tr.gamme} ${data.gamme}');
    if (data.openingType.isNotEmpty) parts.add(data.openingType);
    if (data.configuration.isNotEmpty) parts.add(data.configuration);
    if (data.shutterInfo.isNotEmpty) parts.add(data.shutterInfo);
    if (data.colorName.isNotEmpty) parts.add('${tr.couleur} ${data.colorName}');
    parts.add('${data.width.toStringAsFixed(0)} × ${data.height.toStringAsFixed(0)} mm');
    parts.add('${tr.qte} ${data.qty}');

    widgets.add(
      pw.Container(
        padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 3.5),
        color: _kRowAlt,
        child: pw.Text(
          parts.join('   |   '),
          style: pw.TextStyle(font: font, fontSize: 8.5),
        ),
      ),
    );
    widgets.add(pw.SizedBox(height: 8));

    // ── 3+4+5+6. رسم العنصر جنباً إلى جنب مع جداول التفاصيل ──────────────
    // العمود الأيسر : الرسم (≈42% من العرض)
    // العمود الأيمن : جداول الـ Profils والإكسسوارات والـ Joints (≈58%)
    final accessories = data.bomItems
        .where(
          (b) =>
              b.isActive &&
              b.purchaseQuantity > 0 &&
              (b.pieces == null || b.pieces!.isEmpty) &&
              b.category.toLowerCase() != 'joint',
        )
        .toList();
    final joints = data.bomItems
        .where(
          (b) =>
              b.isActive &&
              b.purchaseQuantity > 0 &&
              b.category.toLowerCase() == 'joint',
        )
        .toList();

    final hasDetails =
        data.profiles.isNotEmpty || accessories.isNotEmpty || joints.isNotEmpty;

    // عمود الرسم
    final pw.Widget drawingWidget = data.drawing != null
        ? pw.Image(
            pw.MemoryImage(data.drawing!),
            fit: pw.BoxFit.contain,
          )
        : pw.Container(
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: _kBorder),
              color: _kRowAlt,
            ),
            child: pw.Center(
              child: pw.Text(
                '${data.width.toStringAsFixed(0)} × ${data.height.toStringAsFixed(0)} mm',
                style: pw.TextStyle(
                  font: fontBold,
                  fontSize: 11,
                  color: PdfColors.grey600,
                ),
              ),
            ),
          );

    // عمود الجداول (Profils + Accessories + Joints)
    final detailColumn = <pw.Widget>[];
    if (data.profiles.isNotEmpty) {
      detailColumn.add(
        _blueBar(tr.profils, fontBold, color: _kBlueSub, fontSize: 9),
      );
      detailColumn.add(pw.SizedBox(height: 2));
      detailColumn.add(
        _buildProfilesTable(data.profiles, font, fontBold, tr),
      );
      detailColumn.add(pw.SizedBox(height: 6));
    }
    if (accessories.isNotEmpty) {
      detailColumn.add(
        _blueBar(tr.accessoires, fontBold, color: _kBlueSub, fontSize: 9),
      );
      detailColumn.add(pw.SizedBox(height: 2));
      detailColumn.add(
        _buildAccessoriesTable(accessories, font, fontBold, tr),
      );
      detailColumn.add(pw.SizedBox(height: 6));
    }
    if (joints.isNotEmpty) {
      detailColumn.add(
        _blueBar(tr.joints, fontBold, color: _kBlueSub, fontSize: 9),
      );
      detailColumn.add(pw.SizedBox(height: 2));
      detailColumn.add(_buildJointsTable(joints, font, fontBold, tr));
    }

    if (hasDetails) {
      // تخطيط عمودين: رسم أكبر قليلاً (48%) تحت الفراغ وأمام التفاصيل | فراغ فاصل | جداول (52%)
      widgets.add(
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            // عمود الرسم
            pw.Expanded(
              flex: 48,
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                children: [
                  pw.SizedBox(height: 6),
                  pw.Container(
                    padding: const pw.EdgeInsets.all(5),
                    decoration: pw.BoxDecoration(
                      border: pw.Border.all(color: _kBorder, width: 0.5),
                      borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
                    ),
                    child: drawingWidget,
                  ),
                ],
              ),
            ),
            pw.SizedBox(width: 10),
            // عمود الجداول
            pw.Expanded(
              flex: 52,
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                children: detailColumn,
              ),
            ),
          ],
        ),
      );
    } else {
      // لا توجد تفاصيل: يظهر الرسم بعرض كامل
      widgets.add(
        pw.Center(
          child: pw.Container(
            width: PdfPageFormat.a4.availableWidth - 10,
            height: 310,
            padding: const pw.EdgeInsets.all(4),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: _kBorder, width: 0.5),
            ),
            child: drawingWidget,
          ),
        ),
      );
    }

    return widgets;
  }

  // ──────────────────────────────────────────────────────────────────────────
  // جدول الـ Profils:
  // لا نكرر العنصر مرتين! المرجع والوصف والصورة في سطر واحد،
  // والقياسات (العرض والارتفاع) تكون سطوراً فرعية داخل نفس السطر.
  // الأعمدة: [صورة] | المرجع | الوصف | الكمية | الطول | زاوية القطع
  // ──────────────────────────────────────────────────────────────────────────
  static pw.Widget _buildProfilesTable(
    List<_ProfileCutRow> rows,
    pw.Font font,
    pw.Font fontBold,
    _Tr tr,
  ) {
    const colWidths = <int, pw.TableColumnWidth>{
      0: pw.FixedColumnWidth(32), // صورة المقطع
      1: pw.FixedColumnWidth(70), // المرجع
      2: pw.FlexColumnWidth(3.0), // الوصف
      3: pw.FixedColumnWidth(32), // الكمية
      4: pw.FixedColumnWidth(65), // الطول
      5: pw.FixedColumnWidth(95), // زاوية القطع
    };

    final tableRows = <pw.TableRow>[];

    // ترويسة الجدول
    tableRows.add(
      pw.TableRow(
        decoration: const pw.BoxDecoration(color: _kBlue),
        children: [
          _hdr(tr.image, fontBold, align: pw.TextAlign.center),
          _hdr(tr.reference, fontBold),
          _hdr(tr.designation, fontBold),
          _hdr(tr.quantite, fontBold, align: pw.TextAlign.center),
          _hdr(tr.longueur, fontBold, align: pw.TextAlign.center),
          _hdr(tr.coupe, fontBold, align: pw.TextAlign.center),
        ],
      ),
    );

    // بناء صفوف القطاعات
    for (var i = 0; i < rows.length; i++) {
      final row = rows[i];
      final isAlt = i.isOdd;
      final cutCount = row.cuts.length;
      final totalRowHeight = cutCount * 25.0;

      tableRows.add(
        pw.TableRow(
          decoration: pw.BoxDecoration(
            color: isAlt ? _kRowAlt : PdfColors.white,
          ),
          children: [
            // [0] صورة المقطع الحقيقية
            pw.Container(
              height: totalRowHeight,
              alignment: pw.Alignment.center,
              padding: const pw.EdgeInsets.all(2),
              child: row.imageWidget ?? _defaultProfileIcon(),
            ),
            // [1] المرجع — يُكتب مرة واحدة فقط
            pw.Container(
              height: totalRowHeight,
              alignment: tr.isRtl ? pw.Alignment.centerRight : pw.Alignment.centerLeft,
              padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              child: pw.Text(
                row.reference,
                style: pw.TextStyle(font: fontBold, fontSize: 8.5),
              ),
            ),
            // [2] الوصف — يُكتب مرة واحدة فقط
            pw.Container(
              height: totalRowHeight,
              alignment: tr.isRtl ? pw.Alignment.centerRight : pw.Alignment.centerLeft,
              padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              child: pw.Text(
                row.description,
                style: pw.TextStyle(font: font, fontSize: 8.5),
              ),
            ),
            // [3] الكمية — سطر لكل قياس داخل نفس الخلية
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: [
                for (var c = 0; c < cutCount; c++) ...[
                  if (c > 0) pw.Container(height: 0.5, color: _kBorder),
                  pw.Container(
                    height: 24.5,
                    alignment: pw.Alignment.center,
                    child: pw.Text(
                      '${row.cuts[c].qty}',
                      style: pw.TextStyle(font: fontBold, fontSize: 8.5),
                    ),
                  ),
                ],
              ],
            ),
            // [4] الطول — سطر لكل قياس داخل نفس الخلية
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: [
                for (var c = 0; c < cutCount; c++) ...[
                  if (c > 0) pw.Container(height: 0.5, color: _kBorder),
                  pw.Container(
                    height: 24.5,
                    alignment: pw.Alignment.center,
                    child: pw.Text(
                      '${row.cuts[c].lengthMm} mm',
                      style: pw.TextStyle(font: font, fontSize: 8.5),
                    ),
                  ),
                ],
              ],
            ),
            // [5] زاوية القطع مع المخطط — سطر لكل قياس داخل نفس الخلية
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: [
                for (var c = 0; c < cutCount; c++) ...[
                  if (c > 0) pw.Container(height: 0.5, color: _kBorder),
                  pw.Container(
                    height: 24.5,
                    alignment: pw.Alignment.center,
                    padding: const pw.EdgeInsets.symmetric(horizontal: 2),
                    child: pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.center,
                      crossAxisAlignment: pw.CrossAxisAlignment.center,
                      children: [
                        _angleSvg(row.cuts[c].angles),
                        pw.SizedBox(width: 4),
                        pw.Text(
                          row.cuts[c].angles,
                          style: pw.TextStyle(
                            font: font,
                            fontSize: 7,
                            color: PdfColors.grey800,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      );
    }

    return pw.Table(
      columnWidths: colWidths,
      border: pw.TableBorder.all(color: _kBorder, width: 0.4),
      children: tableRows,
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // جدول الإكسسوارات (مستقل — بدون زوايا أو قياسات قطع)
  // ──────────────────────────────────────────────────────────────────────────
  static pw.Widget _buildAccessoriesTable(
    List<BomItem> items,
    pw.Font font,
    pw.Font fontBold,
    _Tr tr,
  ) {
    final langCode = tr.lang == AppLanguage.french
        ? 'fr'
        : (tr.lang == AppLanguage.english ? 'en' : 'ar');
    final tableRows = <pw.TableRow>[
      pw.TableRow(
        decoration: const pw.BoxDecoration(color: _kBlue),
        children: [
          _hdr(tr.reference, fontBold),
          _hdr(tr.designation, fontBold),
          _hdr(tr.quantite, fontBold, align: pw.TextAlign.center),
          _hdr(tr.unite, fontBold, align: pw.TextAlign.center),
        ],
      ),
    ];
    for (var i = 0; i < items.length; i++) {
      final b = items[i];
      final localizedName = b.getLocalizedName(langCode);
      tableRows.add(
        pw.TableRow(
          decoration: pw.BoxDecoration(
            color: i.isOdd ? _kRowAlt : PdfColors.white,
          ),
          children: [
            _cell(b.profileCode ?? '-', font),
            _cell(_shortName(localizedName, tr.lang), font),
            _cell(
              _qty(b.purchaseQuantity),
              font,
              align: pw.TextAlign.center,
              bold: true,
              boldFont: fontBold,
            ),
            _cell(_unit(b.unit, tr.lang), font, align: pw.TextAlign.center),
          ],
        ),
      );
    }
    return pw.Table(
      columnWidths: const {
        0: pw.FixedColumnWidth(70),
        1: pw.FlexColumnWidth(3),
        2: pw.FixedColumnWidth(40),
        3: pw.FixedColumnWidth(45),
      },
      border: pw.TableBorder.all(color: _kBorder, width: 0.4),
      children: tableRows,
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // جدول الـ Joints
  // ──────────────────────────────────────────────────────────────────────────
  static pw.Widget _buildJointsTable(
    List<BomItem> items,
    pw.Font font,
    pw.Font fontBold,
    _Tr tr,
  ) {
    final langCode = tr.lang == AppLanguage.french
        ? 'fr'
        : (tr.lang == AppLanguage.english ? 'en' : 'ar');
    final tableRows = <pw.TableRow>[
      pw.TableRow(
        decoration: const pw.BoxDecoration(color: _kBlue),
        children: [
          _hdr(tr.reference, fontBold),
          _hdr(tr.designation, fontBold),
          _hdr(tr.longueurTotale, fontBold, align: pw.TextAlign.center),
        ],
      ),
    ];
    for (var i = 0; i < items.length; i++) {
      final b = items[i];
      final localizedName = b.getLocalizedName(langCode);
      tableRows.add(
        pw.TableRow(
          decoration: pw.BoxDecoration(
            color: i.isOdd ? _kRowAlt : PdfColors.white,
          ),
          children: [
            _cell(b.profileCode ?? '-', font),
            _cell(_shortName(localizedName, tr.lang), font),
            _cell(
              '${b.purchaseQuantity.toStringAsFixed(2)} m',
              font,
              align: pw.TextAlign.center,
            ),
          ],
        ),
      );
    }
    return pw.Table(
      columnWidths: const {
        0: pw.FixedColumnWidth(70),
        1: pw.FlexColumnWidth(3),
        2: pw.FixedColumnWidth(80),
      },
      border: pw.TableBorder.all(color: _kBorder, width: 0.4),
      children: tableRows,
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // رسم زاوية القطع: مستطيل بزوايا 90° أو شبه منحرف بزوايا 45°
  // ──────────────────────────────────────────────────────────────────────────
  static pw.Widget _angleSvg(String angles) {
    final parts = angles.split('/').map((s) => s.trim()).toList();
    final leftPart = parts.isNotEmpty ? parts.first : '45°';
    final rightPart = parts.length > 1 ? parts.last : '45°';
    final leftIs45 = leftPart.contains('45');
    final rightIs45 = rightPart.contains('45');

    final li = leftIs45 ? 6 : 0;
    final ri = rightIs45 ? 6 : 0;

    return pw.SvgImage(
      svg: '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 46 14">'
          '<path d="M1 1 L45 1 L${45 - ri} 13 L${1 + li} 13 Z" '
          'fill="#dbeafe" stroke="#1d4ed8" stroke-width="0.8"/>'
          '<line x1="${1 + li}" y1="7" x2="${45 - ri}" y2="7" '
          'stroke="#93c5fd" stroke-width="0.4" stroke-dasharray="2,1"/>'
          '</svg>',
      width: 44,
      height: 13,
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // تحميل صورة المقطع الحقيقية من المجلد أو قاعدة البيانات
  // ──────────────────────────────────────────────────────────────────────────
  static Future<pw.Widget?> _loadSectionImage({
    required String? code,
    required String? name,
    required String? imagePath,
    required SqlDatabase db,
    required int? catalogItemId,
    required Map<String, pw.Widget?> imageCache,
    double size = 26,
  }) async {
    final cacheKey = '${code ?? ''}|${name ?? ''}|${imagePath ?? ''}';
    if (imageCache.containsKey(cacheKey)) {
      return imageCache[cacheKey];
    }

    final candidates = <String>[];
    void addCandidate(String p) {
      final clean = p.trim().replaceAll('\\', '/');
      if (clean.isNotEmpty && !candidates.contains(clean)) {
        candidates.add(clean);
      }
    }

    // 1. مسار مباشر من قاعدة البيانات
    if (catalogItemId != null && catalogItemId > 0) {
      try {
        final database = await db.initDb();
        final rows = await database.query(
          'Sections',
          columns: ['image_path', 'code'],
          where: 'id = ?',
          whereArgs: [catalogItemId],
          limit: 1,
        );
        if (rows.isNotEmpty) {
          final dbPath = rows.first['image_path']?.toString();
          if (dbPath != null && dbPath.isNotEmpty) addCandidate(dbPath);
          final dbCode = rows.first['code']?.toString();
          if (dbCode != null && dbCode.isNotEmpty) {
            addCandidate('assets/sections/$dbCode.png');
            addCandidate('assets/sections/$dbCode.svg');
          }
        }
      } catch (_) {}
    }

    if (imagePath != null && imagePath.isNotEmpty) {
      addCandidate(imagePath);
      final filename = imagePath.replaceAll('\\', '/').split('/').last;
      if (filename.isNotEmpty) {
        addCandidate('assets/sections/$filename');
        addCandidate('assets/images/$filename');
      }
    }

    if (code != null && code.trim().isNotEmpty) {
      final rawCode = code.trim();
      final noExt = rawCode.replaceFirst(
        RegExp(r'\.(png|jpe?g|svg|webp)$', caseSensitive: false),
        '',
      );
      addCandidate('assets/sections/$rawCode');
      addCandidate('assets/sections/$noExt.png');
      addCandidate('assets/sections/$noExt.svg');
      final clean = noExt.replaceAll(RegExp(r'[\s_\-\/\.]+'), '').toUpperCase();
      if (clean.isNotEmpty && clean != noExt) {
        addCandidate('assets/sections/$clean.png');
        addCandidate('assets/sections/$clean.svg');
      }
    }

    Uint8List? bytes;
    bool isSvg = false;
    String? svgContent;

    for (final path in candidates) {
      // 1. فحص الملف المحلي على القرص
      try {
        final file = File(path);
        if (file.existsSync()) {
          final b = await file.readAsBytes();
          if (b.isNotEmpty) {
            bytes = b;
            isSvg = path.toLowerCase().endsWith('.svg');
            if (isSvg) svgContent = utf8.decode(b);
            break;
          }
        }
      } catch (_) {}

      // 2. فحص نسبي لـ assets/sections/
      try {
        final filename = path.split('/').last;
        final localFile = File('assets/sections/$filename');
        if (localFile.existsSync()) {
          final b = await localFile.readAsBytes();
          if (b.isNotEmpty) {
            bytes = b;
            isSvg = filename.toLowerCase().endsWith('.svg');
            if (isSvg) svgContent = utf8.decode(b);
            break;
          }
        }
      } catch (_) {}

      // 3. فحص من حزمة الأصول (rootBundle)
      try {
        final bd = await rootBundle.load(path);
        if (bd.lengthInBytes > 0) {
          bytes = bd.buffer.asUint8List(bd.offsetInBytes, bd.lengthInBytes);
          isSvg = path.toLowerCase().endsWith('.svg');
          if (isSvg) svgContent = utf8.decode(bytes);
          break;
        }
      } catch (_) {}
    }

    pw.Widget? loaded;
    if (bytes != null) {
      if (isSvg && svgContent != null) {
        try {
          loaded = pw.SvgImage(
            svg: svgContent,
            width: size,
            height: size,
            fit: pw.BoxFit.contain,
          );
        } catch (_) {}
      } else {
        try {
          loaded = pw.Image(
            pw.MemoryImage(bytes),
            width: size,
            height: size,
            fit: pw.BoxFit.contain,
          );
        } catch (_) {}
      }
    }

    imageCache[cacheKey] = loaded;
    return loaded;
  }

  /// أيقونة بديلة للمقطع عند عدم توفر الصورة
  static pw.Widget _defaultProfileIcon({double size = 24}) {
    return pw.SvgImage(
      svg: '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">'
          '<rect x="2" y="2" width="20" height="20" rx="2" fill="#edf2f9" stroke="#0d47a1" stroke-width="1.2"/>'
          '<rect x="6" y="6" width="12" height="12" rx="1" fill="#ffffff" stroke="#5c7ca8" stroke-width="0.8"/>'
          '<line x1="6" y1="12" x2="18" y2="12" stroke="#5c7ca8" stroke-width="0.6"/>'
          '</svg>',
      width: size,
      height: size,
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // تحميل وتجهيز بيانات المنتج
  // ──────────────────────────────────────────────────────────────────────────
  static Future<_ArticleData> _loadArticle(
    SqlDatabase db,
    Map<String, dynamic> item,
    AppLanguage lang,
    Map<String, pw.Widget?> imageCache,
  ) async {
    final width = _num(item['largeur']);
    final height = _num(item['hauteur']);
    final qty = _num(item['quantity'], fb: 1).round();

    final raw = item['partitions_json'];
    if (raw == null || raw.toString().trim().isEmpty) {
      return _ArticleData(
        gamme: item['game']?.toString() ?? '',
        openingType: '',
        configuration: '',
        shutterInfo: '',
        colorName: item['color']?.toString() ?? '',
        width: width,
        height: height,
        qty: qty,
        bomItems: const [],
        profiles: const [],
        drawing: null,
      );
    }

    try {
      final decoded = raw is Map
          ? Map<String, dynamic>.from(raw)
          : Map<String, dynamic>.from(jsonDecode(raw.toString()) as Map);
      final model = WindowModel(db: db);
      await applyWindowModelAndLoadCatalog(model, decoded);
      applyStoredOrderDetailColorToWindowModel(model, item);
      model.quantity = qty.clamp(1, 999999);
      await model.updateShutterDefaultsIfNeeded();

      var bom = ComponentCalculator.generateBom(model, _activeVariants(model));
      final engine = BomEngineV2(database: db);
      await engine.stabilizeSelections(window: model, items: bom);
      bom = await engine.filterItemsByAvailableCandidates(
        window: model,
        items: bom,
      );
      final active = bom.where((r) => r.isActive && r.purchaseQuantity > 0).toList();

      Uint8List? drawing;
      try {
        drawing = await captureWindowImage(
          model,
          maxSide: 2400,
          showDrawingDimensions: true,
        );
      } catch (_) {}

      // استخراج معلومات النظام والفتح والشكل واللون ومركب الستار
      final resolved = _resolveTypeAndConfig(
        item: item,
        decodedMap: decoded,
        model: model,
        lang: lang,
      );
      final rawGamme = model.activeSeries?.name ??
          model.activeSlidingSeries?.name ??
          item['game']?.toString() ??
          '';
      final gamme = Localization.translate(rawGamme, lang);
      final modelColor = model.selectedDbColor != null
          ? (model.selectedDbColor!['name']?.toString() ?? '')
          : model.frameColor.toString().split('.').last;
      final rawColor = item['color']?.toString().trim().isNotEmpty == true
          ? item['color'].toString().trim()
          : modelColor;
      final color = Localization.translate(rawColor, lang);

      // تجميع القطاعات بدون تكرار السطر
      final profileRows = await _buildGroupedProfileRows(
        active,
        db,
        imageCache,
        lang,
      );

      return _ArticleData(
        gamme: gamme,
        openingType: resolved.type,
        configuration: resolved.config,
        shutterInfo: resolved.shutterInfo,
        colorName: color,
        width: model.width > 0 ? model.width : width,
        height: model.height > 0 ? model.height : height,
        qty: qty,
        bomItems: active,
        profiles: profileRows,
        drawing: drawing,
      );
    } catch (_) {
      return _ArticleData(
        gamme: item['game']?.toString() ?? '',
        openingType: '',
        configuration: '',
        shutterInfo: '',
        colorName: item['color']?.toString() ?? '',
        width: width,
        height: height,
        qty: qty,
        bomItems: const [],
        profiles: const [],
        drawing: null,
      );
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // تجميع القطع لكل قطاع في سطر واحد
  // ──────────────────────────────────────────────────────────────────────────
  static Future<List<_ProfileCutRow>> _buildGroupedProfileRows(
    List<BomItem> bomItems,
    SqlDatabase db,
    Map<String, pw.Widget?> imageCache,
    AppLanguage lang,
  ) async {
    final langCode = lang == AppLanguage.french
        ? 'fr'
        : (lang == AppLanguage.english ? 'en' : 'ar');

    // تجميع القطع حسب القطاع: (المرجع + الاسم)
    final profileMap = <String, ({
      String reference,
      String description,
      String? imagePath,
      int? catalogItemId,
      Map<String, ({int qty, int lengthMm, String angles})> cuts,
    })>{};

    for (final bom in bomItems) {
      final pieces = bom.pieces;
      if (!bom.isActive || pieces == null || pieces.isEmpty) continue;

      final ref = bom.profileCode ?? '';
      final localizedName = bom.getLocalizedName(langCode);
      final desc = _shortName(localizedName, lang);
      final key = '${ref.trim()}|${desc.trim()}';

      final existing = profileMap.putIfAbsent(
        key,
        () => (
          reference: ref,
          description: desc,
          imagePath: bom.imagePath,
          catalogItemId: bom.catalogItemId,
          cuts: <String, ({int qty, int lengthMm, String angles})>{},
        ),
      );

      for (var pieceIndex = 0; pieceIndex < pieces.length; pieceIndex++) {
        final pM = pieces[pieceIndex];
        final angles = bom.pieceCutAngles != null &&
                pieceIndex < bom.pieceCutAngles!.length &&
                bom.pieceCutAngles![pieceIndex].trim().isNotEmpty
            ? _formatExplicitAngles(bom.pieceCutAngles![pieceIndex])
            : _anglesFor(bom);
        final mm = (pM * 1000).round();
        if (mm <= 0) continue;
        final cutKey = '$mm|$angles';
        final cur = existing.cuts[cutKey];
        if (cur != null) {
          existing.cuts[cutKey] = (qty: cur.qty + 1, lengthMm: mm, angles: angles);
        } else {
          existing.cuts[cutKey] = (qty: 1, lengthMm: mm, angles: angles);
        }
      }
    }

    final result = <_ProfileCutRow>[];
    for (final entry in profileMap.values) {
      if (entry.cuts.isEmpty) continue;

      final image = await _loadSectionImage(
        code: entry.reference,
        name: entry.description,
        imagePath: entry.imagePath,
        db: db,
        catalogItemId: entry.catalogItemId,
        imageCache: imageCache,
      );

      final sortedCuts = entry.cuts.values
          .map((c) => _CutPiece(qty: c.qty, lengthMm: c.lengthMm, angles: c.angles))
          .toList()
        ..sort((a, b) => b.lengthMm.compareTo(a.lengthMm));

      result.add(
        _ProfileCutRow(
          reference: entry.reference,
          description: entry.description,
          imageWidget: image,
          cuts: sortedCuts,
        ),
      );
    }

    result.sort((a, b) => a.reference.compareTo(b.reference));
    return result;
  }

  // ──────────────────────────────────────────────────────────────────────────
  // تحديد الصنف وطريقة الفتح والشكل حسب اللغة المختارة
  // ──────────────────────────────────────────────────────────────────────────
  static ({String type, String config, String shutterInfo}) _resolveTypeAndConfig({
    required Map<String, dynamic> item,
    required Map<String, dynamic> decodedMap,
    required WindowModel model,
    required AppLanguage lang,
  }) {
    final rawType = item['window_type']?.toString().trim() ?? '';
    final isShutterOnly = decodedMap['isShutterOnly'] == true ||
        rawType.toLowerCase().contains('volet') ||
        rawType.toLowerCase().contains('shutter') ||
        rawType.contains('ستار');

    final isMotor = model.shutterMechanism == 'محرك';
    final isCrank = model.shutterMechanism == 'منايفال' ||
        model.shutterMechanism == 'مانيفال' ||
        model.shutterMechanism == 'مانيفر';
    final mechLabel = isMotor
        ? (lang == AppLanguage.french ? 'Moteur' : (lang == AppLanguage.english ? 'Motor' : 'محرك'))
        : (isCrank
            ? (lang == AppLanguage.french ? 'Manivelle' : (lang == AppLanguage.english ? 'Crank' : 'منايفال'))
            : (lang == AppLanguage.french ? 'Sangle' : (lang == AppLanguage.english ? 'Belt' : 'حزام')));

    final hasShutter = model.hasShutter || isShutterOnly;
    final shutterInfo = hasShutter
        ? (lang == AppLanguage.french
            ? 'Volet : $mechLabel'
            : (lang == AppLanguage.english
                ? 'Shutter: $mechLabel'
                : 'مركب الستار : $mechLabel'))
        : '';

    if (isShutterOnly) {
      return (
        type: lang == AppLanguage.french
            ? 'Volet roulant'
            : (lang == AppLanguage.english ? 'Roller shutter' : 'ستار دوار'),
        config: '',
        shutterInfo: shutterInfo,
      );
    }

    final zonesList = (decodedMap['zones'] as List?) ?? [];
    final hasDoubleSash = zonesList.any(
      (z) => z is Map && z['content']?.toString() == 'doubleSash',
    );
    final hasSlidingSash = zonesList.any(
      (z) => z is Map && z['content']?.toString() == 'slidingSash',
    );
    final hasSingleSash = zonesList.any(
      (z) => z is Map && z['content']?.toString() == 'singleSash',
    );

    String typeStr = '';
    String configStr = '';

    final smartComp =
        DevisBuilder.generateSmartCompositionDescription(decodedMap, lang);
    if (smartComp.isNotEmpty) {
      typeStr = smartComp;
      configStr = '';
    } else if (hasSlidingSash) {
      typeStr = lang == AppLanguage.french
          ? 'Coulissant'
          : (lang == AppLanguage.english ? 'Sliding' : 'منزلق');
      final sashesCount = zonesList
          .where((z) => z is Map && z['content']?.toString() == 'slidingSash')
          .map((z) => (z as Map)['slidingSashesCount'] as num?)
          .whereType<num>()
          .fold<int>(0, (max, count) => count.toInt() > max ? count.toInt() : max);
      final effectiveSlidingSashes = sashesCount > 0 ? sashesCount : 2;
      configStr = switch (lang) {
        AppLanguage.french =>
          effectiveSlidingSashes == 1 ? '1 vantail' : '$effectiveSlidingSashes vantaux',
        AppLanguage.english =>
          effectiveSlidingSashes == 1 ? '1 sash' : '$effectiveSlidingSashes sashes',
        AppLanguage.arabic =>
          effectiveSlidingSashes == 1
              ? 'ضلفة واحدة'
              : effectiveSlidingSashes == 2
                  ? 'ضلفتين'
                  : '$effectiveSlidingSashes درفات',
      };
    } else if (hasDoubleSash) {
      typeStr = lang == AppLanguage.french
          ? 'Battant'
          : (lang == AppLanguage.english ? 'Casement' : 'مفصلي');
      configStr = lang == AppLanguage.french
          ? '2 vantaux'
          : (lang == AppLanguage.english ? 'Double sashes' : 'ضلفتين');
    } else if (hasSingleSash) {
      typeStr = lang == AppLanguage.french
          ? 'Battant'
          : (lang == AppLanguage.english ? 'Casement' : 'مفصلي');
      configStr = lang == AppLanguage.french
          ? '1 vantail'
          : (lang == AppLanguage.english ? 'Single sash' : 'ضلفة واحدة');
    } else {
      typeStr = rawType.isNotEmpty
          ? (lang != AppLanguage.arabic ? Localization.translate(rawType, lang) : rawType)
          : (lang == AppLanguage.french ? 'Fenêtre' : (lang == AppLanguage.english ? 'Window' : 'نافذة'));
    }

    return (type: typeStr, config: configStr, shutterInfo: shutterInfo);
  }

  // ──────────────────────────────────────────────────────────────────────────
  // مساعدات التصميم
  // ──────────────────────────────────────────────────────────────────────────
  static pw.Widget _hdr(
    String text,
    pw.Font fontBold, {
    pw.TextAlign align = pw.TextAlign.left,
  }) =>
      pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3.5),
        child: pw.Text(
          text,
          style: pw.TextStyle(font: fontBold, fontSize: 8, color: PdfColors.white),
          textAlign: align,
        ),
      );

  static pw.Widget _cell(
    String text,
    pw.Font font, {
    pw.Font? boldFont,
    bool bold = false,
    pw.TextAlign align = pw.TextAlign.left,
    double fontSize = 8,
  }) =>
      pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
        child: pw.Text(
          text,
          style: pw.TextStyle(
            font: bold ? (boldFont ?? font) : font,
            fontSize: fontSize,
          ),
          textAlign: align,
        ),
      );

  static pw.Widget _blueBar(
    String title,
    pw.Font fontBold, {
    PdfColor color = _kBlue,
    double fontSize = 10,
  }) =>
      pw.Container(
        padding: const pw.EdgeInsets.symmetric(vertical: 3.5, horizontal: 8),
        decoration: pw.BoxDecoration(color: color),
        child: pw.Text(
          title,
          style: pw.TextStyle(
            font: fontBold,
            fontSize: fontSize,
            color: PdfColors.white,
            letterSpacing: 1.2,
          ),
        ),
      );

  static String _anglesFor(BomItem item) {
    final text = '${item.originalName} ${item.name}'.toLowerCase();
    if (text.contains('45°/90°') ||
        text.contains('45° / 90°') ||
        text.contains('45/90')) return '45° / 90°';
    if (text.contains('90°/90°') ||
        text.contains('90° / 90°') ||
        text.contains('90/90') ||
        text.contains('slim') ||
        text.contains('سليم') ||
        text.contains('وصلة') ||
        text.contains('taquet') ||
        text.contains('lame') ||
        text.contains('axe') ||
        text.contains('caisson') ||
        text.contains('gliss') ||
        text.contains('الشرائح') ||
        text.contains('المحور') ||
        text.contains('الصندوق')) return '90° / 90°';
    return '45° / 45°';
  }

  static String _formatExplicitAngles(String value) {
    final numbers = RegExp(r'\d+')
        .allMatches(value)
        .map((match) => match.group(0))
        .toList();
    if (numbers.length >= 2) return '${numbers[0]}° / ${numbers[1]}°';
    return value;
  }

  static String anglesFor(BomItem item) => _anglesFor(item);

  static Map<String, bool> _activeVariants(WindowModel model) {
    final isTunnel = model.isCaissonTunnel;
    final isMotor = model.shutterMechanism == 'محرك';
    final isCrank = model.shutterMechanism == 'منايفال' ||
        model.shutterMechanism == 'مانيفال' ||
        model.shutterMechanism == 'مانيفر';
    final isBelt = !isMotor && !isCrank;
    return {
      'Verrou Central': model.canUseOpeningOnlyOptions && model.useVerrouCentral,
      'System OB': model.effectiveUseSystemOB,
      'Demi System OB': model.effectiveUseDemiOB,
      'كيت (Kit)': true,
      'طانديم (Tandem)': isTunnel,
      'الامبو (Embout)': isMotor,
      'سيبور رولمو (Support Roulement)': isMotor,
      'سيبور موتور (Support Moteur)': isMotor || isTunnel,
      'أغطية الشفرات (Bouchons Lames)':
          model.componentOverrides.containsKey('أغطية الشفرات (Bouchons Lames)'),
      'كيت فولي موتور (Kit Volet Moteur)': !isTunnel && isMotor,
      'كيت فولي مانيفر (Kit Volet Manivelle)': !isTunnel && isCrank,
      'كيت مانيفر (Kit Manivelle)': !isTunnel && isCrank,
      'كيت فولي (Kit Volet)': !isTunnel && isBelt,
      'كيت حزام (Kit Sangle)': !isTunnel && isBelt,
    };
  }

  static String _unit(String unit, AppLanguage lang) {
    final u = unit.trim().toLowerCase();
    if (lang == AppLanguage.french) {
      if (u == 'قطعة' || u == 'piece' || u == 'pièce') return 'U';
      if (u == 'قطاع' || u == 'بارة' || u == 'barre') return 'Barre';
      if (u == 'متر' || u == 'mètre' || u == 'metre' || u == 'm') return 'm';
      if (u == 'متر مربع' || u == 'm²') return 'm²';
      if (u == 'طقم' || u == 'jeu' || u == 'kit') return 'Jeu';
      return unit;
    } else if (lang == AppLanguage.english) {
      if (u == 'قطعة' || u == 'piece' || u == 'pièce') return 'Pcs';
      if (u == 'قطاع' || u == 'بارة' || u == 'bar') return 'Bar';
      if (u == 'متر' || u == 'mètre' || u == 'metre' || u == 'm') return 'm';
      if (u == 'متر مربع' || u == 'm²') return 'sqm';
      if (u == 'طقم' || u == 'jeu' || u == 'kit') return 'Set';
      return unit;
    }
    return unit;
  }

  static String _shortName(String name, [AppLanguage? lang]) {
    final lines = name
        .split('\n')
        .where((l) =>
            l.isNotEmpty &&
            !l.contains('المطلوب الفعلي') &&
            !l.contains('Besoin réel') &&
            !l.contains('Actual required'))
        .toList();
    var clean = lines.length >= 2
        ? lines[1].trim()
        : (lines.isNotEmpty ? lines[0].trim() : name.trim());

    if (clean.contains('براغي الباتمو') ||
        clean.contains('Vis Meneau') ||
        clean.contains('Batmo Screws')) {
      if (lang == AppLanguage.french) {
        return clean.contains('3.9')
            ? clean
                .replaceAll('براغي الباتمو', 'Vis Meneau')
                .replaceAll('Batmo Screws', 'Vis Meneau')
            : 'Vis Meneau 3.9×50';
      } else if (lang == AppLanguage.english) {
        return clean.contains('3.9')
            ? clean
                .replaceAll('براغي الباتمو', 'Batmo Screws')
                .replaceAll('Vis Meneau', 'Batmo Screws')
            : 'Batmo Screws 3.9×50';
      } else {
        return clean.contains('3.9') ? clean : 'براغي الباتمو 3.9*50';
      }
    }

    if (clean.contains('براغي التجميع') ||
        clean.contains("vis d'assemblage") ||
        clean.contains('Assembly screws')) {
      if (lang == AppLanguage.french) {
        return "Vis d'assemblage";
      } else if (lang == AppLanguage.english) {
        return 'Assembly screws';
      } else {
        return 'براغي التجميع';
      }
    }

    if (lang != null) {
      final translated = Localization.translate(clean, lang);
      if (translated.isNotEmpty && translated != clean) {
        return translated;
      }
    }
    return clean;
  }

  static double _num(Object? v, {double fb = 0}) {
    if (v is num) return v.toDouble();
    return double.tryParse(v?.toString().replaceAll(',', '.') ?? '') ?? fb;
  }

  static String _qty(double v) {
    if ((v - v.roundToDouble()).abs() < 0.000001) return v.round().toString();
    return v.toStringAsFixed(2);
  }

  // ──────────────────────────────────────────────────────────────────────────
  // توافق مع الكود القديم
  // ──────────────────────────────────────────────────────────────────────────
  /// @deprecated استخدم [generateFicheCoupe] مع PdfPreview بدلاً منه.
  static Future<void> generateAndPrintFicheCoupe({
    required Map<String, dynamic> order,
    required List<Map<String, dynamic>> items,
    required String workshopName,
    required SqlDatabase db,
    AppLanguage? language,
  }) async {
    final bytes = await generateFicheCoupe(
      order: order,
      items: items,
      workshopName: workshopName,
      db: db,
      language: language,
    );
    await Printing.layoutPdf(
      onLayout: (_) async => bytes,
      name: 'Fiche_Coupe_${order['id']}.pdf',
    );
  }
}

// ─── كلاس الترجمة المتكاملة حسب لغة التطبيق ───────────────────────────────────

class _Tr {
  final AppLanguage lang;
  const _Tr(this.lang);

  bool get isRtl => lang == AppLanguage.arabic;

  String get ficheDeCoupe => switch (lang) {
        AppLanguage.french => 'FICHE DE COUPE',
        AppLanguage.english => 'CUTTING SHEET',
        AppLanguage.arabic => 'ورقة التقطيع',
      };

  String get date => switch (lang) {
        AppLanguage.french => 'Date :',
        AppLanguage.english => 'Date:',
        AppLanguage.arabic => 'التاريخ :',
      };

  String get client => switch (lang) {
        AppLanguage.french => 'Client :',
        AppLanguage.english => 'Customer:',
        AppLanguage.arabic => 'العميل :',
      };

  String get commande => switch (lang) {
        AppLanguage.french => 'Commande : #',
        AppLanguage.english => 'Order: #',
        AppLanguage.arabic => 'رقم الطلبية : #',
      };

  String get saisiPar => switch (lang) {
        AppLanguage.french => 'Saisi par :',
        AppLanguage.english => 'Entered by:',
        AppLanguage.arabic => 'حرر من طرف :',
      };

  String article(int n) => switch (lang) {
        AppLanguage.french => 'ARTICLE $n',
        AppLanguage.english => 'ITEM $n',
        AppLanguage.arabic => 'عنصر $n',
      };

  String get gamme => switch (lang) {
        AppLanguage.french => 'Gamme :',
        AppLanguage.english => 'Series:',
        AppLanguage.arabic => 'السلسلة :',
      };

  String get couleur => switch (lang) {
        AppLanguage.french => 'Couleur :',
        AppLanguage.english => 'Color:',
        AppLanguage.arabic => 'اللون :',
      };

  String get qte => switch (lang) {
        AppLanguage.french => 'Qté :',
        AppLanguage.english => 'Qty:',
        AppLanguage.arabic => 'العدد :',
      };

  String get profils => switch (lang) {
        AppLanguage.french => 'PROFILS',
        AppLanguage.english => 'PROFILES',
        AppLanguage.arabic => 'القطاعات',
      };

  String get accessoires => switch (lang) {
        AppLanguage.french => 'ACCESSOIRES',
        AppLanguage.english => 'ACCESSORIES',
        AppLanguage.arabic => 'الإكسسوارات',
      };

  String get joints => switch (lang) {
        AppLanguage.french => 'JOINTS',
        AppLanguage.english => 'GASKETS',
        AppLanguage.arabic => 'المفاصل',
      };

  String get image => switch (lang) {
        AppLanguage.french => 'Image',
        AppLanguage.english => 'Image',
        AppLanguage.arabic => 'الصورة',
      };

  String get reference => switch (lang) {
        AppLanguage.french => 'Référence',
        AppLanguage.english => 'Reference',
        AppLanguage.arabic => 'المرجع',
      };

  String get designation => switch (lang) {
        AppLanguage.french => 'Désignation',
        AppLanguage.english => 'Description',
        AppLanguage.arabic => 'الوصف / التعيين',
      };

  String get quantite => switch (lang) {
        AppLanguage.french => 'Qté',
        AppLanguage.english => 'Qty',
        AppLanguage.arabic => 'الكمية',
      };

  String get longueur => switch (lang) {
        AppLanguage.french => 'Longueur',
        AppLanguage.english => 'Length',
        AppLanguage.arabic => 'الطول',
      };

  String get coupe => switch (lang) {
        AppLanguage.french => 'Coupe',
        AppLanguage.english => 'Cut Angle',
        AppLanguage.arabic => 'زاوية القطع',
      };

  String get unite => switch (lang) {
        AppLanguage.french => 'Unité',
        AppLanguage.english => 'Unit',
        AppLanguage.arabic => 'الوحدة',
      };

  String get longueurTotale => switch (lang) {
        AppLanguage.french => 'Longueur totale',
        AppLanguage.english => 'Total length',
        AppLanguage.arabic => 'الطول الإجمالي',
      };

  String page(int p, int t) => switch (lang) {
        AppLanguage.french => 'Page $p / $t',
        AppLanguage.english => 'Page $p of $t',
        AppLanguage.arabic => 'صفحة $p من $t',
      };
}

// ─── نماذج بيانات داخلية ──────────────────────────────────────────────────────

class _ArticleData {
  final String gamme;
  final String openingType;
  final String configuration;
  final String shutterInfo;
  final String colorName;
  final double width;
  final double height;
  final int qty;
  final List<BomItem> bomItems;
  final List<_ProfileCutRow> profiles;
  final Uint8List? drawing;

  const _ArticleData({
    required this.gamme,
    required this.openingType,
    required this.configuration,
    required this.shutterInfo,
    required this.colorName,
    required this.width,
    required this.height,
    required this.qty,
    required this.bomItems,
    required this.profiles,
    required this.drawing,
  });
}

class _CutPiece {
  final int qty;
  final int lengthMm;
  final String angles;

  const _CutPiece({
    required this.qty,
    required this.lengthMm,
    required this.angles,
  });
}

class _ProfileCutRow {
  final String reference;
  final String description;
  final pw.Widget? imageWidget;
  final List<_CutPiece> cuts;

  const _ProfileCutRow({
    required this.reference,
    required this.description,
    this.imageWidget,
    required this.cuts,
  });
}
