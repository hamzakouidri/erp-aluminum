import 'package:database_data/Commande/Systeme/calculate_component.dart';
import 'package:flutter_test/flutter_test.dart';
import 'accessory_assembly_rules_test.dart' as fixtures;

void main() {
  test('opening glass with parclose does not add generic sliding bourrage', () {
    final window = fixtures.makeWindow(fixtures.RuleDatabase());
    final items = ComponentCalculator.generateBom(window, {});
    final bourrage = items.where((item) => item.originalName.contains('Bourrage'));
    expect(bourrage, hasLength(1));
    expect(bourrage.single.originalName, contains('Simple'));
  });
}
