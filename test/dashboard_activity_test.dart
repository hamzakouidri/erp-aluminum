import 'package:database_data/sql_database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _ActivityDatabase extends SqlDatabase {
  _ActivityDatabase(this.connection);

  final Database connection;

  @override
  Future<Database?> get db async => connection;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('opening an order is recorded once, newest first', () async {
    SharedPreferences.setMockInitialValues({});
    sqfliteFfiInit();
    final connection = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
    );
    addTearDown(connection.close);
    final db = _ActivityDatabase(connection);

    await db.recordOrderOpened(41);
    await db.recordOrderOpened(41);
    await db.recordOrderOpened(42);

    final rows = await db.readDashboardActivities();
    expect(rows.map((r) => r['entity_id']), [42, 41]);
    expect(rows.every((r) => r['activity_type'] == 'order_opened'), isTrue);
  });
}
