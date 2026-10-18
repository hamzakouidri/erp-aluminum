import 'dart:math' as math;

/// Where a tempered glass accessory is mounted.
class GlassMountTarget {
  static const door = 'door';
  static const fixed = 'fixed';

  /// On the wall or frame, drilled into the glass edge it holds.
  static const frame = 'frame';

  /// Joins a fixed panel and a door: drilled in both.
  static const between = 'between';
  static const all = 'all';

  static const values = [all, door, fixed, frame, between];

  /// Whether an accessory mounted on [target] can be drilled in a panel of
  /// [panelRole] ('door' or 'fixed').
  static bool fitsPanel(String target, String panelRole) {
    switch (target) {
      case door:
        return panelRole == 'door';
      case fixed:
        return panelRole != 'door';
      default:
        return true;
    }
  }
}

/// Gasket families of tempered glass doors and showers. Every gasket is sold
/// by the piece, except the one fitted between a profile and the glass,
/// which is sold by the metre.
class GlassGasketType {
  static const magnetic90 = 'magnetic_90';
  static const magnetic180 = 'magnetic_180';
  static const h = 'h';
  static const f = 'f';
  static const bulb = 'bombe';
  static const rail = 'rail';

  static const values = [magnetic90, magnetic180, h, f, bulb, rail];

  static bool soldByMetre(String type) => type == rail;
}

/// Where a gasket is fitted on a door.
class GlassGasketLocation {
  /// Door edge on the wall side.
  static const doorWall = 'door_wall';

  /// Between a fixed panel and the door (fitted on both).
  static const doorFixed = 'door_fixed';

  /// Between a profile (U channel, top rail) and the glass it holds.
  static const profile = 'profile';

  static const values = [doorWall, doorFixed, profile];
}

/// Role of a profile in a tempered glass layout.
class GlassProfileRole {
  /// U channel (baguette) holding a fixed glass edge.
  static const uChannel = 'u_channel';

  /// Rail above the glass: the fixed glass enters it, the door slides along.
  static const topRail = 'top_rail';

  static const values = [uChannel, topRail];
}

/// One hole of an accessory, relative to its first hole.
class GlassAccessoryHole {
  const GlassAccessoryHole({
    required this.dxMm,
    required this.dyMm,
    required this.diameterMm,
  });

  final double dxMm;
  final double dyMm;
  final double diameterMm;
}

/// The drilling pattern of a catalogue accessory (TemperedGlassItems row):
/// how many holes, the diameter of each, the centre distance between each
/// hole and the next, their direction, where it is mounted and the glass
/// thickness it is made for.
class GlassAccessoryTemplate {
  const GlassAccessoryTemplate({
    required this.holeDiameters,
    required this.holeSpacings,
    this.vertical = false,
    this.mountTarget = GlassMountTarget.all,
    this.glassThicknessMm = 0,
  });

  /// Reads the pattern from a TemperedGlassItems row. The per-hole lists
  /// fall back to the item's single `entraxe`, and a missing diameter
  /// repeats the previous one.
  factory GlassAccessoryTemplate.fromItem(Map<String, dynamic> item) {
    final count = (item['holes_count'] as num?)?.toInt() ?? 0;
    final diameters = parseMillimetreList(item['hole_diameters']);
    final spacings = parseMillimetreList(item['hole_spacings']);
    final entraxe = (item['entraxe'] as num?)?.toDouble() ?? 0.0;
    final resolvedDiameters = <double>[];
    for (var i = 0; i < count; i++) {
      if (i < diameters.length) {
        resolvedDiameters.add(diameters[i]);
      } else if (resolvedDiameters.isNotEmpty) {
        resolvedDiameters.add(resolvedDiameters.last);
      } else {
        resolvedDiameters.add(12.0);
      }
    }
    final resolvedSpacings = <double>[];
    for (var i = 0; i < math.max(0, count - 1); i++) {
      if (i < spacings.length) {
        resolvedSpacings.add(spacings[i]);
      } else if (spacings.isNotEmpty) {
        resolvedSpacings.add(spacings.last);
      } else {
        resolvedSpacings.add(entraxe);
      }
    }
    return GlassAccessoryTemplate(
      holeDiameters: resolvedDiameters,
      holeSpacings: resolvedSpacings,
      vertical: item['hole_layout']?.toString() == 'vertical',
      mountTarget: GlassMountTarget.values.contains(item['mount_target'])
          ? item['mount_target'].toString()
          : GlassMountTarget.all,
      glassThicknessMm:
          (item['glass_thickness_mm'] as num?)?.toDouble() ?? 0.0,
    );
  }

