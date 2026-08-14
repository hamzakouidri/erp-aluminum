import 'package:database_data/Commande/Systeme/calculate_component.dart';
import 'package:database_data/Commande/Systeme/model.dart';
import 'package:database_data/Commande/order_required_goods_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('required goods order data', () {
    test('database rows are materialized with stable dynamic map types', () {
      final sqliteRows = <Map<String, Object?>>[
        <String, Object?>{'id': 1, 'name': 'Lame 55'},
      ];
      final lazyRows = sqliteRows.map((row) => row);

      final normalized = normalizeDatabaseRows(lazyRows);

      expect(normalized, hasLength(1));
      expect(normalized.single['id'], 1);
      expect(normalized, isA<List<Map<String, dynamic>>>());
    });

    test('only an explicit replacement flag excludes a product', () {
      expect(isExplicitlyReplacedProduct(false, null), isFalse);
      expect(isExplicitlyReplacedProduct(false, false), isFalse);
      expect(isExplicitlyReplacedProduct(false, 'false'), isFalse);
      expect(isExplicitlyReplacedProduct(false, true), isTrue);
      expect(isExplicitlyReplacedProduct(false, '1'), isTrue);
      expect(isExplicitlyReplacedProduct(true, null), isTrue);
    });

    test('instances accept saved numeric and string values', () {
      final instances = parseRequiredGoodsInstances(
        '[{"width":"1200","height":1400.0,"qty":"2"}]',
      );

      expect(instances, hasLength(1));
      expect(instances.single['width'], '1200');
      expect(instances.single['height'], 1400.0);
      expect(instances.single['qty'], '2');
      expect(parseRequiredGoodsInstances('{"qty":1}'), isEmpty);
      expect(parseRequiredGoodsInstances('not-json'), isEmpty);
    });

    test('catalogue identity drives the four inventory classifications', () {
      BomItem item(String category, String inventoryType) => BomItem(
        category: category,
        originalName: 'item',
        name: 'item',
        quantity: 1,
        unit: 'قطعة',
        unitPrice: 0,
        inventoryItemType: inventoryType,
      );

      expect(requiredGoodsCategoryForBom(item('other', 'Section')), 'profile');
      expect(
        requiredGoodsCategoryForBom(item('accessory', 'ShutterComponent')),
        'shutter',
      );
      expect(requiredGoodsCategoryForBom(item('other', 'Joints')), 'joint');
      expect(
        requiredGoodsCategoryForBom(item('other', 'Accessory')),
        'accessory',
      );
    });

    test('order cutting reuses leftovers across separate products', () {
      // Individually these two products need four 6 m bars:
      // product A = 3.0 + 3.0, product B = 2.8 + 2.8.
      // Together each 3.0 m cut shares one bar with a 2.8 m cut.
      final plan = optimizeRequiredGoodsCutting(
        pieces: [3.0, 3.0, 2.8, 2.8],
        stockLength: 6.0,
      );

      expect(plan.barCount, 2);
      expect(plan.bars.every((bar) => bar.length == 2), isTrue);
      expect(plan.wasteLength, closeTo(0.384, 0.0001));
    });

    test('cutting includes the configured saw kerf', () {
      final fitsExactly = optimizeRequiredGoodsCutting(
        pieces: [2.996, 2.996],
        stockLength: 6.0,
      );
      final exceedsByKerf = optimizeRequiredGoodsCutting(
        pieces: [3.0, 2.996],
        stockLength: 6.0,
      );

      expect(fitsExactly.barCount, 1);
      expect(exceedsByKerf.barCount, 2);
    });

    test('matching remnants are consumed before new full bars', () {
      final plan = optimizeCuttingWithRemnants(
        pieces: const [3.0, 2.0, 1.0],
        remnants: const [
          AvailableRemnantPiece(id: 10, length: 2.01),
          AvailableRemnantPiece(id: 11, length: 1.01),
        ],
        stockLength: 6.0,
      );

      expect(plan.remnantUsages, hasLength(2));
      expect(
        plan.remnantUsages.expand((usage) => usage.cuts),
        containsAll(<double>[2.0, 1.0]),
      );
      expect(plan.fullBarPlan.barCount, 1);
      expect(plan.fullBarPlan.bars.single, <double>[3.0]);
    });

    test('a stored remainder smaller than cut plus kerf is not reused', () {
      final plan = optimizeCuttingWithRemnants(
        pieces: const [1.0],
        remnants: const [AvailableRemnantPiece(id: 10, length: 1.003)],
        stockLength: 6.0,
      );

      expect(plan.remnantUsages, isEmpty);
      expect(plan.fullBarPlan.barCount, 1);
    });

    test('only stock-bar BOM rows enter order-level cutting', () {
      BomItem item({required String unit, List<double>? pieces}) => BomItem(
        category: 'profile',
        originalName: 'Frame',
        name: 'Frame',
        length: 6,
        pieces: pieces,
        quantity: 1,
        unit: unit,
        unitPrice: 100,
      );

      expect(
        bomUsesOrderLevelCutting(item(unit: 'قطاع', pieces: [1.2])),
        isTrue,
      );
      expect(
        bomUsesOrderLevelCutting(item(unit: 'متر', pieces: [1.2])),
        isFalse,
      );
      expect(bomUsesOrderLevelCutting(item(unit: 'قطاع')), isFalse);
    });

    test('cutting groups stay separated by item, colour and stock length', () {
      BomItem item({required int colorId, required double length}) => BomItem(
        category: 'profile',
        originalName: 'Frame',
        name: 'Frame',
        length: length,
        pieces: const [1.2],
        quantity: 1,
        unit: 'قطاع',
        unitPrice: 100,
        catalogItemId: 8,
        inventoryItemType: 'Section',
        colorId: colorId,
      );

      final base = requiredGoodsAggregationKey(
        item(colorId: 1, length: 6),
        'profile',
      );
      expect(
        requiredGoodsAggregationKey(item(colorId: 1, length: 6), 'profile'),
        base,
      );
      expect(
        requiredGoodsAggregationKey(item(colorId: 2, length: 6), 'profile'),
        isNot(base),
      );
      expect(
        requiredGoodsAggregationKey(item(colorId: 1, length: 5.8), 'profile'),
        isNot(base),
      );
    });
  });
}
