import 'dart:math' as math;

/// Represents an individual cut piece required for production.
class CuttingPiece {
  final String id;
  final int orderId;
  final String orderName;
  final int detailId;
  final String windowName;
  final String profileName;
  final String profileCode;
  final String color;
  final double lengthMm;
  final int angleLeft;
  final int angleRight;

  const CuttingPiece({
    required this.id,
    required this.orderId,
    required this.orderName,
    required this.detailId,
    required this.windowName,
    required this.profileName,
    this.profileCode = '',
    this.color = 'Standard',
    required this.lengthMm,
    this.angleLeft = 45,
    this.angleRight = 45,
  });

  String get groupKey => '${profileName.trim().toLowerCase()}__${color.trim().toLowerCase()}';
}

/// Represents a placed cut piece on a specific physical bar.
class BarCut {
  final CuttingPiece piece;
  final double startMm;
  final double endMm;

  const BarCut({
    required this.piece,
    required this.startMm,
    required this.endMm,
  });

  double get lengthMm => endMm - startMm;
}

/// Represents a single 6m (or custom) physical aluminium bar with placed cuts and offcuts.
class OptimizedBar {
  final int barNumber;
  final String profileName;
  final String color;
  final double barLengthMm;
  final List<BarCut> cuts;
  final double usedLengthMm;
  final double kerfLossMm;
  final double remnantLengthMm;
  final bool isUsableRemnant;
  final double usableRemnantThresholdMm;

  const OptimizedBar({
    required this.barNumber,
    required this.profileName,
    required this.color,
    required this.barLengthMm,
    required this.cuts,
    required this.usedLengthMm,
    required this.kerfLossMm,
    required this.remnantLengthMm,
    required this.isUsableRemnant,
    required this.usableRemnantThresholdMm,
  });

  double get wasteMm => isUsableRemnant ? 0.0 : remnantLengthMm;

  double get wastePercentage =>
      barLengthMm > 0 ? (wasteMm / barLengthMm) * 100.0 : 0.0;

  double get efficiencyPercentage =>
      barLengthMm > 0 ? (usedLengthMm / barLengthMm) * 100.0 : 0.0;
}

/// Represents all bars and metrics for one specific profile + color category.
class ProfileOptimizationGroup {
  final String profileName;
  final String color;
  final int totalPieces;
  final double totalRequiredMeters;
  final int barsNeeded;
  final List<OptimizedBar> bars;
  final double totalScrapMeters;
  final double totalUsableRemnantsMeters;
  final double efficiencyPercentage;

  const ProfileOptimizationGroup({
    required this.profileName,
    required this.color,
    required this.totalPieces,
    required this.totalRequiredMeters,
    required this.barsNeeded,
    required this.bars,
    required this.totalScrapMeters,
    required this.totalUsableRemnantsMeters,
    required this.efficiencyPercentage,
  });
}

/// Comprehensive report containing optimization results across all profiles.
class CuttingOptimizationReport {
  final List<ProfileOptimizationGroup> groups;
  final int totalBars;
  final int totalPieces;
  final double totalMetersUsed;
  final double totalMetersScrap;
  final double totalMetersUsableRemnants;
  final double overallEfficiency;

  const CuttingOptimizationReport({
    required this.groups,
    required this.totalBars,
    required this.totalPieces,
    required this.totalMetersUsed,
    required this.totalMetersScrap,
    required this.totalMetersUsableRemnants,
    required this.overallEfficiency,
  });
}

/// High-performance 1D Cutting Stock Optimization Engine.
class CuttingOptimizerEngine {
  CuttingOptimizerEngine._();

