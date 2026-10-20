import 'dart:math' as math;
import 'dart:ui';

/// Side of a zone's clear rectangle that a slanted division ends on.
enum ZoneEdge { top, right, bottom, left }

/// One end of a slanted division: a point on [edge] at [ratio] along it
/// (top/bottom run left to right, left/right run top to bottom). Ratios keep
/// the division in place when the zone is resized.
class SlantedDividerAnchor {
  final ZoneEdge edge;
  final double ratio;

  const SlantedDividerAnchor(this.edge, this.ratio);

  Offset pointOn(Rect r) {
    final t = ratio.clamp(0.0, 1.0);
    switch (edge) {
      case ZoneEdge.top:
        return Offset(r.left + r.width * t, r.top);
      case ZoneEdge.bottom:
        return Offset(r.left + r.width * t, r.bottom);
      case ZoneEdge.left:
        return Offset(r.left, r.top + r.height * t);
      case ZoneEdge.right:
        return Offset(r.right, r.top + r.height * t);
    }
  }

  /// Distance in mm from the edge's start corner (left or top).
  double distanceOn(Rect r) =>
      ratio *
      (edge == ZoneEdge.top || edge == ZoneEdge.bottom ? r.width : r.height);

  Map<String, dynamic> toMap() => {'edge': edge.name, 'ratio': ratio};

  static SlantedDividerAnchor? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final edge = ZoneEdge.values
        .where((e) => e.name == raw['edge']?.toString())
        .firstOrNull;
    final ratio = raw['ratio'];
    if (edge == null || ratio is! num) return null;
    return SlantedDividerAnchor(edge, ratio.toDouble().clamp(0.0, 1.0));
  }
}

/// A straight mullion crossing one fixed zone at an angle. It is an inner
/// division of the zone (like innerH/innerV), so the rectangular frame and
/// mullion grid of the drawing is untouched. The profile is chosen by its
/// exact catalogue [profileCode]; null means the drawing's mullion profile.
class SlantedDivider {
  final String id;
  final SlantedDividerAnchor start;
  final SlantedDividerAnchor end;
  final String? profileCode;

  /// Where the division was drawn, as ratios of the zone's clear rectangle.
  /// It then only crosses the part of the earlier divisions holding this
  /// point and stops on them (the first division stays whole). Without it
  /// the division runs across the whole zone, as older drawings did.
  final Offset? seed;

  const SlantedDivider({
    required this.id,
    required this.start,
    required this.end,
    this.profileCode,
    this.seed,
  });

  SlantedDivider copyWith({
    SlantedDividerAnchor? start,
    SlantedDividerAnchor? end,
    String? profileCode,
  }) => SlantedDivider(
    id: id,
    start: start ?? this.start,
    end: end ?? this.end,
    profileCode: profileCode ?? this.profileCode,
    seed: seed,
  );

  Offset? seedPoint(Rect r) => seed == null
      ? null
      : Offset(r.left + r.width * seed!.dx, r.top + r.height * seed!.dy);

  Map<String, dynamic> toMap() => {
    'id': id,
    'start': start.toMap(),
    'end': end.toMap(),
    if (profileCode != null) 'profileCode': profileCode,
    if (seed != null) 'seed': {'x': seed!.dx, 'y': seed!.dy},
  };

  static SlantedDivider? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final start = SlantedDividerAnchor.fromMap(raw['start']);
    final end = SlantedDividerAnchor.fromMap(raw['end']);
    final id = raw['id']?.toString();
    if (start == null || end == null || id == null || id.isEmpty) return null;
    final code = raw['profileCode']?.toString().trim();
    final seed = raw['seed'];
    return SlantedDivider(
      id: id,
      start: start,
      end: end,
      profileCode: code == null || code.isEmpty ? null : code,
      seed: seed is Map && seed['x'] is num && seed['y'] is num
          ? Offset(
              (seed['x'] as num).toDouble().clamp(0.0, 1.0),
              (seed['y'] as num).toDouble().clamp(0.0, 1.0),
            )
          : null,
    );
  }
}

