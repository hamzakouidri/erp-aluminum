part of '../show_system_francais.dart';

/// Pointer, drag, zoom and hit-testing on the drawing canvas.
extension _WindowViewCanvas on _WindowViewState {
  String? _getTappedCellId(WindowZone tappedZ, Offset modelPos) {
    bool isDouble = tappedZ.content == ZoneContent.doubleSash;
    bool isSingle = tappedZ.content == ZoneContent.singleSash;
    bool isSliding = tappedZ.content == ZoneContent.slidingSash;
    if (isDouble || isSingle || isSliding) {
      double splitX =
          tappedZ.boundary.left +
          tappedZ.boundary.width * tappedZ.doubleSashRatio;
      bool isRight = isDouble && (modelPos.dx > splitX);
      Rect sashR = tappedZ.boundary;
      if (isDouble) {
        final sep = 4.0;
        sashR = isRight
            ? Rect.fromLTRB(
                splitX + sep / 2,
                tappedZ.boundary.top,
                tappedZ.boundary.right,
                tappedZ.boundary.bottom,
              )
            : Rect.fromLTRB(
                tappedZ.boundary.left,
                tappedZ.boundary.top,
                splitX - sep / 2,
                tappedZ.boundary.bottom,
              );
      }
      final sashT =
          tappedZ.sashThickness ??
          widget.model.getSectionThickness('sash', fallback: 45.0);
      final glassR = sashR.deflate(sashT);
      if (glassR.contains(modelPos)) {
        int currentInnerH = isRight ? tappedZ.rightInnerH : tappedZ.innerH;
        int currentInnerV = isRight ? tappedZ.rightInnerV : tappedZ.innerV;
        double cellW = glassR.width / (currentInnerV + 1);
        double cellH = glassR.height / (currentInnerH + 1);
        int col = ((modelPos.dx - glassR.left) / cellW)
            .clamp(0, currentInnerV)
            .toInt();
        int row = ((modelPos.dy - glassR.top) / cellH)
            .clamp(0, currentInnerH)
            .toInt();
        String sidePrefix = isDouble ? (isRight ? 'right' : 'left') : 'main';
        return '${sidePrefix}_cell_${row}_$col';
      }
    } else {
      // Non-sash zone (fixed glass, etc.)
      final glassR = tappedZ.boundary;
      if (glassR.contains(modelPos)) {
        int currentInnerH = tappedZ.innerH;
        int currentInnerV = tappedZ.innerV;
        double cellW = glassR.width / (currentInnerV + 1);
        double cellH = glassR.height / (currentInnerH + 1);
        int col = ((modelPos.dx - glassR.left) / cellW)
            .clamp(0, currentInnerV)
            .toInt();
        int row = ((modelPos.dy - glassR.top) / cellH)
            .clamp(0, currentInnerH)
            .toInt();
        return 'main_cell_${row}_$col';
      }
    }
    return null;
  }

  String _currentSelectionKey() {
    final selection = widget.model.selection;
    return '${selection.type}|${selection.zoneId}|${selection.mullionPosition}|'
        '${selection.innerDivisionIndex}|${widget.model.activeSubZone ?? ''}';
  }

  void _handleHandleDrag(Offset delta, WindowZone zone) {
    if (zone.openDirection == null && zone.content != ZoneContent.slidingSash) {
      return;
    }
    double dy = delta.dy / (_userScale * widget.model.canvasScale);
    double newRatio = zone.handlePositionRatio ?? 0.5;
    newRatio -= (dy / zone.boundary.height);
    widget.model.updateHandlePosition(zone.id, newRatio.clamp(0.1, 0.9));
  }

  void _handleHingeDrag(Offset delta, WindowZone zone) {
    if (zone.openDirection == null && zone.content != ZoneContent.slidingSash) {
      return;
    }

    final hingeCount = standardHingeCountForSash(
      sashHeight: zone.boundary.height,
      glassStructure: zone.glass.structure,
    );

    if (hingeCount < 3) {
      // If 2 hinges, we cannot move anything!
      return;
    }

    double dy = delta.dy / (_userScale * widget.model.canvasScale);
    double newOffset = zone.middleHingeDragOffset;
    newOffset += dy * 200; // Multiply to make it more responsive
    if (newOffset < -150) newOffset = -150;
    if (newOffset > 150) newOffset = 150;
    widget.model.updateHingePosition(zone.id, newOffset);
  }

