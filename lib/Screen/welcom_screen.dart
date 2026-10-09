import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb, mapEquals;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:database_data/services/auth_service.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import '../Commande/order_status_order.dart';
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
import '../services/supabase_account_service.dart';
import '../services/supabase_workshop_sync_service.dart';
import 'suppliers_screen.dart';
import 'achat_screen.dart';
import 'inventory_screen.dart';
import 'measurements_screen.dart';
import 'worker_tasks_screen.dart';
import 'material_sales_screen.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'external_operations_hub_screen.dart';

import 'worker_archive_screen.dart';
import 'subscription_overview_card.dart';
import '../widgets/resizable_columns_table.dart';

bool get _isWindowsDesktop =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

class _DesktopSearchResult {
  final String type;
  final String title;
  final String subtitle;
  final IconData icon;

  const _DesktopSearchResult({
    required this.type,
    required this.title,
    required this.subtitle,
    required this.icon,
  });
}

class WelcomScreen extends StatefulWidget {
  final bool embeddedInWorkspace;

  const WelcomScreen({super.key, this.embeddedInWorkspace = false});

  @override
  State<WelcomScreen> createState() => _WelcomScreenState();
}

class _WelcomScreenState extends State<WelcomScreen> {
  final SqlDatabase db = SqlDatabase();
  final ValueNotifier<Map<String, dynamic>?> _dragNotifier =
      ValueNotifier<Map<String, dynamic>?>(null);

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

  String _workshopName = '';
  String _userEmail = 'جاري التحميل...';
  String _workshopPhone = '';
  String? _logoUrl;
  ImageProvider? _cachedLogoProvider; // الصورة المحسوبة مرة واحدة لتجنب الترميش
  StreamSubscription? _userSub;
  StreamSubscription<String>? _databaseUpdateSub;
  Timer? _statsDebounce; // debounce لمنع تكرار _loadStats خلال ms قصيرة
  int _statsLoadToken = 0;

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
  List<Map<String, dynamic>> _desktopClients = [];
  List<Map<String, dynamic>> _desktopProfiles = [];
  List<Map<String, dynamic>> _desktopTreasury = [];
  Map<int, String> _assignedWorkersMap = {};
  int _selectedDesktopTableTab = 0; // 0: الطلبيات, 1: الزبائن, 2: الصندوق
  final TextEditingController _desktopTreasurySearchController =
      TextEditingController();
  final TextEditingController _desktopGlobalSearchController =
      TextEditingController();
  String _desktopGlobalSearchQuery = '';
  String _desktopTreasurySearchQuery = '';
  bool _showTreasuryTotals = false;
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _autoSyncData(showSnackBar: false);
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
          final alertEnabled =
              ((item['low_stock_alert_enabled'] as num?)?.toInt() ?? 0) == 1;
          if (alertEnabled && minQty > 0 && quantity <= minQty) {
            final key =
                "${item['item_id']}_${item['item_type']}_${item['color_id']}";
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
    final lang = Provider.of<AppSettingsProvider>(
      context,
      listen: false,
    ).language;
    showDialog(
      context: context,
      builder: (context) {
        final screenWidth = MediaQuery.of(context).size.width;
        final isDark = Theme.of(context).brightness == Brightness.dark;

        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          backgroundColor: isDark
              ? Color(0xFF1E293B)
              : Theme.of(context).cardColor,
          title: Row(
            children: [
              Icon(
                Icons.warning_amber_rounded,
                color: Colors.orange.shade800,
                size: 28,
              ),
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
                      const Icon(
                        Icons.check_circle_outline_rounded,
                        color: Colors.green,
                        size: 64,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        Localization.translate(
                          'كل الكميات متوفرة بشكل جيد ولا توجد نواقص!',
                          lang,
                        ),
                        style: const TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 14,
                        ),
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
                          color: Colors.orange.shade50.withValues(
                            alpha: isDark ? 0.05 : 1.0,
                          ),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Colors.orange.shade200.withValues(
                              alpha: isDark ? 0.3 : 1.0,
                            ),
                          ),
                        ),
                        child: Text(
                          Localization.translate(
                            'العناصر التالية وصلت للحد الأدنى أو نفذت من المخزون، يرجى إعادة طلبها قريباً:',
                            lang,
                          ),
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 12,
                            color: isDark
                                ? Colors.orange.shade300
                                : Colors.orange.shade900,
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
                            final min =
                                (item['min_qty'] as num?)?.toDouble() ?? 0.0;

                            return Card(
                              margin: const EdgeInsets.symmetric(vertical: 4),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              elevation: 0,
                              color: isDark
                                  ? const Color(0xFF334155)
                                  : Colors.grey.shade50,
                              child: ListTile(
                                dense: true,
                                leading: CircleAvatar(
                                  backgroundColor: Colors.orange.shade100
                                      .withValues(alpha: isDark ? 0.2 : 1.0),
                                  child: Icon(
                                    Icons.inventory_2_rounded,
                                    color: Colors.orange.shade800,
                                    size: 20,
                                  ),
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
                                  style: const TextStyle(
                                    fontFamily: 'Cairo',
                                    fontSize: 11,
                                  ),
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
                                        color: qty <= 0
                                            ? Colors.red
                                            : Colors.orange.shade800,
                                      ),
                                    ),
                                    Text(
                                      '${Localization.translate('الحد الأدنى', lang)}: ${min.toStringAsFixed(min.truncateToDouble() == min ? 0 : 2)}',
                                      style: const TextStyle(
                                        fontFamily: 'Cairo',
                                        fontSize: 9,
                                        color: Colors.grey,
                                      ),
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
                style: const TextStyle(
                  fontFamily: 'Cairo',
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _loadStats() async {
    final loadToken = ++_statsLoadToken;
    try {
      await db.migrateAllPendingOrdersToNouveau();
      final coreData = await Future.wait<dynamic>([
        db.getDashboardStats(),
        db.getOrderStatusStats(),
        db.readCommande(),
      ]);
      final stats = coreData[0] as Map<String, dynamic>;
      final chartData = coreData[1] as Map<String, dynamic>;
      final allCmds = coreData[2] as List<Map<String, dynamic>>;
      final prefs = await SharedPreferences.getInstance();
      final lastCmdCount = prefs.getInt('last_seen_orders_count');
      final unreadOrders = lastCmdCount == null
          ? 0
          : math.max(0, allCmds.length - lastCmdCount).toInt();

      if (!mounted || loadToken != _statsLoadToken) return;

      if (lastCmdCount == null) {
        await prefs.setInt('last_seen_orders_count', allCmds.length);
      }

      final secondaryData = await Future.wait<dynamic>([
        db.readProfile(),
        db.readCommandesWithClients(),
        db.readTreasury(),
        db.readEmployees(),
        db.readClientsForDisplay(),
        db.getOrderAssignedWorkersMap(),
        db.readAllProfiles(),
      ]);
      final profiles = secondaryData[0] as List<Map<String, dynamic>>;
      final desktopOrders = List<Map<String, dynamic>>.from(
        secondaryData[1] as List<Map<String, dynamic>>,
      );
      final treasuryRows = secondaryData[2] as List<Map<String, dynamic>>;
      final employees = secondaryData[3] as List<Map<String, dynamic>>;
      final clients = List<Map<String, dynamic>>.from(
        secondaryData[4] as List<Map<String, dynamic>>,
      );
      final assignedWorkersMap = Map<int, String>.from(
        secondaryData[5] as Map<int, String>,
      );
      final allProfiles = secondaryData[6] as List<Map<String, dynamic>>;

      if (mounted && loadToken == _statsLoadToken) {
        setState(() {
          _newOrdersCount = unreadOrders;
          _commandesCount = stats['cmdCount'] ?? '0';
          _cmdTrend = stats['cmdTrend'] ?? '—';
          _ordersByStatus = canonicalizeOrderStatusCounts(
            Map<String, int>.from(
              (chartData['byStatus'] as Map<String, int>?) ?? {},
            ),
          );
          _ordersByMonth = Map<String, int>.from(
            (chartData['monthly'] as Map<String, int>?) ?? {},
          );
          _clientsCount = stats['cliCount'] ?? '0';
          _cliTrend = stats['cliTrend'] ?? '—';
          // The dashboard card is a catalogue total, not an "active only"
          // filter. Imported backups can legitimately contain inactive
          // profiles, which previously made this card show zero.
          _produitsCount = allProfiles.length.toString();
          _desktopOrders = desktopOrders;
          _desktopClients = clients;
          _desktopProfiles = profiles;
          _desktopTreasury = treasuryRows;
          _assignedWorkersMap = assignedWorkersMap;
          _treasuryBalance = _calculateTreasuryBalance(treasuryRows);
          _workersCount = employees.length;
          _activeWorkersCount = employees.where(_isActiveEmployee).length;
          _pendingOrdersCount = desktopOrders.where(_isOpenOrder).length;
        });
      }

      if (loadToken == _statsLoadToken) await _checkLowStock();
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
      final isExpense =
          type == 'expense' ||
          type.contains('décaissement') ||
          type.contains('decaissement') ||
          type.contains('achat') ||
          type.contains('purchase');
      balance += isExpense ? -amount : amount;
    }
    return balance;
  }

  bool _isTreasuryExpense(Map<String, dynamic> row) {
    final type = (row['transaction_type'] ?? '').toString().toLowerCase();
    final description = (row['description'] ?? '').toString().toLowerCase();
    return type == 'expense' ||
        type == 'withdrawal' ||
        type == 'outflow' ||
        type.contains('décaissement') ||
        type.contains('decaissement') ||
        type.contains('achat') ||
        type.contains('purchase') ||
        type.contains('سحب') ||
        type.contains('مصروف') ||
        type.contains('شراء') ||
        description.contains('سحب') ||
        description.contains('مصروف');
  }

  List<double> _clientAdditionsByMonth() {
    const monthsToShow = 6;
    final now = DateTime.now();
    final counts = List<int>.filled(monthsToShow, 0);
    for (final client in _desktopClients) {
      final date = DateTime.tryParse((client['created_at'] ?? '').toString());
      if (date == null) continue;
      final monthDifference =
          (now.year - date.year) * 12 + now.month - date.month;
      if (monthDifference >= 0 && monthDifference < monthsToShow) {
        counts[monthsToShow - monthDifference - 1] += 1;
      }
    }
    return counts.map((count) => count.toDouble()).toList();
  }

  Future<void> _loadSupabaseWorkshopName() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedName = (prefs.getString('workshop_name') ?? '').trim();
      final savedCode = (prefs.getString('workshop_code') ?? '').trim();
      final account = await SupabaseAccountService().loadCurrentAccount();
      final accountName = account?.workshopName.trim() ?? '';
      final accountCode = account?.workshopCode.trim() ?? savedCode;
      // The synced workshop profile is authoritative for the visible name.
      // The workshops row is only a fallback for an older profile-less account.
      final name = savedName.isNotEmpty && savedName != savedCode
          ? savedName
          : (accountName.isNotEmpty && accountName != accountCode
                ? accountName
                : '');
      final savedLogo = prefs.getString('workshop_logo_base64') ??
          prefs.getString('workshop_logo');
      final savedPhone = (prefs.getString('phone') ?? '').trim();
      if (name.isNotEmpty) {
        await prefs.setString('workshop_name', name);
      }
      if (mounted) {
        setState(() {
          if (name.isNotEmpty) _workshopName = name;
          if (savedPhone.isNotEmpty) _workshopPhone = savedPhone;
        });
        _updateLogo(savedLogo);
      }
    } catch (error) {
      debugPrint('Could not load dashboard workshop name: $error');
    }
  }

  Future<void> _loadUserData() async {
    final user = AppAuthService().currentUser;
    if (user != null) {
      await _userSub?.cancel();
      setState(() {
        _userEmail = user.email ?? 'لا يوجد بريد';
      });
      // Supabase owns the active account and workshop profile.
      if (AppAuthService().usesSupabase) {
        await _loadSupabaseWorkshopName();
      } else {
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
                  final savedCode = (prefs.getString('workshop_code') ?? '')
                      .trim();
                  final usableSavedName =
                      savedName?.trim().isNotEmpty == true &&
                      savedName!.trim() != savedCode &&
                      savedName.trim() != 'ورشة النجارة' &&
                      savedName.trim() != 'ورشة الألمنيوم';
                  final firebaseName =
                      (data['workshopName'] as String?)?.trim() ?? '';
                  final usableFirebaseName =
                      firebaseName.isNotEmpty &&
                      firebaseName != 'ورشة النجارة' &&
                      firebaseName != 'ورشة الألمنيوم';
                  final savedLogo = prefs.getString('workshop_logo_base64');
                  final newLogoUrl =
                      (data['workshopLogoUrl'] as String?)?.isNotEmpty == true
                      ? data['workshopLogoUrl']
                      : savedLogo;
                  final nextName = usableSavedName
                      ? savedName!
                      : (usableFirebaseName
                            ? firebaseName
                            : Localization.translate(
                                'اسم الورشة',
                                Provider.of<AppSettingsProvider>(
                                  context,
                                  listen: false,
                                ).language,
                              ));
                  final nextPhone = (data['phone'] ?? data['phoneNumber'] ?? '')
                      .toString();
                  final nextEmail = data['email']?.toString() ?? _userEmail;

                  final hasChanged =
                      _workshopName != nextName ||
                      _workshopPhone != nextPhone ||
                      _userEmail != nextEmail ||
                      _logoUrl != newLogoUrl;

                  if (hasChanged) {
                    setState(() {
                      _workshopName = nextName;
                      _workshopPhone = nextPhone;
                      _userEmail = nextEmail;
                      _updateLogo(newLogoUrl);
                    });
                  }
                });
              }
            });
      }
    }

    // SubscriptionChecker owns the global Firestore listeners. This page
    // only listens to local update notifications so navigating away cannot
    // stop synchronization for the whole app. This must also run when the
    // active account is Supabase-only and Firebase has no current user.
    await CloudSyncService().init();

    // The workshop identity is owned by Supabase. Firebase user documents
    // may contain an old Arabic fallback, so load the real display name
    // before the dashboard renders it.
    await _loadSupabaseWorkshopName();

    // استماع التحديثات المحلية مع debounce لمنع تكرار البناء خلال مليسثانية فقيرة
    await _databaseUpdateSub?.cancel();
    _databaseUpdateSub = CloudSyncService().dbUpdateStream.listen((event) {
      if (!mounted) return;
      if (event == 'workshop_profile_updated') {
        _loadSupabaseWorkshopName();
        return;
      }
      // Allocation/measurement listeners can emit a snapshot without a
      // dashboard value changing. Reloading the whole dashboard for those
      // events restarts the orders chart and makes it look like it is
      // continually loading.
      if (event == 'status_updated' || event == 'measurements_updated') {
        return;
      }
      _statsDebounce?.cancel();
      _statsDebounce = Timer(const Duration(milliseconds: 600), () {
        if (mounted) {
          if (event == 'cloud_restored' ||
              event == 'cloud_delta_applied' ||
              event == 'supabase_data_updated') {
            Provider.of<AppSettingsProvider>(
              context,
              listen: false,
            ).reloadPermissions();
          }
          _loadStats();
        }
      });
    });
  }

