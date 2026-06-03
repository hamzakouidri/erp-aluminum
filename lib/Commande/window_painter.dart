import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'dart:ui' as ui;
import 'package:database_data/Commande/Systeme/model.dart';
import 'package:database_data/Commande/texture_cache.dart';

class WindowPainter extends CustomPainter {
  final WindowModel model;

  WindowPainter({required this.model}) : super(repaint: model);

  @override
  void paint(Canvas canvas, Size size) {
    final w = model.width, h = model.height, t = model.profileThickness;
    double boxSize = 0;
    if (model.hasShutter) {
      if (h <= 1600) {
        boxSize = 155.0;
      } else if (h <= 2400) {
        boxSize = 185.0;
      } else {
        boxSize = 205.0;
      }
    }

    final innerPath = _buildInnerShapePath(w, h, t);

    canvas.save();
    canvas.clipPath(innerPath);
    for (final zone in model.zones) {
      _drawZoneBackground(canvas, zone, h, t);
    }
    canvas.restore();

    if (model.isInternalView) {
      if (model.hasShutter) {
        _drawShutterSlatsAndTracks(canvas, w, h, model.shutterPosition);
      }

      canvas.save();
      canvas.clipPath(innerPath);
      _drawMullions(canvas, w, h, t);
      canvas.restore();

      _drawOuterFrame(canvas, w, h, t);
      if (model.hasSideCovers) _drawSideCovers(canvas, w, h, boxSize, t);

      canvas.save();
      canvas.clipPath(innerPath);
      for (final zone in model.zones) {
        _drawZoneContent(canvas, zone, h, t);
        if (zone.content == ZoneContent.singleSash ||
            zone.content == ZoneContent.doubleSash) {
          if (zone.content == ZoneContent.singleSash &&
              zone.openDirection != null) {
            _drawWindowDrawHandle(
              canvas,
              _getEffectiveZoneRect(zone.boundary, h, t),
              zone.openDirection!,
              zone.handlePositionRatio ?? 0.5,
            );
          }
        }
      }
      canvas.restore();

      if (model.hasShutter) _drawShutterBox(canvas, w, boxSize);
    } else {
      _drawOuterFrame(canvas, w, h, t);
      if (model.hasSideCovers) _drawSideCovers(canvas, w, h, boxSize, t);

      // 🟢 تصحيح 1: إخراج الصندوق من القص لكي يظهر ويتلون
      if (model.hasShutter) {
        _drawShutterBox(canvas, w, boxSize);
      }

      canvas.save();
      canvas.clipPath(innerPath);
      _drawMullions(canvas, w, h, t);
      canvas.restore();

      if (model.hasBottomFrame) {
        _drawWeepHoles(canvas, Rect.fromLTWH(0, 0, w, h), t);
      }

      canvas.save();
      canvas.clipPath(innerPath);
      for (final zone in model.zones) {
        _drawZoneContent(canvas, zone, h, t);
      }
      // 🟢 رسم الشفرات مرة واحدة داخل القص
      if (model.hasShutter) {
        _drawShutterSlatsAndTracks(canvas, w, h, model.shutterPosition);
      }
      canvas.restore();
    }

    for (final zone in model.zones) {
      if (model.selectedZone != null && model.selectedZone!.id == zone.id) {
        final r = zone.boundary;
        bool highlightEntireZone =
            model.activeSubZone == 'all' ||
            zone.content != ZoneContent.doubleSash;
        if (highlightEntireZone) {
          canvas.drawRect(
            r,
            Paint()
              ..color = Colors.green.shade700.withValues(alpha: 0.35)
              ..style = PaintingStyle.fill,
          );
        } else {
          final sep = 4.0;
          final midX = r.left + r.width / 2;
          Rect sashR;
          if (model.activeSubZone != null &&
              model.activeSubZone!.startsWith('left')) {
            sashR = Rect.fromLTRB(r.left, r.top, midX - sep / 2, r.bottom);
          } else {
            sashR = Rect.fromLTRB(midX + sep / 2, r.top, r.right, r.bottom);
          }
          final thicknessFactor = zone.isSash105 ? 0.14 : 0.10;
          final sashT = math.min(sashR.width, sashR.height) * thicknessFactor;
          final glassR = sashR.deflate(sashT);
          final Path highlightPath = Path()
            ..fillType = PathFillType.evenOdd
            ..addRect(sashR)
            ..addRect(glassR);
          canvas.drawPath(
            highlightPath,
            Paint()
              ..color = Colors.green.shade800.withValues(alpha: 0.35)
              ..style = PaintingStyle.fill,
          );
          canvas.drawPath(
            highlightPath,
            Paint()
              ..color = Colors.green.shade900
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2.5,
          );
        }
      }
      _drawInnerDimensions(canvas, zone);
    }

    if (model.drawingStart != null && model.drawingCurrent != null) {
      final p1 = model.drawingStart!;
      final p2 = model.drawingCurrent!;
      double dx = (p2.dx - p1.dx).abs();
      double dy = (p2.dy - p1.dy).abs();

      if ((p2 - p1).distance > 30.0) {
        bool isHorizontal = dx > dy;
        Offset endPos = isHorizontal
            ? Offset(p2.dx, p1.dy)
            : Offset(p1.dx, p2.dy);

        final drawPaint = Paint()
          ..color = const Color(0xFF0D47A1)
          ..strokeWidth = 6.0
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.square;

        final slashPaint = Paint()
          ..color = const Color(0xFFB71C1C)
          ..strokeWidth = 6.0
          ..strokeCap = StrokeCap.round;

        double dashWidth = 25.0, dashSpace = 15.0, step = dashWidth + dashSpace;

        if (isHorizontal) {
          double startX = math.min(p1.dx, endPos.dx),
              endX = math.max(p1.dx, endPos.dx);
          for (double x = startX; x < endX; x += step) {
            canvas.drawLine(
              Offset(x, p1.dy),
              Offset(math.min(x + dashWidth, endX), p1.dy),
              drawPaint,
            );
          }
        } else {
          double startY = math.min(p1.dy, endPos.dy),
              endY = math.max(p1.dy, endPos.dy);
          for (double y = startY; y < endY; y += step) {
            canvas.drawLine(
              Offset(p1.dx, y),
              Offset(p1.dx, math.min(y + dashWidth, endY)),
              drawPaint,
            );
          }
        }

        double slashSize = 20.0;
        if (isHorizontal) {
          canvas.drawLine(
            Offset(p1.dx, p1.dy - slashSize),
            Offset(p1.dx, p1.dy + slashSize),
            slashPaint,
          );
          canvas.drawLine(
            Offset(endPos.dx, endPos.dy - slashSize),
            Offset(endPos.dx, endPos.dy + slashSize),
            slashPaint,
          );
        } else {
          canvas.drawLine(
            Offset(p1.dx - slashSize, p1.dy),
            Offset(p1.dx + slashSize, p1.dy),
            slashPaint,
          );
          canvas.drawLine(
            Offset(endPos.dx - slashSize, endPos.dy),
            Offset(endPos.dx + slashSize, endPos.dy),
            slashPaint,
          );
        }
      }
    }
  }

