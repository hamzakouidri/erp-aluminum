import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:database_data/services/supabase_workshop_sync_service.dart';

bool get isAdmin {
  final user = FirebaseAuth.instance.currentUser;
  return isApplicationAdminEmail(user?.email);
}

bool isApplicationAdminEmail(String? email) {
  return (email ?? '').trim().toLowerCase() == 'kouidrihamza45@gmail.com';
}

enum AppLanguage { arabic, french, english }

enum CostMethod { linearMeter, squareMeter, percentage }

enum AppViewMode { classic, tabs, windows }

class AppSettingsProvider extends ChangeNotifier {
  // Default values
  AppLanguage _language = AppLanguage.arabic;
  ThemeMode _themeMode = ThemeMode.light;
  CostMethod _costMethod = CostMethod.linearMeter;
  AppViewMode _viewMode = AppViewMode.classic;
  double _profitMargin = 0.0;
  double _fontSizeScale = 1.0;
  String _geminiApiKey =
      'AQ.Ab8RN6K0VzsqO944GLUZOKqevI4ncAbuewu7Cx8pEUg3O-xVaA';

  String _userRole = 'worker';
  String _workshopCode = '';
  String _userDisplayName = 'مدير الورشة';
  Map<String, dynamic> _workerPermissions = {};
  StreamSubscription<DocumentSnapshot>? _permSubscription;
  StreamSubscription<Map<String, dynamic>>? _supabasePermSubscription;
  String? _permissionListenerUid;
  // Firestore is the authoritative source for the signed-in user's role.
  // Supabase can refresh permissions at the same time, but its first row may
  // briefly be stale while a workshop sync is starting.  Do not let that
  // transient row downgrade a manager and cause open screens to close.
  bool _firestoreRoleLoaded = false;
  bool _firestorePermissionsAvailable = false;

  @override
  void dispose() {
    _permSubscription?.cancel();
    _supabasePermSubscription?.cancel();
    super.dispose();
  }

  // Getters
  AppLanguage get language => _language;

  ThemeMode get themeMode => _themeMode;

  CostMethod get costMethod => _costMethod;

  AppViewMode get viewMode => _viewMode;

  double get profitMargin => _profitMargin;

  double get fontSizeScale => _fontSizeScale;

  String get geminiApiKey => _geminiApiKey;

  bool get isDarkMode => _themeMode == ThemeMode.dark;

  bool get enablePremiumAnimations => true;

  String get userRole => _userRole;

  String get workshopCode => _workshopCode;

  String get userDisplayName => _userDisplayName;

  bool get isManager =>
      _userRole == 'manager' ||
      _userRole == 'admin' ||
      (_userRole == 'co_manager' &&
          (_isPermissionTrue(_workerPermissions['full_manager_permissions']) ||
              _isPermissionTrue(_workerPermissions['co_manager']))) ||
      isAdmin;

  bool get isCoManager => _userRole == 'co_manager';

  AppSettingsProvider() {
    loadSettings();
  }