  /// Runs 1D linear cutting optimization across the given list of [pieces].
  static CuttingOptimizationReport optimize({
    required List<CuttingPiece> pieces,
    double barLengthMm = 6000.0,
    double sawKerfMm = 4.0,
    double usableRemnantThresholdMm = 800.0,
  }) {
    if (pieces.isEmpty) {
      return const CuttingOptimizationReport(
        groups: [],
        totalBars: 0,
        totalPieces: 0,
        totalMetersUsed: 0,
        totalMetersScrap: 0,
        totalMetersUsableRemnants: 0,
        overallEfficiency: 0,
      );
    }

    // Group pieces by profile and color
    final Map<String, List<CuttingPiece>> groupedPieces = {};
    for (final piece in pieces) {
      groupedPieces.putIfAbsent(piece.groupKey, () => []).add(piece);
    }

    final groups = <ProfileOptimizationGroup>[];
    int sumBars = 0;
    int sumPieces = 0;
    double sumUsedMeters = 0.0;
    double sumScrapMeters = 0.0;
    double sumUsableRemnantsMeters = 0.0;

    for (final entry in groupedPieces.entries) {
      final list = entry.value;
      if (list.isEmpty) continue;

      final sample = list.first;
      final optimizedBars = _optimizeGroup(
        pieces: list,
        barLengthMm: barLengthMm,
        sawKerfMm: sawKerfMm,
        usableRemnantThresholdMm: usableRemnantThresholdMm,
      );

      double groupUsedMm = 0.0;
      double groupScrapMm = 0.0;
      double groupUsableRemnantMm = 0.0;

      for (final bar in optimizedBars) {
        groupUsedMm += bar.usedLengthMm;
        if (bar.isUsableRemnant) {
          groupUsableRemnantMm += bar.remnantLengthMm;
        } else {
          groupScrapMm += bar.remnantLengthMm;
        }
      }

      final totalPurchasedMm = optimizedBars.length * barLengthMm;
      final groupEfficiency = totalPurchasedMm > 0
          ? ((groupUsedMm + groupUsableRemnantMm) / totalPurchasedMm) * 100.0
          : 0.0;

      final group = ProfileOptimizationGroup(
        profileName: sample.profileName,
        color: sample.color,
        totalPieces: list.length,
        totalRequiredMeters: groupUsedMm / 1000.0,
        barsNeeded: optimizedBars.length,
        bars: optimizedBars,
        totalScrapMeters: groupScrapMm / 1000.0,
        totalUsableRemnantsMeters: groupUsableRemnantMm / 1000.0,
        efficiencyPercentage: groupEfficiency,
      );

      groups.add(group);
      sumBars += optimizedBars.length;
      sumPieces += list.length;
      sumUsedMeters += groupUsedMm / 1000.0;
      sumScrapMeters += groupScrapMm / 1000.0;
      sumUsableRemnantsMeters += groupUsableRemnantMm / 1000.0;
    }

    final double totalAvailableMeters = sumBars * (barLengthMm / 1000.0);
    final double overallEfficiency = totalAvailableMeters > 0
        ? ((sumUsedMeters + sumUsableRemnantsMeters) / totalAvailableMeters) * 100.0
        : 0.0;

    return CuttingOptimizationReport(
      groups: groups,
      totalBars: sumBars,
      totalPieces: sumPieces,
      totalMetersUsed: sumUsedMeters,
      totalMetersScrap: sumScrapMeters,
      totalMetersUsableRemnants: sumUsableRemnantsMeters,
      overallEfficiency: overallEfficiency,
    );
  }

