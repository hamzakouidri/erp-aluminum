import 'package:database_data/sql_database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _CardDatabase extends SqlDatabase {
  _CardDatabase(this.connection);

  final Database connection;

  @override
  Future<Database?> get db async => connection;
}

const _itemId = 7;
const _itemType = 'Section';
const _colorId = 2;
const _store = 1;
const _workshop = 2;

Future<_CardDatabase> _open() async {
  sqfliteFfiInit();
  // Schema checks are cached per process; every test opens a new database.
  SqlDatabase.resetDb();
  SharedPreferences.setMockInitialValues({'user_display_name': 'أحمد'});
  final connection = await databaseFactoryFfi.openDatabase(
    inMemoryDatabasePath,
  );
  addTearDown(connection.close);
  Future<void> run(String sql) => connection.execute(sql);
  await run('''
    CREATE TABLE CurrentStock (
      id INTEGER PRIMARY KEY, item_id INTEGER NOT NULL,
      item_type TEXT NOT NULL, color_id INTEGER,
      location_id INTEGER NOT NULL, quantity REAL NOT NULL DEFAULT 0.0,
      updated_at TEXT
    )
  ''');
  await run('''
    CREATE TABLE InventoryTransactions (
      id INTEGER PRIMARY KEY, item_id INTEGER NOT NULL,
      item_type TEXT NOT NULL, color_id INTEGER,
      location_id INTEGER NOT NULL, transaction_type TEXT NOT NULL,
      quantity REAL NOT NULL, reference_id INTEGER, note TEXT,
      created_at TEXT
    )
  ''');
  await run('''
    CREATE TABLE _sync_runtime_flags (
      id INTEGER PRIMARY KEY, suppress_tombstones INTEGER NOT NULL DEFAULT 0
    )
  ''');
  await connection.insert('_sync_runtime_flags', {'id': 1});
  await run('''
    CREATE TABLE Locations (
      id INTEGER PRIMARY KEY, name TEXT, is_workshop INTEGER DEFAULT 0
    )
  ''');
  await run('CREATE TABLE Suppliers (id INTEGER PRIMARY KEY, name TEXT)');
  await run('''
    CREATE TABLE SectionColorPrices (
      id INTEGER PRIMARY KEY, section_id INTEGER NOT NULL,
      color_id INTEGER NOT NULL, price REAL NOT NULL DEFAULT 0.0,
      UNIQUE(section_id, color_id)
    )
  ''');
  await run('''
    CREATE TABLE Client (
      id INTEGER PRIMARY KEY, firstname TEXT, lastname TEXT
    )
  ''');
  await run('''
    CREATE TABLE Commandes (
      id INTEGER PRIMARY KEY, client_id INTEGER, order_code INTEGER
    )
  ''');
  await run('''
    CREATE TABLE Achats (
      id INTEGER PRIMARY KEY, invoice_number TEXT, supplier_id INTEGER,
      supplier_name TEXT, status TEXT, location_id INTEGER, total REAL,
      paid_amount REAL, remaining_amount REAL, activity_type TEXT,
      is_workshop INTEGER, is_internal INTEGER, linked_sale_id INTEGER,
      created_at TEXT, updated_at TEXT, updated_by TEXT
    )
  ''');
  await run('''
    CREATE TABLE Achat_items (
      id INTEGER PRIMARY KEY, achat_id INTEGER NOT NULL, item_code TEXT,
      item_name TEXT, item_type TEXT, item_id INTEGER, color_id INTEGER,
      quantity REAL NOT NULL, price REAL NOT NULL, total_price REAL,
      received_quantity REAL, created_at TEXT
    )
  ''');
  for (final table in const [
    'Colors',
    'Series',
    'Sections',
    'ShutterComponents',
    'Accessories',
    'Joints',
    'Glass',
  ]) {
    await run('CREATE TABLE $table (id INTEGER PRIMARY KEY, name TEXT)');
  }
  await connection.insert('Locations', {'id': _store, 'name': 'مستودع المحل'});
  await connection.insert('Locations', {
    'id': _workshop,
    'name': 'مستودع الورشة',
    'is_workshop': 1,
  });
  await connection.insert('Suppliers', {'id': 3, 'name': 'مورد الألمنيوم'});
  await connection.insert('Client', {
    'id': 4,
    'firstname': 'زبون',
    'lastname': 'الطلبية',
  });
  await connection.insert('Client', {
    'id': 5,
    'firstname': 'زبون',
    'lastname': 'البيع',
  });
  await connection.insert('Commandes', {
    'id': 80,
    'client_id': 4,
    'order_code': 2026080,
  });
  final database = _CardDatabase(connection);
  // Creates the remnant, sales and reservation tables.
  await database.readStockAvailability(itemId: _itemId, itemType: _itemType);
  return database;
}

Future<int> _insertSale(
  _CardDatabase database, {
  required int id,
  required String code,
  int? clientId,
  required double quantity,
  int isInternal = 0,
}) async {
  for (final column in const [
    'is_internal INTEGER DEFAULT 0',
    'linked_achat_id INTEGER',
    'dest_location_id INTEGER',
  ]) {
    try {
      await database.connection.execute(
        'ALTER TABLE MaterialSales ADD COLUMN $column',
      );
    } catch (_) {}
  }
  await database.connection.insert('MaterialSales', {
    'id': id,
    'sale_code': code,
    'client_id': clientId,
    'location_id': _store,
    'is_internal': isInternal,
    'sale_date': '2026-10-18',
    'created_at': '2026-10-18',
    'updated_at': '2026-10-18',
  });
  await database.connection.insert('MaterialSaleItems', {
    'sale_id': id,
    'item_type': _itemType,
    'item_id': _itemId,
    'item_code': 'F-7',
    'item_name': 'Frame',
    'color_id': _colorId,
    'quantity': quantity,
    'unit_price': 900.0,
  });
  return id;
}