  final List<double> holeDiameters;
  final List<double> holeSpacings;
  final bool vertical;
  final String mountTarget;

  /// 0 means any thickness.
  final double glassThicknessMm;

  int get holeCount => holeDiameters.length;

  /// Distance from the first hole centre to the last one.
  double get spanMm => holeSpacings.fold(0.0, (a, b) => a + b);

  bool fitsThickness(double thicknessMm) =>
      glassThicknessMm <= 0 || (glassThicknessMm - thicknessMm).abs() < 0.5;

  /// The holes, each relative to the first hole centre, along the
  /// accessory's direction.
  List<GlassAccessoryHole> holes() {
    final result = <GlassAccessoryHole>[];
    var offset = 0.0;
    for (var i = 0; i < holeDiameters.length; i++) {
      if (i > 0) offset += holeSpacings[i - 1];
      result.add(
        GlassAccessoryHole(
          dxMm: vertical ? 0 : offset,
          dyMm: vertical ? offset : 0,
          diameterMm: holeDiameters[i],
        ),
      );
    }
    return result;
  }

  /// Whether every hole fits in a [widthMm] × [heightMm] glass when the
  /// first hole centre is at ([xMm], [yMm]).
  bool fitsGlass({
    required double widthMm,
    required double heightMm,
    required double xMm,
    required double yMm,
  }) {
    for (final hole in holes()) {
      final r = hole.diameterMm / 2;
      final x = xMm + hole.dxMm;
      final y = yMm + hole.dyMm;
      if (x - r < 0 || x + r > widthMm || y - r < 0 || y + r > heightMm) {
        return false;
      }
    }
    return true;
  }
}

/// Parses "12, 12;10" into [12, 12, 10]. Invalid or non-positive values are
/// skipped.
List<double> parseMillimetreList(Object? value) {
  final text = value?.toString() ?? '';
  return text
      .split(RegExp(r'[;,\s]+'))
      .map((part) => double.tryParse(part.trim()))
      .whereType<double>()
      .where((v) => v > 0)
      .toList();
}

/// Profiles of a sliding shower: the fixed glass stands in a U channel at
/// the bottom and on the wall side, and its top enters the rail by
/// [railInsertionMm]; the door hangs beside it, reaching the rail through its
/// extra height.
class SlidingGlassProfiles {
  const SlidingGlassProfiles({
    required this.fixedWidthMm,
    required this.fixedHeightMm,
    required this.overallWidthMm,
    this.railInsertionMm = defaultRailInsertionMm,
  });

  static const defaultRailInsertionMm = 15.0;

  final double fixedWidthMm;
  final double fixedHeightMm;
  final double overallWidthMm;
  final double railInsertionMm;

  /// U channel under the fixed glass.
  double get bottomChannelMm => fixedWidthMm;

  /// U channel along the fixed glass on the wall side, below the rail.
  double get wallChannelMm => math.max(0.0, fixedHeightMm - railInsertionMm);

  double get uChannelMm => bottomChannelMm + wallChannelMm;

  /// Rail across the whole opening.
  double get topRailMm => overallWidthMm;

  /// Gasket between the profiles and the fixed glass: wherever the glass
  /// enters a profile (both U channels and the rail along the fixed glass).
  double get profileGasketMm => uChannelMm + fixedWidthMm;
}
