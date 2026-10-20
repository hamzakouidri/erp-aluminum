import 'package:database_data/Commande/Systeme/model.dart';
import 'package:database_data/sql_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

class FakeSqlDatabase extends SqlDatabase {
  // No catalogue: the shutter defaults are not looked up in these tests.
  @override
  Future<Database?> get db async => null;
}

WindowModel _window() {
  final model = WindowModel(db: FakeSqlDatabase());
  model.width = 1200;
  model.height = 1400;
  model.zones = [
    WindowZone(
      id: 'sash',
      content: ZoneContent.doubleSash,
      boundary: const Rect.fromLTWH(60, 60, 1080, 1280),
    ),
  ];
  return model;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('shutter button pressed twice', () {
    test('a window converted into a shutter comes back as it was', () {
      final model = _window();
      model.convertCurrentDrawingToShutter();
      expect(model.isShutterOnly, isTrue);
      expect(model.isShutterDrawing, isTrue);
      expect(model.zones, isEmpty);

      model.convertShutterBackToWindow();
      expect(model.isShutterOnly, isFalse);
      expect(model.hasShutter, isFalse);
      expect(model.isShutterDrawing, isFalse);
      expect(model.zones.single.id, 'sash');
      expect(model.zones.single.content, ZoneContent.doubleSash);
      expect(model.width, 1200);
      expect(model.height, 1400);
    });

    test('a shutter drawn on its own becomes a frame of the same size', () {
      final model = WindowModel(db: FakeSqlDatabase());
      model.prepareShutterOnlyDrawing();
      expect(model.isShutterDrawing, isTrue);
      model
        ..width = 900
        ..height = 1100
        ..isShutterOnly = true
        ..hasShutter = true
        ..drawNextShapeAsShutterOnly = false;

      model.convertShutterBackToWindow();
      expect(model.isShutterOnly, isFalse);
      expect(model.hasShutter, isFalse);
      expect(model.zones, hasLength(1));
      expect(model.width, 900);
      expect(model.height, 1100);
    });

    test('a shutter not drawn yet goes back to drawing a window', () {
      final model = WindowModel(db: FakeSqlDatabase());
      model.prepareShutterOnlyDrawing();
      model.convertShutterBackToWindow();
      expect(model.isShutterDrawing, isFalse);
      expect(model.drawingMode, 'new_frame');
      expect(model.zones, isEmpty);
    });
  });

  group('tapping the handle-height number', () {
    test('finds the number and sets the height from the sash bottom', () {
      final model = _window();
      model.drawnHandleHeightLabels['sash'] = (
        label: const Rect.fromLTWH(100, 900, 120, 80),
        sashTop: 60,
        sashBottom: 1340,
      );
      expect(model.handleHeightLabelAt(const Offset(150, 940)), 'sash');
      expect(model.handleHeightLabelAt(const Offset(600, 300)), isNull);
      expect(model.handleHeightFromBottom('sash'), closeTo(640, 0.01));

      expect(model.setHandleHeightFromBottom('sash', 1000), isTrue);
      expect(model.zones.single.handlePositionRatio, closeTo(1000 / 1280, 1e-9));
      expect(model.handleHeightFromBottom('sash'), closeTo(1000, 0.01));

      // Outside the sash: refused.
      expect(model.setHandleHeightFromBottom('sash', 1500), isFalse);
    });
  });
}
