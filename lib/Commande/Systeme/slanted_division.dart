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

  const SlantedDivider({
    required this.id,
    required this.start,
    required this.end,
    this.profileCode,
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
  );

  Map<String, dynamic> toMap() => {
    'id': id,
    'start': start.toMap(),
    'end': end.toMap(),
    if (profileCode != null) 'profileCode': profileCode,
  };

  static SlantedDivider? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final start = SlantedDividerAnchor.fromMap(raw['start']);
    final end = SlantedDividerAnchor.fromMap(raw['end']);
    final id = raw['id']?.toString();
    if (start == null || end == null || id == null || id.isEmpty) return null;
    final code = raw['profileCode']?.toString().trim();
    return SlantedDivider(
      id: id,
      start: start,
      end: end,
      profileCode: code == null || code.isEmpty ? null : code,
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
  static const crossesDivider = 'لا يمكن أن تتقاطع التقسيمات المائلة';
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

  (Offset, Offset) centreLine(SlantedDivider d) =>
      (d.start.pointOn(clear), d.end.pointOn(clear));

  /// The division profile as a polygon: the band of [profileWidth] around
  /// its centre line, cut by the zone edges (direct angle cut on the face).
  List<Offset> band(SlantedDivider d) {
    final (a, b) = centreLine(d);
    final n = _unitNormal(a, b) * (profileWidth / 2);
    var poly = _rectPolygon(clear);
    poly = clipHalfPlane(poly, a + n, b + n, keepLeft: false);
    poly = clipHalfPlane(poly, a - n, b - n, keepLeft: true);
    return poly;
  }

  /// Clear glass cells left between the divisions (profile bands removed),
  /// ordered top to bottom, then left to right, so their keys are stable.
  List<List<Offset>> cells() {
    var polys = <List<Offset>>[_rectPolygon(clear)];
    for (final d in dividers) {
      final (a, b) = centreLine(d);
      final n = _unitNormal(a, b) * (profileWidth / 2);
      final next = <List<Offset>>[];
      for (final p in polys) {
        final left = clipHalfPlane(p, a - n, b - n, keepLeft: false);
        final right = clipHalfPlane(p, a + n, b + n, keepLeft: true);
        if (polygonArea(left) > 1.0) next.add(left);
        if (polygonArea(right) > 1.0) next.add(right);
      }
      polys = next;
    }
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
  double angleWithEdgeDeg(SlantedDivider d, {required bool atStart}) {
    final (a, b) = centreLine(d);
    final edge = atStart ? d.start.edge : d.end.edge;
    final dir = b - a;
    final horizontal = edge == ZoneEdge.top || edge == ZoneEdge.bottom;
    final along = horizontal ? dir.dx.abs() : dir.dy.abs();
    final across = horizontal ? dir.dy.abs() : dir.dx.abs();
    return math.atan2(across, along) * 180 / math.pi;
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
        final (a1, b1) = centreLine(dividers[i]);
        final (a2, b2) = centreLine(dividers[j]);
        if (_segmentsCloserThan(a1, b1, a2, b2, profileWidth + 1.0)) {
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