void main() {
  test('the card follows a bar from the supplier to its customers', () async {
    final database = await _open();
    final connection = database.connection;

    // Purchase 100 bars into the store.
    await connection.insert('Achats', {
      'id': 45,
      'invoice_number': 'ACH-45',
      'supplier_id': 3,
      'status': 'Pending',
      'location_id': _store,
    });
    await connection.insert('Achat_items', {
      'achat_id': 45,
      'item_type': _itemType,
      'item_id': _itemId,
      'color_id': _colorId,
      'quantity': 100.0,
      'price': 800.0,
    });
    await database.receiveAchatStock(45);

    // Move 20 to the workshop.
    await _insertSale(
      database,
      id: 12,
      code: 'INT-12',
      quantity: 20,
      isInternal: 1,
    );
    await database.executeInternalMaterialSaleTransfer(
      saleId: 12,
      destLocationId: _workshop,
    );

    // Issue 12 to order 80 from the workshop.
    await database.applyOrderInventoryIssue(
      orderId: 80,
      remnantIds: const [],
      stockDeductions: const [
        {
          'item_id': _itemId,
          'item_type': _itemType,
          'color_id': _colorId,
          'location_id': _workshop,
          'quantity': 12.0,
        },
      ],
    );

    // Sell 5 from the store.
    await _insertSale(
      database,
      id: 91,
      code: 'MAT-91',
      clientId: 5,
      quantity: 5,
    );
    await database.deductStockForMaterialSale(91, locationId: _store);

    final card = await database.readProductMovementCard(
      itemId: _itemId,
      itemType: _itemType,
      colorId: _colorId,
    );
    final movements = card['movements'] as List<Map<String, dynamic>>;
    expect(movements, hasLength(4));

    final purchase = movements[0];
    expect(purchase['movement_type'], SqlDatabase.movementPurchaseReceipt);
    expect(purchase['to_location_name'], 'مستودع المحل');
    expect(purchase['supplier_name'], 'مورد الألمنيوم');
    expect(purchase['doc_code'], 'ACH-45');
    expect(purchase['quantity'], 100);
    expect(purchase['performed_by'], 'أحمد');
    expect(purchase['running_balance'], 100);

    final transfer = movements[1];
    expect(transfer['is_transfer'], isTrue);
    expect(transfer['from_location_name'], 'مستودع المحل');
    expect(transfer['to_location_name'], 'مستودع الورشة');
    expect(transfer['transfer_quantity'], 20);
    expect(transfer['out_document_code'], 'INT-12');
    expect(transfer['in_document_type'], 'purchase');
    expect(transfer['running_balance'], 100);

    final issue = movements[2];
    expect(issue['movement_type'], SqlDatabase.movementProductionIssue);
    expect(issue['from_location_name'], 'مستودع الورشة');
    expect(issue['client_name'], 'زبون الطلبية');
    expect(issue['order_code'], 2026080);
    expect(issue['balance_before'], 20);
    expect(issue['balance_after'], 8);
    expect(issue['running_balance'], 88);

    final sale = movements[3];
    expect(sale['movement_type'], SqlDatabase.movementSaleIssue);
    expect(sale['client_name'], 'زبون البيع');
    expect(sale['doc_code'], 'MAT-91');
    expect(sale['running_balance'], 83);

    final balances = card['balances'] as List<Map<String, dynamic>>;
    expect(
      {for (final row in balances) row['location_id']: row['quantity']},
      {_store: 75.0, _workshop: 8.0},
    );
    expect(card['average_cost'], 800);
    expect((card['last_purchase'] as Map)['supplier_name'], 'مورد الألمنيوم');
  });

  test('a posted movement cannot be edited', () async {
    final database = await _open();
    await database.updateInventory(
      itemId: _itemId,
      itemType: _itemType,
      colorId: _colorId,
      locationId: _store,
      quantityChange: 5,
      transactionType: 'Adjustment',
    );
    await expectLater(
      database.connection.update('InventoryTransactions', {'quantity': 50}),
      throwsA(isA<DatabaseException>()),
    );
  });

  test('a cancelled sale is reversed by a linked movement', () async {
    final database = await _open();
    await database.updateInventory(
      itemId: _itemId,
      itemType: _itemType,
      colorId: _colorId,
      locationId: _store,
      quantityChange: 10,
      transactionType: 'Adjustment',
    );
    await _insertSale(
      database,
      id: 91,
      code: 'MAT-91',
      clientId: 5,
      quantity: 4,
    );
    await database.deductStockForMaterialSale(91, locationId: _store);
    await database.deleteMaterialSale(91);

    final card = await database.readProductMovementCard(
      itemId: _itemId,
      itemType: _itemType,
      colorId: _colorId,
    );
    final movements = card['movements'] as List<Map<String, dynamic>>;
    final sale = movements.firstWhere(
      (row) => row['transaction_type'] == 'Material Sale',
    );
    final reversal = movements.last;
    expect(reversal['movement_type'], SqlDatabase.movementReturn);
    expect(reversal['reverses_transaction_id'], sale['id']);
    expect(reversal['quantity'], 4);
    expect(reversal['running_balance'], 10);
  });
}
