import 'package:database_data/sql_database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _GroupsDatabase extends SqlDatabase {
  _GroupsDatabase(this.connection);

  final Database connection;

  @override
  Future<Database?> get db async => connection;
}

void main() {
  test('a profile is compatible with every member of its groups', () async {
    sqfliteFfiInit();
    SqlDatabase.resetDb();
    SharedPreferences.setMockInitialValues({});
    final connection = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
    );
    addTearDown(connection.close);
    final db = _GroupsDatabase(connection);

    // Creates the table. Writes go through the cloud sync, which needs a
    // Supabase session: the rows are inserted directly.
    expect(await db.readProfileCompatibilityGroups(1), isEmpty);
    Future<int> group(String members, {int active = 1}) => connection.insert(
      'ProfileCompatibilityGroups',
      {'series_id': 1, 'member_ids': members, 'is_active': active},
    );
    // Three frames together, a frame with a mullion, and a deleted group.
    await group('10,11,12');
    await group('12, 30');
    await group('10,40', active: 0);

    final groups = await db.readProfileCompatibilityGroups(1);
    expect(groups.map((g) => g['members']), [
      {10, 11, 12},
      {12, 30},
    ]);
    expect(await db.readProfileCompatibilityPartnerIds(10), {11, 12});
    expect(await db.readProfileCompatibilityPartnerIds(12), {10, 11, 30});
    expect(await db.readFrameJoinPartnerIds(30), {12});
    expect(await db.readFrameJoinPartnerIds(30, includeGroups: false), isEmpty);
  });
}
