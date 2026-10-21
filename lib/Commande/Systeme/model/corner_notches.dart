part of '../model.dart';

/// Corner cuts (90° steps) of the frame outline.
///
/// A cut corner has a mullion in line with its step, so every zone stays a
/// rectangle and keeps all of its usual contents (glass, sash, sliding...).
/// The zones are the reference: [_syncCornerNotchesToZones] reads the steps
/// back from the zone edges after any other edit (a frame resize scales the
/// zones, and the steps follow them).
extension WindowModelCornerNotches on WindowModel {
  /// Why the drawing cannot take a corner cut, as a translation key, or null.
  String? get cornerNotchBlocker {
    if (getFrameRects().length != 1) return 'notch_single_frame_only';
    if (hasShutter || isShutterOnly || isCaissonTunnel) {
      return 'notch_no_shutter';
    }
    if (hasShapedOutline) return 'notch_no_shaped_head';
    if (!hasBottomFrame || hasFramePlintheBottom) {
      return 'notch_needs_bottom_frame';
    }
    if (hasSideCovers) return 'notch_no_side_covers';
    if (zones.any((z) => z.slantedDividers.isNotEmpty)) {
      return 'notch_no_slanted_mullion';
    }
    return null;
  }

  // ---- Corner space ------------------------------------------------------
  // Every corner is handled as the top-left one: a rect is mirrored so that
  // the corner of [c] comes to (0, 0).

  Rect _toCornerSpace(NotchCorner c, Rect r) {
    final mx = !CornerNotches.isLeft(c);
    final my = !CornerNotches.isTop(c);
    return Rect.fromLTRB(
      mx ? width - r.right : r.left,
      my ? height - r.bottom : r.top,
      mx ? width - r.left : r.right,
      my ? height - r.top : r.bottom,
    );
  }

  Rect _fromCornerSpace(NotchCorner c, Rect r) => _toCornerSpace(c, r);

  static bool _near(double a, double b) => (a - b).abs() < 1.0;

  /// Moves the zone edges that follow the step of [c] from [from] to [to].
  void _moveZonesWithNotch(NotchCorner c, CornerNotch from, CornerNotch to) {
    if (!from.isCut) return;
    final t = profileThickness;
    final gap = maximumMullionThickness + 12.0;
    final removal = !to.isCut;
    final x0 = from.width + t, y0 = from.height + t;
    final x1 = removal ? t : to.width + t;
    final y1 = removal ? t : to.height + t;
    for (final zone in zones) {
      final r = _toCornerSpace(c, zone.boundary);
      var left = r.left, top = r.top, right = r.right, bottom = r.bottom;
      if (_near(top, y0) && right <= x0 + 1) {
        // Under the cut: its top is the step.
        top = y1;
        if (!removal && right > x0 - gap) right += x1 - x0;
      } else if (_near(left, x0) && bottom <= y0 + 1) {
        // Beside the cut: its side is the step.
        left = x1;
        if (!removal && bottom > y0 - gap) bottom += y1 - y0;
      } else if (!removal && _near(left, x0) && _near(top, t)) {
        // Beyond the mullion in line with a vertical step.
        left = x1;
      } else if (!removal && _near(top, y0) && _near(left, t)) {
        // Below the transom in line with a horizontal step.
        top = y1;
      } else {
        continue;
      }
      zone.boundary = _fromCornerSpace(
        c,
        Rect.fromLTRB(left, top, right, bottom),
      );
    }
  }

  WindowZone _splitPart(WindowZone zone, Rect boundary) => WindowZone(
    id: UniqueKey().toString(),
    boundary: boundary,
    sashColor: zone.sashColor,
    content: zone.content,
    glass: zone.glass.clone(),
    openDirection: zone.openDirection,
    sashThickness: zone.sashThickness,
    isSash105: zone.isSash105,
    lockType: zone.lockType,
    hasSashPlintheBottom: zone.hasSashPlintheBottom,
  );

  /// Splits [zone] by a mullion in line with the step of [c], whose inner
  /// faces are at [x1] / [y1] in corner space. Returns false when the zone
  /// is too small on both axes.
  bool _splitZoneAtNotch(
    NotchCorner c,
    WindowZone zone,
    double x1,
    double y1,
    bool preferHorizontal,
  ) {
    const minSize = 50.0;
    final m = mullionThickness;
    final r = _toCornerSpace(c, zone.boundary);
    final canV = x1 - m - r.left >= minSize && r.right - x1 >= minSize;
    final canH = y1 - m - r.top >= minSize && r.bottom - y1 >= minSize;
    if (!canV && !canH) return false;
    final horizontal = canH && (preferHorizontal || !canV);
    final Rect a, b;
    if (horizontal) {
      a = Rect.fromLTRB(r.left, r.top, r.right, y1 - m);
      b = Rect.fromLTRB(r.left, y1, r.right, r.bottom);
    } else {
      a = Rect.fromLTRB(r.left, r.top, x1 - m, r.bottom);
      b = Rect.fromLTRB(x1, r.top, r.right, r.bottom);
    }
    final ra = _fromCornerSpace(c, a), rb = _fromCornerSpace(c, b);
    // Real space order: left/top part first, as the split commands do.
    final aFirst = horizontal ? ra.top < rb.top : ra.left < rb.left;
    final first = aFirst ? ra : rb, second = aFirst ? rb : ra;
    if (horizontal) {
      primaryMullionAxis ??= 'h';
      recordMullionCreation(true, first.bottom + m / 2);
    } else {
      primaryMullionAxis ??= 'v';
      recordMullionCreation(false, first.right + m / 2);
    }
    final index = zones.indexOf(zone);
    zones
      ..removeAt(index)
      ..insertAll(index, [_splitPart(zone, first), _splitPart(zone, second)]);
    return true;
  }

