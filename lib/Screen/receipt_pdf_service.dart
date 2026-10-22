import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:file_picker/file_picker.dart';
import 'package:flutter_file_dialog/flutter_file_dialog.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import '../settings/app_settings.dart';
import '../settings/localization.dart';
import '../services/pdf_font_cache.dart';

class ReceiptPdfService {
  static String formatReceiptNumber(Map<String, dynamic> transaction) {
    final isEncaissement = (transaction['transaction_type'] ?? '') == 'Encaissement';
    final prefix = isEncaissement ? 'BR' : 'BD';

    String year2 = (DateTime.now().year % 100).toString().padLeft(2, '0');
    final createdAt = transaction['created_at']?.toString() ?? '';
    if (createdAt.isNotEmpty) {
      try {
        final dt = DateTime.parse(createdAt);
        year2 = (dt.year % 100).toString().padLeft(2, '0');
      } catch (_) {}
    }

    final id = (transaction['id'] as num?)?.toInt() ?? 1;
    final seqNum = id.toString().padLeft(3, '0');
    return '$prefix$year2$seqNum';
  }

  static Future<Uint8List> generateReceiptPdfBytes(Map<String, dynamic> transaction) async {
    final pdf = pw.Document();
    final prefs = await SharedPreferences.getInstance();
    final workshopName = prefs.getString('workshop_name') ?? 'نورالور';
    final logoBase64 = prefs.getString('workshop_logo_base64') ?? '';
    final pdfLang = AppSettingsProvider.languageFromPreferences(prefs);
    final currency = pdfLang == AppLanguage.arabic ? 'د.ج' : 'DA';
    String tr(String key) => Localization.translate(key, pdfLang);

    pw.Widget? logoWidget;
    if (logoBase64.isNotEmpty) {
      try {
        final imageBytes = base64Decode(logoBase64);
        logoWidget = pw.Image(pw.MemoryImage(imageBytes), width: 35, height: 35);
      } catch (_) {}
    }

    final fonts = await PdfFontCache.load();
    final fontRegular = fonts.regular;
    final fontBold = fonts.bold;

    final formatter = NumberFormat('#,##0.00');
    final isEncaissement =
        (transaction['transaction_type'] ?? '') == 'Encaissement';

    final receiptTitle = isEncaissement
        ? 'وصل استلام / Bon de Versement'
        : 'وصل دفع / Bon de Remboursement';

    final receiptTitleFr =
        isEncaissement ? 'REÇU DE PAIEMENT' : 'BON DE DÉCAISSEMENT';

    final amount = (transaction['amount'] as num?)?.toDouble() ?? 0.0;
    final oldBalance =
        (transaction['old_balance'] as num?)?.toDouble() ?? 0.0;
    final newBalance =
        (transaction['new_balance'] as num?)?.toDouble() ?? 0.0;
    final entityType = _readableText(transaction['entity_type']);
    final description = _readableText(transaction['description']);
    final phone = _readableText(transaction['phone']);
    final receiptId = formatReceiptNumber(transaction);
    final createdAt = transaction['created_at'] ?? '';

    String dateStr = createdAt;
    String timeStr = '';
    if (createdAt.length >= 19) {
      final dt = DateTime.tryParse(createdAt);
      if (dt != null) {
        dateStr = DateFormat('dd/MM/yyyy').format(dt);
        timeStr = DateFormat('HH:mm').format(dt);
      }
    }

    // اسم الجهة من الوصف
    String entityName = '';
    if (description.startsWith('من الزبون: ')) {
      entityName =
          description.replaceFirst('من الزبون: ', '').split(' - ').first;
    } else if (description.startsWith('إلى العامل: ')) {
      entityName =
          description.replaceFirst('إلى العامل: ', '').split(' - ').first;
    } else if (description.startsWith('للمورد: ')) {
      entityName =
          description.replaceFirst('للمورد: ', '').split(' - ').first;
    }

    String entityLabel;
    if (entityType == 'Client') {
      entityLabel = 'الزبون / Client';
    } else if (entityType == 'Supplier') {
      entityLabel = 'المورد / Fournisseur';
    } else if (entityType == 'Worker') {
      entityLabel = 'العامل / Employé';
    } else {
      entityLabel = 'الجهة / Partie';
    }

    final oldBalanceLabel = oldBalance >= 0 ? 'مدين' : 'دائن';
    final newBalanceLabel = newBalance >= 0 ? 'مدين' : 'دائن';
    final amountWords = _amountToWords(amount);

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a5,
        textDirection: pw.TextDirection.rtl,
        margin: const pw.EdgeInsets.all(20),
        theme: pw.ThemeData.withFont(base: fontRegular, bold: fontBold),
        build: (context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              // رأس الوصل
              pw.Container(
                decoration: const pw.BoxDecoration(
                  color: PdfColors.teal,
                  borderRadius:
                      pw.BorderRadius.all(pw.Radius.circular(8)),
                ),
                padding: const pw.EdgeInsets.symmetric(
                    vertical: 10, horizontal: 16),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.center,
                  children: [
                    if (logoWidget != null) ...[
                      logoWidget,
                      pw.SizedBox(width: 14),
                    ],
                    pw.Column(
                      children: [
                        pw.Text(
                          workshopName,
                          style: pw.TextStyle(
                              font: fontBold,
                              fontSize: 18,
                              color: PdfColors.white),
                          textAlign: pw.TextAlign.center,
                        ),
                        pw.SizedBox(height: 4),
                        pw.Text(
                          receiptTitleFr,
                          style: pw.TextStyle(
                              font: fontRegular,
                              fontSize: 10,
                              color: PdfColors.white),
                          textAlign: pw.TextAlign.center,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 8),

              // عنوان الوصل
              pw.Center(
                child: pw.Text(
                  receiptTitle,
                  style: pw.TextStyle(
                      font: fontBold,
                      fontSize: 13,
                      color: PdfColors.teal900),
                  textAlign: pw.TextAlign.center,
                ),
              ),
              pw.SizedBox(height: 4),

              // رقم الوصل والتاريخ
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('${tr('رقم الوصل:')} $receiptId',
                      style: pw.TextStyle(font: fontBold, fontSize: 9)),
                  pw.Text('$dateStr  $timeStr',
                      style:
                          pw.TextStyle(font: fontRegular, fontSize: 9)),
                ],
              ),
              pw.SizedBox(height: 6),
              pw.Divider(thickness: 0.5),

              // معلومات الجهة
              _buildRow('$entityLabel:', entityName.isEmpty ? '-' : entityName,
                  fontBold, fontRegular),
              if (phone.isNotEmpty)
                _buildRow('رقم الهاتف / Tél:', phone, fontBold, fontRegular),

              pw.Divider(thickness: 0.5),

              // الرصيد القديم
              _buildRow(
                'الرصيد القديم / Ancien Solde:',
                '${formatter.format(oldBalance.abs())} $currency  ($oldBalanceLabel)',
                fontBold,
                fontRegular,
                color: oldBalance > 0 ? PdfColors.orange700 : PdfColors.green700,
              ),
              pw.SizedBox(height: 4),

              // المبلغ
              pw.Container(
                decoration: pw.BoxDecoration(
                  color: isEncaissement ? PdfColors.green50 : PdfColors.red50,
                  borderRadius:
                      const pw.BorderRadius.all(pw.Radius.circular(4)),
                  border: pw.Border.all(
                    color: isEncaissement
                        ? PdfColors.green300
                        : PdfColors.red300,
                    width: 0.5,
                  ),
                ),
                padding: const pw.EdgeInsets.symmetric(
                    horizontal: 10, vertical: 6),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                      isEncaissement
                          ? 'المبلغ المستلم / Montant Reçu:'
                          : 'المبلغ المدفوع / Montant Payé:',
                      style: pw.TextStyle(font: fontBold, fontSize: 10),
                    ),
                    pw.Text(
                      '${formatter.format(amount)} $currency',
                      style: pw.TextStyle(
                        font: fontBold,
                        fontSize: 13,
                        color: isEncaissement
                            ? PdfColors.green800
                            : PdfColors.red800,
                      ),
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 4),

              // الرصيد الجديد
              _buildRow(
                'الرصيد الجديد / Nouveau Solde:',
                '${formatter.format(newBalance.abs())} $currency  ($newBalanceLabel)',
                fontBold,
                fontRegular,
                color: newBalance > 0 ? PdfColors.orange700 : PdfColors.green700,
              ),

              pw.Divider(thickness: 0.5),

              // المبلغ بالحروف
              pw.Container(
                padding: const pw.EdgeInsets.all(6),
                decoration: pw.BoxDecoration(
                  color: PdfColors.grey100,
                  borderRadius:
                      const pw.BorderRadius.all(pw.Radius.circular(4)),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                        'المبلغ بالحروف / Montant en lettres:',
                        style: pw.TextStyle(
                            font: fontBold,
                            fontSize: 8,
                            color: PdfColors.grey600)),
                    pw.Text(amountWords,
                        style: pw.TextStyle(font: fontRegular, fontSize: 9)),
                  ],
                ),
              ),
              pw.SizedBox(height: 6),

              // البيان
              if (description.isNotEmpty) ...[
                pw.Text(tr('البيان / Motif:'),
                    style: pw.TextStyle(font: fontBold, fontSize: 9)),
                pw.Text(description,
                    style: pw.TextStyle(font: fontRegular, fontSize: 9)),
                pw.SizedBox(height: 8),
              ],

              pw.Spacer(),
              pw.Divider(thickness: 0.5),

              // التوقيعات
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.center,
                    children: [
                      pw.Text(tr('المستلم / Signataire'),
                          style: pw.TextStyle(font: fontBold, fontSize: 8)),
                      pw.SizedBox(height: 20),
                      pw.Container(
                          width: 80,
                          height: 0.5,
                          color: PdfColors.black),
                    ],
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.center,
                    children: [
                      pw.Text(tr('الدافع / Payeur'),
                          style: pw.TextStyle(font: fontBold, fontSize: 8)),
                      pw.SizedBox(height: 20),
                      pw.Container(
                          width: 80,
                          height: 0.5,
                          color: PdfColors.black),
                    ],
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );

    return pdf.save();
  }

