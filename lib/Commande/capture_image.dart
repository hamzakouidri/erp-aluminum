import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:database_data/Commande/Systeme/model.dart';
import 'package:database_data/Commande/window_painter.dart';
import 'package:database_data/Screen/tempered_glass_work_screen.dart';

Future<Uint8List> captureWindowImage(
  WindowModel model, {
  int maxSide = 1400,
  bool showDrawingDimensions = false,
}) async {
  model.clearSelection();
  if (model.isGlassWork) {
    if (model.glassWorkPayload != null) {
      try {
        return await TemperedGlassWorkScreen.renderToPng(
          model.glassWorkPayload!,
          maxSide: maxSide,
        );
      } catch (e) {
        debugPrint('Error rendering glass work drawing: $e');
      }
    }
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
  final padding = showDrawingDimensions ? 170.0 : 48.0;

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
    showDrawingDimensions: showDrawingDimensions,
  ).paint(canvas, Size(windowW, windowH));
  if (showDrawingDimensions) {
    _paintCaptureExteriorDimensions(canvas, model, scale, padding);
  }

  canvas.restore();

  final picture = recorder.endRecording();
  final img = await picture.toImage(canvasW, canvasH);
  final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
  return byteData!.buffer.asUint8List();
}

Future<String> saveWindowImageToDisk(
  WindowModel model, {
  int maxSide = 1800,
  bool showDrawingDimensions = false,
}) async {
  try {
    final bytes = await captureWindowImage(
      model,
      maxSide: maxSide,
      showDrawingDimensions: showDrawingDimensions,
    );
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

void _paintCaptureExteriorDimensions(
  Canvas canvas,
  WindowModel model,
  double scale,
  double padding,
) {
  final margin = padding / math.max(scale, 0.1);
  final sideCoverOffset = model.hasSideCovers ? model.sideCoverWidth : 0.0;
  final topY = -margin * 0.55 - sideCoverOffset;
  final leftX = -margin * 0.55 - sideCoverOffset;
  final rightX = model.width + margin * 0.62 + sideCoverOffset;
  final bottomY = model.height + margin * 0.42 + sideCoverOffset;

  final physicalFrames = model.getPhysicalFrameInfos();
  if (physicalFrames.length > 1) {
    final sorted = List<PhysicalFrameInfo>.from(physicalFrames)
      ..sort((a, b) => a.rect.left != b.rect.left
          ? a.rect.left.compareTo(b.rect.left)
          : a.rect.top.compareTo(b.rect.top));
    final hasVaryingHeights = sorted.any(
      (f) => (f.rect.height - sorted.first.rect.height).abs() > 1.0,
    );

    // Total width at top
    _drawCaptureDimension(
      canvas,
      '${model.width.toInt()} mm',
      Offset(0, topY),
      Offset(model.width, topY),
      scale: scale,
    );

    // Individual frame widths at bottom
    for (final f in sorted) {
      _drawCaptureDimension(
        canvas,
        '${f.rect.width.toInt()} mm',
        Offset(f.rect.left, bottomY),
        Offset(f.rect.right, bottomY),
        small: true,
        scale: scale,
      );
    }

    // Leftmost frame height on the left
    final leftmost = sorted.first;
    _drawCaptureDimension(
      canvas,
      '${leftmost.rect.height.toInt()} mm',
      Offset(leftX, leftmost.rect.top),
      Offset(leftX, leftmost.rect.bottom),
      vertical: true,
      scale: scale,
    );

    // If leftmost is shorter than total window height, show total height on outer left
    if (hasVaryingHeights && model.height > leftmost.rect.height + 1.0) {
      _drawCaptureDimension(
        canvas,
        '${model.height.toInt()} mm',
        Offset(leftX - margin * 0.45, 0),
        Offset(leftX - margin * 0.45, model.height),
        vertical: true,
        scale: scale,
      );
    }

    // Rightmost frame height on the right
    final rightmost = sorted.last;
    _drawCaptureDimension(
      canvas,
      '${rightmost.rect.height.toInt()} mm',
      Offset(rightX, rightmost.rect.top),
      Offset(rightX, rightmost.rect.bottom),
      vertical: true,
      scale: scale,
    );

    // Intermediate frames heights
    if (sorted.length >= 3 && hasVaryingHeights) {
      for (int i = 1; i < sorted.length - 1; i++) {
        final f = sorted[i];
        final dimX = f.rect.left + math.min(f.rect.width * 0.28, 65.0);
        _drawCaptureDimension(
          canvas,
          '${f.rect.height.toInt()} mm',
          Offset(dimX, f.rect.top),
          Offset(dimX, f.rect.bottom),
          vertical: true,
          small: true,
          scale: scale,
        );
      }
    }
  } else {
    _drawCaptureDimension(
      canvas,
      '${model.width.toInt()} mm',
      Offset(0, topY),
      Offset(model.width, topY),
      scale: scale,
    );
    _drawCaptureDimension(
      canvas,
      '${model.height.toInt()} mm',
      Offset(leftX, 0),
      Offset(leftX, model.height),
      vertical: true,
      scale: scale,
    );
  }
}

void _drawCaptureDimension(
  Canvas canvas,
  String text,
  Offset p1,
  Offset p2, {
  bool vertical = false,
  bool small = false,
  required double scale,
}) {
  final paint = Paint()
    ..color = Colors.blueGrey.shade700
    ..strokeWidth = small ? 1.5 : 2.0;
  final tick = small ? 10.0 : 14.0;
  final center = Offset((p1.dx + p2.dx) / 2, (p1.dy + p2.dy) / 2);

  final textPainter = TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(
        color: const Color(0xFF0F172A),
        fontSize: (small ? 28 : 38) / math.max(scale, 0.1),
        fontWeight: FontWeight.w800,
        shadows: const [
          Shadow(color: Color(0xDDFFFFFF), blurRadius: 3),
          Shadow(color: Color(0x33000000), blurRadius: 1.5),
        ],
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();

  final gap = textPainter.width + (small ? 24 : 40);
  if (vertical) {
    final minY = math.min(p1.dy, p2.dy);
    final maxY = math.max(p1.dy, p2.dy);
    final halfGap = gap / 2;
    if (center.dy - halfGap > minY) {
      canvas.drawLine(
        Offset(p1.dx, minY),
        Offset(p1.dx, center.dy - halfGap),
        paint,
      );
    }
    if (maxY > center.dy + halfGap) {
      canvas.drawLine(
        Offset(p1.dx, center.dy + halfGap),
        Offset(p1.dx, maxY),
        paint,
      );
    }
    canvas.drawLine(
      Offset(p1.dx - tick, minY),
      Offset(p1.dx + tick, minY),
      paint,
    );
    canvas.drawLine(
      Offset(p1.dx - tick, maxY),
      Offset(p1.dx + tick, maxY),
      paint,
    );
  } else {
    final minX = math.min(p1.dx, p2.dx);
    final maxX = math.max(p1.dx, p2.dx);
    final halfGap = gap / 2;
    if (center.dx - halfGap > minX) {
      canvas.drawLine(
        Offset(minX, p1.dy),
        Offset(center.dx - halfGap, p1.dy),
        paint,
      );
    }
    if (maxX > center.dx + halfGap) {
      canvas.drawLine(
        Offset(center.dx + halfGap, p1.dy),
        Offset(maxX, p1.dy),
        paint,
      );
    }
    canvas.drawLine(
      Offset(minX, p1.dy - tick),
      Offset(minX, p1.dy + tick),
      paint,
    );
    canvas.drawLine(
      Offset(maxX, p1.dy - tick),
      Offset(maxX, p1.dy + tick),
      paint,
    );
  }

  canvas.save();
  canvas.translate(center.dx, center.dy);
  if (vertical) canvas.rotate(-math.pi / 2);
  textPainter.paint(
    canvas,
    Offset(-textPainter.width / 2, -textPainter.height / 2),
  );
  canvas.restore();
}
