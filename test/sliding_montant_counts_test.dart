import 'package:database_data/Commande/Systeme/sliding_montant_counts.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('four leaves on two tracks use four lateral and four central posts', () {
    final counts = slidingMontantCounts(
      sashes: 4,
      tracks: 2,
      faceToFace: false,
    );

    expect(counts.meetsInCenter, isTrue);
    expect(counts.lateral, 4);
    expect(counts.central, 4);
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
}
