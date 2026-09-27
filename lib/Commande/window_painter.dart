// Force compile sync trigger
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:database_data/Commande/texture_cache.dart';
import 'package:database_data/Commande/decor_panel_designs.dart';

// Force compile sync trigger
import 'package:flutter/material.dart';

import 'package:database_data/Commande/Systeme/model.dart';

part 'window_painter_helpers.dart';

class WindowPainter extends CustomPainter {
  final WindowModel model;
  final bool? overrideIsInternalView;
  final int repaintToken;

  /// Technical dimensions are reserved for the interactive drawing editor.
  /// Previews, PDFs and customer-facing images stay clean.
  final bool showDrawingDimensions;

  /// The green editor selection is never part of previews, generated images,
  /// or PDFs. Only the interactive drawing page enables it.
  final bool showSelection;

  // Optimized wood rendering states computed once per repaint to avoid lag
  late final bool _isWood;
  late final ui.Shader? _woodShader;
  late final ColorFilter? _woodColorFilter;

  WindowPainter({
    required this.model,
    this.overrideIsInternalView,
    this.repaintToken = 0,
    this.showDrawingDimensions = false,
    this.showSelection = false,
  }) : super(repaint: model) {
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

  bool get _hasDrawableIntegratedSideCover =>
      model.hasSideCovers &&
      model.isIntegratedFrame &&
      model.isSideCoverAllowed &&
      model.integratedFrameSideCoverWidth > 0;

  bool get _hasDrawableStandaloneSideCover =>
      model.hasSideCovers &&
      !model.isIntegratedFrame &&
      !model.selectedOuterFrameHasIntegratedSideCover &&
      model.canUseStandaloneSideCover &&
      _drawableStandaloneSideCoverWidth > 0;

  bool get _shouldDrawSideCovers =>
      _hasDrawableIntegratedSideCover || _hasDrawableStandaloneSideCover;

  bool get _shouldDrawWindowHardware {
    final isInternal = overrideIsInternalView ?? model.isInternalView;
    // The internal face shows its real hardware by default. The external face
    // stays clean unless the user explicitly enables the hardware overlay.
    return isInternal || model.showInternalHardware;
  }

  bool? _localBottomFrame;

  bool get _hasEffectiveBottomFrame =>
      _localBottomFrame ?? model.effectiveHasBottomFrame;

  double get _drawableStandaloneSideCoverWidth {
    final width = model.standaloneSideCoverWidth;
    if (width > 0) return width;
    if (model.hasSideCovers &&
        (model.selectedSideCover != null || model.sideCoverOverride != null)) {
      return 35.0;
    }
    return 0.0;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final w = model.width;
    final h = model.height;

    // The selected frame owns its visible drawing width. PVC frame roles can
    // have a width different from the generic system profile thickness.
    final frameRects = model.getFrameRects();
    final primaryFrame = frameRects.isEmpty
        ? Rect.fromLTRB(0, _topOffset, w, h)
        : frameRects.first;
    final t = model.frameVisibleWidthForRect(
      primaryFrame,
      fallback: model.profileThickness,
    );

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
            ? const Color(
                0xFF4A5568,
              ) // dark slate grey mortar joints for grey bricks
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
      }
    }

    final innerPath = _buildInnerShapePath(w, h, t, topOffset);

