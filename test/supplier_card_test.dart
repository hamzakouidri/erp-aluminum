import 'package:database_data/sql_database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _SupplierDatabase extends SqlDatabase {
  _SupplierDatabase(this.connection);

  final Database connection;

  @override
  Future<Database?> get db async => connection;
}

void main() {
  test('the card lists what was bought from the supplier', () async {
    sqfliteFfiInit();
    SqlDatabase.resetDb();
    SharedPreferences.setMockInitialValues({});
    final connection = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
    );
    addTearDown(connection.close);
    await connection.execute(
      'CREATE TABLE Achats (id INTEGER PRIMARY KEY, supplier_id INTEGER, '
      'supplier_name TEXT, created_at TEXT, is_deleted INTEGER DEFAULT 0)',
    );
    await connection.execute(
      'CREATE TABLE Achat_items (id INTEGER PRIMARY KEY, achat_id INTEGER, '
      'item_code TEXT, item_name TEXT, item_type TEXT, quantity REAL, '
      'price REAL)',
    );
    Future<void> invoice(int id, String date, {int deleted = 0}) =>
        connection.insert('Achats', {
          'id': id,
          'supplier_id': 7,
          'supplier_name': 'Alu Sétif',
          'created_at': date,
          'is_deleted': deleted,
        });
    await invoice(1, '2026-09-01');
    await invoice(2, '2026-10-01');
    await invoice(3, '2026-10-05', deleted: 1);
    Future<void> line(int invoiceId, double qty, double price) =>
        connection.insert('Achat_items', {
          'achat_id': invoiceId,
          'item_code': '40 102',
          'item_name': 'Dormant',
          'quantity': qty,
          'price': price,
        });
    await line(1, 10, 5000);
    await line(2, 4, 5200);
    await line(3, 99, 1);

    final goods = await _SupplierDatabase(
      connection,
    ).readSupplierPurchasedGoods(7, 'Alu Sétif');
    expect(goods, hasLength(1));
    // The deleted invoice does not count; the last price is the newest.
    expect(goods.single['quantity'], 14);
    expect(goods.single['invoices'], 2);
    expect(goods.single['last_price'], 5200);
  });
}