  List<Color> get _fc {
    if (model.selectedDbColor != null) {
      final hexCode = (model.selectedDbColor!['hex_code'] as String)
          .toUpperCase();

      if (hexCode == '#FFFFFF') return FrameColor.white.gradientColors;
      if (hexCode == '#795548' || hexCode == '#5D4037')
        return FrameColor.brown.gradientColors;
      if (hexCode == '#9E9E9E' || hexCode == '#B0BEC5' || hexCode == '#E0E0E0')
        return FrameColor.gray.gradientColors;
      if (hexCode == '#000000' || hexCode == '#212121')
        return FrameColor.black.gradientColors;
      if (hexCode == '#F5F5DC' || hexCode == '#DDC8A0')
        return FrameColor.beige.gradientColors;

      Color c = Colors.grey;
      try {
        c = Color(int.parse(hexCode.replaceFirst('#', '0xFF')));
      } catch (_) {}

      final hsl = HSLColor.fromColor(c);
      final light = hsl
          .withLightness((hsl.lightness + 0.15).clamp(0.0, 1.0))
          .toColor();
      final dark = hsl
          .withLightness((hsl.lightness - 0.1).clamp(0.0, 1.0))
          .toColor();
      return [light, c, dark];
    }
    return model.frameColor.gradientColors;
  }

  Color get _fb {
    if (model.selectedDbColor != null) {
      final hexCode = model.selectedDbColor!['hex_code'] as String;
      Color c = Colors.grey;
      try {
        c = Color(int.parse(hexCode.replaceFirst('#', '0xFF')));
      } catch (_) {}

      final hsl = HSLColor.fromColor(c);
      return hsl.withLightness((hsl.lightness - 0.2).clamp(0.0, 1.0)).toColor();
    }
    return model.frameColor.borderColor;
  }

  Color get _mc => Color.lerp(_fc.last, Colors.black, 0.4)!;

