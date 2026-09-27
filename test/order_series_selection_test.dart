import 'package:database_data/Commande/Systeme/model.dart';
import 'package:database_data/Commande/Systeme/model_serialization.dart';
import 'package:database_data/sql_database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';
import 'accessory_assembly_rules_test.dart' show MemoryDatabase;

class _CatalogDatabase extends SqlDatabase {
  String? scope;
  @override
  Future<List<Map<String, dynamic>>> getSeriesDesignRoles(int seriesId) async =>
      scope == null ? [] : [
        {'role_key': 'frame', 'section_id': 999, 'usage_scope': scope},
      ];
  final connection = _EmptyCatalogConnection();
  @override
  Future<Database?> get db async => connection;
}

class _EmptyCatalogConnection extends MemoryDatabase {
  @override
  Future<List<Map<String, Object?>>> query(
    String table, {
    bool? distinct,
    List<String>? columns,
    String? where,
    List<Object?>? whereArgs,
    String? groupBy,
    String? having,
    String? orderBy,
    int? limit,
    int? offset,
  }) async => [];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final scope in ['opening', 'sliding']) {
    test('numeric 40000 follows catalogue $scope scope in bulk selection', () async {
      SharedPreferences.setMockInitialValues({});
      final database = _CatalogDatabase()..scope = scope;
      final oldSeries = AluminumSeries(
        id: 1, profileId: 1, name: 'Brolex Battant', type: 'Aluminium',
      );
      final selected = AluminumSeries(
        id: 2, profileId: 2, name: '40000', type: 'Aluminium',
      );
      final model = WindowModel(db: database)
        ..systemMode = scope == 'sliding' ? 'sliding' : 'mixed'
        ..activeSeries = oldSeries
        ..activeSlidingSeries = oldSeries;
      await model.setOrderSeries(selected);
      expect(model.activeFrameSeries?.id, selected.id);
      expect(model.toMap()['seriesName'], '40000');
      model.dispose();
    });
  }

  test('order series change updates the sliding card, drawing and saved name',
      () async {
    SharedPreferences.setMockInitialValues({});
    final oldSeries = AluminumSeries(
      id: 1, profileId: 1, name: 'Old sliding', type: 'sliding',
    );
    final newSeries = AluminumSeries(
      id: 2, profileId: 1, name: 'New sliding', type: 'sliding',
    );
    final model = WindowModel(db: _CatalogDatabase())
      ..systemMode = 'sliding'
      ..activeSeries = oldSeries
      ..activeSlidingSeries = oldSeries
      ..loadedSeriesId = oldSeries.id
      ..loadedSlidingSeriesId = oldSeries.id;

    await model.setOrderSeries(newSeries);

    expect(model.activeFrameSeries?.name, newSeries.name);
    expect(model.activeSlidingSeries?.id, newSeries.id);
    expect(model.loadedSeriesId, newSeries.id);
    expect(model.loadedSlidingSeriesId, newSeries.id);
    final saved = model.toMap();
    expect(saved['seriesName'], newSeries.name);
    expect(saved['slidingSeriesName'], newSeries.name);
    final restored = WindowModel(db: _CatalogDatabase());
    applyWindowModelFromMap(restored, saved);
    expect(restored.loadedSeriesId, newSeries.id);
    expect(restored.loadedSlidingSeriesId, newSeries.id);
    model.dispose();
    restored.dispose();
  });
}
