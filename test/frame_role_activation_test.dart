import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:database_data/Commande/Systeme/model.dart';
import 'package:database_data/Commande/Systeme/calculate_component.dart';
import 'package:database_data/Commande/Systeme/bom_engine_v2.dart';
import 'package:database_data/Commande/devis_builder.dart';
import 'package:database_data/settings/app_settings.dart';
import 'package:database_data/Commande/Systeme/model_serialization.dart';
import 'accessory_assembly_rules_test.dart' as fixtures;

class RoleDb extends fixtures.RuleDatabase {
  @override
  Future<List<Map<String, dynamic>>> getDesignSectionsForScopedDialogRoles(
    int seriesId,
    Iterable<String> roleKeys, {
    required String usageScope,
    bool requireDialog = true,
    bool requireQuantity = false,
    bool requireVisible = true,
  }) async => [
    for (final role in roleKeys)
      {'id': 100, 'name': role, 'design_role_key': role},
  ];

  @override
  Future<List<Map<String, dynamic>>> getDefaultJointsForSection({
    required int seriesId,
    required int sectionId,
    Iterable<String> positionKeys = const [],
  }) async => [
    {
      'id': 20,
      'name': 'Brosse',
      'position_key': 'profile_gasket_1',
      'price_per_meter': 10,
    },
    {
      'id': 21,
      'name': 'Alternative',
      'position_key': 'profile_gasket_1',
      'price_per_meter': 15,
    },
    {
      'id': 22,
      'name': 'Frappe',
      'position_key': 'profile_gasket_2',
      'price_per_meter': 12,
    },
  ];
}

class RoleWindow extends WindowModel {
  RoleWindow()
    : super(
        db: RoleDb(),
        width: 2000,
        height: 1200,
        profileThickness: 50,
        systemMode: 'mixed',
      ) {
    activeSeries = AluminumSeries(
      id: 1,
      profileId: 1,
      name: 'Opening',
      type: 'opening',
    );
    activeSlidingSeries = AluminumSeries(
      id: 2,
      profileId: 1,
      name: 'Sliding',
      type: 'sliding',
    );
    zones = [
      WindowZone(
        id: 'opening',
        content: ZoneContent.doubleSash,
        boundary: const Rect.fromLTRB(50, 50, 850, 1150),
      ),
      WindowZone(
        id: 'sliding',
        content: ZoneContent.slidingSash,
        boundary: const Rect.fromLTRB(1050, 50, 1950, 1150),
      ),
    ];
  }
  final mandatory = <String>{};
  final cacheRainureScopes = <bool>{false, true};
  @override
  AluminumSection? getConfiguredSectionForRole(
    String roleKey, {
    bool? useSlidingSeries,
  }) {
    if (![
      'seuil',
      'cache_dormant',
      'cache_rail',
      'cache_rainure',
      'profile_angle',
      'face_to_face',
    ].contains(roleKey))
      return null;
    if (roleKey == 'cache_rail' && useSlidingSeries != true) return null;
    if (roleKey == 'cache_rainure' &&
        !cacheRainureScopes.contains(useSlidingSeries == true)) {
      return null;
    }
    return AluminumSection(
      id: 100,
      seriesId: useSlidingSeries == true ? 2 : 1,
      name: roleKey,
      code: roleKey,
      type: roleKey,
      barLength: 6,
      visibleWidth: 30,
    );
  }

  @override
  bool isConfiguredRoleRequired(String roleKey, {bool? useSlidingSeries}) =>
      mandatory.contains('${useSlidingSeries == true}:$roleKey');

  @override
  AluminumSection? frameSectionForRect(Rect frame) => AluminumSection(
    id: frameUsesSlidingSeries(frame) ? 202 : 201,
    seriesId: frameUsesSlidingSeries(frame) ? 2 : 1,
    name: 'frame',
    code: 'frame',
    type: 'frame',
    barLength: 6,
    visibleWidth: 50,
    allowsSideCover: true,
  );
}

