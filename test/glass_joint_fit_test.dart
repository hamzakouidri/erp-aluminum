import 'package:flutter_test/flutter_test.dart';
import 'package:database_data/Commande/Systeme/glass_joint_fit.dart';

void main() {
  const rows = <Map<String, dynamic>>[
    {'id': 1, 'thickness': 2},
    {'id': 2, 'thickness': 5},
  ];
  test('two different gaskets can fill the required pocket', () {
    final fit = findGlassJointFit(
      candidates: rows,
      glassThickness: 6,
      capacity: 13,
      sides: 2,
    );
    expect(fit!.map((r) => r['id']).toSet(), {1, 2});
  });
  test('only zero to one millimetre excess allowed; all shortages rejected', () {
    const one = <Map<String, dynamic>>[
      {'thickness': 2},
    ];
    for (final capacity in [7.0, 8.0]) {
      expect(
        findGlassJointFit(
          candidates: one,
          glassThickness: 6,
          capacity: capacity,
          sides: 1,
        ),
        isNotNull,
      );
    }
    for (final capacity in [6.0, 8.1, 9.0, 10.0]) {
      expect(
        findGlassJointFit(
          candidates: one,
          glassThickness: 6,
          capacity: capacity,
          sides: 1,
        ),
        isNull,
      );
    }
  });
  test('gaskets precede spacer and spacer precedes glass', () {
    GlassPackFit? solve(double capacity) => fitGlassPack(
      capacity: capacity, outer: 5, inner: 5, spacer: 8, doubleGlass: true,
      jointChoices: [[{'thickness': 2}, {'thickness': 2}]],
      spacers: [6, 8], outerPanes: [4, 5], innerPanes: [4, 5]);
    expect(solve(22)!.spacer, 8);
    expect(solve(20)!.spacer, 6);
    expect(solve(20)!.outer, 5);
    expect(solve(18)!.outer + solve(18)!.inner, 9);
  });
}
