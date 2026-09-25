import 'dart:ui';

import 'package:database_data/Commande/Systeme/model.dart';
import 'package:database_data/sql_database.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  WindowModel drawing(double integratedWidth) {
    return WindowModel(db: SqlDatabase(), width: 500, height: 200)
      ..frameOverride = {
        'id': 1,
        'series_id': 1,
        'code': 'F1',
        'name': 'Frame',
        'type': 'frame',
        'design_integrated_side_cover': 1,
        'couvre_joint_width': integratedWidth,
      }
      ..selectedSideCover = AluminumSection.fromMap({
        'id': 2,
        'series_id': 1,
        'code': 'C2',
        'name': 'Cover',
        'type': 'side_cover',
        'couvre_joint_width': 80.0,
      })
      ..zones = [
        WindowZone(id: 'left', boundary: const Rect.fromLTWH(10, 10, 100, 100)),
        WindowZone(id: 'right', boundary: const Rect.fromLTWH(250, 10, 100, 100)),
      ];
  }

  test('multiple frames retain the selected integrated profile width', () {
    final model = drawing(25);
    expect(model.getFrameRects(), hasLength(2));
    expect(model.isIntegratedFrame, isTrue);
    expect(model.sideCoverWidth, 25);
  });

  test('missing integrated width never uses the standalone cover width', () {
    final model = drawing(0);
    expect(model.isIntegratedFrame, isTrue);
    expect(model.sideCoverWidth, 0);
  });

  test('a plain frame uses its separately selected cover', () {
    final model = drawing(0);
    model.frameOverride!['design_integrated_side_cover'] = 0;
    expect(model.isIntegratedFrame, isFalse);
    expect(model.sideCoverWidth, model.standaloneSideCoverWidth);
    expect(model.sideCoverWidth, greaterThan(0));
  });
}
