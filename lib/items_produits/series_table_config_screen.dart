import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../settings/app_settings.dart';
import '../sql_database.dart';

/// Application-admin-only definition of the main profile roles for each series.
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
  Map<String, dynamic>? _selectedProfile;
  Map<String, dynamic>? _selectedSeries;
  Map<String, dynamic>? _tableConfig;

  final Map<String, Set<int>> _sectionIdsByRole = {
    for (final role in _roles) role.key: <int>{},
  };
  final Map<String, int?> _defaultSectionByRole = {
    for (final role in _roles) role.key: null,
  };

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
  bool get _canAccess =>
      context.read<AppSettingsProvider>().userRole == 'admin' || isAdmin;
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

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final settings = context.watch<AppSettingsProvider>();
    if (settings.userRole != 'admin' && !isAdmin) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && Navigator.canPop(context)) Navigator.pop(context);
      });
    }
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
    ]);
    if (!mounted) return;

    final roles = results[1] as List<Map<String, dynamic>>;
    _restoreDefinition(roles);
    _restoreFormulaConfig(results[2] as Map<String, dynamic>?);
    setState(() {
      _sections = results[0] as List<Map<String, dynamic>>;
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
      if (item['is_default'] == 1 || _defaultSectionByRole[role] == null) {
        _defaultSectionByRole[role] = sectionId;
      }
    }
  }

  void _toggleSection(String role, int sectionId, bool selected) {
    setState(() {
      final selectedIds = _sectionIdsByRole[role]!;
      if (selected) {
        selectedIds.add(sectionId);
        _defaultSectionByRole[role] ??= sectionId;
      } else {
        selectedIds.remove(sectionId);
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

    final roles = <Map<String, dynamic>>[];
    for (final role in _availableRoles) {
      for (final sectionId in _sectionIdsByRole[role.key]!) {
        roles.add({
          'role_key': role.key,
          'section_id': sectionId,
          'is_required': role.required,
          'is_default': _defaultSectionByRole[role.key] == sectionId,
          'is_visible': true,
        });
      }
    }

    setState(() => _saving = true);
    try {
      await widget.db.saveSeriesDesignRoles(seriesId: seriesId, roles: roles);
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red.shade700 : Colors.green.shade700,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    context.watch<AppSettingsProvider>();
    if (!_canAccess) return const Scaffold(body: SizedBox.shrink());
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
              'حدد المقاطع التي تستعملها السلسلة. عند اختيار سلسلة منزلقة تظهر حسابات عرض الضلفة لكل حالتين أو ثلاث أو أربع ضلفات، وتستعمل في الرسم وحساب الكميات.',
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
        ],
      ),
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
              'أدخل تعديل العرض الخاص بهذه السلسلة لكل حالتين أو ثلاث أو أربع ضلفات. عرض الضلفة = (عرض النافذة − التعديل) ÷ عدد الضلفات. القيمة الموجبة طرح، والسالبة زيادة. إذا بقيت القيمة صفرًا يستعمل النظام الحساب القديم.',
              'Saisissez l’ajustement de largeur propre à cette série pour 2, 3 ou 4 ouvrants. Largeur = (largeur fenêtre − ajustement) ÷ nombre d’ouvrants. Une valeur positive soustrait, une valeur négative ajoute. Zéro conserve l’ancien calcul.',
            ),
          ),
          const SizedBox(height: 12),
          _formulaField(
            _sashWidth2Controller,
            _t('تعديل عرض ضلفتين (مم)', 'Ajustement largeur 2 ouvrants (mm)'),
          ),
          _formulaField(
            _sashWidth3Controller,
            _t('تعديل عرض 3 ضلفات (مم)', 'Ajustement largeur 3 ouvrants (mm)'),
          ),
          _formulaField(
            _sashWidth4Controller,
            _t('تعديل عرض 4 ضلفات (مم)', 'Ajustement largeur 4 ouvrants (mm)'),
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
        decimal: !integer,
        signed: !integer,
      ),
      decoration: InputDecoration(labelText: label),
    ),
  );

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