/// Why a slanted division cannot be built; each value is a translation key.
class SlantedDivisionError {
  static const sameEdge = 'يجب أن يبدأ التقسيم المائل وينتهي على ضلعين مختلفين';
  static const tooCloseToCorner =
      'طرف التقسيم المائل قريب جداً من زاوية الإطار';
  static const angleTooSharp =
      'زاوية التقسيم المائل مع الإطار أصغر من الحد الأدنى {min}°';
  static const crossesDivider =
      'التقسيمات المائلة متلاصقة أو تتقاطع بزاوية أصغر من الحد الأدنى';
  static const cellTooSmall =
      'جزء من الزجاج أضيق من {min} مم بعد التقسيم المائل';
  static const notFixedZone = 'التقسيم المائل متاح في الأجزاء الثابتة فقط';
  static const mixedDivisions =
      'احذف التقسيمات المستقيمة الداخلية قبل إضافة تقسيم مائل';
  static const underShapedHead =
      'التقسيم المائل غير متاح تحت رأس مائل أو مقوس حالياً';
}

/// Geometry of slanted divisions inside one zone's clear rectangle. All
/// values are in mm in drawing coordinates; every cell is a convex polygon
/// (a rectangle cut by straight lines).
class SlantedDivisionGeometry {
  /// Sharpest allowed angle between a division and the edge it meets.
  static const double minimumAngleDeg = 20.0;

  final Rect clear;
  final List<SlantedDivider> dividers;

  /// Visible width of the division profile.
  final double profileWidth;

  const SlantedDivisionGeometry({
    required this.clear,
    required this.dividers,
    required this.profileWidth,
  });

  /// The clear cells after the divisions, in drawing order. A division with
  /// a [SlantedDivider.seed] splits only the cell holding that point (its
  /// region) and stops on the earlier divisions around it; one without
  /// splits every cell it crosses.
  ({List<List<Offset>> cells, Map<String, List<Offset>> regions}) _layout() {
    var cells = <List<Offset>>[_rectPolygon(clear)];
    final regions = <String, List<Offset>>{};
    for (final d in dividers) {
      final a = d.start.pointOn(clear);
      final b = d.end.pointOn(clear);
      final n = _unitNormal(a, b) * (profileWidth / 2);
      List<List<Offset>> split(List<Offset> p) => [
        for (final part in [
          clipHalfPlane(p, a - n, b - n, keepLeft: false),
          clipHalfPlane(p, a + n, b + n, keepLeft: true),
        ])
          if (polygonArea(part) > 1.0) part,
      ];
      final seed = d.seedPoint(clear);
      if (seed == null) {
        cells = [for (final p in cells) ...split(p)];
        continue;
      }
      final index = _cellIndexAt(cells, seed);
      regions[d.id] = cells[index];
      cells = [
        for (var i = 0; i < cells.length; i++)
          if (i == index) ...split(cells[i]) else cells[i],
      ];
    }
    return (cells: cells, regions: regions);
  }

  /// The cell holding [p], or the one whose centre is closest.
  static int _cellIndexAt(List<List<Offset>> cells, Offset p) {
    var best = 0;
    var bestGap = double.infinity;
    for (var i = 0; i < cells.length; i++) {
      if (_convexContains(cells[i], p)) return i;
      final gap = (centroid(cells[i]) - p).distance;
      if (gap < bestGap) {
        best = i;
        bestGap = gap;
      }
    }
    return best;
  }

  /// Centre line of [d]: from side to side of the zone, or, for a division
  /// confined to its region, between what it stops on.
  (Offset, Offset) centreLine(SlantedDivider d) {
    final a = d.start.pointOn(clear);
    final b = d.end.pointOn(clear);
    final region = d.seed == null ? null : _layout().regions[d.id];
    if (region == null) return (a, b);
    return _clipLineToConvex(a, b, region) ?? (a, b);
  }

