import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../widgets/section_image.dart';
import '../../sql_database.dart';
import '../../settings/app_settings.dart';
import '../../settings/localization.dart';
import 'model.dart';

/// The component row that opened the selector belongs either to an opening
/// sash or to a sliding sash.  It must not be inferred from a commercial
/// series name: a PVC catalogue can contain both kinds of hardware.
enum AccessoryDrawingMode { opening, sliding }

String _accessorySearchText(Map<String, dynamic> accessory) =>
    '${accessory['name'] ?? ''} ${accessory['type'] ?? ''}'.toLowerCase();

bool _containsAny(String value, Iterable<String> terms) =>
    terms.any((term) => value.contains(term));

bool _isShutterScrewSelectorType(String profileType) {
  final lower = profileType.toLowerCase();
  return lower == 'is_kit_screw' ||
      lower == 'kit_screw' ||
      lower == 'is_caisson_screw' ||
      lower == 'box_screw' ||
      lower == 'is_moteur_screw' ||
      lower == 'motor_screw' ||
      lower == 'is_manivelle_screw' ||
      lower == 'manivelle_screw' ||
      (profileType.contains('براغي') &&
          (profileType.contains('الكيت') ||
              profileType.contains('الصندوق') ||
              profileType.contains('المحرك') ||
              profileType.contains('المانيفال')));
}

int? _catalogInt(Object? value) {
  if (value is num) return value.toInt();
  return int.tryParse('${value ?? ''}'.trim());
}

