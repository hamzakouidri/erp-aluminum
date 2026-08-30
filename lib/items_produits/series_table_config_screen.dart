import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../settings/app_settings.dart';
import '../sql_database.dart';

/// Administrator-only definition of the main profile roles for each series.
/// This temporary page is intentionally independent from the quantity table.
class SeriesTableConfigScreen extends StatefulWidget {
  final SqlDatabase db;

  const SeriesTableConfigScreen({super.key, required this.db});

  @override
  State<SeriesTableConfigScreen> createState() =>
      _SeriesTableConfigScreenState();
}

class _SeriesRole {
  const _SeriesRole({
    required this.key,
    required this.ar,
    required this.fr,
    required this.descriptionAr,
    required this.descriptionFr,
    this.required = false,
  });

  final String key;
  final String ar;
  final String fr;
  final String descriptionAr;
  final String descriptionFr;
  final bool required;
}

class _SeriesTableConfigScreenState extends State<SeriesTableConfigScreen> {
  static const _roles = <_SeriesRole>[
    _SeriesRole(
      key: 'frame',
      ar: 'الإطار',
      fr: 'Dormant',
      descriptionAr: 'الإطار الرئيسي للسلسلة',
      descriptionFr: 'Profil extérieur principal de la série',
      required: true,
    ),
    _SeriesRole(
      key: 'frame_extension',
      ar: 'مكمل الإطار',
      fr: 'Complément dormant',
      descriptionAr: 'يُختار فقط إذا كانت السلسلة تستعمله',
      descriptionFr: 'À sélectionner uniquement si la série l’utilise',
    ),
    _SeriesRole(
      key: 'sash',
      ar: 'الضلفة',
      fr: 'Ouvrant',
      descriptionAr: 'يمكن اختيار عدة ضلفات هنا، مثلاً الأنواع الثلاثة في TPR',
      descriptionFr:
          'Plusieurs ouvrants possibles, par exemple les trois types TPR',
    ),
    _SeriesRole(
      key: 'sash_extension',
      ar: 'مكمل الضلفة',
      fr: 'Complément ouvrant',
      descriptionAr: 'لا تحدده إذا لم تستعمله السلسلة',
      descriptionFr: 'Laissez vide si la série ne l’utilise pas',
    ),
    _SeriesRole(
      key: 'sash_lateral',
      ar: 'قائم جانبي منزلق',
      fr: 'Montant latéral coulissant',
      descriptionAr: 'القطع التي يمكن أن تستبدل القائم الجانبي في المنزلق',
      descriptionFr:
          'Profils interchangeables pour le montant latéral coulissant',
    ),
    _SeriesRole(
      key: 'sash_central',
      ar: 'قائم وسطي منزلق',
      fr: 'Montant central coulissant',
      descriptionAr: 'القطع التي يمكن أن تستبدل القائم الوسطي في المنزلق',
      descriptionFr:
          'Profils interchangeables pour le montant central coulissant',
    ),
    _SeriesRole(
      key: 'sash_traverse',
      ar: 'سكة / ترافيرس الضلفة',
      fr: 'Traverse ouvrant coulissant',
      descriptionAr: 'القطع العرضية الخاصة بضلفة المنزلق',
      descriptionFr: 'Profils traverses de l’ouvrant coulissant',
    ),
    _SeriesRole(
      key: 'glazing_bead',
      ar: 'باغيت / غطاء الزجاج',
      fr: 'Parclose',
      descriptionAr: 'المقطع الذي يثبت الزجاج',
      descriptionFr: 'Profil de maintien du vitrage',
    ),
    _SeriesRole(
      key: 'mullion',
      ar: 'التقسيم',
      fr: 'Traverse / montant',
      descriptionAr: 'مقاطع التقسيم الداخلية',
      descriptionFr: 'Profils de séparation intérieure',
    ),
    _SeriesRole(
      key: 'side_cover',
      ar: 'الغطاء الجانبي',
      fr: 'Couvre-joint',
      descriptionAr: 'اختره إن كان يجب أن يظهر في هذه السلسلة',
      descriptionFr: 'À choisir lorsqu’il doit apparaître pour cette série',
    ),
    _SeriesRole(
      key: 'batmo',
      ar: 'الباتمو',
      fr: 'Battement',
      descriptionAr: 'مقطع الباتمو الخاص بهذه السلسلة',
      descriptionFr: 'Profil de battement propre à cette série',
    ),
    _SeriesRole(
      key: 'plant',
      ar: 'البلانت',
      fr: 'Plinthe',
      descriptionAr:
          'مقطع سفلي للظلفات والثوابت لتقوية الباب أو تعويض الإطار السفلي',
      descriptionFr:
          'Profil bas pour ouvrants et fixes, utilisé pour renforcer ou remplacer le dormant bas',
    ),
    _SeriesRole(
      key: 'porte_joint',
      ar: 'حامل الجوان',
      fr: 'Porte-joint',
      descriptionAr: 'يستعمل تلقائياً مع البلانت ويحمل جوان البرونز في الأسفل',
      descriptionFr:
          'Utilisé automatiquement avec la plinthe et son joint bronze inférieur',
    ),
    _SeriesRole(
      key: 'triangle',
      ar: 'التراينغل',
      fr: 'Triangle',
      descriptionAr: 'مقطع التراينغل المرتبط بغلق الكريمون',
      descriptionFr: 'Profil triangle lié à la fermeture par crémone',
    ),
    _SeriesRole(
      key: 'renfort',
      ar: 'حديد الدعم',
      fr: 'Renfort',
      descriptionAr: 'حديد الدعم المرتبط بمقاطع هذه السلسلة',
      descriptionFr: 'Renforts liés aux profils de cette série',
    ),
    _SeriesRole(
      key: 'rail',
      ar: 'السكة',
      fr: 'Rail',
      descriptionAr: 'خاص بالسلاسل التي تستعمل السكك',
      descriptionFr: 'Pour les séries utilisant des rails',
    ),
    _SeriesRole(
      key: 'chicane',
      ar: 'الشيكان',
      fr: 'Chicane',
      descriptionAr: 'المقطع الأوسط المتداخل للمنزلق عند الحاجة',
      descriptionFr: 'Profil central de recouvrement si nécessaire',
    ),
    _SeriesRole(
      key: 'reducer',
      ar: 'مخفض الزجاج',
      fr: 'Réducteur',
      descriptionAr: 'مقطع اختياري لتكييف سماكة الزجاج',
      descriptionFr: 'Profil optionnel d’adaptation du vitrage',
    ),
    _SeriesRole(
      key: 'other_profile',
      ar: 'مقطع خاص آخر',
      fr: 'Autre profil spécifique',
      descriptionAr: 'أي مقطع خاص بالسلسلة يجب أن يدخل في الجدول',
      descriptionFr:
          'Tout autre profil propre à cette série à inclure au tableau',
    ),
  ];

