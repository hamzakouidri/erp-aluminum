import 'dart:typed_data';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/widgets.dart' as pw;

/// Shared, local PDF fonts. Loading them once keeps print/save/share actions
/// fast and avoids a network request through PdfGoogleFonts on the first use.
class PdfFontBundle {
  const PdfFontBundle({required this.regular, required this.bold});

  final pw.Font regular;
  final pw.Font bold;
}

class PdfFontCache {
  static Future<PdfFontBundle>? _future;

  static Future<PdfFontBundle> load() {
    _future ??= _load().catchError((error) {
      _future = null;
      throw error;
    });
    return _future!;
  }

  static Future<PdfFontBundle> _load() async {
    final data = await Future.wait<ByteData>([
      rootBundle.load('assets/fonts/Cairo-Regular.ttf'),
      rootBundle.load('assets/fonts/Cairo-Bold.ttf'),
    ]);
    return PdfFontBundle(
      regular: pw.Font.ttf(data[0]),
      bold: pw.Font.ttf(data[1]),
    );
  }
}