  /// The division profile as a polygon: the band of [profileWidth] around
  /// its centre line, cut by the zone edges (direct angle cut on the face)
  /// and, for a confined division, by the earlier divisions it meets.
  List<Offset> band(SlantedDivider d) {
    final a = d.start.pointOn(clear);
    final b = d.end.pointOn(clear);
    final n = _unitNormal(a, b) * (profileWidth / 2);
    var poly = _rectPolygon(clear);
    poly = clipHalfPlane(poly, a + n, b + n, keepLeft: false);
    poly = clipHalfPlane(poly, a - n, b - n, keepLeft: true);
    final region = d.seed == null ? null : _layout().regions[d.id];
    return region == null ? poly : _clipToConvex(poly, region);
  }

  /// What one end of [d] stops on: a side of the zone ([edge]) or, for a
  /// confined division, the earlier division it meets ([divider]).
  ({ZoneEdge? edge, SlantedDivider? divider}) endMeets(
    SlantedDivider d, {
    required bool atStart,
  }) {
    if (d.seed == null) {
      return (edge: atStart ? d.start.edge : d.end.edge, divider: null);
    }
    final (a, b) = centreLine(d);
    final p = atStart ? a : b;
    final edgeGaps = <ZoneEdge, double>{
      ZoneEdge.top: (p.dy - clear.top).abs(),
      ZoneEdge.bottom: (p.dy - clear.bottom).abs(),
      ZoneEdge.left: (p.dx - clear.left).abs(),
      ZoneEdge.right: (p.dx - clear.right).abs(),
    };
    final nearestEdge = edgeGaps.entries.reduce(
      (x, y) => x.value <= y.value ? x : y,
    );
    if (nearestEdge.value <= 1.0) return (edge: nearestEdge.key, divider: null);
    SlantedDivider? best;
    var bestGap = double.infinity;
    for (final other in dividers) {
      if (other.id == d.id) break;
      final gap = _pointLineDistance(
        p,
        other.start.pointOn(clear),
        other.end.pointOn(clear),
      );
      if (gap < bestGap) {
        best = other;
        bestGap = gap;
      }
    }
    return best == null
        ? (edge: nearestEdge.key, divider: null)
        : (edge: null, divider: best);
  }

  /// Clear glass cells left between the divisions (profile bands removed),
  /// ordered top to bottom, then left to right, so their keys are stable.
  List<List<Offset>> cells() {
    final polys = _layout().cells;
    polys.sort((p, q) {
      final cp = centroid(p);
      final cq = centroid(q);
      final dy = cp.dy - cq.dy;
      if (dy.abs() > 1.0) return dy.sign.toInt();
      return (cp.dx - cq.dx).sign.toInt();
    });
    return polys;
  }

  /// Angle (degrees, 0..90) between the division and the edge at [atStart].
  /// A confined division gives the angle with the division it stops on.
  double angleWithEdgeDeg(SlantedDivider d, {required bool atStart}) {
    final meets = endMeets(d, atStart: atStart);
    if (meets.divider != null) return crossingAngleDeg(d, meets.divider!);
    final edge = meets.edge!;
    final dir = d.end.pointOn(clear) - d.start.pointOn(clear);
    final horizontal = edge == ZoneEdge.top || edge == ZoneEdge.bottom;
    final along = horizontal ? dir.dx.abs() : dir.dy.abs();
    final across = horizontal ? dir.dy.abs() : dir.dx.abs();
    return math.atan2(across, along) * 180 / math.pi;
  }

  /// Acute angle (degrees, 0..90) between two divisions.
  double crossingAngleDeg(SlantedDivider a, SlantedDivider b) {
    final u = a.end.pointOn(clear) - a.start.pointOn(clear);
    final v = b.end.pointOn(clear) - b.start.pointOn(clear);
    final cos =
        (u.dx * v.dx + u.dy * v.dy).abs() / (u.distance * v.distance + 1e-9);
    return math.acos(cos.clamp(0.0, 1.0)) * 180 / math.pi;
  }