  Shader _fsGlobal(
    Rect r, {
    List<Color>? gradientColors,
    Map<String, dynamic>? dbColor,
  }) {
    final effectiveDbColor = dbColor ?? model.selectedDbColor;
    if (effectiveDbColor != null) {
      final name = effectiveDbColor['name'].toString().toLowerCase();
      if ((name.contains('خشب') ||
              name.contains('wood') ||
              name.contains('bois')) &&
          TextureCache.woodTexture != null) {
        return ui.ImageShader(
          TextureCache.woodTexture!,
          ui.TileMode.repeated,
          ui.TileMode.repeated,
          Matrix4.identity().scaled(0.5).storage,
        );
      }
    }
    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: gradientColors ?? _fc,
    ).createShader(r);
  }

  Rect _getEffectiveZoneRect(Rect original, double h, double t) {
    if (!model.hasBottomFrame && (original.bottom - (h - t)).abs() < 1.0) {
      return Rect.fromLTRB(original.left, original.top, original.right, h);
    }
    return original;
  }

  Path _buildOuterShapePath(double w, double h) {
    if (model.archHeight == 0 &&
        model.topSlantLeftY == 0 &&
        model.topSlantRightY == 0 &&
        model.bottomSlantLeftY == 0 &&
        model.bottomSlantRightY == 0) {
      return Path()..addRect(Rect.fromLTWH(0, 0, w, h));
    }
    Path p = Path();
    p.moveTo(0, model.topSlantLeftY);
    if (model.archHeight > 0) {
      p.quadraticBezierTo(
        w / 2,
        math.min(model.topSlantLeftY, model.topSlantRightY) -
            (model.archHeight * 2),
        w,
        model.topSlantRightY,
      );
    } else {
      p.lineTo(w, model.topSlantRightY);
    }
    p.lineTo(w, h - model.bottomSlantRightY);
    p.lineTo(0, h - model.bottomSlantLeftY);
    p.close();
    return p;
  }

  Path _buildInnerShapePath(double w, double h, double t) {
    if (model.archHeight == 0 &&
        model.topSlantLeftY == 0 &&
        model.topSlantRightY == 0 &&
        model.bottomSlantLeftY == 0 &&
        model.bottomSlantRightY == 0) {
      return Path()..addRect(Rect.fromLTWH(t, t, w - t * 2, h - t * 2));
    }
    Path p = Path();
    p.moveTo(t, model.topSlantLeftY + t);
    if (model.archHeight > 0) {
      p.quadraticBezierTo(
        w / 2,
        math.min(model.topSlantLeftY, model.topSlantRightY) -
            (model.archHeight * 2) +
            t,
        w - t,
        model.topSlantRightY + t,
      );
    } else {
      p.lineTo(w - t, model.topSlantRightY + t);
    }
    p.lineTo(w - t, h - model.bottomSlantRightY - t);
    p.lineTo(t, h - model.bottomSlantLeftY - t);
    p.close();
    return p;
  }

  void _drawOuterFrame(Canvas canvas, double w, double h, double t) {
    final outerPath = _buildOuterShapePath(w, h);
    final innerPath = _buildInnerShapePath(w, h, t);

    final path = Path();
    if (model.hasBottomFrame) {
      path
        ..addPath(outerPath, Offset.zero)
        ..addPath(innerPath, Offset.zero)
        ..fillType = PathFillType.evenOdd;
    } else {
      path
        ..addPath(outerPath, Offset.zero)
        ..addPath(innerPath, Offset.zero)
        ..fillType = PathFillType.evenOdd;
    }

    final outerRect = Rect.fromLTWH(0, 0, w, h);
    canvas.drawPath(path, Paint()..shader = _fsGlobal(outerRect));

    final bp = Paint()
      ..color = _fb
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    if (model.hasBottomFrame) {
      canvas.drawPath(outerPath, bp);
      canvas.drawPath(innerPath, bp..strokeWidth = 0.8);
    } else {
      canvas.drawPath(outerPath, bp);
      canvas.drawPath(innerPath, bp..strokeWidth = 0.8);
    }

    _drawMiterCorners(
      canvas,
      outerRect,
      Rect.fromLTWH(t, t, w - t * 2, h - t * 2),
      t,
    );
  }

  void _drawMiterCorners(Canvas canvas, Rect outer, Rect inner, double t) {
    final p = Paint()
      ..color = _mc
      ..strokeWidth = 1.8
      ..style = PaintingStyle.stroke;
    canvas.drawLine(outer.topLeft, inner.topLeft, p);
    canvas.drawLine(outer.topRight, inner.topRight, p);
    if (model.hasBottomFrame) {
      canvas.drawLine(outer.bottomLeft, inner.bottomLeft, p);
      canvas.drawLine(outer.bottomRight, inner.bottomRight, p);
    }
  }

  void _drawSideCovers(
    Canvas canvas,
    double w,
    double h,
    double boxSize,
    double t,
  ) {
    final topY = model.hasShutter ? -boxSize : 0.0;
    final paint = Paint()..color = _fc[1];
    final borderPaint = Paint()
      ..color = _fb
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    final hasL = !model.removedShutterSides.contains('left'),
        hasR = !model.removedShutterSides.contains('right'),
        hasT = !model.removedShutterSides.contains('top'),
        hasB =
            !model.removedShutterSides.contains('bottom') &&
            model.hasBottomFrame;
    if (hasL) {
      canvas.drawPath(
        Path()
          ..moveTo(0, topY)
          ..lineTo(-t, hasT ? topY - t : topY)
          ..lineTo(-t, hasB ? h + t : h)
          ..lineTo(0, h)
          ..close(),
        paint,
      );
      canvas.drawPath(
        Path()
          ..moveTo(0, topY)
          ..lineTo(-t, hasT ? topY - t : topY)
          ..lineTo(-t, hasB ? h + t : h)
          ..lineTo(0, h)
          ..close(),
        borderPaint,
      );
    }
    if (hasR) {
      canvas.drawPath(
        Path()
          ..moveTo(w, topY)
          ..lineTo(w + t, hasT ? topY - t : topY)
          ..lineTo(w + t, hasB ? h + t : h)
          ..lineTo(w, h)
          ..close(),
        paint,
      );
      canvas.drawPath(
        Path()
          ..moveTo(w, topY)
          ..lineTo(w + t, hasT ? topY - t : topY)
          ..lineTo(w + t, hasB ? h + t : h)
          ..lineTo(w, h)
          ..close(),
        borderPaint,
      );
    }
    if (hasT) {
      canvas.drawPath(
        Path()
          ..moveTo(0, topY)
          ..lineTo(hasL ? -t : 0.0, topY - t)
          ..lineTo(hasR ? w + t : w, topY - t)
          ..lineTo(w, topY)
          ..close(),
        paint,
      );
      canvas.drawPath(
        Path()
          ..moveTo(0, topY)
          ..lineTo(hasL ? -t : 0.0, topY - t)
          ..lineTo(hasR ? w + t : w, topY - t)
          ..lineTo(w, topY)
          ..close(),
        borderPaint,
      );
    }
    if (hasB) {
      canvas.drawPath(
        Path()
          ..moveTo(0, h)
          ..lineTo(hasL ? -t : 0.0, h + t)
          ..lineTo(hasR ? w + t : w, h + t)
          ..lineTo(w, h)
          ..close(),
        paint,
      );
      canvas.drawPath(
        Path()
          ..moveTo(0, h)
          ..lineTo(hasL ? -t : 0.0, h + t)
          ..lineTo(hasR ? w + t : w, h + t)
          ..lineTo(w, h)
          ..close(),
        borderPaint,
      );
    }
  }

  void _drawMullions(Canvas canvas, double w, double h, double t) {
    final Paint paint = Paint()
      ..color = model.frameColor.gradientColors[1]
      ..style = PaintingStyle.fill;
    final Paint border = Paint()
      ..color = model.frameColor.borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    Path combinedPath = Path();
    for (int i = 0; i < model.zones.length; i++) {
      final z1 = model.zones[i];
      for (int j = i + 1; j < model.zones.length; j++) {
        final z2 = model.zones[j];
        double overlapLeft = math.max(z1.boundary.left, z2.boundary.left);
        double overlapRight = math.min(z1.boundary.right, z2.boundary.right);
        if (overlapLeft < overlapRight - 5) {
          if ((z1.boundary.bottom - z2.boundary.top).abs() <= t + 2) {
            double yCenter = (z1.boundary.bottom + z2.boundary.top) / 2;
            combinedPath = Path.combine(
              PathOperation.union,
              combinedPath,
              Path()..addRect(
                Rect.fromLTRB(
                  overlapLeft - t / 2,
                  yCenter - t / 2,
                  overlapRight + t / 2,
                  yCenter + t / 2,
                ),
              ),
            );
          } else if ((z2.boundary.bottom - z1.boundary.top).abs() <= t + 2) {
            double yCenter = (z2.boundary.bottom + z1.boundary.top) / 2;
            combinedPath = Path.combine(
              PathOperation.union,
              combinedPath,
              Path()..addRect(
                Rect.fromLTRB(
                  overlapLeft - t / 2,
                  yCenter - t / 2,
                  overlapRight + t / 2,
                  yCenter + t / 2,
                ),
              ),
            );
          }
        }
        double overlapTop = math.max(z1.boundary.top, z2.boundary.top);
        double overlapBottom = math.min(z1.boundary.bottom, z2.boundary.bottom);
        if (overlapTop < overlapBottom - 5) {
          if ((z1.boundary.right - z2.boundary.left).abs() <= t + 2) {
            double xCenter = (z1.boundary.right + z2.boundary.left) / 2;
            combinedPath = Path.combine(
              PathOperation.union,
              combinedPath,
              Path()..addRect(
                Rect.fromLTRB(
                  xCenter - t / 2,
                  overlapTop - t / 2,
                  xCenter + t / 2,
                  overlapBottom + t / 2,
                ),
              ),
            );
          } else if ((z2.boundary.right - z1.boundary.left).abs() <= t + 2) {
            double xCenter = (z2.boundary.right + z1.boundary.left) / 2;
            combinedPath = Path.combine(
              PathOperation.union,
              combinedPath,
              Path()..addRect(
                Rect.fromLTRB(
                  xCenter - t / 2,
                  overlapTop - t / 2,
                  xCenter + t / 2,
                  overlapBottom + t / 2,
                ),
              ),
            );
          }
        }
      }
    }

    canvas.save();
    canvas.clipRect(Rect.fromLTWH(t, t, w - t * 2, h - t * 2));

    canvas.drawPath(combinedPath, paint);
    canvas.drawPath(combinedPath, border);

    if (model.selection.type == SelectionType.mullion) {
      bool isH = model.selection.isHorizontalMullion!;
      double pos = model.selection.mullionPosition!;
      if (isH) {
        canvas.drawRect(
          Rect.fromLTRB(0, pos - t / 2, w, pos + t / 2),
          Paint()..color = Colors.green.shade600.withValues(alpha: 0.5),
        );
      } else {
        canvas.drawRect(
          Rect.fromLTRB(pos - t / 2, 0, pos + t / 2, h),
          Paint()..color = Colors.green.shade600.withValues(alpha: 0.5),
        );
      }
    }

    canvas.restore();
  }

  void _drawInnerDimensions(Canvas canvas, WindowZone zone) {
    final r = zone.boundary;
    if (r.width < 150 || r.height < 150) return;
    bool isFullWidth =
        (r.width >= model.width - model.profileThickness * 2 - 2);
    bool isFullHeight =
        (r.height >= model.height - model.profileThickness * 2 - 2);
    final textStyle = const TextStyle(
      color: Color(0xFF1565C0),
      fontSize: 60,
      fontWeight: FontWeight.bold,
    );

    if (!isFullWidth) {
      final widthText = TextPainter(
        text: TextSpan(text: "${r.width.toInt()}", style: textStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      final wOffset = Offset(r.center.dx - (widthText.width / 2), r.top + 5);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            wOffset.dx - 6,
            wOffset.dy - 2,
            widthText.width + 12,
            widthText.height + 4,
          ),
          const Radius.circular(6),
        ),
        Paint()..color = Colors.white.withValues(alpha: 0.85),
      );
      widthText.paint(canvas, wOffset);
    }
    if (!isFullHeight) {
      final heightText = TextPainter(
        text: TextSpan(text: "${r.height.toInt()}", style: textStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      canvas.save();
      canvas.translate(
        r.left + 5 + heightText.height,
        r.center.dy + (heightText.width / 2),
      );
      canvas.rotate(-3.1415926535897932 / 2);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            -6,
            -heightText.height - 2,
            heightText.width + 12,
            heightText.height + 4,
          ),
          const Radius.circular(6),
        ),
        Paint()..color = Colors.white.withValues(alpha: 0.85),
      );
      heightText.paint(canvas, Offset(0, -heightText.height));
      canvas.restore();
    }
  }

  void _drawZoneBackground(Canvas canvas, WindowZone zone, double h, double t) {
    canvas.drawRect(
      _getEffectiveZoneRect(zone.boundary, h, t),
      Paint()..color = const Color(0xFFF5F8FA),
    );
  }

  void _drawZoneContent(Canvas canvas, WindowZone zone, double h, double t) {
    final r = _getEffectiveZoneRect(zone.boundary, h, t);
    switch (zone.content) {
      case ZoneContent.empty:
      case ZoneContent.fixedGlass:
        if (zone.glass.structure == GlassStructure.closed) {
          _drawPanelTexture(canvas, r, model.frameColor);
        } else if (zone.content == ZoneContent.fixedGlass) {
          _drawFixedGlass(canvas, r, zone.glass);
        }
        _drawRealisticParclose(canvas, r, model.frameColor);
        break;
      case ZoneContent.singleSash:
        _drawSingleSash(canvas, r, zone);
        break;
      case ZoneContent.doubleSash:
        final sep = 4.0;
        final midX = r.left + r.width / 2;
        final leftR = Rect.fromLTRB(r.left, r.top, midX - sep / 2, r.bottom);
        final rightR = Rect.fromLTRB(midX + sep / 2, r.top, r.right, r.bottom);
        bool isLeftActive = (zone.openDirection == OpenDirection.left);
        bool isRightActive = (zone.openDirection == OpenDirection.right);
        if (!isLeftActive && !isRightActive) isRightActive = true;
        _renderSash(
          canvas,
          leftR,
          zone.copyWith(openDirection: OpenDirection.right),
          leftR,
          forceHandle: isLeftActive,
          isRightSash: false,
        );
        _renderSash(
          canvas,
          rightR,
          zone.copyWith(openDirection: OpenDirection.left),
          rightR,
          forceHandle: isRightActive,
          isRightSash: true,
        );
        canvas.drawLine(
          Offset(midX, r.top),
          Offset(midX, r.bottom),
          Paint()
            ..color = _fb
            ..strokeWidth = 1.2,
        );
        break;
      case ZoneContent.slidingSash:
        _drawSlidingSash(canvas, r, zone);
        break;
    }
  }

  void _drawFixedGlass(Canvas canvas, Rect r, GlassSpecification glass) {
    final isLookingFromInside = model.isInternalView;
    _drawGlassLayer(
      canvas,
      r,
      isLookingFromInside ? glass.colorInner : glass.colorOuter,
      isLookingFromInside ? glass.finishInner : glass.finishOuter,
      glass.structure,
      glass.colorP,
    );
    _drawGlassLabel(canvas, r, glass.displayName);
  }

  void _drawGlassLayer(
    Canvas canvas,
    Rect r,
    GlassColor color,
    GlassFinish finish,
    GlassStructure structure,
    ClosedGlassColor colorP,
  ) {
    canvas.drawRect(
      r,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: _getColorsForLayer(structure, color, finish, colorP),
        ).createShader(r),
    );
    if (structure != GlassStructure.closed &&
        (finish == GlassFinish.clair || finish == GlassFinish.stopSol)) {
      canvas.drawLine(
        Offset(r.left + r.width * 0.08, r.top + r.height * 0.05),
        Offset(r.left + r.width * 0.38, r.top + r.height * 0.45),
        Paint()
          ..color = Colors.white.withValues(alpha: 0.40)
          ..strokeWidth = r.width * 0.09
          ..strokeCap = StrokeCap.round,
      );
      canvas.drawLine(
        Offset(r.left + r.width * 0.58, r.top + r.height * 0.05),
        Offset(r.left + r.width * 0.68, r.top + r.height * 0.22),
        Paint()
          ..color = Colors.white.withValues(alpha: 0.25)
          ..strokeWidth = r.width * 0.035
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  List<Color> _getColorsForLayer(
    GlassStructure str,
    GlassColor c,
    GlassFinish f,
    ClosedGlassColor p,
  ) {
    if (str == GlassStructure.closed) {
      switch (p) {
        case ClosedGlassColor.white:
          return [Colors.white, Colors.white, Colors.white];
        case ClosedGlassColor.black:
          return [
            const Color(0xFF111111),
            const Color(0xFF222222),
            const Color(0xFF333333),
          ];
        case ClosedGlassColor.grisClair:
          return [
            Colors.grey.shade300,
            Colors.grey.shade400,
            Colors.grey.shade500,
          ];
        case ClosedGlassColor.fbmClair:
          return [
            const Color(0xFFF5F5F5),
            const Color(0xFFE0E0E0),
            const Color(0xFFBDBDBD),
          ];
        case ClosedGlassColor.fbmfonce:
          return [
            const Color(0xFF424242),
            const Color(0xFF212121),
            const Color(0xFF000000),
          ];
        case ClosedGlassColor.grissoris:
          return [
            const Color(0xFF757575),
            const Color(0xFF616161),
            const Color(0xFF424242),
          ];
        case ClosedGlassColor.beige:
          return [
            const Color(0xFFF5E6C8),
            const Color(0xFFDDC8A0),
            const Color(0xFFBBA070),
          ];
        case ClosedGlassColor.transparent:
          return [Colors.white, Colors.white, Colors.white];
        case ClosedGlassColor.opaque:
          return [
            Colors.grey.shade200,
            Colors.grey.shade300,
            Colors.grey.shade400,
          ];
        case ClosedGlassColor.marberier:
          throw UnimplementedError();
      }
    }
    Color baseLight = Colors.white,
        baseMid = Colors.white,
        baseDark = Colors.white;
    switch (c) {
      case GlassColor.brown:
        baseLight = const Color(0xFFD7CCC8);
        baseMid = const Color(0xFFA1887F);
        baseDark = const Color(0xFF5D4037);
        break;
      case GlassColor.green:
        baseLight = const Color(0xFFC8E6C9);
        baseMid = const Color(0xFF81C784);
        baseDark = const Color(0xFF388E3C);
        break;
      case GlassColor.gray:
      case GlassColor.grayAgc:
        baseLight = const Color(0xFFE0E0E0);
        baseMid = const Color(0xFF9E9E9E);
        baseDark = const Color(0xFF616161);
        break;
      case GlassColor.blue:
      case GlassColor.blueAgc:
        baseLight = const Color(0xFFBBDEFB);
        baseMid = const Color(0xFF64B5F6);
        baseDark = const Color(0xFF1976D2);
        break;
      case GlassColor.transparent:
        baseLight = const Color(0xFFE3F2FD);
        baseMid = const Color(0xFF90CAF9);
        baseDark = const Color(0xFF42A5F5);
        break;
    }
    if (f == GlassFinish.stopSol) return [baseLight, baseDark, baseMid];
    return [
      baseLight.withValues(alpha: 0.7),
      baseMid.withValues(alpha: 0.5),
      baseDark.withValues(alpha: 0.6),
    ];
  }

  void _drawGlassLabel(Canvas canvas, Rect r, String text) {
    if (text.trim().isEmpty || r.width < 100) return;
    final textPainter = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 16,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.rtl,
    )..layout(maxWidth: r.width - 10);
    final offset = Offset(
      r.center.dx - (textPainter.width / 2),
      r.center.dy - (textPainter.height / 2),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          offset.dx - 6,
          offset.dy - 4,
          textPainter.width + 12,
          textPainter.height + 8,
        ),
        const Radius.circular(4),
      ),
      Paint()..color = Colors.black.withValues(alpha: 0.5),
    );
    textPainter.paint(canvas, offset);
  }

  void _drawSingleSash(Canvas canvas, Rect r, WindowZone zone) =>
      _renderSash(canvas, r, zone, r, isRightSash: false);

  void _drawSlidingSash(Canvas canvas, Rect r, WindowZone zone) {
    final t = math.min(r.width, r.height) * 0.06;
    final midX = r.left + r.width / 2;
    final backGlass = Rect.fromLTRB(
      r.left,
      r.top,
      r.right,
      r.bottom,
    ).deflate(t);
    _drawSashFrameRect(
      canvas,
      r,
      backGlass,
      zone.sashColor,
      zone.selectedDbColor,
      dimmed: true,
    );
    _drawFixedGlass(canvas, backGlass, zone.glass);
    final frontR = Rect.fromLTRB(midX - t, r.top, r.right, r.bottom);
    final frontGlass = frontR.deflate(t);
    _drawSashFrameRect(
      canvas,
      frontR,
      frontGlass,
      zone.sashColor,
      zone.selectedDbColor,
      dimmed: false,
    );
    _drawFixedGlass(canvas, frontGlass, zone.glass);
    final cx = r.center.dx, cy = r.center.dy;
    final sz = math.min(r.width, r.height) * 0.10;
    final p = Paint()
      ..color = const Color(0xFF42A5F5).withValues(alpha: 0.55)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(cx - sz * 0.2, cy), Offset(cx - sz, cy), p);
    canvas.drawLine(Offset(cx + sz * 0.2, cy), Offset(cx + sz, cy), p);
  }

  void _drawPanelTexture(Canvas canvas, Rect r, FrameColor color) {
    canvas.drawRect(
      r,
      Paint()
        ..color = color.gradientColors[1]
        ..style = PaintingStyle.fill,
    );
    Paint linePaint = Paint()
      ..color = color.borderColor.withValues(alpha: 0.3)
      ..strokeWidth = 1.0;
    for (double x = r.left + 15; x < r.right; x += 15) {
      canvas.drawLine(Offset(x, r.top), Offset(x, r.bottom), linePaint);
    }
  }

  void _drawInternalDivisions(
    Canvas canvas,
    Rect glassR,
    int innerH,
    int innerV,
    FrameColor color,
    double sashT,
    WindowZone zone,
    bool isRightSash,
  ) {
    String sidePrefix = zone.content == ZoneContent.doubleSash
        ? (isRightSash ? 'right' : 'main')
        : 'main';
    if (zone.content == ZoneContent.doubleSash && !isRightSash) {
      sidePrefix = 'left';
    }

    if (innerH == 0 && innerV == 0) {
      if (zone.cellIsPanel['${sidePrefix}_cell_0_0'] == true) {
        _drawPanelTexture(canvas, glassR, color);
      }
      _drawRealisticParclose(canvas, glassR, color);
      if (model.selectedZone?.id == zone.id &&
          model.activeSubZone == '${sidePrefix}_cell_0_0') {
        canvas.drawRect(
          glassR,
          Paint()
            ..color = Colors.green.shade700.withValues(alpha: 0.4)
            ..style = PaintingStyle.fill,
        );
      }
      return;
    }
    final double dividerT = sashT;
    final Paint paint = Paint()
      ..color = color.gradientColors[1]
      ..style = PaintingStyle.fill;
    final Paint border = Paint()
      ..color = color.borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    Path combinedPath = Path();
    final double stepY = glassR.height / (innerH + 1);
    final double stepX = glassR.width / (innerV + 1);

    if (innerH > 0) {
      for (int i = 1; i <= innerH; i++) {
        double y = glassR.top + (stepY * i);
        combinedPath = Path.combine(
          PathOperation.union,
          combinedPath,
          Path()..addRect(
            Rect.fromLTRB(
              glassR.left,
              y - dividerT / 2,
              glassR.right,
              y + dividerT / 2,
            ),
          ),
        );
      }
    }
    if (innerV > 0) {
      for (int i = 1; i <= innerV; i++) {
        double x = glassR.left + (stepX * i);
        combinedPath = Path.combine(
          PathOperation.union,
          combinedPath,
          Path()..addRect(
            Rect.fromLTRB(
              x - dividerT / 2,
              glassR.top,
              x + dividerT / 2,
              glassR.bottom,
            ),
          ),
        );
      }
    }
    canvas.drawPath(combinedPath, paint);
    canvas.drawPath(combinedPath, border);

    for (int row = 0; row <= innerH; row++) {
      for (int col = 0; col <= innerV; col++) {
        double top = glassR.top + (row * stepY);
        if (row > 0) top += dividerT / 2;
        double bottom = glassR.top + ((row + 1) * stepY);
        if (row < innerH) bottom -= dividerT / 2;
        double left = glassR.left + (col * stepX);
        if (col > 0) left += dividerT / 2;
        double right = glassR.left + ((col + 1) * stepX);
        if (col < innerV) right -= dividerT / 2;
        Rect cellRect = Rect.fromLTRB(left, top, right, bottom);
        if (cellRect.width > 4 && cellRect.height > 4) {
          String cellKey = '${sidePrefix}_cell_${row}_$col';
          if (zone.cellIsPanel[cellKey] == true) {
            _drawPanelTexture(canvas, cellRect, color);
          }
          _drawRealisticParclose(canvas, cellRect, color, customThickness: 4.0);
          if (model.selectedZone?.id == zone.id &&
              model.activeSubZone == cellKey) {
            canvas.drawRect(
              cellRect,
              Paint()
                ..color = Colors.green.shade700.withValues(alpha: 0.4)
                ..style = PaintingStyle.fill,
            );
          }
        }
      }
    }
  }

  void _renderSash(
    Canvas canvas,
    Rect zoneR,
    WindowZone zone,
    Rect sashR, {
    bool forceHandle = true,
    bool isRightSash = false,
  }) {
    final thicknessFactor = zone.isSash105 ? 0.14 : 0.10;
    final sashT = math.min(sashR.width, sashR.height) * thicknessFactor;
    final glassR = sashR.deflate(sashT);
    _drawFixedGlass(canvas, glassR, zone.glass);
    int currentInnerH = isRightSash ? zone.rightInnerH : zone.innerH;
    int currentInnerV = isRightSash ? zone.rightInnerV : zone.innerV;
    _drawInternalDivisions(
      canvas,
      glassR,
      currentInnerH,
      currentInnerV,
      zone.sashColor,
      sashT,
      zone,
      isRightSash,
    );
    _drawSashFrameRect(
      canvas,
      sashR,
      glassR,
      zone.sashColor,
      zone.selectedDbColor,
      dimmed: false,
    );

    if (model.isInternalView && zone.openDirection != null) {
      bool hingesOnRight = (zone.openDirection == OpenDirection.left);
      bool hingesOnLeft = (zone.openDirection == OpenDirection.right);
      _drawHinges(
        canvas,
        sashR,
        hingesOnRight,
        hingesOnLeft,
        (zone.openDirection == OpenDirection.bottom),
        (zone.openDirection == OpenDirection.top),
        zone.glass,
      );
      if (forceHandle) {
        _drawWindowDrawHandle(
          canvas,
          sashR,
          zone.openDirection!,
          zone.handlePositionRatio ?? 0.5,
        );
      }
    }
  }

  void _drawSashFrameRect(
    Canvas canvas,
    Rect sashR,
    Rect glassR,
    FrameColor color,
    Map<String, dynamic>? dbColor, {
    required bool dimmed,
  }) {
    final Path framePath = Path()
      ..addRect(sashR)
      ..addRect(glassR)
      ..fillType = PathFillType.evenOdd;

    final grads = getEffectiveGradientColors(color, dbColor);
    final border = getEffectiveBorderColor(color, dbColor);
    canvas.drawPath(
      framePath,
      Paint()..shader = _fsGlobal(sashR, gradientColors: grads),
    );
    canvas.drawRect(
      sashR,
      Paint()
        ..color = border
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0,
    );
    canvas.drawRect(
      glassR,
      Paint()
        ..color = border
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8,
    );
    canvas.drawRect(
      glassR.inflate(3),
      Paint()
        ..color = Colors.black26
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0,
    );
    canvas.drawRect(
      glassR.inflate(1.5),
      Paint()
        ..color = const Color(0xFF1A1A1A)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );
    final mp = Paint()
      ..color = Color.lerp(color.gradientColors.last, Colors.black, 0.4)!
      ..strokeWidth = 1.2;
    canvas.drawLine(sashR.topLeft, glassR.topLeft, mp);
    canvas.drawLine(sashR.topRight, glassR.topRight, mp);
    canvas.drawLine(sashR.bottomLeft, glassR.bottomLeft, mp);
    canvas.drawLine(sashR.bottomRight, glassR.bottomRight, mp);
  }

  void _drawWindowDrawHandle(
    Canvas canvas,
    Rect sashRect,
    OpenDirection handleSide,
    double ratio,
  ) {
    double handleY = sashRect.center.dy;
    double x = sashRect.center.dx;
    if (handleSide == OpenDirection.left) {
      x = sashRect.left + 20;
      handleY = sashRect.top + (sashRect.height * (1.0 - ratio));
    } else if (handleSide == OpenDirection.right) {
      x = sashRect.right - 20;
      handleY = sashRect.top + (sashRect.height * (1.0 - ratio));
    } else if (handleSide == OpenDirection.top) {
      handleY = sashRect.top + 22;
      x = sashRect.left + (sashRect.width * ratio);
    } else if (handleSide == OpenDirection.bottom) {
      handleY = sashRect.bottom - 22;
      x = sashRect.left + (sashRect.width * ratio);
    }

    final Paint basePaint = Paint()
      ..color = const Color(0xFFEEEEEE)
      ..style = PaintingStyle.fill;
    final Paint borderPaint = Paint()
      ..color = const Color(0xFF757575)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    canvas.save();
    canvas.translate(x, handleY);
    if (handleSide == OpenDirection.top || handleSide == OpenDirection.bottom) {
      canvas.rotate(-math.pi / 2);
    }
    final RRect basePlate = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset.zero, width: 18, height: 60),
      const Radius.circular(9),
    );
    canvas.drawRRect(basePlate, basePaint);
    canvas.drawRRect(basePlate, borderPaint);
    final RRect lever = RRect.fromRectAndRadius(
      Rect.fromLTRB(-7, -7, 7, 75),
      const Radius.circular(7),
    );
    canvas.drawRRect(lever, basePaint);
    canvas.drawRRect(lever, borderPaint);
    canvas.drawLine(
      const Offset(-3, 2),
      const Offset(-3, 70),
      Paint()
        ..color = Colors.white
        ..strokeWidth = 2.0,
    );
    canvas.restore();

    final Paint dimPaint = Paint()
      ..color = Colors.blue.shade700
      ..strokeWidth = 3.0
      ..style = PaintingStyle.stroke;
    final TextStyle textStyle = TextStyle(
      color: Colors.blue.shade900,
      fontSize: 80,
      fontWeight: FontWeight.bold,
      backgroundColor: Colors.white.withValues(alpha: 0.7),
    );

    if (handleSide == OpenDirection.left || handleSide == OpenDirection.right) {
      double dimX = (handleSide == OpenDirection.left) ? x + 25 : x - 25;
      double distance = sashRect.bottom - handleY;
      canvas.drawLine(
        Offset(dimX, sashRect.bottom),
        Offset(dimX, handleY),
        dimPaint,
      );
      canvas.drawLine(
        Offset(dimX - 4, sashRect.bottom),
        Offset(dimX + 4, sashRect.bottom),
        dimPaint,
      );
      canvas.drawLine(
        Offset(dimX - 4, handleY),
        Offset(dimX + 4, handleY),
        dimPaint,
      );
      final tp = TextPainter(
        text: TextSpan(text: '${distance.toInt()}', style: textStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(
        canvas,
        Offset(
          (handleSide == OpenDirection.left) ? dimX + 6 : dimX - tp.width - 6,
          handleY + (distance / 2) - (tp.height / 2),
        ),
      );
    } else {
      double dimY = (handleSide == OpenDirection.top)
          ? handleY + 25
          : handleY - 25;
      double distance = x - sashRect.left;
      canvas.drawLine(Offset(sashRect.left, dimY), Offset(x, dimY), dimPaint);
      canvas.drawLine(
        Offset(sashRect.left, dimY - 4),
        Offset(sashRect.left, dimY + 4),
        dimPaint,
      );
      canvas.drawLine(Offset(x, dimY - 4), Offset(x, dimY + 4), dimPaint);
      final tp = TextPainter(
        text: TextSpan(text: '${distance.toInt()}', style: textStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(
        canvas,
        Offset(
          sashRect.left + (distance / 2) - (tp.width / 2),
          (handleSide == OpenDirection.top) ? dimY + 4 : dimY - tp.height - 4,
        ),
      );
    }
  }

  void _drawHinges(
    Canvas canvas,
    Rect sashR,
    bool onRight,
    bool onLeft,
    bool onTop,
    bool onBottom,
    GlassSpecification glassInfo,
  ) {
    final frameH = sashR.height, frameW = sashR.width;
    int hingeCount = (frameH >= 2100 || frameW >= 2100)
        ? 4
        : (frameH >= 1000 || frameW >= 1000)
        ? 3
        : 2;
    if (glassInfo.structure == GlassStructure.double) hingeCount += 1;
    final paint = Paint()..color = const Color(0xFF424242);
    final shadow = Paint()..color = Colors.black45;

    void drawHinge(Offset center, bool horizontal) {
      final rect = horizontal
          ? Rect.fromCenter(center: center, width: 60, height: 12)
          : Rect.fromCenter(center: center, width: 12, height: 60);
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect.translate(1, 1), const Radius.circular(2)),
        shadow,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(2)),
        paint,
      );
    }

    if (onLeft || onRight) {
      double x = onRight ? sashR.right - 2 : sashR.left + 2;
      double startY = sashR.top + 100,
          step = (sashR.bottom - 100 - startY) / (hingeCount - 1);
      for (int i = 0; i < hingeCount; i++) {
        drawHinge(Offset(x, startY + (step * i)), false);
      }
    } else if (onTop || onBottom) {
      double y = onBottom ? sashR.bottom - 2 : sashR.top + 2;
      double startX = sashR.left + 100,
          step = (sashR.right - 100 - startX) / (hingeCount - 1);
      for (int i = 0; i < hingeCount; i++) {
        drawHinge(Offset(startX + (step * i), y), true);
      }
    }
  }

  void _drawWeepHoles(Canvas canvas, Rect outer, double t) {
    final whWidth = 35.0, whHeight = 6.0;
    final y = outer.bottom - (t / 2) - (whHeight / 2);
    final holePaint = Paint()
      ..color = const Color(0xFF111111)
      ..style = PaintingStyle.fill;
    canvas.drawRRect(
      RRect.fromRectXY(
        Rect.fromLTWH(outer.left + (outer.width * 0.2), y, whWidth, whHeight),
        3,
        3,
      ),
      holePaint,
    );
    canvas.drawRRect(
      RRect.fromRectXY(
        Rect.fromLTWH(
          outer.right - (outer.width * 0.2) - whWidth,
          y,
          whWidth,
          whHeight,
        ),
        3,
        3,
      ),
      holePaint,
    );
  }

  void _drawShutterSlatsAndTracks(
    Canvas canvas,
    double w,
    double h,
    double position,
  ) {
    const coulisseWidth = 25.0;

    // 🟢 تصحيح 3: استخدام _fc بدلاً من المتغير الثابت
    final coulissePaint = Paint()
      ..color = _fc[1]
      ..style = PaintingStyle.fill;
    final coulisseBorder = Paint()
      ..color = _fb
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    if (!model.removedShutterSides.contains('left')) {
      canvas.drawRect(Rect.fromLTWH(0, 0, coulisseWidth, h), coulissePaint);
      canvas.drawRect(Rect.fromLTWH(0, 0, coulisseWidth, h), coulisseBorder);
    }
    if (!model.removedShutterSides.contains('right')) {
      canvas.drawRect(
        Rect.fromLTWH(w - coulisseWidth, 0, coulisseWidth, h),
        coulissePaint,
      );
      canvas.drawRect(
        Rect.fromLTWH(w - coulisseWidth, 0, coulisseWidth, h),
        coulisseBorder,
      );
    }

    final visibleSlatsHeight = h * position;
    canvas.save();
    final leftClip = model.removedShutterSides.contains('left')
        ? 0.0
        : coulisseWidth;
    final rightClip = model.removedShutterSides.contains('right')
        ? w
        : w - coulisseWidth;
    canvas.clipRect(Rect.fromLTRB(leftClip, 0, rightClip, visibleSlatsHeight));
    for (double y = 0; y < visibleSlatsHeight; y += 20.0) {
      if (model.removedShutterSides.contains('bottom') && (y + 20.0) >= h) {
        break;
      }
      canvas.drawRect(
        Rect.fromLTRB(leftClip, y, rightClip, y + 20.0),
        Paint()
          ..color = _fc[0]
              .withValues(alpha: 0.95) // 🟢 تصحيح استخدام _fc
          ..style = PaintingStyle.fill,
      );
      canvas.drawLine(
        Offset(leftClip, y + 20.0),
        Offset(rightClip, y + 20.0),
        Paint()
          ..color = _fb
              .withValues(alpha: 0.4) // 🟢 تصحيح استخدام _fb
          ..strokeWidth = 1,
      );
    }
    canvas.restore();
  }

  void _drawShutterBox(Canvas canvas, double w, double boxSize) {
    final boxRect = Rect.fromLTWH(0, -boxSize, w, boxSize);
    canvas.drawRect(
      boxRect,
      Paint()
        ..color =
            _fc[1] // 🟢 تصحيح 2: استخدام _fc بدلاً من المتغير الثابت
        ..style = PaintingStyle.fill,
    );
    canvas.drawRect(
      boxRect,
      Paint()
        ..color =
            _fb // 🟢 تصحيح استخدام _fb
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  void _drawRealisticParclose(
    Canvas canvas,
    Rect rect,
    FrameColor color, {
    double? customThickness,
  }) {
    final double pT = customThickness ?? 8.0;
    if (rect.width <= pT * 2 || rect.height <= pT * 2) return;
    final Rect innerRect = rect.deflate(pT);
    canvas.drawPath(
      Path()
        ..fillType = PathFillType.evenOdd
        ..addRect(rect)
        ..addRect(innerRect),
      Paint()
        ..color = color.gradientColors[1]
        ..style = PaintingStyle.fill,
    );
    final Paint linePaint = Paint()
      ..color = color.borderColor.withValues(alpha: 0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    canvas.drawRect(innerRect, linePaint);
    canvas.drawLine(rect.topLeft, innerRect.topLeft, linePaint);
    canvas.drawLine(rect.topRight, innerRect.topRight, linePaint);
    canvas.drawLine(rect.bottomLeft, innerRect.bottomLeft, linePaint);
    canvas.drawLine(rect.bottomRight, innerRect.bottomRight, linePaint);
  }

  @override
  bool shouldRepaint(covariant WindowPainter oldDelegate) => true;
}

// =========================================================================
// 🟢 الرسام الخارجي لمساحة العمل (WorkspacePainter)
// =========================================================================
class WorkspacePainter extends CustomPainter {
  final List<PlacedFrame> frames;
  final Offset? startDrag;
  final Offset? endDrag;
  final bool isDrawingMode;
  final PlacedFrame? selectedFrame;

  WorkspacePainter({
    required this.frames,
    this.startDrag,
    this.endDrag,
    required this.isDrawingMode,
    this.selectedFrame,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (isDrawingMode && startDrag != null && endDrag != null) {
      final r = Rect.fromPoints(startDrag!, endDrag!);
      canvas.drawRect(
        r,
        Paint()
          ..color = Colors.blueAccent.withValues(alpha: 0.2)
          ..style = PaintingStyle.fill,
      );
      canvas.drawRect(
        r,
        Paint()
          ..color = Colors.blueAccent
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4.0,
      );
    }

    for (var pf in frames) {
      canvas.save();
      canvas.translate(pf.position.dx, pf.position.dy);

      final painter = WindowPainter(model: pf.model);
      painter.paint(canvas, Size(pf.model.width, pf.model.height));

      if (selectedFrame == pf) {
        final path = painter._buildOuterShapePath(
          pf.model.width,
          pf.model.height,
        );
        canvas.drawPath(
          path,
          Paint()
            ..color = Colors.green.shade600
            ..style = PaintingStyle.stroke
            ..strokeWidth = 4.0,
        );
      }

      canvas.restore();
      _paintDimensions(canvas, pf.model, pf.position);
    }
  }

  void _paintDimensions(Canvas canvas, WindowModel model, Offset pos) {
    double offsetDistTop = 100.0;
    if (model.hasShutter) offsetDistTop += 150.0;
    if (model.hasSideCovers && !model.removedShutterSides.contains('top')) {
      offsetDistTop += 60.0;
    }

    double offsetDistLeft = 100.0;
    if (model.hasSideCovers && !model.removedShutterSides.contains('left')) {
      offsetDistLeft += 60.0;
    }

    Offset wMid = Offset(pos.dx + model.width / 2, pos.dy - offsetDistTop);
    _drawText(canvas, '${model.width.toInt()} mm', wMid, isVertical: false);
    _drawArrow(
      canvas,
      Offset(pos.dx, pos.dy - offsetDistTop),
      Offset(pos.dx + model.width, pos.dy - offsetDistTop),
      isVerticalLine: false,
    );

    Offset hMid = Offset(
      pos.dx - offsetDistLeft - 30.0,
      pos.dy + model.height / 2,
    );
    _drawText(canvas, '${model.height.toInt()} mm', hMid, isVertical: true);
    _drawArrow(
      canvas,
      Offset(pos.dx - offsetDistLeft, pos.dy),
      Offset(pos.dx - offsetDistLeft, pos.dy + model.height),
      isVerticalLine: true,
    );
  }

  void _drawText(
    Canvas canvas,
    String text,
    Offset center, {
    bool isVertical = false,
  }) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(
          color: Colors.blue,
          fontWeight: FontWeight.bold,
          fontSize: 80,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    canvas.save();
    canvas.translate(center.dx, center.dy);
    if (isVertical) {
      canvas.rotate(-math.pi / 2);
    }
    final rect = Rect.fromCenter(
      center: Offset.zero,
      width: tp.width + 16,
      height: tp.height + 8,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(6)),
      Paint()..color = Colors.white.withValues(alpha: 0.95),
    );
    tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
    canvas.restore();
  }

  void _drawArrow(
    Canvas canvas,
    Offset p1,
    Offset p2, {
    bool isVerticalLine = false,
  }) {
    final p = Paint()
      ..color = Colors.blueGrey
      ..strokeWidth = 4.0;
    canvas.drawLine(p1, p2, p);
    final Paint tickPaint = Paint()
      ..color = Colors.blueGrey
      ..strokeWidth = 4.0
      ..strokeCap = StrokeCap.round;
    double tickSize = 15.0;

    if (isVerticalLine) {
      canvas.drawLine(
        Offset(p1.dx - tickSize, p1.dy),
        Offset(p1.dx + tickSize, p1.dy),
        tickPaint,
      );
      canvas.drawLine(
        Offset(p2.dx - tickSize, p2.dy),
        Offset(p2.dx + tickSize, p2.dy),
        tickPaint,
      );
    } else {
      canvas.drawLine(
        Offset(p1.dx, p1.dy - tickSize),
        Offset(p1.dx, p1.dy + tickSize),
        tickPaint,
      );
      canvas.drawLine(
        Offset(p2.dx, p2.dy - tickSize),
        Offset(p2.dx, p2.dy + tickSize),
        tickPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
