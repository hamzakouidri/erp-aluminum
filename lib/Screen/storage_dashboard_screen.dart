import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:database_data/settings/app_settings.dart';
import 'package:database_data/settings/localization.dart';
import 'package:database_data/services/auth_service.dart';
import 'package:database_data/services/supabase_account_service.dart';
import '../sql_database.dart';
import 'trash_screen.dart';

class StorageDashboardScreen extends StatefulWidget {
  final SqlDatabase? db;

  const StorageDashboardScreen({super.key, this.db});

  @override
  State<StorageDashboardScreen> createState() => _StorageDashboardScreenState();
}

class _StorageDashboardScreenState extends State<StorageDashboardScreen>
    with SingleTickerProviderStateMixin {
  late final SqlDatabase _db;
  bool _isLoading = true;
  bool _isOptimizing = false;
  int _dbFileSizeBytes = 0;
  Map<String, int> _categoryCounts = {};
  int _selectedCategoryIndex = -1;

  // Admin Multi-Workshop comparison
  late TabController _tabController;
  bool _isAdmin = false;
  List<Map<String, dynamic>> _adminWorkshops = [];
  bool _isLoadingAdminWorkshops = false;

  static const List<_CategoryMeta> _categories = [
    _CategoryMeta(
      key: 'commandes',
      nameAr: 'طلبات الزبائن والمقاسات',
      nameFr: 'Commandes & Devis',
      nameEn: 'Orders & Quotes',
      icon: Icons.assignment_outlined,
      color: Color(0xFF2563EB), // Blue
    ),
    _CategoryMeta(
      key: 'achats',
      nameAr: 'فواتير ومواد الشراء',
      nameFr: 'Factures d\'achat',
      nameEn: 'Purchase Invoices & Materials',
      icon: Icons.shopping_bag_outlined,
      color: Color(0xFFF59E0B), // Amber
    ),
    _CategoryMeta(
      key: 'inventory',
      nameAr: 'حركات المخزون والمستودع',
      nameFr: 'Inventaire & Stock',
      nameEn: 'Inventory & Stock Movements',
      icon: Icons.inventory_2_outlined,
      color: Color(0xFF0D9488), // Teal
    ),
    _CategoryMeta(
      key: 'treasury',
      nameAr: 'الخزينة والمحاسبة المالية',
      nameFr: 'Trésorerie & Finances',
      nameEn: 'Treasury & Finances',
      icon: Icons.account_balance_wallet_outlined,
      color: Color(0xFF10B981), // Emerald
    ),
    _CategoryMeta(
      key: 'catalog',
      nameAr: 'الكتالوج ومقاطع الألمنيوم',
      nameFr: 'Catalogue & Profilés',
      nameEn: 'Catalog & Aluminium Profiles',
      icon: Icons.view_sidebar_outlined,
      color: Color(0xFF8B5CF6), // Purple
    ),
    _CategoryMeta(
      key: 'clients_suppliers',
      nameAr: 'بيانات العملاء والموردين',
      nameFr: 'Clients & Fournisseurs',
      nameEn: 'Clients & Suppliers',
      icon: Icons.people_outline,
      color: Color(0xFF6366F1), // Indigo
    ),
    _CategoryMeta(
      key: 'trash',
      nameAr: 'سلة المهملات والمحذوفات',
      nameFr: 'Corbeille',
      nameEn: 'Recycle Bin & Deleted',
      icon: Icons.auto_delete_outlined,
      color: Color(0xFFEF4444), // Red
    ),
  ];

  @override
  void initState() {
    super.initState();
    _db = widget.db ?? SqlDatabase();
    final userEmail = AppAuthService().currentUser?.email;
    _isAdmin = isApplicationAdminEmail(userEmail);
    _tabController = TabController(length: _isAdmin ? 2 : 1, vsync: this);
    _loadStorageData();
    if (_isAdmin) {
      _loadAdminWorkshops();
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadStorageData() async {
    setState(() => _isLoading = true);
    try {
      final size = await _db.getDatabaseFileSizeBytes();
      final counts = await _db.getStorageCategoryCounts();
      if (mounted) {
        setState(() {
          _dbFileSizeBytes = size;
          _categoryCounts = counts;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading storage data: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadAdminWorkshops() async {
    setState(() => _isLoadingAdminWorkshops = true);
    try {
      final rows = await SupabaseAccountService().fetchAdminWorkshops();
      if (mounted) {
        setState(() {
          _adminWorkshops = rows;
          _isLoadingAdminWorkshops = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading admin workshops: $e');
      if (mounted) setState(() => _isLoadingAdminWorkshops = false);
    }
  }

  Future<void> _runVacuum() async {
    setState(() => _isOptimizing = true);
    try {
      await _db.vacuumDatabase();
      await _loadStorageData();
      if (mounted) {
        final lang = Provider.of<AppSettingsProvider>(context, listen: false).language;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: Colors.greenAccent),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    Localization.translate('تم ضغط وتحسين مساحة قاعدة البيانات بنجاح', lang),
                    style: const TextStyle(fontFamily: 'Cairo'),
                  ),
                ),
              ],
            ),
            backgroundColor: Colors.black87,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      debugPrint('Error running vacuum: $e');
    } finally {
      if (mounted) setState(() => _isOptimizing = false);
    }
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }

  int get _totalRecords {
    int sum = 0;
    for (final v in _categoryCounts.values) {
      sum += v;
    }
    return sum;
  }

  @override
  Widget build(BuildContext context) {
    final lang = Provider.of<AppSettingsProvider>(context).language;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Text(
          Localization.translate('لوحة استهلاك التخزين والذاكرة', lang),
          style: const TextStyle(
            fontFamily: 'Cairo',
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        centerTitle: true,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: Localization.translate('تحديث', lang),
            onPressed: () {
              _loadStorageData();
              if (_isAdmin) _loadAdminWorkshops();
            },
          ),
        ],
        bottom: _isAdmin
            ? TabBar(
                controller: _tabController,
                tabs: [
                  Tab(
                    icon: const Icon(Icons.pie_chart_outline_rounded, size: 20),
                    text: Localization.translate('استهلاك الورشة الحالية', lang),
                  ),
                  Tab(
                    icon: const Icon(Icons.storefront_outlined, size: 20),
                    text: Localization.translate('مقارنة كافة الورشات', lang),
                  ),
                ],
              )
            : null,
      ),
      body: _isAdmin
          ? TabBarView(
              controller: _tabController,
              children: [
                _buildCurrentWorkshopTab(lang, isDark),
                _buildAllWorkshopsTab(lang, isDark),
              ],
            )
          : _buildCurrentWorkshopTab(lang, isDark),
    );
  }

  Widget _buildCurrentWorkshopTab(AppLanguage lang, bool isDark) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final totalRecs = _totalRecords;
    final primaryColor = Theme.of(context).primaryColor;

    return RefreshIndicator(
      onRefresh: _loadStorageData,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header Stats Overview Cards
            Row(
              children: [
                Expanded(
                  child: _buildMetricCard(
                    title: Localization.translate('حجم قاعدة البيانات', lang),
                    value: _formatBytes(_dbFileSizeBytes),
                    subtitle: Localization.translate('الملف المحلي test.db', lang),
                    icon: Icons.storage_rounded,
                    color: const Color(0xFF2563EB),
                    isDark: isDark,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildMetricCard(
                    title: Localization.translate('إجمالي السجلات', lang),
                    value: NumberFormat('#,###').format(totalRecs),
                    subtitle: Localization.translate('سجل بيانات محلي', lang),
                    icon: Icons.table_chart_rounded,
                    color: const Color(0xFF10B981),
                    isDark: isDark,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Interactive Donut Chart Container
            Container(
              padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E293B) : Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(isDark ? 0.3 : 0.05),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        Localization.translate('توزيع استهلاك البيانات', lang),
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : const Color(0xFF1E293B),
                        ),
                      ),
                      if (_selectedCategoryIndex != -1)
                        TextButton.icon(
                          onPressed: () => setState(() => _selectedCategoryIndex = -1),
                          icon: const Icon(Icons.close_rounded, size: 16),
                          label: Text(
                            Localization.translate('إلغاء التحديد', lang),
                            style: const TextStyle(fontFamily: 'Cairo', fontSize: 12),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  // Donut Chart Graphic
                  SizedBox(
                    height: 220,
                    child: TweenAnimationBuilder<double>(
                      tween: Tween<double>(begin: 0.0, end: 1.0),
                      duration: const Duration(milliseconds: 900),
                      curve: Curves.easeOutCubic,
                      builder: (context, progress, child) {
                        return CustomPaint(
                          painter: _DonutChartPainter(
                            categories: _categories,
                            counts: _categoryCounts,
                            totalCount: totalRecs,
                            selectedIndex: _selectedCategoryIndex,
                            progress: progress,
                            isDark: isDark,
                          ),
                          child: Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (_selectedCategoryIndex != -1 &&
                                    _selectedCategoryIndex < _categories.length) ...[
                                  Text(
                                    lang == AppLanguage.french
                                        ? _categories[_selectedCategoryIndex].nameFr
                                        : _categories[_selectedCategoryIndex].nameAr,
                                    style: TextStyle(
                                      fontFamily: 'Cairo',
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: _categories[_selectedCategoryIndex].color,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${NumberFormat('#,###').format(_categoryCounts[_categories[_selectedCategoryIndex].key] ?? 0)}',
                                    style: TextStyle(
                                      fontFamily: 'Cairo',
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                      color: isDark ? Colors.white : Colors.black87,
                                    ),
                                  ),
                                  Text(
                                    totalRecs > 0
                                        ? '${(((_categoryCounts[_categories[_selectedCategoryIndex].key] ?? 0) / totalRecs) * 100).toStringAsFixed(1)}%'
                                        : '0%',
                                    style: TextStyle(
                                      fontFamily: 'Cairo',
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: isDark ? Colors.grey[400] : Colors.grey[600],
                                    ),
                                  ),
                                ] else ...[
                                  Text(
                                    _formatBytes(_dbFileSizeBytes),
                                    style: TextStyle(
                                      fontFamily: 'Cairo',
                                      fontSize: 22,
                                      fontWeight: FontWeight.bold,
                                      color: isDark ? Colors.white : const Color(0xFF0F172A),
                                    ),
                                  ),
                                  Text(
                                    Localization.translate('المساحة الإجمالية', lang),
                                    style: TextStyle(
                                      fontFamily: 'Cairo',
                                      fontSize: 11,
                                      color: isDark ? Colors.grey[400] : Colors.grey[500],
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 20),
                  // Quick Legend
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    alignment: WrapAlignment.center,
                    children: List.generate(_categories.length, (idx) {
                      final cat = _categories[idx];
                      final count = _categoryCounts[cat.key] ?? 0;
                      if (count == 0 && totalRecs > 0) return const SizedBox.shrink();
                      final isSelected = _selectedCategoryIndex == idx;
                      return GestureDetector(
                        onTap: () {
                          setState(() {
                            _selectedCategoryIndex = isSelected ? -1 : idx;
                          });
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? cat.color.withOpacity(0.18)
                                : (isDark ? Colors.white.withOpacity(0.04) : Colors.grey[100]),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: isSelected ? cat.color : Colors.transparent,
                              width: 1.5,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 10,
                                height: 10,
                                decoration: BoxDecoration(
                                  color: cat.color,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                lang == AppLanguage.french ? cat.nameFr : cat.nameAr,
                                style: TextStyle(
                                  fontFamily: 'Cairo',
                                  fontSize: 11,
                                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                  color: isDark ? Colors.white70 : Colors.black87,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Category Details List
            Text(
              Localization.translate('تفاصيل الفئات والأقسام', lang),
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : const Color(0xFF1E293B),
              ),
            ),
            const SizedBox(height: 12),
            ...List.generate(_categories.length, (idx) {
              final cat = _categories[idx];
              final count = _categoryCounts[cat.key] ?? 0;
              final pct = totalRecs > 0 ? (count / totalRecs) : 0.0;
              final isSelected = _selectedCategoryIndex == idx;

              return InkWell(
                onTap: () {
                  setState(() {
                    _selectedCategoryIndex = isSelected ? -1 : idx;
                  });
                },
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1E293B) : Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isSelected ? cat.color : Colors.transparent,
                      width: 1.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(isDark ? 0.2 : 0.03),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: cat.color.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(cat.icon, color: cat.color, size: 22),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  lang == AppLanguage.french ? cat.nameFr : cat.nameAr,
                                  style: TextStyle(
                                    fontFamily: 'Cairo',
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                    color: isDark ? Colors.white : const Color(0xFF1E293B),
                                  ),
                                ),
                                Text(
                                  '${(pct * 100).toStringAsFixed(1)}%',
                                  style: TextStyle(
                                    fontFamily: 'Cairo',
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                    color: cat.color,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: LinearProgressIndicator(
                                value: pct,
                                backgroundColor: isDark
                                    ? Colors.white.withOpacity(0.08)
                                    : Colors.grey[200],
                                valueColor: AlwaysStoppedAnimation<Color>(cat.color),
                                minHeight: 6,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  '${NumberFormat('#,###').format(count)} ${Localization.translate('سجل', lang)}',
                                  style: TextStyle(
                                    fontFamily: 'Cairo',
                                    fontSize: 12,
                                    color: isDark ? Colors.grey[400] : Colors.grey[600],
                                  ),
                                ),
                                if (_dbFileSizeBytes > 0)
                                  Text(
                                    '≈ ${_formatBytes((_dbFileSizeBytes * pct).round())}',
                                    style: TextStyle(
                                      fontFamily: 'Cairo',
                                      fontSize: 11,
                                      color: isDark ? Colors.grey[400] : Colors.grey[500],
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
            const SizedBox(height: 20),

            // Database Maintenance & Optimization Section
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E293B) : Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: primaryColor.withOpacity(0.2),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(isDark ? 0.3 : 0.05),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: primaryColor.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(Icons.build_circle_rounded, color: primaryColor, size: 22),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        Localization.translate('صيانة وتحسين التخزين', lang),
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : const Color(0xFF1E293B),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    Localization.translate(
                      'يساعد ضغط قاعدة البيانات (VACUUM) على استرجاع المساحات غير المستخدمة الناتجة عن عمليات الحذف والتعديل وتسريع أداء التطبيق.',
                      lang,
                    ),
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 12,
                      height: 1.5,
                      color: isDark ? Colors.grey[300] : Colors.grey[600],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: primaryColor,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          onPressed: _isOptimizing ? null : _runVacuum,
                          icon: _isOptimizing
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                  ),
                                )
                              : const Icon(Icons.speed_rounded, size: 20),
                          label: Text(
                            Localization.translate('ضغط وتحسين قاعدة البيانات', lang),
                            style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFFEF4444),
                          side: const BorderSide(color: Color(0xFFEF4444)),
                          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => TrashScreen(db: _db),
                            ),
                          ).then((_) => _loadStorageData());
                        },
                        icon: const Icon(Icons.auto_delete_rounded, size: 18),
                        label: Text(
                          Localization.translate('سلة المهملات', lang),
                          style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAllWorkshopsTab(AppLanguage lang, bool isDark) {
    if (_isLoadingAdminWorkshops) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_adminWorkshops.isEmpty) {
      return Center(
        child: Text(
          Localization.translate('لا توجد بيانات ورشات متاحة', lang),
          style: const TextStyle(fontFamily: 'Cairo'),
        ),
      );
    }

    // Group rows by workshop name
    final Map<String, List<Map<String, dynamic>>> grouped = {};
    for (final row in _adminWorkshops) {
      final name = (row['workshop_name'] ?? row['name'] ?? 'ورشة مجهولة').toString().trim();
      grouped.putIfAbsent(name.isEmpty ? 'ورشة مجهولة' : name, () => []).add(row);
    }

    final workshopNames = grouped.keys.toList();
    final colors = [
      const Color(0xFF2563EB),
      const Color(0xFF10B981),
      const Color(0xFFF59E0B),
      const Color(0xFF8B5CF6),
      const Color(0xFFEC4899),
      const Color(0xFF06B6D4),
      const Color(0xFF64748B),
    ];

    return RefreshIndicator(
      onRefresh: _loadAdminWorkshops,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: workshopNames.length + 1,
        itemBuilder: (context, index) {
          if (index == 0) {
            return Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E293B) : Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(isDark ? 0.3 : 0.05),
                    blurRadius: 10,
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    Localization.translate('مقارنة نشاط وحجم الورشات المشتركة', lang),
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${Localization.translate('إجمالي الورشات المسجلة: ', lang)}${workshopNames.length}',
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 13,
                      color: isDark ? Colors.grey[400] : Colors.grey[600],
                    ),
                  ),
                ],
              ),
            );
          }

          final wsName = workshopNames[index - 1];
          final members = grouped[wsName]!;
          final wsColor = colors[(index - 1) % colors.length];

          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            color: isDark ? const Color(0xFF1E293B) : Colors.white,
            elevation: 1.5,
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: wsColor.withOpacity(0.15),
                foregroundColor: wsColor,
                child: const Icon(Icons.storefront_rounded),
              ),
              title: Text(
                wsName,
                style: const TextStyle(
                  fontFamily: 'Cairo',
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
              subtitle: Text(
                '${Localization.translate('عدد المستخدمين المسجلين: ', lang)}${members.length}',
                style: const TextStyle(fontFamily: 'Cairo', fontSize: 12),
              ),
              trailing: Chip(
                backgroundColor: wsColor.withOpacity(0.12),
                label: Text(
                  'نشط',
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: wsColor,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildMetricCard({
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color color,
    required bool isDark,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.3 : 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 12,
                  color: isDark ? Colors.grey[400] : Colors.grey[600],
                ),
              ),
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 16, color: color),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            value,
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : const Color(0xFF1E293B),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 10,
              color: isDark ? Colors.grey[500] : Colors.grey[400],
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryMeta {
  final String key;
  final String nameAr;
  final String nameFr;
  final String nameEn;
  final IconData icon;
  final Color color;

  const _CategoryMeta({
    required this.key,
    required this.nameAr,
    required this.nameFr,
    required this.nameEn,
    required this.icon,
    required this.color,
  });

  String localizedName(AppLanguage lang) {
    switch (lang) {
      case AppLanguage.french:
        return nameFr;
      case AppLanguage.english:
        return nameEn;
      case AppLanguage.arabic:
        return nameAr;
    }
  }
}

class _DonutChartPainter extends CustomPainter {
  final List<_CategoryMeta> categories;
  final Map<String, int> counts;
  final int totalCount;
  final int selectedIndex;
  final double progress;
  final bool isDark;

  _DonutChartPainter({
    required this.categories,
    required this.counts,
    required this.totalCount,
    required this.selectedIndex,
    required this.progress,
    required this.isDark,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final outerRadius = math.min(size.width, size.height) / 2 - 8;
    final strokeWidth = outerRadius * 0.32;
    final radius = outerRadius - strokeWidth / 2;

    if (totalCount == 0) {
      final bgPaint = Paint()
        ..color = isDark ? Colors.white12 : Colors.grey[300]!
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth;
      canvas.drawCircle(center, radius, bgPaint);
      return;
    }

    double startAngle = -math.pi / 2;
    const double gapAngle = 0.035;

    for (int i = 0; i < categories.length; i++) {
      final cat = categories[i];
      final count = counts[cat.key] ?? 0;
      if (count <= 0) continue;

      final sweepAngle = (count / totalCount) * 2 * math.pi * progress;
      final effectiveSweep = math.max(0.0, sweepAngle - gapAngle);
      final isSelected = selectedIndex == i;

      final paint = Paint()
        ..color = cat.color
        ..style = PaintingStyle.stroke
        ..strokeWidth = isSelected ? strokeWidth + 6 : strokeWidth
        ..strokeCap = StrokeCap.round;

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle + gapAngle / 2,
        effectiveSweep,
        false,
        paint,
      );

      startAngle += sweepAngle;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutChartPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.selectedIndex != selectedIndex ||
        oldDelegate.totalCount != totalCount ||
        oldDelegate.isDark != isDark;
  }
}
