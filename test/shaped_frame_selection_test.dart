import 'package:database_data/Commande/Systeme/model.dart';
import 'package:database_data/sql_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeSqlDatabase extends SqlDatabase {}

WindowModel _model() {
  final model = WindowModel(db: FakeSqlDatabase());
  model.width = 1000;
  model.height = 1200;
  return model;
}

void main() {
  test('a rectangular window keeps the rectangular selection', () {
    final model = _model();
    final rect = Rect.fromLTWH(0, 0, model.width, model.height);
    expect(model.frameSelectionPath(rect).getBounds(), rect);
    expect(model.zoneSelectionPath(rect).getBounds(), rect);
  });

  test('an arched head is part of the frame and sash selection', () {
    final model = _model();
    model.archHeight = 200;
    final apex = model.headArc()!.apex;
    expect(apex.dy, lessThan(0), reason: 'the arch rises above y = 0');

    final frame = model.frameSelectionPath(
      Rect.fromLTWH(0, 0, model.width, model.height),
    );
    expect(frame.contains(Offset(apex.dx, apex.dy + 5)), isTrue);
    expect(frame.contains(Offset(apex.dx, apex.dy - 5)), isFalse);

    final t = model.profileThickness;
    final zoneRect = Rect.fromLTRB(t, t, model.width - t, model.height - t);
    model.zones = [
      WindowZone(
        id: 'sash',
        content: ZoneContent.doubleSash,
        boundary: zoneRect,
      ),
    ];
    final zoneTop = zoneRect.top;
    final sash = model.zoneSelectionPath(zoneRect);
    // Under the arch, above the rectangle of the zone.
    expect(sash.contains(Offset(apex.dx, zoneTop - 20)), isTrue);
  });

  test('a slanted bottom cuts the selection along the slant', () {
    final model = _model();
    model.bottomSlantRightY = 300;
    final frame = model.frameSelectionPath(
      Rect.fromLTWH(0, 0, model.width, model.height),
    );
    // Bottom-right corner of the bounding rectangle lies outside the window.
    expect(frame.contains(Offset(model.width - 5, model.height - 5)), isFalse);
    expect(frame.contains(const Offset(5, 1195)), isTrue);
  });
}
