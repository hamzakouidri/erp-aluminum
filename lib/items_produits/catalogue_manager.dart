import 'package:flutter/material.dart';
import '../sql_database.dart'; // تأكد من مسار ملف قاعدة البيانات
import 'package:database_data/settings/localization.dart';
import 'package:database_data/settings/app_settings.dart';
import 'package:provider/provider.dart';

class CatalogManagerScreen extends StatefulWidget {
  final SqlDatabase db; // نمرر قاعدة البيانات للشاشة

  const CatalogManagerScreen({super.key, required this.db});

  @override
  State<CatalogManagerScreen> createState() => _CatalogManagerScreenState();
}

class _CatalogManagerScreenState extends State<CatalogManagerScreen> {
  List<Map<String, dynamic>> _profiles = [];
  List<Map<String, dynamic>> _currentSeries = [];
  List<Map<String, dynamic>> _currentSections = [];

  int? _selectedProfileId;
  int? _selectedSeriesId;

  @override
  void initState() {
    super.initState();
    _loadProfiles();
  }

  // ==========================================
  // --- دوال جلب البيانات ---
  // ==========================================

  Future<void> _loadProfiles() async {
    final profiles = await widget.db.readProfile();
    setState(() {
      _profiles = profiles;
      _selectedProfileId = null;
      _selectedSeriesId = null;
      _currentSeries = [];
      _currentSections = [];
    });
  }