  static Future<void> printReceipt(Map<String, dynamic> transaction) async {
    final bytes = await generateReceiptPdfBytes(transaction);
    final receiptId = transaction['id']?.toString() ?? '-';
    await Printing.layoutPdf(
      onLayout: (_) async => bytes,
      name: 'receipt_$receiptId.pdf',
    );
  }

  static Future<void> shareReceipt(Map<String, dynamic> transaction) async {
    try {
      final bytes = await generateReceiptPdfBytes(transaction);
      final receiptId = transaction['id']?.toString() ?? '-';
      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/receipt_$receiptId.pdf');
      await file.writeAsBytes(bytes);
      await Share.shareXFiles(
        [XFile(file.path)],
        text: 'وصل معاملة الصندوق رقم $receiptId',
      );
    } catch (_) {
      try {
        final bytes = await generateReceiptPdfBytes(transaction);
        final receiptId = transaction['id']?.toString() ?? '-';
        await Printing.sharePdf(bytes: bytes, filename: 'receipt_$receiptId.pdf');
      } catch (e) {
        debugPrint('Error sharing receipt: $e');
      }
    }
  }

  static Future<void> saveReceipt(Map<String, dynamic> transaction, BuildContext context) async {
    try {
      final bytes = await generateReceiptPdfBytes(transaction);
      final receiptId = transaction['id']?.toString() ?? '-';
      final filename = 'receipt_$receiptId.pdf';
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
            dialogTitle: Localization.translate(
              'حفظ الوصل PDF',
              Provider.of<AppSettingsProvider>(context, listen: false).language,
            ),
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
              Localization.translate(
                'تم حفظ الوصل بنجاح',
                Provider.of<AppSettingsProvider>(context, listen: false).language,
              ),
              style: const TextStyle(fontFamily: 'Cairo'),
            ),
            duration: Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${Localization.translate('خطأ في حفظ الملف', Provider.of<AppSettingsProvider>(context, listen: false).language)}: $e',
              style: const TextStyle(fontFamily: 'Cairo'),
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }


