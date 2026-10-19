import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../Systeme/model.dart';
import '../texture_cache.dart';
import '../../utils/real_color_resolver.dart';
import 'mesh3d.dart';

/// Result of [WindowSceneBuilder.build]: the triangles plus the bounds the
/// camera frames.
class WindowScene {
  WindowScene(this.tris, this.size, this.depth);

  final List<Tri> tris;

  /// Overall width/height of the frames in millimetres.
  final Size size;

  /// Frame depth in millimetres (used for the floor shadow).
  final double depth;
}

/// Visual families of aluminium/PVC sections used by the lightweight 3D
/// renderer. Catalogue-specific templates will refine these families later.
enum _ProfileShape { frame, casementSash, slidingSash }

/// Converts a [WindowModel] into a lit 3D mesh: mitred frame bars with their
/// real face width and a profile depth, mullions, glazing beads, glass,
/// panels, sashes that swing on their hinges or slide on their tracks,
/// handles and hinges. Model coordinates are millimetres with y down; the
/// scene is centred on the frames with y up and the interior towards +z.
class WindowSceneBuilder {
  WindowSceneBuilder(this.model);

  final WindowModel model;

  late double _cx;
  late double _cy;
  late double _frameDepth;
  late bool _shapedHead;
  double _headZoneTop = 0;
  final MeshBuilder _mesh = MeshBuilder();

  static const _headSamples = 28;
  static const _sashOverlap = -1.0;
  static const _glassHalf = 10.0;

  WindowScene build({required double opening}) {
    final frames = model.getFrameRects();
    final frameRects = frames.isEmpty
        ? <Rect>[Rect.fromLTWH(0, 0, model.width, model.height)]
        : frames;
    var bounds = frameRects.first;
    for (final r in frameRects.skip(1)) {
      bounds = bounds.expandToInclude(r);
    }
    _frameDepth = _isPvc ? 70.0 : 60.0;
    _shapedHead = frameRects.length == 1 && model.hasArchOrSlant;
    if (_shapedHead) {
      final frame = frameRects.first;
      // Parts whose top reaches the frame's inner head follow the head line.
      _headZoneTop = frame.top + _frameWidth(frame) + 3;
      // An arch rises above the chord: include its apex in the bounds.
      var top = bounds.top;
      for (var i = 0; i <= _headSamples; i++) {
        final x = frame.left + frame.width * i / _headSamples;
        final y = _safeHead(x, 0);
        if (y != null && y < top) top = y;
      }
      bounds = Rect.fromLTRB(bounds.left, top, bounds.right, bounds.bottom);
    }
    _cx = bounds.center.dx;
    _cy = bounds.center.dy;

    final frameSurface = _surfaceFor(
      model.selectedDbColor,
      model.frameColor.name,
    );

    for (final frame in frameRects) {
      final tf = _frameWidth(frame);
      final outer = _shapedRect(frame, 0, headBase: 0, followHead: true);
      final inner = _shapedRect(frame, tf, headBase: 0, followHead: true);
      _mesh.ring(
        [for (final p in outer) _w(p)],
        [for (final p in inner) _w(p)],
        -_frameDepth / 2,
        _frameDepth / 2,
        frameSurface,
      );
      // A real extrusion has several visible steps: exterior reveal, main
      // face and glazing rebate.  The former single rectangular ring made
      // every series look like a generic wooden frame.  These shallow,
      // geometry-only reliefs make the profile read as an aluminium/PVC
      // section without changing any engineering dimension or BOM value.
      _addProfileRelief(
        frame,
        tf,
        headBase: 0,
        zFront: _frameDepth / 2,
        surface: frameSurface,
        shape: _ProfileShape.frame,
      );
      final zonesHere = [
        for (final z in model.zones)
          if (frame.contains(z.boundary.center)) z,
      ];
      _addMullions(frame.deflate(tf), zonesHere, tf, frameSurface);
      for (final zone in zonesHere) {
        _addZone(zone, tf, frameSurface, opening);
      }
    }

    return WindowScene(_mesh.tris, bounds.size, _frameDepth);
  }

