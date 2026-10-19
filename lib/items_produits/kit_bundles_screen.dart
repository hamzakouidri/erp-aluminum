import 'package:database_data/widgets/app_material.dart';
import '../sql_database.dart';
import 'package:database_data/settings/localization.dart';
import 'package:database_data/settings/app_settings.dart';
import 'package:provider/provider.dart';

class KitBundlesScreen extends StatefulWidget {
  final SqlDatabase db;
  const KitBundlesScreen({super.key, required this.db});
  @override
  State<KitBundlesScreen> createState() => _KitBundlesScreenState();
}

class _KitBundlesScreenState extends State<KitBundlesScreen> {
  List<Map<String, dynamic>> _kits = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadKits();
  }

  Future<void> _loadKits() async {
    setState(() => _loading = true);
    final kits = await widget.db.readKitBundles();
    if (mounted)
      setState(() {
        _kits = kits;
        _loading = false;
      });
  }

  Future<void> _showAddEditKitDialog({Map<String, dynamic>? kit}) async {
    final nameCtrl = TextEditingController(text: kit?['name'] ?? '');
    final descCtrl = TextEditingController(text: kit?['description'] ?? '');
    bool perLeaf = (kit?['per_leaf'] ?? 0) == 1;
    final lang = Provider.of<AppSettingsProvider>(
      context,
      listen: false,
    ).language;

    String materialType = kit?['material_type']?.toString().toLowerCase() ?? 'all';
    if (!const ['all', 'aluminium', 'pvc'].contains(materialType)) {
      materialType = 'all';
    }

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 24,
          ),
          actionsOverflowAlignment: OverflowBarAlignment.end,
          actionsOverflowButtonSpacing: 8,
          title: Text(
            kit == null
                ? Localization.translate('اضافة Kit', lang)
                : Localization.translate('تعديل Kit', lang),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: InputDecoration(
                  labelText: Localization.translate('اسم الـ Kit', lang),
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: descCtrl,
                decoration: InputDecoration(
                  labelText: Localization.translate('وصف', lang),
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                value: materialType,
                decoration: InputDecoration(
                  labelText: Localization.translate('نوع المادة', lang),
                  border: const OutlineInputBorder(),
                ),
                items: [
                  DropdownMenuItem(
                    value: 'all',
                    child: Text(Localization.translate('مشترك (Aluminium + PVC)', lang)),
                  ),
                  DropdownMenuItem(
                    value: 'aluminium',
                    child: Text(Localization.translate('ألمنيوم (Aluminium)', lang)),
                  ),
                  DropdownMenuItem(
                    value: 'pvc',
                    child: Text(Localization.translate('بي في سي (PVC)', lang)),
                  ),
                ],
                onChanged: (val) {
                  if (val != null) setS(() => materialType = val);
                },
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                title: Text(Localization.translate('Kit منفصل لكل ضلفة', lang)),
                subtitle: Text(Localization.translate('ضلفتان = Kit x2', lang)),
                value: perLeaf,
                onChanged: (v) => setS(() => perLeaf = v),
                contentPadding: EdgeInsets.zero,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(Localization.translate('الغاء', lang)),
            ),
            ElevatedButton(
              onPressed: () async {
                if (nameCtrl.text.trim().isEmpty) return;
                if (kit == null) {
                  await widget.db.insertKitBundle(
                    name: nameCtrl.text.trim(),
                    description: descCtrl.text.trim().isEmpty
                        ? null
                        : descCtrl.text.trim(),
                    perLeaf: perLeaf,
                    materialType: materialType,
                  );
                } else {
                  await widget.db.updateKitBundle(
                    kit['id'],
                    name: nameCtrl.text.trim(),
                    description: descCtrl.text.trim().isEmpty
                        ? null
                        : descCtrl.text.trim(),
                    perLeaf: perLeaf,
                    materialType: materialType,
                  );
                }
                if (ctx.mounted) Navigator.pop(ctx);
                _loadKits();
              },
              child: Text(
                kit == null
                    ? Localization.translate('اضافة', lang)
                    : Localization.translate('حفظ', lang),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _searchQuery = '';

  @override
  Widget build(BuildContext context) {
    final lang = Provider.of<AppSettingsProvider>(context).language;
    final query = _searchQuery.trim().toLowerCase();
    final filteredKits = _kits.where((k) {
      if (query.isEmpty) return true;
      final name = (k['name'] ?? '').toString().toLowerCase();
      final desc = (k['description'] ?? '').toString().toLowerCase();
      return name.contains(query) || desc.contains(query);
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(Localization.translate('إدارة الكيت', lang)),
        actions: [
          if (isAdmin)
            IconButton(
              icon: const Icon(Icons.add),
              onPressed: () => _showAddEditKitDialog(),
            ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: TextField(
              decoration: InputDecoration(
                hintText: Localization.translate('بحث في الكيت...', lang),
                prefixIcon: const Icon(Icons.search),
                isDense: true,
                border: const OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(20)),
                ),
              ),
              onChanged: (val) {
                setState(() {
                  _searchQuery = val;
                });
              },
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : filteredKits.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.inventory_2_outlined,
                          size: 64,
                          color: Colors.grey,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          Localization.translate('لا توجد نتائج مطابقة', lang),
                          style: const TextStyle(color: Colors.grey),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: filteredKits.length,
                    itemBuilder: (ctx, i) {
                      final kit = filteredKits[i];
                      final perLeaf = (kit['per_leaf'] ?? 0) == 1;
                      return Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: Theme.of(
                              context,
                            ).colorScheme.primary,
                            child: const Icon(
                              Icons.inventory_2,
                              color: Colors.white,
                            ),
                          ),
                          title: Text(
                            kit['name'] ?? '',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  if (kit['material_type'] == 'pvc')
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.teal.shade50,
                                        borderRadius: BorderRadius.circular(4),
                                        border: Border.all(
                                          color: Colors.teal.shade300,
                                        ),
                                      ),
                                      child: const Text(
                                        'PVC',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.teal,
                                        ),
                                      ),
                                    )
                                  else if (kit['material_type'] == 'aluminium')
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.indigo.shade50,
                                        borderRadius: BorderRadius.circular(4),
                                        border: Border.all(
                                          color: Colors.indigo.shade300,
                                        ),
                                      ),
                                      child: const Text(
                                        'Aluminium',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.indigo,
                                        ),
                                      ),
                                    ),
                                  if (perLeaf) ...[
                                    if (kit['material_type'] == 'pvc' ||
                                        kit['material_type'] == 'aluminium')
                                      const SizedBox(width: 6),
                                    Text(
                                      Localization.translate('Kit لكل ضلفة', lang),
                                      style: const TextStyle(
                                        color: Colors.blue,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ],
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.list_alt),
                                onPressed: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        KitItemsScreen(db: widget.db, kit: kit),
                                  ),
                                ),
                              ),
                              if (isAdmin) ...[
                                IconButton(
                                  icon: const Icon(Icons.edit),
                                  onPressed: () =>
                                      _showAddEditKitDialog(kit: kit),
                                ),
                                IconButton(
                                  icon: const Icon(
                                    Icons.delete,
                                    color: Colors.red,
                                  ),
                                  onPressed: () async {
                                    await widget.db.deleteKitBundle(kit['id']);
                                    _loadKits();
                                  },
                                ),
                              ],
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: isAdmin
          ? FloatingActionButton.extended(
              onPressed: () => _showAddEditKitDialog(),
              icon: const Icon(Icons.add),
              label: Text(Localization.translate('اضافة Kit', lang)),
            )
          : null,
    );
  }
}

