import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:database_data/Commande/Systeme/model.dart';
import 'package:database_data/Commande/Systeme/model_serialization.dart';
import 'montant_slim_test.dart' show FakeSqlDatabase;

void main() {
  test('bottom removal is local and persists; sliding remains closed', () {
    final model = WindowModel(db: FakeSqlDatabase(), width: 900, height: 400)
      ..systemMode = 'mixed'
      ..zones = [
        WindowZone(id: 'a', boundary: const Rect.fromLTWH(50, 50, 200, 300),
          content: ZoneContent.singleSash),
        WindowZone(id: 'b', boundary: const Rect.fromLTWH(400, 50, 200, 300),
          content: ZoneContent.slidingSash),
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
