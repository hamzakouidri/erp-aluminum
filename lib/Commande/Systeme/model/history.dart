part of '../model.dart';

/// Undo/redo history and drawing snapshots of [WindowModel].
extension WindowModelHistory on WindowModel {
  bool get canUndo => _history.isNotEmpty;

  bool get canRedo => _redoHistory.isNotEmpty;

  void _saveSnapshot() {
    _history.add(
      WindowSnapshot(
        width,
        height,
        hasBottomFrame,
        Set<String>.from(removedShutterSides),
        hasFramePlintheBottom,
        zones.map((z) => z.clone()).toList(),
        Map.from(mullionProfiles),
        Map.from(groovedMullionCavityOnPositiveSide),
        mullionSectionOverrides.map(
          (key, value) => MapEntry(key, Map<String, dynamic>.from(value)),
        ),
        selectedDbColor != null ? Map.from(selectedDbColor!) : null,
        Map.from(componentOverrides),
        archHeight,
        topSlantLeftY,
        topSlantRightY,
        bottomSlantLeftY,
        bottomSlantRightY,
        shutterPosition,
        shutterMechanism,
        hasShutter,
        useSystemOB,
        useDemiOB,
        useVerrouCentral,
        isCaissonTunnel,
        showBottomWall,
        showWall,
        wallColor,
        primaryMullionAxis,
        drawnLeft,
        drawnTop,
        useCustomSideCoverLayout,
        sideCoverSegments.map((segment) => segment.copyWith()).toList(),
        Set<String>.from(hiddenSideCoverSegments),
        hasInternalSlidingSideCover,
        internalSlidingSideCoverOverride == null
            ? null
            : Map<String, dynamic>.from(internalSlidingSideCoverOverride!),
        Map<String, int>.from(mullionCreationOrder),
        mullionStepCounter,
        isShutterOnly,
        drawingMode,
        drawNextShapeAsShutterOnly,
        isDrawingMode,
        hasSideCovers,
        _multiFrameSideCoverManuallyEnabled,
        profileAngleMode,
        Set<int>.from(profileAngleJunctions),
        profileAngleJunctionsDisabled,
        viewAs90DegreeCorner,
        frameOverride == null
            ? null
            : Map<String, dynamic>.from(frameOverride!),
        slidingFrameOverride == null
            ? null
            : Map<String, dynamic>.from(slidingFrameOverride!),
        sideCoverOverride == null
            ? null
            : Map<String, dynamic>.from(sideCoverOverride!),
        selectedSideCover,
        _preProfileAngleFrameOverride == null
            ? null
            : Map<String, dynamic>.from(_preProfileAngleFrameOverride!),
        _preProfileAngleSlidingOverride == null
            ? null
            : Map<String, dynamic>.from(_preProfileAngleSlidingOverride!),
        _frameSwitchedForProfileAngle,
        _profileAngleFrameSwitchNotice,
      ),
    );
    _history.last.catalogSelection = _captureCatalogSelection();
    _history.last.cornerNotches = cornerNotches;
    if (_history.length > 20) _history.removeAt(0);
    _redoHistory.clear();
    // Saving undo history does not change anything that is visible.  Notifying
    // here made every edit repaint twice: once with the old value immediately
    // before the mutation, then again with the actual new value.  On complex
    // drawings that duplicate paint/validation pass was noticeable while
    // entering dimensions and could make the text field appear unresponsive.
    // The editing operation itself notifies after its mutation is complete.
  }

  void saveSnapshotOutside() {
    _saveSnapshot();
  }

