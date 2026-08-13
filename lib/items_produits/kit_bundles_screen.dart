import 'package:flutter/material.dart';
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
  void initState() { super.initState(); _loadKits(); }

  Future<void> _loadKits() async {
    setState(() => _loading = true);
    final kits = await widget.db.readKitBundles();
    if (mounted) setState(() { _kits = kits; _loading = false; });
  }

  Future<void> _showAddEditKitDialog({Map<String, dynamic>? kit}) async {
    final nameCtrl = TextEditingController(text: kit?['name'] ?? '');
    final descCtrl = TextEditingController(text: kit?['description'] ?? '');
    bool perLeaf = (kit?['per_leaf'] ?? 0) == 1;
    final lang = Provider.of<AppSettingsProvider>(context, listen: false).language;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: Text(kit == null ? Localization.translate('اضافة Kit', lang) : Localization.translate('تعديل Kit', lang)),
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
                    description: descCtrl.text.trim().isEmpty ? null : descCtrl.text.trim(),
                    perLeaf: perLeaf,
                  );
                } else {
                  await widget.db.updateKitBundle(
                    kit['id'],
                    name: nameCtrl.text.trim(),
                    description: descCtrl.text.trim().isEmpty ? null : descCtrl.text.trim(),
                    perLeaf: perLeaf,
                  );
                }
                if (ctx.mounted) Navigator.pop(ctx);
                _loadKits();
              },
              child: Text(kit == null ? Localization.translate('اضافة', lang) : Localization.translate('حفظ', lang)),
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
            )
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
                        const Icon(Icons.inventory_2_outlined, size: 64, color: Colors.grey),
                        const SizedBox(height: 16),
                        Text(
                          Localization.translate('لا توجد نتائج مطابقة', lang),
                          style: const TextStyle(color: Colors.grey),
                        )
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
                            backgroundColor: Theme.of(context).colorScheme.primary,
                            child: const Icon(Icons.inventory_2, color: Colors.white),
                          ),
                          title: Text(kit['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: perLeaf
                              ? Text(
                                  Localization.translate('Kit لكل ضلفة', lang),
                                  style: const TextStyle(color: Colors.blue, fontSize: 12),
                                )
                              : null,
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.list_alt),
                                onPressed: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => KitItemsScreen(db: widget.db, kit: kit),
                                  ),
                                ),
                              ),
                              if (isAdmin) ...[
                                IconButton(
                                  icon: const Icon(Icons.edit),
                                  onPressed: () => _showAddEditKitDialog(kit: kit),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete, color: Colors.red),
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
  const KitItemsScreen({super.key, required this.db, required this.kit});
  @override
  State<KitItemsScreen> createState() => _KitItemsScreenState();
}

