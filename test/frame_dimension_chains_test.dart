import 'package:database_data/Commande/Systeme/model.dart';
import 'package:database_data/sql_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// Coupled frames from their outer rectangles (45 mm profiles).
  WindowModel build(List<Rect> outers) {
    final model = WindowModel(
      db: SqlDatabase(),
      width: outers.map((r) => r.right).reduce((a, b) => a > b ? a : b),
      height: outers.map((r) => r.bottom).reduce((a, b) => a > b ? a : b),
      profileThickness: 45,
    );
    var i = 0;
    model.zones = [
      for (final r in outers) WindowZone(id: 'f${i++}', boundary: r.deflate(45)),
    ];
    model.coupleFrames = true;
    return model;
  }

  Rect frame(WindowModel m, String id) => m.frameRectForZone(id)!;

  // A transom over two frames, as drawn by the user.
  WindowModel transom() => build(const [
    Rect.fromLTRB(0, 0, 2703, 250),
    Rect.fromLTRB(0, 250, 2152, 1593),
    Rect.fromLTRB(2152, 250, 2703, 1593),
  ]);

  group('frameDimensionChains', () {
    test('transom: lower widths below, heights on the left only', () {
      final c = transom().frameDimensionChains();
      List<String> ids(List<PhysicalFrameInfo> l) =>
          l.map((f) => f.primaryZoneId).toList();
      expect(ids(c.top), isEmpty); // the transom is the overall width
      expect(ids(c.bottom), ['f1', 'f2']);
      expect(ids(c.left), ['f0', 'f1']);
      expect(ids(c.right), ['f2']);
      expect(c.innerWidths, isEmpty);
      expect(c.innerHeights, isEmpty);
    });

    test('row with a lower middle frame: every frame measured once', () {
      final c = build(const [
        Rect.fromLTRB(0, 0, 1200, 1500),
        Rect.fromLTRB(1200, 300, 2000, 1500),
        Rect.fromLTRB(2000, 0, 3000, 1500),
      ]).frameDimensionChains();
      final widths = {
        ...c.top.map((f) => f.primaryZoneId),
        ...c.bottom.map((f) => f.primaryZoneId),
        ...c.innerWidths.map((f) => f.primaryZoneId),
      };
      expect(widths, {'f0', 'f1', 'f2'});
      expect(c.top.length + c.bottom.length + c.innerWidths.length, 3);
      expect(c.innerHeights.map((f) => f.primaryZoneId), ['f1']);
    });

    test('a single frame has no chains', () {
      final c = build(const [
        Rect.fromLTRB(0, 0, 1200, 1500),
      ]).frameDimensionChains();
      expect(c.top, isEmpty);
      expect(c.left, isEmpty);
    });
  });

  group('typed frame dimension', () {
    test('wider lower frame pushes its neighbour and stretches the transom', () {
      final m = transom();
      m.resizeFrameOuterDimensionForZone('f1', isWidth: true, outerSize: 2352);
      expect(frame(m, 'f1').width, closeTo(2352, 1));
      expect(frame(m, 'f2').width, closeTo(551, 1)); // never shrunk
      expect(frame(m, 'f2').left, closeTo(2352, 1));
      expect(frame(m, 'f0').width, closeTo(2903, 1));
      expect(m.width, closeTo(2903, 1));
    });

    test('taller lower frame keeps the row level and grows the total', () {
      final m = transom();
      m.resizeFrameOuterDimensionForZone('f1', isWidth: false, outerSize: 1500);
      expect(frame(m, 'f1').height, closeTo(1500, 1));
      expect(frame(m, 'f2').height, closeTo(1500, 1));
      expect(frame(m, 'f0').height, closeTo(250, 1)); // transom untouched
      expect(m.height, closeTo(1750, 1));
    });

    test('taller transom moves the row down without shrinking it', () {
      final m = transom();
      m.resizeFrameOuterDimensionForZone('f0', isWidth: false, outerSize: 400);
      expect(frame(m, 'f1').height, closeTo(1343, 1));
      expect(frame(m, 'f1').top, closeTo(400, 1));
      expect(m.height, closeTo(1743, 1));
    });

    test('narrower transom leaves the frames under it unchanged', () {
      final m = transom();
      m.resizeFrameOuterDimensionForZone('f0', isWidth: true, outerSize: 2503);
      expect(frame(m, 'f0').width, closeTo(2503, 1));
      expect(frame(m, 'f1').width, closeTo(2152, 1));
      expect(frame(m, 'f2').width, closeTo(551, 1));
      expect(m.width, closeTo(2703, 1));
    });

    test('narrower lower frame: neighbour slides, transom keeps its size', () {
      final m = transom();
      m.resizeFrameOuterDimensionForZone('f1', isWidth: true, outerSize: 2000);
      expect(frame(m, 'f2').width, closeTo(551, 1));
      expect(frame(m, 'f2').left, closeTo(2000, 1));
      expect(frame(m, 'f0').width, closeTo(2703, 1));
    });

    test('transom drawn after the door: its own height changes', () {
      final m = build(const [
        Rect.fromLTRB(0, 429, 935, 2469), // the door, drawn first
        Rect.fromLTRB(0, 0, 935, 429), // the transom over it
      ]);
      expect(frame(m, 'f1').height, closeTo(429, 1));
      m.resizeFrameOuterDimensionForZone('f1', isWidth: false, outerSize: 590);
      expect(frame(m, 'f1').top, closeTo(0, 1));
      expect(frame(m, 'f1').height, closeTo(590, 1));
      expect(frame(m, 'f0').top, closeTo(590, 1));
      expect(frame(m, 'f0').height, closeTo(2040, 1)); // the door keeps its size
      expect(m.height, closeTo(2630, 1));
    });

    test('one undo restores the whole change', () {
      final m = transom();
      m.resizeFrameOuterDimensionForZone('f1', isWidth: true, outerSize: 2352);
      m.undo();
      expect(frame(m, 'f0').width, closeTo(2703, 1));
      expect(frame(m, 'f1').width, closeTo(2152, 1));
      expect(m.width, closeTo(2703, 1));
    });
  });
}
