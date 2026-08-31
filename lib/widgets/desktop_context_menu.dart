import 'package:flutter/material.dart';

/// Opens a Windows-style context menu next to the pointer and keeps the menu
/// inside the current application overlay.
Future<T?> showDesktopContextMenu<T>({
  required BuildContext context,
  required Offset globalPosition,
  required List<PopupMenuEntry<T>> items,
}) async {
  if (items.isEmpty) return null;
  final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
  final localPosition = overlay.globalToLocal(globalPosition);
  final width = overlay.size.width;
  final height = overlay.size.height;
  final x = localPosition.dx.clamp(8.0, width - 8.0).toDouble();
  final y = localPosition.dy.clamp(8.0, height - 8.0).toDouble();

  return showMenu<T>(
    context: context,
    position: RelativeRect.fromLTRB(x, y, width - x, height - y),
    items: items,
  );
}
