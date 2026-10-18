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
      expect(
        geometry([
          divider('a', ZoneEdge.top, 0.2, ZoneEdge.bottom, 0.8),
          divider('b', ZoneEdge.top, 0.8, ZoneEdge.bottom, 0.2),
        ]).validate(),
        SlantedDivisionError.crossesDivider,
      );
      expect(
        geometry([
          divider('a', ZoneEdge.top, 0.30, ZoneEdge.bottom, 0.30),
          divider('b', ZoneEdge.top, 0.35, ZoneEdge.bottom, 0.35),
        ]).validate(),
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