  /// The bars of [d] as cut in the workshop. The first divisions run
  /// through; a later one that crosses an earlier one is cut into two bars
  /// at the crossing. Each bar: its length at the long point and its two
  /// cut angles (the angle shown on the drawing, halved, as at the frame).
  List<({double lengthMm, double startAngleDeg, double endAngleDeg})> cutPieces(
    SlantedDivider d,
  ) {
    // A confined division is one bar between what it stops on.
    if (d.seed != null) {
      return [
        (
          lengthMm: cutLengthMm(d),
          startAngleDeg: cutAngleDeg(d, atStart: true),
          endAngleDeg: cutAngleDeg(d, atStart: false),
        ),
      ];
    }
    final index = dividers.indexWhere((other) => other.id == d.id);
    final (a, b) = centreLine(d);
    final dir = b - a;
    final len2 = dir.dx * dir.dx + dir.dy * dir.dy;
    // Earlier divisions crossing this one, ordered along it.
    final crossings = <({double t, SlantedDivider other})>[];
    for (var j = 0; j < index && j < dividers.length; j++) {
      final other = dividers[j];
      final (c, e) = centreLine(other);
      if (!_segmentsIntersect(a, b, c, e)) continue;
      final hit = _lineIntersection(a, b, c, e);
      if (hit == null || len2 < 1e-9) continue;
      final t = ((hit - a).dx * dir.dx + (hit - a).dy * dir.dy) / len2;
      crossings.add((t: t, other: other));
    }
    crossings.sort((x, y) => x.t.compareTo(y.t));
    var pieces = <List<Offset>>[band(d)];
    for (final crossing in crossings) {
      final (c, e) = centreLine(crossing.other);
      final n = _unitNormal(c, e) * (profileWidth / 2);
      final next = <List<Offset>>[];
      for (final p in pieces) {
        final left = clipHalfPlane(p, c - n, e - n, keepLeft: false);
        final right = clipHalfPlane(p, c + n, e + n, keepLeft: true);
        if (polygonArea(left) > 1.0) next.add(left);
        if (polygonArea(right) > 1.0) next.add(right);
      }
      pieces = next;
    }
    double along(List<Offset> poly) {
      final m = centroid(poly) - a;
      return m.dx * dir.dx + m.dy * dir.dy;
    }

    pieces.sort((p, q) => along(p).compareTo(along(q)));
    double longest(List<Offset> poly) {
      var best = 0.0;
      for (var i = 0; i < poly.length; i++) {
        best = math.max(best, (poly[(i + 1) % poly.length] - poly[i]).distance);
      }
      return best;
    }

    return [
      for (var k = 0; k < pieces.length; k++)
        (
          lengthMm: longest(pieces[k]),
          startAngleDeg: k == 0 || k - 1 >= crossings.length
              ? cutAngleDeg(d, atStart: true)
              : crossingAngleDeg(d, crossings[k - 1].other) / 2,
          endAngleDeg: k == pieces.length - 1 || k >= crossings.length
              ? cutAngleDeg(d, atStart: false)
              : crossingAngleDeg(d, crossings[k].other) / 2,
        ),
    ];
  }

  static Offset? _lineIntersection(Offset p1, Offset p2, Offset q1, Offset q2) {
    final r = p2 - p1;
    final s = q2 - q1;
    final denom = r.dx * s.dy - r.dy * s.dx;
    if (denom.abs() < 1e-9) return null;
    final t = ((q1 - p1).dx * s.dy - (q1 - p1).dy * s.dx) / denom;
    return p1 + r * t;
  }

  /// Workshop cut angle at one end: the angle shown on the drawing, halved.
  double cutAngleDeg(SlantedDivider d, {required bool atStart}) =>
      angleWithEdgeDeg(d, atStart: atStart) / 2;

  /// Length of the profile bar measured at its long point (the longest edge
  /// of the band), which is what is set on the saw.
  double cutLengthMm(SlantedDivider d) {
    final poly = band(d);
    var longest = 0.0;
    for (var i = 0; i < poly.length; i++) {
      final e = (poly[(i + 1) % poly.length] - poly[i]).distance;
      longest = math.max(longest, e);
    }
    return longest;
  }

