import 'package:flutter/material.dart';
import 'model.dart';

// Extension for GlassSpecification
extension GlassSpecificationSerialization on GlassSpecification {
  Map<String, dynamic> toMap() {
    return {
      'structure': structure.name,
      'finishOuter': finishOuter.name,
      'finishInner': finishInner.name,
      'colorOuter': colorOuter.name,
      'colorInner': colorInner.name,
      'processingOuter': processingOuter.name,
      'processingInner': processingInner.name,
      'colorP': colorP.name,
      'decorH': decorH,
      'decorV': decorV,
      'decorHPositions': decorHPositions,
      'decorVPositions': decorVPositions,
      'decorColor': decorColor,
      'decorThickness': decorThickness,
      'hasRosettes': hasRosettes,
      'panneauSubtype': panneauSubtype,
      'panneauColor': panneauColor,
      'decorBaguetteId': decorBaguetteId,
      'decorRosetteId': decorRosetteId,
      'panneauProductId': panneauProductId,
      'thicknessOuter': thicknessOuter,
      'thicknessInner': thicknessInner,
      'laminatedColorOuter': laminatedColorOuter,
      'laminatedColorInner': laminatedColorInner,
      'rosetteShape': rosetteShape,
      'jointTwoSides': jointTwoSides,
      'temperedOuter': temperedOuter,
      'temperedInner': temperedInner,
    };
  }
}

GlassSpecification glassSpecificationFromMap(Map<String, dynamic> map) {
  return GlassSpecification(
    structure: GlassStructure.values.firstWhere(
      (e) => e.name == map['structure'],
      orElse: () => GlassStructure.simple,
    ),
    finishOuter: GlassFinish.values.firstWhere(
      (e) => e.name == map['finishOuter'],
      orElse: () => GlassFinish.clair,
    ),
    finishInner: GlassFinish.values.firstWhere(
      (e) => e.name == map['finishInner'],
      orElse: () => GlassFinish.clair,
    ),
    colorOuter: GlassColor.values.firstWhere(
      (e) => e.name == map['colorOuter'],
      orElse: () => GlassColor.transparent,
    ),
    colorInner: GlassColor.values.firstWhere(
      (e) => e.name == map['colorInner'],
      orElse: () => GlassColor.transparent,
    ),
    processingOuter: GlassProcessing.values.firstWhere(
      (e) => e.name == map['processingOuter'],
      orElse: () => GlassProcessing.none,
    ),
    processingInner: GlassProcessing.values.firstWhere(
      (e) => e.name == map['processingInner'],
      orElse: () => GlassProcessing.none,
    ),
    colorP: ClosedGlassColor.values.firstWhere(
      (e) => e.name == map['colorP'],
      orElse: () => ClosedGlassColor.white,
    ),
    decorH: (map['decorH'] as num?)?.toInt() ?? 0,
    decorV: (map['decorV'] as num?)?.toInt() ?? 0,
    decorHPositions:
        (map['decorHPositions'] as List?)
            ?.map((e) => (e as num).toDouble())
            .toList() ??
        const [],
    decorVPositions:
        (map['decorVPositions'] as List?)
            ?.map((e) => (e as num).toDouble())
            .toList() ??
        const [],
    decorColor: map['decorColor']?.toString() ?? 'white',
    decorThickness: (map['decorThickness'] as num?)?.toDouble() ?? 6.0,
    hasRosettes: map['hasRosettes'] as bool? ?? false,
    panneauSubtype: map['panneauSubtype']?.toString(),
    panneauColor: map['panneauColor']?.toString(),
    decorBaguetteId: map['decorBaguetteId'] as int?,
    decorRosetteId: map['decorRosetteId'] as int?,
    panneauProductId: map['panneauProductId'] as int?,
    thicknessOuter: (map['thicknessOuter'] as num?)?.toDouble(),
    thicknessInner: (map['thicknessInner'] as num?)?.toDouble(),
    laminatedColorOuter:
        map['laminatedColorOuter']?.toString() ?? 'transparent',
    laminatedColorInner:
        map['laminatedColorInner']?.toString() ?? 'transparent',
    rosetteShape: (map['rosetteShape'] as num?)?.toInt() ?? 1,
    jointTwoSides: map['jointTwoSides'] as bool? ?? true,
    temperedOuter: map['temperedOuter'] as bool? ?? false,
    temperedInner: map['temperedInner'] as bool? ?? false,
  );
}

