import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:database_data/Commande/Systeme/model.dart';
import 'package:database_data/Commande/Systeme/model_serialization.dart';
import 'package:database_data/Commande/Systeme/calculate_component.dart';
import 'package:database_data/sql_database.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeSqlDatabase extends SqlDatabase {
  @override
  Future<List<Map<String, dynamic>>> readGlass() async => [];
}

/// The reinforcement mode follows the catalogue series (its
/// `reinforcement_type` or its sections); it is not a per-drawing setting.
AluminumSeries _seriesWithReinforcement(String type) => AluminumSeries(
  id: 42,
  profileId: 1,
  name: 'BS90 Sliding',
  type: 'sliding',
  reinforcementType: type,
);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('Reinforcement Modes and Sliding Series Tests', () {
    test('the reinforcement mode follows the series across save and load', () {
      final fakeDb = FakeSqlDatabase();
      final model = WindowModel(db: fakeDb);
      model.activeSlidingSeries = _seriesWithReinforcement('chicane_combination');
      model.loadedSlidingSeriesId = 42;
      model.loadedSlidingSeriesName = 'BS90 Sliding';

      final map = model.toMap();
      expect(map['reinforcementMode'], equals('chicaneCombination'));
      expect(map['slidingSeriesId'], equals(42));
      expect(map['slidingSeriesName'], equals('BS90 Sliding'));

      final target = WindowModel(db: fakeDb);
      applyWindowModelFromMap(target, map);
      target.activeSlidingSeries = _seriesWithReinforcement('chicane_combination');
      expect(target.reinforcementMode, equals(ReinforcementMode.chicaneCombination));
      expect(target.loadedSlidingSeriesId, equals(42));
      expect(target.loadedSlidingSeriesName, equals('BS90 Sliding'));
    });

    test('an independent screwed series is saved as independentScrewed', () {
      final fakeDb = FakeSqlDatabase();
      final model = WindowModel(db: fakeDb);
      model.activeSlidingSeries = _seriesWithReinforcement('independent_screwed');

      expect(model.reinforcementMode, equals(ReinforcementMode.independentScrewed));
      expect(model.toMap()['reinforcementMode'], equals('independentScrewed'));
    });

    test('Adjacent coupled frames share one seam with a tube carré angle profile', () {
      final fakeDb = FakeSqlDatabase();
      final model = WindowModel(db: fakeDb, width: 2200, height: 1200);
      model.coupleFrames = true;

      // Two zones positioned as adjacent frames (separated by 2 * profileThickness = 90mm)
      model.zones = [
        WindowZone(
          id: 'z1',
          content: ZoneContent.fixedGlass,
          boundary: const Rect.fromLTWH(0, 0, 1000, 1200),
        ),
        WindowZone(
          id: 'z2',
          content: ZoneContent.fixedGlass,
          boundary: const Rect.fromLTWH(1090, 0, 1000, 1200),
        ),
      ];

      model.profileAngleJunctions.add(0);
      expect(model.isProfileAngleJunctionActive(0), isTrue);

      final rects = model.getFrameRects();
      expect(rects.length, equals(2));

      final r1 = rects[0];
      final r2 = rects[1];

      // The profile-angle tube sits behind the 90° corner, so coupled frames
      // share one seam instead of leaving a tube-wide gap between them.
      expect(r2.left - r1.right, closeTo(0, 0.001));
    });

    test('BOM in independentScrewed generates independent profile, screws and caps', () {
      final fakeDb = FakeSqlDatabase();
      final model = WindowModel(db: fakeDb, width: 1500, height: 1200);
      model.systemMode = 'sliding';
      model.activeSlidingSeries = _seriesWithReinforcement('independent_screwed');

      final zone = WindowZone(
        id: 'z1',
        content: ZoneContent.slidingSash,
        boundary: const Rect.fromLTWH(0, 0, 1500, 1200),
      );
      // Reinforce central meeting junction
      zone.slidingMontantReinforced['central_0'] = true;
      zone.slidingMontantReinforced['central_1'] = true;
      model.zones = [zone];

      final bom = ComponentCalculator.generateBom(
        model,
        {},
        kitBundleData: {},
        kitPerLeafMap: {},
      );

      // Verify independent reinforcement profile
      final renfortProfiles = bom.where(
        (item) => item.category == 'profile' && item.originalName.contains('Renfort'),
      );
      expect(renfortProfiles.isNotEmpty, isTrue);

      // Verify reinforcement screws (Vis Renfort 3.9x38)
      final renfortScrews = bom.where(
        (item) => item.category == 'accessory' && item.originalName.contains('Vis') && item.originalName.contains('Renfort'),
      );
      expect(renfortScrews.isNotEmpty, isTrue);

      // Verify reinforcement caps (Caches Renfort)
      final renfortCaps = bom.where(
        (item) => item.category == 'accessory' && (item.originalName.contains('Cache') || item.originalName.contains('Bouchon')),
      );
      expect(renfortCaps.isNotEmpty, isTrue);
    });

    test('BOM in chicaneCombination generates 1 normal and 1 reinforced chicane', () {
      final fakeDb = FakeSqlDatabase();
      final model = WindowModel(db: fakeDb, width: 1500, height: 1200);
      model.systemMode = 'sliding';
      model.activeSlidingSeries = _seriesWithReinforcement('chicane_combination');

      final zone = WindowZone(
        id: 'z1',
        content: ZoneContent.slidingSash,
        boundary: const Rect.fromLTWH(0, 0, 1500, 1200),
      );
      zone.slidingMontantReinforced['central_0'] = true;
      zone.slidingMontantReinforced['central_1'] = true;
      model.zones = [zone];

      final bom = ComponentCalculator.generateBom(
        model,
        {},
        kitBundleData: {},
        kitPerLeafMap: {},
      );

      final normalChicane = bom.where(
        (item) => item.originalName.contains('Chicane') && !item.originalName.contains('Renforcée'),
      );
      final reinforcedChicane = bom.where(
        (item) => item.originalName.contains('Renforcée'),
      );

      expect(normalChicane.isNotEmpty, isTrue);
      expect(reinforcedChicane.isNotEmpty, isTrue);

      // Mode 2 produces 1 piece normal and 1 piece reinforced per junction
      expect(normalChicane.first.pieces?.length, equals(1));
      expect(reinforcedChicane.first.pieces?.length, equals(1));
    });

    test('BOM in fullSubstitution generates 2 reinforced chicane pieces and 0 normal chicane pieces', () {
      final fakeDb = FakeSqlDatabase();
      final model = WindowModel(db: fakeDb, width: 1500, height: 1200);
      model.systemMode = 'sliding';
      model.reinforcementMode = ReinforcementMode.fullSubstitution;

      final zone = WindowZone(
        id: 'z1',
        content: ZoneContent.slidingSash,
        boundary: const Rect.fromLTWH(0, 0, 1500, 1200),
      );
      zone.slidingMontantReinforced['central_0'] = true;
      zone.slidingMontantReinforced['central_1'] = true;
      model.zones = [zone];

      final bom = ComponentCalculator.generateBom(
        model,
        {},
        kitBundleData: {},
        kitPerLeafMap: {},
      );

      final normalChicane = bom.where(
        (item) => item.originalName.contains('Chicane') && !item.originalName.contains('Renforcée'),
      );
      final reinforcedChicane = bom.where(
        (item) => item.originalName.contains('Renforcée'),
      );

      expect(normalChicane.isEmpty, isTrue);
      expect(reinforcedChicane.isNotEmpty, isTrue);
      expect(reinforcedChicane.first.pieces?.length, equals(2));
    });
  });
}
