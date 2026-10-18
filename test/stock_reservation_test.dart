import 'package:database_data/sql_database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _StockDatabase extends SqlDatabase {
  _StockDatabase(this.connection);

  final Database connection;

  @override
  Future<Database?> get db async => connection;
}

const _itemId = 501;
const _itemType = 'Section';
const _colorId = 3;
const _locationId = 1;

Map<String, dynamic> _bars(double quantity) => {
  'item_id': _itemId,
  'item_type': _itemType,
  'color_id': _colorId,
  'location_id': _locationId,
  'quantity': quantity,
};

Future<double> _stock(Database connection) async {
  final rows = await connection.query(
    'CurrentStock',
    columns: const ['quantity'],
    where: 'item_id = ? AND item_type = ? AND color_id = ? AND location_id = ?',
    whereArgs: [_itemId, _itemType, _colorId, _locationId],
  );
  return (rows.first['quantity'] as num).toDouble();
}

Future<_StockDatabase> _openDatabase() async {
  sqfliteFfiInit();
  SharedPreferences.setMockInitialValues({});
  final connection = await databaseFactoryFfi.openDatabase(
    inMemoryDatabasePath,
  );
  addTearDown(connection.close);
  await connection.execute('''
    CREATE TABLE Commandes (
      id INTEGER PRIMARY KEY,
      is_deleted INTEGER NOT NULL DEFAULT 0
    )
  ''');
  await connection.execute('''
    CREATE TABLE CurrentStock (
      id INTEGER PRIMARY KEY,
      item_id INTEGER NOT NULL,
      item_type TEXT NOT NULL,
      color_id INTEGER,
      location_id INTEGER NOT NULL,
      quantity REAL NOT NULL DEFAULT 0.0,
      updated_at TEXT
    )
  ''');
  await connection.execute('''
    CREATE TABLE InventoryTransactions (
      id INTEGER PRIMARY KEY,
      item_id INTEGER NOT NULL,
      item_type TEXT NOT NULL,
      color_id INTEGER,
      location_id INTEGER NOT NULL,
      transaction_type TEXT NOT NULL,
      quantity REAL NOT NULL,
      reference_id INTEGER,
      note TEXT,
      created_at TEXT
    )
  ''');
  for (final table in const [
    'Locations',
    'Colors',
    'Series',
    'ShutterComponents',
    'Accessories',
    'Joints',
    'Glass',
  ]) {
    await connection.execute(
      'CREATE TABLE $table (id INTEGER PRIMARY KEY, name TEXT)',
    );
  }
  await connection.execute(
    'CREATE TABLE Sections '
    '(id INTEGER PRIMARY KEY, name TEXT, code TEXT, series_id INTEGER)',
  );
  await connection.execute('''
    CREATE TABLE Achats (
      id INTEGER PRIMARY KEY,
      supplier_id INTEGER,
      status TEXT,
      location_id INTEGER,
      total REAL,
      paid_amount REAL,
      remaining_amount REAL,
      updated_at TEXT
    )
  ''');
  await connection.execute('''
    CREATE TABLE Achat_items (
      id INTEGER PRIMARY KEY,
      achat_id INTEGER NOT NULL,
      item_code TEXT,
      item_name TEXT,
      item_type TEXT,
      item_id INTEGER,
      color_id INTEGER,
      quantity REAL NOT NULL,
      price REAL NOT NULL
    )
  ''');
  for (final id in const [1, 2]) {
    await connection.insert('Commandes', {'id': id});
  }
  await connection.insert('Locations', {'id': _locationId, 'name': 'Main'});
  await connection.insert('CurrentStock', {..._bars(10), 'id': 1});

  final database = _StockDatabase(connection);
  // Creates the reservation and remnant tables.
  await database.readStockAvailability(itemId: _itemId, itemType: _itemType);
  return database;
}

