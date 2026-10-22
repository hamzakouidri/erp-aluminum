// Force compile sync trigger 2
import 'dart:math' as math;
import 'dart:async';
import 'glass_joint_fit.dart';
import 'profile_selector_dialog.dart'
    show
        CatalogCandidateResolver,
        CatalogCandidateQuery,
        AccessoryDrawingMode,
        profileHasIntegratedSideCover;
import 'package:flutter/material.dart';
import 'package:database_data/settings/app_settings.dart' show AppLanguage;
import '../../sql_database.dart';
import 'package:database_data/utils/real_color_resolver.dart';
import 'slanted_division.dart';
import 'corner_notch.dart';
import 'sash_hinges.dart';

export 'slanted_division.dart';
export 'sash_hinges.dart';

part 'model/history.dart';
part 'model/shutter.dart';
part 'model/glazing.dart';
part 'model/sliding.dart';
part 'model/frame.dart';
part 'model/zones.dart';
part 'model/catalog.dart';
part 'model/corner_notches.dart';
part 'model/double_frame_gap.dart';
part 'model/accessory_choice.dart';

enum DimensionTap { none, width, height }

/// One outer dimension label as it was last painted (model coordinates).
/// [key] says what a tap edits; [dragKey] names the row of dimensions that a
/// drag moves along [normal], which points away from the frame.
class DimensionLabelHit {
  final String key;
  final String dragKey;
  final Rect rect;
  final Offset normal;

  const DimensionLabelHit(this.key, this.dragKey, this.rect, this.normal);
}

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

/// أوضاع الأعمدة المدعمة (Renfort des montants)
enum ReinforcementMode {
  /// القسم الأول: تتغير القطاعات كلياً من العمود العادي إلى المدعم
  fullSubstitution,

  /// القسم الثاني: شيكان مدعمة + شيكان عادية في نقطة الالتقاء المركزية
  chicaneCombination,

  /// القسم الثالث: أعمدة مدعمة مستقلة تركب ببراغي فوق القطاعات ولها أغطية
  independentScrewed,
}

/// الأنظمة الجاهزة للرسم السريع (Preset Window Templates)
enum WindowPresetType {
  /// نافذة بدون ستار (مفصلية، دلفة أو دلفتين حسب العرض)
  windowNoShutter,

  /// نافذة مع ستار (مفصلية مع صندوق الستار المتراكب)
  windowWithShutter,

  /// نافذة جرارة بدون ستار (منزلقة بضلفتين)
  slidingNoShutter,

  /// نافذة جرارة مع الستار (منزلقة بضلفتين مع صندوق الستار)
  slidingWithShutter,

  /// باب بضلفة واحدة وقفل بمفتاح (ضلفة 105، بدون إطار سفلي)
  singleDoor,

  /// باب بضلفتين وقفل بمفتاح (ضلفتين 105، بدون إطار سفلي)
  doubleDoor,

  /// ستار وحده (صندوق وشفرات الستار فقط)
  shutterOnly,

  /// نافذة صغيرة تفتح من الأعلى (قلاب / Soufflet)
  topOpeningSmallWindow,
}

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

/// Represents one independent section of a split shutter box / curtain.
class ShutterSplitSection {
  final double width;
  final double leftOffset;
  final double? customHeight;
  final String label;
  final int? frameIndex;
  final String? mechanism;
  final String? driveSide;

  const ShutterSplitSection({
    required this.width,
    required this.leftOffset,
    this.customHeight,
    this.label = '',
    this.frameIndex,
    this.mechanism,
    this.driveSide,
  });

  Map<String, dynamic> toMap() => {
    'width': width,
    'leftOffset': leftOffset,
    'customHeight': customHeight,
    'label': label,
    'frameIndex': frameIndex,
    'mechanism': mechanism,
    'driveSide': driveSide,
  };

  factory ShutterSplitSection.fromMap(Map<String, dynamic> map) =>
      ShutterSplitSection(
        width: (map['width'] as num?)?.toDouble() ?? 0.0,
        leftOffset: (map['leftOffset'] as num?)?.toDouble() ?? 0.0,
        customHeight: (map['customHeight'] as num?)?.toDouble(),
        label: map['label']?.toString() ?? '',
        frameIndex: (map['frameIndex'] as num?)?.toInt(),
        mechanism: map['mechanism']?.toString(),
        driveSide: map['driveSide']?.toString(),
      );

  ShutterSplitSection copyWith({
    double? width,
    double? leftOffset,
    double? customHeight,
    String? label,
    int? frameIndex,
    String? mechanism,
    String? driveSide,
  }) {
    return ShutterSplitSection(
      width: width ?? this.width,
      leftOffset: leftOffset ?? this.leftOffset,
      customHeight: customHeight ?? this.customHeight,
      label: label ?? this.label,
      frameIndex: frameIndex ?? this.frameIndex,
      mechanism: mechanism ?? this.mechanism,
      driveSide: driveSide ?? this.driveSide,
    );
  }
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
      RegExp(r'با?را?دا?[جش]').hasMatch(normalized);
}

bool decorPanelFitsSpace({
  required double spaceWidth,
  required double spaceHeight,
  required double decorWidth,
  required double decorHeight,
  double edgeClearance = 30.0,
}) {
  if (spaceWidth <= 0 ||
      spaceHeight <= 0 ||
      decorWidth <= 0 ||
      decorHeight <= 0) {
    return false;
  }
  // A decor drawing has a fixed orientation and must remain at least 30 mm
  // inside the usable opening on both axes. It is not rotated or split to
  // force it into a smaller opening.
  return decorWidth + edgeClearance <= spaceWidth + 0.1 &&
      decorHeight + edgeClearance <= spaceHeight + 0.1;
}

