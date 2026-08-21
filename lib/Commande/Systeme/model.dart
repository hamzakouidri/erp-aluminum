// Force compile sync trigger 2
import 'dart:math' as math;
import 'dart:async';
import 'package:flutter/material.dart';
import '../../sql_database.dart';

enum DimensionTap { none, width, height }

/// SQLite returns `Map<String, Object?>` rows.  Calls made through a dynamic
/// database handle can otherwise preserve a lazy `MappedListIterable` whose
/// runtime generic type is not compatible with `Map<String, dynamic>`.
/// Materialize and normalize the rows before passing them to typed helpers.
List<Map<String, dynamic>> normalizeDatabaseRows(dynamic rawRows) {
  if (rawRows is! Iterable) return <Map<String, dynamic>>[];
  return rawRows
      .whereType<Map>()
      .map<Map<String, dynamic>>((row) => Map<String, dynamic>.from(row))
      .toList(growable: false);
}

enum LockType { none, clef, condamnation, point, rouleau, cremone, rouleau2000 }

enum ZoneContent { empty, fixedGlass, singleSash, doubleSash, slidingSash }

enum GlassStructure { simple, double, closed }

/// Resolves the catalogue unit price of a shutter component.
///
/// Component rows can legitimately keep a zero base price while their real
/// price is stored in ShutterColorPrices. Prefer the selected colour, then the
/// grey base colour, then the compatibility mirror on the component row.
double resolveShutterComponentUnitPrice({
  required Map<String, dynamic> component,
  required Iterable<Map<String, dynamic>> colorPrices,
  int? selectedColorId,
  int? fallbackColorId,
}) {
  double readNumber(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString().replaceAll(',', '.') ?? '') ?? 0.0;
  }

  final componentId = component['id'] is num
      ? (component['id'] as num).toInt()
      : int.tryParse('${component['id'] ?? ''}');
  final matchingPrices = colorPrices.where((row) {
    final rawId = row['shutter_component_id'];
    final id = rawId is num ? rawId.toInt() : int.tryParse('$rawId');
    return componentId != null && id == componentId;
  }).toList();

  if (selectedColorId != null) {
    for (final row in matchingPrices) {
      final rawColorId = row['color_id'];
      final colorId = rawColorId is num
          ? rawColorId.toInt()
          : int.tryParse('$rawColorId');
      final price = readNumber(row['price']);
      if (colorId == selectedColorId && price > 0) return price;
    }
  }

  if (fallbackColorId != null) {
    for (final row in matchingPrices) {
      final rawColorId = row['color_id'];
      final colorId = rawColorId is num
          ? rawColorId.toInt()
          : int.tryParse('$rawColorId');
      final price = readNumber(row['price']);
      if (colorId == fallbackColorId && price > 0) return price;
    }
  }

  for (final key in const ['price_dzd', 'price_per_meter', 'price']) {
    final price = readNumber(component[key]);
    if (price > 0) return price;
  }
  // When the caller has supplied the grey base colour, a price belonging to
  // some unrelated colour must not be used as a substitute.  Zero therefore
  // remains an explicit missing-price signal for the required-goods table.
  if (fallbackColorId != null) return 0.0;
  for (final row in matchingPrices) {
    final price = readNumber(row['price']);
    if (price > 0) return price;
  }
  return 0.0;
}

class ShutterBoxResolution {
  const ShutterBoxResolution({
    required this.boxSize,
    required this.exceedsAllLimits,
    required this.maximumSupportedHeight,
  });

  final double boxSize;
  final bool exceedsAllLimits;
  final double maximumSupportedHeight;
}

/// Short codes saved in `KitBundles.description`. They are the stable source
/// of truth for kit purpose; names remain free commercial labels.
String normalizeKitDescriptionCode(dynamic raw) {
  return (raw ?? '').toString().trim().toUpperCase().replaceAll(
    RegExp(r'[\s,;:_-]+'),
    '',
  );
}

bool kitHasDescriptionCode(Map<String, dynamic> kit, String expectedCode) {
  return normalizeKitDescriptionCode(kit['description']) ==
      normalizeKitDescriptionCode(expectedCode);
}

String shutterKitCodeForMechanism(String mechanism) {
  final normalized = mechanism.trim().toLowerCase();
  if (normalized == 'محرك' || normalized.contains('moteur')) return 'MT';
  // V is the common shutter kit for belt and crank assemblies. M identifies
  // the separate crank-only tool kit, not the main shutter kit.
  return 'V';
}

bool isShutterKitForMechanism(
  Map<String, dynamic> kit,
  String mechanism, {
  bool tunnel = false,
}) {
  return kitHasDescriptionCode(
    kit,
    tunnel ? 'CT' : shutterKitCodeForMechanism(mechanism),
  );
}

double? kitBundleSizeMm(Map<String, dynamic> kit) {
  for (final field in const ['measurement', 'name']) {
    final value = (kit[field] ?? '').toString();
    final matches = RegExp(
      r'(?<!\d)(\d{2,3}(?:[.,]\d+)?)(?!\d)',
    ).allMatches(value).toList();
    if (matches.isEmpty) continue;
    var size = double.tryParse(matches.last.group(1)!.replaceAll(',', '.'));
    if (size == null || size <= 0) continue;
    if ((size - 15.5).abs() < 0.01) size = 155;
    if ((size - 18.5).abs() < 0.01) size = 185;
    if ((size - 20.5).abs() < 0.01) size = 205;
    if ((size - 15).abs() < 0.01) size = 150;
    if ((size - 18).abs() < 0.01) size = 180;
    if ((size - 20).abs() < 0.01) size = 200;
    if (size < 100) size *= 10;
    return size;
  }
  return null;
}

List<Map<String, dynamic>> compatibleKitBundles({
  required Iterable<Map<String, dynamic>> kits,
  required String descriptionCode,
  double? minimumSizeMm,
  bool allowWithoutSize = false,
}) {
  final result = kits
      .where((kit) {
        if (!kitHasDescriptionCode(kit, descriptionCode)) return false;
        final size = kitBundleSizeMm(kit);
        if (size == null) return allowWithoutSize;
        return minimumSizeMm == null || size + 0.5 >= minimumSizeMm;
      })
      .map(Map<String, dynamic>.from)
      .toList();
  result.sort((a, b) {
    final aSize = kitBundleSizeMm(a) ?? double.infinity;
    final bSize = kitBundleSizeMm(b) ?? double.infinity;
    final sizeCompare = aSize.compareTo(bSize);
    if (sizeCompare != 0) return sizeCompare;
    return (a['name'] ?? '').toString().compareTo((b['name'] ?? '').toString());
  });
  return result;
}

/// The number of ordinary hinges is based on the height of the actual sash.
/// Double glazing only adds one hinge from 1800 mm upwards; it must not add a
/// hinge to every double-glazed sash regardless of its height.
int standardHingeCountForSash({
  required double sashHeight,
  required GlassStructure glassStructure,
}) {
  var hingeCount = sashHeight > 2100
      ? 4
      : sashHeight > 1000
      ? 3
      : 2;
  if (glassStructure == GlassStructure.double && sashHeight >= 1800) {
    hingeCount += 1;
  }
  return hingeCount;
}

enum GlassFinish {
  clair,
  stopSol,
  sable,
  delta,
  tuC,
  nevada,
  cuisine,
  aFleur,
  paneauSandwitch,
  resine,
  paneauSandwitchDecore,
  plexyGlass,
  bardage,
  moussa,
  harari,
  vitrageArme,
}

bool isDecorPanelSubtype(String? subtype) {
  final normalized = (subtype ?? '').trim().toLowerCase();
  return normalized.contains('decor') ||
      normalized.contains('décor') ||
      normalized.contains('ديكور');
}

bool decorPanelFitsSpace({
  required double spaceWidth,
  required double spaceHeight,
  required double decorWidth,
  required double decorHeight,
}) {
  if (spaceWidth <= 0 ||
      spaceHeight <= 0 ||
      decorWidth <= 0 ||
      decorHeight <= 0) {
    return false;
  }
  // A decor drawing has a fixed orientation. It is not rotated or split to
  // force it into a smaller opening.
  return decorWidth <= spaceWidth + 0.1 && decorHeight <= spaceHeight + 0.1;
}

enum GlassColor { transparent, blue, brown, green, gray, grayAgc, blueAgc }

enum ClosedGlassColor {
  marberier,
  transparent,
  opaque,
  white,
  grisClair,
  grissoris,
  black,
  fbmClair,
  fbmfonce,
  beige,
}

enum GlassProcessing { none, tempered, laminated, lowE }

enum OpenDirection { left, right, top, bottom }

enum FrameColor { white, brown, gray, black, beige, gris, antique, lightWood }

enum SelectionType { zone, mullion, innerDivision, frame }

enum MullionProfileType { standard, flat, grooved }

/// A custom visible cover segment on one outer frame side. The offsets are
/// always stored from the top (vertical sides) or the left (horizontal sides)
/// so the same drawing remains stable after it is saved and restored.
class SideCoverSegment {
  final String side;
  final double startOffset;
  final double endOffset;
  final double visibleWidth;

  const SideCoverSegment({
    required this.side,
    required this.startOffset,
    required this.endOffset,
    required this.visibleWidth,
  });

  double get length => math.max(0.0, endOffset - startOffset);

  SideCoverSegment copyWith({
    String? side,
    double? startOffset,
    double? endOffset,
    double? visibleWidth,
  }) => SideCoverSegment(
    side: side ?? this.side,
    startOffset: startOffset ?? this.startOffset,
    endOffset: endOffset ?? this.endOffset,
    visibleWidth: visibleWidth ?? this.visibleWidth,
  );

  Map<String, dynamic> toMap() => {
    'side': side,
    'startOffset': startOffset,
    'endOffset': endOffset,
    'visibleWidth': visibleWidth,
  };

  factory SideCoverSegment.fromMap(Map<String, dynamic> map) {
    double readDouble(String key) {
      final value = map[key];
      return value is num
          ? value.toDouble()
          : double.tryParse(value?.toString() ?? '') ?? 0.0;
    }

    return SideCoverSegment(
      side: map['side']?.toString().toLowerCase() ?? 'right',
      startOffset: readDouble('startOffset'),
      endOffset: readDouble('endOffset'),
      visibleWidth: readDouble('visibleWidth'),
    );
  }
}

class AluminumSection {
  final int id;
  final int seriesId;
  final String code;
  final String name;
  final String type;
  final double thickness;
  final double glassDeduction;
  final double weightPerMeter;
  final double couvreJointWidth;
  final double couvreJointThickness;
  final double cuttingDeduction;
  final double visibleWidth;
  final double visibleWidth2;
  final double sashOverlap;
  final double barLength;
  final bool isFrame;
  final bool isSash;
  final bool isMullion;
  final double maxGlassThickness;
  final int? linkedParcloseDoubleId;
  final String? imagePath;
  final bool allowsSideCover;

  AluminumSection({
    required this.id,
    required this.seriesId,
    required this.code,
    required this.name,
    required this.type,
    double thickness = 0.0,
    double? profileThickness,
    this.glassDeduction = 0.0,
    this.weightPerMeter = 0.0,
    this.couvreJointWidth = 0.0,
    this.couvreJointThickness = 0.0,
    this.cuttingDeduction = 0.0,
    this.visibleWidth = 0.0,
    this.visibleWidth2 = 0.0,
    this.sashOverlap = 0.0,
    this.barLength = 6.0,
    this.isFrame = false,
    this.isSash = false,
    this.isMullion = false,
    this.maxGlassThickness = 0.0,
    this.linkedParcloseDoubleId,
    this.imagePath,
    this.allowsSideCover = true,
  }) : thickness = profileThickness ?? thickness;

  factory AluminumSection.fromMap(Map<String, dynamic> map) {
    return AluminumSection(
      id: map['id'],
      seriesId: map['series_id'],
      code: map['code'],
      name: map['name'],
      type: map['type'],
      thickness: (map['thickness'] as num?)?.toDouble() ?? 0.0,
      glassDeduction: (map['glass_deduction'] as num?)?.toDouble() ?? 0.0,
      weightPerMeter: (map['weight_per_meter'] as num?)?.toDouble() ?? 0.0,
      couvreJointWidth: (map['couvre_joint_width'] as num?)?.toDouble() ?? 0.0,
      couvreJointThickness:
          (map['couvre_joint_thickness'] as num?)?.toDouble() ?? 0.0,
      cuttingDeduction: (map['cutting_deduction'] as num?)?.toDouble() ?? 0.0,
      visibleWidth: (map['visible_width'] as num?)?.toDouble() ?? 0.0,
      visibleWidth2: (map['visible_width_2'] as num?)?.toDouble() ?? 0.0,
      sashOverlap: (map['sash_overlap'] as num?)?.toDouble() ?? 0.0,
      barLength: (map['bar_length'] as num?)?.toDouble() ?? 6.0,
      isFrame: (map['is_frame'] as int?) == 1,
      isSash: (map['is_sash'] as int?) == 1,
      isMullion: (map['is_mullion'] as int?) == 1,
      maxGlassThickness:
          (map['max_glass_thickness'] as num?)?.toDouble() ?? 0.0,
      linkedParcloseDoubleId: map['linked_parclose_double_id'] as int?,
      imagePath: map['image_path']?.toString(),
      allowsSideCover: (map['allows_side_cover'] as int?) != 0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'series_id': seriesId,
      'code': code,
      'name': name,
      'type': type,
      'thickness': thickness,
      'glass_deduction': glassDeduction,
      'weight_per_meter': weightPerMeter,
      'couvre_joint_width': couvreJointWidth,
      'couvre_joint_thickness': couvreJointThickness,
      'cutting_deduction': cuttingDeduction,
      'visible_width': visibleWidth,
      'visible_width_2': visibleWidth2,
      'sash_overlap': sashOverlap,
      'bar_length': barLength,
      'is_frame': isFrame ? 1 : 0,
      'is_sash': isSash ? 1 : 0,
      'is_mullion': isMullion ? 1 : 0,
      'max_glass_thickness': maxGlassThickness,
      'linked_parclose_double_id': linkedParcloseDoubleId,
      'image_path': imagePath,
      'allows_side_cover': allowsSideCover ? 1 : 0,
    };
  }
}

class AluminumSeries {
  final int id;
  final int profileId;
  final String name;
  final String type;
  final bool hasThreePieceSash;
  List<AluminumSection> sections;

  AluminumSeries({
    required this.id,
    required this.profileId,
    required this.name,
    required this.type,
    this.hasThreePieceSash = false,
    List<AluminumSection>? sections,
  }) : sections = sections ?? [];

  factory AluminumSeries.fromMap(Map<String, dynamic> map) {
    return AluminumSeries(
      id: map['id'],
      profileId: map['profile_id'],
      name: map['name'],
      type: map['type'],
      hasThreePieceSash: (map['has_three_piece_sash'] ?? 0) == 1,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AluminumSeries &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}

class AluminumProfileSystem {
  final int id;
  final String name;
  final String type;
  List<AluminumSeries> series;

  AluminumProfileSystem({
    required this.id,
    required this.name,
    required this.type,
    List<AluminumSeries>? series,
  }) : series = series ?? [];

  factory AluminumProfileSystem.fromMap(Map<String, dynamic> map) {
    return AluminumProfileSystem(
      id: map['id'],
      name: map['name'],
      type: map['type'],
    );
  }
}

/// Series type is the source of truth for the drawing mode. Profile names are
/// commercial labels (for example, Brolex), so they must not decide whether a
/// series belongs to the sliding or opening drawing.
bool isSlidingSeriesForDrawing(AluminumSeries series) {
  final value = '${series.type} ${series.name}'.toLowerCase().trim();
  return value.contains('couliss') ||
      value.contains('sliding') ||
      value.contains('منزلق') ||
      value.contains('جرار') ||
      value.contains('كوليس');
}

bool isOpeningSeriesForDrawing(
  AluminumSeries series,
  AluminumProfileSystem profile,
) {
  final value = '${series.type} ${series.name}'.toLowerCase().trim();
  final isOpening =
      value.contains('frappe') ||
      value.contains('battant') ||
      value.contains('ouvrant') ||
      value.contains('فتح') ||
      value.contains('فرنسي');
  if (isOpening) return true;

  // Legacy PVC catalogues can have an unlabeled opening series. Treat it as
  // opening only when it is not explicitly a sliding series.
  return profile.type.toLowerCase().contains('pvc') &&
      !isSlidingSeriesForDrawing(series);
}

bool seriesMatchesDrawingMode(
  AluminumSeries series,
  AluminumProfileSystem profile,
  String mode,
) {
  switch (mode) {
    case 'sliding':
      return isSlidingSeriesForDrawing(series);
    case 'french':
      return isOpeningSeriesForDrawing(series, profile);
    case 'mixed':
      return isSlidingSeriesForDrawing(series) ||
          isOpeningSeriesForDrawing(series, profile);
    default:
      return true;
  }
}

class InnerDimensionHit {
  final String zoneId;
  final bool isWidth;
  final bool isDoubleSashLeft;
  final bool isDoubleSashRight;
  final bool isSashDivision;
  final bool isHorizontalDivision;
  final int divisionIndex;

  InnerDimensionHit(
    this.zoneId,
    this.isWidth, {
    this.isDoubleSashLeft = false,
    this.isDoubleSashRight = false,
    this.isSashDivision = false,
    this.isHorizontalDivision = false,
    this.divisionIndex = 0,
  });
}

class GlassSpecification {
  final GlassStructure structure;
  final GlassFinish finishOuter;
  final GlassFinish finishInner;
  final GlassColor colorOuter;
  final GlassColor colorInner;
  final GlassProcessing processingOuter;
  final GlassProcessing processingInner;
  final bool temperedOuter;
  final bool temperedInner;
  final ClosedGlassColor colorP;
  final bool hasGas;
  final int intercallThickness;
  final int decorH;
  final int decorV;
  final List<double> decorHPositions;
  final List<double> decorVPositions;
  final double? thicknessOuter;
  final double? thicknessInner;
  final String laminatedColorOuter; // 'transparent', 'white', 'blue'
  final String laminatedColorInner; // 'transparent', 'white', 'blue'
  final String decorColor; // 'white', 'gold', 'silver', 'grey'
  final double decorThickness; // 6.0 or 10.0
  final bool hasRosettes;
  final String? panneauSubtype;
  final String? panneauColor;
  final int? decorBaguetteId;
  final int? decorRosetteId;
  final bool isVerticalBardage;
  final bool bardageUsesFrameColor;
  final int? panneauProductId;
  final int rosetteShape;
  final bool jointTwoSides;

  const GlassSpecification({
    this.structure = GlassStructure.simple,
    this.finishOuter = GlassFinish.clair,
    this.finishInner = GlassFinish.clair,
    this.colorOuter = GlassColor.transparent,
    this.colorInner = GlassColor.transparent,
    this.processingOuter = GlassProcessing.none,
    this.processingInner = GlassProcessing.none,
    this.temperedOuter = false,
    this.temperedInner = false,
    this.colorP = ClosedGlassColor.white,
    this.hasGas = false,
    this.intercallThickness = 12,
    this.decorH = 0,
    this.decorV = 0,
    this.decorHPositions = const [],
    this.decorVPositions = const [],
    this.decorColor = 'white',
    this.decorThickness = 6.0,
    this.hasRosettes = false,
    this.panneauSubtype,
    this.panneauColor,
    this.decorBaguetteId,
    this.decorRosetteId,
    this.isVerticalBardage = false,
    this.bardageUsesFrameColor = true,
    this.panneauProductId,
    this.thicknessOuter,
    this.thicknessInner,
    this.laminatedColorOuter = 'transparent',
    this.laminatedColorInner = 'transparent',
    this.rosetteShape = 1,
    this.jointTwoSides = true,
  });

  GlassSpecification clone() => GlassSpecification(
    structure: structure,
    finishOuter: finishOuter,
    finishInner: finishInner,
    colorOuter: colorOuter,
    colorInner: colorInner,
    processingOuter: processingOuter,
    processingInner: processingInner,
    temperedOuter: temperedOuter,
    temperedInner: temperedInner,
    colorP: colorP,
    hasGas: hasGas,
    intercallThickness: intercallThickness,
    decorH: decorH,
    decorV: decorV,
    decorHPositions: List.from(decorHPositions),
    decorVPositions: List.from(decorVPositions),
    decorColor: decorColor,
    decorThickness: decorThickness,
    hasRosettes: hasRosettes,
    panneauSubtype: panneauSubtype,
    panneauColor: panneauColor,
    decorBaguetteId: decorBaguetteId,
    decorRosetteId: decorRosetteId,
    isVerticalBardage: isVerticalBardage,
    bardageUsesFrameColor: bardageUsesFrameColor,
    panneauProductId: panneauProductId,
    thicknessOuter: thicknessOuter,
    thicknessInner: thicknessInner,
    laminatedColorOuter: laminatedColorOuter,
    laminatedColorInner: laminatedColorInner,
    rosetteShape: rosetteShape,
    jointTwoSides: jointTwoSides,
  );

  GlassSpecification copyWith({
    GlassStructure? structure,
    GlassFinish? finishOuter,
    GlassFinish? finishInner,
    GlassColor? colorOuter,
    GlassColor? colorInner,
    GlassProcessing? processingOuter,
    GlassProcessing? processingInner,
    bool? temperedOuter,
    bool? temperedInner,
    ClosedGlassColor? colorP,
    bool? hasGas,
    int? intercallThickness,
    int? decorH,
    int? decorV,
    List<double>? decorHPositions,
    List<double>? decorVPositions,
    String? decorColor,
    double? decorThickness,
    bool? hasRosettes,
    String? panneauSubtype,
    String? panneauColor,
    int? decorBaguetteId,
    int? decorRosetteId,
    bool? isVerticalBardage,
    bool? bardageUsesFrameColor,
    int? panneauProductId,
    double? thicknessOuter,
    double? thicknessInner,
    String? laminatedColorOuter,
    String? laminatedColorInner,
    int? rosetteShape,
    bool? jointTwoSides,
  }) => GlassSpecification(
    structure: structure ?? this.structure,
    finishOuter: finishOuter ?? this.finishOuter,
    finishInner: finishInner ?? this.finishInner,
    colorOuter: colorOuter ?? this.colorOuter,
    colorInner: colorInner ?? this.colorInner,
    processingOuter: processingOuter ?? this.processingOuter,
    processingInner: processingInner ?? this.processingInner,
    temperedOuter: temperedOuter ?? this.temperedOuter,
    temperedInner: temperedInner ?? this.temperedInner,
    colorP: colorP ?? this.colorP,
    hasGas: hasGas ?? this.hasGas,
    intercallThickness: intercallThickness ?? this.intercallThickness,
    decorH: decorH ?? this.decorH,
    decorV: decorV ?? this.decorV,
    decorHPositions: decorHPositions ?? this.decorHPositions,
    decorVPositions: decorVPositions ?? this.decorVPositions,
    decorColor: decorColor ?? this.decorColor,
    decorThickness: decorThickness ?? this.decorThickness,
    hasRosettes: hasRosettes ?? this.hasRosettes,
    panneauSubtype: panneauSubtype ?? this.panneauSubtype,
    panneauColor: panneauColor ?? this.panneauColor,
    decorBaguetteId: decorBaguetteId ?? this.decorBaguetteId,
    decorRosetteId: decorRosetteId ?? this.decorRosetteId,
    isVerticalBardage: isVerticalBardage ?? this.isVerticalBardage,
    bardageUsesFrameColor: bardageUsesFrameColor ?? this.bardageUsesFrameColor,
    panneauProductId: panneauProductId ?? this.panneauProductId,
    thicknessOuter: thicknessOuter ?? this.thicknessOuter,
    thicknessInner: thicknessInner ?? this.thicknessInner,
    laminatedColorOuter: laminatedColorOuter ?? this.laminatedColorOuter,
    laminatedColorInner: laminatedColorInner ?? this.laminatedColorInner,
    rosetteShape: rosetteShape ?? this.rosetteShape,
    jointTwoSides: jointTwoSides ?? this.jointTwoSides,
  );

  /// Compares all visible choices from the glass drawer, including panel and
  /// decorative details.  The drawer can therefore safely preselect a value
  /// only when every glass cell uses the same configuration.
  bool hasSameConfigurationAs(GlassSpecification other) {
    return structure == other.structure &&
        finishOuter == other.finishOuter &&
        finishInner == other.finishInner &&
        colorOuter == other.colorOuter &&
        colorInner == other.colorInner &&
        processingOuter == other.processingOuter &&
        processingInner == other.processingInner &&
        temperedOuter == other.temperedOuter &&
        temperedInner == other.temperedInner &&
        colorP == other.colorP &&
        hasGas == other.hasGas &&
        intercallThickness == other.intercallThickness &&
        decorH == other.decorH &&
        decorV == other.decorV &&
        _sameDoubleList(decorHPositions, other.decorHPositions) &&
        _sameDoubleList(decorVPositions, other.decorVPositions) &&
        thicknessOuter == other.thicknessOuter &&
        thicknessInner == other.thicknessInner &&
        laminatedColorOuter == other.laminatedColorOuter &&
        laminatedColorInner == other.laminatedColorInner &&
        decorColor == other.decorColor &&
        decorThickness == other.decorThickness &&
        hasRosettes == other.hasRosettes &&
        panneauSubtype == other.panneauSubtype &&
        panneauColor == other.panneauColor &&
        decorBaguetteId == other.decorBaguetteId &&
        decorRosetteId == other.decorRosetteId &&
        isVerticalBardage == other.isVerticalBardage &&
        bardageUsesFrameColor == other.bardageUsesFrameColor &&
        panneauProductId == other.panneauProductId &&
        rosetteShape == other.rosetteShape &&
        jointTwoSides == other.jointTwoSides;
  }

  static bool _sameDoubleList(List<double> first, List<double> second) {
    if (first.length != second.length) return false;
    for (var index = 0; index < first.length; index++) {
      if (first[index] != second[index]) return false;
    }
    return true;
  }

  String get displayName {
    if (structure == GlassStructure.closed) return '';
    if (structure == GlassStructure.double) {
      final tOut = (thicknessOuter ?? 4.0).toStringAsFixed(0);
      final tIn = (thicknessInner ?? 4.0).toStringAsFixed(0);
      final tInter = intercallThickness.toStringAsFixed(0);
      return '$tOut+$tInter+$tIn';
    } else {
      final tOut = (thicknessOuter ?? 5.0).toStringAsFixed(0);
      return '$tOut مم';
    }
  }

  // 🟢 استرجاع سماكة البانو الفعلية من قاعدة البيانات
  double getPanelThickness(List<Map<String, dynamic>> allGlassCache) {
    int? resolvedId = panneauProductId;
    if (resolvedId == null) {
      if (panneauSubtype != null && panneauSubtype!.isNotEmpty) {
        final match = allGlassCache.firstWhere(
          (g) =>
              g['type'].toString().toLowerCase() == 'panneau' &&
              (g['subtype']?.toString().toLowerCase() ==
                      panneauSubtype!.toLowerCase() ||
                  g['name'].toString().toLowerCase().contains(
                    panneauSubtype!.toLowerCase(),
                  )),
          orElse: () => <String, dynamic>{},
        );
        if (match.isNotEmpty) {
          final double? thick = (match['thickness'] as num?)?.toDouble();
          if (thick != null && thick > 0) return thick;
        }
      }

      final List<String> finishKws;
      switch (finishOuter) {
        case GlassFinish.resine:
          finishKws = const ['ارزين', 'resine', 'résine', 'أرزين'];
          break;
        case GlassFinish.plexyGlass:
          finishKws = const ['بليكسي', 'plexy', 'plexiglas', 'plexiglass'];
          break;
        case GlassFinish.paneauSandwitch:
          finishKws = const ['بانو', 'paneau', 'sandwich', 'sandwitch'];
          break;
        case GlassFinish.paneauSandwitchDecore:
          finishKws = const ['بانو ديكور', 'paneau decore', 'sandwich decore'];
          break;
        case GlassFinish.bardage:
          finishKws = const ['بارداج', 'bardage'];
          break;
        default:
          finishKws = const [];
      }

      final match = allGlassCache.firstWhere(
        (g) =>
            g['type'].toString().toLowerCase() == 'panneau' &&
            finishKws.any(
              (kw) =>
                  g['type'].toString().toLowerCase().contains(kw) ||
                  g['name'].toString().toLowerCase().contains(kw),
            ),
        orElse: () => <String, dynamic>{},
      );
      if (match.isNotEmpty) {
        final double? thick = (match['thickness'] as num?)?.toDouble();
        if (thick != null && thick > 0) return thick;
      }

      return 0.0;
    }

    final match = allGlassCache.firstWhere(
      (g) => g['id'] == resolvedId,
      orElse: () => <String, dynamic>{},
    );
    if (match.isNotEmpty) {
      final double? thick = (match['thickness'] as num?)?.toDouble();
      if (thick != null && thick > 0) return thick;
    }

    return 0.0;
  }

  double totalThickness(List<Map<String, dynamic>> allGlassCache) {
    if (structure == GlassStructure.double) {
      final tOut = thicknessOuter ?? 4.0;
      final tIn = thicknessInner ?? 4.0;
      return tOut + intercallThickness.toDouble() + tIn;
    } else if (structure == GlassStructure.closed) {
      return getPanelThickness(allGlassCache);
    } else {
      return thicknessOuter ?? 5.0;
    }
  }
}

class WindowZone {
  final String id;
  double? handlePositionRatio;
  bool useClassicHandle;
  bool useOctoHandle;
  bool usePvcHandleOnAlu;
  Rect boundary;
  ZoneContent content;
  bool isSelected;
  GlassSpecification glass;
  double openAngle;
  OpenDirection? openDirection;
  FrameColor sashColor;
  Map<String, dynamic>? selectedDbColor;
  bool isSash105;
  double? sashThickness;
  int innerH;
  int innerV;
  int slidingSashesCount;
  bool cutSlidingGlassRebate;
  int rightInnerH;
  int rightInnerV;
  List<double> innerHPositions;
  List<double> innerVPositions;
  List<double> rightInnerHPositions;
  List<double> rightInnerVPositions;
  Map<String, bool> cellIsPanel;
  Map<String, bool> cellIsSash;
  Map<String, bool> cellIsDoubleSash;
  Map<String, Map<String, dynamic>> cellSashOverrides;
  LockType lockType;
  Map<String, bool> slidingMontantReinforced;
  double middleHingeDragOffset;
  double doubleSashRatio;

  /// Whether the exceptional two-handle configuration is enabled.
  /// A double sash normally has a handle only on its active leaf.
  bool doubleSashHasTwoHandles;
  Map<String, bool> disabledVerticalDivisions;
  Map<String, bool> disabledHorizontalDivisions;
  String? primaryDivisionAxis;
  String? rightPrimaryDivisionAxis;
  bool isSubdivided;
  bool hasSashPlintheBottom;

  /// Per-cell glass overrides — key is cellKey like 'main_cell_0_0'
  Map<String, GlassSpecification> cellGlassSpec;

  static GlassSpecification globalDefaultGlass = const GlassSpecification();

  /// Returns the glass specification for a given cell, falling back to zone.glass
  GlassSpecification getGlassForCell(String? cellKey) {
    if (cellKey != null) {
      if (cellGlassSpec.containsKey(cellKey)) {
        return cellGlassSpec[cellKey]!;
      }
      if (cellKey.startsWith('right_') && cellGlassSpec.containsKey('right')) {
        return cellGlassSpec['right']!;
      }
      if (cellKey.startsWith('left_') && cellGlassSpec.containsKey('left')) {
        return cellGlassSpec['left']!;
      }
      if (cellKey.startsWith('main_') && cellGlassSpec.containsKey('main')) {
        return cellGlassSpec['main']!;
      }
    }
    return glass;
  }

  WindowZone({
    required this.id,
    this.handlePositionRatio = 0.5,
    this.useClassicHandle = false,
    this.useOctoHandle = false,
    this.usePvcHandleOnAlu = false,
    required this.boundary,
    this.content = ZoneContent.fixedGlass,
    this.isSelected = false,
    GlassSpecification? glass,
    this.openAngle = 0.0,
    this.openDirection = OpenDirection.right,
    this.sashColor = FrameColor.white,
    this.selectedDbColor,
    this.isSash105 = false,
    this.sashThickness,
    this.innerH = 0,
    this.innerV = 0,
    this.slidingSashesCount = 2,
    this.cutSlidingGlassRebate = true,
    this.rightInnerH = 0,
    this.rightInnerV = 0,
    this.innerHPositions = const [],
    this.innerVPositions = const [],
    this.rightInnerHPositions = const [],
    this.rightInnerVPositions = const [],
    this.cellIsPanel = const {},
    this.cellIsSash = const {},
    this.cellIsDoubleSash = const {},
    this.cellSashOverrides = const {},
    this.lockType = LockType.none,
    Map<String, bool>? slidingMontantReinforced,
    this.middleHingeDragOffset = 0.0,
    this.doubleSashRatio = 0.5,
    this.doubleSashHasTwoHandles = false,
    this.disabledVerticalDivisions = const {},
    this.disabledHorizontalDivisions = const {},
    this.primaryDivisionAxis,
    this.rightPrimaryDivisionAxis,
    this.isSubdivided = false,
    this.hasSashPlintheBottom = false,
    Map<String, GlassSpecification>? cellGlassSpec,
  }) : this.glass = glass ?? globalDefaultGlass,
       this.cellGlassSpec = cellGlassSpec ?? const {},
       slidingMontantReinforced =
           slidingMontantReinforced ??
           const {
             'lateral_left': false,
             'lateral_right': false,
             'central_left': false,
             'central_right': false,
           };

  WindowZone clone() => WindowZone(
    id: id,
    handlePositionRatio: handlePositionRatio,
    useClassicHandle: useClassicHandle,
    useOctoHandle: useOctoHandle,
    usePvcHandleOnAlu: usePvcHandleOnAlu,
    boundary: Rect.fromLTWH(
      boundary.left,
      boundary.top,
      boundary.width,
      boundary.height,
    ),
    content: content,
    isSelected: isSelected,
    glass: glass.clone(),
    openAngle: openAngle,
    openDirection: openDirection,
    sashColor: sashColor,
    selectedDbColor: selectedDbColor,
    isSash105: isSash105,
    sashThickness: sashThickness,
    innerH: innerH,
    innerV: innerV,
    slidingSashesCount: slidingSashesCount,
    cutSlidingGlassRebate: cutSlidingGlassRebate,
    rightInnerH: rightInnerH,
    rightInnerV: rightInnerV,
    innerHPositions: List.from(innerHPositions),
    innerVPositions: List.from(innerVPositions),
    rightInnerHPositions: List.from(rightInnerHPositions),
    rightInnerVPositions: List.from(rightInnerVPositions),
    cellIsPanel: Map.from(cellIsPanel),
    cellIsSash: Map.from(cellIsSash),
    cellIsDoubleSash: Map.from(cellIsDoubleSash),
    cellSashOverrides: Map.from(
      cellSashOverrides.map(
        (k, v) => MapEntry(k, Map<String, dynamic>.from(v)),
      ),
    ),
    lockType: lockType,
    slidingMontantReinforced: Map.from(slidingMontantReinforced),
    middleHingeDragOffset: middleHingeDragOffset,
    doubleSashRatio: doubleSashRatio,
    doubleSashHasTwoHandles: doubleSashHasTwoHandles,
    disabledVerticalDivisions: Map.from(disabledVerticalDivisions),
    disabledHorizontalDivisions: Map.from(disabledHorizontalDivisions),
    primaryDivisionAxis: primaryDivisionAxis,
    rightPrimaryDivisionAxis: rightPrimaryDivisionAxis,
    isSubdivided: isSubdivided,
    hasSashPlintheBottom: hasSashPlintheBottom,
    cellGlassSpec: Map.from(
      cellGlassSpec.map((k, v) => MapEntry(k, v.clone())),
    ),
  );

  WindowZone copyWith({
    double? handlePositionRatio,
    bool? useClassicHandle,
    bool? useOctoHandle,
    bool? usePvcHandleOnAlu,
    Rect? boundary,
    ZoneContent? content,
    bool? isSelected,
    GlassSpecification? glass,
    double? openAngle,
    OpenDirection? openDirection,
    FrameColor? sashColor,
    Map<String, dynamic>? selectedDbColor,
    bool? isSash105,
    double? sashThickness,
    int? innerH,
    int? innerV,
    int? slidingSashesCount,
    bool? cutSlidingGlassRebate,
    int? rightInnerH,
    int? rightInnerV,
    List<double>? innerHPositions,
    List<double>? innerVPositions,
    List<double>? rightInnerHPositions,
    List<double>? rightInnerVPositions,
    Map<String, bool>? cellIsPanel,
    Map<String, bool>? cellIsSash,
    Map<String, bool>? cellIsDoubleSash,
    Map<String, Map<String, dynamic>>? cellSashOverrides,
    LockType? lockType,
    Map<String, bool>? slidingMontantReinforced,
    double? middleHingeDragOffset,
    double? doubleSashRatio,
    bool? doubleSashHasTwoHandles,
    Map<String, bool>? disabledVerticalDivisions,
    Map<String, bool>? disabledHorizontalDivisions,
    String? primaryDivisionAxis,
    String? rightPrimaryDivisionAxis,
    bool? isSubdivided,
    bool? hasSashPlintheBottom,
    Map<String, GlassSpecification>? cellGlassSpec,
  }) => WindowZone(
    id: id,
    handlePositionRatio: handlePositionRatio ?? this.handlePositionRatio,
    useClassicHandle: useClassicHandle ?? this.useClassicHandle,
    useOctoHandle: useOctoHandle ?? this.useOctoHandle,
    usePvcHandleOnAlu: usePvcHandleOnAlu ?? this.usePvcHandleOnAlu,
    boundary: boundary ?? this.boundary,
    content: content ?? this.content,
    isSelected: isSelected ?? this.isSelected,
    glass: glass ?? this.glass,
    openAngle: openAngle ?? this.openAngle,
    openDirection: openDirection ?? this.openDirection,
    sashColor: sashColor ?? this.sashColor,
    selectedDbColor: selectedDbColor ?? this.selectedDbColor,
    isSash105: isSash105 ?? this.isSash105,
    sashThickness: sashThickness ?? this.sashThickness,
    innerH: innerH ?? this.innerH,
    innerV: innerV ?? this.innerV,
    slidingSashesCount: slidingSashesCount ?? this.slidingSashesCount,
    cutSlidingGlassRebate: cutSlidingGlassRebate ?? this.cutSlidingGlassRebate,
    rightInnerH: rightInnerH ?? this.rightInnerH,
    rightInnerV: rightInnerV ?? this.rightInnerV,
    innerHPositions: innerHPositions ?? this.innerHPositions,
    innerVPositions: innerVPositions ?? this.innerVPositions,
    rightInnerHPositions: rightInnerHPositions ?? this.rightInnerHPositions,
    rightInnerVPositions: rightInnerVPositions ?? this.rightInnerVPositions,
    cellIsPanel: cellIsPanel ?? this.cellIsPanel,
    cellIsSash: cellIsSash ?? this.cellIsSash,
    cellIsDoubleSash: cellIsDoubleSash ?? this.cellIsDoubleSash,
    cellSashOverrides:
        cellSashOverrides ??
        Map.from(
          this.cellSashOverrides.map(
            (k, v) => MapEntry(k, Map<String, dynamic>.from(v)),
          ),
        ),
    lockType: lockType ?? this.lockType,
    slidingMontantReinforced:
        slidingMontantReinforced ?? Map.from(this.slidingMontantReinforced),
    middleHingeDragOffset: middleHingeDragOffset ?? this.middleHingeDragOffset,
    doubleSashRatio: doubleSashRatio ?? this.doubleSashRatio,
    doubleSashHasTwoHandles:
        doubleSashHasTwoHandles ?? this.doubleSashHasTwoHandles,
    disabledVerticalDivisions:
        disabledVerticalDivisions ?? Map.from(this.disabledVerticalDivisions),
    disabledHorizontalDivisions:
        disabledHorizontalDivisions ??
        Map.from(this.disabledHorizontalDivisions),
    primaryDivisionAxis: primaryDivisionAxis ?? this.primaryDivisionAxis,
    rightPrimaryDivisionAxis:
        rightPrimaryDivisionAxis ?? this.rightPrimaryDivisionAxis,
    isSubdivided: isSubdivided ?? this.isSubdivided,
    hasSashPlintheBottom: hasSashPlintheBottom ?? this.hasSashPlintheBottom,
    cellGlassSpec:
        cellGlassSpec ??
        Map.from(this.cellGlassSpec.map((k, v) => MapEntry(k, v.clone()))),
  );

  Map<String, String> getMergedCellMap({
    required bool isRightSash,
    required bool isDouble,
  }) {
    int rows = (isRightSash ? rightInnerH : innerH) + 1;
    int cols = (isRightSash ? rightInnerV : innerV) + 1;
    final map = <String, String>{};
    final visited = List.generate(
      rows,
      (_) => List.generate(cols, (_) => false),
    );

    String getVKey(int r, int v) {
      if (isDouble && isRightSash) return "right_${r}_$v";
      return "${r}_$v";
    }

    String getHKey(int c, int h) {
      if (isDouble && isRightSash) return "right_${c}_$h";
      return "${c}_$h";
    }

    for (int r = 0; r < rows; r++) {
      for (int c = 0; c < cols; c++) {
        if (visited[r][c]) continue;

        int w = 1;
        while (c + w < cols &&
            disabledVerticalDivisions[getVKey(r, c + w - 1)] == true) {
          w++;
        }

        int h = 1;
        while (r + h < rows) {
          bool canMergeRow = true;
          for (int col = c; col < c + w; col++) {
            if (disabledHorizontalDivisions[getHKey(col, r + h - 1)] != true) {
              canMergeRow = false;
              break;
            }
          }
          if (!canMergeRow) break;

          for (int col = c; col < c + w - 1; col++) {
            if (disabledVerticalDivisions[getVKey(r + h, col)] != true) {
              canMergeRow = false;
              break;
            }
          }
          if (!canMergeRow) break;

          h++;
        }

        final targetKey = "${r}_$c";
        for (int currR = r; currR < r + h; currR++) {
          for (int currC = c; currC < c + w; currC++) {
            visited[currR][currC] = true;
            map["${currR}_$currC"] = targetKey;
          }
        }
      }
    }
    return map;
  }
}

class SelectionInfo {
  final SelectionType? type;
  final String? zoneId;
  final bool? isHorizontalMullion;
  final double? mullionPosition;
  final double? mullionStart;
  final double? mullionEnd;
  final bool? isHorizontalInnerDivision;
  final bool? isRightSashInnerDivision;
  final int? innerDivisionIndex;

  const SelectionInfo({
    this.type,
    this.zoneId,
    this.isHorizontalMullion,
    this.mullionPosition,
    this.mullionStart,
    this.mullionEnd,
    this.isHorizontalInnerDivision,
    this.isRightSashInnerDivision,
    this.innerDivisionIndex,
  });

  static const none = SelectionInfo(type: null);

  factory SelectionInfo.zone(String id) =>
      SelectionInfo(type: SelectionType.zone, zoneId: id);

  factory SelectionInfo.mullion(
    bool isHorizontal,
    double position, {
    double? start,
    double? end,
  }) => SelectionInfo(
    type: SelectionType.mullion,
    isHorizontalMullion: isHorizontal,
    mullionPosition: position,
    mullionStart: start,
    mullionEnd: end,
  );
}

class WindowSnapshot {
  final double width;
  final double height;
  final bool hasBottomFrame;
  final Set<String> removedShutterSides;
  final bool hasFramePlintheBottom;
  final List<WindowZone> zones;
  final Map<String, MullionProfileType> mullionProfiles;
  final Map<String, bool> groovedMullionCavityOnPositiveSide;
  final Map<String, Map<String, dynamic>> mullionSectionOverrides;
  final Map<String, dynamic>? selectedDbColor;
  final Map<String, dynamic> componentOverrides;
  final double archHeight;
  final double topSlantLeftY;
  final double topSlantRightY;
  final double bottomSlantLeftY;
  final double bottomSlantRightY;
  final double shutterPosition;
  final String shutterMechanism;
  final bool hasShutter;
  final bool useSystemOB;
  final bool useDemiOB;
  final bool useVerrouCentral;
  final bool isCaissonTunnel;
  final bool showBottomWall;
  final bool showWall;
  final String wallColor;
  final String? primaryMullionAxis;
  final double? drawnLeft;
  final double? drawnTop;
  final bool useCustomSideCoverLayout;
  final List<SideCoverSegment> sideCoverSegments;
  final Set<String> hiddenSideCoverSegments;
  final bool hasInternalSlidingSideCover;
  final Map<String, dynamic>? internalSlidingSideCoverOverride;

  WindowSnapshot(
    this.width,
    this.height,
    this.hasBottomFrame,
    this.removedShutterSides,
    this.hasFramePlintheBottom,
    this.zones,
    this.mullionProfiles,
    this.groovedMullionCavityOnPositiveSide,
    this.mullionSectionOverrides,
    this.selectedDbColor,
    this.componentOverrides,
    this.archHeight,
    this.topSlantLeftY,
    this.topSlantRightY,
    this.bottomSlantLeftY,
    this.bottomSlantRightY,
    this.shutterPosition,
    this.shutterMechanism,
    this.hasShutter,
    this.useSystemOB,
    this.useDemiOB,
    this.useVerrouCentral,
    this.isCaissonTunnel,
    this.showBottomWall,
    this.showWall,
    this.wallColor,
    this.primaryMullionAxis,
    this.drawnLeft,
    this.drawnTop,
    this.useCustomSideCoverLayout,
    this.sideCoverSegments,
    this.hiddenSideCoverSegments,
    this.hasInternalSlidingSideCover,
    this.internalSlidingSideCoverOverride,
  );
}

extension FrameColorExtension on FrameColor {
  List<Color> get gradientColors {
    switch (this) {
      case FrameColor.white:
        return [Colors.white, Colors.grey.shade200, Colors.grey.shade300];
      case FrameColor.brown:
        return [
          const Color(0xFF6D4C41),
          const Color(0xFF5D4037),
          const Color(0xFF4E342E),
        ];
      case FrameColor.gray:
        return [
          const Color(0xFF6E7688),
          const Color(0xFF565E70),
          const Color(0xFF414858),
        ];
      case FrameColor.black:
        return [
          const Color(0xFF424242),
          const Color(0xFF303030),
          const Color(0xFF212121),
        ];
      case FrameColor.beige:
        return [
          const Color(0xFFF5F5DC),
          const Color(0xFFE8E8D0),
          const Color(0xFFDCDCB4),
        ];
      case FrameColor.gris:
        return [
          const Color(0xFFB8C0C8),
          const Color(0xFF8A939E),
          const Color(0xFF606A75),
        ];
      case FrameColor.antique:
        return [
          const Color(0xFF8F7D6F),
          const Color(0xFF6E5D4F),
          const Color(0xFF4D3E32),
        ];
      case FrameColor.lightWood:
        return [
          const Color(0xFFCBA56A),
          const Color(0xFFA8803E),
          const Color(0xFF7A5828),
        ];
    }
  }

  Color get borderColor {
    switch (this) {
      case FrameColor.white:
        return Colors.grey.shade900;
      case FrameColor.brown:
        return const Color(0xFF3E2723);
      case FrameColor.gray:
        return const Color(0xFF414858);
      case FrameColor.black:
        return Colors.black;
      case FrameColor.beige:
        return const Color(0xFFC0C090);
      case FrameColor.gris:
        return const Color(0xFF575B5D);
      case FrameColor.antique:
        return const Color(0xFF4D3E32);
      case FrameColor.lightWood:
        return const Color(0xFF7A5828);
    }
  }
}

List<Color> getEffectiveGradientColors(
  FrameColor baseColor,
  Map<String, dynamic>? dbColor,
) {
  if (dbColor != null) {
    final String rawName = dbColor['name'].toString().toLowerCase().trim();
    final String name = rawName
        .replaceAll('أ', 'ا')
        .replaceAll('إ', 'ا')
        .replaceAll('آ', 'ا')
        .replaceAll('ى', 'ي')
        .replaceAll('ة', 'ه');
    final String hex = (dbColor['hex_code'] ?? '')
        .toString()
        .toUpperCase()
        .replaceAll('#', '')
        .trim();

    // 1. Check names first to handle colors that might have default hex code (#FFFFFF) in database
    if (name.contains('white') ||
        name.contains('blanc') ||
        name.contains('ابيض') ||
        name.contains('أبيض') ||
        name.contains('╪ú╪¿┘è╪╢')) {
      return FrameColor.white.gradientColors;
    }

    if (name.contains('beige') ||
        name.contains('بيج') ||
        name.contains('╪¿┘è╪¼')) {
      return FrameColor.beige.gradientColors;
    }

    if (name.contains('9007')) {
      return FrameColor.gris.gradientColors;
    }

    if (name.contains('antique') ||
        name.contains('انتيك') ||
        name.contains('╪º┘å╪¬┘è┘â')) {
      return FrameColor.antique.gradientColors;
    }

    if (name.contains('ديزر') ||
        name.contains('ديزير') ||
        name.contains('desert') ||
        name.contains('oak')) {
      return FrameColor.lightWood.gradientColors;
    }

    if (name.contains('gray') ||
        name.contains('grey') ||
        name.contains('gris') ||
        name.contains('رمادي') ||
        name.contains('╪▒┘à╪º╪»┘è') ||
        name.contains('7024') ||
        name.contains('7824') ||
        name.contains('anthracite') ||
        name.contains('انترسيت')) {
      return [
        const Color(0xFF6E7688),
        const Color(0xFF565E70),
        const Color(0xFF414858),
      ];
    }

    if (name.contains('black') ||
        name.contains('noir') ||
        name.contains('اسود') ||
        name.contains('أسود') ||
        name.contains('╪ú╪│┘ê╪»')) {
      return FrameColor.black.gradientColors;
    }

    final bool isGold =
        name.contains('gold') ||
        name.contains('ذهب') ||
        name.contains('doré') ||
        name.contains('dore') ||
        RegExp(r'(^|[\s/(_-])or($|[\s/)_-])').hasMatch(name);
    if (isGold) {
      return [
        const Color(0xFFF1D675),
        const Color(0xFFD4AF37),
        const Color(0xFF9C7616),
      ];
    }

    if (name.contains('silver') ||
        name.contains('فضي') ||
        name.contains('argent')) {
      return [
        const Color(0xFFF5F5F7),
        const Color(0xFFC0C0C0),
        const Color(0xFF7D7D80),
      ];
    }

    if (name.contains('champagne') ||
        name.contains('شامبان') ||
        name.contains('شمبان') ||
        name.contains('وايت')) {
      return [
        const Color(0xFFFFF4DF),
        const Color(0xFFF7E7CE),
        const Color(0xFFC9AE86),
      ];
    }

    if (name.contains('wood') ||
        name.contains('bois') ||
        name.contains('خشب') ||
        name.contains('خشبي') ||
        name.contains('╪«╪┤╪¿') ||
        name.contains('chene') ||
        name.contains('chêne') ||
        name.contains('noyer') ||
        name.contains('acajou') ||
        name.contains('شين') ||
        name.contains('نويا') ||
        name.contains('اكاجو') ||
        name.contains('بوا') ||
        name.contains('faux') ||
        name.contains('فو') ||
        name.contains('antique') ||
        name.contains('انتيك') ||
        name.contains('d0') ||
        name.contains('دي زيرو')) {
      return FrameColor.brown.gradientColors;
    }

    if (name.contains('brown') ||
        name.contains('marron') ||
        name.contains('بني') ||
        name.contains('╪¿┘å┘è')) {
      return FrameColor.brown.gradientColors;
    }

    // 2. If no name matched, check hex codes
    if (hex == 'FFFFFF') {
      return FrameColor.white.gradientColors;
    }
    if (hex == 'F5F5DC') {
      return FrameColor.beige.gradientColors;
    }
    if (hex == '9E9E9E' || hex == 'C0C0C0' || hex == 'E0E0E0') {
      return [
        const Color(0xFF9E9E9E),
        const Color(0xFF757575),
        const Color(0xFF616161),
      ];
    }

    if (dbColor['hex_code'] != null &&
        dbColor['hex_code'].toString().isNotEmpty) {
      String hexCode = dbColor['hex_code'].toString().toUpperCase().trim();
      try {
        String cleanHex = hexCode.replaceAll('#', '');
        if (cleanHex.length == 6) cleanHex = 'FF$cleanHex';
        Color c = Color(int.parse(cleanHex, radix: 16));
        final hsl = HSLColor.fromColor(c);
        final light = hsl
            .withLightness((hsl.lightness + 0.15).clamp(0.0, 1.0))
            .toColor();
        final dark = hsl
            .withLightness((hsl.lightness - 0.1).clamp(0.0, 1.0))
            .toColor();
        return [light, c, dark];
      } catch (_) {}
    }
    return FrameColor.white.gradientColors;
  }
  return baseColor.gradientColors;
}

Color getEffectiveBorderColor(
  FrameColor baseColor,
  Map<String, dynamic>? dbColor,
) {
  if (dbColor != null) {
    final String rawName = dbColor['name'].toString().toLowerCase().trim();
    final String name = rawName
        .replaceAll('أ', 'ا')
        .replaceAll('إ', 'ا')
        .replaceAll('آ', 'ا')
        .replaceAll('ى', 'ي')
        .replaceAll('ة', 'ه');
    final String hex = (dbColor['hex_code'] ?? '')
        .toString()
        .toUpperCase()
        .replaceAll('#', '')
        .trim();

    // 1. Check names first
    if (name.contains('white') ||
        name.contains('blanc') ||
        name.contains('أبيض') ||
        name.contains('╪ú╪¿┘è╪╢')) {
      return FrameColor.white.borderColor;
    }

    if (name.contains('beige') ||
        name.contains('بيج') ||
        name.contains('╪¿┘è╪¼')) {
      return FrameColor.beige.borderColor;
    }

    if (name.contains('9007')) {
      return const Color(0xFF575B5D);
    }

    if (name.contains('antique') ||
        name.contains('انتيك') ||
        name.contains('╪º┘å╪¬┘è┘â')) {
      return FrameColor.antique.borderColor;
    }

    if (name.contains('ديزر') ||
        name.contains('ديزير') ||
        name.contains('desert') ||
        name.contains('oak')) {
      return FrameColor.lightWood.borderColor;
    }

    if (name.contains('gray') ||
        name.contains('grey') ||
        name.contains('gris') ||
        name.contains('رمادي') ||
        name.contains('╪▒┘à╪º╪»┘è') ||
        name.contains('7024') ||
        name.contains('7824') ||
        name.contains('anthracite') ||
        name.contains('انترسيت')) {
      return const Color(0xFF303030);
    }

    if (name.contains('wood') ||
        name.contains('bois') ||
        name.contains('خشبي') ||
        name.contains('خشب') ||
        name.contains('╪«╪┤╪¿') ||
        name.contains('chene') ||
        name.contains('chêne') ||
        name.contains('noyer') ||
        name.contains('acajou') ||
        name.contains('شين') ||
        name.contains('نويا') ||
        name.contains('اكاجو') ||
        name.contains('بوا') ||
        name.contains('faux') ||
        name.contains('فو') ||
        name.contains('antique') ||
        name.contains('انتيك') ||
        name.contains('d0') ||
        name.contains('دي زيرو')) {
      return FrameColor.brown.borderColor;
    }

    if (name.contains('brown') ||
        name.contains('marron') ||
        name.contains('بني') ||
        name.contains('╪¿┘å┘è')) {
      return FrameColor.brown.borderColor;
    }

    if (name.contains('black') ||
        name.contains('noir') ||
        name.contains('أسود') ||
        name.contains('╪ú╪│┘ê╪»')) {
      return FrameColor.black.borderColor;
    }

    final bool isGold =
        name.contains('gold') ||
        name.contains('ذهب') ||
        name.contains('doré') ||
        name.contains('dore') ||
        RegExp(r'(^|[\s/(_-])or($|[\s/)_-])').hasMatch(name);
    if (isGold) {
      return const Color(0xFF76560C);
    }

    if (name.contains('silver') ||
        name.contains('فضي') ||
        name.contains('argent')) {
      return const Color(0xFF7D7D80);
    }

    if (name.contains('champagne') ||
        name.contains('شامبان') ||
        name.contains('شمبان') ||
        name.contains('وايت')) {
      return const Color(0xFFA48661);
    }

    // 2. If no name matched, check hex codes
    if (hex == 'FFFFFF') {
      return FrameColor.white.borderColor;
    }
    if (hex == 'F5F5DC') {
      return FrameColor.beige.borderColor;
    }
    if (hex == '9E9E9E' || hex == 'C0C0C0' || hex == 'E0E0E0') {
      return const Color(0xFF909090);
    }

    if (dbColor['hex_code'] != null &&
        dbColor['hex_code'].toString().isNotEmpty) {
      String hexCode = dbColor['hex_code'].toString().toUpperCase().trim();
      try {
        String cleanHex = hexCode.replaceAll('#', '');
        if (cleanHex.length == 6) cleanHex = 'FF$cleanHex';
        Color c = Color(int.parse(cleanHex, radix: 16));
        final hsl = HSLColor.fromColor(c);
        return hsl
            .withLightness((hsl.lightness - 0.2).clamp(0.0, 1.0))
            .toColor();
      } catch (_) {}
    }
    return FrameColor.white.borderColor;
  }
  return baseColor.borderColor;
}

class WindowModel extends ChangeNotifier {
  static bool isShutterBladeComponent(Map<String, dynamic> component) {
    final type = (component['component_type'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    return type == 'blade' || type == 'lame';
  }

  static bool isBladeEndCapLinkedTo(
    Map<String, dynamic> endCap,
    Map<String, dynamic> blade,
  ) {
    final type = (endCap['component_type'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    final linkedBlade = (endCap['shutter_subtype'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    final bladeName = (blade['name'] ?? '').toString().trim().toLowerCase();
    return type == 'bouchon_lame' &&
        bladeName.isNotEmpty &&
        linkedBlade == bladeName;
  }

  static String? shutterMeasurementKey(
    Map<String, dynamic> component, {
    bool preferTrackMeasurement = false,
  }) {
    final trackMeasurement = preferTrackMeasurement
        ? (component['track_measurement'] ?? '').toString().trim()
        : '';
    final measurement = (component['measurement'] ?? '').toString().trim();
    final source = trackMeasurement.isNotEmpty
        ? trackMeasurement
        : measurement.isNotEmpty
        ? measurement
        : (component['name'] ?? '').toString();
    final match = RegExp(r'\d+(?:[.,]\d+)?').firstMatch(source);
    final value = match == null
        ? null
        : double.tryParse(match.group(0)!.replaceAll(',', '.'));
    if (value == null || value <= 0) return null;
    return value == value.roundToDouble()
        ? value.toInt().toString()
        : value
              .toStringAsFixed(3)
              .replaceFirst(RegExp(r'0+$'), '')
              .replaceFirst(RegExp(r'\.$'), '');
  }

  static List<Map<String, dynamic>> compatibleShutterTracks(
    Map<String, dynamic> blade,
    Iterable<Map<String, dynamic>> tracks,
  ) {
    final requiredMeasurement = shutterMeasurementKey(
      blade,
      preferTrackMeasurement: true,
    );
    if (requiredMeasurement == null) return <Map<String, dynamic>>[];
    return tracks
        .where((track) {
          final type = (track['component_type'] ?? '')
              .toString()
              .trim()
              .toLowerCase();
          return const {
                'track',
                'coulisse',
                'coulisses',
                'glissiere',
              }.contains(type) &&
              shutterMeasurementKey(track) == requiredMeasurement;
        })
        .map(Map<String, dynamic>.from)
        .toList();
  }

  static String _normalizeShutterBladeLabel(String value) {
    return value
        .toLowerCase()
        .replaceAll('\u00e0', 'a')
        .replaceAll('\u00e2', 'a')
        .replaceAll('\u00e4', 'a')
        .replaceAll('\u00e7', 'c')
        .replaceAll('\u00e9', 'e')
        .replaceAll('\u00e8', 'e')
        .replaceAll('\u00ea', 'e')
        .replaceAll('\u00eb', 'e')
        .replaceAll('\u00ee', 'i')
        .replaceAll('\u00ef', 'i')
        .replaceAll('\u00f4', 'o')
        .replaceAll('\u00f6', 'o')
        .replaceAll('\u00f9', 'u')
        .replaceAll('\u00fb', 'u')
        .replaceAll('\u00fc', 'u')
        .replaceAll('أ', 'ا')
        .replaceAll('إ', 'ا')
        .replaceAll('آ', 'ا')
        .replaceAll(RegExp(r'[^a-z0-9\u0600-\u06ff]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static int _shutterBladeNameScore(String actual, String candidate) {
    final normalizedActual = _normalizeShutterBladeLabel(actual);
    final normalizedCandidate = _normalizeShutterBladeLabel(candidate);
    if (normalizedActual.isEmpty || normalizedCandidate.isEmpty) return -1;
    if (normalizedActual.replaceAll(' ', '') ==
        normalizedCandidate.replaceAll(' ', '')) {
      return 1000;
    }

    Set<String> signature(String value) => value
        .split(' ')
        .where(
          (token) =>
              token.isNotEmpty &&
              !const {'lame', 'lames', 'blade', 'blades', 'mm'}.contains(token),
        )
        .toSet();

    final actualTokens = signature(normalizedActual);
    final candidateTokens = signature(normalizedCandidate);
    final actualNumbers = RegExp(
      r'\d+(?:[.,]\d+)?',
    ).allMatches(normalizedActual).map((match) => match.group(0)!).toSet();
    final candidateNumbers = RegExp(
      r'\d+(?:[.,]\d+)?',
    ).allMatches(normalizedCandidate).map((match) => match.group(0)!).toSet();
    if (actualNumbers.isNotEmpty &&
        actualNumbers.intersection(candidateNumbers).isEmpty) {
      return -1;
    }
    final actualExtruded =
        normalizedActual.contains('extrud') || normalizedActual.contains('x3d');
    final candidateExtruded =
        normalizedCandidate.contains('extrud') ||
        normalizedCandidate.contains('x3d');
    if (actualExtruded != candidateExtruded) return -1;
    final common = actualTokens.intersection(candidateTokens).length;
    if (common == 0) return -1;
    var score = common * 50;
    if (actualNumbers.intersection(candidateNumbers).isNotEmpty) score += 150;
    if (actualTokens.length == candidateTokens.length &&
        actualTokens.containsAll(candidateTokens)) {
      score += 400;
    }
    final actualInjected = normalizedActual.contains('inject');
    final candidateInjected = normalizedCandidate.contains('inject');
    if (actualInjected == candidateInjected) score += 40;
    return score;
  }

  static double resolveShutterSqmPrice({
    required String bladeName,
    required String bladeSubtype,
    required int? colorId,
    required Iterable<Map<String, dynamic>> prices,
  }) {
    double readPrice(dynamic value) => value is num
        ? value.toDouble()
        : double.tryParse(value?.toString() ?? '') ?? 0.0;

    var selectedColorScore = -1;
    var generalColorScore = -1;
    var selectedColorPrice = 0.0;
    var generalColorPrice = 0.0;
    var subtypeFallback = 0.0;
    final normalizedSubtype = _normalizeShutterBladeLabel(bladeSubtype);

    for (final row in prices) {
      final rowColorId = (row['color_id'] as num?)?.toInt() ?? 0;
      final isSelectedColor = colorId != null && rowColorId == colorId;
      final isGeneralColor = rowColorId == 0;
      if (!isSelectedColor && !isGeneralColor) continue;
      final price = readPrice(row['price_per_sqm']);
      if (price <= 0) continue;
      final candidate = (row['blade_type'] ?? '').toString();
      final score = _shutterBladeNameScore(bladeName, candidate);
      if (score >= 0 && isSelectedColor && score > selectedColorScore) {
        selectedColorScore = score;
        selectedColorPrice = price;
      } else if (score >= 0 && isGeneralColor && score > generalColorScore) {
        generalColorScore = score;
        generalColorPrice = price;
      } else if (subtypeFallback == 0 &&
          normalizedSubtype == _normalizeShutterBladeLabel(candidate)) {
        subtypeFallback = price;
      }
    }
    if (selectedColorPrice > 0) return selectedColorPrice;
    if (generalColorPrice > 0) return generalColorPrice;
    return subtypeFallback;
  }

  /// Resolves the caisson from the blade-specific limits configured on the
  /// pricing page. A manually selected box is respected only when that exact
  /// size is configured and supports the current height.
  static ShutterBoxResolution? resolveShutterBoxFromLimits({
    required double windowHeight,
    required List<Map<String, dynamic>> limits,
    double? manuallySelectedBoxSize,
  }) {
    if (limits.isEmpty) return null;

    double readNumber(Map<String, dynamic> row, String key) {
      final value = row[key];
      return value is num
          ? value.toDouble()
          : double.tryParse(value?.toString() ?? '') ?? 0.0;
    }

    final sorted =
        limits.where((row) {
          return readNumber(row, 'box_size') > 0 &&
              readNumber(row, 'max_height') > 0;
        }).toList()..sort((a, b) {
          return readNumber(a, 'box_size').compareTo(readNumber(b, 'box_size'));
        });
    if (sorted.isEmpty) return null;

    final supported = sorted.where((row) {
      return windowHeight <= readNumber(row, 'max_height');
    }).toList();
    final largestBox = sorted.last;
    final maximumSupportedHeight = sorted
        .map((row) => readNumber(row, 'max_height'))
        .reduce(math.max);

    if (supported.isEmpty) {
      return ShutterBoxResolution(
        boxSize: readNumber(largestBox, 'box_size'),
        exceedsAllLimits: true,
        maximumSupportedHeight: maximumSupportedHeight,
      );
    }

    final minimumSupported = supported.first;
    var selectedSize = readNumber(minimumSupported, 'box_size');
    if (manuallySelectedBoxSize != null) {
      for (final row in supported) {
        final size = readNumber(row, 'box_size');
        if ((size - manuallySelectedBoxSize).abs() <= 0.5 &&
            size >= selectedSize) {
          selectedSize = size;
          break;
        }
      }
    }

    return ShutterBoxResolution(
      boxSize: selectedSize,
      exceedsAllLimits: false,
      maximumSupportedHeight: maximumSupportedHeight,
    );
  }

  List<PlacedFrame> frames = [];
  PlacedFrame? selectedFrame;
  String? selectedFrameCode;
  Map<String, dynamic> componentOverrides = {};

  bool _isX3dShutterComponent(Map<String, dynamic> component) {
    final text =
        '${component['name'] ?? ''} ${component['shutter_subtype'] ?? ''}'
            .toLowerCase();
    // Catalogue entries may call the same blade either X3D or Extrudé.
    return text.contains('x3d') ||
        text.contains('extrud') ||
        text.contains('إكسترودي') ||
        text.contains('اكسترودي');
  }

  double? _shutterComponentDiameter(Map<String, dynamic> component) {
    final type = (component['component_type'] ?? '').toString().toLowerCase();
    final name = (component['name'] ?? '').toString().toLowerCase();
    final isMotor =
        type == 'motor' || type == 'moteur' || name.contains('moteur');
    for (final field in const ['motor_diameter', 'measurement', 'name']) {
      final value = (component[field] ?? '').toString().trim();
      // "10 Nm" is a torque, not a 10 mm motor diameter. The structured
      // motor_diameter field has priority; legacy names can still hold a
      // diameter when they do not express a torque.
      if (isMotor &&
          field != 'motor_diameter' &&
          RegExp(
            r'\d+(?:[.,]\d+)?\s*n\s*\.?\s*m',
            caseSensitive: false,
          ).hasMatch(value)) {
        continue;
      }
      final match = RegExp(r'(?<!\d)(\d{2,3}(?:[.,]\d+)?)').firstMatch(value);
      if (match != null) {
        return double.tryParse(match.group(1)!.replaceAll(',', '.'));
      }
    }
    return null;
  }

  double? _shutterMotorTorque(Map<String, dynamic> component) {
    for (final field in const ['measurement', 'name']) {
      final value = (component[field] ?? '').toString().trim();
      if (value.isEmpty) continue;
      final match = RegExp(
        r'(\d+(?:[.,]\d+)?)\s*(?:n\s*\.?\s*m|nm|نيوتن)',
        caseSensitive: false,
      ).firstMatch(value);
      if (match != null) {
        return double.tryParse(match.group(1)!.replaceAll(',', '.'));
      }
      // Some older catalogues store a bare torque value in `measurement`.
      if (field == 'measurement') {
        final direct = double.tryParse(value.replaceAll(',', '.'));
        if (direct != null) return direct;
      }
    }
    return null;
  }

  bool _motorHasEmergencyCrank(Map<String, dynamic> motor) {
    final raw = motor['motor_has_emergency_crank'];
    if (raw is bool) return raw;
    if (raw is num) return raw != 0;
    final value = raw?.toString().trim().toLowerCase() ?? '';
    return value == '1' ||
        value == 'true' ||
        value == 'yes' ||
        value == 'oui' ||
        value == 'نعم';
  }

  bool _matchesShutterRole(Map<String, dynamic> component, String role) {
    final type = (component['component_type'] ?? '').toString().toLowerCase();
    final name = (component['name'] ?? '').toString().toLowerCase();
    switch (role) {
      case 'axis':
        return type == 'laxe' ||
            type == 'axe' ||
            type.contains('محور') ||
            name.contains('axe') ||
            name.contains('محور');
      case 'motor':
        return type == 'motor' ||
            type == 'moteur' ||
            name.contains('moteur') ||
            name.contains('محرك');
      case 'embout':
        return type == 'embout' ||
            name.contains('embout') ||
            name.contains('bague filet') ||
            name.contains('bague fil') ||
            name.contains('blague flit');
      case 'support_roulement':
        return type == 'support_roulement' ||
            type.contains('support roulement') ||
            name.contains('support roulement') ||
            name.contains('roulement') ||
            name.contains('سيبور رولمو');
      case 'support_moteur':
        return type == 'support_moteur' ||
            type.contains('support moteur') ||
            name.contains('support moteur') ||
            name.contains('سيبور موتور');
      case 'attache':
        return type == 'attache' ||
            type.contains('attache') ||
            name.contains('attache') ||
            name.contains('أطاش');
      case 'blade_cap':
        return type == 'bouchon_lame';
      default:
        return false;
    }
  }

  List<Map<String, dynamic>> _compatibleShutterAxes(
    Iterable<Map<String, dynamic>> rows, {
    Map<String, dynamic>? blade,
    Map<String, dynamic>? motor,
  }) {
    final selectedBlade = blade ?? componentOverrides['الشرائح (Lames)'];
    final bladeName = (selectedBlade?['name'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    final bladeIsX3d =
        selectedBlade != null && _isX3dShutterComponent(selectedBlade);
    var candidates = rows
        .where(_matchesShutterRoleAxis)
        .map(Map<String, dynamic>.from)
        .where((axis) {
          final axisIsX3d = _isX3dShutterComponent(axis);
          return bladeIsX3d ? axisIsX3d : !axisIsX3d;
        })
        .toList();

    if (bladeName.isNotEmpty) {
      final explicitlyLinked = candidates.where((axis) {
        return (axis['shutter_subtype'] ?? '')
                .toString()
                .trim()
                .toLowerCase() ==
            bladeName;
      }).toList();
      if (explicitlyLinked.isNotEmpty) candidates = explicitlyLinked;
    }

    final motorDiameter = motor == null
        ? null
        : _shutterComponentDiameter(motor);
    if (motorDiameter != null && motorDiameter > 0) {
      candidates = candidates.where((axis) {
        final axisDiameter = _shutterComponentDiameter(axis);
        return axisDiameter != null && axisDiameter >= motorDiameter;
      }).toList();
    }

    candidates.sort((a, b) {
      final aDiameter = _shutterComponentDiameter(a) ?? double.infinity;
      final bDiameter = _shutterComponentDiameter(b) ?? double.infinity;
      return aDiameter.compareTo(bDiameter);
    });
    return candidates;
  }

  bool _matchesShutterRoleAxis(Map<String, dynamic> component) =>
      _matchesShutterRole(component, 'axis');

  /// Chooses only an axis that belongs to the selected blade.  X3D is the
  /// first decision; a motor's diameter then removes axes that are too small.
  Map<String, dynamic>? _selectCompatibleShutterAxis(
    Iterable<Map<String, dynamic>> rows, {
    Map<String, dynamic>? motor,
    bool ignoreCurrentMotor = false,
  }) {
    final selectedMotor = ignoreCurrentMotor
        ? motor
        : (motor ?? componentOverrides['المحرك (Moteur)']);
    final candidates = _compatibleShutterAxes(rows, motor: selectedMotor);
    return candidates.isEmpty ? null : candidates.first;
  }

  /// The rail is dictated by the selected blade's physical measurement.  This
  /// is especially important for Lame Second Sink Injecté, whose rail must
  /// carry the same measurement rather than retaining the default 25 mm rail.
  Future<void> _synchronizeShutterTrackWithBlade(dynamic database) async {
    final blade = componentOverrides['الشرائح (Lames)'];
    if (blade == null) return;

    // Older blades did not have a separate rail measurement, so fall back to
    // their existing measurement for backward compatibility.
    final bladeSize = shutterMeasurementKey(
      Map<String, dynamic>.from(blade),
      preferTrackMeasurement: true,
    );
    if (bladeSize == null || bladeSize.isEmpty) return;

    final rows = await database.query(
      'ShutterComponents',
      where:
          "LOWER(TRIM(component_type)) IN ('track', 'coulisse', 'coulisses', 'glissiere') AND (is_active = 1 OR is_active IS NULL)",
    );
    final bladeIsX3d = _isX3dShutterComponent(blade);
    final bladeName = (blade['name'] ?? '').toString().trim().toLowerCase();
    final candidates = compatibleShutterTracks(
      Map<String, dynamic>.from(blade),
      normalizeDatabaseRows(rows),
    ).where((track) => _isX3dShutterComponent(track) == bladeIsX3d).toList();
    if (candidates.isEmpty) return;

    int score(Map<String, dynamic> track) {
      final subtype = (track['shutter_subtype'] ?? '')
          .toString()
          .trim()
          .toLowerCase();
      if (bladeName.isNotEmpty && subtype == bladeName) return 0;
      final type = (track['component_type'] ?? '').toString().toLowerCase();
      if (type == 'track' || type == 'coulisse') return 1;
      if (subtype.isEmpty || subtype == 'normal') return 2;
      return 3;
    }

    candidates.sort((a, b) => score(a).compareTo(score(b)));
    final selected = Map<String, dynamic>.from(candidates.first);
    final rawPrice = selected['price_dzd'] ?? selected['price'] ?? 0.0;
    selected['calculated_price'] = rawPrice is num
        ? rawPrice.toDouble()
        : double.tryParse(rawPrice.toString()) ?? 0.0;
    componentOverrides['السكك (Coulisses)'] = selected;
    shutterGlissiere = selected['name']?.toString() ?? shutterGlissiere;
  }

  /// Keep the parts that are physically tied to a shutter blade in the
  /// ShutterComponents catalogue.  Kits are intentionally absent here: they
  /// are selected exclusively from KitBundles.
  Future<void> _synchronizeShutterPartsWithBlade(dynamic database) async {
    final blade = componentOverrides['الشرائح (Lames)'];
    if (blade == null) return;

    final rows = await database.query(
      'ShutterComponents',
      where: '(is_active = 1 OR is_active IS NULL)',
    );
    final catalogue = normalizeDatabaseRows(rows);
    final colorPrices = normalizeDatabaseRows(
      await database.query('ShutterColorPrices'),
    );
    final selectedColorId = selectedDbColor?['id'] is num
        ? (selectedDbColor!['id'] as num).toInt()
        : int.tryParse('${selectedDbColor?['id'] ?? ''}');
    final bladeName = (blade['name'] ?? '').toString().trim().toLowerCase();
    final isX3d = _isX3dShutterComponent(blade);

    Map<String, dynamic> withPrice(Map<String, dynamic> row) {
      final result = Map<String, dynamic>.from(row);
      result['calculated_price'] = resolveShutterComponentUnitPrice(
        component: result,
        colorPrices: colorPrices,
        selectedColorId: selectedColorId,
      );
      return result;
    }

    Map<String, dynamic>? selectForBlade(String role, String overrideKey) {
      var candidates = catalogue
          .where((row) => _matchesShutterRole(row, role))
          .where((row) => _isX3dShutterComponent(row) == isX3d)
          .toList();
      if (candidates.isEmpty) return null;

      final exact = candidates.where((row) {
        return bladeName.isNotEmpty &&
            (row['shutter_subtype'] ?? '').toString().trim().toLowerCase() ==
                bladeName;
      }).toList();
      if (exact.isNotEmpty) candidates = exact;

      final currentId = (componentOverrides[overrideKey]?['id'] as num?)
          ?.toInt();
      final current = currentId == null
          ? null
          : candidates.where(
              (row) => (row['id'] as num?)?.toInt() == currentId,
            );
      if (current != null && current.isNotEmpty) {
        return withPrice(current.first);
      }
      return withPrice(candidates.first);
    }

    // Normal motor shutters use the configured component titled/type Moteur.
    // X3D is refined later by its torque calculation in
    // _applyX3dPvcShutterRules.
    if (shutterMechanism == 'محرك' && !isX3d) {
      final motor = selectForBlade('motor', 'المحرك (Moteur)');
      if (motor == null) {
        componentOverrides.remove('المحرك (Moteur)');
      } else {
        componentOverrides['المحرك (Moteur)'] = motor;
      }
    }

    // Attaches belong to the selected blade subtype.  There is deliberately
    // no cross-subtype fallback: normal blades never borrow X3D attaches and
    // vice versa.
    final attache = selectForBlade('attache', 'أطاش (Attache)');
    if (attache == null) {
      componentOverrides.remove('أطاش (Attache)');
    } else {
      componentOverrides['أطاش (Attache)'] = attache;
    }

    // Blade end caps use the exact linked-blade field saved by the catalogue
    // dialog. They never fall back to another blade family or size.
    final linkedEndCaps = catalogue
        .where((row) => _matchesShutterRole(row, 'blade_cap'))
        .where((row) => isBladeEndCapLinkedTo(row, blade))
        .toList();
    if (linkedEndCaps.isEmpty) {
      componentOverrides.remove('أغطية الشفرات (Bouchons Lames)');
    } else {
      componentOverrides['أغطية الشفرات (Bouchons Lames)'] = withPrice(
        linkedEndCaps.first,
      );
    }
  }

  /// X3D shutters in a standard PVC caisson use a dedicated motorised
  /// assembly.  The motor is selected by the requested torque, and only from
  /// motors that physically fit the axis chosen for the X3D blade.
  Future<void> _applyX3dPvcShutterRules(dynamic database) async {
    final blade = componentOverrides['الشرائح (Lames)'];
    if (!hasShutter ||
        isCaissonTunnel ||
        !isPVC ||
        blade == null ||
        !_isX3dShutterComponent(blade)) {
      return;
    }

    shutterMechanism = 'محرك';
    final rows = await database.query(
      'ShutterComponents',
      where: '(is_active = 1 OR is_active IS NULL)',
    );
    final catalogue = normalizeDatabaseRows(rows);
    final axes = _compatibleShutterAxes(
      catalogue.where((row) => _matchesShutterRole(row, 'axis')),
      blade: Map<String, dynamic>.from(blade),
    );

    Map<String, dynamic> withPrice(Map<String, dynamic> component) {
      final result = Map<String, dynamic>.from(component);
      final rawPrice = result['price_dzd'] ?? result['price'] ?? 0.0;
      result['calculated_price'] = rawPrice is num
          ? rawPrice.toDouble()
          : double.tryParse(rawPrice.toString()) ?? 0.0;
      return result;
    }

    // The shutter height excludes the regular PVC caisson.  The required
    // torque is the stated X3D rule: surface × 12 kg/m² ÷ 1.6.
    final shutterHeightMm = math.max(0.0, height - shutterBoxHeight);
    final requiredTorque =
        (width / 1000.0) * (shutterHeightMm / 1000.0) * 12.0 / 1.6;
    final motors =
        catalogue.where((row) => _matchesShutterRole(row, 'motor')).where((
          motor,
        ) {
          final torque = _shutterMotorTorque(motor);
          if (torque == null || torque < requiredTorque) return false;
          // A declared motor diameter must fit inside at least one compatible
          // X3D axis.  Rows without the new diameter field remain selectable
          // for legacy catalogues.
          final motorDiameter = _shutterComponentDiameter(motor);
          return motorDiameter == null ||
              axes.any((axis) {
                final axisDiameter = _shutterComponentDiameter(axis);
                return axisDiameter == null || axisDiameter >= motorDiameter;
              });
        }).toList()..sort((a, b) {
          final torqueCompare = (_shutterMotorTorque(a) ?? double.infinity)
              .compareTo(_shutterMotorTorque(b) ?? double.infinity);
          if (torqueCompare != 0) return torqueCompare;
          return (_shutterComponentDiameter(a) ?? double.infinity).compareTo(
            _shutterComponentDiameter(b) ?? double.infinity,
          );
        });

    // A motor chosen explicitly in the cost table remains authoritative when
    // it still meets the required torque and fits an axis for this blade.
    // This keeps the axis tied to the motor (40/60 mm, etc.) instead of
    // replacing the user's selected motor during a refresh.
    final currentMotor = componentOverrides['المحرك (Moteur)'];
    final currentMotorId = (currentMotor?['id'] as num?)?.toInt();
    Map<String, dynamic>? chosenMotor;
    if (currentMotorId != null) {
      for (final motor in motors) {
        if ((motor['id'] as num?)?.toInt() == currentMotorId) {
          chosenMotor = motor;
          break;
        }
      }
    }
    final selectedMotor = chosenMotor == null
        ? (motors.isEmpty ? null : withPrice(motors.first))
        : withPrice(chosenMotor);
    if (selectedMotor == null) {
      componentOverrides.remove('المحرك (Moteur)');
    } else {
      componentOverrides['المحرك (Moteur)'] = selectedMotor;
    }

    final selectedAxis = axes.where((axis) {
      final motorDiameter = selectedMotor == null
          ? null
          : _shutterComponentDiameter(selectedMotor);
      final axisDiameter = _shutterComponentDiameter(axis);
      return motorDiameter == null ||
          axisDiameter == null ||
          axisDiameter >= motorDiameter;
    }).toList();
    if (selectedAxis.isEmpty) {
      componentOverrides.remove('المحور (Axe)');
    } else {
      componentOverrides['المحور (Axe)'] = withPrice(selectedAxis.first);
    }

    int relationScore(Map<String, dynamic> component) {
      final subtype = (component['shutter_subtype'] ?? '')
          .toString()
          .trim()
          .toLowerCase();
      final bladeName = (blade['name'] ?? '').toString().trim().toLowerCase();
      if (bladeName.isNotEmpty && subtype == bladeName) return 0;
      if (_isX3dShutterComponent(component)) return 1;
      if (subtype == 'normal' || subtype.isEmpty) return 2;
      return 3;
    }

    Map<String, dynamic>? preferredRole(
      String role, {
      required List<String> requiredWords,
    }) {
      final candidates = catalogue.where((component) {
        if (!_matchesShutterRole(component, role)) return false;
        final text =
            '${component['name'] ?? ''} ${component['component_type'] ?? ''}'
                .toLowerCase();
        return requiredWords.every(text.contains);
      }).toList()..sort((a, b) => relationScore(a).compareTo(relationScore(b)));
      return candidates.isEmpty ? null : withPrice(candidates.first);
    }

    // These two parts are mandatory for X3D.  Do not silently replace them
    // with a generic part: a missing catalogue row must remain visible.
    final cpr = preferredRole(
      'support_roulement',
      requiredWords: const ['cpr'],
    );
    if (cpr == null) {
      componentOverrides.remove('سيبور رولمو (Support Roulement)');
    } else {
      componentOverrides['سيبور رولمو (Support Roulement)'] = cpr;
    }
    final galvaEmbout = preferredRole('embout', requiredWords: const ['galva']);
    if (galvaEmbout == null) {
      componentOverrides.remove('الامبو (Embout)');
    } else {
      componentOverrides['الامبو (Embout)'] = galvaEmbout;
    }

    // A motor with an emergency manivelle does not need a support motor.
    if (selectedMotor == null || _motorHasEmergencyCrank(selectedMotor)) {
      componentOverrides.remove('سيبور موتور (Support Moteur)');
    } else {
      final support = preferredRole('support_moteur', requiredWords: const []);
      if (support == null) {
        componentOverrides.remove('سيبور موتور (Support Moteur)');
      } else {
        componentOverrides['سيبور موتور (Support Moteur)'] = support;
      }
    }
  }

  Map<String, dynamic>? frameOverride;
  Map<String, dynamic>? sideCoverOverride;
  Map<String, dynamic>? sashOverride;

  List<Map<String, dynamic>> availableIntercalls = [];
  List<Map<String, dynamic>> availableGases = [];

  double width;
  double height;
  double totalCost = 0.0;
  int quantity = 1;

  bool isReplaced = false;
  String replacementReason = '';
  bool isCustomProduct = false;

  String? manualNameOverride;
  double? manualPriceOverride;
  String? description;
  bool invoiceTableEdited = false;
  String? position;
  String? loadedSeriesName;
  String? loadedSlidingSeriesName;
  int? loadedSeriesId;
  int? loadedSlidingSeriesId;
  Map<String, dynamic>? seriesDesignConfig;
  // Cutting rules are catalog data, separate from the drawing definition.
  // Keep the sliding copy distinct so a mixed drawing never applies an
  // opening-series formula to the sliding leaves.
  Map<String, dynamic>? seriesTableConfig;
  Map<String, dynamic>? slidingSeriesTableConfig;

  double archHeight = 0.0;
  double topSlantLeftY = 0.0;
  double topSlantRightY = 0.0;
  double bottomSlantLeftY = 0.0;
  double bottomSlantRightY = 0.0;

  bool get hasArchOrSlant =>
      archHeight > 0 ||
      topSlantLeftY != 0 ||
      topSlantRightY != 0 ||
      bottomSlantLeftY != 0 ||
      bottomSlantRightY != 0;

  bool get isDoor => zones.any(
    (z) => z.lockType == LockType.clef || z.lockType == LockType.condamnation,
  );

  bool get canBeArchedOrSlanted =>
      !zones.any((z) => z.content == ZoneContent.slidingSash);

  void updateTopSlantAndArch({
    double? leftSlant,
    double? rightSlant,
    double? arch,
  }) {
    if (!canBeArchedOrSlanted) return;
    if (leftSlant != null) topSlantLeftY = leftSlant;
    if (rightSlant != null) topSlantRightY = rightSlant;
    if (arch != null) archHeight = arch;
    if (archHeight > 0 || topSlantLeftY != 0 || topSlantRightY != 0) {
      hasShutter = false;
    }
    notifyListeners();
  }

  AluminumProfileSystem? get system {
    if (activeSeries == null) return null;
    try {
      return availableSystems.firstWhere(
        (s) => s.id == activeSeries!.profileId,
      );
    } catch (_) {
      return null;
    }
  }

  /// In mixed drawings, the outer frame belongs to the opening series while
  /// both kinds of zones are present.  A drawing made only of sliding zones
  /// uses the sliding series as its primary frame instead.
  bool get usesSlidingPrimaryProfiles {
    if (systemMode == 'sliding') return true;
    if (systemMode != 'mixed') return false;

    final occupiedZones = zones
        .where((zone) => zone.content != ZoneContent.empty)
        .toList();
    return occupiedZones.isNotEmpty &&
        occupiedZones.every((zone) => zone.content == ZoneContent.slidingSash);
  }

  bool _isPvcSeries(AluminumSeries? series) {
    if (series == null) return false;
    try {
      final system = availableSystems.firstWhere(
        (s) => s.id == series.profileId,
      );
      return system.type == 'PVC' || system.type == 'pvc';
    } catch (_) {
      return false;
    }
  }

  bool _sectionHasIntegratedSideCover(AluminumSection section) {
    final name = section.name.toLowerCase();
    final type = section.type.toLowerCase();
    return section.couvreJointWidth > 0 ||
        name.contains('مدمج') ||
        name.contains('intégré') ||
        name.contains('integre') ||
        name.contains('monobloc') ||
        type.contains('monobloc');
  }

  bool _overrideHasIntegratedSideCover(Map<String, dynamic>? override) {
    if (override == null) return false;
    final name = (override['name'] ?? '').toString().toLowerCase();
    final type = (override['type'] ?? '').toString().toLowerCase();
    final rawWidth = override['couvre_joint_width'];
    final width = rawWidth is num
        ? rawWidth.toDouble()
        : double.tryParse(rawWidth?.toString() ?? '') ?? 0.0;
    return width > 0 ||
        name.contains('مدمج') ||
        name.contains('intégré') ||
        name.contains('integre') ||
        name.contains('monobloc') ||
        type.contains('monobloc');
  }

  bool get isPVC => _isPvcSeries(
    usesSlidingPrimaryProfiles ? activeSlidingSeries : activeSeries,
  );

  /// Series and override used for the visible outer frame. In a mixed system
  /// the opening series owns the outer frame, while a sliding-only system uses
  /// the sliding series.
  AluminumSeries? get activeFrameSeries => usesSlidingPrimaryProfiles
      ? (activeSlidingSeries ?? activeSeries)
      : activeSeries;

  Map<String, dynamic>? get activeFrameOverride =>
      usesSlidingPrimaryProfiles ? slidingFrameOverride : frameOverride;

  bool get isFramePVC => _isPvcSeries(activeFrameSeries);

  /// Replaces the frame reinforcement with the one linked to the currently
  /// selected outer frame and resolves its price for the selected colour.
  /// Keeping this in the model prevents the drawing page and the quantity
  /// table from retaining a reinforcement (or a zero price) from a frame that
  /// the user has already replaced.
  Future<void> syncFrameReinforcement({bool notify = true}) async {
    const reinforcementKey = 'حديد الإطار (Renfort Frame)';

    int? readId(Object? value) {
      if (value is num) return value.toInt();
      return int.tryParse(value?.toString() ?? '');
    }

    if (!isFramePVC) {
      final removed = componentOverrides.remove(reinforcementKey) != null;
      if (notify && removed) notifyListeners();
      return;
    }

    final frame = activeFrameOverride;
    final frameId = readId(frame?['id']);
    final database = await db.db;
    if (frame == null || frameId == null || database == null) return;

    // Always read the current catalogue row. Older saved drawings may have a
    // frame override without the link column even though the catalogue has it.
    final frameRows = await database.query(
      'Sections',
      where: 'id = ?',
      whereArgs: [frameId],
      limit: 1,
    );
    final frameSource = frameRows.isEmpty ? frame : frameRows.first;
    final linkedReinforcementId = readId(
      frameSource['linked_renfort_id'] ?? frame['linked_renfort_id'],
    );

    Map<String, dynamic>? reinforcement;
    if (linkedReinforcementId != null) {
      final rows = await database.query(
        'Sections',
        where: 'id = ?',
        whereArgs: [linkedReinforcementId],
        limit: 1,
      );
      if (rows.isNotEmpty)
        reinforcement = Map<String, dynamic>.from(rows.first);
    }

    // Some older catalogues did not store linked_renfort_id. Use the frame
    // reinforcement from the same series rather than making its row/pricing
    // disappear when such a frame is selected.
    if (reinforcement == null) {
      final seriesId = activeFrameSeries?.id;
      if (seriesId != null) {
        final candidates = await database.query(
          'Sections',
          where:
              "series_id = ? AND (LOWER(type) LIKE ? OR LOWER(name) LIKE ? OR name LIKE ?)",
          whereArgs: [seriesId, '%renfort%', '%renfort%', '%حديد%'],
        );
        if (candidates.isNotEmpty) {
          final preferred = candidates.firstWhere((candidate) {
            final label =
                '${candidate['name'] ?? ''} ${candidate['type'] ?? ''}'
                    .toLowerCase();
            return label.contains('frame') ||
                label.contains('dormant') ||
                label.contains('cadre') ||
                label.contains('إطار');
          }, orElse: () => candidates.first);
          reinforcement = Map<String, dynamic>.from(preferred);
        }
      }
    }

    if (reinforcement == null) {
      final removed = componentOverrides.remove(reinforcementKey) != null;
      if (notify && removed) notifyListeners();
      return;
    }

    final reinforcementId = readId(reinforcement['id']);
    final colorId = readId(selectedDbColor?['id']);
    var price = reinforcementId == null
        ? 0.0
        : await db.getSectionPrice(reinforcementId, colorId);
    if (price <= 0) {
      final rawPrice = reinforcement['price_dzd'] ?? reinforcement['price'];
      price = rawPrice is num
          ? rawPrice.toDouble()
          : double.tryParse(rawPrice?.toString() ?? '') ?? 0.0;
    }

    reinforcement['calculated_price'] = price;
    reinforcement['_linked_frame_id'] = frameId;
    componentOverrides[reinforcementKey] = reinforcement;
    if (notify) notifyListeners();
  }

  /// Material of a sliding zone.  This must stay independent from [isPVC]
  /// because a mixed drawing has two independently selected series.
  bool get isSlidingPVC => _isPvcSeries(activeSlidingSeries ?? activeSeries);

  bool isSlidingZoneNestedInSingleFrame(WindowZone zone) {
    if (systemMode == 'sliding') return false;
    if (zones.length <= 1) return false;
    if (!zones.any((candidate) => candidate.id == zone.id)) return false;
    return getFrameRects().length == 1;
  }

  bool shouldAskSlidingRebateCut(WindowZone zone) {
    return isSlidingZoneNestedInSingleFrame(zone);
  }

  Rect _outerClearRectForRebate() {
    final topOffset = (hasShutter && !hasArchOrSlant && !isCaissonTunnel)
        ? shutterBoxHeight
        : 0.0;
    final bottomFrame = hasBottomFrame ? profileThickness : 0.0;
    final bottomPlinthe = hasFramePlintheBottom ? plintheHeight : 0.0;
    return Rect.fromLTRB(
      profileThickness,
      topOffset + profileThickness,
      math.max(profileThickness, width - profileThickness),
      math.max(
        topOffset + profileThickness,
        height - bottomFrame - bottomPlinthe,
      ),
    );
  }

  bool _zoneEdgeTouchesAnotherZone(
    WindowZone zone, {
    required bool verticalEdge,
    required bool negativeSide,
  }) {
    const tolerance = 3.0;
    final boundary = zone.boundary;
    for (final other in zones) {
      if (other.id == zone.id) continue;
      final otherBoundary = other.boundary;
      if (verticalEdge) {
        final edge = negativeSide ? boundary.left : boundary.right;
        final otherEdge = negativeSide
            ? otherBoundary.right
            : otherBoundary.left;
        final overlap =
            math.min(boundary.bottom, otherBoundary.bottom) -
            math.max(boundary.top, otherBoundary.top);
        if ((edge - otherEdge).abs() <= divisionThickness + tolerance &&
            overlap > 5.0) {
          return true;
        }
      } else {
        final edge = negativeSide ? boundary.top : boundary.bottom;
        final otherEdge = negativeSide
            ? otherBoundary.bottom
            : otherBoundary.top;
        final overlap =
            math.min(boundary.right, otherBoundary.right) -
            math.max(boundary.left, otherBoundary.left);
        if ((edge - otherEdge).abs() <= divisionThickness + tolerance &&
            overlap > 5.0) {
          return true;
        }
      }
    }
    return false;
  }

  int slidingRebateSideCount(WindowZone zone, {required bool horizontal}) {
    if (!zone.cutSlidingGlassRebate) return 0;
    if (!isSlidingZoneNestedInSingleFrame(zone)) return 0;
    if (openingSashOverlap <= 0) return 0;

    const tolerance = 3.0;
    final outerClear = _outerClearRectForRebate();
    final boundary = zone.boundary;
    var count = 0;

    if (horizontal) {
      final hasLeft =
          (boundary.left - outerClear.left).abs() <= tolerance ||
          _zoneEdgeTouchesAnotherZone(
            zone,
            verticalEdge: true,
            negativeSide: true,
          );
      final hasRight =
          (boundary.right - outerClear.right).abs() <= tolerance ||
          _zoneEdgeTouchesAnotherZone(
            zone,
            verticalEdge: true,
            negativeSide: false,
          );
      if (hasLeft) count++;
      if (hasRight) count++;
    } else {
      final hasTop =
          (boundary.top - outerClear.top).abs() <= tolerance ||
          _zoneEdgeTouchesAnotherZone(
            zone,
            verticalEdge: false,
            negativeSide: true,
          );
      final hasBottom =
          ((hasBottomFrame || hasFramePlintheBottom) &&
              (boundary.bottom - outerClear.bottom).abs() <= tolerance) ||
          _zoneEdgeTouchesAnotherZone(
            zone,
            verticalEdge: false,
            negativeSide: false,
          );
      if (hasTop) count++;
      if (hasBottom) count++;
    }
    return count;
  }

  double slidingRebateDeduction(WindowZone zone, {required bool horizontal}) {
    return openingSashOverlap *
        slidingRebateSideCount(zone, horizontal: horizontal);
  }

  double profileThickness;

  bool coupleFrames = true;

  double get divisionThickness {
    if (coupleFrames) {
      return profileThickness * 2;
    }
    return mullionThickness;
  }

  double get mullionThickness {
    final s = getSectionByType('mullion');
    if (s != null) {
      if (s.visibleWidth > 0) return s.visibleWidth;
      if (s.thickness > 0) return s.thickness;
    }
    return profileThickness;
  }

  String _mullionKey(bool isHorizontal, double position) =>
      '${isHorizontal ? 'H' : 'V'}_${position.toStringAsFixed(1)}';

  AluminumSection? _frameForMullion(MullionProfileType profileType) {
    final series = activeFrameSeries;
    if (series == null) return null;

    final frames = series.sections
        .where(
          (section) => section.isFrame || section.type.toLowerCase() == 'frame',
        )
        .toList();
    if (frames.isEmpty) return null;

    if (profileType == MullionProfileType.grooved) {
      for (final frame in frames) {
        final code = frame.code.toLowerCase();
        final name = frame.name.toLowerCase();
        if (code.contains('140') || name.contains('140')) return frame;
      }
    }

    if (selectedFrameCode != null && selectedFrameCode!.isNotEmpty) {
      for (final frame in frames) {
        if (frame.code == selectedFrameCode) return frame;
      }
    }

    return frames.first;
  }

  /// Returns the selected profile for a mullion. A null result intentionally
  /// means that the standard mullion profile should be used.
  Map<String, dynamic>? effectiveMullionSectionAt(
    bool isHorizontal,
    double position,
  ) {
    final key = _mullionKey(isHorizontal, position);
    final override = mullionSectionOverrides[key];
    if (override != null) return Map<String, dynamic>.from(override);

    final profileType = mullionProfiles[key] ?? MullionProfileType.standard;
    if (profileType == MullionProfileType.standard) {
      return null;
    }

    if (profileType == MullionProfileType.flat && activeFrameOverride != null) {
      return Map<String, dynamic>.from(activeFrameOverride!);
    }

    return _frameForMullion(profileType)?.toMap();
  }

  bool _isEnabledFlag(Object? value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) {
      return value.trim().toLowerCase() == 'true' || value.trim() == '1';
    }
    return false;
  }

  /// A flat mullion is represented by two frame profiles. An explicit flag on
  /// a per-mullion override takes precedence, allowing imported orders to
  /// retain their original construction.
  bool isDoubleFrameMullionAt(bool isHorizontal, double position) {
    final key = _mullionKey(isHorizontal, position);
    final override = mullionSectionOverrides[key];
    if (override != null) {
      for (final flag in const [
        'is_double_frame',
        'isDoubleFrame',
        'double_frame',
        'doubleFrame',
      ]) {
        if (override.containsKey(flag)) return _isEnabledFlag(override[flag]);
      }
    }
    return mullionProfiles[key] == MullionProfileType.flat;
  }

  bool isGroovedFrameMullionAt(bool isHorizontal, double position) =>
      mullionProfiles[_mullionKey(isHorizontal, position)] ==
      MullionProfileType.grooved;

  /// For a grooved frame, false means the cavity faces left/top and true
  /// means it faces right/bottom.
  bool isGroovedMullionCavityOnPositiveSide(
    bool isHorizontal,
    double position,
  ) =>
      groovedMullionCavityOnPositiveSide[_mullionKey(isHorizontal, position)] ??
      false;

  double _sectionVisibleWidth(Map<String, dynamic>? section) {
    if (section == null) return 0.0;
    for (final field in const ['visible_width', 'thickness']) {
      final value = section[field];
      if (value is num && value > 0) return value.toDouble();
    }
    return 0.0;
  }

  /// Uses the widest selected mullion while finding adjoining zones. This
  /// keeps a custom frame-140 or double-frame selection from being skipped.
  double get maximumMullionThickness {
    var maximum = mullionThickness;
    for (final section in mullionSectionOverrides.values) {
      final width = _sectionVisibleWidth(section);
      if (width > maximum) maximum = width;
    }
    for (final profileType in mullionProfiles.values) {
      if (profileType == MullionProfileType.standard) {
        continue;
      }
      final width = _sectionVisibleWidth(
        profileType == MullionProfileType.flat ? activeFrameOverride : null,
      );
      final frameWidth = _frameForMullion(profileType)?.visibleWidth ?? 0.0;
      if (width > maximum) maximum = width;
      if (frameWidth > maximum) maximum = frameWidth;
    }
    return maximum;
  }

  double get plintheHeight {
    if (componentOverrides.containsKey('بلانت (Plinthe)')) {
      return (componentOverrides['بلانت (Plinthe)']['visible_width'] ?? 0.0)
          .toDouble();
    }
    final s = getSectionByType('plinthe');
    if (s != null) return s.visibleWidth;
    return 0.0;
  }

  bool hasBottomFrame = true;
  bool hasFramePlintheBottom = false;
  bool isInternalView = true;
  bool isDrawingMode = false;
  String drawingMode = 'split'; // 'split' or 'add_frame'

  void setDrawingModeAction(String action) {
    drawingMode = action;
    notifyListeners();
  }

  bool hasShutter = false;
  bool isCaissonTunnel = false;
  Map<String, dynamic>? caissonPayload;
  bool isMoustiquaire = false;
  Map<String, dynamic>? moustiquairePayload;
  bool isGlassWork = false;
  Map<String, dynamic>? glassWorkPayload;
  bool showBottomWall = true;
  bool showWall = false;
  String wallColor = 'red';
  int shutterIntercalaireRatio = 1;
  double shutterPosition = 0.5;

  int? selectedShutterLameId;
  int? selectedShutterKitId;
  int? selectedShutterMotorId;

  bool motorHasInterrupteur = false;
  bool motorHasTelecommande = false;

  String shutterMechanism = 'حزام';
  String shutterDriveSide = 'right';
  String shutterLame = 'Lame Injectée';
  String shutterGlissiere = 'Glissière 25';
  String? shutterHeightWarning;

  Future<void> updateShutterLame(String name) async {
    shutterLame = name;
    final database = await db.db;
    if (database != null) {
      final exactMatch = await database.query(
        'ShutterComponents',
        where: 'name = ? AND (is_active = 1 OR is_active IS NULL)',
        whereArgs: [name],
      );
      if (exactMatch.isNotEmpty) {
        componentOverrides['الشرائح (Lames)'] = Map<String, dynamic>.from(
          exactMatch.first,
        );
      }
    }
    await updateShutterDefaultsIfNeeded();
    notifyListeners();
  }

  String selectedSashCode = '104';

  bool useSystemOB = false;
  bool useDemiOB = false;
  bool useVerrouCentral = false;

  List<Map<String, dynamic>> systemObComponents = [];
  List<Map<String, dynamic>> verrouCentralComponents = [];

  int get cremoneLengthCm {
    double heightCm = height / 10.0;
    double targetH = (hasShutter && !hasArchOrSlant)
        ? (heightCm - 35)
        : (heightCm - 20);

    if (targetH >= 180) return 180;
    if (targetH >= 40) return (targetH / 20.0).floor() * 20;
    if (targetH >= 30) return 30;
    return 30;
  }

  int get gachePerEspagnolette {
    int len = cremoneLengthCm;
    if (len < 100) return 2;
    if (len <= 140) return 3;
    return 4;
  }

  bool hasSideCovers = true;
  bool sideCoverUseSecondWidth = false;

  // Legacy drawings use complete covers. A custom layout replaces that
  // complete surround with exactly the saved segments below.
  bool useCustomSideCoverLayout = false;
  List<SideCoverSegment> sideCoverSegments = [];
  bool hasInternalSlidingSideCover = false;
  AluminumSection? selectedInternalSlidingSideCover;
  Map<String, dynamic>? internalSlidingSideCoverOverride;

  // A side hidden by the cover buttons is distinct from the shutter rails.
  // This also lets old, partial custom layouts keep their untouched sides.
  Set<String> hiddenSideCoverSegments = {};
  bool isFrame140 = false;
  bool isShutterOnly = false;
  bool drawNextShapeAsShutterOnly = false;
  Set<String> removedShutterSides = {};
  String? workshopName;

  double caissonTunnelHeight = 300.0; // default 30 cm (300 mm)
  double? customShutterBoxHeight;

  double get shutterBoxHeight {
    if (!(hasShutter && !hasArchOrSlant)) return 0.0;
    if (isCaissonTunnel) {
      return caissonTunnelHeight;
    }
    if (customShutterBoxHeight != null) {
      return customShutterBoxHeight!;
    }
    if (height <= 1600) return 155.0;
    if (height <= 2400) return 185.0;
    return 205.0;
  }

  Rect get expectedOuterFrameClearBoundary {
    final topBox = hasShutter && !hasArchOrSlant && !isCaissonTunnel
        ? shutterBoxHeight
        : 0.0;
    final bottomFrame = hasBottomFrame ? profileThickness : 0.0;
    final bottomPlinthe = hasFramePlintheBottom ? plintheHeight : 0.0;
    return Rect.fromLTRB(
      profileThickness,
      topBox + profileThickness,
      math.max(profileThickness, width - profileThickness),
      math.max(topBox + profileThickness, height - bottomFrame - bottomPlinthe),
    );
  }

  /// A drawing with one zone always fills the exact clear opening of the
  /// selected outer frame. Rebuilding this boundary prevents a former frame
  /// width or caisson height from leaking into sash/glass cutting dimensions.
  void _synchronizeSingleZoneWithOuterFrame() {
    if (zones.length != 1 || width <= 0 || height <= 0) return;
    zones.first.boundary = expectedOuterFrameClearBoundary;
  }

  void _synchronizeZonesAfterShutterBoxChange(
    double previousBoxHeight,
    double nextBoxHeight,
  ) {
    if ((previousBoxHeight - nextBoxHeight).abs() <= 0.1 || zones.isEmpty) {
      _synchronizeSingleZoneWithOuterFrame();
      return;
    }

    if (zones.length == 1) {
      _synchronizeSingleZoneWithOuterFrame();
      return;
    }

    final previousTop = previousBoxHeight + profileThickness;
    final nextTop = nextBoxHeight + profileThickness;
    final bottomFrame = hasBottomFrame ? profileThickness : 0.0;
    final bottomPlinthe = hasFramePlintheBottom ? plintheHeight : 0.0;
    final innerBottom = height - bottomFrame - bottomPlinthe;
    final previousHeight = innerBottom - previousTop;
    final nextHeight = innerBottom - nextTop;
    if (previousHeight <= 0 || nextHeight <= 0) return;

    final scale = nextHeight / previousHeight;
    for (final zone in zones) {
      final top = nextTop + (zone.boundary.top - previousTop) * scale;
      final bottom = nextTop + (zone.boundary.bottom - previousTop) * scale;
      zone.boundary = Rect.fromLTRB(
        zone.boundary.left,
        top,
        zone.boundary.right,
        bottom,
      );
    }
  }

  void setCaissonTunnelHeight(double value) {
    if (caissonTunnelHeight == value) return;
    _saveSnapshot();
    final previousBoxHeight = shutterBoxHeight;
    caissonTunnelHeight = value;
    _synchronizeZonesAfterShutterBoxChange(previousBoxHeight, shutterBoxHeight);
    lastLayoutSize = null;
    notifyListeners();
  }

  AluminumSection? selectedSideCover;

  List<AluminumSection> get availableSideCovers {
    // The cover must follow the series that draws the visible outer frame.
    // In mixed/sliding drawings this can be different from activeSeries.
    final series = activeFrameSeries ?? activeSeries;
    if (series == null) return [];
    return series.sections.where((s) {
      final type = s.type.toLowerCase();
      final name = s.name.toLowerCase();
      return type.contains('couvre') ||
          type.contains('side_cover') ||
          type.contains('غطاء') ||
          type.contains('جانبي') ||
          name.contains('couvre') ||
          name.contains('cover') ||
          name.contains('غطاء') ||
          name.contains('جانبي');
    }).toList();
  }

  bool get isSideCoverAllowed {
    final frame = getSectionByType('frame');
    // A cover found in the active frame series is always drawable when the
    // user enables it. This protects older TPR catalogue rows whose legacy
    // allows_side_cover flag was stored as zero.
    if (availableSideCovers.isNotEmpty || (frame?.couvreJointWidth ?? 0) > 0) {
      return true;
    }
    if (frame != null && !frame.allowsSideCover) {
      return false;
    }
    if (isPVC) return true;
    if (frame == null) return true;
    final codeLower = frame.code.toLowerCase().trim();
    final nameLower = frame.name.toLowerCase().trim();

    if (systemMode != 'sliding') {
      if (codeLower == '4002' ||
          codeLower == '4003' ||
          nameLower.contains('monobloc') ||
          nameLower.contains('rénovation') ||
          nameLower.contains('renovation')) {
        return false;
      }
    } else {
      if (codeLower == '02' ||
          codeLower == '03' ||
          nameLower.contains('monobloc')) {
        return false;
      }
    }
    return true;
  }

  bool get isIntegratedFrame {
    if (activeFrameOverride != null) {
      final nameLower = (activeFrameOverride!['name'] ?? '')
          .toString()
          .toLowerCase();
      final typeLower = (activeFrameOverride!['type'] ?? '')
          .toString()
          .toLowerCase();
      final double cjW =
          (activeFrameOverride!['couvre_joint_width'] as num?)?.toDouble() ??
          0.0;
      if (cjW > 0 ||
          nameLower.contains('مدمج') ||
          nameLower.contains('intégré') ||
          nameLower.contains('integre') ||
          nameLower.contains('monobloc') ||
          typeLower.contains('monobloc')) {
        return true;
      }
    }
    final frame = getSectionByType('frame');
    if (frame == null) return false;
    if (frame.couvreJointWidth > 0) return true;
    final nameLower = frame.name.toLowerCase();
    final codeLower = frame.code.toLowerCase();
    return nameLower.contains('مدمج') ||
        nameLower.contains('intégré') ||
        nameLower.contains('integre') ||
        nameLower.contains('monobloc') ||
        codeLower.contains('103');
  }

  /// Width of the selected standalone side-cover face.
  ///
  /// The first face is stored in `couvre_joint_width` and the second in
  /// `visible_width`. This getter deliberately never reads the frame, so an
  /// integrated-frame width cannot leak into a standalone cover calculation.
  double get standaloneSideCoverWidth {
    double firstWidth = selectedSideCover?.couvreJointWidth ?? 0.0;
    double secondWidth = selectedSideCover?.visibleWidth ?? 0.0;

    if (selectedSideCover == null && sideCoverOverride != null) {
      double read(String key) {
        final value = sideCoverOverride![key];
        return value is num
            ? value.toDouble()
            : double.tryParse(value?.toString() ?? '') ?? 0.0;
      }

      firstWidth = read('couvre_joint_width');
      secondWidth = read('visible_width');
    }

    final selectedWidth = sideCoverUseSecondWidth ? secondWidth : firstWidth;
    final otherWidth = sideCoverUseSecondWidth ? firstWidth : secondWidth;
    if (selectedWidth > 0) return selectedWidth;
    if (otherWidth > 0) return otherWidth;
    return 0.0;
  }

  /// Thickness of the selected standalone cover only. It is used to shorten
  /// the frame once for every side on which that cover is actually installed.
  double get standaloneSideCoverThickness {
    if (selectedSideCover != null) {
      return selectedSideCover!.couvreJointThickness;
    }
    final value = sideCoverOverride?['couvre_joint_thickness'];
    return value is num
        ? value.toDouble()
        : double.tryParse(value?.toString() ?? '') ?? 0.0;
  }

  List<AluminumSection> get availableInternalSlidingSideCovers {
    final series = activeSlidingSeries ?? activeSeries;
    if (series == null) return const <AluminumSection>[];
    return series.sections.where((section) {
      final type = section.type.toLowerCase();
      final name = section.name.toLowerCase();
      return type.contains('couvre') ||
          type.contains('side_cover') ||
          type.contains('cover') ||
          type.contains('غطاء') ||
          type.contains('جانبي') ||
          name.contains('couvre') ||
          name.contains('cover') ||
          name.contains('غطاء') ||
          name.contains('جانبي');
    }).toList();
  }

  Map<String, dynamic>? get effectiveInternalSlidingSideCoverMap {
    if (selectedInternalSlidingSideCover != null) {
      return selectedInternalSlidingSideCover!.toMap();
    }
    return internalSlidingSideCoverOverride;
  }

  double get internalSlidingSideCoverWidth {
    final selected = selectedInternalSlidingSideCover;
    if (selected != null) {
      if (selected.couvreJointWidth > 0) return selected.couvreJointWidth;
      if (selected.visibleWidth > 0) return selected.visibleWidth;
    }

    final override = internalSlidingSideCoverOverride;
    if (override == null) return 0.0;
    for (final key in const ['couvre_joint_width', 'visible_width']) {
      final value = override[key];
      if (value is num && value > 0) return value.toDouble();
      final parsed = double.tryParse(value?.toString() ?? '');
      if (parsed != null && parsed > 0) return parsed;
    }
    return 0.0;
  }

  void _selectDefaultInternalSlidingSideCover() {
    final covers = availableInternalSlidingSideCovers;
    if (covers.isEmpty) return;
    final currentId = internalSlidingSideCoverOverride?['id']?.toString();
    final selected = currentId == null
        ? covers.first
        : covers.firstWhere(
            (cover) => cover.id.toString() == currentId,
            orElse: () => covers.first,
          );
    selectedInternalSlidingSideCover = selected;
    internalSlidingSideCoverOverride = selected.toMap();
  }

  /// Integrated-cover width from the selected frame only.
  double get integratedFrameSideCoverWidth {
    if (activeFrameOverride != null) {
      final value = activeFrameOverride!['couvre_joint_width'];
      return value is num
          ? value.toDouble()
          : double.tryParse(value?.toString() ?? '') ?? 0.0;
    }
    return getSectionByType('frame')?.couvreJointWidth ?? 0.0;
  }

  double get sideCoverWidth {
    final integratedWidth = integratedFrameSideCoverWidth;
    if (integratedWidth > 0) return integratedWidth;
    if (activeFrameOverride != null) {
      // A selected frame override is authoritative. A zero here means this
      // frame has no integrated cover, so continue with the standalone one.
      return standaloneSideCoverWidth;
    }

    return standaloneSideCoverWidth;
  }

  bool get hasCustomSideCoverLayout =>
      useCustomSideCoverLayout && sideCoverSegments.isNotEmpty;

  double sideCoverSideLength(String side) {
    switch (side.toLowerCase()) {
      case 'left':
      case 'right':
        return height;
      case 'top':
      case 'bottom':
        return width;
      default:
        return 0.0;
    }
  }

  SideCoverSegment? sideCoverSegmentForSide(String side) {
    final normalized = side.toLowerCase();
    for (final segment in sideCoverSegments) {
      if (segment.side == normalized) return segment;
    }
    return null;
  }

  /// Keeps custom cover pieces attached to the frame edges when the overall
  /// window size changes. A piece ending at an outer edge extends with that
  /// edge; a piece wholly inside the frame keeps its explicitly chosen size.
  void _resizeSideCoverSegments(
    double oldWidth,
    double oldHeight,
    double newWidth,
    double newHeight,
  ) {
    if (!useCustomSideCoverLayout || sideCoverSegments.isEmpty) return;

    double lengthFor(String side, double windowWidth, double windowHeight) {
      switch (side.toLowerCase()) {
        case 'left':
        case 'right':
          return windowHeight;
        case 'top':
        case 'bottom':
          return windowWidth;
        default:
          return 0.0;
      }
    }

    // Saved drawings can round a full-length cover by one or two millimetres.
    // Treat that as attached to the outer edge so a couvre-joint still grows
    // with the drawing instead of leaving a thin uncovered gap after resize.
    bool isAtEdge(double value, double edge) => (value - edge).abs() <= 2.0;

    sideCoverSegments = sideCoverSegments.map((segment) {
      final oldLength = lengthFor(segment.side, oldWidth, oldHeight);
      final newLength = lengthFor(segment.side, newWidth, newHeight);
      if (oldLength <= 0 || newLength <= 0) return segment;

      final spansWholeSide =
          segment.startOffset.abs() <= 2.0 &&
          isAtEdge(segment.endOffset, oldLength);
      if (spansWholeSide) {
        return segment.copyWith(startOffset: 0.0, endOffset: newLength);
      }

      // Offset 0 is already fixed to the leading edge. Only values that were
      // anchored at the trailing edge should follow the resized frame.
      final start = isAtEdge(segment.startOffset, oldLength)
          ? newLength
          : segment.startOffset.clamp(0.0, newLength).toDouble();
      final end = isAtEdge(segment.endOffset, oldLength)
          ? newLength
          : segment.endOffset.clamp(0.0, newLength).toDouble();

      if (end <= start) {
        // If a shortened frame would otherwise cut the piece off completely,
        // retain its existing span at the new trailing edge instead of
        // silently turning a customised piece into a full-length cover.
        final preservedLength = math.min(segment.length, newLength);
        return segment.copyWith(
          startOffset: newLength - preservedLength,
          endOffset: newLength,
        );
      }
      return segment.copyWith(startOffset: start, endOffset: end);
    }).toList();
  }

  /// Returns the cover pieces that must be drawn or costed. Older saved
  /// drawings may contain one edited side only; their other sides are the
  /// legacy full surround unless the user has explicitly switched one off.
  List<SideCoverSegment> get effectiveSideCoverSegments {
    // A persisted/custom bottom cover is invalid as soon as the bottom frame
    // is removed. Filter it here as a final drawing/BOM safeguard as well as
    // removing it at the state transition below.
    final storedSegments = sideCoverSegments
        .where(
          (segment) =>
              segment.side != 'bottom' || (hasBottomFrame && showBottomWall),
        )
        .toList();
    if (!useCustomSideCoverLayout) {
      return storedSegments;
    }

    final segments = storedSegments;
    const sides = ['top', 'left', 'right', 'bottom'];
    for (final side in sides) {
      if (side == 'bottom' && (!hasBottomFrame || !showBottomWall)) continue;
      if (hiddenSideCoverSegments.contains(side) ||
          removedShutterSides.contains(side) ||
          segments.any((segment) => segment.side == side)) {
        continue;
      }
      final length = sideCoverSideLength(side);
      if (length <= 0) continue;
      segments.add(
        SideCoverSegment(
          side: side,
          startOffset: 0.0,
          endOffset: length,
          visibleWidth: sideCoverWidth,
        ),
      );
    }
    return segments;
  }

  bool isSideCoverSegmentEnabled(String side) {
    final normalized = side.toLowerCase();
    if (normalized == 'bottom' && (!hasBottomFrame || !showBottomWall)) {
      return false;
    }
    if (!useCustomSideCoverLayout) {
      return !removedShutterSides.contains(normalized);
    }
    return effectiveSideCoverSegments.any(
      (segment) => segment.side == normalized,
    );
  }

  /// The old layout is a complete surround. When one side is customised for
  /// the first time, turn that surround into four explicit full-length pieces
  /// before replacing only the edited side. This keeps the other covers on
  /// screen instead of making them disappear.
  void _materializeLegacySideCoverSegments() {
    if (useCustomSideCoverLayout) return;

    const sides = ['top', 'left', 'right', 'bottom'];
    final segments = <SideCoverSegment>[];
    for (final side in sides) {
      if (side == 'bottom' && (!hasBottomFrame || !showBottomWall)) continue;
      if (removedShutterSides.contains(side)) continue;
      final length = sideCoverSideLength(side);
      if (length <= 0) continue;
      segments.add(
        SideCoverSegment(
          side: side,
          startOffset: 0.0,
          endOffset: length,
          visibleWidth: sideCoverWidth,
        ),
      );
    }
    sideCoverSegments = segments;
    useCustomSideCoverLayout = true;
    hiddenSideCoverSegments.clear();
  }

  /// A short press on a cover-side button only turns that side on or off.
  /// A long press opens the segment editor and does not change this state.
  void toggleSideCoverSegment(String side) {
    const allowedSides = {'left', 'right', 'top', 'bottom'};
    final normalized = side.toLowerCase();
    if (!allowedSides.contains(normalized)) return;
    if (normalized == 'bottom' && (!hasBottomFrame || !showBottomWall)) {
      return;
    }

    _saveSnapshot();
    _materializeLegacySideCoverSegments();
    if (!isSideCoverSegmentEnabled(normalized)) {
      final length = sideCoverSideLength(normalized);
      if (length > 0) {
        hiddenSideCoverSegments.remove(normalized);
        sideCoverSegments = [
          ...sideCoverSegments,
          SideCoverSegment(
            side: normalized,
            startOffset: 0.0,
            endOffset: length,
            visibleWidth: sideCoverWidth,
          ),
        ];
        hasSideCovers = true;
      }
    } else {
      sideCoverSegments = sideCoverSegments
          .where((segment) => segment.side != normalized)
          .toList();
      hiddenSideCoverSegments.add(normalized);
    }
    notifyListeners();
  }

  void saveSideCoverSegment(SideCoverSegment segment) {
    const allowedSides = {'left', 'right', 'top', 'bottom'};
    final side = segment.side.toLowerCase();
    if (!allowedSides.contains(side)) return;
    if (side == 'bottom' && (!hasBottomFrame || !showBottomWall)) return;

    final sideLength = sideCoverSideLength(side);
    if (sideLength <= 0) return;
    final start = segment.startOffset.clamp(0.0, sideLength).toDouble();
    final end = segment.endOffset.clamp(0.0, sideLength).toDouble();
    if (end <= start) return;

    _saveSnapshot();
    _materializeLegacySideCoverSegments();
    final normalized = segment.copyWith(
      side: side,
      startOffset: start,
      endOffset: end,
      // A side-specific cover may be narrower than the selected profile, but
      // it must never project farther than that profile's visible width.
      visibleWidth: segment.visibleWidth.clamp(0.0, sideCoverWidth).toDouble(),
    );
    sideCoverSegments = [
      ...sideCoverSegments.where((item) => item.side != side),
      normalized,
    ];
    useCustomSideCoverLayout = true;
    hiddenSideCoverSegments.remove(side);
    hasSideCovers = true;
    notifyListeners();
  }

  void removeSideCoverSegment(String side) {
    final normalized = side.toLowerCase();
    if (!sideCoverSegments.any((item) => item.side == normalized)) return;
    _saveSnapshot();
    sideCoverSegments = sideCoverSegments
        .where((item) => item.side != normalized)
        .toList();
    useCustomSideCoverLayout = true;
    hiddenSideCoverSegments.add(normalized);
    notifyListeners();
  }

  FrameColor _frameColor = FrameColor.white;

  FrameColor get frameColor => _frameColor;

  set frameColor(FrameColor color) {
    _frameColor = color;
    for (var z in zones) {
      z.sashColor = color;
    }
    notifyListeners();
  }

  Map<String, dynamic>? _selectedDbColor;

  Map<String, dynamic>? get selectedDbColor => _selectedDbColor;

  set selectedDbColor(Map<String, dynamic>? colorData) {
    _saveSnapshot();
    _selectedDbColor = colorData == null
        ? null
        : Map<String, dynamic>.from(colorData);
    for (var z in zones) {
      z.selectedDbColor = _selectedDbColor == null
          ? null
          : Map<String, dynamic>.from(_selectedDbColor!);
    }
    unawaited(refreshSectionPricesForSelectedColor());
    unawaited(refreshBardageColorPrices());
    notifyListeners();
  }

  final Map<int, double> sectionPricesForSelectedColor = <int, double>{};

  bool _isParcloseSection(AluminumSection section) {
    final type = section.type.toLowerCase();
    final name = section.name.toLowerCase();
    return section.code.trim() == '514' ||
        type.contains('parclose') ||
        name.contains('parclose') ||
        type.contains('باكيت') ||
        name.contains('باكيت');
  }

  /// Adds the current colour price to an in-memory catalogue section before
  /// it enters the synchronous BOM calculation.
  Map<String, dynamic> sectionMapWithSelectedColorPrice(
    AluminumSection section,
  ) {
    final result = Map<String, dynamic>.from(section.toMap());
    double? price = sectionPricesForSelectedColor[section.id];
    if (price == null) {
      for (final rawOverride in componentOverrides.values) {
        if (rawOverride is! Map ||
            rawOverride['id']?.toString() != section.id.toString()) {
          continue;
        }
        final rawPrice = rawOverride['calculated_price'];
        price = rawPrice is num
            ? rawPrice.toDouble()
            : double.tryParse(rawPrice?.toString() ?? '');
        if (price != null) break;
      }
    }
    if (price != null) result['calculated_price'] = price;
    return result;
  }

  Future<void> refreshSectionPricesForSelectedColor({
    bool notify = true,
  }) async {
    final sections = <int, AluminumSection>{};
    for (final series in <AluminumSeries?>[activeSeries, activeSlidingSeries]) {
      if (series == null) continue;
      for (final section in series.sections) {
        if (_isParcloseSection(section)) sections[section.id] = section;
      }
    }
    if (sections.isEmpty) return;

    final colorId = selectedDbColor?['id'] as int?;
    try {
      for (final section in sections.values) {
        sectionPricesForSelectedColor[section.id] = await db.getSectionPrice(
          section.id,
          colorId,
        );
      }
      for (final entry in componentOverrides.entries.toList()) {
        final rawOverride = entry.value;
        if (rawOverride is! Map) continue;
        final rawId = rawOverride['id'];
        final id = rawId is num
            ? rawId.toInt()
            : int.tryParse(rawId?.toString() ?? '');
        final price = id == null ? null : sectionPricesForSelectedColor[id];
        if (price == null) continue;
        final updated = Map<String, dynamic>.from(rawOverride);
        updated['calculated_price'] = price;
        componentOverrides[entry.key] = updated;
      }
      if (notify) notifyListeners();
    } catch (error) {
      debugPrint('Unable to refresh parclose prices: $error');
    }
  }

  String _profileColorName(Map<String, dynamic>? colorData) {
    return (colorData?['name'] ?? colorData?['color_name'] ?? '')
        .toString()
        .trim();
  }

  String _normalizedProfileColorName(String value) {
    return value
        .toLowerCase()
        .trim()
        .replaceAll('أ', 'ا')
        .replaceAll('إ', 'ا')
        .replaceAll('آ', 'ا')
        .replaceAll('ى', 'ي')
        .replaceAll('ة', 'ه')
        .replaceAll(RegExp(r'\s+'), ' ');
  }

  bool _isWhiteProfileColor(Map<String, dynamic>? colorData) {
    final name = _normalizedProfileColorName(_profileColorName(colorData));
    final hex = (colorData?['hex_code'] ?? colorData?['hex'] ?? '')
        .toString()
        .replaceAll('#', '')
        .toLowerCase()
        .trim();
    return name.contains('white') ||
        name.contains('blanc') ||
        name.contains('ابيض') ||
        hex == 'ffffff' ||
        hex == 'fff';
  }

  bool _isWoodProfileColor(Map<String, dynamic>? colorData) {
    final name = _normalizedProfileColorName(_profileColorName(colorData));
    return name.contains('wood') ||
        name.contains('bois') ||
        name.contains('خشب') ||
        name.contains('خشبي') ||
        name.contains('chene') ||
        name.contains('oak') ||
        name.contains('desert') ||
        name.contains('ديزر') ||
        name.contains('ديزير');
  }

  /// Resolves the colour actually used by a bardage cell. In automatic mode
  /// it always follows the current frame/series colour; an explicit override
  /// is accepted only when it belongs to the active series colour list.
  Map<String, dynamic>? getBardageColorForSpec(GlassSpecification glass) {
    if (glass.bardageUsesFrameColor) return selectedDbColor;

    final requested = _normalizedProfileColorName(glass.panneauColor ?? '');
    if (requested.isNotEmpty) {
      for (final color in availableColors) {
        if (_normalizedProfileColorName(_profileColorName(color)) ==
            requested) {
          return color;
        }
      }
    }
    return selectedDbColor;
  }

  String getBardageColorNameForSpec(GlassSpecification glass) {
    final resolved = _profileColorName(getBardageColorForSpec(glass));
    if (resolved.isNotEmpty) return resolved;
    final fallback = _profileColorName(selectedDbColor);
    return fallback.isNotEmpty
        ? fallback
        : frameColor.toString().split('.').last;
  }

  /// Reads the price attached to the resolved bardage colour. The complete
  /// colour-price map is cached on the selected bardage profile because BOM
  /// generation is synchronous and may contain several bardage colours.
  double getBardagePriceForColor(
    Map<String, dynamic>? colorData,
    String colorName,
  ) {
    final rawOverride = componentOverrides['البارداج (Bardage)'];
    if (rawOverride is! Map) return 0.0;
    final override = Map<String, dynamic>.from(rawOverride);
    final rawPrices = override['color_prices'];
    if (rawPrices is Map) {
      final colorId = colorData?['id'];
      final keys = <String>[
        if (colorId != null) 'id:$colorId',
        'name:${_normalizedProfileColorName(colorName)}',
      ];
      for (final key in keys) {
        final rawPrice = rawPrices[key];
        final price = rawPrice is num
            ? rawPrice.toDouble()
            : double.tryParse(rawPrice?.toString() ?? '');
        if (price != null && price >= 0) return price;
      }
    }

    final rawFallback =
        override['calculated_price'] ??
        override['price_dzd'] ??
        override['price'] ??
        0.0;
    return rawFallback is num
        ? rawFallback.toDouble()
        : double.tryParse(rawFallback.toString()) ?? 0.0;
  }

  Future<void> refreshBardageColorPrices({bool notify = true}) async {
    final rawOverride = componentOverrides['البارداج (Bardage)'];
    if (rawOverride is! Map) return;
    final override = Map<String, dynamic>.from(rawOverride);
    final rawId = override['id'];
    final sectionId = rawId is num
        ? rawId.toInt()
        : int.tryParse(rawId?.toString() ?? '');
    if (sectionId == null) return;

    final fallbackRaw = override['price_dzd'] ?? override['price'] ?? 0.0;
    final fallbackPrice = fallbackRaw is num
        ? fallbackRaw.toDouble()
        : double.tryParse(fallbackRaw.toString()) ?? 0.0;
    final prices = <String, double>{};
    for (final color in availableColors) {
      final rawColorId = color['id'];
      final colorId = rawColorId is num
          ? rawColorId.toInt()
          : int.tryParse(rawColorId?.toString() ?? '');
      if (colorId == null) continue;
      var price = await db.getSectionPrice(sectionId, colorId);
      if (price <= 0) price = fallbackPrice;
      prices['id:$colorId'] = price;
      final name = _normalizedProfileColorName(_profileColorName(color));
      if (name.isNotEmpty) prices['name:$name'] = price;
    }
    override['color_prices'] = prices;

    final selectedName = _profileColorName(selectedDbColor);
    final selectedId = selectedDbColor?['id'];
    if (selectedId != null && prices.containsKey('id:$selectedId')) {
      override['calculated_price'] = prices['id:$selectedId'];
    } else {
      final selectedKey = 'name:${_normalizedProfileColorName(selectedName)}';
      override['calculated_price'] = prices[selectedKey] ?? fallbackPrice;
    }
    componentOverrides['البارداج (Bardage)'] = override;
    if (notify) notifyListeners();
  }

  Map<String, dynamic>? _selectedAccessoryColor;

  Map<String, dynamic>? get selectedAccessoryColor => _selectedAccessoryColor;

  set selectedAccessoryColor(Map<String, dynamic>? colorData) {
    _saveSnapshot();
    _selectedAccessoryColor = colorData;
    notifyListeners();
  }

  Color get accessoryColor {
    if (_selectedAccessoryColor != null) {
      return getEffectiveGradientColors(
        frameColor,
        _selectedAccessoryColor,
      ).last;
    }
    final colors = getEffectiveGradientColors(frameColor, selectedDbColor);
    return colors.last;
  }

  List<WindowZone> zones = [];
  Map<String, MullionProfileType> mullionProfiles = {};

  // false = left/top side, true = right/bottom side.
  Map<String, bool> groovedMullionCavityOnPositiveSide = {};
  Map<String, Map<String, dynamic>> mullionSectionOverrides = {};
  String? primaryMullionAxis;
  SelectionInfo selection = SelectionInfo.none;
  String? activeSubZone;
  bool showZoneMenu = false;
  final List<WindowSnapshot> _history = [];
  final List<WindowSnapshot> _redoHistory = [];

  bool get canUndo => _history.isNotEmpty;

  bool get canRedo => _redoHistory.isNotEmpty;

  double canvasScale = 1.0;
  double canvasDx = 0.0;
  double canvasDy = 0.0;
  Size? lastLayoutSize;
  Offset? drawingStart;
  Offset? drawingCurrent;
  Offset?
  pendingDrawStart; // set on touch-down, committed to drawingStart only after real drag
  double? drawnLeft;
  double? drawnTop;

  /// When enabled, a newly added outer frame copies the size of the frame
  /// directly next to the side where it is attached.
  bool copyPreviousFrameSize = false;
  bool? _lastIsEmpty;
  double? _lastWidth;
  double? _lastHeight;
  double? _lastDrawnLeft;
  double? _lastDrawnTop;
  bool? _lastShowWall;
  bool? _lastShowBottomWall;
  bool? _lastHasShutter;
  bool? _lastIsCaissonTunnel;
  double? _lastShutterBoxHeight;

  final SqlDatabase db;
  List<AluminumProfileSystem> availableSystems = [];
  AluminumSeries? activeSeries;
  AluminumSeries? activeSlidingSeries;
  Map<String, dynamic>? slidingFrameOverride;
  Map<String, dynamic>? slidingSashOverride;
  String? systemMode;
  List<Map<String, dynamic>> availableColors = [];
  List<Map<String, dynamic>> availableAccessoryColors = [];

  Future<void> _loadColorsForProfile(int profileId) async {
    final previousColorId = _selectedDbColor?['id'];
    final previousColorName =
        (_selectedDbColor?['name'] ?? _selectedDbColor?['color_name'])
            ?.toString()
            .toLowerCase()
            .trim();
    final previousWasWood = _isWoodProfileColor(_selectedDbColor);
    availableColors = (await db.getColorsForProfile(
      profileId,
    )).map((color) => Map<String, dynamic>.from(color)).toList();

    Map<String, dynamic>? selectedColor;
    if (!previousWasWood && previousColorId != null) {
      for (final color in availableColors) {
        if (color['id']?.toString() == previousColorId.toString()) {
          selectedColor = color;
          break;
        }
      }
    }
    if (!previousWasWood &&
        selectedColor == null &&
        previousColorName != null &&
        previousColorName.isNotEmpty) {
      for (final color in availableColors) {
        final cName = (color['name'] ?? color['color_name'])
            ?.toString()
            .toLowerCase()
            .trim();
        if (cName == previousColorName ||
            (cName != null &&
                (cName.contains(previousColorName) ||
                    previousColorName.contains(cName)))) {
          selectedColor = color;
          break;
        }
      }
    }
    // A new drawing must begin with the white finish, independently of the
    // order in which the colours happen to be stored in the database.
    selectedColor ??= _defaultFrameColor();
    selectedColor ??= availableColors.isNotEmpty ? availableColors.first : null;

    _selectedDbColor = selectedColor == null
        ? null
        : Map<String, dynamic>.from(selectedColor);
    for (final zone in zones) {
      zone.selectedDbColor = _selectedDbColor == null
          ? null
          : Map<String, dynamic>.from(_selectedDbColor!);
    }
  }

  Map<String, dynamic>? _defaultFrameColor() {
    for (final color in availableColors) {
      if (_isWhiteProfileColor(color)) {
        return color;
      }
    }
    // A missing white price configuration must never make a new drawing look
    // grey merely because grey happens to be the first database row.  The
    // enum default stays white until the workshop configures a white color.
    return null;
  }

  WindowModel({
    required this.db,
    this.width = 0,
    this.height = 0,
    this.profileThickness = 10.0,
    this.systemMode,
  });

  List<Map<String, dynamic>> allGlassCache = [];

  Future<void> loadGlassProducts() async {
    try {
      final list = await db.readGlass();
      final dbInstance = await db.db;
      List<Map<String, dynamic>> colorPrices = [];
      try {
        colorPrices = await dbInstance!.query('GlassColorPrices');
      } catch (_) {}

      allGlassCache = [];
      for (var g in list) {
        final typeLower = g['type'].toString().toLowerCase();
        if (typeLower == 'panneau' ||
            typeLower == 'baguette' ||
            typeLower == 'rosette') {
          final colorsStr = g['color']?.toString() ?? '';
          if (colorsStr.isNotEmpty) {
            final colorsList = colorsStr.split(',');
            for (var col in colorsList) {
              final trimmedCol = col.trim();
              if (trimmedCol.isEmpty) continue;
              double specificPrice = 0.0;
              final match = colorPrices.firstWhere(
                (cp) =>
                    cp['glass_id'] == g['id'] &&
                    cp['color_name'].toString().toLowerCase() ==
                        trimmedCol.toLowerCase(),
                orElse: () => <String, dynamic>{},
              );
              if (match.isNotEmpty) {
                specificPrice = (match['price'] as num).toDouble();
              } else {
                specificPrice = (g['price_per_sqm'] as num?)?.toDouble() ?? 0.0;
              }

              final virtualG = Map<String, dynamic>.from(g);
              virtualG['color'] = trimmedCol;
              virtualG['price_per_sqm'] = specificPrice;
              allGlassCache.add(virtualG);
            }
          } else {
            allGlassCache.add(g);
          }
        } else {
          allGlassCache.add(g);
        }
      }

      availableIntercalls = allGlassCache
          .where((g) => g['type'].toString().toLowerCase() == 'intercall')
          .toList();
      availableGases = allGlassCache
          .where((g) => g['type'].toString().toLowerCase() == 'gas')
          .toList();
      notifyListeners();
    } catch (e) {
      debugPrint("Error loading glass products: $e");
    }
  }

  String getFinishName(GlassFinish f) {
    switch (f) {
      case GlassFinish.clair:
        return 'شفاف';
      case GlassFinish.stopSol:
        return 'ستوبسول';
      case GlassFinish.sable:
        return 'صابلي';
      case GlassFinish.delta:
        return 'دلتا';
      case GlassFinish.tuC:
        return 'تيسي';
      case GlassFinish.nevada:
        return 'نيفادا';
      case GlassFinish.cuisine:
        return 'مطبخ';
      case GlassFinish.aFleur:
        return 'مورد';
      case GlassFinish.paneauSandwitch:
        return 'بانو';
      case GlassFinish.resine:
        return 'ارزين';
      case GlassFinish.plexyGlass:
        return 'بليكسي';
      case GlassFinish.paneauSandwitchDecore:
        return 'بانو ديكور';
      case GlassFinish.bardage:
        return 'بارداج';
      case GlassFinish.moussa:
        return 'موسى';
      case GlassFinish.harari:
        return 'حراري';
      case GlassFinish.vitrageArme:
        return 'زجاج مسلح';
    }
  }

  String getClosedColoreName(ClosedGlassColor d) {
    switch (d) {
      case ClosedGlassColor.transparent:
        return 'شفاف';
      case ClosedGlassColor.white:
        return 'ابيض';
      case ClosedGlassColor.grisClair:
        return 'رمادي فاتح';
      case ClosedGlassColor.fbmfonce:
        return 'خشبي داكن';
      case ClosedGlassColor.grissoris:
        return 'رمادي داكن';
      case ClosedGlassColor.black:
        return 'اسود';
      case ClosedGlassColor.beige:
        return 'باج';
      case ClosedGlassColor.fbmClair:
        return 'خشبي فاتح';
      case ClosedGlassColor.opaque:
        return 'عاتم';
      case ClosedGlassColor.marberier:
        return 'رخامي';
    }
  }

  String getArabicColorName(GlassColor color) {
    switch (color) {
      case GlassColor.transparent:
        return 'شفاف';
      case GlassColor.blue:
        return 'أزرق';
      case GlassColor.brown:
        return 'بني';
      case GlassColor.green:
        return 'أخضر';
      case GlassColor.gray:
        return 'رمادي';
      case GlassColor.grayAgc:
        return 'رمادي';
      case GlassColor.blueAgc:
        return 'أزرق';
    }
  }

  List<String> getFinishKeywords(GlassFinish f) {
    switch (f) {
      case GlassFinish.clair:
        return ['شفاف', 'clair', 'clear', 'simple', 'glass', 'عادي', 'بسيط'];
      case GlassFinish.stopSol:
        return ['ستوبسول', 'stopsol', 'stop sol', 'سوبسول', 'ستوب سول'];
      case GlassFinish.sable:
        return ['صابلي', 'sable', 'sablé'];
      case GlassFinish.delta:
        return ['دلتا', 'delta'];
      case GlassFinish.tuC:
        return ['تيسي', 'tu c', 'tuc'];
      case GlassFinish.nevada:
        return ['نيفادا', 'nevada'];
      case GlassFinish.cuisine:
        return ['مطبخ', 'cuisine'];
      case GlassFinish.aFleur:
        return ['مورد', 'a fleur', 'fleur'];
      case GlassFinish.paneauSandwitch:
        return ['بانو', 'paneau', 'sandwich', 'sandwitch'];
      case GlassFinish.resine:
        return ['ارزين', 'resine', 'résine', 'أرزين'];
      case GlassFinish.plexyGlass:
        return ['بليكسي', 'plexy', 'plexiglas', 'plexiglass'];
      case GlassFinish.paneauSandwitchDecore:
        return ['بانو ديكور', 'paneau decore', 'sandwich decore'];
      case GlassFinish.bardage:
        return ['بارداج', 'bardage'];
      case GlassFinish.moussa:
        return ['موسى', 'moussa'];
      case GlassFinish.harari:
        return ['حراري', 'harari'];
      case GlassFinish.vitrageArme:
        return ['مسلح', 'armé', 'arme', 'vitrage armé', 'vitrage arme'];
    }
  }

  List<String> getColorKeywords(GlassColor color) {
    switch (color) {
      case GlassColor.transparent:
        return [
          'شفاف',
          'transparent',
          'بدون لون',
          'clair',
          'clear',
          'صافي',
          '',
        ];
      case GlassColor.blue:
        return ['أزرق', 'ازرق', 'azur', 'bleu', 'blue'];
      case GlassColor.brown:
        return [
          'بني',
          'marron',
          'brun',
          'brown',
          'bronze',
          'برونز',
          'كوكو',
          'coco',
        ];
      case GlassColor.green:
        return ['أخضر', 'اخضر', 'vert', 'green'];
      case GlassColor.gray:
        return ['رمادي', 'gris', 'gray', 'grey', 'falken', 'فالكن'];
      case GlassColor.grayAgc:
        return [
          'رمادي agc',
          'رمادي بلجيكي',
          'gris agc',
          'gris belge',
          'grey agc',
          'agc',
        ];
      case GlassColor.blueAgc:
        return [
          'أزرق بلجيكي',
          'ازرق بلجيكي',
          'بلجيكي أزرق',
          'بلجيكي ازرق',
          'بلجيكي',
          'أزرق agc',
          'bleu agc',
          'bleu belge',
          'blue belge',
          'belge',
        ];
    }
  }

  bool hasExactColorForFinish(GlassFinish finish, GlassColor color) {
    List<String> finishKws = getFinishKeywords(finish);
    List<String> colorKws = getColorKeywords(color);

    return allGlassCache.any((g) {
      String t = g['type'].toString().toLowerCase();
      String n = g['name'].toString().toLowerCase();
      String c = (g['color'] ?? '').toString().toLowerCase();

      bool matchesFinish = finishKws.any(
        (kw) => t.contains(kw) || n.contains(kw),
      );
      bool matchesColor = colorKws.any((kw) {
        if (kw.isEmpty) {
          return c.isEmpty ||
              c.contains('clair') ||
              c.contains('transparent') ||
              n.contains('clair') ||
              n.contains('transparent');
        }
        return c == kw || c.contains(kw) || n.contains(kw);
      });
      return matchesFinish && matchesColor;
    });
  }

  double getPriceForFinish(
    GlassFinish finish,
    GlassColor color, {
    double? chosenThickness,
  }) {
    List<String> finishKws = getFinishKeywords(finish);
    List<String> colorKws = getColorKeywords(color);

    // 1. Try matching both finish, color, and thickness if specified
    final exactMatch = allGlassCache.firstWhere((g) {
      String t = g['type'].toString().toLowerCase();
      String n = g['name'].toString().toLowerCase();
      String c = (g['color'] ?? '').toString().toLowerCase();
      double thick = (g['thickness'] as num?)?.toDouble() ?? 0.0;

      bool matchesFinish = finishKws.any(
        (kw) => t.contains(kw) || n.contains(kw),
      );
      bool matchesColor = colorKws.any((kw) {
        if (kw.isEmpty) {
          return c.isEmpty ||
              c.contains('clair') ||
              c.contains('transparent') ||
              n.contains('clair') ||
              n.contains('transparent');
        }
        return c == kw || c.contains(kw) || n.contains(kw);
      });
      bool matchesThickness =
          chosenThickness == null || thick == chosenThickness;
      return matchesFinish && matchesColor && matchesThickness;
    }, orElse: () => <String, dynamic>{});

    if (exactMatch.isNotEmpty) {
      return (exactMatch['price_per_sqm'] ?? 0.0).toDouble();
    }

    // 2. Try matching finish only
    final match = allGlassCache.firstWhere((g) {
      String t = g['type'].toString().toLowerCase();
      String n = g['name'].toString().toLowerCase();
      return finishKws.any((kw) => t.contains(kw) || n.contains(kw));
    }, orElse: () => <String, dynamic>{});

    if (match.isNotEmpty) {
      return (match['price_per_sqm'] ?? 0.0).toDouble();
    }

    // 3. Fallback for clair
    if (finish == GlassFinish.clair) {
      final clairMatch = allGlassCache.firstWhere((g) {
        String t = g['type'].toString().toLowerCase();
        return t == 'simple' || t == 'clair' || t == 'glass';
      }, orElse: () => <String, dynamic>{});
      if (clairMatch.isNotEmpty) {
        return (clairMatch['price_per_sqm'] ?? 0.0).toDouble();
      }
    }
    return 0.0;
  }

  List<double> getAvailableThicknesses(GlassFinish finish, GlassColor color) {
    List<String> finishKws = getFinishKeywords(finish);
    List<String> colorKws = getColorKeywords(color);

    var matches = allGlassCache.where((g) {
      String t = g['type'].toString().toLowerCase();
      String n = g['name'].toString().toLowerCase();
      String c = (g['color'] ?? '').toString().toLowerCase();

      bool matchesFinish = finishKws.any(
        (kw) => t.contains(kw) || n.contains(kw),
      );
      bool matchesColor = colorKws.any((kw) {
        if (kw.isEmpty) {
          return c.isEmpty ||
              c.contains('clair') ||
              c.contains('transparent') ||
              n.contains('clair') ||
              n.contains('transparent');
        }
        return c == kw || c.contains(kw) || n.contains(kw);
      });
      return matchesFinish && matchesColor;
    }).toList();

    if (matches.isEmpty) {
      matches = allGlassCache.where((g) {
        String t = g['type'].toString().toLowerCase();
        String n = g['name'].toString().toLowerCase();
        return finishKws.any((kw) => t.contains(kw) || n.contains(kw));
      }).toList();
    }

    final thicknesses = matches
        .map((g) => (g['thickness'] as num?)?.toDouble() ?? 0.0)
        .where((t) => t > 0.0)
        .toSet()
        .toList();
    thicknesses.sort();
    return thicknesses;
  }

  double getThicknessForFinish(GlassFinish finish, GlassColor color) {
    List<String> finishKws = getFinishKeywords(finish);
    List<String> colorKws = getColorKeywords(color);

    // 1. Try matching both finish and color
    final exactMatch = allGlassCache.firstWhere((g) {
      String t = g['type'].toString().toLowerCase();
      String n = g['name'].toString().toLowerCase();
      String c = (g['color'] ?? '').toString().toLowerCase();

      bool matchesFinish = finishKws.any(
        (kw) => t.contains(kw) || n.contains(kw),
      );
      bool matchesColor = colorKws.any((kw) {
        if (kw.isEmpty) {
          return c.isEmpty ||
              c.contains('clair') ||
              c.contains('transparent') ||
              n.contains('clair') ||
              n.contains('transparent');
        }
        return c == kw || c.contains(kw) || n.contains(kw);
      });
      return matchesFinish && matchesColor;
    }, orElse: () => <String, dynamic>{});

    if (exactMatch.isNotEmpty) {
      return (exactMatch['thickness'] ?? 4.0).toDouble();
    }

    // 2. Try matching finish only
    final match = allGlassCache.firstWhere((g) {
      String t = g['type'].toString().toLowerCase();
      String n = g['name'].toString().toLowerCase();
      return finishKws.any((kw) => t.contains(kw) || n.contains(kw));
    }, orElse: () => <String, dynamic>{});

    if (match.isNotEmpty) {
      return (match['thickness'] ?? 4.0).toDouble();
    }

    // 3. Fallback for clair
    if (finish == GlassFinish.clair) {
      final clairMatch = allGlassCache.firstWhere((g) {
        String t = g['type'].toString().toLowerCase();
        return t == 'simple' || t == 'clair' || t == 'glass';
      }, orElse: () => <String, dynamic>{});
      if (clairMatch.isNotEmpty) {
        return (clairMatch['thickness'] ?? 4.0).toDouble();
      }
    }

    return 4.0;
  }

  double getPriceForIntercall(int thickness) {
    if (availableIntercalls.isEmpty) return 0.0;
    try {
      final interMatch = availableIntercalls.firstWhere((item) {
        final rawThickness = item['thickness'];
        final itemThickness = rawThickness is num
            ? rawThickness.toInt()
            : int.tryParse(rawThickness?.toString() ?? '');
        return itemThickness == thickness ||
            item['name'].toString().contains(thickness.toString());
      });
      final price = interMatch['price_per_sqm'] ?? interMatch['price'] ?? 0.0;
      return price is num ? price.toDouble() : double.tryParse('$price') ?? 0.0;
    } catch (_) {
      return 0.0; // No match found
    }
  }

  double getPriceForGas(int thickness) {
    if (availableGases.isEmpty) return 0.0;
    try {
      final gasMatch = availableGases.firstWhere(
        (g) =>
            g['thickness'] == thickness ||
            g['name'].toString().contains(thickness.toString()),
      );
      return (gasMatch['price_per_sqm'] ?? 0.0).toDouble();
    } catch (_) {
      return 0.0; // No match found
    }
  }

  double calculateTotalGlassPricePerSqm() {
    GlassSpecification glass = zones.isNotEmpty
        ? zones.first.glass
        : GlassSpecification();
    return calculateTotalGlassPricePerSqmForZoneGlass(glass);
  }

  double calculateTotalGlassPricePerSqmForZone(WindowZone zone) {
    return calculateTotalGlassPricePerSqmForZoneGlass(zone.glass);
  }

  double getLaminatedPrice(double thickness, String laminatedColor) {
    if (allGlassCache.isEmpty) return 0.0;
    // Search for a laminated glass product matching the thickness and color
    final match = allGlassCache.firstWhere((g) {
      final t = g['type'].toString().toLowerCase();
      final n = g['name'].toString().toLowerCase();
      final c = (g['color'] ?? '').toString().toLowerCase();
      final double thick = (g['thickness'] as num?)?.toDouble() ?? 0.0;

      final isLaminatedProduct =
          t.contains('مورق') ||
          t.contains('laminated') ||
          t.contains('strat') ||
          n.contains('مورق') ||
          n.contains('laminated') ||
          n.contains('strat');
      if (!isLaminatedProduct) return false;

      if (thick != thickness) return false;

      // Color mapping: transparent/clair, white/opale/opaque/milky, blue
      bool matchesColor = false;
      if (laminatedColor == 'transparent') {
        matchesColor =
            c.isEmpty ||
            c.contains('clair') ||
            c.contains('transparent') ||
            n.contains('clair') ||
            n.contains('transparent');
      } else if (laminatedColor == 'white') {
        matchesColor =
            c.contains('blanc') ||
            c.contains('أبيض') ||
            c.contains('opale') ||
            c.contains('opaque') ||
            n.contains('blanc') ||
            n.contains('أبيض');
      } else if (laminatedColor == 'blue') {
        matchesColor =
            c.contains('bleu') ||
            c.contains('أزرق') ||
            n.contains('bleu') ||
            n.contains('أزرق');
      }

      return matchesColor;
    }, orElse: () => <String, dynamic>{});

    if (match.isNotEmpty) {
      return (match['price_per_sqm'] ?? 0.0).toDouble();
    }
    // Fallback: search by thickness only
    final thickMatch = allGlassCache.firstWhere((g) {
      final t = g['type'].toString().toLowerCase();
      final n = g['name'].toString().toLowerCase();
      final double thick = (g['thickness'] as num?)?.toDouble() ?? 0.0;
      final isLaminatedProduct =
          t.contains('مورق') ||
          t.contains('laminated') ||
          t.contains('strat') ||
          n.contains('مورق') ||
          n.contains('laminated') ||
          n.contains('strat');
      return isLaminatedProduct && thick == thickness;
    }, orElse: () => <String, dynamic>{});

    if (thickMatch.isNotEmpty) {
      return (thickMatch['price_per_sqm'] ?? 0.0).toDouble();
    }
    return 0.0;
  }

  double getTemperingPricePerSqm(double thickness) {
    // Tempering is managed in the Glass catalogue as its own service, one
    // price per glass thickness (for example: Trempé 4 mm, Trempé 6 mm).
    // This makes the price available to every drawing without requiring an
    // unrelated component override.
    double? readPrice(Map<String, dynamic> item) {
      final raw =
          item['price_per_sqm'] ??
          item['pricePerSqm'] ??
          item['calculated_price'] ??
          item['price'] ??
          item['prix'];
      return raw is num
          ? raw.toDouble()
          : double.tryParse(
              raw?.toString().trim().replaceAll(' ', '').replaceAll(',', '.') ??
                  '',
            );
    }

    bool isTemperingItem(Map<String, dynamic> item) {
      final type = item['type']?.toString().toLowerCase() ?? '';
      final name = item['name']?.toString().toLowerCase() ?? '';
      return type == 'tempering' ||
          type.contains('tremp') ||
          type.contains('tempering') ||
          name.contains('trempé') ||
          name.contains('trempe') ||
          name.contains('تقسية');
    }

    double itemThickness(Map<String, dynamic> item) {
      final raw = item['thickness'];
      if (raw is num) return raw.toDouble();
      final text = raw?.toString().trim() ?? '';
      final direct = double.tryParse(text.replaceAll(',', '.'));
      if (direct != null) return direct;
      final number = RegExp(r'\d+(?:[.,]\d+)?').firstMatch(text)?.group(0);
      return double.tryParse(number?.replaceAll(',', '.') ?? '') ?? 0.0;
    }

    final matchingItems = allGlassCache.where(
      (item) =>
          isTemperingItem(item) &&
          (itemThickness(item) - thickness).abs() < 0.01,
    );
    // Old synchronisations can leave an earlier zero-priced duplicate beside
    // the priced catalogue item. Prefer the first actual price, rather than
    // returning the first matching row blindly.
    double? fallbackPrice;
    for (final item in matchingItems) {
      final price = readPrice(item);
      if (price == null) continue;
      fallbackPrice ??= price;
      if (price != 0) return price;
    }
    if (fallbackPrice != null) return fallbackPrice;

    // Compatibility with any older catalogues that stored the service as a
    // component override rather than a Glass catalogue item.
    final thickStr = thickness.toStringAsFixed(0);
    for (var entry in componentOverrides.entries) {
      final name = entry.key.toLowerCase();
      final isTempering =
          name.contains('تقسية') ||
          name.contains('tempering') ||
          name.contains('trempe');
      if (isTempering && name.contains(thickStr)) {
        final val = entry.value;
        if (val is Map) {
          return readPrice(Map<String, dynamic>.from(val)) ?? 0.0;
        }
      }
    }
    return 0.0;
  }

  double calculateTotalGlassPricePerSqmForZoneGlass(GlassSpecification glass) {
    double price = 0.0;
    if (glass.structure == GlassStructure.simple) {
      final thick = glass.thicknessOuter ?? 4.0;
      if (glass.processingOuter == GlassProcessing.laminated) {
        price = getLaminatedPrice(thick, glass.laminatedColorOuter);
      } else {
        price = getPriceForFinish(
          glass.finishOuter,
          glass.colorOuter,
          chosenThickness: thick,
        );
      }

      // Add tempering price if enabled
      if (glass.processingOuter == GlassProcessing.tempered ||
          glass.temperedOuter) {
        price += getTemperingPricePerSqm(thick);
      }
    } else if (glass.structure == GlassStructure.double) {
      final thickInner = glass.thicknessInner ?? 4.0;
      final thickOuter = glass.thicknessOuter ?? 4.0;

      double innerPrice = 0.0;
      if (glass.processingInner == GlassProcessing.laminated) {
        innerPrice = getLaminatedPrice(thickInner, glass.laminatedColorInner);
      } else {
        innerPrice = getPriceForFinish(
          glass.finishInner,
          glass.colorInner,
          chosenThickness: thickInner,
        );
      }
      if (glass.processingInner == GlassProcessing.tempered ||
          glass.temperedInner) {
        innerPrice += getTemperingPricePerSqm(thickInner);
      }

      double outerPrice = 0.0;
      if (glass.processingOuter == GlassProcessing.laminated) {
        outerPrice = getLaminatedPrice(thickOuter, glass.laminatedColorOuter);
      } else {
        outerPrice = getPriceForFinish(
          glass.finishOuter,
          glass.colorOuter,
          chosenThickness: thickOuter,
        );
      }
      if (glass.processingOuter == GlassProcessing.tempered ||
          glass.temperedOuter) {
        outerPrice += getTemperingPricePerSqm(thickOuter);
      }

      double intercallPrice = getPriceForIntercall(glass.intercallThickness);

      double gasPrice = 0.0;
      if (glass.hasGas) {
        gasPrice = getPriceForGas(glass.intercallThickness);
      }

      price = innerPrice + outerPrice + intercallPrice + gasPrice;
    } else if (glass.structure == GlassStructure.closed) {
      final sub = glass.panneauSubtype ?? '';
      final col = glass.panneauColor ?? '';

      final match = allGlassCache.firstWhere((g) {
        final t = g['type'].toString().toLowerCase();
        final s = (g['subtype'] ?? '').toString().toLowerCase();
        final c = (g['color'] ?? '').toString().toLowerCase();
        final sameSelectedProduct =
            glass.panneauProductId != null &&
            g['id']?.toString() == glass.panneauProductId.toString() &&
            s == sub.toLowerCase();

        return t == 'panneau' &&
            (sameSelectedProduct || s == sub.toLowerCase()) &&
            c == col.toLowerCase();
      }, orElse: () => <String, dynamic>{});

      if (match.isNotEmpty) {
        price = (match['price_per_sqm'] ?? 0.0).toDouble();
      } else {
        final baseMatch = allGlassCache.firstWhere((g) {
          final t = g['type'].toString().toLowerCase();
          final s = (g['subtype'] ?? '').toString().toLowerCase();
          final sameSelectedProduct =
              glass.panneauProductId != null &&
              g['id']?.toString() == glass.panneauProductId.toString() &&
              s == sub.toLowerCase();
          return t == 'panneau' &&
              (sameSelectedProduct || s == sub.toLowerCase());
        }, orElse: () => <String, dynamic>{});
        if (baseMatch.isNotEmpty) {
          price = (baseMatch['price_per_sqm'] ?? 0.0).toDouble();
        }
      }
    }
    return price;
  }

  Map<String, dynamic>? getPanneauProductForSpec(GlassSpecification glass) {
    final selectedId = glass.panneauProductId;
    final selectedColor = (glass.panneauColor ?? '').trim().toLowerCase();
    final subtype = (glass.panneauSubtype ?? '').trim().toLowerCase();
    if (selectedId != null) {
      Map<String, dynamic>? idFallback;
      for (final product in allGlassCache) {
        if (product['type'].toString().toLowerCase() != 'panneau' ||
            product['id']?.toString() != selectedId.toString() ||
            (product['subtype'] ?? '').toString().trim().toLowerCase() !=
                subtype) {
          continue;
        }
        idFallback ??= product;
        final color = (product['color'] ?? '').toString().trim().toLowerCase();
        if (selectedColor.isEmpty || color == selectedColor) return product;
      }
      if (idFallback != null) return idFallback;
    }

    Map<String, dynamic>? subtypeFallback;
    for (final product in allGlassCache) {
      if (product['type'].toString().toLowerCase() != 'panneau' ||
          (product['subtype'] ?? '').toString().trim().toLowerCase() !=
              subtype) {
        continue;
      }
      subtypeFallback ??= product;
      final color = (product['color'] ?? '').toString().trim().toLowerCase();
      if (selectedColor.isEmpty || color == selectedColor) return product;
    }
    return subtypeFallback;
  }

  Future<void> loadCatalogData([String systemMode = '']) async {
    try {
      if (systemMode.isNotEmpty) {
        this.systemMode = systemMode;
      }
      await loadGlassProducts();

      // Load KitBundles is_selling_calculated settings
      // Only set if not already loaded from saved data (to preserve user overrides)
      try {
        final kitBundles = await db.readKitBundles();
        for (var kb in kitBundles) {
          final kbName = kb['name']?.toString() ?? '';
          if (kbName.isNotEmpty) {
            if (componentOverrides.containsKey(kbName)) {
              // Preserve existing saved data, only update is_selling_calculated
              final existing = componentOverrides[kbName];
              if (existing is Map<String, dynamic>) {
                existing['is_selling_calculated'] =
                    kb['is_selling_calculated'] ?? 1;
              }
            } else {
              componentOverrides[kbName] = {
                'id': kb['id'],
                'name': kb['name'],
                'is_selling_calculated': kb['is_selling_calculated'] ?? 1,
              };
            }
          }
        }
      } catch (_) {}

      final profilesData = await db.readProfile();
      availableColors = [];
      availableAccessoryColors = await db.readAccessoryColors();
      availableSystems.clear();
      bool foundValidSeries = false;

      for (var pData in profilesData) {
        var system = AluminumProfileSystem.fromMap(pData);
        final seriesData = await db.readSeriesByProfile(system.id);

        for (var sData in seriesData) {
          var series = AluminumSeries.fromMap(sData);
          final sectionsData = await db.readSectionsBySeries(series.id);
          series.sections = sectionsData
              .map((e) => AluminumSection.fromMap(e))
              .toList();

          bool isLoadedSeries = false;
          final Set<String> matchQueries = {};
          if (loadedSeriesName != null && loadedSeriesName!.isNotEmpty) {
            matchQueries.add(loadedSeriesName!.toLowerCase().trim());
          }
          if (loadedSlidingSeriesName != null &&
              loadedSlidingSeriesName!.isNotEmpty) {
            matchQueries.add(loadedSlidingSeriesName!.toLowerCase().trim());
          }
          if (activeSeries != null) {
            matchQueries.add(activeSeries!.name.toLowerCase().trim());
          }
          if (activeSlidingSeries != null) {
            matchQueries.add(activeSlidingSeries!.name.toLowerCase().trim());
          }

          final sName = series.name.toLowerCase().trim();
          final sType = series.type.toLowerCase().trim();
          for (final query in matchQueries) {
            if (sName == query ||
                sType == query ||
                sName.contains(query) ||
                query.contains(sName)) {
              isLoadedSeries = true;
              break;
            }
          }

          if (!isLoadedSeries) {
            if (loadedSeriesId != null && series.id == loadedSeriesId) {
              isLoadedSeries = true;
            } else if (loadedSlidingSeriesId != null &&
                series.id == loadedSlidingSeriesId) {
              isLoadedSeries = true;
            } else if (activeSeries != null && series.id == activeSeries!.id) {
              isLoadedSeries = true;
            } else if (activeSlidingSeries != null &&
                series.id == activeSlidingSeries!.id) {
              isLoadedSeries = true;
            }
          }

          String searchString =
              '${system.type} ${system.name} ${series.type} ${series.name}'
                  .toLowerCase();
          bool isMatchingMode = true;
          if (isLoadedSeries) {
            isMatchingMode = true;
          } else if (systemMode == 'french') {
            isMatchingMode =
                searchString.contains('frappe') ||
                searchString.contains('battant') ||
                searchString.contains('فتح') ||
                searchString.contains('فرنسي') ||
                (searchString.contains('pvc') &&
                    !searchString.contains('coulissant') &&
                    !searchString.contains('sliding') &&
                    !searchString.contains('منزلق') &&
                    !searchString.contains('كوليس'));
          } else if (systemMode == 'sliding') {
            isMatchingMode =
                searchString.contains('coulissant') ||
                searchString.contains('sliding') ||
                searchString.contains('منزلق') ||
                searchString.contains('كوليس');
          } else if (systemMode == 'mixed') {
            isMatchingMode = true;
          }

          // Classify by the series type, never by the profile's commercial
          // name. This preserves the strict separation between opening and
          // sliding series while applying it to every active profile.
          isMatchingMode = seriesMatchesDrawingMode(series, system, systemMode);
          if (isMatchingMode) system.series.add(series);
        }
        if (system.series.isNotEmpty) availableSystems.add(system);
      }

      if (availableSystems.isNotEmpty) {
        AluminumSeries? resolvedActive;
        String? activeNameToResolve = loadedSeriesName;
        if (activeNameToResolve == null || activeNameToResolve.isEmpty) {
          activeNameToResolve = activeSeries?.name;
        }

        // Priority 0: Direct DB match by loadedSeriesId — most reliable,
        // bypasses all mode/name filtering. Guarantees saved series is restored.
        if (loadedSeriesId != null) {
          // First check availableSystems (already loaded)
          for (var sys in availableSystems) {
            for (var s in sys.series) {
              if (s.id == loadedSeriesId) {
                resolvedActive = s;
                break;
              }
            }
            if (resolvedActive != null) break;
          }
          // If not found in filtered list, search ALL profiles/series in DB
          if (resolvedActive == null) {
            final allProfilesData0 = await db.readProfile();
            outer0:
            for (var pData in allProfilesData0) {
              final seriesData = await db.readSeriesByProfile(pData['id']);
              for (var sData in seriesData) {
                final s = AluminumSeries.fromMap(sData);
                if (s.id == loadedSeriesId) {
                  final sectionsData = await db.readSectionsBySeries(s.id);
                  s.sections = sectionsData
                      .map((e) => AluminumSection.fromMap(e))
                      .toList();
                  resolvedActive = s;
                  // Inject into availableSystems so downstream logic works
                  if (availableSystems.isNotEmpty) {
                    final alreadyIn = availableSystems.any(
                      (sys) => sys.series.any((sr) => sr.id == s.id),
                    );
                    if (!alreadyIn) availableSystems.first.series.add(s);
                  }
                  break outer0;
                }
              }
            }
          }
        }

        // Priority 1: Match by activeSeries ID (in-memory user choice)
        if (resolvedActive == null && activeSeries != null) {
          for (var sys in availableSystems) {
            for (var s in sys.series) {
              if (s.id == activeSeries!.id) {
                resolvedActive = s;
                break;
              }
            }
            if (resolvedActive != null) break;
          }
          if (resolvedActive == null) {
            // Search globally if not in filtered list
            final allProfilesDataP1 = await db.readProfile();
            outerP1:
            for (var pData in allProfilesDataP1) {
              final seriesData = await db.readSeriesByProfile(pData['id']);
              for (var sData in seriesData) {
                final s = AluminumSeries.fromMap(sData);
                if (s.id == activeSeries!.id) {
                  final sectionsData = await db.readSectionsBySeries(s.id);
                  s.sections = sectionsData
                      .map((e) => AluminumSection.fromMap(e))
                      .toList();
                  resolvedActive = s;
                  final alreadyIn = availableSystems.any(
                    (sys) => sys.series.any((sr) => sr.id == s.id),
                  );
                  if (!alreadyIn && availableSystems.isNotEmpty) {
                    availableSystems.first.series.add(s);
                  }
                  break outerP1;
                }
              }
            }
          }
        }

        if (resolvedActive == null &&
            activeNameToResolve != null &&
            activeNameToResolve.isNotEmpty) {
          final query = activeNameToResolve.toLowerCase().trim();
          for (var sys in availableSystems) {
            for (var s in sys.series) {
              final sName = s.name.toLowerCase().trim();
              final sType = s.type.toLowerCase().trim();
              if (sName == query ||
                  sType == query ||
                  sName.contains(query) ||
                  query.contains(sName)) {
                resolvedActive = s;
                break;
              }
            }
            if (resolvedActive != null) break;
          }
        }

        if (resolvedActive != null) {
          await setActiveSeries(resolvedActive);
          foundValidSeries = true;
        } else {
          AluminumSeries? firstFrench;
          for (var sys in availableSystems) {
            for (var s in sys.series) {
              final searchString = '${sys.type} ${sys.name} ${s.type} ${s.name}'
                  .toLowerCase();
              if (searchString.contains('frappe') ||
                  searchString.contains('battant') ||
                  searchString.contains('فتح') ||
                  searchString.contains('فرنسي')) {
                firstFrench = s;
                break;
              }
            }
            if (firstFrench != null) break;
          }
          if (firstFrench != null) {
            await setActiveSeries(firstFrench);
          } else if (availableSystems.isNotEmpty &&
              availableSystems.first.series.isNotEmpty) {
            await setActiveSeries(availableSystems.first.series.first);
          }
          foundValidSeries = true;
        }

        AluminumSeries? resolvedSliding;
        String? slidingNameToResolve = loadedSlidingSeriesName;
        if (slidingNameToResolve == null || slidingNameToResolve.isEmpty) {
          slidingNameToResolve = activeSlidingSeries?.name;
        }

        if (activeSlidingSeries != null) {
          for (var sys in availableSystems) {
            for (var s in sys.series) {
              if (s.id == activeSlidingSeries!.id) {
                resolvedSliding = s;
                break;
              }
            }
            if (resolvedSliding != null) break;
          }
        }

        if (resolvedSliding == null && loadedSlidingSeriesId != null) {
          for (var sys in availableSystems) {
            for (var s in sys.series) {
              if (s.id == loadedSlidingSeriesId) {
                resolvedSliding = s;
                break;
              }
            }
            if (resolvedSliding != null) break;
          }
        }

        if (resolvedSliding == null &&
            slidingNameToResolve != null &&
            slidingNameToResolve.isNotEmpty) {
          final query = slidingNameToResolve.toLowerCase().trim();
          for (var sys in availableSystems) {
            for (var s in sys.series) {
              final sName = s.name.toLowerCase().trim();
              final sType = s.type.toLowerCase().trim();
              if (sName == query ||
                  sType == query ||
                  sName.contains(query) ||
                  query.contains(sName)) {
                resolvedSliding = s;
                break;
              }
            }
            if (resolvedSliding != null) break;
          }
        }

        if (resolvedSliding != null) {
          await setActiveSlidingSeries(resolvedSliding);
          if (systemMode == 'sliding') {
            await setActiveSeries(resolvedSliding);
          }
        } else {
          AluminumSeries? firstSliding;
          for (var sys in availableSystems) {
            for (var s in sys.series) {
              final searchString = '${sys.type} ${sys.name} ${s.type} ${s.name}'
                  .toLowerCase();
              if (searchString.contains('coulissant') ||
                  searchString.contains('sliding') ||
                  searchString.contains('منزلق') ||
                  searchString.contains('كوليس')) {
                firstSliding = s;
                break;
              }
            }
            if (firstSliding != null) break;
          }
          if (firstSliding != null) {
            await setActiveSlidingSeries(firstSliding);
            if (systemMode == 'sliding') {
              await setActiveSeries(firstSliding);
            }
          } else if (availableSystems.isNotEmpty &&
              availableSystems.first.series.isNotEmpty) {
            await setActiveSlidingSeries(availableSystems.first.series.first);
            if (systemMode == 'sliding') {
              await setActiveSeries(availableSystems.first.series.first);
            }
          }
        }

        if (systemMode == 'mixed') {
          if (resolvedSliding != null) {
            await setActiveSlidingSeries(resolvedSliding);
          } else {
            AluminumSeries? firstSliding;
            final activeSystemId = activeSeries?.profileId;
            if (activeSystemId != null) {
              final activeSystem = availableSystems.firstWhere(
                (s) => s.id == activeSystemId,
                orElse: () => availableSystems.first,
              );
              for (var ser in activeSystem.series) {
                final name = ser.name.toLowerCase();
                final type = ser.type.toLowerCase();
                if (name.contains('couliss') ||
                    name.contains('sliding') ||
                    name.contains('منزلق') ||
                    type.contains('couliss') ||
                    type.contains('sliding') ||
                    type.contains('منزلق')) {
                  firstSliding = ser;
                  break;
                }
              }
            }
            if (firstSliding == null) {
              for (var sys in availableSystems) {
                for (var ser in sys.series) {
                  final name = ser.name.toLowerCase();
                  if (name.contains('couliss') ||
                      name.contains('sliding') ||
                      name.contains('منزلق')) {
                    firstSliding = ser;
                    break;
                  }
                }
                if (firstSliding != null) break;
              }
            }
            await setActiveSlidingSeries(
              firstSliding ?? availableSystems.first.series.first,
            );
          }
        }
      }
      if (!foundValidSeries && activeSeries != null) {
        foundValidSeries = true;
      }
      if (!foundValidSeries) {
        activeSeries = null;
        availableColors = [];
        _selectedDbColor = null;
        for (final zone in zones) {
          zone.selectedDbColor = null;
        }
      }
      notifyListeners();
    } catch (e) {
      debugPrint("Error loading catalog data: $e");
    }
  }

  double _calculateSashThickness(bool is105) {
    // إذا كان هناك ضلفة مخصصة مختارة، نستخدم العرض الظاهر لها
    if (sashOverride != null) {
      double t = (sashOverride!['visible_width'] as num?)?.toDouble() ?? 0.0;
      if (t > 0) return t;
    }

    if (activeSeries == null || activeSeries!.sections.isEmpty) {
      return is105 ? 70.0 : 50.0;
    }

    // محاولة إيجاد الضلفة الافتراضية
    String targetCode = is105 ? '105' : '104';
    try {
      final sashSection = activeSeries!.sections.firstWhere(
        (s) => s.type.toLowerCase() == 'sash' && s.code.contains(targetCode),
      );
      if (sashSection.visibleWidth > 0) return sashSection.visibleWidth;
      if (sashSection.thickness > 0) return sashSection.thickness;
    } catch (_) {
      // إذا لم يجد ضلفة بالكود 104/105، يبحث عن أي ضلفة أخرى في السلسلة
      try {
        final anySash = activeSeries!.sections.firstWhere(
          (s) => s.isSash || s.type.toLowerCase() == 'sash',
        );
        if (anySash.visibleWidth > 0) return anySash.visibleWidth;
      } catch (_) {}
    }
    return is105 ? 70.0 : 50.0;
  }

  /// The opening overlap belongs to the series geometry. Some catalogues keep
  /// it on the normal sash while other sash variants leave their field at
  /// zero, so never let a zero-valued first row erase the configured value.
  /// No global default is applied: an unconfigured series intentionally
  /// returns zero until its overlap is entered in the catalogue.
  double get openingSashOverlap {
    double readOverlap(dynamic value) {
      return value is num
          ? value.toDouble()
          : double.tryParse(value?.toString() ?? '') ?? 0.0;
    }

    // The sash explicitly selected in the drawing is the source of truth.
    final overrideOverlap = readOverlap(sashOverride?['sash_overlap']);
    if (overrideOverlap > 0) return overrideOverlap;

    final series = activeSeries;
    if (series != null) {
      final overrideId = sashOverride?['id']?.toString();
      final overrideCode = sashOverride?['code']?.toString().trim();
      for (final sash in series.sections) {
        final matchesSelected =
            (overrideId != null && sash.id.toString() == overrideId) ||
            (overrideCode != null &&
                overrideCode.isNotEmpty &&
                sash.code.trim() == overrideCode) ||
            (selectedSashCode.isNotEmpty && sash.code == selectedSashCode);
        if (matchesSelected && sash.sashOverlap > 0) {
          return sash.sashOverlap;
        }
      }

      final sashes =
          series.sections.where((section) {
            final type = section.type.toLowerCase();
            final name = section.name.toLowerCase();
            return section.isSash ||
                type.contains('sash') ||
                type.contains('ouvrant') ||
                name.contains('sash') ||
                name.contains('ouvrant');
          }).toList()..sort((a, b) {
            final aWidth = a.visibleWidth > 0 ? a.visibleWidth : a.thickness;
            final bWidth = b.visibleWidth > 0 ? b.visibleWidth : b.thickness;
            return aWidth.compareTo(bWidth);
          });
      for (final sash in sashes) {
        if (sash.sashOverlap > 0) return sash.sashOverlap;
      }
    }
    return 0.0;
  }

  double getSectionThickness(String type, {double fallback = 45.0}) {
    final useSliding =
        usesSlidingPrimaryProfiles && activeSlidingSeries != null;
    final series = useSliding ? activeSlidingSeries : activeSeries;
    final sash = useSliding ? slidingSashOverride : sashOverride;
    if (series == null) return fallback;
    if (type.toLowerCase() == 'sash' && sash != null) {
      double t = (sash['visible_width'] as num?)?.toDouble() ?? 0.0;
      if (t > 0) return t;
      t = (sash['thickness'] as num?)?.toDouble() ?? 0.0;
      if (t > 0 && t <= 80.0) return t;
    }
    if (!useSliding &&
        type.toLowerCase() == 'sash' &&
        selectedSashCode.isNotEmpty) {
      for (var sec in series.sections) {
        if (sec.type.toLowerCase() == 'sash' && sec.code == selectedSashCode) {
          return sec.visibleWidth;
        }
      }
    }
    for (var sec in series.sections) {
      if (sec.type.toLowerCase() == type.toLowerCase()) {
        return sec.visibleWidth;
      }
    }
    return fallback;
  }

  AluminumSection? getSectionByType(String type) {
    final useSliding =
        usesSlidingPrimaryProfiles && activeSlidingSeries != null;
    final series = useSliding ? activeSlidingSeries! : activeSeries;
    if (series == null) return null;
    final normalizedType = type.toLowerCase();

    AluminumSection? result;
    if (normalizedType == 'sash') {
      final ov = useSliding ? slidingSashOverride : sashOverride;
      if (ov != null) result = AluminumSection.fromMap(ov);
    } else if (normalizedType == 'frame') {
      final ov = useSliding ? slidingFrameOverride : frameOverride;
      if (ov != null) result = AluminumSection.fromMap(ov);
    }

    if (result == null) {
      if (normalizedType == 'sash' && selectedSashCode.isNotEmpty) {
        for (var sec in series.sections) {
          if (sec.type.toLowerCase() == 'sash' &&
              sec.code == selectedSashCode) {
            result = sec;
            break;
          }
        }
      }
      if (result == null &&
          normalizedType == 'frame' &&
          selectedFrameCode != null) {
        for (var sec in series.sections) {
          if ((sec.type.toLowerCase() == 'frame' || sec.isFrame) &&
              sec.code == selectedFrameCode) {
            result = sec;
            break;
          }
        }
      }
      if (result == null) {
        for (var sec in series.sections) {
          final sectionType = sec.type.toLowerCase();
          final sectionName = sec.name.toLowerCase();
          final isMullion =
              normalizedType == 'mullion' &&
              (sectionType == 'mullion' ||
                  sectionType.contains('traverse') ||
                  sectionType.contains('meneau') ||
                  sectionType.contains('montant') ||
                  sectionType.contains('تقسيم') ||
                  sectionName.contains('mullion') ||
                  sectionName.contains('traverse') ||
                  sectionName.contains('meneau') ||
                  sectionName.contains('montant') ||
                  sectionName.contains('تقسيم')) &&
              !sectionType.contains('sash') &&
              !sectionType.contains('ouvrant') &&
              !sectionType.contains('ضلفة');
          if (sectionType == normalizedType ||
              isMullion ||
              (normalizedType == 'frame' && sec.isFrame)) {
            result = sec;
            break;
          }
        }
      }
    }

    // Swapping logic for multi-frame (coupled windows)
    if (normalizedType == 'frame' && result != null && zones.length > 1) {
      // If the matched frame is integrated, swap it with the non-integrated frame
      // of the same profile family (same thickness first, then any non-integrated)
      bool isIntegrated =
          result.couvreJointWidth > 0 ||
          result.name.toLowerCase().contains('cadre cj') ||
          result.code.toLowerCase().contains('103');
      if (isIntegrated) {
        // Pass 1: look for a non-integrated frame with same thickness (same family/body)
        AluminumSection? sameFamily;
        for (var sec in series.sections) {
          if (sec.type.toLowerCase() == 'frame' || sec.isFrame) {
            bool secIntegrated =
                sec.couvreJointWidth > 0 ||
                sec.name.toLowerCase().contains('cadre cj') ||
                sec.code.toLowerCase().contains('103');
            if (!secIntegrated && sec.thickness == result.thickness) {
              sameFamily = sec;
              break;
            }
          }
        }
        // Pass 2: if no same-thickness match, fall back to any non-integrated frame
        if (sameFamily == null) {
          for (var sec in series.sections) {
            if (sec.type.toLowerCase() == 'frame' || sec.isFrame) {
              bool secIntegrated =
                  sec.couvreJointWidth > 0 ||
                  sec.name.toLowerCase().contains('cadre cj') ||
                  sec.code.toLowerCase().contains('103');
              if (!secIntegrated) {
                sameFamily = sec;
                break;
              }
            }
          }
        }
        if (sameFamily != null) {
          result = sameFamily;
        }
      }
    }

    return result;
  }

  /// Looks up a profile exclusively in the selected sliding series.  Do not
  /// use [getSectionByType] for a sliding zone in a mixed drawing: that method
  /// intentionally returns the primary (opening) series when both coexist.
  AluminumSection? getSlidingSectionByType(String type) {
    final series = activeSlidingSeries ?? activeSeries;
    if (series == null) return null;
    final normalizedType = type.toLowerCase();

    if (normalizedType == 'sash' && slidingSashOverride != null) {
      return AluminumSection.fromMap(slidingSashOverride!);
    }
    if (normalizedType == 'frame' && slidingFrameOverride != null) {
      return AluminumSection.fromMap(slidingFrameOverride!);
    }

    for (final section in series.sections) {
      if (section.type.toLowerCase() == normalizedType ||
          (normalizedType == 'frame' && section.isFrame)) {
        return section;
      }
    }
    return null;
  }

  /// Returns a manually selected sliding profile only when it belongs to the
  /// active sliding series.  Old orders can otherwise carry an override from
  /// a previously selected series into the quantity and cost table.
  Map<String, dynamic>? getSlidingComponentOverride(String key) {
    final candidate = componentOverrides[key];
    if (candidate is! Map) return null;
    final result = Map<String, dynamic>.from(candidate);
    final activeSeriesId = activeSlidingSeries?.id;
    final sourceSeriesId = result['series_id'];
    if (activeSeriesId != null &&
        sourceSeriesId != null &&
        sourceSeriesId.toString() != activeSeriesId.toString()) {
      return null;
    }
    return result;
  }

  double getSectionThicknessByCode(String code, {double fallback = 45.0}) {
    final series = (usesSlidingPrimaryProfiles && activeSlidingSeries != null)
        ? activeSlidingSeries!
        : activeSeries;
    if (series == null) return fallback;
    for (var sec in series.sections) {
      if (sec.code.toLowerCase() == code.toLowerCase() ||
          sec.name.toLowerCase().contains(code.toLowerCase())) {
        if (sec.visibleWidth > 0) return sec.visibleWidth;
        if (sec.thickness > 0 && sec.thickness <= 80.0) return sec.thickness;
        return fallback;
      }
    }
    return fallback;
  }

  AluminumSection? getSectionByCode(String code) {
    final series = (usesSlidingPrimaryProfiles && activeSlidingSeries != null)
        ? activeSlidingSeries!
        : activeSeries;
    if (series == null) return null;
    for (var sec in series.sections) {
      if (sec.code.toLowerCase() == code.toLowerCase() ||
          sec.name.toLowerCase().contains(code.toLowerCase())) {
        return sec;
      }
    }
    return null;
  }

  Future<void> setActiveSeries(AluminumSeries series) async {
    _saveSnapshot();
    final double previousFrameThickness = profileThickness;
    final double previousMullionThickness = mullionThickness;
    final bool affectsVisibleDivisions = !usesSlidingPrimaryProfiles;
    final bool seriesChanged =
        (activeSeries != null && activeSeries!.id != series.id) ||
        (activeSeries == null && loadedSeriesId == null) ||
        (activeSeries == null &&
            loadedSeriesId != null &&
            loadedSeriesId != series.id);
    activeSeries = series;
    seriesDesignConfig = await db.getSeriesDesignConfig(series.id);
    seriesTableConfig = await db.getSeriesTableConfig(series.id);
    final configuredRoleRows = await db.getSeriesDesignRoles(series.id);
    List<AluminumSection> configuredSectionsFor(Iterable<String> roleKeys) {
      final ids = configuredRoleRows
          .where((row) => roleKeys.contains(row['role_key']))
          .map((row) => (row['section_id'] as num?)?.toInt())
          .whereType<int>()
          .toSet();
      if (ids.isEmpty) return <AluminumSection>[];
      return series.sections
          .where((section) => ids.contains(section.id))
          .toList();
    }

    if (systemMode == 'sliding') {
      activeSlidingSeries ??= series;
      slidingSeriesTableConfig = seriesTableConfig;
    }

    if (seriesChanged) {
      if (systemMode == 'sliding') {
        activeSlidingSeries = series;
        slidingFrameOverride = null;
        slidingSashOverride = null;
      }
      frameOverride = null;
      sashOverride = null;
      selectedSideCover = null;
      sideCoverOverride = null;
      componentOverrides.remove('تقسيم الزجاج (Mullion)');
      componentOverrides.remove('باكيت الزجاج (Parclose)');
      componentOverrides.remove('الباتمو (Batmo)');
      componentOverrides.remove('بوشون باتمو (Bouchon Batmo)');
      componentOverrides.remove('حديد الإطار (Renfort Frame)');
      componentOverrides.remove('حديد الظلفة (Renfort Sash)');
      componentOverrides.remove('حديد الظلفة الخاص بالمفاصل');
      _clearAccessoryOverrides();

      // Profile identifiers from another series (for example TPR) cannot be
      // reused safely.  Let the newly selected series provide its own standard
      // mullion instead of retaining an incompatible old shape.
      if (affectsVisibleDivisions) {
        mullionProfiles.clear();
        groovedMullionCavityOnPositiveSide.clear();
        mullionSectionOverrides.clear();
      }

      // Reset plinthe state: check if new series has a plinthe section
      // If it doesn't, disable plinthe and restore hasBottomFrame
      componentOverrides.remove('بلانت (Plinthe)');
      final hasPlintheInNewSeries = series.sections.any((s) {
        final t = s.type.toLowerCase().trim();
        final n = s.name.toLowerCase().trim();
        return t.contains('plinthe') ||
            n.contains('plinthe') ||
            t.contains('بلانت') ||
            n.contains('بلانت') ||
            t.contains('plinth') ||
            n.contains('plinth');
      });
      if (!hasPlintheInNewSeries) {
        // New series has no plinthe — reset plinthe flags and restore bottom frame
        if (hasFramePlintheBottom || zones.any((z) => z.hasSashPlintheBottom)) {
          final oldPlintheHeight =
              plintheHeight; // still from old series/overrides
          hasFramePlintheBottom = false;
          hasBottomFrame = true;
          for (var z in zones) {
            z.hasSashPlintheBottom = false;
          }
          // Restore zone bottom boundaries: move them from (height - oldPlintheHeight) back to (height - profileThickness)
          for (var z in zones) {
            if ((z.boundary.bottom - (height - oldPlintheHeight)).abs() < 5.0 ||
                z.boundary.bottom > height - 5.0) {
              z.boundary = Rect.fromLTRB(
                z.boundary.left,
                z.boundary.top,
                z.boundary.right,
                height - profileThickness,
              );
            }
          }
        }
      }

      // Auto-matching sliding series for System Mixed
      if (activeSlidingSeries != null) {
        AluminumProfileSystem? currentSystem;
        for (var sys in availableSystems) {
          if (sys.series.any((s) => s.id == series.id)) {
            currentSystem = sys;
            break;
          }
        }
        if (currentSystem != null) {
          if (!currentSystem.series.any(
            (s) => s.id == activeSlidingSeries!.id,
          )) {
            AluminumSeries? newSliding;
            for (var s in currentSystem.series) {
              final name = s.name.toLowerCase();
              final type = s.type.toLowerCase();
              if (name.contains('couliss') ||
                  name.contains('sliding') ||
                  name.contains('منزلق') ||
                  type.contains('couliss') ||
                  type.contains('sliding') ||
                  type.contains('منزلق')) {
                newSliding = s;
                break;
              }
            }
            if (newSliding != null) {
              await setActiveSlidingSeries(newSliding);
            }
          }
        }
      }
    }

    // Set default frame and sash if they are null
    if (frameOverride == null) {
      var frames = configuredSectionsFor(const ['frame', 'frame_extension']);
      if (frames.isEmpty)
        frames = series.sections.where((s) {
          final t = s.type.toLowerCase().trim();
          return t.contains('frame') ||
              t.contains('cadre') ||
              t.contains('إطار') ||
              t.contains('فريم');
        }).toList();

      if (frames.isNotEmpty) {
        // Aluminium shutter windows use a separate cover. Prefer a frame
        // without an integrated couvre-joint when the catalogue provides one.
        final shutterFrames = hasShutter && !_isPvcSeries(series)
            ? frames
                  .where((frame) => !_sectionHasIntegratedSideCover(frame))
                  .toList()
            : frames;
        final candidates = shutterFrames.isNotEmpty ? shutterFrames : frames;
        final match40 = candidates.firstWhere(
          (f) => f.name.contains('40'),
          orElse: () => candidates.first,
        );
        frameOverride = match40.toMap();
      }
    }

    if (sashOverride == null) {
      var sashes = configuredSectionsFor(const ['sash', 'sash_extension']);
      if (sashes.isEmpty)
        sashes = series.sections.where((s) {
          final t = s.type.toLowerCase().trim();
          return t.contains('sash') ||
              t.contains('ouvrant') ||
              t.contains('ضلفة') ||
              t.contains('ساش');
        }).toList();

      if (sashes.isNotEmpty) {
        sashOverride = sashes.first.toMap();
      }
    }

    if (sideCoverOverride == null) {
      var sideCovers = configuredSectionsFor(const ['side_cover']);
      if (sideCovers.isEmpty)
        sideCovers = series.sections.where((s) {
          final t = s.type.toLowerCase().trim();
          final n = s.name.toLowerCase().trim();
          return t.contains('side_cover') ||
              t.contains('couvre') ||
              t.contains('cover') ||
              n.contains('couvre') ||
              n.contains('cover');
        }).toList();

      if (sideCovers.isNotEmpty) {
        sideCoverOverride = sideCovers.first.toMap();
      }
    }

    // Fetch linked renforts for the overrides
    final d = await db.db;
    final colorId = selectedDbColor?['id'] as int?;
    if (d != null) {
      // 🟢 جلب سعر الإطار (frameOverride) من قاعدة البيانات
      if (frameOverride != null) {
        final fId = frameOverride!['id'] as int?;
        if (fId != null) {
          double fPrice = await db.getSectionPrice(fId, colorId);
          if (fPrice == 800.0) fPrice = 0.0;
          frameOverride = Map<String, dynamic>.from(frameOverride!);
          frameOverride!['calculated_price'] = fPrice;
        }
      }

      // 🟢 جلب سعر الظلفة (sashOverride) من قاعدة البيانات
      if (sashOverride != null) {
        final sId = sashOverride!['id'] as int?;
        if (sId != null) {
          double sPrice = await db.getSectionPrice(sId, colorId);
          if (sPrice == 800.0) sPrice = 0.0;
          sashOverride = Map<String, dynamic>.from(sashOverride!);
          sashOverride!['calculated_price'] = sPrice;
        }
      }

      // 🟢 جلب سعر التغطية الجانبية (sideCoverOverride) من قاعدة البيانات
      if (sideCoverOverride != null) {
        final scId = sideCoverOverride!['id'] as int?;
        if (scId != null) {
          double scPrice = await db.getSectionPrice(scId, colorId);
          if (scPrice == 800.0) scPrice = 0.0;
          sideCoverOverride = Map<String, dynamic>.from(sideCoverOverride!);
          sideCoverOverride!['calculated_price'] = scPrice;
        }
      }

      if (frameOverride != null) {
        final fRes = await d.query(
          'Sections',
          where: 'id = ?',
          whereArgs: [frameOverride!['id']],
        );
        if (fRes.isNotEmpty && fRes.first['linked_renfort_id'] != null) {
          final res = await d.query(
            'Sections',
            where: 'id = ?',
            whereArgs: [fRes.first['linked_renfort_id']],
          );
          if (res.isNotEmpty) {
            final rMap = Map<String, dynamic>.from(res.first);
            final rId = rMap['id'] as int;
            final colorId = selectedDbColor?['id'] as int?;
            double price = await db.getSectionPrice(rId, colorId);
            if (price == 800.0) price = 0.0;
            rMap['calculated_price'] = price;
            componentOverrides['حديد الإطار (Renfort Frame)'] = rMap;
          }
        }
      }
      if (sashOverride != null) {
        final sRes = await d.query(
          'Sections',
          where: 'id = ?',
          whereArgs: [sashOverride!['id']],
        );
        if (sRes.isNotEmpty) {
          // 1. Get the linked normal renfort sash
          if (sRes.first['linked_renfort_id'] != null) {
            final res = await d.query(
              'Sections',
              where: 'id = ?',
              whereArgs: [sRes.first['linked_renfort_id']],
            );
            if (res.isNotEmpty) {
              final rMap = Map<String, dynamic>.from(res.first);
              final rId = rMap['id'] as int;
              double price = await db.getSectionPrice(rId, colorId);
              if (price == 800.0) price = 0.0;
              rMap['calculated_price'] = price;
              componentOverrides['حديد الظلفة (Renfort Sash)'] = rMap;
            }
          }

          // 2. Look for the hinge renfort sash (حديد الظلفة الخاص بالمفاصل) in the same series
          final mifsalRes = await d.query(
            'Sections',
            where:
                'series_id = ? AND (name LIKE ? OR type LIKE ? OR name LIKE ? OR type LIKE ? OR name LIKE ? OR type LIKE ? OR name LIKE ? OR type LIKE ? OR name LIKE ? OR type LIKE ?)',
            whereArgs: [
              series.id,
              '%مفصل%',
              '%مفصل%',
              '%مفاصل%',
              '%مفاصل%',
              '%mifsal%',
              '%mifsal%',
              '%paumelle%',
              '%paumelle%',
              '%pomelle%',
              '%pomelle%',
            ],
            limit: 1,
          );
          if (mifsalRes.isNotEmpty) {
            final rMap = Map<String, dynamic>.from(mifsalRes.first);
            final rId = rMap['id'] as int;
            final colorId = selectedDbColor?['id'] as int?;
            double price = await db.getSectionPrice(rId, colorId);
            if (price == 800.0) price = 0.0;
            rMap['calculated_price'] = price;
            componentOverrides['حديد الظلفة الخاص بالمفاصل'] = rMap;
          } else {
            if (componentOverrides.containsKey('حديد الظلفة (Renfort Sash)')) {
              componentOverrides['حديد الظلفة الخاص بالمفاصل'] =
                  componentOverrides['حديد الظلفة (Renfort Sash)'];
            }
          }
        } else {
          // Fallback if no linked renfort is set for the sash
          final seriesRenforts = await d.query(
            'Sections',
            where:
                'series_id = ? AND (type LIKE ? OR name LIKE ? OR type LIKE ? OR name LIKE ?)',
            whereArgs: [
              series.id,
              '%renfort%',
              '%renfort%',
              '%حديد%',
              '%حديد%',
            ],
            orderBy: 'id ASC',
          );
          if (seriesRenforts.length >= 4) {
            // Option 4 (index 3)
            componentOverrides['حديد الظلفة (Renfort Sash)'] =
                Map<String, dynamic>.from(seriesRenforts[3]);
          } else if (seriesRenforts.isNotEmpty) {
            componentOverrides['حديد الظلفة (Renfort Sash)'] =
                Map<String, dynamic>.from(seriesRenforts.last);
          }

          // Look for the hinge renfort sash (حديد الظلفة الخاص بالمفاصل) in the same series
          final mifsalRes = await d.query(
            'Sections',
            where:
                'series_id = ? AND (name LIKE ? OR type LIKE ? OR name LIKE ? OR type LIKE ? OR name LIKE ? OR type LIKE ? OR name LIKE ? OR type LIKE ? OR name LIKE ? OR type LIKE ?)',
            whereArgs: [
              series.id,
              '%مفصل%',
              '%مفصل%',
              '%مفاصل%',
              '%مفاصل%',
              '%mifsal%',
              '%mifsal%',
              '%paumelle%',
              '%paumelle%',
              '%pomelle%',
              '%pomelle%',
            ],
            limit: 1,
          );
          if (mifsalRes.isNotEmpty) {
            final rMap = Map<String, dynamic>.from(mifsalRes.first);
            final rId = rMap['id'] as int;
            final colorId = selectedDbColor?['id'] as int?;
            double price = await db.getSectionPrice(rId, colorId);
            if (price == 800.0) price = 0.0;
            rMap['calculated_price'] = price;
            componentOverrides['حديد الظلفة الخاص بالمفاصل'] = rMap;
          } else {
            if (componentOverrides.containsKey('حديد الظلفة (Renfort Sash)')) {
              componentOverrides['حديد الظلفة الخاص بالمفاصل'] =
                  componentOverrides['حديد الظلفة (Renfort Sash)'];
            }
          }
        }
      }

      // 🟢 تحميل تقسيم الزجاج الافتراضي (Mullion/Traverse) مع سعره
      if (!componentOverrides.containsKey('تقسيم الزجاج (Mullion)')) {
        final mullRes = await d.query(
          'Sections',
          where:
              'series_id = ? AND (LOWER(type) = ? OR LOWER(type) = ? OR LOWER(type) LIKE ? OR LOWER(name) LIKE ?)',
          whereArgs: [series.id, 'mullion', 'traverse', '%mullion%', '%تقسيم%'],
          limit: 1,
        );
        if (mullRes.isNotEmpty) {
          final rMap = Map<String, dynamic>.from(mullRes.first);
          final rId = rMap['id'] as int;
          final colorId = selectedDbColor?['id'] as int?;
          double price = await db.getSectionPrice(rId, colorId);
          if (price == 800.0) price = 0.0;
          rMap['calculated_price'] = price;
          componentOverrides['تقسيم الزجاج (Mullion)'] = rMap;

          // 🟢 تحميل حديد التقسيم الافتراضي (Renfort Mullion) مع سعره
          if (!componentOverrides.containsKey(
            'حديد التقسيم (Renfort Mullion)',
          )) {
            if (rMap['linked_renfort_id'] != null) {
              final renRes = await d.query(
                'Sections',
                where: 'id = ?',
                whereArgs: [rMap['linked_renfort_id']],
              );
              if (renRes.isNotEmpty) {
                final renMap = Map<String, dynamic>.from(renRes.first);
                final renId = renMap['id'] as int;
                double renPrice = await db.getSectionPrice(renId, colorId);
                if (renPrice == 800.0) renPrice = 0.0;
                renMap['calculated_price'] = renPrice;
                componentOverrides['حديد التقسيم (Renfort Mullion)'] = renMap;
              }
            } else {
              // Fallback search
              final renRes = await d.query(
                'Sections',
                where:
                    'series_id = ? AND (type LIKE ? OR name LIKE ?) AND (type LIKE ? OR name LIKE ? OR type LIKE ? OR name LIKE ?)',
                whereArgs: [
                  series.id,
                  '%renfort%',
                  '%حديد%',
                  '%mullion%',
                  '%mullion%',
                  '%تقسيم%',
                  '%تقسيم%',
                ],
                limit: 1,
              );
              if (renRes.isNotEmpty) {
                final renMap = Map<String, dynamic>.from(renRes.first);
                final renId = renMap['id'] as int;
                double renPrice = await db.getSectionPrice(renId, colorId);
                if (renPrice == 800.0) renPrice = 0.0;
                renMap['calculated_price'] = renPrice;
                componentOverrides['حديد التقسيم (Renfort Mullion)'] = renMap;
              }
            }
          }
        }
      }

      // 🟢 تحميل باكيت الزجاج الافتراضي (Parclose) مع سعره
      if (!componentOverrides.containsKey('باكيت الزجاج (Parclose)')) {
        final parRes = await d.query(
          'Sections',
          where:
              'series_id = ? AND (LOWER(type) = ? OR name LIKE ? OR type LIKE ? OR TRIM(code) = ?)',
          whereArgs: [series.id, 'parclose', '%باكيت%', '%parclose%', '514'],
          orderBy: "CASE WHEN TRIM(code) = '514' THEN 0 ELSE 1 END, id",
          limit: 1,
        );
        if (parRes.isNotEmpty) {
          final rMap = Map<String, dynamic>.from(parRes.first);
          final rId = rMap['id'] as int;
          final colorId = selectedDbColor?['id'] as int?;
          double price = await db.getSectionPrice(rId, colorId);
          if (price == 800.0) price = 0.0;
          rMap['calculated_price'] = price;
          componentOverrides['باكيت الزجاج (Parclose)'] = rMap;
        }
      }

      // Load default accessories
      await _loadAccessoryDefaults(d, series.id);
    }

    // Set Batmo
    if (!componentOverrides.containsKey('الباتمو (Batmo)')) {
      var batmos = series.sections.where((s) {
        final t = s.type.toLowerCase().trim();
        final n = s.name.toLowerCase().trim();
        return (t.contains('batmo') ||
                n.contains('batmo') ||
                t.contains('باتمو') ||
                n.contains('باتمو')) &&
            !(t.contains('bouchon') ||
                n.contains('bouchon') ||
                t.contains('بوشون') ||
                n.contains('بوشون'));
      }).toList();
      if (batmos.isNotEmpty) {
        final bMap = Map<String, dynamic>.from(batmos.first.toMap());
        final bId = bMap['id'] as int?;
        if (bId != null) {
          double bPrice = await db.getSectionPrice(bId, colorId);
          if (bPrice == 800.0) bPrice = 0.0;
          bMap['calculated_price'] = bPrice;
        }
        componentOverrides['الباتمو (Batmo)'] = bMap;
      } else if (d != null) {
        final res = await d.query(
          'Sections',
          where:
              'series_id = ? AND (type LIKE ? OR name LIKE ? OR type LIKE ? OR name LIKE ?)',
          whereArgs: [series.id, '%batmo%', '%batmo%', '%باتمو%', '%باتمو%'],
        );
        if (res.isNotEmpty) {
          final bMap = Map<String, dynamic>.from(res.first);
          final bId = bMap['id'] as int?;
          if (bId != null) {
            double bPrice = await db.getSectionPrice(bId, colorId);
            if (bPrice == 800.0) bPrice = 0.0;
            bMap['calculated_price'] = bPrice;
          }
          componentOverrides['الباتمو (Batmo)'] = bMap;
        }
      }
    }

    // Set Bouchon Batmo
    if (!componentOverrides.containsKey('بوشون باتمو (Bouchon Batmo)')) {
      var bouchons = series.sections.where((s) {
        final t = s.type.toLowerCase().trim();
        final n = s.name.toLowerCase().trim();
        final isBouchon =
            t.contains('bouchon') ||
            n.contains('bouchon') ||
            t.contains('بوشون') ||
            n.contains('بوشون') ||
            t.contains('bochon') ||
            n.contains('bochon');
        if (!isBouchon) return false;
        return t.contains('batmo') ||
            t.contains('battement') ||
            t.contains('meneau') ||
            t.contains('باطم') ||
            t.contains('باطو') ||
            t.contains('منو') ||
            n.contains('batmo') ||
            n.contains('battement') ||
            n.contains('meneau') ||
            n.contains('باطم') ||
            n.contains('باطو') ||
            n.contains('منو');
      }).toList();

      if (bouchons.isEmpty) {
        bouchons = series.sections.where((s) {
          final t = s.type.toLowerCase().trim();
          final n = s.name.toLowerCase().trim();
          return t.contains('bouchon') ||
              n.contains('bouchon') ||
              t.contains('بوشون') ||
              n.contains('بوشون') ||
              t.contains('bochon') ||
              n.contains('bochon');
        }).toList();
      }

      if (bouchons.isNotEmpty) {
        componentOverrides['بوشون باتمو (Bouchon Batmo)'] = bouchons.first
            .toMap();
      } else if (d != null) {
        var res = await d.query(
          'Sections',
          where:
              '(type LIKE ? OR name LIKE ? OR type LIKE ? OR name LIKE ? OR type LIKE ? OR name LIKE ?) AND '
              '(type LIKE ? OR name LIKE ? OR type LIKE ? OR name LIKE ? OR type LIKE ? OR name LIKE ? OR type LIKE ? OR name LIKE ? OR type LIKE ? OR name LIKE ? OR type LIKE ? OR name LIKE ?)',
          whereArgs: [
            '%bouchon%',
            '%bouchon%',
            '%بوشون%',
            '%بوشون%',
            '%bochon%',
            '%bochon%',
            '%batmo%',
            '%batmo%',
            '%battement%',
            '%battement%',
            '%meneau%',
            '%meneau%',
            '%باطم%',
            '%باطم%',
            '%باطو%',
            '%باطو%',
            '%منو%',
            '%منو%',
          ],
        );
        if (res.isEmpty) {
          res = await d.query(
            'Sections',
            where:
                'type LIKE ? OR name LIKE ? OR type LIKE ? OR name LIKE ? OR type LIKE ? OR name LIKE ?',
            whereArgs: [
              '%bouchon%',
              '%bouchon%',
              '%بوشون%',
              '%بوشون%',
              '%bochon%',
              '%bochon%',
            ],
          );
        }
        if (res.isNotEmpty) {
          componentOverrides['بوشون باتمو (Bouchon Batmo)'] =
              Map<String, dynamic>.from(res.first);
        }
      }
    }

    // Set Default Shutter Components
    if (d != null) {
      Future<void> assignShutterDefault(
        String overrideName,
        List<String> keywords,
      ) async {
        bool needsReassign = true;
        if (componentOverrides.containsKey(overrideName)) {
          needsReassign = false;
          if (overrideName == 'الصندوق (Caisson)' ||
              overrideName.contains('Kit') ||
              overrideName.contains('كيت')) {
            final currentComp = componentOverrides[overrideName];
            if (currentComp != null) {
              final currentSizeStr = getComponentSize(currentComp);
              if (currentSizeStr != null) {
                final cleanSize = currentSizeStr
                    .replaceAll(RegExp(r'[\s.,]'), '')
                    .trim();
                final targetDigits = shutterBoxHeight.toStringAsFixed(0);
                bool matches = cleanSize == targetDigits;
                // Check shorthand for all known sizes
                if (targetDigits == "105" &&
                    (cleanSize == "10" ||
                        cleanSize == "100" ||
                        cleanSize == "105")) {
                  matches = true;
                }
                if (targetDigits == "155" &&
                    (cleanSize == "15" ||
                        cleanSize == "150" ||
                        cleanSize == "155")) {
                  matches = true;
                }
                if (targetDigits == "185" &&
                    (cleanSize == "18" ||
                        cleanSize == "180" ||
                        cleanSize == "185")) {
                  matches = true;
                }
                if (targetDigits == "205" &&
                    (cleanSize == "20" ||
                        cleanSize == "200" ||
                        cleanSize == "205")) {
                  matches = true;
                }
                if (!matches) {
                  needsReassign = true;
                }
              } else {
                needsReassign = true;
              }
            } else {
              needsReassign = true;
            }
          }
        }

        if (needsReassign) {
          try {
            List<Map<String, dynamic>> res = [];
            if (overrideName == 'الشرائح (Lames)' && shutterLame.isNotEmpty) {
              try {
                res = await d.query(
                  'ShutterComponents',
                  where: "name = ? AND (is_active = 1 OR is_active IS NULL)",
                  whereArgs: [shutterLame],
                );
              } catch (e) {
                print('Error query exact shutterLame: $e');
              }
            }
            if (res.isEmpty) {
              String whereClause = keywords
                  .map((_) => 'name LIKE ? OR component_type LIKE ?')
                  .join(' OR ');
              List<String> args = [];
              for (var kw in keywords) {
                args.addAll(['%$kw%', '%$kw%']);
              }
              try {
                res = await d.query(
                  'ShutterComponents',
                  where:
                      "($whereClause) AND (is_active = 1 OR is_active IS NULL)",
                  whereArgs: args,
                );
              } catch (_) {}
            }
            if (overrideName == 'الشرائح (Lames)') {
              res = res.where(isShutterBladeComponent).toList();
            }
            if (res.isNotEmpty) {
              Map<String, dynamic>? bestMatch;

              if (overrideName == 'الشرائح (Lames)') {
                // Search for 43 or x
                for (var row in res) {
                  final name = row['name'].toString().toLowerCase();
                  if (name.contains('43') || name.contains('x')) {
                    if (!name.contains('final') &&
                        !name.contains('finale') &&
                        !name.contains('نهائي')) {
                      bestMatch = row;
                      break;
                    }
                  }
                }
              } else if (overrideName == 'السكك (Coulisses)') {
                // Search for 25
                for (var row in res) {
                  final name = row['name'].toString().toLowerCase();
                  if (name.contains('25')) {
                    bestMatch = row;
                    break;
                  }
                }
              } else if (overrideName == 'الشريحة النهائية (Lame Finale)' ||
                  overrideName.contains('نهائ')) {
                // Search for 45
                for (var row in res) {
                  final name = row['name'].toString().toLowerCase();
                  if (name.contains('45')) {
                    bestMatch = row;
                    break;
                  }
                }
              } else if (overrideName == 'المحور (Axe)' ||
                  overrideName.contains('محور')) {
                bestMatch = _selectCompatibleShutterAxis(res);
              } else if (overrideName == 'الصندوق (Caisson)' ||
                  overrideName.contains('Kit') ||
                  overrideName.contains('كيت')) {
                final targetSize = shutterBoxHeight; // 155.0, 185.0, 205.0
                final targetDigits = targetSize.toStringAsFixed(0);
                for (var row in res) {
                  final rowSize = getComponentSize(row);
                  if (rowSize != null) {
                    final cleanRowSize = rowSize
                        .replaceAll(RegExp(r'[\s.,]'), '')
                        .trim();
                    if (cleanRowSize == targetDigits) {
                      bestMatch = row;
                      break;
                    }
                    if (targetDigits == "105" &&
                        (cleanRowSize == "10" ||
                            cleanRowSize == "100" ||
                            cleanRowSize == "105")) {
                      bestMatch = row;
                      break;
                    }
                    if (targetDigits == "155" &&
                        (cleanRowSize == "15" ||
                            cleanRowSize == "150" ||
                            cleanRowSize == "155")) {
                      bestMatch = row;
                      break;
                    }
                    if (targetDigits == "185" &&
                        (cleanRowSize == "18" ||
                            cleanRowSize == "180" ||
                            cleanRowSize == "185")) {
                      bestMatch = row;
                      break;
                    }
                    if (targetDigits == "205" &&
                        (cleanRowSize == "20" ||
                            cleanRowSize == "200" ||
                            cleanRowSize == "205")) {
                      bestMatch = row;
                      break;
                    }
                  }
                }
              }

              final isAxis =
                  overrideName == 'المحور (Axe)' ||
                  overrideName.contains('محور');
              if (!isAxis || bestMatch != null) {
                componentOverrides[overrideName] = Map<String, dynamic>.from(
                  bestMatch ?? res.first,
                );
              }
            }
          } catch (e) {
            print('Error assigning shutter default for $overrideName: $e');
          }
        }
      }

      await assignShutterDefault('الصندوق (Caisson)', [
        'box',
        'صندوق',
        'caisson',
      ]);
      await assignShutterDefault('الشرائح (Lames)', ['blade', 'شريح', 'lame']);
      await assignShutterDefault('الشريحة النهائية (Lame Finale)', [
        'final_blade',
        'lame final',
        'نهائي',
      ]);
      await assignShutterDefault('السكك (Coulisses)', [
        'track',
        'سك',
        'coulisse',
      ]);
      await assignShutterDefault('المحور (Axe)', ['laxe', 'axe', 'محور']);

      // Kits are loaded exclusively from KitBundles by the quantity table.
      // Never create a kit override from ShutterComponents here: that could
      // turn an unrelated shutter part into a false "Kit volet moteur".
    }

    var bouchons2 = series.sections.where((s) {
      final t = s.type.toLowerCase().trim();
      return t.contains('bouchon batmo') ||
          t.contains('bouchon batment') ||
          t.contains('غطاء الباتمو');
    }).toList();
    if (bouchons2.isNotEmpty &&
        !componentOverrides.containsKey('غطاء الباتمو (Bouchon Batment)')) {
      componentOverrides['غطاء الباتمو (Bouchon Batment)'] = bouchons2.first
          .toMap();
    }

    var parcloses = series.sections.where((s) {
      final t = s.type.toLowerCase().trim();
      final n = s.name.toLowerCase().trim();
      return s.code.trim() == '514' ||
          t.contains('parclose') ||
          n.contains('parclose') ||
          t.contains('باكيت') ||
          n.contains('باكيت');
    }).toList();
    parcloses.sort((a, b) {
      final aPriority = a.code.trim() == '514' ? 0 : 1;
      final bPriority = b.code.trim() == '514' ? 0 : 1;
      return aPriority.compareTo(bPriority);
    });
    if (parcloses.isNotEmpty) {
      const key = 'باكيت الزجاج (Parclose)';
      final current = componentOverrides[key];
      final currentMax = current is Map
          ? (current['max_glass_thickness'] as num?)?.toDouble() ?? 0.0
          : 0.0;
      final preferred514 = parcloses.where((s) => s.code.trim() == '514');
      if (current == null || (preferred514.isNotEmpty && currentMax <= 10.0)) {
        componentOverrides[key] = preferred514.isNotEmpty
            ? preferred514.first.toMap()
            : parcloses.first.toMap();
      }
    }

    var mullions = series.sections.where((s) {
      final t = s.type.toLowerCase().trim();
      final n = s.name.toLowerCase().trim();
      if (t.contains('sash') || t.contains('ouvrant') || t.contains('ظلفة'))
        return false;
      if (n.contains('sash') || n.contains('ouvrant') || n.contains('ظلفة'))
        return false;
      return t.contains('mullion') ||
          t.contains('traverse') ||
          t.contains('تقسيم');
    }).toList();
    if (mullions.isNotEmpty &&
        !componentOverrides.containsKey('تقسيم الزجاج (Mullion)')) {
      componentOverrides['تقسيم الزجاج (Mullion)'] = mullions.first.toMap();
    }

    var rails = series.sections.where((s) {
      final t = s.type.toLowerCase().trim();
      return t == 'rail' ||
          t.contains('rail') ||
          t == 'الري' ||
          t.contains('الري') ||
          t == 'راي' ||
          t.contains('راي');
    }).toList();
    if (rails.isNotEmpty && !componentOverrides.containsKey('الري (Rail)')) {
      final rMap = Map<String, dynamic>.from(rails.first.toMap());
      final rId = rMap['id'] as int;
      final colorId = selectedDbColor?['id'] as int?;
      double price = await db.getSectionPrice(rId, colorId);
      if (price <= 0) {
        price = ((rMap['price_dzd'] ?? rMap['price'] ?? 0.0) as num).toDouble();
      }
      rMap['calculated_price'] = price;
      componentOverrides['الري (Rail)'] = rMap;
    }

    var chicanes = series.sections.where((s) {
      final t = s.type.toLowerCase().trim();
      final n = s.name.toLowerCase().trim();
      return t.contains('chicane') ||
          n.contains('chicane') ||
          t.contains('شيكان') ||
          n.contains('شيكان');
    }).toList();
    if (chicanes.isNotEmpty &&
        !componentOverrides.containsKey('الشيكان (Chicane)')) {
      final rMap = Map<String, dynamic>.from(chicanes.first.toMap());
      final rId = rMap['id'] as int;
      final colorId = selectedDbColor?['id'] as int?;
      double price = await db.getSectionPrice(rId, colorId);
      if (price <= 0) {
        price = ((rMap['price_dzd'] ?? rMap['price'] ?? 0.0) as num).toDouble();
      }
      rMap['calculated_price'] = price;
      componentOverrides['الشيكان (Chicane)'] = rMap;
    }

    var bardages = series.sections.where((s) {
      final t = s.type.toLowerCase().trim();
      final n = s.name.toLowerCase().trim();
      return t == 'bardage' ||
          t.contains('bardage') ||
          t.contains('بارداج') ||
          t.contains('بارداش') ||
          n.contains('bardage') ||
          n.contains('بارداج') ||
          n.contains('بارداش');
    }).toList();
    if (bardages.isNotEmpty &&
        !componentOverrides.containsKey('البارداج (Bardage)')) {
      final rMap = Map<String, dynamic>.from(bardages.first.toMap());
      final rId = rMap['id'] as int;
      final colorId = selectedDbColor?['id'] as int?;
      double price = await db.getSectionPrice(rId, colorId);
      if (price <= 0) {
        price = ((rMap['price_dzd'] ?? rMap['price'] ?? 0.0) as num).toDouble();
      }
      rMap['calculated_price'] = price;
      componentOverrides['البارداج (Bardage)'] = rMap;
    }

    updateProfileThickness();
    if (seriesChanged && affectsVisibleDivisions) {
      _synchronizeDivisionGapsForSeries(
        previousFrameThickness,
        previousMullionThickness,
      );
    }
    updateAllSashThicknesses();
    final covers = availableSideCovers;
    if (covers.isNotEmpty &&
        (selectedSideCover == null ||
            !covers.any((cover) => cover.id == selectedSideCover!.id))) {
      selectedSideCover = covers.first;
    }
    await _loadColorsForProfile(series.profileId);
    await refreshSectionPricesForSelectedColor(notify: false);
    await refreshBardageColorPrices(notify: false);
    availableAccessoryColors = await db.readAccessoryColors();

    // فلترة أي إكسسوار متبقٍ غير مربوط بهذه السلسلة حتى عند فتح طلب قديم.
    if (d != null) {
      await _filterComponentsByActiveSeries(series, d);
      // إعادة ملء ما أزيل بالاختيار الافتراضي المفلتر للسلسلة نفسها.
      await _loadAccessoryDefaults(d, series.id);
    }

    notifyListeners();
  }

  Future<void> setActiveSlidingSeries(AluminumSeries series) async {
    _saveSnapshot();
    final double previousFrameThickness = profileThickness;
    final double previousMullionThickness = mullionThickness;
    final bool affectsVisibleDivisions = usesSlidingPrimaryProfiles;
    final bool seriesChanged =
        (activeSlidingSeries != null && activeSlidingSeries!.id != series.id) ||
        (activeSlidingSeries == null && loadedSlidingSeriesId == null) ||
        (activeSlidingSeries == null &&
            loadedSlidingSeriesId != null &&
            loadedSlidingSeriesId != series.id);
    activeSlidingSeries = series;
    seriesDesignConfig = await db.getSeriesDesignConfig(series.id);
    slidingSeriesTableConfig = await db.getSeriesTableConfig(series.id);
    final configuredRoleRows = await db.getSeriesDesignRoles(series.id);
    List<AluminumSection> configuredSectionsFor(Iterable<String> roleKeys) {
      final ids = configuredRoleRows
          .where((row) => roleKeys.contains(row['role_key']))
          .map((row) => (row['section_id'] as num?)?.toInt())
          .whereType<int>()
          .toSet();
      if (ids.isEmpty) return <AluminumSection>[];
      return series.sections
          .where((section) => ids.contains(section.id))
          .toList();
    }

    if (seriesChanged) {
      slidingFrameOverride = null;
      slidingSashOverride = null;
      sideCoverOverride = null;
      selectedSideCover = null;
      hasInternalSlidingSideCover = false;
      selectedInternalSlidingSideCover = null;
      internalSlidingSideCoverOverride = null;
      _clearSlidingProfileOverrides();
      _clearAccessoryOverrides();

      if (affectsVisibleDivisions) {
        mullionProfiles.clear();
        groovedMullionCavityOnPositiveSide.clear();
        mullionSectionOverrides.clear();
      }

      // Auto-matching opening series for System Mixed
      if (activeSeries != null) {
        AluminumProfileSystem? currentSystem;
        for (var sys in availableSystems) {
          if (sys.series.any((s) => s.id == series.id)) {
            currentSystem = sys;
            break;
          }
        }
        if (currentSystem != null) {
          if (!currentSystem.series.any((s) => s.id == activeSeries!.id)) {
            AluminumSeries? newOpening;
            for (var s in currentSystem.series) {
              final name = s.name.toLowerCase();
              final type = s.type.toLowerCase();
              if (name.contains('frappe') ||
                  name.contains('battant') ||
                  name.contains('فتح') ||
                  name.contains('فرنسي') ||
                  type.contains('frappe') ||
                  type.contains('battant') ||
                  type.contains('فتح') ||
                  type.contains('فرنسي')) {
                newOpening = s;
                break;
              }
            }
            if (newOpening != null) {
              activeSeries = newOpening;
              frameOverride = null;
              sashOverride = null;
              selectedSideCover = null;

              var frames = newOpening.sections.where((s) {
                final t = s.type.toLowerCase().trim();
                return t.contains('frame') ||
                    t.contains('cadre') ||
                    t.contains('إطار') ||
                    t.contains('فريم');
              }).toList();
              if (frames.isNotEmpty) {
                final match40 = frames.firstWhere(
                  (f) => f.name.contains('40'),
                  orElse: () => frames.first,
                );
                frameOverride = match40.toMap();
              }
              var sashes = newOpening.sections.where((s) {
                final t = s.type.toLowerCase().trim();
                return t.contains('sash') ||
                    t.contains('ouvrant') ||
                    t.contains('ضلفة') ||
                    t.contains('ساش');
              }).toList();
              if (sashes.isNotEmpty) {
                sashOverride = sashes.first.toMap();
              }
              updateProfileThickness();
              updateAllSashThicknesses();
            }
          }
        }
      }
    }

    if (slidingFrameOverride == null) {
      var frames = configuredSectionsFor(const ['frame', 'frame_extension']);
      if (frames.isEmpty)
        frames = series.sections.where((s) {
          final t = s.type.toLowerCase().trim();
          return t.contains('frame') ||
              t.contains('cadre') ||
              t.contains('إطار') ||
              t.contains('فريم');
        }).toList();

      if (frames.isNotEmpty) {
        // Aluminium sliding frames should start without an integrated cover;
        // the cover is controlled as a separate profile when it is needed.
        final plainFrames = !_isPvcSeries(series)
            ? frames
                  .where((frame) => !_sectionHasIntegratedSideCover(frame))
                  .toList()
            : frames;
        final candidates = plainFrames.isNotEmpty ? plainFrames : frames;
        slidingFrameOverride = candidates.first.toMap();
      }
    }

    if (slidingSashOverride == null) {
      var sashes = configuredSectionsFor(const ['sash', 'sash_extension']);
      if (sashes.isEmpty)
        sashes = series.sections.where((s) {
          final t = s.type.toLowerCase().trim();
          return t.contains('sash') ||
              t.contains('ouvrant') ||
              t.contains('ضلفة') ||
              t.contains('ساش');
        }).toList();

      if (sashes.isNotEmpty) {
        slidingSashOverride = sashes.first.toMap();
      }
    }

    if (sideCoverOverride == null) {
      var sideCovers = configuredSectionsFor(const ['side_cover']);
      if (sideCovers.isEmpty) {
        sideCovers = series.sections.where((section) {
          final type = section.type.toLowerCase();
          final name = section.name.toLowerCase();
          return type.contains('side_cover') ||
              type.contains('couvre') ||
              type.contains('cover') ||
              name.contains('couvre') ||
              name.contains('cover');
        }).toList();
      }
      if (sideCovers.isNotEmpty) {
        sideCoverOverride = sideCovers.first.toMap();
        selectedSideCover = sideCovers.first;
      }
    }

    var rails = configuredSectionsFor(const ['rail']);
    if (rails.isEmpty)
      rails = series.sections.where((s) {
        final t = s.type.toLowerCase().trim();
        return t == 'rail' ||
            t.contains('rail') ||
            t == 'الري' ||
            t.contains('الري') ||
            t == 'راي' ||
            t.contains('راي');
      }).toList();
    if (rails.isNotEmpty && !componentOverrides.containsKey('الري (Rail)')) {
      final rMap = Map<String, dynamic>.from(rails.first.toMap());
      final rId = rMap['id'] as int;
      final colorId = selectedDbColor?['id'] as int?;
      double price = await db.getSectionPrice(rId, colorId);
      if (price <= 0) {
        price = ((rMap['price_dzd'] ?? rMap['price'] ?? 0.0) as num).toDouble();
      }
      rMap['calculated_price'] = price;
      componentOverrides['الري (Rail)'] = rMap;
    }

    var chicanes = configuredSectionsFor(const ['chicane']);
    if (chicanes.isEmpty)
      chicanes = series.sections.where((s) {
        final t = s.type.toLowerCase().trim();
        final n = s.name.toLowerCase().trim();
        return t.contains('chicane') ||
            n.contains('chicane') ||
            t.contains('شيكان') ||
            n.contains('شيكان');
      }).toList();
    if (chicanes.isNotEmpty &&
        !componentOverrides.containsKey('الشيكان (Chicane)')) {
      final rMap = Map<String, dynamic>.from(chicanes.first.toMap());
      final rId = rMap['id'] as int;
      final colorId = selectedDbColor?['id'] as int?;
      double price = await db.getSectionPrice(rId, colorId);
      if (price <= 0) {
        price = ((rMap['price_dzd'] ?? rMap['price'] ?? 0.0) as num).toDouble();
      }
      rMap['calculated_price'] = price;
      componentOverrides['الشيكان (Chicane)'] = rMap;
    }

    // Only affects a drawing made entirely of sliding zones in mixed mode.
    // A mixed drawing that still has opening zones keeps its opening frame.
    updateProfileThickness();
    if (seriesChanged && affectsVisibleDivisions) {
      _synchronizeDivisionGapsForSeries(
        previousFrameThickness,
        previousMullionThickness,
      );
    }

    await _loadColorsForProfile(series.profileId);
    await refreshSectionPricesForSelectedColor(notify: false);
    await refreshBardageColorPrices(notify: false);
    final d = await db.db;
    if (d != null) {
      await _loadAccessoryDefaults(d, series.id);
    }

    notifyListeners();
  }

  Future<void> updateShutterDefaultsIfNeeded() async {
    if (!hasShutter) return;

    final previousBoxHeight = shutterBoxHeight;
    final database = await db.db;
    Map<String, dynamic>? blade;
    final rawBlade = componentOverrides['الشرائح (Lames)'];
    if (rawBlade is Map) {
      blade = Map<String, dynamic>.from(rawBlade);
    }

    // The limits table is blade-specific. On the first shutter activation the
    // blade may not have been loaded yet, so resolve it before choosing a box.
    if (blade == null && database != null) {
      var rows = await database.query(
        'ShutterComponents',
        where: 'name = ? AND (is_active = 1 OR is_active IS NULL)',
        whereArgs: [shutterLame],
        limit: 1,
      );
      if (rows.isEmpty) {
        rows = await database.query(
          'ShutterComponents',
          where:
              "LOWER(TRIM(component_type)) IN ('blade', 'lame') AND (is_active = 1 OR is_active IS NULL)",
          limit: 1,
        );
      }
      if (rows.isNotEmpty) {
        final resolvedBlade = Map<String, dynamic>.from(rows.first);
        blade = resolvedBlade;
        componentOverrides['الشرائح (Lames)'] = resolvedBlade;
        shutterLame = resolvedBlade['name']?.toString() ?? shutterLame;
      }
    }

    // 1. Check for extruded blade auto-switch (applies to all, including tunnel boxes!)
    if (blade != null) {
      final bladeSubtype = (blade['shutter_subtype']?.toString() ?? '')
          .toLowerCase();
      final bladeName = (blade['name']?.toString() ?? '').toLowerCase();
      if (bladeSubtype == 'extruded' ||
          bladeName.contains('extruded') ||
          bladeName.contains('إكسترودي') ||
          (isPVC && !isCaissonTunnel && _isX3dShutterComponent(blade))) {
        shutterMechanism = 'محرك';
      }
    }

    if (isCaissonTunnel) {
      if (database != null) {
        await _synchronizeShutterTrackWithBlade(database);
        await _synchronizeShutterPartsWithBlade(database);
      }
      return;
    }

    shutterHeightWarning = null; // Clear previous warning

    // Local helper to extract size from component
    double? getLocalComponentSize(Map<String, dynamic>? component) {
      if (component == null) return null;
      final meas = (component['measurement'] ?? '').toString().trim();
      String? sizeStr;
      if (meas.isNotEmpty) {
        sizeStr = meas.replaceAll('.', '').replaceAll(',', '');
      } else {
        final name = component['name'].toString();
        final regExp = RegExp(r'\d+(\.\d+)?');
        final match = regExp.firstMatch(name);
        if (match != null) {
          sizeStr = match.group(0)!.replaceAll('.', '');
        }
      }
      if (sizeStr != null) {
        double sz = double.tryParse(sizeStr) ?? 0.0;
        if (sz == 15.5) sz = 155.0;
        if (sz == 18.5) sz = 185.0;
        if (sz == 20.5) sz = 205.0;
        if (sz == 15.0) sz = 150.0;
        if (sz == 18.0) sz = 180.0;
        if (sz == 20.0) sz = 200.0;
        if (sz < 100.0) sz = sz * 10.0;
        return sz;
      }
      return null;
    }

    if (database != null) {
      if (blade != null && blade['id'] != null) {
        final bladeId = blade['id'];
        try {
          final List<Map<String, dynamic>> limits = await database.query(
            'ShutterBoxLimits',
            where: 'blade_id = ?',
            whereArgs: [bladeId],
            orderBy: 'box_size ASC',
          );

          double? chosenBoxSize;
          final manualBox = componentOverrides['الصندوق (Caisson)'];
          if (manualBox != null && manualBox['id'] != -999) {
            chosenBoxSize = getLocalComponentSize(manualBox);
          }

          final resolution = resolveShutterBoxFromLimits(
            windowHeight: height,
            limits: limits,
            manuallySelectedBoxSize: chosenBoxSize,
          );
          if (resolution != null) {
            customShutterBoxHeight = resolution.boxSize;
            shutterHeightWarning = resolution.exceedsAllLimits
                ? 'لا يمكن تركيب هذا الستار: ارتفاع النافذة '
                      '${height.toStringAsFixed(0)} مم يتجاوز الحد الأقصى '
                      '${resolution.maximumSupportedHeight.toStringAsFixed(0)} مم. '
                      'تم اختيار أكبر صندوق '
                      '${resolution.boxSize.toStringAsFixed(0)} مم للكميات.'
                : null;
          } else {
            // Height-based fallback if no limits in DB
            double minFallback = 155.0;
            if (height > 1600 && height <= 2400) {
              minFallback = 185.0;
            } else if (height > 2400) {
              minFallback = 205.0;
            }

            if (chosenBoxSize != null && chosenBoxSize >= minFallback) {
              customShutterBoxHeight = chosenBoxSize;
            } else {
              customShutterBoxHeight = minFallback;
            }
            shutterHeightWarning = null;
          }
        } catch (e) {
          print('Error loading shutter box limits from database: $e');
          customShutterBoxHeight = null;
          shutterHeightWarning = null;
        }
      } else {
        customShutterBoxHeight = null;
      }
    } else {
      customShutterBoxHeight = null;
    }

    _synchronizeZonesAfterShutterBoxChange(previousBoxHeight, shutterBoxHeight);

    bool isSameSize(String? size1, String? size2) {
      if (size1 == null || size2 == null) return false;
      final s1 = size1.replaceAll(RegExp(r'[^0-9]'), '').trim();
      final s2 = size2.replaceAll(RegExp(r'[^0-9]'), '').trim();
      if (s1.length >= 2 && s2.length >= 2) {
        return s1.substring(0, 2) == s2.substring(0, 2);
      }
      return s1 == s2;
    }

    final targetSize = shutterBoxHeight; // 155.0, 185.0, 205.0
    final targetDigits = targetSize.toStringAsFixed(0);

    bool caissonMismatch = false;
    final caisson = componentOverrides['الصندوق (Caisson)'];
    if (caisson != null) {
      final sizeStr = getComponentSize(caisson);
      if (sizeStr != null) {
        final cleanSize = sizeStr.replaceAll(RegExp(r'[\s.,]'), '').trim();
        if (!isSameSize(cleanSize, targetDigits)) caissonMismatch = true;
      } else {
        caissonMismatch = true;
      }
    } else {
      caissonMismatch = true;
    }

    final isMotor = shutterMechanism == 'محرك';
    final isCrank =
        shutterMechanism == 'منايفال' ||
        shutterMechanism == 'مانيفال' ||
        shutterMechanism == 'مانيفر';
    // These overrides only remember a manual choice made from KitBundles.
    // They must never be refilled from ShutterComponents merely because the
    // caisson size changed.
    if (isMotor) {
      componentOverrides.remove('كيت (Kit)');
      componentOverrides.remove('كيت فولي مانيفر (Kit Volet Manivelle)');
      componentOverrides.remove('كيت مانيفر (Kit Manivelle)');
      componentOverrides.remove('كيت فولي (Kit Volet)');
    } else if (isCrank) {
      componentOverrides.remove('كيت (Kit)');
      componentOverrides.remove('كيت فولي موتور (Kit Volet Moteur)');
      componentOverrides.remove('كيت فولي (Kit Volet)');
    } else {
      componentOverrides.remove('كيت (Kit)');
      componentOverrides.remove('كيت فولي موتور (Kit Volet Moteur)');
      componentOverrides.remove('كيت فولي مانيفر (Kit Volet Manivelle)');
      componentOverrides.remove('كيت مانيفر (Kit Manivelle)');
    }

    final myDb = await db.db;
    if (myDb != null) {
      Future<void> assignShutterDefault(
        String overrideName,
        List<String> keywords,
      ) async {
        List<Map<String, dynamic>> res = [];
        if (overrideName == 'الشرائح (Lames)' && shutterLame.isNotEmpty) {
          try {
            res = await myDb.query(
              'ShutterComponents',
              where: "name = ? AND (is_active = 1 OR is_active IS NULL)",
              whereArgs: [shutterLame],
            );
          } catch (e) {
            print(
              'Error query exact shutterLame in updateShutterDefaultsIfNeeded: $e',
            );
          }
        }
        if (res.isEmpty) {
          String whereClause = keywords
              .map((_) => 'name LIKE ? OR component_type LIKE ?')
              .join(' OR ');
          List<String> args = [];
          for (var kw in keywords) {
            args.addAll(['%$kw%', '%$kw%']);
          }
          try {
            res = await myDb.query(
              'ShutterComponents',
              where: "($whereClause) AND (is_active = 1 OR is_active IS NULL)",
              whereArgs: args,
            );
          } catch (_) {}
        }
        try {
          if (overrideName == 'الشرائح (Lames)') {
            res = res.where(isShutterBladeComponent).toList();
          }
          if (res.isNotEmpty) {
            Map<String, dynamic>? bestMatch;

            if (overrideName == 'الشرائح (Lames)') {
              // Search for 43 or x
              for (var row in res) {
                final name = row['name'].toString().toLowerCase();
                if (name.contains('43') || name.contains('x')) {
                  if (!name.contains('final') &&
                      !name.contains('finale') &&
                      !name.contains('نهائي')) {
                    bestMatch = row;
                    break;
                  }
                }
              }
            } else if (overrideName == 'السكك (Coulisses)') {
              // Search for 25
              for (var row in res) {
                final name = row['name'].toString().toLowerCase();
                if (name.contains('25')) {
                  bestMatch = row;
                  break;
                }
              }
            } else if (overrideName == 'الشريحة النهائية (Lame Finale)' ||
                overrideName.contains('نهائ')) {
              // Search for 45
              for (var row in res) {
                final name = row['name'].toString().toLowerCase();
                if (name.contains('45')) {
                  bestMatch = row;
                  break;
                }
              }
            } else if (overrideName == 'المحور (Axe)' ||
                overrideName.contains('محور')) {
              bestMatch = _selectCompatibleShutterAxis(res);
            } else if (overrideName == 'الصندوق (Caisson)' ||
                overrideName.contains('Kit') ||
                overrideName.contains('كيت')) {
              final targetSize = shutterBoxHeight; // 155.0, 185.0, 205.0
              final targetDigits = targetSize.toStringAsFixed(0);
              for (var row in res) {
                final rowSize = getComponentSize(row);
                if (rowSize != null) {
                  final cleanRowSize = rowSize
                      .replaceAll(RegExp(r'[\s.,]'), '')
                      .trim();
                  if (cleanRowSize == targetDigits) {
                    bestMatch = row;
                    break;
                  }
                }
              }
            }

            final isAxis =
                overrideName == 'المحور (Axe)' || overrideName.contains('محور');
            if (!isAxis || bestMatch != null) {
              componentOverrides[overrideName] = Map<String, dynamic>.from(
                bestMatch ?? res.first,
              );
            }
          }
        } catch (e) {
          print('Error updating shutter default for $overrideName: $e');
        }
      }

      if (caissonMismatch) {
        await assignShutterDefault('الصندوق (Caisson)', [
          'box',
          'صندوق',
          'caisson',
        ]);
      }
      // Ensure Lames, Coulisse, Lame Finale, and Axe exist
      if (!componentOverrides.containsKey('الشرائح (Lames)')) {
        await assignShutterDefault('الشرائح (Lames)', [
          'blade',
          'شريح',
          'lame',
        ]);
      }
      if (!componentOverrides.containsKey('الشريحة النهائية (Lame Finale)')) {
        await assignShutterDefault('الشريحة النهائية (Lame Finale)', [
          'final_blade',
          'lame final',
          'نهائي',
        ]);
      }
      if (!componentOverrides.containsKey('السكك (Coulisses)')) {
        await assignShutterDefault('السكك (Coulisses)', [
          'track',
          'سك',
          'coulisse',
        ]);
      }

      await _synchronizeShutterTrackWithBlade(myDb);
      await _synchronizeShutterPartsWithBlade(myDb);

      // Keep the automatic axis in sync with the selected blade first, then
      // with the motor diameter.  The old 60/40 equality rule could select an
      // incompatible X3D axis or a tube smaller than its motor.
      final axisRows = await myDb.query(
        'ShutterComponents',
        where:
            "(LOWER(component_type) IN ('laxe', 'axe') OR LOWER(name) LIKE '%axe%' OR name LIKE '%محور%') AND (is_active = 1 OR is_active IS NULL)",
      );
      final preferredAxis = _selectCompatibleShutterAxis(axisRows);
      final currentAxe = componentOverrides['المحور (Axe)'];
      if (preferredAxis == null) {
        // Do not retain a known-incompatible axis when the catalogue has no
        // matching one for the blade/motor combination.
        componentOverrides.remove('المحور (Axe)');
      } else {
        final currentId = (currentAxe?['id'] as num?)?.toInt();
        final preferredId = (preferredAxis['id'] as num?)?.toInt();
        if (currentId != preferredId) {
          await assignShutterDefault('المحور (Axe)', ['laxe', 'axe', 'محور']);
        }
      }

      // An X3D/Extrudé blade in a regular PVC caisson has a fixed assembly
      // rule. Apply it after the caisson and ordinary kit defaults are ready
      // so the table receives the linked axis, motor and support parts in one
      // refresh.
      await _applyX3dPvcShutterRules(myDb);

      notifyListeners();
    }
  }

  WindowZone? get selectedZone {
    if (selection.type == SelectionType.zone && selection.zoneId != null) {
      try {
        return zones.firstWhere((z) => z.id == selection.zoneId);
      } catch (_) {}
    }
    return null;
  }

  /// The selected parclose defines the usable thickness of the glazing pack.
  /// If the user has not selected one explicitly, the first double-glazing
  /// parclose configured for the active frame series is the catalogue
  /// default.  This keeps the glass drawer and the material calculation on
  /// the same default profile.
  double? get selectedParcloseMaxGlassThickness {
    double? capacityOf(Map<String, dynamic> parclose) {
      final rawValue = parclose['max_glass_thickness'];
      final maximum = rawValue is num
          ? rawValue.toDouble()
          : double.tryParse(rawValue?.toString() ?? '');
      return maximum != null && maximum > 0 ? maximum : null;
    }

    final series = activeFrameSeries ?? activeSeries;
    final double doublePaneThickness = zones
        .expand((zone) => [zone.glass, ...zone.cellGlassSpec.values])
        .where((glass) => glass.structure == GlassStructure.double)
        .fold<double>(
          0.0,
          (maximum, glass) => math.max(
            maximum,
            (glass.thicknessOuter ?? 4.0) + (glass.thicknessInner ?? 4.0),
          ),
        );
    final bool needsDoubleParclose = doublePaneThickness > 0;
    final double minimumDoubleCapacity = math.max(10.0, doublePaneThickness);

    // First use a real, explicitly selected parclose only when it can hold
    // the current glazing.  A stale 5 mm single-glazing parclose must not
    // make the drawer hide the spacer after the user switches to double
    // glazing; the quantity table already resolves a double parclose in this
    // situation.
    for (final entry in componentOverrides.entries) {
      if (!entry.key.toLowerCase().contains('parclose') ||
          entry.value is! Map) {
        continue;
      }
      final selected = Map<String, dynamic>.from(entry.value as Map);
      final capacity = capacityOf(selected);
      if (capacity != null &&
          (!needsDoubleParclose || capacity > minimumDoubleCapacity)) {
        return capacity;
      }

      if (needsDoubleParclose && series != null) {
        final rawLinkedId = selected['linked_parclose_double_id'];
        final linkedId = rawLinkedId is num
            ? rawLinkedId.toInt()
            : int.tryParse(rawLinkedId?.toString() ?? '');
        if (linkedId != null) {
          for (final section in series.sections) {
            if (section.id == linkedId &&
                section.maxGlassThickness > minimumDoubleCapacity) {
              return section.maxGlassThickness;
            }
          }
        }
      }
    }

    if (series == null) return null;
    // With double glazing use the same double-parclose family used by the
    // material table.  The largest configured capacity is the safe series
    // default when no explicit link exists (e.g. 18 mm → 5 + 8 + 5).
    if (needsDoubleParclose) {
      final candidates =
          series.sections.where((section) {
            final type = section.type.toLowerCase();
            final name = section.name.toLowerCase();
            final isParclose =
                type.contains('parclose') ||
                name.contains('parclose') ||
                name.contains('باكيت');
            return isParclose &&
                section.maxGlassThickness > minimumDoubleCapacity;
          }).toList()..sort(
            (a, b) => a.maxGlassThickness.compareTo(b.maxGlassThickness),
          );
      return candidates.isEmpty ? null : candidates.last.maxGlassThickness;
    }

    // No double glazing: use the first usable double/single catalogue
    // default exactly as before.
    for (final section in series.sections) {
      final type = section.type.toLowerCase();
      final name = section.name.toLowerCase();
      final isParclose =
          type.contains('parclose') ||
          name.contains('parclose') ||
          section.name.contains('باكيت');
      if (isParclose && section.maxGlassThickness > 10.0) {
        return section.maxGlassThickness;
      }
    }
    return null;
  }

  /// Calculates the spacer that makes a double-glazing pack fit the selected
  /// parclose exactly. It intentionally returns null when the two panes alone
  /// already fill or exceed the capacity, so an impossible spacer is never
  /// written silently.
  int? suggestedIntercallThicknessForDoubleGlass({
    required double thicknessOuter,
    required double thicknessInner,
  }) {
    final maximum = selectedParcloseMaxGlassThickness;
    if (maximum == null) return null;

    final remaining = maximum - thicknessOuter - thicknessInner;
    if (remaining <= 0) return null;
    // Intercall sizes in the catalogue are expressed in whole millimetres.
    // Never round down here: a smaller spacer would make a glazing pack that
    // does not actually match the selected parclose.
    final rounded = remaining.round();
    if ((remaining - rounded).abs() > 0.01) return null;
    return rounded;
  }

  /// Recalculates each double-glazing spacer after the user selects another
  /// parclose. The spacer is a consequence of the glazing panes and the
  /// parclose capacity, rather than a free manual choice.
  void fitDoubleGlassIntercallsToSelectedParclose() {
    if (selectedParcloseMaxGlassThickness == null) return;
    var changed = false;

    GlassSpecification fit(GlassSpecification specification) {
      if (specification.structure != GlassStructure.double) {
        return specification;
      }
      final suggested = suggestedIntercallThicknessForDoubleGlass(
        thicknessOuter: specification.thicknessOuter ?? 4.0,
        thicknessInner: specification.thicknessInner ?? 4.0,
      );
      if (suggested == null || suggested == specification.intercallThickness) {
        return specification;
      }
      changed = true;
      return specification.copyWith(intercallThickness: suggested);
    }

    for (final zone in zones) {
      zone.glass = fit(zone.glass);
      if (zone.cellGlassSpec.isNotEmpty) {
        zone.cellGlassSpec = zone.cellGlassSpec.map(
          (key, value) => MapEntry(key, fit(value)),
        );
      }
    }

    if (changed) notifyListeners();
  }

  double? _parcloseCapacity(Map<String, dynamic>? parclose) {
    if (parclose == null) return null;
    final rawValue = parclose['max_glass_thickness'];
    final value = rawValue is num
        ? rawValue.toDouble()
        : double.tryParse(rawValue?.toString() ?? '');
    return value != null && value > 0 ? value : null;
  }

  /// Ensures that double glazing is paired with a parclose that can contain
  /// both panes and a real spacer. This is deliberately called from the data
  /// model (not only from the drawer), so painting, imports and future screens
  /// cannot save an incompatible glazing combination.
  Future<bool> _ensureParcloseForGlass({
    required GlassStructure structure,
    required double paneThickness,
  }) async {
    final current = componentOverrides['باكيت الزجاج (Parclose)'];
    final currentParclose = current is Map
        ? Map<String, dynamic>.from(current)
        : null;
    final currentCapacity = _parcloseCapacity(currentParclose);

    final needsDoubleParclose = structure == GlassStructure.double;
    if (!needsDoubleParclose && structure != GlassStructure.simple) {
      return false;
    }
    final currentCode = currentParclose?['code']?.toString().trim();
    final needsReplacement = needsDoubleParclose
        ? currentCapacity == null ||
              currentCapacity <= 10.0 ||
              currentCapacity <= paneThickness
        : (currentCapacity != null && currentCapacity > 10.0) ||
              currentCode != '514';
    if (!needsReplacement) return false;

    final seriesId = activeFrameSeries?.id ?? activeSeries?.id;
    if (seriesId == null) return false;

    final dbInstance = SqlDatabase();
    final database = await dbInstance.db;
    if (database == null) return false;

    Future<void> selectParclose(Map<String, dynamic> row) async {
      final selected = Map<String, dynamic>.from(row);
      final id = selected['id'] as int?;
      if (id != null) {
        selected['calculated_price'] = await dbInstance.getSectionPrice(
          id,
          selectedDbColor?['id'],
        );
      }
      componentOverrides['باكيت الزجاج (Parclose)'] = selected;
    }

    if (needsDoubleParclose) {
      final minimumDoubleCapacity = paneThickness > 10.0 ? paneThickness : 10.0;
      // Prefer the explicitly linked double parclose of the current profile
      // when it is large enough for the selected panes.
      final rawLinkedId = currentParclose?['linked_parclose_double_id'];
      final linkedId = rawLinkedId is num
          ? rawLinkedId.toInt()
          : int.tryParse(rawLinkedId?.toString() ?? '');
      if (linkedId != null && linkedId > 0) {
        final linkedRows = await database.query(
          'Sections',
          where: 'id = ?',
          whereArgs: [linkedId],
          limit: 1,
        );
        if (linkedRows.isNotEmpty) {
          final linked = Map<String, dynamic>.from(linkedRows.first);
          if ((_parcloseCapacity(linked) ?? 0) > minimumDoubleCapacity) {
            await selectParclose(linked);
            return true;
          }
        }
      }

      final rows = await database.query(
        'Sections',
        where:
            'series_id = ? AND (LOWER(type) = ? OR LOWER(type) LIKE ? OR LOWER(name) LIKE ?) AND max_glass_thickness > ?',
        whereArgs: [
          seriesId,
          'parclose',
          '%parclose%',
          '%باكيت%',
          minimumDoubleCapacity,
        ],
        // Keep the same double-parclose default as the material table.  In a
        // typical 5 + 5 configuration this resolves the 18 mm parclose and
        // therefore the 8 mm spacer, rather than leaving an old 5 mm simple
        // parclose active in the drawer.
        orderBy: 'max_glass_thickness DESC',
        limit: 1,
      );
      if (rows.isNotEmpty) {
        await selectParclose(Map<String, dynamic>.from(rows.first));
        return true;
      }
      return false;
    }

    // Keep the existing simple-glass behaviour, but return from a double
    // parclose to a compatible single one when the glazing becomes simple.
    final rows = await database.query(
      'Sections',
      where:
          "series_id = ? AND (LOWER(type) = ? OR LOWER(type) LIKE ? OR LOWER(name) LIKE ? OR TRIM(code) = ?) AND (TRIM(code) = '514' OR COALESCE(max_glass_thickness, 0) <= 10.0)",
      whereArgs: [seriesId, 'parclose', '%parclose%', '%باكيت%', '514'],
      orderBy:
          "CASE WHEN TRIM(code) = '514' THEN 0 ELSE 1 END, max_glass_thickness ASC",
      limit: 1,
    );
    if (rows.isNotEmpty) {
      await selectParclose(Map<String, dynamic>.from(rows.first));
      return true;
    }
    return false;
  }

  /// Returns the configuration to preselect in the glass drawer.
  ///
  /// This checks the effective glass of every visible cell, including per-cell
  /// overrides. A null result means the drawing has different glass types (or
  /// no glass), so the drawer must remain at its neutral default state.
  GlassSpecification? getUniformGlassSpecification() {
    GlassSpecification? firstSpecification;

    for (final zone in zones) {
      if (zone.content == ZoneContent.empty) continue;

      for (final specification in _effectiveGlassSpecificationsForZone(zone)) {
        if (firstSpecification == null) {
          firstSpecification = specification;
        } else if (!firstSpecification.hasSameConfigurationAs(specification)) {
          return null;
        }
      }
    }

    return firstSpecification?.clone();
  }

  List<GlassSpecification> _effectiveGlassSpecificationsForZone(
    WindowZone zone,
  ) {
    final cellKeys = <String>[];

    if (zone.content == ZoneContent.slidingSash) {
      final sashCount = zone.slidingSashesCount.clamp(2, 4).toInt();
      for (var sashIndex = 0; sashIndex < sashCount; sashIndex++) {
        cellKeys.add('main_cell_0_$sashIndex');
      }
    } else if (zone.content == ZoneContent.doubleSash) {
      for (var row = 0; row <= zone.innerH; row++) {
        for (var column = 0; column <= zone.innerV; column++) {
          cellKeys.add('left_cell_${row}_$column');
        }
      }
      for (var row = 0; row <= zone.rightInnerH; row++) {
        for (var column = 0; column <= zone.rightInnerV; column++) {
          cellKeys.add('right_cell_${row}_$column');
        }
      }
    } else {
      for (var row = 0; row <= zone.innerH; row++) {
        for (var column = 0; column <= zone.innerV; column++) {
          cellKeys.add('main_cell_${row}_$column');
        }
      }
    }

    return cellKeys
        .map((cellKey) {
          final specification = zone.getGlassForCell(cellKey);
          // Older drawings can mark a cell as a panel separately from its glass
          // specification. Treat that marker as a closed/panel choice here too,
          // so it never appears in the drawer as ordinary glass.
          if (zone.cellIsPanel[cellKey] == true &&
              specification.structure != GlassStructure.closed) {
            return specification.copyWith(structure: GlassStructure.closed);
          }
          return specification;
        })
        .toList(growable: false);
  }

  void _saveSnapshot() {
    _history.add(
      WindowSnapshot(
        width,
        height,
        hasBottomFrame,
        Set<String>.from(removedShutterSides),
        hasFramePlintheBottom,
        zones.map((z) => z.clone()).toList(),
        Map.from(mullionProfiles),
        Map.from(groovedMullionCavityOnPositiveSide),
        mullionSectionOverrides.map(
          (key, value) => MapEntry(key, Map<String, dynamic>.from(value)),
        ),
        selectedDbColor != null ? Map.from(selectedDbColor!) : null,
        Map.from(componentOverrides),
        archHeight,
        topSlantLeftY,
        topSlantRightY,
        bottomSlantLeftY,
        bottomSlantRightY,
        shutterPosition,
        shutterMechanism,
        hasShutter,
        useSystemOB,
        useDemiOB,
        useVerrouCentral,
        isCaissonTunnel,
        showBottomWall,
        showWall,
        wallColor,
        primaryMullionAxis,
        drawnLeft,
        drawnTop,
        useCustomSideCoverLayout,
        sideCoverSegments.map((segment) => segment.copyWith()).toList(),
        Set<String>.from(hiddenSideCoverSegments),
        hasInternalSlidingSideCover,
        internalSlidingSideCoverOverride == null
            ? null
            : Map<String, dynamic>.from(internalSlidingSideCoverOverride!),
      ),
    );
    if (_history.length > 20) _history.removeAt(0);
    _redoHistory.clear();
    notifyListeners();
  }

  void saveSnapshotOutside() {
    _saveSnapshot();
  }

  void validateAndSanitizeAllZonesHandles() {
    for (var zone in zones) {
      if (zone.content != ZoneContent.singleSash &&
          zone.content != ZoneContent.doubleSash &&
          zone.content != ZoneContent.slidingSash) {
        // Reset handle settings for non-sash content types (fixed, slant, etc.)
        zone.lockType = LockType.none;
        zone.useOctoHandle = false;
        zone.usePvcHandleOnAlu = false;
        zone.useClassicHandle = false;
        continue;
      }

      if (zone.content == ZoneContent.slidingSash) {
        zone.lockType = LockType.none;
        zone.useOctoHandle = false;
        zone.usePvcHandleOnAlu = false;
        if (isPVC) {
          zone.useClassicHandle = false;
        }
        continue;
      }

      // Swing Sashes (singleSash or doubleSash)
      // A sash can be made thick from the profile selector, including inside
      // a divided cell.  Do not rely only on the legacy `isSash105` flag here:
      // it may still be false while the selected profile is already a door
      // sash.  Otherwise a notify immediately removes the key/bathroom/
      // Marechal choice that the user has just selected.
      final isDoorSash = _zoneUsesSash105(zone);
      if (isPVC) {
        zone.useClassicHandle = false;

        if (isDoorSash) {
          // PVC door, whether it has one sash or two: a double door still
          // supports the key, bathroom and Maréchal handle choices.  The old
          // double-sash branch reset every lock to `none` during notify(), so
          // the user could press the button but never see the selected handle.
          // A shutter does not invalidate a key or bathroom handle on a
          // thick door sash. Keep the explicit user selection intact.

          if (zone.lockType == LockType.rouleau ||
              zone.lockType == LockType.rouleau2000) {
            final doorHeight = zone.boundary.height;
            if (hasBottomFrame == true ||
                hasShutter == true ||
                doorHeight < 1250.0) {
              zone.lockType = LockType.none;
            } else if (doorHeight <= 2000.0 &&
                zone.lockType == LockType.rouleau2000) {
              zone.lockType = LockType.rouleau;
            }
          }

          if (zone.lockType != LockType.none &&
              zone.lockType != LockType.clef &&
              zone.lockType != LockType.condamnation &&
              zone.lockType != LockType.rouleau &&
              zone.lockType != LockType.rouleau2000) {
            zone.lockType = LockType.none;
          }
          zone.useOctoHandle = false;
        } else {
          // PVC window: a double sash has the normal window handle only;
          // a single sash may also use the Octo handle.
          zone.usePvcHandleOnAlu = false;
          if (zone.lockType != LockType.none) {
            zone.lockType = LockType.none;
          }
          if (zone.content == ZoneContent.doubleSash) {
            zone.useOctoHandle = false;
          }
        }
      } else {
        // Aluminium swing sashes
        zone.useClassicHandle = false;

        if (isDoorSash) {
          // Thick sash (Door)
          if (zone.content == ZoneContent.doubleSash) {
            // Double sash door: Cremone (none), Window handle, Key,
            // Bathroom and Maréchal.
            zone.useOctoHandle = false;
            if (zone.lockType == LockType.point) {
              zone.lockType = LockType.none;
            }
          } else {
            // Single sash door: Cremone (none), Window handle, Key,
            // Bathroom, Octo and Maréchal.
            if (zone.lockType == LockType.point) {
              zone.lockType = LockType.none;
            }
          }

          // A shutter does not invalidate a key or bathroom handle on a
          // thick aluminium door sash. Keep the explicit user selection.

          // Maréchal height and constraint checks
          if (zone.lockType == LockType.rouleau ||
              zone.lockType == LockType.rouleau2000) {
            if (hasBottomFrame == true || hasShutter == true) {
              zone.lockType = LockType.none;
            } else {
              final double doorHeight = zone.boundary.height;
              if (doorHeight < 1250.0) {
                zone.lockType = LockType.none;
              } else if (doorHeight <= 2000.0 &&
                  zone.lockType == LockType.rouleau2000) {
                // Downgrade 2m handle to 1.25m handle if door height is <= 2m
                zone.lockType = LockType.rouleau;
              }
            }
          }

          if (zone.lockType != LockType.none &&
              zone.lockType != LockType.clef &&
              zone.lockType != LockType.condamnation &&
              zone.lockType != LockType.rouleau &&
              zone.lockType != LockType.rouleau2000) {
            zone.lockType = LockType.none;
          }
        } else {
          // Thin sash (Window)
          if (zone.content == ZoneContent.doubleSash) {
            // Double sash thin: Cremone or the selected window handle.  The
            // latter is still drawn on only one leaf unless the explicit
            // two-handle option is enabled.
            zone.lockType = LockType.none;
            zone.useOctoHandle = false;
          } else {
            // Single sash thin: Cremone (none), Octo (useOctoHandle), Point Lock (point)
            zone.usePvcHandleOnAlu = false;
            if (zone.lockType != LockType.none &&
                zone.lockType != LockType.point) {
              zone.lockType = LockType.none;
            }
          }
        }
      }
    }
  }

  @override
  void notifyListeners() {
    validateAndSanitizeAllZonesHandles();
    super.notifyListeners();
  }

  void refreshUI() => notifyListeners();

  void _rescaleZonesInternal(
    double oldW,
    double oldH,
    double newW,
    double newH,
  ) {
    // Calculate topOffset for old height and new height correctly by temporarily setting height
    final double originalHeight = height;

    height = oldH;
    double oldTopOffset = (hasShutter && !hasArchOrSlant && !isCaissonTunnel)
        ? shutterBoxHeight
        : 0.0;

    height = newH;
    double newTopOffset = (hasShutter && !hasArchOrSlant && !isCaissonTunnel)
        ? shutterBoxHeight
        : 0.0;

    height = originalHeight;

    double bottomOffset = hasBottomFrame ? profileThickness : 0.0;
    double pHeight = hasFramePlintheBottom ? plintheHeight : 0.0;

    if (zones.isEmpty) {
      zones.add(
        WindowZone(
          id: UniqueKey().toString(),
          boundary: Rect.fromLTRB(
            profileThickness,
            newTopOffset + profileThickness,
            newW - profileThickness,
            newH - bottomOffset - pHeight,
          ),
          sashThickness: _calculateSashThickness(false),
          useClassicHandle: isPVC,
        ),
      );
      return;
    }

    final double oldInnerLeft = profileThickness;
    final double oldInnerRight = oldW - profileThickness;
    final double newInnerLeft = profileThickness;
    final double newInnerRight = newW - profileThickness;

    final double oldInnerTop = oldTopOffset + profileThickness;
    final double oldInnerBottom = oldH - bottomOffset - pHeight;
    final double newInnerTop = newTopOffset + profileThickness;
    final double newInnerBottom = newH - bottomOffset - pHeight;

    // Collect and sort unique X coordinates
    List<double> xCoords = zones
        .expand((z) => [z.boundary.left, z.boundary.right])
        .toSet()
        .toList();
    xCoords = xCoords
        .map((x) => x.clamp(oldInnerLeft, oldInnerRight))
        .toSet()
        .toList();
    xCoords.sort();

    // Collect and sort unique Y coordinates
    List<double> yCoords = zones
        .expand((z) => [z.boundary.top, z.boundary.bottom])
        .toSet()
        .toList();
    yCoords = yCoords
        .map((y) => y.clamp(oldInnerTop, oldInnerBottom))
        .toSet()
        .toList();
    yCoords.sort();

    if (xCoords.length < 2 || yCoords.length < 2) {
      // Fallback: standard linear scaling factor
      final scaleX = newW / oldW;
      final scaleY = newH / oldH;
      for (var z in zones) {
        z.boundary = Rect.fromLTRB(
          z.boundary.left * scaleX,
          z.boundary.top * scaleY,
          z.boundary.right * scaleX,
          z.boundary.bottom * scaleY,
        );
      }
      return;
    }

    // Classify X spans
    List<bool> isZoneSpanX = [];
    double totalZoneSpanOldW = 0.0;
    double totalMullionSpanOldW = 0.0;
    for (int i = 0; i < xCoords.length - 1; i++) {
      final double left = xCoords[i];
      final double right = xCoords[i + 1];
      final double spanW = right - left;
      final double mid = (left + right) / 2.0;
      bool isZone = false;
      for (var z in zones) {
        if (z.boundary.left <= mid && mid <= z.boundary.right) {
          isZone = true;
          break;
        }
      }
      isZoneSpanX.add(isZone);
      if (isZone) {
        totalZoneSpanOldW += spanW;
      } else {
        totalMullionSpanOldW += spanW;
      }
    }

    // Solve for X scaling factor
    double newInnerW = newInnerRight - newInnerLeft;
    double totalZoneSpanNewW = newInnerW - totalMullionSpanOldW;
    double scaleX = 1.0;
    if (totalZoneSpanOldW > 0 && totalZoneSpanNewW > 0) {
      scaleX = totalZoneSpanNewW / totalZoneSpanOldW;
    } else {
      scaleX = newInnerW / (oldInnerRight - oldInnerLeft);
    }

    // Map X coordinates
    Map<double, double> mapX = {};
    mapX[xCoords[0]] = newInnerLeft;
    double currentNewX = newInnerLeft;
    for (int i = 0; i < xCoords.length - 1; i++) {
      final double spanW = xCoords[i + 1] - xCoords[i];
      final double newSpanW = isZoneSpanX[i] ? (spanW * scaleX) : spanW;
      currentNewX += newSpanW;
      mapX[xCoords[i + 1]] = currentNewX;
    }

    double getMappedX(double oldX) {
      double closestKey = xCoords[0];
      double minDiff = (oldX - closestKey).abs();
      for (var k in xCoords) {
        final diff = (oldX - k).abs();
        if (diff < minDiff) {
          minDiff = diff;
          closestKey = k;
        }
      }
      if (minDiff < 1.0) {
        return mapX[closestKey]!;
      }
      int idx = 0;
      while (idx < xCoords.length - 1 && xCoords[idx + 1] < oldX) {
        idx++;
      }
      if (idx >= xCoords.length - 1) return mapX[xCoords.last]!;
      final double x0 = xCoords[idx];
      final double x1 = xCoords[idx + 1];
      final double y0 = mapX[x0]!;
      final double y1 = mapX[x1]!;
      final double t = (oldX - x0) / (x1 - x0);
      return y0 + t * (y1 - y0);
    }

    // Classify Y spans
    List<bool> isZoneSpanY = [];
    double totalZoneSpanOldH = 0.0;
    double totalMullionSpanOldH = 0.0;
    for (int i = 0; i < yCoords.length - 1; i++) {
      final double top = yCoords[i];
      final double bottom = yCoords[i + 1];
      final double spanH = bottom - top;
      final double mid = (top + bottom) / 2.0;
      bool isZone = false;
      for (var z in zones) {
        if (z.boundary.top <= mid && mid <= z.boundary.bottom) {
          isZone = true;
          break;
        }
      }
      isZoneSpanY.add(isZone);
      if (isZone) {
        totalZoneSpanOldH += spanH;
      } else {
        totalMullionSpanOldH += spanH;
      }
    }

    // Solve for Y scaling factor
    double newInnerH = newInnerBottom - newInnerTop;
    double totalZoneSpanNewH = newInnerH - totalMullionSpanOldH;
    double scaleY = 1.0;
    if (totalZoneSpanOldH > 0 && totalZoneSpanNewH > 0) {
      scaleY = totalZoneSpanNewH / totalZoneSpanOldH;
    } else {
      scaleY = newInnerH / (oldInnerBottom - oldInnerTop);
    }

    // Map Y coordinates
    Map<double, double> mapY = {};
    mapY[yCoords[0]] = newInnerTop;
    double currentNewY = newInnerTop;
    for (int i = 0; i < yCoords.length - 1; i++) {
      final double spanH = yCoords[i + 1] - yCoords[i];
      final double newSpanH = isZoneSpanY[i] ? (spanH * scaleY) : spanH;
      currentNewY += newSpanH;
      mapY[yCoords[i + 1]] = currentNewY;
    }

    double getMappedY(double oldY) {
      double closestKey = yCoords[0];
      double minDiff = (oldY - closestKey).abs();
      for (var k in yCoords) {
        final diff = (oldY - k).abs();
        if (diff < minDiff) {
          minDiff = diff;
          closestKey = k;
        }
      }
      if (minDiff < 1.0) {
        return mapY[closestKey]!;
      }
      int idx = 0;
      while (idx < yCoords.length - 1 && yCoords[idx + 1] < oldY) {
        idx++;
      }
      if (idx >= yCoords.length - 1) return mapY[yCoords.last]!;
      final double y0 = yCoords[idx];
      final double y1 = yCoords[idx + 1];
      final double z0 = mapY[y0]!;
      final double z1 = mapY[y1]!;
      final double t = (oldY - y0) / (y1 - y0);
      return z0 + t * (z1 - z0);
    }

    // Apply mapping to all zone boundaries
    for (var z in zones) {
      double left = getMappedX(z.boundary.left);
      double top = getMappedY(z.boundary.top);
      double right = getMappedX(z.boundary.right);
      double bottom = getMappedY(z.boundary.bottom);
      z.boundary = Rect.fromLTRB(left, top, right, bottom);
    }
  }

  void rescaleZones(double oldW, double oldH, double newW, double newH) {
    if (oldW <= 0 || oldH <= 0 || newW <= 0 || newH <= 0) return;
    _saveSnapshot();
    _rescaleZonesInternal(oldW, oldH, newW, newH);
    width = newW;
    height = newH;
    _resizeSideCoverSegments(oldW, oldH, newW, newH);
    updateShutterDefaultsIfNeeded();
    notifyListeners();
  }

  void undo() {
    if (_history.isEmpty) return;
    _redoHistory.add(
      WindowSnapshot(
        width,
        height,
        hasBottomFrame,
        Set<String>.from(removedShutterSides),
        hasFramePlintheBottom,
        zones.map((z) => z.clone()).toList(),
        Map.from(mullionProfiles),
        Map.from(groovedMullionCavityOnPositiveSide),
        mullionSectionOverrides.map(
          (key, value) => MapEntry(key, Map<String, dynamic>.from(value)),
        ),
        selectedDbColor != null ? Map.from(selectedDbColor!) : null,
        Map.from(componentOverrides),
        archHeight,
        topSlantLeftY,
        topSlantRightY,
        bottomSlantLeftY,
        bottomSlantRightY,
        shutterPosition,
        shutterMechanism,
        hasShutter,
        useSystemOB,
        useDemiOB,
        useVerrouCentral,
        isCaissonTunnel,
        showBottomWall,
        showWall,
        wallColor,
        primaryMullionAxis,
        drawnLeft,
        drawnTop,
        useCustomSideCoverLayout,
        sideCoverSegments.map((segment) => segment.copyWith()).toList(),
        Set<String>.from(hiddenSideCoverSegments),
        hasInternalSlidingSideCover,
        internalSlidingSideCoverOverride == null
            ? null
            : Map<String, dynamic>.from(internalSlidingSideCoverOverride!),
      ),
    );

    if (_redoHistory.length > 20) _redoHistory.removeAt(0);

    final snap = _history.removeLast();
    width = snap.width;
    height = snap.height;
    hasBottomFrame = snap.hasBottomFrame;
    removedShutterSides = Set<String>.from(snap.removedShutterSides);
    hasFramePlintheBottom = snap.hasFramePlintheBottom;
    zones = snap.zones;
    mullionProfiles = snap.mullionProfiles;
    groovedMullionCavityOnPositiveSide = Map.from(
      snap.groovedMullionCavityOnPositiveSide,
    );
    mullionSectionOverrides = snap.mullionSectionOverrides.map(
      (key, value) => MapEntry(key, Map<String, dynamic>.from(value)),
    );
    _selectedDbColor = snap.selectedDbColor;
    componentOverrides = snap.componentOverrides;
    archHeight = snap.archHeight;
    topSlantLeftY = snap.topSlantLeftY;
    topSlantRightY = snap.topSlantRightY;
    bottomSlantLeftY = snap.bottomSlantLeftY;
    bottomSlantRightY = snap.bottomSlantRightY;
    shutterPosition = snap.shutterPosition;
    shutterMechanism = snap.shutterMechanism;
    hasShutter = snap.hasShutter;
    useSystemOB = snap.useSystemOB;
    useDemiOB = snap.useDemiOB;
    useVerrouCentral = snap.useVerrouCentral;
    isCaissonTunnel = snap.isCaissonTunnel;
    showBottomWall = snap.showBottomWall;
    showWall = snap.showWall;
    wallColor = snap.wallColor;
    primaryMullionAxis = snap.primaryMullionAxis;
    drawnLeft = snap.drawnLeft;
    drawnTop = snap.drawnTop;
    useCustomSideCoverLayout = snap.useCustomSideCoverLayout;
    sideCoverSegments = snap.sideCoverSegments
        .map((segment) => segment.copyWith())
        .toList();
    hiddenSideCoverSegments = Set<String>.from(snap.hiddenSideCoverSegments);
    hasInternalSlidingSideCover = snap.hasInternalSlidingSideCover;
    internalSlidingSideCoverOverride =
        snap.internalSlidingSideCoverOverride == null
        ? null
        : Map<String, dynamic>.from(snap.internalSlidingSideCoverOverride!);
    selectedInternalSlidingSideCover = null;
    enforceBottomSideCoverConstraint();

    selection = SelectionInfo.none;
    activeSubZone = null;
    showZoneMenu = false;
    quantity = 1;
    notifyListeners();
  }

  void redo() {
    if (_redoHistory.isEmpty) return;
    _history.add(
      WindowSnapshot(
        width,
        height,
        hasBottomFrame,
        Set<String>.from(removedShutterSides),
        hasFramePlintheBottom,
        zones.map((z) => z.clone()).toList(),
        Map.from(mullionProfiles),
        Map.from(groovedMullionCavityOnPositiveSide),
        mullionSectionOverrides.map(
          (key, value) => MapEntry(key, Map<String, dynamic>.from(value)),
        ),
        selectedDbColor != null ? Map.from(selectedDbColor!) : null,
        Map.from(componentOverrides),
        archHeight,
        topSlantLeftY,
        topSlantRightY,
        bottomSlantLeftY,
        bottomSlantRightY,
        shutterPosition,
        shutterMechanism,
        hasShutter,
        useSystemOB,
        useDemiOB,
        useVerrouCentral,
        isCaissonTunnel,
        showBottomWall,
        showWall,
        wallColor,
        primaryMullionAxis,
        drawnLeft,
        drawnTop,
        useCustomSideCoverLayout,
        sideCoverSegments.map((segment) => segment.copyWith()).toList(),
        Set<String>.from(hiddenSideCoverSegments),
        hasInternalSlidingSideCover,
        internalSlidingSideCoverOverride == null
            ? null
            : Map<String, dynamic>.from(internalSlidingSideCoverOverride!),
      ),
    );
    if (_history.length > 20) _history.removeAt(0);

    final snap = _redoHistory.removeLast();
    width = snap.width;
    height = snap.height;
    hasBottomFrame = snap.hasBottomFrame;
    removedShutterSides = Set<String>.from(snap.removedShutterSides);
    hasFramePlintheBottom = snap.hasFramePlintheBottom;
    zones = snap.zones;
    mullionProfiles = snap.mullionProfiles;
    groovedMullionCavityOnPositiveSide = Map.from(
      snap.groovedMullionCavityOnPositiveSide,
    );
    mullionSectionOverrides = snap.mullionSectionOverrides.map(
      (key, value) => MapEntry(key, Map<String, dynamic>.from(value)),
    );
    _selectedDbColor = snap.selectedDbColor;
    componentOverrides = snap.componentOverrides;
    archHeight = snap.archHeight;
    topSlantLeftY = snap.topSlantLeftY;
    topSlantRightY = snap.topSlantRightY;
    bottomSlantLeftY = snap.bottomSlantLeftY;
    bottomSlantRightY = snap.bottomSlantRightY;
    shutterPosition = snap.shutterPosition;
    shutterMechanism = snap.shutterMechanism;
    hasShutter = snap.hasShutter;
    useSystemOB = snap.useSystemOB;
    useDemiOB = snap.useDemiOB;
    useVerrouCentral = snap.useVerrouCentral;
    isCaissonTunnel = snap.isCaissonTunnel;
    showBottomWall = snap.showBottomWall;
    showWall = snap.showWall;
    wallColor = snap.wallColor;
    primaryMullionAxis = snap.primaryMullionAxis;
    drawnLeft = snap.drawnLeft;
    drawnTop = snap.drawnTop;
    useCustomSideCoverLayout = snap.useCustomSideCoverLayout;
    sideCoverSegments = snap.sideCoverSegments
        .map((segment) => segment.copyWith())
        .toList();
    hiddenSideCoverSegments = Set<String>.from(snap.hiddenSideCoverSegments);
    hasInternalSlidingSideCover = snap.hasInternalSlidingSideCover;
    internalSlidingSideCoverOverride =
        snap.internalSlidingSideCoverOverride == null
        ? null
        : Map<String, dynamic>.from(snap.internalSlidingSideCoverOverride!);
    selectedInternalSlidingSideCover = null;
    enforceBottomSideCoverConstraint();

    selection = SelectionInfo.none;
    activeSubZone = null;
    showZoneMenu = false;
    quantity = 1;
    notifyListeners();
  }

  void updateLayoutMetrics(Size widgetSize) {
    // تجنب إعادة الحساب أثناء الرسم النشط لمنع تحريف الإحداثيات
    if (drawingStart != null) return;

    bool stateChanged =
        _lastIsEmpty != zones.isEmpty ||
        _lastWidth != width ||
        _lastHeight != height ||
        _lastDrawnLeft != drawnLeft ||
        _lastDrawnTop != drawnTop ||
        _lastShowWall != showWall ||
        _lastShowBottomWall != showBottomWall ||
        _lastHasShutter != hasShutter ||
        _lastIsCaissonTunnel != isCaissonTunnel ||
        _lastShutterBoxHeight != shutterBoxHeight;

    // تجنب إعادة الحساب إذا لم يتغير الحجم فعلياً (اقتصاداً في الحساب)
    if (lastLayoutSize == widgetSize &&
        !stateChanged &&
        canvasScale > 0 &&
        (canvasDx != 0 || canvasDy != 0))
      return;

    lastLayoutSize = widgetSize;
    _lastIsEmpty = zones.isEmpty;
    _lastWidth = width;
    _lastHeight = height;
    _lastDrawnLeft = drawnLeft;
    _lastDrawnTop = drawnTop;
    _lastShowWall = showWall;
    _lastShowBottomWall = showBottomWall;
    _lastHasShutter = hasShutter;
    _lastIsCaissonTunnel = isCaissonTunnel;
    _lastShutterBoxHeight = shutterBoxHeight;

    // Keep a narrow, predictable safety border around the drawing.  The
    // camera then fits the window *and* its dimension lines, rather than
    // shrinking the drawing by an arbitrary percentage.
    const double viewportPadding = 24.0;
    final bool isTallViewport = widgetSize.height > widgetSize.width * 1.15;
    final double preferredCenterY =
        widgetSize.height * (isTallViewport ? 0.61 : 0.52);

    double centeredY(double contentHeight) {
      final halfHeight = contentHeight * canvasScale / 2;
      final minCenter = halfHeight + viewportPadding / 2;
      final maxCenter = widgetSize.height - halfHeight - viewportPadding / 2;
      return math.min(maxCenter, math.max(minCenter, preferredCenterY));
    }

    if (width <= 0 || height <= 0 || zones.isEmpty) {
      double virtualW = 2400.0;
      double virtualH = 1800.0;
      double sX = (widgetSize.width - viewportPadding) / virtualW;
      double sY = (widgetSize.height - viewportPadding) / virtualH;
      canvasScale = math.min(sX, sY) * 0.94;
      canvasDx = widgetSize.width / 2 - (virtualW / 2 * canvasScale);
      canvasDy = centeredY(virtualH) - (virtualH / 2 * canvasScale);
      return;
    }

    // The dimension labels sit outside the physical frame.  Include their
    // space in the camera bounds so their text and ticks never get clipped.
    final double sideCoverExtension = hasSideCovers
        ? sideCoverWidth + 15.0
        : 0.0;
    final double dimensionLeft = 90.0 + sideCoverExtension;
    final double dimensionRight = 90.0 + sideCoverExtension;
    final double dimensionTop =
        100.0 + (hasShutter ? 20.0 : 0.0) + sideCoverExtension;
    final double dimensionBottom = 70.0 + sideCoverExtension;

    // Match the actual wall extent used by WindowPainter (500 mm on both
    // sides) instead of the previous smaller virtual extent.
    final double wallLeft = showWall ? 500.0 : 0.0;
    final double wallRight = showWall ? 500.0 : 0.0;
    final double wallTop = showWall
        ? (hasShutter ? shutterBoxHeight + 150.0 : 150.0)
        : 0.0;
    final double wallBottom = (showWall && showBottomWall) ? 200.0 : 0.0;

    final double contentLeft = math.max(wallLeft, dimensionLeft);
    final double contentRight = math.max(wallRight, dimensionRight);
    final double contentTop = math.max(wallTop, dimensionTop);
    final double contentBottom = math.max(wallBottom, dimensionBottom);
    final double totalW = width + contentLeft + contentRight;
    final double totalH = height + contentTop + contentBottom;

    final double maxW = math.max(100.0, widgetSize.width - viewportPadding);
    final double maxH = math.max(100.0, widgetSize.height - viewportPadding);

    double sX = maxW / totalW;
    double sY = maxH / totalH;
    canvasScale = math.min(sX, sY);

    final double boundsCenterX = (width + contentRight - contentLeft) / 2;
    final double boundsCenterY = (height + contentBottom - contentTop) / 2;

    if (drawnLeft != null && drawnTop != null) {
      // Keep the first frame exactly where the user dragged it on an empty
      // canvas.  The previous behaviour discarded this anchor and centred the
      // drawing after every layout update, which is especially disruptive on
      // a wide desktop canvas.
      const double virtualW = 2400.0;
      const double virtualH = 1800.0;
      final emptyScale =
          math.min(
            (widgetSize.width - viewportPadding) / virtualW,
            (widgetSize.height - viewportPadding) / virtualH,
          ) *
          0.94;
      final emptyHalfHeight = virtualH * emptyScale / 2;
      final emptyMinCenter = emptyHalfHeight + viewportPadding / 2;
      final emptyMaxCenter =
          widgetSize.height - emptyHalfHeight - viewportPadding / 2;
      final emptyCenterY = math.min(
        emptyMaxCenter,
        math.max(emptyMinCenter, preferredCenterY),
      );
      final emptyDx = widgetSize.width / 2 - virtualW * emptyScale / 2;
      final emptyDy = emptyCenterY - virtualH * emptyScale / 2;
      canvasDx = emptyDx + drawnLeft! * emptyScale;
      canvasDy = emptyDy + drawnTop! * emptyScale;
    } else {
      canvasDx = widgetSize.width / 2 - (boundsCenterX * canvasScale);
      canvasDy = centeredY(totalH) - (boundsCenterY * canvasScale);
    }
  }

  void centerDrawingOnCanvas() {
    if (drawnLeft == null && drawnTop == null) return;
    drawnLeft = null;
    drawnTop = null;
    lastLayoutSize = null;
    notifyListeners();
  }

  void toggleCopyPreviousFrameSize() {
    copyPreviousFrameSize = !copyPreviousFrameSize;
    notifyListeners();
  }

  /// Selects one outer frame in a coupled drawing.  Unlike a normal zone
  /// selection, this exposes the frame's own resize controls.
  void selectFrame(String zoneId) {
    if (!zones.any((zone) => zone.id == zoneId)) return;
    selection = SelectionInfo(type: SelectionType.frame, zoneId: zoneId);
    showZoneMenu = false;
    activeSubZone = null;
    notifyListeners();
  }

  void selectAt(Offset pos, {bool isLongPress = false}) {
    // Use actual frame profile thickness so we don't eat into zone area
    double borderSlop = profileThickness.clamp(20.0, 60.0);
    double topOffset = (hasShutter && !hasArchOrSlant && !isCaissonTunnel)
        ? shutterBoxHeight
        : 0.0;
    double topY = topOffset;
    if (pos.dx >= 0 && pos.dx <= width) {
      double t = pos.dx / width;
      double slantY = topSlantLeftY + t * (topSlantRightY - topSlantLeftY);
      if (archHeight > 0) {
        double y0 = topSlantLeftY;
        double y1 = math.min(topSlantLeftY, topSlantRightY) - (archHeight * 2);
        double y2 = topSlantRightY;
        topY =
            topOffset +
            ((1 - t) * (1 - t) * y0 + 2 * (1 - t) * t * y1 + t * t * y2);
      } else {
        topY = topOffset + slantY;
      }
    }

    // Check if clicked in empty space outside the window bounds
    if (pos.dx < 0 || pos.dx > width || pos.dy < topY || pos.dy > height) {
      selection = SelectionInfo.none;
      showZoneMenu = false;
      activeSubZone = null;
      notifyListeners();
      return;
    }

    // Now if it is close to the boundary, it's on the frame
    if (pos.dx < borderSlop ||
        pos.dx > width - borderSlop ||
        pos.dy < topY + borderSlop ||
        pos.dy > height - borderSlop) {
      selection = SelectionInfo(type: SelectionType.frame);
      showZoneMenu = false;
      activeSubZone = null;
      notifyListeners();
      return;
    }

    double hitSlop = 40.0;
    final mullionT = mullionThickness;
    // A completed divider remains selectable even after drawing mode is
    // switched off. Drawing mode controls creation only, never selection.
    if (zones.length > 1) {
      for (int i = 0; i < zones.length; i++) {
        for (int j = i + 1; j < zones.length; j++) {
          final z1 = zones[i].boundary;
          final z2 = zones[j].boundary;
          if ((z1.bottom - z2.top).abs() <= mullionT + 4 ||
              (z2.bottom - z1.top).abs() <= mullionT + 4) {
            double yCenter = (z1.bottom + z2.top) / 2;
            if ((z2.bottom - z1.top).abs() <= mullionT + 4) {
              yCenter = (z2.bottom + z1.top) / 2;
            }
            double overlapLeft = math.max(z1.left, z2.left);
            double overlapRight = math.min(z1.right, z2.right);
            if (overlapLeft < overlapRight &&
                pos.dx >= overlapLeft - 10 &&
                pos.dx <= overlapRight + 10 &&
                (pos.dy - yCenter).abs() < hitSlop) {
              selection = SelectionInfo(
                type: SelectionType.mullion,
                isHorizontalMullion: true,
                mullionPosition: yCenter,
                mullionStart: overlapLeft,
                mullionEnd: overlapRight,
              );
              showZoneMenu = false;
              activeSubZone = null;
              notifyListeners();
              return;
            }
          }
          if ((z1.right - z2.left).abs() <= mullionT + 4 ||
              (z2.right - z1.left).abs() <= mullionT + 4) {
            double xCenter = (z1.right + z2.left) / 2;
            if ((z2.right - z1.left).abs() <= mullionT + 4) {
              xCenter = (z2.right + z1.left) / 2;
            }
            double overlapTop = math.max(z1.top, z2.top);
            double overlapBottom = math.min(z1.bottom, z2.bottom);
            if (overlapTop < overlapBottom &&
                pos.dy >= overlapTop - 10 &&
                pos.dy <= overlapBottom + 10 &&
                (pos.dx - xCenter).abs() < hitSlop) {
              selection = SelectionInfo(
                type: SelectionType.mullion,
                isHorizontalMullion: false,
                mullionPosition: xCenter,
                mullionStart: overlapTop,
                mullionEnd: overlapBottom,
              );
              showZoneMenu = false;
              activeSubZone = null;
              notifyListeners();
              return;
            }
          }
        }
      }
    }
    for (var z in zones) {
      if (z.boundary.contains(pos)) {
        final sashT =
            (z.content == ZoneContent.singleSash ||
                z.content == ZoneContent.doubleSash)
            ? (z.sashThickness ?? _calculateSashThickness(z.isSash105))
            : 0.0;
        final isDouble = z.content == ZoneContent.doubleSash;

        SelectionInfo? checkSashDivisions(Rect sashRect, bool isRight) {
          final glassR = sashT > 0
              ? getSafeGlassRect(sashRect, sashT)
              : sashRect;
          final hPositions = isRight
              ? z.rightInnerHPositions
              : z.innerHPositions;
          final vPositions = isRight
              ? z.rightInnerVPositions
              : z.innerVPositions;
          final innerH = isRight ? z.rightInnerH : z.innerH;
          final innerV = isRight ? z.rightInnerV : z.innerV;

          List<double> finalHPos = List.from(hPositions);
          if (finalHPos.isEmpty && innerH > 0) {
            double stepY = 1.0 / (innerH + 1);
            for (int i = 1; i <= innerH; i++) {
              finalHPos.add(stepY * i);
            }
          }
          List<double> finalVPos = List.from(vPositions);
          if (finalVPos.isEmpty && innerV > 0) {
            double stepX = 1.0 / (innerV + 1);
            for (int i = 1; i <= innerV; i++) {
              finalVPos.add(stepX * i);
            }
          }

          final double hitThreshold = 30.0;

          for (int i = 0; i < finalHPos.length; i++) {
            double y = glassR.top + glassR.height * finalHPos[i];
            if ((pos.dy - y).abs() < hitThreshold &&
                pos.dx >= glassR.left - 10 &&
                pos.dx <= glassR.right + 10) {
              return SelectionInfo(
                type: SelectionType.innerDivision,
                zoneId: z.id,
                isHorizontalInnerDivision: true,
                isRightSashInnerDivision: isRight,
                innerDivisionIndex: i,
              );
            }
          }

          for (int i = 0; i < finalVPos.length; i++) {
            double x = glassR.left + glassR.width * finalVPos[i];
            if ((pos.dx - x).abs() < hitThreshold &&
                pos.dy >= glassR.top - 10 &&
                pos.dy <= glassR.bottom + 10) {
              return SelectionInfo(
                type: SelectionType.innerDivision,
                zoneId: z.id,
                isHorizontalInnerDivision: false,
                isRightSashInnerDivision: isRight,
                innerDivisionIndex: i,
              );
            }
          }
          return null;
        }

        final doubleSashSplitX =
            z.boundary.left + z.boundary.width * z.doubleSashRatio;
        final isRightClick = isDouble && (pos.dx > doubleSashSplitX);

        SelectionInfo? hit;
        if (isDouble) {
          final sep = 4.0;
          final leftR = Rect.fromLTRB(
            z.boundary.left,
            z.boundary.top,
            doubleSashSplitX - sep / 2,
            z.boundary.bottom,
          );
          final rightR = Rect.fromLTRB(
            doubleSashSplitX + sep / 2,
            z.boundary.top,
            z.boundary.right,
            z.boundary.bottom,
          );
          hit = isRightClick
              ? checkSashDivisions(rightR, true)
              : checkSashDivisions(leftR, false);
        } else {
          hit = checkSashDivisions(z.boundary, false);
        }

        if (hit != null) {
          selection = hit;
          showZoneMenu = false;
          activeSubZone = null;
          notifyListeners();
          return;
        }
        selection = SelectionInfo(type: SelectionType.zone, zoneId: z.id);
        bool isSingle = z.content == ZoneContent.singleSash;
        bool isSliding = z.content == ZoneContent.slidingSash;
        if (isSliding) {
          showZoneMenu = isLongPress ? false : true;
          final count = z.slidingSashesCount;

          double getSlidingSectionWidth(
            String typeName,
            String fallbackName,
            double defaultVal,
          ) {
            final series = activeSlidingSeries ?? activeSeries;
            if (series == null) return defaultVal;
            final String tName = typeName.toLowerCase();
            String? altType;
            if (tName == 'traverse') {
              altType = 'sash_traverse';
            } else if (tName == 'chicane' ||
                tName == 'central' ||
                tName == 'centrale') {
              altType = 'sash_central';
            } else if (tName == 'lateral') {
              altType = 'sash_lateral';
            }
            for (var sec in series.sections) {
              final secType = sec.type.toLowerCase();
              if (secType == tName || (altType != null && secType == altType)) {
                if (sec.visibleWidth > 0) return sec.visibleWidth;
                if (sec.thickness > 0) return sec.thickness;
              }
            }
            for (var sec in series.sections) {
              final name = sec.name.toLowerCase();
              if (name.contains(tName) || name.contains(fallbackName)) {
                if (sec.visibleWidth > 0) return sec.visibleWidth;
                if (sec.thickness > 0) return sec.thickness;
              }
            }
            return defaultVal;
          }

          final double chicaneT = getSlidingSectionWidth(
            'chicane',
            'centrale',
            45.0,
          );
          final double sashWidth =
              (z.boundary.width + (count - 1) * chicaneT) / count;

          int selectedSashIndex = -1;
          List<int> tracks;
          if (count == 2) {
            tracks = (z.openDirection == OpenDirection.left) ? [1, 0] : [0, 1];
          } else if (count == 3) {
            tracks = [0, 1, 0];
          } else if (count == 4) {
            tracks = [0, 1, 1, 0];
          } else {
            tracks = List.generate(count, (i) => i % 2);
          }

          bool clickedInsideGlass = false;
          final sashT = z.sashThickness ?? _calculateSashThickness(z.isSash105);

          for (int tg = 1; tg >= 0; tg--) {
            for (int i = 0; i < count; i++) {
              if (tracks[i] == tg) {
                double left = z.boundary.left + i * (sashWidth - chicaneT);
                Rect sashRect = Rect.fromLTRB(
                  left,
                  z.boundary.top,
                  left + sashWidth,
                  z.boundary.bottom,
                );
                if (sashRect.contains(pos)) {
                  selectedSashIndex = i;
                  Rect glassR = sashRect.deflate(sashT);
                  if (glassR.contains(pos)) {
                    clickedInsideGlass = true;
                  }
                  break;
                }
              }
            }
            if (selectedSashIndex != -1) break;
          }

          if (selectedSashIndex == -1) {
            double tX = (pos.dx - z.boundary.left) / z.boundary.width;
            selectedSashIndex = (tX * count).floor().clamp(0, count - 1);
          }

          if (clickedInsideGlass) {
            activeSubZone = 'main_cell_0_$selectedSashIndex';
          } else {
            activeSubZone = null;
          }
          selection = SelectionInfo(type: SelectionType.zone, zoneId: z.id);
          notifyListeners();
          return;
        }

        if (isDouble || isSingle) {
          showZoneMenu = isLongPress ? false : true;
          if (isLongPress && isDouble) {
            activeSubZone = 'all';
          } else {
            double splitX =
                z.boundary.left + z.boundary.width * z.doubleSashRatio;
            bool isRight = isDouble && (pos.dx > splitX);
            Rect sashR = z.boundary;
            if (isDouble) {
              final sep = 4.0;
              sashR = isRight
                  ? Rect.fromLTRB(
                      splitX + sep / 2,
                      z.boundary.top,
                      z.boundary.right,
                      z.boundary.bottom,
                    )
                  : Rect.fromLTRB(
                      z.boundary.left,
                      z.boundary.top,
                      splitX - sep / 2,
                      z.boundary.bottom,
                    );
            }
            final sashT =
                z.sashThickness ?? _calculateSashThickness(z.isSash105);
            final glassR = sashR.deflate(sashT);
            if (glassR.contains(pos)) {
              int currentInnerH = isRight ? z.rightInnerH : z.innerH;
              int currentInnerV = isRight ? z.rightInnerV : z.innerV;

              List<double> vPositions = List.from(
                isRight ? z.rightInnerVPositions : z.innerVPositions,
              )..sort();
              if (vPositions.isEmpty && currentInnerV > 0) {
                double stepX = 1.0 / (currentInnerV + 1);
                for (int i = 1; i <= currentInnerV; i++) {
                  vPositions.add(stepX * i);
                }
              }
              List<double> hPositions = List.from(
                isRight ? z.rightInnerHPositions : z.innerHPositions,
              )..sort();
              if (hPositions.isEmpty && currentInnerH > 0) {
                double stepY = 1.0 / (currentInnerH + 1);
                for (int i = 1; i <= currentInnerH; i++) {
                  hPositions.add(stepY * i);
                }
              }

              double xRatio = ((pos.dx - glassR.left) / glassR.width).clamp(
                0.0,
                1.0,
              );
              double yRatio = ((pos.dy - glassR.top) / glassR.height).clamp(
                0.0,
                1.0,
              );

              int col = 0;
              for (int i = 0; i < vPositions.length; i++) {
                if (xRatio > vPositions[i]) col = i + 1;
              }
              int row = 0;
              for (int i = 0; i < hPositions.length; i++) {
                if (yRatio > hPositions[i]) row = i + 1;
              }

              final mergedMap = z.getMergedCellMap(
                isRightSash: isRight,
                isDouble: isDouble,
              );
              final targetKey = mergedMap["${row}_$col"] ?? "${row}_$col";
              final parts = targetKey.split('_');
              int finalRow = int.parse(parts[0]);
              int finalCol = int.parse(parts[1]);

              String sidePrefix = isDouble
                  ? (isRight ? 'right' : 'left')
                  : 'main';
              activeSubZone = '${sidePrefix}_cell_${finalRow}_$finalCol';
            } else {
              activeSubZone = isDouble ? (isRight ? 'right' : 'left') : 'main';
            }
          }
        } else {
          showZoneMenu = isLongPress ? false : true;
          activeSubZone = 'all';
        }
        notifyListeners();
        return;
      }
    }
    selection = SelectionInfo.none;
    activeSubZone = null;
    showZoneMenu = false;
    notifyListeners();
  }

  void clearSelection() {
    selection = SelectionInfo.none;
    activeSubZone = null;
    showZoneMenu = false;
    notifyListeners();
  }

  int? checkMullionDimensionTap(Offset pos) {
    if (selection.type != SelectionType.mullion ||
        selection.mullionPosition == null) {
      return null;
    }
    bool isH = selection.isHorizontalMullion!;
    double mPos = selection.mullionPosition!;
    double hitW = 400.0;
    double hitH = 200.0;
    if (isH) {
      if (Rect.fromCenter(
        center: Offset(width / 2, mPos / 2),
        width: hitW,
        height: hitH,
      ).contains(pos)) {
        return 1;
      }
      if (Rect.fromCenter(
        center: Offset(width / 2, mPos + (height - mPos) / 2),
        width: hitW,
        height: hitH,
      ).contains(pos)) {
        return 2;
      }
    } else {
      if (Rect.fromCenter(
        center: Offset(mPos / 2, height / 2),
        width: hitW,
        height: hitH,
      ).contains(pos)) {
        return 1;
      }
      if (Rect.fromCenter(
        center: Offset(mPos + (width - mPos) / 2, height / 2),
        width: hitW,
        height: hitH,
      ).contains(pos)) {
        return 2;
      }
    }
    return null;
  }

  void resizeMullionDimension(int section, double newVal) {
    if (selection.type != SelectionType.mullion ||
        selection.mullionPosition == null) {
      return;
    }
    _saveSnapshot();
    bool isH = selection.isHorizontalMullion!;
    double oldPos = selection.mullionPosition!;
    final oldKey = _mullionKey(isH, oldPos);
    final t = profileThickness;
    final mullionT = mullionThickness;
    final sep = mullionT / 2;
    double newPos = oldPos;
    if (isH) {
      newPos = (section == 1) ? newVal + t + sep : height - newVal - t - sep;
      double minAllowedY = t * 2;
      double maxAllowedY = height - t * 2;
      for (var z in zones) {
        if ((z.boundary.bottom - (oldPos - sep)).abs() < 2) {
          if (z.boundary.top + 50 > minAllowedY) {
            minAllowedY = z.boundary.top + 50;
          }
        }
        if ((z.boundary.top - (oldPos + sep)).abs() < 2) {
          if (z.boundary.bottom - 50 < maxAllowedY) {
            maxAllowedY = z.boundary.bottom - 50;
          }
        }
      }
      if (newPos < minAllowedY) newPos = minAllowedY;
      if (newPos > maxAllowedY) newPos = maxAllowedY;
      double delta = newPos - oldPos;
      for (var z in zones) {
        if ((z.boundary.bottom - (oldPos - sep)).abs() < 2) {
          z.boundary = Rect.fromLTRB(
            z.boundary.left,
            z.boundary.top,
            z.boundary.right,
            z.boundary.bottom + delta,
          );
        } else if ((z.boundary.top - (oldPos + sep)).abs() < 2) {
          z.boundary = Rect.fromLTRB(
            z.boundary.left,
            z.boundary.top + delta,
            z.boundary.right,
            z.boundary.bottom,
          );
        }
      }
    } else {
      newPos = (section == 1) ? newVal + t + sep : width - newVal - t - sep;
      double minAllowedX = t * 2;
      double maxAllowedX = width - t * 2;
      for (var z in zones) {
        if ((z.boundary.right - (oldPos - sep)).abs() < 2) {
          if (z.boundary.left + 50 > minAllowedX) {
            minAllowedX = z.boundary.left + 50;
          }
        }
        if ((z.boundary.left - (oldPos + sep)).abs() < 2) {
          if (z.boundary.right - 50 < maxAllowedX) {
            maxAllowedX = z.boundary.right - 50;
          }
        }
      }
      if (newPos < minAllowedX) newPos = minAllowedX;
      if (newPos > maxAllowedX) newPos = maxAllowedX;
      double delta = newPos - oldPos;
      for (var z in zones) {
        if ((z.boundary.right - (oldPos - sep)).abs() < 2) {
          z.boundary = Rect.fromLTRB(
            z.boundary.left,
            z.boundary.top,
            z.boundary.right + delta,
            z.boundary.bottom,
          );
        } else if ((z.boundary.left - (oldPos + sep)).abs() < 2) {
          z.boundary = Rect.fromLTRB(
            z.boundary.left + delta,
            z.boundary.top,
            z.boundary.right,
            z.boundary.bottom,
          );
        }
      }
    }
    selection = SelectionInfo(
      type: SelectionType.mullion,
      isHorizontalMullion: isH,
      mullionPosition: newPos,
    );
    _moveMullionMetadata(oldKey, _mullionKey(isH, newPos));
    notifyListeners();
  }

  void setSelectedZonePanelFinish(GlassFinish finish) {
    if (selectedZone == null) return;
    _saveSnapshot();
    final zone = selectedZone!;
    zone.glass = zone.glass.copyWith(
      finishOuter: finish,
      finishInner: finish,
      structure: GlassStructure.closed,
    );
    notifyListeners();
  }

  void paintZoneOrCellSpec(
    String zoneId, {
    required GlassSpecification spec,
    String? cellId,
  }) {
    _saveSnapshot();
    try {
      final zone = zones.firstWhere((z) => z.id == zoneId);

      if (cellId != null && cellId.contains('cell_')) {
        // Store per-cell spec override
        final updatedCellGlass = Map<String, GlassSpecification>.from(
          zone.cellGlassSpec,
        );
        updatedCellGlass[cellId] = spec.clone();
        zone.cellGlassSpec = updatedCellGlass;

        if (spec.structure == GlassStructure.closed) {
          final updatedCells = Map<String, bool>.from(zone.cellIsPanel);
          updatedCells[cellId] = true;
          zone.cellIsPanel = updatedCells;

          final updatedSashes = Map<String, bool>.from(zone.cellIsSash);
          updatedSashes[cellId] = false;
          zone.cellIsSash = updatedSashes;
        } else {
          final updatedCells = Map<String, bool>.from(zone.cellIsPanel);
          updatedCells[cellId] = false;
          zone.cellIsPanel = updatedCells;

          // إذا كانت الخلية زجاجاً في زون من نوع ضلفة → نعود للمحتوى الأصلي
          final updatedCellGlass2 = Map<String, GlassSpecification>.from(
            zone.cellGlassSpec,
          );
          updatedCellGlass2[cellId] = spec.clone();
          zone.cellGlassSpec = updatedCellGlass2;
        }
      } else {
        // لا توجد خلية محددة → تطبيق على الزون كلها
        zone.glass = spec.clone();
        zone.cellGlassSpec = {};
        WindowZone.globalDefaultGlass = zone.glass;

        if (spec.structure == GlassStructure.closed) {
          // تحويل الزون إلى زجاج ثابت (fixedGlass) حتى يظهر البانو
          zone.content = ZoneContent.fixedGlass;
          // وضع علامة على جميع الخلايا الداخلية كبانو
          final updatedPanels = Map<String, bool>.from(zone.cellIsPanel);
          final updatedSashes = Map<String, bool>.from(zone.cellIsSash);
          for (int r = 0; r <= zone.innerH; r++) {
            for (int c = 0; c <= zone.innerV; c++) {
              final key = 'main_cell_${r}_$c';
              updatedPanels[key] = true;
              updatedSashes[key] = false;
            }
          }
          zone.cellIsPanel = updatedPanels;
          zone.cellIsSash = updatedSashes;
        }
      }
      notifyListeners();
    } catch (_) {}
  }

  void paintAllZonesSpec(GlassSpecification spec) {
    _saveSnapshot();
    for (var z in zones) {
      z.glass = spec.clone();
      z.cellGlassSpec = {}; // clear all per-cell overrides
      if (spec.structure == GlassStructure.closed) {
        z.content = ZoneContent.fixedGlass;
        final updatedPanels = Map<String, bool>.from(z.cellIsPanel);
        final updatedSashes = Map<String, bool>.from(z.cellIsSash);
        for (int r = 0; r <= z.innerH; r++) {
          for (int c = 0; c <= z.innerV; c++) {
            updatedPanels['main_cell_${r}_$c'] = true;
            updatedSashes['main_cell_${r}_$c'] = false;
          }
        }
        if (z.content == ZoneContent.doubleSash) {
          for (int r = 0; r <= z.rightInnerH; r++) {
            for (int c = 0; c <= z.rightInnerV; c++) {
              updatedPanels['right_cell_${r}_$c'] = true;
              updatedSashes['right_cell_${r}_$c'] = false;
            }
          }
        }
        z.cellIsPanel = updatedPanels;
        z.cellIsSash = updatedSashes;
      }
    }
    WindowZone.globalDefaultGlass = spec;
    updateGlassGasket();
    notifyListeners();
  }

  void paintZoneOrCell(
    String zoneId, {
    required GlassFinish finish,
    required GlassStructure structure,
    String? cellId,
    ClosedGlassColor? colorP,
    GlassColor? color,
  }) {
    _saveSnapshot();
    try {
      final zone = zones.firstWhere((z) => z.id == zoneId);

      zone.glass = zone.glass.copyWith(
        structure: structure,
        finishOuter: finish,
        finishInner: finish,
        colorP: colorP ?? zone.glass.colorP,
        colorOuter: color ?? zone.glass.colorOuter,
        colorInner: color ?? zone.glass.colorInner,
      );
      WindowZone.globalDefaultGlass = zone.glass;

      if (cellId != null && cellId.contains('cell_')) {
        if (structure == GlassStructure.closed) {
          final updatedCells = Map<String, bool>.from(zone.cellIsPanel);
          updatedCells[cellId] = true;
          zone.cellIsPanel = updatedCells;

          final updatedSashes = Map<String, bool>.from(zone.cellIsSash);
          updatedSashes[cellId] = false;
          zone.cellIsSash = updatedSashes;
        } else {
          final updatedCells = Map<String, bool>.from(zone.cellIsPanel);
          updatedCells[cellId] = false;
          zone.cellIsPanel = updatedCells;
        }
      } else {
        if (structure == GlassStructure.closed) {
          zone.content = ZoneContent.fixedGlass;
        }
      }
      notifyListeners();
    } catch (_) {}
  }

  void paintZoneContent(
    String zoneId,
    ZoneContent content, {
    int? slidingSashesCount,
    bool? cutSlidingGlassRebate,
  }) {
    _saveSnapshot();
    try {
      final zone = zones.firstWhere((z) => z.id == zoneId);
      zone.content = content;
      zone.innerH = 0;
      zone.innerV = 0;
      zone.rightInnerH = 0;
      zone.rightInnerV = 0;
      zone.innerHPositions = const [];
      zone.innerVPositions = const [];
      zone.rightInnerHPositions = const [];
      zone.rightInnerVPositions = const [];
      zone.primaryDivisionAxis = null;
      zone.rightPrimaryDivisionAxis = null;
      zone.cellIsPanel.clear();
      zone.cellIsSash.clear();
      zone.cellIsDoubleSash.clear();

      if (slidingSashesCount != null) {
        zone.slidingSashesCount = slidingSashesCount;
      }
      if (content == ZoneContent.slidingSash) {
        zone.cutSlidingGlassRebate =
            cutSlidingGlassRebate ?? zone.cutSlidingGlassRebate;
      }

      bool is105 = _determineIsSash105FromSashOverride();
      zone.isSash105 = is105;
      zone.sashThickness = _calculateSashThickness(is105);
      if (content == ZoneContent.doubleSash ||
          content == ZoneContent.singleSash ||
          content == ZoneContent.slidingSash) {
        zone.openDirection = OpenDirection.right;
      } else {
        zone.openDirection = null;
      }
      notifyListeners();
    } catch (_) {}
  }

  void toggleSelectedCellPanel() {
    if (selectedZone == null) return;
    _saveSnapshot();
    final zone = selectedZone!;
    if (activeSubZone != null && activeSubZone!.contains('cell_')) {
      bool isCurrentlyPanel = zone.cellIsPanel[activeSubZone!] ?? false;
      Map<String, bool> updatedCells = Map.from(zone.cellIsPanel);
      updatedCells[activeSubZone!] = !isCurrentlyPanel;
      zone.cellIsPanel = updatedCells;

      // If it becomes a panel, it cannot be a sash or double sash
      if (updatedCells[activeSubZone!] == true) {
        Map<String, bool> updatedSashes = Map.from(zone.cellIsSash);
        updatedSashes[activeSubZone!] = false;
        zone.cellIsSash = updatedSashes;

        Map<String, bool> updatedDoubleSashes = Map.from(zone.cellIsDoubleSash);
        updatedDoubleSashes[activeSubZone!] = false;
        zone.cellIsDoubleSash = updatedDoubleSashes;
      }
    } else if (zone.content == ZoneContent.empty ||
        zone.content == ZoneContent.fixedGlass) {
      if (zone.glass.structure == GlassStructure.closed) {
        zone.glass = zone.glass.copyWith(structure: GlassStructure.simple);
      } else {
        zone.content = ZoneContent.fixedGlass;
        final currentFinish = zone.glass.finishOuter;
        final GlassFinish targetFinish =
            (currentFinish == GlassFinish.paneauSandwitch ||
                currentFinish == GlassFinish.resine ||
                currentFinish == GlassFinish.paneauSandwitchDecore ||
                currentFinish == GlassFinish.bardage ||
                currentFinish == GlassFinish.plexyGlass)
            ? currentFinish
            : GlassFinish.paneauSandwitch;

        zone.glass = zone.glass.copyWith(
          structure: GlassStructure.closed,
          finishInner: targetFinish,
          finishOuter: targetFinish,
          colorP: ClosedGlassColor.white,
        );
      }
    }
    notifyListeners();
  }

  void toggleSelectedCellSash() {
    if (selectedZone == null || selectedZone!.id.contains('_nested_')) return;
    _saveSnapshot();
    final zone = selectedZone!;
    if (activeSubZone != null && activeSubZone!.contains('cell_')) {
      bool isCurrentlySash = zone.cellIsSash[activeSubZone!] ?? false;
      Map<String, bool> updatedSashes = Map.from(zone.cellIsSash);
      updatedSashes[activeSubZone!] = !isCurrentlySash;
      zone.cellIsSash = updatedSashes;

      // If it becomes a sash, it cannot be a panel or double sash
      if (updatedSashes[activeSubZone!] == true) {
        Map<String, bool> updatedCells = Map.from(zone.cellIsPanel);
        updatedCells[activeSubZone!] = false;
        zone.cellIsPanel = updatedCells;

        Map<String, bool> updatedDoubleSashes = Map.from(zone.cellIsDoubleSash);
        updatedDoubleSashes[activeSubZone!] = false;
        zone.cellIsDoubleSash = updatedDoubleSashes;
      }
    }
    notifyListeners();
  }

  void toggleSelectedCellDoubleSash() {
    if (selectedZone == null || selectedZone!.id.contains('_nested_')) return;
    _saveSnapshot();
    final zone = selectedZone!;
    if (activeSubZone != null && activeSubZone!.contains('cell_')) {
      bool isCurrentlyDoubleSash =
          zone.cellIsDoubleSash[activeSubZone!] ?? false;
      Map<String, bool> updatedDoubleSashes = Map.from(zone.cellIsDoubleSash);
      updatedDoubleSashes[activeSubZone!] = !isCurrentlyDoubleSash;
      zone.cellIsDoubleSash = updatedDoubleSashes;

      // If it becomes a double sash, it cannot be a panel or single sash
      if (updatedDoubleSashes[activeSubZone!] == true) {
        Map<String, bool> updatedCells = Map.from(zone.cellIsPanel);
        updatedCells[activeSubZone!] = false;
        zone.cellIsPanel = updatedCells;

        Map<String, bool> updatedSashes = Map.from(zone.cellIsSash);
        updatedSashes[activeSubZone!] = false;
        zone.cellIsSash = updatedSashes;
      }
    }
    notifyListeners();
  }

  void paintCellSash(String zoneId, String cellId, bool isSash) {
    _saveSnapshot();
    try {
      final zone = zones.firstWhere((z) => z.id == zoneId);
      Map<String, bool> updatedSashes = Map.from(zone.cellIsSash);
      updatedSashes[cellId] = isSash;
      zone.cellIsSash = updatedSashes;

      if (isSash) {
        Map<String, bool> updatedCells = Map.from(zone.cellIsPanel);
        updatedCells[cellId] = false;
        zone.cellIsPanel = updatedCells;

        Map<String, bool> updatedDoubleSashes = Map.from(zone.cellIsDoubleSash);
        updatedDoubleSashes[cellId] = false;
        zone.cellIsDoubleSash = updatedDoubleSashes;
      }
      notifyListeners();
    } catch (_) {}
  }

  void paintCellDoubleSash(String zoneId, String cellId, bool isDoubleSash) {
    _saveSnapshot();
    try {
      final zone = zones.firstWhere((z) => z.id == zoneId);
      Map<String, bool> updatedDoubleSashes = Map.from(zone.cellIsDoubleSash);
      updatedDoubleSashes[cellId] = isDoubleSash;
      zone.cellIsDoubleSash = updatedDoubleSashes;

      if (isDoubleSash) {
        Map<String, bool> updatedCells = Map.from(zone.cellIsPanel);
        updatedCells[cellId] = false;
        zone.cellIsPanel = updatedCells;

        Map<String, bool> updatedSashes = Map.from(zone.cellIsSash);
        updatedSashes[cellId] = false;
        zone.cellIsSash = updatedSashes;
      }
      notifyListeners();
    } catch (_) {}
  }

  void paintCellPanel(String zoneId, String cellId, bool isPanel) {
    _saveSnapshot();
    try {
      final zone = zones.firstWhere((z) => z.id == zoneId);
      Map<String, bool> updatedCells = Map.from(zone.cellIsPanel);
      updatedCells[cellId] = isPanel;
      zone.cellIsPanel = updatedCells;

      if (isPanel) {
        Map<String, bool> updatedSashes = Map.from(zone.cellIsSash);
        updatedSashes[cellId] = false;
        zone.cellIsSash = updatedSashes;

        Map<String, bool> updatedDoubleSashes = Map.from(zone.cellIsDoubleSash);
        updatedDoubleSashes[cellId] = false;
        zone.cellIsDoubleSash = updatedDoubleSashes;
      }
      notifyListeners();
    } catch (_) {}
  }

  void updateZoneInnerHDivisionRatio(
    String zoneId,
    bool isRightSash,
    int index,
    double ratio,
  ) {
    final idx = zones.indexWhere((z) => z.id == zoneId);
    if (idx == -1) return;
    _saveSnapshot();
    final zone = zones[idx];
    if (isRightSash) {
      if (zone.rightInnerHPositions.length != zone.rightInnerH) {
        zone.rightInnerHPositions = List.generate(
          zone.rightInnerH,
          (i) => (i + 1) / (zone.rightInnerH + 1),
        );
      }
      final mutable = List<double>.from(zone.rightInnerHPositions);
      if (index >= 0 && index < mutable.length) {
        double minVal = index == 0 ? 0.05 : mutable[index - 1] + 0.05;
        double maxVal = index == mutable.length - 1
            ? 0.95
            : mutable[index + 1] - 0.05;
        if (minVal > maxVal) minVal = maxVal - 0.01;
        mutable[index] = ratio.clamp(minVal, maxVal);
        zone.rightInnerHPositions = mutable;
      }
    } else {
      if (zone.innerHPositions.length != zone.innerH) {
        zone.innerHPositions = List.generate(
          zone.innerH,
          (i) => (i + 1) / (zone.innerH + 1),
        );
      }
      final mutable = List<double>.from(zone.innerHPositions);
      if (index >= 0 && index < mutable.length) {
        double minVal = index == 0 ? 0.05 : mutable[index - 1] + 0.05;
        double maxVal = index == mutable.length - 1
            ? 0.95
            : mutable[index + 1] - 0.05;
        if (minVal > maxVal) minVal = maxVal - 0.01;
        mutable[index] = ratio.clamp(minVal, maxVal);
        zone.innerHPositions = mutable;
      }
    }
    notifyListeners();
  }

  void updateZoneInnerVDivisionRatio(
    String zoneId,
    bool isRightSash,
    int index,
    double ratio,
  ) {
    final idx = zones.indexWhere((z) => z.id == zoneId);
    if (idx == -1) return;
    _saveSnapshot();
    final zone = zones[idx];
    if (isRightSash) {
      if (zone.rightInnerVPositions.length != zone.rightInnerV) {
        zone.rightInnerVPositions = List.generate(
          zone.rightInnerV,
          (i) => (i + 1) / (zone.rightInnerV + 1),
        );
      }
      final mutable = List<double>.from(zone.rightInnerVPositions);
      if (index >= 0 && index < mutable.length) {
        double minVal = index == 0 ? 0.05 : mutable[index - 1] + 0.05;
        double maxVal = index == mutable.length - 1
            ? 0.95
            : mutable[index + 1] - 0.05;
        if (minVal > maxVal) minVal = maxVal - 0.01;
        mutable[index] = ratio.clamp(minVal, maxVal);
        zone.rightInnerVPositions = mutable;
      }
    } else {
      if (zone.innerVPositions.length != zone.innerV) {
        zone.innerVPositions = List.generate(
          zone.innerV,
          (i) => (i + 1) / (zone.innerV + 1),
        );
      }
      final mutable = List<double>.from(zone.innerVPositions);
      if (index >= 0 && index < mutable.length) {
        double minVal = index == 0 ? 0.05 : mutable[index - 1] + 0.05;
        double maxVal = index == mutable.length - 1
            ? 0.95
            : mutable[index + 1] - 0.05;
        if (minVal > maxVal) minVal = maxVal - 0.01;
        mutable[index] = ratio.clamp(minVal, maxVal);
        zone.innerVPositions = mutable;
      }
    }
    notifyListeners();
  }

  void updateHandlePosition(String zoneId, double ratio) {
    final idx = zones.indexWhere((z) => z.id == zoneId);
    if (idx != -1) {
      zones[idx].handlePositionRatio = ratio;
      notifyListeners();
    }
  }

  void updateHingePosition(String zoneId, double offset) {
    final idx = zones.indexWhere((z) => z.id == zoneId);
    if (idx != -1) {
      zones[idx] = zones[idx].copyWith(middleHingeDragOffset: offset);
      notifyListeners();
    }
  }

  void updateZoneDoubleSashRatio(String zoneId, double ratio) {
    final idx = zones.indexWhere((z) => z.id == zoneId);
    if (idx != -1) {
      final zone = zones[idx];
      OpenDirection? newDir = zone.openDirection;
      if (ratio > 0.5) {
        newDir = OpenDirection.left;
      } else if (ratio < 0.5) {
        newDir = OpenDirection.right;
      }
      zones[idx] = zone.copyWith(doubleSashRatio: ratio, openDirection: newDir);
      notifyListeners();
    }
  }

  DimensionTap checkOuterDimensionTap(Offset pos) {
    if (Rect.fromLTRB(0, -300, width, -50).contains(pos)) {
      return DimensionTap.width;
    }
    if (Rect.fromLTRB(-300, 0, -50, height).contains(pos)) {
      return DimensionTap.height;
    }
    return DimensionTap.none;
  }

  InnerDimensionHit? _checkSashDivisionHit(
    String zoneId,
    bool isRightSash,
    bool isSash,
    Rect glassR,
    int innerH,
    int innerV,
    List<double> innerHPos,
    List<double> innerVPos,
    Offset pos,
  ) {
    if (innerH == 0 && innerV == 0) return null;

    List<double> hPositions = List.from(innerHPos);
    if (hPositions.isEmpty && innerH > 0) {
      double stepY = 1.0 / (innerH + 1);
      for (int i = 1; i <= innerH; i++) {
        hPositions.add(stepY * i);
      }
    }
    List<double> vPositions = List.from(innerVPos);
    if (vPositions.isEmpty && innerV > 0) {
      double stepX = 1.0 / (innerV + 1);
      for (int i = 1; i <= innerV; i++) {
        vPositions.add(stepX * i);
      }
    }

    int rows = hPositions.length + 1;
    int cols = vPositions.length + 1;

    // 🟢 التحقق من الضغط على أرقام العرض (الأفقية)
    if (cols > 1) {
      for (int col = 0; col < cols; col++) {
        double leftRatio = col == 0 ? 0.0 : vPositions[col - 1];
        double rightRatio = col == cols - 1 ? 1.0 : vPositions[col];
        double left = glassR.left + (glassR.width * leftRatio);
        double right = glassR.left + (glassR.width * rightRatio);
        double cellW = right - left;

        final leftX = left + cellW / 2;
        // تكبير مساحة الضغط لتسهيل النقر على الرقم
        if (Rect.fromCenter(
          center: Offset(leftX, glassR.top + 25),
          width: 120,
          height: 80,
        ).contains(pos)) {
          return InnerDimensionHit(
            zoneId,
            true, // isWidth
            isDoubleSashLeft: !isRightSash,
            isDoubleSashRight: isRightSash,
            isSashDivision: isSash,
            isHorizontalDivision: false,
            divisionIndex: col,
          );
        }
      }
    }

    // 🟢 التحقق من الضغط على أرقام الارتفاع (العمودية)
    if (rows > 1) {
      for (int row = 0; row < rows; row++) {
        double topRatio = row == 0 ? 0.0 : hPositions[row - 1];
        double bottomRatio = row == rows - 1 ? 1.0 : hPositions[row];
        double top = glassR.top + (glassR.height * topRatio);
        double bottom = glassR.top + (glassR.height * bottomRatio);
        double cellH = bottom - top;

        final topY = top + cellH / 2;
        // تكبير مساحة الضغط لتسهيل النقر على الرقم
        if (Rect.fromCenter(
          center: Offset(glassR.left + 25, topY),
          width: 80,
          height: 120,
        ).contains(pos)) {
          return InnerDimensionHit(
            zoneId,
            false, // isHeight
            isDoubleSashLeft: !isRightSash,
            isDoubleSashRight: isRightSash,
            isSashDivision: isSash,
            isHorizontalDivision: true,
            divisionIndex: row,
          );
        }
      }
    }

    return null;
  }

  InnerDimensionHit? checkInnerDimensionTap(Offset pos) {
    for (var z in zones) {
      final r = z.boundary;
      if (r.width < 150 || r.height < 150) continue;

      // 1. Check if it's a sash division click first
      if (z.content == ZoneContent.singleSash ||
          z.content == ZoneContent.doubleSash) {
        final sashT =
            z.sashThickness ?? getSectionThickness('sash', fallback: 45.0);
        if (z.content == ZoneContent.doubleSash) {
          final sep = 4.0;
          final midX = r.left + r.width * z.doubleSashRatio;
          final leftR = Rect.fromLTRB(r.left, r.top, midX - sep / 2, r.bottom);
          final rightR = Rect.fromLTRB(
            midX + sep / 2,
            r.top,
            r.right,
            r.bottom,
          );

          final leftGlassR = getSafeGlassRect(leftR, sashT);
          final rightGlassR = getSafeGlassRect(rightR, sashT);

          final hitL = _checkSashDivisionHit(
            z.id,
            false,
            true,
            // isSash
            leftGlassR,
            z.innerH,
            z.innerV,
            z.innerHPositions,
            z.innerVPositions,
            pos,
          );
          if (hitL != null) return hitL;

          final hitR = _checkSashDivisionHit(
            z.id,
            true,
            true,
            // isSash
            rightGlassR,
            z.rightInnerH,
            z.rightInnerV,
            z.rightInnerHPositions,
            z.rightInnerVPositions,
            pos,
          );
          if (hitR != null) return hitR;
        } else {
          final glassR = getSafeGlassRect(r, sashT);
          final hit = _checkSashDivisionHit(
            z.id,
            false,
            true,
            // isSash
            glassR,
            z.innerH,
            z.innerV,
            z.innerHPositions,
            z.innerVPositions,
            pos,
          );
          if (hit != null) return hit;
        }
      } else {
        // NOT a sash, it's a fixed frame!
        final sashT = getSectionThickness('sash', fallback: 45.0);
        final glassR = getSafeGlassRect(r, sashT);
        final hit = _checkSashDivisionHit(
          z.id,
          false,
          false,
          // isSash
          glassR,
          z.innerH,
          z.innerV,
          z.innerHPositions,
          z.innerVPositions,
          pos,
        );
        if (hit != null) return hit;
      }

      // 2. Standard clicks
      bool isFullWidth = (r.width >= width - profileThickness * 2 - 2);
      bool isFullHeight = (r.height >= height - profileThickness * 2 - 2);
      final bottomInset = math.min(28.0, math.max(16.0, r.height * 0.18));
      final rightInset = math.min(28.0, math.max(16.0, r.width * 0.18));
      if (!isFullWidth &&
          Rect.fromCenter(
            center: Offset(r.center.dx, r.bottom - bottomInset),
            width: math.min(190.0, math.max(120.0, r.width * 0.6)),
            height: 70,
          ).contains(pos)) {
        return InnerDimensionHit(z.id, true);
      }
      if (!isFullHeight &&
          Rect.fromCenter(
            center: Offset(r.right - rightInset, r.center.dy),
            width: 70,
            height: math.min(190.0, math.max(120.0, r.height * 0.6)),
          ).contains(pos)) {
        return InnerDimensionHit(z.id, false);
      }
      if (z.content == ZoneContent.doubleSash) {
        // Match the mirrored ratio used by WindowPainter when viewing the
        // exterior face. The touch target must sit on the visible label.
        final effectiveRatio = isInternalView
            ? z.doubleSashRatio
            : 1.0 - z.doubleSashRatio;
        final leftX = r.left + (r.width * effectiveRatio) / 2;
        if (Rect.fromCenter(
          center: Offset(leftX, r.top + 20),
          width: 120,
          height: 80,
        ).contains(pos)) {
          return InnerDimensionHit(z.id, true, isDoubleSashLeft: true);
        }

        final rightX =
            r.left +
            (r.width * effectiveRatio) +
            (r.width * (1.0 - effectiveRatio)) / 2;
        if (Rect.fromCenter(
          center: Offset(rightX, r.top + 20),
          width: 120,
          height: 80,
        ).contains(pos)) {
          return InnerDimensionHit(z.id, true, isDoubleSashRight: true);
        }
      } else {
        if (!isFullWidth &&
            z.content != ZoneContent.singleSash &&
            z.content != ZoneContent.slidingSash) {
          if (Rect.fromCenter(
            center: Offset(r.center.dx, r.top + 20),
            width: 150,
            height: 80,
          ).contains(pos)) {
            return InnerDimensionHit(z.id, true);
          }
        }
      }
      if (!isFullHeight &&
          z.content != ZoneContent.singleSash &&
          z.content != ZoneContent.doubleSash &&
          z.content != ZoneContent.slidingSash) {
        if (Rect.fromCenter(
          center: Offset(r.left + 20, r.center.dy),
          width: 80,
          height: 150,
        ).contains(pos)) {
          return InnerDimensionHit(z.id, false);
        }
      }
    }
    return null;
  }

  void resizeWindow(double newW, double newH) {
    _saveSnapshot();
    final oldWidth = width;
    final oldHeight = height;
    _rescaleZonesInternal(oldWidth, oldHeight, newW, newH);
    width = newW;
    height = newH;
    _resizeSideCoverSegments(oldWidth, oldHeight, newW, newH);
    lastLayoutSize = null; // أجبر إعادة حساب canvasScale عند تغيير الحجم
    updateShutterDefaultsIfNeeded();
    notifyListeners();
  }

  double getMaxAllowedInnerSize(String zoneId, bool isWidth) {
    final zIdx = zones.indexWhere((z) => z.id == zoneId);
    if (zIdx == -1) return 0;
    final r = zones[zIdx].boundary;
    final sep = divisionThickness / 2;
    if (isWidth) {
      final bool isRightmost = !zones.any((z) => z.boundary.left > r.right - 2);
      if (isRightmost) {
        double oldX = r.left;
        double minAllowedX = profileThickness * 2;
        double divisionX = oldX - sep;
        for (var z in zones) {
          if ((z.boundary.right - (divisionX - sep)).abs() < 2) {
            if (z.boundary.left + 50 > minAllowedX) {
              minAllowedX = z.boundary.left + 50;
            }
          }
        }
        return r.width + (oldX - (minAllowedX + sep));
      } else {
        double oldX = r.right;
        double maxAllowedX = width - profileThickness * 2;
        double divisionX = oldX + sep;
        for (var z in zones) {
          if ((z.boundary.left - (divisionX + sep)).abs() < 2) {
            if (z.boundary.right - 50 < maxAllowedX) {
              maxAllowedX = z.boundary.right - 50;
            }
          }
        }
        return r.width + ((maxAllowedX - sep) - oldX);
      }
    } else {
      final bool isBottommost = !zones.any(
        (z) => z.boundary.top > r.bottom - 2,
      );
      if (isBottommost) {
        double oldY = r.top;
        double minAllowedY = profileThickness * 2;
        double divisionY = oldY - sep;
        for (var z in zones) {
          if ((z.boundary.bottom - (divisionY - sep)).abs() < 2) {
            if (z.boundary.top + 50 > minAllowedY) {
              minAllowedY = z.boundary.top + 50;
            }
          }
        }
        return r.height + (oldY - (minAllowedY + sep));
      } else {
        double oldY = r.bottom;
        double maxAllowedY = height - profileThickness * 2;
        double divisionY = oldY + sep;
        for (var z in zones) {
          if ((z.boundary.top - (divisionY + sep)).abs() < 2) {
            if (z.boundary.bottom - 50 < maxAllowedY) {
              maxAllowedY = z.boundary.bottom - 50;
            }
          }
        }
        return r.height + ((maxAllowedY - sep) - oldY);
      }
    }
  }

  void resizeZoneInner(String zoneId, bool isWidth, double newVal) {
    _saveSnapshot();
    final zIdx = zones.indexWhere((z) => z.id == zoneId);
    if (zIdx == -1) return;
    final r = zones[zIdx].boundary;
    if (isWidth) {
      double diff = newVal - r.width;
      if (diff == 0) return;
      if (newVal > width - 50) diff = (width - 50) - r.width;
      final bool isRightmost = !zones.any((z) => z.boundary.left > r.right - 2);
      if (isRightmost) {
        _moveInternalBoundaryX(r.left, -diff);
      } else {
        _moveInternalBoundaryX(r.right, diff);
      }
    } else {
      double diff = newVal - r.height;
      if (diff == 0) return;
      if (newVal > height - 50) diff = (height - 50) - r.height;
      final bool isBottommost = !zones.any(
        (z) => z.boundary.top > r.bottom - 2,
      );
      if (isBottommost) {
        _moveInternalBoundaryY(r.top, -diff);
      } else {
        _moveInternalBoundaryY(r.bottom, diff);
      }
    }
    notifyListeners();
  }

  /// Resizes one selected outer frame from the supplied handles.  Internal
  /// edges change the overall drawing size and shift the following frames, so
  /// neighbouring frame sizes stay unchanged.
  void resizeFrameFromHandles(
    String zoneId, {
    required bool moveLeft,
    required bool moveRight,
    required bool moveTop,
    required bool moveBottom,
    required double deltaX,
    required double deltaY,
    bool saveHistory = true,
  }) {
    if (zones.length < 2) return;
    final zoneIndex = zones.indexWhere((zone) => zone.id == zoneId);
    if (zoneIndex == -1) return;
    if (saveHistory) _saveSnapshot();
    final oldWidth = width;
    final oldHeight = height;

    const minInnerSize = 50.0;

    bool isLeftOuter(WindowZone zone) => !zones.any(
      (other) =>
          other.id != zone.id && other.boundary.left < zone.boundary.left - 2,
    );
    bool isRightOuter(WindowZone zone) => !zones.any(
      (other) =>
          other.id != zone.id && other.boundary.right > zone.boundary.right + 2,
    );
    bool isTopOuter(WindowZone zone) => !zones.any(
      (other) =>
          other.id != zone.id && other.boundary.top < zone.boundary.top - 2,
    );
    bool isBottomOuter(WindowZone zone) => !zones.any(
      (other) =>
          other.id != zone.id &&
          other.boundary.bottom > zone.boundary.bottom + 2,
    );

    void resizeRightEdge() {
      final zone = zones[zoneIndex];
      double actual = deltaX;
      if (zone.boundary.width + actual < minInnerSize) {
        actual = minInnerSize - zone.boundary.width;
      }
      if (width + actual < 200.0) {
        actual = 200.0 - width;
      }
      if (actual.abs() < 0.001) return;
      if (!isRightOuter(zone)) {
        final oldRight = zone.boundary.right;
        zone.boundary = Rect.fromLTRB(
          zone.boundary.left,
          zone.boundary.top,
          zone.boundary.right + actual,
          zone.boundary.bottom,
        );
        for (var i = 0; i < zones.length; i++) {
          final other = zones[i];
          if (other.id == zone.id || other.boundary.left < oldRight - 1.0) {
            continue;
          }
          zones[i].boundary = other.boundary.shift(Offset(actual, 0));
        }
        width = math.max(200.0, width + actual);
        return;
      }

      final rightInset = width - zone.boundary.right;
      zone.boundary = Rect.fromLTRB(
        zone.boundary.left,
        zone.boundary.top,
        zone.boundary.right + actual,
        zone.boundary.bottom,
      );
      double largestOuterRight = zone.boundary.right + rightInset;
      for (final other in zones) {
        if (other.id == zone.id) continue;
        largestOuterRight = math.max(
          largestOuterRight,
          other.boundary.right + rightInset,
        );
      }
      width = math.max(200.0, largestOuterRight);
    }

    void resizeLeftEdge() {
      final zone = zones[zoneIndex];
      double actual = deltaX;
      if (zone.boundary.width - actual < minInnerSize) {
        actual = zone.boundary.width - minInnerSize;
      }
      if (width - actual < 200.0) {
        actual = width - 200.0;
      }
      if (actual.abs() < 0.001) return;
      if (!isLeftOuter(zone)) {
        final oldRight = zone.boundary.right;
        zone.boundary = Rect.fromLTRB(
          zone.boundary.left,
          zone.boundary.top,
          zone.boundary.right - actual,
          zone.boundary.bottom,
        );
        for (var i = 0; i < zones.length; i++) {
          final other = zones[i];
          if (other.id == zone.id || other.boundary.left < oldRight - 1.0) {
            continue;
          }
          zones[i].boundary = other.boundary.shift(Offset(-actual, 0));
        }
        width = math.max(200.0, width - actual);
        return;
      }

      // Coordinates are anchored at the left edge of the complete drawing.
      // Rebase all frames when this exterior edge moves so there is never an
      // empty gap at x = 0.
      final outerLeft = zone.boundary.left;
      final rightInset = width - zone.boundary.right;
      for (final other in zones) {
        final bool sharesLeft = (other.boundary.left - outerLeft).abs() < 2.0;
        other.boundary = Rect.fromLTRB(
          sharesLeft ? outerLeft : other.boundary.left - actual,
          other.boundary.top,
          other.boundary.right - actual,
          other.boundary.bottom,
        );
      }
      double maxRight = 200.0;
      for (final other in zones) {
        maxRight = math.max(maxRight, other.boundary.right + rightInset);
      }
      width = maxRight;
    }

    void resizeBottomEdge() {
      final zone = zones[zoneIndex];
      double actual = deltaY;
      if (zone.boundary.height + actual < minInnerSize) {
        actual = minInnerSize - zone.boundary.height;
      }
      if (height + actual < 200.0) {
        actual = 200.0 - height;
      }
      if (actual.abs() < 0.001) return;
      if (!isBottomOuter(zone)) {
        final oldBottom = zone.boundary.bottom;
        zone.boundary = Rect.fromLTRB(
          zone.boundary.left,
          zone.boundary.top,
          zone.boundary.right,
          zone.boundary.bottom + actual,
        );
        for (var i = 0; i < zones.length; i++) {
          final other = zones[i];
          if (other.id == zone.id || other.boundary.top < oldBottom - 1.0) {
            continue;
          }
          zones[i].boundary = other.boundary.shift(Offset(0, actual));
        }
        height = math.max(200.0, height + actual);
        return;
      }

      final bottomInset = height - zone.boundary.bottom;
      zone.boundary = Rect.fromLTRB(
        zone.boundary.left,
        zone.boundary.top,
        zone.boundary.right,
        zone.boundary.bottom + actual,
      );
      double largestOuterBottom = zone.boundary.bottom + bottomInset;
      for (final other in zones) {
        if (other.id == zone.id) continue;
        largestOuterBottom = math.max(
          largestOuterBottom,
          other.boundary.bottom + bottomInset,
        );
      }
      height = math.max(200.0, largestOuterBottom);
    }

    void resizeTopEdge() {
      final zone = zones[zoneIndex];
      double actual = deltaY;
      if (zone.boundary.height - actual < minInnerSize) {
        actual = zone.boundary.height - minInnerSize;
      }
      if (height - actual < 200.0) {
        actual = height - 200.0;
      }
      if (actual.abs() < 0.001) return;
      if (!isTopOuter(zone)) {
        final oldBottom = zone.boundary.bottom;
        zone.boundary = Rect.fromLTRB(
          zone.boundary.left,
          zone.boundary.top,
          zone.boundary.right,
          zone.boundary.bottom - actual,
        );
        for (var i = 0; i < zones.length; i++) {
          final other = zones[i];
          if (other.id == zone.id || other.boundary.top < oldBottom - 1.0) {
            continue;
          }
          zones[i].boundary = other.boundary.shift(Offset(0, -actual));
        }
        height = math.max(200.0, height - actual);
        return;
      }

      // Same rebasing rule as the left exterior edge: keep the drawing
      // connected to its top origin while its overall height changes.
      final outerTop = zone.boundary.top;
      final bottomInset = height - zone.boundary.bottom;
      for (final other in zones) {
        final bool sharesTop = (other.boundary.top - outerTop).abs() < 2.0;
        other.boundary = Rect.fromLTRB(
          other.boundary.left,
          sharesTop ? outerTop : other.boundary.top - actual,
          other.boundary.right,
          other.boundary.bottom - actual,
        );
      }
      double maxBottom = 200.0;
      for (final other in zones) {
        maxBottom = math.max(maxBottom, other.boundary.bottom + bottomInset);
      }
      height = maxBottom;
    }

    if (moveLeft) resizeLeftEdge();
    if (moveRight) resizeRightEdge();
    if (moveTop) resizeTopEdge();
    if (moveBottom) resizeBottomEdge();
    _resizeSideCoverSegments(oldWidth, oldHeight, width, height);
    notifyListeners();
  }

  void _moveInternalBoundaryX(double oldX, double diff) {
    // Coupled frames have a double frame gap, not a simple mullion gap.  Use
    // the same half-gap as creation so resizing moves both adjoining frames
    // together instead of leaving a blank space or creating an overlap.
    final sep = divisionThickness / 2;
    double divisionX = oldX;
    bool foundRight = false;
    for (var z in zones) {
      if ((z.boundary.right - oldX).abs() < 2) {
        divisionX = oldX + sep;
        foundRight = true;
        break;
      }
    }
    if (!foundRight) {
      for (var z in zones) {
        if ((z.boundary.left - oldX).abs() < 2) {
          divisionX = oldX - sep;
          break;
        }
      }
    }

    final t = profileThickness;
    double minAllowedX = t * 2;
    double maxAllowedX = width - t * 2;
    for (var z in zones) {
      if ((z.boundary.right - (divisionX - sep)).abs() < 2) {
        if (z.boundary.left + 50 > minAllowedX) {
          minAllowedX = z.boundary.left + 50;
        }
      }
      if ((z.boundary.left - (divisionX + sep)).abs() < 2) {
        if (z.boundary.right - 50 < maxAllowedX) {
          maxAllowedX = z.boundary.right - 50;
        }
      }
    }

    double newDivisionX = divisionX + diff;
    if (newDivisionX - sep < minAllowedX) {
      newDivisionX = minAllowedX + sep;
    }
    if (newDivisionX + sep > maxAllowedX) {
      newDivisionX = maxAllowedX - sep;
    }
    double actualDiff = newDivisionX - divisionX;
    if (actualDiff.abs() < 0.001) return;
    final oldKey = _mullionKey(false, divisionX);

    for (int i = 0; i < zones.length; i++) {
      var z = zones[i];
      if ((z.boundary.right - (divisionX - sep)).abs() < 2) {
        z.boundary = Rect.fromLTRB(
          z.boundary.left,
          z.boundary.top,
          z.boundary.right + actualDiff,
          z.boundary.bottom,
        );
      }
      if ((z.boundary.left - (divisionX + sep)).abs() < 2) {
        z.boundary = Rect.fromLTRB(
          z.boundary.left + actualDiff,
          z.boundary.top,
          z.boundary.right,
          z.boundary.bottom,
        );
      }
    }
    _moveMullionMetadata(oldKey, _mullionKey(false, newDivisionX));
    if (selection.type == SelectionType.mullion &&
        selection.isHorizontalMullion == false &&
        selection.mullionPosition != null &&
        (selection.mullionPosition! - divisionX).abs() < 2) {
      selection = SelectionInfo(
        type: SelectionType.mullion,
        isHorizontalMullion: false,
        mullionPosition: newDivisionX,
        mullionStart: selection.mullionStart,
        mullionEnd: selection.mullionEnd,
      );
    }
  }

  void _moveInternalBoundaryY(double oldY, double diff) {
    // See _moveInternalBoundaryX: coupled frames are separated by
    // [divisionThickness], so their common boundary is its midpoint.
    final sep = divisionThickness / 2;
    double divisionY = oldY;
    bool foundBottom = false;
    for (var z in zones) {
      if ((z.boundary.bottom - oldY).abs() < 2) {
        divisionY = oldY + sep;
        foundBottom = true;
        break;
      }
    }
    if (!foundBottom) {
      for (var z in zones) {
        if ((z.boundary.top - oldY).abs() < 2) {
          divisionY = oldY - sep;
          break;
        }
      }
    }

    final t = profileThickness;
    double minAllowedY = t * 2;
    double maxAllowedY = height - t * 2;
    for (var z in zones) {
      if ((z.boundary.bottom - (divisionY - sep)).abs() < 2) {
        if (z.boundary.top + 50 > minAllowedY) {
          minAllowedY = z.boundary.top + 50;
        }
      }
      if ((z.boundary.top - (divisionY + sep)).abs() < 2) {
        if (z.boundary.bottom - 50 < maxAllowedY) {
          maxAllowedY = z.boundary.bottom - 50;
        }
      }
    }

    double newDivisionY = divisionY + diff;
    if (newDivisionY - sep < minAllowedY) {
      newDivisionY = minAllowedY + sep;
    }
    if (newDivisionY + sep > maxAllowedY) {
      newDivisionY = maxAllowedY - sep;
    }
    double actualDiff = newDivisionY - divisionY;
    if (actualDiff.abs() < 0.001) return;
    final oldKey = _mullionKey(true, divisionY);

    for (int i = 0; i < zones.length; i++) {
      var z = zones[i];
      if ((z.boundary.bottom - (divisionY - sep)).abs() < 2) {
        z.boundary = Rect.fromLTRB(
          z.boundary.left,
          z.boundary.top,
          z.boundary.right,
          z.boundary.bottom + actualDiff,
        );
      }
      if ((z.boundary.top - (divisionY + sep)).abs() < 2) {
        z.boundary = Rect.fromLTRB(
          z.boundary.left,
          z.boundary.top + actualDiff,
          z.boundary.right,
          z.boundary.bottom,
        );
      }
    }
    _moveMullionMetadata(oldKey, _mullionKey(true, newDivisionY));
    if (selection.type == SelectionType.mullion &&
        selection.isHorizontalMullion == true &&
        selection.mullionPosition != null &&
        (selection.mullionPosition! - divisionY).abs() < 2) {
      selection = SelectionInfo(
        type: SelectionType.mullion,
        isHorizontalMullion: true,
        mullionPosition: newDivisionY,
        mullionStart: selection.mullionStart,
        mullionEnd: selection.mullionEnd,
      );
    }
  }

  String? removeSashDivisions({
    WindowZone? zoneOverride,
    String? targetCellKey,
  }) {
    final zone = zoneOverride ?? selectedZone;
    if (zone == null) return null;
    _saveSnapshot();
    final selectedCell = targetCellKey ?? activeSubZone;

    // Fresh zones use immutable empty-map defaults. Make every collection
    // mutable before removing the divisions and their obsolete cell data.
    zone.cellIsPanel = Map<String, bool>.from(zone.cellIsPanel);
    zone.cellIsSash = Map<String, bool>.from(zone.cellIsSash);
    zone.cellIsDoubleSash = Map<String, bool>.from(zone.cellIsDoubleSash);
    zone.cellSashOverrides = Map<String, Map<String, dynamic>>.from(
      zone.cellSashOverrides,
    );
    zone.cellGlassSpec = Map<String, GlassSpecification>.from(
      zone.cellGlassSpec,
    );
    zone.disabledVerticalDivisions = Map<String, bool>.from(
      zone.disabledVerticalDivisions,
    );
    zone.disabledHorizontalDivisions = Map<String, bool>.from(
      zone.disabledHorizontalDivisions,
    );

    void clearCellData(bool Function(String key) matches) {
      zone.cellIsPanel.removeWhere((key, value) => matches(key));
      zone.cellIsSash.removeWhere((key, value) => matches(key));
      zone.cellIsDoubleSash.removeWhere((key, value) => matches(key));
      zone.cellSashOverrides.removeWhere((key, value) => matches(key));
      zone.cellGlassSpec.removeWhere((key, value) => matches(key));
    }

    String? normalizedCell;
    if (selectedCell != null && selectedCell.startsWith('right')) {
      zone.rightInnerH = 0;
      zone.rightInnerV = 0;
      zone.rightInnerHPositions = const [];
      zone.rightInnerVPositions = const [];
      zone.rightPrimaryDivisionAxis = null;
      zone.disabledVerticalDivisions.removeWhere(
        (key, value) => key.startsWith('right_'),
      );
      zone.disabledHorizontalDivisions.removeWhere(
        (key, value) => key.startsWith('right_'),
      );
      clearCellData((key) => key.startsWith('right'));
      normalizedCell = 'right_cell_0_0';
    } else if (selectedCell != null && selectedCell.startsWith('left')) {
      zone.innerH = 0;
      zone.innerV = 0;
      zone.innerHPositions = const [];
      zone.innerVPositions = const [];
      zone.primaryDivisionAxis = null;
      zone.disabledVerticalDivisions.removeWhere(
        (key, value) => !key.startsWith('right_'),
      );
      zone.disabledHorizontalDivisions.removeWhere(
        (key, value) => !key.startsWith('right_'),
      );
      clearCellData((key) => key.startsWith('left'));
      normalizedCell = 'left_cell_0_0';
    } else if (selectedCell != null && selectedCell.startsWith('main')) {
      zone.innerH = 0;
      zone.innerV = 0;
      zone.innerHPositions = const [];
      zone.innerVPositions = const [];
      zone.primaryDivisionAxis = null;
      zone.disabledVerticalDivisions.removeWhere(
        (key, value) => !key.startsWith('right_'),
      );
      zone.disabledHorizontalDivisions.removeWhere(
        (key, value) => !key.startsWith('right_'),
      );
      clearCellData((key) => key.startsWith('main'));
      normalizedCell = 'main_cell_0_0';
    } else {
      zone.innerH = 0;
      zone.innerV = 0;
      zone.rightInnerH = 0;
      zone.rightInnerV = 0;
      zone.innerHPositions = const [];
      zone.innerVPositions = const [];
      zone.rightInnerHPositions = const [];
      zone.rightInnerVPositions = const [];
      zone.primaryDivisionAxis = null;
      zone.rightPrimaryDivisionAxis = null;
      zone.cellIsPanel.clear();
      zone.cellIsSash.clear();
      zone.cellIsDoubleSash.clear();
      zone.cellSashOverrides.clear();
      zone.cellGlassSpec.clear();
      zone.disabledVerticalDivisions.clear();
      zone.disabledHorizontalDivisions.clear();
    }
    if (identical(zone, selectedZone)) activeSubZone = normalizedCell;
    notifyListeners();
    return normalizedCell;
  }

  void updatePrimaryMullionAxis() {
    bool hasHorizontalBoundaries = false;
    bool hasVerticalBoundaries = false;

    for (int i = 0; i < zones.length; i++) {
      final z1 = zones[i];
      for (int j = i + 1; j < zones.length; j++) {
        final z2 = zones[j];

        double overlapLeft = math.max(z1.boundary.left, z2.boundary.left);
        double overlapRight = math.min(z1.boundary.right, z2.boundary.right);
        if (overlapLeft < overlapRight - 5.0) {
          if ((z1.boundary.bottom - z2.boundary.top).abs() <=
                  divisionThickness + 2.0 ||
              (z2.boundary.bottom - z1.boundary.top).abs() <=
                  divisionThickness + 2.0) {
            hasHorizontalBoundaries = true;
          }
        }

        double overlapTop = math.max(z1.boundary.top, z2.boundary.top);
        double overlapBottom = math.min(z1.boundary.bottom, z2.boundary.bottom);
        if (overlapTop < overlapBottom - 5.0) {
          if ((z1.boundary.right - z2.boundary.left).abs() <=
                  divisionThickness + 2.0 ||
              (z2.boundary.right - z1.boundary.left).abs() <=
                  divisionThickness + 2.0) {
            hasVerticalBoundaries = true;
          }
        }
      }
    }

    if (!hasHorizontalBoundaries && !hasVerticalBoundaries) {
      // No partitions remain — reset axis so next split starts fresh
      primaryMullionAxis = null;
    } else if (primaryMullionAxis == null) {
      // Set the axis ONCE on the first split, then never change it automatically.
      // This ensures the first partition the user adds is always the primary (continuous).
      if (!hasHorizontalBoundaries) {
        primaryMullionAxis = 'v';
      } else if (!hasVerticalBoundaries) {
        primaryMullionAxis = 'h';
      } else {
        primaryMullionAxis = 'h';
      }
      // Once set, primaryMullionAxis is only changed explicitly by the user.
    }
    // If primaryMullionAxis is already set, NEVER override it automatically.
    // The first partition the user added determines the primary axis forever.
  }

  void splitSelectedZoneHorizontal({
    int parts = 2,
    List<double>? customSizes,
    bool fromTop = true,
  }) {
    if (selectedZone == null) return;
    _saveSnapshot();
    final zone = selectedZone!;
    final index = zones.indexOf(zone);
    final sep = mullionThickness / 2;
    zones.removeAt(index);
    if (customSizes != null && customSizes.isNotEmpty) {
      if (parts == 2) {
        double splitY = fromTop
            ? zone.boundary.top + customSizes[0]
            : zone.boundary.bottom - customSizes[0];
        if (splitY > zone.boundary.top + 20 &&
            splitY < zone.boundary.bottom - 20) {
          zones.insert(
            index,
            WindowZone(
              id: UniqueKey().toString(),
              boundary: Rect.fromLTRB(
                zone.boundary.left,
                splitY + sep,
                zone.boundary.right,
                zone.boundary.bottom,
              ),
              sashColor: zone.sashColor,
              content: zone.content,
              glass: zone.glass.clone(),
              openDirection: zone.openDirection,
              sashThickness: zone.sashThickness,
              isSash105: zone.isSash105,
              lockType: zone.lockType,
              hasSashPlintheBottom: zone.hasSashPlintheBottom,
            ),
          );
          zones.insert(
            index,
            WindowZone(
              id: UniqueKey().toString(),
              boundary: Rect.fromLTRB(
                zone.boundary.left,
                zone.boundary.top,
                zone.boundary.right,
                splitY - sep,
              ),
              sashColor: zone.sashColor,
              content: zone.content,
              glass: zone.glass.clone(),
              openDirection: zone.openDirection,
              sashThickness: zone.sashThickness,
              isSash105: zone.isSash105,
              lockType: zone.lockType,
              hasSashPlintheBottom: zone.hasSashPlintheBottom,
            ),
          );
        } else {
          zones.insert(index, zone);
        }
      } else if (parts == 3 && customSizes.length >= 2) {
        double splitY1 = zone.boundary.top + customSizes[0];
        double splitY2 = zone.boundary.bottom - customSizes[1];
        if (splitY2 > splitY1 + 40) {
          zones.insert(
            index,
            WindowZone(
              id: UniqueKey().toString(),
              boundary: Rect.fromLTRB(
                zone.boundary.left,
                splitY2 + sep,
                zone.boundary.right,
                zone.boundary.bottom,
              ),
              sashColor: zone.sashColor,
              content: zone.content,
              glass: zone.glass.clone(),
              openDirection: zone.openDirection,
              sashThickness: zone.sashThickness,
              isSash105: zone.isSash105,
              lockType: zone.lockType,
              hasSashPlintheBottom: zone.hasSashPlintheBottom,
            ),
          );
          zones.insert(
            index,
            WindowZone(
              id: UniqueKey().toString(),
              boundary: Rect.fromLTRB(
                zone.boundary.left,
                splitY1 + sep,
                zone.boundary.right,
                splitY2 - sep,
              ),
              sashColor: zone.sashColor,
              content: zone.content,
              glass: zone.glass.clone(),
              openDirection: zone.openDirection,
              sashThickness: zone.sashThickness,
              isSash105: zone.isSash105,
              lockType: zone.lockType,
              hasSashPlintheBottom: zone.hasSashPlintheBottom,
            ),
          );
          zones.insert(
            index,
            WindowZone(
              id: UniqueKey().toString(),
              boundary: Rect.fromLTRB(
                zone.boundary.left,
                zone.boundary.top,
                zone.boundary.right,
                splitY1 - sep,
              ),
              sashColor: zone.sashColor,
              content: zone.content,
              glass: zone.glass.clone(),
              openDirection: zone.openDirection,
              sashThickness: zone.sashThickness,
              isSash105: zone.isSash105,
              lockType: zone.lockType,
              hasSashPlintheBottom: zone.hasSashPlintheBottom,
            ),
          );
        } else {
          zones.insert(index, zone);
        }
      }
    } else {
      // الحجم المتاح بعد خصم جميع الفواصل بين الأجزاء
      final totalMullions = (parts - 1) * mullionThickness;
      final availableHeight = zone.boundary.height - totalMullions;
      final stepY = availableHeight / parts;
      for (int i = 0; i < parts; i++) {
        double top = zone.boundary.top + (i * stepY) + (i * mullionThickness);
        double bottom = top + stepY;
        zones.insert(
          index + i,
          WindowZone(
            id: UniqueKey().toString(),
            boundary: Rect.fromLTRB(
              zone.boundary.left,
              top,
              zone.boundary.right,
              bottom,
            ),
            sashColor: zone.sashColor,
            content: zone.content,
            glass: zone.glass.clone(),
            openDirection: zone.openDirection,
            sashThickness: zone.sashThickness,
            isSash105: zone.isSash105,
            lockType: zone.lockType,
            hasSashPlintheBottom: zone.hasSashPlintheBottom,
          ),
        );
      }
    }
    updatePrimaryMullionAxis();
    selection = SelectionInfo.none;
    showZoneMenu = false;
    activeSubZone = null;
    notifyListeners();
  }

  void splitSelectedZoneVertical({
    int parts = 2,
    List<double>? customSizes,
    bool fromLeft = true,
  }) {
    if (selectedZone == null) return;
    _saveSnapshot();
    final zone = selectedZone!;
    final index = zones.indexOf(zone);
    final sep = mullionThickness / 2;
    zones.removeAt(index);
    if (customSizes != null && customSizes.isNotEmpty) {
      if (parts == 2) {
        double splitX = fromLeft
            ? zone.boundary.left + customSizes[0]
            : zone.boundary.right - customSizes[0];
        if (splitX > zone.boundary.left + 20 &&
            splitX < zone.boundary.right - 20) {
          zones.insert(
            index,
            WindowZone(
              id: UniqueKey().toString(),
              boundary: Rect.fromLTRB(
                splitX + sep,
                zone.boundary.top,
                zone.boundary.right,
                zone.boundary.bottom,
              ),
              sashColor: zone.sashColor,
              content: zone.content,
              glass: zone.glass.clone(),
              openDirection: zone.openDirection,
              sashThickness: zone.sashThickness,
              isSash105: zone.isSash105,
              lockType: zone.lockType,
              hasSashPlintheBottom: zone.hasSashPlintheBottom,
            ),
          );
          zones.insert(
            index,
            WindowZone(
              id: UniqueKey().toString(),
              boundary: Rect.fromLTRB(
                zone.boundary.left,
                zone.boundary.top,
                splitX - sep,
                zone.boundary.bottom,
              ),
              sashColor: zone.sashColor,
              content: zone.content,
              glass: zone.glass.clone(),
              openDirection: zone.openDirection,
              sashThickness: zone.sashThickness,
              isSash105: zone.isSash105,
              lockType: zone.lockType,
              hasSashPlintheBottom: zone.hasSashPlintheBottom,
            ),
          );
        } else {
          zones.insert(index, zone);
        }
      } else if (parts == 3 && customSizes.length >= 2) {
        double splitX1 = zone.boundary.left + customSizes[0];
        double splitX2 = zone.boundary.right - customSizes[1];
        if (splitX2 > splitX1 + 40) {
          zones.insert(
            index,
            WindowZone(
              id: UniqueKey().toString(),
              boundary: Rect.fromLTRB(
                splitX2 + sep,
                zone.boundary.top,
                zone.boundary.right,
                zone.boundary.bottom,
              ),
              sashColor: zone.sashColor,
              content: zone.content,
              glass: zone.glass.clone(),
              openDirection: zone.openDirection,
              sashThickness: zone.sashThickness,
              isSash105: zone.isSash105,
              lockType: zone.lockType,
              hasSashPlintheBottom: zone.hasSashPlintheBottom,
            ),
          );
          zones.insert(
            index,
            WindowZone(
              id: UniqueKey().toString(),
              boundary: Rect.fromLTRB(
                splitX1 + sep,
                zone.boundary.top,
                splitX2 - sep,
                zone.boundary.bottom,
              ),
              sashColor: zone.sashColor,
              content: zone.content,
              glass: zone.glass.clone(),
              openDirection: zone.openDirection,
              sashThickness: zone.sashThickness,
              isSash105: zone.isSash105,
              lockType: zone.lockType,
              hasSashPlintheBottom: zone.hasSashPlintheBottom,
            ),
          );
          zones.insert(
            index,
            WindowZone(
              id: UniqueKey().toString(),
              boundary: Rect.fromLTRB(
                zone.boundary.left,
                zone.boundary.top,
                splitX1 - sep,
                zone.boundary.bottom,
              ),
              sashColor: zone.sashColor,
              content: zone.content,
              glass: zone.glass.clone(),
              openDirection: zone.openDirection,
              sashThickness: zone.sashThickness,
              isSash105: zone.isSash105,
              lockType: zone.lockType,
              hasSashPlintheBottom: zone.hasSashPlintheBottom,
            ),
          );
        } else {
          zones.insert(index, zone);
        }
      }
    } else {
      // الحجم المتاح بعد خصم جميع الفواصل بين الأجزاء
      final totalMullions = (parts - 1) * mullionThickness;
      final availableWidth = zone.boundary.width - totalMullions;
      final stepX = availableWidth / parts;
      for (int i = 0; i < parts; i++) {
        double left = zone.boundary.left + (i * stepX) + (i * mullionThickness);
        double right = left + stepX;
        zones.insert(
          index + i,
          WindowZone(
            id: UniqueKey().toString(),
            boundary: Rect.fromLTRB(
              left,
              zone.boundary.top,
              right,
              zone.boundary.bottom,
            ),
            sashColor: zone.sashColor,
            content: zone.content,
            glass: zone.glass.clone(),
            openDirection: zone.openDirection,
            sashThickness: zone.sashThickness,
            isSash105: zone.isSash105,
            lockType: zone.lockType,
            hasSashPlintheBottom: zone.hasSashPlintheBottom,
          ),
        );
      }
    }
    selection = SelectionInfo.none;
    showZoneMenu = false;
    activeSubZone = null;
    updatePrimaryMullionAxis();
    notifyListeners();
  }

  void toggleDrawingMode() {
    isDrawingMode = !isDrawingMode;
    notifyListeners();
  }

  void setDrawingMode(bool value) {
    if (isDrawingMode != value) {
      isDrawingMode = value;
      notifyListeners();
    }
  }

  void toggleViewMode() {
    isInternalView = !isInternalView;
    notifyListeners();
  }

  void toggleBottomFrame(bool value) {
    if (systemMode == 'sliding') {
      hasBottomFrame = true;
      notifyListeners();
      return;
    }
    _saveSnapshot();
    hasBottomFrame = value;
    _hideBottomCoverWhenBottomFrameIsMissing();
    if (hasBottomFrame) {
      hasFramePlintheBottom = false;
      for (var z in zones) {
        z.hasSashPlintheBottom = false;
      }
    }
    if (!hasBottomFrame) {
      showBottomWall = false;
    } else {
      showBottomWall = true;
    }
    updateBottomZoneBoundaries();
    notifyListeners();
  }

  void toggleSystemOB(bool value) {
    useSystemOB = value;
    if (value) {
      useDemiOB = false;
    } else {
      if (!useDemiOB && useVerrouCentral) {
        useVerrouCentral = false;
      }
    }
    notifyListeners();
  }

  void toggleFramePlintheBottom(bool value) {
    if (hasFramePlintheBottom == value) return;
    _saveSnapshot();

    hasFramePlintheBottom = value;
    if (value) {
      hasBottomFrame = false;
      _autoSelectSash(thick: true);
    } else {
      bool anySashPlinthe = zones.any((z) => z.hasSashPlintheBottom);
      hasBottomFrame = !anySashPlinthe;
      if (!anySashPlinthe) {
        _autoSelectSash(thick: false);
      }
    }

    _hideBottomCoverWhenBottomFrameIsMissing();
    updateBottomZoneBoundaries();

    // Reset bottom zones content to fixedGlass if they contain sash
    if (value) {
      double bottomLimit = height - plintheHeight;
      for (var z in zones) {
        if ((z.boundary.bottom - bottomLimit).abs() < 5.0) {
          if (z.content == ZoneContent.singleSash ||
              z.content == ZoneContent.doubleSash ||
              z.content == ZoneContent.slidingSash) {
            z.content = ZoneContent.fixedGlass;
          }
        }
      }
    }

    notifyListeners();
  }

  void toggleSelectedZoneSashPlintheBottom() {
    final zone = selectedZone;
    if (zone == null) return;
    _saveSnapshot();

    zone.hasSashPlintheBottom = !zone.hasSashPlintheBottom;

    bool anySashPlinthe = zones.any((z) => z.hasSashPlintheBottom);
    if (anySashPlinthe) {
      hasBottomFrame = false;
      _autoSelectSash(thick: true);
    } else {
      if (!hasFramePlintheBottom) {
        hasBottomFrame = true;
        _autoSelectSash(thick: false);
      }
    }

    _hideBottomCoverWhenBottomFrameIsMissing();
    updateBottomZoneBoundaries();
    notifyListeners();
  }

  void _autoSelectSash({required bool thick}) {
    final series = (systemMode == 'sliding' && activeSlidingSeries != null)
        ? activeSlidingSeries!
        : activeSeries;
    if (series == null) return;

    final sashes = series.sections.where((sec) {
      final ty = sec.type.toLowerCase().trim();
      return ty.contains('sash') ||
          ty.contains('ouvrant') ||
          ty.contains('ضلفة') ||
          ty.contains('ساش');
    }).toList();

    if (sashes.isEmpty) return;

    AluminumSection? target;
    if (thick) {
      for (var sec in sashes) {
        final n = sec.name.toLowerCase();
        final c = sec.code.toLowerCase();
        final isThick =
            n.contains('porte') ||
            n.contains('door') ||
            n.contains('grand') ||
            n.contains('large') ||
            n.contains('عريضة') ||
            n.contains('كبيرة') ||
            n.contains('باب') ||
            n.contains('غليظة') ||
            c.contains('porte') ||
            c.contains('door') ||
            c.contains('grand') ||
            c.contains('large') ||
            c.contains('عريضة') ||
            c.contains('كبيرة') ||
            c.contains('باب') ||
            c.contains('غليظة');
        if (isThick) {
          target = sec;
          break;
        }
      }
      if (target == null && sashes.length > 1) {
        final sorted = List<AluminumSection>.from(sashes);
        sorted.sort((a, b) => b.visibleWidth.compareTo(a.visibleWidth));
        target = sorted.first;
      }
    } else {
      for (var sec in sashes) {
        final n = sec.name.toLowerCase();
        final c = sec.code.toLowerCase();
        final isThin =
            n.contains('fenetre') ||
            n.contains('window') ||
            n.contains('petit') ||
            n.contains('رقيقة') ||
            n.contains('نافذة') ||
            n.contains('صغيرة') ||
            c.contains('fenetre') ||
            c.contains('window') ||
            c.contains('petit') ||
            c.contains('رقيقة') ||
            c.contains('نافذة') ||
            c.contains('صغيرة');
        if (isThin) {
          target = sec;
          break;
        }
      }
      if (target == null && sashes.length > 1) {
        final sorted = List<AluminumSection>.from(sashes);
        sorted.sort((a, b) => a.visibleWidth.compareTo(b.visibleWidth));
        target = sorted.first;
      }
    }

    if (target == null) {
      target = sashes.first;
    }

    sashOverride = target.toMap();
    updateAllSashThicknesses();
  }

  void updateBottomZoneBoundaries() {
    double targetBottom = height;
    if (hasFramePlintheBottom) {
      targetBottom = height - plintheHeight;
    } else if (hasBottomFrame) {
      targetBottom = height - profileThickness;
    }

    for (var z in zones) {
      if ((z.boundary.bottom - height).abs() < 5.0 ||
          (z.boundary.bottom - (height - profileThickness)).abs() < 5.0 ||
          (z.boundary.bottom - (height - plintheHeight)).abs() < 5.0) {
        z.boundary = Rect.fromLTRB(
          z.boundary.left,
          z.boundary.top,
          z.boundary.right,
          targetBottom,
        );
      }
    }

    if (!hasBottomFrame) {
      for (var z in zones) {
        if (z.openDirection == OpenDirection.top ||
            z.openDirection == OpenDirection.bottom) {
          z.openDirection = OpenDirection.left;
        }
      }
    }
  }

  bool canZoneHaveSash(WindowZone zone) {
    if (!hasFramePlintheBottom) return true;
    double pHeight = 0.0;
    if (componentOverrides.containsKey('بلانت (Plinthe)')) {
      pHeight = (componentOverrides['بلانت (Plinthe)']['visible_width'] ?? 0.0)
          .toDouble();
    } else {
      final s = getSectionByType('plinthe');
      if (s != null) pHeight = s.visibleWidth;
    }
    double bottomLimit = height - pHeight;
    return (zone.boundary.bottom - bottomLimit).abs() > 5.0;
  }

  void toggleDemiOB(bool value) {
    useDemiOB = value;
    if (value) {
      useSystemOB = false;
    } else {
      if (!useSystemOB && useVerrouCentral) {
        useVerrouCentral = false;
      }
    }
    notifyListeners();
  }

  void toggleVerrouCentral(bool value) {
    useVerrouCentral = value;
    if (value) {
      if (!useSystemOB && !useDemiOB) {
        useSystemOB = true;
      }
    }
    notifyListeners();
  }

  /// Aluminium shutter windows must use the ordinary outer frame together
  /// with a standalone side cover. This also applies to existing drawings
  /// when the user enables the side-cover option after creating the shutter.
  Future<void> _selectNonIntegratedFrameForShutter() async {
    if (!hasShutter || isFramePVC) return;
    final series = activeFrameSeries ?? activeSeries;
    if (series == null) return;

    final currentFrame = activeFrameOverride;
    if (currentFrame != null &&
        !_overrideHasIntegratedSideCover(currentFrame)) {
      return;
    }

    final candidates = series.sections.where((section) {
      final type = section.type.toLowerCase();
      return (section.isFrame || type == 'frame' || type.contains('cadre')) &&
          !_sectionHasIntegratedSideCover(section);
    }).toList();
    if (candidates.isEmpty) return;

    final target = candidates.first;
    final override = target.toMap();
    final colorId = selectedDbColor?['id'];
    if (colorId != null) {
      try {
        final price = await db.getSectionPrice(target.id, colorId);
        if (price > 0 && price != 800.0) {
          override['calculated_price'] = price;
        }
      } catch (_) {
        // The drawing can use the selected section even if a temporary local
        // price lookup fails; the next catalogue refresh will restore price.
      }
    }

    if (usesSlidingPrimaryProfiles) {
      slidingFrameOverride = override;
    } else {
      frameOverride = override;
      selectedFrameCode = target.code;
    }
    updateProfileThickness();
    notifyListeners();
  }

  void toggleShutter(bool value) {
    if (value && hasArchOrSlant) return;
    if (hasShutter == value) return;
    _saveSnapshot();
    double oldTopOffset = (hasShutter && !hasArchOrSlant && !isCaissonTunnel)
        ? shutterBoxHeight
        : 0.0;
    hasShutter = value;
    double newTopOffset = (hasShutter && !hasArchOrSlant && !isCaissonTunnel)
        ? shutterBoxHeight
        : 0.0;
    if (!value) {
      removedShutterSides.clear();
      // The side-cover state is shared by shutter and ordinary frame views.
      // Clearing shutter-specific sides must not resurrect a bottom cover when
      // the bottom frame is absent.
      _hideBottomCoverWhenBottomFrameIsMissing();
      isCaissonTunnel = false;
    }
    if (zones.isNotEmpty && height > 0) {
      double oldInnerH = height - oldTopOffset - (profileThickness * 2);
      double newInnerH = height - newTopOffset - (profileThickness * 2);
      if (oldInnerH > 0 && newInnerH > 0) {
        double scaleY = newInnerH / oldInnerH;
        for (var z in zones) {
          double top =
              newTopOffset +
              profileThickness +
              (z.boundary.top - (oldTopOffset + profileThickness)) * scaleY;
          double bottom =
              newTopOffset +
              profileThickness +
              (z.boundary.bottom - (oldTopOffset + profileThickness)) * scaleY;
          z.boundary = Rect.fromLTRB(
            z.boundary.left,
            top,
            z.boundary.right,
            bottom,
          );
        }
      }
    }
    if (hasShutter) {
      updateShutterDefaultsIfNeeded();
      unawaited(_selectNonIntegratedFrameForShutter());
    }
    notifyListeners();
  }

  void setShutterPosition(double val) {
    shutterPosition = val;
    notifyListeners();
  }

  void toggleCaissonTunnel(bool value) {
    if (isCaissonTunnel == value) return;
    _saveSnapshot();
    double oldTopOffset = (hasShutter && !hasArchOrSlant && !isCaissonTunnel)
        ? shutterBoxHeight
        : 0.0;
    isCaissonTunnel = value;
    if (isCaissonTunnel) {
      shutterMechanism = 'محرك';
      showWall = true;
      componentOverrides['الصندوق (Caisson)'] = {
        'id': -999,
        'name': 'صندوق نفق (Caisson Tunnel)',
        'price': 0.0,
        'price_dzd': 0.0,
        'component_type': 'صندوق',
        'measurement': 'tunnel',
      };
    } else {
      showWall = false;
      if (componentOverrides['الصندوق (Caisson)']?['id'] == -999) {
        componentOverrides.remove('الصندوق (Caisson)');
      }
    }
    double newTopOffset = (hasShutter && !hasArchOrSlant && !isCaissonTunnel)
        ? shutterBoxHeight
        : 0.0;

    if (zones.isNotEmpty && height > 0) {
      double oldInnerH = height - oldTopOffset - (profileThickness * 2);
      double newInnerH = height - newTopOffset - (profileThickness * 2);
      if (oldInnerH > 0 && newInnerH > 0) {
        double scaleY = newInnerH / oldInnerH;
        for (var z in zones) {
          double top =
              newTopOffset +
              profileThickness +
              (z.boundary.top - (oldTopOffset + profileThickness)) * scaleY;
          double bottom =
              newTopOffset +
              profileThickness +
              (z.boundary.bottom - (oldTopOffset + profileThickness)) * scaleY;
          z.boundary = Rect.fromLTRB(
            z.boundary.left,
            top,
            z.boundary.right,
            bottom,
          );
        }
      }
    }
    notifyListeners();
  }

  void toggleBottomWall() {
    _saveSnapshot();
    showBottomWall = !showBottomWall;
    enforceBottomSideCoverConstraint();
    notifyListeners();
  }

  void toggleShowWall(bool value) {
    _saveSnapshot();
    showWall = value;
    notifyListeners();
  }

  void toggleWallColor(String value) {
    _saveSnapshot();
    wallColor = value;
    notifyListeners();
  }

  Future<void> toggleSideCovers(bool value) async {
    if (value && hasArchOrSlant) return;
    _saveSnapshot();
    hasSideCovers = value;
    if (value) {
      final covers = availableSideCovers;
      if (covers.isNotEmpty &&
          !covers.any((cover) => cover.id == selectedSideCover?.id)) {
        selectedSideCover = covers.first;
      }
    }
    // Draw the change immediately. Profile/price lookup stays asynchronous,
    // so a slow catalogue read cannot make the drawing page appear frozen.
    notifyListeners();

    // If this is an aluminium shutter window, an enabled side cover is a
    // separate profile. Do not keep an integrated-cover frame selected.
    await _selectNonIntegratedFrameForShutter();
    if (activeSeries != null && activeSeries!.sections.isNotEmpty) {
      final frames = activeSeries!.sections
          .where((s) => s.isFrame || s.type.toLowerCase() == 'frame')
          .toList();
      if (frames.isNotEmpty) {
        AluminumSection? targetFrame;
        if (value) {
          // User turned Side Covers ON: Do not switch the frame automatically.
          targetFrame = null;
        } else {
          // User turned Side Covers OFF: If current frame has integrated side covers (couvreJointWidth > 0), switch to a frame with couvreJointWidth == 0
          final currentFrame = getSectionByType('frame');
          if (currentFrame != null && currentFrame.couvreJointWidth > 0) {
            for (var f in frames) {
              if (f.couvreJointWidth == 0) {
                targetFrame = f;
                break;
              }
            }
          }
        }

        if (targetFrame != null) {
          selectedFrameCode = targetFrame.code;
          final frameMap = targetFrame.toMap();

          // Fetch calculated price for this frame
          double price = 0.0;
          if (selectedDbColor != null) {
            final db = SqlDatabase();
            try {
              price = await db.getSectionPrice(
                targetFrame.id,
                selectedDbColor!['id'],
              );
            } catch (_) {
              // Keep the frame switch responsive if the local price store is
              // temporarily busy; pricing is refreshed independently.
            }
          }
          frameMap['calculated_price'] = price;
          frameOverride = frameMap;
          updateProfileThickness();
        }
      }
    }
    notifyListeners();
  }

  void toggleInternalSlidingSideCover(bool value) {
    final zone = selectedZone;
    if (zone == null || !isSlidingZoneNestedInSingleFrame(zone)) return;
    _saveSnapshot();
    hasInternalSlidingSideCover = value;
    if (value) {
      _selectDefaultInternalSlidingSideCover();
    }
    notifyListeners();
  }

  void toggleSideCoverOrientation() {
    _saveSnapshot();
    sideCoverUseSecondWidth = !sideCoverUseSecondWidth;
    notifyListeners();
  }

  void toggleFrameType() {
    _saveSnapshot();
    isFrame140 = !isFrame140;
    updateProfileThickness();
    notifyListeners();
  }

  /// Returns an explicit 104/105 classification from catalogue metadata.
  /// A null result means that this series uses neutral names and must be
  /// classified from its visible dimensions.
  bool? _explicitSash105FromProfile(Map<String, dynamic>? profile) {
    if (profile == null) return null;
    final code = profile['code']?.toString().toLowerCase() ?? '';
    final name = profile['name']?.toString().toLowerCase() ?? '';
    final type = profile['type']?.toString().toLowerCase() ?? '';
    final description = '$code $name $type';

    if (description.contains('104') ||
        description.contains('fenetre') ||
        description.contains('window')) {
      return false;
    }
    if (description.contains('105') ||
        description.contains('porte') ||
        description.contains('door')) {
      return true;
    }
    return null;
  }

  /// Determines whether a selected sash profile is a 105/door sash.  The
  /// profile controls, the handle controls and the validator all use this
  /// same rule so that they never disagree after a profile is selected.
  bool _isSash105Profile(
    Map<String, dynamic>? profile, {
    double fallbackWidth = 0.0,
  }) {
    if (profile == null) return false;

    final explicit = _explicitSash105FromProfile(profile);
    if (explicit != null) return explicit;

    final double currentWidth =
        (profile['visible_width'] as num?)?.toDouble() ??
        (profile['thickness'] as num?)?.toDouble() ??
        fallbackWidth;
    final series = activeSeries;
    if (series != null) {
      final sashSections = series.sections.where((section) {
        final type = section.type.toLowerCase().trim();
        final name = section.name.toLowerCase().trim();
        return type.contains('sash') ||
            type.contains('ouvrant') ||
            type.contains('ضلفة') ||
            type.contains('ساش') ||
            name.contains('sash') ||
            name.contains('ouvrant') ||
            name.contains('ضلفة') ||
            name.contains('ساش');
      }).toList();

      if (sashSections.isNotEmpty) {
        final widths = sashSections
            .map((section) => section.visibleWidth)
            .where((width) => width > 0)
            .toList();
        if (widths.length > 1) {
          final maxWidth = widths.reduce(math.max);
          final minWidth = widths.reduce(math.min);
          if (maxWidth > minWidth) {
            return (currentWidth - maxWidth).abs() <
                (currentWidth - minWidth).abs();
          }
        }
      }
    }

    // Single-entry catalogues often have neither 104 nor 105 in their name.
    // This is the same practical width rule used by the renderer.
    return currentWidth > (isPVC ? 60.0 : 50.0);
  }

  bool _zoneUsesSash105(WindowZone zone) {
    if (zone.isSash105) return true;

    // A divided sash may have its own profile.  Handle state is stored on its
    // parent zone, so keep door-handle options available when such a cell is
    // thick even if the parent was created as a normal window sash.
    for (final cellProfile in zone.cellSashOverrides.values) {
      if (_isSash105Profile(cellProfile)) return true;
    }

    return _isSash105Profile(
      sashOverride,
      fallbackWidth: zone.sashThickness ?? 0.0,
    );
  }

  /// Whether the current selection effectively uses a thick/door sash.
  bool get selectedZoneUsesSash105 {
    final zone = selectedZone;
    return zone != null && _zoneUsesSash105(zone);
  }

  bool _determineIsSash105FromSashOverride() {
    return _isSash105Profile(sashOverride);
  }

  void updateAllSashThicknesses() {
    bool is105 = _determineIsSash105FromSashOverride();

    for (var z in zones) {
      if (z.content == ZoneContent.singleSash ||
          z.content == ZoneContent.doubleSash ||
          z.content == ZoneContent.slidingSash) {
        if (sashOverride != null) {
          z.isSash105 = is105;
        }
        z.sashThickness = _calculateSashThickness(z.isSash105);
      }
    }
  }

  /// Keeps the empty space between two zones equal to the profile that is
  /// actually drawn after a series switch.  Otherwise the canvas retains the
  /// old gap while the painter uses the new series' profile width, which makes
  /// TPR (and other series) mullions look clipped, too wide, or disappear.
  void _synchronizeDivisionGapsForSeries(
    double previousFrameThickness,
    double previousMullionThickness,
  ) {
    if (zones.length < 2 ||
        previousFrameThickness <= 0 ||
        profileThickness <= 0) {
      return;
    }

    final oldMullion = previousMullionThickness > 0
        ? previousMullionThickness
        : previousFrameThickness;
    final newMullion = mullionThickness > 0
        ? mullionThickness
        : profileThickness;
    _synchronizeAxisDivisionGaps(
      isVertical: true,
      oldFrameGap: previousFrameThickness * 2,
      newFrameGap: profileThickness * 2,
      oldMullionGap: oldMullion,
      newMullionGap: newMullion,
    );
    _synchronizeAxisDivisionGaps(
      isVertical: false,
      oldFrameGap: previousFrameThickness * 2,
      newFrameGap: profileThickness * 2,
      oldMullionGap: oldMullion,
      newMullionGap: newMullion,
    );
  }

  void _synchronizeAxisDivisionGaps({
    required bool isVertical,
    required double oldFrameGap,
    required double newFrameGap,
    required double oldMullionGap,
    required double newMullionGap,
  }) {
    final Map<double, double> replacements = {};

    void registerGap(double firstEdge, double secondEdge) {
      final gap = secondEdge - firstEdge;
      if (gap <= 0.0) return;

      double? targetGap;
      if (coupleFrames && (gap - oldFrameGap).abs() <= 3.0) {
        targetGap = newFrameGap;
      } else if ((gap - oldMullionGap).abs() <= 3.0) {
        targetGap = newMullionGap;
      }
      if (targetGap == null || (targetGap - gap).abs() < 0.1) return;

      final center = (firstEdge + secondEdge) / 2.0;
      replacements[firstEdge] = center - targetGap / 2.0;
      replacements[secondEdge] = center + targetGap / 2.0;
    }

    for (var i = 0; i < zones.length; i++) {
      final first = zones[i].boundary;
      for (var j = i + 1; j < zones.length; j++) {
        final second = zones[j].boundary;
        if (isVertical) {
          final overlap =
              math.min(first.bottom, second.bottom) -
              math.max(first.top, second.top);
          if (overlap <= 5.0) continue;
          if (first.right <= second.left) {
            registerGap(first.right, second.left);
          } else if (second.right <= first.left) {
            registerGap(second.right, first.left);
          }
        } else {
          final overlap =
              math.min(first.right, second.right) -
              math.max(first.left, second.left);
          if (overlap <= 5.0) continue;
          if (first.bottom <= second.top) {
            registerGap(first.bottom, second.top);
          } else if (second.bottom <= first.top) {
            registerGap(second.bottom, first.top);
          }
        }
      }
    }

    if (replacements.isEmpty) return;

    double replacementFor(double value) {
      for (final entry in replacements.entries) {
        if ((entry.key - value).abs() <= 0.5) return entry.value;
      }
      return value;
    }

    for (final zone in zones) {
      final boundary = zone.boundary;
      final left = isVertical ? replacementFor(boundary.left) : boundary.left;
      final right = isVertical
          ? replacementFor(boundary.right)
          : boundary.right;
      final top = isVertical ? boundary.top : replacementFor(boundary.top);
      final bottom = isVertical
          ? boundary.bottom
          : replacementFor(boundary.bottom);
      if (right > left + 1.0 && bottom > top + 1.0) {
        zone.boundary = Rect.fromLTRB(left, top, right, bottom);
      }
    }
  }

  void updateProfileThickness() {
    double oldThickness = profileThickness;
    final useSliding =
        usesSlidingPrimaryProfiles && activeSlidingSeries != null;
    final activeFrame = useSliding ? slidingFrameOverride : frameOverride;
    final series = useSliding ? activeSlidingSeries : activeSeries;

    if (activeFrame != null) {
      double t = (activeFrame['visible_width'] as num?)?.toDouble() ?? 0.0;
      if (t > 0) {
        profileThickness = t;
      } else {
        profileThickness =
            (activeFrame['thickness'] as num?)?.toDouble() ?? profileThickness;
      }
    } else if (series != null && series.sections.isNotEmpty) {
      final frames = series.sections
          .where((s) => s.isFrame || s.type.toLowerCase() == 'frame')
          .toList();
      if (frames.isNotEmpty) {
        AluminumSection targetFrame;
        if (!useSliding &&
            selectedFrameCode != null &&
            selectedFrameCode!.isNotEmpty) {
          targetFrame = frames.firstWhere(
            (s) => s.code == selectedFrameCode,
            orElse: () => frames.first,
          );
        } else {
          targetFrame = frames.firstWhere(
            (s) => isFrame140 ? s.code.contains('140') : s.code.contains('103'),
            orElse: () => frames.first,
          );
        }
        profileThickness = targetFrame.visibleWidth > 0
            ? targetFrame.visibleWidth
            : (targetFrame.thickness > 0 ? targetFrame.thickness : 40.0);
      } else {
        profileThickness = isFrame140 ? 70.0 : 40.0;
      }
    } else {
      profileThickness = isFrame140 ? 70.0 : 40.0;
    }

    if (oldThickness != profileThickness) {
      double topOffset = (hasShutter && !hasArchOrSlant && !isCaissonTunnel)
          ? shutterBoxHeight
          : 0.0;
      bool isSameEdge(double value, double expected) =>
          (value - expected).abs() <= 1.0;
      for (var z in zones) {
        z.boundary = Rect.fromLTRB(
          isSameEdge(z.boundary.left, oldThickness)
              ? profileThickness
              : z.boundary.left,
          isSameEdge(z.boundary.top, topOffset + oldThickness)
              ? (topOffset + profileThickness)
              : z.boundary.top,
          isSameEdge(z.boundary.right, width - oldThickness)
              ? width - profileThickness
              : z.boundary.right,
          isSameEdge(z.boundary.bottom, height - oldThickness)
              ? height - profileThickness
              : z.boundary.bottom,
        );
      }
    }
    _synchronizeSingleZoneWithOuterFrame();
  }

  void toggleShutterSide(String side) {
    _saveSnapshot();
    if (side == 'bottom' && (!hasBottomFrame || !showBottomWall)) {
      removedShutterSides.add('bottom');
      notifyListeners();
      return;
    }
    if (removedShutterSides.contains(side)) {
      removedShutterSides.remove(side);
    } else {
      removedShutterSides.add(side);
    }
    notifyListeners();
  }

  /// A bottom side cover cannot exist without its bottom frame and wall.
  void _hideBottomCoverWhenBottomFrameIsMissing() {
    enforceBottomSideCoverConstraint();
  }

  /// Normalises the bottom cover after a drawing is restored or altered.
  /// The cover is not restored automatically when the frame/wall returns;
  /// the user deliberately re-enables it from the side-cover controls.
  void enforceBottomSideCoverConstraint() {
    if (!hasBottomFrame || !showBottomWall) {
      removedShutterSides.add('bottom');
      hiddenSideCoverSegments.add('bottom');
      sideCoverSegments = sideCoverSegments
          .where((segment) => segment.side != 'bottom')
          .toList();
    }
  }

  void setSlidingSashesCount(int count) {
    if (selectedZone == null) return;
    _saveSnapshot();
    selectedZone!.slidingSashesCount = count.clamp(2, 4).toInt();
    notifyListeners();
  }

  void setSelectedZoneSlidingSashes(int count, {bool? cutSlidingGlassRebate}) {
    if (hasArchOrSlant) return;
    final zone = selectedZone;
    if (zone == null) return;
    _saveSnapshot();
    zone.content = ZoneContent.slidingSash;
    zone.slidingSashesCount = count.clamp(2, 4).toInt();
    zone.cutSlidingGlassRebate =
        cutSlidingGlassRebate ?? zone.cutSlidingGlassRebate;
    zone.sashThickness = _calculateSashThickness(zone.isSash105);
    zone.openDirection = OpenDirection.right;
    zone.innerH = 0;
    zone.innerV = 0;
    zone.rightInnerH = 0;
    zone.rightInnerV = 0;
    zone.primaryDivisionAxis = null;
    zone.rightPrimaryDivisionAxis = null;
    zone.innerHPositions = const [];
    zone.innerVPositions = const [];
    zone.rightInnerHPositions = const [];
    zone.rightInnerVPositions = const [];
    zone.cellIsPanel.clear();
    activeSubZone = null;
    showZoneMenu = false;
    updateProfileThickness();
    notifyListeners();
  }

  void toggleSelectedZoneClassicHandle() {
    if (selectedZone == null) return;
    if (isPVC) {
      selectedZone!.useClassicHandle = true;
      return;
    }
    _saveSnapshot();
    selectedZone!.useClassicHandle = !selectedZone!.useClassicHandle;
    notifyListeners();
  }

  void setSelectedZoneClassicHandle(bool value) {
    if (selectedZone == null) return;
    _saveSnapshot();
    selectedZone!.useClassicHandle = value;
    notifyListeners();
  }

  void toggleSelectedZoneOctoHandle() {
    if (selectedZone == null) return;
    _saveSnapshot();
    selectedZone!.useOctoHandle = !selectedZone!.useOctoHandle;
    notifyListeners();
  }

  void setSelectedZoneContent(ZoneContent content) {
    if (selectedZone == null) return;
    _saveSnapshot();
    selectedZone!.content = content;
    if (content != ZoneContent.doubleSash) {
      selectedZone!.doubleSashHasTwoHandles = false;
    }
    selectedZone!.innerH = 0;
    selectedZone!.innerV = 0;
    selectedZone!.rightInnerH = 0;
    selectedZone!.rightInnerV = 0;
    selectedZone!.primaryDivisionAxis = null;
    selectedZone!.rightPrimaryDivisionAxis = null;
    selectedZone!.innerHPositions = const [];
    selectedZone!.innerVPositions = const [];
    selectedZone!.rightInnerHPositions = const [];
    selectedZone!.rightInnerVPositions = const [];
    selectedZone!.cellIsPanel.clear();
    bool is105 = _determineIsSash105FromSashOverride();
    selectedZone!.isSash105 = is105;
    selectedZone!.sashThickness = _calculateSashThickness(is105);
    if (content == ZoneContent.doubleSash ||
        content == ZoneContent.singleSash ||
        content == ZoneContent.slidingSash) {
      selectedZone!.openDirection = OpenDirection.right;
      selectedZone!.useClassicHandle = isPVC;
    } else {
      selectedZone!.openDirection = null;
    }
    updateProfileThickness();
    notifyListeners();
  }

  Future<void> updateSelectedZoneGlass({
    GlassStructure? structure,
    GlassFinish? finishOuter,
    GlassFinish? finishInner,
    GlassColor? colorOuter,
    GlassColor? colorInner,
    GlassProcessing? processingOuter,
    GlassProcessing? processingInner,
    ClosedGlassColor? colorP,
    bool? hasGas,
    int? intercallThickness,
    String? panneauSubtype,
    String? panneauColor,
    bool? isVerticalBardage,
    bool? bardageUsesFrameColor,
    int? panneauProductId,
    double? thicknessOuter,
    double? thicknessInner,
    String? laminatedColorOuter,
    String? laminatedColorInner,
    bool? temperedOuter,
    bool? temperedInner,
  }) async {
    // Keep a stable target while selecting a compatible parclose performs its
    // asynchronous catalogue lookup.  The drawer may rebuild during that
    // lookup, but changing glass must never make the selected zone disappear.
    final zone = selectedZone;
    if (zone == null) return;
    final selectedZoneId = zone.id;
    _saveSnapshot();

    final targetCellKey = activeSubZone;
    final baseSpec = (targetCellKey != null && targetCellKey.isNotEmpty)
        ? zone.getGlassForCell(targetCellKey)
        : zone.glass;

    final targetStructure = structure ?? baseSpec.structure;
    double? resolvedThicknessOuter = thicknessOuter;
    double? resolvedThicknessInner = thicknessInner;

    if (targetStructure == GlassStructure.double) {
      resolvedThicknessOuter ??=
          baseSpec.thicknessOuter ??
          getThicknessForFinish(
            finishOuter ?? baseSpec.finishOuter,
            colorOuter ?? baseSpec.colorOuter,
          );
      resolvedThicknessInner ??=
          baseSpec.thicknessInner ??
          getThicknessForFinish(
            finishInner ?? baseSpec.finishInner,
            colorInner ?? baseSpec.colorInner,
          );
    } else {
      resolvedThicknessOuter ??=
          baseSpec.thicknessOuter ??
          getThicknessForFinish(
            finishOuter ?? baseSpec.finishOuter,
            colorOuter ?? baseSpec.colorOuter,
          );
    }

    // The pane selection controls the parclose and normally suggests an
    // Intercall. A spacer explicitly chosen by the user is preserved and is
    // shown with a compatibility warning in the drawing drawer.
    final parcloseChanged = await _ensureParcloseForGlass(
      structure: targetStructure,
      paneThickness: targetStructure == GlassStructure.double
          ? (resolvedThicknessOuter ?? 4.0) + (resolvedThicknessInner ?? 4.0)
          : resolvedThicknessOuter ?? 0.0,
    );
    if (parcloseChanged) {
      // A parclose is shared by the entire drawing. Keep every existing
      // double-glazing cell synchronized when its automatic selection changes.
      fitDoubleGlassIntercallsToSelectedParclose();
    }

    // Gas is part of the usual double-glazing pack. It starts enabled when
    // the user changes a cell to double glass, while an explicit switch-off
    // remains untouched on later edits.
    final resolvedHasGas =
        hasGas ??
        (structure == GlassStructure.double &&
                baseSpec.structure != GlassStructure.double
            ? true
            : null);
    int? resolvedIntercallThickness = intercallThickness;
    if (targetStructure == GlassStructure.double &&
        intercallThickness == null) {
      final suggested = suggestedIntercallThicknessForDoubleGlass(
        thicknessOuter: resolvedThicknessOuter ?? 4.0,
        thicknessInner: resolvedThicknessInner ?? 4.0,
      );
      if (suggested != null) {
        resolvedIntercallThickness = suggested;
      }
    }

    // Baguettes and rosettes exist only inside a double-glazing unit. Clear
    // their active drawing data as soon as this pane becomes simple or a
    // panel, so an old decoration can never remain in the cost table.
    final bool clearGlassDecor = targetStructure != GlassStructure.double;

    if (targetCellKey != null && targetCellKey.isNotEmpty) {
      final GlassSpecification updatedSpec = baseSpec.copyWith(
        structure: structure,
        finishOuter: finishOuter,
        finishInner: finishInner,
        colorOuter: colorOuter,
        colorInner: colorInner,
        processingOuter: processingOuter,
        processingInner: processingInner,
        temperedOuter: temperedOuter,
        temperedInner: temperedInner,
        colorP: colorP,
        hasGas: resolvedHasGas,
        intercallThickness: resolvedIntercallThickness,
        panneauSubtype: panneauSubtype,
        panneauColor: panneauColor,
        isVerticalBardage: isVerticalBardage,
        bardageUsesFrameColor: bardageUsesFrameColor,
        panneauProductId: panneauProductId,
        thicknessOuter: resolvedThicknessOuter,
        thicknessInner: resolvedThicknessInner,
        laminatedColorOuter: laminatedColorOuter,
        laminatedColorInner: laminatedColorInner,
        decorH: clearGlassDecor ? 0 : null,
        decorV: clearGlassDecor ? 0 : null,
        decorHPositions: clearGlassDecor ? const [] : null,
        decorVPositions: clearGlassDecor ? const [] : null,
        hasRosettes: clearGlassDecor ? false : null,
      );
      final updatedCellGlass = Map<String, GlassSpecification>.from(
        zone.cellGlassSpec,
      );
      updatedCellGlass[targetCellKey] = updatedSpec;
      zone.cellGlassSpec = updatedCellGlass;
    } else {
      zone.glass = zone.glass.copyWith(
        structure: structure,
        finishOuter: finishOuter,
        finishInner: finishInner,
        colorOuter: colorOuter,
        colorInner: colorInner,
        processingOuter: processingOuter,
        processingInner: processingInner,
        temperedOuter: temperedOuter,
        temperedInner: temperedInner,
        colorP: colorP,
        hasGas: resolvedHasGas,
        intercallThickness: resolvedIntercallThickness,
        panneauSubtype: panneauSubtype,
        panneauColor: panneauColor,
        isVerticalBardage: isVerticalBardage,
        bardageUsesFrameColor: bardageUsesFrameColor,
        panneauProductId: panneauProductId,
        thicknessOuter: resolvedThicknessOuter,
        thicknessInner: resolvedThicknessInner,
        laminatedColorOuter: laminatedColorOuter,
        laminatedColorInner: laminatedColorInner,
        decorH: clearGlassDecor ? 0 : null,
        decorV: clearGlassDecor ? 0 : null,
        decorHPositions: clearGlassDecor ? const [] : null,
        decorVPositions: clearGlassDecor ? const [] : null,
        hasRosettes: clearGlassDecor ? false : null,
      );
      if (zone.cellGlassSpec.isNotEmpty) {
        final updatedCellGlass = <String, GlassSpecification>{};
        zone.cellGlassSpec.forEach((key, val) {
          updatedCellGlass[key] = val.copyWith(
            structure: structure,
            finishOuter: finishOuter,
            finishInner: finishInner,
            colorOuter: colorOuter,
            colorInner: colorInner,
            processingOuter: processingOuter,
            processingInner: processingInner,
            temperedOuter: temperedOuter,
            temperedInner: temperedInner,
            colorP: colorP,
            hasGas: resolvedHasGas,
            intercallThickness: resolvedIntercallThickness,
            panneauSubtype: panneauSubtype,
            panneauColor: panneauColor,
            isVerticalBardage: isVerticalBardage,
            bardageUsesFrameColor: bardageUsesFrameColor,
            panneauProductId: panneauProductId,
            thicknessOuter: resolvedThicknessOuter,
            thicknessInner: resolvedThicknessInner,
            laminatedColorOuter: laminatedColorOuter,
            laminatedColorInner: laminatedColorInner,
            decorH: clearGlassDecor ? 0 : null,
            decorV: clearGlassDecor ? 0 : null,
            decorHPositions: clearGlassDecor ? const [] : null,
            decorVPositions: clearGlassDecor ? const [] : null,
            hasRosettes: clearGlassDecor ? false : null,
          );
        });
        zone.cellGlassSpec = updatedCellGlass;
      }
      WindowZone.globalDefaultGlass = zone.glass;
    }
    await updateGlassGasket();
    if (zones.any((candidate) => candidate.id == selectedZoneId)) {
      selection = SelectionInfo.zone(selectedZoneId);
      activeSubZone = targetCellKey;
    }
    notifyListeners();
  }

  Future<void> updateGlassGasket() async {
    if (isPVC) {
      componentOverrides.remove('جوان الزجاج (Joint Vitrage)');
      notifyListeners();
      return;
    }

    final parclose = componentOverrides['باكيت الزجاج (Parclose)'];

    // Find active sash profile based on the system mode
    Map<String, dynamic>? activeSashMap;
    if (systemMode == 'sliding') {
      activeSashMap = slidingSashOverride;
      if (activeSashMap == null && activeSlidingSeries != null) {
        try {
          final defaultSash = activeSlidingSeries!.sections.firstWhere(
            (s) => s.isSash || s.type.toLowerCase().contains('sash'),
          );
          activeSashMap = defaultSash.toMap();
        } catch (_) {}
      }
    } else {
      activeSashMap = sashOverride;
      if (activeSashMap == null && activeSeries != null) {
        try {
          final defaultSash = activeSeries!.sections.firstWhere(
            (s) => s.isSash || s.type.toLowerCase().contains('sash'),
          );
          activeSashMap = defaultSash.toMap();
        } catch (_) {}
      }
    }

    double maxGlass = 0.0;
    if (parclose != null) {
      maxGlass = (parclose['max_glass_thickness'] as num?)?.toDouble() ?? 0.0;
    } else if (activeSashMap != null) {
      maxGlass =
          (activeSashMap['max_glass_thickness'] as num?)?.toDouble() ?? 0.0;
    }

    if (maxGlass <= 0) {
      componentOverrides.remove('جوان الزجاج (Joint Vitrage)');
      notifyListeners();
      return;
    }

    if (zones.isEmpty) return;

    // Find the first zone that has glass content
    final glassZone = zones.firstWhere(
      (z) =>
          z.content == ZoneContent.fixedGlass ||
          z.content == ZoneContent.singleSash ||
          z.content == ZoneContent.doubleSash ||
          z.content == ZoneContent.slidingSash,
      orElse: () => zones.first,
    );
    final glassThickness = glassZone.glass.totalThickness(allGlassCache);
    if (glassThickness <= 0) {
      componentOverrides.remove('جوان الزجاج (Joint Vitrage)');
      notifyListeners();
      return;
    }

    final double gap = maxGlass - glassThickness;
    if (gap <= 0) {
      componentOverrides.remove('جوان الزجاج (Joint Vitrage)');
      notifyListeners();
      return;
    }

    final double targetThickness =
        gap; // Gap is exactly the joint thickness needed!

    final dbInstance = SqlDatabase();
    final joints = await dbInstance.readJoints();
    if (joints.isNotEmpty) {
      Map<String, dynamic>? bestJoint;
      double minDiff = 999.0;
      for (var j in joints) {
        final double t = (j['thickness'] as num?)?.toDouble() ?? 0.0;
        final double diff = (t - targetThickness).abs();
        if (diff < minDiff) {
          minDiff = diff;
          bestJoint = j;
        }
      }
      if (bestJoint != null && minDiff <= 1.0) {
        componentOverrides['جوان الزجاج (Joint Vitrage)'] =
            Map<String, dynamic>.from(bestJoint);
      } else {
        componentOverrides.remove('جوان الزجاج (Joint Vitrage)');
      }
    } else {
      componentOverrides.remove('جوان الزجاج (Joint Vitrage)');
    }
    notifyListeners();
  }

  /// These profiles are specific to a sliding series.  Keeping them after a
  /// series change makes the BOM show sections and prices from the old series.
  void _clearSlidingProfileOverrides() {
    const keys = [
      'الظلفة المنزلقة (Sliding Sash)',
      'سكة الظلفة (Sash Traverse)',
      'عرضي (Traverse)',
      'قائم جانبي (Sash Lateral)',
      'قائم جانبي معزز (Sash Lateral Renforcé)',
      'قائم جانبي (Lateral)',
      'قائم وسطي (Sash Central)',
      'قائم وسطي معزز (Sash Central Renforcé)',
      'قائم وسطي (Central)',
      'الشيكان (Chicane)',
      'الري (Rail)',
    ];
    for (final key in keys) {
      componentOverrides.remove(key);
    }
  }

  void _clearAccessoryOverrides() {
    componentOverrides.remove('المقبض (Handle)');
    componentOverrides.remove('مقبض نافذة (Poignée Fenêtre)');
    componentOverrides.remove('كومباس (Compas)');
    componentOverrides.remove('عجلات المنزلق (Roulettes)');
    componentOverrides.remove('اسبانيولات المنزلق (Espagnolette)');
    componentOverrides.remove('إسبانيوليت (Espagnolette)');
    componentOverrides.remove('المفاصل (Hinges)');
    componentOverrides.remove('الفيرو (Verrou)');
    componentOverrides.remove('كاش كوليسون (Gache coulissant)');
    componentOverrides.remove('Gâche coulissant TPR');
    componentOverrides.remove('قاش بورت (Gache Porte)');
    componentOverrides.remove('مقبض الباب (Poignée Porte à Clé)');
    componentOverrides.remove('الأسطوانة (Canon)');
    componentOverrides.remove('قفل الباب (Serrure)');
    componentOverrides.remove('كريمون (Cremone)');
    componentOverrides.remove('بوشون بارك لوز (Bouchon Parclose)');
    componentOverrides.remove('أونتروماتيك (Entrematique)');
    componentOverrides.remove('كيت 67000 (Kit 67000)');
    componentOverrides.remove('كيت 76000 (Kit 76000)');
    componentOverrides.remove('كيت 40000 (Kit 40000)');
    componentOverrides.remove('قاش (Gache)');
    componentOverrides.remove('جوان بروس للظلفة (Joint Brosse Sash)');
    componentOverrides.remove('جوان بروس للستار (Joint Brosse Shutter)');
    componentOverrides.remove('الطاسو (Tasso)');
    componentOverrides.remove('جوان الزجاج (Joint Vitrage)');
  }

  /// فلترة الإكسسوارات حسب السلسلة الحالية.
  /// تحذف أي إكسسوار غير مربوط صراحةً بالسلسلة ولا تمس البروفيلات أو الستار.
  Future<void> _filterComponentsByActiveSeries(
    AluminumSeries series,
    dynamic db,
  ) async {
    if (db == null || activeSeries == null) return;

    final seriesId = series.id;
    final keysToCheck = List<String>.from(componentOverrides.keys);

    for (final key in keysToCheck) {
      final component = componentOverrides[key];
      if (component == null) continue;

      // تجاهل المكونات التي تأتي من البيانات المحلية وليست من قاعدة البيانات
      if (component['id'] == null) continue;

      // تجاهل الأقسام، مكونات الستار، والجوانات. الحقول المتشابهة بين الجداول
      // كانت تجعل القسم يُفحص خطأً داخل Accessories ثم يُحذف.
      final isSection = component.containsKey('code');
      final isShutter = component.containsKey('component_type');
      final isJoint = component.containsKey('gasket_type');
      final isAccessory =
          component.containsKey('material_type') ||
          component.containsKey('screw_count');
      final tableToCheck = isAccessory && !isSection && !isShutter && !isJoint
          ? 'Accessories'
          : null;

      if (tableToCheck != null) {
        try {
          // البحث عن المكون في قاعدة البيانات
          final result = await db.query(
            tableToCheck,
            where: 'id = ?',
            whereArgs: [component['id']],
            limit: 1,
          );

          if (result.isEmpty) {
            componentOverrides.remove(key);
            continue;
          }

          final dbComponent = result.first;
          final componentSeriesId = dbComponent['series_id'];
          final componentSeriesIds =
              dbComponent['series_ids']?.toString() ?? '';
          final materialType = (dbComponent['material_type'] ?? '')
              .toString()
              .trim()
              .toLowerCase();
          final seriesIsPvc = _isPvcSeries(series);
          final materialMatches = seriesIsPvc
              ? (materialType == 'pvc' || materialType == 'both')
              : (materialType == 'aluminium' ||
                    materialType == 'aluminum' ||
                    materialType == 'both' ||
                    materialType.isEmpty);

          // المكوّن المخصص يحتاج سلسلة مطابقة. المكوّن العام مسموح فقط
          // بعد اجتياز فلتر المادة (PVC / Aluminium / Both).
          bool belongsToCurrentSeries = false;

          // إذا كان series_id متطابقاً
          if (componentSeriesId == seriesId) {
            belongsToCurrentSeries = true;
          }
          // أو إذا كان series_ids يحتوي على series_id الحالي
          else if (componentSeriesIds.isNotEmpty) {
            final ids = componentSeriesIds
                .split(',')
                .map((s) => s.trim())
                .where((s) => s.isNotEmpty)
                .toList();
            if (ids.contains(seriesId.toString())) {
              belongsToCurrentSeries = true;
            }
          }
          // الإكسسوار العام بلا أي ربط سلسلة متاح لكل سلسلة متوافقة بالمادة.
          else if ((componentSeriesId == null || componentSeriesId == 0) &&
              componentSeriesIds.trim().isEmpty) {
            belongsToCurrentSeries = materialMatches;
          }

          if (!materialMatches || !belongsToCurrentSeries) {
            componentOverrides.remove(key);
          }
        } catch (e) {
          // في حالة الخطأ، نحتفظ بالمكون
          print('Error filtering component $key: $e');
        }
      }
    }
  }

  Future<void> _loadAccessoryDefaults(dynamic d, int seriesId) async {
    final matType = isPVC ? 'PVC' : 'Aluminium';

    String sName = '';
    try {
      final List<Map<String, dynamic>> seriesRes = await d.query(
        'Series',
        columns: ['name'],
        where: 'id = ?',
        whereArgs: [seriesId],
      );
      if (seriesRes.isNotEmpty) {
        sName = (seriesRes.first['name'] ?? '').toString().toLowerCase();
      }
    } catch (e) {
      sName = (activeSlidingSeries?.name ?? activeSeries?.name ?? '')
          .toLowerCase();
    }
    final bool isTPRSeries =
        sName.contains('tpr') ||
        sName.contains('tpi') ||
        sName.contains('67000');

    double readPrice(dynamic value) {
      final price = value is num
          ? value.toDouble()
          : double.tryParse(value?.toString() ?? '') ?? 0.0;
      return price.isFinite && price >= 0 ? price : 0.0;
    }

    // An accessory either uses its raw/base price or a color-price list.
    // Once color prices exist, only the selected color is valid: there must
    // be no fallback to the base price or to another color's price.
    Future<double> resolveAccessoryPrice(Map<String, dynamic> accessory) async {
      final accessoryId = accessory['id'];
      if (accessoryId == null) return 0.0;

      try {
        final colorPrices = await d.query(
          'AccessoryColorPrices',
          columns: ['color_id', 'price'],
          where: 'accessory_id = ?',
          whereArgs: [accessoryId],
        );
        if (colorPrices.isEmpty) {
          return readPrice(accessory['price_dzd'] ?? accessory['price']);
        }

        final selectedColorId =
            selectedAccessoryColor?['id'] ?? selectedDbColor?['id'];
        if (selectedColorId == null) return 0.0;
        for (final colorPrice in colorPrices) {
          if (colorPrice['color_id']?.toString() ==
              selectedColorId.toString()) {
            return readPrice(colorPrice['price']);
          }
        }
        return 0.0;
      } catch (_) {
        // Preserve the base price only for legacy databases where the
        // color-price table is not available yet.
        return readPrice(accessory['price_dzd'] ?? accessory['price']);
      }
    }

    Future<void> loadAccessory(String key, List<String> searchPatterns) async {
      if (componentOverrides.containsKey(key)) return;

      bool isAccessoryValid(Map<String, dynamic> acc) {
        final n = acc['name'].toString().toLowerCase();
        final ty = (acc['type'] ?? '').toString().toLowerCase();

        // 1. Material Exclusions
        if (matType == 'PVC') {
          if (n.contains('aluminium') ||
              n.contains('aluminum') ||
              n.contains('alu') ||
              n.contains('ألمنيوم') ||
              ty.contains('aluminium') ||
              ty.contains('aluminum') ||
              ty.contains('alu') ||
              ty.contains('ألمنيوم')) {
            return false;
          }
        } else {
          // Aluminium
          if (n.contains('pvc') ||
              ty.contains('pvc') ||
              n.contains('clan') ||
              ty.contains('clan') ||
              n.contains('clane') ||
              ty.contains('clane') ||
              n.contains('كلان') ||
              ty.contains('كلان')) {
            return false;
          }
        }

        // 2. Series Name Exclusions
        if (sName.isNotEmpty) {
          if (sName.contains('67000') || sName.contains('67')) {
            if (n.contains('76000') ||
                n.contains('76') ||
                ty.contains('76000') ||
                ty.contains('76') ||
                n.contains('60000') ||
                n.contains('60') ||
                ty.contains('60000') ||
                ty.contains('60') ||
                n.contains('52000') ||
                n.contains('52') ||
                ty.contains('52000') ||
                ty.contains('52') ||
                n.contains('45000') ||
                n.contains('45') ||
                ty.contains('45000') ||
                ty.contains('45')) {
              return false;
            }
          } else if (sName.contains('76000') || sName.contains('76')) {
            if (n.contains('67000') ||
                n.contains('67') ||
                ty.contains('67000') ||
                ty.contains('67') ||
                n.contains('60000') ||
                n.contains('60') ||
                ty.contains('60000') ||
                ty.contains('60') ||
                n.contains('52000') ||
                n.contains('52') ||
                ty.contains('52000') ||
                ty.contains('52') ||
                n.contains('45000') ||
                n.contains('45') ||
                ty.contains('45000') ||
                ty.contains('45')) {
              return false;
            }
          } else if (sName.contains('60000') || sName.contains('60')) {
            if (n.contains('67000') ||
                n.contains('67') ||
                ty.contains('67000') ||
                ty.contains('67') ||
                n.contains('76000') ||
                n.contains('76') ||
                ty.contains('76000') ||
                ty.contains('76') ||
                n.contains('52000') ||
                n.contains('52') ||
                ty.contains('52000') ||
                ty.contains('52') ||
                n.contains('45000') ||
                n.contains('45') ||
                ty.contains('45000') ||
                ty.contains('45')) {
              return false;
            }
          }

          // 3. System Mode Exclusions
          final isSliding = systemMode == 'sliding';
          if (isSliding) {
            if (n.contains('paumelle') ||
                ty.contains('paumelle') ||
                n.contains('mifsal') ||
                ty.contains('mifsal') ||
                n.contains('مفاصل') ||
                ty.contains('مفاصل') ||
                n.contains('مفصل') ||
                ty.contains('مفصل') ||
                n.contains('system ob') ||
                ty.contains('system ob') ||
                n.contains('demi system ob') ||
                ty.contains('demi system ob') ||
                n.contains('verrou central') ||
                ty.contains('verrou central') ||
                n.contains('gache simple') ||
                ty.contains('gache simple') ||
                n.contains('gache double') ||
                ty.contains('gache double') ||
                n.contains('قاش دوبل') ||
                ty.contains('قاش دوبل') ||
                n.contains('قاش سامبل') ||
                ty.contains('قاش سامبل') ||
                n.contains('فتح') ||
                ty.contains('فتح') ||
                n.contains('ouvrant') ||
                ty.contains('ouvrant')) {
              return false;
            }
          } else {
            if (n.contains('couliss') ||
                ty.contains('couliss') ||
                n.contains('roulette') ||
                ty.contains('roulette') ||
                n.contains('عجلات') ||
                ty.contains('عجلات') ||
                n.contains('منزلق') ||
                ty.contains('منزلق')) {
              return false;
            }
          }
        }

        // 4. Kit Clamp/Clan Exclusions (Exclude clamp from kit matching, and vice versa)
        final isKitKey =
            key.toLowerCase().contains('kit') || key.contains('كيت');
        final isClampKey =
            key.toLowerCase().contains('clamp') ||
            key.toLowerCase().contains('clam') ||
            key.contains('كلامب') ||
            key.contains('كلام') ||
            key.contains('كلان');

        final hasKitName =
            n.contains('kit') ||
            ty.contains('kit') ||
            n.contains('كيت') ||
            ty.contains('كيت');
        final hasClampName =
            n.contains('clamp') ||
            n.contains('clam') ||
            ty.contains('clamp') ||
            ty.contains('clam') ||
            n.contains('كلامب') ||
            n.contains('كلام') ||
            n.contains('كلان') ||
            ty.contains('كلامب') ||
            ty.contains('كلام') ||
            ty.contains('كلان') ||
            n.contains('clan') ||
            ty.contains('clan');

        if (isKitKey && hasClampName) return false;
        if (isClampKey && hasKitName) return false;

        // المقابض العادية للنوافذ لا تقبل مقابض الأبواب أو المقابض الخاصة.
        // الفلتر النصي العام كان يلتقط Rotax وCalimaster رغم عدم صلاحيتهما
        // لنافذة PVC عادية.
        final isWindowHandleKey =
            key == 'المقبض (Handle)' || key == 'مقبض نافذة (Poignée Fenêtre)';
        if (isWindowHandleKey) {
          final category = ty.split('|').first.trim();
          final isExplicitWindowHandle =
              category.contains('poignée fenêtre') ||
              category.contains('poignee fenetre') ||
              category.contains('window handle') ||
              category.contains('مقبض نافذة');
          if (isExplicitWindowHandle) return true;

          final isExplicitDoorHandle =
              category.contains('poignée porte') ||
              category.contains('poignee porte') ||
              category.contains('door handle') ||
              category.contains('مقبض باب') ||
              category.contains('condamnation');
          if (isExplicitDoorHandle) return false;

          final hasHandle =
              n.contains('poignée') ||
              ty.contains('poignée') ||
              n.contains('poignee') ||
              ty.contains('poignee') ||
              n.contains('handle') ||
              ty.contains('handle') ||
              n.contains('مقبض') ||
              ty.contains('مقبض');
          final isDoorOrSpecial =
              n.contains('porte') ||
              ty.contains('porte') ||
              n.contains('door') ||
              ty.contains('door') ||
              n.contains('clé') ||
              ty.contains('clé') ||
              n.contains('clef') ||
              ty.contains('clef') ||
              n.contains('condamnation') ||
              ty.contains('condamnation') ||
              n.contains('rotax') ||
              ty.contains('rotax') ||
              n.contains('calimaster') ||
              ty.contains('calimaster') ||
              n.contains('maréchal') ||
              ty.contains('maréchal') ||
              n.contains('marechal') ||
              ty.contains('marechal');
          if (!hasHandle || isDoorOrSpecial) return false;
        }

        return true;
      }

      String kitClampExclude = '';
      if (key.toLowerCase().contains('kit') || key.contains('كيت')) {
        kitClampExclude =
            " AND (LOWER(name) NOT LIKE '%clamp%' AND LOWER(name) NOT LIKE '%clam%' AND LOWER(name) NOT LIKE '%clomp%' AND LOWER(name) NOT LIKE '%clom%' AND name NOT LIKE '%كلامب%' AND name NOT LIKE '%كلام%' AND name NOT LIKE '%كلان%' AND LOWER(type) NOT LIKE '%clamp%' AND LOWER(type) NOT LIKE '%clam%' AND LOWER(type) NOT LIKE '%clomp%' AND LOWER(type) NOT LIKE '%clom%' AND type NOT LIKE '%كلامب%' AND type NOT LIKE '%كلام%' AND type NOT LIKE '%كلان%')";
      } else if (key.toLowerCase().contains('clamp') ||
          key.toLowerCase().contains('clam') ||
          key.contains('كلامب') ||
          key.contains('كلام') ||
          key.contains('كلان')) {
        kitClampExclude =
            " AND (LOWER(name) NOT LIKE '%kit%' AND name NOT LIKE '%كيت%' AND LOWER(type) NOT LIKE '%kit%' AND type NOT LIKE '%كيت%')";
      }

      String? exactTypeOverride;
      if (isTPRSeries) {
        if (key == 'المقبض (Handle)' || key == 'مقبض نافذة (Poignée Fenêtre)') {
          exactTypeOverride = 'Poignée TPR';
        } else if (key == 'إسبانيوليت (Espagnolette)' ||
            key == 'اسبانيولات المنزلق (Espagnolette)') {
          exactTypeOverride = 'Espagnolette TPR';
        }
      }

      // فلتر نوع المادة متطابق تماماً مع ProfileSelectorDialog
      String matFilter = '';
      if (matType == 'PVC') {
        matFilter =
            " AND (LOWER(material_type) = 'pvc' OR LOWER(material_type) = 'both')";
      } else {
        matFilter =
            " AND (LOWER(material_type) = 'aluminium' OR LOWER(material_type) = 'aluminum' OR LOWER(material_type) = 'both' OR material_type IS NULL OR material_type = '')$kitClampExclude";
      }

      // فلتر السلاسل متطابق تماماً مع ProfileSelectorDialog
      String seriesFilter =
          ' AND ('
          'series_id = ? '
          'OR (series_ids IS NOT NULL AND TRIM(series_ids) != \'\' AND \',\' || REPLACE(series_ids, \' \', \'\') || \',\' LIKE ?)'
          'OR ((series_id IS NULL OR series_id = 0) AND (series_ids IS NULL OR TRIM(series_ids) = \'\'))'
          ')';

      final String orderBy =
          'CASE WHEN series_id = $seriesId OR (series_ids IS NOT NULL AND TRIM(series_ids) != \'\' AND \',\' || REPLACE(series_ids, \' \', \'\') || \',\' LIKE \'%,$seriesId,%\') THEN 0 ELSE 1 END ASC, id ASC';

      List<Map<String, dynamic>> res = [];

      // 1. إذا كانت السلسلة TPR، جرب البحث المرن عن TPR أولاً لضمان انتقاء إكسسوار TPR الصحيح
      List<String> tprPatterns = [];
      if (isTPRSeries) {
        if (key == 'إسبانيوليت (Espagnolette)' ||
            key == 'اسبانيولات المنزلق (Espagnolette)') {
          tprPatterns = [
            '%tpr%espagnolette%',
            '%espagnolette%tpr%',
            '%tpr%سبانيوليت%',
            '%سبانيوليت%tpr%',
            '%tpr%إسبانيوليت%',
            '%إسبانيوليت%tpr%',
          ];
        } else if (key == 'المقبض (Handle)' ||
            key == 'مقبض نافذة (Poignée Fenêtre)') {
          tprPatterns = [
            '%tpr%poign%',
            '%poign%tpr%',
            '%tpr%مقبض%',
            '%مقبض%tpr%',
            '%tpr%handle%',
            '%handle%tpr%',
          ];
        }
      }

      if (tprPatterns.isNotEmpty) {
        String tprClause = tprPatterns
            .map((_) => 'name LIKE ? OR type LIKE ?')
            .join(' OR ');
        String tprWhereClause = '($tprClause) $seriesFilter $matFilter';
        List<dynamic> tprArgs = [];
        for (var pattern in tprPatterns) {
          tprArgs.addAll([pattern, pattern]);
        }
        tprArgs.addAll([seriesId, '%,' + seriesId.toString() + ',%']);
        final rawRows = await d.query(
          'Accessories',
          where: tprWhereClause,
          whereArgs: tprArgs,
          orderBy: orderBy,
        );
        res = rawRows.where(isAccessoryValid).toList();
      }

      // 2. إذا لم يكن TPR أو لم نجد نتيجة بالبحث المرن الخاص بـ TPR، نجري الاستعلام المعتاد
      if (res.isEmpty) {
        String nameClause = exactTypeOverride != null
            ? 'LOWER(type) = ?'
            : searchPatterns
                  .map((_) => 'name LIKE ? OR type LIKE ?')
                  .join(' OR ');

        String whereClause = '($nameClause) $seriesFilter $matFilter';
        List<dynamic> args = [];
        if (exactTypeOverride != null) {
          args.add(exactTypeOverride.toLowerCase());
        } else {
          for (var pattern in searchPatterns) {
            args.addAll([pattern, pattern]);
          }
        }
        args.addAll([seriesId, '%,' + seriesId.toString() + ',%']);

        final rawRows = await d.query(
          'Accessories',
          where: whereClause,
          whereArgs: args,
          orderBy: orderBy,
        );
        res = rawRows.where(isAccessoryValid).toList();

        // Fallback: If exact type search for TPR returned empty, retry with loose patterns
        if (res.isEmpty && exactTypeOverride != null) {
          String nameClauseLoose = searchPatterns
              .map((_) => 'name LIKE ? OR type LIKE ?')
              .join(' OR ');
          String fallbackWhereClause =
              '($nameClauseLoose) $seriesFilter $matFilter';
          List<dynamic> fallbackArgs = [];
          for (var pattern in searchPatterns) {
            fallbackArgs.addAll([pattern, pattern]);
          }
          fallbackArgs.addAll([seriesId, '%,' + seriesId.toString() + ',%']);

          final rawFallbackRows = await d.query(
            'Accessories',
            where: fallbackWhereClause,
            whereArgs: fallbackArgs,
            orderBy: orderBy,
          );
          res = rawFallbackRows.where(isAccessoryValid).toList();
        }
      }

      if (res.isNotEmpty) {
        Map<String, dynamic> selected = res.first;
        if (key == 'إسبانيوليت (Espagnolette)' ||
            key == 'اسبانيولات المنزلق (Espagnolette)') {
          // اختَر أطول إسبانيوليت لا تتجاوز الطول المطلوب، لا أول نتيجة في
          // الجدول. هذا هو نفس قانون نافذة «تغيير».
          final heightCm = height / 10.0;
          final targetHeight = hasShutter ? heightCm - 35.0 : heightCm - 20.0;
          final requiredLength = targetHeight >= 180
              ? 180.0
              : targetHeight >= 140
              ? 140.0
              : targetHeight >= 100
              ? 100.0
              : targetHeight >= 60
              ? 60.0
              : 30.0;
          double? getLength(Map<String, dynamic> accessory) {
            final measurement = (accessory['measurement'] ?? '').toString();
            final source = measurement.isNotEmpty
                ? measurement
                : '${accessory['name'] ?? ''} ${accessory['type'] ?? ''}';
            final match = RegExp(r'(\d+(?:[.,]\d+)?)').firstMatch(source);
            return match == null
                ? null
                : double.tryParse(match.group(1)!.replaceAll(',', '.'));
          }

          final compatible = res.where((accessory) {
            final length = getLength(accessory);
            return length != null && length <= requiredLength;
          }).toList()..sort((a, b) => getLength(b)!.compareTo(getLength(a)!));
          if (compatible.isNotEmpty) selected = compatible.first;
        }
        final m = Map<String, dynamic>.from(selected);
        m['calculated_price'] = await resolveAccessoryPrice(m);
        componentOverrides[key] = m;
      }
    }

    // Load defaults
    await loadAccessory('قاش دوبل (Gache Double Ouvrant)', [
      '%قاش دوبل%',
      '%gache double%',
    ]);
    await loadAccessory('إسبانيوليت (Espagnolette)', [
      '%سبانيوليت%',
      '%espagnolette%',
    ]);
    await loadAccessory('المفاصل (Hinges)', ['%مفاصل%', '%paumelle%']);
    await loadAccessory('الفيرو (Verrou)', [
      '%فيرو%',
      '%verrou%',
      '%verro%',
      '%viro%',
    ]);
    await loadAccessory('المقبض (Handle)', [
      '%مقبض%',
      '%poignée fenêtre%',
      '%poignée fenetre%',
      '%poignee fenetre%',
      '%handle%',
    ]);
    await loadAccessory('مقبض نافذة (Poignée Fenêtre)', [
      '%مقبض%',
      '%poignée fenêtre%',
      '%poignée fenetre%',
      '%poignee fenetre%',
      '%handle%',
    ]);
    await loadAccessory('مقبض أوكتو (Octo)', ['%أوكتو%', '%اوكتو%', '%octo%']);
    await loadAccessory('مقبض نافذة بي في سي (Poignée Fenêtre PVC)', [
      '%مقبض نافذة بي في سي%',
      '%poignée fenêtre pvc%',
      '%poignee fenetre pvc%',
    ]);
    await loadAccessory('كومباس (Compas)', ['%كومباس%', '%compas%']);
    await loadAccessory('عجلات المنزلق (Roulettes)', ['%رول%', '%roulette%']);
    await loadAccessory('اسبانيولات المنزلق (Espagnolette)', [
      '%اسبانيوليت%',
      '%espagnolette%',
    ]);
    await loadAccessory('كاش كوليسون (Gache coulissant)', [
      '%كاش كوليسون%',
      '%كاش كوليس%',
      '%cache coulisson%',
      '%cache coulisse%',
      '%gâche coulisse%',
      '%gache coulisse%',
      '%gâche coulissante%',
      '%gache coulissante%',
    ]);
    await loadAccessory('قاش بورت (Gache Porte)', [
      '%كاش بورت%',
      '%cache porte%',
      '%gâche porte%',
      '%gache porte%',
    ]);
    await loadAccessory('مقبض الباب (Poignée Porte à Clé)', [
      '%مقبض بمفتاح%',
      '%مقبض باب%',
      '%handle key%',
      '%handle porte%',
      '%poignée porte%',
      '%poignee porte%',
      '%poignée de porte%',
      '%poignee de porte%',
    ]);
    await loadAccessory('مقبض الباب عادي (Poignée Porte)', [
      '%مقبض باب عادي%',
      '%مقبض باب%',
      '%poignée porte%',
      '%poignee porte%',
    ]);
    await loadAccessory('مقبض كبير ماريشال 1.25 متر (Poignée Maréchal 1.25m)', [
      '%ماريشال%1.25%',
      '%ماريشال%125%',
      '%marechal%1.25%',
      '%marechal%125%',
      '%maréchal%1.25%',
      '%maréchal%125%',
    ]);
    if (!componentOverrides.containsKey(
      'مقبض كبير ماريشال 1.25 متر (Poignée Maréchal 1.25m)',
    )) {
      await loadAccessory(
        'مقبض كبير ماريشال 1.25 متر (Poignée Maréchal 1.25m)',
        ['%ماريشال%', '%marechal%', '%maréchal%'],
      );
    }

    await loadAccessory('مقبض كبير ماريشال 2 متر (Poignée Maréchal 2m)', [
      '%ماريشال%2%',
      '%ماريشال%200%',
      '%marechal%2%',
      '%marechal%200%',
      '%maréchal%2%',
      '%maréchal%200%',
    ]);
    if (!componentOverrides.containsKey(
      'مقبض كبير ماريشال 2 متر (Poignée Maréchal 2m)',
    )) {
      await loadAccessory('مقبض كبير ماريشال 2 متر (Poignée Maréchal 2m)', [
        '%ماريشال%',
        '%marechal%',
        '%maréchal%',
      ]);
    }
    await loadAccessory('قفل رولون (Serrure à Rouleau)', [
      '%رولون%',
      '%rouleau%',
    ]);
    await loadAccessory('مقبض الباب Condamnation (Poignée Condamnation)', [
      '%حمام%',
      '%condamnation%',
    ]);
    await loadAccessory('قفل الباب Condamnation (Serrure Condamnation)', [
      '%قفل حمام%',
      '%serrure condamnation%',
    ]);
    await loadAccessory('الأسطوانة (Canon)', [
      '%canon%',
      '%الأسطوانة%',
      '%الاسطوانة%',
      '%قفل أسطواني%',
      '%barillet%',
    ]);
    await loadAccessory('قفل الباب (Serrure)', [
      '%قفل%',
      '%serrure%',
      '%lock%',
    ]);
    await loadAccessory('كريمون (Cremone)', ['%كريمون%', '%cremone%']);
    await loadAccessory('بوشون بارك لوز (Bouchon Parclose)', [
      '%بوشون بارك لوز%',
      '%bouchon parclose%',
      '%بوشون باكيت%',
    ]);
    await loadAccessory('أونتروماتيك (Entrematique)', [
      '%entrematique%',
      '%أونتروماتيك%',
      '%اونتروماتيك%',
      '%انتروماتيك%',
      '%أندراماتيك%',
      '%أندرماتيك%',
      '%اندريمانتيك%',
      '%اندروماتيك%',
      '%andramatique%',
      '%andrematique%',
    ]);
    await loadAccessory('كيت 67000 (Kit 67000)', [
      '%67000%kit%',
      '%67000%KIT%',
      '%kit%67000%',
      '%KIT%67000%',
      '%كيت%67000%',
      '%67000%كيت%',
    ]);
    await loadAccessory('كيت 76000 (Kit 76000)', [
      '%76000%kit%',
      '%76000%KIT%',
      '%kit%76000%',
      '%KIT%76000%',
      '%كيت%76000%',
      '%76000%كيت%',
    ]);
    await loadAccessory('قاش (Gache)', ['%قاش%', '%gâche%', '%gache%']);
    // Default Manivelle
    if (!componentOverrides.containsKey('المانيفال (Manivelle)')) {
      try {
        final res = await d.query(
          'ShutterComponents',
          where: 'name LIKE ? OR component_type LIKE ?',
          whereArgs: ['%مانيفال%', '%مانيفال%'],
        );
        if (res.isNotEmpty) {
          final m = Map<String, dynamic>.from(res.first);
          m['calculated_price'] = (m['price_dzd'] ?? m['price'] ?? 0.0)
              .toDouble();
          componentOverrides['المانيفال (Manivelle)'] = m;
        }
      } catch (_) {}
    }

    // Migration for backward compatibility
    if (componentOverrides.containsKey('جوان بروس (Joint Brosse)')) {
      final oldVal = componentOverrides['جوان بروس (Joint Brosse)'];
      if (!componentOverrides.containsKey(
        'جوان بروس للظلفة (Joint Brosse Sash)',
      )) {
        componentOverrides['جوان بروس للظلفة (Joint Brosse Sash)'] = oldVal;
      }
      if (!componentOverrides.containsKey(
        'جوان بروس للستار (Joint Brosse Shutter)',
      )) {
        componentOverrides['جوان بروس للستار (Joint Brosse Shutter)'] = oldVal;
      }
    }

    // Default Joint Brosse for Sash and Shutter
    Future<void> _assignBrosseDefault(String key) async {
      if (!componentOverrides.containsKey(key)) {
        try {
          List<Map<String, Object?>> res = [];

          // 1. البحث أولاً عن جوان بروس المربوط خصيصاً بهذه السلسلة
          res = await d.query(
            'Joints',
            where:
                '(name LIKE ? OR type LIKE ? OR name LIKE ? OR type LIKE ?) AND (series_id = ? OR (series_ids IS NOT NULL AND \',\' || series_ids || \',\' LIKE ?))',
            whereArgs: [
              '%brosse%',
              '%brosse%',
              '%بروس%',
              '%بروس%',
              seriesId,
              '%,' + seriesId.toString() + ',%',
            ],
            limit: 1,
          );

          // 2. إذا لم يجد، يبحث عن جوان بروس TPR للظلفة خصيصاً كخيار احتياطي
          if (res.isEmpty && key == 'جوان بروس للظلفة (Joint Brosse Sash)') {
            res = await d.query(
              'Joints',
              where: 'name LIKE ? OR type LIKE ? OR name LIKE ? OR type LIKE ?',
              whereArgs: [
                '%brosse%tpr%',
                '%brosse%tpr%',
                '%بروس%tpr%',
                '%بروس%tpr%',
              ],
              limit: 1,
            );
          }

          // 3. تراجع أخير: البحث عن جوان بروس العام
          if (res.isEmpty) {
            res = await d.query(
              'Joints',
              where: 'name LIKE ? OR type LIKE ? OR name LIKE ? OR type LIKE ?',
              whereArgs: ['%brosse%', '%brosse%', '%بروس%', '%بروس%'],
              limit: 1,
            );
          }

          if (res.isNotEmpty) {
            final m = Map<String, dynamic>.from(res.first);
            m['calculated_price'] = (m['price_per_meter'] ?? 0.0).toDouble();
            componentOverrides[key] = m;
          }
        } catch (_) {}
      }
    }

    await _assignBrosseDefault('جوان بروس للظلفة (Joint Brosse Sash)');
    await _assignBrosseDefault('جوان بروس للستار (Joint Brosse Shutter)');
  }

  void updateSelectedZoneGlassDecor({
    int? decorH,
    int? decorV,
    List<double>? decorHPositions,
    List<double>? decorVPositions,
    String? decorColor,
    double? decorThickness,
    bool? hasRosettes,
    int? decorBaguetteId,
    int? decorRosetteId,
    int? rosetteShape,
    bool? jointTwoSides,
  }) {
    if (selectedZone == null) return;
    _saveSnapshot();
    final targetCellKey = activeSubZone;
    if (targetCellKey != null && targetCellKey.isNotEmpty) {
      final GlassSpecification currentSpec = selectedZone!.getGlassForCell(
        targetCellKey,
      );
      final GlassSpecification updatedSpec = currentSpec.copyWith(
        decorH: decorH,
        decorV: decorV,
        decorHPositions: decorHPositions,
        decorVPositions: decorVPositions,
        decorColor: decorColor,
        decorThickness: decorThickness,
        hasRosettes: hasRosettes,
        decorBaguetteId: decorBaguetteId,
        decorRosetteId: decorRosetteId,
        rosetteShape: rosetteShape,
        jointTwoSides: jointTwoSides,
      );
      final updatedCellGlass = Map<String, GlassSpecification>.from(
        selectedZone!.cellGlassSpec,
      );
      updatedCellGlass[targetCellKey] = updatedSpec;
      selectedZone!.cellGlassSpec = updatedCellGlass;
    } else {
      selectedZone!.glass = selectedZone!.glass.copyWith(
        decorH: decorH,
        decorV: decorV,
        decorHPositions: decorHPositions,
        decorVPositions: decorVPositions,
        decorColor: decorColor,
        decorThickness: decorThickness,
        hasRosettes: hasRosettes,
        decorBaguetteId: decorBaguetteId,
        decorRosetteId: decorRosetteId,
        rosetteShape: rosetteShape,
        jointTwoSides: jointTwoSides,
      );
    }
    notifyListeners();
  }

  void updateZoneGlassDecorHPos(String zoneId, int index, double ratio) {
    _saveSnapshot();
    final idx = zones.indexWhere((z) => z.id == zoneId);
    if (idx != -1) {
      final spec = zones[idx].glass;
      final mutable = List<double>.from(spec.decorHPositions);
      if (index >= 0 && index < mutable.length) {
        mutable[index] = ratio;
        zones[idx].glass = spec.copyWith(decorHPositions: mutable);
        notifyListeners();
      }
    }
  }

  void updateZoneGlassDecorVPos(String zoneId, int index, double ratio) {
    _saveSnapshot();
    final idx = zones.indexWhere((z) => z.id == zoneId);
    if (idx != -1) {
      final spec = zones[idx].glass;
      final mutable = List<double>.from(spec.decorVPositions);
      if (index >= 0 && index < mutable.length) {
        mutable[index] = ratio;
        zones[idx].glass = spec.copyWith(decorVPositions: mutable);
        notifyListeners();
      }
    }
  }

  void setSelectedZoneOpenDirection(OpenDirection dir) {
    if (selectedZone == null) return;
    _saveSnapshot();
    selectedZone!.openDirection = dir;
    notifyListeners();
  }

  void setSelectedZoneLockType(LockType lock) {
    if (selectedZone == null) return;
    _saveSnapshot();
    selectedZone!.lockType = lock;
    notifyListeners();
  }

  /// Applies one complete handle choice in a single update.  Previously the
  /// interface changed the lock then each handle flag separately; every step
  /// notified listeners and the validation layer could restore the preceding
  /// choice before the new one was fully applied.
  void setSelectedZoneHandle({
    LockType lockType = LockType.none,
    bool useOctoHandle = false,
    bool usePvcHandleOnAlu = false,
    bool useClassicHandle = false,
  }) {
    final zone = selectedZone;
    if (zone == null) return;
    _saveSnapshot();
    // Choosing a door-specific handle is an explicit confirmation that the
    // selected sash is the thick/door variant.  Persist it on the zone too so
    // reopening a saved drawing cannot make the selection disappear before
    // its profile metadata is loaded.
    if (lockType == LockType.clef ||
        lockType == LockType.condamnation ||
        lockType == LockType.rouleau ||
        lockType == LockType.rouleau2000) {
      zone.isSash105 = true;
    }
    zone.lockType = lockType;
    zone.useOctoHandle = useOctoHandle;
    zone.usePvcHandleOnAlu = usePvcHandleOnAlu;
    zone.useClassicHandle = useClassicHandle;
    notifyListeners();
  }

  /// A double sash uses one handle by default.  This option is reserved for
  /// the rare case where the customer explicitly requests a handle on both
  /// leaves.
  void setSelectedZoneDoubleHandles(bool enabled) {
    final zone = selectedZone;
    if (zone == null || zone.content != ZoneContent.doubleSash) return;
    _saveSnapshot();
    zone.doubleSashHasTwoHandles = enabled;
    notifyListeners();
  }

  void setSelectedZonePvcHandleOnAlu(bool useIt) {
    if (selectedZone == null) return;
    _saveSnapshot();
    selectedZone!.usePvcHandleOnAlu = useIt;
    notifyListeners();
  }

  void toggleSashType104105() {
    if (selectedZone == null) return;
    _saveSnapshot();
    selectedZone!.isSash105 = !selectedZone!.isSash105;
    selectedZone!.sashThickness = _calculateSashThickness(
      selectedZone!.isSash105,
    );
    if (!selectedZone!.isSash105) {
      if (selectedZone!.lockType == LockType.clef ||
          selectedZone!.lockType == LockType.condamnation) {
        selectedZone!.lockType = LockType.none;
      }
    }
    notifyListeners();
  }

  Future<void> toggleCellSashType104105(String cellKey) async {
    if (selectedZone == null) return;
    _saveSnapshot();

    bool currentIs105 = false;
    final currentOverride = selectedZone!.cellSashOverrides[cellKey];
    if (currentOverride != null) {
      final code = currentOverride['code']?.toString().toLowerCase() ?? '';
      final name = currentOverride['name']?.toString().toLowerCase() ?? '';
      if (code.contains('104') || name.contains('104')) {
        currentIs105 = false;
      } else if (code.contains('105') ||
          code.contains('porte') ||
          code.contains('ouvr') ||
          name.contains('105') ||
          name.contains('porte') ||
          name.contains('ouvr') ||
          name.contains('بورت')) {
        currentIs105 = true;
      } else {
        currentIs105 = false;
      }
    } else {
      currentIs105 = selectedZone!.isSash105;
    }

    bool targetIs105 = !currentIs105;

    if (activeSeries != null) {
      String targetCode = targetIs105 ? '105' : '104';
      AluminumSection? foundSection;
      for (var sec in activeSeries!.sections) {
        if (sec.type.toLowerCase() == 'sash' &&
            (sec.code.contains(targetCode) || sec.name.contains(targetCode))) {
          foundSection = sec;
          break;
        }
      }

      if (foundSection != null) {
        double price = 0.0;
        if (selectedDbColor != null) {
          int colorId = selectedDbColor!['id'];
          final db = SqlDatabase();
          price = await db.getSectionPrice(foundSection.id, colorId);
        }

        final mutableMap = foundSection.toMap();
        mutableMap['calculated_price'] = price;

        final newOverrides = Map<String, Map<String, dynamic>>.from(
          selectedZone!.cellSashOverrides,
        );
        newOverrides[cellKey] = mutableMap;
        selectedZone!.cellSashOverrides = newOverrides;
      } else {
        final newOverrides = Map<String, Map<String, dynamic>>.from(
          selectedZone!.cellSashOverrides,
        );
        newOverrides.remove(cellKey);
        selectedZone!.cellSashOverrides = newOverrides;
      }
      notifyListeners();
    }
  }

  void setCellSashOpenDirection(String cellKey, OpenDirection dir) {
    if (selectedZone == null) return;
    _saveSnapshot();

    final newOverrides = Map<String, Map<String, dynamic>>.from(
      selectedZone!.cellSashOverrides,
    );
    final cellOverride = Map<String, dynamic>.from(newOverrides[cellKey] ?? {});
    cellOverride['openDirection'] = dir.name;
    newOverrides[cellKey] = cellOverride;
    selectedZone!.cellSashOverrides = newOverrides;

    notifyListeners();
  }

  void prepareShutterOnlyDrawing() {
    _saveSnapshot();
    zones.clear();
    width = 0;
    height = 0;
    isShutterOnly = false;
    hasShutter = false;
    isCaissonTunnel = false;
    hasSideCovers = false;
    useCustomSideCoverLayout = false;
    sideCoverSegments = [];
    hiddenSideCoverSegments = {};
    topSlantLeftY = 0.0;
    topSlantRightY = 0.0;
    bottomSlantLeftY = 0.0;
    bottomSlantRightY = 0.0;
    archHeight = 0.0;
    _frameColor = FrameColor.white;
    final whiteColor = _defaultFrameColor();
    _selectedDbColor = whiteColor == null
        ? null
        : Map<String, dynamic>.from(whiteColor);
    _selectedAccessoryColor = null;
    mullionProfiles.clear();
    groovedMullionCavityOnPositiveSide.clear();
    mullionSectionOverrides.clear();
    primaryMullionAxis = null;
    drawNextShapeAsShutterOnly = true;
    isDrawingMode = true;
    drawingMode = 'shutter_only';
    pendingDrawStart = null;
    drawingStart = null;
    drawingCurrent = null;
    selection = SelectionInfo.none;
    activeSubZone = null;
    notifyListeners();
  }

  void startDrawing(Offset pos) {
    if (drawNextShapeAsShutterOnly || isShutterOnly) {
      drawingMode = 'shutter_only';
      drawingStart = pos;
      drawingCurrent = pos;
      notifyListeners();
      return;
    }

    // A blank canvas can only create its first frame.  Keeping the previous
    // `add_frame` mode here used to create a second zone immediately, which
    // appeared as an unwanted central mullion.
    if (zones.isEmpty) {
      drawingMode = 'new_frame';
    } else {
      // Auto-detect mode: if start is inside the window → split, otherwise → add_frame
      final windowRect = Rect.fromLTWH(0, 0, width, height);
      if (windowRect.contains(pos)) {
        drawingMode = 'split';
      } else {
        drawingMode = 'add_frame';
      }
    }
    drawingStart = pos;
    drawingCurrent = pos;
    notifyListeners();
  }

  void updateDrawing(Offset pos) {
    drawingCurrent = pos;
    notifyListeners();
  }

  Rect getSafeGlassRect(Rect sashRect, double sashT) {
    double finalT = sashT;
    if (sashRect.width <= finalT * 2 + 10) {
      finalT = math.max(1.0, (sashRect.width - 10) / 2);
    }
    if (sashRect.height <= finalT * 2 + 10) {
      finalT = math.max(1.0, math.min(finalT, (sashRect.height - 10) / 2));
    }
    return sashRect.deflate(finalT);
  }

  void endDrawing() {
    pendingDrawStart = null; // always clear, even if we return early
    if (drawingStart == null || drawingCurrent == null) return;
    _saveSnapshot();
    if (drawingMode == 'shutter_only') {
      final drawnRect = Rect.fromPoints(drawingStart!, drawingCurrent!);
      if (drawnRect.width > 50 && drawnRect.height > 50) {
        width = drawnRect.width.clamp(200.0, 10000.0);
        height = drawnRect.height.clamp(200.0, 10000.0);
        drawnLeft = drawnRect.left;
        drawnTop = drawnRect.top;
        zones.clear();
        mullionProfiles.clear();
        groovedMullionCavityOnPositiveSide.clear();
        mullionSectionOverrides.clear();
        primaryMullionAxis = null;
        selection = SelectionInfo.none;
        activeSubZone = null;
        hasShutter = true;
        isShutterOnly = true;
        drawNextShapeAsShutterOnly = false;
        isCaissonTunnel = false;
        hasSideCovers = false;
        useCustomSideCoverLayout = false;
        sideCoverSegments = [];
        hiddenSideCoverSegments = {};
        topSlantLeftY = 0.0;
        topSlantRightY = 0.0;
        bottomSlantLeftY = 0.0;
        bottomSlantRightY = 0.0;
        archHeight = 0.0;
        updateShutterDefaultsIfNeeded();
      }
      drawingStart = null;
      drawingCurrent = null;
      notifyListeners();
      return;
    }
    if (zones.isEmpty) {
      Rect drawnRect = Rect.fromPoints(drawingStart!, drawingCurrent!);
      if (drawnRect.width > 50 && drawnRect.height > 50) {
        width = drawnRect.width.clamp(200.0, 10000.0);
        height = drawnRect.height.clamp(200.0, 10000.0);
        drawnLeft = drawnRect.left;
        drawnTop = drawnRect.top;
        double topOffset = (hasShutter && !hasArchOrSlant)
            ? shutterBoxHeight
            : 0.0;
        double pHeight = hasFramePlintheBottom ? plintheHeight : 0.0;
        double bottomOffset = hasBottomFrame ? profileThickness : 0.0;
        zones.add(
          WindowZone(
            id: UniqueKey().toString(),
            boundary: Rect.fromLTRB(
              profileThickness,
              topOffset + profileThickness,
              width - profileThickness,
              height - bottomOffset - pHeight,
            ),
            sashThickness: _calculateSashThickness(false),
            sashColor: FrameColor.white,
            selectedDbColor: _selectedDbColor,
          ),
        );
      }

      // The initial drag always produces one undivided frame.  In particular,
      // it must never continue into the add-frame branch left over from a
      // previous drawing.
      drawingStart = null;
      drawingCurrent = null;
      notifyListeners();
      return;
    }
    if (drawingMode == 'add_frame') {
      Rect drawnRect = Rect.fromPoints(drawingStart!, drawingCurrent!);
      if (drawnRect.width > 50 && drawnRect.height > 50) {
        double newW = drawnRect.width.clamp(200.0, 10000.0);
        double newH = drawnRect.height.clamp(200.0, 10000.0);

        double topOffset = (hasShutter && !hasArchOrSlant)
            ? shutterBoxHeight
            : 0.0;
        double pHeight = hasFramePlintheBottom ? plintheHeight : 0.0;
        double bottomOffset = hasBottomFrame ? profileThickness : 0.0;

        // Use the center of the drawn rect to determine which side of the
        // existing window the user is drawing on. This is robust regardless
        // of how far outside the window the drag starts/ends.
        double centerX = drawnRect.center.dx;
        double centerY = drawnRect.center.dy;
        double dxRight = (centerX - width).abs(); // distance to right edge
        double dxLeft = (centerX - 0).abs(); // distance to left edge
        double dyTop = (centerY - 0).abs(); // distance to top edge
        double dyBottom = (centerY - height).abs(); // distance to bottom edge

        // Clamp: only consider a side if the center is actually outside the window
        if (centerX > 0 && centerX < width) {
          dxRight = double.infinity;
          dxLeft = double.infinity;
        }
        if (centerY > 0 && centerY < height) {
          dyTop = double.infinity;
          dyBottom = double.infinity;
        }

        double minVal = math.min(
          math.min(dxRight, dxLeft),
          math.min(dyTop, dyBottom),
        );

        if (copyPreviousFrameSize) {
          // Copy the frame adjoining the side chosen by the drag. The first
          // added frame therefore copies the only existing frame; subsequent
          // frames copy the immediately neighbouring one.
          if (minVal == dxRight) {
            final joints = getVerticalFrameJoints();
            final start = joints.isEmpty ? 0.0 : joints.last;
            newW = width - start;
          } else if (minVal == dxLeft) {
            final joints = getVerticalFrameJoints();
            final end = joints.isEmpty ? width : joints.first;
            newW = end;
          } else if (minVal == dyBottom) {
            final joints = getHorizontalFrameJoints();
            final start = joints.isEmpty ? 0.0 : joints.last;
            newH = height - start;
          } else {
            final joints = getHorizontalFrameJoints();
            final end = joints.isEmpty ? height : joints.first;
            newH = end;
          }
        }

        final List<WindowZone> newZones = [];
        final tThickness = divisionThickness;

        if (minVal == dxRight) {
          double oldW = width;
          width = oldW + newW;
          for (var z in zones) {
            double rightEdge = oldW - profileThickness;
            if ((z.boundary.right - rightEdge).abs() < 2.0) {
              final cloned = z.clone();
              cloned.boundary = Rect.fromLTRB(
                z.boundary.left,
                z.boundary.top,
                oldW - tThickness / 2,
                z.boundary.bottom,
              );
              newZones.add(cloned);
            } else {
              newZones.add(z);
            }
          }
          newZones.add(
            WindowZone(
              id: UniqueKey().toString(),
              boundary: Rect.fromLTRB(
                oldW + tThickness / 2,
                topOffset + profileThickness,
                width - profileThickness,
                height - bottomOffset - pHeight,
              ),
              sashThickness: _calculateSashThickness(false),
            ),
          );
        } else if (minVal == dxLeft) {
          double oldW = width;
          width = oldW + newW;
          for (var z in zones) {
            double leftEdge = profileThickness;
            double newLeft = (z.boundary.left - leftEdge).abs() < 2.0
                ? newW + tThickness / 2
                : z.boundary.left + newW;
            final cloned = z.clone();
            cloned.boundary = Rect.fromLTRB(
              newLeft,
              z.boundary.top,
              z.boundary.right + newW,
              z.boundary.bottom,
            );
            newZones.add(cloned);
          }
          newZones.add(
            WindowZone(
              id: UniqueKey().toString(),
              boundary: Rect.fromLTRB(
                profileThickness,
                topOffset + profileThickness,
                newW - tThickness / 2,
                height - bottomOffset - pHeight,
              ),
              sashThickness: _calculateSashThickness(false),
            ),
          );
        } else if (minVal == dyBottom) {
          double oldH = height;
          height = oldH + newH;
          for (var z in zones) {
            double bottomEdge = oldH - bottomOffset - pHeight;
            if ((z.boundary.bottom - bottomEdge).abs() < 2.0) {
              final cloned = z.clone();
              cloned.boundary = Rect.fromLTRB(
                z.boundary.left,
                z.boundary.top,
                z.boundary.right,
                oldH - tThickness / 2,
              );
              newZones.add(cloned);
            } else {
              newZones.add(z);
            }
          }
          newZones.add(
            WindowZone(
              id: UniqueKey().toString(),
              boundary: Rect.fromLTRB(
                profileThickness,
                oldH + tThickness / 2,
                width - profileThickness,
                height - bottomOffset - pHeight,
              ),
              sashThickness: _calculateSashThickness(false),
            ),
          );
        } else {
          double oldH = height;
          height = oldH + newH;
          for (var z in zones) {
            double topEdge = topOffset + profileThickness;
            double newTop = (z.boundary.top - topEdge).abs() < 2.0
                ? newH + tThickness / 2
                : z.boundary.top + newH;
            final cloned = z.clone();
            cloned.boundary = Rect.fromLTRB(
              z.boundary.left,
              newTop,
              z.boundary.right,
              z.boundary.bottom + newH,
            );
            newZones.add(cloned);
          }
          newZones.add(
            WindowZone(
              id: UniqueKey().toString(),
              boundary: Rect.fromLTRB(
                profileThickness,
                topOffset + profileThickness,
                width - profileThickness,
                newH - tThickness / 2,
              ),
              sashThickness: _calculateSashThickness(false),
            ),
          );
        }
        zones = newZones;
        updatePrimaryMullionAxis();
      }
      drawingStart = null;
      drawingCurrent = null;
      notifyListeners();
      return;
    }
    double dx = drawingCurrent!.dx - drawingStart!.dx;
    double dy = drawingCurrent!.dy - drawingStart!.dy;
    if (dx.abs() > 2 || dy.abs() > 2) {
      bool isHorizontal = dx.abs() > dy.abs();
      WindowZone? targetZoneNullable;
      for (var z in zones) {
        if (z.boundary.contains(drawingStart!)) {
          targetZoneNullable = z;
          break;
        }
      }
      if (targetZoneNullable != null) {
        final WindowZone targetZone = targetZoneNullable;

        if (targetZone.content == ZoneContent.singleSash) {
          double sashT =
              targetZone.sashThickness ??
              getSectionThickness('sash', fallback: 45.0);
          Rect glassR = getSafeGlassRect(targetZone.boundary, sashT);

          // 🟢 شرط مسافة 100 ملم للرسم
          double minRatioH = 100.0 / glassR.height;
          double minRatioV = 100.0 / glassR.width;

          if (isHorizontal) {
            double ratio = ((drawingStart!.dy - glassR.top) / glassR.height)
                .clamp(minRatioH, 1.0 - minRatioH);
            List<double> currentPos = List.from(targetZone.innerHPositions);
            if (currentPos.isEmpty && targetZone.innerH > 0) {
              currentPos = List.generate(
                targetZone.innerH,
                (i) => (i + 1) / (targetZone.innerH + 1),
              );
            }

            bool isValid = true;
            for (double p in currentPos) {
              if ((p - ratio).abs() < minRatioH) isValid = false;
            }

            if (isValid) {
              currentPos.add(ratio);
              currentPos.sort();
              int hIndex = currentPos.indexOf(ratio);
              targetZone.innerHPositions = currentPos;
              targetZone.innerH = currentPos.length;
              if (targetZone.primaryDivisionAxis == null) {
                targetZone.primaryDivisionAxis = 'h';
              }

              final updatedDisabled = <String, bool>{};
              targetZone.disabledHorizontalDivisions.forEach((key, value) {
                final parts = key.split('_');
                final c = int.parse(parts[0]);
                final h = int.parse(parts[1]);
                if (h >= hIndex) {
                  updatedDisabled["${c}_${h + 1}"] = value;
                } else {
                  updatedDisabled["${c}_$h"] = value;
                }
              });

              double xRatio = (drawingStart!.dx - glassR.left) / glassR.width;
              int col = 0;
              final sortedV = List<double>.from(targetZone.innerVPositions)
                ..sort();
              for (int i = 0; i < sortedV.length; i++) {
                if (xRatio > sortedV[i]) col = i + 1;
              }

              int totalCols = sortedV.length + 1;
              for (int c = 0; c < totalCols; c++) {
                if (c != col) {
                  updatedDisabled["${c}_$hIndex"] = true;
                }
              }
              targetZone.disabledHorizontalDivisions = updatedDisabled;
            }
          } else {
            double ratio = ((drawingStart!.dx - glassR.left) / glassR.width)
                ///
                .clamp(minRatioV, 1.0 - minRatioV);
            List<double> currentPos = List.from(targetZone.innerVPositions);
            if (currentPos.isEmpty && targetZone.innerV > 0) {
              currentPos = List.generate(
                targetZone.innerV,
                (i) => (i + 1) / (targetZone.innerV + 1),
              );
            }

            bool isValid = true;
            for (double p in currentPos) {
              if ((p - ratio).abs() < minRatioV) isValid = false;
            }

            if (isValid) {
              currentPos.add(ratio);
              currentPos.sort();
              int vIndex = currentPos.indexOf(ratio);
              targetZone.innerVPositions = currentPos;
              targetZone.innerV = currentPos.length;
              if (targetZone.primaryDivisionAxis == null) {
                targetZone.primaryDivisionAxis = 'v';
              }

              final updatedDisabled = <String, bool>{};
              targetZone.disabledVerticalDivisions.forEach((key, value) {
                final parts = key.split('_');
                final r = int.parse(parts[0]);
                final v = int.parse(parts[1]);
                if (v >= vIndex) {
                  updatedDisabled["${r}_${v + 1}"] = value;
                } else {
                  updatedDisabled["${r}_$v"] = value;
                }
              });

              double yRatio = (drawingStart!.dy - glassR.top) / glassR.height;
              int row = 0;
              final sortedH = List<double>.from(targetZone.innerHPositions)
                ..sort();
              for (int i = 0; i < sortedH.length; i++) {
                if (yRatio > sortedH[i]) row = i + 1;
              }

              int totalRows = sortedH.length + 1;
              for (int r = 0; r < totalRows; r++) {
                if (r != row) {
                  updatedDisabled["${r}_$vIndex"] = true;
                }
              }
              targetZone.disabledVerticalDivisions = updatedDisabled;
            }
          }
        } else if (targetZone.content == ZoneContent.doubleSash) {
          double sashT =
              targetZone.sashThickness ??
              getSectionThickness('sash', fallback: 45.0);
          double splitX =
              targetZone.boundary.left +
              targetZone.boundary.width * targetZone.doubleSashRatio;
          bool isRight = drawingStart!.dx > splitX;

          final sep = 4.0;
          Rect sashR = isRight
              ? Rect.fromLTRB(
                  splitX + sep / 2,
                  targetZone.boundary.top,
                  targetZone.boundary.right,
                  targetZone.boundary.bottom,
                )
              : Rect.fromLTRB(
                  targetZone.boundary.left,
                  targetZone.boundary.top,
                  splitX - sep / 2,
                  targetZone.boundary.bottom,
                );
          Rect glassR = getSafeGlassRect(sashR, sashT);

          double minRatioH = 100.0 / glassR.height;
          double minRatioV = 100.0 / glassR.width;

          if (isHorizontal) {
            double ratio = ((drawingStart!.dy - glassR.top) / glassR.height)
                .clamp(minRatioH, 1.0 - minRatioH);
            if (isRight) {
              List<double> currentPos = List.from(
                targetZone.rightInnerHPositions,
              );
              if (currentPos.isEmpty && targetZone.rightInnerH > 0) {
                currentPos = List.generate(
                  targetZone.rightInnerH,
                  (i) => (i + 1) / (targetZone.rightInnerH + 1),
                );
              }
              bool isValid = true;
              for (double p in currentPos) {
                if ((p - ratio).abs() < minRatioH) isValid = false;
              }
              if (isValid) {
                currentPos.add(ratio);
                currentPos.sort();
                int hIndex = currentPos.indexOf(ratio);
                targetZone.rightInnerHPositions = currentPos;
                targetZone.rightInnerH = currentPos.length;
                if (targetZone.rightPrimaryDivisionAxis == null) {
                  targetZone.rightPrimaryDivisionAxis = 'h';
                }

                final updatedDisabled = <String, bool>{};
                targetZone.disabledHorizontalDivisions.forEach((key, value) {
                  final parts = key.split('_');
                  if (parts[0] == 'right') {
                    final c = int.parse(parts[1]);
                    final h = int.parse(parts[2]);
                    if (h >= hIndex) {
                      updatedDisabled["right_${c}_${h + 1}"] = value;
                    } else {
                      updatedDisabled["right_${c}_$h"] = value;
                    }
                  } else {
                    updatedDisabled[key] = value;
                  }
                });

                double xRatio = (drawingStart!.dx - glassR.left) / glassR.width;
                int col = 0;
                final sortedV = List<double>.from(
                  targetZone.rightInnerVPositions,
                )..sort();
                for (int i = 0; i < sortedV.length; i++) {
                  if (xRatio > sortedV[i]) col = i + 1;
                }

                int totalCols = sortedV.length + 1;
                for (int c = 0; c < totalCols; c++) {
                  if (c != col) {
                    updatedDisabled["right_${c}_$hIndex"] = true;
                  }
                }
                targetZone.disabledHorizontalDivisions = updatedDisabled;
              }
            } else {
              List<double> currentPos = List.from(targetZone.innerHPositions);
              if (currentPos.isEmpty && targetZone.innerH > 0) {
                currentPos = List.generate(
                  targetZone.innerH,
                  (i) => (i + 1) / (targetZone.innerH + 1),
                );
              }
              bool isValid = true;
              for (double p in currentPos) {
                if ((p - ratio).abs() < minRatioH) isValid = false;
              }
              if (isValid) {
                currentPos.add(ratio);
                currentPos.sort();
                int hIndex = currentPos.indexOf(ratio);
                targetZone.innerHPositions = currentPos;
                targetZone.innerH = currentPos.length;
                if (targetZone.primaryDivisionAxis == null) {
                  targetZone.primaryDivisionAxis = 'h';
                }

                final updatedDisabled = <String, bool>{};
                targetZone.disabledHorizontalDivisions.forEach((key, value) {
                  final parts = key.split('_');
                  if (parts[0] != 'right') {
                    final c = int.parse(parts[0]);
                    final h = int.parse(parts[1]);
                    if (h >= hIndex) {
                      updatedDisabled["${c}_${h + 1}"] = value;
                    } else {
                      updatedDisabled["${c}_$h"] = value;
                    }
                  } else {
                    updatedDisabled[key] = value;
                  }
                });

                double xRatio = (drawingStart!.dx - glassR.left) / glassR.width;
                int col = 0;
                final sortedV = List<double>.from(targetZone.innerVPositions)
                  ..sort();
                for (int i = 0; i < sortedV.length; i++) {
                  if (xRatio > sortedV[i]) col = i + 1;
                }

                int totalCols = sortedV.length + 1;
                for (int c = 0; c < totalCols; c++) {
                  if (c != col) {
                    updatedDisabled["${c}_$hIndex"] = true;
                  }
                }
                targetZone.disabledHorizontalDivisions = updatedDisabled;
              }
            }
          } else {
            double ratio = ((drawingStart!.dx - glassR.left) / glassR.width)
                .clamp(minRatioV, 1.0 - minRatioV);
            if (isRight) {
              List<double> currentPos = List.from(
                targetZone.rightInnerVPositions,
              );
              if (currentPos.isEmpty && targetZone.rightInnerV > 0) {
                currentPos = List.generate(
                  targetZone.rightInnerV,
                  (i) => (i + 1) / (targetZone.rightInnerV + 1),
                );
              }
              bool isValid = true;
              for (double p in currentPos) {
                if ((p - ratio).abs() < minRatioV) isValid = false;
              }
              if (isValid) {
                currentPos.add(ratio);
                currentPos.sort();
                int vIndex = currentPos.indexOf(ratio);
                targetZone.rightInnerVPositions = currentPos;
                targetZone.rightInnerV = currentPos.length;
                if (targetZone.rightPrimaryDivisionAxis == null) {
                  targetZone.rightPrimaryDivisionAxis = 'v';
                }

                final updatedDisabled = <String, bool>{};
                targetZone.disabledVerticalDivisions.forEach((key, value) {
                  final parts = key.split('_');
                  if (parts[0] == 'right') {
                    final r = int.parse(parts[1]);
                    final v = int.parse(parts[2]);
                    if (v >= vIndex) {
                      updatedDisabled["right_${r}_${v + 1}"] = value;
                    } else {
                      updatedDisabled["right_${r}_$v"] = value;
                    }
                  } else {
                    updatedDisabled[key] = value;
                  }
                });

                double yRatio = (drawingStart!.dy - glassR.top) / glassR.height;
                int row = 0;
                final sortedH = List<double>.from(
                  targetZone.rightInnerHPositions,
                )..sort();
                for (int i = 0; i < sortedH.length; i++) {
                  if (yRatio > sortedH[i]) row = i + 1;
                }

                int totalRows = sortedH.length + 1;
                for (int r = 0; r < totalRows; r++) {
                  if (r != row) {
                    updatedDisabled["right_${r}_$vIndex"] = true;
                  }
                }
                targetZone.disabledVerticalDivisions = updatedDisabled;
              }
            } else {
              List<double> currentPos = List.from(targetZone.innerVPositions);
              if (currentPos.isEmpty && targetZone.innerV > 0) {
                currentPos = List.generate(
                  targetZone.innerV,
                  (i) => (i + 1) / (targetZone.innerV + 1),
                );
              }
              bool isValid = true;
              for (double p in currentPos) {
                if ((p - ratio).abs() < minRatioV) isValid = false;
              }
              if (isValid) {
                currentPos.add(ratio);
                currentPos.sort();
                int vIndex = currentPos.indexOf(ratio);
                targetZone.innerVPositions = currentPos;
                targetZone.innerV = currentPos.length;
                if (targetZone.primaryDivisionAxis == null) {
                  targetZone.primaryDivisionAxis = 'v';
                }

                final updatedDisabled = <String, bool>{};
                targetZone.disabledVerticalDivisions.forEach((key, value) {
                  final parts = key.split('_');
                  if (parts[0] != 'right') {
                    final r = int.parse(parts[0]);
                    final v = int.parse(parts[1]);
                    if (v >= vIndex) {
                      updatedDisabled["${r}_${v + 1}"] = value;
                    } else {
                      updatedDisabled["${r}_$v"] = value;
                    }
                  } else {
                    updatedDisabled[key] = value;
                  }
                });

                double yRatio = (drawingStart!.dy - glassR.top) / glassR.height;
                int row = 0;
                final sortedH = List<double>.from(targetZone.innerHPositions)
                  ..sort();
                for (int i = 0; i < sortedH.length; i++) {
                  if (yRatio > sortedH[i]) row = i + 1;
                }

                int totalRows = sortedH.length + 1;
                for (int r = 0; r < totalRows; r++) {
                  if (r != row) {
                    updatedDisabled["${r}_$vIndex"] = true;
                  }
                }
                targetZone.disabledVerticalDivisions = updatedDisabled;
              }
            }
          }
        } else if (targetZone.content == ZoneContent.slidingSash) {
          // No action
        } else {
          _splitIntersectingZonesSmart(
            drawingStart!,
            drawingCurrent!,
            isHorizontal,
          );
        }
      } else {
        _splitIntersectingZonesSmart(
          drawingStart!,
          drawingCurrent!,
          isHorizontal,
        );
      }
    }
    drawingStart = null;
    drawingCurrent = null;
    notifyListeners();
  }

  void _splitIntersectingZonesSmart(Offset start, Offset end, bool horizontal) {
    _saveSnapshot();
    final List<WindowZone> newZones = [];
    final sep = mullionThickness / 2;
    double minPath = horizontal
        ? math.min(start.dx, end.dx)
        : math.min(start.dy, end.dy);
    double maxPath = horizontal
        ? math.max(start.dx, end.dx)
        : math.max(start.dy, end.dy);
    double cutLine = _snapCutLineToNearbyMullion(start, end, horizontal);

    for (var z in zones) {
      bool intersects = false;
      if (horizontal) {
        if (cutLine > z.boundary.top + 20 && cutLine < z.boundary.bottom - 20) {
          if (maxPath > z.boundary.left && minPath < z.boundary.right) {
            intersects = true;
          }
        }
      } else {
        if (cutLine > z.boundary.left + 20 && cutLine < z.boundary.right - 20) {
          if (maxPath > z.boundary.top && minPath < z.boundary.bottom) {
            intersects = true;
          }
        }
      }
      if (intersects) {
        if (horizontal) {
          newZones.add(
            WindowZone(
              id: UniqueKey().toString(),
              boundary: Rect.fromLTRB(
                z.boundary.left,
                cutLine + sep,
                z.boundary.right,
                z.boundary.bottom,
              ),
              sashColor: z.sashColor,
              content: z.content,
              glass: z.glass.clone(),
              openDirection: z.openDirection,
              sashThickness: z.sashThickness,
            ),
          );
          newZones.add(
            WindowZone(
              id: UniqueKey().toString(),
              boundary: Rect.fromLTRB(
                z.boundary.left,
                z.boundary.top,
                z.boundary.right,
                cutLine - sep,
              ),
              sashColor: z.sashColor,
              content: z.content,
              glass: z.glass.clone(),
              openDirection: z.openDirection,
              sashThickness: z.sashThickness,
            ),
          );
        } else {
          newZones.add(
            WindowZone(
              id: UniqueKey().toString(),
              boundary: Rect.fromLTRB(
                cutLine + sep,
                z.boundary.top,
                z.boundary.right,
                z.boundary.bottom,
              ),
              sashColor: z.sashColor,
              content: z.content,
              glass: z.glass.clone(),
              openDirection: z.openDirection,
              sashThickness: z.sashThickness,
            ),
          );
          newZones.add(
            WindowZone(
              id: UniqueKey().toString(),
              boundary: Rect.fromLTRB(
                z.boundary.left,
                z.boundary.top,
                cutLine - sep,
                z.boundary.bottom,
              ),
              sashColor: z.sashColor,
              content: z.content,
              glass: z.glass.clone(),
              openDirection: z.openDirection,
              sashThickness: z.sashThickness,
            ),
          );
        }
      } else {
        newZones.add(z);
      }
    }
    zones = newZones;
    updatePrimaryMullionAxis();
  }

  double _snapCutLineToNearbyMullion(
    Offset start,
    Offset end,
    bool horizontal,
  ) {
    const snapDistance = 100.0;
    final rawCutLine = horizontal ? start.dy : start.dx;
    final minPath = horizontal
        ? math.min(start.dx, end.dx)
        : math.min(start.dy, end.dy);
    final maxPath = horizontal
        ? math.max(start.dx, end.dx)
        : math.max(start.dy, end.dy);
    final candidates = <double>{};

    for (var i = 0; i < zones.length; i++) {
      for (var j = i + 1; j < zones.length; j++) {
        final a = zones[i].boundary;
        final b = zones[j].boundary;
        if (horizontal) {
          final aBelowB = (a.bottom - b.top).abs() <= mullionThickness + 4.0;
          final bBelowA = (b.bottom - a.top).abs() <= mullionThickness + 4.0;
          if (!aBelowB && !bBelowA) continue;
          final overlap =
              math.min(a.right, b.right) - math.max(a.left, b.left);
          if (overlap <= 5.0) continue;
          candidates.add(
            aBelowB ? (a.bottom + b.top) / 2 : (b.bottom + a.top) / 2,
          );
        } else {
          final aLeftOfB = (a.right - b.left).abs() <= mullionThickness + 4.0;
          final bLeftOfA = (b.right - a.left).abs() <= mullionThickness + 4.0;
          if (!aLeftOfB && !bLeftOfA) continue;
          final overlap =
              math.min(a.bottom, b.bottom) - math.max(a.top, b.top);
          if (overlap <= 5.0) continue;
          candidates.add(
            aLeftOfB ? (a.right + b.left) / 2 : (b.right + a.left) / 2,
          );
        }
      }
    }

    double? best;
    double bestDistance = snapDistance + 0.001;
    for (final candidate in candidates) {
      final distance = (candidate - rawCutLine).abs();
      if (distance > snapDistance || distance >= bestDistance) continue;
      final cutsAtLeastOneDraggedZone = zones.any((zone) {
        final r = zone.boundary;
        if (horizontal) {
          return candidate > r.top + 20 &&
              candidate < r.bottom - 20 &&
              maxPath > r.left &&
              minPath < r.right;
        }
        return candidate > r.left + 20 &&
            candidate < r.right - 20 &&
            maxPath > r.top &&
            minPath < r.bottom;
      });
      if (!cutsAtLeastOneDraggedZone) continue;
      best = candidate;
      bestDistance = distance;
    }

    return best ?? rawCutLine;
  }

  void moveSelectedMullion(double deltaPixels) {
    if (selection.type != SelectionType.mullion ||
        selection.mullionPosition == null) {
      return;
    }
    _saveSnapshot();
    bool isH = selection.isHorizontalMullion!;
    double pos = selection.mullionPosition!;
    final oldKey = _mullionKey(isH, pos);
    final sep = mullionThickness / 2;
    final t = profileThickness;
    if (isH) {
      double minAllowedY = t * 2;
      double maxAllowedY = height - t * 2;
      for (var z in zones) {
        if ((z.boundary.bottom - (pos - sep)).abs() < 2) {
          if (z.boundary.top + 50 > minAllowedY) {
            minAllowedY = z.boundary.top + 50;
          }
        }
        if ((z.boundary.top - (pos + sep)).abs() < 2) {
          if (z.boundary.bottom - 50 < maxAllowedY) {
            maxAllowedY = z.boundary.bottom - 50;
          }
        }
      }
      double newPos = pos + deltaPixels;
      if (newPos - sep < minAllowedY) newPos = minAllowedY + sep;
      if (newPos + sep > maxAllowedY) newPos = maxAllowedY - sep;
      double actualDelta = newPos - pos;
      if (actualDelta == 0) return;

      for (var z in zones) {
        if ((z.boundary.bottom - (pos - sep)).abs() < 2) {
          z.boundary = Rect.fromLTRB(
            z.boundary.left,
            z.boundary.top,
            z.boundary.right,
            z.boundary.bottom + actualDelta,
          );
        } else if ((z.boundary.top - (pos + sep)).abs() < 2) {
          z.boundary = Rect.fromLTRB(
            z.boundary.left,
            z.boundary.top + actualDelta,
            z.boundary.right,
            z.boundary.bottom,
          );
        }
      }
      selection = SelectionInfo(
        type: SelectionType.mullion,
        isHorizontalMullion: isH,
        mullionPosition: newPos,
        mullionStart: selection.mullionStart,
        mullionEnd: selection.mullionEnd,
      );
      _moveMullionMetadata(oldKey, _mullionKey(isH, newPos));
    } else {
      double minAllowedX = t * 2;
      double maxAllowedX = width - t * 2;
      for (var z in zones) {
        if ((z.boundary.right - (pos - sep)).abs() < 2) {
          if (z.boundary.left + 50 > minAllowedX) {
            minAllowedX = z.boundary.left + 50;
          }
        }
        if ((z.boundary.left - (pos + sep)).abs() < 2) {
          if (z.boundary.right - 50 < maxAllowedX) {
            maxAllowedX = z.boundary.right - 50;
          }
        }
      }
      double newPos = pos + deltaPixels;
      if (newPos - sep < minAllowedX) newPos = minAllowedX + sep;
      if (newPos + sep > maxAllowedX) newPos = maxAllowedX - sep;
      double actualDelta = newPos - pos;
      if (actualDelta == 0) return;

      for (var z in zones) {
        if ((z.boundary.right - (pos - sep)).abs() < 2) {
          z.boundary = Rect.fromLTRB(
            z.boundary.left,
            z.boundary.top,
            z.boundary.right + actualDelta,
            z.boundary.bottom,
          );
        } else if ((z.boundary.left - (pos + sep)).abs() < 2) {
          z.boundary = Rect.fromLTRB(
            z.boundary.left + actualDelta,
            z.boundary.top,
            z.boundary.right,
            z.boundary.bottom,
          );
        }
      }
      selection = SelectionInfo(
        type: SelectionType.mullion,
        isHorizontalMullion: isH,
        mullionPosition: newPos,
        mullionStart: selection.mullionStart,
        mullionEnd: selection.mullionEnd,
      );
      _moveMullionMetadata(oldKey, _mullionKey(isH, newPos));
    }
    notifyListeners();
  }

  void _moveMullionMetadata(String oldKey, String newKey) {
    if (oldKey == newKey) return;
    final profile = mullionProfiles.remove(oldKey);
    if (profile != null) {
      mullionProfiles[newKey] = profile;
    }
    final cavity = groovedMullionCavityOnPositiveSide.remove(oldKey);
    if (cavity != null) {
      groovedMullionCavityOnPositiveSide[newKey] = cavity;
    }
    final section = mullionSectionOverrides.remove(oldKey);
    if (section != null) {
      mullionSectionOverrides[newKey] = section;
    }
  }

  void setMullionProfile(MullionProfileType type) {
    if (selection.type != SelectionType.mullion ||
        selection.mullionPosition == null) {
      return;
    }
    _saveSnapshot();
    final isHorizontal = selection.isHorizontalMullion!;
    final position = selection.mullionPosition!;
    String key = _mullionKey(isHorizontal, position);
    mullionProfiles[key] = type;
    mullionSectionOverrides.remove(key);
    if (type != MullionProfileType.grooved) {
      groovedMullionCavityOnPositiveSide.remove(key);
      _restoreGlassOnBothSidesOfMullion(isHorizontal, position);
    } else {
      _enforceGroovedMullionGlassSide(isHorizontal, position);
    }
    notifyListeners();
  }

  void setMullionFrameSection(
    MullionProfileType type,
    Map<String, dynamic> section,
  ) {
    if (selection.type != SelectionType.mullion ||
        selection.mullionPosition == null) {
      return;
    }
    if (type == MullionProfileType.standard) {
      setMullionProfile(type);
      return;
    }

    _saveSnapshot();
    final key = _mullionKey(
      selection.isHorizontalMullion!,
      selection.mullionPosition!,
    );
    final selected = Map<String, dynamic>.from(section);
    selected['mullion_profile_type'] = type.name;
    selected['is_double_frame'] = type == MullionProfileType.flat;
    mullionProfiles[key] = type;
    mullionSectionOverrides[key] = selected;
    if (type != MullionProfileType.grooved) {
      groovedMullionCavityOnPositiveSide.remove(key);
      _restoreGlassOnBothSidesOfMullion(
        selection.isHorizontalMullion!,
        selection.mullionPosition!,
      );
    }
    if (type == MullionProfileType.grooved) {
      _enforceGroovedMullionGlassSide(
        selection.isHorizontalMullion!,
        selection.mullionPosition!,
      );
    }
    notifyListeners();
  }

  List<(WindowZone, WindowZone)> _mullionAdjacentPairs(
    bool isHorizontal,
    double position,
  ) {
    final tolerance = math.max(maximumMullionThickness, profileThickness) + 8.0;

    bool isManaged(WindowZone zone) =>
        zone.content == ZoneContent.fixedGlass ||
        zone.content == ZoneContent.empty;

    bool touchesNegativeSide(WindowZone zone) => isHorizontal
        ? (zone.boundary.bottom <= position &&
              (zone.boundary.bottom - position).abs() <= tolerance)
        : (zone.boundary.right <= position &&
              (zone.boundary.right - position).abs() <= tolerance);

    bool touchesPositiveSide(WindowZone zone) => isHorizontal
        ? (zone.boundary.top >= position &&
              (zone.boundary.top - position).abs() <= tolerance)
        : (zone.boundary.left >= position &&
              (zone.boundary.left - position).abs() <= tolerance);

    double overlap(WindowZone a, WindowZone b) {
      if (isHorizontal) {
        return math.min(a.boundary.right, b.boundary.right) -
            math.max(a.boundary.left, b.boundary.left);
      }
      return math.min(a.boundary.bottom, b.boundary.bottom) -
          math.max(a.boundary.top, b.boundary.top);
    }

    final negativeZones = zones
        .where((zone) => isManaged(zone) && touchesNegativeSide(zone))
        .toList();
    final positiveZones = zones
        .where((zone) => isManaged(zone) && touchesPositiveSide(zone))
        .toList();

    final pairs = <(WindowZone, WindowZone)>[];
    for (final negative in negativeZones) {
      for (final positive in positiveZones) {
        if (overlap(negative, positive) > 5.0) {
          pairs.add((negative, positive));
        }
      }
    }
    return pairs;
  }

  void _restoreGlassOnBothSidesOfMullion(bool isHorizontal, double position) {
    for (final (negative, positive) in _mullionAdjacentPairs(
      isHorizontal,
      position,
    )) {
      final hasGlass =
          negative.content == ZoneContent.fixedGlass ||
          positive.content == ZoneContent.fixedGlass;
      if (!hasGlass) continue;
      negative.content = ZoneContent.fixedGlass;
      positive.content = ZoneContent.fixedGlass;
    }
  }

  void _enforceGroovedMullionGlassSide(bool isHorizontal, double position) {
    final holderOnPositiveSide = isGroovedMullionCavityOnPositiveSide(
      isHorizontal,
      position,
    );

    for (final (negative, positive) in _mullionAdjacentPairs(
      isHorizontal,
      position,
    )) {
      final hasGlass =
          negative.content == ZoneContent.fixedGlass ||
          positive.content == ZoneContent.fixedGlass;
      if (!hasGlass) continue;

      final holder = holderOnPositiveSide ? positive : negative;
      final emptySide = holderOnPositiveSide ? negative : positive;
      holder.content = ZoneContent.fixedGlass;
      emptySide.content = ZoneContent.empty;
    }
  }

  /// Reverses the cavity direction of a Cadre 140.  The direction is stored
  /// per mullion, so it stays unchanged after saving or reopening the order.
  bool toggleGroovedMullionCavity(bool isHorizontal, double position) {
    if (!isGroovedFrameMullionAt(isHorizontal, position)) return false;

    _saveSnapshot();
    final key = _mullionKey(isHorizontal, position);
    groovedMullionCavityOnPositiveSide[key] =
        !(groovedMullionCavityOnPositiveSide[key] ?? false);
    _enforceGroovedMullionGlassSide(isHorizontal, position);
    notifyListeners();
    return true;
  }

  void deleteSelectedMullion() {
    if (selection.type != SelectionType.mullion ||
        selection.mullionPosition == null) {
      return;
    }
    _saveSnapshot();
    bool isH = selection.isHorizontalMullion!;
    double pos = selection.mullionPosition!;
    final sep = mullionThickness / 2;
    final List<WindowZone> toMerge = [];
    final List<WindowZone> others = [];
    for (var z in zones) {
      if (isH) {
        if ((z.boundary.bottom - (pos - sep)).abs() < 2 ||
            (z.boundary.top - (pos + sep)).abs() < 2) {
          toMerge.add(z);
        } else {
          others.add(z);
        }
      } else {
        if ((z.boundary.right - (pos - sep)).abs() < 2 ||
            (z.boundary.left - (pos + sep)).abs() < 2) {
          toMerge.add(z);
        } else {
          others.add(z);
        }
      }
    }
    if (toMerge.length < 2) return;
    double minX = toMerge.map((z) => z.boundary.left).reduce(math.min);
    double minY = toMerge.map((z) => z.boundary.top).reduce(math.min);
    double maxX = toMerge.map((z) => z.boundary.right).reduce(math.max);
    double maxY = toMerge.map((z) => z.boundary.bottom).reduce(math.max);
    others.add(
      WindowZone(
        id: UniqueKey().toString(),
        boundary: Rect.fromLTRB(minX, minY, maxX, maxY),
        sashColor: _frameColor,
        sashThickness: _calculateSashThickness(false),
      ),
    );
    zones = others;
    selection = SelectionInfo.none;
    String key = "${isH ? 'H' : 'V'}_${pos.toStringAsFixed(1)}";
    mullionProfiles.remove(key);
    groovedMullionCavityOnPositiveSide.remove(key);
    mullionSectionOverrides.remove(key);
    updatePrimaryMullionAxis();
    notifyListeners();
  }

  void deleteSelectedInnerDivision() {
    if (selection.type != SelectionType.innerDivision ||
        selection.zoneId == null ||
        selection.innerDivisionIndex == null) {
      return;
    }
    _saveSnapshot();
    final zoneId = selection.zoneId!;
    final index = selection.innerDivisionIndex!;
    final isH = selection.isHorizontalInnerDivision ?? true;
    final isRight = selection.isRightSashInnerDivision ?? false;

    final idx = zones.indexWhere((z) => z.id == zoneId);
    if (idx == -1) return;
    final zone = zones[idx];

    if (isH) {
      if (isRight) {
        if (zone.rightInnerH > 0) {
          zone.rightInnerH -= 1;
          if (zone.rightInnerHPositions.isNotEmpty) {
            List<double> pos = List.from(zone.rightInnerHPositions);
            if (index < pos.length) pos.removeAt(index);
            zone.rightInnerHPositions = pos;
          }
        }
      } else {
        if (zone.innerH > 0) {
          zone.innerH -= 1;
          if (zone.innerHPositions.isNotEmpty) {
            List<double> pos = List.from(zone.innerHPositions);
            if (index < pos.length) pos.removeAt(index);
            zone.innerHPositions = pos;
          }
        }
      }
    } else {
      if (isRight) {
        if (zone.rightInnerV > 0) {
          zone.rightInnerV -= 1;
          if (zone.rightInnerVPositions.isNotEmpty) {
            List<double> pos = List.from(zone.rightInnerVPositions);
            if (index < pos.length) pos.removeAt(index);
            zone.rightInnerVPositions = pos;
          }
        }
      } else {
        if (zone.innerV > 0) {
          zone.innerV -= 1;
          if (zone.innerVPositions.isNotEmpty) {
            List<double> pos = List.from(zone.innerVPositions);
            if (index < pos.length) pos.removeAt(index);
            zone.innerVPositions = pos;
          }
        }
      }
    }
    selection = SelectionInfo.none;

    // Update primary axes for the zone
    if (zone.innerH == 0 && zone.innerV == 0) {
      zone.primaryDivisionAxis = null;
    } else if (zone.innerH == 0) {
      zone.primaryDivisionAxis = 'v';
    } else if (zone.innerV == 0) {
      zone.primaryDivisionAxis = 'h';
    }

    if (zone.rightInnerH == 0 && zone.rightInnerV == 0) {
      zone.rightPrimaryDivisionAxis = null;
    } else if (zone.rightInnerH == 0) {
      zone.rightPrimaryDivisionAxis = 'v';
    } else if (zone.rightInnerV == 0) {
      zone.rightPrimaryDivisionAxis = 'h';
    }

    notifyListeners();
  }

  void moveSelectedInnerDivision(double deltaX, double deltaY) {
    if (selection.type != SelectionType.innerDivision ||
        selection.zoneId == null ||
        selection.innerDivisionIndex == null) {
      return;
    }

    final zone = zones.firstWhere((z) => z.id == selection.zoneId);
    final isH = selection.isHorizontalInnerDivision ?? true;
    final isRight = selection.isRightSashInnerDivision ?? false;
    final index = selection.innerDivisionIndex!;

    double sashT =
        zone.sashThickness ?? getSectionThickness('sash', fallback: 45.0);
    Rect sashR = zone.boundary;
    if (zone.content == ZoneContent.doubleSash) {
      final sep = 4.0;
      final midX = sashR.left + sashR.width * zone.doubleSashRatio;
      sashR = isRight
          ? Rect.fromLTRB(midX + sep / 2, sashR.top, sashR.right, sashR.bottom)
          : Rect.fromLTRB(sashR.left, sashR.top, midX - sep / 2, sashR.bottom);
    }
    Rect glassR = getSafeGlassRect(sashR, sashT);

    // 🟢 شرط الـ 100 ملم (10 سم) أثناء التحريك
    double minRatioH = 100.0 / glassR.height;
    double minRatioV = 100.0 / glassR.width;

    if (isH) {
      double deltaRatio = deltaY / glassR.height;
      List<double> pos = List.from(
        isRight ? zone.rightInnerHPositions : zone.innerHPositions,
      );
      if (index < pos.length) {
        double newVal = pos[index] + deltaRatio;
        double minVal = index == 0 ? minRatioH : pos[index - 1] + minRatioH;
        double maxVal = index == pos.length - 1
            ? 1.0 - minRatioH
            : pos[index + 1] - minRatioH;
        if (minVal > maxVal) return; // يمنع التحريك إذا اقترب أكثر من 10 سم
        pos[index] = newVal.clamp(minVal, maxVal);
        if (isRight) {
          zone.rightInnerHPositions = pos;
        } else {
          zone.innerHPositions = pos;
        }
      }
    } else {
      double deltaRatio = deltaX / glassR.width;
      List<double> pos = List.from(
        isRight ? zone.rightInnerVPositions : zone.innerVPositions,
      );
      if (index < pos.length) {
        double newVal = pos[index] + deltaRatio;
        double minVal = index == 0 ? minRatioV : pos[index - 1] + minRatioV;
        double maxVal = index == pos.length - 1
            ? 1.0 - minRatioV
            : pos[index + 1] - minRatioV;
        if (minVal > maxVal) return; // يمنع التحريك إذا اقترب أكثر من 10 سم
        pos[index] = newVal.clamp(minVal, maxVal);
        if (isRight) {
          zone.rightInnerVPositions = pos;
        } else {
          zone.innerVPositions = pos;
        }
      }
    }
    notifyListeners();
  }

  void clearAll() {
    zones.clear();
    width = 0;
    height = 0;
    mullionProfiles.clear();
    groovedMullionCavityOnPositiveSide.clear();
    mullionSectionOverrides.clear();
    primaryMullionAxis = null;
    selection = SelectionInfo.none;
    activeSubZone = null;
    isDrawingMode = true;
    drawingMode = 'new_frame';
    drawNextShapeAsShutterOnly = false;
    drawnLeft = null;
    drawnTop = null;
    copyPreviousFrameSize = false;
    _frameColor = FrameColor.white;
    _selectedDbColor = _defaultFrameColor();
    _selectedAccessoryColor = null;

    // Reset slants
    topSlantLeftY = 0.0;
    topSlantRightY = 0.0;
    bottomSlantLeftY = 0.0;
    bottomSlantRightY = 0.0;
    archHeight = 0.0;
    hasSideCovers = true;
    useCustomSideCoverLayout = false;
    sideCoverSegments = [];
    hiddenSideCoverSegments = {};

    // Clear histories
    _history.clear();
    _redoHistory.clear();

    notifyListeners();
  }

  List<double> getVerticalFrameJoints() {
    if (!coupleFrames) return [];
    final joints = <double>[];
    final jointT = profileThickness * 2;
    for (int i = 0; i < zones.length; i++) {
      final z1 = zones[i];
      for (int j = i + 1; j < zones.length; j++) {
        final z2 = zones[j];
        if (((z1.boundary.right - z2.boundary.left).abs() - jointT).abs() <=
            2.0) {
          double xCenter = (z1.boundary.right + z2.boundary.left) / 2;
          if (!joints.contains(xCenter)) {
            joints.add(xCenter);
          }
        } else if (((z2.boundary.right - z1.boundary.left).abs() - jointT)
                .abs() <=
            2.0) {
          double xCenter = (z2.boundary.right + z1.boundary.left) / 2;
          if (!joints.contains(xCenter)) {
            joints.add(xCenter);
          }
        }
      }
    }
    joints.sort();
    return joints;
  }

  List<double> getHorizontalFrameJoints() {
    if (!coupleFrames) return [];
    final joints = <double>[];
    final jointT = profileThickness * 2;
    for (int i = 0; i < zones.length; i++) {
      final z1 = zones[i];
      for (int j = i + 1; j < zones.length; j++) {
        final z2 = zones[j];
        if (((z1.boundary.bottom - z2.boundary.top).abs() - jointT).abs() <=
            2.0) {
          double yCenter = (z1.boundary.bottom + z2.boundary.top) / 2;
          if (!joints.contains(yCenter)) {
            joints.add(yCenter);
          }
        } else if (((z2.boundary.bottom - z1.boundary.top).abs() - jointT)
                .abs() <=
            2.0) {
          double yCenter = (z2.boundary.bottom + z1.boundary.top) / 2;
          if (!joints.contains(yCenter)) {
            joints.add(yCenter);
          }
        }
      }
    }
    joints.sort();
    return joints;
  }

  List<Rect> getFrameRects() {
    final List<List<WindowZone>> groups = [];
    final double jointT = profileThickness * 2;

    for (final zone in zones) {
      final List<int> connectedGroupIndices = [];
      for (int i = 0; i < groups.length; i++) {
        bool isConnected = false;
        for (final other in groups[i]) {
          // Check vertical adjacency
          if ((zone.boundary.right - other.boundary.left).abs() <
                  jointT - 2.0 ||
              (other.boundary.right - zone.boundary.left).abs() <
                  jointT - 2.0) {
            double overlapTop = math.max(zone.boundary.top, other.boundary.top);
            double overlapBottom = math.min(
              zone.boundary.bottom,
              other.boundary.bottom,
            );
            if (overlapTop < overlapBottom - 5.0) {
              isConnected = true;
            }
          }

          // Check horizontal adjacency
          if ((zone.boundary.bottom - other.boundary.top).abs() <
                  jointT - 2.0 ||
              (other.boundary.bottom - zone.boundary.top).abs() <
                  jointT - 2.0) {
            double overlapLeft = math.max(
              zone.boundary.left,
              other.boundary.left,
            );
            double overlapRight = math.min(
              zone.boundary.right,
              other.boundary.right,
            );
            if (overlapLeft < overlapRight - 5.0) {
              isConnected = true;
            }
          }

          if (isConnected) break;
        }
        if (isConnected) {
          connectedGroupIndices.add(i);
        }
      }

      if (connectedGroupIndices.isEmpty) {
        groups.add([zone]);
      } else {
        final List<WindowZone> mergedGroup = [zone];
        connectedGroupIndices.sort((a, b) => b.compareTo(a));
        for (final idx in connectedGroupIndices) {
          mergedGroup.addAll(groups[idx]);
          groups.removeAt(idx);
        }
        groups.add(mergedGroup);
      }
    }

    final List<Rect> rects = [];
    final double t = profileThickness;
    for (final group in groups) {
      double minL = group[0].boundary.left;
      double maxR = group[0].boundary.right;
      double minT = group[0].boundary.top;
      double maxB = group[0].boundary.bottom;

      for (final z in group) {
        if (z.boundary.left < minL) minL = z.boundary.left;
        if (z.boundary.right > maxR) maxR = z.boundary.right;
        if (z.boundary.top < minT) minT = z.boundary.top;
        if (z.boundary.bottom > maxB) maxB = z.boundary.bottom;
      }

      rects.add(Rect.fromLTRB(minL - t, minT - t, maxR + t, maxB + t));
    }

    return rects;
  }
}

class PlacedFrame {
  WindowModel model;
  Offset position;

  PlacedFrame({required this.model, required this.position});
}

String? extractSizeDigits(String name) {
  final regExp = RegExp(r'\d+(\.\d+)?');
  final match = regExp.firstMatch(name);
  if (match == null) return null;
  return match.group(0)!.replaceAll('.', '');
}

String? getComponentSize(Map<String, dynamic> component) {
  final meas = (component['measurement'] ?? '').toString().trim();
  if (meas.isNotEmpty) {
    return meas.replaceAll('.', '').replaceAll(',', '');
  }
  return extractSizeDigits(component['name'].toString());
}
