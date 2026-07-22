import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../sql_database.dart';
import '../settings/app_settings.dart';
import '../settings/localization.dart';

/// شاشة تخصيص عناصر جدول الكمية والتكلفة لكل سلسلة
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
  List<Map<String, dynamic>> _allSections = [];

  Map<String, dynamic>? _selectedProfile;
  Map<String, dynamic>? _selectedSeries;

  bool _loadingProfiles = true;
  bool _loadingSeries = false;
  bool _loadingDetails = false;
  bool _saving = false;

  // Selected config sets
  final Set<String> _allowedSectionTypes = {};
  final Set<int> _allowedAccessoryIds = {};
  final Set<String> _allowedAccessoryTypes = {};
  final Set<int> _excludedAccessoryIds = {};

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
      _allSections = [];
      _allowedSectionTypes.clear();
      _allowedAccessoryIds.clear();
      _allowedAccessoryTypes.clear();
      _excludedAccessoryIds.clear();
      _loadingSeries = true;
    });
    final s = await widget.db.readSeriesByProfile(profile['id'] as int);
    setState(() {
      _seriesList = s;
      _loadingSeries = false;
    });
  }

  Future<void> _selectSeries(Map<String, dynamic> series) async {
    setState(() {
      _selectedSeries = series;
      _loadingDetails = true;
      _allowedSectionTypes.clear();
      _allowedAccessoryIds.clear();
      _allowedAccessoryTypes.clear();
      _excludedAccessoryIds.clear();
    });

    final seriesId = series['id'] as int;

    // Load Sections belonging to this series
    final dbInstance = await widget.db.db;
    List<Map<String, dynamic>> secList = [];
    if (dbInstance != null) {
      secList = await dbInstance.query('Sections', where: 'series_id = ?', whereArgs: [seriesId]);
    }

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
        // By default, select all accessories linked to this series or global
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
    } else {
      // Default initial state
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
      _allSections = secList;
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
                      ? Text(Localization.translate('لا توجد سلاسل مسجلة لهذا البروفيل', lang))
                      : Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: _seriesList.map((ser) {
                            final isSel = _selectedSeries?['id'] == ser['id'];
                            return ChoiceChip(
                              label: Text(ser['name'].toString(), style: const TextStyle(fontFamily: 'Cairo')),
                              selected: isSel,
                              selectedColor: Colors.green.withValues(alpha: 0.3),
                              onSelected: (_) => _selectSeries(ser),
                            );
                          }).toList(),
                        ),
              const Divider(height: 28),
            ],

            // ── Step 3: Configure Allowed Components and Accessories ──────────
            if (_selectedSeries != null) ...[
              if (_loadingDetails)
                const Center(child: CircularProgressIndicator())
              else ...[
                // Card A: Allowed Profile Section Types
                _buildCardSection(
                  context,
                  title: Localization.translate('أنواع القطاعات المسموحة بالجدول', lang),
                  icon: Icons.format_shapes_rounded,
                  color: Colors.indigo,
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _defaultSectionTypes.map((type) {
                      final isSel = _allowedSectionTypes.contains(type);
                      return FilterChip(
                        label: Text(type, style: const TextStyle(fontFamily: 'Cairo', fontSize: 13)),
                        selected: isSel,
                        selectedColor: Colors.indigo.withValues(alpha: 0.25),
                        onSelected: (val) {
                          setState(() {
                            val ? _allowedSectionTypes.add(type) : _allowedSectionTypes.remove(type);
                          });
                        },
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 16),

                // Card B: Allowed Accessory Types
                _buildCardSection(
                  context,
                  title: Localization.translate('أنواع الإكسسوارات المسموحة بالجدول', lang),
                  icon: Icons.category_rounded,
                  color: Colors.purple,
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _defaultAccessoryTypes.map((accType) {
                      final isSel = _allowedAccessoryTypes.contains(accType);
                      return FilterChip(
                        label: Text(accType, style: const TextStyle(fontFamily: 'Cairo', fontSize: 13)),
                        selected: isSel,
                        selectedColor: Colors.purple.withValues(alpha: 0.25),
                        onSelected: (val) {
                          setState(() {
                            val ? _allowedAccessoryTypes.add(accType) : _allowedAccessoryTypes.remove(accType);
                          });
                        },
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 16),

                // Card C: Allowed Specific Accessory Items
                _buildCardSection(
                  context,
                  title: Localization.translate('قائمة الإكسسوارات الفردية المسموحة', lang),
                  icon: Icons.construction_rounded,
                  color: Colors.orange,
                  child: Column(
                    children: [
                      TextField(
                        controller: _accSearchCtrl,
                        decoration: InputDecoration(
                          hintText: Localization.translate('بحث في الإكسسوارات...', lang),
                          prefixIcon: const Icon(Icons.search),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        ),
                        onChanged: (v) => setState(() => _accSearchQuery = v.trim().toLowerCase()),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          TextButton.icon(
                            onPressed: () {
                              setState(() {
                                for (var a in _allAccessories) {
                                  final id = a['id'] as int?;
                                  if (id != null) _allowedAccessoryIds.add(id);
                                }
                              });
                            },
                            icon: const Icon(Icons.select_all),
                            label: Text(Localization.translate('تحديد الكل', lang)),
                          ),
                          TextButton.icon(
                            onPressed: () {
                              setState(() => _allowedAccessoryIds.clear());
                            },
                            icon: const Icon(Icons.deselect),
                            label: Text(Localization.translate('إلغاء الكل', lang)),
                          ),
                        ],
                      ),
                      const Divider(),
                      SizedBox(
                        height: 320,
                        child: ListView.builder(
                          itemCount: _allAccessories.length,
                          itemBuilder: (ctx, idx) {
                            final acc = _allAccessories[idx];
                            final id = acc['id'] as int;
                            final name = acc['name'].toString();
                            final type = (acc['type'] ?? acc['material_type'] ?? '').toString();
                            if (_accSearchQuery.isNotEmpty &&
                                !name.toLowerCase().contains(_accSearchQuery) &&
                                !type.toLowerCase().contains(_accSearchQuery)) {
                              return const SizedBox.shrink();
                            }
                            final isAllowed = _allowedAccessoryIds.contains(id);
                            return CheckboxListTile(
                              value: isAllowed,
                              title: Text(name, style: const TextStyle(fontFamily: 'Cairo', fontSize: 14)),
                              subtitle: Text(type, style: TextStyle(color: isDark ? Colors.grey.shade400 : Colors.grey.shade600, fontSize: 12)),
                              dense: true,
                              activeColor: Colors.orange,
                              onChanged: (val) {
                                setState(() {
                                  if (val == true) {
                                    _allowedAccessoryIds.add(id);
                                    _excludedAccessoryIds.remove(id);
                                  } else {
                                    _allowedAccessoryIds.remove(id);
                                    _excludedAccessoryIds.add(id);
                                  }
                                });
                              },
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 80), // Padding for FAB
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCardSection(
    BuildContext context, {
    required String title,
    required IconData icon,
    required Color color,
    required Widget child,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 24),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontFamily: GoogleFonts.cairo().fontFamily,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                ),
              ],
            ),
            const Divider(height: 20),
            child,
          ],
        ),
      ),
    );
  }
}
