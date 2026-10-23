import 'dart:math' as math;

import 'package:database_data/Commande/Systeme/calculate_component.dart';
import 'package:database_data/Commande/Systeme/model.dart';
import 'package:database_data/sql_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The arched window of the report: 2078 mm wide, 1210 mm of straight
/// jambs and a 497 mm arch, two leaves under the arch.
WindowModel _archedDoubleSash({double arch = 497}) {
  final model = WindowModel(
    db: SqlDatabase(),
    width: 2078,
    height: 1210,
    profileThickness: 60,
  );
  model.archHeight = arch;
  model.zones = [
    WindowZone(
      id: 'z',
      content: ZoneContent.doubleSash,
      boundary: const Rect.fromLTRB(60, 60, 2018, 1150),
    ),
  ];
  return model;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a flat head keeps the plain mitre', () {
    final model = _archedDoubleSash(arch: 0);
    expect(model.headBarCuts(0, 2078, inset: 0, depth: 60), isNull);
    final bom = ComponentCalculator.generateBom(model, {});
    final frame = bom.firstWhere((i) => i.originalName == 'الإطار (Frame)');
    expect(frame.pieceCutAngles, everyElement('45/45'));
  });

  test('where the arch meets a jamb the cut is not 45°', () {
    final model = _archedDoubleSash();
    final cuts = model.headBarCuts(0, 2078, inset: 0, depth: 60)!;
    // Arch of 2078 x 497: radius ~1334.5 mm, its end rises at ~51.1°, so
    // the corner is ~141° and each piece is cut at about half of it.
    final radius = 2078 * 2078 / (8 * 497) + 497 / 2;
    final rise = math.asin(1039 / radius) * 180 / math.pi;
    expect(rise, closeTo(51.1, 0.1));
    expect(cuts.left.headDeg, closeTo(70.3, 0.1));
    expect(cuts.left.sideDeg, closeTo(70.3, 0.1));
    expect(cuts.left.headDeg + cuts.left.sideDeg, closeTo(90 + rise, 1.0));
    // Symmetric arch: the same cut on both sides.
    expect(cuts.right.headDeg, closeTo(cuts.left.headDeg, 0.01));
    expect(cuts.right.sideDeg, closeTo(cuts.left.sideDeg, 0.01));
  });

  test('cutting list: frame and leaves follow the arch', () {
    final model = _archedDoubleSash();
    final cuts = model.headBarCuts(0, 2078, inset: 0, depth: 60)!;
    String deg(double v) => v.toStringAsFixed(1);
    final bom = ComponentCalculator.generateBom(model, {});

    final frame = bom.firstWhere((i) => i.originalName == 'الإطار (Frame)');
    // Top (the arch), bottom, left and right.
    expect(frame.pieceCutAngles, [
      '${deg(cuts.left.headDeg)}/${deg(cuts.right.headDeg)}',
      '45/45',
      '${deg(cuts.left.sideDeg)}/45',
      '${deg(cuts.right.sideDeg)}/45',
    ]);

    // The arch is cut to its developed length, not to the 2078 mm span:
    // radius x opening angle (~2381.7 mm).
    final radius = 2078 * 2078 / (8 * 497) + 497 / 2;
    final arcLength = 2 * radius * math.asin(1039 / radius);
    expect(arcLength, closeTo(2381.7, 0.1));
    expect(model.headEdgeLength(0, 2078, 0), closeTo(arcLength, 0.01));
    expect(frame.pieces!.first * 1000, closeTo(arcLength, 0.1));
    // The straight sides keep their size.
    expect(frame.pieces![2] * 1000, closeTo(1210, 0.1));

    final leaves = model.sashHeadCuts(
      model.zones.single,
      leftLeafRatio: model.zones.single.doubleSashRatio,
    )!;
    expect(leaves, hasLength(2));
    final left = leaves.first;
    // Outer corner of the left leaf: steep like the frame's.
    expect(left.left.sideDeg, greaterThan(60));
    // Under the crown the two leaves meet almost square to the arch: the
    // meeting stile stands just beside the crown, where the arch still
    // falls a little (~88.9°).
    expect(left.right.headDeg + left.right.sideDeg, closeTo(88.9, 0.1));

    final sash = bom.firstWhere(
      (i) =>
          i.pieceCutAngles != null &&
          i.pieces != null &&
          i.pieces!.length == 8 &&
          i.pieceCutAngles!.contains('${deg(left.left.sideDeg)}/45'),
    );
    expect(
      sash.pieceCutAngles!.first,
      '${deg(left.left.headDeg)}/${deg(left.right.headDeg)}',
    );
    expect(sash.pieceCutAngles![1], '45/45');
    // Each leaf's top bar is longer than its bottom bar by its arc.
    expect(left.extraLength, greaterThan(100));
    expect(
      (sash.pieces![0] - sash.pieces![1]) * 1000,
      closeTo(left.extraLength, 0.1),
    );
  });
}