  void undo() {
    if (_history.isEmpty) return;
    _redoHistory.add(
      WindowSnapshot(
        width,
        height,
        hasBottomFrame,
        Set<String>.from(removedShutterSides),
        hasFramePlintheBottom,
        zones.map((z) => z.clone()).toList(),
        Map.from(mullionProfiles),
        Map.from(groovedMullionCavityOnPositiveSide),
        mullionSectionOverrides.map(
          (key, value) => MapEntry(key, Map<String, dynamic>.from(value)),
        ),
        selectedDbColor != null ? Map.from(selectedDbColor!) : null,
        Map.from(componentOverrides),
        archHeight,
        topSlantLeftY,
        topSlantRightY,
        bottomSlantLeftY,
        bottomSlantRightY,
        shutterPosition,
        shutterMechanism,
        hasShutter,
        useSystemOB,
        useDemiOB,
        useVerrouCentral,
        isCaissonTunnel,
        showBottomWall,
        showWall,
        wallColor,
        primaryMullionAxis,
        drawnLeft,
        drawnTop,
        useCustomSideCoverLayout,
        sideCoverSegments.map((segment) => segment.copyWith()).toList(),
        Set<String>.from(hiddenSideCoverSegments),
        hasInternalSlidingSideCover,
        internalSlidingSideCoverOverride == null
            ? null
            : Map<String, dynamic>.from(internalSlidingSideCoverOverride!),
        Map<String, int>.from(mullionCreationOrder),
        mullionStepCounter,
        isShutterOnly,
        drawingMode,
        drawNextShapeAsShutterOnly,
        isDrawingMode,
        hasSideCovers,
        _multiFrameSideCoverManuallyEnabled,
        profileAngleMode,
        Set<int>.from(profileAngleJunctions),
        profileAngleJunctionsDisabled,
        viewAs90DegreeCorner,
        frameOverride == null
            ? null
            : Map<String, dynamic>.from(frameOverride!),
        slidingFrameOverride == null
            ? null
            : Map<String, dynamic>.from(slidingFrameOverride!),
        sideCoverOverride == null
            ? null
            : Map<String, dynamic>.from(sideCoverOverride!),
        selectedSideCover,
        _preProfileAngleFrameOverride == null
            ? null
            : Map<String, dynamic>.from(_preProfileAngleFrameOverride!),
        _preProfileAngleSlidingOverride == null
            ? null
            : Map<String, dynamic>.from(_preProfileAngleSlidingOverride!),
        _frameSwitchedForProfileAngle,
        _profileAngleFrameSwitchNotice,
      ),
    );

    _redoHistory.last.catalogSelection = _captureCatalogSelection();
    _redoHistory.last.cornerNotches = cornerNotches;
    if (_redoHistory.length > 20) _redoHistory.removeAt(0);

    final snap = _history.removeLast();
    _restoreCatalogSelection(snap.catalogSelection);
    width = snap.width;
    height = snap.height;
    hasBottomFrame = snap.hasBottomFrame;
    removedShutterSides = Set<String>.from(snap.removedShutterSides);
    hasFramePlintheBottom = snap.hasFramePlintheBottom;
    zones = snap.zones;
    mullionProfiles = snap.mullionProfiles;
    groovedMullionCavityOnPositiveSide = Map.from(
      snap.groovedMullionCavityOnPositiveSide,
    );
    mullionSectionOverrides = snap.mullionSectionOverrides.map(
      (key, value) => MapEntry(key, Map<String, dynamic>.from(value)),
    );
    _selectedDbColor = snap.selectedDbColor;
    componentOverrides = snap.componentOverrides;
    archHeight = snap.archHeight;
    topSlantLeftY = snap.topSlantLeftY;
    topSlantRightY = snap.topSlantRightY;
    bottomSlantLeftY = snap.bottomSlantLeftY;
    bottomSlantRightY = snap.bottomSlantRightY;
    cornerNotches = snap.cornerNotches;
    shutterPosition = snap.shutterPosition;
    shutterMechanism = snap.shutterMechanism;
    hasShutter = snap.hasShutter;
    useSystemOB = snap.useSystemOB;
    useDemiOB = snap.useDemiOB;
    useVerrouCentral = snap.useVerrouCentral;
    isCaissonTunnel = snap.isCaissonTunnel;
    showBottomWall = snap.showBottomWall;
    showWall = snap.showWall;
    wallColor = snap.wallColor;
    primaryMullionAxis = snap.primaryMullionAxis;
    drawnLeft = snap.drawnLeft;
    drawnTop = snap.drawnTop;
    useCustomSideCoverLayout = snap.useCustomSideCoverLayout;
    sideCoverSegments = snap.sideCoverSegments
        .map((segment) => segment.copyWith())
        .toList();
    hiddenSideCoverSegments = Set<String>.from(snap.hiddenSideCoverSegments);
    hasInternalSlidingSideCover = snap.hasInternalSlidingSideCover;
    internalSlidingSideCoverOverride =
        snap.internalSlidingSideCoverOverride == null
        ? null
        : Map<String, dynamic>.from(snap.internalSlidingSideCoverOverride!);
    selectedInternalSlidingSideCover = null;
    isShutterOnly = snap.isShutterOnly;
    drawingMode = snap.drawingMode;
    drawNextShapeAsShutterOnly = snap.drawNextShapeAsShutterOnly;
    isDrawingMode = snap.isDrawingMode;
    hasSideCovers = snap.hasSideCovers;
    _multiFrameSideCoverManuallyEnabled =
        snap.multiFrameSideCoverManuallyEnabled;
    profileAngleMode = snap.profileAngleMode;
    profileAngleJunctions = Set<int>.from(snap.profileAngleJunctions);
    profileAngleJunctionsDisabled = snap.profileAngleJunctionsDisabled;
    viewAs90DegreeCorner = snap.viewAs90DegreeCorner;
    frameOverride = snap.frameOverride == null
        ? null
        : Map<String, dynamic>.from(snap.frameOverride!);
    slidingFrameOverride = snap.slidingFrameOverride == null
        ? null
        : Map<String, dynamic>.from(snap.slidingFrameOverride!);
    sideCoverOverride = snap.sideCoverOverride == null
        ? null
        : Map<String, dynamic>.from(snap.sideCoverOverride!);
    selectedSideCover = snap.selectedSideCover;
    _preProfileAngleFrameOverride = snap.preProfileAngleFrameOverride == null
        ? null
        : Map<String, dynamic>.from(snap.preProfileAngleFrameOverride!);
    _preProfileAngleSlidingOverride =
        snap.preProfileAngleSlidingOverride == null
        ? null
        : Map<String, dynamic>.from(snap.preProfileAngleSlidingOverride!);
    _frameSwitchedForProfileAngle = snap.frameSwitchedForProfileAngle;
    _profileAngleFrameSwitchNotice = snap.profileAngleFrameSwitchNotice;
    selectedFrameCode = frameOverride?['code']?.toString();
    updateProfileThickness();
    enforceBottomSideCoverConstraint();
    if (snap.mullionCreationOrder != null) {
      mullionCreationOrder = Map.from(snap.mullionCreationOrder!);
      mullionStepCounter = snap.mullionStepCounter ?? 0;
    }

    selection = SelectionInfo.none;
    activeSubZone = null;
    showZoneMenu = false;
    // The item quantity is not part of the drawing history: undoing a
    // geometry edit used to reset an order line of 5 windows to 1.
    _notifyModelListeners();
  }

