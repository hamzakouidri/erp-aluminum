import 'package:database_data/Commande/Systeme/calculate_component.dart';
import 'package:database_data/Commande/order_required_goods_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Order Required Goods - Glass & Categorization Tests', () {
    test('glass BomItems aggregate with exact cut dimensions and piece count', () {
      final glassItem1 = BomItem(
        category: 'glass',
        originalName: 'الزجاج',
        name: 'Double Vitrage 4/12/4',
        length: 850.0,
        glassHeight: 1240.0,
        pieceCount: 2,
        quantity: 2.108,
        unit: 'م²',
        unitPrice: 3500.0,
      );

      final glassItem2 = BomItem(
        category: 'glass',
        originalName: 'الزجاج',
        name: 'Double Vitrage 4/12/4',
        length: 850.0,
        glassHeight: 1240.0,
        pieceCount: 3,
        quantity: 3.162,
        unit: 'م²',
        unitPrice: 3500.0,
      );

      final key1 = requiredGoodsAggregationKey(glassItem1, 'glass');
      final key2 = requiredGoodsAggregationKey(glassItem2, 'glass');

      // Both should have identical aggregation key because length (850) and height (1240) match
      expect(key1, equals(key2));

      final agg = AggregatedGoodItem(
        name: glassItem1.name,
        originalName: glassItem1.originalName,
        category: 'glass',
        unit: glassItem1.unit,
        unitPrice: glassItem1.unitPrice,
        totalQuantity: glassItem1.quantity,
        totalCost: glassItem1.quantity * glassItem1.unitPrice,
        stockLength: glassItem1.length,
        glassHeight: glassItem1.glassHeight,
        pieceCount: glassItem1.pieceCount ?? 1,
      );

      agg.mergeWith(glassItem2, glassItem2.quantity, glassItem2.quantity * glassItem2.unitPrice, false);

      // Verify merged totals
      expect(agg.pieceCount, equals(5));
      expect(agg.stockLength, equals(850.0));
      expect(agg.glassHeight, equals(1240.0));
      expect(agg.totalQuantity, closeTo(5.27, 0.01));
    });

    test('different glass cut sizes produce separate aggregation rows', () {
      final glassA = BomItem(
        category: 'glass',
        originalName: 'الزجاج',
        name: 'Double Vitrage 4/12/4',
        length: 850.0,
        glassHeight: 1240.0,
        pieceCount: 2,
        quantity: 2.108,
        unit: 'م²',
        unitPrice: 3500.0,
      );

      final glassB = BomItem(
        category: 'glass',
        originalName: 'الزجاج',
        name: 'Double Vitrage 4/12/4',
        length: 900.0,
        glassHeight: 1240.0,
        pieceCount: 2,
        quantity: 2.232,
        unit: 'م²',
        unitPrice: 3500.0,
      );

      final keyA = requiredGoodsAggregationKey(glassA, 'glass');
      final keyB = requiredGoodsAggregationKey(glassB, 'glass');

      expect(keyA, isNot(equals(keyB)));
    });
  });
}
