import 'package:database_data/Commande/Systeme/calculate_component.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final low = <String, dynamic>{'min_mm': 10, 'max_mm': 20};
  final high = <String, dynamic>{'min_mm': 20, 'max_mm': 30};
  final ranges = [low, high];

  bool contains(Map<String, dynamic> range, double value) =>
      ComponentCalculator.kitRangeContains(range, value, ranges);

  test('a value on a shared boundary belongs to one range only', () {
    expect(contains(low, 20), isFalse);
    expect(contains(high, 20), isTrue);
  });

  test('values inside a range match it', () {
    expect(contains(low, 10), isTrue);
    expect(contains(low, 19.9), isTrue);
    expect(contains(high, 25), isTrue);
  });

  test('the upper bound of the last range still matches', () {
    expect(contains(high, 30), isTrue);
    expect(contains(high, 30.1), isFalse);
  });

  test('ranges of another compatibility group do not take the boundary', () {
    final groupOne = <String, dynamic>{
      'min_mm': 10,
      'max_mm': 20,
      'compatibility_group': 1,
    };
    final groupTwo = <String, dynamic>{
      'min_mm': 20,
      'max_mm': 30,
      'compatibility_group': 2,
    };
    expect(
      ComponentCalculator.kitRangeContains(groupOne, 20, [groupOne, groupTwo]),
      isTrue,
    );
  });
}