  // ---------------------------------------------------------------------------
  // Geometry helpers

  bool get _isPvc {
    try {
      return model.isFramePVC;
    } catch (_) {
      return false;
    }
  }

  double _frameWidth(Rect frame) {
    double t;
    try {
      t = model.frameVisibleWidthForRect(frame);
    } catch (_) {
      t = model.profileThickness;
    }
    if (!t.isFinite || t <= 0) t = 50;
    return t.clamp(20.0, math.min(frame.width, frame.height) / 3).toDouble();
  }

  /// Model point (y down) to scene plane point (y up, centred).
  Offset _w(Offset p) => Offset(p.dx - _cx, _cy - p.dy);

  /// Outline of [r] inset by [inset] mm; under an arched or slanted head the
  /// top edge follows the head line [headBase] + [inset] mm into the window.
  /// Point order (and count, for a given rect) is stable so two calls with
  /// different insets can be joined as a mitred ring.
  List<Offset> _shapedRect(
    Rect r,
    double inset, {
    required double headBase,
    bool? followHead,
  }) {
    final l = r.left + inset;
    final right = r.right - inset;
    final b = r.bottom - inset;
    final flatTop = r.top + inset;
    final follows = _shapedHead && (followHead ?? r.top <= _headZoneTop);
    if (!follows) {
      return [
        Offset(l, b),
        Offset(right, b),
        Offset(right, flatTop),
        Offset(l, flatTop),
      ];
    }
    double topAt(double x) =>
        math.min(_safeHead(x, headBase + inset) ?? flatTop, b - 5);

    final pts = <Offset>[Offset(l, b), Offset(right, b)];
    for (var i = _headSamples; i >= 0; i--) {
      final x = l + (right - l) * i / _headSamples;
      pts.add(Offset(x, topAt(x)));
    }
    return pts;
  }

  double? _safeHead(double x, double inset) {
    try {
      final y = model.headEdgeY(x, inset);
      return y.isFinite ? y : null;
    } catch (_) {
      return null;
    }
  }

  List<Offset> _scene(List<Offset> modelPts) => [
    for (final p in modelPts) _w(p),
  ];

  // ---------------------------------------------------------------------------
  // Mullions and transoms: whatever lies inside the frame but outside every
  // zone's clear opening is profile material.

