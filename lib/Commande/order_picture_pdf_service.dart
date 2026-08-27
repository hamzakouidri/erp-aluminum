import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:database_data/Commande/Systeme/model.dart';
import 'package:database_data/Commande/Systeme/model_serialization.dart';
import 'package:database_data/Commande/capture_image.dart';
import 'package:database_data/Commande/devis_builder.dart';
import 'package:database_data/arabic_reshaper/arabic_reshaper.dart';
import 'package:database_data/settings/app_settings.dart';
import 'package:database_data/settings/localization.dart';
import 'package:database_data/sql_database.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_file_dialog/flutter_file_dialog.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

class OrderPicturePdfService {
  static pw.Font? _font;
  static pw.Font? _fontBold;
  static Future<void>? _fontFuture;

  static Future<void> _loadFonts() {
    _fontFuture ??= _doLoadFonts();
    return _fontFuture!;
  }

  static Future<void> _doLoadFonts() async {
    final regular = await rootBundle.load('assets/fonts/Amiri-Regular.ttf');
    final bold = await rootBundle.load('assets/fonts/Amiri-Bold.ttf');
    _font = pw.Font.ttf(regular);
    _fontBold = pw.Font.ttf(bold);
  }

  static Future<Uint8List> buildPdfBytes({
    required SqlDatabase db,
    required Map<String, dynamic> order,
    required AppLanguage lang,
  }) async {
    await _loadFonts();

    final rawItems = await db.readCommandeDetails(order['id']);
    final items = rawItems
        .map((item) => Map<String, dynamic>.from(item))
        .toList(growable: false);
    await _ensureDrawingImages(db, items);

    final workshop = await DevisBuilder.loadWorkshopInfo();
    final data = await DevisBuilder.build(
      order: order,
      items: items,
      workshop: workshop,
      hidePrices: true,
      documentTitleKey: 'Picture',
      overrideLang: lang,
    );

    final images = <int, pw.MemoryImage>{};
    for (var i = 0; i < data.items.length; i++) {
      final bytes = await _readItemImageBytes(
        db,
        i < items.length ? items[i] : const <String, dynamic>{},
        data.items[i],
      );
      if (bytes != null && bytes.isNotEmpty) {
        final pngBytes = await _asPdfCompatiblePng(bytes);
        if (pngBytes != null && pngBytes.isNotEmpty) {
          images[i] = pw.MemoryImage(pngBytes);
        }
      }
    }

    final pdf = pw.Document();
    final isArabic = lang == AppLanguage.arabic;
    final baseStyle = pw.TextStyle(font: _font, fontSize: 10);
    final boldStyle = pw.TextStyle(font: _fontBold, fontSize: 10);

    if (data.items.isEmpty) {
      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4.landscape,
          margin: const pw.EdgeInsets.fromLTRB(18, 14, 18, 14),
          theme: pw.ThemeData.withFont(base: _font!, bold: _fontBold!),
          build: (context) => pw.Column(
            children: [
              _buildHeader(data, lang, isArabic),
              pw.Expanded(
                child: pw.Center(
                  child: _text(
                    Localization.translate('لا توجد صور لهذه الطلبية', lang),
                    lang,
                    style: boldStyle.copyWith(fontSize: 14),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    } else {
      for (var index = 0; index < data.items.length; index++) {
        pdf.addPage(
          pw.Page(
            pageFormat: PdfPageFormat.a4.landscape,
            margin: const pw.EdgeInsets.fromLTRB(18, 14, 18, 14),
            theme: pw.ThemeData.withFont(base: _font!, bold: _fontBold!),
            build: (context) => pw.Column(
              children: [
                _buildHeader(data, lang, isArabic),
                pw.SizedBox(height: 8),
                pw.Expanded(
                  child: _buildPicturePage(
                    data,
                    data.items[index],
                    images[index],
                    index + 1,
                    lang,
                    baseStyle,
                    boldStyle,
                  ),
                ),
                pw.SizedBox(height: 4),
                _text(
                  '${index + 1} / ${data.items.length}',
                  lang,
                  style: baseStyle.copyWith(
                    color: PdfColors.grey600,
                    fontSize: 9,
                  ),
                ),
              ],
            ),
          ),
        );
      }
    }

    return pdf.save();
  }

  static Future<void> sharePdf({
    required Uint8List bytes,
    required String filename,
  }) async {
    await Printing.sharePdf(bytes: bytes, filename: filename);
  }

  static Future<void> printPdf({
    required Uint8List bytes,
    required String filename,
  }) async {
    await Printing.layoutPdf(name: filename, onLayout: (_) async => bytes);
  }

  static Future<String?> savePdf({
    required Uint8List bytes,
    required String filename,
  }) async {
    if (Platform.isWindows) {
      final picked = await FilePicker.saveFile(
        dialogTitle: filename,
        fileName: filename,
        type: FileType.custom,
        allowedExtensions: ['pdf'],
      );
      if (picked == null) return null;
      await File(picked).writeAsBytes(bytes);
      return picked;
    }

    final tempDir = await getTemporaryDirectory();
    final tempFile = File('${tempDir.path}${Platform.pathSeparator}$filename');
    await tempFile.writeAsBytes(bytes);
    return FlutterFileDialog.saveFile(
      params: SaveFileDialogParams(sourceFilePath: tempFile.path),
    );
  }

  static String fileNameFor(Map<String, dynamic> order, AppLanguage lang) {
    final id = order['id']?.toString().trim() ?? '';
    final clientName = _clientName(
      order,
    ).replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final base = clientName.isNotEmpty
        ? '${Localization.translate('Picture', lang)}_$clientName'
        : '${Localization.translate('Picture', lang)}_${id.isEmpty ? DateTime.now().millisecondsSinceEpoch : id}';
    final clean = base.replaceAll(RegExp(r'\s+'), '_');
    return clean.toLowerCase().endsWith('.pdf') ? clean : '$clean.pdf';
  }

  static Future<void> _ensureDrawingImages(
    SqlDatabase db,
    List<Map<String, dynamic>> items,
  ) async {
    for (final item in items) {
      if (await _hasReadableImage(item)) continue;

      final modelMap = _decodeModelMap(item['partitions_json']);
      if (modelMap.isEmpty) continue;

      try {
        final model = WindowModel(db: db);
        await applyWindowModelAndLoadCatalog(model, modelMap);
        final path = await saveWindowImageToDisk(model, maxSide: 1800);
        if (path.isEmpty) continue;

        item['drawing_image_path'] = path;
        final detailId = (item['id'] as num?)?.toInt();
        if (detailId != null) {
          await db.updateCommandeDetailImagePath(detailId, path);
        }
      } catch (_) {
        item['drawing_image_path'] = '';
      }
    }
  }

  static Future<bool> _hasReadableImage(Map<String, dynamic> item) async {
    final path = item['drawing_image_path']?.toString() ?? '';
    if (path.isNotEmpty && await File(path).exists()) return true;
    final raw = item['drawing_image_base64']?.toString().trim() ?? '';
    return raw.isNotEmpty;
  }

  static Future<Uint8List?> _readItemImageBytes(
    SqlDatabase db,
    Map<String, dynamic> rawItem,
    DevisLineItem lineItem,
  ) async {
    final modelMap = _decodeModelMap(rawItem['partitions_json']);
    if (modelMap.isNotEmpty) {
      try {
        final model = WindowModel(db: db);
        await applyWindowModelAndLoadCatalog(model, modelMap);
        return captureWindowImage(model, maxSide: 2600);
      } catch (_) {}
    }

    final path =
        (lineItem.imagePath?.trim().isNotEmpty == true
            ? lineItem.imagePath!.trim()
            : rawItem['drawing_image_path']?.toString().trim()) ??
        '';

    if (path.isNotEmpty) {
      if (path.startsWith('assets/') || path.startsWith('Icon/')) {
        try {
          return (await rootBundle.load(path)).buffer.asUint8List();
        } catch (_) {
          if (!path.startsWith('assets/')) {
            try {
              return (await rootBundle.load(
                'assets/$path',
              )).buffer.asUint8List();
            } catch (_) {}
          }
        }
      }

      try {
        final file = File(path);
        if (await file.exists()) return file.readAsBytes();
      } catch (_) {}
    }

    final raw = rawItem['drawing_image_base64']?.toString().trim() ?? '';
    if (raw.isEmpty) return null;

    try {
      final separator = raw.indexOf(',');
      final encoded = raw.startsWith('data:image') && separator >= 0
          ? raw.substring(separator + 1)
          : raw;
      return base64Decode(encoded);
    } catch (_) {
      return null;
    }
  }

  static Future<Uint8List?> _asPdfCompatiblePng(Uint8List bytes) async {
    try {
      final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      final descriptor = await ui.ImageDescriptor.encoded(buffer);
      final codec = await descriptor.instantiateCodec();
      final frame = await codec.getNextFrame();
      final png = await frame.image.toByteData(format: ui.ImageByteFormat.png);
      frame.image.dispose();
      codec.dispose();
      descriptor.dispose();
      buffer.dispose();
      return png?.buffer.asUint8List();
    } catch (_) {
      return null;
    }
  }

  static Map<String, dynamic> _decodeModelMap(dynamic raw) {
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) return Map<String, dynamic>.from(raw);
    final text = raw?.toString().trim() ?? '';
    if (text.length < 5) return const {};
    try {
      final decoded = jsonDecode(text);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {}
    return const {};
  }

  static pw.Widget _buildHeader(
    DevisData data,
    AppLanguage lang,
    bool isArabic,
  ) {
    final titleStyle = pw.TextStyle(
      font: _fontBold,
      fontSize: 20,
      color: PdfColors.blue800,
    );
    final metaStyle = pw.TextStyle(
      font: _font,
      fontSize: 10,
      color: PdfColors.grey700,
    );

    final rows = [
      '${Localization.translate('Commande', lang)} #${data.sequenceNumber > 0 ? data.sequenceNumber : data.orderId}',
      '${Localization.translate('Customer', lang)}: ${data.clientName}',
      '${Localization.translate('تاريخ الإنشاء', lang)}: ${data.orderDate}',
    ];

    return pw.Container(
      padding: const pw.EdgeInsets.only(bottom: 12),
      decoration: const pw.BoxDecoration(
        border: pw.Border(
          bottom: pw.BorderSide(color: PdfColors.blue200, width: 1),
        ),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: isArabic
                  ? pw.CrossAxisAlignment.end
                  : pw.CrossAxisAlignment.start,
              children: [
                _text(
                  Localization.translate('Picture', lang),
                  lang,
                  style: titleStyle,
                ),
                pw.SizedBox(height: 4),
                ...rows.map((row) => _text(row, lang, style: metaStyle)),
              ],
            ),
          ),
          if (data.workshop.name.trim().isNotEmpty) ...[
            pw.SizedBox(width: 16),
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 6,
              ),
              decoration: pw.BoxDecoration(
                color: PdfColors.blue50,
                borderRadius: pw.BorderRadius.circular(6),
              ),
              child: _text(
                data.workshop.name,
                lang,
                style: pw.TextStyle(font: _fontBold, fontSize: 11),
              ),
            ),
          ],
        ],
      ),
    );
  }

