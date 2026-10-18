import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'mesh3d.dart';
import 'window_scene_builder.dart';

/// Orbit camera around the scene centre.
@immutable
class OrbitCamera {
  const OrbitCamera({
    this.yaw = -0.55,
    this.pitch = 0.16,
    this.zoom = 1,
    this.pan = Offset.zero,
  });

  /// Rotation around the vertical axis (radians, unbounded).
  final double yaw;

  /// Elevation: positive looks from above.
  final double pitch;
  final double zoom;

  /// Screen-space offset in logical pixels.
  final Offset pan;

  OrbitCamera copyWith({
    double? yaw,
    double? pitch,
    double? zoom,
    Offset? pan,
  }) => OrbitCamera(
    yaw: yaw ?? this.yaw,
    pitch: pitch ?? this.pitch,
    zoom: zoom ?? this.zoom,
    pan: pan ?? this.pan,
  );

  @override
  bool operator ==(Object other) =>
      other is OrbitCamera &&
      other.yaw == yaw &&
      other.pitch == pitch &&
      other.zoom == zoom &&
      other.pan == pan;

  @override
  int get hashCode => Object.hash(yaw, pitch, zoom, pan);
}

/// Perspective renderer for a [WindowScene]: back-face culling, painter's
/// depth sort, a world-fixed key light plus fill and camera light, a soft
/// specular on lacquered profiles, wood foil textures, and glass whose
/// transparency and reflection follow the viewing angle (Fresnel).
class WindowScenePainter extends CustomPainter {
  WindowScenePainter({
    required this.scene,
    required this.camera,
    required this.dark,
  });

  final WindowScene scene;
  final OrbitCamera camera;
  final bool dark;

  static final V3 _key = const V3(-0.45, 0.75, 0.55).normalized();
  static final V3 _fill = const V3(0.55, 0.25, -0.6).normalized();

  @override
  void paint(Canvas canvas, Size size) {
    _paintBackdrop(canvas, size);
    if (scene.tris.isEmpty || size.isEmpty) return;

    final maxDim = math.max(scene.size.width, scene.size.height);
    final focal = 1.15 * math.min(size.width, size.height);
    final dist = 1.55 * maxDim / camera.zoom.clamp(0.2, 8.0);
    final near = math.max(30.0, maxDim * 0.02);
    final cy = math.cos(camera.yaw), sy = math.sin(camera.yaw);
    final cp = math.cos(camera.pitch), sp = math.sin(camera.pitch);
    final centre = size.center(Offset.zero) + camera.pan;
    final eye = V3(-dist * cp * sy, dist * sp, dist * cp * cy);

    // Projects to (screenX, screenY, depth).
    (double, double, double) project(V3 p) {
      final x1 = p.x * cy + p.z * sy;
      final z1 = -p.x * sy + p.z * cy;
      final y2 = p.y * cp - z1 * sp;
      final z2 = p.y * sp + z1 * cp;
      final depth = dist - z2;
      final k = focal / math.max(depth, 1e-3);
      return (centre.dx + x1 * k, centre.dy - y2 * k, depth);
    }

    _paintShadow(canvas, project, near);

    final items = <_Projected>[];
    for (final t in scene.tris) {
      final a = project(t.a), b = project(t.b), c = project(t.c);
      if (a.$3 < near || b.$3 < near || c.$3 < near) continue;
      final centroid = (t.a + t.b + t.c) * (1 / 3);
      final view = (eye - centroid).normalized();
      var n = t.normal;
      if (n.dot(view) < 0) {
        if (!t.surface.twoSided) continue;
        n = -n;
      }
      var depth = (a.$3 + b.$3 + c.$3) / 3;
      // Glass is nudged back so the beads and profiles touching its edge
      // always draw over it instead of alternating triangle by triangle.
      if (t.surface.kind == SurfaceKind.glass) depth += 25;
      items.add(_Projected(t, a, b, c, n, view, depth));
    }
    items.sort((p, q) => q.depth.compareTo(p.depth));

    // Draw consecutive triangles sharing a texture in one call; the order
    // inside a call is preserved, so the depth sort still holds.
    var start = 0;
    while (start < items.length) {
      final tex = items[start].tri.surface.texture;
      var end = start + 1;
      while (end < items.length && items[end].tri.surface.texture == tex) {
        end++;
      }
      _drawRun(canvas, items, start, end, tex, eye);
      start = end;
    }
  }

