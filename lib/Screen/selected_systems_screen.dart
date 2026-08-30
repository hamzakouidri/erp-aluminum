import 'dart:async';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../sql_database.dart';
import '../settings/app_settings.dart';
import '../settings/localization.dart';
import '../services/cloud_sync_service.dart';

class SystemModeItem {
  final String id;
  final String title;
  final String subtitle;
  final String iconPath;
  final IconData defaultIcon;
  final String category;
  bool isActive;

  SystemModeItem({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.iconPath,
    required this.defaultIcon,
    required this.category,
    this.isActive = true,
  });
}

class ProfileSystemItem {
  final int id;
  final String code;
  final String name;
  final String type;
  final String? imagePath;
  bool isActive;

  ProfileSystemItem({
    required this.id,
    required this.code,
    required this.name,
    required this.type,
    this.imagePath,
    this.isActive = true,
  });
}

class SelectedSystemsScreen extends StatefulWidget {
  const SelectedSystemsScreen({super.key});

  @override
  State<SelectedSystemsScreen> createState() => _SelectedSystemsScreenState();
}

class _SelectedSystemsScreenState extends State<SelectedSystemsScreen>
    with SingleTickerProviderStateMixin {
  final SqlDatabase _db = SqlDatabase();
  final CloudSyncService _cloudSync = CloudSyncService();
  bool _isLoading = true;
  bool _isSyncing = false;
  String _searchQuery = '';
  late TabController _tabController;
  StreamSubscription<String>? _syncSubscription;

  List<SystemModeItem> _systemModes = [];
  List<ProfileSystemItem> _profileSystems = [];
  int? _maxSystemModes;
  int? _maxProfiles;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final settings = Provider.of<AppSettingsProvider>(context);
    if (!settings.isManager && !settings.canSelectSystems()) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && Navigator.canPop(context)) {
          Navigator.pop(context);
        }
      });
    }
  }

  final List<Map<String, dynamic>> _presetModes = [
    {
      'id': 'sliding',
      'titleAr': 'نظام الجرار',
      'titleFr': 'Système coulissant',
      'titleEn': 'Sliding system',
      'subtitleAr': 'نظام النوافذ والأبواب الجرارة 2/3/4 سكة',
      'subtitleFr': 'Système de fenêtres et portes coulissantes à 2/3/4 rails',
      'subtitleEn': '2/3/4-track sliding windows and doors system',
      'iconPath': 'Icon/sli.png',
      'defaultIcon': Icons.view_sidebar_rounded,
      'categoryAr': 'جرار',
      'categoryFr': 'Coulissant',
      'categoryEn': 'Sliding',
    },
    {
      'id': 'french',
      'titleAr': 'النظام الفرنسي',
      'titleFr': 'Système à frappe',
      'titleEn': 'Casement system',
      'subtitleAr': 'نظام الفتح الداخلي والخارجي والقلاب',
      'subtitleFr': 'Système à ouverture intérieure, extérieure et oscillo-battante',
      'subtitleEn': 'Inward, outward and tilt-turn opening system',
      'iconPath': 'Icon/french.png',
      'defaultIcon': Icons.door_front_door_rounded,
      'categoryAr': 'فرنسي',
      'categoryFr': 'À frappe',
      'categoryEn': 'Casement',
    },
    {
      'id': 'mixed',
      // Keep the internal id for compatibility with saved drawings. The
      // user-facing name is Conception (design), not "mixed system".
      'titleAr': 'التصميم',
      'titleFr': 'Conception',
      'titleEn': 'Design',
      'subtitleAr': 'صفحة الرسم والتصميم للنوافذ والأبواب',
      'subtitleFr': 'Page de dessin et de conception des fenêtres et portes',
      'subtitleEn': 'Window and door drawing and design page',
      'iconPath': 'Icon/french.png',
      'defaultIcon': Icons.dashboard_customize_rounded,
      'categoryAr': 'تصميم',
      'categoryFr': 'Conception',
      'categoryEn': 'Design',
    },
    {
      'id': 'rolling',
      'titleAr': 'الستار',
      'titleFr': 'Volet roulant',
      'titleEn': 'Roller shutter',
      'subtitleAr': 'أنظمة الستائر المتحركة والمحركات',
      'subtitleFr': 'Systèmes de volets roulants et motorisations',
      'subtitleEn': 'Roller shutter and motor systems',
      'iconPath': 'Icon/roling.png',
      'defaultIcon': Icons.blinds_rounded,
      'categoryAr': 'ستار',
      'categoryFr': 'Volet',
      'categoryEn': 'Shutter',
    },
    {
      'id': 'caisson_tunnel',
      'titleAr': 'صندوق التونيل',
      'titleFr': 'Caisson Tunnel',
      'titleEn': 'Tunnel box',
      'subtitleAr': 'صناديق الستار المدمجة في الجدار',
      'subtitleFr': 'Caissons de volet intégrés dans le mur',
      'subtitleEn': 'Roller shutter boxes built into the wall',
      'iconPath': 'Icon/caisson_tunnel.jpg',
      'defaultIcon': Icons.square_rounded,
      'categoryAr': 'تونيل',
      'categoryFr': 'Tunnel',
      'categoryEn': 'Tunnel',
    },
    {
      'id': 'moustiquaire',
      'titleAr': 'الناموسية',
      'titleFr': 'Moustiquaire',
      'titleEn': 'Insect screen',
      'subtitleAr': 'أنظمة ناموسية الحشرات (ملفوفة، مطوية أكورديون، ثابتة، ومنزلقة)',
      'subtitleFr': 'Systèmes moustiquaires (enroulables, plissés, fixes et coulissants)',
      'subtitleEn': 'Insect screen systems (roller, pleated, fixed and sliding)',
      'iconPath': 'Icon/media.webp',
      'defaultIcon': Icons.grid_4x4_rounded,
      'categoryAr': 'ناموسية',
      'categoryFr': 'Moustiquaire',
      'categoryEn': 'Screen',
    },
    {
      'id': 'precadre',
      'titleAr': 'إطار التثبيت الأولي',
      'titleFr': 'Pré-cadre',
      'titleEn': 'Pre-frame',
      'subtitleAr': 'إطارات الإخفاء والتجهيز قبل التركيب',
      'subtitleFr': 'Cadres de masquage et de préparation avant la pose',
      'subtitleEn': 'Concealment and preparation frames before installation',
      'iconPath': 'Icon/french.png',
      'defaultIcon': Icons.crop_square_rounded,
      'categoryAr': 'إطار أولي',
      'categoryFr': 'Pré-cadre',
      'categoryEn': 'Pre-frame',
    },
    {
      'id': 'verre',
      'titleAr': 'الزجاج المعالج',
      'titleFr': 'Verre trempé',
      'titleEn': 'Tempered glass',
      'subtitleAr': 'أنظمة الزجاج المقوى والواجهات',
      'subtitleFr': 'Systèmes de verre trempé et façades',
      'subtitleEn': 'Tempered glass and façade systems',
      'iconPath': 'Icon/verre.png',
      'defaultIcon': Icons.window_rounded,
      'categoryAr': 'زجاج',
      'categoryFr': 'Vitrage',
      'categoryEn': 'Glass',
    },
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadData();
    _syncSubscription = _cloudSync.dbUpdateStream.listen((event) {
      if (event != 'cloud_restored' || !mounted) return;
      // Realtime already applied the profile to local storage. Refresh only
      // this screen silently so the counters change without a page spinner.
      _loadData(showLoading: false);
    });
  }

  @override
  void dispose() {
    _syncSubscription?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  int? _readSelectionLimit(dynamic value) {
    final parsed = value is num
        ? value.toInt()
        : int.tryParse(value?.toString() ?? '');
    if (parsed == null || parsed >= 999) return null;
    return parsed.clamp(0, 999).toInt();
  }

  Future<void> _loadSubscriptionLimits() async {
    _maxSystemModes = null;
    _maxProfiles = null;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || isApplicationAdminEmail(user.email)) return;

    try {
      final userSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      final userData = userSnapshot.data() ?? <String, dynamic>{};
      final role = userData['role']?.toString().toLowerCase();
      final workshopId = userData['workshopId']?.toString().trim();
      final targetId = workshopId != null && workshopId.isNotEmpty
          ? workshopId
          : user.uid;
      final workshopSnapshot = await FirebaseFirestore.instance
          .collection('workshops')
          .doc(targetId)
          .get();
      final workshopData = <String, dynamic>{
        ...userData,
        ...?workshopSnapshot.data(),
      };

      _maxSystemModes = _readSelectionLimit(workshopData['maxSystems']);
      _maxProfiles = _readSelectionLimit(workshopData['maxProfiles']);
      debugPrint(
        'SelectedSystems limits loaded for $role/$targetId: '
        'systems=$_maxSystemModes profiles=$_maxProfiles',
      );
    } catch (error) {
      // Missing limits keep the old unrestricted behaviour.
      debugPrint('Could not load subscription system limits: $error');
    }
  }

  void _showSelectionLimitMessage(String label, int limit) {
    if (!mounted) return;
    final lang = Provider.of<AppSettingsProvider>(context, listen: false).language;
    final message = limit == 0
        ? 'لا توجد $label مفعلة في اشتراك هذه الورشة.'
        : 'يسمح اشتراك هذه الورشة بحد أقصى $limit من $label.';
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            Localization.translate(message, lang),
            style: const TextStyle(fontFamily: 'Cairo'),
          ),
        ),
      );
  }

  Future<void> _loadData({bool showLoading = true}) async {
    if (showLoading && mounted) setState(() => _isLoading = true);
    final prefs = await SharedPreferences.getInstance();
    await _loadSubscriptionLimits();
    final lang = Provider.of<AppSettingsProvider>(context, listen: false).language;
    final suffix = switch (lang) {
      AppLanguage.french => 'Fr',
      AppLanguage.english => 'En',
      AppLanguage.arabic => 'Ar',
    };

    // 1. Load System Modes preferences
    final List<SystemModeItem> loadedModes = [];
    for (var preset in _presetModes) {
      final id = preset['id'] as String;
      final isActive = prefs.getBool('system_active_$id') ?? true;
      loadedModes.add(
        SystemModeItem(
          id: id,
          title: preset['title$suffix'],
          subtitle: preset['subtitle$suffix'],
          iconPath: preset['iconPath'],
          defaultIcon: preset['defaultIcon'],
          category: preset['category$suffix'],
          isActive: isActive,
        ),
      );
    }

    // 2. Load Profile Systems from SQLite DB
    final List<ProfileSystemItem> loadedProfiles = [];
    try {
      final dbInstance = await _db.db;
      if (dbInstance != null) {
        final profileRows = await dbInstance.query(
          'Profile',
          orderBy: 'name ASC',
        );
        if (profileRows.isNotEmpty) {
          for (var row in profileRows) {
            loadedProfiles.add(
              ProfileSystemItem(
                id: row['id'] as int,
                code: (row['code']?.toString() ?? ''),
                name: (row['name']?.toString() ?? 'نظام غير معنون'),
                type: (row['type']?.toString() ?? 'Aluminium'),
                imagePath: row['image_path']?.toString(),
                isActive: ((row['is_active'] as int?) ?? 1) == 1,
              ),
            );
          }
        } else {
          // Fallback: Query Series if Profile table is empty
          final seriesRows = await dbInstance.query(
            'Series',
            orderBy: 'name ASC',
          );
          for (var row in seriesRows) {
            loadedProfiles.add(
              ProfileSystemItem(
                id: row['id'] as int,
                code: (row['code']?.toString() ?? ''),
                name: (row['name']?.toString() ?? 'سلسلة غير معنونة'),
                type: (row['type']?.toString() ?? 'Aluminium'),
                imagePath: row['image_path']?.toString(),
                isActive: ((row['is_active'] as int?) ?? 1) == 1,
              ),
            );
          }
        }
      }
    } catch (e) {
      debugPrint('Error loading Profile/Series table: $e');
    }

    // If the administrator reduced a subscription limit, disable only the
    // excess selections locally before publishing the corrected selection.
    if (_maxSystemModes != null) {
      final overflowModes = loadedModes
          .where((mode) => mode.isActive)
          .skip(_maxSystemModes!)
          .toList();
      for (final mode in overflowModes) {
        mode.isActive = false;
        await prefs.setBool('system_active_${mode.id}', false);
      }
    }
    if (_maxProfiles != null) {
      final overflowProfiles = loadedProfiles
          .where((profile) => profile.isActive)
          .skip(_maxProfiles!)
          .toList();
      if (overflowProfiles.isNotEmpty) {
        final dbInstance = await _db.db;
        for (final profile in overflowProfiles) {
          profile.isActive = false;
          await dbInstance?.update(
            'Profile',
            {'is_active': 0},
            where: 'id = ?',
            whereArgs: [profile.id],
          );
          await dbInstance?.update(
            'Series',
            {'is_active': 0},
            where: 'profile_id = ? OR id = ?',
            whereArgs: [profile.id, profile.id],
          );
        }
      }
    }

    if (mounted) {
      setState(() {
        _systemModes = loadedModes;
        _profileSystems = loadedProfiles;
        _isLoading = false;
      });
    }
  }

  Future<void> _toggleSystemMode(SystemModeItem item, bool newValue) async {
    if (newValue &&
        _maxSystemModes != null &&
        _systemModes.where((mode) => mode.isActive).length >=
            _maxSystemModes!) {
      _showSelectionLimitMessage('أنظمة العمل', _maxSystemModes!);
      return;
    }
    setState(() => item.isActive = newValue);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('system_active_${item.id}', newValue);
    // ✅ حفظ في السحابة
    await _syncToCloud();
    if (!mounted) return;
    final lang = Provider.of<AppSettingsProvider>(
      context,
      listen: false,
    ).language;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          newValue
              ? '${Localization.translate("تم تفعيل", lang)} ${item.title}'
              : '${Localization.translate("تم إيقاف", lang)} ${item.title}',
          style: const TextStyle(fontFamily: 'Cairo'),
        ),
        duration: const Duration(seconds: 2),
        backgroundColor: newValue
            ? Colors.green.shade700
            : Colors.orange.shade800,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _toggleProfileItem(ProfileSystemItem item, bool newValue) async {
    if (newValue &&
        _maxProfiles != null &&
        _profileSystems.where((profile) => profile.isActive).length >=
            _maxProfiles!) {
      _showSelectionLimitMessage('البروفيلات', _maxProfiles!);
      return;
    }
    setState(() => item.isActive = newValue);
    try {
      final dbInstance = await _db.db;
      if (dbInstance != null) {
        // 1. Update Profile table
        await dbInstance.update(
          'Profile',
          {'is_active': newValue ? 1 : 0},
          where: 'id = ?',
          whereArgs: [item.id],
        );
        // 2. Also update any child Series linked to this profile_id
        await dbInstance.update(
          'Series',
          {'is_active': newValue ? 1 : 0},
          where: 'profile_id = ? OR id = ?',
          whereArgs: [item.id, item.id],
        );
      }
    } catch (e) {
      debugPrint('Error updating Profile/Series is_active: $e');
    }
    // ✅ حفظ في السحابة
    await _syncToCloud();
    if (!mounted) return;
    final lang = Provider.of<AppSettingsProvider>(
      context,
      listen: false,
    ).language;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          newValue
              ? '${Localization.translate("تم تفعيل النظام", lang)}: ${item.name}'
              : '${Localization.translate("تم إيقاف النظام", lang)}: ${item.name}',
          style: const TextStyle(fontFamily: 'Cairo'),
        ),
        duration: const Duration(seconds: 2),
        backgroundColor: newValue
            ? Colors.green.shade700
            : Colors.orange.shade800,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _setAllModes(bool enable) async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      var enabledCount = 0;
      for (var mode in _systemModes) {
        final canEnable = _maxSystemModes == null ||
            enabledCount < _maxSystemModes!;
        mode.isActive = enable && canEnable;
        if (mode.isActive) enabledCount++;
        prefs.setBool('system_active_${mode.id}', mode.isActive);
      }
    });
    await _syncToCloud();
  }

  // ✅ مساعد: يجمع الحالة الحالية ويرسلها للسحابة
  Future<void> _syncToCloud() async {
    final systemModes = {for (var m in _systemModes) m.id: m.isActive};
    if (_maxSystemModes != null) {
      final activeModes = _systemModes.where((mode) => mode.isActive).toList();
      for (final mode in activeModes.skip(_maxSystemModes!)) {
        systemModes[mode.id] = false;
      }
    }
    final activeProfileIds = _profileSystems
        .where((p) => p.isActive)
        .map((p) => p.id)
        .take(_maxProfiles ?? _profileSystems.length)
        .toList();
    await _cloudSync.saveWorkshopSystems(
      systemModes: systemModes,
      activeProfileIds: activeProfileIds,
    );
  }

  // ✅ جلب الإعدادات من السحابة (للعمال أو المدير على جهاز آخر)
  Future<void> _pullFromCloud() async {
    setState(() => _isSyncing = true);
    await _cloudSync.loadAndApplyWorkshopSystems();
    await _loadData();
    if (!mounted) return;
    setState(() => _isSyncing = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          Localization.translate(
            'تم تحديث الأنظمة من السحابة',
            Provider.of<AppSettingsProvider>(context, listen: false).language,
          ),
          style: const TextStyle(fontFamily: 'Cairo'),
        ),
        backgroundColor: Colors.teal,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _setAllProfiles(bool enable) async {
    var enabledCount = 0;
    setState(() {
      for (var p in _profileSystems) {
        final canEnable = _maxProfiles == null ||
            enabledCount < _maxProfiles!;
        p.isActive = enable && canEnable;
        if (p.isActive) enabledCount++;
      }
    });
    try {
      final dbInstance = await _db.db;
      if (dbInstance != null) {
        await dbInstance.update('Profile', {'is_active': 0});
        await dbInstance.update('Series', {'is_active': 0});
        if (enable) {
          for (final profile in _profileSystems.where((p) => p.isActive)) {
            await dbInstance.update(
              'Profile',
              {'is_active': 1},
              where: 'id = ?',
              whereArgs: [profile.id],
            );
            await dbInstance.update(
              'Series',
              {'is_active': 1},
              where: 'profile_id = ? OR id = ?',
              whereArgs: [profile.id, profile.id],
            );
          }
        }
      }
    } catch (e) {
      debugPrint('Error bulk updating Profiles/Series: $e');
    }
    // Keep the visibility choice identical for every user of this workshop.
    await _syncToCloud();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final lang = Provider.of<AppSettingsProvider>(context).language;

    final filteredModes = _systemModes.where((m) {
      if (_searchQuery.isEmpty) return true;
      final q = _searchQuery.toLowerCase();
      return m.title.toLowerCase().contains(q) ||
          m.subtitle.toLowerCase().contains(q) ||
          m.category.toLowerCase().contains(q);
    }).toList();

    final filteredProfiles = _profileSystems.where((p) {
      if (_searchQuery.isEmpty) return true;
      final q = _searchQuery.toLowerCase();
      return p.name.toLowerCase().contains(q) ||
          p.code.toLowerCase().contains(q) ||
          p.type.toLowerCase().contains(q);
    }).toList();

    final activeModesCount = _systemModes.where((m) => m.isActive).length;
    final activeProfilesCount = _profileSystems.where((p) => p.isActive).length;

    return Scaffold(
      backgroundColor: isDark
          ? const Color(0xFF121212)
          : const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: Text(
          Localization.translate('تحديد الأنظمة المستعملة', lang),
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontFamily: 'Cairo',
          ),
        ),
        centerTitle: true,
        elevation: 0,
        backgroundColor: isDark
            ? Theme.of(context).appBarTheme.backgroundColor
            : Colors.blue.shade700,
        foregroundColor: Colors.white,
        actions: [
          // زر المزامنة من السحابة (مدير أو عامل)
          _isSyncing
              ? const Padding(
                  padding: EdgeInsets.all(12),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  ),
                )
              : IconButton(
                  icon: const Icon(Icons.cloud_download_rounded),
                  tooltip: Localization.translate('مزامنة من السحابة', lang),
                  onPressed: _pullFromCloud,
                ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.amberAccent,
          indicatorWeight: 3,
          labelStyle: const TextStyle(
            fontFamily: 'Cairo',
            fontWeight: FontWeight.bold,
            fontSize: 14,
          ),
          unselectedLabelStyle: const TextStyle(
            fontFamily: 'Cairo',
            fontSize: 13,
          ),
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: [
            Tab(
              icon: const Icon(Icons.dashboard_customize_rounded),
              text:
                  '${Localization.translate("أنظمة العمل", lang)} ($activeModesCount/${_systemModes.length})',
            ),
            Tab(
              icon: const Icon(Icons.view_in_ar_rounded),
              text:
                  '${Localization.translate("أنظمة الألمنيوم", lang)} ($activeProfilesCount/${_profileSystems.length})',
            ),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Top Summary Header Card
                Container(
                  padding: const EdgeInsets.all(14.0),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(
                          alpha: isDark ? 0.2 : 0.05,
                        ),
                        blurRadius: 6,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      // Search Bar
                      TextField(
                        onChanged: (val) => setState(() => _searchQuery = val),
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                        decoration: InputDecoration(
                          hintText: Localization.translate(
                            'بحث عن نظام أو بروفيل...',
                            lang,
                          ),
                          hintStyle: TextStyle(
                            fontFamily: 'Cairo',
                            color: isDark
                                ? Colors.white38
                                : Colors.grey.shade500,
                          ),
                          prefixIcon: Icon(
                            Icons.search,
                            color: isDark ? Colors.blue.shade300 : Colors.blue,
                          ),
                          suffixIcon: _searchQuery.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear),
                                  onPressed: () =>
                                      setState(() => _searchQuery = ''),
                                )
                              : null,
                          filled: true,
                          fillColor: isDark
                              ? const Color(0xFF2C2C2C)
                              : Colors.grey.shade100,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),

                      if (_maxSystemModes != null || _maxProfiles != null)
                        Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: Text(
                            'حد الاشتراك: '
                            'أنظمة العمل ${_maxSystemModes ?? "بلا حدود"}، '
                            'بروفيلات ${_maxProfiles ?? "بلا حدود"}',
                            style: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: isDark
                                  ? Colors.amber.shade300
                                  : Colors.indigo.shade700,
                            ),
                          ),
                        ),
                      if (_maxSystemModes != null || _maxProfiles != null)
                        const SizedBox(height: 10),

                      // Quick Control Action Buttons
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                side: BorderSide(
                                  color: isDark
                                      ? Colors.blue.shade400
                                      : Colors.blue,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 8,
                                ),
                              ),
                              icon: const Icon(
                                Icons.check_circle_outline_rounded,
                                size: 18,
                              ),
                              label: Text(
                                Localization.translate('تفعيل الكل', lang),
                                style: const TextStyle(
                                  fontFamily: 'Cairo',
                                  fontSize: 12,
                                ),
                              ),
                              onPressed: () {
                                if (_tabController.index == 0) {
                                  _setAllModes(true);
                                } else {
                                  _setAllProfiles(true);
                                }
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                side: BorderSide(
                                  color: isDark
                                      ? Colors.orange.shade400
                                      : Colors.orange,
                                ),
                                foregroundColor: isDark
                                    ? Colors.orange.shade300
                                    : Colors.orange.shade900,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 8,
                                ),
                              ),
                              icon: const Icon(Icons.cancel_outlined, size: 18),
                              label: Text(
                                Localization.translate('إلغاء الكل', lang),
                                style: const TextStyle(
                                  fontFamily: 'Cairo',
                                  fontSize: 12,
                                ),
                              ),
                              onPressed: () {
                                if (_tabController.index == 0) {
                                  _setAllModes(false);
                                } else {
                                  _setAllProfiles(false);
                                }
                              },
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // Main Tab Bar Views
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      // Tab 1: System Modes
                      _buildModesTab(filteredModes, isDark, lang),

                      // Tab 2: Profile Systems
                      _buildProfilesTab(filteredProfiles, isDark, lang),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildModesTab(
    List<SystemModeItem> modes,
    bool isDark,
    AppLanguage lang,
  ) {
    if (modes.isEmpty) {
      return Center(
        child: Text(
          Localization.translate('لا توجد أنظمة مطابقة للبحث', lang),
          style: TextStyle(
            fontFamily: 'Cairo',
            color: isDark ? Colors.white60 : Colors.grey.shade600,
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: modes.length,
      itemBuilder: (context, index) {
        final item = modes[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 10),
          elevation: item.isActive ? 2 : 0,
          color: isDark
              ? (item.isActive
                    ? const Color(0xFF1E1E1E)
                    : const Color(0xFF161616))
              : (item.isActive ? Colors.white : Colors.grey.shade100),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(
              color: item.isActive
                  ? (isDark ? Colors.blue.shade700 : Colors.blue.shade200)
                  : (isDark ? Colors.grey.shade800 : Colors.grey.shade300),
              width: item.isActive ? 1.5 : 1.0,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                // Icon avatar
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: item.isActive
                        ? (isDark
                              ? Colors.blue.shade900.withValues(alpha: 0.5)
                              : Colors.blue.shade50)
                        : (isDark
                              ? Colors.grey.shade800
                              : Colors.grey.shade200),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(
                    child: Image.asset(
                      item.iconPath,
                      width: 32,
                      height: 32,
                      errorBuilder: (context, error, stackTrace) => Icon(
                        item.defaultIcon,
                        color: item.isActive
                            ? (isDark
                                  ? Colors.blue.shade300
                                  : Colors.blue.shade700)
                            : Colors.grey,
                        size: 26,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 14),

                // Title and subtitle
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              item.title,
                              style: TextStyle(
                                fontFamily: 'Cairo',
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                                color: item.isActive
                                    ? (isDark ? Colors.white : Colors.black87)
                                    : (isDark
                                          ? Colors.white38
                                          : Colors.grey.shade600),
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: item.isActive
                                  ? (isDark
                                        ? Colors.blue.shade900
                                        : Colors.blue.shade100)
                                  : Colors.grey.shade300,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              item.category,
                              style: TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: item.isActive
                                    ? (isDark
                                          ? Colors.blue.shade200
                                          : Colors.blue.shade800)
                                    : Colors.grey.shade700,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        item.subtitle,
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 12,
                          color: isDark ? Colors.white60 : Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),

                // Switch
                Switch(
                  value: item.isActive,
                  activeColor: Colors.blue.shade600,
                  onChanged: (val) => _toggleSystemMode(item, val),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildProfilesTab(
    List<ProfileSystemItem> profiles,
    bool isDark,
    AppLanguage lang,
  ) {
    if (profiles.isEmpty) {
      return Center(
        child: Text(
          Localization.translate(
            'لا توجد أنظمة ألمنيوم مسجلة أو مطابقة للبحث',
            lang,
          ),
          style: TextStyle(
            fontFamily: 'Cairo',
            color: isDark ? Colors.white60 : Colors.grey.shade600,
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: profiles.length,
      itemBuilder: (context, index) {
        final item = profiles[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 10),
          elevation: item.isActive ? 2 : 0,
          color: isDark
              ? (item.isActive
                    ? const Color(0xFF1E1E1E)
                    : const Color(0xFF161616))
              : (item.isActive ? Colors.white : Colors.grey.shade100),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(
              color: item.isActive
                  ? (isDark ? Colors.teal.shade700 : Colors.teal.shade200)
                  : (isDark ? Colors.grey.shade800 : Colors.grey.shade300),
              width: item.isActive ? 1.5 : 1.0,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: item.isActive
                        ? (isDark
                              ? Colors.teal.shade900.withValues(alpha: 0.5)
                              : Colors.teal.shade50)
                        : (isDark
                              ? Colors.grey.shade800
                              : Colors.grey.shade200),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.view_in_ar_rounded,
                    color: item.isActive
                        ? (isDark ? Colors.teal.shade300 : Colors.teal.shade700)
                        : Colors.grey,
                    size: 26,
                  ),
                ),
                const SizedBox(width: 14),

                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              item.name,
                              style: TextStyle(
                                fontFamily: 'Cairo',
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                                color: item.isActive
                                    ? (isDark ? Colors.white : Colors.black87)
                                    : (isDark
                                          ? Colors.white38
                                          : Colors.grey.shade600),
                              ),
                            ),
                          ),
                          if (item.code.isNotEmpty) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: isDark
                                    ? Colors.blueGrey.shade800
                                    : Colors.blueGrey.shade100,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                item.code,
                                style: TextStyle(
                                  fontFamily: 'Cairo',
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: isDark
                                      ? Colors.blueGrey.shade200
                                      : Colors.blueGrey.shade800,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? Colors.grey.shade800
                                  : Colors.grey.shade200,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '${Localization.translate("نوع", lang)}: ${item.type}',
                              style: TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 11,
                                color: isDark
                                    ? Colors.white70
                                    : Colors.grey.shade700,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            item.isActive
                                ? Localization.translate('مفعل بالورشة', lang)
                                : Localization.translate('معطل', lang),
                            style: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: item.isActive ? Colors.green : Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                Switch(
                  value: item.isActive,
                  activeColor: Colors.teal.shade600,
                  onChanged: (val) => _toggleProfileItem(item, val),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
