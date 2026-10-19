import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:path/path.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:database_data/services/cloud_sync_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart' hide Transaction;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:sqflite_common_ffi/sqflite_ffi.dart' as sqflite_common;
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';
import 'package:flutter_file_dialog/flutter_file_dialog.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:database_data/Commande/Systeme/model.dart';
import 'package:database_data/Commande/Systeme/model_serialization.dart';
import 'package:database_data/Commande/Systeme/shutter_calc_rules.dart';
import 'package:database_data/Commande/capture_image.dart';
import 'package:database_data/Commande/order_status_order.dart';
import 'package:database_data/services/auth_service.dart';
import 'package:database_data/services/order_notification_service.dart';
import 'package:database_data/services/worker_push_notification_service.dart';
import 'package:database_data/services/price_sync_service.dart';

part 'sql_database/schema.dart';
part 'sql_database/sync_backup.dart';
part 'sql_database/tempered_glass.dart';
part 'sql_database/finance.dart';
part 'sql_database/purchases.dart';
part 'sql_database/workers.dart';
part 'sql_database/inventory_sales.dart';
part 'sql_database/orders_clients.dart';
part 'sql_database/catalog.dart';

class DuplicateClientException implements Exception {
  final String field;
  final String value;

  const DuplicateClientException(this.field, this.value);

  @override
  String toString() => 'DuplicateClientException($field: $value)';
}

class CloudChangeAcknowledgement {
  const CloudChangeAcknowledgement({
    required this.table,
    required this.rowId,
    required this.revision,
  });

  final String table;
  final String rowId;
  final int revision;
}

class PendingCloudChanges {
  const PendingCloudChanges({
    required this.data,
    required this.acknowledgements,
    required this.changedRows,
    required this.deletedRows,
  });

  final Map<String, dynamic> data;
  final List<CloudChangeAcknowledgement> acknowledgements;
  final int changedRows;
  final int deletedRows;

  bool get isEmpty => acknowledgements.isEmpty;
}

class SqlDatabase {
  /// Treasury rows that pay a shop document (MaterialSales) carry
  /// `document_type = 'MaterialSale'`. They are client receipts, but they
  /// already settle the shop document (`MaterialSales.paid_amount`), so the
  /// window-order ledger must never allocate them to `Commandes` again.
  static const String materialSaleDocumentType = 'MaterialSale';

  static Set<String> _inventoryTypeAliases(String itemType) {
    switch (itemType.toLowerCase().replaceAll(' ', '').trim()) {
      case 'section':
      case 'sections':
      case 'profile':
      case 'profiles':
        return {'Sections', 'Section', 'Profiles', 'Profile'};
      case 'accessory':
      case 'accessories':
        return {'Accessories', 'Accessory'};
      case 'shuttercomponent':
      case 'shuttercomponents':
        return {'ShutterComponents', 'ShutterComponent', 'Shutter Components'};
      case 'joint':
      case 'joints':
        return {'Joints', 'Joint'};
      case 'glass':
        return {'Glass', 'glass'};
      default:
        return {itemType};
    }
  }

  /// Last time `PRAGMA quick_check` passed. The check reads the whole
  /// database; running it before every sync upload (250 ms after any write)
  /// froze the interface on large workshops.
  static DateTime? _lastHealthyCheckAt;

  static const Duration _healthCheckInterval = Duration(minutes: 10);

  /// Schema (tables, their definitions and triggers) for which the sync
  /// tracking was last installed. The full pass reads every table and
  /// creates four triggers per table; it is called before every upload and
  /// many deletions, so it only runs again when the schema really changed.
  static String? _syncInfrastructureSignature;

  static Database? _db;
  static Future<Database>? _openingDb;
  static Future<void>? _databaseReopenTask;
  // Schema checks are required when the database is opened, but running the
  // same CREATE/ALTER/INDEX statements before every catalogue query makes
  // the material table unnecessarily slow (especially on older databases).
  // Keep one in-flight/completed task per open database connection.
  static Object? _seriesDesignSchemaOwner;
  static Future<void>? _seriesDesignSchemaTask;
  static Object? _advancedKitSchemaOwner;
  static Future<void>? _advancedKitSchemaTask;
  static Object? _accessoryLinksSchemaOwner;
  static Future<void>? _accessoryLinksSchemaTask;
  static Object? _remnantInventorySchemaOwner;
  static Future<void>? _remnantInventorySchemaTask;
  static bool _knownColorsRepaired = false;
  static final Random _distributedIdRandom = Random.secure();
  static int _lastDistributedId = 0;

  static String _repairLegacyTextEncoding(String value) {
    if (value.isEmpty ||
        (!value.contains('Ø') &&
            !value.contains('Ã') &&
            !value.contains('Â'))) {
      return value;
    }
    try {
      final repaired = utf8.decode(latin1.encode(value));
      return repaired.contains('�') ? value : repaired;
    } catch (_) {
      return value;
    }
  }

  static const String _mainCaisseName = 'الصندوق الرئيسي';
  static const String _secondCaisseName = 'الصندوق الثاني';
  static const String _bankCaisseName = 'البنك';

  static String? _canonicalCaisseName(String value) {
    final normalized = value.trim().toLowerCase().replaceAll('é', 'e');
    switch (normalized) {
      case _mainCaisseName:
      case 'caisse principale':
        return _mainCaisseName;
      case _secondCaisseName:
      case 'deuxieme caisse':
        return _secondCaisseName;
      case _bankCaisseName:
      case 'banque':
        return _bankCaisseName;
      default:
        return null;
    }
  }