  void redo() {
    if (_redoHistory.isEmpty) return;
    _history.add(
      WindowSnapshot(
        width,
        height,
        hasBottomFrame,
        Set<String>.from(removedShutterSides),
        hasFramePlintheBottom,
        zones.map((z) => z.clone()).toList(),
        Map.from(mullionProfiles),
        Map.from(groovedMullionCavityOnPositiveSide),
        mullionSectionOverrides.map(
          (key, value) => MapEntry(key, Map<String, dynamic>.from(value)),
        ),
        selectedDbColor != null ? Map.from(selectedDbColor!) : null,
        Map.from(componentOverrides),
        archHeight,
        topSlantLeftY,
        topSlantRightY,
        bottomSlantLeftY,
        bottomSlantRightY,
        shutterPosition,
        shutterMechanism,
        hasShutter,
        useSystemOB,
        useDemiOB,
        useVerrouCentral,
        isCaissonTunnel,
        showBottomWall,
        showWall,
        wallColor,
        primaryMullionAxis,
        drawnLeft,
        drawnTop,
        useCustomSideCoverLayout,
        sideCoverSegments.map((segment) => segment.copyWith()).toList(),
        Set<String>.from(hiddenSideCoverSegments),
        hasInternalSlidingSideCover,
        internalSlidingSideCoverOverride == null
            ? null
            : Map<String, dynamic>.from(internalSlidingSideCoverOverride!),
        Map<String, int>.from(mullionCreationOrder),
        mullionStepCounter,
        isShutterOnly,
        drawingMode,
        drawNextShapeAsShutterOnly,
        isDrawingMode,
        hasSideCovers,
        _multiFrameSideCoverManuallyEnabled,
        profileAngleMode,
        Set<int>.from(profileAngleJunctions),
        profileAngleJunctionsDisabled,
        viewAs90DegreeCorner,
        frameOverride == null
            ? null
            : Map<String, dynamic>.from(frameOverride!),
        slidingFrameOverride == null
            ? null
            : Map<String, dynamic>.from(slidingFrameOverride!),
        sideCoverOverride == null
            ? null
            : Map<String, dynamic>.from(sideCoverOverride!),
        selectedSideCover,
        _preProfileAngleFrameOverride == null
            ? null
            : Map<String, dynamic>.from(_preProfileAngleFrameOverride!),
        _preProfileAngleSlidingOverride == null
            ? null
            : Map<String, dynamic>.from(_preProfileAngleSlidingOverride!),
        _frameSwitchedForProfileAngle,
        _profileAngleFrameSwitchNotice,
      ),
    );
    _history.last.catalogSelection = _captureCatalogSelection();
    _history.last.cornerNotches = cornerNotches;
    if (_history.length > 20) _history.removeAt(0);

    final snap = _redoHistory.removeLast();
    _restoreCatalogSelection(snap.catalogSelection);
    width = snap.width;
    height = snap.height;
    hasBottomFrame = snap.hasBottomFrame;
    removedShutterSides = Set<String>.from(snap.removedShutterSides);
    hasFramePlintheBottom = snap.hasFramePlintheBottom;
    zones = snap.zones;
    mullionProfiles = snap.mullionProfiles;
    groovedMullionCavityOnPositiveSide = Map.from(
      snap.groovedMullionCavityOnPositiveSide,
    );
    mullionSectionOverrides = snap.mullionSectionOverrides.map(
      (key, value) => MapEntry(key, Map<String, dynamic>.from(value)),
    );
    _selectedDbColor = snap.selectedDbColor;
    componentOverrides = snap.componentOverrides;
    archHeight = snap.archHeight;
    topSlantLeftY = snap.topSlantLeftY;
    topSlantRightY = snap.topSlantRightY;
    bottomSlantLeftY = snap.bottomSlantLeftY;
    bottomSlantRightY = snap.bottomSlantRightY;
    cornerNotches = snap.cornerNotches;
    shutterPosition = snap.shutterPosition;
    shutterMechanism = snap.shutterMechanism;
    hasShutter = snap.hasShutter;
    useSystemOB = snap.useSystemOB;
    useDemiOB = snap.useDemiOB;
    useVerrouCentral = snap.useVerrouCentral;
    isCaissonTunnel = snap.isCaissonTunnel;
    showBottomWall = snap.showBottomWall;
    showWall = snap.showWall;
    wallColor = snap.wallColor;
    primaryMullionAxis = snap.primaryMullionAxis;
    drawnLeft = snap.drawnLeft;
    drawnTop = snap.drawnTop;
    useCustomSideCoverLayout = snap.useCustomSideCoverLayout;
    sideCoverSegments = snap.sideCoverSegments
        .map((segment) => segment.copyWith())
        .toList();
    hiddenSideCoverSegments = Set<String>.from(snap.hiddenSideCoverSegments);
    hasInternalSlidingSideCover = snap.hasInternalSlidingSideCover;
    internalSlidingSideCoverOverride =
        snap.internalSlidingSideCoverOverride == null
        ? null
        : Map<String, dynamic>.from(snap.internalSlidingSideCoverOverride!);
    selectedInternalSlidingSideCover = null;
    isShutterOnly = snap.isShutterOnly;
    drawingMode = snap.drawingMode;
    drawNextShapeAsShutterOnly = snap.drawNextShapeAsShutterOnly;
    isDrawingMode = snap.isDrawingMode;
    hasSideCovers = snap.hasSideCovers;
    _multiFrameSideCoverManuallyEnabled =
        snap.multiFrameSideCoverManuallyEnabled;
    profileAngleMode = snap.profileAngleMode;
    profileAngleJunctions = Set<int>.from(snap.profileAngleJunctions);
    profileAngleJunctionsDisabled = snap.profileAngleJunctionsDisabled;
    viewAs90DegreeCorner = snap.viewAs90DegreeCorner;
    frameOverride = snap.frameOverride == null
        ? null
        : Map<String, dynamic>.from(snap.frameOverride!);
    slidingFrameOverride = snap.slidingFrameOverride == null
        ? null
        : Map<String, dynamic>.from(snap.slidingFrameOverride!);
    sideCoverOverride = snap.sideCoverOverride == null
        ? null
        : Map<String, dynamic>.from(snap.sideCoverOverride!);
    selectedSideCover = snap.selectedSideCover;
    _preProfileAngleFrameOverride = snap.preProfileAngleFrameOverride == null
        ? null
        : Map<String, dynamic>.from(snap.preProfileAngleFrameOverride!);
    _preProfileAngleSlidingOverride =
        snap.preProfileAngleSlidingOverride == null
        ? null
        : Map<String, dynamic>.from(snap.preProfileAngleSlidingOverride!);
    _frameSwitchedForProfileAngle = snap.frameSwitchedForProfileAngle;
    _profileAngleFrameSwitchNotice = snap.profileAngleFrameSwitchNotice;
    selectedFrameCode = frameOverride?['code']?.toString();
    updateProfileThickness();
    enforceBottomSideCoverConstraint();

    selection = SelectionInfo.none;
    activeSubZone = null;
    showZoneMenu = false;
    // The item quantity is not part of the drawing history: undoing a
    // geometry edit used to reset an order line of 5 windows to 1.
    _notifyModelListeners();
  }

