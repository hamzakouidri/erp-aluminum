import 'package:database_data/Commande/Systeme/model.dart';
import 'package:database_data/Commande/Systeme/model_serialization.dart';
import 'package:database_data/sql_database.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeSqlDatabase extends SqlDatabase {}

AluminumSection parclose(int id, {String? support, String? defaultCut}) =>
    AluminumSection.fromMap({
      'id': id,
      'series_id': 1,
      'code': 'P$id',
      'name': 'Parclose $id',
      'type': 'parclose',
      'max_glass_thickness': 24.0,
      'parclose_cut_support': ?support,
      'parclose_default_cut': ?defaultCut,
    });

WindowModel windowWith(List<AluminumSection> beads, {int? chosenId}) {
  final model = WindowModel(db: FakeSqlDatabase());
  model.activeSeries = AluminumSeries(
    id: 1,
    profileId: 1,
    name: 'Serie',
    type: 'Aluminium',
    sections: beads,
  );
  if (chosenId != null) {
    model.componentOverrides['باكيت الزجاج (Parclose)'] = {'id': chosenId};
  }
  return model;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('parclose cut rule', () {
    test('a profile without the columns keeps every cut, 45° first', () {
      final rule = ParcloseCutRule.fromMap(const {});
      expect(rule.allowedModes, ['45', '90_length', '90_width']);
      expect(rule.isFixed, isFalse);
      expect(rule.initialMode, '45');
      expect(parclose(1).parcloseCutRule, const ParcloseCutRule());
    });

    test('one supported cut is fixed', () {
      const only45 = ParcloseCutRule(support: '45', defaultMode: '90_width');
      expect(only45.allowedModes, ['45']);
      expect(only45.isFixed, isTrue);
      expect(only45.resolve('90_length'), '45');

      const only90 = ParcloseCutRule(support: '90', defaultMode: '90_width');
      expect(only90.allowedModes, ['90_width']);
      expect(only90.resolve('45'), '90_width');
      // A 90° only rule saved with a 45° default falls back to height first.
      expect(
        const ParcloseCutRule(support: '90').allowedModes,
        ['90_length'],
      );
    });

    test('unknown values read as the former behaviour', () {
      final rule = ParcloseCutRule.fromMap({
        'parclose_cut_support': 'x',
        'parclose_default_cut': null,
      });
      expect(rule, const ParcloseCutRule());
    });

    test('the rule survives the section map', () {
      final section = parclose(3, support: '90', defaultCut: '90_width');
      final copy = AluminumSection.fromMap(section.toMap());
      expect(
        copy.parcloseCutRule,
        const ParcloseCutRule(support: '90', defaultMode: '90_width'),
      );
    });

    test('a new drawing starts with the default of the parclose', () {
      final model = windowWith([
        parclose(1, support: 'both', defaultCut: '90_width'),
      ]);
      expect(model.parcloseCutMode, '90_width');
      expect(model.parcloseCutAt90, isTrue);
    });

    test('a parclose taking one cut imposes it', () {
      final model = windowWith([
        parclose(1, support: '45'),
        parclose(2, support: '90', defaultCut: '90_length'),
      ], chosenId: 2);
      model.setParcloseCutMode('45');
      expect(model.parcloseCutRule.isFixed, isTrue);
      expect(model.parcloseCutMode, '90_length');

      model.componentOverrides['باكيت الزجاج (Parclose)'] = {'id': 1};
      expect(model.parcloseCutMode, '45');
    });

    test('parcloses of the series with different rules leave every cut', () {
      final model = windowWith([
        parclose(1, support: '45'),
        parclose(2, support: '90', defaultCut: '90_length'),
      ]);
      expect(model.parcloseCutRule, const ParcloseCutRule());
    });

    test('a saved cut is kept while the parclose takes it', () {
      final saved = windowWith([parclose(1)]);
      saved.setParcloseCutMode('90_width');
      final map = saved.toMap();
      expect(map['parcloseCutMode'], '90_width');

      final both = windowWith([parclose(1, defaultCut: '90_length')]);
      applyWindowModelFromMap(both, map);
      expect(both.parcloseCutMode, '90_width');

      final only45 = windowWith([parclose(1, support: '45')]);
      applyWindowModelFromMap(only45, map);
      expect(only45.parcloseCutMode, '45');
    });
  });
}