  /// First rule this layout breaks, as a translation key, or null.
  String? validate({double minimumCellMm = 80.0}) {
    final cornerGap = profileWidth / 2 + 5.0;
    for (final d in dividers) {
      if (d.start.edge == d.end.edge) return SlantedDivisionError.sameEdge;
      if (d.seed != null) {
        // A confined division: its own ends, on a side of the zone away
        // from the corners or on an earlier division.
        final region = _layout().regions[d.id];
        final segment = region == null
            ? null
            : _clipLineToConvex(
                d.start.pointOn(clear),
                d.end.pointOn(clear),
                region,
              );
        if (segment == null) return SlantedDivisionError.crossesDivider;
        for (final atStart in [true, false]) {
          final edge = endMeets(d, atStart: atStart).edge;
          if (edge == null) continue;
          final p = atStart ? segment.$1 : segment.$2;
          final horizontal = edge == ZoneEdge.top || edge == ZoneEdge.bottom;
          final along = horizontal ? p.dx - clear.left : p.dy - clear.top;
          final length = horizontal ? clear.width : clear.height;
          if (along < cornerGap || length - along < cornerGap) {
            return SlantedDivisionError.tooCloseToCorner;
          }
        }
        if (angleWithEdgeDeg(d, atStart: true) < minimumAngleDeg ||
            angleWithEdgeDeg(d, atStart: false) < minimumAngleDeg) {
          return SlantedDivisionError.angleTooSharp;
        }
        continue;
      }
      for (final anchor in [d.start, d.end]) {
        final length =
            anchor.edge == ZoneEdge.top || anchor.edge == ZoneEdge.bottom
            ? clear.width
            : clear.height;
        final along = anchor.distanceOn(clear);
        if (along < cornerGap || length - along < cornerGap) {
          return SlantedDivisionError.tooCloseToCorner;
        }
      }
      if (angleWithEdgeDeg(d, atStart: true) < minimumAngleDeg ||
          angleWithEdgeDeg(d, atStart: false) < minimumAngleDeg) {
        return SlantedDivisionError.angleTooSharp;
      }
    }
    for (var i = 0; i < dividers.length; i++) {
      for (var j = i + 1; j < dividers.length; j++) {
        // A confined division stops on the earlier ones (checked above);
        // the glass width rule below keeps it away from the others.
        if (dividers[i].seed != null || dividers[j].seed != null) continue;
        final (a1, b1) = centreLine(dividers[i]);
        final (a2, b2) = centreLine(dividers[j]);
        // Divisions may cross (the later one is cut at the crossing), but
        // not at a sharp angle, and never run side by side.
        if (_segmentsIntersect(a1, b1, a2, b2)) {
          if (crossingAngleDeg(dividers[i], dividers[j]) < minimumAngleDeg) {
            return SlantedDivisionError.crossesDivider;
          }
        } else if (_segmentsCloserThan(a1, b1, a2, b2, profileWidth + 1.0)) {
          return SlantedDivisionError.crossesDivider;
        }
      }
    }
    for (final cell in cells()) {
      if (minimumWidth(cell) < minimumCellMm) {
        return SlantedDivisionError.cellTooSmall;
      }
    }
    return null;
  }

  /// The two edge anchors of the straight line through [p] and [q] extended
  /// across [r] (a stroke drawn inside the zone), or null if it misses.
  static (SlantedDividerAnchor, SlantedDividerAnchor)? anchorsThrough(
    Rect r,
    Offset p,
    Offset q,
  ) {
    final d = q - p;
    if (d.distance < 1e-6) return null;
    final hits = <(double, SlantedDividerAnchor)>[];
    void tryEdge(ZoneEdge edge) {
      final horizontal = edge == ZoneEdge.top || edge == ZoneEdge.bottom;
      final fixed = switch (edge) {
        ZoneEdge.top => r.top,
        ZoneEdge.bottom => r.bottom,
        ZoneEdge.left => r.left,
        ZoneEdge.right => r.right,
      };
      final denom = horizontal ? d.dy : d.dx;
      if (denom.abs() < 1e-9) return;
      final t = (fixed - (horizontal ? p.dy : p.dx)) / denom;
      final point = p + d * t;
      final along = horizontal ? point.dx : point.dy;
      final start = horizontal ? r.left : r.top;
      final length = horizontal ? r.width : r.height;
      final ratio = (along - start) / length;
      if (ratio < -1e-6 || ratio > 1 + 1e-6) return;
      hits.add((t, SlantedDividerAnchor(edge, ratio.clamp(0.0, 1.0))));
    }

    for (final edge in ZoneEdge.values) {
      tryEdge(edge);
    }
    if (hits.length < 2) return null;
    hits.sort((a, b) => a.$1.compareTo(b.$1));
    return (hits.first.$2, hits.last.$2);
  }