double _catalogDouble(Object? value) {
  if (value is num) return value.toDouble();
  return double.tryParse('${value ?? ''}'.replaceAll(',', '.').trim()) ?? 0.0;
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

bool _roleIgnoresGlassRule(String roleKey) {
  switch (roleKey.trim().toLowerCase()) {
    case 'batmo':
    case 'plant':
    case 'porte_joint':
    case 'joint_bronze':
    case 'bouchon_batmo':
    case 'batmo_screw':
    case 'bouchon_batmo_screw':
      return true;
  }
  return false;
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

List<String> catalogRuleKeysForAccessorySelectorType(String selectorType) {
  final tLower = normalizeArabic(selectorType.toLowerCase().trim());
  const directRoles = {
    'clam',
    'clamp',
    'frame_clamp',
    'sash_clamp',
    'frame_clamp_support',
    'sash_clamp_support',
    'kit_screw',
    'box_screw',
    'motor_screw',
    'bouchon_batmo',
    'batmo_screw',
    'bouchon_batmo_screw',
    'renfort_screw',
    'manivelle_screw',
    'assembly_screw',
    'installation_screw',
    'accessory_screw',
    'kit',
    'gache_simple',
    'gache_double',
    'gache_door',
    'lock_clef',
    'lock_condamnation',
    'sliding_kit',
    'sliding_kit_40000',
    'sliding_kit_67000',
    'sliding_clamp',
    'sliding_lock',
    'verrou',
    'cremone',
    'tringle',
    'espagnolette',
    'canon',
    'door_handle_key',
    'door_handle_condamnation',
    'handle',
    'hinge',
    'tasso',
    'ekar',
    'alignment_square',
    'roulette',
    'entrematique',
  };
  if (tLower == 'clam' || tLower == 'clamp' || tLower == 'sliding_clamp') {
    return const ['clam', 'clamp', 'sliding_clamp'];
  }
  if (directRoles.contains(tLower)) return [tLower];
  if (tLower == 'is_kit_screw') return const ['kit_screw'];
  if (tLower == 'is_caisson_screw') return const ['box_screw'];
  if (tLower == 'is_moteur_screw') return const ['motor_screw'];
  if (tLower == 'is_batmo_screw') return const ['batmo_screw'];
  if (tLower == 'is_bouchon_batmo_screw') {
    return const ['bouchon_batmo_screw'];
  }
  final isBouchonBatmo =
      (tLower.contains('bouchon') ||
          tLower.contains('bochon') ||
          tLower.contains('بوشون')) &&
      (tLower.contains('batmo') || tLower.contains('باتمو'));
  if (isBouchonBatmo) return const ['bouchon_batmo'];
  if (tLower == 'is_renfort_screw') return const ['renfort_screw'];
  if (tLower == 'is_manivelle_screw') return const ['manivelle_screw'];
  if (tLower == 'is_assembly_screw') return const ['assembly_screw'];
  if (tLower == 'is_installation_screw') {
    return const ['installation_screw'];
  }
  if (tLower == 'is_accessory_screw') return const ['accessory_screw'];
  if (tLower == 'sliding_kit' ||
      ((tLower.contains('kit') || tLower.contains('كيت')) &&
          (tLower.contains('sliding') ||
              tLower.contains('coulissant') ||
              tLower.contains('منزلق') ||
              tLower.contains('67000') ||
              tLower.contains('76000') ||
              tLower.contains('40000')))) {
    return const ['sliding_kit'];
  }
  if (tLower == 'kit' || tLower == 'كيت') return const ['kit'];
  if (tLower.contains('clamp') ||
      tLower.contains('clam') ||
      tLower.contains('كلام')) {
    return const ['clam', 'clamp', 'sliding_clamp'];
  }
  if (tLower.contains('gache couliss') ||
      tLower.contains('gâche couliss') ||
      tLower.contains('كاش كوليسون')) {
    return const ['sliding_lock'];
  }
  if (tLower == 'is_gache_simple') return const ['gache_simple'];
  if (tLower == 'is_gache_double') return const ['gache_double'];
  if (tLower == 'is_gache_porte') return const ['gache_door'];
  if (tLower == 'is_lock_clef') return const ['lock_clef'];
  if (tLower == 'is_lock_condamnation') return const ['lock_condamnation'];
  if (tLower == 'is_poign_clef') return const ['door_handle_key'];
  if (tLower == 'is_poign_condamnation') {
    return const ['door_handle_condamnation'];
  }
  if (tLower == 'is_canon') return const ['canon'];
  if (tLower == 'اسبانيوليت' ||
      tLower.contains('espagnolette') ||
      tLower.contains('سبانيول')) {
    return const ['espagnolette'];
  }
  if (tLower == 'فيرو' || tLower.contains('verrou')) {
    return const ['verrou'];
  }
  if (tLower == 'tringle' ||
      tLower.contains('tringle') ||
      tLower.contains('tangle') ||
      tLower.contains('triangle') ||
      tLower.contains('تراينغل') ||
      tLower.contains('تريانغل')) {
    return const ['tringle'];
  }
  if (tLower == 'cremone' ||
      tLower.contains('crémone') ||
      tLower.contains('كريمون')) {
    return const ['cremone'];
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
  if (tLower == 'tasso' || tLower.contains('الطاسو')) {
    return const ['tasso'];
  }
  if (tLower == 'ekar' ||
      tLower.contains('ekar') ||
      tLower.contains('ikar') ||
      tLower.contains('إيكار') ||
      tLower.contains('ايكار')) {
    return const ['ekar'];
  }
  if (tLower == 'alignment_square' ||
      tLower.contains('alignement') ||
      tLower.contains('alignment') ||
      tLower.contains('دالينمو') ||
      tLower.contains('دالينيمو')) {
    return const ['alignment_square'];
  }
  if (tLower == 'roulette' || tLower.contains('عجلات')) {
    return const ['roulette'];
  }
  if (tLower == 'entrematique' ||
      tLower.contains('أونتروماتيك') ||
      tLower.contains('انتراميتيك') ||
      tLower.contains('intra')) {
    return const ['entrematique'];
  }
  return const [];
}

bool catalogRuleAllowsGlobalFallback(String roleKey) {
  // A rule saved from the global Accessories tab applies to all compatible
  // series. A series-specific rule still has priority because
  // getCatalogItemRules suppresses the global row for that item/series.
  const globallyShareableRoles = {
    'kit_screw',
    'box_screw',
    'motor_screw',
    'batmo_screw',
    'bouchon_batmo',
    'bouchon_batmo_screw',
    'renfort_screw',
    'manivelle_screw',
    'assembly_screw',
    'installation_screw',
    'accessory_screw',
    'gache_simple',
    'gache_double',
    'gache_door',
    'lock_clef',
    'lock_condamnation',
    'sliding_lock',
    'verrou',
    'cremone',
    'tringle',
    'espagnolette',
    'canon',
    'door_handle_key',
    'door_handle_condamnation',
    'handle',
    'hinge',
    'tasso',
    'ekar',
    'alignment_square',
    'roulette',
    'entrematique',
    // Sliding hardware is no less reusable than opening hardware. Omitting
    // these roles made a rule activated from the catalogue-wide accessory
    // page disappear specifically on BS90 and other sliding series, even
    // though its material and drawing scope were compatible.
    'sliding_kit',
    'sliding_kit_40000',
    'sliding_kit_67000',
    // Assembly hardware is governed by its role and by the material/drawing
    // checks below.  It must not be tied to the first series where the
    // administrator happened to create the rule: a Clam configured in the
    // catalogue is valid for every compatible frame/sash that it targets.
    'clam',
    'clamp',
    'frame_clamp',
    'sash_clamp',
    'frame_clamp_support',
    'sash_clamp_support',
    'sliding_clamp',
    'other',
    // Gaskets are catalogue items shared by compatible aluminium series.
    // Their BOM formulas decide whether a material/system may use them;
    // keeping only brush here made every other global gasket rule disappear.
    'joint_vitrage',
    'joint_bourrage',
    'joint_frappe',
    'joint_central',
    'joint_brosse',
    'joint_bronze',
    'shutter_joint_brosse',
  };
  return globallyShareableRoles.contains(roleKey.trim().toLowerCase());
}

bool catalogRuleMatchesExactScope(Map<String, dynamic> rule, int? seriesId) {
  final rawSeriesId = rule['series_id'];
  final ruleSeriesId = rawSeriesId is num
      ? rawSeriesId.toInt()
      : int.tryParse('${rawSeriesId ?? ''}'.trim());
  if (seriesId == null) return ruleSeriesId == null;
  if (ruleSeriesId == seriesId) return true;
  // A global rule must not silently become a rule for every series.  Only the
  // explicitly shared roles (for example common shutter screws) are allowed
  // to fall back from the global catalogue to a series-specific query.
  return ruleSeriesId == null &&
      catalogRuleAllowsGlobalFallback(rule['role_key']?.toString() ?? '');
}

List<String> catalogRuleKeysForJointSelectorType(String selectorType) {
  final tLower = normalizeArabic(selectorType.toLowerCase().trim());
  final compactType = tLower.replaceAll(RegExp(r'[\s_-]+'), '');
  const directRoles = {
    'joint_vitrage',
    'joint_bourrage',
    'joint_frappe',
    'joint_central',
    'joint_brosse',
    'joint_bronze',
    'shutter_joint_brosse',
  };
  if (directRoles.contains(tLower)) return [tLower];
  if (compactType == 'n245') return const ['joint_central'];
  if (tLower.contains('shutter') ||
      tLower.contains('volet') ||
      tLower.contains('للستار')) {
    return const ['shutter_joint_brosse'];
  }
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
  if (tLower.contains('bronze') || tLower.contains('برونز')) {
    return const ['joint_bronze'];
  }
  if (tLower.contains('bross') ||
      tLower.contains('brosse') ||
      tLower.contains('بروس')) {
    return const ['joint_brosse'];
  }
  return const [];
}

List<String> seriesRoleKeysForProfileSelectorType(String selectorType) {
  final t = normalizeArabic(selectorType.toLowerCase().trim());
  if (t.contains("profil d'angle") ||
      t.contains('profile d\'angle') ||
      t.contains('profile_angle') ||
      t.contains('profil angle') ||
      t.contains('زاوية')) {
    return const ['profile_angle'];
  }
  if (t.contains('cache-caniveau') ||
      t.contains('cache caniveau') ||
      t.contains('cache_caniveau')) {
    return const ['cache_caniveau'];
  }
  if (t == 'caniveau' || t.contains('caniveau') || t.contains('كاني')) {
    return const ['caniveau'];
  }
  if (t.contains('cache dormant') || t.contains('cache_dormant')) {
    return const ['cache_dormant'];
  }
  if (t.contains('chch renfort') ||
      t.contains('cache renfort') ||
      t.contains('cache_renfort')) {
    return const ['cache_renfort'];
  }
  if (t.contains('montant central slim') ||
      t.contains('montant_central_slim') ||
      t.contains('central slim')) {
    return const ['montant_central_slim', 'sash_central'];
  }
  if (t.contains('complement haut') ||
      t.contains('complément haut') ||
      t.contains('complement_haut_base') ||
      t.contains('haut et bas')) {
    return const ['complement_haut_base'];
  }
  if (isBardagePanelSubtype(t)) {
    return const ['bardage'];
  }
  if (t == 'frame' || t == 'cadre' || t == 'إطار') {
    return const ['frame', 'frame_extension'];
  }
  if (t == 'sash' || t == 'ouvrant' || t == 'ضلفة') {
    return const ['sash', 'sash_extension'];
  }
  if (t == 'parclose' ||
      t.contains('parclose_simple') ||
      t.contains('parclose_double') ||
      t.contains('parclose')) {
    return const ['glazing_bead'];
  }
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
  if (t.contains('patte') || t == 'p' || t == 'profil p' || t == 'profile p') {
    return const ['triangle'];
  }
  if (t.contains('cache-rainure') ||
      t.contains('cache rainure') ||
      t.contains('cache_rainure')) {
    return const ['cache_rainure'];
  }
  if (t.contains('cache-rail') ||
      t.contains('cache rail') ||
      t.contains('cache_rail')) {
    return const ['cache_rail'];
  }
  if (t.contains('bavette')) return const ['bavette'];
  if (t == 'seuil' || t.contains('seuil')) return const ['seuil'];
  if (t == 'rail' || t.contains('rail') || t.contains('سكة')) {
    return const ['rail'];
  }
  if (t.contains('reduct') || t.contains('67114') || t.contains('ريديك')) {
    return const ['reducer'];
  }
  if (t == 'bouchon_batmo' ||
      t.contains('bouchon_batmo') ||
      t.contains('bouchon batmo') ||
      t.contains('bochon batmo') ||
      (t.contains('بوشون') && t.contains('باتمو'))) {
    return const ['bouchon_batmo'];
  }
  if (t == 'batmo') return const ['batmo'];
  if (t == 'plant' || t.contains('plinthe') || t.contains('بلانت')) {
    return const ['plant'];
  }
  if (t == 'porte_joint' ||
      t.contains('porte joint') ||
      t.contains('porte-joint') ||
      t.contains('حامل الجوان')) {
    return const ['porte_joint'];
  }
  if (t == 'triangle' ||
      t.contains('تراينغل') ||
      t.contains('تريانغل') ||
      t.contains('مثلث')) {
    return const ['triangle'];
  }
  if (t == 'renfort') return const ['renfort'];
  if (t == 'other_profile' ||
      t.contains('other profile') ||
      t.contains('autre profil') ||
      t.contains('مقطع خاص')) {
    return const ['other_profile'];
  }
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
    'tpr',
    'tpi',
    'hps',
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
      name.contains('sunset') ||
      name.contains('sontara') ||
      name.contains('suntara') ||
      type.contains('monobloc') ||
      type.contains('sunset') ||
      type.contains('sontara') ||
      type.contains('suntara');
}

bool _profileSupportsEnabledSideCover(Map<String, dynamic> item) {
  double readWidth(Object? raw) {
    if (raw is num) return raw.toDouble();
    return double.tryParse(raw?.toString() ?? '') ?? 0.0;
  }

  bool? readOptionalBool(Object? raw) {
    if (raw == null) return null;
    if (raw is bool) return raw;
    if (raw is num) return raw != 0;
    final normalized = raw.toString().trim().toLowerCase();
    if (normalized == '1' || normalized == 'true' || normalized == 'yes') {
      return true;
    }
    if (normalized == '0' || normalized == 'false' || normalized == 'no') {
      return false;
    }
    return null;
  }

  final isIntegrated =
      readOptionalBool(
        item['design_integrated_side_cover'] ?? item['integrated_side_cover'],
      ) ??
      profileHasIntegratedSideCover(item);
  if (isIntegrated) {
    // A label such as "monobloc" is not enough: the drawing needs an actual
    // cover width to render a compatible integrated frame.
    return readWidth(item['couvre_joint_width']) > 0;
  }

  final allowsStandalone = readOptionalBool(
    item['design_allows_side_cover'] ?? item['allows_side_cover'],
  );
  // Old catalogue rows have no capability flag and remain compatible by
  // default. An explicit false is the authoritative incompatibility rule.
  return allowsStandalone != false;
}

class CatalogCandidateQuery {
  const CatalogCandidateQuery({
    required this.category,
    required this.selectorType,
    this.roleKeys = const [],
    this.seriesId,
    this.materialType,
    this.hasShutter = false,
    this.isCaissonTunnel = false,
    this.hasSideCovers = false,
    this.multiFrameDrawing = false,
    this.drawingMode,
    this.requireDialog = true,
    this.requireQuantity = true,
    this.hasSimpleGlassForReducer,
    this.hasDoubleGlassForRules,
    this.targetThicknessMm,
    this.effectiveHeightMm,
    this.mainWarehouseStock = const {},
    this.stockColorId,
  });

  final String category;
  final String selectorType;
  final List<String> roleKeys;
  final int? seriesId;
  final String? materialType;
  final bool hasShutter;
  final bool isCaissonTunnel;
  final bool hasSideCovers;
  final bool multiFrameDrawing;
  final AccessoryDrawingMode? drawingMode;
  final bool requireDialog;
  final bool requireQuantity;
  final bool? hasSimpleGlassForReducer;
  final bool? hasDoubleGlassForRules;
  final double? targetThicknessMm;

  /// Snapshot of the main warehouse, supplied by the quantity table. It is
  /// intentionally optional so the dialog remains reusable elsewhere.
  final Map<String, double> mainWarehouseStock;
  final int? stockColorId;
  final double? effectiveHeightMm;
}

class CatalogCandidateResolver {
  CatalogCandidateResolver({SqlDatabase? database})
    : _db = database ?? SqlDatabase();

  final SqlDatabase _db;

  Future<List<Map<String, dynamic>>> resolve(CatalogCandidateQuery query) {
    switch (query.category) {
      case 'profile':
        return _resolveProfiles(query);
      case 'accessory':
      case 'other':
        return _resolveCatalogRules(query, 'Accessories');
      case 'joint':
        return _resolveCatalogRules(query, 'Joints');
    }
    return Future.value(const <Map<String, dynamic>>[]);
  }

  Future<List<Map<String, dynamic>>> _resolveProfiles(
    CatalogCandidateQuery query,
  ) async {
    // An explicit profile role is authoritative: product names can contain
    // both "central" and "lateral" and must not broaden the requested role.
    final roleKeys =
        (query.roleKeys.isNotEmpty
                ? query.roleKeys
                : seriesRoleKeysForProfileSelectorType(query.selectorType))
            .toList();
    if (roleKeys.contains('reducer')) {
      roleKeys.add('Réducteur');
      roleKeys.add('Reducteur');
      roleKeys.add('Réducteure');
    }
    if (query.seriesId == null || roleKeys.isEmpty) {
      return const <Map<String, dynamic>>[];
    }
    if (roleKeys.contains('reducer') &&
        query.hasSimpleGlassForReducer == false) {
      return const <Map<String, dynamic>>[];
    }

    // `frame_extension`/`sash_extension` are additional profiles for the
    // sliding construction. A selector for the base frame or sash must not
    // show them merely because the resolver was given the alias list for the
    // same selector. The administrator's primary role is authoritative.
    final scopedRoleKeys = roleKeys.contains('frame')
        ? roleKeys.where((role) => role == 'frame').toList()
        : roleKeys.contains('sash')
        ? roleKeys.where((role) => role == 'sash').toList()
        : roleKeys;
    final forceFunctionalSlidingProfile = roleKeys.any(
      (role) =>
          role == 'montant_central_slim' ||
          role == 'sash_central_slim' ||
          role == 'complement_haut_base',
    );
    var sections = query.drawingMode == null
        ? await _db.getDesignSectionsForRoles(
            query.seriesId!,
            scopedRoleKeys,
            requireDialog: query.requireDialog,
            requireQuantity: query.requireQuantity,
            requireVisible: !forceFunctionalSlidingProfile,
          )
        : await _db.getDesignSectionsForScopedDialogRoles(
            query.seriesId!,
            scopedRoleKeys,
            usageScope: query.drawingMode == AccessoryDrawingMode.sliding
                ? 'sliding'
                : 'opening',
            requireDialog: query.requireDialog,
            requireQuantity: query.requireQuantity,
            requireVisible: !forceFunctionalSlidingProfile,
          );
    final normalizedMaterial = (query.materialType ?? '').toLowerCase().trim();
    final isAluminium =
        normalizedMaterial.isEmpty ||
        normalizedMaterial == 'aluminium' ||
        normalizedMaterial == 'aluminum' ||
        normalizedMaterial == 'alu';
    final isFrameSelector = roleKeys.contains('frame');

    return sections
        .where((section) {
          final sectionName = (section['name'] ?? '').toString().toLowerCase();
          final sectionType = (section['type'] ?? '').toString().toLowerCase();
          final selectingSlidingMontant = roleKeys.any(
            (role) =>
                role == 'sash_central' ||
                role == 'central' ||
                role == 'sash_lateral' ||
                role == 'lateral' ||
                role == 'chicane',
          );
          final isOpeningSash =
              sectionName.contains('ouvrant') ||
              sectionName.contains('opening') ||
              sectionType.contains('ouvrant') ||
              sectionType.contains('opening');
          if (selectingSlidingMontant &&
              !roleKeys.contains(section['design_role_key']?.toString()) &&
              isOpeningSash &&
              !sectionName.contains('coulissant') &&
              !sectionName.contains('منزلق') &&
              !sectionType.contains('sliding')) {
            return false;
          }
          if (!_designRoleMatchesGlass(section, query)) {
            return false;
          }
          if (isFrameSelector &&
              query.hasSideCovers &&
              !_profileSupportsEnabledSideCover(section)) {
            return false;
          }
          final isPvc = normalizedMaterial == 'pvc';
          if (isFrameSelector &&
              query.multiFrameDrawing &&
              isPvc &&
              profileHasIntegratedSideCover(section)) {
            return false;
          }
          if (query.hasShutter &&
              !query.isCaissonTunnel &&
              isAluminium &&
              isFrameSelector &&
              profileHasIntegratedSideCover(section)) {
            return false;
          }
          return true;
        })
        .map((section) => Map<String, dynamic>.from(section))
        .toList();
  }

  bool _designRoleMatchesGlass(
    Map<String, dynamic> section,
    CatalogCandidateQuery query,
  ) {
    final roleKey = (section['design_role_key'] ?? '').toString();
    if (_roleIgnoresGlassRule(roleKey)) return true;
    final glassRule = (section['design_show_when_glass'] ?? 'any')
        .toString()
        .toLowerCase()
        .trim();
    final selector = query.selectorType.toLowerCase().trim();
    final wantsSimple =
        selector.contains('simple') || selector.contains('مفرد');
    final wantsDouble =
        selector.contains('double') || selector.contains('مزدوج');
    if (glassRule == 'single' || glassRule == 'simple') {
      if (wantsDouble) return false;
      return query.hasSimpleGlassForReducer != false;
    }
    if (glassRule == 'double') {
      if (wantsSimple) return false;
      return query.hasDoubleGlassForRules == true;
    }
    return true;
  }

  Future<List<Map<String, dynamic>>> _resolveCatalogRules(
    CatalogCandidateQuery query,
    String table,
  ) async {
    final roleKeys = _mergedRoleKeys(
      query.roleKeys,
      table == 'Joints'
          ? catalogRuleKeysForJointSelectorType(query.selectorType)
          : catalogRuleKeysForAccessorySelectorType(query.selectorType),
    );
    if (roleKeys.isEmpty) return const <Map<String, dynamic>>[];
    if (table == 'Joints' &&
        query.seriesId == null &&
        !roleKeys.contains('shutter_joint_brosse')) {
      return const <Map<String, dynamic>>[];
    }

    final dbInstance = await _db.db;
    if (dbInstance == null) return const <Map<String, dynamic>>[];
    final rules = await _db.getCatalogItemRules(
      itemTable: table,
      seriesId: query.seriesId,
      // Quantity/drawing rules are scoped to the active series. A global
      // catalogue entry is not an authorization to inject that product into
      // every family: BS90 must have its own enabled role row, as must every
      // future series configured by the administrator.
      exactSeriesOnly: query.seriesId != null,
    );
    // Older catalogues commonly saved an assembly/installation screw rule
    // for the first series only, while the accessory itself was explicitly
    // assigned to several series. Reuse that rule for another assigned
    // series so the screw does not disappear from sliding-series BOMs.
    if (table == 'Accessories' && query.seriesId != null) {
      final requestedRoles = query.roleKeys.map((role) => role.trim()).toSet();
      if (requestedRoles.contains('assembly_screw') ||
          requestedRoles.contains('installation_screw')) {
        final existingItemIds = rules
            .map((rule) => _catalogInt(rule['item_id']))
            .whereType<int>()
            .toSet();
        final fallbacks = await _db.getAssignedAccessoryScrewRuleFallbacks(
          query.seriesId!,
        );
        for (final fallback in fallbacks) {
          final role = '${fallback['role_key'] ?? ''}'.trim();
          final itemId = _catalogInt(fallback['item_id']);
          if (!requestedRoles.contains(role) ||
              itemId == null ||
              !existingItemIds.add(itemId)) {
            continue;
          }
          rules.add({...fallback, 'series_id': query.seriesId});
        }
      }
    }
    final surfaceRules = rules
        .where((rule) => _ruleVisibleOnSurface(rule, query))
        .toList();
    final ruleIds = surfaceRules
        .map((rule) => _catalogInt(rule['item_id']))
        .whereType<int>()
        .toList();

    // CatalogItemRules is authoritative. Do not append rows discovered by
    // name/type matching: that old fallback bypasses show_in_dialog,
    // show_in_quantity and the administrator's selected role.
    if (ruleIds.isEmpty) return const <Map<String, dynamic>>[];

    final rows = await dbInstance.query(
      table,
      where: _activeWhereClause(
        table,
        'id IN (${List.filled(ruleIds.length, '?').join(',')})',
      ),
      whereArgs: ruleIds,
    );
    final byId = {
      for (final row in rows)
        if (_catalogInt(row['id']) != null)
          _catalogInt(row['id'])!: Map<String, dynamic>.from(row),
    };
    final result = <Map<String, dynamic>>[];
    final seen = <int>{};
    for (final rule in surfaceRules) {
      final itemId = _catalogInt(rule['item_id']);
      if (itemId == null || seen.contains(itemId)) continue;
      final row = byId[itemId];
      if (row == null) continue;
      final ruleRole = (rule['role_key'] ?? '').toString().trim();
      final roleMatches = roleKeys.contains(ruleRole);
      final explicitSeriesRule =
          query.seriesId != null &&
          rule['series_id']?.toString() == query.seriesId.toString();
      final globalRoleRule =
          rule['series_id'] == null &&
          catalogRuleAllowsGlobalFallback(ruleRole);
      if (roleMatches &&
          _catalogRuleRowMatchesMaterial(
            row,
            query,
            // A rule explicitly enabled for this series is the catalogue
            // authority. It may intentionally reuse an item whose old
            // `series_id` field still points at another family. A deliberately
            // global role rule likewise controls compatible materials across
            // series, so a Clam/Kit/Gâche role does not need code per series.
            explicitSeriesRule: explicitSeriesRule || globalRoleRule,
          )) {
        seen.add(itemId);
        result.add({...row, 'catalog_rule': Map<String, dynamic>.from(rule)});
      }
    }
    _sortByTargetThicknessIfNeeded(result, query);
    return result;
  }

  void _sortByTargetThicknessIfNeeded(
    List<Map<String, dynamic>> rows,
    CatalogCandidateQuery query,
  ) {
    final target = query.targetThicknessMm;
    if (target == null || target <= 0 || rows.length < 2) return;
    rows.sort((a, b) {
      final aThickness = _catalogDouble(a['thickness']);
      final bThickness = _catalogDouble(b['thickness']);
      final aFits = aThickness >= target - 0.001;
      final bFits = bThickness >= target - 0.001;
      if (aFits != bFits) return aFits ? -1 : 1;
      if (aFits) return aThickness.compareTo(bThickness);
      return bThickness.compareTo(aThickness);
    });
  }

  String _activeWhereClause(String table, String base) {
    if (table == 'Joints') return base;
    return '($base) AND (is_active = 1 OR is_active IS NULL)';
  }

  bool _ruleVisibleOnSurface(
    Map<String, dynamic> rule,
    CatalogCandidateQuery query,
  ) {
    if (rule['is_active'] == 0 || rule['is_active'] == false) return false;
    if (query.requireDialog && rule['show_in_dialog'] == 0) return false;
    if (query.requireQuantity && rule['show_in_quantity'] == 0) return false;
    if (!catalogRuleMatchesExactScope(rule, query.seriesId)) return false;
    if (!_ruleUsageScopeMatches(rule, query.drawingMode)) return false;
    final ruleRole = (rule['role_key'] ?? '').toString();
    if (ruleRole.trim().toLowerCase() == 'espagnolette' &&
        query.effectiveHeightMm != null &&
        !catalogEspagnoletteRuleMatches(
          rule,
          effectiveHeightMm: query.effectiveHeightMm!,
        )) {
      return false;
    }
    if (_roleIgnoresGlassRule(ruleRole)) return true;
    final glassRule = (rule['show_when_glass'] ?? 'any')
        .toString()
        .toLowerCase()
        .trim();
    final selector = query.selectorType.toLowerCase().trim();
    final wantsSimple =
        selector.contains('simple') || selector.contains('مفرد');
    final wantsDouble =
        selector.contains('double') || selector.contains('مزدوج');
    if (glassRule == 'single' || glassRule == 'simple') {
      if (wantsDouble) return false;
      return query.hasSimpleGlassForReducer != false;
    }
    if (glassRule == 'double') {
      if (wantsSimple) return false;
      return query.hasDoubleGlassForRules == true;
    }
    return true;
  }

  bool _ruleUsageScopeMatches(
    Map<String, dynamic> rule,
    AccessoryDrawingMode? drawingMode,
  ) {
    if (drawingMode == null) return true;
    // Assembly screws are physical corner hardware, not sash-opening
    // hardware. Older rules were often saved with `sliding` because the first
    // series configured was a sliding ATP series; that scope must not make the
    // same enabled screw disappear from an opening-series BOM.
    if ((rule['role_key'] ?? '').toString().trim().toLowerCase() ==
        'assembly_screw') {
      return true;
    }
    final scope = (rule['usage_scope'] ?? 'global')
        .toString()
        .trim()
        .toLowerCase();
    if (scope.isEmpty ||
        scope == 'global' ||
        scope == 'auto' ||
        scope == 'both') {
      return true;
    }
    return scope ==
        (drawingMode == AccessoryDrawingMode.sliding ? 'sliding' : 'opening');
  }

  bool _catalogRuleRowMatchesMaterial(
    Map<String, dynamic> row,
    CatalogCandidateQuery query, {
    bool explicitSeriesRule = false,
  }) {
    if (query.category == 'joint') return true;
    final assignedSeries = '${row['series_ids'] ?? ''}'
        .split(',')
        .map((id) => int.tryParse(id.trim()))
        .whereType<int>()
        .toSet();
    final singleSeries = _catalogInt(row['series_id']);
    if (singleSeries != null && singleSeries > 0)
      assignedSeries.add(singleSeries);
    // The rule editor is the source of truth. An explicit active rule for
    // this series deliberately overrides stale legacy ownership stored on
    // the product row; otherwise an administrator could enable a role and
    // still never see it in the BOM. This same override is used only by the
    // explicit global-role allow-list, while the material check below remains
    // the guard against cross-material leakage.
    if (!explicitSeriesRule &&
        assignedSeries.isNotEmpty &&
        !assignedSeries.contains(query.seriesId)) {
      return false;
    }
    final requested = (query.materialType ?? '').toLowerCase().trim();
    if (requested.isEmpty || requested == 'shutter') return true;
    final rawMaterial = row['material_type'];
    final material = (rawMaterial ?? '').toString().toLowerCase().trim();
    if (requested == 'pvc') return material == 'pvc' || material == 'both';
    return material == 'aluminium' ||
        material == 'aluminum' ||
        material == 'both' ||
        material == 'global' ||
        material.isEmpty;
  }

  List<String> _mergedRoleKeys(
    Iterable<String> explicit,
    Iterable<String> inferred,
  ) {
    final seen = <String>{};
    final result = <String>[];
    for (final raw in [...explicit, ...inferred]) {
      final key = raw.trim();
      if (key.isEmpty || !seen.add(key)) continue;
      result.add(key);
    }
    return result;
  }
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
  final bool isCaissonTunnel;
  final bool hasSideCovers;
  final bool multiFrameDrawing;
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
  final List<String> roleKeys;
  final bool? hasSimpleGlassForReducer;
  final bool? hasDoubleGlassForRules;
  final double? targetThicknessMm;
  final Map<String, double> mainWarehouseStock;
  final int? stockColorId;

  const ProfileSelectorDialog({
    super.key,
    required this.profileType,
    this.category = 'profile',
    this.seriesId,
    this.materialType,
    this.hasShutter = false,
    this.isCaissonTunnel = false,
    this.hasSideCovers = false,
    this.multiFrameDrawing = false,
    this.windowHeight,
    this.targetSize,
    this.kitDescriptionCode,
    this.maxAccessoryLength,
    this.accessoryDrawingMode,
    this.bladeId,
    this.selectedBladeName,
    this.selectedBladeIsX3d,
    this.motorDiameter,
    this.roleKeys = const [],
    this.hasSimpleGlassForReducer,
    this.hasDoubleGlassForRules,
    this.targetThicknessMm,
    this.mainWarehouseStock = const {},
    this.stockColorId,
  });

  @override
  _ProfileSelectorDialogState createState() => _ProfileSelectorDialogState();
}

class _ProfileSelectorDialogState extends State<ProfileSelectorDialog> {
  List<Map<String, dynamic>> profiles = [];
  bool isLoading = true;
  String? _loadError;

  double? _mainStockForCandidate(Map<String, dynamic> candidate) {
    final id = _catalogInt(candidate['id']);
    if (id == null) return null;
    String? itemType;
    switch (widget.category) {
      case 'profile':
        itemType = 'Section';
      case 'joint':
        itemType = 'Joints';
      case 'accessory':
      case 'other':
        itemType = 'Accessory';
      case 'glass':
        itemType = 'Glass';
    }
    if (itemType == null) return null;
    String key(int? colorId) => '$itemType|$id|${colorId ?? 0}';
    return widget.mainWarehouseStock[key(widget.stockColorId)] ??
        widget.mainWarehouseStock[key(null)] ??
        0.0;
  }

  @override
  void initState() {
    super.initState();
    _loadProfiles();
  }

  Future<void> _loadProfiles() async {
    final db = SqlDatabase();
    List<Map<String, dynamic>> data = [];

    try {
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

      if (widget.category != 'shutter') {
        final forceVisibleInDialog = widget.roleKeys.any(
          (role) =>
              role == 'montant_central_slim' ||
              role == 'sash_central_slim' ||
              role == 'complement_haut_base',
        );
        data = await CatalogCandidateResolver(database: db)
            .resolve(
              CatalogCandidateQuery(
                category: widget.category,
                selectorType: widget.profileType,
                roleKeys: widget.roleKeys,
                seriesId: widget.seriesId,
                materialType: widget.materialType,
                hasShutter: widget.hasShutter,
                isCaissonTunnel: widget.isCaissonTunnel,
                hasSideCovers: widget.hasSideCovers,
                multiFrameDrawing: widget.multiFrameDrawing,
                drawingMode: widget.accessoryDrawingMode,
                // Slim and its 10 cm top/bottom complement are functional drawing
                // components. Their replacement must remain available whenever the
                // role exists, even if a legacy row has show_in_dialog unchecked.
                requireDialog: !forceVisibleInDialog,
                requireQuantity: widget.category != 'profile',
                hasSimpleGlassForReducer: widget.hasSimpleGlassForReducer,
                hasDoubleGlassForRules: widget.hasDoubleGlassForRules,
                targetThicknessMm: widget.targetThicknessMm,
              ),
            )
            // A catalog failure must never leave the selector permanently busy.
            .timeout(const Duration(seconds: 15));
        if (!mounted) return;
        setState(() {
          profiles = data;
          isLoading = false;
          _loadError = null;
        });
        return;
      }

      if (widget.category == 'accessory' || widget.category == 'other') {
        final myDb = myDbInstance;
        if (myDb != null) {
          final ruleKeys = catalogRuleKeysForAccessorySelectorType(
            widget.profileType,
          );
          if (ruleKeys.isNotEmpty) {
            final rules = await db.getCatalogItemRules(
              itemTable: 'Accessories',
              seriesId: widget.seriesId,
              roleKeys: ruleKeys,
            );
            final ruleIds = rules
                .where(
                  (rule) =>
                      rule['show_in_dialog'] != 0 &&
                      catalogRuleMatchesExactScope(rule, widget.seriesId),
                )
                .map((rule) => _catalogInt(rule['item_id']))
                .whereType<int>()
                .toList();
            if (ruleIds.isNotEmpty) {
              final rows = await myDb.query(
                'Accessories',
                where:
                    'id IN (${List.filled(ruleIds.length, '?').join(',')}) AND (is_active = 1 OR is_active IS NULL)',
                whereArgs: ruleIds,
              );
              final isShutterScrew = _isShutterScrewSelectorType(
                widget.profileType,
              );
              bool materialMatches(Map<String, dynamic> row) {
                if (isShutterScrew || widget.materialType == null) return true;
                final material = (row['material_type'] ?? '')
                    .toString()
                    .toLowerCase()
                    .trim();
                final requested = widget.materialType!.toLowerCase().trim();
                if (requested == 'pvc') {
                  return material == 'pvc' || material == 'both';
                }
                return material == 'aluminium' ||
                    material == 'aluminum' ||
                    material == 'both' ||
                    material.isEmpty;
              }

              final byId = {
                for (final row in rows.where(materialMatches))
                  if (_catalogInt(row['id']) != null)
                    _catalogInt(row['id'])!: row,
              };
              data = [
                for (final itemId in ruleIds)
                  if (byId[itemId] != null)
                    Map<String, dynamic>.from(byId[itemId]!),
              ];
            }
          }
        }
      } else if (widget.category == 'joint') {
        final myDb = await db.db;
        if (myDb != null) {
          // Apply the exact same scope rule used for accessories: a joint that
          // has one or more series is exclusive to them; a joint without a
          // series is global only for its material.
          final t = widget.profileType.toLowerCase();
          final roleKeys = catalogRuleKeysForJointSelectorType(t);
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
            var matchingTypeRows = <Map<String, dynamic>>[];
            if (roleKeys.isNotEmpty) {
              final rules = await db.getCatalogItemRules(
                itemTable: 'Joints',
                seriesId: widget.seriesId,
                roleKeys: roleKeys,
              );
              final ruleIds = rules
                  .where(
                    (rule) =>
                        rule['show_in_dialog'] != 0 &&
                        catalogRuleMatchesExactScope(rule, widget.seriesId),
                  )
                  .map((rule) => _catalogInt(rule['item_id']))
                  .whereType<int>()
                  .toSet();
              if (ruleIds.isNotEmpty) {
                matchingTypeRows = allJoints
                    .where(
                      (joint) =>
                          ruleIds.contains((joint['id'] as num?)?.toInt()),
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
          } else if (roleKeys.isNotEmpty) {
            final allJoints = await myDb.query(
              'Joints',
              where:
                  "(series_id IS NULL OR series_id = 0) AND (series_ids IS NULL OR TRIM(series_ids) = '')",
            );
            final rules = await db.getCatalogItemRules(
              itemTable: 'Joints',
              roleKeys: roleKeys,
            );
            final ruleIds = rules
                .where(
                  (rule) =>
                      rule['show_in_dialog'] != 0 &&
                      catalogRuleMatchesExactScope(rule, null),
                )
                .map((rule) => _catalogInt(rule['item_id']))
                .whereType<int>()
                .toSet();
            data = allJoints
                .where(
                  (joint) => ruleIds.contains((joint['id'] as num?)?.toInt()),
                )
                .map((joint) => Map<String, dynamic>.from(joint))
                .toList();
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
                      (a, b) => (a['box_size'] as num).compareTo(
                        b['box_size'] as num,
                      ),
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
                final aDiameter =
                    shutterComponentDiameter(a) ?? double.infinity;
                final bDiameter =
                    shutterComponentDiameter(b) ?? double.infinity;
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
        if (myDb != null && widget.seriesId != null) {
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

          // The explicit role mapping created by the administrator in
          // "Définition intelligente de la série" is authoritative. An empty
          // mapping means that this profile does not exist for the series.
          final roleKeys = seriesRoleKeysForProfileSelectorType(t);
          if (widget.seriesId != null && roleKeys.isNotEmpty) {
            final roleRows = await db.getSeriesDesignRoles(widget.seriesId!);
            if (roleRows.isEmpty) {
              data = <Map<String, dynamic>>[];
            } else if (widget.accessoryDrawingMode != null) {
              // A frame extension is a sliding track addition, never an
              // opening-frame choice. The role scope is authoritative for all
              // other profile replacements as well.
              final isBaseFrameSelector =
                  t == 'frame' || t == 'cadre' || t == 'إطار';
              final isBaseSashSelector =
                  t == 'sash' || t == 'ouvrant' || t == 'ضلفة';
              final scopedRoleKeys = isBaseFrameSelector
                  ? const ['frame']
                  : isBaseSashSelector
                  ? const ['sash']
                  : roleKeys;
              data = await db.getDesignSectionsForScopedDialogRoles(
                widget.seriesId!,
                scopedRoleKeys,
                usageScope:
                    widget.accessoryDrawingMode == AccessoryDrawingMode.sliding
                    ? 'sliding'
                    : 'opening',
                requireDialog: true,
                requireQuantity: true,
              );
            } else {
              data = await db.getDesignSectionsForRoles(
                widget.seriesId!,
                roleKeys,
              );
            }
          }
          final isFrameSelector = t == 'frame' || t == 'cadre' || t == 'إطار';
          final material = (widget.materialType ?? '').toLowerCase().trim();
          final isAluminium =
              material.isEmpty ||
              material == 'aluminium' ||
              material == 'aluminum' ||
              material == 'alu';
          if (widget.hasShutter &&
              !widget.isCaissonTunnel &&
              isAluminium &&
              isFrameSelector) {
            data = data
                .where((item) => !profileHasIntegratedSideCover(item))
                .toList();
          }
        } else {
          data = [];
        }
      }

      if (!mounted) return;
      setState(() {
        profiles = data;
        isLoading = false;
        _loadError = null;
      });
    } catch (error, stackTrace) {
      debugPrint(
        'Profile selector failed to load ${widget.profileType}: $error',
      );
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted) return;
      setState(() {
        profiles = [];
        isLoading = false;
        _loadError = error.toString();
      });
    }
  }

  String searchQuery = '';

  @override
  Widget build(BuildContext context) {
    final lang = Provider.of<AppSettingsProvider>(context).language;
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
      title: Text(
        '${Localization.translate('اختر', lang)} '
        '${Localization.translate(widget.profileType, lang)}',
      ),
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
                    hintText: Localization.translate('بحث...', lang),
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
                    : _loadError != null
                    ? SizedBox(
                        height: 130,
                        child: Center(
                          child: TextButton.icon(
                            icon: const Icon(Icons.refresh_rounded),
                            label: Text(
                              Localization.translate('إعادة المحاولة', lang),
                            ),
                            onPressed: () {
                              setState(() {
                                isLoading = true;
                                _loadError = null;
                              });
                              _loadProfiles();
                            },
                          ),
                        ),
                      )
                    : filtered.isEmpty
                    ? SizedBox(
                        height: 100,
                        child: Center(
                          child: Text(
                            Localization.translate(
                              'لا توجد نتائج مطابقة',
                              lang,
                            ),
                          ),
                        ),
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
                          final stock = _mainStockForCandidate(item);

                          return ListTile(
                            leading: SectionImageWidget(
                              code: item['code']?.toString(),
                              name: item['name']?.toString(),
                              imagePath: item['image_path']?.toString(),
                              // The profile cross-section is the key part of
                              // this dialog; 40 px made plinths practically
                              // impossible to distinguish.
                              size: 72.0,
                            ),
                            title: Text('$codeStr$nameStr'),
                            subtitle: stock == null
                                ? null
                                : Text(
                                    '${Localization.translate('المستودع الرئيسي', lang)}: ${stock.toStringAsFixed(stock % 1 == 0 ? 0 : 2)}',
                                    style: TextStyle(
                                      color: stock <= 0
                                          ? Colors.red.shade700
                                          : Colors.teal.shade700,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
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
          child: Text(Localization.translate('إلغاء', lang)),
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
