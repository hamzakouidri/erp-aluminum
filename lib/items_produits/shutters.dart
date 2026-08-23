import 'dart:async';

import 'package:flutter/material.dart';
import '../sql_database.dart';
import 'package:database_data/services/cloud_sync_service.dart';
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
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  StreamSubscription<String>? _dbSubscription;
  Timer? _reloadDebounce;

  bool _isEnabledFlag(dynamic value) {
    if (value is num) return value != 0;
    final normalized = value?.toString().trim().toLowerCase();
    return normalized == 'true' || normalized == '1' || normalized == 'yes';
  }

  int? _readInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString().trim() ?? '');
  }

  double _readDouble(dynamic value, {double fallback = 0.0}) {
    if (value is num) return value.toDouble();
    final text = value?.toString().trim().replaceAll(',', '.') ?? '';
    if (text.isEmpty || text.toLowerCase() == 'null') return fallback;
    return double.tryParse(text) ?? fallback;
  }

  @override
  void initState() {
    super.initState();
    _loadItems();
    _dbSubscription = CloudSyncService().dbUpdateStream.listen((_) {
      _reloadDebounce?.cancel();
      _reloadDebounce = Timer(const Duration(milliseconds: 250), () {
        if (mounted) _loadItems();
      });
    });
  }

  @override
  void dispose() {
    _reloadDebounce?.cancel();
    _dbSubscription?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadItems() async {
    try {
      final items = await widget.db.readShutterComponents(
        includeInactive: _showArchived,
      );
      if (!mounted) return;
      setState(() {
        _items = items;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _items = const [];
      });
    }
  }

  void _showAddDialog() {
    final nameCtrl = TextEditingController();
    final barLengthCtrl = TextEditingController();
    final measurementCtrl = TextEditingController();
    final trackMeasurementCtrl = TextEditingController();
    final motorDiameterCtrl = TextEditingController();
    final capThicknessCtrl = TextEditingController();
    String selectedType = 'box';
    String selectedUnit = 'bar';
    bool motorHasEmergencyCrank = false;

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
      'rouleau': Localization.translate('رولمان (Roulement)', lang),
      'tulip': Localization.translate('توليب (Tulip)', lang),
    };

    final units = {
      'piece': Localization.translate('بالقطعة', lang),
      'bar': Localization.translate('بالبارة', lang),
    };

    String selectedSubtype = 'normal';
    String? selectedLinkedBlade;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) => AlertDialog(
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 24,
          ),
          actionsOverflowAlignment: OverflowBarAlignment.end,
          actionsOverflowButtonSpacing: 8,
          title: Text(
            Localization.translate('إضافة مركب للستار', lang),
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          content: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 520,
              maxHeight:
                  (MediaQuery.of(context).size.height -
                      MediaQuery.of(context).viewInsets.bottom) *
                  0.52,
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
                        if (selectedType != 'bouchon_lame') {
                          selectedLinkedBlade = null;
                        }
                        if (selectedType == 'kit') {
                          selectedUnit = 'piece';
                        }
                        if (selectedType != 'motor') {
                          motorHasEmergencyCrank = false;
                        }
                      });
                    },
                  ),
                  SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    initialValue: selectedUnit,
                    isExpanded: true,
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
                      isExpanded: true,
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
                  // Only blade end caps are tied to a particular blade.
                  if (selectedType == 'bouchon_lame') ...[
                    SizedBox(height: 10),
                    FutureBuilder<List<Map<String, dynamic>>>(
                      future: SqlDatabase().db.then(
                        (db) =>
                            db?.query(
                              'ShutterComponents',
                              where:
                                  "LOWER(TRIM(component_type)) IN ('blade', 'lame') AND (is_active = 1 OR is_active IS NULL)",
                            ) ??
                            [],
                      ),
                      builder: (context, snapshot) {
                        if (!snapshot.hasData)
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        final blades = snapshot.data!;
                        return DropdownButtonFormField<String>(
                          isExpanded: true,
                          value:
                              blades.any(
                                (b) => b['name'] == selectedLinkedBlade,
                              )
                              ? selectedLinkedBlade
                              : null,
                          hint: Text(
                            Localization.translate(
                              'اختر الشفرة المرتبطة',
                              lang,
                            ),
                          ),
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
                                  child: Text(
                                    b['name'].toString(),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: (val) {
                            setStateDialog(() {
                              selectedLinkedBlade = val;
                            });
                          },
                        );
                      },
                    ),
                  ],
                  if (![
                    'attache',
                    'support_roulement',
                    'bouchon_lame',
                  ].contains(selectedType)) ...[
                    SizedBox(height: 10),
                    TextField(
                      controller: measurementCtrl,
                      decoration: InputDecoration(
                        labelText: Localization.translate(
                          selectedType == 'blade'
                              ? 'ارتفاع الشفرة (مم)'
                              : selectedType == 'track'
                              ? 'قياس السكة (مم)'
                              : selectedType == 'motor'
                              ? 'قياس المحرك (مثال: 10Nm أو 20Nm)'
                              : selectedType == 'laxe'
                              ? 'قطر المحور (مثال: 40 أو 60 مم)'
                              : selectedType == 'tandem'
                              ? 'قياس المحور المتوافق (مثال: 40 أو 60 مم)'
                              : 'القياس (مثال: 185 أو 55)',
                          lang,
                        ),
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                  if (selectedType == 'blade') ...[
                    SizedBox(height: 10),
                    TextField(
                      controller: trackMeasurementCtrl,
                      keyboardType: TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: Localization.translate(
                          'قياس السكة المطابق (مم)',
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
                    SizedBox(height: 10),
                    DropdownButtonFormField<bool>(
                      initialValue: motorHasEmergencyCrank,
                      decoration: InputDecoration(
                        labelText: Localization.translate(
                          'هل يحتوي المحرك على مانيفيل احتياطي؟',
                          lang,
                        ),
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        DropdownMenuItem(
                          value: true,
                          child: Text(Localization.translate('نعم', lang)),
                        ),
                        DropdownMenuItem(
                          value: false,
                          child: Text(Localization.translate('لا', lang)),
                        ),
                      ],
                      onChanged: (value) => setStateDialog(
                        () => motorHasEmergencyCrank = value ?? false,
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
                  if (selectedType == 'bouchon_lame' &&
                      (selectedLinkedBlade == null ||
                          selectedLinkedBlade!.trim().isEmpty)) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'يجب اختيار الشفرة المرتبطة بهذا الغطاء.',
                        ),
                      ),
                    );
                    return;
                  }
                  try {
                    await widget.db.insertShutterComponent(
                      nameCtrl.text,
                      selectedType,
                      0.0,
                      selectedUnit,
                      barLengthM: double.tryParse(barLengthCtrl.text) ?? 0.0,
                      measurement:
                          [
                            'attache',
                            'support_roulement',
                            'bouchon_lame',
                          ].contains(selectedType)
                          ? null
                          : (measurementCtrl.text.trim().isEmpty
                                ? null
                                : measurementCtrl.text.trim()),
                      trackMeasurement: selectedType == 'blade'
                          ? (trackMeasurementCtrl.text.trim().isEmpty
                                ? null
                                : trackMeasurementCtrl.text.trim())
                          : null,
                      shutterSubtype: selectedLinkedBlade ?? selectedSubtype,
                      motorDiameter: selectedType == 'motor'
                          ? (motorDiameterCtrl.text.trim().isEmpty
                                ? null
                                : motorDiameterCtrl.text.trim())
                          : null,
                      motorHasEmergencyCrank:
                          selectedType == 'motor' && motorHasEmergencyCrank,
                      capThickness: selectedType == 'bouchon_lame'
                          ? (double.tryParse(capThicknessCtrl.text) ?? 0.0)
                          : 0.0,
                    );
                    if (context.mounted) Navigator.pop(context);
                    if (mounted) unawaited(_loadItems());
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
    final trackMeasurementCtrl = TextEditingController(
      text: item['track_measurement']?.toString() ?? '',
    );
    final motorDiameterCtrl = TextEditingController(
      text: item['motor_diameter']?.toString() ?? '',
    );
    final capThicknessCtrl = TextEditingController(
      text: item['cap_thickness']?.toString() ?? '',
    );
    String selectedType = item['component_type']?.toString() ?? 'box';
    String selectedUnit = item['unit']?.toString() ?? 'piece';
    bool motorHasEmergencyCrank = _isEnabledFlag(
      item['motor_has_emergency_crank'],
    );
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
      'rouleau': Localization.translate('رولمان (Roulement)', lang),
      'tulip': Localization.translate('توليب (Tulip)', lang),
    };

    final units = {
      'piece': Localization.translate('بالقطعة', lang),
      'bar': Localization.translate('بالبارة', lang),
    };

    final storedSubtype = item['shutter_subtype']?.toString() ?? 'normal';
    // Legacy Tulip/Rouleau/Axe records sometimes stored a blade name here.
    // They are no longer blade-linked, so return them to their normal type
    // as soon as the item is edited.
    String selectedSubtype =
        ['normal', 'extruded'].contains(storedSubtype.toLowerCase())
        ? storedSubtype
        : 'normal';
    String? selectedLinkedBlade =
        selectedType == 'bouchon_lame' &&
            !['normal', 'extruded'].contains(storedSubtype.toLowerCase())
        ? storedSubtype
        : null;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) => AlertDialog(
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 24,
          ),
          actionsOverflowAlignment: OverflowBarAlignment.end,
          actionsOverflowButtonSpacing: 8,
          title: Text(
            Localization.translate('تعديل مركب للستار', lang),
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          content: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 520,
              maxHeight:
                  (MediaQuery.of(context).size.height -
                      MediaQuery.of(context).viewInsets.bottom) *
                  0.52,
            ),
            child: SingleChildScrollView(
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
                        if (selectedType != 'bouchon_lame') {
                          selectedLinkedBlade = null;
                        }
                        if (selectedType == 'kit') {
                          selectedUnit = 'piece';
                        }
                        if (selectedType != 'motor') {
                          motorHasEmergencyCrank = false;
                        }
                      });
                    },
                  ),
                  SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    initialValue: selectedUnit,
                    isExpanded: true,
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
                      isExpanded: true,
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
                  if (selectedType == 'blade') ...[
                    SizedBox(height: 10),
                    TextField(
                      controller: trackMeasurementCtrl,
                      keyboardType: TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: Localization.translate(
                          'قياس السكة المطابق (مم)',
                          lang,
                        ),
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                  // Tulip is not linked to a blade; this selector belongs only
                  // to blade end caps.
                  if (selectedType == 'bouchon_lame') ...[
                    SizedBox(height: 10),
                    FutureBuilder<List<Map<String, dynamic>>>(
                      future: SqlDatabase().db.then(
                        (db) =>
                            db?.query(
                              'ShutterComponents',
                              where:
                                  "LOWER(TRIM(component_type)) IN ('blade', 'lame') AND (is_active = 1 OR is_active IS NULL)",
                            ) ??
                            [],
                      ),
                      builder: (context, snapshot) {
                        if (!snapshot.hasData)
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        final blades = snapshot.data!;
                        return DropdownButtonFormField<String>(
                          isExpanded: true,
                          value:
                              blades.any(
                                (b) => b['name'] == selectedLinkedBlade,
                              )
                              ? selectedLinkedBlade
                              : null,
                          hint: Text(
                            Localization.translate(
                              'اختر الشفرة المرتبطة',
                              lang,
                            ),
                          ),
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
                                  child: Text(
                                    b['name'].toString(),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: (val) {
                            setStateDialog(() {
                              selectedLinkedBlade = val;
                            });
                          },
                        );
                      },
                    ),
                  ],
                  if (![
                    'attache',
                    'support_roulement',
                    'bouchon_lame',
                  ].contains(selectedType)) ...[
                    SizedBox(height: 10),
                    TextField(
                      controller: measurementCtrl,
                      decoration: InputDecoration(
                        labelText: Localization.translate(
                          selectedType == 'blade'
                              ? 'ارتفاع الشفرة (مم)'
                              : selectedType == 'track'
                              ? 'قياس السكة (مم)'
                              : selectedType == 'motor'
                              ? 'قياس المحرك (مثال: 10Nm أو 20Nm)'
                              : selectedType == 'laxe'
                              ? 'قطر المحور (مثال: 40 أو 60 مم)'
                              : selectedType == 'tandem'
                              ? 'قياس المحور المتوافق (مثال: 40 أو 60 مم)'
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
                    SizedBox(height: 10),
                    DropdownButtonFormField<bool>(
                      initialValue: motorHasEmergencyCrank,
                      decoration: InputDecoration(
                        labelText: Localization.translate(
                          'هل يحتوي المحرك على مانيفيل احتياطي؟',
                          lang,
                        ),
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        DropdownMenuItem(
                          value: true,
                          child: Text(Localization.translate('نعم', lang)),
                        ),
                        DropdownMenuItem(
                          value: false,
                          child: Text(Localization.translate('لا', lang)),
                        ),
                      ],
                      onChanged: (value) => setStateDialog(
                        () => motorHasEmergencyCrank = value ?? false,
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
                  if (selectedType == 'bouchon_lame' &&
                      (selectedLinkedBlade == null ||
                          selectedLinkedBlade!.trim().isEmpty)) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'يجب اختيار الشفرة المرتبطة بهذا الغطاء.',
                        ),
                      ),
                    );
                    return;
                  }
                  try {
                    final itemId = _readInt(item['id']);
                    if (itemId == null) return;
                    await widget.db.updateShutterComponent(
                      itemId,
                      nameCtrl.text,
                      selectedType,
                      double.tryParse(item['price']?.toString() ?? '0') ?? 0.0,
                      selectedUnit,
                      barLengthM: double.tryParse(barLengthCtrl.text) ?? 0.0,
                      measurement:
                          [
                            'attache',
                            'support_roulement',
                            'bouchon_lame',
                          ].contains(selectedType)
                          ? null
                          : (measurementCtrl.text.trim().isEmpty
                                ? null
                                : measurementCtrl.text.trim()),
                      trackMeasurement: selectedType == 'blade'
                          ? (trackMeasurementCtrl.text.trim().isEmpty
                                ? null
                                : trackMeasurementCtrl.text.trim())
                          : null,
                      shutterSubtype: selectedLinkedBlade ?? selectedSubtype,
                      motorDiameter: selectedType == 'motor'
                          ? (motorDiameterCtrl.text.trim().isEmpty
                                ? null
                                : motorDiameterCtrl.text.trim())
                          : null,
                      motorHasEmergencyCrank:
                          selectedType == 'motor' && motorHasEmergencyCrank,
                      capThickness: selectedType == 'bouchon_lame'
                          ? (double.tryParse(capThicknessCtrl.text) ?? 0.0)
                          : 0.0,
                    );
                    if (context.mounted) Navigator.pop(context);
                    if (mounted) unawaited(_loadItems());
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
                final itemId = _readInt(item['id']);
                if (itemId == null) return;
                await widget.db.restoreShutterComponent(itemId);
                if (mounted) unawaited(_loadItems());
                if (context.mounted) Navigator.pop(dialogContext);
              },
              child: Text(
                Localization.translate('استعادة المكون', lang),
                style: const TextStyle(
                  color: Colors.white,
                  fontFamily: 'Cairo',
                ),
              ),
            ),
          if (!isArchived)
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
              onPressed: () async {
                final itemId = _readInt(item['id']);
                if (itemId == null) return;
                await widget.db.deleteShutterComponent(itemId);
                if (mounted) unawaited(_loadItems());
                if (context.mounted) Navigator.pop(dialogContext);
              },
              child: Text(
                Localization.translate('أرشفة (إخفاء)', lang),
                style: const TextStyle(
                  color: Colors.white,
                  fontFamily: 'Cairo',
                ),
              ),
            ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              final itemId = _readInt(item['id']);
              if (itemId == null) return;
              await widget.db.deleteShutterComponentPermanently(itemId);
              if (mounted) unawaited(_loadItems());
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
    final searchQuery = _searchQuery.trim().toLowerCase();
    const typeAliases = <String, String>{
      'box': 'box caisson صندوق',
      'caisson_tunnel': 'caisson tunnel صندوق نفق',
      'blade': 'blade lame شريحة شفرة',
      'track': 'track coulisse سكة مسار',
      'motor': 'motor moteur محرك',
      'kit': 'kit كيت',
      'laxe': 'laxe axe محور أنبوب',
      'final_blade': 'final blade lame finale شفرة نهائية',
      'bouchon_lame': 'bouchon lame bouchons lames أغطية الشفرات',
      'attache': 'attache أطاش',
      'support_moteur': 'support moteur سيبور موتور',
      'embout': 'embout امبو',
      'support_roulement': 'support roulement سيبور رولمان',
      'tandem': 'tandem طانديم',
      'rouleau': 'roulement رولمان',
      'tulip': 'tulip توليب',
    };
    final filteredItems = searchQuery.isEmpty
        ? _items
        : _items.where((item) {
            final name = (item['name'] ?? '').toString().toLowerCase();
            final type = (item['component_type'] ?? '')
                .toString()
                .toLowerCase();
            final subtype = (item['shutter_subtype'] ?? '')
                .toString()
                .toLowerCase();
            final aliases = typeAliases[type] ?? '';
            return name.contains(searchQuery) ||
                type.contains(searchQuery) ||
                aliases.contains(searchQuery) ||
                subtype.contains(searchQuery);
          }).toList();

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
      grouped[type] = filteredItems
          .where((i) => i['component_type'] == type)
          .toList();
    }

    // Add any types that might be missing from the order list
    for (var item in filteredItems) {
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
      'rouleau': Colors.deepPurple,
      'tulip': Colors.lime.shade700,
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
          if (item['component_type'] == 'bouchon_lame') {
            subtypeStr = ' - ${Localization.translate("مرتبط بـ:", lang)} $sub';
          } else {
            subtypeStr =
                ' - ${Localization.translate("النوع:", lang)} ${sub == 'extruded' ? Localization.translate('إكسترودي', lang) : Localization.translate('عادي', lang)}';
          }
        }

        String unitAr = item['unit'] == 'bar'
            ? Localization.translate('بالبارة', lang)
            : Localization.translate('بالقطعة', lang);
        final barLengthM = _readDouble(item['bar_length_m']);
        String barLenStr = (item['unit'] == 'bar' && barLengthM > 0)
            ? ' - ${Localization.translate("طول البارة:", lang)} $barLengthM ${Localization.translate('م', lang)}'
            : '';
        final mVal = item['measurement']?.toString().trim();
        String measStr = '';
        if (mVal != null && mVal.isNotEmpty && mVal.toLowerCase() != 'null') {
          if (item['component_type'] == 'motor') {
            measStr =
                ' - ${Localization.translate("قياس المحرك:", lang)} $mVal';
          } else if (item['component_type'] == 'blade') {
            measStr =
                ' - ${Localization.translate("ارتفاع الشفرة:", lang)} $mVal ${Localization.translate("مم", lang)}';
          } else {
            measStr = ' - ${Localization.translate("القياس:", lang)} $mVal';
          }
        }

        final trackMeasurement = item['track_measurement']?.toString().trim();
        final trackMeasurementStr =
            item['component_type'] == 'blade' &&
                trackMeasurement != null &&
                trackMeasurement.isNotEmpty &&
                trackMeasurement.toLowerCase() != 'null'
            ? ' - ${Localization.translate("قياس السكة المطابق:", lang)} $trackMeasurement ${Localization.translate("مم", lang)}'
            : '';

        final dVal = item['motor_diameter']?.toString().trim();
        String diamStr = '';
        if (item['component_type'] == 'motor' &&
            dVal != null &&
            dVal.isNotEmpty &&
            dVal.toLowerCase() != 'null') {
          diamStr = ' - ${Localization.translate("قطر المحرك:", lang)} $dVal';
        }

        final emergencyCrankStr =
            item['component_type'] == 'motor' &&
                _isEnabledFlag(item['motor_has_emergency_crank'])
            ? ' - ${Localization.translate("مانيفيل احتياطي", lang)}: ${Localization.translate("نعم", lang)}'
            : '';

        final capTh = _readDouble(item['cap_thickness']);
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
                '${Localization.translate("الوحدة:", lang)} $unitAr$subtypeStr$barLenStr$measStr$trackMeasurementStr$diamStr$emergencyCrankStr$capStr',
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
                              final itemId = _readInt(item['id']);
                              if (itemId == null) return;
                              await widget.db.restoreShutterComponent(itemId);
                              if (mounted) unawaited(_loadItems());
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
      floatingActionButton: isUserAdmin
          ? FloatingActionButton(
              onPressed: _showAddDialog,
              child: Icon(Icons.add),
            )
          : null,
    );
  }
}