  /// Anchor on the perimeter of [r] closest to [p]; the distance along the
  /// edge snaps to whole multiples of [snapMm] (magnetic dragging).
  static SlantedDividerAnchor nearestAnchor(
    Rect r,
    Offset p, {
    double snapMm = 10.0,
  }) {
    final candidates = <(double, ZoneEdge, double)>[
      ((p.dy - r.top).abs(), ZoneEdge.top, p.dx - r.left),
      ((p.dy - r.bottom).abs(), ZoneEdge.bottom, p.dx - r.left),
      ((p.dx - r.left).abs(), ZoneEdge.left, p.dy - r.top),
      ((p.dx - r.right).abs(), ZoneEdge.right, p.dy - r.top),
    ]..sort((a, b) => a.$1.compareTo(b.$1));
    final (_, edge, along) = candidates.first;
    final length = edge == ZoneEdge.top || edge == ZoneEdge.bottom
        ? r.width
        : r.height;
    final snapped = snapMm > 0
        ? (along / snapMm).roundToDouble() * snapMm
        : along;
    return SlantedDividerAnchor(edge, (snapped / length).clamp(0.0, 1.0));
  }

  /// Distance from [p] to the centre line of [d] (for hit tests).
  double distanceToDivider(SlantedDivider d, Offset p) {
    final (a, b) = centreLine(d);
    return _pointSegmentDistance(p, a, b);
  }

  // ---- polygon helpers (public for painter, BOM and tests) ----

  /// Keeps the part of a convex polygon on one side of the line a→b.
  static List<Offset> clipHalfPlane(
    List<Offset> poly,
    Offset a,
    Offset b, {
    required bool keepLeft,
  }) {
    double side(Offset p) {
      final s = (b.dx - a.dx) * (p.dy - a.dy) - (b.dy - a.dy) * (p.dx - a.dx);
      return keepLeft ? s : -s;
    }

    final out = <Offset>[];
    for (var i = 0; i < poly.length; i++) {
      final p = poly[i];
      final q = poly[(i + 1) % poly.length];
      final sp = side(p);
      final sq = side(q);
      if (sp >= 0) out.add(p);
      if ((sp >= 0) != (sq >= 0)) {
        final t = sp / (sp - sq);
        out.add(Offset.lerp(p, q, t)!);
      }
    }
    return out;
  }

  /// Moves every side of a convex polygon inwards by [d] (negative grows it);
  /// each new corner is where the two moved sides meet.
  static List<Offset> insetConvex(List<Offset> poly, double d) {
    final clean = <Offset>[];
    for (final p in poly) {
      if (clean.isEmpty || (p - clean.last).distance > 0.5) clean.add(p);
    }
    while (clean.length > 1 && (clean.first - clean.last).distance <= 0.5) {
      clean.removeLast();
    }
    final n = clean.length;
    if (n < 3) return const [];
    final c = centroid(clean);
    final lines = <(Offset, Offset)>[];
    for (var i = 0; i < n; i++) {
      final a = clean[i];
      final b = clean[(i + 1) % n];
      final e = b - a;
      final len = e.distance;
      var normal = Offset(-e.dy / len, e.dx / len);
      final toCentre = c - a;
      if (normal.dx * toCentre.dx + normal.dy * toCentre.dy < 0) {
        normal = -normal;
      }
      lines.add((a + normal * d, b + normal * d));
    }
    final out = <Offset>[];
    for (var i = 0; i < n; i++) {
      final (p1, p2) = lines[(i - 1 + n) % n];
      final (q1, q2) = lines[i];
      final r = p2 - p1;
      final s = q2 - q1;
      final denom = r.dx * s.dy - r.dy * s.dx;
      if (denom.abs() < 1e-9) {
        out.add(q1);
        continue;
      }
      final t = ((q1.dx - p1.dx) * s.dy - (q1.dy - p1.dy) * s.dx) / denom;
      out.add(p1 + r * t);
    }
    return out;
  }