// Extension for WindowZone
extension WindowZoneSerialization on WindowZone {
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'handlePositionRatio': handlePositionRatio,
      'boundary': {
        'left': boundary.left,
        'top': boundary.top,
        'width': boundary.width,
        'height': boundary.height,
      },
      'content': content.name,
      'isSelected': isSelected,
      'glass': glass.toMap(),
      'openAngle': openAngle,
      'openDirection': openDirection?.name,
      'sashColor': sashColor.name,
      'selectedDbColor': selectedDbColor,
      'isSash105': isSash105,
      'innerH': innerH,
      'innerV': innerV,
      'slidingSashesCount': slidingSashesCount,
      'rightInnerH': rightInnerH,
      'rightInnerV': rightInnerV,
      'innerHPositions': innerHPositions,
      'innerVPositions': innerVPositions,
      'rightInnerHPositions': rightInnerHPositions,
      'rightInnerVPositions': rightInnerVPositions,
      'cellIsSash': cellIsSash,
      'cellIsDoubleSash': cellIsDoubleSash,
      'cellIsPanel': cellIsPanel,
      'cellSashOverrides': cellSashOverrides,
      'doubleSashRatio': doubleSashRatio,
      'middleHingeDragOffset': middleHingeDragOffset,
      'primaryDivisionAxis': primaryDivisionAxis,
      'rightPrimaryDivisionAxis': rightPrimaryDivisionAxis,
      'useClassicHandle': useClassicHandle,
      'useOctoHandle': useOctoHandle,
      'usePvcHandleOnAlu': usePvcHandleOnAlu,
      'lockType': lockType.name,
      'slidingMontantReinforced': slidingMontantReinforced,
      'disabledVerticalDivisions': disabledVerticalDivisions,
      'disabledHorizontalDivisions': disabledHorizontalDivisions,
      'isSubdivided': isSubdivided,
      'hasSashPlintheBottom': hasSashPlintheBottom,
      'cellGlassSpec': cellGlassSpec.map((k, v) => MapEntry(k, v.toMap())),
    };
  }
}