  List<Map<String, dynamic>> _profiles = [];
  List<Map<String, dynamic>> _series = [];
  List<Map<String, dynamic>> _sections = [];
  List<Map<String, dynamic>> _joints = [];
  Map<String, dynamic>? _selectedProfile;
  Map<String, dynamic>? _selectedSeries;
  Map<String, dynamic>? _tableConfig;

  final Map<String, Set<int>> _sectionIdsByRole = {
    for (final role in _roles) role.key: <int>{},
  };
  final Map<String, int?> _defaultSectionByRole = {
    for (final role in _roles) role.key: null,
  };
  final Map<String, Map<String, dynamic>> _roleOptionsByRoleSection = {};
  final Map<int, Map<String, String?>> _gasketTypeBySectionPosition = {};

  bool _loadingProfiles = true;
  bool _loadingSeries = false;
  bool _loadingDefinition = false;
  bool _saving = false;

  final _sashWidth2Controller = TextEditingController();
  final _sashWidth3Controller = TextEditingController();
  final _sashWidth4Controller = TextEditingController();
  final _sashOverlapController = TextEditingController();
  final _glassWidthController = TextEditingController();
  final _chicanePiecesController = TextEditingController(text: '1');
  final _railClearanceController = TextEditingController(text: '1');
  final _formulaNotesController = TextEditingController();

  bool get _isArabic =>
      context.read<AppSettingsProvider>().language == AppLanguage.arabic;
  String _t(String ar, String fr) => _isArabic ? ar : fr;
  int? get _seriesId => (_selectedSeries?['id'] as num?)?.toInt();
  bool get _isSlidingSeries {
    final value =
        '${_selectedSeries?['type'] ?? ''} '
                '${_selectedSeries?['name'] ?? ''}'
            .toLowerCase();
    return value.contains('sliding') ||
        value.contains('couliss') ||
        value.contains('منزلق') ||
        value.contains('جرار') ||
        value.contains('كوليس');
  }

  bool get _isPvcProfile =>
      (_selectedProfile?['name']?.toString().toLowerCase() ?? '').contains(
        'pvc',
      );
  Iterable<_SeriesRole> get _availableRoles =>
      _roles.where((role) => !_isPvcProfile || role.key != 'reducer');

  @override
  void initState() {
    super.initState();
    _loadProfiles();
  }

  @override
  void dispose() {
    _sashWidth2Controller.dispose();
    _sashWidth3Controller.dispose();
    _sashWidth4Controller.dispose();
    _sashOverlapController.dispose();
    _glassWidthController.dispose();
    _chicanePiecesController.dispose();
    _railClearanceController.dispose();
    _formulaNotesController.dispose();
    super.dispose();
  }

  Future<void> _loadProfiles() async {
    setState(() => _loadingProfiles = true);
    final profiles = await widget.db.readProfile();
    if (!mounted) return;
    setState(() {
      _profiles = profiles;
      _loadingProfiles = false;
    });
  }

