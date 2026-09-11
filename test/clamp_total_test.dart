import 'package:database_data/Commande/Systeme/bom_engine_v2.dart';
import 'package:flutter_test/flutter_test.dart';

import 'accessory_assembly_rules_test.dart' as fixtures;

void main() {
  test('generic clamp includes frame unless explicitly restricted', () async {
    final db = fixtures.RuleDatabase();
    db.rules
      ..clear()
      ..add({'item_id': 1, 'role_key': 'clam'});
    final window = fixtures.makeWindow(db)..hasBottomFrame = true;
    Future<double> quantity() async {
      final items = await BomEngineV2(database: db)
          .filterItemsByAvailableCandidates(window: window, items: []);
      return items.fold<double>(0, (sum, item) => sum + item.quantity);
    }
    expect(await quantity(), 12);
    db.rules.single['assembly_target'] = 'sash';
    expect(await quantity(), 8);
  });
  test('double sash includes four frame and eight sash clamps', () async {
    final db = fixtures.RuleDatabase();
    db.rules
      ..clear()
      ..addAll([
        {'item_id': 1, 'role_key': 'sash_clamp'},
        {'item_id': 1, 'role_key': 'frame_clamp'},
      ]);
    final window = fixtures.makeWindow(db)..hasBottomFrame = true;
    final items = await BomEngineV2(
      database: db,
    ).filterItemsByAvailableCandidates(window: window, items: []);
    expect(items.fold<double>(0, (sum, item) => sum + item.quantity), 12);
    expect(
      {for (final item in items) item.roleKey: item.quantity},
      {'sash_clamp': 8, 'frame_clamp': 4},
    );
  });
}
