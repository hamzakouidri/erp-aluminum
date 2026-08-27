import 'package:flutter/material.dart';
import '../../widgets/section_image.dart';
import '../../sql_database.dart';
import 'model.dart';

/// The component row that opened the selector belongs either to an opening
/// sash or to a sliding sash.  It must not be inferred from a commercial
/// series name: a PVC catalogue can contain both kinds of hardware.
enum AccessoryDrawingMode { opening, sliding }

String _accessorySearchText(Map<String, dynamic> accessory) =>
    '${accessory['name'] ?? ''} ${accessory['type'] ?? ''}'.toLowerCase();

bool _containsAny(String value, Iterable<String> terms) =>
    terms.any((term) => value.contains(term));

bool _isScrewSelectorType(String profileType) {
  final lower = profileType.toLowerCase();
  return lower.contains('_screw') ||
      lower.contains('screw') ||
      profileType.contains('براغي');
}

bool _isShutterScrewSelectorType(String profileType) {
  final lower = profileType.toLowerCase();
  return lower == 'is_kit_screw' ||
      lower == 'is_caisson_screw' ||
      lower == 'is_moteur_screw' ||
      lower == 'is_manivelle_screw' ||
      (profileType.contains('براغي') &&
          (profileType.contains('الكيت') ||
              profileType.contains('الصندوق') ||
              profileType.contains('المحرك') ||
              profileType.contains('المانيفال')));
}

/// A catalogue item is linked to a series only through [series_id] or
/// [series_ids]. Text in its name/type must never make it appear in another
/// series.
bool catalogItemMatchesSeries(Map<String, dynamic> item, int seriesId) {
  final directId = int.tryParse((item['series_id'] ?? '').toString().trim());
  final linkedIds = (item['series_ids'] ?? '')
      .toString()
      .split(',')
      .map((value) => int.tryParse(value.trim()))
      .whereType<int>()
      .where((id) => id > 0)
      .toSet();

  return directId == seriesId || linkedIds.contains(seriesId);
}

bool catalogItemHasSeriesScope(Map<String, dynamic> item) {
  final directId = int.tryParse((item['series_id'] ?? '').toString().trim());
  final linkedIds = (item['series_ids'] ?? '')
      .toString()
      .split(',')
      .map((value) => int.tryParse(value.trim()))
      .whereType<int>()
      .where((id) => id > 0)
      .toSet();
  return (directId != null && directId > 0) || linkedIds.isNotEmpty;
}

bool catalogItemMatchesSeriesOrGlobal(Map<String, dynamic> item, int seriesId) {
  if (!catalogItemHasSeriesScope(item)) return true;
  return catalogItemMatchesSeries(item, seriesId);
}

bool isEspagnoletteAccessory(Map<String, dynamic> accessory) => _containsAny(
  _accessorySearchText(accessory),
  const ['espagnol', 'إسبانيول', 'اسبانيول', 'سبانيول'],
);

bool isHingeAccessory(Map<String, dynamic> accessory) =>
    _containsAny(_accessorySearchText(accessory), const [
      'paumelle',
      'pomelle',
      'charniere',
      'charnière',
      'hinge',
      'mifsal',
      'mifsel',
      'مفصل',
      'مفاص',
    ]);

bool isSlidingAccessory(Map<String, dynamic> accessory) =>
    _containsAny(_accessorySearchText(accessory), const [
      'couliss',
      'sliding',
      'منزلق',
      'جرار',
      'كوليس',
      'كوريس',
      'roulette',
      'عجلات',
    ]);

bool _isHandleAccessory(Map<String, dynamic> accessory) => _containsAny(
  _accessorySearchText(accessory),
  const ['poignée', 'poignee', 'handle', 'مقبض', 'بواني'],
);

/// Returns whether an accessory belongs in the normal window-handle picker.
///
/// The catalogue category is authoritative. A product may contain a brand or
/// model name such as "Rotax" while still being explicitly classified as a
/// window handle. Text exclusions are used only for old/generic records that
/// do not have a precise category.
bool isWindowHandleAccessory(Map<String, dynamic> accessory) {
  final name = (accessory['name'] ?? '').toString().toLowerCase();
  final rawType = (accessory['type'] ?? '').toString().toLowerCase();
  final category = rawType.split('|').first.trim();

  final isExplicitWindowHandle = _containsAny(category, const [
    'poignée fenêtre',
    'poignee fenetre',
    'window handle',
    'مقبض نافذة',
  ]);
  if (isExplicitWindowHandle) return true;

  final isExplicitDoorHandle = _containsAny(category, const [
    'poignée porte',
    'poignee porte',
    'door handle',
    'مقبض باب',
    'condamnation',
  ]);
  if (isExplicitDoorHandle) return false;

  final text = '$name $rawType';
  final hasHandle = _containsAny(text, const [
    'poignée',
    'poignee',
    'handle',
    'مقبض',
    'بواني',
  ]);
  if (!hasHandle) return false;

  final isDoorOrSpecial = _containsAny(text, const [
    'porte',
    'door',
    'clé',
    'clef',
    'condamnation',
    'rotax',
    'calimaster',
    'maréchal',
    'marechal',
  ]);
  return !isDoorOrSpecial;
}

bool _catalogFlag(Map<String, dynamic> item, String key) {
  final value = item[key];
  if (value is bool) return value;
  if (value is num) return value != 0;
  final text = value?.toString().trim().toLowerCase();
  return text == '1' || text == 'true' || text == 'yes';
}

bool _catalogTextHasAny(Map<String, dynamic> item, Iterable<String> terms) {
  final text = normalizeArabic(_accessorySearchText(item));
  return terms.any(
    (term) => text.contains(normalizeArabic(term.toLowerCase())),
  );
}

bool accessoryMatchesSelectorType(
  Map<String, dynamic> accessory,
  String selectorType, {
  double? maxAccessoryLength,
}) {
  final tLower = normalizeArabic(selectorType.toLowerCase().trim());
  final name = normalizeArabic(
    (accessory['name'] ?? '').toString().toLowerCase(),
  );
  final type = normalizeArabic(
    (accessory['type'] ?? '').toString().toLowerCase(),
  );
  final text = '$name $type';

  bool hasAny(Iterable<String> terms) =>
      terms.any((term) => text.contains(normalizeArabic(term.toLowerCase())));
  bool selectorHasAny(Iterable<String> terms) =>
      terms.any((term) => tLower.contains(normalizeArabic(term.toLowerCase())));

  bool isScrew() => hasAny(const ['screw', 'vis', 'برغي', 'براغي']);
  bool isGache() => hasAny(const ['gache', 'gâche', 'gage', 'قاش', 'كاش']);
  bool isHandle() =>
      hasAny(const ['poignée', 'poignee', 'handle', 'مقبض', 'بواني']);
  bool isLock() => hasAny(const ['serrure', 'lock', 'قفل']);
  bool isKey() => hasAny(const ['clef', 'clé', 'مفتاح']);
  bool isCondamnation() => hasAny(const ['condamnation', 'حمام', 'بدون مفتاح']);
  bool isDoor() => hasAny(const ['porte', 'door', 'بورت', 'باب']);
  bool isDouble() => hasAny(const ['double', 'doub', 'دوبل']);
  bool isSimple() => hasAny(const ['simple', 'سامبل']);
  bool isSliding() =>
      hasAny(const ['couliss', 'sliding', 'منزلق', 'جرار', 'كوليس']);

  if (tLower.startsWith('is_') && _catalogFlag(accessory, selectorType)) {
    return true;
  }

  switch (tLower) {
    case 'is_kit_screw':
      return isScrew() && hasAny(const ['kit', 'كيت']);
    case 'is_caisson_screw':
      return isScrew() && hasAny(const ['caisson', 'box', 'coffre', 'صندوق']);
    case 'is_moteur_screw':
      return isScrew() && hasAny(const ['moteur', 'motor', 'محرك']);
    case 'is_manivelle_screw':
      return isScrew() && hasAny(const ['manivelle', 'مانيف']);
    case 'is_batmo_screw':
      return isScrew() && hasAny(const ['batmo', 'باتمو']);
    case 'is_bouchon_batmo_screw':
      return isScrew() &&
          hasAny(const ['bouchon', 'bochon', 'batment', 'بوشون']);
    case 'is_renfort_screw':
      return isScrew() && hasAny(const ['renfort', 'حديد', 'رنفور']);
    case 'is_assembly_screw':
      return isScrew() && hasAny(const ['assembl', 'تجميع']);
    case 'is_installation_screw':
      return isScrew() && hasAny(const ['install', 'تركيب']);
    case 'is_accessory_screw':
      return isScrew();
    case 'is_gache_simple':
      return isGache() && !isDouble() && !isDoor();
    case 'is_gache_double':
      return isGache() && (isDouble() || selectorHasAny(const ['دوبل']));
    case 'is_gache_porte':
      return isGache() && (isDoor() || (!isSimple() && !isDouble()));
    case 'is_lock_clef':
      return isLock() &&
          isKey() &&
          !isHandle() &&
          !_catalogTextHasAny(accessory, const ['canon', 'اسطوانة', 'أسطوانة']);
    case 'is_lock_condamnation':
      return isLock() && isCondamnation() && !isHandle();
    case 'is_canon':
      return hasAny(const [
        'canon',
        'cylinder',
        'barillet',
        'اسطوانة',
        'أسطوانة',
      ]);
    case 'is_poign_clef':
      return isHandle() && isKey();
    case 'is_poign_condamnation':
      return isHandle() && isCondamnation();
    case 'is_window_handle':
      return isWindowHandleAccessory(accessory);
  }

  if (selectorHasAny(const ['gache couliss', 'gâche couliss', 'كاش كوليسون'])) {
    return isGache() && isSliding();
  }
  if (selectorHasAny(const [
    'poignee coulissante',
    'poignée coulissante',
    'مقبض منزلق',
  ])) {
    return isHandle() && isSliding();
  }
  if (selectorHasAny(const [
    'espagnolette',
    'اسبانيوليت',
    'إسبانيوليت',
    'سبانيوليت',
  ])) {
    final isEspagnolette = hasAny(const [
      'espagnol',
      'اسبانيول',
      'إسبانيول',
      'سبانيول',
    ]);
    if (!isEspagnolette) return false;
    if (maxAccessoryLength == null || maxAccessoryLength <= 0) return true;
    final rawSize = (accessory['measurement'] ?? '').toString();
    final source = rawSize.isNotEmpty ? rawSize : text;
    final sizeMatch = RegExp(r'(\d+(?:[.,]\d+)?)').firstMatch(source);
    final length = sizeMatch == null
        ? null
        : double.tryParse(sizeMatch.group(1)!.replaceAll(',', '.'));
    return length != null && length <= maxAccessoryLength;
  }
  if (selectorHasAny(const ['clamp', 'clam', 'كلامب', 'كلام', 'كلان'])) {
    return hasAny(const ['clamp', 'clam', 'كلامب', 'كلام', 'كلان']) &&
        !hasAny(const ['kit', 'كيت']);
  }
  if (tLower == 'kit' || selectorHasAny(const ['كيت'])) {
    return hasAny(const ['kit', 'كيت']) &&
        !hasAny(const ['clamp', 'clam', 'كلامب', 'كلام', 'كلان']);
  }
  if (selectorHasAny(const ['tasso', 'طاسو', 'طاصو'])) {
    return hasAny(const [
      'tasso',
      'tasseau',
      'equerre',
      'équerre',
      'طاسو',
      'طاصو',
    ]);
  }
  if (selectorHasAny(const ['roulette', 'عجلات'])) {
    return hasAny(const ['roulette', 'رول', 'عجل']);
  }
  if (selectorHasAny(const [
    'entrematique',
    'انتراميتيك',
    'أونتروماتيك',
    'intra',
  ])) {
    return hasAny(const ['entrematique', 'انتراميتيك', 'أونتروماتيك', 'intra']);
  }
  if (selectorHasAny(const ['hinges', 'paumelle', 'مفاصل'])) {
    return isHingeAccessory(accessory);
  }
  if (selectorHasAny(const ['verrou', 'فيرو'])) {
    return hasAny(const ['verrou', 'verro', 'viro', 'فيرو']);
  }
  if (selectorHasAny(const ['مقبض', 'handle', 'poignée', 'poignee'])) {
    return isHandle();
  }
  if (selectorHasAny(const ['serrure', 'lock', 'قفل'])) {
    return isLock();
  }

  return name.contains(tLower) ||
      type.contains(tLower) ||
      tLower.contains(name) ||
      tLower.contains(type);
}

