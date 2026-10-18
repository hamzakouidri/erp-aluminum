import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../settings/app_settings.dart';
import '../settings/localization.dart';
import 'Systeme/model.dart';
import 'texture_cache.dart';
import 'three_d/scene_painter.dart';
import 'three_d/window_scene_builder.dart';

/// Interactive 3D preview generated from the same [WindowModel] used by the
/// technical drawing: mitred profiles with depth, sashes on their hinges or
/// tracks, glass, handles, colours and wood foils, lit in perspective.
/// Editing stays in 2D.
class Window3DPreview extends StatefulWidget {
  const Window3DPreview({super.key, required this.model});

  final WindowModel model;

  @override
  State<Window3DPreview> createState() => _Window3DPreviewState();
}

class _Window3DPreviewState extends State<Window3DPreview>
    with SingleTickerProviderStateMixin {
  static const _angled = OrbitCamera();
  static const _minZoom = 0.35;
  static const _maxZoom = 6.0;

  OrbitCamera _camera = _angled;
  late final AnimationController _openingController;

  WindowScene? _scene;
  double _sceneOpening = -1;
  int _sceneRevision = -1;
  int _revision = 0;

  // Touch / trackpad gestures (mouse is handled by the Listener).
  bool _gestureIsMouse = false;
  double _gestureStartZoom = 1;

  @override
  void initState() {
    super.initState();
    _openingController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    widget.model.drawingRepaint.addListener(_invalidate);
    // Wood foils decode asynchronously; rebuild once they are ready.
    TextureCache.init().then((_) => _invalidate());
  }

  @override
  void dispose() {
    widget.model.drawingRepaint.removeListener(_invalidate);
    _openingController.dispose();
    super.dispose();
  }

  void _invalidate() {
    if (!mounted) return;
    setState(() => _revision++);
  }

  WindowScene _sceneFor(double opening) {
    final cached = _scene;
    if (cached != null &&
        _sceneRevision == _revision &&
        (_sceneOpening - opening).abs() < 1e-4) {
      return cached;
    }
    final scene = WindowSceneBuilder(widget.model).build(opening: opening);
    _scene = scene;
    _sceneOpening = opening;
    _sceneRevision = _revision;
    return scene;
  }

  void _setCamera(OrbitCamera camera) => setState(() => _camera = camera);

  void _zoomBy(double factor) => _setCamera(
    _camera.copyWith(
      zoom: (_camera.zoom * factor).clamp(_minZoom, _maxZoom).toDouble(),
    ),
  );

  void _rotateBy(Offset delta) => _setCamera(
    _camera.copyWith(
      // Yaw is unbounded: the user can orbit through 360° in either direction.
      yaw: _camera.yaw + delta.dx * 0.009,
      pitch: (_camera.pitch + delta.dy * 0.007).clamp(-1.3, 1.3).toDouble(),
    ),
  );

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

  bool get _isDesktop =>
      kIsWeb ||
      defaultTargetPlatform == TargetPlatform.windows ||
      defaultTargetPlatform == TargetPlatform.linux ||
      defaultTargetPlatform == TargetPlatform.macOS;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final lang = Provider.of<AppSettingsProvider>(context).language;
    String tr(String key) => Localization.translate(key, lang);

    return Scaffold(
      backgroundColor: dark ? const Color(0xFF141C26) : const Color(0xFFE9EEF3),
      appBar: AppBar(
        title: Text(tr('معاينة ثلاثية الأبعاد')),
        actions: [
          IconButton(
            tooltip: tr('window3d_view_interior'),
            onPressed: () => _setCamera(const OrbitCamera(yaw: 0, pitch: 0.05)),
            icon: const Icon(Icons.crop_portrait_rounded),
          ),
          IconButton(
            tooltip: tr('window3d_view_exterior'),
            onPressed: () =>
                _setCamera(const OrbitCamera(yaw: math.pi, pitch: 0.05)),
            icon: const Icon(Icons.flip_rounded),
          ),
          IconButton(
            tooltip: tr('window3d_view_angle'),
            onPressed: () => _setCamera(_angled),
            icon: const Icon(Icons.view_in_ar_rounded),
          ),
          IconButton(
            tooltip: tr('window3d_reset_view'),
            onPressed: () => _setCamera(_angled),
            icon: const Icon(Icons.center_focus_strong_rounded),
          ),
          AnimatedBuilder(
            animation: _openingController,
            builder: (context, _) => IconButton(
              tooltip: _openingController.isAnimating
                  ? tr('window3d_pause')
                  : _openingController.value > 0.5
                  ? tr('window3d_close')
                  : tr('window3d_open'),
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
            child: Listener(
              behavior: HitTestBehavior.opaque,
              onPointerSignal: (event) {
                if (event is PointerScrollEvent) {
                  GestureBinding.instance.pointerSignalResolver.register(
                    event,
                    (e) => _zoomBy(
                      math.exp(-(e as PointerScrollEvent).scrollDelta.dy * 0.0015),
                    ),
                  );
                }
              },
              onPointerMove: (event) {
                if (event.kind != PointerDeviceKind.mouse) return;
                if (event.buttons & kPrimaryMouseButton != 0) {
                  _rotateBy(event.delta);
                } else if (event.buttons &
                        (kSecondaryMouseButton | kMiddleMouseButton) !=
                    0) {
                  _setCamera(_camera.copyWith(pan: _camera.pan + event.delta));
                }
              },
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onDoubleTap: () => _setCamera(_angled),
                onScaleStart: (details) {
                  _gestureIsMouse = details.kind == PointerDeviceKind.mouse;
                  _gestureStartZoom = _camera.zoom;
                },
                onScaleUpdate: (details) {
                  if (_gestureIsMouse) return;
                  if (details.pointerCount >= 2 || details.scale != 1.0) {
                    _setCamera(
                      _camera.copyWith(
                        zoom: (_gestureStartZoom * details.scale)
                            .clamp(_minZoom, _maxZoom)
                            .toDouble(),
                        pan: details.pointerCount >= 2
                            ? _camera.pan + details.focalPointDelta
                            : _camera.pan,
                      ),
                    );
                    if (details.pointerCount >= 2) return;
                  }
                  _rotateBy(details.focalPointDelta);
                },
                child: AnimatedBuilder(
                  animation: _openingController,
                  builder: (context, _) => RepaintBoundary(
                    child: CustomPaint(
                      size: Size.infinite,
                      painter: WindowScenePainter(
                        scene: _sceneFor(
                          Curves.easeInOut.transform(_openingController.value),
                        ),
                        camera: _camera,
                        dark: dark,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          PositionedDirectional(
            end: 14,
            bottom: 14,
            child: _ZoomButtons(
              dark: dark,
              zoomInTooltip: tr('window3d_zoom_in'),
              zoomOutTooltip: tr('window3d_zoom_out'),
              onZoomIn: () => _zoomBy(1.2),
              onZoomOut: () => _zoomBy(1 / 1.2),
            ),
          ),
          PositionedDirectional(
            start: 14,
            bottom: 14,
            end: 90,
            child: Align(
              alignment: AlignmentDirectional.bottomStart,
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
                    tr(_isDesktop ? 'window3d_hint_mouse' : 'window3d_hint_touch'),
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
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

class _ZoomButtons extends StatelessWidget {
  const _ZoomButtons({
    required this.dark,
    required this.zoomInTooltip,
    required this.zoomOutTooltip,
    required this.onZoomIn,
    required this.onZoomOut,
  });

  final bool dark;
  final String zoomInTooltip;
  final String zoomOutTooltip;
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: (dark ? Colors.black : Colors.white).withValues(alpha: 0.85),
      elevation: 3,
      borderRadius: BorderRadius.circular(12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: zoomInTooltip,
            onPressed: onZoomIn,
            icon: const Icon(Icons.add_rounded),
          ),
          IconButton(
            tooltip: zoomOutTooltip,
            onPressed: onZoomOut,
            icon: const Icon(Icons.remove_rounded),
          ),
        ],
      ),
    );
  }
}