class _KitItemsScreenState extends State<KitItemsScreen> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  List<String> _suggestedNames = [];

  @override
  void initState() {
    super.initState();
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
        if (c['component_type'] != null) names.add(c['component_type'].toString().trim());
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
    } catch (_) {}
  }

  Future<void> _loadItems() async {
    setState(() => _loading = true);
    final items = await widget.db.readKitBundleItemsWithDetails(widget.kit['id']);
    if (mounted) setState(() { _items = items; _loading = false; });
  }

  String _qtyModeLabel(String mode, AppLanguage lang) {
    switch (mode) {
      case 'by_range': return Localization.translate('بالنطاق', lang);
      case 'by_variant': return 'Simple/Double';
      default: return Localization.translate('ثابتة', lang);
    }
  }
  Color _qtyModeColor(String mode) {
    switch (mode) {
      case 'by_range': return Colors.orange;
      case 'by_variant': return Colors.purple;
      default: return Colors.teal;
    }
  }
  String _dimLabel(String? dim, AppLanguage lang) {
    if (dim == 'leaf_height') return Localization.translate('طول الضلفة', lang);
    if (dim == 'leaf_width') return Localization.translate('عرض الضلفة', lang);
    if (dim == 'shutter_weight') return 'وزن الستار';
    return '';
  }

  Future<void> _showAddEditItemDialog({Map<String, dynamic>? item}) async {
    final typeCtrl = TextEditingController(text: item?['component_type'] ?? '');
    String qtyMode = item?['qty_mode'] ?? 'fixed';
    String? dimension = item?['dimension'];
    final baseQtyCtrl = TextEditingController(text: (item?['base_qty'] ?? 1).toString());
    String unit = item?['unit'] ?? 'قطعة';
    String mechanismScope = item?['mechanism_scope'] ?? 'all';
    final units = ['قطعة', 'متر', 'بارة', 'مجموعة'];
    final lang = Provider.of<AppSettingsProvider>(context, listen: false).language;

    final translatedUnits = {
      'قطعة': Localization.translate('قطعة', lang),
      'متر': Localization.translate('متر', lang),
      'بارة': Localization.translate('بارة', lang),
      'مجموعة': Localization.translate('مجموعة', lang),
    };

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: Text(item == null ? Localization.translate('اضافة مركب', lang) : Localization.translate('تعديل مركب', lang)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Autocomplete<String>(
                  initialValue: TextEditingValue(text: typeCtrl.text),
                  optionsBuilder: (TextEditingValue textEditingValue) {
                    if (textEditingValue.text.isEmpty) return _suggestedNames;
                    return _suggestedNames.where((option) => option.toLowerCase().contains(textEditingValue.text.toLowerCase()));
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
                        hintText: Localization.translate('اكتب أو اختر من القائمة...', lang),
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
                Text(Localization.translate('نوع الكمية:', lang), style: const TextStyle(fontWeight: FontWeight.bold)),
                RadioListTile<String>(
                  title: Text(Localization.translate('ثابتة', lang)),
                  value: 'fixed',
                  groupValue: qtyMode,
                  onChanged: (v) => setS(() => qtyMode = v!),
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                ),
                RadioListTile<String>(
                  title: Text(Localization.translate('بالنطاق (حسب القياس)', lang)),
                  value: 'by_range',
                  groupValue: qtyMode,
                  onChanged: (v) => setS(() => qtyMode = v!),
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                ),
                RadioListTile<String>(
                  title: Text(Localization.translate('بالنوع (Simple/Double Ouvrant)', lang)),
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
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: Localization.translate('الكمية', lang),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ],
                if (qtyMode == 'by_range') ...[
                  const SizedBox(height: 12),
                  Text(Localization.translate('القياس المرجعي:', lang), style: const TextStyle(fontWeight: FontWeight.bold)),
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
                    title: const Text('وزن الستار (كغ)'),
                    value: 'shutter_weight',
                    groupValue: dimension,
                    onChanged: (v) => setS(() => dimension = v),
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                  ),
                ],
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  value: mechanismScope,
                  decoration: const InputDecoration(
                    labelText: 'استعمال المركب',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'all', child: Text('مشترك')),
                    DropdownMenuItem(value: 'belt', child: Text('للحزام فقط')),
                    DropdownMenuItem(value: 'crank', child: Text('للمانيفال فقط')),
                  ],
                  onChanged: (value) => setS(() => mechanismScope = value ?? 'all'),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  value: unit,
                  decoration: InputDecoration(
                    labelText: Localization.translate('الوحدة', lang),
                    border: const OutlineInputBorder(),
                  ),
                  items: units.map((u) => DropdownMenuItem(value: u, child: Text(translatedUnits[u] ?? u))).toList(),
                  onChanged: (v) => setS(() => unit = v!),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(Localization.translate('الغاء', lang)),
            ),
            ElevatedButton(
              onPressed: () async {
                if (typeCtrl.text.trim().isEmpty) return;
                if (item == null) {
                  await widget.db.insertKitBundleItem(
                    kitId: widget.kit['id'],
                    componentType: typeCtrl.text.trim(),
                    qtyMode: qtyMode,
                    dimension: qtyMode == 'by_range' ? dimension : null,
                    baseQty: double.tryParse(baseQtyCtrl.text) ?? 1,
                    unit: unit,
                    mechanismScope: mechanismScope,
                    sortOrder: _items.length,
                  );
                } else {
                  await widget.db.updateKitBundleItem(
                    item['id'],
                    componentType: typeCtrl.text.trim(),
                    qtyMode: qtyMode,
                    dimension: qtyMode == 'by_range' ? dimension : null,
                    baseQty: double.tryParse(baseQtyCtrl.text) ?? 1,
                    unit: unit,
                    mechanismScope: mechanismScope,
                    sortOrder: item['sort_order'] ?? 0,
                  );
                }
                if (ctx.mounted) Navigator.pop(ctx);
                _loadItems();
              },
              child: Text(item == null ? Localization.translate('اضافة', lang) : Localization.translate('حفظ', lang)),
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
        title: Text('${widget.kit['name']} - ' + Localization.translate('المركبات', lang)),
        actions: [if (isAdmin) IconButton(icon: const Icon(Icons.add), onPressed: () => _showAddEditItemDialog())],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
              ? Center(child: Text(Localization.translate('لا توجد مركبات بعد', lang)))
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: _items.length,
                  itemBuilder: (ctx, i) {
                    final item = _items[i];
                    final mode = (item['qty_mode'] ?? 'fixed') as String;
                    final dim = item['dimension'] as String?;
                    final ranges = item['ranges'] as List? ?? [];
                    final variants = item['variants'] as List? ?? [];
                    final mechanismScope = item['mechanism_scope']?.toString() ?? 'all';
                    final mechanismLabel = mechanismScope == 'belt'
                        ? 'للحزام فقط'
                        : mechanismScope == 'crank'
                        ? 'للمانيفال فقط'
                        : 'مشترك';

                    String qtyLabel = '';
                    if (mode == 'fixed') {
                      qtyLabel = 'x${(item['base_qty'] ?? 1).toStringAsFixed(0)}';
                    } else if (mode == 'by_range') {
                      final qtys = ranges.map((r) => (r['qty'] ?? 1.0) as num).toSet();
                      if (qtys.isEmpty) {
                        qtyLabel = '?';
                      } else if (qtys.length == 1) {
                        qtyLabel = 'x${qtys.first.toStringAsFixed(0)}';
                      } else {
                        final minQ = qtys.reduce((a, b) => a < b ? a : b);
                        final maxQ = qtys.reduce((a, b) => a > b ? a : b);
                        qtyLabel = '${minQ.toStringAsFixed(0)}-${maxQ.toStringAsFixed(0)}';
                      }
                    } else if (mode == 'by_variant') {
                      final qtys = variants.map((v) => (v['qty'] ?? 1.0) as num).toSet();
                      if (qtys.isEmpty) {
                        qtyLabel = '?';
                      } else if (qtys.length == 1) {
                        qtyLabel = 'x${qtys.first.toStringAsFixed(0)}';
                      } else {
                        final minQ = qtys.reduce((a, b) => a < b ? a : b);
                        final maxQ = qtys.reduce((a, b) => a > b ? a : b);
                        qtyLabel = '${minQ.toStringAsFixed(0)}-${maxQ.toStringAsFixed(0)}';
                      }
                    }

                    String modeDetails = '';
                    if (mode == 'by_range' && ranges.isNotEmpty) {
                      modeDetails = ' (' + ranges.map((r) {
                        final isWeight = dim == 'shutter_weight';
                        final divisor = isWeight ? 1.0 : 10.0;
                        final minCm = ((r['min_mm'] ?? 0) / divisor).toStringAsFixed(0);
                        final maxCm = ((r['max_mm'] ?? 0) / divisor).toStringAsFixed(0);
                        final qty = (r['qty'] ?? 1).toStringAsFixed(0);
                        final rawGroup = (r['compatibility_group'] as num?)?.toInt() ?? 0;
                        final groupLabel = rawGroup == 0 ? 'مشترك' : 'م$rawGroup';
                        return '$minCm-$maxCm${isWeight ? " كغ، $groupLabel" : ""}: $qty';
                      }).join(', ') + ')';
                    } else if (mode == 'by_variant' && variants.isNotEmpty) {
                      final isShutter = (widget.kit['name'] ?? '').toString().toLowerCase().contains('volet') ||
                          (widget.kit['name'] ?? '').toString().toLowerCase().contains('shutter') ||
                          (widget.kit['name'] ?? '').toString().contains('ستار');
                      modeDetails = ' (' + variants.map((v) {
                        final type = v['ouvrant_type'];
                        String typeLabel = type;
                        if (isShutter) {
                          typeLabel = type == 'extruded' ? 'Extruded' : 'Normal';
                        } else {
                          typeLabel = type == 'double' ? 'Double' : 'Simple';
                        }
                        final qty = (v['qty'] ?? 1).toStringAsFixed(0);
                        return '$typeLabel: $qty';
                      }).join(', ') + ')';
                    }

                    final unitStr = item['unit'] ?? '';
                    final translatedUnit = Localization.translate(unitStr, lang);

                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: _qtyModeColor(mode),
                          radius: 18,
                          child: Text(qtyLabel, style: const TextStyle(color: Colors.white, fontSize: 10)),
                        ),
                        title: Text(item['component_type'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text('${_qtyModeLabel(mode, lang)}$modeDetails${dim != null ? " | ${_dimLabel(dim, lang)}" : ""} | $mechanismLabel | $translatedUnit'),
                        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                          if (mode == 'by_range')
                            IconButton(
                              icon: const Icon(Icons.linear_scale, color: Colors.orange),
                              tooltip: Localization.translate('النطاقات', lang),
                              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => KitItemRangesScreen(db: widget.db, item: item))),
                            ),
                          if (mode == 'by_variant')
                            IconButton(
                              icon: const Icon(Icons.tune, color: Colors.purple),
                              tooltip: Localization.translate('المتغيرات', lang),
                              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => KitItemVariantsScreen(db: widget.db, item: item, kitName: widget.kit['name'] ?? ''))),
                            ),
                          if (isAdmin) ...[
                            IconButton(icon: const Icon(Icons.edit), onPressed: () => _showAddEditItemDialog(item: item)),
                            IconButton(
                              icon: const Icon(Icons.delete, color: Colors.red),
                              onPressed: () async {
                                await widget.db.deleteKitBundleItem(item['id']);
                                _loadItems();
                              },
                            ),
                          ],
                        ]),
                      ),
                    );
                  }),
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
  const KitItemRangesScreen({super.key, required this.db, required this.item});
  @override
  State<KitItemRangesScreen> createState() => _KitItemRangesScreenState();
}

