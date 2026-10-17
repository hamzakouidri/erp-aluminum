import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:database_data/Commande/Systeme/model.dart';
import 'package:database_data/Commande/Systeme/model_serialization.dart';
import 'package:database_data/Commande/Systeme/calculate_component.dart';
import 'package:database_data/Commande/pdf_fiche_coupe_api.dart';
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

  group('Montant Slim (المونتوسليم) Tests', () {
    test('WindowZone serialization preserves slidingMontantSlim', () {
      final zone = WindowZone(
        id: 'z1',
        content: ZoneContent.slidingSash,
        boundary: const Rect.fromLTWH(0, 0, 1500, 1200),
        slidingMontantSlim: {'central_0': true, 'central_1': false},
      );

      final map = zone.toMap();
      expect(
        map['slidingMontantSlim'],
        equals({'central_0': true, 'central_1': false}),
      );

      final restored = windowZoneFromMap(map);
      expect(restored.slidingMontantSlim['central_0'], isTrue);
      expect(restored.slidingMontantSlim['central_1'], isFalse);
    });

    test(
      '2-Sash sliding window with Montant Slim: correct BOM, cleats, angles and chicane cancellation',
      () {
        final fakeDb = FakeSqlDatabase();
        final model = WindowModel(db: fakeDb, width: 1400, height: 1200);
        model.systemMode = 'sliding';
        model.hasBottomFrame = true;

        final slimProfile = AluminumSection(
          id: 999,
          seriesId: 1,
          code: 'SLIM-01',
          name: 'قائم وسطي سليم',
          type: 'montant_central_slim',
          visibleWidth: 18.0,
        );

        model.activeSlidingSeries = AluminumSeries(
          id: 1,
          profileId: 1,
          name: 'Coulissant Slim 67000',
          type: 'sliding',
          sections: [slimProfile],
        );

        // 2-sash sliding zone with central_0 enabled as slim
        model.zones = [
          WindowZone(
            id: 'z1',
            content: ZoneContent.slidingSash,
            slidingSashesCount: 2,
            boundary: const Rect.fromLTWH(0, 0, 1400, 1200),
            slidingMontantSlim: {'central_0': true},
          ),
        ];

        final bom = ComponentCalculator.generateBom(
          model,
          {},
          kitBundleData: {},
          kitPerLeafMap: {},
        );

        // 1. Montant Slim profile must be present in BOM
        final slimItem = bom.firstWhere(
          (item) =>
              item.originalName.contains('سليم') ||
              item.originalName.contains('Slim'),
          orElse: () =>
              throw Exception('Montant Slim profile not found in BOM'),
        );
        expect(slimItem.pieces, isNotNull);
        expect(slimItem.pieces!.length, equals(1)); // 1 slim stile
        expect(slimItem.roleKey, equals('montant_central_slim'));

        // 2. Connector cleat (قطاع وصلة 10 سم) must be present with 2 pieces (0.10 m each)
        final cleatItem = bom.firstWhere(
          (item) =>
              item.originalName.contains('وصلة') ||
              item.originalName.contains('Taquet'),
          orElse: () => throw Exception('Taquet Slim cleat not found in BOM'),
        );
        expect(cleatItem.pieces, isNotNull);
        expect(cleatItem.pieces!.length, equals(2));
        for (final p in cleatItem.pieces!) {
          expect(p, closeTo(0.10, 0.001));
        }
        expect(cleatItem.roleKey, equals('complement_haut_base'));

        // 3. Each sash keeps its two widths (2 sashes => 4). Slim replaces
        // only one vertical montant and must never move those widths to the
        // complement row.
        final sashItem = bom.firstWhere(
          (item) => item.originalName.contains('Sliding Sash'),
        );
        expect(
          sashItem.pieces!.where((piece) => piece < 1.0).length,
          equals(4),
        );
        expect(
          bom.where((item) => item.roleKey == 'sash_traverse'),
          isEmpty,
        );

        // 4. Chicane must be cancelled (eliminated) for this junction
        final chicaneExists = bom.any(
          (item) =>
              item.originalName.contains('Chicane') ||
              item.originalName.contains('الشيكان'),
        );
        expect(chicaneExists, isFalse);
      },
    );

    test(
      '3-Sash sliding window with middle sash both sides slim keeps widths on sash',
      () {
        final fakeDb = FakeSqlDatabase();
        final model = WindowModel(db: fakeDb, width: 2100, height: 1200);
        model.systemMode = 'sliding';
        model.hasBottomFrame = true;

        final slimProfile = AluminumSection(
          id: 999,
          seriesId: 1,
          code: 'SLIM-01',
          name: 'قائم وسطي سليم',
          type: 'montant_central_slim',
          visibleWidth: 18.0,
        );

        model.activeSlidingSeries = AluminumSeries(
          id: 1,
          profileId: 1,
          name: 'Coulissant Slim 67000',
          type: 'sliding',
          sections: [slimProfile],
        );

        // In 3-sash: sash 0 (left: lateral, right: central_0), sash 1 (left: central_1, right: central_2), sash 2 (left: central_3, right: lateral)
        // If central_1 and central_2 are slim, middle sash (sash 1) has both sides slim!
        model.zones = [
          WindowZone(
            id: 'z1',
            content: ZoneContent.slidingSash,
            slidingSashesCount: 3,
            boundary: const Rect.fromLTWH(0, 0, 2100, 1200),
            slidingMontantSlim: {'central_1': true, 'central_2': true},
          ),
        ];

        final bom = ComponentCalculator.generateBom(
          model,
          {},
          kitBundleData: {},
          kitPerLeafMap: {},
        );

        // 1. No separate traverse profile: all six widths remain on the
        // normal sash row, including the middle sash's 90°/90° pieces.
        final sashItem = bom.firstWhere(
          (item) => item.originalName.contains('Sliding Sash'),
        );
        expect(sashItem.pieces!.where((piece) => piece < 1.0).length, equals(6));
        expect(bom.where((item) => item.roleKey == 'sash_traverse'), isEmpty);

        // 2. Montant Slim must have 2 pieces (one for central_1, one for central_2)
        final slimItem = bom.firstWhere(
          (item) =>
              item.originalName.contains('سليم') ||
              item.originalName.contains('Slim'),
        );
        expect(slimItem.pieces!.length, equals(2));

        // 3. Cleats: 2 stiles * 2 pieces = 4 pieces of 0.10 m
        final cleatItem = bom.firstWhere(
          (item) =>
              item.originalName.contains('وصلة') ||
              item.originalName.contains('Taquet'),
        );
        expect(cleatItem.pieces!.length, equals(4));
      },
    );

    test('cancelling the final Slim flag clears the selected profile', () {
      final model = WindowModel(db: FakeSqlDatabase());
      final zone = WindowZone(
        id: 'z1',
        content: ZoneContent.slidingSash,
        boundary: const Rect.fromLTWH(0, 0, 1000, 1000),
        slidingMontantSlim: {'central_0': true},
      );
      model.zones = [zone];
      model.applySlidingMontantSlimOverride({'id': 999, 'name': 'Slim'});
      expect(model.selectedSlimMontantProfile, isNotNull);

      zone.slidingMontantSlim['central_0'] = false;
      model.clearSlidingMontantSlimOverrideIfInactive();

      expect(model.selectedSlimMontantProfile, isNull);
      expect(
        model.componentOverrides['قائم وسطي سليم (Montant Slim)'],
        isNull,
      );
    });

    test(
      'pdf_fiche_coupe_api anglesFor detects 45/90 and slim 90/90 correctly',
      () {
        final bom4590 = BomItem(
          category: 'profile',
          originalName: 'عارضة الضلفة المنزلقة 45°/90° (Traverse Sash 45°/90°)',
          name: 'Traverse Sash 45°/90°',
          quantity: 2,
          unit: 'قطاع',
          unitPrice: 0,
          isMissing: false,
          isInteractive: false,
          isActive: true,
        );

        final bom9090 = BomItem(
          category: 'profile',
          originalName: 'عارضة الضلفة المنزلقة 90°/90° (Traverse Sash 90°/90°)',
          name: 'Traverse Sash 90°/90°',
          quantity: 2,
          unit: 'قطاع',
          unitPrice: 0,
          isMissing: false,
          isInteractive: false,
          isActive: true,
        );

        final bomSlim = BomItem(
          category: 'profile',
          originalName: 'قائم وسطي سليم (Montant Slim)',
          name: 'Montant Slim',
          quantity: 1,
          unit: 'قطاع',
          unitPrice: 0,
          isMissing: false,
          isInteractive: false,
          isActive: true,
        );

        final bomCleat = BomItem(
          category: 'profile',
          originalName: 'قطاع وصلة المونتوسليم 10 سم (Taquet Slim 10cm)',
          name: 'Taquet Slim 10cm',
          quantity: 2,
          unit: 'قطاع',
          unitPrice: 0,
          isMissing: false,
          isInteractive: false,
          isActive: true,
        );

        expect(PdfFicheCoupeApi.anglesFor(bom4590), equals('45° / 90°'));
        expect(PdfFicheCoupeApi.anglesFor(bom9090), equals('90° / 90°'));
        expect(PdfFicheCoupeApi.anglesFor(bomSlim), equals('90° / 90°'));
        expect(PdfFicheCoupeApi.anglesFor(bomCleat), equals('90° / 90°'));
      },
    );
  });
}
