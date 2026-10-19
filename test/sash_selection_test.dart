import 'dart:ui';

import 'package:database_data/Commande/Systeme/model.dart';
import 'package:flutter_test/flutter_test.dart';

import 'montant_slim_test.dart' show FakeSqlDatabase;

WindowModel _twoSashes() =>
    WindowModel(db: FakeSqlDatabase(), width: 1600, height: 1200)
      ..systemMode = 'opening'
      ..zones = [
        WindowZone(
          id: 'left',
          boundary: const Rect.fromLTRB(60, 60, 790, 1140),
          content: ZoneContent.singleSash,
          openDirection: OpenDirection.left,
        ),
        WindowZone(
          id: 'right',
          boundary: const Rect.fromLTRB(810, 60, 1540, 1140),
          content: ZoneContent.singleSash,
          openDirection: OpenDirection.right,
        ),
      ];

const _thick = {'id': 105, 'code': 'S105', 'visible_width': 70.0};

void main() {
  test('a tap changes the profile and handle of one sash only', () {
    final model = _twoSashes();
    model.selectAt(const Offset(400, 600));
    expect(model.selectedZone?.id, 'left');
    expect(model.allSashesSelected, isFalse);

    model.applySashOverride(
      _thick,
      sliding: false,
      targetZone: model.selectedZone,
    );
    model.setSelectedZoneHandle(useOctoHandle: true);

    final left = model.zones.first;
    final right = model.zones.last;
    expect(left.sashOverride?['code'], 'S105');
    expect(right.sashOverride, isNull);
    expect(left.useOctoHandle, isTrue);
    expect(right.useOctoHandle, isFalse);
  });

  test('a long press selects every sash', () {
    final model = _twoSashes();
    model.selectAt(const Offset(400, 600), isLongPress: true);
    expect(model.allSashesSelected, isTrue);
    expect(model.selectedSashZones.map((z) => z.id), ['left', 'right']);

    model.applySashOverride(
      _thick,
      sliding: false,
      targetZone: model.selectedZone,
    );
    model.setSelectedZoneHandle(useOctoHandle: true);

    expect(model.zones.every((z) => z.sashOverride?['code'] == 'S105'), isTrue);
    expect(model.zones.every((z) => z.useOctoHandle), isTrue);
    expect(model.sashOverride?['code'], 'S105');

    // A tap goes back to one sash.
    model.selectAt(const Offset(1200, 600));
    expect(model.allSashesSelected, isFalse);
    expect(model.selectedSashZones.map((z) => z.id), ['right']);
  });

  test('the consumption table still changes every sash', () {
    final model = _twoSashes()..selectAt(const Offset(400, 600));
    model.applySashOverride(_thick, sliding: false, manualSelection: true);
    expect(model.zones.every((z) => z.sashOverride?['code'] == 'S105'), isTrue);
  });
}
