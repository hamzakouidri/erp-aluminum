import 'package:database_data/Commande/Systeme/bom_engine_v2.dart';
import 'package:flutter_test/flutter_test.dart';
import 'accessory_assembly_rules_test.dart' as fixtures;

void main() {
  for (final role in ['kit', 'sliding_kit', 'sliding_kit_40000', 'sliding_kit_67000']) {
    test('enabled $role appears with its price and quantity', () async {
      final db = fixtures.RuleDatabase();
      db.rules
        ..clear()
        ..add({'item_id': 10, 'series_id': 1, 'role_key': role, 'show_in_quantity': 1});
      final window = fixtures.makeWindow(db)..quantity = 2;
      final items = await BomEngineV2(database: db)
          .filterItemsByAvailableCandidates(window: window, items: []);
      final kit = items.single;
      expect(kit.roleKey, role);
      expect(kit.quantity, 2);
      expect(kit.unitPrice, 10);
    });
  }
}
