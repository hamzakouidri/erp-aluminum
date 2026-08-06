import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:database_data/Commande/Systeme/model.dart';
import 'package:database_data/Commande/window_painter.dart';

Future<Uint8List> captureWindowImage(
  WindowModel model, {
  int maxSide = 1400,
}) async {
  if (model.isGlassWork) {
    final selectedPath = model.glassWorkPayload?['imagePath']?.toString() ?? '';
    if (selectedPath.isNotEmpty) {
      try {
        final selectedFile = File(selectedPath);
        if (await selectedFile.exists()) {
          return await selectedFile.readAsBytes();
        }
      } catch (_) {}
    }
    try {
      final ByteData data = await rootBundle.load('Icon/verre.png');
      return data.buffer.asUint8List();
    } catch (_) {}
  }

  if (model.isMoustiquaire ||
      (model.manualNameOverride?.contains('Moustiquaire') == true)) {
    try {
      final ByteData data = await rootBundle.load('Icon/media.webp');
      return data.buffer.asUint8List();
    } catch (_) {}
  }

  // If model is Caisson Tunnel, return official Caisson Tunnel asset image bytes for PDF/Flyer
  if (model.isCaissonTunnel ||
      (model.manualNameOverride?.contains('Caisson Tunnel') == true)) {
    try {
      final ByteData data = await rootBundle.load('Icon/caisson_tunnel.jpg');
      return data.buffer.asUint8List();
    } catch (_) {
      try {
        final ByteData data = await rootBundle.load(
          'assets/Icon/caisson_tunnel.jpg',
        );
        return data.buffer.asUint8List();
      } catch (_) {
        // Fallback drawing if asset not found
      }
    }
  }

  if (model.isCustomProduct) {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    const w = 400.0;
    const h = 400.0;

    final paint = Paint()
      ..shader = ui.Gradient.linear(Offset.zero, const Offset(w, h), [
        Colors.orange.shade400,
        Colors.deepOrange.shade600,
      ]);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(0, 0, w, h),
        const Radius.circular(30),
      ),
      paint,
    );

    final iconPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(w * 0.35, h * 0.35, w * 0.3, h * 0.25),
        const Radius.circular(10),
      ),
      iconPaint,
    );

    final lidPaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 6.0
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    canvas.drawLine(
      const Offset(w * 0.3, h * 0.33),
      const Offset(w * 0.7, h * 0.33),
      lidPaint,
    );
    canvas.drawLine(
      const Offset(w * 0.3, h * 0.33),
      const Offset(w * 0.35, h * 0.45),
      lidPaint,
    );
    canvas.drawLine(
      const Offset(w * 0.7, h * 0.33),
      const Offset(w * 0.65, h * 0.45),
      lidPaint,
    );

    final textPainter = TextPainter(
      text: TextSpan(
        text: model.manualNameOverride ?? 'Special Product',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 24,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.rtl,
      textAlign: TextAlign.center,
    );
    textPainter.layout(maxWidth: w - 40);
    textPainter.paint(canvas, Offset((w - textPainter.width) / 2, h * 0.7));

    final picture = recorder.endRecording();
    final img = await picture.toImage(w.toInt(), h.toInt());
    final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  }

  final windowW = model.width > 0 ? model.width : 1000.0;
  final windowH = model.height > 0 ? model.height : 1000.0;
  const padding = 48.0;

  final boxSize = model.shutterBoxHeight;

  final totalH = windowH + boxSize;
  final scale = (maxSide - padding * 2) / math.max(windowW, totalH);
  final canvasW = (windowW * scale + padding * 2).round();
  final canvasH = (totalH * scale + padding * 2).round();

  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final canvasSize = Size(canvasW.toDouble(), canvasH.toDouble());

  canvas.drawRect(
    Rect.fromLTWH(0, 0, canvasSize.width, canvasSize.height),
    Paint()..color = Colors.white,
  );

  canvas.save();
  // Translate down by padding + the scaled boxSize so the top box fits in the image
  canvas.translate(padding, padding + (boxSize * scale));
  canvas.scale(scale);
  WindowPainter(
    model: model,
    overrideIsInternalView: true,
  ).paint(canvas, Size(windowW, windowH));

  canvas.restore();

  final picture = recorder.endRecording();
  final img = await picture.toImage(canvasW, canvasH);
  final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
  return byteData!.buffer.asUint8List();
}

Future<String> saveWindowImageToDisk(
  WindowModel model, {
  int maxSide = 600,
}) async {
  try {
    final bytes = await captureWindowImage(model, maxSide: maxSide);
    final appDir = await getApplicationDocumentsDirectory();
    final imagesDir = Directory('${appDir.path}/window_drawings');
    if (!await imagesDir.exists()) {
      await imagesDir.create(recursive: true);
    }
    final fileName = 'window_${DateTime.now().millisecondsSinceEpoch}.png';
    final file = File('${imagesDir.path}/$fileName');
    await file.writeAsBytes(bytes);
    return file.path;
  } catch (_) {
    return '';
  }
}
