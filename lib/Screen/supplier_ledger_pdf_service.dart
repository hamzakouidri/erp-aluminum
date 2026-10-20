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
import 'package:intl/intl.dart' hide TextDirection;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';
import 'package:database_data/arabic_reshaper/arabic_reshaper.dart';
import '../settings/localization.dart';
import '../settings/app_settings.dart';
import '../services/pdf_font_cache.dart';
import '../services/pdf_branding.dart';

class SupplierLedgerPdfService {
  static String _safeFilePart(Object? value, {String fallback = 'supplier'}) {
    final cleaned = (value?.toString() ?? '')
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
        .trim();
    return cleaned.isEmpty ? fallback : cleaned;
  }

  static bool _hasArabic(String text) {
    return text.runes.any(
      (r) =>
          (r >= 0x0600 && r <= 0x06FF) ||
          (r >= 0xFB50 && r <= 0xFEFF),
    );
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

  static Future<Uint8List> generateSupplierLedgerPdfBytes(
    Map<String, dynamic> supplier,
    List<Map<String, dynamic>> items, {
    AppLanguage lang = AppLanguage.arabic,
  }) async {
    final pdf = pw.Document();

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
    final supplierName = supplier['name']?.toString() ?? '';
    final supplierPhone = supplier['phone']?.toString() ?? '';
    final supplierEmail = supplier['email']?.toString() ?? '';

    final currency = lang == AppLanguage.arabic ? 'د.ج' : 'DA';

    String t(String key) {
      return _ar(Localization.translate(key, lang));
    }

    double totalPurchases = 0.0;
    double totalPaid = 0.0;
    double totalReturns = 0.0;

    for (var item in items) {
      final type = item['type'] ?? '';
      final double debit = (item['debit'] as num?)?.toDouble() ?? 0.0;
      final double credit = (item['credit'] as num?)?.toDouble() ?? 0.0;

      if (type == 'Purchase') {
        totalPurchases += debit;
      } else if (type == 'Payment') {
        totalPaid += credit;
      } else if (type == 'Return') {
        totalReturns += credit;
      }
    }

    final netDue = totalPurchases - totalPaid - totalReturns;

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        textDirection: pw.TextDirection.ltr,
        margin: const pw.EdgeInsets.all(30),
        theme: pw.ThemeData.withFont(base: fontRegular, bold: fontBold),
        footer: (_) => pw.Center(child: PdfBranding.footerMark(fontRegular)),
        build: (context) {
          return [
            // Header Section
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.center,
                  children: [
                    if (logoWidget != null) logoWidget,
                    if (logoWidget != null) pw.SizedBox(width: 10),
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          _ar(workshopName),
                          style: pw.TextStyle(font: fontBold, fontSize: 16, color: PdfColors.blue900),
                        ),
                        pw.Text(
                          _ar('كشف حساب المورد / Extrait de Compte Fournisseur'),
                          style: pw.TextStyle(font: fontRegular, fontSize: 9, color: PdfColors.grey700),
                        ),
                      ],
                    ),
                  ],
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text(
                      '${t('تاريخ التصدير')}: ${DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now())}',
                      style: pw.TextStyle(font: fontRegular, fontSize: 8),
                    ),
                  ],
                ),
              ],
            ),
            pw.SizedBox(height: 15),
            pw.Divider(thickness: 1, color: PdfColors.blue900),
            pw.SizedBox(height: 10),

            // Supplier Information Box
            pw.Container(
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.blue200),
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
                color: PdfColors.blue50,
              ),
              padding: const pw.EdgeInsets.all(10),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        '${t('المورد')}: ${_ar(supplierName)}',
                        style: pw.TextStyle(font: fontBold, fontSize: 11, color: PdfColors.blue900),
                      ),
                      if (supplierPhone.isNotEmpty)
                        pw.Text('${t('الهاتف')}: $supplierPhone', style: pw.TextStyle(font: fontRegular, fontSize: 9)),
                    ],
                  ),
                  if (supplierEmail.isNotEmpty)
                    pw.Text('${t('البريد الإلكتروني')}: $supplierEmail', style: pw.TextStyle(font: fontRegular, fontSize: 9)),
                ],
              ),
            ),
            pw.SizedBox(height: 15),

            // Ledger Table
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
              columnWidths: {
                0: const pw.FlexColumnWidth(1.2), // Date
                1: const pw.FlexColumnWidth(1.4), // Type
                2: const pw.FlexColumnWidth(2.5), // Description
                3: const pw.FlexColumnWidth(1.3), // Debit (Purchases)
                4: const pw.FlexColumnWidth(1.3), // Credit (Payments/Returns)
              },
              children: [
                // Table Header
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColors.blue800),
                  children: [
                    _tableCell(t('التاريخ'), fontBold, isHeader: true),
                    _tableCell(t('نوع المعاملة'), fontBold, isHeader: true),
                    _tableCell(t('البيان / التفاصيل'), fontBold, isHeader: true),
                    _tableCell(t('مشتريات (مدين)'), fontBold, isHeader: true),
                    _tableCell(t('دفعات / إرجاع (دائن)'), fontBold, isHeader: true),
                  ],
                ),

                // Table Rows
                for (var item in items)
                  pw.TableRow(
                    children: [
                      _tableCell(DateFormat('yyyy-MM-dd').format(item['date'] as DateTime), fontRegular),
                      _tableCell(_ar(item['typeLabel']?.toString() ?? ''), fontRegular),
                      _tableCell(_ar(item['description']?.toString() ?? ''), fontRegular),
                      _tableCell(
                        (item['debit'] as num?)?.toDouble() != 0
                            ? formatter.format((item['debit'] as num).toDouble())
                            : '-',
                        fontRegular,
                        align: pw.Alignment.centerRight,
                      ),
                      _tableCell(
                        (item['credit'] as num?)?.toDouble() != 0
                            ? formatter.format((item['credit'] as num).toDouble())
                            : '-',
                        fontRegular,
                        align: pw.Alignment.centerRight,
                      ),
                    ],
                  ),
              ],
            ),
            pw.SizedBox(height: 15),

            // Summary Section
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.end,
              children: [
                pw.Container(
                  width: 260,
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: PdfColors.grey400),
                    borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
                    color: PdfColors.grey100,
                  ),
                  padding: const pw.EdgeInsets.all(10),
                  child: pw.Column(
                    children: [
                      _summaryRow('${t('إجمالي المشتريات')} :', '${formatter.format(totalPurchases)} $currency', fontRegular),
                      pw.SizedBox(height: 4),
                      _summaryRow('${t('إجمالي المدفوعات')} :', '${formatter.format(totalPaid)} $currency', fontRegular),
                      pw.SizedBox(height: 4),
                      _summaryRow('${t('إجمالي المرتجعات')} :', '${formatter.format(totalReturns)} $currency', fontRegular),
                      pw.Divider(thickness: 0.5),
                      _summaryRow(
                        '${t('الرصيد المتبقي')} :',
                        '${formatter.format(netDue)} $currency',
                        fontBold,
                        textColor: netDue > 0 ? PdfColors.red800 : PdfColors.green800,
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
                    pw.Text(t('توقيع المورد'), style: pw.TextStyle(font: fontBold, fontSize: 9)),
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

  static Future<void> printSupplierLedger(
    Map<String, dynamic> supplier,
    List<Map<String, dynamic>> items, {
    AppLanguage lang = AppLanguage.arabic,
  }) async {
    final bytes = await generateSupplierLedgerPdfBytes(supplier, items, lang: lang);
    final name = _safeFilePart(supplier['name']);
    await Printing.layoutPdf(
      onLayout: (_) async => bytes,
      name: 'kachef_mowarrid_$name.pdf',
    );
  }

  static Future<void> shareSupplierLedger(
    Map<String, dynamic> supplier,
    List<Map<String, dynamic>> items, {
    AppLanguage lang = AppLanguage.arabic,
  }) async {
    try {
      final bytes = await generateSupplierLedgerPdfBytes(supplier, items, lang: lang);
      final name = _safeFilePart(supplier['name']);
      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/kachef_mowarrid_$name.pdf');
      await file.writeAsBytes(bytes);
      await Share.shareXFiles([XFile(file.path)], text: 'كشف حساب المورد $name');
    } catch (_) {
      try {
        final bytes = await generateSupplierLedgerPdfBytes(supplier, items, lang: lang);
        final name = _safeFilePart(supplier['name']);
        await Printing.sharePdf(bytes: bytes, filename: 'kachef_mowarrid_$name.pdf');
      } catch (_) {}
    }
  }

  static Future<void> saveSupplierLedger(
    Map<String, dynamic> supplier,
    List<Map<String, dynamic>> items,
    BuildContext context, {
    AppLanguage lang = AppLanguage.arabic,
  }) async {
    try {
      final bytes = await generateSupplierLedgerPdfBytes(supplier, items, lang: lang);
      final name = _safeFilePart(supplier['name']);
      final filename = 'kachef_mowarrid_$name.pdf';
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
