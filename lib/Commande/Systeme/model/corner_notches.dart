part of '../model.dart';

/// Corner cuts (90° steps) of the frame outline.
///
/// A cut changes the outline only: no mullion is added and the zones keep
/// their full rectangles, whose contents are drawn clipped to the cut
/// outline. Quantities and costs count the window as a full rectangle.
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

  /// A new frame thickness (another series) moves the inner faces of every
  /// step with it, for drawings whose zones were split along their steps.
  /// The cut sizes stay the same.
  void _moveStepsWithThickness(double oldThickness) {
    final t = profileThickness;
    final gap = maximumMullionThickness + 12.0;
    for (final c in NotchCorner.values) {
      final n = cornerNotches.of(c);
      if (!n.isCut) continue;
      final x0 = n.width + oldThickness, y0 = n.height + oldThickness;
      final x1 = n.width + t, y1 = n.height + t;
      for (final zone in zones) {
        final r = _toCornerSpace(c, zone.boundary);
        var left = r.left, top = r.top, right = r.right, bottom = r.bottom;
        if (_near(top, y0) && right <= x0 + 1) {
          // Under the cut: its top is the step.
          top = y1;
          if (right > x0 - gap) right += x1 - x0;
        } else if (_near(left, x0) && bottom <= y0 + 1) {
          // Beside the cut: its side is the step.
          left = x1;
          if (bottom > y0 - gap) bottom += y1 - y0;
        } else if (_near(left, x0) && _near(top, t)) {
          // Beyond the mullion in line with a vertical step.
          left = x1;
        } else if (_near(top, y0) && _near(left, t)) {
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

    if (saveHistory) _saveSnapshot();
    cornerNotches = cornerNotches.withCorner(corner, next);
    selection = SelectionInfo(type: SelectionType.frame, zoneId: 'frame:0');
    notifyListeners();
    return null;
  }

  /// Keeps every cut inside the frame after a resize: the cut sizes stay,
  /// shortened only when the frame became too small for them.
  void _fitCornerNotchesToFrame() {
    var next = cornerNotches;
    for (final c in NotchCorner.values) {
      final n = next.of(c);
      if (!n.isCut) continue;
      next = next.withCorner(
        c,
        next.clampNotch(c, n.width, n.height, width, height),
      );
    }
    cornerNotches = next;
  }
}
