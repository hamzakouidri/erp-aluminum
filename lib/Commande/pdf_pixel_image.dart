import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Pixels written into the PDF as they are.
///
/// pw.MemoryImage and pw.RawImage go through the `image` package, which
/// decodes or repacks every pixel in Dart on the UI thread: seconds for each
/// drawing of a big order. These bytes come from the engine's native decoder
/// and are written straight into the PDF stream.
class PdfPixelImage extends pw.ImageProvider {
  /// [bytes] are RGBA when [alpha] is true, otherwise RGB.
  PdfPixelImage(this._bytes, int width, int height, {required this.alpha})
    : super(width, height, PdfImageOrientation.topLeft, null);

  final Uint8List _bytes;
  final bool alpha;

  @override
  PdfImage buildImage(pw.Context context, {int? width, int? height}) =>
      PdfImage(
        context.document,
        image: _bytes,
        width: this.width!,
        height: this.height!,
        alpha: alpha,
      );
}

/// [image] as a PDF image. An [opaque] image drops its alpha channel, so the
/// PDF holds no soft mask for it: a smaller file and less work to save it.
Future<pw.ImageProvider?> pdfImageFromUiImage(
  ui.Image image, {
  bool opaque = false,
}) async {
  final data = await image.toByteData(
    format: ui.ImageByteFormat.rawStraightRgba,
  );
  if (data == null) return null;
  final rgba = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  if (!opaque) {
    return PdfPixelImage(rgba, image.width, image.height, alpha: true);
  }
  final pixels = image.width * image.height;
  final rgb = Uint8List(pixels * 3);
  for (var i = 0, j = 0; i < pixels; i++, j += 4) {
    rgb[i * 3] = rgba[j];
    rgb[i * 3 + 1] = rgba[j + 1];
    rgb[i * 3 + 2] = rgba[j + 2];
  }
  return PdfPixelImage(rgb, image.width, image.height, alpha: false);
}

/// An encoded PNG or JPEG scaled down by the engine so its longest side is
/// at most [maxSide] pixels. A JPEG already small enough is embedded as it
/// is. Returns null for bytes the engine cannot decode.
Future<pw.ImageProvider?> pdfImageFromEncoded(
  Uint8List bytes, {
  required int maxSide,
}) async {
  if (bytes.length < 4) return null;
  final isJpeg = bytes[0] == 0xFF && bytes[1] == 0xD8;
  ui.ImmutableBuffer? buffer;
  ui.ImageDescriptor? descriptor;
  ui.Codec? codec;
  ui.Image? image;
  try {
    buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    descriptor = await ui.ImageDescriptor.encoded(buffer);
    final w = descriptor.width;
    final h = descriptor.height;
    if (w <= 0 || h <= 0) return null;
    final longest = math.max(w, h);
    if (isJpeg && longest <= maxSide * 1.5) return pw.MemoryImage(bytes);
    final scale = math.min(1.0, maxSide / longest);
    codec = await descriptor.instantiateCodec(
      targetWidth: math.max(1, (w * scale).round()),
      targetHeight: math.max(1, (h * scale).round()),
    );
    image = (await codec.getNextFrame()).image;
    return await pdfImageFromUiImage(image);
  } catch (e) {
    debugPrint('pdfImageFromEncoded: $e');
    return null;
  } finally {
    image?.dispose();
    codec?.dispose();
    descriptor?.dispose();
    buffer?.dispose();
  }
}
