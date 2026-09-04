import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/gestures.dart'
    show GestureBinding, PointerScrollEvent, PointerSignalEvent;
import 'package:flutter/material.dart';

/// Coordinates Windows mouse-wheel input across nested ScrollViews.
///
/// Flutter normally resolves a pointer signal to the first scrollable in the
/// hit-test path. That is correct while the inner view can move, but it makes
/// the page feel stuck when that view is at an edge. Registered scrollables
/// report which ones were actually under the pointer; after Flutter resolves
/// the normal event, this coordinator falls back to the next eligible view.
class DesktopScrollCoordinator {
  DesktopScrollCoordinator._();

  static final Set<_DesktopScrollableRegistration> _registrations = {};
  static final Map<PointerSignalEvent, Set<_DesktopScrollableRegistration>>
      _hits = {};

  static void _register(_DesktopScrollableRegistration registration) {
    _registrations.add(registration);
  }

  static void _unregister(_DesktopScrollableRegistration registration) {
    _registrations.remove(registration);
    for (final hitTargets in _hits.values) {
      hitTargets.remove(registration);
    }
  }

  static void _markHit(
    _DesktopScrollableRegistration registration,
    PointerSignalEvent event,
  ) {
    if (event is! PointerScrollEvent) return;
    _hits.putIfAbsent(event, () => <_DesktopScrollableRegistration>{}).add(
      registration,
    );
  }

  static void handlePointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;

    final hitTargets = _hits.remove(event);
    if (hitTargets == null || hitTargets.isEmpty) return;

    final verticalDelta = event.scrollDelta.dy;
    final horizontalDelta = event.scrollDelta.dx;
    final useVertical = verticalDelta.abs() >= horizontalDelta.abs();
    final delta = useVertical ? verticalDelta : horizontalDelta;
    if (delta == 0) return;

    final candidates = hitTargets
        .where(
          (registration) =>
              registration.axis == (useVertical ? Axis.vertical : Axis.horizontal) &&
              registration.bounds?.contains(event.position) == true &&
              registration.controller.hasClients,
        )
        .toList();
    if (candidates.isEmpty) return;

    // The smallest viewport is normally the deepest nested region, while the
    // largest one is the page fallback.
    candidates.sort((a, b) {
      final aArea = a.bounds!.width * a.bounds!.height;
      final bArea = b.bounds!.width * b.bounds!.height;
      return aArea.compareTo(bArea);
    });
    final offsets = <_DesktopScrollableRegistration, double>{
      for (final candidate in candidates
          .where((candidate) => candidate.controller.hasClients))
        candidate: candidate.controller.position.pixels,
    };

    // Let Flutter's built-in Scrollable handler win first. If it moved any
    // candidate, no fallback is needed and there is no double scrolling.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final anyMoved = offsets.entries.any((entry) {
        final controller = entry.key.controller;
        return controller.hasClients &&
            (controller.position.pixels - entry.value).abs() >= 0.5;
      });
      if (anyMoved) return;

      for (final candidate in candidates) {
        final controller = candidate.controller;
        if (!controller.hasClients || !candidate.canMove(delta)) continue;
        controller.position.pointerScroll(delta);
        break;
      }
    });
  }
}

class _DesktopScrollableRegistration {
  _DesktopScrollableRegistration({
    required this.controller,
    required this.axis,
    required this.context,
  });

  final ScrollController controller;
  final Axis axis;
  final BuildContext context;

  Rect? get bounds {
    final renderObject = context.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) return null;
    final origin = renderObject.localToGlobal(Offset.zero);
    return origin & renderObject.size;
  }

  bool canMove(double delta) {
    if (!controller.hasClients) return false;
    final position = controller.position;
    return delta < 0
        ? position.pixels > position.minScrollExtent
        : position.pixels < position.maxScrollExtent;
  }
}

class _RegisteredDesktopScrollable extends StatefulWidget {
  const _RegisteredDesktopScrollable({
    required this.controller,
    required this.axis,
    required this.child,
  });

  final ScrollController controller;
  final Axis axis;
  final Widget child;

  @override
  State<_RegisteredDesktopScrollable> createState() =>
      _RegisteredDesktopScrollableState();
}

class _RegisteredDesktopScrollableState
    extends State<_RegisteredDesktopScrollable> {
  late _DesktopScrollableRegistration _registration;

  @override
  void initState() {
    super.initState();
    _registration = _DesktopScrollableRegistration(
      controller: widget.controller,
      axis: widget.axis,
      context: context,
    );
    DesktopScrollCoordinator._register(_registration);
  }

  @override
  void didUpdateWidget(covariant _RegisteredDesktopScrollable oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller == widget.controller &&
        oldWidget.axis == widget.axis) {
      return;
    }
    DesktopScrollCoordinator._unregister(_registration);
    _registration = _DesktopScrollableRegistration(
      controller: widget.controller,
      axis: widget.axis,
      context: context,
    );
    DesktopScrollCoordinator._register(_registration);
  }

  @override
  void dispose() {
    DesktopScrollCoordinator._unregister(_registration);
    super.dispose();
  }

  void _markPointerHit(PointerSignalEvent event) {
    DesktopScrollCoordinator._markHit(_registration, event);
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerSignal: _markPointerHit,
      child: widget.child,
    );
  }
}