  /// Interior angle (degrees) at vertex [i] of a convex polygon.
  static double interiorAngleDeg(List<Offset> poly, int i) {
    final n = poly.length;
    final v = poly[i];
    final a = poly[(i - 1 + n) % n] - v;
    final b = poly[(i + 1) % n] - v;
    final la = a.distance;
    final lb = b.distance;
    if (la < 1e-9 || lb < 1e-9) return 0.0;
    final cos = ((a.dx * b.dx + a.dy * b.dy) / (la * lb)).clamp(-1.0, 1.0);
    return math.acos(cos) * 180 / math.pi;
  }

  static double polygonArea(List<Offset> poly) {
    var sum = 0.0;
    for (var i = 0; i < poly.length; i++) {
      final p = poly[i];
      final q = poly[(i + 1) % poly.length];
      sum += p.dx * q.dy - q.dx * p.dy;
    }
    return sum.abs() / 2;
  }

  static Offset centroid(List<Offset> poly) {
    if (poly.isEmpty) return Offset.zero;
    var sum = Offset.zero;
    for (final p in poly) {
      sum += p;
    }
    return sum / poly.length.toDouble();
  }

  /// Width of a convex polygon: the smallest distance between two parallel
  /// supporting lines (one of them always lies on an edge).
  static double minimumWidth(List<Offset> poly) {
    if (poly.length < 3) return 0.0;
    var best = double.infinity;
    for (var i = 0; i < poly.length; i++) {
      final a = poly[i];
      final b = poly[(i + 1) % poly.length];
      final len = (b - a).distance;
      if (len < 1e-6) continue;
      var far = 0.0;
      for (final p in poly) {
        final d =
            ((b.dx - a.dx) * (p.dy - a.dy) - (b.dy - a.dy) * (p.dx - a.dx))
                .abs() /
            len;
        far = math.max(far, d);
      }
      best = math.min(best, far);
    }
    return best;
  }

  /// Rectangle used to price a shaped glass: its width follows the longest
  /// side (even a slanted one) and its height is the extent across it.
  static ({double width, double height}) pricingRectangle(List<Offset> poly) {
    if (poly.length < 3) return (width: 0.0, height: 0.0);
    var bestLen = 0.0;
    var dir = const Offset(1, 0);
    for (var i = 0; i < poly.length; i++) {
      final e = poly[(i + 1) % poly.length] - poly[i];
      if (e.distance > bestLen) {
        bestLen = e.distance;
        dir = e / e.distance;
      }
    }
    final normal = Offset(-dir.dy, dir.dx);
    double minA = double.infinity, maxA = -double.infinity;
    double minN = double.infinity, maxN = -double.infinity;
    for (final p in poly) {
      final a = p.dx * dir.dx + p.dy * dir.dy;
      final n = p.dx * normal.dx + p.dy * normal.dy;
      minA = math.min(minA, a);
      maxA = math.max(maxA, a);
      minN = math.min(minN, n);
      maxN = math.max(maxN, n);
    }
    return (width: maxA - minA, height: maxN - minN);
  }

  static bool _convexContains(List<Offset> poly, Offset p) {
    var sign = 0.0;
    for (var i = 0; i < poly.length; i++) {
      final a = poly[i];
      final b = poly[(i + 1) % poly.length];
      final s = (b.dx - a.dx) * (p.dy - a.dy) - (b.dy - a.dy) * (p.dx - a.dx);
      if (s.abs() < 1e-9) continue;
      if (sign == 0) {
        sign = s.sign;
      } else if (s.sign != sign) {
        return false;
      }
    }
    return poly.length >= 3;
  }