  void _startPermissionListener(User user, SharedPreferences prefs) {
    // Keep one live listener per signed-in account. Recreating this listener
    // during every subscription snapshot could briefly miss a permission
    // change exactly while the manager was saving it.
    if (_permissionListenerUid == user.uid && _permSubscription != null) {
      return;
    }

    _permSubscription?.cancel();
    _firestoreRoleLoaded = false;
    _firestorePermissionsAvailable = false;
    _permissionListenerUid = user.uid;
    _permSubscription = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .snapshots()
        .listen((docSnap) {
          _firestoreRoleLoaded = true;
          final data = docSnap.data();
          _firestorePermissionsAvailable = docSnap.exists && data != null;
          if (!docSnap.exists || data == null) {
            _userRole = 'worker';
            _workerPermissions = {};
            notifyListeners();
            unawaited(prefs.setString('user_role', _userRole));
            return;
          }

          if (!isApplicationAdminEmail(user.email)) {
            final remoteRole = data['role']?.toString() ?? '';
            final isWorkshopOwner = data['workshopId']?.toString() == user.uid;
            _userRole = remoteRole == 'manager' || isWorkshopOwner
                ? 'manager'
                : remoteRole == 'co_manager'
                ? 'co_manager'
                : 'worker';
          }

          Map<String, dynamic> cloudPermissions = {};
          // The Map is the current Firestore field. The JSON field is only a
          // legacy fallback; preferring it could reapply an older snapshot.
          final rawPermissions = data['permissions'];
          final permissionsJson = data['permissions_json'];
          if (rawPermissions is Map) {
            cloudPermissions = Map<String, dynamic>.from(rawPermissions);
          } else if (permissionsJson is String && permissionsJson.isNotEmpty) {
            try {
              final decoded = jsonDecode(permissionsJson);
              if (decoded is Map) {
                cloudPermissions = Map<String, dynamic>.from(decoded);
              }
            } catch (_) {}
          } else if (data['permissions'] is Map) {
            cloudPermissions = Map<String, dynamic>.from(data['permissions']);
          }

          // Update the running app first. Cache writes must never delay the
          // permission that the worker sees on screen.
          _workerPermissions = cloudPermissions;
          notifyListeners();
          unawaited(prefs.setString('user_role', _userRole));
          unawaited(
            prefs.setString(
              'permissions_cloud_fingerprint',
              permissionsJson is String
                  ? permissionsJson
                  : jsonEncode(data['permissions'] ?? {}),
            ),
          );
        });
  }

  void _startSupabasePermissionListener() {
    _supabasePermSubscription ??= SupabaseWorkshopSyncService()
        .permissionsStream
        .listen((payload) {
          final role = payload['role']?.toString() ?? '';
          final rawPermissions = payload['permissions'];
          // Firebase owns permissions for accounts that have a Firebase user
          // document. Supabase refreshes can be briefly behind a manager's
          // latest save, so never let them overwrite that authoritative value.
          if (_firestorePermissionsAvailable) return;
          if (!isAdmin && role.isNotEmpty && !_firestorePermissionsAvailable) {
            _userRole = role;
          }
          if (rawPermissions is Map) {
            _workerPermissions = Map<String, dynamic>.from(rawPermissions);
          }
          notifyListeners();
        });

    unawaited(
      SupabaseWorkshopSyncService().refreshCurrentPermissions().catchError(
        (_) {},
      ),
    );
  }

  Future<void> reloadPermissions() async {
    final oldWorkshopCode = _workshopCode;
    final oldUserDisplayName = _userDisplayName;
    final oldRole = _userRole;
    final oldPermissions = Map<String, dynamic>.from(_workerPermissions);

    final prefs = await SharedPreferences.getInstance();
    _workshopCode = prefs.getString('workshop_code') ?? '';
    _userDisplayName = prefs.getString('user_display_name') ?? 'مدير الورشة';
    final cached = _decodeCachedPermissions(
      prefs.getString('permissions_json'),
    );
    if (!_firestorePermissionsAvailable &&
        (cached.isNotEmpty || _workerPermissions.isEmpty)) {
      _workerPermissions = cached;
    }

    User? user;
    try {
      user = FirebaseAuth.instance.currentUser;
    } catch (_) {}

    if (user == null) {
      _permSubscription?.cancel();
      _permSubscription = null;
      _permissionListenerUid = null;
      _firestoreRoleLoaded = false;
      _firestorePermissionsAvailable = false;
      _userRole = prefs.getString('user_role') ?? 'worker';
    } else {
      if (isApplicationAdminEmail(user.email)) {
        // Keep the application administrator distinct from workshop managers.
        _userRole = 'admin';
        await prefs.setString('user_role', 'admin');
      } else {
        // Never grant manager access merely because this computer has no
        // cached role yet. The first Firestore snapshot is authoritative.
        if (!_firestoreRoleLoaded) {
          _userRole = prefs.getString('user_role') ?? 'worker';
        }
      }

      try {
        _startPermissionListener(user, prefs);
      } catch (_) {}
      _startSupabasePermissionListener();
    }

    final hasChanged =
        _workshopCode != oldWorkshopCode ||
        _userDisplayName != oldUserDisplayName ||
        _userRole != oldRole ||
        !mapEquals(_workerPermissions, oldPermissions);

    if (hasChanged) {
      notifyListeners();
    }
  }

