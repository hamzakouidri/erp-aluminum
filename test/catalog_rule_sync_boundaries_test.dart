import 'package:database_data/sql_database.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('workshop rule tables are not part of the global catalog snapshot', () {
    for (final table in SqlDatabase.workshopCatalogConfigurationTables) {
      expect(
        SqlDatabase.catalogTables,
        isNot(contains(table)),
        reason: '$table must have one synchronization owner only',
      );
    }
  });

  test('accessory and profile rules remain workshop-synchronized', () {
    expect(
      SqlDatabase.workshopCatalogConfigurationTables,
      containsAll(<String>['CatalogItemRules', 'ProfileCalculationRules']),
    );
  });
}
