import 'package:database_data/Screen/tempered_glass_work_screen.dart';
import 'package:flutter_test/flutter_test.dart';

List<TemperedHoleIssue> _check(
  List<({double xMm, double yMm, double diameterMm, String purpose})> holes, {
  double thickness = 10,
}) => findTemperedHoleIssues(
  thicknessMm: thickness,
  panels: [(widthMm: 800, heightMm: 2000, holes: holes)],
);

void main() {
  test('a well placed hole has no issue', () {
    expect(
      _check([(xMm: 60, yMm: 1000, diameterMm: 20, purpose: 'handle')]),
      isEmpty,
    );
  });

  test('a hole touching the glass edge is reported', () {
    final issues = _check([
      (xMm: 10, yMm: 1000, diameterMm: 20, purpose: 'handle'),
    ]);
    expect(issues.single.kind, 'edge');
    expect(issues.single.valueMm, 0);
    expect(issues.single.minimumMm, 20);
  });

  test('a hole smaller than the glass thickness is reported', () {
    final issues = _check([
      (xMm: 100, yMm: 1000, diameterMm: 6, purpose: 'handle'),
    ]);
    expect(issues.map((issue) => issue.kind), ['diameter']);
  });

  test('two holes closer than twice the thickness are reported', () {
    final issues = _check([
      (xMm: 100, yMm: 1000, diameterMm: 20, purpose: 'a'),
      (xMm: 130, yMm: 1000, diameterMm: 20, purpose: 'b'),
    ]);
    expect(issues.single.kind, 'spacing');
    expect(issues.single.valueMm, 10);
    expect(issues.single.purpose, 'a / b');
  });
}