void main() {
  test('optional C toggle replaces and then restores the bottom frame', () {
    final model = RoleWindow();
    final openingFrame = model.getFrameRects().first;

    expect(model.hasBottomFrameForRect(openingFrame), isTrue);
    model.toggleSeuil(true);
    expect(model.usesFrameRole('seuil', sliding: false), isTrue);
    expect(model.hasBottomFrameForRect(openingFrame), isFalse);

    model.toggleSeuil(false);
    expect(model.usesFrameRole('seuil', sliding: false), isFalse);
    expect(model.hasBottomFrame, isTrue);
    expect(model.hasBottomFrameForRect(openingFrame), isTrue);
    model.dispose();
  });

  test(
    'mandatory sliding seuil removes only its bottom and copies frame cuts to cache',
    () {
      final model = RoleWindow()..mandatory.add('true:seuil');
      model.toggleCacheDormant(true);
      final frames = model.getFrameRects();
      expect(model.hasBottomFrameForRect(frames.first), isTrue);
      expect(model.hasBottomFrameForRect(frames.last), isFalse);
      final bom = ComponentCalculator.generateBom(model, {});
      final opening = bom.firstWhere(
        (i) => i.roleKey == 'frame' && i.sourceSeriesId == 1,
      );
      final sliding = bom.firstWhere(
        (i) => i.roleKey == 'frame' && i.sourceSeriesId == 2,
      );
      expect(opening.pieces, hasLength(4));
      expect(sliding.pieces, hasLength(3));
      expect(bom.where((i) => i.roleKey == 'seuil').single.sourceSeriesId, 2);
      for (final frame in [opening, sliding]) {
        expect(
          bom
              .firstWhere(
                (i) =>
                    i.roleKey == 'cache_dormant' &&
                    i.sourceSeriesId == frame.sourceSeriesId,
              )
              .pieces,
          frame.pieces,
        );
      }
      model.dispose();
    },
  );

  test('cache rail defaults on and always uses tracks minus one per side', () {
    final model = RoleWindow();
    model.zones.last.slidingTrackCount = 5;
    var bom = ComponentCalculator.generateBom(model, {});
    expect(
      bom.singleWhere((i) => i.roleKey == 'cache_rail').pieces,
      hasLength(8),
    );
    model.toggleCacheRail(false);
    bom = ComponentCalculator.generateBom(model, {});
    expect(bom.where((i) => i.roleKey == 'cache_rail'), isEmpty);
    model.toggleCacheRail(true);
    model.zones.last.slidingTrackCount = 4;
    bom = ComponentCalculator.generateBom(model, {});
    expect(
      bom.singleWhere((i) => i.roleKey == 'cache_rail').pieces,
      hasLength(6),
    );
    model.dispose();
  });

  test(
    'cache rail remains optional even when its catalogue role is required',
    () {
      final model = RoleWindow()..mandatory.add('true:cache_rail');
      expect(model.usesCacheRail, isTrue);
      model.toggleCacheRail(false);
      expect(model.usesFrameRole('cache_rail', sliding: true), isFalse);
      model.dispose();
    },
  );

  test(
    'cache-rainure needs compatible frames and both different series roles',
    () {
      final model = RoleWindow();
      model.zones[0].boundary = const Rect.fromLTRB(50, 50, 950, 1150);
      model.zones[1].boundary = const Rect.fromLTRB(1050, 50, 1950, 1150);

      final contacts = model.getCacheRainureContacts();
      expect(contacts, hasLength(1));
      expect(contacts.single.length, 1200);
      expect(contacts.single.insideUsesSlidingSeries, isFalse);
      expect(contacts.single.outsideUsesSlidingSeries, isTrue);

      model.cacheRainureScopes.remove(true);
      expect(model.getCacheRainureContacts(), isEmpty);
      model.dispose();
    },
  );

  test('cache-rainure applies to cadre double mullions inside and outside', () {
    final model = RoleWindow();
    model.zones[0].boundary = const Rect.fromLTRB(50, 50, 950, 1150);
    model.zones[1].boundary = const Rect.fromLTRB(1050, 50, 1950, 1150);
    model.mullionProfiles['V_1000.0'] = MullionProfileType.flat;

    final segments = model.getCadreDoubleRainureSegments();
    expect(segments, hasLength(1));
    expect(segments.single.length, 1100);

    final bom = ComponentCalculator.generateBom(model, {});
    final cacheRainure = bom
        .where((i) => i.roleKey == 'cache_rainure')
        .toList();
    expect(cacheRainure, isNotEmpty);
    expect(
      cacheRainure.every(
        (i) =>
            i.cuttingList != null &&
            i.cuttingList!.contains('قطع القص:') &&
            i.cuttingList!.contains('مم'),
      ),
      isTrue,
    );
    model.dispose();
  });

  test(
    'all three roles generate one linked gasket per position at actual length',
    () async {
      final model = RoleWindow();
      final profiles = [
        for (final role in ['seuil', 'cache_dormant', 'cache_rail'])
          BomItem(
            category: 'profile',
            originalName: role,
            name: role,
            quantity: 1,
            unit: 'قطاع',
            unitPrice: 0,
            pieces: [1.2, 1.2],
            catalogItemId: 100,
            sourceSeriesId: 2,
            roleKey: role,
            selectorType: role,
            selectorCategory: 'profile',
          ),
      ];
      final result = await BomEngineV2(
        database: RoleDb(),
      ).filterItemsByAvailableCandidates(window: model, items: profiles);
      final joints = result
          .where((i) => (i.overrideKey ?? '').startsWith('frame-role-joint:'))
          .toList();
      expect(joints, hasLength(6));
      expect(joints.every((i) => (i.quantity - 2.4).abs() < 0.0001), isTrue);
      expect(joints.any((i) => i.catalogItemId == 21), isFalse);
      model.dispose();
    },
  );

  test('profile angle mode sets and calculates pieces correctly', () async {
    final model = RoleWindow();
    expect(model.profileAngleMode, 0);
    expect(model.usesProfileAngle, false);

    model.setProfileAngleMode(1); // right
    expect(model.profileAngleMode, 1);
    expect(model.usesProfileAngle, true);
    expect(model.profileAngleModeName, 'يمين (90°)');

    var items = ComponentCalculator.generateBom(model, {});
    var angleItem = items.firstWhere(
      (item) =>
          (item.roleKey == 'profile_angle' ||
          item.selectorType == 'profile_angle'),
    );
    expect(angleItem.pieces, hasLength(1));
    expect(
      angleItem.pieces!.first,
      closeTo(1.2, 0.001),
    ); // window height = 1200mm = 1.2m
    expect(angleItem.cuttingList, 'يمين (90°)');

    model.setProfileAngleMode(3); // both
    expect(model.profileAngleMode, 3);
    expect(model.profileAngleModeName, 'الجهتين (90°)');

    items = ComponentCalculator.generateBom(model, {});
    angleItem = items.firstWhere(
      (item) =>
          (item.roleKey == 'profile_angle' ||
          item.selectorType == 'profile_angle'),
    );
    expect(angleItem.pieces, hasLength(2));
    expect(angleItem.pieces![0], closeTo(1.2, 0.001));
    expect(angleItem.pieces![1], closeTo(1.2, 0.001));
    expect(angleItem.cuttingList, 'الجهتين (90°)');

    model.dispose();
  });

  test(
    'isSlidingMontantReinforced recognizes chicane and chicane_renforcee',
    () {
      final model = RoleWindow();
      expect(
        model.isSlidingMontantReinforced({
          'design_role_key': 'chicane_renforcee',
        }, central: true),
        isTrue,
      );
      expect(
        model.isSlidingMontantReinforced({
          'design_role_key': 'chicane',
        }, central: true),
        isTrue,
      );
      expect(
        model.isSlidingMontantReinforced({
          'name': 'Chicane',
          'type': 'chicane',
        }, central: true),
        isTrue,
      );
      expect(
        model.isSlidingMontantReinforced({
          'name': 'شيكان عادية',
          'type': 'profil',
        }, central: true),
        isTrue,
      );
      expect(
        model.isSlidingMontantReinforced({
          'name': 'قائم وسطي',
          'type': 'sash',
        }, central: true),
        isFalse,
      );
      model.dispose();
    },
  );

  test('multi-frame junctions detection for 3 and 4 adjacent frames', () {
    final model = RoleWindow();
    // 3 adjacent frames side by side
    model.zones = [
      WindowZone(
        id: 'f1',
        content: ZoneContent.singleSash,
        boundary: const Rect.fromLTRB(50, 50, 550, 1150),
      ),
      WindowZone(
        id: 'f2',
        content: ZoneContent.singleSash,
        boundary: const Rect.fromLTRB(650, 50, 1150, 1150),
      ),
      WindowZone(
        id: 'f3',
        content: ZoneContent.singleSash,
        boundary: const Rect.fromLTRB(1250, 50, 1750, 1150),
      ),
    ];
    final junctions3 = model.getAdjacentFrameJunctions();
    expect(junctions3, hasLength(2));
    expect(junctions3[0].label, 'بين الإطار 1 و 2');
    expect(junctions3[1].label, 'بين الإطار 2 و 3');
    expect(junctions3[0].height, closeTo(1200, 1.0));
    expect(junctions3[1].height, closeTo(1200, 1.0));

    // 4 adjacent frames side by side
    model.zones = [
      WindowZone(
        id: 'f1',
        content: ZoneContent.singleSash,
        boundary: const Rect.fromLTRB(50, 50, 450, 1150),
      ),
      WindowZone(
        id: 'f2',
        content: ZoneContent.singleSash,
        boundary: const Rect.fromLTRB(550, 50, 950, 1150),
      ),
      WindowZone(
        id: 'f3',
        content: ZoneContent.singleSash,
        boundary: const Rect.fromLTRB(1050, 50, 1450, 1150),
      ),
      WindowZone(
        id: 'f4',
        content: ZoneContent.singleSash,
        boundary: const Rect.fromLTRB(1550, 50, 1950, 1150),
      ),
    ];
    final junctions4 = model.getAdjacentFrameJunctions();
    expect(junctions4, hasLength(3));
    expect(junctions4[0].label, 'بين الإطار 1 و 2');
    expect(junctions4[1].label, 'بين الإطار 2 و 3');
    expect(junctions4[2].label, 'بين الإطار 3 و 4');
    model.dispose();
  });

  test(
    'multi-frame profil d angle selection and BOM calculation for specific or all junctions',
    () {
      final model = RoleWindow();
      // 4 frames
      model.zones = [
        WindowZone(
          id: 'f1',
          content: ZoneContent.singleSash,
          boundary: const Rect.fromLTRB(50, 50, 450, 1150),
        ),
        WindowZone(
          id: 'f2',
          content: ZoneContent.singleSash,
          boundary: const Rect.fromLTRB(550, 50, 950, 1150),
        ),
        WindowZone(
          id: 'f3',
          content: ZoneContent.singleSash,
          boundary: const Rect.fromLTRB(1050, 50, 1450, 1150),
        ),
        WindowZone(
          id: 'f4',
          content: ZoneContent.singleSash,
          boundary: const Rect.fromLTRB(1550, 50, 1950, 1150),
        ),
      ];

      expect(model.usesProfileAngle, isFalse);

      // 1. Select only between Frame 1 & 2 (junction 0)
      model.toggleProfileAngleJunction(0, true);
      expect(model.usesProfileAngle, isTrue);
      expect(model.profileAngleModeName, 'بين الإطار 1 و 2 (90°)');

      var bom = ComponentCalculator.generateBom(model, {});
      var angleItem = bom.firstWhere((i) => i.roleKey == 'profile_angle');
      expect(angleItem.pieces, hasLength(1));
      expect(angleItem.pieces!.first, closeTo(1.2, 0.001));
      expect(angleItem.cuttingList, 'بين الإطار 1 و 2');

      // 2. Select between Frame 3 & 4 as well (junctions 0 and 2)
      model.toggleProfileAngleJunction(2, true);
      expect(model.profileAngleModeName, '2 فواصل (90°)');
      bom = ComponentCalculator.generateBom(model, {});
      angleItem = bom.firstWhere((i) => i.roleKey == 'profile_angle');
      expect(angleItem.pieces, hasLength(2));
      expect(angleItem.cuttingList, 'بين الإطار 1 و 2 + بين الإطار 3 و 4');

      // 3. Select all junctions (كلها)
      model.setAllProfileAngleJunctions(true);
      expect(model.profileAngleJunctions, hasLength(3));
      expect(model.profileAngleModeName, 'جميع الفواصل (3) (90°)');
      bom = ComponentCalculator.generateBom(model, {});
      angleItem = bom.firstWhere((i) => i.roleKey == 'profile_angle');
      expect(angleItem.pieces, hasLength(3));
      expect(
        angleItem.cuttingList,
        'بين الإطار 1 و 2 + بين الإطار 2 و 3 + بين الإطار 3 و 4',
      );

      // 4. Clear all junctions
      model.setAllProfileAngleJunctions(false);
      expect(model.usesProfileAngle, isFalse);
      bom = ComponentCalculator.generateBom(model, {});
      expect(bom.any((i) => i.roleKey == 'profile_angle'), isFalse);

      model.dispose();
    },
  );

  test(
    'mandatory profile_angle in series rules automatically activates in BOM',
    () {
      final model = RoleWindow();
      model.mandatory.addAll(['false:profile_angle', 'true:profile_angle']);
      // 3 frames
      model.zones = [
        WindowZone(
          id: 'f1',
          content: ZoneContent.singleSash,
          boundary: const Rect.fromLTRB(50, 50, 550, 1150),
        ),
        WindowZone(
          id: 'f2',
          content: ZoneContent.singleSash,
          boundary: const Rect.fromLTRB(650, 50, 1150, 1150),
        ),
        WindowZone(
          id: 'f3',
          content: ZoneContent.singleSash,
          boundary: const Rect.fromLTRB(1250, 50, 1750, 1150),
        ),
      ];

      expect(model.usesProfileAngle, isTrue);
      expect(model.activeProfileAngleJunctions, hasLength(2));
      final bom = ComponentCalculator.generateBom(model, {});
      final angleItem = bom.firstWhere((i) => i.roleKey == 'profile_angle');
      expect(angleItem.pieces, hasLength(2));
      model.dispose();
    },
  );

  test(
    'face_to_face role auto-activates on 4-sash sliding and generates 2 central pieces',
    () {
      final model = RoleWindow();
      model.systemMode = 'sliding';
      model.zones = [
        WindowZone(
          id: 'z1',
          content: ZoneContent.slidingSash,
          slidingSashesCount: 4,
          slidingTrackCount: 2,
          boundary: const Rect.fromLTRB(50, 50, 1950, 1150),
        ),
      ];

      final bom = ComponentCalculator.generateBom(model, {});
      final ftfItem = bom.firstWhere((i) => i.roleKey == 'face_to_face');
      expect(ftfItem, isNotNull);
      // 4 sashes meeting in the center requires 1 face-to-face piece
      expect(ftfItem.pieces, hasLength(1));
      expect(ftfItem.selectorType, 'face_to_face');
      model.dispose();
    },
  );

  test(
    'face_to_face disabled converts 4-sash to normal overlapping and omits face_to_face pieces',
    () {
      final model = RoleWindow();
      model.systemMode = 'sliding';
      model.zones = [
        WindowZone(
          id: 'z1',
          content: ZoneContent.slidingSash,
          slidingSashesCount: 4,
          slidingTrackCount: 2,
          slidingFaceToFace: false, // explicitly turned off by user
          boundary: const Rect.fromLTRB(50, 50, 1950, 1150),
        ),
      ];

      final bom = ComponentCalculator.generateBom(model, {});
      final ftfItems = bom.where((i) => i.roleKey == 'face_to_face');
      expect(ftfItems, isEmpty);
      model.dispose();
    },
  );

  test(
    'decorative central handle repairs the functional pair and face-to-face disables both',
    () {
      final model = RoleWindow();
      model.systemMode = 'sliding';
      final zone = WindowZone(
        id: 'z1',
        content: ZoneContent.slidingSash,
        slidingSashesCount: 4,
        slidingTrackCount: 2,
        slidingFaceToFace: true,
        slidingCentralHandle: false,
        slidingSecondCentralHandle: false,
        isSelected: true,
        boundary: const Rect.fromLTRB(50, 50, 1950, 1150),
      );
      model.zones = [zone];

      expect(zone.openDirection, OpenDirection.right);
      model.setSelectedZoneSlidingSecondCentralHandle(true);
      expect(zone.slidingCentralHandle, isTrue);
      expect(zone.slidingSecondCentralHandle, isTrue);

      model.setSelectedZoneSlidingFaceToFace(false);
      expect(zone.slidingCentralHandle, isFalse);
      expect(zone.slidingSecondCentralHandle, isFalse);
      model.dispose();
    },
  );

  test('supportedSlidingSashCounts obeys max_sliding_sashes series rule', () {
    final model = RoleWindow();
    model.systemMode = 'sliding';
    model.zones = [
      WindowZone(
        id: 'z1',
        content: ZoneContent.slidingSash,
        slidingSashesCount: 2,
        slidingTrackCount: 2,
        boundary: const Rect.fromLTRB(50, 50, 1950, 1150),
      ),
    ];

    // Case 1: No restriction (0 or null) -> allows 2, 3, 4, 5, 6
    model.slidingSeriesTableConfig = {'max_sliding_sashes': 0};
    expect(model.supportedSlidingSashCounts, equals({2, 3, 4, 5, 6}));

    // Case 2: Restricted to 2 sashes
    model.slidingSeriesTableConfig = {'max_sliding_sashes': 2};
    expect(model.supportedSlidingSashCounts, equals({2}));

    // Case 3: Restricted to 4 sashes
    model.slidingSeriesTableConfig = {'max_sliding_sashes': 4};
    expect(model.supportedSlidingSashCounts, equals({2, 3, 4}));

    model.dispose();
  });

  test(
    'empty frame beside sliding window uses opening series frame and parclose',
    () {
      final model = RoleWindow();
      model.systemMode = 'mixed';
      final frameSliding = const Rect.fromLTRB(50, 50, 1000, 1150);
      final frameEmpty = const Rect.fromLTRB(1000, 50, 1950, 1150);
      model.zones = [
        WindowZone(
          id: 'z1',
          content: ZoneContent.slidingSash,
          slidingSashesCount: 2,
          slidingTrackCount: 2,
          boundary: frameSliding,
        ),
        WindowZone(id: 'z2', content: ZoneContent.empty, boundary: frameEmpty),
      ];
      model.componentOverrides['باكيت الزجاج (Parclose)'] = {
        'id': 50,
        'name': 'باكيت 514',
        'max_glass_thickness': 8.0,
      };

      expect(model.frameUsesSlidingSeries(frameSliding), isTrue);
      expect(model.frameUsesSlidingSeries(frameEmpty), isFalse);
      expect(model.usesSlidingPrimaryProfiles, isFalse);

      final bom = ComponentCalculator.generateBom(model, {});
      // Parclose for the empty frame should be present
      final parcloseItems = bom.where(
        (i) => i.name.contains('باكيت') || i.name.contains('Parclose'),
      );
      expect(parcloseItems, isNotEmpty);

      model.dispose();
    },
  );

  test(
    'sliding montant descriptions show exact counts for reinforced and simple',
    () {
      // 1. All simple (2 sashes = 2 lateral, 2 central)
      final allSimpleDrawing = {
        'hasShutter': false,
        'zones': [
          {
            'content': 'slidingSash',
            'slidingSashesCount': 2,
            'slidingMontantReinforced': {
              'lateral_0': false,
              'lateral_1': false,
              'central_0': false,
              'central_1': false,
            },
          },
        ],
      };

      final arLine = DevisBuilder.buildLineItemFromDetail({
        'id': 1,
        'window_type': 'coulissant',
        'largeur': 1200,
        'hauteur': 1400,
        'quantity': 1,
        'price': 1000,
        'partitions_json': allSimpleDrawing,
      }, overrideLang: AppLanguage.arabic);

      expect(arLine.details.join('\n'), contains('القائم الوسطي: 2 غير مدعم'));
      expect(arLine.details.join('\n'), contains('القائم الجانبي: 2 غير مدعم'));

      final frLine = DevisBuilder.buildLineItemFromDetail({
        'id': 1,
        'window_type': 'coulissant',
        'largeur': 1200,
        'hauteur': 1400,
        'quantity': 1,
        'price': 1000,
        'partitions_json': allSimpleDrawing,
      }, overrideLang: AppLanguage.french);

      expect(
        frLine.details.join('\n'),
        contains('Montant central: 2 simple(s)'),
      );
      expect(
        frLine.details.join('\n'),
        contains('Montant latéral: 2 simple(s)'),
      );

      // 2. Mixed (1 reinforced, 1 simple)
      final mixedDrawing = {
        'hasShutter': false,
        'zones': [
          {
            'content': 'slidingSash',
            'slidingSashesCount': 2,
            'slidingMontantReinforced': {
              'lateral_0': true,
              'lateral_1': false,
              'central_0': true,
              'central_1': false,
            },
          },
        ],
      };

      final arMixed = DevisBuilder.buildLineItemFromDetail({
        'id': 2,
        'window_type': 'coulissant',
        'largeur': 1200,
        'hauteur': 1400,
        'quantity': 1,
        'price': 1000,
        'partitions_json': mixedDrawing,
      }, overrideLang: AppLanguage.arabic);

      expect(
        arMixed.details.join('\n'),
        contains('القائم الوسطي: 1 مدعم، 1 غير مدعم'),
      );
      expect(
        arMixed.details.join('\n'),
        contains('القائم الجانبي: 1 مدعم، 1 غير مدعم'),
      );

      final frMixed = DevisBuilder.buildLineItemFromDetail({
        'id': 2,
        'window_type': 'coulissant',
        'largeur': 1200,
        'hauteur': 1400,
        'quantity': 1,
        'price': 1000,
        'partitions_json': mixedDrawing,
      }, overrideLang: AppLanguage.french);

      expect(
        frMixed.details.join('\n'),
        contains('Montant central: 1 renforcé(s), 1 simple(s)'),
      );
      expect(
        frMixed.details.join('\n'),
        contains('Montant latéral: 1 renforcé(s), 1 simple(s)'),
      );
    },
  );

  test(
    'BOM separates reinforced and simple montants with their pieces when mixed',
    () {
      final model = RoleWindow();
      model.systemMode = 'sliding';
      model.activeSlidingSeries = AluminumSeries(
        id: 2,
        profileId: 1,
        name: 'Sliding TPR',
        type: 'sliding',
        hasThreePieceSash: true,
      );

      model.componentOverrides['قائم جانبي (Sash Lateral)'] = {
        'id': 3,
        'name': 'Montant Lateral Simple',
      };
      model.componentOverrides['قائم جانبي معزز (Sash Lateral Renforcé)'] = {
        'id': 4,
        'name': 'Montant Lateral Renforce',
      };
      model.componentOverrides['قائم وسطي (Sash Central)'] = {
        'id': 5,
        'name': 'Montant Central Simple',
      };
      model.componentOverrides['قائم وسطي معزز (Sash Central Renforcé)'] = {
        'id': 6,
        'name': 'Montant Central Renforce',
      };

      model.zones = [
        WindowZone(
          id: 'z1',
          content: ZoneContent.slidingSash,
          boundary: const Rect.fromLTWH(0, 0, 1600, 1200),
          slidingSashesCount: 2,
          slidingMontantReinforced: {
            'lateral_0': true,
            'lateral_1': false,
            'central_0': true,
            'central_1': false,
          },
        ),
      ];

      final bom = ComponentCalculator.generateBom(model, {});
      final lateralNormal = bom.where(
        (i) => i.name.contains('قائم جانبي (Sash Lateral)'),
      );
      final lateralRenforced = bom.where(
        (i) => i.name.contains('قائم جانبي معزز'),
      );
      final centralNormal = bom.where(
        (i) => i.name.contains('قائم وسطي (Sash Central)'),
      );
      final centralRenforced = bom.where(
        (i) => i.name.contains('قائم وسطي معزز'),
      );

      expect(lateralNormal, isNotEmpty);
      expect(lateralRenforced, isNotEmpty);
      expect(centralNormal, isNotEmpty);
      expect(centralRenforced, isNotEmpty);

      expect(lateralNormal.first.pieces, hasLength(1));
      expect(lateralRenforced.first.pieces, hasLength(1));
      expect(centralNormal.first.pieces, hasLength(1));
      expect(centralRenforced.first.pieces, hasLength(1));

      model.dispose();
    },
  );

  test(
    'undo restores window drawing state after convertCurrentDrawingToShutter',
    () async {
      final model = RoleWindow();
      model.width = 1200;
      model.height = 1000;
      model.zones = [
        WindowZone(
          id: 'z_initial',
          content: ZoneContent.singleSash,
          boundary: const Rect.fromLTWH(0, 0, 1200, 1000),
        ),
      ];
      model.hasSideCovers = true;
      model.isShutterOnly = false;
      model.drawingMode = '';

      expect(model.isShutterOnly, isFalse);
      expect(model.zones, hasLength(1));

      // Convert to shutter
      model.convertCurrentDrawingToShutter();

      expect(model.isShutterOnly, isTrue);
      expect(model.hasShutter, isTrue);
      expect(model.drawingMode, 'shutter_only');
      expect(model.zones, isEmpty);

      // Call Undo
      model.undo();

      // Verify window state is fully restored
      expect(model.isShutterOnly, isFalse);
      expect(model.drawingMode, isNot('shutter_only'));
      expect(model.zones, hasLength(1));
      expect(model.zones.first.id, 'z_initial');
      expect(model.width, 1200);
      expect(model.height, 1000);

      await Future.delayed(const Duration(milliseconds: 150));
      model.dispose();
    },
  );

  test(
    'saved multi-frame drawing preserves hasSideCovers across notifyListeners',
    () {
      final model = RoleWindow();
      final drawingMap = {
        'width': 1600.0,
        'height': 1200.0,
        'hasSideCovers': true,
        'zones': [
          {
            'id': 'f1',
            'boundary': {
              'left': 10.0,
              'top': 10.0,
              'width': 100.0,
              'height': 100.0,
            },
            'content': 'fixedGlass',
          },
          {
            'id': 'f2',
            'boundary': {
              'left': 250.0,
              'top': 10.0,
              'width': 100.0,
              'height': 100.0,
            },
            'content': 'fixedGlass',
          },
        ],
      };

      applyWindowModelFromMap(model, drawingMap);

      expect(model.hasSideCovers, isTrue);
      expect(model.multiFrameSideCoverManuallyEnabled, isTrue);

      // Trigger notifyListeners as happens on catalogue load or canvas repaint
      model.notifyListeners();

      expect(model.getFrameRects().length, greaterThan(1));
      expect(model.hasSideCovers, isTrue);

      model.dispose();
    },
  );

  test(
    'updateLayoutMetrics keeps canvasScale stable when bottom panel opens and closes',
    () {
      final model = RoleWindow();
      model.width = 1200;
      model.height = 1000;
      model.zones = [
        WindowZone(
          id: 'z1',
          boundary: const Rect.fromLTWH(50, 50, 1100, 900),
          content: ZoneContent.fixedGlass,
        ),
      ];

      // Initial layout with full screen height (e.g. 800)
      model.updateLayoutMetrics(const Size(600, 800));
      final initialScale = model.canvasScale;
      expect(initialScale, greaterThan(0));

      // Bottom panel opens: height shrinks from 800 to 500
      model.updateLayoutMetrics(const Size(600, 500));
      final shrunkScale = model.canvasScale;

      // Scale must remain stable and not bounce/shrink
      expect(shrunkScale, closeTo(initialScale, 0.0001));

      // Bottom panel closes: height returns to 800
      model.updateLayoutMetrics(const Size(600, 800));
      expect(model.canvasScale, closeTo(initialScale, 0.0001));

      model.dispose();
    },
  );

  test(
    'resizeFrameFromHandles preserves exact mullion thickness and expands zones proportionally',
    () {
      final model = RoleWindow();
      model.profileThickness = 50.0;
      model.width =
          1100.0; // 50 (frame) + 475 (zone1) + 50 (mullion) + 475 (zone2) + 50 (frame)
      model.height = 1000.0;

      // 2 zones divided by a 50 mm vertical mullion:
      // Zone 1: left 50, right 525 (width 475)
      // Mullion: 525 to 575 (width 50)
      // Zone 2: left 575, right 1050 (width 475)
      model.zones = [
        WindowZone(
          id: 'z1',
          boundary: const Rect.fromLTWH(50, 50, 475, 900),
          content: ZoneContent.fixedGlass,
        ),
        WindowZone(
          id: 'z2',
          boundary: const Rect.fromLTWH(575, 50, 475, 900),
          content: ZoneContent.fixedGlass,
        ),
      ];

      expect(model.getFrameRects().length, equals(1));

      // Resize frame to the right by +200 mm
      model.resizeFrameFromHandles(
        'frame:0',
        moveLeft: false,
        moveRight: true,
        moveTop: false,
        moveBottom: false,
        deltaX: 200.0,
        deltaY: 0.0,
        saveHistory: false,
      );

      // Frame must still be 1 single unified frame, not split!
      expect(model.getFrameRects().length, equals(1));

      // The mullion gap between zone 1 and zone 2 must be EXACTLY 50.0 mm (= profileThickness)!
      final z1 = model.zones.firstWhere((z) => z.id == 'z1');
      final z2 = model.zones.firstWhere((z) => z.id == 'z2');
      final mullionGap = z2.boundary.left - z1.boundary.right;
      expect(mullionGap, closeTo(50.0, 0.5));

      // Both zones must have grown equally by 100 mm each (475 -> 575)
      expect(z1.boundary.width, closeTo(575.0, 1.0));
      expect(z2.boundary.width, closeTo(575.0, 1.0));

      model.dispose();
    },
  );

  test(
    'double sash omits Bouchon Batmo when no rule or section is configured',
    () {
      final model = RoleWindow();
      model.width = 1200;
      model.height = 1400;
      model.zones = [
        WindowZone(
          id: 'z1',
          boundary: const Rect.fromLTWH(50, 50, 1100, 1300),
          content: ZoneContent.doubleSash,
        ),
      ];

      final bom = ComponentCalculator.generateBom(model, {});
      final hasBouchon = bom.any(
        (item) =>
            item.originalName.contains('Bouchon Batmo') ||
            item.originalName.contains('بوشون باتمو'),
      );
      expect(hasBouchon, isFalse);

      model.dispose();
    },
  );

  test(
    'door key locks and cylinders are preserved on aluminum opening windows',
    () {
      final model = RoleWindow();
      model.width = 1000;
      model.height = 2000;
      model.hasBottomFrame = true;
      model.zones = [
        WindowZone(
          id: 'door',
          boundary: const Rect.fromLTWH(50, 50, 900, 1900),
          content: ZoneContent.singleSash,
          isSash105: true,
          lockType: LockType.clef,
        ),
      ];

      final bom = ComponentCalculator.generateBom(model, {});
      final hasCanon = bom.any(
        (item) =>
            item.originalName.contains('كانون') ||
            item.originalName.contains('Canon') ||
            item.originalName.contains('قفل'),
      );
      expect(hasCanon, isTrue);

      // Should NOT convert door cylinder into window cremone
      final cremoneItem = bom.firstWhere(
        (item) => item.originalName.contains('كريمون (Cremone)'),
        orElse: () => BomItem(
          category: 'accessory',
          name: '',
          originalName: '',
          quantity: 0,
          unit: '',
          unitPrice: 0,
        ),
      );
      expect(cremoneItem.quantity, equals(0));

      model.dispose();
    },
  );

  test(
    'System OB generates 3 triangle pieces including horizontal compas piece',
    () {
      final model = RoleWindow();
      model.width = 800;
      model.height = 1200;
      model.useSystemOB = true;
      model.zones = [
        WindowZone(
          id: 'ob_sash',
          boundary: const Rect.fromLTWH(50, 50, 700, 1100),
          content: ZoneContent.singleSash,
        ),
      ];

      // Configure a triangle profile — getSectionByType('triangle') fallback
      // will find it from activeSeries.sections automatically.
      model.activeSeries = AluminumSeries(
        id: 1,
        profileId: 1,
        name: 'Test Series',
        type: 'opening',
        sections: [
          AluminumSection(
            id: 999,
            seriesId: 1,
            name: 'Tringle 999',
            code: 'TR999',
            type: 'triangle',
            barLength: 6.0,
            visibleWidth: 15.0,
          ),
        ],
      );
      model.componentOverrides['System OB'] = {
        'triangle_link_mode': 'required',
        'triangle_deduction_mm': 100.0,
        'triangle_width_deduction_mm': 50.0,
        'triangle_quantity': 1,
      };

      final bom = ComponentCalculator.generateBom(model, {});
      final obTriangle = bom.firstWhere(
        (item) =>
            item.originalName.contains('System OB') &&
            item.originalName.contains('تراينغل'),
        orElse: () => BomItem(
          category: 'profile',
          name: '',
          originalName: '',
          quantity: 0,
          unit: '',
          unitPrice: 0,
        ),
      );
      expect(obTriangle.name.isNotEmpty, isTrue);
      // 3 pieces: 2 vertical + 1 horizontal
      expect(obTriangle.pieces?.length, equals(3));
      expect(obTriangle.cuttingList, contains('(أفقي)'));

      model.dispose();
    },
  );
}
