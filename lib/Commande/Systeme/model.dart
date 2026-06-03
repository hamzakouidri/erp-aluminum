import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../../sql_database.dart';

enum DimensionTap { none, width, height }

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

enum FrameColor { white, brown, gray, black, beige }

enum SelectionType { zone, mullion }

enum MullionProfileType { standard, flat, grooved }

// 🟢 كلاسات الكتالوجات الجديدة
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

  AluminumSection({
    required this.id,
    required this.seriesId,
    required this.code,
    required this.name,
    required this.type,
    required this.thickness,
    required this.glassDeduction,
    required this.weightPerMeter,
    this.couvreJointWidth = 0.0,
  });

  factory AluminumSection.fromMap(Map<String, dynamic> map) {
    return AluminumSection(
      id: map['id'],
      seriesId: map['series_id'],
      code: map['code'],
      name: map['name'],
      type: map['type'],
      thickness: map['thickness'],
      glassDeduction: (map['glass_deduction'] as num?)?.toDouble() ?? 0.0,
      weightPerMeter: (map['weight_per_meter'] as num?)?.toDouble() ?? 0.0,
      couvreJointWidth: (map['couvre_joint_width'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

class AluminumSeries {
  final int id;
  final int profileId;
  final String name;
  final String type;
  List<AluminumSection> sections;

  AluminumSeries({
    required this.id,
    required this.profileId,
    required this.name,
    required this.type,
    List<AluminumSection>? sections, // 🟢 تم التعديل لتكون اختيارية
  }) : sections = sections ?? []; // 🟢 إنشاء قائمة مرنة قابلة للإضافة

  factory AluminumSeries.fromMap(Map<String, dynamic> map) {
    return AluminumSeries(
      id: map['id'],
      profileId: map['profile_id'],
      name: map['name'],
      type: map['type'],
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
    List<AluminumSeries>? series, // 🟢 تم التعديل لتكون اختيارية
  }) : series = series ?? []; // 🟢 إنشاء قائمة مرنة قابلة للإضافة

  factory AluminumProfileSystem.fromMap(Map<String, dynamic> map) {
    return AluminumProfileSystem(
      id: map['id'],
      name: map['name'],
      type: map['type'],
    );
  }
}

class InnerDimensionHit {
  final String zoneId;
  final bool isWidth;

  InnerDimensionHit(this.zoneId, this.isWidth);
}

class GlassSpecification {
  final GlassStructure structure;
  final GlassFinish finishOuter;
  final GlassFinish finishInner;
  final GlassColor colorOuter;
  final GlassColor colorInner;
  final GlassProcessing processingOuter;
  final GlassProcessing processingInner;
  final ClosedGlassColor colorP;

  const GlassSpecification({
    this.structure = GlassStructure.simple,
    this.finishOuter = GlassFinish.clair,
    this.finishInner = GlassFinish.clair,
    this.colorOuter = GlassColor.transparent,
    this.colorInner = GlassColor.transparent,
    this.processingOuter = GlassProcessing.none,
    this.processingInner = GlassProcessing.none,
    this.colorP = ClosedGlassColor.white,
  });

  GlassSpecification clone() => GlassSpecification(
    structure: structure,
    finishOuter: finishOuter,
    finishInner: finishInner,
    colorOuter: colorOuter,
    colorInner: colorInner,
    processingOuter: processingOuter,
    processingInner: processingInner,
    colorP: colorP,
  );

  GlassSpecification copyWith({
    GlassStructure? structure,
    GlassFinish? finishOuter,
    GlassFinish? finishInner,
    GlassColor? colorOuter,
    GlassColor? colorInner,
    GlassProcessing? processingOuter,
    GlassProcessing? processingInner,
    ClosedGlassColor? colorP,
  }) => GlassSpecification(
    structure: structure ?? this.structure,
    finishOuter: finishOuter ?? this.finishOuter,
    finishInner: finishInner ?? this.finishInner,
    colorOuter: colorOuter ?? this.colorOuter,
    colorInner: colorInner ?? this.colorInner,
    processingOuter: processingOuter ?? this.processingOuter,
    processingInner: processingInner ?? this.processingInner,
    colorP: colorP ?? this.colorP,
  );

  String get displayName {
    if (structure == GlassStructure.closed) return '';
    return structure == GlassStructure.double ? '24mm' : '6mm';
  }
}

class WindowZone {
  final String id;
  double? handlePositionRatio;
  Rect boundary;
  ZoneContent content;
  bool isSelected;
  GlassSpecification glass;
  double openAngle;
  OpenDirection? openDirection;
  FrameColor sashColor;
  Map<String, dynamic>? selectedDbColor;
  bool isSash105;
  int innerH;
  int innerV;
  int slidingSashesCount;
  int rightInnerH;
  int rightInnerV;
  Map<String, bool> cellIsPanel;

  WindowZone({
    required this.id,
    this.handlePositionRatio = 0.5,
    required this.boundary,
    this.content = ZoneContent.fixedGlass,
    this.isSelected = false,
    this.glass = const GlassSpecification(),
    this.openAngle = 0.0,
    this.openDirection = OpenDirection.right,
    this.sashColor = FrameColor.gray,
    this.selectedDbColor,
    this.isSash105 = false,
    this.innerH = 0,
    this.innerV = 0,
    this.slidingSashesCount = 2,
    this.rightInnerH = 0,
    this.rightInnerV = 0,
    this.cellIsPanel = const {},
  });

  WindowZone clone() => WindowZone(
    id: id,
    handlePositionRatio: handlePositionRatio,
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
    innerH: innerH,
    innerV: innerV,
    rightInnerH: rightInnerH,
    rightInnerV: rightInnerV,
    cellIsPanel: Map.from(cellIsPanel),
  );

  WindowZone copyWith({
    double? handlePositionRatio,
    Rect? boundary,
    ZoneContent? content,
    bool? isSelected,
    GlassSpecification? glass,
    double? openAngle,
    OpenDirection? openDirection,
    FrameColor? sashColor,
    Map<String, dynamic>? selectedDbColor,
    bool? isSash105,
    int? innerH,
    int? innerV,
    int? slidingSashesCount,
    int? rightInnerH,
    int? rightInnerV,
    Map<String, bool>? cellIsPanel,
  }) => WindowZone(
    id: id,
    handlePositionRatio: handlePositionRatio ?? this.handlePositionRatio,
    boundary: boundary ?? this.boundary,
    content: content ?? this.content,
    isSelected: isSelected ?? this.isSelected,
    glass: glass ?? this.glass,
    openAngle: openAngle ?? this.openAngle,
    openDirection: openDirection ?? this.openDirection,
    sashColor: sashColor ?? this.sashColor,
    selectedDbColor: selectedDbColor ?? this.selectedDbColor,
    isSash105: isSash105 ?? this.isSash105,
    innerH: innerH ?? this.innerH,
    innerV: innerV ?? this.innerV,
    rightInnerH: rightInnerH ?? this.rightInnerH,
    rightInnerV: rightInnerV ?? this.rightInnerV,
    cellIsPanel: cellIsPanel ?? this.cellIsPanel,
  );
}

class SelectionInfo {
  final SelectionType? type;
  final String? zoneId;
  final bool? isHorizontalMullion;
  final double? mullionPosition;
  static const none = SelectionInfo(type: null);

  const SelectionInfo({
    this.type,
    this.zoneId,
    this.isHorizontalMullion,
    this.mullionPosition,
  });
}

class WindowSnapshot {
  final double width;
  final double height;
  final bool hasBottomFrame;
  final List<WindowZone> zones;
  final Map<String, MullionProfileType> mullionProfiles;
  final Map<String, dynamic>? selectedDbColor;

  WindowSnapshot(
    this.width,
    this.height,
    this.hasBottomFrame,
    this.zones,
    this.mullionProfiles,
    this.selectedDbColor,
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
          const Color(0xFFB0BEC5),
          const Color(0xFF90A4AE),
          const Color(0xFF78909C),
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
    }
  }

  Color get borderColor {
    switch (this) {
      case FrameColor.white:
        return Colors.grey.shade400;
      case FrameColor.brown:
        return const Color(0xFF3E2723);
      case FrameColor.gray:
        return const Color(0xFF546E7A);
      case FrameColor.black:
        return Colors.black;
      case FrameColor.beige:
        return const Color(0xFFC0C090);
    }
  }
}

List<Color> getEffectiveGradientColors(
  FrameColor baseColor,
  Map<String, dynamic>? dbColor,
) {
  if (dbColor != null) {
    String name = dbColor['name'].toString().toLowerCase();
    if (name.contains('wood') || name.contains('bois') || name.contains('خشبي')) {
      return FrameColor.brown.gradientColors;
    }
    if (name.contains('black') ||
        name.contains('noir') ||
        name.contains('أسود')) {
      return FrameColor.black.gradientColors;
    }
    if (name.contains('gray') ||
        name.contains('grey') ||
        name.contains('gris') ||
        name.contains('رمادي')) {
      return FrameColor.gray.gradientColors;
    }
    if (name.contains('beige') || name.contains('بيج')) {
      return FrameColor.beige.gradientColors;
    }
    if (name.contains('silver') ||
        name.contains('فض') ||
        name.contains('argent')) {
      return [
        const Color(0xFFE0E0E0),
        const Color(0xFFBDBDBD),
        const Color(0xFF9E9E9E),
      ];
    }
    if (name.contains('champagne') || name.contains('شامبان')) {
      return [
        const Color(0xFFF5E6C8),
        const Color(0xFFDDC8A0),
        const Color(0xFFBBA070),
      ];
    }
    if (name.contains('bronze') || name.contains('برونز')) {
      return [
        const Color(0xFFCD853F),
        const Color(0xFFA0522D),
        const Color(0xFF8B4513),
      ];
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
    String name = dbColor['name'].toString().toLowerCase();
    if (name.contains('wood') || name.contains('bois') || name.contains('خشبي')) {
      return FrameColor.brown.borderColor;
    }
    if (name.contains('black') ||
        name.contains('noir') ||
        name.contains('أسود')) {
      return FrameColor.black.borderColor;
    }
    if (name.contains('gray') ||
        name.contains('grey') ||
        name.contains('gris') ||
        name.contains('رمادي')) {
      return FrameColor.gray.borderColor;
    }
    if (name.contains('beige') || name.contains('بيج')) {
      return FrameColor.beige.borderColor;
    }
    if (name.contains('silver') ||
        name.contains('فض') ||
        name.contains('argent')) {
      return const Color(0xFF757575);
    }
    if (name.contains('champagne') || name.contains('شامبان')) {
      return const Color(0xFF8D6E63);
    }
    if (name.contains('bronze') || name.contains('برونز')) {
      return const Color(0xFF5D4037);
    }
    return FrameColor.white.borderColor;
  }
  return baseColor.borderColor;
}

class WindowModel extends ChangeNotifier {
  List<PlacedFrame> frames = [];
  PlacedFrame? selectedFrame;

  double width;
  double height;
  double totalCost = 0.0;

  double archHeight = 0.0;
  double topSlantLeftY = 0.0;
  double topSlantRightY = 0.0;
  double bottomSlantLeftY = 0.0;
  double bottomSlantRightY = 0.0;

  bool get canBeArchedOrSlanted {
    return !zones.any((z) => z.content == ZoneContent.slidingSash);
  }

  double profileThickness;
  bool hasBottomFrame = true;
  bool isInternalView = false;
  bool isDrawingMode = true;
  bool hasShutter = false;
  double shutterPosition = 0.5;
  bool hasSideCovers = true;
  bool isFrame140 = false;
  Set<String> removedShutterSides = {};

  FrameColor _frameColor = FrameColor.gray;

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

  List<WindowZone> zones = [];
  Map<String, MullionProfileType> mullionProfiles = {};
  SelectionInfo selection = SelectionInfo.none;
  String? activeSubZone;
  bool showZoneMenu = false;
  final List<WindowSnapshot> _history = [];

  bool get canUndo => _history.isNotEmpty;

  double canvasScale = 1.0;
  double canvasDx = 0.0;
  double canvasDy = 0.0;
  Offset? drawingStart;
  Offset? drawingCurrent;

  // المتغيرات الخاصة بالكتالوج
  final SqlDatabase db; // يجب تمرير قاعدة البيانات للموديل
  List<AluminumProfileSystem> availableSystems = [];
  AluminumSeries? activeSeries; // السلسلة المختارة حاليا
  List<Map<String, dynamic>> availableColors =
      []; // الألوان المحملة من قاعدة البيانات

  WindowModel({
    required this.db,
    this.width = 0,
    this.height = 0,
    this.profileThickness = 40.0,
  });

  Future<void> loadCatalogData([String systemMode = '']) async {
    try {
      final profilesData = await db.readProfile();
      availableColors = await db.readColors();
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

          // 🟢 التصفية الذكية بناءً على systemMode
          bool isMatchingMode =
              true; // الافتراضي أن نظهرها إذا لم يكن هناك وضع محدد

          // نجمع أسماء وأنواع النظام والسلسلة للبحث فيها
          String searchString =
              '${system.type} ${system.name} ${series.type} ${series.name}'
                  .toLowerCase();

          if (systemMode == 'french') {
            // كلمات تدل على الفتح الفرنسي
            isMatchingMode =
                searchString.contains('frappe') ||
                searchString.contains('battant') ||
                searchString.contains('فتح') ||
                searchString.contains('فرنسي');
          } else if (systemMode == 'sliding') {
            // كلمات تدل على الانزلاق
            isMatchingMode =
                searchString.contains('coulissant') ||
                searchString.contains('sliding') ||
                searchString.contains('منزلق') ||
                searchString.contains('كوليس');
          }

          // 🟢 إذا كانت السلسلة تطابق نوع الشاشة، نضيفها للقائمة
          if (isMatchingMode) {
            system.series.add(series);
          }
        }

        // 🟢 نضيف النظام فقط إذا كان يحتوي على سلاسل بعد التصفية
        if (system.series.isNotEmpty) {
          availableSystems.add(system);
        }
      }

      if (availableSystems.isNotEmpty) {
        // التأكد من أن السلسلة المحددة حالياً لا تزال موجودة بعد التصفية
        bool hasValidActiveSeries = false;
        if (activeSeries != null) {
          for (var sys in availableSystems) {
            if (sys.series.any((s) => s.id == activeSeries!.id)) {
              hasValidActiveSeries = true;
              break;
            }
          }
        }

        // إذا لم تكن موجودة (أو كان هذا أول فتح للشاشة)، نختار أول سلسلة مطابقة تلقائياً
        if (!hasValidActiveSeries) {
          setActiveSeries(availableSystems.first.series.first);
          foundValidSeries = true;
        } else {
          foundValidSeries = true;
        }
      }

      if (!foundValidSeries) {
        activeSeries = null;
      }

      notifyListeners();
    } catch (e) {
      print("Error loading catalog data: $e");
    }
  }

  // 🟢 دالة تغيير السلسلة المختارة وتحديث الرسم تلقائيا
  void setActiveSeries(AluminumSeries series) {
    _saveSnapshot();
    activeSeries = series;
    _updateProfileThickness();
    notifyListeners();
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
        zones.map((z) => z.clone()).toList(),
        Map.from(mullionProfiles),
        selectedDbColor != null ? Map.from(selectedDbColor!) : null,
      ),
    );
    if (_history.length > 20) _history.removeAt(0);
    notifyListeners();
  }

  void refreshUI() {
    notifyListeners();
  }

  void undo() {
    if (_history.isEmpty) return;
    final snap = _history.removeLast();
    width = snap.width;
    height = snap.height;
    hasBottomFrame = snap.hasBottomFrame;
    zones = snap.zones;
    mullionProfiles = snap.mullionProfiles;
    _selectedDbColor = snap.selectedDbColor;
    selection = SelectionInfo.none;
    activeSubZone = null;
    showZoneMenu = false;
    notifyListeners();
  }

  void updateLayoutMetrics(Size widgetSize) {
    if (width <= 0 || height <= 0 || zones.isEmpty) {
      canvasScale = 1.0;
      canvasDx = 0.0;
      canvasDy = 0.0;
      return;
    }
    final padding = 120.0;
    double maxW = widgetSize.width - padding;
    double maxH = widgetSize.height - padding;
    if (maxW <= 0) maxW = 100;
    if (maxH <= 0) maxH = 100;
    double sX = maxW / width;
    double sY = maxH / height;
    canvasScale = math.min(sX, sY);
    canvasDx = (widgetSize.width - (width * canvasScale)) / 2;
    canvasDy = (widgetSize.height - (height * canvasScale)) / 2;
  }

  void selectAt(Offset pos, {bool isLongPress = false}) {
    double hitSlop = 40.0;
    final t = profileThickness;
    for (int i = 0; i < zones.length; i++) {
      for (int j = i + 1; j < zones.length; j++) {
        final z1 = zones[i].boundary;
        final z2 = zones[j].boundary;
        if ((z1.bottom - z2.top).abs() <= t + 2 ||
            (z2.bottom - z1.top).abs() <= t + 2) {
          double yCenter = (z1.bottom + z2.top) / 2;
          if ((z2.bottom - z1.top).abs() <= t + 2) {
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
            );
            showZoneMenu = false;
            activeSubZone = null;
            notifyListeners();
            return;
          }
        }
        if ((z1.right - z2.left).abs() <= t + 2 ||
            (z2.right - z1.left).abs() <= t + 2) {
          double xCenter = (z1.right + z2.left) / 2;
          if ((z2.right - z1.left).abs() <= t + 2) {
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
            );
            showZoneMenu = false;
            activeSubZone = null;
            notifyListeners();
            return;
          }
        }
      }
    }

    for (var z in zones) {
      if (z.boundary.contains(pos)) {
        selection = SelectionInfo(type: SelectionType.zone, zoneId: z.id);
        bool isDouble = z.content == ZoneContent.doubleSash;
        bool isSingle = z.content == ZoneContent.singleSash;
        bool isSliding = z.content == ZoneContent.slidingSash;
        if (isDouble || isSingle || isSliding) {
          showZoneMenu = true;
          bool isRight = isDouble && (pos.dx > z.boundary.center.dx);
          Rect sashR = z.boundary;
          if (isDouble) {
            final sep = 4.0;
            sashR = isRight
                ? Rect.fromLTRB(
                    z.boundary.center.dx + sep / 2,
                    z.boundary.top,
                    z.boundary.right,
                    z.boundary.bottom,
                  )
                : Rect.fromLTRB(
                    z.boundary.left,
                    z.boundary.top,
                    z.boundary.center.dx - sep / 2,
                    z.boundary.bottom,
                  );
          }
          final thicknessFactor = z.isSash105 ? 0.14 : 0.10;
          final sashT = math.min(sashR.width, sashR.height) * thicknessFactor;
          final glassR = sashR.deflate(sashT);
          if (glassR.contains(pos)) {
            int currentInnerH = isRight ? z.rightInnerH : z.innerH;
            int currentInnerV = isRight ? z.rightInnerV : z.innerV;
            double cellW = glassR.width / (currentInnerV + 1);
            double cellH = glassR.height / (currentInnerH + 1);
            int col = ((pos.dx - glassR.left) / cellW)
                .clamp(0, currentInnerV)
                .toInt();
            int row = ((pos.dy - glassR.top) / cellH)
                .clamp(0, currentInnerH)
                .toInt();
            String sidePrefix = isDouble
                ? (isRight ? 'right' : 'left')
                : 'main';
            activeSubZone = '${sidePrefix}_cell_${row}_$col';
          } else {
            activeSubZone = (isLongPress && isDouble)
                ? 'all'
                : (isDouble ? (isRight ? 'right' : 'left') : 'main');
          }
        } else {
          showZoneMenu = true;
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
    final sep = t / 2;
    double newPos = oldPos;
    if (isH) {
      newPos = (section == 1)
          ? newVal + (t * 1.5)
          : height - newVal - (t * 1.5);

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
      newPos = (section == 1) ? newVal + (t * 1.5) : width - newVal - (t * 1.5);

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

  void toggleSelectedCellPanel() {
    if (selectedZone == null) return;
    _saveSnapshot();
    final zone = selectedZone!;
    if (activeSubZone != null && activeSubZone!.contains('cell_')) {
      bool isCurrentlyPanel = zone.cellIsPanel[activeSubZone!] ?? false;
      Map<String, bool> updatedCells = Map.from(zone.cellIsPanel);
      updatedCells[activeSubZone!] = !isCurrentlyPanel;
      zone.cellIsPanel = updatedCells;
    } else if (zone.content == ZoneContent.empty ||
        zone.content == ZoneContent.fixedGlass) {
      if (zone.glass.structure == GlassStructure.closed) {
        zone.glass = zone.glass.copyWith(structure: GlassStructure.simple);
      } else {
        zone.content = ZoneContent.fixedGlass;
        zone.glass = zone.glass.copyWith(
          structure: GlassStructure.closed,
          finishInner: GlassFinish.paneauSandwitch,
          colorP: ClosedGlassColor.white,
        );
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

  DimensionTap checkOuterDimensionTap(Offset pos) {
    if (Rect.fromLTRB(0, -300, width, -50).contains(pos)) {
      return DimensionTap.width;
    }
    if (Rect.fromLTRB(-300, 0, -50, height).contains(pos)) {
      return DimensionTap.height;
    }
    return DimensionTap.none;
  }

  InnerDimensionHit? checkInnerDimensionTap(Offset pos) {
    for (var z in zones) {
      final r = z.boundary;
      if (r.width < 150 || r.height < 150) continue;
      bool isFullWidth = (r.width >= width - profileThickness * 2 - 2);
      bool isFullHeight = (r.height >= height - profileThickness * 2 - 2);
      if (!isFullWidth) {
        if (Rect.fromCenter(
          center: Offset(r.center.dx, r.top + 20),
          width: 150,
          height: 80,
        ).contains(pos)) {
          return InnerDimensionHit(z.id, true);
        }
      }
      if (!isFullHeight) {
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
    if (zones.isEmpty) {
      zones.add(
        WindowZone(
          id: UniqueKey().toString(),
          boundary: Rect.fromLTRB(
            profileThickness,
            profileThickness,
            newW - profileThickness,
            newH - profileThickness,
          ),
        ),
      );
      width = newW;
      height = newH;
      notifyListeners();
      return;
    }

    double oldInnerW = width - (profileThickness * 2);
    double oldInnerH = height - (profileThickness * 2);
    double newInnerW = newW - (profileThickness * 2);
    double newInnerH = newH - (profileThickness * 2);
    double scaleX = newInnerW / oldInnerW;
    double scaleY = newInnerH / oldInnerH;

    for (var z in zones) {
      double left =
          profileThickness + (z.boundary.left - profileThickness) * scaleX;
      double top =
          profileThickness + (z.boundary.top - profileThickness) * scaleY;
      double right =
          profileThickness + (z.boundary.right - profileThickness) * scaleX;
      double bottom =
          profileThickness + (z.boundary.bottom - profileThickness) * scaleY;
      z.boundary = Rect.fromLTRB(left, top, right, bottom);
    }
    width = newW;
    height = newH;
    notifyListeners();
  }

  double getMaxAllowedInnerSize(String zoneId, bool isWidth) {
    final zIdx = zones.indexWhere((z) => z.id == zoneId);
    if (zIdx == -1) return 0;
    final r = zones[zIdx].boundary;

    if (isWidth) {
      if ((r.right - width).abs() < 2) {
        double oldX = r.left;
        double minAllowedX = 50;
        for (var z in zones) {
          if ((z.boundary.right - oldX).abs() < 2) {
            if (z.boundary.left + 50 > minAllowedX) {
              minAllowedX = z.boundary.left + 50;
            }
          }
        }
        return r.width + (oldX - minAllowedX);
      } else {
        double oldX = r.right;
        double maxAllowedX = width - 50;
        for (var z in zones) {
          if ((z.boundary.left - oldX).abs() < 2) {
            if (z.boundary.right - 50 < maxAllowedX) {
              maxAllowedX = z.boundary.right - 50;
            }
          }
        }
        return r.width + (maxAllowedX - oldX);
      }
    } else {
      if ((r.bottom - height).abs() < 2) {
        double oldY = r.top;
        double minAllowedY = 50;
        for (var z in zones) {
          if ((z.boundary.bottom - oldY).abs() < 2) {
            if (z.boundary.top + 50 > minAllowedY) {
              minAllowedY = z.boundary.top + 50;
            }
          }
        }
        return r.height + (oldY - minAllowedY);
      } else {
        double oldY = r.bottom;
        double maxAllowedY = height - 50;
        for (var z in zones) {
          if ((z.boundary.top - oldY).abs() < 2) {
            if (z.boundary.bottom - 50 < maxAllowedY) {
              maxAllowedY = z.boundary.bottom - 50;
            }
          }
        }
        return r.height + (maxAllowedY - oldY);
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

      if ((r.right - width).abs() < 2) {
        _moveInternalBoundaryX(r.left, -diff);
      } else {
        _moveInternalBoundaryX(r.right, diff);
      }
    } else {
      double diff = newVal - r.height;
      if (diff == 0) return;
      if (newVal > height - 50) diff = (height - 50) - r.height;

      if ((r.bottom - height).abs() < 2) {
        _moveInternalBoundaryY(r.top, -diff);
      } else {
        _moveInternalBoundaryY(r.bottom, diff);
      }
    }

    notifyListeners();
  }

  void _moveInternalBoundaryX(double oldX, double diff) {
    double minAllowedX = 50;
    double maxAllowedX = width - 50;
    for (var z in zones) {
      if ((z.boundary.right - oldX).abs() < 2) {
        if (z.boundary.left + 50 > minAllowedX) {
          minAllowedX = z.boundary.left + 50;
        }
      } else if ((z.boundary.left - oldX).abs() < 2) {
        if (z.boundary.right - 50 < maxAllowedX) {
          maxAllowedX = z.boundary.right - 50;
        }
      }
    }
    double newX = oldX + diff;
    if (newX < minAllowedX) newX = minAllowedX;
    if (newX > maxAllowedX) newX = maxAllowedX;
    double actualDiff = newX - oldX;

    for (int i = 0; i < zones.length; i++) {
      var z = zones[i];
      if ((z.boundary.right - oldX).abs() < 2) {
        z.boundary = Rect.fromLTRB(
          z.boundary.left,
          z.boundary.top,
          z.boundary.right + actualDiff,
          z.boundary.bottom,
        );
      } else if ((z.boundary.left - oldX).abs() < 2) {
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
    double minAllowedY = 50;
    double maxAllowedY = height - 50;
    for (var z in zones) {
      if ((z.boundary.bottom - oldY).abs() < 2) {
        if (z.boundary.top + 50 > minAllowedY) {
          minAllowedY = z.boundary.top + 50;
        }
      } else if ((z.boundary.top - oldY).abs() < 2) {
        if (z.boundary.bottom - 50 < maxAllowedY) {
          maxAllowedY = z.boundary.bottom - 50;
        }
      }
    }
    double newY = oldY + diff;
    if (newY < minAllowedY) newY = minAllowedY;
    if (newY > maxAllowedY) newY = maxAllowedY;
    double actualDiff = newY - oldY;

    for (int i = 0; i < zones.length; i++) {
      var z = zones[i];
      if ((z.boundary.bottom - oldY).abs() < 2) {
        z.boundary = Rect.fromLTRB(
          z.boundary.left,
          z.boundary.top,
          z.boundary.right,
          z.boundary.bottom + actualDiff,
        );
      } else if ((z.boundary.top - oldY).abs() < 2) {
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
      zone.cellIsPanel.removeWhere((key, value) => key.startsWith('right'));
    } else if (activeSubZone != null && activeSubZone!.startsWith('left')) {
      zone.innerH = 0;
      zone.innerV = 0;
      zone.cellIsPanel.removeWhere((key, value) => key.startsWith('left'));
    } else {
      zone.innerH = 0;
      zone.innerV = 0;
      zone.rightInnerH = 0;
      zone.rightInnerV = 0;
      zone.cellIsPanel.clear();
    }
    notifyListeners();
  }

  void splitSelectedZoneHorizontal({
    int parts = 2,
    List<double>? customSizes,
    bool fromTop = true,
  }) {
    if (selectedZone == null) return;
    _saveSnapshot();
    final zone = selectedZone!;
    // Allow sashes to be split just like fixed frames.
    final index = zones.indexOf(zone);
    final sep = profileThickness / 2;
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
              sashColor: _frameColor,
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
              sashColor: _frameColor,
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
              sashColor: _frameColor,
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
              sashColor: _frameColor,
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
              sashColor: _frameColor,
            ),
          );
        } else {
          zones.insert(index, zone);
        }
      }
    } else {
      double stepY = zone.boundary.height / parts;
      for (int i = 0; i < parts; i++) {
        double top = zone.boundary.top + (i * stepY);
        if (i > 0) top += sep;
        double bottom = zone.boundary.top + ((i + 1) * stepY);
        if (i < parts - 1) bottom -= sep;
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
            sashColor: _frameColor,
          ),
        );
      }
    }
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
    // Allow sashes to be split just like fixed frames.
    final index = zones.indexOf(zone);
    final sep = profileThickness / 2;
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
              sashColor: _frameColor,
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
              sashColor: _frameColor,
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
              sashColor: _frameColor,
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
              sashColor: _frameColor,
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
              sashColor: _frameColor,
            ),
          );
        } else {
          zones.insert(index, zone);
        }
      }
    } else {
      double stepX = zone.boundary.width / parts;
      for (int i = 0; i < parts; i++) {
        double left = zone.boundary.left + (i * stepX);
        if (i > 0) left += sep;
        double right = zone.boundary.left + ((i + 1) * stepX);
        if (i < parts - 1) right -= sep;
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
            sashColor: _frameColor,
          ),
        );
      }
    }
    selection = SelectionInfo.none;
    showZoneMenu = false;
    activeSubZone = null;
    notifyListeners();
  }

  void toggleDrawingMode() {
    isDrawingMode = !isDrawingMode;
    notifyListeners();
  }

  void toggleViewMode() {
    isInternalView = !isInternalView;
    notifyListeners();
  }

  void toggleBottomFrame(bool value) {
    _saveSnapshot();
    hasBottomFrame = value;
    notifyListeners();
  }

  void toggleShutter(bool value) {
    _saveSnapshot();
    hasShutter = value;
    if (!value) removedShutterSides.clear();
    notifyListeners();
  }

  void setShutterPosition(double val) {
    shutterPosition = val;
    notifyListeners();
  }

  void toggleSideCovers(bool value) {
    _saveSnapshot();
    hasSideCovers = value;
    notifyListeners();
  }

  void toggleFrameType() {
    _saveSnapshot();
    isFrame140 = !isFrame140;
    _updateProfileThickness();
    notifyListeners();
  }

  void _updateProfileThickness() {
    double oldThickness = profileThickness;
    if (activeSeries != null && activeSeries!.sections.isNotEmpty) {
      final frames = activeSeries!.sections.where((s) => s.type == 'frame').toList();
      if (frames.isNotEmpty) {
        AluminumSection? targetFrame;
        if (isFrame140) {
          targetFrame = frames.firstWhere(
            (s) => s.name.contains('140') || s.code.contains('140'),
            orElse: () => frames.first,
          );
        } else {
          targetFrame = frames.firstWhere(
            (s) => s.name.contains('103') || s.code.contains('103'),
            orElse: () => frames.first,
          );
        }
        if (targetFrame.thickness > 0) {
          profileThickness = targetFrame.thickness;
        } else {
          profileThickness = isFrame140 ? 70.0 : 40.0;
        }
      } else {
        profileThickness = isFrame140 ? 70.0 : 40.0;
      }
    } else {
      profileThickness = isFrame140 ? 70.0 : 40.0;
    }
    
    if (oldThickness != profileThickness) {
      for (var z in zones) {
        z.boundary = Rect.fromLTRB(
          z.boundary.left == oldThickness ? profileThickness : z.boundary.left,
          z.boundary.top == oldThickness ? profileThickness : z.boundary.top,
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
    selectedZone!.slidingSashesCount = count;
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
    selectedZone!.cellIsPanel.clear();
    if (content == ZoneContent.doubleSash ||
        content == ZoneContent.singleSash) {
      selectedZone!.openDirection = OpenDirection.right;
    } else {
      selectedZone!.openDirection = null;
    }
    notifyListeners();
  }

  void updateSelectedZoneGlass({
    GlassStructure? structure,
    GlassFinish? finishOuter,
    GlassFinish? finishInner,
    GlassColor? colorOuter,
    GlassColor? colorInner,
    GlassProcessing? processingOuter,
    GlassProcessing? processingInner,
    ClosedGlassColor? colorP,
  }) {
    if (selectedZone == null) return;
    _saveSnapshot();
    selectedZone!.glass = selectedZone!.glass.copyWith(
      structure: structure,
      finishOuter: finishOuter,
      finishInner: finishInner,
      colorOuter: colorOuter,
      colorInner: colorInner,
      processingOuter: processingOuter,
      processingInner: processingInner,
      colorP: colorP,
    );
    notifyListeners();
  }

  void setSelectedZoneOpenDirection(OpenDirection dir) {
    if (selectedZone == null) return;
    _saveSnapshot();
    selectedZone!.openDirection = dir;
    notifyListeners();
  }

  void toggleSashType104105() {
    if (selectedZone == null) return;
    _saveSnapshot();
    selectedZone!.isSash105 = !selectedZone!.isSash105;
    notifyListeners();
  }

  void startDrawing(Offset pos) {
    drawingStart = pos;
    drawingCurrent = pos;
    notifyListeners();
  }

  void updateDrawing(Offset pos) {
    drawingCurrent = pos;
    notifyListeners();
  }

  void endDrawing() {
    if (drawingStart == null || drawingCurrent == null) return;
    _saveSnapshot();

    // 🟢 1. إذا كانت الشاشة فارغة (لا يوجد إطارات)، الإصبع يرسم الإطار الخارجي الأول
    if (zones.isEmpty) {
      Rect drawnRect = Rect.fromPoints(drawingStart!, drawingCurrent!);

      // التأكد من أن السحب ليس مجرد لمسة خاطئة صغيرة
      if (drawnRect.width > 50 && drawnRect.height > 50) {
        // نأخذ نسبة الطول والعرض التي رسمها الحرفي بيده
        double aspect = drawnRect.width / drawnRect.height;

        // نعطي الإطار مقاساً افتراضياً منطقياً (مثلا 1500 ملم) كبداية
        height = 1500.0;
        width = height * aspect;

        zones.add(
          WindowZone(
            id: UniqueKey().toString(),
            boundary: Rect.fromLTRB(
              profileThickness,
              profileThickness,
              width - profileThickness,
              height - profileThickness,
            ),
          ),
        );
      }
      drawingStart = null;
      drawingCurrent = null;
      notifyListeners();
      return;
    }

    // 🟢 2. إذا كان الإطار موجوداً، فالإصبع يقوم بتقطيعه (منطقك القديم يعمل كالسحر)
    double dx = drawingCurrent!.dx - drawingStart!.dx;
    double dy = drawingCurrent!.dy - drawingStart!.dy;
    if (dx.abs() > 2 || dy.abs() > 2) {
      if (dx.abs() > dy.abs()) {
        _splitIntersectingZonesSmart(drawingStart!, drawingCurrent!, true);
      } else {
        _splitIntersectingZonesSmart(drawingStart!, drawingCurrent!, false);
      }
    }
    drawingStart = null;
    drawingCurrent = null;
    notifyListeners();
  }

  void _splitIntersectingZonesSmart(Offset start, Offset end, bool horizontal) {
    _saveSnapshot();
    final List<WindowZone> newZones = [];
    final sep = profileThickness / 2;
    double minPath = horizontal
        ? math.min(start.dx, end.dx)
        : math.min(start.dy, end.dy);
    double maxPath = horizontal
        ? math.max(start.dx, end.dx)
        : math.max(start.dy, end.dy);
    double cutLine = horizontal ? start.dy : start.dx;

    for (var z in zones) {
      // Allowed splitting sashes just like fixed glass
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
            ),
          );
        }
      } else {
        newZones.add(z);
      }
    }
    zones = newZones;
  }

  // 🟢 دالة تحريك التقسيم (العمود) مع خصم سمك الألمنيوم لمنع التداخل
  void moveSelectedMullion(double deltaPixels) {
    if (selection.type != SelectionType.mullion ||
        selection.mullionPosition == null) {
      return;
    }
    _saveSnapshot();

    bool isH = selection.isHorizontalMullion!;
    double pos = selection.mullionPosition!;
    final sep = profileThickness / 2;

    if (isH) {
      for (var z in zones) {
        if ((z.boundary.bottom - (pos - sep)).abs() < 2) {
          z.boundary = Rect.fromLTRB(
            z.boundary.left,
            z.boundary.top,
            z.boundary.right,
            z.boundary.bottom + deltaPixels,
          );
        } else if ((z.boundary.top - (pos + sep)).abs() < 2) {
          z.boundary = Rect.fromLTRB(
            z.boundary.left,
            z.boundary.top + deltaPixels,
            z.boundary.right,
            z.boundary.bottom,
          );
        }
      }
      selection = SelectionInfo(
        type: SelectionType.mullion,
        isHorizontalMullion: isH,
        mullionPosition: pos + deltaPixels,
      );
    } else {
      for (var z in zones) {
        if ((z.boundary.right - (pos - sep)).abs() < 2) {
          z.boundary = Rect.fromLTRB(
            z.boundary.left,
            z.boundary.top,
            z.boundary.right + deltaPixels,
            z.boundary.bottom,
          );
        } else if ((z.boundary.left - (pos + sep)).abs() < 2) {
          z.boundary = Rect.fromLTRB(
            z.boundary.left + deltaPixels,
            z.boundary.top,
            z.boundary.right,
            z.boundary.bottom,
          );
        }
      }
      selection = SelectionInfo(
        type: SelectionType.mullion,
        isHorizontalMullion: isH,
        mullionPosition: pos + deltaPixels,
      );
    }
    notifyListeners();
  }

  // 🟢 دالة تغيير نوع وشكل قطاع التقسيم (العمود/التيار)
  void setMullionProfile(MullionProfileType type) {
    if (selection.type != SelectionType.mullion ||
        selection.mullionPosition == null) {
      return;
    }

    _saveSnapshot();

    // إنشاء مفتاح فريد للعمود بناءً على اتجاهه ومكانه
    String key =
        "${selection.isHorizontalMullion! ? 'H' : 'V'}_${selection.mullionPosition!.toStringAsFixed(1)}";

    // حفظ النوع الجديد في السجل
    mullionProfiles[key] = type;

    notifyListeners();
  }

  // 🟢 دالة حذف التقسيم (العمود/التيار) المحدد ودمج الفراغات مجدداً
  void deleteSelectedMullion() {
    if (selection.type != SelectionType.mullion ||
        selection.mullionPosition == null) {
      return;
    }

    _saveSnapshot();

    bool isH = selection.isHorizontalMullion!;
    double pos = selection.mullionPosition!;
    final sep = profileThickness / 2; // أخذ نصف سمك الألمنيوم في الحسبان

    final List<WindowZone> toMerge = [];
    final List<WindowZone> others = [];

    // البحث عن المربعات الزجاجية الملاصقة للعمود من الجهتين
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

    if (toMerge.length < 2) return; // إلغاء إذا لم يجد مربعات لدمجها

    // دمج المربعات في مربع زجاجي واحد كبير
    double minX = toMerge.map((z) => z.boundary.left).reduce(math.min);
    double minY = toMerge.map((z) => z.boundary.top).reduce(math.min);
    double maxX = toMerge.map((z) => z.boundary.right).reduce(math.max);
    double maxY = toMerge.map((z) => z.boundary.bottom).reduce(math.max);

    others.add(
      WindowZone(
        id: UniqueKey().toString(),
        boundary: Rect.fromLTRB(minX, minY, maxX, maxY),
        sashColor: _frameColor,
      ),
    );

    zones = others;
    selection = SelectionInfo.none;

    // مسح نوع البروفايل المحفوظ لهذا العمود
    String key = "${isH ? 'H' : 'V'}_${pos.toStringAsFixed(1)}";
    mullionProfiles.remove(key);

    notifyListeners();
  }

  // 🟢 دالة لمسح الشاشة بالكامل والعودة لنقطة الصفر
  void clearAll() {
    _saveSnapshot(); // نحفظ اللقطة لكي يتمكن من التراجع (Undo) إذا مسح بالخطأ
    zones.clear(); // نحذف كل المربعات
    width = 0; // نصفّر العرض
    height = 0; // نصفّر الارتفاع
    mullionProfiles.clear(); // نحذف أي إعدادات لأعمدة التقسيم
    selection = SelectionInfo.none;
    activeSubZone = null;
    isDrawingMode = true; // نُعيد تفعيل وضع الرسم تلقائياً ليرسم من جديد
    notifyListeners();
  }
}

// في نهاية ملف model.dart، خارج أي كلاس
class PlacedFrame {
  WindowModel model;
  Offset position;

  PlacedFrame({required this.model, required this.position});
}