  static String _readableText(dynamic value) {
    final text = value?.toString() ?? '';
    if (text.isEmpty ||
        (!text.contains('Ø') &&
            !text.contains('Ã') &&
            !text.contains('Â'))) {
      return text;
    }
    try {
      final repaired = utf8.decode(latin1.encode(text));
      return repaired.contains('�') ? text : repaired;
    } catch (_) {
      return text;
    }
  }

  static void _showReceiptError(BuildContext context, Object error) {
    debugPrint('Receipt PDF error: $error');
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'تعذر تنفيذ عملية الوصل: $error',
          style: const TextStyle(fontFamily: 'Cairo'),
        ),
        backgroundColor: Colors.red,
      ),
    );
  }

  static Future<void> printReceiptWithFeedback(
    Map<String, dynamic> transaction,
    BuildContext context,
  ) async {
    try {
      final bytes = await generateReceiptPdfBytes(transaction);
      final receiptId = transaction['id']?.toString() ?? '-';
      await Printing.layoutPdf(
        onLayout: (_) async => bytes,
        name: 'receipt_$receiptId.pdf',
      );
    } catch (error) {
      _showReceiptError(context, error);
    }
  }

  static Future<void> shareReceiptWithFeedback(
    Map<String, dynamic> transaction,
    BuildContext context,
  ) async {
    try {
      final bytes = await generateReceiptPdfBytes(transaction);
      final receiptId = transaction['id']?.toString() ?? '-';
      final filename = 'receipt_$receiptId.pdf';
      try {
        await Share.shareXFiles(
          [
            XFile.fromData(
              bytes,
              mimeType: 'application/pdf',
              name: filename,
            ),
          ],
          fileNameOverrides: [filename],
          text: 'وصل معاملة الصندوق رقم $receiptId',
        );
      } catch (_) {
        final shared = await Printing.sharePdf(
          bytes: bytes,
          filename: filename,
        );
        if (!shared) {
          throw StateError('لا تتوفر خدمة المشاركة على هذا الجهاز.');
        }
      }
    } catch (error) {
      _showReceiptError(context, error);
    }
  }

  static Future<void> saveReceiptWithFeedback(
    Map<String, dynamic> transaction,
    BuildContext context,
  ) async {
    try {
      final bytes = await generateReceiptPdfBytes(transaction);
      final receiptId = transaction['id']?.toString() ?? '-';
      final filename = 'receipt_$receiptId.pdf';
      String? savedPath;

      if (kIsWeb) {
        final downloaded = await Printing.sharePdf(
          bytes: bytes,
          filename: filename,
        );
        if (!downloaded) {
          throw StateError('المتصفح لم يسمح بتنزيل ملف الوصل.');
        }
        savedPath = filename;
      } else if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
        final picked = await FilePicker.saveFile(
          dialogTitle: Localization.translate(
            'حفظ الوصل PDF',
            Provider.of<AppSettingsProvider>(context, listen: false).language,
          ),
          fileName: filename,
          type: FileType.custom,
          allowedExtensions: ['pdf'],
        );
        if (picked != null) {
          await File(picked).writeAsBytes(bytes);
          savedPath = picked;
        }
      } else {
        try {
          final tempDir = await getTemporaryDirectory();
          final tempFile = File('${tempDir.path}/$filename');
          await tempFile.writeAsBytes(bytes);
          savedPath = await FlutterFileDialog.saveFile(
            params: SaveFileDialogParams(sourceFilePath: tempFile.path),
          );
        } catch (_) {
          final shared = await Printing.sharePdf(
            bytes: bytes,
            filename: filename,
          );
          if (!shared) rethrow;
          savedPath = filename;
        }
      }

      if (savedPath != null && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              Localization.translate(
                'تم حفظ الوصل بنجاح',
                Provider.of<AppSettingsProvider>(context, listen: false).language,
              ),
              style: const TextStyle(fontFamily: 'Cairo'),
            ),
          ),
        );
      }
    } catch (error) {
      _showReceiptError(context, error);
    }
  }

  static pw.Widget _buildRow(
    String label,
    String value,
    pw.Font fontBold,
    pw.Font fontRegular, {
    PdfColor? color,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 3),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(label, style: pw.TextStyle(font: fontBold, fontSize: 9)),
          pw.Text(
            value,
            style: pw.TextStyle(font: fontRegular, fontSize: 9, color: color),
          ),
        ],
      ),
    );
  }

  static String _amountToWords(double amount) {
    final int n = amount.toInt();
    if (n == 0) return 'صفر دينار جزائري';

    final millions = n ~/ 1000000;
    final thousands = (n % 1000000) ~/ 1000;
    final hundreds = (n % 1000) ~/ 100;
    final tens = (n % 100) ~/ 10;
    final ones = n % 10;

    const unitsM = ['', 'مليون', 'مليونان', 'ثلاثة ملايين', 'أربعة ملايين', 'خمسة ملايين', 'ستة ملايين', 'سبعة ملايين', 'ثمانية ملايين', 'تسعة ملايين'];
    const unitsT = ['', 'ألف', 'ألفان', 'ثلاثة آلاف', 'أربعة آلاف', 'خمسة آلاف', 'ستة آلاف', 'سبعة آلاف', 'ثمانية آلاف', 'تسعة آلاف'];
    const unitsH = ['', 'مئة', 'مئتان', 'ثلاثمئة', 'أربعمئة', 'خمسمئة', 'ستمئة', 'سبعمئة', 'ثمانمئة', 'تسعمئة'];
    const unitsTens = ['', 'عشرة', 'عشرون', 'ثلاثون', 'أربعون', 'خمسون', 'ستون', 'سبعون', 'ثمانون', 'تسعون'];
    const unitsOnes = ['', 'واحد', 'اثنان', 'ثلاثة', 'أربعة', 'خمسة', 'ستة', 'سبعة', 'ثمانية', 'تسعة'];

    final parts = <String>[];
    if (millions > 0 && millions < 10) parts.add(unitsM[millions]);
    else if (millions >= 10) parts.add('$millions مليون');
    if (thousands > 0 && thousands < 10) parts.add(unitsT[thousands]);
    else if (thousands >= 10) parts.add('$thousands ألف');
    if (hundreds > 0) parts.add(unitsH[hundreds]);
    if (tens > 0) parts.add(unitsTens[tens]);
    if (ones > 0) parts.add(unitsOnes[ones]);

    if (parts.isEmpty) return 'صفر دينار جزائري';
    return '${parts.join(' و')} دينار جزائري';
  }
}
