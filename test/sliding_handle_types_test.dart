import 'package:database_data/Commande/Systeme/calculate_component.dart';
import 'package:database_data/Commande/Systeme/model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'sliding_bom_test.dart' show FakeSqlDatabase;

WindowModel _fourLeaves() {
  final model = WindowModel(
    db: FakeSqlDatabase(),
    width: 2400,
    height: 1200,
    systemMode: 'sliding',
  );
  model.activeSlidingSeries = AluminumSeries(
    id: 1,
    profileId: 1,
    name: 'TPR 40000',
    type: 'sliding',
  );
  model.componentOverrides['أونتروماتيك (Entrematique)'] = {
    'id': 501,
    'name': 'Entrematique',
  };
  model.zones = [
    WindowZone(
      id: 'four',
      content: ZoneContent.slidingSash,
      boundary: const Rect.fromLTWH(0, 0, 2400, 1200),
      slidingSashesCount: 4,
      slidingTrackCount: 2,
      slidingFaceToFace: true,
      slidingSecondCentralHandle: true,
    ),
  ];
  return model;
}

int _qty(List<dynamic> bom, String name) => bom
    .where((item) => item.originalName == name)
    .fold<int>(0, (sum, item) => sum + (item.quantity as num).toInt());

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('a four-leaf window has left, right and central handle places', () {
    final model = _fourLeaves();
    final zone = model.zones.single;
    expect(model.slidingHandleSlots(zone), ['left', 'right', 'center']);
    expect(model.slidingHandleSlotForLeaf(zone, 0), 'left');
    expect(model.slidingHandleSlotForLeaf(zone, 1), 'center');
    expect(model.slidingHandleSlotForLeaf(zone, 2), 'center');
    expect(model.slidingHandleSlotForLeaf(zone, 3), 'right');
  });

  test('outer entrematiques with a lever handle at the meeting', () {
    final model = _fourLeaves();
    final zone = model.zones.single;
    // The tapped middle leaf selects the central handles only.
    model.selection = const SelectionInfo(
      type: SelectionType.zone,
      zoneId: 'four',
    );
    model.activeSubZone = 'main_cell_0_1';
    expect(model.selectedSlidingHandleSlots[zone], ['center']);
    model.setSelectedSlidingHandleType(SlidingHandleType.classic);

    expect(model.slidingHandleTypeFor(zone, 'left'), 'entrematique');
    expect(model.slidingHandleTypeFor(zone, 'center'), 'classic');

    final bom = ComponentCalculator.generateBom(model, const {});
    expect(_qty(bom, 'أونتروماتيك (Entrematique)'), 2);
    // Two central handles: the functional one with its espagnolette and
    // the decorative mirror.
    expect(_qty(bom, 'مقبض منزلق (Poignée Coulissante)'), 2);
    expect(_qty(bom, 'اسبانيولات المنزلق (Espagnolette)'), 1);
  });

  test('a PVC sliding window takes no entrematique', () {
    final model = _fourLeaves()
      ..activeSlidingSeries = AluminumSeries(
        id: 2,
        profileId: 2,
        name: 'PVC 70 sliding',
        type: 'sliding',
      );
    expect(model.isSlidingPVC, isTrue);
    final zone = model.zones.single;
    expect(model.availableSlidingHandleTypes, ['pvc_window', 'encastree']);
    model.selection = const SelectionInfo(
      type: SelectionType.zone,
      zoneId: 'four',
    );
    model.activeSubZone = 'main_cell_0_0';
    model.setSelectedSlidingHandleType(SlidingHandleType.entrematique);
    expect(zone.slidingHandleTypes, isEmpty);
    model.setSelectedSlidingHandleType(SlidingHandleType.encastree);
    expect(model.slidingHandleTypeFor(zone, 'left'), 'encastree');
    expect(model.slidingHandleTypeFor(zone, 'right'), 'pvc_window');
  });
}
