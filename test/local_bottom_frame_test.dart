import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:database_data/Commande/Systeme/model.dart';
import 'package:database_data/Commande/Systeme/model_serialization.dart';
import 'montant_slim_test.dart' show FakeSqlDatabase;

void main() {
  test('single frame bottom can toggle without selecting the frame', () {
    final model = WindowModel(db: FakeSqlDatabase(), width: 900, height: 400)
      ..systemMode = 'opening'
      ..zones = [
        WindowZone(
          id: 'only-frame',
          boundary: const Rect.fromLTRB(40, 40, 860, 360),
          content: ZoneContent.singleSash,
        ),
      ]
      ..selection = const SelectionInfo();

    expect(model.getFrameRects(), hasLength(1));
    expect(model.selectedPhysicalFrameRect, isNull);
    expect(model.canEditSelectedBottomFrame, isTrue);

    model.toggleBottomFrame(false);

    expect(model.hasBottomFrame, isFalse);
  });

  test('multiple frames still require an explicit frame selection', () {
    final model = WindowModel(db: FakeSqlDatabase(), width: 900, height: 400)
      ..systemMode = 'opening'
      ..zones = [
        WindowZone(
          id: 'left',
          boundary: const Rect.fromLTWH(50, 50, 200, 300),
          content: ZoneContent.singleSash,
        ),
        WindowZone(
          id: 'right',
          boundary: const Rect.fromLTWH(400, 50, 200, 300),
          content: ZoneContent.singleSash,
        ),
      ]
      ..selection = const SelectionInfo();

    expect(model.getFrameRects(), hasLength(2));
    expect(model.canEditSelectedBottomFrame, isFalse);

    model.toggleBottomFrame(false);

    expect(model.hasBottomFrame, isTrue);
  });

  test('switching a sash back to fixed restores the lower frame state', () {
    final model = WindowModel(db: FakeSqlDatabase(), width: 900, height: 400)
      ..systemMode = 'opening'
      ..hasBottomFrame = false
      ..showBottomWall = false
      ..hasFramePlintheBottom = true
      ..zones = [
        WindowZone(
          id: 'fixed-again',
          boundary: const Rect.fromLTRB(40, 40, 860, 400),
          content: ZoneContent.singleSash,
          hasSashPlintheBottom: true,
        ),
      ]
      ..selection = SelectionInfo.zone('fixed-again');
    model.removedShutterSides.add('bottom');
    model.hiddenSideCoverSegments.add('bottom');

    model.setSelectedZoneContent(ZoneContent.fixedGlass);

    expect(model.hasBottomFrame, isTrue);
    expect(model.hasFramePlintheBottom, isFalse);
    expect(model.showBottomWall, isTrue);
    expect(model.removedShutterSides, isNot(contains('bottom')));
    expect(model.hiddenSideCoverSegments, isNot(contains('bottom')));
    expect(model.zones.single.boundary.bottom, closeTo(360, 0.01));
  });

  test('empty and sliding content also restore the lower frame', () {
    for (final content in [ZoneContent.empty, ZoneContent.slidingSash]) {
      final model = WindowModel(db: FakeSqlDatabase(), width: 900, height: 400)
        ..systemMode = 'opening'
        ..hasBottomFrame = false
        ..showBottomWall = false
        ..hasFramePlintheBottom = true
        ..zones = [
          WindowZone(
            id: 'restore-${content.name}',
            boundary: const Rect.fromLTRB(40, 40, 860, 400),
            content: ZoneContent.singleSash,
            hasSashPlintheBottom: true,
          ),
        ]
        ..selection = SelectionInfo.zone('restore-${content.name}');

      model.setSelectedZoneContent(content);

      expect(model.hasBottomFrame, isTrue, reason: content.name);
      expect(model.showBottomWall, isTrue, reason: content.name);
      expect(model.zones.single.boundary.bottom, closeTo(360, 0.01));
    }
  });

  test('bottom removal is local and persists; sliding remains closed', () {
    final model = WindowModel(db: FakeSqlDatabase(), width: 900, height: 400)
      ..systemMode = 'mixed'
      ..zones = [
        WindowZone(
          id: 'a',
          boundary: const Rect.fromLTWH(50, 50, 200, 300),
          content: ZoneContent.singleSash,
        ),
        WindowZone(
          id: 'b',
          boundary: const Rect.fromLTWH(400, 50, 200, 300),
          content: ZoneContent.slidingSash,
        ),
      ]
      ..selection = SelectionInfo.zone('a');
    expect(model.getFrameRects().length, 2);
    model.toggleBottomFrame(false);
    expect(model.selectedFrameHasBottom, isFalse);
    expect(model.hasBottomFrame, isTrue);
    model.selection = SelectionInfo.zone('b');
    expect(model.selectedFrameHasBottom, isTrue);
    expect(model.canEditSelectedBottomFrame, isFalse);
    model.toggleBottomFrame(false);
    expect(model.selectedFrameHasBottom, isTrue);
    final restored = WindowModel(db: FakeSqlDatabase());
    applyWindowModelFromMap(restored, model.toMap());
    restored.selection = SelectionInfo.zone('a');
    expect(restored.selectedFrameHasBottom, isFalse);
  });
}
