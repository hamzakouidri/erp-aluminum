// Force compile sync trigger
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:database_data/Commande/texture_cache.dart';
// Force compile sync trigger
import 'package:flutter/material.dart';

import 'package:database_data/Commande/Systeme/model.dart';

class WindowPainter extends CustomPainter {
  final WindowModel model;
  final bool? overrideIsInternalView;

  // Optimized wood rendering states computed once per repaint to avoid lag
  late final bool _isWood;
  late final ui.Shader? _woodShader;
  late final ColorFilter? _woodColorFilter;

  WindowPainter({required this.model, this.overrideIsInternalView})
    : super(repaint: model) {
    _initWoodShader();
  }

  void _initWoodShader() {
    final dbColor = model.selectedDbColor;
    if (dbColor == null) {
      _isWood = false;
      _woodShader = null;
      _woodColorFilter = null;
      return;
    }

    final name = dbColor['name'].toString().toLowerCase();

    // Clean name for uniform checking
    final cleanName = name
        .replaceAll('أ', 'ا')
        .replaceAll('إ', 'ا')
        .replaceAll('آ', 'ا')
        .replaceAll('ى', 'ي')
        .replaceAll('ة', 'ه');

    _isWood =
        cleanName.contains('خشب') ||
        cleanName.contains('wood') ||
        cleanName.contains('bois') ||
        cleanName.contains('desert') ||

        cleanName.contains('oak') ||

        cleanName.contains('faux') ||

        cleanName.contains('antique') ||
        cleanName.contains('انتيك') ||
        cleanName.contains('onteak') ||
        cleanName.contains('fonce') ||
        cleanName.contains('foncé') ||
        cleanName.contains('dark');

    if (!_isWood) {
      _woodShader = null;
      _woodColorFilter = null;
      return;
    }

    // Determine texture and shader to use (No color filters applied to preserve raw look)
    _woodColorFilter = null;

    final bool isOakTexture =
        cleanName.contains('d0') ||
        cleanName.contains('di zero') ||
        cleanName.contains('desert') ||
        cleanName.contains('╪»┘è╪▓╪▒');

    final bool isAntiqueTexture =
        cleanName.contains('antique') ||
        cleanName.contains('انتيك') ||
        cleanName.contains('onteak') ||
        cleanName.contains('╪º┘å╪¬┘è┘â');

    final bool isGreyTexture =
        cleanName.contains('grey') ||
        cleanName.contains('gray') ||
        cleanName.contains('رمادي') ||
        cleanName.contains('Gris 7024');

    if (isOakTexture) {
      _woodShader = TextureCache.getShaderD0();
    } else if (isAntiqueTexture) {
      _woodShader = TextureCache.getShaderAntique();
    } else if (isGreyTexture) {
      _woodShader = TextureCache.getShaderGrey();
    } else {
      // Default wood (الخشبي) and dark wood use the raw mahogany texture (wood_texture.png)
      _woodShader = TextureCache.getShaderMahogany();
    }
  }

  bool get _isSlantedOrArched =>
      model.archHeight > 0 ||
      model.topSlantLeftY != 0 ||
      model.topSlantRightY != 0 ||
      model.bottomSlantLeftY != 0 ||
      model.bottomSlantRightY != 0;

  double get _topOffset =>
      (model.hasShutter && !_isSlantedOrArched && !model.isCaissonTunnel)
      ? model.shutterBoxHeight
      : 0.0;

