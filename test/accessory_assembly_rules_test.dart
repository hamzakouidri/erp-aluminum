import 'dart:ui';
import 'package:database_data/Commande/Systeme/accessory_assembly.dart';
import 'package:database_data/Commande/Systeme/bom_engine_v2.dart';
import 'package:database_data/Commande/Systeme/calculate_component.dart';
import 'package:database_data/Commande/Systeme/model.dart';
import 'package:database_data/Commande/Systeme/profile_selector_dialog.dart';
import 'package:database_data/sql_database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

class MemoryDatabase implements Database {
  @override
  Future<void> execute(String sql, [List<Object?>? arguments]) async {}

  @override
  Future<List<Map<String, Object?>>> rawQuery(
    String sql, [
    List<Object?>? arguments,
  ]) async => [];

  @override
  Future<List<Map<String, Object?>>> query(
    String table, {
    bool? distinct,
    List<String>? columns,
    String? where,
    List<Object?>? whereArgs,
    String? groupBy,
    String? having,
    String? orderBy,
    int? limit,
    int? offset,
  }) async => table == 'Accessories'
      ? [
          for (final id in whereArgs ?? [])
            {
              'id': id,
              'name': 'Hardware $id',
              'is_active': 1,
              'material_type': 'both',
              'price': 10,
            },
        ]
      : [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class RuleDatabase extends SqlDatabase {
  final rules = <Map<String, dynamic>>[
    {
      'item_id': 1,
      'role_key': 'frame_clamp',
      'top_corner_qty': 2,
      'bottom_corner_qty': 2,
      'show_in_dialog': 0,
    },
    {
      'item_id': 2,
      'role_key': 'frame_clamp',
      'top_corner_qty': 1,
      'bottom_corner_qty': 1,
    },
    {'item_id': 3, 'role_key': 'frame_clamp_support'},
    {'item_id': 4, 'role_key': 'assembly_screw', 'assembly_target': 'sash'},
  ];

  @override
  Future<Database?> get db async => MemoryDatabase();

  /// Filters like the real query: by role and item when they are given.
  @override
  Future<List<Map<String, dynamic>>> getCatalogItemRules({
    String? itemTable,
    int? itemId,
    int? seriesId,
    Iterable<String> roleKeys = const [],
    bool exactSeriesOnly = false,
    bool includeInactive = false,
  }) async {
    final roles = roleKeys.map((role) => role.trim()).toSet();
    return [
      for (final rule in rules)
        if ((roles.isEmpty || roles.contains('${rule['role_key']}'.trim())) &&
            (itemId == null || rule['item_id'] == itemId))
          rule,
    ];
  }
}

class LegacyAssignedAccessoryDatabase implements Database {
  @override
  Future<void> execute(String sql, [List<Object?>? arguments]) async {}

  @override
  Future<List<Map<String, Object?>>> rawQuery(
    String sql, [
    List<Object?>? arguments,
  ]) async => [];

  @override
  Future<List<Map<String, Object?>>> query(
    String table, {
    bool? distinct,
    List<String>? columns,
    String? where,
    List<Object?>? whereArgs,
    String? groupBy,
    String? having,
    String? orderBy,
    int? limit,
    int? offset,
  }) async => table == 'Accessories'
      ? [
          {
            'id': 40,
            'name': 'Vis assemblage coulissant',
            'is_active': 1,
            'material_type': 'aluminium',
            // The product itself is assigned to the same series as its rule.
            // Accessory-page series selection is a hard compatibility filter.
            'series_id': 1,
            'price': 5,
          },
        ]
      : [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class SlidingAssemblyRuleDatabase extends SqlDatabase {
  @override
  Future<Database?> get db async => LegacyAssignedAccessoryDatabase();

  @override
  Future<List<Map<String, dynamic>>> getCatalogItemRules({
    String? itemTable,
    int? itemId,
    int? seriesId,
    Iterable<String> roleKeys = const [],
    bool exactSeriesOnly = false,
    bool includeInactive = false,
  }) async => [
    {
      'id': 400,
      'item_table': 'Accessories',
      'item_id': 40,
      'series_id': 1,
      'role_key': 'assembly_screw',
      'usage_scope': 'sliding',
      'assembly_target': 'sash',
      'assembly_section_ids': '12',
      'top_corner_qty': 1,
      'bottom_corner_qty': 1,
      'show_in_quantity': 1,
      'is_active': 1,
    },
  ];
}

class MixedAssemblyRuleDatabase extends SqlDatabase {
  @override
  Future<Database?> get db async => MemoryDatabase();

  @override
  Future<List<Map<String, dynamic>>> getCatalogItemRules({
    String? itemTable,
    int? itemId,
    int? seriesId,
    Iterable<String> roleKeys = const [],
    bool exactSeriesOnly = false,
    bool includeInactive = false,
  }) async => [
    {
      'id': seriesId == 2 ? 802 : 801,
      'item_table': 'Accessories',
      'item_id': seriesId == 2 ? 81 : 80,
      'series_id': seriesId,
      'role_key': 'assembly_screw',
      'assembly_target': 'sash',
      'assembly_section_ids': seriesId == 2 ? '30' : '20',
      'top_corner_qty': 1,
      'bottom_corner_qty': 1,
      'show_in_quantity': 1,
      'is_active': 1,
    },
  ];
}

class ProfileLinkedAssemblyRuleDatabase extends SqlDatabase {
  @override
  Future<Database?> get db async => MemoryDatabase();

  @override
  Future<List<Map<String, dynamic>>> getCatalogItemRules({
    String? itemTable,
    int? itemId,
    int? seriesId,
    Iterable<String> roleKeys = const [],
    bool exactSeriesOnly = false,
    bool includeInactive = false,
  }) async => [
    {
      'id': 410,
      'item_table': 'Accessories',
      'item_id': 41,
      'series_id': 1,
      'role_key': 'assembly_screw',
      'usage_scope': 'opening',
      // The generic target deliberately differs: the explicit profile link
      // must still make this rule apply to the selected plinthe/mullion.
      'assembly_target': 'sash',
      'assembly_section_ids': '30',
      'assembly_section_quantities': '30:2:2',
      'top_corner_qty': 1,
      'bottom_corner_qty': 1,
      'show_in_quantity': 1,
      'is_active': 1,
    },
  ];
}

class MultiAccessoryLinkDatabase extends SqlDatabase {
  @override
  Future<Database?> get db async => MemoryDatabase();

  @override
  Future<List<Map<String, dynamic>>> readAccessoryLinksWithDetails(
    int sourceAccessoryId,
  ) async => sourceAccessoryId == 80
      ? [
          {'target_role_key': 'gache_double', 'linked_quantity': 2},
          {'target_role_key': 'other', 'linked_quantity': 1},
        ]
      : sourceAccessoryId == 81
      ? [
          {'target_role_key': 'gache_double', 'linked_quantity': 3},
        ]
      : [];

  @override
  Future<List<Map<String, dynamic>>> getCatalogItemRules({
    String? itemTable,
    int? itemId,
    int? seriesId,
    Iterable<String> roleKeys = const [],
    bool exactSeriesOnly = false,
    bool includeInactive = false,
  }) async {
    final available = [
      {
        'id': 800,
        'item_id': 80,
        'series_id': 1,
        'role_key': 'espagnolette',
        'assembly_section_ids': '',
        'show_in_quantity': 1,
        'is_default': 1,
        'is_active': 1,
      },
      {
        'id': 900,
        'item_id': 90,
        'series_id': 1,
        'role_key': 'gache_double',
        'assembly_section_ids': '',
        'show_in_quantity': 1,
        'is_default': 1,
        'is_active': 1,
      },
      {
        'id': 910,
        'item_id': 91,
        'series_id': 1,
        'role_key': 'other',
        'assembly_section_ids': '999',
        'show_in_quantity': 1,
        'is_active': 1,
      },
    ];
    return available.where((rule) {
      if (itemId != null && rule['item_id'] != itemId) return false;
      return roleKeys.isEmpty || roleKeys.contains(rule['role_key']);
    }).toList();
  }
}

class AccessoryScrewOverrideDatabase extends SqlDatabase {
  @override
  Future<Database?> get db async => MemoryDatabase();

  @override
  Future<List<Map<String, dynamic>>> readAccessoryLinksWithDetails(
    int sourceAccessoryId,
  ) async => [
    // Deliberately stale: the selected accessory override below says 7.
    {'target_role_key': 'accessory_screw', 'linked_quantity': 3},
  ];

  @override
  Future<List<Map<String, dynamic>>> getCatalogItemRules({
    String? itemTable,
    int? itemId,
    int? seriesId,
    Iterable<String> roleKeys = const [],
    bool exactSeriesOnly = false,
    bool includeInactive = false,
  }) async => [
    {
      'item_id': 70,
      'series_id': 1,
      'role_key': 'accessory_screw',
      'show_in_quantity': 1,
      'is_active': 1,
    },
    // The hinge itself is published only through its own enabled rule.
    {
      'item_id': 51,
      'series_id': 1,
      'role_key': 'hinge',
      'show_in_quantity': 1,
      'is_active': 1,
    },
  ];
}

WindowModel makeWindow(SqlDatabase db) {
  final window = WindowModel(
    db: db,
    width: 1000,
    height: 1200,
    profileThickness: 50,
  );
  window.activeSeries = AluminumSeries(
    id: 1,
    profileId: 1,
    name: 'TP67',
    type: 'opening',
  );
  window.zones = [
    WindowZone(
      id: 'main',
      content: ZoneContent.doubleSash,
      boundary: const Rect.fromLTWH(50, 50, 900, 1100),
    ),
  ];
  return window;
}

void main() {
  test('espagnolette rules use effective height with or without shutter', () {
    final rule = {'min_height_mm': 800, 'max_height_mm': 1200};
    expect(
      catalogEspagnoletteRuleMatches(rule, effectiveHeightMm: 1000),
      isTrue,
    );
    expect(
      catalogEspagnoletteRuleMatches(rule, effectiveHeightMm: 700),
      isFalse,
    );
    expect(
      catalogEspagnoletteRuleMatches(rule, effectiveHeightMm: 1000),
      isTrue,
    );
  });

  test('espagnolette rules receive the actual sash height', () {
    final window = makeWindow(RuleDatabase());

    // The outer frame is 1200 mm high, while the sash zone is only 1100 mm.
    expect(window.openingSashHeightMm, 1100);
    expect(window.effectiveEspagnoletteHeightMm, 1100);

    // Adding a top fixed light makes the sash shorter. The espagnolette must
    // follow that sash, not the outer frame or the full window height.
    window.zones = [
      WindowZone(
        id: 'top-fixed',
        content: ZoneContent.fixedGlass,
        boundary: const Rect.fromLTWH(50, 50, 900, 300),
      ),
      WindowZone(
        id: 'lower-sash',
        content: ZoneContent.doubleSash,
        boundary: const Rect.fromLTWH(50, 350, 900, 800),
      ),
    ];
    expect(window.openingSashHeightMm, 800);
    expect(window.effectiveEspagnoletteHeightMm, 800);
  });

  test('renfort screws use endpoints and maximum 400 mm spacing', () {
    final window = makeWindow(RuleDatabase());
    window.activeSeries = AluminumSeries(
      id: 1,
      profileId: 1,
      name: 'PVC',
      type: 'pvc',
    );

    final screws = ComponentCalculator.generateBom(
      window,
      {},
    ).firstWhere((item) => item.originalName == 'براغي حديد الدعم');

    // Outer frame: 2 × (1000 mm => 4 screws) +
    // 2 × (1200 mm => 4 screws) = 16.
    // Two sashes: each 2 × (450 mm => 3) + 2 × (1100 mm => 4) = 14.
    expect(screws.quantity, 44);
  });

  test(
    'PVC double-sash strike has a positive default and uses configured count',
    () {
      final window = makeWindow(RuleDatabase());
      window.activeSeries = AluminumSeries(
        id: 1,
        profileId: 1,
        name: 'PVC',
        type: 'pvc',
      );
      final strike = ComponentCalculator.generateBom(
        window,
        {},
      ).firstWhere((item) => item.roleKey == 'gache_double');
      expect(strike.quantity, 1);
      window.componentOverrides['إسبانيوليت (Espagnolette)'] = {
        'gache_count': 3,
      };
      expect(
        ComponentCalculator.generateBom(
          window,
          {},
        ).firstWhere((item) => item.roleKey == 'gache_double').quantity,
        3,
      );
    },
  );
  test('aluminium strike follows the selected espagnolette link and count', () {
    final window = makeWindow(RuleDatabase())..hasBottomFrame = false;
    window.componentOverrides['إسبانيوليت (Espagnolette)'] = {
      'id': 20,
      'name': 'Espagnolette 1200',
      'price': 10.0,
      'linked_accessory_count': 2,
      'linked_accessory': {'id': 21, 'name': 'Gache liée', 'price': 4.0},
    };

    final bom = ComponentCalculator.generateBom(window, {});
    final espIndex = bom.indexWhere((item) => item.roleKey == 'espagnolette');
    final strikeIndex = bom.indexWhere(
      (item) => item.roleKey == 'gache_double',
    );
    expect(espIndex, greaterThanOrEqualTo(0));
    expect(strikeIndex, greaterThan(espIndex));
    expect(bom[strikeIndex].catalogItemId, 21);
    expect(bom[strikeIndex].quantity, 2);
    expect(
      bom[strikeIndex].overrideKey,
      startsWith('linked-accessory:'),
      reason:
          'An explicit Espagnolette relation must survive the final BOM rule filter.',
    );
  });
  test('sliding assembly screw follows its explicit series rule', () async {
    final db = SlidingAssemblyRuleDatabase();
    final window = WindowModel(
      db: db,
      width: 1000,
      height: 1200,
      profileThickness: 50,
    );
    final series = AluminumSeries(
      id: 1,
      profileId: 1,
      name: 'Coulissant test',
      type: 'sliding',
      sections: [
        AluminumSection(
          id: 11,
          seriesId: 1,
          code: 'D11',
          name: 'Dormant',
          type: 'frame',
          isFrame: true,
        ),
        AluminumSection(
          id: 12,
          seriesId: 1,
          code: 'O12',
          name: 'Ouvrant',
          type: 'sash',
          isSash: true,
        ),
      ],
    );
    window
      ..systemMode = 'sliding'
      ..activeSeries = series
      ..activeSlidingSeries = series
      ..zones = [
        WindowZone(
          id: 'sliding',
          content: ZoneContent.slidingSash,
          slidingSashesCount: 2,
          boundary: const Rect.fromLTWH(0, 0, 1000, 1200),
        ),
      ];

    final items = await BomEngineV2(
      database: db,
    ).filterItemsByAvailableCandidates(window: window, items: []);
    final screws = items.where((item) => item.roleKey == 'assembly_screw');
    expect(screws, hasLength(1));
    expect(screws.single.catalogItemId, 40);
    expect(screws.single.quantity, 8);
    expect(screws.single.unitPrice, 5);
  });
  test('mixed drawing counts opening and sliding assembly screws', () async {
    final db = MixedAssemblyRuleDatabase();
    final window =
        WindowModel(db: db, width: 2000, height: 1200, profileThickness: 50)
          ..systemMode = 'mixed'
          ..activeSeries = AluminumSeries(
            id: 1,
            profileId: 1,
            name: 'Opening',
            type: 'opening',
          )
          ..activeSlidingSeries = AluminumSeries(
            id: 2,
            profileId: 2,
            name: 'Sliding',
            type: 'sliding',
          )
          ..zones = [
            WindowZone(
              id: 'opening',
              content: ZoneContent.singleSash,
              boundary: const Rect.fromLTWH(0, 0, 1000, 1200),
            ),
            WindowZone(
              id: 'sliding',
              content: ZoneContent.slidingSash,
              slidingSashesCount: 2,
              boundary: const Rect.fromLTWH(1000, 0, 1000, 1200),
            ),
          ];
    final profiles = [
      BomItem(
        category: 'profile',
        originalName: 'Opening sash',
        name: 'Opening sash',
        quantity: 1,
        unit: 'متر',
        unitPrice: 1,
        catalogItemId: 20,
        selectorCategory: 'profile',
        selectorType: 'sash',
        roleKey: 'sash',
        sourceSeriesId: 1,
      ),
      BomItem(
        category: 'profile',
        originalName: 'Sliding sash',
        name: 'Sliding sash',
        quantity: 1,
        unit: 'متر',
        unitPrice: 1,
        catalogItemId: 30,
        selectorCategory: 'profile',
        selectorType: 'sash',
        roleKey: 'sash',
        sourceSeriesId: 2,
      ),
    ];

    final items = await BomEngineV2(
      database: db,
    ).filterItemsByAvailableCandidates(window: window, items: profiles);
    final quantities = {
      for (final item in items.where(
        (item) => item.roleKey == 'assembly_screw',
      ))
        item.catalogItemId: item.quantity,
    };
    expect(quantities, {80: 4, 81: 8});
  });
  test(
    'assembly screw follows selected plinthe or mullion profile pieces',
    () async {
      final db = ProfileLinkedAssemblyRuleDatabase();
      final window = makeWindow(db);
      final profiles = [
        BomItem(
          category: 'profile',
          originalName: 'بلانت (Plinthe)',
          name: 'Plinthe P30',
          quantity: 1,
          unit: 'متر',
          unitPrice: 10,
          pieces: const [0.8, 0.8],
          catalogItemId: 30,
          selectorCategory: 'profile',
          selectorType: 'plant',
          roleKey: 'plant',
          sourceSeriesId: 1,
          materialType: 'aluminium',
          overrideKey: 'linked-accessory:test-profile',
        ),
        // The drawing's sash row identifies the sash section (12), so the
        // rule linked to the plinthe section is not applied to its corners.
        BomItem(
          category: 'profile',
          originalName: 'الظلفة (Sash)',
          name: 'Sash S12',
          quantity: 1,
          unit: 'متر',
          unitPrice: 10,
          pieces: const [1.0, 1.0, 0.4, 0.4, 1.0, 1.0, 0.4, 0.4],
          catalogItemId: 12,
          selectorCategory: 'profile',
          selectorType: 'sash',
          roleKey: 'sash',
          sourceSeriesId: 1,
          materialType: 'aluminium',
          overrideKey: 'linked-accessory:test-sash',
        ),
      ];

      final items = await BomEngineV2(
        database: db,
      ).filterItemsByAvailableCandidates(window: window, items: profiles);
      final screws = items.where((item) => item.roleKey == 'assembly_screw');
      expect(screws, hasLength(1));
      expect(screws.single.catalogItemId, 41);
      expect(screws.single.quantity, 8);
    },
  );
  test('a generic accessory can add another linked accessory', () {
    final window = makeWindow(RuleDatabase())..hasBottomFrame = false;
    window.componentOverrides['المقبض (Handle)'] = {
      'id': 50,
      'name': 'Handle source',
      'price': 10.0,
      'linked_accessory_count': 2,
      'linked_accessory': {'id': 51, 'name': 'Accessory target', 'price': 3.0},
    };

    final linked = ComponentCalculator.generateBom(window, {}).where(
      (item) => item.overrideKey?.startsWith('linked-accessory:') == true,
    );
    expect(linked, hasLength(1));
    expect(linked.single.catalogItemId, 51);
    expect(linked.single.quantity, 2);
    expect(linked.single.unitPrice, 3);
  });
  test(
    'multiple accessory links aggregate and enforce section prerequisites',
    () async {
      final window = makeWindow(MultiAccessoryLinkDatabase());
      final sources = [
        BomItem(
          category: 'accessory',
          originalName: 'Espagnolette A',
          name: 'Espagnolette A',
          quantity: 2,
          unit: 'حبة',
          unitPrice: 1,
          catalogItemId: 80,
          kitGroupName: 'test-source-a',
        ),
        BomItem(
          category: 'accessory',
          originalName: 'Espagnolette B',
          name: 'Espagnolette B',
          quantity: 1,
          unit: 'حبة',
          unitPrice: 1,
          catalogItemId: 81,
          kitGroupName: 'test-source-b',
        ),
      ];

      final bom = await BomEngineV2(
        database: MultiAccessoryLinkDatabase(),
      ).filterItemsByAvailableCandidates(window: window, items: sources);
      final linked = bom.where(
        (item) => item.overrideKey?.startsWith('linked-accessory:') == true,
      );

      expect(linked, hasLength(1));
      expect(linked.single.catalogItemId, 90);
      expect(linked.single.quantity, 7); // (2 × 2) + (3 × 1)
      expect(bom.any((item) => item.catalogItemId == 91), isFalse);
    },
  );
  test(
    'duplicate espagnolette and role-linked strike appear only once',
    () async {
      final window = makeWindow(MultiAccessoryLinkDatabase());
      final duplicated = [
        for (var i = 0; i < 2; i++)
          BomItem(
            category: 'accessory',
            originalName: 'Espagnolette',
            name: 'Espagnolette',
            quantity: 1,
            unit: 'حبة',
            unitPrice: 1,
            catalogItemId: 80,
            selectorCategory: 'accessory',
            selectorType: 'espagnolette',
            roleKey: 'espagnolette',
            sourceSeriesId: 1,
            materialType: 'aluminium',
          ),
      ];

      final bom = await BomEngineV2(
        database: MultiAccessoryLinkDatabase(),
      ).filterItemsByAvailableCandidates(window: window, items: duplicated);

      expect(bom.where((item) => item.roleKey == 'espagnolette'), hasLength(1));
      expect(bom.where((item) => item.roleKey == 'gache_double'), hasLength(1));
      expect(
        bom.singleWhere((item) => item.roleKey == 'gache_double').quantity,
        2,
      );
    },
  );
  test('accessory screws are grouped by screw product and kept separate', () {
    final window = makeWindow(RuleDatabase());
    final screwA = {'id': 70, 'name': 'Vis 4x20', 'price': 2.0};
    final screwB = {'id': 71, 'name': 'Vis 4x30', 'price': 3.0};
    window.componentOverrides['كريمون (Cremone)'] = {
      'id': 50,
      'name': 'Cremone',
      'price': 10.0,
      'screw_count': 2,
      'screw_accessory': screwA,
    };
    window.componentOverrides['المفاصل (Hinges)'] = {
      'id': 51,
      'name': 'Hinges',
      'price': 10.0,
      'screw_count': 4,
      'screw_accessory': screwA,
    };
    window.componentOverrides['قاش دوبل (Gache Double Ouvrant)'] = {
      'id': 52,
      'name': 'Gache Double',
      'price': 10.0,
      'screw_count': 3,
      'screw_accessory': screwB,
    };

    final bom = ComponentCalculator.generateBom(window, {});
    final sourceItems = bom.where(
      (item) => const {
        'كريمون (Cremone)',
        'المفاصل (Hinges)',
        'قاش دوبل (Gache Double Ouvrant)',
      }.contains(item.originalName),
    );
    final expectedA = sourceItems
        .where(
          (item) =>
              item.originalName == 'كريمون (Cremone)' ||
              item.originalName == 'المفاصل (Hinges)',
        )
        .fold<double>(0, (sum, item) {
          final count = item.originalName == 'كريمون (Cremone)' ? 2 : 4;
          return sum + count * item.quantity;
        });
    final expectedB = sourceItems
        .where((item) => item.originalName == 'قاش دوبل (Gache Double Ouvrant)')
        .fold<double>(0, (sum, item) => sum + 3 * item.quantity);
    final screws = bom
        .where(
          (item) =>
              item.overrideKey?.startsWith('linked-accessory:screw:') == true,
        )
        .toList();

    expect(
      screws,
      hasLength(2),
      reason: sourceItems
          .map((item) => '${item.originalName}:${item.quantity}')
          .join(', '),
    );
    expect(
      screws.every((item) => item.originalName == 'براغي الإكسسوارات'),
      isTrue,
    );
    expect(
      {for (final item in screws) item.catalogItemId: item.quantity},
      {70: expectedA, 71: expectedB},
    );
    expect(screws.firstWhere((item) => item.catalogItemId == 70).unitPrice, 2);
    expect(screws.firstWhere((item) => item.catalogItemId == 71).unitPrice, 3);
  });
  test('selected hinge screw count overrides a stale relation', () async {
    final database = AccessoryScrewOverrideDatabase();
    final window = makeWindow(database);
    window.componentOverrides['المفاصل (Hinges)'] = {
      'id': 51,
      'name': 'Paumelles',
      'screw_count': 7,
      'screw_accessory': {'id': 70, 'name': 'Vis 4x20'},
    };

    Future<double> screwQuantity(double hingeQuantity) async {
      final result = await BomEngineV2(database: database)
          .filterItemsByAvailableCandidates(
            window: window,
            items: [
              BomItem(
                category: 'accessory',
                originalName: 'المفاصل (Hinges)',
                name: 'Paumelles',
                quantity: hingeQuantity,
                unit: 'حبة',
                unitPrice: 10,
                catalogItemId: 51,
                inventoryItemType: 'Accessory',
                overrideKey: 'linked-accessory:parent:51',
                roleKey: 'hinge',
                sourceSeriesId: 1,
              ),
            ],
          );
      return result
          .singleWhere((item) => item.roleKey == 'accessory_screw')
          .quantity;
    }

    expect(await screwQuantity(6), 42);
    expect(await screwQuantity(8), 56);
    expect(await screwQuantity(8) - await screwQuantity(6), 14);
  });
  test('same physical screw stays separated by its BOM usage', () async {
    final database = RuleDatabase()..rules.clear();
    final window = makeWindow(database);
    final result = await BomEngineV2(database: database)
        .filterItemsByAvailableCandidates(
          window: window,
          items: [
            BomItem(
              category: 'accessory',
              originalName: 'براغي الكيت',
              name: '3.5x0.9',
              quantity: 8,
              unit: 'حبة',
              unitPrice: 1,
              catalogItemId: 70,
              inventoryItemType: 'Accessory',
              roleKey: 'kit_screw',
              selectorType: 'is_kit_screw',
              sourceSeriesId: 1,
            ),
            BomItem(
              category: 'accessory',
              originalName: 'براغي الصندوق',
              name: '3.5x0.9',
              quantity: 10,
              unit: 'حبة',
              unitPrice: 1,
              catalogItemId: 70,
              inventoryItemType: 'Accessory',
              roleKey: 'box_screw',
              selectorType: 'is_caisson_screw',
              sourceSeriesId: 1,
            ),
          ],
        );

    expect(result, hasLength(2));
    expect(
      {for (final item in result) item.roleKey: item.quantity},
      {'kit_screw': 8, 'box_screw': 10},
    );
    expect(result.every((item) => item.cuttingList == null), isTrue);
  });
  test('a series kit does not expand a stale linked accessory', () {
    final window = makeWindow(RuleDatabase())..hasBottomFrame = false;
    window
      ..systemMode = 'sliding'
      ..activeSlidingSeries = window.activeSeries
      ..zones = [
        WindowZone(
          id: 'sliding',
          content: ZoneContent.slidingSash,
          boundary: const Rect.fromLTWH(0, 0, 1000, 1200),
        ),
      ];
    window.componentOverrides['كيت 67000 (Kit 67000)'] = {
      'id': 60,
      'name': 'Kit 67000',
      'price': 10.0,
      'linked_accessory_count': 1,
      'linked_accessory': {'id': 61, 'name': 'Ekar opening', 'price': 3.0},
    };

    final bom = ComponentCalculator.generateBom(window, {});
    final linkedFromKit = bom.where(
      (item) => item.overrideKey?.startsWith('linked-accessory:60:') == true,
    );

    expect(linkedFromKit, isEmpty);
  });
  test(
    'two different clamps and a support accumulate; sash uses screws',
    () async {
      final db = RuleDatabase();
      final window = makeWindow(db)..hasBottomFrame = false;
      final items = await BomEngineV2(
        database: db,
      ).filterItemsByAvailableCandidates(window: window, items: []);
      expect(
        {for (final item in items) item.catalogItemId: item.quantity},
        {1: 4, 2: 2, 3: 2, 4: 8},
      );
      expect(items.first.unitPrice, 10);
      window.hasBottomFrame = true;
      window.quantity = 2;
      final full = await BomEngineV2(
        database: db,
      ).filterItemsByAvailableCandidates(window: window, items: []);
      expect(
        {for (final item in full) item.catalogItemId: item.quantity},
        {1: 16, 2: 8, 3: 8, 4: 16},
      );
    },
  );
  test('profile binding and independent upper/lower corner quantities', () {
    const demands = [
      AssemblyDemand(
        target: 'frame',
        sliding: false,
        topCorners: 2,
        bottomCorners: 2,
        sectionId: 10,
      ),
    ];
    expect(
      assemblyQuantity({
        'role_key': 'frame_clamp',
        'assembly_section_id': 11,
      }, demands),
      0,
    );
    expect(
      assemblyQuantity({
        'role_key': 'frame_clamp',
        'assembly_section_id': 10,
        'top_corner_qty': 2,
        'bottom_corner_qty': 0,
      }, demands),
      4,
    );
  });

  test('generic clam supports multiple linked profiles and closed corners', () {
    expect(
      catalogRuleKeysForAccessorySelectorType('Clam'),
      containsAll(<String>['clam', 'clamp', 'sliding_clamp']),
    );
    const demands = [
      AssemblyDemand(
        target: 'sash',
        sliding: false,
        topCorners: 2,
        bottomCorners: 2,
        sectionId: 10,
      ),
      AssemblyDemand(
        target: 'sash',
        sliding: true,
        topCorners: 4,
        bottomCorners: 4,
        sectionId: 12,
      ),
      AssemblyDemand(
        target: 'sash',
        sliding: false,
        topCorners: 8,
        bottomCorners: 8,
        sectionId: 99,
      ),
    ];

    expect(
      assemblyQuantity({
        'role_key': 'clam',
        'assembly_target': 'sash',
        'assembly_section_ids': '10,12',
        'top_corner_qty': 1,
        'bottom_corner_qty': 1,
      }, demands),
      12,
    );

    const frameWithoutBottom = [
      AssemblyDemand(
        target: 'frame',
        sliding: false,
        topCorners: 2,
        bottomCorners: 0,
        sectionId: 10,
      ),
    ];
    expect(
      assemblyQuantity({
        'role_key': 'clam',
        'assembly_target': 'frame',
        'assembly_section_ids': '10',
        'top_corner_qty': 1,
        'bottom_corner_qty': 1,
      }, frameWithoutBottom),
      2,
    );
    expect(
      assemblyQuantity({
        'role_key': 'clam',
        'assembly_target': 'frame',
        'assembly_section_ids': '10',
        'top_corner_qty': 2,
        'bottom_corner_qty': 2,
      }, frameWithoutBottom),
      4,
    );
  });
  test(
    'opening frame and leaves count every corner despite legacy zero bottom',
    () {
      for (final sashCount in [0, 1, 2]) {
        final demands = [
          const AssemblyDemand(
            target: 'frame',
            sliding: false,
            topCorners: 2,
            bottomCorners: 2,
            sectionId: 10,
          ),
          if (sashCount > 0)
            AssemblyDemand(
              target: 'sash',
              sliding: false,
              topCorners: sashCount * 2,
              bottomCorners: sashCount * 2,
              sectionId: 20,
            ),
        ];
        expect(
          assemblyQuantity({
            'role_key': 'clam',
            'assembly_section_quantities': '10:1:0,20:1:0',
          }, demands),
          4 * (sashCount + 1),
        );
      }
      expect(
        assemblyQuantity(
          {'role_key': 'clam', 'assembly_section_quantities': '10:1:0'},
          const [
            AssemblyDemand(
              target: 'frame',
              sliding: false,
              topCorners: 2,
              bottomCorners: 0,
              sectionId: 10,
            ),
          ],
        ),
        2,
      );
    },
  );

  test('one clamp per corner gives 12 for one frame and two sashes', () {
    const demands = [
      AssemblyDemand(
        target: 'frame',
        sliding: false,
        topCorners: 2,
        bottomCorners: 2,
        sectionId: 10,
      ),
      AssemblyDemand(
        target: 'sash',
        sliding: false,
        topCorners: 4,
        bottomCorners: 4,
        sectionId: 20,
      ),
    ];

    expect(
      assemblyQuantity({
        'role_key': 'clam',
        'assembly_section_ids': '10,20',
        // The second legacy side must not halve a per-corner clamp rule.
        'assembly_section_quantities': '10:1:0,20:1:0',
      }, demands),
      12,
    );
  });
  test(
    'quantity-only rule resolves for BOM but not replacement dialog',
    () async {
      final resolver = CatalogCandidateResolver(database: RuleDatabase());
      final quantity = await resolver.resolve(
        const CatalogCandidateQuery(
          category: 'accessory',
          selectorType: 'frame_clamp',
          seriesId: 1,
          materialType: 'aluminium',
          requireDialog: false,
        ),
      );
      final dialog = await resolver.resolve(
        const CatalogCandidateQuery(
          category: 'accessory',
          selectorType: 'frame_clamp',
          seriesId: 1,
          materialType: 'aluminium',
        ),
      );
      expect(quantity.map((r) => r['id']), [1, 2]);
      expect(dialog.map((r) => r['id']), [2]);
    },
  );
  test(
    'simple glass never invents reducer demand without a configured role',
    () {
      final window = makeWindow(RuleDatabase());
      window.zones.first.glass = const GlassSpecification(
        structure: GlassStructure.simple,
      );
      final bom = ComponentCalculator.generateBom(window, {});
      expect(bom.where((r) => r.roleKey == 'reducer'), isEmpty);
      window.zones.first.glass = const GlassSpecification(
        structure: GlassStructure.double,
      );
      expect(
        ComponentCalculator.generateBom(
          window,
          {},
        ).where((r) => r.roleKey == 'reducer'),
        isEmpty,
      );
    },
  );
  test('mixed glazing never invents reducer without a configured role', () {
    final window = makeWindow(RuleDatabase());
    window.zones = [
      WindowZone(
        id: 'simple',
        boundary: const Rect.fromLTWH(0, 0, 500, 1000),
        glass: const GlassSpecification(structure: GlassStructure.simple),
      ),
      WindowZone(
        id: 'double',
        boundary: const Rect.fromLTWH(500, 0, 500, 1000),
        glass: const GlassSpecification(structure: GlassStructure.double),
      ),
    ];

    final reducers = ComponentCalculator.generateBom(
      window,
      {},
    ).where((row) => row.roleKey == 'reducer');

    expect(reducers, isEmpty);
  });
}
