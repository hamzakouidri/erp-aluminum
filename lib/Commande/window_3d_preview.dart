import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'Systeme/model.dart';

/// Lightweight interactive 3D preview generated from the same [WindowModel]
/// used by the technical drawing. It deliberately keeps editing in 2D; this
/// view is a fast visual check and a foundation for real profile cross-sections.
class Window3DPreview extends StatefulWidget {
  const Window3DPreview({super.key, required this.model});

  final WindowModel model;

  @override
  State<Window3DPreview> createState() => _Window3DPreviewState();
}

class _Window3DPreviewState extends State<Window3DPreview>
    with SingleTickerProviderStateMixin {
  double _yaw = 0.65;
  double _pitch = 0.38;
  double _zoom = 1;
  double _startYaw = 0.65;
  double _startPitch = 0.38;
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
    _yaw = 0.65;
    _pitch = 0.38;
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
    return Scaffold(
      backgroundColor: dark ? const Color(0xFF111827) : const Color(0xFFF1F5F9),
      appBar: AppBar(
        title: const Text('معاينة ثلاثية الأبعاد'),
        actions: [
          IconButton(
            tooltip: 'إعادة ضبط المنظور',
            onPressed: _reset,
            icon: const Icon(Icons.center_focus_strong_rounded),
          ),
          AnimatedBuilder(
            animation: _openingController,
            builder: (context, _) => IconButton(
              tooltip: _openingController.isAnimating
                  ? 'إيقاف الحركة'
                  : _openingController.value > 0.5
                  ? 'إغلاق النافذة'
                  : 'فتح النافذة',
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
                  _pitch = (_startPitch - movement.dy / 220).clamp(-1.35, 1.35);
                  _zoom = (_startZoom * details.scale).clamp(0.55, 2.6);
                });
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
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Text(
                  'اسحب للدوران 360° • اسحب عموديًا للأعلى والأسفل • قرّب بإصبعين',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ),
        ],
      ),
    );
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

  Color get _frameColor {
    final raw =
        model.selectedDbColor?['code']?.toString() ??
        model.selectedDbColor?['hex']?.toString() ??
        '';
    final clean = raw.replaceAll('#', '').trim();
    if (clean.length == 6) {
      final value = int.tryParse(clean, radix: 16);
      if (value != null) return Color(0xFF000000 | value);
    }
    final name = model.frameColor.name.toLowerCase();
    if (name.contains('black') || name.contains('noir'))
      return const Color(0xFF25282B);
    if (name.contains('brown') || name.contains('bronze'))
      return const Color(0xFF6D4C41);
    if (name.contains('gray') || name.contains('grey'))
      return const Color(0xFF8B949E);
    return const Color(0xFFE5E7EB);
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (model.width <= 0 || model.height <= 0) return;
    final usable = Size(
      math.max(80, size.width - 90),
      math.max(80, size.height - 110),
    );
    final scale =
        math.min(usable.width / model.width, usable.height / model.height) *
        zoom;
    final frontSize = Size(model.width * scale, model.height * scale);
    final origin = Offset(
      (size.width - frontSize.width) / 2,
      (size.height - frontSize.height) / 2 + 16,
    );
    final depth = math.min(85.0, math.max(28.0, 58.0 * zoom));
    final orbitScale = 0.72 + 0.28 * math.cos(yaw).abs();
    final visualFront = Size(frontSize.width * orbitScale, frontSize.height);
    final visualOrigin = Offset(
      (size.width - visualFront.width) / 2,
      origin.dy,
    );
    final extrusion = Offset(
      math.sin(yaw) * depth,
      -math.sin(pitch) * depth,
    );

    _paintBackdrop(canvas, size, visualOrigin, visualFront, extrusion);

    Rect mapRect(Rect r) => Rect.fromLTWH(
      visualOrigin.dx + r.left * scale * orbitScale,
      visualOrigin.dy + r.top * scale,
      r.width * scale * orbitScale,
      r.height * scale,
    );

    // Glass/panel surfaces sit behind the aluminium front face.
    for (final zone in model.zones) {
      final rect = mapRect(
        zone.boundary,
      ).deflate(math.max(2, model.profileThickness * scale * 0.34));
      if (rect.width <= 2 || rect.height <= 2) continue;
      _paintZoneSurface(canvas, rect, zone, extrusion * 0.28);
    }

    final frames = model.getFrameRects();
    final frameRects = frames.isEmpty
        ? <Rect>[Rect.fromLTWH(0, 0, model.width, model.height)]
        : frames;
    for (final frame in frameRects) {
      _paintRing(
        canvas,
        mapRect(frame),
        math.max(5, model.profileThickness * scale),
        extrusion,
        _frameColor,
      );
    }

    for (final zone in model.zones) {
      final rect = mapRect(zone.boundary);
      if (zone.content == ZoneContent.singleSash ||
          zone.content == ZoneContent.doubleSash ||
          zone.content == ZoneContent.slidingSash) {
        _paintSashes(canvas, rect, zone, extrusion, openingProgress);
      }
    }
  }

  void _paintBackdrop(
    Canvas canvas,
    Size size,
    Offset origin,
    Size front,
    Offset depth,
  ) {
    final bg = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: dark
            ? const [Color(0xFF071A33), Color(0xFF0D4C73), Color(0xFF0B7189)]
            : const [Color(0xFF75C9FF), Color(0xFFBDE9FF), Color(0xFF168AAD)],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, bg);
    final horizon = size.height * 0.58;
    canvas.drawRect(
      Rect.fromLTWH(0, horizon, size.width, size.height - horizon),
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF249BC1), Color(0xFF086788)],
        ).createShader(Rect.fromLTWH(0, horizon, size.width, size.height - horizon)),
    );
    for (var i = 0; i < 5; i++) {
      final y = horizon + 12 + i * 18;
      canvas.drawArc(
        Rect.fromLTWH(-20 + i * 17, y, size.width + 40, 16),
        math.pi,
        math.pi,
        false,
        Paint()
          ..color = Colors.white.withValues(alpha: 0.16)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
    final groundY = origin.dy + front.height + math.max(16, depth.dy.abs());
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(
          origin.dx + front.width / 2 + depth.dx / 2,
          groundY + 12,
        ),
        width: front.width * 0.92,
        height: math.max(18, front.height * 0.08),
      ),
      Paint()..color = Colors.black.withValues(alpha: 0.16),
    );
  }

  void _paintZoneSurface(Canvas canvas, Rect rect, WindowZone zone, Offset z) {
    final shifted = rect.shift(z);
    final isPanel =
        zone.glass.panneauSubtype?.trim().isNotEmpty == true ||
        zone.glass.panneauProductId != null;
    final color = isPanel
        ? _panelColor(zone.glass.panneauColor)
        : _glassColor(zone.glass);
    canvas.drawRect(shifted, Paint()..color = color);
    if (!isPanel) {
      final highlight = Path()
        ..moveTo(shifted.left + shifted.width * 0.08, shifted.bottom)
        ..lineTo(shifted.left + shifted.width * 0.42, shifted.top)
        ..lineTo(shifted.left + shifted.width * 0.58, shifted.top)
        ..lineTo(shifted.left + shifted.width * 0.24, shifted.bottom)
        ..close();
      canvas.drawPath(
        highlight,
        Paint()..color = Colors.white.withValues(alpha: 0.24),
      );
    }
    canvas.drawRect(
      shifted,
      Paint()
        ..color = (isPanel ? Colors.black : Colors.lightBlue.shade900)
            .withValues(alpha: 0.28)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );
  }

  Color _glassColor(GlassSpecification glass) {
    final name = glass.colorOuter.name.toLowerCase();
    if (name.contains('blue') || name.contains('bleu'))
      return const Color(0x8860A5D8);
    if (name.contains('green') || name.contains('vert'))
      return const Color(0x8874B9A2);
    if (name.contains('brown') || name.contains('bronze'))
      return const Color(0x889C8062);
    return const Color(0x887EC8E3);
  }

  Color _panelColor(String? raw) {
    final clean = (raw ?? '').replaceAll('#', '').trim();
    final value = clean.length == 6 ? int.tryParse(clean, radix: 16) : null;
    return value == null ? const Color(0xFFF1F5F9) : Color(0xFF000000 | value);
  }

  void _paintRing(
    Canvas canvas,
    Rect rect,
    double thickness,
    Offset depth,
    Color color,
  ) {
    final back = rect.shift(depth);
    final side = Paint()..color = Color.lerp(color, Colors.black, 0.32)!;
    _quad(canvas, [
      rect.topLeft,
      back.topLeft,
      back.topRight,
      rect.topRight,
    ], side);
    _quad(canvas, [
      rect.topRight,
      back.topRight,
      back.bottomRight,
      rect.bottomRight,
    ], side);
    _quad(canvas, [
      rect.bottomLeft,
      rect.bottomRight,
      back.bottomRight,
      back.bottomLeft,
    ], Paint()..color = Color.lerp(color, Colors.black, 0.2)!);

    final inner = rect.deflate(
      math.min(thickness, math.min(rect.width, rect.height) * 0.28),
    );
    final ring = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(rect)
      ..addRect(inner);
    canvas.drawPath(ring, Paint()..color = color);
    canvas.drawPath(
      ring,
      Paint()
        ..color = Color.lerp(color, Colors.black, 0.38)!
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.1,
    );
    canvas.drawLine(
      rect.topLeft,
      rect.bottomRight,
      Paint()..color = Colors.black12,
    );
    canvas.drawLine(
      rect.topRight,
      rect.bottomLeft,
      Paint()..color = Colors.black12,
    );
  }

  void _paintSashes(
    Canvas canvas,
    Rect rect,
    WindowZone zone,
    Offset depth,
    double progress,
  ) {
    final count = zone.content == ZoneContent.doubleSash
        ? 2
        : zone.content == ZoneContent.slidingSash
        ? math.max(1, zone.slidingSashesCount)
        : 1;
    for (var i = 0; i < count; i++) {
      final part = Rect.fromLTWH(
        rect.left + rect.width * i / count,
        rect.top,
        rect.width / count,
        rect.height,
      ).deflate(math.max(3, math.min(rect.width, rect.height) * 0.018));
      final isSliding = zone.content == ZoneContent.slidingSash;
      final trackDepth = isSliding
          ? depth * (0.12 + (i % math.max(1, zone.slidingTrackCount)) * 0.12)
          : depth * 0.08;
      final animatedPart = isSliding
          ? part.shift(Offset((i.isEven ? 1 : -1) * part.width * 0.42 * progress, 0))
          : Rect.fromLTWH(
              i.isEven ? part.left : part.right - part.width * (1 - progress * 0.72),
              part.top - depth.dy.abs() * 0.18 * progress,
              part.width * (1 - progress * 0.72),
              part.height,
            );
      _paintRing(
        canvas,
        animatedPart.shift(trackDepth + Offset(depth.dx * 0.42 * progress, 0)),
        math.max(4, math.min(part.width, part.height) * 0.065),
        depth * 0.1,
        _frameColor,
      );
      final handleX = i == 0 ? animatedPart.right - 9 : animatedPart.left + 9;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(handleX, animatedPart.center.dy),
            width: 5,
            height: 28,
          ),
          const Radius.circular(3),
        ).shift(trackDepth),
        Paint()..color = const Color(0xFF374151),
      );
    }
  }

  void _quad(Canvas canvas, List<Offset> points, Paint paint) {
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (final point in points.skip(1)) {
      path.lineTo(point.dx, point.dy);
    }
    path.close();
    canvas.drawPath(path, paint);
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
