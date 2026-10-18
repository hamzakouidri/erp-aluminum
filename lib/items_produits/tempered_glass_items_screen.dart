import 'dart:io';
import 'package:database_data/widgets/app_material.dart';
import 'package:provider/provider.dart';
import '../sql_database.dart';
import '../settings/app_settings.dart';
import '../Commande/glass_handle_designs.dart';
import '../Commande/tempered_glass_hardware.dart';

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
      'faconnage' => _tr('الخدمات والتشطيب', 'Façonnage & Sablage', 'Finishing services'),
      _ => _tr('أخرى', 'Autres', 'Others'),
    };
  }

  static String _mm(double value) =>
      value == value.roundToDouble() ? value.toStringAsFixed(0) : value.toString();

  String _mountLabel(String target) => switch (target) {
    GlassMountTarget.door => _tr('الباب', 'Porte', 'Door'),
    GlassMountTarget.fixed => _tr('الثابت', 'Fixe', 'Fixed panel'),
    GlassMountTarget.frame => _tr('الحائط / الإطار', 'Mur / cadre', 'Wall / frame'),
    GlassMountTarget.between => _tr('بين الثابت والباب', 'Entre fixe et porte', 'Between fixed and door'),
    _ => _tr('الكل', 'Tous', 'Any'),
  };

  String _gasketLabel(String type) => switch (type) {
    GlassGasketType.magnetic90 => _tr('جوان مغناطيسي 90°', 'Joint magnétique 90°', 'Magnetic gasket 90°'),
    GlassGasketType.magnetic180 => _tr('جوان مغناطيسي 180°', 'Joint magnétique 180°', 'Magnetic gasket 180°'),
    GlassGasketType.h => _tr('جوان H (بشفة)', 'Joint H (à lèvre)', 'H gasket (with lip)'),
    GlassGasketType.f => _tr('جوان F (بشفة)', 'Joint F (à lèvre)', 'F gasket (with lip)'),
    GlassGasketType.bulb => _tr('جوان بومبي', 'Joint bombé', 'Bulb gasket'),
    GlassGasketType.rail => _tr('جوان البروفيل (بالمتر)', 'Joint de profilé (au mètre)', 'Profile gasket (per metre)'),
    _ => _tr('غير محدد', 'Non défini', 'Not set'),
  };

  String _profileRoleLabel(String role) => switch (role) {
    GlassProfileRole.uChannel => _tr('بروفيل U للثابت (باغيت)', 'Profilé U du fixe (baguette)', 'Fixed panel U channel'),
    GlassProfileRole.topRail => _tr('الراي العلوي', 'Rail supérieur', 'Top rail'),
    _ => _tr('غير محدد', 'Non défini', 'Not set'),
  };

  IconData _categoryIcon(String category) {
    return switch (category) {
      'poignee' => Icons.door_sliding_outlined,
      'charniere' => Icons.view_sidebar_outlined,
      'profile' => Icons.view_column_outlined,
      'fixation' => Icons.hardware_outlined,
      'joint' => Icons.linear_scale_outlined,
      'serrure' => Icons.lock_outline,
      'faconnage' => Icons.auto_fix_high_outlined,
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
    String imagePath = existing?['image_path']?.toString() ?? '';
    String handleDesignCode = existing?['handle_design_code']?.toString() ?? '';
    final holeDiametersCtrl = TextEditingController(
      text: existing?['hole_diameters']?.toString() ?? '',
    );
    final holeSpacingsCtrl = TextEditingController(
      text: existing?['hole_spacings']?.toString() ?? '',
    );
    bool verticalHoles = existing?['hole_layout']?.toString() == 'vertical';
    String mountTarget =
        GlassMountTarget.values.contains(existing?['mount_target'])
        ? existing!['mount_target'].toString()
        : GlassMountTarget.all;
    double glassThickness =
        (existing?['glass_thickness_mm'] as num?)?.toDouble() ?? 0.0;
    String jointType =
        GlassGasketType.values.contains(existing?['joint_type'])
        ? existing!['joint_type'].toString()
        : '';
    final colorPrices = [...parseColorPrices(existing?['color_prices'])];
    final newColorCtrl = TextEditingController();
    final newColorPriceCtrl = TextEditingController();
    String profileRole =
        GlassProfileRole.values.contains(existing?['profile_role'])
        ? existing!['profile_role'].toString()
        : '';
    if (category == 'poignee' && handleDesignCode.isEmpty) {
      final resolved = GlassHandleDesignCatalog.resolveForItem(existing);
      handleDesignCode = resolved.code;
      if (imagePath.isEmpty) imagePath = resolved.assetPath;
    }

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
                  if (category == 'poignee') ...[
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.teal.shade50.withValues(alpha: 0.7),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.teal.shade300, width: 1.2),
                      ),
                      child: Row(
                        children: [
                          GlassHandleThumbnailView(
                            imagePath: imagePath,
                            designCode: handleDesignCode,
                            size: 58,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _tr(
                                    'الرسمة والصورة المرتبطة',
                                    'Modèle de dessin lié',
                                    'Linked Drawing Design',
                                  ),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  handleDesignCode.isNotEmpty
                                      ? (GlassHandleDesignCatalog.findByCode(handleDesignCode)?.labelAr ?? handleDesignCode)
                                      : (imagePath.isNotEmpty ? 'صورة محددة' : 'اختر تصميم المقبض'),
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.teal.shade900,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          FilledButton.icon(
                            style: FilledButton.styleFrom(
                              backgroundColor: Colors.teal.shade700,
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            onPressed: () async {
                              final picked = await GlassHandleDesignPickerModal.show(
                                context,
                                currentCode: handleDesignCode,
                                currentImagePath: imagePath,
                              );
                              if (picked != null) {
                                setDlg(() {
                                  handleDesignCode = picked.code;
                                  imagePath = picked.assetPath;
                                  if (nameCtrl.text.trim().isEmpty) {
                                    nameCtrl.text = picked.labelAr;
                                  }
                                  if (holesCtrl.text == '0' || holesCtrl.text.isEmpty) {
                                    holesCtrl.text = picked.defaultHolesCount.toString();
                                  }
                                  if (entraxeCtrl.text == '0' || entraxeCtrl.text.isEmpty) {
                                    entraxeCtrl.text = picked.defaultEntraxe.toStringAsFixed(0);
                                  }
                                });
                              }
                            },
                            icon: const Icon(Icons.photo_library_outlined, size: 16),
                            label: Text(_tr('تغيير', 'Changer', 'Change'), style: const TextStyle(fontSize: 12)),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: category,
                          decoration: InputDecoration(
                            labelText: _tr('الفئة', 'Catégorie', 'Category'),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          items: const ['poignee', 'charniere', 'profile', 'fixation', 'joint', 'serrure', 'faconnage', 'autre']
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
                            DropdownMenuItem(value: 'sqm', child: Text(_tr('متر مربع (m²)', 'Mètre carré (m²)', 'Square meter (m²)'))),
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
                  // Drilling pattern: one diameter per hole and the centre
                  // distance from each hole to the next.
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: holeDiametersCtrl,
                          decoration: InputDecoration(
                            labelText: _tr('قطر كل ثقب (مم)', 'Ø de chaque trou (mm)', 'Each hole Ø (mm)'),
                            hintText: '12, 12, 10',
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: holeSpacingsCtrl,
                          decoration: InputDecoration(
                            labelText: _tr('المسافة بين كل ثقب والذي يليه (مم)', 'Entraxe entre trous successifs (mm)', 'Spacing between holes (mm)'),
                            hintText: '150, 200',
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
                        child: DropdownButtonFormField<bool>(
                          value: verticalHoles,
                          decoration: InputDecoration(
                            labelText: _tr('اتجاه الثقوب', 'Sens des trous', 'Holes direction'),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          items: [
                            DropdownMenuItem(value: false, child: Text(_tr('أفقي', 'Horizontal', 'Horizontal'))),
                            DropdownMenuItem(value: true, child: Text(_tr('عمودي', 'Vertical', 'Vertical'))),
                          ],
                          onChanged: (v) => setDlg(() => verticalHoles = v ?? false),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: mountTarget,
                          decoration: InputDecoration(
                            labelText: _tr('مكان التركيب', 'Montage', 'Mounted on'),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          items: GlassMountTarget.values
                              .map((t) => DropdownMenuItem(value: t, child: Text(_mountLabel(t))))
                              .toList(),
                          onChanged: (v) => setDlg(() => mountTarget = v ?? GlassMountTarget.all),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<double>(
                          value: const [0.0, 6.0, 8.0, 10.0, 12.0].contains(glassThickness) ? glassThickness : 0.0,
                          decoration: InputDecoration(
                            labelText: _tr('سمك الزجاج', 'Épaisseur du verre', 'Glass thickness'),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          items: const [0.0, 6.0, 8.0, 10.0, 12.0]
                              .map((t) => DropdownMenuItem(
                                    value: t,
                                    child: Text(t == 0 ? _tr('كل السماكات', 'Toutes', 'Any') : '${t.toStringAsFixed(0)} mm'),
                                  ))
                              .toList(),
                          onChanged: (v) => setDlg(() => glassThickness = v ?? 0.0),
                        ),
                      ),
                      if (category == 'joint') ...[
                        const SizedBox(width: 8),
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            value: jointType,
                            decoration: InputDecoration(
                              labelText: _tr('نوع الجوان', 'Type de joint', 'Gasket type'),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            items: ['', ...GlassGasketType.values]
                                .map((t) => DropdownMenuItem(value: t, child: Text(_gasketLabel(t))))
                                .toList(),
                            onChanged: (v) => setDlg(() {
                              jointType = v ?? '';
                              // The gasket between a profile and the glass is
                              // sold by the metre, every other one by the piece.
                              if (jointType.isNotEmpty) {
                                unit = GlassGasketType.soldByMetre(jointType) ? 'meter' : 'piece';
                              }
                            }),
                          ),
                        ),
                      ],
                      if (category == 'profile') ...[
                        const SizedBox(width: 8),
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            value: profileRole,
                            decoration: InputDecoration(
                              labelText: _tr('دور البروفيل', 'Rôle du profilé', 'Profile role'),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            items: ['', ...GlassProfileRole.values]
                                .map((t) => DropdownMenuItem(value: t, child: Text(_profileRoleLabel(t))))
                                .toList(),
                            onChanged: (v) => setDlg(() {
                              profileRole = v ?? '';
                              if (profileRole.isNotEmpty) unit = 'meter';
                            }),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Price of the accessory in each of its colours; without a
                  // colour price the selling price above applies.
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(
                      _tr('الأسعار حسب اللون', 'Prix par couleur', 'Price by colour'),
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                  ),
                  const SizedBox(height: 6),
                  for (var i = 0; i < colorPrices.length; i++)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.palette_outlined, size: 18),
                      title: Text(colorPrices[i].color),
                      subtitle: Text('${colorPrices[i].price.toStringAsFixed(0)} DZD'),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline, color: Colors.red, size: 18),
                        onPressed: () => setDlg(() => colorPrices.removeAt(i)),
                      ),
                    ),
                  Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: TextField(
                          controller: newColorCtrl,
                          decoration: InputDecoration(
                            labelText: _tr('اللون', 'Couleur', 'Colour'),
                            hintText: _tr('أسود مطفي، ذهبي، كروم…', 'Noir mat, doré, chromé…', 'Matt black, gold, chrome…'),
                            isDense: true,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 2,
                        child: TextField(
                          controller: newColorPriceCtrl,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: InputDecoration(
                            labelText: _tr('السعر (د.ج)', 'Prix (DZD)', 'Price (DZD)'),
                            isDense: true,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: _tr('إضافة اللون', 'Ajouter la couleur', 'Add colour'),
                        icon: const Icon(Icons.add_circle, color: Colors.teal),
                        onPressed: () {
                          final color = newColorCtrl.text.trim();
                          final price = double.tryParse(newColorPriceCtrl.text.trim().replaceAll(',', '.'));
                          if (color.isEmpty || price == null || price < 0) return;
                          setDlg(() {
                            colorPrices.removeWhere((c) => c.color.toLowerCase() == color.toLowerCase());
                            colorPrices.add(GlassItemColorPrice(color: color, price: price));
                            newColorCtrl.clear();
                            newColorPriceCtrl.clear();
                          });
                        },
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
        'image_path': imagePath,
        'handle_design_code': handleDesignCode,
        'hole_diameters': parseMillimetreList(holeDiametersCtrl.text).map(_mm).join(', '),
        'hole_spacings': parseMillimetreList(holeSpacingsCtrl.text).map(_mm).join(', '),
        'hole_layout': verticalHoles ? 'vertical' : 'horizontal',
        'mount_target': mountTarget,
        'glass_thickness_mm': glassThickness,
        'joint_type': category == 'joint' ? jointType : '',
        'profile_role': category == 'profile' ? profileRole : '',
        'color_prices': encodeColorPrices(colorPrices),
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
                      'faconnage',
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
                          final imagePath = item['image_path']?.toString() ?? '';

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
                                  cat == 'poignee'
                                      ? GlassHandleThumbnailView(
                                          imagePath: imagePath,
                                          designCode: item['handle_design_code']?.toString(),
                                          size: 54,
                                        )
                                      : Container(
                                          width: 52,
                                          height: 52,
                                          decoration: BoxDecoration(
                                            color: Colors.white,
                                            borderRadius: BorderRadius.circular(10),
                                            border: Border.all(color: Colors.teal.shade100),
                                          ),
                                          child: ClipRRect(
                                            borderRadius: BorderRadius.circular(9),
                                            child: imagePath.isNotEmpty
                                                ? (imagePath.startsWith('assets/')
                                                    ? Image.asset(
                                                        imagePath,
                                                        fit: BoxFit.contain,
                                                        errorBuilder: (_, __, ___) => Icon(_categoryIcon(cat), color: Colors.teal.shade800, size: 26),
                                                      )
                                                    : Image.file(
                                                        File(imagePath),
                                                        fit: BoxFit.contain,
                                                        errorBuilder: (_, __, ___) => Icon(_categoryIcon(cat), color: Colors.teal.shade800, size: 26),
                                                      ))
                                                : Icon(_categoryIcon(cat), color: Colors.teal.shade800, size: 26),
                                          ),
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
                                        unit == 'meter'
                                            ? _tr('للمتر', '/m', '/m')
                                            : unit == 'sqm'
                                                ? _tr('للمتر المربع', '/m²', '/m²')
                                                : _tr('للقطعة', '/pièce', '/pc'),
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