void main() {
  test('a reservation keeps its quantity away from other orders', () async {
    final database = await _openDatabase();

    await database.setOrderStockReservation(
      orderId: 1,
      reserved: true,
      stockDeductions: [_bars(6)],
    );
    await expectLater(
      database.setOrderStockReservation(
        orderId: 2,
        reserved: true,
        stockDeductions: [_bars(5)],
      ),
      throwsStateError,
    );
    expect(await database.isOrderStockReserved(2), isFalse);

    final forSecondOrder = await database.readStockAvailability(
      itemId: _itemId,
      itemType: _itemType,
      colorId: _colorId,
      forOrderId: 2,
    );
    expect(forSecondOrder.single['quantity'], 4);
    expect(forSecondOrder.single['physical_quantity'], 10);

    // Order 1 still sees its own hold.
    final forFirstOrder = await database.readStockAvailability(
      itemId: _itemId,
      itemType: _itemType,
      colorId: _colorId,
      forOrderId: 1,
    );
    expect(forFirstOrder.single['quantity'], 10);
  });

  test('an order issues its reserved stock and frees the hold', () async {
    final database = await _openDatabase();
    await database.setOrderStockReservation(
      orderId: 1,
      reserved: true,
      stockDeductions: [_bars(6)],
    );
    await database.setOrderStockReservation(
      orderId: 2,
      reserved: true,
      stockDeductions: [_bars(4)],
    );

    // Order 1 cannot take order 2's bars...
    await expectLater(
      database.applyOrderInventoryIssue(
        orderId: 1,
        remnantIds: const [],
        stockDeductions: [_bars(7)],
      ),
      throwsStateError,
    );
    expect(await _stock(database.connection), 10);

    // ...but can issue what it reserved.
    final result = await database.applyOrderInventoryIssue(
      orderId: 1,
      remnantIds: const [],
      stockDeductions: [_bars(6)],
    );
    expect(result['applied'], isTrue);
    expect(await _stock(database.connection), 4);
    expect(await database.isOrderStockReserved(1), isFalse);
    final holds = await database.connection.query(
      'StockReservations',
      where: 'order_id = ?',
      whereArgs: [1],
    );
    expect(holds.single['status'], 'consumed');
  });

  test('stock adjustments cannot use reserved quantities', () async {
    final database = await _openDatabase();
    await database.setOrderStockReservation(
      orderId: 1,
      reserved: true,
      stockDeductions: [_bars(8)],
    );

    await expectLater(
      database.updateInventory(
        itemId: _itemId,
        itemType: _itemType,
        colorId: _colorId,
        locationId: _locationId,
        quantityChange: -3,
        transactionType: 'Adjustment',
      ),
      throwsStateError,
    );
    expect(await _stock(database.connection), 10);

    await database.updateInventory(
      itemId: _itemId,
      itemType: _itemType,
      colorId: _colorId,
      locationId: _locationId,
      quantityChange: -2,
      transactionType: 'Adjustment',
    );
    expect(await _stock(database.connection), 8);

    // Releasing the order frees the bars again.
    await database.setOrderStockReservation(orderId: 1, reserved: false);
    await database.updateInventory(
      itemId: _itemId,
      itemType: _itemType,
      colorId: _colorId,
      locationId: _locationId,
      quantityChange: -3,
      transactionType: 'Adjustment',
    );
    expect(await _stock(database.connection), 5);
  });

  test('a store sale cannot take reserved stock', () async {
    final database = await _openDatabase();
    await database.setOrderStockReservation(
      orderId: 1,
      reserved: true,
      stockDeductions: [_bars(9)],
    );
    await database.connection.insert('MaterialSales', {
      'id': 70,
      'sale_code': 'V-70',
      'sale_date': '2026-10-18',
      'created_at': '2026-10-18',
      'updated_at': '2026-10-18',
    });
    for (final quantity in const [1.0, 1.0]) {
      await database.connection.insert('MaterialSaleItems', {
        'sale_id': 70,
        'item_type': _itemType,
        'item_id': _itemId,
        'item_name': 'Frame',
        'color_id': _colorId,
        'quantity': quantity,
      });
    }

    // Each line alone fits in the free bar; together they do not.
    await expectLater(
      database.deductStockForMaterialSale(70, locationId: _locationId),
      throwsStateError,
    );
    expect(await _stock(database.connection), 10);
  });

  test('a reserved remnant belongs to its order only', () async {
    final database = await _openDatabase();
    await database.connection.insert('MaterialRemnants', {
      'id': 900,
      'ticket_code': 'R-900',
      'item_id': _itemId,
      'item_type': _itemType,
      'color_id': _colorId,
      'length_mm': 2400,
      'location_id': _locationId,
      'status': 'available',
      'created_at': '2026-10-18',
      'updated_at': '2026-10-18',
    });
    await database.setOrderStockReservation(
      orderId: 1,
      reserved: true,
      remnantIds: const [900],
    );

    await expectLater(
      database.setOrderStockReservation(
        orderId: 2,
        reserved: true,
        remnantIds: const [900],
      ),
      throwsStateError,
    );
    final forOtherOrder = await database.readAvailableMaterialRemnants(
      itemId: _itemId,
      itemType: _itemType,
      colorId: _colorId,
      forOrderId: 2,
    );
    expect(forOtherOrder, isEmpty);
    final forOwnOrder = await database.readAvailableMaterialRemnants(
      itemId: _itemId,
      itemType: _itemType,
      colorId: _colorId,
      forOrderId: 1,
    );
    expect(forOwnOrder.single['id'], 900);

    await database.applyOrderInventoryIssue(
      orderId: 1,
      remnantIds: const [900],
      stockDeductions: const [],
    );
    final remnant = await database.connection.query(
      'MaterialRemnants',
      where: 'id = ?',
      whereArgs: [900],
    );
    expect(remnant.single['status'], 'consumed');
  });

  test('a supplier return changes nothing when stock is reserved', () async {
    final database = await _openDatabase();
    await database.connection.insert('Achats', {
      'id': 40,
      'status': 'Confirmed',
      'location_id': _locationId,
      'total': 1000.0,
      'paid_amount': 1000.0,
      'remaining_amount': 0.0,
    });
    await database.connection.insert('Achat_items', {
      'id': 41,
      'achat_id': 40,
      'item_code': 'F-1',
      'item_name': 'Frame',
      'item_type': _itemType,
      'item_id': _itemId,
      'color_id': _colorId,
      'quantity': 10.0,
      'price': 100.0,
    });
    await database.setOrderStockReservation(
      orderId: 1,
      reserved: true,
      stockDeductions: [_bars(8)],
    );

    await expectLater(
      database.returnAchatInvoice(40, [
        {'id': 41, 'returnQty': 3},
      ], 300),
      throwsStateError,
    );
    final line = await database.connection.query(
      'Achat_items',
      where: 'id = ?',
      whereArgs: [41],
    );
    expect(line.single['quantity'], 10);
    expect(await _stock(database.connection), 10);

    await database.returnAchatInvoice(40, [
      {'id': 41, 'returnQty': 2},
    ], 0);
    final returned = await database.connection.query(
      'Achat_items',
      where: 'id = ?',
      whereArgs: [41],
    );
    expect(returned.single['quantity'], 8);
    expect(await _stock(database.connection), 8);
    final achat = await database.connection.query(
      'Achats',
      where: 'id = ?',
      whereArgs: [40],
    );
    expect(achat.single['status'], 'Partial Returned');
  });
}
