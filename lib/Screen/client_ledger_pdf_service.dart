import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_file_dialog/flutter_file_dialog.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';
import 'package:database_data/arabic_reshaper/arabic_reshaper.dart';
import '../settings/localization.dart';
import '../settings/app_settings.dart';
import '../services/pdf_font_cache.dart';

class ClientLedgerPdfService {
  static String _safeFilePart(Object? value, {String fallback = 'client'}) {
    final cleaned = (value?.toString() ?? '')
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
        .trim();
    return cleaned.isEmpty ? fallback : cleaned;
  }

  static bool _hasArabic(String text) {
    return text.runes.any(
      (r) =>
          (r >= 0x0600 && r <= 0x06FF) || // Arabic block
          (r >= 0xFB50 && r <= 0xFEFF),
    ); // Arabic Presentation Forms
  }

  static String _ar(String text) {
    if (!_hasArabic(text)) return text;
    final reshaped = ArabicReshaper.instance.reshape(text);
    final tokens = reshaped.split(' ');
    final processed = tokens.map((token) {
      if (_hasArabic(token)) {
        return String.fromCharCodes(token.runes.toList().reversed);
      }
      return token;
    }).toList();
    return processed.reversed.join(' ');
  }

  static Future<Uint8List> generateLedgerPdfBytes(
    Map<String, dynamic> client,
    List<Map<String, dynamic>> items, {
    required bool detailed,
    AppLanguage lang = AppLanguage.arabic,
  }) async {
    final pdf = pw.Document();

    // Load logo from SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    final logoBase64 = prefs.getString('workshop_logo_base64') ?? '';
    final workshopName = prefs.getString('workshop_name') ?? 'نورالور';
    pw.Widget? logoWidget;
    if (logoBase64.isNotEmpty) {
      try {
        final imageBytes = base64Decode(logoBase64);
        logoWidget = pw.Image(pw.MemoryImage(imageBytes), width: 45, height: 45);
      } catch (_) {}
    }

    final fonts = await PdfFontCache.load();
    final fontRegular = fonts.regular;
    final fontBold = fonts.bold;

    final formatter = NumberFormat('#,##0.00');
    final clientName = '${client['lastname'] ?? ''} ${client['firstname'] ?? ''}'.trim();
    final clientPhone = client['phone1']?.toString() ?? '';
    final clientPhone2 = client['phone2']?.toString() ?? '';
    final clientAddress = client['address']?.toString() ?? '';

    final currency = lang == AppLanguage.arabic ? 'د.ج' : 'DA';

    // Helper translation / reshaping function
    String t(String key) {
      return _ar(Localization.translate(key, lang));
    }

    // Calculate totals
    double totalDebit = 0.0;
    double totalCredit = 0.0;
    for (var item in items) {
      totalDebit += (item['debit'] as num?)?.toDouble() ?? 0.0;
      totalCredit += (item['credit'] as num?)?.toDouble() ?? 0.0;
    }
    final netBalance = totalDebit - totalCredit;

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        textDirection: pw.TextDirection.ltr, // _ar() visual order requires LTR run direction
        margin: const pw.EdgeInsets.all(30),
        build: (context) {
          return [
            // Header Section
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.center,
                  children: [
                    if (logoWidget != null) ...[
                      logoWidget,
                      pw.SizedBox(width: 10),
                    ],
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(_ar(workshopName),
                            style: pw.TextStyle(font: fontBold, fontSize: 16, color: PdfColors.blue800)),
                        pw.SizedBox(height: 4),
                        pw.Text(t('كشف حساب الزبون'),
                            style: pw.TextStyle(font: fontBold, fontSize: 11, color: PdfColors.grey700)),
                      ],
                    ),
                  ],
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text('${t('التاريخ')}: ${DateFormat('dd/MM/yyyy').format(DateTime.now())}',
                        style: pw.TextStyle(font: fontRegular, fontSize: 9)),
                  ],
                ),
              ],
            ),
            pw.SizedBox(height: 15),
            pw.Divider(thickness: 1, color: PdfColors.blue800),
            pw.SizedBox(height: 10),

            // Client Info block
            pw.Container(
              padding: const pw.EdgeInsets.all(10),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.grey300),
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
                color: PdfColors.grey50,
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Row(
                    children: [
                      pw.Text('${t('الزبون')}: ', style: pw.TextStyle(font: fontBold, fontSize: 10)),
                      pw.SizedBox(width: 4),
                      pw.Text(_ar(clientName), style: pw.TextStyle(font: fontRegular, fontSize: 10)),
                    ],
                  ),
                  pw.SizedBox(height: 4),
                  pw.Row(
                    children: [
                      pw.Text('${t('الهاتف')}: ', style: pw.TextStyle(font: fontBold, fontSize: 10)),
                      pw.SizedBox(width: 4),
                      pw.Text(
                        clientPhone2.isNotEmpty && clientPhone2 != '0' && clientPhone2 != 'null'
                            ? '$clientPhone  ·  $clientPhone2'
                            : clientPhone,
                        style: pw.TextStyle(font: fontRegular, fontSize: 10),
                      ),
                    ],
                  ),
                  if (clientAddress.isNotEmpty && clientAddress != 'null') ...[
                    pw.SizedBox(height: 4),
                    pw.Row(
                      children: [
                        pw.Text('${t('العنوان')}: ', style: pw.TextStyle(font: fontBold, fontSize: 10)),
                        pw.SizedBox(width: 4),
                        pw.Text(_ar(clientAddress), style: pw.TextStyle(font: fontRegular, fontSize: 10)),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            pw.SizedBox(height: 20),

            // Ledger details table
            pw.Table(
              columnWidths: {
                0: const pw.FixedColumnWidth(45),  // N° Commande
                1: const pw.FixedColumnWidth(45),  // N° Reçu
                2: const pw.FixedColumnWidth(55),  // Date
                3: const pw.FlexColumnWidth(2),    // Description
                4: const pw.FixedColumnWidth(70),  // Debit
                5: const pw.FixedColumnWidth(70),  // Credit
                6: const pw.FixedColumnWidth(75),  // Balance
              },
              border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
              children: [
                // Header row
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColors.blue800),
                  children: [
                    _tableCell(t('رقم الطلبية'), fontBold, isHeader: true, align: pw.Alignment.center),
                    _tableCell(t('رقم الدفعة'), fontBold, isHeader: true, align: pw.Alignment.center),
                    _tableCell(t('التاريخ'), fontBold, isHeader: true, align: pw.Alignment.center),
                    _tableCell(t('البيان'), fontBold, isHeader: true),
                    _tableCell(t('مدين (+)'), fontBold, isHeader: true, align: pw.Alignment.center),
                    _tableCell(t('دائن (-)'), fontBold, isHeader: true, align: pw.Alignment.center),
                    _tableCell(t('الرصيد'), fontBold, isHeader: true, align: pw.Alignment.center),
                  ],
                ),
                // Transaction rows
                ...items.map((item) {
                  final debitVal = (item['debit'] as num?)?.toDouble() ?? 0.0;
                  final creditVal = (item['credit'] as num?)?.toDouble() ?? 0.0;
                  final balanceVal = (item['runningBalance'] as num?)?.toDouble() ?? 0.0;
                  final dateRaw = item['date'];
                  String dateStr = '';
                  if (dateRaw is DateTime) {
                    dateStr = DateFormat('dd/MM/yyyy').format(dateRaw);
                  } else {
                    dateStr = dateRaw.toString();
                  }

                  final type = item['type'];
                  final id = item['id'];
                  String orderIdStr = '-';
                  String paymentIdStr = '-';

                  String descStr = '';
                  if (type == 'Order') {
                    orderIdStr = '#$id';
                    descStr = '${Localization.translate('طلب شراء', lang)} #$id';
                  } else if (type == 'Payment') {
                    paymentIdStr = '#$id';
                    final refId = item['rawData']?['reference_id'] ?? item['referenceId'];
                    if (refId != null) {
                      orderIdStr = '#$refId';
                    }
                    final method = item['rawData']?['payment_method']?.toString() ?? 'Espèce';
                    final methodTrans = Localization.translate(method, lang);
                    descStr = '${Localization.translate('دفعة مالية', lang)} ($methodTrans)';
                  } else if (type == 'Refund') {
                    paymentIdStr = '#$id';
                    final refId = item['rawData']?['reference_id'] ?? item['referenceId'];
                    if (refId != null) {
                      orderIdStr = '#$refId';
                    }
                    final method = item['rawData']?['payment_method']?.toString() ?? 'Espèce';
                    final methodTrans = Localization.translate(method, lang);
                    descStr = '${Localization.translate('مسترجع نقدي', lang)} ($methodTrans)';
                  }

                  // Build cell content
                  final List<pw.Widget> descWidgets = [
                    pw.Text(_ar(descStr), style: pw.TextStyle(font: fontRegular, fontSize: 9)),
                  ];

                  // Detailed section (order details list)
                  if (detailed && item['type'] == 'Order' && item['details'] != null) {
                    final detailsList = item['details'] as List<dynamic>;
                    for (var sub in detailsList) {
                      final wt = sub['window_type']?.toString() ?? '';
                      final game = sub['game']?.toString() ?? '';
                      final w = sub['largeur']?.toString() ?? '';
                      final h = sub['hauteur']?.toString() ?? '';
                      final double qtyVal = (sub['quantity'] as num?)?.toDouble() ?? 1.0;
                      final double unitPrice = (sub['price'] as num?)?.toDouble() ?? 0.0;
                      final double totalPrice = unitPrice * qtyVal;

                      final subStr = ' - $wt $game (${w}x$h) [${formatter.format(unitPrice)} $currency × ${qtyVal.toInt()}] = ${formatter.format(totalPrice)} $currency';
                      descWidgets.add(
                        pw.Padding(
                          padding: const pw.EdgeInsets.only(top: 2, left: 8),
                          child: pw.Text(
                            _ar(subStr),
                            style: pw.TextStyle(font: fontRegular, fontSize: 8, color: PdfColors.grey600),
                          ),
                        ),
                      );
                    }
                  }

                  return pw.TableRow(
                    children: [
                      _tableCell(orderIdStr, fontRegular, align: pw.Alignment.center),
                      _tableCell(paymentIdStr, fontRegular, align: pw.Alignment.center),
                      _tableCell(dateStr, fontRegular, align: pw.Alignment.center),
                      pw.Container(
                        padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 6),
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: descWidgets,
                        ),
                      ),
                      _tableCell(debitVal > 0 ? '${formatter.format(debitVal)} $currency' : '-', fontRegular, align: pw.Alignment.centerRight),
                      _tableCell(creditVal > 0 ? '${formatter.format(creditVal)} $currency' : '-', fontRegular, align: pw.Alignment.centerRight),
                      _tableCell('${formatter.format(balanceVal)} $currency', fontBold, align: pw.Alignment.centerRight),
                    ],
                  );
                }),
              ],
            ),
            pw.SizedBox(height: 20),

            // Summary box
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.end,
              children: [
                pw.Container(
                  width: 250,
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: PdfColors.grey400),
                    borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
                    color: PdfColors.grey100,
                  ),
                  padding: const pw.EdgeInsets.all(8),
                  child: pw.Column(
                    children: [
                      _summaryRow('${t('إجمالي الطلبيات')} :', '${formatter.format(totalDebit)} $currency', fontRegular),
                      pw.SizedBox(height: 4),
                      _summaryRow('${t('إجمالي المقبوضات')} :', '${formatter.format(totalCredit)} $currency', fontRegular),
                      pw.Divider(thickness: 0.5),
                      _summaryRow(
                        '${t('الرصيد المتبقي')} :',
                        '${formatter.format(netBalance)} $currency',
                        fontBold,
                        textColor: netBalance > 0 ? PdfColors.red800 : PdfColors.green800,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 30),

            // Signatures block
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Column(
                  children: [
                    pw.Text(t('توقيع الزبون'), style: pw.TextStyle(font: fontBold, fontSize: 9)),
                    pw.SizedBox(height: 30),
                    pw.Container(width: 100, height: 0.5, color: PdfColors.black),
                  ],
                ),
                pw.Column(
                  children: [
                    pw.Text(t('إمضاء الورشة'), style: pw.TextStyle(font: fontBold, fontSize: 9)),
                    pw.SizedBox(height: 30),
                    pw.Container(width: 100, height: 0.5, color: PdfColors.black),
                  ],
                ),
              ],
            ),
          ];
        },
      ),
    );

    return pdf.save();
  }

  static pw.Widget _tableCell(String text, pw.Font font, {bool isHeader = false, pw.Alignment align = pw.Alignment.centerLeft}) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 6),
      alignment: align,
      child: pw.Text(
        text,
        style: pw.TextStyle(
          font: font,
          fontSize: isHeader ? 9 : 8.5,
          color: isHeader ? PdfColors.white : PdfColors.black,
        ),
      ),
    );
  }

  static pw.Widget _summaryRow(String label, String value, pw.Font font, {PdfColor? textColor}) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(label, style: pw.TextStyle(font: font, fontSize: 8.5)),
        pw.Text(value, style: pw.TextStyle(font: font, fontSize: 8.5, color: textColor)),
      ],
    );
  }

  static Future<void> printClientLedger(
    Map<String, dynamic> client,
    List<Map<String, dynamic>> items, {
    required bool detailed,
    AppLanguage lang = AppLanguage.arabic,
  }) async {
    final bytes = await generateLedgerPdfBytes(client, items, detailed: detailed, lang: lang);
    final clientName = _safeFilePart(
      '${client['lastname'] ?? ''}_${client['firstname'] ?? ''}',
    );
    await Printing.layoutPdf(
      onLayout: (_) async => bytes,
      name: 'fiche_client_$clientName.pdf',
    );
  }

  static Future<void> shareClientLedger(
    Map<String, dynamic> client,
    List<Map<String, dynamic>> items, {
    required bool detailed,
    AppLanguage lang = AppLanguage.arabic,
  }) async {
    final bytes = await generateLedgerPdfBytes(client, items, detailed: detailed, lang: lang);
    final clientName = '${client['lastname'] ?? ''}_${client['firstname'] ?? ''}'.trim();
    try {
      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/fiche_client_$clientName.pdf');
      await file.writeAsBytes(bytes, flush: true);
      await Share.shareXFiles(
        [XFile(file.path)],
        text: 'كشف حساب الزبون $clientName',
      );
    } catch (_) {
      await Printing.sharePdf(
        bytes: bytes,
        filename: 'fiche_client_$clientName.pdf',
      );
    }
  }

  static Future<void> saveClientLedger(
    Map<String, dynamic> client,
    List<Map<String, dynamic>> items,
    BuildContext context, {
    required bool detailed,
    AppLanguage lang = AppLanguage.arabic,
  }) async {
    try {
      final bytes = await generateLedgerPdfBytes(client, items, detailed: detailed, lang: lang);
      final clientName = _safeFilePart(
        '${client['lastname'] ?? ''}_${client['firstname'] ?? ''}',
      );
      final filename = 'fiche_client_$clientName.pdf';
      String? finalPath;

      if (Platform.isWindows) {
        try {
          final downloadsDir = await getDownloadsDirectory();
          if (downloadsDir != null) {
            final file = File('${downloadsDir.path}\\$filename');
            await file.writeAsBytes(bytes);
            finalPath = file.path;
          }
        } catch (_) {}

        if (finalPath == null) {
          final picked = await FilePicker.saveFile(
            dialogTitle: Localization.translate('حفظ كشف الحساب', lang),
            fileName: filename,
            type: FileType.custom,
            allowedExtensions: ['pdf'],
          );
          if (picked != null) {
            await File(picked).writeAsBytes(bytes);
            finalPath = picked;
          }
        }
      } else {
        final tempDir = await getTemporaryDirectory();
        final tempFile = File('${tempDir.path}/$filename');
        await tempFile.writeAsBytes(bytes);
        final params = SaveFileDialogParams(sourceFilePath: tempFile.path);
        finalPath = await FlutterFileDialog.saveFile(params: params);
      }

      if (finalPath != null && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              Localization.translate('تم حفظ كشف الحساب بنجاح', lang),
              style: const TextStyle(fontFamily: 'Cairo'),
            ),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${Localization.translate('خطأ في حفظ الملف', lang)}: $e',
              style: const TextStyle(fontFamily: 'Cairo'),
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}
