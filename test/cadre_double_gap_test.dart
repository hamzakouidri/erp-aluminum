import 'package:database_data/sql_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:database_data/Commande/Systeme/model.dart';

void main() {
  const frameSection = {'id': 'frame_50', 'visible_width': 50.0};

  WindowModel verticalSplit() {
    final model = WindowModel(
      db: SqlDatabase(),
      width: 1400,
      height: 1200,
      profileThickness: 45,
    );
    final sep = model.mullionThickness / 2;
    model.zones = [
      WindowZone(id: 'left', boundary: Rect.fromLTRB(45, 45, 700 - sep, 1155)),
      WindowZone(
        id: 'right',
        boundary: Rect.fromLTRB(700 + sep, 45, 1355, 1155),
      ),
    ];
    model.mullionCreationOrder['V_700.0'] = 1;
    model.selection = const SelectionInfo(
      type: SelectionType.mullion,
      isHorizontalMullion: false,
      mullionPosition: 700,
      mullionStart: 45,
      mullionEnd: 1155,
    );
    return model;
  }

  WindowModel horizontalTJunction() {
    final model = WindowModel(
      db: SqlDatabase(),
      width: 1400,
      height: 1600,
      profileThickness: 45,
    );
    final sep = model.mullionThickness / 2;
    model.zones = [
      WindowZone(id: 'top', boundary: Rect.fromLTRB(45, 45, 1355, 600 - sep)),
      WindowZone(
        id: 'bottom_left',
        boundary: Rect.fromLTRB(45, 600 + sep, 700 - sep, 1555),
      ),
      WindowZone(
        id: 'bottom_right',
        boundary: Rect.fromLTRB(700 + sep, 600 + sep, 1355, 1555),
      ),
    ];
    model.mullionCreationOrder['H_600.0'] = 1;
    model.mullionCreationOrder['V_700.0'] = 2;
    model.selection = const SelectionInfo(
      type: SelectionType.mullion,
      isHorizontalMullion: true,
      mullionPosition: 600,
      mullionStart: 45,
      mullionEnd: 1355,
    );
    return model;
  }

  Rect zone(WindowModel model, String id) =>
      model.zones.firstWhere((z) => z.id == id).boundary;

  group('Cadre double takes the real width of two frames', () {
    test('choosing Cadre double opens the gap to two frame widths', () {
      final model = verticalSplit();

      model.setMullionFrameSection(
        MullionProfileType.flat,
        Map<String, dynamic>.from(frameSection),
      );

      final left = zone(model, 'left');
      final right = zone(model, 'right');
      expect(right.left - left.right, closeTo(100.0, 0.01));
      expect(left.right, closeTo(650.0, 0.01));
      expect(right.left, closeTo(750.0, 0.01));
      // The outer size and the outer edges do not move.
      expect(model.width, 1400);
      expect(left.left, 45);
      expect(right.right, 1355);
      expect(model.doubleFrameAwareMullionGapAt(false, 700), 100.0);
      expect(model.getPhysicalFrameInfos(), hasLength(1));
    });

    test('a horizontal Cadre double re-spaces every zone along it', () {
      final model = horizontalTJunction();

      model.setMullionFrameSection(
        MullionProfileType.flat,
        Map<String, dynamic>.from(frameSection),
      );

      expect(zone(model, 'top').bottom, closeTo(550.0, 0.01));
      expect(zone(model, 'bottom_left').top, closeTo(650.0, 0.01));
      expect(zone(model, 'bottom_right').top, closeTo(650.0, 0.01));
      // The crossing vertical mullion is untouched.
      final sep = model.mullionThickness / 2;
      expect(zone(model, 'bottom_left').right, 700 - sep);
      expect(zone(model, 'bottom_right').left, 700 + sep);
    });

    test('going back to a standard mullion restores the ordinary gap', () {
      final model = verticalSplit();
      final before = model.zones.map((z) => z.boundary).toList();

      model.setMullionFrameSection(
        MullionProfileType.flat,
        Map<String, dynamic>.from(frameSection),
      );
      model.setMullionProfile(MullionProfileType.standard);

      final after = model.zones.map((z) => z.boundary).toList();
      for (var i = 0; i < before.length; i++) {
        expect(after[i].left, closeTo(before[i].left, 0.01));
        expect(after[i].right, closeTo(before[i].right, 0.01));
      }
    });

    test('undo restores the layout from before Cadre double', () {
      final model = verticalSplit();
      final before = model.zones.map((z) => z.boundary).toList();

      model.setMullionFrameSection(
        MullionProfileType.flat,
        Map<String, dynamic>.from(frameSection),
      );
      model.undo();

      expect(model.zones.map((z) => z.boundary).toList(), before);
    });

    test('other mullion types leave the zones unchanged', () {
      for (final type in [
        MullionProfileType.standard,
        MullionProfileType.grooved,
      ]) {
        final model = verticalSplit();
        final before = model.zones.map((z) => z.boundary).toList();

        model.setMullionFrameSection(
          type,
          Map<String, dynamic>.from(frameSection),
        );

        expect(model.zones.map((z) => z.boundary).toList(), before);
      }
    });

    test('setting a standard mullion again changes nothing', () {
      final model = horizontalTJunction();
      final before = model.zones.map((z) => z.boundary).toList();

      model.setMullionProfile(MullionProfileType.standard);

      expect(model.zones.map((z) => z.boundary).toList(), before);
    });

    // Catalogue rows can carry the width as text. The window must stay one
    // frame with one wide divider, not split into two frames.
    test('a width stored as text keeps the window one frame', () {
      final model = verticalSplit();
      final before = model.zones.map((z) => z.boundary).toList();

      model.setMullionFrameSection(MullionProfileType.flat, {
        'id': 'frame_70',
        'visible_width': '70',
      });

      final left = zone(model, 'left');
      final right = zone(model, 'right');
      expect(right.left - left.right, closeTo(140.0, 0.01));
      expect(model.frameProfileWidthAt(false, 700), 70.0);
      expect(model.getFrameRects(), hasLength(1));

      model.setMullionProfile(MullionProfileType.standard);

      final after = model.zones.map((z) => z.boundary).toList();
      for (var i = 0; i < before.length; i++) {
        expect(after[i].left, closeTo(before[i].left, 0.01));
        expect(after[i].right, closeTo(before[i].right, 0.01));
      }
      expect(model.getFrameRects(), hasLength(1));
    });
  });
}
