import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Minimal 3D vector used by the window preview. World units are millimetres:
/// x to the right, y up, z towards the interior (the default viewer side).
@immutable
class V3 {
  const V3(this.x, this.y, this.z);

  static const zero = V3(0, 0, 0);

  final double x;
  final double y;
  final double z;

  V3 operator +(V3 o) => V3(x + o.x, y + o.y, z + o.z);
  V3 operator -(V3 o) => V3(x - o.x, y - o.y, z - o.z);
  V3 operator *(double s) => V3(x * s, y * s, z * s);
  V3 operator -() => V3(-x, -y, -z);

  double dot(V3 o) => x * o.x + y * o.y + z * o.z;
  V3 cross(V3 o) =>
      V3(y * o.z - z * o.y, z * o.x - x * o.z, x * o.y - y * o.x);
  double get length => math.sqrt(x * x + y * y + z * z);

  V3 normalized() {
    final l = length;
    return l < 1e-9 ? zero : V3(x / l, y / l, z / l);
  }

  static V3 lerp(V3 a, V3 b, double t) => a + (b - a) * t;

  /// Rotates this point around the axis through [origin] along unit [axis].
  V3 rotateAround(V3 origin, V3 axis, double angle) {
    final p = this - origin;
    final c = math.cos(angle);
    final s = math.sin(angle);
    final rotated =
        p * c + axis.cross(p) * s + axis * (axis.dot(p) * (1 - c));
    return origin + rotated;
  }
}

/// How a triangle is shaded by the renderer.
enum SurfaceKind {
  /// Lacquered aluminium / PVC: diffuse plus a soft specular highlight.
  metal,

  /// Wood-grain foil: the texture modulated by the diffuse lighting.
  wood,

  /// Transparent glazing that reflects the studio backdrop.
  glass,

  /// Matte opaque infill (panels, gaskets, floor).
  matte,
}

/// Appearance shared by the triangles of one part.
@immutable
class Surface {
  const Surface({
    required this.color,
    this.kind = SurfaceKind.metal,
    this.texture,
    this.twoSided = false,
  });

  final Color color;
  final SurfaceKind kind;
  final ui.Image? texture;
  final bool twoSided;
}

/// One flat-shaded triangle of the scene.
class Tri {
  Tri(this.a, this.b, this.c, this.normal, this.surface, {this.grain});

  final V3 a;
  final V3 b;
  final V3 c;

  /// Outward unit normal (already oriented by the builder).
  final V3 normal;
  final Surface surface;

  /// Direction the wood grain follows on this triangle (along the bar).
  final V3? grain;
}

/// Accumulates triangles. Faces are given with an outward hint so the
/// winding never has to be right by hand, and long triangles are split so
/// the painter's depth sort stays stable around recessed glass.
class MeshBuilder {
  MeshBuilder({this.maxEdge = 220, this.depthStep = 12});

  final double maxEdge;

  /// Side faces are cut into bands this deep (mm) so parts nested at
  /// different depths (glass, beads, protruding sashes) sort correctly.
  final double depthStep;
  final List<Tri> tris = [];

  /// Adds a planar polygon (convex or star-shaped around its centroid).
  void polygon(
    List<V3> pts,
    Surface surface, {
    required V3 outward,
    V3? grain,
  }) {
    if (pts.length < 3) return;
    var normal = _polygonNormal(pts);
    if (normal == V3.zero) return;
    if (normal.dot(outward) < 0) normal = -normal;
    if (pts.length == 3) {
      _split(pts[0], pts[1], pts[2], normal, surface, grain, 0);
      return;
    }
    if (pts.length == 4) {
      _quadGrid(pts, normal, surface, grain);
      return;
    }
    var cx = 0.0, cy = 0.0, cz = 0.0;
    for (final p in pts) {
      cx += p.x;
      cy += p.y;
      cz += p.z;
    }
    final centre = V3(cx / pts.length, cy / pts.length, cz / pts.length);
    for (var i = 0; i < pts.length; i++) {
      _split(
        centre,
        pts[i],
        pts[(i + 1) % pts.length],
        normal,
        surface,
        grain,
        0,
      );
    }
  }

