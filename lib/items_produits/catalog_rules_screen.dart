import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/supabase_workshop_sync_service.dart';
import '../settings/app_settings.dart';
import '../settings/localization.dart';
import '../sql_database.dart';
import '../services/cloud_sync_service.dart';
import '../widgets/section_image.dart';
import '../Commande/Systeme/accessory_assembly.dart';

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
  final _tables = const ['Accessories', 'Joints', 'ShutterComponents'];
  final Map<String, List<Map<String, dynamic>>> _itemsByTable = {};
  final Map<String, Map<String, dynamic>> _rulesByItem = {};
  final Map<int, List<Map<String, dynamic>>> _accessoryLinks = {};
  final Set<int> _dirtyAccessoryLinkIds = {};
  List<Map<String, dynamic>> _assemblySections = [];
  List<Map<String, dynamic>> _profiles = [];
  List<Map<String, dynamic>> _series = [];
  Map<String, dynamic>? _selectedProfile;
  Map<String, dynamic>? _selectedSeries;
  int? _selectedSeriesId;
  bool _loadingProfiles = true;
  bool _loadingSeries = false;
  bool _loading = false;
  bool _saving = false;
  int? _loadedRulesSeriesId;
  bool get _canSaveRules => !_saving && !_loading &&
      !_loadingProfiles && !_loadingSeries &&
      _selectedSeriesId != null &&
      _loadedRulesSeriesId == _selectedSeriesId;
  bool _isInspectorOpen = false;
  String? _inspectedItemKey;

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
    _tabController = TabController(length: 2, vsync: this);
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
    setState(() => _loadingProfiles = true);
    try {
      final results = await Future.wait<dynamic>([
        widget.db.readAccessories(includeInactive: true),
        widget.db.readJoints(),
        widget.db.readProfile(),
        widget.db.readShutterComponents(),
      ]);
      final accessoryRows = results[0] as List<Map<String, dynamic>>;
      final loadedLinks = await Future.wait(
        accessoryRows.map((item) async {
          final id = (item['id'] as num?)?.toInt();
          return (
            id: id,
            links: id == null
                ? <Map<String, dynamic>>[]
                : (await widget.db.readAccessoryLinksWithDetails(id))
                      .map(
                        (link) => {
                          ...link,
                          'quantity':
                              (link['linked_quantity'] as num?)?.toInt() ?? 1,
                        },
                      )
                      .toList(),
          );
        }),
      );
      if (!mounted) return;
      _accessoryLinks
        ..clear()
        ..addEntries(
          loadedLinks
              .where((entry) => entry.id != null)
              .map((entry) => MapEntry(entry.id!, entry.links)),
        );
      _itemsByTable
        ..clear()
        ..addAll({
          'Accessories': accessoryRows
              .map((row) => Map<String, dynamic>.from(row))
              .toList(),
          'Joints': (results[1] as List<Map<String, dynamic>>)
              .map((row) => Map<String, dynamic>.from(row))
              .toList(),
        });
      _profiles = results[2] as List<Map<String, dynamic>>;
      _itemsByTable['ShutterComponents'] =
          (results[3] as List<Map<String, dynamic>>)
              .where(
                (row) => _guessRole('ShutterComponents', row) == 'shutter_kit',
              )
              .map((row) => Map<String, dynamic>.from(row))
              .toList();
      _rulesByItem.clear();
    } catch (e) {
      debugPrint('Error loading catalog items: $e');
    } finally {
      if (mounted) {
        setState(() => _loadingProfiles = false);
      }
    }
  }

  Future<void> _selectProfile(Map<String, dynamic> profile) async {
    if (_saving) return;
    setState(() {
      _loadedRulesSeriesId = null;
      _selectedProfile = profile;
      _selectedSeries = null;
      _selectedSeriesId = null;
      _series = [];
      _loadingSeries = true;
      _rulesByItem.clear();
      _inspectedItemKey = null;
    });
    final profileId = (profile['id'] as num?)?.toInt();
    final series = profileId == null
        ? <Map<String, dynamic>>[]
        : await widget.db.readSeriesByProfile(profileId);
    if (!mounted) return;
    setState(() {
      _series = series;
      _loadingSeries = false;
    });
  }

  Future<void> _selectSeries(Map<String, dynamic> series) async {
    if (_saving) return;
    final seriesId = (series['id'] as num?)?.toInt();
    if (seriesId == null) return;
    setState(() {
      _selectedSeries = series;
      _selectedSeriesId = seriesId;
      _loading = true;
      _loadedRulesSeriesId = null;
      _inspectedItemKey = null;
    });
    try {
      final results = await Future.wait([
        widget.db.getCatalogItemRules(
          itemTable: 'Accessories',
          seriesId: seriesId,
          exactSeriesOnly: true,
          includeInactive: true,
        ),
        widget.db.getCatalogItemRules(
          itemTable: 'Joints',
          seriesId: seriesId,
          exactSeriesOnly: true,
          includeInactive: true,
        ),
        widget.db.getCatalogItemRules(
          itemTable: 'ShutterComponents',
          seriesId: seriesId,
          exactSeriesOnly: true,
          includeInactive: true,
        ),
      ]);
      final database = await widget.db.db;
      final sections =
          await database?.query(
            'Sections',
            where: 'series_id = ?',
            whereArgs: [seriesId],
            orderBy: 'code',
          ) ??
          [];
      if (!mounted || _selectedSeriesId != seriesId) return;
      _rulesByItem.clear();
      for (final raw in results.expand((rows) => rows)) {
        final table = raw['item_table']?.toString() ?? '';
        final itemId = (raw['item_id'] as num?)?.toInt();
        if (table.isEmpty || itemId == null) continue;
        final rule = Map<String, dynamic>.from(raw)..['series_id'] = seriesId;
        final storedRole = rule['role_key']?.toString() ?? '';
        if (storedRole == 'sliding_clamp' || storedRole == 'clamp') {
          rule['role_key'] = 'clam';
          if (storedRole == 'sliding_clamp') rule['usage_scope'] = 'sliding';
        }
        if (table == 'Accessories' && storedRole == 'kit') {
          final item = (_itemsByTable[table] ?? const <Map<String, dynamic>>[])
              .where((candidate) => _itemId(candidate) == itemId)
              .firstOrNull;
          if (item != null && _guessRole(table, item) == 'alignment_square') {
            rule['role_key'] = 'alignment_square';
          }
        }
        final key = _itemKey(table, itemId);
        if (_rulesByItem.containsKey(key)) {
          final existing = _rulesByItem[key]!;
          final extra = (existing['extra_roles'] as Set<String>?) ?? <String>{
            if (existing['role_key']?.toString().isNotEmpty ?? false)
              existing['role_key'].toString(),
          };
          if (storedRole.isNotEmpty) extra.add(storedRole);
          existing['extra_roles'] = extra;
          if (_truthy(rule['is_active'])) existing['is_active'] = true;
        } else {
          rule['extra_roles'] = <String>{
            if (storedRole.isNotEmpty) storedRole,
          };
          _rulesByItem[key] = rule;
        }
      }
      _assemblySections = sections;
      for (final table in _tables) {
        for (final item
            in _itemsByTable[table] ?? const <Map<String, dynamic>>[]) {
          final itemId = _itemId(item);
          if (itemId != null) {
            final rule = _ruleFor(table, itemId);
            rule['series_id'] = seriesId;
            if (table == 'Accessories' && _isScrewItem(item)) {
              final extra = (rule['extra_roles'] as Set<String>?) ?? <String>{};
              if (extra.isEmpty) {
                final fromItem = _screwRolesFromItem(item);
                if (fromItem.isNotEmpty) {
                  extra.addAll(fromItem);
                  rule['extra_roles'] = extra;
                  if (rule['role_key']?.toString().isEmpty ?? true) {
                    rule['role_key'] = fromItem.first;
                  }
                  rule['is_active'] = true;
                }
              }
              rule['show_in_drawing'] = false;
              rule['show_in_quantity'] = true;
            }
          }
        }
      }
      _loadedRulesSeriesId = seriesId;
    } catch (e) {
      debugPrint('Error loading series rules: $e');
    } finally {
      if (mounted && _selectedSeriesId == seriesId) {
        setState(() => _loading = false);
      }
    }
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
          _RuleRole(
            'bouchon_montant_central_renforce',
            'غطاء قائم وسطي معزز',
            'Bouchon montant central renforcé',
          ),
          _RuleRole(
            'bouchon_montant_lateral_renforce',
            'غطاء قائم جانبي معزز',
            'Bouchon montant latéral renforcé',
          ),
          _RuleRole(
            'bouchon_renfort_rapporte',
            'غطاء عمود تدعيم مستقل',
            'Bouchon renfort rapporté',
          ),
          _RuleRole('renfort_screw', 'براغي حديد الدعم', 'Vis renfort'),
          _RuleRole('manivelle_screw', 'براغي المانيفال', 'Vis manivelle'),
          _RuleRole('assembly_screw', 'براغي التجميع', 'Vis assemblage'),
          _RuleRole('clam', 'كلام', 'Clam'),
          _RuleRole('frame_clamp', 'كلام الإطار', 'Équerre dormant'),
          _RuleRole('sash_clamp', 'كلام الظلفة', 'Équerre ouvrant'),
          _RuleRole(
            'frame_clamp_support',
            'حامل / مكمل كلام الإطار',
            'Support équerre dormant',
          ),
          _RuleRole(
            'sash_clamp_support',
            'حامل / مكمل كلام الظلفة',
            'Support équerre ouvrant',
          ),
          _RuleRole('installation_screw', 'براغي التركيب', 'Vis pose'),
          _RuleRole('accessory_screw', 'براغي الإكسسوارات', 'Vis accessoires'),
          _RuleRole('kit', 'كيت السلسلة', 'Kit de série'),
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
          _RuleRole(
            'alignment_square',
            'إيكار دالينمو',
            "Equerre d'alignement",
          ),
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
      'extra_roles': <String>{},
      'usage_scope': 'global',
      'show_when_glass': 'any',
      'selection_mode': 'always',
      'assembly_target': '',
      'assembly_section_ids': '',
      'assembly_section_quantities': '',
      'top_corner_qty': 1,
      'bottom_corner_qty': 1,
      'integrated_side_cover': false,
      'allows_side_cover': true,
      'allowed_with_shutter': true,
      'min_height_mm': null,
      'max_height_mm': null,
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
    if (!context.read<AppSettingsProvider>().isAdmin) return;
    final itemId = _itemId(item);
    if (itemId == null) return;
    final rule = _ruleFor(table, itemId);
    final key = _itemKey(table, itemId);
    setState(() {
      rule['is_active'] = enabled;
      if (enabled) {
        if (table == 'Accessories' && _isScrewItem(item)) {
          final extra = (rule['extra_roles'] as Set<String>?) ?? <String>{};
          if (extra.isEmpty) {
            final fromItem = _screwRolesFromItem(item);
            if (fromItem.isNotEmpty) {
              extra.addAll(fromItem);
            } else {
              final guessed = _guessRole(table, item);
              extra.add(_isScrewRole(guessed) ? guessed : 'accessory_screw');
            }
          }
          rule['extra_roles'] = extra;
          if (extra.isNotEmpty) {
            rule['role_key'] = extra.first;
          }
          rule['show_in_quantity'] = true;
          rule['show_in_drawing'] = false;
        } else {
          if (rule['role_key']?.toString().trim().isEmpty ?? true) {
            rule['role_key'] = _guessRole(table, item);
          }
          if (_isScrewRole(rule['role_key']?.toString() ?? '')) {
            rule['show_in_quantity'] = true;
            rule['show_in_drawing'] = false;
          }
        }
        _inspectedItemKey = key;
      } else {
        if (_inspectedItemKey == key) {
          _inspectedItemKey = null;
        }
      }
    });
  }

  List<_CatalogGroup> _groupsForTable(String table) {
    if (table == 'ShutterComponents') {
      return const [
        _CatalogGroup(
          key: 'shutter_kits',
          ar: 'كيت الفولي',
          fr: 'Kits volet',
          icon: Icons.inventory_2_outlined,
          roleKeys: {'shutter_kit'},
        ),
      ];
    }
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
    const iconGroups = [
      _CatalogGroup(
        key: 'screws',
        ar: 'براغي أخرى',
        fr: 'Autres vis',
        icon: Icons.build_outlined,
        roleKeys: {
          'kit_screw',
          'box_screw',
          'motor_screw',
          'batmo_screw',
          'renfort_screw',
          'manivelle_screw',
          'assembly_screw',
        },
      ),
      _CatalogGroup(
        key: 'accessory_screws',
        ar: 'براغي الأكسسوارات',
        fr: 'Vis accessoires',
        icon: Icons.build_outlined,
        roleKeys: {'accessory_screw'},
      ),
      _CatalogGroup(
        key: 'installation_screws',
        ar: 'براغي التركيب',
        fr: 'Vis de pose',
        icon: Icons.home_repair_service_outlined,
        roleKeys: {'installation_screw'},
      ),
      _CatalogGroup(
        key: 'bouchon_batmo_screws',
        ar: 'براغي بوشون باتمو',
        fr: 'Vis bouchon Batmo',
        icon: Icons.build_circle_outlined,
        roleKeys: {'bouchon_batmo_screw'},
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
        fr: 'Serrures',
        icon: Icons.lock_outline,
        roleKeys: {'lock_clef', 'lock_condamnation', 'canon'},
      ),
      _CatalogGroup(
        key: 'verrous',
        ar: 'الفيرو',
        fr: 'Verrous',
        icon: Icons.lock_outline,
        roleKeys: {'verrou'},
      ),
      _CatalogGroup(
        key: 'handles',
        ar: 'المقابض',
        fr: 'Poignées',
        icon: Icons.pan_tool_outlined,
        roleKeys: {'handle', 'door_handle_key', 'door_handle_condamnation'},
      ),
      _CatalogGroup(
        key: 'cremones',
        ar: 'الكريمون والإسبانيوليت',
        fr: 'Crémones et espagnolettes',
        icon: Icons.pan_tool_outlined,
        roleKeys: {'cremone', 'tringle', 'espagnolette'},
      ),
      _CatalogGroup(
        key: 'entrematique',
        ar: 'الإندراماتيك',
        fr: 'Entrematique',
        icon: Icons.pan_tool_outlined,
        roleKeys: {'entrematique'},
      ),
      _CatalogGroup(
        key: 'hinges',
        ar: 'المفصلات',
        fr: 'Paumelles',
        icon: Icons.settings_input_component_outlined,
        roleKeys: {'hinge'},
      ),
      _CatalogGroup(
        key: 'clamps',
        ar: 'الكلام وحامل الكلام',
        fr: 'Équerres et supports',
        icon: Icons.crop_square_rounded,
        roleKeys: {
          'clam',
          'clamp',
          'sliding_clamp',
          'frame_clamp',
          'sash_clamp',
          'frame_clamp_support',
          'sash_clamp_support',
        },
      ),
      _CatalogGroup(
        key: 'tasso_ekar',
        ar: 'الطاسو والإيكار',
        fr: 'Tasso et Ekar',
        icon: Icons.crop_square_rounded,
        roleKeys: {'tasso', 'ekar', 'alignment_square'},
      ),
      _CatalogGroup(
        key: 'moving',
        ar: 'العجلات والكيت',
        fr: 'Roulettes et kits',
        icon: Icons.circle_outlined,
        roleKeys: {
          'roulette',
          'kit',
          'sliding_kit',
          'sliding_kit_40000',
          'sliding_kit_67000',
        },
      ),
      _CatalogGroup(
        key: 'batmo',
        ar: 'بوشون باتمو',
        fr: 'Bouchon battement',
        icon: Icons.extension_outlined,
        roleKeys: {'bouchon_batmo'},
      ),
      _CatalogGroup(
        key: 'bouchons_montants_renforces',
        ar: 'أغطية أعمدة الدعم',
        fr: 'Bouchons montants renforcés',
        icon: Icons.shield_outlined,
        roleKeys: {
          'bouchon_montant_central_renforce',
          'bouchon_montant_lateral_renforce',
          'bouchon_renfort_rapporte',
        },
      ),
      _CatalogGroup(
        key: 'other',
        ar: 'أكسسوارات أخرى',
        fr: 'Autres accessoires',
        icon: Icons.extension_outlined,
        roleKeys: {'other'},
      ),
    ];
    if (table == 'Accessories') {
      return iconGroups;
    }
    return _rolesForTable(table)
        .map((role) {
          final iconGroup = iconGroups
              .where((group) => group.roleKeys.contains(role.key))
              .firstOrNull;
          return _CatalogGroup(
            key: role.key,
            ar: role.ar,
            fr: role.fr,
            icon: iconGroup?.icon ?? Icons.extension_outlined,
            roleKeys: {role.key},
          );
        })
        .toList(growable: false);
  }

  String _groupRoleForItem(String table, Map<String, dynamic> item) {
    if (table == 'Accessories') {
      final classifiedRole = _guessRole(table, item);
      if (const {
        'accessory_screw',
        'installation_screw',
        'bouchon_batmo_screw',
      }.contains(classifiedRole)) {
        return classifiedRole;
      }
    }
    final itemId = _itemId(item);
    final savedRole = itemId == null
        ? null
        : _rulesByItem[_itemKey(table, itemId)]?['role_key']?.toString();
    if (savedRole != null &&
        _rolesForTable(table).any((role) => role.key == savedRole)) {
      return savedRole;
    }
    final guessed = _guessRole(table, item);
    if (table == 'Accessories' && guessed == 'other' && _isScrewItem(item)) {
      return 'accessory_screw';
    }
    return guessed;
  }

  static const _screwRoles = {
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
  };

  bool _isScrewRole(String role) =>
      _screwRoles.contains(role.trim().toLowerCase());

  Set<String> _screwRolesFromItem(Map<String, dynamic> item) {
    return {
      if (_truthy(item['is_batmo_screw'])) 'batmo_screw',
      if (_truthy(item['is_bouchon_batmo_screw'])) 'bouchon_batmo_screw',
      if (_truthy(item['is_kit_screw'])) 'kit_screw',
      if (_truthy(item['is_caisson_screw'])) 'box_screw',
      if (_truthy(item['is_moteur_screw'])) 'motor_screw',
      if (_truthy(item['is_renfort_screw'])) 'renfort_screw',
      if (_truthy(item['is_manivelle_screw'])) 'manivelle_screw',
      if (_truthy(item['is_assembly_screw'])) 'assembly_screw',
      if (_truthy(item['is_installation_screw'])) 'installation_screw',
      if (_truthy(item['is_accessory_screw'])) 'accessory_screw',
    };
  }

  bool _isScrewItem(Map<String, dynamic> item) {
    final text = '${item['name'] ?? ''} ${item['type'] ?? ''}'.toLowerCase();
    return _textLooksLikeScrew(text) ||
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

  bool _textLooksLikeScrew(String text) {
    final normalized = _foldSearchText(text);
    return normalized.contains('vis') ||
        normalized.contains('screw') ||
        normalized.contains('برغ') ||
        // «فيس» is the common local spelling of the French word
        // «vis». Catalogue rows often use it in names such as
        // «فيس بوشون باتمو» and «فيس الاكسسوار».
        normalized.contains('فيس');
  }

  bool _itemBelongsToGroup(
    String table,
    Map<String, dynamic> item,
    _CatalogGroup group,
  ) {
    if (table == 'Accessories') {
      final itemId = _itemId(item);
      final rule =
          itemId != null ? _rulesByItem[_itemKey(table, itemId)] : null;
      final extraRoles =
          (rule?['extra_roles'] as Set<String>?) ?? <String>{};
      final mainRole = rule?['role_key']?.toString() ?? '';
      final activeRoles = <String>{
        if (mainRole.isNotEmpty) mainRole,
        ...extraRoles,
        ..._screwRolesFromItem(item),
      };
      if (activeRoles.any(group.roleKeys.contains)) {
        return true;
      }
      if (_isScrewItem(item) && group.roleKeys.any(_isScrewRole)) {
        return true;
      }
    }
    return group.roleKeys.contains(_groupRoleForItem(table, item));
  }

  List<_RuleRole> _rolesForItem(String table, Map<String, dynamic> item) {
    // A catalogue name/type is only a suggestion. Administrators can bind
    // any accessory to its actual construction role.
    if (table == 'Accessories') return _rolesForTable(table);
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
      final isScrew = _textLooksLikeScrew(text);
      if (flag('is_kit_screw')) return 'kit_screw';
      if (flag('is_caisson_screw')) return 'box_screw';
      if (flag('is_moteur_screw')) return 'motor_screw';
      if (flag('is_batmo_screw')) return 'batmo_screw';
      if (flag('is_bouchon_batmo_screw')) return 'bouchon_batmo_screw';
      if (flag('is_renfort_screw')) return 'renfort_screw';
      if (flag('is_manivelle_screw')) return 'manivelle_screw';
      if (flag('is_assembly_screw')) return 'assembly_screw';
      final looksLikeInstallationScrew =
          text.contains('montage') ||
          text.contains('installation') ||
          text.contains('pose') ||
          text.contains('تركيب') ||
          text.contains('تثبيت');
      if (looksLikeInstallationScrew && isScrew) {
        return 'installation_screw';
      }
      final looksLikeAssemblyRequirement =
          text.contains('تجميع') ||
          text.contains('assembl') ||
          text.contains('assembly');
      if (looksLikeAssemblyRequirement &&
          (isScrew ||
              text.contains('احتياج') ||
              text.contains('besoin') ||
              text.contains('requirement'))) {
        return 'assembly_screw';
      }
      if (flag('is_installation_screw')) return 'installation_screw';
      if (flag('is_accessory_screw')) return 'accessory_screw';
      // Legacy screw rows stored the usage in the composite type (for
      // example `...|التجميع`) without setting the dedicated boolean flag.
      if (isScrew &&
          (text.contains('التجميع') ||
              text.contains('assemblage') ||
              text.contains('assembly'))) {
        return 'assembly_screw';
      }
      if (flag('is_gache_simple')) return 'gache_simple';
      if (flag('is_gache_double')) return 'gache_double';
      if (flag('is_gache_porte')) return 'gache_door';
      if (flag('is_lock_clef')) return 'lock_clef';
      if (flag('is_lock_condamnation')) return 'lock_condamnation';
      if (text.contains('kit') && isScrew) {
        return 'kit_screw';
      }
      if (isBouchonBatmo && isScrew) return 'bouchon_batmo_screw';
      if (isBouchonBatmo) return 'bouchon_batmo';
      final isBouchonRenforce =
          (text.contains('bouchon') ||
              text.contains('bochon') ||
              text.contains('غطاء') ||
              text.contains('أغطية') ||
              text.contains('بوشون')) &&
          (text.contains('renforce') ||
              text.contains('renforcé') ||
              text.contains('معزز') ||
              text.contains('renfort') ||
              text.contains('تدعيم'));
      if (isBouchonRenforce) {
        if (text.contains('lateral') ||
            text.contains('latéral') ||
            text.contains('جانبي')) {
          return 'bouchon_montant_lateral_renforce';
        }
        if (text.contains('rapporte') ||
            text.contains('rapporté') ||
            text.contains('مستقل')) {
          return 'bouchon_renfort_rapporte';
        }
        return 'bouchon_montant_central_renforce';
      }
      if ((text.contains('caisson') || text.contains('صندوق')) && isScrew) {
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
      if (text.contains('kit') || text.contains('كيت')) return 'kit';
      if (text.contains('clam') || text.contains('كلام')) return 'clam';
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
      if (text.contains('alignement') ||
          text.contains('alignment') ||
          text.contains('ekd') ||
          text.contains('دالينمو') ||
          text.contains('دالينيمو')) {
        return 'alignment_square';
      }
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
          text.contains('الإندراماتيك') ||
          text.contains('اندراماتيك') ||
          text.contains('أونتروماتيك') ||
          text.contains('انتراميتيك') ||
          text.contains('intra')) {
        return 'entrematique';
      }
      // Any screw without a more specific purpose belongs to the generic
      // accessory-screw rule. This also covers legacy rows whose dedicated
      // is_accessory_screw flag was never populated.
      if (isScrew) return 'accessory_screw';
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
    if (!context.read<AppSettingsProvider>().isAdmin) return;
    final seriesId = _selectedSeriesId;
    if (!_canSaveRules || seriesId == null) return;
    setState(() => _saving = true);
    try {
      for (final table in _tables) {
        final rulesToSave = <Map<String, dynamic>>[];
        for (final entry in _rulesByItem.entries.where(
          (e) => e.key.startsWith('$table:'),
        )) {
          final rule = entry.value;
          if (!_truthy(rule['is_active'])) continue;
          final itemId = (rule['item_id'] as num?)?.toInt();
          if (itemId == null) continue;

          final extraRoles =
              (rule['extra_roles'] as Set<String>?) ?? <String>{};
          final mainRole = rule['role_key']?.toString().trim() ?? '';
          final allRoles = <String>{
            if (mainRole.isNotEmpty) mainRole,
            ...extraRoles,
          };

          final item = (_itemsByTable[table] ?? const <Map<String, dynamic>>[])
              .where((c) => _itemId(c) == itemId)
              .firstOrNull;

          if (table == 'Accessories' &&
              (item != null && _isScrewItem(item) ||
                  allRoles.any(_isScrewRole))) {
            for (final r in allRoles) {
              final rRule = Map<String, dynamic>.from(rule);
              rRule['role_key'] = r;
              rRule['show_in_drawing'] = 0;
              rRule['show_in_quantity'] = 1;
              rulesToSave.add(rRule);
            }
            if (item != null) {
              await widget.db.updateAccessory(itemId, {
                'is_batmo_screw': allRoles.contains('batmo_screw') ? 1 : 0,
                'is_bouchon_batmo_screw':
                    allRoles.contains('bouchon_batmo_screw') ? 1 : 0,
                'is_kit_screw': allRoles.contains('kit_screw') ? 1 : 0,
                'is_caisson_screw': allRoles.contains('box_screw') ? 1 : 0,
                'is_moteur_screw': allRoles.contains('motor_screw') ? 1 : 0,
                'is_renfort_screw': allRoles.contains('renfort_screw') ? 1 : 0,
                'is_manivelle_screw':
                    allRoles.contains('manivelle_screw') ? 1 : 0,
                'is_assembly_screw':
                    allRoles.contains('assembly_screw') ? 1 : 0,
                'is_installation_screw':
                    allRoles.contains('installation_screw') ? 1 : 0,
                'is_accessory_screw':
                    allRoles.contains('accessory_screw') ? 1 : 0,
              });
            }
          } else {
            if (mainRole.isNotEmpty) {
              rulesToSave.add(rule);
            }
          }
        }
        await widget.db.saveCatalogItemRules(
          itemTable: table,
          seriesId: seriesId,
          rules: rulesToSave,
          syncCatalog: false,
        );
      }
      // Save only links changed during this edit. Saving every accessory link
      // made the button execute hundreds of transactions and appear stuck.
      for (final sourceId in _dirtyAccessoryLinkIds.toList()) {
        await _saveAccessoryLinksFor(sourceId, syncCatalog: false);
      }
      // رفع قواعد الورشة فوراً للسحابة لتصل لكل هواتف العمال
      () async {
        try {
          final sync = SupabaseWorkshopSyncService();
          if (sync.isReady || await sync.ensureStarted()) {
            final config = await widget.db.exportWorkshopCatalogConfiguration();
            if (config.isNotEmpty) {
              await sync.saveWorkshopCatalogConfiguration(config);
            }
          }
        } catch (e) {
          debugPrint('Error uploading workshop catalog configuration: $e');
        }
      }();
      unawaited(CloudSyncService().notifyCatalogChange());
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(
            content: Text(
              _t('تم حفظ قواعد السلسلة.', 'Règles de la série enregistrées.'),
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
    context.watch<AppSettingsProvider>(); // rebuild on settings change
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
          if (context.watch<AppSettingsProvider>().isAdmin)
          IconButton(
            tooltip: _t('حفظ', 'Enregistrer'),
            onPressed: _canSaveRules ? _save : null,
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
      body: _loadingProfiles
          ? const Center(child: CircularProgressIndicator())
          : _selectedSeriesId == null && _profiles.isEmpty
          ? _emptyState()
          : TabBarView(
              controller: _tabController,
              children: [
                DefaultTabController(
                  length: 2,
                  child: Column(
                    children: [
                      TabBar(
                        tabs: [
                          Tab(text: _t('الأكسسوارات', 'Accessoires')),
                          Tab(text: _t('كيت الفولي', 'Kits volet')),
                        ],
                      ),
                      Expanded(
                        child: TabBarView(
                          children: [
                            _tableView('Accessories'),
                            _tableView('ShutterComponents'),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                _tableView('Joints'),
              ],
            ),
      floatingActionButton: (_selectedSeriesId == null ||
              !context.watch<AppSettingsProvider>().isAdmin)
          ? null
          : FloatingActionButton.extended(
              onPressed: _canSaveRules ? _save : null,
              icon: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.save_rounded),
              label: Text(_t('حفظ القواعد', 'Enregistrer les règles')),
            ),
    );
  }

  Widget _profileSelector() => Container(
    color: Theme.of(context).colorScheme.primaryContainer,
    padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _t('1. اختر النظام (البروفيل)', '1. Choisissez le profil'),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 42,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _profiles.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (_, index) {
              final profile = _profiles[index];
              final isSelected = profile['id'] == _selectedProfile?['id'];
              return ChoiceChip(
                label: Text(profile['name']?.toString() ?? ''),
                selected: isSelected,
                onSelected: (_) => _selectProfile(profile),
              );
            },
          ),
        ),
      ],
    ),
  );

  Widget _seriesSelector() => Container(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
    child: _loadingSeries
        ? const LinearProgressIndicator()
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _t('2. اختر السلسلة', '2. Choisissez la série'),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              if (_series.isEmpty)
                Text(
                  _t(
                    'لا توجد سلاسل في هذا النظام.',
                    'Ce profil ne contient aucune série.',
                  ),
                )
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: _series.map((s) {
                    final id = (s['id'] as num?)?.toInt();
                    final selected = id == _selectedSeriesId;
                    return ChoiceChip(
                      label: Text(s['name']?.toString() ?? ''),
                      selected: selected,
                      onSelected: (_) => _selectSeries(s),
                    );
                  }).toList(),
                ),
            ],
          ),
  );

  Widget _emptyState() => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.account_tree_outlined,
            size: 64,
            color: Theme.of(context).colorScheme.outline,
          ),
          const SizedBox(height: 16),
          Text(
            _selectedProfile == null
                ? _t(
                    'اختر النظام ثم السلسلة بالأعلى لتحديد قواعد الأكسسوارات والجوانات.',
                    'Choisissez un profil puis une série en haut pour configurer les règles.',
                  )
                : _t(
                    'اختر السلسلة لتحديد قواعد الأكسسوارات والجوانات التابعة لها.',
                    'Choisissez une série pour configurer les accessoires et joints associés.',
                  ),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    ),
  );

  Widget _informationCard({
    required IconData icon,
    required String title,
    required String text,
  }) => Card(
    color: Theme.of(
      context,
    ).colorScheme.secondaryContainer.withValues(alpha: 0.7),
    margin: const EdgeInsets.only(bottom: 12),
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 3),
                Text(text, style: const TextStyle(fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    ),
  );

  Widget _tableView(String table) {
    final items = _itemsByTable[table] ?? const <Map<String, dynamic>>[];
    if (items.isEmpty) {
      return Center(child: Text(_t('لا توجد عناصر.', 'Aucun élément.')));
    }
    final searchController = _searchControllers[table]!;
    final query = searchController.text;
    final matchingItems = items
        .where((item) => _matchesSearch(table, item, query))
        .toList(growable: false);
    final filteredItems = [
      ...matchingItems.where((item) => _itemRuleEnabled(table, item)),
      ...matchingItems.where((item) => !_itemRuleEnabled(table, item)),
    ];
    final isJoints = table == 'Joints';
    final originalGroups = _groupsForTable(table);
    final enabledRoles = items
        .where((item) => _itemRuleEnabled(table, item))
        .map((item) => _groupRoleForItem(table, item))
        .toSet();
    bool groupEnabled(_CatalogGroup group) =>
        group.roleKeys.any(enabledRoles.contains);
    final groups = [
      ...originalGroups.where(groupEnabled),
      ...originalGroups.where((group) => !groupEnabled(group)),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWideScreen = constraints.maxWidth >= 900;

        // Find currently inspected item if any
        Map<String, dynamic>? inspectedItem;
        if (_inspectedItemKey != null &&
            _inspectedItemKey!.startsWith('$table:')) {
          final parts = _inspectedItemKey!.split(':');
          final id = int.tryParse(parts.last);
          if (id != null) {
            inspectedItem = items.where((it) => _itemId(it) == id).firstOrNull;
          }
        }
        if (inspectedItem == null && isWideScreen) {
          inspectedItem = items
              .where((it) => _itemRuleEnabled(table, it))
              .firstOrNull;
          if (inspectedItem != null) {
            final id = _itemId(inspectedItem);
            if (id != null) _inspectedItemKey = _itemKey(table, id);
          }
        }

        List<Widget> ruleStatusSection({required bool enabled}) {
          final statusItems = filteredItems
              .where((item) => _itemRuleEnabled(table, item) == enabled)
              .toList(growable: false);
          final colorScheme = Theme.of(context).colorScheme;
          final sectionColor = enabled
              ? colorScheme.primaryContainer
              : colorScheme.surfaceContainerHighest;
          final sectionIcon = enabled
              ? Icons.check_circle_outline_rounded
              : Icons.pause_circle_outline_rounded;
          final widgets = <Widget>[
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(top: 8, bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              decoration: BoxDecoration(
                color: sectionColor,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Icon(sectionIcon, size: 21),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _t(
                        enabled ? 'القواعد المفعلة' : 'القواعد غير المفعلة',
                        enabled ? 'Règles activées' : 'Règles désactivées',
                      ),
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                  Text('${statusItems.length}'),
                ],
              ),
            ),
          ];
          if (statusItems.isEmpty) {
            widgets.add(
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 4, 14, 12),
                child: Text(
                  _t(
                    enabled
                        ? 'لا توجد قواعد مفعلة لهذه السلسلة.'
                        : 'لا توجد قواعد غير مفعلة.',
                    enabled
                        ? 'Aucune règle activée pour cette série.'
                        : 'Aucune règle désactivée.',
                  ),
                ),
              ),
            );
            return widgets;
          }
          for (final group in groups) {
            final groupItems = statusItems
                .where((item) => _itemBelongsToGroup(table, item, group))
                .toList(growable: false);
            if (groupItems.isEmpty) continue;
            widgets.add(
              Card(
                key: ValueKey(
                  'catalog-group:$_selectedSeriesId:$table:${group.key}:$enabled',
                ),
                margin: const EdgeInsets.only(bottom: 8),
                child: ExpansionTile(
                  key: ValueKey(
                    'role-group:$_selectedSeriesId:$table:${group.key}:$enabled',
                  ),
                  initiallyExpanded: enabled,
                  leading: Icon(group.icon),
                  title: Text(_t(group.ar, group.fr)),
                  subtitle: Text(
                    '${groupItems.length} ${_t('عنصر', 'article(s)')}',
                  ),
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: groupItems
                            .map(
                              (item) =>
                                  _itemToggleChip(table, item, isWideScreen),
                            )
                            .toList(growable: false),
                      ),
                    ),
                    if (enabled) ...[
                      const Divider(height: 1),
                      ...groupItems.map(
                        (item) => _activeItemTile(table, item, isWideScreen),
                      ),
                    ],
                  ],
                ),
              ),
            );
          }
          return widgets;
        }

        final masterList = ListView(
          padding: const EdgeInsets.all(14),
          children: [
            // اختيار النظام والسلسلة — يتمرران مع القائمة للأعلى
            _profileSelector(),
            if (_selectedProfile != null) _seriesSelector(),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_selectedSeriesId == null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: _emptyState(),
              )
            else ...[
              _informationCard(
                icon: isJoints
                    ? Icons.linear_scale_outlined
                    : Icons.extension_outlined,
                title:
                    '${_t(isJoints ? 'قواعد الجوانات للسلسلة' : 'قواعد الأكسسوارات للسلسلة', isJoints ? 'Règles des joints de la série' : 'Règles des accessoires de la série')}${_selectedSeries?['name'] != null ? ' — ${_selectedSeries!['name']}' : ''}',
                text: _t(
                  isJoints
                      ? 'فعّل الجوانات التي تستعملها هذه السلسلة وحدد أدوارها (جوان فيتراج، فراب، بروس...).'
                      : 'فعّل الملحقات التي تستعملها هذه السلسلة (براغي، كلام، أقفال، مقابض...) واضبط قواعد تركيبها وكمياتها.',
                  isJoints
                      ? 'Activez les joints utilisés par cette série et configurez leurs rôles.'
                      : 'Activez les accessoires utilisés par cette série et configurez leurs règles.',
                ),
              ),
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
                  isDense: true,
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 12),
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
              else ...[
                ...ruleStatusSection(enabled: true),
                const SizedBox(height: 8),
                ...ruleStatusSection(enabled: false),
              ],
              const SizedBox(height: 80),
            ],
          ],
        );

        if (!isWideScreen) {
          return masterList;
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 6, child: masterList),
            const VerticalDivider(width: 1),
            Expanded(
              flex: 4,
              child: inspectedItem != null
                  ? SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: _buildItemInspector(
                        table,
                        inspectedItem,
                        readOnly: !context.watch<AppSettingsProvider>().isAdmin,
                      ),
                    )
                  : Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.tune_rounded,
                              size: 48,
                              color: Theme.of(context).colorScheme.outline,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              _t(
                                'اختر ملحقاً أو قُم بتفعيله لتعديل خصائصه وقواعده هنا.',
                                'Sélectionnez un article actif pour modifier ses règles ici.',
                              ),
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _activeItemTile(
    String table,
    Map<String, dynamic> item,
    bool isWideScreen,
  ) {
    final itemId = _itemId(item);
    if (itemId == null) return const SizedBox.shrink();
    final rule = _ruleFor(table, itemId);
    final key = _itemKey(table, itemId);
    final isInspected = _inspectedItemKey == key;
    final roleKey = rule['role_key']?.toString() ?? '';
    final role = _rolesForTable(
      table,
    ).where((r) => r.key == roleKey).firstOrNull;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: isInspected && isWideScreen
            ? Theme.of(
                context,
              ).colorScheme.primaryContainer.withValues(alpha: 0.3)
            : Theme.of(
                context,
              ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isInspected && isWideScreen
              ? Theme.of(context).colorScheme.primary
              : Theme.of(
                  context,
                ).colorScheme.outlineVariant.withValues(alpha: 0.5),
          width: isInspected && isWideScreen ? 1.5 : 1.0,
        ),
      ),
      child: ListTile(
        dense: true,
        leading: SectionImageWidget(
          code: item['code']?.toString(),
          name: item['name']?.toString(),
          imagePath: item['image_path']?.toString(),
          size: 38,
          fallbackIcon: Icons.inventory_2_outlined,
        ),
        title: Text(
          _itemTitle(item),
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
        ),
        subtitle: Builder(
          builder: (context) {
            final extra =
                (rule['extra_roles'] as Set<String>?) ?? <String>{};
            final allRoleKeys = <String>{
              if (rule['role_key']?.toString().isNotEmpty ?? false)
                rule['role_key'].toString(),
              ...extra,
            };
            if (allRoleKeys.length > 1) {
              final labels = allRoleKeys
                  .map((k) {
                    final r = _rolesForTable(table)
                        .where((cand) => cand.key == k)
                        .firstOrNull;
                    return r != null ? _t(r.ar, r.fr) : k;
                  })
                  .join(' • ');
              return Text(
                '${_t('الأدوار:', 'Rôles :')} $labels',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.primary,
                ),
              );
            }
            return Text(
              role != null
                  ? '${_t('الدور:', 'Rôle :')} ${_t(role.ar, role.fr)}'
                  : _t('الدور غير محدد', 'Rôle non défini'),
              style: TextStyle(
                fontSize: 12,
                color: role != null
                    ? Theme.of(context).colorScheme.primary
                    : Colors.orange.shade700,
              ),
            );
          },
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: Icon(
                isWideScreen ? Icons.chevron_right_rounded : Icons.tune_rounded,
                color: Theme.of(context).colorScheme.primary,
              ),
              tooltip: _t('تعديل القواعد', 'Modifier les règles'),
              onPressed: () {
                setState(() => _inspectedItemKey = key);
                if (!isWideScreen) {
                  _openMobileInspector(table, item);
                }
              },
            ),
            if (context.read<AppSettingsProvider>().isAdmin)
            IconButton(
              icon: const Icon(Icons.close_rounded, size: 18),
              tooltip: _t('تعطيل من هذه السلسلة', 'Désactiver'),
              onPressed: () => _toggleItem(table, item, false),
            ),
          ],
        ),
        onTap: () {
          setState(() => _inspectedItemKey = key);
          if (!isWideScreen) {
            _openMobileInspector(table, item);
          }
        },
      ),
    );
  }

  Widget _itemToggleChip(
    String table,
    Map<String, dynamic> item, [
    bool isWideScreen = false,
  ]) {
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
      onSelected: context.read<AppSettingsProvider>().isAdmin
          ? (value) {
              _toggleItem(table, item, value);
              if (value && !isWideScreen) {
                _openMobileInspector(table, item);
              }
            }
          : null,
      tooltip: role == null
          ? null
          : _t('الدور: ${role.ar}', 'Rôle : ${role.fr}'),
    );
  }

  Widget _assemblyRuleEditor(Map<String, dynamic> rule, {bool readOnly = false}) {
    final role = rule['role_key'].toString();
    final isClamp = const {
      'clam',
      'clamp',
      'sliding_clamp',
      'frame_clamp',
      'sash_clamp',
      'frame_clamp_support',
      'sash_clamp_support',
    }.contains(role.trim().toLowerCase());
    final defaultTarget = defaultAssemblyTarget(role);
    final target =
        const {'frame', 'sash', 'both'}.contains(rule['assembly_target'])
        ? rule['assembly_target'].toString()
        : defaultTarget;
    final selectedSectionIds = assemblySectionIds(rule);
    final sectionSideQuantities = assemblySectionSideQuantities(rule);
    void saveSectionQuantities(Map<int, (int, int)> values) {
      final ids = values.keys.toList()..sort();
      rule['assembly_section_quantities'] = ids
          .map((id) => '$id:${values[id]!.$1}:${values[id]!.$2}')
          .join(',');
    }

    return Column(
      children: [
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          initialValue: target,
          decoration: InputDecoration(
            labelText: _t('يُركّب على', 'Assemblage de'),
          ),
          items: [
            DropdownMenuItem(
              value: 'frame',
              child: Text(_t('الإطار', 'Dormant')),
            ),
            DropdownMenuItem(
              value: 'sash',
              child: Text(_t('الظلفة', 'Ouvrant')),
            ),
            DropdownMenuItem(
              value: 'both',
              child: Text(_t('الإطار والظلفة', 'Dormant et ouvrant')),
            ),
          ],
          onChanged: readOnly ? null : (value) => setState(() => rule['assembly_target'] = value),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: Text(
            _t(
              'القطاعات المرتبطة (يمكن اختيار أكثر من قطاع)',
              'Profils associés (sélection multiple)',
            ),
          ),
        ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: _assemblySections.map((section) {
            final id = (section['id'] as num).toInt();
            return FilterChip(
              label: Text(
                '${section['code'] ?? ''} — ${section['name'] ?? ''}',
              ),
              selected: selectedSectionIds.contains(id),
              onSelected: readOnly ? null : (selected) => setState(() {
                final next = {...selectedSectionIds};
                selected ? next.add(id) : next.remove(id);
                final nextQuantities = {...assemblySectionSideQuantities(rule)};
                if (selected) {
                  nextQuantities.putIfAbsent(id, () => (1, 1));
                } else {
                  nextQuantities.remove(id);
                }
                saveSectionQuantities(nextQuantities);
                final sorted = next.toList()..sort();
                rule['assembly_section_ids'] = sorted.join(',');
                // Keep old databases/readers compatible when exactly one
                // profile is linked. The CSV field remains authoritative.
                rule['assembly_section_id'] = sorted.length == 1
                    ? sorted.first
                    : null;
              }),
            );
          }).toList(),
        ),
        const SizedBox(height: 8),
        for (final section in _assemblySections.where(
          (candidate) =>
              selectedSectionIds.contains((candidate['id'] as num).toInt()),
        ))
          Row(
            key: ValueKey('${rule['item_id']}:section:${section['id']}'),
            children: [
              for (final side in (isClamp ? const [0] : const [0, 1])) ...[
                if (side == 1) const SizedBox(width: 8),
                Expanded(
                  child: TextFormField(
                    initialValue:
                        '${side == 0 ? sectionSideQuantities[(section['id'] as num).toInt()]?.$1 ?? 1 : sectionSideQuantities[(section['id'] as num).toInt()]?.$2 ?? 1}',
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: _t(
                        isClamp
                            ? 'عدد الكلام في كل زاوية للقطاع ${section['code'] ?? ''}'
                            : 'براغي الجهة ${side + 1} للقطاع ${section['code'] ?? ''}',
                        isClamp
                            ? 'Clam par angle du profilé ${section['code'] ?? ''}'
                            : 'Vis côté ${side + 1} du profilé ${section['code'] ?? ''}',
                      ),
                    ),
                    onChanged: readOnly
                        ? null
                        : (value) {
                            final count = int.tryParse(value);
                            if (count != null && count >= 0) {
                              final id = (section['id'] as num).toInt();
                              final next = {...assemblySectionSideQuantities(rule)};
                              final current = next[id] ?? (1, 1);
                              next[id] = isClamp
                                  ? (count, count)
                                  : side == 0
                                  ? (count, current.$2)
                                  : (current.$1, count);
                              saveSectionQuantities(next);
                            }
                          },
                  ),
                ),
              ],
            ],
          ),
        Text(
          _t(
            isClamp
                ? 'يُضرب العدد في عدد الزوايا الفعلية: أربع زوايا لكل إطار أو ظلفة مغلقة.'
                : 'تُضرب كمية كل جهة في عدد قطع القطاع الموجودة فعليًا في الرسم.',
            isClamp
                ? 'La quantité est multipliée par les angles réels : quatre angles par dormant ou ouvrant fermé.'
                : 'La quantité de chaque côté est multipliée par le nombre réel de pièces du profilé dans le dessin.',
          ),
        ),
      ],
    );
  }

  Widget _buildItemInspector(
    String table,
    Map<String, dynamic> item, {
    VoidCallback? onClose,
    bool readOnly = false,
  }) {
    final itemId = _itemId(item);
    if (itemId == null) return const SizedBox.shrink();
    final rule = _ruleFor(table, itemId);
    final itemRolesByKey = <String, _RuleRole>{};
    for (final role in _rolesForItem(table, item)) {
      itemRolesByKey.putIfAbsent(role.key, () => role);
    }
    final itemRoles = itemRolesByKey.values.toList(growable: false);
    final storedRole = rule['role_key']?.toString();
    final selectedRole = itemRoles.any((role) => role.key == storedRole)
        ? storedRole
        : null;
    final isEspagnoletteRule =
        table == 'Accessories' && selectedRole == 'espagnolette';
    final isAssemblyScrewRule =
        table == 'Accessories' && selectedRole == 'assembly_screw';
    final isScrew = table == 'Accessories' &&
        (_isScrewItem(item) ||
            _isScrewRole(storedRole ?? '') ||
            ((rule['extra_roles'] as Set<String>?)?.isNotEmpty ?? false));

    return Card(
      key: ValueKey('inspector:$_selectedSeriesId:$table:$itemId'),
      elevation: 0,
      color: Theme.of(
        context,
      ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                SectionImageWidget(
                  code: item['code']?.toString(),
                  name: item['name']?.toString(),
                  imagePath: item['image_path']?.toString(),
                  size: 56,
                  fallbackIcon: Icons.inventory_2_outlined,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _itemTitle(item),
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                      if (_itemSubtitle(item).isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          _itemSubtitle(item),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ],
                  ),
                ),
                if (onClose != null)
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: onClose,
                  ),
              ],
            ),
            const Divider(height: 24),
            if (isScrew) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.withAlpha(20),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.blue.shade300),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.build_circle_outlined,
                          size: 20,
                          color: Colors.blue.shade700,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _t(
                              'أدوار هذا البرغي (يمكن اختيار عدة أدوار)',
                              'Rôles de cette vis (choix multiple)',
                            ),
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              color: Colors.blue.shade900,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _t(
                        'يمكن للبرغي أن يؤدي عدة أدوار معاً (باتمو، صندوق، كيت...). وسيتم دمج أعداده تلقائياً في الكميات المطلوبة.',
                        'Cette vis peut avoir plusieurs rôles (batmo, caisson, kit...). Ses quantités seront combinées automatiquement.',
                      ),
                      style:
                          TextStyle(fontSize: 11, color: Colors.grey.shade700),
                    ),
                    const SizedBox(height: 10),
                    Builder(
                      builder: (context) {
                        final extra = (rule['extra_roles'] as Set<String>?) ??
                            <String>{
                              if (rule['role_key']?.toString().isNotEmpty ??
                                  false)
                                rule['role_key'].toString(),
                            };
                        final screwRoleList = itemRoles
                            .where((r) => _isScrewRole(r.key))
                            .toList();
                        return Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: screwRoleList.map((role) {
                            final isSelected = extra.contains(role.key);
                            return FilterChip(
                              avatar: isSelected
                                  ? const Icon(Icons.check, size: 16)
                                  : null,
                              label: Text(_t(role.ar, role.fr)),
                              selected: isSelected,
                              onSelected: readOnly
                                  ? null
                                  : (selected) {
                                      setState(() {
                                        if (selected) {
                                          extra.add(role.key);
                                          rule['is_active'] = true;
                                        } else {
                                          extra.remove(role.key);
                                          if (extra.isEmpty) {
                                            rule['is_active'] = false;
                                          }
                                        }
                                        rule['extra_roles'] = extra;
                                        if (extra.isNotEmpty) {
                                          rule['role_key'] = extra.first;
                                        } else {
                                          rule['role_key'] = '';
                                        }
                                        rule['show_in_drawing'] = false;
                                        rule['show_in_quantity'] = true;
                                      });
                                    },
                              selectedColor: Colors.blue.shade100,
                              checkmarkColor: Colors.blue.shade800,
                            );
                          }).toList(),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ] else ...[
              DropdownButtonFormField<String>(
                key: ValueKey('role-select:$itemId:$selectedRole'),
                initialValue: selectedRole,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: _t('الدور / العنوان', 'Rôle / rubrique'),
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
                items: itemRoles
                    .map(
                      (role) => DropdownMenuItem(
                        value: role.key,
                        child: Text(_t(role.ar, role.fr)),
                      ),
                    )
                    .toList(),
                onChanged: readOnly
                    ? null
                    : (value) {
                        if (value == null) return;
                        setState(() => rule['role_key'] = value);
                      },
              ),
            ],
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _validUsageScope(rule['usage_scope']),
              isExpanded: true,
              decoration: InputDecoration(
                labelText: _t('مجال استعمال العنصر', 'Domaine d’utilisation'),
                border: const OutlineInputBorder(),
                isDense: true,
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
              onChanged: readOnly
                  ? null
                  : (value) {
                      if (value == null) return;
                      setState(() => rule['usage_scope'] = value);
                    },
            ),
            if (isEspagnoletteRule) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      key: ValueKey('min-height:$itemId'),
                      initialValue: rule['min_height_mm']?.toString() ?? '',
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: _t(
                          'أقل ارتفاع للإسبانيوليت (مم)',
                          'Hauteur minimale (mm)',
                        ),
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                      onChanged: readOnly
                          ? null
                          : (value) => rule['min_height_mm'] =
                              double.tryParse(value.trim().replaceAll(',', '.')),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextFormField(
                      key: ValueKey('max-height:$itemId'),
                      initialValue: rule['max_height_mm']?.toString() ?? '',
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: _t(
                          'أقصى ارتفاع للإسبانيوليت (مم)',
                          'Hauteur maximale (mm)',
                        ),
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                      onChanged: readOnly
                          ? null
                          : (value) => rule['max_height_mm'] =
                              double.tryParse(value.trim().replaceAll(',', '.')),
                    ),
                  ),
                ],
              ),
            ],
            if (table == 'Accessories') ...[
              const SizedBox(height: 14),
              _assemblyRuleEditor(rule, readOnly: readOnly),
              const SizedBox(height: 14),
              _accessoryRelationEditor(item, readOnly: readOnly),
            ],
            const SizedBox(height: 14),
            Text(
              _t(
                'خيارات الظهور والاعتماد:',
                'Options d\'affichage et statut :',
              ),
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                _ruleChip(rule, 'is_default', _t('افتراضي', 'Défaut'), readOnly: readOnly),
                _ruleChip(
                  rule,
                  'show_in_quantity',
                  _t('جدول الكمية', 'Quantité'),
                  readOnly: readOnly,
                ),
                _ruleChip(rule, 'show_in_dialog', _t('نافذة التغيير', 'Choix'), readOnly: readOnly),
                if (!isAssemblyScrewRule && !isScrew)
                  _ruleChip(rule, 'show_in_drawing', _t('الرسم', 'Dessin'), readOnly: readOnly),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _openMobileInspector(String table, Map<String, dynamic> item) {
    if (_isInspectorOpen) return;
    _isInspectorOpen = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        _isInspectorOpen = false;
        return;
      }
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (ctx) {
          return DraggableScrollableSheet(
            initialChildSize: 0.85,
            maxChildSize: 0.95,
            minChildSize: 0.5,
            expand: false,
            builder: (context, scrollController) {
              return SingleChildScrollView(
                controller: scrollController,
                padding: const EdgeInsets.all(16),
                child: _buildItemInspector(
                  table,
                  item,
                  onClose: () => Navigator.of(ctx).pop(),
                  readOnly: !context.read<AppSettingsProvider>().isAdmin,
                ),
              );
            },
          );
        },
      ).whenComplete(() {
        _isInspectorOpen = false;
        if (mounted) setState(() {});
      });
    });
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
    if (!context.read<AppSettingsProvider>().isAdmin) return;
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

  Future<void> _saveAccessoryLinksFor(
    int sourceId, {
    bool syncCatalog = true,
  }) async {
    if (!context.read<AppSettingsProvider>().isAdmin) return;
    try {
      await widget.db.saveAccessoryLinks(
        sourceId,
        _accessoryLinks[sourceId] ?? const [],
        syncCatalog: syncCatalog,
      );
      _dirtyAccessoryLinkIds.remove(sourceId);
    } catch (error) {
      if (!mounted) return;
      _showError(
        '${_t('تعذر حفظ روابط الأكسسوار', 'Liens impossibles à enregistrer')}: $error',
      );
    }
  }

  Widget _accessoryRelationEditor(Map<String, dynamic> item, {bool readOnly = false}) {
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
    final linkableRoles = _rolesForTable(
      'Accessories',
    ).where((role) => role.key != 'other').toList(growable: false);
    final itemId = _itemId(item);
    final screwIds = screwItems
        .map(_itemId)
        .whereType<int>()
        .where((id) => id != itemId)
        .toSet();
    final rawScrewId = (item['screw_accessory_id'] as num?)?.toInt();
    final screwId = screwIds.contains(rawScrewId) ? rawScrewId : 0;
    final links = itemId == null
        ? <Map<String, dynamic>>[]
        : _accessoryLinks.putIfAbsent(itemId, () => []);

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
              onChanged: readOnly
                  ? null
                  : (value) => _updateAccessoryFields(item, {
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
              onFieldSubmitted: readOnly
                  ? null
                  : (value) => _updateAccessoryFields(item, {
                      'screw_count': int.tryParse(value.trim()) ?? 0,
                    }),
            ),
          ],
          if (itemId != null && linkableRoles.isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    _t(
                      'الأكسسوارات المرتبطة وكمياتها',
                      'Accessoires liés et quantités',
                    ),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                IconButton(
                  tooltip: _t(
                    'إضافة أكسسوار مرتبط',
                    'Ajouter un accessoire lié',
                  ),
                  icon: const Icon(Icons.add_circle_outline_rounded),
                  onPressed: readOnly
                      ? null
                      : () => setState(() {
                          links.add({'target_role_key': null, 'quantity': 1});
                          _dirtyAccessoryLinkIds.add(itemId);
                        }),
                ),
              ],
            ),
            ...List.generate(links.length, (index) {
              final currentRoleKey = links[index]['target_role_key']
                  ?.toString();
              final availableRoles = [
                ...linkableRoles,
                if (currentRoleKey != null &&
                    currentRoleKey.isNotEmpty &&
                    !linkableRoles.any((r) => r.key == currentRoleKey))
                  _RuleRole(
                    currentRoleKey,
                    currentRoleKey == 'other'
                        ? _t('أخرى', 'Autre')
                        : currentRoleKey,
                    currentRoleKey == 'other' ? 'Autre' : currentRoleKey,
                  ),
              ];
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 3,
                      child: DropdownButtonFormField<String>(
                        key: ValueKey('accessory-link:$itemId:$index'),
                        initialValue: currentRoleKey,
                        isExpanded: true,
                        decoration: InputDecoration(
                          labelText: _t('دور الأكسسوار المرتبط', 'Rôle lié'),
                        ),
                        items: [
                          for (final role in availableRoles)
                            DropdownMenuItem(
                              value: role.key,
                              child: Text(_t(role.ar, role.fr)),
                            ),
                        ],
                        onChanged: readOnly
                            ? null
                            : (value) {
                                setState(() {
                                  links[index]['target_role_key'] = value;
                                  _dirtyAccessoryLinkIds.add(itemId);
                                });
                                _saveAccessoryLinksFor(itemId);
                              },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextFormField(
                        key: ValueKey('accessory-link-count:$itemId:$index'),
                        initialValue:
                            '${(links[index]['linked_quantity'] as num?)?.toInt() ?? (links[index]['quantity'] as num?)?.toInt() ?? 1}',
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: _t('العدد', 'Nombre'),
                        ),
                        onChanged: readOnly
                            ? null
                            : (value) {
                                final parsed = int.tryParse(value.trim());
                                if (parsed == null || parsed <= 0) return;
                                links[index]['quantity'] = parsed;
                                links[index].remove('linked_quantity');
                                _dirtyAccessoryLinkIds.add(itemId);
                              },
                        onTapOutside: (_) {
                          FocusManager.instance.primaryFocus?.unfocus();
                        },
                        onFieldSubmitted: readOnly
                            ? null
                            : (value) {
                                final parsed = int.tryParse(value.trim());
                                links[index]['quantity'] =
                                    parsed != null && parsed > 0 ? parsed : 1;
                                links[index].remove('linked_quantity');
                                _dirtyAccessoryLinkIds.add(itemId);
                                _saveAccessoryLinksFor(itemId);
                              },
                      ),
                    ),
                    IconButton(
                      tooltip: _t('حذف الرابط', 'Supprimer le lien'),
                      icon: const Icon(Icons.delete_outline_rounded),
                      onPressed: readOnly
                        ? null
                        : () {
                            setState(() {
                              links.removeAt(index);
                              _dirtyAccessoryLinkIds.add(itemId);
                            });
                            _saveAccessoryLinksFor(itemId);
                          },
                    ),
                  ],
                ),
              );
            }),
          ],
        ],
      ),
    );
  }

  Widget _ruleChip(
    Map<String, dynamic> rule,
    String key,
    String label, {
    bool readOnly = false,
  }) {
    final selected = rule[key] == true || rule[key] == 1;
    return FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: readOnly ? null : (value) => setState(() => rule[key] = value),
    );
  }
}
