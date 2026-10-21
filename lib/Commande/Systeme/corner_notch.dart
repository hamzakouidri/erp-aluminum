import 'dart:math' as math;
import 'dart:ui';

/// A corner of the window outline, clockwise from the top left.
enum NotchCorner { topLeft, topRight, bottomRight, bottomLeft }

/// A corner cut inward as a 90° step: [width] along the horizontal side and
/// [height] along the vertical side, both measured on the outer edge (mm).
/// Zero (the default) means the corner is not cut.
class CornerNotch {
  final double width;
  final double height;

  const CornerNotch({this.width = 0, this.height = 0});

  static const CornerNotch none = CornerNotch();

  bool get isCut => width > 0 && height > 0;

  @override
  bool operator ==(Object other) =>
      other is CornerNotch && other.width == width && other.height == height;

  @override
  int get hashCode => Object.hash(width, height);
}

/// One straight side of a notched outline, between two outline vertices.
class NotchedSide {
  final Offset start;
  final Offset end;

  /// Whether the frame bar meets the next bar at a reflex (270°) corner at
  /// its start or end: the inner step corner of a notch.
  final bool reflexStart;
  final bool reflexEnd;

  /// Corner whose step this side belongs to, or null for a remaining part
  /// of one of the four outer sides.
  final NotchCorner? notchCorner;

  const NotchedSide({
    required this.start,
    required this.end,
    required this.reflexStart,
    required this.reflexEnd,
    this.notchCorner,
  });

  double get length => (end - start).distance;
  bool get isHorizontal => (end.dy - start.dy).abs() < 1e-9;
}

/// The four corner cuts of a window frame. A frame without any cut is the
/// plain rectangle, and every caller keeps its rectangular code path for it.
class CornerNotches {
  final CornerNotch topLeft;
  final CornerNotch topRight;
  final CornerNotch bottomRight;
  final CornerNotch bottomLeft;

  const CornerNotches({
    this.topLeft = CornerNotch.none,
    this.topRight = CornerNotch.none,
    this.bottomRight = CornerNotch.none,
    this.bottomLeft = CornerNotch.none,
  });

  static const CornerNotches none = CornerNotches();

  /// Smallest outer side, step or remaining side length (mm).
  static const double minSideMm = 80.0;

  CornerNotch of(NotchCorner corner) => switch (corner) {
    NotchCorner.topLeft => topLeft,
    NotchCorner.topRight => topRight,
    NotchCorner.bottomRight => bottomRight,
    NotchCorner.bottomLeft => bottomLeft,
  };

  bool get hasAny => NotchCorner.values.any((c) => of(c).isCut);

  CornerNotches withCorner(NotchCorner corner, CornerNotch notch) =>
      CornerNotches(
        topLeft: corner == NotchCorner.topLeft ? notch : topLeft,
        topRight: corner == NotchCorner.topRight ? notch : topRight,
        bottomRight: corner == NotchCorner.bottomRight ? notch : bottomRight,
        bottomLeft: corner == NotchCorner.bottomLeft ? notch : bottomLeft,
      );

  static bool isTop(NotchCorner c) =>
      c == NotchCorner.topLeft || c == NotchCorner.topRight;
  static bool isLeft(NotchCorner c) =>
      c == NotchCorner.topLeft || c == NotchCorner.bottomLeft;

  /// Corner sharing the horizontal side with [c].
  static NotchCorner rowNeighbour(NotchCorner c) => switch (c) {
    NotchCorner.topLeft => NotchCorner.topRight,
    NotchCorner.topRight => NotchCorner.topLeft,
    NotchCorner.bottomRight => NotchCorner.bottomLeft,
    NotchCorner.bottomLeft => NotchCorner.bottomRight,
  };

  /// Corner sharing the vertical side with [c].
  static NotchCorner columnNeighbour(NotchCorner c) => switch (c) {
    NotchCorner.topLeft => NotchCorner.bottomLeft,
    NotchCorner.bottomLeft => NotchCorner.topLeft,
    NotchCorner.topRight => NotchCorner.bottomRight,
    NotchCorner.bottomRight => NotchCorner.topRight,
  };

  static NotchCorner opposite(NotchCorner c) => switch (c) {
    NotchCorner.topLeft => NotchCorner.bottomRight,
    NotchCorner.bottomRight => NotchCorner.topLeft,
    NotchCorner.topRight => NotchCorner.bottomLeft,
    NotchCorner.bottomLeft => NotchCorner.topRight,
  };

