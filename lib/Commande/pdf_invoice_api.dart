import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:bidi/bidi.dart' as bidi;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';
import '../settings/localization.dart';
import '../settings/app_settings.dart';
import '../arabic_reshaper/arabic_reshaper.dart';
import 'package:printing/printing.dart';
import 'devis_builder.dart';

class PdfInvoiceApi {
  static AppLanguage _currentLang = AppLanguage.arabic;

  static String t(String key) => Localization.translate(key, _currentLang);

  static const PdfColor _blue = PdfColor.fromInt(0xFF1976D2);

  // ── Font cache (Amiri: full Arabic + Latin support) ──────────────────────
  // Cairo-Regular.ttf in this project is Latin-ONLY (0 Arabic glyphs).
  // Amiri supports Arabic block (0600-06FF), Pres Forms-A (FB50) & -B (FE70).
  static pw.Font? _cachedFont;
  static pw.Font? _cachedFontBold;
  static Future<void>? _preloadFuture; // singleton: prevents duplicate loads

  /// Call this once when the invoice screen opens (runs in background).
  static Future<void> preloadFonts() async {
    _preloadFuture ??= _doPreloadFonts().catchError((e) {
      print('PdfInvoiceApi: Font preloading failed: $e');
      _preloadFuture = null; // Clear so we can retry on next attempt
      throw e;
    });
    return _preloadFuture!;
  }

  static Future<void> _doPreloadFonts() async {
    try {
      print('PdfInvoiceApi: Preloading Amiri fonts from assets...');
      final regular = await rootBundle.load('assets/fonts/Amiri-Regular.ttf');
      print('PdfInvoiceApi: Loaded Amiri-Regular.ttf successfully.');
      final bold = await rootBundle.load('assets/fonts/Amiri-Bold.ttf');
      print('PdfInvoiceApi: Loaded Amiri-Bold.ttf successfully.');
      _cachedFont = pw.Font.ttf(regular);
      _cachedFontBold = pw.Font.ttf(bold);
      print('PdfInvoiceApi: Font preloading completed successfully.');
    } catch (e, stack) {
      print('PdfInvoiceApi: Error preloading fonts: $e');
      print(stack);
      rethrow;
    }
  }

