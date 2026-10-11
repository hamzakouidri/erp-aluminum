import 'package:database_data/widgets/app_material.dart';
import 'package:provider/provider.dart';
import '../sql_database.dart';
import '../settings/app_settings.dart';

class GlassSystemsRulesScreen extends StatefulWidget {
  final SqlDatabase db;

  const GlassSystemsRulesScreen({super.key, required this.db});

  @override
  State<GlassSystemsRulesScreen> createState() =>
      _GlassSystemsRulesScreenState();
}

class _GlassSystemsRulesScreenState extends State<GlassSystemsRulesScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isLoading = true;

  // Data
  List<Map<String, dynamic>> _systems = [];
  List<Map<String, dynamic>> _kits = [];
  List<Map<String, dynamic>> _allItems = [];

  // Tab 3 state: selected system for rules
  String? _selectedSystemCode;
  List<Map<String, dynamic>> _systemRules = [];
  double _filterThickness = 0.0; // 0 = all

  bool _isCompact(BuildContext context) => MediaQuery.sizeOf(context).width < 600;

  Widget _responsivePair(
    BuildContext context,
    Widget first,
    Widget second, {
    double gap = 12,
  }) {
    if (_isCompact(context)) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [first, SizedBox(height: gap), second],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: first),
        SizedBox(width: gap),
        Expanded(child: second),
      ],
    );
  }

  String _tr(String ar, String fr, String en) {
    final lang = Provider.of<AppSettingsProvider>(
      context,
      listen: false,
    ).language;
    return switch (lang) {
      AppLanguage.french => fr,
      AppLanguage.english => en,
      _ => ar,
    };
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadAllData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadAllData() async {
    setState(() => _isLoading = true);
    await widget.db.ensureTemperedGlassSystemsAndRulesTables();
    final systems = await widget.db.getTemperedGlassSystems();
    final kits = await widget.db.getTemperedGlassKits();
    final items = await widget.db.getTemperedGlassItems();

    if (mounted) {
      setState(() {
        _systems = systems;
        _kits = kits;
        _allItems = items;
        if (_selectedSystemCode == null && systems.isNotEmpty) {
          _selectedSystemCode = systems.first['code'] as String;
        }
        _isLoading = false;
      });
      if (_selectedSystemCode != null) {
        _loadRulesForSelectedSystem();
      }
    }
  }

  Future<void> _loadRulesForSelectedSystem() async {
    if (_selectedSystemCode == null) return;
    final rules = await widget.db.getTemperedGlassSystemRules(
      _selectedSystemCode!,
      glassThicknessMm: _filterThickness > 0 ? _filterThickness : null,
    );
    if (mounted) {
      setState(() => _systemRules = rules);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final compact = _isCompact(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _tr(
            'أنظمة وقواعد كيت الزجاج المقسّى',
            'Systèmes & Règles de kits verre',
            'Glass Systems & Kit Rules',
          ),
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: compact ? 15 : 18,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        centerTitle: true,
        bottom: PreferredSize(
          preferredSize: Size.fromHeight(compact ? 56 : 72),
          child: Container(
            color: Theme.of(context).colorScheme.surface,
            child: TabBar(
              controller: _tabController,
              isScrollable: compact,
              tabAlignment: compact ? TabAlignment.start : TabAlignment.fill,
              indicatorColor: Theme.of(context).colorScheme.primary,
              indicatorWeight: 3.5,
              labelColor: Theme.of(context).colorScheme.onSurface,
              unselectedLabelColor: Theme.of(context).colorScheme.onSurfaceVariant,
              labelStyle: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
                fontFamily: 'Cairo',
              ),
              unselectedLabelStyle: const TextStyle(
                fontWeight: FontWeight.normal,
                fontSize: 13,
                fontFamily: 'Cairo',
              ),
              tabs: [
                Tab(
                  icon: compact ? null : const Icon(Icons.dashboard_customize_outlined),
                  text: _tr('الأنظمة (Systèmes)', 'Systèmes', 'Systems'),
                ),
                Tab(
                  icon: compact ? null : const Icon(Icons.architecture_outlined),
                  text: _tr(
                    'كيت الزجاج وقواعد الثقوب',
                    'Kits & Perçages',
                    'Kits & Holes',
                  ),
                ),
                Tab(
                  icon: compact ? null : const Icon(Icons.tune_outlined),
                  text: _tr(
                    'ربط النظام بالإكسسوارات',
                    'Règles du système',
                    'System Rules',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildSystemsTab(isDark),
                _buildKitsTab(isDark),
                _buildRulesTab(isDark),
              ],
            ),
    );
  }

  // ==========================================
  // TAB 1: GLASS SYSTEMS
  // ==========================================

  Widget _buildSystemsTab(bool isDark) {
    final compact = _isCompact(context);
    return Scaffold(
      floatingActionButton: compact
          ? FloatingActionButton(
              backgroundColor: Colors.teal.shade700,
              foregroundColor: Colors.white,
              tooltip: _tr('إضافة نظام جديد', 'Nouveau système', 'Add System'),
              onPressed: () => _openSystemDialog(),
              child: const Icon(Icons.add),
            )
          : FloatingActionButton.extended(
        backgroundColor: Colors.teal.shade700,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: Text(_tr('إضافة نظام جديد', 'Nouveau système', 'Add System')),
        onPressed: () => _openSystemDialog(),
      ),
      body: _systems.isEmpty
          ? Center(
              child: Text(
                _tr(
                  'لا توجد أنظمة حالياً',
                  'Aucun système trouvé',
                  'No systems found',
                ),
                style: const TextStyle(fontSize: 16, color: Colors.grey),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              itemCount: _systems.length,
              itemBuilder: (context, index) {
                final sys = _systems[index];
                final isActive = (sys['is_active'] as int? ?? 1) == 1;

                return Card(
                  elevation: 2,
                  margin: const EdgeInsets.only(bottom: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(
                      color: isActive
                          ? Colors.cyan.withValues(alpha: 0.3)
                          : Colors.grey.withValues(alpha: 0.3),
                      width: 1.2,
                    ),
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    leading: CircleAvatar(
                      backgroundColor: isActive
                          ? Colors.cyan.shade700
                          : Colors.grey.shade600,
                      foregroundColor: Colors.white,
                      child: Icon(
                        _getIconData(sys['icon_name'] as String? ?? 'shower'),
                      ),
                    ),
                    title: Wrap(
                      spacing: 8,
                      runSpacing: 5,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                          Text(
                            sys['name_ar'] as String? ?? '',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                              color: isActive ? null : Colors.grey,
                            ),
                          ),
                        if ((sys['name_fr'] as String? ?? '').isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.blueGrey.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              sys['name_fr'] as String? ?? '',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.blueGrey.shade700,
                              ),
                            ),
                          ),
                      ],
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 4),
                        Text(
                          sys['description'] as String? ?? '',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Wrap(
                          spacing: 16,
                          runSpacing: 4,
                          children: [
                            Text(
                              '${_tr('الكود', 'Code', 'Code')}: ${sys['code']}',
                              style: const TextStyle(
                                fontSize: 11,
                                fontFamily: 'monospace',
                                color: Colors.teal,
                              ),
                            ),
                            if ((sys['default_kit_code'] as String? ?? '')
                                .isNotEmpty)
                              Text(
                                '${_tr('الكيت الافتراضي', 'Kit défaut', 'Default Kit')}: ${sys['default_kit_code']}',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.cyan.shade800,
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                    trailing: compact
                        ? PopupMenuButton<String>(
                            tooltip: _tr('الإجراءات', 'Actions', 'Actions'),
                            onSelected: (value) async {
                              if (value == 'edit') {
                                _openSystemDialog(system: sys);
                              } else {
                                await widget.db.updateTemperedGlassSystem(
                                  sys['id'] as int,
                                  {'is_active': isActive ? 0 : 1},
                                );
                                _loadAllData();
                              }
                            },
                            itemBuilder: (_) => [
                              PopupMenuItem(
                                value: 'edit',
                                child: Text(_tr('تعديل', 'Modifier', 'Edit')),
                              ),
                              PopupMenuItem(
                                value: 'toggle',
                                child: Text(
                                  isActive
                                      ? _tr('تعطيل', 'Désactiver', 'Disable')
                                      : _tr('تفعيل', 'Activer', 'Enable'),
                                ),
                              ),
                            ],
                          )
                        : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(
                            Icons.edit_outlined,
                            color: Colors.teal,
                          ),
                          tooltip: _tr('تعديل', 'Modifier', 'Edit'),
                          onPressed: () => _openSystemDialog(system: sys),
                        ),
                        IconButton(
                          icon: Icon(
                            isActive ? Icons.visibility : Icons.visibility_off,
                            color: isActive ? Colors.green : Colors.grey,
                          ),
                          tooltip: isActive
                              ? _tr('مفعّل', 'Actif', 'Active')
                              : _tr('معطّل', 'Inactif', 'Inactive'),
                          onPressed: () async {
                            await widget.db.updateTemperedGlassSystem(
                              sys['id'] as int,
                              {'is_active': isActive ? 0 : 1},
                            );
                            _loadAllData();
                          },
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }

  void _openSystemDialog({Map<String, dynamic>? system}) {
    final isEdit = system != null;
    final codeCtrl = TextEditingController(
      text: system?['code'] as String? ?? '',
    );
    final nameArCtrl = TextEditingController(
      text: system?['name_ar'] as String? ?? '',
    );
    final nameFrCtrl = TextEditingController(
      text: system?['name_fr'] as String? ?? '',
    );
    final descCtrl = TextEditingController(
      text: system?['description'] as String? ?? '',
    );
    String category = system?['category'] as String? ?? 'douche';
    String iconName = system?['icon_name'] as String? ?? 'shower';
    String defaultKit = system?['default_kit_code'] as String? ?? '';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Text(
            isEdit
                ? _tr('تعديل النظام', 'Modifier le système', 'Edit System')
                : _tr('إضافة نظام جديد', 'Nouveau système', 'Add System'),
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          content: SingleChildScrollView(
            child: SizedBox(
              width: 480,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: nameArCtrl,
                    decoration: InputDecoration(
                      labelText: _tr(
                        'اسم النظام (بالعربية) *',
                        'Nom (arabe) *',
                        'Name (Arabic) *',
                      ),
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(Icons.title),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: nameFrCtrl,
                    decoration: InputDecoration(
                      labelText: _tr(
                        'اسم النظام (بالفرنسية)',
                        'Nom (français)',
                        'Name (French)',
                      ),
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(Icons.language),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: codeCtrl,
                    enabled: !isEdit,
                    decoration: InputDecoration(
                      labelText: _tr(
                        'رمز النظام الفريد (Code) *',
                        'Code unique *',
                        'Unique Code *',
                      ),
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(Icons.code),
                      helperText: isEdit
                          ? _tr(
                              'لا يمكن تغيير الرمز بعد الإنشاء',
                              'Non modifiable',
                              'Cannot change code',
                            )
                          : 'e.g. coulissante_italienne',
                    ),
                  ),
                  const SizedBox(height: 12),
                  _responsivePair(
                    ctx,
                    DropdownButtonFormField<String>(
                          value: category,
                          decoration: InputDecoration(
                            labelText: _tr('التصنيف', 'Catégorie', 'Category'),
                            border: const OutlineInputBorder(),
                          ),
                          items: [
                            DropdownMenuItem(
                              value: 'douche',
                              child: Text(_tr('كابين دوش', 'Douche', 'Shower')),
                            ),
                            DropdownMenuItem(
                              value: 'vitrine',
                              child: Text(
                                _tr('واجهة / فيترين', 'Vitrine', 'Storefront'),
                              ),
                            ),
                            DropdownMenuItem(
                              value: 'separation',
                              child: Text(
                                _tr(
                                  'فاصل مكتبي / حاجز',
                                  'Séparation',
                                  'Partition',
                                ),
                              ),
                            ),
                            DropdownMenuItem(
                              value: 'autre',
                              child: Text(_tr('أخرى', 'Autre', 'Other')),
                            ),
                          ],
                          onChanged: (v) =>
                              setDlgState(() => category = v ?? 'douche'),
                        ),
                    DropdownButtonFormField<String>(
                          value: iconName,
                          decoration: InputDecoration(
                            labelText: _tr('الأيقونة', 'Icône', 'Icon'),
                            border: const OutlineInputBorder(),
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: 'shower',
                              child: Row(
                                children: [
                                  Icon(Icons.shower),
                                  SizedBox(width: 8),
                                  Text('Shower'),
                                ],
                              ),
                            ),
                            DropdownMenuItem(
                              value: 'compare_arrows',
                              child: Row(
                                children: [
                                  Icon(Icons.compare_arrows),
                                  SizedBox(width: 8),
                                  Text('Sliding'),
                                ],
                              ),
                            ),
                            DropdownMenuItem(
                              value: 'storefront',
                              child: Row(
                                children: [
                                  Icon(Icons.storefront),
                                  SizedBox(width: 8),
                                  Text('Storefront'),
                                ],
                              ),
                            ),
                            DropdownMenuItem(
                              value: 'door_front_door_outlined',
                              child: Row(
                                children: [
                                  Icon(Icons.door_front_door_outlined),
                                  SizedBox(width: 8),
                                  Text('Door'),
                                ],
                              ),
                            ),
                            DropdownMenuItem(
                              value: 'crop_portrait',
                              child: Row(
                                children: [
                                  Icon(Icons.crop_portrait),
                                  SizedBox(width: 8),
                                  Text('Panel'),
                                ],
                              ),
                            ),
                          ],
                          onChanged: (v) =>
                              setDlgState(() => iconName = v ?? 'shower'),
                        ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: defaultKit.isEmpty ? null : defaultKit,
                    decoration: InputDecoration(
                      labelText: _tr(
                        'الكيت الافتراضي للثقوب',
                        'Kit par défaut',
                        'Default Kit',
                      ),
                      border: const OutlineInputBorder(),
                      hintText: _tr(
                        'اختر كيت افتراضي (اختياري)',
                        'Optionnel',
                        'Optional',
                      ),
                    ),
                    items: [
                      DropdownMenuItem(
                        value: null,
                        child: Text(_tr('بدون كيت محدد', 'Aucun', 'None')),
                      ),
                      ..._kits.map(
                        (k) => DropdownMenuItem(
                          value: k['code'] as String,
                          child: Text(k['name'] as String),
                        ),
                      ),
                    ],
                    onChanged: (v) => setDlgState(() => defaultKit = v ?? ''),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: descCtrl,
                    maxLines: 2,
                    decoration: InputDecoration(
                      labelText: _tr(
                        'الوصف وملاحظات الاستخدام',
                        'Description',
                        'Description',
                      ),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(_tr('إلغاء', 'Annuler', 'Cancel')),
            ),
            FilledButton.icon(
              icon: const Icon(Icons.check),
              label: Text(_tr('حفظ', 'Enregistrer', 'Save')),
              onPressed: () async {
                final nameAr = nameArCtrl.text.trim();
                final code = codeCtrl.text.trim();
                if (nameAr.isEmpty || code.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        _tr(
                          'يرجى ملء الاسم والكود',
                          'Veuillez remplir le nom et le code',
                          'Please fill name and code',
                        ),
                      ),
                    ),
                  );
                  return;
                }

                final Map<String, dynamic> row = {
                  'code': code,
                  'name_ar': nameAr,
                  'name_fr': nameFrCtrl.text.trim(),
                  'category': category,
                  'icon_name': iconName,
                  'description': descCtrl.text.trim(),
                  'default_kit_code': defaultKit,
                };

                if (isEdit) {
                  await widget.db.updateTemperedGlassSystem(
                    system['id'] as int,
                    row,
                  );
                } else {
                  row['is_active'] = 1;
                  row['display_order'] = _systems.length + 1;
                  await widget.db.insertTemperedGlassSystem(row);
                }

                if (mounted) {
                  Navigator.pop(ctx);
                  _loadAllData();
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  IconData _getIconData(String name) {
    return switch (name) {
      'shower' => Icons.shower,
      'compare_arrows' => Icons.compare_arrows,
      'storefront' => Icons.storefront,
      'door_front_door_outlined' => Icons.door_front_door_outlined,
      'crop_portrait' => Icons.crop_portrait,
      'meeting_room_outlined' => Icons.meeting_room_outlined,
      _ => Icons.widgets_outlined,
    };
  }

  // ==========================================
  // TAB 2: GLASS KITS & HOLE RULES
  // ==========================================

  Widget _buildKitsTab(bool isDark) {
    final compact = _isCompact(context);
    return Scaffold(
      floatingActionButton: compact
          ? FloatingActionButton(
              backgroundColor: Colors.cyan.shade800,
              foregroundColor: Colors.white,
              tooltip: _tr(
                'إنشاء كيت زجاج جديد',
                'Nouveau kit verre',
                'New Glass Kit',
              ),
              onPressed: () => _openKitDialog(),
              child: const Icon(Icons.add),
            )
          : FloatingActionButton.extended(
        backgroundColor: Colors.cyan.shade800,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: Text(
          _tr('إنشاء كيت زجاج جديد', 'Nouveau kit verre', 'New Glass Kit'),
        ),
        onPressed: () => _openKitDialog(),
      ),
      body: _kits.isEmpty
          ? Center(
              child: Text(
                _tr(
                  'لا توجد كيتات زجاج مسجلة',
                  'Aucun kit trouvé',
                  'No kits found',
                ),
                style: const TextStyle(fontSize: 16, color: Colors.grey),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              itemCount: _kits.length,
              itemBuilder: (context, index) {
                final kit = _kits[index];
                final kitId = kit['id'] as int;

                return FutureBuilder<List<Map<String, dynamic>>>(
                  future: widget.db.getTemperedGlassKitHoles(kitId),
                  builder: (context, snapshot) {
                    final holes = snapshot.data ?? [];

                    return Card(
                      elevation: 2,
                      margin: const EdgeInsets.only(bottom: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(
                          color: Colors.cyan.withValues(alpha: 0.3),
                          width: 1.2,
                        ),
                      ),
                      child: ExpansionTile(
                        leading: CircleAvatar(
                          backgroundColor: Colors.teal.shade700,
                          foregroundColor: Colors.white,
                          child: Text(
                            '${holes.length}',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                        title: Wrap(
                          spacing: 8,
                          runSpacing: 5,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                              Text(
                                kit['name'] as String? ?? '',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                ),
                              ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.cyan.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                '${holes.length} ${_tr('ثقوب', 'trous', 'holes')}',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.cyan.shade800,
                                ),
                              ),
                            ),
                          ],
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 3),
                            Text(
                              kit['description'] as String? ?? '',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade600,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              '${_tr('الكود', 'Code', 'Code')}: ${kit['code']} | ${_tr('اللوح المستهدف', 'Cible', 'Target')}: ${_panelRoleLabel(kit['target_panel'] as String? ?? 'door')}',
                              style: const TextStyle(
                                fontSize: 11,
                                color: Colors.blueGrey,
                              ),
                            ),
                          ],
                        ),
                        children: [
                          const Divider(height: 1),
                          // Visual diagram preview + Holes table
                          Padding(
                            padding: const EdgeInsets.all(14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 6,
                                  alignment: WrapAlignment.spaceBetween,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    SizedBox(
                                      width: compact ? double.infinity : null,
                                      child: Text(
                                        _tr(
                                          'قواعد ومواقع الثقوب في هذا الكيت:',
                                          'Règles de perçage pour ce kit :',
                                          'Hole rules for this kit:',
                                        ),
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ),
                                    Wrap(
                                      spacing: 2,
                                      crossAxisAlignment: WrapCrossAlignment.center,
                                      children: [
                                        TextButton.icon(
                                          icon: const Icon(
                                            Icons.add_circle_outline,
                                            size: 18,
                                          ),
                                          label: Text(
                                            _tr(
                                              'إضافة ثقب',
                                              'Ajouter trou',
                                              'Add Hole',
                                            ),
                                          ),
                                          onPressed: () => _openHoleDialog(
                                            kitId: kitId,
                                            existingHoles: holes,
                                          ),
                                        ),
                                        IconButton(
                                          icon: const Icon(
                                            Icons.edit,
                                            size: 18,
                                            color: Colors.teal,
                                          ),
                                          tooltip: _tr(
                                            'تعديل الكيت',
                                            'Modifier kit',
                                            'Edit Kit',
                                          ),
                                          onPressed: () =>
                                              _openKitDialog(kit: kit),
                                        ),
                                        IconButton(
                                          icon: const Icon(
                                            Icons.delete_outline,
                                            size: 18,
                                            color: Colors.red,
                                          ),
                                          tooltip: _tr(
                                            'حذف الكيت',
                                            'Supprimer kit',
                                            'Delete Kit',
                                          ),
                                          onPressed: () => _confirmDeleteKit(
                                            kitId,
                                            kit['name'] as String,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                OutlinedButton.icon(
                                  icon: const Icon(Icons.inventory_2_outlined),
                                  label: Text(
                                    _tr(
                                      'تحديد مكوّنات الكيت',
                                      'Configurer les composants du kit',
                                      'Configure kit components',
                                    ),
                                  ),
                                  onPressed: () =>
                                      _openKitComponentsDialog(kit),
                                ),
                                const SizedBox(height: 10),
                                const SizedBox(height: 10),
                                if (holes.isEmpty)
                                  Container(
                                    padding: const EdgeInsets.all(16),
                                    decoration: BoxDecoration(
                                      color: Colors.amber.withValues(
                                        alpha: 0.08,
                                      ),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: Colors.amber.withValues(
                                          alpha: 0.3,
                                        ),
                                      ),
                                    ),
                                    child: Center(
                                      child: Text(
                                        _tr(
                                          'لا توجد ثقوب مضافة لهذا الكيت بعد. اضغط "إضافة ثقب" لتعريف قواعد الثقوب.',
                                          'Aucun trou défini. Cliquez sur "Ajouter trou".',
                                          'No holes defined. Click "Add Hole".',
                                        ),
                                        style: TextStyle(
                                          color: Colors.amber.shade900,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                  )
                                else
                                  Column(
                                    children: [
                                      // Visual Preview Canvas
                                      SizedBox(
                                        height: 140,
                                        child: ClipRRect(
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                          child: CustomPaint(
                                            painter: _KitHolesPreviewPainter(
                                              holes: holes,
                                            ),
                                            size: Size.infinite,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                      // A six-column table is useful on wide
                                      // screens; on phones each hole becomes
                                      // a readable card with wrapped values.
                                      if (compact)
                                        ...holes.map(
                                          (h) => _buildCompactHoleCard(
                                            kitId,
                                            holes,
                                            h,
                                          ),
                                        )
                                      else
                                      Table(
                                        border: TableBorder.all(
                                          color: Colors.grey.withValues(
                                            alpha: 0.25,
                                          ),
                                        ),
                                        columnWidths: const {
                                          0: FixedColumnWidth(42),
                                          1: FlexColumnWidth(1.2),
                                          2: FlexColumnWidth(1.8),
                                          3: FlexColumnWidth(1.8),
                                          4: FlexColumnWidth(1.5),
                                          5: FixedColumnWidth(80),
                                        },
                                        children: [
                                          TableRow(
                                            decoration: BoxDecoration(
                                              color: Colors.cyan.withValues(
                                                alpha: 0.12,
                                              ),
                                            ),
                                            children: [
                                              _tableHead('#'),
                                              _tableHead(
                                                _tr(
                                                  'القطر',
                                                  'Ø Diamètre',
                                                  'Ø Diameter',
                                                ),
                                              ),
                                              _tableHead(
                                                _tr(
                                                  'الموقع الأفقي X',
                                                  'Position X',
                                                  'Position X',
                                                ),
                                              ),
                                              _tableHead(
                                                _tr(
                                                  'الموقع الرأسي Y',
                                                  'Position Y',
                                                  'Position Y',
                                                ),
                                              ),
                                              _tableHead(
                                                _tr(
                                                  'الشرط',
                                                  'Condition',
                                                  'Condition',
                                                ),
                                              ),
                                              _tableHead(
                                                _tr(
                                                  'إجراء',
                                                  'Action',
                                                  'Action',
                                                ),
                                              ),
                                            ],
                                          ),
                                          for (var h in holes)
                                            TableRow(
                                              children: [
                                                _tableCell(
                                                  '#${h['hole_index']}',
                                                ),
                                                _tableCell(
                                                  'Ø${(h['diameter_mm'] as num).toStringAsFixed(0)} مم',
                                                ),
                                                _tableCell(
                                                  _formatPos(
                                                    h['ref_x'] as String,
                                                    (h['offset_x_mm'] as num)
                                                        .toDouble(),
                                                    h['reference_mode']
                                                            as String? ??
                                                        'edge',
                                                  ),
                                                ),
                                                _tableCell(
                                                  _formatPos(
                                                    h['ref_y'] as String,
                                                    (h['offset_y_mm'] as num)
                                                        .toDouble(),
                                                    h['reference_mode']
                                                            as String? ??
                                                        'edge',
                                                  ),
                                                ),
                                                _tableCell(_formatCondition(h)),
                                                TableCell(
                                                  child: Row(
                                                    mainAxisAlignment:
                                                        MainAxisAlignment
                                                            .center,
                                                    children: [
                                                      IconButton(
                                                        icon: const Icon(
                                                          Icons.edit,
                                                          size: 16,
                                                          color: Colors.teal,
                                                        ),
                                                        padding:
                                                            EdgeInsets.zero,
                                                        constraints:
                                                            const BoxConstraints(),
                                                        onPressed: () =>
                                                            _openHoleDialog(
                                                              kitId: kitId,
                                                              existingHoles:
                                                                  holes,
                                                              holeToEdit: h,
                                                            ),
                                                      ),
                                                      const SizedBox(width: 8),
                                                      IconButton(
                                                        icon: const Icon(
                                                          Icons.delete,
                                                          size: 16,
                                                          color: Colors.red,
                                                        ),
                                                        padding:
                                                            EdgeInsets.zero,
                                                        constraints:
                                                            const BoxConstraints(),
                                                        onPressed: () =>
                                                            _deleteHole(
                                                              kitId,
                                                              holes,
                                                              h,
                                                            ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ],
                                            ),
                                        ],
                                      ),
                                    ],
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
    );
  }

  Widget _tableHead(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
      ),
    );
  }

  Widget _tableCell(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 12),
      ),
    );
  }

  Widget _buildCompactHoleCard(
    int kitId,
    List<Map<String, dynamic>> holes,
    Map<String, dynamic> hole,
  ) {
    final diameter = (hole['diameter_mm'] as num? ?? 0).toDouble();
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '#${hole['hole_index']} · Ø${diameter.toStringAsFixed(0)} mm',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: _tr('تعديل', 'Modifier', 'Edit'),
                  icon: const Icon(Icons.edit_outlined, color: Colors.teal),
                  onPressed: () => _openHoleDialog(
                    kitId: kitId,
                    existingHoles: holes,
                    holeToEdit: hole,
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: _tr('حذف', 'Supprimer', 'Delete'),
                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                  onPressed: () => _deleteHole(kitId, holes, hole),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'X: ${_formatPos(hole['ref_x'] as String, (hole['offset_x_mm'] as num).toDouble(), hole['reference_mode'] as String? ?? 'edge')}',
            ),
            const SizedBox(height: 3),
            Text(
              'Y: ${_formatPos(hole['ref_y'] as String, (hole['offset_y_mm'] as num).toDouble(), hole['reference_mode'] as String? ?? 'edge')}',
            ),
            const SizedBox(height: 3),
            Text(
              _formatCondition(hole),
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatPos(String ref, double offset, String mode) {
    final modeLabel = mode == 'edge'
        ? _tr('حافة', 'Bord', 'Edge')
        : _tr('مركز', 'Centre', 'Center');
    final refLabel = switch (ref) {
      'left' => _tr('اليسار', 'Gauche', 'Left'),
      'right' => _tr('اليمين', 'Droite', 'Right'),
      'top' => _tr('الأعلى', 'Haut', 'Top'),
      'bottom' => _tr('الأسفل', 'Bas', 'Bottom'),
      'center' => _tr('المنتصف', 'Centre', 'Center'),
      _ => ref,
    };
    if (ref == 'center') {
      return _tr('في المنتصف', 'Au centre', 'Centered');
    }
    return '${offset.toStringAsFixed(0)} مم من $refLabel ($modeLabel)';
  }

  String _formatCondition(Map<String, dynamic> hole) {
    final minW = (hole['min_panel_width_mm'] as num? ?? 0).toDouble();
    final target = _panelRoleLabel(hole['target_panel']?.toString() ?? 'door');
    if (minW > 0) {
      return '$target · ${_tr('إذا كان العرض ≥', 'Si largeur ≥', 'If width ≥')} ${minW.toStringAsFixed(0)} مم';
    }
    return '$target · ${_tr('دائماً', 'Toujours', 'Always')}';
  }

  String _panelRoleLabel(String role) {
    return switch (role) {
      'door' => _tr('لوح الباب', 'Porte', 'Door'),
      'fixed' => _tr('لوح ثابت', 'Fixe', 'Fixed'),
      _ => _tr('الجميع', 'Tous', 'All'),
    };
  }

  String _componentTypeForCategory(String category) {
    return switch (category) {
      'joint' => 'joint',
      'profile' => 'profile',
      'poignee' => 'handle',
      'charniere' => 'hinge',
      'fixation' => 'fixation',
      'serrure' => 'lock',
      _ => 'accessory',
    };
  }

  String _defaultTargetForCategory(String category) {
    return switch (category) {
      'poignee' || 'charniere' || 'serrure' => 'door',
      'profile' => 'fixed',
      _ => 'all',
    };
  }

  Future<void> _openKitComponentsDialog(Map<String, dynamic> kit) async {
    final kitId = kit['id'] as int;
    final saved = await widget.db.getTemperedGlassKitComponents(kitId);
    if (!mounted) return;
    final selected = <int, Map<String, dynamic>>{
      for (final row in saved)
        (row['item_id'] as num).toInt(): Map<String, dynamic>.from(row),
    };
    final categories = <String>[
      'joint',
      'profile',
      'poignee',
      'charniere',
      'fixation',
      'serrure',
      'autre',
    ];

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          title: Text(
            '${_tr('مكوّنات الكيت', 'Composants du kit', 'Kit components')} - ${kit['name']}',
          ),
          content: SizedBox(
            width: 620,
            height: MediaQuery.sizeOf(ctx).height * .72,
            child: ListView(
              children: categories.expand((category) {
                final items = _allItems
                    .where((item) => item['category'] == category)
                    .toList();
                if (items.isEmpty) return <Widget>[];
                return <Widget>[
                  Padding(
                    padding: const EdgeInsets.only(top: 10, bottom: 4),
                    child: Text(
                      category == 'joint'
                          ? _tr('الجوانات', 'Joints', 'Gaskets')
                          : category == 'profile'
                          ? _tr(
                              'الرايلات والبروفيلات',
                              'Rails et profilés',
                              'Rails and profiles',
                            )
                          : category == 'poignee'
                          ? _tr('المقابض', 'Poignées', 'Handles')
                          : category == 'charniere'
                          ? _tr('المفصلات', 'Charnières', 'Hinges')
                          : _tr(
                              'ملحقات أخرى',
                              'Autres accessoires',
                              'Other accessories',
                            ),
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.cyan.shade800,
                      ),
                    ),
                  ),
                  ...items.map((item) {
                    final itemId = (item['id'] as num).toInt();
                    final row = selected[itemId];
                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 3),
                      child: Column(
                        children: [
                          CheckboxListTile(
                            dense: true,
                            value: row != null,
                            title: Text(item['name']?.toString() ?? ''),
                            subtitle: Text(
                              item['notes']?.toString() ?? '',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            onChanged: (value) => setDlgState(() {
                              if (value == true) {
                                selected[itemId] = {
                                  'item_id': itemId,
                                  'component_type': _componentTypeForCategory(
                                    category,
                                  ),
                                  'target_panel': _defaultTargetForCategory(
                                    category,
                                  ),
                                  'quantity': 1.0,
                                  'glass_thickness_mm': 0.0,
                                  'is_default': 1,
                                  'notes': '',
                                };
                              } else {
                                selected.remove(itemId);
                              }
                            }),
                          ),
                          if (row != null)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                              child: _isCompact(ctx)
                                  ? Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        DropdownButtonFormField<String>(
                                          value:
                                              row['target_panel']?.toString() ??
                                              'all',
                                          isExpanded: true,
                                          decoration: InputDecoration(
                                            labelText: _tr(
                                              'مكان التركيب',
                                              'Panneau cible',
                                              'Target panel',
                                            ),
                                            isDense: true,
                                          ),
                                          items: [
                                            DropdownMenuItem(
                                              value: 'door',
                                              child: Text(
                                                _panelRoleLabel('door'),
                                              ),
                                            ),
                                            DropdownMenuItem(
                                              value: 'fixed',
                                              child: Text(
                                                _panelRoleLabel('fixed'),
                                              ),
                                            ),
                                            DropdownMenuItem(
                                              value: 'all',
                                              child: Text(
                                                _panelRoleLabel('all'),
                                              ),
                                            ),
                                          ],
                                          onChanged: (value) => setDlgState(
                                            () => row['target_panel'] =
                                                value ?? 'all',
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        Row(
                                          children: [
                                            Expanded(
                                              child: _kitQuantityField(row),
                                            ),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: _kitThicknessField(row),
                                            ),
                                          ],
                                        ),
                                      ],
                                    )
                                  : Row(
                                      children: [
                                        Expanded(
                                          child: DropdownButtonFormField<String>(
                                      value:
                                          row['target_panel']?.toString() ??
                                          'all',
                                      isExpanded: true,
                                      decoration: InputDecoration(
                                        labelText: _tr(
                                          'مكان التركيب',
                                          'Panneau cible',
                                          'Target panel',
                                        ),
                                        isDense: true,
                                      ),
                                      items: [
                                        DropdownMenuItem(
                                          value: 'door',
                                          child: Text(_panelRoleLabel('door')),
                                        ),
                                        DropdownMenuItem(
                                          value: 'fixed',
                                          child: Text(_panelRoleLabel('fixed')),
                                        ),
                                        DropdownMenuItem(
                                          value: 'all',
                                          child: Text(_panelRoleLabel('all')),
                                        ),
                                      ],
                                      onChanged: (value) => setDlgState(
                                        () => row['target_panel'] =
                                            value ?? 'all',
                                      ),
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        SizedBox(
                                          width: 105,
                                          child: _kitQuantityField(row),
                                        ),
                                        const SizedBox(width: 10),
                                        SizedBox(
                                          width: 115,
                                          child: _kitThicknessField(row),
                                        ),
                                      ],
                                    ),
                            ),
                        ],
                      ),
                    );
                  }),
                ];
              }).toList(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(_tr('إلغاء', 'Annuler', 'Cancel')),
            ),
            FilledButton.icon(
              icon: const Icon(Icons.save_outlined),
              label: Text(_tr('حفظ', 'Enregistrer', 'Save')),
              onPressed: () async {
                await widget.db.saveTemperedGlassKitComponents(
                  kitId,
                  selected.values.toList(),
                );
                if (ctx.mounted) Navigator.pop(ctx);
                if (mounted) setState(() {});
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _kitQuantityField(Map<String, dynamic> row) {
    return TextFormField(
      initialValue: (row['quantity'] as num? ?? 1).toString(),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        labelText: _tr('الكمية', 'Quantité', 'Quantity'),
        isDense: true,
      ),
      onChanged: (value) => row['quantity'] =
          double.tryParse(value.replaceAll(',', '.')) ?? 1.0,
    );
  }

  Widget _kitThicknessField(Map<String, dynamic> row) {
    return TextFormField(
      initialValue: (row['glass_thickness_mm'] as num? ?? 0).toString(),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        labelText: _tr('سمك الزجاج', 'Épaisseur', 'Thickness'),
        suffixText: 'mm',
        isDense: true,
      ),
      onChanged: (value) => row['glass_thickness_mm'] =
          double.tryParse(value.replaceAll(',', '.')) ?? 0.0,
    );
  }

  void _openKitDialog({Map<String, dynamic>? kit}) {
    final isEdit = kit != null;
    final nameCtrl = TextEditingController(text: kit?['name'] as String? ?? '');
    final codeCtrl = TextEditingController(text: kit?['code'] as String? ?? '');
    final descCtrl = TextEditingController(
      text: kit?['description'] as String? ?? '',
    );
    String targetPanel = kit?['target_panel'] as String? ?? 'door';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Text(
            isEdit
                ? _tr('تعديل الكيت', 'Modifier kit', 'Edit Kit')
                : _tr(
                    'إنشاء كيت زجاج جديد',
                    'Nouveau kit verre',
                    'New Glass Kit',
                  ),
          ),
          content: SingleChildScrollView(
            child: SizedBox(
              width: 440,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: nameCtrl,
                    decoration: InputDecoration(
                      labelText: _tr(
                        'اسم الكيت *',
                        'Nom du kit *',
                        'Kit Name *',
                      ),
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(Icons.hardware),
                      hintText: 'e.g. كيت ألفا (Kit Alfa)',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: codeCtrl,
                    enabled: !isEdit,
                    decoration: InputDecoration(
                      labelText: _tr(
                        'رمز الكيت الفريد (Code) *',
                        'Code unique *',
                        'Kit Code *',
                      ),
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(Icons.qr_code),
                      hintText: 'kit_alfa',
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: const {'door', 'fixed', 'all'}.contains(targetPanel)
                        ? targetPanel
                        : 'door',
                    decoration: InputDecoration(
                      labelText: _tr(
                        'اللوح المستهدف للثقب',
                        'Panneau cible',
                        'Target Panel',
                      ),
                      border: const OutlineInputBorder(),
                    ),
                    items: [
                      DropdownMenuItem(
                        value: 'door',
                        child: Text(
                          _tr('لوح الباب (Door)', 'Porte', 'Door panel'),
                        ),
                      ),
                      DropdownMenuItem(
                        value: 'fixed',
                        child: Text(
                          _tr('اللوح الثابت (Fixed)', 'Fixe', 'Fixed panel'),
                        ),
                      ),
                      DropdownMenuItem(
                        value: 'all',
                        child: Text(
                          _tr('جميع الألواح', 'Tous panneaux', 'All panels'),
                        ),
                      ),
                    ],
                    onChanged: (v) =>
                        setDlgState(() => targetPanel = v ?? 'door'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: descCtrl,
                    maxLines: 2,
                    decoration: InputDecoration(
                      labelText: _tr('الوصف', 'Description', 'Description'),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(_tr('إلغاء', 'Annuler', 'Cancel')),
            ),
            FilledButton.icon(
              icon: const Icon(Icons.check),
              label: Text(_tr('حفظ', 'Enregistrer', 'Save')),
              onPressed: () async {
                final name = nameCtrl.text.trim();
                final code = codeCtrl.text.trim();
                if (name.isEmpty || code.isEmpty) return;

                final Map<String, dynamic> row = {
                  'code': code,
                  'name': name,
                  'target_panel': targetPanel,
                  'description': descCtrl.text.trim(),
                };

                if (isEdit) {
                  await widget.db.updateTemperedGlassKit(kit['id'] as int, row);
                } else {
                  row['is_active'] = 1;
                  await widget.db.insertTemperedGlassKit(row);
                }

                if (mounted) {
                  Navigator.pop(ctx);
                  _loadAllData();
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  void _openHoleDialog({
    required int kitId,
    required List<Map<String, dynamic>> existingHoles,
    Map<String, dynamic>? holeToEdit,
  }) {
    final isEdit = holeToEdit != null;
    final diameterCtrl = TextEditingController(
      text: (holeToEdit?['diameter_mm'] as num? ?? 20.0).toStringAsFixed(0),
    );
    final offsetXCtrl = TextEditingController(
      text: (holeToEdit?['offset_x_mm'] as num? ?? 80.0).toStringAsFixed(0),
    );
    final offsetYCtrl = TextEditingController(
      text: (holeToEdit?['offset_y_mm'] as num? ?? 35.0).toStringAsFixed(0),
    );
    final minWidthCtrl = TextEditingController(
      text: (holeToEdit?['min_panel_width_mm'] as num? ?? 0.0) > 0
          ? (holeToEdit!['min_panel_width_mm'] as num).toStringAsFixed(0)
          : '',
    );

    String refX = holeToEdit?['ref_x'] as String? ?? 'left';
    String refY = holeToEdit?['ref_y'] as String? ?? 'top';
    String refMode = holeToEdit?['reference_mode'] as String? ?? 'edge';
    String targetPanel = holeToEdit?['target_panel'] as String? ?? 'door';
    String rawPurpose = holeToEdit?['purpose'] as String? ?? 'kit_roller';

    // Normalize or map specific purposes (e.g. door_top_center, door_top_left, etc.) to valid dropdown keys
    String purpose = rawPurpose;
    const standardPurposes = {
      'kit_roller',
      'hinge',
      'clamp',
      'handle',
      'pivot',
      'other',
    };
    if (!standardPurposes.contains(purpose)) {
      if (purpose.contains('door_top') || purpose.contains('roller')) {
        purpose = 'kit_roller';
      } else if (purpose.contains('hinge')) {
        purpose = 'hinge';
      } else if (purpose.contains('clamp')) {
        purpose = 'clamp';
      } else if (purpose.contains('handle')) {
        purpose = 'handle';
      } else if (purpose.contains('pivot')) {
        purpose = 'pivot';
      } else {
        purpose = 'other';
      }
    }

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Text(
            isEdit
                ? _tr('تعديل قاعدة الثقب', 'Modifier trou', 'Edit Hole Rule')
                : _tr('إضافة ثقب جديد للكيت', 'Nouveau trou', 'Add Hole Rule'),
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          content: SingleChildScrollView(
            child: SizedBox(
              width: 480,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Diameter
                  TextField(
                    controller: diameterCtrl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: _tr(
                        'قطر الثقب (Ø مم) *',
                        'Diamètre (mm) *',
                        'Diameter (mm) *',
                      ),
                      border: const OutlineInputBorder(),
                      suffixText: 'مم',
                      prefixIcon: const Icon(Icons.circle_outlined),
                      helperText: 'e.g. 20 مم للرولمان أو 12 مم للمقبض',
                    ),
                  ),
                  const SizedBox(height: 14),

                  DropdownButtonFormField<String>(
                    value: const {'door', 'fixed', 'all'}.contains(targetPanel)
                        ? targetPanel
                        : 'door',
                    decoration: InputDecoration(
                      labelText: _tr(
                        'اللوح الذي يستقبل الثقب',
                        'Panneau recevant le trou',
                        'Hole target panel',
                      ),
                      border: const OutlineInputBorder(),
                    ),
                    items: [
                      DropdownMenuItem(
                        value: 'door',
                        child: Text(_tr('الباب', 'Porte', 'Door')),
                      ),
                      DropdownMenuItem(
                        value: 'fixed',
                        child: Text(_tr('الثابت', 'Fixe', 'Fixed panel')),
                      ),
                      DropdownMenuItem(
                        value: 'all',
                        child: Text(
                          _tr(
                            'الباب والثابت',
                            'Porte et fixe',
                            'Door and fixed',
                          ),
                        ),
                      ),
                    ],
                    onChanged: (value) =>
                        setDlgState(() => targetPanel = value ?? 'door'),
                  ),
                  const SizedBox(height: 14),

                  // Reference Mode: Edge vs Center
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.cyan.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: Colors.cyan.withValues(alpha: 0.2),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _tr(
                            'طريقة حساب المسافة:',
                            'Mode de mesure :',
                            'Measurement reference mode:',
                          ),
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 6),
                        if (_isCompact(ctx)) ...[
                          RadioListTile<String>(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            title: Text(
                              _tr(
                                'من حافة الزجاج إلى حافة الثقب',
                                'Bord à bord',
                                'Edge to edge',
                              ),
                              style: const TextStyle(fontSize: 12),
                            ),
                            value: 'edge',
                            groupValue: refMode,
                            onChanged: (v) =>
                                setDlgState(() => refMode = v!),
                          ),
                          RadioListTile<String>(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            title: Text(
                              _tr(
                                'إلى مركز الثقب (Axes)',
                                'Au centre',
                                'To hole center',
                              ),
                              style: const TextStyle(fontSize: 12),
                            ),
                            value: 'center',
                            groupValue: refMode,
                            onChanged: (v) =>
                                setDlgState(() => refMode = v!),
                          ),
                        ] else
                          Row(
                            children: [
                              Expanded(
                                child: RadioListTile<String>(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                title: Text(
                                  _tr(
                                    'من حافة الزجاج إلى حافة الثقب',
                                    'Bord à bord',
                                    'Edge to edge',
                                  ),
                                  style: const TextStyle(fontSize: 12),
                                ),
                                value: 'edge',
                                groupValue: refMode,
                                onChanged: (v) =>
                                    setDlgState(() => refMode = v!),
                              ),
                            ),
                              Expanded(
                                child: RadioListTile<String>(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                title: Text(
                                  _tr(
                                    'إلى مركز الثقب (Axes)',
                                    'Au centre',
                                    'To hole center',
                                  ),
                                  style: const TextStyle(fontSize: 12),
                                ),
                                value: 'center',
                                groupValue: refMode,
                                onChanged: (v) =>
                                    setDlgState(() => refMode = v!),
                              ),
                            ),
                            ],
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

                  // X position
                  _responsivePair(
                    ctx,
                    DropdownButtonFormField<String>(
                          value:
                              const {'left', 'right', 'center'}.contains(refX)
                              ? refX
                              : 'left',
                          decoration: InputDecoration(
                            labelText: _tr(
                              'المرجع الأفقي X',
                              'Référence X',
                              'X Reference',
                            ),
                            border: const OutlineInputBorder(),
                          ),
                          items: [
                            DropdownMenuItem(
                              value: 'left',
                              child: Text(
                                _tr('من اليسار', 'Gauche', 'From Left'),
                              ),
                            ),
                            DropdownMenuItem(
                              value: 'right',
                              child: Text(
                                _tr('من اليمين', 'Droite', 'From Right'),
                              ),
                            ),
                            DropdownMenuItem(
                              value: 'center',
                              child: Text(
                                _tr('في المنتصف', 'Au centre', 'Center'),
                              ),
                            ),
                          ],
                          onChanged: (v) =>
                              setDlgState(() => refX = v ?? 'left'),
                        ),
                    TextField(
                          controller: offsetXCtrl,
                          enabled: refX != 'center',
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: _tr(
                              'المسافة الأفقية (مم)',
                              'Distance X (mm)',
                              'X Offset (mm)',
                            ),
                            border: const OutlineInputBorder(),
                            suffixText: 'مم',
                          ),
                        ),
                  ),
                  const SizedBox(height: 14),

                  // Y position
                  _responsivePair(
                    ctx,
                    DropdownButtonFormField<String>(
                          value:
                              const {'top', 'bottom', 'center'}.contains(refY)
                              ? refY
                              : 'top',
                          decoration: InputDecoration(
                            labelText: _tr(
                              'المرجع الرأسي Y',
                              'Référence Y',
                              'Y Reference',
                            ),
                            border: const OutlineInputBorder(),
                          ),
                          items: [
                            DropdownMenuItem(
                              value: 'top',
                              child: Text(
                                _tr('من الأعلى', 'Du haut', 'From Top'),
                              ),
                            ),
                            DropdownMenuItem(
                              value: 'bottom',
                              child: Text(
                                _tr('من الأسفل', 'Du bas', 'From Bottom'),
                              ),
                            ),
                            DropdownMenuItem(
                              value: 'center',
                              child: Text(
                                _tr('في المنتصف', 'Au centre', 'Center'),
                              ),
                            ),
                          ],
                          onChanged: (v) =>
                              setDlgState(() => refY = v ?? 'top'),
                        ),
                    TextField(
                          controller: offsetYCtrl,
                          enabled: refY != 'center',
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: _tr(
                              'المسافة الرأسية (مم)',
                              'Distance Y (mm)',
                              'Y Offset (mm)',
                            ),
                            border: const OutlineInputBorder(),
                            suffixText: 'مم',
                          ),
                        ),
                  ),
                  const SizedBox(height: 14),

                  // Width condition
                  TextField(
                    controller: minWidthCtrl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: _tr(
                        'شرط العرض الأدنى للوح (مم) - اختياري',
                        'Largeur min du panneau (mm)',
                        'Min panel width condition (mm)',
                      ),
                      border: const OutlineInputBorder(),
                      suffixText: 'مم',
                      helperText: _tr(
                        'مثال: 1200 مم لإضافة ثقب ثالث فقط إذا كان الباب كبيراً',
                        'Ex: 1200 mm pour ajouter un 3ème trou si la porte est large',
                        'Ex: 1200 mm to add a 3rd hole only for wide panels',
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Purpose
                  DropdownButtonFormField<String>(
                    value:
                        const {
                          'kit_roller',
                          'hinge',
                          'clamp',
                          'handle',
                          'pivot',
                          'other',
                        }.contains(purpose)
                        ? purpose
                        : 'other',
                    decoration: InputDecoration(
                      labelText: _tr(
                        'الغرض من الثقب',
                        'Fonction du trou',
                        'Hole purpose',
                      ),
                      border: const OutlineInputBorder(),
                    ),
                    items: [
                      DropdownMenuItem(
                        value: 'kit_roller',
                        child: Text(
                          _tr(
                            'رولمان / سكة الكيت',
                            'Roulette de kit',
                            'Kit roller',
                          ),
                        ),
                      ),
                      DropdownMenuItem(
                        value: 'hinge',
                        child: Text(_tr('مفصلة باب', 'Charnière', 'Hinge')),
                      ),
                      DropdownMenuItem(
                        value: 'clamp',
                        child: Text(
                          _tr('مشبك تثبيت', 'Pince de fixation', 'Clamp'),
                        ),
                      ),
                      DropdownMenuItem(
                        value: 'handle',
                        child: Text(_tr('مقبض يدوي', 'Poignée', 'Handle')),
                      ),
                      DropdownMenuItem(
                        value: 'pivot',
                        child: Text(_tr('محور دوران', 'Pivot', 'Pivot')),
                      ),
                      DropdownMenuItem(
                        value: 'other',
                        child: Text(_tr('أخرى', 'Autre', 'Other')),
                      ),
                    ],
                    onChanged: (v) =>
                        setDlgState(() => purpose = v ?? 'kit_roller'),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(_tr('إلغاء', 'Annuler', 'Cancel')),
            ),
            FilledButton.icon(
              icon: const Icon(Icons.check),
              label: Text(_tr('حفظ القاعدة', 'Enregistrer', 'Save')),
              onPressed: () async {
                final diam = double.tryParse(diameterCtrl.text.trim()) ?? 20.0;
                final offX = double.tryParse(offsetXCtrl.text.trim()) ?? 0.0;
                final offY = double.tryParse(offsetYCtrl.text.trim()) ?? 0.0;
                final minW = double.tryParse(minWidthCtrl.text.trim()) ?? 0.0;

                final newHole = {
                  'diameter_mm': diam,
                  'ref_x': refX,
                  'offset_x_mm': offX,
                  'ref_y': refY,
                  'offset_y_mm': offY,
                  'reference_mode': refMode,
                  'min_panel_width_mm': minW,
                  'max_panel_width_mm': 0.0,
                  'purpose': purpose,
                  'target_panel': targetPanel,
                };

                final updatedHoles = List<Map<String, dynamic>>.from(
                  existingHoles,
                );
                if (isEdit) {
                  final idx = updatedHoles.indexWhere(
                    (h) => h['id'] == holeToEdit['id'],
                  );
                  if (idx != -1) {
                    updatedHoles[idx] = newHole;
                  }
                } else {
                  updatedHoles.add(newHole);
                }

                await widget.db.saveTemperedGlassKitHoles(kitId, updatedHoles);
                if (mounted) {
                  Navigator.pop(ctx);
                  setState(() {});
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteHole(
    int kitId,
    List<Map<String, dynamic>> holes,
    Map<String, dynamic> holeToDelete,
  ) async {
    final updatedHoles = holes
        .where((h) => h['id'] != holeToDelete['id'])
        .toList();
    await widget.db.saveTemperedGlassKitHoles(kitId, updatedHoles);
    setState(() {});
  }

  Future<void> _confirmDeleteKit(int kitId, String name) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          _tr('تأكيد الحذف', 'Confirmer la suppression', 'Confirm Deletion'),
        ),
        content: Text(
          '${_tr('هل تريد حذف الكيت', 'Supprimer le kit', 'Delete kit')} "$name"؟',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(_tr('إلغاء', 'Annuler', 'Cancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(_tr('حذف', 'Supprimer', 'Delete')),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await widget.db.deleteTemperedGlassKit(kitId);
      _loadAllData();
    }
  }

  // ==========================================
  // TAB 3: SYSTEM RULES & ACCESSORY LINKING
  // ==========================================

  Widget _buildRulesTab(bool isDark) {
    if (_systems.isEmpty) {
      return Center(
        child: Text(_tr('لا توجد أنظمة', 'Aucun système', 'No systems')),
      );
    }

    final selectedSys = _systems.firstWhere(
      (s) => s['code'] == _selectedSystemCode,
      orElse: () => _systems.first,
    );

    return Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // System Selector Header Card
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: Colors.cyan.shade800,
                      foregroundColor: Colors.white,
                      radius: 22,
                      child: Icon(
                        _getIconData(
                          selectedSys['icon_name'] as String? ?? 'shower',
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _tr(
                              'النظام المحدد للتهيئة والقواعد:',
                              'Système sélectionné :',
                              'Configuring rules for:',
                            ),
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade600,
                            ),
                          ),
                          DropdownButton<String>(
                            value: _selectedSystemCode,
                            isExpanded: true,
                            underline: const SizedBox(),
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: isDark ? Colors.white : Colors.black87,
                            ),
                            items: _systems.map((s) {
                              return DropdownMenuItem<String>(
                                value: s['code'] as String,
                                child: Text('${s['name_ar']} (${s['code']})'),
                              );
                            }).toList(),
                            onChanged: (val) {
                              if (val != null) {
                                setState(() => _selectedSystemCode = val);
                                _loadRulesForSelectedSystem();
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),

            // Section 1: Active Kits for this System
            _buildRuleSectionHeader(
              icon: Icons.architecture,
              title: _tr(
                'الكيتات المتاحة لهذا النظام',
                'Kits compatibles avec ce système',
                'Compatible Kits',
              ),
              subtitle: _tr(
                'حدد ما إذا كان كيت ألفا، بيتا، إلخ يظهر عند اختيار هذا النظام',
                'Activez les kits qui seront proposés pour ce système',
                'Select kits offered when this system is chosen',
              ),
            ),
            _buildKitsLinkingList(),
            const SizedBox(height: 20),

            // Section 2: Active Handles (Door & Towel)
            _buildRuleSectionHeader(
              icon: Icons.pan_tool_alt_outlined,
              title: _tr(
                'المقابض ومقابض المناشف المتاحة',
                'Poignées et porte-serviettes actifs',
                'Active Handles & Towel Bars',
              ),
              subtitle: _tr(
                'المقابض المفعلة هنا ستظهر في واجهة كابينة الدوش/الفيترين لاختيارها مباشرة',
                'Les poignées cochées apparaîtront dans le tiroir d\'accessoires',
                'Checked handles will appear in the screen drawer for quick selection',
              ),
            ),
            _buildItemsLinkingList(category: 'poignee', ruleType: 'handle'),
            const SizedBox(height: 20),

            // Section 3: Profiles & Rails (by Glass Thickness: 8mm, 10mm, 12mm)
            _buildRuleSectionHeader(
              icon: Icons.view_sidebar_outlined,
              title: _tr(
                'القطاعات والسكك حسب سمك الزجاج',
                'Profilés & Rails selon l\'épaisseur de verre',
                'Profiles & Rails by Glass Thickness',
              ),
              subtitle: _tr(
                'تحديد قطاعات U والسكك التي تعتمد حصرياً على سمك الزجاج المختار (8 مم، 10 مم، 12 مم)',
                'Profilés adaptés à chaque épaisseur (8mm, 10mm, 12mm)',
                'Profiles tailored to glass thickness (8mm, 10mm, 12mm)',
              ),
            ),
            _buildThicknessFilterChips(),
            const SizedBox(height: 8),
            _buildProfilesLinkingList(),
            const SizedBox(height: 20),

            // Section 4: Hinges, Clamps & Gaskets
            _buildRuleSectionHeader(
              icon: Icons.handyman_outlined,
              title: _tr(
                'المفصلات والمشابك والجوانات',
                'Charnières, fixations & joints',
                'Hinges, Clamps & Seals',
              ),
              subtitle: _tr(
                'المشابك والجوانات التابعة لهذا النظام',
                'Accessoires de fixation et joints pour ce système',
                'Mounting clamps and sealing gaskets for this system',
              ),
            ),
            _buildItemsLinkingList(
              category: 'charniere',
              ruleType: 'charniere',
            ),
            const SizedBox(height: 8),
            _buildItemsLinkingList(category: 'joint', ruleType: 'joint'),
            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }

  Widget _buildRuleSectionHeader({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20, color: Colors.cyan.shade800),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          subtitle,
          style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600),
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _buildThicknessFilterChips() {
    return Wrap(
      spacing: 8,
      children: [
        FilterChip(
          label: Text(
            _tr('جميع السماكات', 'Toutes épaisseurs', 'All thicknesses'),
          ),
          selected: _filterThickness == 0.0,
          onSelected: (val) {
            setState(() => _filterThickness = 0.0);
            _loadRulesForSelectedSystem();
          },
        ),
        FilterChip(
          label: const Text('8 مم (8 mm)'),
          selected: _filterThickness == 8.0,
          onSelected: (val) {
            setState(() => _filterThickness = val ? 8.0 : 0.0);
            _loadRulesForSelectedSystem();
          },
        ),
        FilterChip(
          label: const Text('10 مم (10 mm)'),
          selected: _filterThickness == 10.0,
          onSelected: (val) {
            setState(() => _filterThickness = val ? 10.0 : 0.0);
            _loadRulesForSelectedSystem();
          },
        ),
        FilterChip(
          label: const Text('12 مم (12 mm)'),
          selected: _filterThickness == 12.0,
          onSelected: (val) {
            setState(() => _filterThickness = val ? 12.0 : 0.0);
            _loadRulesForSelectedSystem();
          },
        ),
      ],
    );
  }

  Widget _buildKitsLinkingList() {
    if (_kits.isEmpty) {
      return Text(_tr('لا توجد كيتات مضافة', 'Aucun kit', 'No kits'));
    }

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Column(
        children: _kits.map((kit) {
          final kitId = kit['id'] as int;
          final isLinked = _systemRules.any(
            (r) => r['kit_id'] == kitId && (r['is_active'] as int? ?? 1) == 1,
          );

          return CheckboxListTile(
            dense: true,
            title: Text(
              kit['name'] as String,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              '${kit['code']} - ${kit['description'] ?? ''}',
              style: const TextStyle(fontSize: 11),
            ),
            value: isLinked,
            activeColor: Colors.teal.shade700,
            onChanged: (val) async {
              await widget.db.toggleTemperedGlassSystemRule(
                systemCode: _selectedSystemCode!,
                kitId: kitId,
                ruleType: 'kit',
                isActive: val ?? false,
              );
              _loadRulesForSelectedSystem();
            },
          );
        }).toList(),
      ),
    );
  }

  Widget _buildItemsLinkingList({
    required String category,
    required String ruleType,
  }) {
    final items = _allItems.where((i) => i['category'] == category).toList();
    if (items.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(8.0),
        child: Text(
          _tr(
            'لا توجد عناصر مسجلة في هذا التصنيف',
            'Aucun élément trouvé',
            'No items found',
          ),
        ),
      );
    }

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Column(
        children: items.map((item) {
          final itemId = item['id'] as int;
          final isLinked = _systemRules.any(
            (r) => r['item_id'] == itemId && (r['is_active'] as int? ?? 1) == 1,
          );

          return CheckboxListTile(
            dense: true,
            title: Text(
              item['name'] as String,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              '${(item['price'] as num? ?? 0).toStringAsFixed(0)} DZD | ${item['notes'] ?? ''}',
              style: const TextStyle(fontSize: 11),
            ),
            value: isLinked,
            activeColor: Colors.cyan.shade800,
            onChanged: (val) async {
              await widget.db.toggleTemperedGlassSystemRule(
                systemCode: _selectedSystemCode!,
                itemId: itemId,
                ruleType: ruleType,
                isActive: val ?? false,
              );
              _loadRulesForSelectedSystem();
            },
          );
        }).toList(),
      ),
    );
  }

  Widget _buildProfilesLinkingList() {
    final profiles = _allItems
        .where((i) => i['category'] == 'profile')
        .toList();
    if (profiles.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(8.0),
        child: Text(
          _tr('لا توجد قطاعات مسجلة', 'Aucun profilé', 'No profiles found'),
        ),
      );
    }

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Column(
        children: profiles.map((item) {
          final itemId = item['id'] as int;
          final rule = _systemRules.firstWhere(
            (r) => r['item_id'] == itemId,
            orElse: () => <String, dynamic>{},
          );
          final isLinked =
              rule.isNotEmpty && (rule['is_active'] as int? ?? 1) == 1;
          final thickness = (rule['glass_thickness_mm'] as num? ?? 0.0)
              .toDouble();

          return ListTile(
            dense: true,
            title: Text(
              item['name'] as String,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              '${(item['price'] as num? ?? 0).toStringAsFixed(0)} DZD | ${item['notes'] ?? ''}',
              style: const TextStyle(fontSize: 11),
            ),
            leading: Checkbox(
              value: isLinked,
              activeColor: Colors.teal.shade700,
              onChanged: (val) async {
                await widget.db.toggleTemperedGlassSystemRule(
                  systemCode: _selectedSystemCode!,
                  itemId: itemId,
                  ruleType: 'profile',
                  isActive: val ?? false,
                  glassThicknessMm: _filterThickness,
                );
                _loadRulesForSelectedSystem();
              },
            ),
            trailing: isLinked
                ? ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: _isCompact(context) ? 92 : 150,
                    ),
                    child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.teal.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      thickness > 0
                          ? '${thickness.toStringAsFixed(0)} مم'
                          : _tr('جميع السماكات', 'Toutes', 'All'),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Colors.teal.shade800,
                      ),
                    ),
                    ),
                  )
                : null,
          );
        }).toList(),
      ),
    );
  }
}

// ==========================================
// PREVIEW PAINTER FOR KIT HOLES
// ==========================================

class _KitHolesPreviewPainter extends CustomPainter {
  final List<Map<String, dynamic>> holes;

  _KitHolesPreviewPainter({required this.holes});

  @override
  void paint(Canvas canvas, Size size) {
    final bgPaint = Paint()..color = const Color(0xFF1E293B);
    canvas.drawRect(Offset.zero & size, bgPaint);

    // Draw stylized door panel
    final panelRect = Rect.fromCenter(
      center: Offset(size.width / 2, size.height / 2),
      width: size.width * 0.75,
      height: size.height * 0.78,
    );

    final glassPaint = Paint()
      ..color = Colors.cyan.withValues(alpha: 0.22)
      ..style = PaintingStyle.fill;
    canvas.drawRRect(
      RRect.fromRectAndRadius(panelRect, const Radius.circular(4)),
      glassPaint,
    );

    final borderPaint = Paint()
      ..color = Colors.cyan.shade300
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawRRect(
      RRect.fromRectAndRadius(panelRect, const Radius.circular(4)),
      borderPaint,
    );

    // Draw reference dimensions
    final textStyle = const TextStyle(
      color: Colors.white70,
      fontSize: 10,
      fontWeight: FontWeight.bold,
    );

    // Assume simulated panel width = 800mm, height = 2000mm
    const simWidth = 800.0;
    const simHeight = 2000.0;

    for (final h in holes) {
      final diamMm = (h['diameter_mm'] as num).toDouble();
      final offXMm = (h['offset_x_mm'] as num).toDouble();
      final offYMm = (h['offset_y_mm'] as num).toDouble();
      final refX = h['ref_x'] as String;
      final refY = h['ref_y'] as String;
      final mode = h['reference_mode'] as String? ?? 'edge';

      double px;
      if (refX == 'left') {
        final xMm = mode == 'edge' ? offXMm + diamMm / 2 : offXMm;
        px = panelRect.left + (xMm / simWidth) * panelRect.width;
      } else if (refX == 'right') {
        final xMm = mode == 'edge' ? offXMm + diamMm / 2 : offXMm;
        px = panelRect.right - (xMm / simWidth) * panelRect.width;
      } else {
        px = panelRect.center.dx;
      }

      double py;
      if (refY == 'top') {
        final yMm = mode == 'edge' ? offYMm + diamMm / 2 : offYMm;
        py = panelRect.top + (yMm / simHeight) * panelRect.height;
      } else if (refY == 'bottom') {
        final yMm = mode == 'edge' ? offYMm + diamMm / 2 : offYMm;
        py = panelRect.bottom - (yMm / simHeight) * panelRect.height;
      } else {
        py = panelRect.center.dy;
      }

      final holeRadius = (diamMm / simWidth) * panelRect.width * 0.9;
      final r = holeRadius.clamp(5.0, 14.0);

      // Hole circle
      final holePaint = Paint()..color = Colors.amberAccent;
      canvas.drawCircle(Offset(px, py), r, holePaint);

      final holeBorder = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2;
      canvas.drawCircle(Offset(px, py), r, holeBorder);

      // Label
      final tp = TextPainter(
        text: TextSpan(
          text: '#${h['hole_index']} Ø${diamMm.toStringAsFixed(0)}',
          style: textStyle,
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(px - tp.width / 2, py + r + 2));
    }
  }

  @override
  bool shouldRepaint(covariant _KitHolesPreviewPainter oldDelegate) => true;
}
