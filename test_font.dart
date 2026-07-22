import 'dart:io';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

void main() {
  try {
    final file = File('assets/fonts/Amiri-Regular.ttf');
    final font = pw.Font.ttf(file.readAsBytesSync().buffer.asByteData());
    print("Font loaded successfully: ${font.fontName}");
  } catch (e, stack) {
    print("Failed to load font: $e\n$stack");
  }
}