class _KitItemRangesScreenState extends State<KitItemRangesScreen> {
  List<Map<String, dynamic>> _ranges = [];
  bool _loading = true;
  List<String> _suggestedNames = [];

  @override
  void initState() {
    super.initState();
    _loadRanges();
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
    } catch (_) {}
  }

  Future<void> _loadRanges() async {
    setState(() => _loading = true);
    final ranges = await widget.db.readKitItemRanges(widget.item['id']);
    if (mounted) setState(() { _ranges = ranges; _loading = false; });
  }
  String _dimLabel() {
    switch (widget.item['dimension']) {
      case 'leaf_height': return 'طول الضلفة (سم)';
      case 'leaf_width': return 'عرض الضلفة (سم)';
      case 'shutter_weight': return 'وزن الستار (كغ)';
      default: return 'القياس (سم)';
    }
  }
  Future<void> _showAddEditRangeDialog({Map<String, dynamic>? range}) async {
    final isWeight = widget.item['dimension'] == 'shutter_weight';
    final divisor = isWeight ? 1.0 : 10.0;
    final unitLabel = isWeight ? 'كغ' : 'سم';
    final minCtrl = TextEditingController(text: range != null ? (range['min_mm'] / divisor).toStringAsFixed(isWeight ? 1 : 0) : '');
    final maxCtrl = TextEditingController(text: range != null ? (range['max_mm'] / divisor).toStringAsFixed(isWeight ? 1 : 0) : '');
    final nameCtrl = TextEditingController(text: range?['product_name'] ?? '');
    final priceCtrl = TextEditingController(text: (range?['price'] ?? 0).toString());
    final qtyCtrl = TextEditingController(text: (range?['qty'] ?? 1).toString());
    int compatibilityGroup = ((range?['compatibility_group'] as num?)?.toInt() ?? 0).clamp(0, 2);
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setDialogState) => AlertDialog(
        title: Text(range == null ? 'اضافة نطاق' : 'تعديل النطاق'),
        content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(_dimLabel(), style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: TextField(controller: minCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(labelText: 'من ($unitLabel)', hintText: isWeight ? '1' : '80', border: const OutlineInputBorder()))),
            const SizedBox(width: 8),
            Expanded(child: TextField(controller: maxCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(labelText: 'إلى ($unitLabel)', hintText: isWeight ? '15' : '120', border: const OutlineInputBorder()))),
          ]),
          const SizedBox(height: 10),
          Autocomplete<String>(
            initialValue: TextEditingValue(text: nameCtrl.text),
            optionsBuilder: (TextEditingValue textEditingValue) {
              if (textEditingValue.text.isEmpty) return const Iterable<String>.empty();
              return _suggestedNames.where((option) => option.toLowerCase().contains(textEditingValue.text.toLowerCase()));
            },
            onSelected: (selection) => nameCtrl.text = selection,
            fieldViewBuilder: (ctx, ctrl, node, onSubmit) {
              ctrl.addListener(() => nameCtrl.text = ctrl.text);
              return TextField(
                controller: ctrl,
                focusNode: node,
                onSubmitted: (v) => onSubmit(),
                decoration: const InputDecoration(labelText: 'اسم المنتج', hintText: 'اختر أو اكتب اسم المنتج المالي', border: OutlineInputBorder()),
              );
            },
          ),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: TextField(controller: priceCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'السعر', border: OutlineInputBorder()))),
            const SizedBox(width: 8),
            Expanded(child: TextField(controller: qtyCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'الكمية', border: OutlineInputBorder()))),
          ]),
          if (isWeight) ...[
            const SizedBox(height: 10),
            DropdownButtonFormField<int>(
              value: compatibilityGroup,
              decoration: const InputDecoration(labelText: 'مجموعة التوافق', border: OutlineInputBorder()),
              items: const [
                DropdownMenuItem(value: 0, child: Text('مشترك بين المجموعتين')),
                DropdownMenuItem(value: 1, child: Text('المجموعة 1')),
                DropdownMenuItem(value: 2, child: Text('المجموعة 2')),
              ],
              onChanged: (value) => setDialogState(() => compatibilityGroup = value ?? 0),
            ),
          ],
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('الغاء')),
          ElevatedButton(
            onPressed: () async {
              final minValue = double.tryParse(minCtrl.text.replaceAll(',', '.')) ?? 0;
              final maxValue = double.tryParse(maxCtrl.text.replaceAll(',', '.')) ?? 0;
              if (nameCtrl.text.trim().isEmpty || minValue >= maxValue) return;
              if (range == null) {
                await widget.db.insertKitItemRange(itemId: widget.item['id'], minMm: minValue * divisor, maxMm: maxValue * divisor, productName: nameCtrl.text.trim(), price: double.tryParse(priceCtrl.text) ?? 0, qty: double.tryParse(qtyCtrl.text) ?? 1, compatibilityGroup: compatibilityGroup);
              } else {
                await widget.db.updateKitItemRange(range['id'], minMm: minValue * divisor, maxMm: maxValue * divisor, productName: nameCtrl.text.trim(), price: double.tryParse(priceCtrl.text) ?? 0, qty: double.tryParse(qtyCtrl.text) ?? 1, compatibilityGroup: compatibilityGroup);
              }
              if (ctx.mounted) Navigator.pop(ctx);
              _loadRanges();
            },
            child: Text(range == null ? 'اضافة' : 'حفظ'),
          ),
        ],
      )),
    );
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('${widget.item['component_type']} - النطاقات'), actions: [if (isAdmin) IconButton(icon: const Icon(Icons.add), onPressed: () => _showAddEditRangeDialog())]),
      body: _loading ? const Center(child: CircularProgressIndicator()) : _ranges.isEmpty
          ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.linear_scale, size: 48, color: Colors.grey), const SizedBox(height: 12), Text('لا توجد نطاقات — اضغط + لاضافة نطاق', style: TextStyle(color: Colors.grey[600])), const SizedBox(height: 6), Text(widget.item['dimension'] == 'shutter_weight' ? 'مثال: من 1 كغ إلى 15 كغ' : 'مثال: من 80 سم الى 120 سم', style: TextStyle(color: Colors.grey[400], fontSize: 12))]))
          : ListView.builder(
              padding: const EdgeInsets.all(12), itemCount: _ranges.length,
              itemBuilder: (ctx, i) {
                final r = _ranges[i];
                final isWeight = widget.item['dimension'] == 'shutter_weight';
                final divisor = isWeight ? 1.0 : 10.0;
                final unitLabel = isWeight ? 'كغ' : 'سم';
                final minCm = (r['min_mm'] / divisor).toStringAsFixed(isWeight ? 1 : 0);
                final maxCm = (r['max_mm'] / divisor).toStringAsFixed(isWeight ? 1 : 0);
                final rawGroup = ((r['compatibility_group'] as num?)?.toInt() ?? 0).clamp(0, 2);
                final groupLabel = rawGroup == 0 ? 'مشترك' : 'المجموعة $rawGroup';
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6), decoration: BoxDecoration(color: Colors.orange.withOpacity(0.15), borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.orange.withOpacity(0.4))),
                      child: Text('$minCm-$maxCm\n$unitLabel', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.orange, fontSize: 11))),
                    title: Text(r['product_name'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text('السعر: ${r['price']}  |  الكمية: ${r['qty']?.toStringAsFixed(0)}${isWeight ? "  |  $groupLabel" : ""}'),
                    trailing: isAdmin
                        ? Row(mainAxisSize: MainAxisSize.min, children: [
                            IconButton(icon: const Icon(Icons.edit), onPressed: () => _showAddEditRangeDialog(range: r)),
                            IconButton(icon: const Icon(Icons.delete, color: Colors.red), onPressed: () async { await widget.db.deleteKitItemRange(r['id']); _loadRanges(); }),
                          ])
                        : null,
                  ),
                );
              }),
      floatingActionButton: isAdmin ? FloatingActionButton.extended(onPressed: () => _showAddEditRangeDialog(), icon: const Icon(Icons.add), label: const Text('اضافة نطاق'), backgroundColor: Colors.orange) : null,
    );
  }
}