  void _addMullions(
    Rect interior,
    List<WindowZone> zones,
    double tf,
    Surface surface,
  ) {
    if (zones.isEmpty) return;
    final xs = <double>{interior.left, interior.right};
    final ys = <double>{interior.top, interior.bottom};
    for (final z in zones) {
      final b = z.boundary.intersect(interior);
      if (b.width <= 0 || b.height <= 0) continue;
      xs..add(b.left)..add(b.right);
      ys..add(b.top)..add(b.bottom);
    }
    final sx = xs.toList()..sort();
    final sy = ys.toList()..sort();
    final cols = sx.length - 1, rows = sy.length - 1;
    if (cols <= 0 || rows <= 0) return;
    final filled = List.generate(rows, (_) => List.filled(cols, false));
    for (var j = 0; j < rows; j++) {
      for (var i = 0; i < cols; i++) {
        final w = sx[i + 1] - sx[i], h = sy[j + 1] - sy[j];
        if (w < 0.5 || h < 0.5) continue;
        final c = Offset((sx[i] + sx[i + 1]) / 2, (sy[j] + sy[j + 1]) / 2);
        filled[j][i] = !zones.any((z) => z.boundary.contains(c));
      }
    }
    // Merge horizontal runs, then stack identical runs vertically.
    final open = <String, Rect>{};
    final done = <Rect>[];
    for (var j = 0; j < rows; j++) {
      final runs = <String, Rect>{};
      var i = 0;
      while (i < cols) {
        if (!filled[j][i]) {
          i++;
          continue;
        }
        final start = i;
        while (i < cols && filled[j][i]) {
          i++;
        }
        runs['$start-$i'] = Rect.fromLTRB(sx[start], sy[j], sx[i], sy[j + 1]);
      }
      for (final entry in open.entries) {
        final next = runs[entry.key];
        if (next != null) {
          runs[entry.key] = Rect.fromLTRB(
            entry.value.left,
            entry.value.top,
            entry.value.right,
            next.bottom,
          );
        } else {
          done.add(entry.value);
        }
      }
      open
        ..clear()
        ..addAll(runs);
    }
    done.addAll(open.values);

    for (final r in done) {
      if (r.width < 3 || r.height < 3) continue;
      final outline = _scene(_shapedRect(r, 0, headBase: tf));
      _mesh.slab(
        outline,
        -_frameDepth / 2,
        _frameDepth / 2,
        surface,
        grain: r.height >= r.width ? const V3(0, 1, 0) : const V3(1, 0, 0),
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Zone content

  void _addZone(
    WindowZone zone,
    double tf,
    Surface frameSurface,
    double opening,
  ) {
    final r = zone.boundary;
    if (r.width <= 4 || r.height <= 4) return;
    switch (zone.content) {
      case ZoneContent.empty:
        return;
      case ZoneContent.fixedGlass:
        _addInfill(zone, r, 0, tf, 0);
        _addBead(r, 0, 18, tf, 0, frameSurface);
      case ZoneContent.singleSash:
        final dir = zone.openDirection ?? OpenDirection.right;
        _addCasement(
          zone,
          r.inflate(_sashOverlap),
          tf,
          handleSide: dir,
          hingeSide: _opposite(dir),
          opening: opening,
          withHandle: true,
        );
      case ZoneContent.doubleSash:
        final ratio = zone.doubleSashRatio.clamp(0.2, 0.8).toDouble();
        final split = r.left + r.width * ratio;
        final left = Rect.fromLTRB(
          r.left - _sashOverlap,
          r.top - _sashOverlap,
          split,
          r.bottom + _sashOverlap,
        );
        final right = Rect.fromLTRB(
          split,
          r.top - _sashOverlap,
          r.right + _sashOverlap,
          r.bottom + _sashOverlap,
        );
        final activeLeft = zone.openDirection == OpenDirection.left;
        _addCasement(
          zone,
          left,
          tf,
          handleSide: OpenDirection.right,
          hingeSide: OpenDirection.left,
          opening: opening,
          withHandle: activeLeft || zone.doubleSashHasTwoHandles,
        );
        _addCasement(
          zone,
          right,
          tf,
          handleSide: OpenDirection.left,
          hingeSide: OpenDirection.right,
          opening: opening * (activeLeft ? 0.85 : 1.0),
          withHandle: !activeLeft || zone.doubleSashHasTwoHandles,
        );
      case ZoneContent.slidingSash:
        _addSliding(zone, r, tf, opening);
    }
  }

  static OpenDirection _opposite(OpenDirection d) => switch (d) {
    OpenDirection.left => OpenDirection.right,
    OpenDirection.right => OpenDirection.left,
    OpenDirection.top => OpenDirection.bottom,
    OpenDirection.bottom => OpenDirection.top,
  };

  bool _isPanel(WindowZone zone) =>
      zone.glass.panneauSubtype?.trim().isNotEmpty == true ||
      zone.glass.panneauProductId != null;

  /// Glass pane (or opaque panel) of [r] inset by [inset], centred on [zc].
  void _addInfill(
    WindowZone zone,
    Rect r,
    double inset,
    double tf,
    double zc,
  ) {
    final outline = _scene(_shapedRect(r, inset, headBase: tf));
    if (_isPanel(zone)) {
      _mesh.slab(
        outline,
        zc - 12,
        zc + 12,
        Surface(
          color: _panelColor(zone.glass.panneauColor),
          kind: SurfaceKind.matte,
        ),
        sides: false,
      );
      return;
    }
    _mesh.slab(
      outline,
      zc - _glassHalf,
      zc + _glassHalf,
      Surface(
        color: _glassTint(zone.glass),
        kind: SurfaceKind.glass,
        twoSided: true,
      ),
      sides: false,
    );
  }

  /// Interior glazing bead (parclose) around a pane.
  void _addBead(
    Rect r,
    double inset,
    double width,
    double tf,
    double zc,
    Surface surface,
  ) {
    _mesh.ring(
      _scene(_shapedRect(r, inset, headBase: tf)),
      _scene(_shapedRect(r, inset + width, headBase: tf)),
      zc + _glassHalf,
      zc + _glassHalf + 16,
      surface,
      skipOuterFaces: true,
    );
    // Rubber gasket: a dark, thin band immediately around the glass.  This
    // small separation is far more readable than a single colour transition
    // between the bead and the glazing.
    const gasket = Surface(color: Color(0xFF20262B), kind: SurfaceKind.matte);
    _mesh.ring(
      _scene(_shapedRect(r, inset + width - 2.5, headBase: tf)),
      _scene(_shapedRect(r, inset + width + 2.2, headBase: tf)),
      zc + _glassHalf + 15.8,
      zc + _glassHalf + 18.2,
      gasket,
      skipOuterFaces: true,
    );
  }

  /// Adds two narrow rebates to the visible face of a frame or sash.
  ///
  /// They are intentionally only a few millimetres deep: this is a visual
  /// representation of the profile's stepped section, not a modification to
  /// the technical drawing's width, height or glass clear opening.
  void _addProfileRelief(
    Rect r,
    double profileWidth, {
    required double headBase,
    required double zFront,
    required Surface surface,
    required _ProfileShape shape,
  }) {
    // Keep the detail valid even for narrow profiles or very small zones.
    final available = math.min(profileWidth - 8, math.min(r.width, r.height) / 2 - 5);
    if (available < 10) return;

    // Each family has a recognisable front-face language. Frames have a
    // broader exterior reveal, casement sashes have a tighter glazing
    // channel, and sliding sashes get a deeper central channel. This is not
    // a catalogue-exact extrusion yet; it makes the pieces visibly distinct
    // while we progressively add catalogue section templates.
    final outerStart = switch (shape) {
      _ProfileShape.frame => 4.0,
      _ProfileShape.casementSash => 6.0,
      _ProfileShape.slidingSash => 3.0,
    };
    final outerWidth = switch (shape) {
      _ProfileShape.frame => 6.0,
      _ProfileShape.casementSash => 4.0,
      _ProfileShape.slidingSash => 7.0,
    };
    final outerA = math.min(outerStart, available * 0.30);
    final outerB = math.min(outerA + outerWidth, available * 0.55);
    if (outerB - outerA >= 2) {
      _mesh.ring(
        _scene(_shapedRect(r, outerA, headBase: headBase)),
        _scene(_shapedRect(r, outerB, headBase: headBase)),
        zFront + 0.4,
        zFront + 3.2,
        surface,
        skipOuterFaces: true,
      );
    }

    // The shadow line beside the glazing bead is the cue that most clearly
    // separates a real section from a flat painted rectangle.
    final rebateOffset = switch (shape) {
      _ProfileShape.frame => 14.0,
      _ProfileShape.casementSash => 12.0,
      _ProfileShape.slidingSash => 17.0,
    };
    final rebateWidth = shape == _ProfileShape.slidingSash ? 7.0 : 5.0;
    final rebateOuter = math.max(outerB + 4, profileWidth - rebateOffset);
    final rebateInner = math.min(profileWidth - 3, rebateOuter + rebateWidth);
    if (rebateInner - rebateOuter >= 2 && rebateInner < math.min(r.width, r.height) / 2 - 2) {
      _mesh.ring(
        _scene(_shapedRect(r, rebateOuter, headBase: headBase)),
        _scene(_shapedRect(r, rebateInner, headBase: headBase)),
        zFront + 0.2,
        zFront + 2.2,
        _recessSurface(surface),
        skipOuterFaces: true,
      );
    }

    // A sliding stile has a characteristic middle channel.  It is kept
    // shallow enough to avoid covering the glass or changing its opening.
    if (shape == _ProfileShape.slidingSash) {
      final centreA = math.max(outerB + 5, profileWidth * 0.42);
      final centreB = math.min(profileWidth - 18, centreA + 4.5);
      if (centreB - centreA >= 2 &&
          centreB < math.min(r.width, r.height) / 2 - 2) {
        _mesh.ring(
          _scene(_shapedRect(r, centreA, headBase: headBase)),
          _scene(_shapedRect(r, centreB, headBase: headBase)),
          zFront + 0.35,
          zFront + 1.8,
          _recessSurface(surface),
          skipOuterFaces: true,
        );
      }
    }
  }

  double _sashWidth(WindowZone zone, Rect sash) {
    double t;
    try {
      t = zone.sashThickness ?? model.getSectionThickness('sash');
    } catch (_) {
      t = 55;
    }
    if (!t.isFinite || t <= 0) t = 55;
    return t
        .clamp(30.0, math.max(30.0, math.min(sash.width, sash.height) / 3))
        .toDouble();
  }

  void _addCasement(
    WindowZone zone,
    Rect sash,
    double tf, {
    required OpenDirection handleSide,
    required OpenDirection hingeSide,
    required double opening,
    required bool withHandle,
  }) {
    final surface = _surfaceFor(
      zone.selectedDbColor ?? model.selectedDbColor,
      zone.sashColor.name,
    );
    final ts = _sashWidth(zone, sash);
    final z0 = -_frameDepth / 2 + 10;
    final z1 = _frameDepth / 2 + 12;
    final zc = (z0 + z1) / 2;
    final hardware = _hardwareSurface(surface);

    // Hinges stay on the frame; they are drawn before the moving part.
    _addHinges(sash, hingeSide, z1, hardware);

    final first = _mesh.tris.length;
    final outer = _shapedRect(sash, 0, headBase: tf - _sashOverlap);
    final inner = _shapedRect(sash, ts, headBase: tf - _sashOverlap);
    _mesh.ring(_scene(outer), _scene(inner), z0, z1, surface);
    _addProfileRelief(
      sash,
      ts,
      headBase: tf - _sashOverlap,
      zFront: z1,
      surface: surface,
      shape: _ProfileShape.casementSash,
    );
    _addInfill(zone, sash, ts, tf - _sashOverlap, zc);
    _addBead(sash, ts, 16, tf - _sashOverlap, zc, surface);
    if (withHandle) {
      _addHandle(
        sash,
        ts,
        handleSide,
        zone.handlePositionRatio ?? 0.5,
        z1,
        hardware,
      );
    }

    if (opening <= 0.001) return;
    final s = _scene([sash.topLeft, sash.bottomRight]);
    final left = s[0].dx, top = s[0].dy, right = s[1].dx, bottom = s[1].dy;
    final V3 axisPoint;
    final V3 axis;
    final double maxAngle;
    switch (hingeSide) {
      case OpenDirection.left:
        axisPoint = V3(left, 0, z1);
        axis = const V3(0, 1, 0);
        maxAngle = 78;
      case OpenDirection.right:
        axisPoint = V3(right, 0, z1);
        axis = const V3(0, 1, 0);
        maxAngle = 78;
      case OpenDirection.bottom:
        // Tilt (oscillo / abattant): hinged at the bottom, opens inwards.
        axisPoint = V3(0, bottom, z1);
        axis = const V3(1, 0, 0);
        maxAngle = 14;
      case OpenDirection.top:
        // Projecting sash: hinged at the top, swings outwards.
        axisPoint = V3(0, top, z0);
        axis = const V3(1, 0, 0);
        maxAngle = -28;
    }
    var angle = maxAngle * math.pi / 180 * opening;
    // Pick the sign that moves the free edge towards the interior (or the
    // exterior for a projecting sash).
    final centre = V3((left + right) / 2, (top + bottom) / 2, zc);
    final probe = centre.rotateAround(axisPoint, axis, angle.abs());
    final wantsInward = maxAngle > 0;
    final goesInward = probe.z > centre.z;
    angle = angle.abs() * (goesInward == wantsInward ? 1 : -1);
    _mesh.transformSince(
      first,
      (p) => p.rotateAround(axisPoint, axis, angle),
    );
  }

  void _addSliding(WindowZone zone, Rect r, double tf, double opening) {
    final surface = _surfaceFor(
      zone.selectedDbColor ?? model.selectedDbColor,
      zone.sashColor.name,
    );
    final hardware = _hardwareSurface(surface);
    final n = math.max(1, zone.slidingSashesCount);
    final tracks = math.max(n > 1 ? 2 : 1, zone.slidingTrackCount);
    const overlap = 40.0;
    final full = r.inflate(_sashOverlap);
    final pw = (full.width + overlap * (n - 1)) / n;
    final laneDepth = _frameDepth / tracks;
    _addSlidingTrackRails(full, tracks, surface);
    for (var i = 0; i < n; i++) {
      final lane = i % tracks;
      final zA = -_frameDepth / 2 + laneDepth * lane + laneDepth * 0.12;
      final zB = zA + laneDepth * 0.76;
      final panel = Rect.fromLTWH(
        full.left + i * (pw - overlap),
        full.top,
        pw,
        full.height,
      );
      final ts = _sashWidth(zone, panel);
      final first = _mesh.tris.length;
      _mesh.ring(
        _scene(_shapedRect(panel, 0, headBase: tf - _sashOverlap)),
        _scene(_shapedRect(panel, ts, headBase: tf - _sashOverlap)),
        zA,
        zB,
        surface,
      );
      _addProfileRelief(
        panel,
        ts,
        headBase: tf - _sashOverlap,
        zFront: zB,
        surface: surface,
        shape: _ProfileShape.slidingSash,
      );
      final zc = (zA + zB) / 2;
      final pane = _shapedRect(panel, ts, headBase: tf - _sashOverlap);
      _mesh.slab(
        _scene(pane),
        zc - 4,
        zc + 4,
        _isPanel(zone)
            ? Surface(
                color: _panelColor(zone.glass.panneauColor),
                kind: SurfaceKind.matte,
              )
            : Surface(
                color: _glassTint(zone.glass),
                kind: SurfaceKind.glass,
                twoSided: true,
              ),
        sides: false,
      );
      // Pull handle on the leading stile, interior face.
      final leadingRight = i < n / 2;
      final hx = leadingRight ? panel.right - ts / 2 : panel.left + ts / 2;
      final hy = panel.bottom - panel.height * 0.45;
      final h = _w(Offset(hx, hy));
      _mesh.box(
        V3(h.dx - 9, h.dy - 70, zB),
        V3(h.dx + 9, h.dy + 70, zB + 14),
        hardware,
      );
      final dx = (pw - overlap) * 0.9 * opening;
      final shift = n == 1
          ? 0.0
          : (n.isOdd && i == n ~/ 2)
          ? 0.0
          : (i < n / 2 ? dx : -dx);
      if (shift != 0) {
        _mesh.transformSince(first, (p) => V3(p.x + shift, p.y, p.z));
      }
    }
  }

  /// Two or three real-looking rails distinguish a sliding frame from a
  /// casement frame even when the leaves are closed.  The rails are visual
  /// sub-parts laid inside the existing opening and never alter the model's
  /// measured geometry.
  void _addSlidingTrackRails(Rect opening, int tracks, Surface surface) {
    final count = tracks.clamp(1, 3);
    final railSurface = _recessSurface(surface);
    for (var lane = 0; lane < count; lane++) {
      final laneT = (lane + 0.5) / count;
      final z = -_frameDepth / 2 + _frameDepth * laneT;
      for (final y in [opening.top + 8, opening.bottom - 8]) {
        final p0 = _w(Offset(opening.left + 4, y));
        final p1 = _w(Offset(opening.right - 4, y));
        _mesh.box(
          V3(p0.dx, p0.dy - 4, z - 5),
          V3(p1.dx, p1.dy + 4, z + 5),
          railSurface,
          grain: const V3(1, 0, 0),
        );
      }
    }
  }

  /// Hinge knuckles sit on the frame face just outside the sash edge.
  void _addHinges(Rect sash, OpenDirection side, double z1, Surface s) {
    final zFront = _frameDepth / 2;
    if (side == OpenDirection.left || side == OpenDirection.right) {
      final x = side == OpenDirection.left ? sash.left - 9 : sash.right + 9;
      for (final f in const [0.12, 0.88]) {
        final p = _w(Offset(x, sash.top + sash.height * f));
        // Fixing plate behind the pin.
        _mesh.box(
          V3(p.dx - 19, p.dy - 48, zFront - 1),
          V3(p.dx + 19, p.dy + 48, zFront + 4),
          s,
        );
        // Cylindrical hinge knuckle and a small cap at each end.
        _mesh.cylinderY(V3(p.dx, p.dy, z1 + 7), 8, 80, s);
        _mesh.cylinderY(V3(p.dx, p.dy - 43, z1 + 7), 10, 4, s);
        _mesh.cylinderY(V3(p.dx, p.dy + 43, z1 + 7), 10, 4, s);
      }
    } else {
      final y = side == OpenDirection.top ? sash.top - 9 : sash.bottom + 9;
      for (final f in const [0.15, 0.85]) {
        final p = _w(Offset(sash.left + sash.width * f, y));
        _mesh.box(
          V3(p.dx - 45, p.dy - 7, zFront),
          V3(p.dx + 45, p.dy + 7, z1 + 6),
          s,
        );
      }
    }
  }

  void _addHandle(
    Rect sash,
    double ts,
    OpenDirection side,
    double ratio,
    double z1,
    Surface s,
  ) {
    final r = ratio.clamp(0.05, 0.95).toDouble();
    final vertical = side == OpenDirection.left || side == OpenDirection.right;
    final Offset c;
    if (vertical) {
      final x = side == OpenDirection.right
          ? sash.right - ts / 2
          : sash.left + ts / 2;
      c = _w(Offset(x, sash.bottom - sash.height * r));
    } else {
      final y = side == OpenDirection.top
          ? sash.top + ts / 2
          : sash.bottom - ts / 2;
      c = _w(Offset(sash.left + sash.width * r, y));
    }
    final rose = vertical ? const Size(30, 74) : const Size(74, 30);
    _mesh.box(
      V3(c.dx - rose.width / 2, c.dy - rose.height / 2, z1),
      V3(c.dx + rose.width / 2, c.dy + rose.height / 2, z1 + 10),
      s,
    );
    // Circular rosette and spindle: more recognisable than a flat rectangle
    // when the user turns the view to inspect the hardware.
    _mesh.cylinderZ(V3(c.dx, c.dy, z1 + 13), 15, 8, s);
    _mesh.cylinderZ(V3(c.dx, c.dy, z1 + 19), 6, 7, s, sides: 10);
    // Lever: down when closed on a side stile, sideways on a top/bottom rail.
    if (vertical) {
      _mesh.box(
        V3(c.dx - 10, c.dy - 125, z1 + 12),
        V3(c.dx + 10, c.dy + 10, z1 + 28),
        s,
        grain: const V3(0, 1, 0),
      );
    } else {
      _mesh.box(
        V3(c.dx - 125, c.dy - 10, z1 + 12),
        V3(c.dx + 10, c.dy + 10, z1 + 28),
        s,
        grain: const V3(1, 0, 0),
      );
    }
    _mesh.box(
      V3(c.dx - 9, c.dy - 9, z1 + 10),
      V3(c.dx + 9, c.dy + 9, z1 + 12),
      s,
    );
  }

  // ---------------------------------------------------------------------------
  // Materials

  Surface _surfaceFor(Map<String, dynamic>? dbColor, String enumName) {
    final wood = _woodTexture(dbColor);
    if (wood != null) {
      return Surface(
        color: const Color(0xFFFFFFFF),
        kind: SurfaceKind.wood,
        texture: wood,
      );
    }
    return Surface(color: _solidColor(dbColor, enumName));
  }

  Surface _hardwareSurface(Surface sash) {
    final c = sash.kind == SurfaceKind.wood
        ? const Color(0xFFB8A27A)
        : sash.color.computeLuminance() > 0.45
        ? const Color(0xFFB4BAC0)
        : const Color(0xFFD1D5DB);
    return Surface(color: c);
  }

  /// A restrained darkening for recessed profile channels.  It is derived
  /// from the selected finish, so the visual detail also follows catalogue
  /// colours and wood textures rather than imposing a black stripe.
  Surface _recessSurface(Surface base) {
    final c = Color.lerp(base.color, Colors.black, 0.28)!;
    return Surface(
      color: c,
      kind: base.kind == SurfaceKind.wood ? SurfaceKind.wood : SurfaceKind.matte,
      texture: base.texture,
    );
  }

  static Color _solidColor(Map<String, dynamic>? dbColor, String enumName) {
    final raw =
        dbColor?['code']?.toString() ?? dbColor?['hex']?.toString() ?? '';
    final clean = raw.replaceAll('#', '').trim();
    if (clean.length == 6) {
      final value = int.tryParse(clean, radix: 16);
      if (value != null) return Color(0xFF000000 | value);
    }
    final name = '${dbColor?['name'] ?? ''} $enumName'.toLowerCase();
    if (name.contains('black') || name.contains('noir') || name.contains('أسود')) {
      return const Color(0xFF2B2E31);
    }
    if (name.contains('brown') ||
        name.contains('bronze') ||
        name.contains('marron') ||
        name.contains('بني')) {
      return const Color(0xFF6D4C41);
    }
    if (name.contains('gray') ||
        name.contains('grey') ||
        name.contains('gris') ||
        name.contains('رمادي') ||
        name.contains('anthracite')) {
      return const Color(0xFF5F666D);
    }
    if (name.contains('silver') || name.contains('argent')) {
      return const Color(0xFFC0C4C8);
    }
    return const Color(0xFFF4F5F6);
  }

  /// Same naming rules as the 2D drawing, so the 3D foil matches it.
  static ui.Image? _woodTexture(Map<String, dynamic>? dbColor) {
    if (dbColor == null) return null;
    final n = '${dbColor['name'] ?? ''}'
        .toLowerCase()
        .replaceAll('أ', 'ا')
        .replaceAll('إ', 'ا')
        .replaceAll('آ', 'ا')
        .replaceAll('ى', 'ي')
        .replaceAll('ة', 'ه');
    const woodWords = [
      'خشب',
      'wood',
      'bois',
      'desert',
      'oak',
      'faux',
      'antique',
      'انتيك',
      'onteak',
      'fonce',
      'foncé',
      'dark',
    ];
    if (!woodWords.any(n.contains)) return null;
    TextureCache.ensureLoading();
    // Faux Bois Marron is the light brown wood, never the grey antique.
    if (isLightBrownWoodName(n)) {
      return TextureCache.woodTextureLightBrown ?? TextureCache.woodTexture;
    }
    if (n.contains('d0') || n.contains('di zero') || n.contains('desert')) {
      return TextureCache.woodTextureD0 ?? TextureCache.woodTexture;
    }
    if (n.contains('antique') ||
        n.contains('انتيك') ||
        n.contains('onteak')) {
      return TextureCache.woodTextureAntique ?? TextureCache.woodTexture;
    }
    return TextureCache.woodTexture;
  }

  static Color _glassTint(GlassSpecification glass) {
    final name = glass.colorOuter.name.toLowerCase();
    if (name.contains('blue') || name.contains('bleu')) {
      return const Color(0xFF4F8FC0);
    }
    if (name.contains('green') || name.contains('vert')) {
      return const Color(0xFF5FA98E);
    }
    if (name.contains('brown') || name.contains('bronze')) {
      return const Color(0xFF8C6E50);
    }
    if (name.contains('grey') || name.contains('gray') || name.contains('fum')) {
      return const Color(0xFF5E6670);
    }
    return const Color(0xFF9CC9DB);
  }

  static Color _panelColor(String? raw) {
    final clean = (raw ?? '').replaceAll('#', '').trim();
    final value = clean.length == 6 ? int.tryParse(clean, radix: 16) : null;
    return value == null ? const Color(0xFFF1F5F9) : Color(0xFF000000 | value);
  }
}
