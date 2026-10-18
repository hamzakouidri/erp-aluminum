import 'package:database_data/sql_database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _OrdersDatabase extends SqlDatabase {
  _OrdersDatabase(this.connection);

  final Database connection;

  @override
  Future<Database?> get db async => connection;
}

Future<Map<String, Object?>> _order(Database connection) async =>
    (await connection.query('Commandes', where: 'id = 1')).single;

void main() {
  test('local order writes are stamped with their author', () async {
    sqfliteFfiInit();
    SharedPreferences.setMockInitialValues({});
    final connection = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
    );
    addTearDown(connection.close);
    for (final table in const [
      'Client',
      'Commandes',
      'Commandes_details',
      'Achats',
      'Achat_items',
      'Suppliers',
      'PaymentAllocations',
      'Treasury',
      'WorkerTransactions',
      'Employees',
    ]) {
      await connection.execute(
        'CREATE TABLE $table (id INTEGER PRIMARY KEY, updated_at TEXT)',
      );
    }
    // Installs the sync infrastructure, including the editor triggers.
    await _OrdersDatabase(connection).clearPersonalData();

    Future<void> signIn(String uid) => connection.update(
      '_sync_runtime_flags',
      {'local_editor_uid': uid},
      where: 'id = 1',
    );

    await signIn('worker-a');
    await connection.insert('Commandes', {'id': 1, 'updated_at': 't1'});
    var order = await _order(connection);
    expect(order['last_editor_uid'], 'worker-a');
    expect(order['last_editor_version'], 't1');

    await signIn('worker-b');
    await connection.update('Commandes', {'updated_at': 't2'}, where: 'id = 1');
    order = await _order(connection);
    expect(order['last_editor_uid'], 'worker-b');
    expect(order['last_editor_version'], 't2');

    // A row downloaded from the cloud keeps the author it arrived with.
    await connection.update('_sync_runtime_flags', {
      'suppress_tombstones': 1,
    }, where: 'id = 1');
    await connection.update('Commandes', {
      'updated_at': 't3',
      'last_editor_uid': 'worker-c',
      'last_editor_version': 't3',
    }, where: 'id = 1');
    order = await _order(connection);
    expect(order['last_editor_uid'], 'worker-c');
    expect(order['last_editor_version'], 't3');
  });
}
