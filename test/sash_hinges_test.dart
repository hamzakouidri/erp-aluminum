import 'package:database_data/Commande/Systeme/model.dart';
import 'package:database_data/Commande/Systeme/model_serialization.dart';
import 'package:database_data/sql_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SashHingeRules', () {
    test('automatic layout matches the old drawing (100 mm insets)', () {
      expect(SashHingeRules.automatic(1200, 3), [100, 600, 1100]);
    });

    test('legacy middle offset moves the second hinge from the head', () {
      // Old drawing: second hinge from the top moved 50 mm down.
      final p = SashHingeRules.automatic(1200, 3, middleOffset: 50);
      expect(p, [100, 550, 1100]);
    });

    test('moves stay between neighbours, ends and snap to 10 mm', () {
      final p = [100.0, 600.0, 1100.0];
      expect(SashHingeRules.clampMove(p, 1, 233, 1200), 250);
      expect(SashHingeRules.clampMove(p, 1, 0, 1200), 250); // 100 + 150
      expect(SashHingeRules.clampMove(p, 0, 0, 1200), 80);
      expect(SashHingeRules.clampMove(p, 2, 5000, 1200), 1120);
    });

    test('numeric hinge editing preserves the exact entered distance', () {
      final p = [100.0, 600.0, 1100.0];
      expect(
        SashHingeRules.clampMove(
          p,
          1,
          526,
          1200,
          snapToGrid: false,
        ),
        526,
      );
    });

    test('nearest gap: to the closer neighbour, read from the bottom', () {
      final p = [100.0, 600.0, 1100.0];
      // Middle hinge moved up next to the top one: 1100 - 1000 = 100.
      expect(SashHingeRules.nearestGap([100, 1000, 1100], 1, 1200),
          (from: 1000.0, to: 1100.0));
      expect(SashHingeRules.nearestGap(p, 0, 1200), (from: 0.0, to: 100.0));
      expect(SashHingeRules.nearestGap(p, 2, 1200), (from: 1100.0, to: 1200.0));
      expect(SashHingeRules.nearestGap([100, 450, 1100], 1, 1200),
          (from: 100.0, to: 450.0));
    });

    test('insertion respects the minimum distances', () {
      expect(SashHingeRules.insertionPoint([100, 1100], 1200), 600);
      expect(SashHingeRules.insertionPoint([100, 1100], 1200, near: 120), 250);
      expect(SashHingeRules.insertionPoint([80, 230], 310), isNull);
    });

    test('resize keeps the end hinges at their distance from each end', () {
      final layout = SashHingeLayout(
        positions: [150, 500, 1050],
        referenceLength: 1200,
      );
      final p = SashHingeRules.fitToLength(layout, 1400);
      expect(p.first, 150);
      expect(p.last, 1250); // still 150 mm under the head
      expect(p[1], closeTo(150 + 350 * 1100 / 900, 0.01));
    });

    test('too short an edge falls back to an even spread', () {
      final layout = SashHingeLayout(
        positions: [100, 400, 700, 1000],
        referenceLength: 1100,
      );
      final p = SashHingeRules.fitToLength(layout, 500);
      expect(SashHingeRules.isValid(p, 500), isTrue);
      expect(p.length, SashHingeRules.maxCountFor(500));
    });
  });

  group('WindowModel hinges', () {
    WindowModel makeModel(ZoneContent content) {
      final model = WindowModel(
        db: SqlDatabase(),
        width: 1320,
        height: 1320,
        profileThickness: 60,
      );
      model.zones = [
        WindowZone(
          id: 'z',
          boundary: const Rect.fromLTRB(60, 60, 1260, 1260),
          content: content,
          openDirection: OpenDirection.left,
        ),
      ];
      return model;
    }

    test('double sash: both leaves add, move and remove together', () {
      final model = makeModel(ZoneContent.doubleSash);
      final zone = model.zones.first;
      expect(model.hingeCountForLeaf(zone, 0), 3);
      expect(model.hingeCountForLeaf(zone, 1), 3);

      expect(model.addHinge('z', 1, 1200), isNull);
      expect(model.hingeCountForLeaf(zone, 1), 4);
      expect(model.hingeCountForLeaf(zone, 0), 4);
      expect(model.selectedHinge?.leaf, 1);

      model.moveHinge('z', 1, 0, 300, 1200);
      final moved = model.hingePositionsFor(zone, 1, 1200);
      expect(moved.first, lessThanOrEqualTo(300));
      expect(model.hingePositionsFor(zone, 0, 1200), moved);

      expect(model.removeHinge('z', 1, 0, 1200), isNull);
      expect(model.removeHinge('z', 1, 0, 1200), isNull);
      expect(
        model.removeHinge('z', 1, 0, 1200),
        WindowModel.hingeMinCountKey,
      );
      expect(model.hingeCountForLeaf(zone, 1), 2);
      expect(model.hingeCountForLeaf(zone, 0), 2);

      model.resetHinges('z', leaf: 1);
      expect(model.hingeCountForLeaf(zone, 1), 3);
      expect(model.hingeCountForLeaf(zone, 0), 3);
    });

    test('OB kit leaf of a double sash does not follow its partner', () {
      final model = makeModel(ZoneContent.doubleSash)..useSystemOB = true;
      final zone = model.zones.first; // opens left: leaf 0 has the handle
      expect(model.addHinge('z', 1, 1200), isNull);
      expect(model.hingeCountForLeaf(zone, 1), 4);
      expect(model.hingePositionsFor(zone, 0, 1200), [44, 1156]);
    });

    test('undo restores the previous hinges', () {
      final model = makeModel(ZoneContent.singleSash);
      model.addHinge('z', 0, 1200);
      expect(model.hingeCountForLeaf(model.zones.first, 0), 4);
      model.undo();
      expect(model.hingeCountForLeaf(model.zones.first, 0), 3);
    });

    test('OB kit leaf is locked', () {
      final model = makeModel(ZoneContent.singleSash)..useSystemOB = true;
      expect(model.addHinge('z', 0, 1200), WindowModel.hingeObLockedKey);
      expect(model.hingePositionsFor(model.zones.first, 0, 1200), [44, 1156]);
    });

    test('hand-placed hinges survive serialization and clone', () {
      final zone = WindowZone(
        id: 'z',
        boundary: const Rect.fromLTRB(0, 0, 800, 1500),
        content: ZoneContent.singleSash,
        customHinges: {
          0: SashHingeLayout(positions: [120, 700, 1380], referenceLength: 1500),
        },
      );
      final restored = windowZoneFromMap(zone.toMap());
      expect(restored.customHinges[0]?.positions, [120, 700, 1380]);
      expect(restored.customHinges[0]?.referenceLength, 1500);
      expect(zone.clone().customHinges[0]?.positions, [120, 700, 1380]);
    });

    test('malformed hinge data falls back to automatic', () {
      final map = WindowZone(
        id: 'z',
        boundary: const Rect.fromLTRB(0, 0, 800, 1500),
      ).toMap()..['customHinges'] = {'0': {'positions': 'x'}};
      expect(windowZoneFromMap(map).customHinges, isEmpty);
    });
  });
}