// ---- KitItemsScreen ----
class KitItemsScreen extends StatefulWidget {
  final SqlDatabase db;
  final Map<String, dynamic> kit;
  final Map<String, dynamic>? family;
  const KitItemsScreen({
    super.key,
    required this.db,
    required this.kit,
    this.family,
  });
  @override
  State<KitItemsScreen> createState() => _KitItemsScreenState();
}

class _KitItemsScreenState extends State<KitItemsScreen> {
  List<Map<String, dynamic>> _items = [];
  List<Map<String, dynamic>> _families = [];
  bool _loading = true;
  List<String> _suggestedNames = [];
  late String _group1Name;
  late String _group2Name;
  // Axe deduction (mm) of a tunnel box with each console.
  late double _group1Axe;
  late double _group2Axe;

  @override
  void initState() {
    super.initState();
    _group1Name =
        widget.kit['compatibility_group_1_name']
                ?.toString()
                .trim()
                .isNotEmpty ==
            true
        ? widget.kit['compatibility_group_1_name'].toString()
        : 'Console Quissonnel Standard';
    _group2Name =
        widget.kit['compatibility_group_2_name']
                ?.toString()
                .trim()
                .isNotEmpty ==
            true
        ? widget.kit['compatibility_group_2_name'].toString()
        : 'Console Quissonnel Spécial';
    _group1Axe =
        (widget.kit['compatibility_group_1_axe_deduction'] as num?)
            ?.toDouble() ??
        75;
    _group2Axe =
        (widget.kit['compatibility_group_2_axe_deduction'] as num?)
            ?.toDouble() ??
        75;
    _loadItems();
    _loadSuggestions();
  }

  Future<void> _loadSuggestions() async {
    try {
      final shutterComps = await widget.db.readShutterComponents();
      final accessories = await widget.db.readAccessories();
      final names = <String>{};
      for (final c in shutterComps) {
        if (c['name'] != null) names.add(c['name'].toString().trim());
        if (c['component_type'] != null)
          names.add(c['component_type'].toString().trim());
      }
      for (final a in accessories) {
        if (a['name'] != null) names.add(a['name'].toString().trim());
        if (a['type'] != null) names.add(a['type'].toString().trim());
      }
      if (mounted) {
        setState(() {
          _suggestedNames = names.where((n) => n.isNotEmpty).toList();
        });
      }
    } catch (error) {
      debugPrint('Kit name suggestions unavailable: $error');
    }
  }

  Future<void> _loadItems() async {
    setState(() => _loading = true);
    final familyId = (widget.family?['id'] as num?)?.toInt();
    final results = await Future.wait<dynamic>([
      widget.db.readKitBundleItemsWithDetails(
        widget.kit['id'],
        familyId: familyId,
        topLevelOnly: widget.family == null,
      ),
      if (widget.family == null)
        widget.db.readKitBundleFamilies(widget.kit['id']),
    ]);
    final items = results.first as List<Map<String, dynamic>>;
    final families = widget.family == null && results.length > 1
        ? results[1] as List<Map<String, dynamic>>
        : <Map<String, dynamic>>[];
    if (mounted)
      setState(() {
        _items = items;
        _families = families;
        _loading = false;
      });
  }

  String _qtyModeLabel(String mode, AppLanguage lang) {
    switch (mode) {
      case 'by_range':
        return Localization.translate('بالنطاق', lang);
      case 'by_variant':
        return 'Simple/Double';
      default:
        return Localization.translate('ثابتة', lang);
    }
  }

  Color _qtyModeColor(String mode) {
    switch (mode) {
      case 'by_range':
        return Colors.orange;
      case 'by_variant':
        return Colors.purple;
      default:
        return Colors.teal;
    }
  }

  String _dimLabel(String? dim, AppLanguage lang) {
    if (dim == 'leaf_height') return Localization.translate('طول الضلفة', lang);
    if (dim == 'leaf_width') return Localization.translate('عرض الضلفة', lang);
    if (dim == 'shutter_weight') {
      return Localization.translate('وزن الستار', lang);
    }
    return '';
  }

  bool get _isShutterStyleKit {
    final code = (widget.kit['description'] ?? '')
        .toString()
        .trim()
        .toUpperCase()
        .replaceAll(RegExp(r'[\s,;:_-]+'), '');
    if (const {'V', 'M', 'MT', 'CT'}.contains(code)) return true;
    final name = (widget.kit['name'] ?? '').toString().toLowerCase();
    return name.contains('caisson') ||
        name.contains('tunnel') ||
        name.contains('volet') ||
        name.contains('shutter') ||
        name.contains('ستار');
  }

