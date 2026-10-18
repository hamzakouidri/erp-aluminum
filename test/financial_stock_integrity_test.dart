import 'dart:io';

import 'package:database_data/sql_database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_sqlcipher/sqflite.dart' show Database;

class _TemporaryPaths extends PathProviderPlatform {
  _TemporaryPaths(this.path);
  final String path;

  @override
  Future<String?> getApplicationSupportPath() async => path;
}

Future<(SqlDatabase, Database)> _openTestDatabase(String prefix) async {
  final directory = await Directory.systemTemp.createTemp(prefix);
  final originalPaths = PathProviderPlatform.instance;
  PathProviderPlatform.instance = _TemporaryPaths(directory.path);
  SharedPreferences.setMockInitialValues({});
  SqlDatabase.resetDb();
  final sqlDb = SqlDatabase();
  final connection = await sqlDb.initDb();
  addTearDown(() async {
    await connection.close();
    SqlDatabase.resetDb();
    PathProviderPlatform.instance = originalPaths;
    await directory.delete(recursive: true);
  });
  return (sqlDb, connection);
}

Future<int> _insertSale(Database connection, {double paid = 0.0}) {
  final now = DateTime.now().toUtc().toIso8601String();
  return connection.insert('MaterialSales', {
    'sale_code': 'BL-TEST',
    'client_name': 'Shop client',
    'doc_type': 'bon_livraison',
    'status': 'draft',
    'net_total': 100.0,
    'paid_amount': paid,
    'remaining_amount': 100.0 - paid,
    'location_id': 1,
    'sale_date': now,
    'created_at': now,
    'updated_at': now,
  });
}

