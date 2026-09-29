import 'package:database_data/Commande/Systeme/calculate_component.dart';
import 'package:database_data/Commande/Systeme/model.dart';
import 'package:database_data/Commande/Systeme/model_serialization.dart';
import 'package:database_data/Commande/order_required_goods_screen.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:database_data/sql_database.dart';

void main() {
  test('accessories sharing the same catalogItemId aggregate to identical key without duplication', () {
    final handleAr = BomItem(
      category: 'accessory',
      originalName: 'المقبض (Handle)',
      name: 'المقبض (Handle)\nPoignée Fenêtre',
      quantity: 2,
      unit: 'قطعة',
      unitPrice: 150,
      catalogItemId: 99,
      inventoryItemType: 'Accessory',
    );
    final handleFr = BomItem(
      category: 'accessory',
      originalName: 'Poignée Fenêtre',
      name: 'Poignée Fenêtre',
      quantity: 1,
      unit: 'قطعة',
      unitPrice: 150,
      catalogItemId: 99,
      inventoryItemType: 'Accessory',
    );

    final key1 = requiredGoodsAggregationKey(handleAr, 'accessory');
    final key2 = requiredGoodsAggregationKey(handleFr, 'accessory');
    expect(key1, equals(key2));
  });

  test('AggregatedGoodItem.mergeWith clears isMissing and updates name when merging with catalogue item', () {
    final agg = AggregatedGoodItem(
      name: 'المقبض (Handle)',
      originalName: 'المقبض (Handle)',
      category: 'accessory',
      unit: 'قطعة',
      unitPrice: 0.0,
      totalQuantity: 2.0,
      totalCost: 0.0,
      isMissing: true,
    );

    final linkedBom = BomItem(
      category: 'accessory',
      originalName: 'المقبض (Handle)',
      name: 'المقبض (Handle)\nPoignée Fenêtre Standard',
      quantity: 2,
      unit: 'قطعة',
      unitPrice: 250.0,
      isMissing: false,
      catalogItemId: 55,
      inventoryItemType: 'Accessory',
    );

    agg.mergeWith(linkedBom, 2.0, 500.0, false);
    expect(agg.isMissing, isFalse);
    expect(agg.catalogItemId, equals(55));
    expect(agg.unitPrice, equals(250.0));
    expect(agg.totalCost, equals(500.0));
    expect(agg.totalQuantity, equals(4.0));
    expect(agg.name, contains('Poignée Fenêtre'));
  });

  test('applyWindowModelFromMap populates sliding series correctly for sliding systemMode', () {
    final model = WindowModel(db: SqlDatabase());
    final map = {
      'systemMode': 'sliding',
      'seriesId': 105,
      'seriesName': 'TPR 67000',
      'componentOverrides': {
        'المقبض (Handle)': {'id': 99, 'name': 'Poignée TPR'},
      },
    };

    applyWindowModelFromMap(model, map);
    expect(model.loadedSeriesId, equals(105));
    expect(model.loadedSlidingSeriesId, equals(105));
    expect(model.loadedSlidingSeriesName, equals('TPR 67000'));
    expect(model.componentOverrides.containsKey('المقبض (Handle)'), isTrue);
  });
}
