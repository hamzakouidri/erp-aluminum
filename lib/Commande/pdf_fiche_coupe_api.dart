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
import 'package:database_data/Commande/production_measurements.dart';
import 'package:database_data/settings/app_settings.dart';
import 'package:database_data/settings/localization.dart';
import 'package:database_data/services/pdf_font_cache.dart';
import 'package:database_data/services/pdf_branding.dart';
import 'package:bidi/bidi.dart' as bidi;
import 'package:database_data/arabic_reshaper/arabic_reshaper.dart';

// ─── ألوان التصميم ────────────────────────────────────────────────────────────
const _kBlue = PdfColor(0.051, 0.278, 0.631); // #0D47A1
const _kBlueSub = PdfColor(0.122, 0.467, 0.706); // #1F77B4
const _kRowAlt = PdfColor(0.950, 0.960, 0.980);
const _kBorder = PdfColor(0.788, 0.812, 0.843);

class PdfFicheCoupeApi {
  static bool _hasArabic(String text) {
    return text.runes.any(
      (r) => (r >= 0x0600 && r <= 0x06FF) || (r >= 0xFB50 && r <= 0xFEFF),
    );
  }

  static String _shapeText(String text) {
    if (!_hasArabic(text)) return text;
    return text
        .replaceAll('\r\n', '\n')
        .split('\n')
        .map((line) {
          if (!_hasArabic(line)) return line;
          final reshaped = ArabicReshaper.instance.reshape(line);
          return String.fromCharCodes(bidi.logicalToVisual(reshaped));
        })
        .join('\n');
  }

  static Future<
    ({
      Map<String, List<Map<String, dynamic>>> data,
      Map<String, bool> perLeaf,
      Map<String, Map<String, dynamic>> metadata,
      Map<String, double> prices,
    })
  >
  _loadKitBundleCache(SqlDatabase db) async {
    final data = <String, List<Map<String, dynamic>>>{};
    final perLeaf = <String, bool>{};
    final metadata = <String, Map<String, dynamic>>{};
    final prices = <String, double>{};
    try {
      final kits = await db.readKitBundles();
      await Future.wait(
        kits.map((kit) async {
          final name = kit['name']?.toString().trim() ?? '';
          final rawId = kit['id'];
          final id = rawId is num
              ? rawId.toInt()
              : int.tryParse(rawId?.toString() ?? '');
          if (name.isEmpty || id == null) return;
          final details = await db.readKitBundleItemsWithDetails(
            id,
            topLevelOnly: true,
          );
          data[name] = details
              .map((row) => Map<String, dynamic>.from(row))
              .toList();
          perLeaf[name] = (kit['per_leaf'] ?? 0) == 1;
          metadata[name] = Map<String, dynamic>.from(kit);
          final rawPrice = kit['price'];
          if (rawPrice is num && rawPrice > 0) {
            prices[name] = rawPrice.toDouble();
          }
        }),
      );
    } catch (_) {
      // The cutting sheet can still be generated for installations created
      // before configurable kits existed.
    }
    return (data: data, perLeaf: perLeaf, metadata: metadata, prices: prices);
  }

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

