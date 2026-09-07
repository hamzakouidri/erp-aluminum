import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../settings/app_settings.dart';
import '../settings/localization.dart';
import '../sql_database.dart';
import '../services/cloud_sync_service.dart';
import '../widgets/section_image.dart';

class CatalogRulesScreen extends StatefulWidget {
  const CatalogRulesScreen({super.key, required this.db});

  final SqlDatabase db;

  @override
  State<CatalogRulesScreen> createState() => _CatalogRulesScreenState();
}

class _RuleRole {
  const _RuleRole(this.key, this.ar, this.fr);

  final String key;
  final String ar;
  final String fr;
}

class _CatalogGroup {
  const _CatalogGroup({
    required this.key,
    required this.ar,
    required this.fr,
    required this.icon,
    required this.roleKeys,
  });

  final String key;
  final String ar;
  final String fr;
  final IconData icon;
  final Set<String> roleKeys;
}

class _CatalogRulesScreenState extends State<CatalogRulesScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  late final Map<String, TextEditingController> _searchControllers;

  // Keep accessories and joints as separate grouped rule pages. Shutter
  // components and side-cover profiles continue to use their dedicated
  // profile/shutter selectors and are not mixed into this catalogue page.
  final _tables = const ['Accessories', 'Joints'];
  final Map<String, List<Map<String, dynamic>>> _itemsByTable = {};
  final Map<String, Map<String, dynamic>> _rulesByItem = {};
  bool _loading = true;
  bool _saving = false;

  String _t(String ar, String fr) {
    final language = context.read<AppSettingsProvider>().language;
    if (language == AppLanguage.arabic) return ar;
    if (language == AppLanguage.french) return fr;
    if (ar.startsWith('الدور:')) {
      final role = ar.substring('الدور:'.length).trim();
      return 'Role: ${Localization.translate(role, AppLanguage.english)}';
    }
    final english = Localization.translate(ar, AppLanguage.english);
    return english == ar ? fr : english;
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tables.length, vsync: this);
    _searchControllers = {
      for (final table in _tables) table: TextEditingController(),
    };
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    for (final controller in _searchControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final results = await Future.wait<dynamic>([
      widget.db.readAccessories(),
      widget.db.readJoints(),
      widget.db.getCatalogItemRules(itemTable: 'Accessories'),
      widget.db.getCatalogItemRules(itemTable: 'Joints'),
    ]);
    if (!mounted) return;
    _itemsByTable
      ..clear()
      ..addAll({
        'Accessories': results[0] as List<Map<String, dynamic>>,
        'Joints': results[1] as List<Map<String, dynamic>>,
      });
    _rulesByItem.clear();
    for (final raw in [
      ...(results[2] as List<Map<String, dynamic>>),
      ...(results[3] as List<Map<String, dynamic>>),
    ]) {
      final table = raw['item_table']?.toString() ?? '';
      final itemId = (raw['item_id'] as num?)?.toInt();
      if (table.isEmpty || itemId == null) continue;
      _rulesByItem[_itemKey(table, itemId)] = Map<String, dynamic>.from(raw);
    }
    for (final table in _tables) {
      for (final item
          in _itemsByTable[table] ?? const <Map<String, dynamic>>[]) {
        final itemId = _itemId(item);
        if (itemId == null) continue;
        _ruleFor(table, itemId);
      }
    }
    setState(() => _loading = false);
  }

  List<_RuleRole> _rolesForTable(String table) {
    switch (table) {
      case 'ShutterComponents':
        return const [
          _RuleRole('shutter_blade', 'شرائح الستار', 'Lames volet'),
          _RuleRole('shutter_box', 'صندوق الستار', 'Caisson'),
          _RuleRole('shutter_track', 'كوليس / سكة الستار', 'Coulisse'),
          _RuleRole('shutter_axis', 'محور الستار', 'Axe volet'),
          _RuleRole('shutter_motor', 'محرك الستار', 'Moteur volet'),
          _RuleRole('shutter_final_blade', 'الشريحة النهائية', 'Lame finale'),
          _RuleRole('shutter_cover', 'أغطية الشفرات', 'Bouchons lames'),
          _RuleRole('shutter_kit', 'كيت الستار', 'Kit volet'),
          _RuleRole('other', 'أخرى', 'Autre'),
        ];
      case 'Accessories':
        return const [
          _RuleRole('kit_screw', 'براغي الكيت', 'Vis kit'),
          _RuleRole('box_screw', 'براغي الصندوق', 'Vis caisson'),
          _RuleRole('motor_screw', 'براغي المحرك', 'Vis moteur'),
          _RuleRole('batmo_screw', 'براغي الباتمو', 'Vis batmo'),
          _RuleRole('bouchon_batmo', 'بوشون باتمو', 'Bouchon battement'),
          _RuleRole(
            'bouchon_batmo_screw',
            'براغي بوشون باتمو',
            'Vis bouchon batmo',
          ),
          _RuleRole('renfort_screw', 'براغي حديد الدعم', 'Vis renfort'),
          _RuleRole('manivelle_screw', 'براغي المانيفال', 'Vis manivelle'),
          _RuleRole('assembly_screw', 'براغي التجميع', 'Vis assemblage'),
          _RuleRole('installation_screw', 'براغي التركيب', 'Vis pose'),
          _RuleRole('accessory_screw', 'براغي الإكسسوارات', 'Vis accessoires'),
          _RuleRole('sliding_kit', 'كيت المنزلق', 'Kit coulissant'),
          _RuleRole('gache_simple', 'قاش بسيط', 'Gâche simple'),
          _RuleRole('gache_double', 'قاش مزدوج', 'Gâche double'),
          _RuleRole('gache_door', 'قاش باب', 'Gâche porte'),
          _RuleRole('lock_clef', 'قفل بمفتاح', 'Serrure à clé'),
          _RuleRole(
            'lock_condamnation',
            'قفل كونداناسيون',
            'Serrure condamnation',
          ),
          _RuleRole('sliding_clamp', 'كلام منزلق', 'Clam coulissant'),
          _RuleRole('sliding_lock', 'قفل/قاش منزلق', 'Gâche coulissant'),
          _RuleRole('verrou', 'فيرو', 'Verrou'),
          _RuleRole('cremone', 'كريمون', 'Crémone'),
          _RuleRole('tringle', 'تراينغل الكريمون', 'Tringle crémone'),
          _RuleRole('espagnolette', 'إسبانيوليت', 'Espagnolette'),
          _RuleRole('canon', 'أسطوانة الباب', 'Canon'),
          _RuleRole(
            'door_handle_key',
            'مقبض باب بمفتاح',
            'Poignée porte à clé',
          ),
          _RuleRole(
            'door_handle_condamnation',
            'مقبض باب كونداناسيون',
            'Poignée porte condamnation',
          ),
          _RuleRole('handle', 'مقبض', 'Poignée'),
          _RuleRole('hinge', 'مفاصل', 'Paumelles'),
          _RuleRole('tasso', 'طاسو', 'Tasso'),
          _RuleRole('ekar', 'إيكار', 'Ekar'),
          _RuleRole('roulette', 'عجلات', 'Roulettes'),
          _RuleRole('entrematique', 'أونتروماتيك', 'Entrematique'),
          _RuleRole(
            'sliding_kit_40000',
            'كيت سلسلة 40000 TPR',
            'Kit série 40000 TPR',
          ),
          _RuleRole(
            'sliding_kit_67000',
            'كيت سلسلة 67000 TPR',
            'Kit série 67000 TPR',
          ),
          _RuleRole('other', 'أخرى', 'Autre'),
        ];
      case 'Joints':
        return const [
          _RuleRole('joint_vitrage', 'جوان فيتراج', 'Joint vitrage'),
          _RuleRole('joint_bourrage', 'جوان بوراج', 'Joint bourrage'),
          _RuleRole('joint_frappe', 'جوان فراب', 'Joint frappe'),
          _RuleRole('joint_central', 'جوان سنترال', 'Joint central'),
          _RuleRole('joint_brosse', 'جوان بروس', 'Joint brosse'),
          _RuleRole('joint_bronze', 'جوان برونز', 'Joint bronze'),
          _RuleRole(
            'shutter_joint_brosse',
            'جوان بروس الستار',
            'Joint brosse volet',
          ),
          _RuleRole('other', 'أخرى', 'Autre'),
        ];
      default:
        return const [_RuleRole('other', 'أخرى', 'Autre')];
    }
  }

  String _itemKey(String table, int itemId) => '$table:$itemId';

  int? _itemId(Map<String, dynamic> item) =>
      (item['id'] as num?)?.toInt() ?? int.tryParse('${item['id']}');

  String _withoutQualityLabel(String value) {
    return value
        .replaceAll(
          RegExp(
            r'\s*\(\s*(?:جودة\s+(?:رفيعة|قياسية|تجارية)|qualité\s+(?:haute|standard|commerciale)|(?:premium|standard|commercial)\s+quality)\s*\)',
            caseSensitive: false,
          ),
          '',
        )
        .trim();
  }

  String _itemTitle(Map<String, dynamic> item) {
    final code = item['code']?.toString().trim() ?? '';
    final name = _withoutQualityLabel(item['name']?.toString() ?? '');
    if (code.isEmpty) return name;
    return '$code - $name';
  }

  String _itemSubtitle(Map<String, dynamic> item) {
    final parts = <String>[];
    for (final key in const [
      'type',
      'component_type',
      'shutter_subtype',
      'unit',
      'gasket_type',
    ]) {
      final value = item[key]?.toString().trim() ?? '';
      if (value.isNotEmpty) {
        // Accessory types are stored as category|quality|usage.  Quality is
        // retained as metadata but is not part of the visible rule label.
        parts.add(
          key == 'type' ? _withoutQualityLabel(value.split('|').first) : value,
        );
      }
    }
    return parts.join(' • ');
  }

  String _foldSearchText(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'[\u064B-\u065F\u0670]'), '')
        .replaceAll('أ', 'ا')
        .replaceAll('إ', 'ا')
        .replaceAll('آ', 'ا')
        .replaceAll('ة', 'ه')
        .replaceAll('ى', 'ي')
        .replaceAll('é', 'e')
        .replaceAll('è', 'e')
        .replaceAll('ê', 'e')
        .replaceAll('à', 'a')
        .replaceAll('ç', 'c');
  }

  bool _matchesSearch(
    String table,
    Map<String, dynamic> item,
    String rawQuery,
  ) {
    final query = _foldSearchText(rawQuery).trim();
    if (query.isEmpty) return true;
    final itemId = _itemId(item);
    final rule = itemId == null ? null : _rulesByItem[_itemKey(table, itemId)];
    final roleKey = rule?['role_key']?.toString() ?? '';
    final roleLabel = _rolesForTable(table)
        .where((role) => role.key == roleKey)
        .map((role) => '${role.ar} ${role.fr}')
        .join(' ');
    final haystack = _foldSearchText(
      [
        _itemTitle(item),
        _itemSubtitle(item),
        item['code'],
        item['name'],
        item['type'],
        item['component_type'],
        item['shutter_subtype'],
        item['gasket_type'],
        roleKey,
        roleLabel,
      ].whereType<Object>().join(' '),
    );
    return query
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .every((part) => haystack.contains(part));
  }

  Map<String, dynamic> _defaultRule(String table, int itemId) {
    return {
      'item_table': table,
      'item_id': itemId,
      // An item is enabled only after the administrator activates its button.
      // The old guessed role is still used as a convenient first suggestion
      // when the button is activated, but is not enabled silently.
      'role_key': '',
      'usage_scope': 'global',
      'show_when_glass': 'any',
      'selection_mode': 'always',
      'integrated_side_cover': false,
      'allows_side_cover': true,
      'allowed_with_shutter': true,
      'show_in_drawing': true,
      'show_in_quantity': true,
      'show_in_dialog': true,
      'width_adjust_mm': 0.0,
      'height_adjust_mm': 0.0,
      'formula_note': '',
      'is_default': false,
      'is_active': false,
    };
  }

  bool _truthy(dynamic value, {bool fallback = false}) {
    if (value == null) return fallback;
    if (value is bool) return value;
    if (value is num) return value != 0;
    final text = value.toString().trim().toLowerCase();
    return text == '1' || text == 'true' || text == 'yes' || text == 'oui';
  }

  bool _itemRuleEnabled(String table, Map<String, dynamic> item) {
    final itemId = _itemId(item);
    if (itemId == null) return false;
    return _truthy(_ruleFor(table, itemId)['is_active']);
  }

  void _toggleItem(String table, Map<String, dynamic> item, bool enabled) {
    final itemId = _itemId(item);
    if (itemId == null) return;
    final rule = _ruleFor(table, itemId);
    setState(() {
      rule['is_active'] = enabled;
      if (enabled && (rule['role_key']?.toString().trim().isEmpty ?? true)) {
        rule['role_key'] = _guessRole(table, item);
      }
    });
  }

  List<_CatalogGroup> _groupsForTable(String table) {
    if (table == 'Joints') {
      return const [
        _CatalogGroup(
          key: 'joints',
          ar: 'الجوان',
          fr: 'Joints',
          icon: Icons.linear_scale_outlined,
          roleKeys: {
            'joint_vitrage',
            'joint_bourrage',
            'joint_frappe',
            'joint_central',
            'joint_brosse',
            'joint_bronze',
            'shutter_joint_brosse',
            'other',
          },
        ),
      ];
    }
    return const [
      _CatalogGroup(
        key: 'screws',
        ar: 'الفيس',
        fr: 'Vis',
        icon: Icons.build_outlined,
        roleKeys: {
          'kit_screw',
          'box_screw',
          'motor_screw',
          'batmo_screw',
          'bouchon_batmo_screw',
          'renfort_screw',
          'manivelle_screw',
          'assembly_screw',
          'installation_screw',
          'accessory_screw',
        },
      ),
      _CatalogGroup(
        key: 'gaches',
        ar: 'القاش',
        fr: 'Gâches',
        icon: Icons.toggle_on_outlined,
        roleKeys: {
          'gache_simple',
          'gache_double',
          'gache_door',
          'sliding_lock',
        },
      ),
      _CatalogGroup(
        key: 'locks',
        ar: 'الأقفال',
        fr: 'Serrures et verrous',
        icon: Icons.lock_outline,
        roleKeys: {'lock_clef', 'lock_condamnation', 'verrou', 'canon'},
      ),
      _CatalogGroup(
        key: 'handles',
        ar: 'المقابض والكريمون',
        fr: 'Poignées et crémone',
        icon: Icons.pan_tool_outlined,
        roleKeys: {
          'handle',
          'door_handle_key',
          'door_handle_condamnation',
          'cremone',
          'tringle',
        },
      ),
      _CatalogGroup(
        key: 'hinges',
        ar: 'المفصلات',
        fr: 'Paumelles',
        icon: Icons.settings_input_component_outlined,
        roleKeys: {'hinge'},
      ),
      _CatalogGroup(
        key: 'moving',
        ar: 'الطاسو والإيكار والعجلات',
        fr: 'Tasso, Ekar et roulettes',
        icon: Icons.circle_outlined,
        roleKeys: {
          'tasso',
          'ekar',
          'roulette',
          'sliding_kit',
          'sliding_kit_40000',
          'sliding_kit_67000',
          'sliding_clamp',
        },
      ),
      _CatalogGroup(
        key: 'other',
        ar: 'أكسسوارات أخرى',
        fr: 'Autres accessoires',
        icon: Icons.extension_outlined,
        roleKeys: {'other', 'entrematique'},
      ),
    ];
  }

  String _groupRoleForItem(String table, Map<String, dynamic> item) {
    final guessed = _guessRole(table, item);
    if (table == 'Accessories' && guessed == 'other' && _isScrewItem(item)) {
      return 'accessory_screw';
    }
    return guessed;
  }

  bool _isScrewItem(Map<String, dynamic> item) {
    final text = '${item['name'] ?? ''} ${item['type'] ?? ''}'.toLowerCase();
    return text.contains('vis') ||
        text.contains('screw') ||
        text.contains('برغ') ||
        _truthy(item['is_kit_screw']) ||
        _truthy(item['is_caisson_screw']) ||
        _truthy(item['is_moteur_screw']) ||
        _truthy(item['is_batmo_screw']) ||
        _truthy(item['is_bouchon_batmo_screw']) ||
        _truthy(item['is_renfort_screw']) ||
        _truthy(item['is_manivelle_screw']) ||
        _truthy(item['is_assembly_screw']) ||
        _truthy(item['is_installation_screw']) ||
        _truthy(item['is_accessory_screw']);
  }

  bool _itemBelongsToGroup(
    String table,
    Map<String, dynamic> item,
    _CatalogGroup group,
  ) {
    return group.roleKeys.contains(_groupRoleForItem(table, item));
  }

  List<_RuleRole> _rolesForItem(String table, Map<String, dynamic> item) {
    final group = _groupsForTable(table).firstWhere(
      (candidate) => _itemBelongsToGroup(table, item, candidate),
      orElse: () => _groupsForTable(table).last,
    );
    final roles = _rolesForTable(
      table,
    ).where((role) => group.roleKeys.contains(role.key)).toList();
    final itemId = _itemId(item);
    final currentKey = itemId == null
        ? ''
        : _ruleFor(table, itemId)['role_key']?.toString() ?? '';
    if (currentKey.isNotEmpty && !roles.any((role) => role.key == currentKey)) {
      final currentRole = _rolesForTable(
        table,
      ).where((role) => role.key == currentKey);
      if (currentRole.isNotEmpty) roles.add(currentRole.first);
    }
    return roles;
  }

  String _guessRole(String table, Map<String, dynamic>? item) {
    final text =
        '${item?['name'] ?? ''} ${item?['type'] ?? ''} '
                '${item?['component_type'] ?? ''} ${item?['gasket_type'] ?? ''}'
            .toLowerCase();
    bool flag(String key) {
      final value = item?[key];
      if (value is bool) return value;
      if (value is num) return value != 0;
      final raw = value?.toString().trim().toLowerCase();
      return raw == '1' || raw == 'true' || raw == 'yes';
    }

    if (table == 'ShutterComponents') {
      if (text.contains('caisson') || text.contains('صندوق')) {
        return 'shutter_box';
      }
      if (text.contains('coulisse') || text.contains('كوليس')) {
        return 'shutter_track';
      }
      if (text.contains('axe') || text.contains('محور')) return 'shutter_axis';
      if (text.contains('moteur') || text.contains('محرك')) {
        return 'shutter_motor';
      }
      if (text.contains('kit') || text.contains('كيت')) return 'shutter_kit';
      if (text.contains('bouchon') || text.contains('غطاء')) {
        return 'shutter_cover';
      }
      return 'shutter_blade';
    }
    if (table == 'Accessories') {
      final isBouchonBatmo =
          (text.contains('bouchon') ||
              text.contains('bochon') ||
              text.contains('بوشون')) &&
          (text.contains('batmo') || text.contains('باتمو'));
      final isScrew =
          text.contains('vis') ||
          text.contains('screw') ||
          text.contains('براغ');
      if (flag('is_kit_screw')) return 'kit_screw';
      if (flag('is_caisson_screw')) return 'box_screw';
      if (flag('is_moteur_screw')) return 'motor_screw';
      if (flag('is_batmo_screw')) return 'batmo_screw';
      if (flag('is_bouchon_batmo_screw')) return 'bouchon_batmo_screw';
      if (flag('is_renfort_screw')) return 'renfort_screw';
      if (flag('is_manivelle_screw')) return 'manivelle_screw';
      if (flag('is_assembly_screw')) return 'assembly_screw';
      if (flag('is_installation_screw')) return 'installation_screw';
      if (flag('is_accessory_screw')) return 'accessory_screw';
      if (flag('is_gache_simple')) return 'gache_simple';
      if (flag('is_gache_double')) return 'gache_double';
      if (flag('is_gache_porte')) return 'gache_door';
      if (flag('is_lock_clef')) return 'lock_clef';
      if (flag('is_lock_condamnation')) return 'lock_condamnation';
      if (text.contains('kit') &&
          (text.contains('vis') || text.contains('براغ'))) {
        return 'kit_screw';
      }
      if (isBouchonBatmo && isScrew) return 'bouchon_batmo_screw';
      if (isBouchonBatmo) return 'bouchon_batmo';
      if ((text.contains('caisson') || text.contains('صندوق')) &&
          (text.contains('vis') || text.contains('براغ'))) {
        return 'box_screw';
      }
      if ((text.contains('40000') || text.contains('40000')) &&
          (text.contains('kit') || text.contains('كيت'))) {
        return 'sliding_kit_40000';
      }
      if ((text.contains('67000') || text.contains('67000')) &&
          (text.contains('kit') || text.contains('كيت'))) {
        return 'sliding_kit_67000';
      }
      if (text.contains('kit') || text.contains('كيت')) return 'sliding_kit';
      if (text.contains('clam')) return 'sliding_clamp';
      if (text.contains('gache couliss') || text.contains('gâche couliss')) {
        return 'sliding_lock';
      }
      if (text.contains('gache') || text.contains('gâche')) {
        if (text.contains('double') || text.contains('d.t')) {
          return 'gache_double';
        }
        if (text.contains('porte')) return 'gache_door';
        return 'gache_simple';
      }
      if (text.contains('tringle') ||
          text.contains('tangle') ||
          text.contains('triangle') ||
          text.contains('تراينغل') ||
          text.contains('تريانغل')) {
        return 'tringle';
      }
      if (text.contains('verrou') || text.contains('فيرو')) return 'verrou';
      if (text.contains('cremone') ||
          text.contains('crémone') ||
          text.contains('كريمون')) {
        return 'cremone';
      }
      if (text.contains('espagnolette') ||
          text.contains('اسبانيوليت') ||
          text.contains('إسبانيوليت')) {
        return 'espagnolette';
      }
      if (text.contains('canon') || text.contains('أسطوانة')) return 'canon';
      if (text.contains('poignée porte') || text.contains('poignee porte')) {
        if (text.contains('condamnation')) {
          return 'door_handle_condamnation';
        }
        return 'door_handle_key';
      }
      if (text.contains('poign') || text.contains('مقبض')) return 'handle';
      if (text.contains('paum') || text.contains('مفصل')) return 'hinge';
      if (text.contains('tasso') || text.contains('طاسو')) return 'tasso';
      if (text.contains('ekar') ||
          text.contains('ikar') ||
          text.contains('إيكار') ||
          text.contains('ايكار')) {
        return 'ekar';
      }
      if (text.contains('roulette') || text.contains('عجلات')) {
        return 'roulette';
      }
      if (text.contains('entrematique') ||
          text.contains('أونتروماتيك') ||
          text.contains('انتراميتيك') ||
          text.contains('intra')) {
        return 'entrematique';
      }
      return 'other';
    }
    if (table == 'Joints') {
      if (text.contains('vitrage') || text.contains('فيتراج')) {
        return 'joint_vitrage';
      }
      if (text.contains('bourrage') || text.contains('بوراج')) {
        return 'joint_bourrage';
      }
      if (text.contains('frappe') || text.contains('فراب')) {
        return 'joint_frappe';
      }
      if (text.contains('central') || text.contains('سنترال')) {
        return 'joint_central';
      }
      if (text.contains('bronze') || text.contains('برونز')) {
        return 'joint_bronze';
      }
      if ((text.contains('bross') || text.contains('بروس')) &&
          (text.contains('shutter') ||
              text.contains('volet') ||
              text.contains('ستار'))) {
        return 'shutter_joint_brosse';
      }
      if (text.contains('bross') || text.contains('بروس')) {
        return 'joint_brosse';
      }
    }
    return 'other';
  }

  Map<String, dynamic> _ruleFor(String table, int itemId) {
    return _rulesByItem.putIfAbsent(
      _itemKey(table, itemId),
      () => _defaultRule(table, itemId),
    );
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      for (final table in _tables) {
        final rules = _rulesByItem.entries
            .where((entry) => entry.key.startsWith('$table:'))
            .map((entry) => entry.value)
            .where(
              (rule) =>
                  _truthy(rule['is_active']) &&
                  (rule['role_key']?.toString().isNotEmpty ?? false),
            )
            .toList();
        await widget.db.saveCatalogItemRules(
          itemTable: table,
          rules: rules,
          syncCatalog: false,
        );
      }
      // Upload once after both local tables are committed. Do not make the
      // save button wait for Supabase or fail when the server is slow.
      unawaited(CloudSyncService().notifyCatalogChange());
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(
            content: Text(
              _t('تم حفظ قواعد الكتالوج العامة.', 'Règles enregistrées.'),
            ),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(
            content: Text(
              '${_t('تعذر حفظ قواعد الكتالوج', 'Enregistrement impossible')}: $error',
            ),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<AppSettingsProvider>();
    if (!settings.isAdmin) {
      return Scaffold(
        appBar: AppBar(
          title: Text(_t('قواعد الكتالوج العامة', 'Règles du catalogue')),
        ),
        body: Center(
          child: Text(
            _t(
              'ليس لديك صلاحية للوصول إلى قواعد الكتالوج.',
              'Vous n\'avez pas accès aux règles du catalogue.',
            ),
          ),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _t(
            'قواعد الأكسسوارات والجوانات',
            'Règles des accessoires et des joints',
          ),
        ),
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(
              icon: const Icon(Icons.extension_outlined),
              text: _t('الأكسسوارات', 'Accessoires'),
            ),
            Tab(
              icon: const Icon(Icons.linear_scale_outlined),
              text: _t('الجوانات', 'Joints'),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: _t('حفظ', 'Enregistrer'),
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_rounded),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: _tables.map(_tableView).toList(growable: false),
            ),
    );
  }

  Widget _tableView(String table) {
    final items = _itemsByTable[table] ?? const <Map<String, dynamic>>[];
    if (items.isEmpty) {
      return Center(child: Text(_t('لا توجد عناصر.', 'Aucun élément.')));
    }
    final searchController = _searchControllers[table]!;
    final query = searchController.text;
    final filteredItems = items
        .where((item) => _matchesSearch(table, item, query))
        .toList(growable: false);
    final isJoints = table == 'Joints';
    final groups = _groupsForTable(table);

    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        TextField(
          controller: searchController,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search_rounded),
            suffixIcon: searchController.text.isEmpty
                ? null
                : IconButton(
                    tooltip: _t('مسح البحث', 'Effacer la recherche'),
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () {
                      searchController.clear();
                      setState(() {});
                    },
                  ),
            hintText: _t(
              'بحث بالكود، الاسم، النوع أو العنوان...',
              'Rechercher code, nom, type ou rubrique...',
            ),
            border: const OutlineInputBorder(),
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 14),
        Text(
          _t(
            isJoints
                ? 'اختر عنوان الجوان ثم فعّل النوع الذي تريد تخصيصه'
                : 'اختر عنوان الإكسسوار ثم فعّل النوع الذي تريد تخصيصه',
            isJoints
                ? 'Ouvrez la rubrique des joints puis activez les articles à configurer'
                : 'Ouvrez une rubrique puis activez les articles à configurer',
          ),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        if (filteredItems.isEmpty)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              query.trim().isEmpty
                  ? _t(
                      isJoints ? 'لا توجد جوانات.' : 'لا توجد إكسسوارات.',
                      isJoints ? 'Aucun joint.' : 'Aucun accessoire.',
                    )
                  : _t('لا توجد نتائج.', 'Aucun résultat.'),
              textAlign: TextAlign.center,
            ),
          )
        else
          ...groups.map((group) {
            final groupItems = filteredItems
                .where((item) => _itemBelongsToGroup(table, item, group))
                .toList(growable: false);
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ExpansionTile(
                leading: Icon(group.icon),
                title: Text(_t(group.ar, group.fr)),
                subtitle: Text(
                  '${groupItems.length} ${_t('نوع موجود', 'article(s) disponible(s)')}',
                ),
                children: groupItems.isEmpty
                    ? [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          child: Text(
                            _t(
                              'لا توجد عناصر لهذا العنوان في قاعدة البيانات.',
                              'Aucun article de cette rubrique dans la base de données.',
                            ),
                          ),
                        ),
                      ]
                    : [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
                          child: Align(
                            alignment: AlignmentDirectional.centerStart,
                            child: Text(
                              _t(
                                'فعّل الزر لفتح تخصيص العنصر ودوره.',
                                'Activez le bouton pour ouvrir la configuration et le rôle.',
                              ),
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: groupItems
                                .map((item) => _itemToggleChip(table, item))
                                .toList(growable: false),
                          ),
                        ),
                        const SizedBox(height: 8),
                        ...groupItems
                            .where((item) => _itemRuleEnabled(table, item))
                            .map((item) => _buildRuleCard(table, item)),
                      ],
              ),
            );
          }),
      ],
    );
  }

  Widget _itemToggleChip(String table, Map<String, dynamic> item) {
    final enabled = _itemRuleEnabled(table, item);
    final itemId = _itemId(item);
    final role = itemId == null
        ? null
        : _rolesForTable(table)
              .where(
                (candidate) =>
                    candidate.key == _ruleFor(table, itemId)['role_key'],
              )
              .firstOrNull;
    return FilterChip(
      avatar: enabled
          ? const Icon(Icons.check_rounded, size: 17)
          : SectionImageWidget(
              code: item['code']?.toString(),
              name: item['name']?.toString(),
              imagePath: item['image_path']?.toString(),
              size: 24,
              fallbackIcon: Icons.inventory_2_outlined,
            ),
      label: Text(_itemTitle(item)),
      selected: enabled,
      onSelected: (value) => _toggleItem(table, item, value),
      tooltip: role == null
          ? null
          : _t('الدور: ${role.ar}', 'Rôle : ${role.fr}'),
    );
  }

  Widget _buildRuleCard(String table, Map<String, dynamic> item) {
    final itemId = _itemId(item);
    if (itemId == null) return const SizedBox.shrink();
    final rule = _ruleFor(table, itemId);
    final itemRoles = _rolesForItem(table, item);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Card(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  SectionImageWidget(
                    code: item['code']?.toString(),
                    name: item['name']?.toString(),
                    imagePath: item['image_path']?.toString(),
                    size: 56,
                    fallbackIcon: Icons.inventory_2_outlined,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _itemTitle(item),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              if (_itemSubtitle(item).isNotEmpty) ...[
                const SizedBox(height: 3),
                Text(
                  _itemSubtitle(item),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: rule['role_key']?.toString(),
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: _t('الدور / العنوان', 'Rôle / rubrique'),
                ),
                items: itemRoles
                    .map(
                      (role) => DropdownMenuItem(
                        value: role.key,
                        child: Text(_t(role.ar, role.fr)),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value == null) return;
                  setState(() => rule['role_key'] = value);
                },
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: _validUsageScope(rule['usage_scope']),
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: _t('مجال استعمال العنصر', 'Domaine d’utilisation'),
                ),
                items: [
                  DropdownMenuItem(
                    value: 'global',
                    child: Text(_t('كل الحالات', 'Tous les cas')),
                  ),
                  DropdownMenuItem(
                    value: 'opening',
                    child: Text(_t('فتح فقط', 'Ouvrant seulement')),
                  ),
                  DropdownMenuItem(
                    value: 'sliding',
                    child: Text(_t('منزلق فقط', 'Coulissant seulement')),
                  ),
                  DropdownMenuItem(
                    value: 'both',
                    child: Text(_t('فتح ومنزلق', 'Ouvrant et coulissant')),
                  ),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  setState(() => rule['usage_scope'] = value);
                },
              ),
              if (table == 'Accessories') ...[
                const SizedBox(height: 10),
                _accessoryRelationEditor(item),
              ],
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  _ruleChip(rule, 'is_default', _t('افتراضي', 'Défaut')),
                  _ruleChip(
                    rule,
                    'show_in_quantity',
                    _t('جدول الكمية', 'Quantité'),
                  ),
                  _ruleChip(
                    rule,
                    'show_in_dialog',
                    _t('نافذة التغيير', 'Choix'),
                  ),
                  _ruleChip(rule, 'show_in_drawing', _t('الرسم', 'Dessin')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _validUsageScope(dynamic value) {
    const values = {'global', 'opening', 'sliding', 'both'};
    final normalized = value?.toString().trim().toLowerCase() ?? '';
    return values.contains(normalized) ? normalized : 'global';
  }

  List<Map<String, dynamic>> _accessoriesForRoles(Set<String> roles) {
    final items = _itemsByTable['Accessories'] ?? const [];
    return items
        .where((item) => roles.contains(_groupRoleForItem('Accessories', item)))
        .toList(growable: false);
  }

  Future<void> _updateAccessoryFields(
    Map<String, dynamic> item,
    Map<String, dynamic> values,
  ) async {
    final itemId = _itemId(item);
    if (itemId == null) return;
    try {
      await widget.db.updateAccessory(itemId, values);
      if (!mounted) return;
      setState(() => item.addAll(values));
    } catch (error) {
      if (!mounted) return;
      _showError(
        '${_t('تعذر حفظ ارتباط الأكسسوار', 'Lien impossible à enregistrer')}: $error',
      );
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red.shade700),
    );
  }

  Widget _accessoryRelationEditor(Map<String, dynamic> item) {
    final screwItems = _accessoriesForRoles(const {
      'kit_screw',
      'box_screw',
      'motor_screw',
      'batmo_screw',
      'bouchon_batmo_screw',
      'renfort_screw',
      'manivelle_screw',
      'assembly_screw',
      'installation_screw',
      'accessory_screw',
    });
    final gacheItems = _accessoriesForRoles(const {
      'gache_simple',
      'gache_double',
      'gache_door',
      'sliding_lock',
    });
    final itemId = _itemId(item);
    final screwIds = screwItems
        .map(_itemId)
        .whereType<int>()
        .where((id) => id != itemId)
        .toSet();
    final gacheIds = gacheItems
        .map(_itemId)
        .whereType<int>()
        .where((id) => id != itemId)
        .toSet();
    final rawScrewId = (item['screw_accessory_id'] as num?)?.toInt();
    final rawGacheId = (item['gache_accessory_id'] as num?)?.toInt();
    final screwId = screwIds.contains(rawScrewId) ? rawScrewId : 0;
    final gacheId = gacheIds.contains(rawGacheId) ? rawGacheId : 0;

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _t('الروابط الحسابية', 'Liens de calcul'),
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          if (screwItems.isNotEmpty)
            DropdownButtonFormField<int>(
              initialValue: screwId,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: _t(
                  'الفيس المرتبط بهذا العنصر',
                  'Vis liées à cet élément',
                ),
              ),
              items: [
                DropdownMenuItem(
                  value: 0,
                  child: Text(_t('بدون فيس مرتبط', 'Aucune vis liée')),
                ),
                for (final screw in screwItems)
                  if (_itemId(screw) != itemId)
                    DropdownMenuItem(
                      value: _itemId(screw),
                      child: Text(_itemTitle(screw)),
                    ),
              ],
              onChanged: (value) => _updateAccessoryFields(item, {
                'screw_accessory_id': value == null || value == 0
                    ? null
                    : value,
              }),
            ),
          if (screwItems.isNotEmpty) ...[
            const SizedBox(height: 8),
            TextFormField(
              initialValue: '${(item['screw_count'] as num?)?.toInt() ?? 0}',
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: _t(
                  'عدد الفيس لهذا العنصر',
                  'Nombre de vis pour cet élément',
                ),
              ),
              onFieldSubmitted: (value) => _updateAccessoryFields(item, {
                'screw_count': int.tryParse(value.trim()) ?? 0,
              }),
            ),
          ],
          if (gacheItems.isNotEmpty) ...[
            const SizedBox(height: 8),
            DropdownButtonFormField<int>(
              initialValue: gacheId,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: _t(
                  'القاش المرتبط بهذا القفل/الأكسسوار',
                  'Gâche liée à cet élément',
                ),
              ),
              items: [
                DropdownMenuItem(
                  value: 0,
                  child: Text(_t('بدون قاش مرتبط', 'Aucune gâche liée')),
                ),
                for (final gache in gacheItems)
                  if (_itemId(gache) != itemId)
                    DropdownMenuItem(
                      value: _itemId(gache),
                      child: Text(_itemTitle(gache)),
                    ),
              ],
              onChanged: (value) => _updateAccessoryFields(item, {
                'gache_accessory_id': value == null || value == 0
                    ? null
                    : value,
              }),
            ),
            const SizedBox(height: 8),
            TextFormField(
              initialValue: '${(item['gache_count'] as num?)?.toInt() ?? 0}',
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: _t('عدد القاش المرتبط', 'Nombre de gâches liées'),
              ),
              onFieldSubmitted: (value) => _updateAccessoryFields(item, {
                'gache_count': int.tryParse(value.trim()) ?? 0,
              }),
            ),
          ],
        ],
      ),
    );
  }

  Widget _ruleChip(Map<String, dynamic> rule, String key, String label) {
    final selected = rule[key] == true || rule[key] == 1;
    return FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: (value) => setState(() => rule[key] = value),
    );
  }
}
