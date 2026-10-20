import 'package:database_data/Commande/Systeme/calculate_component.dart';
import 'package:database_data/Commande/Systeme/installation_fees.dart';
import 'package:database_data/Commande/Systeme/model.dart';
import 'package:database_data/Commande/Systeme/model_serialization.dart';
import 'package:database_data/Commande/Systeme/selling_price_calculator.dart';
import 'package:database_data/Commande/devis_builder.dart';
import 'package:database_data/services/price_sync_service.dart';
import 'package:database_data/settings/app_settings.dart';
import 'package:database_data/sql_database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

BomItem _accessory({
  required int id,
  required String name,
  double quantity = 2,
  double unitPrice = 100,
  String? kit,
}) => BomItem(
  category: 'accessory',
  originalName: name,
  name: name,
  quantity: quantity,
  unit: 'حبة',
  unitPrice: unitPrice,
  catalogItemId: id,
  inventoryItemType: 'Accessory',
  overrideKey: name,
  kitGroupName: kit,
);

void main() {
  test('installation is its own total, without margin, apart from parts', () {
    final model = WindowModel(db: SqlDatabase(), width: 1000, height: 1000)
      ..quantity = 2
      ..shutterMechanism = 'مانيفال'
      ..componentOverrides['Handle'] = {'is_selling_calculated': 1};
    final items = [
      _accessory(id: 7, name: 'Handle', kit: 'Kit Ouvrant'),
      BomItem(
        category: 'shutter',
        originalName: 'Lames',
        name: 'Lame 39',
        quantity: 2,
        unit: 'm²',
        unitPrice: 0,
        catalogItemId: 3,
        inventoryItemType: 'ShutterComponent',
      ),
    ];
    final fees = InstallationFees(
      prices: {
        InstallationFees.accessoryKey(7): 50,
        InstallationFees.kitKey(4): 300,
        InstallationFees.shutterKey: 1000,
        InstallationFees.crankKey: 400,
        // Not charged: the shutter works with a crank, not a motor.
        InstallationFees.motorKey: 2000,
      },
      kitIdsByName: const {'Kit Ouvrant': 4},
    );

    final lines = fees.linesFor(model, items);
    expect({for (final l in lines) l.key: l.total}, {
      InstallationFees.shutterKey: 2000.0,
      InstallationFees.crankKey: 800.0,
      InstallationFees.kitKey(4): 600.0,
      InstallationFees.accessoryKey(7): 100.0,
    });

    final totals = calculateSellingTotals(
      model: model,
      items: items,
      costMethod: CostMethod.percentage,
      profitMargin: 50,
      pricePerSqm: 0,
      linearMeterPrice: 0,
      shutterSqmPrice: 0,
      installationFees: fees,
    );
    // Parts get the margin (200 × 1.5); installation is added as it is.
    expect(totals['accessory']!['selling'], 300);
    expect(totals['installation']!['selling'], 3500);
    expect(totals['installation']!['cost'], 0);
    expect(totals['total']!['selling'], 3800);
    model.dispose();
  });

  test('the workshop switch turns every installation fee off', () {
    final model = WindowModel(db: SqlDatabase(), width: 1000, height: 1000);
    final items = [_accessory(id: 7, name: 'Handle')];
    final fees = InstallationFees(
      enabled: false,
      prices: {InstallationFees.accessoryKey(7): 50},
    );
    expect(fees.linesFor(model, items), isEmpty);
    final totals = calculateSellingTotals(
      model: model,
      items: items,
      costMethod: CostMethod.percentage,
      profitMargin: 0,
      pricePerSqm: 0,
      linearMeterPrice: 0,
      shutterSqmPrice: 0,
      installationFees: fees,
    );
    expect(totals['installation']!['selling'], 0);
    model.dispose();
  });

  test('fees are read from the colour-0 installation rows only', () async {
    sqfliteFfiInit();
    final connection = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
    );
    addTearDown(connection.close);
    await connection.execute(
      'CREATE TABLE ShutterSqmPrices (id INTEGER PRIMARY KEY, '
      'blade_type TEXT, color_id INTEGER, price_per_sqm REAL)',
    );
    await connection.execute(
      'CREATE TABLE KitBundles (id INTEGER PRIMARY KEY, name TEXT, '
      'is_active INTEGER)',
    );
    for (final row in [
      {'blade_type': 'Install_acc_7', 'color_id': 0, 'price_per_sqm': 50},
      {'blade_type': 'Moteur_Install', 'color_id': 0, 'price_per_sqm': 2000},
      // `_` must not act as a LIKE wildcard.
      {'blade_type': 'Installx', 'color_id': 0, 'price_per_sqm': 9},
      {'blade_type': 'Install_acc_8', 'color_id': 3, 'price_per_sqm': 9},
      {'blade_type': 'Lame 39', 'color_id': 0, 'price_per_sqm': 4000},
    ]) {
      await connection.insert('ShutterSqmPrices', row);
    }
    await connection.insert('KitBundles', {
      'id': 4,
      'name': 'Kit Ouvrant',
      'is_active': 1,
    });
    await connection.insert('KitBundles', {
      'id': 5,
      'name': 'Old kit',
      'is_active': 0,
    });
    SharedPreferences.setMockInitialValues({
      InstallationFees.enabledPreference: false,
    });

    final fees = await InstallationFees.load(connection);
    expect(fees.enabled, isFalse);
    expect(fees.prices, {'Install_acc_7': 50.0, 'Moteur_Install': 2000.0});
    expect(fees.kitIdsByName, {'Kit Ouvrant': 4});
  });

  test('installation prices are their own shared-price category', () {
    PriceTableSpec only(String category) =>
        PriceSyncService.priceTables[category]!.single;
    final installation = only('installation');
    final shutterSqm = only('shutter_sqm');
    final mosquito = only('moustiquaire');
    for (final key in [
      'Install_acc_7',
      'Install_shutter',
      'Moteur_Install',
      'Manivelle',
      'OB_Install',
    ]) {
      final row = {'blade_type': key};
      expect(installation.accepts(row), isTrue, reason: key);
      expect(shutterSqm.accepts(row), isFalse, reason: key);
      expect(mosquito.accepts(row), isFalse, reason: key);
    }
    expect(installation.accepts({'blade_type': 'Lame 39'}), isFalse);
    expect(shutterSqm.accepts({'blade_type': 'Lame 39'}), isTrue);
    expect(shutterSqm.accepts({'blade_type': 'Moustiquaire_Sqm'}), isFalse);
    expect(PriceTableSpec.escapeLike('Install_'), 'Install!_');
  });

  test('the SQL filter of a category matches its row filter', () async {
    sqfliteFfiInit();
    final connection = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
    );
    addTearDown(connection.close);
    await connection.execute(
      'CREATE TABLE ShutterSqmPrices (blade_type TEXT, color_id INTEGER)',
    );
    for (final key in [
      'Lame 39',
      'Installx',
      'Install_kit_4',
      'Manivelle',
      'Moustiquaire_Sqm',
    ]) {
      await connection.insert('ShutterSqmPrices', {
        'blade_type': key,
        'color_id': 0,
      });
    }
    Future<Set<String>> keys(String category) async {
      final spec = PriceSyncService.priceTables[category]!.single;
      return {
        for (final row in await connection.query(
          'ShutterSqmPrices',
          where: spec.whereClause,
          whereArgs: spec.whereArgs,
        ))
          row['blade_type'] as String,
      };
    }

    expect(await keys('installation'), {'Install_kit_4', 'Manivelle'});
    expect(await keys('shutter_sqm'), {'Lame 39', 'Installx'});
    expect(await keys('moustiquaire'), {'Moustiquaire_Sqm'});
  });

  test('a quote shows the installation included in a window price', () {
    final line = DevisBuilder.buildLineItemFromDetail({
      'id': 1,
      'window_type': 'coulissant',
      'largeur': 1200,
      'hauteur': 1400,
      'quantity': 1,
      'price': 10000,
      'partitions_json': {'hasShutter': false, 'installationFeePerUnit': 1500},
    }, overrideLang: AppLanguage.arabic);
    expect(line.unitPrice, 10000);
    expect(line.details.last, 'منها أجور التركيب: 1500 دج');

    final withoutFee = DevisBuilder.buildLineItemFromDetail({
      'id': 2,
      'window_type': 'coulissant',
      'largeur': 1200,
      'hauteur': 1400,
      'quantity': 1,
      'price': 10000,
      'partitions_json': {'hasShutter': false},
    }, overrideLang: AppLanguage.arabic);
    expect(
      withoutFee.details.any((d) => d.contains('أجور التركيب')),
      isFalse,
    );
  });

  test('the per-unit installation fee survives saving the drawing', () {
    final model = WindowModel(db: SqlDatabase(), width: 1000, height: 1000)
      ..installationFeePerUnit = 1750;
    final restored = WindowModel(db: SqlDatabase(), width: 1, height: 1);
    applyWindowModelFromMap(restored, model.toMap());
    expect(restored.installationFeePerUnit, 1750);
    model.dispose();
    restored.dispose();
  });
}
