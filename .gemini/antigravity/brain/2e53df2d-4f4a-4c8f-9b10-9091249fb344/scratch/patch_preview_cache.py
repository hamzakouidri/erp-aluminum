import re

path_preview = r'c:\Users\hp\Desktop\Noraleur\erp-aluminum-main\lib\Commande\devis_preview_screen.dart'

with open(path_preview, 'r', encoding='utf-8') as f:
    code = f.read()

# 1. Update initState and add _pdfBytes variables
OLD_INIT_STATE = """  @override
  void initState() {
    super.initState();
    // Preload the fonts in the background as soon as the screen opens
    PdfInvoiceApi.preloadFonts();
  }"""

NEW_INIT_STATE = """  Uint8List? _pdfBytes;
  String? _pdfError;

  @override
  void initState() {
    super.initState();
    _initPdfGeneration();
  }

  Future<void> _initPdfGeneration() async {
    try {
      await PdfInvoiceApi.preloadFonts();
      final bytes = await PdfInvoiceApi.buildPdfBytes(data);
      if (mounted) {
        setState(() {
          _pdfBytes = bytes;
        });
      }
    } catch (e) {
      debugPrint('Error generating PDF in background: $e');
      if (mounted) {
        setState(() {
          _pdfError = e.toString();
        });
      }
    }
  }

  Future<Uint8List?> _getPdfBytes() async {
    if (_pdfBytes != null) return _pdfBytes;
    
    setState(() => _isLoading = true);
    await Future.delayed(const Duration(milliseconds: 50));
    
    await _initPdfGeneration();
    
    setState(() => _isLoading = false);
    return _pdfBytes;
  }"""

assert OLD_INIT_STATE in code, "initState not found in devis_preview_screen.dart"
code = code.replace(OLD_INIT_STATE, NEW_INIT_STATE, 1)

# 2. Update _savePdf method to use _getPdfBytes
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
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'خطأ في الحفظ: $e',
            style: const TextStyle(fontFamily: 'Cairo'),
          ),
          backgroundColor: Colors.red,
        ),
      );
    }
  }"""

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

    final bytes = await _getPdfBytes();
    if (bytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_pdfError ?? t('خطأ في توليد PDF')),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });
    await Future.delayed(const Duration(milliseconds: 50));

    try {
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
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'خطأ في الحفظ: $e',
            style: const TextStyle(fontFamily: 'Cairo'),
          ),
          backgroundColor: Colors.red,
        ),
      );
    }
  }"""

assert OLD_SAVE_PDF in code, "OLD_SAVE_PDF not found in devis_preview_screen.dart"
code = code.replace(OLD_SAVE_PDF, NEW_SAVE_PDF, 1)

# 3. Update _printPdf method
OLD_PRINT_PDF = """  Future<void> _printPdf(BuildContext context) async {
    setState(() {
      _isLoading = true;
    });
    await Future.delayed(const Duration(milliseconds: 50));

    try {
      final bytes = await PdfInvoiceApi.buildPdfBytes(data);
      
      setState(() {
        _isLoading = false;
      });
      await Future.delayed(const Duration(milliseconds: 100));

      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => bytes,
        name: 'devis_${data.orderId}.pdf',
      );
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'خطأ في الطباعة: $e',
            style: const TextStyle(fontFamily: 'Cairo'),
          ),
          backgroundColor: Colors.red,
        ),
      );
    }
  }"""

NEW_PRINT_PDF = """  Future<void> _printPdf(BuildContext context) async {
    final bytes = await _getPdfBytes();
    if (bytes == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_pdfError ?? t('خطأ في توليد PDF')),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    setState(() {
      _isLoading = true;
    });
    await Future.delayed(const Duration(milliseconds: 50));

    try {
      setState(() {
        _isLoading = false;
      });
      await Future.delayed(const Duration(milliseconds: 100));

      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => bytes,
        name: 'devis_${data.orderId}.pdf',
      );
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'خطأ في الطباعة: $e',
            style: const TextStyle(fontFamily: 'Cairo'),
          ),
          backgroundColor: Colors.red,
        ),
      );
    }
  }"""