  @override
  void paint(Canvas canvas, Size size) {
    final w = model.width;
    final h = model.height;

    // 🟢 الإطار يأخذ عرضه من القاعدة مباشرة
    final t = model.profileThickness;

    final double topOffset = _topOffset;

    // Draw brick wall and tunnel box around the window opening
    final double wallLeft = 500.0;
    final double wallRight = 500.0;
    final double wallTop = model.hasShutter
        ? (model.shutterBoxHeight + 150.0)
        : 150.0;
    final double wallBottom = model.showBottomWall ? 200.0 : 0.0;

    if (model.showWall) {
      final wallRect = Rect.fromLTRB(
        -wallLeft,
        topOffset - wallTop,
        w + wallRight,
        h + wallBottom,
      );
      final openingRect = Rect.fromLTRB(0, topOffset, w, h);

      // Create the wall path with the window opening excluded
      final wallPath = Path()..addRect(wallRect);
      final openingPath = Path()..addRect(openingRect);
      final combinedWallPath = Path.combine(
        PathOperation.difference,
        wallPath,
        openingPath,
      );

      canvas.save();
      canvas.clipPath(combinedWallPath);

      // Fill with brick background color
      final bool isGreyWall = model.wallColor == 'grey';
      final brickBgPaint = Paint()
        ..color = isGreyWall
            ? const Color(0xFF8A939E) // RAL 9007 metallic/grey brick color
            : const Color(0xFFC85A3F); // Terracotta brick red
      canvas.drawRect(wallRect, brickBgPaint);

      // Draw mortar lines
      final mortarPaint = Paint()
        ..color = isGreyWall
            ? const Color(0xFF4A5568) // dark slate grey mortar joints for grey bricks
            : const Color(0xFFE5DCD5) // mortar grey/beige for red bricks
        ..strokeWidth = 2.0
        ..style = PaintingStyle.stroke;

      final double brickH = 24.0;
      final double brickW = 55.0;

      // Draw horizontal mortar lines
      for (double y = topOffset - wallTop; y <= h + wallBottom; y += brickH) {
        canvas.drawLine(
          Offset(-wallLeft, y),
          Offset(w + wallRight, y),
          mortarPaint,
        );
      }

      // Draw vertical mortar lines (staggered row by row)
      int rowIndex = 0;
      for (double y = topOffset - wallTop; y < h + wallBottom; y += brickH) {
        final double offset = (rowIndex % 2 == 0) ? 0.0 : brickW / 2.0;
        for (
          double x = -wallLeft - brickW;
          x <= w + wallRight + brickW;
          x += brickW
        ) {
          final double vx = x + offset;
          canvas.drawLine(Offset(vx, y), Offset(vx, y + brickH), mortarPaint);
        }
        rowIndex++;
      }

      canvas.restore();

      // Draw Tunnel Box if isCaissonTunnel is true
      if (model.hasShutter && model.isCaissonTunnel && !_isSlantedOrArched) {
        final tunnelBoxPaint = Paint()
          ..color =
              const Color(
                0xFF90CDF4,
              ) // beautiful light blue insulation foam color
          ..style = PaintingStyle.fill;
        final tunnelBoxBorder = Paint()
          ..color =
              const Color(0xFF4299E1) // darker blue border
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5;

        final double overhang = 35.0; // box extends into left/right masonry
        final rect = Rect.fromLTRB(
          -overhang,
          topOffset - model.shutterBoxHeight,
          w + overhang,
          topOffset,
        );
        canvas.drawRect(rect, tunnelBoxPaint);
        canvas.drawRect(rect, tunnelBoxBorder);

        // Draw diagonal texture lines
        final patternPaint = Paint()
          ..color = const Color(0xFF63B3ED).withValues(alpha: 0.5)
          ..strokeWidth = 1.0;
        for (
          double x = -overhang - model.shutterBoxHeight;
          x < w + overhang;
          x += 15.0
        ) {
          canvas.drawLine(
            Offset(x, topOffset - model.shutterBoxHeight),
            Offset(x + model.shutterBoxHeight, topOffset),
            patternPaint,
          );
        }

        // Draw workshop name centered on the tunnel box
        final String nameToDraw = model.workshopName ?? 'ورشة الألمنيوم';
        final textStyle = const TextStyle(
          color: Colors.black,
          fontSize: 70.0,
          fontWeight: FontWeight.bold,
        );
        final textPainter = TextPainter(
          text: TextSpan(text: nameToDraw, style: textStyle),
          textDirection: TextDirection.rtl,
        )..layout();
        final double centerX = w / 2;
        final double centerY = topOffset - model.shutterBoxHeight / 2;
        textPainter.paint(
          canvas,
          Offset(
            centerX - textPainter.width / 2,
            centerY - textPainter.height / 2,
          ),
        );
      }
    }

    final innerPath = _buildInnerShapePath(w, h, t, topOffset);

    canvas.save();
    canvas.clipPath(innerPath);
    for (final zone in model.zones) {
      _drawZoneBackground(canvas, zone, h, t);
    }
    canvas.restore();

    final bool isSlantedOrArched =
        model.archHeight > 0 ||
        model.topSlantLeftY != 0 ||
        model.topSlantRightY != 0 ||
        model.bottomSlantLeftY != 0 ||
        model.bottomSlantRightY != 0;

    if ((overrideIsInternalView ?? model.isInternalView)) {
      if (model.hasShutter && !isSlantedOrArched) {
        _drawShutterSlatsAndTracks(
          canvas,
          w,
          h,
          model.shutterPosition,
          model.isCaissonTunnel ? 0.0 : model.shutterBoxHeight,
        );
      }

      if (!model.isShutterOnly) {
        canvas.save();
        canvas.clipPath(innerPath);
        _drawMullions(canvas, w, h, t);
        canvas.restore();

        _drawOuterFrames(canvas, w, h, t, topOffset);

        if (model.hasFramePlintheBottom) {
          double plintheHeight = model.plintheHeight;
          double yBottom = h;
          
          final plintheRect = Rect.fromLTRB(
            t,
            yBottom - plintheHeight,
            w - t,
            yBottom,
          );
          
          final pPaint = Paint();
          if (_isWoodColor() && TextureCache.woodTexture != null) {
            _applyWoodShader(pPaint, plintheRect);
          } else {
            pPaint.color = _fc[1];
          }
          canvas.drawRect(plintheRect, pPaint);
          
          final bPaint = Paint()
            ..color = _fb
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.0;
          canvas.drawRect(plintheRect, bPaint);
        }

        // 🟢 الغطاء الجانبي يأخذ عرضه من القاعدة (يرسم فقط إذا لم يكن الإطار مدمجاً)
            {
          final _frameForCover = model.getSectionByType('frame');
          final bool _hasBuiltInCoverBand = model.isIntegratedFrame && model.isSideCoverAllowed &&
              _frameForCover != null && _frameForCover.couvreJointWidth > 0;
          if (_hasBuiltInCoverBand || (model.hasSideCovers && model.isSideCoverAllowed && !model.isIntegratedFrame)) {
            _drawSideCovers(canvas, w, h, 0.0, model.sideCoverWidth);
          }
        }

        canvas.save();
        canvas.clipPath(innerPath);
        for (final zone in model.zones) {
          _drawZoneContent(canvas, zone, h, t);
          if (zone.content == ZoneContent.singleSash ||
              zone.content == ZoneContent.doubleSash) {
            if (zone.content == ZoneContent.singleSash &&
                zone.openDirection != null &&
                zone.useOctoHandle != true) {
              _drawWindowDrawHandle(
                canvas,
                _getEffectiveZoneRect(zone.boundary, h, t),
                zone.openDirection!,
                zone.handlePositionRatio ?? 0.5,
                t: t,
                topOffset: topOffset,
                isTopBound: _isTopZone(zone),
                zone: zone,
              );
            }
          }
        }
        canvas.restore();
        // Draw Octo handles OUTSIDE the clip so the keeper (on frame side) is visible
        for (final zone in model.zones) {
          if (zone.content == ZoneContent.singleSash &&
              zone.openDirection != null &&
              zone.useOctoHandle == true) {
            _drawWindowDrawHandle(
              canvas,
              _getEffectiveZoneRect(zone.boundary, h, t),
              zone.openDirection!,
              zone.handlePositionRatio ?? 0.5,
              t: t,
              topOffset: topOffset,
              isTopBound: _isTopZone(zone),
              zone: zone,
            );
          }
        }
      }

      if (model.hasShutter && !isSlantedOrArched) {
        if (model.isCaissonTunnel) {
          if (model.shutterMechanism == 'حزام' ||
              model.shutterMechanism == 'منايفال' ||
              model.shutterMechanism == 'مانيفال' ||
              model.shutterMechanism.toLowerCase().contains('manivelle')) {
            canvas.save();
            canvas.translate(0, -model.shutterBoxHeight);
            _drawShutterBox(
              canvas,
              w,
              model.shutterBoxHeight,
              h,
              drawOnlyManualControls: true,
            );
            canvas.restore();
          }
        } else {
          _drawShutterBox(canvas, w, topOffset, h);
        }
      }
    } else {
      if (!model.isShutterOnly) {
        _drawOuterFrames(canvas, w, h, t, topOffset);

        // 🟢 الغطاء الجانبي يأخذ عرضه من القاعدة (يرسم في الوجه الخارجي فقط في حال عدم وجود جدار ولم يكن الإطار مدمجاً)
            {
          final _frameForCover2 = model.getSectionByType('frame');
          final bool _hasBuiltInCoverBand2 = model.isIntegratedFrame && model.isSideCoverAllowed &&
              _frameForCover2 != null && _frameForCover2.couvreJointWidth > 0;
          if ((_hasBuiltInCoverBand2 || (model.hasSideCovers && model.isSideCoverAllowed && !model.isIntegratedFrame)) &&
              !model.showWall) {
            _drawSideCovers(canvas, w, h, 0.0, model.sideCoverWidth);
          }
        }
      }

      if (!model.isShutterOnly) {
        canvas.save();
        canvas.clipPath(innerPath);
        _drawMullions(canvas, w, h, t);
        canvas.restore();

        if (model.hasBottomFrame) {
          _drawWeepHolesMultiple(canvas, w, h, t, topOffset);
        }

        canvas.save();
        canvas.clipPath(innerPath);
        for (final zone in model.zones) {
          _drawZoneContent(canvas, zone, h, t);
          if (zone.content == ZoneContent.singleSash ||
              zone.content == ZoneContent.doubleSash) {
            if (zone.content == ZoneContent.singleSash &&
                zone.openDirection != null &&
                zone.useOctoHandle != true) {
              OpenDirection handleSide = zone.openDirection!;
              if (handleSide == OpenDirection.left) {
                handleSide = OpenDirection.right;
              } else if (handleSide == OpenDirection.right) {
                handleSide = OpenDirection.left;
              }

              _drawWindowDrawHandle(
                canvas,
                _getEffectiveZoneRect(zone.boundary, h, t),
                handleSide,
                zone.handlePositionRatio ?? 0.5,
                t: t,
                topOffset: topOffset,
                isTopBound: _isTopZone(zone),
                zone: zone,
              );
            }
          }
        }
        canvas.restore();
        // Draw Octo handles OUTSIDE the clip so the keeper (on frame side) is visible
        for (final zone in model.zones) {
          if (zone.content == ZoneContent.singleSash &&
              zone.openDirection != null &&
              zone.useOctoHandle == true) {
            OpenDirection handleSide = zone.openDirection!;
            if (handleSide == OpenDirection.left) {
              handleSide = OpenDirection.right;
            } else if (handleSide == OpenDirection.right) {
              handleSide = OpenDirection.left;
            }
            _drawWindowDrawHandle(
              canvas,
              _getEffectiveZoneRect(zone.boundary, h, t),
              handleSide,
              zone.handlePositionRatio ?? 0.5,
              t: t,
              topOffset: topOffset,
              isTopBound: _isTopZone(zone),
              zone: zone,
            );
          }
        }
      }

      if (model.hasShutter && !isSlantedOrArched) {
        _drawShutterSlatsAndTracks(
          canvas,
          w,
          h,
          model.shutterPosition,
          model.isCaissonTunnel ? 0.0 : model.shutterBoxHeight,
        );
        if (model.isCaissonTunnel) {
          if (
              model.shutterMechanism == 'منايفال' ||
              model.shutterMechanism == 'مانيفال' ||
              model.shutterMechanism.toLowerCase().contains('manivelle')) {
            canvas.save();
            canvas.translate(0, -model.shutterBoxHeight);
            _drawShutterBox(
              canvas,
              w,
              model.shutterBoxHeight,
              h,
              drawOnlyManualControls: true,
            );
            canvas.restore();
          }
        } else {
          _drawShutterBox(canvas, w, topOffset, h);
        }
      }
    }

    for (final zone in model.zones) {
      if (model.selectedZone != null && model.selectedZone!.id == zone.id) {
        final r = zone.boundary;
        bool highlightEntireZone =
            model.activeSubZone == 'all' ||
            zone.content != ZoneContent.doubleSash;
        if (highlightEntireZone) {
          final zonePath = _buildGlassLayerPath(
            r,
            t,
            topOffset,
            _isTopZone(zone),
          );
          canvas.drawPath(
            zonePath,
            Paint()
              ..color = Colors.green.shade700.withValues(alpha: 0.35)
              ..style = PaintingStyle.fill,
          );
        } else {
          final sep = 4.0;
          final isInternal = overrideIsInternalView ?? model.isInternalView;
          final double effectiveRatio = isInternal ? zone.doubleSashRatio : (1.0 - zone.doubleSashRatio);
          final midX = r.left + r.width * effectiveRatio;
          Rect sashR;
          if (model.activeSubZone != null &&
              model.activeSubZone!.startsWith('left')) {
            sashR = Rect.fromLTRB(r.left, r.top, midX - sep / 2, r.bottom);
          } else {
            sashR = Rect.fromLTRB(midX + sep / 2, r.top, r.right, r.bottom);
          }
          final sashT =
              zone.sashThickness ??
              model.getSectionThickness('sash', fallback: 45.0);
          final glassR = _getSafeGlassRect(sashR, sashT, hasSashPlintheBottom: zone.hasSashPlintheBottom);
          final Path highlightPath = Path()
            ..fillType = PathFillType.evenOdd
            ..addPath(
              _buildGlassLayerPath(sashR, t, topOffset, _isTopZone(zone)),
              Offset.zero,
            )
            ..addPath(
              _buildGlassLayerPath(glassR, t, topOffset, _isTopZone(zone)),
              Offset.zero,
            );
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

    if (w > 0) {
      if (model.topSlantLeftY != model.topSlantRightY) {
        double angleRad = math.atan(
          (model.topSlantRightY - model.topSlantLeftY) / w,
        );
        double angleDeg = (angleRad * 180 / math.pi).abs();
        bool rightIsLower = model.topSlantRightY > model.topSlantLeftY;
        double leftAngle = rightIsLower ? (90.0 + angleDeg) : (90.0 - angleDeg);
        double rightAngle = rightIsLower
            ? (90.0 - angleDeg)
            : (90.0 + angleDeg);

        _drawAngleBadge(
          canvas,
          Offset(40, topOffset + model.topSlantLeftY + 30),
          leftAngle,
        );
        _drawAngleBadge(
          canvas,
          Offset(w - 40, topOffset + model.topSlantRightY + 30),
          rightAngle,
        );
      }
      if (model.bottomSlantLeftY != model.bottomSlantRightY) {
        double angleRad = math.atan(
          (model.bottomSlantRightY - model.bottomSlantLeftY) / w,
        );
        double angleDeg = (angleRad * 180 / math.pi).abs();
        bool rightIsHigher = model.bottomSlantRightY > model.bottomSlantLeftY;
        double leftAngle = rightIsHigher
            ? (90.0 - angleDeg)
            : (90.0 + angleDeg);
        double rightAngle = rightIsHigher
            ? (90.0 + angleDeg)
            : (90.0 - angleDeg);

        _drawAngleBadge(
          canvas,
          Offset(40, h - model.bottomSlantLeftY - 30),
          leftAngle,
        );
        _drawAngleBadge(
          canvas,
          Offset(w - 40, h - model.bottomSlantRightY - 30),
          rightAngle,
        );
      }
    }
  }

  List<Color> get _fc =>
      getEffectiveGradientColors(model.frameColor, model.selectedDbColor);

  Color get _fb =>
      getEffectiveBorderColor(model.frameColor, model.selectedDbColor);

  Color get _mc => Color.lerp(_fc.last, Colors.black, 0.4)!;

  bool _isWoodColor([Map<String, dynamic>? dbColor]) {
    // If checking specifically for a different color, run standard check
    if (dbColor != null) {
      final name = dbColor['name'].toString().toLowerCase();

      // Clean name for uniform checking
      final cleanName = name
          .replaceAll('أ', 'ا')
          .replaceAll('إ', 'ا')
          .replaceAll('آ', 'ا')
          .replaceAll('ى', 'ي')
          .replaceAll('ة', 'ه');

      return cleanName.contains('خشب') ||
          cleanName.contains('wood') ||
          cleanName.contains('bois') ||
          cleanName.contains('╪«╪┤╪¿') ||
          cleanName.contains('desert') ||
          cleanName.contains('ديزر') ||
          cleanName.contains('ديزير') ||
          cleanName.contains('oak') ||
          cleanName.contains('اوك') ||
          cleanName.contains('chene') ||
          cleanName.contains('chêne') ||
          cleanName.contains('noyer') ||
          cleanName.contains('acajou') ||
          cleanName.contains('شين') ||
          cleanName.contains('نويا') ||
          cleanName.contains('اكاجو') ||
          cleanName.contains('بوا') ||
          cleanName.contains('faux') ||
          cleanName.contains('فو') ||
          cleanName.contains('antique') ||
          cleanName.contains('انتيك') ||
          cleanName.contains('onteak') ||
          cleanName.contains('fonce') ||
          cleanName.contains('foncé') ||
          cleanName.contains('dark') ||
          cleanName.contains('داكن') ||
          cleanName.contains('d0') ||
          cleanName.contains('دي زيرو') ||
          cleanName.contains('بلوط') ||
          cleanName.contains('balout') ||
          cleanName.contains('di zero');
    }
    return _isWood;
  }

  void _applyWoodShader(
    Paint paint,
    Rect r, {
    List<Color>? gradientColors,
    Map<String, dynamic>? dbColor,
  }) {
    final effectiveDbColor = dbColor ?? model.selectedDbColor;
    if (effectiveDbColor == null) {
      paint.shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: gradientColors ?? _fc,
      ).createShader(r);
      paint.colorFilter = null;
      return;
    }

    // Fast-path: Use precompiled and cached shaders from constructor to prevent garbage collection frame drops
    if (effectiveDbColor['name'] == model.selectedDbColor?['name']) {
      if (_isWood && _woodShader != null) {
        paint.shader = _woodShader;
        paint.colorFilter = _woodColorFilter;
        return;
      }
    }

    // Custom color fallback
    paint.shader = _fsGlobal(
      r,
      gradientColors: gradientColors,
      dbColor: effectiveDbColor,
    );
    paint.colorFilter = null;
  }

  Paint _buildPaint(
    Rect r, {
    List<Color>? gradientColors,
    Map<String, dynamic>? dbColor,
  }) {
    final paint = Paint();
    _applyWoodShader(
      paint,
      r,
      gradientColors: gradientColors,
      dbColor: dbColor,
    );
    return paint;
  }

  Shader _fsGlobal(
    Rect r, {
    List<Color>? gradientColors,
    Map<String, dynamic>? dbColor,
  }) {
    final effectiveDbColor = dbColor ?? model.selectedDbColor;
    if (effectiveDbColor == null) {
      if (_isWood && _woodShader != null) {
        return _woodShader;
      }
    } else {
      if (effectiveDbColor['name'] == model.selectedDbColor?['name']) {
        if (_isWood && _woodShader != null) {
          return _woodShader;
        }
      }
      if (_isWoodColor(effectiveDbColor)) {
        final name = (effectiveDbColor['name'] ?? '').toString().toLowerCase();
        final cleanName = name
            .replaceAll('أ', 'ا')
            .replaceAll('إ', 'ا')
            .replaceAll('آ', 'ا')
            .replaceAll('ى', 'ي')
            .replaceAll('ة', 'ه');

        final bool isOakTexture =
            cleanName.contains('d0') ||
            cleanName.contains('oak') ||
            cleanName.contains('اوك') ||
            cleanName.contains('شين') ||
            cleanName.contains('chene') ||
            cleanName.contains('chêne') ||
            cleanName.contains('بلوط') ||
            cleanName.contains('دي زيرو') ||
            cleanName.contains('di zero') ||
            cleanName.contains('desert') ||
            cleanName.contains('ديزر') ||
            cleanName.contains('ديزير') ||
            cleanName.contains('╪»┘è╪▓╪▒');

        final bool isAntiqueTexture =
            cleanName.contains('antique') ||
            cleanName.contains('انتيك') ||
            cleanName.contains('onteak') ||
            cleanName.contains('╪º┘å╪¬┘è┘â');

        final bool isGreyTexture =
            cleanName.contains('grey') ||
            cleanName.contains('gray') ||
            cleanName.contains('رمادي') ||
            cleanName.contains('gris');

        final ui.Image? texture = isOakTexture
            ? TextureCache.woodTextureD0
            : (isAntiqueTexture
                  ? TextureCache.woodTextureAntique
                  : (isGreyTexture
                        ? TextureCache.woodTextureGrey
                              : (TextureCache.woodTexture ??
                                    TextureCache.woodTextureD0)));

        if (texture != null) {
          return ui.ImageShader(
            texture,
            ui.TileMode.repeated,
            ui.TileMode.repeated,
            Matrix4.identity().scaled(0.5).storage,
          );
        }
      }
    }
    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: gradientColors ?? _fc,
    ).createShader(r);
  }

  void _drawGlassLayer(
    Canvas canvas,
    Rect r,
    GlassSpecification spec,
    GlassColor color,
    GlassFinish finish,
    double t,
    double topOffset,
    bool isTopBound, {
    bool isInsideSash = false,
    double? sashTop,
    double? topW,
  }) {
    final structure = spec.structure;
    final colorP = spec.colorP;
    final glassPath = _buildGlassLayerPath(
      r,
      t,
      topOffset,
      isTopBound,
      isInsideSash: isInsideSash,
      sashTop: sashTop,
      topW: topW,
    );
    canvas.save();
    canvas.clipPath(glassPath);

    final pColor = spec.panneauColor;
    final bool isPanneauWood = pColor != null && _isWoodColor({'name': pColor});
    final Paint fillPaint = Paint();
    if (structure == GlassStructure.closed && isPanneauWood && TextureCache.woodTexture != null) {
      final woodColors = getEffectiveGradientColors(FrameColor.brown, {'name': pColor});
      _applyWoodShader(fillPaint, r, gradientColors: woodColors, dbColor: {'name': pColor});
    } else {
      fillPaint.shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: _getColorsForLayer(structure, color, finish, colorP, pColor),
      ).createShader(r);
    }
    canvas.drawRect(r, fillPaint);

    // 🟢 تعديل البارداج هنا: إزالة شكل الطوب المتقاطع ورسم خطوط أفقية متوازية وصافية
    if (finish == GlassFinish.bardage) {
      final double slatHeight = 22.0; // المسافة بين الشرائح

      final Paint darkPaint = Paint()
        ..color = Colors.black.withValues(alpha: 0.2)
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke;

      final Paint lightPaint = Paint()
        ..color = Colors.white.withValues(alpha: 0.3)
        ..strokeWidth = 1.0
        ..style = PaintingStyle.stroke;

      for (double y = r.top + slatHeight; y <= r.bottom; y += slatHeight) {
        canvas.drawLine(Offset(r.left, y), Offset(r.right, y), darkPaint);
        canvas.drawLine(
          Offset(r.left, y + 1.0),
          Offset(r.right, y + 1.0),
          lightPaint,
        );
      }
    }

    if ((structure != GlassStructure.closed &&
            (finish == GlassFinish.clair || finish == GlassFinish.stopSol)) ||
        finish == GlassFinish.bardage) {
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

    // 🟢 رسم ديكور الزجاج المزدوج (ورود الزجاج)
    if (spec.structure == GlassStructure.double) {
      Color resolveDecorColor(String colorStr) {
        final clean = colorStr.trim().toLowerCase();
        if (clean == 'white' || clean == 'أبيض' || clean == 'blanc') {
          return Colors.white;
        }
        if (clean == 'gold' || clean == 'ذهبي' || clean == 'or') {
          return const Color(0xFFD4AF37);
        }
        if (clean == 'silver' || clean == 'فضي' || clean == 'argent') {
          return const Color(0xFFE0E0E0);
        }
        if (clean == 'grey' || clean == 'gray' || clean == 'رمادي' || clean == 'gris') {
          return const Color(0xFF9E9E9E);
        }
        if (clean == 'black' || clean == 'أسود' || clean == 'noir') {
          return const Color(0xFF212121);
        }
        if (clean == 'bronze' || clean == 'برونزي') {
          return const Color(0xFFCD7F32);
        }
        if (clean == 'brown' || clean == 'بني' || clean == 'marron') {
          return const Color(0xFF8D6E63);
        }
        if (clean.startsWith('#')) {
          try {
            final hex = clean.substring(1);
            if (hex.length == 6) {
              return Color(int.parse('FF$hex', radix: 16));
            } else if (hex.length == 8) {
              return Color(int.parse(hex, radix: 16));
            }
          } catch (_) {}
        }
        return Colors.white;
      }

      final String dColorStr = spec.decorColor;
      final Color dColor = resolveDecorColor(dColorStr);

      final Paint decorPaint = Paint()
        ..color = dColor
        ..strokeWidth = (spec.decorThickness == 10.0 ? 3.5 : 2.0) * 2.0
        ..style = PaintingStyle.stroke;

      final isGold = dColorStr.toLowerCase().contains('gold') || 
                     dColorStr.toLowerCase().contains('ذهبي') || 
                     dColorStr.toLowerCase().contains('or');
      if (isGold) {
        decorPaint.shader = const LinearGradient(
          colors: [
            Color(0xFFB78628),
            Color(0xFFFCCE46),
            Color(0xFFC69320),
            Color(0xFFFCCE46),
            Color(0xFF916012),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ).createShader(r);
      }

      // Draw horizontal decoration lines
      List<double> hPos = [];
      if (spec.decorHPositions.isNotEmpty) {
        hPos = List.from(spec.decorHPositions);
      } else if (spec.decorH > 0) {
        double step = 1.0 / (spec.decorH + 1);
        for (int i = 1; i <= spec.decorH; i++) {
          hPos.add(step * i);
        }
      }
      for (double ratio in hPos) {
        double y = r.top + r.height * ratio;
        canvas.drawLine(Offset(r.left, y), Offset(r.right, y), decorPaint);
      }

      // Draw vertical decoration lines
      List<double> vPos = [];
      if (spec.decorVPositions.isNotEmpty) {
        vPos = List.from(spec.decorVPositions);
      } else if (spec.decorV > 0) {
        double step = 1.0 / (spec.decorV + 1);
        for (int i = 1; i <= spec.decorV; i++) {
          vPos.add(step * i);
        }
      }
      for (double ratio in vPos) {
        double x = r.left + r.width * ratio;
        canvas.drawLine(Offset(x, r.top), Offset(x, r.bottom), decorPaint);
      }

      // Resolve Rosette name
      String rosetteName = '';
      if (spec.decorRosetteId != null) {
        final match = model.allGlassCache.firstWhere(
          (g) => (g['id'] as num?)?.toInt() == spec.decorRosetteId,
          orElse: () => {},
        );
        if (match.isNotEmpty) {
          rosetteName = match['name']?.toString() ?? '';
        }
      }

      // Draw rosettes (flower shapes) at each intersection
      if (spec.hasRosettes && hPos.isNotEmpty && vPos.isNotEmpty) {
        final double baseR = (spec.decorThickness == 10.0 ? 12.0 : 8.0) * 1.5;
        final String nameClean = rosetteName.toLowerCase().trim();

        for (double hr in hPos) {
          double y = r.top + r.height * hr;
          for (double vr in vPos) {
            double x = r.left + r.width * vr;
            Offset center = Offset(x, y);

            final Paint fillPaint = Paint()..style = PaintingStyle.fill;
            final Paint strokePaint = Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.5;

            if (isGold) {
              final Rect gradRect = Rect.fromCenter(center: center, width: baseR * 3, height: baseR * 3);
              final Shader goldenShader = const LinearGradient(
                colors: [
                  Color(0xFFB78628),
                  Color(0xFFFCCE46),
                  Color(0xFFC69320),
                  Color(0xFFFCCE46),
                  Color(0xFF916012),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ).createShader(gradRect);

              fillPaint.shader = goldenShader;
              strokePaint.shader = goldenShader;
            } else {
              fillPaint.color = dColor;
              strokePaint.color = dColor;
            }

            final Paint outlinePaint = Paint()
              ..color = Colors.black.withValues(alpha: 0.3)
              ..strokeWidth = 0.6
              ..style = PaintingStyle.stroke;

            // Determine rosette type based on rosetteShape property, with name-based keywords as fallback
            bool isRosette2 = spec.rosetteShape == 2 || nameClean.contains('curve') || nameClean.contains('courbe') || nameClean.contains('منحني') || nameClean.contains('2');
            bool isRosette3 = spec.rosetteShape == 3 || nameClean.contains('baroque') || nameClean.contains('oval') || nameClean.contains('ovale') || nameClean.contains('بيضاوي') || nameClean.contains('زخرفة') || nameClean.contains('3');
            bool isRosette4 = spec.rosetteShape == 4 || nameClean.contains('solid') || nameClean.contains('plein') || nameClean.contains('ممتلئ') || nameClean.contains('diamond') || nameClean.contains('losange') || nameClean.contains('معين') || nameClean.contains('4');
            bool isRosette1 = spec.rosetteShape == 1 || (!isRosette2 && !isRosette3 && !isRosette4);

            if (isRosette1) {
              // 🌸 Type 1: Star / Cross Flower (Image 1)
              final Path starPath = Path();
              starPath.moveTo(center.dx, center.dy - baseR * 1.5);
              starPath.quadraticBezierTo(center.dx + baseR * 0.25, center.dy - baseR * 0.25, center.dx + baseR * 1.5, center.dy);
              starPath.quadraticBezierTo(center.dx + baseR * 0.25, center.dy + baseR * 0.25, center.dx, center.dy + baseR * 1.5);
              starPath.quadraticBezierTo(center.dx - baseR * 0.25, center.dy + baseR * 0.25, center.dx - baseR * 1.5, center.dy);
              starPath.quadraticBezierTo(center.dx - baseR * 0.25, center.dy - baseR * 0.25, center.dx, center.dy - baseR * 1.5);
              starPath.close();

              canvas.drawPath(starPath, strokePaint);
              canvas.drawPath(starPath, outlinePaint);

              // Inner diamond
              final Path innerPath = Path();
              innerPath.moveTo(center.dx, center.dy - baseR * 0.8);
              innerPath.lineTo(center.dx + baseR * 0.8, center.dy);
              innerPath.lineTo(center.dx, center.dy + baseR * 0.8);
              innerPath.lineTo(center.dx - baseR * 0.8, center.dy);
              innerPath.close();

              canvas.drawPath(innerPath, fillPaint);
              canvas.drawPath(innerPath, outlinePaint);

              canvas.drawCircle(center, baseR * 0.3, strokePaint);
            } else if (isRosette2) {
              // 🌸 Type 2: Curved Center Flare (Image 2)
              final Path curvePath = Path();
              curvePath.moveTo(center.dx, center.dy - baseR * 1.2);
              curvePath.quadraticBezierTo(center.dx, center.dy, center.dx + baseR * 1.2, center.dy);
              curvePath.quadraticBezierTo(center.dx, center.dy, center.dx, center.dy + baseR * 1.2);
              curvePath.quadraticBezierTo(center.dx, center.dy, center.dx - baseR * 1.2, center.dy);
              curvePath.quadraticBezierTo(center.dx, center.dy, center.dx, center.dy - baseR * 1.2);
              curvePath.close();

              canvas.drawPath(curvePath, fillPaint);
              canvas.drawPath(curvePath, outlinePaint);
              canvas.drawCircle(center, baseR * 0.2, strokePaint);
            } else if (isRosette3) {
              // 🌸 Type 3: Filigree Baroque Oval (Image 3)
              canvas.drawOval(
                Rect.fromCenter(center: center, width: baseR * 1.6, height: baseR * 2.8),
                strokePaint,
              );
              canvas.drawOval(
                Rect.fromCenter(center: center, width: baseR * 1.6, height: baseR * 2.8),
                outlinePaint,
              );

              final Path pathL = Path();
              pathL.moveTo(center.dx, center.dy);
              pathL.cubicTo(center.dx - baseR * 0.9, center.dy - baseR * 0.9, center.dx - baseR * 0.9, center.dy + baseR * 0.9, center.dx - baseR * 0.2, center.dy + baseR * 0.6);
              canvas.drawPath(pathL, strokePaint);

              final Path pathR = Path();
              pathR.moveTo(center.dx, center.dy);
              pathR.cubicTo(center.dx + baseR * 0.9, center.dy - baseR * 0.9, center.dx + baseR * 0.9, center.dy + baseR * 0.9, center.dx + baseR * 0.2, center.dy + baseR * 0.6);
              canvas.drawPath(pathR, strokePaint);

              final Path centerDia = Path();
              centerDia.moveTo(center.dx, center.dy - baseR * 0.4);
              centerDia.lineTo(center.dx + baseR * 0.25, center.dy);
              centerDia.lineTo(center.dx, center.dy + baseR * 0.4);
              centerDia.lineTo(center.dx - baseR * 0.25, center.dy);
              centerDia.close();
              canvas.drawPath(centerDia, fillPaint);
            } else if (isRosette4) {
              // 🌸 Type 4: Solid Gold Diamond/Oval (Image 4)
              final Path solidDia = Path();
              solidDia.moveTo(center.dx, center.dy - baseR * 1.0);
              solidDia.lineTo(center.dx + baseR * 0.6, center.dy);
              solidDia.lineTo(center.dx, center.dy + baseR * 1.0);
              solidDia.lineTo(center.dx - baseR * 0.6, center.dy);
              solidDia.close();

              canvas.drawPath(solidDia, fillPaint);
              canvas.drawPath(solidDia, outlinePaint);

              canvas.drawOval(
                Rect.fromCenter(center: center, width: baseR * 1.8, height: baseR * 2.8),
                strokePaint,
              );
              canvas.drawOval(
                Rect.fromCenter(center: center, width: baseR * 1.8, height: baseR * 2.8),
                outlinePaint,
              );
            }
          }
        }
      }
    }

    canvas.restore();
  }

  void _drawAngleBadge(Canvas canvas, Offset center, double angleDeg) {
    if (angleDeg < 0.1) return;
    final String text = '${angleDeg.toStringAsFixed(1)}°';
    final textPainter = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 24,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final badgeW = textPainter.width + 24;
    final badgeH = textPainter.height + 14;
    final badgeRect = Rect.fromCenter(
      center: center,
      width: badgeW,
      height: badgeH,
    );

    final paint = Paint()
      ..color = const Color(0xFF2E7D32)
      ..style = PaintingStyle.fill;
    final borderPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    canvas.drawRRect(
      RRect.fromRectAndRadius(badgeRect, const Radius.circular(6)),
      paint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(badgeRect, const Radius.circular(6)),
      borderPaint,
    );

    textPainter.paint(
      canvas,
      Offset(
        center.dx - textPainter.width / 2,
        center.dy - textPainter.height / 2,
      ),
    );
  }

  Rect _getEffectiveZoneRect(Rect original, double h, double t) {
    if (!model.hasBottomFrame && !model.hasFramePlintheBottom && (original.bottom - (h - t)).abs() < 1.0) {
      return Rect.fromLTRB(original.left, original.top, original.right, h);
    }
    return original;
  }

  double getInnerTopY(double x, double t, double topOffset) {
    if (model.archHeight == 0 &&
        model.topSlantLeftY == 0 &&
        model.topSlantRightY == 0) {
      return topOffset + t;
    }
    double factor = 0.0;
    if (model.width > 2 * t) {
      factor = ((x - t) / (model.width - 2 * t)).clamp(0.0, 1.0);
    }
    double yL = topOffset + model.topSlantLeftY + t;
    double yR = topOffset + model.topSlantRightY + t;
    if (model.archHeight > 0) {
      double yC =
          topOffset +
          math.min(model.topSlantLeftY, model.topSlantRightY) -
          (model.archHeight * 2) +
          t;
      return (1.0 - factor) * (1.0 - factor) * yL +
          2.0 * (1.0 - factor) * factor * yC +
          factor * factor * yR;
    } else {
      return yL + factor * (yR - yL);
    }
  }

  double getSashTopY(
    double x,
    double sashTopFlat,
    double t,
    double topOffset,
    bool isTopBound,
  ) {
    if (!isTopBound) return sashTopFlat;
    double clearance = sashTopFlat - (topOffset + t);
    if (clearance < 0) clearance = 0;
    return getInnerTopY(x, t, topOffset) + clearance;
  }

  bool _isTopZone(WindowZone zone) {
    if (model.zones.isEmpty) return false;
    double minTop = model.zones.map((z) => z.boundary.top).reduce(math.min);
    return zone.boundary.top == minTop;
  }

  Path _buildOuterShapePath(double w, double h, double topY) {
    if (model.archHeight == 0 &&
        model.topSlantLeftY == 0 &&
        model.topSlantRightY == 0 &&
        model.bottomSlantLeftY == 0 &&
        model.bottomSlantRightY == 0) {
      return Path()..addRect(Rect.fromLTRB(0, topY, w, h));
    }
    Path p = Path();
    p.moveTo(0, topY + model.topSlantLeftY);
    if (model.archHeight > 0) {
      p.quadraticBezierTo(
        w / 2,
        topY +
            math.min(model.topSlantLeftY, model.topSlantRightY) -
            (model.archHeight * 2),
        w,
        topY + model.topSlantRightY,
      );
    } else {
      p.lineTo(w, topY + model.topSlantRightY);
    }
    p.lineTo(w, h - model.bottomSlantRightY);
    p.lineTo(0, h - model.bottomSlantLeftY);
    p.close();
    return p;
  }

  Path _buildInnerShapePath(double w, double h, double t, double topY) {
    double bottomOffset = model.hasFramePlintheBottom ? model.plintheHeight : (model.hasBottomFrame ? t : 0.0);

    if (model.archHeight == 0 &&
        model.topSlantLeftY == 0 &&
        model.topSlantRightY == 0 &&
        model.bottomSlantLeftY == 0 &&
        model.bottomSlantRightY == 0) {
      return Path()
        ..addRect(Rect.fromLTRB(t, topY + t, w - t, h - bottomOffset));
    }

    double slope = (model.topSlantRightY - model.topSlantLeftY) / w;
    double alpha = math.atan(slope);
    double cosAlpha = math.cos(alpha);
    double vOffset = t / cosAlpha;

    double innerTopLeftY = topY + model.topSlantLeftY + slope * t + vOffset;
    double innerTopRightY = topY + model.topSlantRightY - slope * t + vOffset;

    Path p = Path();
    p.moveTo(t, innerTopLeftY);
    if (model.archHeight > 0) {
      p.quadraticBezierTo(
        w / 2,
        topY +
            math.min(model.topSlantLeftY, model.topSlantRightY) -
            (model.archHeight * 2) +
            vOffset,
        w - t,
        innerTopRightY,
      );
    } else {
      p.lineTo(w - t, innerTopRightY);
    }
    p.lineTo(w - t, h - model.bottomSlantRightY - bottomOffset);
    p.lineTo(t, h - model.bottomSlantLeftY - bottomOffset);
    p.close();
    return p;
  }

  void _drawOuterFrames(
    Canvas canvas,
    double w,
    double h,
    double t,
    double topOffset,
  ) {
    final frameRects = model.getFrameRects();
    if (frameRects.length <= 1) {
      _drawOuterFrame(canvas, w, h, t, topOffset);
    } else {
      for (final r in frameRects) {
        canvas.save();
        canvas.translate(r.left, r.top - topOffset);
        _drawOuterFrame(canvas, r.width, r.height, t, topOffset);
        canvas.restore();
      }
    }
  }

  void _drawWeepHolesMultiple(
    Canvas canvas,
    double w,
    double h,
    double t,
    double topOffset,
  ) {
    final frameRects = model.getFrameRects();
    if (frameRects.length <= 1) {
      _drawWeepHoles(canvas, Rect.fromLTRB(0, topOffset, w, h), t);
    } else {
      for (final r in frameRects) {
        if ((r.bottom - h).abs() < 5.0) {
          _drawWeepHoles(canvas, Rect.fromLTRB(r.left, topOffset, r.right, h), t);
        }
      }
    }
  }

  void _drawOuterFrame(
    Canvas canvas,
    double w,
    double h,
    double t,
    double topY,
  ) {
    final outerPath = _buildOuterShapePath(w, h, topY);
    final innerPath = _buildInnerShapePath(w, h, t, topY);

    final path = Path()
      ..addPath(outerPath, Offset.zero)
      ..addPath(innerPath, Offset.zero)
      ..fillType = PathFillType.evenOdd;

    final outerRect = Rect.fromLTRB(0, topY, w, h);
    canvas.drawPath(path, _buildPaint(outerRect));

    if (model.selection.type == SelectionType.frame && model.isDrawingMode) {
      canvas.drawPath(
        path,
        Paint()
          ..color = Colors.green.withValues(alpha: 0.25)
          ..style = PaintingStyle.fill,
      );
    }

    final bp = Paint()
      ..color =
          (model.selection.type == SelectionType.frame && model.isDrawingMode)
          ? Colors.green
          : _fb
      ..style = PaintingStyle.stroke
      ..strokeWidth =
          (model.selection.type == SelectionType.frame && model.isDrawingMode)
          ? 3.0
          : 1.5;

    if (model.hasBottomFrame) {
      canvas.drawPath(outerPath, bp);
      canvas.drawPath(
        innerPath,
        bp
          ..strokeWidth =
              (model.selection.type == SelectionType.frame &&
                  model.isDrawingMode)
              ? 1.5
              : 0.8,
      );
    } else {
      final Path outerOpen = Path()
        ..moveTo(0, h - model.bottomSlantLeftY)
        ..lineTo(0, topY + model.topSlantLeftY);
      if (model.archHeight > 0) {
        outerOpen.quadraticBezierTo(
          w / 2,
          topY +
              math.min(model.topSlantLeftY, model.topSlantRightY) -
              (model.archHeight * 2),
          w,
          topY + model.topSlantRightY,
        );
      } else {
        outerOpen.lineTo(w, topY + model.topSlantRightY);
      }
      outerOpen.lineTo(w, h - model.bottomSlantRightY);
      canvas.drawPath(outerOpen, bp);

      double slope = (model.topSlantRightY - model.topSlantLeftY) / w;
      double alpha = math.atan(slope);
      double cosAlpha = math.cos(alpha);
      double vOffset = t / cosAlpha;

      double innerTopLeftY = topY + model.topSlantLeftY + slope * t + vOffset;
      double innerTopRightY = topY + model.topSlantRightY - slope * t + vOffset;

      final Path innerOpen = Path()
        ..moveTo(t, h - model.bottomSlantLeftY)
        ..lineTo(t, innerTopLeftY);
      if (model.archHeight > 0) {
        innerOpen.quadraticBezierTo(
          w / 2,
          topY +
              math.min(model.topSlantLeftY, model.topSlantRightY) -
              (model.archHeight * 2) +
              vOffset,
          w - t,
          innerTopRightY,
        );
      } else {
        innerOpen.lineTo(w - t, innerTopRightY);
      }
      innerOpen.lineTo(w - t, h - model.bottomSlantRightY);
      canvas.drawPath(
        innerOpen,
        bp
          ..strokeWidth =
              (model.selection.type == SelectionType.frame &&
                  model.isDrawingMode)
              ? 1.5
              : 0.8,
      );
    }

    _drawMiterCorners(
      canvas,
      outerRect,
      Rect.fromLTRB(t, topY + t, w - t, h - t),
      t,
    );
  }

  void _drawMiterCorners(Canvas canvas, Rect outer, Rect inner, double t) {
    final p = Paint()
      ..color = _mc
      ..strokeWidth = 1.8
      ..style = PaintingStyle.stroke;
    
    // 45-degree miter joints (outer frame is always 45 degrees, even for 90-degree sliding sashes)
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
    double topY,
    double cW,
  ) {
    final paint = Paint();
    if (_isWoodColor() && TextureCache.woodTexture != null) {
      _applyWoodShader(paint, Rect.fromLTRB(-cW, topY - cW, w + cW, h + cW));
    } else {
      paint.color = _fc[1];
    }

    final borderPaint = Paint()
      ..color = _fb
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    final isInternal = overrideIsInternalView ?? model.isInternalView;
    final hasL = isInternal
        ? !model.removedShutterSides.contains('left')
        : !model.removedShutterSides.contains('right');
    final hasR = isInternal
        ? !model.removedShutterSides.contains('right')
        : !model.removedShutterSides.contains('left');
    final hasT = !model.removedShutterSides.contains('top');
    final hasB =
        !model.removedShutterSides.contains('bottom') && model.hasBottomFrame;

    double yTopL = topY + (isInternal ? model.topSlantLeftY : model.topSlantRightY);
    double yTopR = topY + (isInternal ? model.topSlantRightY : model.topSlantLeftY);
    double yBottomL = h - (isInternal ? model.bottomSlantLeftY : model.bottomSlantRightY);
    double yBottomR = h - (isInternal ? model.bottomSlantRightY : model.bottomSlantLeftY);

    double slopeT = (yTopR - yTopL) / w;
    double slopeB = (yBottomR - yBottomL) / w;

    double alphaT = math.atan(slopeT);
    double cosAlphaT = math.cos(alphaT);
    double cW_vOffset = cW / cosAlphaT;

    double alphaB = math.atan(slopeB);
    double cosAlphaB = math.cos(alphaB);
    double cW_vOffsetB = cW / cosAlphaB;

    if (hasL) {
      Path path = Path()
        ..moveTo(0, yTopL)
        ..lineTo(-cW, yTopL - (hasT ? cW_vOffset : 0.0) - slopeT * cW)
        ..lineTo(-cW, yBottomL + (hasB ? cW_vOffsetB : 0.0) - slopeB * cW)
        ..lineTo(0, yBottomL)
        ..close();
      canvas.drawPath(path, paint);
      canvas.drawPath(path, borderPaint);
    }
    if (hasR) {
      Path path = Path()
        ..moveTo(w, yTopR)
        ..lineTo(w + cW, yTopR - (hasT ? cW_vOffset : 0.0) + slopeT * cW)
        ..lineTo(w + cW, yBottomR + (hasB ? cW_vOffsetB : 0.0) + slopeB * cW)
        ..lineTo(w, yBottomR)
        ..close();
      canvas.drawPath(path, paint);
      canvas.drawPath(path, borderPaint);
    }
    if (hasT) {
      Path path = Path();
      path.moveTo(0, yTopL);
      path.lineTo(
        hasL ? -cW : 0.0,
        yTopL - cW_vOffset - (hasL ? slopeT * cW : 0.0),
      );
      if (model.archHeight > 0) {
        path.quadraticBezierTo(
          w / 2,
          topY +
              math.min(model.topSlantLeftY, model.topSlantRightY) -
              (model.archHeight * 2) -
              cW_vOffset,
          hasR ? w + cW : w,
          yTopR - cW_vOffset + (hasR ? slopeT * cW : 0.0),
        );
        path.lineTo(w, yTopR);
        path.quadraticBezierTo(
          w / 2,
          topY +
              math.min(model.topSlantLeftY, model.topSlantRightY) -
              (model.archHeight * 2),
          0,
          yTopL,
        );
      } else {
        path.lineTo(
          hasR ? w + cW : w,
          yTopR - cW_vOffset + (hasR ? slopeT * cW : 0.0),
        );
        path.lineTo(w, yTopR);
        path.lineTo(0, yTopL);
      }
      path.close();
      canvas.drawPath(path, paint);
      canvas.drawPath(path, borderPaint);
    }
    if (hasB) {
      Path path = Path()
        ..moveTo(0, yBottomL)
        ..lineTo(
          hasL ? -cW : 0.0,
          yBottomL + cW_vOffsetB - (hasL ? slopeB * cW : 0.0),
        )
        ..lineTo(
          hasR ? w + cW : w,
          yBottomR + cW_vOffsetB + (hasR ? slopeB * cW : 0.0),
        )
        ..lineTo(w, yBottomR)
        ..close();
      canvas.drawPath(path, paint);
      canvas.drawPath(path, borderPaint);
    }
  }

  void _drawMullions(Canvas canvas, double w, double h, double t) {
    final double topOffset = _topOffset;
    final double mullionT = model.mullionThickness;
    final Paint paint = Paint();
    if (_isWoodColor() && TextureCache.woodTexture != null) {
      _applyWoodShader(paint, Rect.fromLTWH(0, 0, w, h));
    } else {
      paint.color = _fc[1];
    }
    paint.style = PaintingStyle.fill;
    final Paint border = Paint()
      ..color = _fb
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    final List<_MullionSegment> horizontalSegments = [];
    final List<_MullionSegment> verticalSegments = [];

    for (int i = 0; i < model.zones.length; i++) {
      final z1 = model.zones[i];
      for (int j = i + 1; j < model.zones.length; j++) {
        final z2 = model.zones[j];
        
        // Check for horizontal boundary
        double overlapLeft = math.max(z1.boundary.left, z2.boundary.left);
        double overlapRight = math.min(z1.boundary.right, z2.boundary.right);
        if (overlapLeft < overlapRight - 5.0) {
          if ((z1.boundary.bottom - z2.boundary.top).abs() <= mullionT + 2.0) {
            double yCenter = (z1.boundary.bottom + z2.boundary.top) / 2;
            horizontalSegments.add(_MullionSegment(
              position: yCenter,
              start: overlapLeft,
              end: overlapRight,
            ));
          } else if ((z2.boundary.bottom - z1.boundary.top).abs() <= mullionT + 2.0) {
            double yCenter = (z2.boundary.bottom + z1.boundary.top) / 2;
            horizontalSegments.add(_MullionSegment(
              position: yCenter,
              start: overlapLeft,
              end: overlapRight,
            ));
          }
        }

        // Check for vertical boundary
        double overlapTop = math.max(z1.boundary.top, z2.boundary.top);
        double overlapBottom = math.min(z1.boundary.bottom, z2.boundary.bottom);
        if (overlapTop < overlapBottom - 5.0) {
          if ((z1.boundary.right - z2.boundary.left).abs() <= mullionT + 2.0) {
            double xCenter = (z1.boundary.right + z2.boundary.left) / 2;
            verticalSegments.add(_MullionSegment(
              position: xCenter,
              start: overlapTop,
              end: overlapBottom,
            ));
          } else if ((z2.boundary.right - z1.boundary.left).abs() <= mullionT + 2.0) {
            double xCenter = (z2.boundary.right + z1.boundary.left) / 2;
            verticalSegments.add(_MullionSegment(
              position: xCenter,
              start: overlapTop,
              end: overlapBottom,
            ));
          }
        }
      }
    }

    final String effectivePrimary = model.primaryMullionAxis ?? 'h';
    final List<Rect> mullionRects = [];

    if (effectivePrimary == 'h') {
      // Horizontal is primary (continuous):
      final List<_MullionSegment> mergedHorizontal = _mergeMullionSegments(horizontalSegments, mullionT);
      for (var seg in mergedHorizontal) {
        double left = seg.start - mullionT / 2;
        double right = seg.end + mullionT / 2;
        mullionRects.add(Rect.fromLTRB(left, seg.position - mullionT / 2, right, seg.position + mullionT / 2));
      }
      
      for (var seg in verticalSegments) {
        double top = seg.start;
        double bottom = seg.end;
        double x = seg.position;
        
        if ((top - (topOffset + t)).abs() < 5.0) {
          top = getInnerTopY(x, t, topOffset);
        } else {
          bool meetsHAtTop = horizontalSegments.any((h) => (h.position - top).abs() <= mullionT + 2.0);
          if (meetsHAtTop) {
            top += mullionT / 2 - 0.8;
          } else {
            top -= mullionT / 2;
          }
        }
        
        bool meetsHAtBottom = horizontalSegments.any((h) => (h.position - bottom).abs() <= mullionT + 2.0);
        if (meetsHAtBottom) {
          bottom -= mullionT / 2 - 0.8;
        } else {
          bottom += mullionT / 2;
        }
        
        mullionRects.add(Rect.fromLTRB(x - mullionT / 2, top, x + mullionT / 2, bottom));
      }
    } else {
      // Vertical is primary (continuous):
      final List<_MullionSegment> mergedVertical = _mergeMullionSegments(verticalSegments, mullionT);
      for (var seg in mergedVertical) {
        double top = seg.start;
        double bottom = seg.end;
        double x = seg.position;
        
        if ((top - (topOffset + t)).abs() < 5.0) {
          top = getInnerTopY(x, t, topOffset);
        } else {
          top -= mullionT / 2;
        }
        bottom += mullionT / 2;
        
        mullionRects.add(Rect.fromLTRB(x - mullionT / 2, top, x + mullionT / 2, bottom));
      }
      
      for (var seg in horizontalSegments) {
        double left = seg.start;
        double right = seg.end;
        double y = seg.position;
        
        bool meetsVAtLeft = verticalSegments.any((v) => (v.position - left).abs() <= mullionT + 2.0);
        if (meetsVAtLeft) {
          left += mullionT / 2 - 0.8;
        } else {
          left -= mullionT / 2;
        }
        
        bool meetsVAtRight = verticalSegments.any((v) => (v.position - right).abs() <= mullionT + 2.0);
        if (meetsVAtRight) {
          right -= mullionT / 2 - 0.8;
        } else {
          right += mullionT / 2;
        }
        
        mullionRects.add(Rect.fromLTRB(left, y - mullionT / 2, right, y + mullionT / 2));
      }
    }

    for (var rect in mullionRects) {
      canvas.drawRect(rect, paint);
      canvas.drawRect(rect, border);
    }

    if (model.selection.type == SelectionType.mullion) {
      bool isH = model.selection.isHorizontalMullion!;
      double pos = model.selection.mullionPosition!;
      double start = model.selection.mullionStart ?? 0.0;
      double end = model.selection.mullionEnd ?? (isH ? w : h);
      final highlightPaint = Paint()
        ..color = Colors.green.shade600.withValues(alpha: 0.5)
        ..style = PaintingStyle.fill;
      if (isH) {
        canvas.drawRect(
          Rect.fromLTRB(start, pos - mullionT / 2, end, pos + mullionT / 2),
          highlightPaint,
        );
      } else {
        canvas.drawRect(
          Rect.fromLTRB(pos - mullionT / 2, start, pos + mullionT / 2, end),
          highlightPaint,
        );
      }
    }
  }

  void _drawInnerDimensions(Canvas canvas, WindowZone zone) {
    final r = zone.boundary;
    final double t = model.profileThickness;
    if (r.width < 150 || r.height < 150) return;
    bool isFullWidth =
        (r.width >= model.width - model.profileThickness * 2 - 2);
    bool isFullHeight =
        (r.height >= model.height - model.profileThickness * 2 - 2);
    final textStyle = const TextStyle(
      color: Color(0xFF1565C0),
      fontSize: 63,
      fontWeight: FontWeight.bold,
    );

    // Calculate real cutting sizes if there's a sash in this zone
    double displayWidth = r.width;
    double displayHeight = r.height;
    double displayWLeft = 0.0;
    double displayWRight = 0.0;

    double overlap = model.sashOverride != null
        ? (model.sashOverride!['sash_overlap'] ?? 8.0).toDouble()
        : 8.0;
    double weld = model.isPVC ? 5.0 : 0.0;

    if (zone.content == ZoneContent.singleSash) {
      displayWidth = r.width + overlap * 2 + weld;
      displayHeight = r.height + overlap * 2 + weld;
    } else if (zone.content == ZoneContent.doubleSash) {
      final isInternal = overrideIsInternalView ?? model.isInternalView;
      final double effectiveRatio = isInternal ? zone.doubleSashRatio : (1.0 - zone.doubleSashRatio);
      displayWLeft = r.width * effectiveRatio + overlap + weld;
      displayWRight = r.width * (1.0 - effectiveRatio) + overlap + weld;
      displayHeight = r.height + overlap * 2 + weld;
    } else if (zone.content == ZoneContent.slidingSash) {
      final slidingSashOverride = model.slidingSashOverride ?? model.sashOverride;
      double slidingOverlap = slidingSashOverride != null
          ? (slidingSashOverride['sash_overlap'] ?? 8.0).toDouble()
          : 8.0;
      double wForCalc = r.width;
      double hForCalc = r.height;

      bool isNested = model.zones.length > 1;
      if (isNested) {
        double innerFrameT = 45.0;
        final series = model.activeSlidingSeries ?? model.activeSeries;
        if (series != null) {
          var slidingFrames = series.sections.where((s) {
            final name = s.name.toLowerCase();
            final type = s.type.toLowerCase();
            return (name.contains('coulissant') || name.contains('منزلق') || name.contains('sliding') ||
                    type.contains('coulissant') || type.contains('sliding')) &&
                   (type.contains('frame') || type.contains('cadre') || type.contains('إطار'));
          }).toList();
          if (slidingFrames.isNotEmpty) {
            innerFrameT = slidingFrames.first.visibleWidth > 0
                ? slidingFrames.first.visibleWidth
                : (slidingFrames.first.thickness > 0 ? slidingFrames.first.thickness : 45.0);
          }
        }
        wForCalc = r.width - (innerFrameT * 2.0);
        hForCalc = r.height - (innerFrameT * 2.0);
      }

      int sashes = zone.slidingSashesCount > 0 ? zone.slidingSashesCount : 2;
      double cuttingW = (wForCalc + ((sashes - 1) * 26.0)) / sashes;
      if (model.isPVC) {
        cuttingW = (wForCalc + ((sashes - 1) * slidingOverlap)) / sashes;
      }
      double cuttingH = hForCalc + slidingOverlap * 2;
      final String seriesName = model.activeSlidingSeries?.name.toLowerCase() ?? model.activeSeries?.name.toLowerCase() ?? '';
      final bool isTPI67000 = seriesName.contains('67000') || seriesName.contains('tpi');
      bool hasThreePiece = (model.activeSlidingSeries?.hasThreePieceSash ?? false) || isTPI67000;
      if (hasThreePiece) {
        cuttingH = model.height - 64.0;
      } else {
        if (!model.isPVC) {
          cuttingH = model.height - 81.0;
        }
      }

      displayWidth = cuttingW;
      displayHeight = cuttingH;
    }

    if (zone.content == ZoneContent.doubleSash) {
      final isInternal = overrideIsInternalView ?? model.isInternalView;
      final double effectiveRatio = isInternal ? zone.doubleSashRatio : (1.0 - zone.doubleSashRatio);

      final leftText = TextPainter(
        text: TextSpan(text: "${displayWLeft.toInt()}", style: textStyle),
        textDirection: TextDirection.ltr,
      )..layout();

      final rightText = TextPainter(
        text: TextSpan(text: "${displayWRight.toInt()}", style: textStyle),
        textDirection: TextDirection.ltr,
      )..layout();

      final leftX = r.left + (r.width * effectiveRatio) / 2;
      final rightX =
          r.left +
          (r.width * effectiveRatio) +
          (r.width * (1.0 - effectiveRatio)) / 2;

      final leftOffset = Offset(leftX - (leftText.width / 2), r.top + 5);
      final rightOffset = Offset(rightX - (rightText.width / 2), r.top + 5);

      leftText.paint(canvas, leftOffset);
      rightText.paint(canvas, rightOffset);
    } else {
      if (!isFullWidth) {
        final widthText = TextPainter(
          text: TextSpan(text: "${displayWidth.toInt()}", style: textStyle),
          textDirection: TextDirection.ltr,
        )..layout();
        bool isBottomBound =
            (r.bottom - (model.height - (model.hasBottomFrame ? t : 0.0)))
                .abs() <
            5.0;
        final double labelY = (_isSlantedOrArched && isBottomBound)
            ? (model.height + 10.0)
            : (r.bottom - widthText.height - 12.0);
        final wOffset = Offset(r.center.dx - (widthText.width / 2), labelY);
        widthText.paint(canvas, wOffset);
      }
    }
    if (!isFullHeight) {
      final heightText = TextPainter(
        text: TextSpan(text: "${displayHeight.toInt()}", style: textStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      canvas.save();
      canvas.translate(
        r.left + 5 + heightText.height,
        r.center.dy + (heightText.width / 2),
      );
      canvas.rotate(-3.1415926535897932 / 2);
      heightText.paint(canvas, Offset(0, -heightText.height));
      canvas.restore();
    }
  }

  void _drawZoneBackground(Canvas canvas, WindowZone zone, double h, double t) {
    final r = _getEffectiveZoneRect(zone.boundary, h, t);
    final double topOffset = _topOffset;
    final bool isTopBound = _isTopZone(zone);
    final path = _buildGlassLayerPath(r, t, topOffset, isTopBound);
    canvas.drawPath(path, Paint()..color = const Color(0xFFF5F8FA));
  }

  void _drawZoneContent(Canvas canvas, WindowZone zone, double h, double t) {
    final r = _getEffectiveZoneRect(zone.boundary, h, t);
    final double topOffset = _topOffset;
    final bool isTopBound = _isTopZone(zone);
    switch (zone.content) {
      case ZoneContent.empty:
      case ZoneContent.fixedGlass:
        final cellSpec = zone.getGlassForCell('main_cell_0_0');

        final bool isDecorPanel =
            (cellSpec.structure == GlassStructure.closed &&
            ((overrideIsInternalView ?? model.isInternalView)
                ? cellSpec.finishInner == GlassFinish.paneauSandwitchDecore
                : cellSpec.finishOuter == GlassFinish.paneauSandwitchDecore));
        if (isDecorPanel) {
          _drawPanelTexture(
            canvas,
            r,
            model.frameColor,
            finish: GlassFinish.paneauSandwitchDecore,
            zone: zone,
            spec: cellSpec,
            t: t,
            topOffset: topOffset,
            isTopBound: isTopBound,
          );
        } else if (cellSpec.structure == GlassStructure.closed) {
          _drawPanelTexture(
            canvas,
            r,
            model.frameColor,
            zone: zone,
            spec: cellSpec,
            t: t,
            topOffset: topOffset,
            isTopBound: isTopBound,
          );
        } else if (zone.content == ZoneContent.fixedGlass) {
          _drawFixedGlass(canvas, r, cellSpec, t, topOffset, isTopBound);
        }
        if (!isDecorPanel) {
          _drawRealisticParclose(
            canvas,
            r,
            model.frameColor,
            t: t,
            topOffset: topOffset,
            isTopBound: isTopBound,
          );
        }
        break;

      case ZoneContent.singleSash:
        _drawSingleSash(canvas, r, zone);
        break;
      case ZoneContent.doubleSash:
        final sep = 4.0;
        final isInternal = overrideIsInternalView ?? model.isInternalView;
        final double effectiveRatio = isInternal ? zone.doubleSashRatio : (1.0 - zone.doubleSashRatio);
        final midX = r.left + r.width * effectiveRatio;
        final leftR = Rect.fromLTRB(r.left, r.top, midX - sep / 2, r.bottom);
        final rightR = Rect.fromLTRB(midX + sep / 2, r.top, r.right, r.bottom);
        bool isLeftActive = (zone.openDirection == OpenDirection.left);
        bool isRightActive = (zone.openDirection == OpenDirection.right);
        if (zone.doubleSashRatio > 0.5) {
          isLeftActive = true;
          isRightActive = false;
        } else if (zone.doubleSashRatio < 0.5) {
          isLeftActive = false;
          isRightActive = true;
        } else {
          if (!isLeftActive && !isRightActive) isRightActive = true;
        }
        if (isInternal) {
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
        } else {
          // Mirror horizontally for external view: L sash drawn on rightR, R sash drawn on leftR
          _renderSash(
            canvas,
            leftR,
            zone.copyWith(openDirection: OpenDirection.left),
            leftR,
            forceHandle: isRightActive,
            isRightSash: true,
          );
          _renderSash(
            canvas,
            rightR,
            zone.copyWith(openDirection: OpenDirection.right),
            rightR,
            forceHandle: isLeftActive,
            isRightSash: false,
          );
        }
        canvas.drawLine(
          Offset(midX, r.top),
          Offset(midX, r.bottom),
          Paint()
            ..color = _fb
            ..strokeWidth = 1.2,
        );
        break;
      case ZoneContent.slidingSash:
        _drawSlidingSash(canvas, r, zone, t, topOffset);
        break;
    }
  }

  void _drawFixedGlass(
    Canvas canvas,
    Rect r,
    GlassSpecification glass,
    double t,
    double topOffset,
    bool isTopBound, {
    bool isInsideSash = false,
    double? sashTop,
    double? topW,
  }) {
    final isLookingFromInside =
        (overrideIsInternalView ?? model.isInternalView);
    final GlassColor chosenColor;
    final GlassFinish chosenFinish;
    if (glass.structure == GlassStructure.simple) {
      chosenColor = glass.colorOuter;
      chosenFinish = glass.finishOuter;
    } else {
      chosenColor = isLookingFromInside ? glass.colorInner : glass.colorOuter;
      chosenFinish = isLookingFromInside
          ? glass.finishInner
          : glass.finishOuter;
    }
    _drawGlassLayer(
      canvas,
      r,
      glass,
      chosenColor,
      chosenFinish,
      t,
      topOffset,
      isTopBound,
      isInsideSash: isInsideSash,
      sashTop: sashTop,
      topW: topW,
    );
    _drawGlassLabel(canvas, r, glass.displayName);
  }

  double getInnerBottomY(double x, double t) {
    if (model.bottomSlantLeftY == 0 && model.bottomSlantRightY == 0) {
      return model.height - (model.hasBottomFrame ? t : 0.0);
    }
    double factor = 0.0;
    if (model.width > 2 * t) {
      factor = ((x - t) / (model.width - 2 * t)).clamp(0.0, 1.0);
    }
    double bottomOffset = model.hasFramePlintheBottom ? model.plintheHeight : (model.hasBottomFrame ? t : 0.0);
    double yL = model.height - model.bottomSlantLeftY - bottomOffset;
    double yR = model.height - model.bottomSlantRightY - bottomOffset;
    return yL + factor * (yR - yL);
  }

  Path _buildGlassLayerPath(
    Rect r,
    double t,
    double topOffset,
    bool isTopBound, {
    bool isInsideSash = false,
    double? sashTop,
    double? topW,
  }) {
    final Path path = Path();
    bool isBottomBound = !isInsideSash &&
        (r.bottom - (model.height - (model.hasBottomFrame ? t : 0.0))).abs() <
        5.0;

    double yTL = isTopBound
        ? (isInsideSash && sashTop != null && topW != null
            ? getSashTopY(r.left, sashTop, t, topOffset, true) + topW
            : getInnerTopY(r.left, t, topOffset))
        : r.top;
    double yTR = isTopBound
        ? (isInsideSash && sashTop != null && topW != null
            ? getSashTopY(r.right, sashTop, t, topOffset, true) + topW
            : getInnerTopY(r.right, t, topOffset))
        : r.top;
    double yBL = isBottomBound ? getInnerBottomY(r.left, t) : r.bottom;
    double yBR = isBottomBound ? getInnerBottomY(r.right, t) : r.bottom;

    path.moveTo(r.left, yBL);
    path.lineTo(r.left, yTL);
    if (isTopBound && model.archHeight > 0) {
      double yMid = isInsideSash && sashTop != null && topW != null
          ? getSashTopY((r.left + r.right) / 2, sashTop, t, topOffset, true) + topW
          : getInnerTopY((r.left + r.right) / 2, t, topOffset);
      double yC = 2 * yMid - 0.5 * (yTL + yTR);
      path.quadraticBezierTo((r.left + r.right) / 2, yC, r.right, yTR);
    } else {
      path.lineTo(r.right, yTR);
    }
    path.lineTo(r.right, yBR);
    path.close();
    return path;
  }

  void _drawPanelTexture(
    Canvas canvas,
    Rect r,
    FrameColor color, {
    GlassFinish? finish,
    WindowZone? zone,
    GlassSpecification? spec,
    required double t,
    required double topOffset,
    required bool isTopBound,
    bool isInsideSash = false,
    double? sashTop,
    double? topW,
  }) {
    final Path glassPath = _buildGlassLayerPath(
      r,
      t,
      topOffset,
      isTopBound,
      isInsideSash: isInsideSash,
      sashTop: sashTop,
      topW: topW,
    );
    canvas.save();
    canvas.clipPath(glassPath);

    final effectiveSpec = spec ?? zone?.glass;
    final GlassFinish activeFinish =
        finish ??
        (effectiveSpec != null
            ? ((overrideIsInternalView ?? model.isInternalView)
                ? effectiveSpec.finishInner
                : effectiveSpec.finishOuter)
            : null) ??
        model.selectedZone?.glass.finishOuter ??
        GlassFinish.paneauSandwitch;

    final Paint fillPaint = Paint();
    final String? pColor = effectiveSpec?.panneauColor ?? model.selectedZone?.glass.panneauColor;
    final bool isPanneauWood = pColor != null && _isWoodColor({'name': pColor});
    if (isPanneauWood && TextureCache.woodTexture != null) {
      final woodColors = getEffectiveGradientColors(FrameColor.brown, {'name': pColor});
      _applyWoodShader(fillPaint, r, gradientColors: woodColors, dbColor: {'name': pColor});
    } else {
      final ClosedGlassColor colorP =
          effectiveSpec?.colorP ??
          model.selectedZone?.glass.colorP ??
          ClosedGlassColor.white;
      final List<Color> gradientColors = _getColorsForLayer(
        GlassStructure.closed,
        effectiveSpec?.colorOuter ??
            model.selectedZone?.glass.colorOuter ??
            GlassColor.transparent,
        activeFinish,
        colorP,
        pColor,
      );
      fillPaint.shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: gradientColors,
      ).createShader(r);
    }
    fillPaint.style = PaintingStyle.fill;
    canvas.drawRect(r, fillPaint);


    if (activeFinish == GlassFinish.bardage) {
      // 🟢 رسم البارداج كشرائح أفقية أو عمودية بعرضها الحقيقي من قاعدة البيانات
      final String? panneauSub = effectiveSpec?.panneauSubtype;
      final bool isVertical = effectiveSpec?.isVerticalBardage ?? false;

      double realSlatHeight = 100.0; // قيمة افتراضية للبارداج
      if (model.componentOverrides.containsKey('البارداج (Bardage)')) {
        final bardageOverride = model.componentOverrides['البارداج (Bardage)'];
        if (bardageOverride != null) {
          final dbWidth = (bardageOverride['visible_width'] ?? bardageOverride['thickness']) as num?;
          if (dbWidth != null && dbWidth > 0) {
            realSlatHeight = dbWidth.toDouble();
          }
        }
      } else if (effectiveSpec != null) {
        Map<String, dynamic> dbMatch = <String, dynamic>{};
        if (effectiveSpec.panneauProductId != null) {
          dbMatch = model.allGlassCache.firstWhere(
            (g) => g['id'] == effectiveSpec.panneauProductId,
            orElse: () => <String, dynamic>{},
          );
        }
        if (dbMatch.isEmpty && panneauSub != null) {
          dbMatch = model.allGlassCache.firstWhere(
            (g) =>
                g['type'].toString().toLowerCase() == 'panneau' &&
                (g['subtype'] ?? '').toString().toLowerCase().contains('bardage'),
            orElse: () => <String, dynamic>{},
          );
        }
        if (dbMatch.isNotEmpty) {
          final dbWidth = (dbMatch['visible_width'] ?? dbMatch['thickness']) as num?;
          if (dbWidth != null && dbWidth > 0) {
            // Convert mm to canvas pixels: model scale is applied already
            realSlatHeight = dbWidth.toDouble();
          }
        }
      }

      // Draw slats with shadow and highlight for 3D effect
      final Paint slatShadow = Paint()
        ..color = Colors.black.withValues(alpha: 0.18)
        ..strokeWidth = 2.0
        ..style = PaintingStyle.stroke;
      final Paint slatHighlight = Paint()
        ..color = Colors.white.withValues(alpha: 0.28)
        ..strokeWidth = 1.0
        ..style = PaintingStyle.stroke;
      final Paint slatDivider = Paint()
        ..color = _fb.withValues(alpha: 0.45)
        ..strokeWidth = 1.0
        ..style = PaintingStyle.stroke;

      if (isVertical) {
        // 🟢 رسم شرائح عمودية
        double x = r.left + realSlatHeight;
        while (x <= r.right) {
          canvas.drawLine(Offset(x - 1.5, r.top), Offset(x - 1.5, r.bottom), slatHighlight);
          canvas.drawLine(Offset(x, r.top), Offset(x, r.bottom), slatDivider);
          canvas.drawLine(Offset(x + 1.0, r.top), Offset(x + 1.0, r.bottom), slatShadow);
          x += realSlatHeight;
        }
      } else {
        // 🟢 رسم شرائح أفقية
        double y = r.top + realSlatHeight;
        while (y <= r.bottom) {
          canvas.drawLine(Offset(r.left, y - 1.5), Offset(r.right, y - 1.5), slatHighlight);
          canvas.drawLine(Offset(r.left, y), Offset(r.right, y), slatDivider);
          canvas.drawLine(Offset(r.left, y + 1.0), Offset(r.right, y + 1.0), slatShadow);
          y += realSlatHeight;
        }
      }
    }
 else if (activeFinish == GlassFinish.paneauSandwitchDecore) {
      Paint linePaint = Paint()
        ..color = _fb.withValues(alpha: 0.3)
        ..strokeWidth = 1.5;
      for (double x = r.left + 30; x < r.right; x += 30) {
        canvas.drawLine(Offset(x, r.top), Offset(x, r.bottom), linePaint);
      }
      for (double y = r.top + 30; y < r.bottom; y += 30) {
        canvas.drawLine(Offset(r.left, y), Offset(r.right, y), linePaint);
      }
    }
    canvas.restore();
  }

  List<Color> _getColorsForLayer(
    GlassStructure str,
    GlassColor c,
    GlassFinish f,
    ClosedGlassColor p, [
    String? panneauColor,
  ]) {
    if (str == GlassStructure.closed) {
      if (panneauColor != null && panneauColor.isNotEmpty) {
        final fakeDbColor = {'name': panneauColor};
        return getEffectiveGradientColors(FrameColor.white, fakeDbColor);
      }
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
          return [
            Colors.grey.shade100,
            Colors.grey.shade200,
            Colors.grey.shade300,
          ];
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

  void _drawSlidingSash(
    Canvas canvas,
    Rect r,
    WindowZone zone,
    double t,
    double topOffset,
  ) {
    int count = zone.slidingSashesCount;
    if (count < 2) count = 2;
    final bool isTopBound = _isTopZone(zone);

    bool isNested = model.zones.length > 1;
    if (isNested) {
      double innerFrameT = 45.0;
      final series = model.activeSlidingSeries ?? model.activeSeries;
      if (series != null) {
        var slidingFrames = series.sections.where((s) {
          final name = s.name.toLowerCase();
          final type = s.type.toLowerCase();
          return (name.contains('coulissant') || name.contains('منزلق') || name.contains('sliding') ||
                  type.contains('coulissant') || type.contains('sliding')) &&
                 (type.contains('frame') || type.contains('cadre') || type.contains('إطار'));
        }).toList();
        if (slidingFrames.isNotEmpty) {
          innerFrameT = slidingFrames.first.visibleWidth > 0
              ? slidingFrames.first.visibleWidth
              : (slidingFrames.first.thickness > 0 ? slidingFrames.first.thickness : 45.0);
        } else {
          var anyFrames = series.sections.where((s) {
            final type = s.type.toLowerCase();
            return type.contains('frame') || type.contains('cadre') || type.contains('إطار');
          }).toList();
          if (anyFrames.isNotEmpty) {
            innerFrameT = anyFrames.first.visibleWidth > 0
                ? anyFrames.first.visibleWidth
                : (anyFrames.first.thickness > 0 ? anyFrames.first.thickness : 45.0);
          }
        }
      }

      // Draw the nested inner frame
      final innerFrameGlassRect = r.deflate(innerFrameT);
      _drawSashFrameRect(
        canvas,
        r,
        innerFrameGlassRect,
        model.frameColor,
        model.selectedDbColor,
        dimmed: false,
        t: t,
        topOffset: topOffset,
        isTopBound: isTopBound,
      );

      // Deflate the drawing rect for sashes
      r = innerFrameGlassRect;
    }

    // Get visible widths of different profiles for the sliding sash
    final double traverseT = _getSlidingSectionWidth('traverse', 'traverse', 45.0);
    final double chicaneT = _getSlidingSectionWidth('chicane', 'centrale', 45.0);
    final double lateralT = _getSlidingSectionWidth('lateral', 'poignee', 45.0);

    // sashWidth is calculated using chicaneT (overlap)
    double sashWidth = (r.width + (count - 1) * chicaneT) / count;

    List<int> tracks;
    if (count == 2) {
      if (zone.openDirection == OpenDirection.left) {
        tracks = [1, 0];
      } else {
        tracks = [0, 1];
      }
    } else if (count == 3) {
      tracks = [0, 1, 0];
    } else if (count == 4) {
      tracks = [0, 1, 1, 0];
    } else {
      tracks = List.generate(count, (i) => i % 2);
    }

    for (int tg = 0; tg <= 1; tg++) {
      for (int i = 0; i < count; i++) {
        if (tracks[i] != tg) continue;

        double left = r.left + i * (sashWidth - chicaneT);
        Rect sashRect = Rect.fromLTRB(left, r.top, left + sashWidth, r.bottom);

        // Calculate left and right profile widths for this specific sash
        final double leftProfileW = (i == 0) ? lateralT : chicaneT;
        final double rightProfileW = (i == count - 1) ? lateralT : chicaneT;
        final double topProfileW = traverseT;
        final double bottomProfileW = zone.hasSashPlintheBottom ? model.plintheHeight : traverseT;

        double finalLeftW = leftProfileW;
        double finalRightW = rightProfileW;
        double finalTopW = topProfileW;
        double finalBottomW = bottomProfileW;

        if (sashRect.width <= finalLeftW + finalRightW + 10) {
          finalLeftW = math.max(1.0, (sashRect.width - 10) / 2);
          finalRightW = finalLeftW;
        }
        if (sashRect.height <= finalTopW + finalBottomW + 10) {
          finalTopW = math.max(1.0, (sashRect.height - 10) / 2);
          finalBottomW = finalTopW;
        }

        final glassR = Rect.fromLTRB(
          sashRect.left + finalLeftW,
          sashRect.top + finalTopW,
          sashRect.right - finalRightW,
          sashRect.bottom - finalBottomW,
        );

        final String cellKey = 'main_cell_0_$i';
        final cellSpec = zone.getGlassForCell(cellKey);

        final bool isDecorPanel =
            (cellSpec.structure == GlassStructure.closed &&
            ((overrideIsInternalView ?? model.isInternalView)
                ? cellSpec.finishInner == GlassFinish.paneauSandwitchDecore
                : cellSpec.finishOuter == GlassFinish.paneauSandwitchDecore));

        if (isDecorPanel) {
          _drawPanelTexture(
            canvas,
            sashRect,
            model.frameColor,
            finish: GlassFinish.paneauSandwitchDecore,
            zone: zone,
            spec: cellSpec,
            t: t,
            topOffset: topOffset,
            isTopBound: isTopBound,
            isInsideSash: true,
            sashTop: sashRect.top,
            topW: 0.0,
          );
        } else {
          _drawSashFrameRect(
            canvas,
            sashRect,
            glassR,
            zone.sashColor,
            zone.selectedDbColor,
            dimmed: (tg == 0),
            isSlidingSash: true,
            t: t,
            topOffset: topOffset,
            isTopBound: isTopBound,
          );
          if (cellSpec.structure == GlassStructure.closed) {
            _drawPanelTexture(
              canvas,
              glassR,
              model.frameColor,
              finish: (overrideIsInternalView ?? model.isInternalView)
                  ? cellSpec.finishInner
                  : cellSpec.finishOuter,
              zone: zone,
              spec: cellSpec,
              t: t,
              topOffset: topOffset,
              isTopBound: isTopBound,
              isInsideSash: true,
              sashTop: sashRect.top,
              topW: glassR.top - sashRect.top,
            );
          } else {
            _drawFixedGlass(
              canvas,
              glassR,
              cellSpec,
              t,
              topOffset,
              isTopBound,
              isInsideSash: true,
              sashTop: sashRect.top,
              topW: glassR.top - sashRect.top,
            );
          }
        }

        final bool drawHandle = (i == 0 || i == count - 1) && model.isPVC;
        if (drawHandle) {
          _drawWindowDrawHandle(
            canvas,
            sashRect,
            (i == 0) ? OpenDirection.left : OpenDirection.right,
            zone.handlePositionRatio ?? 0.5,
            t: t,
            topOffset: topOffset,
            isTopBound: isTopBound,
            zone: zone,
          );
        }
      }
    }
  }

  void _drawInternalDivisions(
    Canvas canvas,
    Rect glassR,
    int innerH,
    int innerV,
    List<double> innerHPos,
    List<double> innerVPos,
    FrameColor color,
    double sashT,
    WindowZone zone,
    bool isRightSash,
    bool isTopBound,
  ) {
    String sidePrefix = zone.content == ZoneContent.doubleSash
        ? (isRightSash ? 'right' : 'main')
        : 'main';
    if (zone.content == ZoneContent.doubleSash && !isRightSash) {
      sidePrefix = 'left';
    }

    final double t = model.profileThickness;
    final double topOffset = _topOffset;

    if (innerH == 0 && innerV == 0) {
      final cellKey = '${sidePrefix}_cell_0_0';
      if (zone.cellIsSash[cellKey] == true) {
        double? cellSashThickness;
        bool isSash105 = zone.isSash105;
        if (zone.cellSashOverrides[cellKey] != null) {
          cellSashThickness =
              (zone.cellSashOverrides[cellKey]!['visible_width'] as num?)
                  ?.toDouble();
          final code =
              zone.cellSashOverrides[cellKey]!['code']
                  ?.toString()
                  .toLowerCase() ??
              '';
          final name =
              zone.cellSashOverrides[cellKey]!['name']
                  ?.toString()
                  .toLowerCase() ??
              '';
          if (code.contains('104') || name.contains('104')) {
            isSash105 = false;
          } else if (code.contains('105') ||
              code.contains('porte') ||
              code.contains('ouvr') ||
              name.contains('105') ||
              name.contains('porte') ||
              name.contains('ouvr') ||
              name.contains('بورت')) {
            isSash105 = true;
          }
        }
        OpenDirection cellOpenDirection = OpenDirection.left;
        if (zone.cellSashOverrides[cellKey] != null &&
            zone.cellSashOverrides[cellKey]!['openDirection'] != null) {
          final dirStr = zone.cellSashOverrides[cellKey]!['openDirection']
              .toString();
          cellOpenDirection = OpenDirection.values.firstWhere(
            (d) => d.name == dirStr,
            orElse: () => OpenDirection.left,
          );
        }
        final nestedSashZone = WindowZone(
          id: '${zone.id}_nested_$cellKey',
          boundary: glassR,
          content: ZoneContent.singleSash,
          sashColor: zone.sashColor,
          openDirection: cellOpenDirection,
          glass: zone.getGlassForCell(cellKey),
          isSash105: isSash105,
          sashThickness: cellSashThickness,
        );
        _renderSash(
          canvas,
          glassR,
          nestedSashZone,
          glassR,
          forceHandle: true,
          isRightSash: false,
        );
      } else if (zone.cellIsDoubleSash[cellKey] == true) {
        final sep = 4.0;
        final midX = glassR.left + glassR.width * 0.5;
        final leftR = Rect.fromLTRB(
          glassR.left,
          glassR.top,
          midX - sep / 2,
          glassR.bottom,
        );
        final rightR = Rect.fromLTRB(
          midX + sep / 2,
          glassR.top,
          glassR.right,
          glassR.bottom,
        );

        double? cellSashThickness;
        bool isSash105 = zone.isSash105;
        if (zone.cellSashOverrides[cellKey] != null) {
          cellSashThickness =
              (zone.cellSashOverrides[cellKey]!['visible_width'] as num?)
                  ?.toDouble();
          final code =
              zone.cellSashOverrides[cellKey]!['code']
                  ?.toString()
                  .toLowerCase() ??
              '';
          final name =
              zone.cellSashOverrides[cellKey]!['name']
                  ?.toString()
                  .toLowerCase() ??
              '';
          if (code.contains('104') || name.contains('104')) {
            isSash105 = false;
          } else if (code.contains('105') ||
              code.contains('porte') ||
              code.contains('ouvr') ||
              name.contains('105') ||
              name.contains('porte') ||
              name.contains('ouvr') ||
              name.contains('بورت')) {
            isSash105 = true;
          }
        }

        OpenDirection cellOpenDirection = OpenDirection.right;
        if (zone.cellSashOverrides[cellKey] != null &&
            zone.cellSashOverrides[cellKey]!['openDirection'] != null) {
          final dirStr = zone.cellSashOverrides[cellKey]!['openDirection']
              .toString();
          cellOpenDirection = OpenDirection.values.firstWhere(
            (d) => d.name == dirStr,
            orElse: () => OpenDirection.right,
          );
        }
        bool isLeftActive = (cellOpenDirection == OpenDirection.left);
        bool isRightActive = (cellOpenDirection == OpenDirection.right);

        final nestedSashZoneLeft = WindowZone(
          id: '${zone.id}_nested_${cellKey}_L',
          boundary: leftR,
          content: ZoneContent.doubleSash,
          sashColor: zone.sashColor,
          openDirection: OpenDirection.right,
          glass: zone.getGlassForCell(cellKey),
          isSash105: isSash105,
          sashThickness: cellSashThickness,
        );
        final nestedSashZoneRight = WindowZone(
          id: '${zone.id}_nested_${cellKey}_R',
          boundary: rightR,
          content: ZoneContent.doubleSash,
          sashColor: zone.sashColor,
          openDirection: OpenDirection.left,
          glass: zone.getGlassForCell(cellKey),
          isSash105: isSash105,
          sashThickness: cellSashThickness,
        );

        _renderSash(
          canvas,
          leftR,
          nestedSashZoneLeft,
          leftR,
          forceHandle: isLeftActive,
          isRightSash: false,
        );
        _renderSash(
          canvas,
          rightR,
          nestedSashZoneRight,
          rightR,
          forceHandle: isRightActive,
          isRightSash: true,
        );

        final sepPaint = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = sep;

        if (_isWoodColor() && TextureCache.woodTexture != null) {
          _applyWoodShader(sepPaint, glassR);
        } else {
          sepPaint.color = _fc[1];
        }

        canvas.drawLine(
          Offset(midX, glassR.top),
          Offset(midX, glassR.bottom),
          sepPaint,
        );
      } else {
        final cellSpec = zone.getGlassForCell(cellKey);
        if (cellSpec.structure == GlassStructure.closed) {
          _drawPanelTexture(
            canvas,
            glassR,
            color,
            zone: zone,
            spec: cellSpec,
            t: t,
            topOffset: topOffset,
            isTopBound: isTopBound,
          );
        } else {
          _drawFixedGlass(
            canvas,
            glassR,
            cellSpec,
            t,
            topOffset,
            isTopBound,
          );
        }
        _drawRealisticParclose(
          canvas,
          glassR,
          color,
          t: t,
          topOffset: topOffset,
          isTopBound: isTopBound,
        );
      }

      if (model.selectedZone?.id == zone.id && model.activeSubZone == cellKey) {
        final cellPath = _buildGlassLayerPath(glassR, t, topOffset, isTopBound);
        canvas.drawPath(
          cellPath,
          Paint()
            ..color = Colors.green.shade700.withValues(alpha: 0.4)
            ..style = PaintingStyle.fill,
        );
      }
      return;
    }

    final double dividerT = model.getSectionThickness(
      'mullion',
      fallback: sashT,
    );

    final Paint paint = Paint();
    if (_isWoodColor() && TextureCache.woodTexture != null) {
      _applyWoodShader(paint, glassR);
    } else {
      paint.color = _fc[1];
    }
    paint.style = PaintingStyle.fill;

    final Paint border = Paint()
      ..color = _fb
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    Path combinedPath = Path();

    List<double> hPositions = List.from(innerHPos);
    if (hPositions.isEmpty && innerH > 0) {
      double stepY = 1.0 / (innerH + 1);
      for (int i = 1; i <= innerH; i++) {
        hPositions.add(stepY * i);
      }
    }
    List<double> vPositions = List.from(innerVPos);
    if (vPositions.isEmpty && innerV > 0) {
      double stepX = 1.0 / (innerV + 1);
      for (int i = 1; i <= innerV; i++) {
        vPositions.add(stepX * i);
      }
    }

    String getVKey(int r, int v) {
      if (zone.content == ZoneContent.doubleSash && isRightSash) {
        return "right_${r}_$v";
      }
      return "${r}_$v";
    }

    String getHKey(int c, int h) {
      if (zone.content == ZoneContent.doubleSash && isRightSash) {
        return "right_${c}_$h";
      }
      return "${c}_$h";
    }

    int rows = hPositions.length + 1;
    int cols = vPositions.length + 1;

    final String? primaryAxis = isRightSash ? zone.rightPrimaryDivisionAxis : zone.primaryDivisionAxis;
    final String effectivePrimary = primaryAxis ?? (innerV > 0 ? 'v' : 'h');
    final List<Rect> fillRects = [];

    if (effectivePrimary == 'h') {
      // ==========================================
      // Horizontal is Primary (continuous)
      // ==========================================
      if (hPositions.isNotEmpty) {
        for (int h = 0; h < hPositions.length; h++) {
          double y = glassR.top + (glassR.height * hPositions[h]);
          double? runStart;
          
          for (int c = 0; c < cols; c++) {
            final hKey = getHKey(c, h);
            bool isSegmentActive = zone.disabledHorizontalDivisions[hKey] != true;
            
            if (isSegmentActive) {
              if (runStart == null) {
                double leftRatio = c == 0 ? 0.0 : vPositions[c - 1];
                runStart = glassR.left + (glassR.width * leftRatio);
              }
              
              bool isLast = (c == cols - 1) || (zone.disabledHorizontalDivisions[getHKey(c + 1, h)] == true);
              if (isLast) {
                double rightRatio = c == cols - 1 ? 1.0 : vPositions[c];
                double right = glassR.left + (glassR.width * rightRatio);
                
                double left = runStart;
                if (runStart > glassR.left) left -= dividerT / 2;
                if (right < glassR.right) right += dividerT / 2;
                
                fillRects.add(Rect.fromLTRB(left, y - dividerT / 2, right, y + dividerT / 2));
                runStart = null;
              }
            } else {
              runStart = null;
            }
          }
        }
      }

      if (vPositions.isNotEmpty) {
        for (int v = 0; v < vPositions.length; v++) {
          double x = glassR.left + (glassR.width * vPositions[v]);
          for (int r = 0; r < rows; r++) {
            final vKey = getVKey(r, v);
            if (zone.disabledVerticalDivisions[vKey] == true) {
              continue;
            }
            
            double topRatio = r == 0 ? 0.0 : hPositions[r - 1];
            double bottomRatio = r == rows - 1 ? 1.0 : hPositions[r];
            
            double top = glassR.top + (glassR.height * topRatio);
            double bottom = glassR.top + (glassR.height * bottomRatio);
            
            double topYVal = top;
            if (r == 0) {
              topYVal = getSashTopY(x, glassR.top - sashT, t, topOffset, isTopBound) + sashT;
            } else {
              bool hasActiveHAbove = zone.disabledHorizontalDivisions[getHKey(v, r - 1)] != true ||
                                     (v < vPositions.length && zone.disabledHorizontalDivisions[getHKey(v + 1, r - 1)] != true);
              if (hasActiveHAbove) {
                topYVal += dividerT / 2;
              }
            }
            
            double bottomYVal = bottom;
            if (r < rows - 1) {
              bool hasActiveHBelow = zone.disabledHorizontalDivisions[getHKey(v, r)] != true ||
                                     (v < vPositions.length && zone.disabledHorizontalDivisions[getHKey(v + 1, r)] != true);
              if (hasActiveHBelow) {
                bottomYVal -= dividerT / 2;
              }
            }
            
            fillRects.add(Rect.fromLTRB(x - dividerT / 2, topYVal, x + dividerT / 2, bottomYVal));
          }
        }
      }
    } else {
      // ==========================================
      // Vertical is Primary (continuous)
      // ==========================================
      if (vPositions.isNotEmpty) {
        for (int v = 0; v < vPositions.length; v++) {
          double x = glassR.left + (glassR.width * vPositions[v]);
          double? runStartTop;
          
          for (int r = 0; r < rows; r++) {
            final vKey = getVKey(r, v);
            bool isSegmentActive = zone.disabledVerticalDivisions[vKey] != true;
            
            if (isSegmentActive) {
              if (runStartTop == null) {
                double topRatio = r == 0 ? 0.0 : hPositions[r - 1];
                double top = glassR.top + (glassR.height * topRatio);
                if (r == 0) {
                  runStartTop = getSashTopY(x, glassR.top - sashT, t, topOffset, isTopBound) + sashT;
                } else {
                  runStartTop = top;
                }
              }
              
              bool isLast = (r == rows - 1) || (zone.disabledVerticalDivisions[getVKey(r + 1, v)] == true);
              if (isLast) {
                double bottomRatio = r == rows - 1 ? 1.0 : hPositions[r];
                double bottom = glassR.top + (glassR.height * bottomRatio);
                
                double topYVal = runStartTop;
                double bottomYVal = bottom;
                
                if (r > 0) topYVal -= dividerT / 2;
                if (r < rows - 1) bottomYVal += dividerT / 2;
                
                fillRects.add(Rect.fromLTRB(x - dividerT / 2, topYVal, x + dividerT / 2, bottomYVal));
                runStartTop = null;
              }
            } else {
              runStartTop = null;
            }
          }
        }
      }
      
      if (hPositions.isNotEmpty) {
        for (int h = 0; h < hPositions.length; h++) {
          double y = glassR.top + (glassR.height * hPositions[h]);
          for (int c = 0; c < cols; c++) {
            final hKey = getHKey(c, h);
            if (zone.disabledHorizontalDivisions[hKey] == true) {
              continue;
            }
            
            double leftRatio = c == 0 ? 0.0 : vPositions[c - 1];
            double rightRatio = c == cols - 1 ? 1.0 : vPositions[c];
            
            double left = glassR.left + (glassR.width * leftRatio);
            double right = glassR.left + (glassR.width * rightRatio);
            
            double leftXVal = left;
            if (c > 0) {
              bool hasVLeft = zone.disabledVerticalDivisions[getVKey(h, c - 1)] != true ||
                              (h < hPositions.length && zone.disabledVerticalDivisions[getVKey(h + 1, c - 1)] != true);
              if (hasVLeft) {
                leftXVal += dividerT / 2;
              }
            }
            
            double rightXVal = right;
            if (c < cols - 1) {
              bool hasVRight = zone.disabledVerticalDivisions[getVKey(h, c)] != true ||
                               (h < hPositions.length && zone.disabledVerticalDivisions[getVKey(h + 1, c)] != true);
              if (hasVRight) {
                rightXVal -= dividerT / 2;
              }
            }
            
            fillRects.add(Rect.fromLTRB(leftXVal, y - dividerT / 2, rightXVal, y + dividerT / 2));
          }
        }
      }
    }

    for (var rect in fillRects) {
      canvas.drawRect(rect, paint);
      canvas.drawRect(rect, border);
    }

    // Highlighting for inner division
    if (model.selection.type == SelectionType.innerDivision &&
        model.selection.zoneId == zone.id) {
      final isHSelected = model.selection.isHorizontalInnerDivision ?? false;
      final isRightSelected = model.selection.isRightSashInnerDivision ?? false;
      final selectedIdx = model.selection.innerDivisionIndex ?? -1;

      if (isRightSash == isRightSelected && selectedIdx != -1) {
        final highlightPaint = Paint()
          ..color = Colors.green.shade600.withValues(alpha: 0.5)
          ..style = PaintingStyle.fill;

        if (isHSelected && selectedIdx < hPositions.length) {
          double y = glassR.top + (glassR.height * hPositions[selectedIdx]);
          canvas.drawRect(
            Rect.fromLTRB(
              glassR.left,
              y - dividerT / 2,
              glassR.right,
              y + dividerT / 2,
            ),
            highlightPaint,
          );
        } else if (!isHSelected && selectedIdx < vPositions.length) {
          double x = glassR.left + (glassR.width * vPositions[selectedIdx]);
          double topYVal =
              getSashTopY(x, glassR.top - sashT, t, topOffset, isTopBound) +
              sashT;
          canvas.drawRect(
            Rect.fromLTRB(
              x - dividerT / 2,
              topYVal,
              x + dividerT / 2,
              glassR.bottom,
            ),
            highlightPaint,
          );
        }
      }
    }

    // Greedy cell merging
    final mergedCells = <_MergedCell>[];
    final visited = List.generate(
      rows,
      (_) => List.generate(cols, (_) => false),
    );

    for (int r = 0; r < rows; r++) {
      for (int c = 0; c < cols; c++) {
        if (visited[r][c]) continue;

        int w = 1;
        while (c + w < cols &&
            zone.disabledVerticalDivisions[getVKey(r, c + w - 1)] == true) {
          w++;
        }

        int h = 1;
        while (r + h < rows) {
          bool canMergeRow = true;
          for (int col = c; col < c + w; col++) {
            if (zone.disabledHorizontalDivisions[getHKey(col, r + h - 1)] !=
                true) {
              canMergeRow = false;
              break;
            }
          }
          if (!canMergeRow) break;

          for (int col = c; col < c + w - 1; col++) {
            if (zone.disabledVerticalDivisions[getVKey(r + h, col)] != true) {
              canMergeRow = false;
              break;
            }
          }
          if (!canMergeRow) break;

          h++;
        }

        for (int currR = r; currR < r + h; currR++) {
          for (int currC = c; currC < c + w; currC++) {
            visited[currR][currC] = true;
          }
        }

        double topRatio = r == 0 ? 0.0 : hPositions[r - 1];
        double bottomRatio = r + h - 1 == rows - 1
            ? 1.0
            : hPositions[r + h - 1];
        double leftRatio = c == 0 ? 0.0 : vPositions[c - 1];
        double rightRatio = c + w - 1 == cols - 1 ? 1.0 : vPositions[c + w - 1];

        double top = glassR.top + (glassR.height * topRatio);
        if (r > 0) top += dividerT / 2;
        double bottom = glassR.top + (glassR.height * bottomRatio);
        if (r + h - 1 < rows - 1) bottom -= dividerT / 2;

        double left = glassR.left + (glassR.width * leftRatio);
        if (c > 0) left += dividerT / 2;
        double right = glassR.left + (glassR.width * rightRatio);
        if (c + w - 1 < cols - 1) right -= dividerT / 2;

        Rect cellRect = Rect.fromLTRB(left, top, right, bottom);
        String cellKey = '${sidePrefix}_cell_${r}_$c';

        mergedCells.add(
          _MergedCell(
            row: r,
            col: c,
            hSpan: h,
            wSpan: w,
            rect: cellRect,
            key: cellKey,
          ),
        );
      }
    }

    // Paint merged cells
    for (var cell in mergedCells) {
      if (cell.rect.width > 4 && cell.rect.height > 4) {
        if (zone.cellIsSash[cell.key] == true) {
          double? cellSashThickness;
          bool isSash105 = zone.isSash105;
          if (zone.cellSashOverrides[cell.key] != null) {
            cellSashThickness =
                (zone.cellSashOverrides[cell.key]!['visible_width'] as num?)
                    ?.toDouble();
            final code =
                zone.cellSashOverrides[cell.key]!['code']
                    ?.toString()
                    .toLowerCase() ??
                '';
            final name =
                zone.cellSashOverrides[cell.key]!['name']
                    ?.toString()
                    .toLowerCase() ??
                '';
            if (code.contains('104') || name.contains('104')) {
              isSash105 = false;
            } else if (code.contains('105') ||
                code.contains('porte') ||
                code.contains('ouvr') ||
                name.contains('105') ||
                name.contains('porte') ||
                name.contains('ouvr') ||
                name.contains('بورت')) {
              isSash105 = true;
            }
          }

          OpenDirection cellOpenDirection = OpenDirection.left;
          if (zone.cellSashOverrides[cell.key] != null &&
              zone.cellSashOverrides[cell.key]!['openDirection'] != null) {
            final dirStr = zone.cellSashOverrides[cell.key]!['openDirection']
                .toString();
            cellOpenDirection = OpenDirection.values.firstWhere(
              (d) => d.name == dirStr,
              orElse: () => OpenDirection.left,
            );
          }

          final nestedSashZone = WindowZone(
            id: '${zone.id}_nested_${cell.key}',
            boundary: cell.rect,
            content: ZoneContent.singleSash,
            sashColor: zone.sashColor,
            openDirection: cellOpenDirection,
            glass: zone.glass,
            isSash105: isSash105,
            sashThickness: cellSashThickness,
          );
          _renderSash(
            canvas,
            cell.rect,
            nestedSashZone,
            cell.rect,
            forceHandle: true,
            isRightSash: false,
          );
        } else if (zone.cellIsDoubleSash[cell.key] == true) {
          final sep = 4.0;
          final midX = cell.rect.left + cell.rect.width * 0.5;
          final leftR = Rect.fromLTRB(
            cell.rect.left,
            cell.rect.top,
            midX - sep / 2,
            cell.rect.bottom,
          );
          final rightR = Rect.fromLTRB(
            midX + sep / 2,
            cell.rect.top,
            cell.rect.right,
            cell.rect.bottom,
          );

          double? cellSashThickness;
          bool isSash105 = zone.isSash105;
          if (zone.cellSashOverrides[cell.key] != null) {
            cellSashThickness =
                (zone.cellSashOverrides[cell.key]!['visible_width'] as num?)
                    ?.toDouble();
            final code =
                zone.cellSashOverrides[cell.key]!['code']
                    ?.toString()
                    .toLowerCase() ??
                '';
            final name =
                zone.cellSashOverrides[cell.key]!['name']
                    ?.toString()
                    .toLowerCase() ??
                '';
            if (code.contains('104') || name.contains('104')) {
              isSash105 = false;
            } else if (code.contains('105') ||
                code.contains('porte') ||
                code.contains('ouvr') ||
                name.contains('105') ||
                name.contains('porte') ||
                name.contains('ouvr') ||
                name.contains('بورت')) {
              isSash105 = true;
            }
          }

          OpenDirection cellOpenDirection = OpenDirection.right;
          if (zone.cellSashOverrides[cell.key] != null &&
              zone.cellSashOverrides[cell.key]!['openDirection'] != null) {
            final dirStr = zone.cellSashOverrides[cell.key]!['openDirection']
                .toString();
            cellOpenDirection = OpenDirection.values.firstWhere(
              (d) => d.name == dirStr,
              orElse: () => OpenDirection.right,
            );
          }
          bool isLeftActive = (cellOpenDirection == OpenDirection.left);
          bool isRightActive = (cellOpenDirection == OpenDirection.right);

          final nestedSashZoneLeft = WindowZone(
            id: '${zone.id}_nested_${cell.key}_L',
            boundary: leftR,
            content: ZoneContent.doubleSash,
            sashColor: zone.sashColor,
            openDirection: OpenDirection.right,
            glass: zone.glass,
            isSash105: isSash105,
            sashThickness: cellSashThickness,
          );
          final nestedSashZoneRight = WindowZone(
            id: '${zone.id}_nested_${cell.key}_R',
            boundary: rightR,
            content: ZoneContent.doubleSash,
            sashColor: zone.sashColor,
            openDirection: OpenDirection.left,
            glass: zone.glass,
            isSash105: isSash105,
            sashThickness: cellSashThickness,
          );

          _renderSash(
            canvas,
            leftR,
            nestedSashZoneLeft,
            leftR,
            forceHandle: isLeftActive,
            isRightSash: false,
          );
          _renderSash(
            canvas,
            rightR,
            nestedSashZoneRight,
            rightR,
            forceHandle: isRightActive,
            isRightSash: true,
          );

          final sepPaint = Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = sep;
          if (_isWoodColor() && TextureCache.woodTexture != null) {
            _applyWoodShader(sepPaint, glassR);
          } else {
            sepPaint.color = _fc[1];
          }

          canvas.drawLine(
            Offset(midX, cell.rect.top),
            Offset(midX, cell.rect.bottom),
            sepPaint,
          );
        } else {
          final cellSpec = zone.getGlassForCell(cell.key);
          if (cellSpec.structure == GlassStructure.closed) {
            _drawPanelTexture(
              canvas,
              cell.rect,
              color,
              zone: zone,
              spec: cellSpec,
              t: t,
              topOffset: topOffset,
              isTopBound: isTopBound && cell.row == 0,
            );
          } else {
            // Draw glass separately for this cell so that it is segmented
            _drawFixedGlass(
              canvas,
              cell.rect,
              cellSpec,
              t,
              topOffset,
              isTopBound && cell.row == 0,
            );
          }
          _drawRealisticParclose(
            canvas,
            cell.rect,
            color,
            customThickness: 4.0,
            t: t,
            topOffset: topOffset,
            isTopBound: isTopBound && cell.row == 0,
          );
        }


        // Highlight active subzone
        bool isSelected = false;
        if (model.selectedZone?.id == zone.id && model.activeSubZone != null) {
          if (model.activeSubZone == cell.key) {
            isSelected = true;
          } else if (model.activeSubZone!.startsWith('${sidePrefix}_cell_')) {
            final suffix = model.activeSubZone!.substring(
              '${sidePrefix}_cell_'.length,
            );
            final parts = suffix.split('_');
            if (parts.length == 2) {
              final activeR = int.tryParse(parts[0]);
              final activeC = int.tryParse(parts[1]);
              if (activeR != null && activeC != null) {
                if (activeR >= cell.row &&
                    activeR < cell.row + cell.hSpan &&
                    activeC >= cell.col &&
                    activeC < cell.col + cell.wSpan) {
                  isSelected = true;
                }
              }
            }
          }
        }

        if (isSelected) {
          final cellPath = _buildGlassLayerPath(
            cell.rect,
            t,
            topOffset,
            isTopBound && cell.row == 0,
          );
          canvas.drawPath(
            cellPath,
            Paint()
              ..color = Colors.green.shade700.withValues(alpha: 0.4)
              ..style = PaintingStyle.fill,
          );
        }
      }
    }

    // Cell width and height labels
    final textStyle = const TextStyle(
      color: Color(0xFF1565C0),
      fontSize: 42,
      fontWeight: FontWeight.bold,
    );

    for (var cell in mergedCells) {
      if (cols > 1 || cell.wSpan > 1) {
        final cellW = cell.rect.width;
        final widthText = TextPainter(
          text: TextSpan(text: "${cellW.toInt()}", style: textStyle),
          textDirection: TextDirection.ltr,
        )..layout();
        bool isBottomBound =
            (cell.rect.bottom -
                    (model.height - (model.hasBottomFrame ? t : 0.0)))
                .abs() <
            5.0;
        final double labelY = (_isSlantedOrArched && isBottomBound)
            ? (model.height + 10.0)
            : (cell.rect.bottom - widthText.height - 12.0);
        final wOffset = Offset(
          cell.rect.left + (cellW - widthText.width) / 2,
          labelY,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(
              wOffset.dx - 4,
              wOffset.dy - 1,
              widthText.width + 8,
              widthText.height + 2,
            ),
            const Radius.circular(4),
          ),
          Paint()..color = Colors.white.withValues(alpha: 0.85),
        );
        widthText.paint(canvas, wOffset);
      }

      if (rows > 1 || cell.hSpan > 1) {
        final cellH = cell.rect.height;
        final heightText = TextPainter(
          text: TextSpan(text: "${cellH.toInt()}", style: textStyle),
          textDirection: TextDirection.ltr,
        )..layout();
        double left = cell.rect.left;
        canvas.save();
        canvas.translate(
          left + 5 + heightText.height,
          cell.rect.top + (cellH + heightText.width) / 2,
        );
        canvas.rotate(-3.1415926535897932 / 2);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(
              -4,
              -heightText.height - 1,
              heightText.width + 8,
              heightText.height + 2,
            ),
            const Radius.circular(4),
          ),
          Paint()..color = Colors.white.withValues(alpha: 0.85),
        );
        heightText.paint(canvas, Offset(0, -heightText.height));
        canvas.restore();
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
    final double t = model.profileThickness;
    final double topOffset = _topOffset;
    final bool isTopBound = _isTopZone(zone);

    // 🟢 الظلفة تأخذ العرض الفعلي من القاعدة
    final double sashT =
        zone.sashThickness ?? model.getSectionThickness('sash', fallback: 45.0);
    final glassR = _getSafeGlassRect(sashR, sashT, hasSashPlintheBottom: zone.hasSashPlintheBottom);

    final String sidePrefix = zone.content == ZoneContent.doubleSash
        ? (isRightSash ? 'right' : 'left')
        : 'main';
    final String cellKey = '${sidePrefix}_cell_0_0';
    final cellSpec = zone.getGlassForCell(cellKey);

    final bool isDecorPanel =
        (cellSpec.structure == GlassStructure.closed &&
        ((overrideIsInternalView ?? model.isInternalView)
            ? cellSpec.finishInner == GlassFinish.paneauSandwitchDecore
            : cellSpec.finishOuter == GlassFinish.paneauSandwitchDecore));

    if (isDecorPanel) {
      _drawPanelTexture(
        canvas,
        sashR,
        model.frameColor,
        finish: GlassFinish.paneauSandwitchDecore,
        zone: zone,
        spec: cellSpec,
        t: t,
        topOffset: topOffset,
        isTopBound: isTopBound,
        isInsideSash: true,
        sashTop: sashR.top,
        topW: 0.0,
      );
    } else {
      if (cellSpec.structure == GlassStructure.closed) {
        _drawPanelTexture(
          canvas,
          glassR,
          model.frameColor,
          finish: (overrideIsInternalView ?? model.isInternalView)
              ? cellSpec.finishInner
              : cellSpec.finishOuter,
          zone: zone,
          spec: cellSpec,
          t: t,
          topOffset: topOffset,
          isTopBound: isTopBound,
          isInsideSash: true,
          sashTop: sashR.top,
          topW: glassR.top - sashR.top,
        );
      } else {
        _drawFixedGlass(
          canvas,
          glassR,
          cellSpec,
          t,
          topOffset,
          isTopBound,
          isInsideSash: true,
          sashTop: sashR.top,
          topW: glassR.top - sashR.top,
        );
      }
      _drawInternalDivisions(
        canvas,
        glassR,
        isRightSash ? zone.rightInnerH : zone.innerH,
        isRightSash ? zone.rightInnerV : zone.innerV,
        isRightSash ? zone.rightInnerHPositions : zone.innerHPositions,
        isRightSash ? zone.rightInnerVPositions : zone.innerVPositions,
        zone.sashColor,
        sashT,
        zone,
        isRightSash,
        isTopBound,
      );
      _drawSashFrameRect(
        canvas,
        sashR,
        glassR,
        zone.sashColor,
        zone.selectedDbColor,
        dimmed: false,
        t: t,
        topOffset: topOffset,
        isTopBound: isTopBound,
        hasSashPlintheBottom: zone.hasSashPlintheBottom,
      );
    }

    final isInternal = overrideIsInternalView ?? model.isInternalView;
    final bool hasLock = zone.lockType == LockType.clef ||
        zone.lockType == LockType.condamnation;
    
    bool has104105Option = false;
    if (model.activeSeries != null) {
      for (var sec in model.activeSeries!.sections) {
        if (sec.code.contains('104') || sec.code.contains('105')) {
          has104105Option = true;
          break;
        }
      }
    }
    bool isDoorHandle = false;
    if (has104105Option) {
      isDoorHandle = (zone.isSash105 == true) || hasLock;
    } else {
      if (model.isPVC) {
        isDoorHandle = (zone.isSash105 == true) || (sashT > 60.0) || hasLock;
      } else {
        isDoorHandle = (zone.isSash105 == true) || (sashT > 50.0) || hasLock;
      }
    }
    if (zone.content == ZoneContent.slidingSash) {
      isDoorHandle = false;
    }
    if (zone.lockType == LockType.none || zone.useOctoHandle == true || zone.usePvcHandleOnAlu == true) {
      isDoorHandle = false;
    }

    final bool shouldDrawHandle = isInternal || (isDoorHandle && zone.content == ZoneContent.doubleSash);

    if (shouldDrawHandle && zone.openDirection != null) {
      if (isInternal) {
        bool hingesOnRight = (zone.openDirection == OpenDirection.left);
        bool hingesOnLeft = (zone.openDirection == OpenDirection.right);
        _drawHinges(
          canvas,
          sashR,
          hingesOnRight,
          hingesOnLeft,
          (zone.openDirection == OpenDirection.bottom),
          (zone.openDirection == OpenDirection.top),
          zone,
          forceHandle,
          t: t,
          topOffset: topOffset,
          isTopBound: isTopBound,
        );
      }
      if (forceHandle) {
        OpenDirection handleSide = zone.openDirection!;
        if (!isInternal) {
          if (handleSide == OpenDirection.left) {
            handleSide = OpenDirection.right;
          } else if (handleSide == OpenDirection.right) {
            handleSide = OpenDirection.left;
          }
        }
        _drawWindowDrawHandle(
          canvas,
          sashR,
          handleSide,
          zone.handlePositionRatio ?? 0.5,
          t: t,
          topOffset: topOffset,
          isTopBound: isTopBound,
          zone: zone,
        );
      }
    }
  }

  double _getSlidingSectionWidth(String typeName, String fallbackName, double defaultVal) {
    final series = model.activeSlidingSeries ?? model.activeSeries;
    if (series == null) return defaultVal;

    final String tName = typeName.toLowerCase();
    String? altType;
    if (tName == 'traverse') {
      altType = 'sash_traverse';
    } else if (tName == 'chicane' || tName == 'central' || tName == 'centrale') {
      altType = 'sash_central';
    } else if (tName == 'lateral') {
      altType = 'sash_lateral';
    }
    
    // 1. Try to find by type
    for (var sec in series.sections) {
      final secType = sec.type.toLowerCase();
      if (secType == tName || (altType != null && secType == altType)) {
        if (sec.visibleWidth > 0) return sec.visibleWidth;
        if (sec.thickness > 0) return sec.thickness;
      }
    }
    // 2. Try to find by name/code containing typeName, fallbackName, or altType
    for (var sec in series.sections) {
      final n = sec.name.toLowerCase();
      final c = sec.code.toLowerCase();
      if (n.contains(tName) || 
          c.contains(tName) ||
          n.contains(fallbackName.toLowerCase()) ||
          c.contains(fallbackName.toLowerCase()) ||
          (altType != null && (n.contains(altType) || c.contains(altType)))) {
        if (sec.visibleWidth > 0) return sec.visibleWidth;
        if (sec.thickness > 0) return sec.thickness;
      }
    }
    return defaultVal;
  }

  bool _is90DegreeSystem() {
    String seriesName =
        (model.activeSeries?.name ?? model.loadedSeriesName ?? "")
            .toLowerCase();
    String slidingSeriesName =
        (model.activeSlidingSeries?.name ?? model.loadedSlidingSeriesName ?? "")
            .toLowerCase();
    return seriesName.contains('tpr') ||
        seriesName.contains('hps') ||
        seriesName.contains('hbs') ||
        seriesName.contains('h30') ||
        seriesName.contains('h31') ||
        seriesName.contains('h36') ||
        seriesName.contains('67000') ||
        slidingSeriesName.contains('tpr') ||
        slidingSeriesName.contains('hps') ||
        slidingSeriesName.contains('hbs') ||
        slidingSeriesName.contains('h30') ||
        slidingSeriesName.contains('h31') ||
        slidingSeriesName.contains('h36') ||
        slidingSeriesName.contains('67000');
  }

  void _drawSashFrameRect(
    Canvas canvas,
    Rect sashR,
    Rect glassR,
    FrameColor color,
    Map<String, dynamic>? dbColor, {
    required bool dimmed,
    bool isSlidingSash = false,
    required double t,
    required double topOffset,
    required bool isTopBound,
    bool hasSashPlintheBottom = false,
  }) {
    final Path sashPath = Path();
    final Path glassPath = Path();

    // Use actual top profile thickness instead of average sashT
    final double topW = glassR.top - sashR.top;
    final double sashT = (sashR.width - glassR.width) / 2;

    double ySashL = getSashTopY(
      sashR.left,
      sashR.top,
      t,
      topOffset,
      isTopBound,
    );
    double ySashR = getSashTopY(
      sashR.right,
      sashR.top,
      t,
      topOffset,
      isTopBound,
    );
    sashPath.moveTo(sashR.left, sashR.bottom);
    sashPath.lineTo(sashR.left, ySashL);
    if (model.archHeight > 0 && isTopBound) {
      double ySashMid = getSashTopY(
        (sashR.left + sashR.right) / 2,
        sashR.top,
        t,
        topOffset,
        isTopBound,
      );
      double ySashC = 2 * ySashMid - 0.5 * (ySashL + ySashR);
      sashPath.quadraticBezierTo(
        (sashR.left + sashR.right) / 2,
        ySashC,
        sashR.right,
        ySashR,
      );
    } else {
      sashPath.lineTo(sashR.right, ySashR);
    }
    sashPath.lineTo(sashR.right, sashR.bottom);
    sashPath.close();

    double yGlassL =
        getSashTopY(glassR.left, sashR.top, t, topOffset, isTopBound) + topW;
    double yGlassR =
        getSashTopY(glassR.right, sashR.top, t, topOffset, isTopBound) + topW;
    glassPath.moveTo(glassR.left, glassR.bottom);
    glassPath.lineTo(glassR.left, yGlassL);
    if (model.archHeight > 0 && isTopBound) {
      double yGlassMid =
          getSashTopY(
            (glassR.left + glassR.right) / 2,
            sashR.top,
            t,
            topOffset,
            isTopBound,
          ) +
          topW;
      double yGlassC = 2 * yGlassMid - 0.5 * (yGlassL + yGlassR);
      glassPath.quadraticBezierTo(
        (glassR.left + glassR.right) / 2,
        yGlassC,
        glassR.right,
        yGlassR,
      );
    } else {
      glassPath.lineTo(glassR.right, yGlassR);
    }
    glassPath.lineTo(glassR.right, glassR.bottom);
    glassPath.close();

    final Path framePath = Path()
      ..addPath(sashPath, Offset.zero)
      ..addPath(glassPath, Offset.zero)
      ..fillType = PathFillType.evenOdd;

    canvas.drawPath(framePath, _buildPaint(sashR, gradientColors: _fc));
    canvas.drawPath(
      sashPath,
      Paint()
        ..color = _fb
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0,
    );
    canvas.drawPath(
      glassPath,
      Paint()
        ..color = _fb
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8,
    );
    canvas.drawPath(
      glassPath,
      Paint()
        ..color = Colors.black26
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0,
    );
    canvas.drawPath(
      glassPath,
      Paint()
        ..color = const Color(0xFF1A1A1A)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );

    final mp = Paint()
      ..color = Color.lerp(_fc.last, Colors.black, 0.4)!
      ..strokeWidth = 1.2;

    if (isSlidingSash && _is90DegreeSystem()) {
      canvas.drawLine(
        Offset(glassR.left, ySashL),
        Offset(glassR.left, yGlassL),
        mp,
      );
      canvas.drawLine(
        Offset(glassR.right, ySashR),
        Offset(glassR.right, yGlassR),
        mp,
      );
      canvas.drawLine(
        Offset(glassR.left, glassR.bottom),
        Offset(glassR.left, sashR.bottom),
        mp,
      );
      canvas.drawLine(
        Offset(glassR.right, glassR.bottom),
        Offset(glassR.right, sashR.bottom),
        mp,
      );
    } else {
      canvas.drawLine(
        Offset(sashR.left, ySashL),
        Offset(glassR.left, yGlassL),
        mp,
      );
      canvas.drawLine(
        Offset(sashR.right, ySashR),
        Offset(glassR.right, yGlassR),
        mp,
      );
      if (hasSashPlintheBottom) {
        canvas.drawLine(
          Offset(glassR.left, glassR.bottom),
          Offset(glassR.left, sashR.bottom),
          mp,
        );
        canvas.drawLine(
          Offset(glassR.right, glassR.bottom),
          Offset(glassR.right, sashR.bottom),
          mp,
        );
      } else {
        canvas.drawLine(sashR.bottomLeft, glassR.bottomLeft, mp);
        canvas.drawLine(sashR.bottomRight, glassR.bottomRight, mp);
      }
    }
  }

  bool _isHandleSashProfile(WindowZone? zone) {
    if (zone == null) return false;
    if (model.sashOverride != null) {
      final name = model.sashOverride!['name']?.toString().toLowerCase() ?? '';
      final code = model.sashOverride!['code']?.toString().toLowerCase() ?? '';
      if (name.contains('مقبض') ||
          name.contains('poignée') ||
          name.contains('handle') ||
          code.contains('مقبض') ||
          code.contains('poignée') ||
          code.contains('handle')) {
        return true;
      }
    }
    return false;
  }

  void _drawWindowDrawHandle(
    Canvas canvas,
    Rect sashRect,
    OpenDirection handleSide,
    double ratio, {
    required double t,
    required double topOffset,
    required bool isTopBound,
    WindowZone? zone,
  }) {
    double handleY = sashRect.center.dy;
    double x = sashRect.center.dx;
    if (handleSide == OpenDirection.left) {
      x = sashRect.left + 20;
      double topYVal = getSashTopY(x, sashRect.top, t, topOffset, isTopBound);
      handleY = topYVal + ((sashRect.bottom - topYVal) * (1.0 - ratio));
    } else if (handleSide == OpenDirection.right) {
      x = sashRect.right - 20;
      double topYVal = getSashTopY(x, sashRect.top, t, topOffset, isTopBound);
      handleY = topYVal + ((sashRect.bottom - topYVal) * (1.0 - ratio));
    } else if (handleSide == OpenDirection.top) {
      x = sashRect.left + (sashRect.width * ratio);
      double topYVal = getSashTopY(x, sashRect.top, t, topOffset, isTopBound);
      handleY = topYVal + 22;
    } else if (handleSide == OpenDirection.bottom) {
      handleY = sashRect.bottom - 22;
      x = sashRect.left + (sashRect.width * ratio);
    }

    final Color accessoryColor = model.accessoryColor;
    final Paint basePaint = Paint()
      ..color = accessoryColor
      ..style = PaintingStyle.fill;
    final Paint borderPaint = Paint()
      ..color = Colors.black87
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;

    if (zone?.lockType == LockType.point) {
      Rect sashPart;
      Rect framePart;
      Offset knobCenter;

      if (handleSide == OpenDirection.top) {
        final double topYVal = getSashTopY(x, sashRect.top, t, topOffset, isTopBound);
        sashPart = Rect.fromLTRB(x - 16, topYVal, x + 16, topYVal + 10);
        framePart = Rect.fromLTRB(x - 16, topYVal - 10, x + 16, topYVal);
        knobCenter = Offset(x, topYVal + 5);
      } else if (handleSide == OpenDirection.bottom) {
        sashPart = Rect.fromLTRB(x - 16, sashRect.bottom - 10, x + 16, sashRect.bottom);
        framePart = Rect.fromLTRB(x - 16, sashRect.bottom, x + 16, sashRect.bottom + 10);
        knobCenter = Offset(x, sashRect.bottom - 5);
      } else if (handleSide == OpenDirection.left) {
        sashPart = Rect.fromLTRB(sashRect.left, handleY - 16, sashRect.left + 10, handleY + 16);
        framePart = Rect.fromLTRB(sashRect.left - 10, handleY - 16, sashRect.left, handleY + 16);
        knobCenter = Offset(sashRect.left + 5, handleY);
      } else { // OpenDirection.right
        sashPart = Rect.fromLTRB(sashRect.right - 10, handleY - 16, sashRect.right, handleY + 16);
        framePart = Rect.fromLTRB(sashRect.right, handleY - 16, sashRect.right + 10, handleY + 16);
        knobCenter = Offset(sashRect.right - 5, handleY);
      }

      // Draw Sash part (casing)
      final RRect sashRRect = RRect.fromRectAndRadius(sashPart, const Radius.circular(2));
      canvas.drawRRect(sashRRect, basePaint);
      canvas.drawRRect(sashRRect, borderPaint);

      // Draw Frame part (keeper bracket)
      final RRect frameRRect = RRect.fromRectAndRadius(framePart, const Radius.circular(2));
      canvas.drawRRect(frameRRect, basePaint);
      canvas.drawRRect(frameRRect, borderPaint);

      // Draw central pull knob (circle button - the "point/dot" itself) on the sash part
      canvas.drawCircle(knobCenter, 5.5, Paint()..color = Colors.black87..style = PaintingStyle.fill);
      canvas.drawCircle(knobCenter, 3.5, Paint()..color = Colors.grey[300]!..style = PaintingStyle.fill);
      canvas.drawCircle(knobCenter, 1.2, Paint()..color = Colors.black87..style = PaintingStyle.fill);

      return;
    }

    double px = x;
    double py = handleY;

    final double sashT =
        zone?.sashThickness ??
        model.getSectionThickness('sash', fallback: 45.0);
    bool isDoorHandle = false;

    bool has104105Option = false;
    if (model.activeSeries != null) {
      for (var sec in model.activeSeries!.sections) {
        if (sec.code.contains('104') || sec.code.contains('105')) {
          has104105Option = true;
          break;
        }
      }
    }

    final bool hasLock = zone?.lockType == LockType.clef ||
        zone?.lockType == LockType.condamnation;

    if (has104105Option) {
      isDoorHandle = (zone?.isSash105 == true) || hasLock;
    } else {
      if (model.isPVC) {
        isDoorHandle = (zone?.isSash105 == true) || (sashT > 60.0) || hasLock;
      } else {
        isDoorHandle = (zone?.isSash105 == true) || (sashT > 50.0) || hasLock;
      }
    }

    if (zone?.content == ZoneContent.slidingSash) {
      if (model.isPVC) {
        isDoorHandle = true;
      } else {
        isDoorHandle = false;
      }
    }
    if (zone?.lockType == LockType.none || zone?.useOctoHandle == true || zone?.usePvcHandleOnAlu == true) {
      if (zone?.content != ZoneContent.slidingSash || !model.isPVC) {
        isDoorHandle = false;
      }
    }

    // Cremone transmission rods: not drawn (disabled per design)
    // isCremone = true only for Aluminium sashes (not PVC)
    final bool isCremone = !model.isPVC &&
        (zone?.content == ZoneContent.singleSash || zone?.content == ZoneContent.doubleSash) &&
        (zone?.lockType == LockType.none || zone?.lockType == LockType.cremone) &&
        zone?.useOctoHandle != true &&
        zone?.usePvcHandleOnAlu != true &&
        zone?.useClassicHandle != true;
    // Rods intentionally not rendered (isCremone used only for handle shape below)

    if (zone?.useOctoHandle == true) {
      if (handleSide == OpenDirection.top) {
        double topYVal = getSashTopY(x, sashRect.top, t, topOffset, isTopBound);
        py = topYVal;
      } else if (handleSide == OpenDirection.bottom) {
        py = sashRect.bottom;
      } else if (handleSide == OpenDirection.left) {
        px = sashRect.left;
      } else if (handleSide == OpenDirection.right) {
        px = sashRect.right;
      }
    }

    canvas.save();
    canvas.translate(px, py);
    if (zone?.useOctoHandle == true) {
      double angle = 0.0;
      if (handleSide == OpenDirection.left) {
        angle = math.pi / 2;
      } else if (handleSide == OpenDirection.right) {
        angle = -math.pi / 2;
      } else if (handleSide == OpenDirection.top) {
        angle = math.pi;
      } else if (handleSide == OpenDirection.bottom) {
        angle = 0.0;
      }
      canvas.rotate(angle);
    } else {
      if (handleSide == OpenDirection.top || handleSide == OpenDirection.bottom) {
        canvas.rotate(-math.pi / 2);
      }
    }

    bool isSlidingHandle = false;

    bool isClassicSlidingHandle =
        ((zone?.content == ZoneContent.slidingSash) ||
        _isHandleSashProfile(zone)) && !model.isPVC;

    final bool isMarechal = zone?.lockType == LockType.rouleau || zone?.lockType == LockType.rouleau2000;

    if (isMarechal) {
      if (sashRect.height < 1250.0) {
        canvas.restore();
        return;
      }

      final double handleHeight = (zone?.lockType == LockType.rouleau2000) ? 2000.0 : 1250.0;
      final double handleWidth = 24.0;
      final double postDistY = handleHeight / 2 - 150.0;

      final Paint postPaint = Paint()
        ..color = accessoryColor
        ..style = PaintingStyle.fill;
      final Paint postBorder = Paint()
        ..color = Colors.black87
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0;
      
      // Draw top and bottom posts connecting handle to door
      canvas.drawRect(Rect.fromCenter(center: Offset(0, -postDistY), width: 16, height: 16), postPaint);
      canvas.drawRect(Rect.fromCenter(center: Offset(0, -postDistY), width: 16, height: 16), postBorder);
      canvas.drawRect(Rect.fromCenter(center: Offset(0, postDistY), width: 16, height: 16), postPaint);
      canvas.drawRect(Rect.fromCenter(center: Offset(0, postDistY), width: 16, height: 16), postBorder);

      // Draw the main pull bar
      final RRect pullBar = RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset.zero, width: handleWidth, height: handleHeight),
        Radius.circular(handleWidth / 2),
      );
      canvas.drawRRect(pullBar, basePaint);
      canvas.drawRRect(pullBar, borderPaint);

      // Highlight line on the handle
      canvas.drawLine(
        Offset(-handleWidth / 4, -handleHeight / 2 + handleWidth / 2),
        Offset(-handleWidth / 4, handleHeight / 2 - handleWidth / 2),
        Paint()
          ..color = Colors.white.withValues(alpha: 0.5)
          ..strokeWidth = 3.0,
      );

      // Draw central lock casing
      final RRect lockCasing = RRect.fromRectAndRadius(
        Rect.fromCenter(center: const Offset(0, 0), width: 28, height: 50),
        const Radius.circular(4),
      );
      canvas.drawRRect(lockCasing, basePaint);
      canvas.drawRRect(lockCasing, borderPaint);

      // Draw keyhole
      canvas.drawCircle(const Offset(0, 10), 4.5, Paint()..color = Colors.black87);
      canvas.drawRect(Rect.fromLTRB(-2.5, 10, 2.5, 20), Paint()..color = Colors.black87);

      canvas.restore();
      return;
    }

    if (isDoorHandle) {
      final RRect basePlate = RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset.zero, width: 18, height: 90),
        const Radius.circular(9),
      );
      canvas.drawRRect(basePlate, basePaint);
      canvas.drawRRect(basePlate, borderPaint);

      double leverDirection = (handleSide == OpenDirection.left) ? 1.0 : -1.0;
      final RRect lever = RRect.fromRectAndRadius(
        Rect.fromLTRB(
          leverDirection == 1.0 ? -5 : -55,
          -8,
          leverDirection == 1.0 ? 55 : 5,
          8,
        ),
        const Radius.circular(6),
      );
      canvas.drawRRect(lever, basePaint);
      canvas.drawRRect(lever, borderPaint);

      canvas.drawLine(
        Offset(leverDirection == 1.0 ? 0 : -45, -2),
        Offset(leverDirection == 1.0 ? 45 : 0, -2),
        Paint()
          ..color = Colors.white
          ..strokeWidth = 2.0,
      );

      // Keyhole or turn knob below lever
      double keyholeY = 25.0;
      final bool isCondamnation = zone?.lockType == LockType.condamnation;
      if (isCondamnation) {
        canvas.drawCircle(
          Offset(0, keyholeY),
          7.0,
          Paint()
            ..color = Colors.grey[700]!
            ..style = PaintingStyle.fill,
        );
        canvas.drawCircle(
          Offset(0, keyholeY),
          5.0,
          Paint()
            ..color = Colors.white
            ..style = PaintingStyle.fill,
        );
        canvas.drawRect(
          Rect.fromCenter(center: Offset(0, keyholeY), width: 2, height: 10),
          Paint()
            ..color = Colors.grey[800]!
            ..style = PaintingStyle.fill,
        );
      } else {
        canvas.drawCircle(
          Offset(0, keyholeY),
          3.5,
          Paint()
            ..color = Colors.black87
            ..style = PaintingStyle.fill,
        );
        Path keyholeBody = Path()
          ..moveTo(-2.5, keyholeY + 2)
          ..lineTo(2.5, keyholeY + 2)
          ..lineTo(4, keyholeY + 12)
          ..lineTo(-4, keyholeY + 12)
          ..close();
        canvas.drawPath(
          keyholeBody,
          Paint()
            ..color = Colors.black87
            ..style = PaintingStyle.fill,
        );
      }
    } else if (isSlidingHandle) {
      // ─── Entrematique (sliding handle) ───────────────────────────────────
      //  Same flat rectangular sliding handle as before, but doubled in height
      //  (same width, double length).
      // ─────────────────────────────────────────────────────────────────────
      final RRect basePlate = RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset.zero, width: 18, height: 120),
        const Radius.circular(9),
      );
      canvas.drawRRect(basePlate, basePaint);
      canvas.drawRRect(basePlate, borderPaint);

      // Draw a vertical grab slot inside (double the height: 44 -> 88)
      final RRect slot = RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset.zero, width: 6, height: 88),
        const Radius.circular(3),
      );
      canvas.drawRRect(
        slot,
        Paint()
          ..color = Colors.black87
          ..style = PaintingStyle.fill,
      );

      // Draw a small slide button in the middle
      final RRect button = RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset.zero, width: 10, height: 12),
        const Radius.circular(2),
      );
      canvas.drawRRect(
        button,
        Paint()
          ..color = Colors.grey.shade400
          ..style = PaintingStyle.fill,
      );
      canvas.drawRRect(button, borderPaint);

    } else if (isClassicSlidingHandle) {
      // ─── Bawani Kodi – Z-shaped sliding handle ───────────────────────────
      //  Same original vertical base plate (18 × 60), then the grip:
      //    • starts EXACTLY from the CENTER/MIDDLE of the base plate (Offset.zero)
      //    • slants IMMEDIATELY at 45° downwards and towards the OPPOSITE handle
      //    • drops straight down to y = 120 (longer/prominent)
      //
      //  We draw the base plate FIRST, then draw the Z-shaped grip ON TOP.
      // ─────────────────────────────────────────────────────────────────────
      final double dir = (handleSide == OpenDirection.left) ? 1.0 : -1.0;

      const double plateW    = 18.0;
      const double plateH    = 60.0;
      const double gripThick = 17.0;

      // ── Step A: Draw the base plate FIRST ───────────────────────────────
      final RRect basePlate = RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset.zero, width: plateW, height: plateH),
        const Radius.circular(9),
      );
      canvas.drawRRect(basePlate, basePaint);
      canvas.drawRRect(basePlate, borderPaint);

      // Highlight stripe on base plate
      canvas.drawLine(
        Offset(-plateW / 4, -plateH / 2 + 9),
        Offset(-plateW / 4,  plateH / 2 - 9),
        Paint()
          ..color = Colors.white
          ..strokeWidth = 2.0,
      );

      // ── Step B: Draw the Z-shaped grip ON TOP ───────────────────────────
      final Offset p0 = Offset.zero;
      final Offset p1 = Offset(dir * 32.0, 32.0);  // 45 degrees slant directly from center
      final Offset p2 = Offset(p1.dx,      120.0); // straight down, longer

      final Path gripPath = Path()
        ..moveTo(p0.dx, p0.dy)
        ..lineTo(p1.dx, p1.dy)
        ..lineTo(p2.dx, p2.dy);

      // Draw grip border
      canvas.drawPath(
        gripPath,
        Paint()
          ..color = Colors.black87
          ..style = PaintingStyle.stroke
          ..strokeWidth = gripThick + 2.4
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );

      // Draw grip fill (accessory color)
      canvas.drawPath(
        gripPath,
        Paint()
          ..color = accessoryColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = gripThick
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );

      // Highlight stripe along the grip (following the path)
      canvas.drawPath(
        Path()
          ..moveTo(-dir * gripThick * 0.2, 5.0)
          ..lineTo(p1.dx - dir * gripThick * 0.2, p1.dy)
          ..lineTo(p2.dx - dir * gripThick * 0.2, p2.dy - 6),
        Paint()
          ..color = Colors.white.withValues(alpha: 0.5)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );

    } else if (zone?.useOctoHandle == true) {
      // 1. Draw the Keeper Piece (on the Frame - bottom)
      // Base plate of keeper
      final RRect keeperBase = RRect.fromRectAndRadius(
        Rect.fromLTRB(-14, 10, 14, 14),
        const Radius.circular(1.5),
      );
      canvas.drawRRect(keeperBase, basePaint);
      canvas.drawRRect(keeperBase, borderPaint);
 
      // Screw holes on keeper base
      canvas.drawCircle(const Offset(-9, 12), 1.0, Paint()..color = Colors.black45);
      canvas.drawCircle(const Offset(9, 12), 1.0, Paint()..color = Colors.black45);
 
      // Keeper receiving block (hollow structure)
      final RRect keeperBlock = RRect.fromRectAndRadius(
        Rect.fromLTRB(-8, 0, 8, 10),
        const Radius.circular(2),
      );
      canvas.drawRRect(keeperBlock, basePaint);
      canvas.drawRRect(keeperBlock, borderPaint);
      
      // Drawing the slot/opening line in the keeper
      canvas.drawLine(
        const Offset(-5, 5),
        const Offset(5, 5),
        borderPaint..strokeWidth = 1.0,
      );
      // Restore stroke width of borderPaint
      borderPaint.strokeWidth = 1.2;
 
      // 2. Draw the Main Latch Piece (on the Sash - top)
      // Mounting base plate (flange) of the main body
      final RRect mainBase = RRect.fromRectAndRadius(
        Rect.fromLTRB(-16, -6, 16, 0),
        const Radius.circular(1.5),
      );
      canvas.drawRRect(mainBase, basePaint);
      canvas.drawRRect(mainBase, borderPaint);
 
      // Screw holes on main base
      canvas.drawCircle(const Offset(-11, -4), 1.0, Paint()..color = Colors.black45);
      canvas.drawCircle(const Offset(11, -4), 1.0, Paint()..color = Colors.black45);
 
      // Cylinder Barrel/Housing
      final RRect barrel = RRect.fromRectAndRadius(
        Rect.fromLTRB(-6, -22, 6, 0),
        const Radius.circular(3),
      );
      canvas.drawRRect(barrel, basePaint);
      canvas.drawRRect(barrel, borderPaint);
 
      // Beveled Bolt (Tongue) extending from barrel into the keeper
      final Path boltPath = Path()
        ..moveTo(-3.5, 0)
        ..lineTo(3.5, 0)
        ..lineTo(3.5, 5)
        // Slanted tip (bevel)
        ..lineTo(-1.0, 7.5)
        ..lineTo(-3.5, 5)
        ..close();
      canvas.drawPath(boltPath, Paint()..color = Colors.grey.shade300..style = PaintingStyle.fill);
      canvas.drawPath(boltPath, borderPaint);
 
      // Finger Pull Ring at the top
      final Offset ringCenter = const Offset(0, -28);
      // Outer ring
      canvas.drawCircle(ringCenter, 7.5, basePaint);
      canvas.drawCircle(ringCenter, 7.5, borderPaint);
      // Inner hole (finger entry)
      canvas.drawCircle(ringCenter, 4.5, Paint()..color = Colors.white..style = PaintingStyle.fill);
      canvas.drawCircle(ringCenter, 4.5, borderPaint);
    } else if (isCremone) {
      // Cremone handle: same lever shape as normal, pointing toward hinges.
      // Base plate is vertical (top→bottom), 28 × 90 (square/rectangular with rounded corners).
      // Canvas may be rotated −90° for top/bottom sashes, so we compensate dimensions.
      final bool isRotatedCanvas = (handleSide == OpenDirection.top || handleSide == OpenDirection.bottom);

      // leverDir: lever extends toward the hinge side in local (post-rotation) canvas-X
      final double leverDir;
      if (handleSide == OpenDirection.left || handleSide == OpenDirection.bottom) {
        leverDir = 1.0;   // +X in local space = toward hinges
      } else {
        leverDir = -1.0;  // −X in local space = toward hinges
      }

      // Base plate — squared-off with rounded corners (22 × 80)
      final double bW = isRotatedCanvas ? 80.0 : 22.0;
      final double bH = isRotatedCanvas ? 22.0 : 80.0;
      final RRect basePlate = RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset.zero, width: bW, height: bH),
        const Radius.circular(4),
      );
      canvas.drawRRect(basePlate, basePaint);
      canvas.drawRRect(basePlate, borderPaint);

      // Highlight stripe on base plate
      canvas.drawLine(
        Offset(isRotatedCanvas ? 0 : -bW / 4, isRotatedCanvas ? -bH / 2 + 8 : -bH / 2 + 8),
        Offset(isRotatedCanvas ? 0 : -bW / 4, isRotatedCanvas ?  bH / 2 - 8 :  bH / 2 - 8),
        Paint()
          ..color = Colors.white.withValues(alpha: 0.4)
          ..strokeWidth = 2.0,
      );

      // Lever — thick grip (19px) extending toward the hinge side
      final double halfThick = 19.0 / 2.0; // 9.5
      final RRect lever = RRect.fromRectAndRadius(
        Rect.fromLTRB(
          leverDir == 1.0 ? -halfThick : -75,
          -halfThick,
          leverDir == 1.0 ?  75 :  halfThick,
          halfThick,
        ),
        const Radius.circular(8),
      );
      canvas.drawRRect(lever, basePaint);
      canvas.drawRRect(lever, borderPaint);

      // Highlight on lever
      canvas.drawLine(
        Offset(leverDir == 1.0 ? -2 : -70, -halfThick + 3),
        Offset(leverDir == 1.0 ?  70 :  2, -halfThick + 3),
        Paint()
          ..color = Colors.white.withValues(alpha: 0.5)
          ..strokeWidth = 1.5,
      );
    } else {
      // Normal PVC / standard window handle — base plate + lever always pointing downward
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
          ..strokeWidth = 1.5,
      );
    }
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
    WindowZone zone,
    bool isHandleSash, {
    required double t,
    required double topOffset,
    required bool isTopBound,
  }) {
    double netHeight = zone.boundary.height;
    int hingeCount = (netHeight > 2100)
        ? 4
        : (netHeight > 1000)
        ? 3
        : 2;

    if (zone.glass.structure == GlassStructure.double) {
      hingeCount += 1;
    }

    if ((model.useSystemOB || model.useDemiOB) && isHandleSash) {
      hingeCount = 2;
    }

    final paint = Paint()..color = model.accessoryColor;
    final shadow = Paint()..color = Colors.black45;

    void drawHinge(Offset center, bool horizontal) {
      final rect = horizontal
          ? Rect.fromCenter(center: center, width: 80, height: 16)
          : Rect.fromCenter(center: center, width: 16, height: 80);
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect.translate(1, 1), const Radius.circular(2)),
        shadow,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(2)),
        paint,
      );
      // Draw a black line in the middle of the hinge to make it look like a real aluminum hinge
      final linePaint = Paint()
        ..color = Colors.black // pure black line
        ..strokeWidth = 1.5;
      if (horizontal) {
        // Inset by 5 pixels on each side so the line remains strictly inside the rounded rectangle of the hinge
        canvas.drawLine(
          Offset(center.dx - 35, center.dy),
          Offset(center.dx + 35, center.dy),
          linePaint,
        );
      } else {
        // Inset by 5 pixels on each side so the line remains strictly inside the rounded rectangle of the hinge
        canvas.drawLine(
          Offset(center.dx, center.dy - 35),
          Offset(center.dx, center.dy + 35),
          linePaint,
        );
      }
    }

    if (onLeft || onRight) {
      double x = onRight ? sashR.right - 2 : sashR.left + 2;
      double startY = getSashTopY(x, sashR.top, t, topOffset, isTopBound) + 100,
          step = (sashR.bottom - 100 - startY) / (hingeCount - 1);
      for (int i = 0; i < hingeCount; i++) {
        double yPos = startY + (step * i);
        if (hingeCount >= 3) {
          if (i == 1) {
            yPos += zone.middleHingeDragOffset;
          } else if (i > 1 && i < hingeCount - 1) {
            double p1 = startY + step + zone.middleHingeDragOffset;
            double pLast = startY + step * (hingeCount - 1);
            int remainingSpaces = hingeCount - 2;
            int currentSpace = i - 1;
            yPos = p1 + (pLast - p1) * (currentSpace / remainingSpaces);
          }
        }
        drawHinge(Offset(x, yPos), false);
      }
    } else if (onTop || onBottom) {
      double y = onBottom ? sashR.bottom - 2 : sashR.top + 2;
      double startX = sashR.left + 100,
          step = (sashR.right - 100 - startX) / (hingeCount - 1);
      for (int i = 0; i < hingeCount; i++) {
        double xPos = startX + (step * i);
        if (hingeCount >= 3) {
          if (i == 1) {
            xPos += zone.middleHingeDragOffset;
          } else if (i > 1 && i < hingeCount - 1) {
            double p1 = startX + step + zone.middleHingeDragOffset;
            double pLast = startX + step * (hingeCount - 1);
            int remainingSpaces = hingeCount - 2;
            int currentSpace = i - 1;
            xPos = p1 + (pLast - p1) * (currentSpace / remainingSpaces);
          }
        }
        double finalY = y;
        if (onTop) {
          finalY = getSashTopY(xPos, sashR.top, t, topOffset, isTopBound) + 2;
        }
        drawHinge(Offset(xPos, finalY), true);
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
    double boxSize,
  ) {
    const coulisseWidth = 25.0;
    final double coulisseTop = boxSize;
    final double coulisseHeight = h - boxSize;

    final coulissePaint = Paint();
    if (_isWoodColor() && TextureCache.woodTexture != null) {
      _applyWoodShader(
        coulissePaint,
        Rect.fromLTWH(0, coulisseTop, w, coulisseHeight),
      );
    } else {
      coulissePaint.color = _fc[1];
    }
    coulissePaint.style = PaintingStyle.fill;

    final coulisseBorder = Paint()
      ..color = _fb
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    if (!model.removedShutterSides.contains('left')) {
      canvas.drawRect(
        Rect.fromLTWH(0, coulisseTop, coulisseWidth, coulisseHeight),
        coulissePaint,
      );
      canvas.drawRect(
        Rect.fromLTWH(0, coulisseTop, coulisseWidth, coulisseHeight),
        coulisseBorder,
      );
    }
    if (!model.removedShutterSides.contains('right')) {
      canvas.drawRect(
        Rect.fromLTWH(
          w - coulisseWidth,
          coulisseTop,
          coulisseWidth,
          coulisseHeight,
        ),
        coulissePaint,
      );
      canvas.drawRect(
        Rect.fromLTWH(
          w - coulisseWidth,
          coulisseTop,
          coulisseWidth,
          coulisseHeight,
        ),
        coulisseBorder,
      );
    }

    final visibleSlatsHeight = (h - boxSize) * position;
    canvas.save();
    final leftClip = model.removedShutterSides.contains('left')
        ? 0.0
        : coulisseWidth;
    final rightClip = model.removedShutterSides.contains('right')
        ? w
        : w - coulisseWidth;
    canvas.clipRect(
      Rect.fromLTRB(leftClip, boxSize, rightClip, boxSize + visibleSlatsHeight),
    );

    final slatsPaint = Paint();
    if (_isWoodColor() && TextureCache.woodTexture != null) {
      _applyWoodShader(
        slatsPaint,
        Rect.fromLTRB(
          leftClip,
          boxSize,
          rightClip,
          boxSize + visibleSlatsHeight,
        ),
      );
    } else {
      slatsPaint.color = _fc[0].withValues(alpha: 0.95);
    }
    slatsPaint.style = PaintingStyle.fill;

    for (double y = boxSize; y < boxSize + visibleSlatsHeight; y += 20.0) {
      if (model.removedShutterSides.contains('bottom') && (y + 20.0) >= h) {
        break;
      }
      canvas.drawRect(
        Rect.fromLTRB(leftClip, y, rightClip, y + 20.0),
        slatsPaint,
      );
    }

    final linePaint = Paint()
      ..color = _isWoodColor() ? Colors.black : _fb.withValues(alpha: 0.4)
      ..strokeWidth = _isWoodColor() ? 1.5 : 1.0
      ..style = PaintingStyle.stroke;

    for (double y = boxSize; y < boxSize + visibleSlatsHeight; y += 20.0) {
      if (model.removedShutterSides.contains('bottom') && (y + 20.0) >= h) {
        break;
      }
      canvas.drawLine(
        Offset(leftClip, y + 20.0),
        Offset(rightClip, y + 20.0),
        linePaint,
      );
    }
    canvas.restore();
  }

  void _drawShutterBox(
    Canvas canvas,
    double w,
    double boxSize,
    double h, {
    bool drawOnlyManualControls = false,
  }) {
    double startX = 0.0;
    double endX = w;
    double boxWidth = endX - startX;

    final boxRect = Rect.fromLTWH(startX, 0, boxWidth, boxSize);

    final mechanism = model.shutterMechanism;
    bool isRight = model.shutterDriveSide == 'right';
    if (!model.isInternalView) {
      isRight = !isRight;
    }
    double sign = isRight ? 1.0 : -1.0;

    // Draw Motor mechanism BEFORE the box so it appears from behind
    if (mechanism == 'محرك') {
      if (drawOnlyManualControls) return;

      double sideX = isRight ? (endX - 10) : (startX + 10);
      double startY = -10; // Start above/behind the box
      double wireLength = h * 0.65 + boxSize;
      double step = wireLength / 3;

      Paint motorPaint = Paint()
        ..color = const Color(0xFF212121)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4.5
        ..strokeCap = StrokeCap.round;

      Path wirePath = Path();
      wirePath.moveTo(sideX, startY);

      wirePath.quadraticBezierTo(
        sideX + (sign * 45),
        startY + (step * 0.5),
        sideX + (sign * 20),
        startY + step,
      );
      wirePath.quadraticBezierTo(
        sideX - (sign * 5),
        startY + (step * 1.5),
        sideX + (sign * 30),
        startY + (step * 2.0),
      );
      wirePath.quadraticBezierTo(
        sideX + (sign * 55),
        startY + (step * 2.5),
        sideX + (sign * 15),
        startY + wireLength,
      );

      canvas.drawPath(wirePath, motorPaint);

      double endXPos = sideX + (sign * 15);
      double endY = startY + wireLength;

      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(endXPos, endY + 8),
            width: 14,
            height: 20,
          ),
          const Radius.circular(4),
        ),
        Paint()
          ..color = const Color(0xFF212121)
          ..style = PaintingStyle.fill,
      );

      Paint pinPaint = Paint()
        ..color = Colors.grey.shade400
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round;

      canvas.drawLine(
        Offset(endXPos - 3, endY + 18),
        Offset(endXPos - 3, endY + 28),
        pinPaint,
      );
      canvas.drawLine(
        Offset(endXPos + 3, endY + 18),
        Offset(endXPos + 3, endY + 28),
        pinPaint,
      );
    }

    if (!drawOnlyManualControls) {
      // Draw the box cover
      final Paint boxPaint = Paint();
      if (_isWoodColor() && TextureCache.woodTexture != null) {
        _applyWoodShader(boxPaint, boxRect);
      } else {
        boxPaint.color = _fc[1];
      }
      boxPaint.style = PaintingStyle.fill;

      canvas.drawRect(boxRect, boxPaint);
      canvas.drawRect(
        boxRect,
        Paint()
          ..color = _fb
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }

    // Draw Strap and Crank AFTER the box (on top of it)
    if (model.isInternalView &&
        mechanism != 'Manuel' &&
        mechanism != '' &&
        mechanism != 'محرك') {
      Paint paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0;

      double frontX = isRight ? (endX - 25.0) : (startX + 25.0);

      if (mechanism == 'حزام') {
        paint.color = Colors.grey.shade400;
        paint.strokeWidth = 14.0;

        // If height > 2m (2000mm), place strap in middle of door, else raise it about 30cm from bottom (h - 300).
        double strapLength = (h > 2000) ? (h / 2) : (h - 300);
        if (strapLength < 100) strapLength = 100; // safety

        canvas.drawLine(
          Offset(frontX, boxSize * 0.25),
          // Starts from upper quarter of the box
          Offset(frontX, boxSize + strapLength),
          paint,
        );

        final boxCenter = Offset(frontX, boxSize + strapLength + 37.5);
        canvas.drawRect(
          Rect.fromCenter(center: boxCenter, width: 32, height: 75),
          Paint()
            ..color = Colors.white
            ..style = PaintingStyle.fill,
        );
        canvas.drawRect(
          Rect.fromCenter(center: boxCenter, width: 32, height: 75),
          Paint()
            ..color = Colors.grey.shade600
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5,
        );
        canvas.drawLine(
          Offset(frontX - 8, boxCenter.dy - 22),
          Offset(frontX + 8, boxCenter.dy - 22),
          Paint()
            ..color = Colors.black87
            ..strokeWidth = 3,
        );
      } else if (mechanism == 'مانيفال' ||
          mechanism == 'منايفال' ||
          mechanism.toLowerCase().contains('manivelle')) {
        paint.color = Colors.grey.shade300;
        paint.strokeWidth = 10.0;
        paint.strokeJoin = StrokeJoin.round;
        double rodLength = h * 0.5;

        canvas.drawCircle(
          Offset(frontX, 10), // Revert to top of the box
          9,
          Paint()
            ..color = Colors.grey.shade600
            ..style = PaintingStyle.fill,
        );
        canvas.drawLine(
          Offset(frontX, 10), // Revert to top of the box
          Offset(frontX, boxSize + rodLength),
          paint,
        );

        double zigzagWidth = isRight ? -60.0 : 60.0;

        Path crankPath = Path();
        crankPath.moveTo(frontX, boxSize + rodLength);
        crankPath.lineTo(frontX + zigzagWidth, boxSize + rodLength + 15);
        crankPath.lineTo(frontX + zigzagWidth, boxSize + rodLength + 105);
        crankPath.lineTo(frontX, boxSize + rodLength + 120);
        canvas.drawPath(crankPath, paint);

        canvas.drawLine(
          Offset(frontX, boxSize + rodLength + 120),
          Offset(frontX, boxSize + rodLength + 180),
          Paint()
            ..color = Colors.white
            ..strokeWidth = 14
            ..strokeCap = StrokeCap.round,
        );
      }
    }

    // Draw remote control receiver icon if motorHasTelecommande is true
    if (mechanism == 'محرك' && model.motorHasTelecommande) {
      double rx = startX + 20.0;
      double ry = 15.0; // on the shutter box
      final remoteRect = Rect.fromLTWH(rx, ry, 15, 30);

      // Draw remote shadow
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          remoteRect.translate(1, 1),
          const Radius.circular(3),
        ),
        Paint()..color = Colors.black26,
      );
      // Draw remote body
      canvas.drawRRect(
        RRect.fromRectAndRadius(remoteRect, const Radius.circular(3)),
        Paint()..color = Colors.white,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(remoteRect, const Radius.circular(3)),
        Paint()
          ..color = const Color(0xFF64748B)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2,
      );
      // Draw buttons inside the remote control
      canvas.drawCircle(
        Offset(rx + 7.5, ry + 7),
        2.2,
        Paint()..color = Colors.red,
      );
      canvas.drawCircle(
        Offset(rx + 7.5, ry + 15),
        2.2,
        Paint()..color = Colors.grey.shade600,
      );
      canvas.drawCircle(
        Offset(rx + 7.5, ry + 23),
        2.2,
        Paint()..color = Colors.grey.shade600,
      );
    }
  }

  void _drawRealisticParclose(
    Canvas canvas,
    Rect rect,
    FrameColor color, {
    double? customThickness,
    required double t,
    required double topOffset,
    required bool isTopBound,
  }) {
    final double pT = customThickness ?? 8.0;
    if (rect.width <= pT * 2 || rect.height <= pT * 2) return;

    final bool isBottomOpen =
        !model.hasBottomFrame && (rect.bottom - model.height).abs() < 1.0;
    final Rect innerRect = isBottomOpen
        ? Rect.fromLTRB(
            rect.left + pT,
            rect.top + pT,
            rect.right - pT,
            rect.bottom,
          )
        : rect.deflate(pT);

    final Path outerPath = Path();
    final Path innerPath = Path();

    if (isTopBound) {
      double yOuterL = getSashTopY(rect.left, rect.top, t, topOffset, true);
      double yOuterR = getSashTopY(rect.right, rect.top, t, topOffset, true);
      outerPath.moveTo(rect.left, rect.bottom);
      outerPath.lineTo(rect.left, yOuterL);
      if (model.archHeight > 0) {
        double yMid = getSashTopY(
          (rect.left + rect.right) / 2,
          rect.top,
          t,
          topOffset,
          true,
        );
        double yC = 2 * yMid - 0.5 * (yOuterL + yOuterR);
        outerPath.quadraticBezierTo(
          (rect.left + rect.right) / 2,
          yC,
          rect.right,
          yOuterR,
        );
      } else {
        outerPath.lineTo(rect.right, yOuterR);
      }
      outerPath.lineTo(rect.right, rect.bottom);
      outerPath.close();

      double yInnerL =
          getSashTopY(innerRect.left, rect.top, t, topOffset, true) + pT;
      double yInnerR =
          getSashTopY(innerRect.right, rect.top, t, topOffset, true) + pT;
      innerPath.moveTo(innerRect.left, innerRect.bottom);
      innerPath.lineTo(innerRect.left, yInnerL);
      if (model.archHeight > 0) {
        double yMid =
            getSashTopY(
              (innerRect.left + innerRect.right) / 2,
              rect.top,
              t,
              topOffset,
              true,
            ) +
            pT;
        double yC = 2 * yMid - 0.5 * (yInnerL + yInnerR);
        innerPath.quadraticBezierTo(
          (innerRect.left + innerRect.right) / 2,
          yC,
          innerRect.right,
          yInnerR,
        );
      } else {
        innerPath.lineTo(innerRect.right, yInnerR);
      }
      innerPath.lineTo(innerRect.right, innerRect.bottom);
      innerPath.close();
    } else {
      outerPath.addRect(rect);
      innerPath.addRect(innerRect);
    }

    final Path framePath = Path()
      ..addPath(outerPath, Offset.zero)
      ..addPath(innerPath, Offset.zero)
      ..fillType = PathFillType.evenOdd;

    canvas.drawPath(
      framePath,
      Paint()
        ..color = _fc[1]
        ..style = PaintingStyle.fill,
    );

    final Paint linePaint = Paint()
      ..color = _fb.withValues(alpha: 0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    if (isBottomOpen) {
      final Path innerStrokePath = Path();
      double yInnerL = isTopBound
          ? getSashTopY(innerRect.left, rect.top, t, topOffset, true) + pT
          : innerRect.top;
      double yInnerR = isTopBound
          ? getSashTopY(innerRect.right, rect.top, t, topOffset, true) + pT
          : innerRect.top;

      innerStrokePath.moveTo(innerRect.left, innerRect.bottom);
      innerStrokePath.lineTo(innerRect.left, yInnerL);
      if (isTopBound && model.archHeight > 0) {
        double yMid =
            getSashTopY(
              (innerRect.left + innerRect.right) / 2,
              rect.top,
              t,
              topOffset,
              true,
            ) +
            pT;
        double yC = 2 * yMid - 0.5 * (yInnerL + yInnerR);
        innerStrokePath.quadraticBezierTo(
          (innerRect.left + innerRect.right) / 2,
          yC,
          innerRect.right,
          yInnerR,
        );
      } else {
        innerStrokePath.lineTo(innerRect.right, yInnerR);
      }
      innerStrokePath.lineTo(innerRect.right, innerRect.bottom);
      canvas.drawPath(innerStrokePath, linePaint);
    } else {
      canvas.drawPath(innerPath, linePaint);
    }

    if (isTopBound) {
      double yOuterL = getSashTopY(rect.left, rect.top, t, topOffset, true);
      double yOuterR = getSashTopY(rect.right, rect.top, t, topOffset, true);
      double yInnerL =
          getSashTopY(innerRect.left, rect.top, t, topOffset, true) + pT;
      double yInnerR =
          getSashTopY(innerRect.right, rect.top, t, topOffset, true) + pT;
      canvas.drawLine(
        Offset(rect.left, yOuterL),
        Offset(innerRect.left, yInnerL),
        linePaint,
      );
      canvas.drawLine(
        Offset(rect.right, yOuterR),
        Offset(innerRect.right, yInnerR),
        linePaint,
      );
    } else {
      canvas.drawLine(rect.topLeft, innerRect.topLeft, linePaint);
      canvas.drawLine(rect.topRight, innerRect.topRight, linePaint);
    }

    if (!isBottomOpen) {
      canvas.drawLine(rect.bottomLeft, innerRect.bottomLeft, linePaint);
      canvas.drawLine(rect.bottomRight, innerRect.bottomRight, linePaint);
    }
  }

  Rect _getSafeGlassRect(Rect sashRect, double sashT, {bool hasSashPlintheBottom = false}) {
    double finalT = sashT;
    if (sashRect.width <= finalT * 2 + 10) {
      finalT = math.max(1.0, (sashRect.width - 10) / 2);
    }
    double bottomT = finalT;
    if (hasSashPlintheBottom) {
      bottomT = model.plintheHeight;
    }
    if (sashRect.height <= finalT + bottomT + 10) {
      bottomT = math.max(1.0, sashRect.height - finalT - 10);
    }
    return Rect.fromLTRB(
      sashRect.left + finalT,
      sashRect.top + finalT,
      sashRect.right - finalT,
      sashRect.bottom - bottomT,
    );
  }

  @override
  bool shouldRepaint(covariant WindowPainter oldDelegate) => true;
}

