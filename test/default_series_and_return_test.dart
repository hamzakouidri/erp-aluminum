import 'package:flutter_test/flutter_test.dart';
import 'package:database_data/Commande/Systeme/model.dart';
import 'package:database_data/Commande/Systeme/model_serialization.dart';
import 'package:database_data/sql_database.dart';

void main() {
  test('WindowModel retains loadedSeriesId when active series changes', () {
    final model = WindowModel(width: 1000, height: 1200, db: SqlDatabase());
    final customSeries = AluminumSeries(
      id: 42,
      profileId: 1,
      name: 'TPR 67000',
      type: 'Aluminium',
    );

    model.activeSeries = customSeries;
    model.loadedSeriesId = customSeries.id;
    model.loadedSeriesName = customSeries.name;

    expect(model.loadedSeriesId, equals(42));
    expect(model.loadedSeriesName, equals('TPR 67000'));
    expect(model.activeSeries?.id, equals(42));
  });

  test(
    'WindowModel retains loadedSlidingSeriesId when sliding series changes',
    () {
      final model = WindowModel(width: 1000, height: 1200, db: SqlDatabase());
      final slidingSeries = AluminumSeries(
        id: 99,
        profileId: 2,
        name: 'Sliding 2Rail',
        type: 'Aluminium',
      );

      model.activeSlidingSeries = slidingSeries;
      model.loadedSlidingSeriesId = slidingSeries.id;
      model.loadedSlidingSeriesName = slidingSeries.name;

      expect(model.loadedSlidingSeriesId, equals(99));
      expect(model.loadedSlidingSeriesName, equals('Sliding 2Rail'));
      expect(model.activeSlidingSeries?.id, equals(99));
    },
  );

  test('restores saved series ids when an older order stores them as text', () {
    final model = WindowModel(width: 1000, height: 1200, db: SqlDatabase());

    applyWindowModelFromMap(model, const {
      'seriesId': '42',
      'seriesName': 'Special series',
      'slidingSeriesId': '99',
      'slidingSeriesName': 'Special sliding series',
    });

    expect(model.loadedSeriesId, 42);
    expect(model.loadedSlidingSeriesId, 99);
  });

  test('restores the sliding series from a legacy BS90 frame selection', () {
    final model = WindowModel(width: 1000, height: 1200, db: SqlDatabase());

    applyWindowModelFromMap(model, const {
      'systemMode': 'mixed',
      'seriesId': 40000,
      'slidingFrameOverride': {
        'id': 901,
        'series_id': 90,
        'series_name': 'BS90',
      },
    });

    expect(model.loadedSlidingSeriesId, 90);
    expect(model.loadedSlidingSeriesName, 'BS90');
  });

  test('a sliding-only drawing saves the selected sliding series as primary', () {
    final model = WindowModel(width: 2500, height: 2400, db: SqlDatabase());
    model.systemMode = 'sliding';
    model.activeSeries = AluminumSeries(
      id: 40000,
      profileId: 1,
      name: 'Bennia 40000',
      type: 'Aluminium',
    );
    model.activeSlidingSeries = AluminumSeries(
      id: 90,
      profileId: 2,
      name: 'BS90',
      type: 'Aluminium',
    );

    final saved = model.toMap();

    expect(saved['seriesId'], 90);
    expect(saved['seriesName'], 'BS90');
    expect(saved['slidingSeriesId'], 90);
  });
}
