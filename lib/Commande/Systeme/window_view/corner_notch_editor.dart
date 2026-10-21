part of '../show_system_francais.dart';

/// Distance (screen pixels) of a side length label from its side.
const double _notchLabelGapPx = 26.0;

/// Cuts shown while a corner-cut handle is dragged, else the frame's cuts.
CornerNotches _shownCornerNotches(WindowModel model) {
  final preview = model.cornerNotchPreview;
  return preview == null
      ? model.cornerNotches
      : model.cornerNotches.withCorner(preview.corner, preview.notch);
}

/// Handle of corner [c]: on the inner step corner of a cut, else on the
/// outer corner of the frame.
Offset _cornerNotchHandle(WindowModel model, CornerNotches notches, NotchCorner c) {
  final corner = CornerNotches.cornerPoint(c, model.width, model.height);
  final n = notches.of(c);
  if (!n.isCut) return corner;
  return Offset(
    corner.dx + (CornerNotches.isLeft(c) ? n.width : -n.width),
    corner.dy + (CornerNotches.isTop(c) ? n.height : -n.height),
  );
}

/// Centre of the length label of every outline side, outside the frame.
List<({NotchedSide side, Offset anchor})> _cornerNotchLabels(
  WindowModel model,
  CornerNotches notches,
  double scale,
) {
  final gap = _notchLabelGapPx / scale;
  return [
    for (final side in notches.sides(model.width, model.height))
      if (side.length > 0.5)
        (
          side: side,
          anchor:
              (side.start + side.end) / 2 +
              Offset(
                    side.end.dy - side.start.dy,
                    side.start.dx - side.end.dx,
                  ) /
                  side.length *
                  gap,
        ),
  ];
}

