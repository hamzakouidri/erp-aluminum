import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/gestures.dart'
    show GestureBinding, PointerEvent, PointerScrollEvent, PointerSignalEvent;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show
        HardwareKeyboard,
        KeyDownEvent,
        KeyEvent,
        KeyRepeatEvent,
        LogicalKeyboardKey;

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
  static Offset? _lastPointerPosition;

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
    _hits
        .putIfAbsent(event, () => <_DesktopScrollableRegistration>{})
        .add(registration);

    // PointerSignalEvent objects are unique per wheel tick.  They must not
    // remain as keys in this static map: pages are opened and closed during a
    // session, and retaining every wheel event eventually makes hit testing
    // sluggish and can make scrolling appear to stop.  The normal Flutter
    // scroll handler has already consumed the event by the next frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _hits.remove(event);
    });
    // Force a frame to actually be scheduled. If nothing else in the tree
    // calls setState after this wheel tick (e.g. the pointer is over empty
    // page chrome, or every scrollable under it is already at its edge), no
    // frame would otherwise be produced, and this cleanup callback — along
    // with the fallback logic in handlePointerSignal below — would stay
    // pending indefinitely instead of running on the next tick.
    WidgetsBinding.instance.scheduleFrame();
  }

  static void rememberPointerPosition(PointerEvent event) {
    _lastPointerPosition = event.position;
  }

  static void handlePointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    _lastPointerPosition = event.position;

    // A scrollable can receive the signal before its scrollbar registration
    // is reached in the hit-test path. Use all registered viewports under the
    // pointer as a reliable fallback instead of waiting for a thumb drag.
    final markedTargets =
        _hits.remove(event) ?? <_DesktopScrollableRegistration>{};
    final hitTargets = <_DesktopScrollableRegistration>{...markedTargets};
    if (hitTargets.isEmpty) return;

    final verticalDelta = event.scrollDelta.dy;
    final horizontalDelta = event.scrollDelta.dx;
    final useVertical = verticalDelta.abs() >= horizontalDelta.abs();
    final delta = useVertical ? verticalDelta : horizontalDelta;
    if (delta == 0) return;

    final candidates = hitTargets
        .where(
          (registration) =>
              registration.axis ==
                  (useVertical ? Axis.vertical : Axis.horizontal) &&
              registration.bounds?.contains(event.position) == true &&
              registration.controller.positions.length == 1,
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
      for (final candidate in hitTargets.where(
        (candidate) => candidate.controller.positions.length == 1,
      ))
        candidate: candidate.controller.position.pixels,
    };

    // Let Flutter's built-in Scrollable handler win first. If it moved any
    // candidate, no fallback is needed and there is no double scrolling.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final anyMoved = offsets.entries.any((entry) {
        final controller = entry.key.controller;
        return controller.positions.length == 1 &&
            (controller.position.pixels - entry.value).abs() >= 0.5;
      });
      if (anyMoved) return;

      for (final candidate in candidates) {
        final controller = candidate.controller;
        if (!_registrations.contains(candidate) || !candidate.canMove(delta))
          continue;
        controller.position.pointerScroll(delta);
        break;
      }
    });
    // Same reasoning as in _markHit: without an explicit scheduleFrame,
    // this callback can be left dangling when no scrollable actually moves
    // (pointer over empty chrome, or every candidate already at its edge),
    // silently dropping the fallback scroll for that wheel tick.
    WidgetsBinding.instance.scheduleFrame();
  }

  /// Handles keyboard navigation (arrow keys, Page Up/Down, Home/End) without
  /// stealing cursor movement from a text field. The focused scrollable wins;
  /// otherwise the scrollable under the last pointer position is used, with
  /// the page viewport as fallback.
  ///
  /// Up/Down and PageUp/PageDown/Home/End drive vertical scrollables.
  /// Left/Right drive horizontal scrollables with a small "line" step;
  /// holding Ctrl with Left/Right uses a larger "page" step instead, mirroring
  /// PageUp/PageDown behavior on the vertical axis.
  static bool handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return false;

    final key = event.logicalKey;
    final isCtrlPressed = HardwareKeyboard.instance.isControlPressed;

    Axis? axis;
    var direction = 0; // -1 back, 1 forward, -2 jump to start, 2 jump to end
    var isLineStep = true;

    switch (key) {
      case LogicalKeyboardKey.arrowDown:
        axis = Axis.vertical;
        direction = 1;
        break;
      case LogicalKeyboardKey.arrowUp:
        axis = Axis.vertical;
        direction = -1;
        break;
      case LogicalKeyboardKey.pageDown:
        axis = Axis.vertical;
        direction = 1;
        isLineStep = false;
        break;
      case LogicalKeyboardKey.pageUp:
        axis = Axis.vertical;
        direction = -1;
        isLineStep = false;
        break;
      case LogicalKeyboardKey.home:
        axis = Axis.vertical;
        direction = -2;
        break;
      case LogicalKeyboardKey.end:
        axis = Axis.vertical;
        direction = 2;
        break;
      case LogicalKeyboardKey.arrowRight:
        axis = Axis.horizontal;
        direction = 1;
        isLineStep = !isCtrlPressed;
        break;
      case LogicalKeyboardKey.arrowLeft:
        axis = Axis.horizontal;
        direction = -1;
        isLineStep = !isCtrlPressed;
        break;
      default:
        axis = null;
    }
    if (axis == null || direction == 0) return false;
    final resolvedAxis = axis;

    final focusedContext = FocusManager.instance.primaryFocus?.context;
    if (focusedContext != null && _isInsideEditableText(focusedContext)) {
      return false;
    }
    if (HardwareKeyboard.instance.isAltPressed ||
        HardwareKeyboard.instance.isMetaPressed ||
        isCtrlPressed)
      return false;

    final focusedScrollable = focusedContext == null
        ? null
        : Scrollable.maybeOf(focusedContext);
    final registrations = _registrations
        .where(
          (registration) =>
              registration.axis == resolvedAxis &&
              registration.bounds != null &&
              registration.controller.positions.length == 1 &&
              (focusedContext == null ||
                  ModalRoute.of(registration.context) ==
                      ModalRoute.of(focusedContext)),
        )
        .toList();
    registrations.sort((a, b) {
      final aArea = a.bounds == null
          ? double.infinity
          : a.bounds!.width * a.bounds!.height;
      final bArea = b.bounds == null
          ? double.infinity
          : b.bounds!.width * b.bounds!.height;
      return aArea.compareTo(bArea);
    });

    // The focused ScrollableState cannot always be matched to a registration
    // (for example, when a page intentionally hides its scrollbar), so use its
    // position directly when it can move.
    final focusedMatchesAxis =
        focusedScrollable != null &&
        (resolvedAxis == Axis.vertical
            ? (focusedScrollable.axisDirection == AxisDirection.up ||
                  focusedScrollable.axisDirection == AxisDirection.down)
            : (focusedScrollable.axisDirection == AxisDirection.left ||
                  focusedScrollable.axisDirection == AxisDirection.right));
    if (focusedMatchesAxis &&
        focusedScrollable.position.hasContentDimensions &&
        _canMovePosition(focusedScrollable.position, direction)) {
      _applyKeyScroll(
        focusedScrollable.position,
        direction,
        isLineStep: isLineStep,
      );
      return true;
    }

    final pointer = _lastPointerPosition;
    final underPointer = pointer == null
        ? <_DesktopScrollableRegistration>[]
        : registrations
              .where(
                (registration) =>
                    registration.bounds?.contains(pointer) == true,
              )
              .toList();
    final candidates = [...underPointer]
        .fold<List<_DesktopScrollableRegistration>>(
          <_DesktopScrollableRegistration>[],
          (result, registration) {
            if (!result.contains(registration)) result.add(registration);
            return result;
          },
        );
    for (final registration in candidates) {
      final position = registration.controller.position;
      if (!_canMovePosition(position, direction)) continue;
      _applyKeyScroll(position, direction, isLineStep: isLineStep);
      return true;
    }
    return false;
  }

  static bool _isInsideEditableText(BuildContext context) {
    if (context.widget is EditableText) return true;
    return context.findAncestorWidgetOfExactType<EditableText>() != null;
  }

  static bool _canMovePosition(ScrollPosition position, int direction) {
    if (!position.hasContentDimensions ||
        !position.physics.shouldAcceptUserOffset(position))
      return false;
    if (direction == -2 || direction == -1) {
      return position.pixels > position.minScrollExtent;
    }
    return position.pixels < position.maxScrollExtent;
  }

  static void _applyKeyScroll(
    ScrollPosition position,
    int direction, {
    required bool isLineStep,
  }) {
    if (direction == -2) {
      position.jumpTo(position.minScrollExtent);
      return;
    }
    if (direction == 2) {
      position.jumpTo(position.maxScrollExtent);
      return;
    }
    // Line step: a small, precise nudge (arrow keys / Ctrl+Left/Right at
    // default). Page step: a large jump tied to the viewport size (PageUp/
    // PageDown, and Ctrl+Left/Right), matching the previous PageUp/PageDown
    // sizing exactly.
    final step = isLineStep
        ? 48.0
        : (position.viewportDimension * 0.72).clamp(56.0, 520.0);
    final offset = (position.pixels + (direction > 0 ? step : -step))
        .clamp(position.minScrollExtent, position.maxScrollExtent)
        .toDouble();
    position.jumpTo(offset);
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
    if (!context.mounted) return null;
    if (ModalRoute.of(context)?.isCurrent == false) return null;
    var hidden = false;
    context.visitAncestorElements((element) {
      if (element.widget is Offstage && (element.widget as Offstage).offstage) {
        hidden = true;
        return false;
      }
      return true;
    });
    if (hidden) return null;
    final renderObject = context.findRenderObject();
    if (renderObject is! RenderBox ||
        !renderObject.hasSize ||
        !renderObject.attached)
      return null;
    final offstage = context.findAncestorWidgetOfExactType<Offstage>();
    if (offstage?.offstage == true) return null;
    final origin = renderObject.localToGlobal(Offset.zero);
    return origin & renderObject.size;
  }

  bool canMove(double delta) {
    if (bounds == null || controller.positions.length != 1) return false;
    final offstage = context.findAncestorWidgetOfExactType<Offstage>();
    if (offstage?.offstage == true) return false;
    final position = controller.position;
    if (!position.hasContentDimensions) return false;
    if (!position.physics.shouldAcceptUserOffset(position)) return false;
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

/// Registers a page-level fallback for wheel events that land on fixed page
/// chrome (filters, toolbars, and empty padding) instead of on the scrollable
/// list itself. The normal inner scrollable still wins whenever it can move.
class DesktopScrollFallback extends StatelessWidget {
  const DesktopScrollFallback({
    super.key,
    required this.controller,
    required this.child,
  });

  final ScrollController controller;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return _RegisteredDesktopScrollable(
      controller: controller,
      axis: Axis.vertical,
      child: child,
    );
  }
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
    final isWindowsDesktop =
        !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;
    final controller = details.controller;
    final axis = axisDirectionToAxis(details.direction);

    if (isWindowsDesktop && controller != null && axis == Axis.horizontal) {
      return _RegisteredDesktopScrollable(
        controller: controller,
        axis: axis,
        child: _HorizontalWheelScrollbar(controller: controller, child: child),
      );
    }

    // Register vertical views too. The coordinator uses these registrations
    // only as a fallback when the innermost widget is already at an edge, so
    // the wheel can continue into the page instead of appearing to stop after
    // the first scrollable region. `_RegisteredDesktopScrollable` unregisters
    // on disposal, including during workspace tab rebuilds.
    if (isWindowsDesktop && controller != null && axis == Axis.vertical) {
      return _RegisteredDesktopScrollable(
        controller: controller,
        axis: axis,
        child: super.buildScrollbar(context, child, details),
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
        widget.controller.positions.length != 1) {
      return;
    }

    // A standard mouse wheel reports dy. A trackpad or horizontal wheel may
    // report dx, so preserve that axis when it is the only available delta.
    final delta = event.scrollDelta.dy != 0
        ? event.scrollDelta.dy
        : event.scrollDelta.dx;
    if (delta == 0) return;

    final position = widget.controller.position;
    if (!position.hasContentDimensions ||
        !position.physics.shouldAcceptUserOffset(position))
      return;
    final target = (position.pixels + delta)
        .clamp(position.minScrollExtent, position.maxScrollExtent)
        .toDouble();
    if ((target - position.pixels).abs() < 0.5) return;

    GestureBinding.instance.pointerSignalResolver.register(event, (_) {
      if (!mounted || widget.controller.positions.length != 1) return;
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
          onHover: (event) => _updatePointerPosition(
            event.localPosition,
            constraints.maxHeight,
          ),
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
