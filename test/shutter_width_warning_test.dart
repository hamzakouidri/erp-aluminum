import 'package:flutter_test/flutter_test.dart';
import 'package:database_data/Commande/Systeme/model.dart';
import 'package:database_data/sql_database.dart';

void main() {
  test(
    'warning appears immediately on manual blade selection without async defaults',
    () {
      final model = WindowModel(db: SqlDatabase());
      model.hasShutter = true;
      model.width = 3000;
      model.componentOverrides['الشرائح (Lames)'] = {
        'name': 'Lame 43',
        'max_width_mm': 2500,
        'manual_selection': true,
      };
      expect(model.shutterWidthWarning, contains('Lame 43'));
      expect(model.shutterWidthWarning, contains('2500'));
      model.componentOverrides['الشرائح (Lames)'] = {
        'name': 'Lame 55',
        'max_width_mm': 4000,
        'manual_selection': true,
      };
      expect(model.shutterWidthWarning, isNull);
    },
  );
  test(
    'dimension changes and disabling shutter update warning synchronously',
    () {
      final model = WindowModel(db: SqlDatabase());
      model.hasShutter = true;
      model.componentOverrides['الشرائح (Lames)'] = {
        'name': 'Blade',
        'max_width_mm': 2500,
      };
      model.width = 2500;
      expect(model.shutterWidthWarning, isNull);
      model.width = 2501;
      expect(model.shutterWidthWarning, isNotNull);
      model.hasShutter = false;
      expect(model.shutterWidthWarning, isNull);
    },
  );
  test('bar length also limits a manually selected blade', () {
    final model = WindowModel(db: SqlDatabase());
    model.hasShutter = true;
    model.width = 3500;
    model.componentOverrides['الشرائح (Lames)'] = {
      'name': 'Short bar',
      'max_width_mm': 6000,
      'bar_length_m': 3,
    };
    expect(model.shutterWidthWarning, contains('3000'));
  });
}