  Map<String, dynamic> _decodeCachedPermissions(String? rawJson) {
    if (rawJson == null || rawJson.trim().isEmpty) return {};
    try {
      final decoded = jsonDecode(rawJson);
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
    } catch (_) {}
    return {};
  }

  bool _isPermissionTrue(dynamic val) {
    if (val == true) return true;
    if (val == 1) return true;
    if (val is String) {
      final s = val.trim().toLowerCase();
      return s == 'true' || s == '1';
    }
    return false;
  }

  bool _isPermissionTrueOrDefault(dynamic val, {bool defaultValue = false}) {
    if (val == null) return defaultValue;
    if (val == true || val == 1) return true;
    if (val == false || val == 0) return false;
    if (val is String) {
      final s = val.trim().toLowerCase();
      if (s == 'false' || s == '0') return false;
      if (s == 'true' || s == '1') return true;
    }
    return defaultValue;
  }

  DateTime? _parsePermissionDate(dynamic value) {
    final raw = value?.toString().trim() ?? '';
    if (raw.isEmpty) return null;
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return null;
    return DateTime(parsed.year, parsed.month, parsed.day);
  }

  bool _permissionWindowIsActive(String permissionKey) {
    final from = _parsePermissionDate(
      _workerPermissions['${permissionKey}_valid_from'],
    );
    final to = _parsePermissionDate(
      _workerPermissions['${permissionKey}_valid_to'],
    );
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    if (from != null && today.isBefore(from)) return false;
    if (to != null && today.isAfter(to)) return false;
    return true;
  }

  bool _isSubPermissionEnabled(String key) {
    if (isManager) return true;
    if (!canViewMyAccreditations()) return false;
    if (!_workerPermissions.containsKey(key) ||
        _workerPermissions[key] == null) {
      return false;
    }
    return _isPermissionTrueOrDefault(_workerPermissions[key]);
  }

  // RBAC Permission Checkers
  bool canViewClients() =>
      isManager ||
      _isPermissionTrueOrDefault(_workerPermissions['view_clients']);

  bool canViewClientLedger() =>
      isManager || _isPermissionTrue(_workerPermissions['view_client_ledger']);

  bool canCreateClients() =>
      isManager || _isPermissionTrue(_workerPermissions['create_clients']);

  bool canEditClients() =>
      isManager || _isPermissionTrue(_workerPermissions['edit_clients']);

  bool canDeleteClients() =>
      isManager || _isPermissionTrue(_workerPermissions['delete_clients']);

  bool canViewOrders() =>
      isManager ||
      _isPermissionTrueOrDefault(_workerPermissions['view_orders']);

  bool canViewProjects() =>
      isManager ||
      _isPermissionTrueOrDefault(_workerPermissions['view_projects']);

  bool canAccessInventory() =>
      isManager || _isPermissionTrue(_workerPermissions['inventory']);

  bool canAdjustInventory() =>
      isManager ||
      (canAccessInventory() &&
          _isPermissionTrue(_workerPermissions['inventory_adjustment']) &&
          _permissionWindowIsActive('inventory_adjustment'));

  bool canAccessDistributionTracking() =>
      isManager ||
      _isPermissionTrue(_workerPermissions['distribution_tracking']);

  bool canViewSales() =>
      isManager || _isPermissionTrue(_workerPermissions['sales']);

  bool canViewGlobalConsumption() =>
      isManager || _isPermissionTrue(_workerPermissions['global_consumption']);

  bool canViewWorkerFinances() =>
      isManager || _isPermissionTrue(_workerPermissions['worker_finances']);

  bool canViewWorkerWeeklySettlement() =>
      isManager || _isPermissionTrue(_workerPermissions['worker_settlement']);

  bool canCreateOrders() =>
      isManager || _isPermissionTrue(_workerPermissions['create_orders']);

  bool canEditOrders() =>
      isManager || _isPermissionTrue(_workerPermissions['edit_orders']);

