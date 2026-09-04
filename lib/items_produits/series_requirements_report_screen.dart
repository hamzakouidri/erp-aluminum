import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../settings/app_settings.dart';
import '../settings/localization.dart';
import '../sql_database.dart';

/// Administrative report for a series: the configured manufacturing rules,
/// linked catalogue items and the orders that actually used the series.
class SeriesRequirementsReportScreen extends StatefulWidget {
  final SqlDatabase db;

  const SeriesRequirementsReportScreen({super.key, required this.db});

  @override
  State<SeriesRequirementsReportScreen> createState() =>
      _SeriesRequirementsReportScreenState();
}

class _SeriesRequirementsReportScreenState
    extends State<SeriesRequirementsReportScreen> {
  List<Map<String, dynamic>> _profiles = [];
  List<Map<String, dynamic>> _series = [];
  Map<String, dynamic>? _selectedProfile;
  Map<String, dynamic>? _selectedSeries;
  List<Map<String, dynamic>> _sections = [];
  List<Map<String, dynamic>> _roles = [];
  List<Map<String, dynamic>> _accessories = [];
  List<Map<String, dynamic>> _joints = [];
  List<Map<String, dynamic>> _jointLinks = [];
  Map<String, dynamic>? _config;
  List<Map<String, dynamic>> _orders = [];
  int _orderCount = 0;
  int _itemCount = 0;
  double _revenue = 0;
  bool _loading = true;
  bool _loadingSeries = false;
  bool _loadingReport = false;

  AppLanguage get _lang =>
      Provider.of<AppSettingsProvider>(context, listen: false).language;

  String _t(String ar, String fr, String en) {
    final lang = _lang;
    if (lang == AppLanguage.arabic) return ar;
    if (lang == AppLanguage.french) return fr;
    return en;
  }

  @override
  void initState() {
    super.initState();
    _loadProfiles();
  }

  Future<void> _loadProfiles() async {
    final profiles = await widget.db.readProfile();
    if (!mounted) return;
    setState(() {
      _profiles = profiles;
      _loading = false;
    });
  }

  Future<void> _selectProfile(Map<String, dynamic> profile) async {
    final profileId = (profile['id'] as num?)?.toInt();
    setState(() {
      _selectedProfile = profile;
      _selectedSeries = null;
      _series = [];
      _clearReport();
      _loadingSeries = true;
    });
    final series = profileId == null
        ? <Map<String, dynamic>>[]
        : await widget.db.readSeriesByProfile(profileId);
    if (!mounted) return;
    setState(() {
      _series = series;
      _loadingSeries = false;
    });
  }

  void _clearReport() {
    _sections = [];
    _roles = [];
    _accessories = [];
    _joints = [];
    _jointLinks = [];
    _config = null;
    _orders = [];
    _orderCount = 0;
    _itemCount = 0;
    _revenue = 0;
  }

  Future<void> _selectSeries(Map<String, dynamic> series) async {
    final seriesId = (series['id'] as num?)?.toInt();
    if (seriesId == null) return;
    setState(() {
      _selectedSeries = series;
      _loadingReport = true;
      _clearReport();
    });

    final result = await Future.wait<dynamic>([
      widget.db.readSectionsBySeries(seriesId),
      widget.db.getSeriesDesignRoles(seriesId),
      widget.db.getSeriesDesignConfig(seriesId),
      widget.db.getSeriesTableConfig(seriesId),
      widget.db.readAccessories(),
      widget.db.readJoints(),
      widget.db.getSectionJointLinksForSeries(seriesId),
      _readOrderUsage(seriesId),
    ]);
    if (!mounted) return;

    final allAccessories = result[4] as List<Map<String, dynamic>>;
    final allJoints = result[5] as List<Map<String, dynamic>>;
    final usage = result[7] as Map<String, dynamic>;
    setState(() {
      _sections = result[0] as List<Map<String, dynamic>>;
      _roles = result[1] as List<Map<String, dynamic>>;
      _config = {
        if (result[2] is Map<String, dynamic>)
          ...result[2] as Map<String, dynamic>,
        if (result[3] is Map<String, dynamic>)
          ...result[3] as Map<String, dynamic>,
      };
      _jointLinks = result[6] as List<Map<String, dynamic>>;
      _accessories = allAccessories
          .where((item) => _linked(item, seriesId))
          .toList();
      _joints = allJoints.where((item) => _linked(item, seriesId)).toList();
      _orders =
          (usage['orders'] as List?)
              ?.whereType<Map<String, dynamic>>()
              .toList() ??
          [];
      _orderCount = usage['orderCount'] as int? ?? 0;
      _itemCount = usage['itemCount'] as int? ?? 0;
      _revenue = (usage['revenue'] as num?)?.toDouble() ?? 0;
      _loadingReport = false;
    });
  }

  bool _linked(Map<String, dynamic> item, int seriesId) {
    if ('${item['scope'] ?? ''}'.trim().toLowerCase() == 'global') return true;
    final direct = int.tryParse('${item['series_id'] ?? ''}');
    if (direct == seriesId) return true;
    final ids = '${item['series_ids'] ?? ''}'
        .split(',')
        .map((value) => int.tryParse(value.trim()))
        .whereType<int>();
    return ids.contains(seriesId);
  }

  bool _containsSeries(dynamic value, int seriesId) {
    if (value is Map) {
      for (final entry in value.entries) {
        final key = entry.key.toString().toLowerCase();
        if (key == 'seriesid' || key == 'series_id') {
          if (int.tryParse('${entry.value}') == seriesId) return true;
        }
        if (_containsSeries(entry.value, seriesId)) return true;
      }
      return false;
    }
    if (value is Iterable) {
      return value.any((item) => _containsSeries(item, seriesId));
    }
    return false;
  }

  Future<Map<String, dynamic>> _readOrderUsage(int seriesId) async {
    final database = await widget.db.db;
    if (database == null) {
      return {
        'orders': <Map<String, dynamic>>[],
        'orderCount': 0,
        'itemCount': 0,
        'revenue': 0.0,
      };
    }
    final rows = await database.rawQuery('''
      SELECT c.id AS order_id, c.order_code, c.net_payable, c.total,
             c.created_at, cl.firstname, cl.lastname, d.quantity,
             d.partitions_json
      FROM Commandes c
      INNER JOIN Commandes_details d ON d.id_commandes = c.id
      LEFT JOIN Client cl ON cl.id = c.client_id
      ORDER BY c.id DESC
    ''');
    final matched = <int, Map<String, dynamic>>{};
    var itemCount = 0;
    for (final row in rows) {
      final raw = row['partitions_json']?.toString() ?? '';
      dynamic decoded;
      try {
        decoded = raw.isEmpty ? null : jsonDecode(raw);
      } catch (_) {
        decoded = null;
      }
      if (!_containsSeries(decoded, seriesId)) continue;
      final orderId = (row['order_id'] as num?)?.toInt();
      if (orderId == null) continue;
      itemCount += (row['quantity'] as num?)?.toInt() ?? 1;
      matched[orderId] = {
        'order_id': orderId,
        'order_code': row['order_code'],
        'created_at': row['created_at'],
        'client': '${row['firstname'] ?? ''} ${row['lastname'] ?? ''}'.trim(),
        'value': (row['net_payable'] ?? row['total'] ?? 0) as num,
      };
    }
    final orders = matched.values.toList();
    return {
      'orders': orders,
      'orderCount': orders.length,
      'itemCount': itemCount,
      'revenue': orders.fold<double>(
        0,
        (sum, row) => sum + (row['value'] as num).toDouble(),
      ),
    };
  }

  String _roleLabel(String key) {
    const labels = <String, List<String>>{
      'frame': ['الإطار', 'Dormant', 'Frame'],
      'frame_extension': [
        'مكمل الإطار',
        'Complément dormant',
        'Frame extension',
      ],
      'sash': ['الضلفة', 'Ouvrant', 'Sash'],
      'sash_extension': ['مكمل الضلفة', 'Complément ouvrant', 'Sash extension'],
      'glazing_bead': ['حاملة الزجاج', 'Parclose', 'Glazing bead'],
      'porte_joint': ['فرشاة الضلفة', 'Joint brosse', 'Sash brush gasket'],
      'mullion': ['التقسيم', 'Traverse / montant', 'Mullion'],
      'triangle': ['التراينغل', 'Triangle', 'Triangle'],
      'profile_angle': ['بروفيل الزاوية', 'Profil d’angle', 'Angle profile'],
      'caniveau': ['كانيڤو', 'Caniveau', 'Drain channel'],
      'cache_caniveau': [
        'غطاء الكانيڤو',
        'Cache-caniveau',
        'Drain channel cover',
      ],
    };
    final values = labels[key];
    if (values == null) return Localization.translate(key, _lang);
    return values[_lang == AppLanguage.arabic
        ? 0
        : _lang == AppLanguage.french
        ? 1
        : 2];
  }

  String _number(dynamic value) {
    if (value == null || value.toString().trim().isEmpty) return '—';
    if (value is num && value == value.roundToDouble()) {
      return value.toInt().toString();
    }
    return value.toString();
  }

  String _scopeLabel(dynamic value) {
    final key = '${value ?? 'auto'}'.trim().toLowerCase();
    if (key == 'sliding') return _t('منزلق', 'Coulissant', 'Sliding');
    if (key == 'opening') return _t('فتح', 'Ouvrant', 'Opening');
    if (key == 'both') {
      return _t('فتح ومنزلق', 'Ouvrant et coulissant', 'Opening and sliding');
    }
    return _t('تلقائي', 'Automatique', 'Automatic');
  }

  String _configLabel(String key) {
    const keys = <String, List<String>>{
      'supports_shutter': [
        'يدعم الستارة',
        'Compatible avec volet',
        'Supports shutter',
      ],
      'allows_divisions': [
        'يسمح بالتقسيمات',
        'Autorise les divisions',
        'Allows divisions',
      ],
      'allowed_contents_json': [
        'المحتويات المسموحة',
        'Contenus autorisés',
        'Allowed contents',
      ],
      'sash_w_deduction_2': [
        'خصم عرض الضلفة بسكتين',
        'Déduction largeur ouvrant 2 vantaux',
        'Two-sash width deduction',
      ],
      'sash_w_deduction_3': [
        'خصم عرض الضلفة بثلاث سكات',
        'Déduction largeur ouvrant 3 vantaux',
        'Three-sash width deduction',
      ],
      'sash_w_deduction_4': [
        'خصم عرض الضلفة بأربع سكات',
        'Déduction largeur ouvrant 4 vantaux',
        'Four-sash width deduction',
      ],
      'sash_overlap_val': [
        'تراكب الضلفة',
        'Recouvrement ouvrant',
        'Sash overlap',
      ],
      'glass_w_deduction': [
        'خصم عرض الزجاج',
        'Déduction largeur verre',
        'Glass width deduction',
      ],
      'sliding_chicane_pieces_per_junction': [
        'قطع الشيكينة لكل التقاء',
        'Pièces de chicane par jonction',
        'Chicane pieces per junction',
      ],
      'sliding_rail_clearance': [
        'خلوص سكة المنزلق',
        'Jeu du rail coulissant',
        'Sliding rail clearance',
      ],
      'custom_formula_notes': [
        'ملاحظة معادلة الحساب',
        'Note de formule',
        'Calculation formula note',
      ],
      'allowed_section_types': [
        'أنواع القطاعات المسموحة',
        'Types de profilés autorisés',
        'Allowed profile types',
      ],
      'allowed_accessory_ids': [
        'إكسسوارات مسموحة',
        'Accessoires autorisés',
        'Allowed accessories',
      ],
      'allowed_accessory_types': [
        'أنواع الإكسسوارات المسموحة',
        'Types d’accessoires autorisés',
        'Allowed accessory types',
      ],
      'excluded_accessory_ids': [
        'إكسسوارات مستثناة',
        'Accessoires exclus',
        'Excluded accessories',
      ],
    };
    final value = keys[key];
    if (value == null) return key;
    return value[_lang == AppLanguage.arabic
        ? 0
        : _lang == AppLanguage.french
        ? 1
        : 2];
  }

  String _displayValue(dynamic value) {
    if (value is bool || value is int && (value == 0 || value == 1)) {
      final enabled = value == true || value == 1;
      return enabled ? _t('نعم', 'Oui', 'Yes') : _t('لا', 'Non', 'No');
    }
    return _number(value);
  }

  String _sectionName(Map<String, dynamic> row) {
    final code = row['section_code'] ?? row['code'];
    final name = row['section_name'] ?? row['name'];
    final text = '${name ?? ''}'.trim();
    return '${code ?? ''}'.trim().isEmpty ? text : '$code — $text';
  }

  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<AppSettingsProvider>(context);
    if (!settings.canViewSeriesRequirementsReport()) {
      return Scaffold(
        appBar: AppBar(
          title: Text(
            _t('تقرير السلاسل', 'Rapport des gammes', 'Series report'),
          ),
        ),
        body: Center(
          child: Text(
            _t(
              'ليس لديك صلاحية الوصول إلى هذا التقرير.',
              'Vous n’avez pas accès à ce rapport.',
              'You do not have permission to view this report.',
            ),
          ),
        ),
      );
    }
    final rtl = settings.language == AppLanguage.arabic;
    return Directionality(
      textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            _t(
              'متطلبات واستعمال السلاسل',
              'Besoins et utilisation des gammes',
              'Series requirements and usage',
            ),
          ),
          actions: [
            IconButton(
              onPressed: _loadProfiles,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  _buildSelector(),
                  Expanded(child: _buildReportBody()),
                ],
              ),
      ),
    );
  }

  Widget _buildSelector() {
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _t(
                'اختر البروفيل ثم السلسلة',
                'Choisissez le profil puis la gamme',
                'Choose a profile, then a series',
              ),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<int>(
              initialValue: (_selectedProfile?['id'] as num?)?.toInt(),
              decoration: InputDecoration(
                labelText: _t('البروفيل', 'Profilé', 'Profile'),
                border: const OutlineInputBorder(),
              ),
              items: _profiles
                  .map(
                    (p) => DropdownMenuItem<int>(
                      value: (p['id'] as num).toInt(),
                      child: Text('${p['name'] ?? ''}'),
                    ),
                  )
                  .toList(),
              onChanged: (id) {
                final profile = _profiles.firstWhere((p) => p['id'] == id);
                _selectProfile(profile);
              },
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<int>(
              initialValue: (_selectedSeries?['id'] as num?)?.toInt(),
              decoration: InputDecoration(
                labelText: _t('السلسلة', 'Gamme', 'Series'),
                border: const OutlineInputBorder(),
              ),
              items: _series
                  .map(
                    (s) => DropdownMenuItem<int>(
                      value: (s['id'] as num).toInt(),
                      child: Text('${s['name'] ?? ''}'),
                    ),
                  )
                  .toList(),
              onChanged: _loadingSeries
                  ? null
                  : (id) {
                      final series = _series.firstWhere((s) => s['id'] == id);
                      _selectSeries(series);
                    },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReportBody() {
    if (_selectedSeries == null) {
      return Center(
        child: Text(
          _t(
            'اختر سلسلة لعرض تقريرها.',
            'Choisissez une gamme pour afficher son rapport.',
            'Choose a series to view its report.',
          ),
        ),
      );
    }
    if (_loadingReport) return const Center(child: CircularProgressIndicator());
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _buildSummary(),
        const SizedBox(height: 12),
        _buildRolesCard(),
        _buildSectionsCard(),
        _buildConfigCard(),
        _buildLinkedItemsCard(),
        _buildOrdersCard(),
      ],
    );
  }

  Widget _stat(String label, String value, IconData icon) => Expanded(
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          children: [
            Icon(icon, color: Colors.blue),
            const SizedBox(height: 4),
            Text(
              value,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 11),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _buildSummary() => Card(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${_selectedProfile?['name'] ?? ''} — ${_selectedSeries?['name'] ?? ''}',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _stat(
                _t('الأدوار والقواعد', 'Rôles et règles', 'Roles and rules'),
                '${_roles.length}',
                Icons.rule,
              ),
              _stat(
                _t('القطاعات', 'Profilés', 'Profiles'),
                '${_sections.length}',
                Icons.view_module,
              ),
              _stat(
                _t(
                  'الإكسسوارات والجوانات',
                  'Accessoires et joints',
                  'Accessories and gaskets',
                ),
                '${_accessories.length + _joints.length}',
                Icons.build,
              ),
              _stat(
                _t('الطلبات', 'Commandes', 'Orders'),
                '$_orderCount',
                Icons.receipt_long,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '${_t('قيمة الطلبات المرتبطة', 'Valeur des commandes liées', 'Linked order value')}: ${_revenue.toStringAsFixed(2)}',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          Text(
            _t(
              'هذه قيمة الطلبات الإجمالية وليست الربح الصافي للسلسلة.',
              'Il s’agit de la valeur totale des commandes, pas du bénéfice net de la gamme.',
              'This is the total linked order value, not the series net profit.',
            ),
            style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
          ),
        ],
      ),
    ),
  );

  Widget _buildRolesCard() => Card(
    child: ExpansionTile(
      initiallyExpanded: true,
      title: Text(
        _t(
          'متطلبات السلسلة حسب الدور',
          'Besoins de la gamme par rôle',
          'Series requirements by role',
        ),
      ),
      children: _roles.isEmpty
          ? [
              ListTile(
                title: Text(
                  _t(
                    'لا توجد قواعد أدوار محفوظة.',
                    'Aucune règle de rôle enregistrée.',
                    'No role rules saved.',
                  ),
                ),
              ),
            ]
          : _roles
                .map(
                  (role) => ListTile(
                    leading: const Icon(Icons.account_tree_outlined),
                    title: Text(_roleLabel(role['role_key']?.toString() ?? '')),
                    subtitle: Text(
                      '${_sectionName(role)}\n${_t('النطاق', 'Portée', 'Scope')}: ${_scopeLabel(role['usage_scope'])}  |  ${_t('في الرسم', 'Dessin', 'Drawing')}: ${role['show_in_drawing'] == 1 ? '✓' : '—'}  |  ${_t('في الكمية', 'Quantité', 'Quantity')}: ${role['show_in_quantity'] == 1 ? '✓' : '—'}',
                    ),
                    isThreeLine: true,
                  ),
                )
                .toList(),
    ),
  );

  Widget _buildSectionsCard() => Card(
    child: ExpansionTile(
      title: Text(
        _t(
          'كل قطاعات السلسلة',
          'Tous les profilés de la gamme',
          'All series profiles',
        ),
      ),
      children: _sections.isEmpty
          ? [
              ListTile(
                title: Text(
                  _t(
                    'لا توجد قطاعات محفوظة.',
                    'Aucun profilé enregistré.',
                    'No profiles saved.',
                  ),
                ),
              ),
            ]
          : _sections
                .map(
                  (section) => ListTile(
                    dense: true,
                    leading: const Icon(Icons.view_module_outlined),
                    title: Text(_sectionName(section)),
                    subtitle: Text(
                      '${_t('النوع', 'Type', 'Type')}: ${section['type'] ?? '—'}  |  ${_t('السماكة', 'Épaisseur', 'Thickness')}: ${_number(section['thickness'])}',
                    ),
                  ),
                )
                .toList(),
    ),
  );

  Widget _buildConfigCard() => Card(
    child: ExpansionTile(
      title: Text(
        _t(
          'إعدادات الحساب والقواعد',
          'Paramètres de calcul et règles',
          'Calculation settings and rules',
        ),
      ),
      children: [
        if (_config == null || _config!.isEmpty)
          ListTile(
            title: Text(
              _t(
                'لا توجد إعدادات إضافية.',
                'Aucun paramètre supplémentaire.',
                'No additional settings.',
              ),
            ),
          ),
        ...?_config?.entries.map(
          (entry) => ListTile(
            dense: true,
            title: Text(_configLabel(entry.key)),
            trailing: Text(_displayValue(entry.value)),
          ),
        ),
      ],
    ),
  );

  Widget _buildLinkedItemsCard() => Card(
    child: ExpansionTile(
      title: Text(
        _t(
          'المواد المرتبطة بالسلسلة',
          'Articles liés à la gamme',
          'Items linked to the series',
        ),
      ),
      children: [
        if (_accessories.isEmpty && _joints.isEmpty)
          ListTile(
            title: Text(
              _t(
                'لا توجد إكسسوارات أو جوانات مرتبطة.',
                'Aucun accessoire ou joint lié.',
                'No linked accessories or gaskets.',
              ),
            ),
          ),
        ..._accessories.map(
          (item) => ListTile(
            leading: const Icon(Icons.build_outlined),
            title: Text('${item['name'] ?? ''}'),
            subtitle: Text(_t('إكسسوار', 'Accessoire', 'Accessory')),
          ),
        ),
        ..._joints.map(
          (item) => ListTile(
            leading: const Icon(Icons.linear_scale),
            title: Text('${item['name'] ?? ''}'),
            subtitle: Text(_t('جوان', 'Joint', 'Gasket')),
          ),
        ),
        ..._jointLinks.map(
          (link) => ListTile(
            leading: const Icon(Icons.link),
            title: Text(
              '${link['joint_name'] ?? link['gasket_type'] ?? link['joint_gasket_type'] ?? ''}',
            ),
            subtitle: Text(
              '${_t('مرتبط بالقطاع', 'Lié au profilé', 'Linked to profile')} ${link['section_code'] ?? link['section_id'] ?? ''} — ${link['position_key'] ?? ''}',
            ),
          ),
        ),
      ],
    ),
  );

  Widget _buildOrdersCard() => Card(
    child: ExpansionTile(
      title: Text(
        _t(
          'عائدات واستعمال السلسلة في الطلبيات',
          'Utilisation et valeur dans les commandes',
          'Series usage and order returns',
        ),
      ),
      children: [
        ListTile(
          leading: const Icon(Icons.numbers),
          title: Text(
            '${_t('عدد القطع/النوافذ', 'Nombre de pièces/fenêtres', 'Items/windows')}: $_itemCount',
          ),
        ),
        if (_orders.isEmpty)
          ListTile(
            title: Text(
              _t(
                'لم تستعمل هذه السلسلة في طلبية مسجلة بعد.',
                'Cette gamme n’a pas encore été utilisée dans une commande.',
                'This series has not been used in a recorded order yet.',
              ),
            ),
          ),
        ..._orders.map(
          (order) => ListTile(
            leading: const Icon(Icons.receipt),
            title: Text(
              '${_t('طلبية', 'Commande', 'Order')} #${order['order_code'] ?? order['order_id']} — ${order['client'] ?? ''}',
            ),
            subtitle: Text(
              '${order['created_at'] ?? ''}  |  ${_number(order['value'])}',
            ),
          ),
        ),
      ],
    ),
  );
}
