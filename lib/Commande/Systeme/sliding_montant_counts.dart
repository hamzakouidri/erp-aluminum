typedef SlidingMontantCounts = ({int central, int lateral, bool meetsInCenter});

/// Returns the physical vertical montant count for a sliding sash layout.
SlidingMontantCounts slidingMontantCounts({
  required int sashes,
  required int tracks,
  required bool faceToFace,
}) {
  final meetsInCenter = faceToFace && tracks >= 2 && sashes == tracks * 2;

  if (meetsInCenter) {
    return (lateral: 4, central: sashes == 4 ? 4 : 8, meetsInCenter: true);
  }

  return (
    lateral: 2,
    central: sashes > 1 ? (sashes - 1) * 2 : 0,
    meetsInCenter: false,
  );
}

/// The junctions between neighbouring sashes (0 = between the first and the
/// second sash) that carry chicane pieces: every overlap, one piece on each
/// of its two sashes. The central face-to-face meeting is not an overlap and
/// takes no chicane, so four face-to-face sashes need one chicane each.
List<int> slidingChicaneJunctions({
  required int sashes,
  required bool meetsInCenter,
}) {
  final centralMeeting = meetsInCenter ? sashes ~/ 2 - 1 : -1;
  return [
    for (var junction = 0; junction < sashes - 1; junction++)
      if (junction != centralMeeting) junction,
  ];
}