List<String> catalogRuleKeysForAccessorySelectorType(String selectorType) {
  final tLower = normalizeArabic(selectorType.toLowerCase().trim());
  if (tLower == 'is_kit_screw') return const ['kit_screw'];
  if (tLower == 'is_caisson_screw') return const ['box_screw'];
  if (tLower == 'is_moteur_screw') return const ['motor_screw'];
  if (tLower == 'is_batmo_screw') return const ['batmo_screw'];
  if (tLower == 'is_bouchon_batmo_screw') {
    return const ['bouchon_batmo_screw'];
  }
  if (tLower == 'is_renfort_screw') return const ['renfort_screw'];
  if (tLower == 'is_manivelle_screw') return const ['manivelle_screw'];
  if (tLower == 'is_assembly_screw') return const ['assembly_screw'];
  if (tLower == 'is_installation_screw') {
    return const ['installation_screw'];
  }
  if (tLower == 'is_accessory_screw') return const ['accessory_screw'];
  if (tLower.contains('clamp') ||
      tLower.contains('clam') ||
      tLower.contains('كلام')) {
    return const ['sliding_clamp'];
  }
  if (tLower.contains('gache couliss') ||
      tLower.contains('gâche couliss') ||
      tLower.contains('كاش كوليسون')) {
    return const ['sliding_lock'];
  }
  if (tLower == 'is_window_handle' ||
      tLower.contains('poignee') ||
      tLower.contains('poignée') ||
      tLower.contains('handle') ||
      tLower.contains('مقبض')) {
    return const ['handle'];
  }
  if (tLower.contains('hinge') ||
      tLower.contains('paumelle') ||
      tLower.contains('مفاصل')) {
    return const ['hinge'];
  }
  return const [];
}

List<String> catalogFlagColumnsForAccessorySelectorType(String selectorType) {
  final tLower = normalizeArabic(selectorType.toLowerCase().trim());
  const columns = {
    'is_gache_simple',
    'is_gache_double',
    'is_gache_porte',
    'is_lock_clef',
    'is_lock_condamnation',
    'is_moteur_screw',
    'is_caisson_screw',
    'is_batmo_screw',
    'is_bouchon_batmo_screw',
    'is_renfort_screw',
    'is_manivelle_screw',
    'is_tandem_screw',
    'is_kit_screw',
    'is_assembly_screw',
    'is_installation_screw',
    'is_accessory_screw',
  };
  return columns.contains(tLower) ? <String>[tLower] : const <String>[];
}

List<String> catalogRuleKeysForJointSelectorType(String selectorType) {
  final tLower = normalizeArabic(selectorType.toLowerCase().trim());
  if (tLower.contains('vitrage') ||
      tLower.contains('فيتراج') ||
      tLower.contains('زجاج')) {
    return const ['joint_vitrage'];
  }
  if (tLower.contains('bourrage') || tLower.contains('بوراج')) {
    return const ['joint_bourrage'];
  }
  if (tLower.contains('frappe') ||
      tLower.contains('فراب') ||
      tLower.contains('ضرب')) {
    return const ['joint_frappe'];
  }
  if (tLower.contains('central') ||
      tLower.contains('centrale') ||
      tLower.contains('سنترال') ||
      tLower.contains('وسط')) {
    return const ['joint_central'];
  }
  if (tLower.contains('bross') ||
      tLower.contains('brosse') ||
      tLower.contains('بروس')) {
    return const ['joint_brosse'];
  }
  return const [];
}

bool jointCatalogItemMatchesRole(Map<String, dynamic> joint, String roleKey) {
  final rawType = normalizeArabic(
    (joint['gasket_type'] ?? '').toString().toLowerCase().trim(),
  );
  switch (roleKey) {
    case 'joint_vitrage':
      return rawType == 'joint_vitrage' || rawType == 'جوان فيتراج';
    case 'joint_bourrage':
      return rawType == 'joint_bourrage' ||
          rawType == 'جوان بوراج' ||
          rawType == 'جوان البوراج';
    case 'joint_frappe':
      return rawType == 'joint_frappe' ||
          rawType == 'جوان فراب' ||
          rawType == 'جوان الضرب';
    case 'joint_central':
      return rawType == 'joint_central' ||
          rawType == 'joint_centrale' ||
          rawType == 'جوان سنترال' ||
          rawType == 'جوان الوسط';
    case 'joint_brosse':
      return rawType == 'joint_brosse' ||
          rawType == 'joint_bross' ||
          rawType == 'جوان بروس';
  }
  return false;
}

List<String> seriesRoleKeysForProfileSelectorType(String selectorType) {
  final t = normalizeArabic(selectorType.toLowerCase().trim());
  if (t == 'frame' || t == 'cadre' || t == 'إطار') {
    return const ['frame', 'frame_extension'];
  }
  if (t == 'sash' || t == 'ouvrant' || t == 'ضلفة') {
    return const ['sash', 'sash_extension'];
  }
  if (t == 'parclose') return const ['glazing_bead'];
  if (t.contains('sash_traverse') || t.contains('sash traverse')) {
    return const ['sash_traverse', 'traverse'];
  }
  if (t.contains('sash_lateral') ||
      t.contains('lateral') ||
      t.contains('latéral') ||
      t.contains('جانبي')) {
    return const ['sash_lateral', 'lateral'];
  }
  if (t.contains('sash_central') ||
      t.contains('central') ||
      t.contains('chicane') ||
      t.contains('وسطي')) {
    return const ['sash_central', 'central', 'chicane'];
  }
  if (t == 'mullion' || t == 'traverse') return const ['mullion'];
  if (t.contains('couvre') || t.contains('side cover') || t.contains('غطاء')) {
    return const ['side_cover'];
  }
  if (t == 'rail' || t.contains('rail') || t.contains('سكة')) {
    return const ['rail'];
  }
  if (t.contains('reduct') || t.contains('67114') || t.contains('ريديك')) {
    return const ['reducer'];
  }
  if (t == 'batmo') return const ['batmo'];
  if (t.contains('bouchon')) return const ['bouchon_batmo'];
  if (t == 'renfort') return const ['renfort'];
  return const [];
}

/// Filters hardware using the actual sash type that produced its BOM row.
/// In particular, an unqualified espagnolette or window handle is an opening
/// component; sliding variants must be explicitly labelled as sliding.
bool accessoryMatchesDrawingMode(
  Map<String, dynamic> accessory,
  AccessoryDrawingMode drawingMode,
) {
  final isSliding = isSlidingAccessory(accessory);

  if (isEspagnoletteAccessory(accessory) || _isHandleAccessory(accessory)) {
    return drawingMode == AccessoryDrawingMode.sliding ? isSliding : !isSliding;
  }

  if (isHingeAccessory(accessory)) {
    return drawingMode == AccessoryDrawingMode.opening;
  }

  // Rollers, sliding strikes and other components explicitly labelled as
  // sliding never belong in an opening-sash selector.
  if (drawingMode == AccessoryDrawingMode.opening && isSliding) return false;

  // Hardware that exists only for opening sashes must not leak into sliding
  // dialogs, even in a mixed drawing.
  final text = _accessorySearchText(accessory);
  final isOpeningOnly = _containsAny(text, const [
    'system ob',
    'demi system ob',
    'verrou central',
    'gache simple',
    'gâche simple',
    'gache double',
    'gâche double',
    'ouvrant',
    'frappe',
    'battant',
    'فتح',
  ]);
  return drawingMode != AccessoryDrawingMode.sliding || !isOpeningOnly;
}

String _sectionSearchText(Map<String, dynamic> section) =>
    '${section['code'] ?? ''} ${section['name'] ?? ''} ${section['type'] ?? ''}'
        .toLowerCase();