    final resolvedLanguage =
        language ??
        () {
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
      final map = savedWindowModelMap(item['partitions_json']);
      return !(map['isReplaced'] == true ||
          map['isReplaced']?.toString().toLowerCase() == 'true');
    }).toList();

    // كاش لصور المقاطع لتجنب إعادة التحميل المتكررة
    final imageCache = <String, pw.Widget?>{};
    final kitBundles = await _loadKitBundleCache(db);

    // تحميل بيانات كل منتج مع دمج القطع وصور المقاطع
    final articles = <_ArticleData>[];
    var nextWindowNumber = 1;
    for (final item in activeItems) {
      final articleQty = _num(
        item['quantity'],
        fb: 1,
      ).round().clamp(1, 999999).toInt();
      articles.add(
        await _loadArticle(
          db,
          item,
          resolvedLanguage,
          imageCache,
          firstWindowNumber: nextWindowNumber,
          kitBundleData: kitBundles.data,
          kitPerLeafMap: kitBundles.perLeaf,
          kitBundleMetadata: kitBundles.metadata,
          kitBundlePrices: kitBundles.prices,
        ),
      );
      nextWindowNumber += articleQty;
    }
    final showWindowNumbers = nextWindowNumber > 2;

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
    final clientName = '${order['firstname'] ?? ''} ${order['lastname'] ?? ''}'
        .trim();
    final commandeId = order['id']?.toString() ?? '';
    final enteredBy = order['username']?.toString() ?? '';

    final pdf = pw.Document();
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(20, 20, 20, 24),
        textDirection: pw.TextDirection.ltr,
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
                    style: pw.TextStyle(
                      font: font,
                      fontSize: 8,
                      color: PdfColors.grey600,
                    ),
                  ),
                  pw.Text(
                    _shapeText(tr.page(ctx.pageNumber, ctx.pagesCount)),
                    style: pw.TextStyle(
                      font: font,
                      fontSize: 8,
                      color: PdfColors.grey600,
                    ),
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
                showWindowNumbers: showWindowNumbers,
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
                    _shapeText(workshopName),
                    style: pw.TextStyle(
                      font: fontBold,
                      fontSize: 18,
                      color: _kBlue,
                    ),
                    textAlign: pw.TextAlign.center,
                  ),
                  pw.Text(
                    _shapeText(tr.ficheDeCoupe),
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
                      _shapeText(
                        [
                          if (address.isNotEmpty) address,
                          if (phone.isNotEmpty) 'Tél: $phone',
                        ].join(' | '),
                      ),
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
                  _shapeText('${tr.date} $orderDate'),
                  style: const pw.TextStyle(fontSize: 8.5),
                  textAlign: tr.isRtl ? pw.TextAlign.right : pw.TextAlign.left,
                ),
              ),
              if (enteredBy.isNotEmpty)
                pw.Expanded(
                  child: pw.Text(
                    _shapeText('${tr.saisiPar} $enteredBy'),
                    style: const pw.TextStyle(fontSize: 8.5),
                    textAlign: pw.TextAlign.center,
                  ),
                ),
              pw.Expanded(
                child: pw.Text(
                  _shapeText('${tr.client} $clientName'),
                  style: const pw.TextStyle(fontSize: 8.5),
                  textAlign: pw.TextAlign.center,
                ),
              ),
              pw.Expanded(
                child: pw.Text(
                  _shapeText('${tr.commande}$commandeId'),
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
    final style = pw.TextStyle(
      font: font,
      fontSize: 7.5,
      color: PdfColors.grey600,
    );
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
          pw.Text(_shapeText(workshopName), style: style),
          PdfBranding.footerMark(font),
          pw.Text(
            _shapeText(tr.page(ctx.pageNumber, ctx.pagesCount)),
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
    required bool showWindowNumbers,
  }) {
    final widgets = <pw.Widget>[];

    // ── 1. شريط عنوان المنتج ──
    widgets.add(
      _blueBar(tr.article(index), fontBold, fontSize: 10.5, isRtl: tr.isRtl),
    );
    widgets.add(pw.SizedBox(height: 3));

    // ── 2. سطر مواصفات المنتج بالترتيب المطلوب:
    // Gamme ثم Type ثم Configuration ثم Shutter ثم Couleur ثم Dimensions ثم Quantité
    final parts = <String>[];
    if (data.gamme.isNotEmpty) parts.add('${tr.gamme} ${data.gamme}');
    if (data.openingType.isNotEmpty) parts.add(data.openingType);
    if (data.configuration.isNotEmpty) parts.add(data.configuration);
    if (data.shutterInfo.isNotEmpty) parts.add(data.shutterInfo);
    if (data.colorName.isNotEmpty) parts.add('${tr.couleur} ${data.colorName}');
    parts.add(
      '${data.width.toStringAsFixed(0)} × ${data.height.toStringAsFixed(0)} mm',
    );
    parts.add('${tr.qte} ${data.qty}');

    widgets.add(
      pw.Container(
        padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 3.5),
        color: _kRowAlt,
        alignment: tr.isRtl
            ? pw.Alignment.centerRight
            : pw.Alignment.centerLeft,
        child: pw.Text(
          _shapeText(parts.join('   |   ')),
          style: pw.TextStyle(font: font, fontSize: 8.5),
          textAlign: tr.isRtl ? pw.TextAlign.right : pw.TextAlign.left,
        ),
      ),
    );
    widgets.add(pw.SizedBox(height: 8));

    // ── 3. الرسم وصور المقاطع ─────────────────────────────────────────────
    // الرسم يأخذ أكبر مساحة ممكنة يساراً، وصور المقاطع فقط تكون يمينه.
    // جداول القطع وباقي التفاصيل تأتي أسفل الاثنين بعرض الصفحة كاملاً.
    final accessories = data.bomItems
        .where(
          (b) =>
              b.isActive &&
              b.purchaseQuantity > 0 &&
              !_isShutterComponent(b) &&
              !(b.category.toLowerCase().trim() == 'profile' &&
                  b.pieces != null &&
                  b.pieces!.isNotEmpty) &&
              b.category.toLowerCase().trim() != 'joint',
        )
        .toList();
    final shutterAccessories = data.bomItems
        .where(
          (b) =>
              b.isActive &&
              b.purchaseQuantity > 0 &&
              _isShutterComponent(b) &&
              (b.pieces == null || b.pieces!.isEmpty),
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

    // عمود الرسم
    final pw.Widget drawingWidget = data.drawing != null
        ? pw.Image(pw.MemoryImage(data.drawing!), fit: pw.BoxFit.contain)
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

    // Keep the technical drawing large, while using its side column for the
    // complete accessory list. Profile images belong to the profile table.
    if (accessories.isNotEmpty) {
      widgets.add(
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              flex: 55,
              child: pw.Container(
                height: 255,
                padding: const pw.EdgeInsets.all(4),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: _kBorder, width: 0.5),
                  borderRadius: const pw.BorderRadius.all(
                    pw.Radius.circular(4),
                  ),
                ),
                child: drawingWidget,
              ),
            ),
            pw.SizedBox(width: 8),
            pw.Expanded(
              flex: 45,
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                children: [
                  _blueBar(
                    tr.accessoires,
                    fontBold,
                    color: _kBlueSub,
                    fontSize: 9,
                    isRtl: tr.isRtl,
                  ),
                  pw.SizedBox(height: 2),
                  _buildAccessoriesTable(
                    accessories,
                    font,
                    fontBold,
                    tr,
                    data.itemImages,
                    compact: true,
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    } else {
      widgets.add(
        pw.Center(
          child: pw.Container(
            width: PdfPageFormat.a4.availableWidth - 10,
            height: 300,
            padding: const pw.EdgeInsets.all(4),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: _kBorder, width: 0.5),
            ),
            child: drawingWidget,
          ),
        ),
      );
    }

    // Confirmed production sizes are the bridge between the drawing and the
    // cut rows. Keep the same window numbers here and in every profile cut so
    // the manager and workshop operator can verify them at a glance.
    if (data.measurements.isNotEmpty) {
      widgets.add(pw.SizedBox(height: 6));
      widgets.add(
        _buildConfirmedMeasurementsTable(
          data.measurements,
          font,
          fontBold,
          tr,
          showWindowNumbers: showWindowNumbers,
        ),
      );
    }

    final tablesBelow = <pw.Widget>[];
    if (data.profiles.isNotEmpty) {
      tablesBelow.add(
        _blueBar(
          tr.profils,
          fontBold,
          color: _kBlueSub,
          fontSize: 9,
          isRtl: tr.isRtl,
        ),
      );
      tablesBelow.add(pw.SizedBox(height: 2));
      tablesBelow.add(
        _buildProfilesTable(
          data.profiles,
          font,
          fontBold,
          tr,
          showWindowNumbers: showWindowNumbers,
        ),
      );
      tablesBelow.add(pw.SizedBox(height: 6));
    }
    if (data.shutterProfiles.isNotEmpty) {
      tablesBelow.add(
        _blueBar(
          tr.voletRoulant,
          fontBold,
          color: _kBlueSub,
          fontSize: 9,
          isRtl: tr.isRtl,
        ),
      );
      tablesBelow.add(pw.SizedBox(height: 2));
      tablesBelow.add(
        _buildProfilesTable(
          data.shutterProfiles,
          font,
          fontBold,
          tr,
          showWindowNumbers: showWindowNumbers,
        ),
      );
      if (shutterAccessories.isNotEmpty) {
        tablesBelow.add(pw.SizedBox(height: 3));
        tablesBelow.add(
          _buildAccessoriesTable(
            shutterAccessories,
            font,
            fontBold,
            tr,
            data.itemImages,
          ),
        );
      }
      tablesBelow.add(pw.SizedBox(height: 6));
    } else if (shutterAccessories.isNotEmpty) {
      tablesBelow.add(
        _blueBar(
          tr.voletRoulant,
          fontBold,
          color: _kBlueSub,
          fontSize: 9,
          isRtl: tr.isRtl,
        ),
      );
      tablesBelow.add(pw.SizedBox(height: 2));
      tablesBelow.add(
        _buildAccessoriesTable(
          shutterAccessories,
          font,
          fontBold,
          tr,
          data.itemImages,
        ),
      );
      tablesBelow.add(pw.SizedBox(height: 6));
    }
    if (joints.isNotEmpty) {
      tablesBelow.add(
        _blueBar(
          tr.joints,
          fontBold,
          color: _kBlueSub,
          fontSize: 9,
          isRtl: tr.isRtl,
        ),
      );
      tablesBelow.add(pw.SizedBox(height: 2));
      tablesBelow.add(
        _buildJointsTable(joints, font, fontBold, tr, data.itemImages),
      );
    }

    if (tablesBelow.isNotEmpty) {
      widgets.add(pw.SizedBox(height: 8));
      widgets.addAll(tablesBelow);
    }

    return widgets;
  }

  // ──────────────────────────────────────────────────────────────────────────
  // جدول الـ Profils:
  // لا نكرر العنصر مرتين! المرجع والوصف والصورة في سطر واحد،
  // والقياسات (العرض والارتفاع) تكون سطوراً فرعية داخل نفس السطر.
  // الأعمدة: المرجع | الوصف | الكمية | الطول | زاوية القطع
  // ──────────────────────────────────────────────────────────────────────────
  static pw.Widget _buildProfilesTable(
    List<_ProfileCutRow> rows,
    pw.Font font,
    pw.Font fontBold,
    _Tr tr, {
    required bool showWindowNumbers,
  }) {
    final colWidths = <int, pw.TableColumnWidth>{
      if (showWindowNumbers) 0: const pw.FixedColumnWidth(27), // رقم النافذة
      (showWindowNumbers ? 1 : 0): const pw.FixedColumnWidth(46), // الصورة
      (showWindowNumbers ? 2 : 1): const pw.FixedColumnWidth(62), // المرجع
      (showWindowNumbers ? 3 : 2): const pw.FlexColumnWidth(2.5), // الوصف
      (showWindowNumbers ? 4 : 3): const pw.FixedColumnWidth(32), // الكمية
      (showWindowNumbers ? 5 : 4): const pw.FixedColumnWidth(60), // الطول
      (showWindowNumbers ? 6 : 5): const pw.FixedColumnWidth(96), // زاوية القطع
    };

    final tableRows = <pw.TableRow>[];

    // ترويسة الجدول
    tableRows.add(
      pw.TableRow(
        decoration: const pw.BoxDecoration(color: _kBlue),
        children: [
          if (showWindowNumbers)
            _hdr('N°', fontBold, align: pw.TextAlign.center),
          _hdr(tr.image, fontBold, align: pw.TextAlign.center),
          _hdr(
            tr.reference,
            fontBold,
            align: tr.isRtl ? pw.TextAlign.right : pw.TextAlign.left,
          ),
          _hdr(
            tr.designation,
            fontBold,
            align: tr.isRtl ? pw.TextAlign.right : pw.TextAlign.left,
          ),
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
      final descriptionLines = row.description.split('\n').fold<int>(
        0,
        (sum, line) =>
            sum + (line.trim().length / 34).ceil().clamp(1, 99).toInt(),
      );
      final contentHeight = descriptionLines * 11.0 + 8.0;
      final cutsHeight = cutCount * 25.0;
      final totalRowHeight = contentHeight > cutsHeight
          ? contentHeight
          : cutsHeight;

      tableRows.add(
        pw.TableRow(
          decoration: pw.BoxDecoration(
            color: isAlt ? _kRowAlt : PdfColors.white,
          ),
          children: [
            if (showWindowNumbers)
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                children: [
                  for (var c = 0; c < cutCount; c++) ...[
                    if (c > 0) pw.Container(height: 0.5, color: _kBorder),
                    pw.Container(
                      height: 24.5,
                      alignment: pw.Alignment.center,
                      child: pw.Text(
                        row.cuts[c].windowNumber,
                        style: pw.TextStyle(font: fontBold, fontSize: 7.5),
                      ),
                    ),
                  ],
                ],
              ),
            // [0] صورة المقطع ضمن صفه في الجدول.
            pw.Container(
              height: totalRowHeight,
              alignment: pw.Alignment.center,
              padding: const pw.EdgeInsets.all(3),
              child: pw.Container(
                width: 40,
                height: 40,
                alignment: pw.Alignment.center,
                child: row.imageWidget ?? _defaultProfileIcon(size: 36),
              ),
            ),
            // [1] المرجع — يُكتب مرة واحدة فقط
            pw.Container(
              height: totalRowHeight,
              alignment: tr.isRtl
                  ? pw.Alignment.centerRight
                  : pw.Alignment.centerLeft,
              padding: const pw.EdgeInsets.symmetric(
                horizontal: 5,
                vertical: 2,
              ),
              child: pw.Text(
                _shapeText(row.reference.isNotEmpty ? row.reference : '-'),
                style: pw.TextStyle(font: fontBold, fontSize: 8.5),
                textAlign: tr.isRtl ? pw.TextAlign.right : pw.TextAlign.left,
              ),
            ),
            // [1] الوصف — يُكتب مرة واحدة فقط
            pw.Container(
              height: totalRowHeight,
              alignment: tr.isRtl
                  ? pw.Alignment.centerRight
                  : pw.Alignment.centerLeft,
              padding: const pw.EdgeInsets.symmetric(
                horizontal: 5,
                vertical: 2,
              ),
              child: _designationCell(
                row.description,
                font,
                fontBold,
                align: tr.isRtl ? pw.TextAlign.right : pw.TextAlign.left,
              ),
            ),
            // [2] الكمية — سطر لكل قياس داخل نفس الخلية
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
            // [3] الطول — سطر لكل قياس داخل نفس الخلية
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
            // [4] زاوية القطع مع المخطط — سطر لكل قياس داخل نفس الخلية
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

  static pw.Widget _buildConfirmedMeasurementsTable(
    List<_ConfirmedMeasurement> measurements,
    pw.Font font,
    pw.Font fontBold,
    _Tr tr, {
    required bool showWindowNumbers,
  }) {
    final title = switch (tr.lang) {
      AppLanguage.french => 'MESURES CONFIRMÉES',
      AppLanguage.english => 'CONFIRMED MEASUREMENTS',
      AppLanguage.arabic => 'القياسات المؤكدة',
    };
    final widthLabel = switch (tr.lang) {
      AppLanguage.french => 'Largeur',
      AppLanguage.english => 'Width',
      AppLanguage.arabic => 'العرض',
    };
    final heightLabel = switch (tr.lang) {
      AppLanguage.french => 'Hauteur',
      AppLanguage.english => 'Height',
      AppLanguage.arabic => 'الارتفاع',
    };
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        _blueBar(title, fontBold, color: _kBlueSub, fontSize: 8.5, isRtl: tr.isRtl),
        pw.SizedBox(height: 2),
        pw.Table(
          border: pw.TableBorder.all(color: _kBorder, width: 0.4),
          columnWidths: {
            if (showWindowNumbers) 0: const pw.FixedColumnWidth(44),
            (showWindowNumbers ? 1 : 0): const pw.FlexColumnWidth(),
            (showWindowNumbers ? 2 : 1): const pw.FlexColumnWidth(),
          },
          children: [
            pw.TableRow(
              decoration: const pw.BoxDecoration(color: _kRowAlt),
              children: [
                if (showWindowNumbers)
                  _cell('N°', fontBold, align: pw.TextAlign.center, bold: true, boldFont: fontBold),
                _cell(widthLabel, fontBold, align: pw.TextAlign.center, bold: true, boldFont: fontBold),
                _cell(heightLabel, fontBold, align: pw.TextAlign.center, bold: true, boldFont: fontBold),
              ],
            ),
            for (final measurement in measurements)
              pw.TableRow(
                children: [
                  if (showWindowNumbers)
                    _cell(measurement.windowNumber, fontBold, align: pw.TextAlign.center, bold: true, boldFont: fontBold),
                  _cell('${measurement.widthMm.toStringAsFixed(0)} mm', font, align: pw.TextAlign.center),
                  _cell('${measurement.heightMm.toStringAsFixed(0)} mm', font, align: pw.TextAlign.center),
                ],
              ),
          ],
        ),
      ],
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
    Map<String, pw.Widget?> itemImages, {
    bool compact = false,
  }) {
    final langCode = tr.lang == AppLanguage.french
        ? 'fr'
        : (tr.lang == AppLanguage.english ? 'en' : 'ar');
    final tableRows = <pw.TableRow>[
      pw.TableRow(
        decoration: const pw.BoxDecoration(color: _kBlue),
        children: [
          _hdr(tr.image, fontBold, align: pw.TextAlign.center),
          _hdr(
            tr.reference,
            fontBold,
            align: tr.isRtl ? pw.TextAlign.right : pw.TextAlign.left,
          ),
          _hdr(
            tr.designation,
            fontBold,
            align: tr.isRtl ? pw.TextAlign.right : pw.TextAlign.left,
          ),
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
            pw.Container(
              height: compact ? 28 : 34,
              alignment: pw.Alignment.center,
              padding: const pw.EdgeInsets.all(2),
              child:
                  itemImages[_bomImageKey(b)] ??
                  _defaultItemIcon(size: compact ? 22 : 28),
            ),
            _cell(
              b.profileCode ?? '-',
              font,
              align: tr.isRtl ? pw.TextAlign.right : pw.TextAlign.left,
            ),
            _designationCell(
              _accessoryTableDisplayName(b, localizedName, tr.lang),
              font,
              fontBold,
              align: tr.isRtl ? pw.TextAlign.right : pw.TextAlign.left,
            ),
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
      columnWidths: {
        0: pw.FixedColumnWidth(compact ? 28 : 38),
        1: pw.FixedColumnWidth(compact ? 48 : 70),
        2: const pw.FlexColumnWidth(3),
        3: pw.FixedColumnWidth(compact ? 30 : 40),
        4: pw.FixedColumnWidth(compact ? 34 : 45),
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
    Map<String, pw.Widget?> itemImages,
  ) {
    final langCode = tr.lang == AppLanguage.french
        ? 'fr'
        : (tr.lang == AppLanguage.english ? 'en' : 'ar');
    final tableRows = <pw.TableRow>[
      pw.TableRow(
        decoration: const pw.BoxDecoration(color: _kBlue),
        children: [
          _hdr(tr.image, fontBold, align: pw.TextAlign.center),
          _hdr(
            tr.reference,
            fontBold,
            align: tr.isRtl ? pw.TextAlign.right : pw.TextAlign.left,
          ),
          _hdr(
            tr.designation,
            fontBold,
            align: tr.isRtl ? pw.TextAlign.right : pw.TextAlign.left,
          ),
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
            pw.Container(
              height: 34,
              alignment: pw.Alignment.center,
              padding: const pw.EdgeInsets.all(2),
              child: itemImages[_bomImageKey(b)] ?? _defaultItemIcon(size: 28),
            ),
            _cell(
              b.profileCode ?? '-',
              font,
              align: tr.isRtl ? pw.TextAlign.right : pw.TextAlign.left,
            ),
            _designationCell(
              _jointDisplayName(b, localizedName, tr.lang),
              font,
              fontBold,
              align: tr.isRtl ? pw.TextAlign.right : pw.TextAlign.left,
            ),
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
        0: pw.FixedColumnWidth(38),
        1: pw.FixedColumnWidth(70),
        2: pw.FlexColumnWidth(3),
        3: pw.FixedColumnWidth(80),
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
      svg:
          '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 46 14">'
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
    String? inventoryItemType,
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
        final normalizedType = (inventoryItemType ?? '').toLowerCase();
        final table = normalizedType.contains('accessory')
            ? 'Accessories'
            : normalizedType.contains('shutter')
            ? 'ShutterComponents'
            : normalizedType.contains('joint')
            ? 'Joints'
            : normalizedType.contains('kit')
            ? 'KitBundles'
            : 'Sections';
        final rows = await database.query(
          table,
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

  static String _bomImageKey(BomItem item) =>
      '${item.inventoryItemType ?? ''}|${item.catalogItemId ?? ''}|'
      '${item.profileCode ?? ''}|${item.name}|${item.imagePath ?? ''}';

  /// أيقونة بديلة للمقطع عند عدم توفر الصورة
  static pw.Widget _defaultProfileIcon({double size = 24}) {
    return pw.SvgImage(
      svg:
          '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">'
          '<rect x="2" y="2" width="20" height="20" rx="2" fill="#edf2f9" stroke="#0d47a1" stroke-width="1.2"/>'
          '<rect x="6" y="6" width="12" height="12" rx="1" fill="#ffffff" stroke="#5c7ca8" stroke-width="0.8"/>'
          '<line x1="6" y1="12" x2="18" y2="12" stroke="#5c7ca8" stroke-width="0.6"/>'
          '</svg>',
      width: size,
      height: size,
    );
  }

  /// Neutral placeholder for accessories, glass and joints. It deliberately
  /// does not resemble an aluminium section when an item has no saved image.
  static pw.Widget _defaultItemIcon({double size = 24}) {
    return pw.SvgImage(
      svg:
          '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">'
          '<rect x="2" y="3" width="20" height="18" rx="2" fill="#f7f9fc" stroke="#8aa0bd" stroke-width="1"/>'
          '<circle cx="8" cy="9" r="2" fill="#b7c6d9"/>'
          '<path d="M4 18l5-5 3 3 3-4 5 6z" fill="#dce5f0" stroke="#8aa0bd" stroke-width=".6"/>'
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
    Map<String, pw.Widget?> imageCache, {
    required int firstWindowNumber,
    required Map<String, List<Map<String, dynamic>>> kitBundleData,
    required Map<String, bool> kitPerLeafMap,
    required Map<String, Map<String, dynamic>> kitBundleMetadata,
    required Map<String, double> kitBundlePrices,
  }) async {
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

      final active = <BomItem>[];
      final windowNumbersByItem = <BomItem, String>{};
      final confirmedMeasurements = <_ConfirmedMeasurement>[];
      final measurements = productionMeasurementInstances(
        item,
        quantityLimit: qty,
      );
      var measurementWindowNumber = firstWindowNumber;
      for (final measurement in measurements) {
        final instanceModel = WindowModel(db: db);
        applyWindowModelFromMap(instanceModel, decoded);
        instanceModel.copyCatalogRuntimeFrom(
          model,
          preserveCurrentSelections: false,
        );
        final measuredWidth = (measurement['width'] as num).toDouble();
        final measuredHeight = (measurement['height'] as num).toDouble();
        final measuredQty = (measurement['qty'] as num).toInt();
        final oldWidth = instanceModel.width;
        final oldHeight = instanceModel.height;
        if (instanceModel.zones.isNotEmpty && oldWidth > 0 && oldHeight > 0) {
          instanceModel.rescaleZones(
            oldWidth,
            oldHeight,
            measuredWidth,
            measuredHeight,
          );
        } else {
          instanceModel.width = measuredWidth;
          instanceModel.height = measuredHeight;
        }
        instanceModel.quantity = measuredQty;

        List<BomItem> generateBom() => ComponentCalculator.generateBom(
          instanceModel,
          _activeVariants(instanceModel),
          kitBundleData: kitBundleData,
          kitPerLeafMap: kitPerLeafMap,
          kitBundleMetadata: kitBundleMetadata,
          kitBundlePrices: kitBundlePrices,
        );

        var bom = generateBom();
        final engine = BomEngineV2(database: db);
        await engine.stabilizeSelections(window: instanceModel, items: bom);
        bom = generateBom();
        await engine.stabilizeSelections(window: instanceModel, items: bom);
        bom = await engine.filterItemsByAvailableCandidates(
          window: instanceModel,
          items: generateBom(),
        );
        final windowNumbers = [
          for (var offset = 0; offset < measuredQty; offset++)
            '${measurementWindowNumber + offset}',
        ];
        final windowNumber = windowNumbers.join(', ');
        for (final number in windowNumbers) {
          confirmedMeasurements.add(
            _ConfirmedMeasurement(
              windowNumber: number,
              widthMm: measuredWidth,
              heightMm: measuredHeight,
            ),
          );
        }
        final activeMeasurementItems = bom
            .where((r) => r.isActive && r.purchaseQuantity > 0)
            .toList(growable: false);
        active.addAll(activeMeasurementItems);
        for (final bomItem in activeMeasurementItems) {
          windowNumbersByItem[bomItem] = windowNumber;
        }
        measurementWindowNumber += measuredQty;
      }

      // The quantity table treats a configured shutter Kit as one collapsible
      // commercial row. The cutting sheet uses the same collapsed view: show
      // the exact selected Kit (including its selected caisson size), without
      // duplicating all of its internal children underneath it.
      final ficheItems = <BomItem>[];
      final collapsedShutterKits = <String>{};
      for (final bomItem in active) {
        final groupName = bomItem.kitGroupName?.trim() ?? '';
        final isShutterKit =
            bomItem.category.toLowerCase().trim() == 'shutter' &&
            groupName.isNotEmpty;
        if (!isShutterKit) {
          ficheItems.add(bomItem);
          continue;
        }
        if (!collapsedShutterKits.add(groupName)) continue;

        final metadata = kitBundleMetadata[groupName];
        final sizeMm =
            kitBundleSizeMm(metadata ?? {'name': groupName}) ??
            model.shutterBoxHeight;
        final hasSize = RegExp(
          r'(?<!\d)\d{2,3}(?:[.,]\d+)?(?!\d)',
        ).hasMatch(groupName);
        final sizeCm = sizeMm / 10.0;
        final sizeLabel = sizeCm == sizeCm.roundToDouble()
            ? sizeCm.toStringAsFixed(0)
            : sizeCm.toStringAsFixed(1);
        final exactKitName = hasSize ? groupName : '$groupName - $sizeLabel cm';
        ficheItems.add(
          BomItem(
            category: 'shutter',
            originalName: exactKitName,
            profileCode: metadata?['code']?.toString(),
            name: exactKitName,
            imagePath: metadata?['image_path']?.toString(),
            quantity: qty.toDouble(),
            unit: 'kit',
            unitPrice: kitBundlePrices[groupName] ?? 0,
            kitGroupName: groupName,
            catalogItemId: metadata?['id'] is num
                ? (metadata!['id'] as num).toInt()
                : int.tryParse('${metadata?['id'] ?? ''}'),
            inventoryItemType: 'KitBundle',
            selectorCategory: 'shutter',
            selectorType: 'كيت',
            roleKey: 'kit',
            materialType: 'shutter',
          ),
        );
      }
      final aggregatedFicheItems = _aggregateFicheItems(ficheItems);
      ficheItems
        ..clear()
        ..addAll(aggregatedFicheItems);

      final itemImages = <String, pw.Widget?>{};
      for (final bomItem in ficheItems) {
        itemImages[_bomImageKey(bomItem)] = await _loadSectionImage(
          code: bomItem.profileCode,
          name: bomItem.name,
          imagePath: bomItem.imagePath,
          db: db,
          catalogItemId: bomItem.catalogItemId,
          imageCache: imageCache,
          inventoryItemType: bomItem.inventoryItemType,
          size: 30,
        );
      }

      Uint8List? drawing;
      final storedShutterPosition = model.shutterPosition;
      try {
        // A fully lowered shutter hides the actual construction and turns the
        // cutting-sheet preview into a flat colour block. Keep the stored
        // value intact, but raise it for this technical preview so the slats,
        // frame and opening remain identifiable.
        if (model.hasShutter && model.shutterPosition > 0.42) {
          model.shutterPosition = 0.42;
        }
        drawing = await captureWindowImage(
          model,
          maxSide: 2400,
          showDrawingDimensions: true,
        );
      } catch (e, stackTrace) {
        // Keep the PDF usable with the dimension fallback, but retain the
        // actual capture error in logs instead of silently producing a blank
        // drawing page.
        print('Failed to capture cutting-sheet drawing: $e');
        print(stackTrace);
      } finally {
        model.shutterPosition = storedShutterPosition;
      }

      // استخراج معلومات النظام والفتح والشكل واللون ومركب الستار
      final resolved = _resolveTypeAndConfig(
        item: item,
        decodedMap: decoded,
        model: model,
        lang: lang,
      );
      final rawGamme = model.isShutterOnly
          ? 'Volet'
          : (model.activeSeries?.name ??
              model.activeSlidingSeries?.name ??
              item['game']?.toString() ??
              '');
      var gamme = Localization.translate(rawGamme, lang);
      if (lang != AppLanguage.arabic && _hasArabic(gamme)) {
        gamme = gamme
            .replaceAll(
              'سلسلة',
              lang == AppLanguage.french ? 'Gamme' : 'Series',
            )
            .replaceAll(
              'سلسله',
              lang == AppLanguage.french ? 'Gamme' : 'Series',
            )
            .replaceAll(
              'الستار',
              lang == AppLanguage.french ? 'Volet' : 'Shutter',
            )
            .trim();
        if (_hasArabic(gamme)) {
          final nonAr = gamme
              .replaceAll(RegExp(r'[\u0600-\u06FF\uFB50-\uFEFF]'), '')
              .trim();
          gamme = nonAr.isNotEmpty
              ? (lang == AppLanguage.french ? 'Gamme $nonAr' : 'Series $nonAr')
              : (lang == AppLanguage.french ? 'Standard' : 'Standard');
        }
      }

      final modelColor = model.selectedDbColor != null
          ? (model.selectedDbColor!['name']?.toString() ?? '')
          : model.frameColor.toString().split('.').last;
      final rawColor = item['color']?.toString().trim().isNotEmpty == true
          ? item['color'].toString().trim()
          : modelColor;
      var color = Localization.translate(rawColor, lang);
      if (lang != AppLanguage.arabic && _hasArabic(color)) {
        if (rawColor.contains('أبيض') || rawColor.contains('ابيض')) {
          color = lang == AppLanguage.french ? 'Blanc' : 'White';
        } else if (rawColor.contains('رمادي') || rawColor.contains('غري')) {
          color = lang == AppLanguage.french ? 'Gris' : 'Grey';
        } else if (rawColor.contains('أسود') || rawColor.contains('اسود')) {
          color = lang == AppLanguage.french ? 'Noir' : 'Black';
        } else if (rawColor.contains('بني') || rawColor.contains('مارو')) {
          color = lang == AppLanguage.french ? 'Marron' : 'Brown';
        } else if (rawColor.contains('بيج') || rawColor.contains('باج')) {
          color = lang == AppLanguage.french ? 'Beige' : 'Beige';
        } else if (rawColor.contains('خشب') || rawColor.contains('شين')) {
          color = lang == AppLanguage.french ? 'Chêne faux bois' : 'Wood grain';
        } else {
          final nonAr = color
              .replaceAll(RegExp(r'[\u0600-\u06FF\uFB50-\uFEFF]'), '')
              .trim();
          color = nonAr.isNotEmpty
              ? nonAr
              : (lang == AppLanguage.french ? 'Standard' : 'Standard');
        }
      }

      // فصل عناصر الستار عن قطاعات النوافذ
      final shutterBomItems = ficheItems.where(_isShutterComponent).toList();

      // تجميع القطاعات بدون تكرار السطر
      final profileRows = await _buildGroupedProfileRows(
        active
            .where((b) => b.category.toLowerCase().trim() == 'profile')
            .toList(),
        db,
        imageCache,
        lang,
        windowNumbersByItem: windowNumbersByItem,
      );

      final shutterProfileRows = await _buildGroupedProfileRows(
        active.where(_isShutterComponent).toList(),
        db,
        imageCache,
        lang,
        isShutter: true,
        windowNumbersByItem: windowNumbersByItem,
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
        bomItems: ficheItems,
        profiles: profileRows,
        shutterProfiles: shutterProfileRows,
        itemImages: itemImages,
        measurements: confirmedMeasurements,
        drawing: drawing,
      );
    } catch (_) {
      final rawGamme = item['game']?.toString() ?? '';
      var fallbackGamme = Localization.translate(rawGamme, lang);
      if (lang != AppLanguage.arabic && _hasArabic(fallbackGamme)) {
        fallbackGamme = lang == AppLanguage.french ? 'Standard' : 'Standard';
      }
      final rawColor = item['color']?.toString() ?? '';
      var fallbackColor = Localization.translate(rawColor, lang);
      if (lang != AppLanguage.arabic && _hasArabic(fallbackColor)) {
        fallbackColor = lang == AppLanguage.french ? 'Standard' : 'Standard';
      }
      return _ArticleData(
        gamme: fallbackGamme,
        openingType: '',
        configuration: '',
        shutterInfo: '',
        colorName: fallbackColor,
        width: width,
        height: height,
        qty: qty,
        bomItems: const [],
        profiles: const [],
        shutterProfiles: const [],
        itemImages: const {},
        drawing: null,
      );
    }
  }

  static bool _isShutterComponent(BomItem item) {
    final category = item.category.toLowerCase().trim();
    final inventoryType = (item.inventoryItemType ?? '').toLowerCase().trim();
    final selectorCategory = (item.selectorCategory ?? '').toLowerCase().trim();
    final materialType = (item.materialType ?? '').toLowerCase().trim();
    // Use BOM/catalog identity, not words contained in the visible name.
    // Name matching (lame/axe/caisson...) classified unrelated content rows
    // as shutter components when their selected database name happened to
    // contain one of those fragments.
    return category == 'shutter' ||
        category.contains('volet') ||
        inventoryType.contains('shutter') ||
        inventoryType.contains('volet') ||
        selectorCategory == 'shutter' ||
        selectorCategory.contains('volet') ||
        materialType == 'shutter' ||
        materialType.contains('volet');
  }

  /// Merge identical count-based materials generated by different confirmed
  /// measurement groups. Profiles keep their real cut lists; glass keeps its
  /// dimensions. Accessories with the same catalogue identity, colour and
  /// unit become one row (for example 324 + 64 rollers = 388 rollers).
  static List<BomItem> _aggregateFicheItems(List<BomItem> items) {
    final result = <BomItem>[];
    final indexByKey = <String, int>{};
    for (final item in items) {
      final hasCuts = item.pieces != null && item.pieces!.isNotEmpty;
      final category = item.category.trim().toLowerCase();
      if (hasCuts || category == 'profile') {
        result.add(item);
        continue;
      }
      final identity = item.catalogItemId != null && item.catalogItemId! > 0
          ? 'id:${item.inventoryItemType ?? category}:${item.catalogItemId}'
          : (item.profileCode ?? '').trim().isNotEmpty
          ? 'code:${item.profileCode!.trim().toLowerCase()}'
          : 'name:${item.name.replaceAll(RegExp(r'\s+'), ' ').trim().toLowerCase()}';
      final dimensionKey = category == 'glass' || category == 'panneau'
          ? '${item.length?.toStringAsFixed(3) ?? ''}x${item.glassHeight?.toStringAsFixed(3) ?? ''}'
          : '';
      final key = [
        category,
        identity,
        item.colorId ?? item.colorName?.trim().toLowerCase() ?? '',
        item.unit.trim().toLowerCase(),
        dimensionKey,
        item.kitGroupName ?? '',
      ].join('|');
      final existingIndex = indexByKey[key];
      if (existingIndex == null) {
        indexByKey[key] = result.length;
        result.add(item);
        continue;
      }
      final existing = result[existingIndex];
      result[existingIndex] = existing.copyWith(
        qty: existing.quantity + item.quantity,
        pieceCount: (existing.pieceCount ?? 0) + (item.pieceCount ?? 0),
      );
    }
    return result;
  }

  // ──────────────────────────────────────────────────────────────────────────
  // تجميع القطع لكل قطاع في سطر واحد
  // ──────────────────────────────────────────────────────────────────────────
  static Future<List<_ProfileCutRow>> _buildGroupedProfileRows(
    List<BomItem> bomItems,
    SqlDatabase db,
    Map<String, pw.Widget?> imageCache,
    AppLanguage lang, {
    bool isShutter = false,
    Map<BomItem, String> windowNumbersByItem = const {},
  }) async {
    final langCode = lang == AppLanguage.french
        ? 'fr'
        : (lang == AppLanguage.english ? 'en' : 'ar');

    // تجميع القطع حسب القطاع: (المرجع + الاسم)
    final profileMap =
        <
          String,
          ({
            String reference,
            String description,
            String? imagePath,
            int? catalogItemId,
            Set<String> productionNotes,
            Map<String, ({int qty, int lengthMm, String angles, String windowNumber})> cuts,
          })
        >{};

    for (final bom in bomItems) {
      final pieces = bom.pieces;
      if (!bom.isActive || pieces == null || pieces.isEmpty) continue;

      final ref = bom.profileCode ?? '';
      final localizedName = bom.getLocalizedName(langCode);
      var desc = _shortName(localizedName, lang);
      final roleLabel = desc;
      final catalogLines = bom.name
          .split('\n')
          .map((line) => line.trim())
          .where(
            (line) =>
                line.isNotEmpty &&
                !line.contains('المطلوب الفعلي') &&
                !line.contains('Besoin réel') &&
                !line.contains('Actual required'),
          )
          .toList();
      if (catalogLines.length > 1) {
        var exactCatalogName = catalogLines[1];
        if (ref.trim().isNotEmpty) {
          exactCatalogName = exactCatalogName.replaceFirst(
            RegExp('^${RegExp.escape(ref.trim())}\\s*[-–—:]\\s*'),
            '',
          );
        }
        if (exactCatalogName.isNotEmpty && exactCatalogName != roleLabel) {
          desc = '$roleLabel\n$exactCatalogName';
        }
      }
      if (isShutter) {
        final color = (bom.colorName ?? '').trim();
        if (color.isNotEmpty &&
            color.toLowerCase() != 'null' &&
            !desc.toLowerCase().contains(color.toLowerCase())) {
          desc = '$desc\n${_colorDetailLabel(color, lang)}';
        }
      }
      final key = '${ref.trim()}|${desc.trim()}';

      final existing = profileMap.putIfAbsent(
        key,
        () => (
          reference: ref,
          description: desc,
          imagePath: bom.imagePath,
          catalogItemId: bom.catalogItemId,
          productionNotes: <String>{},
          cuts: <String, ({int qty, int lengthMm, String angles, String windowNumber})>{},
        ),
      );
      final productionNote = bom.productionNote?.trim();
      if (productionNote != null && productionNote.isNotEmpty) {
        existing.productionNotes.add(productionNote);
      }

      for (var pieceIndex = 0; pieceIndex < pieces.length; pieceIndex++) {
        final pM = pieces[pieceIndex];
        final angles = isShutter
            ? '90° / 90°'
            : bom.pieceCutAngles != null &&
                  pieceIndex < bom.pieceCutAngles!.length &&
                  bom.pieceCutAngles![pieceIndex].trim().isNotEmpty
            ? _formatExplicitAngles(bom.pieceCutAngles![pieceIndex])
            : _anglesFor(bom);
        final mm = (pM * 1000).round();
        if (mm <= 0) continue;
        final windowNumber = windowNumbersByItem[bom] ?? '';
        final cutKey = '$windowNumber|$mm|$angles';
        final cur = existing.cuts[cutKey];
        if (cur != null) {
          existing.cuts[cutKey] = (
            qty: cur.qty + 1,
            lengthMm: mm,
            angles: angles,
            windowNumber: windowNumber,
          );
        } else {
          existing.cuts[cutKey] = (
            qty: 1,
            lengthMm: mm,
            angles: angles,
            windowNumber: windowNumber,
          );
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

      final sortedCuts =
          entry.cuts.values
              .map(
                (c) => _CutPiece(
                  qty: c.qty,
                  lengthMm: c.lengthMm,
                  angles: c.angles,
                  windowNumber: c.windowNumber,
                ),
              )
              .toList()
            ..sort((a, b) => b.lengthMm.compareTo(a.lengthMm));

      var description = entry.description;
      if (entry.productionNotes.isNotEmpty) {
        description = '$description\n${entry.productionNotes.join('\n')}';
      }

      result.add(
        _ProfileCutRow(
          reference: entry.reference,
          description: description,
          imageWidget: image,
          cuts: sortedCuts,
        ),
      );
    }

    if (isShutter) {
      int shutterRank(String text) {
        final t = text.toLowerCase();
        if (t.contains('caisson') || t.contains('صندوق')) return 1;
        if (t.contains('axe') || t.contains('محور')) return 2;
        if (t.contains('lame finale') || t.contains('نهائية')) return 4;
        if (t.contains('lame') || t.contains('شريحة') || t.contains('شرائح'))
          return 3;
        if (t.contains('coulisse') ||
            t.contains('gliss') ||
            t.contains('سكة') ||
            t.contains('سكك'))
          return 5;
        return 6;
      }

      result.sort((a, b) {
        final rA = shutterRank('${a.reference} ${a.description}');
        final rB = shutterRank('${b.reference} ${b.description}');
        if (rA != rB) return rA.compareTo(rB);
        return a.reference.compareTo(b.reference);
      });
    } else {
      result.sort((a, b) => a.reference.compareTo(b.reference));
    }
    return result;
  }

  // ──────────────────────────────────────────────────────────────────────────
  // تحديد الصنف وطريقة الفتح والشكل حسب اللغة المختارة
  // ──────────────────────────────────────────────────────────────────────────
  static ({String type, String config, String shutterInfo})
  _resolveTypeAndConfig({
    required Map<String, dynamic> item,
    required Map<String, dynamic> decodedMap,
    required WindowModel model,
    required AppLanguage lang,
  }) {
    final rawType = item['window_type']?.toString().trim() ?? '';
    final isShutterOnly =
        decodedMap['isShutterOnly'] == true ||
        rawType.toLowerCase().contains('volet') ||
        rawType.toLowerCase().contains('shutter') ||
        rawType.contains('ستار');

    final isMotor = model.shutterMechanism == 'محرك';
    final isCrank =
        model.shutterMechanism == 'منايفال' ||
        model.shutterMechanism == 'مانيفال' ||
        model.shutterMechanism == 'مانيفر';
    final mechLabel = isMotor
        ? (lang == AppLanguage.french
              ? 'Moteur'
              : (lang == AppLanguage.english ? 'Motor' : 'محرك'))
        : (isCrank
              ? (lang == AppLanguage.french
                    ? 'Manivelle'
                    : (lang == AppLanguage.english ? 'Crank' : 'منايفال'))
              : (lang == AppLanguage.french
                    ? 'Sangle'
                    : (lang == AppLanguage.english ? 'Belt' : 'حزام')));

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

    final smartComp = DevisBuilder.generateSmartCompositionDescription(
      decodedMap,
      lang,
    );
    if (smartComp.isNotEmpty &&
        (lang == AppLanguage.arabic || !_hasArabic(smartComp))) {
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
          .fold<int>(
            0,
            (max, count) => count.toInt() > max ? count.toInt() : max,
          );
      final effectiveSlidingSashes = sashesCount > 0 ? sashesCount : 2;
      configStr = switch (lang) {
        AppLanguage.french =>
          effectiveSlidingSashes == 1
              ? '1 vantail'
              : '$effectiveSlidingSashes vantaux',
        AppLanguage.english =>
          effectiveSlidingSashes == 1
              ? '1 sash'
              : '$effectiveSlidingSashes sashes',
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
      if (rawType.isNotEmpty) {
        if (lang == AppLanguage.french) {
          final translated = Localization.translate(rawType, lang);
          if (!_hasArabic(translated)) {
            typeStr = translated;
          } else if (rawType.contains('نافذة') || rawType.contains('شباك')) {
            typeStr = 'Fenêtre';
          } else if (rawType.contains('باب')) {
            typeStr = 'Porte';
          } else if (rawType.contains('ستار')) {
            typeStr = 'Volet roulant';
          } else {
            typeStr = 'Fenêtre';
          }
        } else if (lang == AppLanguage.english) {
          final translated = Localization.translate(rawType, lang);
          if (!_hasArabic(translated)) {
            typeStr = translated;
          } else if (rawType.contains('نافذة') || rawType.contains('شباك')) {
            typeStr = 'Window';
          } else if (rawType.contains('باب')) {
            typeStr = 'Door';
          } else if (rawType.contains('ستار')) {
            typeStr = 'Roller shutter';
          } else {
            typeStr = 'Window';
          }
        } else {
          typeStr = rawType;
        }
      } else {
        typeStr = lang == AppLanguage.french
            ? 'Fenêtre'
            : (lang == AppLanguage.english ? 'Window' : 'نافذة');
      }
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
  }) => pw.Padding(
    padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3.5),
    child: pw.Text(
      _shapeText(text),
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
  }) => pw.Padding(
    padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
    child: pw.Text(
      _shapeText(text),
      style: pw.TextStyle(
        font: bold ? (boldFont ?? font) : font,
        fontSize: fontSize,
      ),
      textAlign: align,
    ),
  );

  static pw.Widget _designationCell(
    String text,
    pw.Font font,
    pw.Font fontBold, {
    pw.TextAlign align = pw.TextAlign.left,
  }) {
    final lines = text
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    final title = lines.isEmpty ? '-' : lines.first;
    final details = lines.length > 1 ? lines.skip(1).toList() : <String>[];
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
      child: pw.Column(
        crossAxisAlignment: align == pw.TextAlign.right
            ? pw.CrossAxisAlignment.end
            : pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            _shapeText(title),
            style: pw.TextStyle(font: fontBold, fontSize: 8),
            textAlign: align,
          ),
          for (final detail in details) ...[
            pw.SizedBox(height: 1.5),
            pw.Text(
              _shapeText(detail),
              style: pw.TextStyle(
                font:
                    detail.contains('تنبيه') ||
                        detail.contains('Attention') ||
                        detail.contains('Warning') ||
                        detail.contains('المطلوب الفعلي') ||
                        detail.contains('Besoin réel') ||
                        detail.contains('Actual requirement')
                    ? fontBold
                    : font,
                fontSize: 6.8,
                color:
                    detail.contains('تنبيه') ||
                        detail.contains('Attention') ||
                        detail.contains('Warning')
                    ? PdfColors.orange800
                    : detail.contains('المطلوب الفعلي') ||
                          detail.contains('Besoin réel') ||
                          detail.contains('Actual requirement')
                    ? _kBlue
                    : PdfColors.grey600,
              ),
              textAlign: align,
            ),
          ],
        ],
      ),
    );
  }

  static pw.Widget _blueBar(
    String title,
    pw.Font fontBold, {
    PdfColor color = _kBlue,
    double fontSize = 10,
    bool isRtl = false,
  }) => pw.Container(
    padding: const pw.EdgeInsets.symmetric(vertical: 3.5, horizontal: 8),
    alignment: isRtl ? pw.Alignment.centerRight : pw.Alignment.centerLeft,
    decoration: pw.BoxDecoration(color: color),
    child: pw.Text(
      _shapeText(title),
      style: pw.TextStyle(
        font: fontBold,
        fontSize: fontSize,
        color: PdfColors.white,
        letterSpacing: 1.2,
      ),
      textAlign: isRtl ? pw.TextAlign.right : pw.TextAlign.left,
    ),
  );

  static String _anglesFor(BomItem item) {
    final text = '${item.originalName} ${item.name}'.toLowerCase();
    if (text.contains('45°/90°') ||
        text.contains('45° / 90°') ||
        text.contains('45/90'))
      return '45° / 90°';
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
        text.contains('الصندوق'))
      return '90° / 90°';
    return '45° / 45°';
  }

  static String _formatExplicitAngles(String value) {
    final numbers = RegExp(
      r'\d+',
    ).allMatches(value).map((match) => match.group(0)).toList();
    if (numbers.length >= 2) return '${numbers[0]}° / ${numbers[1]}°';
    return value;
  }

  static String anglesFor(BomItem item) => _anglesFor(item);

  static Map<String, bool> _activeVariants(WindowModel model) {
    final isTunnel = model.isCaissonTunnel;
    final isMotor = model.shutterMechanism == 'محرك';
    final isCrank =
        model.shutterMechanism == 'منايفال' ||
        model.shutterMechanism == 'مانيفال' ||
        model.shutterMechanism == 'مانيفر';
    final isBelt = !isMotor && !isCrank;
    return {
      'Verrou Central':
          model.canUseOpeningOnlyOptions && model.useVerrouCentral,
      'System OB': model.effectiveUseSystemOB,
      'Demi System OB': model.effectiveUseDemiOB,
      'كيت (Kit)': true,
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
      'كيت فولي (Kit Volet)': !isTunnel && isBelt,
      'كيت حزام (Kit Sangle)': !isTunnel && isBelt,
    };
  }

  static String _unit(String unit, AppLanguage lang) {
    final u = unit.trim().toLowerCase();
    if (lang == AppLanguage.french) {
      if (u == 'قطعة' ||
          u == 'حبة' ||
          u == 'piece' ||
          u == 'pièce' ||
          u == 'u' ||
          u == 'unité' ||
          u == 'unite')
        return 'U';
      if (u == 'قطاع' ||
          u == 'بارة' ||
          u == 'قضيب' ||
          u == 'barre' ||
          u == 'bar')
        return 'Barre';
      if (u == 'متر' ||
          u == 'متر طولي' ||
          u == 'متر خطي' ||
          u == 'mètre' ||
          u == 'metre' ||
          u == 'ml' ||
          u == 'm')
        return 'm';
      if (u == 'متر مربع' || u == 'm²' || u == 'm2' || u == 'sqm') return 'm²';
      if (u == 'طقم' ||
          u == 'علبة' ||
          u == 'مجموعة' ||
          u == 'jeu' ||
          u == 'kit' ||
          u == 'set' ||
          u == 'paquet' ||
          u == 'boite' ||
          u == 'boîte')
        return 'Jeu';
      if (u == 'كغ' ||
          u == 'كلغ' ||
          u == 'كيلو' ||
          u == 'كيلوغرام' ||
          u == 'kg')
        return 'kg';
      if (u == 'لتر' || u == 'l' || u == 'litre') return 'L';
      if (_hasArabic(unit)) return 'U';
      return unit;
    } else if (lang == AppLanguage.english) {
      if (u == 'قطعة' || u == 'حبة' || u == 'piece' || u == 'pièce' || u == 'u')
        return 'Pcs';
      if (u == 'قطاع' ||
          u == 'بارة' ||
          u == 'قضيب' ||
          u == 'bar' ||
          u == 'barre')
        return 'Bar';
      if (u == 'متر' ||
          u == 'متر طولي' ||
          u == 'mètre' ||
          u == 'metre' ||
          u == 'm')
        return 'm';
      if (u == 'متر مربع' || u == 'm²' || u == 'm2' || u == 'sqm') return 'sqm';
      if (u == 'طقم' || u == 'مجموعة' || u == 'jeu' || u == 'kit' || u == 'set')
        return 'Set';
      if (u == 'علبة' || u == 'box' || u == 'boite' || u == 'paquet')
        return 'Box';
      if (u == 'كغ' || u == 'كلغ' || u == 'kg') return 'kg';
      if (_hasArabic(unit)) return 'Pcs';
      return unit;
    } else {
      if (u == 'piece' || u == 'pièce' || u == 'u' || u == 'pcs') return 'قطعة';
      if (u == 'barre' || u == 'bar') return 'بارة';
      if (u == 'mètre' || u == 'metre' || u == 'm' || u == 'ml') return 'متر';
      if (u == 'm²' || u == 'm2' || u == 'sqm') return 'م²';
      if (u == 'jeu' || u == 'kit' || u == 'set') return 'طقم';
      if (u == 'box' || u == 'boite' || u == 'paquet') return 'علبة';
      if (u == 'kg') return 'كلغ';
      return unit;
    }
  }

  static String _accessoryDisplayName(
    BomItem item,
    String localizedName,
    AppLanguage lang,
  ) {
    final primary = _shortName(localizedName, lang);
    final sourceLines = item.name
        .split('\n')
        .map((line) => line.trim())
        .where(
          (line) =>
              line.isNotEmpty &&
              !line.contains('المطلوب الفعلي') &&
              !line.contains('Besoin réel') &&
              !line.contains('Actual required'),
        )
        .toList();

    // Accessory BOM rows store the selected catalogue item on the second
    // line as "code - exact database name".  The cutting sheet must show
    // that selected name, just like the quantity/cost table, rather than
    // replacing it with a generic role label such as Paumelles or Vis.
    String? catalogueDetail;
    for (final line in sourceLines.skip(1)) {
      if (line != item.originalName && line != localizedName) {
        catalogueDetail = line;
        break;
      }
    }

    if (catalogueDetail != null && catalogueDetail.isNotEmpty) {
      var exactName = catalogueDetail.trim();
      final reference = item.profileCode?.trim() ?? '';
      if (reference.isNotEmpty) {
        exactName = exactName.replaceFirst(
          RegExp('^${RegExp.escape(reference)}\\s*[-–—:]\\s*'),
          '',
        );
      }
      final searchable = '${item.originalName} ${item.name}'.toLowerCase();
      final isScrew =
          searchable.contains('vis') ||
          searchable.contains('براغ') ||
          searchable.contains('بلاغ');
      if (isScrew) {
        final dimension = RegExp(
          r'\d+(?:[.,]\d+)?\s*[x×*]\s*\d+(?:[.,]\d+)?',
          caseSensitive: false,
        ).firstMatch('${item.originalName} ${item.name}')?.group(0);
        if (dimension != null &&
            !exactName
                .replaceAll(' ', '')
                .contains(dimension.replaceAll(' ', ''))) {
          exactName = '$exactName $dimension';
        }
      }
      if (exactName.isNotEmpty) {
        return exactName == primary ? primary : '$primary\n$exactName';
      }
    }

    // Kit bundles already carry their exact configured database name as the
    // visible BOM name. Preserve it even when it contains words such as
    // "Kit Volet", which _shortName would otherwise collapse to a generic
    // translation.
    if (item.kitGroupName != null && sourceLines.isNotEmpty) {
      final exactName = sourceLines.first;
      return exactName == primary ? primary : '$primary\n$exactName';
    }

    final label = primary;

    final category = item.category.toLowerCase().trim();
    if (category == 'glass' || category == 'panneau') {
      final glassName =
          catalogueDetail ??
          sourceLines.firstWhere(
            (line) => line != item.originalName,
            orElse: () => '',
          );
      final glassPrefix = lang == AppLanguage.french
          ? 'Vitrage'
          : (lang == AppLanguage.english ? 'Glazing' : 'الزجاج');
      return glassName.isEmpty ? glassPrefix : '$glassPrefix - $glassName';
    }

    return label;
  }

  static String _colorDetailLabel(String color, AppLanguage lang) {
    return switch (lang) {
      AppLanguage.french => 'Couleur : $color',
      AppLanguage.english => 'Color: $color',
      AppLanguage.arabic => 'اللون: $color',
    };
  }

  static String _accessoryTableDisplayName(
    BomItem item,
    String localizedName,
    AppLanguage lang,
  ) {
    var label = _accessoryDisplayName(item, localizedName, lang);
    if (!_isShutterComponent(item)) return label;
    final color = (item.colorName ?? '').trim();
    if (color.isEmpty ||
        color.toLowerCase() == 'null' ||
        label.toLowerCase().contains(color.toLowerCase())) {
      return label;
    }
    return '$label\n${_colorDetailLabel(color, lang)}';
  }

  static String _jointDisplayName(
    BomItem item,
    String localizedName,
    AppLanguage lang,
  ) {
    final role = _shortName(localizedName, lang);
    final lines = item.name
        .split('\n')
        .map((line) => line.trim())
        .where(
          (line) =>
              line.isNotEmpty &&
              !line.contains('المطلوب الفعلي') &&
              !line.contains('Besoin réel') &&
              !line.contains('Actual required'),
        )
        .toList();
    if (lines.length < 2) return role;
    var exactName = lines[1];
    final reference = item.profileCode?.trim() ?? '';
    if (reference.isNotEmpty) {
      exactName = exactName.replaceFirst(
        RegExp('^${RegExp.escape(reference)}\\s*[-–—:]\\s*'),
        '',
      );
    }
    if (exactName.isEmpty || exactName == role) return role;
    return '$role\n$exactName';
  }

  static String _shortName(String name, [AppLanguage? lang]) {
    final targetLang = lang ?? AppLanguage.french;
    final lines = name
        .split('\n')
        .map((l) => l.trim())
        .where(
          (l) =>
              l.isNotEmpty &&
              !l.contains('المطلوب الفعلي') &&
              !l.contains('Besoin réel') &&
              !l.contains('Actual required'),
        )
        .toList();

    String clean;
    if (targetLang == AppLanguage.arabic) {
      clean = lines.firstWhere(
        (l) => _hasArabic(l),
        orElse: () => lines.isNotEmpty ? lines.first : name.trim(),
      );
    } else {
      clean = lines.firstWhere(
        (l) => !_hasArabic(l),
        orElse: () => lines.isNotEmpty ? lines.first : name.trim(),
      );
    }

    if (targetLang != AppLanguage.arabic && _hasArabic(clean)) {
      final parenMatch = RegExp(r'\(([^)]+)\)').firstMatch(clean);
      if (parenMatch != null) {
        final inside = parenMatch.group(1)!.trim();
        if (!_hasArabic(inside)) {
          clean = inside;
        }
      }
    }

    final lowerClean = clean.toLowerCase();

    // ── 1. براغي ومثبتات ──
    if (lowerClean.contains('vis meneau') ||
        clean.contains('براغي الباتمو') ||
        lowerClean.contains('batmo screw')) {
      if (targetLang == AppLanguage.french) {
        return clean.contains('3.9')
            ? clean
                  .replaceAll('براغي الباتمو', 'Vis Meneau')
                  .replaceAll('Batmo Screws', 'Vis Meneau')
                  .replaceAll('batmo screw', 'Vis Meneau')
            : 'Vis Meneau 3.9×50';
      } else if (targetLang == AppLanguage.english) {
        return clean.contains('3.9')
            ? clean
                  .replaceAll('براغي الباتمو', 'Batmo Screws')
                  .replaceAll('Vis Meneau', 'Batmo Screws')
            : 'Batmo Screws 3.9×50';
      } else {
        return clean.contains('3.9') ? clean : 'براغي الباتمو 3.9*50';
      }
    }

    if (lowerClean.contains("vis d'assemblage") ||
        clean.contains('براغي التجميع') ||
        lowerClean.contains('assembly screw')) {
      if (targetLang == AppLanguage.french) return "Vis d'assemblage";
      if (targetLang == AppLanguage.english) return 'Assembly screws';
      return 'براغي التجميع';
    }

    if (clean.contains('براغي حديد الدعم') ||
        clean.contains('براغي التدعيم') ||
        lowerClean.contains('vis renfort')) {
      if (targetLang == AppLanguage.french) return 'Vis Renfort 3.9×38';
      if (targetLang == AppLanguage.english)
        return 'Reinforcement Screws 3.9×38';
      return 'براغي تدعيم 3.9×38';
    }

    if (clean.contains('براغي الصندوق') || lowerClean.contains('vis caisson')) {
      if (targetLang == AppLanguage.french) return 'Vis Caisson';
      if (targetLang == AppLanguage.english) return 'Box Screws';
      return 'براغي الصندوق';
    }

    if (clean.contains('براغي الإكسسوارات') ||
        lowerClean.contains('vis accessoire')) {
      if (targetLang == AppLanguage.french) return 'Vis Accessoires';
      if (targetLang == AppLanguage.english) return 'Accessory Screws';
      return 'براغي الإكسسوارات';
    }

    // ── 2. مركبات الستار الدوار (Caisson, Axe, Lames, Coulisses, Attache, etc.) ──
    if (lowerClean.contains('caisson') ||
        clean.contains('الصندوق') ||
        clean.contains('كيسون')) {
      return targetLang == AppLanguage.french
          ? 'Caisson'
          : (targetLang == AppLanguage.english
                ? 'Box / Caisson'
                : 'الكيسون (الصندوق)');
    }
    if (lowerClean.contains('lame finale') ||
        clean.contains('الشريحة النهائية') ||
        clean.contains('لام فينال')) {
      return targetLang == AppLanguage.french
          ? 'Lame finale'
          : (targetLang == AppLanguage.english
                ? 'Bottom slat'
                : 'اللام فينال (الشريحة النهائية)');
    }
    if (lowerClean.contains('lame') ||
        clean.contains('الشرائح') ||
        clean.contains('الشفرات') ||
        clean.contains('اللام')) {
      return targetLang == AppLanguage.french
          ? 'Lames'
          : (targetLang == AppLanguage.english ? 'Slats' : 'اللام (الشرائح)');
    }
    if (lowerClean.contains('axe') ||
        clean.contains('المحور') ||
        clean.contains('لاكس')) {
      return targetLang == AppLanguage.french
          ? 'Axe'
          : (targetLang == AppLanguage.english
                ? 'Tube / Axle'
                : 'اللاكس (المحور)');
    }
    if (lowerClean.contains('coulisse') ||
        (lowerClean.contains('gliss') && !lowerClean.contains('coulissant')) ||
        clean.contains('السكك') ||
        clean.contains('كليسير') ||
        clean.contains('غليسير')) {
      return targetLang == AppLanguage.french
          ? 'Coulisses / Glissières'
          : (targetLang == AppLanguage.english
                ? 'Guide rails'
                : 'الڭليسيرات (السكك)');
    }
    if (lowerClean.contains('attache') || clean.contains('أطاش')) {
      return targetLang == AppLanguage.french
          ? 'Attache tablier'
          : (targetLang == AppLanguage.english
                ? 'Shutter clip'
                : 'أطاش (Attache)');
    }
    if (lowerClean.contains('embout') || clean.contains('الامبو')) {
      return targetLang == AppLanguage.french
          ? 'Embout'
          : (targetLang == AppLanguage.english ? 'End cap' : 'الامبو (Embout)');
    }
    if (lowerClean.contains('tandem') || clean.contains('طانديم')) {
      return targetLang == AppLanguage.french
          ? 'Tandem'
          : (targetLang == AppLanguage.english ? 'Tandem' : 'طانديم (Tandem)');
    }
    if (lowerClean.contains('support moteur') ||
        clean.contains('سيبور موتور')) {
      return targetLang == AppLanguage.french
          ? 'Support Moteur'
          : (targetLang == AppLanguage.english
                ? 'Motor Support'
                : 'سيبور موتور');
    }
    if (lowerClean.contains('support roulement') ||
        clean.contains('سيبور رولمو')) {
      return targetLang == AppLanguage.french
          ? 'Support Roulement'
          : (targetLang == AppLanguage.english
                ? 'Bearing Support'
                : 'سيبور رولمو');
    }
    if (lowerClean.contains('bouchon lame') ||
        clean.contains('أغطية الشفرات')) {
      return targetLang == AppLanguage.french
          ? 'Bouchons Lames'
          : (targetLang == AppLanguage.english
                ? 'Slat End Caps'
                : 'أغطية الشفرات');
    }
    if (lowerClean.contains('kit volet moteur') ||
        clean.contains('كيت فولي موتور')) {
      return targetLang == AppLanguage.french
          ? 'Kit Volet Moteur'
          : (targetLang == AppLanguage.english
                ? 'Motorized Shutter Kit'
                : 'كيت فولي موتور');
    }
    if (lowerClean.contains('kit volet manivelle') ||
        clean.contains('كيت فولي مانيفر') ||
        clean.contains('كيت مانيفر')) {
      return targetLang == AppLanguage.french
          ? 'Kit Volet Manivelle'
          : (targetLang == AppLanguage.english
                ? 'Crank Shutter Kit'
                : 'كيت فولي مانيفر');
    }
    if (lowerClean.contains('kit volet') || clean.contains('كيت فولي')) {
      return targetLang == AppLanguage.french
          ? 'Kit Volet'
          : (targetLang == AppLanguage.english ? 'Shutter Kit' : 'كيت فولي');
    }
    if (lowerClean.contains('kit sangle') || clean.contains('كيت حزام')) {
      return targetLang == AppLanguage.french
          ? 'Kit Sangle'
          : (targetLang == AppLanguage.english ? 'Belt Kit' : 'كيت حزام');
    }

    // ── 3. قطاعات النوافذ والأبواب ──
    if (lowerClean.contains('cache dormant') ||
        clean.contains('كاش دورمو') ||
        clean.contains('كاش الإطار')) {
      return targetLang == AppLanguage.french
          ? 'Cache dormant'
          : (targetLang == AppLanguage.english ? 'Frame Cover' : 'كاش دورمو');
    }
    if (lowerClean.contains('seuil') ||
        clean.contains('سوي') ||
        clean.contains('عتبة')) {
      return targetLang == AppLanguage.french
          ? 'Seuil'
          : (targetLang == AppLanguage.english ? 'Threshold' : 'سوي');
    }
    if (lowerClean.contains('cache-rail') ||
        lowerClean.contains('cache rail') ||
        clean.contains('كاش راي')) {
      return targetLang == AppLanguage.french
          ? 'Cache-rail'
          : (targetLang == AppLanguage.english ? 'Rail Cover' : 'كاش راي');
    }
    if (lowerClean.contains('chicane') || clean.contains('شيكان')) {
      final isReinf = lowerClean.contains('renforc') || clean.contains('معزز');
      if (isReinf) {
        return targetLang == AppLanguage.french
            ? 'Chicane Renforcée'
            : (targetLang == AppLanguage.english
                  ? 'Reinforced Chicane'
                  : 'شيكان معزز');
      }
      return targetLang == AppLanguage.french
          ? 'Chicane'
          : (targetLang == AppLanguage.english ? 'Chicane' : 'شيكان');
    }
    // Gâche names frequently contain "ouvrant" as a qualifier (for example
    // "Gache double ouvrant"). Classify the accessory before the generic
    // opening-profile rule below, otherwise its heading becomes "Ouvrant".
    if (lowerClean.contains('gache') ||
        lowerClean.contains('gâche') ||
        clean.contains('قاش') ||
        clean.contains('كاش')) {
      return targetLang == AppLanguage.french
          ? 'Gâche'
          : (targetLang == AppLanguage.english ? 'Strike plate' : 'قاش');
    }
    if (lowerClean.contains('dormant') || clean.contains('إطار')) {
      return targetLang == AppLanguage.french
          ? 'Dormant'
          : (targetLang == AppLanguage.english ? 'Frame' : 'إطار');
    }
    if (lowerClean.contains('ouvrant') ||
        clean.contains('ضلفة') ||
        clean.contains('ظلفة')) {
      return targetLang == AppLanguage.french
          ? 'Ouvrant'
          : (targetLang == AppLanguage.english ? 'Sash' : 'ضلفة');
    }
    if (lowerClean.contains('parclose') ||
        clean.contains('باركلوز') ||
        clean.contains('بارك لوز')) {
      return targetLang == AppLanguage.french
          ? 'Parclose'
          : (targetLang == AppLanguage.english ? 'Glazing bead' : 'باركلوز');
    }
    if (lowerClean.contains('battement') || clean.contains('باتمو')) {
      return targetLang == AppLanguage.french
          ? 'Battement'
          : (targetLang == AppLanguage.english ? 'Meeting stile' : 'باتمو');
    }

    // ── 4. الإكسسوارات والمفاصل ──
    if (lowerClean.contains('poignée') ||
        lowerClean.contains('handle') ||
        clean.contains('مقبض')) {
      if (lowerClean.contains('couliss') || clean.contains('منزلق')) {
        return targetLang == AppLanguage.french
            ? 'Poignée Coulissante'
            : (targetLang == AppLanguage.english
                  ? 'Sliding Handle'
                  : 'مقبض منزلق');
      }
      if (lowerClean.contains('porte') || clean.contains('باب')) {
        return targetLang == AppLanguage.french
            ? 'Poignée Porte'
            : (targetLang == AppLanguage.english ? 'Door Handle' : 'مقبض باب');
      }
      return targetLang == AppLanguage.french
          ? 'Poignée Fenêtre'
          : (targetLang == AppLanguage.english ? 'Window Handle' : 'مقبض');
    }
    if (lowerClean.contains('serrure') || clean.contains('قفل')) {
      return targetLang == AppLanguage.french
          ? 'Serrure'
          : (targetLang == AppLanguage.english ? 'Lock' : 'قفل');
    }
    if (lowerClean.contains('canon') || clean.contains('أسطوانة')) {
      return targetLang == AppLanguage.french
          ? 'Canon'
          : (targetLang == AppLanguage.english ? 'Cylinder' : 'الأسطوانة');
    }
    if (lowerClean.contains('paumelle') ||
        lowerClean.contains('hinge') ||
        clean.contains('مفصل')) {
      return targetLang == AppLanguage.french
          ? 'Paumelles'
          : (targetLang == AppLanguage.english ? 'Hinges' : 'مفصلات');
    }
    if (lowerClean.contains('roulette') || clean.contains('عجلات')) {
      return targetLang == AppLanguage.french
          ? 'Roulettes'
          : (targetLang == AppLanguage.english ? 'Rollers' : 'عجلات');
    }
    if (lowerClean.contains('verrou') || clean.contains('فيرو')) {
      return targetLang == AppLanguage.french
          ? 'Verrou'
          : (targetLang == AppLanguage.english ? 'Flush bolt' : 'فيرو');
    }
    if (lowerClean.contains('crémone') ||
        lowerClean.contains('cremone') ||
        clean.contains('كريمون')) {
      return targetLang == AppLanguage.french
          ? 'Crémone'
          : (targetLang == AppLanguage.english ? 'Cremone' : 'كريمون');
    }
    if (lowerClean.contains('tringle') || clean.contains('تراينغل')) {
      return targetLang == AppLanguage.french
          ? 'Tringle crémone'
          : (targetLang == AppLanguage.english ? 'Cremone rod' : 'قضيب كريمون');
    }
    if (lowerClean.contains('joint brosse') || clean.contains('جوان بروس')) {
      return targetLang == AppLanguage.french
          ? 'Joint brosse'
          : (targetLang == AppLanguage.english ? 'Brush gasket' : 'جوان بروس');
    }
    if (lowerClean.contains('joint') || clean.contains('جوان')) {
      return targetLang == AppLanguage.french
          ? 'Joint'
          : (targetLang == AppLanguage.english ? 'Gasket' : 'جوان');
    }

    final translated = Localization.translate(clean, targetLang);
    if (translated.isNotEmpty && translated != clean) {
      if (targetLang != AppLanguage.arabic && _hasArabic(translated)) {
        final nonAr = translated
            .replaceAll(RegExp(r'[\u0600-\u06FF\uFB50-\uFEFF]'), '')
            .trim();
        if (nonAr.isNotEmpty) return nonAr;
      } else {
        return translated;
      }
    }

    if (targetLang != AppLanguage.arabic && _hasArabic(clean)) {
      final nonAr = clean
          .replaceAll(RegExp(r'[\u0600-\u06FF\uFB50-\uFEFF\(\)]'), '')
          .trim();
      if (nonAr.isNotEmpty) return nonAr;
      return targetLang == AppLanguage.french ? 'Accessoire' : 'Accessory';
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

  String get voletRoulant => switch (lang) {
    AppLanguage.french => 'VOLET ROULANT',
    AppLanguage.english => 'ROLLER SHUTTER',
    AppLanguage.arabic => 'مركبات الستار',
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
  final List<_ProfileCutRow> shutterProfiles;
  final Map<String, pw.Widget?> itemImages;
  final List<_ConfirmedMeasurement> measurements;
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
    this.shutterProfiles = const [],
    this.itemImages = const {},
    this.measurements = const [],
    required this.drawing,
  });
}

class _ConfirmedMeasurement {
  final String windowNumber;
  final double widthMm;
  final double heightMm;

  const _ConfirmedMeasurement({
    required this.windowNumber,
    required this.widthMm,
    required this.heightMm,
  });
}

class _CutPiece {
  final int qty;
  final int lengthMm;
  final String angles;
  final String windowNumber;

  const _CutPiece({
    required this.qty,
    required this.lengthMm,
    required this.angles,
    required this.windowNumber,
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
