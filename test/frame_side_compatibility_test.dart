import 'package:database_data/Commande/Systeme/model.dart';
import 'package:database_data/sql_database.dart';
import 'package:flutter_test/flutter_test.dart';

AluminumSection _frame(
  int id, {
  int seriesId = 1,
  double visibleWidth = 0,
  double thickness = 50,
}) => AluminumSection(
  id: id,
  seriesId: seriesId,
  name: 'Frame $id',
  code: 'F$id',
  type: 'frame',
  isFrame: true,
  thickness: thickness,
  visibleWidth: visibleWidth,
);

void main() {
  WindowModel model() => WindowModel(
    db: SqlDatabase(),
    width: 500,
    height: 200,
    profileThickness: 10,
  );

  test('without a group, a side takes a frame of the same visible width', () {
    final m = model();
    final base = _frame(1, visibleWidth: 45);

    expect(m.frameFitsSideOf(base, _frame(2, visibleWidth: 45)), isTrue);
    expect(m.frameFitsSideOf(base, _frame(3, visibleWidth: 46)), isFalse);
    expect(
      m.frameFitsSideOf(base, _frame(4, seriesId: 2, visibleWidth: 45)),
      isFalse,
    );
    // No visible width: the thickness stands for it.
    expect(m.frameFitsSideOf(_frame(5), _frame(6)), isTrue);
  });

  test('a frame in a group takes only the frames of its group', () {
    final m = model();
    // Group of three: 1, 2 and 7 (another series); 3 stays out.
    m.setFrameJoinGroupsForTest({
      1: {2, 7},
      2: {1, 7},
      7: {1, 2},
    });
    final base = _frame(1, visibleWidth: 45);

    expect(m.frameFitsSideOf(base, _frame(2, visibleWidth: 60)), isTrue);
    expect(
      m.frameFitsSideOf(base, _frame(7, seriesId: 2, visibleWidth: 45)),
      isTrue,
    );
    expect(m.frameFitsSideOf(base, _frame(3, visibleWidth: 45)), isFalse);
    expect(m.frameFitsSideOf(base, base), isTrue);
  });
}
