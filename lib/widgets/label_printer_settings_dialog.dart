import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:provider/provider.dart';

import '../services/labels/label_print_service.dart';
import '../settings/app_settings.dart';
import '../settings/localization.dart';

/// Chooses how this device prints labels: the system dialog, or ZPL straight
/// to a network thermal label printer.
Future<void> showLabelPrinterSettingsDialog(BuildContext context) async {
  final lang = Provider.of<AppSettingsProvider>(
    context,
    listen: false,
  ).language;
  String t(String key) => Localization.translate(key, lang);
  var settings = await LabelPrinterSettings.load();
  final hostController = TextEditingController(text: settings.host);
  final portController = TextEditingController(text: '${settings.port}');
  if (!context.mounted) return;

  LabelPrinterSettings current() => settings.copyWith(
    host: hostController.text.trim(),
    port: int.tryParse(portController.text.trim()) ?? 9100,
  );

  await showDialog<void>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setDialogState) {
        final zpl = settings.mode == LabelPrinterMode.zplNetwork;
        return AlertDialog(
          title: Text(t('طابعة الملصقات')),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  RadioGroup<LabelPrinterMode>(
                    groupValue: settings.mode,
                    onChanged: (mode) => setDialogState(
                      () => settings = settings.copyWith(mode: mode),
                    ),
                    child: Column(
                      children: [
                        RadioListTile<LabelPrinterMode>(
                          value: LabelPrinterMode.system,
                          title: Text(t('طابعة النظام (PDF)')),
                          subtitle: Text(t('نافذة الطباعة العادية لأي طابعة')),
                        ),
                        RadioListTile<LabelPrinterMode>(
                          value: LabelPrinterMode.zplNetwork,
                          title: Text(t('طابعة ملصقات حرارية (ZPL)')),
                          subtitle: Text(
                            t('طباعة مباشرة عبر الشبكة دون نافذة الطباعة'),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (zpl) ...[
                    const SizedBox(height: 8),
                    TextField(
                      controller: hostController,
                      decoration: InputDecoration(
                        labelText: t('عنوان IP للطابعة'),
                        hintText: '192.168.1.50',
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: portController,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: t('المنفذ'),
                              border: const OutlineInputBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: DropdownButtonFormField<int>(
                            initialValue: settings.dpi,
                            decoration: InputDecoration(
                              labelText: t('دقة رأس الطباعة'),
                              border: const OutlineInputBorder(),
                            ),
                            items: [
                              for (final dpi in const [203, 300, 600])
                                DropdownMenuItem(
                                  value: dpi,
                                  child: Text('$dpi dpi'),
                                ),
                            ],
                            onChanged: (dpi) => setDialogState(
                              () => settings = settings.copyWith(dpi: dpi),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            if (zpl)
              TextButton.icon(
                icon: const Icon(Icons.print_rounded),
                label: Text(t('طباعة ملصق تجريبي')),
                onPressed: () async {
                  final messenger = ScaffoldMessenger.of(context);
                  try {
                    await _printTestLabel(current(), lang);
                    messenger.showSnackBar(
                      SnackBar(content: Text(t('تم إرسال الملصق التجريبي'))),
                    );
                  } catch (error) {
                    messenger.showSnackBar(
                      SnackBar(
                        backgroundColor: Colors.red.shade700,
                        content: Text('${t('تعذر الاتصال بالطابعة')}: $error'),
                      ),
                    );
                  }
                },
              ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(t('إلغاء')),
            ),
            FilledButton(
              onPressed: () async {
                await current().save();
                if (dialogContext.mounted) Navigator.pop(dialogContext);
              },
              child: Text(t('حفظ')),
            ),
          ],
        );
      },
    ),
  );
  hostController.dispose();
  portController.dispose();
}

Future<void> _printTestLabel(
  LabelPrinterSettings settings,
  AppLanguage lang,
) async {
  const format = PdfPageFormat(
    50 * PdfPageFormat.mm,
    30 * PdfPageFormat.mm,
    marginAll: 1 * PdfPageFormat.mm,
  );
  final document = pw.Document()
    ..addPage(
      pw.Page(
        pageFormat: format,
        build: (_) => pw.Column(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text('TEST 50 x 30 mm', style: const pw.TextStyle(fontSize: 10)),
            pw.SizedBox(
              height: 12,
              child: pw.BarcodeWidget(
                barcode: pw.Barcode.code128(),
                data: 'TEST-123456',
                drawText: true,
                textStyle: const pw.TextStyle(fontSize: 5),
              ),
            ),
          ],
        ),
      ),
    );
  await LabelPrintService.printLabels(
    document,
    format: format,
    name: 'test-label.pdf',
    settings: settings.copyWith(mode: LabelPrinterMode.zplNetwork),
  );
}