  /// Internal bin packing solver with Best-Fit Decreasing and Chute-Prioritized Lookahead.
  static List<OptimizedBar> _optimizeGroup({
    required List<CuttingPiece> pieces,
    required double barLengthMm,
    required double sawKerfMm,
    required double usableRemnantThresholdMm,
  }) {
    // Sort descending by length
    final sorted = List<CuttingPiece>.from(pieces)
      ..sort((a, b) => b.lengthMm.compareTo(a.lengthMm));

    // Internal simulation bar structure
    final List<_WorkingBar> workingBars = [];

    for (final piece in sorted) {
      if (piece.lengthMm > barLengthMm) {
        // Piece exceeds standard bar length - must be assigned to its own oversized bar
        final bar = _WorkingBar(
          barLengthMm: piece.lengthMm,
          sawKerfMm: sawKerfMm,
          usableThresholdMm: usableRemnantThresholdMm,
        );
        bar.addPiece(piece);
        workingBars.add(bar);
        continue;
      }

      int bestBarIndex = -1;
      double minRemainingSpace = double.infinity;
      int bestChuteBarIndex = -1;
      double minChuteExcess = double.infinity;

      for (int i = 0; i < workingBars.length; i++) {
        final bar = workingBars[i];
        final remaining = bar.availableSpaceAfter(piece.lengthMm);
        if (remaining >= 0) {
          // Check if this placement preserves a usable chute (>= threshold)
          if (remaining >= usableRemnantThresholdMm) {
            final excess = remaining - usableRemnantThresholdMm;
            if (excess < minChuteExcess) {
              minChuteExcess = excess;
              bestChuteBarIndex = i;
            }
          }
          // Standard Best-Fit (minimizing waste)
          if (remaining < minRemainingSpace) {
            minRemainingSpace = remaining;
            bestBarIndex = i;
          }
        }
      }

      // Prioritize preserving a clean usable chute if available, otherwise best tight fit
      final chosenIndex = bestChuteBarIndex != -1
          ? bestChuteBarIndex
          : bestBarIndex;

      if (chosenIndex != -1) {
        workingBars[chosenIndex].addPiece(piece);
      } else {
        // Open a new bar
        final newBar = _WorkingBar(
          barLengthMm: barLengthMm,
          sawKerfMm: sawKerfMm,
          usableThresholdMm: usableRemnantThresholdMm,
        );
        newBar.addPiece(piece);
        workingBars.add(newBar);
      }
    }

    // Convert working bars to immutable OptimizedBar objects
    return List.generate(workingBars.length, (idx) {
      final wb = workingBars[idx];
      return wb.toOptimizedBar(
        barNumber: idx + 1,
        profileName: pieces.first.profileName,
        color: pieces.first.color,
      );
    });
  }
}

class _WorkingBar {
  final double barLengthMm;
  final double sawKerfMm;
  final double usableThresholdMm;
  final List<CuttingPiece> pieces = [];

  _WorkingBar({
    required this.barLengthMm,
    required this.sawKerfMm,
    required this.usableThresholdMm,
  });

  double get usedLengthMm {
    double sum = 0.0;
    for (final p in pieces) {
      sum += p.lengthMm;
    }
    return sum;
  }

  double get totalKerfMm {
    return pieces.length > 1 ? (pieces.length - 1) * sawKerfMm : 0.0;
  }

  double get totalOccupiedMm => usedLengthMm + totalKerfMm;

  double availableSpaceAfter(double newPieceLengthMm) {
    final kerfToAdd = pieces.isNotEmpty ? sawKerfMm : 0.0;
    final needed = newPieceLengthMm + kerfToAdd;
    return (barLengthMm - totalOccupiedMm) - needed;
  }

  void addPiece(CuttingPiece piece) {
    pieces.add(piece);
  }

  OptimizedBar toOptimizedBar({
    required int barNumber,
    required String profileName,
    required String color,
  }) {
    final cuts = <BarCut>[];
    double cursor = 0.0;

    for (int i = 0; i < pieces.length; i++) {
      final p = pieces[i];
      final start = cursor;
      final end = start + p.lengthMm;
      cuts.add(BarCut(piece: p, startMm: start, endMm: end));
      cursor = end + sawKerfMm;
    }

    final used = usedLengthMm;
    final kerf = totalKerfMm;
    final remnant = math.max(0.0, barLengthMm - (used + kerf));
    final isUsable = remnant >= usableThresholdMm;

    return OptimizedBar(
      barNumber: barNumber,
      profileName: profileName,
      color: color,
      barLengthMm: barLengthMm,
      cuts: cuts,
      usedLengthMm: used,
      kerfLossMm: kerf,
      remnantLengthMm: remnant,
      isUsableRemnant: isUsable,
      usableRemnantThresholdMm: usableThresholdMm,
    );
  }
}