bool isSlidingProfileSection(Map<String, dynamic> section) {
  final text = _sectionSearchText(section);
  return _containsAny(text, const [
    'couliss',
    'sliding',
    '2rail',
    '3rail',
    '2 rail',
    '3 rail',
    'monorail',
    'galandage',
    'rail',
    'chicane',
    'sash lateral',
    'sash central',
    'sash traverse',
    'منزلق',
    'جرار',
    'كوليس',
    'جانبي',
    'وسطي',
    'سكة',
    'ريديكتور',
  ]);
}

bool profileSectionMatchesDrawingMode({
  required Map<String, dynamic> section,
  required String profileType,
  required String activeSeriesType,
  required AccessoryDrawingMode? drawingMode,
}) {
  if (drawingMode == null) return true;
  final t = profileType.toLowerCase().trim();
  final isSideCover =
      t.contains('couvre') ||
      t.contains('side cover') ||
      t.contains('غطاء') ||
      t.contains('كافر');
  if (isSideCover) return true;

  final seriesLooksSliding = _containsAny(activeSeriesType, const [
    'couliss',
    'sliding',
    'منزلق',
    'جرار',
  ]);
  final sectionLooksSliding = isSlidingProfileSection(section);

  if (drawingMode == AccessoryDrawingMode.sliding) {
    // A sliding selector must never show ordinary opening sections from a
    // foreign/opening series. If the selected series is itself marked
    // sliding, its configured rows are accepted even when their label is
    // short; otherwise the section must carry a sliding marker such as 2Rail.
    return seriesLooksSliding || sectionLooksSliding;
  }

  return !sectionLooksSliding;
}

bool _isX3dShutterComponent(Map<String, dynamic> component) {
  final text =
      '${component['name'] ?? ''} ${component['shutter_subtype'] ?? ''}'
          .toLowerCase();
  return text.contains('x3d') ||
      text.contains('extrud') ||
      text.contains('إكسترودي') ||
      text.contains('اكسترودي');
}

bool profileHasIntegratedSideCover(Map<String, dynamic> item) {
  final name = (item['name'] ?? '').toString().toLowerCase();
  final type = (item['type'] ?? '').toString().toLowerCase();
  final rawWidth = item['couvre_joint_width'];
  final width = rawWidth is num
      ? rawWidth.toDouble()
      : double.tryParse('${rawWidth ?? ''}') ?? 0.0;
  return width > 0 ||
      name.contains('مدمج') ||
      name.contains('intégré') ||
      name.contains('integre') ||
      name.contains('monobloc') ||
      type.contains('monobloc');
}

/// Axes created before the dedicated diameter field was available often keep
/// their diameter in the name (for example: "Axe 60 mm").  Prefer the
/// structured fields, then use that legacy value as a fallback.
double? shutterComponentDiameter(Map<String, dynamic> component) {
  for (final field in const ['motor_diameter', 'measurement', 'name']) {
    final value = (component[field] ?? '').toString().trim();
    final match = RegExp(r'(?<!\d)(\d{2,3}(?:[.,]\d+)?)').firstMatch(value);
    if (match != null) {
      return double.tryParse(match.group(1)!.replaceAll(',', '.'));
    }
  }
  return null;
}

class ProfileSelectorDialog extends StatefulWidget {
  final String profileType; // مثلاً 'Cadre'
  final String category; // 'profile', 'accessory', 'shutter'
  final int? seriesId;
  final String? materialType;
  final bool hasShutter;
  final double? windowHeight;
  final double? targetSize;
  final String? kitDescriptionCode;

  /// الحد الأقصى لطول الإسبانيوليت المطلوب للرسم. لا تعرض النافذة
  /// الإسبانيوليت الأطول منه لأنها لا تصلح للتركيب في هذه النافذة.
  final double? maxAccessoryLength;

  /// The mode of the sash that owns the component being replaced.  This is
  /// supplied by the BOM row and is more reliable than a series label.
  final AccessoryDrawingMode? accessoryDrawingMode;
  final int? bladeId;

  /// The currently selected blade.  Axes are explicitly linked to it through
  /// their shutter_subtype value in the shutter catalogue.
  final String? selectedBladeName;
  final bool? selectedBladeIsX3d;

  /// A selected motor cannot fit inside an axis with a smaller diameter.
  final double? motorDiameter;

  const ProfileSelectorDialog({
    super.key,
    required this.profileType,
    this.category = 'profile',
    this.seriesId,
    this.materialType,
    this.hasShutter = false,
    this.windowHeight,
    this.targetSize,
    this.kitDescriptionCode,
    this.maxAccessoryLength,
    this.accessoryDrawingMode,
    this.bladeId,
    this.selectedBladeName,
    this.selectedBladeIsX3d,
    this.motorDiameter,
  });

  @override
  _ProfileSelectorDialogState createState() => _ProfileSelectorDialogState();
}