WindowZone windowZoneFromMap(Map<String, dynamic> map) {
  final boundaryMap = map['boundary'] as Map<String, dynamic>;
  final rect = Rect.fromLTWH(
    (boundaryMap['left'] as num).toDouble(),
    (boundaryMap['top'] as num).toDouble(),
    (boundaryMap['width'] as num).toDouble(),
    (boundaryMap['height'] as num).toDouble(),
  );

  return WindowZone(
    id: map['id'],
    handlePositionRatio:
        (map['handlePositionRatio'] as num?)?.toDouble() ?? 0.5,
    boundary: rect,
    content: ZoneContent.values.firstWhere(
      (e) => e.name == map['content'],
      orElse: () => ZoneContent.fixedGlass,
    ),
    isSelected: map['isSelected'] ?? false,
    glass: map['glass'] != null
        ? glassSpecificationFromMap(map['glass'])
        : const GlassSpecification(),
    openAngle: (map['openAngle'] as num?)?.toDouble() ?? 0.0,
    openDirection: map['openDirection'] != null
        ? OpenDirection.values.firstWhere(
            (e) => e.name == map['openDirection'],
            orElse: () => OpenDirection.right,
          )
        : null,
    sashColor: FrameColor.values.firstWhere(
      (e) => e.name == map['sashColor'],
      orElse: () => FrameColor.white,
    ),
    selectedDbColor: map['selectedDbColor'],
    isSash105: map['isSash105'] ?? false,
    useClassicHandle: map['useClassicHandle'] ?? false,
    useOctoHandle: map['useOctoHandle'] ?? false,
    usePvcHandleOnAlu: map['usePvcHandleOnAlu'] ?? false,
    doubleSashRatio: (map['doubleSashRatio'] as num?)?.toDouble() ?? 0.5,
    innerH: map['innerH'] ?? 0,
    innerV: map['innerV'] ?? 0,
    slidingSashesCount: map['slidingSashesCount'] ?? 2,
    rightInnerH: map['rightInnerH'] ?? 0,
    rightInnerV: map['rightInnerV'] ?? 0,
    innerHPositions:
        (map['innerHPositions'] as List<dynamic>?)
            ?.map((e) => (e as num).toDouble())
            .toList() ??
        const [],
    innerVPositions:
        (map['innerVPositions'] as List<dynamic>?)
            ?.map((e) => (e as num).toDouble())
            .toList() ??
        const [],
    rightInnerHPositions:
        (map['rightInnerHPositions'] as List<dynamic>?)
            ?.map((e) => (e as num).toDouble())
            .toList() ??
        const [],
    rightInnerVPositions:
        (map['rightInnerVPositions'] as List<dynamic>?)
            ?.map((e) => (e as num).toDouble())
            .toList() ??
        const [],
    cellIsPanel:
        (map['cellIsPanel'] as Map<String, dynamic>?)?.map(
          (k, v) => MapEntry(k, v as bool),
        ) ??
        {},
    cellIsSash:
        (map['cellIsSash'] as Map<String, dynamic>?)?.map(
          (k, v) => MapEntry(k, v as bool),
        ) ??
        {},
    cellIsDoubleSash:
        (map['cellIsDoubleSash'] as Map<String, dynamic>?)?.map(
          (k, v) => MapEntry(k, v as bool),
        ) ??
        {},
    cellSashOverrides:
        (map['cellSashOverrides'] as Map<String, dynamic>?)?.map(
          (k, v) => MapEntry(k, Map<String, dynamic>.from(v as Map)),
        ) ??
        const {},
    middleHingeDragOffset:
        (map['middleHingeDragOffset'] as num?)?.toDouble() ?? 0.0,
    primaryDivisionAxis: map['primaryDivisionAxis'],
    rightPrimaryDivisionAxis: map['rightPrimaryDivisionAxis'],
    lockType: map['lockType'] != null
        ? LockType.values.firstWhere(
            (e) => e.name == map['lockType'],
            orElse: () => LockType.none,
          )
        : LockType.none,
    slidingMontantReinforced:
        (map['slidingMontantReinforced'] as Map<String, dynamic>?)?.map(
          (k, v) => MapEntry(k, v as bool),
        ),
    disabledVerticalDivisions:
        (map['disabledVerticalDivisions'] as Map<String, dynamic>?)?.map(
          (k, v) => MapEntry(k, v as bool),
        ) ??
        const {},
    disabledHorizontalDivisions:
        (map['disabledHorizontalDivisions'] as Map<String, dynamic>?)?.map(
          (k, v) => MapEntry(k, v as bool),
        ) ??
        const {},
    isSubdivided: map['isSubdivided'] ?? false,
    hasSashPlintheBottom: map['hasSashPlintheBottom'] ?? false,
    cellGlassSpec:
        (map['cellGlassSpec'] as Map?)?.map(
          (k, v) => MapEntry(
            k.toString(),
            glassSpecificationFromMap(Map<String, dynamic>.from(v as Map)),
          ),
        ) ??
        const {},
  );
}