  bool _isManualSyncing = false;

  Future<void> _autoSyncData({bool showSnackBar = false}) async {
    if (_isManualSyncing) return;
    if (mounted) setState(() => _isManualSyncing = true);
    if (showSnackBar && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'جاري تنزيل وتحديث كافة بيانات الورشة والطلبات من السحابة... ⏳',
            style: TextStyle(fontFamily: 'Cairo'),
          ),
          duration: Duration(seconds: 2),
          backgroundColor: Colors.blue,
        ),
      );
    }
    try {
      try {
        await SupabaseWorkshopSyncService().downloadWorkshopData();
        await SupabaseWorkshopSyncService()
            .loadAndApplyWorkshopCatalogConfiguration();
      } catch (_) {}
      await CloudSyncService().fullRecoverySync();
      if (mounted) {
        await Provider.of<AppSettingsProvider>(
          context,
          listen: false,
        ).reloadPermissions();
        await _loadStats();
        if (showSnackBar) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'تم تنزيل وتحديث البيانات والطلبات من السحابة بنجاح 🔄',
                style: TextStyle(fontFamily: 'Cairo'),
              ),
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
    _desktopTreasurySearchController.dispose();
    _desktopGlobalSearchController.dispose();
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
        final workspace = context.read<WorkspaceController>();
        // This dashboard stays mounted behind the other workspace tabs.
        // Only the active tab may handle Back; the shell returns it home.
        if (!workspace.isHomeActive ||
            identical(
              Navigator.of(context),
              workspace.navigatorKeyFor('home').currentState,
            )) {
          return;
        }
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
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: Text(
              lang == AppLanguage.arabic
                  ? 'الخروج من التطبيق'
                  : lang == AppLanguage.french
                  ? 'Quitter l\'application'
                  : 'Exit App',
              style: const TextStyle(
                fontFamily: 'Cairo',
                fontWeight: FontWeight.bold,
              ),
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
                  lang == AppLanguage.arabic
                      ? 'لا'
                      : lang == AppLanguage.french
                      ? 'Non'
                      : 'No',
                  style: const TextStyle(fontFamily: 'Cairo'),
                ),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                ),
                child: Text(
                  lang == AppLanguage.arabic
                      ? 'خروج'
                      : lang == AppLanguage.french
                      ? 'Quitter'
                      : 'Exit',
                  style: const TextStyle(
                    fontFamily: 'Cairo',
                    fontWeight: FontWeight.bold,
                  ),
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
                child: _WaterWaveBackground(
                  enabled: settings.enablePremiumAnimations,
                ),
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
                          padding: EdgeInsets.fromLTRB(
                            dashboardPadding,
                            0,
                            dashboardPadding,
                            32,
                          ),
                          sliver: SliverList(
                            delegate: SliverChildListDelegate([
                              // ── محدد قسم العمل (الورشة / المحل / الكل) ───────────────
                              _buildMobileSectionSelector(context),

                              // ── إحصائيات ────────────────────────────────────────
                              _buildStatsRow(context),
                              const SizedBox(height: 24),

                              // ── عنوان القسم ──────────────────────────────────────
                              _sectionLabel(
                                Localization.translate('التنقل السريع', lang),
                              ),
                              const SizedBox(height: 12),

                              // ── شبكة التنقل ──────────────────────────────────────
                              _buildMeasurementCard(context),
                              const SizedBox(height: 12),
                              _buildNavGrid(context),
                              const SizedBox(height: 24),

                              // ── مخطط الطلبيات ─────────────────────────────────
                              _sectionLabel(
                                Localization.translate('تحليل الطلبيات', lang),
                              ),
                              const SizedBox(height: 12),
                              _OrdersChartCard(
                                byStatus: _ordersByStatus,
                                byMonth: _ordersByMonth,
                              ),
                              const SizedBox(height: 24),

                              if (settings.canViewSubscription()) ...[
                                // ── بيانات الاشتراك ──────────────────────────────
                                _sectionLabel(
                                  Localization.translate(
                                    'الاشتراك والمدة المتبقية',
                                    lang,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                const SubscriptionOverviewCard(),
                              ],
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
  String _desktopText(
    AppLanguage lang,
    String arabic,
    String french,
    String english,
  ) {
    if (lang == AppLanguage.arabic) return arabic;
    if (lang == AppLanguage.french) return french;
    return english;
  }

  String _desktopSearchable(Map<String, dynamic> row) => row.values
      .map((value) => (value ?? '').toString().toLowerCase())
      .join(' ');

  List<_DesktopSearchResult> _desktopSearchResults(AppLanguage lang) {
    final query = _desktopGlobalSearchQuery.trim().toLowerCase();
    if (query.isEmpty) return const [];
    final results = <_DesktopSearchResult>[];

    for (final order in _desktopOrders) {
      if (!_desktopSearchable(order).contains(query)) continue;
      final number = _desktopOrderDisplayNumber(order);
      final client =
          (order['client_name'] ??
                  order['client_display'] ??
                  '${order['firstname'] ?? ''} ${order['lastname'] ?? ''}')
              .toString()
              .trim();
      results.add(
        _DesktopSearchResult(
          type: 'order',
          title: number > 0 ? '#$number' : 'طلبية',
          subtitle: client.isEmpty
              ? _desktopText(lang, 'طلبية', 'Commande', 'Order')
              : client,
          icon: Icons.receipt_long_rounded,
        ),
      );
      if (results.length >= 8) return results;
    }
    for (final client in _desktopClients) {
      if (!_desktopSearchable(client).contains(query)) continue;
      final name = '${client['firstname'] ?? ''} ${client['lastname'] ?? ''}'
          .trim();
      results.add(
        _DesktopSearchResult(
          type: 'client',
          title: name.isEmpty
              ? _desktopText(lang, 'زبون', 'Client', 'Customer')
              : name,
          subtitle: (client['phone1'] ?? client['phone'] ?? '').toString(),
          icon: Icons.people_alt_rounded,
        ),
      );
      if (results.length >= 8) return results;
    }
    for (final profile in _desktopProfiles) {
      if (!_desktopSearchable(profile).contains(query)) continue;
      results.add(
        _DesktopSearchResult(
          type: 'profile',
          title: (profile['name'] ?? profile['code'] ?? '').toString(),
          subtitle: (profile['type'] ?? profile['code'] ?? '').toString(),
          icon: Icons.category_rounded,
        ),
      );
      if (results.length >= 8) return results;
    }
    return results;
  }

  List<Map<String, dynamic>> _filteredDesktopOrders() {
    final query = _desktopGlobalSearchQuery.trim().toLowerCase();
    if (query.isEmpty) return _desktopOrders;
    return _desktopOrders
        .where((row) => _desktopSearchable(row).contains(query))
        .toList();
  }

  List<Map<String, dynamic>> _filteredDesktopClients() {
    final query = _desktopGlobalSearchQuery.trim().toLowerCase();
    if (query.isEmpty) return _desktopClients;
    return _desktopClients
        .where((row) => _desktopSearchable(row).contains(query))
        .toList();
  }

  Widget _buildDesktopSearchResults(
    BuildContext context,
    AppLanguage lang,
    Color cardColor,
    Color contentColor,
    Color mutedColor,
  ) {
    final results = _desktopSearchResults(lang);
    if (results.isEmpty) {
      return const SizedBox.shrink();
    }
    return Container(
      constraints: const BoxConstraints(maxHeight: 270),
      margin: const EdgeInsets.only(top: 5),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: mutedColor.withValues(alpha: 0.14)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x22000000),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: ListView.separated(
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(vertical: 4),
        itemCount: results.length,
        separatorBuilder: (_, __) => Divider(
          height: 1,
          indent: 46,
          color: mutedColor.withValues(alpha: 0.10),
        ),
        itemBuilder: (context, index) {
          final result = results[index];
          return ListTile(
            dense: true,
            leading: Icon(
              result.icon,
              color: const Color(0xFF4D67F0),
              size: 20,
            ),
            title: Text(
              result.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: contentColor,
                fontFamily: 'Cairo',
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
            subtitle: Text(
              result.subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: mutedColor,
                fontFamily: 'Cairo',
                fontSize: 10,
              ),
            ),
            onTap: () {
              setState(() {
                _selectedDesktopTableTab = result.type == 'client' ? 1 : 0;
                _desktopGlobalSearchController.clear();
                _desktopGlobalSearchQuery = '';
              });
              if (result.type == 'profile') {
                openAdaptiveScreen(
                  context,
                  title: _desktopText(lang, 'المنتجات', 'Produits', 'Products'),
                  icon: Icons.category_rounded,
                  screen: ProductsMenuScreen(db: db),
                );
              } else if (result.type == 'order') {
                _openOrders();
              } else {
                _openClients();
              }
            },
          );
        },
      ),
    );
  }

  Widget _buildDesktopTopBar(
    BuildContext context,
    AppLanguage lang,
    Color cardColor,
    Color contentColor,
    Color mutedColor,
  ) {
    final firebaseUser = AppAuthService().currentUser;
    final email = _userEmail == 'جاري التحميل...'
        ? (firebaseUser?.email ?? '')
        : _userEmail;
    final displayName = firebaseUser?.displayName?.trim().isNotEmpty == true
        ? firebaseUser!.displayName!.trim()
        : (email.contains('@') ? email.split('@').first : email);
    final initial = displayName.isEmpty
        ? 'A'
        : displayName.substring(0, 1).toUpperCase();

    final account = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: mutedColor.withValues(alpha: 0.12)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.035),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(
            radius: 17,
            backgroundColor: const Color(0xFF4D67F0),
            child: Text(
              initial,
              style: const TextStyle(
                color: Colors.white,
                fontFamily: 'Cairo',
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 130),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  displayName.isEmpty
                      ? _desktopText(lang, 'المستخدم', 'Utilisateur', 'User')
                      : displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: contentColor,
                    fontFamily: 'Cairo',
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  _desktopText(
                    lang,
                    'حساب التطبيق',
                    'Compte application',
                    'Application account',
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: mutedColor,
                    fontFamily: 'Cairo',
                    fontSize: 9,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    final search = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          height: 46,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: mutedColor.withValues(alpha: 0.10)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.035),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: TextField(
            controller: _desktopGlobalSearchController,
            textInputAction: TextInputAction.search,
            onChanged: (value) {
              setState(() => _desktopGlobalSearchQuery = value);
            },
            style: TextStyle(
              color: contentColor,
              fontFamily: 'Cairo',
              fontSize: 11,
            ),
            decoration: InputDecoration(
              isDense: true,
              border: InputBorder.none,
              prefixIcon: const Icon(
                Icons.search_rounded,
                color: Color(0xFF4D67F0),
                size: 21,
              ),
              hintText: _desktopText(
                lang,
                'ابحث عن طلبية أو زبون أو منتج...',
                'Rechercher commande, client ou produit...',
                'Search orders, clients, or products...',
              ),
              hintStyle: TextStyle(
                color: mutedColor,
                fontFamily: 'Cairo',
                fontSize: 11,
              ),
              suffixIcon: _desktopGlobalSearchQuery.trim().isEmpty
                  ? null
                  : IconButton(
                      tooltip: _desktopText(
                        lang,
                        'مسح البحث',
                        'Effacer',
                        'Clear',
                      ),
                      icon: const Icon(Icons.close_rounded, size: 18),
                      onPressed: () {
                        _desktopGlobalSearchController.clear();
                        setState(() => _desktopGlobalSearchQuery = '');
                      },
                    ),
              contentPadding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),
        if (_desktopGlobalSearchQuery.trim().isNotEmpty)
          _buildDesktopSearchResults(
            context,
            lang,
            cardColor,
            contentColor,
            mutedColor,
          ),
      ],
    );

    final brand = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: const Color(0xFF4D67F0).withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(13),
            image: _cachedLogoProvider == null
                ? null
                : DecorationImage(
                    image: _cachedLogoProvider!,
                    fit: BoxFit.cover,
                  ),
          ),
          child: _cachedLogoProvider == null
              ? const Icon(Icons.layers_rounded, color: Color(0xFF4D67F0))
              : null,
        ),
        const SizedBox(width: 9),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 190),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _workshopName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: contentColor,
                  fontFamily: 'Cairo',
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text(
                _desktopText(
                  lang,
                  'نظام إدارة الورشة',
                  'Gestion de l’atelier',
                  'Workshop management',
                ),
                style: TextStyle(
                  color: mutedColor,
                  fontFamily: 'Cairo',
                  fontSize: 10,
                ),
              ),
            ],
          ),
        ),
      ],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 820) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [account, const Spacer(), brand]),
              const SizedBox(height: 14),
              search,
            ],
          );
        }
        return Row(
          children: [
            account,
            const SizedBox(width: 12),
            IconButton(
              tooltip: _desktopText(
                lang,
                'تنبيهات المخزون',
                'Alertes stock',
                'Inventory alerts',
              ),
              onPressed: () => _showLowStockNotifications(context),
              icon: const Icon(Icons.notifications_none_rounded),
              color: const Color(0xFF4D67F0),
              style: IconButton.styleFrom(
                backgroundColor: cardColor,
                side: BorderSide(color: mutedColor.withValues(alpha: 0.10)),
              ),
            ),
            const SizedBox(width: 18),
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: search,
                ),
              ),
            ),
            const SizedBox(width: 18),
            brand,
          ],
        );
      },
    );
  }

  Widget _buildDesktopDashboard(BuildContext context) {
    final settings = Provider.of<AppSettingsProvider>(context);
    final lang = settings.language;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final pageColor = isDark
        ? const Color(0xFF0F172A)
        : const Color(0xFFF6F8FC);
    final cardColor = isDark ? const Color(0xFF172033) : Colors.white;
    final contentColor = isDark
        ? const Color(0xFFE5E7EB)
        : const Color(0xFF17233A);
    final mutedColor = isDark
        ? const Color(0xFF94A3B8)
        : const Color(0xFF64748B);

    return Container(
      color: pageColor,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(28, 22, 28, 36),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1440),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildDesktopTopBar(
                  context,
                  lang,
                  cardColor,
                  contentColor,
                  mutedColor,
                ),
                const SizedBox(height: 26),
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
                                _desktopText(
                                  lang,
                                  'لوحة القيادة والإحصائيات',
                                  'Tableau de bord et statistiques',
                                  'Dashboard and statistics',
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: contentColor,
                                  fontFamily: 'Cairo',
                                  fontSize: 21,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              Text(
                                _desktopText(
                                  lang,
                                  'متابعة فورية للورشة والطلبات والمخزون',
                                  'Suivi de l’atelier, des commandes et du stock',
                                  'Live workshop, orders, and inventory overview',
                                ),
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
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.sync_rounded, size: 18),
                      label: Text(
                        _desktopText(
                          lang,
                          'تحديث البيانات',
                          'Actualiser',
                          'Refresh data',
                        ),
                        style: const TextStyle(
                          fontFamily: 'Cairo',
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF2563EB),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 13,
                        ),
                      ),
                    );
                    final sectionSelector = _buildDesktopSectionSelector(context, lang, cardColor, contentColor, mutedColor);
                    if (narrow) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          title,
                          if (sectionSelector != null) ...[
                            const SizedBox(height: 14),
                            sectionSelector,
                          ],
                          const SizedBox(height: 14),
                          refresh,
                        ],
                      );
                    }
                    return Row(
                      children: [
                        Expanded(child: title),
                        if (sectionSelector != null) ...[
                          const SizedBox(width: 14),
                          sectionSelector,
                        ],
                        const SizedBox(width: 12),
                        refresh,
                      ],
                    );
                  },
                ),
                const SizedBox(height: 22),
                _buildDesktopMetrics(
                  context,
                  cardColor,
                  contentColor,
                  mutedColor,
                ),
                const SizedBox(height: 18),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final sideWidth = 290.0;
                    final isCompact = constraints.maxWidth < 980;
                    final orders = _buildDesktopTrendPanel(
                      context,
                      cardColor,
                      contentColor,
                      mutedColor,
                    );
                    final side = Column(
                      children: [
                        _buildDesktopWorkloadPanel(
                          context,
                          cardColor,
                          contentColor,
                          mutedColor,
                        ),
                        const SizedBox(height: 16),
                        _buildDesktopActivityPanel(
                          context,
                          cardColor,
                          contentColor,
                          mutedColor,
                        ),
                      ],
                    );
                    if (isCompact) {
                      return Column(
                        children: [orders, const SizedBox(height: 16), side],
                      );
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
                LayoutBuilder(
                  builder: (context, constraints) {
                    final orders = _buildDesktopOrdersPanel(
                      context,
                      cardColor,
                      contentColor,
                      mutedColor,
                    );
                    // Stock alerts live below the open-orders metric.  Keeping
                    // a second, wide stock panel here made the dashboard much
                    // taller and could overflow in smaller desktop windows.
                    return orders;
                  },
                ),
                if (settings.canViewSubscription()) ...[
                  const SizedBox(height: 18),
                  const SubscriptionOverviewCard(),
                ],
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
    final values = _ordersByMonth.values
        .map((value) => value.toDouble())
        .toList();
    final clientValues = _clientAdditionsByMonth();
    final cards = <Widget>[
      if (settings.canViewOrders())
        _DesktopMetricCard(
          icon: Icons.receipt_long_rounded,
          title: _desktopText(
            lang,
            'إجمالي الطلبيات',
            'Total des commandes',
            'Total orders',
          ),
          value: _commandesCount,
          caption: _cmdTrend.isEmpty
              ? _desktopText(
                  lang,
                  'كل الطلبيات',
                  'Toutes les commandes',
                  'All orders',
                )
              : _cmdTrend,
          color: const Color(0xFF2563EB),
          values: values,
          backgroundColor: cardColor,
          textColor: contentColor,
          mutedColor: mutedColor,
          onTap: _openOrders,
          secondaryLabel: _desktopText(
            lang,
            'تنبيهات المخزون',
            'Alertes de stock',
            'Stock alerts',
          ),
          secondaryValue: _lowStockCount.toString(),
          secondaryIcon: _lowStockCount == 0
              ? Icons.verified_rounded
              : Icons.warning_amber_rounded,
          secondaryColor: _lowStockCount == 0
              ? const Color(0xFF10B981)
              : const Color(0xFFF97316),
          onSecondaryTap: () => _showLowStockNotifications(context),
        ),
      if (settings.canAccessTreasury())
        _DesktopMetricCard(
          icon: Icons.account_balance_wallet_rounded,
          title: _desktopText(
            lang,
            'رصيد الخزينة',
            'Solde de trésorerie',
            'Treasury balance',
          ),
          value: _formatCurrency(_treasuryBalance),
          caption: _desktopText(
            lang,
            'المتاح حالياً',
            'Disponible actuellement',
            'Available now',
          ),
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
        icon: Icons.people_alt_rounded,
        title: _desktopText(
          lang,
          'إجمالي الزبائن',
          'Total des clients',
          'Total clients',
        ),
        value: _clientsCount,
        caption: _cliTrend.isEmpty
            ? _desktopText(
                lang,
                'الزبائن المضافون حديثاً',
                'Clients ajoutés récemment',
                'Recently added clients',
              )
            : _cliTrend,
        color: const Color(0xFF8B5CF6),
        values: clientValues,
        backgroundColor: cardColor,
        textColor: contentColor,
        mutedColor: mutedColor,
        onTap: settings.canViewClients() ? _openClients : null,
      ),
      if (settings.canViewOrders())
        _DesktopMetricCard(
          icon: Icons.pending_actions_rounded,
          title: _desktopText(
            lang,
            'طلبيات مفتوحة',
            'Commandes ouvertes',
            'Open orders',
          ),
          value: _pendingOrdersCount.toString(),
          caption: _desktopText(
            lang,
            'تحتاج إلى متابعة',
            'À suivre',
            'Need follow-up',
          ),
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
        final columns = constraints.maxWidth >= 1180
            ? 4
            : constraints.maxWidth >= 660
            ? 2
            : 1;
        final width = (constraints.maxWidth - ((columns - 1) * gap)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final card in cards) SizedBox(width: width, child: card),
          ],
        );
      },
    );
  }

  Widget _buildDesktopTrendPanel(
    BuildContext context,
    Color cardColor,
    Color contentColor,
    Color mutedColor,
  ) {
    final lang = Provider.of<AppSettingsProvider>(context).language;
    final entries = _ordersByMonth.entries.toList();
    final values = entries.map((entry) => entry.value.toDouble()).toList();
    final maxValue = entries.fold<int>(
      0,
      (maximum, entry) => math.max(maximum, entry.value),
    );

    return _desktopPanel(
      context: context,
      title: _desktopText(
        lang,
        'حركة الطلبيات',
        'Évolution des commandes',
        'Order activity',
      ),
      subtitle: _desktopText(
        lang,
        'مقارنة الطلبيات المسجلة خلال الأشهر الأخيرة',
        'Comparaison des commandes des derniers mois',
        'Comparison of orders from recent months',
      ),
      icon: Icons.query_stats_rounded,
      color: const Color(0xFF4D67F0),
      backgroundColor: cardColor,
      textColor: contentColor,
      mutedColor: mutedColor,
      child: SizedBox(
        height: 350,
        child: Column(
          children: [
            Row(
              children: [
                _desktopTrendLegend(
                  const Color(0xFF7289F4),
                  _desktopText(lang, 'الطلبيات', 'Commandes', 'Orders'),
                  mutedColor,
                ),
                const SizedBox(width: 16),
                _desktopTrendLegend(
                  const Color(0xFF10B981),
                  _desktopText(
                    lang,
                    'اتجاه النشاط',
                    'Tendance',
                    'Activity trend',
                  ),
                  mutedColor,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final usableHeight = math.max(
                    1.0,
                    constraints.maxHeight - 20,
                  );
                  return Stack(
                    children: [
                      Positioned.fill(
                        child: Column(
                          children: List.generate(
                            4,
                            (_) => Expanded(
                              child: Align(
                                alignment: Alignment.bottomCenter,
                                child: Divider(
                                  color: mutedColor.withValues(alpha: 0.14),
                                  height: 1,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      Positioned.fill(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 13,
                            vertical: 10,
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              for (final entry in entries)
                                Expanded(
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 7,
                                    ),
                                    child: Align(
                                      alignment: Alignment.bottomCenter,
                                      child: Container(
                                        height: maxValue == 0
                                            ? 3
                                            : math.max(
                                                4.0,
                                                usableHeight *
                                                    entry.value /
                                                    maxValue,
                                              ),
                                        decoration: BoxDecoration(
                                          color: const Color(
                                            0xFF7289F4,
                                          ).withValues(alpha: 0.92),
                                          borderRadius:
                                              const BorderRadius.vertical(
                                                top: Radius.circular(7),
                                              ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                      Positioned.fill(
                        child: IgnorePointer(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 18,
                              vertical: 12,
                            ),
                            child: Opacity(
                              opacity: 0.9,
                              child: _DesktopSparkline(
                                values: values,
                                color: const Color(0xFF10B981),
                                fill: false,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                for (final entry in entries)
                  Expanded(
                    child: Text(
                      _desktopTrendMonth(entry.key, lang),
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: mutedColor,
                        fontFamily: 'Cairo',
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _desktopTrendLegend(Color color, String label, Color mutedColor) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: TextStyle(
            color: mutedColor,
            fontFamily: 'Cairo',
            fontSize: 10,
          ),
        ),
      ],
    );
  }

  String _desktopTrendMonth(String key, AppLanguage lang) {
    final month = int.tryParse(key.split('/').first);
    const arabic = [
      '',
      'يناير',
      'فبراير',
      'مارس',
      'أبريل',
      'مايو',
      'يونيو',
      'يوليو',
      'أغسطس',
      'سبتمبر',
      'أكتوبر',
      'نوفمبر',
      'ديسمبر',
    ];
    const french = [
      '',
      'janv.',
      'févr.',
      'mars',
      'avr.',
      'mai',
      'juin',
      'juil.',
      'août',
      'sept.',
      'oct.',
      'nov.',
      'déc.',
    ];
    const english = [
      '',
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    if (month == null || month < 1 || month > 12) return key;
    return _desktopText(lang, arabic[month], french[month], english[month]);
  }

  Widget _buildDesktopOrdersPanel(
    BuildContext context,
    Color cardColor,
    Color contentColor,
    Color mutedColor,
  ) {
    final settings = Provider.of<AppSettingsProvider>(context);
    final lang = settings.language;
    final selectedTab =
        !settings.canAccessTreasury() && _selectedDesktopTableTab == 2
        ? 0
        : _selectedDesktopTableTab;
    if (selectedTab == 2) {
      return _buildDesktopTreasuryPanel(
        context,
        cardColor,
        contentColor,
        mutedColor,
        lang,
      );
    }
    final isOrdersTab = selectedTab == 0;

    return _desktopPanel(
      context: context,
      title: isOrdersTab
          ? _desktopText(
              lang,
              'متابعة الطلبيات والمشاريع',
              'Suivi des commandes',
              'Orders & Projects',
            )
          : _desktopText(
              lang,
              'سجل الزبائن والحسابات',
              'Registre des clients',
              'Clients & Accounts',
            ),
      subtitle: isOrdersTab
          ? _desktopText(
              lang,
              'تفاصيل الحسابات، العمال وحالة العمل بالورشة',
              'Détails des commandes',
              'Detailed orders & assignments',
            )
          : _desktopText(
              lang,
              'إجمالي المبيعات، الدفعات والديون المتبقية للزبائن',
              'Détails des comptes clients',
              'Client balances & debts',
            ),
      icon: isOrdersTab ? Icons.table_rows_rounded : Icons.people_alt_rounded,
      color: isOrdersTab ? const Color(0xFF2563EB) : const Color(0xFF0EA5E9),
      backgroundColor: cardColor,
      textColor: contentColor,
      mutedColor: mutedColor,
      action: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Consumer<AppSettingsProvider>(
            builder: (context, appSettings, _) {
              final canAdd = isOrdersTab
                  ? appSettings.canCreateOrders()
                  : appSettings.canCreateClients();
              if (!canAdd) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsetsDirectional.only(end: 10),
                child: FilledButton.icon(
                  onPressed: () {
                    if (isOrdersTab) {
                      _openOrders(openAddOrderOnStart: true);
                    } else {
                      _openClients(openAddClientOnStart: true);
                    }
                  },
                  icon: const Icon(Icons.add_rounded, size: 16),
                  label: Text(
                    isOrdersTab
                        ? _desktopText(
                            lang,
                            'إضافة طلبية',
                            'Ajouter commande',
                            'Add Order',
                          )
                        : _desktopText(
                            lang,
                            'إضافة زبون',
                            'Ajouter client',
                            'Add Client',
                          ),
                    style: const TextStyle(
                      fontFamily: 'Cairo',
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: isOrdersTab
                        ? const Color(0xFF2563EB)
                        : const Color(0xFF0EA5E9),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                  ),
                ),
              );
            },
          ),
          SegmentedButton<int>(
            segments: [
              ButtonSegment(
                value: 0,
                label: Text(
                  _desktopText(lang, 'الطلبيات', 'Commandes', 'Orders'),
                  style: const TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                icon: const Icon(Icons.receipt_long_rounded, size: 14),
              ),
              ButtonSegment(
                value: 1,
                label: Text(
                  _desktopText(lang, 'الزبائن', 'Clients', 'Clients'),
                  style: const TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                icon: const Icon(Icons.people_alt_rounded, size: 14),
              ),
              if (settings.canAccessTreasury())
                ButtonSegment(
                  value: 2,
                  label: Text(
                    _desktopText(lang, 'الصندوق', 'Trésorerie', 'Treasury'),
                    style: const TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  icon: const Icon(
                    Icons.account_balance_wallet_rounded,
                    size: 14,
                  ),
                ),
            ],
            selected: {selectedTab},
            onSelectionChanged: (set) {
              if (set.isNotEmpty) {
                setState(() {
                  _selectedDesktopTableTab = set.first;
                });
              }
            },
            style: const ButtonStyle(
              visualDensity: VisualDensity.compact,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
          const SizedBox(width: 8),
          TextButton.icon(
            onPressed: isOrdersTab ? _openOrders : _openClients,
            icon: const Icon(Icons.arrow_forward_rounded, size: 16),
            label: Text(
              isOrdersTab
                  ? _desktopText(lang, 'كل الطلبيات', 'Tout voir', 'View all')
                  : _desktopText(
                      lang,
                      'كل الزبائن',
                      'Tous les clients',
                      'All clients',
                    ),
              style: const TextStyle(fontFamily: 'Cairo'),
            ),
          ),
        ],
      ),
      child: SizedBox(
        height: 380,
        child: isOrdersTab
            ? _buildDetailedOrdersTable(context, contentColor, mutedColor, lang)
            : _buildDetailedClientsTable(
                context,
                contentColor,
                mutedColor,
                lang,
              ),
      ),
    );
  }

  Widget _buildDesktopTreasuryPanel(
    BuildContext context,
    Color cardColor,
    Color contentColor,
    Color mutedColor,
    AppLanguage lang,
  ) {
    return _desktopPanel(
      context: context,
      title: _desktopText(
        lang,
        'سجل الصندوق',
        'Registre de trésorerie',
        'Treasury register',
      ),
      subtitle: _desktopText(
        lang,
        'تابع عمليات الدفع والسحب والمُدخل والتاريخ من مكان واحد',
        'Suivez les encaissements, décaissements et saisies',
        'Track income, withdrawals, dates, and entries in one place',
      ),
      icon: Icons.account_balance_wallet_rounded,
      color: const Color(0xFF0EA5A4),
      backgroundColor: cardColor,
      textColor: contentColor,
      mutedColor: mutedColor,
      action: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SegmentedButton<int>(
            segments: [
              ButtonSegment(
                value: 0,
                label: Text(
                  _desktopText(lang, 'الطلبيات', 'Commandes', 'Orders'),
                  style: const TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                icon: const Icon(Icons.receipt_long_rounded, size: 14),
              ),
              ButtonSegment(
                value: 1,
                label: Text(
                  _desktopText(lang, 'الزبائن', 'Clients', 'Clients'),
                  style: const TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                icon: const Icon(Icons.people_alt_rounded, size: 14),
              ),
              ButtonSegment(
                value: 2,
                label: Text(
                  _desktopText(lang, 'الصندوق', 'Trésorerie', 'Treasury'),
                  style: const TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                icon: const Icon(
                  Icons.account_balance_wallet_rounded,
                  size: 14,
                ),
              ),
            ],
            selected: const {2},
            onSelectionChanged: (set) {
              if (set.isNotEmpty) {
                setState(() => _selectedDesktopTableTab = set.first);
              }
            },
            style: const ButtonStyle(
              visualDensity: VisualDensity.compact,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            onPressed: () => TreasuryScreen.showQuickTransactionDialog(
              context,
              db: db,
              initialType: 'Encaissement',
              onSaved: () => _loadStats(),
            ),
            icon: const Icon(Icons.arrow_downward_rounded, size: 14, color: Colors.white),
            label: Text(
              _desktopText(lang, '+ قبض', '+ Encaissement', '+ Income'),
              style: const TextStyle(
                fontFamily: 'Cairo',
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF10B981),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
              visualDensity: VisualDensity.compact,
              elevation: 0,
            ),
          ),
          const SizedBox(width: 6),
          ElevatedButton.icon(
            onPressed: () => TreasuryScreen.showQuickTransactionDialog(
              context,
              db: db,
              initialType: 'Décaissement',
              onSaved: () => _loadStats(),
            ),
            icon: const Icon(Icons.arrow_upward_rounded, size: 14, color: Colors.white),
            label: Text(
              _desktopText(lang, '- دفع', '- Décaissement', '- Expense'),
              style: const TextStyle(
                fontFamily: 'Cairo',
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFF59E0B),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
              visualDensity: VisualDensity.compact,
              elevation: 0,
            ),
          ),
          const SizedBox(width: 8),
          TextButton.icon(
            onPressed: _openTreasury,
            icon: const Icon(Icons.arrow_forward_rounded, size: 16),
            label: Text(
              _desktopText(lang, 'كل العمليات', 'Tout voir', 'View all'),
              style: const TextStyle(fontFamily: 'Cairo'),
            ),
          ),
        ],
      ),
      child: SizedBox(
        height: 420,
        child: _buildDetailedTreasuryTable(contentColor, mutedColor, lang),
      ),
    );
  }

  void _openTreasury() {
    final lang = Provider.of<AppSettingsProvider>(
      context,
      listen: false,
    ).language;
    openAdaptiveScreen(
      context,
      title: _desktopText(lang, 'الصندوق', 'Trésorerie', 'Treasury'),
      icon: Icons.account_balance_wallet_rounded,
      screen: TreasuryScreen(db: db),
    );
  }

  void _openClients({bool openAddClientOnStart = false}) {
    openAdaptiveScreen(
      context,
      title: Localization.translate(
        'الزبائن',
        Provider.of<AppSettingsProvider>(context, listen: false).language,
      ),
      icon: Icons.people_alt_rounded,
      screen: Customers(openAddClientOnStart: openAddClientOnStart),
    );
  }

  int _desktopOrderDisplayNumber(Map<String, dynamic> order) {
    for (final key in const ['display_number', 'order_code']) {
      final value = order[key];
      final number = value is num
          ? value.toInt()
          : int.tryParse(value?.toString().trim() ?? '');
      if (number != null && number > 0) return number;
    }
    final id = order['id'];
    return id is num ? id.toInt() : int.tryParse(id?.toString() ?? '') ?? 0;
  }

  Widget _buildDetailedOrdersTable(
    BuildContext context,
    Color contentColor,
    Color mutedColor,
    AppLanguage lang,
  ) {
    if (_desktopOrders.isEmpty) {
      return Center(
        child: Text(
          _desktopText(
            lang,
            'لا توجد طلبيات مسجلة بعد',
            'Aucune commande',
            'No recorded orders',
          ),
          style: TextStyle(fontFamily: 'Cairo', color: mutedColor),
        ),
      );
    }

    final columns = [
      ResizableTableColumn(
        id: 'id',
        label: _desktopTableHeaderLabel('#', mutedColor),
        initialWidth: 60,
        minWidth: 45,
        maxWidth: 100,
      ),
      ResizableTableColumn(
        id: 'client_project',
        label: _desktopTableHeaderLabel(
          _desktopText(
            lang,
            'الزبون والمشروع',
            'Client & Projet',
            'Client & Project',
          ),
          mutedColor,
        ),
        initialWidth: 200,
        minWidth: 120,
        maxWidth: 350,
      ),
      ResizableTableColumn(
        id: 'date',
        label: _desktopTableHeaderLabel(
          _desktopText(lang, 'تاريخ الإنشاء', 'Date création', 'Order Date'),
          mutedColor,
        ),
        initialWidth: 110,
        minWidth: 90,
        maxWidth: 180,
      ),
      ResizableTableColumn(
        id: 'total',
        label: _desktopTableHeaderLabel(
          _desktopText(lang, 'المجموع (د.ج)', 'Total (DA)', 'Total (DA)'),
          mutedColor,
        ),
        initialWidth: 120,
        minWidth: 90,
        maxWidth: 200,
      ),
      ResizableTableColumn(
        id: 'advance',
        label: _desktopTableHeaderLabel(
          _desktopText(lang, 'المدفوع', 'Payé', 'Paid'),
          mutedColor,
        ),
        initialWidth: 110,
        minWidth: 85,
        maxWidth: 180,
      ),
      ResizableTableColumn(
        id: 'remaining',
        label: _desktopTableHeaderLabel(
          _desktopText(lang, 'المتبقي', 'Reste', 'Balance'),
          mutedColor,
        ),
        initialWidth: 110,
        minWidth: 85,
        maxWidth: 180,
      ),
      ResizableTableColumn(
        id: 'status',
        label: _desktopTableHeaderLabel(
          _desktopText(lang, 'حالة الورشة', 'Statut', 'Status'),
          mutedColor,
        ),
        initialWidth: 120,
        minWidth: 90,
        maxWidth: 200,
      ),
      ResizableTableColumn(
        id: 'creator',
        label: _desktopTableHeaderLabel(
          _desktopText(lang, 'المُدخل', 'Inscrit par', 'Recorded By'),
          mutedColor,
        ),
        initialWidth: 130,
        minWidth: 90,
        maxWidth: 220,
      ),
      ResizableTableColumn(
        id: 'workers',
        label: _desktopTableHeaderLabel(
          _desktopText(lang, 'فريق التنفيذ', 'Assignés', 'Assigned Workers'),
          mutedColor,
        ),
        initialWidth: 160,
        minWidth: 110,
        maxWidth: 300,
      ),
    ];

    final displayOrders = _filteredDesktopOrders().take(15).toList();
    final rows = displayOrders.map((order) {
      final orderId = (order['id'] as num?)?.toInt() ?? 0;
      final status = (order['status'] ?? 'Pending').toString();
      final color = _desktopStatusColor(status);
      final firstName = (order['firstname'] ?? '').toString().trim();
      final lastName = (order['lastname'] ?? '').toString().trim();
      final clientName = '$firstName $lastName'.trim();
      final projectName = (order['project_name'] ?? '').toString().trim();
      final clientProject = projectName.isNotEmpty
          ? '$clientName ($projectName)'
          : clientName;

      final total =
          (order['net_payable'] as num?)?.toDouble() ??
          (order['total'] as num?)?.toDouble() ??
          0.0;
      final advance = (order['advance_payment'] as num?)?.toDouble() ?? 0.0;
      final remaining = total - advance;
      final creator = _formatCreatorDisplay(
        order['creation_platform']?.toString(),
      );
      final assignedWorkers =
          _assignedWorkersMap[orderId] ??
          _desktopText(lang, 'غير مُسند', 'Non assigné', 'Unassigned');

      return ResizableTableRow(
        onTap: _openOrders,
        cells: [
          Text(
            '#${_desktopOrderDisplayNumber(order)}',
            style: const TextStyle(
              fontFamily: 'Cairo',
              fontWeight: FontWeight.bold,
              color: Color(0xFF2563EB),
              fontSize: 12,
            ),
          ),
          Text(
            clientProject.isEmpty ? 'زبون عام' : clientProject,
            style: TextStyle(
              fontFamily: 'Cairo',
              color: contentColor,
              fontSize: 12,
            ),
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            _formatDate(order['created_at']),
            style: TextStyle(
              fontFamily: 'Cairo',
              color: mutedColor,
              fontSize: 11,
            ),
          ),
          Text(
            _formatCurrency(total),
            style: TextStyle(
              fontFamily: 'Cairo',
              color: contentColor,
              fontSize: 12,
            ),
          ),
          Text(
            _formatCurrency(advance),
            style: const TextStyle(
              fontFamily: 'Cairo',
              color: Color(0xFF10B981),
              fontSize: 12,
            ),
          ),
          Text(
            _formatCurrency(remaining),
            style: TextStyle(
              fontFamily: 'Cairo',
              color: remaining > 0
                  ? const Color(0xFFEF4444)
                  : const Color(0xFF10B981),
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: color.withOpacity(0.13),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              _desktopStatusText(status, lang),
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontSize: 10,
                fontWeight: FontWeight.w800,
                fontFamily: 'Cairo',
              ),
            ),
          ),
          Text(
            creator,
            style: TextStyle(
              fontFamily: 'Cairo',
              color: mutedColor,
              fontSize: 11,
            ),
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            assignedWorkers,
            style: TextStyle(
              fontFamily: 'Cairo',
              color: contentColor,
              fontSize: 11,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      );
    }).toList();

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: ResizableColumnsTable(
        persistenceKey: 'dashboard_primary',
        columns: columns,
        rows: rows,
        headerColor: const Color(0xFF2563EB).withOpacity(0.08),
        borderColor: mutedColor.withOpacity(0.12),
        rowColor: Colors.transparent,
        headerMinHeight: 36,
        rowMinHeight: 44,
      ),
    );
  }

  String _formatCreatorDisplay(String? rawPlatform) {
    String raw = (rawPlatform ?? '').trim();
    raw = raw
        .replaceFirst(
          RegExp(
            r'\s+\((?:web|phone|computer|هاتف|كمبيوتر|ÙˆÙŠØ¨|ÙƒÙ…Ø¨ÙŠÙˆØªØ±|Ù‡Ø§ØªÙ)\)$',
            caseSensitive: false,
          ),
          '',
        )
        .trim();
    if (raw.isNotEmpty &&
        raw != 'unknown' &&
        raw != 'تطبيق' &&
        raw != 'phone' &&
        raw != 'computer' &&
        raw != 'web' &&
        raw != 'هاتف' &&
        raw != 'كمبيوتر' &&
        raw != 'المدير / عامل الورشة') {
      return raw;
    }
    final user = AppAuthService().currentUser;
    if (user != null) {
      final emailName = user.email?.contains('@') == true
          ? user.email!.split('@').first
          : '';
      final displayName = user.displayName?.trim().isNotEmpty == true
          ? user.displayName!.trim()
          : emailName;
      if (displayName.isNotEmpty) {
        if (raw.isNotEmpty) {
          return '$displayName ($raw)';
        }
        return displayName;
      }
    }
    return 'المدير / عامل الورشة';
  }

  Widget _desktopDetailedOrderRow(
    BuildContext context,
    Map<String, dynamic> order,
    Color contentColor,
    Color mutedColor,
    AppLanguage lang,
  ) {
    final orderId = (order['id'] as num?)?.toInt() ?? 0;
    final status = (order['status'] ?? 'Pending').toString();
    final color = _desktopStatusColor(status);
    final firstName = (order['firstname'] ?? '').toString().trim();
    final lastName = (order['lastname'] ?? '').toString().trim();
    final clientName = '$firstName $lastName'.trim();
    final projectName = (order['project_name'] ?? '').toString().trim();
    final clientProject = projectName.isNotEmpty
        ? '$clientName ($projectName)'
        : clientName;

    final total =
        (order['net_payable'] as num?)?.toDouble() ??
        (order['total'] as num?)?.toDouble() ??
        0.0;
    final advance = (order['advance_payment'] as num?)?.toDouble() ?? 0.0;
    final remaining = total - advance;
    final creator = _formatCreatorDisplay(
      order['creation_platform']?.toString(),
    );
    final assignedWorkers =
        _assignedWorkersMap[orderId] ??
        _desktopText(lang, 'غير مُسند', 'Non assigné', 'Unassigned');

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _openOrders,
        child: Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              _desktopTableCell(
                '#${_desktopOrderDisplayNumber(order)}',
                1,
                contentColor,
                false,
                colorOverride: const Color(0xFF2563EB),
              ),
              _desktopTableCell(
                clientProject.isEmpty ? 'زبون عام' : clientProject,
                3,
                contentColor,
                false,
              ),
              _desktopTableCell(
                _formatDate(order['created_at']),
                2,
                mutedColor,
                false,
              ),
              _desktopTableCell(_formatCurrency(total), 2, contentColor, false),
              _desktopTableCell(
                _formatCurrency(advance),
                2,
                const Color(0xFF10B981),
                false,
              ),
              _desktopTableCell(
                _formatCurrency(remaining),
                2,
                remaining > 0
                    ? const Color(0xFFEF4444)
                    : const Color(0xFF10B981),
                false,
                fontWeight: FontWeight.bold,
              ),
              Expanded(
                flex: 2,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.13),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      _desktopStatusText(status, lang),
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: color,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        fontFamily: 'Cairo',
                      ),
                    ),
                  ),
                ),
              ),
              _desktopTableCell(creator, 2, mutedColor, false),
              _desktopTableCell(assignedWorkers, 3, contentColor, false),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailedClientsTable(
    BuildContext context,
    Color contentColor,
    Color mutedColor,
    AppLanguage lang,
  ) {
    if (_desktopClients.isEmpty) {
      return Center(
        child: Text(
          _desktopText(
            lang,
            'لا يوجد زبائن مسجلين بعد',
            'Aucun client',
            'No clients',
          ),
          style: TextStyle(fontFamily: 'Cairo', color: mutedColor),
        ),
      );
    }

    final columns = [
      ResizableTableColumn(
        id: 'id',
        label: _desktopTableHeaderLabel('#', mutedColor),
        initialWidth: 60,
        minWidth: 45,
        maxWidth: 100,
      ),
      ResizableTableColumn(
        id: 'name',
        label: _desktopTableHeaderLabel(
          _desktopText(lang, 'اسم الزبون', 'Nom client', 'Client Name'),
          mutedColor,
        ),
        initialWidth: 180,
        minWidth: 120,
        maxWidth: 320,
      ),
      ResizableTableColumn(
        id: 'phone',
        label: _desktopTableHeaderLabel(
          _desktopText(lang, 'رقم الهاتف', 'Téléphone', 'Phone'),
          mutedColor,
        ),
        initialWidth: 130,
        minWidth: 95,
        maxWidth: 200,
      ),
      ResizableTableColumn(
        id: 'address',
        label: _desktopTableHeaderLabel(
          _desktopText(lang, 'العنوان', 'Adresse', 'Address'),
          mutedColor,
        ),
        initialWidth: 140,
        minWidth: 95,
        maxWidth: 240,
      ),
      ResizableTableColumn(
        id: 'email',
        label: _desktopTableHeaderLabel(
          _desktopText(lang, 'البريد الإلكتروني', 'E-mail', 'Email'),
          mutedColor,
        ),
        initialWidth: 140,
        minWidth: 95,
        maxWidth: 240,
      ),
      ResizableTableColumn(
        id: 'fiscal',
        label: _desktopTableHeaderLabel(
          _desktopText(
            lang,
            'البيانات الجبائية (NIF/RC)',
            'Fiscaux',
            'Tax & Com',
          ),
          mutedColor,
        ),
        initialWidth: 150,
        minWidth: 100,
        maxWidth: 260,
      ),
      ResizableTableColumn(
        id: 'date',
        label: _desktopTableHeaderLabel(
          _desktopText(lang, 'تاريخ الإضافة', 'Date d\'ajout', 'Added Date'),
          mutedColor,
        ),
        initialWidth: 110,
        minWidth: 85,
        maxWidth: 180,
      ),
      ResizableTableColumn(
        id: 'total',
        label: _desktopTableHeaderLabel(
          _desktopText(lang, 'مجموع الحسابات', 'Total', 'Total'),
          mutedColor,
        ),
        initialWidth: 120,
        minWidth: 90,
        maxWidth: 200,
      ),
      ResizableTableColumn(
        id: 'paid',
        label: _desktopTableHeaderLabel(
          _desktopText(lang, 'المدفوع', 'Payé', 'Paid'),
          mutedColor,
        ),
        initialWidth: 110,
        minWidth: 85,
        maxWidth: 180,
      ),
      ResizableTableColumn(
        id: 'remaining',
        label: _desktopTableHeaderLabel(
          _desktopText(lang, 'المتبقي', 'Reste', 'Remaining'),
          mutedColor,
        ),
        initialWidth: 110,
        minWidth: 85,
        maxWidth: 180,
      ),
      ResizableTableColumn(
        id: 'orders_count',
        label: _desktopTableHeaderLabel(
          _desktopText(lang, 'عدد الطلبيات', 'Cmds', 'Orders'),
          mutedColor,
        ),
        initialWidth: 80,
        minWidth: 60,
        maxWidth: 130,
      ),
      ResizableTableColumn(
        id: 'creator',
        label: _desktopTableHeaderLabel(
          _desktopText(lang, 'المُضيف', 'Ajouté par', 'Added By'),
          mutedColor,
        ),
        initialWidth: 120,
        minWidth: 90,
        maxWidth: 200,
      ),
    ];

    final displayClients = _filteredDesktopClients().take(15).toList();
    final rows = displayClients.map((client) {
      final clientId = (client['id'] as num?)?.toInt() ?? 0;
      final clientNumber =
          (client['display_number'] as num?)?.toInt() ?? clientId;
      final firstName = (client['firstname'] ?? '').toString().trim();
      final lastName = (client['lastname'] ?? '').toString().trim();
      final fullName = '$firstName $lastName'.trim();

      final phone1 = (client['phone1'] ?? '').toString().trim();
      final phone2 = (client['phone2'] ?? '').toString().trim();
      final phoneDisplay = phone1.isNotEmpty
          ? (phone2.isNotEmpty && phone2 != '0' ? '$phone1 / $phone2' : phone1)
          : (phone2.isNotEmpty && phone2 != '0' ? phone2 : '—');

      final addressDisplay =
          (client['address'] ?? '').toString().trim().isNotEmpty
          ? client['address'].toString().trim()
          : '—';

      final emailDisplay = (client['email'] ?? '').toString().trim().isNotEmpty
          ? client['email'].toString().trim()
          : '—';

      final nif = (client['nif'] ?? '').toString().trim();
      final nis = (client['nis'] ?? '').toString().trim();
      final rc = (client['rc'] ?? '').toString().trim();
      final ai = (client['ai'] ?? '').toString().trim();

      final List<String> taxParts = [];
      if (nif.isNotEmpty) taxParts.add('NIF: $nif');
      if (nis.isNotEmpty) taxParts.add('NIS: $nis');
      if (rc.isNotEmpty) taxParts.add('RC: $rc');
      if (ai.isNotEmpty) taxParts.add('AI: $ai');
      final taxDisplay = taxParts.isNotEmpty ? taxParts.join(' | ') : '—';

      final clientOrders = _desktopOrders
          .where((o) => (o['client_id'] as num?)?.toInt() == clientId)
          .toList();
      double totalSum = 0.0;
      double paidSum = 0.0;
      for (var o in clientOrders) {
        double net =
            (o['net_payable'] as num?)?.toDouble() ??
            (o['total'] as num?)?.toDouble() ??
            0.0;
        double advance = (o['advance_payment'] as num?)?.toDouble() ?? 0.0;
        totalSum += net;
        paidSum += advance;
      }
      double remainingDebt = totalSum - paidSum;
      final addedBy = _formatCreatorDisplay(
        client['creation_platform']?.toString(),
      );

      return ResizableTableRow(
        onTap: _openClients,
        cells: [
          Text(
            '#$clientNumber',
            style: const TextStyle(
              fontFamily: 'Cairo',
              fontWeight: FontWeight.bold,
              color: Color(0xFF0EA5E9),
              fontSize: 12,
            ),
          ),
          Text(
            fullName.isEmpty ? 'زبون #$clientNumber' : fullName,
            style: const TextStyle(
              fontFamily: 'Cairo',
              color: Color(0xFF0EA5E9),
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            phoneDisplay,
            style: TextStyle(
              fontFamily: 'Cairo',
              color: contentColor,
              fontSize: 11.5,
            ),
          ),
          Text(
            addressDisplay,
            style: TextStyle(
              fontFamily: 'Cairo',
              color: mutedColor,
              fontSize: 11.5,
            ),
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            emailDisplay,
            style: TextStyle(
              fontFamily: 'Cairo',
              color: mutedColor,
              fontSize: 11.5,
            ),
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            taxDisplay,
            style: const TextStyle(
              fontFamily: 'Cairo',
              color: Color(0xFF8B5CF6),
              fontSize: 11,
            ),
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            _formatDate(client['created_at']),
            style: TextStyle(
              fontFamily: 'Cairo',
              color: mutedColor,
              fontSize: 11,
            ),
          ),
          Text(
            _formatCurrency(totalSum),
            style: TextStyle(
              fontFamily: 'Cairo',
              color: contentColor,
              fontSize: 12,
            ),
          ),
          Text(
            _formatCurrency(paidSum),
            style: const TextStyle(
              fontFamily: 'Cairo',
              color: Color(0xFF10B981),
              fontSize: 12,
            ),
          ),
          Text(
            _formatCurrency(remainingDebt),
            style: TextStyle(
              fontFamily: 'Cairo',
              color: remainingDebt > 0
                  ? const Color(0xFFEF4444)
                  : const Color(0xFF10B981),
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
          Text(
            '${clientOrders.length}',
            style: TextStyle(
              fontFamily: 'Cairo',
              color: contentColor,
              fontSize: 12,
            ),
          ),
          Text(
            addedBy,
            style: TextStyle(
              fontFamily: 'Cairo',
              color: mutedColor,
              fontSize: 11,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      );
    }).toList();

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: ResizableColumnsTable(
        persistenceKey: 'dashboard_secondary',
        columns: columns,
        rows: rows,
        headerColor: const Color(0xFF0EA5E9).withOpacity(0.08),
        borderColor: mutedColor.withOpacity(0.12),
        rowColor: Colors.transparent,
        headerMinHeight: 36,
        rowMinHeight: 44,
      ),
    );
  }

  List<Map<String, dynamic>> _filteredDesktopTreasuryRows() {
    final query = _desktopTreasurySearchQuery.trim().toLowerCase();
    if (query.isEmpty) return _desktopTreasury;
    return _desktopTreasury.where((row) {
      final searchable = [
        row['id'],
        row['description'],
        row['amount'],
        row['transaction_type'],
        row['created_at'],
        row['recorded_by'],
        row['caisse_name'],
        row['payment_method'],
        row['entity_type'],
      ].map((value) => (value ?? '').toString().toLowerCase()).join(' ');
      return searchable.contains(query);
    }).toList();
  }

  double _desktopTreasuryTotal(
    List<Map<String, dynamic>> rows, {
    required bool expenses,
  }) {
    return rows
        .where((row) => _isTreasuryExpense(row) == expenses)
        .fold<double>(
          0,
          (total, row) => total + ((row['amount'] as num?)?.toDouble() ?? 0),
        );
  }

  Widget _buildDetailedTreasuryTable(
    Color contentColor,
    Color mutedColor,
    AppLanguage lang,
  ) {
    final rows = _filteredDesktopTreasuryRows();
    return Column(
      children: [
        TextField(
          controller: _desktopTreasurySearchController,
          onChanged: (value) {
            setState(() => _desktopTreasurySearchQuery = value);
          },
          style: TextStyle(
            fontFamily: 'Cairo',
            fontSize: 12,
            color: contentColor,
          ),
          decoration: InputDecoration(
            isDense: true,
            prefixIcon: const Icon(Icons.search_rounded, size: 19),
            hintText: _desktopText(
              lang,
              'بحث: البيان، المبلغ، التاريخ أو المُدخل',
              'Rechercher : libellé, montant, date ou saisi par',
              'Search description, amount, date, or recorded by',
            ),
            hintStyle: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 11,
              color: mutedColor,
            ),
            filled: true,
            fillColor: mutedColor.withOpacity(0.06),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: mutedColor.withOpacity(0.16)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: mutedColor.withOpacity(0.16)),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 11,
            ),
          ),
        ),
        const SizedBox(height: 10),
        _desktopTreasuryTableHeader(mutedColor, lang),
        const SizedBox(height: 6),
        Expanded(
          child: rows.isEmpty
              ? Center(
                  child: Text(
                    _desktopText(
                      lang,
                      _desktopTreasurySearchQuery.isEmpty
                          ? 'لا توجد عمليات صندوق مسجلة بعد'
                          : 'لا توجد نتائج مطابقة للبحث',
                      _desktopTreasurySearchQuery.isEmpty
                          ? 'Aucune opération de trésorerie'
                          : 'Aucun résultat trouvé',
                      _desktopTreasurySearchQuery.isEmpty
                          ? 'No treasury transactions yet'
                          : 'No matching results',
                    ),
                    style: TextStyle(fontFamily: 'Cairo', color: mutedColor),
                  ),
                )
              : ListView.separated(
                  itemCount: math.min(10, rows.length),
                  separatorBuilder: (_, __) =>
                      Divider(height: 1, color: mutedColor.withOpacity(0.12)),
                  itemBuilder: (context, index) => _desktopTreasuryRow(
                    rows[index],
                    contentColor,
                    mutedColor,
                    lang,
                  ),
                ),
        ),
        const SizedBox(height: 8),
        _desktopTreasuryTotalsFooter(rows, contentColor, mutedColor, lang),
      ],
    );
  }

  Widget _desktopTreasuryTableHeader(Color mutedColor, AppLanguage lang) {
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF0EA5A4).withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          _desktopTableCell('#', 1, mutedColor, true),
          _desktopTableCell(
            _desktopText(lang, 'البيان', 'Libellé', 'Description'),
            4,
            mutedColor,
            true,
          ),
          _desktopTableCell(
            _desktopText(lang, 'الدفع', 'Encaissement', 'Income'),
            3,
            mutedColor,
            true,
          ),
          _desktopTableCell(
            _desktopText(lang, 'السحب', 'Décaissement', 'Withdrawal'),
            3,
            mutedColor,
            true,
          ),
          _desktopTableCell(
            _desktopText(lang, 'تاريخ الإنشاء', 'Date création', 'Created at'),
            2,
            mutedColor,
            true,
          ),
          _desktopTableCell(
            _desktopText(lang, 'أدخلها', 'Saisi par', 'Recorded by'),
            3,
            mutedColor,
            true,
          ),
          _desktopTableCell(
            _desktopText(lang, 'الصندوق', 'Caisse', 'Cashbox'),
            2,
            mutedColor,
            true,
          ),
        ],
      ),
    );
  }

  Widget _desktopTreasuryRow(
    Map<String, dynamic> row,
    Color contentColor,
    Color mutedColor,
    AppLanguage lang,
  ) {
    final id = (row['id'] as num?)?.toInt() ?? 0;
    final amount = (row['amount'] as num?)?.toDouble() ?? 0;
    final isExpense = _isTreasuryExpense(row);
    final description = (row['description'] ?? '').toString().trim();
    final type = (row['transaction_type'] ?? '').toString().trim();
    final recordedBy = (row['recorded_by'] ?? '').toString().trim();
    final cashbox = (row['caisse_name'] ?? '').toString().trim();

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _openTreasury,
        child: Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              _desktopTableCell(
                id < 100000 ? '#$id' : '—',
                1,
                contentColor,
                false,
                colorOverride: const Color(0xFF0EA5A4),
              ),
              _desktopTableCell(
                description.isEmpty
                    ? (type.isEmpty
                          ? _desktopText(
                              lang,
                              'عملية صندوق',
                              'Opération de caisse',
                              'Treasury entry',
                            )
                          : type)
                    : description,
                4,
                contentColor,
                false,
              ),
              _desktopTableCell(
                isExpense ? '—' : _formatCurrency(amount),
                3,
                isExpense ? mutedColor : const Color(0xFF10B981),
                false,
                fontWeight: isExpense ? null : FontWeight.bold,
              ),
              _desktopTableCell(
                isExpense ? _formatCurrency(amount) : '—',
                3,
                isExpense ? const Color(0xFFEF4444) : mutedColor,
                false,
                fontWeight: isExpense ? FontWeight.bold : null,
              ),
              _desktopTableCell(
                _formatDate(row['created_at']),
                2,
                mutedColor,
                false,
              ),
              _desktopTableCell(
                recordedBy.isEmpty || recordedBy == 'system'
                    ? _desktopText(lang, 'النظام', 'Système', 'System')
                    : recordedBy,
                3,
                mutedColor,
                false,
              ),
              _desktopTableCell(
                cashbox.isEmpty
                    ? _desktopText(lang, 'الرئيسي', 'Principale', 'Main')
                    : cashbox,
                2,
                mutedColor,
                false,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _desktopTreasuryTotalsFooter(
    List<Map<String, dynamic>> rows,
    Color contentColor,
    Color mutedColor,
    AppLanguage lang,
  ) {
    final income = _desktopTreasuryTotal(rows, expenses: false);
    final expense = _desktopTreasuryTotal(rows, expenses: true);
    final balance = income - expense;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: Tooltip(
        message: _desktopText(
          lang,
          'اضغط لعرض أو إخفاء تفاصيل الإجماليات',
          'Cliquez pour afficher ou masquer les totaux',
          'Click to show or hide total details',
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () =>
                setState(() => _showTreasuryTotals = !_showTreasuryTotals),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                color: const Color(0xFF0EA5A4).withOpacity(0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: const Color(0xFF0EA5A4).withOpacity(0.18),
                ),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.calculate_rounded,
                        size: 17,
                        color: const Color(0xFF0EA5A4),
                      ),
                      const SizedBox(width: 7),
                      Text(
                        _desktopText(lang, 'الإجماليات', 'Totaux', 'Totals'),
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 11,
                          color: contentColor,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '${rows.length} ${_desktopText(lang, 'عملية', 'opérations', 'entries')}',
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 10,
                          color: mutedColor,
                        ),
                      ),
                      const SizedBox(width: 5),
                      Icon(
                        _showTreasuryTotals
                            ? Icons.keyboard_arrow_up_rounded
                            : Icons.keyboard_arrow_down_rounded,
                        color: mutedColor,
                      ),
                    ],
                  ),
                  AnimatedSize(
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOut,
                    alignment: Alignment.topCenter,
                    child: _showTreasuryTotals
                        ? Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Align(
                              alignment: AlignmentDirectional.centerEnd,
                              child: Wrap(
                                spacing: 16,
                                runSpacing: 4,
                                children: [
                                  _desktopTreasuryTotalLabel(
                                    _desktopText(
                                      lang,
                                      'الدفع',
                                      'Encaissements',
                                      'Income',
                                    ),
                                    _formatCurrency(income),
                                    const Color(0xFF10B981),
                                  ),
                                  _desktopTreasuryTotalLabel(
                                    _desktopText(
                                      lang,
                                      'السحب',
                                      'Décaissements',
                                      'Withdrawals',
                                    ),
                                    _formatCurrency(expense),
                                    const Color(0xFFEF4444),
                                  ),
                                  _desktopTreasuryTotalLabel(
                                    _desktopText(
                                      lang,
                                      'الرصيد',
                                      'Solde',
                                      'Balance',
                                    ),
                                    _formatCurrency(balance),
                                    const Color(0xFF0EA5A4),
                                  ),
                                ],
                              ),
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _desktopTreasuryTotalLabel(String label, String value, Color color) {
    return RichText(
      text: TextSpan(
        style: const TextStyle(fontFamily: 'Cairo', fontSize: 10),
        children: [
          TextSpan(
            text: '$label: ',
            style: const TextStyle(color: Color(0xFF64748B)),
          ),
          TextSpan(
            text: value,
            style: TextStyle(color: color, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }

  Widget _desktopTableCell(
    String text,
    int flex,
    Color color,
    bool isHeader, {
    Color? colorOverride,
    FontWeight? fontWeight,
  }) {
    return Expanded(
      flex: flex,
      child: Text(
        text,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: colorOverride ?? color,
          fontFamily: 'Cairo',
          fontSize: isHeader ? 10 : 11,
          fontWeight:
              fontWeight ?? (isHeader ? FontWeight.w700 : FontWeight.w600),
        ),
      ),
    );
  }

  Widget _desktopTableHeaderLabel(
    String text,
    Color color, {
    Color? colorOverride,
    FontWeight? fontWeight,
  }) {
    return Text(
      text,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: colorOverride ?? color,
        fontFamily: 'Cairo',
        fontSize: 10,
        fontWeight: fontWeight ?? FontWeight.w700,
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
      title: _desktopText(
        lang,
        'حالة سير العمل',
        'État du travail',
        'Work progress',
      ),
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
                      style: TextStyle(
                        color: contentColor,
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                      ),
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
                    _desktopText(
                      lang,
                      '$completed مكتملة',
                      '$completed terminées',
                      '$completed completed',
                    ),
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      color: contentColor,
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    _desktopText(
                      lang,
                      'من أصل $total طلبية',
                      'sur $total commandes',
                      'out of $total orders',
                    ),
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      color: mutedColor,
                      fontSize: 11,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _desktopText(
                      lang,
                      '$_activeWorkersCount عامل نشط',
                      '$_activeWorkersCount employés actifs',
                      '$_activeWorkersCount active workers',
                    ),
                    style: const TextStyle(
                      fontFamily: 'Cairo',
                      color: Color(0xFF0EA5A4),
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  int _orderLifecycleWeight(String key) {
    return orderStatusWeight(key);
  }

  Widget _buildDesktopActivityPanel(
    BuildContext context,
    Color cardColor,
    Color contentColor,
    Color mutedColor,
  ) {
    final lang = Provider.of<AppSettingsProvider>(context).language;
    final total = _ordersByStatus.values.fold<int>(
      0,
      (sum, value) => sum + value,
    );
    final statusColors = <String, Color>{
      'Nouveau': const Color(0xFF64748B),
      'New': const Color(0xFF64748B),
      'Confirmed': const Color(0xFF10B981),
      'In Progress': const Color(0xFF2563EB),
      'Pending': const Color(0xFFF59E0B),
      'Partial Manufacturing': const Color(0xFF0EA5E9),
      'Full Manufacturing': const Color(0xFF0F766E),
      'Partial Distribution': const Color(0xFFF97316),
      'Full Distribution': const Color(0xFF22C55E),
      'Installation': const Color(0xFF8B5CF6),
      'Reserve': const Color(0xFFEF4444),
      'Done': const Color(0xFF059669),
    };
    final sortedStatusMap = <String, int>{};
    final legendEntries = _ordersByStatus.entries.toList()
      ..sort(
        (a, b) => _orderLifecycleWeight(
          a.key,
        ).compareTo(_orderLifecycleWeight(b.key)),
      );
    for (final e in legendEntries) {
      sortedStatusMap[e.key] = e.value;
    }
    return _desktopPanel(
      context: context,
      title: _desktopText(
        lang,
        'حالات الطلبيات',
        'État des commandes',
        'Order statuses',
      ),
      subtitle: _desktopText(
        lang,
        'توزيع الطلبيات حسب الحالة',
        'Répartition par état',
        'Orders grouped by status',
      ),
      icon: Icons.donut_small_rounded,
      color: const Color(0xFF2563EB),
      backgroundColor: cardColor,
      textColor: contentColor,
      mutedColor: mutedColor,
      child: SizedBox(
        height: 138,
        child: total == 0
            ? Center(
                child: Text(
                  _desktopText(
                    lang,
                    'لا توجد طلبيات بعد',
                    'Aucune commande pour le moment',
                    'No orders yet',
                  ),
                  style: TextStyle(color: mutedColor, fontSize: 11),
                ),
              )
            : Row(
                children: [
                  SizedBox(
                    width: 116,
                    height: 116,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        CustomPaint(
                          size: const Size.square(116),
                          painter: _DonutPainter(
                            data: sortedStatusMap,
                            colors: statusColors,
                            progress: 1,
                            bgColor: mutedColor.withValues(alpha: 0.14),
                          ),
                        ),
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              total.toString(),
                              style: TextStyle(
                                color: contentColor,
                                fontFamily: 'Arial',
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            Text(
                              _desktopText(
                                lang,
                                'طلبية',
                                'commandes',
                                'orders',
                              ),
                              style: TextStyle(color: mutedColor, fontSize: 9),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final entry in legendEntries.take(4))
                          _desktopStatusLegend(
                            color:
                                statusColors[entry.key] ??
                                const Color(0xFF94A3B8),
                            label: _desktopStatusText(entry.key, lang),
                            count: entry.value,
                            mutedColor: mutedColor,
                          ),
                        if (legendEntries.length > 4)
                          Text(
                            '+${legendEntries.length - 4}',
                            style: TextStyle(
                              color: mutedColor,
                              fontFamily: 'Arial',
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _desktopStatusLegend({
    required Color color,
    required String label,
    required int count,
    required Color mutedColor,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 84),
          child: Text(
            '$label ($count)',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: mutedColor,
              fontFamily: 'Arial',
              fontSize: 9,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
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
      title: _desktopText(
        lang,
        'تنبيهات المخزون',
        'Alertes de stock',
        'Inventory alerts',
      ),
      subtitle: _lowStockCount == 0
          ? _desktopText(
              lang,
              'المخزون ضمن الحدود الآمنة',
              'Le stock est dans les limites sûres',
              'Stock levels are within safe limits',
            )
          : _desktopText(
              lang,
              '$_lowStockCount عناصر تحتاج إلى متابعة',
              '$_lowStockCount éléments à suivre',
              '$_lowStockCount items need attention',
            ),
      icon: Icons.inventory_2_rounded,
      color: _lowStockCount == 0
          ? const Color(0xFF10B981)
          : const Color(0xFFF97316),
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
              label: Text(
                _desktopText(
                  lang,
                  'فتح المخزون',
                  'Ouvrir le stock',
                  'Open inventory',
                ),
                style: const TextStyle(fontFamily: 'Cairo'),
              ),
            )
          : null,
      child: _lowStockItems.isEmpty
          ? SizedBox(
              height: 68,
              child: Row(
                children: [
                  const Icon(
                    Icons.verified_rounded,
                    color: Color(0xFF10B981),
                    size: 28,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _desktopText(
                        lang,
                        'لا يوجد أي نقص في المواد ذات حد التنبيه.',
                        'Aucun manque dans les articles suivis.',
                        'No low-stock items need attention.',
                      ),
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        color: mutedColor,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            )
          : LayoutBuilder(
              builder: (context, constraints) {
                final items = _lowStockItems.take(4).toList();
                final columns = constraints.maxWidth >= 900
                    ? 4
                    : constraints.maxWidth >= 540
                    ? 2
                    : 1;
                const gap = 10.0;
                final itemWidth =
                    (constraints.maxWidth - ((columns - 1) * gap)) / columns;
                return Wrap(
                  spacing: gap,
                  runSpacing: gap,
                  children: [
                    for (final item in items)
                      SizedBox(
                        width: itemWidth,
                        child: _desktopStockItem(
                          item,
                          contentColor,
                          mutedColor,
                          lang,
                        ),
                      ),
                  ],
                );
              },
            ),
    );
  }

  Widget _desktopStockItem(
    Map<String, dynamic> item,
    Color contentColor,
    Color mutedColor,
    AppLanguage lang,
  ) {
    final quantity = (item['quantity'] as num?)?.toDouble() ?? 0.0;
    final minQuantity = (item['min_qty'] as num?)?.toDouble() ?? 0.0;
    final name =
        (item['item_name'] ??
                item['name'] ??
                _desktopText(lang, 'عنصر', 'Article', 'Item'))
            .toString();
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
              const Icon(
                Icons.warning_amber_rounded,
                color: Color(0xFFF97316),
                size: 17,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  name,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontWeight: FontWeight.w800,
                    color: contentColor,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            _desktopText(
              lang,
              'الرصيد: ${_formatQuantity(quantity)} / الحد: ${_formatQuantity(minQuantity)}',
              'Solde : ${_formatQuantity(quantity)} / min. : ${_formatQuantity(minQuantity)}',
              'Stock: ${_formatQuantity(quantity)} / min: ${_formatQuantity(minQuantity)}',
            ),
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: 'Cairo',
              color: mutedColor,
              fontSize: 10,
            ),
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
        border: Border.all(
          color: isDark
              ? Colors.white.withOpacity(0.08)
              : const Color(0xFFE2E8F0),
        ),
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
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 19),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        color: textColor,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          color: mutedColor,
                          fontSize: 10,
                        ),
                      ),
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

  void _openOrders({bool openAddOrderOnStart = false}) {
    final lang = Provider.of<AppSettingsProvider>(
      context,
      listen: false,
    ).language;
    _markOrdersAsRead();
    openAdaptiveScreen(
      context,
      title: _desktopText(lang, 'الطلبيات', 'Commandes', 'Orders'),
      icon: Icons.receipt_long_rounded,
      screen: Commande(openAddOrderOnStart: openAddOrderOnStart),
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

  String _formatQuantity(double value) => value == value.roundToDouble()
      ? value.toInt().toString()
      : value.toStringAsFixed(2);

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
      'partial manufacturing': [
        'تصنيع جزئي',
        'Fabrication partielle',
        'Partial manufacturing',
      ],
      'full manufacturing': [
        'تم التصنيع',
        'Fabrication terminée',
        'Manufactured',
      ],
      'partial distribution': [
        'توزيع جزئي',
        'Distribution partielle',
        'Partial distribution',
      ],
      'full distribution': [
        'تم التوزيع',
        'Distribution terminée',
        'Distributed',
      ],
      'installation': ['تركيب', 'Installation', 'Installation'],
      'reserve': ['تحفّظ', 'Réserve', 'Reserve'],
      'done': ['مكتملة', 'Terminée', 'Completed'],
      'completed': ['مكتملة', 'Terminée', 'Completed'],
      'finished': ['مكتملة', 'Terminée', 'Completed'],
    };
    final translated = values[normalized];
    if (translated == null) return status;
    return lang == AppLanguage.arabic
        ? translated[0]
        : lang == AppLanguage.french
        ? translated[1]
        : translated[2];
  }

  Widget _buildSliverHeader(BuildContext context) {
    final isDesktop = _isWindowsDesktop;
    final lang = Provider.of<AppSettingsProvider>(
      context,
      listen: false,
    ).language;
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
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2,
                  ),
                ),
              )
            : IconButton(
                icon: const Icon(Icons.sync_rounded, color: Colors.white),
                tooltip: _desktopText(
                  lang,
                  'تحديث ومزامنة البيانات والمهام من السحابة',
                  'Actualiser et synchroniser les données et les tâches depuis le cloud',
                  'Refresh and sync data and tasks from the cloud',
                ),
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
                color: (_lowStockCount + _newOrdersCount) > 0
                    ? Colors.amberAccent
                    : Colors.white,
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
              colors: Theme.of(context).brightness == Brightness.dark
                  ? [Color(0xFF111827), Color(0xFF070E1D)]
                  : [Color(0xFF2563EB), Color(0xFF0EA5E9)],
              begin: Alignment.topLeft,
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
                          colors:
                              Theme.of(context).brightness == Brightness.dark
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
            : (lang == AppLanguage.french
                  ? 'Alertes de stock'
                  : 'Stock alerts'),
        value: _lowStockCount.toString(),
        color: _lowStockCount > 0 ? Colors.deepOrange : _green,
        trend: _lowStockCount > 0
            ? (lang == AppLanguage.arabic ? 'يحتاج متابعة' : 'Needs attention')
            : (lang == AppLanguage.arabic
                  ? 'المخزون مستقر'
                  : 'Stock is stable'),
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
              for (final card in cards) SizedBox(width: cardWidth, child: card),
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

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 420;
        return Container(
          width: double.infinity,
          constraints: const BoxConstraints(minHeight: 90),
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
                padding: EdgeInsets.symmetric(
                  horizontal: compact ? 12 : 20,
                  vertical: 12,
                ),
                child: Row(
                  children: [
                    Container(
                      padding: EdgeInsets.all(compact ? 8 : 10),
                      decoration: BoxDecoration(
                        color: Theme.of(context).cardColor.withOpacity(0.2),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.mic_none_outlined,
                        color: Colors.white,
                        size: compact ? 26 : 32,
                      ),
                    ),
                    SizedBox(width: compact ? 10 : 16),
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
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            Localization.translate(
                              'إدخال القياسات السريع بالكتابة أو بالصوت',
                              lang,
                            ),
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.85),
                              fontSize: 13,
                              fontFamily: 'Cairo',
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.arrow_forward_ios_rounded,
                      color: Colors.white,
                      size: compact ? 18 : 20,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  // ── شبكة التنقل ──────────────────────────────────────────────────────────
  Widget _buildNavGrid(BuildContext context) {
    final settings = Provider.of<AppSettingsProvider>(context);
    final lang = settings.language;
    final allowWorkshop = settings.workingSection == WorkingSection.all ||
        settings.workingSection == WorkingSection.workshop;
    final allowStore = settings.workingSection == WorkingSection.all ||
        settings.workingSection == WorkingSection.materialsStore;

    final items = [
      if (allowWorkshop && settings.hasWorkshop && settings.canViewOrders())
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
      if (allowStore && settings.hasMaterialsStore && settings.canMaterialSales())
        _NavItem(
          icon: Icons.storefront_rounded,
          label: Localization.translate('بيع المواد', lang),
          color: const Color(0xFFEA580C), // Orange
          onTap: () => openAdaptiveScreen(
            context,
            title: Localization.translate('بيع المواد', lang),
            icon: Icons.storefront_rounded,
            screen: MaterialSalesScreen(db: db),
          ),
        ),
      if (allowWorkshop && settings.hasWorkshop && settings.canViewProjects())
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
      if (allowWorkshop && settings.hasWorkshop && settings.canViewMyTasks())
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
      if (allowWorkshop && settings.hasWorkshop && settings.canViewMyTasks())
        _NavItem(
          icon: Icons.archive_rounded,
          label: lang == AppLanguage.arabic
              ? 'أرشيف التوزيع والمهام'
              : (lang == AppLanguage.french
                    ? 'Archives & Distribution'
                    : 'Tasks & Distribution Archive'),
          color: const Color(0xFFEA580C), // Vivid Burnt Orange
          onTap: () => openAdaptiveScreen(
            context,
            title: lang == AppLanguage.arabic
                ? 'أرشيف التوزيع والمهام'
                : (lang == AppLanguage.french
                      ? 'Archives & Distribution'
                      : 'Tasks & Distribution Archive'),
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
      if (allowWorkshop && settings.hasWorkshop && settings.canAccessExternalOperations())
        _NavItem(
          icon: Icons.engineering_rounded,
          label: lang == AppLanguage.arabic
              ? 'الأعمال والمهمات الخارجية'
              : (lang == AppLanguage.french
                    ? 'Opérations Externe'
                    : 'External Operations'),
          color: const Color(0xFF0891B2), // Deep Ocean Cyan
          onTap: () => openAdaptiveScreen(
            context,
            title: lang == AppLanguage.arabic
                ? 'الأعمال والمهمات الخارجية'
                : (lang == AppLanguage.french
                      ? 'Opérations Externe'
                      : 'External Operations'),
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
          itemBuilder: (_, i) =>
              _NavCard(item: items[i], index: i, dragNotifier: _dragNotifier),
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

  Widget? _buildDesktopSectionSelector(
    BuildContext context,
    AppLanguage lang,
    Color cardColor,
    Color contentColor,
    Color mutedColor,
  ) {
    final settings = Provider.of<AppSettingsProvider>(context);
    if (!settings.isDualActivity) return null;

    final current = settings.workingSection;

    Widget buildOption({
      required WorkingSection section,
      required String label,
      required IconData icon,
    }) {
      final isSelected = current == section;
      return InkWell(
        onTap: () => settings.setWorkingSection(section),
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFF2563EB) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: const Color(0xFF2563EB).withValues(alpha: 0.25),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    )
                  ]
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 15,
                color: isSelected ? Colors.white : mutedColor,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                  color: isSelected ? Colors.white : contentColor,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: mutedColor.withValues(alpha: 0.15)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          buildOption(
            section: WorkingSection.all,
            label: _desktopText(lang, 'الكل', 'Tout', 'All'),
            icon: Icons.dashboard_customize_rounded,
          ),
          const SizedBox(width: 4),
          buildOption(
            section: WorkingSection.workshop,
            label: _desktopText(lang, 'الورشة', 'Atelier', 'Workshop'),
            icon: Icons.precision_manufacturing_rounded,
          ),
          const SizedBox(width: 4),
          buildOption(
            section: WorkingSection.materialsStore,
            label: _desktopText(lang, 'المحل', 'Magasin', 'Store'),
            icon: Icons.storefront_rounded,
          ),
        ],
      ),
    );
  }

  Widget _buildMobileSectionSelector(BuildContext context) {
    final settings = Provider.of<AppSettingsProvider>(context);
    if (!settings.isDualActivity) return const SizedBox.shrink();

    final lang = settings.language;
    final current = settings.workingSection;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    Widget buildTab({
      required WorkingSection section,
      required String title,
      required IconData icon,
      required Color activeColor,
    }) {
      final isSelected = current == section;
      return Expanded(
        child: InkWell(
          onTap: () => settings.setWorkingSection(section),
          borderRadius: BorderRadius.circular(12),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 4),
            decoration: BoxDecoration(
              color: isSelected
                  ? (isDark ? activeColor.withValues(alpha: 0.28) : activeColor)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
              border: isSelected && isDark
                  ? Border.all(color: activeColor.withValues(alpha: 0.6), width: 1.2)
                  : null,
              boxShadow: isSelected && !isDark
                  ? [
                      BoxShadow(
                        color: activeColor.withValues(alpha: 0.30),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      )
                    ]
                  : null,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: 16,
                  color: isSelected
                      ? (isDark ? activeColor : Colors.white)
                      : (isDark ? Colors.white60 : Colors.blueGrey.shade600),
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 12,
                      fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                      color: isSelected
                          ? (isDark ? Colors.white : Colors.white)
                          : (isDark ? Colors.white70 : Colors.blueGrey.shade700),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? Colors.white12 : Colors.blueGrey.withValues(alpha: 0.12),
        ),
      ),
      child: Row(
        children: [
          buildTab(
            section: WorkingSection.all,
            title: _desktopText(lang, 'الكل', 'Tout', 'All'),
            icon: Icons.dashboard_customize_rounded,
            activeColor: const Color(0xFF2563EB),
          ),
          const SizedBox(width: 4),
          buildTab(
            section: WorkingSection.workshop,
            title: _desktopText(lang, 'الورشة', 'Atelier', 'Workshop'),
            icon: Icons.precision_manufacturing_rounded,
            activeColor: const Color(0xFF1D4ED8),
          ),
          const SizedBox(width: 4),
          buildTab(
            section: WorkingSection.materialsStore,
            title: _desktopText(lang, 'المحل', 'Magasin', 'Store'),
            icon: Icons.storefront_rounded,
            activeColor: const Color(0xFF0D9488),
          ),
        ],
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
    this.secondaryLabel,
    this.secondaryValue,
    this.secondaryIcon,
    this.secondaryColor,
    this.onSecondaryTap,
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
  final String? secondaryLabel;
  final String? secondaryValue;
  final IconData? secondaryIcon;
  final Color? secondaryColor;
  final VoidCallback? onSecondaryTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          height: secondaryValue == null ? 108 : 132,
          padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 15),
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.08)
                  : const Color(0xFFE8EDF6),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.16 : 0.045),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      title,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 11,
                        color: mutedColor,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    SizedBox(
                      height: 31,
                      width: double.infinity,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: AlignmentDirectional.centerStart,
                        child: Text(
                          value,
                          maxLines: 1,
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 23,
                            color: textColor,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                    Text(
                      caption,
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 10,
                        color: color,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (secondaryValue != null) ...[
                      const SizedBox(height: 6),
                      Divider(
                        height: 1,
                        color: mutedColor.withValues(alpha: 0.15),
                      ),
                      const SizedBox(height: 5),
                      InkWell(
                        onTap: onSecondaryTap,
                        borderRadius: BorderRadius.circular(6),
                        child: Row(
                          children: [
                            Icon(
                              secondaryIcon ?? Icons.warning_amber_rounded,
                              color: secondaryColor ?? color,
                              size: 14,
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                secondaryLabel ?? '',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontFamily: 'Arial',
                                  fontSize: 9,
                                  color: mutedColor,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            Text(
                              secondaryValue!,
                              style: TextStyle(
                                fontFamily: 'Arial',
                                fontSize: 12,
                                color: secondaryColor ?? color,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 23, color: color),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DesktopSparkline extends StatelessWidget {
  const _DesktopSparkline({
    required this.values,
    required this.color,
    this.fill = false,
  });

  final List<double> values;
  final Color color;
  final bool fill;

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: CustomPaint(
        painter: _DesktopSparklinePainter(
          values: values,
          color: color,
          fill: fill,
        ),
      ),
    );
  }
}

class _DesktopSparklinePainter extends CustomPainter {
  const _DesktopSparklinePainter({
    required this.values,
    required this.color,
    required this.fill,
  });

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
      final y =
          size.height -
          ((source[index] - minValue) / range * (size.height - 5)) -
          2;
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
      oldDelegate.values != values ||
      oldDelegate.color != color ||
      oldDelegate.fill != fill;
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
      final newWord = Localization.translate('طلبية جديدة', lang);
      displayTrend = displayTrend.replaceAll('(new)', newWord);
    }
    if (displayTrend.contains('(new_client)')) {
      final newWord = Localization.translate('زبون جديد', lang);
      displayTrend = displayTrend.replaceAll('(new_client)', newWord);
    }
    if (displayTrend.contains('(جديد)')) {
      final newWord = Localization.translate('جديد', lang);
      displayTrend = displayTrend.replaceAll('(جديد)', '($newWord)');
    }
    if (displayTrend.contains('(جديدة)')) {
      final newWord = Localization.translate('جديدة', lang);
      displayTrend = displayTrend.replaceAll('(جديدة)', '($newWord)');
    }
    final depthColor =
        Color.lerp(widget.color, Colors.black, 0.20) ?? widget.color;

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
              widget.dragNotifier.value = {'id': _myId, 'offset': _dragOffset};
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
                        border: Border.all(
                          color: Theme.of(context).dividerColor,
                          width: 1.2,
                        ),
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
                                child: Icon(
                                  widget.icon,
                                  color: widget.color,
                                  size: 16,
                                ),
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
              widget.dragNotifier.value = {'id': _myId, 'offset': _dragOffset};
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
                            color: color.withValues(
                              alpha: isDark ? 0.28 : 0.16,
                            ),
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
                            ? Color.alphaBlend(
                                color.withValues(alpha: 0.12),
                                const Color(0xFF1E293B),
                              )
                            : Color.alphaBlend(
                                color.withValues(alpha: 0.05),
                                Colors.white,
                              ),
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
                                  color: color.withValues(
                                    alpha: isDark ? 0.55 : 0.38,
                                  ),
                                  blurRadius: 7,
                                  spreadRadius: -3,
                                  offset: Offset.zero,
                                ),
                                // ظل سفلي خفيف
                                BoxShadow(
                                  color: color.withValues(
                                    alpha: isDark ? 0.18 : 0.10,
                                  ),
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
                              color: color.withValues(
                                alpha: isDark ? 0.25 : 0.14,
                              ),
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
                              color: isDark
                                  ? Colors.white
                                  : const Color(0xFF1E293B),
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
    'Nouveau': Color(0xFF546E7A), // رمادي مزرق
    'New': Color(0xFF546E7A), // رمادي مزرق
    'Confirmed': Color(0xFF2E7D32), // أخضر داكن
    'In Progress': Color(0xFF1565C0), // أزرق داكن
    'Pending': Color(0xFFE65100), // برتقالي محروق
    'Partial Manufacturing': Color(0xFF0288D1), // أزرق فاتح
    'Full Manufacturing': Color(0xFF00796B), // تيل داكن
    'Partial Distribution': Color(0xFFF57C00), // برتقالي داكن
    'Full Distribution': Color(0xFF388E3C), // أخضر
    'Installation': Color(0xFF6A1B9A), // بنفسجي
    'Reserve': Color(0xFFD84315), // أحمر برتقالي - التحفظ
    'Done': Color(0xFF00695C), // تيل/أخضر مائل
    'Unknown': Color(0xFF78909C), // رمادي
  };

  static const _statusAr = {
    'Nouveau': 'جديدة',
    'New': 'جديدة',
    'Confirmed': 'مؤكدة',
    'In Progress': 'تأكيد القياسات',
    'Pending': 'قيد الانتظار',
    'Partial Manufacturing': 'تصنيع جزئي',
    'Full Manufacturing': 'تصنيع كامل',
    'Partial Distribution': 'توزيع جزئي',
    'Full Distribution': 'توزيع كامل',
    'Installation': 'تركيب',
    'Reserve': 'تحت التحفظ',
    'Done': 'منتهية',
    'Unknown': 'أخرى',
  };

  Map<String, int> get _sortedByStatus {
    final entries = widget.byStatus.entries.toList()
      ..sort((a, b) {
        final wA = _statusOrderWeight(a.key);
        final wB = _statusOrderWeight(b.key);
        return wA.compareTo(wB);
      });
    final res = <String, int>{};
    for (final e in entries) {
      res[e.key] = e.value;
    }
    return res;
  }

  static int _statusOrderWeight(String key) {
    final s = key.trim().toLowerCase();
    if (s == 'nouveau' ||
        s == 'new' ||
        s == 'جديدة' ||
        s == 'جديد' ||
        s == 'draft')
      return 10;
    if (s == 'confirmed' || s.contains('مؤكد') || s.contains('confirme'))
      return 20;
    if (s == 'in progress' ||
        s.contains('قياسات') ||
        s.contains('جارية') ||
        s.contains('cours'))
      return 30;
    if (s == 'pending' ||
        s == 'en attente' ||
        s == 'en_attente' ||
        s.contains('انتظار'))
      return 40;
    if (s == 'partial manufacturing' ||
        s.contains('تصنيع جزئي') ||
        s.contains('fabrication partielle'))
      return 50;
    if (s == 'full manufacturing' ||
        s.contains('تصنيع كلي') ||
        s.contains('تصنيع كامل') ||
        s.contains('fabrication totale') ||
        s.contains('fabrication complète'))
      return 60;
    if (s == 'partial distribution' ||
        s.contains('توزيع جزئي') ||
        s.contains('livraison partielle'))
      return 70;
    if (s == 'full distribution' ||
        s.contains('توزيع كلي') ||
        s.contains('توزيع كامل') ||
        s.contains('livraison totale') ||
        s.contains('livraison complète'))
      return 80;
    if (s == 'installation' || s.contains('تركيب')) return 90;
    if (s == 'reserve' || s.contains('تحفظ') || s.contains('réserve'))
      return 95;
    if (s == 'done' ||
        s == 'livré' ||
        s == 'livre' ||
        s.contains('منتهي') ||
        s.contains('مكتمل'))
      return 100;
    if (s == 'cancelled' || s.contains('ملغاة') || s.contains('annulé'))
      return 999;
    return 85;
  }

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
    if (!mapEquals(old.byStatus, widget.byStatus) ||
        !mapEquals(old.byMonth, widget.byMonth)) {
      _anim.forward(from: 0);
    }
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
                colors: Theme.of(context).brightness == Brightness.dark
                    ? [Color(0xFF111827), Color(0xFF070E1D)]
                    : [Color(0xFF2563EB), Color(0xFF0EA5E9)],
                begin: Alignment.centerLeft,
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
                    data: _sortedByStatus,
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
                      style: const TextStyle(fontSize: 11, fontFamily: 'Cairo'),
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
              children: _sortedByStatus.entries.map((e) {
                final color = _statusColors[e.key] ?? const Color(0xFF94A3B8);
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
                          lang == AppLanguage.arabic
                              ? (_statusAr[e.key] ??
                                    Localization.translate(e.key, lang))
                              : Localization.translate(e.key, lang),
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
    final lang = Provider.of<AppSettingsProvider>(
      context,
      listen: false,
    ).language;
    final entries = widget.byMonth.entries.toList();
    if (entries.isEmpty) return _emptyState();
    final maxVal = entries.map((e) => e.value).fold(0, (a, b) => a > b ? a : b);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 175,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: entries.map((e) {
                final ratio = maxVal > 0
                    ? (e.value / maxVal) * _progress.value
                    : 0.0;
                final isLast = entries.last == e;
                return Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(right: isLast ? 0 : 6),
                    child: Column(
                      children: [
                        // Keep the value in a separate, fixed-height area.
                        // This is important on desktop where the bar column
                        // can be laid out with tighter vertical constraints.
                        SizedBox(
                          height: 14,
                          child: Center(
                            child: Text(
                              e.value.toString(),
                              maxLines: 1,
                              overflow: TextOverflow.visible,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 10,
                                color: Color(0xFF2563EB),
                                fontWeight: FontWeight.w700,
                                fontFamily: 'Cairo',
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        SizedBox(
                          height: 110,
                          child: Align(
                            alignment: Alignment.bottomCenter,
                            child: AnimatedContainer(
                              duration: Duration.zero,
                              height: 110 * ratio,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors:
                                      Theme.of(context).brightness ==
                                          Brightness.dark
                                      ? [Color(0xFF111827), Color(0xFF070E1D)]
                                      : [Color(0xFF2563EB), Color(0xFF0EA5E9)],
                                  begin: Alignment.bottomCenter,
                                  end: Alignment.topCenter,
                                ),
                                borderRadius: const BorderRadius.only(
                                  topLeft: Radius.circular(6),
                                  topRight: Radius.circular(6),
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(
                                      0xFF2563EB,
                                    ).withValues(alpha: 0.25),
                                    blurRadius: 8,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                            ),
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
                Localization.translate(
                  'آخر 6 أشهر: {count} طلبية',
                  lang,
                ).replaceAll(
                  '{count}',
                  '${entries.fold(0, (s, e) => s + e.value)}',
                ),
                style: const TextStyle(fontSize: 11, fontFamily: 'Cairo'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLineView() {
    final lang = Provider.of<AppSettingsProvider>(
      context,
      listen: false,
    ).language;
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
                Localization.translate(
                  'آخر 6 أشهر: {count} طلبية',
                  lang,
                ).replaceAll(
                  '{count}',
                  '${entries.fold(0, (s, e) => s + e.value)}',
                ),
                style: const TextStyle(fontSize: 11, fontFamily: 'Cairo'),
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
      '',
      'يناير',
      'فبراير',
      'مارس',
      'أبريل',
      'مايو',
      'يونيو',
      'يوليو',
      'أغسطس',
      'سبتمبر',
      'أكتوبر',
      'نوفمبر',
      'ديسمبر',
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
                fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
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
      final double y =
          height - (entries[i].value / maxValDouble * height * progress);
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
        style: const TextStyle(fontSize: 9, fontFamily: 'Cairo'),
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
      '',
      'يناير',
      'فبراير',
      'مارس',
      'أبريل',
      'مايو',
      'يونيو',
      'يوليو',
      'أغسطس',
      'سبتمبر',
      'أكتوبر',
      'نوفمبر',
      'ديسمبر',
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
        _bubbles.add(
          _Bubble(
            xFraction: rand.nextDouble(),
            yFraction: 0.3 + rand.nextDouble() * 0.7,
            radius: 2.0 + rand.nextDouble() * 5.0,
            speed: 0.05 + rand.nextDouble() * 0.05,
            wobbleSpeed: 0.5 + rand.nextDouble() * 1.5,
            wobbleScale: 0.01 + rand.nextDouble() * 0.02,
          ),
        );
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
                          const Color(
                            0xFFF1F5F9,
                          ), // blends to normal background at the bottom
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
                          : const Color(
                              0x3338BDF8,
                            ), // sky-400 with glowing highlight
                      amplitude: 14,
                      frequency: 1.2,
                      phaseShift: 0.0,
                      highlightColor: isDark
                          ? Colors.white.withOpacity(0.08)
                          : Colors.white.withOpacity(0.35),
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
                      highlightColor: isDark
                          ? Colors.white.withOpacity(0.12)
                          : Colors.white.withOpacity(0.45),
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
                      highlightColor: isDark
                          ? Colors.white.withOpacity(0.15)
                          : Colors.white.withOpacity(0.55),
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
      final double angle =
          (x / waveLength) * 2 * math.pi * frequency +
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

      double wobble =
          math.sin(progress * 2 * math.pi * bubble.wobbleSpeed) *
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