class _MergedCell {
  final int row;
  final int col;
  final int hSpan;
  final int wSpan;
  final Rect rect;
  final String key;

  _MergedCell({
    required this.row,
    required this.col,
    required this.hSpan,
    required this.wSpan,
    required this.rect,
    required this.key,
  });
}

class _MullionSegment {
  final double position;
  final double start;
  final double end;
  _MullionSegment({required this.position, required this.start, required this.end});
}

List<_MullionSegment> _mergeMullionSegments(List<_MullionSegment> segments, double thickness) {
  if (segments.isEmpty) return [];
  
  List<_MullionSegment> sorted = List.from(segments);
  sorted.sort((a, b) {
    int cmp = a.position.compareTo(b.position);
    if (cmp != 0) return cmp;
    return a.start.compareTo(b.start);
  });
  
  List<_MullionSegment> merged = [];
  _MullionSegment current = sorted[0];
  
  for (int i = 1; i < sorted.length; i++) {
    _MullionSegment next = sorted[i];
    
    if ((next.position - current.position).abs() < 2.0 && next.start <= current.end + thickness + 5.0) {
      current = _MullionSegment(
        position: current.position,
        start: current.start,
        end: math.max(current.end, next.end),
      );
    } else {
      merged.add(current);
      current = next;
    }
  }
  merged.add(current);
  return merged;
}