/// Corner-cut handles, the dashed ghost of a dragged cut and the length of
/// every side, drawn over the selected frame in corner-cut mode.
void _paintCornerNotchOverlay(Canvas canvas, WindowModel model, double scale) {
  if (!model.cornerNotchMode ||
      model.selection.type != SelectionType.frame) {
    return;
  }
  final notches = _shownCornerNotches(model);
  if (model.cornerNotchPreview != null) {
    final ghost = Paint()
      ..color = Colors.orange.shade800
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0 / scale;
    final pts = notches.outline(model.width, model.height);
    final dash = 10.0 / scale;
    for (var i = 0; i < pts.length; i++) {
      final a = pts[i], b = pts[(i + 1) % pts.length];
      final len = (b - a).distance;
      if (len == 0) continue;
      final d = (b - a) / len;
      for (var s = 0.0; s < len; s += dash * 2) {
        canvas.drawLine(a + d * s, a + d * math.min(len, s + dash), ghost);
      }
    }
  }

  final side = 18.0 / scale;
  final fill = Paint()
    ..color = Colors.green.shade600
    ..style = PaintingStyle.fill;
  final border = Paint()
    ..color = Colors.white
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.5 / scale;
  final cutMark = Paint()
    ..color = Colors.white
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2.0 / scale;
  for (final c in NotchCorner.values) {
    final center = _cornerNotchHandle(model, notches, c);
    final handle = Rect.fromCenter(center: center, width: side, height: side);
    canvas.drawRect(handle, fill);
    canvas.drawRect(handle, border);
    // An L inside the square shows that it cuts the corner.
    final sx = CornerNotches.isLeft(c) ? 1.0 : -1.0;
    final sy = CornerNotches.isTop(c) ? 1.0 : -1.0;
    final q = side * 0.28;
    canvas.drawPath(
      Path()
        ..moveTo(center.dx - sx * q, center.dy + sy * q)
        ..lineTo(center.dx + sx * q, center.dy + sy * q)
        ..lineTo(center.dx + sx * q, center.dy - sy * q),
      cutMark,
    );
  }

  for (final label in _cornerNotchLabels(model, notches, scale)) {
    final isStep = label.side.notchCorner != null;
    final tp = TextPainter(
      text: TextSpan(
        text: label.side.length.toStringAsFixed(0),
        style: TextStyle(
          color: Colors.white,
          fontSize: 13 / scale,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final pad = 4 / scale;
    final box = Rect.fromCenter(
      center: label.anchor,
      width: tp.width + pad * 2,
      height: tp.height + pad,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(box, Radius.circular(4 / scale)),
      Paint()..color = isStep ? Colors.orange.shade800 : Colors.green.shade700,
    );
    tp.paint(canvas, box.center - Offset(tp.width / 2, tp.height / 2));
  }
}

extension _CornerNotchEditor on _WindowViewState {
  AppLanguage get _notchLang =>
      Provider.of<AppSettingsProvider>(context, listen: false).language;

  void _showCornerNotchNotice(String key) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(Localization.translate(key, _notchLang)),
          duration: const Duration(seconds: 3),
        ),
      );
  }

  /// The "corner cut" button of the frame toolbar.
  Widget _buildCornerNotchButton() {
    final model = widget.model;
    final active = model.cornerNotchMode;
    return Padding(
      padding: const EdgeInsetsDirectional.only(start: 8),
      child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          backgroundColor: active ? Colors.orange.shade800 : Colors.white,
          foregroundColor: active ? Colors.white : Colors.indigo.shade900,
        ),
        icon: const Icon(Icons.turn_slight_left, size: 18),
        label: Text(Localization.translate('notch_button', _notchLang)),
        onPressed: _toggleCornerNotchMode,
      ),
    );
  }

  /// Shows or hides the corner-cut handles of the selected frame.
  void _toggleCornerNotchMode() {
    final model = widget.model;
    final active = model.cornerNotchMode;
    if (!active) {
      final blocker = model.cornerNotchBlocker;
      if (blocker != null) {
        _showCornerNotchNotice(blocker);
        return;
      }
      if (model.selection.type != SelectionType.frame) {
        model.selection = SelectionInfo(type: SelectionType.frame);
      }
    }
    model.cornerNotchMode = !active;
    model.frameShapeMode = false;
    model.setCornerNotchPreview(null);
    model.refreshUI();
    if (!active) _showCornerNotchNotice('notch_hint');
  }

  /// Corner whose cut handle is under [screen], in corner-cut mode.
  NotchCorner? _cornerNotchHandleAt(Offset screen) {
    final model = widget.model;
    if (!model.cornerNotchMode ||
        model.selection.type != SelectionType.frame) {
      return null;
    }
    NotchCorner? closest;
    var best = 30.0;
    for (final c in NotchCorner.values) {
      final handle = _modelToScreen(
        _cornerNotchHandle(model, model.cornerNotches, c),
      );
      final d = (handle - screen).distance;
      if (d <= best) {
        best = d;
        closest = c;
      }
    }
    return closest;
  }

  /// Moves the ghost of the cut of [c] to the pointer at [screen].
  void _updateCornerNotchDrag(NotchCorner c, Offset screen) {
    final model = widget.model;
    final pos = _getModelPos(screen);
    final cutWidth = CornerNotches.isLeft(c) ? pos.dx : model.width - pos.dx;
    final cutHeight = CornerNotches.isTop(c) ? pos.dy : model.height - pos.dy;
    model.setCornerNotchPreview((
      corner: c,
      notch: model.cornerNotches.clampNotch(
        c,
        cutWidth,
        cutHeight,
        model.width,
        model.height,
      ),
    ));
  }

  /// Applies the ghost to the frame as one undo step.
  void _commitCornerNotchDrag() {
    final model = widget.model;
    final preview = model.cornerNotchPreview;
    if (preview == null) return;
    model.setCornerNotchPreview(null);
    final error = model.setCornerNotch(preview.corner, preview.notch);
    if (error != null) _showCornerNotchNotice(error);
  }

  /// A tap on a side length opens its editor. Returns whether it was one.
  bool _handleCornerNotchLabelTap(Offset screen) {
    final model = widget.model;
    if (!model.cornerNotchMode ||
        model.selection.type != SelectionType.frame) {
      return false;
    }
    final scale = model.canvasScale * _userScale;
    if (scale <= 0) return false;
    for (final label in _cornerNotchLabels(model, model.cornerNotches, scale)) {
      if ((_modelToScreen(label.anchor) - screen).distance <= 22) {
        _editCornerNotchSide(label.side);
        return true;
      }
    }
    return false;
  }

  /// Cut corner whose size a typed side length changes: the side's own
  /// step, else a cut corner at one of its ends.
  ({NotchCorner corner, bool alongWidth, bool grows})? _cornerForSide(
    NotchedSide side,
  ) {
    final model = widget.model;
    final notches = model.cornerNotches;
    if (side.notchCorner != null) {
      return (corner: side.notchCorner!, alongWidth: side.isHorizontal, grows: true);
    }
    for (final c in NotchCorner.values) {
      if (!notches.of(c).isCut) continue;
      final corner = CornerNotches.cornerPoint(c, model.width, model.height);
      final onSide = side.isHorizontal
          ? (corner.dy - side.start.dy).abs() < 0.5
          : (corner.dx - side.start.dx).abs() < 0.5;
      if (onSide) {
        // A longer remaining side means a smaller cut.
        return (corner: c, alongWidth: side.isHorizontal, grows: false);
      }
    }
    return null;
  }

  Future<void> _editCornerNotchSide(NotchedSide side) async {
    final model = widget.model;
    final lang = _notchLang;
    final target = _cornerForSide(side);
    if (target == null) {
      _showCornerNotchNotice('notch_full_side_hint');
      return;
    }
    final controller = TextEditingController(
      text: side.length.toStringAsFixed(0),
    );
    final value = await showDialog<double>(
      context: context,
      builder: (dialogContext) {
        void submit() {
          final v = double.tryParse(
            controller.text.trim().replaceAll(',', '.'),
          );
          Navigator.of(dialogContext).pop(v);
        }

        return AlertDialog(
          title: Text(Localization.translate('notch_side_length', lang)),
          content: TextField(
            controller: controller,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              suffixText: Localization.translate('مم', lang),
              helperText: Localization.translate('notch_min_hint', lang),
            ),
            onSubmitted: (_) => submit(),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(Localization.translate('إلغاء', lang)),
            ),
            ElevatedButton(
              onPressed: submit,
              child: Text(Localization.translate('تأكيد', lang)),
            ),
          ],
        );
      },
    );
    // The controller is left to the garbage collector: the dialog still
    // rebuilds its text field during its closing animation, and disposing it
    // here crashed the page.
    if (value == null || !mounted) return;
    final current = model.cornerNotches.of(target.corner);
    final delta = target.grows ? value - side.length : side.length - value;
    final next = target.alongWidth
        ? CornerNotch(width: current.width + delta, height: current.height)
        : CornerNotch(width: current.width, height: current.height + delta);
    final error = model.setCornerNotch(target.corner, next);
    if (error != null) _showCornerNotchNotice(error);
  }
}