  static Future<void> generateAndPrintInvoice({required DevisData data}) async {
    final bytes = await buildPdfBytes(data);
    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => bytes,
      name: 'devis_${data.orderId}.pdf',
    );
  }

  static Future<Uint8List> buildPdfBytes(
    DevisData data, {
    AppLanguage? overrideLang,
    bool imageUnderPrices = false,
  }) async {
    if (overrideLang != null) {
      _currentLang = overrideLang;
    } else {
      final prefs = await SharedPreferences.getInstance();
      final langIndex = prefs.getInt('app_language') ?? 0;
      _currentLang = AppLanguage.values[langIndex];
    }

    await preloadFonts();
    final font = _cachedFont!;
    final fontBold = _cachedFontBold!;

    if (data.documentTitleKey == 'BON_CHARGE') {
      return _buildBonDeChargePdf(data, font, fontBold);
    }

    final pdf = pw.Document();

    final bool isOfficial =
        data.isProForma ||
        data.documentTitleKey == 'FACTURE_VENTE' ||
        data.documentTitleKey == 'BON_ROUTE';
    final imageWidgets = <int, pw.MemoryImage>{};
    if (!isOfficial) {
      // Partial delivery notes can contain many repeated item images. Cache
      // each load once and start all item loads together instead of waiting
      // for every image sequentially.
      final imageLoadCache = <String, Future<Uint8List?>>{};

      Future<Uint8List?> loadPath(String path) {
        return imageLoadCache.putIfAbsent(path, () async {
          try {
            if (path.startsWith('assets/') || path.startsWith('Icon/')) {
              return (await rootBundle.load(path)).buffer.asUint8List();
            }
            final file = File(path);
            if (await file.exists()) return file.readAsBytes();
          } catch (_) {}
          return null;
        });
      }

      Future<Uint8List?> loadFirstAvailable(List<String> paths) async {
        for (final path in paths) {
          final bytes = await loadPath(path);
          if (bytes != null) return bytes;
        }
        return null;
      }

      final imageResults = await Future.wait<MapEntry<int, pw.MemoryImage>?>([
        for (int i = 0; i < data.items.length; i++)
          () async {
            final item = data.items[i];
            final path = item.imagePath;
            Uint8List? bytes;

            if (item.imageBase64 != null &&
                item.imageBase64!.trim().isNotEmpty) {
              try {
                final raw = item.imageBase64!.trim();
                final separator = raw.indexOf(',');
                final encoded = raw.startsWith('data:image') && separator >= 0
                    ? raw.substring(separator + 1)
                    : raw;
                bytes = base64Decode(encoded);
              } catch (_) {}
            }

            if (bytes == null &&
                (item.title.contains('Moustiquaire') ||
                    item.title.contains('موستيكير') ||
                    (path != null && path.contains('moustiquaire')))) {
              bytes = await loadFirstAvailable([
                'Icon/media.webp',
                'assets/Icon/media.webp',
              ]);
            } else if (bytes == null && path != null && path.isNotEmpty) {
              bytes = await loadPath(path);
            }

            // Compatibility fallback for old tunnel rows whose only image was
            // the official asset. New rows reach the branches above first.
            if (bytes == null &&
                (item.title.contains('Caisson Tunnel') ||
                    (path != null && path.contains('caisson_tunnel')))) {
              bytes = await loadFirstAvailable([
                'Icon/caisson_tunnel.jpg',
                'assets/Icon/caisson_tunnel.jpg',
              ]);
            }

            return bytes == null ? null : MapEntry(i, pw.MemoryImage(bytes));
          }(),
      ]);

      for (final result in imageResults) {
        if (result != null) imageWidgets[result.key] = result.value;
      }
    }

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(28, 28, 28, 50),
        textDirection: pw.TextDirection.ltr,
        theme: pw.ThemeData.withFont(base: font, bold: fontBold),
        build: (context) => [
          _buildTopHeader(data),
          pw.SizedBox(height: 12),
          pw.Divider(color: PdfColors.grey400),
          pw.SizedBox(height: 12),
          _buildParties(data),
          if (data.chequeNumber.isNotEmpty) ...[
            pw.SizedBox(height: 6),
            pw.Align(
              alignment: pw.Alignment.centerRight,
              child: pw.Text(
                _ar(
                  _currentLang == AppLanguage.french
                      ? 'N° chèque: ${data.chequeNumber}'
                      : 'رقم الشيك: ${data.chequeNumber}',
                ),
                textDirection: _dir(
                  _currentLang == AppLanguage.french
                      ? 'N° chèque: ${data.chequeNumber}'
                      : 'رقم الشيك: ${data.chequeNumber}',
                ),
                style: pw.TextStyle(
                  fontSize: 10,
                  fontWeight: pw.FontWeight.bold,
                  color: _blue,
                ),
              ),
            ),
            pw.SizedBox(height: 4),
          ] else ...[
            pw.SizedBox(height: 14),
          ],
          _buildTable(data, imageWidgets, imageUnderPrices: imageUnderPrices),
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
          if (isOfficial && data.workshop.rib.isNotEmpty) ...[
            pw.SizedBox(height: 14),
            pw.Text(
              _ar(
                _currentLang == AppLanguage.french
                    ? 'RIB: ${data.workshop.rib}'
                    : _currentLang == AppLanguage.english
                    ? 'RIB: ${data.workshop.rib}'
                    : 'الحساب البنكي (RIB): ${data.workshop.rib}',
              ),
              textDirection: _dir(
                _currentLang == AppLanguage.french
                    ? 'RIB: ${data.workshop.rib}'
                    : _currentLang == AppLanguage.english
                    ? 'RIB: ${data.workshop.rib}'
                    : 'الحساب البنكي (RIB): ${data.workshop.rib}',
              ),
              style: pw.TextStyle(
                fontSize: 10,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.grey900,
              ),
            ),
          ],
          if (data.invoiceNote.trim().isNotEmpty) ...[
            pw.SizedBox(height: 12),
            _buildDocumentNoteAtEnd(data.invoiceNote),
          ],
        ],
        footer: (context) => _buildDocumentFooter(data),
      ),
    );

    return pdf.save();
  }

  static String _formatDocumentNumber(DevisData data) {
    String prefix = 'DV';
    final key = data.documentTitleKey ?? '';

    if (key == 'BON_CHARGE') {
      prefix = data.isPartial ? 'FCP' : 'FC';
    } else if (key == 'FACTURE_VENTE' || key == 'BON_ROUTE') {
      prefix = 'FV';
    } else if (key == 'doc_devis' || key == 'DEVIS') {
      prefix = data.isPartial ? 'DVP' : 'DV';
    } else if (key == 'DEVIS_PARTIAL') {
      prefix = 'DVP';
    } else if (data.isProForma) {
      prefix = data.isPartial ? 'FPP' : 'FP';
    } else if (key == 'doc_bon_livraison' ||
        key == 'doc_bon_livraison_sans_prix') {
      prefix = 'BL';
    } else if (key == 'doc_bon_livraison_partiel' ||
        key == 'doc_bon_livraison_partiel_sans_prix') {
      prefix = 'BLP';
    } else {
      if (data.isProForma) {
        prefix = 'FP';
      } else {
        prefix = 'DV';
      }
    }

    String year2 = (DateTime.now().year % 100).toString().padLeft(2, '0');
    try {
      final dateStr = data.orderDate;
      final yearMatch = RegExp(r'\b(20\d{2})\b').firstMatch(dateStr);
      if (yearMatch != null) {
        year2 = yearMatch.group(1)!.substring(2);
      } else {
        final any4Digit = RegExp(r'\b(\d{4})\b').firstMatch(dateStr);
        if (any4Digit != null) {
          year2 = any4Digit.group(1)!.substring(2);
        }
      }
    } catch (_) {}

    final seq = data.sequenceNumber > 0
        ? data.sequenceNumber
        : (data.orderId > 0 && data.orderId < 100000
              ? data.orderId
              : (data.orderId % 1000).abs());
    final seqNum = seq.toString().padLeft(3, '0');
    return '$prefix$year2$seqNum';
  }

  static pw.Widget _buildTopHeader(DevisData data) {
    String titleText;
    if (data.isProForma) {
      if (_currentLang == AppLanguage.french) {
        titleText = 'Facture Proforma';
      } else if (_currentLang == AppLanguage.english) {
        titleText = 'Proforma Invoice';
      } else {
        titleText = 'فاتورة تقديرية / أولية';
      }
    } else {
      var titleKey =
          data.documentTitleKey ?? (data.isPartial ? 'DEVIS_PARTIAL' : 'DEVIS');
      if (titleKey == 'BON_ROUTE') {
        titleKey = 'FACTURE_VENTE';
      }
      if (titleKey == 'doc_bon_livraison_sans_prix' ||
          titleKey == 'doc_bon_livraison_partiel' ||
          titleKey == 'doc_bon_livraison_partiel_sans_prix') {
        if (_currentLang == AppLanguage.french) {
          titleText = 'Bon de livraison';
        } else if (_currentLang == AppLanguage.english) {
          titleText = 'Delivery Note';
        } else {
          titleText = 'وصل تسليم';
        }
      } else {
        titleText = t(titleKey);
      }
    }

    pw.Widget? logoWidget;
    if (data.workshop.logoBase64.isNotEmpty) {
      try {
        final imageBytes = base64Decode(data.workshop.logoBase64);
        logoWidget = pw.Image(
          pw.MemoryImage(imageBytes),
          width: 60,
          height: 60,
        );
      } catch (_) {}
    }

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            if (logoWidget != null) ...[logoWidget, pw.SizedBox(width: 10)],
            pw.Text(
              _ar(data.workshop.name),
              textDirection: _dir(data.workshop.name),
              style: pw.TextStyle(
                fontSize: 16,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.grey900,
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 8),
        pw.Divider(thickness: 0.8, color: PdfColors.grey300),
        pw.SizedBox(height: 8),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  _ar(titleText),
                  textDirection: _dir(titleText),
                  style: pw.TextStyle(
                    fontSize: 22,
                    fontWeight: pw.FontWeight.bold,
                    color: _blue,
                  ),
                ),
              ],
            ),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                _metaLine(t('N°:'), _formatDocumentNumber(data)),
                _metaLine(t('Date:'), data.orderDate),
                if (data.isProForma && data.validUntil.isNotEmpty)
                  _metaLine(t('Valide jusqu\'au:'), data.validUntil),
              ],
            ),
          ],
        ),
      ],
    );
  }

  static pw.Widget _metaLine(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 2),
      child: pw.RichText(
        textDirection: pw.TextDirection.ltr,
        text: pw.TextSpan(
          children: [
            pw.TextSpan(
              text: '${_ar(label)} ',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10),
            ),
            pw.TextSpan(
              text: _ar(value),
              style: const pw.TextStyle(fontSize: 10),
            ),
          ],
        ),
      ),
    );
  }

  static pw.Widget _buildParties(DevisData data) {
    final phonePrefix = _currentLang == AppLanguage.french
        ? 'Tél: '
        : _currentLang == AppLanguage.english
        ? 'Phone: '
        : 'الهاتف: ';
    final clientIdPrefix = _currentLang == AppLanguage.french
        ? 'N° Client: '
        : _currentLang == AppLanguage.english
        ? 'Client ID: '
        : 'رقم الزبون: ';
    final addressPrefix = _currentLang == AppLanguage.french
        ? 'Adresse: '
        : _currentLang == AppLanguage.english
        ? 'Address: '
        : 'العنوان: ';

    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Expanded(
          child: _partyBlock(_ar(t('FOURNISSEUR')), [
            data.workshop.name,
            if (data.workshop.phone.isNotEmpty)
              '$phonePrefix${data.workshop.phone}',
            if (data.workshop.address.isNotEmpty)
              '$addressPrefix${data.workshop.address}',
            if (data.isProForma ||
                data.documentTitleKey == 'FACTURE_VENTE' ||
                data.documentTitleKey == 'BON_ROUTE') ...[
              if (data.workshop.rc.isNotEmpty) 'RC: ${data.workshop.rc}',
              if (data.workshop.nif.isNotEmpty) 'NIF: ${data.workshop.nif}',
              if (data.workshop.nis.isNotEmpty) 'NIS: ${data.workshop.nis}',
              if (data.workshop.ai.isNotEmpty) 'AI: ${data.workshop.ai}',
            ],
          ]),
        ),
        pw.SizedBox(width: 20),
        pw.Expanded(
          child: _partyBlock(_ar(t('CLIENT')), [
            if (data.clientReference.isNotEmpty)
              '$clientIdPrefix${data.clientReference}',
            data.clientName,
            if (data.clientPhone.isNotEmpty) '$phonePrefix${data.clientPhone}',
            if (data.clientNif.isNotEmpty) 'NIF: ${data.clientNif}',
            if (data.clientNis.isNotEmpty) 'NIS: ${data.clientNis}',
            if (data.clientRc.isNotEmpty) 'RC: ${data.clientRc}',
            if (data.clientAi.isNotEmpty) 'AI: ${data.clientAi}',
          ]),
        ),
      ],
    );
  }

  static pw.Widget _partyBlock(String title, List<String> lines) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          _ar(title),
          textDirection: _dir(title),
          style: pw.TextStyle(
            fontSize: 9,
            fontWeight: pw.FontWeight.bold,
            color: PdfColors.grey700,
          ),
        ),
        pw.SizedBox(height: 4),
        ...lines.map(
          (line) => pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 2),
            child: pw.Text(
              _ar(line),
              textDirection: _dir(line),
              style: const pw.TextStyle(fontSize: 10),
            ),
          ),
        ),
      ],
    );
  }

  static bool _hasArabic(String text) {
    return text.runes.any(
      (r) =>
          (r >= 0x0600 && r <= 0x06FF) || // Arabic block
          (r >= 0xFB50 && r <= 0xFEFF),
    ); // Arabic Presentation Forms
  }

  /// Processes Arabic text for PDF rendering.
  ///
  /// The `pdf` package does NOT implement the Unicode BiDi algorithm.
  /// It renders every glyph strictly left-to-right in the order they appear
  /// in the string, even when textDirection: rtl is set (rtl only affects
  /// alignment/paragraph direction, not glyph run reordering).
  ///
  /// To display Arabic correctly we reshape it first, then use the Unicode
  /// Bidirectional Algorithm to produce visual order. A word-by-word reverse
  /// is not sufficient for notes containing French, numbers or parentheses.
  static String _ar(String text) {
    if (!_hasArabic(text)) return text;

    // Keep user-entered line order. Reversing the whole note at once would
    // also reverse the lines, making the last line appear first in the PDF.
    return text
        .replaceAll('\r\n', '\n')
        .split('\n')
        .map(_arSingleLine)
        .join('\n');
  }

  static String _arSingleLine(String text) {
    // Shape Arabic glyphs first, then resolve mixed RTL/LTR runs (Arabic,
    // French, numbers and paired punctuation) with the real UBA algorithm.
    final reshaped = ArabicReshaper.instance.reshape(text);
    // bidi.logicalToVisual returns Unicode code points.  Returning that list
    // directly makes String interpolation print `[82, 101, ...]` in the PDF
    // instead of the actual text.
    return String.fromCharCodes(bidi.logicalToVisual(reshaped));
  }

  // Always LTR: _ar() already produced visual-order text.
  static pw.TextDirection _dir(String text) => pw.TextDirection.ltr;

  // ── حساب أعرض الأعمدة بالـ points (بما يطابق تماماً pw.Table القديم) ──────
  // A4 عرضها 595.28 pt، الهامش 28 من كل جانب => 539.28 pt متاحة
  static const double _tableW = 595.28 - 56.0; // 539.28
  static const double _col0w = 50.0; // Image  (fixed)
  static const double _col3w = 32.0; // Qty    (fixed)
  static const double _flexTotal = 4.0 + 1.5 + 1.6; // 7.1
  static double get _flexUnit => (_tableW - _col0w - _col3w) / _flexTotal;

  static double get _col1w => _flexUnit * 4.0;

  static double get _col2w => _flexUnit * 1.5;

  static double get _col4w => _flexUnit * 1.6;

  /// خلية عادية داخل صف المحاكاة
  static pw.Widget _cell(
    double width,
    pw.Widget child, {
    pw.Alignment alignment = pw.Alignment.centerLeft,
    PdfColor? bg,
    pw.EdgeInsets padding = const pw.EdgeInsets.all(6),
    bool hasBorder = true,
  }) {
    return pw.Container(
      width: width,
      padding: padding,
      alignment: alignment,
      decoration: pw.BoxDecoration(
        color: bg,
        border: hasBorder
            ? pw.Border.all(color: PdfColors.grey300, width: 0.5)
            : null,
      ),
      child: child,
    );
  }

  /// صف رأس الجدول
  static pw.Widget _tableHeader(
    bool hidePrices,
    bool isProForma, {
    bool hasBorder = true,
    bool imageUnderPrices = false,
  }) {
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
        border: hasBorder
            ? pw.Border.all(color: PdfColors.grey300, width: 0.5)
            : null,
      ),
      child: pw.Text(
        _ar(text),
        textDirection: _dir(text),
        maxLines: null,
        style: pw.TextStyle(
          color: PdfColors.white,
          fontWeight: pw.FontWeight.bold,
          fontSize: 9,
        ),
      ),
    );
    return pw.Row(
      children: [
        if (!isProForma && !imageUnderPrices) hCell(_col0w, t('Image')),
        hCell(
          imageUnderPrices
              ? (_tableW - _col3w - (hidePrices ? 0 : _col2w + _col4w))
              : isProForma
              ? (hidePrices ? _tableW : (_tableW - _col2w - _col3w - _col4w))
              : (hidePrices ? (_tableW - _col0w - _col3w) : _col1w),
          t('Désignation'),
        ),
        if (!hidePrices)
          hCell(
            _col2w,
            isProForma ? 'P.U. H.T.' : t('Prix Unit.'),
            align: pw.Alignment.centerRight,
          ),
        hCell(_col3w, t('Qté'), align: pw.Alignment.centerRight),
        if (!hidePrices)
          hCell(
            _col4w,
            isProForma ? 'TOTAL H.T.' : t('Total'),
            align: pw.Alignment.centerRight,
          ),
      ],
    );
  }

  /// بناء صف بيانات — إذا كان مشطوباً يُلف بـ Stack لرسم X على كامل الصف
  static pw.Widget _dataRow({
    required DevisLineItem item,
    required int index,
    required pw.MemoryImage? image,
    required bool hidePrices,
    required bool isProForma,
    bool imageUnderPrices = false,
    bool hasBorder = true,
  }) {
    final PdfColor bg = index.isEven ? PdfColors.white : PdfColors.grey100;
    final PdfColor? txtColor = item.isReplaced ? PdfColors.red : null;

    final List<String> displayDetails;
    if (isProForma) {
      if (_currentLang == AppLanguage.french) {
        displayDetails = [
          'Largeur: ${item.width} mm | Hauteur: ${item.height} mm',
        ];
      } else if (_currentLang == AppLanguage.english) {
        displayDetails = [
          'Width: ${item.width} mm | Height: ${item.height} mm',
        ];
      } else {
        displayDetails = [
          'العرض: ${item.width} مم | الارتفاع: ${item.height} مم',
        ];
      }
    } else {
      displayDetails = item.details;
    }

    final pw.Widget rowContent = pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        // عمود 0: الصورة
        if (!isProForma && !imageUnderPrices)
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
            hasBorder: hasBorder,
          ),
        // عمود 1: الاسم والتفاصيل
        _cell(
          imageUnderPrices
              ? (_tableW - _col3w - (hidePrices ? 0 : _col2w + _col4w))
              : isProForma
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
              _detailsBlock(displayDetails, twoColumns: hidePrices),
              if (imageUnderPrices && image != null) ...[
                pw.SizedBox(height: 6),
                pw.Container(
                  width: double.infinity,
                  height: 150,
                  alignment: pw.Alignment.centerLeft,
                  child: pw.Image(image, fit: pw.BoxFit.contain),
                ),
              ],
            ],
          ),
          bg: bg,
          hasBorder: hasBorder,
        ),
        // عمود 2: سعر الوحدة
        if (!hidePrices)
          _cell(
            _col2w,
            pw.Text(
              _formatMoney(item.unitPrice),
              style: pw.TextStyle(
                fontSize: 9,
                fontWeight: pw.FontWeight.bold,
                color: txtColor,
              ),
            ),
            alignment: pw.Alignment.centerRight,
            bg: bg,
            hasBorder: hasBorder,
          ),
        // عمود 3: الكمية
        _cell(
          _col3w,
          pw.Text(
            '${item.quantity}',
            style: pw.TextStyle(fontSize: 9, color: txtColor),
          ),
          alignment: pw.Alignment.centerRight,
          bg: bg,
          hasBorder: hasBorder,
        ),
        // عمود 4: الإجمالي
        if (!hidePrices)
          _cell(
            _col4w,
            pw.Text(
              _formatMoney(item.unitPrice * item.quantity),
              style: pw.TextStyle(
                fontSize: 9,
                fontWeight: pw.FontWeight.bold,
                color: txtColor,
              ),
            ),
            alignment: pw.Alignment.centerRight,
            bg: bg,
            hasBorder: hasBorder,
          ),
      ],
    );

    if (!item.isReplaced) return rowContent;

    // ── صف مشطوب: Stack يضع علامة X فوق كامل الصف ──────────────────────
    return pw.Stack(
      children: [
        rowContent,
        pw.Positioned.fill(
          child: pw.CustomPaint(
            painter: (PdfGraphics canvas, PdfPoint size) {
              canvas
                ..setColor(PdfColors.red)
                ..setLineWidth(1.5)
                ..drawLine(0, 0, size.x, size.y)
                ..drawLine(0, size.y, size.x, 0)
                ..strokePath();
            },
          ),
        ),
      ],
    );
  }

  static bool _isCaissonOnly(DevisData data) {
    return data.items.isNotEmpty &&
        data.items.every(
          (item) =>
              item.title.contains('Caisson Tunnel') ||
              item.title.contains('caisson') ||
              (item.imagePath != null &&
                  item.imagePath!.contains('caisson_tunnel')) ||
              item.details.any(
                (d) =>
                    d.contains('Caisson') ||
                    d.contains('صندوق') ||
                    d.contains('Kit'),
              ),
        );
  }

  static pw.Widget _buildTable(
    DevisData data,
    Map<int, pw.MemoryImage> imageWidgets, {
    bool imageUnderPrices = false,
  }) {
    final bool hidePrices = data.hidePrices;
    final bool isOfficial =
        data.isProForma ||
        data.documentTitleKey == 'FACTURE_VENTE' ||
        data.documentTitleKey == 'BON_ROUTE';
    final bool hasBorder = data.documentTitleKey != 'BON_ROUTE';
    final bool isCaissonOnly = _isCaissonOnly(data);

    imageUnderPrices = imageUnderPrices && !isOfficial;

    if (isCaissonOnly && !imageUnderPrices) {
      return _buildCaissonTunnelTable(
        data,
        imageWidgets,
        hidePrices,
        hasBorder,
      );
    }

    final List<pw.Widget> rows = [
      _tableHeader(
        hidePrices,
        isOfficial,
        hasBorder: hasBorder,
        imageUnderPrices: imageUnderPrices,
      ),
    ];

    for (var entry in data.items.asMap().entries) {
      final index = entry.key;
      final item = entry.value;

      rows.add(
        _dataRow(
          item: item,
          index: index,
          image: imageWidgets[index],
          hidePrices: hidePrices,
          isProForma: isOfficial,
          imageUnderPrices: imageUnderPrices,
          hasBorder: hasBorder,
        ),
      );

      // صف سبب التعديل (يظهر أسفل الصف المشطوب)
      if (item.isReplaced && item.replacementReason.isNotEmpty) {
        final reasonText = 'سبب التعديل: ${item.replacementReason}';
        rows.add(
          pw.Row(
            children: [
              pw.Container(
                width: _col0w,
                decoration: pw.BoxDecoration(
                  color: PdfColors.red50,
                  border: hasBorder
                      ? pw.Border.all(color: PdfColors.grey300, width: 0.5)
                      : null,
                ),
              ),
              pw.Container(
                width: hidePrices
                    ? (_tableW - _col0w)
                    : (_col1w + _col2w + _col3w + _col4w),
                padding: const pw.EdgeInsets.symmetric(
                  horizontal: 6,
                  vertical: 4,
                ),
                decoration: pw.BoxDecoration(
                  color: PdfColors.red50,
                  border: hasBorder
                      ? pw.Border.all(color: PdfColors.grey300, width: 0.5)
                      : null,
                ),
                child: pw.Text(
                  _ar(reasonText),
                  textDirection: _dir(reasonText),
                  style: const pw.TextStyle(
                    color: PdfColors.red900,
                    fontSize: 9,
                  ),
                ),
              ),
            ],
          ),
        );
      }
    }

    // صف مجموع الكميات في الأسفل
    final int totalQty = data.items
        .where((i) => !i.isReplaced)
        .fold(0, (s, i) => s + i.quantity);
    rows.add(
      pw.Row(
        children: [
          pw.Container(
            width: _col0w,
            decoration: pw.BoxDecoration(
              color: PdfColors.grey100,
              border: hasBorder
                  ? pw.Border.all(color: PdfColors.grey300, width: 0.5)
                  : null,
            ),
          ),
          pw.Container(
            width: hidePrices ? (_tableW - _col0w - _col3w) : (_col1w + _col2w),
            padding: const pw.EdgeInsets.all(6),
            alignment: pw.Alignment.centerLeft,
            decoration: pw.BoxDecoration(
              color: PdfColors.grey100,
              border: hasBorder
                  ? pw.Border.all(color: PdfColors.grey300, width: 0.5)
                  : null,
            ),
            child: pw.Text(
              _ar(t('Quantité Totale / مجموع الكميات')),
              textDirection: pw.TextDirection.ltr,
              style: pw.TextStyle(
                fontSize: 9,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.grey800,
              ),
            ),
          ),
          pw.Container(
            width: _col3w,
            padding: const pw.EdgeInsets.all(6),
            alignment: pw.Alignment.centerRight,
            decoration: pw.BoxDecoration(
              color: PdfColors.grey100,
              border: hasBorder
                  ? pw.Border.all(color: PdfColors.grey300, width: 0.5)
                  : null,
            ),
            child: pw.Text(
              '$totalQty',
              style: pw.TextStyle(
                fontSize: 10,
                fontWeight: pw.FontWeight.bold,
                color: _blue,
              ),
            ),
          ),
          if (!hidePrices)
            pw.Container(
              width: _col4w,
              decoration: pw.BoxDecoration(
                color: PdfColors.grey100,
                border: hasBorder
                    ? pw.Border.all(color: PdfColors.grey300, width: 0.5)
                    : null,
              ),
            ),
        ],
      ),
    );

    return pw.Column(children: rows);
  }

  // ── جدول خاص بالـ Caisson Tunnel المستقل (6 أعمدة) ──────────────────────
  static pw.Widget _buildCaissonTunnelTable(
    DevisData data,
    Map<int, pw.MemoryImage> imageWidgets,
    bool hidePrices,
    bool hasBorder,
  ) {
    const double cImgW = 50.0;
    const double cDimW = 135.0;
    const double cSizeW = 100.0;
    const double cPriceW = 85.0;
    const double cQtyW = 45.0;
    const double cTotalW =
        _tableW - cImgW - cDimW - cSizeW - cPriceW - cQtyW; // 124.28

    pw.Widget hCell(
      double w,
      String text, {
      pw.Alignment align = pw.Alignment.center,
    }) => pw.Container(
      width: w,
      padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      alignment: align,
      decoration: pw.BoxDecoration(
        color: _blue,
        border: hasBorder
            ? pw.Border.all(color: PdfColors.grey300, width: 0.5)
            : null,
      ),
      child: pw.Text(
        _ar(text),
        textDirection: _dir(text),
        textAlign: pw.TextAlign.center,
        style: pw.TextStyle(
          color: PdfColors.white,
          fontWeight: pw.FontWeight.bold,
          fontSize: 9,
        ),
      ),
    );

    final List<pw.Widget> rows = [
      pw.Row(
        children: [
          hCell(cImgW, 'الصورة'),
          hCell(cDimW, 'التفاصيل (البعد)'),
          hCell(cSizeW, 'حجم الصندوق'),
          if (!hidePrices) hCell(cPriceW, 'سعر الوحدة'),
          hCell(cQtyW, 'الكمية'),
          if (!hidePrices) hCell(cTotalW, 'المجموع'),
        ],
      ),
    ];

    for (var entry in data.items.asMap().entries) {
      final index = entry.key;
      final item = entry.value;
      final bg = index.isEven ? PdfColors.white : PdfColors.grey100;

      // استخراج البعد (Dimension)
      String dimText = item.width > 0 ? '${item.width} cm' : '';
      if (dimText.isEmpty && item.details.isNotEmpty) {
        dimText = item.details.firstWhere(
          (d) =>
              d.contains('cm') ||
              d.contains('ملم') ||
              d.contains('مم') ||
              d.contains('طول') ||
              d.contains('البعد'),
          orElse: () => item.details.first,
        );
      }

      // استخراج حجم الصندوق (Box Size)
      String boxSizeText = item.height > 0 ? '${item.height} cm' : '';
      if (boxSizeText.isEmpty && item.details.length > 1) {
        boxSizeText = item.details.firstWhere(
          (d) =>
              d.contains('Kit') ||
              d.contains('صندوق') ||
              d.contains('25') ||
              d.contains('30') ||
              d.contains('40'),
          orElse: () => item.details.length > 1 ? item.details[1] : '—',
        );
      } else if (boxSizeText.isEmpty) {
        boxSizeText = '—';
      }

      rows.add(
        pw.Row(
          children: [
            // 1. الصورة
            _cell(
              cImgW,
              imageWidgets[index] != null
                  ? pw.Image(imageWidgets[index]!, fit: pw.BoxFit.contain)
                  : pw.Text(
                      '-',
                      style: const pw.TextStyle(color: PdfColors.grey500),
                    ),
              alignment: pw.Alignment.center,
              bg: bg,
              padding: const pw.EdgeInsets.all(3),
              hasBorder: hasBorder,
            ),
            // 2. التفاصيل (البعد)
            _cell(
              cDimW,
              pw.Text(
                _ar(dimText),
                textDirection: _dir(dimText),
                style: pw.TextStyle(
                  fontSize: 9,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              alignment: pw.Alignment.center,
              bg: bg,
              hasBorder: hasBorder,
            ),
            // 3. حجم الصندوق
            _cell(
              cSizeW,
              pw.Text(
                _ar(boxSizeText),
                textDirection: _dir(boxSizeText),
                style: const pw.TextStyle(fontSize: 8.5),
              ),
              alignment: pw.Alignment.center,
              bg: bg,
              hasBorder: hasBorder,
            ),
            // 4. سعر الوحدة
            if (!hidePrices)
              _cell(
                cPriceW,
                pw.Text(
                  '${item.unitPrice.toStringAsFixed(2)} DA',
                  style: const pw.TextStyle(fontSize: 8.5),
                ),
                alignment: pw.Alignment.centerRight,
                bg: bg,
                hasBorder: hasBorder,
              ),
            // 5. الكمية
            _cell(
              cQtyW,
              pw.Text(
                '${item.quantity}',
                style: pw.TextStyle(
                  fontSize: 9,
                  fontWeight: pw.FontWeight.bold,
                  color: _blue,
                ),
              ),
              alignment: pw.Alignment.center,
              bg: bg,
              hasBorder: hasBorder,
            ),
            // 6. المجموع
            if (!hidePrices)
              _cell(
                cTotalW,
                pw.Text(
                  '${(item.unitPrice * item.quantity).toStringAsFixed(2)} DA',
                  style: pw.TextStyle(
                    fontSize: 9,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                alignment: pw.Alignment.centerRight,
                bg: bg,
                hasBorder: hasBorder,
              ),
          ],
        ),
      );
    }

    // مجموع الكميات ومجموع حسابات الكميات في الأسفل
    final int totalQty = data.items
        .where((i) => !i.isReplaced)
        .fold(0, (s, i) => s + i.quantity);
    final double totalCalcAmount = data.items
        .where((i) => !i.isReplaced)
        .fold(0.0, (s, i) => s + (i.unitPrice * i.quantity));

    // 1. صف مجموع الكميات
    rows.add(
      pw.Row(
        children: [
          _cell(
            cImgW + cDimW + cSizeW,
            pw.Text(
              _ar('مجموع الكميات (Total Quantités)'),
              style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
            ),
            bg: PdfColors.grey100,
            hasBorder: hasBorder,
          ),
          _cell(
            cQtyW,
            pw.Text(
              '$totalQty',
              style: pw.TextStyle(
                fontSize: 10,
                fontWeight: pw.FontWeight.bold,
                color: _blue,
              ),
            ),
            alignment: pw.Alignment.center,
            bg: PdfColors.grey100,
            hasBorder: hasBorder,
          ),
          if (!hidePrices)
            _cell(
              cPriceW + cTotalW,
              pw.SizedBox(),
              bg: PdfColors.grey100,
              hasBorder: hasBorder,
            ),
        ],
      ),
    );

    // 2. صف مجموع حسابات الكميات / المجموع الإجمالي
    if (!hidePrices) {
      rows.add(
        pw.Row(
          children: [
            _cell(
              cImgW + cDimW + cSizeW + cPriceW + cQtyW,
              pw.Text(
                _ar('مجموع حسابات الكميات (Total Général)'),
                style: pw.TextStyle(
                  fontSize: 9.5,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              alignment: pw.Alignment.centerRight,
              bg: PdfColors.grey200,
              hasBorder: hasBorder,
            ),
            _cell(
              cTotalW,
              pw.Text(
                '${totalCalcAmount.toStringAsFixed(2)} DA',
                style: pw.TextStyle(
                  fontSize: 10,
                  fontWeight: pw.FontWeight.bold,
                  color: _blue,
                ),
              ),
              alignment: pw.Alignment.centerRight,
              bg: PdfColors.grey200,
              hasBorder: hasBorder,
            ),
          ],
        ),
      );
    }

    return pw.Column(children: rows);
  }

  static pw.Widget _buildTotalQtyBlock(DevisData data) {
    final int totalQty = data.items
        .where((i) => !i.isReplaced)
        .fold(0, (s, i) => s + i.quantity);

    return pw.Align(
      alignment: pw.Alignment.centerRight,
      child: pw.Container(
        width: 220,
        padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: pw.BoxDecoration(
          color: _blue,
          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
        ),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              _ar(t('Quantité Totale')),
              textDirection: _dir(t('Quantité Totale')),
              style: pw.TextStyle(
                color: PdfColors.white,
                fontWeight: pw.FontWeight.bold,
                fontSize: 10,
              ),
            ),
            pw.Text(
              '$totalQty',
              style: pw.TextStyle(
                color: PdfColors.white,
                fontWeight: pw.FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  static pw.Widget _buildInvoiceNote(String note) {
    String label;
    if (_currentLang == AppLanguage.french) {
      label = 'Remarque';
    } else if (_currentLang == AppLanguage.english) {
      label = 'Note';
    } else {
      label = 'ملاحظة';
    }
    final labelText = '$label:';
    final noteText = _ar(note);
    final labelWidget = pw.Text(
      labelText,
      textDirection: pw.TextDirection.ltr,
      style: pw.TextStyle(
        fontSize: 10,
        fontWeight: pw.FontWeight.bold,
        color: PdfColors.grey900,
      ),
    );
    final noteWidget = pw.Expanded(
      child: pw.Text(
        noteText,
        textDirection: _dir(note),
        style: pw.TextStyle(
          fontSize: 10,
          fontWeight: pw.FontWeight.bold,
          color: PdfColors.grey900,
        ),
      ),
    );
    return pw.Container(
      width: double.infinity,
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: _currentLang == AppLanguage.arabic
            ? [noteWidget, pw.SizedBox(width: 5), labelWidget]
            : [labelWidget, pw.SizedBox(width: 5), noteWidget],
      ),
    );
  }

  /// Keep the order note in the document flow so it is rendered once, after
  /// the last content block, instead of changing the footer height while
  /// MultiPage is calculating the page count.
  static pw.Widget _buildDocumentNoteAtEnd(String note) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.only(top: 8),
      decoration: const pw.BoxDecoration(
        border: pw.Border(
          top: pw.BorderSide(color: PdfColors.grey300, width: 0.5),
        ),
      ),
      child: _buildInvoiceNote(note),
    );
  }

  /// Official documents keep the workshop legal/contact line in the footer.
  /// The order note is deliberately not part of this footer: it belongs once
  /// at the end of the document content.
  static pw.Widget _buildDocumentFooter(DevisData data) {
    final isOfficial =
        data.isProForma ||
        data.documentTitleKey == 'FACTURE_VENTE' ||
        data.documentTitleKey == 'BON_ROUTE';
    if (!isOfficial) return pw.SizedBox();

    final parts = <String>[];
    if (isOfficial) {
      if (data.workshop.name.isNotEmpty) parts.add(data.workshop.name);
      if (data.workshop.address.isNotEmpty) {
        parts.add('Adresse: ${data.workshop.address}');
      }
      if (data.workshop.rc.isNotEmpty) parts.add('RC: ${data.workshop.rc}');
      if (data.workshop.nif.isNotEmpty) parts.add('NIF: ${data.workshop.nif}');
      if (data.workshop.nis.isNotEmpty) parts.add('NIS: ${data.workshop.nis}');
      if (data.workshop.ai.isNotEmpty) parts.add('AI: ${data.workshop.ai}');
      if (data.workshop.phone.isNotEmpty) {
        parts.add('Tél: ${data.workshop.phone}');
      }
    }

    final footerText = parts.join(' | ');
    final children = <pw.Widget>[];
    if (footerText.isNotEmpty) {
      children.add(
        pw.Text(
          _ar(footerText),
          textDirection: _dir(footerText),
          style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey700),
          textAlign: pw.TextAlign.center,
        ),
      );
    }

    return pw.Container(
      alignment: pw.Alignment.center,
      padding: const pw.EdgeInsets.only(top: 8),
      decoration: const pw.BoxDecoration(
        border: pw.Border(
          top: pw.BorderSide(color: PdfColors.grey300, width: 0.5),
        ),
      ),
      child: pw.Column(children: children),
    );
  }

  static pw.Widget _detailRichText(
    String text, {
    PdfColor color = PdfColors.grey800,
    double fontSize = 8.5,
  }) {
    final normalStyle = pw.TextStyle(fontSize: fontSize, color: color);
    final labelStyle = pw.TextStyle(
      fontSize: fontSize,
      color: color,
      fontWeight: pw.FontWeight.bold,
    );

    return pw.RichText(
      textDirection: _dir(text),
      text: pw.TextSpan(children: _detailSpans(text, normalStyle, labelStyle)),
    );
  }

  /// No-price delivery documents are primarily used as workshop sheets.
  /// Their window details are therefore split into two columns to reduce the
  /// number of printed pages while preserving the original detail order.
  static pw.Widget _detailsBlock(
    List<String> details, {
    required bool twoColumns,
  }) {
    final clean = details.where((item) => item.trim().isNotEmpty).toList();
    if (clean.isEmpty) return pw.SizedBox();

    pw.Widget column(List<String> values) => pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        for (final value in values)
          _detailRichText(value, color: PdfColors.grey800),
      ],
    );

    if (!twoColumns || clean.length < 2) return column(clean);

    final split = (clean.length + 1) ~/ 2;
    final first = clean.sublist(0, split);
    final second = clean.sublist(split);
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Expanded(child: column(first)),
        pw.SizedBox(width: 8),
        pw.Expanded(child: column(second)),
      ],
    );
  }

  static List<pw.TextSpan> _detailSpans(
    String text,
    pw.TextStyle normalStyle,
    pw.TextStyle labelStyle,
  ) {
    final spans = <pw.TextSpan>[];
    final parts = text.split('|');
    for (var i = 0; i < parts.length; i++) {
      if (i > 0) {
        spans.add(pw.TextSpan(text: _ar(' | '), style: normalStyle));
      }
      final part = parts[i];
      final colonIndex = part.indexOf(':');
      if (colonIndex > 0) {
        spans.add(
          pw.TextSpan(
            text: _ar(part.substring(0, colonIndex + 1)),
            style: labelStyle,
          ),
        );
        spans.add(
          pw.TextSpan(
            text: _ar(part.substring(colonIndex + 1)),
            style: normalStyle,
          ),
        );
      } else {
        spans.add(pw.TextSpan(text: _ar(part), style: normalStyle));
      }
    }
    return spans;
  }

  static pw.Widget _buildTotals(DevisData data) {
    final bool isOfficial =
        data.isProForma || data.documentTitleKey == 'FACTURE_VENTE';
    final totalBrutLabel = isOfficial ? 'TOTAL HT' : t('Total Brut');
    final remiseLabel = isOfficial ? 'REMISE' : t('Remise');
    final netHtLabel = isOfficial ? 'NET HT' : t('Total après remise');
    final tvaLabel = isOfficial
        ? 'TVA'
        : 'TVA (${data.tvaPercent.toStringAsFixed(0)}%)';
    final totalTtcLabel = isOfficial ? 'NET A PAYER' : t('TOTAL TTC');
    final amountRemaining = (data.totalTTC - data.amountPaid)
        .clamp(0.0, double.infinity)
        .toDouble();

    return pw.Align(
      alignment: pw.Alignment.centerRight,
      child: pw.SizedBox(
        width: 220,
        child: pw.Column(
          children: [
            _totalRow(totalBrutLabel, data.totalBrut),
            _totalRow(remiseLabel, data.remise),
            _totalRow(netHtLabel, data.totalBeforeTax),
            _totalRow(tvaLabel, data.tvaAmount),
            pw.Container(
              width: double.infinity,
              margin: const pw.EdgeInsets.only(top: 4),
              padding: const pw.EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 6,
              ),
              color: _blue,
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    _ar(totalTtcLabel),
                    textDirection: _dir(totalTtcLabel),
                    style: pw.TextStyle(
                      color: PdfColors.white,
                      fontWeight: pw.FontWeight.bold,
                      fontSize: 10,
                    ),
                  ),
                  pw.Text(
                    '${_formatMoney(data.totalTTC)} D.A',
                    style: pw.TextStyle(
                      color: PdfColors.white,
                      fontWeight: pw.FontWeight.bold,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
            _totalRow(
              t('Montant payé'),
              data.amountPaid,
              color: PdfColors.green,
            ),
            _totalRow(t('Remaining:'), amountRemaining, color: PdfColors.red),
          ],
        ),
      ),
    );
  }

  static pw.Widget _totalRow(String label, double value, {PdfColor? color}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            _ar(label),
            textDirection: _dir(label),
            style: pw.TextStyle(fontSize: 9, color: color),
          ),
          pw.Text(
            '${_formatMoney(value)} D.A',
            style: pw.TextStyle(
              fontSize: 9,
              fontWeight: pw.FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  static String _formatMoney(double value) {
    if (value == value.roundToDouble()) {
      return value.toStringAsFixed(0);
    }
    return value.toStringAsFixed(2);
  }

  static Future<Uint8List> _buildBonDeChargePdf(
    DevisData data,
    pw.Font font,
    pw.Font fontBold,
  ) async {
    final pdf = pw.Document();

    final List<Map<String, dynamic>> rows = [];
    int globalIndex = 0;
    for (final item in data.items) {
      for (int i = 0; i < item.quantity; i++) {
        globalIndex++;
        final barcodeVal =
            'CMD-${data.orderId}-D${item.detailId}-W$globalIndex-F';
        final cumTicketNum = data.priorConfirmedWindowsCount + globalIndex;
        rows.add({
          'num': '$globalIndex\n(#$cumTicketNum)',
          'title': item.title,
          'client': data.clientName,
          'dims': '${item.width} x ${item.height} mm',
          'color': item.color,
          'barcode': barcodeVal,
        });
      }
    }

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(28, 28, 28, 50),
        textDirection: pw.TextDirection.ltr,
        theme: pw.ThemeData.withFont(base: font, bold: fontBold),
        build: (context) => [
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    _ar(data.workshop.name),
                    style: pw.TextStyle(
                      fontSize: 16,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  if (data.workshop.phone.isNotEmpty)
                    pw.Text(
                      'Tél: ${data.workshop.phone}',
                      style: const pw.TextStyle(fontSize: 10),
                    ),
                ],
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text(
                    _currentLang == AppLanguage.french
                        ? 'Bon de charge / Livraison'
                        : _currentLang == AppLanguage.english
                        ? 'Loading & Delivery Note'
                        : _ar('وصل الشحن والتسليم (الفاتورة التقديرية)'),
                    style: pw.TextStyle(
                      fontSize: 18,
                      fontWeight: pw.FontWeight.bold,
                      color: _blue,
                    ),
                  ),
                  pw.Text(
                    'Date: ${data.orderDate}',
                    style: const pw.TextStyle(fontSize: 10),
                  ),
                ],
              ),
            ],
          ),
          pw.SizedBox(height: 10),
          pw.Divider(color: PdfColors.grey400, thickness: 1),
          pw.SizedBox(height: 10),

          pw.Container(
            padding: const pw.EdgeInsets.all(8),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.grey300, width: 0.5),
              color: PdfColors.grey50,
            ),
            child: pw.Row(
              children: [
                pw.Text(
                  _currentLang == AppLanguage.french
                      ? 'Client: '
                      : _currentLang == AppLanguage.english
                      ? 'Client: '
                      : _ar('الزبون: '),
                  style: pw.TextStyle(
                    fontWeight: pw.FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
                pw.Text(
                  _ar(data.clientName),
                  style: pw.TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 15),

          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
            columnWidths: {
              0: const pw.FixedColumnWidth(45), // N° Ticket
              1: const pw.FlexColumnWidth(1.8), // Designation / Item Title
              2: const pw.FlexColumnWidth(1.2), // Dimensions
              3: const pw.FlexColumnWidth(1), // Couleur
              4: const pw.FlexColumnWidth(1.5), // Barcode
            },
            children: [
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: PdfColors.grey100),
                children: [
                  _headerCell(
                    _currentLang == AppLanguage.french
                        ? 'N°'
                        : _currentLang == AppLanguage.english
                        ? 'No'
                        : 'رقم',
                  ),
                  _headerCell(
                    _currentLang == AppLanguage.french
                        ? 'Désignation'
                        : _currentLang == AppLanguage.english
                        ? 'Item Designation'
                        : 'البيان / النافذة',
                  ),
                  _headerCell(
                    _currentLang == AppLanguage.french
                        ? 'Dimensions (mm)'
                        : _currentLang == AppLanguage.english
                        ? 'Dimensions (mm)'
                        : 'المقاسات (ملم)',
                  ),
                  _headerCell(
                    _currentLang == AppLanguage.french
                        ? 'Couleur'
                        : _currentLang == AppLanguage.english
                        ? 'Color'
                        : 'اللون',
                  ),
                  _headerCell(
                    _currentLang == AppLanguage.french
                        ? 'Code à barres'
                        : _currentLang == AppLanguage.english
                        ? 'Barcode'
                        : 'الكود بار',
                  ),
                ],
              ),
              for (final row in rows)
                pw.TableRow(
                  children: [
                    _dataCell(row['num']!),
                    _dataCell(row['title']!),
                    _dataCell(row['dims']!),
                    _dataCell(row['color']!),
                    pw.Container(
                      padding: const pw.EdgeInsets.symmetric(
                        vertical: 4,
                        horizontal: 8,
                      ),
                      alignment: pw.Alignment.center,
                      child: pw.BarcodeWidget(
                        barcode: pw.Barcode.code128(),
                        data: row['barcode']!,
                        width: 120,
                        height: 25,
                        drawText: true,
                        textStyle: const pw.TextStyle(fontSize: 7),
                      ),
                    ),
                  ],
                ),
            ],
          ),
          if (data.invoiceNote.trim().isNotEmpty) ...[
            pw.SizedBox(height: 12),
            _buildDocumentNoteAtEnd(data.invoiceNote),
          ],
        ],
        footer: (context) => _buildDocumentFooter(data),
      ),
    );

    return pdf.save();
  }

  static pw.Widget _headerCell(String text) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(6),
      alignment: pw.Alignment.center,
      child: pw.Text(
        _ar(text),
        style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10),
      ),
    );
  }

  static pw.Widget _dataCell(String text) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(6),
      alignment: pw.Alignment.center,
      child: pw.Text(_ar(text), style: const pw.TextStyle(fontSize: 9)),
    );
  }
}