  /// Keeps the part of the convex [poly] inside the convex [region].
  static List<Offset> _clipToConvex(List<Offset> poly, List<Offset> region) {
    final c = centroid(region);
    var out = poly;
    for (var i = 0; i < region.length && out.isNotEmpty; i++) {
      final p = region[i];
      final q = region[(i + 1) % region.length];
      final s = (q.dx - p.dx) * (c.dy - p.dy) - (q.dy - p.dy) * (c.dx - p.dx);
      if (s.abs() < 1e-9) continue;
      out = clipHalfPlane(out, p, q, keepLeft: s > 0);
    }
    return out;
  }

  /// The part of the straight line through [a] and [b] inside the convex
  /// [poly], or null if it misses it.
  static (Offset, Offset)? _clipLineToConvex(
    Offset a,
    Offset b,
    List<Offset> poly,
  ) {
    final d = b - a;
    final c = centroid(poly);
    var t0 = -double.infinity;
    var t1 = double.infinity;
    for (var i = 0; i < poly.length; i++) {
      final p = poly[i];
      final e = poly[(i + 1) % poly.length] - p;
      if (e.distance < 1e-9) continue;
      double cross(Offset v) => e.dx * v.dy - e.dy * v.dx;
      final inside = cross(c - p).sign;
      if (inside == 0) continue;
      final f0 = cross(a - p) * inside;
      final f1 = cross(d) * inside;
      if (f1.abs() < 1e-12) {
        if (f0 < 0) return null;
        continue;
      }
      final t = -f0 / f1;
      if (f1 > 0) {
        t0 = math.max(t0, t);
      } else {
        t1 = math.min(t1, t);
      }
    }
    if (!t0.isFinite || !t1.isFinite || t1 - t0 < 1e-9) return null;
    return (a + d * t0, a + d * t1);
  }

  static double _pointLineDistance(Offset p, Offset a, Offset b) {
    final ab = b - a;
    final len = ab.distance;
    if (len < 1e-9) return (p - a).distance;
    return ((ab.dx * (p.dy - a.dy) - ab.dy * (p.dx - a.dx)).abs()) / len;
  }

  static List<Offset> _rectPolygon(Rect r) => [
    r.topLeft,
    r.topRight,
    r.bottomRight,
    r.bottomLeft,
  ];

  static Offset _unitNormal(Offset a, Offset b) {
    final d = b - a;
    final len = d.distance;
    if (len < 1e-9) return Offset.zero;
    return Offset(-d.dy / len, d.dx / len);
  }

  static bool _segmentsCloserThan(
    Offset a1,
    Offset b1,
    Offset a2,
    Offset b2,
    double gap,
  ) {
    if (_segmentsIntersect(a1, b1, a2, b2)) return true;
    return [
          _pointSegmentDistance(a1, a2, b2),
          _pointSegmentDistance(b1, a2, b2),
          _pointSegmentDistance(a2, a1, b1),
          _pointSegmentDistance(b2, a1, b1),
        ].reduce(math.min) <
        gap;
  }

  static bool _segmentsIntersect(Offset p1, Offset p2, Offset q1, Offset q2) {
    double cross(Offset o, Offset a, Offset b) =>
        (a.dx - o.dx) * (b.dy - o.dy) - (a.dy - o.dy) * (b.dx - o.dx);
    final d1 = cross(q1, q2, p1);
    final d2 = cross(q1, q2, p2);
    final d3 = cross(p1, p2, q1);
    final d4 = cross(p1, p2, q2);
    return ((d1 > 0) != (d2 > 0)) && ((d3 > 0) != (d4 > 0));
  }

  static double _pointSegmentDistance(Offset p, Offset a, Offset b) {
    final ab = b - a;
    final len2 = ab.dx * ab.dx + ab.dy * ab.dy;
    if (len2 < 1e-12) return (p - a).distance;
    final t = (((p.dx - a.dx) * ab.dx + (p.dy - a.dy) * ab.dy) / len2).clamp(
      0.0,
      1.0,
    );
    return (p - (a + ab * t)).distance;
  }
}
