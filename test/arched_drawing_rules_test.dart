import 'package:database_data/Commande/Systeme/model.dart';
import 'package:database_data/Commande/Systeme/model_serialization.dart';
import 'package:database_data/sql_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

class FakeSqlDatabase extends SqlDatabase {
  @override
  Future<Database?> get db async => null;
}

WindowModel _arched() {
  final model = WindowModel(db: FakeSqlDatabase());
  model.width = 1500;
  model.height = 1200;
  model.archHeight = 400;
  final t = model.profileThickness;
  model.zones = [
    WindowZone(
      id: 'glass',
      content: ZoneContent.fixedGlass,
      boundary: Rect.fromLTRB(t, t, 1500 - t, 1200 - t),
    ),
  ];
  return model;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('separate shutter over a slanted or arched head', () {
    test('takes the lower jamb as its height and its own box', () {
      final model = WindowModel(db: FakeSqlDatabase())
        ..width = 1000
        ..height = 1500
        ..topSlantLeftY = 300
        ..hasShutter = true;
      expect(model.isSeparateShutter, isTrue);
      // Jambs of 1500 and 1200: the shutter is 1200 high.
      expect(model.shutterFlatHeight, 1200);
      expect(model.separateShutterTop, 300);
      expect(model.separateShutterBoxHeight, 155);
      expect(model.shutterPartsBoxHeight, 155);
    });

    test('an arch never counts in its height', () {
      final model = _arched()..hasShutter = true;
      expect(model.shutterFlatHeight, 1200);
    });

    test('a plain window keeps the integrated shutter', () {
      final model = WindowModel(db: FakeSqlDatabase())
        ..width = 1000
        ..height = 1500
        ..hasShutter = true;
      expect(model.isSeparateShutter, isFalse);
      expect(model.shutterFlatHeight, 1500);
    });

    test('the inside belt pulley needs a belt and is saved', () {
      final model = _arched()..hasShutter = true;
      expect(model.canChooseSeparateShutterBelt, isTrue);
      model.setSeparateShutterBeltInside(true);
      expect(model.showsBeltPulley, isTrue);
      model.shutterMechanism = 'محرك';
      expect(model.showsBeltPulley, isFalse);

      final restored = WindowModel(db: FakeSqlDatabase());
      applyWindowModelFromMap(restored, model.toMap());
      expect(restored.separateShutterBeltInside, isTrue);
    });
  });

  group('drawing inside the arch', () {
    test('a stroke inside the arch divides, never draws a frame', () {
      final model = _arched();
      final apex = model.headArc()!.apex;
      model.startDrawing(Offset(apex.dx, apex.dy + 40));
      expect(model.drawingMode, 'split');
    });

    test('a horizontal division stays under the springing line', () {
      final model = _arched();
      final apex = model.headArc()!.apex;
      final start = Offset(apex.dx, apex.dy + 40);
      final moved = model.splitStartUnderArch(
        start,
        start + const Offset(400, 10),
      );
      expect(moved.dy, greaterThanOrEqualTo(model.profileThickness));
      expect(model.zones.single.boundary.contains(moved), isTrue);
    });

    test('a vertical division starts in the opening under the arch', () {
      final model = _arched();
      final apex = model.headArc()!.apex;
      final start = Offset(apex.dx, apex.dy + 40);
      final moved = model.splitStartUnderArch(
        start,
        start + const Offset(10, 600),
      );
      expect(moved.dx, start.dx);
      expect(model.zones.single.boundary.contains(moved), isTrue);
    });
  });

  test('a straight division keeps the slanted one in both parts', () {
    const source = Rect.fromLTWH(0, 0, 1000, 1000);
    // Diagonal from the top-left corner region to the bottom-right one.
    const divider = SlantedDivider(
      id: 's',
      start: SlantedDividerAnchor(ZoneEdge.left, 0.1),
      end: SlantedDividerAnchor(ZoneEdge.right, 0.9),
    );
    const top = Rect.fromLTRB(0, 0, 1000, 480);
    const bottom = Rect.fromLTRB(0, 520, 1000, 1000);
    final inTop = slantedDividersInPart([divider], source, top);
    final inBottom = slantedDividersInPart([divider], source, bottom);
    expect(inTop, hasLength(1));
    expect(inBottom, hasLength(1));
    expect(inTop.single.start.edge, ZoneEdge.left);
    expect(inTop.single.end.edge, ZoneEdge.bottom);
    expect(inBottom.single.start.edge, ZoneEdge.top);
    expect(inBottom.single.end.edge, ZoneEdge.right);
    // A part the line never crosses keeps nothing.
    expect(
      slantedDividersInPart(
        [divider],
        source,
        const Rect.fromLTRB(800, 0, 1000, 300),
      ),
      isEmpty,
    );
  });

  test('a moved angle badge is found and saved with the drawing', () {
    final model = WindowModel(db: FakeSqlDatabase());
    model.drawnAngleBadges['top_left'] = const Rect.fromLTWH(10, 10, 80, 40);
    expect(model.angleBadgeAt(const Offset(40, 30)), 'top_left');
    expect(model.angleBadgeAt(const Offset(400, 300)), isNull);
    model.dragAngleBadge('top_left', const Offset(30, -20));
    model.dragAngleBadge('top_left', const Offset(5, 5));
    expect(model.angleBadgeOffsets['top_left'], const Offset(35, -15));

    final restored = WindowModel(db: FakeSqlDatabase());
    applyWindowModelFromMap(restored, model.toMap());
    expect(restored.angleBadgeOffsets['top_left'], const Offset(35, -15));
  });
}
