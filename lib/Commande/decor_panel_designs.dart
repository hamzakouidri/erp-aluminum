import 'dart:math' as math;

import 'package:flutter/material.dart';

class DecorPanelDesignDefinition {
  final String code;
  final String label;

  const DecorPanelDesignDefinition(this.code, this.label);
}

/// Lightweight, code-drawn motifs for decorated PVC/aluminium door panels.
///
/// The database stores only [DecorPanelDesignDefinition.code]. Product names
/// can therefore be edited without breaking the drawing link.
class DecorPanelDesignCatalog {
  static const List<DecorPanelDesignDefinition> designs = [
    DecorPanelDesignDefinition('decor_arch_double', 'قوس علوي ولوحتان'),
    DecorPanelDesignDefinition('decor_fan_flutes', 'مروحة وخطوط طولية'),
    DecorPanelDesignDefinition('decor_diamond_rays', 'ماسة وأشعة'),
    DecorPanelDesignDefinition('decor_gothic_cross', 'قوس وزخرفة متقاطعة'),
    DecorPanelDesignDefinition('decor_fan_steps', 'مروحة ومستطيلات'),
    DecorPanelDesignDefinition('decor_clover_columns', 'زهرة وثلاثة أعمدة'),
    DecorPanelDesignDefinition('decor_classic_oval', 'كلاسيكي وبيضاوي'),
  ];

  static bool isSupported(String? code) {
    final normalized = code?.trim() ?? '';
    return designs.any((design) => design.code == normalized);
  }

  static String labelKeyFor(String? code) {
    final normalized = code?.trim() ?? '';
    for (final design in designs) {
      if (design.code == normalized) return design.label;
    }
    return 'بدون رسم مرتبط';
  }

  @Deprecated('Use labelKeyFor and pass the result through Localization.')
  static String labelFor(String? code) => labelKeyFor(code);

  /// Resolves a motif through the selected Glass/Panneau row ID. This avoids
  /// fragile product-name matching and keeps existing order data compact.
  static String? resolveForProduct({
    required int? productId,
    required Iterable<Map<String, dynamic>> glassProducts,
  }) {
    if (productId == null) return null;
    for (final product in glassProducts) {
      final rawId = product['id'];
      final id = rawId is num ? rawId.toInt() : int.tryParse('$rawId');
      if (id != productId) continue;
      final code = product['decor_design_code']?.toString().trim() ?? '';
      return isSupported(code) ? code : null;
    }
    return null;
  }
}

class DecorPanelDesignPreview extends StatelessWidget {
  final String? designCode;
  final Color panelColor;
  final double width;
  final double height;

  const DecorPanelDesignPreview({
    super.key,
    required this.designCode,
    this.panelColor = const Color(0xFFF3F4F6),
    this.width = 72,
    this.height = 128,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: CustomPaint(
        painter: DecorPanelDesignPainter(
          designCode: designCode,
          panelColor: panelColor,
        ),
      ),
    );
  }
}

class DecorPanelDesignPainter extends CustomPainter {
  final String? designCode;
  final Color panelColor;

