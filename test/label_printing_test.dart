import 'dart:typed_data';

import 'package:database_data/services/cutting_optimizer_engine.dart';
import 'package:database_data/services/labels/cut_piece_labels.dart';
import 'package:database_data/services/labels/zpl_encoder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a monochrome label becomes one ^GFA graphic', () {
    // 10 x 2 dots: first row black, second row white.
    final dots = [for (var i = 0; i < 20; i++) i < 10];
    final zpl = zplLabelFromDots(width: 10, height: 2, dots: dots);
    // 2 bytes per row (10 dots), 4 bytes in all.
    expect(zpl, startsWith('^XA^PW10^LL2'));
    expect(zpl, contains('^GFA,4,4,2,FFC00000^FS'));
    expect(zpl.trim(), endsWith('^XZ'));
  });

  test('dark opaque pixels print, light or transparent ones do not', () {
    final rgba = Uint8List.fromList([
      0, 0, 0, 255, // black
      255, 255, 255, 255, // white
      0, 0, 0, 0, // transparent
    ]);
    expect(monochromeFromRgba(rgba, 3, 1), [true, false, false]);
  });

  test('cut-piece labels follow the cutting order with ASCII barcodes', () {
    CuttingPiece piece(double length) => CuttingPiece(
      id: 'قطعة',
      orderId: 1234567890123,
      orderName: 'طلبية 43',
      detailId: 1,
      windowName: 'نافذة 1',
      profileName: 'إطار',
      lengthMm: length,
    );
    final bar = OptimizedBar(
      barNumber: 2,
      profileName: 'إطار',
      color: 'أبيض',
      barLengthMm: 6000,
      cuts: [
        BarCut(piece: piece(1200), startMm: 0, endMm: 1200),
        BarCut(piece: piece(800), startMm: 1203, endMm: 2003),
      ],
      usedLengthMm: 2000,
      kerfLossMm: 6,
      remnantLengthMm: 3994,
      isUsableRemnant: true,
      usableRemnantThresholdMm: 500,
    );
    final report = CuttingOptimizationReport(
      groups: [
        ProfileOptimizationGroup(
          profileName: 'إطار',
          color: 'أبيض',
          totalPieces: 2,
          totalRequiredMeters: 2,
          barsNeeded: 1,
          bars: [bar],
          totalScrapMeters: 0,
          totalUsableRemnantsMeters: 4,
          efficiencyPercentage: 33,
        ),
      ],
      totalBars: 1,
      totalPieces: 2,
      totalMetersUsed: 2,
      totalMetersScrap: 0,
      totalMetersUsableRemnants: 4,
      overallEfficiency: 33,
    );
    final labels = cutPieceLabelsFor(report);
    expect(labels.map((l) => l.lengthMm), [1200, 800]);
    expect(labels.map((l) => '${l.cutNumber}/${l.cutsOnBar}'), ['1/2', '2/2']);
    final ascii = RegExp(r'^[\x20-\x7E]+$');
    expect(labels.every((l) => ascii.hasMatch(l.barcode)), isTrue);
    expect(labels.map((l) => l.barcode).toSet().length, 2);
  });
}
