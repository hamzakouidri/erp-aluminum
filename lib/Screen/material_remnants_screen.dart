import 'package:database_data/widgets/app_material.dart';
import 'package:provider/provider.dart';

import '../settings/app_settings.dart';
import '../settings/localization.dart';
import '../sql_database.dart';
import '../widgets/section_image.dart';

class MaterialRemnantsScreen extends StatefulWidget {
  const MaterialRemnantsScreen({super.key});

  @override
  State<MaterialRemnantsScreen> createState() => _MaterialRemnantsScreenState();
}

class _MaterialRemnantsScreenState extends State<MaterialRemnantsScreen> {
  final SqlDatabase _db = SqlDatabase();
  bool _loading = true;
  List<Map<String, dynamic>> _remnants = [];
  String _selectedFilter = 'all';

  // تصنيفات الفلترة العلوية
  static const List<Map<String, String>> _filterButtons = [
    {'key': 'all', 'label_ar': 'الكل', 'label_fr': 'Tous'},
    {
      'key': 'panneau_sandwich',
      'label_ar': 'بانو ساندويتش',
      'label_fr': 'Panneau Sandwich',
    },
    {'key': 'resine', 'label_ar': 'ريزين', 'label_fr': 'Résine / HPL'},
    {'key': 'alucobond', 'label_ar': 'أليكوبوند', 'label_fr': 'Alucobond'},
    {'key': 'plexyglass', 'label_ar': 'بيكسي جلاس', 'label_fr': 'Plexiglas'},
    {'key': 'glass', 'label_ar': 'زجاج', 'label_fr': 'Verre'},
    {'key': 'profile', 'label_ar': 'مقاطع ألمنيوم', 'label_fr': 'Profilés'},
  ];

  @override
  void initState() {
    super.initState();
    _loadRemnants();
  }

  Future<void> _loadRemnants() async {
    setState(() => _loading = true);
    final all = await _db.readAllAvailableMaterialRemnants();
    if (mounted) {
      setState(() {
        _remnants = all;
        _loading = false;
      });
    }
  }

  List<Map<String, dynamic>> get _filteredRemnants {
    if (_selectedFilter == 'all') return _remnants;
    if (_selectedFilter == 'profile') {
      return _remnants.where((r) {
        final width = (r['width_mm'] as num?)?.toDouble() ?? 0.0;
        final type = r['material_type']?.toString().toLowerCase() ?? '';
        return width <= 0 &&
            (type.isEmpty || type == 'profile' || r['item_type'] == 'Section');
      }).toList();
    }
    return _remnants.where((r) {
      final type = r['material_type']?.toString().toLowerCase() ?? '';
      final itemType = r['item_type']?.toString().toLowerCase() ?? '';
      return type == _selectedFilter.toLowerCase() ||
          itemType == _selectedFilter.toLowerCase();
    }).toList();
  }

