import 'package:database_data/Commande/Systeme/model.dart';
import 'package:database_data/sql_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  WindowModel twoFrames() {
    final model = WindowModel(
      db: SqlDatabase(),
      width: 2000,
      height: 1400,
      profileThickness: 50,
    );
    model.coupleFrames = true;
    model.zones = [
      WindowZone(
        id: 'left',
        boundary: const Rect.fromLTRB(50, 50, 950, 1350),
        content: ZoneContent.fixedGlass,
      ),
      WindowZone(
        id: 'right',
        boundary: const Rect.fromLTRB(1050, 50, 1950, 1350),
        content: ZoneContent.fixedGlass,
      ),
    ];
    return model;
  }

  test('a press on the outer border selects the frame under it', () {
    final model = twoFrames();
    expect(model.getFrameRects(), hasLength(2));

    // Right jamb of the right frame, then the left jamb of the left one.
    model.selectAt(const Offset(1980, 700), isLongPress: true);
    expect(model.selection.type, SelectionType.frame);
    expect(model.selection.zoneId, 'frame:1');
    model.selectAt(const Offset(20, 700), isLongPress: true);
    expect(model.selection.zoneId, 'frame:0');
  });

  test('a long press on the right frame deletes the right frame', () {
    final model = twoFrames();
    model.selectAt(const Offset(1500, 1385), isLongPress: true);
    model.deleteSelectedFrame();
    expect(model.zones.map((z) => z.id), ['left']);
  });
}
