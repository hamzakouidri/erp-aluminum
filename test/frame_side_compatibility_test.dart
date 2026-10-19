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

  test('without a pairing, a side takes only the frame itself', () {
    final m = model();
    final base = _frame(1, visibleWidth: 45);

    // Nothing is guessed from widths any more.
    expect(m.frameFitsSideOf(base, _frame(2, visibleWidth: 45)), isFalse);
    expect(m.frameFitsSideOf(base, base), isTrue);
  });

  test('a side takes the frames set in the frame pairing page', () {
    final m = model();
    m.setFramePairingsForTest({
      1: {'no_cover_frame_id': 2, 'corner_frame_id': 3, 'join_ids': '7'},
    });
    final base = _frame(1, visibleWidth: 45);

    expect(m.frameFitsSideOf(base, _frame(2, visibleWidth: 45)), isTrue);
    expect(m.frameFitsSideOf(base, _frame(3, visibleWidth: 50)), isTrue);
    expect(m.frameFitsSideOf(base, _frame(7, seriesId: 2)), isTrue);
    expect(m.frameFitsSideOf(base, _frame(4, visibleWidth: 45)), isFalse);
    expect(m.noCoverFrameIdFor(1), 2);
    expect(m.cornerFrameIdFor(1), 3);
    // Joining goes both ways.
    expect(m.frameFitsSideOf(_frame(7, seriesId: 2), base), isTrue);
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