assert OLD_PRINT_PDF in code, "OLD_PRINT_PDF not found in devis_preview_screen.dart"
code = code.replace(OLD_PRINT_PDF, NEW_PRINT_PDF, 1)

# 4. Update _sharePdf method
OLD_SHARE_PDF = """  Future<void> _sharePdf(BuildContext context) async {
    setState(() => _isLoading = true);
    await Future.delayed(const Duration(milliseconds: 50));

    try {
      final bytes = await PdfInvoiceApi.buildPdfBytes(data);

      final cleanClientName = data.clientName.trim().replaceAll(RegExp(r'[\\\\/:*?"<>|]'), '_');
      final filename = cleanClientName.isNotEmpty
          ? '$cleanClientName.pdf'
          : 'devis_${data.orderId}.pdf';

      final tempDir = await getTemporaryDirectory();
      final tempFile = File('${tempDir.path}/$filename');
      await tempFile.writeAsBytes(bytes);

      setState(() => _isLoading = false);
      await Future.delayed(const Duration(milliseconds: 100));

      if (Platform.isWindows) {
        final finalPath = await FilePicker.saveFile(
          dialogTitle: t('مشاركة وحفظ PDF'),
          fileName: filename,
          type: FileType.custom,
          allowedExtensions: ['pdf'],
        );
        if (finalPath != null) {
          final file = File(finalPath);
          await file.writeAsBytes(bytes);
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(t('تم حفظ PDF بنجاح'),
                  style: const TextStyle(fontFamily: 'Cairo'),
                ),
                duration: const Duration(seconds: 4),
              ),
            );
          }
        }
      } else {
        await Printing.sharePdf(bytes: bytes, filename: filename);
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('خطأ في المشاركة: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }"""

NEW_SHARE_PDF = """  Future<void> _sharePdf(BuildContext context) async {
    final bytes = await _getPdfBytes();
    if (bytes == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_pdfError ?? t('خطأ في توليد PDF')),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    setState(() => _isLoading = true);
    await Future.delayed(const Duration(milliseconds: 50));

    try {
      final cleanClientName = data.clientName.trim().replaceAll(RegExp(r'[\\\\/:*?"<>|]'), '_');
      final filename = cleanClientName.isNotEmpty
          ? '$cleanClientName.pdf'
          : 'devis_${data.orderId}.pdf';

      final tempDir = await getTemporaryDirectory();
      final tempFile = File('${tempDir.path}/$filename');
      await tempFile.writeAsBytes(bytes);

      setState(() => _isLoading = false);
      await Future.delayed(const Duration(milliseconds: 100));

      if (Platform.isWindows) {
        final finalPath = await FilePicker.saveFile(
          dialogTitle: t('مشاركة وحفظ PDF'),
          fileName: filename,
          type: FileType.custom,
          allowedExtensions: ['pdf'],
        );
        if (finalPath != null) {
          final file = File(finalPath);
          await file.writeAsBytes(bytes);
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(t('تم حفظ PDF بنجاح'),
                  style: const TextStyle(fontFamily: 'Cairo'),
                ),
                duration: const Duration(seconds: 4),
              ),
            );
          }
        }
      } else {
        await Printing.sharePdf(bytes: bytes, filename: filename);
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('خطأ في المشاركة: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }"""

assert OLD_SHARE_PDF in code, "OLD_SHARE_PDF not found in devis_preview_screen.dart"
code = code.replace(OLD_SHARE_PDF, NEW_SHARE_PDF, 1)

with open(path_preview, 'w', encoding='utf-8') as f:
    f.write(code)
print("devis_preview_screen.dart updated with cached background PDF generation.")
