import re

path_preview = r'c:\Users\hp\Desktop\Noraleur\erp-aluminum-main\lib\Commande\devis_preview_screen.dart'
path_keys = r'c:\Users\hp\Desktop\Noraleur\erp-aluminum-main\lib\settings\locales\general_keys.dart'

# ────────────────────────────────────────────────────
# 1. Update devis_preview_screen.dart (_savePdf method)
# ────────────────────────────────────────────────────
with open(path_preview, 'r', encoding='utf-8') as f:
    code_preview = f.read()

OLD_SAVE_PDF = """  Future<void> _savePdf(BuildContext context) async {
    final defaultFileName = data.clientName.trim().isNotEmpty
        ? data.clientName.trim().replaceAll(RegExp(r'[\\\\/:*?"<>|]'), '_')
        : 'devis_${data.orderId}';
    final nameController = TextEditingController(text: defaultFileName);
    final confirmedName = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(t('اسم الملف'),
            style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold),
          ),
          content: TextField(
            controller: nameController,
            decoration: InputDecoration(
              labelText: t('ادخل اسم الملف'),
              suffixText: '.pdf',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, null),
              child: Text(t('إلغاء'), style: TextStyle(fontFamily: 'Cairo')),
            ),
            ElevatedButton(
              onPressed: () =>
                  Navigator.pop(context, nameController.text.trim()),
              child: Text(t('اختيار مسار الحفظ'),
                style: TextStyle(fontFamily: 'Cairo'),
              ),
            ),
          ],
        );
      },
    );

    if (confirmedName == null || confirmedName.isEmpty) return;

    if (!context.mounted) return;
    setState(() {
      _isLoading = true;
    });
    // Give Flutter a frame to paint the spinner
    await Future.delayed(const Duration(milliseconds: 50));

    try {
      final bytes = await PdfInvoiceApi.buildPdfBytes(data);

      String filename = confirmedName;
      if (!filename.toLowerCase().endsWith('.pdf')) {
        filename += '.pdf';
      }

      final tempDir = await getTemporaryDirectory();
      final tempFile = File('${tempDir.path}/$filename');
      await tempFile.writeAsBytes(bytes);

      setState(() {
        _isLoading = false;
      });
      // Give Flutter a frame to clear the spinner from screen
      await Future.delayed(const Duration(milliseconds: 100));

      String? finalPath;
      if (Platform.isWindows) {
        finalPath = await FilePicker.saveFile(
          dialogTitle: t('حفظ PDF'),
          fileName: filename,
          type: FileType.custom,
          allowedExtensions: ['pdf'],
        );
        if (finalPath != null) {
          final file = File(finalPath);
          await file.writeAsBytes(bytes);
        }
      } else {
        final params = SaveFileDialogParams(sourceFilePath: tempFile.path);
        finalPath = await FlutterFileDialog.saveFile(params: params);
      }

      if (finalPath != null && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(t('تم حفظ PDF بنجاح'),
              style: const TextStyle(fontFamily: 'Cairo'),
            ),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {"""

# Replace OLD_SAVE_PDF with the optimized one
NEW_SAVE_PDF = """  Future<void> _savePdf(BuildContext context) async {
    final defaultFileName = data.clientName.trim().isNotEmpty
        ? data.clientName.trim().replaceAll(RegExp(r'[\\\\/:*?"<>|]'), '_')
        : 'devis_${data.orderId}';
    final nameController = TextEditingController(text: defaultFileName);
    final confirmedName = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(t('اسم الملف'),
            style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold),
          ),
          content: TextField(
            controller: nameController,
            decoration: InputDecoration(
              labelText: t('ادخل اسم الملف'),
              suffixText: '.pdf',
              border: const OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, null),
              child: Text(t('إلغاء'), style: const TextStyle(fontFamily: 'Cairo')),
            ),
            ElevatedButton(
              onPressed: () =>
                  Navigator.pop(context, nameController.text.trim()),
              child: Text(t('حفظ'),
                style: const TextStyle(fontFamily: 'Cairo'),
              ),
            ),
          ],
        );
      },
    );

    if (confirmedName == null || confirmedName.isEmpty) return;

    if (!context.mounted) return;
    setState(() {
      _isLoading = true;
    });
    // Give Flutter a frame to paint the spinner
    await Future.delayed(const Duration(milliseconds: 50));

    try {
      final bytes = await PdfInvoiceApi.buildPdfBytes(data);

      String filename = confirmedName;
      if (!filename.toLowerCase().endsWith('.pdf')) {
        filename += '.pdf';
      }

      final tempDir = await getTemporaryDirectory();
      final tempFile = File('${tempDir.path}/$filename');
      await tempFile.writeAsBytes(bytes);

      setState(() {
        _isLoading = false;
      });
      // Give Flutter a frame to clear the spinner from screen
      await Future.delayed(const Duration(milliseconds: 100));

      String? finalPath;
      bool savedDirectly = false;

      // Try saving directly to the downloads directory without displaying the native file dialog
      try {
        final downloadsDir = await getDownloadsDirectory();
        if (downloadsDir != null) {
          final targetFile = File('${downloadsDir.path}/$filename');
          await targetFile.writeAsBytes(bytes);
          finalPath = targetFile.path;
          savedDirectly = true;
        }
      } catch (e) {
        debugPrint('Direct save failed: $e. Falling back to platform file dialog.');
      }

      if (!savedDirectly) {
        if (Platform.isWindows) {
          finalPath = await FilePicker.saveFile(
            dialogTitle: t('حفظ PDF'),
            fileName: filename,
            type: FileType.custom,
            allowedExtensions: ['pdf'],
          );
          if (finalPath != null) {
            final file = File(finalPath);
            await file.writeAsBytes(bytes);
          }
        } else {
          final params = SaveFileDialogParams(sourceFilePath: tempFile.path);
          finalPath = await FlutterFileDialog.saveFile(params: params);
        }
      }

      if (finalPath != null && context.mounted) {
        final successMsg = savedDirectly
            ? t('تم حفظ PDF بنجاح في مجلد التحميلات')
            : t('تم حفظ PDF بنجاح');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(successMsg,
              style: const TextStyle(fontFamily: 'Cairo'),
            ),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {"""

assert OLD_SAVE_PDF in code_preview, "OLD_SAVE_PDF not found in devis_preview_screen"
code_preview = code_preview.replace(OLD_SAVE_PDF, NEW_SAVE_PDF, 1)

with open(path_preview, 'w', encoding='utf-8') as f:
    f.write(code_preview)
print("devis_preview_screen.dart updated with direct save to downloads.")

# ────────────────────────────────────────────────────
# 2. Update general_keys.dart
# ────────────────────────────────────────────────────
with open(path_keys, 'r', encoding='utf-8') as f:
    code_keys = f.read()

ANCHOR_KEY = """  'caisse': {"""
NEW_KEYS = """  'تم حفظ PDF بنجاح في مجلد التحميلات': {
    AppLanguage.arabic: 'تم حفظ PDF بنجاح في مجلد التحميلات',
    AppLanguage.french: 'PDF enregistré avec succès dans le dossier Téléchargements',
    AppLanguage.english: 'PDF saved successfully in Downloads folder',
  },
  'caisse': {"""

assert ANCHOR_KEY in code_keys, "Anchor key not found in general_keys.dart"
code_keys = code_keys.replace(ANCHOR_KEY, NEW_KEYS, 1)

with open(path_keys, 'w', encoding='utf-8') as f:
    f.write(code_keys)
print("general_keys.dart updated successfully.")
