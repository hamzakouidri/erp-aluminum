import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:database_data/Commande/Systeme/model.dart';
import 'package:database_data/Commande/Systeme/calculate_component.dart';
import 'package:database_data/sql_database.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeSqlDatabase extends SqlDatabase {
  @override
  Future<List<Map<String, dynamic>>> readGlass() async => [];
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test(
    'Sliding window BOM generates correct sliding kits under other category and correct assembly screws',
    () {
      final fakeDb = FakeSqlDatabase();
      final model = WindowModel(db: fakeDb, width: 1500, height: 1200);
      model.systemMode = 'sliding';

      // Simulate active sliding series containing "67000"
      model.activeSlidingSeries = AluminumSeries(
        id: 1,
        profileId: 1,
        name: 'E67000 Sliding Series',
        type: 'sliding',
      );

      // Simulate zones: 1 sliding zone
      model.zones = [
        WindowZone(
          id: 'z1',
          content: ZoneContent.slidingSash,
          boundary: const Rect.fromLTWH(0, 0, 1500, 1200),
        ),
      ];

      // Generate BOM
      final bom = ComponentCalculator.generateBom(
        model,
        {},
        kitBundleData: {},
        kitPerLeafMap: {},
      );

      // 1. Verify Kit 67000 is present and categorized as 'other'
      final kitItem = bom.firstWhere(
        (item) => item.originalName == 'كيت 67000 (Kit 67000)',
        orElse: () => throw Exception('Kit 67000 not found'),
      );
      expect(kitItem.category, equals('other'));
      expect(kitItem.quantity, equals(1.0));

      // 2. Verify 'براغي التجميع' is present instead of 'براغي الإكسسوارات'
      // slidingTotalRoulettes = sashes * 2. With 1 sliding zone, usually sashes = 2.
      // So assembly screws quantity = 2 sashes * 4 = 8.
      final screwsItem = bom.firstWhere(
        (item) => item.originalName == 'براغي التجميع',
        orElse: () => throw Exception('Assembly screws not found'),
      );
      expect(screwsItem.category, equals('accessory'));
      expect(screwsItem.quantity, equals(8.0));

      // Verify there are no 'براغي الإكسسوارات'
      final hasGenericScrews = bom.any(
        (item) => item.originalName == 'براغي الإكسسوارات',
      );
      expect(hasGenericScrews, isFalse);
    },
  );

  test(
    'sliding-only mixed drawing uses sliding frame row instead of opening frame row',
    () {
      final fakeDb = FakeSqlDatabase();
      final model = WindowModel(db: fakeDb, width: 1600, height: 1400);
      model.systemMode = 'mixed';
      model.activeSeries = AluminumSeries(
        id: 10,
        profileId: 1,
        name: 'TPR Frappe',
        type: 'Frappe',
        sections: [
          AluminumSection(
            id: 101,
            seriesId: 10,
            code: 'OF',
            name: 'Opening Frame',
            type: 'frame',
            thickness: 50,
            visibleWidth: 50,
            isFrame: true,
          ),
        ],
      );
      model.activeSlidingSeries = AluminumSeries(
        id: 20,
        profileId: 1,
        name: 'TPR Coulissant',
        type: 'Coulissant',
        sections: [
          AluminumSection(
            id: 201,
            seriesId: 20,
            code: 'SF',
            name: 'Sliding Frame',
            type: 'frame',
            thickness: 60,
            visibleWidth: 60,
            isFrame: true,
          ),
        ],
      );
      model.slidingFrameOverride = model.activeSlidingSeries!.sections.first
          .toMap();
      model.zones = [
        WindowZone(
          id: 'z1',
          content: ZoneContent.slidingSash,
          boundary: const Rect.fromLTWH(60, 60, 1480, 1280),
        ),
      ];

      final bom = ComponentCalculator.generateBom(model, {});

      expect(model.isSlidingOnlyDrawing, isTrue);
      expect(bom.any((item) => item.originalName == 'الإطار (Frame)'), isFalse);
      final slidingFrame = bom.firstWhere(
        (item) => item.originalName == 'إطار منزلق (Cadre Coulissant)',
        orElse: () => throw Exception('Sliding frame row not found'),
      );
      expect(slidingFrame.profileCode, equals('SF'));
    },
  );

  test('sliding sash width adjustment accepts subtraction and addition', () {
    final model = WindowModel(db: FakeSqlDatabase());
    model.slidingSeriesTableConfig = {
      'sash_w_deduction_2': 45.0,
      'sash_w_deduction_3': -30.0,
      'sash_w_deduction_4': '12.5',
    };

    expect(model.slidingSashWidthDeduction(2), equals(45.0));
    expect(model.slidingSashWidthDeduction(3), equals(-30.0));
    expect(model.slidingSashWidthDeduction(4), equals(12.5));
  });

  test(
    'double glass intercall reserves gasket thickness per selected side',
    () {
      final model = WindowModel(db: FakeSqlDatabase());
      model.componentOverrides['باكيت الزجاج (Parclose)'] = {
        'max_glass_thickness': 24.0,
      };
      model.availableIntercalls = [
        {'thickness': 10, 'name': '10 مم'},
        {'thickness': 12, 'name': '12 مم'},
      ];

      expect(
        model.suggestedIntercallThicknessForDoubleGlass(
          thicknessOuter: 5.0,
          thicknessInner: 5.0,
          jointTwoSides: false,
        ),
        equals(12),
      );
      expect(
        model.suggestedIntercallThicknessForDoubleGlass(
          thicknessOuter: 5.0,
          thicknessInner: 5.0,
          jointTwoSides: true,
        ),
        equals(10),
      );
      expect(
        const GlassSpecification(
          structure: GlassStructure.double,
        ).totalThickness(const []),
        equals(22.0),
      );
    },
  );

  test('standalone side cover can draw from saved override', () {
    final model = WindowModel(db: FakeSqlDatabase());
    model.systemMode = 'sliding';
    model.activeSlidingSeries = AluminumSeries(
      id: 67,
      profileId: 1,
      name: 'TPR 67000',
      type: 'sliding',
    );
    model.hasSideCovers = true;
    model.sideCoverOverride = {
      'id': 671,
      'name': 'Couvre-joint TPR',
      'type': 'side_cover',
      'couvre_joint_width': 45.0,
      'couvre_joint_thickness': 2.0,
    };

    expect(model.canUseStandaloneSideCover, isTrue);
    expect(model.hasDrawableStandaloneSideCover, isTrue);
    expect(model.sideCoverWidth, equals(45.0));
  });
}
