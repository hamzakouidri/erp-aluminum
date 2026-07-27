// Force compile sync trigger 2
import 'dart:math' as math;
import 'dart:async';
import 'package:flutter/material.dart';
import '../../sql_database.dart';

enum DimensionTap { none, width, height }

enum LockType { none, clef, condamnation, point, rouleau, cremone, rouleau2000 }

enum ZoneContent { empty, fixedGlass, singleSash, doubleSash, slidingSash }

enum GlassStructure { simple, double, closed }

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
  final isOpening = value.contains('frappe') ||
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
    panneauProductId: panneauProductId ?? this.panneauProductId,
    thicknessOuter: thicknessOuter ?? this.thicknessOuter,
    thicknessInner: thicknessInner ?? this.thicknessInner,
    laminatedColorOuter: laminatedColorOuter ?? this.laminatedColorOuter,
    laminatedColorInner: laminatedColorInner ?? this.laminatedColorInner,
    rosetteShape: rosetteShape ?? this.rosetteShape,
    jointTwoSides: jointTwoSides ?? this.jointTwoSides,
  );

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
              (g['subtype']?.toString().toLowerCase() == panneauSubtype!.toLowerCase() ||
               g['name'].toString().toLowerCase().contains(panneauSubtype!.toLowerCase())),
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
            finishKws.any((kw) =>
                g['type'].toString().toLowerCase().contains(kw) ||
                g['name'].toString().toLowerCase().contains(kw)),
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
    disabledVerticalDivisions: Map.from(disabledVerticalDivisions),
    disabledHorizontalDivisions: Map.from(disabledHorizontalDivisions),
    primaryDivisionAxis: primaryDivisionAxis,
    rightPrimaryDivisionAxis: rightPrimaryDivisionAxis,
    isSubdivided: isSubdivided,
    hasSashPlintheBottom: hasSashPlintheBottom,
    cellGlassSpec: Map.from(cellGlassSpec.map((k, v) => MapEntry(k, v.clone()))),
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
    cellGlassSpec: cellGlassSpec ?? Map.from(this.cellGlassSpec.map((k, v) => MapEntry(k, v.clone()))),
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
  final bool hasFramePlintheBottom;
  final List<WindowZone> zones;
  final Map<String, MullionProfileType> mullionProfiles;
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

  WindowSnapshot(
    this.width,
    this.height,
    this.hasBottomFrame,
    this.hasFramePlintheBottom,
    this.zones,
    this.mullionProfiles,
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
          const Color(0xFF9E9E9E),
          const Color(0xFF757575),
          const Color(0xFF616161),
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
        return const Color(0xFF616161);
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

    if (name.contains('ديزر') || name.contains('desert')) {
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

    if (name.contains('gold') || name.contains('ذهبي') || name.contains('or')) {
      return [
        const Color(0xFFFFF3CC),
        const Color(0xFFD4AF37),
        const Color(0xFF8A6421),
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
        name.contains('وايت')) {
      return [
        const Color(0xFFF5E6C8),
        const Color(0xFFDDC8A0),
        const Color(0xFFBBA070),
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

    if (name.contains('ديزر') || name.contains('desert')) {
      return [
        const Color(0xFFCBA56A),
        const Color(0xFFA8803E),
        const Color(0xFF7A5828),
      ];
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
      return const Color(0xFF909090);
    }

    if (name.contains('9007')) {
      return FrameColor.gris.borderColor;
    }

    if (name.contains('antique') ||
        name.contains('انتيك') ||
        name.contains('╪º┘å╪¬┘è┘â')) {
      return FrameColor.antique.borderColor;
    }

    if (name.contains('ديزر') || name.contains('desert')) {
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

    if (name.contains('gold') || name.contains('ذهبي') || name.contains('or')) {
      return const Color(0xFF8A6421);
    }

    if (name.contains('silver') ||
        name.contains('فضي') ||
        name.contains('argent')) {
      return const Color(0xFF7D7D80);
    }

    if (name.contains('champagne') ||
        name.contains('شامبان') ||
        name.contains('وايت')) {
      return const Color(0xFF8D6E63);
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
  List<PlacedFrame> frames = [];
  PlacedFrame? selectedFrame;
  String? selectedFrameCode;
  Map<String, dynamic> componentOverrides = {};
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
  String? position;
  String? loadedSeriesName;
  String? loadedSlidingSeriesName;
  int? loadedSeriesId;
  int? loadedSlidingSeriesId;
  Map<String, dynamic>? seriesTableConfig;

  Future<void> loadSeriesTableConfig() async {
    final myDb = db;
    if (myDb == null) return;
    final sId = loadedSlidingSeriesId ?? loadedSeriesId ?? activeSlidingSeries?.id ?? activeSeries?.id;
    if (sId != null) {
      try {
        seriesTableConfig = await myDb.getSeriesTableConfig(sId);
      } catch (e) {
        debugPrint('Error loading seriesTableConfig: $e');
      }
    }
  }

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

  bool get isDoor =>
      zones.any((z) => z.lockType == LockType.clef || z.lockType == LockType.condamnation);

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

  bool get isPVC {
    final series = (systemMode == 'sliding') ? activeSlidingSeries : activeSeries;
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
    if (s != null) return s.visibleWidth;
    return profileThickness;
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
  bool isFrame140 = false;
  bool isShutterOnly = false;
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

  void setCaissonTunnelHeight(double value) {
    if (caissonTunnelHeight == value) return;
    _saveSnapshot();
    caissonTunnelHeight = value;
    notifyListeners();
  }

  AluminumSection? selectedSideCover;

  List<AluminumSection> get availableSideCovers {
    if (activeSeries == null) return [];
    return activeSeries!.sections.where((s) {
      final type = s.type.toLowerCase();
      return type.contains('couvre') ||
          type.contains('side_cover') ||
          type.contains('غطاء') ||
          type.contains('جانبي');
    }).toList();
  }

  bool get isSideCoverAllowed {
    final frame = getSectionByType('frame');
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
    if (frameOverride != null) {
      final nameLower = (frameOverride!['name'] ?? '').toString().toLowerCase();
      final typeLower = (frameOverride!['type'] ?? '').toString().toLowerCase();
      final double cjW = (frameOverride!['couvre_joint_width'] as num?)?.toDouble() ?? 0.0;
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

  double get sideCoverWidth {
    if (frameOverride != null) {
      final double? w = (frameOverride!['couvre_joint_width'] as num?)?.toDouble() ??
          (frameOverride!['visible_width'] as num?)?.toDouble();
      if (w != null && w > 0) return w;
    }

    final frame = getSectionByType('frame');
    if (frame != null) {
      if (frame.couvreJointWidth > 0) return frame.couvreJointWidth;
      if (isIntegratedFrame && (frame.visibleWidth ?? 0) > 0) return frame.visibleWidth!;
    }

    if (selectedSideCover != null) {
      final w1 = selectedSideCover!.couvreJointWidth;
      final w2 = selectedSideCover!.visibleWidth;
      if (w2 > 0) return w2;
      if (w1 > 0) return w1;
    }    return 40.0;
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
    _selectedDbColor = colorData;
    for (var z in zones) {
      z.selectedDbColor = colorData;
    }
    notifyListeners();
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
  Offset? pendingDrawStart; // set on touch-down, committed to drawingStart only after real drag
  double? drawnLeft;
  double? drawnTop;
  bool? _lastIsEmpty;
  double? _lastWidth;
  double? _lastHeight;
  double? _lastDrawnLeft;
  double? _lastDrawnTop;

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
    availableColors = await db.getColorsForProfile(profileId);

    Map<String, dynamic>? selectedColor;
    for (final color in availableColors) {
      if (color['id'] == previousColorId) {
        selectedColor = color;
        break;
      }
    }
    selectedColor ??= availableColors.isNotEmpty ? availableColors.first : null;

    _selectedDbColor = selectedColor;
    for (final zone in zones) {
      zone.selectedDbColor = selectedColor;
    }
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
        return ['شفاف', 'transparent', 'بدون لون', 'clair', 'clear', 'صافي', ''];
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

  double getPriceForFinish(GlassFinish finish, GlassColor color, {double? chosenThickness}) {
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
      bool matchesThickness = chosenThickness == null || thick == chosenThickness;
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
      final interMatch = availableIntercalls.firstWhere(
        (i) =>
            i['thickness'] == thickness ||
            i['name'].toString().contains(thickness.toString()),
      );
      return (interMatch['price_per_sqm'] ?? 0.0).toDouble();
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

      final isLaminatedProduct = t.contains('مورق') || t.contains('laminated') || t.contains('strat') ||
                                 n.contains('مورق') || n.contains('laminated') || n.contains('strat');
      if (!isLaminatedProduct) return false;

      if (thick != thickness) return false;

      // Color mapping: transparent/clair, white/opale/opaque/milky, blue
      bool matchesColor = false;
      if (laminatedColor == 'transparent') {
        matchesColor = c.isEmpty || c.contains('clair') || c.contains('transparent') || n.contains('clair') || n.contains('transparent');
      } else if (laminatedColor == 'white') {
        matchesColor = c.contains('blanc') || c.contains('أبيض') || c.contains('opale') || c.contains('opaque') || n.contains('blanc') || n.contains('أبيض');
      } else if (laminatedColor == 'blue') {
        matchesColor = c.contains('bleu') || c.contains('أزرق') || n.contains('bleu') || n.contains('أزرق');
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
      final isLaminatedProduct = t.contains('مورق') || t.contains('laminated') || t.contains('strat') ||
                                 n.contains('مورق') || n.contains('laminated') || n.contains('strat');
      return isLaminatedProduct && thick == thickness;
    }, orElse: () => <String, dynamic>{});

    if (thickMatch.isNotEmpty) {
      return (thickMatch['price_per_sqm'] ?? 0.0).toDouble();
    }
    return 0.0;
  }

  double getTemperingPricePerSqm(double thickness) {
    // Search in componentOverrides or query directly from database. But since we have componentOverrides,
    // let's look for an accessory named e.g. "تقسية" or "trempe" containing the thickness
    final String thickStr = thickness.toStringAsFixed(0); // e.g. "4" or "6"
    
    // We can check in componentOverrides
    for (var entry in componentOverrides.entries) {
      final name = entry.key.toLowerCase();
      final isTempering = name.contains('تقسية') || name.contains('tempering') || name.contains('trempe');
      if (isTempering && name.contains(thickStr)) {
        final val = entry.value;
        if (val is Map) {
          return ((val['calculated_price'] ?? val['price'] ?? 0.0) as num).toDouble();
        }
      }
    }
    
    // Fallback search in allGlassCache or a default value
    return 0.0;
  }

  double calculateTotalGlassPricePerSqmForZoneGlass(GlassSpecification glass) {
    double price = 0.0;
    if (glass.structure == GlassStructure.simple) {
      final thick = glass.thicknessOuter ?? 4.0;
      if (glass.processingOuter == GlassProcessing.laminated) {
        price = getLaminatedPrice(thick, glass.laminatedColorOuter);
      } else {
        price = getPriceForFinish(glass.finishOuter, glass.colorOuter, chosenThickness: thick);
      }
      
      // Add tempering price if enabled
      if (glass.processingOuter == GlassProcessing.tempered || glass.temperedOuter) {
        price += getTemperingPricePerSqm(thick);
      }
    } else if (glass.structure == GlassStructure.double) {
      final thickInner = glass.thicknessInner ?? 4.0;
      final thickOuter = glass.thicknessOuter ?? 4.0;
      
      double innerPrice = 0.0;
      if (glass.processingInner == GlassProcessing.laminated) {
        innerPrice = getLaminatedPrice(thickInner, glass.laminatedColorInner);
      } else {
        innerPrice = getPriceForFinish(glass.finishInner, glass.colorInner, chosenThickness: thickInner);
      }
      if (glass.processingInner == GlassProcessing.tempered || glass.temperedInner) {
        innerPrice += getTemperingPricePerSqm(thickInner);
      }

      double outerPrice = 0.0;
      if (glass.processingOuter == GlassProcessing.laminated) {
        outerPrice = getLaminatedPrice(thickOuter, glass.laminatedColorOuter);
      } else {
        outerPrice = getPriceForFinish(glass.finishOuter, glass.colorOuter, chosenThickness: thickOuter);
      }
      if (glass.processingOuter == GlassProcessing.tempered || glass.temperedOuter) {
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

        return t == 'panneau' &&
            s == sub.toLowerCase() &&
            c == col.toLowerCase();
      }, orElse: () => <String, dynamic>{});

      if (match.isNotEmpty) {
        price = (match['price_per_sqm'] ?? 0.0).toDouble();
      } else {
        final baseMatch = allGlassCache.firstWhere((g) {
          final t = g['type'].toString().toLowerCase();
          final s = (g['subtype'] ?? '').toString().toLowerCase();
          return t == 'panneau' && s == sub.toLowerCase();
        }, orElse: () => <String, dynamic>{});
        if (baseMatch.isNotEmpty) {
          price = (baseMatch['price_per_sqm'] ?? 0.0).toDouble();
        }
      }
    }
    return price;
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
                existing['is_selling_calculated'] = kb['is_selling_calculated'] ?? 1;
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
            } else if (loadedSlidingSeriesId != null && series.id == loadedSlidingSeriesId) {
              isLoadedSeries = true;
            } else if (activeSeries != null && series.id == activeSeries!.id) {
              isLoadedSeries = true;
            } else if (activeSlidingSeries != null && series.id == activeSlidingSeries!.id) {
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
          isMatchingMode =
              seriesMatchesDrawingMode(series, system, systemMode);
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
                    final alreadyIn = availableSystems
                        .any((sys) => sys.series.any((sr) => sr.id == s.id));
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
                  final alreadyIn = availableSystems
                      .any((sys) => sys.series.any((sr) => sr.id == s.id));
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

  double getSectionThickness(String type, {double fallback = 45.0}) {
    if (activeSeries == null) return fallback;
    if (type.toLowerCase() == 'sash' && sashOverride != null) {
      double t = (sashOverride!['visible_width'] as num?)?.toDouble() ?? 0.0;
      if (t > 0) return t;
      t = (sashOverride!['thickness'] as num?)?.toDouble() ?? 0.0;
      if (t > 0 && t <= 80.0) return t;
    }
    if (type.toLowerCase() == 'sash' && selectedSashCode.isNotEmpty) {
      for (var sec in activeSeries!.sections) {
        if (sec.type.toLowerCase() == 'sash' && sec.code == selectedSashCode) {
          return sec.visibleWidth;
        }
      }
    }
    for (var sec in activeSeries!.sections) {
      if (sec.type.toLowerCase() == type.toLowerCase()) {
        return sec.visibleWidth;
      }
    }
    return fallback;
  }

  AluminumSection? getSectionByType(String type) {
    final series = (systemMode == 'sliding' && activeSlidingSeries != null)
        ? activeSlidingSeries!
        : activeSeries;
    if (series == null) return null;
    final normalizedType = type.toLowerCase();

    AluminumSection? result;
    if (normalizedType == 'sash') {
      final ov = slidingSashOverride ?? sashOverride;
      if (ov != null) result = AluminumSection.fromMap(ov);
    } else if (normalizedType == 'frame') {
      final ov = slidingFrameOverride ?? frameOverride;
      if (ov != null) result = AluminumSection.fromMap(ov);
    }

    if (result == null) {
      if (normalizedType == 'sash' && selectedSashCode.isNotEmpty) {
        for (var sec in series.sections) {
          if (sec.type.toLowerCase() == 'sash' && sec.code == selectedSashCode) {
            result = sec;
            break;
          }
        }
      }
      if (result == null && normalizedType == 'frame' && selectedFrameCode != null) {
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
          if (sec.type.toLowerCase() == normalizedType ||
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
      bool isIntegrated = result.couvreJointWidth > 0 ||
          result.name.toLowerCase().contains('cadre cj') ||
          result.code.toLowerCase().contains('103');
      if (isIntegrated) {
        // Pass 1: look for a non-integrated frame with same thickness (same family/body)
        AluminumSection? sameFamily;
        for (var sec in series.sections) {
          if (sec.type.toLowerCase() == 'frame' || sec.isFrame) {
            bool secIntegrated = sec.couvreJointWidth > 0 ||
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
              bool secIntegrated = sec.couvreJointWidth > 0 ||
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

  double getSectionThicknessByCode(String code, {double fallback = 45.0}) {
    final series = (systemMode == 'sliding' && activeSlidingSeries != null)
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
    final series = (systemMode == 'sliding' && activeSlidingSeries != null)
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
    final bool seriesChanged =
        (activeSeries != null && activeSeries!.id != series.id) ||
        (activeSeries == null && loadedSeriesId == null) ||
        (activeSeries == null && loadedSeriesId != null && loadedSeriesId != series.id);
    activeSeries = series;

    if (systemMode == 'sliding' && activeSlidingSeries == null) {
      activeSlidingSeries = series;
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
      componentOverrides.remove('تقسيم الزجاج (Mullion)');
      componentOverrides.remove('باكيت الزجاج (Parclose)');
      componentOverrides.remove('الباتمو (Batmo)');
      componentOverrides.remove('بوشون باتمو (Bouchon Batmo)');
      componentOverrides.remove('حديد الإطار (Renfort Frame)');
      componentOverrides.remove('حديد الظلفة (Renfort Sash)');
      componentOverrides.remove('حديد الظلفة الخاص بالمفاصل');
      _clearAccessoryOverrides();

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
          final oldPlintheHeight = plintheHeight; // still from old series/overrides
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
              activeSlidingSeries = newSliding;
              slidingFrameOverride = null;
              slidingSashOverride = null;

              var frames = newSliding.sections.where((s) {
                final t = s.type.toLowerCase().trim();
                return t.contains('frame') ||
                    t.contains('cadre') ||
                    t.contains('إطار') ||
                    t.contains('فريم');
              }).toList();
              if (frames.isNotEmpty) {
                slidingFrameOverride = frames.first.toMap();
              }
              var sashes = newSliding.sections.where((s) {
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
          }
        }
      }
    }

    // Set default frame and sash if they are null
    if (frameOverride == null) {
      var frames = series.sections.where((s) {
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
    }

    if (sashOverride == null) {
      var sashes = series.sections.where((s) {
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
      var sideCovers = series.sections.where((s) {
        final t = s.type.toLowerCase().trim();
        return t.contains('side_cover');
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
          where: 'series_id = ? AND (LOWER(type) = ? OR LOWER(type) = ? OR LOWER(type) LIKE ? OR LOWER(name) LIKE ?)',
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
          if (!componentOverrides.containsKey('حديد التقسيم (Renfort Mullion)')) {
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
                where: 'series_id = ? AND (type LIKE ? OR name LIKE ?) AND (type LIKE ? OR name LIKE ? OR type LIKE ? OR name LIKE ?)',
                whereArgs: [series.id, '%renfort%', '%حديد%', '%mullion%', '%mullion%', '%تقسيم%', '%تقسيم%'],
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
          where: 'series_id = ? AND (LOWER(type) = ? OR name LIKE ? OR type LIKE ?)',
          whereArgs: [series.id, 'parclose', '%باكيت%', '%parclose%'],
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
        final isBouchon = t.contains('bouchon') ||
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
            '%bouchon%', '%bouchon%', '%بوشون%', '%بوشون%', '%bochon%', '%bochon%',
            '%batmo%', '%batmo%', '%battement%', '%battement%', '%meneau%', '%meneau%',
            '%باطم%', '%باطم%', '%باطو%', '%باطو%', '%منو%', '%منو%',
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
            if (res.isNotEmpty) {
              Map<String, dynamic>? bestMatch;

              if (overrideName == 'الشرائح (Lames)') {
                // Search for 43 or x
                for (var row in res) {
                  final name = row['name'].toString().toLowerCase();
                  if (name.contains('43') || name.contains('x')) {
                    if (!name.contains('final') && !name.contains('finale') && !name.contains('نهائي')) {
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
              } else if (overrideName == 'الشريحة النهائية (Lame Finale)' || overrideName.contains('نهائ')) {
                // Search for 45
                for (var row in res) {
                  final name = row['name'].toString().toLowerCase();
                  if (name.contains('45')) {
                    bestMatch = row;
                    break;
                  }
                }
              } else if (overrideName == 'المحور (Axe)' || overrideName.contains('محور')) {
                // Determine target diameter
                final bool isMotor = shutterMechanism == 'محرك';
                String targetDiam = '60'; // Default manual axle is 60
                if (isMotor) {
                  final motorComp = componentOverrides['المحرك (Moteur)'];
                  final motorDiamRaw = motorComp?['motor_diameter']?.toString() ?? '';
                  if (motorDiamRaw.isNotEmpty) {
                    final match = RegExp(r'(\d+)').firstMatch(motorDiamRaw);
                    if (match != null) {
                      targetDiam = match.group(1)!;
                    }
                  } else {
                    targetDiam = '40'; // standard motor axle fallback
                  }
                }

                for (var row in res) {
                  final name = row['name'].toString().toLowerCase();
                  final motorDiamField = row['motor_diameter']?.toString() ?? '';
                  final nameMatch = RegExp(r'(\d+)').firstMatch(name);
                  final nameDiam = nameMatch != null ? nameMatch.group(1) : '';

                  if (motorDiamField == targetDiam || nameDiam == targetDiam || name.contains(targetDiam)) {
                    bestMatch = row;
                    break;
                  }
                }
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

              componentOverrides[overrideName] = Map<String, dynamic>.from(
                bestMatch ?? res.first,
              );
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

      final isMotorFetch = shutterMechanism == 'محرك';
      final isCrankFetch =
          shutterMechanism == 'منايفال' ||
          shutterMechanism == 'مانيفال' ||
          shutterMechanism == 'مانيفر';
      if (isMotorFetch) {
        // كيت فولي موتور: DB اسمه "Kit volet Moteur 155" أو "Kit volet moteur 185"
        await assignShutterDefault('كيت فولي موتور (Kit Volet Moteur)', [
          'Kit volet Moteur',
          'Kit volet moteur',
          'kit volet moteur',
          'Kit Moteur',
          'kit moteur',
        ]);
      } else if (isCrankFetch) {
        // كيت فولي مانيفال: DB اسمه "Kit volet manivelle"
        await assignShutterDefault('كيت فولي مانيفر (Kit Volet Manivelle)', [
          'Kit volet manivelle',
          'kit volet manivelle',
          'Kit Volet Manivelle',
        ]);
        // كيت مانيفال: DB اسمه "Kit Manivelle"
        await assignShutterDefault('كيت مانيفر (Kit Manivelle)', [
          'Kit Manivelle',
          'kit manivelle',
          'kit_manivelle',
        ]);
      } else {
        // حزام: DB اسمه "Kit volet 155" أو "Kit volet 185" أو "Kit volet 205"
        // نبحث عن "Kit volet 1" و"Kit volet 2" حتى لا يتطابق مع Moteur أو manivelle
        await assignShutterDefault('كيت فولي (Kit Volet)', [
          'Kit volet 1',
          'Kit volet 2',
          'kit volet 1',
          'kit volet 2',
          'Kit volet 0',
        ]);
      }
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
      return t.contains('parclose') || t.contains('باكيت');
    }).toList();
    if (parcloses.isNotEmpty &&
        !componentOverrides.containsKey('باكيت الزجاج (Parclose)')) {
      componentOverrides['باكيت الزجاج (Parclose)'] = parcloses.first.toMap();
    }

    var mullions = series.sections.where((s) {
      final t = s.type.toLowerCase().trim();
      final n = s.name.toLowerCase().trim();
      if (t.contains('sash') || t.contains('ouvrant') || t.contains('ظلفة')) return false;
      if (n.contains('sash') || n.contains('ouvrant') || n.contains('ظلفة')) return false;
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
      return t == 'bardage' || t.contains('bardage') || t.contains('بارداج') || t.contains('بارداش') ||
             n.contains('bardage') || n.contains('بارداج') || n.contains('بارداش');
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
    updateAllSashThicknesses();
    final covers = availableSideCovers;
    if (covers.isNotEmpty &&
        (selectedSideCover == null ||
            !covers.any((cover) => cover.id == selectedSideCover!.id))) {
      selectedSideCover = covers.first;
    }
    await _loadColorsForProfile(series.profileId);
    availableAccessoryColors = await db.readAccessoryColors();
    
    // فلترة أي اكسسوارات متبقية تنتمي إلى سلسلة أخرى
    if (seriesChanged && d != null) {
      await _filterComponentsByActiveSeries(series, d);
    }
    
    notifyListeners();
  }

  Future<void> setActiveSlidingSeries(AluminumSeries series) async {
    _saveSnapshot();
    final bool seriesChanged =
        (activeSlidingSeries != null && activeSlidingSeries!.id != series.id) ||
        (activeSlidingSeries == null && loadedSlidingSeriesId == null) ||
        (activeSlidingSeries == null && loadedSlidingSeriesId != null && loadedSlidingSeriesId != series.id);
    activeSlidingSeries = series;

    if (seriesChanged) {
      slidingFrameOverride = null;
      slidingSashOverride = null;
      _clearAccessoryOverrides();

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
      var frames = series.sections.where((s) {
        final t = s.type.toLowerCase().trim();
        return t.contains('frame') ||
            t.contains('cadre') ||
            t.contains('إطار') ||
            t.contains('فريم');
      }).toList();

      if (frames.isNotEmpty) {
        slidingFrameOverride = frames.first.toMap();
      }
    }

    if (slidingSashOverride == null) {
      var sashes = series.sections.where((s) {
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

    await _loadColorsForProfile(series.profileId);
    final d = await db.db;
    if (d != null) {
      await _loadAccessoryDefaults(d, series.id);
    }

    notifyListeners();
  }

  Future<void> updateShutterDefaultsIfNeeded() async {
    if (!hasShutter) return;

    // 1. Check for extruded blade auto-switch (applies to all, including tunnel boxes!)
    final blade = componentOverrides['الشرائح (Lames)'];
    if (blade != null) {
      final bladeSubtype = (blade['shutter_subtype']?.toString() ?? '')
          .toLowerCase();
      final bladeName = (blade['name']?.toString() ?? '').toLowerCase();
      if (bladeSubtype == 'extruded' ||
          bladeName.contains('extruded') ||
          bladeName.contains('إكسترودي')) {
        shutterMechanism = 'محرك';
      }
    }

    if (isCaissonTunnel) return;

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

    final database = await db.db;
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

          double? requiredMinBox;
          if (limits.isNotEmpty) {
            for (var limit in limits) {
              final boxSize = (limit['box_size'] as num).toDouble();
              final maxHeight = (limit['max_height'] as num).toDouble();
              if (height <= maxHeight) {
                requiredMinBox = boxSize;
                break;
              }
            }
            if (requiredMinBox == null) {
              requiredMinBox = (limits.last['box_size'] as num).toDouble();
            }
          }

          // Respect manually selected box size if >= requiredMinBox
          double? chosenBoxSize;
          final manualBox = componentOverrides['الصندوق (Caisson)'];
          if (manualBox != null && manualBox['id'] != -999) {
            chosenBoxSize = getLocalComponentSize(manualBox);
          }

          if (requiredMinBox != null) {
            if (chosenBoxSize != null && chosenBoxSize >= requiredMinBox) {
              customShutterBoxHeight = chosenBoxSize;
              shutterHeightWarning = null;
            } else {
              customShutterBoxHeight = requiredMinBox;
              if (height > (limits.last['max_height'] as num).toDouble()) {
                shutterHeightWarning =
                    "هذا الصندوق لا يمكنه أن يحمل هذا الارتفاع من الستار";
              } else {
                shutterHeightWarning = null;
              }
            }
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
    List<String> activeKitKeys = [];
    if (isMotor) {
      activeKitKeys.add('كيت فولي موتور (Kit Volet Moteur)');
      componentOverrides.remove('كيت (Kit)');
      componentOverrides.remove('كيت فولي مانيفر (Kit Volet Manivelle)');
      componentOverrides.remove('كيت مانيفر (Kit Manivelle)');
      componentOverrides.remove('كيت فولي (Kit Volet)');
    } else if (isCrank) {
      activeKitKeys.addAll([
        'كيت فولي مانيفر (Kit Volet Manivelle)',
        'كيت مانيفر (Kit Manivelle)',
      ]);
      componentOverrides.remove('كيت (Kit)');
      componentOverrides.remove('كيت فولي موتور (Kit Volet Moteur)');
      componentOverrides.remove('كيت فولي (Kit Volet)');
    } else {
      // حزام (Sangle)
      activeKitKeys.add('كيت فولي (Kit Volet)');
      componentOverrides.remove('كيت (Kit)');
      componentOverrides.remove('كيت فولي موتور (Kit Volet Moteur)');
      componentOverrides.remove('كيت فولي مانيفر (Kit Volet Manivelle)');
      componentOverrides.remove('كيت مانيفر (Kit Manivelle)');
    }

    Map<String, bool> kitMismatches = {};
    for (var key in activeKitKeys) {
      bool mismatch = false;
      final kit = componentOverrides[key];
      if (kit != null) {
        final sizeStr = getComponentSize(kit);
        if (sizeStr != null) {
          final cleanSize = sizeStr.replaceAll(RegExp(r'[\s.,]'), '').trim();
          if (!isSameSize(cleanSize, targetDigits)) mismatch = true;
        } else {
          mismatch = true;
        }
      } else {
        mismatch = true;
      }
      kitMismatches[key] = mismatch;
    }

    bool hasAnyMismatch = caissonMismatch || kitMismatches.values.any((m) => m);

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
          if (res.isNotEmpty) {
            Map<String, dynamic>? bestMatch;

            if (overrideName == 'الشرائح (Lames)') {
              // Search for 43 or x
              for (var row in res) {
                final name = row['name'].toString().toLowerCase();
                if (name.contains('43') || name.contains('x')) {
                  if (!name.contains('final') && !name.contains('finale') && !name.contains('نهائي')) {
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
            } else if (overrideName == 'الشريحة النهائية (Lame Finale)' || overrideName.contains('نهائ')) {
              // Search for 45
              for (var row in res) {
                final name = row['name'].toString().toLowerCase();
                if (name.contains('45')) {
                  bestMatch = row;
                  break;
                }
              }
            } else if (overrideName == 'المحور (Axe)' || overrideName.contains('محور')) {
              // Determine target diameter
              final bool isMotor = shutterMechanism == 'محرك';
              String targetDiam = '60'; // Default manual axle is 60
              if (isMotor) {
                final motorComp = componentOverrides['المحرك (Moteur)'];
                final motorDiamRaw = motorComp?['motor_diameter']?.toString() ?? '';
                if (motorDiamRaw.isNotEmpty) {
                  final match = RegExp(r'(\d+)').firstMatch(motorDiamRaw);
                  if (match != null) {
                    targetDiam = match.group(1)!;
                  }
                } else {
                  targetDiam = '40'; // standard motor axle fallback
                }
              }

              for (var row in res) {
                final name = row['name'].toString().toLowerCase();
                final motorDiamField = row['motor_diameter']?.toString() ?? '';
                final nameMatch = RegExp(r'(\d+)').firstMatch(name);
                final nameDiam = nameMatch != null ? nameMatch.group(1) : '';

                if (motorDiamField == targetDiam || nameDiam == targetDiam || name.contains(targetDiam)) {
                  bestMatch = row;
                  break;
                }
              }
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

            componentOverrides[overrideName] = Map<String, dynamic>.from(
              bestMatch ?? res.first,
            );
          }
        } catch (e) {
          print('Error updating shutter default for $overrideName: $e');
        }
      }

      if (caissonMismatch || hasAnyMismatch) {
        await assignShutterDefault('الصندوق (Caisson)', [
          'box',
          'صندوق',
          'caisson',
        ]);
      }
      for (var key in activeKitKeys) {
        if (kitMismatches[key] == true || hasAnyMismatch) {
          if (key == 'كيت فولي موتور (Kit Volet Moteur)') {
            await assignShutterDefault(key, [
              'Kit volet Moteur',
              'Kit volet moteur',
              'kit volet moteur',
              'Kit Moteur',
              'kit moteur',
            ]);
          } else if (key == 'كيت فولي مانيفر (Kit Volet Manivelle)') {
            await assignShutterDefault(key, [
              'Kit volet manivelle',
              'kit volet manivelle',
              'Kit Volet Manivelle',
            ]);
          } else if (key == 'كيت مانيفر (Kit Manivelle)') {
            await assignShutterDefault(key, [
              'Kit Manivelle',
              'kit manivelle',
              'kit_manivelle',
            ]);
          } else if (key == 'كيت فولي (Kit Volet)') {
            await assignShutterDefault(key, [
              'Kit volet 1',
              'Kit volet 2',
              'kit volet 1',
              'kit volet 2',
              'Kit volet 0',
            ]);
          }
        }
      }

      // Ensure Lames, Coulisse, Lame Finale, and Axe exist
      if (!componentOverrides.containsKey('الشرائح (Lames)')) {
        await assignShutterDefault('الشرائح (Lames)', ['blade', 'شريح', 'lame']);
      }
      if (!componentOverrides.containsKey('الشريحة النهائية (Lame Finale)')) {
        await assignShutterDefault('الشريحة النهائية (Lame Finale)', ['final_blade', 'lame final', 'نهائي']);
      }
      if (!componentOverrides.containsKey('السكك (Coulisses)')) {
        await assignShutterDefault('السكك (Coulisses)', ['track', 'سك', 'coulisse']);
      }

      // Check if Axe needs to be updated due to mechanism change (e.g. manual 60 vs motor 40/45)
      bool axeMismatch = false;
      final currentAxe = componentOverrides['المحور (Axe)'];
      if (currentAxe != null) {
        final name = currentAxe['name']?.toString()?.toLowerCase() ?? '';
        final motorDiamField = currentAxe['motor_diameter']?.toString() ?? '';
        final nameMatch = RegExp(r'(\d+)').firstMatch(name);
        final nameDiam = nameMatch != null ? nameMatch.group(1) : '';

        final bool isMotor = shutterMechanism == 'محرك';
        if (isMotor) {
          // If motorized, axle should NOT be 60mm
          if (nameDiam == '60' || name.contains('60') || motorDiamField == '60') {
            axeMismatch = true;
          }
        } else {
          // If manual, axle SHOULD be 60mm
          if (nameDiam != '60' && !name.contains('60') && motorDiamField != '60') {
            axeMismatch = true;
          }
        }
      } else {
        axeMismatch = true;
      }

      if (axeMismatch) {
        await assignShutterDefault('المحور (Axe)', ['laxe', 'axe', 'محور']);
      }

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

  void _saveSnapshot() {
    _history.add(
      WindowSnapshot(
        width,
        height,
        hasBottomFrame,
        hasFramePlintheBottom,
        zones.map((z) => z.clone()).toList(),
        Map.from(mullionProfiles),
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
      if (isPVC) {
        zone.usePvcHandleOnAlu = false;
        zone.useClassicHandle = false;
        
        if (zone.content == ZoneContent.doubleSash) {
          // Double sash PVC window: only none/window handle allowed
          zone.lockType = LockType.none;
          zone.useOctoHandle = false;
        } else {
          // Single sash PVC window
          if (zone.isSash105) {
            // PVC Door: clef, condamnation, rouleau
            // Forbid clef and condamnation if shutter is present
            if (hasShutter == true) {
              if (zone.lockType == LockType.clef || zone.lockType == LockType.condamnation) {
                zone.lockType = LockType.none;
              }
            }
            if (zone.lockType == LockType.rouleau && (hasBottomFrame == true || hasShutter == true)) {
              zone.lockType = LockType.none;
            }
            if (zone.lockType != LockType.none &&
                zone.lockType != LockType.clef &&
                zone.lockType != LockType.condamnation &&
                zone.lockType != LockType.rouleau) {
              zone.lockType = LockType.none;
            }
            zone.useOctoHandle = false;
          } else {
            // PVC Window: none or Octo
            if (zone.lockType != LockType.none) {
              zone.lockType = LockType.none;
            }
          }
        }
      } else {
        // Aluminium swing sashes
        zone.useClassicHandle = false;

        if (zone.isSash105) {
          // Thick sash (Door)
          if (zone.content == ZoneContent.doubleSash) {
            // Double sash door: Cremone (none), Key, Bathroom, Maréchal, PVC on Alu
            zone.useOctoHandle = false;
            if (zone.lockType == LockType.point) {
              zone.lockType = LockType.none;
            }
          } else {
            // Single sash door: Cremone (none), Key, Bathroom, Octo, Maréchal, PVC on Alu
            if (zone.lockType == LockType.point) {
              zone.lockType = LockType.none;
            }
          }

          // Forbid clef and condamnation if shutter is present (Aluminium thick sash)
          if (hasShutter == true) {
            if (zone.lockType == LockType.clef || zone.lockType == LockType.condamnation) {
              zone.lockType = LockType.none;
            }
          }

          // Maréchal height and constraint checks
          if (zone.lockType == LockType.rouleau || zone.lockType == LockType.rouleau2000) {
            if (hasBottomFrame == true || hasShutter == true) {
              zone.lockType = LockType.none;
            } else {
              final double doorHeight = zone.boundary.height;
              if (doorHeight < 1250.0) {
                zone.lockType = LockType.none;
              } else if (doorHeight <= 2000.0 && zone.lockType == LockType.rouleau2000) {
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
            // Double sash thin: ONLY Cremone (none)
            zone.lockType = LockType.none;
            zone.useOctoHandle = false;
            zone.usePvcHandleOnAlu = false;
          } else {
            // Single sash thin: Cremone (none), Octo (useOctoHandle), Point Lock (point)
            zone.usePvcHandleOnAlu = false;
            if (zone.lockType != LockType.none && zone.lockType != LockType.point) {
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

  void _rescaleZonesInternal(double oldW, double oldH, double newW, double newH) {
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
    xCoords = xCoords.map((x) => x.clamp(oldInnerLeft, oldInnerRight)).toSet().toList();
    xCoords.sort();

    // Collect and sort unique Y coordinates
    List<double> yCoords = zones
        .expand((z) => [z.boundary.top, z.boundary.bottom])
        .toSet()
        .toList();
    yCoords = yCoords.map((y) => y.clamp(oldInnerTop, oldInnerBottom)).toSet().toList();
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
        hasFramePlintheBottom,
        zones.map((z) => z.clone()).toList(),
        Map.from(mullionProfiles),
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
      ),
    );
    if (_redoHistory.length > 20) _redoHistory.removeAt(0);

    final snap = _history.removeLast();
    width = snap.width;
    height = snap.height;
    hasBottomFrame = snap.hasBottomFrame;
    hasFramePlintheBottom = snap.hasFramePlintheBottom;
    zones = snap.zones;
    mullionProfiles = snap.mullionProfiles;
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
        hasFramePlintheBottom,
        zones.map((z) => z.clone()).toList(),
        Map.from(mullionProfiles),
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
      ),
    );
    if (_history.length > 20) _history.removeAt(0);

    final snap = _redoHistory.removeLast();
    width = snap.width;
    height = snap.height;
    hasBottomFrame = snap.hasBottomFrame;
    hasFramePlintheBottom = snap.hasFramePlintheBottom;
    zones = snap.zones;
    mullionProfiles = snap.mullionProfiles;
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

    selection = SelectionInfo.none;
    activeSubZone = null;
    showZoneMenu = false;
    quantity = 1;
    notifyListeners();
  }

  void updateLayoutMetrics(Size widgetSize) {
    // تجنب إعادة الحساب أثناء الرسم النشط لمنع تحريف الإحداثيات
    if (drawingStart != null) return;

    bool stateChanged = _lastIsEmpty != zones.isEmpty ||
        _lastWidth != width ||
        _lastHeight != height ||
        _lastDrawnLeft != drawnLeft ||
        _lastDrawnTop != drawnTop;

    // تجنب إعادة الحساب إذا لم يتغير الحجم فعلياً (اقتصاداً في الحساب)
    if (lastLayoutSize == widgetSize &&
        !stateChanged &&
        canvasScale > 0 &&
        (canvasDx != 0 || canvasDy != 0)) return;

    lastLayoutSize = widgetSize;
    _lastIsEmpty = zones.isEmpty;
    _lastWidth = width;
    _lastHeight = height;
    _lastDrawnLeft = drawnLeft;
    _lastDrawnTop = drawnTop;

    if (width <= 0 || height <= 0 || zones.isEmpty) {
      double virtualW = 2400.0;
      double virtualH = 1800.0;
      double sX = (widgetSize.width - 60.0) / virtualW;
      double sY = (widgetSize.height - 60.0) / virtualH;
      canvasScale = math.min(sX, sY) * 0.85;
      canvasDx = widgetSize.width / 2 - (virtualW / 2 * canvasScale);
      canvasDy = widgetSize.height / 2 - (virtualH / 2 * canvasScale);
      return;
    }

    final double wallLeft = showWall ? 300.0 : 0.0;
    final double wallRight = showWall ? 300.0 : 0.0;
    final double wallTop = showWall
        ? (hasShutter && !isCaissonTunnel ? (shutterBoxHeight + 100.0) : 150.0)
        : 0.0;
    final double wallBottom = (showWall && showBottomWall) ? 150.0 : 0.0;

    double totalW = width + wallLeft + wallRight;
    double totalH = height + wallTop + wallBottom;

    final padding = 60.0;
    double maxW = math.max(100.0, widgetSize.width - padding);
    double maxH = math.max(100.0, widgetSize.height - padding);

    double sX = maxW / totalW;
    double sY = maxH / totalH;
    canvasScale = math.min(sX, sY) * 0.85;

    double boundsCenterX = (width + wallRight - wallLeft) / 2;
    double boundsCenterY = (height + wallBottom - wallTop) / 2;

    canvasDx = widgetSize.width / 2 - (boundsCenterX * canvasScale);
    canvasDy = widgetSize.height / 2 - (boundsCenterY * canvasScale);
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
    if (isDrawingMode && drawingMode == 'split') {
      for (int i = 0; i < zones.length; i++) {
        for (int j = i + 1; j < zones.length; j++) {
          final z1 = zones[i].boundary;
          final z2 = zones[j].boundary;
          if ((z1.bottom - z2.top).abs() <= mullionT + 2 ||
              (z2.bottom - z1.top).abs() <= mullionT + 2) {
            double yCenter = (z1.bottom + z2.top) / 2;
            if ((z2.bottom - z1.top).abs() <= mullionT + 2) {
              yCenter = (z2.bottom + z1.top) / 2;
            }
            double overlapLeft = math.max(z1.left, z2.left);
            double overlapRight = math.min(z1.right, z2.right);
            if (overlapLeft < overlapRight &&
                pos.dx >= overlapLeft &&
                pos.dx <= overlapRight &&
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
          if ((z1.right - z2.left).abs() <= mullionT + 2 ||
              (z2.right - z1.left).abs() <= mullionT + 2) {
            double xCenter = (z1.right + z2.left) / 2;
            if ((z2.right - z1.left).abs() <= mullionT + 2) {
              xCenter = (z2.right + z1.left) / 2;
            }
            double overlapTop = math.max(z1.top, z2.top);
            double overlapBottom = math.min(z1.bottom, z2.bottom);
            if (overlapTop < overlapBottom &&
                pos.dy >= overlapTop &&
                pos.dy <= overlapBottom &&
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
        if (isDrawingMode && drawingMode == 'split' &&
            (z.content == ZoneContent.singleSash ||
                z.content == ZoneContent.doubleSash)) {
          final sashT = z.sashThickness ?? _calculateSashThickness(z.isSash105);
          final isDouble = z.content == ZoneContent.doubleSash;

          SelectionInfo? checkSashDivisions(Rect sashRect, bool isRight) {
            final glassR = getSafeGlassRect(sashRect, sashT);
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

            final double hitThreshold = 25.0;

            for (int i = 0; i < finalHPos.length; i++) {
              double y = glassR.top + glassR.height * finalHPos[i];
              if ((pos.dy - y).abs() < hitThreshold &&
                  pos.dx >= glassR.left &&
                  pos.dx <= glassR.right) {
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
                  pos.dy >= glassR.top &&
                  pos.dy <= glassR.bottom) {
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
        }
        selection = SelectionInfo(type: SelectionType.zone, zoneId: z.id);
        bool isDouble = z.content == ZoneContent.doubleSash;
        bool isSingle = z.content == ZoneContent.singleSash;
        bool isSliding = z.content == ZoneContent.slidingSash;
        if (isSliding) {
          showZoneMenu = isLongPress ? false : true;
          final count = z.slidingSashesCount;

          double getSlidingSectionWidth(String typeName, String fallbackName, double defaultVal) {
            final series = activeSlidingSeries ?? activeSeries;
            if (series == null) return defaultVal;
            final String tName = typeName.toLowerCase();
            String? altType;
            if (tName == 'traverse') {
              altType = 'sash_traverse';
            } else if (tName == 'chicane' || tName == 'central' || tName == 'centrale') {
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

          final double chicaneT = getSlidingSectionWidth('chicane', 'centrale', 45.0);
          final double sashWidth = (z.boundary.width + (count - 1) * chicaneT) / count;

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
                Rect sashRect = Rect.fromLTRB(left, z.boundary.top, left + sashWidth, z.boundary.bottom);
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
        final updatedCellGlass = Map<String, GlassSpecification>.from(zone.cellGlassSpec);
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
          final updatedCellGlass2 = Map<String, GlassSpecification>.from(zone.cellGlassSpec);
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

      bool is105 = _determineIsSash105FromSashOverride();
      zone.isSash105 = is105;
      zone.sashThickness = _calculateSashThickness(is105);
      if (content == ZoneContent.doubleSash ||
          content == ZoneContent.singleSash) {
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
      if (z.content == ZoneContent.doubleSash) {
        final leftX = r.left + (r.width * z.doubleSashRatio) / 2;
        if (Rect.fromCenter(
          center: Offset(leftX, r.top + 20),
          width: 120,
          height: 80,
        ).contains(pos)) {
          return InnerDimensionHit(z.id, true, isDoubleSashLeft: true);
        }

        final rightX =
            r.left +
            (r.width * z.doubleSashRatio) +
            (r.width * (1.0 - z.doubleSashRatio)) / 2;
        if (Rect.fromCenter(
          center: Offset(rightX, r.top + 20),
          width: 120,
          height: 80,
        ).contains(pos)) {
          return InnerDimensionHit(z.id, true, isDoubleSashRight: true);
        }
      } else {
        if (!isFullWidth && z.content != ZoneContent.singleSash && z.content != ZoneContent.slidingSash) {
          if (Rect.fromCenter(
            center: Offset(r.center.dx, r.top + 20),
            width: 150,
            height: 80,
          ).contains(pos)) {
            return InnerDimensionHit(z.id, true);
          }
        }
      }
      if (!isFullHeight && z.content != ZoneContent.singleSash && z.content != ZoneContent.doubleSash && z.content != ZoneContent.slidingSash) {
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
    _rescaleZonesInternal(width, height, newW, newH);
    width = newW;
    height = newH;
    lastLayoutSize = null; // أجبر إعادة حساب canvasScale عند تغيير الحجم
    updateShutterDefaultsIfNeeded();
    notifyListeners();
  }

  double getMaxAllowedInnerSize(String zoneId, bool isWidth) {
    final zIdx = zones.indexWhere((z) => z.id == zoneId);
    if (zIdx == -1) return 0;
    final r = zones[zIdx].boundary;
    final sep = mullionThickness / 2;
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

  void _moveInternalBoundaryX(double oldX, double diff) {
    final sep = mullionThickness / 2;
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
  }

  void _moveInternalBoundaryY(double oldY, double diff) {
    final sep = mullionThickness / 2;
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
  }

  void removeSashDivisions() {
    if (selectedZone == null) return;
    _saveSnapshot();
    final zone = selectedZone!;
    if (activeSubZone != null && activeSubZone!.startsWith('right')) {
      zone.rightInnerH = 0;
      zone.rightInnerV = 0;
      zone.rightPrimaryDivisionAxis = null;
      zone.cellIsPanel.removeWhere((key, value) => key.startsWith('right'));
    } else if (activeSubZone != null && activeSubZone!.startsWith('left')) {
      zone.innerH = 0;
      zone.innerV = 0;
      zone.primaryDivisionAxis = null;
      zone.cellIsPanel.removeWhere((key, value) => key.startsWith('left'));
    } else {
      zone.innerH = 0;
      zone.innerV = 0;
      zone.rightInnerH = 0;
      zone.rightInnerV = 0;
      zone.primaryDivisionAxis = null;
      zone.rightPrimaryDivisionAxis = null;
      zone.cellIsPanel.clear();
    }
    notifyListeners();
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
        final isThick = n.contains('porte') ||
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
        final isThin = n.contains('fenetre') ||
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
            price = await db.getSectionPrice(
              targetFrame.id,
              selectedDbColor!['id'],
            );
          }
          frameMap['calculated_price'] = price;
          frameOverride = frameMap;
          updateProfileThickness();
        }
      }
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

  bool _determineIsSash105FromSashOverride() {
    if (sashOverride == null) return false;
    
    // If it's PVC, fallback to standard name checks because PVC uses different series naming logic
    if (isPVC) {
      final code = sashOverride!['code']?.toString().toLowerCase() ?? '';
      final name = sashOverride!['name']?.toString().toLowerCase() ?? '';
      if (code.contains('104') || name.contains('104')) {
        return false;
      }
      if (code.contains('105') ||
          code.contains('porte') ||
          code.contains('ouvr') ||
          name.contains('105') ||
          name.contains('porte') ||
          name.contains('ouvr') ||
          name.contains('بورت')) {
        return true;
      }
      return false;
    }

    // For Aluminium: Compare visible widths of all sashes in the active series
    final double currentWidth = (sashOverride!['visible_width'] as num?)?.toDouble() ?? 0.0;
    
    final series = activeSeries;
    if (series != null) {
      // Find all sash/ouvrant sections in this series
      final sashSections = series.sections.where((s) {
        final t = s.type.toLowerCase().trim();
        final n = s.name.toLowerCase().trim();
        return t.contains('sash') ||
            t.contains('ouvrant') ||
            t.contains('ضلفة') ||
            t.contains('ساش') ||
            n.contains('sash') ||
            n.contains('ouvrant') ||
            n.contains('ضلفة') ||
            n.contains('ساش');
      }).toList();

      if (sashSections.isNotEmpty) {
        double maxVisibleWidth = 0.0;
        double minVisibleWidth = 999999.0;
        for (var s in sashSections) {
          final w = (s.visibleWidth as num?)?.toDouble() ?? 0.0;
          if (w > maxVisibleWidth) maxVisibleWidth = w;
          if (w < minVisibleWidth) minVisibleWidth = w;
        }

        // If we have a range of widths:
        if (maxVisibleWidth > minVisibleWidth) {
          // If the selected sash's width is closer to the max width, it is the thick sash
          if ((currentWidth - maxVisibleWidth).abs() < (currentWidth - minVisibleWidth).abs()) {
            return true;
          } else {
            return false;
          }
        }
      }
    }

    // Fallback: If no other sashes found or widths are same, use name check or absolute threshold
    if (currentWidth >= 90.0) {
      return true;
    }
    
    // Fallback to name check
    final code = sashOverride!['code']?.toString().toLowerCase() ?? '';
    final name = sashOverride!['name']?.toString().toLowerCase() ?? '';
    if (code.contains('104') || name.contains('104')) {
      return false;
    }
    if (code.contains('105') ||
        code.contains('porte') ||
        code.contains('ouvr') ||
        name.contains('105') ||
        name.contains('porte') ||
        name.contains('ouvr') ||
        name.contains('بورت')) {
      return true;
    }
    return false;
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

  void updateProfileThickness() {
    double oldThickness = profileThickness;

    if (frameOverride != null) {
      double t = (frameOverride!['visible_width'] as num?)?.toDouble() ?? 0.0;
      if (t > 0) {
        profileThickness = t;
      } else {
        profileThickness =
            (frameOverride!['thickness'] as num?)?.toDouble() ??
            profileThickness;
      }
    } else if (activeSeries != null && activeSeries!.sections.isNotEmpty) {
      final frames = activeSeries!.sections
          .where((s) => s.isFrame || s.type.toLowerCase() == 'frame')
          .toList();
      if (frames.isNotEmpty) {
        AluminumSection targetFrame;
        if (selectedFrameCode != null && selectedFrameCode!.isNotEmpty) {
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
      for (var z in zones) {
        z.boundary = Rect.fromLTRB(
          z.boundary.left == oldThickness ? profileThickness : z.boundary.left,
          z.boundary.top == (topOffset + oldThickness)
              ? (topOffset + profileThickness)
              : z.boundary.top,
          z.boundary.right == width - oldThickness
              ? width - profileThickness
              : z.boundary.right,
          z.boundary.bottom == height - oldThickness
              ? height - profileThickness
              : z.boundary.bottom,
        );
      }
    }
  }

  void toggleShutterSide(String side) {
    _saveSnapshot();
    if (removedShutterSides.contains(side)) {
      removedShutterSides.remove(side);
    } else {
      removedShutterSides.add(side);
    }
    notifyListeners();
  }

  void setSlidingSashesCount(int count) {
    if (selectedZone == null) return;
    _saveSnapshot();
    selectedZone!.slidingSashesCount = count.clamp(2, 4).toInt();
    notifyListeners();
  }

  void setSelectedZoneSlidingSashes(int count) {
    if (hasArchOrSlant) return;
    final zone = selectedZone;
    if (zone == null) return;
    _saveSnapshot();
    zone.content = ZoneContent.slidingSash;
    zone.slidingSashesCount = count.clamp(2, 4).toInt();
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
    int? panneauProductId,
    double? thicknessOuter,
    double? thicknessInner,
    String? laminatedColorOuter,
    String? laminatedColorInner,
    bool? temperedOuter,
    bool? temperedInner,
  }) async {
    if (selectedZone == null) return;
    _saveSnapshot();

    // Automatic parclose switching logic
    if (structure != null) {
      final currentParclose = componentOverrides['باكيت الزجاج (Parclose)'];
      if (currentParclose != null) {
        final dbInstance = SqlDatabase();
        final activeId = activeSeries?.id;
        if (structure == GlassStructure.double) {
          final double maxG =
              (currentParclose['max_glass_thickness'] as num?)?.toDouble() ??
              0.0;
          if (maxG <= 10.0) {
            final int? linkedId =
                currentParclose['linked_parclose_double_id'] as int?;
            if (linkedId != null && linkedId > 0) {
               final d = await dbInstance.db;
               final res = await d?.query(
                'Sections',
                where: 'id = ?',
                whereArgs: [linkedId],
              );
              if (res != null && res.isNotEmpty) {
                final newP = Map<String, dynamic>.from(res.first);
                final price = await dbInstance.getSectionPrice(
                  linkedId,
                  selectedDbColor?['id'],
                );
                newP['calculated_price'] = price;
                componentOverrides['باكيت الزجاج (Parclose)'] = newP;
              }
            } else {
               final d = await dbInstance.db;
               final res = await d?.query(
                'Sections',
                where:
                    'series_id = ? AND (type = ? OR type LIKE ? OR name LIKE ?) AND max_glass_thickness > 10.0',
                whereArgs: [activeId, 'parclose', '%parclose%', '%باكيت%'],
                limit: 1,
              );
              if (res != null && res.isNotEmpty) {
                final newP = Map<String, dynamic>.from(res.first);
                final price = await dbInstance.getSectionPrice(
                  newP['id'] as int,
                  selectedDbColor?['id'],
                );
                newP['calculated_price'] = price;
                componentOverrides['باكيت الزجاج (Parclose)'] = newP;
              }
            }
          }
        } else if (structure == GlassStructure.simple) {
          final double maxG =
              (currentParclose['max_glass_thickness'] as num?)?.toDouble() ??
              0.0;
          if (maxG > 10.0) {
            final d = await dbInstance.db;
            final res = await d?.query(
              'Sections',
              where:
                  'series_id = ? AND (type = ? OR type LIKE ? OR name LIKE ?) AND max_glass_thickness <= 10.0',
              whereArgs: [activeId, 'parclose', '%parclose%', '%باكيت%'],
              limit: 1,
            );
            if (res != null && res.isNotEmpty) {
              final newP = Map<String, dynamic>.from(res.first);
              final price = await dbInstance.getSectionPrice(
                newP['id'] as int,
                selectedDbColor?['id'],
              );
              newP['calculated_price'] = price;
              componentOverrides['باكيت الزجاج (Parclose)'] = newP;
            }
          }
        }
      }
    }

    final targetCellKey = activeSubZone;
    final baseSpec = (targetCellKey != null && targetCellKey.isNotEmpty)
        ? selectedZone!.getGlassForCell(targetCellKey)
        : selectedZone!.glass;

    final targetStructure = structure ?? baseSpec.structure;
    double? resolvedThicknessOuter = thicknessOuter;
    double? resolvedThicknessInner = thicknessInner;

    if (targetStructure == GlassStructure.double) {
      resolvedThicknessOuter ??= baseSpec.thicknessOuter ?? getThicknessForFinish(
        finishOuter ?? baseSpec.finishOuter,
        colorOuter ?? baseSpec.colorOuter,
      );
      resolvedThicknessInner ??= baseSpec.thicknessInner ?? getThicknessForFinish(
        finishInner ?? baseSpec.finishInner,
        colorInner ?? baseSpec.colorInner,
      );
    } else {
      resolvedThicknessOuter ??= baseSpec.thicknessOuter ?? getThicknessForFinish(
        finishOuter ?? baseSpec.finishOuter,
        colorOuter ?? baseSpec.colorOuter,
      );
    }

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
        hasGas: hasGas,
        intercallThickness: intercallThickness,
        panneauSubtype: panneauSubtype,
        panneauColor: panneauColor,
        isVerticalBardage: isVerticalBardage,
        panneauProductId: panneauProductId,
        thicknessOuter: resolvedThicknessOuter,
        thicknessInner: resolvedThicknessInner,
        laminatedColorOuter: laminatedColorOuter,
        laminatedColorInner: laminatedColorInner,
      );
      final updatedCellGlass = Map<String, GlassSpecification>.from(selectedZone!.cellGlassSpec);
      updatedCellGlass[targetCellKey] = updatedSpec;
      selectedZone!.cellGlassSpec = updatedCellGlass;
    } else {
      selectedZone!.glass = selectedZone!.glass.copyWith(
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
        panneauSubtype: panneauSubtype,
        panneauColor: panneauColor,
        isVerticalBardage: isVerticalBardage,
        panneauProductId: panneauProductId,
        thicknessOuter: resolvedThicknessOuter,
        thicknessInner: resolvedThicknessInner,
        laminatedColorOuter: laminatedColorOuter,
        laminatedColorInner: laminatedColorInner,
      );
      if (selectedZone!.cellGlassSpec.isNotEmpty) {
        final updatedCellGlass = <String, GlassSpecification>{};
        selectedZone!.cellGlassSpec.forEach((key, val) {
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
            hasGas: hasGas,
            intercallThickness: intercallThickness,
            panneauSubtype: panneauSubtype,
            panneauColor: panneauColor,
            isVerticalBardage: isVerticalBardage,
            panneauProductId: panneauProductId,
            thicknessOuter: resolvedThicknessOuter,
            thicknessInner: resolvedThicknessInner,
            laminatedColorOuter: laminatedColorOuter,
            laminatedColorInner: laminatedColorInner,
          );
        });
        selectedZone!.cellGlassSpec = updatedCellGlass;
      }
      WindowZone.globalDefaultGlass = selectedZone!.glass;
    }
    await updateGlassGasket();
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
      maxGlass = (activeSashMap['max_glass_thickness'] as num?)?.toDouble() ?? 0.0;
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

    final double targetThickness = gap; // Gap is exactly the joint thickness needed!

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

  /// فلترة الاكسسوارات والبروفيلات بناءً على السلسلة الحالية
  /// تقوم بحذف أي اكسسوار أو بروفيل لا ينتمي إلى السلسلة الحالية أو ليس له scope = "Global"
  Future<void> _filterComponentsByActiveSeries(AluminumSeries series, dynamic db) async {
    if (db == null || activeSeries == null) return;
    
    final seriesId = series.id;
    final keysToCheck = List<String>.from(componentOverrides.keys);
    
    for (final key in keysToCheck) {
      final component = componentOverrides[key];
      if (component == null) continue;
      
      // تجاهل المكونات التي تأتي من البيانات المحلية وليست من قاعدة البيانات
      if (component['id'] == null) continue;
      
      // تجاهل الأقسام (Sections)، نتعامل فقط مع الاكسسوارات
      final tableToCheck = component.containsKey('series_id') || 
                          component.containsKey('series_ids') ||
                          component.containsKey('scope') ? 'Accessories' : null;
      
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
          final componentScope = dbComponent['scope']?.toString() ?? '';
          final componentSeriesIds = dbComponent['series_ids']?.toString() ?? '';
          
          // التحقق من أن المكون ينتمي إلى السلسلة الحالية أو له scope = "Global"
          bool belongsToCurrentSeries = false;
          
          // إذا كان series_id متطابقاً
          if (componentSeriesId == seriesId) {
            belongsToCurrentSeries = true;
          }
          // أو إذا كان scope = "Global"
          else if (componentScope == 'Global') {
            belongsToCurrentSeries = true;
          }
          // أو إذا كان series_ids يحتوي على series_id الحالي
          else if (componentSeriesIds.isNotEmpty) {
            final ids = componentSeriesIds.split(',')
                .map((s) => s.trim())
                .where((s) => s.isNotEmpty)
                .toList();
            if (ids.contains(seriesId.toString())) {
              belongsToCurrentSeries = true;
            }
          }
          
          if (!belongsToCurrentSeries) {
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
      sName = (activeSlidingSeries?.name ?? activeSeries?.name ?? '').toLowerCase();
    }
    final bool isTPRSeries = sName.contains('tpr') || sName.contains('tpi') || sName.contains('67000');

    Future<void> loadAccessory(String key, List<String> searchPatterns) async {
      if (componentOverrides.containsKey(key)) return;

      bool isAccessoryValid(Map<String, dynamic> acc) {
        final n = acc['name'].toString().toLowerCase();
        final ty = (acc['type'] ?? '').toString().toLowerCase();

        // 1. Material Exclusions
        if (matType == 'PVC') {
          if (n.contains('aluminium') || n.contains('aluminum') || n.contains('alu') || n.contains('ألمنيوم') ||
              ty.contains('aluminium') || ty.contains('aluminum') || ty.contains('alu') || ty.contains('ألمنيوم')) {
            return false;
          }
        } else { // Aluminium
          if (n.contains('pvc') || ty.contains('pvc') ||
              n.contains('clan') || ty.contains('clan') ||
              n.contains('clane') || ty.contains('clane') ||
              n.contains('كلان') || ty.contains('كلان')) {
            return false;
          }
        }

        // 2. Series Name Exclusions
        if (sName.isNotEmpty) {
          if (sName.contains('67000') || sName.contains('67')) {
            if (n.contains('76000') || n.contains('76') || ty.contains('76000') || ty.contains('76') ||
                n.contains('60000') || n.contains('60') || ty.contains('60000') || ty.contains('60') ||
                n.contains('52000') || n.contains('52') || ty.contains('52000') || ty.contains('52') ||
                n.contains('45000') || n.contains('45') || ty.contains('45000') || ty.contains('45')) {
              return false;
            }
          } else if (sName.contains('76000') || sName.contains('76')) {
            if (n.contains('67000') || n.contains('67') || ty.contains('67000') || ty.contains('67') ||
                n.contains('60000') || n.contains('60') || ty.contains('60000') || ty.contains('60') ||
                n.contains('52000') || n.contains('52') || ty.contains('52000') || ty.contains('52') ||
                n.contains('45000') || n.contains('45') || ty.contains('45000') || ty.contains('45')) {
              return false;
            }
          } else if (sName.contains('60000') || sName.contains('60')) {
            if (n.contains('67000') || n.contains('67') || ty.contains('67000') || ty.contains('67') ||
                n.contains('76000') || n.contains('76') || ty.contains('76000') || ty.contains('76') ||
                n.contains('52000') || n.contains('52') || ty.contains('52000') || ty.contains('52') ||
                n.contains('45000') || n.contains('45') || ty.contains('45000') || ty.contains('45')) {
              return false;
            }
          }

          // 3. System Mode Exclusions
          final isSliding = systemMode == 'sliding';
          if (isSliding) {
            if (n.contains('paumelle') || ty.contains('paumelle') ||
                n.contains('mifsal') || ty.contains('mifsal') ||
                n.contains('مفاصل') || ty.contains('مفاصل') ||
                n.contains('مفصل') || ty.contains('مفصل') ||
                n.contains('system ob') || ty.contains('system ob') ||
                n.contains('demi system ob') || ty.contains('demi system ob') ||
                n.contains('verrou central') || ty.contains('verrou central') ||
                n.contains('gache simple') || ty.contains('gache simple') ||
                n.contains('gache double') || ty.contains('gache double') ||
                n.contains('قاش دوبل') || ty.contains('قاش دوبل') ||
                n.contains('قاش سامبل') || ty.contains('قاش سامبل') ||
                n.contains('فتح') || ty.contains('فتح') ||
                n.contains('ouvrant') || ty.contains('ouvrant')) {
              return false;
            }
          } else {
            if (n.contains('couliss') || ty.contains('couliss') ||
                n.contains('roulette') || ty.contains('roulette') ||
                n.contains('عجلات') || ty.contains('عجلات') ||
                n.contains('منزلق') || ty.contains('منزلق')) {
              return false;
            }
          }
        }

        // 4. Kit Clamp/Clan Exclusions (Exclude clamp from kit matching, and vice versa)
        final isKitKey = key.toLowerCase().contains('kit') || key.contains('كيت');
        final isClampKey = key.toLowerCase().contains('clamp') || key.toLowerCase().contains('clam') || key.contains('كلامب') || key.contains('كلام') || key.contains('كلان');

        final hasKitName = n.contains('kit') || ty.contains('kit') || n.contains('كيت') || ty.contains('كيت');
        final hasClampName = n.contains('clamp') || n.contains('clam') || ty.contains('clamp') || ty.contains('clam') || n.contains('كلامب') || n.contains('كلام') || n.contains('كلان') || ty.contains('كلامب') || ty.contains('كلام') || ty.contains('كلان') || n.contains('clan') || ty.contains('clan');

        if (isKitKey && hasClampName) return false;
        if (isClampKey && hasKitName) return false;

        return true;
      }

      String kitClampExclude = '';
      if (key.toLowerCase().contains('kit') || key.contains('كيت')) {
        kitClampExclude = " AND (LOWER(name) NOT LIKE '%clamp%' AND LOWER(name) NOT LIKE '%clam%' AND LOWER(name) NOT LIKE '%clomp%' AND LOWER(name) NOT LIKE '%clom%' AND name NOT LIKE '%كلامب%' AND name NOT LIKE '%كلام%' AND name NOT LIKE '%كلان%' AND LOWER(type) NOT LIKE '%clamp%' AND LOWER(type) NOT LIKE '%clam%' AND LOWER(type) NOT LIKE '%clomp%' AND LOWER(type) NOT LIKE '%clom%' AND type NOT LIKE '%كلامب%' AND type NOT LIKE '%كلام%' AND type NOT LIKE '%كلان%')";
      } else if (key.toLowerCase().contains('clamp') || key.toLowerCase().contains('clam') || key.contains('كلامب') || key.contains('كلام') || key.contains('كلان')) {
        kitClampExclude = " AND (LOWER(name) NOT LIKE '%kit%' AND name NOT LIKE '%كيت%' AND LOWER(type) NOT LIKE '%kit%' AND type NOT LIKE '%كيت%')";
      }

      String? exactTypeOverride;
      if (isTPRSeries) {
        if (key == 'المقبض (Handle)' || key == 'مقبض نافذة (Poignée Fenêtre)') {
          exactTypeOverride = 'Poignée TPR';
        } else if (key == 'إسبانيوليت (Espagnolette)' || key == 'اسبانيولات المنزلق (Espagnolette)') {
          exactTypeOverride = 'Espagnolette TPR';
        }
      }

      // فلتر نوع المادة متطابق تماماً مع ProfileSelectorDialog
      String matFilter = '';
      if (matType == 'PVC') {
        matFilter = " AND (LOWER(material_type) = 'pvc' OR LOWER(material_type) = 'both')";
      } else {
        matFilter = " AND (LOWER(material_type) = 'aluminium' OR LOWER(material_type) = 'aluminum' OR LOWER(material_type) = 'both' OR material_type IS NULL OR material_type = '')$kitClampExclude";
      }

      // فلتر السلاسل متطابق تماماً مع ProfileSelectorDialog
      String seriesFilter = ' AND ('
          'series_id = ? '
          'OR (series_ids IS NOT NULL AND series_ids != \'\' AND \',\' || series_ids || \',\' LIKE ?) '
          'OR ((series_id IS NULL OR series_id = 0) AND (series_ids IS NULL OR series_ids = \'\'))'
          ')';

      final String orderBy = 'CASE WHEN series_id = $seriesId OR (series_ids IS NOT NULL AND series_ids != \'\' AND \',\' || series_ids || \',\' LIKE \'%,$seriesId,%\') THEN 0 ELSE 1 END ASC, id ASC';

      List<Map<String, dynamic>> res = [];

      // 1. إذا كانت السلسلة TPR، جرب البحث المرن عن TPR أولاً لضمان انتقاء إكسسوار TPR الصحيح
      List<String> tprPatterns = [];
      if (isTPRSeries) {
        if (key == 'إسبانيوليت (Espagnolette)' || key == 'اسبانيولات المنزلق (Espagnolette)') {
          tprPatterns = ['%tpr%espagnolette%', '%espagnolette%tpr%', '%tpr%سبانيوليت%', '%سبانيوليت%tpr%', '%tpr%إسبانيوليت%', '%إسبانيوليت%tpr%'];
        } else if (key == 'المقبض (Handle)' || key == 'مقبض نافذة (Poignée Fenêtre)') {
          tprPatterns = ['%tpr%poign%', '%poign%tpr%', '%tpr%مقبض%', '%مقبض%tpr%', '%tpr%handle%', '%handle%tpr%'];
        }
      }

      if (tprPatterns.isNotEmpty) {
        String tprClause = tprPatterns.map((_) => 'name LIKE ? OR type LIKE ?').join(' OR ');
        String tprWhereClause = '($tprClause) $seriesFilter $matFilter';
        List<dynamic> tprArgs = [];
        for (var pattern in tprPatterns) {
          tprArgs.addAll([pattern, pattern]);
        }
        tprArgs.addAll([
          seriesId,
          '%,' + seriesId.toString() + ',%',
        ]);
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
            : searchPatterns.map((_) => 'name LIKE ? OR type LIKE ?').join(' OR ');

        String whereClause = '($nameClause) $seriesFilter $matFilter';
        List<dynamic> args = [];
        if (exactTypeOverride != null) {
          args.add(exactTypeOverride.toLowerCase());
        } else {
          for (var pattern in searchPatterns) {
            args.addAll([pattern, pattern]);
          }
        }
        args.addAll([
          seriesId,
          '%,' + seriesId.toString() + ',%',
        ]);

        final rawRows = await d.query(
          'Accessories',
          where: whereClause,
          whereArgs: args,
          orderBy: orderBy,
        );
        res = rawRows.where(isAccessoryValid).toList();

        // Fallback: If exact type search for TPR returned empty, retry with loose patterns
        if (res.isEmpty && exactTypeOverride != null) {
          String nameClauseLoose = searchPatterns.map((_) => 'name LIKE ? OR type LIKE ?').join(' OR ');
          String fallbackWhereClause = '($nameClauseLoose) $seriesFilter $matFilter';
          List<dynamic> fallbackArgs = [];
          for (var pattern in searchPatterns) {
            fallbackArgs.addAll([pattern, pattern]);
          }
          fallbackArgs.addAll([
            seriesId,
            '%,' + seriesId.toString() + ',%',
          ]);

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
        final m = Map<String, dynamic>.from(res.first);
        m['calculated_price'] = (m['price_dzd'] ?? m['price'] ?? 0.0)
            .toDouble();
        componentOverrides[key] = m;
      }
    }

    // Load defaults
    await loadAccessory('قاش دوبل (Gache Double Ouvrant)', [
      '%قاش دوبل%',
      '%gache double%',
    ]);
    await loadAccessory('إسبانيوليت (Espagnolette)', ['%سبانيوليت%', '%espagnolette%']);
    await loadAccessory('المفاصل (Hinges)', ['%مفاصل%', '%paumelle%']);
    await loadAccessory('الفيرو (Verrou)', ['%فيرو%', '%verrou%']);
    await loadAccessory('المقبض (Handle)', ['%مقبض%', '%poignée fenêtre%', '%poignée fenetre%', '%poignee fenetre%', '%handle%']);
    await loadAccessory('مقبض نافذة (Poignée Fenêtre)', ['%مقبض%', '%poignée fenêtre%', '%poignée fenetre%', '%poignee fenetre%', '%handle%']);
    await loadAccessory('مقبض أوكتو (Octo)', ['%أوكتو%', '%اوكتو%', '%octo%']);
    await loadAccessory('مقبض نافذة بي في سي (Poignée Fenêtre PVC)', ['%مقبض نافذة بي في سي%', '%poignée fenêtre pvc%', '%poignee fenetre pvc%']);
    await loadAccessory('كومباس (Compas)', ['%كومباس%', '%compas%']);
    await loadAccessory('عجلات المنزلق (Roulettes)', ['%رول%', '%roulette%']);
    await loadAccessory('اسبانيولات المنزلق (Espagnolette)', [
      '%اسبانيوليت%',
      '%espagnolette%',
    ]);
    await loadAccessory('كاش كوليسون (Gache coulissant)', [
      '%كاش كوليسون%',
      '%cache coulisson%',
      '%collissante%',
      '%كوليسون|جودة%',
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
    if (!componentOverrides.containsKey('مقبض كبير ماريشال 1.25 متر (Poignée Maréchal 1.25m)')) {
      await loadAccessory('مقبض كبير ماريشال 1.25 متر (Poignée Maréchal 1.25m)', [
        '%ماريشال%',
        '%marechal%',
        '%maréchal%',
      ]);
    }

    await loadAccessory('مقبض كبير ماريشال 2 متر (Poignée Maréchal 2m)', [
      '%ماريشال%2%',
      '%ماريشال%200%',
      '%marechal%2%',
      '%marechal%200%',
      '%maréchal%2%',
      '%maréchal%200%',
    ]);
    if (!componentOverrides.containsKey('مقبض كبير ماريشال 2 متر (Poignée Maréchal 2m)')) {
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
    await loadAccessory('قاش (Gache)', [
      '%قاش%',
      '%gâche%',
      '%gache%',
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
      if (!componentOverrides.containsKey('جوان بروس للظلفة (Joint Brosse Sash)')) {
        componentOverrides['جوان بروس للظلفة (Joint Brosse Sash)'] = oldVal;
      }
      if (!componentOverrides.containsKey('جوان بروس للستار (Joint Brosse Shutter)')) {
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
            where: '(name LIKE ? OR type LIKE ? OR name LIKE ? OR type LIKE ?) AND (series_id = ? OR (series_ids IS NOT NULL AND \',\' || series_ids || \',\' LIKE ?))',
            whereArgs: [
              '%brosse%', '%brosse%', '%بروس%', '%بروس%',
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
              whereArgs: ['%brosse%tpr%', '%brosse%tpr%', '%بروس%tpr%', '%بروس%tpr%'],
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
      final GlassSpecification currentSpec = selectedZone!.getGlassForCell(targetCellKey);
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
      final updatedCellGlass = Map<String, GlassSpecification>.from(selectedZone!.cellGlassSpec);
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

  void startDrawing(Offset pos) {
    // Auto-detect mode: if start is inside the window → split, otherwise → add_frame
    if (zones.isNotEmpty) {
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
          ),
        );
      }
    }
    if (drawingMode == 'add_frame') {
      Rect drawnRect = Rect.fromPoints(drawingStart!, drawingCurrent!);
      if (drawnRect.width > 50 && drawnRect.height > 50) {
        double newW = drawnRect.width.clamp(200.0, 10000.0);
        double newH = drawnRect.height.clamp(200.0, 10000.0);

        double topOffset = (hasShutter && !hasArchOrSlant) ? shutterBoxHeight : 0.0;
        double pHeight = hasFramePlintheBottom ? plintheHeight : 0.0;
        double bottomOffset = hasBottomFrame ? profileThickness : 0.0;

        // Use the center of the drawn rect to determine which side of the
        // existing window the user is drawing on. This is robust regardless
        // of how far outside the window the drag starts/ends.
        double centerX = drawnRect.center.dx;
        double centerY = drawnRect.center.dy;
        double dxRight  = (centerX - width).abs();   // distance to right edge
        double dxLeft   = (centerX - 0).abs();        // distance to left edge
        double dyTop    = (centerY - 0).abs();         // distance to top edge
        double dyBottom = (centerY - height).abs();   // distance to bottom edge

        // Clamp: only consider a side if the center is actually outside the window
        if (centerX > 0 && centerX < width) {
          dxRight = double.infinity;
          dxLeft  = double.infinity;
        }
        if (centerY > 0 && centerY < height) {
          dyTop    = double.infinity;
          dyBottom = double.infinity;
        }

        double minVal = math.min(math.min(dxRight, dxLeft), math.min(dyTop, dyBottom));

        final List<WindowZone> newZones = [];
        final tThickness = divisionThickness;

        if (minVal == dxRight) {
          double oldW = width;
          width = oldW + newW + tThickness;
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
          newZones.add(WindowZone(
            id: UniqueKey().toString(),
            boundary: Rect.fromLTRB(
              oldW + tThickness / 2,
              topOffset + profileThickness,
              width - profileThickness,
              height - bottomOffset - pHeight,
            ),
            sashThickness: _calculateSashThickness(false),
          ));
        } else if (minVal == dxLeft) {
          double oldW = width;
          width = oldW + newW + tThickness;
          for (var z in zones) {
            double leftEdge = profileThickness;
            double newLeft = (z.boundary.left - leftEdge).abs() < 2.0
                ? newW + tThickness / 2
                : z.boundary.left + newW + tThickness;
            final cloned = z.clone();
            cloned.boundary = Rect.fromLTRB(
              newLeft,
              z.boundary.top,
              z.boundary.right + newW + tThickness,
              z.boundary.bottom,
            );
            newZones.add(cloned);
          }
          newZones.add(WindowZone(
            id: UniqueKey().toString(),
            boundary: Rect.fromLTRB(
              profileThickness,
              topOffset + profileThickness,
              newW - tThickness / 2,
              height - bottomOffset - pHeight,
            ),
            sashThickness: _calculateSashThickness(false),
          ));
        } else if (minVal == dyBottom) {
          double oldH = height;
          height = oldH + newH + tThickness;
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
          newZones.add(WindowZone(
            id: UniqueKey().toString(),
            boundary: Rect.fromLTRB(
              profileThickness,
              oldH + tThickness / 2,
              width - profileThickness,
              height - bottomOffset - pHeight,
            ),
            sashThickness: _calculateSashThickness(false),
          ));
        } else {
          double oldH = height;
          height = oldH + newH + tThickness;
          for (var z in zones) {
            double topEdge = topOffset + profileThickness;
            double newTop = (z.boundary.top - topEdge).abs() < 2.0
                ? newH + tThickness / 2
                : z.boundary.top + newH + tThickness;
            final cloned = z.clone();
            cloned.boundary = Rect.fromLTRB(
              z.boundary.left,
              newTop,
              z.boundary.right,
              z.boundary.bottom + newH + tThickness,
            );
            newZones.add(cloned);
          }
          newZones.add(WindowZone(
            id: UniqueKey().toString(),
            boundary: Rect.fromLTRB(
              profileThickness,
              topOffset + profileThickness,
              width - profileThickness,
              newH - tThickness / 2,
            ),
            sashThickness: _calculateSashThickness(false),
          ));
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
    double cutLine = horizontal ? start.dy : start.dx;

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

  void moveSelectedMullion(double deltaPixels) {
    if (selection.type != SelectionType.mullion ||
        selection.mullionPosition == null) {
      return;
    }
    _saveSnapshot();
    bool isH = selection.isHorizontalMullion!;
    double pos = selection.mullionPosition!;
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
    }
    notifyListeners();
  }

  void setMullionProfile(MullionProfileType type) {
    if (selection.type != SelectionType.mullion ||
        selection.mullionPosition == null) {
      return;
    }
    _saveSnapshot();
    String key =
        "${selection.isHorizontalMullion! ? 'H' : 'V'}_${selection.mullionPosition!.toStringAsFixed(1)}";
    mullionProfiles[key] = type;
    notifyListeners();
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
    primaryMullionAxis = null;
    selection = SelectionInfo.none;
    activeSubZone = null;
    isDrawingMode = true;
    drawnLeft = null;
    drawnTop = null;

    // Reset slants
    topSlantLeftY = 0.0;
    topSlantRightY = 0.0;
    bottomSlantLeftY = 0.0;
    bottomSlantRightY = 0.0;
    archHeight = 0.0;
    hasSideCovers = true;

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
        if (((z1.boundary.right - z2.boundary.left).abs() - jointT).abs() <= 2.0) {
          double xCenter = (z1.boundary.right + z2.boundary.left) / 2;
          if (!joints.contains(xCenter)) {
            joints.add(xCenter);
          }
        } else if (((z2.boundary.right - z1.boundary.left).abs() - jointT).abs() <= 2.0) {
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
        if (((z1.boundary.bottom - z2.boundary.top).abs() - jointT).abs() <= 2.0) {
          double yCenter = (z1.boundary.bottom + z2.boundary.top) / 2;
          if (!joints.contains(yCenter)) {
            joints.add(yCenter);
          }
        } else if (((z2.boundary.bottom - z1.boundary.top).abs() - jointT).abs() <= 2.0) {
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
          if ((zone.boundary.right - other.boundary.left).abs() < jointT - 2.0 ||
              (other.boundary.right - zone.boundary.left).abs() < jointT - 2.0) {
            double overlapTop = math.max(zone.boundary.top, other.boundary.top);
            double overlapBottom = math.min(zone.boundary.bottom, other.boundary.bottom);
            if (overlapTop < overlapBottom - 5.0) {
              isConnected = true;
            }
          }
          
          // Check horizontal adjacency
          if ((zone.boundary.bottom - other.boundary.top).abs() < jointT - 2.0 ||
              (other.boundary.bottom - zone.boundary.top).abs() < jointT - 2.0) {
            double overlapLeft = math.max(zone.boundary.left, other.boundary.left);
            double overlapRight = math.min(zone.boundary.right, other.boundary.right);
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

      rects.add(Rect.fromLTRB(
        minL - t,
        minT - t,
        maxR + t,
        maxB + t,
      ));
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
