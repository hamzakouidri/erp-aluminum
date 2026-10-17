import 'package:database_data/sql_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:database_data/Commande/Systeme/model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Multi-Frame Physical Frame Dimensions Tests', () {
    test('Single frame returns 1 PhysicalFrameInfo with correct bounds', () {
      final model = WindowModel(
        db: SqlDatabase(),
        width: 1200,
        height: 1500,
        profileThickness: 45,
      );
      final pt = model.profileThickness;
      model.zones = [
        WindowZone(
          id: 'main_zone',
          boundary: Rect.fromLTWH(pt, pt, 1200 - 2 * pt, 1500 - 2 * pt),
        ),
      ];
      final frames = model.getPhysicalFrameInfos();
      expect(frames.length, equals(1));
      expect(frames.first.index, equals(0));
      expect(frames.first.rect.width, closeTo(1200, 1.0));
      expect(frames.first.rect.height, closeTo(1500, 1.0));
      expect(frames.first.primaryZoneId, equals('main_zone'));
    });

    test(
      'Two coupled frames with different heights are distinctly identified',
      () {
        final model = WindowModel(
          db: SqlDatabase(),
          width: 2500,
          height: 2000,
          profileThickness: 45,
        );
        final pt = model.profileThickness;
        final zone1 = WindowZone(
          id: 'z_left',
          boundary: Rect.fromLTRB(pt, pt, 1000 - pt, 1200 - pt),
        );
        final zone2 = WindowZone(
          id: 'z_right',
          boundary: Rect.fromLTRB(1000 + pt, pt, 2500 - pt, 2000 - pt),
        );
        model.zones = [zone1, zone2];
        model.coupleFrames = true;

        final frames = model.getPhysicalFrameInfos();
        expect(frames.length, equals(2));

        final sorted = List<PhysicalFrameInfo>.from(frames)
          ..sort((a, b) => a.rect.left.compareTo(b.rect.left));

        final leftFrame = sorted.first;
        final rightFrame = sorted.last;

        expect(leftFrame.primaryZoneId, equals('z_left'));
        expect(rightFrame.primaryZoneId, equals('z_right'));

        expect(leftFrame.rect.height, closeTo(1200, 2.0));
        expect(rightFrame.rect.height, closeTo(2000, 2.0));

        final hasVaryingHeights =
            (leftFrame.rect.height - rightFrame.rect.height).abs() > 1.0;
        expect(hasVaryingHeights, isTrue);
      },
    );

    test(
      'Three frames configuration detects leftmost, intermediate, and rightmost',
      () {
        final model = WindowModel(
          db: SqlDatabase(),
          width: 3000,
          height: 1800,
          profileThickness: 45,
        );
        final pt = model.profileThickness;
        final z1 = WindowZone(
          id: 'z1',
          boundary: Rect.fromLTRB(pt, pt, 800 - pt, 1200 - pt),
        );
        final z2 = WindowZone(
          id: 'z2',
          boundary: Rect.fromLTRB(800 + pt, pt, 2200 - pt, 1800 - pt),
        );
        final z3 = WindowZone(
          id: 'z3',
          boundary: Rect.fromLTRB(2200 + pt, pt, 3000 - pt, 1200 - pt),
        );
        model.zones = [z1, z2, z3];
        model.coupleFrames = true;

        final frames = model.getPhysicalFrameInfos();
        expect(frames.length, equals(3));

        final sorted = List<PhysicalFrameInfo>.from(frames)
          ..sort((a, b) => a.rect.left.compareTo(b.rect.left));

        expect(sorted[0].primaryZoneId, equals('z1'));
        expect(sorted[1].primaryZoneId, equals('z2'));
        expect(sorted[2].primaryZoneId, equals('z3'));

        // Check intermediate frame height
        expect(sorted[1].rect.height, closeTo(1800, 2.0));
        // Left and right frame heights
        expect(sorted[0].rect.height, closeTo(1200, 2.0));
        expect(sorted[2].rect.height, closeTo(1200, 2.0));

        final hasVaryingHeights = sorted.any(
          (f) => (f.rect.height - sorted.first.rect.height).abs() > 1.0,
        );
        expect(hasVaryingHeights, isTrue);

        // Intermediate dimX formula test
        final intermediateX =
            sorted[1].rect.left +
            (sorted[1].rect.width * 0.28).clamp(0.0, 65.0);
        expect(intermediateX, greaterThan(sorted[1].rect.left));
        expect(intermediateX, lessThan(sorted[1].rect.right));
      },
    );

    test('Frame with internal mullions stays grouped as 1 physical frame', () {
      final model = WindowModel(
        db: SqlDatabase(),
        width: 1400,
        height: 1600,
        profileThickness: 45,
      );
      final pt = model.profileThickness;
      final mt = model.mullionThickness;

      // 1 frame divided into top and bottom panes by a mullion
      final topZone = WindowZone(
        id: 'pane_top',
        boundary: Rect.fromLTRB(pt, pt, 1400 - pt, 600 - mt / 2),
      );
      final bottomZone = WindowZone(
        id: 'pane_bottom',
        boundary: Rect.fromLTRB(pt, 600 + mt / 2, 1400 - pt, 1600 - pt),
      );
      model.zones = [topZone, bottomZone];

      final frames = model.getPhysicalFrameInfos();
      expect(frames.length, equals(1));
      expect(frames.first.zones.length, equals(2));
      expect(frames.first.rect.width, closeTo(1400, 2.0));
      expect(frames.first.rect.height, closeTo(1600, 2.0));
    });

    test('a moved wide internal mullion does not become a second frame', () {
      final model = WindowModel(
        db: SqlDatabase(),
        width: 1400,
        height: 1600,
        profileThickness: 45,
      );
      const split = 600.0;
      model.zones = [
        WindowZone(
          id: 'pane_top_wide',
          boundary: const Rect.fromLTRB(45, 45, 1355, 550),
        ),
        WindowZone(
          id: 'pane_bottom_wide',
          boundary: const Rect.fromLTRB(45, 650, 1355, 1555),
        ),
      ];
      model.mullionProfiles['H_600.0'] = MullionProfileType.flat;
      model.mullionCreationOrder['H_600.0'] = 1;
      model.mullionSectionOverrides['H_600.0'] = {
        'visible_width': 50.0,
        'is_double_frame': 1,
      };

      expect(model.getPhysicalFrameInfos(), hasLength(1));

      model.selection = const SelectionInfo(
        type: SelectionType.mullion,
        isHorizontalMullion: true,
        mullionPosition: split,
        mullionStart: 45,
        mullionEnd: 1355,
      );
      model.moveSelectedMullion(40);

      expect(model.getPhysicalFrameInfos(), hasLength(1));
    });

    test('one undo restores the complete mullion drag', () {
      final model = WindowModel(
        db: SqlDatabase(),
        width: 1200,
        height: 1000,
        profileThickness: 50,
      );
      model.zones = [
        WindowZone(
          id: 'top_drag',
          boundary: const Rect.fromLTRB(50, 50, 1150, 475),
        ),
        WindowZone(
          id: 'bottom_drag',
          boundary: const Rect.fromLTRB(50, 525, 1150, 950),
        ),
      ];
      model.mullionCreationOrder['H_500.0'] = 1;
      model.selection = const SelectionInfo(
        type: SelectionType.mullion,
        isHorizontalMullion: true,
        mullionPosition: 500,
        mullionStart: 50,
        mullionEnd: 1150,
      );
      final before = model.zones.map((zone) => zone.boundary).toList();

      model.saveSnapshotOutside();
      model.moveSelectedMullionWithHistory(10, saveHistory: false);
      model.moveSelectedMullionWithHistory(15, saveHistory: false);
      model.moveSelectedMullionWithHistory(20, saveHistory: false);
      expect(model.zones.first.boundary, isNot(before.first));

      model.undo();

      expect(model.zones.map((zone) => zone.boundary).toList(), before);
    });

    // Coupled frames are closed onto one shared seam (the profile-angle tube
    // sits behind the corner, not between the frames), so their top edge is
    // one continuous segment.
    test('coupled frames close the gap into one top edge', () {
      final model = WindowModel(
        db: SqlDatabase(),
        width: 2460,
        height: 1300,
        profileThickness: 45,
      );
      model.zones = [
        WindowZone(
          id: 'angle_left',
          boundary: const Rect.fromLTRB(45, 45, 1155, 1255),
        ),
        WindowZone(
          id: 'angle_right',
          boundary: const Rect.fromLTRB(1305, 45, 2415, 1255),
        ),
      ];
      model.coupleFrames = true;

      final topEdges = model
          .getExposedFrameEdgeSegments()
          .where((edge) => edge.side == 'top')
          .toList();

      final rects = model.getFrameRects();
      expect(rects, hasLength(2));
      expect(rects.first.right, rects.last.left);
      expect(topEdges, hasLength(1));
    });

    test('undo restores profile-angle state exactly', () {
      final model = WindowModel(
        db: SqlDatabase(),
        width: 2400,
        height: 1300,
        profileThickness: 45,
      );
      model.zones = [
        WindowZone(
          id: 'undo_angle_left',
          boundary: const Rect.fromLTRB(45, 45, 1155, 1255),
        ),
        WindowZone(
          id: 'undo_angle_right',
          boundary: const Rect.fromLTRB(1245, 45, 2355, 1255),
        ),
      ];
      model.coupleFrames = true;
      expect(model.usesProfileAngle, isFalse);
      final cornerViewBefore = model.viewAs90DegreeCorner;

      model.setAllProfileAngleJunctions(true);
      expect(model.usesProfileAngle, isTrue);

      model.undo();

      expect(model.profileAngleMode, 0);
      expect(model.profileAngleJunctions, isEmpty);
      expect(model.usesProfileAngle, isFalse);
      expect(model.viewAs90DegreeCorner, cornerViewBefore);
    });
  });
}
