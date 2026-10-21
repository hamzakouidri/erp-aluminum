import 'dart:typed_data';

import 'package:database_data/Commande/Systeme/model.dart';
import 'package:database_data/Commande/window_painter.dart';
import 'package:database_data/sql_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Records the rectangles and lines the painter draws, ignoring the rest.
class _RecordingCanvas implements Canvas {
  final rects = <Rect>[];
  final lines = <(Offset, Offset, Paint)>[];
  int _saves = 1;

  @override
  void drawRect(Rect rect, Paint paint) => rects.add(rect);

  @override
  void drawLine(Offset p1, Offset p2, Paint paint) =>
      lines.add((p1, p2, paint));

  @override
  void save() => _saves++;

  @override
  void saveLayer(Rect? bounds, Paint paint) => _saves++;

  @override
  void restore() => _saves--;

  @override
  int getSaveCount() => _saves;

  @override
  Float64List getTransform() =>
      Float64List.fromList(Matrix4.identity().storage);

  @override
  Rect getLocalClipBounds() => const Rect.fromLTWH(0, 0, 4000, 4000);

  @override
  Rect getDestinationClipBounds() => const Rect.fromLTWH(0, 0, 4000, 4000);

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  const frameWidth = 50.0;

  WindowModel crossWithCadreDouble() {
    final model = WindowModel(
      db: SqlDatabase(),
      width: 1400,
      height: 1200,
      profileThickness: 45,
    );
    final sep = model.mullionThickness / 2;
    model.zones = [
      WindowZone(
        id: 'tl',
        boundary: Rect.fromLTRB(45, 45, 700 - sep, 500 - sep),
      ),
      WindowZone(
        id: 'tr',
        boundary: Rect.fromLTRB(700 + sep, 45, 1355, 500 - sep),
      ),
      WindowZone(
        id: 'bl',
        boundary: Rect.fromLTRB(45, 500 + sep, 700 - sep, 1155),
      ),
      WindowZone(
        id: 'br',
        boundary: Rect.fromLTRB(700 + sep, 500 + sep, 1355, 1155),
      ),
    ];
    model.mullionCreationOrder['V_700.0'] = 1;
    model.mullionCreationOrder['H_500.0'] = 2;
    model.selection = const SelectionInfo(
      type: SelectionType.mullion,
      isHorizontalMullion: false,
      mullionPosition: 700,
      mullionStart: 45,
      mullionEnd: 1155,
    );
    model.setMullionFrameSection(MullionProfileType.flat, {
      'id': 'frame_50',
      'visible_width': frameWidth,
    });
    model.selection = SelectionInfo.none;
    return model;
  }

  test('a Cadre double is drawn as two frames with a thin black joint', () {
    final model = crossWithCadreDouble();
    expect(model.isMullionGapBetween(false, 650, 750), isTrue);

    final canvas = _RecordingCanvas();
    WindowPainter(model: model).paint(canvas, const Size(1400, 1200));

    bool near(double a, double b) => (a - b).abs() < 1.5;

    // The two frame bars, back-to-back on the divider's centre line.
    final leftBars = canvas.rects.where(
      (r) => near(r.left, 650) && near(r.right, 700) && r.height > 300,
    );
    final rightBars = canvas.rects.where(
      (r) => near(r.left, 700) && near(r.right, 750) && r.height > 300,
    );
    expect(leftBars, isNotEmpty);
    expect(rightBars, isNotEmpty);

    // The black joint between them.
    final joints = canvas.lines.where(
      (l) =>
          near(l.$1.dx, 700) &&
          near(l.$2.dx, 700) &&
          l.$3.color == Colors.black,
    );
    expect(joints, isNotEmpty);

    // The horizontal mullions stop at the faces of the Cadre double instead
    // of running into it.
    final sep = model.mullionThickness / 2;
    final horizontalBars = canvas.rects.where(
      (r) => near(r.top, 500 - sep) && near(r.bottom, 500 + sep),
    );
    expect(horizontalBars, isNotEmpty);
    for (final bar in horizontalBars) {
      final crossesDouble = bar.left < 750 - 2 && bar.right > 650 + 2;
      expect(crossesDouble, isFalse, reason: 'bar $bar');
    }
  });

  test('an ordinary wide gap is still not taken for a divider', () {
    final model = WindowModel(
      db: SqlDatabase(),
      width: 1400,
      height: 1200,
      profileThickness: 45,
    );
    expect(model.isMullionGapBetween(false, 650, 750), isFalse);
    expect(
      model.isMullionGapBetween(
        false,
        700 - model.mullionThickness / 2,
        700 + model.mullionThickness / 2,
      ),
      isTrue,
    );
  });
}