  const DecorPanelDesignPainter({
    required this.designCode,
    this.panelColor = const Color(0xFFF3F4F6),
  });

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Offset.zero & size;
    final background = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color.lerp(panelColor, Colors.white, 0.16)!,
          panelColor,
          Color.lerp(panelColor, Colors.black, 0.08)!,
        ],
      ).createShader(bounds);
    canvas.drawRRect(
      RRect.fromRectAndRadius(bounds, const Radius.circular(5)),
      background,
    );
    final border = Paint()
      ..color = Color.lerp(panelColor, Colors.black, 0.42)!
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1, math.min(size.width, size.height) * 0.018);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        bounds.deflate(border.strokeWidth),
        const Radius.circular(5),
      ),
      border,
    );
    paintDesign(canvas, bounds, designCode, panelColor: panelColor);
  }

  static void paintDesign(
    Canvas canvas,
    Rect bounds,
    String? designCode, {
    Color panelColor = const Color(0xFFF3F4F6),
  }) {
    if (!DecorPanelDesignCatalog.isSupported(designCode) ||
        bounds.width <= 0 ||
        bounds.height <= 0) {
      return;
    }
    final inset = math.min(bounds.width, bounds.height) * 0.07;
    final rect = bounds.deflate(inset);
    if (rect.width <= 0 || rect.height <= 0) return;

    final dark = Color.lerp(panelColor, Colors.black, 0.38)!;
    final light = Color.lerp(panelColor, Colors.white, 0.62)!;
    final scale = math.min(rect.width, rect.height);
    final darkPaint = Paint()
      ..color = dark.withValues(alpha: 0.68)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = (scale * 0.019).clamp(1.1, 7.0);
    final lightPaint = Paint()
      ..color = light.withValues(alpha: 0.9)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = (darkPaint.strokeWidth * 0.52).clamp(0.7, 3.5);
    final glassFill = Paint()
      ..color = const Color(0xFF7DB7C7).withValues(alpha: 0.5)
      ..style = PaintingStyle.fill;

    Offset point(double x, double y) =>
        Offset(rect.left + rect.width * x, rect.top + rect.height * y);

    void ridge(Path path) {
      canvas.drawPath(path, darkPaint);
      canvas.save();
      canvas.translate(
        -darkPaint.strokeWidth * 0.22,
        -darkPaint.strokeWidth * 0.28,
      );
      canvas.drawPath(path, lightPaint);
      canvas.restore();
    }

    void ridgePolyline(List<Offset> points, {bool close = false}) {
      if (points.isEmpty) return;
      final path = Path()..moveTo(points.first.dx, points.first.dy);
      for (final p in points.skip(1)) {
        path.lineTo(p.dx, p.dy);
      }
      if (close) path.close();
      ridge(path);
    }

    void insetGlass(Path path) {
      canvas.drawPath(path, glassFill);
      ridge(path);
    }

    void archedPanel(double top, double bottom, {double side = 0.16}) {
      final path = Path()
        ..moveTo(point(side, bottom).dx, point(side, bottom).dy)
        ..lineTo(point(side, top + 0.055).dx, point(side, top + 0.055).dy)
        ..quadraticBezierTo(
          point(0.5, top - 0.035).dx,
          point(0.5, top - 0.035).dy,
          point(1 - side, top + 0.055).dx,
          point(1 - side, top + 0.055).dy,
        )
        ..lineTo(point(1 - side, bottom).dx, point(1 - side, bottom).dy)
        ..close();
      ridge(path);
    }

    void fanWindow({double top = 0.08, double bottom = 0.27}) {
      final path = Path()
        ..moveTo(point(0.23, bottom).dx, point(0.23, bottom).dy)
        ..quadraticBezierTo(
          point(0.5, top).dx,
          point(0.5, top).dy,
          point(0.77, bottom).dx,
          point(0.77, bottom).dy,
        )
        ..quadraticBezierTo(
          point(0.5, bottom + 0.12).dx,
          point(0.5, bottom + 0.12).dy,
          point(0.23, bottom).dx,
          point(0.23, bottom).dy,
        )
        ..close();
      insetGlass(path);
    }

    canvas.save();
    canvas.clipRect(bounds);
    switch (designCode) {
      case 'decor_arch_double':
        final glass = Path()
          ..moveTo(point(0.16, 0.18).dx, point(0.16, 0.18).dy)
          ..quadraticBezierTo(
            point(0.5, 0.08).dx,
            point(0.5, 0.08).dy,
            point(0.84, 0.18).dx,
            point(0.84, 0.18).dy,
          )
          ..lineTo(point(0.78, 0.31).dx, point(0.78, 0.31).dy)
          ..quadraticBezierTo(
            point(0.5, 0.37).dx,
            point(0.5, 0.37).dy,
            point(0.22, 0.31).dx,
            point(0.22, 0.31).dy,
          )
          ..close();
        insetGlass(glass);
        archedPanel(0.39, 0.59, side: 0.18);
        ridgePolyline([
          point(0.2, 0.68),
          point(0.8, 0.68),
          point(0.73, 0.91),
          point(0.27, 0.91),
        ], close: true);
        break;
      case 'decor_fan_flutes':
        fanWindow(top: 0.07, bottom: 0.22);
        for (final y in [0.29, 0.33]) {
          ridgePolyline([point(0.18, y), point(0.5, y + 0.08), point(0.82, y)]);
        }
        for (final x in [0.26, 0.36, 0.64, 0.74]) {
          ridgePolyline([point(0.5, 0.39), point(x, 0.83)]);
        }
        break;
      case 'decor_diamond_rays':
        final diamond = Path()
          ..moveTo(point(0.5, 0.08).dx, point(0.5, 0.08).dy)
          ..quadraticBezierTo(
            point(0.67, 0.12).dx,
            point(0.67, 0.12).dy,
            point(0.78, 0.21).dx,
            point(0.78, 0.21).dy,
          )
          ..lineTo(point(0.5, 0.34).dx, point(0.5, 0.34).dy)
          ..lineTo(point(0.22, 0.21).dx, point(0.22, 0.21).dy)
          ..quadraticBezierTo(
            point(0.33, 0.12).dx,
            point(0.33, 0.12).dy,
            point(0.5, 0.08).dx,
            point(0.5, 0.08).dy,
          )
          ..close();
        insetGlass(diamond);
        for (final dx in [0.12, 0.2, 0.28]) {
          ridgePolyline([point(0.5, 0.31), point(dx, 0.82)]);
          ridgePolyline([point(0.5, 0.31), point(1 - dx, 0.82)]);
        }
        break;
      case 'decor_gothic_cross':
        fanWindow(top: 0.055, bottom: 0.19);
        for (final y in [0.24, 0.28]) {
          ridgePolyline([point(0.16, y), point(0.5, y + 0.11), point(0.84, y)]);
        }
        for (final x in [0.2, 0.29, 0.71, 0.8]) {
          ridgePolyline([point(x, 0.34), point(1 - x, 0.86)]);
        }
        break;
      case 'decor_fan_steps':
        fanWindow(top: 0.075, bottom: 0.22);
        for (final y in [0.29, 0.39, 0.68]) {
          ridgePolyline([point(0.32, y), point(0.68, y)]);
        }
        ridgePolyline([
          point(0.36, 0.46),
          point(0.64, 0.46),
          point(0.64, 0.64),
          point(0.36, 0.64),
        ], close: true);
        ridgePolyline([
          point(0.38, 0.74),
          point(0.62, 0.74),
          point(0.62, 0.9),
          point(0.38, 0.9),
        ], close: true);
        break;
      case 'decor_clover_columns':
        final clover = Path()
          ..moveTo(point(0.18, 0.2).dx, point(0.18, 0.2).dy)
          ..quadraticBezierTo(
            point(0.28, 0.08).dx,
            point(0.28, 0.08).dy,
            point(0.42, 0.14).dx,
            point(0.42, 0.14).dy,
          )
          ..quadraticBezierTo(
            point(0.5, 0.03).dx,
            point(0.5, 0.03).dy,
            point(0.58, 0.14).dx,
            point(0.58, 0.14).dy,
          )
          ..quadraticBezierTo(
            point(0.72, 0.08).dx,
            point(0.72, 0.08).dy,
            point(0.82, 0.2).dx,
            point(0.82, 0.2).dy,
          )
          ..lineTo(point(0.5, 0.34).dx, point(0.5, 0.34).dy)
          ..close();
        insetGlass(clover);
        ridgePolyline([point(0.16, 0.26), point(0.5, 0.39), point(0.84, 0.26)]);
        for (final x in [0.27, 0.5, 0.73]) {
          ridgePolyline([point(x, 0.39), point(x, 0.86)]);
          for (final y in [0.43, 0.5, 0.78, 0.85]) {
            final half = y < 0.6 ? 0.055 : 0.045;
            ridgePolyline([
              point(x, y - 0.035),
              point(x + half, y),
              point(x, y + 0.035),
              point(x - half, y),
            ], close: true);
          }
        }
        break;
      case 'decor_classic_oval':
        archedPanel(0.08, 0.39, side: 0.15);
        final oval = Rect.fromCenter(
          center: point(0.5, 0.52),
          width: rect.width * 0.42,
          height: rect.height * 0.105,
        );
        final ovalPath = Path()..addOval(oval);
        ridge(ovalPath);
        archedPanel(0.63, 0.9, side: 0.18);
        break;
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant DecorPanelDesignPainter oldDelegate) {
    return oldDelegate.designCode != designCode ||
        oldDelegate.panelColor != panelColor;
  }
}
