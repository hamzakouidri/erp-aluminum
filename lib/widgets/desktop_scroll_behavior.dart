import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/gestures.dart'
    show GestureBinding, PointerScrollEvent, PointerSignalEvent;
import 'package:flutter/material.dart';

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

    if (isWindowsDesktop && axis == Axis.horizontal && controller != null) {
      return _HorizontalWheelScrollbar(
        controller: controller,
        child: child,
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
