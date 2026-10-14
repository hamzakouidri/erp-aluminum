import 'package:bidi/bidi.dart' as bidi;
import 'package:database_data/arabic_reshaper/arabic_reshaper.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Shared application identity used on generated documents.
class PdfBranding {
  PdfBranding._();

  static const String appName = 'ورشتي';

  static String get shapedAppName {
    final reshaped = ArabicReshaper.instance.reshape(appName);
    return String.fromCharCodes(bidi.logicalToVisual(reshaped));
  }

  static pw.Widget footerMark(
    pw.Font font, {
    PdfColor color = PdfColors.grey500,
    double fontSize = 7.5,
  }) {
    return pw.Text(
      shapedAppName,
      style: pw.TextStyle(font: font, fontSize: fontSize, color: color),
    );
  }
}
