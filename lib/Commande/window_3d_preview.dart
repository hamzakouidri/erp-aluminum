import 'dart:math' as math;

import 'package:flutter/gestures.dart' show PointerScrollEvent;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../settings/app_settings.dart';
import '../settings/localization.dart';
import 'Systeme/model.dart';

/// Lightweight interactive 3D preview generated from the same [WindowModel]
/// used by the technical drawing. Editing stays in 2D; this view is a visual
/// check. Frames are placed on walls in real 3D space, so two frames joined
/// by a 90° profile angle are shown as a corner window, and the roller
/// shutter (box, guide rails and curtain) is shown in front of the frames.
class Window3DPreview extends StatefulWidget {
  const Window3DPreview({super.key, required this.model});

  final WindowModel model;

  @override
  State<Window3DPreview> createState() => _Window3DPreviewState();
}

class _Window3DPreviewState extends State<Window3DPreview>
    with SingleTickerProviderStateMixin {
  // Seen from the front right, so both faces of a corner window show.
  static const _defaultYaw = -0.55;
  static const _defaultPitch = 0.22;
  double _yaw = _defaultYaw;
  double _pitch = _defaultPitch;
  double _zoom = 1;
  double _startYaw = _defaultYaw;
  double _startPitch = _defaultPitch;
  double _startZoom = 1;
  Offset _startFocal = Offset.zero;
  late final AnimationController _openingController;

  @override
  void initState() {
    super.initState();
    _openingController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
  }

  @override
  void dispose() {
    _openingController.dispose();
    super.dispose();
  }

  void _reset() => setState(() {
    _yaw = _defaultYaw;
    _pitch = _defaultPitch;
    _zoom = 1;
  });

  void _toggleOpening() {
    if (_openingController.isAnimating) {
      _openingController.stop();
    } else if (_openingController.value >= 0.99) {
      _openingController.reverse();
    } else {
      _openingController.forward();
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final lang = Provider.of<AppSettingsProvider>(context).language;
    String t(String key) => Localization.translate(key, lang);
    return Scaffold(
      backgroundColor: dark ? const Color(0xFF111827) : const Color(0xFFF1F5F9),
      appBar: AppBar(
        title: Text(t('معاينة ثلاثية الأبعاد')),
        actions: [
          IconButton(
            tooltip: t('إعادة ضبط المنظور'),
            onPressed: _reset,
            icon: const Icon(Icons.center_focus_strong_rounded),
          ),
          AnimatedBuilder(
            animation: _openingController,
            builder: (context, _) => IconButton(
              tooltip: _openingController.isAnimating
                  ? t('إيقاف الحركة')
                  : _openingController.value > 0.5
                  ? t('إغلاق النافذة')
                  : t('فتح النافذة'),
              onPressed: _toggleOpening,
              icon: Icon(
                _openingController.isAnimating
                    ? Icons.pause_rounded
                    : _openingController.value > 0.5
                    ? Icons.door_back_door_outlined
                    : Icons.door_front_door_outlined,
              ),
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onDoubleTap: _reset,
              onScaleStart: (details) {
                _startYaw = _yaw;
                _startPitch = _pitch;
                _startZoom = _zoom;
                _startFocal = details.focalPoint;
              },
              onScaleUpdate: (details) {
                final movement = details.focalPoint - _startFocal;
                setState(() {
                  // Yaw is deliberately unbounded: the user can orbit through
                  // a complete 360° and continue rotating in either direction.
                  _yaw = _startYaw + movement.dx / 150;
                  _pitch = (_startPitch + movement.dy / 220).clamp(-1.3, 1.3);
                  _zoom = (_startZoom * details.scale).clamp(0.55, 2.6);
                });
              },
              child: Listener(
                onPointerSignal: (event) {
                  if (event is PointerScrollEvent) {
                    setState(() {
                      _zoom = (_zoom * (event.scrollDelta.dy > 0 ? 0.92 : 1.08))
                          .clamp(0.55, 2.6);
                    });
                  }
                },
                child: AnimatedBuilder(
                  animation: _openingController,
                  builder: (context, _) => CustomPaint(
                    painter: Window3DPainter(
                      model: widget.model,
                      yaw: _yaw,
                      pitch: _pitch,
                      zoom: _zoom,
                      openingProgress: Curves.easeInOut.transform(
                        _openingController.value,
                      ),
                      dark: dark,
                    ),
                  ),
                ),
              ),
            ),
          ),
          PositionedDirectional(
            start: 14,
            bottom: 14,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: (dark ? Colors.black : Colors.white).withValues(
                  alpha: 0.82,
                ),
                borderRadius: BorderRadius.circular(12),
                boxShadow: const [
                  BoxShadow(color: Colors.black26, blurRadius: 8),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Text(
                  t(
                    'اسحب للدوران 360° • اسحب عموديًا للأعلى والأسفل • قرّب بإصبعين',
                  ),
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A point or direction in millimetres. y points up, z towards the viewer of
/// the first wall (its outside).
class _V3 {
  const _V3(this.x, this.y, this.z);

  final double x;
  final double y;
  final double z;

  static const zero = _V3(0, 0, 0);
  static const up = _V3(0, 1, 0);

  _V3 operator +(_V3 o) => _V3(x + o.x, y + o.y, z + o.z);
  _V3 operator -(_V3 o) => _V3(x - o.x, y - o.y, z - o.z);
  _V3 operator *(double s) => _V3(x * s, y * s, z * s);
  double dot(_V3 o) => x * o.x + y * o.y + z * o.z;
  _V3 cross(_V3 o) =>
      _V3(y * o.z - z * o.y, z * o.x - x * o.z, x * o.y - y * o.x);
  double get length => math.sqrt(dot(this));
  _V3 get unit {
    final l = length;
    return l == 0 ? this : this * (1 / l);
  }
}

/// Places drawing coordinates (x to the right, y down, in mm) on a wall: a
/// frame run along [u] with its outside facing [n]. z is the depth along [n]
/// (0 = outer face of the frame, negative = into the room).
class _Wall {
  const _Wall({
    required this.origin,
    required this.u,
    required this.xStart,
    required this.height,
  });

  final _V3 origin;
  final _V3 u;
  final double xStart;
  final double height;

  _V3 get n => _V3(-u.z, 0, u.x);

  _V3 at(double x, double y, [double z = 0]) =>
      origin + u * (x - xStart) + _V3.up * (height - y) + n * z;
}

/// One planar polygon (with optional holes) of the scene.
class _Face {
  _Face(this.points, this.color, {this.holes = const [], this.normal});

  final List<_V3> points;
  final List<List<_V3>> holes;
  final Color color;

  /// Outward normal for back-face culling and shading; null draws both sides.
  final _V3? normal;

  _V3 get centroid {
    var sum = _V3.zero;
    for (final p in points) {
      sum = sum + p;
    }
    return sum * (1 / points.length);
  }
}

/// A group of faces sorted as one object (a frame, a sash, a shutter part).
/// Faces are drawn in list order, so each builder lists them back to front
/// for both viewing sides (culling removes the hidden ones).
class _Solid {
  _Solid(this.faces, {this.priority = 0});

  final List<_Face> faces;

  /// Tie-breaker for solids at the same depth (glass before profiles).
  final int priority;

  _V3 get centroid {
    var sum = _V3.zero;
    var count = 0;
    for (final face in faces) {
      for (final p in face.points) {
        sum = sum + p;
        count++;
      }
    }
    return count == 0 ? sum : sum * (1 / count);
  }
}

/// One frame on its wall with what it holds. Its parts are drawn in a fixed
/// order for the visible side, because a frame and its sashes share depths
/// that a plain depth sort cannot order.
class _Group {
  _Group(this.wall);

  final _Wall wall;
  final List<_Face> frameSides = [];
  _Face? front;
  _Face? back;

  /// Sashes, glass and handles inside the frame.
  final List<_Solid> contents = [];

  /// Parts outside the frame face (roller shutter) or standalone (corner tube).
  final List<_Solid> exterior = [];

  _V3 get centroid {
    var sum = _V3.zero;
    var count = 0;
    void add(_V3 p) {
      sum = sum + p;
      count++;
    }

    for (final face in [?front, ...frameSides]) {
      face.points.forEach(add);
    }
    if (count == 0) {
      for (final solid in [...contents, ...exterior]) {
        add(solid.centroid);
      }
    }
    return count == 0 ? sum : sum * (1 / count);
  }
}

class Window3DPainter extends CustomPainter {
  Window3DPainter({
    required this.model,
    required this.yaw,
    required this.pitch,
    required this.zoom,
    required this.openingProgress,
    required this.dark,
  }) : super(repaint: model.drawingRepaint);

  final WindowModel model;
  final double yaw;
  final double pitch;
  final double zoom;
  final double openingProgress;
  final bool dark;

  /// Depth of the outer frame, sash and roller-shutter box (mm).
  static const double frameDepth = 70;
  static const double sashDepth = 58;
  static const double guideRailWidth = 25;
  static const _light = _V3(-0.45, 0.65, 0.6);

  Color get _frameColor => _colorFromRow(model.selectedDbColor) ?? _namedColor;

  Color get _shutterColor =>
      _colorFromRow(model.effectiveShutterColor) ?? _frameColor;

  Color? _colorFromRow(Map<String, dynamic>? row) {
    final raw = row?['code']?.toString() ?? row?['hex']?.toString() ?? '';
    final clean = raw.replaceAll('#', '').trim();
    if (clean.length != 6) return null;
    final value = int.tryParse(clean, radix: 16);
    return value == null ? null : Color(0xFF000000 | value);
  }

  Color get _namedColor {
    final name = model.frameColor.name.toLowerCase();
    if (name.contains('black') || name.contains('noir')) {
      return const Color(0xFF25282B);
    }
    if (name.contains('brown') || name.contains('bronze')) {
      return const Color(0xFF6D4C41);
    }
    if (name.contains('gray') || name.contains('grey')) {
      return const Color(0xFF8B949E);
    }
    return const Color(0xFFE5E7EB);
  }

  // ---------------------------------------------------------------- walls

  /// Frames sorted left to right, each with the wall it stands on. A frame
  /// after an active 90° profile-angle junction turns the wall by 90°, with
  /// the square corner tube between the two frames.
  List<(Rect, _Wall)> _framesOnWalls(List<_Solid> solids) {
    final height = model.height.toDouble();
    final frames = List<Rect>.from(model.getFrameRects())
      ..sort((a, b) => a.left.compareTo(b.left));
    if (frames.isEmpty && !model.isShutterOnly) {
      frames.add(Rect.fromLTWH(0, 0, model.width, height));
    }
    final straight = _Wall(
      origin: _V3.zero,
      u: const _V3(1, 0, 0),
      xStart: 0,
      height: height,
    );
    if (frames.isEmpty) return const [];

    final turning = <int>{};
    if (model.viewAs90DegreeCorner) {
      final active = model.activeProfileAngleJunctions;
      for (final junction in model.getAdjacentFrameJunctions()) {
        if (!active.contains(junction.index)) continue;
        final second = frames.indexWhere(
          (f) => (f.left - junction.secondFrame.left).abs() < 0.5,
        );
        if (second > 0) turning.add(second);
      }
    }
    final tube = model.profileAngleTubeWidth;
    final result = <(Rect, _Wall)>[];
    var wall = straight;
    for (var i = 0; i < frames.length; i++) {
      final frame = frames[i];
      if (turning.contains(i)) {
        final previous = frames[i - 1];
        final corner = wall.at(previous.right, 0) - _V3.up * height;
        solids.add(
          _cuboid(
            corner,
            wall.u * tube,
            _V3.up * math.max(previous.height, frame.height),
            wall.n * -tube,
            _frameColor,
            originAtBottom: true,
            bottomY: height - math.max(previous.bottom, frame.bottom),
          ),
        );
        // Turn away from the viewer so the corner points outwards.
        final u = _V3(wall.u.z, 0, -wall.u.x);
        wall = _Wall(
          origin: corner + wall.u * tube + u * tube,
          u: u,
          xStart: frame.left,
          height: height,
        );
      }
      result.add((frame, wall));
    }

    // A profile angle at the outer end of a single frame (mode 1 right,
    // 2 left, 3 both): only the corner tube is shown.
    if (turning.isEmpty && model.activeProfileAngleJunctions.isEmpty) {
      final mode = model.profileAngleMode;
      final (firstRect, firstWall) = result.first;
      final (lastRect, lastWall) = result.last;
      if (mode == 1 || mode == 3) {
        solids.add(
          _cuboid(
            lastWall.at(lastRect.right, lastRect.bottom),
            lastWall.u * tube,
            _V3.up * lastRect.height,
            lastWall.n * -tube,
            _frameColor,
          ),
        );
      }
      if (mode == 2 || mode == 3) {
        solids.add(
          _cuboid(
            firstWall.at(firstRect.left, firstRect.bottom) - firstWall.u * tube,
            firstWall.u * tube,
            _V3.up * firstRect.height,
            firstWall.n * -tube,
            _frameColor,
          ),
        );
      }
    }
    return result;
  }

  _Wall _wallForX(List<(Rect, _Wall)> frames, double x) {
    for (final (rect, wall) in frames) {
      if (x >= rect.left - 1 && x <= rect.right + 1) return wall;
    }
    var best = frames.first;
    for (final entry in frames) {
      if (entry.$1.left <= x) best = entry;
    }
    return best.$2;
  }

  // ------------------------------------------------------------- builders

  /// An axis-aligned box from [origin] spanned by [a], [b], [c] (each a
  /// direction times its length). With [originAtBottom] the box is lifted to
  /// [bottomY] above the wall base.
  _Solid _cuboid(
    _V3 origin,
    _V3 a,
    _V3 b,
    _V3 c,
    Color color, {
    bool originAtBottom = false,
    double bottomY = 0,
  }) {
    final o = originAtBottom ? origin + _V3.up * bottomY : origin;
    final p000 = o;
    final p100 = o + a;
    final p010 = o + b;
    final p110 = o + a + b;
    final p001 = o + c;
    final p101 = o + a + c;
    final p011 = o + b + c;
    final p111 = o + a + b + c;
    // Orient every normal away from the box centre.
    final centre = o + (a + b + c) * 0.5;
    _Face face(List<_V3> pts) {
      final f = _Face(pts, color);
      final normal = (f.centroid - centre).unit;
      return _Face(pts, color, normal: normal);
    }

    return _Solid([
      face([p000, p100, p110, p010]),
      face([p001, p101, p111, p011]),
      face([p000, p001, p011, p010]),
      face([p100, p101, p111, p110]),
      face([p000, p100, p101, p001]),
      face([p010, p110, p111, p011]),
    ]);
  }

  List<_V3> _rect(_Wall wall, Rect r, double z) => [
    wall.at(r.left, r.top, z),
    wall.at(r.right, r.top, z),
    wall.at(r.right, r.bottom, z),
    wall.at(r.left, r.bottom, z),
  ];

  /// A profile ring: an outer rectangle with holes, extruded from depth
  /// [zFront] to [zBack]. Listed back to front for either viewing side:
  /// reveals, then the far face, then the near face (culling keeps one).
  List<_Face> _ring(
    _Wall wall,
    Rect outer,
    List<Rect> holes,
    double zFront,
    double zBack,
    Color color, {
    _V3 Function(_V3 p)? transform,
  }) {
    _V3 tr(_V3 p) => transform == null ? p : transform(p);
    List<_V3> quad(List<_V3> pts) => pts.map(tr).toList();
    final n = wall.n;
    final faces = <_Face>[];
    // Outer sides.
    final front = _rect(wall, outer, zFront);
    final back = _rect(wall, outer, zBack);
    final sideNormals = [_V3.up, wall.u, _V3.up * -1, wall.u * -1];
    for (var i = 0; i < 4; i++) {
      final j = (i + 1) % 4;
      faces.add(
        _Face(
          quad([front[i], front[j], back[j], back[i]]),
          color,
          normal: transform == null ? sideNormals[i] : null,
        ),
      );
    }
    // Hole reveals face the hole centre.
    for (final hole in holes) {
      final hf = _rect(wall, hole, zFront);
      final hb = _rect(wall, hole, zBack);
      final revealNormals = [_V3.up * -1, wall.u * -1, _V3.up, wall.u];
      for (var i = 0; i < 4; i++) {
        final j = (i + 1) % 4;
        faces.add(
          _Face(
            quad([hf[i], hf[j], hb[j], hb[i]]),
            Color.lerp(color, Colors.black, 0.12)!,
            normal: transform == null ? revealNormals[i] : null,
          ),
        );
      }
    }
    final holesFront = [for (final h in holes) quad(_rect(wall, h, zFront))];
    final holesBack = [for (final h in holes) quad(_rect(wall, h, zBack))];
    _V3 normalOf(_V3 base) =>
        transform == null ? base : (tr(base) - tr(_V3.zero)).unit;
    faces.add(
      _Face(quad(back), color, holes: holesBack, normal: normalOf(n * -1)),
    );
    faces.add(_Face(quad(front), color, holes: holesFront, normal: normalOf(n)));
    return faces;
  }

  Color _glassColor(GlassSpecification glass) {
    if (glass.structure == GlassStructure.closed) {
      final clean = (glass.panneauColor ?? '').replaceAll('#', '').trim();
      final value = clean.length == 6 ? int.tryParse(clean, radix: 16) : null;
      return value == null ? const Color(0xFFF1F5F9) : Color(0xFF000000 | value);
    }
    final name = glass.colorOuter.name.toLowerCase();
    if (name.contains('blue') || name.contains('bleu')) {
      return const Color(0x8860A5D8);
    }
    if (name.contains('green') || name.contains('vert')) {
      return const Color(0x8874B9A2);
    }
    if (name.contains('brown') || name.contains('bronze')) {
      return const Color(0x889C8062);
    }
    return const Color(0x887EC8E3);
  }

  _Face _pane(_Wall wall, Rect r, double z, GlassSpecification glass) =>
      _Face(_rect(wall, r, z), _glassColor(glass));

  /// Rotation of [p] around the axis through [pivot] along [axis].
  _V3 _rotate(_V3 p, _V3 pivot, _V3 axis, double angle) {
    final k = axis.unit;
    final v = p - pivot;
    final c = math.cos(angle);
    final s = math.sin(angle);
    final rotated = v * c + k.cross(v) * s + k * (k.dot(v) * (1 - c));
    return pivot + rotated;
  }

  void _addZone(List<_Solid> solids, _Wall wall, WindowZone zone) {
    final r = zone.boundary;
    switch (zone.content) {
      case ZoneContent.empty:
        return;
      case ZoneContent.fixedGlass:
        solids.add(
          _Solid([_pane(wall, r, -frameDepth / 2, zone.glass)], priority: -1),
        );
        return;
      case ZoneContent.singleSash:
        _addCasement(solids, wall, zone, r, zone.openDirection);
        return;
      case ZoneContent.doubleSash:
        final split = r.left + r.width * zone.doubleSashRatio.clamp(0.2, 0.8);
        _addCasement(
          solids,
          wall,
          zone,
          Rect.fromLTRB(r.left, r.top, split, r.bottom),
          OpenDirection.left,
        );
        _addCasement(
          solids,
          wall,
          zone,
          Rect.fromLTRB(split, r.top, r.right, r.bottom),
          OpenDirection.right,
        );
        return;
      case ZoneContent.slidingSash:
        _addSlidingLeaves(solids, wall, zone, r);
        return;
    }
  }

  double _sashWidth(Rect r) =>
      math.min(62.0, math.min(r.width, r.height) * 0.22);

  void _addCasement(
    List<_Solid> solids,
    _Wall wall,
    WindowZone zone,
    Rect r,
    OpenDirection? hinge,
  ) {
    final zFront = -(frameDepth - sashDepth) / 2;
    final zBack = zFront - sashDepth;
    // The leaf swings into the room around its hinge side.
    final angle = openingProgress * (math.pi * 0.42);
    _V3 Function(_V3)? transform;
    if (angle > 0.001 && hinge != null) {
      final _V3 pivot;
      final _V3 axis;
      switch (hinge) {
        case OpenDirection.left:
          pivot = wall.at(r.left, r.bottom, zBack);
          axis = _V3.up;
        case OpenDirection.right:
          pivot = wall.at(r.right, r.bottom, zBack);
          axis = _V3.up * -1;
        case OpenDirection.top:
          pivot = wall.at(r.left, r.top, zBack);
          axis = wall.u * -1;
        case OpenDirection.bottom:
          pivot = wall.at(r.left, r.bottom, zBack);
          axis = wall.u;
      }
      final turn = hinge == OpenDirection.bottom ? angle * 0.35 : angle;
      transform = (p) => _rotate(p, pivot, axis, turn);
    }
    final profile = _sashWidth(r);
    final glassRect = r.deflate(profile);
    final glass = _pane(wall, glassRect, (zFront + zBack) / 2, zone.glass);
    final faces = _ring(
      wall,
      r,
      [glassRect],
      zFront,
      zBack,
      _frameColor,
      transform: transform,
    );
    final ring = faces.sublist(0, faces.length - 2);
    final big = faces.sublist(faces.length - 2);
    solids.add(
      _Solid([
        ...ring,
        big.first,
        _Face(
          transform == null ? glass.points : glass.points.map(transform).toList(),
          glass.color,
        ),
        big.last,
      ]),
    );
    final handle = _handle(wall, r, hinge, zBack, transform);
    if (handle.isNotEmpty) solids.add(_Solid(handle, priority: 1));
  }

  /// The handle sits on the room side, opposite the hinge.
  List<_Face> _handle(
    _Wall wall,
    Rect r,
    OpenDirection? hinge,
    double zBack,
    _V3 Function(_V3)? transform,
  ) {
    if (hinge == null) return const [];
    final inset = _sashWidth(r) / 2;
    final (double x, double y) = switch (hinge) {
      OpenDirection.left => (r.right - inset, r.center.dy),
      OpenDirection.right => (r.left + inset, r.center.dy),
      OpenDirection.top => (r.center.dx, r.bottom - inset),
      OpenDirection.bottom => (r.center.dx, r.top + inset),
    };
    final box = _cuboid(
      wall.at(x - 12, y + 75, zBack),
      wall.u * 24,
      _V3.up * 150,
      wall.n * -45,
      const Color(0xFF374151),
    );
    if (transform == null) return box.faces;
    return [
      for (final f in box.faces)
        _Face(f.points.map(transform).toList(), f.color),
    ];
  }

  void _addSlidingLeaves(
    List<_Solid> solids,
    _Wall wall,
    WindowZone zone,
    Rect r,
  ) {
    final count = math.max(1, zone.slidingSashesCount);
    final tracks = math.max(1, zone.slidingTrackCount);
    final trackDepth = frameDepth / (tracks + 0.5);
    const overlap = 30.0;
    final width = (r.width + overlap * (count - 1)) / count;
    for (var i = 0; i < count; i++) {
      final left = r.left + i * (width - overlap);
      // Alternate leaves run on alternate tracks and slide towards each other.
      final track = i % tracks;
      final direction = i.isEven ? 1.0 : -1.0;
      final shift = direction * width * 0.42 * openingProgress;
      final leaf = Rect.fromLTWH(left + shift, r.top, width, r.height);
      final zFront = -trackDepth * (track + 0.25);
      final zBack = zFront - trackDepth * 0.7;
      final profile = _sashWidth(leaf);
      final glassRect = leaf.deflate(profile);
      final faces = _ring(wall, leaf, [glassRect], zFront, zBack, _frameColor);
      solids.add(
        _Solid([
          ...faces.sublist(0, faces.length - 2),
          faces[faces.length - 2],
          _pane(wall, glassRect, (zFront + zBack) / 2, zone.glass),
          faces.last,
        ]),
      );
    }
  }

  void _addShutter(List<_Group> groups, List<(Rect, _Wall)> frames) {
    if (!model.hasShutter || frames.isEmpty) return;
    final height = model.height.toDouble();
    final tunnel = model.isCaissonTunnel;
    final box = model.shutterBoxHeight;
    final color = _shutterColor;
    final splits = model.effectiveShutterSplits;
    final sections = splits.isEmpty
        ? [
            ShutterSplitSection(
              width: model.width.toDouble(),
              leftOffset: 0,
              label: '',
            ),
          ]
        : splits;
    for (var s = 0; s < sections.length; s++) {
      final split = sections[s];
      final left = split.leftOffset;
      final right = left + split.width;
      final wall = _wallForX(frames, (left + right) / 2);
      final solids = groups
          .firstWhere(
            (group) => identical(group.wall, wall),
            orElse: () {
              final group = _Group(wall);
              groups.add(group);
              return group;
            },
          )
          .exterior;
      final bottom = split.customHeight ?? height;
      // The curtain runs in front of the frames; a tunnel box sits above
      // the frame, an ordinary box inside the window height.
      final boxTop = tunnel ? -box : 0.0;
      final boxBottom = tunnel ? 0.0 : box;
      final boxDepth = tunnel ? frameDepth * 2.6 : math.max(box, frameDepth);
      solids.add(
        _cuboid(
          wall.at(left, boxBottom, tunnel ? frameDepth * 0.6 : boxDepth),
          wall.u * (right - left),
          _V3.up * (boxBottom - boxTop),
          wall.n * -boxDepth,
          tunnel ? const Color(0xFFBFDDF2) : color,
        ),
      );
      final railDepth = 30.0;
      final zRail = 8.0 + railDepth;
      final drawLeft = s > 0 || !model.removedShutterSides.contains('left');
      final drawRight =
          s < sections.length - 1 ||
          !model.removedShutterSides.contains('right');
      if (drawLeft) {
        solids.add(
          _cuboid(
            wall.at(left, bottom, zRail),
            wall.u * guideRailWidth,
            _V3.up * (bottom - boxBottom),
            wall.n * -railDepth,
            color,
          ),
        );
      }
      if (drawRight) {
        solids.add(
          _cuboid(
            wall.at(right - guideRailWidth, bottom, zRail),
            wall.u * guideRailWidth,
            _V3.up * (bottom - boxBottom),
            wall.n * -railDepth,
            color,
          ),
        );
      }
      // The curtain is lowered to the drawn position, raised while the
      // preview opens the window.
      final drop =
          (bottom - boxBottom) *
          model.shutterPosition.clamp(0.0, 1.0) *
          (1 - openingProgress);
      if (drop > 2) {
        final curtain = Rect.fromLTRB(
          left + guideRailWidth * 0.5,
          boxBottom,
          right - guideRailWidth * 0.5,
          boxBottom + drop,
        );
        final zCurtain = 8.0 + railDepth / 2;
        final slats = <_Face>[
          _Face(
            _rect(wall, curtain, zCurtain),
            Color.lerp(color, Colors.white, 0.06)!,
          ),
        ];
        // Slat joints every 40 mm.
        for (var y = curtain.top + 40; y < curtain.bottom; y += 40) {
          slats.add(
            _Face(
              _rect(
                wall,
                Rect.fromLTRB(curtain.left, y - 1.5, curtain.right, y + 1.5),
                zCurtain + 0.5,
              ),
              Color.lerp(color, Colors.black, 0.3)!,
            ),
          );
        }
        solids.add(_Solid(slats, priority: 1));
      }
    }
  }

  List<_Group> _buildScene() {
    final posts = <_Solid>[];
    final frames = _framesOnWalls(posts);
    final groups = <_Group>[];
    if (!model.isShutterOnly) {
      for (final (rect, wall) in frames) {
        final group = _Group(wall);
        final zones = model.zones
            .where((z) => rect.contains(z.boundary.center))
            .toList();
        final ring = _ring(
          wall,
          rect,
          [for (final z in zones) z.boundary.intersect(rect)],
          0,
          -frameDepth,
          _frameColor,
        );
        group.frameSides.addAll(ring.sublist(0, ring.length - 2));
        group.back = ring[ring.length - 2];
        group.front = ring.last;
        for (final zone in zones) {
          _addZone(group.contents, wall, zone);
        }
        groups.add(group);
      }
    }
    for (final post in posts) {
      groups.add(_Group(frames.first.$2)..exterior.add(post));
    }
    _addShutter(groups, frames);
    return groups;
  }

  // ------------------------------------------------------------ rendering

  @override
  void paint(Canvas canvas, Size size) {
    if (model.width <= 0 || model.height <= 0) return;
    _paintBackdrop(canvas, size);
    final groups = _buildScene();
    if (groups.isEmpty) return;

    var minV = const _V3(double.infinity, double.infinity, double.infinity);
    var maxV = const _V3(
      double.negativeInfinity,
      double.negativeInfinity,
      double.negativeInfinity,
    );
    void extend(_Face face) {
      for (final p in face.points) {
        minV = _V3(
          math.min(minV.x, p.x),
          math.min(minV.y, p.y),
          math.min(minV.z, p.z),
        );
        maxV = _V3(
          math.max(maxV.x, p.x),
          math.max(maxV.y, p.y),
          math.max(maxV.z, p.z),
        );
      }
    }

    for (final group in groups) {
      [?group.front, ...group.frameSides].forEach(extend);
      for (final solid in [...group.contents, ...group.exterior]) {
        solid.faces.forEach(extend);
      }
    }
    if (!minV.x.isFinite) return;
    final centre = (minV + maxV) * 0.5;
    final radius = math.max(1.0, (maxV - minV).length / 2);
    final distance = radius * 3.2;
    final fit =
        math.min(size.width, size.height - 40) * 0.5 / radius * 1.05 * zoom;
    final cy = math.cos(yaw), sy = math.sin(yaw);
    final cp = math.cos(pitch), sp = math.sin(pitch);

    _V3 dirToCamera(_V3 d) {
      final x1 = d.x * cy + d.z * sy;
      final z1 = -d.x * sy + d.z * cy;
      return _V3(x1, d.y * cp - z1 * sp, d.y * sp + z1 * cp);
    }

    _V3 toCamera(_V3 p) => dirToCamera(p - centre);

    final screenCentre = Offset(size.width / 2, size.height / 2 + 8);
    Offset project(_V3 c) {
      final s = distance / math.max(radius * 0.2, distance - c.z);
      return screenCentre + Offset(c.x * s * fit, -c.y * s * fit);
    }

    final eye = _V3(0, 0, distance);
    bool facesCamera(_V3 normal, _V3 point) =>
        dirToCamera(normal).dot(eye - toCamera(point)) > 0;
    double depth(_V3 p) => toCamera(p).z;
    List<_Solid> byDepth(List<_Solid> solids) => solids.toList()
      ..sort((a, b) {
        final da = depth(a.centroid);
        final db = depth(b.centroid);
        if ((da - db).abs() > 1.0) return da.compareTo(db);
        return a.priority.compareTo(b.priority);
      });

    _paintShadow(canvas, groups, toCamera, project);
    final lightDir = _light.unit;
    void drawFace(_Face face) {
      final cam = face.points.map(toCamera).toList();
      var color = face.color;
      if (face.normal != null) {
        if (dirToCamera(face.normal!).dot(eye - cam.first) <= 0) return;
        final lambert = face.normal!.dot(lightDir).clamp(-1.0, 1.0);
        color = Color.lerp(
          color,
          lambert >= 0 ? Colors.white : Colors.black,
          lambert >= 0 ? lambert * 0.12 : -lambert * 0.38,
        )!;
      }
      final path = Path()..fillType = PathFillType.evenOdd;
      path.addPolygon(cam.map(project).toList(), true);
      for (final hole in face.holes) {
        path.addPolygon(hole.map((p) => project(toCamera(p))).toList(), true);
      }
      canvas.drawPath(path, Paint()..color = color);
      if (color.a > 0.9) {
        canvas.drawPath(
          path,
          Paint()
            ..color = Color.lerp(color, Colors.black, 0.35)!
            ..style = PaintingStyle.stroke
            ..strokeWidth = 0.8,
        );
      }
    }

    void drawSolids(List<_Solid> solids) {
      for (final solid in byDepth(solids)) {
        solid.faces.forEach(drawFace);
      }
    }

    final orderedGroups = groups.toList()
      ..sort((a, b) => depth(a.centroid).compareTo(depth(b.centroid)));
    for (final group in orderedGroups) {
      final front = group.front;
      final outside = front == null
          ? true
          : facesCamera(group.wall.n, front.points.first);
      if (outside) {
        // Outside: frame reveals, what the frame holds, its face, then the
        // shutter in front of it.
        group.frameSides.forEach(drawFace);
        drawSolids(group.contents);
        if (front != null) drawFace(front);
        drawSolids(group.exterior);
      } else {
        // Room side: the shutter is behind; an open sash comes towards the
        // viewer, so it is drawn after the frame's room face.
        drawSolids(group.exterior);
        group.frameSides.forEach(drawFace);
        if (group.back != null) drawFace(group.back!);
        drawSolids(group.contents);
      }
    }
  }

  /// A soft floor shadow under each frame, from its outside to the room.
  void _paintShadow(
    Canvas canvas,
    List<_Group> groups,
    _V3 Function(_V3) toCamera,
    Offset Function(_V3) project,
  ) {
    final paint = Paint()
      ..color = Colors.black.withValues(alpha: 0.16)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
    for (final group in groups) {
      final front = group.front;
      if (front == null) continue;
      final floor = front.points.map((p) => p.y).reduce(math.min);
      final base = front.points
          .where((p) => (p.y - floor).abs() < 0.5)
          .toList(growable: false);
      if (base.length < 2) continue;
      final n = group.wall.n;
      final quad = [
        base[0] + n * 140,
        base[1] + n * 140,
        base[1] - n * (frameDepth + 90),
        base[0] - n * (frameDepth + 90),
      ];
      canvas.drawPath(
        Path()..addPolygon(quad.map((p) => project(toCamera(p))).toList(), true),
        paint,
      );
    }
  }

  void _paintBackdrop(Canvas canvas, Size size) {
    final bg = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: dark
            ? const [Color(0xFF071A33), Color(0xFF0D4C73), Color(0xFF0B7189)]
            : const [Color(0xFF75C9FF), Color(0xFFBDE9FF), Color(0xFF168AAD)],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, bg);
    final horizon = size.height * 0.62;
    final groundRect = Rect.fromLTWH(
      0,
      horizon,
      size.width,
      size.height - horizon,
    );
    canvas.drawRect(
      groundRect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: dark
              ? const [Color(0xFF16324A), Color(0xFF0B1A28)]
              : const [Color(0xFFCFD8DC), Color(0xFF90A4AE)],
        ).createShader(groundRect),
    );
  }

  @override
  bool shouldRepaint(covariant Window3DPainter oldDelegate) =>
      oldDelegate.model != model ||
      oldDelegate.yaw != yaw ||
      oldDelegate.pitch != pitch ||
      oldDelegate.zoom != zoom ||
      oldDelegate.openingProgress != openingProgress ||
      oldDelegate.dark != dark;
}
