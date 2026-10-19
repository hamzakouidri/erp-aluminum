import 'package:database_data/Commande/Systeme/model.dart';
import 'package:database_data/sql_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a cover stops at its own frame when the frame below takes none', () {
    final model = WindowModel(
      db: SqlDatabase(),
      width: 1200,
      height: 2400,
      profileThickness: 45,
    );
    final pt = model.profileThickness;
    model.zones = [
      WindowZone(
        id: 'upper',
        boundary: Rect.fromLTRB(pt, pt, 1200 - pt, 1200 - pt),
      ),
      WindowZone(
        id: 'lower',
        boundary: Rect.fromLTRB(pt, 1200 + pt, 1200 - pt, 2400 - pt),
      ),
    ];
    model.coupleFrames = true;

    final frames = model.getFrameRects()..sort((a, b) => a.top.compareTo(b.top));
    expect(frames, hasLength(2));
    final upper = frames.first;

    double leftLength(List<FrameEdgeSegment> edges) => edges
        .where((edge) => edge.side == 'left')
        .fold(0.0, (sum, edge) => sum + (edge.end - edge.start));

    // Both frames take a cover: one continuous left edge.
    final joined = model.getExposedFrameEdgeSegments();
    expect(leftLength(joined), closeTo(2400, 2));

    // The lower frame takes none: the left edge ends with the upper frame.
    final broken = model.getExposedFrameEdgeSegments(
      includeSide: (frame, side) => frame == upper,
    );
    final left = broken.where((edge) => edge.side == 'left').toList();
    expect(left, hasLength(1));
    expect(left.single.end, closeTo(upper.bottom, 2));
  });
}
