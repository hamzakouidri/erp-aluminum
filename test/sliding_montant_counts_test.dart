import 'package:database_data/Commande/Systeme/sliding_montant_counts.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('enabled four leaves on two tracks meet in the center', () {
    final counts = slidingMontantCounts(
      sashes: 4,
      tracks: 2,
      faceToFace: true,
    );

    expect(counts.meetsInCenter, isTrue);
    expect(counts.lateral, 4);
    expect(counts.central, 4);
  });

  test('disabled face-to-face keeps the normal overlapping layout', () {
    final counts = slidingMontantCounts(
      sashes: 4,
      tracks: 2,
      faceToFace: false,
    );

    expect(counts.meetsInCenter, isFalse);
    expect(counts.lateral, 2);
    expect(counts.central, 6);
  });

  test('six leaves require three tracks for face-to-face', () {
    expect(
      slidingMontantCounts(sashes: 6, tracks: 3, faceToFace: true)
          .meetsInCenter,
      isTrue,
    );
    expect(
      slidingMontantCounts(sashes: 6, tracks: 2, faceToFace: true)
          .meetsInCenter,
      isFalse,
    );
  });

  test('two leaves keep two lateral and two central posts', () {
    final counts = slidingMontantCounts(
      sashes: 2,
      tracks: 2,
      faceToFace: false,
    );

    expect(counts.meetsInCenter, isFalse);
    expect(counts.lateral, 2);
    expect(counts.central, 2);
  });

  group('chicane pieces (one on each sash of every overlap)', () {
    int pieces(int sashes, {bool faceToFace = false}) =>
        slidingChicaneJunctions(sashes: sashes, meetsInCenter: faceToFace)
            .length *
        2;

    test('two sashes need two chicanes', () => expect(pieces(2), 2));
    test('three sashes: the middle one takes two', () => expect(pieces(3), 4));
    test('four sashes: the two middle ones take two', () {
      expect(pieces(4), 6);
    });
    test('four face-to-face sashes need one chicane each', () {
      expect(pieces(4, faceToFace: true), 4);
      expect(slidingChicaneJunctions(sashes: 4, meetsInCenter: true), [0, 2]);
    });
    test('six face-to-face sashes skip only the central meeting', () {
      expect(
        slidingChicaneJunctions(sashes: 6, meetsInCenter: true),
        [0, 1, 3, 4],
      );
    });
  });
}