  /// Extrudes a ring between [outer] and [inner] (same point count, index
  /// to index correspondence, both in the plane z = const) from [z0] to
  /// [z1]. Each edge becomes a mitred bar: front, back, outer and inner
  /// faces. Points are (x, y) in world millimetres.
  void ring(
    List<Offset> outer,
    List<Offset> inner,
    double z0,
    double z1,
    Surface surface, {
    bool skipOuterFaces = false,
  }) {
    final n = outer.length;
    if (n < 3 || inner.length != n) return;
    final centre = _centroid(outer);
    for (var i = 0; i < n; i++) {
      final j = (i + 1) % n;
      final o0 = outer[i], o1 = outer[j], i0 = inner[i], i1 = inner[j];
      final grain = V3(o1.dx - o0.dx, o1.dy - o0.dy, 0).normalized();
      if (grain == V3.zero) continue;
      // Front (interior) and back faces of the bar.
      polygon(
        [_v(o0, z1), _v(o1, z1), _v(i1, z1), _v(i0, z1)],
        surface,
        outward: const V3(0, 0, 1),
        grain: grain,
      );
      polygon(
        [_v(o0, z0), _v(o1, z0), _v(i1, z0), _v(i0, z0)],
        surface,
        outward: const V3(0, 0, -1),
        grain: grain,
      );
      // Edge normal pointing away from the ring centre.
      final mid = Offset((o0.dx + o1.dx) / 2, (o0.dy + o1.dy) / 2);
      var edgeOut = V3(o1.dy - o0.dy, -(o1.dx - o0.dx), 0).normalized();
      if (edgeOut.dot(V3(mid.dx - centre.dx, mid.dy - centre.dy, 0)) < 0) {
        edgeOut = -edgeOut;
      }
      if (!skipOuterFaces) {
        _side(o0, o1, z0, z1, surface, edgeOut, grain);
      }
      _side(i0, i1, z0, z1, surface, -edgeOut, grain);
    }
  }

  /// Extrudes a closed polygon into a slab (glass pane, panel, mullion).
  void slab(
    List<Offset> outline,
    double z0,
    double z1,
    Surface surface, {
    V3? grain,
    bool sides = true,
  }) {
    if (outline.length < 3) return;
    polygon(
      [for (final p in outline) _v(p, z1)],
      surface,
      outward: const V3(0, 0, 1),
      grain: grain,
    );
    if ((z1 - z0).abs() < 0.01) return;
    polygon(
      [for (final p in outline) _v(p, z0)],
      surface,
      outward: const V3(0, 0, -1),
      grain: grain,
    );
    if (!sides) return;
    final centre = _centroid(outline);
    for (var i = 0; i < outline.length; i++) {
      final a = outline[i], b = outline[(i + 1) % outline.length];
      final mid = Offset((a.dx + b.dx) / 2, (a.dy + b.dy) / 2);
      var out = V3(b.dy - a.dy, -(b.dx - a.dx), 0).normalized();
      if (out == V3.zero) continue;
      if (out.dot(V3(mid.dx - centre.dx, mid.dy - centre.dy, 0)) < 0) {
        out = -out;
      }
      _side(
        a,
        b,
        z0,
        z1,
        surface,
        out,
        grain ?? V3(b.dx - a.dx, b.dy - a.dy, 0).normalized(),
      );
    }
  }

  /// Axis-aligned box from [min] to [max].
  void box(V3 min, V3 max, Surface surface, {V3? grain}) {
    slab(
      [
        Offset(min.x, min.y),
        Offset(max.x, min.y),
        Offset(max.x, max.y),
        Offset(min.x, max.y),
      ],
      min.z,
      max.z,
      surface,
      grain: grain,
    );
  }

  /// Low-poly cylinder whose centre line follows the Y axis.  It is used for
  /// small hardware only (hinge pins and handles), so ten sides give a round
  /// silhouette without making the lightweight Canvas renderer expensive.
  void cylinderY(
    V3 centre,
    double radius,
    double length,
    Surface surface, {
    int sides = 10,
  }) {
    if (radius <= 0 || length <= 0 || sides < 3) return;
    final bottom = <V3>[];
    final top = <V3>[];
    for (var i = 0; i < sides; i++) {
      final a = 2 * math.pi * i / sides;
      final x = centre.x + math.cos(a) * radius;
      final z = centre.z + math.sin(a) * radius;
      bottom.add(V3(x, centre.y - length / 2, z));
      top.add(V3(x, centre.y + length / 2, z));
    }
    polygon(bottom, surface, outward: const V3(0, -1, 0));
    polygon(top, surface, outward: const V3(0, 1, 0));
    for (var i = 0; i < sides; i++) {
      final j = (i + 1) % sides;
      final a = V3(bottom[i].x - centre.x, 0, bottom[i].z - centre.z)
          .normalized();
      final b = V3(bottom[j].x - centre.x, 0, bottom[j].z - centre.z)
          .normalized();
      polygon(
        [bottom[i], bottom[j], top[j], top[i]],
        surface,
        outward: (a + b).normalized(),
        grain: const V3(0, 1, 0),
      );
    }
  }

  /// Low-poly cylinder pointing towards the viewer.  Suitable for the round
  /// escutcheon/rosette behind a handle.
  void cylinderZ(
    V3 centre,
    double radius,
    double depth,
    Surface surface, {
    int sides = 12,
  }) {
    if (radius <= 0 || depth <= 0 || sides < 3) return;
    final back = <V3>[];
    final front = <V3>[];
    for (var i = 0; i < sides; i++) {
      final a = 2 * math.pi * i / sides;
      final x = centre.x + math.cos(a) * radius;
      final y = centre.y + math.sin(a) * radius;
      back.add(V3(x, y, centre.z - depth / 2));
      front.add(V3(x, y, centre.z + depth / 2));
    }
    polygon(back, surface, outward: const V3(0, 0, -1));
    polygon(front, surface, outward: const V3(0, 0, 1));
    for (var i = 0; i < sides; i++) {
      final j = (i + 1) % sides;
      final a = V3(back[i].x - centre.x, back[i].y - centre.y, 0)
          .normalized();
      final b = V3(back[j].x - centre.x, back[j].y - centre.y, 0)
          .normalized();
      polygon(
        [back[i], back[j], front[j], front[i]],
        surface,
        outward: (a + b).normalized(),
      );
    }
  }

