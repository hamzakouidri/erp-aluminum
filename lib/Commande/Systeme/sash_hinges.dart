import 'dart:math' as math;
import 'dart:ui' show Offset;

/// Hinge positions the user placed by hand on one sash leaf.
///
/// [positions] are hinge centres in mm from the start of the hinged edge,
/// ascending: from the bottom of the sash for side hinges, from the inside
/// left for top/bottom hinges ([horizontal]). [referenceLength] is the edge
/// length they were placed on, so they can follow a later resize.
class SashHingeLayout {
  final List<double> positions;
  final double referenceLength;
  final bool horizontal;

  SashHingeLayout({
    required List<double> positions,
    required this.referenceLength,
    this.horizontal = false,
  }) : positions = List<double>.unmodifiable(
         List<double>.of(positions)..sort(),
       );

  Map<String, dynamic> toMap() => {
    'positions': positions,
    'referenceLength': referenceLength,
    if (horizontal) 'horizontal': true,
  };

  /// Returns null for malformed data; the leaf then falls back to the
  /// automatic layout.
  static SashHingeLayout? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final list = raw['positions'];
    final reference = (raw['referenceLength'] as num?)?.toDouble();
    if (list is! List || reference == null || reference <= 0) return null;
    final positions = <double>[];
    for (final p in list) {
      if (p is! num || !p.isFinite) return null;
      positions.add(p.toDouble());
    }
    if (positions.length < SashHingeRules.minCount) return null;
    return SashHingeLayout(
      positions: positions,
      referenceLength: reference,
      horizontal: raw['horizontal'] == true,
    );
  }
}

/// Workshop rules for placing hinges along a sash edge. All values are hinge
/// centres in mm from the start of the edge.
class SashHingeRules {
  /// Smallest distance from a hinge centre to either end of the sash.
  static const double minEndDistanceMm = 80.0;

  /// Smallest distance between two neighbouring hinge centres.
  static const double minSpacingMm = 150.0;

  /// End inset of the automatic layout.
  static const double autoEndInsetMm = 100.0;

  /// End inset of the two hinges of a full OB kit.
  static const double obEndInsetMm = 44.0;

  static const int minCount = 2;

  static double snap(double mm) => (mm / 10.0).roundToDouble() * 10.0;

  /// How many hinges fit on an edge of [length] with the minimum distances.
  static int maxCountFor(double length) {
    final usable = length - 2 * minEndDistanceMm;
    if (usable < 0) return minCount;
    return math.max(minCount, (usable / minSpacingMm).floor() + 1);
  }

  /// The automatic layout: [count] hinges evenly spread between [endInset]
  /// from each end. [middleOffset] is the legacy drag of the second hinge
  /// counted from the head (mm towards the bottom), kept for old orders.
  static List<double> automatic(
    double length,
    int count, {
    double endInset = autoEndInsetMm,
    double middleOffset = 0.0,
  }) {
    final n = math.max(minCount, count);
    final inset = math.min(endInset, length / 2);
    final step = (length - 2 * inset) / (n - 1);
    // Offsets from the head, as the hinges were always laid out.
    final fromHead = <double>[for (var i = 0; i < n; i++) inset + step * i];
    if (n >= 3 && middleOffset != 0.0) {
      final p1 = fromHead[1] + middleOffset;
      final pLast = fromHead[n - 1];
      fromHead[1] = p1;
      for (var i = 2; i < n - 1; i++) {
        fromHead[i] = p1 + (pLast - p1) * ((i - 1) / (n - 2));
      }
    }
    return [for (final d in fromHead.reversed) length - d];
  }

  /// Even spread used when manual positions cannot fit a shorter edge.
  static List<double> evenlySpread(double length, int count) {
    final inset = math.min(minEndDistanceMm, length / 2);
    final n = math.max(minCount, count);
    final step = (length - 2 * inset) / (n - 1);
    return [for (var i = 0; i < n; i++) inset + step * i];
  }

  /// Positions of [layout] on an edge that is now [length] long. The first
  /// and last hinge keep their distance from their own end; the middle ones
  /// keep their proportion between them.
  static List<double> fitToLength(SashHingeLayout layout, double length) {
    final src = layout.positions;
    if ((layout.referenceLength - length).abs() < 0.5) {
      return List<double>.of(src);
    }
    var count = src.length;
    if (count > maxCountFor(length)) count = maxCountFor(length);
    if (count != src.length) return evenlySpread(length, count);

    final first = math.max(minEndDistanceMm, src.first);
    final last = math.max(
      first,
      length - math.max(minEndDistanceMm, layout.referenceLength - src.last),
    );
    final span = src.last - src.first;
    final result = <double>[
      for (final p in src)
        span <= 0 ? first : first + (p - src.first) * (last - first) / span,
    ];
    return isValid(result, length) ? result : evenlySpread(length, count);
  }

