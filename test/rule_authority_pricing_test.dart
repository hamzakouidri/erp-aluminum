import 'package:database_data/Commande/Systeme/bom_engine_v2.dart';
import 'package:database_data/Commande/Systeme/calculate_component.dart';
import 'package:database_data/Commande/Systeme/model.dart';
import 'package:database_data/sql_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

import 'accessory_assembly_rules_test.dart' show MemoryDatabase, makeWindow;

/// Series 2 has one enabled frame rule (section 20). Section 10 belongs to
/// series 1. Colour 7 costs 2000/m, every other colour 1000/m.
class _SeriesRuleDb extends SqlDatabase {
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
  }) async => [];

  @override
  Future<List<Map<String, dynamic>>> getDesignSectionsForRoles(
    int seriesId,
    Iterable<String> roleKeys, {
    bool requireDialog = true,
    bool requireQuantity = false,
    bool requireVisible = true,
  }) async => roleKeys.contains('frame') && seriesId == 2
      ? [
          {
            ..._frameB.toMap(),
            'material_type': 'aluminium',
            'design_role_key': 'frame',
          },
        ]
      : [];

  @override
  Future<List<Map<String, dynamic>>> getDesignSectionsForScopedDialogRoles(
    int seriesId,
    Iterable<String> roleKeys, {
    required String usageScope,
    bool requireDialog = true,
    bool requireQuantity = false,
    bool requireVisible = true,
  }) => getDesignSectionsForRoles(seriesId, roleKeys);

  @override
  Future<double> getSectionPrice(dynamic nameOrId, [int? colorId]) async =>
      colorId == 7 ? 2000.0 : 1000.0;
}

final _frameB = AluminumSection(
  id: 20,
  seriesId: 2,
  code: 'B-F',
  name: 'Frame B',
  type: 'frame',
  isFrame: true,
  visibleWidth: 60,
);

WindowModel _seriesBWindow(SqlDatabase db) {
  final model = WindowModel(db: db, width: 1000, height: 1000);
  model.activeSeries = AluminumSeries(
    id: 2,
    profileId: 1,
    name: 'B',
    type: 'Aluminium',
    sections: [_frameB],
  );
  model.frameOverride = {
    ..._frameB.toMap(),
    'design_role_key': 'frame',
    'calculated_price': 1000.0,
  };
  model.zones = [
    WindowZone(id: 'z1', boundary: const Rect.fromLTWH(0, 0, 1000, 1000)),
  ];
  return model;
}

/// The exact sequence used by the quantity/cost table, the cutting sheet,
/// the required goods and the order repricing.
Future<List<BomItem>> _materialTable(WindowModel model, SqlDatabase db) async {
  final engine = BomEngineV2(database: db);
  await engine.stabilizeSelections(
    window: model,
    items: ComponentCalculator.generateBom(model, const {}),
  );
  await engine.stabilizeSelections(
    window: model,
    items: ComponentCalculator.generateBom(model, const {}),
  );
  return engine.filterItemsByAvailableCandidates(
    window: model,
    items: ComponentCalculator.generateBom(model, const {}),
  );
}

BomItem _frameRow(List<BomItem> items) =>
    items.singleWhere((item) => item.roleKey == 'frame');

/// Hinge 51 links 7 screws of product 70. [rules] mimics CatalogItemRules
/// with the real active/series filtering of getCatalogItemRules.
class _ScrewRuleDb extends SqlDatabase {
  _ScrewRuleDb(List<Map<String, dynamic>> rules)
    : rules = [
        ...rules,
        // The hinge itself is enabled in series 1.
        {
          'item_id': 51,
          'series_id': 1,
          'role_key': 'hinge',
          'show_in_quantity': 1,
          'is_active': 1,
        },
      ];

  final List<Map<String, dynamic>> rules;

  @override
  Future<Database?> get db async => MemoryDatabase();

  @override
  Future<List<Map<String, dynamic>>> readAccessoryLinksWithDetails(
    int sourceAccessoryId,
  ) async => [];

