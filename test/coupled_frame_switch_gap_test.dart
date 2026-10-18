import 'package:database_data/Commande/Systeme/model.dart';
import 'package:database_data/sql_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // TPR 40000: "40 149 Dormant scj D.T" (44.6) and "40 102 Dormant scj S.T" (28).
  final wide = AluminumSection(
    id: 136,
    seriesId: 11,
    code: '40 149',
    name: 'Dormant scj D.T',
    type: 'frame',
    thickness: 44.6,
    visibleWidth: 44.6,
  );
  final narrow = AluminumSection(
    id: 12,
    seriesId: 11,
    code: '40 102',
    name: 'Dormant scj S.T',
    type: 'frame',
    thickness: 28,
    visibleWidth: 28,
  );

  WindowModel coupledCasements() {
    final model = WindowModel(
      db: SqlDatabase(),
      width: 2000,
      height: 1416,
      profileThickness: 44.6,
    );
    model.activeSeries = AluminumSeries(
      id: 11,
      profileId: 5,
      name: 'Tpr 40000',
      type: 'Frappe',
      sections: [wide, narrow],
    );
    model.frameOverride = wide.toMap();
    model.updateProfileThickness();
    final t = model.profileThickness;
    model.coupleFrames = true;
    // Two frames side by side: the zones are separated by two frame jambs.
    model.zones = [
      WindowZone(
        id: 'left',
        boundary: Rect.fromLTRB(t, t, 1000 - t, 1416 - t),
        content: ZoneContent.singleSash,
      ),
      WindowZone(
        id: 'right',
        boundary: Rect.fromLTRB(1000 + t, t, 2000 - t, 1416 - t),
        content: ZoneContent.singleSash,
      ),
    ];
    return model;
  }

  test('switching the frame keeps both sashes against the coupled jambs', () {
    final model = coupledCasements();
    expect(model.getFrameRects(), hasLength(2));

    model.applyFrameOverride(
      narrow.toMap(),
      sliding: false,
      manualSelection: true,
    );
    expect(model.profileThickness, 28);

    final frames = model.getFrameRects()
      ..sort((a, b) => a.left.compareTo(b.left));
    final left = model.zones.firstWhere((z) => z.id == 'left').boundary;
    final right = model.zones.firstWhere((z) => z.id == 'right').boundary;
    final leftJambInner =
        frames[0].right -
        model.frameSideVisibleWidth(frames[0], 'right', fallback: 28);
    final rightJambInner =
        frames[1].left +
        model.frameSideVisibleWidth(frames[1], 'left', fallback: 28);

    // Outer jambs follow the new profile ...
    expect(left.left, closeTo(frames[0].left + 28, 0.01));
    expect(right.right, closeTo(frames[1].right - 28, 0.01));
    // ... and so must the jambs where the two frames meet.
    expect(left.right, closeTo(leftJambInner, 0.01));
    expect(right.left, closeTo(rightJambInner, 0.01));
    // The joint itself does not move.
    expect(frames[0].right, closeTo(1000, 0.01));
  });
}
