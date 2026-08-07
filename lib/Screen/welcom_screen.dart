import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import '../Cliente/client.dart';
import '../Commande/commande.dart';
import '../items_produits/products_menu_screen.dart';
import '../sql_database.dart';
import 'projects_screen.dart';
import 'drawer.dart';
import 'settings_screen.dart';
import 'reports_hub_screen.dart';
import 'treasury_screen.dart';
import 'app_workspace_shell.dart';
import 'package:provider/provider.dart';
import '../settings/app_settings.dart';
import '../settings/localization.dart';
import '../services/cloud_sync_service.dart';
import 'suppliers_screen.dart';
import 'achat_screen.dart';
import 'inventory_screen.dart';
import 'measurements_screen.dart';
import 'worker_tasks_screen.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'external_operations_hub_screen.dart';

import 'worker_archive_screen.dart';

bool get _isWindowsDesktop =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

class WelcomScreen extends StatefulWidget {
  final bool embeddedInWorkspace;

  const WelcomScreen({super.key, this.embeddedInWorkspace = false});

  @override
  State<WelcomScreen> createState() => _WelcomScreenState();
}

class _WelcomScreenState extends State<WelcomScreen> {
  final SqlDatabase db = SqlDatabase();
  final ValueNotifier<Map<String, dynamic>?> _dragNotifier = ValueNotifier<Map<String, dynamic>?>(null);

  static Offset _getCardCenter(String id) {
    if (id.startsWith('stat_')) {
      final index = int.parse(id.split('_')[1]);
      return Offset(40.0 + index * 120.0, 0.0);
    } else if (id.startsWith('nav_')) {
      final index = int.parse(id.split('_')[1]);
      final row = index ~/ 3;
      final col = index % 3;
      return Offset(40.0 + col * 120.0, 150.0 + row * 115.0);
    }
    return Offset.zero;
  }

  // ── Palette ───────────────────────────────────────────────────────────────
  static const _blue = Color(0xFF3B82F6);
  static const _cyan = Color(0xFF06B6D4);
  static const _amber = Color(0xFFF59E0B);
  static const _green = Color(0xFF10B981);
  static const _purple = Color(0xFF8B5CF6);

  String _workshopName = 'ورشة النجارة';
  String _userEmail = 'جاري التحميل...';
  String _workshopPhone = '';
  String? _logoUrl;
  ImageProvider? _cachedLogoProvider; // الصورة المحسوبة مرة واحدة لتجنب الترميش
  StreamSubscription? _userSub;
  StreamSubscription<String>? _databaseUpdateSub;
  Timer? _statsDebounce; // debounce لمنع تكرار _loadStats خلال ms قصيرة

  // إحصائيات
  String _commandesCount = '—';
  String _cmdTrend = '';
  String _clientsCount = '—';
  String _cliTrend = '';
  String _produitsCount = '—';

  // تنبيهات الطلبات والمخزون
  int _lowStockCount = 0;
  List<Map<String, dynamic>> _lowStockItems = [];
  int _newOrdersCount = 0;

  // Desktop dashboard data.  These values are loaded from the same local
  // database that is kept in sync with Firebase, so the Windows view never
  // needs a separate source of truth.
  List<Map<String, dynamic>> _desktopOrders = [];
  double _treasuryBalance = 0.0;
  int _activeWorkersCount = 0;
  int _workersCount = 0;
  int _pendingOrdersCount = 0;

  Future<void> _markOrdersAsRead() async {
    try {
      final allCmds = await db.readCommande();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('last_seen_orders_count', allCmds.length);
      if (mounted) {
        setState(() {
          _newOrdersCount = 0;
        });
      }
    } catch (e) {
      debugPrint("Error marking orders read: $e");
    }
  }

  // بيانات المخطط البياني
  Map<String, int> _ordersByStatus = {};
  Map<String, int> _ordersByMonth = {};

