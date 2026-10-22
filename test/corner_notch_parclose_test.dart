import 'dart:typed_data';

import 'package:database_data/Commande/Systeme/corner_notch.dart';
import 'package:database_data/Commande/Systeme/model.dart';
import 'package:database_data/Commande/window_painter.dart';
import 'package:database_data/sql_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Records the lines the painter draws, ignoring the rest.
class _RecordingCanvas implements Canvas {
  final lines = <(Offset, Offset)>[];
  int _saves = 1;

  @override
  void drawLine(Offset p1, Offset p2, Paint paint) => lines.add((p1, p2));

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
  TestWidgetsFlutterBinding.ensureInitialized();
  const w = 2000.0, h = 1500.0, t = 50.0;
  const glass = Rect.fromLTRB(t, t, w - t, h - t);

  group('clipRect', () {
    test('a rect no cut reaches stays as it is', () {
      const n = CornerNotches(topRight: CornerNotch(width: 400, height: 300));
      expect(
        n.clipRect(
          const Rect.fromLTRB(t, 600, 900, h - t),
          w,
          h,
          inset: t,
        ),
        isNull,
      );
      expect(CornerNotches.none.clipRect(glass, w, h, inset: t), isNull);
    });

    test('a top-right cut gives the L-shaped glass with its inner corner', () {
      const n = CornerNotches(topRight: CornerNotch(width: 400, height: 300));
      expect(n.clipRect(glass, w, h, inset: t), const [
        Offset(t, t),
        Offset(w - 400 - t, t),
        Offset(w - 400 - t, 300 + t),
        Offset(w - t, 300 + t),
        Offset(w - t, h - t),
        Offset(t, h - t),
      ]);
    });

    test('a cut across the whole zone width only lowers its top', () {
      const n = CornerNotches(topLeft: CornerNotch(width: 900, height: 300));
      expect(
        n.clipRect(const Rect.fromLTRB(t, t, 800, h - t), w, h, inset: t),
        const [
          Offset(t, 300 + t),
          Offset(800, 300 + t),
          Offset(800, h - t),
          Offset(t, h - t),
        ],
      );
    });

    test('a zone wholly inside a cut has no glass', () {
      const n = CornerNotches(topLeft: CornerNotch(width: 900, height: 600));
      expect(
        n.clipRect(const Rect.fromLTRB(t, t, 800, 500), w, h, inset: t),
        isEmpty,
      );
    });
  });

  group('parclose drawing', () {
    WindowModel window() {
      final model = WindowModel(
        db: SqlDatabase(),
        width: w,
        height: h,
        profileThickness: t,
      );
      model.zones = [
        WindowZone(id: 'g', content: ZoneContent.fixedGlass, boundary: glass),
      ];
      return model;
    }

    bool hasLine(_RecordingCanvas c, Offset a, Offset b) => c.lines.any(
      (l) =>
          ((l.$1 - a).distance < 0.5 && (l.$2 - b).distance < 0.5) ||
          ((l.$1 - b).distance < 0.5 && (l.$2 - a).distance < 0.5),
    );

    test('a cut-corner glass gets 45° parclose joints at every corner', () {
      final model = window();
      expect(
        model.setCornerNotch(
          NotchCorner.topRight,
          const CornerNotch(width: 400, height: 300),
        ),
        isNull,
      );
      final canvas = _RecordingCanvas();
      WindowPainter(model: model).paint(canvas, const Size(w, h));

      const p = 18.0;
      final glassOutline = model.cornerNotches.clipRect(
        glass,
        w,
        h,
        inset: t,
      )!;
      final inner = CornerNotches.insetPolygon(glassOutline, p);
      for (var i = 0; i < glassOutline.length; i++) {
        expect(
          hasLine(canvas, glassOutline[i], inner[i]),
          isTrue,
          reason: 'joint at ${glassOutline[i]}',
        );
      }
      // The inner corner of the L, mitred into the glass.
      expect(inner[2], const Offset(w - 400 - t - p, 300 + t + p));
    });

    test('a plain window keeps its four rectangular joints', () {
      final canvas = _RecordingCanvas();
      WindowPainter(model: window()).paint(canvas, const Size(w, h));
      final innerGlass = glass.deflate(18);
      expect(hasLine(canvas, glass.topLeft, innerGlass.topLeft), isTrue);
      expect(hasLine(canvas, glass.topRight, innerGlass.topRight), isTrue);
      expect(hasLine(canvas, glass.bottomLeft, innerGlass.bottomLeft), isTrue);
      expect(
        hasLine(canvas, glass.bottomRight, innerGlass.bottomRight),
        isTrue,
      );
    });
  });
}