Future<double> _stock(Database connection, int itemId) async {
  final rows = await connection.query(
    'CurrentStock',
    where: "item_id = ? AND item_type = 'Accessories' AND location_id = 1",
    whereArgs: [itemId],
  );
  return rows.isEmpty ? 0.0 : (rows.first['quantity'] as num).toDouble();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('shop receipts never pay window orders', () async {
    final (sqlDb, connection) = await _openTestDatabase('erp_shop_receipt_');
    final now = DateTime.now().toUtc().toIso8601String();
    final clientId = await connection.insert('Client', {
      'firstname': 'Shop',
      'lastname': 'Client',
      'created_at': now,
      'updated_at': now,
    });
    final orderId = await connection.insert('Commandes', {
      'order_code': 301,
      'client_id': clientId,
      'status': 'Nouveau',
      'total': 100.0,
      'net_payable': 100.0,
      'advance_payment': 0.0,
      'payment_status': 'Unpaid',
      'created_at': now,
      'updated_at': now,
    });
    final saleId = await _insertSale(connection);

    await sqlDb.recordMaterialSalePaidIncrease(
      saleId: saleId,
      previousPaid: 0.0,
      newPaid: 60.0,
      saleCode: 'BL-TEST',
      clientId: clientId,
    );

    final order = (await connection.query(
      'Commandes',
      where: 'id = ?',
      whereArgs: [orderId],
    )).single;
    expect(order['advance_payment'], 0.0);
    expect(order['payment_status'], 'Unpaid');
    expect(await sqlDb.materialSaleReceiptsTotal(saleId), 60.0);

    // Deleting the receipt removes it from the shop document as well.
    await connection.update(
      'MaterialSales',
      {'paid_amount': 60.0, 'remaining_amount': 40.0},
      where: 'id = ?',
      whereArgs: [saleId],
    );
    final receipt = (await connection.query(
      'Treasury',
      where: 'reference_id = ?',
      whereArgs: [saleId],
    )).single;
    await sqlDb.deleteTreasury(receipt['id'] as int);
    final sale = (await connection.query(
      'MaterialSales',
      where: 'id = ?',
      whereArgs: [saleId],
    )).single;
    expect(sale['paid_amount'], 0.0);
    expect(sale['remaining_amount'], 100.0);
  });

  test('posted shop document stock follows its edited lines', () async {
    final (sqlDb, connection) = await _openTestDatabase('erp_shop_stock_');
    final accessoryId = await connection.insert('Accessories', {
      'name': 'Handle',
      'type': 'Poignée',
      'price': 100.0,
    });
    await sqlDb.updateInventory(
      itemId: accessoryId,
      itemType: 'Accessories',
      locationId: 1,
      quantityChange: 20,
      transactionType: 'Adjustment',
    );
    final saleId = await _insertSale(connection);
    final lineId = await connection.insert('MaterialSaleItems', {
      'sale_id': saleId,
      'item_type': 'Accessories',
      'item_id': accessoryId,
      'item_name': 'Handle',
      'quantity': 10.0,
    });

    await sqlDb.deductStockForMaterialSale(saleId, locationId: 1);
    expect(await _stock(connection, accessoryId), 10.0);

    // The line is reduced after posting: only the difference comes back,
    // even if a different warehouse is passed.
    await connection.update(
      'MaterialSaleItems',
      {'quantity': 4.0},
      where: 'id = ?',
      whereArgs: [lineId],
    );
    await sqlDb.deductStockForMaterialSale(saleId, locationId: 2);
    expect(await _stock(connection, accessoryId), 16.0);

    // Duplicate lines are summed before checking the availability.
    final secondSale = await _insertSale(connection);
    for (var i = 0; i < 2; i++) {
      await connection.insert('MaterialSaleItems', {
        'sale_id': secondSale,
        'item_type': 'Accessories',
        'item_id': accessoryId,
        'item_name': 'Handle',
        'quantity': 9.0,
      });
    }
    await expectLater(
      sqlDb.deductStockForMaterialSale(secondSale, locationId: 1),
      throwsStateError,
    );
    expect(await _stock(connection, accessoryId), 16.0);
  });

  test('purchase price becomes the weighted average cost', () async {
    final (sqlDb, connection) = await _openTestDatabase('erp_purchase_cost_');
    final accessoryId = await connection.insert('Accessories', {
      'name': 'Hinge',
      'type': 'Paumelle',
      'price': 0.0,
    });

    // No stock: the new purchase price is taken directly.
    await sqlDb.updateInventory(
      itemId: accessoryId,
      itemType: 'Accessories',
      locationId: 1,
      quantityChange: 10,
      transactionType: 'Purchase',
      unitPrice: 1000,
    );
    // Stock of 10 at 1000, then 10 more at 1100 → 1050.
    await sqlDb.updateInventory(
      itemId: accessoryId,
      itemType: 'Accessories',
      locationId: 1,
      quantityChange: 10,
      transactionType: 'Purchase',
      unitPrice: 1100,
    );
    final accessory = (await connection.query(
      'Accessories',
      where: 'id = ?',
      whereArgs: [accessoryId],
    )).single;
    expect(accessory['price'], 1050.0);
    final override = (await connection.query(
      'WorkshopPriceOverrides',
      where: "table_name = 'Accessories' AND row_key = ?",
      whereArgs: ['$accessoryId'],
    )).single;
    expect(override['price'], 1050.0);
    expect(override['source'], 'purchase');
  });

  test('a purchase invoice is purged only from the trash', () async {
    final (sqlDb, connection) = await _openTestDatabase('erp_purchase_purge_');
    final achatId = await sqlDb.insertAchat('ACH-0001', 'Supplier', 0.0);

    await expectLater(sqlDb.deleteAchat(achatId), throwsStateError);

    await sqlDb.deleteAchatToTrash(achatId);
    expect(await sqlDb.deleteAchat(achatId), 1);
    expect(
      await connection.query('Achats', where: 'id = ?', whereArgs: [achatId]),
      isEmpty,
    );
    expect(await sqlDb.getNextAchatInvoiceNumber(), 'ACH-0001');
  });
}
