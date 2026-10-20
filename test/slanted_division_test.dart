import 'package:database_data/Commande/Systeme/calculate_component.dart';
import 'package:database_data/Commande/Systeme/model.dart';
import 'package:database_data/Commande/Systeme/model_serialization.dart';
import 'package:database_data/sql_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const clear = Rect.fromLTRB(0, 0, 2000, 3800);

  SlantedDivider divider(
    String id,
    ZoneEdge startEdge,
    double startRatio,
    ZoneEdge endEdge,
    double endRatio,
  ) => SlantedDivider(
    id: id,
    start: SlantedDividerAnchor(startEdge, startRatio),
    end: SlantedDividerAnchor(endEdge, endRatio),
  );

  SlantedDivisionGeometry geometry(List<SlantedDivider> dividers) =>
      SlantedDivisionGeometry(
        clear: clear,
        dividers: dividers,
        profileWidth: 60,
      );

  group('SlantedDivisionGeometry', () {
    test('crossing divisions: four cells, the later one cut in two', () {
      final g = geometry([
        divider('a', ZoneEdge.top, 0.2, ZoneEdge.bottom, 0.8),
        divider('b', ZoneEdge.top, 0.8, ZoneEdge.bottom, 0.2),
      ]);
      expect(g.validate(), isNull);
      expect(g.cells(), hasLength(4));
      final first = g.cutPieces(g.dividers[0]);
      final second = g.cutPieces(g.dividers[1]);
      expect(first, hasLength(1));
      expect(second, hasLength(2));
      // The two bars of the crossing division are shorter than the whole.
      final whole = g.cutLengthMm(g.dividers[1]);
      for (final piece in second) {
        expect(piece.lengthMm, lessThan(whole));
        expect(piece.lengthMm, greaterThan(whole / 4));
      }
      expect(
        second.first.endAngleDeg,
        closeTo(g.crossingAngleDeg(g.dividers[0], g.dividers[1]) / 2, 1e-6),
      );
    });

    test('divisions crossing at a sharp angle are refused', () {
      expect(
        geometry([
          divider('a', ZoneEdge.top, 0.40, ZoneEdge.bottom, 0.50),
          divider('b', ZoneEdge.top, 0.50, ZoneEdge.bottom, 0.40),
        ]).validate(),
        SlantedDivisionError.crossesDivider,
      );
    });

    test('one top-to-bottom division splits the glass into two cells', () {
      final g = geometry([
        divider('d', ZoneEdge.top, 0.2, ZoneEdge.bottom, 0.4),
      ]);
      expect(g.validate(), isNull);
      final cells = g.cells();
      expect(cells, hasLength(2));
      final band = g.band(g.dividers.first);
      final total =
          cells
              .map(SlantedDivisionGeometry.polygonArea)
              .reduce((a, b) => a + b) +
          SlantedDivisionGeometry.polygonArea(band);
      expect(total, closeTo(clear.width * clear.height, 1.0));
      // Left cell first (same centroid row ordering falls back to x).
      expect(
        SlantedDivisionGeometry.centroid(cells.first).dx,
        lessThan(SlantedDivisionGeometry.centroid(cells.last).dx),
      );
    });

    test('angle with the edge and the halved workshop cut angle', () {
      final g = geometry([
        divider('d', ZoneEdge.left, 0.2, ZoneEdge.right, 0.2 + 2000 / 3800),
      ]);
      final d = g.dividers.first;
      expect(g.angleWithEdgeDeg(d, atStart: true), closeTo(45, 0.01));
      expect(g.cutAngleDeg(d, atStart: true), closeTo(22.5, 0.01));
      // Ends on parallel sides: the band is a parallelogram, so the long
      // point equals the centre-line length.
      final (a, b) = g.centreLine(d);
      expect(g.cutLengthMm(d), closeTo((b - a).distance, 0.01));
      // Ends on adjacent sides: the outer side is longer than the centre.
      final corner = geometry([
        divider('c', ZoneEdge.top, 0.5, ZoneEdge.right, 0.3),
      ]);
      final c = corner.dividers.first;
      final (ca, cb) = corner.centreLine(c);
      expect(corner.cutLengthMm(c), greaterThan((cb - ca).distance));
    });

    test('rejects impossible layouts', () {
      expect(
        geometry([
          divider('d', ZoneEdge.top, 0.2, ZoneEdge.top, 0.8),
        ]).validate(),
        SlantedDivisionError.sameEdge,
      );
      expect(
        geometry([
          divider('d', ZoneEdge.top, 0.001, ZoneEdge.bottom, 0.5),
        ]).validate(),
        SlantedDivisionError.tooCloseToCorner,
      );
      // Nearly flat across a tall zone: ~4° with the left/right edges' normal.
      expect(
        geometry([
          divider('d', ZoneEdge.left, 0.40, ZoneEdge.right, 0.42),
        ]).validate(),
        isNull,
      );
      expect(
        geometry([
          divider('d', ZoneEdge.top, 0.1, ZoneEdge.left, 0.9),
        ]).validate(),
        SlantedDivisionError.angleTooSharp,
      );
      // Two divisions may cross at a clean angle.
      expect(
        geometry([
          divider('a', ZoneEdge.top, 0.2, ZoneEdge.bottom, 0.8),
          divider('b', ZoneEdge.top, 0.8, ZoneEdge.bottom, 0.2),
        ]).validate(),
        isNull,
      );
      expect(
        geometry([
          divider('a', ZoneEdge.top, 0.30, ZoneEdge.bottom, 0.30),
          divider('b', ZoneEdge.top, 0.35, ZoneEdge.bottom, 0.35),
        ]).validate(),
        SlantedDivisionError.cellTooSmall,
      );
    });

    test('a later division stays in the cell it was drawn in', () {
      final slant = divider('a', ZoneEdge.top, 0.2, ZoneEdge.bottom, 0.8);
      // Horizontal, drawn left of the slanted division.
      const across = SlantedDivider(
        id: 'h',
        start: SlantedDividerAnchor(ZoneEdge.left, 0.5),
        end: SlantedDividerAnchor(ZoneEdge.right, 0.5),
        seed: Offset(0.05, 0.5),
      );
      final g = geometry([slant, across]);
      expect(g.validate(), isNull);
      // Only the left part is split: three panes, the slant stays whole.
      expect(g.cells(), hasLength(3));
      expect(g.cutPieces(slant), hasLength(1));
      expect(g.cutPieces(across), hasLength(1));
      // It runs from the left side to the slanted division (x = 1000 at
      // mid-height), stopping on its face.
      final (a, b) = g.centreLine(across);
      expect(a.dx, closeTo(0, 0.01));
      expect(b.dx, inInclusiveRange(940, 1000));
      expect(g.endMeets(across, atStart: true).edge, ZoneEdge.left);
      expect(g.endMeets(across, atStart: false).divider?.id, 'a');
      expect(
        g.angleWithEdgeDeg(across, atStart: false),
        closeTo(g.crossingAngleDeg(slant, across), 1e-6),
      );
      expect(g.cutLengthMm(across), lessThan(1000));
      // Survives serialization.
      final restored = SlantedDivider.fromMap(across.toMap())!;
      expect(restored.seed, const Offset(0.05, 0.5));
    });

    test('a confined division keeps the 80 mm glass rule', () {
      final slant = divider('a', ZoneEdge.top, 0.2, ZoneEdge.bottom, 0.8);
      const nearTop = SlantedDivider(
        id: 'h',
        start: SlantedDividerAnchor(ZoneEdge.left, 100 / 3800),
        end: SlantedDividerAnchor(ZoneEdge.right, 100 / 3800),
        seed: Offset(0.05, 100 / 3800),
      );
      expect(
        geometry([slant, nearTop]).validate(),
        SlantedDivisionError.cellTooSmall,
      );
    });

    test('pricing rectangle follows the longest (slanted) side', () {
      // Right triangle 3000 x 1000: hypotenuse is the longest side.
      final r = SlantedDivisionGeometry.pricingRectangle(const [
        Offset(0, 0),
        Offset(3000, 0),
        Offset(0, 1000),
      ]);
      expect(r.width, closeTo(3162.28, 0.1));
      expect(r.height, closeTo(948.68, 0.1));
    });
  });

  group('WindowZone / WindowModel', () {
    WindowModel makeModel(ZoneContent content) {
      final model = WindowModel(
        db: SqlDatabase(),
        width: 2120,
        height: 3920,
        profileThickness: 60,
      );
      model.zones = [
        WindowZone(id: 'z', boundary: const Rect.fromLTRB(60, 60, 2060, 3860)),
      ];
      model.zones.first.content = content;
      return model;
    }

    test('dividers survive serialization and clone', () {
      final zone = WindowZone(
        id: 'z',
        boundary: clear,
        slantedDividers: [
          divider('d', ZoneEdge.top, 0.25, ZoneEdge.bottom, 0.5),
        ],
      );
      final restored = windowZoneFromMap(zone.toMap());
      expect(restored.slantedDividers, hasLength(1));
      expect(restored.slantedDividers.first.start.edge, ZoneEdge.top);
      expect(restored.slantedDividers.first.end.ratio, 0.5);
      expect(zone.clone().slantedDividers, hasLength(1));
      expect(zone.cloneForSplit(clear).slantedDividers, isEmpty);
    });

    test('only fixed zones accept a slanted division, with one undo', () {
      final sash = makeModel(ZoneContent.singleSash);
      expect(
        sash.setSlantedDivider(
          'z',
          divider('d', ZoneEdge.top, 0.25, ZoneEdge.bottom, 0.5),
        ),
        SlantedDivisionError.notFixedZone,
      );

      final fixed = makeModel(ZoneContent.fixedGlass);
      expect(
        fixed.setSlantedDivider(
          'z',
          divider('d', ZoneEdge.top, 0.25, ZoneEdge.bottom, 0.5),
        ),
        isNull,
      );
      expect(fixed.zones.first.slantedDividers, hasLength(1));
      fixed.undo();
      expect(fixed.zones.first.slantedDividers, isEmpty);
    });

    test('a straight stroke after a slanted one stays in its cell', () {
      final model = makeModel(ZoneContent.fixedGlass);
      void stroke(Offset from, Offset to) {
        model.startDrawing(from);
        model.updateDrawing(to);
        model.endDrawing();
      }

      // Slanted, then horizontal left of it (the slant is at x ≈ 1055).
      stroke(const Offset(300, 300), const Offset(1500, 3000));
      expect(model.drawingNotice, isNull);
      stroke(const Offset(150, 2000), const Offset(700, 2010));
      expect(model.drawingNotice, isNull);
      expect(model.zones, hasLength(1));
      final zone = model.zones.single;
      expect(zone.slantedDividers, hasLength(2));
      final g = model.slantedGeometryFor(zone);
      expect(g.cells(), hasLength(3));
      // The first (slanted) division is never cut by the later one.
      expect(g.cutPieces(zone.slantedDividers.first), hasLength(1));
      expect(
        g.endMeets(zone.slantedDividers.last, atStart: false).divider?.id,
        zone.slantedDividers.first.id,
      );

      // A pane under 80 mm is refused and nothing changes.
      stroke(const Offset(150, 110), const Offset(600, 112));
      expect(model.drawingNotice, SlantedDivisionError.cellTooSmall);
      expect(model.zones.single.slantedDividers, hasLength(2));
    });

    test('turning the zone into a sash removes its slanted divisions', () {
      final model = makeModel(ZoneContent.fixedGlass);
      model.setSlantedDivider(
        'z',
        divider('d', ZoneEdge.top, 0.25, ZoneEdge.bottom, 0.5),
      );
      model.paintZoneContent('z', ZoneContent.singleSash);
      expect(model.zones.first.slantedDividers, isEmpty);
    });
    test('cutting list: bar, shaped glass and mitred parclose', () {
      final model = makeModel(ZoneContent.fixedGlass);
      expect(
        model.setSlantedDivider(
          'z',
          divider('d', ZoneEdge.top, 0.19, ZoneEdge.bottom, 0.39),
        ),
        isNull,
      );
      final bom = ComponentCalculator.generateBom(model, {});

      final bar = bom.singleWhere(
        (i) => i.originalName.contains('Traverse inclinée'),
      );
      expect(bar.pieces, hasLength(1));
      // The drawing angle (~84°) is halved for the saw at both ends.
      expect(bar.pieceCutAngles, ['42.0/42.0']);

      final glass = bom.where((i) => i.category == 'glass').toList();
      expect(glass, hasLength(2));
      for (final g in glass) {
        expect(g.name, contains('Forme'));
        // Priced as the rectangle along the longest (slanted) side.
        expect(g.length!, greaterThan(3700));
      }

      final parclose = bom.firstWhere(
        (i) =>
            i.pieces != null &&
            i.pieces!.length == 8 &&
            i.pieceCutAngles != null,
      );
      expect(parclose.pieceCutAngles, contains('45.0/48.0'));
    });
  });
}
