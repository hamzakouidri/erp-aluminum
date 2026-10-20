import 'dart:ui';

import 'package:database_data/Commande/Systeme/calculate_component.dart';
import 'package:database_data/Commande/Systeme/model.dart';
import 'package:flutter_test/flutter_test.dart';

import 'frame_role_activation_test.dart' show RoleWindow;

/// An opening frame (series 1) beside a sliding frame (series 2), both with
/// a separate side cover; the sliding frame's bottom is then cut from a
/// frame that takes no cover.
void main() {
  final noCoverBottom = AluminumSection(
    id: 303,
    seriesId: 2,
    name: 'Sliding frame without cover',
    code: 'NOCOVER',
    type: 'frame',
    isFrame: true,
    barLength: 6,
    visibleWidth: 50,
    allowsSideCover: false,
  );

  RoleWindow coupledWithCover() {
    final model = RoleWindow();
    model.hasSideCovers = true;
    model.sideCoverOverride = AluminumSection(
      id: 400,
      seriesId: 1,
      name: 'Couvre-joint',
      code: 'CJ',
      type: 'side_cover',
      barLength: 6,
      visibleWidth: 30,
    ).toMap();
    return model;
  }

  Rect slidingFrame(WindowModel model) =>
      model.getFrameRects().singleWhere(model.frameUsesSlidingSeries);
  Rect openingFrame(WindowModel model) => model.getFrameRects().singleWhere(
    (r) => !model.frameUsesSlidingSeries(r),
  );

  test('a no-cover bottom on one frame keeps the other frame bottom cover', () {
    final model = coupledWithCover();
    final sliding = slidingFrame(model);
    final opening = openingFrame(model);

    model.setFrameSideOverrides(sliding, ['bottom'], noCoverBottom.toMap());

    expect(model.frameSideAllowsSideCover(sliding, 'bottom'), isFalse);
    expect(model.frameSideAllowsSideCover(opening, 'bottom'), isTrue);
    expect(model.isSideCoverSegmentEnabled('bottom'), isTrue);

    final bom = ComponentCalculator.generateBom(model, {});
    final cover = bom.singleWhere((i) => i.roleKey == 'side_cover');
    // Top (one continuous piece), left, right and the opening frame's
    // bottom only.
    expect(cover.pieces, hasLength(4));
    final bottomLength = opening.width / 1000.0;
    expect(
      cover.pieces!.where((p) => (p - bottomLength).abs() < 0.1),
      isNotEmpty,
      reason: 'the opening frame keeps its bottom cover',
    );
    // The right cover (sliding frame) ends square at the bottom: one 45° cut
    // only, at the top.
    final rightIndex = cover.pieces!.indexWhere(
      (p) => (p - (sliding.height + 30) / 1000.0).abs() < 0.002,
    );
    expect(rightIndex, isNot(-1));
    expect(cover.pieceCutAngles![rightIndex], isNot('45/45'));
    model.dispose();
  });

  test('the replaced bottom has its own row in the quantity table', () {
    final model = coupledWithCover();
    final sliding = slidingFrame(model);
    model.setFrameSideOverrides(sliding, ['bottom'], noCoverBottom.toMap());

    final bom = ComponentCalculator.generateBom(model, {});
    final slidingFrameRow = bom.singleWhere(
      (i) => i.originalName.startsWith('إطار منزلق'),
    );
    expect(slidingFrameRow.pieces, hasLength(3));
    final replaced = bom.where(
      (i) => i.catalogItemId == noCoverBottom.id || i.profileCode == 'NOCOVER',
    );
    expect(replaced, hasLength(1));
    expect(replaced.single.pieces, hasLength(1));
    // Checked against the sliding series rules, where the frame is set;
    // under the opening series the table dropped the row.
    expect(replaced.single.sourceSeriesId, 2);
    model.dispose();
  });
}
