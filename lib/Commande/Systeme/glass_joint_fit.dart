/// Searches only the catalogue rows supplied by the active series rules.
List<Map<String, dynamic>>? findGlassJointFit({
  required List<Map<String, dynamic>> candidates,
  required double glassThickness,
  required double capacity,
  required int sides,
}) {
  double thickness(Map<String, dynamic> row) =>
      double.tryParse('${row['thickness'] ?? 0}') ?? 0;
  final usable = candidates.where((row) => thickness(row) > 0).toList();
  List<Map<String, dynamic>>? best;
  var bestError = double.infinity;
  for (final first in usable) {
    for (final second in sides == 2 ? usable : <Map<String, dynamic>>[{}]) {
      final error =
          (glassThickness +
                  thickness(first) +
                  (sides == 2 ? thickness(second) : 0) -
                  capacity);
      if (error >= -0.000001 && error <= 1.000001 && error < bestError) {
        bestError = error;
        best = [first, if (sides == 2) second];
      }
    }
  }
  return best;
}

class GlassPackFit {
  const GlassPackFit(this.outer, this.inner, this.spacer, this.joints, this.total);
  final double outer, inner, spacer, total;
  final List<Map<String, dynamic>> joints;
}

/// Ordered search: joints only, then spacer, then glass. Candidates must be
/// supplied from the current series rules / compatible glass catalogue.
GlassPackFit? fitGlassPack({
  required double capacity,
  required double outer,
  required double inner,
  required double spacer,
  required bool doubleGlass,
  required List<List<Map<String, dynamic>>> jointChoices,
  required List<double> spacers,
  required List<double> outerPanes,
  required List<double> innerPanes,
  bool lockSpacer = false,
}) {
  List<double> nearest(List<double> values, double current) =>
      values.where((v) => v > 0).toSet().toList()
        ..sort((a, b) => (a - current).abs().compareTo((b - current).abs()));
  GlassPackFit? attempt(double out, double inside, double gap) {
    GlassPackFit? best;
    for (final joints in jointChoices) {
      final total = out + (doubleGlass ? inside + gap : 0) +
          joints.fold<double>(0, (sum, row) => sum +
              (double.tryParse('${row['thickness']}') ?? 0));
      final excess = total - capacity;
      if (excess >= -0.000001 && excess <= 1.000001 &&
          (best == null || total < best.total)) {
        best = GlassPackFit(out, inside, gap, joints, total);
      }
    }
    return best;
  }
  final exact = attempt(outer, inner, spacer);
  if (exact != null) return exact;
  // A spacer chosen by the user is kept: the caller reports the conflict and
  // suggests a fitting spacer instead of silently replacing it.
  if (lockSpacer) return null;
  final gaps = doubleGlass ? nearest(spacers, spacer) : <double>[0];
  // Among the spacers that fit, prefer the tightest pack (an exact fit before
  // the tolerated +1 mm); `gaps` is ordered by closeness to the requested
  // spacer, so ties keep the spacer nearest to the user's choice.
  GlassPackFit? bestGap;
  for (final gap in gaps) {
    final result = attempt(outer, inner, gap);
    if (result != null &&
        (bestGap == null || result.total < bestGap.total - 0.000001)) {
      bestGap = result;
    }
  }
  if (bestGap != null) return bestGap;
  final panes = <(double, double)>[
    for (final out in {outer, ...nearest(outerPanes, outer)})
      for (final inside in doubleGlass ? {inner, ...nearest(innerPanes, inner)} : {0.0})
        (out, inside),
  ]..sort((a, b) => ((a.$1 - outer).abs() + (a.$2 - inner).abs())
      .compareTo((b.$1 - outer).abs() + (b.$2 - inner).abs()));
  for (final pane in panes) {
    for (final gap in {spacer, ...gaps}) {
      final result = attempt(pane.$1, pane.$2, gap);
      if (result != null) return result;
    }
  }
  return null;
}

/// Thickest glazing gasket (per side) assumed when sizing a bead before the
/// catalogue gaskets are known.
const double kMaxGlazingGasketMm = 6.0;

/// The smallest glazing bead that can hold a pack of [requiredPack] (its
/// thinnest build-up). The pack may exceed the capacity by at most 1 mm (the
/// gasket compresses) but never fall short of it, so a bead holds it when
/// `capacity + 1 >= requiredPack`. A bead larger than [maximumPack] (the
/// thickest build-up) cannot be filled and is never used: a simple pane is
/// not glazed in a double bead. When the glass is too thick for every usable
/// bead, the largest is returned so the overflow is reported against a real
/// profile; when every bead is too large, there is none.
T? smallestFittingGlazingBead<T>(
  Iterable<T> beads,
  double Function(T bead) capacityOf, {
  required double requiredPack,
  double? maximumPack,
  bool Function(T bead)? preferred,
}) {
  final sorted =
      beads
          .where(
            (bead) =>
                capacityOf(bead) > 0 &&
                (maximumPack == null ||
                    capacityOf(bead) <= maximumPack + 0.000001),
          )
          .toList()
        ..sort((a, b) => capacityOf(a).compareTo(capacityOf(b)));
  if (sorted.isEmpty) return null;
  for (final bead in sorted) {
    if (capacityOf(bead) + 1.000001 < requiredPack) continue;
    if (preferred != null) {
      final sameCapacity = sorted.where(
        (other) => (capacityOf(other) - capacityOf(bead)).abs() < 0.000001,
      );
      for (final other in sameCapacity) {
        if (preferred(other)) return other;
      }
    }
    return bead;
  }
  return sorted.last;
}
