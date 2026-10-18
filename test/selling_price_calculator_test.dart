import 'package:database_data/Commande/Systeme/calculate_component.dart';
import 'package:database_data/Commande/Systeme/model.dart';
import 'package:database_data/Commande/Systeme/selling_price_calculator.dart';
import 'package:database_data/settings/app_settings.dart';
import 'package:database_data/sql_database.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('linear meter pricing follows the configured profile multiplier', () {
    final model = WindowModel(db: SqlDatabase(), width: 1000, height: 1000);
    final totals = calculateSellingTotals(
      model: model,
      items: [
        BomItem(
          category: 'profile',
          originalName: 'Frame',
          name: 'Frame',
          quantity: 1,
          unit: 'm',
          unitPrice: 100,
          pieces: const [2],
          catalogItemId: 5,
          roleKey: 'frame',
        ),
      ],
      costMethod: CostMethod.linearMeter,
      profitMargin: 0,
      pricePerSqm: 0,
      linearMeterPrice: 1000,
      shutterSqmPrice: 5000,
      profileRules: {
        5: {'calculation_mode': 'linear_meter', 'linear_meter_multiplier': 1.5},
      },
    );
    expect(totals['total']!['selling'], 3000);
    model.dispose();
  });

  test('square meter price has no shutter charge without shutter items', () {
    final model = WindowModel(db: SqlDatabase(), width: 1000, height: 1000);
    final totals = calculateSellingTotals(
      model: model,
      items: const [],
      costMethod: CostMethod.squareMeter,
      profitMargin: 0,
      pricePerSqm: 1000,
      linearMeterPrice: 0,
      shutterSqmPrice: 5000,
    );
    expect(totals['total']!['selling'], 1000);
    model.dispose();
  });

  test('moustiquaire add-on is priced by window area and quantity', () {
    final model = WindowModel(db: SqlDatabase(), width: 1200, height: 1500)
      ..quantity = 2
      ..hasMoustiquaireAddon = true;
    final totals = calculateSellingTotals(
      model: model,
      items: const [],
      costMethod: CostMethod.linearMeter,
      profitMargin: 0,
      pricePerSqm: 0,
      linearMeterPrice: 0,
      shutterSqmPrice: 0,
      moustiquaireSqmPrice: 2500,
    );

    // Screen cut 2 mm smaller: 1.198 × 1.498 × 2 = 3.589 → 3.59 m², the same
    // rounded area as the quantity-table row.
    expect(totals['moustiquaire']!['selling'], closeTo(3.59 * 2500, 1e-6));
    expect(totals['total']!['selling'], closeTo(3.59 * 2500, 1e-6));
    model.dispose();
  });

  test('moustiquaire selling matches its quantity-table row', () {
    final model = WindowModel(db: SqlDatabase(), width: 1234, height: 1567)
      ..quantity = 3
      ..hasMoustiquaireAddon = true
      ..componentOverrides['moustiquaire'] = {'price_per_sqm': 2500.0};
    final row = ComponentCalculator.generateBom(model, const {})
        .singleWhere((item) => item.category == 'moustiquaire');
    final totals = calculateSellingTotals(
      model: model,
      items: [row],
      costMethod: CostMethod.percentage,
      profitMargin: 0,
      pricePerSqm: 0,
      linearMeterPrice: 0,
      shutterSqmPrice: 0,
      moustiquaireSqmPrice: 2500,
    );
    expect(totals['moustiquaire']!['cost'], closeTo(row.total, 1e-6));
    expect(totals['moustiquaire']!['selling'], closeTo(row.total, 1e-6));
    model.dispose();
  });
}
