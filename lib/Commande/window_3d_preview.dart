import 'dart:math' as math;

import 'package:flutter/gestures.dart' show PointerScrollEvent;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../settings/app_settings.dart';
import '../settings/localization.dart';
import 'Systeme/model.dart';

/// Interactive 3D preview generated from the same [WindowModel] used by the
/// technical drawing. Editing stays in 2D; this view is a visual check.
///
/// The drawing is read as seen from the room (the drawing's default internal
/// view): the handle of a casement is on its `openDirection` side and its
/// hinges on the opposite side, exactly as the 2D drawing places them. The
/// preview opens on the room side, in a wall overlooking the sea; turning
/// round shows the outside with the shutter, the mosquito net and the drain
/// slots of the bottom frame.
class Window3DPreview extends StatefulWidget {
  const Window3DPreview({super.key, required this.model});

  final WindowModel model;

  @override
  State<Window3DPreview> createState() => _Window3DPreviewState();
}

class _Window3DPreviewState extends State<Window3DPreview>
    with SingleTickerProviderStateMixin {
  // Seen from the room, slightly from the left: the depth shows, and a
  // corner window (which turns towards the room on the right) shows both of
  // its room faces.
  static const _defaultYaw = 0.42;
  static const _defaultPitch = 0.12;
  double _yaw = _defaultYaw;
  double _pitch = _defaultPitch;
  double _zoom = 1;
  double _startYaw = _defaultYaw;
  double _startPitch = _defaultPitch;
  double _startZoom = 1;
  Offset _startFocal = Offset.zero;
  bool _showWall = true;
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

  /// Turns the view to face the room side or the outside straight on.
  void _face({required bool outside}) => setState(() {
    _yaw = outside ? math.pi : 0;
    _pitch = 0;
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
      backgroundColor: const Color(0xFF7CC7F5),
      appBar: AppBar(
        title: Text(t('معاينة ثلاثية الأبعاد')),
        actions: [
          IconButton(
            tooltip: t('الواجهة الداخلية'),
            onPressed: () => _face(outside: false),
            icon: const Icon(Icons.chair_outlined),
          ),
          IconButton(
            tooltip: t('الواجهة الخارجية'),
            onPressed: () => _face(outside: true),
            icon: const Icon(Icons.wb_sunny_outlined),
          ),
          IconButton(
            tooltip: _showWall ? t('إخفاء الجدار') : t('إظهار الجدار'),
            onPressed: () => setState(() => _showWall = !_showWall),
            icon: Icon(
              _showWall ? Icons.wallpaper_rounded : Icons.crop_free_rounded,
            ),
          ),
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
                  _zoom = (_startZoom * details.scale).clamp(0.55, 3.2);
                });
              },
              child: Listener(
                onPointerSignal: (event) {
                  if (event is PointerScrollEvent) {
                    setState(() {
                      _zoom = (_zoom * (event.scrollDelta.dy > 0 ? 0.92 : 1.08))
                          .clamp(0.55, 3.2);
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
                      showWall: _showWall,
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
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
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

/// A point or direction in millimetres. y points up.
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

/// Places drawing coordinates (x to the right as seen from the room, y down,
/// in mm) on a wall: a frame run along [u] with its outside facing [n]. z is
/// the depth along [n]: 0 = outer face of the frame, negative = towards the
/// room. With u = +x the room is on +z, so a camera on the room side sees the
/// drawing the right way round.
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

  _V3 get n => _V3(u.z, 0, -u.x);

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

  _Face map(_V3 Function(_V3) f) => _Face(
    points.map(f).toList(),
    color,
    holes: [for (final h in holes) h.map(f).toList()],
    normal: normal == null ? null : (f(normal!) - f(_V3.zero)).unit,
  );
}

/// A group of faces sorted as one object (a frame, a sash, a shutter part).
///
/// [faces] are drawn in list order (culling removes the hidden ones). A
/// solid made of several depth layers (a sash: room lip, body, glass, outer
/// rebate) lists them in [layers] from the room side to the outside; they are
/// drawn far to near for whichever side the camera is on.
class _Solid {
  _Solid(this.faces, {this.priority = 0}) : layers = null, outward = null;

  _Solid.layered(List<List<_Face>> this.layers, _V3 this.outward)
    : faces = [for (final layer in layers) ...layer],
      priority = 0;

  final List<_Face> faces;
  final List<List<_Face>>? layers;
  final _V3? outward;

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

  /// Sashes and glass inside the frame.
  final List<_Solid> contents = [];

  /// Hinges and handles on the room side. They are drawn after the sashes
  /// from the room and before them from outside: a depth sort by centre
  /// would put a handle on a stile behind the middle of its own sash.
  final List<_Solid> hardware = [];

  /// Parts outside the frame face (shutter, mosquito net, drain slots) or
  /// standalone (corner tube).
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

/// The masonry around the frames of one wall, with its two sills.
class _WallSlab {
  _WallSlab({
    required this.sides,
    required this.outer,
    required this.inner,
    required this.innerSill,
    required this.outerSill,
  });

  /// Edges and opening reveals.
  final List<_Face> sides;
  final _Face outer;
  final _Face inner;
  final _Solid innerSill;
  final _Solid outerSill;
}

class Window3DPainter extends CustomPainter {
  Window3DPainter({
    required this.model,
    required this.yaw,
    required this.pitch,
    required this.zoom,
    required this.openingProgress,
    required this.dark,
    this.showWall = true,
  }) : super(repaint: model.drawingRepaint);

  final WindowModel model;
  final double yaw;
  final double pitch;
  final double zoom;
  final double openingProgress;
  final bool dark;
  final bool showWall;

  /// Depths (mm, along the outward normal from the frame's outer face).
  static const double frameDepth = 70;
  static const double sashOuterZ = -8;
  static const double sashRoomZ = -84;
  static const double glassZ = -40;
  static const double guideRailWidth = 25;
  static const double wallRoomZ = -210;

  static const _gasket = Color(0xFF15171A);
  static const _wallInside = Color(0xFFF3EEE6);
  static const _wallOutside = Color(0xFFE6D8BF);
  static const _innerSillColor = Color(0xFFE9E6E1);
  static const _outerSillColor = Color(0xFFCFC6B8);

  static Color _middle(List<Color> colors) => colors[colors.length ~/ 2];

  Color get _frameColor => _middle(
    getEffectiveGradientColors(model.frameColor, model.selectedDbColor),
  );

  Color _sashColor(WindowZone zone) => Color.lerp(
    _middle(
      getEffectiveGradientColors(
        zone.sashColor,
        zone.selectedDbColor ?? model.selectedDbColor,
      ),
    ),
    Colors.black,
    0.035,
  )!;

  Color get _shutterColor =>
      _colorFromRow(model.effectiveShutterColor) ?? _frameColor;

  Color get _hardwareColor {
    final accessory = model.accessoryColor;
    return accessory.computeLuminance() > 0.62
        ? const Color(0xFFB8BEC6)
        : Color.lerp(accessory, Colors.black, 0.12)!;
  }

  Color? _colorFromRow(Map<String, dynamic>? row) {
    final raw = row?['code']?.toString() ?? row?['hex']?.toString() ?? '';
    final clean = raw.replaceAll('#', '').trim();
    if (clean.length != 6) return null;
    final value = int.tryParse(clean, radix: 16);
    return value == null ? null : Color(0xFF000000 | value);
  }

  double get _sashProfile =>
      model.getSectionThickness('sash', fallback: 62).clamp(35.0, 120.0);

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
        // Turn towards the room, so the corner points outwards.
        final u = _V3(-wall.u.z, 0, wall.u.x);
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

  /// Depth of the wall's outer face: deep enough to hold the shutter box.
  double get _wallOuterZ {
    if (!model.hasShutter) return 110;
    final box = model.isCaissonTunnel
        ? frameDepth * 0.6
        : math.max(model.shutterBoxHeight, frameDepth);
    return math.max(110, box + 12);
  }

  /// One masonry slab per wall, with an opening around its frames.
  List<_WallSlab> _wallSlabs(List<(Rect, _Wall)> frames) {
    final slabs = <_WallSlab>[];
    final walls = <_Wall>[];
    for (final (_, wall) in frames) {
      if (!walls.any((w) => identical(w, wall))) walls.add(wall);
    }
    final tunnelBox = model.hasShutter && model.isCaissonTunnel
        ? model.shutterBoxHeight
        : 0.0;
    for (var i = 0; i < walls.length; i++) {
      final wall = walls[i];
      final rects = [
        for (final (rect, w) in frames)
          if (identical(w, wall)) rect,
      ];
      var opening = rects.first;
      for (final rect in rects.skip(1)) {
        opening = opening.expandToInclude(rect);
      }
      // A tunnel box sits above the frames; an ordinary box inside the
      // window height. Either stays inside the opening.
      final top = model.hasShutter && !model.isCaissonTunnel
          ? math.min(opening.top, 0.0)
          : opening.top - tunnelBox;
      opening = Rect.fromLTRB(opening.left, top, opening.right, opening.bottom);
      // A corner leaves no masonry between its two walls.
      final leftMargin = i == 0 ? 750.0 : 0.0;
      final rightMargin = i == walls.length - 1 ? 750.0 : 0.0;
      final outer = Rect.fromLTRB(
        opening.left - leftMargin,
        opening.top - 650,
        opening.right + rightMargin,
        opening.bottom + 520,
      );
      final zOut = _wallOuterZ;
      final faces = _ring(wall, outer, [opening], zOut, wallRoomZ, _wallInside);
      final sides = faces.sublist(0, faces.length - 2);
      final inner = faces[faces.length - 2];
      final outerFace = faces.last;
      // Marble sill in the room, stone sill outside, both under the opening.
      final innerSill = _cuboid(
        wall.at(opening.left - 45, opening.bottom + 28, wallRoomZ),
        wall.u * (opening.width + 90),
        _V3.up * 28,
        wall.n * -55,
        _innerSillColor,
      );
      final outerSill = _cuboid(
        wall.at(opening.left - 35, opening.bottom + 40, zOut + 45),
        wall.u * (opening.width + 70),
        _V3.up * 40,
        wall.n * -(zOut + 45),
        _outerSillColor,
      );
      slabs.add(
        _WallSlab(
          sides: sides,
          inner: inner,
          outer: _Face(
            outerFace.points,
            _wallOutside,
            holes: outerFace.holes,
            normal: outerFace.normal,
          ),
          innerSill: innerSill,
          outerSill: outerSill,
        ),
      );
    }
    return slabs;
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
    int priority = 0,
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
    ], priority: priority);
  }

  /// A box on [wall] covering [r] (drawing mm) from depth [zA] to [zB].
  _Solid _block(
    _Wall wall,
    Rect r,
    double zA,
    double zB,
    Color color, {
    int priority = 1,
  }) => _cuboid(
    wall.at(r.left, r.bottom, zA),
    wall.u * r.width,
    _V3.up * r.height,
    wall.n * (zB - zA),
    color,
    priority: priority,
  );

  List<_V3> _rect(_Wall wall, Rect r, double z) => [
    wall.at(r.left, r.top, z),
    wall.at(r.right, r.top, z),
    wall.at(r.right, r.bottom, z),
    wall.at(r.left, r.bottom, z),
  ];

  /// A profile ring: an outer rectangle with holes, extruded from depth
  /// [zFront] (outside) to [zBack] (room side). Listed back to front for
  /// either viewing side: sides and reveals, then the room face, then the
  /// outer face (culling keeps the visible one).
  List<_Face> _ring(
    _Wall wall,
    Rect outer,
    List<Rect> holes,
    double zFront,
    double zBack,
    Color color,
  ) {
    final n = wall.n;
    final faces = <_Face>[];
    final front = _rect(wall, outer, zFront);
    final back = _rect(wall, outer, zBack);
    final sideNormals = [_V3.up, wall.u, _V3.up * -1, wall.u * -1];
    for (var i = 0; i < 4; i++) {
      final j = (i + 1) % 4;
      faces.add(
        _Face(
          [front[i], front[j], back[j], back[i]],
          color,
          normal: sideNormals[i],
        ),
      );
    }
    // Hole reveals face the hole centre, a shade darker than the faces.
    for (final hole in holes) {
      final hf = _rect(wall, hole, zFront);
      final hb = _rect(wall, hole, zBack);
      final revealNormals = [_V3.up * -1, wall.u * -1, _V3.up, wall.u];
      for (var i = 0; i < 4; i++) {
        final j = (i + 1) % 4;
        faces.add(
          _Face(
            [hf[i], hf[j], hb[j], hb[i]],
            Color.lerp(color, Colors.black, 0.14)!,
            normal: revealNormals[i],
          ),
        );
      }
    }
    faces.add(
      _Face(
        back,
        color,
        holes: [for (final h in holes) _rect(wall, h, zBack)],
        normal: n * -1,
      ),
    );
    faces.add(
      _Face(
        front,
        color,
        holes: [for (final h in holes) _rect(wall, h, zFront)],
        normal: n,
      ),
    );
    return faces;
  }

  Color _glassColor(GlassSpecification glass) {
    if (glass.structure == GlassStructure.closed) {
      final clean = (glass.panneauColor ?? '').replaceAll('#', '').trim();
      final value = clean.length == 6 ? int.tryParse(clean, radix: 16) : null;
      return value == null
          ? const Color(0xFFF1F5F9)
          : Color(0xFF000000 | value);
    }
    final name = glass.colorOuter.name.toLowerCase();
    if (name.contains('blue') || name.contains('bleu')) {
      return const Color(0x7760A5D8);
    }
    if (name.contains('green') || name.contains('vert')) {
      return const Color(0x7774B9A2);
    }
    if (name.contains('brown') || name.contains('bronze')) {
      return const Color(0x889C8062);
    }
    return const Color(0x55A9DCF0);
  }

  /// The glass pane with its black gasket on both faces.
  List<_Face> _glazing(_Wall wall, Rect glass, double z, GlassSpecification g) {
    final pane = _Face(_rect(wall, glass, z), _glassColor(g));
    final gasketOuter = glass.inflate(4);
    _Face gasket(double dz) => _Face(
      _rect(wall, gasketOuter, z + dz),
      _gasket,
      holes: [_rect(wall, glass, z + dz)],
    );
    return [gasket(-6), pane, gasket(6)];
  }

  /// Rotation of [p] around the axis through [pivot] along [axis].
  _V3 _rotate(_V3 p, _V3 pivot, _V3 axis, double angle) {
    final k = axis.unit;
    final v = p - pivot;
    final c = math.cos(angle);
    final s = math.sin(angle);
    final rotated = v * c + k.cross(v) * s + k * (k.dot(v) * (1 - c));
    return pivot + rotated;
  }

  void _addZone(_Group group, _Wall wall, WindowZone zone) {
    final r = zone.boundary;
    final solids = group.contents;
    switch (zone.content) {
      case ZoneContent.empty:
        return;
      case ZoneContent.fixedGlass:
        _addFixedGlass(solids, wall, zone, r);
        return;
      case ZoneContent.singleSash:
        final handleSide = zone.openDirection;
        _addCasement(
          group,
          wall,
          zone,
          r,
          hinge: handleSide == null ? null : _opposite(handleSide),
          handleSide: handleSide,
          isHandleSash: true,
        );
        return;
      case ZoneContent.doubleSash:
        // As in the drawing's internal view: the left leaf is hinged on the
        // left, the right leaf on the right, and the handle sits on the
        // meeting stile of the active leaf (right unless left is chosen).
        final split = r.left + r.width * zone.doubleSashRatio.clamp(0.15, 0.85);
        final leftActive = zone.openDirection == OpenDirection.left;
        final both = zone.doubleSashHasTwoHandles;
        _addCasement(
          group,
          wall,
          zone,
          Rect.fromLTRB(r.left, r.top, split - 2, r.bottom),
          hinge: OpenDirection.left,
          handleSide: both || leftActive ? OpenDirection.right : null,
          isHandleSash: leftActive,
          lag: leftActive ? 0 : 0.35,
        );
        _addCasement(
          group,
          wall,
          zone,
          Rect.fromLTRB(split + 2, r.top, r.right, r.bottom),
          hinge: OpenDirection.right,
          handleSide: both || !leftActive ? OpenDirection.left : null,
          isHandleSash: !leftActive,
          lag: leftActive ? 0.35 : 0,
        );
        return;
      case ZoneContent.slidingSash:
        _addSlidingLeaves(group, wall, zone, r);
        return;
    }
  }

  static OpenDirection _opposite(OpenDirection d) => switch (d) {
    OpenDirection.left => OpenDirection.right,
    OpenDirection.right => OpenDirection.left,
    OpenDirection.top => OpenDirection.bottom,
    OpenDirection.bottom => OpenDirection.top,
  };

  /// Fixed glass held in the frame: an outer stop, the pane and the room
  /// side glazing bead, which leaves a visible rebate.
  void _addFixedGlass(
    List<_Solid> solids,
    _Wall wall,
    WindowZone zone,
    Rect r,
  ) {
    const bead = 18.0;
    final glass = r.deflate(math.min(bead, math.min(r.width, r.height) / 4));
    const z = -frameDepth / 2;
    final color = _frameColor;
    final beadColor = Color.lerp(color, Colors.black, 0.06)!;
    solids.add(
      _Solid.layered([
        _ring(wall, r, [glass], z - 4, -frameDepth + 6, beadColor),
        _glazing(wall, glass, z, zone.glass),
        _ring(wall, r, [glass], -6, z + 4, color),
      ], wall.n),
    );
  }

  void _addCasement(
    _Group group,
    _Wall wall,
    WindowZone zone,
    Rect r, {
    required OpenDirection? hinge,
    required OpenDirection? handleSide,
    required bool isHandleSash,
    double lag = 0,
  }) {
    final roomward = wall.n * -1;
    final progress = ((openingProgress - lag) / (1 - lag)).clamp(0.0, 1.0);
    _V3 Function(_V3)? transform;
    if (progress > 0.001 && hinge != null) {
      late final _V3 pivot;
      late final _V3 axis;
      late final double angle;
      switch (hinge) {
        case OpenDirection.left:
          // Free edge at +u swings into the room.
          pivot = wall.at(r.left, r.bottom, sashRoomZ);
          axis = wall.u.cross(roomward);
          angle = progress * math.pi * 0.42;
        case OpenDirection.right:
          pivot = wall.at(r.right, r.bottom, sashRoomZ);
          axis = wall.u.cross(wall.n);
          angle = progress * math.pi * 0.42;
        case OpenDirection.bottom:
          // Bottom-hung (soufflet): the top tilts into the room.
          pivot = wall.at(r.left, r.bottom, sashRoomZ);
          axis = _V3.up.cross(roomward);
          angle = progress * 0.2;
        case OpenDirection.top:
          // Top-hung: the bottom projects outwards.
          pivot = wall.at(r.left, r.top, sashOuterZ);
          axis = _V3.up.cross(roomward);
          angle = progress * 0.45;
      }
      transform = (p) => _rotate(p, pivot, axis, angle);
    }

    final color = _sashColor(zone);
    final profile = math.min(_sashProfile, math.min(r.width, r.height) * 0.3);
    const bead = 16.0;
    final glassRect = r.deflate(profile);
    final beadRect = glassRect.inflate(bead);
    final overlap = model.openingSashOverlap > 0
        ? model.openingSashOverlap.clamp(4.0, 20.0)
        : 10.0;
    final layers = <List<_Face>>[
      // Room side glazing bead, slightly recessed in the sash.
      _ring(
        wall,
        beadRect,
        [glassRect],
        glassZ - 6,
        sashRoomZ + 5,
        Color.lerp(color, Colors.black, 0.07)!,
      ),
      // Room lip, which laps over the frame by the series overlap.
      _ring(
        wall,
        r.inflate(overlap),
        [beadRect],
        -frameDepth,
        sashRoomZ,
        color,
      ),
      // Body inside the frame opening, then the outer glazing rebate.
      _ring(wall, r, [beadRect], glassZ - 6, -frameDepth, color),
      _glazing(wall, glassRect, glassZ, zone.glass),
      _ring(wall, r, [glassRect], sashOuterZ, glassZ - 6, color),
    ];
    // Dark shadow line between the lip and the frame.
    layers.insert(1, [
      _Face(
        _rect(wall, r.inflate(overlap + 1.5), -frameDepth - 0.5),
        const Color(0x66000000),
        holes: [_rect(wall, r.inflate(overlap), -frameDepth - 0.5)],
        normal: roomward,
      ),
    ]);
    final mapped = transform == null
        ? layers
        : [
            for (final layer in layers)
              [for (final f in layer) f.map(transform)],
          ];
    final outward = transform == null
        ? wall.n
        : (transform(wall.n) - transform(_V3.zero)).unit;
    group.contents.add(_Solid.layered(mapped, outward));

    if (hinge != null) {
      _addHinges(group.hardware, wall, zone, r, hinge, isHandleSash, overlap);
    }
    if (handleSide != null) {
      final handle = _handle(wall, zone, r, handleSide);
      group.hardware.add(
        _Solid(
          transform == null
              ? handle
              : [for (final f in handle) f.map(transform)],
          priority: 2,
        ),
      );
    }
  }

  /// Hinges on the room side, on the frame/sash joint of the hinge side,
  /// counted and spaced like the drawing.
  void _addHinges(
    List<_Solid> solids,
    _Wall wall,
    WindowZone zone,
    Rect r,
    OpenDirection hinge,
    bool isHandleSash,
    double overlap,
  ) {
    var count = standardHingeCountForSash(
      sashHeight: zone.boundary.height,
      glassStructure: zone.glass.structure,
    );
    final ob = model.useSystemOB && isHandleSash;
    if (ob) count = 2;
    final inset = ob ? 44.0 : 100.0;
    final color = _hardwareColor;
    const knuckle = 16.0;
    const length = 80.0;
    final z0 = sashRoomZ + 4;
    final z1 = sashRoomZ - 14;
    final vertical =
        hinge == OpenDirection.left || hinge == OpenDirection.right;
    final start = vertical ? r.top + inset : r.left + inset;
    final end = vertical ? r.bottom - inset : r.right - inset;
    for (var i = 0; i < count; i++) {
      var pos = count == 1
          ? (start + end) / 2
          : start + (end - start) * i / (count - 1);
      if (count >= 3 && i == 1) pos += zone.middleHingeDragOffset;
      final Rect rect;
      if (vertical) {
        final x = hinge == OpenDirection.left
            ? r.left - overlap
            : r.right + overlap;
        rect = Rect.fromCenter(
          center: Offset(x, pos),
          width: knuckle,
          height: length,
        );
      } else {
        final y = hinge == OpenDirection.top
            ? r.top - overlap
            : r.bottom + overlap;
        rect = Rect.fromCenter(
          center: Offset(pos, y),
          width: length,
          height: knuckle,
        );
      }
      solids.add(_block(wall, rect, z0, z1, color, priority: 2));
      // The pin caps that split the two leaves of the hinge.
      final cap = vertical
          ? Rect.fromCenter(center: rect.center, width: knuckle + 2, height: 3)
          : Rect.fromCenter(center: rect.center, width: 3, height: knuckle + 2);
      solids.add(
        _block(
          wall,
          cap,
          z0 + 0.5,
          z1 - 0.5,
          Color.lerp(color, Colors.black, 0.45)!,
          priority: 3,
        ),
      );
    }
  }

  /// The handle on the room face of the sash, placed like the drawing: on
  /// [side], at the drawing's handle height, with its lock type's shape.
  List<_Face> _handle(_Wall wall, WindowZone zone, Rect r, OpenDirection side) {
    final ratio = (zone.handlePositionRatio ?? 0.5).clamp(0.05, 0.95);
    final inset = math.min(_sashProfile / 2, 30.0);
    final (double x, double y) = switch (side) {
      OpenDirection.left => (r.left + inset, r.top + r.height * (1 - ratio)),
      OpenDirection.right => (r.right - inset, r.top + r.height * (1 - ratio)),
      OpenDirection.top => (r.left + r.width * ratio, r.top + inset),
      OpenDirection.bottom => (r.left + r.width * ratio, r.bottom - inset),
    };
    final color = model.accessoryColor;
    final dark = Color.lerp(color, Colors.black, 0.35)!;
    final faces = <_Face>[];
    void block(Rect rect, double depth, Color c, {double from = 0}) {
      faces.addAll(
        _block(wall, rect, sashRoomZ - from, sashRoomZ - from - depth, c).faces,
      );
    }

    final horizontalEdge =
        side == OpenDirection.top || side == OpenDirection.bottom;
    switch (zone.lockType) {
      case LockType.point:
        // A small turn knob.
        block(
          Rect.fromCenter(center: Offset(x, y), width: 30, height: 30),
          8,
          color,
        );
        block(
          Rect.fromCenter(center: Offset(x, y), width: 14, height: 14),
          22,
          dark,
          from: 8,
        );
      case LockType.clef ||
          LockType.condamnation ||
          LockType.rouleau ||
          LockType.rouleau2000:
        // Door lock: long plate, lever and key cylinder.
        block(
          Rect.fromCenter(center: Offset(x, y + 40), width: 30, height: 230),
          7,
          color,
        );
        block(
          Rect.fromCenter(center: Offset(x, y), width: 18, height: 18),
          34,
          color,
          from: 7,
        );
        block(Rect.fromLTWH(x - 9, y - 9, 120, 18), 14, color, from: 27);
        block(
          Rect.fromCenter(center: Offset(x, y + 90), width: 16, height: 26),
          4,
          dark,
          from: 7,
        );
      default:
        // Window lever: rosette, stem, grip at rest (down, or sideways on a
        // top/bottom rail).
        if (horizontalEdge) {
          block(
            Rect.fromCenter(center: Offset(x, y), width: 72, height: 28),
            8,
            color,
          );
          block(
            Rect.fromCenter(center: Offset(x, y), width: 16, height: 16),
            26,
            color,
            from: 8,
          );
          block(Rect.fromLTWH(x - 9, y - 9, 115, 18), 14, color, from: 22);
        } else {
          block(
            Rect.fromCenter(center: Offset(x, y), width: 28, height: 72),
            8,
            color,
          );
          block(
            Rect.fromCenter(center: Offset(x, y), width: 16, height: 16),
            26,
            color,
            from: 8,
          );
          block(Rect.fromLTWH(x - 9, y - 9, 18, 115), 14, color, from: 22);
        }
    }
    return faces;
  }

  void _addSlidingLeaves(_Group group, _Wall wall, WindowZone zone, Rect r) {
    final count = math.max(1, zone.slidingSashesCount);
    final tracks = math.max(1, zone.slidingTrackCount);
    final trackDepth = frameDepth / (tracks + 0.5);
    const overlap = 30.0;
    final width = (r.width + overlap * (count - 1)) / count;
    final color = _sashColor(zone);
    final hasCentralMeeting = zone.slidingFaceToFace && count >= 4;
    for (var i = 0; i < count; i++) {
      final left = r.left + i * (width - overlap);
      // Alternate leaves run on alternate tracks and slide towards each other.
      final track = i % tracks;
      final direction = i.isEven ? 1.0 : -1.0;
      final shift = direction * width * 0.42 * openingProgress;
      final leaf = Rect.fromLTWH(left + shift, r.top, width, r.height);
      // The first track is the room-side one.
      final zBack = -frameDepth + trackDepth * track + 4;
      final zFront = zBack + trackDepth * 0.75;
      final profile = math.min(
        _sashProfile,
        math.min(leaf.width, leaf.height) * 0.3,
      );
      final glassRect = leaf.deflate(profile);
      final zGlass = (zFront + zBack) / 2;
      final ring = _ring(wall, leaf, [glassRect], zFront, zBack, color);
      group.contents.add(
        _Solid.layered([
          ring.sublist(0, ring.length - 1),
          _glazing(wall, glassRect, zGlass, zone.glass),
          [ring.last],
        ], wall.n),
      );
      // Pulls as in the drawing: on the outer edges of the end leaves, and
      // on the meeting stiles of a central meeting.
      final pulls = <double>[
        if (i == 0) leaf.left + profile / 2,
        if (i == count - 1) leaf.right - profile / 2,
        if (hasCentralMeeting &&
            (zone.slidingCentralHandle || zone.slidingSecondCentralHandle) &&
            i == count ~/ 2 - 1)
          leaf.right - profile / 2,
        if (hasCentralMeeting &&
            (zone.slidingCentralHandle || zone.slidingSecondCentralHandle) &&
            i == count ~/ 2)
          leaf.left + profile / 2,
      ];
      final ratio = (zone.handlePositionRatio ?? 0.5).clamp(0.1, 0.9);
      final y = leaf.top + leaf.height * (1 - ratio);
      for (final x in pulls) {
        group.hardware.add(
          _block(
            wall,
            Rect.fromCenter(center: Offset(x, y), width: 20, height: 150),
            zBack,
            zBack - 12,
            model.accessoryColor,
            priority: 2,
          ),
        );
      }
    }
  }

  /// Two drain slots on the outer face of each bottom frame rail, 20% in
  /// from its ends, as in the drawing's external view.
  void _addDrainSlots(_Group group, Rect frame) {
    if (!model.effectiveHasBottomFrame) return;
    if ((frame.bottom - model.height).abs() > 5) return;
    final t = model.frameSideVisibleWidth(
      frame,
      'bottom',
      fallback: model.profileThickness,
    );
    const w = 35.0, h = 6.0;
    final y = frame.bottom - t / 2;
    for (final x in [
      frame.left + frame.width * 0.2,
      frame.right - frame.width * 0.2 - w,
    ]) {
      final slot = Rect.fromLTWH(x, y - h / 2, w, h);
      group.exterior.add(
        _Solid([
          _Face(
            _rect(group.wall, slot, 0.6),
            const Color(0xFF0B0B0C),
            normal: group.wall.n,
          ),
        ], priority: 3),
      );
    }
  }

  /// A framed mosquito screen in front of each frame opening, outside.
  void _addMosquitoNet(_Group group, Rect frame) {
    if (!(model.hasMoustiquaireAddon || model.isMoustiquaire)) return;
    final wall = group.wall;
    final outer = frame.deflate(12);
    final mesh = outer.deflate(22);
    final frameColor = Color.lerp(_frameColor, Colors.black, 0.08)!;
    group.exterior.add(
      _Solid.layered([
        _ring(wall, outer, [mesh], 6, 1.5, frameColor).sublist(0, 9),
        [
          _Face(_rect(wall, mesh, 3.5), const Color(0x7329323A)),
          for (var x = mesh.left + 60; x < mesh.right; x += 60)
            _Face(
              _rect(
                wall,
                Rect.fromLTRB(x - 0.6, mesh.top, x + 0.6, mesh.bottom),
                3.6,
              ),
              const Color(0x30000000),
            ),
        ],
        _ring(wall, outer, [mesh], 6, 1.5, frameColor).sublist(9),
      ], wall.n),
    );
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
          tunnel ? Color.lerp(_frameColor, Colors.white, 0.35)! : color,
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

  (List<_Group>, List<_WallSlab>) _buildScene() {
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
          _addZone(group, wall, zone);
        }
        _addDrainSlots(group, rect);
        _addMosquitoNet(group, rect);
        groups.add(group);
      }
    }
    for (final post in posts) {
      groups.add(_Group(frames.first.$2)..exterior.add(post));
    }
    _addShutter(groups, frames);
    // A corner window turns onto a second wall; two slabs cannot be ordered
    // by this painter, so a corner is shown without masonry.
    final straight =
        frames.isNotEmpty &&
        frames.every((f) => identical(f.$2, frames.first.$2));
    final slabs = showWall && straight
        ? _wallSlabs(frames)
        : const <_WallSlab>[];
    return (groups, slabs);
  }

  // ------------------------------------------------------------ rendering

  @override
  void paint(Canvas canvas, Size size) {
    if (model.width <= 0 || model.height <= 0) return;
    _paintBackdrop(canvas, size);
    final (groups, slabs) = _buildScene();
    if (groups.isEmpty) return;

    // The camera fits the window itself; the wall extends beyond the view.
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
      for (final solid in [
        ...group.contents,
        ...group.hardware,
        ...group.exterior,
      ]) {
        solid.faces.forEach(extend);
      }
    }
    if (!minV.x.isFinite) return;
    final centre = (minV + maxV) * 0.5;
    final radius = math.max(1.0, (maxV - minV).length / 2);
    final distance = radius * 3.4;
    final fit =
        math.min(size.width, size.height - 40) * 0.5 / radius * 0.86 * zoom;
    final cy = math.cos(yaw), sy = math.sin(yaw);
    final cp = math.cos(pitch), sp = math.sin(pitch);

    _V3 dirToCamera(_V3 d) {
      final x1 = d.x * cy + d.z * sy;
      final z1 = -d.x * sy + d.z * cy;
      return _V3(x1, d.y * cp - z1 * sp, d.y * sp + z1 * cp);
    }

    _V3 toCamera(_V3 p) => dirToCamera(p - centre);

    final screenCentre = Offset(size.width / 2, size.height / 2 + 8);
    final near = radius * 0.25;
    Offset project(_V3 c) {
      final s = distance / math.max(near, distance - c.z);
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

    // The light comes from above, in front of and left of the viewer, so
    // the side being looked at (room or outside) is the lit one.
    final towardsViewer = _V3(-sy, 0, cy);
    final viewerLeft = _V3(-cy, 0, -sy);
    final lightDir =
        (towardsViewer * 0.6 + _V3.up * 0.65 + viewerLeft * 0.45).unit;
    void drawFace(_Face face) {
      final cam = face.points.map(toCamera).toList();
      // Skip faces that reach behind the camera.
      if (cam.any((p) => distance - p.z < near)) return;
      var color = face.color;
      if (face.normal != null) {
        if (dirToCamera(face.normal!).dot(eye - cam.first) <= 0) return;
        final lambert = face.normal!.dot(lightDir).clamp(-1.0, 1.0);
        color = Color.lerp(
          color,
          lambert >= 0 ? Colors.white : Colors.black,
          lambert >= 0 ? lambert * 0.14 : -lambert * 0.36,
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
            ..color = Color.lerp(color, Colors.black, 0.3)!
            ..style = PaintingStyle.stroke
            ..strokeWidth = 0.7,
        );
      }
    }

    void drawSolid(_Solid solid) {
      final layers = solid.layers;
      if (layers == null) {
        solid.faces.forEach(drawFace);
        return;
      }
      // Far layer first: from the outside the room side is far.
      final outside = facesCamera(solid.outward!, solid.centroid);
      for (final layer in outside ? layers : layers.reversed) {
        layer.forEach(drawFace);
      }
    }

    void drawSolids(List<_Solid> solids) => byDepth(solids).forEach(drawSolid);

    // Masonry behind: edges and reveals (culling keeps the visible ones),
    // and the sill on the far side of the wall.
    final roomView =
        slabs.isNotEmpty &&
        facesCamera(slabs.first.inner.normal!, slabs.first.inner.points.first);
    for (final slab in slabs) {
      slab.sides.forEach(drawFace);
      drawSolid(roomView ? slab.outerSill : slab.innerSill);
    }
    if (slabs.isEmpty) _paintShadow(canvas, groups, toCamera, project);

    final orderedGroups = groups.toList()
      ..sort((a, b) => depth(a.centroid).compareTo(depth(b.centroid)));

    // An open sash and its handle can swing past the wall's room face; those
    // solids are drawn after the wall face, the rest before it.
    bool pastWall(_Group group, _Solid solid) {
      if (slabs.isEmpty) return false;
      final wall = group.wall;
      for (final face in solid.faces) {
        for (final p in face.points) {
          if ((p - wall.origin).dot(wall.n) < wallRoomZ) return true;
        }
      }
      return false;
    }

    final inFrontOfWall = <(_Group, List<_Solid>)>[];
    for (final group in orderedGroups) {
      final front = group.front;
      final outside = front == null
          ? !roomView
          : facesCamera(group.wall.n, front.points.first);
      if (outside) {
        // Outside: frame reveals, what the frame holds, its face, then the
        // shutter, the net and the drain slots in front of it.
        group.frameSides.forEach(drawFace);
        drawSolids(group.hardware);
        drawSolids(group.contents);
        if (front != null) drawFace(front);
        drawSolids(group.exterior);
      } else {
        // Room side: the shutter is behind; an open sash comes towards the
        // viewer, so it is drawn after the frame's room face.
        drawSolids(group.exterior);
        group.frameSides.forEach(drawFace);
        if (group.back != null) drawFace(group.back!);
        final ahead = [
          for (final solid in [...group.contents, ...group.hardware])
            if (pastWall(group, solid)) solid,
        ];
        drawSolids([
          for (final solid in group.contents)
            if (!ahead.contains(solid)) solid,
        ]);
        drawSolids([
          for (final solid in group.hardware)
            if (!ahead.contains(solid)) solid,
        ]);
        if (ahead.isNotEmpty) inFrontOfWall.add((group, ahead));
      }
    }

    // Masonry in front: the wall face around the opening and the sill on
    // the viewer's side, then what has swung into the room above the sill.
    for (final slab in slabs) {
      drawFace(slab.inner);
      drawFace(slab.outer);
      drawSolid(roomView ? slab.innerSill : slab.outerSill);
    }
    for (final (_, solids) in inFrontOfWall) {
      // Sashes before the hardware that sits on them.
      drawSolids([
        for (final s in solids)
          if (s.layers != null) s,
      ]);
      drawSolids([
        for (final s in solids)
          if (s.layers == null) s,
      ]);
    }
  }

  /// A soft floor shadow under each frame when no wall is shown.
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
        Path()
          ..addPolygon(quad.map((p) => project(toCamera(p))).toList(), true),
        paint,
      );
    }
  }

  /// A clear sky over the sea and a sandy beach.
  void _paintBackdrop(Canvas canvas, Size size) {
    final all = Offset.zero & size;
    final horizon = size.height * 0.56;
    final shore = size.height * 0.74;
    canvas.drawRect(
      Rect.fromLTRB(0, 0, size.width, horizon),
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF3FA9F5), Color(0xFF8ED2FB), Color(0xFFD6F0FF)],
        ).createShader(Rect.fromLTRB(0, 0, size.width, horizon)),
    );
    // Sun with its glow.
    final sun = Offset(size.width * 0.8, size.height * 0.14);
    canvas.drawCircle(
      sun,
      size.shortestSide * 0.16,
      Paint()
        ..shader =
            RadialGradient(
              colors: [
                Colors.white.withValues(alpha: 0.55),
                Colors.white.withValues(alpha: 0),
              ],
            ).createShader(
              Rect.fromCircle(center: sun, radius: size.shortestSide * 0.16),
            ),
    );
    canvas.drawCircle(
      sun,
      size.shortestSide * 0.045,
      Paint()..color = const Color(0xFFFFF6D5),
    );
    // A few soft clouds.
    final cloud = Paint()
      ..color = Colors.white.withValues(alpha: 0.75)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);
    for (final (fx, fy, s) in const [
      (0.18, 0.12, 1.0),
      (0.42, 0.22, 0.7),
      (0.62, 0.08, 0.55),
    ]) {
      final c = Offset(size.width * fx, size.height * fy);
      final r = size.shortestSide * 0.05 * s;
      canvas.drawOval(
        Rect.fromCenter(center: c, width: r * 5, height: r * 1.6),
        cloud,
      );
      canvas.drawCircle(c + Offset(-r * 0.8, -r * 0.4), r, cloud);
      canvas.drawCircle(c + Offset(r * 0.7, -r * 0.55), r * 1.15, cloud);
    }
    // Sea: deep at the horizon, turquoise near the shore, with wave glints.
    final sea = Rect.fromLTRB(0, horizon, size.width, shore);
    canvas.drawRect(
      sea,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF0B5D9A), Color(0xFF1386B8), Color(0xFF2CC2C9)],
        ).createShader(sea),
    );
    final glint = Paint()
      ..color = Colors.white.withValues(alpha: 0.28)
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round;
    final random = math.Random(7);
    for (var i = 0; i < 46; i++) {
      final fy = random.nextDouble();
      final y = horizon + (shore - horizon) * fy;
      final x = random.nextDouble() * size.width;
      final len = 8 + 26 * fy;
      canvas.drawLine(Offset(x, y), Offset(x + len, y), glint);
    }
    // Foam line and sand.
    final sand = Rect.fromLTRB(0, shore, size.width, size.height);
    canvas.drawRect(
      sand,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFF4E2BC), Color(0xFFE5C892)],
        ).createShader(sand),
    );
    canvas.drawRect(
      Rect.fromLTRB(0, shore - 3, size.width, shore + 4),
      Paint()..color = Colors.white.withValues(alpha: 0.7),
    );
    if (dark) {
      canvas.drawRect(all, Paint()..color = const Color(0x22000814));
    }
  }

  @override
  bool shouldRepaint(covariant Window3DPainter oldDelegate) =>
      oldDelegate.model != model ||
      oldDelegate.yaw != yaw ||
      oldDelegate.pitch != pitch ||
      oldDelegate.zoom != zoom ||
      oldDelegate.openingProgress != openingProgress ||
      oldDelegate.dark != dark ||
      oldDelegate.showWall != showWall;
}