  Future<void> _selectProfile(Map<String, dynamic> profile) async {
    setState(() {
      _selectedProfile = profile;
      _selectedSeries = null;
      _series = [];
      _sections = [];
      _loadingSeries = true;
      _resetDefinition();
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

  void _resetDefinition() {
    for (final role in _roles) {
      _sectionIdsByRole[role.key]!.clear();
      _defaultSectionByRole[role.key] = null;
    }
    _tableConfig = null;
    _roleOptionsByRoleSection.clear();
    _gasketTypeBySectionPosition.clear();
    _sashWidth2Controller.clear();
    _sashWidth3Controller.clear();
    _sashWidth4Controller.clear();
    _sashOverlapController.clear();
    _glassWidthController.clear();
    _chicanePiecesController.text = '1';
    _railClearanceController.text = '1';
    _formulaNotesController.clear();
  }

  Future<void> _selectSeries(Map<String, dynamic> series) async {
    final seriesId = (series['id'] as num?)?.toInt();
    if (seriesId == null) return;
    setState(() {
      _selectedSeries = series;
      _loadingDefinition = true;
      _resetDefinition();
    });

    final results = await Future.wait<dynamic>([
      widget.db.readSectionsBySeries(seriesId),
      widget.db.getSeriesDesignRoles(seriesId),
      widget.db.getSeriesTableConfig(seriesId),
      widget.db.readJoints(),
      widget.db.getSectionJointLinksForSeries(seriesId),
    ]);
    if (!mounted) return;

    final roles = results[1] as List<Map<String, dynamic>>;
    _restoreDefinition(roles);
    _restoreFormulaConfig(results[2] as Map<String, dynamic>?);
    _restoreJointLinks(results[4] as List<Map<String, dynamic>>);
    setState(() {
      _sections = results[0] as List<Map<String, dynamic>>;
      _joints = results[3] as List<Map<String, dynamic>>;
      _loadingDefinition = false;
    });
  }

  void _restoreFormulaConfig(Map<String, dynamic>? config) {
    _tableConfig = config;
    String number(String key, {String fallback = ''}) {
      final value = config?[key];
      if (value == null) return fallback;
      final parsed = value is num
          ? value.toDouble()
          : double.tryParse('$value');
      if (parsed == null) return fallback;
      return parsed == parsed.roundToDouble()
          ? parsed.toInt().toString()
          : parsed.toString();
    }

    _sashWidth2Controller.text = number('sash_w_deduction_2');
    _sashWidth3Controller.text = number('sash_w_deduction_3');
    _sashWidth4Controller.text = number('sash_w_deduction_4');
    _sashOverlapController.text = number('sash_overlap_val');
    _glassWidthController.text = number('glass_w_deduction', fallback: '10');
    _chicanePiecesController.text = number(
      'sliding_chicane_pieces_per_junction',
      fallback: '1',
    );
    _railClearanceController.text = number(
      'sliding_rail_clearance',
      fallback: '1',
    );
    _formulaNotesController.text =
        config?['custom_formula_notes']?.toString() ?? '';
  }

  double _decimal(TextEditingController controller, {double fallback = 0}) =>
      double.tryParse(controller.text.trim().replaceAll(',', '.')) ?? fallback;

  int _positiveInt(TextEditingController controller, {int fallback = 1}) {
    final value = _decimal(controller, fallback: fallback.toDouble()).round();
    return value < 1 ? fallback : value;
  }

  void _restoreDefinition(List<Map<String, dynamic>> roles) {
    for (final item in roles) {
      final role = item['role_key']?.toString() ?? '';
      final sectionId = (item['section_id'] as num?)?.toInt();
      if (!_sectionIdsByRole.containsKey(role) || sectionId == null) continue;
      _sectionIdsByRole[role]!.add(sectionId);
      _roleOptionsByRoleSection[_roleOptionKey(role, sectionId)] =
          _roleOptionsFromRow(item);
      if (item['is_default'] == 1 || _defaultSectionByRole[role] == null) {
        _defaultSectionByRole[role] = sectionId;
      }
    }
  }

  void _restoreJointLinks(List<Map<String, dynamic>> links) {
    _gasketTypeBySectionPosition.clear();
    for (final item in links) {
      final sectionId = (item['section_id'] as num?)?.toInt();
      final gasketType =
          (item['gasket_type']?.toString().trim().isNotEmpty ?? false)
          ? item['gasket_type'].toString().trim()
          : item['joint_gasket_type']?.toString().trim() ?? '';
      final position = item['position_key']?.toString().trim() ?? '';
      if (sectionId == null || gasketType.isEmpty || position.isEmpty) {
        continue;
      }
      final normalizedPosition = position == 'frame_gasket'
          ? 'frame_inner'
          : position == 'porte_joint_bronze'
          ? 'porte_joint_brosse'
          : position;
      _gasketTypeBySectionPosition.putIfAbsent(sectionId, () => {});
      _gasketTypeBySectionPosition[sectionId]![normalizedPosition] = gasketType;
    }
  }

  String _roleOptionKey(String role, int sectionId) => '$role:$sectionId';

  bool _truthy(dynamic value, {bool fallback = false}) {
    if (value == null) return fallback;
    if (value is bool) return value;
    if (value is num) return value != 0;
    final text = value.toString().trim().toLowerCase();
    if (text.isEmpty) return fallback;
    return text == '1' || text == 'true' || text == 'yes' || text == 'oui';
  }

  double _number(dynamic value, {double fallback = 0}) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString().replaceAll(',', '.') ?? '') ??
        fallback;
  }

  Map<String, dynamic> _defaultRoleOptions(String role) {
    return {
      'usage_scope': _isSlidingSeries ? 'sliding' : 'opening',
      'show_when_glass': role == 'reducer' ? 'simple' : 'any',
      'integrated_side_cover': false,
      'allows_side_cover': true,
      'allowed_with_shutter': true,
      'show_in_drawing': true,
      'show_in_quantity': true,
      'show_in_dialog': true,
      'width_adjust_mm': 0.0,
      'height_adjust_mm': 0.0,
      'formula_note': '',
      'skip_glazing_bead': false,
      'requires_plant': role == 'porte_joint',
      'joint_length_multiplier': role == 'porte_joint' ? 2.0 : 1.0,
    };
  }

  bool _roleUsesGlassRule(String role) {
    switch (role) {
      case 'glazing_bead':
      case 'reducer':
        return true;
    }
    return false;
  }

  Map<String, dynamic> _normalizedRoleOptions(
    String role,
    Map<String, dynamic> options,
  ) {
    final normalized = Map<String, dynamic>.from(options);
    if (!_roleUsesGlassRule(role)) {
      normalized['show_when_glass'] = 'any';
    }
    if (role != 'sash' && role != 'sash_extension') {
      normalized['skip_glazing_bead'] = false;
    }
    if (role != 'porte_joint') {
      normalized['requires_plant'] = false;
      normalized['joint_length_multiplier'] = 1.0;
    }
    return normalized;
  }

  Map<String, dynamic> _roleOptionsFromRow(Map<String, dynamic> row) {
    final role = row['role_key']?.toString() ?? '';
    return _normalizedRoleOptions(role, {
      ..._defaultRoleOptions(role),
      'usage_scope': row['usage_scope']?.toString() ?? 'auto',
      'show_when_glass': row['show_when_glass']?.toString() ?? 'any',
      'integrated_side_cover': _truthy(row['integrated_side_cover']),
      'allows_side_cover': _truthy(row['allows_side_cover'], fallback: true),
      'allowed_with_shutter': _truthy(
        row['allowed_with_shutter'],
        fallback: true,
      ),
      'show_in_drawing': _truthy(row['show_in_drawing'], fallback: true),
      'show_in_quantity': _truthy(row['show_in_quantity'], fallback: true),
      'show_in_dialog': _truthy(row['show_in_dialog'], fallback: true),
      'width_adjust_mm': _number(row['width_adjust_mm']),
      'height_adjust_mm': _number(row['height_adjust_mm']),
      'formula_note': row['formula_note']?.toString() ?? '',
      'skip_glazing_bead': _truthy(row['skip_glazing_bead']),
      'requires_plant': _truthy(row['requires_plant']),
      'joint_length_multiplier': _number(
        row['joint_length_multiplier'],
        fallback: role == 'porte_joint' ? 2.0 : 1.0,
      ),
    });
  }

  Map<String, dynamic> _roleOptionsFor(String role, int sectionId) {
    return _roleOptionsByRoleSection.putIfAbsent(
      _roleOptionKey(role, sectionId),
      () => _defaultRoleOptions(role),
    );
  }

  void _toggleSection(String role, int sectionId, bool selected) {
    setState(() {
      final selectedIds = _sectionIdsByRole[role]!;
      if (selected) {
        selectedIds.add(sectionId);
        _defaultSectionByRole[role] ??= sectionId;
        _roleOptionsFor(role, sectionId);
      } else {
        selectedIds.remove(sectionId);
        _roleOptionsByRoleSection.remove(_roleOptionKey(role, sectionId));
        if (role == 'frame' ||
            role == 'sash' ||
            role == 'glazing_bead' ||
            role == 'porte_joint') {
          _gasketTypeBySectionPosition.remove(sectionId);
        }
        if (_defaultSectionByRole[role] == sectionId) {
          _defaultSectionByRole[role] = selectedIds.isEmpty
              ? null
              : selectedIds.first;
        }
      }
    });
  }

  String _sectionLabel(Map<String, dynamic> section) {
    final code = section['code']?.toString().trim() ?? '';
    final name = section['name']?.toString().trim() ?? '';
    return code.isEmpty ? name : '$code — $name';
  }

  Future<void> _save() async {
    if (_saving) return;
    final seriesId = _seriesId;
    if (seriesId == null) return;
    if (_sectionIdsByRole['frame']!.isEmpty) {
      _showMessage(
        _t(
          'حدد الإطار لهذه السلسلة أولاً.',
          'Choisissez d’abord le dormant de cette série.',
        ),
        isError: true,
      );
      return;
    }
    setState(() => _saving = true);

    final roles = <Map<String, dynamic>>[];
    for (final role in _availableRoles) {
      for (final sectionId in _sectionIdsByRole[role.key]!) {
        final options = _normalizedRoleOptions(
          role.key,
          _roleOptionsFor(role.key, sectionId),
        );
        roles.add({
          'role_key': role.key,
          'section_id': sectionId,
          ...options,
          'is_required': role.required,
          'is_default': _defaultSectionByRole[role.key] == sectionId,
          'is_visible': true,
        });
      }
    }
    final jointLinks = <Map<String, dynamic>>[];
    final jointPositionsByRole = <String, List<String>>{
      if (!_isSlidingSeries) 'frame': const ['frame_inner', 'frame_outer'],
      'sash': const ['sash_inner', 'sash_outer'],
      'glazing_bead': const ['parclose_gasket'],
      'porte_joint': const ['porte_joint_brosse'],
    };
    for (final entry in jointPositionsByRole.entries) {
      for (final sectionId in _sectionIdsByRole[entry.key] ?? const <int>{}) {
        final links = _gasketTypeBySectionPosition[sectionId] ?? const {};
        for (final position in entry.value) {
          final gasketType = links[position]?.trim() ?? '';
          if (gasketType.isEmpty) continue;
          jointLinks.add({
            'section_id': sectionId,
            'gasket_type': gasketType,
            'position_key': position,
            'is_default': true,
          });
        }
      }
    }
    try {
      await widget.db.saveSeriesDesignRoles(seriesId: seriesId, roles: roles);
      await widget.db.saveSectionJointLinksForSeries(
        seriesId: seriesId,
        links: jointLinks,
      );
      await widget.db.upsertSeriesTableConfig(
        seriesId: seriesId,
        allowedSectionTypes:
            _tableConfig?['allowed_section_types']?.toString() ?? '',
        allowedAccessoryIds:
            _tableConfig?['allowed_accessory_ids']?.toString() ?? '',
        allowedAccessoryTypes:
            _tableConfig?['allowed_accessory_types']?.toString() ?? '',
        excludedAccessoryIds:
            _tableConfig?['excluded_accessory_ids']?.toString() ?? '',
        sashWDeduction2: _decimal(_sashWidth2Controller),
        sashWDeduction3: _decimal(_sashWidth3Controller),
        sashWDeduction4: _decimal(_sashWidth4Controller),
        sashOverlapVal: _decimal(_sashOverlapController),
        glassWDeduction: _decimal(_glassWidthController, fallback: 10),
        slidingChicanePiecesPerJunction: _positiveInt(_chicanePiecesController),
        slidingRailClearance: _decimal(_railClearanceController, fallback: 1),
        customFormulaNotes: _formulaNotesController.text.trim(),
      );
      if (mounted) {
        _showMessage(
          _t(
            'تم حفظ تعريف مكوّنات السلسلة.',
            'Définition des composants de la série enregistrée.',
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        _showMessage(
          '${_t('تعذر الحفظ', 'Enregistrement impossible')}: $error',
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showMessage(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red.shade700 : Colors.green.shade700,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<AppSettingsProvider>();
    if (!settings.isManager) {
      return Scaffold(
        appBar: AppBar(
          title: Text(
            _t(
              'مكوّنات وحسابات السلسلة',
              'Composants et calculs de la série',
            ),
          ),
        ),
        body: Center(
          child: Text(
            _t(
              'ليس لديك صلاحية للوصول إلى إعدادات السلسلة.',
              'Vous n\'avez pas accès aux réglages de la série.',
            ),
          ),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _t('مكوّنات وحسابات السلسلة', 'Composants et calculs de la série'),
        ),
        actions: [
          if (_selectedSeries != null)
            IconButton(
              tooltip: _t('حفظ', 'Enregistrer'),
              onPressed: _saving ? null : _save,
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
            ),
        ],
      ),
      body: _loadingProfiles
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _profileSelector(),
                if (_selectedProfile != null) _seriesSelector(),
                Expanded(child: _body()),
              ],
            ),
      floatingActionButton: _selectedSeries == null
          ? null
          : FloatingActionButton.extended(
              onPressed: _saving ? null : _save,
              icon: const Icon(Icons.save_rounded),
              label: Text(_t('حفظ المكوّنات', 'Enregistrer')),
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
          _t('1. اختر البروفيل', '1. Choisissez le profil'),
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
              return ChoiceChip(
                label: Text(profile['name']?.toString() ?? ''),
                selected: profile['id'] == _selectedProfile?['id'],
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
                    'لا توجد سلاسل في هذا البروفيل.',
                    'Ce profil ne contient aucune série.',
                  ),
                )
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: _series
                      .map(
                        (series) => ChoiceChip(
                          label: Text(series['name']?.toString() ?? ''),
                          selected: series['id'] == _selectedSeries?['id'],
                          onSelected: (_) => _selectSeries(series),
                        ),
                      )
                      .toList(),
                ),
            ],
          ),
  );

  Widget _body() {
    if (_selectedSeries == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Text(
            _t(
              'اختر سلسلة، ثم حدد مقاطعها الأساسية. سيتم اعتماد صياغة الجدول لاحقًا بشكل مستقل.',
              'Choisissez une série, puis ses profils principaux. Le tableau sera configuré séparément plus tard.',
            ),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    if (_loadingDefinition) {
      return const Center(child: CircularProgressIndicator());
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _informationCard(
            icon: Icons.table_chart_rounded,
            title: _t('مكوّنات وحسابات السلسلة', 'Composants et calculs'),
            text: _t(
              'حدد المقاطع التي تستعملها السلسلة. عند اختيار سلسلة منزلقة تظهر هنا حسابات عرض الضلفة لكل حالتين أو ثلاث أو أربع ضلفات، وتستعمل في الرسم وحساب الكميات.',
              'Définissez les profils utilisés par la série. Pour une série coulissante, les calculs de largeur pour 2, 3 ou 4 ouvrants sont utilisés par le dessin et le calcul des quantités.',
            ),
          ),
          const SizedBox(height: 18),
          Text(
            _t('بروفيلات السلسلة', 'Profils de la série'),
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 4),
          Text(
            _t(
              'حدد ما تستعمله السلسلة فعلاً. يمكن اختيار أكثر من مقطع لنفس الدور؛ اضغط مطولاً على المقطع المختار لجعله الافتراضي.',
              'Sélectionnez ce que la série utilise réellement. Plusieurs profils sont possibles par rôle ; maintenez un profil sélectionné pour le définir par défaut.',
            ),
          ),
          const SizedBox(height: 12),
          if (_isSlidingSeries) ...[
            _slidingFormulaCard(),
            const SizedBox(height: 14),
          ],
          for (final role in _availableRoles) _roleCard(role),
          _aluminumJointLinksCard(),
          const SizedBox(height: 90),
        ],
      ),
    );
  }

  Widget _roleCard(_SeriesRole role) {
    final selectedIds = _sectionIdsByRole[role.key]!;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ExpansionTile(
        leading: Icon(
          role.required ? Icons.star_rounded : Icons.account_tree_outlined,
        ),
        title: Text('${_t(role.ar, role.fr)}${role.required ? ' *' : ''}'),
        subtitle: Text(
          selectedIds.isEmpty
              ? _t('غير محدد', 'Non défini')
              : _t(
                  '${selectedIds.length} مقطع محدد',
                  '${selectedIds.length} profil(s) sélectionné(s)',
                ),
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
        children: [
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: Text(_t(role.descriptionAr, role.descriptionFr)),
          ),
          const SizedBox(height: 10),
          if (_sections.isEmpty)
            Text(
              _t(
                'لا توجد مقاطع فعالة في هذه السلسلة.',
                'Aucun profil actif dans cette série.',
              ),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _sections.map((section) {
                final sectionId = (section['id'] as num?)?.toInt();
                if (sectionId == null) return const SizedBox.shrink();
                final selected = selectedIds.contains(sectionId);
                final isDefault = _defaultSectionByRole[role.key] == sectionId;
                return GestureDetector(
                  onLongPress: selected
                      ? () => setState(
                          () => _defaultSectionByRole[role.key] = sectionId,
                        )
                      : null,
                  child: FilterChip(
                    avatar: selected && isDefault
                        ? const Icon(Icons.star_rounded, size: 17)
                        : null,
                    label: Text(_sectionLabel(section)),
                    selected: selected,
                    onSelected: (value) =>
                        _toggleSection(role.key, sectionId, value),
                  ),
                );
              }).toList(),
            ),
          _selectedRoleRulesList(role),
        ],
      ),
    );
  }

  Widget _selectedRoleRulesList(_SeriesRole role) {
    final sections = _selectedSectionsForRole(role.key);
    if (sections.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _t('قواعد المقاطع المختارة', 'Règles des profils choisis'),
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          for (final section in sections) _selectedRoleRuleTile(role, section),
        ],
      ),
    );
  }