  @override
  Future<List<Map<String, dynamic>>> getCatalogItemRules({
    String? itemTable,
    int? itemId,
    int? seriesId,
    Iterable<String> roleKeys = const [],
    bool exactSeriesOnly = false,
    bool includeInactive = false,
  }) async => rules
      .where(
        (rule) =>
            (includeInactive || rule['is_active'] != 0) &&
            (seriesId == null || rule['series_id'] == seriesId) &&
            (roleKeys.isEmpty || roleKeys.contains(rule['role_key'])),
      )
      .toList();
}

Future<List<BomItem>> _hingeScrews(_ScrewRuleDb db) async {
  final window = makeWindow(db);
  window.componentOverrides['المفاصل (Hinges)'] = {
    'id': 51,
    'name': 'Paumelles',
    'screw_count': 7,
    'screw_accessory': {'id': 70, 'name': 'Vis 4x20'},
  };
  final result = await BomEngineV2(database: db).filterItemsByAvailableCandidates(
    window: window,
    items: [
      BomItem(
        category: 'accessory',
        originalName: 'المفاصل (Hinges)',
        name: 'Paumelles',
        quantity: 2,
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
  return result.where((item) => item.roleKey == 'accessory_screw').toList();
}

Map<String, dynamic> _screwRule(int itemId, {int seriesId = 1, int active = 1}) => {
  'item_id': itemId,
  'series_id': seriesId,
  'role_key': 'accessory_screw',
  'show_in_quantity': 1,
  'is_active': active,
};

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('a table row saved for another series frame is not reused', () async {
    final db = _SeriesRuleDb();
    final model = _seriesBWindow(db);
    // Manual price edit made while the order used series 1.
    model.componentOverrides['الإطار (Frame)'] = {
      'id': 10,
      'series_id': 1,
      'code': 'A-F',
      'name': 'Frame A',
      'price': 500.0,
      'calculated_price': 500.0,
    };

    final frame = _frameRow(await _materialTable(model, db));

    expect(frame.catalogItemId, 20);
    expect(frame.profileCode, 'B-F');
    expect(frame.unitPrice, 1000.0);
    model.dispose();
  });

  test('a manual price for the same section is still honoured', () {
    final model = _seriesBWindow(_SeriesRuleDb());
    model.componentOverrides['الإطار (Frame)'] = {
      'id': 20,
      'price': 1500.0,
      'calculated_price': 1500.0,
    };

    final frame = _frameRow(ComponentCalculator.generateBom(model, const {}));

    expect(frame.catalogItemId, 20);
    expect(frame.unitPrice, 1500.0);
    model.dispose();
  });

  test('changing the colour reprices the selected frame', () async {
    final db = _SeriesRuleDb();
    final model = _seriesBWindow(db);

    model.selectedDbColor = {'id': 7, 'name': 'Gris'};
    await model.refreshSectionPricesForSelectedColor(notify: false);
    final frame = _frameRow(await _materialTable(model, db));

    expect(frame.unitPrice, 2000.0);
    model.dispose();
  });

  test('bulk colour change prices like a line drawn in that colour', () async {
    final db = _SeriesRuleDb();
    final changed = _seriesBWindow(db);
    changed.selectedDbColor = {'id': 7, 'name': 'Gris'};
    await changed.refreshSectionPricesForSelectedColor(notify: false);

    final fresh = WindowModel(db: db, width: 1000, height: 1000)
      ..activeSeries = changed.activeSeries
      ..zones = [
        WindowZone(id: 'z1', boundary: const Rect.fromLTWH(0, 0, 1000, 1000)),
      ];
    fresh.selectedDbColor = {'id': 7, 'name': 'Gris'};
    await fresh.refreshSectionPricesForSelectedColor(notify: false);

    final changedTotal = (await _materialTable(changed, db))
        .fold<double>(0, (sum, item) => sum + item.total);
    final freshTotal = (await _materialTable(fresh, db))
        .fold<double>(0, (sum, item) => sum + item.total);

    expect(_frameRow(await _materialTable(fresh, db)).unitPrice, 2000.0);
    expect(changedTotal, closeTo(freshTotal, 1e-6));
    changed.dispose();
    fresh.dispose();
  });

  test('a frame from another series does not pass its price on', () async {
    final db = _SeriesRuleDb();
    final model = _seriesBWindow(db);
    // Left over from series 1: not an enabled frame rule of series 2.
    model.frameOverride = {
      'id': 10,
      'series_id': 1,
      'code': 'A-F',
      'name': 'Frame A',
      'type': 'frame',
      'calculated_price': 500.0,
    };

    final frame = _frameRow(await _materialTable(model, db));

    expect(frame.catalogItemId, 20);
    expect(frame.unitPrice, 1000.0);
    model.dispose();
  });

  test('saved-row matching keeps legacy price-only rows', () {
    expect(savedProfileOverrideMatchesSection({'price': 5}, {'id': 3}), isTrue);
    expect(savedProfileOverrideMatchesSection({'id': 3}, null), isTrue);
    expect(savedProfileOverrideMatchesSection({'id': '3'}, {'id': 3}), isTrue);
    expect(savedProfileOverrideMatchesSection({'id': 4}, {'id': 3}), isFalse);
  });

  test('an accessory screw with an enabled rule in the series is shown', () async {
    final screws = await _hingeScrews(_ScrewRuleDb([_screwRule(70)]));
    expect(screws.single.catalogItemId, 70);
    expect(screws.single.quantity, 14);
  });

  test('a linked screw whose own rule is disabled is not shown', () async {
    final screws = await _hingeScrews(
      _ScrewRuleDb([_screwRule(70, active: 0), _screwRule(71)]),
    );
    expect(screws.map((item) => item.catalogItemId), isNot(contains(70)));
  });

  test('a screw enabled only in another series is not shown', () async {
    final screws = await _hingeScrews(
      _ScrewRuleDb([_screwRule(70, seriesId: 2), _screwRule(71)]),
    );
    expect(screws.map((item) => item.catalogItemId), isNot(contains(70)));
  });

  test('a profile row is kept only for an enabled section of its role', () async {
    final db = _SeriesRuleDb();
    final model = _seriesBWindow(db);
    BomItem frameRow(int id) => BomItem(
      category: 'profile',
      originalName: 'الإطار (Frame)',
      name: 'Frame',
      quantity: 1,
      unit: 'قطاع',
      unitPrice: 1000,
      pieces: const [1000, 1000, 1000, 1000],
      catalogItemId: id,
      selectorCategory: 'profile',
      selectorType: 'frame',
      roleKey: 'frame',
      sourceSeriesId: 2,
    );

    final kept = await BomEngineV2(database: db).filterItemsByAvailableCandidates(
      window: model,
      items: [frameRow(10), frameRow(20)],
    );

    final ids = kept
        .where((item) => item.category == 'profile')
        .map((item) => item.catalogItemId);
    expect(ids, [20]);
    model.dispose();
  });

  Future<List<int?>> linkedRows(List<Map<String, dynamic>> rules) async {
    final db = _ScrewRuleDb(rules);
    final window = makeWindow(db);
    final kept = await BomEngineV2(database: db).filterItemsByAvailableCandidates(
      window: window,
      items: [
        BomItem(
          category: 'accessory',
          originalName: 'أكسسوار مرتبط: Gâche',
          name: 'Gâche',
          quantity: 2,
          unit: 'حبة',
          unitPrice: 10,
          catalogItemId: 80,
          inventoryItemType: 'Accessory',
          overrideKey: 'linked-accessory:51:80',
          selectorCategory: 'accessory',
          roleKey: 'gache_simple',
          sourceSeriesId: 1,
        ),
      ],
    );
    return kept
        .where((item) => (item.overrideKey ?? '').startsWith('linked-accessory:51'))
        .map((item) => item.catalogItemId)
        .toList();
  }

  Map<String, dynamic> gacheRule({int seriesId = 1, int active = 1}) => {
    'item_id': 80,
    'series_id': seriesId,
    'role_key': 'gache_simple',
    'show_in_quantity': 1,
    'is_active': active,
  };

  test('a linked accessory with an enabled rule in the series is shown', () async {
    expect(await linkedRows([gacheRule()]), [80]);
  });

  test('a linked accessory without an enabled rule is not shown', () async {
    expect(await linkedRows([]), isEmpty);
    expect(await linkedRows([gacheRule(active: 0)]), isEmpty);
    expect(await linkedRows([gacheRule(seriesId: 2)]), isEmpty);
  });
}
