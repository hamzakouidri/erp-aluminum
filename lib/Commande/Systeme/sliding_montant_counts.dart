typedef SlidingMontantCounts = ({int central, int lateral, bool meetsInCenter});

/// Returns the physical vertical montant count for a sliding sash layout.
SlidingMontantCounts slidingMontantCounts({
  required int sashes,
  required int tracks,
  required bool faceToFace,
}) {
  final meetsInCenter =
      sashes >= 4 &&
      sashes.isEven &&
      (faceToFace || tracks == 2 || tracks == 0);

  if (meetsInCenter) {
    return (lateral: 4, central: sashes == 4 ? 4 : 8, meetsInCenter: true);
  }

  return (
    lateral: 2,
    central: sashes > 1 ? (sashes - 1) * 2 : 0,
    meetsInCenter: false,
  );
}
