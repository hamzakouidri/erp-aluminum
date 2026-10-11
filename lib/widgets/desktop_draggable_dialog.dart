import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' as material;

/// App-wide dialog entry point.
///
/// On desktop, dialogs can be moved only from the narrow top/edge handles.
/// The rest of the dialog keeps the normal arrow cursor and all interactive
/// controls retain their native gestures. Mobile dialogs are unchanged.
Future<T?> showDialog<T>({
  required material.BuildContext context,
  required material.WidgetBuilder builder,
  bool barrierDismissible = true,
  material.Color? barrierColor,
  String? barrierLabel,
  bool useSafeArea = true,
  bool useRootNavigator = true,
  material.RouteSettings? routeSettings,
  material.Offset? anchorPoint,
  material.TraversalEdgeBehavior? traversalEdgeBehavior,
  bool? requestFocus,
  material.AnimationStyle? animationStyle,
}) {
  return material.showDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierColor: barrierColor,
    barrierLabel: barrierLabel,
    useSafeArea: useSafeArea,
    useRootNavigator: useRootNavigator,
    routeSettings: routeSettings,
    anchorPoint: anchorPoint,
    traversalEdgeBehavior: traversalEdgeBehavior,
    requestFocus: requestFocus,
    animationStyle: animationStyle,
    builder: (dialogContext) =>
        DesktopDraggableDialog(child: builder(dialogContext)),
  );
}

class DesktopDraggableDialog extends material.StatefulWidget {
  final material.Widget child;

  const DesktopDraggableDialog({super.key, required this.child});

  @override
  material.State<DesktopDraggableDialog> createState() =>
      _DesktopDraggableDialogState();
}

class _DesktopDraggableDialogState
    extends material.State<DesktopDraggableDialog> {
  material.Offset _offset = material.Offset.zero;

  bool get _isDesktop =>
      defaultTargetPlatform == TargetPlatform.windows ||
      defaultTargetPlatform == TargetPlatform.linux ||
      defaultTargetPlatform == TargetPlatform.macOS;

  void _move(material.DragUpdateDetails details) {
    final size = material.MediaQuery.sizeOf(context);
    final maxX = size.width * 0.46;
    final maxY = size.height * 0.43;
    setState(() {
      _offset = material.Offset(
        (_offset.dx + details.delta.dx).clamp(-maxX, maxX),
        (_offset.dy + details.delta.dy).clamp(-maxY, maxY),
      );
    });
  }

  material.Widget _dragZone({
    double? width,
    double? height,
  }) {
    return material.SizedBox(
      width: width,
      height: height,
      child: material.MouseRegion(
        cursor: material.SystemMouseCursors.move,
        child: material.GestureDetector(
          behavior: material.HitTestBehavior.opaque,
          onPanUpdate: _move,
        ),
      ),
    );
  }

  @override
  material.Widget build(material.BuildContext context) {
    if (!_isDesktop || material.MediaQuery.sizeOf(context).width < 700) {
      return widget.child;
    }

    return material.Transform.translate(
      offset: _offset,
      child: material.Stack(
        fit: material.StackFit.passthrough,
        children: [
          material.MouseRegion(
            cursor: material.SystemMouseCursors.basic,
            child: widget.child,
          ),
          // A slim top grip and narrow edge grips keep the move cursor away
          // from fields, buttons, and unused interior whitespace.
          material.Positioned(top: 0, left: 10, right: 10, child: _dragZone(height: 16)),
          material.Positioned(top: 16, bottom: 10, left: 0, child: _dragZone(width: 8)),
          material.Positioned(top: 16, bottom: 10, right: 0, child: _dragZone(width: 8)),
          material.Positioned(bottom: 0, left: 10, right: 10, child: _dragZone(height: 8)),
        ],
      ),
    );
  }
}
