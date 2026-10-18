import 'package:database_data/Commande/Systeme/calculate_component.dart';
import 'package:database_data/Commande/Systeme/model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'accessory_assembly_rules_test.dart' as fixtures;

void main() {
  test('opening glass with parclose does not add generic sliding bourrage', () {
    final window = fixtures.makeWindow(fixtures.RuleDatabase());
    // The parclose is read from the series; without one the sash is treated
    // as its own glazing pocket and uses the direct Bourrage gasket instead.
    window.activeSeries!.sections.add(
      AluminumSection(
        id: 514,
        seriesId: 1,
        code: '514',
        name: 'Parclose',
        type: 'parclose',
      ),
    );
    final items = ComponentCalculator.generateBom(window, {});
    final bourrage = items.where((item) => item.originalName.contains('Bourrage'));
    expect(bourrage, hasLength(1));
    expect(bourrage.single.originalName, contains('Simple'));
  });
}