  Widget _selectedRoleRuleTile(_SeriesRole role, Map<String, dynamic> section) {
    final sectionId = (section['id'] as num?)?.toInt();
    if (sectionId == null) return const SizedBox.shrink();
    final options = _normalizedRoleOptions(
      role.key,
      _roleOptionsFor(role.key, sectionId),
    );
    final isDefault = _defaultSectionByRole[role.key] == sectionId;
    final badges = <String>[
      _usageScopeLabel(options['usage_scope']?.toString() ?? 'auto'),
      if (_roleUsesGlassRule(role.key))
        _glassRuleLabel(options['show_when_glass']?.toString() ?? 'any'),
      if (_truthy(options['integrated_side_cover']))
        _t('غطاء مدمج', 'Couvre-joint intégré'),
      if (!_truthy(options['allows_side_cover'], fallback: true))
        _t('لا يقبل كوفرجوا', 'Sans couvre-joint séparé'),
      if (!_truthy(options['allowed_with_shutter'], fallback: true))
        _t('ممنوع مع الستار', 'Interdit avec volet'),
    ];
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        dense: true,
        leading: Icon(
          isDefault ? Icons.star_rounded : Icons.rule_folder_outlined,
          color: isDefault ? Colors.amber.shade700 : null,
        ),
        title: Text(_sectionLabel(section)),
        subtitle: Text(badges.join(' • ')),
        trailing: IconButton(
          tooltip: _t('تعديل القواعد', 'Modifier les règles'),
          icon: const Icon(Icons.tune_rounded),
          onPressed: () => _editRoleOptions(role, section),
        ),
        onTap: () => _editRoleOptions(role, section),
      ),
    );
  }

  String _usageScopeLabel(String value) {
    switch (value) {
      case 'opening':
        return _t('فتح', 'Ouvrant');
      case 'sliding':
        return _t('منزلق', 'Coulissant');
      case 'both':
        return _t('فتح ومنزلق', 'Ouvrant et coulissant');
      default:
        return _t('تلقائي', 'Auto');
    }
  }

  String _glassRuleLabel(String value) {
    switch (value) {
      case 'simple':
        return _t('زجاج مفرد فقط', 'Vitrage simple seul');
      case 'double':
        return _t('زجاج مزدوج فقط', 'Double vitrage seul');
      default:
        return _t('كل أنواع الزجاج', 'Tout vitrage');
    }
  }

  Future<void> _editRoleOptions(
    _SeriesRole role,
    Map<String, dynamic> section,
  ) async {
    final sectionId = (section['id'] as num?)?.toInt();
    if (sectionId == null) return;
    final original = Map<String, dynamic>.from(
      _normalizedRoleOptions(role.key, _roleOptionsFor(role.key, sectionId)),
    );
    final widthCtrl = TextEditingController(
      text: _number(original['width_adjust_mm']).toString(),
    );
    final heightCtrl = TextEditingController(
      text: _number(original['height_adjust_mm']).toString(),
    );
    final noteCtrl = TextEditingController(
      text: original['formula_note']?.toString() ?? '',
    );
    final usesGlassRule = _roleUsesGlassRule(role.key);
    var draft = Map<String, dynamic>.from(original);
    if (!usesGlassRule) draft['show_when_glass'] = 'any';

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            void update(String key, dynamic value) {
              setDialogState(() => draft[key] = value);
            }

            return AlertDialog(
              title: Text('${_t('قواعد', 'Règles')} ${_sectionLabel(section)}'),
              content: SizedBox(
                width: 520,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      DropdownButtonFormField<String>(
                        initialValue:
                            draft['usage_scope']?.toString() ?? 'auto',
                        decoration: InputDecoration(
                          labelText: _t('استعمال المقطع', 'Utilisation'),
                        ),
                        items: [
                          DropdownMenuItem(
                            value: 'auto',
                            child: Text(_usageScopeLabel('auto')),
                          ),
                          DropdownMenuItem(
                            value: 'opening',
                            child: Text(_usageScopeLabel('opening')),
                          ),
                          DropdownMenuItem(
                            value: 'sliding',
                            child: Text(_usageScopeLabel('sliding')),
                          ),
                          DropdownMenuItem(
                            value: 'both',
                            child: Text(_usageScopeLabel('both')),
                          ),
                        ],
                        onChanged: (value) =>
                            update('usage_scope', value ?? 'auto'),
                      ),
                      const SizedBox(height: 10),
                      if (usesGlassRule)
                        DropdownButtonFormField<String>(
                          initialValue:
                              draft['show_when_glass']?.toString() ?? 'any',
                          decoration: InputDecoration(
                            labelText: _t('يظهر مع الزجاج', 'Vitrage'),
                          ),
                          items: [
                            DropdownMenuItem(
                              value: 'any',
                              child: Text(_glassRuleLabel('any')),
                            ),
                            DropdownMenuItem(
                              value: 'simple',
                              child: Text(_glassRuleLabel('simple')),
                            ),
                            DropdownMenuItem(
                              value: 'double',
                              child: Text(_glassRuleLabel('double')),
                            ),
                          ],
                          onChanged: (value) =>
                              update('show_when_glass', value ?? 'any'),
                        )
                      else
                        ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.lock_outline_rounded),
                          title: Text(
                            _t(
                              'غير مرتبط بسماكة الزجاج',
                              'Indépendant du vitrage',
                            ),
                          ),
                          subtitle: Text(
                            _t(
                              'هذا الدور لا يتغير بين زجاج مفرد ومزدوج.',
                              'Ce rôle ne change pas entre vitrage simple et double.',
                            ),
                          ),
                        ),
                      const SizedBox(height: 10),
                      _dialogSwitch(
                        title: _t('غطاء جانبي مدمج', 'Couvre-joint intégré'),
                        value: _truthy(draft['integrated_side_cover']),
                        onChanged: (value) =>
                            update('integrated_side_cover', value),
                      ),
                      _dialogSwitch(
                        title: _t(
                          'يقبل كوفرجوا منفصل',
                          'Accepte un couvre-joint séparé',
                        ),
                        value: _truthy(
                          draft['allows_side_cover'],
                          fallback: true,
                        ),
                        onChanged: (value) =>
                            update('allows_side_cover', value),
                      ),
                      _dialogSwitch(
                        title: _t('مسموح مع الستار', 'Autorisé avec volet'),
                        value: _truthy(
                          draft['allowed_with_shutter'],
                          fallback: true,
                        ),
                        onChanged: (value) =>
                            update('allowed_with_shutter', value),
                      ),
                      const Divider(height: 20),
                      if (role.key == 'sash' || role.key == 'sash_extension')
                        _dialogSwitch(
                          title: _t(
                            'هذه الضلفة بدون بيركلوز',
                            'Cet ouvrant est sans parclose',
                          ),
                          value: _truthy(draft['skip_glazing_bead']),
                          onChanged: (value) =>
                              update('skip_glazing_bead', value),
                        ),
                      if (role.key == 'porte_joint')
                        ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.link_rounded),
                          title: Text(
                            _t(
                              'يستعمل تلقائياً مع البلانت',
                              'Utilisé automatiquement avec la plinthe',
                            ),
                          ),
                          subtitle: Text(
                            _t(
                              'جوان البروس يحسب بطول ضعفي حامل الجوان.',
                              'Le joint brosse est calculé à deux fois la longueur du porte-joint.',
                            ),
                          ),
                        ),
                      if (role.key == 'sash' ||
                          role.key == 'sash_extension' ||
                          role.key == 'porte_joint')
                        const Divider(height: 20),
                      _dialogSwitch(
                        title: _t('يظهر في الرسم', 'Visible au dessin'),
                        value: _truthy(
                          draft['show_in_drawing'],
                          fallback: true,
                        ),
                        onChanged: (value) => update('show_in_drawing', value),
                      ),
                      _dialogSwitch(
                        title: _t(
                          'يظهر في جدول الكمية',
                          'Visible au tableau quantité',
                        ),
                        value: _truthy(
                          draft['show_in_quantity'],
                          fallback: true,
                        ),
                        onChanged: (value) => update('show_in_quantity', value),
                      ),
                      _dialogSwitch(
                        title: _t('يظهر في نافذة التغيير', 'Visible au choix'),
                        value: _truthy(draft['show_in_dialog'], fallback: true),
                        onChanged: (value) => update('show_in_dialog', value),
                      ),
                      const Divider(height: 20),
                      TextField(
                        controller: widthCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                          signed: true,
                          decimal: true,
                        ),
                        decoration: InputDecoration(
                          labelText: _t(
                            'تعديل العرض لهذا الدور (مم)',
                            'Correction largeur du rôle (mm)',
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: heightCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                          signed: true,
                          decimal: true,
                        ),
                        decoration: InputDecoration(
                          labelText: _t(
                            'تعديل الطول لهذا الدور (مم)',
                            'Correction hauteur du rôle (mm)',
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: noteCtrl,
                        minLines: 2,
                        maxLines: 4,
                        decoration: InputDecoration(
                          labelText: _t('ملاحظة حسابية', 'Note de calcul'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: Text(_t('إلغاء', 'Annuler')),
                ),
                FilledButton.icon(
                  onPressed: () {
                    draft = {
                      ...draft,
                      if (!usesGlassRule) 'show_when_glass': 'any',
                      'width_adjust_mm': _number(widthCtrl.text),
                      'height_adjust_mm': _number(heightCtrl.text),
                      'formula_note': noteCtrl.text.trim(),
                    };
                    Navigator.pop(dialogContext, draft);
                  },
                  icon: const Icon(Icons.check_rounded),
                  label: Text(_t('اعتماد', 'Valider')),
                ),
              ],
            );
          },
        );
      },
    );

    widthCtrl.dispose();
    heightCtrl.dispose();
    noteCtrl.dispose();

    if (!mounted) return;
    if (result == null) return;
    setState(() {
      _roleOptionsByRoleSection[_roleOptionKey(role.key, sectionId)] = result;
    });
  }

  Widget _dialogSwitch({
    required String title,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return SwitchListTile.adaptive(
      dense: true,
      contentPadding: EdgeInsets.zero,
      title: Text(title),
      value: value,
      onChanged: onChanged,
    );
  }

  Widget _slidingFormulaCard() => Card(
    color: Theme.of(context).colorScheme.primaryContainer,
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _t('حسابات ضلف النظام المنزلق', 'Calculs des ouvrants coulissants'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
          Text(
            _t(
              'أدخل تعديل العرض الخاص بهذه السلسلة لكل حالتين أو ثلاث أو أربع ضلفات. عرض الضلفة = (العرض الداخلي − القيمة) ÷ عدد الضلفات. الرقم الموجب يطرح، والرقم السالب يضيف، والصفر يستعمل الحساب القديم.',
              'Saisissez l’ajustement de largeur propre à cette série pour 2, 3 ou 4 ouvrants. Largeur = (largeur intérieure − valeur) ÷ nombre d’ouvrants. Une valeur positive retire, une valeur négative ajoute, zéro conserve l’ancien calcul.',
            ),
          ),
          const SizedBox(height: 12),
          _formulaField(
            _sashWidth2Controller,
            _t('خصم عرض ضلفتين (مم)', 'Déduction largeur 2 ouvrants (mm)'),
          ),
          _formulaField(
            _sashWidth3Controller,
            _t('خصم عرض 3 ضلفات (مم)', 'Déduction largeur 3 ouvrants (mm)'),
          ),
          _formulaField(
            _sashWidth4Controller,
            _t('خصم عرض 4 ضلفات (مم)', 'Déduction largeur 4 ouvrants (mm)'),
          ),
          _formulaField(
            _sashOverlapController,
            _t('تداخل طول الضلفة (مم)', 'Recouvrement hauteur ouvrant (mm)'),
          ),
          _formulaField(
            _glassWidthController,
            _t(
              'خصم أمان عرض الزجاج (مم)',
              'Jeu de sécurité largeur vitrage (mm)',
            ),
          ),
          _formulaField(
            _chicanePiecesController,
            _t('قطع الشيكان لكل فاصل', 'Pièces chicane par jonction'),
            integer: true,
          ),
          _formulaField(
            _railClearanceController,
            _t('خلوص تركيب السكة (مم)', 'Jeu de pose du rail (mm)'),
          ),
          TextField(
            controller: _formulaNotesController,
            minLines: 2,
            maxLines: 4,
            decoration: InputDecoration(
              labelText: _t('ملاحظة خاصة بالسلسلة', 'Note propre à la série'),
              alignLabelWithHint: true,
            ),
          ),
        ],
      ),
    ),
  );

  Widget _formulaField(
    TextEditingController controller,
    String label, {
    bool integer = false,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: TextField(
      controller: controller,
      keyboardType: TextInputType.numberWithOptions(
        signed: true,
        decimal: !integer,
      ),
      decoration: InputDecoration(labelText: label),
    ),
  );

  List<Map<String, dynamic>> _selectedSectionsForRole(String role) {
    final ids = _sectionIdsByRole[role] ?? const <int>{};
    if (ids.isEmpty) return const [];
    return _sections.where((section) {
      final sectionId = (section['id'] as num?)?.toInt();
      return sectionId != null && ids.contains(sectionId);
    }).toList();
  }

  List<String> _availableGasketTypes() {
    const preferredOrder = [
      'جوان فيتراج',
      'جوان فراب',
      'جوان سنترال',
      'جوان براش',
      'جوان بوراج',
    ];
    final types = <String>{};
    for (final joint in _joints) {
      final material = joint['type']?.toString().toLowerCase() ?? '';
      if (material.contains('pvc')) continue;
      final canonical = _canonicalGasketType(joint);
      if (canonical != null) {
        types.add(canonical);
        continue;
      }
      final rawType = joint['gasket_type']?.toString().trim() ?? '';
      if (rawType.isNotEmpty) types.add(rawType);
    }
    final sorted = types.toList()
      ..sort((a, b) {
        final aIndex = preferredOrder.indexOf(a);
        final bIndex = preferredOrder.indexOf(b);
        if (aIndex != -1 || bIndex != -1) {
          return (aIndex == -1 ? 999 : aIndex).compareTo(
            bIndex == -1 ? 999 : bIndex,
          );
        }
        return a.compareTo(b);
      });
    return sorted;
  }

  String? _canonicalGasketType(Map<String, dynamic> joint) {
    final text = '${joint['gasket_type'] ?? ''} ${joint['name'] ?? ''}'
        .toLowerCase();
    if (text.contains('فيتراج') ||
        text.contains('vitrage') ||
        text.contains('زجاج') ||
        text.contains('glass')) {
      return 'جوان فيتراج';
    }
    if (text.contains('فراب') ||
        text.contains('frappe') ||
        text.contains('ضرب')) {
      return 'جوان فراب';
    }
    if (text.contains('سنترال') ||
        text.contains('central') ||
        text.contains('وسط')) {
      return 'جوان سنترال';
    }
    if (text.contains('براش') ||
        text.contains('بروش') ||
        text.contains('بروس') ||
        text.contains('brosse') ||
        text.contains('brush') ||
        text.contains('bros')) {
      return 'جوان براش';
    }
    if (text.contains('بوراج') ||
        text.contains('bourrage') ||
        text.contains('bouraj')) {
      return 'جوان بوراج';
    }
    return null;
  }

  String _localizedGasketType(String type) {
    final text = type.trim().toLowerCase();
    final language = context.read<AppSettingsProvider>().language;

    String localized(String ar, String fr, String en) {
      switch (language) {
        case AppLanguage.arabic:
          return ar;
        case AppLanguage.french:
          return fr;
        case AppLanguage.english:
          return en;
      }
    }

    if (text.contains('فيتراج') ||
        text.contains('vitrage') ||
        text.contains('glass') ||
        text.contains('زجاج')) {
      return localized('جوان فيتراج', 'Joint vitrage', 'Glass gasket');
    }
    if (text.contains('فراب') ||
        text.contains('frappe') ||
        text.contains('strike') ||
        text.contains('ضرب')) {
      return localized('جوان فراب', 'Joint frappe', 'Strike gasket');
    }
    if (text.contains('سنترال') ||
        text.contains('central') ||
        text.contains('وسط')) {
      return localized('جوان سنترال', 'Joint central', 'Central gasket');
    }
    if (text.contains('براش') ||
        text.contains('بروش') ||
        text.contains('بروس') ||
        text.contains('brosse') ||
        text.contains('brush') ||
        text.contains('bros')) {
      return localized('جوان بروس', 'Joint brosse', 'Brush gasket');
    }
    if (text.contains('بوراج') ||
        text.contains('bourrage') ||
        text.contains('bouraj') ||
        text.contains('filler')) {
      return localized('جوان بوراج', 'Joint bourrage', 'Filler gasket');
    }
    return type;
  }

  void _setGasketTypeLink(int sectionId, String position, String? gasketType) {
    setState(() {
      final links = _gasketTypeBySectionPosition.putIfAbsent(
        sectionId,
        () => {},
      );
      final normalized = gasketType?.trim() ?? '';
      if (normalized.isEmpty) {
        links.remove(position);
        if (links.isEmpty) _gasketTypeBySectionPosition.remove(sectionId);
      } else {
        links[position] = normalized;
      }
    });
  }

  Widget _aluminumJointLinksCard() {
    final frameSections = _isSlidingSeries
        ? const <Map<String, dynamic>>[]
        : _selectedSectionsForRole('frame');
    final sashSections = _selectedSectionsForRole('sash');
    final parcloseSections = _selectedSectionsForRole('glazing_bead');
    final porteJointSections = _selectedSectionsForRole('porte_joint');
    if (frameSections.isEmpty &&
        sashSections.isEmpty &&
        parcloseSections.isEmpty &&
        porteJointSections.isEmpty) {
      return const SizedBox.shrink();
    }
    final gasketTypes = _availableGasketTypes();

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ExpansionTile(
        leading: const Icon(Icons.linear_scale_rounded),
        title: Text(_t('ربط أنواع الجوانات', 'Types de joints liés')),
        subtitle: Text(
          _t(
            _isSlidingSeries
                ? 'الضلفة المنزلقة لها جوان داخلي وخارجي، والباكلوز له جوان واحد. إطار المنزلق لا يحمل جوان في هذه السلاسل.'
                : 'إطار الفتح يمكن أن يحمل جواناً أو جوانين، والضلفة لها جوانان، والباكلوز له جوان واحد. يختار الحساب السماكة المناسبة من النوع المرتبط.',
            _isSlidingSeries
                ? 'L’ouvrant coulissant a un joint intérieur et extérieur, et la parclose un joint. Le dormant coulissant n’a pas de joint ici.'
                : 'Le dormant ouvrant peut avoir un ou deux joints, l’ouvrant deux joints, et la parclose un joint. Le calcul choisit l’épaisseur adaptée du type lié.',
          ),
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
        children: [
          if (gasketTypes.isEmpty)
            Text(
              _t(
                'لا توجد أنواع جوانات ألمنيوم في الكتالوج.',
                'Aucun type de joint aluminium dans le catalogue.',
              ),
            )
          else ...[
            _jointRoleSection(_t('الإطار', 'Dormant'), frameSections, const [
              ('frame_inner', 'جوان الإطار الداخلي', 'Joint dormant intérieur'),
              ('frame_outer', 'جوان الإطار الخارجي', 'Joint dormant extérieur'),
            ], gasketTypes),
            _jointRoleSection(_t('الضلفة', 'Ouvrant'), sashSections, const [
              ('sash_inner', 'جوان الظلفة الداخلي', 'Joint ouvrant intérieur'),
              ('sash_outer', 'جوان الظلفة الخارجي', 'Joint ouvrant extérieur'),
            ], gasketTypes),
            _jointRoleSection(
              _t('الباكلوز', 'Parclose'),
              parcloseSections,
              const [('parclose_gasket', 'جوان الباكلوز', 'Joint parclose')],
              gasketTypes,
            ),
            _jointRoleSection(
              _t('حامل الجوان', 'Porte-joint'),
              porteJointSections,
              const [
                (
                  'porte_joint_brosse',
                  'جوان بروس حامل الجوان',
                  'Joint brosse porte-joint',
                ),
              ],
              gasketTypes,
            ),
          ],
        ],
      ),
    );
  }

  Widget _jointRoleSection(
    String title,
    List<Map<String, dynamic>> sections,
    List<(String, String, String)> positions,
    List<String> gasketTypes,
  ) {
    if (sections.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          for (final section in sections)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_sectionLabel(section)),
                  const SizedBox(height: 6),
                  for (final position in positions)
                    _gasketTypeDropdown(
                      section,
                      position.$1,
                      _t(position.$2, position.$3),
                      gasketTypes,
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _gasketTypeDropdown(
    Map<String, dynamic> section,
    String position,
    String label,
    List<String> gasketTypes,
  ) {
    final sectionId = (section['id'] as num?)?.toInt();
    if (sectionId == null) return const SizedBox.shrink();
    final selected = _gasketTypeBySectionPosition[sectionId]?[position];
    final validSelected = selected != null && gasketTypes.contains(selected);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: DropdownButtonFormField<String?>(
        isExpanded: true,
        initialValue: validSelected ? selected : null,
        decoration: InputDecoration(labelText: label),
        items: [
          DropdownMenuItem<String?>(
            value: null,
            child: Text(_t('بدون ربط', 'Sans liaison')),
          ),
          ...gasketTypes.map(
            (type) => DropdownMenuItem<String?>(
              value: type,
              child: Text(_localizedGasketType(type)),
            ),
          ),
        ],
        onChanged: (type) => _setGasketTypeLink(sectionId, position, type),
      ),
    );
  }

  Widget _informationCard({
    required IconData icon,
    required String title,
    required String text,
  }) => Card(
    color: Theme.of(context).colorScheme.secondaryContainer,
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(text),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