  static bool _looksLikeUnreadableCaisseName(String value) {
    final name = value.trim();
    if (name.isEmpty || name.contains('�') || name.contains('ï¿½')) {
      return true;
    }
    if (name.contains('Ø') ||
        name.contains('Ù') ||
        name.contains('Ã') ||
        name.contains('Â') ||
        name.contains('Ð') ||
        name.contains('Ñ')) {
      return true;
    }
    if (name.codeUnits.any((unit) => unit < 32 || unit == 127)) return true;
    if (RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
      caseSensitive: false,
    ).hasMatch(name)) {
      return true;
    }
    return RegExp(
      r'^(caisse|cashbox)[_-][a-z0-9_-]{12,}$',
      caseSensitive: false,
    ).hasMatch(name);
  }

  static final DatabaseFactory _webDbFactory = createDatabaseFactoryFfiWeb(
    noWebWorker: true,
    options: SqfliteFfiWebOptions(
      sqlite3WasmUri: Uri.parse('assets/web/sqlite3.wasm'),
    ),
    tag: 'erp_web',
  );

  /// Generates an ordered 64-bit ID without relying on a device-local
  /// AUTOINCREMENT value, so concurrent offline additions cannot collide.
  static int _nextDistributedId() {
    var candidate =
        DateTime.now().millisecondsSinceEpoch * 1000000 +
        _distributedIdRandom.nextInt(1000000);
    if (candidate <= _lastDistributedId) {
      candidate = _lastDistributedId + 1;
    }
    _lastDistributedId = candidate;
    return candidate;
  }


  static double? _readStoredNumber(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString().trim() ?? '');
  }

  static String _canonicalKnownColorHex(String name, String fallback) {
    final normalized = name.toLowerCase().trim();
    if (normalized.contains('9007')) return '#8A939E';
    if (normalized.contains('desert')) {
      return '#B68B55';
    }
    if (normalized.contains('champagne') ||
        normalized.contains('chompagne') ||
        normalized.contains('شامبان')) {
      return '#F7E7CE';
    }
    if (normalized.contains('faux bois marron') ||
        normalized.contains('marron faux bois') ||
        (normalized.contains('marron') && normalized.contains('bois')) ||
        (normalized.contains('بني') && normalized.contains('خشب'))) {
      // A light faux-bois brown, not the dark antique.
      return '#A9774E';
    }
    final isGold =
        normalized.contains('gold') ||
        normalized.contains('ذهبي') ||
        normalized.contains('doré') ||
        normalized.contains('dore') ||
        RegExp(r'(^|[\s/(_-])or($|[\s/)_-])').hasMatch(normalized);
    if (isGold) return '#D4AF37';
    return fallback;
  }

  /// Identity of a colour name for duplicate detection: case, spacing and
  /// Arabic letter variants are ignored, and the spellings of one colour
  /// (Champagne / شامبانيا / شمبانيا ...) share one key.
  static String colorIdentityKey(Object? name) {
    final normalized = (name ?? '')
        .toString()
        .toLowerCase()
        .trim()
        .replaceAll(RegExp('[أإآ]'), 'ا')
        .replaceAll('ى', 'ي')
        .replaceAll('ة', 'ه')
        .replaceAll(RegExp(r'[\s_\-]+'), ' ');
    const champagne = [
      'champagne',
      'chompagne',
      'شامبانيا',
      'شمبانيا',
      'شومبانيا',
      'شامبان',
      'شمبان',
    ];
    // Only a name made of champagne spellings alone (e.g. "شمبانيا
    // (Champagne)"); "Champagne mat" stays a colour of its own.
    var rest = normalized;
    for (final spelling in champagne) {
      rest = rest.replaceAll(spelling, ' ');
    }
    if (rest != normalized && rest.replaceAll(RegExp(r'[\s()/]+'), '').isEmpty) {
      return 'champagne';
    }
    return normalized;
  }

  static String _canonicalLegacyColorName(String value) {
    const exactFixes = <String, String>{
      'â•ªÃºâ•ªÂ¿â”˜Ã¨â•ªâ•¢': 'أبيض',
      'â•ªÂ¿â”˜Ã¥â”˜Ã¨': 'بني',
      'â•ªâ–’â”˜Ã â•ªÂºâ•ªÂ»â”˜Ã¨': 'رمادي',
      'â•ªÃºâ•ªâ”‚â”˜Ãªâ•ªÂ»': 'أسود',
      'â•ªÂ¿â”˜Ã¨â•ªÂ¼': 'بيج',
      'â•ªâ”¤â•ªÂºâ”˜Ã â•ªÂ¿â•ªÂºâ”˜Ã¥': 'شمبانيا',
    };
    final exact = exactFixes[value];
    if (exact != null) return exact;
    return _repairLegacyTextEncoding(value);
  }

  static const String _whiteColorSql =
      "(LOWER(name) LIKE '%white%' OR LOWER(name) LIKE '%blanc%' "
      "OR name LIKE '%أبيض%' OR name LIKE '%ابيض%' "
      "OR REPLACE(LOWER(hex_code), '#', '') IN ('ffffff', 'fff'))";

  static String _profileColorSyncId(int profileId, int colorId) =>
      '$profileId:$colorId';

  static Map<String, dynamic> _withDistributedId(Map<String, dynamic> values) {
    return <String, dynamic>{
      ...values,
      'id': values['id'] ?? _nextDistributedId(),
    };
  }

  static DatabaseFactory get _dbFactory {
    if (kIsWeb) {
      // The shared-worker variant depends on sqflite_sw.js being present in
      // every Firebase deployment. The no-worker variant persists in
      // IndexedDB and reads the bundled wasm asset above instead.
      return _webDbFactory;
    }
    if (!kIsWeb &&
        (Platform.isWindows ||
            Platform.isLinux ||
            Platform.isMacOS ||
            Platform.environment.containsKey('FLUTTER_TEST'))) {
      sqflite_common.sqfliteFfiInit();
      return sqflite_common.databaseFactoryFfi;
    }
    return databaseFactory;
  }

  /// Returns a writable path for the SQLite database file.
  /// On desktop platforms, getDatabasesPath() from sqflite_ffi can return the
  /// app's installation directory (e.g. Program Files) which is read-only for
  /// standard users. We use getApplicationSupportDirectory() from path_provider
  /// instead, which always resolves to a writable location (%AppData% on Windows).
  static Future<String> _getWritableDatabasesPath() async {
    if (!kIsWeb &&
        (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      try {
        final appSupportDir = await getApplicationSupportDirectory();
        final dbDir = Directory(join(appSupportDir.path, 'databases'));
        if (!await dbDir.exists()) await dbDir.create(recursive: true);
        return dbDir.path;
      } catch (_) {}
    }
    // Mobile platforms use sqflite's platform database directory. Calling
    // this helper again here caused unbounded recursion (Stack Overflow), so
    // Android could fail before opening or restoring its local database.
    return await getDatabasesPath();
  }

  static const List<String> catalogTables = [
    'Profile',
    'Series',
    'Sections',
    'Colors',
    'Accessories',
    'Joints',
    'Glass',
    'ShutterComponents',
    'ShutterComponentColors',
    'ProfileColors',
    'ProfileColorConfig',
    'KitBundles',
    'KitBundleItems',
    'KitItemRanges',
    'KitItemVariants',
    'TemperedGlassItems',
    'TemperedGlassSystems',
    'TemperedGlassKits',
    'TemperedGlassKitHoles',
    'TemperedGlassKitComponents',
    'TemperedGlassSystemRules',
  ];

  static const List<String> workshopTables = [
    // The catalogue is global and is synced through catalog_manifest and
    // catalog_chunks in Supabase. It must never be copied into a workshop
    // backup, otherwise one workshop could overwrite every other workshop's
    // catalogue.
    'ClientCodeSequence',
    'Client',
    'Projects',
    'Measurements',
    'Commandes',
    'Commandes_details',
    'Commandes_deliveries',
    'Achats',
    'Achat_items',
    'Achat_Details',
    'Suppliers',
    'Employees',
    'Caisses',
    'Treasury',
    'PaymentAllocations',
    'WorkerTransactions',
    'WorkerAllocations',
    'WorkerAttendance',
    'WorkerDailyJobs',
    'Locations',
    'InventoryTransactions',
    'CurrentStock',
    'InventorySettings',
    'OrderCuttingSessions',
    'OrderInventoryIssueSessions',
    'StockReservations',
    'MaterialRemnants',
    'MaterialScrap',
    'StandardSheets',
    // Selling prices are workshop data: each workshop has its own local
    // market prices and must not overwrite another workshop's prices.
    'GlassColorPrices',
    'ShutterColorPrices',
    'ShutterSqmPrices',
    'ShutterBoxLimits',
    'CaissonTunnelPrices',
    'SeriesColorPrices',
    'SectionColorPrices',
    'AccessoryColorPrices',
    // The workshop's own catalogue base prices and price-origin markers.
    'WorkshopPriceOverrides',
    'MaterialSales',
    'MaterialSaleItems',
    'AuditLogs',
    'BusinessDayClosings',
  ];

  // These rows describe how a workshop uses the shared catalogue. The base
  // catalogue remains global, while these workshop configuration rows are
  // mirrored only to the other phones in the same workshop. Keep them out of
  // [catalogTables]: otherwise a central-catalog refresh can replace a
  // workshop's rules with another snapshot.
  static const List<String> workshopCatalogConfigurationTables = [
    'SeriesTableConfig',
    'SeriesDesignConfig',
    'SeriesDesignRoles',
    'SectionSharingRules',
    'FrameJoinRules',
    'ProfileCompatibilityGroups',
    'ShutterCalcRules',
    'CatalogItemRules',
    'ProfileCalculationRules',
    'SectionJointLinks',
    'SeriesShutterRules',
    'AccessoryLinks',
    'AccessoryRoleLinks',
  ];

  static void resetDb() {
    _db = null;
    _openingDb = null;
    _seriesDesignSchemaOwner = null;
    _seriesDesignSchemaTask = null;
    _advancedKitSchemaOwner = null;
    _advancedKitSchemaTask = null;
    _accessoryLinksSchemaOwner = null;
    _accessoryLinksSchemaTask = null;
    _remnantInventorySchemaOwner = null;
    _remnantInventorySchemaTask = null;
    _syncInfrastructureSignature = null;
    _lastHealthyCheckAt = null;
    _readySchemas.clear();
    // A reopened or restored database file may lack these columns again.
    _decorPanelDesignSchemaReady = false;
    _orderCodeInfrastructureReady = false;
    _orderTrashInfrastructureReady = false;
    _orderPinningInfrastructureReady = false;
    _achatTrashInfrastructureReady = false;
    _auditLogsInfrastructureReady = false;
    _dashboardActivitiesInfrastructureReady = false;
  }

  /// Indexes on the most-read workshop tables. Without them every order,
  /// ledger, stock and worker screen scanned whole tables. Each index is only
  /// created when its columns exist on this (possibly old) database.
  static const List<(String, String, List<String>)> _performanceIndexes = [
    ('idx_commandes_client', 'Commandes', ['client_id']),
    ('idx_commandes_details_order', 'Commandes_details', ['id_commandes']),
    ('idx_commandes_deliveries_order', 'Commandes_deliveries', [
      'id_commandes',
    ]),
    ('idx_treasury_entity', 'Treasury', ['entity_type', 'entity_id']),
    ('idx_treasury_reference', 'Treasury', ['reference_id']),
    ('idx_inventory_tx_item', 'InventoryTransactions', [
      'item_id',
      'item_type',
      'color_id',
    ]),
    ('idx_inventory_tx_reference', 'InventoryTransactions', [
      'reference_id',
      'transaction_type',
    ]),
    ('idx_worker_allocations_worker', 'WorkerAllocations', [
      'worker_uid',
      'is_settled',
    ]),
    ('idx_worker_transactions_worker', 'WorkerTransactions', [
      'worker_uid',
      'is_settled',
    ]),
    ('idx_achat_items_achat', 'Achat_items', ['achat_id']),
    ('idx_achat_items_item', 'Achat_items', ['item_id', 'item_type']),
    ('idx_achats_supplier', 'Achats', ['supplier_id']),
    ('idx_material_sale_items_sale', 'MaterialSaleItems', ['sale_id']),
  ];

  Future<void> _ensurePerformanceIndexes(DatabaseExecutor db) async {
    for (final (name, table, columns) in _performanceIndexes) {
      try {
        final existing = await _tableColumns(db, table);
        if (!columns.every(existing.contains)) continue;
        await db.execute(
          'CREATE INDEX IF NOT EXISTS $name ON $table (${columns.join(', ')})',
        );
      } catch (error) {
        debugPrint('Index $name skipped: $error');
      }
    }
  }

  /// Schema checks already done on the open database. They run ALTER/CREATE
  /// statements that fail harmlessly when the column exists, yet every failing
  /// statement still parses the schema and takes a write lock, and several of
  /// them ran on every list read (accessories, stock, orders, clients...).
  static final Set<String> _readySchemas = <String>{};

  Future<void> _ensureSchemaOnce(
    DatabaseExecutor executor,
    String key,
    Future<void> Function() ensure,
  ) async {
    if (_readySchemas.contains(key)) return;
    await ensure();
    // A transaction may still roll back its schema change: only a check run
    // directly on the database is remembered.
    if (executor is Database) _readySchemas.add(key);
  }

  /// Clears only the workshop-specific transactional rows (orders, customers, stock, finances),
  /// while preserving the global aluminium catalog (profiles, series, sections, colors, accessories).
  static Future<void> clearWorkshopDataOnly() async {
    try {
      final dbInstance = await SqlDatabase().db;
      if (dbInstance == null) return;
      await dbInstance.transaction((txn) async {
        for (final table in workshopTables) {
          try {
            await txn.delete(table);
          } catch (_) {}
        }
        for (final table in workshopCatalogConfigurationTables) {
          try {
            await txn.delete(table);
          } catch (_) {}
        }
      });
      debugPrint('Workshop data cleared successfully; catalog preserved.');
    } catch (e) {
      debugPrint('Error clearing workshop data: $e');
    }
  }

  static Future<void> clearAllLocalData() async {
    // Close database
    if (_db != null) {
      try {
        await _db!.close();
      } catch (_) {}
      _db = null;
      _openingDb = null;
    }
    // Delete SQLite file
    try {
      final dbName = 'test.db';
      final dataPath = await _getWritableDatabasesPath();
      final path = join(dataPath, dbName);
      await _dbFactory.deleteDatabase(path);
      debugPrint('Database file test.db deleted successfully.');
    } catch (e) {
      debugPrint('Error deleting database file: $e');
    }
    // Clear SharedPreferences
    try {
      final prefs = await SharedPreferences.getInstance();
      // Keep settings, device ID, and offline account cache so user can re-log in or work offline
      final lang = prefs.getString('language');
      final theme = prefs.getString('themeMode');
      final deviceId = prefs.getString('device_id');
      final cachedAccounts = <String, String>{};
      for (final key in prefs.getKeys()) {
        if (key.startsWith('supabase_account_cache_v1_')) {
          final val = prefs.getString(key);
          if (val != null) cachedAccounts[key] = val;
        }
      }

      await prefs.clear();

      if (lang != null) await prefs.setString('language', lang);
      if (theme != null) await prefs.setString('themeMode', theme);
      if (deviceId != null) await prefs.setString('device_id', deviceId);
      for (final entry in cachedAccounts.entries) {
        await prefs.setString(entry.key, entry.value);
      }
      debugPrint(
        'SharedPreferences cleared successfully (settings & offline account cache preserved).',
      );
    } catch (e) {
      debugPrint('Error clearing SharedPreferences: $e');
    }
  }

  String get now => DateTime.now().toUtc().toIso8601String();

  String get date => DateFormat('yyyy-MM-dd').format(DateTime.now());














  static bool _decorPanelDesignSchemaReady = false;



  /// Normalised movement kinds shown on the product card.
  static const String movementPurchaseReceipt = 'purchase_receipt';

  static const String movementSaleIssue = 'sale_issue';

  static const String movementInternalTransfer = 'internal_transfer';

  static const String movementProductionIssue = 'production_issue';

  static const String movementReturn = 'return';

  static const String movementAdjustment = 'adjustment';

  static const String movementRemnant = 'remnant';

  static const String movementDamage = 'damage';

  /// Maps the free-text `transaction_type` written by older code and screens
  /// to a [movement_type]. Used for new rows and to read old ones.
  static String movementTypeForTransaction(String transactionType) {
    final type = transactionType.toLowerCase();
    if (type.contains('internal transfer') || type.contains('internal return')) {
      return SqlDatabase.movementInternalTransfer;
    }
    if (type.contains('return') || type.contains('reversal')) {
      return SqlDatabase.movementReturn;
    }
    if (type.startsWith('purchase')) return SqlDatabase.movementPurchaseReceipt;
    if (type.contains('material sale')) return SqlDatabase.movementSaleIssue;
    if (type == 'order_issue_remnant') return SqlDatabase.movementRemnant;
    if (type.startsWith('order_issue')) return SqlDatabase.movementProductionIssue;
    if (type.contains('cutting_error') || type.contains('scrap')) {
      return SqlDatabase.movementDamage;
    }
    return SqlDatabase.movementAdjustment;
  }

  /// A new id shared by the two legs of one transfer.
  static String _newTransferId() =>
      'TRF-${DateTime.now().toUtc().microsecondsSinceEpoch}-'
      '${Random().nextInt(1 << 20)}';

  /// The signed-in account's id, or null when signed out.
  static String? currentEditorUid() {
    try {
      final uid = AppAuthService().currentUser?.uid.trim() ?? '';
      return uid.isEmpty ? null : uid;
    } catch (_) {
      return null;
    }
  }

  /// True when the latest change to [order] was made by the signed-in
  /// account itself, so it must not appear as unread to that account.
  static bool isOwnLatestOrderEdit(Map<String, dynamic> order) {
    final uid = currentEditorUid();
    if (uid == null) return false;
    final version = order['updated_at']?.toString() ?? '';
    return order['last_editor_uid']?.toString() == uid &&
        version.isNotEmpty &&
        order['last_editor_version']?.toString() == version;
  }

  static Object? _localEditorUidOwner;

  static String? _localEditorUidWritten;

  Future<Database?> get db async {
    final current = _db;
    if (current != null) {
      _refreshLocalEditorUid(current);
      return current;
    }

    // Several startup services ask for SQLite concurrently. Opening the same
    // file twice while migrations are running can leave a stale native handle
    // behind, so all callers must share one opening operation.
    final opening = _openingDb;
    if (opening != null) return opening;

    late final Future<Database> task;
    task = initDb().whenComplete(() {
      if (identical(_openingDb, task)) {
        _openingDb = null;
      }
    });
    _openingDb = task;
    final opened = await task;
    _db = opened;
    _refreshLocalEditorUid(opened);
    return opened;
  }


  static bool isCorruptionError(Object error) {
    final text = error.toString().toLowerCase();
    return text.contains('database image malformed') ||
        text.contains('database disk image is malformed') ||
        text.contains('file is not a database') ||
        text.contains('sqlite_corrupt') ||
        text.contains('sqlite_notadb') ||
        text.contains('sqlite_error: 26') ||
        text.contains('sqlite error 26') ||
        text.contains('code 11');
  }

  /// SQLite code 1032 (SQLITE_READONLY_DBMOVED) means the file was replaced
  /// or moved after this connection was opened. It is not a permissions issue:
  /// close the stale handle and reopen the current application database before
  /// attempting the write again.
  static bool isDatabaseMovedError(Object error) {
    final text = error.toString().toLowerCase();
    return text.contains('code 1032') ||
        text.contains('readonly_dbmoved') ||
        text.contains('database has been moved');
  }



  Future<T> _retryAfterDatabaseMove<T>(Future<T> Function() operation) async {
    try {
      return await operation();
    } catch (error) {
      if (!isDatabaseMovedError(error)) rethrow;
      await reopenAfterDatabaseMoved();
      return operation();
    }
  }
























  //////////////////////////////////// Sections //////////////////////////////////////
  Future<List<Map<String, dynamic>>> readSectionsBySeries(int seriesId) async {
    Database? myDb = await db;
    return await myDb!.query(
      'Sections',
      where: 'series_id = ? AND (is_active = 1 OR is_active IS NULL)',
      whereArgs: [seriesId],
    );
  }





  // ─── FrameJoinRules ────────────────────────────────────────────────────────














  static bool _orderCodeInfrastructureReady = false;
  static bool _orderTrashInfrastructureReady = false;
  static bool _orderPinningInfrastructureReady = false;




  bool _orderStockReservationInfrastructureReady = false;






















  String get _currentCreationPlatform {
    final user = AppAuthService().currentUser;
    final displayName = user?.displayName?.trim() ?? '';
    if (displayName.isNotEmpty) return displayName;

    final email = user?.email?.trim() ?? '';
    if (email.isNotEmpty) {
      return email.contains('@') ? email.split('@').first.trim() : email;
    }
    return 'system';
  }































  Future<int> getPriorConfirmedWindowsCount(int targetOrderId) async {
    Database? myDb = await db;
    final res = await myDb!.rawQuery(
      '''
      SELECT SUM(d.quantity) as total_windows
      FROM Commandes_details d
      JOIN Commandes c ON d.id_commandes = c.id
      WHERE c.id < ? 
        AND c.status NOT IN ('En attente', 'في الانتظار', 'Pending', 'Draft', 'ملغاة', 'Nouveau', 'New', 'جديدة', 'جديد')
    ''',
      [targetOrderId],
    );

    if (res.isNotEmpty && res.first['total_windows'] != null) {
      return (res.first['total_windows'] as num).toInt();
    }
    return 0;
  }


































































  Future<int> emptyTrash() async {
    final myDb = await db;
    if (myDb == null) return 0;
    await _ensureOrderTrashInfrastructure(myDb);
    final rows = await myDb.query(
      'Commandes',
      columns: ['id'],
      where: 'is_deleted = 1',
    );
    int total = 0;
    for (final r in rows) {
      final id = _positiveInt(r['id']);
      if (id > 0) {
        final deleted = await deleteCommandePermanently(id);
        if (deleted > 0) total++;
      }
    }
    return total;
  }











  static const Map<int, int> _unicodeToWin1252Map = <int, int>{
    0x20AC: 0x80,
    0x201A: 0x82,
    0x0192: 0x83,
    0x201E: 0x84,
    0x2026: 0x85,
    0x2020: 0x86,
    0x2021: 0x87,
    0x02C6: 0x88,
    0x2030: 0x89,
    0x0160: 0x8A,
    0x2039: 0x8B,
    0x0152: 0x8C,
    0x017D: 0x8E,
    0x2018: 0x91,
    0x2019: 0x92,
    0x201C: 0x93,
    0x201D: 0x94,
    0x2022: 0x95,
    0x2013: 0x96,
    0x2014: 0x97,
    0x02DC: 0x98,
    0x2122: 0x99,
    0x0161: 0x9A,
    0x203A: 0x9B,
    0x0153: 0x9C,
    0x017E: 0x9E,
    0x0178: 0x9F,
  };

































  static bool _achatTrashInfrastructureReady = false;


























  bool _isInsertingColors = false;


























  //////////////////////////////////// Glass //////////////////////////////////////
  Future<List<Map<String, dynamic>>> readGlass() async {
    Database? myDb = await db;
    await _ensureDecorPanelDesignSchema(myDb!);
    return await myDb.query(
      'Glass',
      where: 'is_active = 1 OR is_active IS NULL',
    );
  }
























  static const double _paymentTolerance = 0.0001;

  static int? _paymentRecordId(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  static double _paymentNumber(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0.0;
  }

  static String _normalisedTreasuryType(String value) {
    return _repairLegacyTextEncoding(
      value,
    ).trim().toLowerCase().replaceAll('é', 'e');
  }

  static bool _isClientReceipt(Map<String, dynamic> row) {
    return row['entity_type']?.toString().trim().toLowerCase() == 'client' &&
        _normalisedTreasuryType(row['transaction_type']?.toString() ?? '') ==
            'encaissement';
  }

  static bool _isSupplierPayment(Map<String, dynamic> row) {
    return row['entity_type']?.toString().trim().toLowerCase() == 'supplier' &&
        _normalisedTreasuryType(row['transaction_type']?.toString() ?? '') ==
            'decaissement';
  }





























  /// Catalogue base-price columns. The catalogue is global, so a workshop's
  /// own value for one of these columns lives in [WorkshopPriceOverrides].
  static const Map<String, List<String>> workshopBasePriceColumns = {
    'Accessories': ['price'],
    'Glass': ['price_per_sqm'],
    'Joints': ['price_per_meter'],
    'Series': ['price_per_meter'],
    'ShutterComponents': ['price'],
    'Sections': ['price_dzd'],
    'TemperedGlassItems': ['price', 'cost_price'],
  };

  /// Sources of a workshop price that an administrator publication must not
  /// replace unless the manager explicitly asks for it.
  static const Set<String> ownWorkshopPriceSources = {'manual', 'purchase'};

  static String priceRowKey(Iterable<Object?> keys) =>
      keys.map((key) => '${key ?? ''}').join('|');

  /// Workshop-owned prices: typed by the manager, derived from a purchase or
  /// accepted from an administrator publication. The table is workshop data,
  /// so every phone of the workshop receives it. Base catalogue prices are
  /// re-applied from it after each catalogue refresh; colour-price rows only
  /// use it as a marker of who set the price.
  Future<void> _ensureWorkshopPriceSchema(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS WorkshopPriceOverrides (
        id INTEGER PRIMARY KEY,
        table_name TEXT NOT NULL,
        row_key TEXT NOT NULL,
        column_name TEXT NOT NULL,
        price REAL NOT NULL DEFAULT 0.0,
        source TEXT NOT NULL DEFAULT 'manual',
        updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
        UNIQUE(table_name, row_key, column_name)
      )
    ''');

    // GlassColorPrices had no id column: the sync triggers and the workshop
    // upload skip such tables, so glass colour prices never reached the other
    // phones of the workshop. Rebuild it once with distributed ids.
    final glassColumns = await _tableColumns(db, 'GlassColorPrices');
    if (glassColumns.isEmpty || glassColumns.contains('id')) return;
    final rows = await db.query('GlassColorPrices');
    await db.execute('DROP TABLE IF EXISTS GlassColorPrices_with_id');
    await db.execute('''
      CREATE TABLE GlassColorPrices_with_id (
        id INTEGER PRIMARY KEY,
        glass_id INTEGER,
        color_name TEXT,
        price REAL NOT NULL,
        UNIQUE(glass_id, color_name)
      )
    ''');
    for (final row in rows) {
      await db.insert(
        'GlassColorPrices_with_id',
        _withDistributedId({
          'glass_id': row['glass_id'],
          'color_name': row['color_name'],
          'price': row['price'] ?? 0.0,
        }),
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
    await db.execute('DROP TABLE GlassColorPrices');
    await db.execute(
      'ALTER TABLE GlassColorPrices_with_id RENAME TO GlassColorPrices',
    );
  }

  /// Records a workshop-owned price. Never throws: a failed marker must not
  /// undo the price the user has just saved.
  Future<void> recordWorkshopPrice(
    DatabaseExecutor executor, {
    required String table,
    required String rowKey,
    required String column,
    required double price,
    required String source,
  }) async {
    try {
      final now = DateTime.now().toUtc().toIso8601String();
      final updated = await executor.update(
        'WorkshopPriceOverrides',
        {'price': price, 'source': source, 'updated_at': now},
        where: 'table_name = ? AND row_key = ? AND column_name = ?',
        whereArgs: [table, rowKey, column],
      );
      if (updated == 0) {
        await executor.insert(
          'WorkshopPriceOverrides',
          _withDistributedId({
            'table_name': table,
            'row_key': rowKey,
            'column_name': column,
            'price': price,
            'source': source,
            'updated_at': now,
          }),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    } catch (error) {
      debugPrint('Workshop price marker skipped for $table/$rowKey: $error');
    }
  }

  Future<void> markWorkshopPrice({
    required String table,
    required String rowKey,
    required String column,
    required double price,
    String source = 'manual',
  }) async {
    final myDb = await db;
    if (myDb == null) return;
    await recordWorkshopPrice(
      myDb,
      table: table,
      rowKey: rowKey,
      column: column,
      price: price,
      source: source,
    );
  }

  /// (table → row key) pairs whose price the workshop set itself.
  Future<Set<String>> readOwnWorkshopPriceKeys(DatabaseExecutor executor) async {
    try {
      final rows = await executor.query(
        'WorkshopPriceOverrides',
        columns: const ['table_name', 'row_key'],
        where:
            'source IN (${List.filled(ownWorkshopPriceSources.length, '?').join(', ')})',
        whereArgs: ownWorkshopPriceSources.toList(),
      );
      return {for (final r in rows) '${r['table_name']}\x1f${r['row_key']}'};
    } catch (_) {
      return <String>{};
    }
  }

  Future<Map<String, Map<String, Map<String, double>>>> _readBasePriceOverrides(
    DatabaseExecutor executor,
  ) async {
    final result = <String, Map<String, Map<String, double>>>{};
    List<Map<String, Object?>> rows;
    try {
      rows = await executor.query(
        'WorkshopPriceOverrides',
        where:
            'table_name IN (${List.filled(workshopBasePriceColumns.length, '?').join(', ')})',
        whereArgs: workshopBasePriceColumns.keys.toList(),
      );
    } catch (_) {
      return result;
    }
    for (final row in rows) {
      final table = row['table_name']?.toString() ?? '';
      final column = row['column_name']?.toString() ?? '';
      if (!(workshopBasePriceColumns[table]?.contains(column) ?? false)) {
        continue;
      }
      final price = (row['price'] as num?)?.toDouble();
      if (price == null) continue;
      result
          .putIfAbsent(table, () => {})
          .putIfAbsent(row['row_key']?.toString() ?? '', () => {})[column] =
          price;
    }
    return result;
  }

  /// Puts the workshop's own base prices back into an incoming catalogue so a
  /// central-catalogue refresh cannot erase them.
  Future<void> _overlayWorkshopBasePrices(
    Map<String, dynamic> catalogData,
  ) async {
    final myDb = await db;
    if (myDb == null) return;
    final overrides = await _readBasePriceOverrides(myDb);
    for (final entry in overrides.entries) {
      final rows = catalogData[entry.key];
      if (rows is! List) continue;
      for (final row in rows) {
        if (row is! Map) continue;
        final prices = entry.value['${row['id']}'];
        if (prices != null) row.addAll(prices);
      }
    }
  }

  /// Writes the workshop's own base prices into the local catalogue tables,
  /// e.g. after another phone of the workshop sent new overrides.
  Future<void> applyWorkshopBasePriceOverrides() async {
    final myDb = await db;
    if (myDb == null) return;
    final overrides = await _readBasePriceOverrides(myDb);
    if (overrides.isEmpty) return;
    await myDb.transaction((txn) async {
      // Catalogue tables are not uploaded with the workshop data, so these
      // local writes must not pile up in the change log.
      await txn.update('_sync_runtime_flags', {
        'suppress_tombstones': 1,
      }, where: 'id = 1');
      try {
        for (final entry in overrides.entries) {
          final columns = await _tableColumns(txn, entry.key);
          for (final row in entry.value.entries) {
            for (final price in row.value.entries) {
              if (!columns.contains(price.key)) continue;
              await txn.rawUpdate(
                'UPDATE "${entry.key}" SET "${price.key}" = ? '
                'WHERE CAST(id AS TEXT) = ? '
                'AND ("${price.key}" IS NULL OR "${price.key}" != ?)',
                [price.value, row.key, price.value],
              );
            }
          }
        }
      } finally {
        await txn.update('_sync_runtime_flags', {
          'suppress_tombstones': 0,
        }, where: 'id = 1');
      }
    });
  }

  static bool _isSafeSqlIdentifier(String value) {
    return RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$').hasMatch(value);
  }


















































  // ── Standard Sheets & 2D Offcuts ──


























  Future<double> getSectionPrice(dynamic nameOrId, [int? colorId]) async {
    final database = await db;
    if (database == null) return 0.0;

    // Resolve to section id first
    int? sectionId;
    double fallbackPrice = 0.0;

    if (nameOrId is int) {
      sectionId = nameOrId;
      final res = await database.query(
        'Sections',
        where: 'id = ?',
        whereArgs: [sectionId],
        limit: 1,
      );
      if (res.isNotEmpty) {
        fallbackPrice = (res.first['price_dzd'] as num?)?.toDouble() ?? 0.0;
      }
    } else {
      final res = await database.query(
        'Sections',
        where: 'name = ?',
        whereArgs: [nameOrId],
        limit: 1,
      );
      if (res.isNotEmpty) {
        sectionId = res.first['id'] as int?;
        fallbackPrice = (res.first['price_dzd'] as num?)?.toDouble() ?? 0.0;
      }
    }

    if (sectionId == null) return 0.0;

    // If colorId provided, look up SectionColorPrices first
    if (colorId != null) {
      final colorRes = await database.query(
        'SectionColorPrices',
        where: 'section_id = ? AND color_id = ?',
        whereArgs: [sectionId, colorId],
        limit: 1,
      );
      if (colorRes.isNotEmpty) {
        final colorPrice = (colorRes.first['price'] as num?)?.toDouble() ?? 0.0;
        if (colorPrice > 0) return colorPrice;
      }
    }

    if (fallbackPrice > 0) return fallbackPrice;

    // If we reach here, we have 0 price. Let's try to get ANY color price as a final fallback.
    final anyColorRes = await database.query(
      'SectionColorPrices',
      where: 'section_id = ? AND price > 0',
      whereArgs: [sectionId],
      limit: 1,
    );
    if (anyColorRes.isNotEmpty) {
      return (anyColorRes.first['price'] as num?)?.toDouble() ?? 0.0;
    }

    return fallbackPrice;
  }


  static bool _auditLogsInfrastructureReady = false;
  static bool _dashboardActivitiesInfrastructureReady = false;









  /// Search filter shared by [readAuditLogsPage] and [countAuditLogs].
  /// The JSON snapshots in `details` are deliberately not scanned: they hold
  /// whole documents and would make every keystroke a full-table read.
  (String?, List<Object?>) _auditLogsSearchClause(String? query) {
    final q = (query ?? '').trim();
    if (q.isEmpty) return (null, const []);
    final like = '%$q%';
    return (
      '(entity_title LIKE ? OR user_name LIKE ? OR action_type LIKE ? '
          'OR entity_type LIKE ? OR entity_id LIKE ?)',
      [like, like, like, like, like],
    );
  }

  /// Reads one page of the audit log, newest first, without the heavy
  /// `details` payload. Pass the last row of the previous page as
  /// [beforeTimestamp]/[beforeId] to continue (keyset pagination).
  Future<List<Map<String, dynamic>>> readAuditLogsPage({
    int limit = 50,
    String? beforeTimestamp,
    int? beforeId,
    String? query,
  }) async {
    final database = await db;
    if (database == null) return [];
    try {
      await _ensureAuditLogsInfrastructure(database);
      final where = <String>[];
      final args = <Object?>[];
      final (searchWhere, searchArgs) = _auditLogsSearchClause(query);
      if (searchWhere != null) {
        where.add(searchWhere);
        args.addAll(searchArgs);
      }
      if (beforeTimestamp != null && beforeId != null) {
        where.add('(timestamp < ? OR (timestamp = ? AND id < ?))');
        args.addAll([beforeTimestamp, beforeTimestamp, beforeId]);
      }
      args.add(limit);
      return await database.rawQuery('''
        SELECT id, action_type, entity_type, entity_id, entity_title,
               user_name, timestamp,
               CASE WHEN details IS NULL OR details = '' THEN 0 ELSE 1 END
                 AS has_details,
               CASE WHEN substr(details, 1, 1) IN ('{', '[') THEN ''
                    ELSE substr(COALESCE(details, ''), 1, 300) END
                 AS details_preview
        FROM AuditLogs
        ${where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}'}
        ORDER BY timestamp DESC, id DESC
        LIMIT ?
      ''', args);
    } catch (e) {
      debugPrint('Error reading audit logs page: $e');
      return [];
    }
  }

  Future<int> countAuditLogs({String? query}) async {
    final database = await db;
    if (database == null) return 0;
    try {
      await _ensureAuditLogsInfrastructure(database);
      final (searchWhere, searchArgs) = _auditLogsSearchClause(query);
      final rows = await database.rawQuery(
        'SELECT COUNT(*) AS c FROM AuditLogs'
        '${searchWhere == null ? '' : ' WHERE $searchWhere'}',
        searchArgs,
      );
      return (rows.first['c'] as num?)?.toInt() ?? 0;
    } catch (_) {
      return 0;
    }
  }

  /// Loads the full before/after payload of one audit entry on demand.
  Future<String> readAuditLogDetails(int id) async {
    final database = await db;
    if (database == null) return '';
    try {
      await _ensureAuditLogsInfrastructure(database);
      final rows = await database.query(
        'AuditLogs',
        columns: ['details'],
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      if (rows.isEmpty) return '';
      return rows.first['details']?.toString() ?? '';
    } catch (_) {
      return '';
    }
  }

  // ========================= KIT BUNDLES CRUD =========================








  Future<List<Map<String, dynamic>>> readAccessoryLinksWithDetails(
    int sourceAccessoryId,
  ) async {
    final myDb = await db;
    if (myDb == null) return [];
    await _ensureAccessoryLinksSchema(myDb);
    final roleLinks = await myDb.rawQuery(
      '''
      SELECT id AS link_id, source_accessory_id, target_role_key,
             quantity AS linked_quantity
      FROM AccessoryRoleLinks
      WHERE source_accessory_id = ? AND is_active = 1
      ORDER BY id ASC
      ''',
      [sourceAccessoryId],
    );
    if (roleLinks.isNotEmpty) return roleLinks;
    return myDb.rawQuery(
      '''
      SELECT l.id AS link_id, l.source_accessory_id, l.target_accessory_id,
             l.quantity AS linked_quantity, a.*
      FROM AccessoryLinks l
      INNER JOIN Accessories a ON a.id = l.target_accessory_id
      WHERE l.source_accessory_id = ?
        AND l.is_active = 1
        AND (a.is_active = 1 OR a.is_active IS NULL)
      ORDER BY l.id ASC
      ''',
      [sourceAccessoryId],
    );
  }


  // ========================= KIT BUNDLE FAMILIES CRUD =========================





  // ========================= KIT BUNDLE ITEMS CRUD =========================





  // ========================= KIT ITEM RANGES CRUD =========================







  // ========================= KIT ITEM VARIANTS CRUD =========================










  // â”€â”€ Caisson Tunnel Prices â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€




  // â”€â”€ Series Table Config â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€



  // ── Dynamic design definition (drawing + shutter) ───────────────────────


  Future<List<Map<String, dynamic>>> getSeriesDesignRoles(int seriesId) async {
    final myDb = await db;
    if (myDb == null) return [];
    await _ensureSeriesDesignTables(myDb);
    await _ensureSectionSharingSchema(myDb);
    return myDb.rawQuery(
      '''
      SELECT r.*, s.code AS section_code, s.name AS section_name,
             s.type AS section_type, s.visible_width, s.thickness
      FROM SeriesDesignRoles r
      INNER JOIN Sections s ON s.id = r.section_id
      WHERE r.series_id = ?
        AND (
          s.series_id = ?
          OR EXISTS (
            SELECT 1
            FROM SectionSharingRules share
            WHERE share.source_section_id = s.id
              AND share.target_scope = 'series'
              AND share.target_id = ?
              AND share.role_key = r.role_key
              AND share.is_active = 1
          )
        )
      ORDER BY r.sort_order ASC, r.is_default DESC, r.id ASC
    ''',
      [seriesId, seriesId, seriesId],
    );
  }




  Future<List<Map<String, dynamic>>> getDefaultJointsForSection({
    required int seriesId,
    required int sectionId,
    Iterable<String> positionKeys = const [],
  }) async {
    final myDb = await db;
    if (myDb == null) return [];
    await _ensureSeriesDesignTables(myDb);
    final positions = positionKeys
        .map((key) => key.trim())
        .where((key) => key.isNotEmpty)
        .toList();
    final positionWhere = positions.isEmpty
        ? ''
        : 'AND l.position_key IN (${List.filled(positions.length, '?').join(',')})';
    return myDb.rawQuery(
      '''
      SELECT j.*, l.position_key, l.is_default AS link_is_default,
             l.sort_order AS link_sort_order
      FROM SectionJointLinks l
      INNER JOIN Joints j ON (
        (l.joint_id IS NOT NULL AND l.joint_id > 0 AND j.id = l.joint_id)
        OR (
          TRIM(l.gasket_type) != ''
          AND (
            j.gasket_type = l.gasket_type
            OR LOWER(j.gasket_type) = LOWER(l.gasket_type)
            OR (
              l.gasket_type LIKE '%فيتراج%'
              AND (
                j.gasket_type LIKE '%فيتراج%'
                OR j.gasket_type LIKE '%زجاج%'
                OR LOWER(j.gasket_type) LIKE '%vitrage%'
                OR LOWER(j.gasket_type) LIKE '%glass%'
                OR j.name LIKE '%فيتراج%'
                OR j.name LIKE '%زجاج%'
                OR LOWER(j.name) LIKE '%vitrage%'
                OR LOWER(j.name) LIKE '%glass%'
              )
            )
            OR (
              l.gasket_type LIKE '%فراب%'
              AND (
                j.gasket_type LIKE '%فراب%'
                OR j.gasket_type LIKE '%ضرب%'
                OR LOWER(j.gasket_type) LIKE '%frappe%'
                OR j.name LIKE '%فراب%'
                OR j.name LIKE '%ضرب%'
                OR LOWER(j.name) LIKE '%frappe%'
              )
            )
            OR (
              l.gasket_type LIKE '%سنترال%'
              AND (
                j.gasket_type LIKE '%سنترال%'
                OR j.gasket_type LIKE '%وسط%'
                OR LOWER(j.gasket_type) LIKE '%central%'
                OR j.name LIKE '%سنترال%'
                OR j.name LIKE '%وسط%'
                OR LOWER(j.name) LIKE '%central%'
              )
            )
            OR (
              (l.gasket_type LIKE '%براش%' OR l.gasket_type LIKE '%بروس%')
              AND (
                j.gasket_type LIKE '%براش%'
                OR j.gasket_type LIKE '%بروش%'
                OR j.gasket_type LIKE '%بروس%'
                OR LOWER(j.gasket_type) LIKE '%brosse%'
                OR LOWER(j.gasket_type) LIKE '%brush%'
                OR LOWER(j.gasket_type) LIKE '%bros%'
                OR j.name LIKE '%براش%'
                OR j.name LIKE '%بروش%'
                OR j.name LIKE '%بروس%'
                OR LOWER(j.name) LIKE '%brosse%'
                OR LOWER(j.name) LIKE '%brush%'
                OR LOWER(j.name) LIKE '%bros%'
              )
            )
            OR (
              l.gasket_type LIKE '%بوراج%'
              AND (
                j.gasket_type LIKE '%بوراج%'
                OR LOWER(j.gasket_type) LIKE '%bourrage%'
                OR LOWER(j.gasket_type) LIKE '%bouraj%'
                OR j.name LIKE '%بوراج%'
                OR LOWER(j.name) LIKE '%bourrage%'
                OR LOWER(j.name) LIKE '%bouraj%'
              )
            )
          )
        )
      )
      WHERE l.series_id = ?
        AND l.section_id = ?
        $positionWhere
        AND (j.is_active = 1 OR j.is_active IS NULL)
        AND (
          j.type IS NULL
          OR TRIM(j.type) = ''
          OR LOWER(j.type) LIKE '%aluminium%'
          OR LOWER(j.type) LIKE '%aluminum%'
        )
        AND (
          j.scope IS NULL
          OR TRIM(j.scope) = ''
          OR LOWER(j.scope) != 'unique'
          OR j.series_id = l.series_id
          OR (
            j.series_ids IS NOT NULL
            AND TRIM(j.series_ids) != ''
            AND ',' || REPLACE(j.series_ids, ' ', '') || ',' LIKE '%,' || l.series_id || ',%'
          )
        )
      ORDER BY l.is_default DESC, l.sort_order ASC, l.id ASC
    ''',
      [seriesId, sectionId, ...positions],
    );
  }


  Future<List<Map<String, dynamic>>> getCatalogItemRules({
    String? itemTable,
    int? itemId,
    int? seriesId,
    Iterable<String> roleKeys = const [],
    bool exactSeriesOnly = false,
    bool includeInactive = false,
  }) async {
    final myDb = await db;
    if (myDb == null) return [];
    await _ensureSeriesDesignTables(myDb);
    final where = <String>[];
    if (!includeInactive) where.add('is_active = 1');
    final args = <Object?>[];
    if (itemTable != null && itemTable.trim().isNotEmpty) {
      where.add('item_table = ?');
      args.add(itemTable.trim());
    }
    if (itemId != null) {
      where.add('item_id = ?');
      args.add(itemId);
    }
    if (seriesId != null) {
      if (exactSeriesOnly) {
        where.add('series_id = ?');
        args.add(seriesId);
      } else {
        // A series-specific rule always overrides the global rule for the same
        // catalogue item. This includes an explicit disabled rule: otherwise a
        // disabled local rule would silently fall back to the global one.
        where.add('''(
          series_id = ?
          OR (
            series_id IS NULL
            AND NOT EXISTS (
              SELECT 1
              FROM CatalogItemRules scoped_rule
              WHERE scoped_rule.item_table = CatalogItemRules.item_table
                AND scoped_rule.item_id = CatalogItemRules.item_id
                AND scoped_rule.series_id = ?
            )
          )
        )''');
        args.add(seriesId);
        args.add(seriesId);
      }
    }
    final keys = roleKeys
        .map((key) => key.trim())
        .where((key) => key.isNotEmpty)
        .toList();
    if (keys.isNotEmpty) {
      where.add('role_key IN (${List.filled(keys.length, '?').join(',')})');
      args.addAll(keys);
    }

    return myDb.query(
      'CatalogItemRules',
      where: where.join(' AND '),
      whereArgs: args,
      orderBy:
          'CASE WHEN series_id IS NULL THEN 1 ELSE 0 END, is_default DESC, sort_order ASC, id ASC',
    );
  }




  Future<List<Map<String, dynamic>>> getDesignSectionsForRoles(
    int seriesId,
    Iterable<String> roleKeys, {
    bool requireDialog = true,
    bool requireQuantity = false,
    bool requireVisible = true,
  }) async {
    return _getDesignSectionsForRoles(
      seriesId,
      roleKeys,
      requireDialog: requireDialog,
      requireQuantity: requireQuantity,
      requireVisible: requireVisible,
    );
  }





  /// Resolves profiles for a scoped selector dialog.  This keeps a manual
  /// replacement in the same opening/sliding catalogue scope as the drawing.
  Future<List<Map<String, dynamic>>> getDesignSectionsForScopedDialogRoles(
    int seriesId,
    Iterable<String> roleKeys, {
    required String usageScope,
    bool requireDialog = true,
    bool requireQuantity = false,
    bool requireVisible = true,
  }) async {
    return _getDesignSectionsForRoles(
      seriesId,
      roleKeys,
      requireDialog: requireDialog,
      requireQuantity: requireQuantity,
      requireVisible: requireVisible,
      usageScope: usageScope,
    );
  }







  /// Codes of the tempered-glass services priced from the catalogue.
  static const temperedGlassEdgeSmoothService = 'edge_smooth';
  static const temperedGlassEdgeExtraSmoothService = 'edge_extra_smooth';
  static const temperedGlassFrostingService = 'sablage';










  // ==========================================
  // Tempered Glass Systems, Kits & Rules
  // ==========================================




  // --- TemperedGlassSystems CRUD ---





  // --- TemperedGlassKits CRUD ---





  // --- TemperedGlassKitHoles CRUD ---



  // --- Components selected manually for each tempered-glass kit ---



  // --- TemperedGlassSystemRules CRUD ---






  // ═══════════════════════════════════════════════════════════════════════
  //  MATERIAL SALES – بيع المواد والمستلزمات
  // ═══════════════════════════════════════════════════════════════════════

























}