  Future<void> _loadSeries(int profileId) async {
    final series = await widget.db.readSeriesByProfile(profileId);
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
    String selectedType = 'Aluminium';

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setStateDialog) => AlertDialog(
          title: Text(Localization.translate('إضافة مقطع ألمنيوم جديد', Provider.of<AppSettingsProvider>(context).language),
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: InputDecoration(
                  labelText: Localization.translate('اسم المقطع (مثال: TPR)', Provider.of<AppSettingsProvider>(context).language),
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
                decoration: InputDecoration(labelText: Localization.translate('النوع', Provider.of<AppSettingsProvider>(context).language)),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(Localization.translate('إلغاء', Provider.of<AppSettingsProvider>(context).language), style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
              onPressed: () async {
                if (nameCtrl.text.isNotEmpty) {
                  await widget.db.insertProfile(nameCtrl.text, selectedType);
                  _loadProfiles();
                  if (context.mounted) Navigator.pop(dialogContext);
                }
              },
              child: Text(Localization.translate('حفظ', Provider.of<AppSettingsProvider>(context).language), style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  void _showAddSeriesDialog() {
    if (_selectedProfileId == null) return;
    final nameCtrl = TextEditingController();
    String selectedType = 'Frappe';

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: Text(Localization.translate('إضافة سلسلة جديدة', Provider.of<AppSettingsProvider>(context).language),
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
                  onChanged: (val) => setDialogState(() => selectedType = val!),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(Localization.translate('إلغاء', Provider.of<AppSettingsProvider>(context).language),
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
                    );
                    _loadSeries(_selectedProfileId!);
                    Navigator.pop(context);
                  }
                },
                child: Text(Localization.translate('حفظ', Provider.of<AppSettingsProvider>(context).language), style: TextStyle(color: Colors.white)),
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
    
    int? selectedSourceProfileId = profiles.first['id'] as int?;
    List<Map<String, dynamic>> sourceSeriesList = await widget.db.readSeriesByProfile(selectedSourceProfileId!);
    int? selectedSourceSeriesId = sourceSeriesList.isNotEmpty ? sourceSeriesList.first['id'] as int? : null;

    if (!mounted) return;
    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Text(Localization.translate('نسخ المقاطع من سلسلة أخرى', Provider.of<AppSettingsProvider>(context).language)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<int>(
                    decoration: InputDecoration(labelText: Localization.translate('البروفيل', Provider.of<AppSettingsProvider>(context).language)),
                    initialValue: selectedSourceProfileId,
                    items: profiles.map((p) => DropdownMenuItem<int>(
                      value: p['id'] as int,
                      child: Text(p['name'].toString()),
                    )).toList(),
                    onChanged: (val) async {
                      if (val != null) {
                        final newSeries = await widget.db.readSeriesByProfile(val);
                        setState(() {
                          selectedSourceProfileId = val;
                          sourceSeriesList = newSeries;
                          selectedSourceSeriesId = newSeries.isNotEmpty ? newSeries.first['id'] as int? : null;
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<int>(
                    decoration: InputDecoration(labelText: Localization.translate('السلسلة', Provider.of<AppSettingsProvider>(context).language)),
                    initialValue: selectedSourceSeriesId,
                    items: sourceSeriesList.map((s) => DropdownMenuItem<int>(
                      value: s['id'] as int,
                      child: Text(s['name'].toString()),
                    )).toList(),
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
                  child: Text(Localization.translate('إلغاء', Provider.of<AppSettingsProvider>(context).language)),
                ),
                ElevatedButton(
                  onPressed: selectedSourceSeriesId == null ? null : () async {
                    Navigator.pop(context);
                    final sourceSections = await widget.db.readSectionsBySeries(selectedSourceSeriesId!);
                    for (var sec in sourceSections) {
                      await widget.db.insertSection(
                        seriesId: _selectedSeriesId!,
                        code: sec['code'].toString(),
                        name: sec['name'].toString(),
                        type: sec['type'].toString(),
                        thickness: (sec['thickness'] as num?)?.toDouble() ?? 0.0,
                        glassDeduction: (sec['glass_deduction'] as num?)?.toDouble() ?? 0.0,
                        weightPerMeter: (sec['weight_per_meter'] as num?)?.toDouble() ?? 0.0,
                      );
                    }
                    _loadSections(_selectedSeriesId!);
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(Localization.translate('تم النسخ', Provider.of<AppSettingsProvider>(context).language))),
                      );
                    }
                  },
                  child: Text(Localization.translate('نسخ', Provider.of<AppSettingsProvider>(context).language)),
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

    final codeCtrl = TextEditingController();
    final nameCtrl = TextEditingController();
    final thicknessCtrl = TextEditingController();
    final glassDedCtrl = TextEditingController();
    final weightCtrl = TextEditingController();
    final couvreJointWidthCtrl = TextEditingController();
    String selectedType = 'frame';

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: Text(Localization.translate('إضافة مقطع جديد', Provider.of<AppSettingsProvider>(context).language),
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: codeCtrl,
                    decoration: InputDecoration(
                      labelText: 'الكود التجاري (مثال: P400)',
                    ),
                  ),
                  TextField(
                    controller: nameCtrl,
                    decoration: InputDecoration(
                      labelText: 'اسم المقطع (مثال: حلق 45)',
                    ),
                  ),
                  SizedBox(height: 10),
                  DropdownButton<String>(
                    isExpanded: true,
                    value: selectedType,
                    items: [
                      DropdownMenuItem(
                        value: 'frame',
                        child: Text(Localization.translate('حلق خارجي (Frame)', Provider.of<AppSettingsProvider>(context).language)),
                      ),
                      DropdownMenuItem(
                        value: 'sash',
                        child: Text(Localization.translate('ضلفة (Sash)', Provider.of<AppSettingsProvider>(context).language)),
                      ),
                      DropdownMenuItem(
                        value: 'mullion',
                        child: Text(Localization.translate('تيار / تقسيم (Mullion)', Provider.of<AppSettingsProvider>(context).language)),
                      ),
                      DropdownMenuItem(
                        value: 'parclose',
                        child: Text(Localization.translate('باغيت (Parclose)', Provider.of<AppSettingsProvider>(context).language)),
                      ),
                      DropdownMenuItem(
                        value: 'batmo',
                        child: Text('باتمو (Batmo)'),
                      ),
                      DropdownMenuItem(
                        value: 'bouchon_batmo',
                        child: Text('غطاء باتمو (Bouchon Batmo)'),
                      ),
                    ],
                    onChanged: (val) =>
                        setDialogState(() => selectedType = val!),
                  ),
                  if (selectedType != 'parclose' && selectedType != 'batmo' && selectedType != 'bouchon_batmo')
                    TextField(
                      controller: thicknessCtrl,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: 'العرض الظاهر / Thickness (mm)',
                      ),
                    ),
                  if (selectedType != 'batmo' && selectedType != 'bouchon_batmo')
                    TextField(
                      controller: glassDedCtrl,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: 'ركوب الزجاج / Glass Deduction (mm)',
                      ),
                    ),
                  TextField(
                    controller: weightCtrl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'الوزن للمتر (Kg/m)',
                    ),
                  ),
                  if (selectedType == 'frame')
                    TextField(
                      controller: couvreJointWidthCtrl,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: 'عرض الكوفرجوا / Couvre-joint Width (mm)',
                      ),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(Localization.translate('إلغاء', Provider.of<AppSettingsProvider>(context).language),
                  style: TextStyle(color: Colors.grey),
                ),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                onPressed: () async {
                  if (codeCtrl.text.isNotEmpty &&
                      (selectedType == 'parclose' || selectedType == 'batmo' || selectedType == 'bouchon_batmo' || thicknessCtrl.text.isNotEmpty)) {
                    await widget.db.insertSection(
                      seriesId: _selectedSeriesId!,
                      code: codeCtrl.text,
                      name: nameCtrl.text,
                      type: selectedType,
                      thickness: (selectedType == 'parclose' || selectedType == 'batmo' || selectedType == 'bouchon_batmo') ? 0.0 : (double.tryParse(thicknessCtrl.text) ?? 0.0),
                      glassDeduction: (selectedType == 'batmo' || selectedType == 'bouchon_batmo') ? 0.0 : (double.tryParse(glassDedCtrl.text) ?? 0.0),
                      weightPerMeter: double.tryParse(weightCtrl.text) ?? 0.0,
                      couvreJointWidth: double.tryParse(couvreJointWidthCtrl.text) ?? 0.0,
                    );
                    _loadSections(_selectedSeriesId!);
                    Navigator.pop(context);
                  }
                },
                child: Text(Localization.translate('إضافة المقطع', Provider.of<AppSettingsProvider>(context).language),
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
    final codeCtrl = TextEditingController(text: section['code']?.toString() ?? '');
    final nameCtrl = TextEditingController(text: section['name']?.toString() ?? '');
    final thicknessCtrl = TextEditingController(text: section['thickness']?.toString() ?? '');
    final glassDedCtrl = TextEditingController(text: section['glass_deduction']?.toString() ?? '');
    final weightCtrl = TextEditingController(text: section['weight_per_meter']?.toString() ?? '');
    final couvreJointWidthCtrl = TextEditingController(text: section['couvre_joint_width']?.toString() ?? '');
    String selectedType = section['type']?.toString() ?? 'frame';

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: Text(Localization.translate('تعديل المقطع', Provider.of<AppSettingsProvider>(context).language),
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: codeCtrl,
                    decoration: InputDecoration(
                      labelText: 'الكود التجاري (مثال: P400)',
                    ),
                  ),
                  TextField(
                    controller: nameCtrl,
                    decoration: InputDecoration(
                      labelText: 'اسم المقطع (مثال: حلق 45)',
                    ),
                  ),
                  SizedBox(height: 10),
                  DropdownButton<String>(
                    isExpanded: true,
                    value: selectedType,
                    items: [
                      DropdownMenuItem(
                        value: 'frame',
                        child: Text(Localization.translate('حلق خارجي (Frame)', Provider.of<AppSettingsProvider>(context).language)),
                      ),
                      DropdownMenuItem(
                        value: 'sash',
                        child: Text(Localization.translate('ضلفة (Sash)', Provider.of<AppSettingsProvider>(context).language)),
                      ),
                      DropdownMenuItem(
                        value: 'mullion',
                        child: Text(Localization.translate('تيار / تقسيم (Mullion)', Provider.of<AppSettingsProvider>(context).language)),
                      ),
                      DropdownMenuItem(
                        value: 'parclose',
                        child: Text(Localization.translate('باغيت (Parclose)', Provider.of<AppSettingsProvider>(context).language)),
                      ),
                      DropdownMenuItem(
                        value: 'batmo',
                        child: Text('باتمو (Batmo)'),
                      ),
                      DropdownMenuItem(
                        value: 'bouchon_batmo',
                        child: Text('غطاء باتمو (Bouchon Batmo)'),
                      ),
                    ],
                    onChanged: (val) =>
                        setDialogState(() => selectedType = val!),
                  ),
                  if (selectedType != 'parclose' && selectedType != 'batmo' && selectedType != 'bouchon_batmo')
                    TextField(
                      controller: thicknessCtrl,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: 'العرض الظاهر / Thickness (mm)',
                      ),
                    ),
                  if (selectedType != 'batmo' && selectedType != 'bouchon_batmo')
                    TextField(
                      controller: glassDedCtrl,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: 'ركوب الزجاج / Glass Deduction (mm)',
                      ),
                    ),
                  TextField(
                    controller: weightCtrl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'الوزن للمتر (Kg/m)',
                    ),
                  ),
                  if (selectedType == 'frame')
                    TextField(
                      controller: couvreJointWidthCtrl,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: 'عرض الكوفرجوا / Couvre-joint Width (mm)',
                      ),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(Localization.translate('إلغاء', Provider.of<AppSettingsProvider>(context).language),
                  style: TextStyle(color: Colors.grey),
                ),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
                onPressed: () async {
                  if (codeCtrl.text.isNotEmpty &&
                      (selectedType == 'parclose' || selectedType == 'batmo' || selectedType == 'bouchon_batmo' || thicknessCtrl.text.isNotEmpty)) {
                    await widget.db.updateSection(section['id'] as int, {
                      'code': codeCtrl.text,
                      'name': nameCtrl.text,
                      'type': selectedType,
                      'thickness': (selectedType == 'parclose' || selectedType == 'batmo' || selectedType == 'bouchon_batmo') ? 0.0 : (double.tryParse(thicknessCtrl.text) ?? 0.0),
                      'glass_deduction': (selectedType == 'batmo' || selectedType == 'bouchon_batmo') ? 0.0 : (double.tryParse(glassDedCtrl.text) ?? 0.0),
                      'weight_per_meter': double.tryParse(weightCtrl.text) ?? 0.0,
                      'couvre_joint_width': double.tryParse(couvreJointWidthCtrl.text) ?? 0.0,
                    });
                    _loadSections(_selectedSeriesId!);
                    Navigator.pop(context);
                  }
                },
                child: Text(Localization.translate('تعديل', Provider.of<AppSettingsProvider>(context).language),
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

  void _showEditProfileDialog(int id, String currentName, String currentType) {
    final nameCtrl = TextEditingController(text: currentName);
    String selectedType = (currentType == 'PVC') ? 'PVC' : 'Aluminium';

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setStateDialog) => AlertDialog(
          title: Text(Localization.translate('تعديل اسم المقطع', Provider.of<AppSettingsProvider>(context).language),
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: InputDecoration(
                  labelText: Localization.translate('اسم المقطع الجديد (مثال: TPR)', Provider.of<AppSettingsProvider>(context).language),
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
                decoration: InputDecoration(labelText: Localization.translate('النوع', Provider.of<AppSettingsProvider>(context).language)),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(Localization.translate('إلغاء', Provider.of<AppSettingsProvider>(context).language), style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
              onPressed: () async {
                if (nameCtrl.text.isNotEmpty) {
                  await widget.db.updateProfile(id, nameCtrl.text, selectedType);
                  _loadProfiles();
                  if (context.mounted) Navigator.pop(dialogContext);
                }
              },
              child: Text(Localization.translate('حفظ التعديل', Provider.of<AppSettingsProvider>(context).language),
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
        title: Text(Localization.translate('إدارة الكتالوج (Profiles & Sections)', Provider.of<AppSettingsProvider>(context).language)),
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
                    content: Text("هل أنت متأكد أنك تريد نسخ مقاطع ProWin 60 و 70 وتطبيقها على باقي بروفيلات الـ PVC والألمنيوم؟"),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text("إلغاء")),
                      ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: Text("نعم، انسخ")),
                    ],
                  )
                );
                if (confirm != true) return;

                try {
                  var database = await widget.db.db;
                  var profiles = await database!.query('Profiles');
                  var prowin = profiles.firstWhere((p) => p['name'].toString().toLowerCase().contains('prowin'), orElse: () => {});
                  if (prowin.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('بروفيل ProWin غير موجود!')));
                    return;
                  }
                  
                  int prowinId = prowin['id'] as int;
                  var prowinSeries = await database.query('Series', where: 'profile_id = ?', whereArgs: [prowinId]);
                  
                  var prowin60 = prowinSeries.firstWhere((s) => s['name'].toString() == '60', orElse: () => {});
                  var prowin70 = prowinSeries.firstWhere((s) => s['name'].toString() == '70' || s['name'].toString() == '72', orElse: () => {});
                  
                  if (prowin60.isEmpty || prowin70.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('السلسلة 60 أو 70/72 غير موجودة داخل ProWin!')));
                    return;
                  }
                  
                  int p60Id = prowin60['id'] as int;
                  int p70Id = prowin70['id'] as int;
                  
                  var secs60 = await database.query('Sections', where: 'series_id = ?', whereArgs: [p60Id]);
                  var secs70 = await database.query('Sections', where: 'series_id = ?', whereArgs: [p70Id]);
                  
                  for (var p in profiles) {
                    if (p['id'] == prowinId) continue;
                    var series = await database.query('Series', where: 'profile_id = ?', whereArgs: [p['id']]);
                    for (var s in series) {
                      String sName = s['name'].toString();
                      List<Map<String, dynamic>> sourceSecs = [];
                      if (sName == '60') {
                        sourceSecs = secs60;
                      } else if (sName == '60 PM' || sName == '70' || sName == '75' || sName == '72') {
                        sourceSecs = secs70;
                      }
                      
                      if (sourceSecs.isNotEmpty) {
                         // Check if target series already has sections
                         var existingSecs = await database.query('Sections', where: 'series_id = ?', whereArgs: [s['id']]);
                         if (existingSecs.isEmpty) {
                           for (var sec in sourceSecs) {
                             await widget.db.insertSection(
                               seriesId: s['id'] as int,
                               code: sec['code'].toString(),
                               name: sec['name'].toString(),
                               type: sec['type'].toString(),
                               thickness: (sec['thickness'] as num?)?.toDouble() ?? 0.0,
                               weightPerMeter: (sec['weight_per_meter'] as num?)?.toDouble() ?? 0.0,
                               glassDeduction: (sec['glass_deduction'] as num?)?.toDouble() ?? 0.0,
                               
                               
                             );
                           }
                         }
                      }
                    }
                  }
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تم نسخ المقاطع بنجاح!')));
                  _loadProfiles();
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('حدث خطأ أثناء النسخ: $e')));
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
                  color: Colors.grey.shade100,
                  child: Column(
                    children: [
                      Container(
                        padding: EdgeInsets.all(8),
                        color: Colors.blueGrey,
                        width: double.infinity,
                        child: Text('1. ${Localization.translate("الأنظمة", Provider.of<AppSettingsProvider>(context).language)} (Profiles)',
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
                              onTap: () => _loadSeries(p['id']),
                              child: Container(
                                color: isSelected ? Colors.blue.shade100 : Colors.transparent,
                                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 14),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      p['name'].toString(),
                                      style: TextStyle(fontWeight: isSelected ? FontWeight.bold : FontWeight.normal, fontSize: 13),
                                    ),
                                    if (isUserAdmin)
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.end,
                                        children: [
                                          IconButton(
                                            padding: EdgeInsets.zero,
                                            constraints: const BoxConstraints(),
                                            icon: const Icon(Icons.edit, color: Colors.blue, size: 16),
                                            onPressed: () => _showEditProfileDialog(p['id'], p['name'], p['type']),
                                          ),
                                          const SizedBox(width: 8),
                                          IconButton(
                                            padding: EdgeInsets.zero,
                                            constraints: const BoxConstraints(),
                                            icon: const Icon(Icons.delete, color: Colors.red, size: 16),
                                            onPressed: () async {
                                              await widget.db.deleteProfile(p['id']);
                                              _loadProfiles();
                                            },
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
                          label: Text(Localization.translate('نظام جديد', Provider.of<AppSettingsProvider>(context).language)),
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
                  color: Colors.grey.shade50,
                  child: Column(
                    children: [
                      Container(
                        padding: EdgeInsets.all(8),
                        color: Colors.blueGrey.shade600,
                        width: double.infinity,
                        child: Text('2. ${Localization.translate("السلاسل", Provider.of<AppSettingsProvider>(context).language)} (Series)',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      if (_selectedProfileId == null)
                        Expanded(
                          child: Center(child: Text(Localization.translate('اختر نظاماً أولاً', Provider.of<AppSettingsProvider>(context).language))),
                        ),
                      if (_selectedProfileId != null)
                        Expanded(
                          child: ListView.builder(
                            itemCount: _currentSeries.length,
                            itemBuilder: (context, index) {
                              final s = _currentSeries[index];
                              final isSelected = s['id'] == _selectedSeriesId;
                              return InkWell(
                                onTap: () => _loadSections(s['id']),
                                child: Container(
                                  color: isSelected ? Colors.blue.shade50 : Colors.transparent,
                                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 14),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        s['name'].toString(),
                                        style: TextStyle(fontWeight: isSelected ? FontWeight.bold : FontWeight.normal, fontSize: 13),
                                      ),
                                      if (s['type'] != null && s['type'].toString().isNotEmpty)
                                        Text(
                                          s['type'].toString(),
                                          style: const TextStyle(fontSize: 10, color: Colors.grey),
                                        ),
                                      if (isUserAdmin)
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.end,
                                          children: [
                                            
                                            IconButton(
                                              padding: EdgeInsets.zero,
                                              constraints: const BoxConstraints(),
                                              icon: const Icon(Icons.delete, color: Colors.red, size: 16),
                                              onPressed: () async {
                                                await widget.db.deleteSeries(s['id']);
                                                _loadSeries(_selectedProfileId!);
                                              },
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
                            label: Text(Localization.translate('سلسلة جديدة', Provider.of<AppSettingsProvider>(context).language)),
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
                  color: Colors.white,
                  child: Column(
                    children: [
                      Container(
                        padding: EdgeInsets.all(8),
                        color: Colors.blueGrey.shade700,
                        width: double.infinity,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('3. ${Localization.translate("المقاطع", Provider.of<AppSettingsProvider>(context).language)} (Sections)',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            if (_selectedSeriesId != null && isUserAdmin)
                              IconButton(
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                icon: const Icon(Icons.copy, color: Colors.white, size: 18),
                                tooltip: Localization.translate('نسخ مقاطع من سلسلة أخرى', Provider.of<AppSettingsProvider>(context).language),
                                onPressed: _showCopyFromSeriesDialog,
                              ),
                          ],
                        ),
                      ),
                      if (_selectedSeriesId == null)
                        Expanded(
                          child: Center(child: Text(Localization.translate('اختر سلسلة لعرض مقاطعها', Provider.of<AppSettingsProvider>(context).language))),
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
                                case 'frame':
                                  typeIcon = Icons.crop_square;
                                  typeColor = Colors.blue;
                                  break;
                                case 'sash':
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
                                margin: EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                child: ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor: typeColor.withValues(alpha: 0.2),
                                    child: Icon(typeIcon, color: typeColor),
                                  ),
                                  // 🟢 منع تكسر النص
                                  title: Text('${sec['code']} - ${sec['name']}',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  subtitle: Text('سماكة: ${sec['thickness']}mm | ركوب: ${sec['glass_deduction']}mm | وزن: ${sec['weight_per_meter']} Kg/m',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  trailing: isUserAdmin ? SingleChildScrollView(
                                    scrollDirection: Axis.horizontal,
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        IconButton(
                                          padding: EdgeInsets.zero,
                                          constraints: BoxConstraints(),
                                          icon: Icon(Icons.edit, color: Colors.blue, size: 18),
                                          onPressed: () => _showEditSectionDialog(sec),
                                        ),
                                        SizedBox(width: 8),
                                        IconButton(
                                          padding: EdgeInsets.zero,
                                          constraints: BoxConstraints(),
                                          icon: Icon(Icons.delete, color: Colors.red, size: 18),
                                          onPressed: () async {
                                            await widget.db.deleteSection(sec['id']);
                                            _loadSections(_selectedSeriesId!);
                                          },
                                        ),
                                      ],
                                    ),
                                  ) : null,
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
                            label: Text(Localization.translate('إضافة مقطع جديد', Provider.of<AppSettingsProvider>(context).language)),
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