  bool _isTopZone(WindowZone zone) {
    if (widget.model.zones.isEmpty) return false;
    double minTop = widget.model.zones
        .map((z) => z.boundary.top)
        .reduce(math.min);
    return zone.boundary.top == minTop;
  }

  double getInnerTopY(double x, double t, double topOffset) {
    if (widget.model.archHeight == 0 &&
        widget.model.topSlantLeftY == 0 &&
        widget.model.topSlantRightY == 0) {
      return topOffset + t;
    }
    double factor = 0.0;
    if (widget.model.width > 2 * t) {
      factor = ((x - t) / (widget.model.width - 2 * t)).clamp(0.0, 1.0);
    }
    double yL = topOffset + widget.model.topSlantLeftY + t;
    double yR = topOffset + widget.model.topSlantRightY + t;
    if (widget.model.archHeight > 0) {
      double yC =
          topOffset +
          math.min(widget.model.topSlantLeftY, widget.model.topSlantRightY) -
          (widget.model.archHeight * 2) +
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

  bool _checkAndStartSashDividerDrag(
    String zoneId,
    bool isRight,
    Rect glassR,
    int innerH,
    int innerV,
    List<double> innerHPos,
    List<double> innerVPos,
    Offset touchScreen,
  ) {
    if (innerH == 0 && innerV == 0) return false;

    // 🟢 تكبير مساحة التقاط اللمس لتسهيل التحديد والتحريك (Hit Slop)
    final double hitRadius = 50.0; // كانت 30.0

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
    final zone = widget.model.zones.firstWhere(
      (candidate) => candidate.id == zoneId,
      orElse: () => WindowZone(
        id: zoneId,
        boundary: Rect.zero,
        sashColor: widget.model.frameColor,
      ),
    );
    String getVKey(int r, int v) => isRight ? 'right_${r}_$v' : '${r}_$v';
    String getHKey(int c, int h) => isRight ? 'right_${c}_$h' : '${c}_$h';

    // Check horizontal dividers
    for (int i = 0; i < hPositions.length; i++) {
      double yVal = glassR.top + glassR.height * hPositions[i];
      for (int c = 0; c < vPositions.length + 1; c++) {
        if (zone.disabledHorizontalDivisions[getHKey(c, i)] == true) {
          continue;
        }
        final leftRatio = c == 0 ? 0.0 : vPositions[c - 1];
        final rightRatio = c == vPositions.length ? 1.0 : vPositions[c];
        final lineStart = _modelToScreen(
          Offset(glassR.left + glassR.width * leftRatio, yVal),
        );
        final lineEnd = _modelToScreen(
          Offset(glassR.left + glassR.width * rightRatio, yVal),
        );
        final screenY = lineStart.dy;
        final screenLeft = math.min(lineStart.dx, lineEnd.dx);
        final screenRight = math.max(lineStart.dx, lineEnd.dx);

        if ((touchScreen.dy - screenY).abs() < hitRadius &&
            touchScreen.dx >= screenLeft - hitRadius &&
            touchScreen.dx <= screenRight + hitRadius) {
          _setViewState(() {
            _isDraggingSashDivision = true;
            _draggedSashZoneId = zoneId;
            _draggedSashIsRight = isRight;
            _draggedSashIsHorizontal = true;
            _draggedSashIndex = i;
          });
          widget.model.selection = SelectionInfo(
            type: SelectionType.innerDivision,
            zoneId: zoneId,
            isHorizontalInnerDivision: true,
            isRightSashInnerDivision: isRight,
            innerDivisionIndex: i,
          );
          widget.model.showZoneMenu = false;
          widget.model.activeSubZone = null;
          widget.model.refreshUI();
          return true;
        }
      }
    }

    // Check vertical dividers
    for (int i = 0; i < vPositions.length; i++) {
      double xVal = glassR.left + glassR.width * vPositions[i];
      for (int r = 0; r < hPositions.length + 1; r++) {
        if (zone.disabledVerticalDivisions[getVKey(r, i)] == true) {
          continue;
        }
        final topRatio = r == 0 ? 0.0 : hPositions[r - 1];
        final bottomRatio = r == hPositions.length ? 1.0 : hPositions[r];
        final lineStart = _modelToScreen(
          Offset(xVal, glassR.top + glassR.height * topRatio),
        );
        final lineEnd = _modelToScreen(
          Offset(xVal, glassR.top + glassR.height * bottomRatio),
        );
        final screenX = lineStart.dx;
        final screenTop = math.min(lineStart.dy, lineEnd.dy);
        final screenBottom = math.max(lineStart.dy, lineEnd.dy);

        if ((touchScreen.dx - screenX).abs() < hitRadius &&
            touchScreen.dy >= screenTop - hitRadius &&
            touchScreen.dy <= screenBottom + hitRadius) {
          _setViewState(() {
            _isDraggingSashDivision = true;
            _draggedSashZoneId = zoneId;
            _draggedSashIsRight = isRight;
            _draggedSashIsHorizontal = false;
            _draggedSashIndex = i;
          });
          widget.model.selection = SelectionInfo(
            type: SelectionType.innerDivision,
            zoneId: zoneId,
            isHorizontalInnerDivision: false,
            isRightSashInnerDivision: isRight,
            innerDivisionIndex: i,
          );
          widget.model.showZoneMenu = false;
          widget.model.activeSubZone = null;
          widget.model.refreshUI();
          return true;
        }
      }
    }

    return false;
  }

  void _startDrawingTimer() {
    _drawingTimer?.cancel();
    widget.model.setDrawingMode(true);
    _drawingTimer = Timer(const Duration(seconds: 10), () {
      if (mounted) {
        widget.model.setDrawingMode(false);
      }
    });
  }

  void _stopDrawingTimer() {
    _drawingTimer?.cancel();
    widget.model.setDrawingMode(false);
  }

  Offset _getModelPos(Offset screenPos) {
    final totalScale = widget.model.canvasScale * _userScale;
    return Offset(
      (screenPos.dx - widget.model.canvasDx - _userPan.dx) / totalScale,
      (screenPos.dy - widget.model.canvasDy - _userPan.dy) / totalScale,
    );
  }

  Offset _modelToScreen(Offset modelPosition) {
    final totalScale = widget.model.canvasScale * _userScale;
    return Offset(
      widget.model.canvasDx + _userPan.dx + modelPosition.dx * totalScale,
      widget.model.canvasDy + _userPan.dy + modelPosition.dy * totalScale,
    );
  }

  void _toggleMovementLock() {
    _setViewState(() {
      _isMovementLocked = !_isMovementLocked;
      widget.model.isMovementLocked = _isMovementLocked;
      if (!_isMovementLocked) {
        widget.model.lastLayoutSize = null;
      }
    });
    final lang = Provider.of<AppSettingsProvider>(
      context,
      listen: false,
    ).language;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _isMovementLocked
              ? Localization.translate('تم تثبيت الرسم ومنع حركته', lang)
              : Localization.translate('تم تحرير حركة الرسم', lang),
          style: const TextStyle(fontFamily: 'Cairo'),
        ),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _changeDrawingZoom(double factor, Offset focalPoint) {
    if (_isMovementLocked) return;
    final double nextScale = (_userScale * factor).clamp(
      _WindowViewState._minUserScale,
      _WindowViewState._maxUserScale,
    );
    if (nextScale == _userScale) return;

    _setViewState(() {
      final scaleRatio = nextScale / _userScale;
      // canvasDx/canvasDy are applied before the user zoom.  Keeping them in
      // this equation makes the focal point truly stationary instead of
      // pulling the drawing towards the top-left on every zoom step.
      final canvasOrigin = Offset(widget.model.canvasDx, widget.model.canvasDy);
      _userPan =
          focalPoint -
          canvasOrigin -
          (focalPoint - canvasOrigin - _userPan) * scaleRatio;
      _userScale = nextScale;
    });
  }

  void _handleDrawingPointerSignal(PointerSignalEvent event) {
    if (_isMovementLocked) return;
    if (!_isWindowsDesktop || event is! PointerScrollEvent) return;
    final verticalDelta = event.scrollDelta.dy;
    if (verticalDelta == 0) return;

    GestureBinding.instance.pointerSignalResolver.register(event, (_) {
      if (!mounted) return;
      _changeDrawingZoom(
        verticalDelta < 0 ? _WindowViewState._zoomStep : 1 / _WindowViewState._zoomStep,
        _drawingViewportCenter(),
      );
    });
  }

  void _resetDrawingZoom() {
    if (_isMovementLocked) return;
    _setViewState(() {
      _userScale = 1.0;
      _userPan = Offset.zero;
    });
    // The drawing stays where it was created until the user explicitly asks
    // to centre it using this control.
    widget.model.centerDrawingOnCanvas();
  }

  Offset _drawingViewportCenter() {
    final size = widget.model.lastLayoutSize;
    if (size == null) return Offset.zero;
    return Offset(size.width / 2, size.height / 2);
  }

  Rect? _dimensionTextBounds(
    String text,
    Rect bounds, {
    bool vertical = false,
  }) {
    final crossAxis = vertical ? bounds.width : bounds.height;
    final mainAxis = vertical ? bounds.height : bounds.width;
    if (crossAxis < 12 || mainAxis < 35) return null;

    double fontSize = math.min(34.0, math.max(15.0, crossAxis * 0.78));
    late TextPainter painter;
    while (true) {
      painter = TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w800),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      if (painter.width <= mainAxis - 8 || fontSize <= 10) break;
      fontSize -= 1.0;
    }
    if (painter.width > mainAxis - 4) return null;

    return vertical
        ? Rect.fromCenter(
            center: bounds.center,
            width: painter.height + 6,
            height: painter.width + 8,
          )
        : Rect.fromCenter(
            center: bounds.center,
            width: painter.width + 8,
            height: painter.height + 6,
          );
  }

  /// Hit-test only the visible number written in the selected frame profile.
  /// The remaining profile area stays available for selecting the frame.
  InnerDimensionHit? _frameProfileDimensionHit(Offset modelPosition) {
    if (widget.model.zones.length < 2) return null;
    final thickness = widget.model.profileThickness;
    final showWidthInside = widget.model.getVerticalFrameJoints().isEmpty;
    final showHeightInside = widget.model.getHorizontalFrameJoints().isEmpty;
    final frameRects = widget.model.getFrameRects();
    for (final outer in frameRects.reversed) {
      WindowZone? representativeZone;
      final inner = outer.deflate(thickness);
      for (final zone in widget.model.zones) {
        if (inner.overlaps(zone.boundary) ||
            inner.contains(zone.boundary.center)) {
          representativeZone = zone;
          break;
        }
      }
      if (representativeZone == null) continue;
      if (showWidthInside) {
        final widthBounds = Rect.fromLTWH(
          outer.left + 2,
          outer.top + 1,
          math.max(0.0, outer.width - 4),
          math.max(0.0, thickness - 2),
        );
        final widthText = _dimensionTextBounds(
          '${outer.width.toInt()}',
          widthBounds,
        );
        if (widthText?.contains(modelPosition) == true) {
          return InnerDimensionHit(representativeZone.id, true);
        }
      }

      if (showHeightInside) {
        final heightBounds = Rect.fromLTWH(
          outer.left + 1,
          outer.top + 2,
          math.max(0.0, thickness - 2),
          math.max(0.0, outer.height - 4),
        );
        final heightText = _dimensionTextBounds(
          '${outer.height.toInt()}',
          heightBounds,
          vertical: true,
        );
        if (heightText?.contains(modelPosition) == true) {
          return InnerDimensionHit(representativeZone.id, false);
        }
      }
    }
    return null;
  }

  void _toggleDrawingInteractionMode() {
    if (widget.model.isDrawingMode) {
      _stopDrawingTimer();
    } else {
      _startDrawingTimer();
    }
    _setViewState(() {});
  }

  String _shownDimensionText(double value) {
    final rounded = (value * 10).round() / 10;
    return (rounded - rounded.round()).abs() < 0.001
        ? rounded.round().toString()
        : rounded.toStringAsFixed(1);
  }
}
