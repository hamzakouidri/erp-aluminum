import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../sql_database.dart'; // تأكد من مسار ملف قاعدة البيانات
import 'package:database_data/settings/localization.dart';
import 'package:database_data/settings/app_settings.dart';
import 'package:database_data/widgets/section_image.dart';
import 'package:provider/provider.dart';

class CatalogManagerScreen extends StatefulWidget {
  final SqlDatabase db; // نمرر قاعدة البيانات للشاشة

  const CatalogManagerScreen({super.key, required this.db});

  @override
  State<CatalogManagerScreen> createState() => _CatalogManagerScreenState();
}

class _CatalogManagerScreenState extends State<CatalogManagerScreen> {
  Future<void> _confirmDelete(
    String title,
    String content,
    VoidCallback onConfirm,
  ) async {
    return showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          'تأكيد الحذف',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red),
        ),
        content: Text(
          'سيتم أرشفة هذا العنصر (إخفاؤه) ولن يتم حذفه نهائياً حفاظاً على سلامة بيانات المخزون والفواتير السابقة المرتبطة به.',
          style: TextStyle(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              Localization.translate(
                'إلغاء',
                Provider.of<AppSettingsProvider>(
                  context,
                  listen: false,
                ).language,
              ),
              style: TextStyle(color: Colors.grey),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              Navigator.pop(ctx);
              onConfirm();
            },
            child: Text(
              'موافق، قم بالأرشفة',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  List<Map<String, dynamic>> _profiles = [];
  List<Map<String, dynamic>> _currentSeries = [];
  List<Map<String, dynamic>> _currentSections = [];

  int? _selectedProfileId;
  int? _selectedSeriesId;

  int? _readInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  bool _readFlag(dynamic value, {bool fallback = false}) {
    if (value == null) return fallback;
    if (value is bool) return value;
    if (value is num) return value != 0;
    final text = value.toString().trim().toLowerCase();
    if (text.isEmpty) return fallback;
    return text == '1' || text == 'true' || text == 'yes' || text == 'oui';
  }

  @override
  void initState() {
    super.initState();
    _loadProfiles();
  }

  // ==========================================
  // --- دوال جلب البيانات ---
  // ==========================================

  Future<void> _loadProfiles() async {
    final profiles = await widget.db.readAllProfiles();
    setState(() {
      _profiles = profiles;
      _selectedProfileId = null;
      _selectedSeriesId = null;
      _currentSeries = [];
      _currentSections = [];
    });
  }

  Future<void> _loadSeries(int profileId) async {
    final series = await widget.db.readAllSeriesByProfile(profileId);
    setState(() {
      _selectedProfileId = profileId;
      _currentSeries = series;
      _selectedSeriesId = null;
      _currentSections = [];
    });
  }

  Future<void> _loadSections(int seriesId) async {
    final sections = await widget.db.readSectionsBySeries(seriesId);
    setState(() {
      _selectedSeriesId = seriesId;
      _currentSections = sections;
    });
  }

  // ==========================================
  // --- دوال الإضافة (Add Dialogs) ---
  // ==========================================

  void _showAddProfileDialog() {
    final nameCtrl = TextEditingController();
    final defaultBarLengthCtrl = TextEditingController(text: '5.8');
    String selectedType = 'Aluminium';

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setStateDialog) => AlertDialog(
          title: Text(
            Localization.translate(
              'إضافة نظام ألمنيوم جديد',
              Provider.of<AppSettingsProvider>(context).language,
            ),
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: InputDecoration(
                  labelText: Localization.translate(
                    'اسم المقطع (مثال: TPR)',
                    Provider.of<AppSettingsProvider>(context).language,
                  ),
                ),
              ),
              SizedBox(height: 10),
              TextField(
                controller: defaultBarLengthCtrl,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: Localization.translate(
                    'طول العود الافتراضي (متر)',
                    Provider.of<AppSettingsProvider>(context).language,
                  ),
                ),
              ),
              SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: selectedType,
                items: ['Aluminium', 'PVC'].map((String value) {
                  return DropdownMenuItem<String>(
                    value: value,
                    child: Text(value),
                  );
                }).toList(),
                onChanged: (newValue) {
                  setStateDialog(() {
                    selectedType = newValue!;
                  });
                },
                decoration: InputDecoration(
                  labelText: Localization.translate(
                    'النوع',
                    Provider.of<AppSettingsProvider>(context).language,
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
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
                  double defaultBarLength =
                      double.tryParse(defaultBarLengthCtrl.text) ?? 5.8;
                  await widget.db.insertProfile(
                    nameCtrl.text,
                    selectedType,
                    defaultBarLength: defaultBarLength,
                  );
                  _loadProfiles();
                  if (context.mounted) Navigator.pop(dialogContext);
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
        ),
      ),
    );
  }

  void _showEditSeriesDialog(Map<String, dynamic> series) {
    final nameCtrl = TextEditingController(
      text: series['name']?.toString() ?? '',
    );
    String selectedType = series['type']?.toString() ?? 'Frappe';
    bool hasThreePieceSash = (series['has_three_piece_sash'] ?? 0) == 1;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: Text(
              Localization.translate(
                'تعديل السلسلة',
                Provider.of<AppSettingsProvider>(context).language,
              ),
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: InputDecoration(
                    labelText: 'اسم السلسلة (مثال: سلسلة 45)',
                  ),
                ),
                SizedBox(height: 10),
                DropdownButton<String>(
                  isExpanded: true,
                  value: selectedType,
                  items: ['Frappe', 'Coulissant', 'Mur Rideau']
                      .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                      .toList(),
                  onChanged: (val) => setDialogState(() {
                    selectedType = val!;
                    if (selectedType != 'Coulissant') {
                      hasThreePieceSash = false;
                    }
                  }),
                ),
                if (selectedType == 'Coulissant') ...[
                  SizedBox(height: 10),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text(
                      'دعم ضلفة 3 قطع (Lateral/Central/Traverse)',
                    ),
                    value: hasThreePieceSash,
                    onChanged: (val) =>
                        setDialogState(() => hasThreePieceSash = val),
                  ),
                ],
              ],
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
                    await widget.db.updateSeries(
                      series['id'],
                      _selectedProfileId!,
                      nameCtrl.text,
                      selectedType,
                      hasThreePieceSash: hasThreePieceSash ? 1 : 0,
                    );
                    _loadSeries(_selectedProfileId!);
                    if (context.mounted) {
                      Navigator.pop(context);
                    }
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

  void _showAddSeriesDialog() {
    if (_selectedProfileId == null) return;
    final nameCtrl = TextEditingController();
    String selectedType = 'Frappe';
    bool hasThreePieceSash = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: Text(
              Localization.translate(
                'إضافة سلسلة جديدة',
                Provider.of<AppSettingsProvider>(context).language,
              ),
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: InputDecoration(
                    labelText: 'اسم السلسلة (مثال: سلسلة 45)',
                  ),
                ),
                SizedBox(height: 10),
                DropdownButton<String>(
                  isExpanded: true,
                  value: selectedType,
                  items: ['Frappe', 'Coulissant', 'Mur Rideau']
                      .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                      .toList(),
                  onChanged: (val) => setDialogState(() {
                    selectedType = val!;
                    if (selectedType != 'Coulissant') {
                      hasThreePieceSash = false;
                    }
                  }),
                ),
                if (selectedType == 'Coulissant') ...[
                  SizedBox(height: 10),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text(
                      'دعم ضلفة 3 قطع (Lateral/Central/Traverse)',
                    ),
                    value: hasThreePieceSash,
                    onChanged: (val) =>
                        setDialogState(() => hasThreePieceSash = val),
                  ),
                ],
              ],
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
                    await widget.db.insertSeries(
                      _selectedProfileId!,
                      nameCtrl.text,
                      selectedType,
                      hasThreePieceSash: hasThreePieceSash ? 1 : 0,
                    );
                    _loadSeries(_selectedProfileId!);
                    if (context.mounted) {
                      Navigator.pop(context);
                    }
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

  void _showCopyFromSeriesDialog() async {
    if (_selectedSeriesId == null) return;

    final profiles = await widget.db.readProfile();
    if (profiles.isEmpty) return;

    int? selectedSourceProfileId = _readInt(profiles.first['id']);
    if (selectedSourceProfileId == null) return;
    List<Map<String, dynamic>> sourceSeriesList = await widget.db
        .readSeriesByProfile(selectedSourceProfileId);
    int? selectedSourceSeriesId = sourceSeriesList.isNotEmpty
        ? _readInt(sourceSeriesList.first['id'])
        : null;

    if (!mounted) return;
    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Text(
                Localization.translate(
                  'نسخ المقاطع من سلسلة أخرى',
                  Provider.of<AppSettingsProvider>(context).language,
                ),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<int>(
                    decoration: InputDecoration(
                      labelText: Localization.translate(
                        'البروفيل',
                        Provider.of<AppSettingsProvider>(context).language,
                      ),
                    ),
                    initialValue: selectedSourceProfileId,
                    items: profiles
                        .map(
                          (p) => DropdownMenuItem<int>(
                            value: _readInt(p['id']),
                            child: Text(p['name'].toString()),
                          ),
                        )
                        .toList(),
                    onChanged: (val) async {
                      if (val != null) {
                        final newSeries = await widget.db.readSeriesByProfile(
                          val,
                        );
                        setState(() {
                          selectedSourceProfileId = val;
                          sourceSeriesList = newSeries;
                          selectedSourceSeriesId = newSeries.isNotEmpty
                              ? _readInt(newSeries.first['id'])
                              : null;
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<int>(
                    decoration: InputDecoration(
                      labelText: Localization.translate(
                        'السلسلة',
                        Provider.of<AppSettingsProvider>(context).language,
                      ),
                    ),
                    initialValue: selectedSourceSeriesId,
                    items: sourceSeriesList
                        .map(
                          (s) => DropdownMenuItem<int>(
                            value: _readInt(s['id']),
                            child: Text(s['name'].toString()),
                          ),
                        )
                        .toList(),
                    onChanged: (val) {
                      setState(() {
                        selectedSourceSeriesId = val;
                      });
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(
                    Localization.translate(
                      'إلغاء',
                      Provider.of<AppSettingsProvider>(context).language,
                    ),
                  ),
                ),
                ElevatedButton(
                  onPressed: selectedSourceSeriesId == null
                      ? null
                      : () async {
                          Navigator.pop(context);
                          final sourceSections = await widget.db
                              .readSectionsBySeries(selectedSourceSeriesId!);
                          for (var sec in sourceSections) {
                            await widget.db.insertSection(
                              seriesId: _selectedSeriesId!,
                              code: sec['code'].toString(),
                              name: sec['name'].toString(),
                              type: sec['type'].toString(),
                              thickness:
                                  (sec['thickness'] as num?)?.toDouble() ?? 0.0,
                              glassDeduction:
                                  (sec['glass_deduction'] as num?)
                                      ?.toDouble() ??
                                  0.0,
                              weightPerMeter:
                                  (sec['weight_per_meter'] as num?)
                                      ?.toDouble() ??
                                  0.0,
                              couvreJointWidth:
                                  (sec['couvre_joint_width'] as num?)
                                      ?.toDouble() ??
                                  0.0,
                              couvreJointThickness:
                                  (sec['couvre_joint_thickness'] as num?)
                                      ?.toDouble() ??
                                  0.0,
                              cuttingDeduction:
                                  (sec['cutting_deduction'] as num?)
                                      ?.toDouble() ??
                                  0.0,
                              visibleWidth:
                                  (sec['visible_width'] as num?)?.toDouble() ??
                                  0.0,
                              visibleWidth2:
                                  (sec['visible_width_2'] as num?)
                                      ?.toDouble() ??
                                  0.0,
                              sashOverlap:
                                  (sec['sash_overlap'] as num?)?.toDouble() ??
                                  0.0,
                              barLength:
                                  (sec['bar_length'] as num?)?.toDouble() ??
                                  5.8,
                              imagePath: sec['image_path']?.toString(),
                              isFrame:
                                  (sec['is_frame'] as num?)?.toInt() ??
                                  (sec['type'] == 'frame' ? 1 : 0),
                              isSash:
                                  (sec['is_sash'] as num?)?.toInt() ??
                                  (sec['type'].toString().startsWith('sash')
                                      ? 1
                                      : 0),
                              isMullion:
                                  (sec['is_mullion'] as num?)?.toInt() ??
                                  (sec['type'] == 'mullion' ? 1 : 0),
                            );
                          }
                          _loadSections(_selectedSeriesId!);
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  Localization.translate(
                                    'تم النسخ',
                                    Provider.of<AppSettingsProvider>(
                                      context,
                                    ).language,
                                  ),
                                ),
                              ),
                            );
                          }
                        },
                  child: Text(
                    Localization.translate(
                      'نسخ',
                      Provider.of<AppSettingsProvider>(context).language,
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showAddSectionDialog() {
    if (_selectedSeriesId == null) return;
    String seriesType = _currentSeries
        .firstWhere(
          (s) => s['id'] == _selectedSeriesId,
          orElse: () => {'type': ''},
        )['type']
        .toString();
    String seriesName = _currentSeries
        .firstWhere(
          (s) => s['id'] == _selectedSeriesId,
          orElse: () => {'name': ''},
        )['name']
        .toString()
        .toUpperCase();
    bool isSlidingSashSubtypeAllowed =
        (seriesType == 'Coulissant' ||
            seriesType == 'منزلق' ||
            seriesType == 'جرار') &&
        (seriesName.contains('TPR') || seriesName.contains('HPS'));
    String profileType = _profiles
        .firstWhere(
          (p) => p['id'] == _selectedProfileId,
          orElse: () => {'type': ''},
        )['type']
        .toString();

    final codeCtrl = TextEditingController();
    final nameCtrl = TextEditingController();
    final barLengthCtrl = TextEditingController(text: '5.8');
    final glassDedCtrl = TextEditingController();
    bool hasThreePieceSash =
        (_currentSeries.firstWhere(
              (s) => s['id'] == _selectedSeriesId,
              orElse: () => {},
            )['has_three_piece_sash'] ??
            0) ==
        1;
    final weightCtrl = TextEditingController();
    final couvreJointWidthCtrl = TextEditingController();
    final couvreJointThicknessCtrl = TextEditingController();
    final cuttingDedCtrl = TextEditingController();
    final visibleWidthCtrl = TextEditingController();
    final visibleWidth2Ctrl = TextEditingController();
    final sashOverlapCtrl = TextEditingController();
    final maxGlassThicknessCtrl = TextEditingController();
    int? selectedParcloseDoubleId;
    String selectedType = 'frame';
    String displayedType = 'frame';
    String sashSubtype = 'sash_lateral';
    String? selectedImagePath;
    // `type` remains the primary/legacy type.  These three flags are the
    // independent roles used by the mixed drawing system.
    bool isFrameRole = true;
    bool isSashRole = false;
    bool isMullionRole = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: Text(
              Localization.translate(
                'إضافة مقطع جديد',
                Provider.of<AppSettingsProvider>(context).language,
              ),
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(height: 8),
                  TextField(
                    controller: codeCtrl,
                    decoration: InputDecoration(
                      labelText: 'الكود التجاري (مثال: P400)',
                    ),
                  ),
                  SizedBox(height: 12),
                  TextField(
                    controller: nameCtrl,
                    decoration: InputDecoration(
                      labelText: 'اسم المقطع (مثال: حلق 45)',
                    ),
                  ),
                  SizedBox(height: 12),
                  DropdownButton<String>(
                    isExpanded: true,
                    value: displayedType,
                    items: [
                      DropdownMenuItem(
                        value: 'frame',
                        child: Text(
                          Localization.translate(
                            'حلق خارجي (Frame)',
                            Provider.of<AppSettingsProvider>(context).language,
                          ),
                        ),
                      ),
                      DropdownMenuItem(
                        value: 'sash',
                        child: Text(
                          Localization.translate(
                            'ضلفة (Sash)',
                            Provider.of<AppSettingsProvider>(context).language,
                          ),
                        ),
                      ),
                      DropdownMenuItem(
                        value: 'mullion',
                        child: Text(
                          Localization.translate(
                            'تيار / تقسيم (Mullion)',
                            Provider.of<AppSettingsProvider>(context).language,
                          ),
                        ),
                      ),
                      if (seriesType != 'Coulissant' &&
                          seriesType != 'منزلق' &&
                          seriesType != 'جرار') ...[
                        DropdownMenuItem(
                          value: 'plinthe',
                          child: Text(
                            Localization.translate(
                              'بلانت (Plinthe)',
                              Provider.of<AppSettingsProvider>(
                                context,
                              ).language,
                            ),
                          ),
                        ),
                      ],
                      DropdownMenuItem(
                        value: 'parclose',
                        child: Text(
                          Localization.translate(
                            'باغيت (Parclose)',
                            Provider.of<AppSettingsProvider>(context).language,
                          ),
                        ),
                      ),
                      DropdownMenuItem(
                        value: 'side_cover',
                        child: Text('غطاء جانبي / Couvre-joint'),
                      ),
                      DropdownMenuItem(
                        value: 'bardage',
                        child: Text('بارداش (Bardage Profile)'),
                      ),
                      DropdownMenuItem(
                        value: 'panneau',
                        child: Text('بانو / برداج (قديم)'),
                      ),
                      if (seriesType != 'Coulissant' &&
                          seriesType != 'منزلق' &&
                          seriesType != 'جرار') ...[
                        DropdownMenuItem(
                          value: 'batmo',
                          child: Text('باتمو (Batmo)'),
                        ),
                        DropdownMenuItem(
                          value: 'bouchon_batmo',
                          child: Text('غطاء باتمو (Bouchon Batmo)'),
                        ),
                      ],
                      if (seriesType == 'Coulissant' ||
                          seriesType == 'منزلق' ||
                          seriesType == 'جرار') ...[
                        DropdownMenuItem(
                          value: 'rail',
                          child: Text('ري / سكة (Rail)'),
                        ),
                      ],
                      if (profileType == 'PVC')
                        DropdownMenuItem(
                          value: 'renfort',
                          child: Text('حديد دعم (Renfort)'),
                        ),
                    ],
                    onChanged: (val) {
                      setDialogState(() {
                        displayedType = val!;
                        // Choosing a primary type gives sensible defaults.
                        // The user may then tick additional roles below.
                        isFrameRole = val == 'frame';
                        isSashRole = val == 'sash';
                        isMullionRole = val == 'mullion';
                        final bool isTprHps =
                            seriesName.contains('TPR') ||
                            seriesName.contains('HPS');
                        if (displayedType == 'sash' &&
                            (seriesType == 'Coulissant' ||
                                seriesType == 'منزلق' ||
                                seriesType == 'جرار') &&
                            isTprHps) {
                          selectedType = sashSubtype;
                        } else {
                          selectedType = val;
                        }
                      });
                    },
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'وظائف المقطع في الرسم (يمكن اختيار أكثر من وظيفة)',
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('يُستعمل كإطار (Frame)'),
                    value: isFrameRole,
                    onChanged: (value) =>
                        setDialogState(() => isFrameRole = value ?? false),
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('يُستعمل كظلفة (Sash)'),
                    value: isSashRole,
                    onChanged: (value) =>
                        setDialogState(() => isSashRole = value ?? false),
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('يُستعمل كتقسيم (Mullion)'),
                    value: isMullionRole,
                    onChanged: (value) =>
                        setDialogState(() => isMullionRole = value ?? false),
                  ),
                  if (displayedType == 'sash' &&
                      (seriesType == 'Coulissant' ||
                          seriesType == 'منزلق' ||
                          seriesType == 'جرار') &&
                      (seriesName.contains('TPR') ||
                          seriesName.contains('HPS'))) ...[
                    SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value:
                          [
                            'sash_lateral',
                            'sash_central',
                            'sash_traverse',
                          ].contains(selectedType)
                          ? selectedType
                          : 'sash_lateral',
                      items: const [
                        DropdownMenuItem(
                          value: 'sash_lateral',
                          child: Text('Montant Lateral'),
                        ),
                        DropdownMenuItem(
                          value: 'sash_central',
                          child: Text(' Montant Central'),
                        ),
                        DropdownMenuItem(
                          value: 'sash_traverse',
                          child: Text(' Traverse Haut et Bas'),
                        ),
                      ],
                      onChanged: (val) {
                        setDialogState(() {
                          sashSubtype = val!;
                          selectedType = val!;
                        });
                      },
                      decoration: const InputDecoration(
                        labelText: 'نوع الضلفة المنزلقة / Sash Sub-type',
                      ),
                    ),
                  ],
                  SizedBox(height: 12),
                  if (selectedType != 'bouchon_batmo') ...[
                    TextField(
                      controller: barLengthCtrl,
                      keyboardType: TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: 'طول البار (متر) / Bar Length (m)',
                      ),
                    ),
                    SizedBox(height: 12),
                  ],
                  if (selectedType != 'batmo' &&
                      selectedType != 'bouchon_batmo' &&
                      selectedType != 'renfort' &&
                      selectedType != 'side_cover' &&
                      selectedType != 'chicane' &&
                      selectedType != 'panneau' &&
                      selectedType != 'bardage' &&
                      !(selectedType == 'frame' &&
                          (seriesType == 'Coulissant' ||
                              seriesType == 'منزلق' ||
                              seriesType == 'جرار'))) ...[
                    TextField(
                      controller: glassDedCtrl,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: 'ركوب الزجاج / Glass Deduction (mm)',
                      ),
                    ),
                    SizedBox(height: 12),
                  ],
                  TextField(
                    controller: weightCtrl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'الوزن للمتر (Kg/m)',
                    ),
                  ),
                  SizedBox(height: 12),
                  if (selectedType == 'frame' ||
                      selectedType == 'side_cover') ...[
                    TextField(
                      controller: couvreJointWidthCtrl,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: selectedType == 'side_cover'
                            ? 'عرض الكوفرجوا (الاتجاه الأول) (mm)'
                            : 'عرض الكوفرجوا / Couvre-joint Width (mm)',
                      ),
                    ),
                    SizedBox(height: 12),
                    TextField(
                      controller: couvreJointThicknessCtrl,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText:
                            'سمك الكوفرجوا / Couvre-joint Thickness (mm)',
                      ),
                    ),
                    SizedBox(height: 12),
                  ],
                  if (selectedType == 'batmo') ...[
                    TextField(
                      controller: cuttingDedCtrl,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText:
                            'خصم التقطيع الإضافي / Cutting Deduction (mm)',
                      ),
                    ),
                    SizedBox(height: 12),
                  ],
                  if (selectedType.startsWith('sash') ||
                      selectedType == 'frame' ||
                      selectedType == 'mullion' ||
                      selectedType == 'side_cover' ||
                      selectedType == 'bardage' ||
                      selectedType == 'plinthe') ...[
                    TextField(
                      controller: visibleWidthCtrl,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: selectedType == 'side_cover'
                            ? 'العرض الظاهر (الاتجاه الثاني) (mm)'
                            : 'العرض الظاهر / Visible Width (mm)',
                      ),
                    ),
                    SizedBox(height: 12),
                  ],
                  if (selectedType.startsWith('sash')) ...[
                    TextField(
                      controller: sashOverlapCtrl,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText:
                            'تداخل الضلفة لكل جهة / Recouvrement par côté (mm) (مثال: 10)',
                      ),
                    ),
                    SizedBox(height: 12),
                  ],
                  if (selectedType == 'parclose') ...[
                    TextField(
                      controller: maxGlassThicknessCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText:
                            'السمك الأقصى للزجاج / Max Glass Thickness (mm)',
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<int>(
                      decoration: const InputDecoration(
                        labelText:
                            'البيركلوز المزدوج المرتبط / Linked Double Parclose',
                      ),
                      value: selectedParcloseDoubleId,
                      items: _currentSections
                          .where((s) => s['type'] == 'parclose')
                          .map(
                            (s) => DropdownMenuItem<int>(
                              value: _readInt(s['id']),
                              child: Text('${s['code']} - ${s['name']}'),
                            ),
                          )
                          .toList(),
                      onChanged: (val) {
                        setDialogState(() {
                          selectedParcloseDoubleId = val;
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                  ],
                  SizedBox(height: 10),
                  ElevatedButton.icon(
                    onPressed: () async {
                      final picker = ImagePicker();
                      final pickedFile = await picker.pickImage(
                        source: ImageSource.gallery,
                        imageQuality: 50, // ضغط الصورة لتقليل حجمها
                      );
                      if (pickedFile != null) {
                        setDialogState(() {
                          selectedImagePath = pickedFile.path;
                        });
                      }
                    },
                    icon: Icon(Icons.image),
                    label: Text(
                      selectedImagePath == null
                          ? 'اختر صورة المقطع (اختياري)'
                          : 'تم اختيار الصورة',
                    ),
                  ),
                  if (selectedImagePath != null)
                    Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Image.file(
                        File(selectedImagePath!),
                        height: 100,
                        width: 100,
                        fit: BoxFit.cover,
                      ),
                    ),
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
                style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                onPressed: () async {
                  if (codeCtrl.text.isNotEmpty &&
                      (selectedType == 'parclose' ||
                          selectedType == 'batmo' ||
                          selectedType == 'bouchon_batmo' ||
                          selectedType == 'renfort' ||
                          barLengthCtrl.text.isNotEmpty)) {
                    await widget.db.insertSection(
                      seriesId: _selectedSeriesId!,
                      code: codeCtrl.text,
                      name: nameCtrl.text,
                      type: selectedType,
                      thickness: double.tryParse(visibleWidthCtrl.text) ?? 45.0,
                      barLength: double.tryParse(barLengthCtrl.text) ?? 5.8,
                      glassDeduction:
                          (selectedType == 'batmo' ||
                              selectedType == 'bouchon_batmo')
                          ? 0.0
                          : (double.tryParse(glassDedCtrl.text) ?? 0.0),
                      weightPerMeter: double.tryParse(weightCtrl.text) ?? 0.0,
                      couvreJointWidth:
                          double.tryParse(couvreJointWidthCtrl.text) ?? 0.0,
                      couvreJointThickness:
                          double.tryParse(couvreJointThicknessCtrl.text) ?? 0.0,
                      cuttingDeduction:
                          double.tryParse(cuttingDedCtrl.text) ?? 0.0,
                      visibleWidth:
                          double.tryParse(visibleWidthCtrl.text) ?? 0.0,
                      visibleWidth2:
                          double.tryParse(visibleWidth2Ctrl.text) ?? 0.0,
                      sashOverlap: double.tryParse(sashOverlapCtrl.text) ?? 0.0,
                      imagePath: selectedImagePath,
                      maxGlassThickness:
                          double.tryParse(maxGlassThicknessCtrl.text) ?? 0.0,
                      linkedParcloseDoubleId: selectedParcloseDoubleId,
                      isFrame: isFrameRole ? 1 : 0,
                      isSash: isSashRole ? 1 : 0,
                      isMullion: isMullionRole ? 1 : 0,
                    );
                    _loadSections(_selectedSeriesId!);
                    if (context.mounted) {
                      Navigator.pop(context);
                    }
                  }
                },
                child: Text(
                  Localization.translate(
                    'إضافة المقطع',
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

  void _showEditSectionDialog(Map<String, dynamic> section) {
    String seriesType = _currentSeries
        .firstWhere(
          (s) => s['id'] == _selectedSeriesId,
          orElse: () => {'type': ''},
        )['type']
        .toString();
    String seriesName = _currentSeries
        .firstWhere(
          (s) => s['id'] == _selectedSeriesId,
          orElse: () => {'name': ''},
        )['name']
        .toString()
        .toUpperCase();
    final codeCtrl = TextEditingController(
      text: section['code']?.toString() ?? '',
    );
    final nameCtrl = TextEditingController(
      text: section['name']?.toString() ?? '',
    );
    final barLengthCtrl = TextEditingController(
      text: section['bar_length']?.toString() ?? '5.8',
    );
    final glassDedCtrl = TextEditingController(
      text: section['glass_deduction']?.toString() ?? '',
    );
    final weightCtrl = TextEditingController(
      text: section['weight_per_meter']?.toString() ?? '',
    );
    final couvreJointWidthCtrl = TextEditingController(
      text: section['couvre_joint_width']?.toString() ?? '',
    );
    final couvreJointThicknessCtrl = TextEditingController(
      text: section['couvre_joint_thickness']?.toString() ?? '',
    );
    final cuttingDedCtrl = TextEditingController(
      text: section['cutting_deduction']?.toString() ?? '',
    );
    final visibleWidthCtrl = TextEditingController(
      text: section['visible_width']?.toString() ?? '',
    );
    final visibleWidth2Ctrl = TextEditingController(
      text: section['visible_width_2']?.toString() ?? '',
    );
    final sashOverlapCtrl = TextEditingController(
      text: section['sash_overlap']?.toString() ?? '',
    );
    final renfortDeductionCtrl = TextEditingController(
      text: section['renfort_deduction']?.toString() ?? '140',
    );
    final maxGlassThicknessCtrl = TextEditingController(
      text: section['max_glass_thickness']?.toString() ?? '',
    );
    bool allowsSideCoverVal = _readFlag(
      section['allows_side_cover'],
      fallback: true,
    );
    int? selectedParcloseDoubleId = _readInt(
      section['linked_parclose_double_id'],
    );
    String? selectedImagePath = section['image_path']?.toString();
    String selectedType = section['type']?.toString() ?? 'frame';
    String displayedType = selectedType;
    if ([
      'sash_lateral',
      'sash_central',
      'sash_traverse',
    ].contains(displayedType)) {
      displayedType = 'sash';
    }
    bool readRole(String key, bool fallback) {
      final value = section[key];
      if (value == null) return fallback;
      if (value is bool) return value;
      if (value is num) return value != 0;
      final text = value.toString().trim().toLowerCase();
      return text == '1' || text == 'true' || text == 'yes';
    }

    bool isFrameRole = readRole('is_frame', selectedType == 'frame');
    bool isSashRole = readRole('is_sash', selectedType.startsWith('sash'));
    bool isMullionRole = readRole('is_mullion', selectedType == 'mullion');
    String sashSubtype =
        ['sash_lateral', 'sash_central', 'sash_traverse'].contains(selectedType)
        ? selectedType
        : 'sash_lateral';
    int? selectedRenfortId = _readInt(section['linked_renfort_id']);
    String profileType = _profiles
        .firstWhere(
          (p) => p['id'] == _selectedProfileId,
          orElse: () => {'type': ''},
        )['type']
        .toString();
    List<Map<String, dynamic>> renforts = _currentSections
        .where((s) => s['type'] == 'renfort' && s['id'] != section['id'])
        .toList();

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: Text(
              Localization.translate(
                'تعديل المقطع',
                Provider.of<AppSettingsProvider>(context).language,
              ),
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(height: 8),
                  TextField(
                    controller: codeCtrl,
                    decoration: InputDecoration(
                      labelText: 'الكود التجاري (مثال: P400)',
                    ),
                  ),
                  SizedBox(height: 12),
                  TextField(
                    controller: nameCtrl,
                    decoration: InputDecoration(
                      labelText: 'اسم المقطع (مثال: حلق 45)',
                    ),
                  ),
                  SizedBox(height: 12),
                  DropdownButton<String>(
                    isExpanded: true,
                    value: displayedType,
                    items: [
                      DropdownMenuItem(
                        value: 'frame',
                        child: Text(
                          Localization.translate(
                            'حلق خارجي (Frame)',
                            Provider.of<AppSettingsProvider>(context).language,
                          ),
                        ),
                      ),
                      DropdownMenuItem(
                        value: 'sash',
                        child: Text(
                          Localization.translate(
                            'ضلفة (Sash)',
                            Provider.of<AppSettingsProvider>(context).language,
                          ),
                        ),
                      ),
                      DropdownMenuItem(
                        value: 'mullion',
                        child: Text(
                          Localization.translate(
                            'تيار / تقسيم (Mullion)',
                            Provider.of<AppSettingsProvider>(context).language,
                          ),
                        ),
                      ),
                      if (seriesType != 'Coulissant' &&
                          seriesType != 'منزلق' &&
                          seriesType != 'جرار') ...[
                        DropdownMenuItem(
                          value: 'plinthe',
                          child: Text(
                            Localization.translate(
                              'بلانت (Plinthe)',
                              Provider.of<AppSettingsProvider>(
                                context,
                              ).language,
                            ),
                          ),
                        ),
                      ],
                      DropdownMenuItem(
                        value: 'parclose',
                        child: Text(
                          Localization.translate(
                            'باغيت (Parclose)',
                            Provider.of<AppSettingsProvider>(context).language,
                          ),
                        ),
                      ),
                      DropdownMenuItem(
                        value: 'side_cover',
                        child: Text('غطاء جانبي / Couvre-joint'),
                      ),
                      DropdownMenuItem(
                        value: 'bardage',
                        child: Text('بارداش (Bardage Profile)'),
                      ),
                      DropdownMenuItem(
                        value: 'panneau',
                        child: Text('بانو / برداج (قديم)'),
                      ),
                      if (seriesType != 'Coulissant' &&
                          seriesType != 'منزلق' &&
                          seriesType != 'جرار') ...[
                        DropdownMenuItem(
                          value: 'batmo',
                          child: Text('باتمو (Batmo)'),
                        ),
                        DropdownMenuItem(
                          value: 'bouchon_batmo',
                          child: Text('غطاء باتمو (Bouchon Batmo)'),
                        ),
                      ],
                      if (seriesType == 'Coulissant' ||
                          seriesType == 'منزلق' ||
                          seriesType == 'جرار') ...[
                        DropdownMenuItem(
                          value: 'rail',
                          child: Text('ري / سكة (Rail)'),
                        ),
                      ],
                      if (profileType == 'PVC')
                        DropdownMenuItem(
                          value: 'renfort',
                          child: Text('حديد دعم (Renfort)'),
                        ),
                    ],
                    onChanged: (val) {
                      setDialogState(() {
                        displayedType = val!;
                        // Reset only the suggested roles when changing the
                        // primary type. The user can choose several roles
                        // immediately below.
                        isFrameRole = val == 'frame';
                        isSashRole = val == 'sash';
                        isMullionRole = val == 'mullion';
                        final bool isTprHps =
                            seriesName.contains('TPR') ||
                            seriesName.contains('HPS');
                        if (displayedType == 'sash' &&
                            (seriesType == 'Coulissant' ||
                                seriesType == 'منزلق' ||
                                seriesType == 'جرار') &&
                            isTprHps) {
                          selectedType = sashSubtype;
                        } else {
                          selectedType = val!;
                        }
                      });
                    },
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'وظائف المقطع في الرسم (يمكن اختيار أكثر من وظيفة)',
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('يُستعمل كإطار (Frame)'),
                    value: isFrameRole,
                    onChanged: (value) =>
                        setDialogState(() => isFrameRole = value ?? false),
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('يُستعمل كظلفة (Sash)'),
                    value: isSashRole,
                    onChanged: (value) =>
                        setDialogState(() => isSashRole = value ?? false),
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('يُستعمل كتقسيم (Mullion)'),
                    value: isMullionRole,
                    onChanged: (value) =>
                        setDialogState(() => isMullionRole = value ?? false),
                  ),
                  if (displayedType == 'sash' &&
                      (seriesType == 'Coulissant' ||
                          seriesType == 'منزلق' ||
                          seriesType == 'جرار') &&
                      (seriesName.contains('TPR') ||
                          seriesName.contains('HPS'))) ...[
                    SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value:
                          [
                            'sash_lateral',
                            'sash_central',
                            'sash_traverse',
                          ].contains(selectedType)
                          ? selectedType
                          : 'sash_lateral',
                      items: const [
                        DropdownMenuItem(
                          value: 'sash_lateral',
                          child: Text('Montant Lateral'),
                        ),
                        DropdownMenuItem(
                          value: 'sash_central',
                          child: Text('Montant Central'),
                        ),
                        DropdownMenuItem(
                          value: 'sash_traverse',
                          child: Text('Traverse Haut et Bas'),
                        ),
                      ],
                      onChanged: (val) {
                        setDialogState(() {
                          sashSubtype = val!;
                          selectedType = val!;
                        });
                      },
                      decoration: const InputDecoration(
                        labelText: 'نوع الضلفة المنزلقة / Sash Sub-type',
                      ),
                    ),
                  ],
                  SizedBox(height: 12),
                  if (selectedType != 'bouchon_batmo') ...[
                    TextField(
                      controller: barLengthCtrl,
                      keyboardType: TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: 'طول البار (متر) / Bar Length (m)',
                      ),
                    ),
                    SizedBox(height: 12),
                  ],
                  if (selectedType != 'batmo' &&
                      selectedType != 'bouchon_batmo' &&
                      selectedType != 'renfort' &&
                      selectedType != 'side_cover' &&
                      selectedType != 'chicane' &&
                      selectedType != 'panneau' &&
                      selectedType != 'bardage' &&
                      !(selectedType == 'frame' &&
                          (seriesType == 'Coulissant' ||
                              seriesType == 'منزلق' ||
                              seriesType == 'جرار'))) ...[
                    TextField(
                      controller: glassDedCtrl,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: 'ركوب الزجاج / Glass Deduction (mm)',
                      ),
                    ),
                    SizedBox(height: 12),
                  ],
                  TextField(
                    controller: weightCtrl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'الوزن للمتر (Kg/m)',
                    ),
                  ),
                  SizedBox(height: 12),
                  if (selectedType == 'frame' ||
                      selectedType == 'side_cover') ...[
                    TextField(
                      controller: couvreJointWidthCtrl,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: selectedType == 'side_cover'
                            ? 'عرض الكوفرجوا (الاتجاه الأول) (mm)'
                            : 'عرض الكوفرجوا / Couvre-joint Width (mm)',
                      ),
                    ),
                    SizedBox(height: 12),
                    TextField(
                      controller: couvreJointThicknessCtrl,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText:
                            'سمك الكوفرجوا / Couvre-joint Thickness (mm)',
                      ),
                    ),
                    if (selectedType == 'frame' &&
                        (double.tryParse(couvreJointWidthCtrl.text) ?? 0.0) ==
                            0) ...[
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text(
                          'يسمح بركوب غطاء جانبي منفصل (Couvre-joint)',
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        subtitle: const Text(
                          'قم بإلغاء التحديد إذا كان هذا الإطار لا يركب عليه غطاء جانبي منفصل مطلقاً',
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 11,
                            color: Colors.grey,
                          ),
                        ),
                        value: allowsSideCoverVal,
                        onChanged: (val) {
                          setDialogState(() {
                            allowsSideCoverVal = val ?? true;
                          });
                        },
                      ),
                      const SizedBox(height: 12),
                    ],
                  ],
                  if (selectedType == 'batmo') ...[
                    TextField(
                      controller: cuttingDedCtrl,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText:
                            'خصم التقطيع الإضافي / Cutting Deduction (mm)',
                      ),
                    ),
                    SizedBox(height: 12),
                  ],
                  if (selectedType.startsWith('sash') ||
                      selectedType == 'frame' ||
                      selectedType == 'mullion' ||
                      selectedType == 'side_cover' ||
                      selectedType == 'bardage' ||
                      selectedType == 'plinthe') ...[
                    TextField(
                      controller: visibleWidthCtrl,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: selectedType == 'side_cover'
                            ? 'العرض الظاهر (الاتجاه الثاني) (mm)'
                            : 'العرض الظاهر / Visible Width (mm)',
                      ),
                    ),
                    SizedBox(height: 12),
                  ],
                  if (selectedType.startsWith('sash')) ...[
                    TextField(
                      controller: sashOverlapCtrl,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText:
                            'تداخل الضلفة لكل جهة / Recouvrement par côté (mm) (مثال: 10)',
                      ),
                    ),
                    SizedBox(height: 12),
                  ],
                  if (selectedType == 'parclose') ...[
                    TextField(
                      controller: maxGlassThicknessCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText:
                            'السمك الأقصى للزجاج / Max Glass Thickness (mm)',
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<int>(
                      decoration: const InputDecoration(
                        labelText:
                            'البيركلوز المزدوج المرتبط / Linked Double Parclose',
                      ),
                      value: selectedParcloseDoubleId,
                      items: _currentSections
                          .where(
                            (s) =>
                                s['type'] == 'parclose' &&
                                s['id'] != section['id'],
                          )
                          .map(
                            (s) => DropdownMenuItem<int>(
                              value: _readInt(s['id']),
                              child: Text('${s['code']} - ${s['name']}'),
                            ),
                          )
                          .toList(),
                      onChanged: (val) {
                        setDialogState(() {
                          selectedParcloseDoubleId = val;
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (profileType == 'PVC' &&
                      (selectedType == 'frame' ||
                          selectedType.startsWith('sash') ||
                          selectedType == 'mullion')) ...[
                    SizedBox(height: 10),
                    DropdownButtonFormField<int>(
                      decoration: InputDecoration(
                        labelText: 'حديد الدعم المرتبط (Renfort)',
                      ),
                      initialValue:
                          renforts.any((r) => r['id'] == selectedRenfortId)
                          ? selectedRenfortId
                          : null,
                      items: renforts
                          .map(
                            (r) => DropdownMenuItem<int>(
                              value: _readInt(r['id']),
                              child: Text(r['name'].toString()),
                            ),
                          )
                          .toList(),
                      onChanged: (val) {
                        setDialogState(() {
                          selectedRenfortId = val;
                        });
                      },
                    ),
                    if (selectedRenfortId != null) ...[
                      SizedBox(height: 10),
                      TextField(
                        controller: renfortDeductionCtrl,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: 'خصم اللحام (mm) (مثال: 140)',
                        ),
                      ),
                    ],
                  ],
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    onPressed: () async {
                      final picker = ImagePicker();
                      final pickedFile = await picker.pickImage(
                        source: ImageSource.gallery,
                        imageQuality: 50,
                      );
                      if (pickedFile != null) {
                        setDialogState(() {
                          selectedImagePath = pickedFile.path;
                        });
                      }
                    },
                    icon: const Icon(Icons.image),
                    label: Text(
                      selectedImagePath == null
                          ? 'اختيار صورة للمقطع (اختياري)'
                          : 'تغيير صورة المقطع',
                    ),
                  ),
                  if (selectedImagePath != null)
                    Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Image.file(
                        File(selectedImagePath!),
                        height: 100,
                        width: 100,
                        fit: BoxFit.cover,
                      ),
                    ),
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
                  if (codeCtrl.text.isNotEmpty &&
                      (selectedType == 'parclose' ||
                          selectedType == 'batmo' ||
                          selectedType == 'bouchon_batmo' ||
                          selectedType == 'renfort' ||
                          barLengthCtrl.text.isNotEmpty)) {
                    try {
                      final sectionId = _readInt(section['id']);
                      if (sectionId == null) return;
                      await widget.db.updateSection(sectionId, {
                        'code': codeCtrl.text,
                        'name': nameCtrl.text,
                        'type': selectedType,
                        'is_frame': isFrameRole ? 1 : 0,
                        'is_sash': isSashRole ? 1 : 0,
                        'is_mullion': isMullionRole ? 1 : 0,
                        'thickness':
                            double.tryParse(visibleWidthCtrl.text) ?? 45.0,
                        'bar_length':
                            double.tryParse(barLengthCtrl.text) ?? 5.8,
                        'glass_deduction':
                            (selectedType == 'batmo' ||
                                selectedType == 'bouchon_batmo' ||
                                selectedType == 'renfort' ||
                                selectedType == 'chicane' ||
                                (selectedType == 'frame' &&
                                    (seriesType == 'Coulissant' ||
                                        seriesType == 'منزلق' ||
                                        seriesType == 'جرار')))
                            ? 0.0
                            : (double.tryParse(glassDedCtrl.text) ?? 0.0),
                        'weight_per_meter':
                            double.tryParse(weightCtrl.text) ?? 0.0,
                        'couvre_joint_width':
                            double.tryParse(couvreJointWidthCtrl.text) ?? 0.0,
                        'couvre_joint_thickness':
                            double.tryParse(couvreJointThicknessCtrl.text) ??
                            0.0,
                        'cutting_deduction':
                            double.tryParse(cuttingDedCtrl.text) ?? 0.0,
                        'visible_width':
                            double.tryParse(visibleWidthCtrl.text) ?? 0.0,
                        'visible_width_2':
                            double.tryParse(visibleWidth2Ctrl.text) ?? 0.0,
                        'sash_overlap':
                            double.tryParse(sashOverlapCtrl.text) ?? 0.0,
                        'linked_renfort_id': selectedRenfortId,
                        'renfort_deduction':
                            double.tryParse(renfortDeductionCtrl.text) ?? 140.0,
                        'image_path': selectedImagePath,
                        'max_glass_thickness':
                            double.tryParse(maxGlassThicknessCtrl.text) ?? 0.0,
                        'linked_parclose_double_id': selectedParcloseDoubleId,
                        'allows_side_cover': allowsSideCoverVal ? 1 : 0,
                      });
                      _loadSections(_selectedSeriesId!);
                      if (context.mounted) {
                        Navigator.pop(context);
                      }
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'خطأ أثناء الحفظ. يرجى إعادة تشغيل التطبيق لتحديث قاعدة البيانات. \n$e',
                            ),
                            backgroundColor: Colors.red,
                          ),
                        );
                      }
                    }
                  }
                },
                child: Text(
                  Localization.translate(
                    'تعديل',
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

  // ==========================================
  // --- دوال التعديل (Edit Dialogs) ---
  // ==========================================

  void _showEditProfileDialog(
    int id,
    String currentName,
    String currentType,
    double currentBarLength,
  ) {
    final nameCtrl = TextEditingController(text: currentName);
    final defaultBarLengthCtrl = TextEditingController(
      text: currentBarLength.toString(),
    );
    String selectedType = (currentType == 'PVC') ? 'PVC' : 'Aluminium';

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setStateDialog) => AlertDialog(
          title: Text(
            Localization.translate(
              'تعديل اسم المقطع',
              Provider.of<AppSettingsProvider>(context).language,
            ),
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: InputDecoration(
                  labelText: Localization.translate(
                    'اسم المقطع الجديد (مثال: TPR)',
                    Provider.of<AppSettingsProvider>(context).language,
                  ),
                ),
              ),
              SizedBox(height: 10),
              TextField(
                controller: defaultBarLengthCtrl,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: Localization.translate(
                    'طول العود الافتراضي (متر)',
                    Provider.of<AppSettingsProvider>(context).language,
                  ),
                ),
              ),
              SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: selectedType,
                items: ['Aluminium', 'PVC'].map((String value) {
                  return DropdownMenuItem<String>(
                    value: value,
                    child: Text(value),
                  );
                }).toList(),
                onChanged: (newValue) {
                  setStateDialog(() {
                    selectedType = newValue!;
                  });
                },
                decoration: InputDecoration(
                  labelText: Localization.translate(
                    'النوع',
                    Provider.of<AppSettingsProvider>(context).language,
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
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
                  double defaultBarLength =
                      double.tryParse(defaultBarLengthCtrl.text) ?? 5.8;
                  await widget.db.updateProfile(
                    id,
                    nameCtrl.text,
                    selectedType,
                    defaultBarLength: defaultBarLength,
                  );
                  _loadProfiles();
                  if (context.mounted) Navigator.pop(dialogContext);
                }
              },
              child: Text(
                Localization.translate(
                  'حفظ التعديل',
                  Provider.of<AppSettingsProvider>(context).language,
                ),
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================
  // --- بناء الواجهة (Build) ---
  // ==========================================

  @override
  Widget build(BuildContext context) {
    final bool isUserAdmin = isAdmin;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          Localization.translate(
            'إدارة الكتالوج (Profiles & Sections)',
            Provider.of<AppSettingsProvider>(context).language,
          ),
        ),
        backgroundColor: Theme.of(context).brightness == Brightness.dark
            ? Theme.of(context).appBarTheme.backgroundColor
            : Colors.blue,
        centerTitle: true,
        actions: [
          if (isUserAdmin)
            IconButton(
              icon: Icon(Icons.copy_all, color: Colors.white),
              tooltip: 'نسخ المقاطع من ProWin إلى باقي السلاسل',
              onPressed: () async {
                bool? confirm = await showDialog(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: Text("تأكيد النسخ"),
                    content: Text(
                      "هل أنت متأكد أنك تريد نسخ مقاطع ProWin 60 و 70 وتطبيقها على باقي بروفيلات الـ PVC والألمنيوم؟",
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: Text("إلغاء"),
                      ),
                      ElevatedButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: Text("نعم، انسخ"),
                      ),
                    ],
                  ),
                );
                if (confirm != true) return;

                try {
                  var database = await widget.db.db;
                  var profiles = await database!.query('Profiles');
                  var prowin = profiles.firstWhere(
                    (p) =>
                        p['name'].toString().toLowerCase().contains('prowin'),
                    orElse: () => {},
                  );
                  if (prowin.isEmpty) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('بروفيل ProWin غير موجود!')),
                      );
                    }
                    return;
                  }

                  final prowinId = _readInt(prowin['id']);
                  if (prowinId == null) return;
                  var prowinSeries = await database.query(
                    'Series',
                    where: 'profile_id = ?',
                    whereArgs: [prowinId],
                  );

                  var prowin60 = prowinSeries.firstWhere(
                    (s) => s['name'].toString() == '60',
                    orElse: () => {},
                  );
                  var prowin70 = prowinSeries.firstWhere(
                    (s) =>
                        s['name'].toString() == '70' ||
                        s['name'].toString() == '72',
                    orElse: () => {},
                  );

                  if (prowin60.isEmpty || prowin70.isEmpty) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'السلسلة 60 أو 70/72 غير موجودة داخل ProWin!',
                          ),
                        ),
                      );
                    }
                    return;
                  }

                  final p60Id = _readInt(prowin60['id']);
                  final p70Id = _readInt(prowin70['id']);
                  if (p60Id == null || p70Id == null) return;

                  var secs60 = await database.query(
                    'Sections',
                    where: 'series_id = ?',
                    whereArgs: [p60Id],
                  );
                  var secs70 = await database.query(
                    'Sections',
                    where: 'series_id = ?',
                    whereArgs: [p70Id],
                  );

                  for (var p in profiles) {
                    if (_readInt(p['id']) == prowinId) continue;
                    var series = await database.query(
                      'Series',
                      where: 'profile_id = ?',
                      whereArgs: [p['id']],
                    );
                    for (var s in series) {
                      final targetSeriesId = _readInt(s['id']);
                      if (targetSeriesId == null) continue;
                      String sName = s['name'].toString();
                      List<Map<String, dynamic>> sourceSecs = [];
                      if (sName == '60') {
                        sourceSecs = secs60;
                      } else if (sName == '60 PM' ||
                          sName == '70' ||
                          sName == '75' ||
                          sName == '72') {
                        sourceSecs = secs70;
                      }

                      if (sourceSecs.isNotEmpty) {
                        // Check if target series already has sections
                        var existingSecs = await database.query(
                          'Sections',
                          where: 'series_id = ?',
                          whereArgs: [targetSeriesId],
                        );
                        if (existingSecs.isEmpty) {
                          for (var sec in sourceSecs) {
                            await widget.db.insertSection(
                              seriesId: targetSeriesId,
                              code: sec['code'].toString(),
                              name: sec['name'].toString(),
                              type: sec['type'].toString(),
                              thickness:
                                  (sec['thickness'] as num?)?.toDouble() ?? 0.0,
                              weightPerMeter:
                                  (sec['weight_per_meter'] as num?)
                                      ?.toDouble() ??
                                  0.0,
                              glassDeduction:
                                  (sec['glass_deduction'] as num?)
                                      ?.toDouble() ??
                                  0.0,
                              couvreJointWidth:
                                  (sec['couvre_joint_width'] as num?)
                                      ?.toDouble() ??
                                  0.0,
                              couvreJointThickness:
                                  (sec['couvre_joint_thickness'] as num?)
                                      ?.toDouble() ??
                                  0.0,
                              cuttingDeduction:
                                  (sec['cutting_deduction'] as num?)
                                      ?.toDouble() ??
                                  0.0,
                              visibleWidth:
                                  (sec['visible_width'] as num?)?.toDouble() ??
                                  0.0,
                              visibleWidth2:
                                  (sec['visible_width_2'] as num?)
                                      ?.toDouble() ??
                                  0.0,
                              sashOverlap:
                                  (sec['sash_overlap'] as num?)?.toDouble() ??
                                  0.0,
                              barLength:
                                  (sec['bar_length'] as num?)?.toDouble() ??
                                  5.8,
                              imagePath: sec['image_path']?.toString(),
                              isFrame:
                                  (sec['is_frame'] as num?)?.toInt() ??
                                  (sec['type'] == 'frame' ? 1 : 0),
                              isSash:
                                  (sec['is_sash'] as num?)?.toInt() ??
                                  (sec['type'].toString().startsWith('sash')
                                      ? 1
                                      : 0),
                              isMullion:
                                  (sec['is_mullion'] as num?)?.toInt() ??
                                  (sec['type'] == 'mullion' ? 1 : 0),
                            );
                          }
                        }
                      }
                    }
                  }
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('تم نسخ المقاطع بنجاح!')),
                    );
                  }
                  _loadProfiles();
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('حدث خطأ أثناء النسخ: $e')),
                    );
                  }
                }
              },
            ),
        ],
      ),
      // 🟢 تغليف بـ SingleChildScrollView لمنع الانضغاط أفقياً
      body: InteractiveViewer(
        panEnabled: true,
        scaleEnabled: true,
        minScale: 0.5,
        maxScale: 3.0,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: 1200, // عرض كافٍ يضمن عدم انضغاط النصوص أفقياً
            child: Row(
              children: [
                // 1. قائمة الأنظمة (Profiles)
                Expanded(
                  flex: 2,
                  child: Container(
                    color: Theme.of(context).brightness == Brightness.dark
                        ? Colors.grey.shade900
                        : Colors.grey.shade100,
                    child: Column(
                      children: [
                        Container(
                          padding: EdgeInsets.all(8),
                          color: Colors.blueGrey,
                          width: double.infinity,
                          child: Text(
                            '1. ${Localization.translate("الأنظمة", Provider.of<AppSettingsProvider>(context).language)} (Profiles)',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        Expanded(
                          child: ListView.builder(
                            itemCount: _profiles.length,
                            itemBuilder: (context, index) {
                              final p = _profiles[index];
                              final isSelected = p['id'] == _selectedProfileId;
                              return InkWell(
                                onTap: () {
                                  final profileId = _readInt(p['id']);
                                  if (profileId != null) {
                                    _loadSeries(profileId);
                                  }
                                },
                                child: Container(
                                  color: isSelected
                                      ? (Theme.of(context).brightness ==
                                                Brightness.dark
                                            ? Colors.blue.shade900.withValues(
                                                alpha: 0.5,
                                              )
                                            : Colors.blue.shade100)
                                      : Colors.transparent,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 8,
                                    horizontal: 14,
                                  ),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(
                                              p['name'].toString(),
                                              style: TextStyle(
                                                fontWeight: isSelected
                                                    ? FontWeight.bold
                                                    : FontWeight.normal,
                                                fontSize: 13,
                                              ),
                                            ),
                                            if (p['type'] != null &&
                                                p['type'].toString().isNotEmpty)
                                              Text(
                                                p['type'].toString(),
                                                style: const TextStyle(
                                                  fontSize: 10,
                                                  color: Colors.grey,
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                      if (isUserAdmin)
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            IconButton(
                                              padding: EdgeInsets.zero,
                                              constraints:
                                                  const BoxConstraints(),
                                              icon: const Icon(
                                                Icons.edit,
                                                color: Colors.blue,
                                                size: 16,
                                              ),
                                              onPressed: () {
                                                final profileId = _readInt(
                                                  p['id'],
                                                );
                                                if (profileId == null) return;
                                                _showEditProfileDialog(
                                                  profileId,
                                                  p['name'],
                                                  p['type'],
                                                  (p['default_bar_length']
                                                              as num?)
                                                          ?.toDouble() ??
                                                      5.8,
                                                );
                                              },
                                            ),
                                            const SizedBox(width: 8),
                                            IconButton(
                                              padding: EdgeInsets.zero,
                                              constraints:
                                                  const BoxConstraints(),
                                              icon: const Icon(
                                                Icons.delete,
                                                color: Colors.red,
                                                size: 16,
                                              ),
                                              onPressed: () => _confirmDelete(
                                                'تأكيد الحذف',
                                                'هل أنت متأكد أنك تريد حذف هذا النظام؟',
                                                () async {
                                                  final profileId = _readInt(
                                                    p['id'],
                                                  );
                                                  if (profileId == null) {
                                                    return;
                                                  }
                                                  await widget.db.deleteProfile(
                                                    profileId,
                                                  );
                                                  _loadProfiles();
                                                },
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
                        if (isUserAdmin)
                          Padding(
                            padding: EdgeInsets.all(8.0),
                            child: ElevatedButton.icon(
                              onPressed: _showAddProfileDialog,
                              icon: Icon(Icons.add),
                              label: Text(
                                Localization.translate(
                                  'نظام جديد',
                                  Provider.of<AppSettingsProvider>(
                                    context,
                                  ).language,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const VerticalDivider(width: 1),

                // 2. قائمة السلاسل (Series)
                Expanded(
                  flex: 2,
                  child: Container(
                    color: Theme.of(context).brightness == Brightness.dark
                        ? const Color(0xFF1E1E2C)
                        : Colors.grey.shade50,
                    child: Column(
                      children: [
                        Container(
                          padding: EdgeInsets.all(8),
                          color: Colors.blueGrey.shade600,
                          width: double.infinity,
                          child: Text(
                            '2. ${Localization.translate("السلاسل", Provider.of<AppSettingsProvider>(context).language)} (Series)',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        if (_selectedProfileId == null)
                          Expanded(
                            child: Center(
                              child: Text(
                                Localization.translate(
                                  'اختر نظاماً أولاً',
                                  Provider.of<AppSettingsProvider>(
                                    context,
                                  ).language,
                                ),
                              ),
                            ),
                          ),
                        if (_selectedProfileId != null)
                          Expanded(
                            child: ListView.builder(
                              itemCount: _currentSeries.length,
                              itemBuilder: (context, index) {
                                final s = _currentSeries[index];
                                final isSelected = s['id'] == _selectedSeriesId;
                                return InkWell(
                                  onTap: () {
                                    final seriesId = _readInt(s['id']);
                                    if (seriesId != null) {
                                      _loadSections(seriesId);
                                    }
                                  },
                                  child: Container(
                                    color: isSelected
                                        ? (Theme.of(context).brightness ==
                                                  Brightness.dark
                                              ? Colors.blue.shade900.withValues(
                                                  alpha: 0.3,
                                                )
                                              : Colors.blue.shade50)
                                        : Colors.transparent,
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 8,
                                      horizontal: 14,
                                    ),
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                "${s['name']} (${_profiles.firstWhere((p) => p['id'] == _selectedProfileId, orElse: () => {'type': ''})['type']})",
                                                style: TextStyle(
                                                  fontWeight: isSelected
                                                      ? FontWeight.bold
                                                      : FontWeight.normal,
                                                  fontSize: 13,
                                                ),
                                              ),
                                              if (s['type'] != null &&
                                                  s['type']
                                                      .toString()
                                                      .isNotEmpty)
                                                Text(
                                                  s['type'].toString(),
                                                  style: const TextStyle(
                                                    fontSize: 10,
                                                    color: Colors.grey,
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ),
                                        if (isUserAdmin)
                                          Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              IconButton(
                                                padding: EdgeInsets.zero,
                                                constraints:
                                                    const BoxConstraints(),
                                                icon: const Icon(
                                                  Icons.edit,
                                                  color: Colors.blue,
                                                  size: 16,
                                                ),
                                                onPressed: () =>
                                                    _showEditSeriesDialog(s),
                                              ),
                                              const SizedBox(width: 8),
                                              IconButton(
                                                padding: EdgeInsets.zero,
                                                constraints:
                                                    const BoxConstraints(),
                                                icon: const Icon(
                                                  Icons.delete,
                                                  color: Colors.red,
                                                  size: 16,
                                                ),
                                                onPressed: () => _confirmDelete(
                                                  'تأكيد الحذف',
                                                  'هل أنت متأكد أنك تريد حذف هذه السلسلة؟',
                                                  () async {
                                                    final seriesId = _readInt(
                                                      s['id'],
                                                    );
                                                    if (seriesId == null) {
                                                      return;
                                                    }
                                                    await widget.db
                                                        .deleteSeries(seriesId);
                                                    _loadSeries(
                                                      _selectedProfileId!,
                                                    );
                                                  },
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
                        if (_selectedProfileId != null && isUserAdmin)
                          Padding(
                            padding: EdgeInsets.all(8.0),
                            child: ElevatedButton.icon(
                              onPressed: _showAddSeriesDialog,
                              icon: Icon(Icons.add),
                              label: Text(
                                Localization.translate(
                                  'سلسلة جديدة',
                                  Provider.of<AppSettingsProvider>(
                                    context,
                                  ).language,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const VerticalDivider(width: 1),

                // 3. قائمة المقاطع (Sections)
                Expanded(
                  flex: 5,
                  child: Container(
                    color: Theme.of(context).brightness == Brightness.dark
                        ? Theme.of(context).scaffoldBackgroundColor
                        : Colors.white,
                    child: Column(
                      children: [
                        Container(
                          padding: EdgeInsets.all(8),
                          color: Colors.blueGrey.shade700,
                          width: double.infinity,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                '3. ${Localization.translate("المقاطع", Provider.of<AppSettingsProvider>(context).language)} (Sections)',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              if (_selectedSeriesId != null && isUserAdmin)
                                IconButton(
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                  icon: const Icon(
                                    Icons.copy,
                                    color: Colors.white,
                                    size: 18,
                                  ),
                                  tooltip: Localization.translate(
                                    'نسخ مقاطع من سلسلة أخرى',
                                    Provider.of<AppSettingsProvider>(
                                      context,
                                    ).language,
                                  ),
                                  onPressed: _showCopyFromSeriesDialog,
                                ),
                            ],
                          ),
                        ),
                        if (_selectedSeriesId == null)
                          Expanded(
                            child: Center(
                              child: Text(
                                Localization.translate(
                                  'اختر سلسلة لعرض مقاطعها',
                                  Provider.of<AppSettingsProvider>(
                                    context,
                                  ).language,
                                ),
                              ),
                            ),
                          ),
                        if (_selectedSeriesId != null)
                          Expanded(
                            child: ListView.builder(
                              itemCount: _currentSections.length,
                              itemBuilder: (context, index) {
                                final sec = _currentSections[index];
                                IconData typeIcon;
                                Color typeColor;
                                switch (sec['type']) {
                                  case 'plinthe':
                                    typeIcon = Icons.border_bottom;
                                    typeColor = Colors.brown;

                                    break;
                                  case 'frame':
                                    typeIcon = Icons.crop_square;
                                    typeColor = Colors.blue;
                                    break;
                                  case 'sash':
                                  case 'sash_traverse':
                                  case 'sash_lateral':
                                  case 'sash_central':
                                    typeIcon = Icons.door_front_door;
                                    typeColor = Colors.green;
                                    break;
                                  case 'mullion':
                                    typeIcon = Icons.add;
                                    typeColor = Colors.orange;
                                    break;
                                  case 'parclose':
                                    typeIcon = Icons.horizontal_rule;
                                    typeColor = Colors.purple;
                                    break;
                                  case 'side_cover':
                                    typeIcon = Icons.border_outer;
                                    typeColor = Colors.indigo;
                                    break;
                                  case 'batmo':
                                    typeIcon = Icons.vertical_align_center;
                                    typeColor = Colors.teal;
                                    break;
                                  case 'bouchon_batmo':
                                    typeIcon = Icons.compress;
                                    typeColor = Colors.brown;
                                    break;
                                  default:
                                    typeIcon = Icons.block;
                                    typeColor = Colors.grey;
                                }

                                return Card(
                                  margin: EdgeInsets.all(8),
                                  child: ListTile(
                                    leading: SectionImageWidget(
                                      code: sec['code']?.toString(),
                                      imagePath: sec['image_path']?.toString(),
                                      size: 40.0,
                                      fallbackIcon: typeIcon,
                                      fallbackColor: typeColor,
                                    ),
                                    // 🟢 منع تكسر النص
                                    title: Text(
                                      '${sec['code']} - ${sec['name']}',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    subtitle: Text(
                                      'سماكة: ${sec['thickness']}mm | ركوب: ${sec['glass_deduction']}mm | وزن: ${sec['weight_per_meter']} Kg/m',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    trailing: isUserAdmin
                                        ? Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              IconButton(
                                                icon: Icon(
                                                  Icons.edit,
                                                  color: Colors.blue,
                                                ),
                                                onPressed: () =>
                                                    _showEditSectionDialog(sec),
                                              ),
                                              IconButton(
                                                icon: Icon(
                                                  Icons.delete,
                                                  color: Colors.red,
                                                ),
                                                onPressed: () async {
                                                  await widget.db.deleteSection(
                                                    sec['id'],
                                                  );
                                                  _loadSections(
                                                    _selectedSeriesId!,
                                                  );
                                                },
                                              ),
                                            ],
                                          )
                                        : null,
                                  ),
                                );
                              },
                            ),
                          ),
                        if (_selectedSeriesId != null && isUserAdmin)
                          Padding(
                            padding: EdgeInsets.all(8.0),
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green,
                                foregroundColor: Colors.white,
                              ),
                              onPressed: _showAddSectionDialog,
                              icon: Icon(Icons.add),
                              label: Text(
                                Localization.translate(
                                  'إضافة مقطع جديد',
                                  Provider.of<AppSettingsProvider>(
                                    context,
                                  ).language,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
