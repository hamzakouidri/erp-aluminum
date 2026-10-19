import 'dart:typed_data';

/// Turns rendered labels into ZPL for thermal label printers (Zebra and
/// compatibles).
///
/// Each label is sent as one monochrome graphic (`^GFA`), so Arabic text, the
/// workshop font and the barcode print exactly as on the PDF label: the fonts
/// built into these printers cannot shape Arabic.

/// Black/white pixels of an RGBA image, row by row (`true` = print a dot).
/// Transparent pixels stay white.
List<bool> monochromeFromRgba(
  Uint8List rgba,
  int width,
  int height, {
  int threshold = 160,
}) {
  final dots = List<bool>.filled(width * height, false);
  for (var i = 0; i < width * height; i++) {
    final o = i * 4;
    if (o + 3 >= rgba.length) break;
    final alpha = rgba[o + 3];
    if (alpha < 128) continue;
    // Perceived brightness (ITU-R BT.601).
    final luma =
        (rgba[o] * 299 + rgba[o + 1] * 587 + rgba[o + 2] * 114) ~/ 1000;
    dots[i] = luma < threshold;
  }
  return dots;
}

/// One label (`^XA ... ^XZ`) printing [dots] at the top-left corner.
String zplLabelFromDots({
  required int width,
  required int height,
  required List<bool> dots,
  int copies = 1,
}) {
  final bytesPerRow = (width + 7) ~/ 8;
  final hex = StringBuffer();
  const digits = '0123456789ABCDEF';
  for (var y = 0; y < height; y++) {
    for (var byteIndex = 0; byteIndex < bytesPerRow; byteIndex++) {
      var value = 0;
      for (var bit = 0; bit < 8; bit++) {
        final x = byteIndex * 8 + bit;
        if (x < width && dots[y * width + x]) value |= 0x80 >> bit;
      }
      hex
        ..write(digits[value >> 4])
        ..write(digits[value & 0x0F]);
    }
  }
  final total = bytesPerRow * height;
  return '^XA'
      '^PW$width'
      '^LL$height'
      '^LH0,0'
      '^FO0,0^GFA,$total,$total,$bytesPerRow,$hex^FS'
      '${copies > 1 ? '^PQ$copies' : ''}'
      '^XZ\n';
}
