import 'dart:ui' as ui;

import 'package:database_data/Commande/Systeme/model.dart';
import 'package:database_data/Commande/window_3d_preview.dart';
import 'package:database_data/sql_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void paintAll(WindowModel model) {
  for (final yaw in [-0.55, 0.0, 0.42, 1.6, 3.1]) {
    for (final open in [0.0, 0.5, 1.0]) {
      for (final wall in [true, false]) {
        final canvas = Canvas(ui.PictureRecorder());
        Window3DPainter(
          model: model,
          yaw: yaw,
          pitch: 0.3,
          zoom: 1,
          openingProgress: open,
          dark: false,
          showWall: wall,
        ).paint(canvas, const Size(800, 600));
      }
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('corner window with a profile angle and a shutter paints', () {
    final model = WindowModel(
      db: SqlDatabase(),
      width: 2000,
      height: 1200,
      profileThickness: 40,
    );
    model.zones = [
      WindowZone(
        id: 'a',
        content: ZoneContent.singleSash,
        openDirection: OpenDirection.left,
        boundary: const Rect.fromLTRB(40, 40, 960, 1160),
      ),
      WindowZone(
        id: 'b',
        content: ZoneContent.fixedGlass,
        boundary: const Rect.fromLTRB(1040, 40, 1960, 1160),
      ),
    ];
    model.coupleFrames = true;
    model.profileAngleJunctions = {0};
    model.hasShutter = true;
    expect(model.activeProfileAngleJunctions, {0});
    paintAll(model);
  });

  test('casements with every hinge side, lock and a mosquito net paint', () {
    for (final direction in OpenDirection.values) {
      for (final lock in LockType.values) {
        final model = WindowModel(
          db: SqlDatabase(),
          width: 1500,
          height: 1300,
          profileThickness: 45,
        )..hasMoustiquaireAddon = true;
        model.zones = [
          WindowZone(
            id: 'single',
            content: ZoneContent.singleSash,
            openDirection: direction,
            lockType: lock,
            boundary: const Rect.fromLTRB(45, 45, 700, 1255),
          ),
          WindowZone(
            id: 'double',
            content: ZoneContent.doubleSash,
            openDirection: OpenDirection.left,
            doubleSashHasTwoHandles: true,
            boundary: const Rect.fromLTRB(745, 45, 1455, 1255),
          ),
        ];
        paintAll(model);
      }
    }
  });

  test('sliding window with a tunnel box paints', () {
    final model =
        WindowModel(
            db: SqlDatabase(),
            width: 2400,
            height: 1500,
            profileThickness: 50,
            systemMode: 'sliding',
          )
          ..hasShutter = true
          ..isCaissonTunnel = true;
    model.zones = [
      WindowZone(
        id: 's',
        content: ZoneContent.slidingSash,
        slidingSashesCount: 3,
        slidingTrackCount: 3,
        boundary: const Rect.fromLTRB(50, 50, 2350, 1450),
      ),
    ];
    paintAll(model);
  });
}