bool decorPanelSheetCoversSpace({
  required double spaceWidth,
  required double spaceHeight,
  required double panelWidth,
  required double panelHeight,
}) {
  if (spaceWidth <= 0 ||
      spaceHeight <= 0 ||
      panelWidth <= 0 ||
      panelHeight <= 0) {
    return false;
  }
  return panelWidth + 0.1 >= spaceWidth && panelHeight + 0.1 >= spaceHeight;
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

enum FrameColor {
  white,
  brown,
  gray,
  black,
  beige,
  gris,
  antique,
  lightWood,
  fauxBoisMarron,
}

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
/// Handle types of a sliding window, and the places a sliding window has a
/// handle: the left and right outer leaves and the central meeting (whose
/// two handles always share their type).
class SlidingHandleType {
  /// Flush aluminium handle with its lock (andromatic).
  static const entrematique = 'entrematique';

  /// Aluminium lever handle ("code" handle).
  static const classic = 'classic';

  /// Standard PVC window handle.
  static const pvcWindow = 'pvc_window';

  /// PVC recessed handle (poignée encastrée).
  static const encastree = 'encastree';

  static const values = [entrematique, classic, pvcWindow, encastree];

  static const left = 'left';
  static const right = 'right';
  static const center = 'center';
  static const slots = [left, right, center];

  /// Whether the type needs an espagnolette (every type but the
  /// entrematique, which carries its own lock).
  static bool needsEspagnolette(String type) => type != entrematique;

  /// The accessory line of the type in the quantity and cost table.
  static String accessoryKey(String type) => switch (type) {
    entrematique => 'أونتروماتيك (Entrematique)',
    pvcWindow => 'مقبض نافذة (Poignée Fenêtre)',
    encastree => 'مقبض مدمج (Poignée Encastrée)',
    _ => 'مقبض منزلق (Poignée Coulissante)',
  };

  /// The type of a catalogue handle from its rule role.
  static String fromRole(String? roleKey, {required bool pvc}) =>
      switch (roleKey) {
        'entrematique' => entrematique,
        'poignee_encastree' => encastree,
        _ => pvc ? pvcWindow : classic,
      };
}

class FrameEdgeSegment {
  final String side;
  final double start;
  final double end;
  final double coordinate;
  final Rect? frameRect;

  const FrameEdgeSegment({
    required this.side,
    required this.start,
    required this.end,
    required this.coordinate,
    this.frameRect,
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

class CadreDoubleRainureSegment {
  final bool isHorizontal;
  final double position;
  final double start;
  final double end;
  final bool usesSlidingSeries;

  const CadreDoubleRainureSegment({
    required this.isHorizontal,
    required this.position,
    required this.start,
    required this.end,
    required this.usesSlidingSeries,
  });

  double get length => math.max(0.0, end - start);
}

class FrameAngleJunction {
  final int index;
  final int firstFrameIndex;
  final int secondFrameIndex;
  final Rect firstFrame;
  final Rect secondFrame;
  final double x;
  final double top;
  final double bottom;

  const FrameAngleJunction({
    required this.index,
    required this.firstFrameIndex,
    required this.secondFrameIndex,
    required this.firstFrame,
    required this.secondFrame,
    required this.x,
    required this.top,
    required this.bottom,
  });

  double get height => (bottom - top).abs();

  String get label =>
      'بين الإطار ${firstFrameIndex + 1} و ${secondFrameIndex + 1}';

  String localizedLabel(AppLanguage lang) {
    switch (lang) {
      case AppLanguage.french:
        return 'Entre cadre ${firstFrameIndex + 1} et ${secondFrameIndex + 1}';
      case AppLanguage.arabic:
        return 'بين الإطار ${firstFrameIndex + 1} و ${secondFrameIndex + 1}';
      default:
        return 'Between frame ${firstFrameIndex + 1} and ${secondFrameIndex + 1}';
    }
  }
}

/// Which aluminium parclose cuts a catalogue parclose takes
/// (`Sections.parclose_cut_support` and `Sections.parclose_default_cut`).
/// The defaults keep the former behaviour: every cut, 45° first.
class ParcloseCutRule {
  static const List<String> modes = ['45', '90_length', '90_width'];

  /// `both`, `45` (45° only) or `90` (90° only).
  final String support;

  /// The cut a new drawing starts with: one of [modes].
  final String defaultMode;

  const ParcloseCutRule({this.support = 'both', this.defaultMode = '45'});

  factory ParcloseCutRule.fromMap(Map<dynamic, dynamic> map) {
    final support = map['parclose_cut_support']?.toString().trim();
    final defaultMode = map['parclose_default_cut']?.toString().trim();
    return ParcloseCutRule(
      support: const {'45', '90'}.contains(support) ? support! : 'both',
      defaultMode: modes.contains(defaultMode) ? defaultMode! : '45',
    );
  }

  List<String> get allowedModes => switch (support) {
    '45' => const ['45'],
    '90' => [defaultMode == '90_width' ? '90_width' : '90_length'],
    _ => modes,
  };

  /// A single allowed cut: nothing to choose in the drawing.
  bool get isFixed => allowedModes.length == 1;

  String get initialMode =>
      allowedModes.contains(defaultMode) ? defaultMode : allowedModes.first;

  /// [mode] when this parclose takes it, otherwise [initialMode].
  String resolve(String? mode) =>
      allowedModes.contains(mode) ? mode! : initialMode;

  Map<String, dynamic> toMap() => {
    'parclose_cut_support': support,
    'parclose_default_cut': defaultMode,
  };

  @override
  bool operator ==(Object other) =>
      other is ParcloseCutRule &&
      other.support == support &&
      other.defaultMode == defaultMode;

  @override
  int get hashCode => Object.hash(support, defaultMode);
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
  final ParcloseCutRule parcloseCutRule;
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
    this.parcloseCutRule = const ParcloseCutRule(),
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

    // Saved overrides (older orders, manual choices) can lack catalogue
    // columns; reading them must not stop the whole BOM with a type error.
    int readInt(Object? value) => value is num
        ? value.toInt()
        : int.tryParse(value?.toString() ?? '') ?? 0;
    String readText(Object? value) => value?.toString() ?? '';

    return AluminumSection(
      id: readInt(map['id']),
      seriesId: readInt(map['series_id'] ?? map['source_series_id']),
      code: readText(map['code']),
      name: readText(map['name']),
      type: readText(map['type']),
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
      parcloseCutRule: ParcloseCutRule.fromMap(map),
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
      ...parcloseCutRule.toMap(),
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

  /// True when the series rules include a face_to_face role, meaning the two
  /// central sashes are expected to meet face-to-face when drawn.  Drawings
  /// that use this series will auto-enable slidingFaceToFace on their sliding
  /// zones (unless the user explicitly overrides it).
  final bool hasFaceToFace;
  final String? reinforcementType;
  List<AluminumSection> sections;

  AluminumSeries({
    required this.id,
    required this.profileId,
    required this.name,
    required this.type,
    this.hasThreePieceSash = false,
    this.hasFaceToFace = false,
    this.reinforcementType,
    List<AluminumSection>? sections,
  }) : sections = sections ?? [];

  factory AluminumSeries.fromMap(Map<String, dynamic> map) {
    return AluminumSeries(
      id: map['id'],
      profileId: map['profile_id'],
      name: map['name'],
      type: map['type'],
      hasThreePieceSash: (map['has_three_piece_sash'] ?? 0) == 1,
      hasFaceToFace: (map['has_face_to_face'] ?? 0) == 1,
      reinforcementType: map['reinforcement_type']?.toString(),
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
  // Opening series (e.g. TPR EX45, EX 60, Ouvrant, Frappe, etc.) must NEVER be
  // classified as sliding, even if manufactured by TPR or stored with "Aluminium" in type.
  if (value.contains('ouvrant') ||
      value.contains('frappe') ||
      value.contains('battant') ||
      value.contains('فتح') ||
      value.contains('فرنسي') ||
      RegExp(r'\bex\s*-?\s*\d+').hasMatch(value)) {
    return false;
  }
  return value.contains('couliss') ||
      value.contains('sliding') ||
      value.contains('منزلق') ||
      value.contains('جرار') ||
      value.contains('كوليس') ||
      value.contains('67000') ||
      value.contains('40000') ||
      value.contains('76000') ||
      value.contains('tpi') ||
      value.contains('hps') ||
      (value.contains('tpr') &&
          (value.contains('67') ||
              value.contains('40') ||
              value.contains('76') ||
              value.contains('couliss') ||
              value.contains('sliding') ||
              value.contains('منزلق') ||
              value == 'tpr'));
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
  final isOpening =
      value.contains('frappe') ||
      value.contains('battant') ||
      value.contains('ouvrant') ||
      value.contains('فتح') ||
      value.contains('فرنسي') ||
      RegExp(r'\bex\s*-?\s*\d+').hasMatch(value);
  if (isOpening) return true;

  // A mixed system must never offer the same series in both selectors. Some
  // legacy names contain both opening and sliding words, so sliding wins.
  if (isSlidingSeriesForDrawing(series)) return false;

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

/// One glass cell of a divided zone as drawn: [key] is its top-left grid
/// cell ('main_cell_0_1', 'left_cell_1_0'...), spanning [hSpan] rows and
/// [wSpan] columns when divisions are removed between grid cells.
class DrawnGlassCell {
  final String key;
  final int row;
  final int col;
  final int hSpan;
  final int wSpan;
  final Rect rect;

  const DrawnGlassCell({
    required this.key,
    required this.row,
    required this.col,
    required this.hSpan,
    required this.wSpan,
    required this.rect,
  });

  /// Whether [subZone] (a tapped cell key) falls inside this cell.
  bool covers(String subZone) {
    if (subZone == key) return true;
    final prefix = key.substring(0, key.indexOf('_cell_') + '_cell_'.length);
    if (!subZone.startsWith(prefix)) return false;
    final parts = subZone.substring(prefix.length).split('_');
    if (parts.length != 2) return false;
    final r = int.tryParse(parts[0]);
    final c = int.tryParse(parts[1]);
    return r != null &&
        c != null &&
        r >= row &&
        r < row + hSpan &&
        c >= col &&
        c < col + wSpan;
  }
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
  final String? decorDesignCode;
  final int rosetteShape;
  final bool jointTwoSides;
  final List<Map<String, dynamic>> fittedJoints;
  final bool? glazingFitValid;

  /// The user picked this spacer explicitly. Automatic fitting then keeps it
  /// (and only reports an incompatibility) until the panes change.
  final bool manualIntercall;

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
    this.decorDesignCode,
    this.thicknessOuter,
    this.thicknessInner,
    this.laminatedColorOuter = 'transparent',
    this.laminatedColorInner = 'transparent',
    this.rosetteShape = 1,
    this.jointTwoSides = true,
    this.fittedJoints = const [],
    this.glazingFitValid,
    this.manualIntercall = false,
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
    decorDesignCode: decorDesignCode,
    thicknessOuter: thicknessOuter,
    thicknessInner: thicknessInner,
    laminatedColorOuter: laminatedColorOuter,
    laminatedColorInner: laminatedColorInner,
    rosetteShape: rosetteShape,
    jointTwoSides: jointTwoSides,
    fittedJoints: fittedJoints,
    glazingFitValid: glazingFitValid,
    manualIntercall: manualIntercall,
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
    String? decorDesignCode,
    double? thicknessOuter,
    double? thicknessInner,
    String? laminatedColorOuter,
    String? laminatedColorInner,
    int? rosetteShape,
    bool? jointTwoSides,
    List<Map<String, dynamic>>? fittedJoints,
    bool? glazingFitValid,
    bool? manualIntercall,
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
    decorDesignCode: decorDesignCode ?? this.decorDesignCode,
    thicknessOuter: thicknessOuter ?? this.thicknessOuter,
    thicknessInner: thicknessInner ?? this.thicknessInner,
    laminatedColorOuter: laminatedColorOuter ?? this.laminatedColorOuter,
    laminatedColorInner: laminatedColorInner ?? this.laminatedColorInner,
    rosetteShape: rosetteShape ?? this.rosetteShape,
    jointTwoSides: jointTwoSides ?? this.jointTwoSides,
    fittedJoints: fittedJoints ?? this.fittedJoints,
    glazingFitValid: glazingFitValid ?? this.glazingFitValid,
    manualIntercall: manualIntercall ?? this.manualIntercall,
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
        decorDesignCode == other.decorDesignCode &&
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
    // The thickness stored on the panel is used when the catalogue row is
    // not available (catalogue not loaded, product removed). Returning 0
    // chose the thinnest glazing bead for an 18 mm panel.
    final savedThickness =
        thicknessOuter != null && thicknessOuter! > 0 ? thicknessOuter! : 0.0;
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

      return savedThickness;
    }

    final match = allGlassCache.firstWhere(
      (g) => g['id'] == resolvedId,
      orElse: () => <String, dynamic>{},
    );
    if (match.isNotEmpty) {
      final double? thick = (match['thickness'] as num?)?.toDouble();
      if (thick != null && thick > 0) return thick;
    }

    return savedThickness;
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

  /// Positions of single sliding handles moved alone ('left', 'right',
  /// 'center', 'center2'); the others follow [handlePositionRatio].
  Map<String, double> handleRatios;

  double handleRatioFor(String key) =>
      handleRatios[key] ?? handlePositionRatio ?? 0.5;
  bool useClassicHandle;
  bool useOctoHandle;
  bool usePvcHandleOnAlu;

  /// PVC recessed handle (poignée encastrée) on an opening sash.
  bool useEncastreeHandle;
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
  Map<String, dynamic>? sashOverride;
  Map<String, dynamic>? slidingSashOverride;
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

  /// The handle type of each handle place of a sliding window
  /// ([SlidingHandleType.slots]). An empty map keeps [useClassicHandle].
  Map<String, String> slidingHandleTypes;
  double middleHingeDragOffset;

  /// Hinges the user placed by hand, by leaf: 0 for a single sash and for the
  /// leaf on the left seen from inside, 1 for the other leaf of a double
  /// sash. A missing leaf uses the automatic layout.
  Map<int, SashHingeLayout> customHinges;
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

  /// Straight mullions crossing this fixed zone at an angle. Their cells are
  /// keyed 'slant_cell_<i>' in [cellGlassSpec] (see SlantedDivisionGeometry).
  List<SlantedDivider> slantedDividers;

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
    Map<String, double>? handleRatios,
    this.useClassicHandle = false,
    this.useOctoHandle = false,
    this.usePvcHandleOnAlu = false,
    this.useEncastreeHandle = false,
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
    this.sashOverride,
    this.slidingSashOverride,
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
    Map<String, bool>? cellIsPanel,
    Map<String, bool>? cellIsSash,
    Map<String, bool>? cellIsDoubleSash,
    this.cellSashOverrides = const {},
    this.lockType = LockType.none,
    Map<String, bool>? slidingMontantReinforced,
    Map<String, bool>? slidingMontantSlim,
    Map<String, String>? slidingHandleTypes,
    this.middleHingeDragOffset = 0.0,
    this.doubleSashRatio = 0.5,
    this.doubleSashHasTwoHandles = false,
    bool? slidingFaceToFace,
    bool? slidingCentralHandle,
    bool? slidingSecondCentralHandle,
    this.disabledVerticalDivisions = const {},
    this.disabledHorizontalDivisions = const {},
    this.primaryDivisionAxis,
    this.rightPrimaryDivisionAxis,
    this.isSubdivided = false,
    this.hasSashPlintheBottom = false,
    Map<String, GlassSpecification>? cellGlassSpec,
    List<SlantedDivider>? slantedDividers,
    Map<int, SashHingeLayout>? customHinges,
  }) : handleRatios = handleRatios ?? {}, slantedDividers = List<SlantedDivider>.of(slantedDividers ?? const []),
       customHinges = Map<int, SashHingeLayout>.of(customHinges ?? const {}),
       slidingFaceToFace =
           slidingFaceToFace ??
           isSlidingFaceToFaceLayout(
             trackCount: slidingTrackCount,
             sashCount: slidingSashesCount,
           ),
       slidingCentralHandle =
           slidingCentralHandle ??
           (slidingFaceToFace ??
               isSlidingFaceToFaceLayout(
                 trackCount: slidingTrackCount,
                 sashCount: slidingSashesCount,
               )),
       slidingSecondCentralHandle =
           slidingSecondCentralHandle ??
           (slidingFaceToFace ??
               isSlidingFaceToFaceLayout(
                 trackCount: slidingTrackCount,
                 sashCount: slidingSashesCount,
               )),
       glass = glass ?? const GlassSpecification(),
       // Cell flags are edited in place (paintZoneContent clears them), so a
       // zone must never hold an unmodifiable const map.
       cellIsPanel = Map<String, bool>.from(cellIsPanel ?? const {}),
       cellIsSash = Map<String, bool>.from(cellIsSash ?? const {}),
       cellIsDoubleSash = Map<String, bool>.from(cellIsDoubleSash ?? const {}),
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
       ),
       slidingHandleTypes = Map<String, String>.from(
         slidingHandleTypes ?? const {},
       );

  WindowZone clone() => WindowZone(
    id: id,
    handlePositionRatio: handlePositionRatio,
    handleRatios: Map<String, double>.from(handleRatios),
    useClassicHandle: useClassicHandle,
    useOctoHandle: useOctoHandle,
    usePvcHandleOnAlu: usePvcHandleOnAlu,
    useEncastreeHandle: useEncastreeHandle,
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
    sashOverride: sashOverride == null
        ? null
        : Map<String, dynamic>.from(sashOverride!),
    slidingSashOverride: slidingSashOverride == null
        ? null
        : Map<String, dynamic>.from(slidingSashOverride!),
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
    slidingHandleTypes: Map.from(slidingHandleTypes),
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
    slantedDividers: slantedDividers,
    customHinges: customHinges,
  );

  /// Slanted divisions are not carried over: they belong to the geometry of
  /// the zone being split.
  WindowZone cloneForSplit(Rect newBoundary) => WindowZone(
    id: UniqueKey().toString(),
    handlePositionRatio: handlePositionRatio,
    handleRatios: Map<String, double>.from(handleRatios),
    useClassicHandle: useClassicHandle,
    slidingHandleTypes: Map.from(slidingHandleTypes),
    useOctoHandle: useOctoHandle,
    usePvcHandleOnAlu: usePvcHandleOnAlu,
    useEncastreeHandle: useEncastreeHandle,
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
    sashOverride: sashOverride == null
        ? null
        : Map<String, dynamic>.from(sashOverride!),
    slidingSashOverride: slidingSashOverride == null
        ? null
        : Map<String, dynamic>.from(slidingSashOverride!),
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
    bool? useEncastreeHandle,
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
    Map<String, dynamic>? sashOverride,
    Map<String, dynamic>? slidingSashOverride,
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
    Map<String, String>? slidingHandleTypes,
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
    List<SlantedDivider>? slantedDividers,
    Map<int, SashHingeLayout>? customHinges,
  }) => WindowZone(
    id: id,
    handlePositionRatio: handlePositionRatio ?? this.handlePositionRatio,
    handleRatios: Map<String, double>.from(this.handleRatios),
    useClassicHandle: useClassicHandle ?? this.useClassicHandle,
    useOctoHandle: useOctoHandle ?? this.useOctoHandle,
    usePvcHandleOnAlu: usePvcHandleOnAlu ?? this.usePvcHandleOnAlu,
    useEncastreeHandle: useEncastreeHandle ?? this.useEncastreeHandle,
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
    sashOverride:
        sashOverride ??
        (this.sashOverride != null
            ? Map<String, dynamic>.from(this.sashOverride!)
            : null),
    slidingSashOverride:
        slidingSashOverride ??
        (this.slidingSashOverride != null
            ? Map<String, dynamic>.from(this.slidingSashOverride!)
            : null),
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
    slidingHandleTypes: slidingHandleTypes ?? Map.from(this.slidingHandleTypes),
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
    slantedDividers: slantedDividers ?? this.slantedDividers,
    customHinges: customHinges ?? this.customHinges,
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
  final bool isShutterOnly;
  final String drawingMode;
  final bool drawNextShapeAsShutterOnly;
  final bool isDrawingMode;
  final bool hasSideCovers;
  final bool multiFrameSideCoverManuallyEnabled;
  final int profileAngleMode;
  final Set<int> profileAngleJunctions;
  final bool profileAngleJunctionsDisabled;
  final bool viewAs90DegreeCorner;
  final Map<String, dynamic>? frameOverride;
  final Map<String, dynamic>? slidingFrameOverride;
  final Map<String, dynamic>? sideCoverOverride;
  final AluminumSection? selectedSideCover;
  final Map<String, dynamic>? preProfileAngleFrameOverride;
  final Map<String, dynamic>? preProfileAngleSlidingOverride;
  final bool frameSwitchedForProfileAngle;
  final String? profileAngleFrameSwitchNotice;

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
    this.isShutterOnly = false,
    this.drawingMode = '',
    this.drawNextShapeAsShutterOnly = false,
    this.isDrawingMode = false,
    this.hasSideCovers = false,
    this.multiFrameSideCoverManuallyEnabled = false,
    this.profileAngleMode = 0,
    this.profileAngleJunctions = const <int>{},
    this.profileAngleJunctionsDisabled = false,
    this.viewAs90DegreeCorner = false,
    this.frameOverride,
    this.slidingFrameOverride,
    this.sideCoverOverride,
    this.selectedSideCover,
    this.preProfileAngleFrameOverride,
    this.preProfileAngleSlidingOverride,
    this.frameSwitchedForProfileAngle = false,
    this.profileAngleFrameSwitchNotice,
  ]);

  /// Set right after construction by every snapshot site.
  DrawingCatalogSelection? catalogSelection;

  /// Corner cuts of the frame, set with [catalogSelection].
  CornerNotches cornerNotches = CornerNotches.none;
}

/// The catalogue choices of one drawing. Undo/redo restores them together
/// with the geometry, so a profile set is never restored without the series
/// it belongs to (undoing a series switch used to bring back the old
/// profiles while the new series stayed active).
class DrawingCatalogSelection {
  final AluminumSeries? activeSeries;
  final AluminumSeries? activeSlidingSeries;
  final int? loadedSeriesId;
  final String? loadedSeriesName;
  final int? loadedSlidingSeriesId;
  final String? loadedSlidingSeriesName;
  final Map<String, dynamic>? sashOverride;
  final Map<String, dynamic>? slidingSashOverride;
  final Map<String, dynamic>? seriesDesignConfig;
  final Map<String, dynamic>? seriesTableConfig;
  final Map<String, dynamic>? slidingSeriesTableConfig;
  final GlassSpecification defaultGlass;

  const DrawingCatalogSelection({
    this.activeSeries,
    this.activeSlidingSeries,
    this.loadedSeriesId,
    this.loadedSeriesName,
    this.loadedSlidingSeriesId,
    this.loadedSlidingSeriesName,
    this.sashOverride,
    this.slidingSashOverride,
    this.seriesDesignConfig,
    this.seriesTableConfig,
    this.slidingSeriesTableConfig,
    this.defaultGlass = const GlassSpecification(),
  });
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
      case FrameColor.fauxBoisMarron:
        // Light faux-bois brown (not the dark antique).
        return [
          const Color(0xFFC79566),
          const Color(0xFFA9774E),
          const Color(0xFF85593A),
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
      case FrameColor.fauxBoisMarron:
        return const Color(0xFF5D3528);
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

    // Checked before the generic faux bois marron match below.
    if (isLightBrownWoodName(name)) {
      return const [Color(0xFFC08A5E), Color(0xFFA66C42), Color(0xFF7E4F2E)];
    }

    if (name.contains('faux bois marron') ||
        name.contains('marron faux bois') ||
        (name.contains('marron') &&
            (name.contains('bois') ||
                name.contains('faux') ||
                name.contains('خشب'))) ||
        (name.contains('بني') &&
            (name.contains('خشب') || name.contains('خشبي')))) {
      return FrameColor.fauxBoisMarron.gradientColors;
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

    if (isLightBrownWoodName(name)) {
      return const Color(0xFF6A4127);
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
  /// Smallest glazed strip kept inside any zone or leaf, so a division can
  /// never collapse into a sliver that cannot be manufactured.
  static const double minimumGlazingSpanMm = 50.0;

  /// Smallest clear glass between two internal sash divisions (petits bois /
  /// traverses inside one leaf).
  static const double minimumSashCellMm = 80.0;

  /// Smallest width or height of any zone between the frame and a mullion
  /// or between two mullions. A division that would leave less is refused.
  static const double minimumZoneMm = 80.0;

  static const zoneTooSmallKey =
      'لا يمكن التقسيم هنا: كل منطقة يجب أن تكون {min} مم على الأقل طولاً وعرضاً';

  static const hingeObLockedKey =
      'مفاصل نظام OB ثابتة ضمن الطقم ولا يمكن تعديلها';
  static const hingeNoRoomKey =
      'لا يوجد مكان لمفصل آخر: {min} مم من الطرف و {gap} مم بين المفاصل';
  static const hingeMinCountKey = 'يجب أن تبقى في الضلفة مفصلتان على الأقل';

  /// Hinged edges painted in the last editor frame (editor canvas only).
  List<SashHingeEdge> hingeEdges = [];

  /// The hinge picked in the editor, if any.
  SelectedHinge? selectedHinge;

  /// [notifyListeners] for the topic extensions in `model/` (a protected
  /// member cannot be called from an extension without a lint).
  void _notifyModelListeners() => notifyListeners();

  /// Repaints the expensive drawing layer only when geometry/material data
  /// changes. Editor-only state such as selection uses the normal model
  /// notifier without touching this channel.
  final ChangeNotifier drawingRepaint = ChangeNotifier();

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
      // Mosquito-net prices share this table; they are never blade prices.
      if (candidate.toLowerCase().startsWith('moustiquaire_')) continue;
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

  /// Glazing used for new zones of this drawing only. It used to be a static
  /// on [WindowZone], which let one drawing change the glass of another one
  /// opened later in the same process. Order-level "last used glass" is
  /// copied into a new drawing once, by the caller that creates it.
  GlassSpecification defaultGlass = const GlassSpecification();

  /// Catalogue reads that failed while resolving this drawing. Each one
  /// means a price or a component may have fallen back to a default, so the
  /// quantity table shows them instead of presenting the result as exact.
  final List<String> catalogIssues = [];


  /// Optional shutter parts the user switched on or off in the quantity
  /// table (kits, tandem, embout, supports), stored as differences from
  /// [ComponentCalculator.standardActiveVariants]. They used to live only in
  /// that screen, so the cutting sheet and required goods counted the
  /// default parts instead.
  Map<String, bool> shutterVariantChoices = {};

  /// The shutter mechanism/box the choices were made for; choices made for
  /// another mechanism are ignored.
  String? shutterVariantChoicesContext;












  Map<String, dynamic>? frameOverride;
  Map<String, dynamic>? sideCoverOverride;
  Map<String, dynamic>? sashOverride;

  List<Map<String, dynamic>> availableIntercalls = [];
  List<Map<String, dynamic>> availableGases = [];
  double _lastResolvedVitrageJointThickness = 0.0;


  double _readPositiveDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString().replaceAll(',', '.') ?? '') ?? 0.0;
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

  /// Installation (labour) part of one unit's selling price, kept apart so a
  /// quote can show it; it is already included in [totalCost].
  double installationFeePerUnit = 0.0;
  String? description;
  String? persistedDrawingImagePath;
  String? persistedDrawingImageBase64;
  bool invoiceTableEdited = false;
  String? position;
  String? loadedSeriesName;
  String? loadedSlidingSeriesName;
  int? loadedSeriesId;
  int? loadedSlidingSeriesId;
  ReinforcementMode _reinforcementMode = ReinforcementMode.fullSubstitution;

  ReinforcementMode get autoReinforcementMode {
    final series = effectiveSlidingSeries ?? activeSeries;
    if (series != null) {
      final explicitType = series.reinforcementType?.toLowerCase();
      if (explicitType == 'full_substitution') {
        return ReinforcementMode.fullSubstitution;
      } else if (explicitType == 'chicane_combination') {
        return ReinforcementMode.chicaneCombination;
      } else if (explicitType == 'independent_screwed') {
        return ReinforcementMode.independentScrewed;
      }

      final sections = series.sections;

      // 1. Independent screwed renfort
      final hasIndependentRenfort = sections.any((s) {
        final t = s.type.toLowerCase();
        final n = s.name.toLowerCase();
        return t == 'independent_renfort' ||
            t == 'renfort' ||
            t.contains('rapporte') ||
            n.contains('renfort rapporté') ||
            n.contains('renfort rapporte') ||
            n.contains('تدعيم مستقل');
      });
      if (hasIndependentRenfort) {
        return ReinforcementMode.independentScrewed;
      }

      // 2. Chicane combinée / renforcée
      final hasChicaneRenforcee = sections.any((s) {
        final t = s.type.toLowerCase();
        final n = s.name.toLowerCase();
        return t == 'chicane_renforcee' ||
            t.contains('chicane_renf') ||
            n.contains('chicane renforc') ||
            n.contains('شيكان معزز') ||
            n.contains('شيكان مدعم');
      });
      if (hasChicaneRenforcee) {
        return ReinforcementMode.chicaneCombination;
      }
    }

    if (componentOverrides.containsKey(
          'عمود تدعيم مستقل (Profilé de Renfort Rapporté)',
        ) ||
        componentOverrides.containsKey(
          'عمود مدعم مستقل (Profilé de Renfort Rapporté)',
        )) {
      return ReinforcementMode.independentScrewed;
    }
    if (componentOverrides.containsKey('شيكان معزز (Chicane Renforcée)')) {
      return ReinforcementMode.chicaneCombination;
    }

    return ReinforcementMode.fullSubstitution;
  }

  ReinforcementMode get reinforcementMode => autoReinforcementMode;

  set reinforcementMode(ReinforcementMode value) => _reinforcementMode = value;
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

  /// Corners of the frame cut inward as a 90° step. None by default: every
  /// drawing without a cut keeps the rectangular code paths unchanged.
  CornerNotches cornerNotches = CornerNotches.none;

  bool get hasCornerNotches => cornerNotches.hasAny;


  /// The selected frame shows its corner-cut handles instead of its resize
  /// squares (the "corner cut" button of the frame toolbar).
  bool cornerNotchMode = false;

  /// Cut shown as a ghost while a corner-cut handle is dragged; the frame
  /// only changes when the drag is released.
  ({NotchCorner corner, CornerNotch notch})? cornerNotchPreview;

  void setCornerNotchPreview(
    ({NotchCorner corner, CornerNotch notch})? value,
  ) {
    cornerNotchPreview = value;
    drawingRepaint.notifyListeners();
  }

  bool get hasArchOrSlant =>
      archHeight > 0 ||
      topSlantLeftY != 0 ||
      topSlantRightY != 0 ||
      bottomSlantLeftY != 0 ||
      bottomSlantRightY != 0;


  bool get canBeArchedOrSlanted =>
      !zones.any((z) => z.content == ZoneContent.slidingSash);


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
    bool saveHistory = true,
  }) {
    if (!canBeArchedOrSlanted) return;
    if (hasCornerNotches) return;
    final wantsShapedHead =
        (arch ?? archHeight) > 0 ||
        (leftSlant ?? topSlantLeftY) != 0 ||
        (rightSlant ?? topSlantRightY) != 0;
    var historySaved = false;
    if (wantsShapedHead && hasShutter) {
      // A roller shutter needs a straight head for its box; on a slanted or
      // arched frame it is removed completely, and the zones are moved back
      // up into the space the box used to take (before the limits below are
      // measured on them).
      if (saveHistory) _saveSnapshot();
      historySaved = true;
      if (componentOverrides['الصندوق (Caisson)']?['id'] == -999) {
        componentOverrides.remove('الصندوق (Caisson)');
      }
      _applyShutterState(false);
    }
    final next = clampTopShape(
      leftSlant: leftSlant,
      rightSlant: rightSlant,
      arch: arch,
    );
    final nextLeft = next.left;
    final nextRight = next.right;
    final nextArch = next.arch;
    if ((nextLeft - topSlantLeftY).abs() < 0.01 &&
        (nextRight - topSlantRightY).abs() < 0.01 &&
        (nextArch - archHeight).abs() < 0.01) {
      if (historySaved) notifyListeners();
      return;
    }
    if (saveHistory && !historySaved) _saveSnapshot();
    topSlantLeftY = nextLeft;
    topSlantRightY = nextRight;
    archHeight = nextArch;
    notifyListeners();
  }

  /// Circle of the arched head's OUTER edge, or null without an arch. The arch
  /// is a circular segment standing on the chord between the two top corners,
  /// with [archHeight] as its sagitta (rise), never more than a semicircle.
  ({Offset center, double radius, Offset apex})? headArc({
    double? left,
    double? right,
    double? arch,
    double topOffset = 0.0,
  }) {
    final rise = arch ?? archHeight;
    if (rise <= 0 || width <= 0) return null;
    final p0 = Offset(0, topOffset + (left ?? topSlantLeftY));
    final p1 = Offset(width, topOffset + (right ?? topSlantRightY));
    final chord = p1 - p0;
    final c = chord.distance;
    if (c <= 0) return null;
    final s = math.min(rise, c / 2);
    final d = chord / c;
    // Unit normal pointing into the window (downwards for a level chord).
    final n = Offset(-d.dy, d.dx);
    final radius = c * c / (8 * s) + s / 2;
    final mid = (p0 + p1) / 2;
    return (center: mid + n * (radius - s), radius: radius, apex: mid - n * s);
  }

  /// Y of the head edge at [x], offset [inset] mm into the window measured
  /// perpendicular to the edge: a parallel line under a slant, a concentric
  /// circle under an arch. Frame, sash, glass and parclose all use it so
  /// every band keeps a constant thickness.
  double headEdgeY(
    double x,
    double inset, {
    double topOffset = 0.0,
    double? left,
    double? right,
    double? arch,
  }) {
    final l = left ?? topSlantLeftY;
    final r = right ?? topSlantRightY;
    final circle = headArc(left: l, right: r, arch: arch, topOffset: topOffset);
    if (circle != null) {
      final radius = math.max(0.0, circle.radius - inset);
      final dx = x - circle.center.dx;
      return circle.center.dy - math.sqrt(math.max(0.0, radius * radius - dx * dx));
    }
    if (l == 0 && r == 0 || width <= 0) return topOffset + inset;
    final slope = (r - l) / width;
    return topOffset + l + slope * x + inset * math.sqrt(1 + slope * slope);
  }

  /// Geometry of the slanted divisions of [zone] inside its clear rectangle,
  /// optionally for a candidate list of [dividers].
  SlantedDivisionGeometry slantedGeometryFor(
    WindowZone zone, {
    List<SlantedDivider>? dividers,
  }) => SlantedDivisionGeometry(
    clear: zone.boundary,
    dividers: dividers ?? zone.slantedDividers,
    profileWidth: mullionThickness,
  );

  /// A stroke from [start] to [end] draws a slanted division: it is clearly
  /// diagonal (between the minimum angle and its complement) and starts in a
  /// fixed zone. Near-horizontal or near-vertical strokes split as before.
  bool isSlantedStroke(Offset start, Offset end) {
    final dx = (end.dx - start.dx).abs();
    final dy = (end.dy - start.dy).abs();
    if (dx <= 40 && dy <= 40) return false;
    final angle = math.atan2(dy, dx) * 180 / math.pi;
    const minSlant = SlantedDivisionGeometry.minimumAngleDeg;
    if (angle < minSlant || angle > 90 - minSlant) return false;
    for (final z in zones) {
      if (z.boundary.contains(start)) {
        return z.content == ZoneContent.fixedGlass ||
            z.content == ZoneContent.empty;
      }
    }
    return false;
  }

  /// Adds [divider] to the zone, or replaces the one with the same id. Returns
  /// a translation key (nothing changes) when the result cannot be built.
  String? setSlantedDivider(
    String zoneId,
    SlantedDivider divider, {
    bool saveHistory = true,
  }) {
    final index = zones.indexWhere((z) => z.id == zoneId);
    if (index == -1) return null;
    final zone = zones[index];
    if (zone.content != ZoneContent.fixedGlass &&
        zone.content != ZoneContent.empty) {
      return SlantedDivisionError.notFixedZone;
    }
    if (zone.innerH > 0 || zone.innerV > 0) {
      return SlantedDivisionError.mixedDivisions;
    }
    if (hasArchOrSlant) {
      final topRow = zones.map((z) => z.boundary.top).reduce(math.min);
      if ((zone.boundary.top - topRow).abs() < 2.0) {
        return SlantedDivisionError.underShapedHead;
      }
    }
    final next = [
      for (final d in zone.slantedDividers)
        if (d.id != divider.id) d,
      divider,
    ];
    final error = slantedGeometryFor(
      zone,
      dividers: next,
    ).validate(minimumCellMm: minimumSashCellMm);
    if (error != null) return error;
    if (saveHistory) _saveSnapshot();
    zone.slantedDividers = next;
    // Cell glass keys follow the new cell order.
    zone.cellGlassSpec = {
      for (final entry in zone.cellGlassSpec.entries)
        if (!entry.key.startsWith('slant_cell_')) entry.key: entry.value,
    };
    notifyListeners();
    return null;
  }

  /// Translation key of the last rejected drawing action (e.g. a slanted
  /// stroke that breaks a rule); the drawing page shows it and clears it.
  String? drawingNotice;

  /// Slanted mullion picked in the editor (shows its end handles).
  ({String zoneId, String dividerId})? selectedSlantedDivider;

  /// A slanted mullion being dragged: drawn instead of the stored one until
  /// the drag ends; [error] is the rule it currently breaks, if any.
  ({String zoneId, SlantedDivider divider, String? error})?
  slantedDividerPreview;

  List<SlantedDivider> slantedDividersShownFor(WindowZone zone) {
    final preview = slantedDividerPreview;
    if (preview == null || preview.zoneId != zone.id) {
      return zone.slantedDividers;
    }
    return [
      for (final d in zone.slantedDividers)
        d.id == preview.divider.id ? preview.divider : d,
    ];
  }

  WindowZone? _zoneById(String id) {
    for (final z in zones) {
      if (z.id == id) return z;
    }
    return null;
  }

  SlantedDivider? slantedDividerById(String zoneId, String dividerId) {
    final zone = _zoneById(zoneId);
    if (zone == null) return null;
    for (final d in zone.slantedDividers) {
      if (d.id == dividerId) return d;
    }
    return null;
  }

  /// Slanted mullion under [pos] within [slopMm] of its band.
  ({String zoneId, String dividerId})? slantedDividerAt(
    Offset pos, {
    double slopMm = 0.0,
  }) {
    for (final zone in zones) {
      if (zone.slantedDividers.isEmpty ||
          !zone.boundary.inflate(slopMm).contains(pos)) {
        continue;
      }
      final geometry = slantedGeometryFor(zone);
      for (final d in zone.slantedDividers) {
        if (geometry.distanceToDivider(d, pos) <=
            mullionThickness / 2 + slopMm) {
          return (zoneId: zone.id, dividerId: d.id);
        }
      }
    }
    return null;
  }

  void selectSlantedDivider(({String zoneId, String dividerId})? value) {
    selectedSlantedDivider = value;
    drawingRepaint.notifyListeners();
    super.notifyListeners();
  }

  /// Moves one end of a slanted mullion as a preview (magnetic 10 mm steps
  /// along the zone side under the pointer).
  void previewSlantedDividerEnd(
    String zoneId,
    String dividerId, {
    required bool atStart,
    required Offset pointer,
  }) {
    final zone = _zoneById(zoneId);
    final stored = slantedDividerById(zoneId, dividerId);
    if (zone == null || stored == null) return;
    final anchor = SlantedDivisionGeometry.nearestAnchor(
      zone.boundary,
      pointer,
    );
    final moved = atStart
        ? stored.copyWith(start: anchor)
        : stored.copyWith(end: anchor);
    final candidate = [
      for (final d in zone.slantedDividers)
        d.id == dividerId ? moved : d,
    ];
    slantedDividerPreview = (
      zoneId: zoneId,
      divider: moved,
      error: slantedGeometryFor(
        zone,
        dividers: candidate,
      ).validate(minimumCellMm: minimumSashCellMm),
    );
    drawingRepaint.notifyListeners();
  }

  /// Applies the dragged preview (one undo step). Returns the rule it broke
  /// as a translation key, in which case the mullion stays where it was.
  String? commitSlantedDividerPreview() {
    final preview = slantedDividerPreview;
    slantedDividerPreview = null;
    if (preview == null) return null;
    final error = setSlantedDivider(preview.zoneId, preview.divider);
    drawingRepaint.notifyListeners();
    return error;
  }

  void removeSlantedDivider(String zoneId, String dividerId) {
    final index = zones.indexWhere((z) => z.id == zoneId);
    if (index == -1) return;
    final zone = zones[index];
    if (!zone.slantedDividers.any((d) => d.id == dividerId)) return;
    if (selectedSlantedDivider?.dividerId == dividerId) {
      selectedSlantedDivider = null;
    }
    _saveSnapshot();
    zone.slantedDividers = [
      for (final d in zone.slantedDividers)
        if (d.id != dividerId) d,
    ];
    zone.cellGlassSpec = {
      for (final entry in zone.cellGlassSpec.entries)
        if (!entry.key.startsWith('slant_cell_')) entry.key: entry.value,
    };
    notifyListeners();
  }

  /// Head shape shown as a dashed ghost while a slant/arch handle is being
  /// dragged; the frame itself only changes when the drag is released.
  ({double left, double right, double arch})? topShapePreview;

  void setTopShapePreview(({double left, double right, double arch})? value) {
    topShapePreview = value;
    drawingRepaint.notifyListeners();
  }

  /// Legal head shape for the requested values (null keeps the current one).
  /// A corner may be raised above the top line (negative value) until that
  /// jamb reaches one bar length, or lowered until a jamb or a top zone
  /// would lose its minimum; a circular head rises at most half the width.
  ({double left, double right, double arch}) clampTopShape({
    double? leftSlant,
    double? rightSlant,
    double? arch,
  }) {
    final maxRaise = -math.max(0.0, maximumFrameBarLengthMm - height);
    final left = (leftSlant ?? topSlantLeftY)
        .clamp(maxRaise, maxTopSlantMm(left: true, otherSlant: rightSlant))
        .toDouble();
    final right = (rightSlant ?? topSlantRightY)
        .clamp(maxRaise, maxTopSlantMm(left: false, otherSlant: left))
        .toDouble();
    final nextArch = (arch ?? archHeight)
        .clamp(0.0, math.max(0.0, width / 2))
        .toDouble();
    return (left: left, right: right, arch: nextArch);
  }

  /// Largest drop of one top corner that keeps the jamb on that side and
  /// every top-row zone above its minimum height. [otherSlant] is the drop
  /// of the opposite corner (defaults to its current value).
  double maxTopSlantMm({required bool left, double? otherSlant}) {
    if (width <= 0 || height <= 0) return 0.0;
    final other = (otherSlant ?? (left ? topSlantRightY : topSlantLeftY))
        .clamp(-height, height)
        .toDouble();
    final bottomSlant = left ? bottomSlantLeftY : bottomSlantRightY;
    var limit =
        height - bottomSlant - profileThickness * 2 - minimumGlazingSpanMm;
    if (zones.isNotEmpty) {
      final innerTop = zones.map((z) => z.boundary.top).reduce(math.min);
      for (final z in zones) {
        if ((z.boundary.top - innerTop).abs() > 2.0) continue;
        final room = z.boundary.height - minimumZoneSpanMm(z, isWidth: false);
        for (final x in [z.boundary.left, z.boundary.right]) {
          final t = (x / width).clamp(0.0, 1.0).toDouble();
          // Drop of the top line at x: left*(1-t) + right*t.
          final ownShare = left ? 1.0 - t : t;
          final otherShare = 1.0 - ownShare;
          if (ownShare < 0.01) continue;
          limit = math.min(limit, (room - other * otherShare) / ownShare);
        }
      }
    }
    return math.max(0.0, limit);
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
    if (configuredIds.isEmpty) {
      if (roleKey.trim() == 'face_to_face') {
        // Do not call getSlidingSectionByType here: that resolver asks this
        // method first and the two functions recurse until Windows terminates
        // the process with a stack overflow. Legacy catalogues without an
        // explicit design-role row may still use the section's own type/name.
        for (final section in series.sections) {
          final type = section.type.trim().toLowerCase();
          final name = section.name.trim().toLowerCase();
          if (type == 'face_to_face' ||
              type == 'face to face' ||
              name.contains('face to face') ||
              name.contains('face-to-face')) {
            return section;
          }
        }
      }
      return null;
    }
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




















  bool get isPVC => _isPvcSeries(
    usesSlidingPrimaryProfiles ? activeSlidingSeries : activeSeries,
  );

  bool get effectiveUseSystemOB => canUseOpeningOnlyOptions && useSystemOB;

  bool get canUseDemiOB => isPVC && canUseOpeningOnlyOptions;

  bool get effectiveUseDemiOB => canUseDemiOB && useDemiOB;




























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




  double profileThickness;

  /// Keyed by section_id → set of compatible partner section_ids.
  /// Populated by [reloadFrameJoinRules] whenever series change.
  Map<int, Set<int>> _frameJoinPartners = {};

  /// FramePairingRules by frame section id: the frame of its sides without
  /// a cover, its frame against a corner profile, the frames it joins.
  Map<int, Map<String, dynamic>> _framePairings = {};

  /// Frames named by the last refused corner profile switch.
  List<String> lastCornerPairingRefusal = const [];














  bool coupleFrames = true;








  bool _isEnabledFlag(Object? value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) {
      return value.trim().toLowerCase() == 'true' || value.trim() == '1';
    }
    return false;
  }










  bool hasBottomFrame = true;
  bool useOptionalSeuil = false;
  bool useOptionalCacheDormant = false;
  bool useOptionalTriangle = false;
  bool useOptionalCaniveau = false;

  /// Bavette mode: 0 disabled, 1 bottom only, 2 all four directions.
  int optionalBavetteMode = 0;

  /// Profil d'angle mode: 0 disabled, 1 right (يمين), 2 left (يسار), 3 both (الجهتين).
  int profileAngleMode = 0;

  /// Junction indices between adjacent frames where 90° angle profile is installed.
  Set<int> profileAngleJunctions = <int>{};
  bool profileAngleJunctionsDisabled = false;

  /// Whether to render the drawing with a 90° corner 3D perspective when angle junctions are active.
  bool viewAs90DegreeCorner = true;
  Map<String, dynamic>? _preProfileAngleFrameOverride;
  Map<String, dynamic>? _preProfileAngleSlidingOverride;
  bool _frameSwitchedForProfileAngle = false;
  String? _profileAngleFrameSwitchNotice;


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

  /// Optional mosquito screen sold with this window. It is intentionally not
  /// painted on the technical drawing; it only participates in pricing.
  bool hasMoustiquaireAddon = false;
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

  /// هل تم تفعيل فصل الصناديق
  bool isShutterSplit = false;

  /// وضع التقسيم: 'per_frame' (لكل إطار صندوقه) أو 'custom_divisions' (تقسيم يدوي)
  String shutterSplitMode = 'per_frame';

  /// أقسام الصناديق المقسمة
  List<ShutterSplitSection> shutterSplits = [];








  String shutterDriveSide = 'left';


  String shutterLame = 'Lame Injectée';
  String shutterGlissiere = 'Glissière 25';
  String? shutterHeightWarning;
  List<Map<String, dynamic>> _shutterBladeWarningCatalogue = [];






  double? shutterMaximumWidthMm;








  String selectedSashCode = '104';

  bool useSystemOB = false;
  bool useDemiOB = false;
  bool useVerrouCentral = false;

  /// Aluminium opening parclose cutting. `45` cuts every piece at the inner
  /// glazing size (mitred, like PVC). `90_length` keeps the vertical pieces
  /// full and shortens the horizontal ones by 2 x the parclose glass
  /// deduction; `90_width` does the opposite.
  ///
  /// The selected parclose's [ParcloseCutRule] decides which cuts are
  /// possible: a new drawing follows its default cut, a chosen or saved cut
  /// is kept while that parclose takes it.
  String get parcloseCutMode {
    final rule = parcloseCutRule;
    final chosen = _parcloseCutMode;
    return chosen == null ? rule.initialMode : rule.resolve(chosen);
  }

  set parcloseCutMode(String mode) {
    _parcloseCutMode = ParcloseCutRule.modes.contains(mode) ? mode : '45';
  }

  /// The cut the user chose or the drawing was saved with; null on a new
  /// drawing.
  String? _parcloseCutMode;

  bool get parcloseCutAt90 =>
      parcloseCutMode == '90_length' || parcloseCutMode == '90_width';

  void setParcloseCutMode(String mode) {
    if (_parcloseCutMode != null && parcloseCutMode == mode) return;
    parcloseCutMode = mode;
    notifyListeners();
  }

  /// How far the user moved each cut-angle badge of a slanted head (key →
  /// mm), so a badge covering something can be pushed aside.
  final Map<String, Offset> angleBadgeOffsets = {};

  /// Where each cut-angle badge was last drawn, for hit tests.
  final Map<String, Rect> drawnAngleBadges = {};

  /// The cut-angle badge at [point], or null.
  String? angleBadgeAt(Offset point, {double margin = 10}) {
    for (final entry in drawnAngleBadges.entries) {
      if (entry.value.inflate(margin).contains(point)) return entry.key;
    }
    return null;
  }

  void dragAngleBadge(String key, Offset deltaMm) {
    angleBadgeOffsets[key] = (angleBadgeOffsets[key] ?? Offset.zero) + deltaMm;
    drawingRepaint.notifyListeners();
  }

  /// The belt of a separate shutter (over a slanted or arched head) is
  /// brought inside through a pulley set in the frame jamb; otherwise it
  /// stays outside, between the window and the shutter rails.
  bool separateShutterBeltInside = false;

  void setSeparateShutterBeltInside(bool inside) {
    if (separateShutterBeltInside == inside) return;
    separateShutterBeltInside = inside;
    notifyListeners();
  }

  /// With a 90° parclose cut, a plastic corner cap (bouchon) may cover each
  /// corner where two parclose pieces meet. It is drawn and counted only
  /// while the cut is at 90° (see [showsParcloseCornerCaps]).
  bool parcloseCornerCaps = false;

  bool get showsParcloseCornerCaps =>
      !isPVC && parcloseCutAt90 && parcloseCornerCaps;

  void setParcloseCornerCaps(bool enabled) {
    if (parcloseCornerCaps == enabled) return;
    parcloseCornerCaps = enabled;
    notifyListeners();
  }

  List<Map<String, dynamic>> systemObComponents = [];
  List<Map<String, dynamic>> verrouCentralComponents = [];

  int get cremoneLengthCm {
    final targetH = effectiveEspagnoletteHeightMm / 10.0;

    if (targetH >= 180) return 180;
    if (targetH >= 40) return (targetH / 20.0).floor() * 20;
    if (targetH >= 30) return 30;
    return 30;
  }




  bool hasSideCovers = false;
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

  /// The console the customer's tunnel box takes: 1 Standard, 2 Special
  /// (the two compatibility groups of the CT kit). Chosen, not computed.
  int tunnelConsoleGroup = 1;
  double? customShutterBoxHeight;









  AluminumSection? selectedSideCover;



























  FrameColor _frameColor = FrameColor.white;



  Map<String, dynamic>? _selectedDbColor;
  Map<String, dynamic>? _preferredDbColorForCatalogLoad;



  final Map<int, double> sectionPricesForSelectedColor = <int, double>{};

















  Map<String, dynamic>? _selectedAccessoryColor;
  Map<String, dynamic>? selectedShutterColor;






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

  /// The sash zone a long press selected every sash from. It holds only
  /// while that zone stays selected (see [allSashesSelected]).
  String? allSashesAnchorZoneId;

  /// The sliding leaf picked by a tap (its index in the selected sliding
  /// zone); null when the whole zone, or every sash, is selected.
  int? selectedSlidingLeaf;

  /// The leaves of each sliding zone as last drawn (zone id → rects), so the
  /// selection overlay highlights exactly the leaf picked.
  final Map<String, List<Rect>> drawnSlidingLeafRects = {};

  /// The bars of each inner division as last drawn (see
  /// [innerDivisionKey]), so the selection overlay outlines exactly the
  /// division picked, inside a sash as inside a fixed glass.
  final Map<String, List<Rect>> drawnInnerDivisionRects = {};

  /// The glass cells of each divided zone as last drawn (zone id → cells),
  /// so the selection overlay highlights the cell tapped inside a sash.
  final Map<String, List<DrawnGlassCell>> drawnGlassCells = {};

  static String innerDivisionKey(
    String zoneId, {
    required bool isRightSash,
    required bool isHorizontal,
    required int index,
  }) => '$zoneId|${isRightSash ? 'r' : 'l'}|${isHorizontal ? 'h' : 'v'}|$index';

  /// Where the handle-height number of each opening sash was last drawn
  /// (zone id → the number's rect and the sash span it measures), so a tap
  /// on the number can edit the handle height.
  final Map<String, ({Rect label, double sashTop, double sashBottom})>
  drawnHandleHeightLabels = {};

  /// The zone whose handle-height number is at [point] (with a margin for a
  /// finger), or null.
  String? handleHeightLabelAt(Offset point, {double margin = 20}) {
    for (final entry in drawnHandleHeightLabels.entries) {
      if (!zones.any((zone) => zone.id == entry.key)) continue;
      if (entry.value.label.inflate(margin).contains(point)) return entry.key;
    }
    return null;
  }

  /// The handle height of [zoneId] in mm from the sash bottom, as drawn.
  double? handleHeightFromBottom(String zoneId) {
    final label = drawnHandleHeightLabels[zoneId];
    if (label == null) return null;
    final zone = zones.where((z) => z.id == zoneId).firstOrNull;
    if (zone == null) return null;
    final span = label.sashBottom - label.sashTop;
    return span * (zone.handlePositionRatio ?? 0.5);
  }

  /// Sets the handle of [zoneId] at [mm] from the sash bottom. Returns false
  /// when the number was never drawn or [mm] is outside the sash.
  bool setHandleHeightFromBottom(String zoneId, double mm) {
    final label = drawnHandleHeightLabels[zoneId];
    if (label == null) return false;
    final span = label.sashBottom - label.sashTop;
    if (span <= 0 || mm <= 0 || mm >= span) return false;
    _saveSnapshot();
    updateHandlePosition(zoneId, mm / span);
    return true;
  }

  /// A selected frame shows its resize squares (one tap) or, after a double
  /// tap, its slant/arch circles: never both at once.
  bool frameShapeMode = false;

  /// The selected frame can show the slant/arch circles: a window without
  /// sliding sashes, and in a coupled drawing only its first frame.
  bool get canShapeSelectedFrame {
    if (selection.type != SelectionType.frame || !canBeArchedOrSlanted) {
      return false;
    }
    // A cut corner and a slanted or arched head are not combined.
    if (hasCornerNotches) return false;
    final key = selection.zoneId;
    return key == null || key == 'frame:0' || getFrameRects().length <= 1;
  }

  /// Sets the frame mode after a tap selected something. A tap on a frame
  /// shows its resize squares (green); a second quick tap on the same frame
  /// ([isDoubleTap], with [frameKeyBeforeTap] the frame selected before
  /// this tap) shows its slant/arch circles (orange). Anything else that is
  /// selected leaves the frame mode.
  void applyFrameTapMode({
    required bool isDoubleTap,
    String? frameKeyBeforeTap,
  }) {
    if (selection.type != SelectionType.frame) {
      frameShapeMode = false;
      cornerNotchMode = false;
      return;
    }
    final key = selection.zoneId ?? 'frame:0';
    frameShapeMode = isDoubleTap && frameKeyBeforeTap == key;
    if (frameShapeMode) cornerNotchMode = false;
    _notifySelectionChanged();
  }

  /// The selected frame key before a tap, for [applyFrameTapMode].
  String? get selectedFrameKey => selection.type == SelectionType.frame
      ? (selection.zoneId ?? 'frame:0')
      : null;

  /// How far the last frame resize moved the whole drawing to keep it at
  /// the origin (growing from the left or the top). The view moves the
  /// camera back by as much, so the side dragged is the side that grows.
  Offset lastResizeAnchorShift = Offset.zero;
  bool showZoneMenu = false;
  final List<WindowSnapshot> _history = [];
  final List<WindowSnapshot> _redoHistory = [];

  /// The window drawing that was converted into a shutter, so pressing the
  /// shutter button again brings it back (see convertShutterBackToWindow).
  WindowSnapshot? _drawingBeforeShutter;



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
  double? _lastHeadRise;

  /// How far the head (arch and/or a raised slant corner) rises above the
  /// nominal top line; the camera, wall and dimensions must make room for it.
  double get headRiseMm =>
      archHeight + math.max(0.0, -math.min(topSlantLeftY, topSlantRightY));
  double _maxObservedLayoutHeight = 0.0;

  final SqlDatabase db;
  List<AluminumProfileSystem> availableSystems = [];
  AluminumSeries? activeSeries;
  AluminumSeries? activeSlidingSeries;

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



  WindowModel({
    required this.db,
    this.width = 0,
    this.height = 0,
    // 40 mm is the fallback frame width used everywhere else; the old 10 mm
    // was only overwritten because a missing catalogue forced 40 mm.
    this.profileThickness = 40.0,
    this.systemMode,
  });

  List<Map<String, dynamic>> allGlassCache = [];


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






















































  /// The spacer for the [remaining] gap of a glazing pack. The pack may exceed
  /// the capacity by 1 mm at most, never fall short: the thinnest spacer in
  /// that window wins (18 mm with 5+5 => 8, not the nearest 12). Without one,
  /// the largest spacer that does not overflow is the closest option and the
  /// fit is reported as incompatible.
  int? _spacerFillingGap(double remaining) {
    if (remaining <= 0) return null;
    final choices = _availableIntercallThicknesses();
    for (final thickness in choices) {
      if (thickness >= remaining - 0.000001 &&
          thickness <= remaining + 1.000001) {
        return thickness;
      }
    }
    int? best;
    for (final thickness in choices) {
      if (thickness <= remaining + 1.000001) best = thickness;
    }
    return best;
  }
















  @override
  void notifyListeners() {
    if (hasCornerNotches) _fitCornerNotchesToFrame();
    _enforceMultiFramePlainFrameRule();
    _disableSlidingMontantReinforcementForPvc();
    validateAndSanitizeAllZonesHandles();
    drawingRepaint.notifyListeners();
    super.notifyListeners();
  }

  /// Selection changes are visual/editor state only. They must not rerun the
  /// structural normalization used after geometry, series, or profile edits.
  /// That normalization walks the complete frame/zone graph and made a simple
  /// click on a frame noticeably lag on complex drawings.
  void _notifySelectionChanged() => super.notifyListeners();

  @override
  void dispose() {
    drawingRepaint.dispose();
    super.dispose();
  }

  void refreshUI() => notifyListeners();





  /// Set while a finger or the mouse is dragging on the canvas: the camera
  /// waits for the release before it refits, so a handle never runs away
  /// from the pointer.
  bool holdCamera = false;

  /// Places the drawing in [widgetSize], a fixed working area passed by the
  /// view (not the canvas that the bottom menu shrinks), so panels and menus
  /// never move it. A drawing already on screen keeps its camera, like a CAD
  /// view: the first frame stays where and as large as it was dragged. The
  /// drawing is fitted and centred only when it is opened, when it no longer
  /// fits the working area, or when the user asks (centerDrawingOnCanvas).
  void updateLayoutMetrics(Size widgetSize) {
    // تجنب إعادة الحساب أثناء الرسم النشط لمنع تحريف الإحداثيات
    if (drawingStart != null || holdCamera) return;

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
        _lastShutterBoxHeight != shutterBoxHeight ||
        _lastHeadRise != headRiseMm;

    // تجنب إعادة الحساب إذا لم يتغير الحجم فعلياً (اقتصاداً في الحساب)
    if (lastLayoutSize == widgetSize &&
        !stateChanged &&
        canvasScale > 0 &&
        (canvasDx != 0 || canvasDy != 0)) {
      return;
    }

    final double effectiveHeight = widgetSize.height;
    final bool? wasEmpty = _lastIsEmpty;
    final Size? previousSize = lastLayoutSize;

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
    _lastHeadRise = headRiseMm;

    // Keep a narrow, predictable safety border around the drawing.  The
    // camera then fits the window *and* its dimension lines, rather than
    // shrinking the drawing by an arbitrary percentage.
    const double viewportPadding = 24.0;
    final double centerY = effectiveHeight / 2;

    // The empty canvas: a 1500 x 1125 mm sheet where the first frame is
    // dragged, close enough for a usual window to fill most of the view.
    void useEmptyCanvasCamera() {
      const double virtualW = 1500.0;
      const double virtualH = 1125.0;
      double sX = (widgetSize.width - viewportPadding) / virtualW;
      double sY = (effectiveHeight - viewportPadding) / virtualH;
      canvasScale = math.min(sX, sY);
      canvasDx = widgetSize.width / 2 - (virtualW / 2 * canvasScale);
      canvasDy = centerY - (virtualH / 2 * canvasScale);
    }

    if (width <= 0 || height <= 0 || zones.isEmpty) {
      useEmptyCanvasCamera();
      return;
    }

    // The dimension labels sit outside the physical frame.  Include their
    // space in the camera bounds so their text and ticks never get clipped.
    final double sideCoverExtension = hasSideCovers
        ? sideCoverWidth + 15.0
        : 0.0;

    // Whether the frame (covers and arch included) leaves the working area.
    bool frameLeavesView() {
      final double left = canvasDx - sideCoverExtension * canvasScale;
      final double right =
          canvasDx + (width + sideCoverExtension) * canvasScale;
      final double top =
          canvasDy - (headRiseMm + sideCoverExtension) * canvasScale;
      final double bottom =
          canvasDy + (height + sideCoverExtension) * canvasScale;
      return left < 0 ||
          top < 0 ||
          right > widgetSize.width ||
          bottom > effectiveHeight;
    }

    if (previousSize != null && wasEmpty == false && canvasScale > 0) {
      // Already on screen: keep the zoom and the place. A resized app
      // window keeps the drawing at the same distance from the centre.
      canvasDx += (widgetSize.width - previousSize.width) / 2;
      canvasDy += (widgetSize.height - previousSize.height) / 2;
      if (!frameLeavesView()) return;
    } else if (wasEmpty == true && drawnLeft != null && drawnTop != null) {
      // The first frame just dragged: same zoom and place as the drag.
      useEmptyCanvasCamera();
      canvasDx += drawnLeft! * canvasScale;
      canvasDy += drawnTop! * canvasScale;
      if (!frameLeavesView()) return;
    }
    // Dimension text and spacing are painted at a constant screen size
    // (AppWorkspacePainter), so their room is reserved in pixels; frame,
    // covers, arch and wall are reserved in millimetres.
    final bool multiFrame = getFrameRects().length > 1;
    // Slanted mullions add a row of end positions on each side they reach.
    final bool hasSlantRows = zones.any((z) => z.slantedDividers.isNotEmpty);
    // The side dimension line sits 44 px out, its number just beyond; the
    // shutter adds its own height line on the right.
    final double dimensionLeftPx = 70.0 + (hasSlantRows ? 44.0 : 0.0);
    final double dimensionRightPx =
        70.0 + (hasSlantRows ? 44.0 : 0.0) + (hasShutter ? 60.0 : 0.0);
    final double dimensionTopPx =
        (multiFrame ? 120.0 : 75.0) +
        (hasSlantRows ? 44.0 : 0.0) +
        (hasShutter ? 16.0 : 0.0);
    // A shaped head moves the overall width below the frame.
    // Coupled frames may carry a chain of frame widths under the drawing.
    final double dimensionBottomPx =
        50.0 +
        (hasArchOrSlant ? 70.0 : 0.0) +
        (multiFrame ? 40.0 : 0.0) +
        (hasSlantRows ? 44.0 : 0.0);

    // Match the actual wall extent used by WindowPainter (500 mm on both
    // sides) instead of the previous smaller virtual extent.
    final double wallLeft = showWall ? 500.0 : 0.0;
    final double wallRight = showWall ? 500.0 : 0.0;
    final double wallTop = showWall
        ? (hasShutter ? shutterBoxHeight + 150.0 : 150.0) + headRiseMm
        : 0.0;
    final double wallBottom = (showWall && showBottomWall) ? 200.0 : 0.0;

    final double maxW = math.max(100.0, widgetSize.width - viewportPadding);
    final double maxH = math.max(100.0, effectiveHeight - viewportPadding);

    // An arch rises above the nominal top line (see _buildOuterShapePath).
    double sX =
        math.max(maxW * 0.35, maxW - dimensionLeftPx - dimensionRightPx) /
        (width + 2 * sideCoverExtension);
    double sY =
        math.max(maxH * 0.35, maxH - dimensionTopPx - dimensionBottomPx) /
        (height + headRiseMm + 2 * sideCoverExtension);
    if (showWall) {
      sX = math.min(sX, maxW / (width + wallLeft + wallRight));
      sY = math.min(sY, maxH / (height + wallTop + wallBottom));
    }
    canvasScale = math.max(1e-4, math.min(sX, sY));

    final double contentLeft = math.max(
      wallLeft,
      dimensionLeftPx / canvasScale + sideCoverExtension,
    );
    final double contentRight = math.max(
      wallRight,
      dimensionRightPx / canvasScale + sideCoverExtension,
    );
    final double contentTop = math.max(
      wallTop,
      dimensionTopPx / canvasScale + sideCoverExtension + headRiseMm,
    );
    final double contentBottom = math.max(
      wallBottom,
      dimensionBottomPx / canvasScale + sideCoverExtension,
    );
    final double boundsCenterX = (width + contentRight - contentLeft) / 2;
    final double boundsCenterY = (height + contentBottom - contentTop) / 2;

    // Always centred, wherever the first frame was drawn on the canvas.
    canvasDx = widgetSize.width / 2 - (boundsCenterX * canvasScale);
    canvasDy = centerY - (boundsCenterY * canvasScale);
  }

  /// Refits and recentres the drawing (the reset-zoom control).
  void centerDrawingOnCanvas() {
    drawnLeft = null;
    drawnTop = null;
    lastLayoutSize = null;
    notifyListeners();
  }




































  /// Outer dimension labels painted in the last frame (editor canvas only).
  List<DimensionLabelHit> dimensionLabelHits = [];

  /// Extra distance (mm) the user dragged each outer dimension away from the
  /// frame, by label key. Editor-only layout state, not part of the design.
  final Map<String, double> dimensionOffsets = {};

  DimensionLabelHit? dimensionLabelAt(Offset pos) {
    for (final hit in dimensionLabelHits.reversed) {
      if (hit.rect.contains(pos)) return hit;
    }
    return null;
  }

  void dragDimension(String key, double deltaMm) {
    dimensionOffsets[key] = ((dimensionOffsets[key] ?? 0.0) + deltaMm)
        .clamp(0.0, 3000.0)
        .toDouble();
    drawingRepaint.notifyListeners();
  }

  DimensionTap checkOuterDimensionTap(Offset pos) {
    // Hit exactly the painted labels; they move with the camera, the shaped
    // head and the user's dragging, so fixed bands no longer match them.
    if (dimensionLabelHits.isNotEmpty) {
      final key = dimensionLabelAt(pos)?.key;
      if (key == 'width') return DimensionTap.width;
      if (key == 'height') return DimensionTap.height;
      return DimensionTap.none;
    }
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
      final canTapZoneDimensions =
          z.content == ZoneContent.empty || z.content == ZoneContent.fixedGlass;
      if (canTapZoneDimensions) {
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
      // Never shrink below what the zones, sash bars and mullions need.
      final wLimits = outerDimensionLimits(isWidth: true, otherSide: newH);
      final hLimits = outerDimensionLimits(isWidth: false, otherSide: newW);
      newW = newW.clamp(wLimits.min, wLimits.max).toDouble();
      newH = newH.clamp(hLimits.min, hLimits.max).toDouble();
    }
    if ((newW - width).abs() < 0.001 && (newH - height).abs() < 0.001) return;
    _saveSnapshot();
    final oldWidth = width;
    final oldHeight = height;
    _rescaleZonesInternal(oldWidth, oldHeight, newW, newH);
    width = newW;
    height = newH;
    _resizeSideCoverSegments(oldWidth, oldHeight, newW, newH);
    synchronizeShutterAfterFrameResize(oldWidth, oldHeight);
    // The camera keeps its zoom and place: a new size never refits the
    // drawing (the user zooms, pans or centres it).
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
            if (z.boundary.left + minimumZoneSpanMm(z, isWidth: true) > minAllowedX) {
              minAllowedX = z.boundary.left + minimumZoneSpanMm(z, isWidth: true);
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
            if (z.boundary.right - minimumZoneSpanMm(z, isWidth: true) < maxAllowedX) {
              maxAllowedX = z.boundary.right - minimumZoneSpanMm(z, isWidth: true);
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
            if (z.boundary.top + minimumZoneSpanMm(z, isWidth: false) > minAllowedY) {
              minAllowedY = z.boundary.top + minimumZoneSpanMm(z, isWidth: false);
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
            if (z.boundary.bottom - minimumZoneSpanMm(z, isWidth: false) < maxAllowedY) {
              maxAllowedY = z.boundary.bottom - minimumZoneSpanMm(z, isWidth: false);
            }
          }
        }
        return r.height + ((maxAllowedY - sep) - oldY);
      }
    }
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
        if (z.boundary.left + minimumZoneSpanMm(z, isWidth: true) > minAllowedX) {
          minAllowedX = z.boundary.left + minimumZoneSpanMm(z, isWidth: true);
        }
      }
      if ((z.boundary.left - (divisionX + sep)).abs() < 2) {
        if (z.boundary.right - minimumZoneSpanMm(z, isWidth: true) < maxAllowedX) {
          maxAllowedX = z.boundary.right - minimumZoneSpanMm(z, isWidth: true);
        }
      }
    }

    double newDivisionX = divisionX + diff;
    // No legal position: the neighbouring zones are already at their minimum.
    if (minAllowedX + sep > maxAllowedX - sep) return;
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
        if (z.boundary.top + minimumZoneSpanMm(z, isWidth: false) > minAllowedY) {
          minAllowedY = z.boundary.top + minimumZoneSpanMm(z, isWidth: false);
        }
      }
      if ((z.boundary.top - (divisionY + sep)).abs() < 2) {
        if (z.boundary.bottom - minimumZoneSpanMm(z, isWidth: false) < maxAllowedY) {
          maxAllowedY = z.boundary.bottom - minimumZoneSpanMm(z, isWidth: false);
        }
      }
    }

    double newDivisionY = divisionY + diff;
    // No legal position: the neighbouring zones are already at their minimum.
    if (minAllowedY + sep > maxAllowedY - sep) return;
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
































  AluminumSection? frameSectionForRect(Rect frame) {
    final sliding = frameUsesSlidingSeries(frame);
    final selected = sliding ? slidingFrameOverride : activeFrameOverride;
    if (selected != null) return AluminumSection.fromMap(selected);
    return getConfiguredSectionForRole('frame', useSlidingSeries: sliding) ??
        (sliding ? getSlidingBaseFrameSection() : getSectionByType('frame'));
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






  void toggleShowWall(bool value) {
    _saveSnapshot();
    showWall = value;
    notifyListeners();
  }








































  /// Result of the last automatic glazing fit, shown in the glass drawer.
  GlazingFitReport? glazingFitReport;
































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
      // Inside the arch (above the openings) a stroke is never a new frame:
      // it divides the opening under the arch.
      final startsInsideArch =
          archHeight > 0 && this.windowOutlinePath().contains(pos);
      if ((windowRect.contains(pos) && startsInsideFrame) ||
          startsInsideArch) {
        drawingMode = 'split';
      } else {
        drawingMode = 'add_frame';
      }
    }
    _splitRawStart = drawingMode == 'split' ? pos : null;
    drawingStart = pos;
    drawingCurrent = pos;
    notifyListeners();
  }

  /// Where a division stroke started, before [splitStartUnderArch] moved it.
  Offset? _splitRawStart;

  /// Start of a division stroke begun at [start] and now at [current]. Under
  /// an arch a horizontal division never rises into the arch: it stays at
  /// or below the springing line (where the arch ends). A vertical or
  /// slanted one starts in the opening right under the arch.
  Offset splitStartUnderArch(Offset start, Offset current) {
    if (archHeight <= 0) return start;
    final delta = current - start;
    final horizontal = delta.dx.abs() > delta.dy.abs();
    final springing =
        math.max(topSlantLeftY, topSlantRightY) + profileThickness;
    var y = horizontal ? math.max(start.dy, springing) : start.dy;
    final under = zones
        .where(
          (zone) =>
              start.dx >= zone.boundary.left && start.dx <= zone.boundary.right,
        )
        .toList();
    if (under.isEmpty) return start;
    if (!under.any((zone) => zone.boundary.contains(Offset(start.dx, y)))) {
      final top = under.map((zone) => zone.boundary.top).reduce(math.min);
      if (y < top) y = top + 1;
    }
    return Offset(start.dx, y);
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
      final rawStart = _splitRawStart;
      if (drawingMode == 'split' && rawStart != null) {
        // The dashed preview shows the division where it will really go.
        drawingStart = splitStartUnderArch(rawStart, pos);
      }
    }
    notifyListeners();
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
    try {
      _endDrawingImpl();
    } finally {
      // If any branch throws, a non-null drawingStart made the drawing page
      // treat every later click as a continuing drag (mouse "stuck").
      if (drawingStart != null || drawingCurrent != null) {
        drawingStart = null;
        drawingCurrent = null;
        notifyListeners();
      }
      pendingDrawStart = null;
      _splitRawStart = null;
    }
  }

  void _endDrawingImpl() {
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
        cornerNotches = CornerNotches.none;
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
        // A first frame is never smaller than 250 mm per side.
        final firstFrame = _limitFrameSize(drawnRect.width, drawnRect.height);
        width = firstFrame.width;
        height = firstFrame.height;
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
            glass: defaultGlass.clone(),
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
      final previousFrameRects = getFrameRects();
      final previousBottomFrameByZone = <String, bool>{};
      for (final zone in zones) {
        var state = effectiveHasBottomFrame;
        for (final frame in previousFrameRects) {
          if (frame.contains(zone.boundary.center)) {
            state = hasBottomFrameForRect(frame);
            break;
          }
        }
        previousBottomFrameByZone[zone.id] = state;
      }
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
            drawnRect.bottom - profileThickness,
          );
          if (inner.width > 50 && inner.height > 50) {
            zones.add(
              WindowZone(
                id: UniqueKey().toString(),
                glass: defaultGlass.clone(),
                boundary: inner,
                sashThickness: _calculateSashThickness(false),
                sashColor: FrameColor.white,
                selectedDbColor: _selectedDbColor,
              ),
            );
            for (final zone in zones) {
              componentOverrides['frame-bottom:${zone.id}'] =
                  previousBottomFrameByZone[zone.id] ?? true;
            }
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
        final double newFrameBottomOffset = profileThickness;

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
        // The new frame shares its other side with the frames it is placed
        // against: the 250 mm rule applies to both of its sides.
        if (minVal == dxRight || minVal == dxLeft) {
          newW = math.max(newW, minimumFrameSideFor(spanBottom - spanTop));
        } else {
          newH = math.max(newH, minimumFrameSideFor(spanRight - spanLeft));
        }

        final double prevW = width;
        final double prevH = height;
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
              glass: defaultGlass.clone(),
              boundary: Rect.fromLTRB(
                oldW + tThickness / 2,
                spanTop +
                    (spanTop <= 1.0
                        ? topOffset + profileThickness
                        : tThickness / 2),
                width - profileThickness,
                spanBottom -
                    (spanBottom >= height - 1.0
                        ? newFrameBottomOffset + pHeight
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
              glass: defaultGlass.clone(),
              boundary: Rect.fromLTRB(
                profileThickness,
                spanTop +
                    (spanTop <= 1.0
                        ? topOffset + profileThickness
                        : tThickness / 2),
                newW - tThickness / 2,
                spanBottom -
                    (spanBottom >= height - 1.0
                        ? newFrameBottomOffset + pHeight
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
              glass: defaultGlass.clone(),
              boundary: Rect.fromLTRB(
                spanLeft +
                    (spanLeft <= 1.0 ? profileThickness : tThickness / 2),
                oldH + tThickness / 2,
                spanRight -
                    (spanRight >= width - 1.0
                        ? profileThickness
                        : tThickness / 2),
                height - newFrameBottomOffset - pHeight,
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
              glass: defaultGlass.clone(),
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
        for (final zone in zones) {
          componentOverrides['frame-bottom:${zone.id}'] =
              previousBottomFrameByZone[zone.id] ?? true;
        }
        // A full-length couvre-joint is anchored to the outer perimeter.
        // Growing the drawing with another physical frame must grow those
        // stored segments as well; otherwise the cover stops at the old
        // 800 mm / old height boundary.
        _resizeSideCoverSegments(prevW, prevH, width, height);
        updatePrimaryMullionAxis();
        synchronizeShutterAfterFrameResize(prevW, prevH);
      }
      drawingStart = null;
      drawingCurrent = null;
      notifyListeners();
      return;
    }
    double dx = drawingCurrent!.dx - drawingStart!.dx;
    double dy = drawingCurrent!.dy - drawingStart!.dy;
    // A clearly diagonal stroke (between the minimum angle and its
    // complement) inside a fixed zone draws a slanted mullion along it,
    // extended to the zone's sides. Near-horizontal or near-vertical strokes
    // keep splitting the zone as before.
    final slantedStroke = isSlantedStroke(drawingStart!, drawingCurrent!);
    WindowZone? strokeZone;
    for (final z in zones) {
      if (z.boundary.contains(drawingStart!)) {
        strokeZone = z;
        break;
      }
    }
    final strokeInFixedZone =
        strokeZone != null &&
        (strokeZone.content == ZoneContent.fixedGlass ||
            strokeZone.content == ZoneContent.empty);
    // Once a fixed zone has a slanted division, a straight stroke in it is
    // a division of the cell it was drawn in too: it stops on the earlier
    // divisions instead of splitting the whole zone through them.
    final straightAfterSlant =
        !slantedStroke &&
        strokeInFixedZone &&
        strokeZone.slantedDividers.isNotEmpty &&
        (dx.abs() > 2 || dy.abs() > 2);
    if (slantedStroke || straightAfterSlant) {
      final slantZone = strokeZone;
      if (slantZone != null && strokeInFixedZone) {
        final start = drawingStart!;
        final ends = SlantedDivisionGeometry.anchorsThrough(
          slantZone.boundary,
          start,
          slantedStroke
              ? drawingCurrent!
              : start +
                    (dx.abs() > dy.abs()
                        ? const Offset(1, 0)
                        : const Offset(0, 1)),
        );
        if (ends != null) {
          // The clock may give two quick strokes the same time: the id must
          // stay new, or the second stroke replaces the first division.
          var id = 'slant_${DateTime.now().microsecondsSinceEpoch}';
          while (slantZone.slantedDividers.any((d) => d.id == id)) {
            id = '${id}_';
          }
          final r = slantZone.boundary;
          // _endDrawingImpl already saved the undo step for this stroke.
          drawingNotice = setSlantedDivider(
            slantZone.id,
            SlantedDivider(
              id: id,
              start: ends.$1,
              end: ends.$2,
              seed: Offset(
                ((start.dx - r.left) / r.width).clamp(0.0, 1.0),
                ((start.dy - r.top) / r.height).clamp(0.0, 1.0),
              ),
            ),
            saveHistory: false,
          );
          if (drawingNotice == null) {
            selectedSlantedDivider = (zoneId: slantZone.id, dividerId: id);
          }
        }
        drawingStart = null;
        drawingCurrent = null;
        notifyListeners();
        return;
      }
    }
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

          // Same 80 mm clear-glass rule as _clampInnerDivisionRatio.
          final cellPitch =
              minimumSashCellMm +
              getSectionThickness('mullion', fallback: sashT);
          double minRatioH = cellPitch / glassR.height;
          double minRatioV = cellPitch / glassR.width;

          if (isHorizontal) {
            double ratio = ((drawingStart!.dy - glassR.top) / glassR.height)
                .clamp(math.min(minRatioH, 0.5), math.max(0.5, 1.0 - minRatioH));
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
                // Keys left over from a former double sash look like
                // "right_0_1"; int.parse threw and froze the drawing page.
                final c = parts.length == 2 ? int.tryParse(parts[0]) : null;
                final h = parts.length == 2 ? int.tryParse(parts[1]) : null;
                if (c == null || h == null) {
                  updatedDisabled[key] = value;
                  return;
                }
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
                .clamp(math.min(minRatioV, 0.5), math.max(0.5, 1.0 - minRatioV));
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

          final cellPitch =
              minimumSashCellMm +
              getSectionThickness('mullion', fallback: sashT);
          double minRatioH = cellPitch / glassR.height;
          double minRatioV = cellPitch / glassR.width;

          if (isHorizontal) {
            double ratio = ((drawingStart!.dy - glassR.top) / glassR.height)
                .clamp(math.min(minRatioH, 0.5), math.max(0.5, 1.0 - minRatioH));
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
                .clamp(math.min(minRatioV, 0.5), math.max(0.5, 1.0 - minRatioV));
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


  WindowZone _splitClone(WindowZone source, Rect boundary) {
    return source.cloneForSplit(boundary);
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
    cornerNotches = CornerNotches.none;
    hasSideCovers = false;
    useCustomSideCoverLayout = false;
    sideCoverSegments = [];
    hiddenSideCoverSegments = {};

    // Clear histories
    _history.clear();
    _redoHistory.clear();

    notifyListeners();
  }







}

class PlacedFrame {
  WindowModel model;
  Offset position;

  PlacedFrame({required this.model, required this.position});
}

class PhysicalFrameInfo {
  final int index;
  final Rect rect;
  final List<WindowZone> zones;

  const PhysicalFrameInfo({
    required this.index,
    required this.rect,
    required this.zones,
  });

  String get primaryZoneId => zones.isNotEmpty ? zones.first.id : '';
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

/// Face-to-face is physically valid only when every rail carries two leaves:
/// two rails/four leaves or three rails/six leaves. Higher rail counts cannot
/// qualify because the drawing currently supports at most seven leaves.
bool isSlidingFaceToFaceLayout({
  required int trackCount,
  required int sashCount,
}) => trackCount >= 2 && sashCount == trackCount * 2;

/// Keys of the actual internal sash edges. In a face-to-face layout the two
/// meeting edges are intentionally omitted: they belong to the meeting joint,
/// not to Montant Slim. For six leaves this yields 0,1,2,3,6,7,8,9.
List<String> slidingCentralEdgeKeys({
  required WindowZone zone,
  required int sashesCount,
}) {
  final hasCentralMeeting =
      zone.slidingFaceToFace &&
      isSlidingFaceToFaceLayout(
        trackCount: zone.slidingTrackCount,
        sashCount: sashesCount,
      );
  final halfSashes = sashesCount ~/ 2;
  final keys = <String>[];
  for (var sash = 0; sash < sashesCount; sash++) {
    final meetingLeft = hasCentralMeeting && sash == halfSashes;
    final meetingRight = hasCentralMeeting && sash == halfSashes - 1;
    if (sash > 0 && !meetingLeft) {
      keys.add('central_${(sash - 1) * 2 + 1}');
    }
    if (sash < sashesCount - 1 && !meetingRight) {
      keys.add('central_${sash * 2}');
    }
  }
  return keys;
}

/// What the automatic glazing fit decided for one glass, for the drawer
/// message. [fit] is set when the pack fits; otherwise [suggestion] holds a
/// combination that would fit (another spacer, or other panes).
class GlazingFitReport {
  const GlazingFitReport({
    required this.structure,
    required this.usesBead,
    required this.sliding,
    required this.capacity,
    required this.outer,
    required this.inner,
    required this.spacer,
    required this.valid,
    this.beadName,
    this.manualSpacer = false,
    this.fit,
    this.suggestion,
  });

  final GlassStructure structure;
  final bool usesBead;
  final bool sliding;
  final String? beadName;
  final double? capacity;
  final double outer;
  final double inner;
  final double spacer;
  final bool valid;
  final bool manualSpacer;
  final GlassPackFit? fit;
  final GlassPackFit? suggestion;

  /// Whether this report describes [spec] (the drawer shows the report of
  /// the glass that is selected, not of another pane).
  bool describes(GlassSpecification spec) {
    if (spec.structure != structure) return false;
    final specOuter = spec.thicknessOuter ?? kDefaultGlassPaneThickness;
    if ((specOuter - outer).abs() > 0.01) return false;
    if (structure != GlassStructure.double) return true;
    final specInner = spec.thicknessInner ?? kDefaultGlassPaneThickness;
    return (specInner - inner).abs() <= 0.01 &&
        (spec.intercallThickness - spacer).abs() <= 0.01;
  }
}
