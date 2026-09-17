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
}