  @override
  void initState() {
    super.initState();
    _loadUserData();
    _loadStats();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        await CloudSyncService().init();
        await CloudSyncService().refreshFromCloudIfChanged();
        if (mounted) {
          _loadStats();
        }
      } catch (e) {
        debugPrint('WelcomScreen cloud refresh notice: $e');
      }
    });
  }

  /// تحديث صورة الشعار فقط عند تغيير فعلي لتجنب إعادة فك التشفير في كل rebuild
  void _updateLogo(String? newUrl) {
    if (newUrl == _logoUrl) return; // لم يتغير شيء → لا نعيد البناء
    _logoUrl = newUrl;
    _cachedLogoProvider = null;
    if (newUrl != null && newUrl.isNotEmpty) {
      if (newUrl.startsWith('http')) {
        _cachedLogoProvider = NetworkImage(newUrl);
      } else {
        try {
          final bytes = base64Decode(newUrl);
          if (bytes.isNotEmpty) _cachedLogoProvider = MemoryImage(bytes);
        } catch (_) {}
      }
    }
  }

  Future<void> _checkLowStock() async {
    try {
      final locations = await db.readLocations();
      final List<Map<String, dynamic>> allLowStock = [];
      final Set<String> uniqueKeys = {};

      for (var loc in locations) {
        final locId = loc['id'] as int;
        final stockData = await db.readCurrentStock(locId);
        for (var item in stockData) {
          final quantity = (item['quantity'] as num?)?.toDouble() ?? 0.0;
          final minQty = (item['min_qty'] as num?)?.toDouble() ?? 0.0;
          if (minQty > 0 && quantity <= minQty) {
            final key = "${item['item_id']}_${item['item_type']}_${item['color_id']}";
            if (!uniqueKeys.contains(key)) {
              uniqueKeys.add(key);
              allLowStock.add(item);
            }
          }
        }
      }

      if (mounted) {
        setState(() {
          _lowStockItems = allLowStock;
          _lowStockCount = allLowStock.length;
        });
      }
    } catch (e) {
      debugPrint("Error checking low stock: $e");
    }
  }

  void _showLowStockNotifications(BuildContext context) {
    final lang = Provider.of<AppSettingsProvider>(context, listen: false).language;
    showDialog(
      context: context,
      builder: (context) {
        final screenWidth = MediaQuery.of(context).size.width;
        final isDark = Theme.of(context).brightness == Brightness.dark;
        
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          backgroundColor: isDark ? Color(0xFF1E293B) : Theme.of(context).cardColor,
          title: Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.orange.shade800, size: 28),
              const SizedBox(width: 8),
              Text(
                Localization.translate('تنبيهات المخزون', lang),
                style: const TextStyle(
                  fontFamily: 'Cairo',
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: screenWidth > 600 ? 500 : double.maxFinite,
            child: _lowStockItems.isEmpty
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.check_circle_outline_rounded, color: Colors.green, size: 64),
                      const SizedBox(height: 16),
                      Text(
                        Localization.translate('كل الكميات متوفرة بشكل جيد ولا توجد نواقص!', lang),
                        style: const TextStyle(fontFamily: 'Cairo', fontSize: 14),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade50.withValues(alpha: isDark ? 0.05 : 1.0),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.orange.shade200.withValues(alpha: isDark ? 0.3 : 1.0)),
                        ),
                        child: Text(
                          Localization.translate('العناصر التالية وصلت للحد الأدنى أو نفذت من المخزون، يرجى إعادة طلبها قريباً:', lang),
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 12,
                            color: isDark ? Colors.orange.shade300 : Colors.orange.shade900,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Flexible(
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: _lowStockItems.length,
                          itemBuilder: (context, index) {
                            final item = _lowStockItems[index];
                            final name = item['item_name'] as String;
                            final type = item['item_type'] as String;
                            final color = item['color_name'] as String;
                            final qty = (item['quantity'] as num).toDouble();
                            final min = (item['min_qty'] as num?)?.toDouble() ?? 0.0;
                            
                            return Card(
                              margin: const EdgeInsets.symmetric(vertical: 4),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              elevation: 0,
                              color: isDark ? const Color(0xFF334155) : Colors.grey.shade50,
                              child: ListTile(
                                dense: true,
                                leading: CircleAvatar(
                                  backgroundColor: Colors.orange.shade100.withValues(alpha: isDark ? 0.2 : 1.0),
                                  child: Icon(Icons.inventory_2_rounded, color: Colors.orange.shade800, size: 20),
                                ),
                                title: Text(
                                  name,
                                  style: const TextStyle(
                                    fontFamily: 'Cairo',
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                  ),
                                ),
                                subtitle: Text(
                                  '${Localization.translate(type, lang)} ${color.isNotEmpty ? "- ${Localization.translate(color, lang)}" : ""}',
                                  style: const TextStyle(fontFamily: 'Cairo', fontSize: 11),
                                ),
                                trailing: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      '${Localization.translate('الرصيد', lang)}: ${qty.toStringAsFixed(qty.truncateToDouble() == qty ? 0 : 2)}',
                                      style: TextStyle(
                                        fontFamily: 'Cairo',
                                        fontWeight: FontWeight.w900,
                                        fontSize: 13,
                                        color: qty <= 0 ? Colors.red : Colors.orange.shade800,
                                      ),
                                    ),
                                    Text(
                                      '${Localization.translate('الحد الأدنى', lang)}: ${min.toStringAsFixed(min.truncateToDouble() == min ? 0 : 2)}',
                                      style: const TextStyle(fontFamily: 'Cairo', fontSize: 9, color: Colors.grey),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                Localization.translate('إغلاق', lang),
                style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _loadStats() async {
    try {
      final dashboardData = await Future.wait<dynamic>([
        db.getDashboardStats(),
        db.readProfile(),
        db.getOrderStatusStats(),
        db.readCommande(),
        db.readCommandesWithClients(),
        db.readTreasury(),
        db.readEmployees(),
      ]);
      final stats = dashboardData[0] as Map<String, dynamic>;
      final profiles = dashboardData[1] as List<Map<String, dynamic>>;
      final chartData = dashboardData[2] as Map<String, dynamic>;
      final allCmds = dashboardData[3] as List<Map<String, dynamic>>;
      final desktopOrders = List<Map<String, dynamic>>.from(
        dashboardData[4] as List<Map<String, dynamic>>,
      );
      final treasuryRows = dashboardData[5] as List<Map<String, dynamic>>;
      final employees = dashboardData[6] as List<Map<String, dynamic>>;
      final prefs = await SharedPreferences.getInstance();
      final lastCmdCount = prefs.getInt('last_seen_orders_count');
      int unreadOrders = 0;
      if (lastCmdCount == null) {
        await prefs.setInt('last_seen_orders_count', allCmds.length);
        unreadOrders = 0;
      } else {
        unreadOrders = allCmds.length > lastCmdCount ? (allCmds.length - lastCmdCount) : 0;
      }
      if (mounted) {
        setState(() {
          _newOrdersCount = unreadOrders;
          _commandesCount = stats['cmdCount'] ?? '0';
          _cmdTrend = stats['cmdTrend'] ?? '—';
          _clientsCount = stats['cliCount'] ?? '0';
          _cliTrend = stats['cliTrend'] ?? '—';
          _produitsCount = profiles.length.toString();
          _ordersByStatus = Map<String, int>.from(
            (chartData['byStatus'] as Map<String, int>?) ?? {},
          );
          _ordersByMonth = Map<String, int>.from(
            (chartData['monthly'] as Map<String, int>?) ?? {},
          );
          _desktopOrders = desktopOrders;
          _treasuryBalance = _calculateTreasuryBalance(treasuryRows);
          _workersCount = employees.length;
          _activeWorkersCount = employees.where(_isActiveEmployee).length;
          _pendingOrdersCount = desktopOrders.where(_isOpenOrder).length;
        });
      }
      await _checkLowStock();
    } catch (e) {
      debugPrint("Error loading stats: $e");
    }
  }

  bool _isActiveEmployee(Map<String, dynamic> employee) {
    final active = employee['is_active'];
    if (active is num) return active != 0;
    if (active is bool) return active;
    if (active != null) {
      final value = active.toString().trim().toLowerCase();
      if (value == 'false' || value == '0' || value == 'inactive') return false;
    }
    return true;
  }

  bool _isOpenOrder(Map<String, dynamic> order) {
    final status = (order['status'] ?? '').toString().trim().toLowerCase();
    return !{
      'done',
      'completed',
      'complete',
      'archived',
      'finished',
      'منتهية',
      'مكتملة',
      'أرشيف',
    }.contains(status);
  }

  double _calculateTreasuryBalance(List<Map<String, dynamic>> rows) {
    double balance = 0.0;
    for (final row in rows) {
      final type = (row['transaction_type'] ?? '').toString().toLowerCase();
      final amount = (row['amount'] as num?)?.toDouble() ?? 0.0;
      final isExpense = type == 'expense' ||
          type.contains('décaissement') ||
          type.contains('decaissement') ||
          type.contains('achat') ||
          type.contains('purchase');
      balance += isExpense ? -amount : amount;
    }
    return balance;
  }

  Future<void> _loadUserData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      await _userSub?.cancel();
      setState(() {
        _userEmail = user.email ?? 'لا يوجد بريد';
      });
      _userSub = FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .snapshots()
          .listen((doc) {
            if (doc.exists && mounted) {
              final data = doc.data() as Map<String, dynamic>;
              SharedPreferences.getInstance().then((prefs) {
                if (!mounted) return;
                final savedName = prefs.getString('workshop_name');
                final savedLogo = prefs.getString('workshop_logo_base64');
                final newLogoUrl = (data['workshopLogoUrl'] as String?)?.isNotEmpty == true
                    ? data['workshopLogoUrl']
                    : savedLogo;
                setState(() {
                  _workshopName = (data['workshopName'] as String?)?.isNotEmpty == true
                      ? data['workshopName']
                      : (savedName?.isNotEmpty == true ? savedName! : 'ورشة النجارة');
                  _workshopPhone = data['phone'] ?? data['phoneNumber'] ?? '';
                  if (data['email'] != null) {
                    _userEmail = data['email'];
                  }
                  _updateLogo(newLogoUrl); // تحديث مخبأ فقط عند تغيير فعلي
                });
              });
            }
          });

      // SubscriptionChecker owns the global Firestore listeners.  This page
      // only listens to local update notifications so navigating away cannot
      // stop synchronization for the whole app.
      await CloudSyncService().init();

      // استماع التحديثات المحلية مع debounce لمنع تكرار البناء خلال مليسثانية فقيرة
      await _databaseUpdateSub?.cancel();
      _databaseUpdateSub = CloudSyncService().dbUpdateStream.listen((_) {
        if (!mounted) return;
        _statsDebounce?.cancel();
        _statsDebounce = Timer(const Duration(milliseconds: 300), () {
          if (mounted) {
            Provider.of<AppSettingsProvider>(context, listen: false).reloadPermissions();
            _loadStats();
          }
        });
      });
    }
  }

  bool _isManualSyncing = false;

  Future<void> _autoSyncData({bool showSnackBar = false}) async {
    if (_isManualSyncing) return;
    if (mounted) setState(() => _isManualSyncing = true);
    if (showSnackBar && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('جاري تنزيل وتحديث كافة بيانات الورشة والطلبات من السحابة... ⏳', style: TextStyle(fontFamily: 'Cairo')),
          duration: Duration(seconds: 2),
          backgroundColor: Colors.blue,
        ),
      );
    }
    try {
      await CloudSyncService().fullRecoverySync();
      if (mounted) {
        await Provider.of<AppSettingsProvider>(context, listen: false).reloadPermissions();
        await _loadStats();
        if (showSnackBar) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('تم تنزيل وتحديث البيانات والطلبات من السحابة بنجاح 🔄', style: TextStyle(fontFamily: 'Cairo')),
              duration: Duration(seconds: 2),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Auto sync data error: $e');
      if (showSnackBar && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'تعذرت المزامنة: ${e.toString().replaceAll('Exception: ', '')}',
              style: const TextStyle(fontFamily: 'Cairo'),
            ),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isManualSyncing = false);
    }
  }

  @override
  void dispose() {
    _userSub?.cancel();
    _databaseUpdateSub?.cancel();
    _statsDebounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<AppSettingsProvider>(context);
    final lang = settings.language;
    final double screenWidth = MediaQuery.sizeOf(context).width;
    final double dashboardPadding = _isWindowsDesktop
        ? (screenWidth > 1488 ? (screenWidth - 1440) / 2 : 24)
        : 16;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        // التحقق من أننا في الشاشة الرئيسية فعلاً (لا يوجد مسار سابق)
        final navigator = Navigator.of(context);
        if (navigator.canPop()) {
          // يوجد شاشة سابقة — نعود إليها
          navigator.pop();
          return;
        }
        // نحن في أسفل الـ stack — نسأل المستخدم إذا أراد الخروج
        final shouldExit = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Text(
              lang == AppLanguage.arabic
                  ? 'الخروج من التطبيق'
                  : lang == AppLanguage.french
                      ? 'Quitter l\'application'
                      : 'Exit App',
              style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold),
            ),
            content: Text(
              lang == AppLanguage.arabic
                  ? 'هل تريد الخروج من التطبيق؟'
                  : lang == AppLanguage.french
                      ? 'Voulez-vous quitter l\'application ?'
                      : 'Do you want to exit the application?',
              style: const TextStyle(fontFamily: 'Cairo'),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: Text(
                  lang == AppLanguage.arabic ? 'لا' : lang == AppLanguage.french ? 'Non' : 'No',
                  style: const TextStyle(fontFamily: 'Cairo'),
                ),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
                child: Text(
                  lang == AppLanguage.arabic ? 'خروج' : lang == AppLanguage.french ? 'Quitter' : 'Exit',
                  style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        );
        if (shouldExit == true) {
          await SystemNavigator.pop();
        }
      },
      child: Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        drawer: AppDrawer(),
        body: Stack(
          children: [
            if (!_isWindowsDesktop)
              Positioned.fill(
                child: _WaterWaveBackground(enabled: settings.enablePremiumAnimations),
              ),
            RefreshIndicator(
              onRefresh: _autoSyncData,
              color: Colors.blue,
              child: _isWindowsDesktop
                  ? _buildDesktopDashboard(context)
                  : CustomScrollView(
              slivers: [
              _buildSliverHeader(context),
              SliverPadding(
                padding: EdgeInsets.fromLTRB(dashboardPadding, 0, dashboardPadding, 32),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    // ── إحصائيات ────────────────────────────────────────
                    _buildStatsRow(context),
                    const SizedBox(height: 24),

                    // ── عنوان القسم ──────────────────────────────────────
                    _sectionLabel(Localization.translate('التنقل السريع', lang)),
                    const SizedBox(height: 12),

                    // ── شبكة التنقل ──────────────────────────────────────
                    _buildMeasurementCard(context),
                    const SizedBox(height: 12),
                    _buildNavGrid(context),
                    const SizedBox(height: 24),

                    // ── مخطط الطلبيات ─────────────────────────────────
                    _sectionLabel(Localization.translate('تحليل الطلبيات', lang)),
                    const SizedBox(height: 12),
                    _OrdersChartCard(
                      byStatus: _ordersByStatus,
                      byMonth: _ordersByMonth,
                    ),

                   ]),
                ),
              ),
            ],
          ),
            ),
        ],
      ),
    ), // end Scaffold
    ); // end PopScope
  }

  // ── SliverAppBar ──────────────────────────────────────────────────────────
  String _desktopText(AppLanguage lang, String arabic, String french, String english) {
    if (lang == AppLanguage.arabic) return arabic;
    if (lang == AppLanguage.french) return french;
    return english;
  }

  Widget _buildDesktopDashboard(BuildContext context) {
    final settings = Provider.of<AppSettingsProvider>(context);
    final lang = settings.language;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final pageColor = isDark ? const Color(0xFF0F172A) : Colors.white;
    final cardColor = isDark ? const Color(0xFF172033) : Colors.white;
    final contentColor = isDark ? const Color(0xFFE5E7EB) : const Color(0xFF17233A);
    final mutedColor = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);

    return Container(
      color: pageColor,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(24, 22, 24, 36),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1440),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LayoutBuilder(
                  builder: (context, constraints) {
                    final narrow = constraints.maxWidth < 660;
                    final title = Row(
                      children: [
                        Container(
                          width: 50,
                          height: 50,
                          decoration: BoxDecoration(
                            color: const Color(0xFF2563EB).withOpacity(0.10),
                            borderRadius: BorderRadius.circular(14),
                            image: _cachedLogoProvider == null
                                ? null
                                : DecorationImage(
                                    image: _cachedLogoProvider!,
                                    fit: BoxFit.cover,
                                  ),
                          ),
                          child: _cachedLogoProvider == null
                              ? const Icon(
                                  Icons.carpenter_rounded,
                                  color: Color(0xFF2563EB),
                                  size: 25,
                                )
                              : null,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _workshopName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: contentColor,
                                  fontFamily: 'Cairo',
                                  fontSize: 17,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              Text(
                                _desktopText(lang, 'لوحة التحكم', 'Tableau de bord', 'Dashboard'),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: mutedColor,
                                  fontFamily: 'Cairo',
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                    final refresh = FilledButton.icon(
                      onPressed: _isManualSyncing
                          ? null
                          : () => _autoSyncData(showSnackBar: true),
                      icon: _isManualSyncing
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.sync_rounded, size: 18),
                      label: Text(
                        _desktopText(lang, 'تحديث البيانات', 'Actualiser', 'Refresh data'),
                        style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w700),
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF2563EB),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                      ),
                    );
                    if (narrow) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [title, const SizedBox(height: 14), refresh],
                      );
                    }
                    return Row(
                      children: [Expanded(child: title), refresh],
                    );
                  },
                ),
                const SizedBox(height: 22),
                _buildDesktopMetrics(context, cardColor, contentColor, mutedColor),
                const SizedBox(height: 18),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final sideWidth = 290.0;
                    final isCompact = constraints.maxWidth < 980;
                    final orders = _buildDesktopOrdersPanel(context, cardColor, contentColor, mutedColor);
                    final side = Column(
                      children: [
                        _buildDesktopWorkloadPanel(context, cardColor, contentColor, mutedColor),
                        const SizedBox(height: 16),
                        _buildDesktopActivityPanel(context, cardColor, contentColor, mutedColor),
                      ],
                    );
                    if (isCompact) {
                      return Column(children: [orders, const SizedBox(height: 16), side]);
                    }
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: orders),
                        const SizedBox(width: 16),
                        SizedBox(width: sideWidth, child: side),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 18),
                _buildDesktopLowStockPanel(context, cardColor, contentColor, mutedColor),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDesktopMetrics(
    BuildContext context,
    Color cardColor,
    Color contentColor,
    Color mutedColor,
  ) {
    final settings = Provider.of<AppSettingsProvider>(context);
    final lang = settings.language;
    final values = _ordersByMonth.values.map((value) => value.toDouble()).toList();
    final cards = <Widget>[
      if (settings.canViewOrders())
        _DesktopMetricCard(
          icon: Icons.receipt_long_rounded,
          title: _desktopText(lang, 'إجمالي الطلبيات', 'Total des commandes', 'Total orders'),
          value: _commandesCount,
          caption: _cmdTrend.isEmpty ? _desktopText(lang, 'كل الطلبيات', 'Toutes les commandes', 'All orders') : _cmdTrend,
          color: const Color(0xFF2563EB),
          values: values,
          backgroundColor: cardColor,
          textColor: contentColor,
          mutedColor: mutedColor,
          onTap: _openOrders,
        ),
      if (settings.canAccessTreasury())
        _DesktopMetricCard(
          icon: Icons.account_balance_wallet_rounded,
          title: _desktopText(lang, 'رصيد الخزينة', 'Solde de trésorerie', 'Treasury balance'),
          value: _formatCurrency(_treasuryBalance),
          caption: _desktopText(lang, 'المتاح حالياً', 'Disponible actuellement', 'Available now'),
          color: const Color(0xFF0EA5A4),
          values: values,
          backgroundColor: cardColor,
          textColor: contentColor,
          mutedColor: mutedColor,
          onTap: () => openAdaptiveScreen(
            context,
            title: _desktopText(lang, 'الخزينة', 'Trésorerie', 'Treasury'),
            icon: Icons.account_balance_wallet_rounded,
            screen: TreasuryScreen(db: db),
          ),
        ),
      _DesktopMetricCard(
        icon: Icons.groups_rounded,
        title: _desktopText(lang, 'العاملون النشطون', 'Employés actifs', 'Active workers'),
        value: _activeWorkersCount.toString(),
        caption: _workersCount == 0
            ? _desktopText(lang, 'لا يوجد عاملون مسجلون', 'Aucun employé enregistré', 'No registered workers')
            : _desktopText(lang, 'من أصل $_workersCount عامل', 'sur $_workersCount employés', 'of $_workersCount workers'),
        color: const Color(0xFF8B5CF6),
        values: values,
        backgroundColor: cardColor,
        textColor: contentColor,
        mutedColor: mutedColor,
        onTap: settings.canViewMyTasks()
            ? () => openAdaptiveScreen(
                  context,
                  title: _desktopText(lang, 'مهامي وتصنيعاتي', 'Mes tâches', 'My tasks'),
                  icon: Icons.assignment_turned_in_rounded,
                  screen: WorkerTasksScreen(db: db),
                )
            : null,
      ),
      if (settings.canViewOrders())
        _DesktopMetricCard(
          icon: Icons.pending_actions_rounded,
          title: _desktopText(lang, 'طلبيات مفتوحة', 'Commandes ouvertes', 'Open orders'),
          value: _pendingOrdersCount.toString(),
          caption: _desktopText(lang, 'تحتاج إلى متابعة', 'À suivre', 'Need follow-up'),
          color: const Color(0xFFF59E0B),
          values: values,
          backgroundColor: cardColor,
          textColor: contentColor,
          mutedColor: mutedColor,
          onTap: _openOrders,
        ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 16.0;
        final columns = constraints.maxWidth >= 1180 ? 4 : constraints.maxWidth >= 660 ? 2 : 1;
        final width = (constraints.maxWidth - ((columns - 1) * gap)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [for (final card in cards) SizedBox(width: width, child: card)],
        );
      },
    );
  }

  Widget _buildDesktopOrdersPanel(
    BuildContext context,
    Color cardColor,
    Color contentColor,
    Color mutedColor,
  ) {
    final lang = Provider.of<AppSettingsProvider>(context).language;
    return _desktopPanel(
      context: context,
      title: _desktopText(lang, 'متابعة الطلبيات', 'Suivi des commandes', 'Orders tracking'),
      subtitle: _desktopText(lang, 'أحدث الطلبيات المسجلة', 'Dernières commandes enregistrées', 'Latest recorded orders'),
      icon: Icons.table_rows_rounded,
      color: const Color(0xFF2563EB),
      backgroundColor: cardColor,
      textColor: contentColor,
      mutedColor: mutedColor,
      action: TextButton.icon(
        onPressed: _openOrders,
        icon: const Icon(Icons.arrow_forward_rounded, size: 16),
        label: Text(_desktopText(lang, 'كل الطلبيات', 'Tout voir', 'View all'), style: const TextStyle(fontFamily: 'Cairo')),
      ),
      child: SizedBox(
        height: 318,
        child: _desktopOrders.isEmpty
            ? Center(
                child: Text(
                  _desktopText(lang, 'لا توجد طلبيات بعد', 'Aucune commande pour le moment', 'No orders yet'),
                  style: TextStyle(fontFamily: 'Cairo', color: mutedColor),
                ),
              )
            : Column(
                children: [
                  _desktopOrderHeader(contentColor, mutedColor, lang),
                  const SizedBox(height: 4),
                  Expanded(
                    child: ListView.separated(
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: math.min(6, _desktopOrders.length),
                      separatorBuilder: (_, __) => Divider(height: 1, color: mutedColor.withOpacity(0.18)),
                      itemBuilder: (context, index) => _desktopOrderRow(
                        context,
                        _desktopOrders[index],
                        contentColor,
                        mutedColor,
                        lang,
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _desktopOrderHeader(Color contentColor, Color mutedColor, AppLanguage lang) {
    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF2563EB).withOpacity(0.07),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          _desktopTableCell(_desktopText(lang, 'الطلبية', 'Commande', 'Order'), 2, mutedColor, true),
          _desktopTableCell(_desktopText(lang, 'الزبون', 'Client', 'Customer'), 3, mutedColor, true),
          _desktopTableCell(_desktopText(lang, 'التاريخ', 'Date', 'Date'), 2, mutedColor, true),
          _desktopTableCell(_desktopText(lang, 'الحالة', 'Statut', 'Status'), 2, mutedColor, true),
          _desktopTableCell(_desktopText(lang, 'التقدم', 'Progression', 'Progress'), 3, mutedColor, true),
        ],
      ),
    );
  }

  Widget _desktopOrderRow(
    BuildContext context,
    Map<String, dynamic> order,
    Color contentColor,
    Color mutedColor,
    AppLanguage lang,
  ) {
    final status = (order['status'] ?? 'Pending').toString();
    final color = _desktopStatusColor(status);
    final firstName = (order['firstname'] ?? '').toString().trim();
    final lastName = (order['lastname'] ?? '').toString().trim();
    final clientName = '$firstName $lastName'.trim();
    final orderId = order['id']?.toString() ?? '—';
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _openOrders,
        child: SizedBox(
          height: 43,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                _desktopTableCell('#$orderId', 2, contentColor, false, colorOverride: const Color(0xFF2563EB)),
                _desktopTableCell(
                  clientName.isEmpty ? _desktopText(lang, 'زبون', 'Client', 'Customer') : clientName,
                  3,
                  contentColor,
                  false,
                ),
                _desktopTableCell(_formatDate(order['created_at']), 2, mutedColor, false),
                Expanded(
                  flex: 2,
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(color: color.withOpacity(0.13), borderRadius: BorderRadius.circular(12)),
                      child: Text(
                        _desktopStatusText(status, lang),
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w800, fontFamily: 'Cairo'),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: Padding(
                    padding: const EdgeInsetsDirectional.only(start: 16),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: LinearProgressIndicator(
                        value: _desktopStatusProgress(status),
                        minHeight: 6,
                        backgroundColor: mutedColor.withOpacity(0.16),
                        valueColor: AlwaysStoppedAnimation<Color>(color),
                      ),
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

  Widget _desktopTableCell(String text, int flex, Color color, bool isHeader, {Color? colorOverride}) {
    return Expanded(
      flex: flex,
      child: Text(
        text,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: colorOverride ?? color,
          fontFamily: 'Cairo',
          fontSize: isHeader ? 10 : 11,
          fontWeight: isHeader ? FontWeight.w700 : FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildDesktopWorkloadPanel(
    BuildContext context,
    Color cardColor,
    Color contentColor,
    Color mutedColor,
  ) {
    final lang = Provider.of<AppSettingsProvider>(context).language;
    final total = _desktopOrders.length;
    final completed = math.max(0, total - _pendingOrdersCount);
    final rate = total == 0 ? 0.0 : completed / total;
    return _desktopPanel(
      context: context,
      title: _desktopText(lang, 'حالة سير العمل', 'État du travail', 'Work progress'),
      icon: Icons.track_changes_rounded,
      color: const Color(0xFF0EA5E9),
      backgroundColor: cardColor,
      textColor: contentColor,
      mutedColor: mutedColor,
      child: SizedBox(
        height: 168,
        child: Row(
          children: [
            SizedBox(
              width: 104,
              height: 104,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CircularProgressIndicator(
                    value: rate,
                    strokeWidth: 9,
                    backgroundColor: mutedColor.withOpacity(0.14),
                    valueColor: const AlwaysStoppedAnimation(Color(0xFF06B6D4)),
                  ),
                  Center(
                    child: Text(
                      '${(rate * 100).round()}%',
                      style: TextStyle(color: contentColor, fontWeight: FontWeight.w800, fontSize: 18),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _desktopText(lang, '$completed مكتملة', '$completed terminées', '$completed completed'),
                    style: TextStyle(fontFamily: 'Cairo', color: contentColor, fontWeight: FontWeight.w800, fontSize: 15),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    _desktopText(lang, 'من أصل $total طلبية', 'sur $total commandes', 'out of $total orders'),
                    style: TextStyle(fontFamily: 'Cairo', color: mutedColor, fontSize: 11),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _desktopText(lang, '$_activeWorkersCount عامل نشط', '$_activeWorkersCount employés actifs', '$_activeWorkersCount active workers'),
                    style: const TextStyle(fontFamily: 'Cairo', color: Color(0xFF0EA5A4), fontSize: 11, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDesktopActivityPanel(
    BuildContext context,
    Color cardColor,
    Color contentColor,
    Color mutedColor,
  ) {
    final lang = Provider.of<AppSettingsProvider>(context).language;
    final entries = _ordersByMonth.values.map((value) => value.toDouble()).toList();
    return _desktopPanel(
      context: context,
      title: _desktopText(lang, 'نشاط الطلبيات', 'Activité des commandes', 'Order activity'),
      icon: Icons.show_chart_rounded,
      color: const Color(0xFF2563EB),
      backgroundColor: cardColor,
      textColor: contentColor,
      mutedColor: mutedColor,
      child: SizedBox(
        height: 138,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _DesktopSparkline(values: entries, color: const Color(0xFF2563EB), fill: true)),
            const SizedBox(height: 6),
            Text(
              _desktopText(lang, 'الستة أشهر الأخيرة', 'Six derniers mois', 'Last six months'),
              style: TextStyle(fontFamily: 'Cairo', color: mutedColor, fontSize: 10),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDesktopLowStockPanel(
    BuildContext context,
    Color cardColor,
    Color contentColor,
    Color mutedColor,
  ) {
    final settings = Provider.of<AppSettingsProvider>(context);
    final lang = settings.language;
    return _desktopPanel(
      context: context,
      title: _desktopText(lang, 'تنبيهات المخزون', 'Alertes de stock', 'Inventory alerts'),
      subtitle: _lowStockCount == 0
          ? _desktopText(lang, 'المخزون ضمن الحدود الآمنة', 'Le stock est dans les limites sûres', 'Stock levels are within safe limits')
          : _desktopText(lang, '$_lowStockCount عناصر تحتاج إلى متابعة', '$_lowStockCount éléments à suivre', '$_lowStockCount items need attention'),
      icon: Icons.inventory_2_rounded,
      color: _lowStockCount == 0 ? const Color(0xFF10B981) : const Color(0xFFF97316),
      backgroundColor: cardColor,
      textColor: contentColor,
      mutedColor: mutedColor,
      action: settings.canAccessInventory()
          ? TextButton.icon(
              onPressed: () => openAdaptiveScreen(
                context,
                title: _desktopText(lang, 'المخزون', 'Stock', 'Inventory'),
                icon: Icons.warehouse_rounded,
                screen: InventoryScreen(db: db),
              ),
              icon: const Icon(Icons.open_in_new_rounded, size: 15),
              label: Text(_desktopText(lang, 'فتح المخزون', 'Ouvrir le stock', 'Open inventory'), style: const TextStyle(fontFamily: 'Cairo')),
            )
          : null,
      child: _lowStockItems.isEmpty
          ? SizedBox(
              height: 68,
              child: Row(
                children: [
                  const Icon(Icons.verified_rounded, color: Color(0xFF10B981), size: 28),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _desktopText(lang, 'لا يوجد أي نقص في المواد ذات حد التنبيه.', 'Aucun manque dans les articles suivis.', 'No low-stock items need attention.'),
                      style: TextStyle(fontFamily: 'Cairo', color: mutedColor, fontSize: 12),
                    ),
                  ),
                ],
              ),
            )
          : LayoutBuilder(
              builder: (context, constraints) {
                final items = _lowStockItems.take(4).toList();
                final columns = constraints.maxWidth >= 900 ? 4 : constraints.maxWidth >= 540 ? 2 : 1;
                const gap = 10.0;
                final itemWidth = (constraints.maxWidth - ((columns - 1) * gap)) / columns;
                return Wrap(
                  spacing: gap,
                  runSpacing: gap,
                  children: [
                    for (final item in items)
                      SizedBox(
                        width: itemWidth,
                        child: _desktopStockItem(item, contentColor, mutedColor, lang),
                      ),
                  ],
                );
              },
            ),
    );
  }

  Widget _desktopStockItem(Map<String, dynamic> item, Color contentColor, Color mutedColor, AppLanguage lang) {
    final quantity = (item['quantity'] as num?)?.toDouble() ?? 0.0;
    final minQuantity = (item['min_qty'] as num?)?.toDouble() ?? 0.0;
    final name = (item['item_name'] ?? item['name'] ?? _desktopText(lang, 'عنصر', 'Article', 'Item')).toString();
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF97316).withOpacity(0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFF97316).withOpacity(0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.warning_amber_rounded, color: Color(0xFFF97316), size: 17),
              const SizedBox(width: 6),
              Expanded(
                child: Text(name, overflow: TextOverflow.ellipsis, style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w800, color: contentColor, fontSize: 12)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            _desktopText(lang, 'الرصيد: ${_formatQuantity(quantity)} / الحد: ${_formatQuantity(minQuantity)}', 'Solde : ${_formatQuantity(quantity)} / min. : ${_formatQuantity(minQuantity)}', 'Stock: ${_formatQuantity(quantity)} / min: ${_formatQuantity(minQuantity)}'),
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontFamily: 'Cairo', color: mutedColor, fontSize: 10),
          ),
        ],
      ),
    );
  }

  Widget _desktopPanel({
    required BuildContext context,
    required String title,
    String? subtitle,
    required IconData icon,
    required Color color,
    required Color backgroundColor,
    required Color textColor,
    required Color mutedColor,
    required Widget child,
    Widget? action,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isDark ? Colors.white.withOpacity(0.08) : const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.18 : 0.055),
            blurRadius: 16,
            offset: const Offset(0, 5),
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
                decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(10)),
                child: Icon(icon, color: color, size: 19),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, overflow: TextOverflow.ellipsis, style: TextStyle(fontFamily: 'Cairo', color: textColor, fontSize: 14, fontWeight: FontWeight.w800)),
                    if (subtitle != null)
                      Text(subtitle, overflow: TextOverflow.ellipsis, style: TextStyle(fontFamily: 'Cairo', color: mutedColor, fontSize: 10)),
                  ],
                ),
              ),
              if (action != null) action,
            ],
          ),
          const SizedBox(height: 13),
          child,
        ],
      ),
    );
  }

  void _openOrders() {
    final lang = Provider.of<AppSettingsProvider>(context, listen: false).language;
    _markOrdersAsRead();
    openAdaptiveScreen(
      context,
      title: _desktopText(lang, 'الطلبيات', 'Commandes', 'Orders'),
      icon: Icons.receipt_long_rounded,
      screen: const Commande(),
    );
  }

  String _formatCurrency(double value) {
    final sign = value < 0 ? '-' : '';
    final text = value.abs().round().toString();
    final buffer = StringBuffer();
    for (var index = 0; index < text.length; index++) {
      if (index > 0 && (text.length - index) % 3 == 0) buffer.write(' ');
      buffer.write(text[index]);
    }
    return '$sign${buffer.toString()} دج';
  }

  String _formatQuantity(double value) => value == value.roundToDouble() ? value.toInt().toString() : value.toStringAsFixed(2);

  String _formatDate(dynamic raw) {
    final date = DateTime.tryParse((raw ?? '').toString());
    if (date == null) return '—';
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }

  double _desktopStatusProgress(String value) {
    switch (value.trim().toLowerCase()) {
      case 'pending':
      case 'draft':
      case 'new':
        return 0.12;
      case 'confirmed':
        return 0.25;
      case 'in progress':
        return 0.45;
      case 'partial manufacturing':
        return 0.60;
      case 'full manufacturing':
        return 0.72;
      case 'partial distribution':
        return 0.82;
      case 'full distribution':
        return 0.90;
      case 'installation':
      case 'reserve':
        return 0.95;
      case 'done':
      case 'completed':
      case 'finished':
        return 1.0;
      default:
        return 0.2;
    }
  }

  Color _desktopStatusColor(String status) {
    final progress = _desktopStatusProgress(status);
    if (progress >= 1) return const Color(0xFF10B981);
    if (progress >= 0.80) return const Color(0xFF06B6D4);
    if (progress >= 0.45) return const Color(0xFF2563EB);
    return const Color(0xFFF59E0B);
  }

  String _desktopStatusText(String status, AppLanguage lang) {
    final normalized = status.trim().toLowerCase();
    final values = <String, List<String>>{
      'pending': ['قيد الانتظار', 'En attente', 'Pending'],
      'draft': ['مسودة', 'Brouillon', 'Draft'],
      'new': ['جديدة', 'Nouvelle', 'New'],
      'confirmed': ['مؤكدة', 'Confirmée', 'Confirmed'],
      'in progress': ['قيد التنفيذ', 'En cours', 'In progress'],
      'partial manufacturing': ['تصنيع جزئي', 'Fabrication partielle', 'Partial manufacturing'],
      'full manufacturing': ['تم التصنيع', 'Fabrication terminée', 'Manufactured'],
      'partial distribution': ['توزيع جزئي', 'Distribution partielle', 'Partial distribution'],
      'full distribution': ['تم التوزيع', 'Distribution terminée', 'Distributed'],
      'installation': ['تركيب', 'Installation', 'Installation'],
      'reserve': ['تحفّظ', 'Réserve', 'Reserve'],
      'done': ['مكتملة', 'Terminée', 'Completed'],
      'completed': ['مكتملة', 'Terminée', 'Completed'],
      'finished': ['مكتملة', 'Terminée', 'Completed'],
    };
    final translated = values[normalized];
    if (translated == null) return status;
    return lang == AppLanguage.arabic ? translated[0] : lang == AppLanguage.french ? translated[1] : translated[2];
  }

  Widget _buildSliverHeader(BuildContext context) {
    final isDesktop = _isWindowsDesktop;
    return SliverAppBar(
      expandedHeight: isDesktop ? 132 : 180,
      pinned: true,
      backgroundColor: Theme.of(context).brightness == Brightness.dark
          ? Theme.of(context).appBarTheme.backgroundColor
          : const Color(0xFF2563EB),
      surfaceTintColor: Colors.transparent,
      leading: _isWindowsDesktop
          ? null
          : Builder(
              builder: (ctx) => IconButton(
                icon: const Icon(Icons.menu_rounded, color: Colors.white),
                onPressed: () => Scaffold.of(ctx).openDrawer(),
              ),
            ),
      actions: [
        _isManualSyncing
            ? const Padding(
                padding: EdgeInsets.all(12),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                ),
              )
            : IconButton(
                icon: const Icon(Icons.sync_rounded, color: Colors.white),
                tooltip: 'تحديث ومزامنة البيانات والمهام من السحابة',
                onPressed: () => _autoSyncData(showSnackBar: true),
              ),
        Stack(
          alignment: Alignment.center,
          children: [
            IconButton(
              icon: Icon(
                (_lowStockCount + _newOrdersCount) > 0
                    ? Icons.notifications_active_rounded
                    : Icons.notifications_none_rounded,
                color: (_lowStockCount + _newOrdersCount) > 0 ? Colors.amberAccent : Colors.white,
              ),
              onPressed: () async {
                await _markOrdersAsRead();
                if (context.mounted) {
                  _showLowStockNotifications(context);
                }
              },
            ),
            if ((_lowStockCount + _newOrdersCount) > 0)
              Positioned(
                top: 8,
                right: 8,
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: Colors.red,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  constraints: const BoxConstraints(
                    minWidth: 16,
                    minHeight: 16,
                  ),
                  child: Text(
                    '${_lowStockCount + _newOrdersCount}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Cairo',
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(width: 4),
      ],
      flexibleSpace: FlexibleSpaceBar(
        background: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: Theme.of(context).brightness == Brightness.dark ? [Color(0xFF111827), Color(0xFF070E1D)] : [Color(0xFF2563EB), Color(0xFF0EA5E9)], begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Stack(
            children: [
              // دوائر زخرفية
              Positioned(
                right: -30,
                top: -30,
                child: Container(
                  width: 160,
                  height: 160,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Theme.of(context).cardColor.withValues(alpha: 0.10),
                  ),
                ),
              ),
              Positioned(
                right: 40,
                top: 20,
                child: Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Theme.of(context).cardColor.withValues(alpha: 0.08),
                  ),
                ),
              ),
              // المحتوى
              Padding(
                padding: EdgeInsets.fromLTRB(20, isDesktop ? 52 : 70, 20, 20),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    // أفاتار الشركة
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: Theme.of(context).brightness == Brightness.dark
                              ? [Color(0xFF111827), Color(0xFF070E1D)]
                              : [_blue, _cyan],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(14),
                        image: _cachedLogoProvider != null
                            ? DecorationImage(
                                image: _cachedLogoProvider!,
                                fit: BoxFit.cover,
                              )
                            : null,
                        boxShadow: [
                          BoxShadow(
                            color: _blue.withValues(alpha: 0.4),
                            blurRadius: 16,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: _cachedLogoProvider == null
                          ? const Icon(
                              Icons.carpenter_rounded,
                              color: Colors.white,
                              size: 28,
                            )
                          : null,
                    ),
                    const SizedBox(width: 14),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _workshopName,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.4,
                            fontFamily: 'Cairo',
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _userEmail,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.8),
                            fontSize: 13,
                            fontFamily: 'Cairo',
                          ),
                        ),
                        if (_workshopPhone.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              Icon(
                                Icons.phone_rounded,
                                size: 12,
                                color: Colors.white.withValues(alpha: 0.8),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                _workshopPhone,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.8),
                                  fontSize: 12,
                                  fontFamily: 'Cairo',
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                    const Spacer(),
                    // بادج الحالة
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: _green.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: _green.withValues(alpha: 0.4),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: _green,
                            ),
                          ),
                          const SizedBox(width: 5),
                          Text(
                            'Actif',
                            style: TextStyle(
                              color: _green,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        title: isDesktop
            ? null
            : Text(
                _workshopName,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
        titlePadding: const EdgeInsets.only(left: 56, bottom: 14),
        collapseMode: CollapseMode.pin,
      ),
    );
  }

  // ── صف الإحصائيات ────────────────────────────────────────────────────────
  Widget _buildStatsRow(BuildContext context) {
    final lang = Provider.of<AppSettingsProvider>(context).language;
    final settings = Provider.of<AppSettingsProvider>(context);
    final ordersLabel = lang == AppLanguage.arabic
        ? 'الطلبيات'
        : Localization.translate('commandes', lang);
    final clientsLabel = lang == AppLanguage.arabic
        ? 'الزبائن'
        : Localization.translate('clients', lang);
    final productsLabel = lang == AppLanguage.arabic
        ? 'المنتجات'
        : Localization.translate('produits', lang);

    final cards = <Widget>[];

    void addCard({
      required IconData icon,
      required String label,
      required String value,
      required Color color,
      required String trend,
    }) {
      cards.add(
        _StatCard(
          icon: icon,
          label: label,
          value: value,
          color: color,
          trend: trend,
          index: cards.length,
          dragNotifier: _dragNotifier,
        ),
      );
    }

    if (settings.canViewOrders()) {
      addCard(
        icon: Icons.receipt_long_rounded,
        label: ordersLabel,
        value: _commandesCount,
        color: _blue,
        trend: _cmdTrend,
      );
    }

    if (settings.canViewClients()) {
      addCard(
        icon: Icons.people_alt_rounded,
        label: clientsLabel,
        value: _clientsCount,
        color: _purple,
        trend: _cliTrend,
      );
    }

    addCard(
      icon: Icons.inventory_2_rounded,
      label: productsLabel,
      value: _produitsCount,
      color: _amber,
      trend: '—',
    );

    if (_isWindowsDesktop) {
      addCard(
        icon: Icons.warning_amber_rounded,
        label: lang == AppLanguage.arabic
            ? 'تنبيهات المخزون'
            : (lang == AppLanguage.french ? 'Alertes de stock' : 'Stock alerts'),
        value: _lowStockCount.toString(),
        color: _lowStockCount > 0 ? Colors.deepOrange : _green,
        trend: _lowStockCount > 0
            ? (lang == AppLanguage.arabic ? 'يحتاج متابعة' : 'Needs attention')
            : (lang == AppLanguage.arabic ? 'المخزون مستقر' : 'Stock is stable'),
      );

      return LayoutBuilder(
        builder: (context, constraints) {
          const gap = 16.0;
          final targetColumns = constraints.maxWidth >= 1200 ? 4 : 3;
          final columns = cards.length < targetColumns
              ? cards.length
              : targetColumns;
          final cardWidth =
              (constraints.maxWidth - ((columns - 1) * gap)) / columns;
          return Wrap(
            spacing: gap,
            runSpacing: gap,
            children: [
              for (final card in cards)
                SizedBox(width: cardWidth, child: card),
            ],
          );
        },
      );
    }

    return Row(
      children: [
        for (var index = 0; index < cards.length; index++) ...[
          Expanded(child: cards[index]),
          if (index != cards.length - 1) const SizedBox(width: 12),
        ],
      ],
    );
  }

  // ── بطاقة رفع القياسات الذكية كاملة العرض ─────────────────────────────────────
  Widget _buildMeasurementCard(BuildContext context) {
    final settings = Provider.of<AppSettingsProvider>(context);
    if (!settings.canAccessMeasurements()) {
      return const SizedBox.shrink();
    }
    final lang = settings.language;
    
    return Container(
      width: double.infinity,
      height: 90,
      decoration: BoxDecoration(
        gradient: Theme.of(context).brightness == Brightness.dark
            ? const LinearGradient(
                colors: [Color(0xFF1E3A5F), Color(0xFF0F2744)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
            : const LinearGradient(
                colors: [Color(0xFF3B82F6), Color(0xFF1D4ED8)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF3B82F6).withOpacity(0.3),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            openAdaptiveScreen(
              context,
              title: Localization.translate('بطاقة رفع القياسات', lang),
              icon: Icons.mic_none_outlined,
              screen: MeasurementsScreen(db: db),
            );
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
            child: Row(
              children: [
                Container(
                  padding: EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardColor.withOpacity(0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.mic_none_outlined,
                    color: Colors.white,
                    size: 32,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        Localization.translate('بطاقة رفع القياسات', lang),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'Cairo',
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        Localization.translate('إدخال القياسات السريع بالكتابة أو بالصوت', lang),
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.85),
                          fontSize: 13,
                          fontFamily: 'Cairo',
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.arrow_forward_ios_rounded,
                  color: Colors.white,
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── شبكة التنقل ──────────────────────────────────────────────────────────
  Widget _buildNavGrid(BuildContext context) {
    final settings = Provider.of<AppSettingsProvider>(context);
    final lang = settings.language;
    final items = [
      if (settings.canViewOrders())
        _NavItem(
          icon: Icons.receipt_long_rounded,
          label: Localization.translate('commandes', lang),
          color: const Color(0xFF2563EB), // Deep Royal Blue
          onTap: () async {
            await _markOrdersAsRead();
            if (context.mounted) {
              openAdaptiveScreen(
                context,
                title: Localization.translate('commandes', lang),
                icon: Icons.receipt_long_rounded,
                screen: const Commande(),
              );
            }
          },
        ),
      if (settings.canViewProjects())
        _NavItem(
          icon: Icons.folder_shared_rounded,
          label: Localization.translate('المشاريع', lang),
          color: const Color(0xFF0284C7), // Sky Cyan
          onTap: () => openAdaptiveScreen(
            context,
            title: Localization.translate('المشاريع', lang),
            icon: Icons.folder_shared_rounded,
            screen: ProjectsScreen(db: db),
          ),
        ),
      if (settings.canViewClients())
        _NavItem(
          icon: Icons.people_alt_rounded,
          label: Localization.translate('clients', lang),
          color: const Color(0xFF8B5CF6), // Amethyst Violet
          onTap: () => openAdaptiveScreen(
            context,
            title: Localization.translate('clients', lang),
            icon: Icons.people_alt_rounded,
            screen: const Customers(),
          ),
        ),
      if (settings.canViewMyAccreditations())
        _NavItem(
          icon: Icons.inventory_2_rounded,
          label: Localization.translate('produits', lang),
          color: const Color(0xFFF59E0B), // Golden Amber
          onTap: () => openAdaptiveScreen(
            context,
            title: Localization.translate('produits', lang),
            icon: Icons.inventory_2_rounded,
            screen: ProductsMenuScreen(db: db),
          ),
        ),
      if (settings.canViewMyTasks())
        _NavItem(
          icon: Icons.assignment_turned_in_rounded,
          label: Localization.translate('مهامي وتصنيعاتي', lang),
          color: const Color(0xFF10B981), // Emerald Green
          onTap: () => openAdaptiveScreen(
            context,
            title: Localization.translate('مهامي وتصنيعاتي', lang),
            icon: Icons.assignment_turned_in_rounded,
            screen: WorkerTasksScreen(db: db),
          ),
        ),
      if (settings.canViewMyTasks())
        _NavItem(
          icon: Icons.archive_rounded,
          label: lang == AppLanguage.arabic
              ? 'أرشيف التوزيع والمهام'
              : (lang == AppLanguage.french ? 'Archives & Distribution' : 'Tasks & Distribution Archive'),
          color: const Color(0xFFEA580C), // Vivid Burnt Orange
          onTap: () => openAdaptiveScreen(
            context,
            title: lang == AppLanguage.arabic
                ? 'أرشيف التوزيع والمهام'
                : (lang == AppLanguage.french ? 'Archives & Distribution' : 'Tasks & Distribution Archive'),
            icon: Icons.archive_rounded,
            screen: WorkerArchiveScreen(db: db),
          ),
        ),
      if (settings.canViewSuppliers())
        _NavItem(
          icon: Icons.local_shipping_rounded,
          label: Localization.translate('الموردين', lang),
          color: const Color(0xFFE11D48), // Rose Crimson
          onTap: () => openAdaptiveScreen(
            context,
            title: Localization.translate('الموردين', lang),
            icon: Icons.local_shipping_rounded,
            screen: SuppliersScreen(db: db),
          ),
        ),
      if (settings.canAccessInventory())
        _NavItem(
          icon: Icons.warehouse_rounded,
          label: Localization.translate('المخزون', lang),
          color: const Color(0xFFD946EF), // Neon Fuchsia Magenta
          onTap: () => openAdaptiveScreen(
            context,
            title: Localization.translate('المخزون', lang),
            icon: Icons.warehouse_rounded,
            screen: InventoryScreen(db: db),
          ),
        ),
      if (settings.canRegisterPurchases())
        _NavItem(
          icon: Icons.shopping_bag_rounded,
          label: Localization.translate('المشتريات', lang),
          color: const Color(0xFF06B6D4), // Bright Turquoise
          onTap: () => openAdaptiveScreen(
            context,
            title: Localization.translate('المشتريات', lang),
            icon: Icons.shopping_bag_rounded,
            screen: AchatScreen(db: db),
          ),
        ),
      if (settings.canAccessSettings())
        _NavItem(
          icon: Icons.settings_rounded,
          label: Localization.translate('settings', lang),
          color: const Color(0xFF475569), // Dark Slate Graphite
          onTap: () => openAdaptiveScreen(
            context,
            title: Localization.translate('settings', lang),
            icon: Icons.settings_rounded,
            screen: const SettingsScreen(),
          ),
        ),
      if (settings.canViewStatistics())
        _NavItem(
          icon: Icons.bar_chart_rounded,
          label: Localization.translate('rapports', lang),
          color: const Color(0xFF6366F1), // Vivid Indigo Blue
          onTap: () => openAdaptiveScreen(
            context,
            title: Localization.translate('rapports', lang),
            icon: Icons.bar_chart_rounded,
            screen: ReportsHubScreen(db: db),
          ),
        ),
      if (settings.canAccessTreasury())
        _NavItem(
          icon: Icons.account_balance_wallet_rounded,
          label: Localization.translate('الخزينة', lang),
          color: const Color(0xFF15803D), // Forest Green
          onTap: () => openAdaptiveScreen(
            context,
            title: Localization.translate('الخزينة', lang),
            icon: Icons.account_balance_wallet_rounded,
            screen: TreasuryScreen(db: db),
          ),
        ),
      if (settings.canAccessExternalOperations())
        _NavItem(
          icon: Icons.engineering_rounded,
          label: lang == AppLanguage.arabic
              ? 'الأعمال والمهمات الخارجية'
              : (lang == AppLanguage.french ? 'Opérations Externe' : 'External Operations'),
          color: const Color(0xFF0891B2), // Deep Ocean Cyan
          onTap: () => openAdaptiveScreen(
            context,
            title: lang == AppLanguage.arabic
                ? 'الأعمال والمهمات الخارجية'
                : (lang == AppLanguage.french ? 'Opérations Externe' : 'External Operations'),
            icon: Icons.engineering_rounded,
            screen: ExternalOperationsHubScreen(db: db),
          ),
        ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final desktopColumns = constraints.maxWidth >= 1240 ? 6 : 5;
        final crossAxisCount = _isWindowsDesktop ? desktopColumns : 3;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            crossAxisSpacing: _isWindowsDesktop ? 14 : 10,
            mainAxisSpacing: _isWindowsDesktop ? 14 : 10,
            childAspectRatio: _isWindowsDesktop ? 1.65 : 1.05,
          ),
          itemCount: items.length,
          itemBuilder: (_, i) => _NavCard(
            item: items[i],
            index: i,
            dragNotifier: _dragNotifier,
          ),
        );
      },
    );
  }



  // ── helpers ───────────────────────────────────────────────────────────────
  Widget _sectionLabel(String text) {
    return Text(
      text.toUpperCase(),
      style: const TextStyle(
        color: Color(0xFF94A3B8),
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.4,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Sub-widgets
// ─────────────────────────────────────────────────────────────────────────────

/// بطاقة إحصائية ثلاثية الأبعاد مع حركة دخول تدريجية وسحب مطاطي مرن وتباعد تفاعلي
class _DesktopMetricCard extends StatelessWidget {
  const _DesktopMetricCard({
    required this.icon,
    required this.title,
    required this.value,
    required this.caption,
    required this.color,
    required this.values,
    required this.backgroundColor,
    required this.textColor,
    required this.mutedColor,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String value;
  final String caption;
  final Color color;
  final List<double> values;
  final Color backgroundColor;
  final Color textColor;
  final Color mutedColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          // Windows can use larger system text and the treasury value can be
          // much longer than the other metrics.  Keep enough vertical room
          // and scale only the value when its available width is limited.
          height: 154,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: isDark ? Colors.white.withOpacity(0.08) : const Color(0xFFE2E8F0)),
            boxShadow: [
              BoxShadow(
                color: color.withOpacity(isDark ? 0.10 : 0.09),
                blurRadius: 16,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontFamily: 'Cairo', fontSize: 11, color: mutedColor, fontWeight: FontWeight.w700),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(9)),
                    child: Icon(icon, size: 18, color: color),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              SizedBox(
                height: 32,
                width: double.infinity,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(
                    value,
                    maxLines: 1,
                    style: TextStyle(fontFamily: 'Cairo', fontSize: 23, color: textColor, fontWeight: FontWeight.w900),
                  ),
                ),
              ),
              const Spacer(),
              SizedBox(height: 20, child: _DesktopSparkline(values: values, color: color)),
              const SizedBox(height: 4),
              Text(
                caption,
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
                style: TextStyle(fontFamily: 'Cairo', fontSize: 10, color: mutedColor),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DesktopSparkline extends StatelessWidget {
  const _DesktopSparkline({required this.values, required this.color, this.fill = false});

  final List<double> values;
  final Color color;
  final bool fill;

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: CustomPaint(
        painter: _DesktopSparklinePainter(values: values, color: color, fill: fill),
      ),
    );
  }
}

class _DesktopSparklinePainter extends CustomPainter {
  const _DesktopSparklinePainter({required this.values, required this.color, required this.fill});

  final List<double> values;
  final Color color;
  final bool fill;

  @override
  void paint(Canvas canvas, Size size) {
    final source = values.length < 2 ? <double>[0, 0] : values;
    final maxValue = source.reduce((a, b) => a > b ? a : b);
    final minValue = source.reduce((a, b) => a < b ? a : b);
    final range = maxValue == minValue ? 1.0 : maxValue - minValue;
    final path = Path();
    for (var index = 0; index < source.length; index++) {
      final x = size.width * index / (source.length - 1);
      final y = size.height - ((source[index] - minValue) / range * (size.height - 5)) - 2;
      if (index == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    if (fill) {
      final fillPath = Path.from(path)
        ..lineTo(size.width, size.height)
        ..lineTo(0, size.height)
        ..close();
      canvas.drawPath(fillPath, Paint()..color = color.withOpacity(0.12));
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant _DesktopSparklinePainter oldDelegate) =>
      oldDelegate.values != values || oldDelegate.color != color || oldDelegate.fill != fill;
}

class _StatCard extends StatefulWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final String trend;
  final int index;
  final ValueNotifier<Map<String, dynamic>?> dragNotifier;

  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    required this.trend,
    required this.index,
    required this.dragNotifier,
  });

  @override
  State<_StatCard> createState() => _StatCardState();
}

class _StatCardState extends State<_StatCard> with TickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;
  late AnimationController _snapController;
  late Animation<Offset> _snapAnimation;
  Offset _dragOffset = Offset.zero;
  Offset _repulsionOffset = Offset.zero;
  late String _myId;

  @override
  void initState() {
    super.initState();
    _myId = 'stat_${widget.index}';
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 550),
    );
    _animation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutBack,
    );
    _snapController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    );
    Future.delayed(Duration(milliseconds: widget.index * 65), () {
      if (mounted) {
        _controller.forward();
      }
    });

    widget.dragNotifier.addListener(_onDragChanged);
  }

  @override
  void dispose() {
    widget.dragNotifier.removeListener(_onDragChanged);
    _controller.dispose();
    _snapController.dispose();
    super.dispose();
  }

  void _onDragChanged() {
    if (!mounted) return;
    final dragInfo = widget.dragNotifier.value;
    if (dragInfo == null || dragInfo['id'] == _myId) {
      if (_repulsionOffset != Offset.zero) {
        setState(() {
          _repulsionOffset = Offset.zero;
        });
      }
      return;
    }

    final draggedId = dragInfo['id'] as String;
    final draggedOffset = dragInfo['offset'] as Offset;

    final myCenter = _WelcomScreenState._getCardCenter(_myId);
    final draggedBaseCenter = _WelcomScreenState._getCardCenter(draggedId);
    final draggedCurrentCenter = draggedBaseCenter + draggedOffset;

    final toMe = myCenter - draggedCurrentCenter;
    final distance = toMe.distance;
    const double repulsionRadius = 135.0;

    if (distance < repulsionRadius && distance > 1.0) {
      final force = (repulsionRadius - distance) / repulsionRadius;
      setState(() {
        _repulsionOffset = (toMe / distance) * force * 45.0;
      });
    } else {
      if (_repulsionOffset != Offset.zero) {
        setState(() {
          _repulsionOffset = Offset.zero;
        });
      }
    }
  }

  void _updateOffset() {
    setState(() {
      _dragOffset = _snapAnimation.value;
    });
  }

  @override
  Widget build(BuildContext context) {
    String displayTrend = widget.trend;
    final lang = Provider.of<AppSettingsProvider>(context).language;
    if (displayTrend.contains('(new)')) {
      final newWord = Localization.translate('جديدة', lang);
      displayTrend = displayTrend.replaceAll('(new)', '($newWord)');
    }
    if (displayTrend.contains('(new_client)')) {
      final newWord = Localization.translate('جديد', lang);
      displayTrend = displayTrend.replaceAll('(new_client)', '($newWord)');
    }
    if (displayTrend.contains('(جديد)')) {
      final newWord = Localization.translate('جديد', lang);
      displayTrend = displayTrend.replaceAll('(جديد)', '($newWord)');
    }
    if (displayTrend.contains('(جديدة)')) {
      final newWord = Localization.translate('جديدة', lang);
      displayTrend = displayTrend.replaceAll('(جديدة)', '($newWord)');
    }
    final depthColor = Color.lerp(widget.color, Colors.black, 0.20) ?? widget.color;

    return ScaleTransition(
      scale: _animation,
      child: FadeTransition(
        opacity: _animation,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          transform: Matrix4.translationValues(
            _dragOffset.dx + _repulsionOffset.dx,
            _dragOffset.dy + _repulsionOffset.dy,
            0.0,
          ),
          child: GestureDetector(
            onPanUpdate: (details) {
              if (_snapController.isAnimating) {
                _snapController.stop();
              }
              setState(() {
                _dragOffset += details.delta * 0.85;
              });
              widget.dragNotifier.value = {
                'id': _myId,
                'offset': _dragOffset,
              };
            },
            onPanEnd: (details) {
              widget.dragNotifier.value = null;
              final startOffset = _dragOffset;
              _snapAnimation = _snapController.drive(
                Tween<Offset>(
                  begin: startOffset,
                  end: Offset.zero,
                ).chain(CurveTween(curve: const ElasticOutCurve(0.65))),
              );
              _snapController.addListener(_updateOffset);
              _snapController.forward(from: 0.0).then((_) {
                _snapController.removeListener(_updateOffset);
              });
            },
            child: SizedBox(
              height: 125, // ارتفاع ثابت لاحتواء عمق الـ 3D
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  // طبقة العمق والظل ثلاثي الأبعاد
                  Positioned.fill(
                    top: 5,
                    child: Container(
                      decoration: BoxDecoration(
                        color: depthColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                  // بطاقة الواجهة الأمامية المرتفعة
                  Positioned.fill(
                    bottom: 5,
                    child: Container(
                      padding: EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Theme.of(context).cardColor,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Theme.of(context).dividerColor, width: 1.2),
                        boxShadow: [
                          BoxShadow(
                            color: widget.color.withValues(alpha: 0.06),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Container(
                                width: 32,
                                height: 32,
                                decoration: BoxDecoration(
                                  color: widget.color.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(9),
                                ),
                                child: Icon(widget.icon, color: widget.color, size: 16),
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  displayTrend,
                                  textAlign: TextAlign.end,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: displayTrend == '—'
                                        ? const Color(0xFF64748B)
                                        : const Color(0xFF10B981),
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    fontFamily: 'Cairo',
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const Spacer(),
                          Text(
                            widget.value,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              fontFamily: 'Cairo',
                            ),
                          ),
                          const SizedBox(height: 1),
                          Text(
                            widget.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              fontFamily: 'Cairo',
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
      ),
    );
  }
}

/// بند التنقل
class _NavItem {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });
}

/// بطاقة تنقل تفاعلية ثلاثية الأبعاد بضغط فيزيائي ملموس وسحب مطاطي مرن وتباعد تفاعلي وحركة دخول تدريجية
class _NavCard extends StatefulWidget {
  final _NavItem item;
  final int index;
  final ValueNotifier<Map<String, dynamic>?> dragNotifier;

  const _NavCard({
    required this.item,
    required this.index,
    required this.dragNotifier,
  });

  @override
  State<_NavCard> createState() => _NavCardState();
}

class _NavCardState extends State<_NavCard> with TickerProviderStateMixin {
  bool _pressed = false;
  Offset _dragOffset = Offset.zero;
  Offset _repulsionOffset = Offset.zero;
  late String _myId;
  late AnimationController _entranceController;
  late Animation<double> _entranceAnimation;
  late AnimationController _snapController;
  late Animation<Offset> _snapAnimation;

  @override
  void initState() {
    super.initState();
    _myId = 'nav_${widget.index}';
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _entranceAnimation = CurvedAnimation(
      parent: _entranceController,
      curve: Curves.easeOutBack,
    );
    _snapController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    );
    Future.delayed(Duration(milliseconds: widget.index * 50), () {
      if (mounted) {
        _entranceController.forward();
      }
    });

    widget.dragNotifier.addListener(_onDragChanged);
  }

  @override
  void dispose() {
    widget.dragNotifier.removeListener(_onDragChanged);
    _entranceController.dispose();
    _snapController.dispose();
    super.dispose();
  }

  void _onDragChanged() {
    if (!mounted) return;
    final dragInfo = widget.dragNotifier.value;
    if (dragInfo == null || dragInfo['id'] == _myId) {
      if (_repulsionOffset != Offset.zero) {
        setState(() {
          _repulsionOffset = Offset.zero;
        });
      }
      return;
    }

    final draggedId = dragInfo['id'] as String;
    final draggedOffset = dragInfo['offset'] as Offset;

    final myCenter = _WelcomScreenState._getCardCenter(_myId);
    final draggedBaseCenter = _WelcomScreenState._getCardCenter(draggedId);
    final draggedCurrentCenter = draggedBaseCenter + draggedOffset;

    final toMe = myCenter - draggedCurrentCenter;
    final distance = toMe.distance;
    const double repulsionRadius = 135.0;

    if (distance < repulsionRadius && distance > 1.0) {
      final force = (repulsionRadius - distance) / repulsionRadius;
      setState(() {
        _repulsionOffset = (toMe / distance) * force * 45.0;
      });
    } else {
      if (_repulsionOffset != Offset.zero) {
        setState(() {
          _repulsionOffset = Offset.zero;
        });
      }
    }
  }

  void _updateOffset() {
    setState(() {
      _dragOffset = _snapAnimation.value;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = widget.item.color;

    return ScaleTransition(
      scale: _entranceAnimation,
      child: FadeTransition(
        opacity: _entranceAnimation,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          transform: Matrix4.translationValues(
            _dragOffset.dx + _repulsionOffset.dx,
            _dragOffset.dy + _repulsionOffset.dy,
            0.0,
          ),
          child: GestureDetector(
            onTapDown: (_) => setState(() => _pressed = true),
            onTapUp: (_) {
              setState(() => _pressed = false);
              widget.item.onTap();
            },
            onTapCancel: () => setState(() => _pressed = false),
            onPanUpdate: (details) {
              if (_snapController.isAnimating) {
                _snapController.stop();
              }
              setState(() {
                _dragOffset += details.delta * 0.85;
                _pressed = false; // إلغاء تفعيل الضغط ثلاثي الأبعاد عند السحب
              });
              widget.dragNotifier.value = {
                'id': _myId,
                'offset': _dragOffset,
              };
            },
            onPanEnd: (details) {
              widget.dragNotifier.value = null;
              final startOffset = _dragOffset;
              _snapAnimation = _snapController.drive(
                Tween<Offset>(
                  begin: startOffset,
                  end: Offset.zero,
                ).chain(CurveTween(curve: const ElasticOutCurve(0.65))),
              );
              _snapController.addListener(_updateOffset);
              _snapController.forward(from: 0.0).then((_) {
                _snapController.removeListener(_updateOffset);
              });
            },
            child: SizedBox(
              height: 105, // ارتفاع ثابت للبطاقة
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  // طبقة العمق ثلاثية الأبعاد في الخلف
                  Positioned(
                    left: 0,
                    right: 0,
                    top: 6, // إزاحة للأسفل
                    bottom: 0,
                    child: Container(
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: isDark ? 0.35 : 0.22),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: color.withValues(alpha: isDark ? 0.28 : 0.16),
                            blurRadius: 6,
                            spreadRadius: -2,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                    ),
                  ),
                  // وجه البطاقة الأمامي القابل للانضغاط
                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 80),
                    curve: Curves.easeOut,
                    left: 0,
                    right: 0,
                    top: _pressed ? 6 : 0, // عند الضغط تنزل لطبقة العمق
                    bottom: _pressed ? 0 : 6, // عند الضغط تفقد الارتفاع
                    child: Container(
                      decoration: BoxDecoration(
                        color: isDark
                            ? Color.alphaBlend(color.withValues(alpha: 0.12), const Color(0xFF1E293B))
                            : Color.alphaBlend(color.withValues(alpha: 0.05), Colors.white),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: _pressed
                              ? color
                              : color.withValues(alpha: isDark ? 0.45 : 0.3),
                          width: _pressed ? 2 : 1.4,
                        ),
                        boxShadow: _pressed
                            ? []
                            : [
                                // هالة خارجية ضيقة على الأطراف فقط
                                BoxShadow(
                                  color: color.withValues(alpha: isDark ? 0.55 : 0.38),
                                  blurRadius: 7,
                                  spreadRadius: -3,
                                  offset: Offset.zero,
                                ),
                                // ظل سفلي خفيف
                                BoxShadow(
                                  color: color.withValues(alpha: isDark ? 0.18 : 0.10),
                                  blurRadius: 4,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: isDark ? 0.25 : 0.14),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: color.withValues(alpha: 0.35),
                                width: 1.2,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: color.withValues(alpha: 0.22),
                                  blurRadius: 4,
                                  spreadRadius: -1,
                                ),
                              ],
                            ),
                            child: Icon(
                              widget.item.icon,
                              color: color,
                              size: 20,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            widget.item.label,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'Cairo',
                              color: isDark ? Colors.white : const Color(0xFF1E293B),
                            ),
                            textAlign: TextAlign.center,
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
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  مخطط الطلبيات
// ═══════════════════════════════════════════════════════════════════════════

class _OrdersChartCard extends StatefulWidget {
  final Map<String, int> byStatus;
  final Map<String, int> byMonth;

  const _OrdersChartCard({required this.byStatus, required this.byMonth});

  @override
  State<_OrdersChartCard> createState() => _OrdersChartCardState();
}

class _OrdersChartCardState extends State<_OrdersChartCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _anim;
  late Animation<double> _progress;
  int _selectedTab = 0; // 0 = Donut (حسب الحالة), 1 = Bar (شهري)

  static const _statusColors = {
    'New':                   Color(0xFF546E7A), // رمادي مزرق
    'Pending':               Color(0xFFE65100), // برتقالي محروق
    'Confirmed':             Color(0xFF2E7D32), // أخضر داكن
    'In Progress':           Color(0xFF1565C0), // أزرق داكن
    'Partial Manufacturing': Color(0xFF0288D1), // أزرق فاتح
    'Full Manufacturing':    Color(0xFF00796B), // تيل داكن
    'Partial Distribution':  Color(0xFFF57C00), // برتقالي داكن
    'Full Distribution':     Color(0xFF388E3C), // أخضر
    'Installation':          Color(0xFF6A1B9A), // بنفسجي
    'Reserve':               Color(0xFFD84315), // أحمر برتقالي - التحفظ
    'Done':                  Color(0xFF00695C), // تيل/أخضر مائل
    'Unknown':               Color(0xFF78909C), // رمادي
  };

  static const _statusAr = {
    'New':                  'جديدة',
    'Pending':              'قيد الانتظار',
    'Confirmed':            'مؤكدة',
    'In Progress':          'جارية',
    'Partial Manufacturing':'تصنيع جزئي',
    'Full Manufacturing':   'تصنيع كامل',
    'Partial Distribution': 'توزيع جزئي',
    'Full Distribution':    'توزيع كامل',
    'Installation':         'تركيب',
    'Reserve':              'تحت التحفظ',
    'Done':                 'منتهية',
    'Unknown':              'أخرى',
  };

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _progress = CurvedAnimation(parent: _anim, curve: Curves.easeOutCubic);
    _anim.forward();
  }

  @override
  void didUpdateWidget(_OrdersChartCard old) {
    super.didUpdateWidget(old);
    _anim.forward(from: 0);
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lang = Provider.of<AppSettingsProvider>(context).language;
    final total = widget.byStatus.values.fold(0, (a, b) => a + b);
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF2563EB).withValues(alpha: 0.08),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── رأسية البطاقة ───────────────────────────────────────────────
          Container(
            padding: EdgeInsets.fromLTRB(20, 18, 16, 14),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: Theme.of(context).brightness == Brightness.dark ? [Color(0xFF111827), Color(0xFF070E1D)] : [Color(0xFF2563EB), Color(0xFF0EA5E9)], begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
              ),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.bar_chart_rounded,
                  color: Colors.white,
                  size: 22,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    Localization.translate('حالة الطلبيات', lang),
                    style: const TextStyle(
                      color: Colors.white,
                      fontFamily: 'Cairo',
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                // تبديل العرض
                Container(
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardColor.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  padding: const EdgeInsets.all(3),
                  child: Row(
                    children: [
                      _TabBtn(
                        label: Localization.translate('دائري', lang),
                        icon: Icons.donut_small_rounded,
                        selected: _selectedTab == 0,
                        onTap: () => setState(() => _selectedTab = 0),
                      ),
                      _TabBtn(
                        label: Localization.translate('أشهر', lang),
                        icon: Icons.bar_chart_rounded,
                        selected: _selectedTab == 1,
                        onTap: () => setState(() => _selectedTab = 1),
                      ),
                      _TabBtn(
                        label: Localization.translate('منحنى بياني', lang),
                        icon: Icons.show_chart_rounded,
                        selected: _selectedTab == 2,
                        onTap: () => setState(() => _selectedTab = 2),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // ── جسم المخطط ──────────────────────────────────────────────────
          AnimatedBuilder(
            animation: _progress,
            builder: (_, __) {
              if (_selectedTab == 0) {
                return _buildDonutView(total);
              } else if (_selectedTab == 1) {
                return _buildBarView();
              } else {
                return _buildLineView();
              }
            },
          ),
        ],
      ),
    );
  }

  // ── مخطط الدونات (حسب الحالة) ─────────────────────────────────────────────
  Widget _buildDonutView(int total) {
    final lang = Provider.of<AppSettingsProvider>(context).language;
    if (total == 0) return _emptyState();
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // الدائرة
          SizedBox(
            width: 140,
            height: 140,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CustomPaint(
                  size: const Size(140, 140),
                  painter: _DonutPainter(
                    data: widget.byStatus,
                    colors: _statusColors,
                    progress: _progress.value,
                    bgColor: Theme.of(context).scaffoldBackgroundColor,
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      total.toString(),
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        fontFamily: 'Cairo',
                      ),
                    ),
                    Text(
                      Localization.translate('إجمالي', lang),
                      style: const TextStyle(
                        fontSize: 11,

                        fontFamily: 'Cairo',
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 20),
          // مفاتيح الألوان
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: widget.byStatus.entries.map((e) {
                final color =
                    _statusColors[e.key] ?? const Color(0xFF94A3B8);
                final pct = total > 0
                    ? (e.value / total * 100).toStringAsFixed(1)
                    : '0';
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          Localization.translate(_statusAr[e.key] ?? e.key, lang),
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF334155),
                            fontFamily: 'Cairo',
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        '${e.value}  ($pct%)',
                        style: TextStyle(
                          fontSize: 11,
                          color: color,
                          fontWeight: FontWeight.w700,
                          fontFamily: 'Cairo',
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  // ── مخطط الأعمدة (شهري) ─────────────────────────────────────────────────
  Widget _buildBarView() {
    final lang = Provider.of<AppSettingsProvider>(context, listen: false).language;
    final entries = widget.byMonth.entries.toList();
    if (entries.isEmpty) return _emptyState();
    final maxVal = entries.map((e) => e.value).fold(0, (a, b) => a > b ? a : b);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 160,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: entries.map((e) {
                final ratio =
                    maxVal > 0 ? (e.value / maxVal) * _progress.value : 0.0;
                final isLast = entries.last == e;
                return Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(right: isLast ? 0 : 6),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        if (e.value > 0)
                          Text(
                            e.value.toString(),
                            style: const TextStyle(
                              fontSize: 10,
                              color: Color(0xFF2563EB),
                              fontWeight: FontWeight.w700,
                              fontFamily: 'Cairo',
                            ),
                          ),
                        const SizedBox(height: 4),
                        AnimatedContainer(
                          duration: Duration.zero,
                          height: 120 * ratio,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: Theme.of(context).brightness == Brightness.dark ? [Color(0xFF111827), Color(0xFF070E1D)] : [Color(0xFF2563EB), Color(0xFF0EA5E9)], begin: Alignment.bottomCenter,
                              end: Alignment.topCenter,
                            ),
                            borderRadius: const BorderRadius.only(
                              topLeft: Radius.circular(6),
                              topRight: Radius.circular(6),
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF2563EB)
                                    .withValues(alpha: 0.25),
                                blurRadius: 8,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _monthLabel(e.key, lang),
                          style: const TextStyle(
                            fontSize: 9,
                            color: Color(0xFF94A3B8),
                            fontFamily: 'Cairo',
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 12),
          // إجمالي الفترة
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              const Icon(
                Icons.trending_up_rounded,
                size: 14,
                color: Color(0xFF10B981),
              ),
              const SizedBox(width: 4),
              Text(
                Localization.translate('آخر 6 أشهر: {count} طلبية', lang)
                    .replaceAll('{count}', '${entries.fold(0, (s, e) => s + e.value)}'),
                style: const TextStyle(
                  fontSize: 11,

                  fontFamily: 'Cairo',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLineView() {
    final lang = Provider.of<AppSettingsProvider>(context, listen: false).language;
    final entries = widget.byMonth.entries.toList();
    if (entries.isEmpty) return _emptyState();
    final maxVal = entries.map((e) => e.value).fold(0, (a, b) => a > b ? a : b);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 160,
            width: double.infinity,
            child: CustomPaint(
              size: const Size(double.infinity, 160),
              painter: _LineChartPainter(
                entries: entries,
                maxVal: maxVal,
                progress: _progress.value,
                lang: lang,
                gridColor: Theme.of(context).dividerColor,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              const Icon(
                Icons.trending_up_rounded,
                size: 14,
                color: Color(0xFF10B981),
              ),
              const SizedBox(width: 4),
              Text(
                Localization.translate('آخر 6 أشهر: {count} طلبية', lang)
                    .replaceAll('{count}', '${entries.fold(0, (s, e) => s + e.value)}'),
                style: const TextStyle(
                  fontSize: 11,

                  fontFamily: 'Cairo',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _emptyState() {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 40),
      child: Center(
        child: Column(
          children: [
            Icon(Icons.bar_chart_outlined, size: 40, color: Color(0xFFCBD5E1)),
            SizedBox(height: 8),
            Text(
              'لا توجد طلبيات بعد',
              style: TextStyle(
                color: Color(0xFF94A3B8),
                fontFamily: 'Cairo',
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _monthLabel(String key, AppLanguage lang) {
    final parts = key.split('/');
    if (parts.length != 2) return key;
    const months = [
      '', 'يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو',
      'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر'
    ];
    final m = int.tryParse(parts[0]) ?? 0;
    return m > 0 && m <= 12 ? Localization.translate(months[m], lang) : key;
  }
}

// ── زر التبديل في الرأسية ────────────────────────────────────────────────
class _TabBtn extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _TabBtn({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: Duration(milliseconds: 200),
        padding: EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? Theme.of(context).cardColor : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 13,
              color: selected
                  ? const Color(0xFF2563EB)
                  : Colors.white.withValues(alpha: 0.8),
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontFamily: 'Cairo',
                fontWeight:
                    selected ? FontWeight.w700 : FontWeight.w400,
                color: selected
                    ? const Color(0xFF2563EB)
                    : Colors.white.withValues(alpha: 0.8),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── رسّام الدائرة ─────────────────────────────────────────────────────────
class _DonutPainter extends CustomPainter {
  final Map<String, int> data;
  final Map<String, Color> colors;
  final double progress;
  final Color bgColor;

  _DonutPainter({
    required this.data,
    required this.colors,
    required this.progress,
    required this.bgColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final total = data.values.fold(0, (a, b) => a + b);
    if (total == 0) return;

    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 8;
    const strokeWidth = 22.0;
    final rect = Rect.fromCircle(center: center, radius: radius);

    double startAngle = -3.14159 / 2; // -90°
    final totalSweep = 2 * 3.14159 * progress;

    for (final entry in data.entries) {
      final sweep = (entry.value / total) * totalSweep;
      final color = colors[entry.key] ?? const Color(0xFF94A3B8);

      final paint = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.butt;

      canvas.drawArc(rect, startAngle, sweep - 0.04, false, paint);
      startAngle += sweep;
    }

    // دائرة خلفية خافتة
    final bgPaint = Paint()
      ..color = bgColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    canvas.drawCircle(center, radius, bgPaint);

    // إعادة رسم الشرائح فوق الخلفية
    startAngle = -3.14159 / 2;
    for (final entry in data.entries) {
      final sweep = (entry.value / total) * totalSweep;
      final color = colors[entry.key] ?? const Color(0xFF94A3B8);
      final paint = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.butt;
      canvas.drawArc(rect, startAngle, sweep - 0.04, false, paint);
      startAngle += sweep;
    }
  }

  @override
  bool shouldRepaint(_DonutPainter old) =>
      old.progress != progress || old.data != data;
}



class _LineChartPainter extends CustomPainter {
  final List<MapEntry<String, int>> entries;
  final int maxVal;
  final double progress;
  final AppLanguage lang;
  final Color gridColor;

  _LineChartPainter({
    required this.entries,
    required this.maxVal,
    required this.progress,
    required this.lang,
    this.gridColor = const Color(0xFFE2E8F0),
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (entries.isEmpty) return;

    final double width = size.width;
    final double height = size.height - 30; // Leave space for X labels
    final double stepX = width / (entries.length - 1);
    final double maxValDouble = maxVal == 0 ? 1.0 : maxVal.toDouble();

    final List<Offset> points = [];
    for (int i = 0; i < entries.length; i++) {
      final double x = i * stepX;
      final double y = height - (entries[i].value / maxValDouble * height * progress);
      points.add(Offset(x, y));
    }

    // Paint for background grid lines
    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1.0;
    
    // Draw 3 horizontal grid lines
    for (int i = 0; i <= 3; i++) {
      final double y = (height / 3) * i;
      canvas.drawLine(Offset(0, y), Offset(width, y), gridPaint);
    }

    // Paint for the gradient fill path
    final Path path = Path();
    path.moveTo(points.first.dx, height);
    for (final p in points) {
      path.lineTo(p.dx, p.dy);
    }
    path.lineTo(points.last.dx, height);
    path.close();

    final fillPaint = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0x3B3B82F6), Color(0x003B82F6)],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ).createShader(Rect.fromLTRB(0, 0, width, height))
      ..style = PaintingStyle.fill;
    canvas.drawPath(path, fillPaint);

    // Paint for the stroke line
    final linePaint = Paint()
      ..color = const Color(0xFF2563EB)
      ..strokeWidth = 3.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final Path strokePath = Path();
    strokePath.moveTo(points.first.dx, points.first.dy);
    for (int i = 1; i < points.length; i++) {
      strokePath.lineTo(points[i].dx, points[i].dy);
    }
    canvas.drawPath(strokePath, linePaint);

    // Paint for dots on each point
    final dotPaint = Paint()
      ..color = const Color(0xFF2563EB)
      ..style = PaintingStyle.fill;
    final dotBorderPaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;

    // X Labels text painter
    for (int i = 0; i < entries.length; i++) {
      final p = points[i];
      canvas.drawCircle(p, 5.0, dotPaint);
      canvas.drawCircle(p, 5.0, dotBorderPaint);

      // Draw values text above the dots
      final valSpan = TextSpan(
        text: entries[i].value.toString(),
        style: const TextStyle(

          fontSize: 10,
          fontWeight: FontWeight.bold,
          fontFamily: 'Cairo',
        ),
      );
      final valPainter = TextPainter(
        text: valSpan,
        textDirection: TextDirection.rtl,
      );
      valPainter.layout();
      valPainter.paint(canvas, Offset(p.dx - valPainter.width / 2, p.dy - 18));

      // Draw labels text below the line chart
      final labelSpan = TextSpan(
        text: _monthLabel(entries[i].key, lang),
        style: const TextStyle(
          fontSize: 9,
          fontFamily: 'Cairo',
        ),
      );
      final labelPainter = TextPainter(
        text: labelSpan,
        textDirection: TextDirection.rtl,
      );
      labelPainter.layout();
      labelPainter.paint(
        canvas,
        Offset(p.dx - labelPainter.width / 2, height + 8),
      );
    }
  }

  String _monthLabel(String key, AppLanguage lang) {
    final parts = key.split('/');
    if (parts.length != 2) return key;
    const months = [
      '', 'يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو',
      'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر'
    ];
    final m = int.tryParse(parts[0]) ?? 0;
    return m > 0 && m <= 12 ? Localization.translate(months[m], lang) : key;
  }

  @override
  bool shouldRepaint(_LineChartPainter old) =>
      old.progress != progress || old.entries != entries || old.lang != lang;
}

class _WaterWaveBackground extends StatefulWidget {
  final bool enabled;
  const _WaterWaveBackground({required this.enabled});

  @override
  State<_WaterWaveBackground> createState() => _WaterWaveBackgroundState();
}

class _Bubble {
  double xFraction;
  double yFraction;
  double radius;
  double speed;
  double wobbleSpeed;
  double wobbleScale;

  _Bubble({
    required this.xFraction,
    required this.yFraction,
    required this.radius,
    required this.speed,
    required this.wobbleSpeed,
    required this.wobbleScale,
  });
}

class _WaterWaveBackgroundState extends State<_WaterWaveBackground>
    with SingleTickerProviderStateMixin {
  AnimationController? _controller;
  final List<_Bubble> _bubbles = [];

  @override
  void initState() {
    super.initState();
    if (widget.enabled) {
      _controller = AnimationController(
        vsync: this,
        duration: const Duration(seconds: 12),
      )..repeat();

      final rand = math.Random();
      for (int i = 0; i < 16; i++) {
        _bubbles.add(_Bubble(
          xFraction: rand.nextDouble(),
          yFraction: 0.3 + rand.nextDouble() * 0.7,
          radius: 2.0 + rand.nextDouble() * 5.0,
          speed: 0.05 + rand.nextDouble() * 0.05,
          wobbleSpeed: 0.5 + rand.nextDouble() * 1.5,
          wobbleScale: 0.01 + rand.nextDouble() * 0.02,
        ));
      }
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled || _controller == null) {
      return const SizedBox.shrink();
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AnimatedBuilder(
      animation: _controller!,
      builder: (context, child) {
        return Stack(
          children: [
            // Safe gradient base (Ocean/Dark style)
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: isDark
                      ? [
                          const Color(0xFF0F172A), // slate-900
                          const Color(0xFF020617), // slate-950
                          const Color(0xFF070E1D), // normal dark background
                        ]
                      : [
                          const Color(0xFFE0F2FE), // sky-100 (light top)
                          const Color(0xFFBAE6FD), // sky-200
                          const Color(0xFFF1F5F9), // blends to normal background at the bottom
                        ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            ),
            // Floating bubbles in the depths
            Positioned.fill(
              child: CustomPaint(
                painter: _BubblesPainter(
                  progress: _controller!.value,
                  bubbles: _bubbles,
                ),
              ),
            ),
            // Wave Layer 1 (Back, slower, smaller)
            Positioned.fill(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: SizedBox(
                  height: 380,
                  child: CustomPaint(
                    painter: _WavePainter(
                      progress: _controller!.value,
                      waveColor: isDark
                          ? const Color(0x1F1E293B) // soft dark slate wave
                          : const Color(0x3338BDF8), // sky-400 with glowing highlight
                      amplitude: 14,
                      frequency: 1.2,
                      phaseShift: 0.0,
                      highlightColor: isDark ? Colors.white.withOpacity(0.08) : Colors.white.withOpacity(0.35),
                    ),
                  ),
                ),
              ),
            ),
            // Wave Layer 2 (Middle, medium)
            Positioned.fill(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: SizedBox(
                  height: 310,
                  child: CustomPaint(
                    painter: _WavePainter(
                      progress: _controller!.value,
                      waveColor: isDark
                          ? const Color(0x2A334155) // slate-700 wave
                          : const Color(0x400EA5E9), // cyan-500
                      amplitude: 18,
                      frequency: 0.8,
                      phaseShift: 2.2,
                      highlightColor: isDark ? Colors.white.withOpacity(0.12) : Colors.white.withOpacity(0.45),
                    ),
                  ),
                ),
              ),
            ),
            // Wave Layer 3 (Front, faster, larger)
            Positioned.fill(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: SizedBox(
                  height: 240,
                  child: CustomPaint(
                    painter: _WavePainter(
                      progress: _controller!.value,
                      waveColor: isDark
                          ? const Color(0x38475569) // slate-600 wave
                          : const Color(0x520284C7), // sky-600
                      amplitude: 22,
                      frequency: 1.4,
                      phaseShift: 4.5,
                      highlightColor: isDark ? Colors.white.withOpacity(0.15) : Colors.white.withOpacity(0.55),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _WavePainter extends CustomPainter {
  final double progress;
  final Color waveColor;
  final double amplitude;
  final double frequency;
  final double phaseShift;
  final Color highlightColor;

  _WavePainter({
    required this.progress,
    required this.waveColor,
    required this.amplitude,
    required this.frequency,
    required this.phaseShift,
    required this.highlightColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final double waveCrestY = size.height * 0.6 - amplitude;
    final rect = Rect.fromLTRB(0, waveCrestY, size.width, size.height);
    
    // Gradient shading (darker blue at the bottom, lighter cyan at the crest)
    final gradient = LinearGradient(
      colors: [
        waveColor.withOpacity(waveColor.opacity * 0.5),
        waveColor.withOpacity(waveColor.opacity * 0.9),
        waveColor.withOpacity(waveColor.opacity * 1.0),
      ],
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
    ).createShader(rect);

    final paint = Paint()
      ..shader = gradient
      ..style = PaintingStyle.fill;

    // Glowing white foam highlight line at the crest of the waves
    final strokePaint = Paint()
      ..color = highlightColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    final path = Path();
    path.moveTo(0, size.height);

    final double waveLength = size.width;
    for (double x = 0; x <= size.width; x++) {
      final double angle = (x / waveLength) * 2 * math.pi * frequency +
          (progress * 2 * math.pi) +
          phaseShift;
      final double y = size.height * 0.6 + amplitude * math.sin(angle);
      path.lineTo(x, y);
    }

    path.lineTo(size.width, size.height);
    path.close();

    // Draw translucent gradient filled wave
    canvas.drawPath(path, paint);
    // Draw glowing crest highlight
    canvas.drawPath(path, strokePaint);
  }

  @override
  bool shouldRepaint(covariant _WavePainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}

class _BubblesPainter extends CustomPainter {
  final double progress;
  final List<_Bubble> bubbles;

  _BubblesPainter({required this.progress, required this.bubbles});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.18)
      ..style = PaintingStyle.fill;

    final borderPaint = Paint()
      ..color = Colors.white.withOpacity(0.35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;

    for (var bubble in bubbles) {
      double currentY = (bubble.yFraction - progress * bubble.speed) % 1.0;
      if (currentY < 0) currentY += 1.0;

      double wobble = math.sin(progress * 2 * math.pi * bubble.wobbleSpeed) *
          bubble.wobbleScale *
          size.width;

      double x = (bubble.xFraction * size.width + wobble) % size.width;
      double y = currentY * size.height;

      canvas.drawCircle(Offset(x, y), bubble.radius, paint);
      canvas.drawCircle(Offset(x, y), bubble.radius, borderPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _BubblesPainter oldDelegate) {
    return true;
  }
}
