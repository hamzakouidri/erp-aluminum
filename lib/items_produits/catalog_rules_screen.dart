import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../settings/app_settings.dart';
import '../sql_database.dart';

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

class _CatalogRulesScreenState extends State<CatalogRulesScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  late final Map<String, TextEditingController> _searchControllers;

  final _tables = const ['ShutterComponents', 'Accessories', 'Joints'];
  final Map<String, List<Map<String, dynamic>>> _itemsByTable = {};
  final Map<String, Map<String, dynamic>> _rulesByItem = {};
  bool _loading = true;
  bool _saving = false;

  bool get _isArabic =>
      context.read<AppSettingsProvider>().language == AppLanguage.arabic;
  String _t(String ar, String fr) => _isArabic ? ar : fr;

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
      widget.db.readShutterComponents(),
      widget.db.readAccessories(),
      widget.db.readJoints(),
      widget.db.getCatalogItemRules(itemTable: 'ShutterComponents'),
      widget.db.getCatalogItemRules(itemTable: 'Accessories'),
      widget.db.getCatalogItemRules(itemTable: 'Joints'),
    ]);
    if (!mounted) return;
    _itemsByTable
      ..clear()
      ..addAll({
        'ShutterComponents': results[0] as List<Map<String, dynamic>>,
        'Accessories': results[1] as List<Map<String, dynamic>>,
        'Joints': results[2] as List<Map<String, dynamic>>,
      });
    _rulesByItem.clear();
    for (final tableRules in results.skip(3)) {
      for (final raw in tableRules as List<Map<String, dynamic>>) {
        final table = raw['item_table']?.toString() ?? '';
        final itemId = (raw['item_id'] as num?)?.toInt();
        if (table.isEmpty || itemId == null) continue;
        _rulesByItem[_itemKey(table, itemId)] = Map<String, dynamic>.from(raw);
      }
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
          _RuleRole('roulette', 'عجلات', 'Roulettes'),
          _RuleRole('entrematique', 'أونتروماتيك', 'Entrematique'),
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

  String _itemTitle(Map<String, dynamic> item) {
    final code = item['code']?.toString().trim() ?? '';
    final name = item['name']?.toString().trim() ?? '';
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
      if (value.isNotEmpty) parts.add(value);
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
    final tableItems = _itemsByTable[table] ?? const <Map<String, dynamic>>[];
    Map<String, dynamic>? item;
    for (final candidate in tableItems) {
      if (_itemId(candidate) == itemId) {
        item = candidate;
        break;
      }
    }
    return {
      'item_table': table,
      'item_id': itemId,
      'role_key': _guessRole(table, item),
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
      'is_active': true,
    };
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
            .where((rule) => (rule['role_key']?.toString().isNotEmpty ?? false))
            .toList();
        await widget.db.saveCatalogItemRules(itemTable: table, rules: rules);
      }
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
    if (!settings.isManager) return const Scaffold(body: SizedBox.shrink());
    return Scaffold(
      appBar: AppBar(
        title: Text(_t('قواعد الكتالوج العامة', 'Règles du catalogue')),
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(text: _t('الستار', 'Volet')),
            Tab(text: _t('الأكسسوارات', 'Accessoires')),
            Tab(text: _t('الجوانات', 'Joints')),
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
              children: _tables.map(_tableView).toList(),
            ),
    );
  }

  Widget _tableView(String table) {
    final items = _itemsByTable[table] ?? const <Map<String, dynamic>>[];
    if (items.isEmpty) {
      return Center(child: Text(_t('لا توجد عناصر.', 'Aucun élément.')));
    }
    final searchController = _searchControllers[table]!;
    final filteredItems = items
        .where((item) => _matchesSearch(table, item, searchController.text))
        .toList(growable: false);
    return ListView.separated(
      padding: const EdgeInsets.all(14),
      itemCount: filteredItems.isEmpty ? 2 : filteredItems.length + 1,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        if (index == 0) {
          return TextField(
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
                'بحث بالكود، الاسم، النوع أو الدور...',
                'Rechercher code, nom, type ou rôle...',
              ),
              border: const OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() {}),
          );
        }
        if (filteredItems.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(_t('لا توجد نتائج.', 'Aucun résultat.')),
            ),
          );
        }
        final item = filteredItems[index - 1];
        final itemId = _itemId(item);
        if (itemId == null) return const SizedBox.shrink();
        final rule = _ruleFor(table, itemId);
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _itemTitle(item),
                  style: const TextStyle(fontWeight: FontWeight.bold),
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
                  decoration: InputDecoration(labelText: _t('الدور', 'Rôle')),
                  items: _rolesForTable(table)
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
        );
      },
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
