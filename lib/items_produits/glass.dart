import 'package:flutter/material.dart';
import '../sql_database.dart';
import 'package:database_data/settings/localization.dart';
import 'package:database_data/settings/app_settings.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import '../Commande/decor_panel_designs.dart';

class GlassScreen extends StatefulWidget {
  final SqlDatabase db;

  const GlassScreen({super.key, required this.db});

  @override
  State<GlassScreen> createState() => _GlassScreenState();
}

class _GlassScreenState extends State<GlassScreen> {
  List<Map<String, dynamic>> _items = [];
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  List<String> _glassColors = ['بدون لون'];
  List<String> _allColors = []; // جميع الألوان (للـ Panneau)
  final ImagePicker _picker = ImagePicker();

  bool _isDecorSubtype(String? subtype) {
    final value = (subtype ?? '').toLowerCase();
    return value.contains('decor') ||
        value.contains('décor') ||
        value.contains('ديكور');
  }

  @override
  void initState() {
    super.initState();
    _loadItems();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
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

  final List<String> _glassTypes = [
    'Glass',
    'Intercall',
    'Gas',
    'Tempering',
    'Panneau',
    'Baguette',
    'Rosette',
  ];
  final List<String> _panneauSubtypes = [
    'plexiglass',
    'bardage',
    'panneau sandwitch',
    'panneau décor',
    'aluco',
    'résine',
  ];

  Widget _buildDecorDesignSelector({
    required String selectedCode,
    required ValueChanged<String> onChanged,
    bool enabled = true,
  }) {
    final lang = Provider.of<AppSettingsProvider>(context).language;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: Text(
            Localization.translate('الرسم المرتبط بهذا البانو:', lang),
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          ),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          initialValue: DecorPanelDesignCatalog.isSupported(selectedCode)
              ? selectedCode
              : '',
          isExpanded: true,
          decoration: InputDecoration(
            labelText: Localization.translate('تصميم البانو ديكور', lang),
            helperText: Localization.translate(
              'الرسم مرتبط بسجل المنتج، وليس باسم المنتج.',
              lang,
            ),
            border: const OutlineInputBorder(),
          ),
          items: [
            DropdownMenuItem<String>(
              value: '',
              child: Text(Localization.translate('بدون رسم مرتبط', lang)),
            ),
            ...DecorPanelDesignCatalog.designs.map(
              (design) => DropdownMenuItem<String>(
                value: design.code,
                child: Row(
                  children: [
                    DecorPanelDesignPreview(
                      designCode: design.code,
                      width: 28,
                      height: 44,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        Localization.translate(design.label, lang),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          onChanged: enabled ? (value) => onChanged(value ?? '') : null,
        ),
        if (DecorPanelDesignCatalog.isSupported(selectedCode)) ...[
          const SizedBox(height: 10),
          Center(
            child: DecorPanelDesignPreview(
              designCode: selectedCode,
              width: 90,
              height: 150,
            ),
          ),
        ],
      ],
    );
  }

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
    String selectedDecorDesignCode = '';
    String? imagePath;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) {
          final isPanneau = selectedType == 'Panneau';
          final isTempering = selectedType == 'Tempering';
          final hasMultipleColors =
              selectedType == 'Panneau' ||
              selectedType == 'Baguette' ||
              selectedType == 'Rosette';
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
                  if (!isTempering) ...[
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
                  ],
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
                        'Tempering': 'تقسية (Trempé)',
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
                        return DropdownMenuItem(
                          value: subtype,
                          child: Text(subtype),
                        );
                      }).toList(),
                      onChanged: (val) {
                        if (val != null)
                          setStateDialog(() => selectedSubtype = val);
                      },
                    ),
                  ],
                  if (isPanneau && _isDecorSubtype(selectedSubtype)) ...[
                    const SizedBox(height: 12),
                    _buildDecorDesignSelector(
                      selectedCode: selectedDecorDesignCode,
                      onChanged: (value) =>
                          setStateDialog(() => selectedDecorDesignCode = value),
                    ),
                  ],
                  if (hasMultipleColors) ...[
                    const SizedBox(height: 10),
                    // ── اختيار الألوان (متعددة) للـ Panneau/Baguette/Rosette ─────────────────
                    Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        Localization.translate(
                          selectedType == 'Panneau'
                            ? 'الألوان المتاحة لهذا الـ Panneau:'
                            : selectedType == 'Baguette'
                            ? 'الألوان المتاحة للباجيت:'
                            : 'الألوان المتاحة للوردة:',
                          Provider.of<AppSettingsProvider>(context).language,
                        ),
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
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
                              title: Text(
                                color,
                                style: TextStyle(fontSize: 13),
                              ),
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
                  ] else if (!isTempering) ...[
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
                        return DropdownMenuItem(
                          value: color,
                          child: Text(color),
                        );
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
                  if (selectedType == 'Panneau' &&
                      (selectedSubtype == 'bardage' ||
                          _isDecorSubtype(selectedSubtype))) ...[
                    const SizedBox(height: 10),
                    TextField(
                      controller: visibleWidthCtrl,
                      decoration: InputDecoration(
                        labelText: Localization.translate(
                          _isDecorSubtype(selectedSubtype)
                              ? 'عرض الديكور'
                              : 'العرض الظاهر (Visible Width)',
                          Provider.of<AppSettingsProvider>(context).language,
                        ),
                      ),
                      keyboardType: TextInputType.number,
                    ),
                  ],
                  if (selectedType == 'Rosette' ||
                      (selectedType == 'Panneau' &&
                          _isDecorSubtype(selectedSubtype))) ...[
                    const SizedBox(height: 10),
                    TextField(
                      controller: heightCtrl,
                      decoration: InputDecoration(
                        labelText: Localization.translate(
                          _isDecorSubtype(selectedSubtype)
                              ? 'طول الديكور'
                              : 'الطول',
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
                          isTempering
                              ? 'سعر التقسية للمتر المربع'
                              : 'سعر المتر المربع',
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
                  final thickness = double.tryParse(thicknessCtrl.text) ?? 0.0;
                  final decorWidth =
                      double.tryParse(visibleWidthCtrl.text) ?? 0.0;
                  final decorHeight = double.tryParse(heightCtrl.text) ?? 0.0;
                  final isDecorPanneau =
                      selectedType == 'Panneau' &&
                      _isDecorSubtype(selectedSubtype);
                  final itemName = isTempering
                      ? 'Trempé ${thickness.toStringAsFixed(thickness == thickness.roundToDouble() ? 0 : 1)} mm'
                      : nameCtrl.text.trim();
                  if (isDecorPanneau && (decorWidth <= 0 || decorHeight <= 0)) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          Localization.translate(
                            'يجب إدخال عرض الديكور وطوله.',
                            Provider.of<AppSettingsProvider>(context, listen: false).language,
                          ),
                        ),
                        backgroundColor: Colors.red,
                      ),
                    );
                    return;
                  }
                  if (itemName.isNotEmpty && thickness > 0) {
                    // تجميع اللون/الألوان بحسب النوع
                    final String colorValue = hasMultipleColors
                        ? selectedPanneauColors.join(',')
                        : (selectedColor == 'بدون لون' ? '' : selectedColor);
                    await widget.db.insertGlass(
                      itemName,
                      selectedType,
                      thickness,
                      isPanneau
                          ? 0.0
                          : (double.tryParse(priceCtrl.text) ?? 0.0),
                      color: colorValue,
                      imagePath: imagePath ?? '',
                      subtype: isPanneau ? selectedSubtype : '',
                      height: selectedType == 'Rosette' || isDecorPanneau
                          ? decorHeight
                          : 0.0,
                      visibleWidth:
                          (isPanneau && selectedSubtype == 'bardage') ||
                              isDecorPanneau
                          ? decorWidth
                          : null,
                      decorDesignCode: isDecorPanneau
                          ? selectedDecorDesignCode
                          : '',
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
    Set<String> selectedPanneauColors =
        (selectedType == 'Panneau' ||
            selectedType == 'Baguette' ||
            selectedType == 'Rosette')
        ? (c.isEmpty
              ? {}
              : c
                    .split(',')
                    .map((s) => s.trim())
                    .where((s) => s.isNotEmpty)
                    .toSet())
        : {};
    String selectedColor =
        (selectedType != 'Panneau' &&
            selectedType != 'Baguette' &&
            selectedType != 'Rosette')
        ? (c.isEmpty ? 'بدون لون' : (_glassColors.contains(c) ? c : 'بدون لون'))
        : 'بدون لون';
    String selectedSubtype = item['subtype']?.toString() ?? 'plexiglass';
    if (selectedSubtype.isEmpty) selectedSubtype = 'plexiglass';
    String selectedDecorDesignCode =
        item['decor_design_code']?.toString() ?? '';
    String? imagePath = item['image_path']?.toString();
    if (imagePath != null && imagePath.isEmpty) imagePath = null;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) {
          final isPanneau = selectedType == 'Panneau';
          final isTempering = selectedType == 'Tempering';
          final hasMultipleColors =
              selectedType == 'Panneau' ||
              selectedType == 'Baguette' ||
              selectedType == 'Rosette';
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
                  if (!isTempering) ...[
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
                  ],
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
                        'Tempering': 'تقسية (Trempé)',
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
                        return DropdownMenuItem(
                          value: subtype,
                          child: Text(subtype),
                        );
                      }).toList(),
                      onChanged: !isUserAdmin
                          ? null
                          : (val) {
                              if (val != null)
                                setStateDialog(() => selectedSubtype = val);
                            },
                    ),
                  ],
                  if (isPanneau && _isDecorSubtype(selectedSubtype)) ...[
                    const SizedBox(height: 12),
                    _buildDecorDesignSelector(
                      selectedCode: selectedDecorDesignCode,
                      enabled: isUserAdmin,
                      onChanged: (value) =>
                          setStateDialog(() => selectedDecorDesignCode = value),
                    ),
                  ],
                  if (hasMultipleColors) ...[
                    const SizedBox(height: 10),
                    // ── اختيار الألوان (متعددة) للـ Panneau/Baguette/Rosette ─────────────────
                    Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        Localization.translate(
                          selectedType == 'Panneau'
                            ? 'الألوان المتاحة لهذا الـ Panneau:'
                            : selectedType == 'Baguette'
                            ? 'الألوان المتاحة للباجيت:'
                            : 'الألوان المتاحة للوردة:',
                          Provider.of<AppSettingsProvider>(context).language,
                        ),
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
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
                              title: Text(
                                color,
                                style: TextStyle(fontSize: 13),
                              ),
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
                  ] else if (!isTempering) ...[
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
                        return DropdownMenuItem(
                          value: color,
                          child: Text(color),
                        );
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
                  if (selectedType == 'Panneau' &&
                      (selectedSubtype == 'bardage' ||
                          _isDecorSubtype(selectedSubtype))) ...[
                    const SizedBox(height: 10),
                    TextField(
                      controller: visibleWidthCtrl,
                      enabled: isUserAdmin,
                      decoration: InputDecoration(
                        labelText: Localization.translate(
                          _isDecorSubtype(selectedSubtype)
                              ? 'عرض الديكور'
                              : 'العرض الظاهر (Visible Width)',
                          Provider.of<AppSettingsProvider>(context).language,
                        ),
                      ),
                      keyboardType: TextInputType.number,
                    ),
                  ],
                  if (selectedType == 'Rosette' ||
                      (selectedType == 'Panneau' &&
                          _isDecorSubtype(selectedSubtype))) ...[
                    const SizedBox(height: 10),
                    TextField(
                      controller: heightCtrl,
                      enabled: isUserAdmin,
                      decoration: InputDecoration(
                        labelText: Localization.translate(
                          _isDecorSubtype(selectedSubtype)
                              ? 'طول الديكور'
                              : 'الطول',
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
                          isTempering
                              ? 'سعر التقسية للمتر المربع'
                              : 'سعر المتر المربع',
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
                  final thickness = double.tryParse(thicknessCtrl.text) ?? 0.0;
                  final decorWidth =
                      double.tryParse(visibleWidthCtrl.text) ?? 0.0;
                  final decorHeight = double.tryParse(heightCtrl.text) ?? 0.0;
                  final isDecorPanneau =
                      selectedType == 'Panneau' &&
                      _isDecorSubtype(selectedSubtype);
                  final itemName = isTempering
                      ? 'Trempé ${thickness.toStringAsFixed(thickness == thickness.roundToDouble() ? 0 : 1)} mm'
                      : nameCtrl.text.trim();
                  if (isDecorPanneau && (decorWidth <= 0 || decorHeight <= 0)) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          Localization.translate(
                            'يجب إدخال عرض الديكور وطوله.',
                            Provider.of<AppSettingsProvider>(context, listen: false).language,
                          ),
                        ),
                        backgroundColor: Colors.red,
                      ),
                    );
                    return;
                  }
                  if (itemName.isNotEmpty && thickness > 0) {
                    final String colorValue = hasMultipleColors
                        ? selectedPanneauColors.join(',')
                        : (selectedColor == 'بدون لون' ? '' : selectedColor);
                    await widget.db.updateGlass(
                      item['id'],
                      itemName,
                      selectedType,
                      thickness,
                      isPanneau
                          ? 0.0
                          : (double.tryParse(priceCtrl.text) ?? 0.0),
                      color: colorValue,
                      imagePath: imagePath ?? '',
                      subtype: isPanneau ? selectedSubtype : '',
                      height: selectedType == 'Rosette' || isDecorPanneau
                          ? decorHeight
                          : 0.0,
                      visibleWidth:
                          (isPanneau && selectedSubtype == 'bardage') ||
                              isDecorPanneau
                          ? decorWidth
                          : null,
                      decorDesignCode: isDecorPanneau
                          ? selectedDecorDesignCode
                          : '',
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
    final lang = Provider.of<AppSettingsProvider>(context, listen: false).language;
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          Localization.translate('تأكيد الحذف', lang),
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.red,
          ),
        ),
        content: Text(
          Localization.translate(
            'سيتم أرشفة هذا العنصر (إخفاؤه) ولن يتم حذفه نهائياً حفاظاً على سلامة بيانات المخزون والفواتير السابقة المرتبطة به.',
            lang,
          ),
          style: const TextStyle(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(Localization.translate('إلغاء', lang)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              await widget.db.deleteGlass(item['id']);
              _loadItems();
              if (context.mounted) Navigator.pop(dialogContext);
            },
            child: Text(
              Localization.translate('موافق، قم بالأرشفة', lang),
              style: const TextStyle(color: Colors.white),
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
    final searchQuery = _searchQuery.trim().toLowerCase();
    const typeAliases = <String, String>{
      'Glass': 'glass verre زجاج',
      'Intercall': 'intercall intercalaire intercalair انتراكال فاصل',
      'Gas': 'gas gaz غاز',
      'Tempering': 'tempering trempe trempé تقسية ترومبي',
      'Panneau': 'panneau panel مغلق لوحة',
      'Baguette': 'baguette ديكور',
      'Rosette': 'rosette وردة ديكور',
    };
    final filteredItems = searchQuery.isEmpty
        ? _items
        : _items.where((item) {
            final name = (item['name'] ?? '').toString().toLowerCase();
            final type = (item['type'] ?? '').toString().toLowerCase();
            final subtype = (item['subtype'] ?? '').toString().toLowerCase();
            return name.contains(searchQuery) ||
                type.contains(searchQuery) ||
                (typeAliases[item['type']] ?? '').contains(searchQuery) ||
                subtype.contains(searchQuery);
          }).toList();

    // Group items by type
    final Map<String, List<Map<String, dynamic>>> grouped = {};
    for (var type in _glassTypes) {
      grouped[type] = filteredItems.where((i) => i['type'] == type).toList();
    }

    // Build sections
    List<Widget> sections = [];
    final typeLabels = {
      'Glass': Localization.translate('الزجاج (Glass)', lang),
      'Intercall': Localization.translate('الإنتركال (Intercall)', lang),
      'Gas': Localization.translate('الغاز (Gas)', lang),
      'Tempering': Localization.translate('التقسية (Trempé)', lang),
      'Panneau': Localization.translate('مغلق (Panneau)', lang),
      'Baguette': Localization.translate('باجيت ديكور (Baguette)', lang),
      'Rosette': Localization.translate('وردة ديكور (Rosette)', lang),
    };
    final typeIcons = {
      'Glass': Icons.layers,
      'Intercall': Icons.space_bar,
      'Gas': Icons.opacity,
      'Tempering': Icons.local_fire_department_outlined,
      'Panneau': Icons.view_quilt,
      'Baguette': Icons.border_vertical_rounded,
      'Rosette': Icons.api_rounded,
    };
    final typeColors = {
      'Glass': Colors.cyan.shade800,
      'Intercall': Colors.teal.shade800,
      'Gas': Colors.amber.shade900,
      'Tempering': Colors.deepOrange.shade800,
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
                child: Divider(
                  color: sectionColor.withValues(alpha: 0.4),
                  thickness: 1.5,
                ),
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
              leading:
                  type == 'Panneau' &&
                      _isDecorSubtype(item['subtype']?.toString()) &&
                      DecorPanelDesignCatalog.isSupported(
                        item['decor_design_code']?.toString(),
                      )
                  ? DecorPanelDesignPreview(
                      designCode: item['decor_design_code']?.toString(),
                      width: 36,
                      height: 58,
                    )
                  : null,
              title: Text(
                Localization.translate(item['name'].toString(), lang),
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: sectionColor,
                ),
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
                    : type == 'Tempering'
                    ? Localization.translate('تقسية (Trempé)', lang)
                    : type == 'Panneau'
                    ? Localization.translate('مغلق', lang)
                    : type == 'Baguette'
                    ? Localization.translate('باجيت ديكور', lang)
                    : Localization.translate('وردة ديكور', lang);
                String dimText = '';
                if (type == 'Rosette') {
                  dimText =
                      ' - ${Localization.translate('الأبعاد', lang)}: ${thickness.toStringAsFixed(0)} × ${rosetteHeight.toStringAsFixed(0)} ${Localization.translate('مم', lang)}';
                } else if (type == 'Baguette') {
                  dimText =
                      ' - ${Localization.translate('العرض', lang)}: ${thickness.toStringAsFixed(0)} ${Localization.translate('مم', lang)}';
                } else {
                  dimText =
                      ' - ${Localization.translate('السماكة', lang)}: ${thickness.toStringAsFixed(thickness.truncateToDouble() == thickness ? 0 : 1)} ${Localization.translate('مم', lang)}';
                  if (type == 'Panneau' &&
                      (item['subtype']?.toString() ?? '') == 'bardage' &&
                      item['visible_width'] != null) {
                    double vw = (item['visible_width'] is num)
                        ? (item['visible_width'] as num).toDouble()
                        : double.tryParse(item['visible_width'].toString()) ??
                              0.0;
                    if (vw > 0)
                      dimText +=
                          ' - ${Localization.translate('العرض الظاهر', lang)}: ${vw.toStringAsFixed(0)} ${Localization.translate('مم', lang)}';
                  } else if (type == 'Panneau' &&
                      _isDecorSubtype(item['subtype']?.toString())) {
                    final decorWidth =
                        (item['visible_width'] as num?)?.toDouble() ?? 0.0;
                    final decorHeight =
                        (item['height'] as num?)?.toDouble() ?? 0.0;
                    if (decorWidth > 0 && decorHeight > 0) {
                      dimText +=
                          ' - ${Localization.translate('أبعاد الديكور', lang)}: ${decorWidth.toStringAsFixed(0)} × ${decorHeight.toStringAsFixed(0)} ${Localization.translate('مم', lang)}';
                    }
                  }
                }
                final colorPart =
                    (type == 'Glass' ||
                            type == 'Panneau' ||
                            type == 'Baguette' ||
                            type == 'Rosette') &&
                        colorText.isNotEmpty
                    ? ' - ${Localization.translate('اللون', lang)}: ${Localization.translate(colorText, lang)}'
                    : '';
                final subtypePart =
                    type == 'Panneau' &&
                        (item['subtype']?.toString() ?? '').isNotEmpty
                    ? ' - ${Localization.translate('الخاصية', lang)}: ${item['subtype']}'
                    : '';
                final designPart =
                    type == 'Panneau' &&
                        _isDecorSubtype(item['subtype']?.toString()) &&
                        DecorPanelDesignCatalog.isSupported(
                          item['decor_design_code']?.toString(),
                        )
                    ? ' - ${Localization.translate('الرسم', lang)}: ${Localization.translate(DecorPanelDesignCatalog.labelKeyFor(item['decor_design_code']?.toString()), lang)}'
                    : '';
                final priceUnit =
                    type == 'Rosette' ||
                        (type == 'Panneau' &&
                            _isDecorSubtype(item['subtype']?.toString()))
                    ? Localization.translate('دج/قطعة', lang)
                    : type == 'Baguette'
                    ? Localization.translate('دج/متر', lang)
                    : Localization.translate('دج/م²', lang);
                final pricePart =
                    ' - ${Localization.translate('السعر', lang)}: ${price.toStringAsFixed(price.truncateToDouble() == price ? 0 : 2)} $priceUnit';
                return '${Localization.translate('النوع', lang)}: $typeLabel$dimText$colorPart$subtypePart$designPart$pricePart';
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
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
            child: TextField(
              controller: _searchController,
              onChanged: (value) => setState(() => _searchQuery = value),
              decoration: InputDecoration(
                hintText: Localization.translate('بحث بالاسم أو النوع', lang),
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchQuery.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                      ),
                border: const OutlineInputBorder(),
              ),
            ),
          ),
          Expanded(
            child: filteredItems.isEmpty
                ? Center(
                    child: Text(Localization.translate('لا توجد نتائج', lang)),
                  )
                : ListView(children: sections),
          ),
        ],
      ),
      floatingActionButton: !isUserAdmin
          ? null
          : FloatingActionButton(
              onPressed: _showAddDialog,
              child: const Icon(Icons.add),
            ),
    );
  }
}
