import 'package:flutter/material.dart';
import '../sql_database.dart';
import 'package:database_data/settings/localization.dart';
import 'package:database_data/settings/app_settings.dart';
import 'package:provider/provider.dart';
import 'kit_bundles_screen.dart';

class ShuttersScreen extends StatefulWidget {
  final SqlDatabase db;

  const ShuttersScreen({super.key, required this.db});

  @override
  State<ShuttersScreen> createState() => _ShuttersScreenState();
}

class _ShuttersScreenState extends State<ShuttersScreen> {
  List<Map<String, dynamic>> _items = [];
  bool _showArchived = false;

  @override
  void initState() {
    super.initState();
    _loadItems();
  }

  Future<void> _loadItems() async {
    final items = await widget.db.readShutterComponents(
      includeInactive: _showArchived,
    );
    if (!mounted) return;
    setState(() {
      _items = items;
    });
  }

  void _showAddDialog() {
    final nameCtrl = TextEditingController();
    final barLengthCtrl = TextEditingController();
    final measurementCtrl = TextEditingController();
    final motorDiameterCtrl = TextEditingController();
    final capThicknessCtrl = TextEditingController();
    String selectedType = 'box';
    String selectedUnit = 'bar';

    final lang = Provider.of<AppSettingsProvider>(
      context,
      listen: false,
    ).language;
    final types = {
      'box': Localization.translate('صندوق', lang),
      'caisson_tunnel': 'Caisson Tunnel',
      'blade': Localization.translate('شفرة/شريحة', lang),
      'track': Localization.translate('سكة/مسار', lang),
      'motor': Localization.translate('محرك', lang),
      'kit': Localization.translate('كيت (Kit)', lang),
      'laxe': Localization.translate('أنبوب المحرك (L\'axe)', lang),
      'final_blade': Localization.translate('الشفرة النهائية', lang),
      'attache': Localization.translate('أطاش (Attache)', lang),
      'support_moteur': Localization.translate(
        'سيبور موتور (Support Moteur)',
        lang,
      ),
      'embout': Localization.translate('الامبو (Embout)', lang),
      'support_roulement': Localization.translate(
        'سيبور رولمو (Support Roulement)',
        lang,
      ),
      'tandem': Localization.translate('طانديم (Tandem)', lang),
      'bouchon_lame': Localization.translate(
        'أغطية الشفرات (Bouchons Lames)',
        lang,
      ),
      'rouleau': Localization.translate('رولو (Rouleau)', lang),
      'tulip': Localization.translate('توليب (Tulip)', lang),
    };

    final units = {
      'piece': Localization.translate('بالقطعة', lang),
      'bar': Localization.translate('بالبارة', lang),
    };

    String selectedSubtype = 'normal';

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) => AlertDialog(
          title: Text(
            Localization.translate('إضافة مركب للستار', lang),
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          content: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 520,
              maxHeight: MediaQuery.of(context).size.height * 0.7,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                TextField(
                  controller: nameCtrl,
                  decoration: InputDecoration(
                    labelText: Localization.translate(
                      'اسم المركب (مثال: محرك سومفي)',
                      lang,
                    ),
                    border: OutlineInputBorder(),
                  ),
                ),
                SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: selectedType,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: Localization.translate('النوع', lang),
                    border: OutlineInputBorder(),
                  ),
                  items: types.entries
                      .map(
                        (e) => DropdownMenuItem(
                          value: e.key,
                          child: Text(
                            e.value,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (val) {
                    setStateDialog(() {
                      selectedType = val!;
                      if (selectedType == 'kit') {
                        selectedUnit = 'piece';
                      }
                    });
                  },
                ),
                SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: selectedUnit,
                  decoration: InputDecoration(
                    labelText: Localization.translate('الوحدة', lang),
                    border: OutlineInputBorder(),
                  ),
                  items: units.entries
                      .map(
                        (e) => DropdownMenuItem(
                          value: e.key,
                          child: Text(e.value),
                        ),
                      )
                      .toList(),
                  onChanged: (val) {
                    setStateDialog(() {
                      selectedUnit = val!;
                      // Force piece for specific types
                      if (selectedType == 'kit') {
                        selectedUnit = 'piece';
                      }
                    });
                  },
                ),
                if (selectedUnit == 'bar' && selectedType != 'kit') ...[
                  SizedBox(height: 10),
                  TextField(
                    controller: barLengthCtrl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: Localization.translate(
                        'طول البارة (بالمتر)',
                        lang,
                      ),
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
                if ([
                  'blade',
                  'laxe',
                  'final_blade',
                  'attache',
                  'support_moteur',
                  'embout',
                  'support_roulement',
                  'tandem',
                  'rouleau',
                  'tulip',
                ].contains(selectedType)) ...[
                  SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    initialValue: selectedSubtype,
                    decoration: InputDecoration(
                      labelText: Localization.translate(
                        'نوع الشفرة/الملحق',
                        lang,
                      ),
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      DropdownMenuItem(
                        value: 'normal',
                        child: Text(Localization.translate('عادي', lang)),
                      ),
                      DropdownMenuItem(
                        value: 'extruded',
                        child: Text(Localization.translate('إكسترودي', lang)),
                      ),
                    ],
                    onChanged: (val) {
                      setStateDialog(() {
                        selectedSubtype = val!;
                      });
                    },
                  ),
                ],
                if (selectedType == 'bouchon_lame' || selectedType == 'rouleau' || selectedType == 'tulip') ...[
                  SizedBox(height: 10),
                  FutureBuilder<List<Map<String, dynamic>>>(
                    future: SqlDatabase().db.then(
                      (db) =>
                          db?.query(
                            'ShutterComponents',
                            where:
                                "component_type = 'blade' AND (is_active = 1 OR is_active IS NULL)",
                          ) ??
                          [],
                    ),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData)
                        return const Center(child: CircularProgressIndicator());
                      final blades = snapshot.data!;
                      return DropdownButtonFormField<String>(
                        value: blades.any((b) => b['name'] == selectedSubtype)
                            ? selectedSubtype
                            : (blades.isNotEmpty
                                  ? blades.first['name'].toString()
                                  : null),
                        decoration: InputDecoration(
                          labelText: Localization.translate(
                            'الشفرة المرتبطة (Blade)',
                            lang,
                          ),
                          border: OutlineInputBorder(),
                        ),
                        items: blades
                            .map(
                              (b) => DropdownMenuItem(
                                value: b['name'].toString(),
                                child: Text(b['name'].toString()),
                              ),
                            )
                            .toList(),
                        onChanged: (val) {
                          setStateDialog(() {
                            selectedSubtype = val ?? 'normal';
                          });
                        },
                      );
                    },
                  ),
                ],
                if (![
                  'laxe',
                  'attache',
                  'support_roulement',
                  'tandem',
                  'bouchon_lame',
                ].contains(selectedType)) ...[
                  SizedBox(height: 10),
                  TextField(
                    controller: measurementCtrl,
                    decoration: InputDecoration(
                      labelText: Localization.translate(
                        selectedType == 'motor'
                            ? 'قياس المحرك (مثال: 10Nm أو 20Nm)'
                            : 'القياس (مثال: 185 أو 55)',
                        lang,
                      ),
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
                if (selectedType == 'motor') ...[
                  SizedBox(height: 10),
                  TextField(
                    controller: motorDiameterCtrl,
                    decoration: InputDecoration(
                      labelText: Localization.translate(
                        'قطر المحرك (مثال: 45 أو 55)',
                        lang,
                      ),
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
                if (selectedType == 'bouchon_lame') ...[
                  SizedBox(height: 10),
                  TextField(
                    controller: capThicknessCtrl,
                    keyboardType: TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: Localization.translate(
                        'سمك أغطية الشفرات (مم)',
                        lang,
                      ),
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(Localization.translate('إلغاء', lang)),
            ),
            ElevatedButton(
              onPressed: () async {
                if (nameCtrl.text.isNotEmpty) {
                  try {
                    await widget.db.insertShutterComponent(
                      nameCtrl.text,
                      selectedType,
                      0.0,
                      selectedUnit,
                      barLengthM: double.tryParse(barLengthCtrl.text) ?? 0.0,
                      measurement:
                          [
                            'laxe',
                            'attache',
                            'support_roulement',
                            'tandem',
                            'bouchon_lame',
                          ].contains(selectedType)
                          ? null
                          : (measurementCtrl.text.trim().isEmpty
                                ? null
                                : measurementCtrl.text.trim()),
                      shutterSubtype: selectedSubtype,
                      motorDiameter: selectedType == 'motor'
                          ? (motorDiameterCtrl.text.trim().isEmpty
                                ? null
                                : motorDiameterCtrl.text.trim())
                          : null,
                      capThickness: selectedType == 'bouchon_lame'
                          ? (double.tryParse(capThicknessCtrl.text) ?? 0.0)
                          : 0.0,
                    );
                    if (context.mounted) Navigator.pop(context);
                    _loadItems();
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(SnackBar(content: Text('Error: $e')));
                    }
                  }
                }
              },
              child: Text(Localization.translate('إضافة', lang)),
            ),
          ],
        ),
      ),
    );
  }

  void _showEditDialog(Map<String, dynamic> item) {
    final nameCtrl = TextEditingController(text: item['name']);
    final barLengthCtrl = TextEditingController(
      text: item['bar_length_m']?.toString() ?? '',
    );
    final measurementCtrl = TextEditingController(
      text: item['measurement']?.toString() ?? '',
    );
    final motorDiameterCtrl = TextEditingController(
      text: item['motor_diameter']?.toString() ?? '',
    );
    final capThicknessCtrl = TextEditingController(
      text: item['cap_thickness']?.toString() ?? '',
    );
    String selectedType = item['component_type']?.toString() ?? 'box';
    String selectedUnit = item['unit']?.toString() ?? 'piece';
    if (selectedUnit != 'piece' && selectedUnit != 'bar') {
      selectedUnit = 'piece';
    }

    final lang = Provider.of<AppSettingsProvider>(
      context,
      listen: false,
    ).language;
    final types = {
      'box': Localization.translate('صندوق', lang),
      'caisson_tunnel': 'Caisson Tunnel',
      'blade': Localization.translate('شفرة/شريحة', lang),
      'track': Localization.translate('سكة/مسار', lang),
      'motor': Localization.translate('محرك', lang),
      'kit': Localization.translate('كيت (Kit)', lang),
      'laxe': Localization.translate('أنبوب المحرك (L\'axe)', lang),
      'final_blade': Localization.translate('الشفرة النهائية', lang),
      'attache': Localization.translate('أطاش (Attache)', lang),
      'support_moteur': Localization.translate(
        'سيبور موتور (Support Moteur)',
        lang,
      ),
      'embout': Localization.translate('الامبو (Embout)', lang),
      'support_roulement': Localization.translate(
        'سيبور رولمو (Support Roulement)',
        lang,
      ),
      'tandem': Localization.translate('طانديم (Tandem)', lang),
      'bouchon_lame': Localization.translate(
        'أغطية الشفرات (Bouchons Lames)',
        lang,
      ),
      'rouleau': Localization.translate('رولو (Rouleau)', lang),
      'tulip': Localization.translate('توليب (Tulip)', lang),
    };

    final units = {
      'piece': Localization.translate('بالقطعة', lang),
      'bar': Localization.translate('بالبارة', lang),
    };

    String selectedSubtype = item['shutter_subtype']?.toString() ?? 'normal';

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) => AlertDialog(
          title: Text(
            Localization.translate('تعديل مركب للستار', lang),
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: InputDecoration(
                    labelText: Localization.translate('اسم المركب', lang),
                    border: OutlineInputBorder(),
                  ),
                ),
                SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: types.containsKey(selectedType)
                      ? selectedType
                      : 'box',
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: Localization.translate('النوع', lang),
                    border: OutlineInputBorder(),
                  ),
                  items: types.entries
                      .map(
                        (e) => DropdownMenuItem(
                          value: e.key,
                          child: Text(
                            e.value,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (val) {
                    setStateDialog(() {
                      selectedType = val!;
                      if (selectedType == 'kit') {
                        selectedUnit = 'piece';
                      }
                    });
                  },
                ),
                SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: selectedUnit,
                  decoration: InputDecoration(
                    labelText: Localization.translate('الوحدة', lang),
                    border: OutlineInputBorder(),
                  ),
                  items: units.entries
                      .map(
                        (e) => DropdownMenuItem(
                          value: e.key,
                          child: Text(e.value),
                        ),
                      )
                      .toList(),
                  onChanged: (val) {
                    setStateDialog(() {
                      selectedUnit = val!;
                      // Force piece for specific types
                      if ([
                        'kit',
                        'screw_kit',
                        'screw_box',
                        'screw_motor',
                        'screw_manivelle',
                      ].contains(selectedType)) {
                        selectedUnit = 'piece';
                      }
                    });
                  },
                ),
                if (selectedUnit == 'bar' && selectedType != 'kit') ...[
                  SizedBox(height: 10),
                  TextField(
                    controller: barLengthCtrl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: Localization.translate(
                        'طول البارة (بالمتر)',
                        lang,
                      ),
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
                if ([
                  'blade',
                  'laxe',
                  'final_blade',
                  'attache',
                  'support_moteur',
                  'embout',
                  'support_roulement',
                  'tandem',
                  'rouleau',
                  'tulip',
                ].contains(selectedType)) ...[
                  SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    initialValue: selectedSubtype,
                    decoration: InputDecoration(
                      labelText: Localization.translate(
                        'نوع الشفرة/الملحق',
                        lang,
                      ),
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      DropdownMenuItem(
                        value: 'normal',
                        child: Text(Localization.translate('عادي', lang)),
                      ),
                      DropdownMenuItem(
                        value: 'extruded',
                        child: Text(Localization.translate('إكسترودي', lang)),
                      ),
                    ],
                    onChanged: (val) {
                      setStateDialog(() {
                        selectedSubtype = val!;
                      });
                    },
                  ),
                ],
                if (selectedType == 'bouchon_lame' || selectedType == 'rouleau' || selectedType == 'tulip') ...[
                  SizedBox(height: 10),
                  FutureBuilder<List<Map<String, dynamic>>>(
                    future: SqlDatabase().db.then(
                      (db) =>
                          db?.query(
                            'ShutterComponents',
                            where:
                                "component_type = 'blade' AND (is_active = 1 OR is_active IS NULL)",
                          ) ??
                          [],
                    ),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData)
                        return const Center(child: CircularProgressIndicator());
                      final blades = snapshot.data!;
                      return DropdownButtonFormField<String>(
                        value: blades.any((b) => b['name'] == selectedSubtype)
                            ? selectedSubtype
                            : (blades.isNotEmpty
                                  ? blades.first['name'].toString()
                                  : null),
                        decoration: InputDecoration(
                          labelText: Localization.translate(
                            'الشفرة المرتبطة (Blade)',
                            lang,
                          ),
                          border: OutlineInputBorder(),
                        ),
                        items: blades
                            .map(
                              (b) => DropdownMenuItem(
                                value: b['name'].toString(),
                                child: Text(b['name'].toString()),
                              ),
                            )
                            .toList(),
                        onChanged: (val) {
                          setStateDialog(() {
                            selectedSubtype = val ?? 'normal';
                          });
                        },
                      );
                    },
                  ),
                ],
                if (![
                  'laxe',
                  'attache',
                  'support_roulement',
                  'tandem',
                  'bouchon_lame',
                ].contains(selectedType)) ...[
                  SizedBox(height: 10),
                  TextField(
                    controller: measurementCtrl,
                    decoration: InputDecoration(
                      labelText: Localization.translate(
                        selectedType == 'motor'
                            ? 'قياس المحرك (مثال: 10Nm أو 20Nm)'
                            : 'القياس (مثال: 185 أو 55)',
                        lang,
                      ),
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
                if (selectedType == 'motor') ...[
                  SizedBox(height: 10),
                  TextField(
                    controller: motorDiameterCtrl,
                    decoration: InputDecoration(
                      labelText: Localization.translate(
                        'قطر المحرك (مثال: 45 أو 55)',
                        lang,
                      ),
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
                if (selectedType == 'bouchon_lame') ...[
                  SizedBox(height: 10),
                  TextField(
                    controller: capThicknessCtrl,
                    keyboardType: TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: Localization.translate(
                        'سمك أغطية الشفرات (مم)',
                        lang,
                      ),
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(Localization.translate('إلغاء', lang)),
            ),
            ElevatedButton(
              onPressed: () async {
                if (nameCtrl.text.isNotEmpty) {
                  try {
                    await widget.db.updateShutterComponent(
                      item['id'],
                      nameCtrl.text,
                      selectedType,
                      double.tryParse(item['price']?.toString() ?? '0') ?? 0.0,
                      selectedUnit,
                      barLengthM: double.tryParse(barLengthCtrl.text) ?? 0.0,
                      measurement:
                          [
                            'laxe',
                            'attache',
                            'support_roulement',
                            'tandem',
                            'bouchon_lame',
                          ].contains(selectedType)
                          ? null
                          : (measurementCtrl.text.trim().isEmpty
                                ? null
                                : measurementCtrl.text.trim()),
                      shutterSubtype: selectedSubtype,
                      motorDiameter: selectedType == 'motor'
                          ? (motorDiameterCtrl.text.trim().isEmpty
                                ? null
                                : motorDiameterCtrl.text.trim())
                          : null,
                      capThickness: selectedType == 'bouchon_lame'
                          ? (double.tryParse(capThicknessCtrl.text) ?? 0.0)
                          : 0.0,
                    );
                    if (context.mounted) Navigator.pop(context);
                    _loadItems();
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(SnackBar(content: Text('Error: $e')));
                    }
                  }
                }
              },
              child: Text(Localization.translate('حفظ', lang)),
            ),
          ],
        ),
      ),
    );
  }

  void _showDeleteDialog(Map<String, dynamic> item) {
    final bool isArchived = item['is_active'] == 0;
    final lang = Provider.of<AppSettingsProvider>(
      context,
      listen: false,
    ).language;

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          isArchived
              ? Localization.translate('خيارات حذف المكون المؤرشف', lang)
              : Localization.translate('تأكيد الحذف والأرشفة', lang),
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.red,
            fontFamily: 'Cairo',
          ),
        ),
        content: Text(
          isArchived
              ? Localization.translate(
                  'هذا العنصر مؤرشف بالفعل. يمكنك استعادته ليصبح نشطاً مجدداً أو حذفه نهائياً من قاعدة البيانات.',
                  lang,
                )
              : Localization.translate(
                  'يمكنك أرشفة هذا العنصر (إخفاؤه من الطلبيات الجديدة مع الحفاظ على الفواتير القديمة) أو حذفه نهائياً من قاعدة البيانات.',
                  lang,
                ),
          style: const TextStyle(fontSize: 14, fontFamily: 'Cairo'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(
              Localization.translate('إلغاء', lang),
              style: const TextStyle(fontFamily: 'Cairo'),
            ),
          ),
          if (isArchived)
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
              onPressed: () async {
                await widget.db.restoreShutterComponent(item['id']);
                _loadItems();
                if (context.mounted) Navigator.pop(dialogContext);
              },
              child: Text(
                Localization.translate('استعادة المكون', lang),
                style: const TextStyle(color: Colors.white, fontFamily: 'Cairo'),
              ),
            ),
          if (!isArchived)
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
              onPressed: () async {
                await widget.db.deleteShutterComponent(item['id']);
                _loadItems();
                if (context.mounted) Navigator.pop(dialogContext);
              },
              child: Text(
                Localization.translate('أرشفة (إخفاء)', lang),
                style: const TextStyle(color: Colors.white, fontFamily: 'Cairo'),
              ),
            ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              await widget.db.deleteShutterComponentPermanently(item['id']);
              _loadItems();
              if (context.mounted) Navigator.pop(dialogContext);
            },
            child: Text(
              Localization.translate('حذف نهائي', lang),
              style: const TextStyle(color: Colors.white, fontFamily: 'Cairo'),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isUserAdmin = isAdmin; // from app_settings
    final lang = Provider.of<AppSettingsProvider>(context).language;

    final typeOrder = [
      'box',
      'caisson_tunnel',
      'blade',
      'track',
      'motor',
      'kit',
      'laxe',
      'final_blade',
      'bouchon_lame',
      'attache',
      'support_moteur',
      'embout',
      'support_roulement',
      'tandem',
    ];

    Map<String, List<Map<String, dynamic>>> grouped = {};
    for (var type in typeOrder) {
      grouped[type] = _items.where((i) => i['component_type'] == type).toList();
    }

    // Add any types that might be missing from the order list
    for (var item in _items) {
      if (!typeOrder.contains(item['component_type'])) {
        grouped
            .putIfAbsent(
              item['component_type']?.toString() ?? 'other',
              () => [],
            )
            .add(item);
      }
    }

    List<Widget> sections = [];

    final typeLabels = {
      'box': Localization.translate('صندوق', lang),
      'caisson_tunnel': 'Caisson Tunnel',
      'blade': Localization.translate('شفرات', lang),
      'track': Localization.translate('سكة/مسار', lang),
      'motor': Localization.translate('محرك', lang),
      'kit': Localization.translate('كيت (Kit)', lang),
      'laxe': Localization.translate('أنبوب المحرك (L\'axe)', lang),
      'final_blade': Localization.translate('الشفرة النهائية', lang),
      'attache': Localization.translate('أطاش (Attache)', lang),
      'support_moteur': Localization.translate(
        'سيبور موتور (Support Moteur)',
        lang,
      ),
      'embout': Localization.translate('الامبو (Embout)', lang),
      'support_roulement': Localization.translate(
        'سيبور رولمو (Support Roulement)',
        lang,
      ),
      'tandem': Localization.translate('طانديم (Tandem)', lang),
      'bouchon_lame': Localization.translate(
        'أغطية الشفرات (Bouchons Lames)',
        lang,
      ),
    };

    final typeColors = {
      'box': Colors.blue,
      'caisson_tunnel': Colors.deepOrange,
      'blade': Colors.teal,
      'track': Colors.orange,
      'motor': Colors.purple,
      'kit': Colors.red,
      'laxe': Colors.indigo,
      'final_blade': Colors.green,
      'attache': Colors.brown,
      'support_moteur': Colors.cyan,
      'embout': Colors.amber,
      'support_roulement': Colors.deepOrange,
      'tandem': Colors.pink,
      'bouchon_lame': Colors.blueGrey,
      'other': Colors.grey,
    };

    for (var type in grouped.keys) {
      final items = grouped[type] ?? [];
      if (items.isEmpty) continue;

      final sectionColor = typeColors[type] ?? Colors.blue;

      sections.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
          child: Row(
            children: [
              Icon(Icons.category, color: sectionColor, size: 22),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  typeLabels[type] ?? type,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: sectionColor,
                  ),
                  overflow: TextOverflow.ellipsis,
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
        String subtypeStr = '';
        if ([
          'blade',
          'laxe',
          'final_blade',
          'attache',
          'support_moteur',
          'embout',
          'support_roulement',
          'tandem',
          'bouchon_lame',
          'rouleau',
          'tulip',
        ].contains(item['component_type'])) {
          final sub = item['shutter_subtype']?.toString() ?? 'normal';
          if (['bouchon_lame', 'rouleau', 'tulip'].contains(item['component_type'])) {
            subtypeStr = ' - ${Localization.translate("مرتبط بـ:", lang)} $sub';
          } else {
            subtypeStr =
                ' - ${Localization.translate("النوع:", lang)} ${sub == 'extruded' ? Localization.translate('إكسترودي', lang) : Localization.translate('عادي', lang)}';
          }
        }

        String unitAr = item['unit'] == 'bar'
            ? Localization.translate('بالبارة', lang)
            : Localization.translate('بالقطعة', lang);
        String barLenStr =
            (item['unit'] == 'bar' &&
                item['bar_length_m'] != null &&
                item['bar_length_m'] > 0)
            ? ' - ${Localization.translate("طول البارة:", lang)} ${item['bar_length_m']} ${Localization.translate('م', lang)}'
            : '';
        final mVal = item['measurement']?.toString().trim();
        String measStr = '';
        if (mVal != null && mVal.isNotEmpty && mVal.toLowerCase() != 'null') {
          if (item['component_type'] == 'motor') {
            measStr =
                ' - ${Localization.translate("قياس المحرك:", lang)} $mVal';
          } else {
            measStr = ' - ${Localization.translate("القياس:", lang)} $mVal';
          }
        }

        final dVal = item['motor_diameter']?.toString().trim();
        String diamStr = '';
        if (item['component_type'] == 'motor' &&
            dVal != null &&
            dVal.isNotEmpty &&
            dVal.toLowerCase() != 'null') {
          diamStr = ' - ${Localization.translate("قطر المحرك:", lang)} $dVal';
        }

        final capTh = item['cap_thickness'] != null
            ? (item['cap_thickness'] as num).toDouble()
            : 0.0;
        String capStr = '';
        if (capTh > 0 &&
            [
              'blade',
              'final_blade',
              'bouchon_lame',
            ].contains(item['component_type'])) {
          capStr =
              ' - ${Localization.translate("سمك الأغطية:", lang)} $capTh ${Localization.translate('مم', lang)}';
        }

        final bool isArchived = item['is_active'] == 0;

        sections.add(
          Card(
            color: isArchived ? Colors.grey.shade100 : null,
            margin: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: ListTile(
              title: Text(
                isArchived
                    ? '${item['name']} (${Localization.translate('مؤرشف', lang)})'
                    : item['name'].toString(),
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: isArchived ? Colors.grey : sectionColor,
                  decoration: isArchived ? TextDecoration.lineThrough : null,
                ),
              ),
              subtitle: Text(
                '${Localization.translate("الوحدة:", lang)} $unitAr$subtypeStr$barLenStr$measStr$diamStr$capStr',
                style: TextStyle(color: isArchived ? Colors.grey : null),
              ),
              trailing: isUserAdmin
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (isArchived) ...[
                          IconButton(
                            icon: Icon(Icons.restore, color: Colors.green),
                            tooltip: Localization.translate('استعادة', lang),
                            onPressed: () async {
                              await widget.db.restoreShutterComponent(
                                item['id'],
                              );
                              _loadItems();
                            },
                          ),
                          IconButton(
                            icon: Icon(Icons.delete_forever, color: Colors.red),
                            tooltip: Localization.translate('حذف نهائي', lang),
                            onPressed: () => _showDeleteDialog(item),
                          ),
                        ] else ...[
                          IconButton(
                            icon: Icon(Icons.edit, color: Colors.blue),
                            onPressed: () => _showEditDialog(item),
                          ),
                          IconButton(
                            icon: Icon(Icons.delete, color: Colors.red),
                            tooltip: Localization.translate('أرشفة', lang),
                            onPressed: () => _showDeleteDialog(item),
                          ),
                        ],
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
        title: Text(Localization.translate('مركبات الستائر', lang)),
        actions: [
          IconButton(
            icon: Icon(_showArchived ? Icons.visibility : Icons.visibility_off),
            tooltip: _showArchived
                ? Localization.translate('إخفاء المؤرشف', lang)
                : Localization.translate('عرض المؤرشف', lang),
            onPressed: () {
              setState(() {
                _showArchived = !_showArchived;
              });
              _loadItems();
            },
          ),
          if (isUserAdmin)
            IconButton(
              icon: const Icon(Icons.inventory_2_outlined),
              tooltip: Localization.translate('ادارة Kits', lang),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => KitBundlesScreen(db: widget.db),
                ),
              ),
            ),
        ],
      ),
      body: _items.isEmpty
          ? Center(child: Text(Localization.translate('لا توجد بيانات', lang)))
          : ListView(children: sections),
      floatingActionButton: isUserAdmin
          ? FloatingActionButton(
              onPressed: _showAddDialog,
              child: Icon(Icons.add),
            )
          : null,
    );
  }
}