  /// Applies [transform] to every triangle added since [fromIndex] (used to
  /// swing or slide a sash as one rigid part).
  void transformSince(int fromIndex, V3 Function(V3) transform) {
    for (var i = fromIndex; i < tris.length; i++) {
      final t = tris[i];
      final a = transform(t.a), b = transform(t.b), c = transform(t.c);
      final tip = transform(t.a + t.normal) - a;
      final grain = t.grain;
      tris[i] = Tri(
        a,
        b,
        c,
        tip.normalized(),
        t.surface,
        grain: grain == null ? null : (transform(t.a + grain) - a).normalized(),
      );
    }
  }

  /// Splits a quad into a regular grid. Neighbouring quads that share an
  /// edge get the same points on it, so there are no T-junction cracks.
  void _quadGrid(List<V3> p, V3 n, Surface s, V3? grain) {
    final maxEdge = _edgeFor(s);
    final nu = math.max(
      1,
      (math.max((p[1] - p[0]).length, (p[2] - p[3]).length) / maxEdge).ceil(),
    );
    final nv = math.max(
      1,
      (math.max((p[3] - p[0]).length, (p[2] - p[1]).length) / maxEdge).ceil(),
    );
    V3 at(int i, int j) {
      final u = i / nu, v = j / nv;
      return V3.lerp(V3.lerp(p[0], p[1], u), V3.lerp(p[3], p[2], u), v);
    }

    for (var j = 0; j < nv; j++) {
      for (var i = 0; i < nu; i++) {
        final a = at(i, j), b = at(i + 1, j);
        final c = at(i + 1, j + 1), d = at(i, j + 1);
        tris
          ..add(Tri(a, b, c, n, s, grain: grain))
          ..add(Tri(a, c, d, n, s, grain: grain));
      }
    }
  }

  void _split(
    V3 a,
    V3 b,
    V3 c,
    V3 n,
    Surface s,
    V3? grain,
    int depth,
  ) {
    final ab = (b - a).length, bc = (c - b).length, ca = (a - c).length;
    final longest = math.max(ab, math.max(bc, ca));
    if (longest <= _edgeFor(s) || depth > 9) {
      tris.add(Tri(a, b, c, n, s, grain: grain));
      return;
    }
    if (longest == ab) {
      final m = V3.lerp(a, b, 0.5);
      _split(a, m, c, n, s, grain, depth + 1);
      _split(m, b, c, n, s, grain, depth + 1);
    } else if (longest == bc) {
      final m = V3.lerp(b, c, 0.5);
      _split(a, b, m, n, s, grain, depth + 1);
      _split(a, m, c, n, s, grain, depth + 1);
    } else {
      final m = V3.lerp(c, a, 0.5);
      _split(a, b, m, n, s, grain, depth + 1);
      _split(m, b, c, n, s, grain, depth + 1);
    }
  }

  /// Side wall between plan points [a] and [b], banded along z.
  void _side(
    Offset a,
    Offset b,
    double z0,
    double z1,
    Surface surface,
    V3 outward,
    V3? grain,
  ) {
    final lo = math.min(z0, z1), hi = math.max(z0, z1);
    final bands = math.max(1, ((hi - lo) / depthStep).ceil());
    for (var k = 0; k < bands; k++) {
      final za = lo + (hi - lo) * k / bands;
      final zb = lo + (hi - lo) * (k + 1) / bands;
      polygon(
        [_v(a, za), _v(b, za), _v(b, zb), _v(a, zb)],
        surface,
        outward: outward,
        grain: grain,
      );
    }
  }

  /// Glass gets finer tiles: it is large, transparent and sits between
  /// opaque parts, so its depth sort needs more resolution.
  double _edgeFor(Surface s) =>
      s.kind == SurfaceKind.glass ? math.min(maxEdge, 80.0) : maxEdge;

  static V3 _v(Offset p, double z) => V3(p.dx, p.dy, z);

  static Offset _centroid(List<Offset> pts) {
    var x = 0.0, y = 0.0;
    for (final p in pts) {
      x += p.dx;
      y += p.dy;
    }
    return Offset(x / pts.length, y / pts.length);
  }

  /// Newell's method: robust for any planar polygon orientation.
  static V3 _polygonNormal(List<V3> pts) {
    var nx = 0.0, ny = 0.0, nz = 0.0;
    for (var i = 0; i < pts.length; i++) {
      final a = pts[i], b = pts[(i + 1) % pts.length];
      nx += (a.y - b.y) * (a.z + b.z);
      ny += (a.z - b.z) * (a.x + b.x);
      nz += (a.x - b.x) * (a.y + b.y);
    }
    return V3(nx, ny, nz).normalized();
  }
}