    canvas.save();
    canvas.clipPath(innerPath);
    // Saved zone bounds may retain the previous profile's rebate deduction.
    // Paint the pocket of each real frame before its glazing, so any exposed
    // rebate uses the profile finish instead of the white page background.
    // Do not fill the overall bounding box: gaps between frames stay empty.
    final physicalFrames = model.getFrameRects();
    final pocketFrames = physicalFrames.length == 1
        ? [Rect.fromLTRB(0, topOffset, w, h)]
        : physicalFrames;
    for (final frame in pocketFrames) {
      final pocket = frame.deflate(t);
      if (pocket.width > 0 && pocket.height > 0) {
        canvas.drawRect(pocket, _buildPaint(pocket));
      }
    }
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
        _drawMainZoneHinges(canvas, h, t);
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
      }

      if (!model.isShutterOnly) {
        canvas.save();
        canvas.clipPath(innerPath);
        _drawMullions(canvas, w, h, t);
        canvas.restore();

        if (_hasEffectiveBottomFrame) {
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
        _drawMainZoneHinges(canvas, h, t);
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
          if (model.shutterMechanism == 'منايفال' ||
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

    // Draw the side cover after both face pipelines have finished. This keeps
    // it visible when the wall, shutter, or sash layers are enabled.
    if (!model.isShutterOnly) {
      // The shutter box occupies the area from y=0 to [topOffset]. The
      // side-cover perimeter must start at y=0 as well; otherwise it only
      // surrounds the frame below the box and leaves the box outside the
      // cover. Tunnel shutters already use a zero top offset.
      final sideCoverTopY = model.hasShutter && !isSlantedOrArched
          ? 0.0
          : topOffset;
      _drawConfiguredSideCovers(canvas, w, h, sideCoverTopY);
      _drawFrameRoleProfiles(canvas, w, h, topOffset);
    }

    if (model.hasShutter &&
        !isSlantedOrArched &&
        model.shutterMechanism == 'محرك') {
      _drawMotorControls(canvas, w, h, t, topOffset);
    }

    if (showSelection) {
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
            final double effectiveRatio = isInternal
                ? zone.doubleSashRatio
                : (1.0 - zone.doubleSashRatio);
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
            final glassR = _getSafeGlassRect(
              sashR,
              sashT,
              hasSashPlintheBottom: zone.hasSashPlintheBottom,
            );
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
        if (showDrawingDimensions) _drawInnerDimensions(canvas, zone);
      }
    } else if (showDrawingDimensions) {
      for (final zone in model.zones) {
        _drawInnerDimensions(canvas, zone);
      }
    }

    // Adding an outer frame uses the same solid blue rectangle preview as
    // the first frame. Dashed lines remain reserved for splitting a frame.
    if (model.drawingMode != 'add_frame' &&
        model.drawingStart != null &&
        model.drawingCurrent != null) {
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

  String? _effectivePanneauColor(GlassSpecification? spec) {
    if (spec == null) return null;
    final isBardage =
        spec.finishOuter == GlassFinish.bardage ||
        spec.finishInner == GlassFinish.bardage ||
        isBardagePanelSubtype(spec.panneauSubtype);
    if (isBardage && spec.bardageUsesFrameColor) {
      return model.getBardageColorNameForSpec(spec);
    }
    return spec.panneauColor;
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

    final pColor = _effectivePanneauColor(spec);
    final bool isPanneauWood = pColor != null && _isWoodColor({'name': pColor});
    final Paint fillPaint = Paint();
    if (structure == GlassStructure.closed &&
        isPanneauWood &&
        TextureCache.woodTexture != null) {
      final woodColors = getEffectiveGradientColors(FrameColor.brown, {
        'name': pColor,
      });
      _applyWoodShader(
        fillPaint,
        r,
        gradientColors: woodColors,
        dbColor: {'name': pColor},
      );
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
        if (clean == 'grey' ||
            clean == 'gray' ||
            clean == 'رمادي' ||
            clean == 'gris') {
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

      final isGold =
          dColorStr.toLowerCase().contains('gold') ||
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
              final Rect gradRect = Rect.fromCenter(
                center: center,
                width: baseR * 3,
                height: baseR * 3,
              );
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
            bool isRosette2 =
                spec.rosetteShape == 2 ||
                nameClean.contains('curve') ||
                nameClean.contains('courbe') ||
                nameClean.contains('منحني') ||
                nameClean.contains('2');
            bool isRosette3 =
                spec.rosetteShape == 3 ||
                nameClean.contains('baroque') ||
                nameClean.contains('oval') ||
                nameClean.contains('ovale') ||
                nameClean.contains('بيضاوي') ||
                nameClean.contains('زخرفة') ||
                nameClean.contains('3');
            bool isRosette4 =
                spec.rosetteShape == 4 ||
                nameClean.contains('solid') ||
                nameClean.contains('plein') ||
                nameClean.contains('ممتلئ') ||
                nameClean.contains('diamond') ||
                nameClean.contains('losange') ||
                nameClean.contains('معين') ||
                nameClean.contains('4');
            bool isRosette1 =
                spec.rosetteShape == 1 ||
                (!isRosette2 && !isRosette3 && !isRosette4);

            if (isRosette1) {
              // 🌸 Type 1: Star / Cross Flower (Image 1)
              final Path starPath = Path();
              starPath.moveTo(center.dx, center.dy - baseR * 1.5);
              starPath.quadraticBezierTo(
                center.dx + baseR * 0.25,
                center.dy - baseR * 0.25,
                center.dx + baseR * 1.5,
                center.dy,
              );
              starPath.quadraticBezierTo(
                center.dx + baseR * 0.25,
                center.dy + baseR * 0.25,
                center.dx,
                center.dy + baseR * 1.5,
              );
              starPath.quadraticBezierTo(
                center.dx - baseR * 0.25,
                center.dy + baseR * 0.25,
                center.dx - baseR * 1.5,
                center.dy,
              );
              starPath.quadraticBezierTo(
                center.dx - baseR * 0.25,
                center.dy - baseR * 0.25,
                center.dx,
                center.dy - baseR * 1.5,
              );
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
              curvePath.quadraticBezierTo(
                center.dx,
                center.dy,
                center.dx + baseR * 1.2,
                center.dy,
              );
              curvePath.quadraticBezierTo(
                center.dx,
                center.dy,
                center.dx,
                center.dy + baseR * 1.2,
              );
              curvePath.quadraticBezierTo(
                center.dx,
                center.dy,
                center.dx - baseR * 1.2,
                center.dy,
              );
              curvePath.quadraticBezierTo(
                center.dx,
                center.dy,
                center.dx,
                center.dy - baseR * 1.2,
              );
              curvePath.close();

              canvas.drawPath(curvePath, fillPaint);
              canvas.drawPath(curvePath, outlinePaint);
              canvas.drawCircle(center, baseR * 0.2, strokePaint);
            } else if (isRosette3) {
              // 🌸 Type 3: Filigree Baroque Oval (Image 3)
              canvas.drawOval(
                Rect.fromCenter(
                  center: center,
                  width: baseR * 1.6,
                  height: baseR * 2.8,
                ),
                strokePaint,
              );
              canvas.drawOval(
                Rect.fromCenter(
                  center: center,
                  width: baseR * 1.6,
                  height: baseR * 2.8,
                ),
                outlinePaint,
              );

              final Path pathL = Path();
              pathL.moveTo(center.dx, center.dy);
              pathL.cubicTo(
                center.dx - baseR * 0.9,
                center.dy - baseR * 0.9,
                center.dx - baseR * 0.9,
                center.dy + baseR * 0.9,
                center.dx - baseR * 0.2,
                center.dy + baseR * 0.6,
              );
              canvas.drawPath(pathL, strokePaint);

              final Path pathR = Path();
              pathR.moveTo(center.dx, center.dy);
              pathR.cubicTo(
                center.dx + baseR * 0.9,
                center.dy - baseR * 0.9,
                center.dx + baseR * 0.9,
                center.dy + baseR * 0.9,
                center.dx + baseR * 0.2,
                center.dy + baseR * 0.6,
              );
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
                Rect.fromCenter(
                  center: center,
                  width: baseR * 1.8,
                  height: baseR * 2.8,
                ),
                strokePaint,
              );
              canvas.drawOval(
                Rect.fromCenter(
                  center: center,
                  width: baseR * 1.8,
                  height: baseR * 2.8,
                ),
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
    if (!_hasEffectiveBottomFrame && (original.bottom - (h - t)).abs() < 5.0) {
      final matchingZone = model.zones.firstWhere(
        (z) =>
            (z.boundary.left - original.left).abs() < 2.0 &&
            (z.boundary.top - original.top).abs() < 2.0 &&
            (z.boundary.right - original.right).abs() < 2.0,
        orElse: () => WindowZone(
          id: 'temp',
          boundary: original,
          content: ZoneContent.singleSash,
        ),
      );
      bool isFixed =
          matchingZone.content == ZoneContent.fixedGlass ||
          matchingZone.content == ZoneContent.empty;
      if (isFixed) {
        return original; // الثابت يستقر على الإطار السفلي عند (h - t)
      }
      final frameRect = Rect.fromLTRB(0, _topOffset, model.width, h);
      final sliding = model.frameUsesSlidingSeries(frameRect);
      if (model.usesFrameRole('seuil', sliding: sliding)) {
        final seuilSection = model.getConfiguredSectionForRole(
          'seuil',
          useSlidingSeries: sliding,
        );
        final seuilT = (seuilSection != null && seuilSection.visibleWidth > 0)
            ? seuilSection.visibleWidth
            : 0.0;
        return Rect.fromLTRB(
          original.left,
          original.top,
          original.right,
          h - seuilT,
        );
      }
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
    double bottomOffset = _hasEffectiveBottomFrame ? t : 0.0;

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
      final frame = Rect.fromLTRB(0, topOffset, w, h);
      final sliding = model.frameUsesSlidingSeries(frame);
      final previousBottomFrame = _localBottomFrame;
      if (model.usesFrameRole('seuil', sliding: sliding)) {
        _localBottomFrame = false;
      }
      try {
        _drawOuterFrame(canvas, w, h, t, topOffset, sourceFrame: frame);
      } finally {
        _localBottomFrame = previousBottomFrame;
      }
    } else {
      for (final r in frameRects) {
        // A frame rectangle already starts below the shutter box.  Drawing it
        // with the global [topOffset] after translating only partly on Y made
        // its height lose the shutter-box height a second time.  In a
        // multi-frame shutter drawing this left a transparent/short frame
        // behind the new frame.  Use the frame's own local coordinate system
        // instead: (0, 0) → (r.width, r.height).
        canvas.save();
        canvas.translate(r.left, r.top);
        final localThickness = model.frameVisibleWidthForRect(r, fallback: t);
        final previousBottomFrame = _localBottomFrame;
        _localBottomFrame = model.hasBottomFrameForRect(r);
        if (model.usesFrameRole(
          'seuil',
          sliding: model.frameUsesSlidingSeries(r),
        )) {
          _localBottomFrame = false;
        }
        try {
          _drawOuterFrame(
            canvas,
            r.width,
            r.height,
            localThickness,
            0.0,
            sourceFrame: r,
          );
        } finally {
          _localBottomFrame = previousBottomFrame;
          canvas.restore();
        }
      }
    }
  }

  void _drawFrameRoleProfiles(Canvas canvas, double w, double h, double top) {
    final frames = model.getFrameRects();
    for (final raw in frames) {
      final r = frames.length == 1 ? Rect.fromLTRB(0, top, w, h) : raw;
      final sliding = model.frameUsesSlidingSeries(raw);
      void drawProfile(Rect rect) {
        if (rect.isEmpty) return;
        canvas.drawRect(rect, _buildPaint(rect));
        canvas.drawRect(
          rect,
          Paint()
            ..color = _fb
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1,
        );
      }

      void drawSeuil(Rect rect) {
        if (rect.isEmpty) return;
        canvas.drawRect(rect, _buildPaint(rect));
        final border = Paint()
          ..color = _fb
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5;
        canvas.drawRect(rect, border);
      }

      for (final role in ['cache_dormant', 'cache_rail', 'seuil']) {
        if (!model.usesFrameRole(role, sliding: sliding)) continue;
        final section = model.getConfiguredSectionForRole(
          role,
          useSlidingSeries: sliding,
        );
        if (section == null || section.visibleWidth <= 0) continue;
        final visible = section.visibleWidth.clamp(
          0.0,
          math.min(r.width / 2, r.height / 2),
        );
        if (role == 'seuil') {
          // Straight ends meet the jambs at 90 degrees.
          drawSeuil(
            Rect.fromLTRB(r.left, r.bottom - visible, r.right, r.bottom),
          );
        } else if (role == 'cache_dormant') {
          drawProfile(Rect.fromLTRB(r.left, r.top, r.right, r.top + visible));
          drawProfile(
            Rect.fromLTRB(r.left, r.top + visible, r.left + visible, r.bottom),
          );
          drawProfile(
            Rect.fromLTRB(
              r.right - visible,
              r.top + visible,
              r.right,
              r.bottom,
            ),
          );
          if (model.hasBottomFrameForRect(raw)) {
            drawProfile(
              Rect.fromLTRB(r.left, r.bottom - visible, r.right, r.bottom),
            );
          }
        } else if (sliding) {
          final counts = model.cacheRailCountsForRect(raw);
          drawProfile(
            Rect.fromLTRB(
              r.left,
              r.top,
              r.left + visible * counts.$1,
              r.bottom,
            ),
          );
          drawProfile(
            Rect.fromLTRB(
              r.right - visible * counts.$2,
              r.top,
              r.right,
              r.bottom,
            ),
          );
        }
      }
    }

    // Cache-rainure is fitted on both faces of a compatible junction between
    // two outer frames. It is intentionally independent from the perimeter
    // side-cover drawing: only shared frame seams receive it.
    for (final contact in model.getCacheRainureContacts()) {
      final insideSection = model.getConfiguredSectionForRole(
        'cache_rainure',
        useSlidingSeries: contact.insideUsesSlidingSeries,
      );
      final outsideSection = model.getConfiguredSectionForRole(
        'cache_rainure',
        useSlidingSeries: contact.outsideUsesSlidingSeries,
      );
      if (insideSection == null || outsideSection == null) continue;
      // Cache-rainure is deliberately shown as two slightly separated black
      // seam lines, one per face, so it is visible exactly between the two
      // compatible frames without obscuring their profile colours.
      final seam = Paint()
        ..color = Colors.black
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.0;
      if (contact.isVertical) {
        for (final x in [contact.coordinate - 1.5, contact.coordinate + 1.5]) {
          canvas.drawLine(
            Offset(x, contact.start),
            Offset(x, contact.end),
            seam,
          );
        }
      } else {
        for (final y in [contact.coordinate - 1.5, contact.coordinate + 1.5]) {
          canvas.drawLine(
            Offset(contact.start, y),
            Offset(contact.end, y),
            seam,
          );
        }
      }
    }

    // Bavette is an optional visible cover. In bottom mode it follows the
    // lower edge; in four-side mode it follows the complete perimeter.
    if (model.usesBavette) {
      for (final frame in frames) {
        final sliding = model.frameUsesSlidingSeries(frame);
        final section = model.getConfiguredSectionForRole(
          'bavette',
          useSlidingSeries: sliding,
        );
        if (section == null) continue;
        final width = section.visibleWidth.clamp(1.0, 80.0).toDouble();
        final border = Paint()
          ..color = _fb
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1;
        final rects = <Rect>[
          Rect.fromLTRB(
            frame.left,
            frame.bottom - width,
            frame.right,
            frame.bottom,
          ),
        ];
        if (model.optionalBavetteMode == 2) {
          rects.addAll([
            Rect.fromLTRB(
              frame.left,
              frame.top,
              frame.right,
              frame.top + width,
            ),
            Rect.fromLTRB(
              frame.left,
              frame.top,
              frame.left + width,
              frame.bottom,
            ),
            Rect.fromLTRB(
              frame.right - width,
              frame.top,
              frame.right,
              frame.bottom,
            ),
          ]);
        }
        for (final rect in rects) {
          canvas.drawRect(rect, _buildPaint(rect));
          canvas.drawRect(rect, border);
        }
      }
    }

    // The caniveau is visible from the exterior only. It stays below the
    // existing lower frame; the cache-caniveau is the upper strip covering
    // the channel, so neither replaces nor draws a second lower frame.
    if (!model.isInternalView) {
      for (final frame in frames) {
        if (!model.usesCaniveauForRect(frame)) continue;
        final sliding = model.frameUsesSlidingSeries(frame);
        final caniveau = model.getConfiguredSectionForRole(
          'caniveau',
          useSlidingSeries: sliding,
        );
        final cache = model.getConfiguredSectionForRole(
          'cache_caniveau',
          useSlidingSeries: sliding,
        );
        if (caniveau == null || cache == null) continue;
        final double channelHeight = caniveau.visibleWidth
            .clamp(0.0, 80.0)
            .toDouble();
        final double cacheHeight = cache.visibleWidth
            .clamp(0.0, 80.0)
            .toDouble();
        if (channelHeight <= 0 || cacheHeight <= 0) continue;
        final cacheRect = Rect.fromLTRB(
          frame.left,
          frame.bottom,
          frame.right,
          frame.bottom + cacheHeight,
        );
        final channelRect = Rect.fromLTRB(
          frame.left,
          cacheRect.bottom,
          frame.right,
          cacheRect.bottom + channelHeight,
        );
        final border = Paint()
          ..color = _fb
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1;
        canvas.drawRect(cacheRect, _buildPaint(cacheRect));
        canvas.drawRect(cacheRect, border);
        canvas.drawRect(channelRect, _buildPaint(channelRect));
        canvas.drawRect(channelRect, border);

        // The two Bouchons are accessories, but drawing their end caps makes
        // the outside caniveau unambiguous: one at the right and one at the
        // left, without changing the sash or glazing dimensions.
        final double capWidth = math
            .min(math.max(4.0, cacheHeight), frame.width / 4.0)
            .toDouble();
        final capTop = cacheRect.top;
        final capBottom = channelRect.bottom;
        for (final left in [frame.left, frame.right - capWidth]) {
          final capRect = Rect.fromLTRB(
            left,
            capTop,
            left + capWidth,
            capBottom,
          );
          canvas.drawRect(capRect, Paint()..color = _fb.withOpacity(0.82));
          canvas.drawRect(capRect, border);
        }
      }
    }
  }

  double _slidingFrameWidth(double fallback) {
    final section = model.getSlidingBaseFrameSection();
    if (section != null) {
      final visible = section.visibleWidth;
      if (visible > 0) return visible;
      final thickness = section.thickness;
      if (thickness > 0) return thickness;
    }
    return fallback;
  }

  bool _frameTopTouchesShutterBox(double top) {
    return model.hasShutter &&
        !model.isCaissonTunnel &&
        model.shutterBoxHeight > 0 &&
        (top - model.shutterBoxHeight).abs() <= 0.01;
  }

  void _drawInternalSlidingSideCover(Canvas canvas, Rect frameRect) {
    if (!model.hasInternalSlidingSideCover) return;
    final coverWidth = model.internalSlidingSideCoverWidth;
    if (coverWidth <= 0) return;

    final paint = Paint();
    if (_isWoodColor() && TextureCache.woodTexture != null) {
      _applyWoodShader(paint, frameRect.inflate(coverWidth));
    } else {
      paint.color = _fc[1];
    }
    final border = Paint()
      ..color = _fb
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1;

    final rects = <Rect>[
      Rect.fromLTRB(
        frameRect.left - coverWidth,
        frameRect.top - coverWidth,
        frameRect.right + coverWidth,
        frameRect.top,
      ),
      Rect.fromLTRB(
        frameRect.left - coverWidth,
        frameRect.bottom,
        frameRect.right + coverWidth,
        frameRect.bottom + coverWidth,
      ),
      Rect.fromLTRB(
        frameRect.left - coverWidth,
        frameRect.top,
        frameRect.left,
        frameRect.bottom,
      ),
      Rect.fromLTRB(
        frameRect.right,
        frameRect.top,
        frameRect.right + coverWidth,
        frameRect.bottom,
      ),
    ];
    for (final rect in rects) {
      canvas.drawRect(rect, paint);
      canvas.drawRect(rect, border);
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
          _drawWeepHoles(
            canvas,
            Rect.fromLTRB(r.left, topOffset, r.right, h),
            t,
          );
        }
      }
    }
  }

  void _drawOuterFrame(
    Canvas canvas,
    double w,
    double h,
    double t,
    double topY, {
    Rect? sourceFrame,
  }) {
    final outerPath = _buildOuterShapePath(w, h, topY);
    final innerPath = _buildInnerShapePath(w, h, t, topY);

    final path = Path()
      ..addPath(outerPath, Offset.zero)
      ..addPath(innerPath, Offset.zero)
      ..fillType = PathFillType.evenOdd;

    final outerRect = Rect.fromLTRB(0, topY, w, h);
    canvas.drawPath(path, _buildPaint(outerRect));

    final isWholeDrawingFrameSelected =
        model.selection.type == SelectionType.frame &&
        model.selection.zoneId == null &&
        model.isDrawingMode;

    if (isWholeDrawingFrameSelected) {
      canvas.drawPath(
        path,
        Paint()
          ..color = Colors.green.withValues(alpha: 0.25)
          ..style = PaintingStyle.fill,
      );
    }

    final bp = Paint()
      ..color = isWholeDrawingFrameSelected ? Colors.green : _fb
      ..style = PaintingStyle.stroke
      ..strokeWidth = isWholeDrawingFrameSelected ? 3.0 : 1.5;

    // الكود الجديد:
    if (_hasEffectiveBottomFrame) {
      // إذا كان الإطار مدمجاً ومفعلاً الغطاء، لا نرسم outerPath هنا لأنه يُرسم موحداً في دالة الغطاء
      if (!model.isIntegratedFrame || !_shouldDrawSideCovers) {
        canvas.drawPath(outerPath, bp);
      }
      canvas.drawPath(
        innerPath,
        bp..strokeWidth = isWholeDrawingFrameSelected ? 1.5 : 0.8,
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
        bp..strokeWidth = isWholeDrawingFrameSelected ? 1.5 : 0.8,
      );

      // With no lower frame, both jambs terminate with square cuts.
      canvas.drawLine(Offset(0, h), Offset(t, h), bp);
      canvas.drawLine(Offset(w - t, h), Offset(w, h), bp);

      // Removing the bottom frame applies only below opening sashes. Fixed
      // cells still sit on their own lower frame segment. Zone coordinates
      // are global, so translate them into this physical frame's local space.
      final frame = sourceFrame ?? Rect.fromLTRB(0, topY, w, h);
      for (final zone in model.zones) {
        if (!frame.contains(zone.boundary.center)) continue;
        final isBottomBound =
            (zone.boundary.bottom - (frame.bottom - t)).abs() < 5.0 ||
            zone.boundary.bottom >= frame.bottom - t;
        final isFixed =
            zone.content == ZoneContent.fixedGlass ||
            zone.content == ZoneContent.empty;
        if (!isBottomBound || !isFixed) continue;

        final touchesLeft = (zone.boundary.left - (frame.left + t)).abs() < 5.0;
        final touchesRight =
            (zone.boundary.right - (frame.right - t)).abs() < 5.0;
        final left = touchesLeft ? 0.0 : zone.boundary.left - frame.left;
        final right = touchesRight ? w : zone.boundary.right - frame.left;
        if (right <= left) continue;

        final segment = Rect.fromLTRB(left, h - t, right, h);
        canvas.drawRect(segment, _buildPaint(segment));
        canvas.drawRect(
          segment,
          bp..strokeWidth = isWholeDrawingFrameSelected ? 1.5 : 0.8,
        );
      }
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
      ..color = _fb
      ..strokeWidth = 1.55
      ..style = PaintingStyle.stroke;

    // عند الإطار المدمج مع ستار: الزوايا العلوية عمودية 90° لا مائلة 45°
    if (!(model.hasShutter && model.isIntegratedFrame)) {
      canvas.drawLine(outer.topLeft, inner.topLeft, p);
      canvas.drawLine(outer.topRight, inner.topRight, p);
    }
    if (_hasEffectiveBottomFrame) {
      canvas.drawLine(outer.bottomLeft, inner.bottomLeft, p);
      canvas.drawLine(outer.bottomRight, inner.bottomRight, p);
    }
  }

  void _drawCustomSideCovers(Canvas canvas, double w, double h, double topY) {
    final segments = model.effectiveSideCoverSegments;
    if (!_shouldDrawSideCovers || segments.isEmpty) return;

    final paint = Paint();
    if (_isWoodColor() && TextureCache.woodTexture != null) {
      _applyWoodShader(paint, Rect.fromLTRB(-100, -100, w + 100, h + 100));
    } else {
      paint.color = _fc[1];
    }
    final borderPaint = Paint()
      ..color = _fb
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.15;

    // Normalise every visible segment once, then use the adjacent segments to
    // decide whether an endpoint is welded at 45° or simply cut at 90°.
    // A partial cover must not change the cut of the unrelated sides.
    final geometry = <String, Map<String, double>>{};
    for (final segment in segments) {
      final isVertical = segment.side == 'left' || segment.side == 'right';
      final sideLength = isVertical ? h - topY : w;
      if (sideLength <= 0) continue;

      final start = segment.startOffset.clamp(0.0, sideLength).toDouble();
      final end = segment.endOffset.clamp(0.0, sideLength).toDouble();
      if (end <= start) continue;
      // A custom value is a visible projection, never an instruction to let
      // a cover grow beyond the selected cover profile itself.  This also
      // repairs older drawings that accidentally stored a larger value.
      final fallbackCoverWidth = _drawableStandaloneSideCoverWidth;
      final visible =
          (segment.visibleWidth > 0 ? segment.visibleWidth : fallbackCoverWidth)
              .clamp(0.0, fallbackCoverWidth)
              .toDouble();
      if (visible <= 0) continue;
      geometry[segment.side] = {'start': start, 'end': end, 'visible': visible};
    }
    if (geometry.isEmpty) return;

    bool reachesStart(String side) =>
        (geometry[side]?['start'] ?? double.infinity) <= 0.1;
    bool reachesEnd(String side) {
      final data = geometry[side];
      if (data == null) return false;
      final sideLength = (side == 'left' || side == 'right') ? h - topY : w;
      return (sideLength - (data['end'] ?? 0.0)).abs() <= 0.1;
    }

    // A 45° joint exists only where both covers really meet at the outside
    // corner. For example, a right cover ending halfway down is 45° at the
    // top (if the top cover is enabled), but its lower end stays a 90° cut.
    // At the bottom, however, the real lower frame is itself the closing
    // member. Therefore a vertical cover must still be mitred when the user
    // hides only the standalone bottom cover.
    final joinTopLeft = reachesStart('top') && reachesStart('left');
    final joinTopRight = reachesEnd('top') && reachesStart('right');
    final joinBottomLeft = _hasEffectiveBottomFrame && reachesEnd('left');
    final joinBottomRight = _hasEffectiveBottomFrame && reachesEnd('right');

    // Where two covers meet with different visible widths, only the common
    // part is welded at 45°.  The excess of the wider profile is cut square
    // at that same point.  Drawing both pieces with their own full width was
    // what made a partial cover spill past the adjacent frame side.
    double jointSpan(String first, String second, bool joins) {
      if (!joins) return 0.0;
      return math.min(
        geometry[first]!['visible']!,
        geometry[second]!['visible']!,
      );
    }

    double bottomFrameJointSpan(String side, bool joins) {
      if (!joins) return 0.0;
      final verticalWidth = geometry[side]!['visible']!;
      final bottom = geometry['bottom'];
      final bottomTouchesCorner =
          bottom != null &&
          (side == 'left' ? reachesStart('bottom') : reachesEnd('bottom'));
      final bottomWidth = bottomTouchesCorner ? bottom!['visible'] : null;
      return math.min(verticalWidth, bottomWidth ?? verticalWidth);
    }

    final topLeftSpan = jointSpan('top', 'left', joinTopLeft);
    final topRightSpan = jointSpan('top', 'right', joinTopRight);
    final bottomLeftSpan = bottomFrameJointSpan('left', joinBottomLeft);
    final bottomRightSpan = bottomFrameJointSpan('right', joinBottomRight);

    for (final entry in geometry.entries) {
      final side = entry.key;
      final data = entry.value;
      final start = data['start']!;
      final end = data['end']!;
      final visible = data['visible']!;
      final Path path;

      switch (side) {
        case 'left':
          final topSpan = topLeftSpan;
          final bottomSpan = bottomLeftSpan;
          path = Path()
            ..moveTo(0, topY + start)
            ..lineTo(topSpan > 0 ? -topSpan : -visible, topY + start - topSpan);
          if (topSpan > 0 && visible > topSpan) {
            path.lineTo(-visible, topY + start - topSpan);
          }
          path.lineTo(-visible, topY + end + bottomSpan);
          if (bottomSpan > 0 && visible > bottomSpan) {
            path.lineTo(-bottomSpan, topY + end + bottomSpan);
          }
          path
            ..lineTo(0, topY + end)
            ..close();
          break;
        case 'right':
          final topSpan = topRightSpan;
          final bottomSpan = bottomRightSpan;
          path = Path()
            ..moveTo(w, topY + start)
            ..lineTo(
              w + (topSpan > 0 ? topSpan : visible),
              topY + start - topSpan,
            );
          if (topSpan > 0 && visible > topSpan) {
            path.lineTo(w + visible, topY + start - topSpan);
          }
          path.lineTo(w + visible, topY + end + bottomSpan);
          if (bottomSpan > 0 && visible > bottomSpan) {
            path.lineTo(w + bottomSpan, topY + end + bottomSpan);
          }
          path
            ..lineTo(w, topY + end)
            ..close();
          break;
        case 'top':
          final leftSpan = topLeftSpan;
          final rightSpan = topRightSpan;
          path = Path()
            ..moveTo(start, topY)
            ..lineTo(end, topY)
            ..lineTo(
              end + rightSpan,
              topY - (rightSpan > 0 ? rightSpan : visible),
            );
          if (rightSpan > 0 && visible > rightSpan) {
            path.lineTo(end + rightSpan, topY - visible);
          }
          path.lineTo(start - leftSpan, topY - visible);
          if (leftSpan > 0 && visible > leftSpan) {
            path.lineTo(start - leftSpan, topY - leftSpan);
          }
          path
            ..lineTo(start, topY)
            ..close();
          break;
        case 'bottom':
          if (!_hasEffectiveBottomFrame) continue;
          final leftSpan = bottomLeftSpan;
          final rightSpan = bottomRightSpan;
          path = Path()
            ..moveTo(start, h)
            ..lineTo(end, h)
            ..lineTo(
              end + rightSpan,
              h + (rightSpan > 0 ? rightSpan : visible),
            );
          if (rightSpan > 0 && visible > rightSpan) {
            path.lineTo(end + rightSpan, h + visible);
          }
          path.lineTo(start - leftSpan, h + visible);
          if (leftSpan > 0 && visible > leftSpan) {
            path.lineTo(start - leftSpan, h + leftSpan);
          }
          path
            ..lineTo(start, h)
            ..close();
          break;
        default:
          continue;
      }
      canvas.drawPath(path, paint);
      canvas.drawPath(path, borderPaint);
    }
  }

  void _drawConfiguredSideCovers(
    Canvas canvas,
    double w,
    double h,
    double topY,
  ) {
    if (!_shouldDrawSideCovers) return;
    final coverWidth = model.isIntegratedFrame
        ? model.integratedFrameSideCoverWidth
        : _drawableStandaloneSideCoverWidth;
    if (coverWidth <= 0) return;

    // In a multi-frame drawing the cover follows the outside perimeter of
    // the real frames. Drawing one cover around the full window rectangle
    // leaves a cover floating over empty areas when a frame is only above one
    // part of another row.
    if (model.getFrameRects().length > 1) {
      _drawMultiFrameSideCovers(canvas, coverWidth);
      return;
    }

    if (!model.isIntegratedFrame && model.useCustomSideCoverLayout) {
      final segments = model.effectiveSideCoverSegments;
      if (segments.isNotEmpty) {
        _drawCustomSideCovers(canvas, w, h, topY);
        return;
      }

      // Old/restored drawings can keep the custom flag without any stored
      // segment. In that state the user has enabled a standalone cover, so
      // render the normal full surround instead of silently drawing nothing.
      if (model.hiddenSideCoverSegments.isNotEmpty) return;
    }

    _drawSideCovers(canvas, w, h, topY, coverWidth);
  }

  void _drawMultiFrameSideCovers(Canvas canvas, double coverWidth) {
    // A regular shutter box sits above all physical frame rectangles. Its
    // cover therefore needs its own short perimeter; the exposed-frame
    // segments below do not include this area.
    if (model.hasShutter &&
        !model.isCaissonTunnel &&
        model.shutterBoxHeight > 0) {
      _drawMultiFrameShutterBoxCover(
        canvas,
        model.width,
        model.shutterBoxHeight,
        coverWidth,
      );
    }

    final edges = model.getExposedFrameEdgeSegments();
    if (edges.isEmpty) return;

    final paint = Paint();
    if (_isWoodColor() && TextureCache.woodTexture != null) {
      _applyWoodShader(
        paint,
        Rect.fromLTWH(
          -coverWidth,
          -coverWidth,
          model.width + coverWidth * 2,
          model.height + coverWidth * 2,
        ),
      );
    } else {
      paint.color = _fc[1];
    }
    final borderPaint = Paint()
      ..color = _fb
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    // Keep the real exposed perimeter, including custom side selections.
    // Each piece carries its own visible width because a side may have been
    // edited independently from the other sides.
    final customSegments = model.useCustomSideCoverLayout
        ? model.effectiveSideCoverSegments
        : const <SideCoverSegment>[];
    final pieces = <({FrameEdgeSegment edge, double visible})>[];

    for (final edge in edges) {
      // The box already has an outer cover. Its contact with the frame is
      // an internal seam, so it must not receive another top cover.
      if (edge.side == 'top' && _frameTopTouchesShutterBox(edge.coordinate)) {
        continue;
      }
      if (model.hiddenSideCoverSegments.contains(edge.side) ||
          model.removedShutterSides.contains(edge.side) ||
          (edge.side == 'bottom' && !_hasEffectiveBottomFrame)) {
        continue;
      }

      final spans = customSegments.isEmpty
          ? <SideCoverSegment>[
              SideCoverSegment(
                side: edge.side,
                startOffset: edge.start,
                endOffset: edge.end,
                visibleWidth: coverWidth,
              ),
            ]
          : customSegments
                .where((segment) => segment.side == edge.side)
                .toList();

      for (final span in spans) {
        final start = math.max(edge.start, span.startOffset);
        final end = math.min(edge.end, span.endOffset);
        if (end <= start) continue;
        final visible = (span.visibleWidth > 0 ? span.visibleWidth : coverWidth)
            .clamp(0.0, coverWidth)
            .toDouble();
        if (visible <= 0) continue;
        pieces.add((
          edge: FrameEdgeSegment(
            side: edge.side,
            start: start,
            end: end,
            coordinate: edge.coordinate,
          ),
          visible: visible,
        ));
      }
    }
    if (pieces.isEmpty) return;

    const tolerance = 2.0;
    bool isHorizontal(String side) => side == 'top' || side == 'bottom';

    Offset endpointOf(
      ({FrameEdgeSegment edge, double visible}) piece,
      bool atStart,
    ) {
      final edge = piece.edge;
      final axis = atStart ? edge.start : edge.end;
      return isHorizontal(edge.side)
          ? Offset(axis, edge.coordinate)
          : Offset(edge.coordinate, axis);
    }

    bool pointTouchesEdge(Offset point, FrameEdgeSegment edge) {
      if (isHorizontal(edge.side)) {
        return (point.dy - edge.coordinate).abs() <= tolerance &&
            point.dx >= edge.start - tolerance &&
            point.dx <= edge.end + tolerance;
      }
      return (point.dx - edge.coordinate).abs() <= tolerance &&
          point.dy >= edge.start - tolerance &&
          point.dy <= edge.end + tolerance;
    }

    bool isEdgeEndpoint(Offset point, FrameEdgeSegment edge) {
      final startPoint = isHorizontal(edge.side)
          ? Offset(edge.start, edge.coordinate)
          : Offset(edge.coordinate, edge.start);
      final endPoint = isHorizontal(edge.side)
          ? Offset(edge.end, edge.coordinate)
          : Offset(edge.coordinate, edge.end);
      return (point - startPoint).distance <= tolerance ||
          (point - endPoint).distance <= tolerance;
    }

    Offset rayIntoEdge(FrameEdgeSegment edge, Offset point) {
      final startPoint = isHorizontal(edge.side)
          ? Offset(edge.start, edge.coordinate)
          : Offset(edge.coordinate, edge.start);
      final isAtStart = (point - startPoint).distance <= tolerance;
      if (isHorizontal(edge.side)) {
        return Offset(isAtStart ? 1.0 : -1.0, 0.0);
      }
      return Offset(0.0, isAtStart ? 1.0 : -1.0);
    }

    // Do not inflate the rectangles here.  The sample is deliberately taken
    // inside the quadrant formed by the two edge rays; expanding the frame
    // would incorrectly turn a narrow recessed corner into an outside one.
    bool frameContains(Offset point) =>
        model.getFrameRects().any((rect) => rect.contains(point));

    bool isBottomFrameEndpoint(
      ({FrameEdgeSegment edge, double visible}) piece,
      bool atStart,
    ) {
      if (isHorizontal(piece.edge.side)) {
        return false;
      }
      // A vertical exposed edge that reaches the physical frame's bottom is
      // closed by that frame even when the optional bottom cover was hidden.
      final point = endpointOf(piece, atStart);
      if (atStart) return false;
      return model.getFrameRects().any(
        (rect) =>
            model.hasBottomFrameForRect(rect) &&
            (point.dy - rect.bottom).abs() <= tolerance &&
            ((point.dx - rect.left).abs() <= tolerance ||
                (point.dx - rect.right).abs() <= tolerance),
      );
    }

    // Return the common width and the corner direction.  The old code
    // treated every perpendicular meeting as an outside corner and extended
    // both covers past it.  At a recessed/inside corner that creates the
    // wrong diagonal.  Looking at the quadrant immediately inside the two
    // edge rays tells us which miter is needed:
    //   - occupied quadrant: normal outside (convex) miter;
    //   - empty quadrant: inverse (concave) 45-degree miter.
    ({double width, bool isConvex})? jointAt(
      ({FrameEdgeSegment edge, double visible}) piece,
      bool atStart,
    ) {
      final point = endpointOf(piece, atStart);
      var result = double.infinity;
      for (final other in pieces) {
        if (identical(other, piece) ||
            isHorizontal(other.edge.side) == isHorizontal(piece.edge.side)) {
          continue;
        }
        if (!pointTouchesEdge(point, other.edge) ||
            !isEdgeEndpoint(point, other.edge)) {
          continue;
        }

        final rayA = rayIntoEdge(piece.edge, point);
        final rayB = rayIntoEdge(other.edge, point);
        const sampleDistance = 1.0;
        final cornerSample =
            point +
            Offset(rayA.dx + rayB.dx, rayA.dy + rayB.dy) * sampleDistance;
        result = math.min(result, other.visible);
        return (
          width: math.min(result, piece.visible),
          isConvex: frameContains(cornerSample),
        );
      }
      if (isBottomFrameEndpoint(piece, atStart)) {
        return (width: piece.visible, isConvex: true);
      }
      return null;
    }

    Path piecePath(({FrameEdgeSegment edge, double visible}) piece) {
      final edge = piece.edge;
      final visible = piece.visible;
      final startCorner = jointAt(piece, true);
      final endCorner = jointAt(piece, false);
      // Outside corners extend away from the endpoint.  Inside corners use
      // the opposite sign, trimming the two covers into a true 45-degree
      // joint instead of producing a square/extra piece in the empty area.
      final startJoint = startCorner == null
          ? 0.0
          : (startCorner.isConvex ? 1.0 : -1.0) * startCorner.width;
      final endJoint = endCorner == null
          ? 0.0
          : (endCorner.isConvex ? 1.0 : -1.0) * endCorner.width;

      switch (edge.side) {
        case 'top':
          return Path()
            ..moveTo(edge.start, edge.coordinate)
            ..lineTo(edge.end, edge.coordinate)
            ..lineTo(edge.end + endJoint, edge.coordinate - visible)
            ..lineTo(edge.start - startJoint, edge.coordinate - visible)
            ..close();
        case 'bottom':
          return Path()
            ..moveTo(edge.start, edge.coordinate)
            ..lineTo(edge.end, edge.coordinate)
            ..lineTo(edge.end + endJoint, edge.coordinate + visible)
            ..lineTo(edge.start - startJoint, edge.coordinate + visible)
            ..close();
        case 'left':
          return Path()
            ..moveTo(edge.coordinate, edge.start)
            ..lineTo(edge.coordinate, edge.end)
            ..lineTo(edge.coordinate - visible, edge.end + endJoint)
            ..lineTo(edge.coordinate - visible, edge.start - startJoint)
            ..close();
        case 'right':
          return Path()
            ..moveTo(edge.coordinate, edge.start)
            ..lineTo(edge.coordinate, edge.end)
            ..lineTo(edge.coordinate + visible, edge.end + endJoint)
            ..lineTo(edge.coordinate + visible, edge.start - startJoint)
            ..close();
        default:
          return Path();
      }
    }

    // The union removes seams between cover pieces, but a welded corner must
    // still remain visible. Draw the 45-degree cut line for every joined
    // endpoint, including recessed (inside) corners. The sign is the same
    // sign used by piecePath, so an inside corner is the inverse diagonal of
    // an outside corner rather than a square cut.
    Offset miterOuterPoint(
      ({FrameEdgeSegment edge, double visible}) piece,
      bool atStart,
      ({double width, bool isConvex}) joint,
    ) {
      final edge = piece.edge;
      final point = endpointOf(piece, atStart);
      final signedWidth = (joint.isConvex ? 1.0 : -1.0) * joint.width;
      switch (edge.side) {
        case 'top':
          return Offset(
            point.dx + (atStart ? -signedWidth : signedWidth),
            point.dy - piece.visible,
          );
        case 'bottom':
          return Offset(
            point.dx + (atStart ? -signedWidth : signedWidth),
            point.dy + piece.visible,
          );
        case 'left':
          return Offset(
            point.dx - piece.visible,
            point.dy + (atStart ? -signedWidth : signedWidth),
          );
        case 'right':
          return Offset(
            point.dx + piece.visible,
            point.dy + (atStart ? -signedWidth : signedWidth),
          );
        default:
          return point;
      }
    }

    // Union the pieces before painting. This removes internal seams between
    // neighbouring sides and makes the cover behave as one surrounding strip.
    Path? coverPath;
    for (final piece in pieces) {
      final path = piecePath(piece);
      coverPath = coverPath == null
          ? path
          : Path.combine(PathOperation.union, coverPath, path);
    }
    if (coverPath == null) return;

    canvas.drawPath(coverPath, paint);
    _drawMultiFrameCoverOutline(canvas, coverPath, borderPaint);

    // The union retains the silhouette but removes the shared diagonal
    // between two welded cover pieces. Restore that diagonal explicitly.
    final paintedJoints = <String>{};
    canvas.save();
    canvas.clipPath(coverPath);
    for (final piece in pieces) {
      for (final atStart in [true, false]) {
        final joint = jointAt(piece, atStart);
        if (joint == null) continue;
        final inner = endpointOf(piece, atStart);
        final outer = miterOuterPoint(piece, atStart, joint);
        final key =
            '${inner.dx.toStringAsFixed(2)},'
            '${inner.dy.toStringAsFixed(2)}:'
            '${outer.dx.toStringAsFixed(2)},${outer.dy.toStringAsFixed(2)}';
        if (paintedJoints.add(key)) {
          canvas.drawLine(inner, outer, borderPaint);
        }
      }
    }
    canvas.restore();
  }

  void _drawMultiFrameCoverOutline(Canvas canvas, Path path, Paint border) {
    canvas.save();
    if (model.hasShutter && !model.isCaissonTunnel) {
      // Both cover strips continue past the box/frame seam. Their separate
      // closed polygons must not leave a horizontal end-cap on that seam.
      final y = model.shutterBoxHeight;
      final bounds = path.getBounds().inflate(2);
      final clip = Path()..addRect(bounds);
      final caps = Path();
      if (bounds.left < 0) {
        caps.addRect(Rect.fromLTRB(bounds.left, y - 1, 0, y + 1));
      }
      if (bounds.right > model.width) {
        caps.addRect(Rect.fromLTRB(model.width, y - 1, bounds.right, y + 1));
      }
      canvas.clipPath(Path.combine(PathOperation.difference, clip, caps));
    }
    canvas.drawPath(path, border);
    canvas.restore();
  }

  void _drawMultiFrameShutterBoxCover(
    Canvas canvas,
    double w,
    double boxHeight,
    double coverWidth,
  ) {
    final isInternal = overrideIsInternalView ?? model.isInternalView;
    final hasL = isInternal
        ? !model.removedShutterSides.contains('left')
        : !model.removedShutterSides.contains('right');
    final hasR = isInternal
        ? !model.removedShutterSides.contains('right')
        : !model.removedShutterSides.contains('left');
    final hasT = !model.removedShutterSides.contains('top');

    final paint = Paint();
    if (_isWoodColor() && TextureCache.woodTexture != null) {
      _applyWoodShader(
        paint,
        Rect.fromLTRB(-coverWidth, -coverWidth, w + coverWidth, boxHeight),
      );
    } else {
      paint.color = _fc[1];
    }
    final borderPaint = Paint()
      ..color = _fb
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    if (hasL) {
      final path = Path()
        ..moveTo(0, 0)
        ..lineTo(-coverWidth, hasT ? -coverWidth : 0)
        ..lineTo(-coverWidth, boxHeight)
        ..lineTo(0, boxHeight)
        ..close();
      canvas.drawPath(path, paint);
      _drawMultiFrameCoverOutline(canvas, path, borderPaint);
    }
    if (hasR) {
      final path = Path()
        ..moveTo(w, 0)
        ..lineTo(w + coverWidth, hasT ? -coverWidth : 0)
        ..lineTo(w + coverWidth, boxHeight)
        ..lineTo(w, boxHeight)
        ..close();
      canvas.drawPath(path, paint);
      _drawMultiFrameCoverOutline(canvas, path, borderPaint);
    }
    if (hasT) {
      final path = Path()
        ..moveTo(0, 0)
        ..lineTo(hasL ? -coverWidth : 0, -coverWidth)
        ..lineTo(hasR ? w + coverWidth : w, -coverWidth)
        ..lineTo(w, 0)
        ..close();
      canvas.drawPath(path, paint);
      canvas.drawPath(path, borderPaint);
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
    // The lower cover and the lower frame are different states.  A user may
    // hide only the bottom cover while the real lower frame remains present;
    // the vertical cover must still finish against that frame instead of
    // ending with an open cut.
    final hasBottomFrameForJoin = _hasEffectiveBottomFrame;
    final hasB =
        !model.removedShutterSides.contains('bottom') && hasBottomFrameForJoin;

    double yTopL =
        topY + (isInternal ? model.topSlantLeftY : model.topSlantRightY);
    double yTopR =
        topY + (isInternal ? model.topSlantRightY : model.topSlantLeftY);
    double yBottomL =
        h - (isInternal ? model.bottomSlantLeftY : model.bottomSlantRightY);
    double yBottomR =
        h - (isInternal ? model.bottomSlantRightY : model.bottomSlantLeftY);

    double slopeT = (yTopR - yTopL) / w;
    double slopeB = (yBottomR - yBottomL) / w;

    double alphaT = math.atan(slopeT);
    double cosAlphaT = math.cos(alphaT);
    double cW_vOffset = cW / cosAlphaT;

    double alphaB = math.atan(slopeB);
    double cosAlphaB = math.cos(alphaB);
    double cW_vOffsetB = cW / cosAlphaB;

    final bool isIntegrated = model.isIntegratedFrame;

    // رسم مسارات التعبئة (Fill) أولاً لكل جهة
    void drawCoverSegment({
      required Path path,
      required Offset outerStart,
      required Offset outerEnd,
      required Offset innerStart,
      required Offset innerEnd,
      required bool hasStartJoin,
      required bool hasEndJoin,
    }) {
      // 1. تعبئة اللون (سواء خشب أو لون عادي)
      canvas.drawPath(path, paint);

      if (!isIntegrated) {
        // إذا كان غطاء منفصلاً، نرسم حدوده كاملة مع الخط الفاصل
        canvas.drawPath(path, borderPaint);
      } else {
        // إذا كان إطاراً مدمجاً: نرسم فقط الحد الخارجي وخطوط زوايا 45° الخارجية
        // ولا نرسم الخط الداخلي المشترك مع الحلق
        final outerEdge = Path()
          ..moveTo(outerStart.dx, outerStart.dy)
          ..lineTo(outerEnd.dx, outerEnd.dy);
        canvas.drawPath(outerEdge, borderPaint);

        // خط زاوية البداية المائل 45°
        if (hasStartJoin) {
          canvas.drawLine(outerStart, innerStart, borderPaint);
        }
        // خط زاوية النهاية المائل 45°
        if (hasEndJoin) {
          canvas.drawLine(outerEnd, innerEnd, borderPaint);
        }
      }
    }

    if (hasL) {
      final pInnerStart = Offset(0, yTopL);
      final pOuterStart = Offset(
        -cW,
        yTopL - (hasT ? cW_vOffset : 0.0) - slopeT * cW,
      );
      final pOuterEnd = Offset(
        -cW,
        yBottomL + (hasBottomFrameForJoin ? cW_vOffsetB : 0.0) - slopeB * cW,
      );
      final pInnerEnd = Offset(0, yBottomL);

      final path = Path()
        ..moveTo(pInnerStart.dx, pInnerStart.dy)
        ..lineTo(pOuterStart.dx, pOuterStart.dy)
        ..lineTo(pOuterEnd.dx, pOuterEnd.dy)
        ..lineTo(pInnerEnd.dx, pInnerEnd.dy)
        ..close();

      drawCoverSegment(
        path: path,
        outerStart: pOuterStart,
        outerEnd: pOuterEnd,
        innerStart: pInnerStart,
        innerEnd: pInnerEnd,
        hasStartJoin: hasT,
        hasEndJoin: hasBottomFrameForJoin,
      );
    }

    if (hasR) {
      final pInnerStart = Offset(w, yTopR);
      final pOuterStart = Offset(
        w + cW,
        yTopR - (hasT ? cW_vOffset : 0.0) + slopeT * cW,
      );
      final pOuterEnd = Offset(
        w + cW,
        yBottomR + (hasBottomFrameForJoin ? cW_vOffsetB : 0.0) + slopeB * cW,
      );
      final pInnerEnd = Offset(w, yBottomR);

      final path = Path()
        ..moveTo(pInnerStart.dx, pInnerStart.dy)
        ..lineTo(pOuterStart.dx, pOuterStart.dy)
        ..lineTo(pOuterEnd.dx, pOuterEnd.dy)
        ..lineTo(pInnerEnd.dx, pInnerEnd.dy)
        ..close();

      drawCoverSegment(
        path: path,
        outerStart: pOuterStart,
        outerEnd: pOuterEnd,
        innerStart: pInnerStart,
        innerEnd: pInnerEnd,
        hasStartJoin: hasT,
        hasEndJoin: hasBottomFrameForJoin,
      );
    }

    if (hasT) {
      final pInnerStart = Offset(0, yTopL);
      final pOuterStart = Offset(
        hasL ? -cW : 0.0,
        yTopL - cW_vOffset - (hasL ? slopeT * cW : 0.0),
      );
      final pOuterEnd = Offset(
        hasR ? w + cW : w,
        yTopR - cW_vOffset + (hasR ? slopeT * cW : 0.0),
      );
      final pInnerEnd = Offset(w, yTopR);

      final path = Path()
        ..moveTo(pInnerStart.dx, pInnerStart.dy)
        ..lineTo(pOuterStart.dx, pOuterStart.dy);

      if (model.archHeight > 0) {
        path.quadraticBezierTo(
          w / 2,
          topY +
              math.min(model.topSlantLeftY, model.topSlantRightY) -
              (model.archHeight * 2) -
              cW_vOffset,
          pOuterEnd.dx,
          pOuterEnd.dy,
        );
        path.lineTo(pInnerEnd.dx, pInnerEnd.dy);
        path.quadraticBezierTo(
          w / 2,
          topY +
              math.min(model.topSlantLeftY, model.topSlantRightY) -
              (model.archHeight * 2),
          pInnerStart.dx,
          pInnerStart.dy,
        );
      } else {
        path.lineTo(pOuterEnd.dx, pOuterEnd.dy);
        path.lineTo(pInnerEnd.dx, pInnerEnd.dy);
        path.lineTo(pInnerStart.dx, pInnerStart.dy);
      }
      path.close();

      drawCoverSegment(
        path: path,
        outerStart: pOuterStart,
        outerEnd: pOuterEnd,
        innerStart: pInnerStart,
        innerEnd: pInnerEnd,
        hasStartJoin: hasL,
        hasEndJoin: hasR,
      );
    }

    if (hasB) {
      final pInnerStart = Offset(0, yBottomL);
      final pOuterStart = Offset(
        hasL ? -cW : 0.0,
        yBottomL + cW_vOffsetB - (hasL ? slopeB * cW : 0.0),
      );
      final pOuterEnd = Offset(
        hasR ? w + cW : w,
        yBottomR + cW_vOffsetB + (hasR ? slopeB * cW : 0.0),
      );
      final pInnerEnd = Offset(w, yBottomR);

      final path = Path()
        ..moveTo(pInnerStart.dx, pInnerStart.dy)
        ..lineTo(pOuterStart.dx, pOuterStart.dy)
        ..lineTo(pOuterEnd.dx, pOuterEnd.dy)
        ..lineTo(pInnerEnd.dx, pInnerEnd.dy)
        ..close();

      drawCoverSegment(
        path: path,
        outerStart: pOuterStart,
        outerEnd: pOuterEnd,
        innerStart: pInnerStart,
        innerEnd: pInnerEnd,
        hasStartJoin: hasL,
        hasEndJoin: hasR,
      );
    }
  }

  void _drawMullions(Canvas canvas, double w, double h, double t) {
    final double topOffset = _topOffset;
    final double mullionT = model.mullionThickness;
    final Paint paint = Paint();
    if (_isWoodColor() && TextureCache.woodTexture != null) {
      _applyWoodShader(paint, Rect.fromLTWH(0, 0, w, h));
    } else {
      final Color baseColor = _fc[1];
      if (baseColor == Colors.white || baseColor.value == 0xFFFFFFFF) {
        paint.color = const Color(0xFFE2E8F0);
      } else {
        paint.color = baseColor;
      }
    }
    paint.style = PaintingStyle.fill;
    final Paint border = Paint()
      ..color = (_fb == Colors.white || _fb.value == 0xFFFFFFFF)
          ? const Color(0xFF475569)
          : _fb
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    final List<_MullionSegment> horizontalSegments = [];
    final List<_MullionSegment> verticalSegments = [];
    final physicalFrames = model.getFrameRects();
    int ownerOf(WindowZone zone) => physicalFrames.indexWhere(
      (frame) => frame.contains(zone.boundary.center),
    );

    bool verticalMullionShouldReachFloor(double x, double bottom) {
      if (_hasEffectiveBottomFrame) return false;
      if ((bottom - (h - t)).abs() > math.max(15.0, mullionT + 4.0)) {
        return false;
      }
      return model.zones.any((z) {
        final r = z.boundary;
        final isAdjacent =
            (r.right - x).abs() <= mullionT + 4.0 ||
            (r.left - x).abs() <= mullionT + 4.0;
        return isAdjacent && r.bottom >= h - t - 2.0;
      });
    }

    for (int i = 0; i < model.zones.length; i++) {
      final z1 = model.zones[i];
      for (int j = i + 1; j < model.zones.length; j++) {
        final z2 = model.zones[j];

        // Coupled frames already have their own two jambs. A mullion only
        // belongs between panes inside the same physical frame.
        if (ownerOf(z1) != ownerOf(z2)) continue;

        // Check for horizontal boundary
        double overlapLeft = math.max(z1.boundary.left, z2.boundary.left);
        double overlapRight = math.min(z1.boundary.right, z2.boundary.right);
        if (overlapLeft < overlapRight - 5.0) {
          if ((z1.boundary.bottom - z2.boundary.top).abs() <= mullionT + 2.0) {
            double yCenter = (z1.boundary.bottom + z2.boundary.top) / 2;
            horizontalSegments.add(
              _MullionSegment(
                position: yCenter,
                start: overlapLeft,
                end: overlapRight,
              ),
            );
          } else if ((z2.boundary.bottom - z1.boundary.top).abs() <=
              mullionT + 2.0) {
            double yCenter = (z2.boundary.bottom + z1.boundary.top) / 2;
            horizontalSegments.add(
              _MullionSegment(
                position: yCenter,
                start: overlapLeft,
                end: overlapRight,
              ),
            );
          }
        }

        // Check for vertical boundary
        double overlapTop = math.max(z1.boundary.top, z2.boundary.top);
        double overlapBottom = math.min(z1.boundary.bottom, z2.boundary.bottom);
        if (overlapTop < overlapBottom - 5.0) {
          if ((z1.boundary.right - z2.boundary.left).abs() <= mullionT + 2.0) {
            double xCenter = (z1.boundary.right + z2.boundary.left) / 2;
            verticalSegments.add(
              _MullionSegment(
                position: xCenter,
                start: overlapTop,
                end: overlapBottom,
              ),
            );
          } else if ((z2.boundary.right - z1.boundary.left).abs() <=
              mullionT + 2.0) {
            double xCenter = (z2.boundary.right + z1.boundary.left) / 2;
            verticalSegments.add(
              _MullionSegment(
                position: xCenter,
                start: overlapTop,
                end: overlapBottom,
              ),
            );
          }
        }
      }
    }

    // 🟢 احترام الأولوية التي بدأ بها المستخدم دون فرض الأفقي
    final String effectivePrimary = model.primaryMullionAxis ?? 'h';
    final List<_MullionVisual> mullions = [];

    // Helper functions for mullion dimensions
    double getMullionThickness(bool isH, double pos) {
      if (model.isDoubleFrameMullionAt(isH, pos)) {
        return _frameProfileWidthAt(isH, pos) * 2.0;
      }
      if (model.isGroovedFrameMullionAt(isH, pos)) {
        return _frameProfileWidthAt(isH, pos);
      }
      return mullionT;
    }

    final List<_MullionSegment> mergedH = _mergeMullionSegments(
      horizontalSegments,
      mullionT,
    );
    final List<_MullionSegment> mergedV = _mergeMullionSegments(
      verticalSegments,
      mullionT,
    );

    // Checks if horizontal mullion h cuts through vertical mullion v
    bool hCutsV(_MullionSegment h, _MullionSegment v) {
      final vThick = getMullionThickness(false, v.position);
      if (h.position <= v.start + 5.0 || h.position >= v.end - 5.0)
        return false;
      if (v.position < h.start - vThick / 2 - 2.0 ||
          v.position > h.end + vThick / 2 + 2.0)
        return false;

      final vIsDouble = model.isDoubleFrameMullionAt(false, v.position);
      final hIsDouble = model.isDoubleFrameMullionAt(true, h.position);

      if (vIsDouble && !hIsDouble) return false;
      if (hIsDouble && !vIsDouble) return true;

      // If h only terminates at v (T-junction from left or right), h never cuts v
      final hPassesThrough =
          (h.start < v.position - vThick / 2 - 5.0) &&
          (h.end > v.position + vThick / 2 + 5.0);
      if (!hPassesThrough) return false;

      // Both pass through (4-way cross junction):
      // 🟢 احترام أسبقية الإنشاء: التقسيم الأقدم في تاريخ النافذة يسبق ويقطع الأحدث
      final hOrder = model.getMullionCreationOrder(true, h.position);
      final vOrder = model.getMullionCreationOrder(false, v.position);
      if (hOrder < vOrder) return true;
      if (vOrder < hOrder) return false;

      return effectivePrimary == 'h';
    }

    // Checks if vertical mullion v cuts through horizontal mullion h
    bool vCutsH(_MullionSegment v, _MullionSegment h) {
      final vThick = getMullionThickness(false, v.position);
      final hThick = getMullionThickness(true, h.position);
      if (v.position <= h.start + 5.0 || v.position >= h.end - 5.0)
        return false;
      if (h.position < v.start - hThick / 2 - 2.0 ||
          h.position > v.end + hThick / 2 + 2.0)
        return false;

      final vIsDouble = model.isDoubleFrameMullionAt(false, v.position);
      final hIsDouble = model.isDoubleFrameMullionAt(true, h.position);

      if (hIsDouble && !vIsDouble) return false;
      if (vIsDouble && !hIsDouble) return true;

      // If v only terminates at h (T-junction from top or bottom), v never cuts h
      final vPassesThrough =
          (v.start < h.position - hThick / 2 - 5.0) &&
          (v.end > h.position + hThick / 2 + 5.0);
      if (!vPassesThrough) return false;

      // Both pass through (4-way cross junction):
      // 🟢 احترام أسبقية الإنشاء: التقسيم الأقدم في تاريخ النافذة يسبق ويقطع الأحدث
      final hOrder = model.getMullionCreationOrder(true, h.position);
      final vOrder = model.getMullionCreationOrder(false, v.position);
      if (vOrder < hOrder) return true;
      if (hOrder < vOrder) return false;

      return effectivePrimary == 'v';
    }

    // 1. Process Vertical Mullions
    for (final v in mergedV) {
      final x = v.position;
      final vThick = getMullionThickness(false, x);
      double top = v.start - mullionT / 2;
      double bottom = v.end + mullionT / 2;

      // Check if top terminates at an uncut horizontal mullion
      for (final h in mergedH) {
        final hThick = getMullionThickness(true, h.position);
        if ((v.start - h.position).abs() <= hThick / 2 + 5.0 &&
            x >= h.start - vThick / 2 - 2.0 &&
            x <= h.end + vThick / 2 + 2.0) {
          if (!vCutsH(v, h)) {
            top = h.position + hThick / 2 - 0.8;
          }
        }
      }

      if ((v.start - (topOffset + t)).abs() < 5.0) {
        top = getInnerTopY(x, t, topOffset);
      }

      // Check if bottom terminates at an uncut horizontal mullion
      for (final h in mergedH) {
        final hThick = getMullionThickness(true, h.position);
        if ((v.end - h.position).abs() <= hThick / 2 + 5.0 &&
            x >= h.start - vThick / 2 - 2.0 &&
            x <= h.end + vThick / 2 + 2.0) {
          if (!vCutsH(v, h)) {
            bottom = h.position - hThick / 2 + 0.8;
          }
        }
      }

      if (verticalMullionShouldReachFloor(x, bottom)) {
        bottom = h;
      }

      // Find all horizontal mullions that cut this vertical mullion
      final cuts = <_MullionSegment>[];
      for (final h in mergedH) {
        if (hCutsV(h, v)) {
          cuts.add(h);
        }
      }
      cuts.sort((a, b) => a.position.compareTo(b.position));

      if (cuts.isEmpty) {
        if (bottom > top + 1.0) {
          mullions.add(
            _MullionVisual(
              rect: Rect.fromLTRB(x - vThick / 2, top, x + vThick / 2, bottom),
              isHorizontal: false,
              position: x,
              isPrimary: true,
            ),
          );
        }
      } else {
        double currentTop = top;
        for (final cutH in cuts) {
          final hThick = getMullionThickness(true, cutH.position);
          final pieceBottom = cutH.position - hThick / 2 + 0.8;
          if (pieceBottom > currentTop + 1.0) {
            mullions.add(
              _MullionVisual(
                rect: Rect.fromLTRB(
                  x - vThick / 2,
                  currentTop,
                  x + vThick / 2,
                  pieceBottom,
                ),
                isHorizontal: false,
                position: x,
                isPrimary: false,
              ),
            );
          }
          currentTop = cutH.position + hThick / 2 - 0.8;
        }
        if (bottom > currentTop + 1.0) {
          mullions.add(
            _MullionVisual(
              rect: Rect.fromLTRB(
                x - vThick / 2,
                currentTop,
                x + vThick / 2,
                bottom,
              ),
              isHorizontal: false,
              position: x,
              isPrimary: false,
            ),
          );
        }
      }
    }

    // 2. Process Horizontal Mullions
    for (final h in mergedH) {
      final y = h.position;
      final hThick = getMullionThickness(true, y);
      double left = h.start - mullionT / 2;
      double right = h.end + mullionT / 2;

      // Check if left terminates at an uncut vertical mullion
      for (final v in mergedV) {
        final vThick = getMullionThickness(false, v.position);
        if ((h.start - v.position).abs() <= vThick / 2 + 5.0 &&
            y >= v.start - hThick / 2 - 2.0 &&
            y <= v.end + hThick / 2 + 2.0) {
          if (!hCutsV(h, v)) {
            left = v.position + vThick / 2 - 0.8;
          }
        }
      }

      // Check if right terminates at an uncut vertical mullion
      for (final v in mergedV) {
        final vThick = getMullionThickness(false, v.position);
        if ((h.end - v.position).abs() <= vThick / 2 + 5.0 &&
            y >= v.start - hThick / 2 - 2.0 &&
            y <= v.end + hThick / 2 + 2.0) {
          if (!hCutsV(h, v)) {
            right = v.position - vThick / 2 + 0.8;
          }
        }
      }

      // Find all vertical mullions that cut this horizontal mullion
      final cuts = <_MullionSegment>[];
      for (final v in mergedV) {
        if (vCutsH(v, h)) {
          cuts.add(v);
        }
      }
      cuts.sort((a, b) => a.position.compareTo(b.position));

      if (cuts.isEmpty) {
        if (right > left + 1.0) {
          mullions.add(
            _MullionVisual(
              rect: Rect.fromLTRB(left, y - hThick / 2, right, y + hThick / 2),
              isHorizontal: true,
              position: y,
              isPrimary: true,
            ),
          );
        }
      } else {
        double currentLeft = left;
        for (final cutV in cuts) {
          final vThick = getMullionThickness(false, cutV.position);
          final pieceRight = cutV.position - vThick / 2 + 0.8;
          if (pieceRight > currentLeft + 1.0) {
            mullions.add(
              _MullionVisual(
                rect: Rect.fromLTRB(
                  currentLeft,
                  y - hThick / 2,
                  pieceRight,
                  y + hThick / 2,
                ),
                isHorizontal: true,
                position: y,
                isPrimary: false,
              ),
            );
          }
          currentLeft = cutV.position + vThick / 2 - 0.8;
        }
        if (right > currentLeft + 1.0) {
          mullions.add(
            _MullionVisual(
              rect: Rect.fromLTRB(
                currentLeft,
                y - hThick / 2,
                right,
                y + hThick / 2,
              ),
              isHorizontal: true,
              position: y,
              isPrimary: false,
            ),
          );
        }
      }
    }

    void drawMullion(_MullionVisual mullion) {
      if (mullion.rect.width <= 0 || mullion.rect.height <= 0) return;

      if (model.isGroovedFrameMullionAt(
        mullion.isHorizontal,
        mullion.position,
      )) {
        final frameWidth = _frameProfileWidthAt(
          mullion.isHorizontal,
          mullion.position,
        );
        final center = mullion.isHorizontal
            ? mullion.rect.center.dy
            : mullion.rect.center.dx;
        final frame = mullion.isHorizontal
            ? Rect.fromLTRB(
                mullion.rect.left,
                center - frameWidth / 2,
                mullion.rect.right,
                center + frameWidth / 2,
              )
            : Rect.fromLTRB(
                center - frameWidth / 2,
                mullion.rect.top,
                center + frameWidth / 2,
                mullion.rect.bottom,
              );
        _drawGroovedMullionProfile(
          canvas,
          frame,
          isHorizontal: mullion.isHorizontal,
          fill: paint,
          border: border,
          cavityOnPositiveSide: model.isGroovedMullionCavityOnPositiveSide(
            mullion.isHorizontal,
            mullion.position,
          ),
        );
        return;
      }

      if (!model.isDoubleFrameMullionAt(
        mullion.isHorizontal,
        mullion.position,
      )) {
        canvas.drawRect(mullion.rect, paint);
        canvas.drawRect(mullion.rect, border);
        return;
      }

      // Cadre double: two frame profiles coupled together back-to-back.
      // Draws both frame bodies with realistic parclose cavities (تجويف الباركلوز)
      // facing the adjoining openings on both outer sides, plus a central joint seam line.
      final frameWidth = _frameProfileWidthAt(
        mullion.isHorizontal,
        mullion.position,
      );
      final center = mullion.isHorizontal
          ? mullion.rect.center.dy
          : mullion.rect.center.dx;
      final first = mullion.isHorizontal
          ? Rect.fromLTRB(
              mullion.rect.left,
              center - frameWidth,
              mullion.rect.right,
              center,
            )
          : Rect.fromLTRB(
              center - frameWidth,
              mullion.rect.top,
              center,
              mullion.rect.bottom,
            );
      final second = mullion.isHorizontal
          ? Rect.fromLTRB(
              mullion.rect.left,
              center,
              mullion.rect.right,
              center + frameWidth,
            )
          : Rect.fromLTRB(
              center,
              mullion.rect.top,
              center + frameWidth,
              mullion.rect.bottom,
            );

      _drawGroovedMullionProfile(
        canvas,
        first,
        isHorizontal: mullion.isHorizontal,
        fill: paint,
        border: border,
        cavityOnPositiveSide: false,
      );
      _drawGroovedMullionProfile(
        canvas,
        second,
        isHorizontal: mullion.isHorizontal,
        fill: paint,
        border: border,
        cavityOnPositiveSide: true,
      );

      final hasCacheRainure =
          model.getConfiguredSectionForRole('cache_rainure') != null;
      final separatorPaint = Paint()
        ..color = hasCacheRainure
            ? Colors.black.withValues(alpha: 0.85)
            : border.color.withValues(alpha: 0.75)
        ..style = PaintingStyle.stroke
        ..strokeWidth = hasCacheRainure ? 1.8 : 0.9;
      if (mullion.isHorizontal) {
        canvas.drawLine(
          Offset(mullion.rect.left, center),
          Offset(mullion.rect.right, center),
          separatorPaint,
        );
      } else {
        canvas.drawLine(
          Offset(center, mullion.rect.top),
          Offset(center, mullion.rect.bottom),
          separatorPaint,
        );
      }
    }

    // Internal divisions stop at the inner face of their enclosing frame.
    // The old half-profile extension crossed the mitred outer frame and
    // left vertical lines and triangular fragments on its lower rail.
    final openings = Path();
    for (final frame in physicalFrames) {
      final frameWidth = model.frameVisibleWidthForRect(frame, fallback: t);
      final bottom = model.hasBottomFrameForRect(frame)
          ? frame.bottom - frameWidth
          : frame.bottom;
      final opening = Rect.fromLTRB(
        frame.left + frameWidth,
        frame.top + frameWidth,
        frame.right - frameWidth,
        bottom,
      );
      if (!opening.isEmpty) openings.addRect(opening);
    }
    canvas.save();
    canvas.clipPath(openings);
    for (final mullion in mullions.where((m) => !m.isPrimary)) {
      drawMullion(mullion);
    }
    for (final mullion in mullions.where((m) => m.isPrimary)) {
      drawMullion(mullion);
    }
    canvas.restore();

    if (model.selection.type == SelectionType.mullion) {
      bool isH = model.selection.isHorizontalMullion!;
      double pos = model.selection.mullionPosition!;
      double start = model.selection.mullionStart ?? 0.0;
      double end = model.selection.mullionEnd ?? (isH ? w : h);
      final highlightPaint = Paint()
        ..color = Colors.green.shade600.withValues(alpha: 0.5)
        ..style = PaintingStyle.fill;
      final selectionThickness = model.isDoubleFrameMullionAt(isH, pos)
          ? _frameProfileWidthAt(isH, pos) * 2
          : model.isGroovedFrameMullionAt(isH, pos)
          ? _frameProfileWidthAt(isH, pos)
          : mullionT;
      if (isH) {
        canvas.drawRect(
          Rect.fromLTRB(
            start,
            pos - selectionThickness / 2,
            end,
            pos + selectionThickness / 2,
          ),
          highlightPaint,
        );
      } else {
        canvas.drawRect(
          Rect.fromLTRB(
            pos - selectionThickness / 2,
            start,
            pos + selectionThickness / 2,
            end,
          ),
          highlightPaint,
        );
      }
    }
  }

  double _frameProfileWidthAt(bool isHorizontal, double position) {
    final section = model.effectiveMullionSectionAt(isHorizontal, position);
    for (final field in const ['visible_width', 'thickness']) {
      final value = section?[field];
      final width = value is num
          ? value.toDouble()
          : double.tryParse(value?.toString() ?? '');
      if (width != null && width > 0) return width;
    }
    return model.profileThickness;
  }

  void _drawGroovedMullionProfile(
    Canvas canvas,
    Rect rect, {
    required bool isHorizontal,
    required Paint fill,
    required Paint border,
    required bool cavityOnPositiveSide,
  }) {
    if (rect.isEmpty) return;

    canvas.drawRect(rect, fill);
    canvas.drawRect(rect, border);

    final profileWidth = isHorizontal ? rect.height : rect.width;
    if (profileWidth <= 4.0) return;

    final grooveWidth = math.min(8.0, profileWidth * 0.25);
    final highlightInset = math.min(4.0, profileWidth * 0.12);
    final groovePaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.08)
      ..style = PaintingStyle.fill;
    final shadowLine = Paint()
      ..color = border.color.withValues(alpha: 0.75)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    final highlightLine = Paint()
      ..color = Colors.white.withValues(alpha: 0.35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;

    if (isHorizontal) {
      final groove = cavityOnPositiveSide
          ? Rect.fromLTRB(
              rect.left,
              rect.bottom - grooveWidth,
              rect.right,
              rect.bottom,
            )
          : Rect.fromLTRB(
              rect.left,
              rect.top,
              rect.right,
              rect.top + grooveWidth,
            );
      final shadowY = cavityOnPositiveSide
          ? rect.bottom - grooveWidth
          : rect.top + grooveWidth;
      final highlightY = cavityOnPositiveSide
          ? shadowY - highlightInset
          : shadowY + highlightInset;
      canvas.drawRect(groove, groovePaint);
      canvas.drawLine(
        Offset(rect.left, shadowY),
        Offset(rect.right, shadowY),
        shadowLine,
      );
      if (highlightY > rect.top && highlightY < rect.bottom) {
        canvas.drawLine(
          Offset(rect.left, highlightY),
          Offset(rect.right, highlightY),
          highlightLine,
        );
      }
    } else {
      final groove = cavityOnPositiveSide
          ? Rect.fromLTRB(
              rect.right - grooveWidth,
              rect.top,
              rect.right,
              rect.bottom,
            )
          : Rect.fromLTRB(
              rect.left,
              rect.top,
              rect.left + grooveWidth,
              rect.bottom,
            );
      final shadowX = cavityOnPositiveSide
          ? rect.right - grooveWidth
          : rect.left + grooveWidth;
      final highlightX = cavityOnPositiveSide
          ? shadowX - highlightInset
          : shadowX + highlightInset;
      canvas.drawRect(groove, groovePaint);
      canvas.drawLine(
        Offset(shadowX, rect.top),
        Offset(shadowX, rect.bottom),
        shadowLine,
      );
      if (highlightX > rect.left && highlightX < rect.right) {
        canvas.drawLine(
          Offset(highlightX, rect.top),
          Offset(highlightX, rect.bottom),
          highlightLine,
        );
      }
    }
  }

  void _drawInnerDimensions(Canvas canvas, WindowZone zone) {
    final r = zone.boundary;
    if (r.width < 150 || r.height < 150) return;
    final isSash =
        zone.content == ZoneContent.singleSash ||
        zone.content == ZoneContent.doubleSash ||
        zone.content == ZoneContent.slidingSash;
    // Every sash cutting measurement belongs to the sash profile itself,
    // never to the glass area.  The width sits in the top sash bar and the
    // height sits in an outer vertical sash bar, just like frame and side-
    // cover dimensions.  This keeps the glazing area visually clean.
    if (!isSash) return;
    final sashThickness =
        zone.sashThickness ?? model.getSectionThickness('sash', fallback: 45.0);
    final isSlidingZone = zone.content == ZoneContent.slidingSash;
    final sashOverride = isSlidingZone
        ? (model.slidingSashOverride ?? model.sashOverride)
        : model.sashOverride;
    final overriddenSashCode = (sashOverride?['code'] ?? '').toString().trim();
    final sashCode = overriddenSashCode.isNotEmpty
        ? overriddenSashCode
        : (model.getSectionByType('sash')?.code ?? '').trim();
    // Use clear blue labels so cutting sizes remain readable without hiding
    // the drawing. The section code travels with the size, never as a long
    // profile name.
    final sashTextStyle = TextStyle(
      color: const Color(0xFF1565C0),
      fontSize: math.max(15.0, math.min(30.0, sashThickness * 0.62)),
      fontWeight: FontWeight.w600,
    );

    String dimensionLabel(double value) {
      final rounded = (value * 10).round() / 10;
      final size = (rounded - rounded.round()).abs() < 0.001
          ? rounded.round().toString()
          : rounded.toStringAsFixed(1);
      return sashCode.isEmpty ? size : '$size ($sashCode)';
    }

    void paintWidthInSashProfile(
      TextPainter text,
      Rect sashRect, {
      bool avoidCenter = false,
    }) {
      final profile = Rect.fromLTRB(
        sashRect.left + 4,
        sashRect.top + 2,
        sashRect.right - 4,
        sashRect.top + sashThickness - 2,
      );
      if (profile.width < text.width + 8 || profile.height < text.height + 4) {
        return;
      }
      double x = profile.center.dx - text.width / 2;
      if (avoidCenter) {
        final sideWidth = (profile.width - text.width - 12) / 2;
        if (sideWidth > 0) {
          x = profile.left + math.max(6.0, sideWidth * 0.5);
        }
      }
      text.paint(canvas, Offset(x, profile.center.dy - text.height / 2));
    }

    void paintHeightInSashProfile(
      TextPainter text,
      Rect sashRect, {
      required bool onRight,
    }) {
      final profile = Rect.fromLTRB(
        onRight ? sashRect.right - sashThickness + 2 : sashRect.left + 2,
        sashRect.top + sashThickness + 4,
        onRight ? sashRect.right - 2 : sashRect.left + sashThickness - 2,
        sashRect.bottom - sashThickness - 4,
      );
      if (profile.height < text.width + 8 || profile.width < text.height + 4) {
        return;
      }
      // Handles are normally centred vertically (and sliding systems may
      // draw one on each outer sash stile).  Reserve the whole middle band
      // for hardware and keep the complete cut label in the upper part.
      final halfLabelLength = text.width / 2;
      final minimumY = profile.top + halfLabelLength + 4;
      final maximumY = profile.top + (profile.height * 0.44) - halfLabelLength;
      if (minimumY > maximumY) return;
      final labelY = (profile.top + profile.height * 0.27)
          .clamp(minimumY, maximumY)
          .toDouble();
      canvas.save();
      canvas.translate(profile.center.dx, labelY);
      canvas.rotate(-math.pi / 2);
      text.paint(canvas, Offset(-text.width / 2, -text.height / 2));
      canvas.restore();
    }

    // Calculate real cutting sizes if there's a sash in this zone
    double displayWidth = r.width;
    double displayHeight = r.height;
    double displayWLeft = 0.0;
    double displayWRight = 0.0;

    // The selected thick sash must not change cutting dimensions. Read the
    // configured series overlap, add it to both sides of the whole clear
    // opening, then distribute that total width between the leaves.
    final double overlap = model.openingSashOverlap;
    // Sash profiles are cut without an added welding allowance. PVC loses
    // 5 mm only after welding, so the dimension shown beside the glazed
    // opening represents the finished frame; aluminium keeps its cut size.
    final finishedSashWeldLoss = model.isPVC ? 5.0 : 0.0;

    if (zone.content == ZoneContent.singleSash) {
      displayWidth = r.width + overlap * 2 - finishedSashWeldLoss;
      displayHeight = r.height + overlap * 2 - finishedSashWeldLoss;
    } else if (zone.content == ZoneContent.doubleSash) {
      final isInternal = overrideIsInternalView ?? model.isInternalView;
      final double effectiveRatio = isInternal
          ? zone.doubleSashRatio
          : (1.0 - zone.doubleSashRatio);
      final totalCutWidth = r.width + overlap * 2;
      displayWLeft = totalCutWidth * effectiveRatio - finishedSashWeldLoss;
      displayWRight =
          totalCutWidth * (1.0 - effectiveRatio) - finishedSashWeldLoss;
      displayHeight = r.height + overlap * 2 - finishedSashWeldLoss;
    } else if (zone.content == ZoneContent.slidingSash) {
      final slidingSashOverride =
          model.slidingSashOverride ?? model.sashOverride;
      double slidingOverlap = slidingSashOverride != null
          ? (slidingSashOverride['sash_overlap'] ?? 8.0).toDouble()
          : 8.0;
      double wForCalc = r.width;
      double hForCalc = r.height;

      bool isNested = model.isSlidingZoneNestedInSingleFrame(zone);
      if (isNested) {
        double innerFrameT = 45.0;
        final slidingFrame = model.getSlidingBaseFrameSection();
        if (slidingFrame != null) {
          innerFrameT = slidingFrame.visibleWidth > 0
              ? slidingFrame.visibleWidth
              : (slidingFrame.thickness > 0
                    ? slidingFrame.thickness
                    : innerFrameT);
        } else {
          final series = model.activeSlidingSeries ?? model.activeSeries;
          if (series != null) {
            var slidingFrames = series.sections.where((s) {
              final name = s.name.toLowerCase();
              final type = s.type.toLowerCase();
              return (name.contains('coulissant') ||
                      name.contains('منزلق') ||
                      name.contains('sliding') ||
                      type.contains('coulissant') ||
                      type.contains('sliding')) &&
                  (type.contains('frame') ||
                      type.contains('cadre') ||
                      type.contains('إطار'));
            }).toList();
            if (slidingFrames.isNotEmpty) {
              innerFrameT = slidingFrames.first.visibleWidth > 0
                  ? slidingFrames.first.visibleWidth
                  : (slidingFrames.first.thickness > 0
                        ? slidingFrames.first.thickness
                        : 45.0);
            }
          }
        }
        wForCalc =
            r.width -
            model.slidingRebateDeduction(zone, horizontal: true) -
            (innerFrameT * 2.0);
        hForCalc =
            r.height -
            model.slidingRebateDeduction(zone, horizontal: false) -
            (innerFrameT * 2.0);
      }
      wForCalc = math.max(0.0, wForCalc);
      hForCalc = math.max(0.0, hForCalc);

      int sashes = zone.slidingSashesCount > 0 ? zone.slidingSashesCount : 2;
      final configuredSashDeduction = model.slidingSashWidthDeduction(sashes);
      double cuttingW = configuredSashDeduction != 0
          ? (wForCalc - configuredSashDeduction) / sashes
          : (wForCalc + ((sashes - 1) * 26.0)) / sashes;
      if (configuredSashDeduction == 0 && model.isPVC) {
        cuttingW = (wForCalc + ((sashes - 1) * slidingOverlap)) / sashes;
      }
      final configuredHeightDeduction = model.slidingSashHeightDeduction();
      final usableWindowHeight = math.max(
        0.0,
        model.height -
            (model.hasShutter && !model.isCaissonTunnel
                ? model.shutterBoxHeight
                : 0.0),
      );
      double cuttingH = configuredHeightDeduction != 0
          ? usableWindowHeight - configuredHeightDeduction
          : hForCalc + slidingOverlap * 2;
      final String seriesName =
          model.activeSlidingSeries?.name.toLowerCase() ??
          model.activeSeries?.name.toLowerCase() ??
          '';
      final bool isTPI67000 =
          seriesName.contains('67000') || seriesName.contains('tpi');
      bool hasThreePiece =
          (model.activeSlidingSeries?.hasThreePieceSash ?? false) || isTPI67000;
      if (!hasThreePiece && configuredHeightDeduction == 0 && model.isPVC) {
        cuttingH = hForCalc + slidingOverlap;
      }

      displayWidth = cuttingW;
      displayHeight = cuttingH;
    }

    if (zone.content == ZoneContent.doubleSash) {
      final isInternal = overrideIsInternalView ?? model.isInternalView;
      final double effectiveRatio = isInternal
          ? zone.doubleSashRatio
          : (1.0 - zone.doubleSashRatio);

      final leftText = TextPainter(
        text: TextSpan(
          text: dimensionLabel(displayWLeft),
          style: sashTextStyle,
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      final rightText = TextPainter(
        text: TextSpan(
          text: dimensionLabel(displayWRight),
          style: sashTextStyle,
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      final splitX = r.left + r.width * effectiveRatio;
      final leftSash = Rect.fromLTRB(r.left, r.top, splitX - 2, r.bottom);
      final rightSash = Rect.fromLTRB(splitX + 2, r.top, r.right, r.bottom);
      paintWidthInSashProfile(leftText, leftSash);
      paintWidthInSashProfile(rightText, rightSash);
    } else {
      final widthText = TextPainter(
        text: TextSpan(
          text: dimensionLabel(displayWidth),
          style: sashTextStyle,
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      paintWidthInSashProfile(
        widthText,
        r,
        avoidCenter: zone.content == ZoneContent.slidingSash,
      );
    }
    // The two leaves share their height, but each gets its own label inside
    // its outer vertical profile.  A single sash uses its left profile.
    {
      final heightText = TextPainter(
        text: TextSpan(
          text: dimensionLabel(displayHeight),
          style: sashTextStyle,
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      if (zone.content == ZoneContent.doubleSash) {
        final isInternal = overrideIsInternalView ?? model.isInternalView;
        final effectiveRatio = isInternal
            ? zone.doubleSashRatio
            : (1.0 - zone.doubleSashRatio);
        final splitX = r.left + r.width * effectiveRatio;
        final leftSash = Rect.fromLTRB(r.left, r.top, splitX - 2, r.bottom);
        final rightSash = Rect.fromLTRB(splitX + 2, r.top, r.right, r.bottom);
        paintHeightInSashProfile(heightText, leftSash, onRight: false);
        paintHeightInSashProfile(heightText, rightSash, onRight: true);
      } else {
        paintHeightInSashProfile(heightText, r, onRight: false);
      }
    }
  }

  void _drawZoneBackground(Canvas canvas, WindowZone zone, double h, double t) {
    final r = _getEffectiveZoneRect(zone.boundary, h, t);
    final double topOffset = _topOffset;
    final bool isTopBound = _isTopZone(zone);
    final path = _buildGlassLayerPath(r, t, topOffset, isTopBound);
    // Exposed rebates belong to the profile, not a white backing sheet.
    // Glass/panel content is painted over this layer afterwards.
    final backingPaint = _buildPaint(r);
    canvas.drawPath(path, backingPaint);
  }

  void _drawZoneContent(Canvas canvas, WindowZone zone, double h, double t) {
    final previousBottom = _localBottomFrame;
    for (final frame in model.getFrameRects()) {
      if (frame.contains(zone.boundary.center)) {
        _localBottomFrame = model.hasBottomFrameForRect(frame);
        break;
      }
    }
    try {
      _drawZoneContentForFrame(canvas, zone, h, t);
    } finally {
      _localBottomFrame = previousBottom;
    }
  }

  void _drawZoneContentForFrame(
    Canvas canvas,
    WindowZone zone,
    double h,
    double t,
  ) {
    final r = _getEffectiveZoneRect(zone.boundary, h, t);
    final double topOffset = _topOffset;
    final bool isTopBound = _isTopZone(zone);
    switch (zone.content) {
      case ZoneContent.empty:
      case ZoneContent.fixedGlass:
        if (zone.content == ZoneContent.empty) {
          break;
        }
        final hasBottomPlinthe =
            model.hasFramePlintheBottom && zone.hasSashPlintheBottom;
        final contentRect = hasBottomPlinthe ? _rectWithoutBottomPlinthe(r) : r;
        final cellSpec = zone.getGlassForCell('main_cell_0_0');

        final bool isDecorPanel =
            (cellSpec.structure == GlassStructure.closed &&
            ((overrideIsInternalView ?? model.isInternalView)
                ? cellSpec.finishInner == GlassFinish.paneauSandwitchDecore
                : cellSpec.finishOuter == GlassFinish.paneauSandwitchDecore));
        if (isDecorPanel) {
          _drawPanelTexture(
            canvas,
            contentRect,
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
            contentRect,
            model.frameColor,
            zone: zone,
            spec: cellSpec,
            t: t,
            topOffset: topOffset,
            isTopBound: isTopBound,
          );
        } else if (zone.content == ZoneContent.fixedGlass) {
          _drawFixedGlass(
            canvas,
            contentRect,
            cellSpec,
            t,
            topOffset,
            isTopBound,
          );
        }
        if (!isDecorPanel) {
          _drawRealisticParclose(
            canvas,
            contentRect,
            model.frameColor,
            t: t,
            topOffset: topOffset,
            isTopBound: isTopBound,
          );
        }
        if (hasBottomPlinthe) {
          _drawBottomPlinthe(canvas, r);
        }
        break;

      case ZoneContent.singleSash:
        _drawSingleSash(canvas, r, zone);
        break;
      case ZoneContent.doubleSash:
        final sep = 4.0;
        final isInternal = overrideIsInternalView ?? model.isInternalView;
        final double effectiveRatio = isInternal
            ? zone.doubleSashRatio
            : (1.0 - zone.doubleSashRatio);
        final midX = r.left + r.width * effectiveRatio;
        final leftR = Rect.fromLTRB(r.left, r.top, midX - sep / 2, r.bottom);
        final rightR = Rect.fromLTRB(midX + sep / 2, r.top, r.right, r.bottom);
        final drawBothHandles = zone.doubleSashHasTwoHandles;
        var isLeftActive = zone.openDirection == OpenDirection.left;
        var isRightActive = zone.openDirection == OpenDirection.right;
        // Old saved drawings can have no direction.  Keep the historical
        // default of one handle on the right leaf in that case.
        if (!isLeftActive && !isRightActive) {
          isRightActive = true;
        }
        if (isInternal) {
          _renderSash(
            canvas,
            leftR,
            zone.copyWith(openDirection: OpenDirection.right),
            leftR,
            // By default, draw only the selected/active leaf.  A second
            // handle is an explicit customer option.
            forceHandle: drawBothHandles || isLeftActive,
            isRightSash: false,
          );
          _renderSash(
            canvas,
            rightR,
            zone.copyWith(openDirection: OpenDirection.left),
            rightR,
            forceHandle: drawBothHandles || isRightActive,
            isRightSash: true,
          );
        } else {
          // Mirror horizontally for external view: L sash drawn on rightR, R sash drawn on leftR
          _renderSash(
            canvas,
            leftR,
            zone.copyWith(openDirection: OpenDirection.left),
            leftR,
            forceHandle: drawBothHandles || isRightActive,
            isRightSash: true,
          );
          _renderSash(
            canvas,
            rightR,
            zone.copyWith(openDirection: OpenDirection.right),
            rightR,
            forceHandle: drawBothHandles || isLeftActive,
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

  Rect _rectWithoutBottomPlinthe(Rect rect) {
    final plintheHeight = model.plintheHeight;
    if (plintheHeight <= 0 || rect.height <= plintheHeight + 2.0) {
      return rect;
    }
    return Rect.fromLTRB(
      rect.left,
      rect.top,
      rect.right,
      rect.bottom - plintheHeight,
    );
  }

  void _drawBottomPlinthe(Canvas canvas, Rect zoneRect) {
    final plintheHeight = model.plintheHeight;
    if (plintheHeight <= 0 || zoneRect.height <= plintheHeight) return;

    final plintheRect = Rect.fromLTRB(
      zoneRect.left,
      zoneRect.bottom - plintheHeight,
      zoneRect.right,
      zoneRect.bottom,
    );
    canvas.drawRect(plintheRect, _buildPaint(plintheRect, gradientColors: _fc));
    canvas.drawRect(
      plintheRect,
      Paint()
        ..color = _fb
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0,
    );
    canvas.drawLine(
      plintheRect.topLeft,
      plintheRect.topRight,
      Paint()
        ..color = _fb.withValues(alpha: 0.85)
        ..strokeWidth = 1.0,
    );
  }

  double getInnerBottomY(double x, double t) {
    if (model.bottomSlantLeftY == 0 && model.bottomSlantRightY == 0) {
      return model.height - (_hasEffectiveBottomFrame ? t : 0.0);
    }
    double factor = 0.0;
    if (model.width > 2 * t) {
      factor = ((x - t) / (model.width - 2 * t)).clamp(0.0, 1.0);
    }
    double bottomOffset = _hasEffectiveBottomFrame ? t : 0.0;
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
    bool isBottomBound =
        !isInsideSash &&
        (r.bottom - (model.height - (_hasEffectiveBottomFrame ? t : 0.0)))
                .abs() <
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
          ? getSashTopY((r.left + r.right) / 2, sashTop, t, topOffset, true) +
                topW
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
    final String? pColor = _effectivePanneauColor(
      effectiveSpec ?? model.selectedZone?.glass,
    );
    final bool isPanneauWood = pColor != null && _isWoodColor({'name': pColor});
    if (isPanneauWood && TextureCache.woodTexture != null) {
      final woodColors = getEffectiveGradientColors(FrameColor.brown, {
        'name': pColor,
      });
      _applyWoodShader(
        fillPaint,
        r,
        gradientColors: woodColors,
        dbColor: {'name': pColor},
      );
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

    if (activeFinish == GlassFinish.bardage ||
        isBardagePanelSubtype(effectiveSpec?.panneauSubtype)) {
      // 🟢 رسم البارداج كشرائح أفقية أو عمودية بعرضها الحقيقي من قاعدة البيانات
      final String? panneauSub = effectiveSpec?.panneauSubtype;
      final bool isVertical = effectiveSpec?.isVerticalBardage ?? false;

      double realSlatHeight = 100.0; // قيمة افتراضية للبارداج
      final bardageOverride = model.getBardageProfileOverride();
      if (bardageOverride != null) {
        final dbWidth = bardageOverride['visible_width'] as num?;
        if (dbWidth != null && dbWidth > 0) {
          realSlatHeight = dbWidth.toDouble();
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
                (g['subtype'] ?? '').toString().toLowerCase().contains(
                  'bardage',
                ),
            orElse: () => <String, dynamic>{},
          );
        }
        if (dbMatch.isNotEmpty) {
          final dbWidth =
              (dbMatch['visible_width'] ?? dbMatch['thickness']) as num?;
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
          canvas.drawLine(
            Offset(x - 1.5, r.top),
            Offset(x - 1.5, r.bottom),
            slatHighlight,
          );
          canvas.drawLine(Offset(x, r.top), Offset(x, r.bottom), slatDivider);
          canvas.drawLine(
            Offset(x + 1.0, r.top),
            Offset(x + 1.0, r.bottom),
            slatShadow,
          );
          x += realSlatHeight;
        }
      } else {
        // 🟢 رسم شرائح أفقية
        double y = r.top + realSlatHeight;
        while (y <= r.bottom) {
          canvas.drawLine(
            Offset(r.left, y - 1.5),
            Offset(r.right, y - 1.5),
            slatHighlight,
          );
          canvas.drawLine(Offset(r.left, y), Offset(r.right, y), slatDivider);
          canvas.drawLine(
            Offset(r.left, y + 1.0),
            Offset(r.right, y + 1.0),
            slatShadow,
          );
          y += realSlatHeight;
        }
      }
    } else if (activeFinish == GlassFinish.paneauSandwitchDecore) {
      final designCode = DecorPanelDesignCatalog.resolveForProduct(
        productId: effectiveSpec?.panneauProductId,
        glassProducts: model.allGlassCache,
      );
      if (designCode != null) {
        DecorPanelDesignPainter.paintDesign(
          canvas,
          r,
          designCode,
          panelColor: _getColorsForLayer(
            GlassStructure.closed,
            effectiveSpec?.colorOuter ?? GlassColor.transparent,
            activeFinish,
            effectiveSpec?.colorP ?? ClosedGlassColor.white,
            pColor,
          ).first,
        );
      } else {
        // Keep the old neutral texture for existing products that have not
        // been linked to one of the lightweight code-drawn motifs yet.
        final linePaint = Paint()
          ..color = _fb.withValues(alpha: 0.3)
          ..strokeWidth = 1.5;
        for (double x = r.left + 30; x < r.right; x += 30) {
          canvas.drawLine(Offset(x, r.top), Offset(x, r.bottom), linePaint);
        }
        for (double y = r.top + 30; y < r.bottom; y += 30) {
          canvas.drawLine(Offset(r.left, y), Offset(r.right, y), linePaint);
        }
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

  /// Paints hinges after the content clip has been removed.  A hinge is placed
  /// in the narrow reveal between the sash and its frame, which is partly
  /// outside the inner glass-opening clip.  Keeping this pass separate makes
  /// it visible on every normal sash as well as on coupled frames.
  void _drawMainZoneHinges(Canvas canvas, double h, double t) {
    if (!_shouldDrawWindowHardware) return;
    final isInternal = overrideIsInternalView ?? model.isInternalView;
    final topOffset = _topOffset;

    void drawForSash(
      Rect sashRect,
      WindowZone sashZone,
      bool isHandleSash,
      bool isTopBound,
    ) {
      final direction = sashZone.openDirection;
      if (direction == null) return;
      final hingesOnRight = isInternal
          ? direction == OpenDirection.left
          : direction == OpenDirection.right;
      final hingesOnLeft = isInternal
          ? direction == OpenDirection.right
          : direction == OpenDirection.left;
      _drawHinges(
        canvas,
        sashRect,
        hingesOnRight,
        hingesOnLeft,
        direction == OpenDirection.bottom,
        direction == OpenDirection.top,
        sashZone,
        isHandleSash,
        t: t,
        topOffset: topOffset,
        isTopBound: isTopBound,
      );
    }

    for (final zone in model.zones) {
      if (zone.content != ZoneContent.singleSash &&
          zone.content != ZoneContent.doubleSash) {
        continue;
      }
      final r = _getEffectiveZoneRect(zone.boundary, h, t);
      final isTopBound = _isTopZone(zone);

      if (zone.content == ZoneContent.singleSash) {
        drawForSash(r, zone, true, isTopBound);
        continue;
      }

      final sep = 4.0;
      final effectiveRatio = isInternal
          ? zone.doubleSashRatio
          : (1.0 - zone.doubleSashRatio);
      final splitX = r.left + r.width * effectiveRatio;
      final leftSash = Rect.fromLTRB(r.left, r.top, splitX - sep / 2, r.bottom);
      final rightSash = Rect.fromLTRB(
        splitX + sep / 2,
        r.top,
        r.right,
        r.bottom,
      );
      final drawBothHandles = zone.doubleSashHasTwoHandles;
      var isLeftActive = zone.openDirection == OpenDirection.left;
      var isRightActive = zone.openDirection == OpenDirection.right;
      if (!isLeftActive && !isRightActive) isRightActive = true;

      if (isInternal) {
        drawForSash(
          leftSash,
          zone.copyWith(openDirection: OpenDirection.right),
          drawBothHandles || isLeftActive,
          isTopBound,
        );
        drawForSash(
          rightSash,
          zone.copyWith(openDirection: OpenDirection.left),
          drawBothHandles || isRightActive,
          isTopBound,
        );
      } else {
        drawForSash(
          leftSash,
          zone.copyWith(openDirection: OpenDirection.left),
          drawBothHandles || isRightActive,
          isTopBound,
        );
        drawForSash(
          rightSash,
          zone.copyWith(openDirection: OpenDirection.right),
          drawBothHandles || isLeftActive,
          isTopBound,
        );
      }
    }
  }

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

    bool isNested = model.isSlidingZoneNestedInSingleFrame(zone);
    if (isNested) {
      double innerFrameT = _slidingFrameWidth(45.0);
      if (model.getSlidingBaseFrameSection() == null) {
        final series = model.activeSlidingSeries;
        if (series != null) {
          var slidingFrames = series.sections.where((s) {
            final name = s.name.toLowerCase();
            final type = s.type.toLowerCase();
            return (name.contains('coulissant') ||
                    name.contains('منزلق') ||
                    name.contains('sliding') ||
                    type.contains('coulissant') ||
                    type.contains('sliding')) &&
                (type.contains('frame') ||
                    type.contains('cadre') ||
                    type.contains('إطار'));
          }).toList();
          if (slidingFrames.isNotEmpty) {
            innerFrameT = slidingFrames.first.visibleWidth > 0
                ? slidingFrames.first.visibleWidth
                : (slidingFrames.first.thickness > 0
                      ? slidingFrames.first.thickness
                      : 45.0);
          } else {
            var anyFrames = series.sections.where((s) {
              final type = s.type.toLowerCase();
              return type.contains('frame') ||
                  type.contains('cadre') ||
                  type.contains('إطار');
            }).toList();
            if (anyFrames.isNotEmpty) {
              innerFrameT = anyFrames.first.visibleWidth > 0
                  ? anyFrames.first.visibleWidth
                  : (anyFrames.first.thickness > 0
                        ? anyFrames.first.thickness
                        : 45.0);
            }
          }
        }
      }

      // Draw the nested inner frame
      _drawInternalSlidingSideCover(canvas, r);
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
    final double traverseT = _getSlidingSectionWidth(
      'traverse',
      'traverse',
      45.0,
    );
    final double chicaneT = _getSlidingSectionWidth(
      'chicane',
      'centrale',
      45.0,
    );
    final double normalLateralT = _getSlidingSectionWidth(
      'lateral',
      'poignee',
      45.0,
      reinforced: false,
    );
    final double reinforcedLateralT = _getSlidingSectionWidth(
      'lateral',
      'poignee',
      normalLateralT,
      reinforced: true,
    );

    final double slimProfileW =
        (model.selectedSlimMontantProfile != null &&
            (model.selectedSlimMontantProfile!['visible_width'] ?? 0) > 0)
        ? (model.selectedSlimMontantProfile!['visible_width'] as num).toDouble()
        : 18.0;

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

    // The ordinary two-track arrangement paints the outer leaves on top of
    // the middle leaves.  Face-to-Face deliberately reverses that order so
    // the two middle leaves are the visible meeting pair.  Keep the
    // historical alternating order for two leaves, where there is no
    // middle/outer distinction.
    final drawTrackOrder =
        (count >= 3 && zone.slidingTrackCount == 2 && zone.slidingFaceToFace)
        ? const <int>[0, 1]
        : (count >= 3 ? const <int>[1, 0] : const <int>[0, 1]);
    for (final tg in drawTrackOrder) {
      for (int i = 0; i < count; i++) {
        if (tracks[i] != tg) continue;

        double left = r.left + i * (sashWidth - chicaneT);
        Rect sashRect = Rect.fromLTRB(left, r.top, left + sashWidth, r.bottom);

        // Calculate left and right profile widths for this specific sash
        final leftLateralReinforced =
            zone.slidingMontantReinforced['lateral_0'] ??
            zone.slidingMontantReinforced['lateral_left'] ??
            false;
        final rightLateralReinforced =
            zone.slidingMontantReinforced['lateral_1'] ??
            zone.slidingMontantReinforced['lateral_right'] ??
            false;
        final bool isLeftSlim =
            (i > 0) &&
            (zone.slidingMontantSlim['central_${(i - 1) * 2 + 1}'] ?? false);
        final bool isRightSlim =
            (i < count - 1) &&
            (zone.slidingMontantSlim['central_${i * 2}'] ?? false);

        final double leftProfileW = (i == 0)
            ? (leftLateralReinforced ? reinforcedLateralT : normalLateralT)
            : (isLeftSlim ? slimProfileW : chicaneT);
        final double rightProfileW = (i == count - 1)
            ? (rightLateralReinforced ? reinforcedLateralT : normalLateralT)
            : (isRightSlim ? slimProfileW : chicaneT);
        final double topProfileW = traverseT;
        final double bottomProfileW = zone.hasSashPlintheBottom
            ? model.plintheHeight
            : traverseT;

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
            squareLeft: isLeftSlim,
            squareRight: isRightSlim,
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

        final bool drawHandle = (i == 0 || i == count - 1);
        if (drawHandle && _shouldDrawWindowHardware) {
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

    // Face-to-Face is a catalogue role, not a name-based fallback.  It is
    // drawn only when the active sliding series has assigned that role and
    // the user enabled it on this zone.  For four leaves the central meeting
    // is made from two face-to-face profiles; for three leaves it is one
    // central profile.
    final faceSection = count >= 3
        ? model.getConfiguredSectionForRole(
            'face_to_face',
            useSlidingSeries: true,
          )
        : null;
    final faceEnabled =
        (count == 4 && zone.slidingTrackCount == 2 && zone.slidingFaceToFace) ||
        (count == 3 && faceSection != null);
    if (faceEnabled && count >= 3) {
      final configuredFaceSection = faceSection;
      if (configuredFaceSection != null) {
        final rawWidth = configuredFaceSection.visibleWidth > 0
            ? configuredFaceSection.visibleWidth
            : configuredFaceSection.thickness;
        final faceWidth = rawWidth > 0 ? rawWidth : 0.0;
        if (faceWidth > 0) {
          final junction = count == 4 ? 1 : (count - 1) ~/ 2;
          final rightEdge =
              r.left + junction * (sashWidth - chicaneT) + sashWidth;
          final centerX = rightEdge - (chicaneT / 2.0);
          final faceCount = count == 4 ? 2 : 1;
          for (var faceIndex = 0; faceIndex < faceCount; faceIndex++) {
            final offset = faceCount == 2
                ? (faceIndex == 0 ? -faceWidth / 2.0 : faceWidth / 2.0)
                : 0.0;
            final faceRect = Rect.fromLTRB(
              centerX + offset - faceWidth / 2.0,
              r.top,
              centerX + offset + faceWidth / 2.0,
              r.bottom,
            );
            canvas.drawRect(
              faceRect,
              _buildPaint(faceRect, gradientColors: _fc),
            );
            canvas.drawRect(
              faceRect,
              Paint()
                ..color = _fb
                ..style = PaintingStyle.stroke
                ..strokeWidth = 1.0,
            );
          }
        }
      }
    }

    // A central handle is optional and belongs to the meeting of the middle
    // pair only.  Draw it after all leaves and the Face-to-Face profile so it
    // cannot disappear under the other middle sash.
    if (zone.slidingCentralHandle &&
        zone.slidingTrackCount == 2 &&
        count == 4 &&
        _shouldDrawWindowHardware) {
      final centralLeft = r.left + (sashWidth - chicaneT);
      final centralSash = Rect.fromLTRB(
        centralLeft,
        r.top,
        centralLeft + sashWidth,
        r.bottom,
      );
      _drawWindowDrawHandle(
        canvas,
        centralSash,
        OpenDirection.right,
        zone.handlePositionRatio ?? 0.5,
        t: t,
        topOffset: topOffset,
        isTopBound: isTopBound,
        zone: zone,
      );
    }
    if (zone.slidingSecondCentralHandle &&
        zone.slidingTrackCount == 2 &&
        count == 4 &&
        _shouldDrawWindowHardware) {
      // The mirrored middle handle is intentionally only a visual handle.
      // Its BOM row is added separately without any lock hardware.
      final centralRightLeft = r.left + 2 * (sashWidth - chicaneT);
      final centralRightSash = Rect.fromLTRB(
        centralRightLeft,
        r.top,
        centralRightLeft + sashWidth,
        r.bottom,
      );
      _drawWindowDrawHandle(
        canvas,
        centralRightSash,
        OpenDirection.left,
        zone.handlePositionRatio ?? 0.5,
        t: t,
        topOffset: topOffset,
        isTopBound: isTopBound,
        zone: zone,
      );
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
          _drawFixedGlass(canvas, glassR, cellSpec, t, topOffset, isTopBound);
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

    final String? primaryAxis = isRightSash
        ? zone.rightPrimaryDivisionAxis
        : zone.primaryDivisionAxis;
    final String effectivePrimary = primaryAxis ?? (innerV > 0 ? 'v' : 'h');
    final List<Rect> primaryDivisionRects = [];
    final List<Rect> secondaryDivisionRects = [];
    final List<Rect> selectedDivisionRects = [];
    final bool selectedThisSide =
        model.selection.type == SelectionType.innerDivision &&
        model.selection.zoneId == zone.id &&
        (model.selection.isRightSashInnerDivision ?? false) == isRightSash;
    final bool selectedIsHorizontal =
        model.selection.isHorizontalInnerDivision ?? false;
    final int selectedDivisionIndex = model.selection.innerDivisionIndex ?? -1;

    void addDivisionRect(
      Rect rect, {
      required bool isHorizontal,
      required int index,
      required bool isPrimary,
    }) {
      if (isPrimary) {
        primaryDivisionRects.add(rect);
      } else {
        secondaryDivisionRects.add(rect);
      }
      if (selectedThisSide &&
          selectedIsHorizontal == isHorizontal &&
          selectedDivisionIndex == index) {
        selectedDivisionRects.add(rect);
      }
    }

    if (effectivePrimary == 'h') {
      // ==========================================
      // Horizontal is Primary (continuous)
      // ==========================================
      if (hPositions.isNotEmpty) {
        for (int h = 0; h < hPositions.length; h++) {
          double y = glassR.top + (glassR.height * hPositions[h]);
          double? runStart;

          for (int c = 0; c < cols; c++) {
            bool isSegmentActive = true;

            if (isSegmentActive) {
              if (runStart == null) {
                double leftRatio = c == 0 ? 0.0 : vPositions[c - 1];
                runStart = glassR.left + (glassR.width * leftRatio);
              }

              bool isLast = c == cols - 1;
              if (isLast) {
                double rightRatio = c == cols - 1 ? 1.0 : vPositions[c];
                double right = glassR.left + (glassR.width * rightRatio);

                double left = runStart;
                if (runStart > glassR.left) left -= dividerT / 2;
                if (right < glassR.right) right += dividerT / 2;

                addDivisionRect(
                  Rect.fromLTRB(
                    left,
                    y - dividerT / 2,
                    right,
                    y + dividerT / 2,
                  ),
                  isHorizontal: true,
                  index: h,
                  isPrimary: true,
                );
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
              topYVal =
                  getSashTopY(x, glassR.top - sashT, t, topOffset, isTopBound) +
                  sashT;
            } else {
              bool hasActiveHAbove = true;
              if (hasActiveHAbove) {
                topYVal += dividerT / 2;
              }
            }

            double bottomYVal = bottom;
            if (r < rows - 1) {
              bool hasActiveHBelow = true;
              if (hasActiveHBelow) {
                bottomYVal -= dividerT / 2;
              }
            }

            addDivisionRect(
              Rect.fromLTRB(
                x - dividerT / 2,
                topYVal,
                x + dividerT / 2,
                bottomYVal,
              ),
              isHorizontal: false,
              index: v,
              isPrimary: false,
            );
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
            bool isSegmentActive = true;

            if (isSegmentActive) {
              if (runStartTop == null) {
                double topRatio = r == 0 ? 0.0 : hPositions[r - 1];
                double top = glassR.top + (glassR.height * topRatio);
                if (r == 0) {
                  runStartTop =
                      getSashTopY(
                        x,
                        glassR.top - sashT,
                        t,
                        topOffset,
                        isTopBound,
                      ) +
                      sashT;
                } else {
                  runStartTop = top;
                }
              }

              bool isLast = r == rows - 1;
              if (isLast) {
                double bottomRatio = r == rows - 1 ? 1.0 : hPositions[r];
                double bottom = glassR.top + (glassR.height * bottomRatio);

                double topYVal = runStartTop;
                double bottomYVal = bottom;

                if (r > 0) topYVal -= dividerT / 2;
                if (r < rows - 1) bottomYVal += dividerT / 2;

                addDivisionRect(
                  Rect.fromLTRB(
                    x - dividerT / 2,
                    topYVal,
                    x + dividerT / 2,
                    bottomYVal,
                  ),
                  isHorizontal: false,
                  index: v,
                  isPrimary: true,
                );
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
              bool hasVLeft = true;
              if (hasVLeft) {
                leftXVal += dividerT / 2;
              }
            }

            double rightXVal = right;
            if (c < cols - 1) {
              bool hasVRight = true;
              if (hasVRight) {
                rightXVal -= dividerT / 2;
              }
            }

            addDivisionRect(
              Rect.fromLTRB(
                leftXVal,
                y - dividerT / 2,
                rightXVal,
                y + dividerT / 2,
              ),
              isHorizontal: true,
              index: h,
              isPrimary: false,
            );
          }
        }
      }
    }

    for (var rect in secondaryDivisionRects) {
      canvas.drawRect(rect, paint);
      canvas.drawRect(rect, border);
    }
    for (var rect in primaryDivisionRects) {
      canvas.drawRect(rect, paint);
      canvas.drawRect(rect, border);
    }

    if (selectedDivisionRects.isNotEmpty) {
      final highlightPaint = Paint()
        ..color = Colors.green.shade600.withValues(alpha: 0.5)
        ..style = PaintingStyle.fill;
      for (final rect in selectedDivisionRects) {
        canvas.drawRect(rect, highlightPaint);
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
      fontSize: 48,
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
                    (model.height - (_hasEffectiveBottomFrame ? t : 0.0)))
                .abs() <
            5.0;
        final double labelY = (_isSlantedOrArched && isBottomBound)
            ? (model.height + 10.0)
            : (cell.rect.bottom - widthText.height - 12.0);
        final wOffset = Offset(
          cell.rect.left + (cellW - widthText.width) / 2,
          labelY,
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
    final glassR = _getSafeGlassRect(
      sashR,
      sashT,
      hasSashPlintheBottom: zone.hasSashPlintheBottom,
    );

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

    // Hardware is always shown on the internal face. On the external face it
    // remains an optional aid controlled by the visibility switch.
    final bool shouldDrawHandle = _shouldDrawWindowHardware;

    if (zone.openDirection != null) {
      // Hinges are painted after the window's inner area has been unclipped.
      // They sit partly on the outer frame reveal, so painting them here would
      // cut off the normal-window hinges at the external edges.
      if (shouldDrawHandle && forceHandle) {
        OpenDirection handleSide = zone.openDirection!;
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

  double _getSlidingSectionWidth(
    String typeName,
    String fallbackName,
    double defaultVal, {
    bool? reinforced,
  }) {
    final series = model.activeSlidingSeries;
    if (series == null) return defaultVal;

    final String tName = typeName.toLowerCase();
    final overrideKeys = <String>[];
    if (tName == 'traverse') {
      overrideKeys.addAll(const [
        'عرضي (Traverse)',
        'سكة الظلفة (Sash Traverse)',
      ]);
    } else if (tName == 'chicane') {
      overrideKeys.addAll(
        reinforced == true
            ? const [
                'قائم وسطي معزز (Sash Central Renforcé)',
                'قائم وسطي (Sash Central)',
                'قائم وسطي (Central)',
                'الشيكان (Chicane)',
              ]
            : const [
                'قائم وسطي (Sash Central)',
                'قائم وسطي (Central)',
                'الشيكان (Chicane)',
                'قائم وسطي معزز (Sash Central Renforcé)',
              ],
      );
    } else if (tName == 'lateral') {
      overrideKeys.addAll(
        reinforced == true
            ? const [
                'قائم جانبي معزز (Sash Lateral Renforcé)',
                'قائم جانبي (Sash Lateral)',
                'قائم جانبي (Lateral)',
              ]
            : const [
                'قائم جانبي (Sash Lateral)',
                'قائم جانبي (Lateral)',
                'قائم جانبي معزز (Sash Lateral Renforcé)',
              ],
      );
    }

    double widthFromOverride(Map<String, dynamic> override) {
      for (final key in const ['visible_width', 'thickness', 'width']) {
        final raw = override[key];
        final width = raw is num
            ? raw.toDouble()
            : double.tryParse(raw?.toString() ?? '') ?? 0.0;
        if (width > 0) return width;
      }
      return 0.0;
    }

    for (final key in overrideKeys) {
      final override = model.getSlidingComponentOverride(key);
      if (override != null) {
        final width = widthFromOverride(override);
        if (width > 0) return width;
      }
    }

    String? altType;
    if (tName == 'traverse') {
      altType = 'sash_traverse';
    } else if (tName == 'chicane' ||
        tName == 'central' ||
        tName == 'centrale') {
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
    bool squareLeft = false,
    bool squareRight = false,
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
        Offset(squareLeft ? glassR.left : sashR.left, ySashL),
        Offset(glassR.left, yGlassL),
        mp,
      );
      canvas.drawLine(
        Offset(squareRight ? glassR.right : sashR.right, ySashR),
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
        canvas.drawLine(
          Offset(squareLeft ? glassR.left : sashR.left, sashR.bottom),
          glassR.bottomLeft,
          mp,
        );
        canvas.drawLine(
          Offset(squareRight ? glassR.right : sashR.right, sashR.bottom),
          glassR.bottomRight,
          mp,
        );
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
    if (!_shouldDrawWindowHardware) return;

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
        final double topYVal = getSashTopY(
          x,
          sashRect.top,
          t,
          topOffset,
          isTopBound,
        );
        sashPart = Rect.fromLTRB(x - 16, topYVal, x + 16, topYVal + 10);
        framePart = Rect.fromLTRB(x - 16, topYVal - 10, x + 16, topYVal);
        knobCenter = Offset(x, topYVal + 5);
      } else if (handleSide == OpenDirection.bottom) {
        sashPart = Rect.fromLTRB(
          x - 16,
          sashRect.bottom - 10,
          x + 16,
          sashRect.bottom,
        );
        framePart = Rect.fromLTRB(
          x - 16,
          sashRect.bottom,
          x + 16,
          sashRect.bottom + 10,
        );
        knobCenter = Offset(x, sashRect.bottom - 5);
      } else if (handleSide == OpenDirection.left) {
        sashPart = Rect.fromLTRB(
          sashRect.left,
          handleY - 16,
          sashRect.left + 10,
          handleY + 16,
        );
        framePart = Rect.fromLTRB(
          sashRect.left - 10,
          handleY - 16,
          sashRect.left,
          handleY + 16,
        );
        knobCenter = Offset(sashRect.left + 5, handleY);
      } else {
        // OpenDirection.right
        sashPart = Rect.fromLTRB(
          sashRect.right - 10,
          handleY - 16,
          sashRect.right,
          handleY + 16,
        );
        framePart = Rect.fromLTRB(
          sashRect.right,
          handleY - 16,
          sashRect.right + 10,
          handleY + 16,
        );
        knobCenter = Offset(sashRect.right - 5, handleY);
      }

      // Draw Sash part (casing)
      final RRect sashRRect = RRect.fromRectAndRadius(
        sashPart,
        const Radius.circular(2),
      );
      canvas.drawRRect(sashRRect, basePaint);
      canvas.drawRRect(sashRRect, borderPaint);

      // Draw Frame part (keeper bracket)
      final RRect frameRRect = RRect.fromRectAndRadius(
        framePart,
        const Radius.circular(2),
      );
      canvas.drawRRect(frameRRect, basePaint);
      canvas.drawRRect(frameRRect, borderPaint);

      // Draw central pull knob (circle button - the "point/dot" itself) on the sash part
      canvas.drawCircle(
        knobCenter,
        5.5,
        Paint()
          ..color = Colors.black87
          ..style = PaintingStyle.fill,
      );
      canvas.drawCircle(
        knobCenter,
        3.5,
        Paint()
          ..color = Colors.grey[300]!
          ..style = PaintingStyle.fill,
      );
      canvas.drawCircle(
        knobCenter,
        1.2,
        Paint()
          ..color = Colors.black87
          ..style = PaintingStyle.fill,
      );

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

    final bool hasLock =
        zone?.lockType == LockType.clef ||
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
      isDoorHandle = false; // سواء PVC أو ألمنيوم، المنزلق لا يأخذ مقبض باب
    }

    if (zone?.lockType == LockType.none ||
        zone?.useOctoHandle == true ||
        zone?.usePvcHandleOnAlu == true) {
      if (zone?.content != ZoneContent.slidingSash || !model.isPVC) {
        isDoorHandle = false;
      }
    }

    // Cremone transmission rods: not drawn (disabled per design)
    // isCremone = true only for Aluminium sashes (not PVC)
    final bool isCremone =
        !model.isPVC &&
        (zone?.content == ZoneContent.singleSash ||
            zone?.content == ZoneContent.doubleSash) &&
        (zone?.lockType == LockType.none ||
            zone?.lockType == LockType.cremone) &&
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
      if (handleSide == OpenDirection.top ||
          handleSide == OpenDirection.bottom) {
        canvas.rotate(-math.pi / 2);
      }
    }

    final bool isSlidingSash =
        (zone?.content == ZoneContent.slidingSash) ||
        _isHandleSashProfile(zone);

    // في BBC المنزلق (isSlidingPVC) نستخدم نفس المقبض العادي لا المنزلق
    final bool isAluminumSliding =
        isSlidingSash && !model.isPVC && !model.isSlidingPVC;

    bool isSlidingHandle =
        isSlidingSash && !model.isPVC && zone?.useClassicHandle != true;

    bool isClassicSlidingHandle =
        isSlidingSash && !model.isPVC && zone?.useClassicHandle == true;

    final bool isMarechal =
        zone?.lockType == LockType.rouleau ||
        zone?.lockType == LockType.rouleau2000;

    if (isMarechal) {
      if (sashRect.height < 1250.0) {
        canvas.restore();
        return;
      }

      final double handleHeight = (zone?.lockType == LockType.rouleau2000)
          ? 2000.0
          : 1250.0;
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
      canvas.drawRect(
        Rect.fromCenter(center: Offset(0, -postDistY), width: 16, height: 16),
        postPaint,
      );
      canvas.drawRect(
        Rect.fromCenter(center: Offset(0, -postDistY), width: 16, height: 16),
        postBorder,
      );
      canvas.drawRect(
        Rect.fromCenter(center: Offset(0, postDistY), width: 16, height: 16),
        postPaint,
      );
      canvas.drawRect(
        Rect.fromCenter(center: Offset(0, postDistY), width: 16, height: 16),
        postBorder,
      );

      // Draw the main pull bar
      final RRect pullBar = RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset.zero,
          width: handleWidth,
          height: handleHeight,
        ),
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
      canvas.drawCircle(
        const Offset(0, 10),
        4.5,
        Paint()..color = Colors.black87,
      );
      canvas.drawRect(
        Rect.fromLTRB(-2.5, 10, 2.5, 20),
        Paint()..color = Colors.black87,
      );

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

      // Keyhole or turn knob below lever — only drawn when lock or bathroom option is selected
      double keyholeY = 25.0;
      final bool isCondamnation = zone?.lockType == LockType.condamnation;
      final bool isClef = zone?.lockType == LockType.clef;

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
      } else if (isClef) {
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

      const double plateW = 18.0;
      const double plateH = 60.0;
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
        Offset(-plateW / 4, plateH / 2 - 9),
        Paint()
          ..color = Colors.white
          ..strokeWidth = 2.0,
      );

      // ── Step B: Draw the Z-shaped grip ON TOP ───────────────────────────
      final Offset p0 = Offset.zero;
      final Offset p1 = Offset(
        dir * 32.0,
        32.0,
      ); // 45 degrees slant directly from center
      final Offset p2 = Offset(p1.dx, 120.0); // straight down, longer

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
      canvas.drawCircle(
        const Offset(-9, 12),
        1.0,
        Paint()..color = Colors.black45,
      );
      canvas.drawCircle(
        const Offset(9, 12),
        1.0,
        Paint()..color = Colors.black45,
      );

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
      canvas.drawCircle(
        const Offset(-11, -4),
        1.0,
        Paint()..color = Colors.black45,
      );
      canvas.drawCircle(
        const Offset(11, -4),
        1.0,
        Paint()..color = Colors.black45,
      );

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
      canvas.drawPath(
        boltPath,
        Paint()
          ..color = Colors.grey.shade300
          ..style = PaintingStyle.fill,
      );
      canvas.drawPath(boltPath, borderPaint);

      // Finger Pull Ring at the top
      final Offset ringCenter = const Offset(0, -28);
      // Outer ring
      canvas.drawCircle(ringCenter, 7.5, basePaint);
      canvas.drawCircle(ringCenter, 7.5, borderPaint);
      // Inner hole (finger entry)
      canvas.drawCircle(
        ringCenter,
        4.5,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.fill,
      );
      canvas.drawCircle(ringCenter, 4.5, borderPaint);
    } else if (isCremone) {
      // Cremone handle: same lever shape as normal, pointing toward hinges.
      // Base plate is vertical (top→bottom), 28 × 90 (square/rectangular with rounded corners).
      // Canvas may be rotated −90° for top/bottom sashes, so we compensate dimensions.
      final bool isRotatedCanvas =
          (handleSide == OpenDirection.top ||
          handleSide == OpenDirection.bottom);

      // leverDir: lever extends toward the hinge side in local (post-rotation) canvas-X
      final double leverDir;
      if (handleSide == OpenDirection.left ||
          handleSide == OpenDirection.bottom) {
        leverDir = 1.0; // +X in local space = toward hinges
      } else {
        leverDir = -1.0; // −X in local space = toward hinges
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
        Offset(
          isRotatedCanvas ? 0 : -bW / 4,
          isRotatedCanvas ? -bH / 2 + 8 : -bH / 2 + 8,
        ),
        Offset(
          isRotatedCanvas ? 0 : -bW / 4,
          isRotatedCanvas ? bH / 2 - 8 : bH / 2 - 8,
        ),
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
          leverDir == 1.0 ? 75 : halfThick,
          halfThick,
        ),
        const Radius.circular(8),
      );
      canvas.drawRRect(lever, basePaint);
      canvas.drawRRect(lever, borderPaint);

      // Highlight on lever
      canvas.drawLine(
        Offset(leverDir == 1.0 ? -2 : -70, -halfThick + 3),
        Offset(leverDir == 1.0 ? 70 : 2, -halfThick + 3),
        Paint()
          ..color = Colors.white.withValues(alpha: 0.5)
          ..strokeWidth = 1.5,
      );
    } else {
      // Normal PVC / standard window handle — base plate + lever always pointing downward
      final RRect basePlate = RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset.zero, width: 20, height: 64),
        const Radius.circular(8),
      );
      canvas.drawRRect(basePlate, basePaint);
      canvas.drawRRect(basePlate, borderPaint);

      // Screw caps on base plate
      canvas.drawCircle(
        const Offset(0, -21),
        1.8,
        Paint()..color = Colors.black45,
      );
      canvas.drawCircle(
        const Offset(0, 21),
        1.8,
        Paint()..color = Colors.black45,
      );

      // Central pivot hub
      canvas.drawCircle(Offset.zero, 8.0, basePaint);
      canvas.drawCircle(Offset.zero, 8.0, borderPaint);

      // Lever handle body extending downwards
      final RRect lever = RRect.fromRectAndRadius(
        Rect.fromLTRB(-8, -5, 8, 76),
        const Radius.circular(7),
      );
      canvas.drawRRect(lever, basePaint);
      canvas.drawRRect(lever, borderPaint);

      // Highlight stripe along the window lever handle for 3D depth
      canvas.drawLine(
        const Offset(-4, 0),
        const Offset(-4, 70),
        Paint()
          ..color = Colors.white.withValues(alpha: 0.6)
          ..strokeWidth = 2.0,
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
    var hingeCount = standardHingeCountForSash(
      sashHeight: zone.boundary.height,
      glassStructure: zone.glass.structure,
    );

    // Full System OB replaces the ordinary hinge layout only on the leaf that
    // carries the handle. Demi-OB has its own hardware and must not be drawn
    // as a full OB leaf.
    final bool isFullObHandleSash = model.useSystemOB && isHandleSash;
    if (isFullObHandleSash) {
      hingeCount = 2;
    }

    // Hinge hardware must remain readable on a white profile. Use the selected
    // accessory colour when it is dark enough; otherwise use a neutral grey,
    // then give it a dark outline and a central pin line.
    final accessoryColor = model.accessoryColor;
    final hingeColor = accessoryColor.computeLuminance() > 0.62
        ? const Color(0xFFB0B7C0)
        : Color.lerp(accessoryColor, Colors.black, 0.18)!;
    final paint = Paint()..color = hingeColor;
    final shadow = Paint()..color = Colors.black54;
    final outlinePaint = Paint()
      ..color = Colors.black87
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.35;

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
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(2)),
        outlinePaint,
      );
      // The central black pin visually separates the two leaves of the hinge.
      final linePaint = Paint()
        ..color = Colors.black
        ..strokeWidth = 1.7;
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
      // The hinge belongs in the narrow frame/sash reveal, not on top of the
      // sash face. Its offset is scaled from the profile thickness so it is
      // also correct for the wider series.
      final revealOffset = (t * 0.28).clamp(9.0, 18.0).toDouble();
      double x = onRight
          ? sashR.right + revealOffset
          : sashR.left - revealOffset;
      // OB keeps only the upper and lower hinges, positioned directly at the
      // ends of the sash rather than at the usual 100 mm inset.
      final double endInset = isFullObHandleSash ? 44.0 : 100.0;
      double startY =
              getSashTopY(x, sashR.top, t, topOffset, isTopBound) + endInset,
          step = (sashR.bottom - endInset - startY) / (hingeCount - 1);
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
      final revealOffset = (t * 0.28).clamp(9.0, 18.0).toDouble();
      double y = onBottom
          ? sashR.bottom + revealOffset
          : sashR.top - revealOffset;
      final double endInset = isFullObHandleSash ? 44.0 : 100.0;
      double startX = sashR.left + endInset,
          step = (sashR.right - endInset - startX) / (hingeCount - 1);
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
          finalY =
              getSashTopY(xPos, sashR.top, t, topOffset, isTopBound) -
              revealOffset;
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
    final _fc = getEffectiveGradientColors(
      model.frameColor,
      model.effectiveShutterColor,
    );
    bool _isWoodColor() =>
        this._isWoodColor() &&
        (model.selectedShutterColor == null ||
            model.selectedShutterColor?['id'] == model.selectedDbColor?['id']);
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

  /// Renders the motor controls independently from the shutter box so they
  /// also remain visible with a tunnel box. The remote is placed inside the
  /// frame; the wall switch is shown only when a wall is enabled.
  void _drawMotorControls(
    Canvas canvas,
    double w,
    double h,
    double t,
    double topOffset,
  ) {
    final controlTop = (model.isCaissonTunnel ? 0.0 : topOffset) + t + 18.0;
    final controlBottom = h - t - 18.0;
    if (controlBottom <= controlTop) return;

    final isRight = model.shutterDriveSide == 'right';
    if (model.motorHasTelecommande) {
      const remoteWidth = 21.0;
      const remoteHeight = 42.0;
      final remoteX = isRight ? w - t - remoteWidth - 18.0 : t + 18.0;
      final remoteY = math.min(controlTop, controlBottom - remoteHeight);
      final remoteRect = Rect.fromLTWH(
        remoteX,
        remoteY,
        remoteWidth,
        remoteHeight,
      );
      final border = Paint()
        ..color = const Color(0xFF475569)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.3;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          remoteRect.translate(1.5, 1.5),
          const Radius.circular(4),
        ),
        Paint()..color = Colors.black26,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(remoteRect, const Radius.circular(4)),
        Paint()..color = Colors.white,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(remoteRect, const Radius.circular(4)),
        border,
      );
      for (final entry in <MapEntry<double, Color>>[
        const MapEntry(10.0, Color(0xFFDC2626)),
        const MapEntry(21.0, Color(0xFF64748B)),
        const MapEntry(32.0, Color(0xFF64748B)),
      ]) {
        canvas.drawCircle(
          Offset(remoteRect.center.dx, remoteRect.top + entry.key),
          2.6,
          Paint()..color = entry.value,
        );
      }
    }

    if (model.motorHasInterrupteur && model.showWall) {
      const switchWidth = 36.0;
      const switchHeight = 56.0;
      final switchX = isRight ? w + 48.0 : -48.0 - switchWidth;
      final switchY = math.max(
        controlTop,
        math.min(
          controlBottom - switchHeight,
          controlTop + (controlBottom - controlTop) * 0.55,
        ),
      );
      final switchRect = Rect.fromLTWH(
        switchX,
        switchY,
        switchWidth,
        switchHeight,
      );
      final cableEnd = isRight ? switchRect.left : switchRect.right;
      canvas.drawLine(
        Offset(isRight ? w : 0.0, switchRect.center.dy),
        Offset(cableEnd, switchRect.center.dy),
        Paint()
          ..color = const Color(0xFF334155)
          ..strokeWidth = 2.0,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          switchRect.translate(1.5, 1.5),
          const Radius.circular(5),
        ),
        Paint()..color = Colors.black26,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(switchRect, const Radius.circular(5)),
        Paint()..color = const Color(0xFFF8FAFC),
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(switchRect, const Radius.circular(5)),
        Paint()
          ..color = const Color(0xFF475569)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4,
      );
      final symbolPaint = Paint()
        ..color = const Color(0xFF1E3A5F)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round;
      canvas.drawCircle(switchRect.center, 8.0, symbolPaint);
      canvas.drawLine(
        Offset(switchRect.center.dx, switchRect.center.dy - 12.0),
        Offset(switchRect.center.dx, switchRect.center.dy - 2.0),
        symbolPaint,
      );
    }
  }

  void _drawShutterBox(
    Canvas canvas,
    double w,
    double boxSize,
    double h, {
    bool drawOnlyManualControls = false,
  }) {
    final _fc = getEffectiveGradientColors(
      model.frameColor,
      model.effectiveShutterColor,
    );
    bool _isWoodColor() =>
        this._isWoodColor() &&
        (model.selectedShutterColor == null ||
            model.selectedShutterColor?['id'] == model.selectedDbColor?['id']);
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
        !_hasEffectiveBottomFrame && (rect.bottom - model.height).abs() < 1.0;
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

    canvas.drawPath(framePath, _buildPaint(rect));

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
      innerStrokePath.lineTo(innerRect.left, innerRect.bottom);
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

  Rect _getSafeGlassRect(
    Rect sashRect,
    double sashT, {
    bool hasSashPlintheBottom = false,
  }) {
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
  bool shouldRepaint(covariant WindowPainter oldDelegate) {
    return oldDelegate.model != model ||
        oldDelegate.repaintToken != repaintToken ||
        oldDelegate.overrideIsInternalView != overrideIsInternalView ||
        oldDelegate.showDrawingDimensions != showDrawingDimensions ||
        oldDelegate.showSelection != showSelection;
  }
}