  bool canViewClientDetails() =>
      isManager ||
      _isPermissionTrueOrDefault(_workerPermissions['view_client_details']);

  bool canViewOrderDetails() =>
      isManager ||
      _isPermissionTrueOrDefault(_workerPermissions['view_order_details']);

  bool canViewOrderDocuments() =>
      isManager ||
      _isPermissionTrueOrDefault(_workerPermissions['view_order_documents']);

  bool canViewFicheDeCoupe() =>
      isManager ||
      _isPermissionTrueOrDefault(_workerPermissions['fiche_de_coupe']);

  bool canViewOrderMaterials() =>
      isManager ||
      _isPermissionTrueOrDefault(_workerPermissions['view_order_materials']);

  bool canConfirmMeasurements() =>
      isManager ||
      _isPermissionTrue(_workerPermissions['confirm_measurements']);

  bool canAccessMeasurements() =>
      isManager || _isPermissionTrue(_workerPermissions['measurements_card']);

  bool canChangeOrderStatus() =>
      isManager || _isPermissionTrue(_workerPermissions['change_order_status']);

  bool canPassNextStage() =>
      isManager || _isPermissionTrue(_workerPermissions['pass_to_next_stage']);

  bool canDuplicateOrders() =>
      isManager || _isPermissionTrue(_workerPermissions['duplicate_orders']);

  bool canViewMyTasks() =>
      isManager ||
      _isPermissionTrueOrDefault(_workerPermissions['view_my_tasks']);

  bool canViewAllWorkerTasks() =>
      isManager ||
      _isPermissionTrue(_workerPermissions['view_all_worker_tasks']) ||
      _isPermissionTrue(_workerPermissions['view_all_tasks']);

  bool canViewMyAccreditations() =>
      isManager ||
      _isPermissionTrueOrDefault(_workerPermissions['view_my_accreditations']);

  bool canViewProfiles() => _isSubPermissionEnabled('view_profiles');

  bool canViewGlass() => _isSubPermissionEnabled('view_glass');

  bool canViewShutters() => _isSubPermissionEnabled('view_shutters');

  bool canViewColors() => _isSubPermissionEnabled('view_colors');

  bool canViewAccessories() => _isSubPermissionEnabled('view_accessories');

  bool canViewSeriesAccessories() =>
      _isSubPermissionEnabled('view_series_accessories');

  bool canViewJoints() => _isSubPermissionEnabled('view_joints');

  bool canViewKitBundles() => _isSubPermissionEnabled('view_kit_bundles');

  bool canAccessExternalOperations() =>
      isManager || _isPermissionTrue(_workerPermissions['external_operations']);

  bool canAllocateTasks() =>
      isManager || _isPermissionTrue(_workerPermissions['order_allocation']);

  bool canAccessSettings() =>
      isManager || _isPermissionTrue(_workerPermissions['settings']);

  bool canSelectSystems() =>
      isManager || _isPermissionTrue(_workerPermissions['select_systems']);

  bool canChangePrices() =>
      isManager || _isPermissionTrue(_workerPermissions['change_prices']);

  bool canViewCostPrice() =>
      isManager || _isPermissionTrue(_workerPermissions['view_cost_price']);

  bool canAccessTreasury() =>
      isManager || _isPermissionTrue(_workerPermissions['treasury']);

  bool canChangeTransactionDates() =>
      isManager ||
      _isPermissionTrue(_workerPermissions['change_transaction_dates']);

  bool canManageWorkers() =>
      isManager || _isPermissionTrue(_workerPermissions['manage_workers']);

  bool canEditWorker() =>
      isManager || _isPermissionTrue(_workerPermissions['edit_worker']);

  bool canDeleteWorker() =>
      isManager || _isPermissionTrue(_workerPermissions['delete_worker']);

  bool canBackupToCloud() =>
      isManager || _isPermissionTrue(_workerPermissions['cloud_backup']);

  bool canSyncGlobalCatalog() =>
      isManager || _isPermissionTrue(_workerPermissions['sync_global_catalog']);