  static pw.Widget _buildPicturePage(
    DevisData data,
    DevisLineItem item,
    pw.MemoryImage? image,
    int index,
    AppLanguage lang,
    pw.TextStyle baseStyle,
    pw.TextStyle boldStyle,
  ) {
    final orderMeta = <String>[
      '${Localization.translate('Customer', lang)}: ${data.clientName}',
      if (data.clientPhone.trim().isNotEmpty)
        '${Localization.translate('Phone', lang)}: ${data.clientPhone}',
      if (_projectName(data).isNotEmpty)
        '${Localization.translate('المشروع', lang)}: ${_projectName(data)}',
      if (_siteLocation(data).isNotEmpty)
        '${Localization.translate('الموقع', lang)}: ${_siteLocation(data)}',
    ];
    final productMeta = <String>[
      if (item.width > 0 || item.height > 0)
        '${Localization.translate('الأبعاد', lang)}: ${item.width} x ${item.height} mm',
      '${Localization.translate('الكمية', lang)}: ${item.quantity}',
      if (item.color.trim().isNotEmpty)
        '${Localization.translate('اللون', lang)}: ${item.color}',
    ];
    final detailLines = _prioritizedDetails(item.details);
    final imageFlex = detailLines.length > 12 ? 5 : 6;
    final detailsFlex = detailLines.length > 12 ? 4 : 3;

    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 18),
      child: pw.Column(
        crossAxisAlignment: lang == AppLanguage.arabic
            ? pw.CrossAxisAlignment.end
            : pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: lang == AppLanguage.arabic
                      ? pw.CrossAxisAlignment.end
                      : pw.CrossAxisAlignment.start,
                  children: [
                    _text(
                      '$index. ${item.title}',
                      lang,
                      style: boldStyle.copyWith(fontSize: 15),
                    ),
                    pw.SizedBox(height: 3),
                    _text(
                      [...orderMeta, ...productMeta].join('   |   '),
                      lang,
                      style: baseStyle.copyWith(
                        color: PdfColors.grey700,
                        fontSize: 9.2,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 8),
          pw.Expanded(
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: [
                pw.Expanded(
                  flex: imageFlex,
                  child: pw.Container(
                    alignment: pw.Alignment.center,
                    decoration: pw.BoxDecoration(
                      color: PdfColors.white,
                      border: pw.Border.all(
                        color: PdfColors.grey300,
                        width: 0.6,
                      ),
                    ),
                    child: image == null
                        ? _text(
                            '-',
                            lang,
                            style: boldStyle.copyWith(fontSize: 28),
                          )
                        : pw.Padding(
                            padding: const pw.EdgeInsets.all(6),
                            child: pw.Image(image, fit: pw.BoxFit.contain),
                          ),
                  ),
                ),
                pw.SizedBox(width: 10),
                pw.Expanded(
                  flex: detailsFlex,
                  child: pw.Container(
                    padding: const pw.EdgeInsets.all(8),
                    decoration: pw.BoxDecoration(
                      color: PdfColors.grey50,
                      border: pw.Border.all(
                        color: PdfColors.grey300,
                        width: 0.5,
                      ),
                    ),
                    child: pw.Column(
                      crossAxisAlignment: lang == AppLanguage.arabic
                          ? pw.CrossAxisAlignment.end
                          : pw.CrossAxisAlignment.start,
                      children: [
                        _text(
                          Localization.translate('التفاصيل والقياسات', lang),
                          lang,
                          style: boldStyle.copyWith(fontSize: 11),
                        ),
                        pw.SizedBox(height: 5),
                        ...detailLines.map(
                          (detail) => pw.Padding(
                            padding: const pw.EdgeInsets.only(bottom: 2.2),
                            child: _text(
                              detail,
                              lang,
                              style: baseStyle.copyWith(fontSize: 8.8),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static List<String> _prioritizedDetails(List<String> details) {
    final cleaned = details
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList(growable: false);
    final priority = <String>[];
    final rest = <String>[];
    for (final line in cleaned) {
      final lower = line.toLowerCase();
      final important =
          lower.contains('largeur') ||
          lower.contains('width') ||
          lower.contains('العرض') ||
          lower.contains('hauteur') ||
          lower.contains('height') ||
          lower.contains('الارتفاع') ||
          lower.contains('poignée') ||
          lower.contains('handle') ||
          lower.contains('مقبض') ||
          lower.contains('vitrage') ||
          lower.contains('glass') ||
          lower.contains('زجاج') ||
          lower.contains('couleur') ||
          lower.contains('color') ||
          lower.contains('لون') ||
          lower.contains('couvre') ||
          lower.contains('cover') ||
          lower.contains('كوفر');
      (important ? priority : rest).add(line);
    }
    return [...priority, ...rest];
  }

  static String _projectName(DevisData data) {
    return data.rawOrder?['project_name']?.toString().trim() ?? '';
  }

  static String _siteLocation(DevisData data) {
    final order = data.rawOrder ?? const <String, dynamic>{};
    final candidates = <String>[
      order['window_location']?.toString() ?? '',
      order['site_location']?.toString() ?? '',
      order['location']?.toString() ?? '',
      order['client_address']?.toString() ?? '',
      order['address']?.toString() ?? '',
      order['project_description']?.toString() ?? '',
    ];
    for (final value in candidates) {
      final clean = value.trim();
      if (clean.isNotEmpty) return clean;
    }
    return '';
  }

  static String _clientName(Map<String, dynamic> order) {
    final first = order['firstname']?.toString().trim() ?? '';
    final last = order['lastname']?.toString().trim() ?? '';
    final direct =
        order['client_name']?.toString().trim() ??
        order['client_display']?.toString().trim() ??
        '';
    final combined = '$first $last'.trim();
    return combined.isNotEmpty ? combined : direct;
  }

  static pw.Text _text(
    String text,
    AppLanguage lang, {
    pw.TextStyle? style,
    pw.TextAlign? align,
  }) {
    return pw.Text(
      _shapeText(text),
      style: style,
      textDirection: pw.TextDirection.ltr,
      textAlign:
          align ??
          (lang == AppLanguage.arabic ? pw.TextAlign.right : pw.TextAlign.left),
    );
  }

  static String _shapeText(String text) {
    if (!RegExp(r'[\u0600-\u06FF]').hasMatch(text)) return text;
    final reshaped = ArabicReshaper.instance.reshape(text);
    final tokens = reshaped.split(' ');
    final processed = tokens.map((token) {
      if (RegExp(r'[\u0600-\u06FF]').hasMatch(token)) {
        return String.fromCharCodes(token.runes.toList().reversed);
      }
      return token;
    }).toList();
    return processed.reversed.join(' ');
  }
}