// ---- KitItemVariantsScreen ----
class KitItemVariantsScreen extends StatefulWidget {
  final SqlDatabase db;
  final Map<String, dynamic> item;
  final String kitName;
  const KitItemVariantsScreen({super.key, required this.db, required this.item, required this.kitName});
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
    } catch (_) {}
  }

  Future<void> _loadVariants() async {
    setState(() => _loading = true);
    final v = await widget.db.readKitItemVariants(widget.item['id']);
    if (mounted) setState(() { _variants = v; _loading = false; });
  }

  bool get _isShutterKit {
    final nameLower = widget.kitName.toLowerCase();
    return nameLower.contains('volet') || nameLower.contains('shutter') || nameLower.contains('ستار');
  }

  Future<void> _showAddEditVariantDialog({Map<String, dynamic>? variant}) async {
    String ouvrantType = variant?['ouvrant_type'] ?? (_isShutterKit ? 'normal' : 'simple');
    final nameCtrl = TextEditingController(text: variant?['product_name'] ?? '');
    final priceCtrl = TextEditingController(text: (variant?['price'] ?? 0).toString());
    final qtyCtrl = TextEditingController(text: (variant?['qty'] ?? 1).toString());
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: Text(variant == null ? 'اضافة متغير' : 'تعديل متغير'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(_isShutterKit ? 'نوع شفرة الستار:' : 'نوع الضلفة:', style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            if (_isShutterKit) ...[
              RadioListTile<String>(title: const Text('شفرة عادية (Normal)'), value: 'normal', groupValue: ouvrantType, onChanged: (v) => setS(() => ouvrantType = v!), dense: true, contentPadding: EdgeInsets.zero),
              RadioListTile<String>(title: const Text('شفرة إكسترودي (Extruded)'), value: 'extruded', groupValue: ouvrantType, onChanged: (v) => setS(() => ouvrantType = v!), dense: true, contentPadding: EdgeInsets.zero),
            ] else ...[
              RadioListTile<String>(title: const Text('Simple Ouvrant'), value: 'simple', groupValue: ouvrantType, onChanged: (v) => setS(() => ouvrantType = v!), dense: true, contentPadding: EdgeInsets.zero),
              RadioListTile<String>(title: const Text('Double Ouvrant'), value: 'double', groupValue: ouvrantType, onChanged: (v) => setS(() => ouvrantType = v!), dense: true, contentPadding: EdgeInsets.zero),
            ],
            const SizedBox(height: 10),
            Autocomplete<String>(
              initialValue: TextEditingValue(text: nameCtrl.text),
              optionsBuilder: (TextEditingValue textEditingValue) {
                if (textEditingValue.text.isEmpty) return const Iterable<String>.empty();
                return _suggestedNames.where((option) => option.toLowerCase().contains(textEditingValue.text.toLowerCase()));
              },
              onSelected: (selection) => nameCtrl.text = selection,
              fieldViewBuilder: (ctx, ctrl, node, onSubmit) {
                ctrl.addListener(() => nameCtrl.text = ctrl.text);
                return TextField(
                  controller: ctrl,
                  focusNode: node,
                  onSubmitted: (v) => onSubmit(),
                  decoration: const InputDecoration(labelText: 'اسم المنتج', border: OutlineInputBorder()),
                );
              },
            ),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: TextField(controller: priceCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'السعر', border: OutlineInputBorder()))),
              const SizedBox(width: 8),
              Expanded(child: TextField(controller: qtyCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'الكمية', border: OutlineInputBorder()))),
            ]),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('الغاء')),
            ElevatedButton(
              onPressed: () async {
                if (nameCtrl.text.trim().isEmpty) return;
                if (variant == null) {
                  await widget.db.insertKitItemVariant(itemId: widget.item['id'], ouvrantType: ouvrantType, productName: nameCtrl.text.trim(), price: double.tryParse(priceCtrl.text) ?? 0, qty: double.tryParse(qtyCtrl.text) ?? 1);
                } else {
                  await widget.db.updateKitItemVariant(variant['id'], ouvrantType: ouvrantType, productName: nameCtrl.text.trim(), price: double.tryParse(priceCtrl.text) ?? 0, qty: double.tryParse(qtyCtrl.text) ?? 1);
                }
                if (ctx.mounted) Navigator.pop(ctx);
                _loadVariants();
              },
              child: Text(variant == null ? 'اضافة' : 'حفظ'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isShutter = _isShutterKit;
    return Scaffold(
      appBar: AppBar(title: Text('${widget.item['component_type']} - المتغيرات'), actions: [if (isAdmin) IconButton(icon: const Icon(Icons.add), onPressed: () => _showAddEditVariantDialog())]),
      body: _loading ? const Center(child: CircularProgressIndicator()) : _variants.isEmpty
          ? const Center(child: Text('لا توجد متغيرات بعد'))
          : ListView.builder(
              padding: const EdgeInsets.all(12), itemCount: _variants.length,
              itemBuilder: (ctx, i) {
                final v = _variants[i];
                final isSimpleOrNormal = v['ouvrant_type'] == 'simple' || v['ouvrant_type'] == 'normal';
                
                String typeLabel = '';
                if (isShutter) {
                  typeLabel = v['ouvrant_type'] == 'extruded' ? 'شفرة إكسترودي (Extruded)' : 'شفرة عادية (Normal)';
                } else {
                  typeLabel = v['ouvrant_type'] == 'double' ? 'Double Ouvrant' : 'Simple Ouvrant';
                }

                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: isSimpleOrNormal ? Colors.blue : Colors.purple, 
                      child: Text(isSimpleOrNormal ? (isShutter ? 'N' : 'S') : (isShutter ? 'E' : 'D'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))
                    ),
                    title: Text(v['product_name'] ?? ''),
                    subtitle: Text('$typeLabel  |  السعر: ${v['price']}  |  الكمية: ${v['qty']?.toStringAsFixed(0)}'),
                    trailing: isAdmin
                        ? Row(mainAxisSize: MainAxisSize.min, children: [
                            IconButton(icon: const Icon(Icons.edit), onPressed: () => _showAddEditVariantDialog(variant: v)),
                            IconButton(icon: const Icon(Icons.delete, color: Colors.red), onPressed: () async { await widget.db.deleteKitItemVariant(v['id']); _loadVariants(); }),
                          ])
                        : null,
                  ),
                );
              }),
      floatingActionButton: isAdmin ? FloatingActionButton.extended(onPressed: () => _showAddEditVariantDialog(), icon: const Icon(Icons.add), label: const Text('اضافة متغير'), backgroundColor: Colors.purple) : null,
    );
  }
}
