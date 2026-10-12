import 'dart:ui';

import 'package:database_data/Commande/Systeme/model.dart';
import 'package:database_data/sql_database.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('multiple frames keep the default side cover enabled', () async {
    final model = WindowModel(
      db: SqlDatabase(),
      width: 500,
      height: 200,
      profileThickness: 10,
    );
    model.zones = [
      WindowZone(id: 'left', boundary: const Rect.fromLTWH(10, 10, 100, 100)),
      WindowZone(id: 'right', boundary: const Rect.fromLTWH(250, 10, 100, 100)),
    ];
    model.hasSideCovers = true;

    model.notifyListeners();
    expect(model.getFrameRects(), hasLength(2));
    expect(model.hasSideCovers, isTrue);

    model.notifyListeners();
    expect(model.hasSideCovers, isTrue);
  });

  test(
    'multi-frame always replaces integrated cover frame with plain frame',
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
        name: 'Compatible series',
        type: 'opening',
      );
      final integratedFrame = AluminumSection(
        id: 20,
        seriesId: 1,
        name: 'Integrated outer cover',
        code: 'FRAME-INT-OK',
        type: 'frame',
        isFrame: true,
        thickness: 50,
        designIntegratedSideCover: true,
      );
      final plainFrame = AluminumSection(
        id: 21,
        seriesId: 1,
        name: 'Plain compatible frame',
        code: 'FRAME-PLAIN-OK',
        type: 'frame',
        isFrame: true,
        thickness: 50,
        designIntegratedSideCover: false,
      );
      final separateCover = AluminumSection(
        id: 22,
        seriesId: 1,
        name: 'Separate articulated cover',
        code: 'COVER-SEPARATE',
        type: 'side_cover',
      );
      series.sections = [integratedFrame, plainFrame, separateCover];
      model.activeSeries = series;
      model.frameOverride = integratedFrame.toMap();
      model.hasSideCovers = true;
      model.zones = [
        WindowZone(id: 'left', boundary: const Rect.fromLTWH(10, 10, 100, 100)),
        WindowZone(
          id: 'right',
          boundary: const Rect.fromLTWH(250, 10, 100, 100),
        ),
      ];

      model.notifyListeners();

      expect(model.getFrameRects(), hasLength(2));
      expect(model.hasSideCovers, isTrue);
      expect(model.isIntegratedFrame, isFalse);
      expect(model.frameOverride?['code'], 'FRAME-PLAIN-OK');
      expect(model.sideCoverOverride?['code'], 'COVER-SEPARATE');
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
        WindowZone(id: 'left', boundary: const Rect.fromLTWH(50, 50, 150, 100)),
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

  test('plain frame keeps enabled cover as a separate profile', () {
    final model = WindowModel(
      db: SqlDatabase(),
      width: 500,
      height: 200,
      profileThickness: 10,
    );
    final series = AluminumSeries(
      id: 1,
      profileId: 1,
      name: 'Series with separate cover',
      type: 'opening',
    );
    final plainFrame = AluminumSection(
      id: 31,
      seriesId: 1,
      name: 'Plain frame',
      code: 'FRAME-PLAIN',
      type: 'frame',
      isFrame: true,
      designIntegratedSideCover: false,
      allowsSideCover: false,
    );
    final separateCover = AluminumSection(
      id: 32,
      seriesId: 1,
      name: 'Separate side cover',
      code: 'COVER-SEPARATE',
      type: 'side_cover',
    );
    series.sections = [plainFrame, separateCover];
    model.activeSeries = series;
    model.hasSideCovers = true;
    model.selectedSideCover = separateCover;
    model.sideCoverOverride = separateCover.toMap();

    model.applyFrameOverride(
      plainFrame.toMap(),
      sliding: false,
      manualSelection: true,
    );

    expect(model.frameOverride?['code'], 'FRAME-PLAIN');
    expect(model.hasSideCovers, isTrue);
    expect(model.sideCoverOverride?['code'], 'COVER-SEPARATE');
  });

  test('custom shutter boxes keep independent mechanism and drive side', () {
    final model = WindowModel(
      db: SqlDatabase(),
      width: 1000,
      height: 1200,
      profileThickness: 10,
    );

    model.splitShutterCustomDivisions(
      const [400, 600],
      mechanisms: const ['حزام', 'محرك'],
      driveSides: const ['right', 'left'],
    );

    final rightBox = model.shutterSplits.singleWhere(
      (split) => split.label == 'صندوق 1',
    );
    final leftBox = model.shutterSplits.singleWhere(
      (split) => split.label == 'صندوق 2',
    );
    expect(rightBox.mechanism, 'حزام');
    expect(rightBox.driveSide, 'right');
    expect(leftBox.mechanism, 'محرك');
    expect(leftBox.driveSide, 'left');
  });
}