  /// Finds all Cadre double mullion segments in the drawing.
  /// Each Cadre double divider receives two Cache-rainure cuts (inside and outside).
  List<CadreDoubleRainureSegment> getCadreDoubleRainureSegments() {
    final segments = <CadreDoubleRainureSegment>[];
    if (zones.length < 2) return segments;

    final double mullionT =
        math.max(maximumMullionThickness, profileThickness * 2) + 8.0;

    for (int i = 0; i < zones.length; i++) {
      final z1 = zones[i];
      for (int j = i + 1; j < zones.length; j++) {
        final z2 = zones[j];

        // Horizontal boundary
        final overlapLeft = math.max(z1.boundary.left, z2.boundary.left);
        final overlapRight = math.min(z1.boundary.right, z2.boundary.right);
        if (overlapLeft < overlapRight - 5.0) {
          if ((z1.boundary.bottom - z2.boundary.top).abs() <= mullionT ||
              (z2.boundary.bottom - z1.boundary.top).abs() <= mullionT) {
            final yCenter =
                ((z1.boundary.bottom - z2.boundary.top).abs() <= mullionT)
                ? (z1.boundary.bottom + z2.boundary.top) / 2.0
                : (z2.boundary.bottom + z1.boundary.top) / 2.0;
            if (isDoubleFrameMullionAt(true, yCenter)) {
              final sliding =
                  z1.content == ZoneContent.slidingSash ||
                  z2.content == ZoneContent.slidingSash;
              segments.add(
                CadreDoubleRainureSegment(
                  isHorizontal: true,
                  position: yCenter,
                  start: overlapLeft,
                  end: overlapRight,
                  usesSlidingSeries: sliding,
                ),
              );
            }
          }
        }

        // Vertical boundary
        final overlapTop = math.max(z1.boundary.top, z2.boundary.top);
        final overlapBottom = math.min(z1.boundary.bottom, z2.boundary.bottom);
        if (overlapTop < overlapBottom - 5.0) {
          if ((z1.boundary.right - z2.boundary.left).abs() <= mullionT ||
              (z2.boundary.right - z1.boundary.left).abs() <= mullionT) {
            final xCenter =
                ((z1.boundary.right - z2.boundary.left).abs() <= mullionT)
                ? (z1.boundary.right + z2.boundary.left) / 2.0
                : (z2.boundary.right + z1.boundary.left) / 2.0;
            if (isDoubleFrameMullionAt(false, xCenter)) {
              final sliding =
                  z1.content == ZoneContent.slidingSash ||
                  z2.content == ZoneContent.slidingSash;
              segments.add(
                CadreDoubleRainureSegment(
                  isHorizontal: false,
                  position: xCenter,
                  start: overlapTop,
                  end: overlapBottom,
                  usesSlidingSeries: sliding,
                ),
              );
            }
          }
        }
      }
    }

    if (segments.length <= 1) return segments;
    final result = <CadreDoubleRainureSegment>[];
    final grouped = <String, List<CadreDoubleRainureSegment>>{};
    for (final seg in segments) {
      final key =
          '${seg.isHorizontal ? "H" : "V"}_${(seg.position / 2.0).round() * 2}';
      grouped.putIfAbsent(key, () => []).add(seg);
    }

    for (final list in grouped.values) {
      list.sort((a, b) => a.start.compareTo(b.start));
      var currentStart = list.first.start;
      var currentEnd = list.first.end;
      var currentPos = list.first.position;
      var isH = list.first.isHorizontal;
      var sliding = list.first.usesSlidingSeries;

      for (int i = 1; i < list.length; i++) {
        final s = list[i];
        if (s.start <= currentEnd + 5.0) {
          currentEnd = math.max(currentEnd, s.end);
        } else {
          result.add(
            CadreDoubleRainureSegment(
              isHorizontal: isH,
              position: currentPos,
              start: currentStart,
              end: currentEnd,
              usesSlidingSeries: sliding,
            ),
          );
          currentStart = s.start;
          currentEnd = s.end;
          currentPos = s.position;
          sliding = s.usesSlidingSeries;
        }
      }
      result.add(
        CadreDoubleRainureSegment(
          isHorizontal: isH,
          position: currentPos,
          start: currentStart,
          end: currentEnd,
          usesSlidingSeries: sliding,
        ),
      );
    }
    return result;
  }