  void _drawRun(
    Canvas canvas,
    List<_Projected> items,
    int start,
    int end,
    ui.Image? tex,
    V3 eye,
  ) {
    final count = end - start;
    final positions = Float32List(count * 6);
    final colors = Int32List(count * 3);
    final uvs = tex == null ? null : Float32List(count * 6);
    final texScale = tex == null ? 0.0 : tex.width / 420.0;
    for (var i = 0; i < count; i++) {
      final it = items[start + i];
      final pts = [it.a, it.b, it.c];
      final verts = [it.tri.a, it.tri.b, it.tri.c];
      for (var v = 0; v < 3; v++) {
        positions[i * 6 + v * 2] = pts[v].$1;
        positions[i * 6 + v * 2 + 1] = pts[v].$2;
      }
      final s = it.tri.surface;
      if (s.kind == SurfaceKind.glass) {
        for (var v = 0; v < 3; v++) {
          colors[i * 3 + v] = _glassColor(s.color, it.normal, eye, verts[v]);
        }
      } else {
        final c = _shade(s, it.normal, it.view).toARGB32();
        colors[i * 3] = c;
        colors[i * 3 + 1] = c;
        colors[i * 3 + 2] = c;
      }
      if (uvs != null) {
        final grain = it.tri.grain ?? const V3(1, 0, 0);
        var across = it.tri.normal.cross(grain);
        if (across.length < 1e-6) across = const V3(0, 1, 0);
        for (var v = 0; v < 3; v++) {
          uvs[i * 6 + v * 2] = verts[v].dot(grain) * texScale;
          uvs[i * 6 + v * 2 + 1] = verts[v].dot(across) * texScale;
        }
      }
    }
    final vertices = ui.Vertices.raw(
      ui.VertexMode.triangles,
      positions,
      textureCoordinates: uvs,
      colors: colors,
    );
    final paint = Paint()..color = const Color(0xFFFFFFFF);
    if (tex != null) {
      paint.shader = ui.ImageShader(
        tex,
        TileMode.repeated,
        TileMode.repeated,
        Matrix4.identity().storage,
        filterQuality: FilterQuality.medium,
      );
    }
    // Modulate is symmetric, so vertex colours win over the white paint and
    // act as the lighting tint over a wood texture.
    canvas.drawVertices(vertices, BlendMode.modulate, paint);
    vertices.dispose();
  }

  Color _shade(Surface s, V3 n, V3 view) {
    final key = math.max(0.0, n.dot(_key));
    final fill = math.max(0.0, n.dot(_fill));
    final head = math.max(0.0, n.dot(view));
    final diffuse = 0.42 + 0.5 * key + 0.14 * fill + 0.22 * head;
    if (s.kind == SurfaceKind.wood) {
      final g = (math.min(1.0, diffuse * 0.95) * 255).round();
      return Color.fromARGB(255, g, g, g);
    }
    final half = (_key + view).normalized();
    final specPower = s.kind == SurfaceKind.matte ? 8.0 : 36.0;
    final specGain = s.kind == SurfaceKind.matte ? 0.05 : 0.32;
    final spec =
        math.pow(math.max(0.0, n.dot(half)), specPower).toDouble() * specGain;
    int ch(double base) =>
        ((base * diffuse + spec) * 255).clamp(0, 255).round();
    return Color.fromARGB(
      255,
      ch(s.color.r),
      ch(s.color.g),
      ch(s.color.b),
    );
  }

  int _glassColor(Color tint, V3 n, V3 eye, V3 p) {
    final v = (eye - p).normalized();
    final cosT = n.dot(v).abs();
    final fresnel = math.pow(1 - cosT, 3).toDouble();
    // Reflected direction picks a colour from the studio sky / floor.
    final r = n * (2 * n.dot(v)) - v;
    final sky = _environment(r.y);
    final mix = (0.28 + 0.6 * fresnel).clamp(0.0, 0.9);
    final c = Color.lerp(tint, sky, mix)!;
    final alpha = (0.26 + 0.55 * fresnel).clamp(0.0, 0.85);
    return c.withValues(alpha: alpha).toARGB32();
  }

  Color _environment(double up) {
    final t = ((up + 1) / 2).clamp(0.0, 1.0);
    final ground = dark ? const Color(0xFF1F2933) : const Color(0xFF7D8A96);
    final horizon = dark ? const Color(0xFF3B5368) : const Color(0xFFDDE9F2);
    final zenith = dark ? const Color(0xFF6E9CC4) : const Color(0xFFFFFFFF);
    return t < 0.5
        ? Color.lerp(ground, horizon, t * 2)!
        : Color.lerp(horizon, zenith, (t - 0.5) * 2)!;
  }

  void _paintBackdrop(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: dark
              ? const [Color(0xFF243447), Color(0xFF141C26), Color(0xFF0D131B)]
              : const [Color(0xFFEFF3F7), Color(0xFFDCE3EA), Color(0xFFB7C2CD)],
          stops: const [0, 0.62, 1],
        ).createShader(rect),
    );
  }

  void _paintShadow(
    Canvas canvas,
    (double, double, double) Function(V3) project,
    double near,
  ) {
    if (camera.pitch < -0.05) return;
    final w = scene.size.width / 2 + 40;
    final d = scene.depth / 2 + 90;
    final y = -scene.size.height / 2 - 1;
    final corners = [
      project(V3(-w, y, -d)),
      project(V3(w, y, -d)),
      project(V3(w, y, d)),
      project(V3(-w, y, d)),
    ];
    if (corners.any((c) => c.$3 < near)) return;
    final path = Path()..moveTo(corners[0].$1, corners[0].$2);
    for (final c in corners.skip(1)) {
      path.lineTo(c.$1, c.$2);
    }
    path.close();
    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.black.withValues(alpha: dark ? 0.45 : 0.22)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14),
    );
  }

  @override
  bool shouldRepaint(covariant WindowScenePainter old) =>
      old.scene != scene || old.camera != camera || old.dark != dark;
}

class _Projected {
  _Projected(
    this.tri,
    this.a,
    this.b,
    this.c,
    this.normal,
    this.view,
    this.depth,
  );

  final Tri tri;
  final (double, double, double) a;
  final (double, double, double) b;
  final (double, double, double) c;

  /// Normal facing the camera (flipped for the back of two-sided glass).
  final V3 normal;
  final V3 view;
  final double depth;
}
