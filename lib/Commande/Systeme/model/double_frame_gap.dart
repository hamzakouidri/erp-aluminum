part of '../model.dart';

/// Keeps the clear gap around a Cadre double divider equal to its real
/// visible width: two frame profiles back-to-back. Without this the two
/// neighbouring zones kept the ordinary mullion gap while the painter drew
/// two frame bars, so the drawing, the dimensions and the cut lists all
/// used one mullion where the workshop fits two frames.
extension WindowModelDoubleFrameGap on WindowModel {
  /// Real visible width of the divider at [position]: twice the frame
  /// profile for a Cadre double, the ordinary mullion otherwise.
  double doubleFrameAwareMullionGapAt(bool isHorizontal, double position) {
    if (!isDoubleFrameMullionAt(isHorizontal, position)) {
      return mullionThickness;
    }
    final section = effectiveMullionSectionAt(isHorizontal, position);
    for (final field in const ['visible_width', 'thickness']) {
      final value = section?[field];
      final width = value is num
          ? value.toDouble()
          : double.tryParse(value?.toString() ?? '');
      if (width != null && width > 0) return width * 2.0;
    }
    return profileThickness * 2.0;
  }

  /// Whether two facing zone edges are separated by a divider: the ordinary
  /// mullion gap, or the wider gap of a Cadre double centred between them.
  bool isMullionGapBetween(
    bool isHorizontal,
    double firstEdge,
    double secondEdge, {
    double slop = 2.0,
  }) {
    final gap = (secondEdge - firstEdge).abs();
    if (gap <= mullionThickness + slop) return true;
    final centre = (firstEdge + secondEdge) / 2.0;
    if (!isDoubleFrameMullionAt(isHorizontal, centre)) return false;
    return gap <= doubleFrameAwareMullionGapAt(isHorizontal, centre) + slop;
  }

  /// Re-spaces the zones on both sides of the divider at [position] so the
  /// gap between them is [doubleFrameAwareMullionGapAt]. The divider keeps
  /// its centre and each side gives up half of the difference, so the outer
  /// size of the window does not change. Nothing moves when a zone would
  /// fall below its minimum opening. [previousGap] is the widest divider
  /// before the change, so a gap that is narrowing is still found.
  void _respaceZonesAroundMullion(
    bool isHorizontal,
    double position, {
    required double previousGap,
  }) {
    final targetGap = doubleFrameAwareMullionGapAt(isHorizontal, position);
    final half = targetGap / 2.0;
    final tolerance =
        math.max(math.max(maximumMullionThickness, previousGap), targetGap) +
        8.0;

    final newBoundaries = <int, Rect>{};
    for (var i = 0; i < zones.length; i++) {
      for (var j = 0; j < zones.length; j++) {
        if (i == j) continue;
        // Detect on the original layout: a zone can border several zones
        // across the same divider (a T junction).
        final before = zones[i].boundary;
        final after = zones[j].boundary;
        final beforeEdge = isHorizontal ? before.bottom : before.right;
        final afterEdge = isHorizontal ? after.top : after.left;
        final gap = afterEdge - beforeEdge;
        if (gap < -1.0 || gap > tolerance) continue;
        final centre = (beforeEdge + afterEdge) / 2.0;
        if ((centre - position).abs() > 6.0) continue;
        final overlap = isHorizontal
            ? math.min(before.right, after.right) -
                  math.max(before.left, after.left)
            : math.min(before.bottom, after.bottom) -
                  math.max(before.top, after.top);
        if (overlap <= 2.0) continue;

        final first = newBoundaries[i] ?? before;
        final second = newBoundaries[j] ?? after;
        newBoundaries[i] = isHorizontal
            ? Rect.fromLTRB(first.left, first.top, first.right, centre - half)
            : Rect.fromLTRB(first.left, first.top, centre - half, first.bottom);
        newBoundaries[j] = isHorizontal
            ? Rect.fromLTRB(
                second.left,
                centre + half,
                second.right,
                second.bottom,
              )
            : Rect.fromLTRB(
                centre + half,
                second.top,
                second.right,
                second.bottom,
              );
      }
    }

    for (final entry in newBoundaries.entries) {
      final zone = zones[entry.key];
      final span = isHorizontal ? entry.value.height : entry.value.width;
      final currentSpan = isHorizontal
          ? zone.boundary.height
          : zone.boundary.width;
      if (span < currentSpan &&
          span < minimumZoneSpanMm(zone, isWidth: !isHorizontal)) {
        return;
      }
    }
    for (final entry in newBoundaries.entries) {
      zones[entry.key] = zones[entry.key].copyWith(boundary: entry.value);
    }
  }
}