  Future<void> _editCompatibilityGroupNames() async {
    final lang = Provider.of<AppSettingsProvider>(
      context,
      listen: false,
    ).language;
    final first = TextEditingController(text: _group1Name);
    final second = TextEditingController(text: _group2Name);
    String mm(double v) => v == v.roundToDouble() ? '${v.toInt()}' : '$v';
    final firstAxe = TextEditingController(text: mm(_group1Axe));
    final secondAxe = TextEditingController(text: mm(_group2Axe));
    Widget axeField(TextEditingController controller) => Padding(
      padding: const EdgeInsets.only(top: 8),
      child: TextField(
        controller: controller,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(
          labelText: Localization.translate('خصم المحور (مم)', lang),
          border: const OutlineInputBorder(),
          isDense: true,
        ),
      ),
    );
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(Localization.translate('تسمية مجموعتي التوافق', lang)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: first,
              decoration: InputDecoration(
                labelText: Localization.translate('المجموعة الأولى', lang),
                border: const OutlineInputBorder(),
              ),
            ),
            axeField(firstAxe),
            const SizedBox(height: 12),
            TextField(
              controller: second,
              decoration: InputDecoration(
                labelText: Localization.translate('المجموعة الثانية', lang),
                border: const OutlineInputBorder(),
              ),
            ),
            axeField(secondAxe),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(Localization.translate('إلغاء', lang)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(Localization.translate('حفظ', lang)),
          ),
        ],
      ),
    );
    if (saved != true) return;
    final axe1 = double.tryParse(firstAxe.text.replaceAll(',', '.'));
    final axe2 = double.tryParse(secondAxe.text.replaceAll(',', '.'));
    await widget.db.updateKitCompatibilityGroupNames(
      widget.kit['id'],
      group1Name: first.text,
      group2Name: second.text,
      group1AxeDeduction: axe1,
      group2AxeDeduction: axe2,
    );
    if (mounted) {
      setState(() {
        _group1Axe = axe1 ?? _group1Axe;
        _group2Axe = axe2 ?? _group2Axe;
        _group1Name = first.text.trim().isEmpty
            ? 'Console Quissonnel Standard'
            : first.text.trim();
        _group2Name = second.text.trim().isEmpty
            ? 'Console Quissonnel Spécial'
            : second.text.trim();
      });
    }
  }

  static const _mechanismOptions = <(String, String)>[
    ('belt', 'حزام'),
    ('crank', 'مانيفال'),
    ('motor', 'كل المحركات'),
    ('motor_plain', 'محرك عادي'),
    ('motor_emergency', 'محرك مع مانيفال احتياطي'),
  ];

  String _mechanismLabel(Set<String> scopes, AppLanguage lang) {
    if (scopes.isEmpty) return Localization.translate('كل الميكانيزمات', lang);
    return _mechanismOptions
        .where((option) => scopes.contains(option.$1))
        .map((option) => Localization.translate(option.$2, lang))
        .join(lang == AppLanguage.arabic ? '، ' : ', ');
  }

  Future<void> _showAddEditFamilyDialog({Map<String, dynamic>? family}) async {
    final lang = Provider.of<AppSettingsProvider>(
      context,
      listen: false,
    ).language;
    final nameCtrl = TextEditingController(
      text: family?['name']?.toString() ?? '',
    );
    final selectedMechanisms = (family?['mechanism_scopes'] ?? '')
        .toString()
        .split(',')
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toSet();
    String bladeScope = family?['blade_scope']?.toString() ?? 'all';
    if (bladeScope == 'x3d') bladeScope = 'extruded';
    bool perLeaf = (family?['per_leaf'] as num?)?.toInt() == 1;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 24,
          ),
          actionsOverflowAlignment: OverflowBarAlignment.end,
          actionsOverflowButtonSpacing: 8,
          title: Text(
            family == null ? 'إضافة عائلة داخل الكيت' : 'تعديل عائلة الكيت',
          ),
          content: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 560,
              maxHeight:
                  (MediaQuery.of(ctx).size.height -
                      MediaQuery.of(ctx).viewInsets.bottom) *
                  0.52,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: nameCtrl,
                    decoration: InputDecoration(
                      labelText: Localization.translate('اسم العائلة', lang),
                      hintText: Localization.translate(
                        'مثال: Embout + Support Roulement',
                        lang,
                      ),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    Localization.translate(
                      'فلترة اختيارية حسب الميكانيزم:',
                      lang,
                    ),
                  ),
                  Text(
                    Localization.translate(
                      'اتركها بلا اختيار لتكون العائلة متاحة عند اختيارها داخل نطاق.',
                      lang,
                    ),
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                  for (final option in _mechanismOptions)
                    CheckboxListTile(
                      value: selectedMechanisms.contains(option.$1),
                      title: Text(Localization.translate(option.$2, lang)),
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      onChanged: (checked) => setDialogState(() {
                        if (checked == true) {
                          selectedMechanisms.add(option.$1);
                        } else {
                          selectedMechanisms.remove(option.$1);
                        }
                      }),
                    ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: bladeScope,
                    decoration: InputDecoration(
                      labelText: Localization.translate('نوع الشفرة', lang),
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      DropdownMenuItem(
                        value: 'all',
                        child: Text(Localization.translate('كل الشفرات', lang)),
                      ),
                      DropdownMenuItem(
                        value: 'normal',
                        child: Text(
                          Localization.translate('الشفرة العادية فقط', lang),
                        ),
                      ),
                      DropdownMenuItem(
                        value: 'extruded',
                        child: Text(
                          Localization.translate('شفرة Extrudé فقط', lang),
                        ),
                      ),
                    ],
                    onChanged: (value) =>
                        setDialogState(() => bladeScope = value ?? 'all'),
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      Localization.translate('تتكرر لكل ضلفة', lang),
                    ),
                    subtitle: Text(
                      Localization.translate(
                        'اتركها مغلقة لاستعمال العائلة مرة واحدة داخل الكيت.',
                        lang,
                      ),
                    ),
                    value: perLeaf,
                    onChanged: (value) => setDialogState(() => perLeaf = value),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(Localization.translate('الغاء', lang)),
            ),
            ElevatedButton(
              onPressed: () async {
                if (nameCtrl.text.trim().isEmpty) return;
                final scopes = selectedMechanisms.toList()..sort();
                if (family == null) {
                  await widget.db.insertKitBundleFamily(
                    kitId: widget.kit['id'],
                    name: nameCtrl.text.trim(),
                    mechanismScopes: scopes.join(','),
                    bladeScope: bladeScope,
                    perLeaf: perLeaf,
                    sortOrder: _families.length,
                  );
                } else {
                  await widget.db.updateKitBundleFamily(
                    family['id'],
                    name: nameCtrl.text.trim(),
                    mechanismScopes: scopes.join(','),
                    bladeScope: bladeScope,
                    perLeaf: perLeaf,
                    sortOrder: (family['sort_order'] as num?)?.toInt() ?? 0,
                  );
                }
                if (ctx.mounted) Navigator.pop(ctx);
                _loadItems();
              },
              child: Text(
                Localization.translate(family == null ? 'اضافة' : 'حفظ', lang),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showAddEditItemDialog({Map<String, dynamic>? item}) async {
    final typeCtrl = TextEditingController(text: item?['component_type'] ?? '');
    String qtyMode = item?['qty_mode'] ?? 'fixed';
    String? dimension = item?['dimension'];
    final baseQtyCtrl = TextEditingController(
      text: (item?['base_qty'] ?? 1).toString(),
    );
    final rawScopes = (item?['mechanism_scopes'] ?? '')
        .toString()
        .split(',')
        .map((scope) => scope.trim())
        .where((scope) => scope.isNotEmpty)
        .toSet();
    final selectedMechanisms = rawScopes.isEmpty
        ? <String>{'belt', 'crank', 'motor'}
        : <String>{...rawScopes};
    String bladeScope = item?['blade_scope']?.toString() ?? 'all';
    if (bladeScope == 'x3d') bladeScope = 'extruded';
    final lang = Provider.of<AppSettingsProvider>(
      context,
      listen: false,
    ).language;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 24,
          ),
          actionsOverflowAlignment: OverflowBarAlignment.end,
          actionsOverflowButtonSpacing: 8,
          title: Text(
            item == null
                ? Localization.translate('اضافة مركب', lang)
                : Localization.translate('تعديل مركب', lang),
          ),
          content: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 520,
              maxHeight:
                  (MediaQuery.of(ctx).size.height -
                      MediaQuery.of(ctx).viewInsets.bottom) *
                  0.52,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Autocomplete<String>(
                    initialValue: TextEditingValue(text: typeCtrl.text),
                    optionsBuilder: (TextEditingValue textEditingValue) {
                      if (textEditingValue.text.isEmpty) return _suggestedNames;
                      return _suggestedNames.where(
                        (option) => option.toLowerCase().contains(
                          textEditingValue.text.toLowerCase(),
                        ),
                      );
                    },
                    onSelected: (selection) => typeCtrl.text = selection,
                    fieldViewBuilder: (ctx, ctrl, node, onSubmit) {
                      ctrl.addListener(() => typeCtrl.text = ctrl.text);
                      return TextField(
                        controller: ctrl,
                        focusNode: node,
                        onSubmitted: (v) => onSubmit(),
                        decoration: InputDecoration(
                          labelText: Localization.translate('نوع المركب', lang),
                          hintText: Localization.translate(
                            'اكتب أو اختر من القائمة...',
                            lang,
                          ),
                          border: const OutlineInputBorder(),
                          suffixIcon: IconButton(
                            icon: const Icon(Icons.arrow_drop_down),
                            onPressed: () {
                              node.requestFocus();
                              if (ctrl.text.isEmpty) {
                                // trigger optionsBuilder
                                ctrl.text = ' ';
                                ctrl.text = '';
                              }
                            },
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  Text(
                    Localization.translate('نوع الكمية:', lang),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  RadioListTile<String>(
                    title: Text(Localization.translate('ثابتة', lang)),
                    value: 'fixed',
                    groupValue: qtyMode,
                    onChanged: (v) => setS(() => qtyMode = v!),
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                  ),
                  RadioListTile<String>(
                    title: Text(
                      Localization.translate('بالنطاق (حسب القياس)', lang),
                    ),
                    value: 'by_range',
                    groupValue: qtyMode,
                    onChanged: (v) => setS(() => qtyMode = v!),
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                  ),
                  RadioListTile<String>(
                    title: Text(
                      Localization.translate(
                        'بالنوع (Simple/Double Ouvrant)',
                        lang,
                      ),
                    ),
                    value: 'by_variant',
                    groupValue: qtyMode,
                    onChanged: (v) => setS(() => qtyMode = v!),
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                  ),
                  if (qtyMode == 'fixed') ...[
                    const SizedBox(height: 10),
                    TextField(
                      controller: baseQtyCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: Localization.translate('الكمية', lang),
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ],
                  if (qtyMode == 'by_range') ...[
                    const SizedBox(height: 12),
                    Text(
                      Localization.translate('القياس المرجعي:', lang),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    RadioListTile<String?>(
                      title: Text(Localization.translate('طول الضلفة', lang)),
                      value: 'leaf_height',
                      groupValue: dimension,
                      onChanged: (v) => setS(() => dimension = v),
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                    ),
                    RadioListTile<String?>(
                      title: Text(Localization.translate('عرض الضلفة', lang)),
                      value: 'leaf_width',
                      groupValue: dimension,
                      onChanged: (v) => setS(() => dimension = v),
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                    ),
                    RadioListTile<String?>(
                      title: Text(
                        Localization.translate('وزن الستار (كغ)', lang),
                      ),
                      value: 'shutter_weight',
                      groupValue: dimension,
                      onChanged: (v) => setS(() => dimension = v),
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                    ),
                  ],
                  const SizedBox(height: 12),
                  Text(
                    Localization.translate(
                      'استعمال المركب (يمكن اختيار أكثر من نوع):',
                      lang,
                    ),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  for (final option in _mechanismOptions)
                    CheckboxListTile(
                      value: selectedMechanisms.contains(option.$1),
                      title: Text(Localization.translate(option.$2, lang)),
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      onChanged: (checked) => setS(() {
                        if (checked == true) {
                          selectedMechanisms.add(option.$1);
                        } else {
                          selectedMechanisms.remove(option.$1);
                        }
                      }),
                    ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: bladeScope,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: Localization.translate(
                        'نوع الشفرة المرتبط بالمركب',
                        lang,
                      ),
                      border: const OutlineInputBorder(),
                    ),
                    items: [
                      DropdownMenuItem(
                        value: 'all',
                        child: Text(Localization.translate('كل الشفرات', lang)),
                      ),
                      DropdownMenuItem(
                        value: 'normal',
                        child: Text(
                          Localization.translate('الشفرة العادية فقط', lang),
                        ),
                      ),
                      DropdownMenuItem(
                        value: 'extruded',
                        child: Text(
                          Localization.translate('شفرة Extrudé فقط', lang),
                        ),
                      ),
                    ],
                    onChanged: (value) =>
                        setS(() => bladeScope = value ?? 'all'),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    Localization.translate('الوحدة ثابتة: قطعة', lang),
                    style: const TextStyle(color: Colors.grey),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(Localization.translate('الغاء', lang)),
            ),
            ElevatedButton(
              onPressed: () async {
                if (typeCtrl.text.trim().isEmpty ||
                    selectedMechanisms.isEmpty) {
                  return;
                }
                final mechanismScopes = selectedMechanisms.toList()..sort();
                if (item == null) {
                  await widget.db.insertKitBundleItem(
                    kitId: widget.kit['id'],
                    componentType: typeCtrl.text.trim(),
                    qtyMode: qtyMode,
                    dimension: qtyMode == 'by_range' ? dimension : null,
                    baseQty: double.tryParse(baseQtyCtrl.text) ?? 1,
                    unit: 'قطعة',
                    mechanismScope: 'all',
                    mechanismScopes: mechanismScopes.join(','),
                    bladeScope: bladeScope,
                    familyId: (widget.family?['id'] as num?)?.toInt(),
                    sortOrder: _items.length,
                  );
                } else {
                  await widget.db.updateKitBundleItem(
                    item['id'],
                    componentType: typeCtrl.text.trim(),
                    qtyMode: qtyMode,
                    dimension: qtyMode == 'by_range' ? dimension : null,
                    baseQty: double.tryParse(baseQtyCtrl.text) ?? 1,
                    unit: 'قطعة',
                    mechanismScope: 'all',
                    mechanismScopes: mechanismScopes.join(','),
                    bladeScope: bladeScope,
                    sortOrder: item['sort_order'] ?? 0,
                  );
                }
                if (ctx.mounted) Navigator.pop(ctx);
                _loadItems();
              },
              child: Text(
                item == null
                    ? Localization.translate('اضافة', lang)
                    : Localization.translate('حفظ', lang),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final lang = Provider.of<AppSettingsProvider>(context).language;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          '${widget.kit['name']}${widget.family == null ? '' : ' › ${widget.family!['name']}'} - ${Localization.translate('المركبات', lang)}',
        ),
        actions: [
          if (isAdmin && widget.family == null)
            IconButton(
              tooltip: Localization.translate('تسمية مجموعتي التوافق', lang),
              icon: const Icon(Icons.drive_file_rename_outline),
              onPressed: _editCompatibilityGroupNames,
            ),
          if (isAdmin && widget.family == null)
            IconButton(
              tooltip: Localization.translate('إضافة عائلة داخل الكيت', lang),
              icon: const Icon(Icons.account_tree_outlined),
              onPressed: () => _showAddEditFamilyDialog(),
            ),
          if (isAdmin)
            IconButton(
              icon: const Icon(Icons.add),
              onPressed: () => _showAddEditItemDialog(),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty && _families.isEmpty
          ? Center(
              child: Text(
                widget.family == null
                    ? 'لا توجد مركبات أو عائلات بعد'
                    : 'لا توجد مركبات داخل هذه العائلة بعد',
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: _families.length + _items.length,
              itemBuilder: (ctx, i) {
                if (i < _families.length) {
                  final family = _families[i];
                  final scopes = (family['mechanism_scopes'] ?? '')
                      .toString()
                      .split(',')
                      .map((scope) => scope.trim())
                      .where((scope) => scope.isNotEmpty)
                      .toSet();
                  final bladeScope = family['blade_scope']?.toString() ?? 'all';
                  final bladeLabel = bladeScope == 'normal'
                      ? Localization.translate('شفرة عادية', lang)
                      : bladeScope == 'extruded' || bladeScope == 'x3d'
                      ? Localization.translate('شفرة Extrudé', lang)
                      : Localization.translate('كل الشفرات', lang);
                  final onceLabel = (family['per_leaf'] as num?)?.toInt() == 1
                      ? 'لكل ضلفة'
                      : 'مرة واحدة داخل الكيت';
                  return Card(
                    color: Theme.of(context).colorScheme.secondaryContainer,
                    margin: const EdgeInsets.only(bottom: 10),
                    child: ListTile(
                      leading: const CircleAvatar(
                        child: Icon(Icons.account_tree_outlined),
                      ),
                      title: Text(
                        family['name']?.toString() ?? '',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text(
                        '$onceLabel | ${_mechanismLabel(scopes, lang)} | $bladeLabel',
                      ),
                      onTap: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => KitItemsScreen(
                              db: widget.db,
                              kit: widget.kit,
                              family: family,
                            ),
                          ),
                        );
                        _loadItems();
                      },
                      trailing: isAdmin
                          ? Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.edit),
                                  onPressed: () =>
                                      _showAddEditFamilyDialog(family: family),
                                ),
                                IconButton(
                                  icon: const Icon(
                                    Icons.delete,
                                    color: Colors.red,
                                  ),
                                  onPressed: () async {
                                    await widget.db.deleteKitBundleFamily(
                                      family['id'],
                                    );
                                    _loadItems();
                                  },
                                ),
                              ],
                            )
                          : const Icon(Icons.chevron_right),
                    ),
                  );
                }
                final item = _items[i - _families.length];
                final mode = (item['qty_mode'] ?? 'fixed') as String;
                final dim = item['dimension'] as String?;
                final ranges = item['ranges'] as List? ?? [];
                final variants = item['variants'] as List? ?? [];
                final scopes = (item['mechanism_scopes'] ?? '')
                    .toString()
                    .split(',')
                    .where((scope) => scope.trim().isNotEmpty)
                    .toSet();
                final mechanismLabel = _mechanismLabel(scopes, lang);
                final bladeScope = item['blade_scope']?.toString() ?? 'all';
                final bladeLabel = bladeScope == 'normal'
                    ? Localization.translate('شفرة عادية', lang)
                    : bladeScope == 'extruded' || bladeScope == 'x3d'
                    ? Localization.translate('شفرة Extrudé', lang)
                    : Localization.translate('كل الشفرات', lang);

                String qtyLabel = '';
                if (mode == 'fixed') {
                  qtyLabel = 'x${(item['base_qty'] ?? 1).toStringAsFixed(0)}';
                } else if (mode == 'by_range') {
                  final qtys = ranges
                      .map((r) => (r['qty'] ?? 1.0) as num)
                      .toSet();
                  if (qtys.isEmpty) {
                    qtyLabel = '?';
                  } else if (qtys.length == 1) {
                    qtyLabel = 'x${qtys.first.toStringAsFixed(0)}';
                  } else {
                    final minQ = qtys.reduce((a, b) => a < b ? a : b);
                    final maxQ = qtys.reduce((a, b) => a > b ? a : b);
                    qtyLabel =
                        '${minQ.toStringAsFixed(0)}-${maxQ.toStringAsFixed(0)}';
                  }
                } else if (mode == 'by_variant') {
                  final qtys = variants
                      .map((v) => (v['qty'] ?? 1.0) as num)
                      .toSet();
                  if (qtys.isEmpty) {
                    qtyLabel = '?';
                  } else if (qtys.length == 1) {
                    qtyLabel = 'x${qtys.first.toStringAsFixed(0)}';
                  } else {
                    final minQ = qtys.reduce((a, b) => a < b ? a : b);
                    final maxQ = qtys.reduce((a, b) => a > b ? a : b);
                    qtyLabel =
                        '${minQ.toStringAsFixed(0)}-${maxQ.toStringAsFixed(0)}';
                  }
                }

                String modeDetails = '';
                if (mode == 'by_range' && ranges.isNotEmpty) {
                  modeDetails =
                      ' (' +
                      ranges
                          .map((r) {
                            final isWeight = dim == 'shutter_weight';
                            final divisor = isWeight ? 1.0 : 10.0;
                            final minCm = ((r['min_mm'] ?? 0) / divisor)
                                .toStringAsFixed(0);
                            final maxCm = ((r['max_mm'] ?? 0) / divisor)
                                .toStringAsFixed(0);
                            final qty = (r['qty'] ?? 1).toStringAsFixed(0);
                            final rawGroup =
                                (r['compatibility_group'] as num?)?.toInt() ??
                                0;
                            final groupLabel = rawGroup == 0
                                ? Localization.translate('مشترك', lang)
                                : rawGroup == 1
                                ? _group1Name
                                : _group2Name;
                            return '$minCm-$maxCm${isWeight ? " ${Localization.translate('كغ', lang)}، $groupLabel" : ""}: $qty';
                          })
                          .join(', ') +
                      ')';
                } else if (mode == 'by_variant' && variants.isNotEmpty) {
                  final isShutter = _isShutterStyleKit;
                  modeDetails =
                      ' (' +
                      variants
                          .map((v) {
                            final type = v['ouvrant_type'];
                            String typeLabel = type;
                            if (isShutter) {
                              typeLabel = type == 'extruded'
                                  ? 'Extruded'
                                  : 'Normal';
                            } else {
                              typeLabel = type == 'double'
                                  ? 'Double'
                                  : 'Simple';
                            }
                            final qty = (v['qty'] ?? 1).toStringAsFixed(0);
                            return '$typeLabel: $qty';
                          })
                          .join(', ') +
                      ')';
                }

                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: _qtyModeColor(mode),
                      radius: 18,
                      child: Text(
                        qtyLabel,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                        ),
                      ),
                    ),
                    title: Text(
                      item['component_type'] ?? '',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(
                      '${_qtyModeLabel(mode, lang)}$modeDetails'
                      '${dim != null ? " | ${_dimLabel(dim, lang)}" : ""}'
                      ' | $mechanismLabel | $bladeLabel | ${Localization.translate('قطعة', lang)}',
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (mode == 'by_range')
                          IconButton(
                            icon: const Icon(
                              Icons.linear_scale,
                              color: Colors.orange,
                            ),
                            tooltip: Localization.translate('النطاقات', lang),
                            onPressed: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => KitItemRangesScreen(
                                  db: widget.db,
                                  item: item,
                                  group1Name: _group1Name,
                                  group2Name: _group2Name,
                                ),
                              ),
                            ),
                          ),
                        if (mode == 'by_variant')
                          IconButton(
                            icon: const Icon(Icons.tune, color: Colors.purple),
                            tooltip: Localization.translate('المتغيرات', lang),
                            onPressed: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => KitItemVariantsScreen(
                                  db: widget.db,
                                  item: item,
                                  kitName: widget.kit['name'] ?? '',
                                  isShutterKit: _isShutterStyleKit,
                                ),
                              ),
                            ),
                          ),
                        if (isAdmin) ...[
                          IconButton(
                            icon: const Icon(Icons.edit),
                            onPressed: () => _showAddEditItemDialog(item: item),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete, color: Colors.red),
                            onPressed: () async {
                              await widget.db.deleteKitBundleItem(item['id']);
                              _loadItems();
                            },
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              },
            ),
      floatingActionButton: isAdmin
          ? FloatingActionButton.extended(
              onPressed: () => _showAddEditItemDialog(),
              icon: const Icon(Icons.add),
              label: Text(Localization.translate('اضافة مركب', lang)),
            )
          : null,
    );
  }
}

// ---- KitItemRangesScreen ----
class KitItemRangesScreen extends StatefulWidget {
  final SqlDatabase db;
  final Map<String, dynamic> item;
  final String group1Name;
  final String group2Name;
  const KitItemRangesScreen({
    super.key,
    required this.db,
    required this.item,
    this.group1Name = 'Console Quissonnel Standard',
    this.group2Name = 'Console Quissonnel Spécial',
  });
  @override
  State<KitItemRangesScreen> createState() => _KitItemRangesScreenState();
}

class _KitItemRangesScreenState extends State<KitItemRangesScreen> {
  List<Map<String, dynamic>> _ranges = [];
  bool _loading = true;
  List<Map<String, dynamic>> _shutterComponents = [];
  List<Map<String, dynamic>> _families = [];

  @override
  void initState() {
    super.initState();
    _loadRanges();
    _loadSuggestions();
  }

  Future<void> _loadSuggestions() async {
    try {
      final shutterComps = await widget.db.readShutterComponents();
      final kitId = (widget.item['kit_id'] as num?)?.toInt();
      final families = kitId == null
          ? <Map<String, dynamic>>[]
          : await widget.db.readKitBundleFamilies(kitId);
      if (mounted) {
        setState(() {
          _shutterComponents =
              shutterComps
                  .where(
                    (component) =>
                        component['name']?.toString().trim().isNotEmpty ==
                            true &&
                        (component['is_active'] == null ||
                            component['is_active'] == 1),
                  )
                  .map((component) => Map<String, dynamic>.from(component))
                  .toList()
                ..sort(
                  (a, b) =>
                      a['name'].toString().compareTo(b['name'].toString()),
                );
          _families = families
              .map((family) => Map<String, dynamic>.from(family))
              .toList();
        });
      }
    } catch (error) {
      // An empty list here looks like a kit without components or families;
      // say that the data could not be read instead.
      debugPrint('Kit components/families load failed: $error');
      if (mounted) {
        final lang = Provider.of<AppSettingsProvider>(
          context,
          listen: false,
        ).language;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              Localization.translate(
                'تعذر تحميل مكونات وعائلات الكت. أعد فتح الصفحة.',
                lang,
              ),
            ),
          ),
        );
      }
    }
  }

  Future<void> _loadRanges() async {
    setState(() => _loading = true);
    final ranges = await widget.db.readKitItemRanges(widget.item['id']);
    if (mounted)
      setState(() {
        _ranges = ranges;
        _loading = false;
      });
  }

  String _dimLabel(AppLanguage lang) {
    switch (widget.item['dimension']) {
      case 'leaf_height':
        return Localization.translate('طول الضلفة (سم)', lang);
      case 'leaf_width':
        return Localization.translate('عرض الضلفة (سم)', lang);
      case 'shutter_weight':
        return Localization.translate('وزن الستار (كغ)', lang);
      default:
        return Localization.translate('القياس (سم)', lang);
    }
  }

  Future<void> _showAddEditRangeDialog({Map<String, dynamic>? range}) async {
    final lang = Provider.of<AppSettingsProvider>(
      context,
      listen: false,
    ).language;
    final isWeight = widget.item['dimension'] == 'shutter_weight';
    final divisor = isWeight ? 1.0 : 10.0;
    final unitLabel = isWeight ? 'كغ' : 'سم';
    final minCtrl = TextEditingController(
      text: range != null
          ? (range['min_mm'] / divisor).toStringAsFixed(isWeight ? 1 : 0)
          : '',
    );
    final maxCtrl = TextEditingController(
      text: range != null
          ? (range['max_mm'] / divisor).toStringAsFixed(isWeight ? 1 : 0)
          : '',
    );
    int? selectedComponentId = (range?['shutter_component_id'] as num?)
        ?.toInt();
    if (selectedComponentId != null &&
        !_shutterComponents.any(
          (component) => component['id'] == selectedComponentId,
        )) {
      selectedComponentId = null;
    }
    int? selectedFamilyId = (range?['family_id'] as num?)?.toInt();
    if (selectedFamilyId != null &&
        !_families.any((family) => family['id'] == selectedFamilyId)) {
      selectedFamilyId = null;
    }
    // A range has exactly one target.  Older rows could contain both IDs;
    // keep the family because it is the target shown by the range list and
    // clear the stale component before the dialog is rendered.
    if (selectedComponentId != null && selectedFamilyId != null) {
      selectedComponentId = null;
    }
    String? selectedTarget = selectedComponentId != null
        ? 'component:$selectedComponentId'
        : selectedFamilyId != null
        ? 'family:$selectedFamilyId'
        : null;
    final qtyCtrl = TextEditingController(
      text: (range?['qty'] ?? 1).toString(),
    );
    int compatibilityGroup =
        ((range?['compatibility_group'] as num?)?.toInt() ?? 0).clamp(0, 2);
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 24,
          ),
          actionsOverflowAlignment: OverflowBarAlignment.end,
          actionsOverflowButtonSpacing: 8,
          title: Text(
            Localization.translate(
              range == null ? 'إضافة نطاق' : 'تعديل النطاق',
              lang,
            ),
          ),
          content: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 560,
              maxHeight:
                  (MediaQuery.of(ctx).size.height -
                      MediaQuery.of(ctx).viewInsets.bottom) *
                  0.52,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _dimLabel(lang),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: minCtrl,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: InputDecoration(
                            labelText:
                                '${Localization.translate('من', lang)} ($unitLabel)',
                            hintText: isWeight ? '1' : '80',
                            border: const OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: maxCtrl,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: InputDecoration(
                            labelText:
                                '${Localization.translate('إلى', lang)} ($unitLabel)',
                            hintText: isWeight ? '15' : '120',
                            border: const OutlineInputBorder(),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    initialValue: selectedTarget,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: Localization.translate(
                        'العنصر داخل النطاق',
                        lang,
                      ),
                      helperText: Localization.translate(
                        'اختر هدفاً واحداً فقط: مركّب أو عائلة.',
                        lang,
                      ),
                      border: const OutlineInputBorder(),
                    ),
                    items: [
                      ..._shutterComponents.map(
                        (component) => DropdownMenuItem<String>(
                          value:
                              'component:${(component['id'] as num).toInt()}',
                          child: Text(
                            '${Localization.translate('مركّب:', lang)} ${component['name']}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                      ..._families.map(
                        (family) => DropdownMenuItem<String>(
                          value: 'family:${(family['id'] as num).toInt()}',
                          child: Text(
                            '${Localization.translate('عائلة:', lang)} ${family['name']}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ],
                    onChanged: (value) => setDialogState(() {
                      selectedTarget = value;
                      selectedComponentId = null;
                      selectedFamilyId = null;
                      if (value == null) return;
                      final parts = value.split(':');
                      if (parts.length != 2) {
                        selectedTarget = null;
                        return;
                      }
                      final id = int.tryParse(parts[1]);
                      if (id == null) {
                        selectedTarget = null;
                        return;
                      }
                      if (parts[0] == 'component') {
                        selectedComponentId = id;
                      } else if (parts[0] == 'family') {
                        selectedFamilyId = id;
                      } else {
                        selectedTarget = null;
                      }
                    }),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: qtyCtrl,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: Localization.translate('الكمية (قطعة)', lang),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  if (isWeight) ...[
                    const SizedBox(height: 10),
                    DropdownButtonFormField<int>(
                      value: compatibilityGroup,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: Localization.translate(
                          'مجموعة التوافق',
                          lang,
                        ),
                        border: const OutlineInputBorder(),
                      ),
                      items: [
                        DropdownMenuItem(
                          value: 0,
                          child: Text(
                            Localization.translate(
                              'مشترك بين المجموعتين',
                              lang,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        DropdownMenuItem(
                          value: 1,
                          child: Text(
                            widget.group1Name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        DropdownMenuItem(
                          value: 2,
                          child: Text(
                            widget.group2Name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                      onChanged: (value) =>
                          setDialogState(() => compatibilityGroup = value ?? 0),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(Localization.translate('الغاء', lang)),
            ),
            ElevatedButton(
              onPressed: () async {
                final minValue =
                    double.tryParse(minCtrl.text.replaceAll(',', '.')) ?? 0;
                final maxValue =
                    double.tryParse(maxCtrl.text.replaceAll(',', '.')) ?? 0;
                if (selectedTarget == null || minValue >= maxValue) return;
                final targetParts = selectedTarget!.split(':');
                final targetId = int.tryParse(targetParts.last);
                if (targetId == null) return;
                final isFamily = targetParts.first == 'family';
                final selected = isFamily
                    ? _families.firstWhere((row) => row['id'] == targetId)
                    : _shutterComponents.firstWhere(
                        (row) => row['id'] == targetId,
                      );
                final productName = selected['name'].toString();
                final linkedComponentId = isFamily ? null : targetId;
                final linkedFamilyId = isFamily ? targetId : null;
                if (range == null) {
                  final insertResult = await widget.db.insertKitItemRange(
                    itemId: widget.item['id'],
                    minMm: minValue * divisor,
                    maxMm: maxValue * divisor,
                    productName: productName,
                    price: 0,
                    qty: double.tryParse(qtyCtrl.text) ?? 1,
                    compatibilityGroup: compatibilityGroup,
                    shutterComponentId: linkedComponentId,
                    familyId: linkedFamilyId,
                  );
                  if (insertResult == -2) {
                    if (ctx.mounted) {
                      ScaffoldMessenger.of(ctx).showSnackBar(
                        SnackBar(
                          content: Text(
                            Localization.translate(
                              'هذا المركّب مضاف سابقًا في نفس النطاق والمجموعة.',
                              lang,
                            ),
                          ),
                        ),
                      );
                    }
                    return;
                  }
                } else {
                  final updateResult = await widget.db.updateKitItemRange(
                    range['id'],
                    minMm: minValue * divisor,
                    maxMm: maxValue * divisor,
                    productName: productName,
                    price: 0,
                    qty: double.tryParse(qtyCtrl.text) ?? 1,
                    compatibilityGroup: compatibilityGroup,
                    shutterComponentId: linkedComponentId,
                    familyId: linkedFamilyId,
                  );
                  if (updateResult == -2) {
                    if (ctx.mounted) {
                      ScaffoldMessenger.of(ctx).showSnackBar(
                        SnackBar(
                          content: Text(
                            Localization.translate(
                              'هذا المركّب موجود في نطاق متداخل ضمن المجموعة نفسها.',
                              lang,
                            ),
                          ),
                        ),
                      );
                    }
                    return;
                  }
                }
                if (ctx.mounted) Navigator.pop(ctx);
                _loadRanges();
              },
              child: Text(
                Localization.translate(range == null ? 'اضافة' : 'حفظ', lang),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final lang = Provider.of<AppSettingsProvider>(context).language;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          '${widget.item['component_type']} - ${Localization.translate('النطاقات', lang)}',
        ),
        actions: [
          if (isAdmin)
            IconButton(
              icon: const Icon(Icons.add),
              onPressed: () => _showAddEditRangeDialog(),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _ranges.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.linear_scale, size: 48, color: Colors.grey),
                  const SizedBox(height: 12),
                  Text(
                    Localization.translate(
                      'لا توجد نطاقات — اضغط + لإضافة نطاق',
                      lang,
                    ),
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    widget.item['dimension'] == 'shutter_weight'
                        ? Localization.translate(
                            'مثال: من 1 كغ إلى 15 كغ',
                            lang,
                          )
                        : Localization.translate(
                            'مثال: من 80 سم إلى 120 سم',
                            lang,
                          ),
                    style: TextStyle(color: Colors.grey[400], fontSize: 12),
                  ),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: _ranges.length,
              itemBuilder: (ctx, i) {
                final r = _ranges[i];
                final isWeight = widget.item['dimension'] == 'shutter_weight';
                final divisor = isWeight ? 1.0 : 10.0;
                final unitLabel = isWeight ? 'كغ' : 'سم';
                final minCm = (r['min_mm'] / divisor).toStringAsFixed(
                  isWeight ? 1 : 0,
                );
                final maxCm = (r['max_mm'] / divisor).toStringAsFixed(
                  isWeight ? 1 : 0,
                );
                final rawGroup =
                    ((r['compatibility_group'] as num?)?.toInt() ?? 0).clamp(
                      0,
                      2,
                    );
                final groupLabel = rawGroup == 0
                    ? Localization.translate('مشترك', lang)
                    : rawGroup == 1
                    ? widget.group1Name
                    : widget.group2Name;
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.orange.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: Colors.orange.withOpacity(0.4),
                        ),
                      ),
                      child: Text(
                        '$minCm-$maxCm\n$unitLabel',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.orange,
                          fontSize: 11,
                        ),
                      ),
                    ),
                    title: Text(
                      r['family_id'] == null
                          ? r['product_name'] ?? ''
                          : '${Localization.translate('عائلة:', lang)} ${r['product_name'] ?? ''}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(
                      '${r['family_id'] != null
                          ? "تُضاف عناصر العائلة فقط عند مطابقة هذا النطاق"
                          : r['shutter_component_id'] == null
                          ? "⚠ ${Localization.translate('غير مرتبط بمركّب ستار', lang)}"
                          : Localization.translate('السعر مرتبط بإدارة الأسعار', lang)}'
                      '  |  ${Localization.translate('الكمية', lang)}: ${r['qty']?.toStringAsFixed(0)} ${Localization.translate('قطعة', lang)}'
                      '${isWeight ? "  |  $groupLabel" : ""}',
                    ),
                    trailing: isAdmin
                        ? Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.edit),
                                onPressed: () =>
                                    _showAddEditRangeDialog(range: r),
                              ),
                              IconButton(
                                icon: const Icon(
                                  Icons.delete,
                                  color: Colors.red,
                                ),
                                onPressed: () async {
                                  await widget.db.deleteKitItemRange(r['id']);
                                  _loadRanges();
                                },
                              ),
                            ],
                          )
                        : null,
                  ),
                );
              },
            ),
      floatingActionButton: isAdmin
          ? FloatingActionButton.extended(
              onPressed: () => _showAddEditRangeDialog(),
              icon: const Icon(Icons.add),
              label: Text(Localization.translate('إضافة نطاق', lang)),
              backgroundColor: Colors.orange,
            )
          : null,
    );
  }
}

// ---- KitItemVariantsScreen ----
class KitItemVariantsScreen extends StatefulWidget {
  final SqlDatabase db;
  final Map<String, dynamic> item;
  final String kitName;
  final bool isShutterKit;
  const KitItemVariantsScreen({
    super.key,
    required this.db,
    required this.item,
    required this.kitName,
    this.isShutterKit = false,
  });
  @override
  State<KitItemVariantsScreen> createState() => _KitItemVariantsScreenState();
}

class _KitItemVariantsScreenState extends State<KitItemVariantsScreen> {
  List<Map<String, dynamic>> _variants = [];
  bool _loading = true;
  List<String> _suggestedNames = [];

  @override
  void initState() {
    super.initState();
    _loadVariants();
    _loadSuggestions();
  }

  Future<void> _loadSuggestions() async {
    try {
      final shutterComps = await widget.db.readShutterComponents();
      final accessories = await widget.db.readAccessories();
      final names = <String>{};
      for (final c in shutterComps) {
        if (c['name'] != null) names.add(c['name'].toString().trim());
      }
      for (final a in accessories) {
        if (a['name'] != null) names.add(a['name'].toString().trim());
      }
      if (mounted) {
        setState(() {
          _suggestedNames = names.where((n) => n.isNotEmpty).toList();
        });
      }
    } catch (error) {
      debugPrint('Kit name suggestions unavailable: $error');
    }
  }

  Future<void> _loadVariants() async {
    setState(() => _loading = true);
    final v = await widget.db.readKitItemVariants(widget.item['id']);
    if (mounted)
      setState(() {
        _variants = v;
        _loading = false;
      });
  }

  bool get _isShutterKit {
    final nameLower = widget.kitName.toLowerCase();
    return widget.isShutterKit ||
        nameLower.contains('caisson') ||
        nameLower.contains('tunnel') ||
        nameLower.contains('volet') ||
        nameLower.contains('shutter') ||
        nameLower.contains('ستار');
  }

  Future<void> _showAddEditVariantDialog({
    Map<String, dynamic>? variant,
  }) async {
    final lang = Provider.of<AppSettingsProvider>(
      context,
      listen: false,
    ).language;
    String ouvrantType =
        variant?['ouvrant_type'] ?? (_isShutterKit ? 'normal' : 'simple');
    final nameCtrl = TextEditingController(
      text: variant?['product_name'] ?? '',
    );
    final priceCtrl = TextEditingController(
      text: (variant?['price'] ?? 0).toString(),
    );
    final qtyCtrl = TextEditingController(
      text: (variant?['qty'] ?? 1).toString(),
    );
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: Text(
            Localization.translate(
              variant == null ? 'إضافة متغير' : 'تعديل متغير',
              lang,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                Localization.translate(
                  _isShutterKit ? 'نوع شفرة الستار:' : 'نوع الضلفة:',
                  lang,
                ),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              if (_isShutterKit) ...[
                RadioListTile<String>(
                  title: Text(
                    Localization.translate('شفرة عادية (Normal)', lang),
                  ),
                  value: 'normal',
                  groupValue: ouvrantType,
                  onChanged: (v) => setS(() => ouvrantType = v!),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                ),
                RadioListTile<String>(
                  title: Text(
                    Localization.translate('شفرة إكسترودي (Extruded)', lang),
                  ),
                  value: 'extruded',
                  groupValue: ouvrantType,
                  onChanged: (v) => setS(() => ouvrantType = v!),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ] else ...[
                RadioListTile<String>(
                  title: const Text('Simple Ouvrant'),
                  value: 'simple',
                  groupValue: ouvrantType,
                  onChanged: (v) => setS(() => ouvrantType = v!),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                ),
                RadioListTile<String>(
                  title: const Text('Double Ouvrant'),
                  value: 'double',
                  groupValue: ouvrantType,
                  onChanged: (v) => setS(() => ouvrantType = v!),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ],
              const SizedBox(height: 10),
              Autocomplete<String>(
                initialValue: TextEditingValue(text: nameCtrl.text),
                optionsBuilder: (TextEditingValue textEditingValue) {
                  if (textEditingValue.text.isEmpty)
                    return const Iterable<String>.empty();
                  return _suggestedNames.where(
                    (option) => option.toLowerCase().contains(
                      textEditingValue.text.toLowerCase(),
                    ),
                  );
                },
                onSelected: (selection) => nameCtrl.text = selection,
                fieldViewBuilder: (ctx, ctrl, node, onSubmit) {
                  ctrl.addListener(() => nameCtrl.text = ctrl.text);
                  return TextField(
                    controller: ctrl,
                    focusNode: node,
                    onSubmitted: (v) => onSubmit(),
                    decoration: InputDecoration(
                      labelText: Localization.translate('اسم المنتج', lang),
                      border: const OutlineInputBorder(),
                    ),
                  );
                },
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: priceCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: Localization.translate('السعر', lang),
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: qtyCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: Localization.translate('الكمية', lang),
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(Localization.translate('الغاء', lang)),
            ),
            ElevatedButton(
              onPressed: () async {
                if (nameCtrl.text.trim().isEmpty) return;
                if (variant == null) {
                  await widget.db.insertKitItemVariant(
                    itemId: widget.item['id'],
                    ouvrantType: ouvrantType,
                    productName: nameCtrl.text.trim(),
                    price: double.tryParse(priceCtrl.text) ?? 0,
                    qty: double.tryParse(qtyCtrl.text) ?? 1,
                  );
                } else {
                  await widget.db.updateKitItemVariant(
                    variant['id'],
                    ouvrantType: ouvrantType,
                    productName: nameCtrl.text.trim(),
                    price: double.tryParse(priceCtrl.text) ?? 0,
                    qty: double.tryParse(qtyCtrl.text) ?? 1,
                  );
                }
                if (ctx.mounted) Navigator.pop(ctx);
                _loadVariants();
              },
              child: Text(
                Localization.translate(variant == null ? 'اضافة' : 'حفظ', lang),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isShutter = _isShutterKit;
    final lang = Provider.of<AppSettingsProvider>(context).language;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          '${widget.item['component_type']} - ${Localization.translate('المتغيرات', lang)}',
        ),
        actions: [
          if (isAdmin)
            IconButton(
              icon: const Icon(Icons.add),
              onPressed: () => _showAddEditVariantDialog(),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _variants.isEmpty
          ? Center(
              child: Text(Localization.translate('لا توجد متغيرات بعد', lang)),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: _variants.length,
              itemBuilder: (ctx, i) {
                final v = _variants[i];
                final isSimpleOrNormal =
                    v['ouvrant_type'] == 'simple' ||
                    v['ouvrant_type'] == 'normal';

                String typeLabel = '';
                if (isShutter) {
                  typeLabel = v['ouvrant_type'] == 'extruded'
                      ? Localization.translate('شفرة إكسترودي (Extruded)', lang)
                      : Localization.translate('شفرة عادية (Normal)', lang);
                } else {
                  typeLabel = v['ouvrant_type'] == 'double'
                      ? 'Double Ouvrant'
                      : 'Simple Ouvrant';
                }

                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: isSimpleOrNormal
                          ? Colors.blue
                          : Colors.purple,
                      child: Text(
                        isSimpleOrNormal
                            ? (isShutter ? 'N' : 'S')
                            : (isShutter ? 'E' : 'D'),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    title: Text(v['product_name'] ?? ''),
                    subtitle: Text(
                      '$typeLabel  |  ${Localization.translate('السعر', lang)}: ${v['price']}  |  ${Localization.translate('الكمية', lang)}: ${v['qty']?.toStringAsFixed(0)}',
                    ),
                    trailing: isAdmin
                        ? Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.edit),
                                onPressed: () =>
                                    _showAddEditVariantDialog(variant: v),
                              ),
                              IconButton(
                                icon: const Icon(
                                  Icons.delete,
                                  color: Colors.red,
                                ),
                                onPressed: () async {
                                  await widget.db.deleteKitItemVariant(v['id']);
                                  _loadVariants();
                                },
                              ),
                            ],
                          )
                        : null,
                  ),
                );
              },
            ),
      floatingActionButton: isAdmin
          ? FloatingActionButton.extended(
              onPressed: () => _showAddEditVariantDialog(),
              icon: const Icon(Icons.add),
              label: Text(Localization.translate('إضافة متغير', lang)),
              backgroundColor: Colors.purple,
            )
          : null,
    );
  }
}
