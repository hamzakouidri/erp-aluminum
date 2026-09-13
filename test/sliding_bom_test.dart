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

      // A single sliding frame must not be emitted through the opening-frame
      // row. This is the regression that made sliding series show opening
      // profiles in the drawing and material table.
      expect(
        bom.any((item) => item.originalName == 'إطار منزلق (Cadre Coulissant)'),
        isTrue,
      );
      expect(bom.any((item) => item.originalName == 'الإطار (Frame)'), isFalse);

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

  test('sliding BOM uses one series kit for every pair of leaves', () {
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
    model.zones = [
      WindowZone(
        id: 'four-leaves',
        content: ZoneContent.slidingSash,
        boundary: const Rect.fromLTWH(0, 0, 2400, 1200),
        slidingSashesCount: 4,
      ),
    ];

    final bom = ComponentCalculator.generateBom(model, const {});
    final kit = bom.firstWhere(
      (item) => item.originalName == 'كيت 40000 (Kit 40000)',
    );

    expect(kit.quantity, 2);
  });

  test('sliding BOM counts a kit for each independent two-leaf frame', () {
    final model = WindowModel(
      db: FakeSqlDatabase(),
      width: 3600,
      height: 1200,
      systemMode: 'sliding',
    );
    model.activeSlidingSeries = AluminumSeries(
      id: 1,
      profileId: 1,
      name: 'TPR 67000',
      type: 'sliding',
    );
    model.zones = List.generate(
      3,
      (index) => WindowZone(
        id: 'frame-$index',
        content: ZoneContent.slidingSash,
        boundary: Rect.fromLTWH(index * 1200, 0, 1200, 1200),
        slidingSashesCount: 2,
      ),
    );

    final bom = ComponentCalculator.generateBom(model, const {});
    final kit = bom.firstWhere(
      (item) => item.originalName == 'كيت 67000 (Kit 67000)',
    );

    expect(kit.quantity, 3);
  });

  test(
    'choosing a sliding leaf after drawing the frame promotes the frame',
    () {
      final model = WindowModel(
        db: FakeSqlDatabase(),
        width: 1500,
        height: 1200,
        systemMode: 'mixed',
      );
      model.activeSeries = AluminumSeries(
        id: 10,
        profileId: 1,
        name: 'Opening Series',
        type: 'opening',
        sections: [
          AluminumSection(
            id: 101,
            seriesId: 10,
            code: 'OF',
            name: 'Opening Frame',
            type: 'frame',
            isFrame: true,
          ),
        ],
      );
      model.frameOverride = model.activeSeries!.sections.first.toMap();
      model.activeSlidingSeries = AluminumSeries(
        id: 20,
        profileId: 1,
        name: 'Sliding Series',
        type: 'sliding',
        sections: [
          AluminumSection(
            id: 201,
            seriesId: 20,
            code: 'SF',
            name: 'Sliding Frame',
            type: 'frame',
            isFrame: true,
          ),
          AluminumSection(
            id: 202,
            seriesId: 20,
            code: 'SS',
            name: 'Sliding Sash',
            type: 'sash',
            isSash: true,
          ),
        ],
      );
      model.zones = [
        WindowZone(
          id: 'z1',
          content: ZoneContent.fixedGlass,
          boundary: const Rect.fromLTWH(0, 0, 1500, 1200),
        ),
      ];
      model.selection = SelectionInfo.zone('z1');

      model.setSelectedZoneSlidingSashes(3);

      expect(model.zones.single.content, ZoneContent.slidingSash);
      expect(model.slidingFrameOverride?['id'], 201);
      expect(model.slidingSashOverride?['id'], 202);
      expect(model.activeFrameOverride?['id'], 201);

      final bom = ComponentCalculator.generateBom(model, {});
      expect(
        bom.any((item) => item.originalName == 'إطار منزلق (Cadre Coulissant)'),
        isTrue,
      );
      expect(bom.any((item) => item.originalName == 'الإطار (Frame)'), isFalse);
    },
  );

  test('selecting a three-rail frame promotes the drawing to three sashes', () {
    final model = WindowModel(
      db: FakeSqlDatabase(),
      width: 1500,
      height: 1200,
      systemMode: 'sliding',
    );
    model.zones = [
      WindowZone(
        id: 'z1',
        content: ZoneContent.fixedGlass,
        boundary: const Rect.fromLTWH(0, 0, 1500, 1200),
      ),
    ];
    model.selection = SelectionInfo.zone('z1');

    model.applyFrameOverride(
      {'id': 300, 'code': 'C3R', 'name': 'Cadre 3 rails', 'type': 'frame'},
      sliding: true,
      manualSelection: true,
    );

    expect(model.zones.single.content, ZoneContent.slidingSash);
    expect(model.zones.single.slidingSashesCount, 3);
    expect(model.zones.single.slidingTrackCount, 3);
    expect(model.slidingFrameOverride?['id'], 300);
  });

  test('sliding leaves and frame rails can be selected independently', () {
    final model = WindowModel(db: FakeSqlDatabase(), width: 1500, height: 1200)
      ..zones = [
        WindowZone(
          id: 'z1',
          content: ZoneContent.slidingSash,
          boundary: const Rect.fromLTWH(0, 0, 1500, 1200),
          slidingSashesCount: 4,
          slidingTrackCount: 2,
        ),
      ];
    model.selection = SelectionInfo.zone('z1');
    model.slidingFrameOverride = {
      'id': 50,
      'design_track_mode': 'base',
      'design_track_count': 2,
      'design_supported_track_counts': '2,3,4,5,6',
    };

    model.setSelectedZoneSlidingTracks(5);

    expect(model.zones.single.slidingSashesCount, 4);
    expect(model.zones.single.slidingTrackCount, 5);
    expect(model.slidingSingleTrackAdditionCount(5), 3);
  });

  test('a three-track frame cannot leave only two sliding leaves', () {
    final model = WindowModel(db: FakeSqlDatabase(), width: 1200, height: 1000)
      ..zones = [
        WindowZone(
          id: 'z1',
          content: ZoneContent.slidingSash,
          boundary: const Rect.fromLTWH(0, 0, 1200, 1000),
          slidingSashesCount: 2,
          slidingTrackCount: 2,
        ),
      ];
    model.selection = SelectionInfo.zone('z1');
    model.slidingFrameOverride = {
      'design_track_mode': 'complete',
      'design_track_count': 3,
      'design_supported_track_counts': '3',
    };

    model.applyFrameOverride(model.slidingFrameOverride!, sliding: true);

    expect(model.zones.single.slidingTrackCount, 3);
    expect(model.zones.single.slidingSashesCount, 3);
    expect(model.supportedSlidingSashCounts, isNot(contains(2)));
  });

  test('three-track frame with integrated cover is rejected by shutter', () {
    final allowed = slidingFrameRoleAllowedForDrawing(
      {
        'allowed_with_shutter': 1,
        'integrated_side_cover': 1,
        'couvre_joint_width': 35,
      },
      hasShutter: true,
      isCaissonTunnel: false,
      isPvc: false,
    );

    expect(allowed, isFalse);
  });

  test('rail extension uses its own shutter permission', () {
    for (final permitted in [true, false]) {
      expect(
        slidingFrameRoleAllowedForDrawing(
          {
            'allowed_with_shutter': permitted ? 1 : 0,
            'integrated_side_cover': 1,
            'couvre_joint_width': 35,
          },
          hasShutter: true,
          isCaissonTunnel: false,
          isPvc: false,
          isFrameExtension: true,
        ),
        permitted,
      );
    }
  });

  test('PVC sliding keeps brush joint but excludes bourrage joint', () {
    final model = WindowModel(
      db: FakeSqlDatabase(),
      width: 1500,
      height: 1200,
      systemMode: 'sliding',
    );
    model.activeSlidingSeries = AluminumSeries(
      id: 30,
      profileId: 1,
      name: 'PVC Sliding',
      type: 'PVC',
    );
    model.zones = [
      WindowZone(
        id: 'z1',
        content: ZoneContent.slidingSash,
        boundary: const Rect.fromLTWH(0, 0, 1500, 1200),
      ),
    ];

    final bom = ComponentCalculator.generateBom(model, const {});

    expect(model.isSlidingPVC, isTrue);
    expect(
      bom.any(
        (item) => item.originalName == 'جوان بروس للظلفة (Joint Brosse Sash)',
      ),
      isTrue,
    );
    expect(bom.any((item) => item.roleKey == 'joint_bourrage'), isFalse);
  });

  test('a tunnel shutter on a complete window keeps the window profiles', () {
    final model = WindowModel(
      db: FakeSqlDatabase(),
      width: 1500,
      height: 1200,
      systemMode: 'mixed',
    );
    final frame = AluminumSection(
      id: 101,
      seriesId: 10,
      code: 'OF',
      name: 'Opening Frame',
      type: 'frame',
      isFrame: true,
      barLength: 6,
    );
    final series = AluminumSeries(
      id: 10,
      profileId: 1,
      name: '4000',
      type: 'opening',
      sections: [frame],
    );
    model.activeSeries = series;
    model.frameOverride = frame.toMap();
    model.hasShutter = true;
    model.isCaissonTunnel = true;
    model.zones = [
      WindowZone(
        id: 'z1',
        content: ZoneContent.fixedGlass,
        boundary: const Rect.fromLTWH(0, 0, 1500, 1200),
      ),
    ];

    final bom = ComponentCalculator.generateBom(model, const {});

    expect(bom.any((item) => item.originalName == 'الإطار (Frame)'), isTrue);
  });
}