  /// Outer corner point of [c] on a [width] x [height] frame at [top].
  static Offset cornerPoint(
    NotchCorner c,
    double width,
    double height, {
    double top = 0,
  }) => Offset(isLeft(c) ? 0 : width, isTop(c) ? top : top + height);

  /// Area removed by the cut of [c], or null when it is not cut.
  Rect? cutRect(NotchCorner c, double width, double height, {double top = 0}) {
    final n = of(c);
    if (!n.isCut) return null;
    final left = isLeft(c) ? 0.0 : width - n.width;
    final y = isTop(c) ? top : top + height - n.height;
    return Rect.fromLTWH(left, y, n.width, n.height);
  }

  /// Outline vertices, clockwise on screen from the top-left corner, of a
  /// [width] x [height] frame whose top edge is at [top].
  List<Offset> outline(double width, double height, {double top = 0}) {
    final b = top + height;
    final tl = topLeft, tr = topRight, br = bottomRight, bl = bottomLeft;
    return [
      if (tl.isCut) ...[
        Offset(0, top + tl.height),
        Offset(tl.width, top + tl.height),
        Offset(tl.width, top),
      ] else
        Offset(0, top),
      if (tr.isCut) ...[
        Offset(width - tr.width, top),
        Offset(width - tr.width, top + tr.height),
        Offset(width, top + tr.height),
      ] else
        Offset(width, top),
      if (br.isCut) ...[
        Offset(width, b - br.height),
        Offset(width - br.width, b - br.height),
        Offset(width - br.width, b),
      ] else
        Offset(width, b),
      if (bl.isCut) ...[
        Offset(bl.width, b),
        Offset(bl.width, b - bl.height),
        Offset(0, b - bl.height),
      ] else
        Offset(0, b),
    ];
  }

  /// Inward normal of the clockwise edge [a] → [b].
  static Offset _inward(Offset a, Offset b) {
    final d = b - a;
    final len = d.distance;
    if (len == 0) return Offset.zero;
    return Offset(-d.dy / len, d.dx / len);
  }

  static bool _isReflex(Offset prev, Offset v, Offset next) {
    final a = v - prev;
    final b = next - v;
    return a.dx * b.dy - a.dy * b.dx < 0;
  }

  /// [outline] moved [inset] mm inward: the inner edge of a frame bar of
  /// that width. Every side is horizontal or vertical, so each vertex moves
  /// by the inward normals of its two sides.
  List<Offset> insetOutline(
    double width,
    double height, {
    double inset = 0,
    double top = 0,
  }) {
    final pts = outline(width, height, top: top);
    if (inset == 0) return pts;
    final n = pts.length;
    return [
      for (var i = 0; i < n; i++)
        pts[i] +
            (_inward(pts[(i - 1 + n) % n], pts[i]) +
                    _inward(pts[i], pts[(i + 1) % n])) *
                inset,
    ];
  }

  Path outlinePath(
    double width,
    double height, {
    double inset = 0,
    double top = 0,
  }) => Path()
    ..addPolygon(insetOutline(width, height, inset: inset, top: top), true);

  /// Sides of the outline in [outline] order (the side starting at vertex i).
  List<NotchedSide> sides(double width, double height, {double top = 0}) {
    final pts = outline(width, height, top: top);
    final n = pts.length;
    bool reflexAt(int i) =>
        _isReflex(pts[(i - 1 + n) % n], pts[i], pts[(i + 1) % n]);
    NotchCorner? stepOf(Offset a, Offset b) {
      for (final c in NotchCorner.values) {
        final r = cutRect(c, width, height, top: top);
        if (r == null) continue;
        final inner = Offset(
          isLeft(c) ? r.right : r.left,
          isTop(c) ? r.bottom : r.top,
        );
        if ((a - inner).distance < 1e-6 || (b - inner).distance < 1e-6) {
          return c;
        }
      }
      return null;
    }

    return [
      for (var i = 0; i < n; i++)
        NotchedSide(
          start: pts[i],
          end: pts[(i + 1) % n],
          reflexStart: reflexAt(i),
          reflexEnd: reflexAt((i + 1) % n),
          notchCorner: stepOf(pts[i], pts[(i + 1) % n]),
        ),
    ];
  }

  /// Outer perimeter (mm). A 90° step keeps the rectangle's perimeter.
  double perimeter(double width, double height) =>
      sides(width, height).fold(0.0, (sum, s) => sum + s.length);

