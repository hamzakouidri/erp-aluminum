import 'package:flutter_test/flutter_test.dart';
import 'package:database_data/Commande/Systeme/model.dart';
import 'package:database_data/sql_database.dart';
import 'package:database_data/settings/app_settings.dart' show AppLanguage;

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

  test('recommends compatible blade and applies recommendation correctly', () {
    final model = WindowModel(db: SqlDatabase());
    model.hasShutter = true;
    model.width = 2800;

    final blade43 = {
      'id': 1,
      'name': 'Lame 43',
      'max_width_mm': 2200,
    };
    final blade55 = {
      'id': 2,
      'name': 'Lame 55',
      'max_width_mm': 3200,
    };
    final bladeX3d = {
      'id': 3,
      'name': 'Lame X3D',
      'max_width_mm': 4500,
    };

    model.setShutterBladeWarningCatalogue([blade43, blade55, bladeX3d]);
    model.componentOverrides['الشرائح (Lames)'] = Map<String, dynamic>.from(blade43);

    // Recommended blade should be the smallest fitting blade (Lame 55)
    expect(model.recommendedShutterBlade?['name'], equals('Lame 55'));

    // Localized warnings check
    final ar = model.localizedShutterWidthWarning(AppLanguage.arabic);
    expect(ar, contains('يُنصح بتغيير الشفرة إلى «Lame 55»'));

    final fr = model.localizedShutterWidthWarning(AppLanguage.french);
    expect(fr, contains('Il est recommandé de choisir «Lame 55»'));

    final en = model.localizedShutterWidthWarning(AppLanguage.english);
    expect(en, contains('It is recommended to choose «Lame 55»'));

    // Apply recommendation
    model.applyRecommendedShutterBlade();
    expect(model.componentOverrides['الشرائح (Lames)']?['name'], equals('Lame 55'));
    expect(model.shutterWidthWarning, isNull);
  });
}
