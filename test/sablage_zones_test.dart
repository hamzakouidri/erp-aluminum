import 'package:database_data/Screen/tempered_glass_work_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('bands at the top and bottom, full frosting in the middle', () {
    final ranges = splitGlassHeight(2000, [400, null, 400])!;
    expect(ranges.map((r) => (r.startMm, r.endMm)), [
      (0.0, 400.0),
      (400.0, 1600.0),
      (1600.0, 2000.0),
    ]);
  });

  test('zones without a remainder leave the rest of the glass as it is', () {
    final ranges = splitGlassHeight(2000, [300, 500])!;
    expect(ranges.last.endMm, 800);
  });

  test('impossible divisions are refused', () {
    expect(splitGlassHeight(2000, [1500, 600]), isNull);
    expect(splitGlassHeight(2000, [null, null]), isNull);
    expect(splitGlassHeight(2000, [0, null]), isNull);
  });
}