  static bool isValid(List<double> positions, double length) {
    if (positions.length < minCount) return false;
    if (positions.first < minEndDistanceMm - 0.5) return false;
    if (positions.last > length - minEndDistanceMm + 0.5) return false;
    for (var i = 1; i < positions.length; i++) {
      if (positions[i] - positions[i - 1] < minSpacingMm - 0.5) return false;
    }
    return true;
  }

  /// Clamps [target] for hinge [index] between the edge ends and its two
  /// neighbours, keeping the minimum distances.
  static double clampMove(
    List<double> positions,
    int index,
    double target,
    double length, {
    bool snapToGrid = true,
  }) {
    final low = index > 0
        ? positions[index - 1] + minSpacingMm
        : minEndDistanceMm;
    final high = index < positions.length - 1
        ? positions[index + 1] - minSpacingMm
        : length - minEndDistanceMm;
    if (high < low) return positions[index];
    var value = (snapToGrid ? snap(target) : target)
        .clamp(low, high)
        .toDouble();
    // Snapping can step just outside a limit that is not on the 10 mm grid.
    if (value < low) value = low;
    if (value > high) value = high;
    return value;
  }

  /// The span shown while hinge [index] is selected or dragged: from the
  /// hinge to its nearest neighbour, the next hinge or the end of the sash,
  /// whichever is closer. [from] is always the lower end, so the distance
  /// reads from the bottom upwards.
  static ({double from, double to}) nearestGap(
    List<double> positions,
    int index,
    double length,
  ) {
    final p = positions[index];
    final below = index > 0 ? positions[index - 1] : 0.0;
    final above = index < positions.length - 1
        ? positions[index + 1]
        : length;
    return p - below <= above - p
        ? (from: below, to: p)
        : (from: p, to: above);
  }

  /// Where a new hinge goes: as close as possible to [near] (or the middle of
  /// the largest gap when null) while respecting the minimum distances.
  /// Returns null when the edge has no room for another hinge.
  static double? insertionPoint(
    List<double> positions,
    double length, {
    double? near,
  }) {
    final bounds = <double>[
      minEndDistanceMm - minSpacingMm,
      ...positions,
      length - minEndDistanceMm + minSpacingMm,
    ];
    double? best;
    var bestScore = double.infinity;
    for (var i = 0; i < bounds.length - 1; i++) {
      final low = bounds[i] + minSpacingMm;
      final high = bounds[i + 1] - minSpacingMm;
      if (high < low) continue;
      final double candidate;
      final double score;
      if (near == null) {
        candidate = (low + high) / 2;
        score = -(high - low); // Prefer the largest gap.
      } else {
        candidate = near.clamp(low, high).toDouble();
        score = (candidate - near).abs();
      }
      if (score < bestScore) {
        bestScore = score;
        best = candidate;
      }
    }
    if (best == null) return null;
    final snapped = snap(best);
    final probe = [...positions, snapped]..sort();
    return isValid(probe, length) ? snapped : best;
  }
}

/// One hinged sash edge as the editor last painted it, so taps and drags hit
/// exactly what is on screen. Coordinates are model millimetres.
class SashHingeEdge {
  final String zoneId;
  final int leaf;

  /// Where position 0 lies (the bottom of a side edge, the inside-left end of
  /// a top/bottom edge) and the other end of the edge.
  final Offset start;
  final Offset end;
  final List<double> positions;
  final List<Offset> centers;
  final bool vertical;

  /// False for the leaf carrying a full OB kit, whose hinges are fixed.
  final bool editable;

  const SashHingeEdge({
    required this.zoneId,
    required this.leaf,
    required this.start,
    required this.end,
    required this.positions,
    required this.centers,
    required this.vertical,
    required this.editable,
  });

  double get length => (end - start).distance;

  /// Position along the edge (mm from [start]) of the model point [p].
  double positionAt(Offset p) {
    final axis = end - start;
    final len = axis.distance;
    if (len <= 0) return 0;
    final d = p - start;
    return (d.dx * axis.dx + d.dy * axis.dy) / len;
  }

  Offset pointAt(double position) {
    final len = length;
    if (len <= 0) return start;
    return start + (end - start) * (position / len);
  }
}

/// The hinge picked in the editor.
class SelectedHinge {
  final String zoneId;
  final int leaf;
  final int index;

  const SelectedHinge(this.zoneId, this.leaf, this.index);

  bool matches(SashHingeEdge edge) =>
      edge.zoneId == zoneId && edge.leaf == leaf;
}