// Extension for WindowModel
extension WindowModelSerialization on WindowModel {
  Map<String, dynamic> toMap() {
    return {
      'width': width,
      'height': height,
      'systemMode': () {
        final hasSliding = zones.any((z) => z.content == ZoneContent.slidingSash);
        final hasFrench = zones.any((z) => z.content == ZoneContent.singleSash || z.content == ZoneContent.doubleSash);
        if (hasSliding && hasFrench) return 'mixed';
        if (hasSliding) return 'sliding';
        if (hasFrench) return 'french';
        return (systemMode != null && systemMode!.isNotEmpty) ? systemMode : 'mixed';
      }(),
      'totalCost': totalCost,
      'quantity': quantity,
      'manualNameOverride': manualNameOverride,
      'manualPriceOverride': manualPriceOverride,
      'description': description,
      'invoiceTableEdited': invoiceTableEdited,
      'position': position,
      'isCustomProduct': isCustomProduct,
      'archHeight': archHeight,
      'topSlantLeftY': topSlantLeftY,
      'topSlantRightY': topSlantRightY,
      'bottomSlantLeftY': bottomSlantLeftY,
      'bottomSlantRightY': bottomSlantRightY,
      'profileThickness': profileThickness,
      'hasBottomFrame': hasBottomFrame,
      'hasFramePlintheBottom': hasFramePlintheBottom,
      'isInternalView': isInternalView,
      'isDrawingMode': isDrawingMode,
      'hasShutter': hasShutter,
      'isCaissonTunnel': isCaissonTunnel,
      'caissonPayload': caissonPayload,
      'isMoustiquaire': isMoustiquaire,
      'moustiquairePayload': moustiquairePayload,
      'isGlassWork': isGlassWork,
      'glassWorkPayload': glassWorkPayload,
      'caissonTunnelHeight': caissonTunnelHeight,
      'showBottomWall': showBottomWall,
      'showWall': showWall,
      'wallColor': wallColor,
      'shutterIntercalaireRatio': shutterIntercalaireRatio,
      'shutterMechanism': shutterMechanism,
      'motorHasInterrupteur': motorHasInterrupteur,
      'motorHasTelecommande': motorHasTelecommande,
      'shutterLame': shutterLame,
      'shutterGlissiere': shutterGlissiere,
      'shutterPosition': shutterPosition,
      'shutterDriveSide': shutterDriveSide,
      'customShutterBoxHeight': customShutterBoxHeight,
      'selectedShutterLameId': selectedShutterLameId,
      'selectedShutterKitId': selectedShutterKitId,
      'selectedShutterMotorId': selectedShutterMotorId,
      'hasSideCovers': hasSideCovers,
      'sideCoverUseSecondWidth': sideCoverUseSecondWidth,
      'isFrame140': isFrame140,
      'isShutterOnly': isShutterOnly,
      'removedShutterSides': removedShutterSides.toList(),
      'frameColor': frameColor.name,
      'selectedDbColor': selectedDbColor,
      'selectedAccessoryColor': selectedAccessoryColor,
      'primaryMullionAxis': primaryMullionAxis,
      'zones': zones.map((z) => z.toMap()).toList(),
      'mullionProfiles': mullionProfiles.map((k, v) => MapEntry(k, v.name)),
      'mullionSectionOverrides': mullionSectionOverrides,
      'componentOverrides': componentOverrides,
      'isReplaced': isReplaced,
      'replacementReason': replacementReason,
      'frameOverride': frameOverride,
      'sashOverride': sashOverride,
      'sideCoverOverride': sideCoverOverride,
      'slidingFrameOverride': slidingFrameOverride,
      'slidingSashOverride': slidingSashOverride,
      // إذا كانت activeSeries محملة نستخدمها، وإلا نحتفظ بالقيم المحفوظة مسبقاً
      'seriesName': activeSeries?.name ?? loadedSeriesName,
      'seriesId': activeSeries?.id ?? loadedSeriesId,
      'slidingSeriesName': activeSlidingSeries?.name ?? loadedSlidingSeriesName,
      'slidingSeriesId': activeSlidingSeries?.id ?? loadedSlidingSeriesId,
      'profileName': () {
        if (activeSeries == null || availableSystems.isEmpty) return null;
        for (var s in availableSystems) {
          if (s.id == activeSeries!.profileId) return s.name;
        }
        return null;
      }(),
      // Note: db, availableSystems, activeSeries, availableColors are transient/session-based.
      // We only save the structural and visual data.
    };
  }
}

