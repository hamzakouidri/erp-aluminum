import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../settings/app_settings.dart';
import '../sql_database.dart';

class StandardSheetsScreen extends StatefulWidget {
  const StandardSheetsScreen({super.key});

  @override
  State<StandardSheetsScreen> createState() => _StandardSheetsScreenState();
}

class _StandardSheetsScreenState extends State<StandardSheetsScreen> {
  final SqlDatabase _db = SqlDatabase();
  bool _loading = true;
  List<Map<String, dynamic>> _sheets = [];
  String _selectedFilter = 'all';

  // أنواع المواد المتاحة
  static const List<Map<String, String>> _materialTypes = [
    {'key': 'resine', 'label_ar': 'ريزين (Résine / HPL)', 'label_fr': 'Résine / HPL'},
    {'key': 'alucobond', 'label_ar': 'أليكوبوند (Alucobond)', 'label_fr': 'Alucobond'},
    {'key': 'panneau_sandwich', 'label_ar': 'بانو ساندويتش (Panneau Sandwich)', 'label_fr': 'Panneau Sandwich'},
    {'key': 'plexyglass', 'label_ar': 'بيكسي جلاس (Plexiglas)', 'label_fr': 'Plexiglas'},
    {'key': 'glass', 'label_ar': 'زجاج (Verre)', 'label_fr': 'Verre (Vitrage)'},
  ];

  @override
  void initState() {
    super.initState();
    _loadSheets();
  }

  Future<void> _loadSheets() async {
    setState(() => _loading = true);
    final data = await _db.readStandardSheets(
      materialType: _selectedFilter == 'all' ? null : _selectedFilter,
    );
    if (mounted) {
      setState(() {
        _sheets = data;
        _loading = false;
      });
    }
  }

  String _getMaterialLabel(String key, AppLanguage lang) {
    final found = _materialTypes.firstWhere(
      (m) => m['key'] == key.toLowerCase(),
      orElse: () => {'key': key, 'label_ar': key, 'label_fr': key},
    );
    return lang == AppLanguage.arabic ? found['label_ar']! : found['label_fr']!;
  }

