import 'package:flutter/material.dart';
import '../sql_database.dart';
import 'package:database_data/settings/localization.dart';
import 'package:database_data/settings/app_settings.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';

class GlassScreen extends StatefulWidget {
  final SqlDatabase db;

  const GlassScreen({super.key, required this.db});

  @override
  State<GlassScreen> createState() => _GlassScreenState();
}

class _GlassScreenState extends State<GlassScreen> {
  List<Map<String, dynamic>> _items = [];
  List<String> _glassColors = ['بدون لون'];
  List<String> _allColors = []; // جميع الألوان (للـ Panneau)
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _loadItems();
  }

  Future<void> _loadItems() async {
    final items = await widget.db.readGlass();

    final dbInstance = await widget.db.db;
    List<String> loadedGlassColors = ['بدون لون'];
    List<String> loadedAllColors = [];
    if (dbInstance != null) {
      // ألوان الزجاج (للأنواع الأخرى)
      final glassColorRows = await dbInstance.query(
        'Colors',
        where: 'is_glass_color = 1',
      );
      for (var row in glassColorRows) {
        loadedGlassColors.add(row['name'].toString());
      }
      // جميع الألوان (للـ Panneau)
      final allColorRows = await dbInstance.query('Colors');
      for (var row in allColorRows) {
        loadedAllColors.add(row['name'].toString());
      }
    }

    setState(() {
      _items = items;
      _glassColors = loadedGlassColors;
      _allColors = loadedAllColors;
    });
  }

  final List<String> _glassTypes = ['Glass', 'Intercall', 'Gas', 'Panneau', 'Baguette', 'Rosette'];
  final List<String> _panneauSubtypes = ['plexiglass', 'bardage', 'panneau sandwitch', 'panneau décor', 'aluco', 'résine'];

  void _showAddDialog() {
    final nameCtrl = TextEditingController();
    final thicknessCtrl = TextEditingController();
    final priceCtrl = TextEditingController();
    final heightCtrl = TextEditingController();
    final visibleWidthCtrl = TextEditingController();

    String selectedType = 'Glass';
    String selectedColor = 'بدون لون';
    Set<String> selectedPanneauColors = {}; // ألوان Panneau (متعددة)
    String selectedSubtype = 'plexiglass';
    String? imagePath;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) {
          final isPanneau = selectedType == 'Panneau';
          final hasMultipleColors = selectedType == 'Panneau' || selectedType == 'Baguette' || selectedType == 'Rosette';
          return AlertDialog(
            title: Text(
              Localization.translate(
                'إضافة زجاج جديد',
                Provider.of<AppSettingsProvider>(context).language,
              ),
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  GestureDetector(
                    onTap: () async {
                      final XFile? image = await _picker.pickImage(
                        source: ImageSource.gallery,
                      );
                      if (image != null) {
                        setStateDialog(() {
                          imagePath = image.path;
                        });
                      }
                    },
                    child: CircleAvatar(
                      radius: 40,
                      backgroundColor: Colors.grey.shade200,
                      backgroundImage: imagePath != null
                          ? FileImage(File(imagePath!))
                          : null,
                      child: imagePath == null
                          ? Icon(
                              Icons.add_a_photo,
                              size: 30,
                              color: Colors.grey,
                            )
                          : null,
                    ),
                  ),
                  const SizedBox(height: 15),
                  TextField(
                    controller: nameCtrl,
                    decoration: InputDecoration(
                      labelText: Localization.translate(
                        'اسم الزجاج',
                        Provider.of<AppSettingsProvider>(context).language,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    value: selectedType,
                    decoration: InputDecoration(
                      labelText: Localization.translate(
                        'النوع',
                        Provider.of<AppSettingsProvider>(context).language,
                      ),
                    ),
                    items: _glassTypes.map((type) {
                      final Map<String, String> typeLabelsDropdown = {
                        'Glass': 'زجاج (Glass)',
                        'Intercall': 'إنتركال (Intercall)',
                        'Gas': 'غاز (Gas)',
                        'Panneau': 'مغلق (Panneau)',
                        'Baguette': 'باجيت ديكور (Baguette)',
                        'Rosette': 'وردة ديكور (Rosette)',
                        'Moussa': 'موسى (Moussa)',
                        'Harari': 'حراري (Harari)',
                        'Vitrage armé': 'زجاج مسلح (Vitrage armé)',
                      };
                      final label = typeLabelsDropdown[type] ?? type;
                      return DropdownMenuItem(value: type, child: Text(label));
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) setStateDialog(() => selectedType = val);
                    },
                  ),
                  if (isPanneau) ...[
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      value: selectedSubtype,
                      decoration: InputDecoration(
                        labelText: Localization.translate(
                          'الخاصية',
                          Provider.of<AppSettingsProvider>(context).language,
                        ),
                      ),
                      items: _panneauSubtypes.map((subtype) {
                        return DropdownMenuItem(value: subtype, child: Text(subtype));
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) setStateDialog(() => selectedSubtype = val);
                      },
                    ),
                  ],
                  if (hasMultipleColors) ...[
                    const SizedBox(height: 10),
                    // ── اختيار الألوان (متعددة) للـ Panneau/Baguette/Rosette ─────────────────
                    Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        selectedType == 'Panneau'
                            ? 'الألوان المتاحة لهذا الـ Panneau:'
                            : selectedType == 'Baguette'
                                ? 'الألوان المتاحة للباجيت:'
                                : 'الألوان المتاحة للوردة:',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      constraints: BoxConstraints(maxHeight: 200),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: SingleChildScrollView(
                        child: Column(
                          children: _allColors.map((color) {
                            return CheckboxListTile(
                              dense: true,
                              title: Text(color, style: TextStyle(fontSize: 13)),
                              value: selectedPanneauColors.contains(color),
                              onChanged: (checked) {
                                setStateDialog(() {
                                  if (checked == true) {
                                    selectedPanneauColors.add(color);
                                  } else {
                                    selectedPanneauColors.remove(color);
                                  }
                                });
                              },
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                  ] else ...[
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      value: selectedColor,
                      decoration: InputDecoration(
                        labelText: Localization.translate(
                          'اللون',
                          Provider.of<AppSettingsProvider>(context).language,
                        ),
                      ),
                      items: _glassColors.map((color) {
                        return DropdownMenuItem(value: color, child: Text(color));
                      }).toList(),
                      onChanged: (val) {
                        if (val != null)
                          setStateDialog(() => selectedColor = val);
                      },
                    ),
                  ],
                  const SizedBox(height: 10),
                  TextField(
                    controller: thicknessCtrl,
                    decoration: InputDecoration(
                      labelText: Localization.translate(
                        selectedType == 'Rosette' ? 'العرض' : 'السماكة',
                        Provider.of<AppSettingsProvider>(context).language,
                      ),
                    ),
                    keyboardType: TextInputType.number,
                  ),
                  if (selectedType == 'Panneau' && selectedSubtype == 'bardage') ...[
                    const SizedBox(height: 10),
                    TextField(
                      controller: visibleWidthCtrl,
                      decoration: InputDecoration(
                        labelText: Localization.translate(
                          'العرض الظاهر (Visible Width)',
                          Provider.of<AppSettingsProvider>(context).language,
                        ),
                      ),
                      keyboardType: TextInputType.number,
                    ),
                  ],
                  if (selectedType == 'Rosette') ...[
                    const SizedBox(height: 10),
                    TextField(
                      controller: heightCtrl,
                      decoration: InputDecoration(
                        labelText: Localization.translate(
                          'الطول',
                          Provider.of<AppSettingsProvider>(context).language,
                        ),
                      ),
                      keyboardType: TextInputType.number,
                    ),
                  ],
                  // سعر المتر المربع — يُخفى للـ Panneau (يُدار من صفحة الأسعار)
                  if (!isPanneau) ...[
                    const SizedBox(height: 10),
                    TextField(
                      controller: priceCtrl,
                      decoration: InputDecoration(
                        labelText: Localization.translate(
                          'سعر المتر المربع',
                          Provider.of<AppSettingsProvider>(context).language,
                        ),
                      ),
                      keyboardType: TextInputType.number,
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(
                  Localization.translate(
                    'إلغاء',
                    Provider.of<AppSettingsProvider>(context).language,
                  ),
                  style: TextStyle(color: Colors.grey),
                ),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
                onPressed: () async {
                  if (nameCtrl.text.isNotEmpty) {
                    // تجميع اللون/الألوان بحسب النوع
                    final String colorValue = hasMultipleColors
                        ? selectedPanneauColors.join(',')
                        : (selectedColor == 'بدون لون' ? '' : selectedColor);
                    await widget.db.insertGlass(
                      nameCtrl.text,
                      selectedType,
                      double.tryParse(thicknessCtrl.text) ?? 0.0,
                      isPanneau ? 0.0 : (double.tryParse(priceCtrl.text) ?? 0.0),
                      color: colorValue,
                      imagePath: imagePath ?? '',
                      subtype: isPanneau ? selectedSubtype : '',
                      height: selectedType == 'Rosette' ? (double.tryParse(heightCtrl.text) ?? 0.0) : 0.0,
                      visibleWidth: (isPanneau && selectedSubtype == 'bardage') ? (double.tryParse(visibleWidthCtrl.text) ?? 0.0) : null,
                    );
                    _loadItems();
                    if (context.mounted) Navigator.pop(context);
                  }
                },
                child: Text(
                  Localization.translate(
                    'حفظ',
                    Provider.of<AppSettingsProvider>(context).language,
                  ),
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showEditDialog(Map<String, dynamic> item, bool isUserAdmin) {
    final nameCtrl = TextEditingController(text: item['name'].toString());
    final thicknessCtrl = TextEditingController(
      text: item['thickness'].toString(),
    );
    final priceCtrl = TextEditingController(
      text: item['price_per_sqm'].toString(),
    );
    final heightCtrl = TextEditingController(
      text: (item['height'] ?? 0.0).toString(),
    );
    final visibleWidthCtrl = TextEditingController(
      text: (item['visible_width'] ?? '').toString(),
    );

    String selectedType = _glassTypes.contains(item['type'])
        ? item['type']
        : 'Glass';
    String c = item['color']?.toString() ?? '';
    // للـ Panneau: parse CSV → Set؛ لغيره: اللون الأحادي
    Set<String> selectedPanneauColors = (selectedType == 'Panneau' || selectedType == 'Baguette' || selectedType == 'Rosette')
        ? (c.isEmpty ? {} : c.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toSet())
        : {};
    String selectedColor = (selectedType != 'Panneau' && selectedType != 'Baguette' && selectedType != 'Rosette')
        ? (c.isEmpty ? 'بدون لون' : (_glassColors.contains(c) ? c : 'بدون لون'))
        : 'بدون لون';
    String selectedSubtype = item['subtype']?.toString() ?? 'plexiglass';
    if (selectedSubtype.isEmpty) selectedSubtype = 'plexiglass';
    String? imagePath = item['image_path']?.toString();
    if (imagePath != null && imagePath.isEmpty) imagePath = null;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) {
          final isPanneau = selectedType == 'Panneau';
          final hasMultipleColors = selectedType == 'Panneau' || selectedType == 'Baguette' || selectedType == 'Rosette';
          return AlertDialog(
            title: Text(
              Localization.translate(
                'تعديل',
                Provider.of<AppSettingsProvider>(context).language,
              ),
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  GestureDetector(
                    onTap: !isUserAdmin
                        ? null
                        : () async {
                            final XFile? image = await _picker.pickImage(
                              source: ImageSource.gallery,
                            );
                            if (image != null) {
                              setStateDialog(() {
                                imagePath = image.path;
                              });
                            }
                          },
                    child: CircleAvatar(
                      radius: 40,
                      backgroundColor: Colors.grey.shade200,
                      backgroundImage: imagePath != null
                          ? FileImage(File(imagePath!))
                          : null,
                      child: imagePath == null
                          ? Icon(
                              Icons.add_a_photo,
                              size: 30,
                              color: Colors.grey,
                            )
                          : null,
                    ),
                  ),
                  const SizedBox(height: 15),
                  TextField(
                    controller: nameCtrl,
                    enabled: isUserAdmin,
                    decoration: InputDecoration(
                      labelText: Localization.translate(
                        'اسم الزجاج',
                        Provider.of<AppSettingsProvider>(context).language,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    value: selectedType,
                    decoration: InputDecoration(
                      labelText: Localization.translate(
                        'النوع',
                        Provider.of<AppSettingsProvider>(context).language,
                      ),
                    ),
                    items: _glassTypes.map((type) {
                      final Map<String, String> typeLabelsDropdown = {
                        'Glass': 'زجاج (Glass)',
                        'Intercall': 'إنتركال (Intercall)',
                        'Gas': 'غاز (Gas)',
                        'Panneau': 'مغلق (Panneau)',
                        'Baguette': 'باجيت ديكور (Baguette)',
                        'Rosette': 'وردة ديكور (Rosette)',
                        'Moussa': 'موسى (Moussa)',
                        'Harari': 'حراري (Harari)',
                        'Vitrage armé': 'زجاج مسلح (Vitrage armé)',
                      };
                      final label = typeLabelsDropdown[type] ?? type;
                      return DropdownMenuItem(value: type, child: Text(label));
                    }).toList(),
                    onChanged: !isUserAdmin
                        ? null
                        : (val) {
                            if (val != null)
                              setStateDialog(() => selectedType = val);
                          },
                  ),
                  if (isPanneau) ...[
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      value: selectedSubtype,
                      decoration: InputDecoration(
                        labelText: Localization.translate(
                          'الخاصية',
                          Provider.of<AppSettingsProvider>(context).language,
                        ),
                      ),
                      items: _panneauSubtypes.map((subtype) {
                        return DropdownMenuItem(value: subtype, child: Text(subtype));
                      }).toList(),
                      onChanged: !isUserAdmin
                          ? null
                          : (val) {
                              if (val != null)
                                setStateDialog(() => selectedSubtype = val);
                            },
                    ),
                  ],
                  if (hasMultipleColors) ...[
                    const SizedBox(height: 10),
                    // ── اختيار الألوان (متعددة) للـ Panneau/Baguette/Rosette ─────────────────
                    Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        selectedType == 'Panneau'
                            ? 'الألوان المتاحة لهذا الـ Panneau:'
                            : selectedType == 'Baguette'
                                ? 'الألوان المتاحة للباجيت:'
                                : 'الألوان المتاحة للوردة:',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      constraints: BoxConstraints(maxHeight: 200),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: SingleChildScrollView(
                        child: Column(
                          children: _allColors.map((color) {
                            return CheckboxListTile(
                              dense: true,
                              title: Text(color, style: TextStyle(fontSize: 13)),
                              value: selectedPanneauColors.contains(color),
                              onChanged: !isUserAdmin
                                  ? null
                                  : (checked) {
                                      setStateDialog(() {
                                        if (checked == true) {
                                          selectedPanneauColors.add(color);
                                        } else {
                                          selectedPanneauColors.remove(color);
                                        }
                                      });
                                    },
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                  ] else ...[
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      value: selectedColor,
                      decoration: InputDecoration(
                        labelText: Localization.translate(
                          'اللون',
                          Provider.of<AppSettingsProvider>(context).language,
                        ),
                      ),
                      items: _glassColors.map((color) {
                        return DropdownMenuItem(value: color, child: Text(color));
                      }).toList(),
                      onChanged: !isUserAdmin
                          ? null
                          : (val) {
                              if (val != null)
                                setStateDialog(() => selectedColor = val);
                            },
                    ),
                  ],
                  const SizedBox(height: 10),
                  TextField(
                    controller: thicknessCtrl,
                    enabled: isUserAdmin,
                    decoration: InputDecoration(
                      labelText: Localization.translate(
                        selectedType == 'Rosette' ? 'العرض' : 'السماكة',
                        Provider.of<AppSettingsProvider>(context).language,
                      ),
                    ),
                    keyboardType: TextInputType.number,
                  ),
                  if (selectedType == 'Panneau' && selectedSubtype == 'bardage') ...[
                    const SizedBox(height: 10),
                    TextField(
                      controller: visibleWidthCtrl,
                      enabled: isUserAdmin,
                      decoration: InputDecoration(
                        labelText: Localization.translate(
                          'العرض الظاهر (Visible Width)',
                          Provider.of<AppSettingsProvider>(context).language,
                        ),
                      ),
                      keyboardType: TextInputType.number,
                    ),
                  ],
                  if (selectedType == 'Rosette') ...[
                    const SizedBox(height: 10),
                    TextField(
                      controller: heightCtrl,
                      enabled: isUserAdmin,
                      decoration: InputDecoration(
                        labelText: Localization.translate(
                          'الطول',
                          Provider.of<AppSettingsProvider>(context).language,
                        ),
                      ),
                      keyboardType: TextInputType.number,
                    ),
                  ],
                  // سعر المتر المربع — يُخفى للـ Panneau (يُدار من صفحة الأسعار)
                  if (!isPanneau) ...[
                    const SizedBox(height: 10),
                    TextField(
                      controller: priceCtrl,
                      decoration: InputDecoration(
                        labelText: Localization.translate(
                          'سعر المتر المربع',
                          Provider.of<AppSettingsProvider>(context).language,
                        ),
                      ),
                      keyboardType: TextInputType.number,
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(
                  Localization.translate(
                    'إلغاء',
                    Provider.of<AppSettingsProvider>(context).language,
                  ),
                  style: TextStyle(color: Colors.grey),
                ),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
                onPressed: () async {
                  if (nameCtrl.text.isNotEmpty) {
                    final String colorValue = hasMultipleColors
                        ? selectedPanneauColors.join(',')
                        : (selectedColor == 'بدون لون' ? '' : selectedColor);
                    await widget.db.updateGlass(
                      item['id'],
                      nameCtrl.text,
                      selectedType,
                      double.tryParse(thicknessCtrl.text) ?? 0.0,
                      isPanneau ? 0.0 : (double.tryParse(priceCtrl.text) ?? 0.0),
                      color: colorValue,
                      imagePath: imagePath ?? '',
                      subtype: isPanneau ? selectedSubtype : '',
                      height: selectedType == 'Rosette' ? (double.tryParse(heightCtrl.text) ?? 0.0) : 0.0,
                      visibleWidth: (isPanneau && selectedSubtype == 'bardage') ? (double.tryParse(visibleWidthCtrl.text) ?? 0.0) : null,
                    );
                    _loadItems();
                    if (context.mounted) Navigator.pop(context);
                  }
                },
                child: Text(
                  Localization.translate(
                    'حفظ تعديل',
                    Provider.of<AppSettingsProvider>(context).language,
                  ),
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showDeleteDialog(Map<String, dynamic> item) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          'تأكيد الحذف',
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.red,
          ),
        ),
        content: Text(
          'سيتم أرشفة هذا العنصر (إخفاؤه) ولن يتم حذفه نهائياً حفاظاً على سلامة بيانات المخزون والفواتير السابقة المرتبطة به.',
          style: const TextStyle(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              await widget.db.deleteGlass(item['id']);
              _loadItems();
              if (context.mounted) Navigator.pop(dialogContext);
            },
            child: const Text(
              'موافق، قم بالأرشفة',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isUserAdmin = isAdmin;
    final lang = Provider.of<AppSettingsProvider>(context).language;

    // Group items by type
    final Map<String, List<Map<String, dynamic>>> grouped = {};
    for (var type in _glassTypes) {
      grouped[type] = _items.where((i) => i['type'] == type).toList();
    }

    // Build sections
    List<Widget> sections = [];
    final typeLabels = {
      'Glass': Localization.translate('الزجاج (Glass)', lang),
      'Intercall': Localization.translate('الإنتركال (Intercall)', lang),
      'Gas': Localization.translate('الغاز (Gas)', lang),
      'Panneau': Localization.translate('مغلق (Panneau)', lang),
      'Baguette': Localization.translate('باجيت ديكور (Baguette)', lang),
      'Rosette': Localization.translate('وردة ديكور (Rosette)', lang),
    };
    final typeIcons = {
      'Glass': Icons.layers,
      'Intercall': Icons.space_bar,
      'Gas': Icons.opacity,
      'Panneau': Icons.view_quilt,
      'Baguette': Icons.border_vertical_rounded,
      'Rosette': Icons.api_rounded,
    };
    final typeColors = {
      'Glass': Colors.cyan.shade800,
      'Intercall': Colors.teal.shade800,
      'Gas': Colors.amber.shade900,
      'Panneau': Colors.purple.shade800,
      'Baguette': Colors.orange.shade800,
      'Rosette': Colors.pink.shade800,
    };

    for (var type in _glassTypes) {
      final items = grouped[type] ?? [];
      if (items.isEmpty) continue;

      final sectionColor = typeColors[type] ?? Colors.blue;

      sections.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
          child: Row(
            children: [
              Icon(typeIcons[type], color: sectionColor, size: 22),
              const SizedBox(width: 8),
              Text(
                typeLabels[type] ?? type,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: sectionColor,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Divider(color: sectionColor.withValues(alpha: 0.4), thickness: 1.5),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: sectionColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${items.length}',
                  style: TextStyle(
                    color: sectionColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
        ),
      );

      for (var item in items) {
        String colorText = item['color']?.toString() ?? '';
        double thickness = (item['thickness'] ?? 0.0) is num
            ? (item['thickness'] as num).toDouble()
            : double.tryParse(item['thickness'].toString()) ?? 0.0;
        double price = (item['price_per_sqm'] ?? 0.0) is num
            ? (item['price_per_sqm'] as num).toDouble()
            : double.tryParse(item['price_per_sqm'].toString()) ?? 0.0;

        sections.add(
          Card(
            margin: EdgeInsets.all(8),
            child: ListTile(
              title: Text(
                Localization.translate(item['name'].toString(), lang),
                style: TextStyle(fontWeight: FontWeight.bold, color: sectionColor),
              ),
              subtitle: Text(() {
                double rosetteHeight = (item['height'] ?? 0.0) is num
                    ? (item['height'] as num).toDouble()
                    : double.tryParse(item['height'].toString()) ?? 0.0;
                final typeLabel = type == 'Glass'
                    ? Localization.translate('زجاج', lang)
                    : type == 'Intercall'
                        ? Localization.translate('إنتركال', lang)
                        : type == 'Gas'
                            ? Localization.translate('غاز', lang)
                            : type == 'Panneau'
                                ? Localization.translate('مغلق', lang)
                                : type == 'Baguette'
                                    ? Localization.translate('باجيت ديكور', lang)
                                    : Localization.translate('وردة ديكور', lang);
                String dimText = '';
                if (type == 'Rosette') {
                  dimText = ' - ${Localization.translate('الأبعاد', lang)}: ${thickness.toStringAsFixed(0)} × ${rosetteHeight.toStringAsFixed(0)} ${Localization.translate('مم', lang)}';
                } else if (type == 'Baguette') {
                  dimText = ' - ${Localization.translate('العرض', lang)}: ${thickness.toStringAsFixed(0)} ${Localization.translate('مم', lang)}';
                } else {
                  dimText = ' - ${Localization.translate('السماكة', lang)}: ${thickness.toStringAsFixed(thickness.truncateToDouble() == thickness ? 0 : 1)} ${Localization.translate('مم', lang)}';
                  if (type == 'Panneau' && (item['subtype']?.toString() ?? '') == 'bardage' && item['visible_width'] != null) {
                    double vw = (item['visible_width'] is num) ? (item['visible_width'] as num).toDouble() : double.tryParse(item['visible_width'].toString()) ?? 0.0;
                    if (vw > 0) dimText += ' - ${Localization.translate('العرض الظاهر', lang)}: ${vw.toStringAsFixed(0)} ${Localization.translate('مم', lang)}';
                  }
                }
                final colorPart = (type == 'Glass' || type == 'Panneau' || type == 'Baguette' || type == 'Rosette') && colorText.isNotEmpty
                    ? ' - ${Localization.translate('اللون', lang)}: ${Localization.translate(colorText, lang)}'
                    : '';
                final subtypePart = type == 'Panneau' && (item['subtype']?.toString() ?? '').isNotEmpty
                    ? ' - ${Localization.translate('الخاصية', lang)}: ${item['subtype']}'
                    : '';
                final priceUnit = type == 'Rosette'
                    ? Localization.translate('دج/قطعة', lang)
                    : type == 'Baguette'
                        ? Localization.translate('دج/متر', lang)
                        : Localization.translate('دج/م²', lang);
                final pricePart = ' - ${Localization.translate('السعر', lang)}: ${price.toStringAsFixed(price.truncateToDouble() == price ? 0 : 2)} $priceUnit';
                return '${Localization.translate('النوع', lang)}: $typeLabel$dimText$colorPart$subtypePart$pricePart';
              }()),
              trailing: isUserAdmin
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: Icon(Icons.edit, color: Colors.blue),
                          onPressed: () => _showEditDialog(item, isUserAdmin),
                        ),
                        IconButton(
                          icon: Icon(Icons.delete, color: Colors.red),
                          onPressed: () => _showDeleteDialog(item),
                        ),
                      ],
                    )
                  : null,
            ),
          ),
        );
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          Localization.translate(
            'إدارة الزجاج',
            Provider.of<AppSettingsProvider>(context).language,
          ),
        ),
      ),
      body: _items.isEmpty
          ? Center(
              child: Text(
                Localization.translate(
                  'لا توجد بيانات',
                  Provider.of<AppSettingsProvider>(context).language,
                ),
              ),
            )
          : ListView(children: sections),
      floatingActionButton: !isUserAdmin
          ? null
          : FloatingActionButton(
              onPressed: _showAddDialog,
              child: const Icon(Icons.add),
            ),
    );
  }
}