void applyWindowModelFromMap(WindowModel model, Map<String, dynamic> map) {
  model.width = (map['width'] as num?)?.toDouble() ?? 0.0;
  model.height = (map['height'] as num?)?.toDouble() ?? 0.0;
  model.lastLayoutSize = null; // أجبر إعادة حساب canvasScale عند تحميل رسم جديد
  model.systemMode = map['systemMode']?.toString();
  model.isReplaced = map['isReplaced'] ?? false;
  model.replacementReason = map['replacementReason'] ?? '';
  model.isCustomProduct = map['isCustomProduct'] ?? false;
  model.totalCost = (map['totalCost'] as num?)?.toDouble() ?? 0.0;
  model.quantity = (map['quantity'] as num?)?.toInt() ?? 1;
  model.manualNameOverride = map['manualNameOverride']?.toString();
  model.manualPriceOverride = (map['manualPriceOverride'] as num?)?.toDouble();
  model.description = map['description']?.toString();
  model.invoiceTableEdited =
      map['invoiceTableEdited'] == true ||
      map['invoiceTableEdited']?.toString().toLowerCase() == 'true';
  model.position = map['position']?.toString();
  model.archHeight = (map['archHeight'] as num?)?.toDouble() ?? 0.0;
  model.topSlantLeftY = (map['topSlantLeftY'] as num?)?.toDouble() ?? 0.0;
  model.topSlantRightY = (map['topSlantRightY'] as num?)?.toDouble() ?? 0.0;
  model.bottomSlantLeftY = (map['bottomSlantLeftY'] as num?)?.toDouble() ?? 0.0;
  model.bottomSlantRightY =
      (map['bottomSlantRightY'] as num?)?.toDouble() ?? 0.0;
  model.profileThickness =
      (map['profileThickness'] as num?)?.toDouble() ?? 40.0;
  model.hasBottomFrame = map['hasBottomFrame'] ?? true;
  model.hasFramePlintheBottom = map['hasFramePlintheBottom'] ?? false;
  model.isInternalView = map['isInternalView'] ?? false;
  model.isDrawingMode = false;
  model.hasShutter = map['hasShutter'] ?? false;
  model.isCaissonTunnel = map['isCaissonTunnel'] ?? false;
  if (map['caissonPayload'] != null && map['caissonPayload'] is Map) {
    model.caissonPayload = Map<String, dynamic>.from(map['caissonPayload']);
  } else if (map['items'] != null && map['kitType'] != null) {
    model.caissonPayload = {
      'systemType': 'caisson_tunnel',
      'kitType': map['kitType'],
      'inputUnit': map['inputUnit'] ?? 'cm',
      'itemsCount': map['itemsCount'] ?? (map['items'] as List).length,
      'grandTotalCaissonBars': map['grandTotalCaissonBars'] ?? 0,
      'grandTotalBottomCoverBars': map['grandTotalBottomCoverBars'] ?? 0,
      'grandTotalPairs': map['grandTotalPairs'] ?? 0,
      'items': map['items'],
      'sizeCalculations': map['sizeCalculations'],
    };
  }
  model.isMoustiquaire = map['isMoustiquaire'] ?? false;
  if (map['moustiquairePayload'] is Map) {
    model.moustiquairePayload = Map<String, dynamic>.from(
      map['moustiquairePayload'] as Map,
    );
  }
  model.isGlassWork = map['isGlassWork'] ?? false;
  if (map['glassWorkPayload'] is Map) {
    model.glassWorkPayload = Map<String, dynamic>.from(
      map['glassWorkPayload'] as Map,
    );
  }
  model.showBottomWall = map['showBottomWall'] ?? true;
  model.showWall = map['showWall'] ?? true;
  model.wallColor = map['wallColor'] ?? 'red';
  model.shutterIntercalaireRatio = map['shutterIntercalaireRatio'] ?? 1;
  model.shutterMechanism = map['shutterMechanism'] ?? 'حزام';
  if (model.shutterMechanism == 'Manuel' || model.shutterMechanism.isEmpty) {
    model.shutterMechanism = 'حزام';
  }
  model.motorHasInterrupteur = map['motorHasInterrupteur'] ?? false;
  model.motorHasTelecommande = map['motorHasTelecommande'] ?? false;
  model.shutterLame = map['shutterLame'] ?? 'Lame Injectée';
  model.shutterGlissiere = map['shutterGlissiere'] ?? 'Glissière 25';
  model.shutterPosition = (map['shutterPosition'] as num?)?.toDouble() ?? 0.5;
  model.shutterDriveSide = map['shutterDriveSide'] ?? 'right';
  model.customShutterBoxHeight = (map['customShutterBoxHeight'] as num?)
      ?.toDouble();
  model.selectedShutterLameId = (map['selectedShutterLameId'] as num?)?.toInt();
  model.selectedShutterKitId = (map['selectedShutterKitId'] as num?)?.toInt();
  model.selectedShutterMotorId = (map['selectedShutterMotorId'] as num?)
      ?.toInt();
  model.hasSideCovers = map['hasSideCovers'] ?? true;
  model.sideCoverUseSecondWidth = map['sideCoverUseSecondWidth'] ?? false;
  model.isFrame140 = map['isFrame140'] ?? false;
  model.isShutterOnly = map['isShutterOnly'] ?? false;
  model.primaryMullionAxis = map['primaryMullionAxis'];
  model.caissonTunnelHeight =
      (map['caissonTunnelHeight'] as num?)?.toDouble() ?? 300.0;

  if (map['removedShutterSides'] != null) {
    model.removedShutterSides = Set<String>.from(map['removedShutterSides']);
  }

  if (map['frameColor'] != null) {
    model.frameColor = FrameColor.values.firstWhere(
      (e) => e.name == map['frameColor'],
      orElse: () => FrameColor.white,
    );
  }

  model.selectedDbColor = map['selectedDbColor'] != null
      ? Map<String, dynamic>.from(map['selectedDbColor'])
      : null;
  model.selectedAccessoryColor = map['selectedAccessoryColor'] != null
      ? Map<String, dynamic>.from(map['selectedAccessoryColor'])
      : null;
  model.loadedSeriesName =
      map['seriesName']?.toString() ?? map['profileName']?.toString();
  model.loadedSeriesId = (map['seriesId'] as num?)?.toInt();
  model.loadedSlidingSeriesName = map['slidingSeriesName']?.toString();
  model.loadedSlidingSeriesId = (map['slidingSeriesId'] as num?)?.toInt();

  model.frameOverride = map['frameOverride'] != null
      ? Map<String, dynamic>.from(map['frameOverride'])
      : null;
  model.sashOverride = map['sashOverride'] != null
      ? Map<String, dynamic>.from(map['sashOverride'])
      : null;
  model.sideCoverOverride = map['sideCoverOverride'] != null
      ? Map<String, dynamic>.from(map['sideCoverOverride'])
      : null;
  model.slidingFrameOverride = map['slidingFrameOverride'] != null
      ? Map<String, dynamic>.from(map['slidingFrameOverride'])
      : null;
  model.slidingSashOverride = map['slidingSashOverride'] != null
      ? Map<String, dynamic>.from(map['slidingSashOverride'])
      : null;

  if (map['componentOverrides'] != null) {
    final raw = map['componentOverrides'] as Map;
    model.componentOverrides = {};
    for (final entry in raw.entries) {
      final key = entry.key.toString();
      final val = entry.value;
      if (val is Map) {
        model.componentOverrides[key] = Map<String, dynamic>.from(val);
      } else {
        model.componentOverrides[key] = val;
      }
    }
  }

  if (map['zones'] != null) {
    model.zones = (map['zones'] as List<dynamic>)
        .map((zMap) => windowZoneFromMap(zMap as Map<String, dynamic>))
        .toList();
  }

  if (map['mullionProfiles'] != null) {
    model.mullionProfiles = (map['mullionProfiles'] as Map<String, dynamic>)
        .map(
          (k, v) => MapEntry(
            k,
            MullionProfileType.values.firstWhere(
              (e) => e.name == v,
              orElse: () => MullionProfileType.standard,
            ),
          ),
        );
  }

  if (map['mullionSectionOverrides'] is Map) {
    model.mullionSectionOverrides =
        (map['mullionSectionOverrides'] as Map).map(
      (key, value) => MapEntry(
        key.toString(),
        Map<String, dynamic>.from(value as Map),
      ),
    );
  }
}

Future<void> applyWindowModelAndLoadCatalog(
  WindowModel model,
  Map<String, dynamic> map,
) async {
  applyWindowModelFromMap(model, map);
  await model.loadCatalogData(model.systemMode ?? '');
}