  Future<void> _showAddEditDialog([Map<String, dynamic>? existing]) async {
    final lang = Provider.of<AppSettingsProvider>(context, listen: false).language;
    final isArabic = lang == AppLanguage.arabic;
    final isEditing = existing != null;

    String materialType = existing?['material_type']?.toString() ??
        (_selectedFilter == 'all' ? 'resine' : _selectedFilter);
    final nameCtrl = TextEditingController(
      text: existing?['name']?.toString() ?? '',
    );
    final lengthCtrl = TextEditingController(
      text: existing != null ? (existing['length_mm'] as num).toStringAsFixed(0) : '2800',
    );
    final widthCtrl = TextEditingController(
      text: existing != null ? (existing['width_mm'] as num).toStringAsFixed(0) : '1300',
    );
    final thicknessCtrl = TextEditingController(
      text: existing != null && (existing['thickness_mm'] as num?) != null
          ? (existing['thickness_mm'] as num).toStringAsFixed(1)
          : '',
    );
    final priceSheetCtrl = TextEditingController(
      text: existing != null && (existing['price_per_sheet'] as num?) != null
          ? (existing['price_per_sheet'] as num).toStringAsFixed(2)
          : '0.00',
    );
    final priceSqmCtrl = TextEditingController(
      text: existing != null && (existing['price_per_sqm'] as num?) != null
          ? (existing['price_per_sqm'] as num).toStringAsFixed(2)
          : '0.00',
    );
    final colorCtrl = TextEditingController(
      text: existing?['color']?.toString() ?? '',
    );
    bool allowRotation = existing != null
        ? ((existing['allow_rotation'] as num?)?.toInt() ?? 1) == 1
        : true;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDlgState) {
          final isGlass = materialType == 'glass';

          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Row(
              children: [
                Icon(
                  isEditing ? Icons.edit_note : Icons.add_photo_alternate_outlined,
                  color: Colors.blueAccent,
                ),
                const SizedBox(width: 8),
                Text(
                  isEditing
                      ? (isArabic ? 'تعديل مقاس اللوح' : 'Modifier le format de feuille')
                      : (isArabic ? 'إضافة مقاس لوح جديد' : 'Nouveau format de feuille'),
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
                width: 480,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // اختيار نوع المادة
                    DropdownButtonFormField<String>(
                      value: materialType,
                      decoration: InputDecoration(
                        labelText: isArabic ? 'نوع المادة' : 'Type de matériau',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        prefixIcon: const Icon(Icons.layers_outlined),
                      ),
                      items: _materialTypes.map((m) {
                        return DropdownMenuItem<String>(
                          value: m['key'],
                          child: Text(
                            isArabic ? m['label_ar']! : m['label_fr']!,
                            style: TextStyle(fontFamily: isArabic ? 'Cairo' : null),
                          ),
                        );
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setDlgState(() {
                            materialType = val;
                            if (nameCtrl.text.isEmpty || nameCtrl.text.startsWith('لوح')) {
                              if (val == 'resine') {
                                lengthCtrl.text = '2800';
                                widthCtrl.text = '1300';
                              } else if (val == 'alucobond' || val == 'plexyglass') {
                                lengthCtrl.text = '2440';
                                widthCtrl.text = '1220';
                              } else if (val == 'panneau_sandwich') {
                                lengthCtrl.text = '3000';
                                widthCtrl.text = '1200';
                              } else if (val == 'glass') {
                                lengthCtrl.text = '3210';
                                widthCtrl.text = '2250';
                              }
                            }
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 14),

                    // اسم المقاس / التسمية
                    TextField(
                      controller: nameCtrl,
                      decoration: InputDecoration(
                        labelText: isArabic ? 'اسم أو وصف اللوح (اختياري)' : 'Désignation de la feuille',
                        hintText: isArabic ? 'مثلاً: لوح قياسي 130×280' : 'Ex: Feuille standard 130x280',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        prefixIcon: const Icon(Icons.label_outline),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // الأبعاد: الطول والعرض
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: lengthCtrl,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: isArabic ? 'الطول (مم)' : 'Longueur (mm)',
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                              suffixText: 'mm',
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: widthCtrl,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: isArabic ? 'العرض (مم)' : 'Largeur (mm)',
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                              suffixText: 'mm',
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),

                    // السماكة واللون
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: thicknessCtrl,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: isArabic ? 'السماكة (مم)' : 'Épaisseur (mm)',
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                              suffixText: 'mm',
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: colorCtrl,
                            decoration: InputDecoration(
                              labelText: isArabic ? 'اللون (اختياري)' : 'Couleur (optionnelle)',
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                              prefixIcon: const Icon(Icons.color_lens_outlined),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),

                    // السعر: باللوح لباقي المواد، وبالمتر المربع للزجاج
                    if (isGlass)
                      TextField(
                        controller: priceSqmCtrl,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: isArabic ? 'السعر بالمتر المربع (DA / m²)' : 'Prix par m² (DA / m²)',
                          helperText: isArabic
                              ? 'الزجاج يُحتسب ويباع دائماً بالمتر المربع'
                              : 'Le vitrage est toujours tarifé au m²',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          prefixIcon: const Icon(Icons.attach_money),
                        ),
                      )
                    else
                      TextField(
                        controller: priceSheetCtrl,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: isArabic ? 'سعر اللوح الكامل (DA / Feuille)' : 'Prix par feuille complète (DA)',
                          helperText: isArabic
                              ? 'سعر الفاية الكاملة لاحتساب تكلفة الطلبية بعدد الألواح'
                              : 'Prix de la plaque entière pour le calcul au panneau',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          prefixIcon: const Icon(Icons.payments_outlined),
                        ),
                      ),
                    const SizedBox(height: 14),

                    // السماح بالتدوير 90 درجة
                    SwitchListTile(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: Colors.grey.shade300),
                      ),
                      title: Text(
                        isArabic ? 'السماح بالتدوير 90° (Rotation)' : 'Autoriser la rotation 90°',
                        style: TextStyle(
                          fontFamily: isArabic ? 'Cairo' : null,
                          fontWeight: FontWeight.bold,
                          fontSize: 13.5,
                        ),
                      ),
                      subtitle: Text(
                        isArabic
                            ? 'عطّل هذا الخيار إذا كان للوح خطوط أو عروق خشبية طولية متناسقة'
                            : 'Désactiver si le panneau a un sens de fil/veinage obligatoire',
                        style: TextStyle(
                          fontFamily: isArabic ? 'Cairo' : null,
                          fontSize: 11.5,
                        ),
                      ),
                      value: allowRotation,
                      onChanged: (val) => setDlgState(() => allowRotation = val),
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
                icon: const Icon(Icons.save),
                label: Text(isArabic ? 'حفظ' : 'Enregistrer'),
                onPressed: () async {
                  final length = double.tryParse(lengthCtrl.text) ?? 0.0;
                  final width = double.tryParse(widthCtrl.text) ?? 0.0;
                  if (length <= 0 || width <= 0) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          isArabic ? 'يرجى إدخال طول وعرض صحيحين' : 'Dimensions invalides',
                        ),
                        backgroundColor: Colors.redAccent,
                      ),
                    );
                    return;
                  }

                  final name = nameCtrl.text.trim().isNotEmpty
                      ? nameCtrl.text.trim()
                      : '${_getMaterialLabel(materialType, lang)} (${length.round()} × ${width.round()} مم)';

                  final row = {
                    'material_type': materialType,
                    'name': name,
                    'length_mm': length,
                    'width_mm': width,
                    'thickness_mm': double.tryParse(thicknessCtrl.text) ?? 0.0,
                    'price_per_sheet': double.tryParse(priceSheetCtrl.text) ?? 0.0,
                    'price_per_sqm': double.tryParse(priceSqmCtrl.text) ?? 0.0,
                    'color': colorCtrl.text.trim(),
                    'allow_rotation': allowRotation ? 1 : 0,
                  };

                  if (isEditing) {
                    await _db.updateStandardSheet(existing['id'] as int, row);
                  } else {
                    await _db.insertStandardSheet(row);
                  }

                  if (mounted) {
                    Navigator.pop(ctx);
                    _loadSheets();
                  }
                },
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _deleteSheet(Map<String, dynamic> sheet) async {
    final lang = Provider.of<AppSettingsProvider>(context, listen: false).language;
    final isArabic = lang == AppLanguage.arabic;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isArabic ? 'تأكيد الحذف' : 'Confirmer la suppression'),
        content: Text(
          isArabic
              ? 'هل أنت متأكد من حذف مقاس اللوح "${sheet['name']}"؟'
              : 'Voulez-vous vraiment supprimer "${sheet['name']}" ?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(isArabic ? 'إلغاء' : 'Annuler'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(isArabic ? 'حذف' : 'Supprimer'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _db.deleteStandardSheet(sheet['id'] as int);
      _loadSheets();
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<AppSettingsProvider>(context);
    final lang = settings.language;
    final isArabic = lang == AppLanguage.arabic;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          isArabic ? 'أبعاد وأسعار الألواح والصفائح' : 'Formats et prix des feuilles & panneaux',
          style: TextStyle(
            fontFamily: isArabic ? 'Cairo' : null,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: Text(
          isArabic ? 'إضافة مقاس لوح جديد' : 'Nouveau format',
          style: TextStyle(fontFamily: isArabic ? 'Cairo' : null),
        ),
        onPressed: () => _showAddEditDialog(),
      ),
      body: Column(
        children: [
          // شريط أزرار الفلترة العلوية
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              border: Border(bottom: BorderSide(color: Theme.of(context).dividerColor)),
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  ChoiceChip(
                    label: Text(isArabic ? 'الكل' : 'Tous'),
                    selected: _selectedFilter == 'all',
                    onSelected: (_) {
                      setState(() => _selectedFilter = 'all');
                      _loadSheets();
                    },
                  ),
                  const SizedBox(width: 8),
                  ..._materialTypes.map((m) {
                    final selected = _selectedFilter == m['key'];
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(isArabic ? m['label_ar']! : m['label_fr']!),
                        selected: selected,
                        onSelected: (_) {
                          setState(() => _selectedFilter = m['key']!);
                          _loadSheets();
                        },
                      ),
                    );
                  }),
                ],
              ),
            ),
          ),

          // قائمة الألواح المسجلة
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _sheets.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.layers_clear_outlined, size: 64, color: Colors.grey.shade400),
                            const SizedBox(height: 12),
                            Text(
                              isArabic
                                  ? 'لا توجد مقاسات مسجلة لهذا النوع.\nاضغط على الزر أدناه لإدخال أبعاد اللوح.'
                                  : 'Aucun format enregistré.\nAppuyez sur le bouton ci-dessous pour en ajouter.',
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
                        itemCount: _sheets.length,
                        itemBuilder: (context, index) {
                          final item = _sheets[index];
                          final length = (item['length_mm'] as num).toDouble();
                          final width = (item['width_mm'] as num).toDouble();
                          final areaSqm = (length * width) / 1000000.0;
                          final matKey = item['material_type']?.toString() ?? '';
                          final isGlass = matKey == 'glass';
                          final priceSheet = (item['price_per_sheet'] as num?)?.toDouble() ?? 0.0;
                          final priceSqm = (item['price_per_sqm'] as num?)?.toDouble() ?? 0.0;
                          final canRotate = ((item['allow_rotation'] as num?)?.toInt() ?? 1) == 1;

                          return Card(
                            elevation: 1.5,
                            margin: const EdgeInsets.symmetric(vertical: 6),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            child: Padding(
                              padding: const EdgeInsets.all(14),
                              child: Row(
                                children: [
                                  // أيقونة وبطاقة الأبعاد
                                  Container(
                                    width: 72,
                                    height: 72,
                                    decoration: BoxDecoration(
                                      color: Colors.blue.withValues(alpha: 0.08),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: Colors.blue.withValues(alpha: 0.25)),
                                    ),
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        const Icon(Icons.aspect_ratio, color: Colors.blueAccent, size: 24),
                                        const SizedBox(height: 4),
                                        Text(
                                          '${areaSqm.toStringAsFixed(2)} m²',
                                          style: const TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.blueAccent,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 14),

                                  // تفاصيل المقاس
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                item['name']?.toString() ?? '',
                                                style: TextStyle(
                                                  fontFamily: isArabic ? 'Cairo' : null,
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 15,
                                                ),
                                              ),
                                            ),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: canRotate ? Colors.green.shade50 : Colors.amber.shade50,
                                                borderRadius: BorderRadius.circular(8),
                                                border: Border.all(
                                                  color: canRotate ? Colors.green.shade300 : Colors.amber.shade300,
                                                ),
                                              ),
                                              child: Text(
                                                canRotate
                                                    ? (isArabic ? '🔄 تدوير 90° متاح' : '🔄 Rotation 90°')
                                                    : (isArabic ? '🔒 اتجاه ثابت' : '🔒 Direction fixe'),
                                                style: TextStyle(
                                                  fontSize: 10.5,
                                                  fontWeight: FontWeight.bold,
                                                  color: canRotate ? Colors.green.shade800 : Colors.amber.shade900,
                                                  fontFamily: isArabic ? 'Cairo' : null,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          '${isArabic ? 'المادة:' : 'Matériau:'} ${_getMaterialLabel(matKey, lang)} · ${length.round()} × ${width.round()} مم',
                                          style: TextStyle(
                                            fontFamily: isArabic ? 'Cairo' : null,
                                            fontSize: 12.5,
                                            color: Colors.grey.shade700,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          isGlass
                                              ? '${isArabic ? 'السعر:' : 'Prix:'} ${priceSqm.toStringAsFixed(2)} DA / m²'
                                              : '${isArabic ? 'سعر اللوح الكامل:' : 'Prix par feuille:'} ${priceSheet.toStringAsFixed(2)} DA',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            color: Colors.teal,
                                            fontSize: 13,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),

                                  // أزرار التحكم
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        icon: const Icon(Icons.edit_outlined, color: Colors.blueGrey),
                                        tooltip: isArabic ? 'تعديل' : 'Modifier',
                                        onPressed: () => _showAddEditDialog(item),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                                        tooltip: isArabic ? 'حذف' : 'Supprimer',
                                        onPressed: () => _deleteSheet(item),
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
