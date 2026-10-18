import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_file_dialog/flutter_file_dialog.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'pdf_font_cache.dart';

/// Exports the rows shown on the product movement card. Each row is the
/// list of cell texts in the order of [headers].
class ProductMovementExportService {
  /// A UTF-8 CSV with a byte-order mark, which Excel opens with Arabic text
  /// intact.
  static Uint8List buildCsv(List<String> headers, List<List<String>> rows) {
    String cell(String value) {
      final needsQuotes =
          value.contains(',') ||
          value.contains('"') ||
          value.contains('\n') ||
          value.contains('\r');
      final escaped = value.replaceAll('"', '""');
      return needsQuotes ? '"$escaped"' : escaped;
    }

    final buffer = StringBuffer('\uFEFF')..writeln(headers.map(cell).join(','));
    for (final row in rows) {
      buffer.writeln(row.map(cell).join(','));
    }
    return Uint8List.fromList(utf8.encode(buffer.toString()));
  }

  static Future<Uint8List> buildPdf({
    required String title,
    required List<String> summary,
    required List<String> headers,
    required List<List<String>> rows,
    required bool rtl,
  }) async {
    final fonts = await PdfFontCache.load();
    final direction = rtl ? pw.TextDirection.rtl : pw.TextDirection.ltr;
    final document = pw.Document(
      theme: pw.ThemeData.withFont(base: fonts.regular, bold: fonts.bold),
    );
    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        textDirection: direction,
        margin: const pw.EdgeInsets.all(20),
        build: (_) => [
          pw.Text(title, style: pw.TextStyle(font: fonts.bold, fontSize: 15)),
          pw.SizedBox(height: 6),
          for (final line in summary)
            pw.Text(line, style: const pw.TextStyle(fontSize: 9)),
          pw.SizedBox(height: 10),
          pw.TableHelper.fromTextArray(
            headers: headers,
            data: rows,
            headerStyle: pw.TextStyle(font: fonts.bold, fontSize: 8),
            cellStyle: const pw.TextStyle(fontSize: 7.5),
            headerDecoration: const pw.BoxDecoration(
              color: PdfColor.fromInt(0xFFE2E8F0),
            ),
            cellAlignment: rtl
                ? pw.Alignment.centerRight
                : pw.Alignment.centerLeft,
          ),
        ],
      ),
    );
    return document.save();
  }

  /// Saves [bytes] where the user chooses. Returns the path, or null when
  /// the dialog is cancelled.
  static Future<String?> save(
    Uint8List bytes,
    String filename,
    String extension,
  ) async {
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      final picked = await FilePicker.saveFile(
        dialogTitle: filename,
        fileName: filename,
        type: FileType.custom,
        allowedExtensions: [extension],
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

  static Future<void> printPdf(Uint8List bytes, String filename) =>
      Printing.layoutPdf(name: filename, onLayout: (_) async => bytes);
}