  Future<void> _showAddManualRemnantDialog() async {
    final lang = Provider.of<AppSettingsProvider>(
      context,
      listen: false,
    ).language;
    final isArabic = lang == AppLanguage.arabic;

    String materialType =
        _selectedFilter == 'all' || _selectedFilter == 'profile'
        ? 'resine'
        : _selectedFilter;
    final lengthCtrl = TextEditingController(text: '1200');
    final widthCtrl = TextEditingController(text: '800');
    final colorCtrl = TextEditingController();
    final noteCtrl = TextEditingController();
    final rackCtrl = TextEditingController();
    bool allowRotation = true;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDlgState) {
          final isProfile = materialType == 'profile';

          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: Row(
              children: [
                const Icon(Icons.add_box_outlined, color: Colors.teal),
                const SizedBox(width: 8),
                Text(
                  isArabic
                      ? 'إدخال فضلة جديدة للمخزون'
                      : 'Ajouter une chute au stock',
                  style: TextStyle(
                    fontFamily: isArabic ? 'Cairo' : null,
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: SizedBox(
                width: 460,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<String>(
                      value: materialType,
                      decoration: InputDecoration(
                        labelText: isArabic ? 'نوع المادة' : 'Type de matériau',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      items: _filterButtons
                          .where((b) => b['key'] != 'all')
                          .map(
                            (b) => DropdownMenuItem(
                              value: b['key'],
                              child: Text(
                                isArabic ? b['label_ar']! : b['label_fr']!,
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (val) {
                        if (val != null) setDlgState(() => materialType = val);
                      },
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: lengthCtrl,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: isArabic
                                  ? 'الطول (مم)'
                                  : 'Longueur (mm)',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              suffixText: 'mm',
                            ),
                          ),
                        ),
                        if (!isProfile) ...[
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextField(
                              controller: widthCtrl,
                              keyboardType: TextInputType.number,
                              decoration: InputDecoration(
                                labelText: isArabic
                                    ? 'العرض (مم)'
                                    : 'Largeur (mm)',
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                suffixText: 'mm',
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: colorCtrl,
                            decoration: InputDecoration(
                              labelText: isArabic ? 'اللون' : 'Couleur',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            controller: rackCtrl,
                            decoration: InputDecoration(
                              labelText: isArabic
                                  ? 'مكان التخزين / الحامل'
                                  : 'Râtelier / Emplacement',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (!isProfile) ...[
                      const SizedBox(height: 12),
                      SwitchListTile(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(color: Colors.grey.shade300),
                        ),
                        title: Text(
                          isArabic
                              ? 'السماح بالتدوير 90°'
                              : 'Autoriser la rotation 90°',
                          style: TextStyle(
                            fontFamily: isArabic ? 'Cairo' : null,
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        value: allowRotation,
                        onChanged: (val) =>
                            setDlgState(() => allowRotation = val),
                      ),
                    ],
                    const SizedBox(height: 12),
                    TextField(
                      controller: noteCtrl,
                      decoration: InputDecoration(
                        labelText: isArabic ? 'ملاحظة' : 'Note',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(isArabic ? 'إلغاء' : 'Annuler'),
              ),
              FilledButton.icon(
                icon: const Icon(Icons.check),
                label: Text(isArabic ? 'إضافة للمخزون' : 'Ajouter'),
                onPressed: () async {
                  final length = double.tryParse(lengthCtrl.text) ?? 0.0;
                  final width = isProfile
                      ? 0.0
                      : (double.tryParse(widthCtrl.text) ?? 0.0);
                  if (length <= 0) return;

                  final dbInstance = await _db.db;
                  if (dbInstance == null) return;

                  final now = DateTime.now().toIso8601String();
                  final ticket =
                      'RM-${DateTime.now().millisecondsSinceEpoch % 100000}';

                  await dbInstance.insert('MaterialRemnants', {
                    'ticket_code': ticket,
                    'item_id': 0,
                    'item_type': isProfile ? 'Section' : materialType,
                    'material_type': materialType,
                    'length_mm': length,
                    'width_mm': width,
                    'allow_rotation': allowRotation ? 1 : 0,
                    'location_id': 1,
                    'rack_code': rackCtrl.text.trim(),
                    'status': 'available',
                    'note': noteCtrl.text.trim(),
                    'created_at': now,
                    'updated_at': now,
                  });

                  if (mounted) {
                    Navigator.pop(ctx);
                    _loadRemnants();
                  }
                },
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _scrapRemnant(Map<String, dynamic> rem) async {
    final lang = Provider.of<AppSettingsProvider>(
      context,
      listen: false,
    ).language;
    final isArabic = lang == AppLanguage.arabic;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isArabic ? 'تسجيل هدر الفضلة' : 'Déclarer comme déchet'),
        content: Text(
          isArabic
              ? 'هل تريد نقل الفضلة (${rem['ticket_code']}) إلى سجل الهدر؟'
              : 'Voulez-vous transférer la chute (${rem['ticket_code']}) au rebut ?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(isArabic ? 'إلغاء' : 'Annuler'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(isArabic ? 'تأكيد' : 'Confirmer'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _db.markMaterialRemnantAsScrap(remnantId: rem['id'] as int);
      _loadRemnants();
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<AppSettingsProvider>(context);
    final lang = settings.language;
    final isArabic = lang == AppLanguage.arabic;
    final list = _filteredRemnants;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          isArabic
              ? 'إدارة فضلات الألواح والمقاطع'
              : 'Gestion des chutes (Panneaux & Profilés)',
          style: TextStyle(
            fontFamily: isArabic ? 'Cairo' : null,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: Text(
          isArabic ? 'إدخال فضلة يدوية' : 'Nouvelle chute',
          style: TextStyle(fontFamily: isArabic ? 'Cairo' : null),
        ),
        onPressed: _showAddManualRemnantDialog,
      ),
      body: Column(
        children: [
          // أزرار الفلترة العلوية
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              border: Border(
                bottom: BorderSide(color: Theme.of(context).dividerColor),
              ),
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: _filterButtons.map((btn) {
                  final selected = _selectedFilter == btn['key'];
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(
                        isArabic ? btn['label_ar']! : btn['label_fr']!,
                        style: TextStyle(
                          fontFamily: isArabic ? 'Cairo' : null,
                          fontWeight: selected
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),
                      ),
                      selected: selected,
                      onSelected: (_) {
                        setState(() => _selectedFilter = btn['key']!);
                      },
                    ),
                  );
                }).toList(),
              ),
            ),
          ),

          // قائمة الفضلات
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : list.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.recycling_outlined,
                          size: 64,
                          color: Colors.grey.shade400,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          isArabic
                              ? 'لا توجد فضلات متاحة في هذا التصنيف.\nالفضلات الصالحة للاستعمال ستظهر هنا تلقائياً بعد عمليات التقطيع.'
                              : 'Aucune chute disponible dans cette catégorie.\nLes chutes réutilisables apparaîtront ici après le débit.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontFamily: isArabic ? 'Cairo' : null,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: list.length,
                    itemBuilder: (context, index) {
                      final rem = list[index];
                      final length =
                          (rem['length_mm'] as num?)?.toDouble() ?? 0.0;
                      final width =
                          (rem['width_mm'] as num?)?.toDouble() ?? 0.0;
                      final isSheet = width > 0;
                      final areaSqm = isSheet
                          ? (length * width) / 1000000.0
                          : 0.0;
                      final ticket = rem['ticket_code']?.toString() ?? '';
                      final color = rem['color_name']?.toString() ?? '';
                      final rack = rem['rack_code']?.toString() ?? '';
                      final itemCode = rem['item_code']?.toString() ?? '';
                      final itemName = rem['item_name']?.toString() ?? '';
                      final itemImagePath =
                          rem['item_image_path']?.toString() ?? '';
                      final canRotate =
                          ((rem['allow_rotation'] as num?)?.toInt() ?? 1) == 1;

                      final seriesName = rem['series_name']?.toString() ?? '';
                      final shelf = rem['shelf_code']?.toString() ?? '';
                      final bin = rem['bin_code']?.toString() ?? '';

                      return Card(
                        elevation: 1.5,
                        margin: const EdgeInsets.symmetric(vertical: 6),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Row(
                            children: [
                              // بطاقة المقاس
                              Container(
                                width: 72,
                                height: 72,
                                decoration: BoxDecoration(
                                  color: isSheet
                                      ? Colors.teal.withValues(alpha: 0.08)
                                      : Colors.indigo.withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: isSheet
                                        ? Colors.teal.withValues(alpha: 0.3)
                                        : Colors.indigo.withValues(alpha: 0.3),
                                  ),
                                ),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    if (isSheet)
                                      const Icon(
                                        Icons.crop_landscape,
                                        color: Colors.teal,
                                        size: 24,
                                      )
                                    else
                                      Expanded(
                                        child: Padding(
                                          padding: const EdgeInsets.fromLTRB(
                                            5,
                                            5,
                                            5,
                                            1,
                                          ),
                                          child: SectionImageWidget(
                                            code: itemCode,
                                            name: itemName,
                                            imagePath: itemImagePath,
                                            size: 48,
                                            fallbackIcon:
                                                Icons.view_in_ar_outlined,
                                          ),
                                        ),
                                      ),
                                    if (isSheet) const SizedBox(height: 4),
                                    Text(
                                      isSheet
                                          ? '${areaSqm.toStringAsFixed(2)} m²'
                                          : '${length.round()} mm',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: isSheet
                                            ? Colors.teal
                                            : Colors.indigo,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 14),

                              // تفاصيل الفضلة
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 6,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.blueGrey.shade50,
                                            borderRadius: BorderRadius.circular(
                                              6,
                                            ),
                                          ),
                                          child: Text(
                                            ticket,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 11,
                                              color: Colors.blueGrey,
                                            ),
                                          ),
                                        ),
                                        if (itemCode.isNotEmpty) ...[
                                          const SizedBox(width: 6),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 6,
                                              vertical: 2,
                                            ),
                                            decoration: BoxDecoration(
                                              color: Colors.indigo.shade50,
                                              borderRadius: BorderRadius.circular(
                                                6,
                                              ),
                                              border: Border.all(
                                                color: Colors.indigo.shade200,
                                              ),
                                            ),
                                            child: Text(
                                              itemCode,
                                              style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 11,
                                                color: Colors.indigo.shade800,
                                              ),
                                            ),
                                          ),
                                        ],
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            rem['item_name']?.toString() ??
                                                (isSheet ? 'لوح' : 'مقطع'),
                                            style: TextStyle(
                                              fontFamily: isArabic
                                                  ? 'Cairo'
                                                  : null,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 14,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        Text(
                                          isSheet
                                              ? '${isArabic ? 'المقاس:' : 'Dimensions:'} ${length.round()} × ${width.round()} مم'
                                              : '${isArabic ? 'الطول:' : 'Longueur:'} ${length.round()} مم',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w700,
                                            color: Colors.teal,
                                            fontSize: 13,
                                          ),
                                        ),
                                        if (seriesName.isNotEmpty) ...[
                                          const SizedBox(width: 8),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 6,
                                              vertical: 1.5,
                                            ),
                                            decoration: BoxDecoration(
                                              color: Colors.amber.shade50,
                                              borderRadius: BorderRadius.circular(4),
                                              border: Border.all(
                                                color: Colors.amber.shade400,
                                              ),
                                            ),
                                            child: Text(
                                              seriesName,
                                              style: TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w600,
                                                color: Colors.amber.shade900,
                                                fontFamily: isArabic ? 'Cairo' : null,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      [
                                        if (color.isNotEmpty)
                                          '${isArabic ? 'اللون:' : 'Couleur:'} ${Localization.colorName(color, lang)}',
                                        if (rack.isNotEmpty)
                                          '${isArabic ? 'الحامل:' : 'Râtelier:'} $rack',
                                        if (shelf.isNotEmpty)
                                          '${isArabic ? 'الرف:' : 'Étagère:'} $shelf',
                                        if (bin.isNotEmpty)
                                          '${isArabic ? 'الخانة:' : 'Casier:'} $bin',
                                        if (isSheet)
                                          (canRotate ? '🔄 90°' : '🔒 Fixe'),
                                      ].join(' · '),
                                      style: TextStyle(
                                        fontFamily: isArabic ? 'Cairo' : null,
                                        fontSize: 11.5,
                                        color: Colors.grey.shade700,
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              // زر تسجيل هدر
                              IconButton(
                                icon: const Icon(
                                  Icons.delete_outline,
                                  color: Colors.redAccent,
                                ),
                                tooltip: isArabic ? 'تسجيل كهدر' : 'Rebut',
                                onPressed: () => _scrapRemnant(rem),
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
