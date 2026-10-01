import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../sql_database.dart';
import '../settings/app_settings.dart';

class TemperedGlassItemsScreen extends StatefulWidget {
  final SqlDatabase db;

  const TemperedGlassItemsScreen({super.key, required this.db});

  @override
  State<TemperedGlassItemsScreen> createState() => _TemperedGlassItemsScreenState();
}

class _TemperedGlassItemsScreenState extends State<TemperedGlassItemsScreen> {
  List<Map<String, dynamic>> _items = [];
  bool _isLoading = true;
  String _selectedCategory = 'all';
  String _searchQuery = '';
  final TextEditingController _searchCtrl = TextEditingController();

  String _tr(String ar, String fr, String en) {
    final lang = Provider.of<AppSettingsProvider>(context, listen: false).language;
    return switch (lang) {
      AppLanguage.french => fr,
      AppLanguage.english => en,
      _ => ar,
    };
  }

  @override
  void initState() {
    super.initState();
    _loadItems();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadItems() async {
    setState(() => _isLoading = true);
    final items = await widget.db.getTemperedGlassItems();
    if (mounted) {
      setState(() {
        _items = items;
        _isLoading = false;
      });
    }
  }

  List<Map<String, dynamic>> get _filteredItems {
    return _items.where((item) {
      final matchesCategory = _selectedCategory == 'all' || item['category'] == _selectedCategory;
      final q = _searchQuery.trim().toLowerCase();
      final matchesSearch = q.isEmpty ||
          (item['name'] ?? '').toString().toLowerCase().contains(q) ||
          (item['notes'] ?? '').toString().toLowerCase().contains(q) ||
          (item['category_name'] ?? '').toString().toLowerCase().contains(q);
      return matchesCategory && matchesSearch;
    }).toList();
  }

  String _categoryLabel(String key) {
    return switch (key) {
      'all' => _tr('الكل', 'Tous', 'All'),
      'poignee' => _tr('المقابض', 'Poignées', 'Handles'),
      'charniere' => _tr('المفصلات', 'Charnières', 'Hinges'),
      'profile' => _tr('القطاعات والسكك', 'Profilés & Rails', 'Profiles & Rails'),
      'fixation' => _tr('التثبيت والمشابك', 'Fixations & Pinces', 'Clamps & Fixations'),
      'joint' => _tr('الجوانات والعوازل', 'Joints d\'étanchéité', 'Seals & Gaskets'),
      'serrure' => _tr('الأقفال والمزاليج', 'Serrures & Verrous', 'Locks'),
      _ => _tr('أخرى', 'Autres', 'Others'),
    };
  }

  IconData _categoryIcon(String category) {
    return switch (category) {
      'poignee' => Icons.door_sliding_outlined,
      'charniere' => Icons.view_sidebar_outlined,
      'profile' => Icons.view_column_outlined,
      'fixation' => Icons.hardware_outlined,
      'joint' => Icons.linear_scale_outlined,
      'serrure' => Icons.lock_outline,
      _ => Icons.category_outlined,
    };
  }

  Future<void> _showAddEditItemDialog([Map<String, dynamic>? existing]) async {
    final isEdit = existing != null;
    final nameCtrl = TextEditingController(text: existing?['name']?.toString() ?? '');
    final priceCtrl = TextEditingController(text: existing != null ? (existing['price'] as num?)?.toString() ?? '0' : '');
    final costCtrl = TextEditingController(text: existing != null ? (existing['cost_price'] as num?)?.toString() ?? '0' : '');
    final notesCtrl = TextEditingController(text: existing?['notes']?.toString() ?? '');
    final entraxeCtrl = TextEditingController(text: existing != null ? (existing['entraxe'] as num?)?.toString() ?? '0' : '0');
    final holesCtrl = TextEditingController(text: existing != null ? (existing['holes_count'] as num?)?.toString() ?? '0' : '0');

    String category = existing?['category']?.toString() ?? (_selectedCategory != 'all' ? _selectedCategory : 'poignee');
    String type = existing?['type']?.toString() ?? 'accessoire';
    String unit = existing?['unit']?.toString() ?? 'piece';

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (context, setDlg) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(
            isEdit
                ? _tr('تعديل عنصر زجاج مقسّى', 'Modifier élément verre trempé', 'Edit tempered glass item')
                : _tr('إضافة عنصر زجاج مقسّى', 'Ajouter élément verre trempé', 'Add tempered glass item'),
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
          ),
          content: SingleChildScrollView(
            child: SizedBox(
              width: 480,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameCtrl,
                    decoration: InputDecoration(
                      labelText: _tr('اسم العنصر / الموديل', 'Nom / Modèle', 'Item Name / Model'),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      prefixIcon: const Icon(Icons.label_outline),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: category,
                          decoration: InputDecoration(
                            labelText: _tr('الفئة', 'Catégorie', 'Category'),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          items: const ['poignee', 'charniere', 'profile', 'fixation', 'joint', 'serrure', 'autre']
                              .map((c) => DropdownMenuItem(value: c, child: Text(_categoryLabel(c))))
                              .toList(),
                          onChanged: (v) => setDlg(() => category = v ?? 'poignee'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: type,
                          decoration: InputDecoration(
                            labelText: _tr('النوع', 'Type', 'Type'),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          items: [
                            DropdownMenuItem(value: 'accessoire', child: Text(_tr('إكسسوار', 'Accessoire', 'Accessory'))),
                            DropdownMenuItem(value: 'profile', child: Text(_tr('قطاع / سكة', 'Profilé / Rail', 'Profile / Rail'))),
                          ],
                          onChanged: (v) => setDlg(() => type = v ?? 'accessoire'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: unit,
                          decoration: InputDecoration(
                            labelText: _tr('وحدة القياس', 'Unité', 'Unit'),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          items: [
                            DropdownMenuItem(value: 'piece', child: Text(_tr('قطعة (Pièce)', 'Pièce', 'Piece'))),
                            DropdownMenuItem(value: 'meter', child: Text(_tr('متر طولي (m)', 'Mètre linéaire', 'Linear meter'))),
                          ],
                          onChanged: (v) => setDlg(() => unit = v ?? 'piece'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: priceCtrl,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: InputDecoration(
                            labelText: _tr('سعر البيع (د.ج)', 'Prix de vente (DZD)', 'Selling Price (DZD)'),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            prefixIcon: const Icon(Icons.sell_outlined),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: costCtrl,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: InputDecoration(
                            labelText: _tr('سعر التكلفة (د.ج)', 'Prix de revient (DZD)', 'Cost Price (DZD)'),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            prefixIcon: const Icon(Icons.monetization_on_outlined),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: holesCtrl,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: _tr('عدد الثقوب', 'Nb de trous', 'Holes count'),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: entraxeCtrl,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: InputDecoration(
                            labelText: _tr('المسافة بين الثقوب (مم)', 'Entraxe (mm)', 'Entraxe (mm)'),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: notesCtrl,
                    maxLines: 2,
                    decoration: InputDecoration(
                      labelText: _tr('ملاحظات / مواصفات', 'Notes / Spécifications', 'Notes / Specs'),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx, false),
              child: Text(_tr('إلغاء', 'Annuler', 'Cancel')),
            ),
            FilledButton(
              onPressed: () {
                final name = nameCtrl.text.trim();
                if (name.isEmpty) return;
                Navigator.pop(dialogCtx, true);
              },
              child: Text(_tr('حفظ', 'Enregistrer', 'Save')),
            ),
          ],
        ),
      ),
    );

    if (saved == true && mounted) {
      final name = nameCtrl.text.trim();
      final price = double.tryParse(priceCtrl.text.trim()) ?? 0.0;
      final cost = double.tryParse(costCtrl.text.trim()) ?? 0.0;
      final holes = int.tryParse(holesCtrl.text.trim()) ?? 0;
      final entraxe = double.tryParse(entraxeCtrl.text.trim()) ?? 0.0;
      final notes = notesCtrl.text.trim();

      final itemData = {
        'name': name,
        'category': category,
        'category_name': _categoryLabel(category),
        'type': type,
        'unit': unit,
        'price': price,
        'cost_price': cost,
        'holes_count': holes,
        'entraxe': entraxe,
        'notes': notes,
        'is_active': 1,
      };

      if (isEdit) {
        await widget.db.updateTemperedGlassItem(existing['id'] as int, itemData);
      } else {
        await widget.db.insertTemperedGlassItem(itemData);
      }
      _loadItems();
    }
  }

  Future<void> _deleteItem(int id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_tr('حذف العنصر؟', 'Supprimer l\'élément ?', 'Delete item?')),
        content: Text(_tr('هل أنت متأكد من رغبتك في حذف هذا العنصر من كتالوج الزجاج المقسى؟',
            'Êtes-vous sûr de vouloir supprimer cet élément ?', 'Are you sure you want to delete this item?')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(_tr('إلغاء', 'Annuler', 'Cancel'))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(_tr('حذف', 'Supprimer', 'Delete')),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await widget.db.deleteTemperedGlassItem(id);
      _loadItems();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final filtered = _filteredItems;

    return Scaffold(
      appBar: AppBar(
        title: Text(_tr('إكسسوارات وقطاعات الزجاج المقسّى', 'Accessoires & profilés verre trempé', 'Tempered Glass Accessories & Profiles')),
        backgroundColor: isDark ? null : Colors.teal.shade700,
        foregroundColor: Colors.white,
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: _tr('تحديث', 'Actualiser', 'Refresh'),
            icon: const Icon(Icons.refresh),
            onPressed: _loadItems,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: Colors.teal.shade700,
        foregroundColor: Colors.white,
        onPressed: () => _showAddEditItemDialog(),
        icon: const Icon(Icons.add),
        label: Text(_tr('إضافة عنصر جديد', 'Ajouter un élément', 'Add New Item')),
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            color: isDark ? Colors.grey.shade900 : Colors.teal.shade50,
            child: Column(
              children: [
                TextField(
                  controller: _searchCtrl,
                  decoration: InputDecoration(
                    hintText: _tr('بحث عن إكسسوار، مقبض، قطاع أو مفصلة...', 'Rechercher un accessoire, profilé...', 'Search item, profile, handle...'),
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _searchCtrl.clear();
                              setState(() => _searchQuery = '');
                            },
                          )
                        : null,
                    filled: true,
                    fillColor: Theme.of(context).cardColor,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  onChanged: (val) => setState(() => _searchQuery = val),
                ),
                const SizedBox(height: 10),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      'all',
                      'poignee',
                      'charniere',
                      'profile',
                      'fixation',
                      'joint',
                      'serrure',
                    ].map((cat) {
                      final isSelected = _selectedCategory == cat;
                      return Padding(
                        padding: const EdgeInsets.only(right: 6, left: 6),
                        child: ChoiceChip(
                          selected: isSelected,
                          label: Text(_categoryLabel(cat)),
                          avatar: Icon(_categoryIcon(cat), size: 16),
                          selectedColor: Colors.teal.shade600,
                          labelStyle: TextStyle(
                            color: isSelected ? Colors.white : null,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          ),
                          onSelected: (_) => setState(() => _selectedCategory = cat),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : filtered.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.inventory_2_outlined, size: 64, color: Colors.grey.shade400),
                            const SizedBox(height: 12),
                            Text(
                              _tr('لا توجد عناصر مطابقة', 'Aucun élément trouvé', 'No items found'),
                              style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
                            ),
                          ],
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
                        itemCount: filtered.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final item = filtered[index];
                          final id = item['id'] as int;
                          final name = item['name']?.toString() ?? '';
                          final cat = item['category']?.toString() ?? '';
                          final unit = item['unit']?.toString() ?? 'piece';
                          final price = (item['price'] as num?)?.toDouble() ?? 0.0;
                          final cost = (item['cost_price'] as num?)?.toDouble() ?? 0.0;
                          final holes = (item['holes_count'] as num?)?.toInt() ?? 0;
                          final entraxe = (item['entraxe'] as num?)?.toDouble() ?? 0.0;
                          final notes = item['notes']?.toString() ?? '';

                          return Card(
                            elevation: 1,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: BorderSide(color: Colors.teal.shade200.withValues(alpha: 0.5)),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Container(
                                    width: 48,
                                    height: 48,
                                    decoration: BoxDecoration(
                                      color: Colors.teal.shade50,
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Icon(_categoryIcon(cat), color: Colors.teal.shade800, size: 26),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          name,
                                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                                        ),
                                        const SizedBox(height: 4),
                                        Wrap(
                                          spacing: 8,
                                          runSpacing: 4,
                                          children: [
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: Colors.grey.shade200,
                                                borderRadius: BorderRadius.circular(4),
                                              ),
                                              child: Text(
                                                _categoryLabel(cat),
                                                style: TextStyle(fontSize: 11, color: Colors.grey.shade800),
                                              ),
                                            ),
                                            if (holes > 0)
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: Colors.blue.shade50,
                                                  borderRadius: BorderRadius.circular(4),
                                                ),
                                                child: Text(
                                                  '${_tr('ثقوب', 'trous', 'holes')}: $holes${entraxe > 0 ? ' (E: ${entraxe.toStringAsFixed(0)}mm)' : ''}',
                                                  style: TextStyle(fontSize: 11, color: Colors.blue.shade800),
                                                ),
                                              ),
                                            if (notes.isNotEmpty)
                                              Text(
                                                notes,
                                                style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                                              ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text(
                                        '${price.toStringAsFixed(0)} DZD',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 15,
                                          color: Colors.teal.shade800,
                                        ),
                                      ),
                                      Text(
                                        unit == 'meter' ? _tr('للمتر', '/m', '/m') : _tr('للقطعة', '/pièce', '/pc'),
                                        style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                                      ),
                                      if (cost > 0)
                                        Text(
                                          '${_tr('التكلفة', 'Coût', 'Cost')}: ${cost.toStringAsFixed(0)}',
                                          style: TextStyle(fontSize: 10.5, color: Colors.grey.shade500),
                                        ),
                                    ],
                                  ),
                                  const SizedBox(width: 8),
                                  PopupMenuButton<String>(
                                    icon: const Icon(Icons.more_vert, size: 20),
                                    onSelected: (val) {
                                      if (val == 'edit') {
                                        _showAddEditItemDialog(item);
                                      } else if (val == 'delete') {
                                        _deleteItem(id);
                                      }
                                    },
                                    itemBuilder: (_) => [
                                      PopupMenuItem(
                                        value: 'edit',
                                        child: Row(
                                          children: [
                                            const Icon(Icons.edit, size: 18, color: Colors.blue),
                                            const SizedBox(width: 8),
                                            Text(_tr('تعديل', 'Modifier', 'Edit')),
                                          ],
                                        ),
                                      ),
                                      PopupMenuItem(
                                        value: 'delete',
                                        child: Row(
                                          children: [
                                            const Icon(Icons.delete, size: 18, color: Colors.red),
                                            const SizedBox(width: 8),
                                            Text(_tr('حذف', 'Supprimer', 'Delete')),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