  bool canAccessLocalJsonBackup() =>
      isManager || _isPermissionTrue(_workerPermissions['local_json_backup']);

  bool canRegisterPurchases() =>
      isManager || _isPermissionTrue(_workerPermissions['purchases']);

  bool canAddPurchases() =>
      isManager || _isPermissionTrue(_workerPermissions['add_purchases']);

  bool canEditPurchases() =>
      isManager || _isPermissionTrue(_workerPermissions['edit_purchases']);

  bool canDeletePurchases() =>
      isManager || _isPermissionTrue(_workerPermissions['delete_purchases']);

  bool canAccelerateConfirmedInvoices() =>
      isManager ||
      _isPermissionTrue(_workerPermissions['accelerate_confirmed_invoices']);

  bool canViewStatistics() =>
      isManager || _isPermissionTrue(_workerPermissions['statistics']);

  bool canDeleteOrders() =>
      isManager || _isPermissionTrue(_workerPermissions['delete_orders']);

  bool canViewSuppliers() =>
      isManager || _isPermissionTrue(_workerPermissions['view_suppliers']);

  bool canEditPayments() =>
      isManager || _isPermissionTrue(_workerPermissions['edit_payments']);

  bool canDeletePayments() =>
      isManager || _isPermissionTrue(_workerPermissions['delete_payments']);

  bool canManageCaisses() =>
      isManager || _workerPermissions['manage_caisses'] == true;

  // Load settings from SharedPreferences
  Future<void> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();

    // Load Language
    final langIndex = prefs.getInt('app_language') ?? 0;
    _language = AppLanguage.values[langIndex];

    // Load Theme
    final isDark = prefs.getBool('app_is_dark') ?? false;
    _themeMode = isDark ? ThemeMode.dark : ThemeMode.light;

    // Load Cost Method
    final costIndex = prefs.getInt('app_cost_method') ?? 0;
    _costMethod = CostMethod.values[costIndex];
    _profitMargin = prefs.getDouble('app_profit_margin') ?? 20.0; // Default 20%

    // Load View Mode
    final viewModeIndex = prefs.getInt('app_view_mode') ?? 0;
    if (viewModeIndex < AppViewMode.values.length) {
      _viewMode = AppViewMode.values[viewModeIndex];
    } else {
      _viewMode = AppViewMode.classic;
    }

    // Load Font Size
    _fontSizeScale = prefs.getDouble('app_font_scale') ?? 1.0;

    // Load API Key — always use the latest key
    const latestKey = 'AQ.Ab8RN6K0VzsqO944GLUZOKqevI4ncAbuewu7Cx8pEUg3O-xVaA';
    String savedKey = prefs.getString('app_gemini_api_key') ?? '';
    // إذا كان المفتاح المحفوظ هو القديم أو فارغ، استخدم الجديد
    if (savedKey.isEmpty ||
        savedKey == 'AQ.Ab8RN6IG6H5dVvsdAM0aPusDJrTfJ2-SNA22NToPNklSb-27IQ') {
      _geminiApiKey = latestKey;
      await prefs.setString('app_gemini_api_key', latestKey);
    } else {
      _geminiApiKey = savedKey;
    }

    await reloadPermissions();
  }

  // Setters with save functionality
  Future<void> setLanguage(AppLanguage lang) async {
    _language = lang;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('app_language', lang.index);
  }

  Future<void> setTheme(ThemeMode mode) async {
    _themeMode = mode;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('app_is_dark', mode == ThemeMode.dark);
  }

  Future<void> setCostMethod(CostMethod method) async {
    _costMethod = method;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('app_cost_method', method.index);
  }

  Future<void> setViewMode(AppViewMode mode) async {
    _viewMode = mode;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('app_view_mode', mode.index);
  }

  Future<void> setProfitMargin(double margin) async {
    _profitMargin = margin;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('app_profit_margin', margin);
  }

  Future<void> setFontSizeScale(double scale) async {
    _fontSizeScale = scale;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('app_font_scale', scale);
  }

  Future<void> setGeminiApiKey(String key) async {
    _geminiApiKey = key;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('app_gemini_api_key', key);
  }
}
