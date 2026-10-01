import 'dart:ui';

import 'package:database_data/Commande/Systeme/model.dart';
import 'package:database_data/sql_database.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('selecting a frame preserves window zones and frame rects', () {
    final model = WindowModel(
      db: SqlDatabase(),
      width: 1200,
      height: 1000,
      profileThickness: 50,
    );
    model.zones = [
      WindowZone(
        id: 'z1',
        boundary: const Rect.fromLTWH(50, 50, 1100, 900),
        content: ZoneContent.fixedGlass,
      ),
    ];

    expect(model.getFrameRects(), hasLength(1));
    expect(model.zones, hasLength(1));

    // When a frame is selected
    model.selectFrameByIndex(0);
    expect(model.selection.type, equals(SelectionType.frame));
    expect(model.getFrameRects(), hasLength(1));
    expect(model.zones, isNotEmpty);
    expect(model.zones.first.id, equals('z1'));

    model.dispose();
  });

  test('selecting a mullion preserves window zones and mullion position', () {
    final model = WindowModel(
      db: SqlDatabase(),
      width: 1200,
      height: 1000,
      profileThickness: 50,
    );
    model.zones = [
      WindowZone(
        id: 'z1',
        boundary: const Rect.fromLTWH(50, 50, 525, 900),
        content: ZoneContent.fixedGlass,
      ),
      WindowZone(
        id: 'z2',
        boundary: const Rect.fromLTWH(625, 50, 525, 900),
        content: ZoneContent.fixedGlass,
      ),
    ];

    model.selection = SelectionInfo.mullion(
      false,
      600.0,
      start: 50.0,
      end: 950.0,
    );

    expect(model.selection.type, equals(SelectionType.mullion));
    expect(model.selection.isHorizontalMullion, isFalse);
    expect(model.selection.mullionPosition, equals(600.0));
    expect(model.zones, hasLength(2));

    model.dispose();
  });
}