  void moveSelectedMullionWithHistory(
    double deltaPixels, {
    bool saveHistory = true,
  }) {
    if (selection.type != SelectionType.mullion ||
        selection.mullionPosition == null) {
      return;
    }
    if (saveHistory) _saveSnapshot();
    bool isH = selection.isHorizontalMullion!;
    double pos = selection.mullionPosition!;
    final isDouble = isDoubleFrameMullionAt(isH, pos);
    final profileW = frameProfileWidthAt(isH, pos);
    final effectiveThickness = isDouble ? profileW * 2.0 : mullionThickness;
    final sep = effectiveThickness / 2;
    final t = profileThickness;
    final selectedStart = selection.mullionStart ?? double.negativeInfinity;
    final selectedEnd = selection.mullionEnd ?? double.infinity;
    bool overlapsSelectedSpan(WindowZone zone) {
      final spanStart = isH ? zone.boundary.left : zone.boundary.top;
      final spanEnd = isH ? zone.boundary.right : zone.boundary.bottom;
      return math.max(spanStart, selectedStart) <
          math.min(spanEnd, selectedEnd) - 2.0;
    }

    const alignThreshold = 100.0;
    final matchingDividers = <double>{pos};
    for (var i = 0; i < zones.length; i++) {
      for (var j = i + 1; j < zones.length; j++) {
        final za = zones[i].boundary;
        final zb = zones[j].boundary;
        if (isH) {
          if ((za.bottom - zb.top).abs() <= maximumMullionThickness + 8.0 ||
              (zb.bottom - za.top).abs() <= maximumMullionThickness + 8.0) {
            final yMid =
                ((za.bottom - zb.top).abs() <= maximumMullionThickness + 8.0)
                ? (za.bottom + zb.top) / 2
                : (zb.bottom + za.top) / 2;
            if ((yMid - pos).abs() <= alignThreshold) {
              matchingDividers.add(yMid);
            }
          }
        } else {
          if ((za.right - zb.left).abs() <= maximumMullionThickness + 8.0 ||
              (zb.right - za.left).abs() <= maximumMullionThickness + 8.0) {
            final xMid =
                ((za.right - zb.left).abs() <= maximumMullionThickness + 8.0)
                ? (za.right + zb.left) / 2
                : (zb.right + za.left) / 2;
            if ((xMid - pos).abs() <= alignThreshold) {
              matchingDividers.add(xMid);
            }
          }
        }
      }
    }

    if (isH) {
      double minAllowedY = t * 2;
      double maxAllowedY = height - t * 2;
      for (var z in zones) {
        if (!overlapsSelectedSpan(z)) continue;
        for (final divY in matchingDividers) {
          if ((z.boundary.bottom - divY).abs() <= effectiveThickness + 8.0) {
            if (z.boundary.top + minimumZoneSpanMm(z, isWidth: false) > minAllowedY) {
              minAllowedY = z.boundary.top + minimumZoneSpanMm(z, isWidth: false);
            }
          }
          if ((z.boundary.top - divY).abs() <= effectiveThickness + 8.0) {
            if (z.boundary.bottom - minimumZoneSpanMm(z, isWidth: false) < maxAllowedY) {
              maxAllowedY = z.boundary.bottom - minimumZoneSpanMm(z, isWidth: false);
            }
          }
        }
      }
      double newPos = pos + deltaPixels;
      // No legal position: the neighbouring zones are already at their minimum.
      if (minAllowedY + sep > maxAllowedY - sep) return;
      if (newPos - sep < minAllowedY) newPos = minAllowedY + sep;
      if (newPos + sep > maxAllowedY) newPos = maxAllowedY - sep;
      double actualDelta = newPos - pos;
      if (actualDelta == 0) return;

      for (int i = 0; i < zones.length; i++) {
        var z = zones[i];
        if (!overlapsSelectedSpan(z)) continue;
        for (final divY in matchingDividers) {
          if (z.boundary.bottom <= divY + 4.0 &&
              (divY - z.boundary.bottom).abs() <= effectiveThickness + 8.0) {
            zones[i] = z.copyWith(
              boundary: Rect.fromLTRB(
                z.boundary.left,
                z.boundary.top,
                z.boundary.right,
                z.boundary.bottom + actualDelta,
              ),
            );
            z = zones[i];
          } else if (z.boundary.top >= divY - 4.0 &&
              (z.boundary.top - divY).abs() <= effectiveThickness + 8.0) {
            zones[i] = z.copyWith(
              boundary: Rect.fromLTRB(
                z.boundary.left,
                z.boundary.top + actualDelta,
                z.boundary.right,
                z.boundary.bottom,
              ),
            );
            z = zones[i];
          }
        }
      }
      for (final oldDiv in matchingDividers) {
        _moveMullionMetadata(
          _mullionKey(isH, oldDiv),
          _mullionKey(isH, oldDiv + actualDelta),
        );
      }
      selection = SelectionInfo(
        type: SelectionType.mullion,
        isHorizontalMullion: isH,
        mullionPosition: newPos,
        mullionStart: selection.mullionStart,
        mullionEnd: selection.mullionEnd,
      );
      _snapNearbyParallelMullions(isHorizontal: true, targetPos: newPos);
    } else {
      double minAllowedX = t * 2;
      double maxAllowedX = width - t * 2;
      for (var z in zones) {
        if (!overlapsSelectedSpan(z)) continue;
        for (final divX in matchingDividers) {
          if ((z.boundary.right - divX).abs() <= effectiveThickness + 8.0) {
            if (z.boundary.left + minimumZoneSpanMm(z, isWidth: true) > minAllowedX) {
              minAllowedX = z.boundary.left + minimumZoneSpanMm(z, isWidth: true);
            }
          }
          if ((z.boundary.left - divX).abs() <= effectiveThickness + 8.0) {
            if (z.boundary.right - minimumZoneSpanMm(z, isWidth: true) < maxAllowedX) {
              maxAllowedX = z.boundary.right - minimumZoneSpanMm(z, isWidth: true);
            }
          }
        }
      }
      double newPos = pos + deltaPixels;
      // No legal position: the neighbouring zones are already at their minimum.
      if (minAllowedX + sep > maxAllowedX - sep) return;
      if (newPos - sep < minAllowedX) newPos = minAllowedX + sep;
      if (newPos + sep > maxAllowedX) newPos = maxAllowedX - sep;
      double actualDelta = newPos - pos;
      if (actualDelta == 0) return;

      for (int i = 0; i < zones.length; i++) {
        var z = zones[i];
        if (!overlapsSelectedSpan(z)) continue;
        for (final divX in matchingDividers) {
          if (z.boundary.right <= divX + 4.0 &&
              (divX - z.boundary.right).abs() <= effectiveThickness + 8.0) {
            zones[i] = z.copyWith(
              boundary: Rect.fromLTRB(
                z.boundary.left,
                z.boundary.top,
                z.boundary.right + actualDelta,
                z.boundary.bottom,
              ),
            );
            z = zones[i];
          } else if (z.boundary.left >= divX - 4.0 &&
              (z.boundary.left - divX).abs() <= effectiveThickness + 8.0) {
            zones[i] = z.copyWith(
              boundary: Rect.fromLTRB(
                z.boundary.left + actualDelta,
                z.boundary.top,
                z.boundary.right,
                z.boundary.bottom,
              ),
            );
            z = zones[i];
          }
        }
      }
      for (final oldDiv in matchingDividers) {
        _moveMullionMetadata(
          _mullionKey(isH, oldDiv),
          _mullionKey(isH, oldDiv + actualDelta),
        );
      }
      selection = SelectionInfo(
        type: SelectionType.mullion,
        isHorizontalMullion: isH,
        mullionPosition: newPos,
        mullionStart: selection.mullionStart,
        mullionEnd: selection.mullionEnd,
      );
      _snapNearbyParallelMullions(isHorizontal: false, targetPos: newPos);
    }
    _notifyModelListeners();
  }
}
