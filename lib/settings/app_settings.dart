import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:database_data/services/supabase_workshop_sync_service.dart';
import 'package:database_data/services/auth_service.dart';

bool get isAdmin {
  final user = AppAuthService().currentUser;
  return isApplicationAdminEmail(user?.email);
}

bool isApplicationAdminEmail(String? email) {
  final clean = (email ?? '').trim().toLowerCase();
  return clean == 'kouidrihamza45@gmail.com' ||
      clean == 'kouidrihamza046@gmail.com' ||
      clean == 'kouidrihamza46@gmail.com';
}

enum AppLanguage { arabic, french, english }

enum CostMethod { linearMeter, squareMeter, percentage }

enum AppViewMode { classic, tabs, windows }

enum AppUpdateMode { automatic, manual }

enum BusinessActivityType {
  workshopOnly, // ورشة فقط
  materialsStoreOnly, // محل بيع مواد فقط
  workshopAndStore, // ورشة + محل بيع مواد
}

enum WorkingSection {
  all, // كل الأقسام
  management, // الإدارة العامة
  workshop, // تطبيق الورشة
  materialsStore, // تطبيق محل بيع المواد
}

class AppSettingsProvider extends ChangeNotifier {
  // Default values
  // French is the default application language.
  AppLanguage _language = AppLanguage.french;
  ThemeMode _themeMode = ThemeMode.light;
  CostMethod _costMethod = CostMethod.linearMeter;
  bool _applyPurchasePricesToCostTable = false;
  BusinessActivityType _businessActivity =
      BusinessActivityType.workshopAndStore;
  WorkingSection _workingSection = WorkingSection.all;
  int? _defaultWorkshopLocationId;
  int? _defaultStoreLocationId;

  // Price synchronization options per category
  bool _syncPriceProfiles = true;
  bool _syncPriceSeries = true;
  bool _syncPriceAccessories = true;
  bool _syncPriceShutters = true;
  bool _syncPriceJoints = true;
  bool _syncPriceGlass = true;

  bool get syncPriceProfiles => _syncPriceProfiles;
  bool get syncPriceSeries => _syncPriceSeries;
  bool get syncPriceAccessories => _syncPriceAccessories;
  bool get syncPriceShutters => _syncPriceShutters;
  bool get syncPriceJoints => _syncPriceJoints;
  bool get syncPriceGlass => _syncPriceGlass;

  // Tabs are the default workspace on phones and other non-desktop devices.
  AppViewMode _viewMode = AppViewMode.tabs;
  AppUpdateMode _updateMode = AppUpdateMode.automatic;
  double _profitMargin = 0.0;
  double _fontSizeScale = 1.0;
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

  bool get applyPurchasePricesToCostTable => _applyPurchasePricesToCostTable;

  BusinessActivityType get businessActivity => _businessActivity;

  bool get hasWorkshop =>
      _businessActivity == BusinessActivityType.workshopOnly ||
      _businessActivity == BusinessActivityType.workshopAndStore;

  bool get hasMaterialsStore =>
      _businessActivity == BusinessActivityType.materialsStoreOnly ||
      _businessActivity == BusinessActivityType.workshopAndStore;

  bool get isDualActivity =>
      _businessActivity == BusinessActivityType.workshopAndStore;

  WorkingSection get workingSection {
    if (!hasWorkshop && hasMaterialsStore) return WorkingSection.materialsStore;
    if (hasWorkshop && !hasMaterialsStore) return WorkingSection.workshop;
    if (!canAccessWorkshopScope() && canAccessStoreScope())
      return WorkingSection.materialsStore;
    if (canAccessWorkshopScope() && !canAccessStoreScope())
      return WorkingSection.workshop;
    return _workingSection;
  }

  bool get isWorkingInWorkshop =>
      hasWorkshop &&
      canAccessWorkshopScope() &&
      (workingSection == WorkingSection.all ||
          workingSection == WorkingSection.workshop);

  bool get isWorkingInStore =>
      hasMaterialsStore &&
      canAccessStoreScope() &&
      (workingSection == WorkingSection.all ||
          workingSection == WorkingSection.materialsStore);

  bool get isWorkingInManagement =>
      workingSection == WorkingSection.all ||
      workingSection == WorkingSection.management;

  int? get defaultWorkshopLocationId => _defaultWorkshopLocationId;
  int? get defaultStoreLocationId => _defaultStoreLocationId;

