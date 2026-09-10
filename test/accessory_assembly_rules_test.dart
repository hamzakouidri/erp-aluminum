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
  }) async => rules;
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
