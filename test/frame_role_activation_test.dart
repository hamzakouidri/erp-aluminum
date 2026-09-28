import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:database_data/Commande/Systeme/model.dart';
import 'package:database_data/Commande/Systeme/calculate_component.dart';
import 'package:database_data/Commande/Systeme/bom_engine_v2.dart';
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
    final cacheRainure =
        bom.where((i) => i.roleKey == 'cache_rainure').toList();
    expect(cacheRainure, isNotEmpty);
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
      (item) => (item.roleKey == 'profile_angle' || item.selectorType == 'profile_angle'),
    );
    expect(angleItem.pieces, hasLength(1));
    expect(angleItem.pieces!.first, closeTo(1.2, 0.001)); // window height = 1200mm = 1.2m
    expect(angleItem.cuttingList, 'يمين (90°)');

    model.setProfileAngleMode(3); // both
    expect(model.profileAngleMode, 3);
    expect(model.profileAngleModeName, 'الجهتين (90°)');

    items = ComponentCalculator.generateBom(model, {});
    angleItem = items.firstWhere(
      (item) => (item.roleKey == 'profile_angle' || item.selectorType == 'profile_angle'),
    );
    expect(angleItem.pieces, hasLength(2));
    expect(angleItem.pieces![0], closeTo(1.2, 0.001));
    expect(angleItem.pieces![1], closeTo(1.2, 0.001));
    expect(angleItem.cuttingList, 'الجهتين (90°)');

    model.dispose();
  });

  test('isSlidingMontantReinforced recognizes chicane and chicane_renforcee', () {
    final model = RoleWindow();
    expect(
      model.isSlidingMontantReinforced({'design_role_key': 'chicane_renforcee'}, central: true),
      isTrue,
    );
    expect(
      model.isSlidingMontantReinforced({'design_role_key': 'chicane'}, central: true),
      isTrue,
    );
    expect(
      model.isSlidingMontantReinforced({'name': 'Chicane', 'type': 'chicane'}, central: true),
      isTrue,
    );
    expect(
      model.isSlidingMontantReinforced({'name': 'شيكان عادية', 'type': 'profil'}, central: true),
      isTrue,
    );
    expect(
      model.isSlidingMontantReinforced({'name': 'قائم وسطي', 'type': 'sash'}, central: true),
      isFalse,
    );
    model.dispose();
  });
}
