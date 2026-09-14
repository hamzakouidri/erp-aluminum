import 'package:database_data/Commande/Systeme/calculate_component.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Cremone Tringle rule', () {
    test('centred handle splits the usable length equally', () {
      final cuts = ComponentCalculator.cremoneTringleCutsMm(
        heightMm: 1200,
        deductionMm: 200,
        handleRatio: 0.5,
      );

      expect(cuts, <double>[500, 500]);
    });

    test('handle below centre shares its displacement between both cuts', () {
      final cuts = ComponentCalculator.cremoneTringleCutsMm(
        heightMm: 1200,
        deductionMm: 200,
        handleRatio: 400 / 1200,
      );

      expect(cuts[0], closeTo(400, 0.000001));
      expect(cuts[1], closeTo(600, 0.000001));
    });

    test('handle above centre reverses the long and short cuts', () {
      final cuts = ComponentCalculator.cremoneTringleCutsMm(
        heightMm: 1200,
        deductionMm: 200,
        handleRatio: 800 / 1200,
      );

      expect(cuts[0], closeTo(600, 0.000001));
      expect(cuts[1], closeTo(400, 0.000001));
      expect(cuts[0] + cuts[1], 1000);
    });
  });
}
