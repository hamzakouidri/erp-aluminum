import 'package:database_data/Commande/Systeme/calculate_component.dart';
import 'package:database_data/Commande/Systeme/model.dart';
import 'package:database_data/Commande/Systeme/model_serialization.dart';
import 'package:database_data/Commande/Systeme/profile_selector_dialog.dart';
import 'package:database_data/sql_database.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeSqlDatabase extends SqlDatabase {}

void main() {
  group('parclose corner caps', () {
    test('one cap per corner of each rectangular parclose', () {
      // One glass: two widths and two heights, four corners.
      expect(
        ComponentCalculator.parcloseCornerCount([true, true, false, false]),
        4,
      );
      // Two glasses.
      expect(
        ComponentCalculator.parcloseCornerCount([
          true, true, false, false, //
          true, true, false, false,
        ]),
        8,
      );
      // A shaped (slanted) cell is mitred and takes no cap.
      expect(
        ComponentCalculator.parcloseCornerCount([null, null, null]),
        0,
      );
    });

    test('caps show only with a 90° aluminium cut and the option on', () {
      final model = WindowModel(db: FakeSqlDatabase());
      expect(model.showsParcloseCornerCaps, isFalse);
      model.setParcloseCornerCaps(true);
      expect(model.showsParcloseCornerCaps, isFalse, reason: '45° cut');
      model.setParcloseCutMode('90_length');
      expect(model.showsParcloseCornerCaps, model.isPVC ? isFalse : isTrue);
      model.setParcloseCornerCaps(false);
      expect(model.showsParcloseCornerCaps, isFalse);
    });

    test('the option is saved with the drawing', () {
      final model = WindowModel(db: FakeSqlDatabase());
      model.setParcloseCutMode('90_width');
      model.setParcloseCornerCaps(true);
      final restored = WindowModel(db: FakeSqlDatabase());
      applyWindowModelFromMap(restored, model.toMap());
      expect(restored.parcloseCornerCaps, isTrue);
      expect(restored.parcloseCutMode, '90_width');

      applyWindowModelFromMap(restored, const {});
      expect(restored.parcloseCornerCaps, isFalse);
    });

    test('the cap resolves to its own catalogue role', () {
      expect(catalogRuleKeysForAccessorySelectorType('parclose_corner_cap'), [
        'parclose_corner_cap',
      ]);
      expect(catalogRuleAllowsGlobalFallback('parclose_corner_cap'), isTrue);
    });
  });
}
