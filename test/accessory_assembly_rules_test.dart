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

  @override
  Future<List<Map<String, dynamic>>> getCatalogItemRules({
    String? itemTable,
    int? itemId,
    int? seriesId,
    Iterable<String> roleKeys = const [],
    bool exactSeriesOnly = false,
    bool includeInactive = false,
  }) async => rules;
}

class LegacyAssignedAccessoryDatabase implements Database {
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
            // Legacy catalogue assignment; the explicit rule below is
            // the authoritative assignment to series 1.
            'series_id': 999,
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
    'opening simple glass produces reducer demand without drawing role cache',
    () {
      final window = makeWindow(RuleDatabase());
      window.zones.first.glass = const GlassSpecification(
        structure: GlassStructure.simple,
      );
      final bom = ComponentCalculator.generateBom(window, {});
      expect(bom.where((r) => r.roleKey == 'reducer'), isNotEmpty);
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
  test('mixed glazing keeps reducer pieces for simple-glass cells', () {
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

    expect(reducers, isNotEmpty);
    expect(reducers.single.pieces, isNotEmpty);
  });
}
