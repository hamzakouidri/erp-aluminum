import 'package:database_data/Commande/Systeme/model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const merged = DrawnGlassCell(
    key: 'left_cell_0_1',
    row: 0,
    col: 1,
    hSpan: 2,
    wSpan: 2,
    rect: Rect.fromLTWH(0, 0, 100, 100),
  );

  test('a tapped grid cell inside a merged sash cell selects it', () {
    expect(merged.covers('left_cell_0_1'), isTrue);
    expect(merged.covers('left_cell_1_2'), isTrue);
  });

  test('cells outside the span or on the other leaf are not covered', () {
    expect(merged.covers('left_cell_0_0'), isFalse);
    expect(merged.covers('left_cell_2_1'), isFalse);
    expect(merged.covers('right_cell_0_1'), isFalse);
    expect(merged.covers('left'), isFalse);
  });

  test('division keys tell the two leaves and both axes apart', () {
    String key(bool right, bool horizontal) => WindowModel.innerDivisionKey(
      'z',
      isRightSash: right,
      isHorizontal: horizontal,
      index: 0,
    );
    expect(
      {key(false, false), key(false, true), key(true, false), key(true, true)},
      hasLength(4),
    );
  });
}
