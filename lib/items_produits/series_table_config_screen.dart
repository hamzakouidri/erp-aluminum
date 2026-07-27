import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../sql_database.dart';
import '../settings/app_settings.dart';
import '../settings/localization.dart';

/// شاشة تخصيص عناصر وطريقة حساب جدول الكمية والتكلفة لكل سلسلة
/// المسار: المنتجات ← تخصيص جدول الكمية والتكلفة
class SeriesTableConfigScreen extends StatefulWidget {
  final SqlDatabase db;
  const SeriesTableConfigScreen({super.key, required this.db});

  @override
  State<SeriesTableConfigScreen> createState() => _SeriesTableConfigScreenState();
}

class _SeriesTableConfigScreenState extends State<SeriesTableConfigScreen> {
  List<Map<String, dynamic>> _profiles = [];
  List<Map<String, dynamic>> _seriesList = [];
  List<Map<String, dynamic>> _allAccessories = [];

  Map<String, dynamic>? _selectedProfile;
  Map<String, dynamic>? _selectedSeries;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final settings = Provider.of<AppSettingsProvider>(context);
    if (!settings.isManager) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && Navigator.canPop(context)) {
          Navigator.pop(context);
        }
      });
    }
  }

  bool _loadingProfiles = true;
  bool _loadingSeries = false;
  bool _loadingDetails = false;
  bool _saving = false;

  // Selected config sets
  final Set<String> _allowedSectionTypes = {};
  final Set<int> _allowedAccessoryIds = {};
  final Set<String> _allowedAccessoryTypes = {};
  final Set<int> _excludedAccessoryIds = {};

  // Calculation Formula Controllers
  final TextEditingController _sashDeduction2Ctrl = TextEditingController();
  final TextEditingController _sashDeduction3Ctrl = TextEditingController();
  final TextEditingController _sashDeduction4Ctrl = TextEditingController();
  final TextEditingController _sashOverlapCtrl = TextEditingController();
  final TextEditingController _glassDeductionCtrl = TextEditingController();
  final TextEditingController _formulaNotesCtrl = TextEditingController();

  String _accSearchQuery = '';
  final TextEditingController _accSearchCtrl = TextEditingController();

  static const List<String> _defaultSectionTypes = [
    'Dormant (إطار)',
    'Ouvrant (ظلفة)',
    'Parclose (باغيت)',
    'Traverse (عرضي)',
    'Chicane (شيكان)',
    'Rail (سكة)',
    'Renfort (حديد تعزيز)',
    'Couvre-joint (كافر جوان)',
    'Mullion (تقسيم)',
    'Battement (باطمو)',
  ];

  static const List<String> _defaultAccessoryTypes = [
    'Poignée (مقبض)',
    'Paumelle (مفصلة)',
    'Roulette (عجلات)',
    'Verrou (فيرو)',
    'Serrure (قفل)',
    'Joint (جوان)',
    'Espagnolette (إسبانيوليت)',
    'System OB (أوسيلو باتون)',
    'Gâche (كاش كوليسون)',
    'Arrêt (صداد)',
    'Visse (براغي)',
    'Attache (أطاش)',
  ];

  @override
  void initState() {
    super.initState();
    _loadProfiles();
  }

  @override
  void dispose() {
    _accSearchCtrl.dispose();
    _sashDeduction2Ctrl.dispose();
    _sashDeduction3Ctrl.dispose();
    _sashDeduction4Ctrl.dispose();
    _sashOverlapCtrl.dispose();
    _glassDeductionCtrl.dispose();
    _formulaNotesCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadProfiles() async {
    setState(() => _loadingProfiles = true);
    final p = await widget.db.readProfile();
    setState(() {
      _profiles = p;
      _loadingProfiles = false;
    });
  }

  Future<void> _selectProfile(Map<String, dynamic> profile) async {
    setState(() {
      _selectedProfile = profile;
      _selectedSeries = null;
      _seriesList = [];
      _allAccessories = [];
      _allowedSectionTypes.clear();
      _allowedAccessoryIds.clear();
      _allowedAccessoryTypes.clear();
      _excludedAccessoryIds.clear();
      _clearFormulaInputs();
      _loadingSeries = true;
    });
    final s = await widget.db.readSeriesByProfile(profile['id'] as int);
    setState(() {
      _seriesList = s;
      _loadingSeries = false;
    });
  }

  void _clearFormulaInputs() {
    _sashDeduction2Ctrl.clear();
    _sashDeduction3Ctrl.clear();
    _sashDeduction4Ctrl.clear();
    _sashOverlapCtrl.clear();
    _glassDeductionCtrl.clear();
    _formulaNotesCtrl.clear();
  }

  Future<void> _selectSeries(Map<String, dynamic> series) async {
    setState(() {
      _selectedSeries = series;
      _loadingDetails = true;
      _allowedSectionTypes.clear();
      _allowedAccessoryIds.clear();
      _allowedAccessoryTypes.clear();
      _excludedAccessoryIds.clear();
      _clearFormulaInputs();
    });

    final seriesId = series['id'] as int;

    // Load Accessories and Joints
    final allAcc = await widget.db.readAccessories();
    final allJoints = await widget.db.readJoints();

    final List<Map<String, dynamic>> combined = [];
    for (var a in allAcc) {
      combined.add(Map<String, dynamic>.from(a)..['isJoint'] = false);
    }
    for (var j in allJoints) {
      combined.add(Map<String, dynamic>.from(j)
        ..['isJoint'] = true
        ..['material_type'] = j['type']);
    }

    // Filter by material type (PVC vs Aluminium)
    final pt = (_selectedProfile?['type'] ?? 'Aluminium').toString().toLowerCase();
    final filteredAcc = combined.where((a) {
      final mt = (a['material_type'] ?? 'Aluminium').toString().toLowerCase();
      return pt == 'pvc' ? mt == 'pvc' : (mt == 'aluminium' || mt == '' || mt == 'null' || mt == 'aluminum');
    }).toList();

    // Load existing SeriesTableConfig
    final existingConfig = await widget.db.getSeriesTableConfig(seriesId);

    if (existingConfig != null) {
      final String secTypesStr = existingConfig['allowed_section_types'] ?? '';
      final String accIdsStr = existingConfig['allowed_accessory_ids'] ?? '';
      final String accTypesStr = existingConfig['allowed_accessory_types'] ?? '';
      final String exclIdsStr = existingConfig['excluded_accessory_ids'] ?? '';

      if (secTypesStr.isNotEmpty) {
        _allowedSectionTypes.addAll(secTypesStr.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty));
      } else {
        _allowedSectionTypes.addAll(_defaultSectionTypes);
      }

      if (accIdsStr.isNotEmpty) {
        _allowedAccessoryIds.addAll(accIdsStr.split(',').map((e) => int.tryParse(e.trim())).whereType<int>());
      } else {
        for (var a in filteredAcc) {
          final id = a['id'] as int?;
          if (id != null) {
            final sStr = (a['series_ids'] ?? '').toString();
            final isGlobal = (a['scope'] ?? 'Global').toString() == 'Global';
            if (isGlobal || sStr.split(',').map((e) => int.tryParse(e.trim())).contains(seriesId)) {
              _allowedAccessoryIds.add(id);
            }
          }
        }
      }

      if (accTypesStr.isNotEmpty) {
        _allowedAccessoryTypes.addAll(accTypesStr.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty));
      } else {
        _allowedAccessoryTypes.addAll(_defaultAccessoryTypes);
      }

      if (exclIdsStr.isNotEmpty) {
        _excludedAccessoryIds.addAll(exclIdsStr.split(',').map((e) => int.tryParse(e.trim())).whereType<int>());
      }

      // Populate formula controllers
      final d2 = (existingConfig['sash_w_deduction_2'] as num?)?.toDouble() ?? 0.0;
      final d3 = (existingConfig['sash_w_deduction_3'] as num?)?.toDouble() ?? 0.0;
      final d4 = (existingConfig['sash_w_deduction_4'] as num?)?.toDouble() ?? 0.0;
      final ov = (existingConfig['sash_overlap_val'] as num?)?.toDouble() ?? 0.0;
      final gd = (existingConfig['glass_w_deduction'] as num?)?.toDouble() ?? 0.0;
      final fn = (existingConfig['custom_formula_notes'] ?? '').toString();

      _sashDeduction2Ctrl.text = d2 != 0.0 ? d2.toString() : '';
      _sashDeduction3Ctrl.text = d3 != 0.0 ? d3.toString() : '';
      _sashDeduction4Ctrl.text = d4 != 0.0 ? d4.toString() : '';
      _sashOverlapCtrl.text = ov != 0.0 ? ov.toString() : '';
      _glassDeductionCtrl.text = gd != 0.0 ? gd.toString() : '';
      _formulaNotesCtrl.text = fn;
    } else {
      _allowedSectionTypes.addAll(_defaultSectionTypes);
      _allowedAccessoryTypes.addAll(_defaultAccessoryTypes);
      for (var a in filteredAcc) {
        final id = a['id'] as int?;
        if (id != null) {
          final sStr = (a['series_ids'] ?? '').toString();
          final isGlobal = (a['scope'] ?? 'Global').toString() == 'Global';
          if (isGlobal || sStr.split(',').map((e) => int.tryParse(e.trim())).contains(seriesId)) {
            _allowedAccessoryIds.add(id);
          }
        }
      }
    }

    setState(() {
      _allAccessories = filteredAcc;
      _loadingDetails = false;
    });
  }

  Future<void> _saveConfig() async {
    final seriesId = _selectedSeries?['id'] as int?;
    final lang = Provider.of<AppSettingsProvider>(context, listen: false).language;
    if (seriesId == null) return;

    setState(() => _saving = true);

    try {
      await widget.db.upsertSeriesTableConfig(
        seriesId: seriesId,
        allowedSectionTypes: _allowedSectionTypes.join(','),
        allowedAccessoryIds: _allowedAccessoryIds.join(','),
        allowedAccessoryTypes: _allowedAccessoryTypes.join(','),
        excludedAccessoryIds: _excludedAccessoryIds.join(','),
        sashWDeduction2: double.tryParse(_sashDeduction2Ctrl.text) ?? 0.0,
        sashWDeduction3: double.tryParse(_sashDeduction3Ctrl.text) ?? 0.0,
        sashWDeduction4: double.tryParse(_sashDeduction4Ctrl.text) ?? 0.0,
        sashOverlapVal: double.tryParse(_sashOverlapCtrl.text) ?? 0.0,
        glassWDeduction: double.tryParse(_glassDeductionCtrl.text) ?? 0.0,
        customFormulaNotes: _formulaNotesCtrl.text.trim(),
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(Localization.translate('تم حفظ إعدادات جدول الكمية والتكلفة بنجاح', lang)),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      debugPrint('Save series table config error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ أثناء الحفظ: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final lang = Provider.of<AppSettingsProvider>(context).language;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final primaryColor = isDark ? const Color(0xFF90CAF9) : const Color(0xFF1E3A5F);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          Localization.translate('تخصيص جدول الكمية والتكلفة', lang),
          style: TextStyle(fontFamily: GoogleFonts.cairo().fontFamily, fontWeight: FontWeight.bold),
        ),
        backgroundColor: isDark ? Theme.of(context).appBarTheme.backgroundColor : Colors.blue,
        centerTitle: true,
      ),
      floatingActionButton: _selectedSeries != null
          ? FloatingActionButton.extended(
              onPressed: _saving ? null : _saveConfig,
              icon: _saving
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Icon(Icons.save_rounded, color: Colors.white),
              label: Text(
                Localization.translate('حفظ الإعدادات', lang),
                style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, color: Colors.white),
              ),
              backgroundColor: Colors.green,
            )
          : null,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Step 1: Select Profile ─────────────────────────────────────────
            Text(
              Localization.translate('1. اختر البروفيل / السيستم', lang),
              style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 16, color: primaryColor),
            ),
            const SizedBox(height: 8),
            _loadingProfiles
                ? const Center(child: CircularProgressIndicator())
                : SizedBox(
                    height: 50,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: _profiles.length,
                      itemBuilder: (ctx, i) {
                        final prof = _profiles[i];
                        final isSel = _selectedProfile?['id'] == prof['id'];
                        return Padding(
                          padding: const EdgeInsets.only(left: 8.0, right: 8.0),
                          child: ChoiceChip(
                            label: Text(prof['name'].toString(), style: const TextStyle(fontFamily: 'Cairo')),
                            selected: isSel,
                            selectedColor: Colors.blue.withValues(alpha: 0.3),
                            onSelected: (_) => _selectProfile(prof),
                          ),
                        );
                      },
                    ),
                  ),
            const Divider(height: 28),

            // ── Step 2: Select Series ──────────────────────────────────────────
            if (_selectedProfile != null) ...[
              Text(
                Localization.translate('2. اختر السلسلة', lang),
                style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 16, color: primaryColor),
              ),
              const SizedBox(height: 8),
              _loadingSeries
                  ? const Center(child: CircularProgressIndicator())
                  : _seriesList.isEmpty
                      ? Text(Localization.translate('لا توجد سلاسل مسجلة لهذا البروفيل', lang), style: const TextStyle(fontFamily: 'Cairo', color: Colors.orange))
                      : SizedBox(
                          height: 50,
                          child: ListView.builder(
                            scrollDirection: Axis.horizontal,
                            itemCount: _seriesList.length,
                            itemBuilder: (ctx, i) {
                              final ser = _seriesList[i];
                              final isSel = _selectedSeries?['id'] == ser['id'];
                              return Padding(
                                padding: const EdgeInsets.only(left: 8.0, right: 8.0),
                                child: ChoiceChip(
                                  label: Text(ser['name'].toString(), style: const TextStyle(fontFamily: 'Cairo')),
                                  selected: isSel,
                                  selectedColor: Colors.green.withValues(alpha: 0.3),
                                  onSelected: (_) => _selectSeries(ser),
                                ),
                              );
                            },
                          ),
                        ),
              const Divider(height: 28),
            ],

            // ── Details Section ────────────────────────────────────────────────
            if (_selectedSeries != null) ...[
              if (_loadingDetails)
                const Center(child: CircularProgressIndicator())
              else ...[
                // ── Section 1: Calculation Formulas for Sash & Glass Width ────
                Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.calculate_outlined, color: Colors.blue),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                Localization.translate('طريقة وحسابات عرض الدلفة والزجاج بالسلسلة', lang),
                                style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 15),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'تتيح لك هذه الخانات تحديد طريقة الخصم أو التداخل لحساب عرض الدلفة وعرض الزجاج بدقة لهذه السلسلة (مثال: سلاسل 10 بياس، سلاسل PVC المنزلقة... إلخ).',
                          style: TextStyle(fontFamily: 'Cairo', fontSize: 12, color: isDark ? Colors.grey[400] : Colors.grey[700]),
                        ),
                        const SizedBox(height: 16),

                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _sashDeduction2Ctrl,
                                keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                                decoration: InputDecoration(
                                  labelText: Localization.translate('خصم/ثابت عرض الدلفة (ضلفتين 2 Sashes)', lang),
                                  hintText: 'مثال: 26.0 أو -154.0',
                                  border: const OutlineInputBorder(),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextField(
                                controller: _sashDeduction3Ctrl,
                                keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                                decoration: InputDecoration(
                                  labelText: Localization.translate('خصم/ثابت عرض الدلفة (3 ضلفات 3 Sashes)', lang),
                                  hintText: 'مثال: 52.0 أو -160.0',
                                  border: const OutlineInputBorder(),
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
                                controller: _sashDeduction4Ctrl,
                                keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                                decoration: InputDecoration(
                                  labelText: Localization.translate('خصم/ثابت عرض الدلفة (4 ضلفات 4 Sashes)', lang),
                                  hintText: 'مثال: 78.0',
                                  border: const OutlineInputBorder(),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextField(
                                controller: _sashOverlapCtrl,
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                decoration: InputDecoration(
                                  labelText: Localization.translate('ثابت تداخل المنزلق (Overlap مم)', lang),
                                  hintText: 'افتراضي: 26 مم',
                                  border: const OutlineInputBorder(),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),

                        TextField(
                          controller: _glassDeductionCtrl,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: InputDecoration(
                            labelText: Localization.translate('خصم عرض الزجاج من عرض الدلفة (مم)', lang),
                            hintText: 'مثال: الخصم من عرض الدلفة للزجاج',
                            border: const OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 12),

                        TextField(
                          controller: _formulaNotesCtrl,
                          maxLines: 2,
                          decoration: InputDecoration(
                            labelText: Localization.translate('ملاحظات المعادلات الخاصة بالسلسلة', lang),
                            hintText: 'أدخل أي شرح أو قواعد خاصة لمعادلة هذه السلسلة...',
                            border: const OutlineInputBorder(),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // ── Section 2: Allowed Section Types ───────────────────────────
                Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          Localization.translate('أنواع القطاعات المسموحة بالجدول', lang),
                          style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 15, color: primaryColor),
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: _defaultSectionTypes.map((type) {
                            final isSel = _allowedSectionTypes.contains(type);
                            return FilterChip(
                              label: Text(type, style: const TextStyle(fontFamily: 'Cairo', fontSize: 12)),
                              selected: isSel,
                              selectedColor: Colors.blue.withValues(alpha: 0.2),
                              onSelected: (val) {
                                setState(() {
                                  if (val) {
                                    _allowedSectionTypes.add(type);
                                  } else {
                                    _allowedSectionTypes.remove(type);
                                  }
                                });
                              },
                            );
                          }).toList(),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // ── Section 3: Allowed Accessory Types ─────────────────────────
                Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          Localization.translate('أنواع الإكسسوارات المسموحة بالجدول', lang),
                          style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 15, color: primaryColor),
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: _defaultAccessoryTypes.map((type) {
                            final isSel = _allowedAccessoryTypes.contains(type);
                            return FilterChip(
                              label: Text(type, style: const TextStyle(fontFamily: 'Cairo', fontSize: 12)),
                              selected: isSel,
                              selectedColor: Colors.amber.withValues(alpha: 0.2),
                              onSelected: (val) {
                                setState(() {
                                  if (val) {
                                    _allowedAccessoryTypes.add(type);
                                  } else {
                                    _allowedAccessoryTypes.remove(type);
                                  }
                                });
                              },
                            );
                          }).toList(),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // ── Section 4: Specific Accessories List ───────────────────────
                Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                Localization.translate('قائمة الإكسسوارات الفردية المسموحة', lang),
                                style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 15, color: primaryColor),
                              ),
                            ),
                            TextButton(
                              onPressed: () {
                                setState(() {
                                  _allowedAccessoryIds.addAll(_allAccessories.map((a) => a['id'] as int));
                                });
                              },
                              child: Text(Localization.translate('تحديد الكل', lang), style: const TextStyle(fontFamily: 'Cairo', fontSize: 12)),
                            ),
                            TextButton(
                              onPressed: () {
                                setState(() {
                                  _allowedAccessoryIds.clear();
                                });
                              },
                              child: Text(Localization.translate('إلغاء الكل', lang), style: const TextStyle(fontFamily: 'Cairo', fontSize: 12, color: Colors.red)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),

                        TextField(
                          controller: _accSearchCtrl,
                          onChanged: (val) => setState(() => _accSearchQuery = val.trim().toLowerCase()),
                          decoration: InputDecoration(
                            hintText: Localization.translate('بحث في الإكسسوارات...', lang),
                            prefixIcon: const Icon(Icons.search, size: 20),
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                        const SizedBox(height: 12),

                        Builder(builder: (ctx) {
                          final list = _allAccessories.where((a) {
                            if (_accSearchQuery.isEmpty) return true;
                            final name = (a['name'] ?? '').toString().toLowerCase();
                            final ref = (a['reference'] ?? '').toString().toLowerCase();
                            return name.contains(_accSearchQuery) || ref.contains(_accSearchQuery);
                          }).toList();

                          if (list.isEmpty) {
                            return const Padding(
                              padding: EdgeInsets.all(16.0),
                              child: Center(child: Text('لا توجد نتائج مطابقة للبحث', style: TextStyle(fontFamily: 'Cairo'))),
                            );
                          }

                          return ListView.separated(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: list.length,
                            separatorBuilder: (context, idx) => const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final item = list[index];
                              final id = item['id'] as int;
                              final name = item['name'].toString();
                              final isJoint = item['isJoint'] == true;
                              final isChecked = _allowedAccessoryIds.contains(id);

                              return CheckboxListTile(
                                dense: true,
                                title: Text(
                                  '$name ${isJoint ? "(جوان)" : ""}',
                                  style: const TextStyle(fontFamily: 'Cairo', fontSize: 13),
                                ),
                                subtitle: Text(
                                  'ID: $id | النوع: ${item['type'] ?? "-"}',
                                  style: const TextStyle(fontFamily: 'Cairo', fontSize: 11, color: Colors.grey),
                                ),
                                value: isChecked,
                                onChanged: (val) {
                                  setState(() {
                                    if (val == true) {
                                      _allowedAccessoryIds.add(id);
                                    } else {
                                      _allowedAccessoryIds.remove(id);
                                    }
                                  });
                                },
                              );
                            },
                          );
                        }),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 80),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