  /// First cut length of every frame bar, in [sides] order, for bars of
  /// [profileWidth] mitred at 45° at every corner. A bar is measured tip to
  /// tip: its outer side, plus one profile width at each reflex end where
  /// the inner face is the longer one.
  List<double> frameCutLengths(
    double width,
    double height, {
    required double profileWidth,
  }) => [
    for (final s in sides(width, height))
      s.length +
          (s.reflexStart ? profileWidth : 0) +
          (s.reflexEnd ? profileWidth : 0),
  ];

  /// Why this set of cuts does not fit a [width] x [height] frame, or null.
  String? validate(double width, double height) {
    const min = minSideMm;
    for (final c in NotchCorner.values) {
      final n = of(c);
      if (n.width == 0 && n.height == 0) continue;
      if (n.width < min || n.height < min) return 'notch_too_small';
    }
    for (final c in [NotchCorner.topLeft, NotchCorner.bottomLeft]) {
      if (of(c).width + of(rowNeighbour(c)).width > width - min) {
        return 'notch_overlap';
      }
    }
    for (final c in [NotchCorner.topLeft, NotchCorner.topRight]) {
      if (of(c).height + of(columnNeighbour(c)).height > height - min) {
        return 'notch_overlap';
      }
    }
    for (final c in [NotchCorner.topLeft, NotchCorner.topRight]) {
      final a = of(c), b = of(opposite(c));
      if (!a.isCut || !b.isCut) continue;
      if (a.width + b.width > width - min &&
          a.height + b.height > height - min) {
        return 'notch_overlap';
      }
    }
    return null;
  }

  /// The cut of [corner] closest to [width] x [height] that keeps every
  /// side at least [minSideMm] long and away from the other cuts. A cut
  /// smaller than half the minimum on either side is removed.
  CornerNotch clampNotch(
    NotchCorner corner,
    double cutWidth,
    double cutHeight,
    double width,
    double height,
  ) {
    const min = minSideMm;
    if (cutWidth < min / 2 || cutHeight < min / 2) return CornerNotch.none;
    var maxW = width - min - of(rowNeighbour(corner)).width;
    var maxH = height - min - of(columnNeighbour(corner)).height;
    if (maxW < min || maxH < min) return CornerNotch.none;
    var w = cutWidth.clamp(min, maxW).toDouble();
    var h = cutHeight.clamp(min, maxH).toDouble();
    final opp = of(opposite(corner));
    if (opp.isCut &&
        w + opp.width > width - min &&
        h + opp.height > height - min) {
      // Give up the overlap on the axis that moves the cut the least.
      final shrinkW = w + opp.width - (width - min);
      final shrinkH = h + opp.height - (height - min);
      if (shrinkW <= shrinkH && w - shrinkW >= min) {
        w -= shrinkW;
      } else if (h - shrinkH >= min) {
        h -= shrinkH;
      } else {
        return CornerNotch.none;
      }
    }
    return CornerNotch(width: w, height: h);
  }

  static const _keys = {
    NotchCorner.topLeft: 'tl',
    NotchCorner.topRight: 'tr',
    NotchCorner.bottomRight: 'br',
    NotchCorner.bottomLeft: 'bl',
  };

  /// Only the cut corners are written; an uncut frame is an empty map.
  Map<String, dynamic> toJson() => {
    for (final c in NotchCorner.values)
      if (of(c).isCut) _keys[c]!: {'w': of(c).width, 'h': of(c).height},
  };

  static CornerNotches fromJson(Object? json) {
    if (json is! Map) return none;
    CornerNotch read(NotchCorner c) {
      final v = json[_keys[c]];
      if (v is! Map) return CornerNotch.none;
      final w = (v['w'] as num?)?.toDouble() ?? 0;
      final h = (v['h'] as num?)?.toDouble() ?? 0;
      return CornerNotch(width: math.max(0, w), height: math.max(0, h));
    }

    return CornerNotches(
      topLeft: read(NotchCorner.topLeft),
      topRight: read(NotchCorner.topRight),
      bottomRight: read(NotchCorner.bottomRight),
      bottomLeft: read(NotchCorner.bottomLeft),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is CornerNotches &&
      other.topLeft == topLeft &&
      other.topRight == topRight &&
      other.bottomRight == bottomRight &&
      other.bottomLeft == bottomLeft;

  @override
  int get hashCode => Object.hash(topLeft, topRight, bottomRight, bottomLeft);
}