  AppViewMode get viewMode => _viewMode;

  AppUpdateMode get updateMode => _updateMode;

  bool get isAutoUpdateEnabled => _updateMode == AppUpdateMode.automatic;

  String get appVersion => '1.0.0';

  double get profitMargin => _profitMargin;

  double get fontSizeScale => _fontSizeScale;

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

  bool get isAdmin =>
      isApplicationAdminEmail(AppAuthService().currentUser?.email);

  bool get isCoManager => _userRole == 'co_manager';

  AppSettingsProvider() {
    loadSettings();
  }

  void _startPermissionListener(AppAuthUser user, SharedPreferences prefs) {
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
          final previousRole = _userRole;
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
          final roleChanged = _userRole != previousRole;
          final permissionsChanged = !mapEquals(
            _workerPermissions,
            cloudPermissions,
          );
          _workerPermissions = cloudPermissions;
          if (roleChanged || permissionsChanged) notifyListeners();
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
          final previousRole = _userRole;
          final previousPermissions = Map<String, dynamic>.from(
            _workerPermissions,
          );
          final role = payload['role']?.toString() ?? '';
          final rawPermissions = payload['permissions'];
          // Once the Supabase session is open, Supabase is authoritative for
          // workshop roles and permissions. Firebase remains only the login
          // provider and must not overwrite this live workshop state.
          if (!isAdmin && role.isNotEmpty) {
            _userRole = role;
          }
          if (rawPermissions is Map) {
            _workerPermissions = Map<String, dynamic>.from(rawPermissions);
          }
          if (previousRole != _userRole ||
              !mapEquals(previousPermissions, _workerPermissions)) {
            notifyListeners();
          }
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

    AppAuthUser? user;
    try {
      user = AppAuthService().currentUser;
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
        if (SupabaseWorkshopSyncService().isSignedIn) {
          _permSubscription?.cancel();
          _permSubscription = null;
          _permissionListenerUid = null;
          _firestoreRoleLoaded = false;
          _firestorePermissionsAvailable = false;
        } else {
          _startPermissionListener(user, prefs);
        }
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

  /// Creating a warehouse is a separate administrative action from stock
  /// adjustment. Managers always have it; workers need an explicit grant.
  bool canAddWarehouses() =>
      isManager || _isPermissionTrue(_workerPermissions['add_warehouses']);

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

  bool canMaterialSales() =>
      isManager ||
      _isPermissionTrue(_workerPermissions['store_sales']) ||
      _isPermissionTrue(_workerPermissions['material_sales']) ||
      canViewSales();

  bool canViewStoreSales() =>
      isManager ||
      _isPermissionTrue(_workerPermissions['store_sales']) ||
      _isPermissionTrue(_workerPermissions['view_store_sales']);

  bool canCreateStoreSales() =>
      isManager || _isPermissionTrue(_workerPermissions['create_store_sales']);

  bool canEditStoreSales() =>
      isManager || _isPermissionTrue(_workerPermissions['edit_store_sales']);

  bool canConfirmStoreSales() =>
      isManager || _isPermissionTrue(_workerPermissions['confirm_store_sales']);

  bool canDeleteStoreSales() =>
      isManager || _isPermissionTrue(_workerPermissions['delete_store_sales']);

  bool canRegisterStorePayments() =>
      isManager ||
      _isPermissionTrue(_workerPermissions['register_store_payments']);

  bool canReturnStoreSales() =>
      isManager || _isPermissionTrue(_workerPermissions['return_store_sales']);

  bool canViewDocumentHistory() =>
      isManager ||
      _isPermissionTrue(_workerPermissions['view_document_history']);

  bool canRestoreDeletedDocuments() =>
      isManager ||
      _isPermissionTrue(_workerPermissions['restore_deleted_documents']);

  bool canCloseBusinessDay() =>
      isManager || _isPermissionTrue(_workerPermissions['close_business_day']);

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

  /// The series report contains catalogue rules and commercial usage totals.
  /// Managers have it automatically; other workers need an explicit grant.
  bool canViewSeriesRequirementsReport() =>
      isManager ||
      _isPermissionTrue(_workerPermissions['view_series_requirements_report']);

  bool canViewJoints() => _isSubPermissionEnabled('view_joints');

  bool canViewKitBundles() => _isSubPermissionEnabled('view_kit_bundles');

  bool canAccessExternalOperations() =>
      isManager || _isPermissionTrue(_workerPermissions['external_operations']);

  bool canAllocateTasks() =>
      isManager || _isPermissionTrue(_workerPermissions['order_allocation']);

  bool canAccessSettings() =>
      isManager || _isPermissionTrue(_workerPermissions['settings']);

  /// Subscription details are visible to managers by default. A normal worker
  /// only sees them when the workshop manager explicitly grants this permission.
  bool canViewSubscription() =>
      isManager || _isPermissionTrue(_workerPermissions['view_subscription']);

  /// The general application administrator and workshop managers always have
  /// access. Other workers need the explicit workshop permission.
  bool canSelectSystems() =>
      isAdmin ||
      isManager ||
      _isPermissionTrue(_workerPermissions['select_systems']);

  /// Workshop managers control their prices and can delegate price editing.
  bool canChangePrices() =>
      isManager || _isPermissionTrue(_workerPermissions['change_prices']);

  bool canViewCostPrice() =>
      isManager || _isPermissionTrue(_workerPermissions['view_cost_price']);

  bool canAccessTreasury() =>
      isManager || _isPermissionTrue(_workerPermissions['treasury']);

  bool canChangeTransactionDates() =>
      isManager ||
      _isPermissionTrue(_workerPermissions['change_transaction_dates']);

  /// Date permissions are separated by business area. Keep the old treasury
  /// permission as a compatibility fallback for existing workers.
  bool canChangeOrderDates() =>
      isManager || _isPermissionTrue(_workerPermissions['change_order_dates']);

  bool canChangePaymentDates() =>
      isManager ||
      _isPermissionTrue(_workerPermissions['change_payment_dates']) ||
      _isPermissionTrue(_workerPermissions['change_transaction_dates']);

  bool canChangePurchaseDates() =>
      isManager ||
      _isPermissionTrue(_workerPermissions['change_purchase_dates']);

  bool canManageWorkers() =>
      isManager || _isPermissionTrue(_workerPermissions['manage_workers']);

  bool canEditWorker() =>
      isManager || _isPermissionTrue(_workerPermissions['edit_worker']);

  bool canDeleteWorker() =>
      isManager || _isPermissionTrue(_workerPermissions['delete_worker']);

  bool canBackupToCloud() =>
      isManager || _isPermissionTrue(_workerPermissions['cloud_backup']);

  /// Every user who can open the products/catalogue screen must be able to
  /// refresh its shared catalogue on their device. This is a local download;
  /// it does not grant permission to edit or publish the global catalogue.
  bool canSyncGlobalCatalog() => canViewMyAccreditations();

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

  bool canAccessTrash() =>
      isManager || _isPermissionTrue(_workerPermissions['access_trash']);

  bool canViewSuppliers() =>
      isManager || _isPermissionTrue(_workerPermissions['view_suppliers']);

  bool canEditPayments() =>
      isManager || _isPermissionTrue(_workerPermissions['edit_payments']);

  bool canDeletePayments() =>
      isManager || _isPermissionTrue(_workerPermissions['delete_payments']);

  bool canManageCaisses() =>
      isManager || _isPermissionTrue(_workerPermissions['manage_caisses']);

  /// Creating a caisse is separately grantable from editing/deleting caisses.
  bool canAddCaisses() =>
      isManager || _isPermissionTrue(_workerPermissions['add_caisses']);

  // Granular Activity & Scope Permissions
  bool canAccessWorkshopScope() =>
      isManager ||
      _isPermissionTrueOrDefault(
        _workerPermissions['access_workshop'],
        defaultValue: true,
      );

  bool canAccessStoreScope() =>
      isManager ||
      _isPermissionTrueOrDefault(
        _workerPermissions['access_store'],
        defaultValue: true,
      );

  bool canAccessManagementScope() =>
      isManager || _isPermissionTrue(_workerPermissions['access_management']);

  bool canAccessWorkshopPurchases() =>
      hasWorkshop &&
      (isManager ||
          _isPermissionTrueOrDefault(
            _workerPermissions['workshop_purchases'],
            defaultValue: true,
          ) ||
          _isPermissionTrue(_workerPermissions['purchases']));

  bool canAccessStorePurchases() =>
      hasMaterialsStore &&
      (isManager ||
          _isPermissionTrueOrDefault(
            _workerPermissions['store_purchases'],
            defaultValue: true,
          ) ||
          _isPermissionTrue(_workerPermissions['purchases']));

  bool canAccessStoreSales() => hasMaterialsStore && canViewStoreSales();

  bool canExecuteInternalSales() =>
      isDualActivity &&
      (isManager ||
          _isPermissionTrueOrDefault(
            _workerPermissions['internal_sales'],
            defaultValue: true,
          ));

  /// Called after the user picks another language, e.g. so the push token
  /// row on the server is updated and closed-app pushes use that language.
  static void Function(AppLanguage language)? onLanguageChanged;

  /// The saved application language, readable without a [BuildContext]
  /// (background isolates, services, notification texts).
  static AppLanguage languageFromPreferences(SharedPreferences prefs) {
    final langIndex = prefs.getInt('app_language');
    final hasExplicitLanguage = prefs.getBool('app_language_explicit') ?? false;
    final effectiveLanguageIndex =
        langIndex == null ||
            (!hasExplicitLanguage && langIndex == AppLanguage.arabic.index)
        ? AppLanguage.french.index
        : langIndex;
    return effectiveLanguageIndex >= 0 &&
            effectiveLanguageIndex < AppLanguage.values.length
        ? AppLanguage.values[effectiveLanguageIndex]
        : AppLanguage.french;
  }

  static Future<AppLanguage> loadSavedLanguage() async {
    try {
      return languageFromPreferences(await SharedPreferences.getInstance());
    } catch (_) {
      return AppLanguage.french;
    }
  }

  // Load settings from SharedPreferences
  Future<void> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();

    // Load Language. Older installations used Arabic as the implicit default
    // (without an explicit user choice), so upgrade only that old default to
    // French while preserving a language selected by the user.
    _language = languageFromPreferences(prefs);

    // Load Theme
    final isDark = prefs.getBool('app_is_dark') ?? false;
    _themeMode = isDark ? ThemeMode.dark : ThemeMode.light;

    // Load Cost Method
    final costIndex = prefs.getInt('app_cost_method') ?? 0;
    _costMethod = CostMethod.values[costIndex];
    _applyPurchasePricesToCostTable =
        prefs.getBool('app_apply_purchase_prices_to_cost_table') ?? false;
    _profitMargin = prefs.getDouble('app_profit_margin') ?? 20.0; // Default 20%

    // Load Price Synchronization Preferences
    _syncPriceProfiles = prefs.getBool('sync_price_profiles') ?? true;
    _syncPriceSeries = prefs.getBool('sync_price_series') ?? true;
    _syncPriceAccessories = prefs.getBool('sync_price_accessories') ?? true;
    _syncPriceShutters = prefs.getBool('sync_price_shutters') ?? true;
    _syncPriceJoints = prefs.getBool('sync_price_joints') ?? true;
    _syncPriceGlass = prefs.getBool('sync_price_glass') ?? true;
    _extraPriceSyncSwitches
      ..clear()
      ..addAll({
        for (final key in prefs.getKeys())
          if (key.startsWith('sync_price_'))
            key.substring('sync_price_'.length): prefs.getBool(key) ?? true,
      });

    // Load Business Activity Type (Default: workshopAndStore)
    final activityIndex = prefs.getInt('app_business_activity');
    if (activityIndex != null &&
        activityIndex >= 0 &&
        activityIndex < BusinessActivityType.values.length) {
      _businessActivity = BusinessActivityType.values[activityIndex];
    } else {
      _businessActivity = BusinessActivityType.workshopAndStore;
    }

    // Load Working Section
    final sectionIndex = prefs.getInt('app_working_section');
    if (sectionIndex != null &&
        sectionIndex >= 0 &&
        sectionIndex < WorkingSection.values.length) {
      _workingSection = WorkingSection.values[sectionIndex];
    } else {
      _workingSection = WorkingSection.all;
    }

    _defaultWorkshopLocationId = prefs.getInt(
      'app_default_workshop_location_id',
    );
    _defaultStoreLocationId = prefs.getInt('app_default_store_location_id');

    // Load View Mode. A value of classic without the explicit-choice marker
    // belongs to older installations where classic was the old default.
    // Upgrade those installations to tabs once, while preserving any mode
    // the user deliberately selected from Settings.
    final viewModeIndex = prefs.getInt('app_view_mode');
    final hasExplicitViewMode =
        prefs.getBool('app_view_mode_explicit') ?? false;
    final effectiveViewModeIndex =
        viewModeIndex == null ||
            (!hasExplicitViewMode && viewModeIndex == AppViewMode.classic.index)
        ? AppViewMode.tabs.index
        : (viewModeIndex ?? AppViewMode.tabs.index);
    if (effectiveViewModeIndex < AppViewMode.values.length) {
      _viewMode = AppViewMode.values[effectiveViewModeIndex];
    } else {
      _viewMode = AppViewMode.tabs;
    }

    // Load Update Mode (defaults to automatic)
    final updateModeIndex = prefs.getInt('app_update_mode');
    if (updateModeIndex != null &&
        updateModeIndex >= 0 &&
        updateModeIndex < AppUpdateMode.values.length) {
      _updateMode = AppUpdateMode.values[updateModeIndex];
    } else {
      _updateMode = AppUpdateMode.automatic;
    }

    // Load Font Size
    _fontSizeScale = prefs.getDouble('app_font_scale') ?? 1.0;

    await reloadPermissions();
  }

  // Setters with save functionality
  Future<void> setLanguage(AppLanguage lang) async {
    _language = lang;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('app_language', lang.index);
    await prefs.setBool('app_language_explicit', true);
    onLanguageChanged?.call(lang);
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

  Future<void> setApplyPurchasePricesToCostTable(bool value) async {
    _applyPurchasePricesToCostTable = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('app_apply_purchase_prices_to_cost_table', value);
  }

  Future<void> setViewMode(AppViewMode mode) async {
    _viewMode = mode;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('app_view_mode', mode.index);
    await prefs.setBool('app_view_mode_explicit', true);
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

  Future<void> setBusinessActivity(BusinessActivityType activity) async {
    _businessActivity = activity;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('app_business_activity', activity.index);
  }

  Future<void> setUpdateMode(AppUpdateMode mode) async {
    _updateMode = mode;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('app_update_mode', mode.index);
  }

  Future<void> setWorkingSection(WorkingSection section) async {
    if (section == WorkingSection.workshop && !canAccessWorkshopScope()) return;
    if (section == WorkingSection.materialsStore && !canAccessStoreScope())
      return;
    if (section == WorkingSection.all &&
        (!canAccessWorkshopScope() || !canAccessStoreScope())) {
      if (canAccessStoreScope()) {
        _workingSection = WorkingSection.materialsStore;
      } else {
        _workingSection = WorkingSection.workshop;
      }
    } else {
      _workingSection = section;
    }
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('app_working_section', _workingSection.index);
  }

  Future<void> setDefaultWorkshopLocationId(int? id) async {
    _defaultWorkshopLocationId = id;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    if (id != null) {
      await prefs.setInt('app_default_workshop_location_id', id);
    } else {
      await prefs.remove('app_default_workshop_location_id');
    }
  }

  Future<void> setDefaultStoreLocationId(int? id) async {
    _defaultStoreLocationId = id;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    if (id != null) {
      await prefs.setInt('app_default_store_location_id', id);
    } else {
      await prefs.remove('app_default_store_location_id');
    }
  }

  Future<void> setSyncPriceProfiles(bool value) async {
    _syncPriceProfiles = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('sync_price_profiles', value);
  }

  Future<void> setSyncPriceSeries(bool value) async {
    _syncPriceSeries = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('sync_price_series', value);
  }

  Future<void> setSyncPriceAccessories(bool value) async {
    _syncPriceAccessories = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('sync_price_accessories', value);
  }

  Future<void> setSyncPriceShutters(bool value) async {
    _syncPriceShutters = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('sync_price_shutters', value);
  }

  Future<void> setSyncPriceJoints(bool value) async {
    _syncPriceJoints = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('sync_price_joints', value);
  }

  Future<void> setSyncPriceGlass(bool value) async {
    _syncPriceGlass = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('sync_price_glass', value);
  }

  /// Price-sync switches of the price pages added after the six above
  /// (stored as `sync_price_<category>`, enabled by default).
  final Map<String, bool> _extraPriceSyncSwitches = {};

  bool isExtraPriceSyncEnabled(String category) =>
      _extraPriceSyncSwitches[category] ?? true;

  Future<void> setExtraPriceSyncEnabled(String category, bool value) async {
    _extraPriceSyncSwitches[category] = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('sync_price_$category', value);
  }
}
