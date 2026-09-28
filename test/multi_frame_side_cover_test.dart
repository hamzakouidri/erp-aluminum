import 'dart:ui';

import 'package:database_data/Commande/Systeme/model.dart';
import 'package:database_data/sql_database.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'multiple frames default to no side cover but allow explicit enable',
    () async {
    final model = WindowModel(
      db: SqlDatabase(),
      width: 500,
      height: 200,
      profileThickness: 10,
    );
    model.zones = [
      WindowZone(
        id: 'left',
        boundary: const Rect.fromLTWH(10, 10, 100, 100),
      ),
      WindowZone(
        id: 'right',
        boundary: const Rect.fromLTWH(250, 10, 100, 100),
      ),
    ];
    model.hasSideCovers = true;

    model.notifyListeners();
    expect(model.getFrameRects(), hasLength(2));
    expect(model.hasSideCovers, isFalse);

    await model.toggleSideCovers(true);
    expect(model.hasSideCovers, isTrue);

    model.notifyListeners();
    expect(model.hasSideCovers, isTrue);
    },
  );

  test(
    'multiple frames automatically switch integrated cover frame to plain frame',
    () {
      final model = WindowModel(
        db: SqlDatabase(),
        width: 500,
        height: 200,
        profileThickness: 10,
      );
      final series = AluminumSeries(
        id: 1,
        profileId: 1,
        name: 'Standard Series',
        type: 'opening',
      );
      final integratedFrame = AluminumSection(
        id: 10,
        seriesId: 1,
        name: 'Cadre avec couvre-joint integre',
        code: 'FRAME-INT',
        type: 'frame',
        isFrame: true,
        designIntegratedSideCover: true,
      );
      final plainFrame = AluminumSection(
        id: 11,
        seriesId: 1,
        name: 'Cadre simple sans couvre-joint',
        code: 'FRAME-PLAIN',
        type: 'frame',
        isFrame: true,
        designIntegratedSideCover: false,
      );
      series.sections = [integratedFrame, plainFrame];
      model.activeSeries = series;

      // Start with single frame and integrated frame override
      model.zones = [
        WindowZone(
          id: 'single',
          boundary: const Rect.fromLTWH(50, 50, 400, 100),
        ),
      ];
      model.frameOverride = integratedFrame.toMap();
      expect(model.isIntegratedFrame, isTrue);

      // Now add a second frame to become multi-frame
      model.zones = [
        WindowZone(
          id: 'left',
          boundary: const Rect.fromLTWH(50, 50, 150, 100),
        ),
        WindowZone(
          id: 'right',
          boundary: const Rect.fromLTWH(250, 50, 150, 100),
        ),
      ];
      model.notifyListeners();

      expect(model.getFrameRects(), hasLength(2));
      expect(model.isIntegratedFrame, isFalse);
      expect(model.frameOverride?['code'], 'FRAME-PLAIN');
    },
  );
}
