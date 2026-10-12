import 'dart:async' show scheduleMicrotask;
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
  static final Map<PointerEvent, Set<_DesktopScrollableRegistration>> _hits =
      {};
  static final Set<PointerEvent> _signalsSeenByWidgetTree = {};
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
    // Hit-test transforms create separate event wrappers for the same wheel
    // tick. Use the original event, as Flutter's signal resolver does, so
    // translated descendants and the root listener share the same hit list.
    final eventKey = event.original ?? event;
    if (_hits.length > 40) {
      _hits.clear();
    }
    _hits
        .putIfAbsent(eventKey, () => <_DesktopScrollableRegistration>{})
        .add(registration);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _hits.remove(eventKey);
    });
  }

  static void rememberPointerPosition(PointerEvent event) {
    _lastPointerPosition = event.position;
  }

  static void handlePointerSignal(
    PointerSignalEvent event, {
    bool resolveDirectly = false,
  }) {
    if (event is! PointerScrollEvent) return;
    final eventKey = event.original ?? event;
    _signalsSeenByWidgetTree.add(eventKey);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _signalsSeenByWidgetTree.remove(eventKey);
    });
    debugPrint(
      'WHEEL called, regs=${_registrations.length}, hits=${_hits.length}',
    );
    _lastPointerPosition = event.position;

    try {
      final key = event.original ?? event;
      final markedTargets = _hits[key];
      final hitTargets = markedTargets != null
          ? <_DesktopScrollableRegistration>{...markedTargets}
          : <_DesktopScrollableRegistration>{};
      final pool = hitTargets.isNotEmpty ? hitTargets : _registrations;
      if (pool.isEmpty) return;

      final isShiftPressed = HardwareKeyboard.instance.isShiftPressed;
      final verticalDelta = event.scrollDelta.dy;
      final horizontalDelta = event.scrollDelta.dx;
      final bool useHorizontalFromShift =
          isShiftPressed && verticalDelta.abs() > 0;
      final bool useVertical =
          !useHorizontalFromShift &&
          (verticalDelta.abs() >= horizontalDelta.abs());
      final delta = useHorizontalFromShift
          ? verticalDelta
          : (useVertical ? verticalDelta : horizontalDelta);
      if (delta == 0) return;

      final candidates = pool
          .where(
            (registration) =>
                registration.bounds?.contains(event.position) == true &&
                registration.controller.positions.isNotEmpty,
          )
          .toList();
      debugPrint(
        'wheel: pool=${pool.length} candidates====================${candidates.length}',
      );
      if (candidates.isEmpty) return;

      candidates.sort((a, b) {
        final aBounds = a.bounds;
        final bBounds = b.bounds;
        if (aBounds == null || bBounds == null) return 0;
        final aArea = aBounds.width * aBounds.height;
        final bArea = bBounds.width * bBounds.height;
        return aArea.compareTo(bArea);
      });

      final requestedAxis = useVertical ? Axis.vertical : Axis.horizontal;
      for (final c in candidates) {
        debugPrint(
          'cand axis=${c.axis} positions=${c.controller.positions.length} '
          'canMove=${c.canMove(delta)} '
          'pix=${c.controller.positions.map((p) => "${p.pixels}/${p.maxScrollExtent}").toList()}',
        );
      }
      debugPrint('requested=$requestedAxis delta=$delta');
      // Prioritize scrollables matching the requested axis (e.g. vertical wheel -> vertical scrollable)
      for (final candidate in candidates) {
        if (candidate.axis != requestedAxis) continue;
        if (candidate.canMove(delta)) {
          if (resolveDirectly) {
            _scrollCandidate(candidate, delta);
            return;
          }
          final offsetsBeforeResolution = <ScrollPosition, double>{
            for (final position in candidate.controller.positions)
              position: position.pixels,
          };
          var coordinatorResolvedSignal = false;
          GestureBinding.instance.pointerSignalResolver.register(event, (_) {
            coordinatorResolvedSignal = true;
            _scrollCandidate(candidate, delta);
          });

          // A descendant Scrollable can win Flutter's pointer-signal resolver
          // before this root coordinator. Normally that winner moves the same
          // position. After a Windows focus loss/regain, however, a stale
          // winner can consume the signal without moving anything. Fall back
          // only when our callback lost *and* none of this candidate's
          // positions changed, which avoids applying a wheel tick twice.
          scheduleMicrotask(() {
            if (coordinatorResolvedSignal ||
                !_registrations.contains(candidate)) {
              return;
            }
            final positionMoved = offsetsBeforeResolution.entries.any(
              (entry) =>
                  entry.key.hasPixels &&
                  (entry.key.pixels - entry.value).abs() >= 0.5,
            );
            if (!positionMoved && candidate.canMove(delta)) {
              _scrollCandidate(candidate, delta);
            }
          });
          return;
        }
      }
      debugPrint('WHEEL: no candidate accepted the scroll');
    } catch (e, s) {
      debugPrint('WHEEL ERROR: $e\n$s');
    }
  }

  /// Last-resort route for Windows after the app regains focus.
  ///
  /// Flutter can occasionally keep a stale pointer hit-test path until the
  /// user clicks a newly built page. The global pointer router still receives
  /// the wheel event in that state. Defer until normal dispatch has finished,
  /// then handle only events that never reached the root widget listener.
  static void handleGlobalPointerEvent(PointerEvent event) {
    if (event is! PointerScrollEvent) return;
    final eventKey = event.original ?? event;
    scheduleMicrotask(() {
      if (_signalsSeenByWidgetTree.contains(eventKey)) return;
      handlePointerSignal(event, resolveDirectly: true);
    });
  }

  static void _scrollCandidate(
    _DesktopScrollableRegistration candidate,
    double delta,
  ) {
    if (!_registrations.contains(candidate)) return;
    for (final position in candidate.controller.positions) {
      if (!position.hasContentDimensions ||
          !position.physics.shouldAcceptUserOffset(position)) {
        continue;
      }
      final canMove = delta < 0
          ? position.pixels > position.minScrollExtent
          : position.pixels < position.maxScrollExtent;
      if (canMove) {
        position.pointerScroll(delta);
        return;
      }
    }
    final fallbackPosition = candidate.activePosition;
    if (fallbackPosition != null && fallbackPosition.hasContentDimensions) {
      fallbackPosition.pointerScroll(delta);
    }
  }

  /// Handles keyboard navigation
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
              registration.controller.positions.isNotEmpty,
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
      final position = registration.activePosition;
      if (position == null || !_canMovePosition(position, direction)) continue;
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

  ScrollPosition? get activePosition {
    if (controller.positions.isEmpty) return null;
    if (controller.positions.length == 1) return controller.positions.first;
    ScrollPosition? best;
    double maxExtent = -1;
    for (final pos in controller.positions) {
      if (pos.hasContentDimensions && pos.physics.shouldAcceptUserOffset(pos)) {
        final extent = pos.maxScrollExtent;
        if (extent > maxExtent) {
          maxExtent = extent;
          best = pos;
        }
      }
    }
    return best ?? controller.positions.first;
  }

  Rect? get bounds {
    if (!context.mounted) return null;
    final route = ModalRoute.of(context);
    // isActive remains true for a page covered by a dialog. isCurrent is the
    // correct guard: a wheel event over a modal barrier must never scroll the
    // hidden quantities table behind it.
    if (route != null && !route.isCurrent) return null;
    if (!DesktopTabScope.isActive(context)) return null;

    var hidden = false;
    try {
      context.visitAncestorElements((element) {
        if (element.widget is Offstage &&
            (element.widget as Offstage).offstage) {
          hidden = true;
          return false;
        }
        if (element.widget is Visibility &&
            !(element.widget as Visibility).visible) {
          hidden = true;
          return false;
        }
        return true;
      });
      if (hidden) return null;
      final renderObject = context.findRenderObject();
      if (renderObject is! RenderBox ||
          !renderObject.hasSize ||
          !renderObject.attached ||
          renderObject.size.isEmpty) {
        return null;
      }
      final origin = renderObject.localToGlobal(Offset.zero);
      return origin & renderObject.size;
    } catch (_) {
      return null;
    }
  }

  bool canMove(double delta) {
    if (bounds == null) return false;
    if (controller.positions.isEmpty) return false;
    for (final position in controller.positions) {
      if (!position.hasContentDimensions ||
          !position.physics.shouldAcceptUserOffset(position)) {
        continue;
      }
      final can = delta < 0
          ? position.pixels > position.minScrollExtent
          : position.pixels < position.maxScrollExtent;
      if (can) return true;
    }
    return false;
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
  ScrollPhysics getScrollPhysics(BuildContext context) {
    final isWindowsDesktop =
        !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;
    if (isWindowsDesktop) {
      return const ClampingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      );
    }
    return const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics());
  }

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
    final controller =
        details.controller ?? PrimaryScrollController.maybeOf(context);
    final axis = axisDirectionToAxis(details.direction);

    if (isWindowsDesktop && controller != null && axis == Axis.horizontal) {
      return _RegisteredDesktopScrollable(
        controller: controller,
        axis: axis,
        child: _HorizontalWheelScrollbar(controller: controller, child: child),
      );
    }

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
    if (event is! PointerScrollEvent || widget.controller.positions.isEmpty) {
      return;
    }
    // Recompute against the current layout on every tick. A hover flag can
    // remain true after scrolling/rebuilding moves the scrollbar away, and
    // then hijack vertical wheel input until the pointer moves again.
    try {
      final box = context.findRenderObject();
      if (box is! RenderBox || !box.hasSize || !box.attached) return;
      var needsLayout = false;
      assert(() {
        if (box.debugNeedsLayout) needsLayout = true;
        return true;
      }());
      if (needsLayout) return;
      final local = box.globalToLocal(event.position);
      if (local.dx < 0 ||
          local.dx > box.size.width ||
          local.dy < box.size.height - _hitBandHeight ||
          local.dy > box.size.height) {
        return;
      }

      // A standard mouse wheel reports dy. A trackpad or horizontal wheel may
      // report dx, so preserve that axis when it is the only available delta.
      final delta = event.scrollDelta.dy != 0
          ? event.scrollDelta.dy
          : event.scrollDelta.dx;
      if (delta == 0) return;

      final position = widget.controller.positions.first;
      if (!position.hasContentDimensions ||
          !position.physics.shouldAcceptUserOffset(position)) {
        return;
      }
      final target = (position.pixels + delta)
          .clamp(position.minScrollExtent, position.maxScrollExtent)
          .toDouble();
      if ((target - position.pixels).abs() < 0.5) return;

      GestureBinding.instance.pointerSignalResolver.register(event, (_) {
        if (!mounted || widget.controller.positions.isEmpty) return;
        final current = widget.controller.positions.first;
        final currentTarget = (current.pixels + delta)
            .clamp(current.minScrollExtent, current.maxScrollExtent)
            .toDouble();
        if ((currentTarget - current.pixels).abs() >= 0.5) {
          current.pointerScroll(delta);
        }
      });
    } catch (_) {}
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
            behavior: HitTestBehavior.translucent,
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

class DesktopTabScope extends InheritedWidget {
  const DesktopTabScope({
    super.key,
    required this.active,
    required super.child,
  });

  final bool active;

  static bool isActive(BuildContext context) =>
      context.getInheritedWidgetOfExactType<DesktopTabScope>()?.active ?? true;

  @override
  bool updateShouldNotify(DesktopTabScope old) => active != old.active;
}