  /// Fits every zone outside the cut corners: a zone under or beside a cut
  /// meets its step, a zone across a cut is split in line with the step.
  bool _fitZonesToNotches() {
    final t = profileThickness;
    for (var pass = 0; pass < 32; pass++) {
      var changed = false;
      for (final c in NotchCorner.values) {
        final n = cornerNotches.of(c);
        if (!n.isCut) continue;
        final x1 = n.width + t, y1 = n.height + t;
        for (final zone in List<WindowZone>.of(zones)) {
          final r = _toCornerSpace(c, zone.boundary);
          if (r.left >= x1 - 0.5 || r.top >= y1 - 0.5) continue;
          if (r.right <= x1 + 0.5) {
            zone.boundary = _fromCornerSpace(
              c,
              Rect.fromLTRB(r.left, y1, r.right, r.bottom),
            );
          } else if (r.bottom <= y1 + 0.5) {
            zone.boundary = _fromCornerSpace(
              c,
              Rect.fromLTRB(x1, r.top, r.right, r.bottom),
            );
          } else if (!_splitZoneAtNotch(c, zone, x1, y1, n.height <= n.width)) {
            return false;
          }
          changed = true;
        }
      }
      if (!changed) return _zonesFitNotches();
    }
    return false;
  }

  bool _zonesFitNotches() {
    const minSize = 50.0;
    final t = profileThickness;
    for (final zone in zones) {
      if (zone.boundary.width < minSize || zone.boundary.height < minSize) {
        return false;
      }
      for (final c in NotchCorner.values) {
        final n = cornerNotches.of(c);
        if (!n.isCut) continue;
        final r = _toCornerSpace(c, zone.boundary);
        if (r.left < n.width + t - 0.5 && r.top < n.height + t - 0.5) {
          return false;
        }
      }
    }
    return true;
  }

  /// Cuts [corner] to [requested] (kept within [CornerNotches.clampNotch])
  /// as one undo step; a zero size removes the cut. Returns a translation key
  /// when the cut cannot be made, the drawing then stays unchanged.
  String? setCornerNotch(
    NotchCorner corner,
    CornerNotch requested, {
    bool saveHistory = true,
  }) {
    final old = cornerNotches.of(corner);
    if (requested.isCut) {
      final blocker = cornerNotchBlocker;
      if (blocker != null) return blocker;
    }
    final next = requested.isCut
        ? cornerNotches.clampNotch(
            corner,
            requested.width,
            requested.height,
            width,
            height,
          )
        : CornerNotch.none;
    if (next == old) return null;

    final savedZones = zones.map((z) => z.clone()).toList();
    final savedNotches = cornerNotches;
    final savedAxis = primaryMullionAxis;
    final savedOrder = Map<String, int>.of(mullionCreationOrder);
    final savedCounter = mullionStepCounter;
    if (saveHistory) _saveSnapshot();
    _suspendNotchSync = true;
    try {
      _moveZonesWithNotch(corner, old, next);
      cornerNotches = cornerNotches.withCorner(corner, next);
      if (!_fitZonesToNotches()) {
        zones = savedZones;
        cornerNotches = savedNotches;
        primaryMullionAxis = savedAxis;
        mullionCreationOrder = savedOrder;
        mullionStepCounter = savedCounter;
        if (saveHistory && _history.isNotEmpty) _history.removeLast();
        return 'notch_zones_conflict';
      }
    } finally {
      _suspendNotchSync = false;
    }
    selection = SelectionInfo(type: SelectionType.frame, zoneId: 'frame:0');
    notifyListeners();
    return null;
  }

  /// Reads the steps back from the zones: under a cut, the first zone along
  /// each side starts at the step. A step whose zones were merged or moved
  /// back to the frame removes the cut.
  void _syncCornerNotchesToZones() {
    if (_suspendNotchSync || zones.isEmpty) return;
    final t = profileThickness;
    var next = cornerNotches;
    for (final c in NotchCorner.values) {
      if (!cornerNotches.of(c).isCut) continue;
      final rects = zones.map((z) => _toCornerSpace(c, z.boundary)).toList();
      final alongSide = rects.where((r) => _near(r.left, t)).map((r) => r.top);
      final alongHead = rects.where((r) => _near(r.top, t)).map((r) => r.left);
      final cutHeight = alongSide.isEmpty
          ? 0.0
          : alongSide.reduce(math.min) - t;
      final cutWidth = alongHead.isEmpty
          ? 0.0
          : alongHead.reduce(math.min) - t;
      final notch = cutWidth > 0.5 && cutHeight > 0.5
          ? CornerNotch(width: cutWidth, height: cutHeight)
          : CornerNotch.none;
      if (notch != cornerNotches.of(c)) next = next.withCorner(c, notch);
    }
    cornerNotches = next;
  }
}