/// Application-wide scrolling rules for the Windows desktop build.
///
/// Vertical wheel input is left to the nearest vertical scrollable. A wheel
/// over a horizontal scrollbar is redirected to that scrollbar, including a
/// normal mouse wheel whose native delta is vertical. This keeps horizontal
/// rows from hijacking the page wheel when the pointer is over their content.
class DesktopScrollBehavior extends MaterialScrollBehavior {
  const DesktopScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.stylus,
        PointerDeviceKind.invertedStylus,
        PointerDeviceKind.unknown,
      };

  @override
  Widget buildScrollbar(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    final isWindowsDesktop = !kIsWeb &&
        defaultTargetPlatform == TargetPlatform.windows;
    final controller = details.controller;
    final axis = axisDirectionToAxis(details.direction);

    if (isWindowsDesktop && controller != null) {
      if (axis == Axis.horizontal) {
        return _RegisteredDesktopScrollable(
          controller: controller,
          axis: axis,
          child: _HorizontalWheelScrollbar(
            controller: controller,
            child: child,
          ),
        );
      }

      // Bind the visible scrollbar to the exact controller used by the
      // scrollable. This prevents pages with nested lists from waiting until
      // the user drags the thumb before the wheel/scroll position is active.
      return _RegisteredDesktopScrollable(
        controller: controller,
        axis: axis,
        child: Scrollbar(
          controller: controller,
          thumbVisibility: true,
          interactive: true,
          child: child,
        ),
      );
    }

    return super.buildScrollbar(context, child, details);
  }
}

/// Adds a small, non-blocking hit area around the horizontal scrollbar.
///
/// The listener is an ancestor of the scrollbar, so dragging the thumb still
/// works normally. It only claims a wheel event while the last pointer hover
/// position is inside the bottom scrollbar band; elsewhere the event remains
/// available to the page's vertical scrollable.
class _HorizontalWheelScrollbar extends StatefulWidget {
  final ScrollController controller;
  final Widget child;

  const _HorizontalWheelScrollbar({
    required this.controller,
    required this.child,
  });

  @override
  State<_HorizontalWheelScrollbar> createState() =>
      _HorizontalWheelScrollbarState();
}

class _HorizontalWheelScrollbarState extends State<_HorizontalWheelScrollbar> {
  static const double _hitBandHeight = 18;
  bool _pointerOverScrollbar = false;

  void _updatePointerPosition(Offset localPosition, double height) {
    final next = localPosition.dy >= height - _hitBandHeight;
    if (next != _pointerOverScrollbar && mounted) {
      setState(() => _pointerOverScrollbar = next);
    }
  }

  void _handlePointerSignal(PointerSignalEvent event) {
    if (!_pointerOverScrollbar ||
        event is! PointerScrollEvent ||
        !widget.controller.hasClients) {
      return;
    }

    // A standard mouse wheel reports dy. A trackpad or horizontal wheel may
    // report dx, so preserve that axis when it is the only available delta.
    final delta = event.scrollDelta.dy != 0
        ? event.scrollDelta.dy
        : event.scrollDelta.dx;
    if (delta == 0) return;

    final position = widget.controller.position;
    final target = (position.pixels + delta)
        .clamp(position.minScrollExtent, position.maxScrollExtent)
        .toDouble();
    if ((target - position.pixels).abs() < 0.5) return;

    GestureBinding.instance.pointerSignalResolver.register(event, (_) {
      if (!widget.controller.hasClients) return;
      final current = widget.controller.position;
      final currentTarget = (current.pixels + delta)
          .clamp(current.minScrollExtent, current.maxScrollExtent)
          .toDouble();
      if ((currentTarget - current.pixels).abs() >= 0.5) {
        current.pointerScroll(delta);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return MouseRegion(
          onHover: (event) =>
              _updatePointerPosition(event.localPosition, constraints.maxHeight),
          onExit: (_) {
            if (mounted) setState(() => _pointerOverScrollbar = false);
          },
          child: Listener(
            behavior: HitTestBehavior.opaque,
            onPointerSignal: _handlePointerSignal,
            child: Scrollbar(
              controller: widget.controller,
              thumbVisibility: true,
              interactive: true,
              child: widget.child,
            ),
          ),
        );
      },
    );
  }
}
