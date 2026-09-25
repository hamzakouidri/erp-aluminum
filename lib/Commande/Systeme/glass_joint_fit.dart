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
  final gaps = doubleGlass ? nearest(spacers, spacer) : <double>[0];
  for (final gap in gaps) {
    final result = attempt(outer, inner, gap);
    if (result != null) return result;
  }
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