class _ProfileSelectorDialogState extends State<ProfileSelectorDialog> {
  List<Map<String, dynamic>> profiles = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadProfiles();
  }

  Future<void> _loadProfiles() async {
    final db = SqlDatabase();
    List<Map<String, dynamic>> data = [];

    // Fetch active series name first so it is available globally in _loadProfiles
    String activeSeriesName = '';
    String activeSeriesType = '';
    final myDbInstance = await db.db;
    if (myDbInstance != null && widget.seriesId != null) {
      try {
        final sRes = await myDbInstance.query(
          'Series',
          columns: ['name', 'type'],
          where: 'id = ?',
          whereArgs: [widget.seriesId],
          limit: 1,
        );
        if (sRes.isNotEmpty) {
          activeSeriesName = (sRes.first['name'] ?? '')
              .toString()
              .toLowerCase();
          activeSeriesType = (sRes.first['type'] ?? '')
              .toString()
              .toLowerCase();
        }
      } catch (_) {}
    }

    if (widget.category == 'accessory' || widget.category == 'other') {
      final myDb = myDbInstance;
      if (myDb != null) {
        // الإكسسوار المرتبط بسلسلة يظهر لتلك السلسلة فقط. أما الإكسسوار
        // العام (بلا سلسلة) فيظهر لكل سلسلة تتطابق مادتها معه.
        Future<List<Map<String, dynamic>>> queryAccessories(
          String customWhere,
          List<dynamic> baseArgs,
        ) async {
          // A selector without a selected series must not become a catalogue
          // wide selector.  Showing unrelated parts is worse than showing an
          // empty list and prompting the user to choose a series first.
          if (widget.seriesId == null) {
            return const <Map<String, dynamic>>[];
          }

          List<dynamic> args = List.from(baseArgs);
          String where = customWhere;

          // يظهر إذا كان مرتبطاً بالسلسلة مباشرة أو ضمن قائمة سلاسلها.
          // REPLACE handles old catalogues that stored "12, 13" with spaces.
          const linkedSeriesConstraint =
              "series_id = ? OR (series_ids IS NOT NULL AND TRIM(series_ids) != '' AND ',' || REPLACE(series_ids, ' ', '') || ',' LIKE ?)";
          final seriesConstraint =
              "$linkedSeriesConstraint OR ((series_id IS NULL OR series_id = 0) AND (series_ids IS NULL OR TRIM(series_ids) = ''))";
          where += ' AND ($seriesConstraint)';
          args.add(widget.seriesId);
          args.add('%,' + widget.seriesId.toString() + ',%');

          final profileTypeLower = widget.profileType.toLowerCase();
          final isScrewLookup = _isScrewSelectorType(widget.profileType);
          final isShutterScrewLookup = _isShutterScrewSelectorType(
            widget.profileType,
          );

          if (widget.materialType != null && !isShutterScrewLookup) {
            final mat = widget.materialType!.toLowerCase().trim();
            if (mat == 'pvc') {
              // PVC: يظهر فقط ما هو pvc أو both. الـ NULL/فارغ = ألمنيوم بالافتراضي → لا يظهر في PVC
              where +=
                  " AND (TRIM(LOWER(material_type)) = 'pvc' OR TRIM(LOWER(material_type)) = 'both')";
            } else {
              // Aluminium: يظهر ما هو aluminium أو both أو NULL/فارغ (الافتراضي = ألمنيوم)
              where +=
                  " AND (TRIM(LOWER(material_type)) = 'aluminium' OR TRIM(LOWER(material_type)) = 'aluminum' OR TRIM(LOWER(material_type)) = 'both' OR material_type IS NULL OR TRIM(material_type) = '')";
            }
          }

          String? orderBy;
          if (widget.seriesId != null) {
            final sid = widget.seriesId;
            orderBy =
                'CASE WHEN series_id = $sid OR (series_ids IS NOT NULL AND TRIM(series_ids) != \'\' AND \',\' || REPLACE(series_ids, \' \', \'\') || \',\' LIKE \'%,$sid,%\') THEN 0 ELSE 1 END ASC, id ASC';
          }

          final rawRows = await myDb.query(
            'Accessories',
            where: where,
            whereArgs: args,
            orderBy: orderBy,
          );
          var scopedRows = rawRows
              .map((row) => Map<String, dynamic>.from(row))
              .toList();
          final exactSeriesRows = scopedRows
              .where((row) => catalogItemMatchesSeries(row, widget.seriesId!))
              .toList();
          if (!isShutterScrewLookup && exactSeriesRows.isNotEmpty) {
            scopedRows = exactSeriesRows;
          }

          return scopedRows.where((a) {
            if (!catalogItemMatchesSeriesOrGlobal(a, widget.seriesId!)) {
              return false;
            }

            final n = a['name'].toString().toLowerCase();
            final ty = (a['type'] ?? '').toString().toLowerCase();
            final isClampLookup =
                profileTypeLower.contains('clamp') ||
                profileTypeLower.contains('clam') ||
                widget.profileType.contains('كلامب') ||
                widget.profileType.contains('كلام') ||
                widget.profileType.contains('كلان');

            final drawingMode =
                widget.accessoryDrawingMode ??
                ((activeSeriesType.contains('couliss') ||
                        activeSeriesType.contains('sliding') ||
                        activeSeriesType.contains('منزلق') ||
                        activeSeriesType.contains('جرار'))
                    ? AccessoryDrawingMode.sliding
                    : AccessoryDrawingMode.opening);
            if (!isScrewLookup &&
                !accessoryMatchesDrawingMode(a, drawingMode)) {
              return false;
            }

            // 1. Material Exclusions
            final mat = (widget.materialType ?? '').toLowerCase().trim();
            if (isShutterScrewLookup) {
              // Screws of the shutter kit/box/motor are stock accessories of
              // the shutter itself. They must not disappear when the selected
              // window material changes from PVC to Aluminium or the opposite.
            } else if (mat == 'pvc') {
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
                  (!isClampLookup &&
                      (n.contains('clan') ||
                          ty.contains('clan') ||
                          n.contains('clane') ||
                          ty.contains('clane') ||
                          n.contains('كلان') ||
                          ty.contains('كلان')))) {
                return false;
              }
            }

            // 2. Series Name Exclusions
            if (activeSeriesName.isNotEmpty) {
              final sName = activeSeriesName;
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
            }

            // 4. Kit Clamp/Clan Exclusions (Exclude clamp from kit matching, and vice versa)
            final isScrewQuery = isScrewLookup;
            final isKitQuery =
                !isScrewQuery &&
                (profileTypeLower.contains('kit') ||
                    widget.profileType.contains('كيت'));
            final isClampQuery = isClampLookup;

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

            if (isKitQuery && hasClampName) return false;
            if (isClampQuery && hasKitName) return false;

            return true;
          }).toList();
        }

        // Column-based filtering for Gache/Lock types
        const colMap = {
          'is_gache_simple': 'is_gache_simple',
          'is_gache_double': 'is_gache_double',
          'is_gache_porte': 'is_gache_porte',
          'is_lock_clef': 'is_lock_clef',
          'is_lock_condamnation': 'is_lock_condamnation',
          'is_moteur_screw': 'is_moteur_screw',
          'is_caisson_screw': 'is_caisson_screw',
          'is_batmo_screw': 'is_batmo_screw',
          'is_bouchon_batmo_screw': 'is_bouchon_batmo_screw',
          'is_renfort_screw': 'is_renfort_screw',
          'is_manivelle_screw': 'is_manivelle_screw',
          'is_tandem_screw': 'is_tandem_screw',
          'is_kit_screw': 'is_kit_screw',
          'is_assembly_screw': 'is_assembly_screw',
          'is_installation_screw': 'is_installation_screw',
          'is_accessory_screw': 'is_accessory_screw',
        };
        final t = widget.profileType;
        final ruleKeys = catalogRuleKeysForAccessorySelectorType(t);
        final typedColumns = catalogFlagColumnsForAccessorySelectorType(t);
        if (ruleKeys.isNotEmpty && widget.seriesId != null) {
          final rules = await db.getCatalogItemRules(
            itemTable: 'Accessories',
            seriesId: widget.seriesId,
            roleKeys: ruleKeys,
          );
          final visibleRules = rules
              .where((rule) => rule['show_in_dialog'] != 0)
              .toList();
          final ruleIds = visibleRules
              .map((rule) => (rule['item_id'] as num?)?.toInt())
              .whereType<int>()
              .toList();
          if (ruleIds.isNotEmpty) {
            final rows = await queryAccessories(
              'id IN (${List.filled(ruleIds.length, '?').join(',')}) AND (is_active = 1 OR is_active IS NULL)',
              ruleIds,
            );
            final byId = {
              for (final row in rows)
                if (row['id'] is num) (row['id'] as num).toInt(): row,
            };
            data = [
              for (final itemId in ruleIds)
                if (byId[itemId] != null) byId[itemId]!,
            ];
          }
        }
        if (data.isEmpty && typedColumns.isNotEmpty) {
          final columnWhere = typedColumns
              .map((column) => '$column = 1')
              .join(' OR ');
          data = await queryAccessories(
            '($columnWhere) AND (is_active = 1 OR is_active IS NULL)',
            [],
          );
        }
        final customTypes = [
          'is_lock',
          'is_canon',
          'is_poign_clef',
          'is_poign_condamnation',
        ];
        if (data.isEmpty && t == 'is_lock') {
          final customWhere =
              '(is_lock_clef = 1 OR is_lock_condamnation = 1) AND (is_active = 1 OR is_active IS NULL)';
          data = await queryAccessories(customWhere, []);
        } else if (data.isEmpty && t == 'is_canon') {
          data = [];
        } else if (data.isEmpty && t == 'is_poign_clef') {
          data = [];
        } else if (data.isEmpty && t == 'is_poign_condamnation') {
          data = [];
        } else if (data.isEmpty && colMap.containsKey(t)) {
          // Use column-based query
          final customWhere =
              '${colMap[t]} = 1 AND (is_active = 1 OR is_active IS NULL)';
          data = await queryAccessories(customWhere, []);
        }

        if (customTypes.contains(t) ||
            colMap.containsKey(t) ||
            ruleKeys.isNotEmpty ||
            typedColumns.isNotEmpty) {
          // Typed selectors are strict: no name/type fallback.
        } else {
          // Fall back to name/type text matching
          final allAcc = await queryAccessories(
            'is_active = 1 OR is_active IS NULL',
            [],
          );
          final tLower = t.toLowerCase();
          data = allAcc.where((a) {
            final n = a['name'].toString().toLowerCase();
            final ty = (a['type'] ?? '').toString().toLowerCase();

            if (tLower == 'is_window_handle') {
              return isWindowHandleAccessory(a);
            }

            if (tLower == 'فيرو' || tLower == 'verrou' || tLower == 'viro') {
              return n.contains('verrou') ||
                  ty.contains('verrou') ||
                  n.contains('verro') ||
                  ty.contains('verro') ||
                  n.contains('viro') ||
                  ty.contains('viro') ||
                  n.contains('فيرو') ||
                  ty.contains('فيرو');
            }

            if (tLower == 'اسبانيوليت' ||
                tLower == 'espagnolette' ||
                tLower.contains('اسبانيول') ||
                tLower.contains('إسبانيول')) {
              final isEspagnolette =
                  n.contains('espagnol') ||
                  ty.contains('espagnol') ||
                  n.contains('اسبانيول') ||
                  ty.contains('اسبانيول') ||
                  n.contains('سبانيول') ||
                  ty.contains('سبانيول');
              if (!isEspagnolette) return false;
              final maxLength = widget.maxAccessoryLength;
              if (maxLength == null || maxLength <= 0) return true;
              final rawSize = (a['measurement'] ?? '').toString();
              final sizeMatch = RegExp(r'(\d+(?:[.,]\d+)?)').firstMatch(
                rawSize.isNotEmpty
                    ? rawSize
                    : '${a['name'] ?? ''} ${a['type'] ?? ''}',
              );
              final length = sizeMatch == null
                  ? null
                  : double.tryParse(sizeMatch.group(1)!.replaceAll(',', '.'));
              // القيم بلا طول صريح لا تعد بديلاً آمناً لإسبانيوليت محسوب.
              return length != null && length <= maxLength;
            }
            if (tLower == 'clamp' ||
                tLower.contains('clamp') ||
                tLower.contains('clam') ||
                tLower.contains('كلامب') ||
                tLower.contains('كلام') ||
                tLower.contains('كلان')) {
              final isClamp =
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
              final isKit =
                  n.contains('kit') ||
                  ty.contains('kit') ||
                  n.contains('كيت') ||
                  ty.contains('كيت');
              return isClamp && !isKit;
            }
            if (tLower == 'kit' || tLower.contains('كيت')) {
              final isKit =
                  n.contains('kit') ||
                  ty.contains('kit') ||
                  n.contains('كيت') ||
                  ty.contains('كيت');
              final isClamp =
                  n.contains('clamp') ||
                  n.contains('clam') ||
                  ty.contains('clamp') ||
                  ty.contains('clam') ||
                  n.contains('كلامب') ||
                  n.contains('كلام') ||
                  ty.contains('كلامب') ||
                  ty.contains('كلام') ||
                  n.contains('كلان') ||
                  ty.contains('كلان') ||
                  n.contains('clan') ||
                  ty.contains('clan');
              return isKit && !isClamp;
            }
            if (tLower == 'كاش كوليسون' ||
                tLower == 'gache coulisse' ||
                tLower == 'gâche coulisse' ||
                tLower == 'gache coulissante' ||
                tLower == 'gâche coulissante' ||
                tLower == 'gache coulissant' ||
                tLower == 'gâche coulissant') {
              return n.contains('couliss') ||
                  ty.contains('couliss') ||
                  n.contains('كاش') ||
                  ty.contains('كاش') ||
                  n.contains('gache') ||
                  ty.contains('gache') ||
                  n.contains('gâche') ||
                  ty.contains('gâche');
            }
            if (tLower == 'poignee coulissante' ||
                tLower == 'poignée coulissante' ||
                tLower == 'مقبض منزلق') {
              final isHandle =
                  n.contains('poignée') ||
                  ty.contains('poignée') ||
                  n.contains('poignee') ||
                  ty.contains('poignee') ||
                  n.contains('handle') ||
                  ty.contains('handle') ||
                  n.contains('مقبض') ||
                  ty.contains('مقبض');
              final isSliding =
                  n.contains('couliss') ||
                  ty.contains('couliss') ||
                  n.contains('sliding') ||
                  ty.contains('sliding') ||
                  n.contains('منزلق') ||
                  ty.contains('منزلق') ||
                  n.contains('جرار') ||
                  ty.contains('جرار');
              return isHandle && isSliding;
            }
            if (tLower == 'tasso') {
              return n.contains('tasso') ||
                  n.contains('tasseau') ||
                  n.contains('طاسو') ||
                  n.contains('طاصو') ||
                  ty.contains('tasso') ||
                  ty.contains('tasseau') ||
                  ty.contains('طاسو') ||
                  ty.contains('طاصو');
            }
            if (tLower == 'batmo') {
              return (n.contains('batmo') || ty.contains('batmo')) &&
                  !n.contains('bouchon') &&
                  !ty.contains('bouchon') &&
                  !n.contains('bochon') &&
                  !ty.contains('bochon');
            }
            if (tLower == 'bouchon batmo' ||
                tLower == 'bouchon' ||
                tLower == 'bochon batment' ||
                tLower == 'bochon') {
              return n.contains('bouchon') ||
                  ty.contains('bouchon') ||
                  n.contains('bochon') ||
                  ty.contains('bochon') ||
                  n.contains('batment') ||
                  ty.contains('batment');
            }
            if (tLower == 'system ob') {
              return n.contains('system ob') ||
                  ty.contains('system ob') ||
                  n.contains('سيستم أو بي') ||
                  n.contains('سيستم او بي') ||
                  ty.contains('سيستم أو بي') ||
                  ty.contains('سيستم او بي');
            }
            if (tLower == 'entrematique') {
              return n.contains('entrematique') ||
                  n.contains('أونتروماتيك') ||
                  n.contains('انتراميتيك') ||
                  n.contains('intra') ||
                  ty.contains('entrematique') ||
                  ty.contains('أونتروماتيك') ||
                  ty.contains('انتراميتيك') ||
                  ty.contains('intra');
            }
            if (tLower == 'demi system ob' || tLower == 'demi ob') {
              return n.contains('demi') ||
                  ty.contains('demi') ||
                  n.contains('ديمي') ||
                  ty.contains('ديمي');
            }
            if (tLower == 'verrou central') {
              return n.contains('verrou central') ||
                  ty.contains('verrou central') ||
                  n.contains('فيرو سنترال') ||
                  ty.contains('فيرو سنترال') ||
                  n.contains('فيرو سونترال') ||
                  ty.contains('فيرو سونترال') ||
                  n.contains('central') ||
                  ty.contains('central') ||
                  n.contains('سنترال') ||
                  ty.contains('سنترال') ||
                  n.contains('سونترال') ||
                  ty.contains('سونترال');
            }

            if (tLower == 'مفاصل' ||
                tLower == 'hinges' ||
                tLower == 'paumelle' ||
                tLower == 'paumelles') {
              return isHingeAccessory(a);
            }
            if (tLower == 'مقبض' ||
                tLower == 'handle' ||
                tLower == 'poignée' ||
                tLower == 'poignée fenêtre' ||
                tLower == 'poignee fenetre' ||
                tLower == 'poignée tpr' ||
                tLower == 'poignee tpr' ||
                tLower == 'poignee') {
              return n.contains('poignée') ||
                  ty.contains('poignée') ||
                  n.contains('poignee') ||
                  ty.contains('poignee') ||
                  n.contains('handle') ||
                  ty.contains('handle') ||
                  n.contains('مقبض') ||
                  ty.contains('مقبض') ||
                  n.contains('بواني') ||
                  ty.contains('بواني') ||
                  n.contains('بوانيي') ||
                  ty.contains('بوانيي');
            }
            if (tLower == 'serrure' || tLower == 'lock' || tLower == 'قفل') {
              return n.contains('serrure') ||
                  ty.contains('serrure') ||
                  n.contains('lock') ||
                  ty.contains('lock') ||
                  n.contains('قفل') ||
                  ty.contains('قفل');
            }
            if (tLower == 'canon' ||
                tLower == 'cylinder' ||
                tLower == 'الأسطوانة' ||
                tLower == 'الاسطوانة' ||
                tLower == 'اسطوانة' ||
                tLower == 'أسطوانة') {
              return n.contains('canon') ||
                  ty.contains('canon') ||
                  n.contains('cylinder') ||
                  ty.contains('cylinder') ||
                  n.contains('اسطوانة') ||
                  ty.contains('اسطوانة') ||
                  n.contains('أسطوانة') ||
                  ty.contains('أسطوانة');
            }
            if (tLower == 'cache porte' ||
                tLower == 'gache porte' ||
                tLower == 'كاش بورت' ||
                tLower == 'كاش بورت (cache porte)') {
              return n.contains('cache') ||
                  ty.contains('cache') ||
                  n.contains('gache') ||
                  ty.contains('gache') ||
                  n.contains('كاش') ||
                  ty.contains('كاش');
            }
            if (tLower == 'roulette' ||
                tLower == 'roulettes' ||
                tLower == 'عجلات') {
              return n.contains('roulette') ||
                  ty.contains('roulette') ||
                  n.contains('رول') ||
                  ty.contains('رول') ||
                  n.contains('عجل') ||
                  ty.contains('عجل');
            }
            if (tLower == 'clamp' ||
                tLower.contains('clamp') ||
                tLower.contains('clam') ||
                tLower.contains('كلامب') ||
                tLower.contains('كلام') ||
                tLower.contains('كلان')) {
              final isClamp =
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
              final isKit =
                  n.contains('kit') ||
                  ty.contains('kit') ||
                  n.contains('كيت') ||
                  ty.contains('كيت');
              return isClamp && !isKit;
            }
            if (tLower == 'kit' || tLower.contains('كيت')) {
              final isKit =
                  n.contains('kit') ||
                  ty.contains('kit') ||
                  n.contains('كيت') ||
                  ty.contains('كيت');
              final isClamp =
                  n.contains('clamp') ||
                  n.contains('clam') ||
                  ty.contains('clamp') ||
                  ty.contains('clam') ||
                  n.contains('كلامب') ||
                  n.contains('كلام') ||
                  ty.contains('كلامب') ||
                  ty.contains('كلام') ||
                  n.contains('كلان') ||
                  ty.contains('كلان');
              return isKit && !isClamp;
            }

            final normN = normalizeArabic(n);
            final normTy = normalizeArabic(ty);
            final normTLower = normalizeArabic(tLower);
            bool match =
                normN.contains(normTLower) ||
                normTy.contains(normTLower) ||
                normTLower.contains(normN) ||
                normTLower.contains(normTy);

            // Defensive exclusion for generic matches
            if (match) {
              final searchHasKit =
                  normTLower.contains('kit') || normTLower.contains('كيت');
              final searchHasClamp =
                  normTLower.contains('clamp') ||
                  normTLower.contains('clam') ||
                  normTLower.contains('كلامب') ||
                  normTLower.contains('كلام') ||
                  normTLower.contains('كلان');
              final itemHasKit =
                  normN.contains('kit') ||
                  normTy.contains('kit') ||
                  normN.contains('كيت') ||
                  normTy.contains('كيت');
              final itemHasClamp =
                  normN.contains('clamp') ||
                  normN.contains('clam') ||
                  normTy.contains('clamp') ||
                  normTy.contains('clam') ||
                  normN.contains('كلامب') ||
                  normN.contains('كلام') ||
                  normN.contains('كلان') ||
                  normTy.contains('كلامب') ||
                  normTy.contains('كلام') ||
                  normTy.contains('كلان');

              if (searchHasKit && itemHasClamp) return false;
              if (searchHasClamp && itemHasKit) return false;
            }

            // For Central accessories (like Verrou Central), enforce that the matched db item also contains 'central'
            if (match && tLower.contains('central')) {
              if (!n.contains('central') &&
                  !ty.contains('central') &&
                  !n.contains('سنترال') &&
                  !ty.contains('سنترال') &&
                  !n.contains('سونترال') &&
                  !ty.contains('سونترال')) {
                return false;
              }
            }

            // For Espagnolettes, enforce exact number match if a number exists in both
            if (match &&
                (tLower.contains('espagnolette') ||
                    tLower.contains('اسبانيوليت') ||
                    tLower.contains('إسبانيوليت') ||
                    tLower.contains('سبانيوليت'))) {
              final tMatch = RegExp(r'\d+').firstMatch(tLower);
              final nMatch =
                  RegExp(r'\d+').firstMatch(n) ?? RegExp(r'\d+').firstMatch(ty);
              if (tMatch != null && nMatch != null) {
                if (tMatch.group(0) != nMatch.group(0)) {
                  return false; // Numbers don't match!
                }
              }
            }

            return match;
          }).toList();
        }
      }
    } else if (widget.category == 'joint') {
      final myDb = await db.db;
      if (myDb != null) {
        // Apply the exact same scope rule used for accessories: a joint that
        // has one or more series is exclusive to them; a joint without a
        // series is global only for its material.
        if (widget.seriesId != null) {
          final isPvc = widget.materialType?.trim().toLowerCase() == 'pvc';
          const seriesConstraint =
              "series_id = ? OR (series_ids IS NOT NULL AND TRIM(series_ids) != '' AND ',' || REPLACE(series_ids, ' ', '') || ',' LIKE ?) OR ((series_id IS NULL OR series_id = 0) AND (series_ids IS NULL OR TRIM(series_ids) = ''))";
          final materialConstraint = isPvc
              ? "TRIM(LOWER(type)) = 'pvc' OR TRIM(LOWER(type)) = 'both'"
              : "TRIM(LOWER(type)) = 'aluminium' OR TRIM(LOWER(type)) = 'aluminum' OR TRIM(LOWER(type)) = 'both' OR type IS NULL OR TRIM(type) = '' OR TRIM(LOWER(type)) = 'global'";
          final allJoints = await myDb.query(
            'Joints',
            where: '($seriesConstraint) AND ($materialConstraint)',
            whereArgs: [widget.seriesId, '%,${widget.seriesId},%'],
          );
          final t = widget.profileType.toLowerCase();
          final roleKeys = catalogRuleKeysForJointSelectorType(t);
          var matchingTypeRows = <Map<String, dynamic>>[];
          if (roleKeys.isNotEmpty) {
            final rules = await db.getCatalogItemRules(
              itemTable: 'Joints',
              seriesId: widget.seriesId,
              roleKeys: roleKeys,
            );
            final ruleIds = rules
                .where((rule) => rule['show_in_dialog'] != 0)
                .map((rule) => (rule['item_id'] as num?)?.toInt())
                .whereType<int>()
                .toSet();
            if (ruleIds.isNotEmpty) {
              matchingTypeRows = allJoints
                  .where(
                    (joint) => ruleIds.contains((joint['id'] as num?)?.toInt()),
                  )
                  .map((joint) => Map<String, dynamic>.from(joint))
                  .toList();
            }
            if (matchingTypeRows.isEmpty) {
              matchingTypeRows = allJoints
                  .where(
                    (joint) =>
                        catalogItemMatchesSeriesOrGlobal(
                          joint,
                          widget.seriesId!,
                        ) &&
                        roleKeys.any(
                          (roleKey) =>
                              jointCatalogItemMatchesRole(joint, roleKey),
                        ),
                  )
                  .map((joint) => Map<String, dynamic>.from(joint))
                  .toList();
            }
          }
          final exactSeriesRows = matchingTypeRows
              .where((row) => catalogItemMatchesSeries(row, widget.seriesId!))
              .toList();
          data = exactSeriesRows.isNotEmpty
              ? exactSeriesRows
              : matchingTypeRows;
        }
      }
    } else if (widget.category == 'shutter') {
      final myDb = await db.db;
      if (myDb != null) {
        final t = widget.profileType.toLowerCase();

        // 1. Get the allowed box sizes from ShutterBoxLimits if available
        List<double> allowedBoxSizes = [];
        if (widget.windowHeight != null &&
            widget.bladeId != null &&
            (t == 'صندوق' ||
                t == 'كيت' ||
                t.contains('caisson') ||
                t.contains('kit'))) {
          try {
            final List<Map<String, dynamic>> limits = await myDb.query(
              'ShutterBoxLimits',
              where: 'blade_id = ?',
              whereArgs: [widget.bladeId],
            );
            if (limits.isNotEmpty) {
              for (var limit in limits) {
                final boxSize = (limit['box_size'] as num).toDouble();
                final maxHeight = (limit['max_height'] as num).toDouble();
                if (widget.windowHeight! <= maxHeight) {
                  allowedBoxSizes.add(boxSize);
                }
              }
              // If no box size is large enough, the largest box is the only one allowed
              if (allowedBoxSizes.isEmpty) {
                final sortedLimits = List<Map<String, dynamic>>.from(limits)
                  ..sort(
                    (a, b) =>
                        (a['box_size'] as num).compareTo(b['box_size'] as num),
                  );
                allowedBoxSizes.add(
                  (sortedLimits.last['box_size'] as num).toDouble(),
                );
              }
            }
          } catch (e) {
            print('Error loading shutter box limits in profile selector: $e');
          }
        }

        if (t.contains('كيت') || t.contains('kit')) {
          final allKits = await myDb.query(
            'KitBundles',
            where: 'is_active = 1 OR is_active IS NULL',
          );
          data = allKits
              .map(
                (e) => {
                  'id': e['id'],
                  'name': e['name'],
                  'description': e['description'],
                  'price': 0.0,
                  'price_dzd': 0.0,
                  'component_type': 'كيت',
                  'measurement': extractSizeDigits(e['name'].toString()),
                  'catalog_source': 'KitBundles',
                },
              )
              .toList();

          if (widget.kitDescriptionCode != null &&
              widget.kitDescriptionCode!.trim().isNotEmpty) {
            data = compatibleKitBundles(
              kits: data,
              descriptionCode: widget.kitDescriptionCode!,
              minimumSizeMm: widget.targetSize,
            );
          }

          // Filter kits list by material type and series name
          final activeSeriesNameLower = activeSeriesName.toLowerCase();
          final mat = (widget.materialType ?? '').toLowerCase().trim();

          data = data.where((e) {
            final n = e['name'].toString().toLowerCase();

            // 1. Material Exclusions
            if (mat == 'pvc') {
              if (n.contains('aluminium') ||
                  n.contains('aluminum') ||
                  n.contains('alu') ||
                  n.contains('ألمنيوم') ||
                  n.contains('tpr')) {
                return false;
              }
            } else {
              // Aluminium
              if (n.contains('pvc')) {
                return false;
              }
            }

            // 2. Series Name Exclusions
            if (activeSeriesNameLower.isNotEmpty) {
              if (activeSeriesNameLower.contains('67000') ||
                  activeSeriesNameLower.contains('67')) {
                if (n.contains('76000') ||
                    n.contains('76') ||
                    n.contains('60000') ||
                    n.contains('60') ||
                    n.contains('52000') ||
                    n.contains('52') ||
                    n.contains('45000') ||
                    n.contains('45')) {
                  return false;
                }
              } else if (activeSeriesNameLower.contains('76000') ||
                  activeSeriesNameLower.contains('76')) {
                if (n.contains('67000') ||
                    n.contains('67') ||
                    n.contains('60000') ||
                    n.contains('60') ||
                    n.contains('52000') ||
                    n.contains('52') ||
                    n.contains('45000') ||
                    n.contains('45')) {
                  return false;
                }
              } else if (activeSeriesNameLower.contains('60000') ||
                  activeSeriesNameLower.contains('60')) {
                if (n.contains('67000') ||
                    n.contains('67') ||
                    n.contains('76000') ||
                    n.contains('76') ||
                    n.contains('52000') ||
                    n.contains('52') ||
                    n.contains('45000') ||
                    n.contains('45')) {
                  return false;
                }
              }
            }
            return true;
          }).toList();

          if (widget.windowHeight != null &&
              (widget.kitDescriptionCode == null ||
                  widget.kitDescriptionCode!.trim().isEmpty)) {
            data = data.where((a) {
              final sizeDigits = getComponentSize(a);
              if (sizeDigits != null) {
                double compSize = double.tryParse(sizeDigits) ?? 0.0;
                if (compSize == 15.5) compSize = 155.0;
                if (compSize == 18.5) compSize = 185.0;
                if (compSize == 20.5) compSize = 205.0;
                if (compSize == 15.0) compSize = 150.0;
                if (compSize == 18.0) compSize = 180.0;
                if (compSize == 20.0) compSize = 200.0;
                if (compSize < 100.0) {
                  compSize = compSize * 10.0;
                }

                if (allowedBoxSizes.isNotEmpty) {
                  bool isAllowed = false;
                  for (var allowed in allowedBoxSizes) {
                    if ((compSize - allowed).abs() < 5.0) {
                      isAllowed = true;
                      break;
                    }
                  }
                  if (!isAllowed) return false;
                } else {
                  double minAllowedSize = 155.0;
                  if (widget.windowHeight! > 1600 &&
                      widget.windowHeight! <= 2400) {
                    minAllowedSize = 185.0;
                  } else if (widget.windowHeight! > 2400) {
                    minAllowedSize = 205.0;
                  }
                  if (compSize < minAllowedSize) {
                    return false;
                  }
                }
              }
              return true;
            }).toList();
          }
        } else {
          String shutWhere = 'is_active = 1 OR is_active IS NULL';
          List<dynamic> shutArgs = [];
          if (widget.seriesId != null) {
            shutWhere +=
                ' AND ('
                'series_id = ? '
                'OR (series_ids IS NOT NULL AND series_ids != \'\' AND \',\' || series_ids || \',\' LIKE ?) '
                'OR ((series_id IS NULL OR series_id = 0) AND (series_ids IS NULL OR series_ids = \'\'))'
                ')';
            shutArgs.add(widget.seriesId);
            shutArgs.add('%,' + widget.seriesId.toString() + ',%');
          }
          final allShut = await myDb.query(
            'ShutterComponents',
            where: shutWhere,
            whereArgs: shutArgs,
          );

          final isBladeSelector = t == 'شريحة' || t == 'lame' || t == 'blade';
          final isTrackSelector =
              t.contains('سكك') ||
              t.contains('سكة') ||
              t.contains('coulisse') ||
              t.contains('track');
          final isBladeEndCapSelector =
              t.contains('أغطية الشفرات') ||
              t.contains('bouchon lame') ||
              t.contains('bouchons lames');

          List<String> keywords = [t];
          if (t.contains('صندوق') || t.contains('caisson'))
            keywords.addAll(['box', 'صندوق', 'caisson']);
          else if (t.contains('شريحة نهائية') || t.contains('lame finale'))
            keywords.addAll(['final_blade', 'lame final', 'نهائي']);
          else if (t.contains('شريحة') || t.contains('lame'))
            keywords.addAll(['blade', 'شريح', 'lame']);
          else if (t.contains('سكك') || t.contains('coulisse'))
            keywords.addAll(['track', 'سك', 'coulisse']);
          else if (t.contains('محور') || t.contains('axe'))
            keywords.addAll(['laxe', 'axe', 'محور']);
          else if (t.contains('أطاش') || t.contains('attache'))
            keywords.addAll(['attache', 'أطاش']);
          else if (t.contains('سيبور موتور') ||
              t.contains('support_moteur') ||
              t.contains('support moteur'))
            keywords.addAll(['support_moteur', 'سيبور موتور']);
          else if (t.contains('الامبو') || t.contains('embout'))
            keywords.addAll(['embout', 'امبو']);
          else if (t.contains('سيبور رولمو') ||
              t.contains('support_roulement') ||
              t.contains('support roulement'))
            keywords.addAll(['support_roulement', 'سيبور رولمو']);
          else if (t.contains('طانديم') || t.contains('tandem'))
            keywords.addAll(['tandem', 'طانديم']);
          else if (t.contains('أغطية الشفرات') ||
              t.contains('bouchon lame') ||
              t.contains('bouchons lames'))
            keywords.addAll(['bouchon_lame', 'أغطية الشفرات', 'غطاء']);

          var initialFiltered = allShut.where((a) {
            final n = a['name'].toString().toLowerCase();
            final ty = (a['component_type'] ?? '').toString().toLowerCase();

            if (isBladeSelector && ty != 'blade' && ty != 'lame') {
              return false;
            }
            if (isTrackSelector &&
                !const {
                  'track',
                  'coulisse',
                  'coulisses',
                  'glissiere',
                }.contains(ty.trim())) {
              return false;
            }
            if (isBladeEndCapSelector) {
              final linkedBlade = (a['shutter_subtype'] ?? '')
                  .toString()
                  .trim()
                  .toLowerCase();
              final selectedBlade = (widget.selectedBladeName ?? '')
                  .trim()
                  .toLowerCase();
              if (ty.trim() != 'bouchon_lame' ||
                  selectedBlade.isEmpty ||
                  linkedBlade != selectedBlade) {
                return false;
              }
            }

            if (t.contains('نهائية') || t.contains('finale')) {
              if (!n.contains('final') &&
                  !n.contains('finale') &&
                  !n.contains('نهائي') &&
                  !ty.contains('final') &&
                  !ty.contains('finale') &&
                  !ty.contains('نهائي')) {
                return false;
              }
            }
            if (t == 'شريحة' || t == 'lame') {
              if (n.contains('final') ||
                  n.contains('finale') ||
                  n.contains('نهائي') ||
                  ty.contains('final') ||
                  ty.contains('finale') ||
                  ty.contains('نهائي')) {
                return false;
              }
            }

            // فلترة الأحجام بناءً على ارتفاع النافذة لمنع الاختيارات الخاطئة
            if ((t == 'صندوق' ||
                    t == 'كيت' ||
                    t.contains('caisson') ||
                    t.contains('kit')) &&
                widget.windowHeight != null) {
              final sizeDigits = getComponentSize(a);
              if (sizeDigits != null) {
                double compSize = double.tryParse(sizeDigits) ?? 0.0;
                if (compSize == 15.5) compSize = 155.0;
                if (compSize == 18.5) compSize = 185.0;
                if (compSize == 20.5) compSize = 205.0;
                if (compSize == 15.0) compSize = 150.0;
                if (compSize == 18.0) compSize = 180.0;
                if (compSize == 20.0) compSize = 200.0;
                if (compSize < 100.0) {
                  compSize = compSize * 10.0;
                }

                if (allowedBoxSizes.isNotEmpty) {
                  bool isAllowed = false;
                  for (var allowed in allowedBoxSizes) {
                    if ((compSize - allowed).abs() < 5.0) {
                      isAllowed = true;
                      break;
                    }
                  }
                  if (!isAllowed) return false;
                } else {
                  double minAllowedSize = 155.0;
                  if (widget.windowHeight! > 1600 &&
                      widget.windowHeight! <= 2400) {
                    minAllowedSize = 185.0;
                  } else if (widget.windowHeight! > 2400) {
                    minAllowedSize = 205.0;
                  }
                  if (compSize < minAllowedSize) {
                    return false; // استبعاد الحجم غير المناسب
                  }
                }
              }
            }

            for (var kw in keywords) {
              if (n.contains(kw) || ty.contains(kw)) return true;
            }
            return false;
          }).toList();

          if (isTrackSelector && widget.bladeId != null) {
            final bladeRows = await myDb.query(
              'ShutterComponents',
              columns: const ['track_measurement', 'measurement', 'name'],
              where: 'id = ?',
              whereArgs: [widget.bladeId],
              limit: 1,
            );
            if (bladeRows.isNotEmpty) {
              final requiredTrackMeasurement = componentMeasurementKey(
                bladeRows.first,
                preferTrackMeasurement: true,
              );
              if (requiredTrackMeasurement != null) {
                initialFiltered = initialFiltered
                    .where(
                      (track) =>
                          componentMeasurementKey(track) ==
                          requiredTrackMeasurement,
                    )
                    .toList();
              }
            }
          }

          // If the manager configured shutter components for this series, use
          // that definition before falling back to global/name-based matching.
          if (widget.seriesId != null) {
            String? role;
            if (t.contains('caisson') ||
                t.contains('box') ||
                t.contains('صندوق')) {
              role = 'box';
            } else if (t.contains('lame') ||
                t.contains('blade') ||
                t.contains('شريحة')) {
              role = 'blade';
            } else if (t.contains('coulisse') ||
                t.contains('track') ||
                t.contains('سكة')) {
              role = 'rail';
            } else if (t.contains('moteur') ||
                t.contains('motor') ||
                t.contains('محرك')) {
              role = 'motor';
            } else if (t.contains('manivelle') ||
                t.contains('crank') ||
                t.contains('مانيفيل')) {
              role = 'crank';
            } else if (t.contains('axe') ||
                t.contains('axis') ||
                t.contains('محور')) {
              role = 'axis';
            }
            if (role != null) {
              final configuredRules = await db.getSeriesShutterRules(
                widget.seriesId!,
              );
              final allowedIds = configuredRules
                  .where((rule) => rule['component_role'] == role)
                  .map((rule) => (rule['component_id'] as num?)?.toInt())
                  .whereType<int>()
                  .toSet();
              if (allowedIds.isNotEmpty) {
                initialFiltered = initialFiltered
                    .where(
                      (component) => allowedIds.contains(
                        (component['id'] as num?)?.toInt(),
                      ),
                    )
                    .toList();
              }
            }
          }

          // The axis is not a generic shutter component.  Its blade relation
          // has priority: an X3D blade may only use X3D axes, while a normal
          // blade must never receive an X3D axis.  Only after that relation is
          // respected do we apply the motor-diameter constraint.
          final isAxisSelector =
              t.contains('axe') ||
              t.contains('axis') ||
              t.contains('laxe') ||
              t.contains('محور');
          if (isAxisSelector) {
            final selectedBlade = (widget.selectedBladeName ?? '')
                .toLowerCase();
            final selectedBladeIsX3d =
                widget.selectedBladeIsX3d ?? selectedBlade.contains('x3d');

            initialFiltered = initialFiltered.where((component) {
              final axisIsX3d = _isX3dShutterComponent(component);
              return selectedBladeIsX3d ? axisIsX3d : !axisIsX3d;
            }).toList();

            // New catalogue entries store the exact blade name in
            // shutter_subtype.  Prefer that explicit relationship whenever it
            // exists, while retaining the X3D/normal fallback for older data
            // that only stored a generic subtype.
            if (selectedBlade.isNotEmpty) {
              final explicitlyLinked = initialFiltered.where((component) {
                return (component['shutter_subtype'] ?? '')
                        .toString()
                        .trim()
                        .toLowerCase() ==
                    selectedBlade;
              }).toList();
              if (explicitlyLinked.isNotEmpty) {
                initialFiltered = explicitlyLinked;
              }
            }

            final requiredMotorDiameter = widget.motorDiameter;
            if (requiredMotorDiameter != null && requiredMotorDiameter > 0) {
              initialFiltered = initialFiltered.where((component) {
                final axisDiameter = shutterComponentDiameter(component);
                // With a motor selected, an axis with no known diameter is not
                // safe to propose: it cannot be proven compatible.
                return axisDiameter != null &&
                    axisDiameter >= requiredMotorDiameter;
              }).toList();
            }

            // When several axes fit, offer the smallest compatible diameter
            // first.  This keeps the default choice deterministic as well.
            initialFiltered.sort((a, b) {
              final aDiameter = shutterComponentDiameter(a) ?? double.infinity;
              final bDiameter = shutterComponentDiameter(b) ?? double.infinity;
              return aDiameter.compareTo(bDiameter);
            });
          }

          // Attaches, motors and their supports are shutter components tied to
          // the selected blade family.  A normal blade must never offer X3D
          // parts, and an X3D blade must never fall back to the normal family.
          final isBladeBoundSelector =
              t.contains('attache') ||
              t.contains('أطاش') ||
              t.contains('moteur') ||
              t.contains('motor') ||
              t.contains('محرك') ||
              t.contains('support moteur') ||
              t.contains('support_moteur') ||
              t.contains('سيبور موتور') ||
              t.contains('support roulement') ||
              t.contains('support_roulement') ||
              t.contains('سيبور رولمو') ||
              t.contains('embout') ||
              t.contains('الامبو');
          if (isBladeBoundSelector) {
            final selectedBlade = (widget.selectedBladeName ?? '')
                .trim()
                .toLowerCase();
            final selectedBladeIsX3d =
                widget.selectedBladeIsX3d ?? selectedBlade.contains('x3d');
            initialFiltered = initialFiltered.where((component) {
              return _isX3dShutterComponent(component) == selectedBladeIsX3d;
            }).toList();

            // An explicit blade relation is stronger than a generic normal/X3D
            // label whenever the catalogue contains one.
            final explicitlyLinked = initialFiltered.where((component) {
              return selectedBlade.isNotEmpty &&
                  (component['shutter_subtype'] ?? '')
                          .toString()
                          .trim()
                          .toLowerCase() ==
                      selectedBlade;
            }).toList();
            if (explicitlyLinked.isNotEmpty) {
              initialFiltered = explicitlyLinked;
            }
          }

          if (widget.targetSize != null) {
            final targetDigits = widget.targetSize!.toStringAsFixed(0);
            final matchedSizeData = initialFiltered.where((a) {
              final sizeDigits = extractSizeDigits(a['name'].toString());
              return sizeDigits == targetDigits;
            }).toList();
            if (matchedSizeData.isNotEmpty) {
              data = matchedSizeData;
            } else {
              data = initialFiltered;
            }
          } else {
            data = initialFiltered;
          }

          if (t.contains('صندوق') || t.contains('caisson')) {
            data = List<Map<String, dynamic>>.from(data);
            data.insert(0, {
              'id': -999,
              'name': 'صندوق نفق (Caisson Tunnel)',
              'price': 0.0,
              'price_dzd': 0.0,
              'component_type': 'صندوق',
              'measurement': 'tunnel',
            });
          }
        } // end else for ShutterComponents
      } // end if (myDb != null)
    } else {
      final myDb = await db.db;
      if (myDb != null) {
        String whereClause = '(is_active = 1 OR is_active IS NULL)';
        List<dynamic> whereArgs = [];
        if (widget.seriesId != null) {
          whereClause = 'series_id = ? AND ' + whereClause;
          whereArgs = [widget.seriesId];
        }
        final allSections = await myDb.query(
          'Sections',
          where: whereClause,
          whereArgs: whereArgs,
        );

        final t = widget.profileType.toLowerCase().trim();
        data = allSections.where((s) {
          if (!profileSectionMatchesDrawingMode(
            section: s,
            profileType: widget.profileType,
            activeSeriesType: activeSeriesType,
            drawingMode: widget.accessoryDrawingMode,
          )) {
            return false;
          }
          final ty = s['type'].toString().toLowerCase().trim();
          final name = s['name'].toString().toLowerCase().trim();

          if (t == 'frame' || t == 'cadre' || t == 'إطار') {
            return ty.contains('frame') ||
                ty.contains('cadre') ||
                ty.contains('إطار') ||
                ty.contains('فريم');
          } else if (t == 'sash' || t == 'ouvrant' || t == 'ضلفة') {
            return ty.contains('sash') ||
                ty.contains('ouvrant') ||
                ty.contains('ضلفة') ||
                ty.contains('ساش');
          } else if (t.contains('lateral') || t.contains('جانبي')) {
            final lowerName = name.toLowerCase();
            final lowerType = ty.toLowerCase();
            final code = (s['code'] ?? '').toString().toLowerCase();
            return (code.contains('67108') ||
                    code.contains('67104') ||
                    code.endsWith('108') ||
                    code.endsWith('104') ||
                    lowerType.contains('lateral') ||
                    lowerName.contains('latéral') ||
                    lowerName.contains('lateral') ||
                    lowerName.contains('جانبي')) &&
                !lowerName.contains('central') &&
                !lowerName.contains('وسطي') &&
                !lowerName.contains('chicane') &&
                !code.contains('105') &&
                !code.contains('107');
          } else if (t.contains('central') ||
              t.contains('وسطي') ||
              t.contains('chicane')) {
            final lowerName = name.toLowerCase();
            final lowerType = ty.toLowerCase();
            final code = (s['code'] ?? '').toString().toLowerCase();
            return (code.contains('67107') ||
                    code.contains('67105') ||
                    code.endsWith('107') ||
                    code.endsWith('105') ||
                    lowerType.contains('central') ||
                    lowerName.contains('central') ||
                    lowerName.contains('وسطي') ||
                    lowerName.contains('chicane')) &&
                !lowerName.contains('latéral') &&
                !lowerName.contains('lateral') &&
                !lowerName.contains('جانبي') &&
                !code.contains('104') &&
                !code.contains('108');
          } else if (t.contains('sash_traverse') ||
              t.contains('sash traverse')) {
            return ty.contains('traverse') ||
                name.contains('traverse') ||
                ty.contains('عرضي') ||
                name.contains('عرضي');
          } else if (t.contains('couvre') ||
              t.contains('side cover') ||
              t.contains('غطاء جانبي') ||
              t.contains('كافر')) {
            final lowerName = name.toLowerCase();
            final lowerType = ty.toLowerCase();
            final code = (s['code'] ?? '').toString().toLowerCase();
            return lowerType.contains('couvre') ||
                lowerName.contains('couvre') ||
                lowerName.contains('غطاء') ||
                lowerType.contains('side_cover') ||
                code.contains('couvre');
          } else if (t == 'renfort') {
            return ty.contains('renfort') ||
                ty.contains('رنفور') ||
                ty.contains('حديد');
          } else if (t == 'batmo') {
            return (ty.contains('batmo') || ty.contains('باتمو')) &&
                !ty.contains('bouchon') &&
                !ty.contains('بوشون');
          } else if (t == 'parclose') {
            final isReducer =
                ty.contains('reduct') ||
                name.contains('reduct') ||
                ty.contains('réduct') ||
                name.contains('réduct') ||
                ty.contains('ريديكتور') ||
                name.contains('ريديكتور') ||
                ty.contains('مخفض') ||
                name.contains('مخفض');
            return !isReducer &&
                (ty.contains('parclose') ||
                    name.contains('parclose') ||
                    ty.contains('باركلوز') ||
                    name.contains('باكيت') ||
                    name.contains('بيركلوز'));
          } else if (t == 'mullion' || t == 'traverse') {
            return ty.contains('mullion') ||
                ty.contains('traverse') ||
                ty.contains('موليان') ||
                ty.contains('ترافيرس');
          } else if (t == 'bouchon batmo' ||
              t == 'bouchon batment' ||
              t == 'bouchon') {
            return ty.contains('bouchon') ||
                ty.contains('بوشون') ||
                ty.contains('bochon');
          }
          // البحث بالكود مباشرة (مثلاً 67114 للريديكتور)
          final code = (s['code'] ?? '').toString().toLowerCase().trim();
          if (RegExp(r'^\d+$').hasMatch(t)) {
            return code.contains(t) &&
                !ty.contains('rail') &&
                !name.contains('rail') &&
                !name.contains('سكة');
          }
          if (t.contains('reduct') ||
              t.contains('67114') ||
              t.contains('ريديك') ||
              t.contains('مخفض')) {
            return (ty.contains('reduct') ||
                    name.contains('reduct') ||
                    name.contains('مخفض') ||
                    name.contains('ريديكتور') ||
                    code.contains('67114')) &&
                !ty.contains('rail') &&
                !ty.contains('cadre') &&
                !ty.contains('frame') &&
                !name.contains('rail') &&
                !name.contains('سكة') &&
                !name.contains('cadre') &&
                !name.contains('إطار');
          }
          if (t == 'rail' ||
              t.contains('rail') ||
              t.contains('الري') ||
              t.contains('سكة')) {
            return (ty == 'rail' ||
                    ty.contains('rail') ||
                    name.contains('rail') ||
                    name.contains('سكة')) &&
                !ty.contains('frame') &&
                !ty.contains('cadre') &&
                !name.contains('cadre') &&
                !name.contains('إطار');
          }
          return ty.contains(t) ||
              t.contains(ty) ||
              name.contains(t) ||
              t.contains(name);
        }).toList();

        // Prefer the explicit role mapping created by the administrator in
        // "Définition intelligente de la série".  Name and code matching
        // above remains a fallback for older, not-yet-configured series.
        final roleKeys = seriesRoleKeysForProfileSelectorType(t);
        if (widget.seriesId != null && roleKeys.isNotEmpty) {
          final roleSelector =
              t.contains('central') ||
              t.contains('chicane') ||
              t.contains('lateral') ||
              t.contains('جانبي') ||
              t.contains('sash_traverse') ||
              t.contains('sash traverse');
          final configured =
              (await db.getDesignSectionsForRoles(
                widget.seriesId!,
                roleKeys,
              )).where((section) {
                if (roleSelector) return true;
                return profileSectionMatchesDrawingMode(
                  section: section,
                  profileType: widget.profileType,
                  activeSeriesType: activeSeriesType,
                  drawingMode: widget.accessoryDrawingMode,
                );
              }).toList();
          data = configured;
        }
        final isFrameSelector = t == 'frame' || t == 'cadre' || t == 'إطار';
        final material = (widget.materialType ?? '').toLowerCase().trim();
        final isAluminium =
            material.isEmpty ||
            material == 'aluminium' ||
            material == 'aluminum' ||
            material == 'alu';
        if (widget.hasShutter && isAluminium && isFrameSelector) {
          data = data
              .where((item) => !profileHasIntegratedSideCover(item))
              .toList();
        }
      } else {
        data = [];
      }
    }

    setState(() {
      profiles = data;
      isLoading = false;
    });
  }

  String searchQuery = '';

  @override
  Widget build(BuildContext context) {
    final filtered = profiles.where((item) {
      if (searchQuery.isEmpty) return true;
      final q = searchQuery.toLowerCase().trim();
      final name = (item['name'] ?? '').toString().toLowerCase();
      final code = (item['code'] ?? '').toString().toLowerCase();
      final type = (item['type'] ?? '').toString().toLowerCase();
      return name.contains(q) || code.contains(q) || type.contains(q);
    }).toList();

    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      title: Text('اختر ${widget.profileType}'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 380),
        child: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: TextField(
                  style: TextStyle(
                    color: Theme.of(context).brightness == Brightness.dark
                        ? Colors.white
                        : Colors.black87,
                  ),
                  decoration: InputDecoration(
                    hintText: 'بحث...',
                    hintStyle: TextStyle(
                      color: Theme.of(context).brightness == Brightness.dark
                          ? Colors.white54
                          : Colors.black38,
                    ),
                    prefixIcon: Icon(
                      Icons.search,
                      color: Theme.of(context).brightness == Brightness.dark
                          ? Colors.white70
                          : Colors.grey,
                    ),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(
                        color: Theme.of(context).brightness == Brightness.dark
                            ? Colors.white30
                            : Colors.grey.shade300,
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(
                        color: Theme.of(context).brightness == Brightness.dark
                            ? Colors.white24
                            : Colors.grey.shade300,
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(
                        color: Theme.of(context).brightness == Brightness.dark
                            ? Colors.blue.shade300
                            : Colors.blue,
                        width: 1.5,
                      ),
                    ),
                  ),
                  onChanged: (val) {
                    setState(() {
                      searchQuery = val;
                    });
                  },
                ),
              ),
              Expanded(
                child: isLoading
                    ? const SizedBox(
                        height: 100,
                        child: Center(child: CircularProgressIndicator()),
                      )
                    : filtered.isEmpty
                    ? const SizedBox(
                        height: 100,
                        child: Center(child: Text('لا توجد نتائج مطابقة')),
                      )
                    : ListView.builder(
                        shrinkWrap: true,
                        itemCount: filtered.length,
                        itemBuilder: (context, index) {
                          final item = filtered[index];

                          // معالجة القيم الفارغة في الكود والاسم
                          final codeStr =
                              (item['code'] != null &&
                                  item['code'].toString().isNotEmpty)
                              ? '${item['code']} - '
                              : '';
                          final nameStr = (item['name'] ?? 'بدون اسم')
                              .toString()
                              .replaceAll(RegExp(r'\s*\(\s*جودة[^)]*\)'), '')
                              .trim();

                          return ListTile(
                            leading: SectionImageWidget(
                              code: item['code']?.toString(),
                              imagePath: item['image_path']?.toString(),
                              size: 40.0,
                            ),
                            title: Text('$codeStr$nameStr'),
                            onTap: () => Navigator.pop(context, item),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('إلغاء'),
        ),
      ],
    );
  }
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

String? componentMeasurementKey(
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

String normalizeArabic(String str) {
  return str
      .replaceAll('إ', 'ا')
      .replaceAll('أ', 'ا')
      .replaceAll('آ', 'ا')
      .replaceAll('ة', 'ه')
      .replaceAll('ى', 'ي');
}
