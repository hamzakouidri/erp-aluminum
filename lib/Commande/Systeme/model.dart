// Force compile sync trigger 2
import 'dart:math' as math;
import 'dart:async';
import 'glass_joint_fit.dart';
import 'profile_selector_dialog.dart'
    show CatalogCandidateResolver, CatalogCandidateQuery, AccessoryDrawingMode;
import 'package:flutter/material.dart';
import '../../sql_database.dart';
import 'package:database_data/utils/real_color_resolver.dart';

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

const double kDefaultGlassPaneThickness = 5.0;

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

/// Recognizes the legacy and Arabic spellings used for bardage in catalog data.
bool isBardagePanelSubtype(String? value) {
  final normalized = (value ?? '')
      .trim()
      .toLowerCase()
      .replaceAll('\u0640', '')
      .replaceAll(RegExp(r'[\u064B-\u065F\u0670]'), '');
  return normalized.contains('bardage') ||
      normalized.contains('بارداج') ||
      normalized.contains('بارداش') ||
      normalized.contains('برداج') ||
      normalized.contains('برداش') ||
      RegExp(r'ب(?:ا)?ر(?:ا)?د(?:ا)?[جش]').hasMatch(normalized);
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

/// One exposed edge of a physical frame in a multi-frame drawing. [start]
/// and [end] are measured on the edge axis; [coordinate] is the fixed x/y
/// position of that edge in the drawing.
class FrameEdgeSegment {
  final String side;
  final double start;
  final double end;
  final double coordinate;

  const FrameEdgeSegment({
    required this.side,
    required this.start,
    required this.end,
    required this.coordinate,
  });

  double get length => math.max(0.0, end - start);
}

/// One meeting line between two physical frames that needs a Cache-rainure.
/// The profile is fitted once on the inside and once on the outside.
class FrameCacheRainureContact {
  final Rect firstFrame;
  final Rect secondFrame;
  final bool isVertical;
  final double coordinate;
  final double start;
  final double end;

  /// The two faces may be supplied by different series when two compatible
  /// frames from different systems meet.
  final bool insideUsesSlidingSeries;
  final bool outsideUsesSlidingSeries;

  const FrameCacheRainureContact({
    required this.firstFrame,
    required this.secondFrame,
    required this.isVertical,
    required this.coordinate,
    required this.start,
    required this.end,
    required this.insideUsesSlidingSeries,
    required this.outsideUsesSlidingSeries,
  });

  double get length => math.max(0.0, end - start);
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
  final int? linkedRenfortId;
  final double renfortDeduction;
  final String? imagePath;
  final bool allowsSideCover;
  final bool? designIntegratedSideCover;

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
    this.linkedRenfortId,
    this.renfortDeduction = 140.0,
    this.imagePath,
    this.allowsSideCover = true,
    this.designIntegratedSideCover,
  }) : thickness = profileThickness ?? thickness;

  factory AluminumSection.fromMap(Map<String, dynamic> map) {
    double readDouble(String key) {
      final value = map[key];
      return value is num
          ? value.toDouble()
          : double.tryParse(value?.toString() ?? '') ?? 0.0;
    }

    bool readBool(Object? value, {bool fallback = true}) {
      if (value is bool) return value;
      if (value is num) return value != 0;
      if (value is String) {
        final normalized = value.trim().toLowerCase();
        if (normalized == '1' || normalized == 'true' || normalized == 'yes') {
          return true;
        }
        if (normalized == '0' || normalized == 'false' || normalized == 'no') {
          return false;
        }
      }
      return fallback;
    }

    bool? readOptionalBool(Object? value) {
      if (value == null) return null;
      return readBool(value, fallback: false);
    }

    return AluminumSection(
      id: map['id'],
      seriesId: map['series_id'],
      code: map['code'],
      name: map['name'],
      type: map['type'],
      thickness: (map['thickness'] as num?)?.toDouble() ?? 0.0,
      glassDeduction: (map['glass_deduction'] as num?)?.toDouble() ?? 0.0,
      weightPerMeter: (map['weight_per_meter'] as num?)?.toDouble() ?? 0.0,
      couvreJointWidth: readDouble('couvre_joint_width'),
      couvreJointThickness: readDouble('couvre_joint_thickness'),
      cuttingDeduction: (map['cutting_deduction'] as num?)?.toDouble() ?? 0.0,
      visibleWidth: readDouble('visible_width'),
      visibleWidth2: readDouble('visible_width_2'),
      sashOverlap: (map['sash_overlap'] as num?)?.toDouble() ?? 0.0,
      barLength: (map['bar_length'] as num?)?.toDouble() ?? 6.0,
      isFrame: (map['is_frame'] as int?) == 1,
      isSash: (map['is_sash'] as int?) == 1,
      isMullion: (map['is_mullion'] as int?) == 1,
      maxGlassThickness:
          (map['max_glass_thickness'] as num?)?.toDouble() ?? 0.0,
      linkedParcloseDoubleId: map['linked_parclose_double_id'] as int?,
      linkedRenfortId: map['linked_renfort_id'] is num
          ? (map['linked_renfort_id'] as num).toInt()
          : int.tryParse(map['linked_renfort_id']?.toString() ?? ''),
      renfortDeduction: readDouble('renfort_deduction') > 0
          ? readDouble('renfort_deduction')
          : 140.0,
      imagePath: map['image_path']?.toString(),
      // Role-specific options returned by getDesignSectionsForRoles override
      // the base section capability for the current series.
      allowsSideCover: readBool(
        map['design_allows_side_cover'] ?? map['allows_side_cover'],
      ),
      designIntegratedSideCover: readOptionalBool(
        map['design_integrated_side_cover'],
      ),
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
      'linked_renfort_id': linkedRenfortId,
      'renfort_deduction': renfortDeduction,
      'image_path': imagePath,
      'allows_side_cover': allowsSideCover ? 1 : 0,
      if (designIntegratedSideCover != null)
        'design_integrated_side_cover': designIntegratedSideCover! ? 1 : 0,
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
      value.contains('كوليس') ||
      // TPR/HPS are commercial names for sliding systems. Some catalogue
      // rows store only "Aluminium" in type, so the series name must also be
      // accepted when classifying the drawing mode.
      value.contains('tpr') ||
      value.contains('tpi') ||
      value.contains('hps');
}

String normalizeSeriesDesignRoleKey(dynamic raw) {
  final value = raw?.toString().trim().toLowerCase() ?? '';
  // Face-to-face is entered in the catalogue by users with several
  // spellings.  Keep one canonical role so the drawing, BOM and selectors
  // all resolve the same rule without looking at a series name.
  final compact = value
      .replaceAll('-', '_')
      .replaceAll(' ', '_')
      .replaceAll(RegExp(r'_+'), '_');
  if (const {
    'face_to_face',
    'face2face',
    'face_2_face',
    'montant_face_to_face',
    'قائم_face_to_face',
    'فيس_تو_فيس',
  }.contains(compact)) {
    return 'face_to_face';
  }
  if (const {
    'reducer',
    'reducteur',
    'réducteur',
    'réducteure',
    'ريديكتور',
    'مخفض الزجاج',
  }.contains(value)) {
    return 'reducer';
  }
  return value;
}

bool isOpeningSeriesForDrawing(
  AluminumSeries series,
  AluminumProfileSystem profile,
) {
  final value = '${series.type} ${series.name}'.toLowerCase().trim();
  // A mixed system must never offer the same series in both selectors. Some
  // legacy names contain both opening and sliding words, so sliding wins.
  if (isSlidingSeriesForDrawing(series)) return false;
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

AluminumProfileSystem? profileSystemForSeries(
  Iterable<AluminumProfileSystem> systems,
  AluminumSeries? series,
) {
  if (series == null) return null;
  for (final system in systems) {
    if (system.id == series.profileId ||
        system.series.any((candidate) => candidate.id == series.id)) {
      return system;
    }
  }
  return null;
}

/// Opening and sliding series must come from the same catalogue system.
///
/// `Profile.id` is the stable system identity; its `type` is only the
/// material label. Comparing only `type` allowed an opening series from one
/// aluminium system to be paired with a sliding series from another one.
/// That produced a drawing made from two unrelated systems, even though both
/// rows happened to say "Aluminium". A different profile row is therefore
/// never a valid pairing, regardless of its material label.
bool profileSystemsShareMaterial(
  AluminumProfileSystem first,
  AluminumProfileSystem second,
) {
  return first.id == second.id;
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
  final List<Map<String, dynamic>> fittedJoints;
  final bool? glazingFitValid;

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
    this.fittedJoints = const [],
    this.glazingFitValid,
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
    fittedJoints: fittedJoints,
    glazingFitValid: glazingFitValid,
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
    List<Map<String, dynamic>>? fittedJoints,
    bool? glazingFitValid,
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
    fittedJoints: fittedJoints ?? this.fittedJoints,
    glazingFitValid: glazingFitValid ?? this.glazingFitValid,
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
      final tOut = (thicknessOuter ?? kDefaultGlassPaneThickness)
          .toStringAsFixed(0);
      final tIn = (thicknessInner ?? kDefaultGlassPaneThickness)
          .toStringAsFixed(0);
      final tInter = intercallThickness.toStringAsFixed(0);
      return '$tOut+$tInter+$tIn';
    } else {
      final tOut = (thicknessOuter ?? kDefaultGlassPaneThickness)
          .toStringAsFixed(0);
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
          finishKws = const ['بارداج', 'بارداش', 'برداج', 'برداش', 'bardage'];
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
      final tOut = thicknessOuter ?? kDefaultGlassPaneThickness;
      final tIn = thicknessInner ?? kDefaultGlassPaneThickness;
      return tOut + intercallThickness.toDouble() + tIn;
    } else if (structure == GlassStructure.closed) {
      return getPanelThickness(allGlassCache);
    } else {
      return thicknessOuter ?? kDefaultGlassPaneThickness;
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

  /// Physical rails in the frame. This is deliberately independent from
  /// [slidingSashesCount]: three/four leaves may run on two or more rails.
  int slidingTrackCount;
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
  Map<String, bool> slidingMontantSlim;
  double middleHingeDragOffset;
  double doubleSashRatio;

  /// Whether the exceptional two-handle configuration is enabled.
  /// A double sash normally has a handle only on its active leaf.
  bool doubleSashHasTwoHandles;

  /// Sliding-only options are stored on the zone, not globally on the
  /// drawing.  This is important when a drawing contains more than one
  /// sliding frame: enabling Face-to-Face or the optional central handle on
  /// one frame must never alter its neighbour.
  bool slidingFaceToFace;
  bool slidingCentralHandle;

  /// The second middle handle is visual-only: it is listed as a handle in
  /// the BOM but must not create a second espagnolette, gache or kit.
  bool slidingSecondCentralHandle;
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
    this.slidingTrackCount = 2,
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
    Map<String, bool>? slidingMontantSlim,
    this.middleHingeDragOffset = 0.0,
    this.doubleSashRatio = 0.5,
    this.doubleSashHasTwoHandles = false,
    this.slidingFaceToFace = false,
    this.slidingCentralHandle = false,
    this.slidingSecondCentralHandle = false,
    this.disabledVerticalDivisions = const {},
    this.disabledHorizontalDivisions = const {},
    this.primaryDivisionAxis,
    this.rightPrimaryDivisionAxis,
    this.isSubdivided = false,
    this.hasSashPlintheBottom = false,
    Map<String, GlassSpecification>? cellGlassSpec,
  }) : glass = glass ?? globalDefaultGlass,
       cellGlassSpec = cellGlassSpec ?? const {},
       slidingMontantReinforced = Map<String, bool>.from(
         slidingMontantReinforced ??
             const {
               'lateral_left': false,
               'lateral_right': false,
               'central_left': false,
               'central_right': false,
             },
       ),
       slidingMontantSlim = Map<String, bool>.from(
         slidingMontantSlim ?? const {},
       );

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
    slidingTrackCount: slidingTrackCount,
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
    slidingMontantSlim: Map.from(slidingMontantSlim),
    middleHingeDragOffset: middleHingeDragOffset,
    doubleSashRatio: doubleSashRatio,
    doubleSashHasTwoHandles: doubleSashHasTwoHandles,
    slidingFaceToFace: slidingFaceToFace,
    slidingCentralHandle: slidingCentralHandle,
    slidingSecondCentralHandle: slidingSecondCentralHandle,
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

  WindowZone cloneForSplit(Rect newBoundary) => WindowZone(
    id: UniqueKey().toString(),
    handlePositionRatio: handlePositionRatio,
    useClassicHandle: useClassicHandle,
    useOctoHandle: useOctoHandle,
    usePvcHandleOnAlu: usePvcHandleOnAlu,
    boundary: newBoundary,
    content: content,
    isSelected: false,
    glass: glass.clone(),
    openAngle: openAngle,
    openDirection: openDirection,
    sashColor: sashColor,
    selectedDbColor: selectedDbColor == null
        ? null
        : Map<String, dynamic>.from(selectedDbColor!),
    isSash105: isSash105,
    sashThickness: sashThickness,
    innerH: innerH,
    innerV: innerV,
    slidingSashesCount: slidingSashesCount,
    slidingTrackCount: slidingTrackCount,
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
    slidingFaceToFace: slidingFaceToFace,
    slidingCentralHandle: slidingCentralHandle,
    slidingSecondCentralHandle: slidingSecondCentralHandle,
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
    int? slidingTrackCount,
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
    Map<String, bool>? slidingMontantSlim,
    double? middleHingeDragOffset,
    double? doubleSashRatio,
    bool? doubleSashHasTwoHandles,
    bool? slidingFaceToFace,
    bool? slidingCentralHandle,
    bool? slidingSecondCentralHandle,
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
    slidingTrackCount: slidingTrackCount ?? this.slidingTrackCount,
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
    slidingMontantSlim: slidingMontantSlim ?? Map.from(this.slidingMontantSlim),
    middleHingeDragOffset: middleHingeDragOffset ?? this.middleHingeDragOffset,
    doubleSashRatio: doubleSashRatio ?? this.doubleSashRatio,
    doubleSashHasTwoHandles:
        doubleSashHasTwoHandles ?? this.doubleSashHasTwoHandles,
    slidingFaceToFace: slidingFaceToFace ?? this.slidingFaceToFace,
    slidingCentralHandle: slidingCentralHandle ?? this.slidingCentralHandle,
    slidingSecondCentralHandle:
        slidingSecondCentralHandle ?? this.slidingSecondCentralHandle,
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
  final Map<String, int>? mullionCreationOrder;
  final int? mullionStepCounter;

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
    this.internalSlidingSideCoverOverride, [
    this.mullionCreationOrder,
    this.mullionStepCounter,
  ]);
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
    final realHexColor = parseRealHexColor(dbColor['hex_code']);
    if (realHexColor != null &&
        !const {
          'FFF',
          'FFFFFF',
          'FFFFFFFF',
          'F5F5DC',
          '9E9E9E',
          'FF9E9E9E',
        }.contains(hex)) {
      return gradientFromColor(realHexColor);
    }

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
        name.contains('chompagne') ||
        name.contains('شامبان') ||
        name.contains('شمبان') ||
        name.contains('شومبان') ||
        name.contains('شامباني') ||
        name.contains('شمباني') ||
        name.contains('شومباني') ||
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
    final realHexColor = parseRealHexColor(dbColor['hex_code']);
    if (realHexColor != null &&
        !const {
          'FFF',
          'FFFFFF',
          'FFFFFFFF',
          '9E9E9E',
          'FF9E9E9E',
        }.contains(hex)) {
      final hsl = HSLColor.fromColor(realHexColor);
      return hsl
          .withLightness((hsl.lightness - 0.22).clamp(0.0, 1.0))
          .toColor();
    }

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
        name.contains('chompagne') ||
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

bool slidingFrameRoleAllowedForDrawing(
  Map<String, dynamic> options, {
  required bool hasShutter,
  required bool isCaissonTunnel,
  required bool isPvc,
  bool isFrameExtension = false,
}) {
  bool truthy(dynamic value, {bool fallback = false}) {
    if (value == null) return fallback;
    if (value is bool) return value;
    if (value is num) return value != 0;
    final text = value.toString().trim().toLowerCase();
    if (text == '1' || text == 'true' || text == 'yes') return true;
    if (text == '0' || text == 'false' || text == 'no') return false;
    return fallback;
  }

  if (!hasShutter) return true;
  if (!truthy(options['allowed_with_shutter'], fallback: true)) return false;
  // The integrated-cover restriction concerns the main frame, not the
  // additional rail profile. Extensions retain their own shutter permission.
  if (isFrameExtension || isCaissonTunnel || isPvc) return true;
  final integrated = truthy(
    options['design_integrated_side_cover'] ?? options['integrated_side_cover'],
  );
  final rawWidth = options['couvre_joint_width'];
  final coverWidth = rawWidth is num
      ? rawWidth.toDouble()
      : double.tryParse(rawWidth?.toString() ?? '') ?? 0;
  final label =
      '${options['section_name'] ?? options['name'] ?? ''} '
              '${options['section_type'] ?? options['type'] ?? ''}'
          .toLowerCase();
  return !(integrated ||
      coverWidth > 0 ||
      label.contains('مدمج') ||
      label.contains('intégré') ||
      label.contains('integre') ||
      label.contains('monobloc') ||
      label.contains('sunset') ||
      label.contains('sontara') ||
      label.contains('suntara'));
}

bool catalogEspagnoletteRuleMatches(
  Map<String, dynamic> rule, {
  required double effectiveHeightMm,
}) {
  double? number(dynamic value) => value is num
      ? value.toDouble()
      : double.tryParse(value?.toString().replaceAll(',', '.') ?? '');
  final min = number(rule['min_height_mm']);
  final max = number(rule['max_height_mm']);
  if (min != null && effectiveHeightMm < min) return false;
  if (max != null && effectiveHeightMm > max) return false;
  return true;
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
    if (actualNumbers.intersection(candidateNumbers).isNotEmpty) {
      score += 150;
    }
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
  double _lastResolvedVitrageJointThickness = 0.0;

  double _glassPaneThicknessOrDefault(double? value) =>
      value != null && value > 0 ? value : kDefaultGlassPaneThickness;

  double _readPositiveDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString().replaceAll(',', '.') ?? '') ?? 0.0;
  }

  Map<String, dynamic>? selectedVitrageJointOverride() {
    final exact = componentOverrides['جوان الزجاج (Joint Vitrage)'];
    if (exact is Map) return Map<String, dynamic>.from(exact);
    for (final entry in componentOverrides.entries) {
      final key = entry.key.toLowerCase();
      if (entry.value is Map &&
          (key.contains('joint vitrage') ||
              key.contains('joint de vitrage') ||
              key.contains('جوان الزجاج') ||
              key.contains('فيتراج'))) {
        return Map<String, dynamic>.from(entry.value as Map);
      }
    }
    return null;
  }

  double selectedVitrageJointThickness({double fallback = 0.0}) {
    if (isPVC) return fallback;
    final selected = selectedVitrageJointOverride();
    final thickness = _readPositiveDouble(selected?['thickness']);
    if (thickness > 0) return thickness;
    if (_lastResolvedVitrageJointThickness > 0) {
      return _lastResolvedVitrageJointThickness;
    }
    return fallback;
  }

  Map<String, dynamic>? selectedBourrageJointOverride({
    bool doubleGlass = true,
  }) {
    final preferredKeys = doubleGlass
        ? const [
            'جوان البوراج للزجاج المزدوج (Joint Bourrage Double)',
            'جوان البوراج (Joint Bourrage)',
          ]
        : const [
            'جوان البوراج للزجاج المفرد (Joint Bourrage Simple)',
            'جوان البوراج (Joint Bourrage)',
          ];
    for (final key in preferredKeys) {
      final value = componentOverrides[key];
      if (value is Map) return Map<String, dynamic>.from(value);
    }
    return null;
  }

  double selectedBourrageJointThickness({
    bool doubleGlass = true,
    double fallback = 0.0,
  }) {
    final thickness = _readPositiveDouble(
      selectedBourrageJointOverride(doubleGlass: doubleGlass)?['thickness'],
    );
    return thickness > 0 ? thickness : fallback;
  }

  double vitrageJointAllowanceForGlass(
    GlassSpecification specification, {
    bool? sliding,
  }) {
    final jointThickness = selectedVitrageJointThickness();
    if (jointThickness <= 0) return 0.0;
    final usesSliding = sliding ?? systemMode == 'sliding';
    if (usesSliding) {
      return jointThickness * (specification.jointTwoSides ? 2.0 : 1.0);
    }
    return jointThickness +
        selectedBourrageJointThickness(
          doubleGlass: specification.structure == GlassStructure.double,
          fallback: 2.0,
        );
  }

  double glassPackThicknessIncludingVitrageJoint(
    GlassSpecification specification, {
    bool? sliding,
  }) {
    return specification.totalThickness(allGlassCache) +
        vitrageJointAllowanceForGlass(specification, sliding: sliding);
  }

  List<int> _availableIntercallThicknesses() {
    final values =
        availableIntercalls
            .map((item) => _readPositiveDouble(item['thickness']).round())
            .where((thickness) => thickness > 0)
            .toSet()
            .toList()
          ..sort();
    if (values.isNotEmpty) return values;
    return const [6, 8, 10, 12, 14, 16, 18, 20, 22, 24];
  }

  int? _nearestIntercallThickness(double target) {
    if (target <= 0) return null;
    final choices = _availableIntercallThicknesses();
    if (choices.isEmpty) return null;
    int best = choices.first;
    double bestDiff = double.infinity;
    for (final thickness in choices) {
      final diff = (thickness.toDouble() - target).abs();
      if (diff < bestDiff) {
        best = thickness;
        bestDiff = diff;
      }
    }
    return bestDiff <= 2.5 ? best : null;
  }

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
  String? persistedDrawingImagePath;
  String? persistedDrawingImageBase64;
  bool invoiceTableEdited = false;
  String? position;
  String? loadedSeriesName;
  String? loadedSlidingSeriesName;
  int? loadedSeriesId;
  int? loadedSlidingSeriesId;
  Map<String, dynamic>? seriesDesignConfig;
  final Map<int, Set<String>> _seriesDesignRoleKeys = {};
  final Map<int, Map<String, Set<int>>> _seriesDesignRoleSectionIds = {};
  final Map<int, Map<String, Map<int, String>>> _seriesDesignRoleUsageScopes =
      {};
  final Map<int, Map<String, Map<int, bool>>> _seriesDesignRoleAllowsSideCover =
      {};
  final Map<int, Map<String, Map<int, bool>>>
  _seriesDesignRoleIntegratedSideCover = {};
  final Map<int, Map<String, Map<int, Map<String, dynamic>>>>
  _seriesDesignRoleOptions = {};

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

  bool get hasOpeningSashZones => zones.any(
    (z) =>
        z.content == ZoneContent.singleSash ||
        z.content == ZoneContent.doubleSash,
  );

  bool get canUseOpeningOnlyOptions => hasOpeningSashZones;

  void _clearOpeningOnlyOptionsIfUnavailable() {
    if (canUseOpeningOnlyOptions) return;

    final hadPlinthe =
        hasFramePlintheBottom || zones.any((z) => z.hasSashPlintheBottom);
    useSystemOB = false;
    useDemiOB = false;
    useVerrouCentral = false;
    hasFramePlintheBottom = false;
    for (final zone in zones) {
      zone.hasSashPlintheBottom = false;
    }
    if (hadPlinthe) {
      hasBottomFrame = true;
      showBottomWall = true;
      updateBottomZoneBoundaries();
    }
  }

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

  /// In mixed drawings, the opening series owns the frame only when the
  /// drawing actually contains an opening sash. A sliding-only drawing may
  /// still contain fixed-glass or empty zones; those zones must not make the
  /// resolver borrow an opening frame or sash.
  bool get usesSlidingPrimaryProfiles {
    if (systemMode == 'sliding') return true;
    if (systemMode != 'mixed') return false;

    final occupiedZones = zones
        .where((zone) => zone.content != ZoneContent.empty)
        .toList();
    final hasSlidingZone = occupiedZones.any(
      (zone) => zone.content == ZoneContent.slidingSash,
    );
    final hasOpeningSash = occupiedZones.any(
      (zone) =>
          zone.content == ZoneContent.singleSash ||
          zone.content == ZoneContent.doubleSash,
    );
    return hasSlidingZone && !hasOpeningSash;
  }

  bool _isPvcSeries(AluminumSeries? series) {
    if (series == null) return false;
    final seriesType = (series.type).trim().toLowerCase();
    final seriesName = series.name.trim().toLowerCase();
    if (seriesType == 'pvc' || seriesName.contains('pvc')) return true;
    try {
      final system = availableSystems.firstWhere(
        (s) => s.id == series.profileId,
      );
      return system.type.trim().toLowerCase() == 'pvc';
    } catch (_) {
      return false;
    }
  }

  void _rememberSeriesRoleKeys(
    AluminumSeries series,
    List<Map<String, dynamic>> rows,
  ) {
    _seriesDesignRoleKeys[series.id] = rows
        .map((row) => normalizeSeriesDesignRoleKey(row['role_key']))
        .where((role) => role.isNotEmpty)
        .toSet();
    final roleIds = <String, Set<int>>{};
    final roleScopes = <String, Map<int, String>>{};
    final roleAllowsSideCover = <String, Map<int, bool>>{};
    final roleIntegratedSideCover = <String, Map<int, bool>>{};
    final roleOptions = <String, Map<int, Map<String, dynamic>>>{};
    bool? readBool(Object? value) {
      if (value is bool) return value;
      if (value is num) return value != 0;
      if (value is String) {
        final normalized = value.trim().toLowerCase();
        if (normalized == '1' || normalized == 'true' || normalized == 'yes') {
          return true;
        }
        if (normalized == '0' || normalized == 'false' || normalized == 'no') {
          return false;
        }
      }
      return null;
    }

    for (final row in rows) {
      final role = normalizeSeriesDesignRoleKey(row['role_key']);
      final rawId = row['section_id'];
      final sectionId = rawId is num
          ? rawId.toInt()
          : int.tryParse(rawId?.toString() ?? '');
      if (role.isEmpty || sectionId == null) continue;
      roleIds.putIfAbsent(role, () => <int>{}).add(sectionId);
      roleOptions.putIfAbsent(role, () => {})[sectionId] =
          Map<String, dynamic>.from(row);
      roleScopes.putIfAbsent(role, () => {})[sectionId] =
          row['usage_scope']?.toString().trim().toLowerCase() ?? 'auto';
      final allowsSideCover = readBool(row['allows_side_cover']);
      if (allowsSideCover != null) {
        roleAllowsSideCover.putIfAbsent(role, () => {})[sectionId] =
            allowsSideCover;
      }
      final integratedSideCover = readBool(row['integrated_side_cover']);
      if (integratedSideCover != null) {
        roleIntegratedSideCover.putIfAbsent(role, () => {})[sectionId] =
            integratedSideCover;
      }
    }
    _seriesDesignRoleSectionIds[series.id] = roleIds;
    _seriesDesignRoleUsageScopes[series.id] = roleScopes;
    _seriesDesignRoleAllowsSideCover[series.id] = roleAllowsSideCover;
    _seriesDesignRoleIntegratedSideCover[series.id] = roleIntegratedSideCover;
    _seriesDesignRoleOptions[series.id] = roleOptions;
  }

  bool _roleScopeMatches(String? scope, {required bool sliding}) {
    final normalized = scope?.trim().toLowerCase() ?? 'auto';
    return normalized.isEmpty ||
        normalized == 'auto' ||
        normalized == 'both' ||
        normalized == (sliding ? 'sliding' : 'opening');
  }

  bool _configuredSectionMatchesScope(
    AluminumSeries series,
    String roleKey,
    int sectionId, {
    required bool sliding,
  }) {
    final scope =
        _seriesDesignRoleUsageScopes[series.id]?[roleKey.trim()]?[sectionId];
    return _roleScopeMatches(scope, sliding: sliding);
  }

  AluminumSection _sectionWithConfiguredRoleOptions(
    AluminumSeries series,
    Iterable<String> roleKeys,
    AluminumSection section,
  ) {
    for (final rawRoleKey in roleKeys) {
      final roleKey = rawRoleKey.trim();
      if (roleKey.isEmpty ||
          _seriesDesignRoleSectionIds[series.id]?[roleKey]?.contains(
                section.id,
              ) !=
              true) {
        continue;
      }
      final allowsSideCover =
          _seriesDesignRoleAllowsSideCover[series.id]?[roleKey]?[section.id];
      final integratedSideCover =
          _seriesDesignRoleIntegratedSideCover[series.id]?[roleKey]?[section
              .id];
      if (allowsSideCover == null && integratedSideCover == null) {
        return section;
      }
      final map = section.toMap();
      if (allowsSideCover != null) {
        map['allows_side_cover'] = allowsSideCover ? 1 : 0;
        map['design_allows_side_cover'] = allowsSideCover ? 1 : 0;
      }
      if (integratedSideCover != null) {
        map['design_integrated_side_cover'] = integratedSideCover ? 1 : 0;
      }
      return AluminumSection.fromMap(map);
    }
    return section;
  }

  bool seriesHasConfiguredRoles(AluminumSeries? series) {
    if (series == null) return false;
    return _seriesDesignRoleKeys[series.id]?.isNotEmpty == true;
  }

  /// Returns whether the catalogue explicitly assigned this series to the
  /// opening or sliding drawing scope.  Names such as PBC or Anime are
  /// commercial system names and cannot reliably classify a series.
  bool seriesSupportsDrawingScope(
    AluminumSeries series,
    String scope, {
    AluminumProfileSystem? profile,
  }) {
    final normalizedScope = scope.trim().toLowerCase();
    final configuredScopes = <String>{};
    final roleScopes = _seriesDesignRoleUsageScopes[series.id];
    if (roleScopes != null) {
      for (final sectionScopes in roleScopes.values) {
        for (final value in sectionScopes.values) {
          final normalized = value.trim().toLowerCase();
          if (normalized == 'opening' ||
              normalized == 'sliding' ||
              normalized == 'both') {
            configuredScopes.add(normalized);
          }
        }
      }
    }

    if (configuredScopes.isNotEmpty) {
      return configuredScopes.contains(normalizedScope) ||
          configuredScopes.contains('both');
    }

    // Older catalogues have no explicit scope. Preserve their legacy
    // classifier as a fallback until the series is configured.
    return normalizedScope == 'sliding'
        ? isSlidingSeriesForDrawing(series)
        : profile != null && isOpeningSeriesForDrawing(series, profile);
  }

  /// Applies the drawing scope to the whole catalogue system, not only to
  /// the individual series that happen to have role rows. Older catalogues
  /// commonly configured roles for one representative series while keeping
  /// several other active series in the same opening/sliding family.
  bool seriesSupportsDrawingScopeInSystem(
    AluminumSeries series,
    String scope, {
    AluminumProfileSystem? profile,
  }) {
    final normalizedScope = scope.trim().toLowerCase();
    final system = profile ?? profileSystemForSeries(availableSystems, series);
    if (system == null) {
      return seriesSupportsDrawingScope(series, normalizedScope);
    }
    if (seriesSupportsDrawingScope(series, normalizedScope, profile: system)) {
      return true;
    }

    final oppositeScope = normalizedScope == 'sliding' ? 'opening' : 'sliding';
    if (seriesSupportsDrawingScope(series, oppositeScope, profile: system)) {
      return false;
    }

    // If at least one series in this system identifies the requested scope,
    // an otherwise unlabelled active series belongs to that family unless it
    // is recognizably from the opposite drawing.
    final hasSystemScope = system.series.any(
      (candidate) => seriesSupportsDrawingScope(
        candidate,
        normalizedScope,
        profile: system,
      ),
    );
    if (!hasSystemScope) return false;
    return normalizedScope == 'sliding'
        ? !isOpeningSeriesForDrawing(series, system)
        : !isSlidingSeriesForDrawing(series);
  }

  bool _hasLoadedRoleMetadata(AluminumSeries? series) {
    return series != null && _seriesDesignRoleSectionIds.containsKey(series.id);
  }

  List<AluminumSection> _sideCoversForSeries(AluminumSeries series) {
    final configuredIds = _seriesDesignRoleSectionIds[series.id]?['side_cover'];
    if (!_hasLoadedRoleMetadata(series) ||
        configuredIds == null ||
        configuredIds.isEmpty) {
      return const <AluminumSection>[];
    }
    return series.sections
        .where((section) => configuredIds.contains(section.id))
        .toList(growable: false);
  }

  void _synchronizeSharedSideCover() {
    // The outer frame owns its couvre-joint.  Never scan sibling series in a
    // profile system: a similarly named PVC/aluminium cover from another
    // family must not be injected into the current drawing.
    final owner = activeFrameSeries;
    final covers = owner == null
        ? const <AluminumSection>[]
        : _sideCoversForSeries(owner);

    AluminumSection? selected;
    final selectedId =
        selectedSideCover?.id ??
        (sideCoverOverride?['id'] is num
            ? (sideCoverOverride!['id'] as num).toInt()
            : int.tryParse('${sideCoverOverride?['id'] ?? ''}'));
    final selectedCode =
        (selectedSideCover?.code ??
                sideCoverOverride?['code']?.toString() ??
                '')
            .trim()
            .toLowerCase();
    for (final cover in covers) {
      if ((selectedId != null && cover.id == selectedId) ||
          (selectedCode.isNotEmpty &&
              cover.code.trim().toLowerCase() == selectedCode)) {
        selected = cover;
        break;
      }
    }

    if (selected == null && covers.isNotEmpty) {
      selected = covers.first;
    }
    if (selected == null) {
      selectedSideCover = null;
      sideCoverOverride = null;
      // An integrated couvre-joint belongs to the selected frame and does
      // not require a separate catalogue row. Do not turn off the global
      // cover switch merely because the shared standalone catalogue is empty.
      // This also preserves an explicit user choice when switching series.
      return;
    }

    selectedSideCover = selected;
    final oldOverride = sideCoverOverride;
    sideCoverOverride = selected.toMap();
    if (oldOverride?['calculated_price'] != null) {
      sideCoverOverride!['calculated_price'] = oldOverride!['calculated_price'];
    }
  }

  AluminumSeries? _seriesForConfiguredRole({bool? useSlidingSeries}) {
    if (useSlidingSeries == true) {
      return activeSlidingSeries ??
          (systemMode == 'sliding' || usesSlidingPrimaryProfiles
              ? activeSeries
              : null);
    }
    if (useSlidingSeries == false) return activeSeries;
    final useSliding = systemMode == 'sliding' || usesSlidingPrimaryProfiles;
    return useSliding ? (activeSlidingSeries ?? activeSeries) : activeSeries;
  }

  /// Resolves a single profile selected for a catalogue design role.
  ///
  /// An empty result is intentional: when a series has configured roles, a
  /// profile that is not assigned to the requested role must not be guessed
  /// from its name or type.
  AluminumSection? getConfiguredSectionForRole(
    String roleKey, {
    bool? useSlidingSeries,
  }) {
    final series = _seriesForConfiguredRole(useSlidingSeries: useSlidingSeries);
    if (series == null) return null;
    final configuredIds =
        _seriesDesignRoleSectionIds[series.id]?[roleKey.trim()] ??
        const <int>{};
    if (configuredIds.isEmpty) return null;
    final sliding =
        useSlidingSeries ??
        (systemMode == 'sliding' || usesSlidingPrimaryProfiles);
    for (final section in series.sections) {
      if (configuredIds.contains(section.id) &&
          _configuredSectionMatchesScope(
            series,
            roleKey,
            section.id,
            sliding: sliding,
          )) {
        return _sectionWithConfiguredRoleOptions(series, [roleKey], section);
      }
    }
    return null;
  }

  /// Resolves all profiles assigned to a catalogue design role.
  List<AluminumSection> getConfiguredSectionsForRole(
    String roleKey, {
    bool? useSlidingSeries,
  }) {
    final series = _seriesForConfiguredRole(useSlidingSeries: useSlidingSeries);
    if (series == null) return const <AluminumSection>[];
    final configuredIds =
        _seriesDesignRoleSectionIds[series.id]?[roleKey.trim()] ??
        const <int>{};
    if (configuredIds.isEmpty) return const <AluminumSection>[];
    final sliding =
        useSlidingSeries ??
        (systemMode == 'sliding' || usesSlidingPrimaryProfiles);
    return series.sections
        .where(
          (section) =>
              configuredIds.contains(section.id) &&
              _configuredSectionMatchesScope(
                series,
                roleKey,
                section.id,
                sliding: sliding,
              ),
        )
        .map(
          (section) =>
              _sectionWithConfiguredRoleOptions(series, [roleKey], section),
        )
        .toList(growable: false);
  }

  bool isConfiguredRoleRequired(String roleKey, {bool? useSlidingSeries}) {
    final series = _seriesForConfiguredRole(useSlidingSeries: useSlidingSeries);
    if (series == null) return false;
    final ids = _seriesDesignRoleSectionIds[series.id]?[roleKey.trim()];
    if (ids == null || ids.isEmpty) return false;
    final sliding =
        useSlidingSeries ??
        (systemMode == 'sliding' || usesSlidingPrimaryProfiles);
    return ids.any((id) {
      if (!_configuredSectionMatchesScope(
        series,
        roleKey,
        id,
        sliding: sliding,
      )) {
        return false;
      }
      final value =
          _seriesDesignRoleOptions[series.id]?[roleKey
              .trim()]?[id]?['is_required'];
      return value == true || value == 1 || value?.toString() == '1';
    });
  }

  bool seriesUsesReducer(AluminumSeries? series) {
    if (series == null) return false;
    return _seriesDesignRoleKeys[series.id]?.contains('reducer') == true;
  }

  bool _sectionHasIntegratedSideCover(AluminumSection section) {
    if (section.designIntegratedSideCover != null) {
      return section.designIntegratedSideCover!;
    }
    final name = section.name.toLowerCase();
    final type = section.type.toLowerCase();
    return section.couvreJointWidth > 0 ||
        name.contains('مدمج') ||
        name.contains('intégré') ||
        name.contains('integre') ||
        name.contains('monobloc') ||
        name.contains('sunset') ||
        name.contains('sontara') ||
        name.contains('suntara') ||
        type.contains('monobloc') ||
        type.contains('sunset') ||
        type.contains('sontara') ||
        type.contains('suntara');
  }

  bool _sectionIsSideCover(AluminumSection section) {
    final label = '${section.type} ${section.name}'.toLowerCase().replaceAll(
      '-',
      '_',
    );
    return label.contains('couvre') ||
        label.contains('couvre_joint') ||
        label.contains('couvrejoint') ||
        label.contains('side_cover') ||
        label.contains('sidecover') ||
        label.contains('cover') ||
        label.contains('غطاء') ||
        label.contains('كوفر') ||
        label.contains('كوفرجوا') ||
        label.contains('كوفرجوان') ||
        label.contains('كوفر جوان') ||
        label.contains('كفر') ||
        label.contains('كفرجون') ||
        label.contains('جانبي') ||
        label.contains('جوانب');
  }

  bool _sectionAllowsStandaloneSideCover(AluminumSection section) {
    return !_sectionHasIntegratedSideCover(section) && section.allowsSideCover;
  }

  bool _overrideAllowsStandaloneSideCover(Map<String, dynamic>? override) {
    if (override == null) return true;
    if (_overrideHasIntegratedSideCover(override)) return false;
    final rawAllowed =
        override['design_allows_side_cover'] ?? override['allows_side_cover'];
    if (rawAllowed is bool) return rawAllowed;
    if (rawAllowed is num) return rawAllowed != 0;
    if (rawAllowed is String) {
      final normalized = rawAllowed.trim().toLowerCase();
      return normalized != '0' && normalized != 'false' && normalized != 'no';
    }
    return true;
  }

  bool _frameMapWasManuallySelected(Map<String, dynamic>? override) {
    if (override == null) return false;
    return override['manual_selection'] == true ||
        override['is_manual_selection'] == true ||
        override['user_selected'] == true;
  }

  List<AluminumSection> _compatibleFrameCandidatesForSeries(
    AluminumSeries series,
    List<AluminumSection> frames,
  ) {
    if (!hasShutter || isCaissonTunnel || _isPvcSeries(series)) return frames;

    final sideCoverCapable = frames
        .where(_sectionAllowsStandaloneSideCover)
        .toList();
    if (sideCoverCapable.isNotEmpty) return sideCoverCapable;

    return frames
        .where((frame) => !_sectionHasIntegratedSideCover(frame))
        .toList();
  }

  AluminumSection _preferredFrameForSeries(
    List<AluminumSection> frames,
    AluminumSeries series,
  ) {
    if (frames.length <= 1) return frames.first;
    final seriesLabel = '${series.name} ${series.type}'.toLowerCase();
    String? family;
    if (seriesLabel.contains('67000') || seriesLabel.contains('67')) {
      family = '67';
    } else if (seriesLabel.contains('40000') || seriesLabel.contains('40')) {
      family = '40';
    }
    if (family == null) return frames.first;

    return frames.firstWhere(
      (frame) => '${frame.name} ${frame.code}'.toLowerCase().contains(family!),
      orElse: () => frames.first,
    );
  }

  /// Keeps the rail metadata entered in the series-role editor on the actual
  /// selected frame map. [AluminumSection] intentionally contains only the
  /// physical section fields, so converting it with `toMap()` used to discard
  /// `track_count` / `track_mode`; every frame then looked like the default
  /// two-rail base to the calculator.
  Map<String, dynamic> _slidingFrameMapWithRoleOptions(
    AluminumSection section,
    AluminumSeries series,
  ) {
    final result = section.toMap();
    final options = _seriesDesignRoleOptions[series.id]?['frame']?[section.id];
    if (options == null) return result;
    const optionKeys = <String>[
      'track_count',
      'track_mode',
      'supported_track_counts',
      'design_track_count',
      'design_track_mode',
      'design_supported_track_counts',
    ];
    for (final key in optionKeys) {
      final value = options[key];
      if (value == null) continue;
      final designKey = key.startsWith('design_') ? key : 'design_$key';
      result[designKey] = value;
    }
    return result;
  }

  int _requestedSlidingTrackCount() {
    var result = 2;
    for (final zone in zones) {
      if (zone.content != ZoneContent.slidingSash) continue;
      result = math.max(result, zone.slidingTrackCount.clamp(2, 7).toInt());
    }
    return result;
  }

  /// Prefer a complete frame explicitly configured for the requested rails.
  /// If the series has no such frame, retain the normal base-frame choice so
  /// the configured Complément dormant can add the missing rails.
  AluminumSection _preferredSlidingFrameForTrackCount(
    List<AluminumSection> frames,
    AluminumSeries series,
    int trackCount,
  ) {
    if (frames.length <= 1) return frames.first;
    final target = trackCount.clamp(2, 7).toInt();
    final exactComplete = frames.where((section) {
      final options =
          _seriesDesignRoleOptions[series.id]?['frame']?[section.id];
      final mode = options?['track_mode']?.toString().toLowerCase() ?? '';
      final rawCount = options?['track_count'];
      final count = rawCount is num
          ? rawCount.toInt()
          : int.tryParse(rawCount?.toString() ?? '');
      return mode == 'complete' && count == target;
    }).toList();
    if (exactComplete.isNotEmpty) {
      return _preferredFrameForSeries(exactComplete, series);
    }
    return _preferredFrameForSeries(frames, series);
  }

  bool _isFrameSection(AluminumSection section) {
    final type = section.type.toLowerCase();
    return section.isFrame ||
        type == 'frame' ||
        type.contains('cadre') ||
        type.contains('إطار') ||
        type.contains('فريم');
  }

  /// Multi-frame drawings keep the side-cover option enabled by default.
  void _enforceMultiFramePlainFrameRule() {
    final previousThickness = profileThickness;
    final previousMullionThickness = mullionThickness;
    var changedFrame = false;
    final isMultiFrame = getFrameRects().length > 1;
    if (!isMultiFrame) {
      _multiFrameSideCoverManuallyEnabled = false;
      // A single-frame drawing keeps the user's side-cover state. It must not
      // be reset by notifyListeners or by an unrelated drawing edit.
      return;
    }

    // Joining frames changes their profile construction, not the user's
    // cover switch or individually hidden sides. Never reset these on notify.

    for (final sliding in [false, true]) {
      final series = sliding ? effectiveSlidingSeries : activeSeries;
      if (series == null) continue;
      final currentFrame = sliding
          ? slidingFrameOverride ?? getSlidingSectionByType('frame')?.toMap()
          : frameOverride ?? getSectionByType('frame')?.toMap();
      if (!_overrideHasIntegratedSideCover(currentFrame) &&
          (!hasSideCovers || _overrideAllowsStandaloneSideCover(currentFrame)))
        continue;
      final configured = getConfiguredSectionsForRole(
        'frame',
        useSlidingSeries: sliding,
      );
      final plainFrames = configured
          .where(
            (section) =>
                !_sectionHasIntegratedSideCover(section) &&
                (!hasSideCovers || _sectionAllowsStandaloneSideCover(section)),
          )
          .toList();
      if (plainFrames.isEmpty) continue;

      final selected = sliding
          ? _preferredSlidingFrameForTrackCount(
              plainFrames,
              series,
              _requestedSlidingTrackCount(),
            )
          : _preferredFrameForSeries(plainFrames, series);
      final plainFrame = sliding
          ? _slidingFrameMapWithRoleOptions(selected, series)
          : selected.toMap();
      changedFrame = true;
      if (sliding) {
        slidingFrameOverride = plainFrame;
      } else {
        frameOverride = plainFrame;
        selectedFrameCode = plainFrame['code']?.toString();
      }
    }

    if (changedFrame) {
      updateProfileThickness();
      _synchronizeDivisionGapsForSeries(
        previousThickness,
        previousMullionThickness,
      );
    }

    // These are already the side_cover role of the owning series. A cover's
    // own width/name must not classify it as an integrated FRAME.
    final separateCovers = availableSideCovers;
    if (separateCovers.isNotEmpty) {
      if (!separateCovers.any((cover) => cover.id == selectedSideCover?.id)) {
        selectedSideCover = separateCovers.first;
      }
      if (changedFrame || sideCoverOverride == null) {
        sideCoverOverride = selectedSideCover!.toMap();
      }
    }
  }

  String? slidingSeriesFamily({AluminumSeries? series}) {
    final source =
        series ??
        (systemMode == 'sliding' || usesSlidingPrimaryProfiles
            ? activeSlidingSeries
            : activeSeries);
    if (source == null) return null;
    final label = '${source.name} ${source.type}'.toLowerCase();
    if (label.contains('67000') ||
        label.contains('67 mil') ||
        label.contains('67m') ||
        label.contains('67 m') ||
        RegExp(r'(^|[^0-9])67([^0-9]|$)').hasMatch(label)) {
      return '67';
    }
    if (label.contains('40000') ||
        label.contains('40 mil') ||
        label.contains('40m') ||
        label.contains('40 m') ||
        RegExp(r'(^|[^0-9])40([^0-9]|$)').hasMatch(label)) {
      return '40';
    }
    if (label.contains('h36') ||
        label.contains('h 36') ||
        label.contains('hps') ||
        RegExp(r'(^|[^0-9])36([^0-9]|$)').hasMatch(label)) {
      return 'h36';
    }
    // TPR is a named sliding family in the catalogue (not a numeric
    // millimetre series). Keep it in the same family resolver so all
    // quantity/cost component rules can select it consistently.
    if (label.contains('tpr') || label.contains('tpi')) return 'tpr';
    return null;
  }

  bool get isSliding67Family => slidingSeriesFamily() == '67';

  bool get isSliding40Family => slidingSeriesFamily() == '40';

  bool get isSlidingH36Family => slidingSeriesFamily() == 'h36';

  bool _overrideHasIntegratedSideCover(Map<String, dynamic>? override) {
    if (override == null) return false;
    // إذا كان عرض الغطاء المدمج > 0 فهو مدمج بالتأكيد بغض النظر عن design_integrated
    final rawWidth = override['couvre_joint_width'];
    final width = rawWidth is num
        ? rawWidth.toDouble()
        : double.tryParse('${rawWidth ?? ''}') ?? 0.0;
    if (width > 0) return true;

    final name = (override['name'] ?? '').toString().toLowerCase();
    final type = (override['type'] ?? '').toString().toLowerCase();
    final rawIntegrated = override['design_integrated_side_cover'];
    if (rawIntegrated is bool) return rawIntegrated;
    if (rawIntegrated is num) return rawIntegrated != 0;
    if (rawIntegrated is String) {
      final normalized = rawIntegrated.trim().toLowerCase();
      if (normalized == '1' || normalized == 'true' || normalized == 'yes') {
        return true;
      }
      if (normalized == '0' || normalized == 'false' || normalized == 'no') {
        return false;
      }
    }
    return name.contains('مدمج') ||
        name.contains('intégré') ||
        name.contains('integre') ||
        name.contains('monobloc');
  }

  bool get isPVC => _isPvcSeries(
    usesSlidingPrimaryProfiles ? activeSlidingSeries : activeSeries,
  );

  bool get effectiveUseSystemOB => canUseOpeningOnlyOptions && useSystemOB;

  bool get canUseDemiOB => isPVC && canUseOpeningOnlyOptions;

  bool get effectiveUseDemiOB => canUseDemiOB && useDemiOB;

  /// Series and override used for the visible outer frame. In a mixed system
  /// the opening series owns the outer frame, while a sliding-only system uses
  /// the sliding series.
  AluminumSeries? get activeFrameSeries =>
      usesSlidingPrimaryProfiles ? activeSlidingSeries : activeSeries;

  Map<String, dynamic>? get activeFrameOverride {
    if (usesSlidingPrimaryProfiles) {
      // getSlidingBaseFrameSection already validates the saved override
      // against the active sliding series and its configured frame role.
      return getSlidingBaseFrameSection()?.toMap();
    }

    final override = frameOverride;
    final series = activeSeries;
    if (override == null || !_hasLoadedRoleMetadata(series)) return override;
    final rawId = override['id'];
    final id = rawId is num
        ? rawId.toInt()
        : int.tryParse(rawId?.toString() ?? '');
    final configuredIds =
        _seriesDesignRoleSectionIds[series!.id]?['frame'] ?? const <int>{};
    return id != null &&
            configuredIds.contains(id) &&
            _configuredSectionMatchesScope(series, 'frame', id, sliding: false)
        ? override
        : null;
  }

  /// Maximum length of one frame profile piece, in millimetres.
  ///
  /// The catalogue stores [AluminumSection.barLength] in metres.  A legacy
  /// row may already contain millimetres, so values above 100 are accepted as
  /// millimetres.  A standalone cover is included when it is actually part
  /// of the drawing; an integrated cover is already part of the frame row.
  double get maximumFrameBarLengthMm {
    double asMillimetres(double value) {
      if (value <= 0) return 0.0;
      return value > 100.0 ? value : value * 1000.0;
    }

    final lengths = <double>[];
    final frameLength = asMillimetres(
      getSectionByType('frame')?.barLength ?? 0,
    );
    if (frameLength > 0) lengths.add(frameLength);

    if (hasSideCovers && !isIntegratedFrame) {
      final overrideLength = sideCoverOverride?['bar_length'];
      final coverLength = asMillimetres(
        selectedSideCover?.barLength ??
            (overrideLength is num
                ? overrideLength.toDouble()
                : double.tryParse(overrideLength?.toString() ?? '') ?? 0.0),
      );
      if (coverLength > 0) lengths.add(coverLength);
    }

    return lengths.isEmpty ? 6000.0 : lengths.reduce(math.min);
  }

  double _limitFrameDimension(double value) =>
      value.clamp(200.0, maximumFrameBarLengthMm).toDouble();

  bool get isFramePVC => _isPvcSeries(activeFrameSeries);

  void applyFrameOverride(
    Map<String, dynamic> frame, {
    required bool sliding,
    bool manualSelection = false,
  }) {
    var mutable = Map<String, dynamic>.from(frame);
    if (manualSelection) {
      _sideCoverSelectionRevision++;
      mutable['manual_selection'] = true;
    }

    // An integrated-cover frame is a complete frame selection. Keep it as
    // selected, including for shutter systems; replacing it with a plain
    // frame here made the painter fall back to the unrelated standalone
    // side-cover profile. Multi-frame layouts are handled separately by the
    // perimeter painter and must not change the selected frame either.

    // A frame role may explicitly reject a separate couvre-joint. Apply that
    // rule in every drawing mode, not only in the shutter/multi-frame paths.
    // Integrated covers stay enabled because they belong to the frame itself.
    if (manualSelection &&
        !_overrideHasIntegratedSideCover(mutable) &&
        !_overrideAllowsStandaloneSideCover(mutable)) {
      hasSideCovers = false;
      useCustomSideCoverLayout = false;
      sideCoverSegments = [];
      hiddenSideCoverSegments.clear();
      selectedSideCover = null;
      sideCoverOverride = null;
      componentOverrides.remove('الغطاء الجانبي (Side Cover)');
    }

    // Selecting a frame from the lower drawing toolbar also selects the
    // cover mode represented by that frame. An integrated-cover frame must
    // appear with its cover immediately; a plain frame must not keep a cover
    // left over from the previously selected frame. The cover button remains
    // available afterwards, so the user can enable a standalone cover again
    // when the selected plain frame supports it.
    if (manualSelection) {
      final frameHasIntegratedCover = _overrideHasIntegratedSideCover(mutable);
      hasSideCovers =
          frameHasIntegratedCover ||
          _overrideAllowsStandaloneSideCover(mutable);
      _multiFrameSideCoverManuallyEnabled = false;
      useCustomSideCoverLayout = false;
      sideCoverSegments = [];
      hiddenSideCoverSegments.clear();
    }

    final frameHasIntegratedCover = _overrideHasIntegratedSideCover(mutable);
    if (frameHasIntegratedCover) {
      // The couvre-joint belongs to the selected frame itself. It must not
      // remain hidden because a previous plain frame disabled the optional
      // standalone-cover switch.
      hasSideCovers = true;
    }

    if (sliding) {
      slidingFrameOverride = mutable;
      _synchronizeSlidingSashesWithFrameTracks(mutable);
    } else {
      frameOverride = mutable;
      selectedFrameCode = mutable['code']?.toString();
    }
    updateProfileThickness();
  }

  int? _slidingTrackCountFromFrame(Map<String, dynamic> frame) {
    final configured = frame['design_track_count'] ?? frame['track_count'];
    final configuredCount = configured is num
        ? configured.toInt()
        : int.tryParse(configured?.toString() ?? '');
    if (configuredCount != null && configuredCount >= 2) {
      return configuredCount.clamp(2, 7).toInt();
    }
    final label =
        '${frame['name'] ?? ''} ${frame['type'] ?? ''} '
                '${frame['code'] ?? ''}'
            .toLowerCase()
            .replaceAll(RegExp(r'[_-]+'), ' ');

    bool mentions(int count) {
      return RegExp(
        '(^|[^0-9])$count\\s*(?:rail+l?s?|rails?|voies?|tracks?|سكك|سكة)',
        caseSensitive: false,
      ).hasMatch(label);
    }

    if (mentions(5)) return 5;
    if (mentions(4)) return 4;
    if (mentions(3)) return 3;
    if (mentions(2)) return 2;
    return null;
  }

  void _synchronizeSlidingSashesWithFrameTracks(Map<String, dynamic> frame) {
    final trackCount = _slidingTrackCountFromFrame(frame);
    if (trackCount == null) return;

    var updated = false;
    final isCompleteFrame =
        frame['design_track_mode']?.toString().toLowerCase() == 'complete';
    for (final zone in zones) {
      if (zone.content == ZoneContent.slidingSash) {
        zone.slidingTrackCount = trackCount;
        if (isCompleteFrame || zone.slidingSashesCount < trackCount) {
          zone.slidingSashesCount = trackCount.clamp(2, 7).toInt();
        }
        updated = true;
      }
    }

    // Selecting a complete multi-rail frame is also an explicit drawing
    // choice. If the current drawing has not yet been made sliding, promote
    // the selected zone (or the sole zone) immediately to the matching sash
    // count so a 3-rail frame visibly becomes a 3-sash drawing.
    if (!updated) {
      final target = selectedZone ?? (zones.length == 1 ? zones.first : null);
      if (target != null) {
        target.content = ZoneContent.slidingSash;
        target.slidingTrackCount = trackCount;
        // A complete N-rail frame starts with an intuitive N-leaf drawing,
        // but the user can then change leaves and rails independently.
        target.slidingSashesCount = trackCount.clamp(2, 7).toInt();
        target.innerH = 0;
        target.innerV = 0;
        target.rightInnerH = 0;
        target.rightInnerV = 0;
        target.openDirection = OpenDirection.right;
      }
    }
  }

  void applySashOverride(
    Map<String, dynamic> sash, {
    required bool sliding,
    bool manualSelection = false,
  }) {
    final mutable = Map<String, dynamic>.from(sash);
    if (manualSelection) {
      mutable['manual_selection'] = true;
    }

    if (sliding) {
      slidingSashOverride = mutable;
    } else {
      sashOverride = mutable;
      selectedSashCode = mutable['code']?.toString() ?? selectedSashCode;
    }
    updateAllSashThicknesses();
  }

  bool isSlidingMontantReinforced(
    Map<String, dynamic> profile, {
    required bool central,
  }) {
    final role = (profile['design_role_key'] ?? '').toString();
    if (role == 'sash_central_reinforced' ||
        role == 'sash_lateral_reinforced') {
      return true;
    }
    if (role == 'sash_central' || role == 'sash_lateral') return false;
    final code = (profile['code'] ?? '').toString().trim().toLowerCase();
    final name = (profile['name'] ?? '').toString().toLowerCase();
    final type = (profile['type'] ?? '').toString().toLowerCase();
    final description = '$name $type';
    if (description.contains('غير معزز') ||
        description.contains('غير معزّز') ||
        RegExp(r'(non|sans)[\s-]*renfor').hasMatch(description) ||
        description.contains('not reinforced') ||
        description.contains('unreinforced')) {
      return false;
    }
    return code.endsWith(central ? '107' : '108') ||
        name.contains('معزز') ||
        name.contains('renforc') ||
        type.contains('renforc');
  }

  void applySlidingMontantOverride(
    Map<String, dynamic> profile, {
    required bool central,
    bool? reinforced,
    bool manualSelection = false,
    bool updateAllMembers = true,
  }) {
    final mutable = Map<String, dynamic>.from(profile);
    if (manualSelection) {
      mutable['manual_selection'] = true;
      mutable['user_selected'] = true;
    }

    // PVC never uses a reinforced sliding montant, including when a drawing
    // loaded from an older version still contains the old reinforcement flag.
    final isReinforced =
        !isSlidingPVC &&
        (reinforced ?? isSlidingMontantReinforced(mutable, central: central));

    for (final zone in zones) {
      if (!updateAllMembers) break;
      if (zone.content != ZoneContent.slidingSash) continue;
      zone.slidingMontantReinforced = Map<String, bool>.from(
        zone.slidingMontantReinforced,
      );
      if (central) {
        final sashes = zone.slidingSashesCount > 0
            ? zone.slidingSashesCount
            : 2;
        final centralCount = math.max(0, (sashes * 2) - 2);
        for (var index = 0; index < centralCount; index++) {
          zone.slidingMontantReinforced['central_$index'] = isReinforced;
        }
      } else {
        zone.slidingMontantReinforced['lateral_0'] = isReinforced;
        zone.slidingMontantReinforced['lateral_1'] = isReinforced;
      }
    }

    if (central) {
      if (updateAllMembers) {
        componentOverrides.remove('قائم وسطي (Sash Central)');
        componentOverrides.remove('قائم وسطي معزز (Sash Central Renforcé)');
      }
      componentOverrides.remove('قائم وسطي (Central)');
      componentOverrides[isReinforced
              ? 'قائم وسطي معزز (Sash Central Renforcé)'
              : 'قائم وسطي (Sash Central)'] =
          mutable;
    } else {
      if (updateAllMembers) {
        componentOverrides.remove('قائم جانبي (Sash Lateral)');
        componentOverrides.remove('قائم جانبي معزز (Sash Lateral Renforcé)');
      }
      componentOverrides.remove('قائم جانبي (Lateral)');
      componentOverrides[isReinforced
              ? 'قائم جانبي معزز (Sash Lateral Renforcé)'
              : 'قائم جانبي (Sash Lateral)'] =
          mutable;
    }
    notifyListeners();
  }

  bool isSlidingMontantSlimCandidate(Map<String, dynamic> profile) {
    final role =
        (profile['design_role_key'] ??
                profile['roleKey'] ??
                profile['role_key'] ??
                '')
            .toString()
            .toLowerCase();
    if (role == 'montant_central_slim' ||
        role == 'sash_central_slim' ||
        role == 'montant_slim') {
      return true;
    }
    final code = (profile['code'] ?? '').toString().trim().toLowerCase();
    final name = (profile['name'] ?? '').toString().toLowerCase();
    final type = (profile['type'] ?? '').toString().toLowerCase();
    final description = '$name $type $code';
    return description.contains('slim') || description.contains('سليم');
  }

  List<Map<String, dynamic>> getSlidingSlimCandidates() {
    // The role assignment is authoritative. A Slim profile is often stored
    // with the ordinary central-montant type/name, so name matching alone
    // makes it disappear from the drawing and the BOM.
    final configured = getConfiguredSectionsForRole(
      'montant_central_slim',
      useSlidingSeries: true,
    );
    if (configured.isNotEmpty) {
      return configured.map((section) => section.toMap()).toList();
    }
    final sections = (activeSlidingSeries ?? activeSeries)?.sections ?? [];
    return sections
        .map((s) => s.toMap())
        .where((m) => isSlidingMontantSlimCandidate(m))
        .toList();
  }

  Map<String, dynamic>? get selectedSlimMontantProfile {
    final override = componentOverrides['قائم وسطي سليم (Montant Slim)'];
    if (override is Map<String, dynamic>) return override;
    if (override is Map) return Map<String, dynamic>.from(override);
    final candidates = getSlidingSlimCandidates();
    return candidates.isNotEmpty ? candidates.first : null;
  }

  void applySlidingMontantSlimOverride(
    Map<String, dynamic> profile, {
    bool manualSelection = false,
  }) {
    final mutable = Map<String, dynamic>.from(profile);
    if (manualSelection) {
      mutable['manual_selection'] = true;
      mutable['user_selected'] = true;
    }
    componentOverrides['قائم وسطي سليم (Montant Slim)'] = mutable;
    notifyListeners();
  }

  bool get hasSimpleGlassForReducer {
    if (zones.isEmpty) {
      return WindowZone.globalDefaultGlass.structure == GlassStructure.simple;
    }
    for (final zone in zones) {
      for (final spec in _effectiveGlassSpecificationsForZone(zone)) {
        if (spec.structure == GlassStructure.simple) return true;
      }
    }
    return false;
  }

  bool get hasDoubleGlassForRules {
    if (zones.isEmpty) {
      return WindowZone.globalDefaultGlass.structure == GlassStructure.double;
    }
    for (final zone in zones) {
      for (final spec in _effectiveGlassSpecificationsForZone(zone)) {
        if (spec.structure == GlassStructure.double) return true;
      }
    }
    return false;
  }

  void clearReducerOverride() {
    componentOverrides.remove('ريديكتور (Réducteur)');
    componentOverrides.remove('مخفض الزجاج (Réducteur)');
  }

  Future<void> ensureFrameCompatibleWithShutter() {
    return _selectNonIntegratedFrameForShutter();
  }

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
    Map<String, dynamic>? reinforcement;
    // The Renfort role is the authoritative association configured for the
    // selected series. This also supports a shared section whose owner is a
    // different series or even a different material system.
    final configuredReinforcement = getConfiguredSectionForRole(
      'renfort',
      useSlidingSeries: false,
    );
    if (configuredReinforcement != null) {
      reinforcement = configuredReinforcement.toMap();
    }

    final linkedReinforcementId = readId(
      frameSource['linked_renfort_id'] ?? frame['linked_renfort_id'],
    );
    if (reinforcement == null && linkedReinforcementId != null) {
      final rows = await database.query(
        'Sections',
        where: 'id = ?',
        whereArgs: [linkedReinforcementId],
        limit: 1,
      );
      if (rows.isNotEmpty) {
        reinforcement = Map<String, dynamic>.from(rows.first);
      }
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
  bool get isSlidingPVC => _isPvcSeries(
    systemMode == 'sliding' || usesSlidingPrimaryProfiles
        ? activeSlidingSeries
        : activeSeries,
  );

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
    return Rect.fromLTRB(
      profileThickness,
      topOffset + profileThickness,
      math.max(profileThickness, width - profileThickness),
      math.max(topOffset + profileThickness, height - bottomFrame),
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

  bool _divisionKeyBelongsToSide(String key, {required bool isRightSash}) {
    final isRightKey = key.startsWith('right_');
    return isRightSash ? isRightKey : !isRightKey;
  }

  void _keepPrimaryInnerDivisionsContinuous(
    WindowZone zone, {
    required bool isRightSash,
  }) {
    final primaryAxis = isRightSash
        ? zone.rightPrimaryDivisionAxis
        : zone.primaryDivisionAxis;
    if (primaryAxis == 'h') {
      zone.disabledHorizontalDivisions =
          Map<String, bool>.from(zone.disabledHorizontalDivisions)..removeWhere(
            (key, value) =>
                _divisionKeyBelongsToSide(key, isRightSash: isRightSash),
          );
    } else if (primaryAxis == 'v') {
      zone.disabledVerticalDivisions =
          Map<String, bool>.from(zone.disabledVerticalDivisions)..removeWhere(
            (key, value) =>
                _divisionKeyBelongsToSide(key, isRightSash: isRightSash),
          );
    }
  }

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

  void recordMullionCreation(bool isHorizontal, double position) {
    for (final entry in mullionCreationOrder.entries) {
      if (entry.key.startsWith(isHorizontal ? 'H_' : 'V_')) {
        final posStr = entry.key.substring(2);
        final p = double.tryParse(posStr);
        if (p != null && (p - position).abs() < 5.0) {
          return;
        }
      }
    }
    final key = _mullionKey(isHorizontal, position);
    mullionCreationOrder[key] = ++mullionStepCounter;
  }

  /// Determines the creation order of a mullion. A lower number means it was created earlier.
  int getMullionCreationOrder(bool isHorizontal, double position) {
    final key = _mullionKey(isHorizontal, position);
    if (mullionCreationOrder.containsKey(key)) {
      return mullionCreationOrder[key]!;
    }
    for (final entry in mullionCreationOrder.entries) {
      if (entry.key.startsWith(isHorizontal ? 'H_' : 'V_')) {
        final posStr = entry.key.substring(2);
        final p = double.tryParse(posStr);
        if (p != null && (p - position).abs() < 6.0) {
          return entry.value;
        }
      }
    }
    return 999999;
  }

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
      final isDoubleFrame =
          _isEnabledFlag(section['is_double_frame']) ||
          _isEnabledFlag(section['isDoubleFrame']) ||
          _isEnabledFlag(section['double_frame']) ||
          _isEnabledFlag(section['doubleFrame']);
      final effectiveWidth = isDoubleFrame ? width * 2.0 : width;
      if (effectiveWidth > maximum) maximum = effectiveWidth;
    }
    for (final profileType in mullionProfiles.values) {
      if (profileType == MullionProfileType.standard) {
        continue;
      }
      final width = _sectionVisibleWidth(
        profileType == MullionProfileType.flat ? activeFrameOverride : null,
      );
      final frameWidth = _frameForMullion(profileType)?.visibleWidth ?? 0.0;
      final effectiveOverrideWidth = profileType == MullionProfileType.flat
          ? width * 2.0
          : width;
      if (effectiveOverrideWidth > maximum) maximum = effectiveOverrideWidth;
      final effectiveFrameWidth = profileType == MullionProfileType.flat
          ? frameWidth * 2.0
          : frameWidth;
      if (effectiveFrameWidth > maximum) maximum = effectiveFrameWidth;
    }
    return maximum;
  }

  double get plintheHeight {
    if (componentOverrides.containsKey('بلانت (Plinthe)')) {
      final rawWidth =
          componentOverrides['بلانت (Plinthe)']['visible_width'] ??
          componentOverrides['بلانت (Plinthe)']['thickness'];
      final width = rawWidth is num
          ? rawWidth.toDouble()
          : double.tryParse(rawWidth?.toString() ?? '') ?? 0.0;
      if (width > 0) return width;
    }
    final s = getSectionByType('plinthe');
    if (s != null) return s.visibleWidth;
    return 0.0;
  }

  bool hasBottomFrame = true;
  bool useOptionalSeuil = false;
  bool useOptionalCacheDormant = false;
  bool useOptionalTriangle = false;
  bool useOptionalCaniveau = false;

  /// Bavette mode: 0 disabled, 1 bottom only, 2 all four directions.
  int optionalBavetteMode = 0;
  int cacheRailLeftCount = 0;
  int cacheRailRightCount = 0;

  // Cache-rail is a cosmetic sliding profile.  A series role makes it
  // available, never mandatory; new drawings start with it enabled.
  bool useOptionalCacheRail = true;
  bool hasFramePlintheBottom = false;
  bool isInternalView = true;
  bool showInternalHardware = false;
  bool isDrawingMode = false;
  String drawingMode = 'split'; // 'split' or 'add_frame'

  void setDrawingModeAction(String action) {
    drawingMode = action;
    notifyListeners();
  }

  bool hasShutter = false;
  bool isCaissonTunnel = false;

  // True when this model belongs to the full window-design workspace. This
  // distinguishes a designed window with a tunnel box/wall from a standalone
  // Caisson Tunnel quantity created by the dedicated calculator.
  bool isDesignDrawing = false;
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

  // Belt shutters are left-driven by default. An explicit saved/user choice
  // still replaces this value during deserialization or from the UI.
  String shutterDriveSide = 'left';
  String shutterLame = 'Lame Injectée';
  String shutterGlissiere = 'Glissière 25';
  String? shutterHeightWarning;
  String? shutterWidthWarning;
  double? shutterMaximumWidthMm;

  double get maximumShutterBarLengthMm {
    double readLength(Object? raw) {
      final value = raw is num
          ? raw.toDouble()
          : double.tryParse(raw?.toString() ?? '') ?? 0.0;
      if (value <= 0) return 6000.0;
      final millimetres = value > 100.0 ? value : value * 1000.0;
      return math.min(6000.0, millimetres);
    }

    final blade = componentOverrides['الشرائح (Lames)'];
    if (blade is Map) {
      return readLength(blade['bar_length_m'] ?? blade['bar_length']);
    }
    return 6000.0;
  }

  double get maximumAllowedShutterWidthMm =>
      math.min(maximumShutterBarLengthMm, shutterMaximumWidthMm ?? 6000.0);

  bool _componentWasManuallySelected(Map<String, dynamic>? component) {
    if (component == null) return false;

    bool enabled(Object? value) {
      if (value is bool) return value;
      if (value is num) return value != 0;
      final normalized = value?.toString().trim().toLowerCase();
      return normalized == 'true' || normalized == '1' || normalized == 'yes';
    }

    return enabled(component['manual_selection']) ||
        enabled(component['is_manual_selection']) ||
        enabled(component['user_selected']);
  }

  double _shutterBladeConfiguredMaxWidthMm(Map<String, dynamic> blade) {
    final raw = blade['max_width_mm'];
    final value = raw is num
        ? raw.toDouble()
        : double.tryParse(raw?.toString() ?? '') ?? 0.0;
    if (value <= 0) return 6000.0;
    return math.min(6000.0, value);
  }

  double _shutterBladeBarLimitMm(Map<String, dynamic> blade) {
    final raw = blade['bar_length_m'] ?? blade['bar_length'];
    final value = raw is num
        ? raw.toDouble()
        : double.tryParse(raw?.toString() ?? '') ?? 0.0;
    if (value <= 0) return 6000.0;
    final millimetres = value > 100.0 ? value : value * 1000.0;
    return math.min(6000.0, millimetres);
  }

  double _shutterBladeEffectiveMaxWidthMm(Map<String, dynamic> blade) {
    return math.min(
      _shutterBladeConfiguredMaxWidthMm(blade),
      _shutterBladeBarLimitMm(blade),
    );
  }

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
        final selected = Map<String, dynamic>.from(exactMatch.first);
        selected['manual_selection'] = true;
        selected['user_selected'] = true;
        selected['automatic_selection'] = false;
        componentOverrides['الشرائح (Lames)'] = selected;
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
    final targetH = effectiveEspagnoletteHeightMm / 10.0;

    if (targetH >= 180) return 180;
    if (targetH >= 40) return (targetH / 20.0).floor() * 20;
    if (targetH >= 30) return 30;
    return 30;
  }

  /// Height governed by espagnolette catalogue ranges. The shutter box is
  /// drawn first and occupies part of the opening; only the remaining height
  /// selects the matching min/max rule. Without a shutter, use the full
  /// drawing height.
  double get effectiveEspagnoletteHeightMm =>
      math.max(0.0, height.toDouble() - (hasShutter ? shutterBoxHeight : 0.0));

  int get gachePerEspagnolette {
    int len = cremoneLengthCm;
    if (len < 100) return 2;
    if (len <= 140) return 3;
    return 4;
  }

  bool hasSideCovers = true;
  bool _multiFrameSideCoverManuallyEnabled = false;
  int _sideCoverSelectionRevision = 0;
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
    return Rect.fromLTRB(
      profileThickness,
      topBox + profileThickness,
      math.max(profileThickness, width - profileThickness),
      math.max(topBox + profileThickness, height - bottomFrame),
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
    final innerBottom = height - bottomFrame;
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

  void setManualShutterBoxHeight(double value) {
    if (value <= 0 || customShutterBoxHeight == value) return;
    _saveSnapshot();
    final previousBoxHeight = shutterBoxHeight;
    customShutterBoxHeight = value;
    _synchronizeZonesAfterShutterBoxChange(previousBoxHeight, shutterBoxHeight);
    lastLayoutSize = null;
    notifyListeners();
  }

  AluminumSection? selectedSideCover;

  List<AluminumSection> get availableSideCovers {
    final owner = activeFrameSeries;
    return owner == null
        ? const <AluminumSection>[]
        : _sideCoversForSeries(owner);
  }

  /// Whether the selected plain frame accepts a separate side-cover profile.
  ///
  /// This is intentionally separate from [isIntegratedFrame]. A frame with
  /// an integrated cover does not need a second cover row, while a plain
  /// frame may explicitly reject a standalone cover in the catalogue.
  bool get canUseStandaloneSideCover {
    final canSwitchIntegratedFrame =
        _canSwitchIntegratedFrameToStandaloneSideCover;
    if (hasShutter && !isCaissonTunnel && !isFramePVC) {
      final currentFrame = activeFrameOverride;
      if (currentFrame != null) {
        return _overrideAllowsStandaloneSideCover(currentFrame) ||
            canSwitchIntegratedFrame;
      }
      final frame = getSectionByType('frame');
      if (frame != null) {
        return _sectionAllowsStandaloneSideCover(frame) ||
            canSwitchIntegratedFrame;
      }
    }
    if (isIntegratedFrame && !canSwitchIntegratedFrame) return false;
    final frame = getSectionByType('frame');
    final rawAllowed = activeFrameOverride?['allows_side_cover'];
    if (rawAllowed is bool && !rawAllowed) return canSwitchIntegratedFrame;
    if (rawAllowed is num && rawAllowed == 0) return canSwitchIntegratedFrame;
    if (rawAllowed is String &&
        (rawAllowed.trim() == '0' || rawAllowed.toLowerCase() == 'false')) {
      return canSwitchIntegratedFrame;
    }
    if (frame != null && !frame.allowsSideCover) {
      return canSwitchIntegratedFrame;
    }
    return availableSideCovers.isNotEmpty || standaloneSideCoverWidth > 0;
  }

  bool get _currentFrameHasIntegratedSideCover {
    final currentFrame = activeFrameOverride;
    if (currentFrame != null) {
      return _overrideHasIntegratedSideCover(currentFrame);
    }
    final frame = getSectionByType('frame');
    return frame != null && _sectionHasIntegratedSideCover(frame);
  }

  bool get _canSwitchIntegratedFrameToStandaloneSideCover {
    return !isFramePVC &&
        (availableSideCovers.isNotEmpty || standaloneSideCoverWidth > 0) &&
        (_currentFrameHasIntegratedSideCover ||
            !_overrideAllowsStandaloneSideCover(activeFrameOverride)) &&
        _hasFrameThatAllowsStandaloneSideCover;
  }

  bool get _hasFrameThatAllowsStandaloneSideCover {
    final series = activeFrameSeries;
    if (series == null) return false;
    final configuredFrames = getConfiguredSectionsForRole(
      'frame',
      useSlidingSeries: usesSlidingPrimaryProfiles,
    );
    final frames = configuredFrames.isNotEmpty
        ? configuredFrames
        : series.sections;
    return frames.any((section) {
      final type = section.type.toLowerCase();
      return (section.isFrame || type == 'frame' || type.contains('cadre')) &&
          _sectionAllowsStandaloneSideCover(section);
    });
  }

  bool get isSideCoverAllowed {
    // The selected frame owns this cover. Check it before the shutter rule
    // for standalone covers, otherwise an integrated frame can be rejected
    // before the drawing has a chance to render its own side cover.
    if (isIntegratedFrame) return integratedFrameSideCoverWidth > 0;

    if (hasShutter && !isCaissonTunnel && !isFramePVC) {
      final currentFrame = activeFrameOverride;
      if (currentFrame != null) {
        return _overrideAllowsStandaloneSideCover(currentFrame) ||
            _canSwitchIntegratedFrameToStandaloneSideCover;
      }
      final frame = getSectionByType('frame');
      if (frame != null) {
        return _sectionAllowsStandaloneSideCover(frame) ||
            _canSwitchIntegratedFrameToStandaloneSideCover;
      }
    }

    if (!canUseStandaloneSideCover) return false;
    return true;
  }

  bool get isIntegratedFrame {
    // Integration is a property of the selected profile, not the number of
    // frames. The painter separately follows their exposed perimeter.
    // Prefer the exact user-selected override.  The validated accessor can
    // temporarily return null while role metadata is refreshing; falling
    // through in that window incorrectly makes the painter use the separate
    // side-cover profile.
    final selectedOverride = usesSlidingPrimaryProfiles
        ? slidingFrameOverride
        : frameOverride;
    if (selectedOverride != null) {
      return _overrideHasIntegratedSideCover(selectedOverride);
    }
    if (activeFrameOverride != null) {
      return _overrideHasIntegratedSideCover(activeFrameOverride);
    }
    final frame = getSectionByType('frame');
    if (frame == null) return false;
    return _sectionHasIntegratedSideCover(frame);
  }

  /// Width of the selected standalone side-cover face.
  ///
  /// Older catalogues are not perfectly consistent: some TPR rows keep the
  /// drawable face in `visible_width_2` or in a textual measurement instead
  /// of `couvre_joint_width`. This getter deliberately never reads the frame,
  /// so an integrated-frame width cannot leak into a standalone cover
  /// calculation.
  double get standaloneSideCoverWidth {
    double readTextDimension(Object? value) {
      final text = value?.toString().replaceAll(',', '.') ?? '';
      if (text.trim().isEmpty) {
        return 0.0;
      }
      final matches = RegExp(r'\d+(?:\.\d+)?')
          .allMatches(text)
          .map((match) => double.tryParse(match.group(0)!))
          .whereType<double>()
          .where((number) => number > 1.0)
          .toList();
      if (matches.isEmpty) return 0.0;
      return matches.reduce(math.max);
    }

    double firstWidth = selectedSideCover?.couvreJointWidth ?? 0.0;
    double secondWidth = selectedSideCover?.visibleWidth ?? 0.0;
    double thirdWidth = selectedSideCover?.visibleWidth2 ?? 0.0;

    if (selectedSideCover == null && sideCoverOverride != null) {
      double read(String key) {
        final value = sideCoverOverride![key];
        return value is num
            ? value.toDouble()
            : double.tryParse(value?.toString() ?? '') ?? 0.0;
      }

      firstWidth = read('couvre_joint_width');
      secondWidth = read('visible_width');
      thirdWidth = read('visible_width_2');
      if (firstWidth <= 0) {
        firstWidth = read('cover_width');
      }
      if (secondWidth <= 0) {
        secondWidth = read('width');
      }
      if (thirdWidth <= 0) {
        thirdWidth = read('largeur');
      }
      if (firstWidth <= 0 && secondWidth <= 0 && thirdWidth <= 0) {
        thirdWidth = math.max(
          readTextDimension(sideCoverOverride!['measurement']),
          readTextDimension(sideCoverOverride!['dimension']),
        );
      }
    }

    final selectedWidth = sideCoverUseSecondWidth ? secondWidth : firstWidth;
    final otherWidth = sideCoverUseSecondWidth ? firstWidth : secondWidth;
    if (selectedWidth > 0) return selectedWidth;
    if (otherWidth > 0) return otherWidth;
    if (thirdWidth > 0) return thirdWidth;
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
    final series = activeSlidingSeries;
    if (series == null) return const <AluminumSection>[];
    return series.sections.where(_sectionIsSideCover).toList();
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
    final selectedOverride = usesSlidingPrimaryProfiles
        ? slidingFrameOverride
        : frameOverride;
    final source = selectedOverride ?? activeFrameOverride;
    if (source != null) {
      final value = source['couvre_joint_width'];
      return value is num
          ? value.toDouble()
          : double.tryParse(value?.toString() ?? '') ?? 0.0;
    }
    return getSectionByType('frame')?.couvreJointWidth ?? 0.0;
  }

  double get sideCoverWidth {
    if (isIntegratedFrame) {
      // Missing frame measurements must never borrow another profile's face.
      return integratedFrameSideCoverWidth;
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
    // or the bottom wall is removed. Filter it here as a final drawing/BOM
    // safeguard as well as removing it at the state transition below.
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
      if (side == 'bottom' && !canUseBottomSideCover) continue;
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
    if (normalized == 'bottom' && !canUseBottomSideCover) {
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
      if (side == 'bottom' && !canUseBottomSideCover) continue;
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
    if (normalized == 'bottom' && !canUseBottomSideCover) {
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
    if (side == 'bottom' && !canUseBottomSideCover) return;

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
  Map<String, dynamic>? _preferredDbColorForCatalogLoad;

  Map<String, dynamic>? get selectedDbColor => _selectedDbColor;

  set selectedDbColor(Map<String, dynamic>? colorData) {
    _saveSnapshot();
    _selectedDbColor = colorData == null
        ? null
        : Map<String, dynamic>.from(colorData);
    _preferredDbColorForCatalogLoad = _selectedDbColor == null
        ? null
        : Map<String, dynamic>.from(_selectedDbColor!);
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
    // The BOM is built synchronously from this cache.  Limiting it to
    // parcloses made ordinary linear-metre profiles start at 0 until the
    // user pressed the manual refresh button, which happens to reload their
    // prices later in the workflow.
    final sections = <int, AluminumSection>{};
    for (final series in <AluminumSeries?>[activeSeries, activeSlidingSeries]) {
      if (series == null) continue;
      for (final section in series.sections) {
        sections[section.id] = section;
      }
    }
    if (sections.isEmpty) return;

    final rawColorId = selectedDbColor?['id'];
    final colorId = rawColorId is num
        ? rawColorId.toInt()
        : int.tryParse(rawColorId?.toString() ?? '');
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

  String _profileColorHex(Map<String, dynamic>? colorData) {
    return (colorData?['hex_code'] ?? colorData?['hex'] ?? '')
        .toString()
        .replaceAll('#', '')
        .toLowerCase()
        .trim();
  }

  String _normalizedProfileColorName(String value) {
    return value
        .toLowerCase()
        .trim()
        .replaceAll('é', 'e')
        .replaceAll('è', 'e')
        .replaceAll('ê', 'e')
        .replaceAll('ë', 'e')
        .replaceAll('à', 'a')
        .replaceAll('â', 'a')
        .replaceAll('î', 'i')
        .replaceAll('ï', 'i')
        .replaceAll('ô', 'o')
        .replaceAll('ù', 'u')
        .replaceAll('û', 'u')
        .replaceAll('ç', 'c')
        .replaceAll('أ', 'ا')
        .replaceAll('إ', 'ا')
        .replaceAll('آ', 'ا')
        .replaceAll('ى', 'ي')
        .replaceAll('ة', 'ه')
        .replaceAll(RegExp(r'\s+'), ' ');
  }

  String? _profileColorAliasKey(String rawValue) {
    final value = _normalizedProfileColorName(rawValue);
    if (value.isEmpty) return null;
    if (value.contains('white') ||
        value.contains('blanc') ||
        value.contains('ابيض')) {
      return 'white';
    }
    if (value.contains('gris') ||
        value.contains('gray') ||
        value.contains('grey') ||
        value.contains('رمادي')) {
      return 'gray';
    }
    if (value.contains('black') ||
        value.contains('noir') ||
        value.contains('اسود')) {
      return 'black';
    }
    if (value.contains('wood') ||
        value.contains('bois') ||
        value.contains('fbm') ||
        value.contains('خشبي')) {
      return 'wood';
    }
    if (value.contains('brown') ||
        value.contains('marron') ||
        value.contains('بني')) {
      return 'brown';
    }
    if (value.contains('beige') ||
        value.contains('بيج') ||
        value.contains('باج')) {
      return 'beige';
    }
    return null;
  }

  Map<String, dynamic>? _findAvailableColorByName(String rawName) {
    final name = _normalizedProfileColorName(rawName);
    if (name.isEmpty) return null;

    for (final color in availableColors) {
      final colorName = _normalizedProfileColorName(_profileColorName(color));
      if (colorName == name) return color;
    }

    for (final color in availableColors) {
      final colorName = _normalizedProfileColorName(_profileColorName(color));
      if (colorName.isEmpty) continue;
      if (colorName.contains(name) || name.contains(colorName)) return color;
    }

    final alias = _profileColorAliasKey(rawName);
    if (alias != null) {
      for (final color in availableColors) {
        final colorAlias = _profileColorAliasKey(_profileColorName(color));
        if (colorAlias == alias) return color;
      }
    }

    return null;
  }

  Map<String, dynamic>? _findAvailableColorByHex(String rawHex) {
    final hex = rawHex.replaceAll('#', '').toLowerCase().trim();
    if (hex.isEmpty) return null;
    for (final color in availableColors) {
      if (_profileColorHex(color) == hex) return color;
    }
    return null;
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
        (name.isEmpty && (hex == 'ffffff' || hex == 'fff'));
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

  /// Returns the physical stock profile used for bardage. New catalogues may
  /// assign it through the generic panneau role, while older ones use the
  /// dedicated bardage role.
  Map<String, dynamic>? getBardageProfileOverride() {
    final specific = componentOverrides['البارداج (Bardage)'];
    if (specific is Map) return Map<String, dynamic>.from(specific);
    final panneau = componentOverrides['البانو (Panneau)'];
    if (panneau is Map &&
        (isBardagePanelSubtype(panneau['type']?.toString()) ||
            isBardagePanelSubtype(panneau['name']?.toString()))) {
      return Map<String, dynamic>.from(panneau);
    }
    for (final series in <AluminumSeries?>[activeSeries, activeSlidingSeries]) {
      if (series == null) continue;
      for (final section in series.sections) {
        if (isBardagePanelSubtype(section.type) ||
            isBardagePanelSubtype(section.name)) {
          return section.toMap();
        }
      }
    }
    return null;
  }

  double get bardageVisibleWidth {
    final profile = getBardageProfileOverride();
    final raw = profile?['visible_width'];
    return raw is num
        ? raw.toDouble()
        : double.tryParse(raw?.toString() ?? '') ?? 0.0;
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

  double getPanneauProfilePriceForColor(
    Map<String, dynamic>? colorData,
    String colorName,
  ) {
    final rawOverride = componentOverrides['البانو (Panneau)'];
    if (rawOverride is! Map) return 0.0;
    final override = Map<String, dynamic>.from(rawOverride);
    final rawPrices = override['color_prices'];
    if (rawPrices is Map) {
      final colorId = colorData?['id'];
      for (final key in <String>[
        if (colorId != null) 'id:$colorId',
        'name:${_normalizedProfileColorName(colorName)}',
      ]) {
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
  Map<String, dynamic>? selectedShutterColor;

  Map<String, dynamic>? get effectiveShutterColor =>
      selectedShutterColor ?? selectedDbColor;

  /// An explicit profile-colour choice resets both dependent colours.
  /// Loading a saved drawing must not call this: its independent choices stay.
  void selectProfileColorWithDefaults(Map<String, dynamic> color) {
    selectedDbColor = color;
    selectedShutterColor = Map<String, dynamic>.from(color);
    selectedAccessoryColor = Map<String, dynamic>.from(color);
    notifyListeners();
  }

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

  /// Catalog defaults alone do not constitute a drawn order item.
  /// An empty frame is still geometry, even before a sash is inserted.
  bool get hasDrawnGeometry =>
      width > 0 &&
      height > 0 &&
      (isShutterOnly || zones.any((zone) => !zone.boundary.isEmpty));
  Map<String, MullionProfileType> mullionProfiles = {};

  // false = left/top side, true = right/bottom side.
  Map<String, bool> groovedMullionCavityOnPositiveSide = {};
  Map<String, Map<String, dynamic>> mullionSectionOverrides = {};
  Map<String, int> mullionCreationOrder = {};
  int mullionStepCounter = 0;
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

  AluminumSeries? get effectiveSlidingSeries =>
      activeSlidingSeries ??
      (systemMode == 'sliding' || usesSlidingPrimaryProfiles
          ? activeSeries
          : null);
  Map<String, dynamic>? slidingFrameOverride;
  Map<String, dynamic>? slidingSashOverride;
  String? systemMode;
  Future<void> _catalogLoadChain = Future<void>.value();
  Future<void> _seriesUpdateChain = Future<void>.value();
  List<Map<String, dynamic>> availableColors = [];
  List<Map<String, dynamic>> availableAccessoryColors = [];
  bool colorsLoading = false;
  int _colorsLoadGeneration = 0;
  int? _loadedColorsProfileId;

  Future<void> _loadColorsForProfile(int profileId) async {
    if (_loadedColorsProfileId == profileId && availableColors.isNotEmpty) {
      colorsLoading = false;
      return;
    }
    final loadGeneration = ++_colorsLoadGeneration;
    final preferredColor = _preferredDbColorForCatalogLoad ?? _selectedDbColor;
    final previousColorId = preferredColor?['id'];
    final previousColorName =
        (preferredColor?['name'] ?? preferredColor?['color_name'])
            ?.toString()
            .toLowerCase()
            .trim();
    final previousColorHex = _profileColorHex(preferredColor);
    colorsLoading = true;
    availableColors = [];
    _selectedDbColor = null;
    for (final zone in zones) {
      zone.selectedDbColor = null;
    }
    notifyListeners();

    List<Map<String, dynamic>> loadedColors;
    try {
      loadedColors = (await db.getColorsForProfile(
        profileId,
      )).map((color) => Map<String, dynamic>.from(color)).toList();
    } catch (_) {
      if (loadGeneration == _colorsLoadGeneration) {
        availableColors = [];
        colorsLoading = false;
        notifyListeners();
      }
      return;
    }
    if (loadGeneration != _colorsLoadGeneration) return;
    availableColors = loadedColors;
    _loadedColorsProfileId = profileId;
    Map<String, dynamic>? selectedColor;

    // A saved order can travel between devices whose local colour IDs differ.
    // Resolve by stable identity first: name, then hex.  Use the numeric id
    // only when no stable identity was saved.
    if (previousColorName != null && previousColorName.isNotEmpty) {
      selectedColor = _findAvailableColorByName(previousColorName);
    }
    if (selectedColor == null && previousColorHex.isNotEmpty) {
      selectedColor = _findAvailableColorByHex(previousColorHex);
    }
    if (selectedColor == null &&
        previousColorId != null &&
        (previousColorName == null || previousColorName.isEmpty) &&
        previousColorHex.isEmpty) {
      for (final color in availableColors) {
        if (color['id']?.toString() == previousColorId.toString()) {
          selectedColor = color;
          break;
        }
      }
    }
    // Preserve the user's/order's colour only when the newly selected series
    // really supports it. Otherwise choose a valid colour for that series.
    selectedColor ??= _defaultFrameColor();
    if (selectedColor == null) _frameColor = FrameColor.white;

    _selectedDbColor = selectedColor == null
        ? null
        : Map<String, dynamic>.from(selectedColor);
    for (final zone in zones) {
      zone.selectedDbColor = _selectedDbColor == null
          ? null
          : Map<String, dynamic>.from(_selectedDbColor!);
    }
    colorsLoading = false;
    notifyListeners();
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
        return ['بارداج', 'بارداش', 'برداج', 'برداش', 'bardage'];
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
      return (exactMatch['thickness'] ?? kDefaultGlassPaneThickness).toDouble();
    }

    // 2. Try matching finish only
    final match = allGlassCache.firstWhere((g) {
      String t = g['type'].toString().toLowerCase();
      String n = g['name'].toString().toLowerCase();
      return finishKws.any((kw) => t.contains(kw) || n.contains(kw));
    }, orElse: () => <String, dynamic>{});

    if (match.isNotEmpty) {
      return (match['thickness'] ?? kDefaultGlassPaneThickness).toDouble();
    }

    // 3. Fallback for clair
    if (finish == GlassFinish.clair) {
      final clairMatch = allGlassCache.firstWhere((g) {
        String t = g['type'].toString().toLowerCase();
        return t == 'simple' || t == 'clair' || t == 'glass';
      }, orElse: () => <String, dynamic>{});
      if (clairMatch.isNotEmpty) {
        return (clairMatch['thickness'] ?? kDefaultGlassPaneThickness)
            .toDouble();
      }
    }

    return kDefaultGlassPaneThickness;
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
      final thick = glass.thicknessOuter ?? kDefaultGlassPaneThickness;
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
      final thickInner = glass.thicknessInner ?? kDefaultGlassPaneThickness;
      final thickOuter = glass.thicknessOuter ?? kDefaultGlassPaneThickness;

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

  Future<void> loadCatalogData([String systemMode = '']) {
    final next = _catalogLoadChain.then((_) => _loadCatalogData(systemMode));
    _catalogLoadChain = next.catchError((Object error, StackTrace stack) {});
    return next;
  }

  Future<void> _loadCatalogData([String systemMode = '']) async {
    colorsLoading = true;
    notifyListeners();
    try {
      if (systemMode.isNotEmpty) {
        this.systemMode = systemMode;
      }

      // Put the palette on screen before the slower catalogue/role pass. The
      // selected product already knows its active profile when editing an
      // order, so there is no reason to wait for every catalogue table first.
      _loadedColorsProfileId = null;
      final earlyColorSeries = this.systemMode == 'sliding'
          ? activeSlidingSeries
          : activeSeries;
      if (earlyColorSeries != null) {
        await _loadColorsForProfile(earlyColorSeries.profileId);
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
      // Keep the early palette visible while the remaining catalogue tables
      // are being resolved. Clearing it here brought back the white/default
      // state and made colours appear to load much later than they did.
      availableAccessoryColors = await db.readAccessoryColors();
      final newAvailableSystems = <AluminumProfileSystem>[];
      bool foundValidSeries = false;
      final selectedSeriesIds = <int>{
        if (loadedSeriesId != null) loadedSeriesId!,
        if (loadedSlidingSeriesId != null) loadedSlidingSeriesId!,
        if (activeSeries != null) activeSeries!.id,
        if (activeSlidingSeries != null) activeSlidingSeries!.id,
      };
      final selectedSeriesNames = <String>{
        if (loadedSeriesName != null && loadedSeriesName!.trim().isNotEmpty)
          loadedSeriesName!.trim().toLowerCase(),
        if (loadedSlidingSeriesName != null &&
            loadedSlidingSeriesName!.trim().isNotEmpty)
          loadedSlidingSeriesName!.trim().toLowerCase(),
        if (activeSeries != null && activeSeries!.name.trim().isNotEmpty)
          activeSeries!.name.trim().toLowerCase(),
        if (activeSlidingSeries != null &&
            activeSlidingSeries!.name.trim().isNotEmpty)
          activeSlidingSeries!.name.trim().toLowerCase(),
      };

      for (var pData in profilesData) {
        var system = AluminumProfileSystem.fromMap(pData);
        final seriesData = <Map<String, dynamic>>[
          ...(await db.readSeriesByProfile(system.id)),
        ];

        // Keep an explicitly selected series visible even if it was marked
        // inactive after the drawing was saved. Do not expose every inactive
        // catalogue row; restore only the row(s) already selected by the
        // drawing/order.
        if (selectedSeriesIds.isNotEmpty || selectedSeriesNames.isNotEmpty) {
          final allSeriesData = await db.readAllSeriesByProfile(system.id);
          for (final candidate in allSeriesData) {
            final rawId = candidate['id'];
            final candidateId = rawId is int
                ? rawId
                : int.tryParse(rawId?.toString() ?? '');
            final candidateName = (candidate['name'] ?? '')
                .toString()
                .trim()
                .toLowerCase();
            final selectedById =
                candidateId != null && selectedSeriesIds.contains(candidateId);
            final selectedByName =
                candidateName.isNotEmpty &&
                selectedSeriesNames.contains(candidateName);
            if (selectedById || selectedByName) {
              final alreadyLoaded = seriesData.any((row) {
                final rowId = row['id'];
                return rowId?.toString() == rawId?.toString();
              });
              if (!alreadyLoaded) seriesData.add(candidate);
            }
          }
        }

        for (var sData in seriesData) {
          var series = AluminumSeries.fromMap(sData);
          final sectionsData = await db.readAvailableSectionsBySeries(
            series.id,
          );
          series.sections = sectionsData
              .map((e) => AluminumSection.fromMap(e))
              .toList();
          // Cache role ownership for every loaded series. This lets shared
          // components such as couvre-joint be collected across series while
          // keeping frames and sashes tied to their own role rows.
          _rememberSeriesRoleKeys(
            series,
            await db.getSeriesDesignRoles(series.id),
          );

          // Keep every active catalogue row available to the drawing page.
          // Opening/sliding classification is used later to resolve the
          // correct role and calculation path; it must never remove an
          // enabled system from the selector. This is especially important
          // for commercial/legacy types such as TPR whose type field may not
          // contain an exact opening/sliding label.
          system.series.add(series);
        }
        if (system.series.isNotEmpty) newAvailableSystems.add(system);
      }
      if (newAvailableSystems.isNotEmpty) {
        availableSystems = newAvailableSystems;
      }

      if (availableSystems.isNotEmpty) {
        bool isOpeningCandidate(
          AluminumSeries series,
          AluminumProfileSystem profile,
        ) {
          if (systemMode == 'sliding') return false;
          if (systemMode == 'mixed' || systemMode == 'french') {
            return seriesSupportsDrawingScopeInSystem(
              series,
              'opening',
              profile: profile,
            );
          }
          return true;
        }

        bool isSlidingCandidate(
          AluminumSeries series,
          AluminumProfileSystem profile,
        ) {
          if (systemMode == 'french') return false;
          if (systemMode == 'mixed' || systemMode == 'sliding') {
            return seriesSupportsDrawingScopeInSystem(
              series,
              'sliding',
              profile: profile,
            );
          }
          return true;
        }

        bool isPrimarySeriesCandidate(
          AluminumSeries series,
          AluminumProfileSystem profile,
        ) {
          // In a sliding drawing activeSeries is the primary sliding series;
          // in the other drawing modes it is the opening series.
          return systemMode == 'sliding'
              ? isSlidingCandidate(series, profile)
              : isOpeningCandidate(series, profile);
        }

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
              // A saved series id is an explicit user choice.  Do not reject
              // it because a legacy or partially configured series cannot
              // yet be classified as opening/sliding; rejecting it here made
              // the product silently fall back to the first default series.
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
              final sourceSystem = AluminumProfileSystem.fromMap(pData);
              final seriesData = await db.readSeriesByProfile(pData['id']);
              for (var sData in seriesData) {
                final s = AluminumSeries.fromMap(sData);
                if (s.id == loadedSeriesId) {
                  final sectionsData = await db.readAvailableSectionsBySeries(
                    s.id,
                  );
                  s.sections = sectionsData
                      .map((e) => AluminumSection.fromMap(e))
                      .toList();
                  resolvedActive = s;
                  // Inject into the matching system only. Never attach a
                  // restored series to the first unrelated profile row.
                  final targetSystem = availableSystems.where(
                    (sys) => sys.id == sourceSystem.id,
                  );
                  final alreadyIn = targetSystem.any(
                    (sys) => sys.series.any((sr) => sr.id == s.id),
                  );
                  if (!alreadyIn) {
                    if (targetSystem.isNotEmpty) {
                      targetSystem.first.series.add(s);
                    } else {
                      sourceSystem.series.add(s);
                      availableSystems.add(sourceSystem);
                    }
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
              final sourceSystem = AluminumProfileSystem.fromMap(pData);
              final seriesData = await db.readSeriesByProfile(pData['id']);
              for (var sData in seriesData) {
                final s = AluminumSeries.fromMap(sData);
                if (s.id == activeSeries!.id) {
                  final sectionsData = await db.readAvailableSectionsBySeries(
                    s.id,
                  );
                  s.sections = sectionsData
                      .map((e) => AluminumSection.fromMap(e))
                      .toList();
                  resolvedActive = s;
                  final targetSystem = availableSystems.where(
                    (sys) => sys.id == sourceSystem.id,
                  );
                  final alreadyIn = targetSystem.any(
                    (sys) => sys.series.any((sr) => sr.id == s.id),
                  );
                  if (!alreadyIn) {
                    if (targetSystem.isNotEmpty) {
                      targetSystem.first.series.add(s);
                    } else {
                      sourceSystem.series.add(s);
                      availableSystems.add(sourceSystem);
                    }
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
              if (!isPrimarySeriesCandidate(s, sys)) continue;
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
              if (isPrimarySeriesCandidate(s, sys)) {
                firstFrench = s;
                break;
              }
            }
            if (firstFrench != null) break;
          }
          if (firstFrench != null) {
            await setActiveSeries(firstFrench);
          }
          foundValidSeries = firstFrench != null;
        }

        final pairedSystem = systemMode == 'mixed'
            ? profileSystemForSeries(availableSystems, activeSeries)
            : null;
        final selectedPairedSystem = pairedSystem;
        bool belongsToPairedSystem(AluminumProfileSystem system) =>
            selectedPairedSystem == null ||
            profileSystemsShareMaterial(system, selectedPairedSystem);

        AluminumSeries? resolvedSliding;
        String? slidingNameToResolve = loadedSlidingSeriesName;
        if (slidingNameToResolve == null || slidingNameToResolve.isEmpty) {
          slidingNameToResolve = activeSlidingSeries?.name;
        }

        // A saved sliding-series id is an explicit product choice.  It may
        // legitimately belong to a different catalogue system than the
        // opening series (for example Bennia 40000 + BS 90).  Resolving it
        // only inside the paired system made the restore fail and then
        // silently replace it with that system's first sliding series.
        if (loadedSlidingSeriesId != null) {
          for (final sys in availableSystems) {
            for (final series in sys.series) {
              if (series.id == loadedSlidingSeriesId) {
                resolvedSliding = series;
                break;
              }
            }
            if (resolvedSliding != null) break;
          }
        }

        if (resolvedSliding == null && activeSlidingSeries != null) {
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
            if (!belongsToPairedSystem(sys)) continue;
            for (var s in sys.series) {
              if (!isSlidingCandidate(s, sys)) continue;
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

        // Keep the selected system as the only source. Never restore a saved
        // sliding id from another system just because its material is equal.
        if (resolvedSliding == null) {
          for (var sys in availableSystems) {
            if (!belongsToPairedSystem(sys)) continue;
            for (var s in sys.series) {
              final matchesSavedId =
                  loadedSlidingSeriesId != null &&
                  s.id == loadedSlidingSeriesId;
              final matchesActiveId =
                  activeSlidingSeries != null &&
                  s.id == activeSlidingSeries!.id;
              if ((matchesSavedId || matchesActiveId) &&
                  isSlidingCandidate(s, sys)) {
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
            if (!belongsToPairedSystem(sys)) continue;
            for (var s in sys.series) {
              if (!isSlidingCandidate(s, sys)) continue;
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
            if (!belongsToPairedSystem(sys)) continue;
            for (var s in sys.series) {
              if (isSlidingCandidate(s, sys)) {
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
          }
        }

        if (systemMode == 'mixed') {
          if (resolvedSliding != null) {
            await setActiveSlidingSeries(resolvedSliding);
          } else {
            AluminumSeries? firstSliding;
            final activeSystem = profileSystemForSeries(
              availableSystems,
              activeSeries,
            );
            if (activeSystem != null) {
              for (var ser in activeSystem.series) {
                if (isSlidingCandidate(ser, activeSystem)) {
                  firstSliding = ser;
                  break;
                }
              }
            }
            if (firstSliding != null) {
              await setActiveSlidingSeries(firstSliding);
            } else {
              // A mixed drawing may keep the sliding family in another
              // profile row. Use the first actual sliding series, never the
              // opening series as a substitute, but keep the same material.
              for (var sys in availableSystems) {
                if (!belongsToPairedSystem(sys)) continue;
                for (var ser in sys.series) {
                  if (isSlidingCandidate(ser, sys)) {
                    firstSliding = ser;
                    break;
                  }
                }
                if (firstSliding != null) break;
              }
              if (firstSliding != null) {
                await setActiveSlidingSeries(firstSliding);
              } else {
                activeSlidingSeries = null;
              }
            }
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
      // Restore the cover selected by the frame-owning series as soon as all
      // series roles are known. A saved enabled cover must be drawable on the
      // first frame; it must never wait for the user to toggle its button.
      _synchronizeSharedSideCover();
      colorsLoading = false;
      notifyListeners();
    } catch (e) {
      colorsLoading = false;
      notifyListeners();
      debugPrint("Error loading catalog data: $e");
    }
  }

  void copyCatalogRuntimeFrom(
    WindowModel source, {
    bool preserveCurrentSelections = true,
  }) {
    Map<String, dynamic>? cloneMap(Map<String, dynamic>? value) =>
        value == null ? null : Map<String, dynamic>.from(value);
    dynamic cloneOverrideValue(Object? value) {
      if (value is Map<String, dynamic>) {
        return Map<String, dynamic>.from(value);
      }
      if (value is Map) {
        return Map<String, dynamic>.from(value);
      }
      return value;
    }

    final currentDbColor = _selectedDbColor == null
        ? null
        : Map<String, dynamic>.from(_selectedDbColor!);
    final currentAccessoryColor = _selectedAccessoryColor == null
        ? null
        : Map<String, dynamic>.from(_selectedAccessoryColor!);
    final currentFrameOverride = cloneMap(frameOverride);
    final currentSideCoverOverride = cloneMap(sideCoverOverride);
    final currentSashOverride = cloneMap(sashOverride);
    final currentSlidingFrameOverride = cloneMap(slidingFrameOverride);
    final currentSlidingSashOverride = cloneMap(slidingSashOverride);
    final currentInternalSlidingSideCoverOverride = cloneMap(
      internalSlidingSideCoverOverride,
    );
    final currentSelectedSideCover = selectedSideCover;
    final currentSelectedInternalSlidingSideCover =
        selectedInternalSlidingSideCover;
    final currentComponentOverrides = componentOverrides.map(
      (key, value) => MapEntry(key, cloneOverrideValue(value)),
    );

    availableSystems = source.availableSystems;
    activeSeries = source.activeSeries;
    activeSlidingSeries = source.activeSlidingSeries;
    systemMode = systemMode ?? source.systemMode;
    allGlassCache = source.allGlassCache
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
    availableIntercalls = source.availableIntercalls
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
    availableGases = source.availableGases
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
    availableColors = source.availableColors
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
    availableAccessoryColors = source.availableAccessoryColors
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
    seriesDesignConfig = source.seriesDesignConfig == null
        ? null
        : Map<String, dynamic>.from(source.seriesDesignConfig!);
    seriesTableConfig = source.seriesTableConfig == null
        ? null
        : Map<String, dynamic>.from(source.seriesTableConfig!);
    slidingSeriesTableConfig = source.slidingSeriesTableConfig == null
        ? null
        : Map<String, dynamic>.from(source.slidingSeriesTableConfig!);

    _seriesDesignRoleKeys
      ..clear()
      ..addAll(
        source._seriesDesignRoleKeys.map(
          (seriesId, roles) => MapEntry(seriesId, Set<String>.from(roles)),
        ),
      );
    _seriesDesignRoleSectionIds
      ..clear()
      ..addAll(
        source._seriesDesignRoleSectionIds.map(
          (seriesId, roles) => MapEntry(
            seriesId,
            roles.map((role, ids) => MapEntry(role, Set<int>.from(ids))),
          ),
        ),
      );
    _seriesDesignRoleUsageScopes
      ..clear()
      ..addAll(
        source._seriesDesignRoleUsageScopes.map(
          (seriesId, roles) => MapEntry(
            seriesId,
            roles.map(
              (role, scopes) => MapEntry(role, Map<int, String>.from(scopes)),
            ),
          ),
        ),
      );
    sectionPricesForSelectedColor
      ..clear()
      ..addAll(source.sectionPricesForSelectedColor);
    if (preserveCurrentSelections) {
      frameOverride = currentFrameOverride ?? cloneMap(source.frameOverride);
      sideCoverOverride =
          currentSideCoverOverride ?? cloneMap(source.sideCoverOverride);
      sashOverride = currentSashOverride ?? cloneMap(source.sashOverride);
      slidingFrameOverride =
          currentSlidingFrameOverride ?? cloneMap(source.slidingFrameOverride);
      slidingSashOverride =
          currentSlidingSashOverride ?? cloneMap(source.slidingSashOverride);
      internalSlidingSideCoverOverride =
          currentInternalSlidingSideCoverOverride ??
          cloneMap(source.internalSlidingSideCoverOverride);
      selectedSideCover = currentSelectedSideCover ?? source.selectedSideCover;
      selectedInternalSlidingSideCover =
          currentSelectedInternalSlidingSideCover ??
          source.selectedInternalSlidingSideCover;
      componentOverrides = source.componentOverrides.map(
        (key, value) => MapEntry(key, cloneOverrideValue(value)),
      );
      currentComponentOverrides.forEach((key, value) {
        componentOverrides[key] = cloneOverrideValue(value);
      });
    } else {
      frameOverride = cloneMap(source.frameOverride);
      sideCoverOverride = cloneMap(source.sideCoverOverride);
      sashOverride = cloneMap(source.sashOverride);
      slidingFrameOverride = cloneMap(source.slidingFrameOverride);
      slidingSashOverride = cloneMap(source.slidingSashOverride);
      internalSlidingSideCoverOverride = cloneMap(
        source.internalSlidingSideCoverOverride,
      );
      selectedSideCover = source.selectedSideCover;
      selectedInternalSlidingSideCover =
          source.selectedInternalSlidingSideCover;
      componentOverrides = source.componentOverrides.map(
        (key, value) => MapEntry(key, cloneOverrideValue(value)),
      );
    }

    if (preserveCurrentSelections) {
      _selectedDbColor =
          currentDbColor ??
          (source.selectedDbColor == null
              ? null
              : Map<String, dynamic>.from(source.selectedDbColor!));
      _selectedAccessoryColor =
          currentAccessoryColor ??
          (source.selectedAccessoryColor == null
              ? null
              : Map<String, dynamic>.from(source.selectedAccessoryColor!));
    } else {
      _selectedDbColor = source.selectedDbColor == null
          ? null
          : Map<String, dynamic>.from(source.selectedDbColor!);
      _selectedAccessoryColor = source.selectedAccessoryColor == null
          ? null
          : Map<String, dynamic>.from(source.selectedAccessoryColor!);
    }
    if (!preserveCurrentSelections || selectedShutterColor == null) {
      selectedShutterColor = source.selectedShutterColor == null
          ? null
          : Map<String, dynamic>.from(source.selectedShutterColor!);
    }
    for (final zone in zones) {
      zone.selectedDbColor = _selectedDbColor == null
          ? null
          : Map<String, dynamic>.from(_selectedDbColor!);
    }
  }

  double _calculateSashThickness(bool is105) {
    final useSliding = systemMode == 'sliding' || usesSlidingPrimaryProfiles;
    final selectedOverride = useSliding ? slidingSashOverride : sashOverride;
    final selectedSeries = useSliding ? activeSlidingSeries : activeSeries;

    // إذا كان هناك ضلفة مخصصة مختارة، نستخدم العرض الظاهر لها
    if (selectedOverride != null) {
      double t = (selectedOverride['visible_width'] as num?)?.toDouble() ?? 0.0;
      if (t > 0) return t;
    }

    if (selectedSeries == null || selectedSeries.sections.isEmpty) {
      return is105 ? 70.0 : 50.0;
    }

    // محاولة إيجاد الضلفة الافتراضية
    String targetCode = is105 ? '105' : '104';
    try {
      final sashSection = selectedSeries.sections.firstWhere(
        (s) => s.type.toLowerCase() == 'sash' && s.code.contains(targetCode),
      );
      if (sashSection.visibleWidth > 0) return sashSection.visibleWidth;
      if (sashSection.thickness > 0) return sashSection.thickness;
    } catch (_) {
      // إذا لم يجد ضلفة بالكود 104/105، يبحث عن أي ضلفة أخرى في السلسلة
      try {
        final anySash = selectedSeries.sections.firstWhere(
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

    final useSliding = systemMode == 'sliding' || usesSlidingPrimaryProfiles;
    final selectedOverride = useSliding ? slidingSashOverride : sashOverride;

    // The sash explicitly selected in the drawing is the source of truth.
    final overrideOverlap = readOverlap(selectedOverride?['sash_overlap']);
    if (overrideOverlap > 0) return overrideOverlap;

    final series = useSliding
        ? (activeSlidingSeries ?? activeSeries)
        : activeSeries;
    if (series != null) {
      final overrideId = selectedOverride?['id']?.toString();
      final overrideCode = selectedOverride?['code']?.toString().trim();
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

  /// Series-specific total deduction used to calculate the cut width of
  /// sliding leaves.  A value may be entered independently for 2, 3, or 4
  /// leaves; zero keeps the catalogue's legacy formula.
  double slidingSashWidthDeduction(int sashCount) {
    final config = slidingSeriesTableConfig ?? seriesTableConfig;
    final key = switch (sashCount) {
      2 => 'sash_w_deduction_2',
      3 => 'sash_w_deduction_3',
      4 => 'sash_w_deduction_4',
      _ => null,
    };
    if (key == null) return 0.0;
    final value = config?[key];
    if (value is num) {
      return value.toDouble();
    }
    return double.tryParse(value?.toString() ?? '') ?? 0.0;
  }

  /// Vertical deduction configured for the sliding sash. The database keeps
  /// the legacy column name `sash_overlap_val`, but the series form defines
  /// it as a value deducted from the usable height.
  double slidingSashHeightDeduction() {
    final config = slidingSeriesTableConfig ?? seriesTableConfig;
    final value = config?['sash_overlap_val'];
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0.0;
  }

  double getSectionThickness(String type, {double fallback = 45.0}) {
    final useSliding = systemMode == 'sliding' || usesSlidingPrimaryProfiles;
    final series = useSliding
        ? (activeSlidingSeries ?? activeSeries)
        : activeSeries;
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
    final useSliding = systemMode == 'sliding' || usesSlidingPrimaryProfiles;
    final series = useSliding ? activeSlidingSeries : activeSeries;
    if (series == null) return null;
    final normalizedType = type.toLowerCase();

    AluminumSection? result;
    if (normalizedType == 'sash') {
      final ov = useSliding ? slidingSashOverride : sashOverride;
      if (ov != null) result = AluminumSection.fromMap(ov);
    } else if (normalizedType == 'plinthe' ||
        normalizedType == 'plinth' ||
        normalizedType == 'plant') {
      final ov = componentOverrides['بلانت (Plinthe)'];
      if (ov is Map) {
        result = AluminumSection.fromMap(Map<String, dynamic>.from(ov));
      }
    } else if (normalizedType == 'frame') {
      final ov = useSliding ? slidingFrameOverride : frameOverride;
      if (ov != null) result = AluminumSection.fromMap(ov);
    }

    // Once role metadata is loaded, a frame exists only when the current
    // series assigns one to the frame role. Never fall back to a frame found
    // by name/type, which is how opening frames leaked into sliding drawings.
    if (normalizedType == 'frame' && _hasLoadedRoleMetadata(series)) {
      final configuredIds =
          _seriesDesignRoleSectionIds[series.id]?['frame'] ?? const <int>{};
      if (configuredIds.isEmpty) return null;
      if (result != null) {
        final rawId = result.id;
        if (configuredIds.contains(rawId) &&
            _configuredSectionMatchesScope(
              series,
              'frame',
              rawId,
              sliding: useSliding,
            )) {
          return result;
        }
        result = null;
      }
      for (final section in series.sections) {
        if (configuredIds.contains(section.id) &&
            _configuredSectionMatchesScope(
              series,
              'frame',
              section.id,
              sliding: useSliding,
            )) {
          return section;
        }
      }
      return null;
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
          final isPlinthe =
              (normalizedType == 'plinthe' ||
                  normalizedType == 'plinth' ||
                  normalizedType == 'plant') &&
              (sectionType.contains('plinthe') ||
                  sectionType.contains('plinth') ||
                  sectionType.contains('plant') ||
                  sectionType.contains('بلانت') ||
                  sectionName.contains('plinthe') ||
                  sectionName.contains('plinth') ||
                  sectionName.contains('plant') ||
                  sectionName.contains('بلانت'));
          if (sectionType == normalizedType ||
              isPlinthe ||
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
    final series = effectiveSlidingSeries;
    if (series == null) return null;
    final normalizedType = type.toLowerCase();

    if (normalizedType == 'sash') {
      final rawId = slidingSashOverride?['id'];
      final overrideId = rawId is num
          ? rawId.toInt()
          : int.tryParse(rawId?.toString() ?? '');
      final configuredIds =
          _seriesDesignRoleSectionIds[series.id]?['sash'] ?? const <int>{};
      final overrideIsAllowed =
          overrideId != null &&
          (!_hasLoadedRoleMetadata(series) ||
              (configuredIds.contains(overrideId) &&
                  _configuredSectionMatchesScope(
                    series,
                    'sash',
                    overrideId,
                    sliding: true,
                  )));
      if (overrideIsAllowed) {
        return AluminumSection.fromMap(slidingSashOverride!);
      }
      if (_hasLoadedRoleMetadata(series)) {
        for (final section in series.sections) {
          if (configuredIds.contains(section.id) &&
              _configuredSectionMatchesScope(
                series,
                'sash',
                section.id,
                sliding: true,
              )) {
            return section;
          }
        }
        return null;
      }
    }
    if (normalizedType == 'frame') {
      final base = getSlidingBaseFrameSection();
      if (base != null) return base;
      // A configured sliding series with no frame role must stay empty. Do
      // not select an opening frame merely because its type is also "frame".
      if (_hasLoadedRoleMetadata(series)) return null;
    }

    for (final section in series.sections) {
      if (section.type.toLowerCase() == normalizedType ||
          (normalizedType == 'frame' && section.isFrame)) {
        return section;
      }
    }
    return null;
  }

  /// Returns true when a catalogue row is the one-track extension assigned
  /// to a sliding series. This is used by the selector to keep the mandatory
  /// two-track base frame separate from its automatic additions.
  bool isSlidingFrameExtension(Map<String, dynamic> section) {
    final series = effectiveSlidingSeries;
    final rawId = section['id'];
    final id = rawId is num
        ? rawId.toInt()
        : int.tryParse(rawId?.toString() ?? '');
    final configuredIds = series == null
        ? const <int>{}
        : (_seriesDesignRoleSectionIds[series.id]?['frame_extension'] ??
              const <int>{});
    return id != null && configuredIds.contains(id);
  }

  /// Resolves the physical two-track base frame even when an old drawing or
  /// an overly broad catalogue role contains a one-track profile.
  AluminumSection? getSlidingBaseFrameSection() {
    final series = effectiveSlidingSeries;
    if (series == null) return null;

    bool isCurrentSlidingFrame(Map<String, dynamic> value) {
      final rawId = value['id'];
      final id = rawId is num
          ? rawId.toInt()
          : int.tryParse(rawId?.toString() ?? '');
      if (id == null || isSlidingFrameExtension(value)) return false;

      AluminumSection? section;
      for (final candidate in series.sections) {
        if (candidate.id == id) {
          section = candidate;
          break;
        }
      }
      if (section == null) return false;
      if (!_hasLoadedRoleMetadata(series)) return true;

      final configuredIds =
          _seriesDesignRoleSectionIds[series.id]?['frame'] ?? const <int>{};
      return configuredIds.contains(id) &&
          _configuredSectionMatchesScope(series, 'frame', id, sliding: true);
    }

    if (slidingFrameOverride != null &&
        isCurrentSlidingFrame(slidingFrameOverride!)) {
      return AluminumSection.fromMap(slidingFrameOverride!);
    }

    final configuredIds =
        _seriesDesignRoleSectionIds[series.id]?['frame'] ?? const <int>{};
    for (final section in series.sections) {
      if (configuredIds.contains(section.id) &&
          _configuredSectionMatchesScope(
            series,
            'frame',
            section.id,
            sliding: true,
          ) &&
          !isSlidingFrameExtension(section.toMap())) {
        return section;
      }
    }

    // Older catalogues do not have SeriesDesignRoles yet. Keep the legacy
    // fallback only for those catalogues; once role metadata exists, an
    // unassigned frame must remain missing instead of borrowing an opening
    // profile.
    if (!_hasLoadedRoleMetadata(series)) {
      for (final section in series.sections) {
        if (_isFrameSection(section) &&
            !isSlidingFrameExtension(section.toMap())) {
          return section;
        }
      }
    }

    return null;
  }

  /// The sliding frame is always the two-track base frame.  Additional
  /// tracks are represented by the section assigned to `frame_extension` in
  /// the series rules, rather than by selecting a fictitious three/four-track
  /// frame from the catalogue.
  AluminumSection? getSlidingFrameExtensionSection() {
    final series = effectiveSlidingSeries;
    if (series == null) return null;

    final configuredIds =
        _seriesDesignRoleSectionIds[series.id]?['frame_extension'] ??
        const <int>{};
    if (configuredIds.isNotEmpty) {
      for (final section in series.sections) {
        if (configuredIds.contains(section.id) &&
            _configuredSectionMatchesScope(
              series,
              'frame_extension',
              section.id,
              sliding: true,
            )) {
          return section;
        }
      }
    }

    return null;
  }

  /// Number of C-profile pieces needed after the configured base frame.
  /// One physical C profile may add one, two or three rails as selected in
  /// the series rules.
  int slidingSingleTrackAdditionCount(int trackCount) {
    final safeCount = trackCount.clamp(2, 7).toInt();
    final frameMode =
        slidingFrameOverride?['design_track_mode']?.toString().toLowerCase() ??
        '';
    if (frameMode == 'complete') return 0;
    final baseRaw = slidingFrameOverride?['design_track_count'];
    final baseCount = baseRaw is num
        ? baseRaw.toInt()
        : int.tryParse(baseRaw?.toString() ?? '') ?? 2;
    final missingTracks = math.max(0, safeCount - baseCount);
    final extension = getSlidingFrameExtensionSection();
    final seriesId = effectiveSlidingSeries?.id;
    final addsRaw = seriesId == null || extension == null
        ? null
        : _seriesDesignRoleOptions[seriesId]?['frame_extension']?[extension
              .id]?['track_adds'];
    final configuredTracksPerPiece = addsRaw is num
        ? addsRaw.toInt()
        : int.tryParse(addsRaw?.toString() ?? '') ?? 1;
    final tracksPerPiece = configuredTracksPerPiece.clamp(1, 3);
    return (missingTracks / tracksPerPiece).ceil();
  }

  dynamic _selectedSlidingRoleOption(String roleKey, String optionKey) {
    final seriesId = activeSlidingSeries?.id ?? activeSeries?.id;
    if (seriesId == null) return null;
    final selectedRail = componentOverrides['الري (Rail)'];
    final selectedId = roleKey == 'rail' && selectedRail is Map
        ? selectedRail['id']
        : null;
    final parsedSelectedId = selectedId is num
        ? selectedId.toInt()
        : int.tryParse('${selectedId ?? ''}');
    final roleOptions = _seriesDesignRoleOptions[seriesId]?[roleKey];
    if (roleOptions == null || roleOptions.isEmpty) return null;
    if (parsedSelectedId != null && roleOptions.containsKey(parsedSelectedId)) {
      return roleOptions[parsedSelectedId]?[optionKey];
    }
    return roleOptions.values.first[optionKey];
  }

  /// Number of physical lower-rail pieces required for the drawing. The
  /// catalogue rule defines whether one piece represents 1, 2 or 3 rails.
  int slidingRailPieceCount(int trackCount) {
    final raw = _selectedSlidingRoleOption('rail', 'track_adds');
    final configured = raw is num
        ? raw.toInt()
        : int.tryParse('${raw ?? ''}') ?? 1;
    final railsPerPiece = configured.clamp(1, 3);
    return (trackCount.clamp(0, 7) / railsPerPiece).ceil();
  }

  int slidingTrackCountForRect(Rect frame) => zones
      .where((zone) => frame.contains(zone.boundary.center))
      .fold<int>(1, (count, zone) => math.max(count, zone.slidingTrackCount));

  /// Number of physical Seuil/C pieces required below a sliding frame.
  /// The catalogue rule defines whether one profile covers 1, 2 or 3 rails.
  int slidingSeuilPieceCount(int trackCount) {
    final raw = _selectedSlidingRoleOption('seuil', 'track_adds');
    final configured = raw is num
        ? raw.toInt()
        : int.tryParse('${raw ?? ''}') ?? 1;
    final tracksPerPiece = configured.clamp(1, 3);
    return (trackCount.clamp(0, 7) / tracksPerPiece).ceil();
  }

  /// Final catalogue-rule correction applied after calculating the clear
  /// internal rail width. A saved rule has priority over inferred defaults.
  double get slidingRailWidthAdjustmentMm {
    final raw = _selectedSlidingRoleOption('rail', 'width_adjust_mm');
    return raw is num
        ? raw.toDouble()
        : double.tryParse('${raw ?? ''}'.replaceAll(',', '.')) ?? 0.0;
  }

  bool get selectedSlidingFrameIsComplete =>
      slidingFrameOverride?['design_track_mode']?.toString().toLowerCase() ==
      'complete';

  Set<int> get supportedSlidingTrackCounts {
    final seriesId = effectiveSlidingSeries?.id;
    final result = <int>{};

    bool allowedForCurrentDrawing(
      Map<String, dynamic> options, {
      bool isFrameExtension = false,
    }) {
      return slidingFrameRoleAllowedForDrawing(
        options,
        hasShutter: hasShutter,
        isCaissonTunnel: isCaissonTunnel,
        isPvc: isSlidingPVC,
        isFrameExtension: isFrameExtension,
      );
    }

    void addCounts(Map<String, dynamic> options) {
      final count = options['design_track_count'] ?? options['track_count'];
      final parsedCount = count is num
          ? count.toInt()
          : int.tryParse(count?.toString() ?? '');
      if (parsedCount != null && parsedCount >= 2 && parsedCount <= 7) {
        result.add(parsedCount);
      }
      for (final token
          in (options['design_supported_track_counts'] ??
                  options['supported_track_counts'] ??
                  '')
              .toString()
              .split(',')) {
        final value = int.tryParse(token.trim());
        if (value != null && value >= 2 && value <= 7) result.add(value);
      }
    }

    if (seriesId == null) {
      if (slidingFrameOverride != null &&
          allowedForCurrentDrawing(slidingFrameOverride!)) {
        addCounts(slidingFrameOverride!);
      }
      return result.isEmpty ? const {2} : result;
    }
    final roles = _seriesDesignRoleOptions[seriesId];
    if (roles == null || roles.isEmpty) {
      // Compatibility for old catalogues that predate explicit frame rules.
      return const {2, 3, 4};
    }
    final frameOptions = roles['frame'];
    var hasEligibleBaseFrame = false;
    if (frameOptions != null) {
      for (final options in frameOptions.values) {
        if (!allowedForCurrentDrawing(options)) continue;
        final mode = options['track_mode']?.toString().toLowerCase() ?? 'base';
        if (mode == 'complete') {
          final count = options['track_count'];
          final parsed = count is num
              ? count.toInt()
              : int.tryParse(count?.toString() ?? '');
          if (parsed != null && parsed >= 2 && parsed <= 7) result.add(parsed);
        } else {
          hasEligibleBaseFrame = true;
          final count = options['track_count'];
          final parsed = count is num
              ? count.toInt()
              : int.tryParse(count?.toString() ?? '');
          result.add(parsed != null && parsed >= 2 && parsed <= 7 ? parsed : 2);
        }
      }
    }
    final extensionOptions = roles['frame_extension'];
    if (hasEligibleBaseFrame && extensionOptions != null) {
      for (final options in extensionOptions.values) {
        if (!allowedForCurrentDrawing(options, isFrameExtension: true)) {
          continue;
        }
        addCounts(options);
      }
    }
    return result.isEmpty ? const {2} : result;
  }

  /// Leaf choices follow the catalogue capability. A composable frame may
  /// expose 5/6 leaves; a closed three-track system remains limited to 3.
  Set<int> get supportedSlidingSashCounts {
    final tracks = supportedSlidingTrackCounts;
    final maxCount = tracks.reduce(math.max);
    final minimum = selectedZone?.content == ZoneContent.slidingSash
        ? selectedZone!.slidingTrackCount.clamp(2, 7).toInt()
        : 2;
    return {for (var count = minimum; count <= maxCount; count++) count};
  }

  /// Returns a manually selected sliding profile only when it belongs to the
  /// active sliding series.  Old orders can otherwise carry an override from
  /// a previously selected series into the quantity and cost table.
  Map<String, dynamic>? getSlidingComponentOverride(String key) {
    final candidate = componentOverrides[key];
    if (candidate is! Map) return null;
    final result = Map<String, dynamic>.from(candidate);
    final activeSeriesId = effectiveSlidingSeries?.id;
    final sourceSeriesId = result['series_id'];
    if (activeSeriesId != null &&
        sourceSeriesId != null &&
        sourceSeriesId.toString() != activeSeriesId.toString()) {
      return null;
    }
    return result;
  }

  double getSectionThicknessByCode(String code, {double fallback = 45.0}) {
    final useSliding = systemMode == 'sliding' || usesSlidingPrimaryProfiles;
    final series = useSliding ? activeSlidingSeries : activeSeries;
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
    final useSliding = systemMode == 'sliding' || usesSlidingPrimaryProfiles;
    final series = useSliding ? activeSlidingSeries : activeSeries;
    if (series == null) return null;
    for (var sec in series.sections) {
      if (sec.code.toLowerCase() == code.toLowerCase() ||
          sec.name.toLowerCase().contains(code.toLowerCase())) {
        return sec;
      }
    }
    return null;
  }

  /// Applies an order-level selection to both the drawing and its saved state.
  Future<void> setOrderSeries(AluminumSeries series) async {
    // Use the same catalogue scopes as the drawing selectors. Numeric names
    // such as 40000 do not describe whether a series is opening or sliding.
    final roles = await db.getSeriesDesignRoles(series.id);
    _rememberSeriesRoleKeys(series, roles);
    final supportsSliding = seriesSupportsDrawingScopeInSystem(
      series,
      'sliding',
    );
    final supportsOpening = seriesSupportsDrawingScopeInSystem(
      series,
      'opening',
    );
    final useSliding =
        supportsSliding && !supportsOpening ||
        usesSlidingPrimaryProfiles && !supportsOpening;
    if (useSliding) {
      await setActiveSlidingSeries(series);
      if (systemMode == 'sliding') {
        await setActiveSeries(series);
      }
    } else {
      await setActiveSeries(series);
    }
  }

  Future<void> setActiveSeries(AluminumSeries series) {
    final next = _seriesUpdateChain.then((_) => _setActiveSeries(series));
    _seriesUpdateChain = next.catchError((Object error, StackTrace stack) {});
    return next;
  }

  Future<void> _setActiveSeries(AluminumSeries series) async {
    _saveSnapshot();
    // Capture the old plinthe geometry before switching activeSeries. Once
    // the new series is assigned, plintheHeight would be read from the new
    // catalogue and the old sash bottom could no longer be recognised.
    final previousPlintheHeight = plintheHeight;
    final previousPlintheZoneIds = zones
        .where((zone) => zone.hasSashPlintheBottom)
        .map((zone) => zone.id)
        .toSet();
    final hadPreviousFramePlinthe = hasFramePlintheBottom;
    final hadPreviousPlinthe =
        hasFramePlintheBottom || previousPlintheZoneIds.isNotEmpty;
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
    loadedSeriesId = series.id;
    loadedSeriesName = series.name;
    seriesDesignConfig = await db.getSeriesDesignConfig(series.id);
    seriesTableConfig = await db.getSeriesTableConfig(series.id);
    final configuredRoleRows = await db.getSeriesDesignRoles(series.id);
    _rememberSeriesRoleKeys(series, configuredRoleRows);
    final bool isSliding =
        systemMode == 'sliding' ||
        usesSlidingPrimaryProfiles ||
        isSlidingSeriesForDrawing(series);
    final strictProfileRoles = configuredRoleRows.isNotEmpty;
    bool configuredRoleRowAllowed(Map<String, dynamic> row) {
      if (row['is_visible'] == 0 || row['show_in_quantity'] == 0) {
        return false;
      }
      if (!_roleScopeMatches(
        row['usage_scope']?.toString(),
        sliding: isSliding,
      )) {
        return false;
      }
      final glassRule = row['show_when_glass']?.toString().trim() ?? 'any';
      if (glassRule == 'simple' && !hasSimpleGlassForReducer) {
        return false;
      }
      if (glassRule == 'double' && !hasDoubleGlassForRules) return false;
      if (hasShutter && row['allowed_with_shutter'] == 0) return false;
      return true;
    }

    List<AluminumSection> configuredSectionsFor(Iterable<String> roleKeys) {
      final ids = configuredRoleRows
          .where(
            (row) =>
                roleKeys.contains(
                  normalizeSeriesDesignRoleKey(row['role_key']),
                ) &&
                configuredRoleRowAllowed(row),
          )
          .map((row) {
            final rawId = row['section_id'];
            return rawId is num
                ? rawId.toInt()
                : int.tryParse(rawId?.toString() ?? '');
          })
          .whereType<int>()
          .toSet();
      if (ids.isEmpty) return <AluminumSection>[];
      return series.sections
          .where((section) => ids.contains(section.id))
          .map(
            (section) =>
                _sectionWithConfiguredRoleOptions(series, roleKeys, section),
          )
          .toList();
    }

    if (systemMode == 'sliding' || isSliding) {
      activeSlidingSeries ??= series;
      slidingSeriesTableConfig = seriesTableConfig;
    }

    if (seriesChanged) {
      if (systemMode == 'sliding' || isSliding) {
        activeSlidingSeries = series;
        // Availability in a newly selected sliding series starts enabled.
        // Loading a saved drawing can still restore an explicit false value
        // afterwards through model serialization.
        if (getConfiguredSectionForRole('cache_rail', useSlidingSeries: true) !=
            null) {
          useOptionalCacheRail = true;
        }
        slidingFrameOverride = null;
        slidingSashOverride = null;
      }
      frameOverride = null;
      sashOverride = null;
      componentOverrides.remove('تقسيم الزجاج (Mullion)');
      componentOverrides.remove('باكيت الزجاج (Parclose)');
      componentOverrides.remove('الباتمو (Batmo)');
      componentOverrides.remove('بوشون باتمو (Bouchon Batmo)');
      componentOverrides.remove('حديد الإطار (Renfort Frame)');
      componentOverrides.remove('حديد الظلفة (Renfort Sash)');
      componentOverrides.remove('حديد الظلفة الخاص بالمفاصل');
      componentOverrides.remove('البارداج (Bardage)');
      componentOverrides.remove('البانو (Panneau)');
      _clearAccessoryOverrides();

      // Section identifiers from another series (for example TPR) cannot be
      // reused safely. Preserve the user's mullion type, then resolve its
      // concrete frame section from the newly selected series.
      if (affectsVisibleDivisions) {
        mullionProfiles.clear();
        groovedMullionCavityOnPositiveSide.clear();
        mullionSectionOverrides.clear();
      }

      // Reset plinthe state: check if new series has a plinthe section
      // If it doesn't, disable plinthe and restore hasBottomFrame
      componentOverrides.remove('بلانت (Plinthe)');
      final configuredPlinthes = configuredSectionsFor(const ['plant']);
      final hasPlintheInNewSeries = configuredRoleRows.isNotEmpty
          ? configuredPlinthes.isNotEmpty
          : series.sections.any((s) {
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
        if (hadPreviousPlinthe) {
          hasFramePlintheBottom = false;
          hasBottomFrame = true;
          showBottomWall = true;
          for (var z in zones) {
            z.hasSashPlintheBottom = false;
            if (hadPreviousFramePlinthe ||
                previousPlintheZoneIds.contains(z.id) ||
                (z.boundary.bottom - (height - previousPlintheHeight)).abs() <
                    5.0) {
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

      // Initialize the counterpart from the same system, but never replace
      // the series already used by existing sliding geometry.
      if (systemMode == 'mixed' &&
          !(activeSlidingSeries != null &&
              zones.any((zone) => zone.content == ZoneContent.slidingSash))) {
        final currentSystem = profileSystemForSeries(availableSystems, series);
        if (currentSystem != null) {
          AluminumSeries? newSliding;
          for (final candidate in currentSystem.series) {
            if (candidate.id != series.id &&
                seriesSupportsDrawingScope(
                  candidate,
                  'sliding',
                  profile: currentSystem,
                )) {
              newSliding = candidate;
              break;
            }
          }

          // If only one series has explicit sliding role metadata, use it
          // before the system-wide fallback. This prevents an unlabelled
          // opening sibling from being selected as the automatic counterpart.
          if (newSliding == null) {
            for (final candidate in currentSystem.series) {
              if (candidate.id != series.id &&
                  seriesSupportsDrawingScopeInSystem(
                    candidate,
                    'sliding',
                    profile: currentSystem,
                  )) {
                newSliding = candidate;
                break;
              }
            }
          }

          // Imported catalogues may contain a multi-series system without
          // role metadata or recognizable names. In that case, use the first
          // series other than the selected opening series as the counterpart.
          if (newSliding == null && currentSystem.series.length > 1) {
            final hasKnownRole = currentSystem.series.any(
              (candidate) =>
                  seriesSupportsDrawingScopeInSystem(
                    candidate,
                    'opening',
                    profile: currentSystem,
                  ) ||
                  seriesSupportsDrawingScopeInSystem(
                    candidate,
                    'sliding',
                    profile: currentSystem,
                  ),
            );
            if (!hasKnownRole) {
              for (final candidate in currentSystem.series) {
                if (candidate.id != series.id) {
                  newSliding = candidate;
                  break;
                }
              }
            }
          }

          if (newSliding != null) {
            if (activeSlidingSeries?.id != newSliding.id) {
              await _setActiveSlidingSeries(newSliding);
            }
          } else {
            activeSlidingSeries = null;
            slidingFrameOverride = null;
            slidingSashOverride = null;
            _clearSlidingProfileOverrides();
          }
        }
      }
    }

    // Set default frame and sash if they are null
    if (isSliding) {
      if (slidingFrameOverride == null) {
        final frames = configuredSectionsFor(const ['frame']);
        if (frames.isNotEmpty) {
          final candidates = hasShutter
              ? _compatibleFrameCandidatesForSeries(series, frames)
              : (!_isPvcSeries(series)
                    ? frames
                          .where(
                            (frame) => !_sectionHasIntegratedSideCover(frame),
                          )
                          .toList()
                    : frames);
          if (candidates.isNotEmpty) {
            final selected = _preferredSlidingFrameForTrackCount(
              candidates,
              series,
              _requestedSlidingTrackCount(),
            );
            slidingFrameOverride = _slidingFrameMapWithRoleOptions(
              selected,
              series,
            );
          }
        }
      }
      if (slidingSashOverride == null) {
        final sashes = configuredSectionsFor(const ['sash', 'sash_extension']);
        if (sashes.isNotEmpty) {
          slidingSashOverride = sashes.first.toMap();
        }
      }
    }

    if (frameOverride == null) {
      final frames = configuredSectionsFor(const ['frame']);

      if (frames.isNotEmpty) {
        // Only a regular box above an aluminium window requires a plain
        // frame. A tunnel box permits the frame's integrated couvre-joint.
        final candidates = _compatibleFrameCandidatesForSeries(series, frames);
        if (candidates.isNotEmpty) {
          frameOverride = _preferredFrameForSeries(candidates, series).toMap();
        }
      }
    }

    if (sashOverride == null) {
      final sashes = configuredSectionsFor(const ['sash', 'sash_extension']);

      if (sashes.isNotEmpty) {
        sashOverride = sashes.first.toMap();
      }
    }

    // Plant/Plinthe is an independent series role. Do not derive it from
    // the selected sash: a thin or thick sash may use the same plant.
    final configuredPlinthes = configuredSectionsFor(const ['plant']);
    if (configuredPlinthes.isNotEmpty &&
        !componentOverrides.containsKey('بلانت (Plinthe)')) {
      componentOverrides['بلانت (Plinthe)'] = configuredPlinthes.first.toMap();
    }

    final reducers = configuredSectionsFor(const ['reducer']);
    if (reducers.isNotEmpty && hasSimpleGlassForReducer) {
      final rMap = Map<String, dynamic>.from(reducers.first.toMap());
      final rId = rMap['id'] as int?;
      if (rId != null) {
        final colorId = selectedDbColor?['id'] as int?;
        double price = await db.getSectionPrice(rId, colorId);
        if (price <= 0) {
          price = ((rMap['price_dzd'] ?? rMap['price'] ?? 0.0) as num)
              .toDouble();
        }
        rMap['calculated_price'] = price;
      }
      componentOverrides['ريديكتور (Réducteur)'] = rMap;
      componentOverrides.remove('مخفض الزجاج (Réducteur)');
    } else if (seriesHasConfiguredRoles(series)) {
      clearReducerOverride();
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
      if (!strictProfileRoles &&
          !componentOverrides.containsKey('تقسيم الزجاج (Mullion)')) {
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
      if (!strictProfileRoles &&
          !componentOverrides.containsKey('باكيت الزجاج (Parclose)')) {
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
    if (!strictProfileRoles &&
        !componentOverrides.containsKey('الباتمو (Batmo)')) {
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
    if (!strictProfileRoles &&
        !componentOverrides.containsKey('بوشون باتمو (Bouchon Batmo)')) {
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
    if (!strictProfileRoles &&
        bouchons2.isNotEmpty &&
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
    if (!strictProfileRoles && parcloses.isNotEmpty) {
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
      if (t.contains('sash') || t.contains('ouvrant') || t.contains('ظلفة')) {
        return false;
      }
      if (n.contains('sash') || n.contains('ouvrant') || n.contains('ظلفة')) {
        return false;
      }
      return t.contains('mullion') ||
          t.contains('traverse') ||
          t.contains('تقسيم');
    }).toList();
    if (!strictProfileRoles &&
        mullions.isNotEmpty &&
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
    if (!strictProfileRoles &&
        rails.isNotEmpty &&
        !componentOverrides.containsKey('الري (Rail)')) {
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
    if (!strictProfileRoles &&
        chicanes.isNotEmpty &&
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

    var bardages = configuredSectionsFor(const ['bardage']);
    if (bardages.isEmpty && !strictProfileRoles) {
      bardages = series.sections.where((s) {
        final t = s.type.toLowerCase().trim();
        final n = s.name.toLowerCase().trim();
        return isBardagePanelSubtype(t) || isBardagePanelSubtype(n);
      }).toList();
    }
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

    final panneaux = configuredSectionsFor(const ['panneau']);
    if (panneaux.isNotEmpty &&
        !componentOverrides.containsKey('البانو (Panneau)')) {
      final rMap = Map<String, dynamic>.from(panneaux.first.toMap());
      final rId = rMap['id'] as int;
      final colorId = selectedDbColor?['id'] as int?;
      double price = await db.getSectionPrice(rId, colorId);
      if (price <= 0) {
        price = ((rMap['price_dzd'] ?? rMap['price'] ?? 0.0) as num).toDouble();
      }
      rMap['calculated_price'] = price;
      componentOverrides['البانو (Panneau)'] = rMap;
    }

    updateProfileThickness();
    if (seriesChanged && affectsVisibleDivisions) {
      _synchronizeDivisionGapsForSeries(
        previousFrameThickness,
        previousMullionThickness,
      );
    }
    updateAllSashThicknesses();
    _synchronizeSharedSideCover();
    await _loadColorsForProfile(series.profileId);
    await _ensureParcloseForCurrentGlass();
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

  Future<void> setActiveSlidingSeries(AluminumSeries series) {
    final next = _seriesUpdateChain.then(
      (_) => _setActiveSlidingSeries(series),
    );
    _seriesUpdateChain = next.catchError((Object error, StackTrace stack) {});
    return next;
  }

  Future<void> _setActiveSlidingSeries(AluminumSeries series) async {
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
    loadedSlidingSeriesId = series.id;
    loadedSlidingSeriesName = series.name;
    seriesDesignConfig = await db.getSeriesDesignConfig(series.id);
    slidingSeriesTableConfig = await db.getSeriesTableConfig(series.id);
    final configuredRoleRows = await db.getSeriesDesignRoles(series.id);
    _rememberSeriesRoleKeys(series, configuredRoleRows);
    final strictProfileRoles = configuredRoleRows.isNotEmpty;
    bool configuredRoleRowAllowed(Map<String, dynamic> row) {
      if (row['is_visible'] == 0 || row['show_in_quantity'] == 0) {
        return false;
      }
      if (!_roleScopeMatches(row['usage_scope']?.toString(), sliding: true)) {
        return false;
      }
      final glassRule = row['show_when_glass']?.toString().trim() ?? 'any';
      if (glassRule == 'simple' && !hasSimpleGlassForReducer) {
        return false;
      }
      if (glassRule == 'double' && !hasDoubleGlassForRules) return false;
      if (hasShutter && row['allowed_with_shutter'] == 0) return false;
      return true;
    }

    List<AluminumSection> configuredSectionsFor(Iterable<String> roleKeys) {
      final ids = configuredRoleRows
          .where(
            (row) =>
                roleKeys.contains(
                  normalizeSeriesDesignRoleKey(row['role_key']),
                ) &&
                configuredRoleRowAllowed(row),
          )
          .map((row) {
            final rawId = row['section_id'];
            return rawId is num
                ? rawId.toInt()
                : int.tryParse(rawId?.toString() ?? '');
          })
          .whereType<int>()
          .toSet();
      if (ids.isEmpty) return <AluminumSection>[];
      return series.sections
          .where((section) => ids.contains(section.id))
          .map(
            (section) =>
                _sectionWithConfiguredRoleOptions(series, roleKeys, section),
          )
          .toList();
    }

    if (seriesChanged) {
      slidingFrameOverride = null;
      slidingSashOverride = null;
      hasInternalSlidingSideCover = false;
      selectedInternalSlidingSideCover = null;
      internalSlidingSideCoverOverride = null;
      _clearSlidingProfileOverrides();
      _clearAccessoryOverrides();
      componentOverrides.remove('البارداج (Bardage)');
      componentOverrides.remove('البانو (Panneau)');

      if (affectsVisibleDivisions) {
        mullionProfiles.clear();
        groovedMullionCavityOnPositiveSide.clear();
        mullionSectionOverrides.clear();
      }

      // Auto-matching opening series for System Mixed
      if (systemMode == 'mixed' || activeSeries != null) {
        final currentSystem = profileSystemForSeries(availableSystems, series);
        final openingSystem = profileSystemForSeries(
          availableSystems,
          activeSeries,
        );
        final canAutoMatchOpening =
            currentSystem != null &&
            (systemMode == 'mixed' ||
                activeSeries == null ||
                openingSystem == null ||
                profileSystemsShareMaterial(currentSystem, openingSystem));
        if (canAutoMatchOpening) {
          final openingMissingOrForeign =
              activeSeries == null ||
              (!zones.any(
                    (zone) =>
                        zone.content == ZoneContent.singleSash ||
                        zone.content == ZoneContent.doubleSash,
                  ) &&
                  (openingSystem == null ||
                      !profileSystemsShareMaterial(
                        currentSystem,
                        openingSystem,
                      )));
          if (openingMissingOrForeign) {
            AluminumSeries? newOpening;
            for (var s in currentSystem.series) {
              if (seriesSupportsDrawingScope(
                s,
                'opening',
                profile: currentSystem,
              )) {
                newOpening = s;
                break;
              }
            }
            if (newOpening == null) {
              for (final candidateSystem in availableSystems) {
                if (!profileSystemsShareMaterial(
                  currentSystem,
                  candidateSystem,
                )) {
                  continue;
                }
                for (final candidate in candidateSystem.series) {
                  if (seriesSupportsDrawingScopeInSystem(
                    candidate,
                    'opening',
                    profile: candidateSystem,
                  )) {
                    newOpening = candidate;
                    break;
                  }
                }
                if (newOpening != null) break;
              }
            }
            if (newOpening != null) {
              activeSeries = newOpening;
              frameOverride = null;
              sashOverride = null;
              final frames = getConfiguredSectionsForRole(
                'frame',
                useSlidingSeries: false,
              );
              if (frames.isNotEmpty) {
                final candidates = _compatibleFrameCandidatesForSeries(
                  newOpening,
                  frames,
                );
                if (candidates.isNotEmpty) {
                  frameOverride = _preferredFrameForSeries(
                    candidates,
                    newOpening,
                  ).toMap();
                }
              }
              final sashes = getConfiguredSectionsForRole(
                'sash',
                useSlidingSeries: false,
              );
              if (sashes.isNotEmpty) {
                sashOverride = sashes.first.toMap();
              }
              updateProfileThickness();
              updateAllSashThicknesses();
            } else if (systemMode == 'mixed') {
              activeSeries = null;
              frameOverride = null;
              sashOverride = null;
            }
          }
        }
      }
    }

    if (slidingFrameOverride == null) {
      // `frame` is the mandatory two-track base.  `frame_extension` is a
      // separate one-track profile and must never replace the base frame.
      final frames = configuredSectionsFor(const ['frame']);

      if (frames.isNotEmpty) {
        // Aluminium sliding frames should start without an integrated cover;
        // the cover is controlled as a separate profile when it is needed.
        final candidates = hasShutter
            ? _compatibleFrameCandidatesForSeries(series, frames)
            : (!_isPvcSeries(series)
                  ? frames
                        .where(
                          (frame) => !_sectionHasIntegratedSideCover(frame),
                        )
                        .toList()
                  : frames);
        if (candidates.isNotEmpty) {
          final selected = _preferredSlidingFrameForTrackCount(
            candidates,
            series,
            _requestedSlidingTrackCount(),
          );
          slidingFrameOverride = _slidingFrameMapWithRoleOptions(
            selected,
            series,
          );
        }
      }
    }

    if (slidingSashOverride == null) {
      final sashes = configuredSectionsFor(const ['sash', 'sash_extension']);

      if (sashes.isNotEmpty) {
        slidingSashOverride = sashes.first.toMap();
      }
    }

    var bardages = configuredSectionsFor(const ['bardage']);
    if (bardages.isEmpty && !strictProfileRoles) {
      bardages = series.sections.where((s) {
        final t = s.type.toLowerCase().trim();
        final n = s.name.toLowerCase().trim();
        return isBardagePanelSubtype(t) || isBardagePanelSubtype(n);
      }).toList();
    }
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

    final panneaux = configuredSectionsFor(const ['panneau']);
    if (panneaux.isNotEmpty &&
        !componentOverrides.containsKey('البانو (Panneau)')) {
      final rMap = Map<String, dynamic>.from(panneaux.first.toMap());
      final rId = rMap['id'] as int;
      final colorId = selectedDbColor?['id'] as int?;
      double price = await db.getSectionPrice(rId, colorId);
      if (price <= 0) {
        price = ((rMap['price_dzd'] ?? rMap['price'] ?? 0.0) as num).toDouble();
      }
      rMap['calculated_price'] = price;
      componentOverrides['البانو (Panneau)'] = rMap;
    }

    var rails = configuredSectionsFor(const ['rail']);
    if (rails.isEmpty && !strictProfileRoles) {
      rails = series.sections.where((s) {
        final t = s.type.toLowerCase().trim();
        return t == 'rail' ||
            t.contains('rail') ||
            t == 'الري' ||
            t.contains('الري') ||
            t == 'راي' ||
            t.contains('راي');
      }).toList();
    }
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
    if (chicanes.isEmpty && !strictProfileRoles) {
      chicanes = series.sections.where((s) {
        final t = s.type.toLowerCase().trim();
        final n = s.name.toLowerCase().trim();
        return t.contains('chicane') ||
            n.contains('chicane') ||
            t.contains('شيكان') ||
            n.contains('شيكان');
      }).toList();
    }
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

    final reducers = configuredSectionsFor(const ['reducer']);
    if (reducers.isNotEmpty && hasSimpleGlassForReducer) {
      final rMap = Map<String, dynamic>.from(reducers.first.toMap());
      final rId = rMap['id'] as int?;
      if (rId != null) {
        final colorId = selectedDbColor?['id'] as int?;
        double price = await db.getSectionPrice(rId, colorId);
        if (price <= 0) {
          price = ((rMap['price_dzd'] ?? rMap['price'] ?? 0.0) as num)
              .toDouble();
        }
        rMap['calculated_price'] = price;
      }
      componentOverrides['ريديكتور (Réducteur)'] = rMap;
      componentOverrides.remove('مخفض الزجاج (Réducteur)');
    } else if (seriesHasConfiguredRoles(series)) {
      clearReducerOverride();
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

    _synchronizeSharedSideCover();
    await _loadColorsForProfile(series.profileId);
    await _ensureParcloseForCurrentGlass();
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
    shutterWidthWarning = null;
    shutterMaximumWidthMm = null;
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

    // Saved drawings can contain an older, reduced blade map. Refresh the
    // limit fields from the catalogue so automatic selection and warnings
    // always use the current database value.
    if (database != null && blade != null && blade['id'] != null) {
      final bladeId = (blade['id'] as num?)?.toInt();
      if (bladeId != null) {
        final catalogRows = await database.query(
          'ShutterComponents',
          where: 'id = ?',
          whereArgs: [bladeId],
          limit: 1,
        );
        if (catalogRows.isNotEmpty) {
          final hydrated = Map<String, dynamic>.from(blade);
          for (final key in const [
            'name',
            'component_type',
            'max_width_mm',
            'bar_length_m',
            'shutter_subtype',
          ]) {
            hydrated[key] = catalogRows.first[key];
          }
          blade = hydrated;
          shutterLame = hydrated['name']?.toString() ?? shutterLame;
          componentOverrides['الشرائح (Lames)'] = hydrated;
        }
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

    // Choose a safe blade automatically when the current blade was not picked
    // by the user.  The smallest blade that supports the current window is
    // preferred, which prevents a weak blade from being used while avoiding
    // an unnecessarily oversized blade.  A manual choice is never replaced:
    // it remains in the drawing/BOM and receives a clear warning instead.
    if (database != null && width > 0) {
      try {
        final bladeRows = await database.query(
          'ShutterComponents',
          where:
              "LOWER(TRIM(component_type)) IN ('blade', 'lame') AND (is_active = 1 OR is_active IS NULL)",
          orderBy: 'name ASC',
        );
        final blades = bladeRows
            .map(Map<String, dynamic>.from)
            .where(isShutterBladeComponent)
            .toList();
        final currentBladeIsManual = _componentWasManuallySelected(blade);

        if (blades.isNotEmpty && !currentBladeIsManual) {
          final currentId = (blade?['id'] as num?)?.toInt();
          final currentLimit = blade == null
              ? 0.0
              : _shutterBladeEffectiveMaxWidthMm(blade);
          final currentSupportsWidth = blade != null && currentLimit >= width;

          if (!currentSupportsWidth) {
            blades.sort((a, b) {
              final limitCompare = _shutterBladeEffectiveMaxWidthMm(
                a,
              ).compareTo(_shutterBladeEffectiveMaxWidthMm(b));
              if (limitCompare != 0) return limitCompare;
              return (a['id'] as num? ?? 0).compareTo(b['id'] as num? ?? 0);
            });
            final compatible = blades
                .where(
                  (candidate) =>
                      _shutterBladeEffectiveMaxWidthMm(candidate) >= width,
                )
                .toList();
            final replacement = compatible.isNotEmpty
                ? compatible.first
                : blades.last;
            final replacementId = (replacement['id'] as num?)?.toInt();
            if (replacementId != null && replacementId != currentId) {
              final automaticSelection = Map<String, dynamic>.from(replacement)
                ..['manual_selection'] = false
                ..['user_selected'] = false
                ..['automatic_selection'] = true;
              componentOverrides['الشرائح (Lames)'] = automaticSelection;
              blade = automaticSelection;
              shutterLame =
                  automaticSelection['name']?.toString() ?? shutterLame;
            }
          }
        }

        if (blade != null) {
          // The automatic replacement may have selected an extruded blade;
          // apply the motor requirement to the replacement as well.
          final replacementSubtype =
              (blade['shutter_subtype']?.toString() ?? '').toLowerCase();
          final replacementName = (blade['name']?.toString() ?? '')
              .toLowerCase();
          if (replacementSubtype == 'extruded' ||
              replacementName.contains('extruded') ||
              replacementName.contains('إكسترودي') ||
              (isPVC && !isCaissonTunnel && _isX3dShutterComponent(blade))) {
            shutterMechanism = 'محرك';
          }
          shutterMaximumWidthMm = _shutterBladeConfiguredMaxWidthMm(blade);
          final effectiveLimit = maximumAllowedShutterWidthMm;
          if (width > effectiveLimit) {
            final configuredLimit = shutterMaximumWidthMm!;
            shutterWidthWarning =
                'عرض الستار ${width.toStringAsFixed(0)} مم يتجاوز الحد الأقصى المسجل '
                'للامة ${blade['name'] ?? shutterLame}: '
                '${configuredLimit.toStringAsFixed(0)} مم.';
            if (effectiveLimit < configuredLimit) {
              shutterWidthWarning =
                  '${shutterWidthWarning!} الحد الفعلي لطول البارة هو '
                  '${effectiveLimit.toStringAsFixed(0)} مم.';
            }
          }
        }
      } catch (e) {
        print('Error resolving shutter blade width limit: $e');
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
          final rawManualBox = componentOverrides['الصندوق (Caisson)'];
          final manualBox = rawManualBox is Map
              ? Map<String, dynamic>.from(rawManualBox)
              : null;
          final manualBoxWasUserSelected =
              manualBox != null &&
              (manualBox['manual_selection'] == true ||
                  manualBox['is_manual_selection'] == true ||
                  manualBox['user_selected'] == true);
          if (manualBoxWasUserSelected && manualBox['id'] != -999) {
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

            if (manualBoxWasUserSelected &&
                chosenBoxSize != null &&
                chosenBoxSize >= minFallback) {
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
          final ruleRole = switch (overrideName) {
            'الصندوق (Caisson)' => 'shutter_box',
            'الشرائح (Lames)' => 'shutter_blade',
            'الشريحة النهائية (Lame Finale)' => 'shutter_final_blade',
            'السكك (Coulisses)' => 'shutter_track',
            'المحور (Axe)' => 'shutter_axis',
            _
                when overrideName.contains('كيت') ||
                    overrideName.contains('Kit') =>
              'shutter_kit',
            _ => '',
          };
          if (ruleRole.isNotEmpty) {
            final ruleRows = await db.getCatalogItemRules(
              itemTable: 'ShutterComponents',
              roleKeys: [ruleRole],
            );
            for (final rule in ruleRows) {
              if (rule['show_in_quantity'] == 0) continue;
              final itemId = (rule['item_id'] as num?)?.toInt();
              if (itemId == null) continue;
              final rows = await myDb.query(
                'ShutterComponents',
                where: 'id = ? AND (is_active = 1 OR is_active IS NULL)',
                whereArgs: [itemId],
                limit: 1,
              );
              if (rows.isEmpty) continue;
              res = rows;
              break;
            }
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

      Future<double> resolveShutterAccessoryPrice(
        Map<String, dynamic> accessory,
      ) async {
        final accessoryId = accessory['id'];
        if (accessoryId == null) return 0.0;
        final selectedColorId = effectiveShutterColor?['id'];
        try {
          if (selectedColorId != null) {
            final colorRows = await myDb.query(
              'AccessoryColorPrices',
              columns: const ['price'],
              where: 'accessory_id = ? AND color_id = ?',
              whereArgs: [accessoryId, selectedColorId],
              limit: 1,
            );
            if (colorRows.isNotEmpty) {
              final value = colorRows.first['price'];
              final price = value is num
                  ? value.toDouble()
                  : double.tryParse(value?.toString() ?? '') ?? 0.0;
              if (price > 0) return price;
            }
          }
        } catch (_) {}
        final rawPrice = accessory['price_dzd'] ?? accessory['price'];
        return rawPrice is num
            ? rawPrice.toDouble()
            : double.tryParse(rawPrice?.toString() ?? '') ?? 0.0;
      }

      Future<void> assignShutterScrewDefault(
        String overrideName,
        String flagColumn,
        List<String> keywords,
      ) async {
        if (componentOverrides.containsKey(overrideName)) return;
        final ruleRole = switch (flagColumn) {
          'is_kit_screw' => 'kit_screw',
          'is_caisson_screw' => 'box_screw',
          'is_moteur_screw' => 'motor_screw',
          _ => '',
        };
        if (ruleRole.isNotEmpty) {
          final ruleRows = await db.getCatalogItemRules(
            itemTable: 'Accessories',
            roleKeys: [ruleRole],
          );
          for (final rule in ruleRows) {
            if (rule['show_in_quantity'] == 0) continue;
            final itemId = (rule['item_id'] as num?)?.toInt();
            if (itemId == null) continue;
            final rows = await myDb.query(
              'Accessories',
              where: 'id = ? AND (is_active = 1 OR is_active IS NULL)',
              whereArgs: [itemId],
              limit: 1,
            );
            if (rows.isEmpty) continue;
            final selected = Map<String, dynamic>.from(rows.first);
            selected['calculated_price'] = await resolveShutterAccessoryPrice(
              selected,
            );
            selected['catalog_source'] = 'Accessories';
            componentOverrides[overrideName] = selected;
            return;
          }
        }
        const screwKeywords = ['vis', 'screw', 'برغي', 'براغي'];
        final keywordClauses = <String>[];
        final screwClauses = <String>[];
        final keywordArgs = <Object?>[];
        final screwArgs = <Object?>[];
        for (final keyword in keywords) {
          keywordClauses.add('LOWER(name) LIKE ?');
          keywordClauses.add('LOWER(type) LIKE ?');
          keywordArgs.add('%${keyword.toLowerCase()}%');
          keywordArgs.add('%${keyword.toLowerCase()}%');
        }
        for (final keyword in screwKeywords) {
          screwClauses.add('LOWER(name) LIKE ?');
          screwClauses.add('LOWER(type) LIKE ?');
          screwArgs.add('%${keyword.toLowerCase()}%');
          screwArgs.add('%${keyword.toLowerCase()}%');
        }
        final args = <Object?>[...keywordArgs, ...screwArgs];
        try {
          final rows = await myDb.query(
            'Accessories',
            where:
                '($flagColumn = 1 OR ((${keywordClauses.join(' OR ')}) AND (${screwClauses.join(' OR ')}))) AND (is_active = 1 OR is_active IS NULL)',
            whereArgs: args,
            orderBy: 'CASE WHEN $flagColumn = 1 THEN 0 ELSE 1 END ASC, id ASC',
            limit: 1,
          );
          if (rows.isEmpty) return;
          final selected = Map<String, dynamic>.from(rows.first);
          selected['calculated_price'] = await resolveShutterAccessoryPrice(
            selected,
          );
          selected['catalog_source'] = 'Accessories';
          componentOverrides[overrideName] = selected;
        } catch (_) {
          try {
            final rows = await myDb.query(
              'Accessories',
              where:
                  '((${keywordClauses.join(' OR ')}) AND (${screwClauses.join(' OR ')})) AND (is_active = 1 OR is_active IS NULL)',
              whereArgs: args,
              orderBy: 'id ASC',
              limit: 1,
            );
            if (rows.isEmpty) return;
            final selected = Map<String, dynamic>.from(rows.first);
            selected['calculated_price'] = await resolveShutterAccessoryPrice(
              selected,
            );
            selected['catalog_source'] = 'Accessories';
            componentOverrides[overrideName] = selected;
          } catch (_) {}
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
      await assignShutterScrewDefault('براغي الكيت', 'is_kit_screw', [
        'kit',
        'كيت',
      ]);
      await assignShutterScrewDefault('براغي الصندوق', 'is_caisson_screw', [
        'caisson',
        'box',
        'صندوق',
      ]);
      await assignShutterScrewDefault('براغي المحرك', 'is_moteur_screw', [
        'moteur',
        'motor',
        'محرك',
      ]);

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

  bool _isParcloseSection(AluminumSection section) {
    final type = section.type.toLowerCase();
    final name = section.name.toLowerCase();
    return section.code.trim() == '514' ||
        type.contains('parclose') ||
        name.contains('parclose') ||
        type.contains('باكيت') ||
        name.contains('باكيت');
  }

  /// Whether this catalogue actually retains glazing with a parclose.  A
  /// configured (but empty) glazing-bead role means that the sash itself is
  /// the glazing pocket; never fall back to an unrelated legacy parclose.
  bool hasGlazingBeadForContext({bool? sliding}) {
    final useSliding =
        sliding ??
        (systemMode == 'sliding' ||
            (selectedZone?.content == ZoneContent.slidingSash));
    final series = useSliding ? activeSlidingSeries : activeSeries;
    if (series == null) return false;
    final configured = getConfiguredSectionsForRole(
      'glazing_bead',
      useSlidingSeries: useSliding,
    );
    if (configured.isNotEmpty) return true;
    if (seriesHasConfiguredRoles(series)) return false;
    return series.sections.any(_isParcloseSection);
  }

  double? sashGlassCapacityForContext({bool? sliding}) {
    final useSliding =
        sliding ??
        (systemMode == 'sliding' ||
            (selectedZone?.content == ZoneContent.slidingSash));
    final sash = useSliding
        ? slidingSashOverride ??
              getSlidingSectionByType('sash_sliding')?.toMap() ??
              getSlidingSectionByType('sash')?.toMap()
        : sashOverride ?? getSectionByType('sash')?.toMap();
    // Saved drawings contain a snapshot of the section. Capacity is catalogue
    // metadata, not a drawing override: refresh it by the same section ID.
    final series = useSliding ? effectiveSlidingSeries : activeSeries;
    final selectedId = int.tryParse('${sash?['id'] ?? ''}');
    AluminumSection? currentSection;
    if (selectedId != null && series != null) {
      for (final section in series.sections) {
        if (section.id == selectedId) {
          currentSection = section;
          break;
        }
      }
    }
    final raw =
        currentSection?.maxGlassThickness ?? sash?['max_glass_thickness'];
    final capacity = raw is num
        ? raw.toDouble()
        : double.tryParse(raw?.toString() ?? '');
    return capacity != null && capacity > 0 ? capacity : null;
  }

  /// The usable glazing pocket.  With a real parclose its capacity wins; in
  /// series without parclose the selected sash's max-glass field is the sole
  /// source of truth.
  double? glazingCapacityForStructure(
    GlassStructure structure, {
    bool? sliding,
  }) {
    final useSliding =
        sliding ??
        (systemMode == 'sliding' ||
            (selectedZone?.content == ZoneContent.slidingSash));
    if (hasGlazingBeadForContext(sliding: useSliding)) {
      return parcloseCapacityForStructure(structure, sliding: useSliding);
    }
    return sashGlassCapacityForContext(sliding: useSliding);
  }

  double? parcloseCapacityForStructure(
    GlassStructure structure, {
    bool? sliding,
  }) {
    double? capacityOf(dynamic parclose) {
      if (parclose is! Map) return null;
      final rawValue = parclose['max_glass_thickness'];
      final maximum = rawValue is num
          ? rawValue.toDouble()
          : double.tryParse(rawValue?.toString() ?? '');
      return maximum != null && maximum > 0 ? maximum : null;
    }

    final useSliding =
        sliding ??
        (systemMode == 'sliding' ||
            (selectedZone?.content == ZoneContent.slidingSash));
    final series = useSliding ? activeSlidingSeries : activeSeries;
    if (!hasGlazingBeadForContext(sliding: useSliding)) return null;

    if (structure == GlassStructure.simple) {
      final specificSimple =
          componentOverrides['باكيت زجاج مفرد (Parclose Simple)'];
      final cap = capacityOf(specificSimple);
      if (cap != null && cap <= 14.0) return cap;

      final generic = componentOverrides['باكيت الزجاج (Parclose)'];
      final genericCap = capacityOf(generic);
      if (genericCap != null && genericCap <= 14.0) return genericCap;

      if (series != null) {
        for (final s in series.sections) {
          final isParclose = _isParcloseSection(s);
          if (isParclose &&
              s.maxGlassThickness > 0 &&
              s.maxGlassThickness <= 14.0) {
            return s.maxGlassThickness;
          }
        }
      }
      return null;
    } else if (structure == GlassStructure.double) {
      final specificDouble =
          componentOverrides['باكيت زجاج مزدوج (Parclose Double)'];
      final cap = capacityOf(specificDouble);
      if (cap != null && cap > 16.0) return cap;

      final generic = componentOverrides['باكيت الزجاج (Parclose)'];
      final genericCap = capacityOf(generic);
      if (genericCap != null && genericCap > 16.0) return genericCap;

      if (series != null) {
        if (generic is Map) {
          final rawLinkedId = generic['linked_parclose_double_id'];
          final linkedId = rawLinkedId is num
              ? rawLinkedId.toInt()
              : int.tryParse(rawLinkedId?.toString() ?? '');
          if (linkedId != null && linkedId > 0) {
            for (final s in series.sections) {
              if (s.id == linkedId && s.maxGlassThickness > 16.0) {
                return s.maxGlassThickness;
              }
            }
          }
        }

        for (final s in series.sections) {
          final isParclose = _isParcloseSection(s);
          if (isParclose && s.maxGlassThickness > 16.0) {
            return s.maxGlassThickness;
          }
        }
      }
      return null;
    }
    return selectedParcloseMaxGlassThickness;
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

    final series = activeFrameSeries;
    var requiredDoubleThickness = 0.0;
    for (final zone in zones) {
      final isSlidingZone =
          systemMode == 'sliding' || zone.content == ZoneContent.slidingSash;
      for (final glass in [zone.glass, ...zone.cellGlassSpec.values]) {
        if (glass.structure != GlassStructure.double) continue;
        requiredDoubleThickness = math.max(
          requiredDoubleThickness,
          glassPackThicknessIncludingVitrageJoint(
            glass,
            sliding: isSlidingZone,
          ),
        );
      }
    }
    final bool needsDoubleParclose = requiredDoubleThickness > 0;
    final double minimumDoubleCapacity = math.max(
      10.0,
      requiredDoubleThickness,
    );

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
          (!needsDoubleParclose || capacity >= minimumDoubleCapacity)) {
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
                section.maxGlassThickness >= minimumDoubleCapacity) {
              return section.maxGlassThickness;
            }
          }
        }
      }
    }

    if (series == null) return null;
    // With double glazing use the smallest parclose that can contain the
    // current glazing pack. If the glass grows past the selected parclose, it
    // moves to the next larger catalogue capacity.
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
                section.maxGlassThickness >= minimumDoubleCapacity;
          }).toList()..sort(
            (a, b) => a.maxGlassThickness.compareTo(b.maxGlassThickness),
          );
      return candidates.isEmpty ? null : candidates.first.maxGlassThickness;
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
    bool jointTwoSides = true,
    double? jointThickness,
    bool? sliding,
  }) {
    final selectedUsesSliding =
        sliding ??
        (systemMode == 'sliding' ||
            (selectedZone != null
                ? selectedZone!.content == ZoneContent.slidingSash
                : usesSlidingPrimaryProfiles));
    final maximum = glazingCapacityForStructure(
      GlassStructure.double,
      sliding: selectedUsesSliding,
    );
    if (maximum == null) return null;
    final effectiveJointThickness =
        jointThickness ?? selectedVitrageJointThickness(fallback: 2.0);
    final jointAllowance = selectedUsesSliding
        ? effectiveJointThickness * (jointTwoSides ? 2 : 1)
        : effectiveJointThickness +
              selectedBourrageJointThickness(doubleGlass: true, fallback: 2.0);
    final remaining =
        maximum - thicknessOuter - thicknessInner - jointAllowance;
    if (remaining <= 0) return null;
    return _nearestIntercallThickness(remaining);
  }

  /// Recalculates each double-glazing spacer after the user selects another
  /// parclose. The spacer is a consequence of the glazing panes and the
  /// parclose capacity, rather than a free manual choice.
  void fitDoubleGlassIntercallsToSelectedParclose() {
    var changed = false;

    GlassSpecification fit(
      GlassSpecification specification, {
      required bool sliding,
    }) {
      if (specification.structure != GlassStructure.double) {
        return specification;
      }
      final suggested = suggestedIntercallThicknessForDoubleGlass(
        thicknessOuter:
            specification.thicknessOuter ?? kDefaultGlassPaneThickness,
        thicknessInner:
            specification.thicknessInner ?? kDefaultGlassPaneThickness,
        jointTwoSides: specification.jointTwoSides,
        sliding: sliding,
      );
      if (suggested == null || suggested == specification.intercallThickness) {
        return specification;
      }
      changed = true;
      return specification.copyWith(intercallThickness: suggested);
    }

    for (final zone in zones) {
      final zoneUsesSliding =
          systemMode == 'sliding' || zone.content == ZoneContent.slidingSash;
      zone.glass = fit(zone.glass, sliding: zoneUsesSliding);
      if (zone.cellGlassSpec.isNotEmpty) {
        zone.cellGlassSpec = zone.cellGlassSpec.map(
          (key, value) => MapEntry(key, fit(value, sliding: zoneUsesSliding)),
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

  bool _isVitrageJointRow(Map<String, dynamic> joint) {
    final text =
        '${joint['name'] ?? ''} ${joint['type'] ?? ''} ${joint['gasket_type'] ?? ''}'
            .toLowerCase();
    return text.contains('vitrage') ||
        text.contains('فيتراج') ||
        text.contains('زجاج') ||
        text.contains('glass');
  }

  bool _catalogRowMatchesSeriesScope(
    Map<String, dynamic> row,
    AluminumSeries? series,
  ) {
    if (series == null) return true;
    final directId = int.tryParse((row['series_id'] ?? '').toString().trim());
    final linkedIds = (row['series_ids'] ?? '')
        .toString()
        .split(',')
        .map((value) => int.tryParse(value.trim()))
        .whereType<int>()
        .where((id) => id > 0)
        .toSet();
    if ((directId == null || directId <= 0) && linkedIds.isEmpty) return true;
    return directId == series.id || linkedIds.contains(series.id);
  }

  Future<double> _resolveVitrageJointThicknessForRules({
    required bool jointTwoSides,
  }) async {
    final selectedThickness = selectedVitrageJointThickness();
    if (selectedThickness > 0) {
      _lastResolvedVitrageJointThickness = selectedThickness;
      return selectedThickness;
    }

    final useSliding = systemMode == 'sliding' || usesSlidingPrimaryProfiles;
    final activeSeriesForSash = useSliding ? activeSlidingSeries : activeSeries;
    final activeSashMap = useSliding
        ? slidingSashOverride ??
              getSlidingSectionByType('sash_sliding')?.toMap() ??
              getSlidingSectionByType('sash')?.toMap()
        : sashOverride ?? getSectionByType('sash')?.toMap();
    final rawActiveSashId = activeSashMap?['id'];
    final activeSashId = rawActiveSashId is num
        ? rawActiveSashId.toInt()
        : int.tryParse(rawActiveSashId?.toString() ?? '');

    final dbInstance = SqlDatabase();
    if (activeSeriesForSash != null && activeSashId != null) {
      final positions = jointTwoSides
          ? const ['sash_inner', 'sash_outer', 'sash_glass', 'all']
          : const ['sash_inner', 'sash_glass', 'all'];
      final linkedRows = await dbInstance.getDefaultJointsForSection(
        seriesId: activeSeriesForSash.id,
        sectionId: activeSashId,
        positionKeys: positions,
      );
      for (final row in linkedRows) {
        final joint = Map<String, dynamic>.from(row);
        final thickness = _readPositiveDouble(joint['thickness']);
        if (thickness > 0 && _isVitrageJointRow(joint)) {
          _lastResolvedVitrageJointThickness = thickness;
          return thickness;
        }
      }
    }

    final joints = await dbInstance.readJoints();
    final candidates =
        joints
            .map((row) => Map<String, dynamic>.from(row))
            .where(_isVitrageJointRow)
            .where(
              (joint) =>
                  _catalogRowMatchesSeriesScope(joint, activeSeriesForSash),
            )
            .map((joint) => _readPositiveDouble(joint['thickness']))
            .where((thickness) => thickness > 0)
            .toList()
          ..sort();
    final resolved = candidates.isEmpty ? 0.0 : candidates.first;
    _lastResolvedVitrageJointThickness = resolved;
    return resolved;
  }

  /// Ensures that double glazing is paired with a parclose that can contain
  /// both panes and a real spacer. This is deliberately called from the data
  /// model (not only from the drawer), so painting, imports and future screens
  /// cannot save an incompatible glazing combination.
  Future<bool> _ensureParcloseForGlass({
    required GlassStructure structure,
    required double glassThickness,
    bool jointTwoSides = true,
    double? jointThickness,
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
    final effectiveJointThickness =
        jointThickness ??
        await _resolveVitrageJointThicknessForRules(
          jointTwoSides: jointTwoSides,
        );
    final selectedUsesSliding =
        systemMode == 'sliding' ||
        (selectedZone != null
            ? selectedZone!.content == ZoneContent.slidingSash
            : usesSlidingPrimaryProfiles);
    // A sash-only series has no parclose to select. Its own max-glass
    // thickness is enforced by the drawer/calculation, without mutating the
    // catalogue selection or inserting a phantom glazing bead.
    if (!hasGlazingBeadForContext(sliding: selectedUsesSliding)) {
      return false;
    }
    final jointAllowance = selectedUsesSliding
        ? effectiveJointThickness * (jointTwoSides ? 2.0 : 1.0)
        : effectiveJointThickness +
              selectedBourrageJointThickness(
                doubleGlass: needsDoubleParclose,
                fallback: 2.0,
              );
    final glassPackWithJoint = glassThickness + jointAllowance;
    final requiredCapacity = needsDoubleParclose
        ? math.max(10.0, glassPackWithJoint)
        : glassPackWithJoint;
    final currentTooSmall =
        currentCapacity == null || currentCapacity < requiredCapacity;
    final needsReplacement = needsDoubleParclose
        ? currentTooSmall || currentCapacity <= 10.0
        : currentTooSmall ||
              (requiredCapacity <= 10.0 &&
                  (currentCapacity > 10.0 || currentCode != '514'));
    if (!needsReplacement) return false;

    final seriesId = activeFrameSeries?.id;
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
          if ((_parcloseCapacity(linked) ?? 0) >= requiredCapacity) {
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
          requiredCapacity - 0.001,
        ],
        // Pick the next larger capacity, not the largest available profile.
        orderBy: 'max_glass_thickness ASC',
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
          "series_id = ? AND (LOWER(type) = ? OR LOWER(type) LIKE ? OR LOWER(name) LIKE ? OR TRIM(code) = ?) AND (COALESCE(max_glass_thickness, 0) >= ? OR (TRIM(code) = '514' AND ? <= 10.0))",
      whereArgs: [
        seriesId,
        'parclose',
        '%parclose%',
        '%باكيت%',
        '514',
        requiredCapacity,
        requiredCapacity,
      ],
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

  Future<bool> _ensureParcloseForCurrentGlass() async {
    if (seriesHasConfiguredRoles(activeFrameSeries)) {
      return false;
    }

    GlassStructure? targetStructure;
    double targetThickness = 0.0;
    bool targetJointTwoSides = true;

    for (final zone in zones) {
      if (zone.content == ZoneContent.empty) continue;
      for (final specification in _effectiveGlassSpecificationsForZone(zone)) {
        if (specification.structure == GlassStructure.closed) continue;
        if (specification.structure == GlassStructure.double) {
          targetStructure = GlassStructure.double;
          targetThickness = math.max(
            targetThickness,
            specification.totalThickness(allGlassCache),
          );
          targetJointTwoSides = specification.jointTwoSides;
        } else if (targetStructure != GlassStructure.double &&
            specification.structure == GlassStructure.simple) {
          targetStructure = GlassStructure.simple;
          targetThickness = math.max(
            targetThickness,
            specification.thicknessOuter ?? kDefaultGlassPaneThickness,
          );
          targetJointTwoSides = specification.jointTwoSides;
        }
      }
    }

    if (targetStructure == null) return false;
    final changed = await _ensureParcloseForGlass(
      structure: targetStructure,
      glassThickness: targetThickness,
      jointTwoSides: targetJointTwoSides,
    );
    if (changed && targetStructure == GlassStructure.double) {
      fitDoubleGlassIntercallsToSelectedParclose();
    }
    return changed;
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
        Map<String, int>.from(mullionCreationOrder),
        mullionStepCounter,
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
        zone.slidingFaceToFace = false;
        zone.slidingCentralHandle = false;
        zone.slidingSecondCentralHandle = false;
        continue;
      }

      if (zone.content == ZoneContent.slidingSash) {
        zone.lockType = LockType.none;
        zone.useOctoHandle = false;
        zone.usePvcHandleOnAlu = false;
        if (zone.slidingSashesCount != 4 || zone.slidingTrackCount != 2) {
          zone.slidingFaceToFace = false;
          zone.slidingCentralHandle = false;
          zone.slidingSecondCentralHandle = false;
        } else if (!zone.slidingCentralHandle) {
          zone.slidingSecondCentralHandle = false;
        }
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

  void _disableSlidingMontantReinforcementForPvc() {
    if (!isSlidingPVC) return;

    for (final zone in zones) {
      for (final key in zone.slidingMontantReinforced.keys.toList()) {
        if (zone.slidingMontantReinforced[key] == true) {
          zone.slidingMontantReinforced[key] = false;
        }
      }
    }

    const reinforcedKeys = [
      'قائم جانبي معزز (Sash Lateral Renforcé)',
      'قائم وسطي معزز (Sash Central Renforcé)',
    ];
    for (final key in reinforcedKeys) {
      componentOverrides.remove(key);
    }

    // A legacy save may have put a reinforced profile under the normal key.
    // Remove it so the regular series profile is resolved again.
    const normalOverrides = [
      ('قائم جانبي (Sash Lateral)', false),
      ('قائم جانبي (Lateral)', false),
      ('قائم وسطي (Sash Central)', true),
      ('قائم وسطي (Central)', true),
    ];
    for (final (key, central) in normalOverrides) {
      final value = componentOverrides[key];
      if (value is Map &&
          isSlidingMontantReinforced(
            Map<String, dynamic>.from(value),
            central: central,
          )) {
        componentOverrides.remove(key);
      }
    }
  }

  @override
  void notifyListeners() {
    _enforceMultiFramePlainFrameRule();
    _disableSlidingMontantReinforcementForPvc();
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
    const double pHeight = 0.0;

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

    List<double> normalizeGridCoordinates(
      Iterable<double> rawCoordinates,
      double minValue,
      double maxValue,
    ) {
      const tolerance = 2.0;
      final values = <double>[minValue, maxValue];
      values.addAll(
        rawCoordinates.map((value) => value.clamp(minValue, maxValue)),
      );
      values.sort();

      final normalized = <double>[];
      for (final value in values) {
        if (normalized.isEmpty) {
          normalized.add(value);
          continue;
        }

        final last = normalized.last;
        if ((value - last).abs() <= tolerance) {
          if ((last - minValue).abs() <= tolerance ||
              (value - minValue).abs() <= tolerance) {
            normalized[normalized.length - 1] = minValue;
          } else if ((last - maxValue).abs() <= tolerance ||
              (value - maxValue).abs() <= tolerance) {
            normalized[normalized.length - 1] = maxValue;
          } else {
            normalized[normalized.length - 1] = (last + value) / 2.0;
          }
        } else {
          normalized.add(value);
        }
      }
      return normalized;
    }

    // Collect and sort unique X coordinates
    final List<double> xCoords = normalizeGridCoordinates(
      zones.expand((z) => [z.boundary.left, z.boundary.right]),
      oldInnerLeft,
      oldInnerRight,
    );

    // Collect and sort unique Y coordinates
    final List<double> yCoords = normalizeGridCoordinates(
      zones.expand((z) => [z.boundary.top, z.boundary.bottom]),
      oldInnerTop,
      oldInnerBottom,
    );

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
    newW = _limitFrameDimension(newW);
    newH = _limitFrameDimension(newH);
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
    if (snap.mullionCreationOrder != null) {
      mullionCreationOrder = Map.from(snap.mullionCreationOrder!);
      mullionStepCounter = snap.mullionStepCounter ?? 0;
    }

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
        (canvasDx != 0 || canvasDy != 0)) {
      return;
    }

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

  String _frameSelectionKey(int index) => 'frame:$index';

  int? _frameIndexFromSelectionKey(String? key) {
    if (key == null || !key.startsWith('frame:')) return null;
    final index = int.tryParse(key.substring('frame:'.length));
    final frameCount = getFrameRects().length;
    if (index == null || index < 0 || index >= frameCount) return null;
    return index;
  }

  Rect? frameRectForSelection(String? key) {
    final index = _frameIndexFromSelectionKey(key);
    if (index == null) return null;
    final rects = getFrameRects();
    return index < rects.length ? rects[index] : null;
  }

  int? _frameIndexContainingZone(String zoneId) {
    final groups = _frameZoneGroups();
    for (var index = 0; index < groups.length; index++) {
      if (groups[index].any((zone) => zone.id == zoneId)) {
        return index;
      }
    }
    return null;
  }

  Rect? frameRectForZone(String zoneId) {
    final index = _frameIndexContainingZone(zoneId);
    if (index == null) return null;
    final rects = getFrameRects();
    return index < rects.length ? rects[index] : null;
  }

  void resizeFrameOuterDimensionForZone(
    String zoneId, {
    required bool isWidth,
    required double outerSize,
  }) {
    final index = _frameIndexContainingZone(zoneId);
    if (index == null) return;
    final rects = getFrameRects();
    if (index >= rects.length) return;
    final current = rects[index];
    final clampedSize = outerSize.clamp(200.0, maximumFrameBarLengthMm);
    final delta = clampedSize - (isWidth ? current.width : current.height);
    if (delta.abs() < 0.001) return;
    resizeFrameFromHandles(
      _frameSelectionKey(index),
      moveLeft: false,
      moveRight: isWidth,
      moveTop: false,
      moveBottom: !isWidth,
      deltaX: isWidth ? delta : 0.0,
      deltaY: isWidth ? 0.0 : delta,
    );
  }

  /// Selects one physical outer frame in a coupled drawing. A divided single
  /// frame remains one selectable frame; its inner zones do not expose resize
  /// handles independently.
  void selectFrameByIndex(int index) {
    final frameCount = getFrameRects().length;
    if (index < 0 || index >= frameCount) return;
    selection = SelectionInfo(
      type: SelectionType.frame,
      zoneId: _frameSelectionKey(index),
    );
    showZoneMenu = false;
    activeSubZone = null;
    notifyListeners();
  }

  void selectFrame(String zoneId) {
    if (zoneId.startsWith('frame:')) {
      final index = _frameIndexFromSelectionKey(zoneId);
      if (index == null) return;
      selectFrameByIndex(index);
      return;
    }

    final groups = _frameZoneGroups();
    for (var index = 0; index < groups.length; index++) {
      if (groups[index].any((zone) => zone.id == zoneId)) {
        selectFrameByIndex(index);
        return;
      }
    }
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
      if (getFrameRects().isNotEmpty) {
        selectFrameByIndex(0);
      } else {
        selection = SelectionInfo(type: SelectionType.frame);
        showZoneMenu = false;
        activeSubZone = null;
        notifyListeners();
      }
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
          String getVKey(int r, int v) => isRight ? 'right_${r}_$v' : '${r}_$v';
          String getHKey(int c, int h) => isRight ? 'right_${c}_$h' : '${c}_$h';

          for (int i = 0; i < finalHPos.length; i++) {
            double y = glassR.top + glassR.height * finalHPos[i];
            if ((pos.dy - y).abs() >= hitThreshold) continue;
            for (int c = 0; c < finalVPos.length + 1; c++) {
              if (z.disabledHorizontalDivisions[getHKey(c, i)] == true) {
                continue;
              }
              final leftRatio = c == 0 ? 0.0 : finalVPos[c - 1];
              final rightRatio = c == finalVPos.length ? 1.0 : finalVPos[c];
              final left = glassR.left + glassR.width * leftRatio;
              final right = glassR.left + glassR.width * rightRatio;
              if (pos.dx < left - 10 || pos.dx > right + 10) continue;
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
            if ((pos.dx - x).abs() >= hitThreshold) continue;
            for (int r = 0; r < finalHPos.length + 1; r++) {
              if (z.disabledVerticalDivisions[getVKey(r, i)] == true) {
                continue;
              }
              final topRatio = r == 0 ? 0.0 : finalHPos[r - 1];
              final bottomRatio = r == finalHPos.length ? 1.0 : finalHPos[r];
              final top = glassR.top + glassR.height * topRatio;
              final bottom = glassR.top + glassR.height * bottomRatio;
              if (pos.dy < top - 10 || pos.dy > bottom + 10) continue;
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
            final series = activeSlidingSeries;
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
      if (newPos - sep < minAllowedY) newPos = minAllowedY + sep;
      if (newPos + sep > maxAllowedY) newPos = maxAllowedY - sep;
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
      if (newPos - sep < minAllowedX) newPos = minAllowedX + sep;
      if (newPos + sep > maxAllowedX) newPos = maxAllowedX - sep;
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
      mullionStart: selection.mullionStart,
      mullionEnd: selection.mullionEnd,
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
    // The last glazing choice in the current order becomes the default for
    // the next drawing added to that order, including a cell-level choice.
    WindowZone.globalDefaultGlass = spec;
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
          final previousContent = zone.content;
          zone.content = ZoneContent.fixedGlass;
          if (previousContent != ZoneContent.fixedGlass) {
            _restoreBottomFrameForContent(zone);
          }
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
        final previousContent = z.content;
        z.content = ZoneContent.fixedGlass;
        if (previousContent != ZoneContent.fixedGlass) {
          _restoreBottomFrameForContent(z);
        }
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

  /// Applies a bulk glazing choice through the same model path used by the
  /// drawing screen, including automatic parclose and spacer compatibility.
  Future<void> applyGlassSpecificationToAllZones(
    GlassSpecification spec,
  ) async {
    paintAllZonesSpec(spec);
    for (final zone in List<WindowZone>.from(zones)) {
      zone.glass = await fitGlazingByRules(
        zone.glass,
        sliding: zone.content == ZoneContent.slidingSash,
      );
      for (final key in zone.cellGlassSpec.keys.toList()) {
        zone.cellGlassSpec[key] = await fitGlazingByRules(
          zone.cellGlassSpec[key]!,
          sliding: zone.content == ZoneContent.slidingSash,
        );
      }
    }
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
      final resolvedColor =
          color ??
          (structure == GlassStructure.closed || finish == GlassFinish.stopSol
              ? zone.glass.colorOuter
              : GlassColor.transparent);

      zone.glass = zone.glass.copyWith(
        structure: structure,
        finishOuter: finish,
        finishInner: finish,
        colorP: colorP ?? zone.glass.colorP,
        colorOuter: resolvedColor,
        colorInner: resolvedColor,
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
          final previousContent = zone.content;
          zone.content = ZoneContent.fixedGlass;
          if (previousContent != ZoneContent.fixedGlass) {
            _restoreBottomFrameForContent(zone);
          }
        }
      }
      notifyListeners();
    } catch (_) {}
  }

  GlassColor _resolveGlassColorAfterEdit({
    required GlassStructure targetStructure,
    required GlassFinish targetFinish,
    required GlassColor currentColor,
    required GlassStructure? requestedStructure,
    required GlassFinish? requestedFinish,
    required GlassColor? requestedColor,
  }) {
    if (requestedColor != null) return requestedColor;
    if (targetStructure == GlassStructure.closed) return currentColor;
    if (requestedFinish != null && requestedFinish != GlassFinish.stopSol) {
      return GlassColor.transparent;
    }
    if (requestedStructure != null && targetFinish != GlassFinish.stopSol) {
      return GlassColor.transparent;
    }
    return currentColor;
  }

  /// Fixed, empty and sliding content all require a real lower frame. Older
  /// drawings can arrive here after the lower frame was removed for a
  /// sash/plinthe, so changing only the zone content leaves the new content
  /// at the old open-bottom height. Restore the structural state as one
  /// atomic transition.
  ///
  /// In a multi-frame drawing this is kept local to the physical frame that
  /// owns [zone].  In a single-frame drawing the lower-frame/plinthe state is
  /// global by design and all opening plinth flags are cleared together.
  void _restoreBottomFrameForContent(WindowZone zone) {
    final frames = getFrameRects();
    Rect? owner;
    for (final frame in frames) {
      if (frame.contains(zone.boundary.center)) {
        owner = frame;
        break;
      }
    }

    if (frames.length > 1 && owner != null) {
      // The local override is attached to every zone in this physical frame
      // so a later resize or serialisation cannot partially restore it.
      for (final candidate in zones) {
        if (owner.contains(candidate.boundary.center)) {
          componentOverrides['frame-bottom:${candidate.id}'] = true;
          candidate.hasSashPlintheBottom = false;
        }
      }
    } else {
      hasBottomFrame = true;
      hasFramePlintheBottom = false;
      for (final candidate in zones) {
        candidate.hasSashPlintheBottom = false;
        componentOverrides.remove('frame-bottom:${candidate.id}');
      }
    }

    showBottomWall = true;
    // These two sets may contain stale entries created when the lower frame
    // was absent.  Returning to a fixed pane must behave like restoring the
    // original drawing, including its bottom cover and 45-degree corners.
    _restoreBottomSideCoverWhenFrameReturns();
    updateBottomZoneBoundaries();
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
      final previousContent = zone.content;
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

      // Fixed, empty and sliding content all sit on a real lower frame.
      // Discard the old local hide flag so the frame corners and bottom cover
      // return together when the drawing leaves an open-bottom state.
      if ((content == ZoneContent.fixedGlass ||
              content == ZoneContent.empty ||
              content == ZoneContent.slidingSash) &&
          previousContent != content) {
        _restoreBottomFrameForContent(zone);
      }

      if (slidingSashesCount != null) {
        zone.slidingSashesCount = slidingSashesCount;
      }
      if (content == ZoneContent.slidingSash) {
        zone.cutSlidingGlassRebate =
            cutSlidingGlassRebate ?? zone.cutSlidingGlassRebate;
        _activateSlidingProfilesForDrawing();
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
        zone.doubleSashHasTwoHandles = false;
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

  double? _clampInnerDivisionRatio({
    required WindowZone zone,
    required bool isRightSash,
    required bool isHorizontal,
    required int index,
    required double ratio,
    required List<double> positions,
  }) {
    if (index < 0 || index >= positions.length) return null;

    final sashT =
        zone.sashThickness ??
        getSectionThickness('sash', fallback: profileThickness);
    Rect sashR = zone.boundary;
    if (zone.content == ZoneContent.doubleSash) {
      const sep = 4.0;
      final midX =
          zone.boundary.left + zone.boundary.width * zone.doubleSashRatio;
      sashR = isRightSash
          ? Rect.fromLTRB(
              midX + sep / 2,
              zone.boundary.top,
              zone.boundary.right,
              zone.boundary.bottom,
            )
          : Rect.fromLTRB(
              zone.boundary.left,
              zone.boundary.top,
              midX - sep / 2,
              zone.boundary.bottom,
            );
    }

    final glassR = getSafeGlassRect(sashR, sashT);
    final physicalSize = isHorizontal ? glassR.height : glassR.width;
    // Keep numeric editing and pointer dragging on the same 100 mm rule.
    final minRatio = (100.0 / math.max(1.0, physicalSize))
        .clamp(0.02, 0.45)
        .toDouble();
    final minVal = index == 0 ? minRatio : positions[index - 1] + minRatio;
    final maxVal = index == positions.length - 1
        ? 1.0 - minRatio
        : positions[index + 1] - minRatio;
    if (minVal > maxVal) return null;
    return ratio.clamp(minVal, maxVal).toDouble();
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
        final nextRatio = _clampInnerDivisionRatio(
          zone: zone,
          isRightSash: true,
          isHorizontal: true,
          index: index,
          ratio: ratio,
          positions: mutable,
        );
        if (nextRatio == null) return;
        mutable[index] = nextRatio;
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
        final nextRatio = _clampInnerDivisionRatio(
          zone: zone,
          isRightSash: false,
          isHorizontal: true,
          index: index,
          ratio: ratio,
          positions: mutable,
        );
        if (nextRatio == null) return;
        mutable[index] = nextRatio;
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
        final nextRatio = _clampInnerDivisionRatio(
          zone: zone,
          isRightSash: true,
          isHorizontal: false,
          index: index,
          ratio: ratio,
          positions: mutable,
        );
        if (nextRatio == null) return;
        mutable[index] = nextRatio;
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
        final nextRatio = _clampInnerDivisionRatio(
          zone: zone,
          isRightSash: false,
          isHorizontal: false,
          index: index,
          ratio: ratio,
          positions: mutable,
        );
        if (nextRatio == null) return;
        mutable[index] = nextRatio;
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
    if (isShutterOnly) {
      newW = newW.clamp(200.0, maximumShutterBarLengthMm).toDouble();
      // The blade rule is about width only; shutter height remains independent.
      newH = newH.clamp(100.0, 10000.0).toDouble();
    } else {
      newW = _limitFrameDimension(newW);
      newH = _limitFrameDimension(newH);
    }
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
    if (isWidth) {
      final bool isRightmost = !zones.any((z) => z.boundary.left > r.right - 2);
      if (isRightmost) {
        double oldX = r.left;
        double sep = mullionThickness / 2;
        for (var n in zones) {
          if (n.boundary.right <= oldX + 1 &&
              (oldX - n.boundary.right) <= divisionThickness + 4 &&
              math.max(r.top, n.boundary.top) <
                  math.min(r.bottom, n.boundary.bottom) - 2) {
            sep = (oldX - n.boundary.right) / 2;
            break;
          }
        }
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
        double sep = mullionThickness / 2;
        for (var n in zones) {
          if (n.boundary.left >= oldX - 1 &&
              (n.boundary.left - oldX) <= divisionThickness + 4 &&
              math.max(r.top, n.boundary.top) <
                  math.min(r.bottom, n.boundary.bottom) - 2) {
            sep = (n.boundary.left - oldX) / 2;
            break;
          }
        }
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
        double sep = mullionThickness / 2;
        for (var n in zones) {
          if (n.boundary.bottom <= oldY + 1 &&
              (oldY - n.boundary.bottom) <= divisionThickness + 4 &&
              math.max(r.left, n.boundary.left) <
                  math.min(r.right, n.boundary.right) - 2) {
            sep = (oldY - n.boundary.bottom) / 2;
            break;
          }
        }
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
        double sep = mullionThickness / 2;
        for (var n in zones) {
          if (n.boundary.top >= oldY - 1 &&
              (n.boundary.top - oldY) <= divisionThickness + 4 &&
              math.max(r.left, n.boundary.left) <
                  math.min(r.right, n.boundary.right) - 2) {
            sep = (n.boundary.top - oldY) / 2;
            break;
          }
        }
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
    newVal = math.min(newVal, maximumFrameBarLengthMm);
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

  /// Resizes the selected outer frame from the supplied handles. Physical
  /// neighbour frames that touch the moved side are translated with it so the
  /// drawing behaves like a snapped frame grid instead of leaving gaps.
  void resizeFrameFromHandles(
    String frameSelectionId, {
    required bool moveLeft,
    required bool moveRight,
    required bool moveTop,
    required bool moveBottom,
    required double deltaX,
    required double deltaY,
    bool saveHistory = true,
  }) {
    final frameIndex = _frameIndexFromSelectionKey(frameSelectionId);
    if (frameIndex != null) {
      _resizePhysicalFrameFromHandles(
        frameIndex,
        moveLeft: moveLeft,
        moveRight: moveRight,
        moveTop: moveTop,
        moveBottom: moveBottom,
        deltaX: deltaX,
        deltaY: deltaY,
        saveHistory: saveHistory,
      );
      return;
    }

    final zoneIndex = zones.indexWhere((zone) => zone.id == frameSelectionId);
    if (zoneIndex == -1) return;
    if (saveHistory) _saveSnapshot();
    final oldWidth = width;
    final oldHeight = height;

    const minInnerSize = 50.0;

    final current = zones[zoneIndex].boundary;
    double left = current.left;
    double top = current.top;
    double right = current.right;
    double bottom = current.bottom;
    final minLeft = profileThickness;
    final minTop = profileThickness;
    double clampDouble(double value, double minimum, double maximum) {
      if (maximum < minimum) return minimum;
      return value.clamp(minimum, maximum).toDouble();
    }

    if (moveLeft) {
      left = clampDouble(
        left + deltaX,
        math.max(minLeft, right - maximumFrameBarLengthMm),
        right - minInnerSize,
      );
    }
    if (moveRight) {
      right = clampDouble(
        right + deltaX,
        left + minInnerSize,
        left + maximumFrameBarLengthMm,
      );
    }
    if (moveTop) {
      top = clampDouble(
        top + deltaY,
        math.max(minTop, bottom - maximumFrameBarLengthMm),
        bottom - minInnerSize,
      );
    }
    if (moveBottom) {
      bottom = clampDouble(
        bottom + deltaY,
        top + minInnerSize,
        top + maximumFrameBarLengthMm,
      );
    }

    final next = Rect.fromLTRB(left, top, right, bottom);
    if ((next.left - current.left).abs() < 0.001 &&
        (next.top - current.top).abs() < 0.001 &&
        (next.right - current.right).abs() < 0.001 &&
        (next.bottom - current.bottom).abs() < 0.001) {
      return;
    }

    zones[zoneIndex].boundary = next;
    double nextWidth = 200.0;
    double nextHeight = 200.0;
    for (final zone in zones) {
      nextWidth = math.max(nextWidth, zone.boundary.right + profileThickness);
      nextHeight = math.max(
        nextHeight,
        zone.boundary.bottom + (hasBottomFrame ? profileThickness : 0.0),
      );
    }
    width = math.min(maximumFrameBarLengthMm, nextWidth);
    height = math.min(maximumFrameBarLengthMm, nextHeight);
    _resizeSideCoverSegments(oldWidth, oldHeight, width, height);
    notifyListeners();
  }

  /// Snaps a physical frame edge to the outside edge of the next touching
  /// frame when the dragged edge is within 100 mm. This lets an upper frame
  /// grow from one lower frame to two, three, or more frames without requiring
  /// millimetre-perfect dragging.
  double _snapPhysicalFrameEdge({
    required int frameIndex,
    required Rect current,
    required List<Rect> rects,
    required String side,
    required double proposed,
  }) {
    const threshold = 100.0;

    // Snapping is for extension toward a neighbouring frame. It must not
    // pull an edge back when the user is deliberately reducing its size.
    if ((side == 'right' && proposed <= current.right) ||
        (side == 'left' && proposed >= current.left) ||
        (side == 'bottom' && proposed <= current.bottom) ||
        (side == 'top' && proposed >= current.top)) {
      return proposed;
    }

    bool overlap(
      double firstStart,
      double firstEnd,
      double secondStart,
      double secondEnd,
    ) {
      return math.min(firstEnd, secondEnd) - math.max(firstStart, secondStart) >
          2.0;
    }

    bool nearPerpendicularEdge(Rect candidate) {
      if (side == 'left' || side == 'right') {
        return overlap(
              current.top,
              current.bottom,
              candidate.top,
              candidate.bottom,
            ) ||
            (candidate.top - current.bottom).abs() <= threshold ||
            (candidate.bottom - current.top).abs() <= threshold;
      }
      return overlap(
            current.left,
            current.right,
            candidate.left,
            candidate.right,
          ) ||
          (candidate.left - current.right).abs() <= threshold ||
          (candidate.right - current.left).abs() <= threshold;
    }

    double? best;
    var bestDistance = threshold + 0.001;
    for (var index = 0; index < rects.length; index++) {
      if (index == frameIndex) continue;
      final candidate = rects[index];
      if (!nearPerpendicularEdge(candidate)) continue;

      double? target;
      switch (side) {
        case 'right':
          if (candidate.right <= current.right + 2.0 ||
              candidate.left > proposed + threshold) {
            continue;
          }
          target = candidate.right;
          break;
        case 'left':
          if (candidate.left >= current.left - 2.0 ||
              candidate.right < proposed - threshold) {
            continue;
          }
          target = candidate.left;
          break;
        case 'bottom':
          if (candidate.bottom <= current.bottom + 2.0 ||
              candidate.top > proposed + threshold) {
            continue;
          }
          target = candidate.bottom;
          break;
        case 'top':
          if (candidate.top >= current.top - 2.0 ||
              candidate.bottom < proposed - threshold) {
            continue;
          }
          target = candidate.top;
          break;
      }
      if (target == null) continue;
      final distance = (target - proposed).abs();
      if (distance <= threshold && distance < bestDistance) {
        best = target;
        bestDistance = distance;
      }
    }
    return best ?? proposed;
  }

  void _resizePhysicalFrameFromHandles(
    int frameIndex, {
    required bool moveLeft,
    required bool moveRight,
    required bool moveTop,
    required bool moveBottom,
    required double deltaX,
    required double deltaY,
    bool saveHistory = true,
  }) {
    final groups = _frameZoneGroups();
    final rects = getFrameRects();
    if (frameIndex < 0 ||
        frameIndex >= groups.length ||
        frameIndex >= rects.length) {
      return;
    }
    final group = groups[frameIndex];
    if (group.isEmpty) return;
    if (saveHistory) _saveSnapshot();

    final oldWidth = width;
    final oldHeight = height;
    const minInnerSize = 50.0;

    final currentOuter = rects[frameIndex];
    double left = currentOuter.left;
    double top = currentOuter.top;
    double right = currentOuter.right;
    double bottom = currentOuter.bottom;

    double clampDouble(double value, double minimum, double maximum) {
      if (maximum < minimum) return minimum;
      return value.clamp(minimum, maximum).toDouble();
    }

    if (moveLeft) {
      left = clampDouble(
        left + deltaX,
        right - maximumFrameBarLengthMm,
        right - minInnerSize - (2 * profileThickness),
      );
    }
    if (moveRight) {
      right = clampDouble(
        right + deltaX,
        left + minInnerSize + (2 * profileThickness),
        left + maximumFrameBarLengthMm,
      );
    }
    if (moveTop) {
      top = clampDouble(
        top + deltaY,
        bottom - maximumFrameBarLengthMm,
        bottom - minInnerSize - (2 * profileThickness),
      );
    }
    if (moveBottom) {
      bottom = clampDouble(
        bottom + deltaY,
        top + minInnerSize + (2 * profileThickness),
        top + maximumFrameBarLengthMm,
      );
    }

    // Magnetic extension: when a frame edge approaches the next physical
    // frame, lock it to that frame's outside edge within 100 mm.
    if (moveRight) {
      right = _snapPhysicalFrameEdge(
        frameIndex: frameIndex,
        current: currentOuter,
        rects: rects,
        side: 'right',
        proposed: right,
      );
    }
    if (moveLeft) {
      left = _snapPhysicalFrameEdge(
        frameIndex: frameIndex,
        current: currentOuter,
        rects: rects,
        side: 'left',
        proposed: left,
      );
    }
    if (moveBottom) {
      bottom = _snapPhysicalFrameEdge(
        frameIndex: frameIndex,
        current: currentOuter,
        rects: rects,
        side: 'bottom',
        proposed: bottom,
      );
    }
    if (moveTop) {
      top = _snapPhysicalFrameEdge(
        frameIndex: frameIndex,
        current: currentOuter,
        rects: rects,
        side: 'top',
        proposed: top,
      );
    }

    bool overlapsRange(
      double firstStart,
      double firstEnd,
      double secondStart,
      double secondEnd,
    ) {
      return math.max(firstStart, secondStart) <
          math.min(firstEnd, secondEnd) - 2.0;
    }

    final nextOuter = Rect.fromLTRB(left, top, right, bottom);
    if ((nextOuter.left - currentOuter.left).abs() < 0.001 &&
        (nextOuter.top - currentOuter.top).abs() < 0.001 &&
        (nextOuter.right - currentOuter.right).abs() < 0.001 &&
        (nextOuter.bottom - currentOuter.bottom).abs() < 0.001) {
      return;
    }

    final currentInner = currentOuter.deflate(profileThickness);
    final nextInner = nextOuter.deflate(profileThickness);
    final scaleX = currentInner.width.abs() < 0.001
        ? 1.0
        : nextInner.width / currentInner.width;
    final scaleY = currentInner.height.abs() < 0.001
        ? 1.0
        : nextInner.height / currentInner.height;

    for (final zone in group) {
      final r = zone.boundary;
      zone.boundary = Rect.fromLTRB(
        nextInner.left + (r.left - currentInner.left) * scaleX,
        nextInner.top + (r.top - currentInner.top) * scaleY,
        nextInner.left + (r.right - currentInner.left) * scaleX,
        nextInner.top + (r.bottom - currentInner.top) * scaleY,
      );
    }

    Set<int> affectedFrameChain({
      required String side,
      required Rect movedRect,
    }) {
      const touchTolerance = 3.0;
      final affected = <int>{};
      final queue = <int>[];

      bool touches(Rect source, Rect candidate) {
        switch (side) {
          case 'right':
            return (candidate.left - source.right).abs() <= touchTolerance &&
                overlapsRange(
                  movedRect.top,
                  movedRect.bottom,
                  candidate.top,
                  candidate.bottom,
                );
          case 'left':
            return (candidate.right - source.left).abs() <= touchTolerance &&
                overlapsRange(
                  movedRect.top,
                  movedRect.bottom,
                  candidate.top,
                  candidate.bottom,
                );
          case 'bottom':
            return (candidate.top - source.bottom).abs() <= touchTolerance &&
                overlapsRange(
                  movedRect.left,
                  movedRect.right,
                  candidate.left,
                  candidate.right,
                );
          case 'top':
            return (candidate.bottom - source.top).abs() <= touchTolerance &&
                overlapsRange(
                  movedRect.left,
                  movedRect.right,
                  candidate.left,
                  candidate.right,
                );
        }
        return false;
      }

      void enqueueTouching(Rect source) {
        for (var i = 0; i < rects.length; i++) {
          if (i == frameIndex || affected.contains(i)) continue;
          if (!touches(source, rects[i])) continue;
          affected.add(i);
          queue.add(i);
        }
      }

      enqueueTouching(currentOuter);
      while (queue.isNotEmpty) {
        final currentIndex = queue.removeAt(0);
        enqueueTouching(rects[currentIndex]);
      }
      return affected;
    }

    void translateFrameGroups(Set<int> frameIndices, double dx, double dy) {
      if (frameIndices.isEmpty || (dx == 0 && dy == 0)) return;
      for (final index in frameIndices) {
        if (index < 0 || index >= groups.length) continue;
        for (final zone in groups[index]) {
          zone.boundary = zone.boundary.shift(Offset(dx, dy));
        }
      }
    }

    final deltaLeft = nextOuter.left - currentOuter.left;
    final deltaRight = nextOuter.right - currentOuter.right;
    final deltaTop = nextOuter.top - currentOuter.top;
    final deltaBottom = nextOuter.bottom - currentOuter.bottom;

    if (moveLeft && deltaLeft.abs() > 0.001) {
      translateFrameGroups(
        affectedFrameChain(side: 'left', movedRect: currentOuter),
        deltaLeft,
        0.0,
      );
    }
    if (moveRight && deltaRight.abs() > 0.001) {
      translateFrameGroups(
        affectedFrameChain(side: 'right', movedRect: currentOuter),
        deltaRight,
        0.0,
      );
    }
    if (moveTop && deltaTop.abs() > 0.001) {
      translateFrameGroups(
        affectedFrameChain(side: 'top', movedRect: currentOuter),
        0.0,
        deltaTop,
      );
    }
    if (moveBottom && deltaBottom.abs() > 0.001) {
      translateFrameGroups(
        affectedFrameChain(side: 'bottom', movedRect: currentOuter),
        0.0,
        deltaBottom,
      );
    }

    double nextWidth = 200.0;
    double nextHeight = 200.0;
    for (final zone in zones) {
      nextWidth = math.max(nextWidth, zone.boundary.right + profileThickness);
      nextHeight = math.max(
        nextHeight,
        zone.boundary.bottom + (hasBottomFrame ? profileThickness : 0.0),
      );
    }
    width = math.min(maximumFrameBarLengthMm, nextWidth);
    height = math.min(maximumFrameBarLengthMm, nextHeight);
    _resizeSideCoverSegments(oldWidth, oldHeight, width, height);
    notifyListeners();
  }

  void _moveInternalBoundaryX(double oldX, double diff) {
    // Detect the actual boundary gap dynamically: it could be a single mullion
    // (mullionThickness) or coupled frames (divisionThickness).
    double sep = mullionThickness / 2;
    double divisionX = oldX;
    bool foundRight = false;

    // Check if oldX is the right edge of a left zone, find its right neighbor
    // to measure the exact gap.
    for (var z in zones) {
      if ((z.boundary.right - oldX).abs() < 2) {
        for (var n in zones) {
          if (n.boundary.left >= oldX - 1 &&
              (n.boundary.left - oldX) <= divisionThickness + 4 &&
              math.max(z.boundary.top, n.boundary.top) <
                  math.min(z.boundary.bottom, n.boundary.bottom) - 2) {
            final actualGap = n.boundary.left - z.boundary.right;
            sep = actualGap / 2;
            break;
          }
        }
        divisionX = oldX + sep;
        foundRight = true;
        break;
      }
    }

    // If not found, check if oldX is the left edge of a right zone, find its
    // left neighbor.
    if (!foundRight) {
      for (var z in zones) {
        if ((z.boundary.left - oldX).abs() < 2) {
          for (var n in zones) {
            if (n.boundary.right <= oldX + 1 &&
                (oldX - n.boundary.right) <= divisionThickness + 4 &&
                math.max(z.boundary.top, n.boundary.top) <
                    math.min(z.boundary.bottom, n.boundary.bottom) - 2) {
              final actualGap = z.boundary.left - n.boundary.right;
              sep = actualGap / 2;
              break;
            }
          }
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
    // Detect the actual boundary gap dynamically (see _moveInternalBoundaryX).
    double sep = mullionThickness / 2;
    double divisionY = oldY;
    bool foundBottom = false;

    // Check if oldY is the bottom edge of a top zone, find its bottom neighbor
    // to measure the exact gap.
    for (var z in zones) {
      if ((z.boundary.bottom - oldY).abs() < 2) {
        for (var n in zones) {
          if (n.boundary.top >= oldY - 1 &&
              (n.boundary.top - oldY) <= divisionThickness + 4 &&
              math.max(z.boundary.left, n.boundary.left) <
                  math.min(z.boundary.right, n.boundary.right) - 2) {
            final actualGap = n.boundary.top - z.boundary.bottom;
            sep = actualGap / 2;
            break;
          }
        }
        divisionY = oldY + sep;
        foundBottom = true;
        break;
      }
    }

    // If not found, check if oldY is the top edge of a bottom zone, find its
    // top neighbor.
    if (!foundBottom) {
      for (var z in zones) {
        if ((z.boundary.top - oldY).abs() < 2) {
          for (var n in zones) {
            if (n.boundary.bottom <= oldY + 1 &&
                (oldY - n.boundary.bottom) <= divisionThickness + 4 &&
                math.max(z.boundary.left, n.boundary.left) <
                    math.min(z.boundary.right, n.boundary.right) - 2) {
              final actualGap = z.boundary.top - n.boundary.bottom;
              sep = actualGap / 2;
              break;
            }
          }
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
      // لا توجد أي تقسيمات — إعادة التعيين لتبدأ النافذة من جديد
      primaryMullionAxis = null;
      mullionCreationOrder.clear();
      mullionStepCounter = 0;
    } else if (!hasHorizontalBoundaries) {
      primaryMullionAxis = 'v';
    } else if (!hasVerticalBoundaries) {
      primaryMullionAxis = 'h';
    } else {
      // 🟢 إذا وُجد كلاهما: الحفاظ التام على التقسيم الأول الذي بدأ به المستخدم وعدم تغييره
      primaryMullionAxis ??= 'v';
    }
  }

  void splitSelectedZoneHorizontal({
    int parts = 2,
    List<double>? customSizes,
    bool fromTop = true,
  }) {
    if (selectedZone == null) return;
    primaryMullionAxis ??= 'h'; // 🟢 يثبت أول تقسيم أفقي إذا كانت النافذة فارغة
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
          recordMullionCreation(true, splitY);
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
          recordMullionCreation(true, splitY1);
          recordMullionCreation(true, splitY2);
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
        if (i < parts - 1) {
          recordMullionCreation(true, bottom + mullionThickness / 2);
        }
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

  /// Applies a regular/custom division pattern inside sash glass without
  /// replacing the sash with new outer-frame zones.
  void configureSelectedSashDivisions({
    required bool horizontal,
    int parts = 2,
    List<double>? customSizes,
    bool fromStart = true,
    bool applyToAllSashes = false,
  }) {
    final selected = selectedZone;
    if (selected == null ||
        (selected.content != ZoneContent.singleSash &&
            selected.content != ZoneContent.doubleSash)) {
      return;
    }
    _saveSnapshot();

    final targets = <(WindowZone, bool, Rect)>[];
    void addZoneSashes(WindowZone zone, {bool allSides = true}) {
      if (zone.content == ZoneContent.singleSash) {
        targets.add((zone, false, zone.boundary));
        return;
      }
      if (zone.content != ZoneContent.doubleSash) return;
      final splitX =
          zone.boundary.left + zone.boundary.width * zone.doubleSashRatio;
      const gap = 4.0;
      final left = Rect.fromLTRB(
        zone.boundary.left,
        zone.boundary.top,
        splitX - gap / 2,
        zone.boundary.bottom,
      );
      final right = Rect.fromLTRB(
        splitX + gap / 2,
        zone.boundary.top,
        zone.boundary.right,
        zone.boundary.bottom,
      );
      if (allSides) {
        targets.add((zone, false, left));
        targets.add((zone, true, right));
      } else {
        final selectedRight = activeSubZone?.startsWith('right') == true;
        targets.add((zone, selectedRight, selectedRight ? right : left));
      }
    }

    if (applyToAllSashes) {
      for (final zone in zones) {
        addZoneSashes(zone);
      }
    } else {
      addZoneSashes(selected, allSides: false);
    }

    List<double> positionsFor(Rect sashRect, WindowZone zone) {
      final sashThickness =
          zone.sashThickness ??
          getSectionThickness('sash', fallback: profileThickness);
      final glass = getSafeGlassRect(sashRect, sashThickness);
      final extent = horizontal ? glass.height : glass.width;
      if (extent <= 0 || parts < 2) return const [];
      if (customSizes == null || customSizes.isEmpty) {
        return List.generate(parts - 1, (index) => (index + 1) / parts);
      }
      if (parts == 2) {
        final size = customSizes.first.clamp(0.0, extent);
        final ratio = fromStart ? size / extent : 1.0 - (size / extent);
        return [ratio.clamp(0.01, 0.99)];
      }
      if (parts == 3 && customSizes.length >= 2) {
        final first = (customSizes[0] / extent).clamp(0.01, 0.98);
        final second = (1.0 - customSizes[1] / extent).clamp(0.02, 0.99);
        if (second <= first) return const [];
        return [first, second];
      }
      return const [];
    }

    for (final target in targets) {
      final zone = target.$1;
      final isRight = target.$2;
      final positions = positionsFor(target.$3, zone);
      if (positions.isEmpty) continue;
      if (horizontal) {
        if (isRight) {
          zone.rightInnerHPositions = positions;
          zone.rightInnerH = positions.length;
          zone.rightPrimaryDivisionAxis ??= 'h';
          zone.disabledHorizontalDivisions = Map<String, bool>.from(
            zone.disabledHorizontalDivisions,
          )..removeWhere((key, _) => key.startsWith('right_'));
        } else {
          zone.innerHPositions = positions;
          zone.innerH = positions.length;
          zone.primaryDivisionAxis ??= 'h';
          zone.disabledHorizontalDivisions = Map<String, bool>.from(
            zone.disabledHorizontalDivisions,
          )..removeWhere((key, _) => !key.startsWith('right_'));
        }
      } else {
        if (isRight) {
          zone.rightInnerVPositions = positions;
          zone.rightInnerV = positions.length;
          zone.rightPrimaryDivisionAxis ??= 'v';
          zone.disabledVerticalDivisions = Map<String, bool>.from(
            zone.disabledVerticalDivisions,
          )..removeWhere((key, _) => key.startsWith('right_'));
        } else {
          zone.innerVPositions = positions;
          zone.innerV = positions.length;
          zone.primaryDivisionAxis ??= 'v';
          zone.disabledVerticalDivisions = Map<String, bool>.from(
            zone.disabledVerticalDivisions,
          )..removeWhere((key, _) => !key.startsWith('right_'));
        }
      }
    }
    selection = SelectionInfo(type: SelectionType.zone, zoneId: selected.id);
    showZoneMenu = false;
    notifyListeners();
  }

  void splitSelectedZoneVertical({
    int parts = 2,
    List<double>? customSizes,
    bool fromLeft = true,
  }) {
    if (selectedZone == null) return;
    primaryMullionAxis ??= 'v'; // 🟢 يثبت أول تقسيم رأسي إذا كانت النافذة فارغة
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
          recordMullionCreation(false, splitX);
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
          recordMullionCreation(false, splitX1);
          recordMullionCreation(false, splitX2);
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
        if (i < parts - 1) {
          recordMullionCreation(false, right + mullionThickness / 2);
        }
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

  bool get canDisableBottomFrame {
    if (usesSeuil) return true;
    if (systemMode == 'sliding') return false;
    return true;
  }

  bool usesFrameRole(String role, {required bool sliding}) {
    if (getConfiguredSectionForRole(role, useSlidingSeries: sliding) == null)
      return false;
    if (role == 'cache_rail') return sliding && useOptionalCacheRail;
    if (isConfiguredRoleRequired(role, useSlidingSeries: sliding)) return true;
    return role == 'seuil'
        ? useOptionalSeuil
        : role == 'cache_dormant'
        ? useOptionalCacheDormant
        // Cache-rainure is never a drawing option: assigning it to a series
        // means it is always installed at a compatible frame-to-frame joint.
        : role == 'cache_rainure'
        ? true
        : false;
  }

  bool hasFrameRole(String role) =>
      getConfiguredSectionForRole(role, useSlidingSeries: false) != null ||
      getConfiguredSectionForRole(role, useSlidingSeries: true) != null;

  bool supportsCaniveauForScope(bool sliding) =>
      getConfiguredSectionForRole('caniveau', useSlidingSeries: sliding) !=
          null &&
      getConfiguredSectionForRole(
            'cache_caniveau',
            useSlidingSeries: sliding,
          ) !=
          null;

  bool get hasCaniveauSupport =>
      supportsCaniveauForScope(false) || supportsCaniveauForScope(true);

  bool get hasBavetteSupport => hasFrameRole('bavette');

  bool get usesBavette => optionalBavetteMode > 0 && hasBavetteSupport;

  void setOptionalBavetteMode(int mode) {
    final next = mode.clamp(0, 2).toInt();
    if (next > 0 && !hasBavetteSupport) return;
    _saveSnapshot();
    optionalBavetteMode = next;
    notifyListeners();
  }

  bool frameRoleRequiredInAllScopes(String role) {
    final scopes = [false, true].where(
      (sliding) =>
          getConfiguredSectionForRole(role, useSlidingSeries: sliding) != null,
    );
    return scopes.isNotEmpty &&
        scopes.every(
          (sliding) =>
              isConfiguredRoleRequired(role, useSlidingSeries: sliding),
        );
  }

  bool frameRoleEnabledInAnyScope(String role) =>
      [false, true].any((sliding) => usesFrameRole(role, sliding: sliding));

  (int, int) cacheRailCountsForRect(Rect frame) {
    if (!usesFrameRole('cache_rail', sliding: true)) return (0, 0);
    final tracks = zones
        .where((zone) => frame.contains(zone.boundary.center))
        .fold<int>(1, (count, zone) => math.max(count, zone.slidingTrackCount));
    final maximum = math.max(0, tracks - 1);
    return (maximum, maximum);
  }

  bool frameUsesSlidingSeries(Rect frame) {
    final members = zones
        .where((zone) => frame.contains(zone.boundary.center))
        .toList();
    if (members.isEmpty) return usesSlidingPrimaryProfiles;

    final hasSlidingSash = members.any(
      (zone) => zone.content == ZoneContent.slidingSash,
    );
    final hasOpeningSash = members.any(
      (zone) =>
          zone.content == ZoneContent.singleSash ||
          zone.content == ZoneContent.doubleSash,
    );

    // Fixed-glass and empty cells do not turn a TPR sliding frame into an
    // opening frame.  Only an actual opening sash owns the opening series.
    return hasSlidingSash && !hasOpeningSash;
  }

  AluminumSection? frameSectionForRect(Rect frame) {
    final sliding = frameUsesSlidingSeries(frame);
    final selected = sliding ? slidingFrameOverride : activeFrameOverride;
    if (selected != null) return AluminumSection.fromMap(selected);
    return getConfiguredSectionForRole('frame', useSlidingSeries: sliding) ??
        (sliding ? getSlidingBaseFrameSection() : getSectionByType('frame'));
  }

  /// Visible workshop width of the exact frame selected for this rectangle.
  /// The painter must not reuse the generic profile thickness after a role
  /// rule has selected a different PVC frame.
  double frameVisibleWidthForRect(Rect frame, {double? fallback}) {
    final section = frameSectionForRect(frame);
    if (section != null) {
      final row = section.toMap();
      for (final key in const ['visible_width', 'thickness']) {
        final raw = row[key];
        final value = raw is num
            ? raw.toDouble()
            : double.tryParse(raw?.toString() ?? '');
        if (value != null && value > 0) return value;
      }
    }
    return fallback ?? profileThickness;
  }

  bool frameHasIntegratedSideCoverForRect(Rect frame) {
    final section = frameSectionForRect(frame);
    return section != null && _sectionHasIntegratedSideCover(section);
  }

  bool get selectedOuterFrameHasIntegratedSideCover {
    final frames = getFrameRects();
    final frame = frames.isEmpty
        ? Rect.fromLTWH(0, 0, width, height)
        : frames.first;
    return frameHasIntegratedSideCoverForRect(frame);
  }

  bool frameCanUseCacheRainure(Rect frame) {
    final section = frameSectionForRect(frame);
    return section != null && _sectionAllowsStandaloneSideCover(section);
  }

  /// Finds seams shared by two independent frames. A seam is eligible only
  /// when both frames accept a separate couvre-joint and either they belong
  /// to one series with Cache-rainure, or each touching series defines it.
  /// Each eligible seam receives one profile on the inside and one outside.
  List<FrameCacheRainureContact> getCacheRainureContacts() {
    const tolerance = 5.0;
    final frames = getFrameRects();
    final contacts = <FrameCacheRainureContact>[];

    for (var firstIndex = 0; firstIndex < frames.length; firstIndex++) {
      for (
        var secondIndex = firstIndex + 1;
        secondIndex < frames.length;
        secondIndex++
      ) {
        final first = frames[firstIndex];
        final second = frames[secondIndex];
        if (!frameCanUseCacheRainure(first) ||
            !frameCanUseCacheRainure(second)) {
          continue;
        }

        final firstSliding = frameUsesSlidingSeries(first);
        final secondSliding = frameUsesSlidingSeries(second);
        final firstSection = frameSectionForRect(first);
        final secondSection = frameSectionForRect(second);
        final sameSeries =
            firstSection != null &&
            secondSection != null &&
            firstSection.seriesId == secondSection.seriesId;
        final firstHasRole =
            getConfiguredSectionForRole(
              'cache_rainure',
              useSlidingSeries: firstSliding,
            ) !=
            null;
        final secondHasRole =
            getConfiguredSectionForRole(
              'cache_rainure',
              useSlidingSeries: secondSliding,
            ) !=
            null;
        // A role on only one of two different series is insufficient: it
        // would leave one face without a compatible Cache-rainure profile.
        if (!(sameSeries
            ? (firstHasRole || secondHasRole)
            : (firstHasRole && secondHasRole))) {
          continue;
        }
        final insideRoleSeries = firstHasRole ? firstSliding : secondSliding;
        final outsideRoleSeries = sameSeries ? insideRoleSeries : secondSliding;

        final vertical =
            (first.right - second.left).abs() <= tolerance ||
            (second.right - first.left).abs() <= tolerance;
        if (vertical) {
          final start = math.max(first.top, second.top);
          final end = math.min(first.bottom, second.bottom);
          if (end <= start + tolerance) continue;
          final coordinate = (first.right - second.left).abs() <= tolerance
              ? (first.right + second.left) / 2.0
              : (second.right + first.left) / 2.0;
          contacts.add(
            FrameCacheRainureContact(
              firstFrame: first,
              secondFrame: second,
              isVertical: true,
              coordinate: coordinate,
              start: start,
              end: end,
              insideUsesSlidingSeries: insideRoleSeries,
              outsideUsesSlidingSeries: outsideRoleSeries,
            ),
          );
          continue;
        }

        final horizontal =
            (first.bottom - second.top).abs() <= tolerance ||
            (second.bottom - first.top).abs() <= tolerance;
        if (!horizontal) continue;
        final start = math.max(first.left, second.left);
        final end = math.min(first.right, second.right);
        if (end <= start + tolerance) continue;
        final coordinate = (first.bottom - second.top).abs() <= tolerance
            ? (first.bottom + second.top) / 2.0
            : (second.bottom + first.top) / 2.0;
        contacts.add(
          FrameCacheRainureContact(
            firstFrame: first,
            secondFrame: second,
            isVertical: false,
            coordinate: coordinate,
            start: start,
            end: end,
            insideUsesSlidingSeries: insideRoleSeries,
            outsideUsesSlidingSeries: outsideRoleSeries,
          ),
        );
      }
    }
    return contacts;
  }

  bool get usesSeuil =>
      usesFrameRole('seuil', sliding: usesSlidingPrimaryProfiles);

  bool get usesCacheDormant =>
      useOptionalCacheDormant || isConfiguredRoleRequired('cache_dormant');

  bool get usesCacheRail =>
      useOptionalCacheRail &&
      getConfiguredSectionForRole('cache_rail', useSlidingSeries: true) != null;

  void toggleSeuil(bool value) {
    if (value && !hasFrameRole('seuil')) return;
    _saveSnapshot();
    useOptionalSeuil = value;
    if (value) {
      useOptionalCaniveau = false;
    } else {
      // C/Seuil physically replaces the lower frame member. Switching it
      // off must therefore restore that member, even when an older drawing
      // had its bottom frame disabled before C was selected.
      final wasBottomFrame = hasBottomFrame;
      hasBottomFrame = true;
      showBottomWall = true;
      if (!wasBottomFrame) _restoreBottomSideCoverWhenFrameReturns();
      updateBottomZoneBoundaries();
    }
    notifyListeners();
  }

  void toggleCacheDormant(bool value) {
    if (value && !hasFrameRole('cache_dormant')) return;
    _saveSnapshot();
    useOptionalCacheDormant = value;
    notifyListeners();
  }

  void setCacheRailCounts(int left, int right) {
    _saveSnapshot();
    cacheRailLeftCount = math.max(0, left);
    cacheRailRightCount = math.max(0, right);
    useOptionalCacheRail = cacheRailLeftCount > 0 || cacheRailRightCount > 0;
    notifyListeners();
  }

  void toggleCacheRail(bool value) {
    if (value &&
        getConfiguredSectionForRole('cache_rail', useSlidingSeries: true) ==
            null) {
      return;
    }
    _saveSnapshot();
    useOptionalCacheRail = value;
    notifyListeners();
  }

  bool get effectiveHasBottomFrame =>
      (hasBottomFrame && !usesSeuil) || !canDisableBottomFrame;

  /// Plinthe belongs to its opening frame, not neighbouring sliding frames.
  bool hasBottomFrameForRect(Rect frameRect) {
    final sliding = frameUsesSlidingSeries(frameRect);
    if (sliding) return true;
    if (usesFrameRole('seuil', sliding: sliding)) return false;
    for (final zone in zones) {
      if (!frameRect.contains(zone.boundary.center)) continue;
      final local = componentOverrides['frame-bottom:${zone.id}'];
      if (local is bool) return local;
    }
    return hasBottomFrame;
  }

  Rect? get selectedPhysicalFrameRect {
    final zone = selectedZone;
    if (zone == null) return null;
    for (final rect in getFrameRects()) {
      if (rect.contains(zone.boundary.center)) return rect;
    }
    return null;
  }

  bool get selectedFrameHasBottom {
    final rect = selectedPhysicalFrameRect;
    return rect == null ? effectiveHasBottomFrame : hasBottomFrameForRect(rect);
  }

  bool get canUseBottomSideCover {
    final frames = getFrameRects();
    if (frames.length > 1) return frames.any(hasBottomFrameForRect);
    return hasBottomFrame;
  }

  bool get canEditSelectedBottomFrame {
    if (!canDisableBottomFrame) return false;
    final frames = getFrameRects();
    final selected = selectedPhysicalFrameRect;
    if (frames.length > 1 && selected == null) return false;
    if (selected == null || frameUsesSlidingSeries(selected)) return false;
    final frameZones = zones.where((z) => selected.contains(z.boundary.center));
    if (frameZones.isNotEmpty &&
        frameZones.every(
          (z) =>
              z.content == ZoneContent.fixedGlass ||
              z.content == ZoneContent.empty,
        )) {
      return false;
    }
    return true;
  }

  bool usesCaniveauForRect(Rect frameRect) {
    if (!useOptionalCaniveau) return false;
    final sliding = frameUsesSlidingSeries(frameRect);
    // A caniveau always sits outside an existing lower frame. Seuil/C removes
    // that frame, so the two profiles can never be used together.
    return supportsCaniveauForScope(sliding) &&
        hasBottomFrameForRect(frameRect) &&
        !usesFrameRole('seuil', sliding: sliding);
  }

  bool get canEnableCaniveau =>
      getFrameRects().any(usesCaniveauForRect) ||
      (hasCaniveauSupport &&
          !frameRoleEnabledInAnyScope('seuil') &&
          (hasBottomFrame || systemMode == 'sliding'));

  void toggleCaniveau(bool value) {
    if (value && (!hasCaniveauSupport || frameRoleEnabledInAnyScope('seuil'))) {
      return;
    }
    _saveSnapshot();
    useOptionalCaniveau = value;
    notifyListeners();
  }

  void toggleOptionalTriangle(bool value) {
    _saveSnapshot();
    useOptionalTriangle = value;
    notifyListeners();
  }

  bool get hasOptionalTriangleLink => componentOverrides.values.any(
    (value) =>
        value is Map &&
        '${value['triangle_link_mode'] ?? ''}'.trim().toLowerCase() ==
            'optional',
  );

  bool _normalizeBottomFrameForCurrentContent() {
    if (canDisableBottomFrame && systemMode != 'sliding') return false;

    var changed = false;
    if (!hasBottomFrame) {
      hasBottomFrame = true;
      changed = true;
    }
    if (hasFramePlintheBottom) {
      hasFramePlintheBottom = false;
      changed = true;
    }
    for (final zone in zones) {
      if (zone.hasSashPlintheBottom) {
        zone.hasSashPlintheBottom = false;
        changed = true;
      }
    }
    if (!showBottomWall) {
      showBottomWall = true;
      changed = true;
    }
    return changed;
  }

  void enforceBottomFrameForCurrentContent({bool notify = false}) {
    final changed = _normalizeBottomFrameForCurrentContent();
    if (!changed) return;
    updateBottomZoneBoundaries();
    if (notify) notifyListeners();
  }

  void toggleViewMode() {
    isInternalView = !isInternalView;
    if (isInternalView) showInternalHardware = false;
    notifyListeners();
  }

  void setInternalHardwareVisibility(bool value) {
    if (showInternalHardware == value) return;
    showInternalHardware = value;
    notifyListeners();
  }

  void toggleBottomFrame(bool value) {
    final frames = getFrameRects();
    if (frames.length > 1) {
      final selected = selectedPhysicalFrameRect;
      if (selected == null ||
          frameUsesSlidingSeries(selected) ||
          !canDisableBottomFrame)
        return;
      _saveSnapshot();
      // Zone IDs survive resizing, serialization and undo. Keep this setting
      // on all members of the physical frame, without moving its boundaries
      // or changing the neighbouring frame's wall/cover state.
      for (final zone in zones) {
        if (selected.contains(zone.boundary.center)) {
          componentOverrides['frame-bottom:${zone.id}'] = value;
        }
      }
      notifyListeners();
      return;
    }
    componentOverrides.removeWhere(
      (key, value) => key.startsWith('frame-bottom:'),
    );
    if (!value && !canEditSelectedBottomFrame) return;
    if (systemMode == 'sliding' || (!value && !canDisableBottomFrame)) {
      final wasBottomFrame = hasBottomFrame;
      hasBottomFrame = true;
      if (!wasBottomFrame) _restoreBottomSideCoverWhenFrameReturns();
      hasFramePlintheBottom = false;
      for (var z in zones) {
        z.hasSashPlintheBottom = false;
      }
      showBottomWall = true;
      updateBottomZoneBoundaries();
      notifyListeners();
      return;
    }
    _saveSnapshot();
    final wasBottomFrame = hasBottomFrame;
    hasBottomFrame = value;
    if (hasBottomFrame && !wasBottomFrame) {
      _restoreBottomSideCoverWhenFrameReturns();
    }
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
    if (value && !canUseOpeningOnlyOptions) {
      useSystemOB = false;
      useDemiOB = false;
      useVerrouCentral = false;
      notifyListeners();
      return;
    }
    useSystemOB = value;
    if (value) {
      useDemiOB = false;
    } else {
      if (!effectiveUseDemiOB && useVerrouCentral) {
        useVerrouCentral = false;
      }
    }
    notifyListeners();
  }

  void toggleFramePlintheBottom(bool value) {
    bool isPlintheEligible(WindowZone zone) {
      return zone.content == ZoneContent.singleSash ||
          zone.content == ZoneContent.doubleSash ||
          zone.content == ZoneContent.fixedGlass;
    }

    final canUsePlinthe =
        hasOpeningSashZones ||
        zones.any((z) => z.content == ZoneContent.fixedGlass);
    if (value && !canUsePlinthe) {
      final wasBottomFrame = hasBottomFrame;
      hasFramePlintheBottom = false;
      for (final zone in zones) {
        zone.hasSashPlintheBottom = false;
      }
      hasBottomFrame = true;
      if (!wasBottomFrame) _restoreBottomSideCoverWhenFrameReturns();
      showBottomWall = true;
      updateBottomZoneBoundaries();
      notifyListeners();
      return;
    }
    final flagsMatch = zones.every(
      (zone) => zone.hasSashPlintheBottom == (value && isPlintheEligible(zone)),
    );
    final frameStateMatches = value ? !hasBottomFrame : hasBottomFrame;
    if (hasFramePlintheBottom == value && frameStateMatches && flagsMatch) {
      return;
    }
    _saveSnapshot();
    final wasBottomFrame = hasBottomFrame;

    if (value) {
      hasFramePlintheBottom = true;
      hasBottomFrame = false;
      showBottomWall = false;
      // The frame plinthe is a bottom profile for every opening/fixed zone.
      // Sliding zones use a different bottom-profile system and must not be
      // pulled into this opening-frame option.
      for (final z in zones) {
        z.hasSashPlintheBottom = isPlintheEligible(z);
      }
    } else {
      hasFramePlintheBottom = false;
      hasBottomFrame = true;
      if (!wasBottomFrame) _restoreBottomSideCoverWhenFrameReturns();
      showBottomWall = true;
      for (final z in zones) {
        z.hasSashPlintheBottom = false;
      }
    }

    _hideBottomCoverWhenBottomFrameIsMissing();
    updateBottomZoneBoundaries();
    notifyListeners();
  }

  void toggleSelectedZoneSashPlintheBottom() {
    final zone = selectedZone;
    if (zone == null) return;
    if (zone.content != ZoneContent.singleSash &&
        zone.content != ZoneContent.doubleSash) {
      return;
    }
    _saveSnapshot();

    zone.hasSashPlintheBottom = !zone.hasSashPlintheBottom;

    final anySashPlinthe = zones.any(
      (z) =>
          (z.content == ZoneContent.singleSash ||
              z.content == ZoneContent.doubleSash) &&
          z.hasSashPlintheBottom,
    );
    if (anySashPlinthe) {
      hasFramePlintheBottom = true;
      hasBottomFrame = false;
      showBottomWall = false;
    } else {
      final wasBottomFrame = hasBottomFrame;
      hasFramePlintheBottom = false;
      hasBottomFrame = true;
      if (!wasBottomFrame) _restoreBottomSideCoverWhenFrameReturns();
      showBottomWall = true;
      // Fixed-zone flags can only come from the global frame-plinthe mode.
      // Clear them when the last sash plinthe is disabled.
      for (final z in zones) {
        if (z.content != ZoneContent.singleSash &&
            z.content != ZoneContent.doubleSash) {
          z.hasSashPlintheBottom = false;
        }
      }
    }

    _hideBottomCoverWhenBottomFrameIsMissing();
    updateBottomZoneBoundaries();
    notifyListeners();
  }

  void updateBottomZoneBoundaries() {
    _normalizeBottomFrameForCurrentContent();

    for (var z in zones) {
      if (z.content == ZoneContent.slidingSash) {
        z.hasSashPlintheBottom = false;
        continue;
      }
      final hasPlintheBottom = !hasBottomFrame && z.hasSashPlintheBottom;
      final targetBottom = hasPlintheBottom
          ? height
          : height - profileThickness;
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
        if (z.content == ZoneContent.slidingSash) continue;
        if (z.openDirection == OpenDirection.top ||
            z.openDirection == OpenDirection.bottom) {
          z.openDirection = OpenDirection.left;
        }
      }
    }
  }

  bool canZoneHaveSash(WindowZone zone) {
    return true;
  }

  void toggleDemiOB(bool value) {
    useDemiOB = canUseDemiOB && value;
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
    if (value && !canUseOpeningOnlyOptions) {
      useVerrouCentral = false;
      notifyListeners();
      return;
    }
    useVerrouCentral = value;
    if (value) {
      if (!useSystemOB && !effectiveUseDemiOB) {
        useSystemOB = true;
      }
    }
    notifyListeners();
  }

  /// A regular box above an aluminium window requires a plain frame. A tunnel
  /// box is behind the wall and permits the frame's integrated side cover.
  Future<void> _selectNonIntegratedFrameForShutter() async {
    if (!hasShutter || isCaissonTunnel || isFramePVC) return;
    final series = activeFrameSeries;
    if (series == null) return;
    final revision = _sideCoverSelectionRevision;

    final currentFrame = activeFrameOverride;
    final hasIntegratedFrame = currentFrame != null
        ? _overrideHasIntegratedSideCover(currentFrame)
        : _currentFrameHasIntegratedSideCover;
    final currentAllowsSideCover = currentFrame != null
        ? _overrideAllowsStandaloneSideCover(currentFrame)
        : true;
    if (!hasIntegratedFrame && currentAllowsSideCover) {
      return;
    }

    if (_frameMapWasManuallySelected(currentFrame) &&
        !currentAllowsSideCover &&
        !hasIntegratedFrame) {
      hasSideCovers = false;
      useCustomSideCoverLayout = false;
      sideCoverSegments = [];
      hiddenSideCoverSegments.clear();
      notifyListeners();
      return;
    }

    final candidates = series.sections.where((section) {
      final type = section.type.toLowerCase();
      return (section.isFrame || type == 'frame' || type.contains('cadre')) &&
          _sectionAllowsStandaloneSideCover(section);
    }).toList();
    if (candidates.isEmpty) {
      hasSideCovers = false;
      useCustomSideCoverLayout = false;
      sideCoverSegments = [];
      hiddenSideCoverSegments.clear();
      notifyListeners();
      return;
    }

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

    // The user may have switched to Tunnel while the price was loading.
    if (!hasShutter ||
        isCaissonTunnel ||
        series != activeFrameSeries ||
        revision != _sideCoverSelectionRevision) {
      return;
    }
    applyFrameOverride(override, sliding: usesSlidingPrimaryProfiles);
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
      hasShutter = true;
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
    if (!isCaissonTunnel && hasShutter) {
      unawaited(_selectNonIntegratedFrameForShutter());
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
    final revision = ++_sideCoverSelectionRevision;
    final isMultiFrame = getFrameRects().length > 1;
    _saveSnapshot();
    _multiFrameSideCoverManuallyEnabled = isMultiFrame && value;
    hasSideCovers = value;
    if (value) {
      final covers = availableSideCovers;
      if (covers.isNotEmpty &&
          !covers.any((cover) => cover.id == selectedSideCover?.id)) {
        selectedSideCover = covers.first;
        sideCoverOverride = covers.first.toMap();
      } else if (selectedSideCover != null && sideCoverOverride == null) {
        sideCoverOverride = selectedSideCover!.toMap();
      }
    }
    // Draw the change immediately. Profile/price lookup stays asynchronous,
    // so a slow catalogue read cannot make the drawing page appear frozen.
    notifyListeners();

    await _selectFrameForSideCoverToggle(value, revision: revision);
  }

  Future<void> _selectFrameForSideCoverToggle(
    bool enabled, {
    required int revision,
  }) async {
    final series = activeFrameSeries;
    if (series == null) return;
    final sliding = usesSlidingPrimaryProfiles;
    final hadShutter = hasShutter;
    final hadTunnel = isCaissonTunnel;
    final multiFrame = getFrameRects().length > 1;
    final needsStandalone =
        multiFrame || (hasShutter && !isCaissonTunnel && !isFramePVC);
    final current = activeFrameOverride ?? getSectionByType('frame')?.toMap();
    final integrated = _overrideHasIntegratedSideCover(current);
    if (!enabled && !integrated) return;
    if (enabled && !needsStandalone && integrated && sideCoverWidth > 0) return;
    if (enabled &&
        needsStandalone &&
        current != null &&
        _overrideAllowsStandaloneSideCover(current)) {
      return;
    }

    bool stillCurrent() =>
        revision == _sideCoverSelectionRevision &&
        enabled == hasSideCovers &&
        series == activeFrameSeries &&
        sliding == usesSlidingPrimaryProfiles &&
        hadShutter == hasShutter &&
        hadTunnel == isCaissonTunnel &&
        multiFrame == (getFrameRects().length > 1);

    // A cover-button click may change the frame, but never invent a role or
    // select a profile that is hidden from the replacement dialog.
    final List<Map<String, dynamic>> rows;
    try {
      rows = await db.getDesignSectionsForScopedDialogRoles(
        series.id,
        const ['frame'],
        usageScope: sliding ? 'sliding' : 'opening',
        requireDialog: true,
        requireQuantity: true,
      );
    } catch (_) {
      return;
    }
    if (!stillCurrent()) return;
    final frames = rows.where((row) {
      final glassRule = '${row['design_show_when_glass'] ?? 'any'}'
          .trim()
          .toLowerCase();
      if ((glassRule == 'single' || glassRule == 'simple') &&
          !hasSimpleGlassForReducer) {
        return false;
      }
      if (glassRule == 'double' && !hasDoubleGlassForRules) return false;
      return true;
    }).toList();
    final plain = frames.where((row) => !_overrideHasIntegratedSideCover(row));
    final standalone = plain.where(_overrideAllowsStandaloneSideCover).toList();
    final integratedFrames = frames.where((row) {
      final width = _readPositiveDouble(row['couvre_joint_width']);
      return _overrideHasIntegratedSideCover(row) && width > 0;
    }).toList();
    final candidates = !enabled
        ? plain.toList()
        : needsStandalone
        ? standalone
        : integratedFrames.isNotEmpty
        ? integratedFrames
        : standalone;
    if (candidates.isEmpty) return;

    // Switching couvre-joint may require a compatible frame, but it must not
    // silently collapse a 4/5/6-rail sliding drawing back to the first
    // (usually two-rail) catalogue frame. Prefer an exact complete frame for
    // the rails already present; when none exists, keep the candidate base
    // and let Complément dormant supply the additional rails.
    final requestedTracks = sliding ? _requestedSlidingTrackCount() : 2;
    Map<String, dynamic>? completeMatchingTracks;
    for (final candidate in candidates) {
      final mode =
          (candidate['design_track_mode'] ?? candidate['track_mode'] ?? '')
              .toString()
              .trim()
              .toLowerCase();
      final rawCount =
          candidate['design_track_count'] ?? candidate['track_count'];
      final count = rawCount is num
          ? rawCount.toInt()
          : int.tryParse(rawCount?.toString() ?? '');
      if (mode == 'complete' && count == requestedTracks) {
        completeMatchingTracks = candidate;
        break;
      }
    }
    final target = Map<String, dynamic>.from(
      completeMatchingTracks ?? candidates.first,
    );
    target['manual_selection'] = true;
    // Preserve the requested switch state: applyFrameOverride's manual mode
    // is for clicking a profile, which intentionally disables plain covers.
    applyFrameOverride(target, sliding: sliding);
    useCustomSideCoverLayout = false;
    sideCoverSegments = [];
    hiddenSideCoverSegments.clear();
    notifyListeners();

    final colorId = selectedDbColor?['id'];
    if (colorId == null) return;
    try {
      final price = await db.getSectionPrice(target['id'], colorId);
      if (!stillCurrent() || selectedDbColor?['id'] != colorId) return;
      final selected = sliding ? slidingFrameOverride : frameOverride;
      if (selected?['id'] == target['id']) {
        selected!['calculated_price'] = price;
        notifyListeners();
      }
    } catch (_) {
      // Geometry is already updated; a temporarily unavailable price must
      // not undo the user's frame/cover choice.
    }
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
    final useSliding = systemMode == 'sliding' || usesSlidingPrimaryProfiles;
    final activeFrame = useSliding
        ? getSlidingBaseFrameSection()?.toMap()
        : frameOverride;
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
    if (side == 'bottom' && !hasBottomFrame) {
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

  /// Re-enable a bottom cover after the drawing returns from a plinthe/open
  /// bottom to a real bottom frame. The missing-frame constraint intentionally
  /// stores the old state as hidden; clear only that stale state on this
  /// transition, without changing a user's deliberate hide action while the
  /// frame is already present.
  void _restoreBottomSideCoverWhenFrameReturns() {
    if (!hasBottomFrame) return;
    removedShutterSides.remove('bottom');
    hiddenSideCoverSegments.remove('bottom');
  }

  /// Normalises the bottom cover after a drawing is restored or altered.
  /// A bottom cover requires both a bottom frame and a visible bottom wall.
  void enforceBottomSideCoverConstraint() {
    if (!canUseBottomSideCover) {
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
    selectedZone!.slidingSashesCount = count.clamp(2, 7).toInt();
    if (selectedZone!.slidingSashesCount != 4) {
      selectedZone!.slidingFaceToFace = false;
      selectedZone!.slidingCentralHandle = false;
      selectedZone!.slidingSecondCentralHandle = false;
    }
    notifyListeners();
  }

  void setSelectedZoneSlidingTracks(int count) {
    final zone = selectedZone;
    if (zone == null || zone.content != ZoneContent.slidingSash) return;
    _saveSnapshot();
    if (!supportedSlidingTrackCounts.contains(count)) return;
    zone.slidingTrackCount = count.clamp(2, 7).toInt();
    if (zone.slidingSashesCount < zone.slidingTrackCount) {
      zone.slidingSashesCount = zone.slidingTrackCount;
    }
    // A series may provide a ready-made 4/5/6-rail frame in addition to the
    // composable two-rail base. Select that exact complete frame as soon as
    // the user chooses its rail count. If it does not exist, keep the base
    // frame so the C-profile/Complément dormant calculation remains active.
    final series = effectiveSlidingSeries;
    if (series != null) {
      final frames = getConfiguredSectionsForRole(
        'frame',
        useSlidingSeries: true,
      );
      if (frames.isNotEmpty) {
        final selected = _preferredSlidingFrameForTrackCount(
          frames,
          series,
          zone.slidingTrackCount,
        );
        final selectedMap = _slidingFrameMapWithRoleOptions(selected, series);
        if (_catalogueId(slidingFrameOverride) != selected.id) {
          slidingFrameOverride = selectedMap;
        } else {
          // Keep role metadata fresh even when the physical section did not
          // change (old saved drawings lack these design fields).
          slidingFrameOverride = {
            ...slidingFrameOverride ?? const <String, dynamic>{},
            ...selectedMap,
          };
        }
      }
    }
    notifyListeners();
  }

  void setSelectedZoneSlidingSashes(int count, {bool? cutSlidingGlassRebate}) {
    if (hasArchOrSlant) return;
    final zone = selectedZone;
    if (zone == null) return;
    _saveSnapshot();
    zone.content = ZoneContent.slidingSash;
    if (!supportedSlidingSashCounts.contains(count) ||
        count < zone.slidingTrackCount) {
      return;
    }
    zone.slidingSashesCount = count.clamp(2, 7).toInt();
    if (zone.slidingSashesCount != 4) {
      zone.slidingFaceToFace = false;
      zone.slidingCentralHandle = false;
      zone.slidingSecondCentralHandle = false;
    }
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
    zone.cellIsPanel = {};
    activeSubZone = null;
    showZoneMenu = false;
    // A frame is drawn before the user chooses its contents, so only the
    // first explicit sliding choice can resolve the opening/sliding
    // ambiguity. Promote the selected profiles immediately so the canvas and
    // the BOM use the same sliding frame.
    _activateSlidingProfilesForDrawing();
    updateProfileThickness();
    notifyListeners();
  }

  void _activateSlidingProfilesForDrawing() {
    AluminumSeries? series = activeSlidingSeries;
    if (series == null && systemMode == 'sliding') {
      series = activeSeries;
    }
    if (series == null) {
      for (final profileSystem in availableSystems) {
        for (final candidate in profileSystem.series) {
          if (isSlidingSeriesForDrawing(candidate)) {
            series = candidate;
            break;
          }
        }
        if (series != null) break;
      }
    }
    if (series == null) return;
    activeSlidingSeries ??= series;

    final frames = getConfiguredSectionsForRole(
      'frame',
      useSlidingSeries: true,
    );
    final frame = frames.isNotEmpty
        ? _preferredSlidingFrameForTrackCount(
            frames,
            series,
            _requestedSlidingTrackCount(),
          )
        : getSlidingBaseFrameSection();
    if (frame != null &&
        (slidingFrameOverride == null ||
            getSlidingBaseFrameSection()?.id !=
                _catalogueId(slidingFrameOverride))) {
      slidingFrameOverride = _slidingFrameMapWithRoleOptions(frame, series);
    }

    if (slidingSashOverride == null) {
      final configured = getConfiguredSectionForRole(
        'sash',
        useSlidingSeries: true,
      );
      if (configured != null) {
        slidingSashOverride = configured.toMap();
      } else if (!_hasLoadedRoleMetadata(series)) {
        for (final section in series.sections) {
          final type = section.type.toLowerCase();
          if (section.isSash || type == 'sash' || type.contains('ouvrant')) {
            slidingSashOverride = section.toMap();
            break;
          }
        }
      }
    }
    updateAllSashThicknesses();
  }

  int? _catalogueId(Map<String, dynamic>? value) {
    final raw = value?['id'];
    return raw is num ? raw.toInt() : int.tryParse(raw?.toString() ?? '');
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

  /// Whether the active sliding series has explicitly assigned the
  /// Face-to-Face profile role.  A missing rule means the option does not
  /// exist; the painter and BOM must not guess a profile by its name.
  bool get supportsSlidingFaceToFace =>
      getConfiguredSectionForRole('face_to_face', useSlidingSeries: true) !=
      null;

  void setSelectedZoneSlidingFaceToFace(bool value) {
    final zone = selectedZone;
    if (zone == null || zone.content != ZoneContent.slidingSash) return;
    if (value &&
        (zone.slidingSashesCount != 4 || zone.slidingTrackCount != 2)) {
      return;
    }
    if (value && !supportsSlidingFaceToFace) return;
    if (zone.slidingFaceToFace == value) return;
    _saveSnapshot();
    zone.slidingFaceToFace = value;
    notifyListeners();
  }

  void toggleSelectedZoneSlidingFaceToFace() {
    final zone = selectedZone;
    if (zone == null) return;
    setSelectedZoneSlidingFaceToFace(!zone.slidingFaceToFace);
  }

  void setSelectedZoneSlidingCentralHandle(bool value) {
    final zone = selectedZone;
    if (zone == null || zone.content != ZoneContent.slidingSash) return;
    // The central handle described for the two-track layout is the meeting
    // handle of the middle pair.  It is not a valid option for two or three
    // leaves and is intentionally kept per zone.
    if (value &&
        (zone.slidingSashesCount != 4 || zone.slidingTrackCount != 2)) {
      return;
    }
    if (zone.slidingCentralHandle == value) return;
    _saveSnapshot();
    zone.slidingCentralHandle = value;
    notifyListeners();
  }

  void toggleSelectedZoneSlidingCentralHandle() {
    final zone = selectedZone;
    if (zone == null) return;
    setSelectedZoneSlidingCentralHandle(!zone.slidingCentralHandle);
  }

  /// Enables the second middle handle as a drawing/BOM handle only.  It is
  /// intentionally dependent on the first central handle: without the
  /// functional middle handle there is no valid pair to mirror.
  void setSelectedZoneSlidingSecondCentralHandle(bool value) {
    final zone = selectedZone;
    if (zone == null || zone.content != ZoneContent.slidingSash) return;
    if (value &&
        (zone.slidingSashesCount != 4 ||
            zone.slidingTrackCount != 2 ||
            !zone.slidingCentralHandle)) {
      return;
    }
    if (zone.slidingSecondCentralHandle == value) return;
    _saveSnapshot();
    zone.slidingSecondCentralHandle = value;
    notifyListeners();
  }

  void toggleSelectedZoneSlidingSecondCentralHandle() {
    final zone = selectedZone;
    if (zone == null) return;
    setSelectedZoneSlidingSecondCentralHandle(!zone.slidingSecondCentralHandle);
  }

  void toggleSelectedZoneOctoHandle() {
    if (selectedZone == null) return;
    _saveSnapshot();
    selectedZone!.useOctoHandle = !selectedZone!.useOctoHandle;
    notifyListeners();
  }

  void setSelectedZoneContent(ZoneContent content) {
    if (selectedZone == null) return;
    final zone = selectedZone!;
    // Keep one canonical transition path.  The drawing-screen menu used to
    // mutate this field directly, which skipped lower-frame restoration.
    paintZoneContent(zone.id, content);
    if (content == ZoneContent.doubleSash ||
        content == ZoneContent.singleSash ||
        content == ZoneContent.slidingSash) {
      zone.useClassicHandle = isPVC;
    } else {
      zone.doubleSashHasTwoHandles = false;
    }
    _clearOpeningOnlyOptionsIfUnavailable();
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
    final targetFinishOuter = finishOuter ?? baseSpec.finishOuter;
    final targetFinishInner = finishInner ?? baseSpec.finishInner;
    final resolvedColorOuter = _resolveGlassColorAfterEdit(
      targetStructure: targetStructure,
      targetFinish: targetFinishOuter,
      currentColor: baseSpec.colorOuter,
      requestedStructure: structure,
      requestedFinish: finishOuter,
      requestedColor: colorOuter,
    );
    final resolvedColorInner = _resolveGlassColorAfterEdit(
      targetStructure: targetStructure,
      targetFinish: targetFinishInner,
      currentColor: baseSpec.colorInner,
      requestedStructure: structure,
      requestedFinish: finishInner,
      requestedColor: colorInner,
    );
    double? resolvedThicknessOuter = thicknessOuter;
    double? resolvedThicknessInner = thicknessInner;
    final switchingToDouble =
        targetStructure == GlassStructure.double &&
        baseSpec.structure != GlassStructure.double;

    if (targetStructure == GlassStructure.double) {
      resolvedThicknessOuter ??=
          (switchingToDouble ? kDefaultGlassPaneThickness : null) ??
          baseSpec.thicknessOuter ??
          getThicknessForFinish(targetFinishOuter, resolvedColorOuter);
      resolvedThicknessInner ??=
          (switchingToDouble ? kDefaultGlassPaneThickness : null) ??
          baseSpec.thicknessInner ??
          getThicknessForFinish(targetFinishInner, resolvedColorInner);
    } else {
      resolvedThicknessOuter ??=
          baseSpec.thicknessOuter ??
          getThicknessForFinish(targetFinishOuter, resolvedColorOuter);
    }
    final effectiveThicknessOuter = resolvedThicknessOuter;
    final effectiveThicknessInner =
        resolvedThicknessInner ?? kDefaultGlassPaneThickness;

    // The pane selection controls the parclose and normally suggests an
    // Intercall. A spacer explicitly chosen by the user is preserved and is
    // shown with a compatibility warning in the drawing drawer.

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

    // Baguettes and rosettes exist only inside a double-glazing unit. Clear
    // their active drawing data as soon as this pane becomes simple or a
    // panel, so an old decoration can never remain in the cost table.
    final bool clearGlassDecor = targetStructure != GlassStructure.double;

    if (targetCellKey != null && targetCellKey.isNotEmpty) {
      final GlassSpecification updatedSpec = baseSpec.copyWith(
        structure: structure,
        finishOuter: finishOuter,
        finishInner: finishInner,
        colorOuter: resolvedColorOuter,
        colorInner: resolvedColorInner,
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
        thicknessOuter: effectiveThicknessOuter,
        thicknessInner: effectiveThicknessInner,
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
        colorOuter: resolvedColorOuter,
        colorInner: resolvedColorInner,
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
        thicknessOuter: effectiveThicknessOuter,
        thicknessInner: effectiveThicknessInner,
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
          final cellTargetStructure = structure ?? val.structure;
          final cellFinishOuter = finishOuter ?? val.finishOuter;
          final cellFinishInner = finishInner ?? val.finishInner;
          updatedCellGlass[key] = val.copyWith(
            structure: structure,
            finishOuter: finishOuter,
            finishInner: finishInner,
            colorOuter: _resolveGlassColorAfterEdit(
              targetStructure: cellTargetStructure,
              targetFinish: cellFinishOuter,
              currentColor: val.colorOuter,
              requestedStructure: structure,
              requestedFinish: finishOuter,
              requestedColor: colorOuter,
            ),
            colorInner: _resolveGlassColorAfterEdit(
              targetStructure: cellTargetStructure,
              targetFinish: cellFinishInner,
              currentColor: val.colorInner,
              requestedStructure: structure,
              requestedFinish: finishInner,
              requestedColor: colorInner,
            ),
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
            thicknessOuter: effectiveThicknessOuter,
            thicknessInner: effectiveThicknessInner,
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
    if (!hasSimpleGlassForReducer) {
      clearReducerOverride();
    }
    final requested = targetCellKey != null && targetCellKey.isNotEmpty
        ? zone.getGlassForCell(targetCellKey)
        : zone.glass;
    final fitted = await fitGlazingByRules(
      requested,
      sliding: zone.content == ZoneContent.slidingSash,
    );
    if (!zones.contains(zone)) return;
    if (targetCellKey != null && targetCellKey.isNotEmpty) {
      zone.cellGlassSpec = {...zone.cellGlassSpec, targetCellKey: fitted};
    } else {
      zone.glass = fitted;
      for (final key in zone.cellGlassSpec.keys.toList()) {
        zone.cellGlassSpec[key] = await fitGlazingByRules(
          zone.cellGlassSpec[key]!,
          sliding: zone.content == ZoneContent.slidingSash,
        );
      }
    }
    if (zones.any((candidate) => candidate.id == selectedZoneId)) {
      selection = SelectionInfo.zone(selectedZoneId);
      activeSubZone = targetCellKey;
    }
    notifyListeners();
  }

  String? glazingFitMessage;

  Future<GlassSpecification> fitGlazingByRules(
    GlassSpecification spec, {
    required bool sliding,
  }) async {
    if (spec.structure == GlassStructure.closed) return spec;
    final capacity = glazingCapacityForStructure(
      spec.structure,
      sliding: sliding,
    );
    if (capacity == null) {
      glazingFitMessage =
          'تعذر الحساب: سعة الزجاج غير محددة للباركلوز أو الضلفة.';
      return spec;
    }
    final pvc = sliding ? isSlidingPVC : isPVC;
    final series = sliding ? effectiveSlidingSeries : activeSeries;
    final resolver = CatalogCandidateResolver(database: db);
    Future<List<Map<String, dynamic>>> candidates(String role) =>
        resolver.resolve(
          CatalogCandidateQuery(
            category: 'joint',
            selectorType: role,
            roleKeys: [role],
            seriesId: series?.id,
            materialType: pvc ? 'pvc' : 'aluminium',
            drawingMode: sliding
                ? AccessoryDrawingMode.sliding
                : AccessoryDrawingMode.opening,
            requireDialog: false,
            requireQuantity: true,
            hasSimpleGlassForReducer: spec.structure == GlassStructure.simple,
            hasDoubleGlassForRules: spec.structure == GlassStructure.double,
          ),
        );
    final vitrage = pvc
        ? <Map<String, dynamic>>[]
        : await candidates('joint_vitrage');
    final bourrage = pvc
        ? <Map<String, dynamic>>[]
        : await candidates('joint_bourrage');
    final choices = <List<Map<String, dynamic>>>[];
    if (pvc) {
      choices.add([]);
    } else if (!spec.jointTwoSides) {
      choices.addAll((vitrage.isNotEmpty ? vitrage : bourrage).map((r) => [r]));
    } else {
      final firstSide = vitrage.isNotEmpty ? [vitrage.first] : bourrage;
      final secondSide = bourrage.isNotEmpty ? bourrage : vitrage;
      for (final first in firstSide) {
        for (final second in secondSide) {
          choices.add([first, second]);
        }
      }
    }
    final result = fitGlassPack(
      capacity: capacity,
      outer: spec.thicknessOuter ?? kDefaultGlassPaneThickness,
      inner: spec.thicknessInner ?? kDefaultGlassPaneThickness,
      spacer: spec.intercallThickness.toDouble(),
      doubleGlass: spec.structure == GlassStructure.double,
      jointChoices: choices,
      spacers: availableIntercalls
          .map((r) => _readPositiveDouble(r['thickness']))
          .where((v) => v > 0)
          .toList(),
      outerPanes: getAvailableThicknesses(spec.finishOuter, spec.colorOuter),
      innerPanes: getAvailableThicknesses(spec.finishInner, spec.colorInner),
    );
    if (result == null) {
      glazingFitMessage =
          'تركيب غير متوافق مع السعة $capacity مم. لا توجد تركيبة مسموحة من القواعد؛ النقص ممنوع والزيادة القصوى 1 مم.';
      return spec.copyWith(fittedJoints: const [], glazingFitValid: false);
    }
    glazingFitMessage =
        'الاختيار: ${spec.thicknessOuter ?? 5} / ${spec.intercallThickness} / ${spec.thicknessInner ?? 5} مم. '
        'التركيب المعتمد: ${result.outer}${spec.structure == GlassStructure.double ? ' + ${result.spacer} + ${result.inner}' : ''} مم؛ '
        '${result.joints.map((r) => '${r['name']} (${r['thickness']} مم)').join(' + ')}. '
        'المجموع ${result.total} مم / السعة $capacity مم. أولوية التعديل: الجوانات ثم الأنتركال ثم الزجاج.';
    return spec.copyWith(
      thicknessOuter: result.outer,
      thicknessInner: result.inner,
      intercallThickness: result.spacer.round(),
      fittedJoints: result.joints,
      glazingFitValid: true,
    );
  }

  Future<void> updateGlassGasket({bool recalculateIntercall = true}) async {
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
      maxGlass = _readPositiveDouble(parclose['max_glass_thickness']);
    } else if (activeSashMap != null) {
      maxGlass = _readPositiveDouble(activeSashMap['max_glass_thickness']);
    }

    if (maxGlass <= 0) {
      componentOverrides.remove('جوان الزجاج (Joint Vitrage)');
      notifyListeners();
      return;
    }

    if (zones.isEmpty) return;

    GlassSpecification? activeGlass;
    final zone = selectedZone;
    if (zone != null) {
      activeGlass = zone.getGlassForCell(activeSubZone);
    }
    activeGlass ??= zones
        .expand((z) => [z.glass, ...z.cellGlassSpec.values])
        .firstWhere(
          (glass) => glass.structure != GlassStructure.closed,
          orElse: () => const GlassSpecification(),
        );

    if (activeGlass.structure == GlassStructure.closed) {
      componentOverrides.remove('جوان الزجاج (Joint Vitrage)');
      notifyListeners();
      return;
    }

    final dbInstance = SqlDatabase();
    final rawJoints = await dbInstance.readJoints();
    final joints = rawJoints
        .map((row) => Map<String, dynamic>.from(row))
        .where((joint) => _readPositiveDouble(joint['thickness']) > 0)
        .toList();
    if (joints.isEmpty) {
      componentOverrides.remove('جوان الزجاج (Joint Vitrage)');
      notifyListeners();
      return;
    }

    bool isVitrageJoint(Map<String, dynamic> joint) {
      final text =
          '${joint['name'] ?? ''} ${joint['type'] ?? ''} ${joint['gasket_type'] ?? ''}'
              .toLowerCase();
      return text.contains('vitrage') ||
          text.contains('فيتراج') ||
          text.contains('زجاج') ||
          text.contains('glass');
    }

    bool isBourrageJoint(Map<String, dynamic> joint) {
      final text =
          '${joint['name'] ?? ''} ${joint['type'] ?? ''} ${joint['gasket_type'] ?? ''}'
              .toLowerCase();
      return text.contains('bourrage') ||
          text.contains('بوراج') ||
          text.contains('حشو');
    }

    final vitrageJoints = joints.where(isVitrageJoint).toList();
    final bourrageJoints = joints.where(isBourrageJoint).toList();
    final jointSides = activeGlass.jointTwoSides ? 2 : 1;
    final useSliding =
        systemMode == 'sliding' ||
        (selectedZone != null
            ? selectedZone!.content == ZoneContent.slidingSash
            : usesSlidingPrimaryProfiles);
    final activeSeriesForSash = useSliding ? activeSlidingSeries : activeSeries;
    final rawActiveSashId = activeSashMap?['id'];
    final activeSashId = rawActiveSashId is num
        ? rawActiveSashId.toInt()
        : int.tryParse(rawActiveSashId?.toString() ?? '');
    final linkedJoints = <Map<String, dynamic>>[];
    if (activeSeriesForSash != null && activeSashId != null) {
      final positions = activeGlass.jointTwoSides
          ? const ['sash_inner', 'sash_outer', 'sash_glass', 'all']
          : const ['sash_inner', 'sash_glass', 'all'];
      final linkedRows = await dbInstance.getDefaultJointsForSection(
        seriesId: activeSeriesForSash.id,
        sectionId: activeSashId,
        positionKeys: positions,
      );
      for (final row in linkedRows) {
        final joint = Map<String, dynamic>.from(row);
        if (_readPositiveDouble(joint['thickness']) <= 0) continue;
        if (!isVitrageJoint(joint)) continue;
        linkedJoints.add(joint);
      }
    }
    final candidateJoints = linkedJoints.isNotEmpty
        ? linkedJoints
        : (vitrageJoints.isNotEmpty ? vitrageJoints : joints);
    Map<String, dynamic>? bestJoint;
    Map<String, dynamic>? bestBourrageJoint;
    int? bestIntercall;
    var bestScore = double.infinity;

    if (activeGlass.structure == GlassStructure.double) {
      final paneThickness =
          _glassPaneThicknessOrDefault(activeGlass.thicknessOuter) +
          _glassPaneThicknessOrDefault(activeGlass.thicknessInner);
      final availableGap = maxGlass - paneThickness;
      if (availableGap <= 0) {
        componentOverrides.remove('جوان الزجاج (Joint Vitrage)');
        notifyListeners();
        return;
      }

      if (useSliding) {
        // Sliding uses the same glazing gasket on one or two sides.  Start
        // with the thinnest valid gasket, then fit the closest real spacer.
        for (final joint in candidateJoints) {
          final jointThickness = _readPositiveDouble(joint['thickness']);
          final intercallTarget = availableGap - (jointThickness * jointSides);
          final intercall = recalculateIntercall
              ? _nearestIntercallThickness(intercallTarget)
              : activeGlass.intercallThickness;
          if (intercall == null) continue;
          final exactness = (intercall.toDouble() - intercallTarget).abs();
          final score = exactness * 100 + jointThickness * 0.01;
          if (score < bestScore) {
            bestScore = score;
            bestJoint = joint;
            bestIntercall = intercall;
          }
        }
      } else {
        // Opening aluminium always has the fixed Vitrage gasket before the
        // glass and a Bourrage gasket after it.  Evaluate the spacer and the
        // Bourrage together; a compressible +1 mm fit is preferred to a
        // loose -1 mm fit.
        final selectedVitrage = selectedVitrageJointOverride();
        bestJoint = linkedJoints.isNotEmpty
            ? linkedJoints.first
            : (selectedVitrage ??
                  (vitrageJoints.isNotEmpty
                      ? (vitrageJoints.toList()..sort(
                              (a, b) => _readPositiveDouble(
                                a['thickness'],
                              ).compareTo(_readPositiveDouble(b['thickness'])),
                            ))
                            .first
                      : null));
        if (bestJoint != null) {
          final vitrageThickness = _readPositiveDouble(bestJoint['thickness']);
          final scopedBourrage = bourrageJoints
              .where(
                (joint) =>
                    _catalogRowMatchesSeriesScope(joint, activeSeriesForSash),
              )
              .toList();
          final candidates = scopedBourrage.isNotEmpty
              ? scopedBourrage
              : bourrageJoints;
          for (final bourrage in candidates) {
            final bourrageThickness = _readPositiveDouble(
              bourrage['thickness'],
            );
            if (bourrageThickness <= 0) continue;
            final intercallChoices = recalculateIntercall
                ? _availableIntercallThicknesses()
                : <int>[activeGlass.intercallThickness];
            for (final intercall in intercallChoices) {
              final fitted =
                  vitrageThickness + bourrageThickness + intercall.toDouble();
              final delta = fitted - availableGap;
              if (delta > 1.0) continue;
              // For equal fits prefer the smaller spacer and let the thicker
              // Bourrage absorb the compression (8 + 4 before 10 + 2).
              final tieBreak = intercall * 0.001 - bourrageThickness * 0.000001;
              final score = delta == 0
                  ? tieBreak
                  : delta > 0
                  ? delta.abs() * 10 + tieBreak
                  : delta.abs() * 10 + 5 + tieBreak;
              if (score < bestScore) {
                bestScore = score;
                bestBourrageJoint = bourrage;
                bestIntercall = intercall;
              }
            }
          }
        }
      }
      if (bestJoint == null || bestIntercall == null) {
        componentOverrides.remove('جوان الزجاج (Joint Vitrage)');
        notifyListeners();
        return;
      }

      final targetZone = selectedZone;
      if (recalculateIntercall && targetZone != null) {
        final targetCellKey = activeSubZone;
        if (targetCellKey != null && targetCellKey.isNotEmpty) {
          final current = targetZone.getGlassForCell(targetCellKey);
          targetZone.cellGlassSpec =
              Map<String, GlassSpecification>.from(targetZone.cellGlassSpec)
                ..[targetCellKey] = current.copyWith(
                  intercallThickness: bestIntercall,
                );
        } else {
          targetZone.glass = targetZone.glass.copyWith(
            intercallThickness: bestIntercall,
          );
        }
      }
    } else {
      final glassThickness = _glassPaneThicknessOrDefault(
        activeGlass.thicknessOuter,
      );
      final targetJointThickness = (maxGlass - glassThickness) / jointSides;
      if (targetJointThickness <= 0) {
        componentOverrides.remove('جوان الزجاج (Joint Vitrage)');
        notifyListeners();
        return;
      }
      for (final joint in candidateJoints) {
        final jointThickness = _readPositiveDouble(joint['thickness']);
        final diff = (jointThickness - targetJointThickness).abs();
        final score = diff * 100 + jointThickness * 0.01;
        if (diff <= 1.0 && score < bestScore) {
          bestScore = score;
          bestJoint = joint;
        }
      }
      if (bestJoint == null) {
        componentOverrides.remove('جوان الزجاج (Joint Vitrage)');
        notifyListeners();
        return;
      }
    }

    componentOverrides['جوان الزجاج (Joint Vitrage)'] =
        Map<String, dynamic>.from(bestJoint);
    if (!useSliding && bestBourrageJoint != null) {
      componentOverrides['جوان البوراج للزجاج المزدوج (Joint Bourrage Double)'] =
          Map<String, dynamic>.from(bestBourrageJoint);
    }
    _lastResolvedVitrageJointThickness = _readPositiveDouble(
      bestJoint['thickness'],
    );
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
    componentOverrides.remove('تراينغل الكريمون (Triangle)');
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

  Future<void> _loadJointRuleDefaults(dynamic d, int seriesId) async {
    final rules = await db.getCatalogItemRules(
      itemTable: 'Joints',
      seriesId: seriesId,
    );
    if (rules.isEmpty) return;

    final isSlidingSeriesContext =
        systemMode == 'sliding' ||
        (activeSlidingSeries?.id == seriesId && activeSeries?.id != seriesId);
    bool ruleScopeMatches(Map<String, dynamic> rule) {
      final scope = (rule['usage_scope'] ?? 'global')
          .toString()
          .trim()
          .toLowerCase();
      return scope.isEmpty ||
          scope == 'global' ||
          scope == 'auto' ||
          scope == 'both' ||
          scope == (isSlidingSeriesContext ? 'sliding' : 'opening');
    }

    Future<void> loadJoint(
      String overrideKey,
      String roleKey, {
      List<String> aliases = const [],
    }) async {
      if (componentOverrides.containsKey(overrideKey)) return;
      final acceptedRoles = {roleKey, ...aliases};
      final matchingRules = rules.where((rule) {
        if (rule['show_in_quantity'] == 0) return false;
        if (!ruleScopeMatches(rule)) return false;
        final currentRole = rule['role_key']?.toString().trim();
        return currentRole != null && acceptedRoles.contains(currentRole);
      });

      for (final rule in matchingRules) {
        final itemId = (rule['item_id'] as num?)?.toInt();
        if (itemId == null) continue;
        final rows = await d.query(
          'Joints',
          where: 'id = ? AND (is_active = 1 OR is_active IS NULL)',
          whereArgs: [itemId],
          limit: 1,
        );
        if (rows.isEmpty) continue;
        final selected = Map<String, dynamic>.from(rows.first);
        final rawPrice = selected['price_per_meter'] ?? selected['price'];
        selected['calculated_price'] = rawPrice is num
            ? rawPrice.toDouble()
            : double.tryParse(rawPrice?.toString() ?? '') ?? 0.0;
        componentOverrides[overrideKey] = selected;
        return;
      }
    }

    // These keys are the exact keys consumed by ComponentCalculator. Keeping
    // the mapping here makes the Joints rules page affect the quantity table
    // without coupling the catalogue UI to the calculation formulas.
    await loadJoint('جوان الزجاج (Joint Vitrage)', 'joint_vitrage');
    await loadJoint('جوان البوراج (Joint Bourrage)', 'joint_bourrage');
    await loadJoint(
      'جوان البوراج للزجاج المفرد (Joint Bourrage Simple)',
      'joint_bourrage',
    );
    await loadJoint(
      'جوان البوراج للزجاج المزدوج (Joint Bourrage Double)',
      'joint_bourrage',
    );
    await loadJoint('جوان الضرب (Joint Frappe)', 'joint_frappe');
    await loadJoint('N 245', 'joint_central');
    await loadJoint('جوان بروس للظلفة (Joint Brosse Sash)', 'joint_brosse');
    await loadJoint(
      'جوان بروس للستار (Joint Brosse Shutter)',
      'shutter_joint_brosse',
      aliases: const ['joint_brosse'],
    );
    await loadJoint('جوان برونز (Joint Bronze)', 'joint_bronze');
  }

  Future<void> _loadAccessoryDefaults(dynamic d, int seriesId) async {
    await _loadJointRuleDefaults(d, seriesId);
    final isSlidingSeriesContext =
        systemMode == 'sliding' ||
        (activeSlidingSeries?.id == seriesId && activeSeries?.id != seriesId);
    bool ruleScopeMatches(Map<String, dynamic> rule) {
      final scope = (rule['usage_scope'] ?? 'global')
          .toString()
          .trim()
          .toLowerCase();
      return scope.isEmpty ||
          scope == 'global' ||
          scope == 'auto' ||
          scope == 'both' ||
          scope == (isSlidingSeriesContext ? 'sliding' : 'opening');
    }

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

    String? ruleKeyForAccessoryDefault(String key) {
      final lower = key.toLowerCase();
      if (lower.contains('tringle') ||
          lower.contains('tangle') ||
          lower.contains('triangle') ||
          key.contains('تراينغل') ||
          key.contains('تريانغل')) {
        return 'tringle';
      }
      if (key == 'كريمون (Cremone)' ||
          lower.contains('cremone') ||
          lower.contains('crémone') ||
          key.contains('كريمون')) {
        return 'cremone';
      }
      if (key == 'الفيرو (Verrou)' ||
          (lower.contains('verrou') && !lower.contains('central')) ||
          key.contains('فيرو')) {
        return 'verrou';
      }
      if (key == 'كاش كوليسون (Gache coulissant)' ||
          key == 'Gâche coulissant TPR') {
        return 'sliding_lock';
      }
      if (key.contains('قاش دوبل')) return 'gache_double';
      if (key.contains('قاش بورت')) return 'gache_door';
      if (key.contains('قاش') || lower.contains('gache')) {
        return 'gache_simple';
      }
      if (lower.contains('espagnolette') ||
          key.contains('اسبانيول') ||
          key.contains('إسبانيول')) {
        return 'espagnolette';
      }
      if (lower.contains('poignée porte') || lower.contains('poignee porte')) {
        return lower.contains('condamnation')
            ? 'door_handle_condamnation'
            : 'door_handle_key';
      }
      if ((lower.contains('poignée') || lower.contains('poignee')) &&
          lower.contains('condamnation')) {
        return 'door_handle_condamnation';
      }
      if (lower.contains('condamnation')) return 'lock_condamnation';
      if (lower.contains('poignée') ||
          lower.contains('poignee') ||
          lower.contains('handle') ||
          key.contains('مقبض')) {
        return 'handle';
      }
      if (lower.contains('paumelle') || key.contains('مفاصل')) return 'hinge';
      if (lower.contains('canon') || key.contains('أسطوانة')) return 'canon';
      if (lower.contains('serrure') || key.contains('قفل')) return 'lock_clef';
      if (lower.contains('roulette') || key.contains('عجلات')) {
        return 'roulette';
      }
      if (lower.contains('tasso') || key.contains('الطاسو')) return 'tasso';
      if (lower.contains('ekar') ||
          lower.contains('ikar') ||
          key.contains('إيكار') ||
          key.contains('ايكار')) {
        return 'ekar';
      }
      if (lower.contains('entrematique') || key.contains('أونتروماتيك')) {
        return 'entrematique';
      }
      if ((lower.contains('40000') || key.contains('40000')) &&
          (lower.contains('kit') || key.contains('كيت'))) {
        return 'sliding_kit_40000';
      }
      if ((lower.contains('67000') || key.contains('67000')) &&
          (lower.contains('kit') || key.contains('كيت'))) {
        return 'sliding_kit_67000';
      }
      if (lower.contains('kit') || key.contains('كيت')) return 'sliding_kit';
      if (lower.contains('clam') || key.contains('كلام')) {
        return 'clam';
      }
      return null;
    }

    Future<void> loadAccessory(String key, List<String> searchPatterns) async {
      if (componentOverrides.containsKey(key)) return;

      Future<Map<String, dynamic>?> loadRelatedAccessory(dynamic rawId) async {
        final relatedId = rawId is num
            ? rawId.toInt()
            : int.tryParse(rawId?.toString() ?? '');
        if (relatedId == null) return null;
        try {
          final related = await d.query(
            'Accessories',
            where: '(is_active = 1 OR is_active IS NULL) AND id = ?',
            whereArgs: [relatedId],
            limit: 1,
          );
          return related.isEmpty
              ? null
              : Map<String, dynamic>.from(related.first);
        } catch (_) {
          return null;
        }
      }

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

      final ruleKey = ruleKeyForAccessoryDefault(key);
      if (ruleKey != null) {
        final ruleKeys = <String>[ruleKey];
        if (ruleKey == 'sliding_kit_40000' || ruleKey == 'sliding_kit_67000') {
          // Keep generic rules created before the series-specific roles.
          ruleKeys.add('sliding_kit');
        }
        final ruleRows = await db.getCatalogItemRules(
          itemTable: 'Accessories',
          seriesId: seriesId,
          roleKeys: ruleKeys,
          exactSeriesOnly: true,
        );
        final effectiveEspagnoletteHeight = effectiveEspagnoletteHeightMm;
        bool ruleMatchesEspagnoletteRange(Map<String, dynamic> rule) {
          if (ruleKey != 'espagnolette') return true;
          return catalogEspagnoletteRuleMatches(
            rule,
            effectiveHeightMm: effectiveEspagnoletteHeight,
          );
        }

        for (final rule in ruleRows) {
          if (rule['show_in_quantity'] == 0) continue;
          if (!ruleScopeMatches(rule)) continue;
          if (!ruleMatchesEspagnoletteRange(rule)) continue;
          final itemId = (rule['item_id'] as num?)?.toInt();
          if (itemId == null) continue;
          final rows = await d.query(
            'Accessories',
            where: 'id = ? AND (is_active = 1 OR is_active IS NULL)',
            whereArgs: [itemId],
            limit: 1,
          );
          if (rows.isEmpty) continue;
          if (!isAccessoryValid(rows.first)) continue;
          final selected = Map<String, dynamic>.from(rows.first);
          selected['calculated_price'] = await resolveAccessoryPrice(selected);
          final linkedGache = await loadRelatedAccessory(
            selected['linked_accessory_id'] ?? selected['gache_accessory_id'],
          );
          if (linkedGache != null) {
            selected['linked_accessory'] = linkedGache;
            selected['gache_accessory'] = linkedGache;
          }
          selected['linked_accessories'] = await db
              .readAccessoryLinksWithDetails(itemId);
          componentOverrides[key] = selected;
          return;
        }
        if (ruleKey == 'espagnolette' && ruleRows.isNotEmpty) return;
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
        tprArgs.addAll([seriesId, '%,$seriesId,%']);
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
        args.addAll([seriesId, '%,$seriesId,%']);

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
          fallbackArgs.addAll([seriesId, '%,$seriesId,%']);

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
        // The administrator's default is an explicit catalogue choice. It
        // wins over the old "first row" behaviour and over automatic length
        // guessing, so every drawing uses the value entered in Accessories.
        final defaults = res.where((accessory) {
          final value = accessory['is_default'];
          if (value is num) return value != 0;
          final text = value?.toString().trim().toLowerCase();
          return text == '1' ||
              text == 'true' ||
              text == 'yes' ||
              text == 'oui';
        }).toList();
        Map<String, dynamic> selected = Map<String, dynamic>.from(
          defaults.isNotEmpty ? defaults.first : res.first,
        );
        if (defaults.isEmpty &&
            (key == 'إسبانيوليت (Espagnolette)' ||
                key == 'اسبانيولات المنزلق (Espagnolette)')) {
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
        final linkedGache = await loadRelatedAccessory(
          m['linked_accessory_id'] ?? m['gache_accessory_id'],
        );
        if (linkedGache != null) {
          m['linked_accessory'] = linkedGache;
          m['gache_accessory'] = linkedGache;
        }
        final linkedScrew = await loadRelatedAccessory(m['screw_accessory_id']);
        if (linkedScrew != null) m['screw_accessory'] = linkedScrew;
        final selectedId = (m['id'] as num?)?.toInt();
        if (selectedId != null) {
          m['linked_accessories'] = await db.readAccessoryLinksWithDetails(
            selectedId,
          );
        }
        componentOverrides[key] = m;
      }
    }

    // Exact series rules are authoritative. Other roles can still use the
    // legacy catalogue fallback when this series has no explicit rules.
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
    await loadAccessory('تراينغل الكريمون (Triangle)', [
      '%tringle%',
      '%tangle%',
      '%triangle%',
      '%تراينغل%',
      '%تريانغل%',
    ]);
    await loadAccessory('بوشون بارك لوز (Bouchon Parclose)', [
      '%بوشون بارك لوز%',
      '%bouchon parclose%',
      '%بوشون باكيت%',
    ]);
    await loadAccessory('بوشون الكانيفو (Bouchon Caniveau)', [
      '%بوشون كانيفو%',
      '%بوشون الكانيفو%',
      '%bouchon caniveau%',
      '%cache caniveau bouchon%',
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
    await loadAccessory('كيت 40000 (Kit 40000)', [
      '%40000%kit%',
      '%40000%KIT%',
      '%kit%40000%',
      '%KIT%40000%',
      '%كيت%40000%',
      '%40000%كيت%',
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
    await loadAccessory('الطاسو (Tasso)', ['%طاسو%', '%tasso%']);
    await loadAccessory('الإيكار (Ekar)', [
      '%إيكار%',
      '%ايكار%',
      '%ekar%',
      '%ikar%',
    ]);
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
    Future<void> assignBrosseDefault(String key) async {
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
              '%,$seriesId,%',
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

    await assignBrosseDefault('جوان بروس للظلفة (Joint Brosse Sash)');
    await assignBrosseDefault('جوان بروس للستار (Joint Brosse Shutter)');

    // Dynamic Joint Bourrage matching based on closest real thickness in DB
    try {
      final rawBourrageRows = await d.query(
        'Joints',
        where: 'type LIKE ? OR name LIKE ? OR gasket_type LIKE ?',
        whereArgs: ['%bourrage%', '%bourrage%', '%bourrage%'],
      );
      if (rawBourrageRows.isNotEmpty) {
        final bourrageRows = rawBourrageRows.map((r) {
          final m = Map<String, dynamic>.from(r);
          m['calculated_price'] = (m['price_per_meter'] ?? 0.0).toDouble();
          return m;
        }).toList();

        Map<String, dynamic>? findClosest(double target) {
          if (bourrageRows.isEmpty) return null;
          Map<String, dynamic>? best;
          double minDiff = double.infinity;
          for (final row in bourrageRows) {
            double thick = _readPositiveDouble(row['thickness']);
            if (thick <= 0) {
              final code = (row['code'] ?? '').toString().trim();
              if (code.contains('52034'))
                thick = 2.0;
              else if (code.contains('52035'))
                thick = 4.0;
              else if (code.contains('52036'))
                thick = 6.0;
            }
            if (thick <= 0) continue;
            final diff = (thick - target).abs();
            if (diff < minDiff) {
              minDiff = diff;
              best = row;
            }
          }
          return best ?? bourrageRows.first;
        }

        final bestForDouble = findClosest(2.0);
        if (bestForDouble != null &&
            !componentOverrides.containsKey(
              'جوان البوراج للزجاج المزدوج (Joint Bourrage Double)',
            )) {
          componentOverrides['جوان البوراج للزجاج المزدوج (Joint Bourrage Double)'] =
              bestForDouble;
        }

        final bestForSimple = findClosest(4.0);
        if (bestForSimple != null &&
            !componentOverrides.containsKey(
              'جوان البوراج للزجاج المفرد (Joint Bourrage Simple)',
            )) {
          componentOverrides['جوان البوراج للزجاج المفرد (Joint Bourrage Simple)'] =
              bestForSimple;
        }

        final bestGeneral = findClosest(6.0);
        if (bestGeneral != null &&
            !componentOverrides.containsKey('جوان البوراج (Joint Bourrage)')) {
          componentOverrides['جوان البوراج (Joint Bourrage)'] = bestGeneral;
        }
      }
    } catch (_) {}
    await _enrichAccessoryRelations(d);
  }

  Future<void> _enrichAccessoryRelations(dynamic d) async {
    Future<Map<String, dynamic>?> findAccessory(dynamic rawId) async {
      final id = rawId is num
          ? rawId.toInt()
          : int.tryParse(rawId?.toString() ?? '');
      if (id == null) return null;
      try {
        final rows = await d.query(
          'Accessories',
          where: '(is_active = 1 OR is_active IS NULL) AND id = ?',
          whereArgs: [id],
          limit: 1,
        );
        return rows.isEmpty ? null : Map<String, dynamic>.from(rows.first);
      } catch (_) {
        return null;
      }
    }

    for (final entry in componentOverrides.entries) {
      final value = entry.value;
      if (value is! Map) continue;
      final accessory = Map<String, dynamic>.from(value);
      if (accessory['linked_accessory'] == null &&
          accessory['gache_accessory'] == null) {
        final linked = await findAccessory(
          accessory['linked_accessory_id'] ?? accessory['gache_accessory_id'],
        );
        if (linked != null) {
          accessory['linked_accessory'] = linked;
          accessory['gache_accessory'] = linked;
        }
      }
      if (accessory['screw_accessory'] == null) {
        final linked = await findAccessory(accessory['screw_accessory_id']);
        if (linked != null) accessory['screw_accessory'] = linked;
      }
      componentOverrides[entry.key] = accessory;
    }
  }

  void updateAllSlidingJointSides(bool twoSides) {
    final targets = zones.where((z) => z.content == ZoneContent.slidingSash);
    if (isPVC || targets.isEmpty) return;
    _saveSnapshot();
    for (final zone in targets) {
      zone.glass = zone.glass.copyWith(jointTwoSides: twoSides);
      zone.cellGlassSpec = zone.cellGlassSpec.map(
        (key, value) => MapEntry(key, value.copyWith(jointTwoSides: twoSides)),
      );
    }
    unawaited(updateGlassGasket());
    notifyListeners();
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
    if (jointTwoSides != null) {
      unawaited(updateGlassGasket());
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

  /// Converts the current drawing into a shutter while preserving its
  /// measured size and position on the canvas.
  void convertCurrentDrawingToShutter() {
    final currentWidth = width;
    final currentHeight = height;
    if (currentWidth <= 0 || currentHeight <= 0) {
      prepareShutterOnlyDrawing();
      return;
    }

    final currentLeft = drawnLeft;
    final currentTop = drawnTop;

    // Reuse the same cleanup used when starting a new shutter drawing, then
    // restore the existing dimensions instead of asking the user to redraw.
    prepareShutterOnlyDrawing();
    width = currentWidth;
    height = currentHeight;
    drawnLeft = currentLeft;
    drawnTop = currentTop;
    isShutterOnly = true;
    hasShutter = true;
    drawNextShapeAsShutterOnly = false;
    isDrawingMode = true;
    drawingMode = 'shutter_only';
    drawingStart = null;
    drawingCurrent = null;
    pendingDrawStart = null;
    unawaited(updateShutterDefaultsIfNeeded());
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
      // Auto-detect mode: inside an existing frame means split; inside a
      // deliberate blank area means draw a new independent frame there.
      final windowRect = Rect.fromLTWH(0, 0, width, height);
      final startsInsideFrame = zones.any(
        (zone) => zone.boundary.inflate(profileThickness).contains(pos),
      );
      if (windowRect.contains(pos) && startsInsideFrame) {
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
    if (drawingStart != null &&
        (drawingMode == 'new_frame' ||
            drawingMode == 'add_frame' ||
            drawingMode == 'shutter_only')) {
      final maxWidth = drawingMode == 'shutter_only'
          ? maximumShutterBarLengthMm
          : maximumFrameBarLengthMm;
      final maxHeight = drawingMode == 'shutter_only' ? 10000.0 : maxWidth;
      final delta = pos - drawingStart!;
      drawingCurrent = Offset(
        drawingStart!.dx + delta.dx.clamp(-maxWidth, maxWidth),
        drawingStart!.dy + delta.dy.clamp(-maxHeight, maxHeight),
      );
    } else {
      drawingCurrent = pos;
    }
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

  Rect? _blankFrameCellForDrawnFrame(Rect drawnRect, Offset start) {
    final windowRect = Rect.fromLTWH(0, 0, width, height);
    if (!windowRect.contains(start) || !windowRect.contains(drawnRect.center)) {
      return null;
    }

    final frameRects = getFrameRects();
    final xs = <double>[0.0, width];
    final ys = <double>[0.0, height];
    for (final frame in frameRects) {
      xs.add(frame.left.clamp(0.0, width).toDouble());
      xs.add(frame.right.clamp(0.0, width).toDouble());
      ys.add(frame.top.clamp(0.0, height).toDouble());
      ys.add(frame.bottom.clamp(0.0, height).toDouble());
    }

    List<double> sortedUnique(List<double> values) {
      values.sort();
      final result = <double>[];
      for (final value in values) {
        if (result.isEmpty || (value - result.last).abs() > 2.0) {
          result.add(value);
        }
      }
      return result;
    }

    final uniqueX = sortedUnique(xs);
    final uniqueY = sortedUnique(ys);
    Rect? best;
    double bestOverlap = 0.0;

    for (var xi = 0; xi < uniqueX.length - 1; xi++) {
      for (var yi = 0; yi < uniqueY.length - 1; yi++) {
        final cell = Rect.fromLTRB(
          uniqueX[xi],
          uniqueY[yi],
          uniqueX[xi + 1],
          uniqueY[yi + 1],
        );
        if (cell.width <= 50 + 2 * profileThickness ||
            cell.height <= 50 + 2 * profileThickness ||
            !cell.contains(start) ||
            !cell.contains(drawnRect.center)) {
          continue;
        }

        final occupied = frameRects.any(
          (frame) => frame.deflate(1.0).overlaps(cell.deflate(1.0)),
        );
        if (occupied) continue;

        final overlap = _rectOverlapArea(cell, drawnRect);
        if (overlap > bestOverlap) {
          best = cell;
          bestOverlap = overlap;
        }
      }
    }

    return best;
  }

  double _rectOverlapArea(Rect a, Rect b) {
    final left = math.max(a.left, b.left);
    final top = math.max(a.top, b.top);
    final right = math.min(a.right, b.right);
    final bottom = math.min(a.bottom, b.bottom);
    if (right <= left || bottom <= top) return 0.0;
    return (right - left) * (bottom - top);
  }

  void endDrawing() {
    pendingDrawStart = null; // always clear, even if we return early
    if (drawingStart == null || drawingCurrent == null) return;
    _saveSnapshot();
    if (drawingMode == 'shutter_only') {
      final drawnRect = Rect.fromPoints(drawingStart!, drawingCurrent!);
      if (drawnRect.width > 50 && drawnRect.height > 50) {
        width = drawnRect.width
            .clamp(200.0, maximumShutterBarLengthMm)
            .toDouble();
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
        width = _limitFrameDimension(drawnRect.width);
        height = _limitFrameDimension(drawnRect.height);
        drawnLeft = drawnRect.left;
        drawnTop = drawnRect.top;
        double topOffset = (hasShutter && !hasArchOrSlant)
            ? shutterBoxHeight
            : 0.0;
        const double pHeight = 0.0;
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
        final windowRect = Rect.fromLTWH(0, 0, width, height);
        final startsInBlankArea =
            windowRect.contains(drawingStart!) &&
            !zones.any(
              (zone) => zone.boundary
                  .inflate(profileThickness)
                  .contains(drawingStart!),
            );
        final blankFrameRect = startsInBlankArea
            ? _blankFrameCellForDrawnFrame(drawnRect, drawingStart!)
            : null;
        final isInternalBlankFrame = blankFrameRect != null;
        drawnRect = blankFrameRect ?? drawnRect;

        if (startsInBlankArea && !isInternalBlankFrame) {
          drawingStart = null;
          drawingCurrent = null;
          notifyListeners();
          return;
        }
        if (isInternalBlankFrame) {
          final inner = Rect.fromLTRB(
            drawnRect.left + profileThickness,
            drawnRect.top + profileThickness,
            drawnRect.right - profileThickness,
            drawnRect.bottom - (hasBottomFrame ? profileThickness : 0.0),
          );
          if (inner.width > 50 && inner.height > 50) {
            zones.add(
              WindowZone(
                id: UniqueKey().toString(),
                boundary: inner,
                sashThickness: _calculateSashThickness(false),
                sashColor: FrameColor.white,
                selectedDbColor: _selectedDbColor,
              ),
            );
            width = math.max(width, drawnRect.right);
            height = math.max(height, drawnRect.bottom);
            updatePrimaryMullionAxis();
          }
          drawingStart = null;
          drawingCurrent = null;
          notifyListeners();
          return;
        }

        double newW = _limitFrameDimension(drawnRect.width);
        double newH = _limitFrameDimension(drawnRect.height);

        double topOffset = (hasShutter && !hasArchOrSlant)
            ? shutterBoxHeight
            : 0.0;
        const double pHeight = 0.0;
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

        final drawnX1 = math.min(drawingStart!.dx, drawingCurrent!.dx);
        final drawnX2 = math.max(drawingStart!.dx, drawingCurrent!.dx);
        final drawnY1 = math.min(drawingStart!.dy, drawingCurrent!.dy);
        final drawnY2 = math.max(drawingStart!.dy, drawingCurrent!.dy);
        final tThickness = divisionThickness;

        double spanLeft = 0.0;
        double spanRight = width;
        double spanTop = 0.0;
        double spanBottom = height;
        // Select only the physical frames in the row/column nearest to the
        // side where the new frame is being drawn. The old joint-based
        // implementation treated every interval touched by a 100 mm halo as
        // selected, so a drag over one column could unexpectedly span several
        // columns (or the full drawing).
        final frameRects = getFrameRects();
        final addingTop = minVal == dyTop;
        final addingBottom = minVal == dyBottom;
        final addingLeft = minVal == dxLeft;
        final addingRight = minVal == dxRight;

        double distanceToDrawnSide(Rect frame) {
          if (addingTop) return math.max(0.0, frame.top - drawnRect.bottom);
          if (addingBottom) return math.max(0.0, drawnRect.top - frame.bottom);
          if (addingLeft) return math.max(0.0, frame.left - drawnRect.right);
          if (addingRight) return math.max(0.0, drawnRect.left - frame.right);
          return 0.0;
        }

        final nearestDistance = frameRects.isEmpty
            ? double.infinity
            : frameRects.map(distanceToDrawnSide).reduce(math.min);
        final referenceFrames = frameRects
            .where(
              (frame) =>
                  (distanceToDrawnSide(frame) - nearestDistance).abs() <= 2.0,
            )
            .toList();

        if (addingTop || addingBottom) {
          final matched = referenceFrames
              .where(
                (frame) =>
                    math.min(frame.right, drawnX2) -
                        math.max(frame.left, drawnX1) >
                    5.0,
              )
              .toList();
          if (matched.isNotEmpty) {
            spanLeft = matched.map((frame) => frame.left).reduce(math.min);
            spanRight = matched.map((frame) => frame.right).reduce(math.max);
          }
        } else if (addingLeft || addingRight) {
          final matched = referenceFrames
              .where(
                (frame) =>
                    math.min(frame.bottom, drawnY2) -
                        math.max(frame.top, drawnY1) >
                    5.0,
              )
              .toList();
          if (matched.isNotEmpty) {
            spanTop = matched.map((frame) => frame.top).reduce(math.min);
            spanBottom = matched.map((frame) => frame.bottom).reduce(math.max);
          }
        }

        if (copyPreviousFrameSize || newW < 50.0) {
          final joints = getVerticalFrameJoints();
          if (minVal == dxRight) {
            final start = joints.isEmpty ? 0.0 : joints.last;
            newW = width - start;
          } else if (minVal == dxLeft) {
            final end = joints.isEmpty ? width : joints.first;
            newW = end;
          }
        }

        if (copyPreviousFrameSize || newH < 50.0) {
          final joints = getHorizontalFrameJoints();
          if (minVal == dyBottom) {
            final start = joints.isEmpty ? 0.0 : joints.last;
            newH = height - start;
          } else if (minVal == dyTop) {
            final end = joints.isEmpty ? height : joints.first;
            newH = end;
          }
        }

        newW = _limitFrameDimension(newW);
        newH = _limitFrameDimension(newH);

        final List<WindowZone> newZones = [];

        if (minVal == dxRight) {
          double oldW = width;
          width = oldW + newW;
          for (var z in zones) {
            double rightEdge = oldW - profileThickness;
            bool isBesideSpan =
                z.boundary.bottom > spanTop + 5.0 &&
                z.boundary.top < spanBottom - 5.0;
            double newRight =
                (z.boundary.right - rightEdge).abs() < 2.0 && isBesideSpan
                ? oldW - tThickness / 2
                : z.boundary.right;
            final cloned = z.clone();
            cloned.boundary = Rect.fromLTRB(
              z.boundary.left,
              z.boundary.top,
              newRight,
              z.boundary.bottom,
            );
            newZones.add(cloned);
          }
          newZones.add(
            WindowZone(
              id: UniqueKey().toString(),
              boundary: Rect.fromLTRB(
                oldW + tThickness / 2,
                spanTop +
                    (spanTop <= 1.0
                        ? topOffset + profileThickness
                        : tThickness / 2),
                width - profileThickness,
                spanBottom -
                    (spanBottom >= height - 1.0
                        ? bottomOffset + pHeight
                        : tThickness / 2),
              ),
              sashThickness: _calculateSashThickness(false),
            ),
          );
        } else if (minVal == dxLeft) {
          double oldW = width;
          width = oldW + newW;
          for (var z in zones) {
            double leftEdge = profileThickness;
            bool isBesideSpan =
                z.boundary.bottom > spanTop + 5.0 &&
                z.boundary.top < spanBottom - 5.0;
            double newLeft =
                (z.boundary.left - leftEdge).abs() < 2.0 && isBesideSpan
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
                spanTop +
                    (spanTop <= 1.0
                        ? topOffset + profileThickness
                        : tThickness / 2),
                newW - tThickness / 2,
                spanBottom -
                    (spanBottom >= height - 1.0
                        ? bottomOffset + pHeight
                        : tThickness / 2),
              ),
              sashThickness: _calculateSashThickness(false),
            ),
          );
        } else if (minVal == dyBottom) {
          double oldH = height;
          height = oldH + newH;
          for (var z in zones) {
            double bottomEdge = oldH - bottomOffset - pHeight;
            bool isUnderSpan =
                z.boundary.right > spanLeft + 5.0 &&
                z.boundary.left < spanRight - 5.0;
            double newBottom =
                (z.boundary.bottom - bottomEdge).abs() < 2.0 && isUnderSpan
                ? oldH - tThickness / 2
                : z.boundary.bottom;
            final cloned = z.clone();
            cloned.boundary = Rect.fromLTRB(
              z.boundary.left,
              z.boundary.top,
              z.boundary.right,
              newBottom,
            );
            newZones.add(cloned);
          }
          newZones.add(
            WindowZone(
              id: UniqueKey().toString(),
              boundary: Rect.fromLTRB(
                spanLeft +
                    (spanLeft <= 1.0 ? profileThickness : tThickness / 2),
                oldH + tThickness / 2,
                spanRight -
                    (spanRight >= width - 1.0
                        ? profileThickness
                        : tThickness / 2),
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
            bool isUnderSpan =
                z.boundary.right > spanLeft + 5.0 &&
                z.boundary.left < spanRight - 5.0;
            double newTop =
                (z.boundary.top - topEdge).abs() < 2.0 && isUnderSpan
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
                spanLeft +
                    (spanLeft <= 1.0 ? profileThickness : tThickness / 2),
                topOffset + profileThickness,
                spanRight -
                    (spanRight >= width - 1.0
                        ? profileThickness
                        : tThickness / 2),
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
              targetZone.primaryDivisionAxis ??= 'h';

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
              _keepPrimaryInnerDivisionsContinuous(
                targetZone,
                isRightSash: false,
              );
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
              targetZone.primaryDivisionAxis ??= 'v';

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
              _keepPrimaryInnerDivisionsContinuous(
                targetZone,
                isRightSash: false,
              );
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
                targetZone.rightPrimaryDivisionAxis ??= 'h';

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
                _keepPrimaryInnerDivisionsContinuous(
                  targetZone,
                  isRightSash: true,
                );
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
                targetZone.primaryDivisionAxis ??= 'h';

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
                _keepPrimaryInnerDivisionsContinuous(
                  targetZone,
                  isRightSash: false,
                );
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
                targetZone.rightPrimaryDivisionAxis ??= 'v';

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
                _keepPrimaryInnerDivisionsContinuous(
                  targetZone,
                  isRightSash: true,
                );
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
                targetZone.primaryDivisionAxis ??= 'v';

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
                _keepPrimaryInnerDivisionsContinuous(
                  targetZone,
                  isRightSash: false,
                );
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
    // 🟢 تثبيت أولوية التقسيم الأول (إذا كان أول تقسيم عمودياً يثبت كـ v ولا يتغير)
    if (horizontal) {
      primaryMullionAxis ??= 'h';
    } else {
      primaryMullionAxis ??= 'v';
    }
    final List<WindowZone> newZones = [];
    final sep = mullionThickness / 2;
    double minPath = horizontal
        ? math.min(start.dx, end.dx)
        : math.min(start.dy, end.dy);
    double maxPath = horizontal
        ? math.max(start.dx, end.dx)
        : math.max(start.dy, end.dy);
    double cutLine = _snapCutLineToNearbyMullion(start, end, horizontal);
    recordMullionCreation(horizontal, cutLine);

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
            _splitClone(
              z,
              Rect.fromLTRB(
                z.boundary.left,
                cutLine + sep,
                z.boundary.right,
                z.boundary.bottom,
              ),
            ),
          );
          newZones.add(
            _splitClone(
              z,
              Rect.fromLTRB(
                z.boundary.left,
                z.boundary.top,
                z.boundary.right,
                cutLine - sep,
              ),
            ),
          );
        } else {
          newZones.add(
            _splitClone(
              z,
              Rect.fromLTRB(
                cutLine + sep,
                z.boundary.top,
                z.boundary.right,
                z.boundary.bottom,
              ),
            ),
          );
          newZones.add(
            _splitClone(
              z,
              Rect.fromLTRB(
                z.boundary.left,
                z.boundary.top,
                cutLine - sep,
                z.boundary.bottom,
              ),
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

  WindowZone _splitClone(WindowZone source, Rect boundary) {
    return source.cloneForSplit(boundary);
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
          final overlap = math.min(a.right, b.right) - math.max(a.left, b.left);
          if (overlap <= 5.0) continue;
          candidates.add(
            aBelowB ? (a.bottom + b.top) / 2 : (b.bottom + a.top) / 2,
          );
        } else {
          final aLeftOfB = (a.right - b.left).abs() <= mullionThickness + 4.0;
          final bLeftOfA = (b.right - a.left).abs() <= mullionThickness + 4.0;
          if (!aLeftOfB && !bLeftOfA) continue;
          final overlap = math.min(a.bottom, b.bottom) - math.max(a.top, b.top);
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
    final selectedStart = selection.mullionStart ?? double.negativeInfinity;
    final selectedEnd = selection.mullionEnd ?? double.infinity;
    bool overlapsSelectedSpan(WindowZone zone) {
      final spanStart = isH ? zone.boundary.left : zone.boundary.top;
      final spanEnd = isH ? zone.boundary.right : zone.boundary.bottom;
      return math.max(spanStart, selectedStart) <
          math.min(spanEnd, selectedEnd) - 2.0;
    }

    if (isH) {
      double minAllowedY = t * 2;
      double maxAllowedY = height - t * 2;
      for (var z in zones) {
        if (!overlapsSelectedSpan(z)) continue;
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
        if (!overlapsSelectedSpan(z)) continue;
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
      _snapNearbyParallelMullions(isHorizontal: true, targetPos: newPos);
    } else {
      double minAllowedX = t * 2;
      double maxAllowedX = width - t * 2;
      for (var z in zones) {
        if (!overlapsSelectedSpan(z)) continue;
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
        if (!overlapsSelectedSpan(z)) continue;
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
      _snapNearbyParallelMullions(isHorizontal: false, targetPos: newPos);
    }
    notifyListeners();
  }

  /// محاذاة تلقائية للتقسيمات المتوازية المجاورة عندما تكون في مجال 10 سم (100 ملم)
  void _snapNearbyParallelMullions({
    required bool isHorizontal,
    required double targetPos,
  }) {
    const double snapThreshold = 100.0; // 10 سم
    final sep = mullionThickness / 2;

    final candidates = <double>{};
    for (var z in zones) {
      if (isHorizontal) {
        final bottomPos = z.boundary.bottom + sep;
        final topPos = z.boundary.top - sep;
        if (z.boundary.top > profileThickness + 1) candidates.add(topPos);
        if (z.boundary.bottom < height - profileThickness - 1) {
          candidates.add(bottomPos);
        }
      } else {
        final rightPos = z.boundary.right + sep;
        final leftPos = z.boundary.left - sep;
        if (z.boundary.left > profileThickness + 1) candidates.add(leftPos);
        if (z.boundary.right < width - profileThickness - 1) {
          candidates.add(rightPos);
        }
      }
    }

    for (final candidatePos in candidates) {
      final distance = (candidatePos - targetPos).abs();
      if (distance < 1.0 || distance > snapThreshold) continue;

      final diff = targetPos - candidatePos;
      if (isHorizontal) {
        _moveInternalBoundaryY(candidatePos - sep, diff);
      } else {
        _moveInternalBoundaryX(candidatePos - sep, diff);
      }
    }
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
    final bool isH = selection.isHorizontalMullion!;
    final double pos = selection.mullionPosition!;
    final double sep = mullionThickness / 2;
    final double selectedStart =
        selection.mullionStart ?? double.negativeInfinity;
    final double selectedEnd = selection.mullionEnd ?? double.infinity;

    bool overlapsSelectedSpan(WindowZone zone) {
      final spanStart = isH ? zone.boundary.left : zone.boundary.top;
      final spanEnd = isH ? zone.boundary.right : zone.boundary.bottom;
      return math.max(spanStart, selectedStart) <
          math.min(spanEnd, selectedEnd) - 2.0;
    }

    final List<WindowZone> newZones = [];
    final Set<String> processedZoneIds = {};

    if (isH) {
      // ── تقسيم أفقي: دمج كل زوج متقابل (أعلى / أسفل) ──
      final topZones = zones
          .where(
            (z) =>
                overlapsSelectedSpan(z) &&
                (z.boundary.bottom - (pos - sep)).abs() < 4.0,
          )
          .toList();
      final bottomZones = zones
          .where(
            (z) =>
                overlapsSelectedSpan(z) &&
                (z.boundary.top - (pos + sep)).abs() < 4.0,
          )
          .toList();

      for (final topZ in topZones) {
        WindowZone? matchingBottom;
        double maxOverlap = 0.0;

        for (final botZ in bottomZones) {
          if (processedZoneIds.contains(botZ.id)) continue;
          final overlapL = math.max(topZ.boundary.left, botZ.boundary.left);
          final overlapR = math.min(topZ.boundary.right, botZ.boundary.right);
          final overlap = overlapR - overlapL;
          if (overlap > 5.0 && overlap > maxOverlap) {
            maxOverlap = overlap;
            matchingBottom = botZ;
          }
        }

        if (matchingBottom != null) {
          processedZoneIds.add(topZ.id);
          processedZoneIds.add(matchingBottom.id);

          final mergedRect = Rect.fromLTRB(
            math.min(topZ.boundary.left, matchingBottom.boundary.left),
            topZ.boundary.top,
            math.max(topZ.boundary.right, matchingBottom.boundary.right),
            matchingBottom.boundary.bottom,
          );

          final primaryZone = topZ.content != ZoneContent.empty
              ? topZ
              : matchingBottom;
          newZones.add(primaryZone.copyWith(boundary: mergedRect));
        }
      }
    } else {
      // ── تقسيم عمودي: دمج كل زوج متقابل (يسار / يمين) ──
      final leftZones = zones
          .where(
            (z) =>
                overlapsSelectedSpan(z) &&
                (z.boundary.right - (pos - sep)).abs() < 4.0,
          )
          .toList();
      final rightZones = zones
          .where(
            (z) =>
                overlapsSelectedSpan(z) &&
                (z.boundary.left - (pos + sep)).abs() < 4.0,
          )
          .toList();

      for (final leftZ in leftZones) {
        WindowZone? matchingRight;
        double maxOverlap = 0.0;

        for (final rightZ in rightZones) {
          if (processedZoneIds.contains(rightZ.id)) continue;
          final overlapT = math.max(leftZ.boundary.top, rightZ.boundary.top);
          final overlapB = math.min(
            leftZ.boundary.bottom,
            rightZ.boundary.bottom,
          );
          final overlap = overlapB - overlapT;
          if (overlap > 5.0 && overlap > maxOverlap) {
            maxOverlap = overlap;
            matchingRight = rightZ;
          }
        }

        if (matchingRight != null) {
          processedZoneIds.add(leftZ.id);
          processedZoneIds.add(matchingRight.id);

          final mergedRect = Rect.fromLTRB(
            leftZ.boundary.left,
            math.min(leftZ.boundary.top, matchingRight.boundary.top),
            matchingRight.boundary.right,
            math.max(leftZ.boundary.bottom, matchingRight.boundary.bottom),
          );

          final primaryZone = leftZ.content != ZoneContent.empty
              ? leftZ
              : matchingRight;
          newZones.add(primaryZone.copyWith(boundary: mergedRect));
        }
      }
    }

    // إضافة جميع المناطق التي لم تتأثر بالحذف كما هي تماماً
    for (final z in zones) {
      if (!processedZoneIds.contains(z.id)) {
        newZones.add(z);
      }
    }

    zones = newZones;
    selection = SelectionInfo.none;

    final key = _mullionKey(isH, pos);
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
    _keepPrimaryInnerDivisionsContinuous(zone, isRightSash: false);

    if (zone.rightInnerH == 0 && zone.rightInnerV == 0) {
      zone.rightPrimaryDivisionAxis = null;
    } else if (zone.rightInnerH == 0) {
      zone.rightPrimaryDivisionAxis = 'v';
    } else if (zone.rightInnerV == 0) {
      zone.rightPrimaryDivisionAxis = 'h';
    }
    _keepPrimaryInnerDivisionsContinuous(zone, isRightSash: true);

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

    const double minDivSpacing = 30.0;
    double minRatioH = minDivSpacing / glassR.height;
    double minRatioV = minDivSpacing / glassR.width;

    double movedAbsolutePos = 0.0;

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
        if (minVal > maxVal) return;
        pos[index] = newVal.clamp(minVal, maxVal);
        if (isRight) {
          zone.rightInnerHPositions = pos;
        } else {
          zone.innerHPositions = pos;
        }
        movedAbsolutePos = glassR.top + glassR.height * pos[index];
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
        if (minVal > maxVal) return;
        pos[index] = newVal.clamp(minVal, maxVal);
        if (isRight) {
          zone.rightInnerVPositions = pos;
        } else {
          zone.innerVPositions = pos;
        }
        movedAbsolutePos = glassR.left + glassR.width * pos[index];
      }
    }

    // ── الالتصاق المغناطيسي للضلفة المجاورة والإطارات المجاورة ضمن 100 ملم ──
    _snapNearbyInnerDivisions(
      sourceZoneId: zone.id,
      sourceIsRight: isRight,
      isHorizontal: isH,
      targetAbsolutePos: movedAbsolutePos,
    );

    notifyListeners();
  }

  /// محاذاة تلقائية لأي تقسيم موازٍ في الضلفة المجاورة (داخل الضلفتين أو عبر المناطق)
  /// عندما يكون في مجال 10 سم (100 ملم)
  void _snapNearbyInnerDivisions({
    required String sourceZoneId,
    required bool sourceIsRight,
    required bool isHorizontal,
    required double targetAbsolutePos,
  }) {
    const double snapThresholdMm = 100.0; // 10 سم

    for (final z in zones) {
      final isDouble = z.content == ZoneContent.doubleSash;
      final sides = isDouble ? [false, true] : [false];

      for (final isRightSide in sides) {
        // تخطي نفس الضلفة التي يتم تحريكها حالياً
        if (z.id == sourceZoneId && isRightSide == sourceIsRight) continue;

        double sT =
            z.sashThickness ?? getSectionThickness('sash', fallback: 45.0);
        Rect sR = z.boundary;
        if (isDouble) {
          final sep = 4.0;
          final midX = sR.left + sR.width * z.doubleSashRatio;
          sR = isRightSide
              ? Rect.fromLTRB(midX + sep / 2, sR.top, sR.right, sR.bottom)
              : Rect.fromLTRB(sR.left, sR.top, midX - sep / 2, sR.bottom);
        }
        final gR = getSafeGlassRect(sR, sT);

        if (isHorizontal) {
          List<double> positions = List.from(
            isRightSide ? z.rightInnerHPositions : z.innerHPositions,
          );
          bool changed = false;
          for (int i = 0; i < positions.length; i++) {
            double currentAbsY = gR.top + gR.height * positions[i];
            if ((currentAbsY - targetAbsolutePos).abs() <= snapThresholdMm) {
              double targetRatio = (targetAbsolutePos - gR.top) / gR.height;
              positions[i] = targetRatio.clamp(0.05, 0.95);
              changed = true;
            }
          }
          if (changed) {
            if (isRightSide) {
              z.rightInnerHPositions = positions;
            } else {
              z.innerHPositions = positions;
            }
          }
        } else {
          List<double> positions = List.from(
            isRightSide ? z.rightInnerVPositions : z.innerVPositions,
          );
          bool changed = false;
          for (int i = 0; i < positions.length; i++) {
            double currentAbsX = gR.left + gR.width * positions[i];
            if ((currentAbsX - targetAbsolutePos).abs() <= snapThresholdMm) {
              double targetRatio = (targetAbsolutePos - gR.left) / gR.width;
              positions[i] = targetRatio.clamp(0.05, 0.95);
              changed = true;
            }
          }
          if (changed) {
            if (isRightSide) {
              z.rightInnerVPositions = positions;
            } else {
              z.innerVPositions = positions;
            }
          }
        }
      }
    }
  }

  /// حذف الإطار المحدد حالياً وسد الفراغ تلقائياً مع تحديث أبعاد النافذة
  void deleteSelectedFrame() {
    final groups = _frameZoneGroups();
    final rects = getFrameRects();
    if (groups.isEmpty || rects.isEmpty) return;

    int? targetIndex;
    if (selection.type == SelectionType.frame && selection.zoneId != null) {
      targetIndex = _frameIndexFromSelectionKey(selection.zoneId!);
    }
    if (targetIndex == null && selectedZone != null) {
      for (int i = 0; i < groups.length; i++) {
        if (groups[i].any((z) => z.id == selectedZone!.id)) {
          targetIndex = i;
          break;
        }
      }
    }

    if (targetIndex == null ||
        targetIndex < 0 ||
        targetIndex >= groups.length) {
      return;
    }

    _saveSnapshot();

    // إذا كان الإطار الوحيد، يتم تصفير كل شيء
    if (groups.length == 1) {
      clearAll();
      notifyListeners();
      return;
    }

    final deletedFrameRect = rects[targetIndex];
    final deletedZones = groups[targetIndex];
    final deletedZoneIds = deletedZones.map((z) => z.id).toSet();

    // حذف مناطق الإطار المحدد
    zones.removeWhere((z) => deletedZoneIds.contains(z.id));

    // حساب إزاحة الإطارات المتبقية على اليمين لسد الفراغ
    final double shiftX = deletedFrameRect.width;

    // الإطارات الواقعة على يمين الإطار المحذوف تُزاح لليسار
    for (int i = 0; i < groups.length; i++) {
      if (i == targetIndex) continue;
      final otherRect = rects[i];
      if (otherRect.left >= deletedFrameRect.right - 2.0) {
        for (final z in groups[i]) {
          z.boundary = z.boundary.shift(Offset(-shiftX, 0));
        }
      }
    }

    // إذا كان الإطار المحذوف هو الأول وكان باقي الإطارات مزاحة، نعيد محاذاة البداية
    double minLeft = double.infinity;
    for (final z in zones) {
      if (z.boundary.left < minLeft) minLeft = z.boundary.left;
    }
    if (minLeft != double.infinity && minLeft > profileThickness + 1.0) {
      final double correction = minLeft - profileThickness;
      for (final z in zones) {
        z.boundary = z.boundary.shift(Offset(-correction, 0));
      }
    }

    // تحديث العرض والارتفاع الكلي
    double maxRight = 200.0;
    double maxBottom = 200.0;
    for (final z in zones) {
      if (z.boundary.right + profileThickness > maxRight) {
        maxRight = z.boundary.right + profileThickness;
      }
      if (z.boundary.bottom + profileThickness > maxBottom) {
        maxBottom = z.boundary.bottom + profileThickness;
      }
    }
    width = maxRight;
    height = maxBottom;

    selection = SelectionInfo.none;
    showZoneMenu = false;
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

  List<List<WindowZone>> _frameZoneGroups() {
    final List<List<WindowZone>> groups = [];
    final double jointT = profileThickness * 2;

    bool zonesAreAdjacent(WindowZone first, WindowZone second) {
      final verticalTouch =
          (first.boundary.right - second.boundary.left).abs() < jointT - 2.0 ||
          (second.boundary.right - first.boundary.left).abs() < jointT - 2.0;
      if (verticalTouch) {
        final overlapTop = math.max(first.boundary.top, second.boundary.top);
        final overlapBottom = math.min(
          first.boundary.bottom,
          second.boundary.bottom,
        );
        if (overlapTop < overlapBottom - 5.0) return true;
      }

      final horizontalTouch =
          (first.boundary.bottom - second.boundary.top).abs() < jointT - 2.0 ||
          (second.boundary.bottom - first.boundary.top).abs() < jointT - 2.0;
      if (horizontalTouch) {
        final overlapLeft = math.max(first.boundary.left, second.boundary.left);
        final overlapRight = math.min(
          first.boundary.right,
          second.boundary.right,
        );
        if (overlapLeft < overlapRight - 5.0) return true;
      }
      return false;
    }

    for (final zone in zones) {
      final List<int> connectedGroupIndices = [];
      for (int i = 0; i < groups.length; i++) {
        bool isConnected = false;
        for (final other in groups[i]) {
          if (zonesAreAdjacent(zone, other)) {
            isConnected = true;
            break;
          }
        }
        // A partially visited grid is often L-shaped. Rejecting it before
        // visiting the remaining panes splits one real frame into several.
        // Connectivity uses the physical double-frame gap above, so coupled
        // frames remain separate without an area test on partial groups.
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

    return groups;
  }

  List<Rect> getFrameRects() {
    final groups = _frameZoneGroups();

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

  /// Returns only the outside perimeter of the physical frames.
  ///
  /// A single global rectangle is incorrect when one frame is above only
  /// part of another row: it creates a cover across the empty area. Shared
  /// edges are therefore removed and touching collinear edges are joined.
  List<FrameEdgeSegment> getExposedFrameEdgeSegments() {
    final rects = getFrameRects();
    if (rects.length <= 1) return const <FrameEdgeSegment>[];

    // Adjacent frames can differ by a few logical pixels after proportional
    // layout/rounding. Treat that seam as shared so no cover or visual gap is
    // produced between the frames.
    const tolerance = 5.0;
    final raw = <FrameEdgeSegment>[];

    void addVisiblePieces({
      required String side,
      required double start,
      required double end,
      required double coordinate,
      required List<List<double>> blockers,
    }) {
      var pieces = <List<double>>[
        [start, end],
      ];
      for (final blocker in blockers) {
        final next = <List<double>>[];
        for (final piece in pieces) {
          final overlapStart = math.max(piece[0], blocker[0]);
          final overlapEnd = math.min(piece[1], blocker[1]);
          if (overlapEnd <= overlapStart + tolerance) {
            next.add(piece);
            continue;
          }
          if (piece[0] < overlapStart - tolerance) {
            next.add([piece[0], overlapStart]);
          }
          if (overlapEnd < piece[1] - tolerance) {
            next.add([overlapEnd, piece[1]]);
          }
        }
        pieces = next;
        if (pieces.isEmpty) break;
      }
      for (final piece in pieces) {
        if (piece[1] > piece[0] + tolerance) {
          raw.add(
            FrameEdgeSegment(
              side: side,
              start: piece[0],
              end: piece[1],
              coordinate: coordinate,
            ),
          );
        }
      }
    }

    for (var index = 0; index < rects.length; index++) {
      final rect = rects[index];
      final others = [
        for (var otherIndex = 0; otherIndex < rects.length; otherIndex++)
          if (otherIndex != index) rects[otherIndex],
      ];

      addVisiblePieces(
        side: 'top',
        start: rect.left,
        end: rect.right,
        coordinate: rect.top,
        blockers: [
          for (final other in others)
            if ((other.bottom - rect.top).abs() <= tolerance)
              [
                math.max(rect.left, other.left),
                math.min(rect.right, other.right),
              ],
        ],
      );
      addVisiblePieces(
        side: 'bottom',
        start: rect.left,
        end: rect.right,
        coordinate: rect.bottom,
        blockers: [
          for (final other in others)
            if ((other.top - rect.bottom).abs() <= tolerance)
              [
                math.max(rect.left, other.left),
                math.min(rect.right, other.right),
              ],
        ],
      );
      addVisiblePieces(
        side: 'left',
        start: rect.top,
        end: rect.bottom,
        coordinate: rect.left,
        blockers: [
          for (final other in others)
            if ((other.right - rect.left).abs() <= tolerance)
              [
                math.max(rect.top, other.top),
                math.min(rect.bottom, other.bottom),
              ],
        ],
      );
      addVisiblePieces(
        side: 'right',
        start: rect.top,
        end: rect.bottom,
        coordinate: rect.right,
        blockers: [
          for (final other in others)
            if ((other.left - rect.right).abs() <= tolerance)
              [
                math.max(rect.top, other.top),
                math.min(rect.bottom, other.bottom),
              ],
        ],
      );
    }

    raw.sort((a, b) {
      final sideCompare = a.side.compareTo(b.side);
      if (sideCompare != 0) return sideCompare;
      final coordinateCompare = a.coordinate.compareTo(b.coordinate);
      if (coordinateCompare != 0) return coordinateCompare;
      return a.start.compareTo(b.start);
    });

    final merged = <FrameEdgeSegment>[];
    for (final segment in raw) {
      if (merged.isNotEmpty) {
        final previous = merged.last;
        if (previous.side == segment.side &&
            (previous.coordinate - segment.coordinate).abs() <= tolerance &&
            segment.start <= previous.end + tolerance) {
          merged[merged.length - 1] = FrameEdgeSegment(
            side: previous.side,
            start: previous.start,
            end: math.max(previous.end, segment.end),
            coordinate: previous.coordinate,
          );
          continue;
        }
      }
      merged.add(segment);
    }
    return merged;
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
