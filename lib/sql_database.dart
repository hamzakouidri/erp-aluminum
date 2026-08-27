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
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:sqflite_common_ffi/sqflite_ffi.dart' as sqflite_common;
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';
import 'package:flutter_file_dialog/flutter_file_dialog.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:database_data/Commande/Systeme/model.dart';
import 'package:database_data/Commande/Systeme/model_serialization.dart';
import 'package:database_data/Commande/capture_image.dart';

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
  static Database? _db;
  static Future<Database>? _openingDb;
  static Future<void>? _databaseReopenTask;
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

  int createDistributedId() => _nextDistributedId();

  static double? _readStoredNumber(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString().trim() ?? '');
  }

  static String _canonicalKnownColorHex(String name, String fallback) {
    final normalized = name.toLowerCase().trim();
    if (normalized.contains('9007')) return '#8A939E';
    if (normalized.contains('desert') ||
        normalized.contains('ديزرت') ||
        normalized.contains('ديزيرت') ||
        normalized.contains('ديزر')) {
      return '#B68B55';
    }
    if (normalized.contains('champagne') ||
        normalized.contains('شامبان') ||
        normalized.contains('شمبان')) {
      return '#F7E7CE';
    }
    final isGold =
        normalized.contains('gold') ||
        normalized.contains('ذهبي') ||
        normalized.contains('ذهب') ||
        normalized.contains('doré') ||
        normalized.contains('dore') ||
        RegExp(r'(^|[\s/(_-])or($|[\s/)_-])').hasMatch(normalized);
    if (isGold) return '#D4AF37';
    return fallback;
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
    'SeriesTableConfig',
    'SeriesDesignConfig',
    'SeriesDesignRoles',
    'CatalogItemRules',
    'SectionJointLinks',
    'SeriesShutterRules',
    'Colors',
    'Accessories',
    'Joints',
    'Glass',
    'ShutterComponents',
    'ShutterColorPrices',
    'ShutterComponentColors',
    'ShutterSqmPrices',
    'ShutterBoxLimits',
    'CaissonTunnelPrices',
    'SeriesColorPrices',
    'SectionColorPrices',
    'AccessoryColorPrices',
    'ProfileColors',
    'ProfileColorConfig',
    'KitBundles',
    'KitBundleItems',
    'KitItemRanges',
    'KitItemVariants',
  ];

  static const List<String> workshopTables = [
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
    'MaterialRemnants',
    'MaterialScrap',
  ];

  static void resetDb() {
    _db = null;
    _openingDb = null;
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
      // Keep only language, theme, and deviceId
      final lang = prefs.getString('language');
      final theme = prefs.getString('themeMode');
      final deviceId = prefs.getString('device_id');

      await prefs.clear();

      if (lang != null) await prefs.setString('language', lang);
      if (theme != null) await prefs.setString('themeMode', theme);
      if (deviceId != null) await prefs.setString('device_id', deviceId);
      debugPrint(
        'SharedPreferences cleared successfully (settings preserved).',
      );
    } catch (e) {
      debugPrint('Error clearing SharedPreferences: $e');
    }
  }

  String get now => DateTime.now().toIso8601String();

  String get date => DateFormat('yyyy-MM-dd').format(DateTime.now());

  Future<String> _resolveDbPassword(String dbName) async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'db_cipher_$dbName';
    final stored = prefs.getString(key);
    if (stored != null && stored.isNotEmpty) return stored;

    final stable = 'aluminum_${dbName.hashCode.abs()}_v1';
    await prefs.setString(key, stable);
    return stable;
  }

  Future<Database> _openEncryptedDb(String path, String password) {
    if (kIsWeb ||
        (!kIsWeb &&
            (Platform.isWindows ||
                Platform.isLinux ||
                Platform.isMacOS ||
                Platform.environment.containsKey('FLUTTER_TEST')))) {
      return _dbFactory.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 64,
          onCreate: _onCreate,
          onUpgrade: _onUpgrade,
          onOpen: (db) async {
            await _onOpenLogic(db);
          },
        ),
      );
    }
    return openDatabase(
      path,
      version: 64,
      password: password,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
      onOpen: (db) async {
        await _onOpenLogic(db);
      },
    );
  }

  Future<void> _onOpenLogic(Database db) async {
    // Ensure old records have is_active = 1 and missing columns are added
    final tablesToFix = [
      'Profile',
      'Series',
      'Sections',
      'Colors',
      'Accessories',
      'Glass',
      'ShutterComponents',
      'Locations',
    ];
    try {
      await db.execute(
        "ALTER TABLE Glass ADD COLUMN height REAL NOT NULL DEFAULT 0.0;",
      );
    } catch (_) {}
    try {
      // Detail rows participate in cloud conflict resolution.  Older local
      // databases need this column before an edited order is saved.
      await db.execute(
        "ALTER TABLE Commandes_details ADD COLUMN updated_at TEXT;",
      );
    } catch (_) {}
    try {
      // A purchase invoice can contain several glass rows with the same
      // catalogue id when their measurements or glazing composition differ.
      await db.execute('DROP INDEX IF EXISTS idx_achat_items_unique;');
    } catch (_) {}

    // Migrations for Employees table
    try {
      await db.execute("ALTER TABLE Employees ADD COLUMN salary_type TEXT;");
    } catch (_) {}
    try {
      await db.execute("ALTER TABLE Employees ADD COLUMN base_salary REAL;");
    } catch (_) {}
    try {
      await db.execute("ALTER TABLE Employees ADD COLUMN phone TEXT;");
    } catch (_) {}
    try {
      await db.execute("ALTER TABLE Employees ADD COLUMN address TEXT;");
    } catch (_) {}
    try {
      await db.execute("ALTER TABLE Employees ADD COLUMN job_role TEXT;");
    } catch (_) {}

    // â”€â”€ Ø¬Ø¯ÙˆÙ„ Ø§Ù„Ø­Ø¶ÙˆØ± Ø§Ù„ÙŠÙˆÙ…ÙŠ â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    try {
      await db.execute('''
            CREATE TABLE IF NOT EXISTS WorkerAttendance (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              worker_uid TEXT NOT NULL,
              attendance_date TEXT NOT NULL,
              check_in TEXT,
              check_out TEXT,
              note TEXT,
              created_at TEXT NOT NULL DEFAULT (datetime('now')),
              UNIQUE(worker_uid, attendance_date)
            )
          ''');
    } catch (_) {}

    // â”€â”€ Ø¬Ø¯ÙˆÙ„ Ø§Ù„Ø£Ø¹Ù…Ø§Ù„ Ø§Ù„ÙŠÙˆÙ…ÙŠØ© (Ø¹Ù…Ù„ ÙŠÙˆÙ…ÙŠ) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    try {
      await db.execute('''
            CREATE TABLE IF NOT EXISTS WorkerDailyJobs (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              worker_uid TEXT NOT NULL,
              work_date TEXT NOT NULL,
              title TEXT NOT NULL DEFAULT 'Ø¹Ù…Ù„ ÙŠÙˆÙ…ÙŠ',
              note TEXT,
              price REAL NOT NULL DEFAULT 0.0,
              is_settled INTEGER NOT NULL DEFAULT 0,
              settled_at TEXT,
              settlement_week_id TEXT,
              created_at TEXT NOT NULL DEFAULT (datetime('now'))
            )
          ''');
    } catch (_) {}

    for (final table in tablesToFix) {
      try {
        await db.execute(
          "ALTER TABLE $table ADD COLUMN is_active INTEGER NOT NULL DEFAULT 1;",
        );
      } catch (_) {}
      try {
        await db.execute(
          "UPDATE $table SET is_active = 1 WHERE is_active IS NULL;",
        );
      } catch (_) {}
      try {
        await db.execute("ALTER TABLE $table ADD COLUMN image_path TEXT;");
      } catch (_) {}
    }

    try {
      await db.execute(
        "ALTER TABLE Sections ADD COLUMN couvre_joint_thickness REAL NOT NULL DEFAULT 0.0;",
      );
    } catch (_) {}
    try {
      await db.execute(
        "ALTER TABLE Sections ADD COLUMN allows_side_cover INTEGER NOT NULL DEFAULT 1;",
      );
    } catch (_) {}
    try {
      await db.execute(
        'ALTER TABLE Sections ADD COLUMN is_frame INTEGER NOT NULL DEFAULT 0;',
      );
    } catch (_) {}
    try {
      await db.execute(
        'ALTER TABLE Sections ADD COLUMN is_sash INTEGER NOT NULL DEFAULT 0;',
      );
    } catch (_) {}
    try {
      await db.execute(
        'ALTER TABLE Sections ADD COLUMN is_mullion INTEGER NOT NULL DEFAULT 0;',
      );
    } catch (_) {}

    await _ensureSeriesDesignTables(db);
    await _ensureClientCodeInfrastructure(db);
    await _ensureOrderCodeInfrastructure(db);
    await _ensureRemnantInventorySchema(db);
    await _ensureAdvancedKitCompatibilitySchema(db);
    await _ensureDecorPanelDesignSchema(db);
    await _ensurePaymentAllocationSchema(db);
    await _ensureSyncTombstoneInfrastructure(db);
    await _backfillClientCodes(db);
    await _backfillOrderCodes(db);

    // Automatically link section and profile images based on their codes
    try {
      final sections = await db.query('Sections');
      for (var sec in sections) {
        final id = sec['id'];
        final code = sec['code']?.toString() ?? '';
        if (code.isNotEmpty) {
          final expectedPath = 'assets/sections/$code.png';
          await db.update(
            'Sections',
            {'image_path': expectedPath},
            where: 'id = ?',
            whereArgs: [id],
          );
        }
      }
    } catch (_) {}

    try {
      final profiles = await db.query('Profile');
      for (var prof in profiles) {
        final id = prof['id'];
        final code = prof['code']?.toString() ?? '';
        if (code.isNotEmpty) {
          final expectedPath = 'assets/sections/$code.png';
          await db.update(
            'Profile',
            {'image_path': expectedPath},
            where: 'id = ?',
            whereArgs: [id],
          );
        }
      }
    } catch (_) {}

    try {
      await db.execute("ALTER TABLE Joints ADD COLUMN gasket_type TEXT;");
    } catch (_) {}
    try {
      await db.execute(
        "ALTER TABLE Client ADD COLUMN creation_platform TEXT NOT NULL DEFAULT 'unknown';",
      );
    } catch (_) {}

    // Treasury: Ø£Ø¹Ù…Ø¯Ø© Ø§Ù„Ø¬Ù‡Ø© ÙˆØ§Ù„Ø±ØµÙŠØ¯
    try {
      await db.execute("ALTER TABLE Treasury ADD COLUMN entity_type TEXT;");
    } catch (_) {}
    try {
      await db.execute("ALTER TABLE Treasury ADD COLUMN entity_id INTEGER;");
    } catch (_) {}
    try {
      await db.execute("ALTER TABLE Treasury ADD COLUMN phone TEXT;");
    } catch (_) {}
    try {
      await db.execute(
        "ALTER TABLE Treasury ADD COLUMN old_balance REAL DEFAULT 0.0;",
      );
    } catch (_) {}
    try {
      await db.execute(
        "ALTER TABLE Treasury ADD COLUMN new_balance REAL DEFAULT 0.0;",
      );
    } catch (_) {}

    try {
      await db.execute(
        "ALTER TABLE Commandes_details ADD COLUMN assigned_worker_uid TEXT;",
      );
    } catch (_) {}

    try {
      await db.execute(
        "ALTER TABLE Commandes_details ADD COLUMN worker_price REAL DEFAULT 0.0;",
      );
    } catch (_) {}

    try {
      await db.execute(
        "ALTER TABLE Commandes_details ADD COLUMN assigned_at TEXT;",
      );
    } catch (_) {}

    try {
      await db.execute(
        "ALTER TABLE Commandes_details ADD COLUMN worker_settled INTEGER DEFAULT 0;",
      );
    } catch (_) {}

    try {
      await db.execute(
        "ALTER TABLE Commandes_details ADD COLUMN worker_settled_at TEXT;",
      );
    } catch (_) {}

    try {
      await db.execute(
        "ALTER TABLE Commandes_details ADD COLUMN drawing_image_base64 TEXT;",
      );
    } catch (_) {}

    try {
      await db.execute(
        "ALTER TABLE Commandes_details ADD COLUMN glass_received_qty INTEGER DEFAULT 0;",
      );
    } catch (_) {}

    try {
      await db.execute(
        "ALTER TABLE Commandes_details ADD COLUMN is_glass_received INTEGER DEFAULT 0;",
      );
    } catch (_) {}

    try {
      await db.execute(
        "ALTER TABLE Commandes_details ADD COLUMN confirmed_mesures_json TEXT;",
      );
    } catch (_) {}

    try {
      await db.execute(
        "ALTER TABLE WorkerTransactions ADD COLUMN is_settled INTEGER DEFAULT 0;",
      );
    } catch (_) {}

    try {
      await db.execute(
        "ALTER TABLE WorkerTransactions ADD COLUMN settled_at TEXT;",
      );
    } catch (_) {}

    // Create Caisses table if not exists
    try {
      await db.execute('''
            CREATE TABLE IF NOT EXISTS Caisses (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              name TEXT NOT NULL UNIQUE
            )
          ''');
    } catch (_) {}

    // Create WorkerAllocations table if not exists
    try {
      await db.execute('''
            CREATE TABLE IF NOT EXISTS WorkerAllocations (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              commande_detail_id INTEGER NOT NULL,
              worker_uid TEXT NOT NULL,
              quantity INTEGER NOT NULL,
              worker_price REAL NOT NULL,
              assigned_at TEXT NOT NULL,
              is_settled INTEGER DEFAULT 0,
              settled_at TEXT,
              is_manufactured INTEGER DEFAULT 0,
              manufactured_at TEXT,
              is_glass_installed INTEGER DEFAULT 0,
              glass_installed_at TEXT,
              installation_worker_uid TEXT,
              installation_assigned_at TEXT,
              updated_at TEXT,
              FOREIGN KEY (commande_detail_id) REFERENCES Commandes_details(id) ON DELETE CASCADE
            )
          ''');
    } catch (_) {}

    try {
      await db.execute(
        "ALTER TABLE WorkerAllocations ADD COLUMN is_manufactured INTEGER DEFAULT 0;",
      );
    } catch (_) {}

    try {
      await db.execute(
        "ALTER TABLE WorkerAllocations ADD COLUMN manufactured_at TEXT;",
      );
    } catch (_) {}

    try {
      await db.execute(
        "ALTER TABLE WorkerAllocations ADD COLUMN is_glass_installed INTEGER DEFAULT 0;",
      );
    } catch (_) {}

    try {
      await db.execute(
        "ALTER TABLE WorkerAllocations ADD COLUMN glass_installed_at TEXT;",
      );
    } catch (_) {}

    try {
      await db.execute(
        "ALTER TABLE WorkerAllocations ADD COLUMN is_distributed INTEGER DEFAULT 0;",
      );
    } catch (_) {}

    try {
      await db.execute(
        "ALTER TABLE WorkerAllocations ADD COLUMN distributed_at TEXT;",
      );
    } catch (_) {}

    try {
      await db.execute(
        "ALTER TABLE WorkerAllocations ADD COLUMN is_installed INTEGER DEFAULT 0;",
      );
    } catch (_) {}

    try {
      await db.execute(
        "ALTER TABLE WorkerAllocations ADD COLUMN installed_at TEXT;",
      );
    } catch (_) {}

    try {
      await db.execute(
        "ALTER TABLE WorkerAllocations ADD COLUMN installation_worker_uid TEXT;",
      );
    } catch (_) {}

    try {
      await db.execute(
        "ALTER TABLE WorkerAllocations ADD COLUMN installation_assigned_at TEXT;",
      );
    } catch (_) {}

    try {
      await db.execute(
        "ALTER TABLE WorkerAllocations ADD COLUMN is_completed INTEGER DEFAULT 0;",
      );
    } catch (_) {}

    try {
      await db.execute(
        "ALTER TABLE WorkerAllocations ADD COLUMN completed_at TEXT;",
      );
    } catch (_) {}

    try {
      await db.execute(
        "ALTER TABLE WorkerAllocations ADD COLUMN has_reserve INTEGER DEFAULT 0;",
      );
    } catch (_) {}

    try {
      await db.execute(
        "ALTER TABLE WorkerAllocations ADD COLUMN reserve_notes TEXT;",
      );
    } catch (_) {}

    try {
      await db.execute(
        "ALTER TABLE WorkerAllocations ADD COLUMN reserve_at TEXT;",
      );
    } catch (_) {}

    try {
      await db.execute(
        "ALTER TABLE WorkerAllocations ADD COLUMN unit_index INTEGER;",
      );
    } catch (_) {}

    try {
      await db.execute(
        "ALTER TABLE WorkerAllocations ADD COLUMN unit_position TEXT;",
      );
    } catch (_) {}

    try {
      await db.execute(
        "ALTER TABLE WorkerAllocations ADD COLUMN unit_width INTEGER;",
      );
    } catch (_) {}

    try {
      await db.execute(
        "ALTER TABLE WorkerAllocations ADD COLUMN unit_height INTEGER;",
      );
    } catch (_) {}

    try {
      await db.execute(
        "ALTER TABLE WorkerAllocations ADD COLUMN updated_at TEXT;",
      );
    } catch (_) {}

    try {
      await db.execute('''
        UPDATE WorkerAllocations
        SET updated_at = COALESCE(
          NULLIF(transferred_at, ''),
          NULLIF(completed_at, ''),
          NULLIF(installed_at, ''),
          NULLIF(distributed_at, ''),
          NULLIF(glass_installed_at, ''),
          NULLIF(manufactured_at, ''),
          NULLIF(assigned_at, ''),
          datetime('now')
        )
        WHERE updated_at IS NULL OR TRIM(updated_at) = ''
      ''');
    } catch (_) {}

    // Auto purge settled data older than 6 months
    try {
      await db.execute('''
            DELETE FROM Commandes_details 
            WHERE worker_settled = 1 
              AND worker_settled_at IS NOT NULL 
              AND datetime(worker_settled_at) < datetime('now', '-6 months')
          ''');
    } catch (_) {}

    try {
      await db.execute('''
            DELETE FROM WorkerTransactions 
            WHERE is_settled = 1 
              AND settled_at IS NOT NULL 
              AND datetime(settled_at) < datetime('now', '-6 months')
          ''');
    } catch (_) {}

    try {
      await db.execute('''
            DELETE FROM WorkerAllocations 
            WHERE is_settled = 1 
              AND settled_at IS NOT NULL 
              AND datetime(settled_at) < datetime('now', '-6 months')
          ''');
    } catch (_) {}

    try {
      await db.execute(
        "ALTER TABLE Accessories ADD COLUMN is_selling_calculated INTEGER DEFAULT 0;",
      );
    } catch (_) {}

    try {
      await db.execute(
        "ALTER TABLE KitBundles ADD COLUMN is_selling_calculated INTEGER NOT NULL DEFAULT 1;",
      );
    } catch (_) {}

    try {
      await db.execute('''
            CREATE TABLE IF NOT EXISTS GlassColorPrices (
              glass_id INTEGER,
              color_name TEXT,
              price REAL NOT NULL,
              PRIMARY KEY (glass_id, color_name)
            )
          ''');
    } catch (_) {}

    try {
      // Migrate any existing 'Ø¨Ø¯ÙˆÙ† Ù„ÙˆÙ† / Ø§Ù„Ù„ÙˆÙ† Ø§Ù„Ø®Ø§Ù…' to 'Ø®Ø§Ù…'
      await db.update(
        'Colors',
        {'name': 'Ø®Ø§Ù…'},
        where: "name = ?",
        whereArgs: ['Ø¨Ø¯ÙˆÙ† Ù„ÙˆÙ† / Ø§Ù„Ù„ÙˆÙ† Ø§Ù„Ø®Ø§Ù…'],
      );
      await db.update(
        'GlassColorPrices',
        {'color_name': 'Ø®Ø§Ù…'},
        where: "color_name = ?",
        whereArgs: ['Ø¨Ø¯ÙˆÙ† Ù„ÙˆÙ† / Ø§Ù„Ù„ÙˆÙ† Ø§Ù„Ø®Ø§Ù…'],
      );
      try {
        await db.update(
          'Commandes_details',
          {'color': 'Ø®Ø§Ù…'},
          where: "color = ?",
          whereArgs: ['Ø¨Ø¯ÙˆÙ† Ù„ÙˆÙ† / Ø§Ù„Ù„ÙˆÙ† Ø§Ù„Ø®Ø§Ù…'],
        );
      } catch (_) {}
      try {
        await db.update(
          'Glass',
          {'color': 'Ø®Ø§Ù…'},
          where: "color = ?",
          whereArgs: ['Ø¨Ø¯ÙˆÙ† Ù„ÙˆÙ† / Ø§Ù„Ù„ÙˆÙ† Ø§Ù„Ø®Ø§Ù…'],
        );
      } catch (_) {}

      final check = await db.query(
        'Colors',
        where: "name = ?",
        whereArgs: ['Ø®Ø§Ù…'],
      );
      if (check.isEmpty) {
        await db.insert('Colors', {
          'name': 'Ø®Ø§Ù…',
          'hex_code': '#E0E0E0',
          'type': 'Global',
          'is_active': 1,
        });
      }
    } catch (_) {}

    try {
      await db.execute('''
            CREATE TABLE IF NOT EXISTS ShutterBoxLimits (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              box_size INTEGER NOT NULL,
              blade_id INTEGER NOT NULL,
              max_height REAL NOT NULL,
              FOREIGN KEY (blade_id) REFERENCES ShutterComponents(id) ON DELETE CASCADE
            )
          ''');
    } catch (_) {}

    try {
      await db.execute('''
            CREATE TABLE IF NOT EXISTS CaissonTunnelPrices (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              color_id INTEGER NOT NULL,
              profile_price_per_bar REAL NOT NULL DEFAULT 0.0,
              bottom_cover_price_per_bar REAL NOT NULL DEFAULT 0.0,
              price_per_meter REAL NOT NULL DEFAULT 0.0,
              UNIQUE(color_id)
            )
          ''');
    } catch (_) {}

    try {
      await db.execute('''
            CREATE TABLE IF NOT EXISTS SeriesTableConfig (
              series_id INTEGER PRIMARY KEY,
              allowed_section_types TEXT NOT NULL DEFAULT '',
              allowed_accessory_ids TEXT NOT NULL DEFAULT '',
              allowed_accessory_types TEXT NOT NULL DEFAULT '',
              excluded_accessory_ids TEXT NOT NULL DEFAULT '',
              sash_w_deduction_2 REAL DEFAULT 0.0,
              sash_w_deduction_3 REAL DEFAULT 0.0,
              sash_w_deduction_4 REAL DEFAULT 0.0,
              sash_overlap_val REAL DEFAULT 0.0,
              glass_w_deduction REAL DEFAULT 0.0,
              sliding_chicane_pieces_per_junction INTEGER DEFAULT 1,
              sliding_rail_clearance REAL DEFAULT 1.0,
              custom_formula_notes TEXT DEFAULT '',
              updated_at TEXT NOT NULL DEFAULT ''
            )
          ''');
    } catch (_) {}
    try {
      await db.execute(
        "ALTER TABLE SeriesTableConfig ADD COLUMN sash_w_deduction_2 REAL DEFAULT 0.0;",
      );
    } catch (_) {}
    try {
      await db.execute(
        "ALTER TABLE SeriesTableConfig ADD COLUMN sash_w_deduction_3 REAL DEFAULT 0.0;",
      );
    } catch (_) {}
    try {
      await db.execute(
        "ALTER TABLE SeriesTableConfig ADD COLUMN sash_w_deduction_4 REAL DEFAULT 0.0;",
      );
    } catch (_) {}
    try {
      await db.execute(
        "ALTER TABLE SeriesTableConfig ADD COLUMN sash_overlap_val REAL DEFAULT 0.0;",
      );
    } catch (_) {}
    try {
      await db.execute(
        "ALTER TABLE SeriesTableConfig ADD COLUMN glass_w_deduction REAL DEFAULT 0.0;",
      );
    } catch (_) {}
    try {
      await db.execute(
        'ALTER TABLE SeriesTableConfig ADD COLUMN sliding_chicane_pieces_per_junction INTEGER DEFAULT 1;',
      );
    } catch (_) {}
    try {
      await db.execute(
        'ALTER TABLE SeriesTableConfig ADD COLUMN sliding_rail_clearance REAL DEFAULT 1.0;',
      );
    } catch (_) {}
    try {
      await db.execute(
        "ALTER TABLE SeriesTableConfig ADD COLUMN custom_formula_notes TEXT DEFAULT '';",
      );
    } catch (_) {}

    // Ensure ShutterComponents has measurement, shutter_subtype, and bar_length_m columns and migrate existing records
    try {
      await db.execute(
        "ALTER TABLE ShutterComponents ADD COLUMN measurement TEXT DEFAULT '';",
      );
    } catch (_) {}
    try {
      await db.execute(
        "ALTER TABLE ShutterComponents ADD COLUMN motor_diameter TEXT DEFAULT '';",
      );
    } catch (_) {}
    try {
      await db.execute(
        'ALTER TABLE ShutterComponents ADD COLUMN motor_has_emergency_crank INTEGER NOT NULL DEFAULT 0;',
      );
    } catch (_) {}
    try {
      await db.execute(
        "ALTER TABLE ShutterComponents ADD COLUMN shutter_subtype TEXT NOT NULL DEFAULT 'normal';",
      );
    } catch (_) {}
    try {
      await db.execute(
        "ALTER TABLE ShutterComponents ADD COLUMN bar_length_m REAL NOT NULL DEFAULT 0.0;",
      );
    } catch (_) {}
    try {
      await db.execute(
        'ALTER TABLE ShutterComponents ADD COLUMN max_width_mm REAL NOT NULL DEFAULT 6000.0;',
      );
    } catch (_) {}
    try {
      await db.execute(
        "ALTER TABLE ShutterComponents ADD COLUMN cap_thickness REAL NOT NULL DEFAULT 0.0;",
      );
    } catch (_) {}
    try {
      await db.execute(
        "ALTER TABLE ShutterComponents ADD COLUMN weight_per_sqm REAL NOT NULL DEFAULT 0.0;",
      );
    } catch (_) {}
    try {
      await db.execute(
        "ALTER TABLE ShutterComponents ADD COLUMN track_measurement TEXT DEFAULT '';",
      );
    } catch (_) {}
    try {
      final rows = await db.rawQuery(
        "SELECT id, name, shutter_subtype, measurement FROM ShutterComponents",
      );
      for (var row in rows) {
        final id = row['id'];
        final name = row['name'].toString();
        final currentMeas = (row['measurement'] ?? '').toString();
        if (currentMeas.isEmpty) {
          final regExp = RegExp(r'\d+(\.\d+)?');
          final match = regExp.firstMatch(name);
          if (match != null) {
            String sizeDigits = match.group(0)!.replaceAll('.', '');
            await db.rawUpdate(
              "UPDATE ShutterComponents SET measurement = ? WHERE id = ?",
              [sizeDigits, id],
            );
          }
        }
        // Seed weight_per_sqm if it is 0.0 or null
        final subtype = (row['shutter_subtype'] ?? '').toString().toLowerCase();
        final nameLower = name.toLowerCase();
        double defaultWeight = 0.0;
        if (subtype == 'extruded' ||
            nameLower.contains('extruded') ||
            nameLower.contains('Ø¥ÙƒØ³ØªØ±ÙˆØ¯ÙŠ')) {
          defaultWeight = 12.0;
        } else if (nameLower.contains('55') ||
            currentMeas == '55' ||
            currentMeas == '550' ||
            nameLower.contains('Ù¥Ù¥')) {
          defaultWeight = 4.0;
        } else if (nameLower.contains('lame') ||
            nameLower.contains('Ø´Ø±ÙŠØ­') ||
            nameLower.contains('Ø´Ø±ÙŠØ­Ø©') ||
            nameLower.contains('final')) {
          defaultWeight = 3.0;
        }
        if (defaultWeight > 0.0) {
          await db.rawUpdate(
            "UPDATE ShutterComponents SET weight_per_sqm = ? WHERE id = ? AND (weight_per_sqm IS NULL OR weight_per_sqm = 0.0)",
            [defaultWeight, id],
          );
        }
      }
    } catch (_) {}

    // Ensure Glass has color column
    try {
      await db.execute("ALTER TABLE Glass ADD COLUMN color TEXT DEFAULT '';");
    } catch (_) {}

    // Ensure Achats has location_id
    try {
      await db.execute("ALTER TABLE Achats ADD COLUMN location_id INTEGER;");
    } catch (_) {}

    // Ensure Accessories has new columns
    try {
      await db.execute(
        "ALTER TABLE Accessories ADD COLUMN is_moteur_screw INTEGER DEFAULT 0;",
      );
    } catch (_) {}
    try {
      await db.execute(
        "ALTER TABLE Accessories ADD COLUMN is_caisson_screw INTEGER DEFAULT 0;",
      );
    } catch (_) {}
    try {
      await db.execute(
        "ALTER TABLE Accessories ADD COLUMN is_batmo_screw INTEGER DEFAULT 0;",
      );
    } catch (_) {}
    try {
      await db.execute(
        "ALTER TABLE Accessories ADD COLUMN is_bouchon_batmo_screw INTEGER DEFAULT 0;",
      );
    } catch (_) {}
    try {
      await db.execute(
        "ALTER TABLE Accessories ADD COLUMN is_renfort_screw INTEGER DEFAULT 0;",
      );
    } catch (_) {}
    try {
      await db.execute(
        "ALTER TABLE Accessories ADD COLUMN is_manivelle_screw INTEGER DEFAULT 0;",
      );
    } catch (_) {}
    try {
      await db.execute(
        "ALTER TABLE Accessories ADD COLUMN is_gache_simple INTEGER DEFAULT 0;",
      );
    } catch (_) {}
    try {
      await db.execute(
        "ALTER TABLE Accessories ADD COLUMN is_gache_double INTEGER DEFAULT 0;",
      );
    } catch (_) {}
    try {
      await db.execute(
        "ALTER TABLE Accessories ADD COLUMN is_gache_porte INTEGER DEFAULT 0;",
      );
    } catch (_) {}
    try {
      await db.execute(
        "ALTER TABLE Accessories ADD COLUMN is_lock_clef INTEGER DEFAULT 0;",
      );
    } catch (_) {}
    try {
      await db.execute(
        "ALTER TABLE Accessories ADD COLUMN is_lock_condamnation INTEGER DEFAULT 0;",
      );
    } catch (_) {}
    try {
      await db.execute(
        "ALTER TABLE Accessories ADD COLUMN is_assembly_screw INTEGER DEFAULT 0;",
      );
    } catch (_) {}
    try {
      await db.execute(
        "ALTER TABLE Accessories ADD COLUMN is_accessory_screw INTEGER DEFAULT 0;",
      );
    } catch (_) {}
    try {
      await db.execute(
        "ALTER TABLE Accessories ADD COLUMN is_installation_screw INTEGER DEFAULT 0;",
      );
    } catch (_) {}
    try {
      await db.execute(
        "ALTER TABLE Accessories ADD COLUMN is_kit_screw INTEGER DEFAULT 0;",
      );
    } catch (_) {}
    try {
      await db.execute(
        "ALTER TABLE Accessories ADD COLUMN is_tandem_screw INTEGER DEFAULT 0;",
      );
    } catch (_) {}

    // Ensure new tables exist in case of skipped version updates
    await db.execute('''
          CREATE TABLE IF NOT EXISTS Suppliers (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            phone TEXT,
            email TEXT,
            notes TEXT,
            latitude REAL,
            longitude REAL,
            created_at TEXT NOT NULL DEFAULT (datetime('now'))
          )
        ''');
    await db.execute('''
          CREATE TABLE IF NOT EXISTS Locations (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            type TEXT NOT NULL,
            is_active INTEGER NOT NULL DEFAULT 1,
            created_at TEXT NOT NULL DEFAULT (datetime('now'))
          )
        ''');
    await db.execute('''
          CREATE TABLE IF NOT EXISTS Achats (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            invoice_number TEXT NOT NULL,
            supplier_id INTEGER,
            location_id INTEGER,
            total_amount REAL NOT NULL,
            status TEXT NOT NULL DEFAULT 'Ù†Ø´Ø·Ø©',
            created_at TEXT NOT NULL DEFAULT (datetime('now')),
            updated_at TEXT NOT NULL DEFAULT (datetime('now')),
            FOREIGN KEY (supplier_id) REFERENCES Suppliers(id) ON DELETE SET NULL,
            FOREIGN KEY (location_id) REFERENCES Locations(id) ON DELETE SET NULL
          )
        ''');
    await db.execute('''
          CREATE TABLE IF NOT EXISTS Achat_Details (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            achat_id INTEGER NOT NULL,
            item_type TEXT NOT NULL,
            item_id INTEGER NOT NULL,
            color_id INTEGER,
            quantity REAL NOT NULL,
            unit_price REAL NOT NULL,
            total_price REAL NOT NULL,
            FOREIGN KEY (achat_id) REFERENCES Achats(id) ON DELETE CASCADE
          )
        ''');
    await _ensureShutterColorTables(db);
    // v38: Kit Bundles tables
    try {
      await db.execute('''
            CREATE TABLE IF NOT EXISTS KitBundles (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              name TEXT NOT NULL,
              description TEXT,
              per_leaf INTEGER NOT NULL DEFAULT 0,
              is_active INTEGER NOT NULL DEFAULT 1,
              is_selling_calculated INTEGER NOT NULL DEFAULT 1
            )
          ''');
    } catch (_) {}
    try {
      await db.execute('''
            CREATE TABLE IF NOT EXISTS KitBundleItems (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              kit_id INTEGER NOT NULL,
              family_id INTEGER,
              component_type TEXT NOT NULL,
              qty_mode TEXT NOT NULL DEFAULT 'fixed',
              dimension TEXT,
              base_qty REAL NOT NULL DEFAULT 1,
              unit TEXT NOT NULL DEFAULT 'Ù‚Ø·Ø¹Ø©',
              mechanism_scope TEXT NOT NULL DEFAULT 'all',
              sort_order INTEGER NOT NULL DEFAULT 0,
              FOREIGN KEY (kit_id) REFERENCES KitBundles(id) ON DELETE CASCADE
            )
          ''');
    } catch (_) {}
    try {
      await db.execute('''
            CREATE TABLE IF NOT EXISTS KitBundleFamilies (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              kit_id INTEGER NOT NULL,
              name TEXT NOT NULL,
              mechanism_scopes TEXT NOT NULL DEFAULT 'belt,crank,motor',
              blade_scope TEXT NOT NULL DEFAULT 'all',
              per_leaf INTEGER NOT NULL DEFAULT 0,
              sort_order INTEGER NOT NULL DEFAULT 0,
              is_active INTEGER NOT NULL DEFAULT 1,
              FOREIGN KEY (kit_id) REFERENCES KitBundles(id) ON DELETE CASCADE
            )
          ''');
    } catch (_) {}
    try {
      await db.execute('''
            CREATE TABLE IF NOT EXISTS KitItemRanges (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              item_id INTEGER NOT NULL,
              min_mm REAL NOT NULL,
              max_mm REAL NOT NULL,
              product_name TEXT NOT NULL,
              price REAL NOT NULL DEFAULT 0.0,
              qty REAL NOT NULL DEFAULT 1,
              compatibility_group INTEGER NOT NULL DEFAULT 0,
              family_id INTEGER,
              FOREIGN KEY (item_id) REFERENCES KitBundleItems(id) ON DELETE CASCADE
            )
          ''');
    } catch (_) {}
    try {
      await db.execute('''
            CREATE TABLE IF NOT EXISTS KitItemVariants (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              item_id INTEGER NOT NULL,
              ouvrant_type TEXT NOT NULL,
              product_name TEXT NOT NULL,
              price REAL NOT NULL DEFAULT 0.0,
              qty REAL NOT NULL DEFAULT 1,
              FOREIGN KEY (item_id) REFERENCES KitBundleItems(id) ON DELETE CASCADE
            )
          ''');
    } catch (_) {}
    try {
      await db.execute(
        "ALTER TABLE Commandes_details ADD COLUMN delivered_qty INTEGER DEFAULT 0;",
      );
    } catch (_) {}
    try {
      await db.execute('''
            CREATE TABLE IF NOT EXISTS Commandes_deliveries (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              id_commandes INTEGER NOT NULL,
              client_id INTEGER NOT NULL,
              delivery_date TEXT NOT NULL,
              items_json TEXT NOT NULL,
              total_amount REAL NOT NULL DEFAULT 0.0,
              FOREIGN KEY (id_commandes) REFERENCES Commandes(id) ON DELETE CASCADE
            )
          ''');
    } catch (_) {}
    try {
      await _cleanShutterComponentEncodings(db);
    } catch (_) {}

    // Translate Arabic accessory types to French in the Accessories table
    try {
      final translationMap = {
        'Ù…ÙØ§ØµÙ„': 'Paumelles',
        'Ù…Ù‚Ø¨Ø¶': 'PoignÃ©e FenÃªtre',
        'Ù‚ÙÙ„': 'Serrure',
        'Ù‚Ø§Ø´': 'GÃ¢che',
        'ÙÙŠØ±Ùˆ': 'Verrou',
        'Ø¥Ø³Ø¨Ø§Ù†ÙŠÙˆÙ„ÙŠØª': 'Espagnolette',
        'ÙƒØ§Ù†Ùˆ': 'Canon',
        'Ø³ÙŠØ³ØªÙ… Ø£Ùˆ Ø¨ÙŠ': 'System OB',
        'Ø¯ÙŠÙ…ÙŠ Ø³ÙŠØ³ØªÙ… Ø£Ùˆ Ø¨ÙŠ': 'Demi System OB',
        'ÙÙŠØ±Ùˆ Ø³Ù†ØªØ±Ø§Ù„': 'Verrou Central',
        'ÙƒØ§Ø´ Ø¨ÙˆØ±Øª': 'GÃ¢che Porte',
        'ÙƒØ§Ø´ ÙƒÙˆÙ„ÙŠØ³ÙˆÙ†': 'GÃ¢che Coulissante',
        'ÙƒØ±ÙŠÙ…ÙˆÙ†': 'CrÃ©mone',
        'Ø¨ÙˆØ´ÙˆÙ† Ø¨Ø§Ø±Ùƒ Ù„ÙˆØ²': 'Bouchon Parclose',
        'Ø§Ù„Ø¨Ø±Ø§ØºÙŠ': 'Visse',
      };
      for (var entry in translationMap.entries) {
        await db.rawUpdate(
          "UPDATE Accessories SET type = REPLACE(type, ?, ?) WHERE type LIKE ?;",
          [entry.key, entry.value, '%${entry.key}%'],
        );
      }
    } catch (_) {}

    // v39: Projects table & Commandes project_id
    try {
      await db.execute('''
            CREATE TABLE IF NOT EXISTS Projects (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              name TEXT NOT NULL,
              client_id INTEGER NOT NULL,
              description TEXT,
              created_at TEXT NOT NULL DEFAULT (datetime('now')),
              updated_at TEXT NOT NULL DEFAULT (datetime('now')),
              FOREIGN KEY (client_id) REFERENCES Client(id) ON DELETE CASCADE
            )
          ''');
    } catch (_) {}
    try {
      await db.execute("ALTER TABLE Commandes ADD COLUMN project_id INTEGER;");
    } catch (_) {}

    await _ensurePaymentAllocationSchema(db);
    // Install deletion tracking after every legacy table has been created.
    // This must happen before the user can delete anything in the UI.
    try {
      await _ensureSyncTombstoneInfrastructure(db);
    } catch (error) {
      debugPrint('Could not initialize deletion sync tracking: $error');
    }

    // Run background migration to generate base64 representation of drawings for existing details
    // so they can sync to the workers
    Future.delayed(const Duration(seconds: 2), () {
      backfillBase64Drawings();
    });
  }

  Future<void> backfillBase64Drawings() async {
    try {
      Database? myDb = await db;
      if (myDb == null) return;

      // 1. Query all details where drawing_image_base64 is null or empty
      final list = await myDb.rawQuery('''
        SELECT id, drawing_image_path, partitions_json 
        FROM Commandes_details 
        WHERE drawing_image_base64 IS NULL OR drawing_image_base64 = ''
      ''');

      if (list.isEmpty) return;

      for (var row in list) {
        final id = row['id'] as int;
        final path = row['drawing_image_path']?.toString() ?? '';

        String? base64Str;
        if (path.isNotEmpty) {
          try {
            final file = File(path);
            if (await file.exists()) {
              final bytes = await file.readAsBytes();
              base64Str = base64Encode(bytes);
            }
          } catch (_) {}
        }

        // If path didn't exist but we have partitions_json, try to draw it dynamically
        if (base64Str == null) {
          final partitionsJson = row['partitions_json'];
          if (partitionsJson != null && partitionsJson.toString().isNotEmpty) {
            try {
              Map<String, dynamic> modelMap = {};
              final str = partitionsJson.toString().trim();
              if (str.length >= 5) {
                if (str.startsWith('{')) {
                  modelMap = jsonDecode(str) as Map<String, dynamic>;
                }
              }
              if (modelMap.isNotEmpty) {
                final model = WindowModel(db: this);
                await applyWindowModelAndLoadCatalog(model, modelMap);
                final bytes = await captureWindowImage(model);
                if (bytes.isNotEmpty) {
                  base64Str = base64Encode(bytes);
                }
              }
            } catch (_) {}
          }
        }

        if (base64Str != null && base64Str.isNotEmpty) {
          await myDb.update(
            'Commandes_details',
            {'drawing_image_base64': base64Str},
            where: 'id = ?',
            whereArgs: [id],
          );
        }
      }
      CloudSyncService().notifyChange();
    } catch (e) {
      debugPrint('Error backfilling base64 drawings: $e');
    }
  }

  String _cleanEncoding(String val) {
    if (val.isEmpty) return val;
    String cleaned = val;

    // Replace CP437/CP1252/UTF-8 mojibake
    cleaned = cleaned
        .replaceAll('â”œâŒ', 'Ã©')
        .replaceAll('â”œÂ¿', 'Ã¨')
        .replaceAll('ÃƒÂ©', 'Ã©')
        .replaceAll('ÃƒÂ¨', 'Ã¨')
        // Replace corrupted Arabic names
        .replaceAll(
          'â•ªâ”‚â•ªÂ¬â•ªÂºâ•ªâ–’ â•ªÃºâ•ªÂ¿â”˜Ã¨â•ªâ•¢',
          'Ø³ØªØ§Ø± Ø£Ø¨ÙŠØ¶',
        )
        .replaceAll(
          'â•ªâ”‚â•ªÂ¬â•ªÂºâ•ªâ–’ â•ªÂ«â•ªâ”¤â•ªÂ¿â”˜Ã¨',
          'Ø³ØªØ§Ø± Ø®Ø´Ø¨ÙŠ',
        )
        .replaceAll(
          'â•ªâ”‚â•ªÂ¬â•ªÂºâ•ªâ–’ â•ªÂ¿â”˜Ã¥â”˜Ã¨/â•ªÂ«â•ªâ”¤â•ªÂ¿â”˜Ã¨',
          'Ø³ØªØ§Ø± Ø¨Ù†ÙŠ/Ø®Ø´Ø¨ÙŠ',
        )
        .replaceAll(
          'â•ªâ”‚â•ªÂ¬â•ªÂºâ•ªâ–’ â•ªÂ¿â”˜Ã¥â”˜Ã¨ / â•ªÂ«â•ªâ”¤â•ªÂ¿â”˜Ã¨',
          'Ø³ØªØ§Ø± Ø¨Ù†ÙŠ/Ø®Ø´Ø¨ÙŠ',
        )
        .replaceAll('Injecte', 'InjectÃ©e')
        .replaceAll('Extrude', 'ExtrudÃ©e')
        .replaceAll('Glissire', 'GlissiÃ¨re');

    // Ensure common variations are fully normalized
    if (cleaned.toLowerCase() == 'lame injectee' ||
        cleaned.toLowerCase() == 'lame injectÃ©e') {
      cleaned = 'Lame InjectÃ©e';
    }
    if (cleaned.toLowerCase() == 'lame extrudee' ||
        cleaned.toLowerCase() == 'lame extrudÃ©e') {
      cleaned = 'Lame ExtrudÃ©e';
    }
    if (cleaned.toLowerCase() == 'glissiere 25' ||
        cleaned.toLowerCase() == 'glissiÃ¨re 25') {
      cleaned = 'GlissiÃ¨re 25';
    }
    if (cleaned.toLowerCase() == 'glissiere 120' ||
        cleaned.toLowerCase() == 'glissiÃ¨re 120') {
      cleaned = 'GlissiÃ¨re 120';
    }
    if (cleaned.toLowerCase() == 'glissiere 100' ||
        cleaned.toLowerCase() == 'glissiÃ¨re 100') {
      cleaned = 'GlissiÃ¨re 100';
    }
    return cleaned;
  }

  Future<void> _cleanShutterComponentEncodings(DatabaseExecutor db) async {
    try {
      // 1. Clean ShutterComponents
      final comps = await db.query('ShutterComponents');
      for (final row in comps) {
        final id = row['id'] as int;
        final name = row['name']?.toString() ?? '';
        final type = row['component_type']?.toString() ?? '';

        final cleanedName = _cleanEncoding(name);
        final cleanedType = _cleanEncoding(type);

        if (cleanedName != name || cleanedType != type) {
          await db.update(
            'ShutterComponents',
            {'name': cleanedName, 'component_type': cleanedType},
            where: 'id = ?',
            whereArgs: [id],
          );

          // Also update any ShutterSqmPrices references using the old name
          await db.update(
            'ShutterSqmPrices',
            {'blade_type': cleanedName},
            where: 'blade_type = ?',
            whereArgs: [name],
          );
        }
      }

      // 2. Clean Accessories
      final accs = await db.query('Accessories');
      for (final row in accs) {
        final id = row['id'] as int;
        final name = row['name']?.toString() ?? '';
        final type = row['type']?.toString() ?? '';

        final cleanedName = _cleanEncoding(name);
        final cleanedType = _cleanEncoding(type);

        if (cleanedName != name || cleanedType != type) {
          await db.update(
            'Accessories',
            {'name': cleanedName, 'type': cleanedType},
            where: 'id = ?',
            whereArgs: [id],
          );
        }
      }

      // 3. Clean ShutterSqmPrices
      final sqmPrices = await db.query('ShutterSqmPrices');
      for (final row in sqmPrices) {
        final id = row['id'] as int;
        final bladeType = row['blade_type']?.toString() ?? '';
        final cleanedBlade = _cleanEncoding(bladeType);
        if (cleanedBlade != bladeType) {
          await db.update(
            'ShutterSqmPrices',
            {'blade_type': cleanedBlade},
            where: 'id = ?',
            whereArgs: [id],
          );
        }
      }
    } catch (_) {}
  }

  Future<void> _ensureShutterColorTables(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS ShutterColorPrices (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        shutter_component_id INTEGER NOT NULL,
        color_id INTEGER NOT NULL,
        price REAL NOT NULL DEFAULT 0.0,
        UNIQUE(shutter_component_id, color_id)
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS ShutterComponentColors (
        shutter_component_id INTEGER NOT NULL,
        color_id INTEGER NOT NULL,
        PRIMARY KEY (shutter_component_id, color_id)
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS ShutterSqmPrices (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        blade_type TEXT NOT NULL,
        color_id INTEGER NOT NULL,
        price_per_sqm REAL NOT NULL DEFAULT 0.0,
        UNIQUE(blade_type, color_id)
      )
    ''');
  }

  /// Stores the administrator-defined blueprint used by the single Design
  /// screen.  The renderer and the material calculator read the same rows;
  /// a series is therefore identified by component roles, never by a name or
  /// by a hard-coded section number.
  Future<void> _ensureSeriesDesignTables(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS SeriesDesignConfig (
        series_id INTEGER PRIMARY KEY,
        supports_shutter INTEGER NOT NULL DEFAULT 0,
        allows_divisions INTEGER NOT NULL DEFAULT 1,
        allowed_contents_json TEXT NOT NULL DEFAULT '[]',
        updated_at TEXT NOT NULL DEFAULT ''
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS SeriesDesignRoles (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        series_id INTEGER NOT NULL,
        role_key TEXT NOT NULL,
        section_id INTEGER NOT NULL,
        usage_scope TEXT NOT NULL DEFAULT 'auto',
        show_when_glass TEXT NOT NULL DEFAULT 'any',
        integrated_side_cover INTEGER NOT NULL DEFAULT 0,
        allows_side_cover INTEGER NOT NULL DEFAULT 1,
        allowed_with_shutter INTEGER NOT NULL DEFAULT 1,
        show_in_drawing INTEGER NOT NULL DEFAULT 1,
        show_in_quantity INTEGER NOT NULL DEFAULT 1,
        show_in_dialog INTEGER NOT NULL DEFAULT 1,
        width_adjust_mm REAL NOT NULL DEFAULT 0.0,
        height_adjust_mm REAL NOT NULL DEFAULT 0.0,
        formula_note TEXT NOT NULL DEFAULT '',
        is_required INTEGER NOT NULL DEFAULT 0,
        is_default INTEGER NOT NULL DEFAULT 0,
        is_visible INTEGER NOT NULL DEFAULT 1,
        sort_order INTEGER NOT NULL DEFAULT 0,
        updated_at TEXT NOT NULL DEFAULT '',
        UNIQUE(series_id, role_key, section_id)
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS SectionJointLinks (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        series_id INTEGER NOT NULL,
        section_id INTEGER NOT NULL,
        joint_id INTEGER,
        gasket_type TEXT NOT NULL DEFAULT '',
        position_key TEXT NOT NULL DEFAULT 'sash_inner',
        is_default INTEGER NOT NULL DEFAULT 1,
        sort_order INTEGER NOT NULL DEFAULT 0,
        updated_at TEXT NOT NULL DEFAULT '',
        UNIQUE(series_id, section_id, position_key, gasket_type)
      )
    ''');
    try {
      await db.execute(
        "ALTER TABLE SectionJointLinks ADD COLUMN gasket_type TEXT NOT NULL DEFAULT '';",
      );
    } catch (_) {}
    await db.execute('''
      CREATE TABLE IF NOT EXISTS SeriesShutterRules (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        series_id INTEGER NOT NULL,
        component_id INTEGER NOT NULL,
        component_role TEXT NOT NULL,
        selection_mode TEXT NOT NULL DEFAULT 'always',
        min_width_mm REAL,
        max_width_mm REAL,
        min_height_mm REAL,
        max_height_mm REAL,
        is_default INTEGER NOT NULL DEFAULT 0,
        is_active INTEGER NOT NULL DEFAULT 1,
        sort_order INTEGER NOT NULL DEFAULT 0,
        updated_at TEXT NOT NULL DEFAULT '',
        UNIQUE(series_id, component_id, component_role, selection_mode)
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS CatalogItemRules (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        item_table TEXT NOT NULL,
        item_id INTEGER NOT NULL,
        series_id INTEGER,
        role_key TEXT NOT NULL,
        usage_scope TEXT NOT NULL DEFAULT 'global',
        show_when_glass TEXT NOT NULL DEFAULT 'any',
        selection_mode TEXT NOT NULL DEFAULT 'always',
        integrated_side_cover INTEGER NOT NULL DEFAULT 0,
        allows_side_cover INTEGER NOT NULL DEFAULT 1,
        allowed_with_shutter INTEGER NOT NULL DEFAULT 1,
        show_in_drawing INTEGER NOT NULL DEFAULT 1,
        show_in_quantity INTEGER NOT NULL DEFAULT 1,
        show_in_dialog INTEGER NOT NULL DEFAULT 1,
        width_adjust_mm REAL NOT NULL DEFAULT 0.0,
        height_adjust_mm REAL NOT NULL DEFAULT 0.0,
        formula_note TEXT NOT NULL DEFAULT '',
        is_default INTEGER NOT NULL DEFAULT 0,
        is_active INTEGER NOT NULL DEFAULT 1,
        sort_order INTEGER NOT NULL DEFAULT 0,
        updated_at TEXT NOT NULL DEFAULT '',
        UNIQUE(item_table, item_id, series_id, role_key)
      )
    ''');
    for (final statement in const [
      "ALTER TABLE SeriesDesignRoles ADD COLUMN usage_scope TEXT NOT NULL DEFAULT 'auto';",
      "ALTER TABLE SeriesDesignRoles ADD COLUMN show_when_glass TEXT NOT NULL DEFAULT 'any';",
      'ALTER TABLE SeriesDesignRoles ADD COLUMN integrated_side_cover INTEGER NOT NULL DEFAULT 0;',
      'ALTER TABLE SeriesDesignRoles ADD COLUMN allows_side_cover INTEGER NOT NULL DEFAULT 1;',
      'ALTER TABLE SeriesDesignRoles ADD COLUMN allowed_with_shutter INTEGER NOT NULL DEFAULT 1;',
      'ALTER TABLE SeriesDesignRoles ADD COLUMN show_in_drawing INTEGER NOT NULL DEFAULT 1;',
      'ALTER TABLE SeriesDesignRoles ADD COLUMN show_in_quantity INTEGER NOT NULL DEFAULT 1;',
      'ALTER TABLE SeriesDesignRoles ADD COLUMN show_in_dialog INTEGER NOT NULL DEFAULT 1;',
      'ALTER TABLE SeriesDesignRoles ADD COLUMN width_adjust_mm REAL NOT NULL DEFAULT 0.0;',
      'ALTER TABLE SeriesDesignRoles ADD COLUMN height_adjust_mm REAL NOT NULL DEFAULT 0.0;',
      "ALTER TABLE SeriesDesignRoles ADD COLUMN formula_note TEXT NOT NULL DEFAULT '';",
    ]) {
      try {
        await db.execute(statement);
      } catch (_) {}
    }
    for (final statement in const [
      "ALTER TABLE CatalogItemRules ADD COLUMN usage_scope TEXT NOT NULL DEFAULT 'global';",
      "ALTER TABLE CatalogItemRules ADD COLUMN show_when_glass TEXT NOT NULL DEFAULT 'any';",
      "ALTER TABLE CatalogItemRules ADD COLUMN selection_mode TEXT NOT NULL DEFAULT 'always';",
      'ALTER TABLE CatalogItemRules ADD COLUMN integrated_side_cover INTEGER NOT NULL DEFAULT 0;',
      'ALTER TABLE CatalogItemRules ADD COLUMN allows_side_cover INTEGER NOT NULL DEFAULT 1;',
      'ALTER TABLE CatalogItemRules ADD COLUMN allowed_with_shutter INTEGER NOT NULL DEFAULT 1;',
      'ALTER TABLE CatalogItemRules ADD COLUMN show_in_drawing INTEGER NOT NULL DEFAULT 1;',
      'ALTER TABLE CatalogItemRules ADD COLUMN show_in_quantity INTEGER NOT NULL DEFAULT 1;',
      'ALTER TABLE CatalogItemRules ADD COLUMN show_in_dialog INTEGER NOT NULL DEFAULT 1;',
      'ALTER TABLE CatalogItemRules ADD COLUMN width_adjust_mm REAL NOT NULL DEFAULT 0.0;',
      'ALTER TABLE CatalogItemRules ADD COLUMN height_adjust_mm REAL NOT NULL DEFAULT 0.0;',
      "ALTER TABLE CatalogItemRules ADD COLUMN formula_note TEXT NOT NULL DEFAULT '';",
      'ALTER TABLE CatalogItemRules ADD COLUMN is_default INTEGER NOT NULL DEFAULT 0;',
      'ALTER TABLE CatalogItemRules ADD COLUMN is_active INTEGER NOT NULL DEFAULT 1;',
      'ALTER TABLE CatalogItemRules ADD COLUMN sort_order INTEGER NOT NULL DEFAULT 0;',
      "ALTER TABLE CatalogItemRules ADD COLUMN updated_at TEXT NOT NULL DEFAULT '';",
    ]) {
      try {
        await db.execute(statement);
      } catch (_) {}
    }
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_design_roles_series ON SeriesDesignRoles(series_id, role_key);',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_section_joint_links_series ON SectionJointLinks(series_id, section_id, position_key);',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_section_joint_links_joint ON SectionJointLinks(joint_id);',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_design_shutter_series ON SeriesShutterRules(series_id, component_role);',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_catalog_item_rules_lookup ON CatalogItemRules(item_table, item_id, series_id, role_key);',
    );
  }

  Future<void> _ensureAdvancedKitCompatibilitySchema(
    DatabaseExecutor db,
  ) async {
    for (final statement in const [
      "ALTER TABLE KitBundleItems ADD COLUMN mechanism_scopes TEXT NOT NULL DEFAULT 'belt,crank,motor';",
      "ALTER TABLE KitBundleItems ADD COLUMN blade_scope TEXT NOT NULL DEFAULT 'all';",
      'ALTER TABLE KitBundleItems ADD COLUMN family_id INTEGER;',
      'ALTER TABLE KitItemRanges ADD COLUMN shutter_component_id INTEGER;',
      'ALTER TABLE KitItemRanges ADD COLUMN family_id INTEGER;',
      "ALTER TABLE KitBundles ADD COLUMN compatibility_group_1_name TEXT NOT NULL DEFAULT 'Console Quissonnel Standard';",
      "ALTER TABLE KitBundles ADD COLUMN compatibility_group_2_name TEXT NOT NULL DEFAULT 'Console Quissonnel Spécial';",
    ]) {
      try {
        await db.execute(statement);
      } catch (_) {}
    }
    try {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS KitBundleFamilies (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          kit_id INTEGER NOT NULL,
          name TEXT NOT NULL,
          mechanism_scopes TEXT NOT NULL DEFAULT 'belt,crank,motor',
          blade_scope TEXT NOT NULL DEFAULT 'all',
          per_leaf INTEGER NOT NULL DEFAULT 0,
          sort_order INTEGER NOT NULL DEFAULT 0,
          is_active INTEGER NOT NULL DEFAULT 1,
          FOREIGN KEY (kit_id) REFERENCES KitBundles(id) ON DELETE CASCADE
        )
      ''');
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_kit_bundle_families_kit ON KitBundleFamilies(kit_id, sort_order, id);',
      );
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_kit_bundle_items_family ON KitBundleItems(family_id, sort_order, id);',
      );
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_kit_item_ranges_family ON KitItemRanges(family_id, item_id);',
      );
    } catch (_) {}

    // Preserve old single-scope choices while moving to multi-select scopes.
    try {
      await db.execute('''
        UPDATE KitBundleItems
        SET mechanism_scopes = CASE LOWER(TRIM(mechanism_scope))
          WHEN 'belt' THEN 'belt'
          WHEN 'crank' THEN 'crank'
          WHEN 'motor' THEN 'motor'
          ELSE 'belt,crank,motor'
        END
        WHERE mechanism_scopes IS NULL
           OR TRIM(mechanism_scopes) = ''
           OR mechanism_scopes = 'belt,crank,motor'
      ''');
    } catch (_) {}
    try {
      await db.execute('''
        UPDATE KitBundles
        SET compatibility_group_1_name = 'Console Quissonnel Standard',
            compatibility_group_2_name = 'Console Quissonnel Spécial'
        WHERE UPPER(TRIM(description)) = 'CT'
          AND (
            compatibility_group_1_name IS NULL OR
            TRIM(compatibility_group_1_name) = '' OR
            compatibility_group_1_name = 'المجموعة 1'
          )
      ''');
    } catch (_) {}
    try {
      await db.execute('''
        UPDATE KitBundleItems
        SET blade_scope = 'extruded'
        WHERE LOWER(TRIM(blade_scope)) = 'x3d'
      ''');
    } catch (_) {}
  }

  Future<void> _ensureDecorPanelDesignSchema(DatabaseExecutor db) async {
    // Older workshop databases already contain the Glass table but predate
    // the width field used by bardage and panneau décor.  Without this repair
    // every insert/update carrying a décor size fails with
    // "no such column: visible_width" and the product dialog appears not to
    // save anything.
    try {
      await db.execute(
        'ALTER TABLE Glass ADD COLUMN visible_width REAL DEFAULT NULL;',
      );
    } catch (_) {}
    try {
      await db.execute(
        "ALTER TABLE Glass ADD COLUMN decor_design_code TEXT NOT NULL DEFAULT '';",
      );
    } catch (_) {}
  }

  /// These roles are independent of the legacy `type` field: one profile can
  /// be offered as a frame, sash and/or mullion.  Keep the schema repair here
  /// too because users can edit the catalogue in a session that started before
  /// the normal database-open migration ran.
  Future<void> _ensureSectionDrawingRoleColumns(
    DatabaseExecutor executor,
  ) async {
    try {
      await executor.execute(
        'ALTER TABLE Sections ADD COLUMN allows_side_cover INTEGER NOT NULL DEFAULT 1;',
      );
    } catch (_) {}
    try {
      await executor.execute(
        'ALTER TABLE Sections ADD COLUMN is_frame INTEGER NOT NULL DEFAULT 0;',
      );
    } catch (_) {}
    try {
      await executor.execute(
        'ALTER TABLE Sections ADD COLUMN is_sash INTEGER NOT NULL DEFAULT 0;',
      );
    } catch (_) {}
    try {
      await executor.execute(
        'ALTER TABLE Sections ADD COLUMN is_mullion INTEGER NOT NULL DEFAULT 0;',
      );
    } catch (_) {}
  }

  Future<void> _ensureShutterComponentSeeds(DatabaseExecutor db) async {
    final List<Map<String, dynamic>> itemsToSeed = [
      {
        'name': 'Ø§Ù„Ù…Ø­Ø±Ùƒ (Moteur)',
        'component_type': 'Moteur',
        'price': 0.0,
        'unit': 'pcs',
        'is_active': 1,
      },
      {
        'name': 'Ø§Ù„Ù…Ø§Ù†ÙŠÙØ§Ù„ (Manivelle)',
        'component_type': 'Manivelle',
        'price': 0.0,
        'unit': 'pcs',
        'is_active': 1,
      },
      {
        'name': 'Ø§Ù„Ø³ÙƒÙƒ (Coulisses)',
        'component_type': 'Glissiere',
        'price': 0.0,
        'unit': 'pcs',
        'is_active': 1,
      },
    ];

    for (final item in itemsToSeed) {
      final name = item['name'] as String;
      final existing = await db.query(
        'ShutterComponents',
        where: 'name = ?',
        whereArgs: [name],
      );
      if (existing.isEmpty) {
        await db.insert('ShutterComponents', item);
      }
    }
  }

  Future<Database?> get db async {
    final current = _db;
    if (current != null) return current;

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
    _db = await task;
    return _db;
  }

  Future<Database> initDb() async {
    String dbName = 'test.db';

    String path;
    if (kIsWeb) {
      path = dbName;
    } else {
      String dataPath = await _getWritableDatabasesPath();
      path = join(dataPath, dbName);
    }
    final dbPassword = await _resolveDbPassword(dbName);

    if (!kIsWeb) {
      try {
        final dataPath = await _getWritableDatabasesPath();
        final directory = Directory(dataPath);
        final activeFile = File(path);
        // A file marked as corrupt must never replace a newly created healthy
        // database. Only consider an old backup when the active file is
        // genuinely missing, and verify it with SQLite quick_check first.
        if (!await activeFile.exists() && await directory.exists()) {
          final files = directory.listSync();
          final corruptFiles =
              files.where((f) => f.path.contains('$dbName.corrupt_')).toList()
                ..sort((a, b) => b.path.compareTo(a.path));

          for (var corruptFile in corruptFiles) {
            try {
              final testDb = await _openEncryptedDb(
                corruptFile.path,
                dbPassword,
              );
              final check = await testDb.rawQuery('PRAGMA quick_check');
              final isHealthy =
                  check.isNotEmpty &&
                  check.every(
                    (row) => row.values.any(
                      (value) => value.toString().toLowerCase() == 'ok',
                    ),
                  );
              await testDb.close();
              if (!isHealthy) continue;

              await File(corruptFile.path).rename(path);
              break;
            } catch (_) {}
          }
        }
      } catch (_) {}
    }

    try {
      return await _openEncryptedDb(path, dbPassword);
    } catch (e) {
      Text('Failed to open encrypted database: $e');
      if (!kIsWeb && await _dbFactory.databaseExists(path)) {
        try {
          final file = File(path);
          final backupPath =
              '$path.corrupt_${DateTime.now().millisecondsSinceEpoch}';
          await file.rename(backupPath);
          Text('Renamed unreadable database to $backupPath');
        } catch (renameError) {
          Text('Could not rename corrupt database: $renameError');
        }
        resetDb();
        return await _openEncryptedDb(path, dbPassword);
      }
      rethrow;
    }
  }

  static bool isCorruptionError(Object error) {
    final text = error.toString().toLowerCase();
    return text.contains('database image malformed') ||
        text.contains('database disk image is malformed') ||
        text.contains('sqlite_corrupt') ||
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

  Future<void> reopenAfterDatabaseMoved() {
    final activeTask = _databaseReopenTask;
    if (activeTask != null) return activeTask;

    late final Future<void> task;
    task = _reopenAfterDatabaseMoved().whenComplete(() {
      if (identical(_databaseReopenTask, task)) {
        _databaseReopenTask = null;
      }
    });
    _databaseReopenTask = task;
    return task;
  }

  Future<void> _reopenAfterDatabaseMoved() async {
    final staleDb = _db;
    _db = null;
    _openingDb = null;
    if (staleDb != null) {
      try {
        await staleDb.close();
      } catch (_) {}
    }
    _db = await initDb();
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

  Future<bool> isDatabaseHealthy() async {
    try {
      final currentDb = await db;
      if (currentDb == null) return false;
      final check = await currentDb.rawQuery('PRAGMA quick_check');
      return check.isNotEmpty &&
          check.every(
            (row) => row.values.any(
              (value) => value.toString().toLowerCase() == 'ok',
            ),
          );
    } catch (error) {
      // Do not label a moved open handle as corruption. The sync layer can
      // safely close and reopen it, whereas treating it as corruption would
      // unnecessarily discard a perfectly valid database file.
      if (isDatabaseMovedError(error)) rethrow;
      return false;
    }
  }

  /// Preserves the unreadable SQLite file for diagnostics, creates a clean
  /// database with the same encryption key, and keeps login/workshop settings.
  Future<String?> recreateCorruptedDatabase() async {
    const dbName = 'test.db';
    final path = await getDatabaseFilePath();
    String? diagnosticBackupPath;

    final currentDb = _db;
    _db = null;
    if (currentDb != null) {
      try {
        await currentDb.close();
      } catch (_) {}
    }

    if (!kIsWeb) {
      final activeFile = File(path);
      if (await activeFile.exists()) {
        diagnosticBackupPath =
            '$path.corrupt_${DateTime.now().millisecondsSinceEpoch}';
        try {
          await activeFile.copy(diagnosticBackupPath);
        } catch (error) {
          debugPrint('Could not preserve corrupt database copy: $error');
          diagnosticBackupPath = null;
        }
      }
    }

    // databaseFactory.deleteDatabase also removes SQLite WAL/SHM sidecar
    // files, which can otherwise re-corrupt the newly created database.
    await _dbFactory.deleteDatabase(path);
    final password = await _resolveDbPassword(dbName);
    _db = await _openEncryptedDb(path, password);
    return diagnosticBackupPath;
  }

  void _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('''
        CREATE TABLE Series (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          profile_id INTEGER NOT NULL,
          name TEXT NOT NULL,
          type TEXT NOT NULL,
          price_per_meter REAL NOT NULL DEFAULT 0.0,
          FOREIGN KEY (profile_id) REFERENCES Profile(id) ON DELETE CASCADE
        )
      ''');
      await db.execute('''
        CREATE TABLE Sections (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          series_id INTEGER NOT NULL,
          code TEXT NOT NULL,
          name TEXT NOT NULL,
          type TEXT NOT NULL,
          thickness REAL NOT NULL,
          glass_deduction REAL NOT NULL,
          weight_per_meter REAL NOT NULL,
          couvre_joint_width REAL NOT NULL DEFAULT 0.0,
          bar_length REAL NOT NULL DEFAULT 5.8,
          FOREIGN KEY (series_id) REFERENCES Series(id) ON DELETE CASCADE
        )
      ''');
    }
    if (oldVersion < 3) {
      await db.execute('''
        CREATE TABLE Achats (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          invoice_number TEXT NOT NULL,
          supplier_name TEXT NOT NULL,
          status TEXT NOT NULL DEFAULT 'Active',
          total REAL NOT NULL DEFAULT 0.0,
          created_at TEXT NOT NULL DEFAULT (datetime('now')),
          updated_at TEXT NOT NULL DEFAULT (datetime('now'))
        )
      ''');
    }
    if (oldVersion < 4) {
      await db.execute('ALTER TABLE Achats ADD COLUMN image_path TEXT;');
      await db.execute('ALTER TABLE Achats ADD COLUMN pdf_path TEXT;');
      await db.execute('''
        CREATE TABLE Achat_items (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          achat_id INTEGER NOT NULL,
          item_code TEXT NOT NULL,
          item_name TEXT NOT NULL,
          item_type TEXT NOT NULL DEFAULT 'Other',
          item_id INTEGER NOT NULL DEFAULT 0,
          color_id INTEGER,
          quantity REAL NOT NULL,
          price REAL NOT NULL,
          FOREIGN KEY (achat_id) REFERENCES Achats(id) ON DELETE CASCADE
        )
      ''');
    }
    if (oldVersion < 19) {
      try {
        await db.execute('ALTER TABLE Achats ADD COLUMN pdf_path TEXT;');
      } catch (e) {
        Text('Could not add pdf_path to Achats: $e');
      }
    }
    if (oldVersion < 20) {
      try {
        await db.execute(
          'ALTER TABLE Commandes ADD COLUMN advance_payment REAL NOT NULL DEFAULT 0.0;',
        );
      } catch (_) {}
      try {
        await db.execute(
          "ALTER TABLE Commandes ADD COLUMN payment_status TEXT NOT NULL DEFAULT 'Unpaid';",
        );
      } catch (_) {}
      try {
        await db.execute(
          "ALTER TABLE Commandes ADD COLUMN created_at TEXT NOT NULL DEFAULT (datetime('now'));",
        );
      } catch (_) {}
      try {
        await db.execute(
          "ALTER TABLE Commandes ADD COLUMN updated_at TEXT NOT NULL DEFAULT (datetime('now'));",
        );
      } catch (_) {}
    }
    if (oldVersion < 21) {
      try {
        await db.execute(
          "UPDATE Commandes SET created_at = datetime('now') WHERE created_at IS NULL OR TRIM(created_at) = '';",
        );
      } catch (_) {}
      try {
        await db.execute(
          "UPDATE Commandes SET updated_at = datetime('now') WHERE updated_at IS NULL OR TRIM(updated_at) = '';",
        );
      } catch (_) {}
    }
    if (oldVersion < 22) {
      try {
        await db.execute(
          'ALTER TABLE Accessories ADD COLUMN screw_count INTEGER NOT NULL DEFAULT 0;',
        );
      } catch (_) {}
    }
    if (oldVersion < 23) {
      try {
        await db.execute(
          'ALTER TABLE Sections ADD COLUMN linked_renfort_id INTEGER;',
        );
      } catch (_) {}
      try {
        await db.execute(
          'ALTER TABLE Sections ADD COLUMN renfort_deduction REAL NOT NULL DEFAULT 140.0;',
        );
      } catch (_) {}
    }
    if (oldVersion < 24) {
      try {
        await db.execute(
          'ALTER TABLE Sections ADD COLUMN cutting_deduction REAL NOT NULL DEFAULT 0.0;',
        );
      } catch (_) {}
      try {
        await db.execute(
          'ALTER TABLE Sections ADD COLUMN visible_width REAL NOT NULL DEFAULT 0.0;',
        );
      } catch (_) {}
    }
    if (oldVersion < 26) {
      try {
        await db.execute(
          'ALTER TABLE Sections ADD COLUMN sash_overlap REAL NOT NULL DEFAULT 0.0;',
        );
      } catch (_) {}
    }
    if (oldVersion < 5) {
      await db.execute('''
        CREATE TABLE Colors (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          hex_code TEXT NOT NULL,
          type TEXT NOT NULL DEFAULT 'Global',
          price REAL NOT NULL DEFAULT 0.0,
          is_glass_color INTEGER NOT NULL DEFAULT 0
        )
      ''');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS Accessories (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          material_type TEXT NOT NULL DEFAULT 'Aluminium',
          scope TEXT NOT NULL DEFAULT 'Global',
          series_id INTEGER,
          series_ids TEXT,
          type TEXT NOT NULL,
          price REAL NOT NULL DEFAULT 0.0,
          screw_count INTEGER NOT NULL DEFAULT 0,
          is_moteur_screw INTEGER DEFAULT 0,
          is_caisson_screw INTEGER DEFAULT 0,
          is_batmo_screw INTEGER DEFAULT 0,
          is_bouchon_batmo_screw INTEGER DEFAULT 0,
          is_renfort_screw INTEGER DEFAULT 0,
          is_manivelle_screw INTEGER DEFAULT 0,
          is_tandem_screw INTEGER DEFAULT 0,
          is_kit_screw INTEGER DEFAULT 0,
          is_assembly_screw INTEGER DEFAULT 0,
          is_accessory_screw INTEGER DEFAULT 0,
          is_installation_screw INTEGER DEFAULT 0,
          is_gache_simple INTEGER DEFAULT 0,
          is_gache_double INTEGER DEFAULT 0,
          is_gache_porte INTEGER DEFAULT 0,
          is_lock_clef INTEGER DEFAULT 0,
          is_lock_condamnation INTEGER DEFAULT 0,
          is_active INTEGER NOT NULL DEFAULT 1
        )
      ''');
      await db.execute('''
        CREATE TABLE Joints (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          thickness REAL NOT NULL,
          price_per_meter REAL NOT NULL,
          type TEXT NOT NULL DEFAULT 'Global',
          scope TEXT NOT NULL DEFAULT 'Global',
          series_id INTEGER,
          series_ids TEXT,
          gasket_type TEXT
        )
      ''');
      await db.execute('''
        CREATE TABLE Glass (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          type TEXT NOT NULL,
          thickness REAL NOT NULL,
          price_per_sqm REAL NOT NULL,
          color TEXT DEFAULT '',
          image_path TEXT DEFAULT '',
          subtype TEXT DEFAULT '',
          height REAL NOT NULL DEFAULT 0.0,
          visible_width REAL DEFAULT NULL
        )
      ''');
      await db.execute('''
        CREATE TABLE ShutterComponents (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          component_type TEXT NOT NULL,
          name TEXT NOT NULL,
          price REAL NOT NULL,
          unit TEXT NOT NULL DEFAULT 'sqm',
          scope TEXT NOT NULL DEFAULT 'Global',
          series_id INTEGER,
          series_ids TEXT,
          is_active INTEGER NOT NULL DEFAULT 1,
          measurement TEXT DEFAULT '',
          track_measurement TEXT DEFAULT '',
          shutter_subtype TEXT NOT NULL DEFAULT 'normal',
          bar_length_m REAL NOT NULL DEFAULT 0.0,
          motor_diameter TEXT DEFAULT '',
          cap_thickness REAL NOT NULL DEFAULT 0.0,
          max_width_mm REAL NOT NULL DEFAULT 6000.0
        )
      ''');
    }
    if (oldVersion < 6) {
      try {
        await db.execute(
          'ALTER TABLE Series ADD COLUMN price_per_meter REAL NOT NULL DEFAULT 0.0;',
        );
      } catch (_) {}
      try {
        await db.execute(
          'ALTER TABLE Colors ADD COLUMN price REAL NOT NULL DEFAULT 0.0;',
        );
      } catch (_) {}
    }
    if (oldVersion < 7) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS SeriesColorPrices (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          series_id INTEGER NOT NULL,
          color_id INTEGER NOT NULL,
          price REAL NOT NULL DEFAULT 0.0,
          UNIQUE(series_id, color_id)
        )
      ''');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS SectionColorPrices (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          section_id INTEGER NOT NULL,
          color_id INTEGER NOT NULL,
          price REAL NOT NULL DEFAULT 0.0,
          UNIQUE(
          section_id, color_id)
        )
      ''');
    }
    if (oldVersion < 8) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS ProfileColors (
          id TEXT UNIQUE,
          profile_id INTEGER NOT NULL,
          color_id INTEGER NOT NULL,
          PRIMARY KEY (profile_id, color_id),
          FOREIGN KEY (profile_id) REFERENCES Profile(id) ON DELETE CASCADE,
          FOREIGN KEY (color_id) REFERENCES Colors(id) ON DELETE CASCADE
        )
      ''');
    }
    if (oldVersion < 9) {
      await db.execute('DROP TABLE IF EXISTS Client');
      await db.execute('''
        CREATE TABLE Client (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          firstname TEXT NOT NULL,
          lastname TEXT NOT NULL,
          phone1 TEXT,
          phone2 TEXT,
          email TEXT,
          address TEXT,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL
        )
      ''');
    }
    if (oldVersion < 10) {
      try {
        await db.execute(
          "ALTER TABLE Achat_items ADD COLUMN item_type TEXT NOT NULL DEFAULT 'Other';",
        );
        await db.execute(
          "ALTER TABLE Achat_items ADD COLUMN item_id INTEGER NOT NULL DEFAULT 0;",
        );
        await db.execute(
          "ALTER TABLE Achat_items ADD COLUMN color_id INTEGER;",
        );
      } catch (_) {}
    }
    if (oldVersion < 11) {
      try {
        await db.execute(
          "ALTER TABLE Profile ADD COLUMN default_bar_length REAL NOT NULL DEFAULT 5.8;",
        );
        await db.execute(
          "ALTER TABLE Sections ADD COLUMN bar_length REAL NOT NULL DEFAULT 5.8;",
        );
      } catch (_) {}
    }
    if (oldVersion < 12) {
      try {
        await db.execute("ALTER TABLE Achats ADD COLUMN supplier_id INTEGER;");
        await db.execute(
          "ALTER TABLE Achats ADD COLUMN paid_amount REAL NOT NULL DEFAULT 0.0;",
        );
        await db.execute(
          "ALTER TABLE Achats ADD COLUMN remaining_amount REAL NOT NULL DEFAULT 0.0;",
        );
      } catch (_) {}
      await db.execute('''
        CREATE TABLE IF NOT EXISTS Suppliers (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          phone TEXT,
          email TEXT,
          notes TEXT,
          created_at TEXT NOT NULL DEFAULT (datetime('now'))
        )
      ''');
    }
    if (oldVersion < 13) {
      try {
        await db.execute(
          "ALTER TABLE Commandes_details ADD COLUMN drawing_image_path TEXT;",
        );
      } catch (_) {}
    }
    if (oldVersion < 14) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS Suppliers (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          phone TEXT,
          email TEXT,
          notes TEXT,
          created_at TEXT NOT NULL DEFAULT (datetime('now'))
        )
      ''');
      try {
        await db.execute("ALTER TABLE Suppliers ADD COLUMN email TEXT;");
      } catch (_) {}
      try {
        await db.execute("ALTER TABLE Suppliers ADD COLUMN notes TEXT;");
      } catch (_) {}
    }
    if (oldVersion < 15) {
      try {
        await db.execute(
          "ALTER TABLE Accessories ADD COLUMN material_type TEXT NOT NULL DEFAULT 'Aluminium'",
        );
      } catch (_) {}
      try {
        await db.execute(
          "ALTER TABLE Accessories ADD COLUMN scope TEXT NOT NULL DEFAULT 'Global'",
        );
      } catch (_) {}
      try {
        await db.execute(
          "ALTER TABLE Accessories ADD COLUMN series_id INTEGER",
        );
      } catch (_) {}
      try {
        await db.execute("ALTER TABLE Accessories ADD COLUMN series_ids TEXT");
      } catch (_) {}
      try {
        await db.execute(
          "ALTER TABLE Joints ADD COLUMN type TEXT NOT NULL DEFAULT 'Global'",
        );
      } catch (_) {}
      try {
        await db.execute(
          "ALTER TABLE Joints ADD COLUMN scope TEXT NOT NULL DEFAULT 'Global'",
        );
      } catch (_) {}
      try {
        await db.execute("ALTER TABLE Joints ADD COLUMN series_id INTEGER");
      } catch (_) {}
      try {
        await db.execute("ALTER TABLE Joints ADD COLUMN series_ids TEXT");
      } catch (_) {}
      try {
        await db.execute(
          "ALTER TABLE Sections ADD COLUMN couvre_joint_width REAL NOT NULL DEFAULT 0.0",
        );
      } catch (_) {}
      try {
        await db.execute("ALTER TABLE Achats ADD COLUMN supplier_id INTEGER");
      } catch (_) {}
      try {
        await db.execute(
          "ALTER TABLE Achats ADD COLUMN paid_amount REAL NOT NULL DEFAULT 0.0",
        );
      } catch (_) {}
      try {
        await db.execute(
          "ALTER TABLE Achats ADD COLUMN remaining_amount REAL NOT NULL DEFAULT 0.0",
        );
      } catch (_) {}
      try {
        await db.execute("ALTER TABLE Suppliers ADD COLUMN email TEXT");
      } catch (_) {}
      try {
        await db.execute("ALTER TABLE Suppliers ADD COLUMN notes TEXT");
      } catch (_) {}
      try {
        await db.execute(
          "ALTER TABLE Commandes_details ADD COLUMN drawing_image_path TEXT",
        );
      } catch (_) {}
    }
    if (oldVersion < 16) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS AccessoryColorPrices (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          accessory_id INTEGER NOT NULL,
          color_id INTEGER NOT NULL,
          price REAL NOT NULL DEFAULT 0.0,
          UNIQUE(accessory_id, color_id)
        )
      ''');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS Treasury (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          transaction_type TEXT NOT NULL,
          amount REAL NOT NULL,
          description TEXT,
          reference_id INTEGER,
          recorded_by TEXT NOT NULL,
          created_at TEXT NOT NULL DEFAULT (datetime('now')),
          entity_type TEXT,
          entity_id INTEGER,
          phone TEXT,
          old_balance REAL DEFAULT 0.0,
          new_balance REAL DEFAULT 0.0,
          caisse_name TEXT,
          payment_method TEXT
        )
      ''');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS WorkerTransactions (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          worker_uid TEXT NOT NULL,
          amount REAL NOT NULL,
          transaction_type TEXT NOT NULL,
          note TEXT,
          created_at TEXT NOT NULL DEFAULT (datetime('now'))
        )
      ''');
    }

    if (oldVersion < 27) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS Locations (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          type TEXT NOT NULL,
          is_active INTEGER NOT NULL DEFAULT 1,
          created_at TEXT NOT NULL DEFAULT (datetime('now'))
        )
      ''');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS InventoryTransactions (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          item_id INTEGER NOT NULL,
          item_type TEXT NOT NULL,
          color_id INTEGER,
          location_id INTEGER NOT NULL,
          transaction_type TEXT NOT NULL,
          quantity REAL NOT NULL,
          reference_id INTEGER,
          note TEXT,
          created_at TEXT NOT NULL DEFAULT (datetime('now'))
        )
      ''');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS CurrentStock (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          item_id INTEGER NOT NULL,
          item_type TEXT NOT NULL,
          color_id INTEGER,
          location_id INTEGER NOT NULL,
          quantity REAL NOT NULL DEFAULT 0.0,
          low_stock_alert_enabled INTEGER NOT NULL DEFAULT 0,
          updated_at TEXT NOT NULL DEFAULT (datetime('now')),
          UNIQUE(item_id, item_type, color_id, location_id)
        )
      ''');
    }

    if (oldVersion < 28) {
      final tablesToAlter = [
        'Profile',
        'Series',
        'Sections',
        'Colors',
        'Accessories',
        'Glass',
        'ShutterComponents',
      ];
      for (final table in tablesToAlter) {
        try {
          await db.execute(
            "ALTER TABLE $table ADD COLUMN is_active INTEGER NOT NULL DEFAULT 1;",
          );
        } catch (_) {}
      }
    }

    if (oldVersion < 33) {
      try {
        await db.execute("ALTER TABLE Glass ADD COLUMN color TEXT DEFAULT '';");
      } catch (_) {}
      try {
        await db.execute(
          "ALTER TABLE Glass ADD COLUMN image_path TEXT DEFAULT '';",
        );
      } catch (_) {}
    }

    if (oldVersion < 34) {
      try {
        await db.execute(
          "ALTER TABLE Colors ADD COLUMN is_glass_color INTEGER NOT NULL DEFAULT 0;",
        );
      } catch (_) {}
    }

    if (oldVersion < 36) {
      try {
        await db.execute(
          "ALTER TABLE Glass ADD COLUMN subtype TEXT DEFAULT '';",
        );
      } catch (_) {}
    }

    if (oldVersion < 37) {
      try {
        await db.execute(
          "ALTER TABLE Sections ADD COLUMN couvre_joint_thickness REAL NOT NULL DEFAULT 0.0;",
        );
      } catch (_) {}
    }

    if (oldVersion < 40) {
      try {
        await db.execute(
          "ALTER TABLE Sections ADD COLUMN max_glass_thickness REAL NOT NULL DEFAULT 0.0;",
        );
      } catch (_) {}
      try {
        await db.execute(
          "ALTER TABLE Sections ADD COLUMN linked_parclose_double_id INTEGER;",
        );
      } catch (_) {}
      try {
        await db.execute(
          "ALTER TABLE Sections ADD COLUMN allows_side_cover INTEGER NOT NULL DEFAULT 1;",
        );
      } catch (_) {}
    }

    if (oldVersion < 42) {
      try {
        await db.execute(
          "ALTER TABLE Commandes_details ADD COLUMN instances_json TEXT;",
        );
      } catch (_) {}
    }

    if (oldVersion < 43) {
      try {
        await db.execute(
          "ALTER TABLE CurrentStock ADD COLUMN min_qty REAL DEFAULT 0.0;",
        );
      } catch (_) {}
    }
    if (oldVersion < 64) {
      await _ensureInventoryAlertSchema(db);
      await _ensureOrderInventoryIssueSchema(db);
    }

    if (oldVersion < 44) {
      try {
        await db.execute("ALTER TABLE Joints ADD COLUMN gasket_type TEXT;");
      } catch (_) {}
    }

    if (oldVersion < 45) {
      try {
        await db.execute("ALTER TABLE Suppliers ADD COLUMN latitude REAL;");
      } catch (_) {}
      try {
        await db.execute("ALTER TABLE Suppliers ADD COLUMN longitude REAL;");
      } catch (_) {}
    }

    if (oldVersion < 46) {
      try {
        await db.execute(
          "ALTER TABLE Client ADD COLUMN nif TEXT NOT NULL DEFAULT '';",
        );
      } catch (_) {}
      try {
        await db.execute(
          "ALTER TABLE Client ADD COLUMN nis TEXT NOT NULL DEFAULT '';",
        );
      } catch (_) {}
      try {
        await db.execute(
          "ALTER TABLE Client ADD COLUMN rc TEXT NOT NULL DEFAULT '';",
        );
      } catch (_) {}
      try {
        await db.execute(
          "ALTER TABLE Client ADD COLUMN ai TEXT NOT NULL DEFAULT '';",
        );
      } catch (_) {}
      try {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS Measurements (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            length REAL,
            width REAL,
            frame_type TEXT,
            opening_system TEXT,
            shutter_exists INTEGER,
            shutter_side TEXT,
            shutter_type TEXT,
            shutter_motor_maneuver INTEGER,
            glass_type TEXT,
            glass_decoration TEXT,
            handle_height REAL,
            reinforced_lateral INTEGER,
            reinforced_center INTEGER,
            bottom_frame_exists INTEGER,
            window_location TEXT,
            media_path TEXT,
            audio_path TEXT,
            video_path TEXT,
            note TEXT,
            created_at TEXT NOT NULL DEFAULT (datetime('now'))
          )
        ''');
      } catch (_) {}
    }

    if (oldVersion < 47) {
      try {
        await db.execute("ALTER TABLE Treasury ADD COLUMN entity_type TEXT;");
      } catch (_) {}
      try {
        await db.execute("ALTER TABLE Treasury ADD COLUMN entity_id INTEGER;");
      } catch (_) {}
      try {
        await db.execute("ALTER TABLE Treasury ADD COLUMN phone TEXT;");
      } catch (_) {}
      try {
        await db.execute(
          "ALTER TABLE Treasury ADD COLUMN old_balance REAL DEFAULT 0.0;",
        );
      } catch (_) {}
      try {
        await db.execute(
          "ALTER TABLE Treasury ADD COLUMN new_balance REAL DEFAULT 0.0;",
        );
      } catch (_) {}
      try {
        await db.execute("ALTER TABLE Treasury ADD COLUMN caisse_name TEXT;");
      } catch (_) {}
      try {
        await db.execute(
          "ALTER TABLE Treasury ADD COLUMN payment_method TEXT;",
        );
      } catch (_) {}
    }

    if (oldVersion < 48) {
      try {
        await db.execute(
          "ALTER TABLE Commandes_deliveries ADD COLUMN is_loaded INTEGER DEFAULT 0;",
        );
      } catch (_) {}
    }

    if (oldVersion < 50) {
      try {
        await db.execute(
          "ALTER TABLE Client ADD COLUMN creation_platform TEXT NOT NULL DEFAULT 'unknown';",
        );
      } catch (_) {}
    }

    if (oldVersion < 51) {
      try {
        await db.execute('ALTER TABLE Client ADD COLUMN latitude REAL;');
      } catch (_) {}
      try {
        await db.execute('ALTER TABLE Client ADD COLUMN longitude REAL;');
      } catch (_) {}
    }

    if (oldVersion < 52) {
      try {
        await db.execute(
          'ALTER TABLE Sections ADD COLUMN is_frame INTEGER NOT NULL DEFAULT 0;',
        );
      } catch (_) {}
      try {
        await db.execute(
          'ALTER TABLE Sections ADD COLUMN is_sash INTEGER NOT NULL DEFAULT 0;',
        );
      } catch (_) {}
      try {
        await db.execute(
          'ALTER TABLE Sections ADD COLUMN is_mullion INTEGER NOT NULL DEFAULT 0;',
        );
      } catch (_) {}
      // Preserve the role implied by the old primary type.
      try {
        await db.execute(
          "UPDATE Sections SET is_frame = 1 WHERE is_frame = 0 AND LOWER(type) = 'frame';",
        );
        await db.execute(
          "UPDATE Sections SET is_sash = 1 WHERE is_sash = 0 AND LOWER(type) LIKE 'sash%';",
        );
        await db.execute(
          "UPDATE Sections SET is_mullion = 1 WHERE is_mullion = 0 AND LOWER(type) = 'mullion';",
        );
      } catch (_) {}
    }

    if (oldVersion < 53) {
      await _ensureSeriesDesignTables(db);
    }
    if (oldVersion < 54) {
      await _ensureClientCodeInfrastructure(db);
      await _backfillClientCodes(db);
    }
    if (oldVersion < 55) {
      try {
        await db.execute(
          'ALTER TABLE KitItemRanges ADD COLUMN compatibility_group INTEGER NOT NULL DEFAULT 0;',
        );
      } catch (_) {}
    }
    if (oldVersion < 56) {
      try {
        await db.execute(
          "ALTER TABLE KitBundleItems ADD COLUMN mechanism_scope TEXT NOT NULL DEFAULT 'all';",
        );
      } catch (_) {}
    }
    if (oldVersion < 57) {
      await _ensureRemnantInventorySchema(db);
      await _ensureSyncTombstoneInfrastructure(db);
    }
    if (oldVersion < 58) {
      await _ensureAdvancedKitCompatibilitySchema(db);
      await _ensureSyncTombstoneInfrastructure(db);
    }
    if (oldVersion < 59) {
      await _ensureDecorPanelDesignSchema(db);
      await _ensureSyncTombstoneInfrastructure(db);
    }
    if (oldVersion < 60) {
      await _ensurePaymentAllocationSchema(db);
      await _ensureSyncTombstoneInfrastructure(db);
    }
    if (oldVersion < 61) {
      await _ensureAdvancedKitCompatibilitySchema(db);
      await _ensureSyncTombstoneInfrastructure(db);
    }
    if (oldVersion < 62) {
      try {
        await db.execute('DROP INDEX IF EXISTS idx_achat_items_unique;');
      } catch (_) {}
      await _ensureInventoryAlertSchema(db);
    }
    if (oldVersion < 63) {
      await _ensureOrderCodeInfrastructure(db);
      await _backfillOrderCodes(db);
    }
  }

  void _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS SeriesColorPrices (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        series_id INTEGER NOT NULL,
        color_id INTEGER NOT NULL,
        price REAL NOT NULL DEFAULT 0.0,
        UNIQUE(series_id, color_id)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS SectionColorPrices (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        section_id INTEGER NOT NULL,
        color_id INTEGER NOT NULL,
        price REAL NOT NULL DEFAULT 0.0,
        UNIQUE(section_id, color_id)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS ProfileColors (
        id TEXT UNIQUE,
        profile_id INTEGER NOT NULL,
        color_id INTEGER NOT NULL,
        PRIMARY KEY (profile_id, color_id),
        FOREIGN KEY (profile_id) REFERENCES Profile(id) ON DELETE CASCADE,
        FOREIGN KEY (color_id) REFERENCES Colors(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
    CREATE TABLE Profile (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL UNIQUE,
      type TEXT NOT NULL,
      is_active INTEGER NOT NULL DEFAULT 1,
      default_bar_length REAL NOT NULL DEFAULT 5.8
    )
    ''');

    await db.execute('''
      CREATE TABLE Series (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      profile_id INTEGER NOT NULL,
      name TEXT NOT NULL,
      type TEXT NOT NULL,
      is_active INTEGER NOT NULL DEFAULT 1,
      price_per_meter REAL NOT NULL DEFAULT 0.0,
      has_three_piece_sash INTEGER NOT NULL DEFAULT 0,
      FOREIGN KEY (profile_id) REFERENCES Profile(id) ON DELETE CASCADE
    )
    ''');

    await db.execute('''
      CREATE TABLE Sections (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      series_id INTEGER NOT NULL,
      code TEXT NOT NULL,
      name TEXT NOT NULL,
      type TEXT NOT NULL,
      thickness REAL NOT NULL,
      glass_deduction REAL NOT NULL DEFAULT 0.0,
      weight_per_meter REAL NOT NULL DEFAULT 0.0,
      couvre_joint_width REAL NOT NULL DEFAULT 0.0,
      couvre_joint_thickness REAL NOT NULL DEFAULT 0.0,
      bar_length REAL NOT NULL DEFAULT 5.8,
      linked_renfort_id INTEGER,
      renfort_deduction REAL NOT NULL DEFAULT 140.0,
      cutting_deduction REAL NOT NULL DEFAULT 0.0,
      visible_width REAL NOT NULL DEFAULT 0.0,
      visible_width_2 REAL NOT NULL DEFAULT 0.0,
      sash_overlap REAL NOT NULL DEFAULT 0.0,
      max_glass_thickness REAL NOT NULL DEFAULT 0.0,
      linked_parclose_double_id INTEGER,
      allows_side_cover INTEGER NOT NULL DEFAULT 1,
      is_frame INTEGER NOT NULL DEFAULT 0,
      is_sash INTEGER NOT NULL DEFAULT 0,
      is_mullion INTEGER NOT NULL DEFAULT 0,
      FOREIGN KEY (series_id) REFERENCES Series(id) ON DELETE CASCADE
    )
    ''');

    await db.execute('''
    CREATE TABLE Client (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      client_code INTEGER NOT NULL DEFAULT 0,
      firstname TEXT NOT NULL,
      lastname TEXT NOT NULL,
      phone1 TEXT,
      phone2 TEXT,
      email TEXT,
      address TEXT,
      nif TEXT NOT NULL DEFAULT '',
      nis TEXT NOT NULL DEFAULT '',
      rc TEXT NOT NULL DEFAULT '',
      ai TEXT NOT NULL DEFAULT '',
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      creation_platform TEXT NOT NULL DEFAULT 'unknown'
    )
    ''');
    await _ensureClientCodeInfrastructure(db);

    await db.execute('''
      CREATE TABLE IF NOT EXISTS Measurements (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        length REAL,
        width REAL,
        frame_type TEXT,
        opening_system TEXT,
        shutter_exists INTEGER,
        shutter_side TEXT,
        shutter_type TEXT,
        shutter_motor_maneuver INTEGER,
        glass_type TEXT,
        glass_decoration TEXT,
        handle_height REAL,
        reinforced_lateral INTEGER,
        reinforced_center INTEGER,
        bottom_frame_exists INTEGER,
        window_location TEXT,
        media_path TEXT,
        audio_path TEXT,
        video_path TEXT,
        note TEXT,
        created_at TEXT NOT NULL DEFAULT (datetime('now'))
      )
    ''');

    await db.execute('''
  CREATE TABLE Commandes (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    order_code INTEGER NOT NULL DEFAULT 0,
    client_id INTEGER NOT NULL,
    status TEXT,
    description TEXT,
    remise REAL DEFAULT 0.0,
    tva REAL DEFAULT 0.0,
    total REAL NOT NULL,
    net_payable REAL NOT NULL DEFAULT 0.0,
    advance_payment REAL NOT NULL DEFAULT 0.0,
    payment_status TEXT NOT NULL DEFAULT 'Unpaid',
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at TEXT NOT NULL DEFAULT (datetime('now'))
  )
''');
    await _ensureOrderCodeInfrastructure(db);

    await db.execute('''
  CREATE TABLE Commandes_details (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    id_commandes INTEGER NOT NULL,
    largeur INTEGER NOT NULL,
    hauteur INTEGER NOT NULL,
    game TEXT NOT NULL,
    quantity INTEGER NOT NULL,
    glass TEXT NOT NULL,
    color TEXT NOT NULL,
    volet TEXT NOT NULL,
    accessories TEXT NOT NULL,
    description TEXT NOT NULL,
    price DECIMAL(10,2) NOT NULL,
    window_type TEXT,
    partitions_json TEXT,
    drawing_image_path TEXT,
    drawing_image_base64 TEXT,
    delivered_qty INTEGER DEFAULT 0,
    instances_json TEXT,
    updated_at TEXT,
    FOREIGN KEY (id_commandes) REFERENCES Commandes(id) ON DELETE CASCADE
  )
''');

    await db.execute('''
      CREATE TABLE Commandes_deliveries (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        id_commandes INTEGER NOT NULL,
        client_id INTEGER NOT NULL,
        delivery_date TEXT NOT NULL,
        items_json TEXT NOT NULL,
        total_amount REAL NOT NULL DEFAULT 0.0,
        FOREIGN KEY (id_commandes) REFERENCES Commandes(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
    CREATE TABLE Achats (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      invoice_number TEXT NOT NULL,
      supplier_id INTEGER,
      supplier_name TEXT NOT NULL,
      status TEXT NOT NULL DEFAULT 'Active',
      total REAL NOT NULL DEFAULT 0.0,
      paid_amount REAL NOT NULL DEFAULT 0.0,
      remaining_amount REAL NOT NULL DEFAULT 0.0,
      image_path TEXT,
      pdf_path TEXT,
      created_at TEXT NOT NULL DEFAULT (datetime('now')),
      updated_at TEXT NOT NULL DEFAULT (datetime('now'))
    )
    ''');

    await db.execute('''
    CREATE TABLE Achat_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        achat_id INTEGER NOT NULL,
        item_code TEXT NOT NULL,
        item_name TEXT NOT NULL,
        item_type TEXT NOT NULL DEFAULT 'Other',
        item_id INTEGER NOT NULL DEFAULT 0,
        color_id INTEGER,
        quantity REAL NOT NULL,
        price REAL NOT NULL,
        FOREIGN KEY (achat_id) REFERENCES Achats(id) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
    CREATE TABLE Employees (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      uid TEXT NOT NULL UNIQUE,
      email TEXT NOT NULL,
      name TEXT NOT NULL,
      permissions_json TEXT NOT NULL,
      salary_type TEXT,
      base_salary REAL,
      phone TEXT,
      address TEXT,
      job_role TEXT
    )
    ''');

    await db.execute('''
        CREATE TABLE Colors (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      hex_code TEXT NOT NULL,
      type TEXT NOT NULL DEFAULT 'Global',
      price REAL NOT NULL DEFAULT 0.0,
      is_glass_color INTEGER NOT NULL DEFAULT 0
    )
    ''');

    await db.execute('''
    CREATE TABLE Accessories (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      type TEXT NOT NULL,
      price REAL NOT NULL,
      material_type TEXT NOT NULL DEFAULT 'Aluminium',
      scope TEXT NOT NULL DEFAULT 'Global',
      series_id INTEGER,
      series_ids TEXT,
      screw_count INTEGER NOT NULL DEFAULT 0,
      is_active INTEGER NOT NULL DEFAULT 1,
      is_selling_calculated INTEGER DEFAULT 0
    )
    ''');

    await db.execute('''
    CREATE TABLE Joints (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      thickness REAL NOT NULL,
      price_per_meter REAL NOT NULL,
      type TEXT NOT NULL DEFAULT 'Global',
      scope TEXT NOT NULL DEFAULT 'Global',
      series_id INTEGER,
      series_ids TEXT
    )
    ''');

    await db.execute('''
    CREATE TABLE Glass (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      type TEXT NOT NULL,
      thickness REAL NOT NULL,
      price_per_sqm REAL NOT NULL,
      color TEXT DEFAULT '',
      image_path TEXT DEFAULT '',
      subtype TEXT DEFAULT '',
      height REAL NOT NULL DEFAULT 0.0
    )
    ''');

    await db.execute('''
    CREATE TABLE IF NOT EXISTS GlassColorPrices (
      glass_id INTEGER,
      color_name TEXT,
      price REAL NOT NULL,
      PRIMARY KEY (glass_id, color_name)
    )
    ''');

    await db.execute('''
    CREATE TABLE ShutterComponents (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      component_type TEXT NOT NULL,
      name TEXT NOT NULL,
      price REAL NOT NULL,
      unit TEXT NOT NULL DEFAULT 'sqm',
      scope TEXT NOT NULL DEFAULT 'Global',
      series_id INTEGER,
      series_ids TEXT,
      is_active INTEGER NOT NULL DEFAULT 1,
      measurement TEXT DEFAULT '',
      track_measurement TEXT DEFAULT '',
      shutter_subtype TEXT NOT NULL DEFAULT 'normal',
      bar_length_m REAL NOT NULL DEFAULT 0.0,
      motor_diameter TEXT DEFAULT '',
      motor_has_emergency_crank INTEGER NOT NULL DEFAULT 0,
      cap_thickness REAL NOT NULL DEFAULT 0.0,
      max_width_mm REAL NOT NULL DEFAULT 6000.0
    )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS Suppliers (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        phone TEXT,
        email TEXT,
        notes TEXT,
        latitude REAL,
        longitude REAL,
        created_at TEXT NOT NULL DEFAULT (datetime('now'))
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS AccessoryColorPrices (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        accessory_id INTEGER NOT NULL,
        color_id INTEGER NOT NULL,
        price REAL NOT NULL DEFAULT 0.0,
        UNIQUE(accessory_id, color_id)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS Treasury (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        transaction_type TEXT NOT NULL,
        amount REAL NOT NULL,
        description TEXT,
        reference_id INTEGER,
        recorded_by TEXT NOT NULL,
        created_at TEXT NOT NULL DEFAULT (datetime('now')),
        entity_type TEXT,
        entity_id INTEGER,
        phone TEXT,
        old_balance REAL DEFAULT 0.0,
        new_balance REAL DEFAULT 0.0,
        caisse_name TEXT,
        payment_method TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS Caisses (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL UNIQUE
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS WorkerTransactions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        worker_uid TEXT NOT NULL,
        amount REAL NOT NULL,
        transaction_type TEXT NOT NULL,
        note TEXT,
        created_at TEXT NOT NULL DEFAULT (datetime('now'))
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS Locations (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        type TEXT NOT NULL,
        is_active INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL DEFAULT (datetime('now'))
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS InventoryTransactions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        item_id INTEGER NOT NULL,
        item_type TEXT NOT NULL,
        color_id INTEGER,
        location_id INTEGER NOT NULL,
        transaction_type TEXT NOT NULL,
        quantity REAL NOT NULL,
        reference_id INTEGER,
        note TEXT,
        created_at TEXT NOT NULL DEFAULT (datetime('now'))
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS CurrentStock (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        item_id INTEGER NOT NULL,
        item_type TEXT NOT NULL,
        color_id INTEGER,
        location_id INTEGER NOT NULL,
        quantity REAL NOT NULL DEFAULT 0.0,
        min_qty REAL DEFAULT 0.0,
        low_stock_alert_enabled INTEGER NOT NULL DEFAULT 0,
        updated_at TEXT NOT NULL DEFAULT (datetime('now')),
        UNIQUE(item_id, item_type, color_id, location_id)
      )
    ''');
    await _ensureRemnantInventorySchema(db);
    await _ensureOrderInventoryIssueSchema(db);

    // Kit Bundles tables
    await db.execute('''
      CREATE TABLE IF NOT EXISTS KitBundles (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        description TEXT,
        per_leaf INTEGER NOT NULL DEFAULT 0,
        is_active INTEGER NOT NULL DEFAULT 1,
        is_selling_calculated INTEGER NOT NULL DEFAULT 1
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS KitBundleItems (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        kit_id INTEGER NOT NULL,
        component_type TEXT NOT NULL,
        qty_mode TEXT NOT NULL DEFAULT 'fixed',
        dimension TEXT,
        base_qty REAL NOT NULL DEFAULT 1,
        unit TEXT NOT NULL DEFAULT 'Ù‚Ø·Ø¹Ø©',
        mechanism_scope TEXT NOT NULL DEFAULT 'all',
        sort_order INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY (kit_id) REFERENCES KitBundles(id) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS KitItemRanges (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        item_id INTEGER NOT NULL,
        min_mm REAL NOT NULL,
        max_mm REAL NOT NULL,
        product_name TEXT NOT NULL,
        price REAL NOT NULL DEFAULT 0.0,
        qty REAL NOT NULL DEFAULT 1,
        compatibility_group INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY (item_id) REFERENCES KitBundleItems(id) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS KitItemVariants (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        item_id INTEGER NOT NULL,
        ouvrant_type TEXT NOT NULL,
        product_name TEXT NOT NULL,
        price REAL NOT NULL DEFAULT 0.0,
        qty REAL NOT NULL DEFAULT 1,
        FOREIGN KEY (item_id) REFERENCES KitBundleItems(id) ON DELETE CASCADE
      )
    ''');
    await _ensureAdvancedKitCompatibilitySchema(db);
    await _ensureDecorPanelDesignSchema(db);

    await db.execute('''
      CREATE TABLE IF NOT EXISTS ShutterBoxLimits (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        box_size INTEGER NOT NULL,
        blade_id INTEGER NOT NULL,
        max_height REAL NOT NULL,
        FOREIGN KEY (blade_id) REFERENCES ShutterComponents(id) ON DELETE CASCADE
      )
    ''');
  }

  //////////////////////////////////// Profile //////////////////////////////////////
  Future<List<Map<String, dynamic>>> readProfile() async {
    Database? myDb = await db;
    return await myDb!.rawQuery(
      'SELECT * FROM Profile WHERE is_active = 1 OR is_active IS NULL',
    );
  }

  Future<List<Map<String, dynamic>>> readAllProfiles() async {
    Database? myDb = await db;
    return await myDb!.rawQuery('SELECT * FROM Profile ORDER BY name ASC');
  }

  Future<int> insertProfile(
    String name,
    String type, {
    double defaultBarLength = 5.8,
  }) async {
    Database? myDb = await db;
    var res = await myDb!.rawInsert(
      'INSERT INTO Profile (name, type, default_bar_length) VALUES (?, ?, ?)',
      [name, type, defaultBarLength],
    );
    CloudSyncService().notifyChange();
    return res;
  }

  Future<int> updateProfile(
    int id,
    String name,
    String type, {
    double defaultBarLength = 5.8,
  }) async {
    Database? myDb = await db;
    var res = await myDb!.update(
      'Profile',
      {'name': name, 'type': type, 'default_bar_length': defaultBarLength},
      where: 'id = ?',
      whereArgs: [id],
    );
    CloudSyncService().notifyChange();
    return res;
  }

  Future<int> deleteProfile(int id) async {
    Database? myDb = await db;
    var res = await myDb!.update(
      'Profile',
      {'is_active': 0},
      where: 'id = ?',
      whereArgs: [id],
    );
    CloudSyncService().notifyChange();
    return res;
  }

  //////////////////////////////////// Series //////////////////////////////////////
  Future<List<Map<String, dynamic>>> readSeriesByProfile(int profileId) async {
    Database? myDb = await db;
    return await myDb!.query(
      'Series',
      where: 'profile_id = ? AND (is_active = 1 OR is_active IS NULL)',
      whereArgs: [profileId],
    );
  }

  Future<List<Map<String, dynamic>>> readAllSeriesByProfile(
    int profileId,
  ) async {
    Database? myDb = await db;
    return await myDb!.query(
      'Series',
      where: 'profile_id = ?',
      whereArgs: [profileId],
    );
  }

  Future<int> insertSeries(
    int profileId,
    String name,
    String type, {
    double pricePerMeter = 0.0,
    int hasThreePieceSash = 0,
  }) async {
    Database? myDb = await db;
    var res = await myDb!.insert('Series', {
      'profile_id': profileId,
      'name': name,
      'type': type,
      'price_per_meter': pricePerMeter,
      'has_three_piece_sash': hasThreePieceSash,
    });
    CloudSyncService().notifyChange();
    return res;
  }

  Future<double> getSeriesColorPrice(int seriesId, int colorId) async {
    Database? myDb = await db;
    var res = await myDb!.query(
      'SeriesColorPrices',
      where: 'series_id = ? AND color_id = ?',
      whereArgs: [seriesId, colorId],
    );
    if (res.isNotEmpty) {
      return (res.first['price'] as num).toDouble();
    }
    return 0.0;
  }

  Future<double> getSectionColorPrice(int sectionId, int colorId) async {
    Database? myDb = await db;
    var res = await myDb!.query(
      'SectionColorPrices',
      where: 'section_id = ? AND color_id = ?',
      whereArgs: [sectionId, colorId],
    );
    if (res.isNotEmpty) {
      return (res.first['price'] as num).toDouble();
    }
    return 0.0;
  }

  Future<double> getAccessoryColorPrice(int accessoryId, int colorId) async {
    Database? myDb = await db;
    var res = await myDb!.query(
      'AccessoryColorPrices',
      where: 'accessory_id = ? AND color_id = ?',
      whereArgs: [accessoryId, colorId],
    );
    if (res.isNotEmpty) {
      return (res.first['price'] as num).toDouble();
    }
    return 0.0;
  }

  Future<List<Map<String, dynamic>>> getAccessoriesWithPrices(
    int? seriesId,
    int? colorId,
  ) async {
    final myDb = await db;
    if (myDb == null) return [];

    final List<Map<String, dynamic>> rawAccessories = await myDb.query(
      'Accessories',
      where: 'is_active = 1',
    );

    List<Map<String, dynamic>> result = [];
    for (var acc in rawAccessories) {
      int accId = acc['id'] as int;
      final List<Map<String, dynamic>> allColorPriceRows = await myDb.query(
        'AccessoryColorPrices',
        columns: ['color_id', 'price'],
        where: 'accessory_id = ?',
        whereArgs: [accId],
      );
      double finalPrice;
      if (allColorPriceRows.isEmpty) {
        finalPrice = (acc['price'] as num?)?.toDouble() ?? 0.0;
      } else {
        final matchingColorPrice = colorId == null
            ? <Map<String, dynamic>>[]
            : allColorPriceRows
                  .where(
                    (row) => row['color_id']?.toString() == colorId.toString(),
                  )
                  .toList();
        finalPrice = matchingColorPrice.isEmpty
            ? 0.0
            : (matchingColorPrice.first['price'] as num?)?.toDouble() ?? 0.0;
      }

      String scope = acc['scope'] ?? 'Global';
      if (scope == 'Series' && seriesId != null) {
        int? accSeriesId = acc['series_id'] as int?;
        String? seriesIdsStr = acc['series_ids'] as String?;
        bool matches = false;
        if (accSeriesId == seriesId) {
          matches = true;
        } else if (seriesIdsStr != null && seriesIdsStr.isNotEmpty) {
          try {
            List<dynamic> ids = jsonDecode(seriesIdsStr);
            if (ids.contains(seriesId)) {
              matches = true;
            }
          } catch (_) {}
        }
        if (!matches) continue;
      }

      var accMap = Map<String, dynamic>.from(acc);
      accMap['final_price'] = finalPrice;
      result.add(accMap);
    }

    return result;
  }

  Future<int> setSeriesColorPrice(
    int seriesId,
    int colorId,
    double price,
  ) async {
    Database? myDb = await db;
    var res = await myDb!.insert('SeriesColorPrices', {
      'series_id': seriesId,
      'color_id': colorId,
      'price': price,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    CloudSyncService().notifyChange();
    return res;
  }

  Future<int> setSectionColorPrice(
    int sectionId,
    int colorId,
    double price,
  ) async {
    Database? myDb = await db;
    if (myDb == null) {
      throw StateError('قاعدة البيانات غير متاحة لحفظ سعر القطاع');
    }
    if (!price.isFinite || price < 0) {
      throw ArgumentError.value(price, 'price', 'سعر القطاع غير صالح');
    }

    await myDb.execute('''
      CREATE TABLE IF NOT EXISTS SectionColorPrices (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        section_id INTEGER NOT NULL,
        color_id INTEGER NOT NULL,
        price REAL NOT NULL DEFAULT 0.0,
        UNIQUE(section_id, color_id)
      )
    ''');

    // بعض قواعد البيانات القديمة لم يكن فيها القيد الفريد على
    // (section_id, color_id). في تلك الحالة كان INSERT OR REPLACE يضيف صفاً
    // جديداً ويترك السعر القديم يُقرأ أولاً. نحدّث كل الصفوف المطابقة صراحة.
    final updated = await myDb.update(
      'SectionColorPrices',
      {'price': price},
      where: 'section_id = ? AND color_id = ?',
      whereArgs: [sectionId, colorId],
    );
    final res = updated > 0
        ? updated
        : await myDb.insert('SectionColorPrices', {
            'section_id': sectionId,
            'color_id': colorId,
            'price': price,
          });

    // تحقق مباشر قبل إعلام الواجهة بالنجاح؛ لا نعرض نجاحاً وهمياً إذا لم
    // يُكتب السعر فعلاً في التخزين المحلي.
    final persisted = await myDb.query(
      'SectionColorPrices',
      columns: ['price'],
      where: 'section_id = ? AND color_id = ?',
      whereArgs: [sectionId, colorId],
    );
    if (persisted.isEmpty ||
        persisted.any(
          (row) => ((row['price'] as num?)?.toDouble() ?? double.nan) != price,
        )) {
      throw StateError('تعذر التحقق من حفظ سعر القطاع');
    }
    CloudSyncService().notifyChange();
    return res;
  }

  Future<int> setAccessoryColorPrice(
    int accessoryId,
    int colorId,
    double price,
  ) async {
    Database? myDb = await db;
    var res = await myDb!.insert('AccessoryColorPrices', {
      'accessory_id': accessoryId,
      'color_id': colorId,
      'price': price,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    CloudSyncService().notifyChange();
    return res;
  }

  Future<int> updateSeries(
    int id,
    int profileId,
    String name,
    String type, {
    double pricePerMeter = 0.0,
    int hasThreePieceSash = 0,
  }) async {
    Database? myDb = await db;
    var res = await myDb!.update(
      'Series',
      {
        'profile_id': profileId,
        'name': name,
        'type': type,
        'price_per_meter': pricePerMeter,
        'has_three_piece_sash': hasThreePieceSash,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    CloudSyncService().notifyChange();
    return res;
  }

  Future<int> deleteSeries(int id) async {
    Database? myDb = await db;
    var res = await myDb!.update(
      'Series',
      {'is_active': 0},
      where: 'id = ?',
      whereArgs: [id],
    );
    CloudSyncService().notifyChange();
    return res;
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

  Future<List<Map<String, dynamic>>> searchSectionsWithProfile(
    String query,
  ) async {
    final dbClient = await db;
    String q = query.toLowerCase();

    return await dbClient!.rawQuery(
      '''
      SELECT s.*, p.name as profile_name
      FROM Sections s
      JOIN Series ser ON s.series_id = ser.id
      JOIN Profile p ON ser.profile_id = p.id
      WHERE (s.is_active = 1 OR s.is_active IS NULL) AND (ser.is_active = 1 OR ser.is_active IS NULL) AND (p.is_active = 1 OR p.is_active IS NULL) AND (LOWER(s.name) LIKE ? OR LOWER(s.code) LIKE ? OR LOWER(p.name) LIKE ?)
    ''',
      ['%$q%', '%$q%', '%$q%'],
    );
  }

  Future<int> insertSection({
    required int seriesId,
    required String code,
    required String name,
    required String type,
    required double thickness,
    required double glassDeduction,
    required double weightPerMeter,
    double couvreJointWidth = 0.0,
    double couvreJointThickness = 0.0,
    double cuttingDeduction = 0.0,
    double visibleWidth = 0.0,
    double visibleWidth2 = 0.0,
    double sashOverlap = 0.0,
    double barLength = 5.8,
    String? imagePath,
    double maxGlassThickness = 0.0,
    int? linkedParcloseDoubleId,
    int allowsSideCover = 1,
    int isFrame = 0,
    int isSash = 0,
    int isMullion = 0,
  }) async {
    Database? myDb = await db;
    // A running application can keep an older local database open during a
    // hot restart.  Ensure the independent drawing-role columns exist before
    // creating a section, rather than silently losing the selected roles.
    await _ensureSectionDrawingRoleColumns(myDb!);
    var res = await myDb!.insert('Sections', {
      'series_id': seriesId,
      'code': code,
      'name': name,
      'type': type,
      'thickness': thickness,
      'glass_deduction': glassDeduction,
      'weight_per_meter': weightPerMeter,
      'couvre_joint_width': couvreJointWidth,
      'couvre_joint_thickness': couvreJointThickness,
      'cutting_deduction': cuttingDeduction,
      'visible_width': visibleWidth,
      'visible_width_2': visibleWidth2,
      'sash_overlap': sashOverlap,
      'bar_length': barLength,
      'image_path': imagePath,
      'max_glass_thickness': maxGlassThickness,
      'linked_parclose_double_id': linkedParcloseDoubleId,
      'allows_side_cover': allowsSideCover,
      'is_frame': isFrame,
      'is_sash': isSash,
      'is_mullion': isMullion,
    });
    // Sections are part of the shared catalogue.  A normal data-change
    // notification does not mark the catalogue as newer, so opening the
    // profile page could import an older catalogue and undo these roles.
    CloudSyncService().notifyCatalogChange();
    return res;
  }

  Future<int> updateSection(int id, Map<String, dynamic> data) async {
    Database? myDb = await db;
    await _ensureSectionDrawingRoleColumns(myDb!);
    var res = await myDb!.update(
      'Sections',
      data,
      where: 'id = ?',
      whereArgs: [id],
    );
    CloudSyncService().notifyCatalogChange();
    return res;
  }

  Future<int> deleteSection(int id) async {
    Database? myDb = await db;
    var res = await myDb!.update(
      'Sections',
      {'is_active': 0},
      where: 'id = ?',
      whereArgs: [id],
    );
    CloudSyncService().notifyChange();
    return res;
  }

  //////////////////////////////////// Client //////////////////////////////////////
  /// Adds the immutable, user-facing client ID infrastructure.  [id] remains
  /// a distributed technical key for synchronisation; [client_code] is the
  /// business ID shown to people (1, 2, 3...) and is never recalculated.
  Future<void> _ensureClientCodeInfrastructure(
    DatabaseExecutor executor,
  ) async {
    try {
      await executor.execute(
        'ALTER TABLE Client ADD COLUMN client_code INTEGER NOT NULL DEFAULT 0;',
      );
    } catch (_) {
      // The column already exists on new and upgraded databases.
    }
    await executor.execute('''
      CREATE TABLE IF NOT EXISTS ClientCodeSequence (
        id INTEGER PRIMARY KEY CHECK (id = 1),
        last_code INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await executor.insert('ClientCodeSequence', {
      'id': 1,
      'last_code': 0,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  int _positiveInt(Object? value) {
    if (value is num) {
      final number = value.toInt();
      return number > 0 ? number : 0;
    }
    final parsed = int.tryParse(value?.toString().trim() ?? '') ?? 0;
    return parsed > 0 ? parsed : 0;
  }

  /// Gives legacy rows a permanent client code once.  Existing old local IDs
  /// are preserved as their visible code; newer distributed IDs receive the
  /// next available code.  The sequence's high-water mark is retained even
  /// if all clients are later deleted.
  Future<void> _backfillClientCodes(DatabaseExecutor executor) async {
    await _ensureClientCodeInfrastructure(executor);
    final rows = await executor.query(
      'Client',
      columns: ['id', 'client_code', 'created_at'],
      orderBy: 'created_at ASC, id ASC',
    );
    if (rows.isEmpty) return;

    final usedCodes = <int>{};
    final pending = <Map<String, dynamic>>[];
    var highestCode = 0;

    for (final source in rows) {
      final row = Map<String, dynamic>.from(source);
      final code = _positiveInt(row['client_code']);
      if (code > 0 && usedCodes.add(code)) {
        if (code > highestCode) highestCode = code;
      } else {
        pending.add(row);
      }
    }

    // Old databases used AUTOINCREMENT for Client.id. Preserve those numbers
    // so a historical client #21 stays #21 after this migration.
    final stillPending = <Map<String, dynamic>>[];
    for (final row in pending) {
      final legacyId = _positiveInt(row['id']);
      if (legacyId > 0 && legacyId < 100000 && usedCodes.add(legacyId)) {
        await executor.update(
          'Client',
          {'client_code': legacyId},
          where: 'id = ?',
          whereArgs: [row['id']],
        );
        if (legacyId > highestCode) highestCode = legacyId;
      } else {
        stillPending.add(row);
      }
    }

    for (final row in stillPending) {
      do {
        highestCode++;
      } while (usedCodes.contains(highestCode));
      usedCodes.add(highestCode);
      await executor.update(
        'Client',
        {'client_code': highestCode},
        where: 'id = ?',
        whereArgs: [row['id']],
      );
    }

    final sequenceRows = await executor.query(
      'ClientCodeSequence',
      columns: ['last_code'],
      where: 'id = 1',
      limit: 1,
    );
    final previousHighWater = sequenceRows.isEmpty
        ? 0
        : _positiveInt(sequenceRows.first['last_code']);
    if (highestCode > previousHighWater) {
      await executor.update('ClientCodeSequence', {
        'last_code': highestCode,
      }, where: 'id = 1');
    }
  }

  Future<int> _reserveNextClientCode(DatabaseExecutor executor) async {
    await _ensureClientCodeInfrastructure(executor);
    final sequenceRows = await executor.query(
      'ClientCodeSequence',
      columns: ['last_code'],
      where: 'id = 1',
      limit: 1,
    );
    final sequenceValue = sequenceRows.isEmpty
        ? 0
        : _positiveInt(sequenceRows.first['last_code']);
    final maxRows = await executor.rawQuery(
      'SELECT MAX(client_code) AS max_code FROM Client',
    );
    final maxExisting = maxRows.isEmpty
        ? 0
        : _positiveInt(maxRows.first['max_code']);
    final nextCode =
        (sequenceValue > maxExisting ? sequenceValue : maxExisting) + 1;
    await executor.update('ClientCodeSequence', {
      'last_code': nextCode,
    }, where: 'id = 1');
    return nextCode;
  }

  /// Adds the immutable, user-facing order number infrastructure.  [id] can be
  /// a large distributed sync key; [order_code] is the short number people see.
  Future<void> _ensureOrderCodeInfrastructure(DatabaseExecutor executor) async {
    try {
      await executor.execute(
        'ALTER TABLE Commandes ADD COLUMN order_code INTEGER NOT NULL DEFAULT 0;',
      );
    } catch (_) {
      // The column already exists on new and upgraded databases.
    }
    await executor.execute('''
      CREATE TABLE IF NOT EXISTS OrderCodeSequence (
        id INTEGER PRIMARY KEY CHECK (id = 1),
        last_code INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await executor.insert('OrderCodeSequence', {
      'id': 1,
      'last_code': 0,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  /// Gives restored or legacy orders a permanent display number once.  Old
  /// AUTOINCREMENT IDs such as #21 are preserved; distributed IDs get #22...
  /// based on creation order.
  Future<void> _backfillOrderCodes(DatabaseExecutor executor) async {
    await _ensureOrderCodeInfrastructure(executor);
    final rows = await executor.query(
      'Commandes',
      columns: ['id', 'order_code', 'created_at', 'updated_at'],
      orderBy:
          "COALESCE(NULLIF(TRIM(created_at), ''), NULLIF(TRIM(updated_at), ''), CAST(id AS TEXT)) ASC, id ASC",
    );
    if (rows.isEmpty) return;

    final usedCodes = <int>{};
    final pending = <Map<String, dynamic>>[];
    var highestCode = 0;

    for (final source in rows) {
      final row = Map<String, dynamic>.from(source);
      final code = _positiveInt(row['order_code']);
      if (code > 0 && usedCodes.add(code)) {
        if (code > highestCode) highestCode = code;
      } else {
        pending.add(row);
      }
    }

    final stillPending = <Map<String, dynamic>>[];
    for (final row in pending) {
      final legacyId = _positiveInt(row['id']);
      if (legacyId > 0 && legacyId < 100000 && usedCodes.add(legacyId)) {
        await executor.update(
          'Commandes',
          {'order_code': legacyId},
          where: 'id = ?',
          whereArgs: [row['id']],
        );
        if (legacyId > highestCode) highestCode = legacyId;
      } else {
        stillPending.add(row);
      }
    }

    for (final row in stillPending) {
      do {
        highestCode++;
      } while (usedCodes.contains(highestCode));
      usedCodes.add(highestCode);
      await executor.update(
        'Commandes',
        {'order_code': highestCode},
        where: 'id = ?',
        whereArgs: [row['id']],
      );
    }

    final sequenceRows = await executor.query(
      'OrderCodeSequence',
      columns: ['last_code'],
      where: 'id = 1',
      limit: 1,
    );
    final previousHighWater = sequenceRows.isEmpty
        ? 0
        : _positiveInt(sequenceRows.first['last_code']);
    if (highestCode > previousHighWater) {
      await executor.update('OrderCodeSequence', {
        'last_code': highestCode,
      }, where: 'id = 1');
    }
  }

  Future<int> _reserveNextOrderCode(DatabaseExecutor executor) async {
    await _ensureOrderCodeInfrastructure(executor);
    final sequenceRows = await executor.query(
      'OrderCodeSequence',
      columns: ['last_code'],
      where: 'id = 1',
      limit: 1,
    );
    final sequenceValue = sequenceRows.isEmpty
        ? 0
        : _positiveInt(sequenceRows.first['last_code']);
    final maxRows = await executor.rawQuery(
      'SELECT MAX(order_code) AS max_code FROM Commandes',
    );
    final maxExisting = maxRows.isEmpty
        ? 0
        : _positiveInt(maxRows.first['max_code']);
    final nextCode =
        (sequenceValue > maxExisting ? sequenceValue : maxExisting) + 1;
    await executor.update('OrderCodeSequence', {
      'last_code': nextCode,
    }, where: 'id = 1');
    return nextCode;
  }

  Future<List<Map<String, dynamic>>> readClient() async {
    Database? myDb = await db;
    return await myDb!.rawQuery('SELECT * FROM Client');
  }

  /// Client primary keys are intentionally large distributed IDs so records
  /// created offline on two devices cannot collide.  Screens and documents
  /// must show a short, human-friendly number instead of exposing that key.
  ///
  /// This method leaves [readClient] unchanged because synchronisation needs
  /// the exact database rows, without this computed display-only field.
  Future<List<Map<String, dynamic>>> readClientsForDisplay() async {
    final myDb = await db;
    if (myDb == null) return [];
    await _backfillClientCodes(myDb);
    return _queryClientsForDisplay(database: myDb);
  }

  Future<List<Map<String, dynamic>>> _queryClientsForDisplay({
    Database? database,
    String? whereClause,
    List<Object?>? whereArgs,
  }) async {
    final myDb = database ?? await db;
    if (myDb == null) return [];

    final where = (whereClause ?? '').trim();
    final filter = where.isEmpty ? '' : 'WHERE $where';
    return myDb.rawQuery('''
      SELECT c.*,
        c.client_code AS display_number
      FROM Client AS c
      $filter
      ORDER BY c.client_code ASC, c.id ASC
      ''', whereArgs);
  }

  Future<int> insertClient(
    String firstname,
    String lastname,
    String phone1,
    String phone2,
    String email,
    String address, [
    String nif = '',
    String nis = '',
    String rc = '',
    String ai = '',
  ]) async {
    Database? myDb = await db;
    if (myDb == null) throw StateError('قاعدة بيانات الزبائن غير متاحة');
    final clientId = _nextDistributedId();
    await myDb.transaction((txn) async {
      await _backfillClientCodes(txn);
      final clientCode = await _reserveNextClientCode(txn);
      await txn.insert('Client', {
        'id': clientId,
        'client_code': clientCode,
        'firstname': firstname,
        'lastname': lastname,
        'phone1': phone1,
        'phone2': phone2,
        'email': email,
        'address': address,
        'nif': nif,
        'nis': nis,
        'rc': rc,
        'ai': ai,
        'created_at': now,
        'updated_at': now,
        'creation_platform': _currentCreationPlatform,
      });
    });
    CloudSyncService().notifyChangeImmediate();
    return clientId;
  }

  Future<int> updateClient(
    int id,
    String firstname,
    String lastname,
    String phone1,
    String phone2,
    String email,
    String address,
    String updatedAt, [
    String nif = '',
    String nis = '',
    String rc = '',
    String ai = '',
  ]) async {
    Database? myDb = await db;
    var res = await myDb!.update(
      'Client',
      {
        'firstname': firstname,
        'lastname': lastname,
        'phone1': phone1,
        'phone2': phone2,
        'email': email,
        'address': address,
        'nif': nif,
        'nis': nis,
        'rc': rc,
        'ai': ai,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    CloudSyncService().notifyChangeImmediate();
    return res;
  }

  Future<int> updateClientCoordinates(
    int id,
    double latitude,
    double longitude,
  ) async {
    Database? myDb = await db;
    if (myDb == null) return 0;
    try {
      var res = await myDb.update(
        'Client',
        {
          'latitude': latitude,
          'longitude': longitude,
          'updated_at': DateTime.now().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [id],
      );
      CloudSyncService().notifyChangeImmediate();
      return res;
    } catch (_) {
      return 0;
    }
  }

  Future<int> deleteClient(dynamic id) {
    return _retryAfterDatabaseMove(() => _deleteClientOnce(id));
  }

  String get _currentCreationPlatform {
    final user = FirebaseAuth.instance.currentUser;
    final email = user?.email ?? '';
    final platformStr = kIsWeb
        ? 'ÙˆÙŠØ¨'
        : (Platform.isWindows || Platform.isLinux || Platform.isMacOS
              ? 'ÙƒÙ…Ø¨ÙŠÙˆØªØ±'
              : 'Ù‡Ø§ØªÙ');
    if (email.isNotEmpty) {
      final namePart = email.split('@').first;
      return '$namePart ($platformStr)';
    }
    return platformStr;
  }

  Future<int> _deleteClientOnce(dynamic id) async {
    Database? myDb = await db;
    if (myDb == null) return 0;
    // Old installations may not have opened the database since deletion
    // tracking was introduced. Ensure the Client delete creates a tombstone
    // before it is queued for Firebase.
    await _ensureSyncTombstoneInfrastructure(myDb);
    final parsedInt = id is num
        ? id.toInt()
        : int.tryParse(id.toString().trim());
    final strVal = id.toString().trim();
    int res = 0;
    if (parsedInt != null) {
      res = await myDb.rawDelete(
        'DELETE FROM Client WHERE id = ? OR CAST(id AS TEXT) = ?',
        [parsedInt, strVal],
      );
    } else {
      res = await myDb.rawDelete(
        'DELETE FROM Client WHERE CAST(id AS TEXT) = ?',
        [strVal],
      );
    }
    if (res > 0) {
      CloudSyncService().notifyChangeImmediate();
    }
    return res;
  }

  //////////////////////////////////// Measurements //////////////////////////////////////
  Future<int> insertMeasurement(Map<String, dynamic> data) async {
    Database? myDb = await db;
    var res = await myDb!.insert('Measurements', _withDistributedId(data));
    CloudSyncService().notifyChange();
    return res;
  }

  Future<List<Map<String, dynamic>>> readMeasurements() async {
    Database? myDb = await db;
    return await myDb!.query('Measurements', orderBy: 'id DESC');
  }

  Future<int> deleteMeasurement(int id) async {
    Database? myDb = await db;
    var res = await myDb!.delete(
      'Measurements',
      where: 'id = ?',
      whereArgs: [id],
    );
    CloudSyncService().notifyChange();
    return res;
  }

  Future<List<Map<String, dynamic>>> searchClient(String query) async {
    final dbClient = await db;
    List<String> terms = query
        .trim()
        .split(RegExp(r'\s+'))
        .where((s) => s.isNotEmpty)
        .toList();
    if (terms.isEmpty) {
      return await dbClient!.rawQuery('SELECT * FROM Client');
    }

    String whereClause = terms
        .map((_) {
          return "(firstname LIKE ? OR lastname LIKE ? OR phone1 LIKE ? OR phone2 LIKE ? OR address LIKE ?)";
        })
        .join(" AND ");

    List<String> whereArgs = [];
    for (String term in terms) {
      whereArgs.addAll(['%$term%', '%$term%', '%$term%', '%$term%', '%$term%']);
    }

    return await dbClient!.rawQuery(
      'SELECT * FROM Client WHERE $whereClause',
      whereArgs,
    );
  }

  /// Search variant for customer-facing lists.  The returned maps contain
  /// [display_number], while [id] remains the internal foreign-key value.
  Future<List<Map<String, dynamic>>> searchClientsForDisplay(
    String query,
  ) async {
    final myDb = await db;
    if (myDb == null) return [];
    await _backfillClientCodes(myDb);
    final terms = query
        .trim()
        .split(RegExp(r'\s+'))
        .where((term) => term.isNotEmpty)
        .toList();
    if (terms.isEmpty) return _queryClientsForDisplay(database: myDb);

    final whereClause = terms
        .map(
          (_) =>
              '(c.firstname LIKE ? OR c.lastname LIKE ? OR c.phone1 LIKE ? OR c.phone2 LIKE ? OR c.address LIKE ?)',
        )
        .join(' AND ');
    final whereArgs = <Object?>[];
    for (final term in terms) {
      whereArgs.addAll(['%$term%', '%$term%', '%$term%', '%$term%', '%$term%']);
    }
    return _queryClientsForDisplay(
      database: myDb,
      whereClause: whereClause,
      whereArgs: whereArgs,
    );
  }

  Future<List<Map<String, dynamic>>> getClientById(int id) async {
    final dbclient = await db;
    return await dbclient!.query('Client', where: 'id = ?', whereArgs: [id]);
  }

  ///////////////////////////////// Projects ////////////////////////////////
  Future<int> insertProject(
    String name,
    int clientId,
    String? description,
  ) async {
    Database? myDb = await db;
    final now = DateTime.now().toIso8601String();
    var res = await myDb!.rawInsert(
      'INSERT INTO Projects (id, name, client_id, description, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?)',
      [_nextDistributedId(), name, clientId, description, now, now],
    );
    CloudSyncService().notifyChangeImmediate();
    return res;
  }

  Future<int> updateProject(
    int id,
    String name,
    int clientId,
    String? description,
  ) async {
    Database? myDb = await db;
    var res = await myDb!.update(
      'Projects',
      {
        'name': name,
        'client_id': clientId,
        'description': description,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    CloudSyncService().notifyChangeImmediate();
    return res;
  }

  Future<int> deleteProject(int id) async {
    Database? myDb = await db;
    await myDb!.rawUpdate(
      'UPDATE Commandes SET project_id = NULL WHERE project_id = ?',
      [id],
    );
    var res = await myDb.rawDelete('DELETE FROM Projects WHERE id = ?', [id]);
    CloudSyncService().notifyChangeImmediate();
    return res;
  }

  Future<List<Map<String, dynamic>>> readProjects() async {
    Database? myDb = await db;
    return await myDb!.rawQuery('''
      SELECT p.*, c.firstname, c.lastname, c.phone1 as phone
      FROM Projects p
      INNER JOIN Client c ON p.client_id = c.id
      ORDER BY p.updated_at DESC
    ''');
  }

  Future<List<Map<String, dynamic>>> searchProjects(String query) async {
    Database? myDb = await db;
    List<String> terms = query
        .trim()
        .split(RegExp(r'\s+'))
        .where((s) => s.isNotEmpty)
        .toList();
    if (terms.isEmpty) {
      return await readProjects();
    }

    String whereClause = terms
        .map((_) {
          return "(p.name LIKE ? OR c.firstname LIKE ? OR c.lastname LIKE ? OR p.description LIKE ?)";
        })
        .join(" AND ");

    List<String> whereArgs = [];
    for (String term in terms) {
      whereArgs.addAll(['%$term%', '%$term%', '%$term%', '%$term%']);
    }

    return await myDb!.rawQuery('''
      SELECT p.*, c.firstname, c.lastname, c.phone1 as phone
      FROM Projects p
      INNER JOIN Client c ON p.client_id = c.id
      WHERE $whereClause
      ORDER BY p.updated_at DESC
    ''', whereArgs);
  }

  Future<Map<String, dynamic>?> readProjectById(int id) async {
    Database? myDb = await db;
    final list = await myDb!.rawQuery(
      '''
      SELECT p.*, c.firstname, c.lastname, c.phone1 as phone, c.email
      FROM Projects p
      INNER JOIN Client c ON p.client_id = c.id
      WHERE p.id = ?
    ''',
      [id],
    );
    return list.isNotEmpty ? list.first : null;
  }

  Future<List<Map<String, dynamic>>> readCommandesForProject(
    int projectId,
  ) async {
    final myDb = await db;
    if (myDb == null) return [];
    await _backfillOrderCodes(myDb);
    return await myDb.rawQuery(
      '''
      SELECT co.*,
        co.order_code AS display_number,
        cl.firstname, cl.lastname 
      FROM Commandes co
      INNER JOIN Client cl ON co.client_id = cl.id
      WHERE co.project_id = ?
      ORDER BY co.created_at DESC
    ''',
      [projectId],
    );
  }

  Future<List<Map<String, dynamic>>> readProjectsForClient(int clientId) async {
    Database? myDb = await db;
    return await myDb!.rawQuery(
      'SELECT * FROM Projects WHERE client_id = ? ORDER BY updated_at DESC',
      [clientId],
    );
  }

  ///////////////////////////////// Commande ////////////////////////////////
  Future<List<Map<String, dynamic>>> readCommande() async {
    Database? myDb = await db;
    return await myDb!.rawQuery('SELECT * FROM Commandes');
  }

  Future<List<Map<String, dynamic>>> readCommandesWithClients() async {
    final myDb = await db;
    if (myDb == null) return [];
    await _backfillOrderCodes(myDb);
    return await myDb.rawQuery('''
      SELECT c.*,
        c.order_code AS display_number,
        COALESCE(NULLIF(TRIM(c.created_at), ''), NULLIF(TRIM(c.updated_at), '')) as created_at,
        cl.firstname, cl.lastname, cl.phone1 as phone,
        cl.address as client_address,
        p.name as project_name,
        p.description as project_description
      FROM Commandes c
      LEFT JOIN Client cl ON c.client_id = cl.id
      LEFT JOIN Projects p ON c.project_id = p.id
      ORDER BY COALESCE(NULLIF(TRIM(c.created_at), ''), NULLIF(TRIM(c.updated_at), ''), c.id) DESC
    ''');
  }

  Future<int> updateCommandeStatus(
    int id,
    String newStatus, {
    bool skipAllocationSync = false,
  }) async {
    Database? myDb = await db;
    var res = await myDb!.update(
      'Commandes',
      {'status': newStatus},
      where: 'id = ?',
      whereArgs: [id],
    );

    if (!skipAllocationSync) {
      await _syncAllocationsFromOrderStatus(id, newStatus);
    }

    // The local database is authoritative for the current action. Cloud
    // delivery continues in the background and must never freeze the UI.
    unawaited(_uploadOrderStatusToCloud(id, newStatus));
    CloudSyncService().notifyChange();
    return res;
  }

  Future<void> _uploadOrderStatusToCloud(
    int orderId,
    String status, {
    int? clientId,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final workshopId = prefs.getString('workshop_code');
      if (workshopId != null && workshopId.isNotEmpty) {
        final payload = <String, dynamic>{
          'id': orderId,
          'status': status,
          'updated_at': FieldValue.serverTimestamp(),
        };
        if (clientId != null) {
          payload['client_id'] = clientId;
        }
        await FirebaseFirestore.instance
            .collection('workshops')
            .doc(workshopId)
            .collection('orders_status')
            .doc(orderId.toString())
            .set(payload, SetOptions(merge: true))
            .timeout(const Duration(seconds: 10));
        debugPrint(
          '--- SqlDatabase: Uploaded order status $orderId ($status, client: $clientId) to cloud ---',
        );
      }
    } catch (e) {
      debugPrint('Error uploading order status to cloud: $e');
    }
  }

  /// Returns true only when cloud data changed a local order.
  Future<bool> syncOrdersStatusFromCloud({
    Iterable<Map<String, dynamic>>? changedRows,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final workshopId = prefs.getString('workshop_code');
    if (workshopId == null || workshopId.isEmpty) return false;

    try {
      Database? myDb = await db;
      if (myDb == null) return false;
      var didChange = false;

      final rows =
          changedRows ??
          (await FirebaseFirestore.instance
                  .collection('workshops')
                  .doc(workshopId)
                  .collection('orders_status')
                  .get())
              .docs
              .map(
                (doc) => <String, dynamic>{
                  '__order_status_id': doc.id,
                  ...doc.data(),
                },
              );

      for (final data in rows) {
        final orderId = int.tryParse(
          data['__order_status_id']?.toString() ?? data['id']?.toString() ?? '',
        );
        if (orderId == null) continue;
        final cloudStatus = data['status']?.toString() ?? '';
        final cloudClientId = (data['client_id'] as num?)?.toInt();

        final existing = await myDb.query(
          'Commandes',
          where: 'id = ?',
          whereArgs: [orderId],
        );
        if (existing.isNotEmpty) {
          final currentStatus = existing.first['status']?.toString() ?? '';
          final currentClientId = (existing.first['client_id'] as num?)
              ?.toInt();
          final updateMap = <String, dynamic>{};

          if (cloudStatus.isNotEmpty && currentStatus != cloudStatus) {
            updateMap['status'] = cloudStatus;
          }
          if (cloudClientId != null && cloudClientId != currentClientId) {
            updateMap['client_id'] = cloudClientId;
          }

          if (updateMap.isNotEmpty) {
            await myDb.update(
              'Commandes',
              updateMap,
              where: 'id = ?',
              whereArgs: [orderId],
            );
            if (updateMap.containsKey('status')) {
              await _syncAllocationsFromOrderStatus(orderId, cloudStatus);
            }
            didChange = true;
          }
        }
      }
      debugPrint(
        '--- SqlDatabase: Synced orders status from cloud successfully ---',
      );
      return didChange;
    } catch (e) {
      debugPrint('Error syncing orders status from cloud: $e');
      return false;
    }
  }

  Future<void> _uploadConfirmedMeasurementsToCloud(
    int detailId,
    String instancesJson,
    String confirmedJson,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final workshopId = prefs.getString('workshop_code');
      if (workshopId != null && workshopId.isNotEmpty) {
        await FirebaseFirestore.instance
            .collection('workshops')
            .doc(workshopId)
            .collection('confirmed_measurements')
            .doc(detailId.toString())
            .set({
              'id': detailId,
              'instances_json': instancesJson,
              'confirmed_mesures_json': confirmedJson,
              'updated_at': FieldValue.serverTimestamp(),
            }, SetOptions(merge: true));
        debugPrint(
          '--- SqlDatabase: Uploaded confirmed measurements for detail $detailId to cloud ---',
        );
      }
    } catch (e) {
      debugPrint('Error uploading confirmed measurements to cloud: $e');
    }
  }

  Future<void> syncConfirmedMeasurementsFromCloud({
    Iterable<Map<String, dynamic>>? changedRows,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final workshopId = prefs.getString('workshop_code');
    if (workshopId == null || workshopId.isEmpty) return;

    try {
      Database? myDb = await db;
      if (myDb == null) return;

      final rows =
          changedRows ??
          (await FirebaseFirestore.instance
                  .collection('workshops')
                  .doc(workshopId)
                  .collection('confirmed_measurements')
                  .get())
              .docs
              .map(
                (doc) => <String, dynamic>{
                  '__measurement_id': doc.id,
                  ...doc.data(),
                },
              );

      for (final data in rows) {
        final detailId = int.tryParse(
          data['__measurement_id']?.toString() ?? data['id']?.toString() ?? '',
        );
        if (detailId == null) continue;
        final instancesStr = data['instances_json']?.toString() ?? '';
        final confirmedStr = data['confirmed_mesures_json']?.toString() ?? '';
        if (instancesStr.isEmpty && confirmedStr.isEmpty) continue;

        final existing = await myDb.query(
          'Commandes_details',
          where: 'id = ?',
          whereArgs: [detailId],
        );
        if (existing.isNotEmpty) {
          Map<String, dynamic> updates = {};
          if (instancesStr.isNotEmpty) updates['instances_json'] = instancesStr;
          if (confirmedStr.isNotEmpty)
            updates['confirmed_mesures_json'] = confirmedStr;

          if (updates.isNotEmpty) {
            await myDb.update(
              'Commandes_details',
              updates,
              where: 'id = ?',
              whereArgs: [detailId],
            );
          }
        }
      }
      debugPrint(
        '--- SqlDatabase: Synced confirmed measurements from cloud successfully ---',
      );
    } catch (e) {
      debugPrint('Error syncing confirmed measurements from cloud: $e');
    }
  }

  Future<int> updateCommandeDetailConfirmedMesures(
    int detailId,
    String instancesJson,
    String confirmedJson,
  ) async {
    Database? myDb = await db;
    if (myDb == null) return 0;

    var res = await myDb.update(
      'Commandes_details',
      {
        'instances_json': instancesJson,
        'confirmed_mesures_json': confirmedJson,
      },
      where: 'id = ?',
      whereArgs: [detailId],
    );

    await _uploadConfirmedMeasurementsToCloud(
      detailId,
      instancesJson,
      confirmedJson,
    );
    CloudSyncService().notifyChange();
    return res;
  }

  Future<void> _syncAllocationsFromOrderStatus(
    int orderId,
    String status,
  ) async {
    Database? myDb = await db;
    if (myDb == null) return;

    final nowStr = DateTime.now().toIso8601String();
    final details = await readCommandeDetails(orderId);
    if (details.isEmpty) return;
    final allocationIdsToUpload = <int>{};

    final sLower = status.trim().toLowerCase();

    final isMfgAll =
        sLower.contains('full manufacturing') ||
        sLower.contains('ØªØµÙ†ÙŠØ¹ ÙƒÙ„ÙŠ') ||
        sLower.contains('Ø§Ù„ØªØµÙ†ÙŠØ¹ Ø§Ù„ÙƒÙ„ÙŠ') ||
        sLower.contains('fabrication totale') ||
        sLower.contains('full distribution') ||
        sLower.contains('ØªÙˆØ²ÙŠØ¹ ÙƒÙ„ÙŠ') ||
        sLower.contains('Ø§Ù„ØªÙˆØ²ÙŠØ¹ Ø§Ù„ÙƒÙ„ÙŠ') ||
        sLower.contains('livraison totale') ||
        sLower.contains('livrÃ©') ||
        sLower.contains('installation') ||
        sLower.contains('Ø§Ù„ØªØ±ÙƒÙŠØ¨') ||
        sLower.contains('pose') ||
        sLower.contains('reserve') ||
        sLower.contains('Ù…Ø­Ø¬ÙˆØ²Ø©') ||
        sLower.contains('done') ||
        sLower.contains('Ù…Ù†ØªÙ‡ÙŠØ©') ||
        sLower.contains('ØªÙ…Øª');

    final isDistAll =
        sLower.contains('full distribution') ||
        sLower.contains('ØªÙˆØ²ÙŠØ¹ ÙƒÙ„ÙŠ') ||
        sLower.contains('Ø§Ù„ØªÙˆØ²ÙŠØ¹ Ø§Ù„ÙƒÙ„ÙŠ') ||
        sLower.contains('livraison totale') ||
        sLower.contains('livrÃ©') ||
        sLower.contains('installation') ||
        sLower.contains('Ø§Ù„ØªØ±ÙƒÙŠØ¨') ||
        sLower.contains('pose') ||
        sLower.contains('reserve') ||
        sLower.contains('Ù…Ø­Ø¬ÙˆØ²Ø©') ||
        sLower.contains('done') ||
        sLower.contains('Ù…Ù†ØªÙ‡ÙŠØ©') ||
        sLower.contains('ØªÙ…Øª');

    final isMfgPartial =
        sLower.contains('partial manufacturing') ||
        sLower.contains('ØªØµÙ†ÙŠØ¹ Ø¬Ø²Ø¦ÙŠ') ||
        sLower.contains('Ø§Ù„ØªØµÙ†ÙŠØ¹ Ø§Ù„Ø¬Ø²Ø¦ÙŠ');
    final isDistPartial =
        sLower.contains('partial distribution') ||
        sLower.contains('ØªÙˆØ²ÙŠØ¹ Ø¬Ø²Ø¦ÙŠ') ||
        sLower.contains('Ø§Ù„ØªÙˆØ²ÙŠØ¹ Ø§Ù„Ø¬Ø²Ø¦ÙŠ');

    final isPreMfg =
        sLower == 'pending' ||
        sLower == 'draft' ||
        sLower == 'new' ||
        sLower == 'confirmed' ||
        sLower == 'in progress' ||
        sLower.contains('attente') ||
        sLower.contains('Ø§Ù†ØªØ¸Ø§Ø±') ||
        sLower.contains('Ù…Ø¤ÙƒØ¯') ||
        sLower.contains('Ù‚ÙŠØ§Ø³Ø§Øª');

    for (var i = 0; i < details.length; i++) {
      final detailId = (details[i]['id'] as num?)?.toInt() ?? 0;
      if (detailId <= 0) continue;
      final allocs = await readWorkerAllocations(detailId);
      for (var j = 0; j < allocs.length; j++) {
        final allocId = (allocs[j]['id'] as num?)?.toInt() ?? 0;
        if (allocId <= 0) continue;
        // Re-read the current DB row to check existing timestamps before overwriting
        final currentRows = await myDb.query(
          'WorkerAllocations',
          where: 'id = ?',
          whereArgs: [allocId],
        );
        if (currentRows.isEmpty) continue;
        final current = currentRows.first;
        Map<String, dynamic> updates = {};
        final alreadyTransferred =
            (current['is_transferred_to_dist'] as num?)?.toInt() == 1;

        if (alreadyTransferred && isPreMfg) {
          continue;
        }

        if (isPreMfg) {
          updates['is_manufactured'] = 0;
          updates['manufactured_at'] = null;
          updates['is_glass_installed'] = 0;
          updates['glass_installed_at'] = null;
          updates['is_distributed'] = 0;
          updates['distributed_at'] = null;
          updates['is_transferred_to_dist'] = 0;
          updates['transferred_at'] = null;
          updates['is_installed'] = 0;
          updates['installed_at'] = null;
          updates['is_completed'] = 0;
          updates['completed_at'] = null;
          updates['has_reserve'] = 0;
          updates['reserve_notes'] = null;
          updates['reserve_at'] = null;
        } else if (isMfgAll || (isMfgPartial && i == 0 && j == 0)) {
          updates['is_manufactured'] = 1;
          // âœ… Only set timestamp if not already recorded (preserve the exact button-press moment)
          if (current['manufactured_at'] == null ||
              current['manufactured_at'].toString().isEmpty) {
            updates['manufactured_at'] = nowStr;
          }
          updates['is_glass_installed'] = 1;
          // âœ… Only set timestamp if not already recorded
          if (current['glass_installed_at'] == null ||
              current['glass_installed_at'].toString().isEmpty) {
            updates['glass_installed_at'] = nowStr;
          }
        }

        if (isDistAll || (isDistPartial && i == 0 && j == 0)) {
          updates['is_distributed'] = 1;
          // âœ… Only set timestamp if not already recorded
          if (current['distributed_at'] == null ||
              current['distributed_at'].toString().isEmpty) {
            updates['distributed_at'] = nowStr;
          }
        }

        if (updates.isNotEmpty) {
          updates['updated_at'] = nowStr;
          await myDb.update(
            'WorkerAllocations',
            updates,
            where: 'id = ?',
            whereArgs: [allocId],
          );
          allocationIdsToUpload.add(allocId);
        }
      }
    }

    if (allocationIdsToUpload.isNotEmpty) {
      unawaited(
        Future.wait(allocationIdsToUpload.map(_uploadAllocationStatusToCloud)),
      );
    }
  }

  /// Ù…Ø²Ø§Ù…Ù†Ø© Ø¢Ù„ÙŠØ© Ù„Ø¬Ù…ÙŠØ¹ Ø§Ù„Ø¥Ø³Ù†Ø§Ø¯Ø§Øª Ø¨Ù†Ø§Ø¡Ù‹ Ø¹Ù„Ù‰ Ø­Ø§Ù„Ø§Øª Ø¬Ù…ÙŠØ¹ Ø§Ù„Ø·Ù„Ø¨ÙŠØ§Øª Ø§Ù„Ù…Ø³Ø¬Ù„Ø©
  Future<void> syncAllAllocationsFromAllOrderStatuses() async {
    try {
      Database? myDb = await db;
      if (myDb == null) return;
      final orders = await myDb.query('Commandes');
      for (var order in orders) {
        final orderId = (order['id'] as num?)?.toInt() ?? 0;
        final status = order['status']?.toString() ?? '';
        if (orderId > 0 && status.isNotEmpty) {
          await _syncAllocationsFromOrderStatus(orderId, status);
        }
      }
    } catch (e) {
      debugPrint('syncAllAllocationsFromAllOrderStatuses error: $e');
    }
  }

  Future<int> getPriorConfirmedWindowsCount(int targetOrderId) async {
    Database? myDb = await db;
    final res = await myDb!.rawQuery(
      '''
      SELECT SUM(d.quantity) as total_windows
      FROM Commandes_details d
      JOIN Commandes c ON d.id_commandes = c.id
      WHERE c.id < ? 
        AND c.status NOT IN ('En attente', 'ÙÙŠ Ø§Ù„Ø§Ù†ØªØ¸Ø§Ø±', 'Pending', 'Draft', 'Ù…Ù„ØºØ§Ø©')
    ''',
      [targetOrderId],
    );

    if (res.isNotEmpty && res.first['total_windows'] != null) {
      return (res.first['total_windows'] as num).toInt();
    }
    return 0;
  }

  /// Returns 1-based sequential order index for display/document numbering (1, 2, 3, 4...)
  Future<int> getOrderSequenceNumber(int orderId) async {
    try {
      final myDb = await db;
      if (myDb == null) return 1;
      await _backfillOrderCodes(myDb);
      final orderRows = await myDb.query(
        'Commandes',
        columns: ['order_code'],
        where: 'id = ? OR CAST(id AS TEXT) = ?',
        whereArgs: [orderId, orderId.toString()],
        limit: 1,
      );
      if (orderRows.isEmpty) return 1;
      final code = _positiveInt(orderRows.first['order_code']);
      if (code > 0) return code;
    } catch (e) {
      debugPrint('Error computing order sequence number: $e');
    }
    return (orderId % 1000).abs();
  }

  /// Returns the immutable customer number shown in tables and documents.
  /// This must never be derived from the current row count because deletion
  /// of another client must not alter a customer's identifier.
  Future<int> getClientSequenceNumber(int clientId) async {
    if (clientId <= 0) return 0;

    try {
      final myDb = await db;
      if (myDb == null) return 0;
      await _backfillClientCodes(myDb);
      final rows = await myDb.query(
        'Client',
        columns: ['client_code'],
        where: 'id = ? OR CAST(id AS TEXT) = ?',
        whereArgs: [clientId, clientId.toString()],
        limit: 1,
      );
      if (rows.isEmpty) return 0;
      return _positiveInt(rows.first['client_code']);
    } catch (e) {
      debugPrint('Error computing client sequence number: $e');
      return 0;
    }
  }

  Future<Map<String, dynamic>?> readCommandeWithClientById(int id) async {
    final myDb = await db;
    if (myDb == null) return null;
    await _backfillOrderCodes(myDb);
    final rows = await myDb.rawQuery(
      '''
      SELECT c.*,
        c.order_code AS display_number,
        COALESCE(NULLIF(TRIM(c.created_at), ''), NULLIF(TRIM(c.updated_at), '')) as created_at,
        cl.firstname, cl.lastname, cl.phone1 as phone,
        p.name as project_name
      FROM Commandes c
      LEFT JOIN Client cl ON c.client_id = cl.id
      LEFT JOIN Projects p ON c.project_id = p.id
      WHERE c.id = ?
    ''',
      [id],
    );
    return rows.isEmpty ? null : rows.first;
  }

  Future<List<Map<String, dynamic>>> readCommandeDetails(
    dynamic idCommande,
  ) async {
    Database? myDb = await db;
    if (myDb == null) return [];
    final parsedInt = idCommande is num
        ? idCommande.toInt()
        : int.tryParse(idCommande.toString().trim());
    final strVal = idCommande.toString().trim();
    if (parsedInt != null) {
      return await myDb.query(
        'Commandes_details',
        where: 'id_commandes = ? OR CAST(id_commandes AS TEXT) = ?',
        whereArgs: [parsedInt, strVal],
        orderBy: 'id ASC',
      );
    }
    return await myDb.query(
      'Commandes_details',
      where: 'CAST(id_commandes AS TEXT) = ?',
      whereArgs: [strVal],
      orderBy: 'id ASC',
    );
  }

  // â”€â”€ WorkerAllocations Helpers â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  Future<List<Map<String, dynamic>>> readWorkerAllocations(int detailId) async {
    Database? myDb = await db;
    return await myDb!.query(
      'WorkerAllocations',
      where: 'commande_detail_id = ?',
      whereArgs: [detailId],
    );
  }

  Future<int> insertWorkerAllocation(
    int detailId,
    String workerUid,
    int quantity,
    double workerPrice, {
    int? unitIndex,
    String? unitPosition,
    int? unitWidth,
    int? unitHeight,
  }) async {
    Database? myDb = await db;
    if (myDb == null) return 0;

    // ðŸ›¡ï¸ 1. Hard constraint check: ensure total allocated quantity for this detail does not exceed detail.quantity
    final details = await myDb.query(
      'Commandes_details',
      where: 'id = ?',
      whereArgs: [detailId],
    );
    if (details.isNotEmpty) {
      final totalAllowedQty =
          (details.first['quantity'] ?? details.first['nbr'] ?? 1) as int;
      final existingAllocs = await readWorkerAllocations(detailId);

      int currentAllocatedSum = 0;
      for (var a in existingAllocs) {
        if (unitIndex != null) {
          if (a['unit_index'] == unitIndex) {
            currentAllocatedSum += (a['quantity'] as int);
          }
        } else {
          currentAllocatedSum += (a['quantity'] as int);
        }
      }

      int maxAllowed = unitIndex != null ? 1 : totalAllowedQty;
      if (currentAllocatedSum + quantity > maxAllowed) {
        throw Exception(
          'Ø§Ù„ÙƒÙ…ÙŠØ© Ø§Ù„Ù…Ø³Ù†Ø¯Ø© ØªØ¬Ø§ÙˆØ²Øª Ø§Ù„Ø­Ø¯ Ø§Ù„Ù…Ø³Ù…ÙˆØ­ Ø¨Ù‡ ($maxAllowed Ù‚Ø·Ø¹Ø©). Ø§Ù„Ù…ØªØ¨Ù‚ÙŠ Ù„Ù„Ø¥Ø³Ù†Ø§Ø¯: ${maxAllowed - currentAllocatedSum}',
        );
      }
    }

    // ðŸ›¡ï¸ 2. Clean slate initialization: reset all status flags for new allocation
    final nowStr = DateTime.now().toIso8601String();
    final Map<String, dynamic> row = {
      'commande_detail_id': detailId,
      'worker_uid': workerUid,
      'quantity': quantity,
      'worker_price': workerPrice,
      'assigned_at': nowStr,
      'is_settled': 0,
      'is_manufactured': 0,
      'manufactured_at': null,
      'is_glass_installed': 0,
      'glass_installed_at': null,
      'is_distributed': 0,
      'distributed_at': null,
      'is_transferred_to_dist': 0,
      'transferred_at': null,
      'updated_at': nowStr,
    };
    if (unitIndex != null) row['unit_index'] = unitIndex;
    if (unitPosition != null && unitPosition.isNotEmpty)
      row['unit_position'] = unitPosition;
    if (unitWidth != null && unitWidth > 0) row['unit_width'] = unitWidth;
    if (unitHeight != null && unitHeight > 0) row['unit_height'] = unitHeight;

    final res = await myDb.insert('WorkerAllocations', _withDistributedId(row));
    await _uploadAllocationStatusToCloud(res);
    CloudSyncService().notifyChange();
    return res;
  }

  Future<int> updateWorkerAllocationDetails(
    int allocationId,
    String workerUid,
    int quantity,
    double workerPrice,
  ) async {
    Database? myDb = await db;
    if (myDb == null) return 0;

    final allocRow = await myDb.query(
      'WorkerAllocations',
      where: 'id = ?',
      whereArgs: [allocationId],
    );
    if (allocRow.isNotEmpty) {
      final detailId =
          (allocRow.first['commande_detail_id'] as num?)?.toInt() ?? 0;
      final unitIndex = allocRow.first['unit_index'];
      if (detailId > 0) {
        final details = await myDb.query(
          'Commandes_details',
          where: 'id = ?',
          whereArgs: [detailId],
        );
        if (details.isNotEmpty) {
          final totalAllowedQty =
              (details.first['quantity'] ?? details.first['nbr'] ?? 1) as int;
          final existingAllocs = await readWorkerAllocations(detailId);

          int currentAllocatedSum = 0;
          for (var a in existingAllocs) {
            if ((a['id'] as num?)?.toInt() == allocationId) continue;
            if (unitIndex != null) {
              if (a['unit_index'] == unitIndex) {
                currentAllocatedSum += (a['quantity'] as int);
              }
            } else {
              currentAllocatedSum += (a['quantity'] as int);
            }
          }

          int maxAllowed = unitIndex != null ? 1 : totalAllowedQty;
          if (currentAllocatedSum + quantity > maxAllowed) {
            throw Exception(
              'Ø§Ù„ÙƒÙ…ÙŠØ© Ø§Ù„Ù…Ø³Ù†Ø¯Ø© ØªØ¬Ø§ÙˆØ²Øª Ø§Ù„Ø­Ø¯ Ø§Ù„Ù…Ø³Ù…ÙˆØ­ Ø¨Ù‡ ($maxAllowed Ù‚Ø·Ø¹Ø©). Ø§Ù„Ù…ØªØ¨Ù‚ÙŠ Ù„Ù„Ø¥Ø³Ù†Ø§Ø¯: ${maxAllowed - currentAllocatedSum}',
            );
          }
        }
      }
    }

    final res = await myDb.update(
      'WorkerAllocations',
      {
        'worker_uid': workerUid,
        'quantity': quantity,
        'worker_price': workerPrice,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [allocationId],
    );

    await _uploadAllocationStatusToCloud(allocationId);
    CloudSyncService().notifyChange();
    return res;
  }

  Future<void> _deleteAllocationFromCloud(int allocationId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final workshopId = prefs.getString('workshop_code');
      final userRole = prefs.getString('user_role') ?? 'worker';
      if (workshopId != null && workshopId.isNotEmpty) {
        final workshopRef = FirebaseFirestore.instance
            .collection('workshops')
            .doc(workshopId);

        // 1. ÙƒØªØ§Ø¨Ø© Ø¹Ù„Ø§Ù…Ø© Ø­Ø°Ù Ø¯Ø§Ø¦Ù…Ø© (tombstone) ØªÙ…Ù†Ø¹ restore Ù…Ù† Ø¥Ø¹Ø§Ø¯Ø© Ø§Ù„Ø¥Ø³Ù†Ø§Ø¯ Ø§Ù„Ù…Ø­Ø°ÙˆÙ
        try {
          await workshopRef
              .collection('deleted_allocations')
              .doc(allocationId.toString())
              .set({
                'deleted_at': FieldValue.serverTimestamp(),
                'id': allocationId,
              })
              .timeout(const Duration(seconds: 5));
        } catch (e) {
          debugPrint('Error writing deleted_allocations tombstone: $e');
        }

        // 2. Delete from worker_allocations_status
        try {
          await workshopRef
              .collection('worker_allocations_status')
              .doc(allocationId.toString())
              .delete()
              .timeout(const Duration(seconds: 5));
        } catch (e) {
          debugPrint('Error deleting status doc: $e');
        }

        // 3. Delete from allocations subcollection if present
        try {
          await workshopRef
              .collection('allocations')
              .doc(allocationId.toString())
              .delete()
              .timeout(const Duration(seconds: 5));
        } catch (_) {}

        // 4. Clean up from backup chunks (only for manager/admin)
        if (userRole != 'worker') {
          try {
            final chunksSnap = await workshopRef
                .collection('backups')
                .doc('latest')
                .collection('chunks')
                .get()
                .timeout(const Duration(seconds: 5));

            for (var chunkDoc in chunksSnap.docs) {
              final data = chunkDoc.data();
              String table = data['table']?.toString() ?? '';
              if (table.isEmpty) {
                table = chunkDoc.id.replaceAll(RegExp(r'_\d+$'), '');
              }
              if (table == 'WorkerAllocations') {
                List<dynamic> rows = List<dynamic>.from(data['data'] ?? []);
                final int initialLen = rows.length;
                rows.removeWhere(
                  (r) =>
                      r is Map && ((r['id'] as num?)?.toInt() == allocationId),
                );
                if (rows.length < initialLen) {
                  if (rows.isEmpty) {
                    await chunkDoc.reference.delete().timeout(
                      const Duration(seconds: 5),
                    );
                  } else {
                    await chunkDoc.reference
                        .update({'data': rows})
                        .timeout(const Duration(seconds: 5));
                  }
                }
              }
            }
          } catch (e) {
            debugPrint('Error updating chunks for deleted allocation: $e');
          }
        }
        debugPrint(
          '--- SqlDatabase: Deleted allocation $allocationId from cloud ---',
        );
      }
    } catch (e) {
      debugPrint('Error deleting allocation from cloud: $e');
    }
  }

  Future<int> deleteWorkerAllocation(int allocationId) async {
    Database? myDb = await db;
    if (myDb == null) return 0;

    int orderId = 0;
    try {
      final allocRow = await myDb.query(
        'WorkerAllocations',
        where: 'id = ?',
        whereArgs: [allocationId],
      );
      if (allocRow.isNotEmpty) {
        final detailId =
            (allocRow.first['commande_detail_id'] as num?)?.toInt() ?? 0;
        if (detailId > 0) {
          final detailRow = await myDb.query(
            'Commandes_details',
            where: 'id = ?',
            whereArgs: [detailId],
          );
          if (detailRow.isNotEmpty) {
            orderId = (detailRow.first['id_commandes'] as num?)?.toInt() ?? 0;
          }
        }
      }
    } catch (_) {}

    // 1. Ø­Ø°Ù Ù…Ù† SQLite Ø£ÙˆÙ„Ø§Ù‹ (ÙÙˆØ±ÙŠ)
    final res = await myDb.delete(
      'WorkerAllocations',
      where: 'id = ?',
      whereArgs: [allocationId],
    );

    // 2. Ø­Ø°Ù Ù…Ù† Ø§Ù„Ø³Ø­Ø§Ø¨Ø© ÙˆØªØ³Ø¬ÙŠÙ„ Ø¹Ù„Ø§Ù…Ø© Ø§Ù„Ø­Ø°Ù Ø§Ù„Ø¯Ø§Ø¦Ù…Ø©
    await _deleteAllocationFromCloud(allocationId);

    if (orderId > 0) {
      await syncOrderAndAllocationsStatus(orderId);
    }

    // Ù…Ù„Ø§Ø­Ø¸Ø©: Ù„Ø§ Ù†Ø³ØªØ¯Ø¹ÙŠ backupToCloud() Ù‡Ù†Ø§ Ù„ØªØ¬Ù†Ø¨ Ø§Ù„ØªØ£Ø®Ø± 20+ Ø«Ø§Ù†ÙŠØ©.
    // notifyChange() ÙŠØ¹Ù…Ù„ Ø¨Ù€ debounce 1 Ø«Ø§Ù†ÙŠØ© ÙˆÙŠØ·Ù„Ù‚ _silentBackup() ØªÙ„Ù‚Ø§Ø¦ÙŠØ§Ù‹.
    CloudSyncService().notifyChange();
    return res;
  }

  /// Ø­Ø°Ù Ø¥Ø³Ù†Ø§Ø¯ Ù…Ø­Ù„ÙŠØ§Ù‹ ÙÙ‚Ø· (Ø¨Ø¯ÙˆÙ† Ø£ÙŠ Ø§ØªØµØ§Ù„ Ø³Ø­Ø§Ø¨Ø©) â€” ÙŠÙØ³ØªØ®Ø¯Ù… Ø¹Ù†Ø¯ ØªØ·Ø¨ÙŠÙ‚ tombstones Ø¨Ø¹Ø¯ Ø§Ù„Ù€ restore
  Future<void> deleteWorkerAllocationLocalOnly(int allocationId) async {
    try {
      Database? myDb = await db;
      if (myDb == null) return;
      await myDb.delete(
        'WorkerAllocations',
        where: 'id = ?',
        whereArgs: [allocationId],
      );
    } catch (e) {
      debugPrint('deleteWorkerAllocationLocalOnly error: $e');
    }
  }

  /// Ø­Ø°Ù Achat ÙˆØ¹Ù†Ø§ØµØ±Ù‡ Ù…Ø­Ù„ÙŠØ§Ù‹ ÙÙ‚Ø· (Ù„Ø§ ÙŠÙØ´ØºÙ‘Ù„ backup) â€” ÙŠÙØ³ØªØ®Ø¯Ù… Ø¨Ø¹Ø¯ restore
  Future<void> deleteAchatLocalOnly(int id) async {
    try {
      Database? myDb = await db;
      if (myDb == null) return;
      await myDb.delete('Achat_items', where: 'achat_id = ?', whereArgs: [id]);
      await myDb.delete('Achats', where: 'id = ?', whereArgs: [id]);
    } catch (e) {
      debugPrint('deleteAchatLocalOnly error: $e');
    }
  }

  /// ØªØ¹Ø·ÙŠÙ„ Ø³Ø¬Ù„ Ø²Ø¬Ø§Ø¬ Ù…Ø­Ù„ÙŠØ§Ù‹ ÙÙ‚Ø· (is_active=0) â€” ÙŠÙØ³ØªØ®Ø¯Ù… Ø¨Ø¹Ø¯ restore
  Future<void> setGlassInactiveLocalOnly(int id) async {
    try {
      Database? myDb = await db;
      if (myDb == null) return;
      await myDb.update(
        'Glass',
        {'is_active': 0},
        where: 'id = ?',
        whereArgs: [id],
      );
    } catch (e) {
      debugPrint('setGlassInactiveLocalOnly error: $e');
    }
  }

  /// ðŸ§¹ ØªØµÙÙŠØ± ÙˆØ­Ø°Ù Ø¬Ù…ÙŠØ¹ Ø§Ù„Ù…Ù‡Ø§Ù… ÙˆØ§Ù„Ø¥Ø³Ù†Ø§Ø¯Ø§Øª Ù…Ø­Ù„ÙŠØ§Ù‹ ÙˆÙÙŠ Ø§Ù„Ø³Ø­Ø§Ø¨Ø© Ù„Ù„ØªØ·ÙˆÙŠØ±
  Future<void> clearAllWorkerAllocationsFromCloudAndLocal() async {
    Database? myDb = await db;
    if (myDb != null) {
      await myDb.rawDelete('DELETE FROM WorkerAllocations');
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final workshopId = prefs.getString('workshop_code');
      final userRole = prefs.getString('user_role') ?? 'worker';
      if (workshopId != null && workshopId.isNotEmpty) {
        final workshopRef = FirebaseFirestore.instance
            .collection('workshops')
            .doc(workshopId);

        // 1. Delete all status docs
        try {
          final statusDocs = await workshopRef
              .collection('worker_allocations_status')
              .get()
              .timeout(const Duration(seconds: 5));
          for (var doc in statusDocs.docs) {
            await doc.reference.delete().timeout(const Duration(seconds: 3));
          }
        } catch (e) {
          debugPrint('Error clearing status docs: $e');
        }

        // 2. Delete all allocs docs
        try {
          final allocDocs = await workshopRef
              .collection('allocations')
              .get()
              .timeout(const Duration(seconds: 5));
          for (var doc in allocDocs.docs) {
            await doc.reference.delete().timeout(const Duration(seconds: 3));
          }
        } catch (_) {}

        // 3. Delete all WorkerAllocations chunks from backups/latest/chunks (only for manager)
        if (userRole != 'worker') {
          try {
            final chunksSnap = await workshopRef
                .collection('backups')
                .doc('latest')
                .collection('chunks')
                .get()
                .timeout(const Duration(seconds: 5));

            for (var doc in chunksSnap.docs) {
              final data = doc.data();
              String table = data['table']?.toString() ?? '';
              if (table.isEmpty) {
                table = doc.id.replaceAll(RegExp(r'_\d+$'), '');
              }
              if (table == 'WorkerAllocations') {
                await doc.reference.delete().timeout(
                  const Duration(seconds: 5),
                );
              }
            }
          } catch (e) {
            debugPrint('Error deleting chunk docs: $e');
          }

          // 4. Update latest backup metadata
          try {
            final latestRef = workshopRef.collection('backups').doc('latest');
            final latestSnap = await latestRef.get().timeout(
              const Duration(seconds: 5),
            );
            if (latestSnap.exists && latestSnap.data() != null) {
              final map = latestSnap.data()!;
              if (map.containsKey('data_json')) {
                final rawJson = map['data_json']?.toString() ?? '{}';
                try {
                  final Map<String, dynamic> allData = jsonDecode(rawJson);
                  allData['WorkerAllocations'] = [];
                  await latestRef
                      .set({
                        'data_json': jsonEncode(allData),
                        'updated_at': FieldValue.serverTimestamp(),
                      }, SetOptions(merge: true))
                      .timeout(const Duration(seconds: 5));
                } catch (e) {
                  debugPrint('Error updating cloud backup json: $e');
                }
              }
            }
          } catch (e) {
            debugPrint('Error updating latest backup doc: $e');
          }
        }
      }
    } catch (e) {
      debugPrint('Error clearing cloud allocations: $e');
    }

    CloudSyncService().notifyChange();
  }

  /// ðŸ§¹ ØªØµÙÙŠØ± Ø¨ÙŠØ§Ù†Ø§Øª Ø§Ù„ØªØ±ÙƒÙŠØ¨Ø§Øª ÙˆØ§Ù„Ø¹Ù…Ù„ÙŠØ§Øª Ø§Ù„Ø®Ø§Ø±Ø¬ÙŠØ© Ù…Ø­Ù„ÙŠØ§Ù‹ ÙˆÙÙŠ Ø§Ù„Ø³Ø­Ø§Ø¨Ø© Ù„Ù„ØªØ·ÙˆÙŠØ±
  Future<void> clearAllInstallationDataFromCloudAndLocal() async {
    Database? myDb = await db;
    if (myDb != null) {
      // 1. ØªØµÙÙŠØ± Ø­Ø§Ù„Ø§Øª Ø§Ù„ØªØ±ÙƒÙŠØ¨ ÙˆØ§Ù„ØªØ­ÙØ¸ ÙˆØ§Ù„Ø²Ø¬Ø§Ø¬ Ø¨Ø§Ù„ÙƒØ§Ù…Ù„ ÙÙŠ WorkerAllocations
      await myDb.rawUpdate('''
        UPDATE WorkerAllocations 
        SET is_transferred_to_dist = 0, transferred_at = NULL,
            is_distributed = 0, distributed_at = NULL,
            is_installed = 0, installed_at = NULL,
            is_glass_installed = 0, glass_installed_at = NULL,
            is_completed = 0, completed_at = NULL,
            has_reserve = 0, reserve_notes = NULL, reserve_at = NULL
      ''');

      // 2. ØªØµÙÙŠØ± Ø¨ÙŠØ§Ù†Ø§Øª Ø§Ø³ØªÙ„Ø§Ù… Ø§Ù„Ø²Ø¬Ø§Ø¬ ÙˆØ§Ù„Ù…Ø´ØªØ±ÙŠØ§Øª ÙˆØ§Ù„Ù†ÙˆØ§Ù‚Øµ ÙÙŠ Commandes_details
      try {
        await myDb.rawUpdate('''
          UPDATE Commandes_details 
          SET glass_status = NULL, glass_received_qty = 0, glass_received_at = NULL,
              glass_supplier = NULL, is_purchased = 0, purchase_status = NULL
        ''');
      } catch (_) {}

      // 3. Ø­Ø°Ù Ø£ÙŠ Ø³Ø¬Ù„Ø§Øª Ù…Ø³ØªÙ‚Ù„Ø© Ù„Ù„Ø²Ø¬Ø§Ø¬ ÙˆØ§Ù„Ù…Ø´ØªØ±ÙŠØ§Øª
      try {
        await myDb.rawDelete('DELETE FROM GlassOrders');
      } catch (_) {}
      try {
        await myDb.rawDelete('DELETE FROM Achats');
      } catch (_) {}
      try {
        await myDb.rawDelete('DELETE FROM Commandes_achat');
      } catch (_) {}
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final workshopId = prefs.getString('workshop_code');
      if (workshopId != null && workshopId.isNotEmpty) {
        final latestRef = FirebaseFirestore.instance
            .collection('workshops')
            .doc(workshopId)
            .collection('backups')
            .doc('latest');

        final latestSnap = await latestRef.get().timeout(
          const Duration(seconds: 5),
        );
        if (latestSnap.exists && latestSnap.data() != null) {
          final map = latestSnap.data()!;
          if (map.containsKey('data_json')) {
            final rawJson = map['data_json']?.toString() ?? '{}';
            try {
              final Map<String, dynamic> allData = jsonDecode(rawJson);
              if (allData.containsKey('WorkerAllocations') &&
                  allData['WorkerAllocations'] is List) {
                final List allocs = allData['WorkerAllocations'];
                for (var a in allocs) {
                  if (a is Map) {
                    a['is_transferred_to_dist'] = 0;
                    a['transferred_at'] = null;
                    a['is_distributed'] = 0;
                    a['distributed_at'] = null;
                    a['is_installed'] = 0;
                    a['installed_at'] = null;
                    a['is_glass_installed'] = 0;
                    a['glass_installed_at'] = null;
                    a['is_completed'] = 0;
                    a['completed_at'] = null;
                    a['has_reserve'] = 0;
                    a['reserve_notes'] = null;
                    a['reserve_at'] = null;
                  }
                }
                allData['WorkerAllocations'] = allocs;
              }
              if (allData.containsKey('Commandes_details') &&
                  allData['Commandes_details'] is List) {
                final List details = allData['Commandes_details'];
                for (var d in details) {
                  if (d is Map) {
                    d['glass_status'] = null;
                    d['glass_received_qty'] = 0;
                    d['glass_received_at'] = null;
                    d['glass_supplier'] = null;
                    d['is_purchased'] = 0;
                    d['purchase_status'] = null;
                  }
                }
                allData['Commandes_details'] = details;
              }
              allData['GlassOrders'] = [];
              allData['Achats'] = [];
              allData['Commandes_achat'] = [];

              await latestRef
                  .set({
                    'data_json': jsonEncode(allData),
                    'updated_at': FieldValue.serverTimestamp(),
                  }, SetOptions(merge: true))
                  .timeout(const Duration(seconds: 5));
            } catch (e) {
              debugPrint('Error updating cloud backup json: $e');
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Error clearing cloud installation data: $e');
    }

    CloudSyncService().notifyChange();
  }

  /// ðŸ§¹ ØªØµÙÙŠØ± Ø³Ø¬Ù„Ø§Øª Ø§Ù„Ù…Ø­Ø§Ø³Ø¨Ø© Ù…Ø­Ù„ÙŠØ§Ù‹ ÙˆÙÙŠ Ø§Ù„Ø³Ø­Ø§Ø¨Ø© Ù„Ù„ØªØ·ÙˆÙŠØ±
  Future<void> clearAllWeeklySettlementsFromCloudAndLocal() async {
    Database? myDb = await db;
    if (myDb != null) {
      await myDb.rawUpdate(
        'UPDATE WorkerAllocations SET is_settled = 0, settlement_id = NULL',
      );
      await myDb.rawUpdate(
        'UPDATE WorkerTransactions SET is_settled = 0, settlement_id = NULL',
      );
      try {
        await myDb.rawDelete('DELETE FROM WorkerSettlements');
      } catch (_) {}
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final workshopId = prefs.getString('workshop_code');
      if (workshopId != null && workshopId.isNotEmpty) {
        final latestRef = FirebaseFirestore.instance
            .collection('workshops')
            .doc(workshopId)
            .collection('backups')
            .doc('latest');

        final latestSnap = await latestRef.get();
        if (latestSnap.exists && latestSnap.data() != null) {
          final map = latestSnap.data()!;
          if (map.containsKey('data_json')) {
            final rawJson = map['data_json']?.toString() ?? '{}';
            try {
              final Map<String, dynamic> allData = jsonDecode(rawJson);
              if (allData.containsKey('WorkerAllocations') &&
                  allData['WorkerAllocations'] is List) {
                final List allocs = allData['WorkerAllocations'];
                for (var a in allocs) {
                  if (a is Map) {
                    a['is_settled'] = 0;
                    a['settlement_id'] = null;
                  }
                }
                allData['WorkerAllocations'] = allocs;
              }
              if (allData.containsKey('WorkerTransactions') &&
                  allData['WorkerTransactions'] is List) {
                final List txs = allData['WorkerTransactions'];
                for (var t in txs) {
                  if (t is Map) {
                    t['is_settled'] = 0;
                    t['settlement_id'] = null;
                  }
                }
                allData['WorkerTransactions'] = txs;
              }
              allData['WorkerSettlements'] = [];
              await latestRef.set({
                'data_json': jsonEncode(allData),
                'updated_at': FieldValue.serverTimestamp(),
              }, SetOptions(merge: true));
            } catch (e) {
              debugPrint('Error updating cloud backup json: $e');
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Error clearing cloud settlements: $e');
    }

    CloudSyncService().notifyChange();
  }

  Future<List<Map<String, dynamic>>> readWorkerUnsettledAllocations(
    String workerUid,
  ) async {
    Database? myDb = await db;
    if (myDb == null) return [];

    final cleanKey = workerUid.trim().toLowerCase();
    if (cleanKey.isEmpty) return [];

    return await myDb.rawQuery(
      '''
      SELECT wa.*, cd.window_type, cd.largeur, cd.hauteur, cd.color, cd.glass, cd.id_commandes, cd.partitions_json, cd.drawing_image_path, cd.drawing_image_base64,
             cl.firstname, cl.lastname
      FROM WorkerAllocations wa
      INNER JOIN Commandes_details cd ON wa.commande_detail_id = cd.id
      INNER JOIN Commandes c ON cd.id_commandes = c.id
      LEFT JOIN Client cl ON c.client_id = cl.id
      WHERE (
        wa.worker_uid = ?
        OR LOWER(wa.worker_uid) = ?
        OR wa.worker_uid IN (
          SELECT CAST(id AS TEXT) FROM Employees WHERE (uid = ? OR LOWER(email) = ? OR CAST(id AS TEXT) = ?)
        )
        OR wa.worker_uid IN (
          SELECT uid FROM Employees WHERE (uid = ? OR LOWER(email) = ? OR CAST(id AS TEXT) = ?)
        )
        OR wa.worker_uid IN (
          SELECT email FROM Employees WHERE (uid = ? OR LOWER(email) = ? OR CAST(id AS TEXT) = ?)
        )
      ) AND (wa.is_settled = 0 OR wa.is_settled IS NULL)
      ORDER BY wa.assigned_at DESC
    ''',
      [
        workerUid,
        cleanKey,
        cleanKey,
        cleanKey,
        cleanKey,
        cleanKey,
        cleanKey,
        cleanKey,
        cleanKey,
        cleanKey,
        cleanKey,
      ],
    );
  }

  Future<List<Map<String, dynamic>>> readWorkerSettledAllocations(
    String workerUid,
  ) async {
    Database? myDb = await db;
    if (myDb == null) return [];

    final cleanKey = workerUid.trim().toLowerCase();
    if (cleanKey.isEmpty) return [];

    return await myDb.rawQuery(
      '''
      SELECT wa.*, cd.window_type, cd.largeur, cd.hauteur, cd.color, cd.glass, cd.id_commandes, cd.partitions_json, cd.drawing_image_path, cd.drawing_image_base64,
             cl.firstname, cl.lastname
      FROM WorkerAllocations wa
      INNER JOIN Commandes_details cd ON wa.commande_detail_id = cd.id
      INNER JOIN Commandes c ON cd.id_commandes = c.id
      LEFT JOIN Client cl ON c.client_id = cl.id
      WHERE (
        wa.worker_uid = ?
        OR LOWER(wa.worker_uid) = ?
        OR wa.worker_uid IN (
          SELECT CAST(id AS TEXT) FROM Employees WHERE (uid = ? OR LOWER(email) = ? OR CAST(id AS TEXT) = ?)
        )
        OR wa.worker_uid IN (
          SELECT uid FROM Employees WHERE (uid = ? OR LOWER(email) = ? OR CAST(id AS TEXT) = ?)
        )
        OR wa.worker_uid IN (
          SELECT email FROM Employees WHERE (uid = ? OR LOWER(email) = ? OR CAST(id AS TEXT) = ?)
        )
      ) AND wa.is_settled = 1
      ORDER BY wa.settled_at DESC
    ''',
      [
        workerUid,
        cleanKey,
        cleanKey,
        cleanKey,
        cleanKey,
        cleanKey,
        cleanKey,
        cleanKey,
        cleanKey,
        cleanKey,
        cleanKey,
      ],
    );
  }

  Future<List<Map<String, dynamic>>> readWorkerSettledTransactions(
    String workerUid,
  ) async {
    Database? myDb = await db;
    if (myDb == null) return [];

    final cleanKey = workerUid.trim().toLowerCase();
    if (cleanKey.isEmpty) return [];

    return await myDb.rawQuery(
      '''
      SELECT wt.*
      FROM WorkerTransactions wt
      WHERE (
        wt.worker_uid = ?
        OR LOWER(wt.worker_uid) = ?
        OR wt.worker_uid IN (
          SELECT CAST(id AS TEXT) FROM Employees WHERE (uid = ? OR LOWER(email) = ? OR CAST(id AS TEXT) = ?)
        )
        OR wt.worker_uid IN (
          SELECT uid FROM Employees WHERE (uid = ? OR LOWER(email) = ? OR CAST(id AS TEXT) = ?)
        )
        OR wt.worker_uid IN (
          SELECT email FROM Employees WHERE (uid = ? OR LOWER(email) = ? OR CAST(id AS TEXT) = ?)
        )
      ) AND wt.is_settled = 1
      ORDER BY wt.settled_at DESC
    ''',
      [
        workerUid,
        cleanKey,
        cleanKey,
        cleanKey,
        cleanKey,
        cleanKey,
        cleanKey,
        cleanKey,
        cleanKey,
        cleanKey,
        cleanKey,
      ],
    );
  }

  Future<List<Map<String, dynamic>>> readAllWorkerAllocations(
    String workerUid,
    String workerEmail,
  ) async {
    Database? myDb = await db;
    if (myDb == null) return [];
    final cleanEmail = workerEmail.trim().toLowerCase();
    final cleanUid = workerUid.trim().toLowerCase();

    // 1. Ø§Ø³ØªØ¹Ù„Ø§Ù… Ø¯Ù‚ÙŠÙ‚ ÙŠØ¶Ù…Ù† ÙÙ„ØªØ±Ø© ÙˆØ­ØµØ± Ø§Ù„Ø¥Ø³Ù†Ø§Ø¯Ø§Øª Ø§Ù„Ù…Ø³Ù†Ø¯Ø© Ù„Ù‡Ø°Ø§ Ø§Ù„Ø¹Ø§Ù…Ù„ ÙÙ‚Ø· Ø¨Ø¯ÙˆÙ† ØªØ³Ø±ÙŠØ¨ Ø¥Ø³Ù†Ø§Ø¯Ø§Øª ØºÙŠØ±Ù‡
    final List<Map<String, dynamic>> results;
    if (cleanEmail.isNotEmpty) {
      results = await myDb.rawQuery(
        '''
        SELECT wa.*, cd.window_type, cd.largeur, cd.hauteur, cd.color, cd.glass, cd.drawing_image_path, cd.drawing_image_base64, cd.partitions_json, cd.confirmed_mesures_json,
               cd.id_commandes, cd.accessories, cd.description, cd.quantity as detail_quantity,
               cl.firstname, cl.lastname, e.name as worker_name
        FROM WorkerAllocations wa
        LEFT JOIN Commandes_details cd ON wa.commande_detail_id = cd.id
        LEFT JOIN Commandes c ON cd.id_commandes = c.id
        LEFT JOIN Client cl ON c.client_id = cl.id
        LEFT JOIN Employees e ON (
          wa.worker_uid = e.uid 
          OR CAST(e.id AS TEXT) = wa.worker_uid
          OR (e.email IS NOT NULL AND e.email != '' AND LOWER(e.email) = LOWER(wa.worker_uid))
        )
        WHERE (
          wa.worker_uid = ?
          OR LOWER(wa.worker_uid) = ?
          OR wa.worker_uid IN (SELECT CAST(id AS TEXT) FROM Employees WHERE (uid = ? OR (email IS NOT NULL AND LOWER(email) = ?)))
          OR wa.worker_uid IN (SELECT uid FROM Employees WHERE (uid = ? OR (email IS NOT NULL AND LOWER(email) = ?)))
        )
          AND (wa.is_transferred_to_dist IS NULL OR wa.is_transferred_to_dist = 0)
        ORDER BY wa.assigned_at DESC
      ''',
        [workerUid, cleanEmail, cleanUid, cleanEmail, cleanUid, cleanEmail],
      );
    } else {
      results = await myDb.rawQuery(
        '''
        SELECT wa.*, cd.window_type, cd.largeur, cd.hauteur, cd.color, cd.glass, cd.drawing_image_path, cd.drawing_image_base64, cd.partitions_json, cd.confirmed_mesures_json,
               cd.id_commandes, cd.accessories, cd.description, cd.quantity as detail_quantity,
               cl.firstname, cl.lastname, e.name as worker_name
        FROM WorkerAllocations wa
        LEFT JOIN Commandes_details cd ON wa.commande_detail_id = cd.id
        LEFT JOIN Commandes c ON cd.id_commandes = c.id
        LEFT JOIN Client cl ON c.client_id = cl.id
        LEFT JOIN Employees e ON (
          wa.worker_uid = e.uid 
          OR CAST(e.id AS TEXT) = wa.worker_uid
        )
        WHERE (
          wa.worker_uid = ?
          OR wa.worker_uid IN (SELECT CAST(id AS TEXT) FROM Employees WHERE uid = ?)
          OR wa.worker_uid IN (SELECT uid FROM Employees WHERE CAST(id AS TEXT) = ?)
        )
          AND (wa.is_transferred_to_dist IS NULL OR wa.is_transferred_to_dist = 0)
        ORDER BY wa.assigned_at DESC
      ''',
        [workerUid, workerUid, workerUid],
      );
    }

    return results;
  }

  /// Ø±Ø¨Ø· Ø¥Ø³Ù†Ø§Ø¯Ø§Øª Ø§Ù„Ø¹Ø§Ù…Ù„ Ø¨Ù€ UID Ø§Ù„ØµØ­ÙŠØ­ Ø¨Ø¹Ø¯ Ø§Ù„Ø§Ø³ØªØ¹Ø§Ø¯Ø© Ù…Ù† Ø§Ù„Ø³Ø­Ø§Ø¨Ø©
  Future<void> relinkCurrentWorkerAllocations() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      Database? myDb = await db;
      if (myDb == null) return;

      final currentUid = user.uid;
      final currentEmail = (user.email ?? '').trim().toLowerCase();

      final allEmps = await myDb.query('Employees');
      for (var emp in allEmps) {
        final empIdStr = emp['id']?.toString() ?? '';
        final eUid = emp['uid']?.toString() ?? '';
        final eEmail = (emp['email']?.toString() ?? '').trim().toLowerCase();

        bool isMe = false;
        if (currentUid.isNotEmpty && eUid.isNotEmpty && eUid == currentUid) {
          isMe = true;
        } else if (currentEmail.isNotEmpty &&
            eEmail.isNotEmpty &&
            eEmail == currentEmail) {
          isMe = true;
        }

        if (isMe) {
          debugPrint(
            'relinkCurrentWorkerAllocations: linking empId=$empIdStr, eUid=$eUid -> $currentUid',
          );
          await myDb.transaction((txn) async {
            if (eUid != currentUid && eUid.isNotEmpty) {
              await txn.update(
                'Employees',
                {'uid': currentUid},
                where: 'uid = ?',
                whereArgs: [eUid],
              );
            }
            if (empIdStr.isNotEmpty) {
              await txn.update(
                'WorkerAllocations',
                {'worker_uid': currentUid},
                where: 'worker_uid = ?',
                whereArgs: [empIdStr],
              );
            }
            if (eEmail.isNotEmpty) {
              await txn.update(
                'WorkerAllocations',
                {'worker_uid': currentUid},
                where: 'LOWER(worker_uid) = ?',
                whereArgs: [eEmail],
              );
            }
            if (eUid.isNotEmpty && eUid != currentUid) {
              await txn.update(
                'WorkerAllocations',
                {'worker_uid': currentUid},
                where: 'worker_uid = ?',
                whereArgs: [eUid],
              );
            }
          });
        }
      }

      if (currentEmail.isNotEmpty) {
        await myDb.rawUpdate(
          '''
          UPDATE WorkerAllocations
          SET worker_uid = ?
          WHERE LOWER(worker_uid) = ?
        ''',
          [currentUid, currentEmail],
        );
        await myDb.rawUpdate(
          '''
          UPDATE WorkerAllocations
          SET installation_worker_uid = ?
          WHERE LOWER(installation_worker_uid) = ?
        ''',
          [currentUid, currentEmail],
        );
      }

      debugPrint('relinkCurrentWorkerAllocations: done for uid=$currentUid');
    } catch (e) {
      debugPrint('relinkCurrentWorkerAllocations error: $e');
    }
  }

  Future<List<Map<String, dynamic>>> readAbsoluteAllWorkerAllocations() async {
    Database? myDb = await db;
    if (myDb == null) return [];
    return await myDb.rawQuery('''
      SELECT wa.*, cd.window_type, cd.largeur, cd.hauteur, cd.color, cd.glass, cd.drawing_image_path, cd.drawing_image_base64, cd.partitions_json, cd.id_commandes, cd.accessories, cd.description, cl.firstname, cl.lastname, e.name as worker_name
      FROM WorkerAllocations wa
      INNER JOIN Commandes_details cd ON wa.commande_detail_id = cd.id
      INNER JOIN Commandes c ON cd.id_commandes = c.id
      LEFT JOIN Client cl ON c.client_id = cl.id
      LEFT JOIN Employees e ON (wa.worker_uid = e.uid OR CAST(e.id AS TEXT) = wa.worker_uid OR (e.email IS NOT NULL AND LOWER(e.email) = LOWER(wa.worker_uid)))
      WHERE (wa.is_transferred_to_dist IS NULL OR wa.is_transferred_to_dist = 0)
      ORDER BY wa.assigned_at DESC
    ''');
  }

  Future<List<Map<String, dynamic>>>
  readAllArchivedAllocationsForManager() async {
    Database? myDb = await db;
    if (myDb == null) return [];
    await purgeOldArchivedAllocations();

    final results = await myDb.rawQuery('''
      SELECT wa.*, cd.window_type, cd.largeur, cd.hauteur, cd.color, cd.glass, cd.drawing_image_path, cd.drawing_image_base64, cd.partitions_json,
             cd.id_commandes, cd.accessories, cd.description, cd.quantity as detail_quantity,
             cl.firstname, cl.lastname, e.name as worker_name,
             COALESCE(NULLIF(iw.name, ''), NULLIF(wa.installation_worker_uid, ''), NULLIF(e.name, ''), wa.worker_uid) as installation_worker_name,
             c.status as order_status
      FROM WorkerAllocations wa
      LEFT JOIN Commandes_details cd ON wa.commande_detail_id = cd.id
      LEFT JOIN Commandes c ON cd.id_commandes = c.id
      LEFT JOIN Client cl ON c.client_id = cl.id
      LEFT JOIN Employees e ON wa.worker_uid = e.uid
      LEFT JOIN Employees iw ON (
        wa.installation_worker_uid = iw.uid
        OR CAST(iw.id AS TEXT) = wa.installation_worker_uid
        OR (iw.email IS NOT NULL AND LOWER(iw.email) = LOWER(wa.installation_worker_uid))
      )
      WHERE wa.is_transferred_to_dist = 1
        AND (wa.is_completed = 1 OR wa.is_installed = 1)
      ORDER BY wa.transferred_at DESC, wa.assigned_at DESC
    ''');

    final now = DateTime.now();
    final List<Map<String, dynamic>> processed = [];
    for (var row in results) {
      final mutable = Map<String, dynamic>.from(row);
      final transferredAtStr = row['transferred_at']?.toString();
      bool isLocked = (row['archive_locked'] as num?)?.toInt() == 1;
      if (!isLocked &&
          transferredAtStr != null &&
          transferredAtStr.isNotEmpty) {
        try {
          final dt = DateTime.parse(transferredAtStr);
          if (now.difference(dt).inDays >= 7) {
            isLocked = true;
            final allocId = (row['id'] as num?)?.toInt() ?? 0;
            if (allocId > 0) {
              await myDb.update(
                'WorkerAllocations',
                {
                  'archive_locked': 1,
                  'updated_at': DateTime.now().toIso8601String(),
                },
                where: 'id = ?',
                whereArgs: [allocId],
              );
            }
          }
        } catch (_) {}
      }
      mutable['is_locked_after_week'] = isLocked;
      processed.add(mutable);
    }
    return processed;
  }

  Future<void> _uploadAllocationStatusToCloud(int allocationId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final workshopId = prefs.getString('workshop_code');
      if (workshopId != null && workshopId.isNotEmpty) {
        final myDb = await db;
        if (myDb == null) return;
        final allocs = await myDb.query(
          'WorkerAllocations',
          where: 'id = ?',
          whereArgs: [allocationId],
        );
        if (allocs.isNotEmpty) {
          final alloc = allocs.first;
          await FirebaseFirestore.instance
              .collection('workshops')
              .doc(workshopId)
              .collection('worker_allocations_status')
              .doc(allocationId.toString())
              .set({
                'id': allocationId,
                'commande_detail_id': alloc['commande_detail_id'],
                'worker_uid': alloc['worker_uid'],
                'quantity': alloc['quantity'],
                'worker_price': alloc['worker_price'],
                'assigned_at': alloc['assigned_at'],
                'unit_index': alloc['unit_index'],
                'unit_position': alloc['unit_position'],
                'unit_width': alloc['unit_width'],
                'unit_height': alloc['unit_height'],
                'is_manufactured': alloc['is_manufactured'] ?? 0,
                'manufactured_at': alloc['manufactured_at'],
                'is_glass_installed': alloc['is_glass_installed'] ?? 0,
                'glass_installed_at': alloc['glass_installed_at'],
                'is_distributed': alloc['is_distributed'] ?? 0,
                'distributed_at': alloc['distributed_at'],
                'is_transferred_to_dist': alloc['is_transferred_to_dist'] ?? 0,
                'transferred_at': alloc['transferred_at'],
                'is_installed': alloc['is_installed'] ?? 0,
                'installed_at': alloc['installed_at'],
                'installation_worker_uid': alloc['installation_worker_uid'],
                'installation_assigned_at': alloc['installation_assigned_at'],
                'is_completed': alloc['is_completed'] ?? 0,
                'completed_at': alloc['completed_at'],
                'has_reserve': alloc['has_reserve'] ?? 0,
                'reserve_notes': alloc['reserve_notes'],
                'reserve_at': alloc['reserve_at'],
                'updated_at':
                    alloc['updated_at'] ?? DateTime.now().toIso8601String(),
                'cloud_synced_at': FieldValue.serverTimestamp(),
              }, SetOptions(merge: true))
              .timeout(const Duration(seconds: 10));
          debugPrint(
            '--- SqlDatabase: Uploaded allocation status $allocationId (reserves & installation) to cloud ---',
          );
        }
      }
    } catch (e) {
      debugPrint('Error uploading allocation status to cloud: $e');
    }
  }

  /// Synchronises allocation status rows. When [changedRows] is provided only
  /// those rows are merged; the real-time listener uses this path so a single
  /// reassignment never downloads the entire workshop again.
  Future<void> syncWorkerAllocationsStatusFromCloud({
    Iterable<Map<String, dynamic>>? changedRows,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final workshopId = prefs.getString('workshop_code');
    if (workshopId == null || workshopId.isEmpty) return;

    try {
      final statusRows = <Map<String, dynamic>>[];
      if (changedRows != null) {
        for (final row in changedRows) {
          final copy = Map<String, dynamic>.from(row);
          if (copy['__allocation_id'] == null && copy['id'] != null) {
            copy['__allocation_id'] = copy['id'];
          }
          statusRows.add(copy);
        }
      } else {
        final snapshot = await FirebaseFirestore.instance
            .collection('workshops')
            .doc(workshopId)
            .collection('worker_allocations_status')
            .get();
        for (final doc in snapshot.docs) {
          final data = Map<String, dynamic>.from(doc.data());
          data['__allocation_id'] = doc.id;
          statusRows.add(data);
        }
      }

      Database? myDb = await db;
      if (myDb == null) return;

      await myDb.transaction((txn) async {
        for (final data in statusRows) {
          final allocationId = int.tryParse(
            data['__allocation_id']?.toString() ?? '',
          );
          if (allocationId == null) continue;
          final cloudUpdatedAt = _sanitizeImportValue(
            data['updated_at'],
          )?.toString();

          final existing = await txn.query(
            'WorkerAllocations',
            where: 'id = ?',
            whereArgs: [allocationId],
          );
          if (existing.isNotEmpty) {
            final old = existing.first;
            final oldTransferred =
                (old['is_transferred_to_dist'] as num?)?.toInt() == 1;
            final incomingTransferredRaw = data['is_transferred_to_dist'];
            final incomingTransferred =
                incomingTransferredRaw == true ||
                (incomingTransferredRaw is num &&
                    incomingTransferredRaw.toInt() == 1) ||
                incomingTransferredRaw?.toString() == '1';
            if (cloudUpdatedAt == null &&
                oldTransferred &&
                !incomingTransferred) {
              continue;
            }
            if (cloudUpdatedAt != null &&
                _localRowIsNewer(Map<String, dynamic>.from(old), {
                  'updated_at': cloudUpdatedAt,
                })) {
              continue;
            }
            await txn.update(
              'WorkerAllocations',
              {
                'worker_uid': data['worker_uid'] ?? old['worker_uid'],
                'quantity': data['quantity'] ?? old['quantity'],
                'worker_price': data['worker_price'] ?? old['worker_price'],
                'unit_index': data['unit_index'] ?? old['unit_index'],
                'unit_position': data['unit_position'] ?? old['unit_position'],
                'unit_width': data['unit_width'] ?? old['unit_width'],
                'unit_height': data['unit_height'] ?? old['unit_height'],
                'is_manufactured':
                    data['is_manufactured'] ?? old['is_manufactured'] ?? 0,
                'manufactured_at': data.containsKey('manufactured_at')
                    ? data['manufactured_at']
                    : old['manufactured_at'],
                'is_glass_installed':
                    data['is_glass_installed'] ??
                    old['is_glass_installed'] ??
                    0,
                'glass_installed_at': data.containsKey('glass_installed_at')
                    ? data['glass_installed_at']
                    : old['glass_installed_at'],
                'is_distributed':
                    data['is_distributed'] ?? old['is_distributed'] ?? 0,
                'distributed_at': data.containsKey('distributed_at')
                    ? data['distributed_at']
                    : old['distributed_at'],
                'is_transferred_to_dist':
                    data['is_transferred_to_dist'] ??
                    old['is_transferred_to_dist'] ??
                    0,
                'transferred_at': data.containsKey('transferred_at')
                    ? data['transferred_at']
                    : old['transferred_at'],
                'is_installed':
                    data['is_installed'] ?? old['is_installed'] ?? 0,
                'installed_at': data.containsKey('installed_at')
                    ? data['installed_at']
                    : old['installed_at'],
                'installation_worker_uid':
                    data.containsKey('installation_worker_uid')
                    ? data['installation_worker_uid']
                    : old['installation_worker_uid'],
                'installation_assigned_at':
                    data.containsKey('installation_assigned_at')
                    ? data['installation_assigned_at']
                    : old['installation_assigned_at'],
                'is_completed':
                    data['is_completed'] ?? old['is_completed'] ?? 0,
                'completed_at': data.containsKey('completed_at')
                    ? data['completed_at']
                    : old['completed_at'],
                'has_reserve': data['has_reserve'] ?? old['has_reserve'] ?? 0,
                'reserve_notes': data.containsKey('reserve_notes')
                    ? data['reserve_notes']
                    : old['reserve_notes'],
                'reserve_at': data.containsKey('reserve_at')
                    ? data['reserve_at']
                    : old['reserve_at'],
                'updated_at':
                    cloudUpdatedAt ?? old['updated_at'] ?? old['assigned_at'],
              },
              where: 'id = ?',
              whereArgs: [allocationId],
            );
          } else if (data['commande_detail_id'] != null &&
              data['worker_uid'] != null) {
            await txn.insert('WorkerAllocations', {
              'id': allocationId,
              'commande_detail_id': data['commande_detail_id'],
              'worker_uid': data['worker_uid'],
              'quantity': data['quantity'] ?? 1,
              'worker_price': data['worker_price'] ?? 0.0,
              'assigned_at':
                  data['assigned_at'] ?? DateTime.now().toIso8601String(),
              'unit_index': data['unit_index'],
              'unit_position': data['unit_position'],
              'is_settled': 0,
              'is_manufactured': data['is_manufactured'] ?? 0,
              'manufactured_at': data['manufactured_at'],
              'is_glass_installed': data['is_glass_installed'] ?? 0,
              'glass_installed_at': data['glass_installed_at'],
              'is_distributed': data['is_distributed'] ?? 0,
              'distributed_at': data['distributed_at'],
              'is_transferred_to_dist': data['is_transferred_to_dist'] ?? 0,
              'transferred_at': data['transferred_at'],
              'is_installed': data['is_installed'] ?? 0,
              'installed_at': data['installed_at'],
              'installation_worker_uid': data['installation_worker_uid'],
              'installation_assigned_at': data['installation_assigned_at'],
              'is_completed': data['is_completed'] ?? 0,
              'completed_at': data['completed_at'],
              'has_reserve': data['has_reserve'] ?? 0,
              'reserve_notes': data['reserve_notes'],
              'reserve_at': data['reserve_at'],
              'updated_at': cloudUpdatedAt ?? DateTime.now().toIso8601String(),
            });
          }
        }
      });
      debugPrint(
        '--- SqlDatabase: Synced allocations status (including reserves and installation) from cloud successfully ---',
      );
    } catch (e) {
      debugPrint('Error syncing worker allocations status: $e');
    }
  }

  Future<void> syncOrderAndAllocationsStatus(int orderId) async {
    try {
      Database? myDb = await db;
      if (myDb == null || orderId <= 0) return;

      final allOrderAllocs = await myDb.rawQuery(
        '''
        SELECT wa.* 
        FROM WorkerAllocations wa
        INNER JOIN Commandes_details cd ON wa.commande_detail_id = cd.id
        WHERE cd.id_commandes = ?
      ''',
        [orderId],
      );

      if (allOrderAllocs.isEmpty) return;

      int totalAllocs = allOrderAllocs.length;
      int mfgAllocs = allOrderAllocs
          .where((wa) => (wa['is_manufactured'] as num?)?.toInt() == 1)
          .length;
      int distAllocs = allOrderAllocs
          .where(
            (wa) =>
                (wa['is_distributed'] as num?)?.toInt() == 1 ||
                (wa['is_transferred_to_dist'] as num?)?.toInt() == 1,
          )
          .length;
      int installAllocs = allOrderAllocs
          .where((wa) => (wa['is_installed'] as num?)?.toInt() == 1)
          .length;
      int reserveAllocs = allOrderAllocs
          .where((wa) => (wa['has_reserve'] as num?)?.toInt() == 1)
          .length;
      int completedAllocs = allOrderAllocs
          .where((wa) => (wa['is_completed'] as num?)?.toInt() == 1)
          .length;

      String? targetStatus;
      if (completedAllocs >= totalAllocs &&
          totalAllocs > 0 &&
          reserveAllocs == 0) {
        targetStatus = 'Done';
      } else if (reserveAllocs > 0) {
        targetStatus = 'Reserve';
      } else if (installAllocs >= totalAllocs && totalAllocs > 0) {
        targetStatus = 'Installation';
      } else if (distAllocs >= totalAllocs && totalAllocs > 0) {
        targetStatus = 'Full Distribution';
      } else if (distAllocs > 0) {
        targetStatus = 'Partial Distribution';
      } else if (mfgAllocs >= totalAllocs && totalAllocs > 0) {
        targetStatus = 'Full Manufacturing';
      } else if (mfgAllocs > 0) {
        targetStatus = 'Partial Manufacturing';
      }

      if (targetStatus != null) {
        final orderRow = await myDb.query(
          'Commandes',
          where: 'id = ?',
          whereArgs: [orderId],
        );
        if (orderRow.isNotEmpty) {
          final currentStatus = orderRow.first['status']?.toString() ?? '';
          if (currentStatus != targetStatus) {
            await updateCommandeStatus(
              orderId,
              targetStatus,
              skipAllocationSync: true,
            );
            debugPrint(
              'syncOrderAndAllocationsStatus: updated order #$orderId status from $currentStatus to $targetStatus',
            );
          }
        }
      }
    } catch (e) {
      debugPrint('syncOrderAndAllocationsStatus error: $e');
    }
  }

  Future<bool> isOrderFullyManufactured(int orderId) async {
    Database? myDb = await db;
    if (myDb == null || orderId <= 0) return false;

    final details = await myDb.query(
      'Commandes_details',
      where: 'id_commandes = ?',
      whereArgs: [orderId],
    );
    if (details.isEmpty) return false;

    int totalRequiredQty = 0;
    for (final d in details) {
      totalRequiredQty += (d['quantity'] as num?)?.toInt() ?? 0;
    }
    if (totalRequiredQty == 0) return false;

    final manufacturedAllocs = await myDb.rawQuery(
      '''
      SELECT SUM(wa.quantity) as total_mfg_qty
      FROM WorkerAllocations wa
      INNER JOIN Commandes_details cd ON wa.commande_detail_id = cd.id
      WHERE cd.id_commandes = ? AND wa.is_manufactured = 1
    ''',
      [orderId],
    );

    int totalMfgQty = 0;
    if (manufacturedAllocs.isNotEmpty &&
        manufacturedAllocs.first['total_mfg_qty'] != null) {
      totalMfgQty = (manufacturedAllocs.first['total_mfg_qty'] as num).toInt();
    }

    return totalMfgQty >= totalRequiredQty;
  }

  Future<void> updateWorkerAllocationManufacturing(
    int allocationId,
    int isManufactured,
  ) async {
    Database? myDb = await db;
    if (myDb == null) return;
    final nowStr = DateTime.now().toIso8601String();

    await myDb.update(
      'WorkerAllocations',
      {
        'is_manufactured': isManufactured,
        'manufactured_at': isManufactured == 1 ? nowStr : null,
        'updated_at': nowStr,
      },
      where: 'id = ?',
      whereArgs: [allocationId],
    );

    final allocRow = await myDb.query(
      'WorkerAllocations',
      where: 'id = ?',
      whereArgs: [allocationId],
    );
    if (allocRow.isNotEmpty) {
      final detailId =
          (allocRow.first['commande_detail_id'] as num?)?.toInt() ?? 0;
      if (detailId > 0) {
        final detailRow = await myDb.query(
          'Commandes_details',
          where: 'id = ?',
          whereArgs: [detailId],
        );
        if (detailRow.isNotEmpty) {
          final orderId =
              (detailRow.first['id_commandes'] as num?)?.toInt() ?? 0;
          if (orderId > 0) {
            await syncOrderAndAllocationsStatus(orderId);
          }
        }
      }
    }

    await _uploadAllocationStatusToCloud(allocationId);
    // Reassignment is an urgent row-level event. Do not put it behind the
    // normal backup debounce; the status listener on the other phone receives
    // the single allocation document immediately.
    CloudSyncService().notifyChangeImmediate();
  }

  Future<void> updateWorkerAllocationGlass(
    int allocationId,
    int isGlassInstalled,
  ) async {
    Database? myDb = await db;
    if (myDb == null) return;
    final nowStr = DateTime.now().toIso8601String();

    await myDb.update(
      'WorkerAllocations',
      {
        'is_glass_installed': isGlassInstalled,
        'glass_installed_at': isGlassInstalled == 1 ? nowStr : null,
        'updated_at': nowStr,
      },
      where: 'id = ?',
      whereArgs: [allocationId],
    );

    final allocRow = await myDb.query(
      'WorkerAllocations',
      where: 'id = ?',
      whereArgs: [allocationId],
    );
    if (allocRow.isNotEmpty) {
      final detailId =
          (allocRow.first['commande_detail_id'] as num?)?.toInt() ?? 0;
      if (detailId > 0) {
        final detailRow = await myDb.query(
          'Commandes_details',
          where: 'id = ?',
          whereArgs: [detailId],
        );
        if (detailRow.isNotEmpty) {
          final orderId =
              (detailRow.first['id_commandes'] as num?)?.toInt() ?? 0;
          if (orderId > 0) {
            await syncOrderAndAllocationsStatus(orderId);
          }
        }
      }
    }

    await _uploadAllocationStatusToCloud(allocationId);
    CloudSyncService().notifyChange();
  }

  Future<void> updateWorkerAllocationDistribution(
    int allocationId,
    int isDistributed,
  ) async {
    Database? myDb = await db;
    if (myDb == null) return;
    final nowStr = DateTime.now().toIso8601String();

    await myDb.update(
      'WorkerAllocations',
      {
        'is_distributed': isDistributed,
        'distributed_at': isDistributed == 1 ? nowStr : null,
        'updated_at': nowStr,
      },
      where: 'id = ?',
      whereArgs: [allocationId],
    );

    final allocRow = await myDb.query(
      'WorkerAllocations',
      where: 'id = ?',
      whereArgs: [allocationId],
    );
    if (allocRow.isNotEmpty) {
      final detailId =
          (allocRow.first['commande_detail_id'] as num?)?.toInt() ?? 0;
      if (detailId > 0) {
        final detailRow = await myDb.query(
          'Commandes_details',
          where: 'id = ?',
          whereArgs: [detailId],
        );
        if (detailRow.isNotEmpty) {
          final orderId =
              (detailRow.first['id_commandes'] as num?)?.toInt() ?? 0;
          if (orderId > 0) {
            await syncOrderAndAllocationsStatus(orderId);
          }
        }
      }
    }

    await _uploadAllocationStatusToCloud(allocationId);
    CloudSyncService().notifyChange();
  }

  Future<void> updateWorkerAllocationTransfer(
    int allocationId,
    int isTransferred,
  ) async {
    Database? myDb = await db;
    if (myDb == null) return;
    final nowStr = DateTime.now().toIso8601String();

    // âœ”ï¸ Ø¹Ù†Ø¯ Ø§Ù„ØªØ­ÙˆÙŠÙ„ Ø¥Ù„Ù‰ Ø§Ù„ØªÙˆØ²ÙŠØ¹: Ù†Ø¶Ø¨Ø· Ø­Ù‚Ù„ Ø§Ù„ØªØ­ÙˆÙŠÙ„ ÙÙ‚Ø· â†’ Ø§Ù„Ø¹Ù†ØµØ± ÙŠÙ†ØªÙ‚Ù„ Ù„ØµÙØ­Ø© Ø§Ù„ØªØ±ÙƒÙŠØ¨Ø§Øª Ø§Ù„Ù…ÙŠØ¯Ø§Ù†ÙŠØ©
    // âœ”ï¸ Ø¹Ù†Ø¯ Ø§Ù„Ø¥Ù„ØºØ§Ø¡ (Ø¥Ø±Ø¬Ø§Ø¹ Ù…Ù† Ø§Ù„Ø£Ø±Ø´ÙŠÙ): Ù†ØµÙÙ‘Ø± Ø¬Ù…ÙŠØ¹ Ø­Ù‚ÙˆÙ„ Ø§Ù„ØªØ±ÙƒÙŠØ¨/Ø§Ù„Ø§ÙƒØªÙ…Ø§Ù„ Ø­ØªÙ‰ ÙŠÙ…Ø± Ø§Ù„Ø¹Ù†ØµØ± Ø¨Ù…Ø±Ø­Ù„Ø© Ø§Ù„ØªØ±ÙƒÙŠØ¨Ø§Øª Ø§Ù„Ù…ÙŠØ¯Ø§Ù†ÙŠØ© Ù…Ø±Ø© Ø£Ø®Ø±Ù‰
    final Map<String, dynamic> updateFields = isTransferred == 1
        ? {
            'is_transferred_to_dist': 1,
            'transferred_at': nowStr,
            'updated_at': nowStr,
          }
        : {
            'is_transferred_to_dist': 0,
            'transferred_at': null,
            // âœ… Ø£Ø³Ø§Ø³ÙŠ: Ø¹Ù†Ø¯ Ø§Ù„Ø¥Ø±Ø¬Ø§Ø¹ Ù…Ù† Ø§Ù„Ø£Ø±Ø´ÙŠÙ ÙŠØ¬Ø¨ Ù…Ø³Ø­ Ø­Ø§Ù„Ø© Ø§Ù„ØªØ±ÙƒÙŠØ¨ ÙˆØ§Ù„Ø§ÙƒØªÙ…Ø§Ù„ Ù„ÙŠØ¹ÙˆØ¯ Ù„Ù„ØªØ±ÙƒÙŠØ¨Ø§Øª Ø§Ù„Ù…ÙŠØ¯Ø§Ù†ÙŠØ© Ø¨Ø¹Ø¯ Ø°Ù„Ùƒ
            'is_installed': 0,
            'installed_at': null,
            'is_completed': 0,
            'completed_at': null,
            'archive_locked': 0,
            'updated_at': nowStr,
          };

    await myDb.update(
      'WorkerAllocations',
      updateFields,
      where: 'id = ?',
      whereArgs: [allocationId],
    );

    // âš¡ï¸ ØªØ´ØºÙŠÙ„ syncOrder ÙÙŠ Ø§Ù„Ø®Ù„ÙÙŠØ© Ø¯ÙˆÙ† Ø­Ø¸Ø± Ø§Ù„ÙˆØ§Ø¬Ù‡Ø© (ØªØ­Ø³ÙŠÙ† Ø§Ù„Ø³Ø±Ø¹Ø©)
    () async {
      try {
        final allocRow = await myDb.query(
          'WorkerAllocations',
          where: 'id = ?',
          whereArgs: [allocationId],
        );
        if (allocRow.isNotEmpty) {
          final detailId =
              (allocRow.first['commande_detail_id'] as num?)?.toInt() ?? 0;
          if (detailId > 0) {
            final detailRow = await myDb.query(
              'Commandes_details',
              where: 'id = ?',
              whereArgs: [detailId],
            );
            if (detailRow.isNotEmpty) {
              final orderId =
                  (detailRow.first['id_commandes'] as num?)?.toInt() ?? 0;
              if (orderId > 0) {
                await syncOrderAndAllocationsStatus(orderId);
              }
            }
          }
        }
      } catch (e) {
        debugPrint('Background syncOrder error: $e');
      }
    }();

    await _uploadAllocationStatusToCloud(allocationId);
    CloudSyncService().notifyChange();
  }

  Future<List<Map<String, dynamic>>> readFieldInstallationAllocations() async {
    Database? myDb = await db;
    if (myDb == null) return [];

    final results = await myDb.rawQuery('''
      SELECT wa.*, cd.window_type, cd.largeur, cd.hauteur, cd.color, cd.glass, cd.drawing_image_path, cd.drawing_image_base64, cd.partitions_json,
             cd.id_commandes, cd.accessories, cd.description, cd.quantity as detail_quantity,
             cl.firstname, cl.lastname, cl.id as client_id, e.name as worker_name,
             COALESCE(NULLIF(iw.name, ''), NULLIF(wa.installation_worker_uid, ''), NULLIF(e.name, ''), wa.worker_uid) as installation_worker_name,
             c.status as order_status
      FROM WorkerAllocations wa
      INNER JOIN Commandes_details cd ON wa.commande_detail_id = cd.id
      INNER JOIN Commandes c ON cd.id_commandes = c.id
      LEFT JOIN Client cl ON c.client_id = cl.id
      LEFT JOIN Employees e ON wa.worker_uid = e.uid
      LEFT JOIN Employees iw ON (
        wa.installation_worker_uid = iw.uid
        OR CAST(iw.id AS TEXT) = wa.installation_worker_uid
        OR (iw.email IS NOT NULL AND LOWER(iw.email) = LOWER(wa.installation_worker_uid))
      )
      WHERE wa.is_transferred_to_dist = 1
        AND (wa.is_completed IS NULL OR wa.is_completed = 0)
      ORDER BY cl.lastname ASC, cl.firstname ASC, cd.id_commandes ASC, wa.id ASC
    ''');
    return results.map((r) => Map<String, dynamic>.from(r)).toList();
  }

  Future<void> updateWorkerAllocationInstallation(
    int allocationId,
    int isInstalled,
  ) async {
    Database? myDb = await db;
    if (myDb == null) return;
    final nowStr = DateTime.now().toIso8601String();
    await myDb.update(
      'WorkerAllocations',
      {
        'is_installed': isInstalled,
        'installed_at': isInstalled == 1 ? nowStr : null,
        'updated_at': nowStr,
      },
      where: 'id = ?',
      whereArgs: [allocationId],
    );

    final allocRow = await myDb.query(
      'WorkerAllocations',
      where: 'id = ?',
      whereArgs: [allocationId],
    );
    if (allocRow.isNotEmpty) {
      final detailId =
          (allocRow.first['commande_detail_id'] as num?)?.toInt() ?? 0;
      if (detailId > 0) {
        final detailRow = await myDb.query(
          'Commandes_details',
          where: 'id = ?',
          whereArgs: [detailId],
        );
        if (detailRow.isNotEmpty) {
          final orderId =
              (detailRow.first['id_commandes'] as num?)?.toInt() ?? 0;
          if (orderId > 0) {
            await syncOrderAndAllocationsStatus(orderId);
          }
        }
      }
    }

    await _uploadAllocationStatusToCloud(allocationId);
    CloudSyncService().notifyChange();
  }

  Future<void> updateWorkerAllocationInstallationWorker(
    int allocationId,
    String workerUid,
  ) async {
    Database? myDb = await db;
    if (myDb == null) return;
    final nowStr = DateTime.now().toIso8601String();
    await myDb.update(
      'WorkerAllocations',
      {
        'installation_worker_uid': workerUid,
        'installation_assigned_at': nowStr,
        'updated_at': nowStr,
      },
      where: 'id = ?',
      whereArgs: [allocationId],
    );

    await _uploadAllocationStatusToCloud(allocationId);
    // Reassignment is an urgent row-level event. Do not put it behind the
    // normal backup debounce; the status listener on the other phone receives
    // the single allocation document immediately.
    CloudSyncService().notifyChangeImmediate();
  }

  Future<void> updateWorkerAllocationCompletion(
    int allocationId,
    int isCompleted,
  ) async {
    Database? myDb = await db;
    if (myDb == null) return;
    final nowStr = DateTime.now().toIso8601String();
    await myDb.update(
      'WorkerAllocations',
      {
        'is_completed': isCompleted,
        'completed_at': isCompleted == 1 ? nowStr : null,
        'is_transferred_to_dist': 1,
        'transferred_at': nowStr,
        if (isCompleted == 1) 'has_reserve': 0,
        if (isCompleted == 1) 'reserve_notes': null,
        'updated_at': nowStr,
      },
      where: 'id = ?',
      whereArgs: [allocationId],
    );

    final allocRow = await myDb.query(
      'WorkerAllocations',
      where: 'id = ?',
      whereArgs: [allocationId],
    );
    if (allocRow.isNotEmpty) {
      final detailId =
          (allocRow.first['commande_detail_id'] as num?)?.toInt() ?? 0;
      if (detailId > 0) {
        final detailRow = await myDb.query(
          'Commandes_details',
          where: 'id = ?',
          whereArgs: [detailId],
        );
        if (detailRow.isNotEmpty) {
          final orderId =
              (detailRow.first['id_commandes'] as num?)?.toInt() ?? 0;
          if (orderId > 0) {
            await syncOrderAndAllocationsStatus(orderId);
          }
        }
      }
    }

    await _uploadAllocationStatusToCloud(allocationId);
    CloudSyncService().notifyChange();
  }

  Future<void> updateWorkerAllocationReserve(
    int allocationId,
    int hasReserve,
    String? reserveNotes,
  ) async {
    Database? myDb = await db;
    if (myDb == null) return;
    final nowStr = DateTime.now().toIso8601String();
    await myDb.update(
      'WorkerAllocations',
      {
        'has_reserve': hasReserve,
        'reserve_notes': hasReserve == 1 ? reserveNotes : null,
        'reserve_at': hasReserve == 1 ? nowStr : null,
        'updated_at': nowStr,
      },
      where: 'id = ?',
      whereArgs: [allocationId],
    );

    final allocRow = await myDb.query(
      'WorkerAllocations',
      where: 'id = ?',
      whereArgs: [allocationId],
    );
    if (allocRow.isNotEmpty) {
      final detailId =
          (allocRow.first['commande_detail_id'] as num?)?.toInt() ?? 0;
      if (detailId > 0) {
        final detailRow = await myDb.query(
          'Commandes_details',
          where: 'id = ?',
          whereArgs: [detailId],
        );
        if (detailRow.isNotEmpty) {
          final orderId =
              (detailRow.first['id_commandes'] as num?)?.toInt() ?? 0;
          if (orderId > 0) {
            if (hasReserve == 1) {
              await updateCommandeStatus(
                orderId,
                'Reserve',
                skipAllocationSync: true,
              );
            } else {
              await syncOrderAndAllocationsStatus(orderId);
            }
          }
        }
      }
    }

    await _uploadAllocationStatusToCloud(allocationId);
    CloudSyncService().notifyChange();
  }

  Future<List<Map<String, dynamic>>> readReserveAllocations() async {
    Database? myDb = await db;
    if (myDb == null) return [];

    final results = await myDb.rawQuery('''
      SELECT wa.*, cd.window_type, cd.largeur, cd.hauteur, cd.color, cd.glass, cd.drawing_image_path, cd.drawing_image_base64, cd.partitions_json,
             cd.id_commandes, cd.accessories, cd.description, cd.quantity as detail_quantity,
             cl.firstname, cl.lastname, cl.id as client_id, e.name as worker_name,
             COALESCE(NULLIF(iw.name, ''), NULLIF(wa.installation_worker_uid, ''), NULLIF(e.name, ''), wa.worker_uid) as installation_worker_name,
             c.status as order_status
      FROM WorkerAllocations wa
      INNER JOIN Commandes_details cd ON wa.commande_detail_id = cd.id
      INNER JOIN Commandes c ON cd.id_commandes = c.id
      LEFT JOIN Client cl ON c.client_id = cl.id
      LEFT JOIN Employees e ON wa.worker_uid = e.uid
      LEFT JOIN Employees iw ON (
        wa.installation_worker_uid = iw.uid
        OR CAST(iw.id AS TEXT) = wa.installation_worker_uid
        OR (iw.email IS NOT NULL AND LOWER(iw.email) = LOWER(wa.installation_worker_uid))
      )
      WHERE wa.has_reserve = 1
        AND (wa.is_completed IS NULL OR wa.is_completed = 0)
      ORDER BY cl.lastname ASC, cl.firstname ASC, cd.id_commandes ASC, wa.id ASC
    ''');
    return results.map((r) => Map<String, dynamic>.from(r)).toList();
  }

  Future<void> purgeOldArchivedAllocations() async {
    try {
      Database? myDb = await db;
      if (myDb == null) return;
      final sixMonthsAgo = DateTime.now()
          .subtract(const Duration(days: 180))
          .toIso8601String();
      await myDb.rawDelete(
        '''
        DELETE FROM WorkerAllocations 
        WHERE is_transferred_to_dist = 1 
          AND transferred_at IS NOT NULL 
          AND transferred_at < ?
      ''',
        [sixMonthsAgo],
      );
    } catch (e) {
      debugPrint('purgeOldArchivedAllocations error: $e');
    }
  }

  Future<List<Map<String, dynamic>>> readWorkerArchivedAllocations(
    String workerUid,
    String workerEmail,
  ) async {
    Database? myDb = await db;
    if (myDb == null) return [];
    await purgeOldArchivedAllocations();
    final cleanEmail = workerEmail.trim().toLowerCase();

    final results = await myDb.rawQuery(
      '''
      SELECT wa.*, cd.window_type, cd.largeur, cd.hauteur, cd.color, cd.glass, cd.drawing_image_path, cd.drawing_image_base64, cd.partitions_json,
             cd.id_commandes, cd.accessories, cd.description, cd.quantity as detail_quantity,
             cl.firstname, cl.lastname, e.name as worker_name,
             COALESCE(NULLIF(iw.name, ''), NULLIF(wa.installation_worker_uid, ''), NULLIF(e.name, ''), wa.worker_uid) as installation_worker_name,
             c.status as order_status
      FROM WorkerAllocations wa
      LEFT JOIN Commandes_details cd ON wa.commande_detail_id = cd.id
      LEFT JOIN Commandes c ON cd.id_commandes = c.id
      LEFT JOIN Client cl ON c.client_id = cl.id
      LEFT JOIN Employees e ON (wa.worker_uid = e.uid OR (e.email IS NOT NULL AND LOWER(e.email) = ?))
      LEFT JOIN Employees iw ON (
        wa.installation_worker_uid = iw.uid
        OR CAST(iw.id AS TEXT) = wa.installation_worker_uid
        OR (iw.email IS NOT NULL AND LOWER(iw.email) = LOWER(wa.installation_worker_uid))
      )
      WHERE (wa.worker_uid = ?
         OR LOWER(wa.worker_uid) = ?
         OR (e.email IS NOT NULL AND e.email != '' AND LOWER(e.email) = ?)
         OR wa.installation_worker_uid = ?
         OR LOWER(wa.installation_worker_uid) = ?
         OR (iw.email IS NOT NULL AND iw.email != '' AND LOWER(iw.email) = ?))
        AND wa.is_transferred_to_dist = 1
        AND (wa.is_completed = 1 OR wa.is_installed = 1)
      ORDER BY wa.transferred_at DESC, wa.assigned_at DESC
    ''',
      [
        cleanEmail,
        workerUid,
        cleanEmail,
        cleanEmail,
        workerUid,
        cleanEmail,
        cleanEmail,
      ],
    );

    final now = DateTime.now();
    final List<Map<String, dynamic>> processed = [];
    for (var row in results) {
      final mutable = Map<String, dynamic>.from(row);
      final transferredAtStr = row['transferred_at']?.toString();
      bool isLocked = (row['archive_locked'] as num?)?.toInt() == 1;
      if (!isLocked &&
          transferredAtStr != null &&
          transferredAtStr.isNotEmpty) {
        try {
          final dt = DateTime.parse(transferredAtStr);
          if (now.difference(dt).inDays >= 7) {
            isLocked = true;
            final allocId = (row['id'] as num?)?.toInt() ?? 0;
            if (allocId > 0) {
              await myDb.update(
                'WorkerAllocations',
                {
                  'archive_locked': 1,
                  'updated_at': DateTime.now().toIso8601String(),
                },
                where: 'id = ?',
                whereArgs: [allocId],
              );
            }
          }
        } catch (_) {}
      }
      mutable['is_locked_after_week'] = isLocked;
      processed.add(mutable);
    }
    return processed;
  }

  Future<void> updateWorkerAllocationPrice(
    int allocationId,
    double price,
  ) async {
    Database? myDb = await db;
    if (myDb == null) return;
    await myDb.update(
      'WorkerAllocations',
      {'worker_price': price, 'updated_at': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [allocationId],
    );
    await _uploadAllocationStatusToCloud(allocationId);
    CloudSyncService().notifyChange();
  }

  // â”€â”€ Ø§Ù„Ø­Ø¶ÙˆØ± ÙˆØ§Ù„ØºÙŠØ§Ø¨ (WorkerAttendance) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  Future<List<Map<String, dynamic>>> readWorkerAttendance(
    String workerUid,
  ) async {
    Database? myDb = await db;
    if (myDb == null) return [];
    final cleanUid = workerUid.trim().toLowerCase();
    final results = await myDb.rawQuery(
      '''
      SELECT * FROM WorkerAttendance 
      WHERE worker_uid = ? OR LOWER(worker_uid) = ?
      ORDER BY attendance_date DESC
    ''',
      [workerUid, cleanUid],
    );
    return results.map((r) => Map<String, dynamic>.from(r)).toList();
  }

  Future<void> upsertWorkerAttendance({
    required String workerUid,
    required String date,
    String? checkIn,
    String? checkOut,
    String? note,
  }) async {
    Database? myDb = await db;
    if (myDb == null) return;

    if (checkIn == null && checkOut == null && (note == null || note.isEmpty)) {
      // ðŸ—‘ï¸ Ø¥Ø°Ø§ ÙƒØ§Ù†Øª Ø§Ù„Ø¨ÙŠØ§Ù†Ø§Øª ÙØ§Ø±ØºØ©ØŒ Ø§Ø­Ø°Ù Ø§Ù„Ø³Ø¬Ù„ Ù„ØªØµÙÙŠØ± Ø®ÙŠØ§Ø± Ø§Ù„Ø­Ø¶ÙˆØ± ÙˆØ§Ù„ØºÙŠØ§Ø¨ (ÙØ§Ø±Øº âšª)
      await myDb.delete(
        'WorkerAttendance',
        where: 'worker_uid = ? AND attendance_date = ?',
        whereArgs: [workerUid, date],
      );
      CloudSyncService().notifyChange();
      return;
    }

    final existing = await myDb.query(
      'WorkerAttendance',
      where: 'worker_uid = ? AND attendance_date = ?',
      whereArgs: [workerUid, date],
    );

    if (existing.isNotEmpty) {
      await myDb.update(
        'WorkerAttendance',
        {'check_in': checkIn, 'check_out': checkOut, 'note': note},
        where: 'worker_uid = ? AND attendance_date = ?',
        whereArgs: [workerUid, date],
      );
    } else {
      await myDb.insert(
        'WorkerAttendance',
        _withDistributedId({
          'worker_uid': workerUid,
          'attendance_date': date,
          'check_in': checkIn,
          'check_out': checkOut,
          'note': note,
        }),
      );
    }
    CloudSyncService().notifyChange();
  }

  // â”€â”€ Ø§Ù„Ø£Ø¹Ù…Ø§Ù„ Ø§Ù„ÙŠÙˆÙ…ÙŠØ© (WorkerDailyJobs - Ø¹Ù…Ù„ ÙŠÙˆÙ…ÙŠ) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  Future<List<Map<String, dynamic>>> readWorkerDailyJobs(
    String workerUid,
  ) async {
    Database? myDb = await db;
    if (myDb == null) return [];
    final cleanUid = workerUid.trim().toLowerCase();
    final results = await myDb.rawQuery(
      '''
      SELECT * FROM WorkerDailyJobs 
      WHERE worker_uid = ? OR LOWER(worker_uid) = ?
      ORDER BY work_date DESC, id DESC
    ''',
      [workerUid, cleanUid],
    );
    return results.map((r) => Map<String, dynamic>.from(r)).toList();
  }

  Future<List<Map<String, dynamic>>> readWorkerUnsettledDailyJobs(
    String workerUid,
  ) async {
    Database? myDb = await db;
    if (myDb == null) return [];
    final cleanUid = workerUid.trim().toLowerCase();
    final results = await myDb.rawQuery(
      '''
      SELECT * FROM WorkerDailyJobs 
      WHERE (worker_uid = ? OR LOWER(worker_uid) = ?)
        AND (is_settled = 0 OR is_settled IS NULL)
      ORDER BY work_date DESC
    ''',
      [workerUid, cleanUid],
    );
    return results.map((r) => Map<String, dynamic>.from(r)).toList();
  }

  Future<void> addWorkerDailyJob({
    required String workerUid,
    required String workDate,
    required String title,
    String? note,
    required double price,
  }) async {
    Database? myDb = await db;
    if (myDb == null) return;
    await myDb.insert(
      'WorkerDailyJobs',
      _withDistributedId({
        'worker_uid': workerUid,
        'work_date': workDate,
        'title': title.trim().isEmpty ? 'Ø¹Ù…Ù„ ÙŠÙˆÙ…ÙŠ' : title.trim(),
        'note': note,
        'price': price,
        'is_settled': 0,
      }),
    );
    CloudSyncService().notifyChange();
  }

  Future<void> deleteWorkerDailyJob(int jobId) async {
    Database? myDb = await db;
    if (myDb == null) return;
    await myDb.delete('WorkerDailyJobs', where: 'id = ?', whereArgs: [jobId]);
    CloudSyncService().notifyChange();
  }

  Future<void> settleWorkerWeek(
    String workerUid,
    int workerId,
    double paymentAmount,
    String recordedBy,
    String workerName, {
    String? caisseName,
  }) async {
    Database? myDb = await db;
    if (myDb == null) return;

    final now = DateTime.now().toIso8601String();
    final cleanKey = workerUid.trim().toLowerCase();

    // Collect all matching identifiers for this worker
    List<String> allKeys = [];
    if (workerUid.trim().isNotEmpty) allKeys.add(workerUid.trim());
    if (workerId > 0) allKeys.add(workerId.toString());

    final empRows = await myDb.query(
      'Employees',
      where: 'uid = ? OR LOWER(email) = ? OR id = ?',
      whereArgs: [workerUid, cleanKey, workerId],
    );
    if (empRows.isNotEmpty) {
      final emp = empRows.first;
      final u = emp['uid']?.toString() ?? '';
      final idStr = emp['id']?.toString() ?? '';
      final email = emp['email']?.toString() ?? '';
      if (u.isNotEmpty && !allKeys.contains(u)) allKeys.add(u);
      if (idStr.isNotEmpty && !allKeys.contains(idStr)) allKeys.add(idStr);
      if (email.isNotEmpty && !allKeys.contains(email)) allKeys.add(email);
    }

    if (allKeys.isEmpty) return;

    final placeholders = List.filled(allKeys.length, '?').join(',');

    // 1. Calculate total earned from unsettled allocations (only manufactured)
    final List<Map<String, dynamic>> allocations = await myDb.rawQuery(
      "SELECT COALESCE(SUM(quantity * worker_price), 0) as total FROM WorkerAllocations WHERE worker_uid IN ($placeholders) AND (is_settled = 0 OR is_settled IS NULL) AND is_manufactured = 1",
      allKeys,
    );
    final double totalAllocEarned =
        (allocations.first['total'] as num?)?.toDouble() ?? 0.0;

    // 1b. Calculate total earned from unsettled daily jobs (Ø¹Ù…Ù„ ÙŠÙˆÙ…ÙŠ)
    final List<Map<String, dynamic>> dailyJobs = await myDb.rawQuery(
      "SELECT COALESCE(SUM(price), 0) as total FROM WorkerDailyJobs WHERE worker_uid IN ($placeholders) AND (is_settled = 0 OR is_settled IS NULL)",
      allKeys,
    );
    final double totalDailyEarned =
        (dailyJobs.first['total'] as num?)?.toDouble() ?? 0.0;

    final double totalEarned = totalAllocEarned + totalDailyEarned;

    // 2. Calculate total advances/loans/payments taken (unsettled)
    final List<Map<String, dynamic>> transactions = await myDb.rawQuery(
      "SELECT COALESCE(SUM(amount), 0) as total FROM WorkerTransactions WHERE worker_uid IN ($placeholders) AND (is_settled = 0 OR is_settled IS NULL)",
      allKeys,
    );
    final double totalPaidBefore =
        (transactions.first['total'] as num?)?.toDouble() ?? 0.0;

    // Net due to worker before this settlement payment
    final double netDueBefore = totalEarned - totalPaidBefore;

    // 3. Mark all current unsettled, manufactured allocations as settled
    await myDb.rawUpdate(
      "UPDATE WorkerAllocations SET is_settled = 1, settled_at = ? WHERE worker_uid IN ($placeholders) AND (is_settled = 0 OR is_settled IS NULL) AND is_manufactured = 1",
      [now, ...allKeys],
    );

    // 3b. Mark all current unsettled daily jobs as settled
    await myDb.rawUpdate(
      "UPDATE WorkerDailyJobs SET is_settled = 1, settled_at = ? WHERE worker_uid IN ($placeholders) AND (is_settled = 0 OR is_settled IS NULL)",
      [now, ...allKeys],
    );

    // 4. Mark all current unsettled transactions as settled
    await myDb.rawUpdate(
      "UPDATE WorkerTransactions SET is_settled = 1, settled_at = ? WHERE worker_uid IN ($placeholders) AND (is_settled = 0 OR is_settled IS NULL)",
      [now, ...allKeys],
    );

    final primaryKey = allKeys.first;

    // 5. Record the actual payment made in SQLite WorkerTransactions
    await myDb.insert(
      'WorkerTransactions',
      _withDistributedId({
        'worker_uid': primaryKey,
        'amount': paymentAmount,
        'transaction_type': 'salary',
        'note': 'ØªØ³ÙˆÙŠØ© Ø£Ø³Ø¨ÙˆØ¹ÙŠØ© - Ø¯ÙØ¹ Ø£Ø³Ø¨ÙˆØ¹ÙŠ',
        'created_at': now,
        'is_settled': 1,
        'settled_at': now,
      }),
    );

    // 6. Record in Treasury as Decaissement (ALWAYS record full payout in selected Caisse)
    if (paymentAmount != 0.0) {
      await insertTreasury(
        'DÃ©caissement',
        paymentAmount.abs(),
        'ØªØ³ÙˆÙŠØ© Ø£Ø³Ø¨ÙˆØ¹ÙŠØ© Ù„Ù„Ø¹Ø§Ù…Ù„ $workerName',
        entityType: 'Worker',
        entityId: workerId > 0 ? workerId : null,
        recordedBy: recordedBy,
        caisseName: caisseName ?? 'Ø§Ù„ØµÙ†Ø¯ÙˆÙ‚ Ø§Ù„Ø±Ø¦ÙŠØ³ÙŠ',
        referenceId: -1,
        createdAt: now,
      );
    }

    // 7. Calculate carryover (the difference)
    final double carryover = paymentAmount - netDueBefore;
    if (carryover != 0.0) {
      await myDb.insert(
        'WorkerTransactions',
        _withDistributedId({
          'worker_uid': primaryKey,
          'amount': carryover,
          'transaction_type': 'advance',
          'note': 'Ø±ØµÙŠØ¯ Ù…Ø±Ø­Ù‘Ù„ Ù…Ù† Ø§Ù„Ø£Ø³Ø¨ÙˆØ¹ Ø§Ù„Ø³Ø§Ø¨Ù‚',
          'created_at': now,
          'is_settled': 0,
        }),
      );
    }

    CloudSyncService().notifyChangeImmediate();
  }

  Future<void> updateItemWorkerAllocation(
    int detailId,
    String? workerUid, {
    double workerPrice = 0.0,
  }) async {
    Database? myDb = await db;
    await myDb!.update(
      'Commandes_details',
      {
        'assigned_worker_uid': workerUid,
        'worker_price': workerUid != null ? workerPrice : 0.0,
        'assigned_at': workerUid != null
            ? DateTime.now().toIso8601String()
            : null,
      },
      where: 'id = ?',
      whereArgs: [detailId],
    );
  }

  /// Saves the order header and every detail row as one SQLite transaction.
  /// If any row fails, SQLite rolls the whole operation back so an existing
  /// order can never keep its total while losing Commandes_details.
  Future<int> saveCommandeWithDetails({
    int? idCommande,
    required int clientId,
    required String status,
    required String description,
    required double remise,
    required double tva,
    required double total,
    required double netPayable,
    required String createdAt,
    int? projectId,
    required List<Map<String, dynamic>> details,
  }) async {
    final myDb = await db;
    if (myDb == null) {
      throw StateError('Ù‚Ø§Ø¹Ø¯Ø© Ø§Ù„Ø¨ÙŠØ§Ù†Ø§Øª ØºÙŠØ± Ù…ØªØ§Ø­Ø©.');
    }
    await _backfillOrderCodes(myDb);
    if (details.isEmpty) {
      throw StateError(
        'Ù„Ø§ ÙŠÙ…ÙƒÙ† Ø­ÙØ¸ Ø·Ù„Ø¨ÙŠØ© Ø¨Ø¯ÙˆÙ† ØªÙØ§ØµÙŠÙ„.',
      );
    }
    if (!total.isFinite || !netPayable.isFinite) {
      throw StateError('Ù…Ø¬Ù…ÙˆØ¹ Ø§Ù„Ø·Ù„Ø¨ÙŠØ© ØºÙŠØ± ØµØ§Ù„Ø­.');
    }

    // File access is intentionally completed before starting the transaction.
    // The SQL transaction then stays short and cannot leave half an order.
    int? detailIdFrom(dynamic rawId) {
      if (rawId is int) return rawId;
      if (rawId is num) return rawId.toInt();
      return int.tryParse(rawId?.toString() ?? '');
    }

    final preparedDetails = await Future.wait(
      details.map((rawDetail) async {
        // Keep the detail ID while editing.  It is the cloud-sync identity of
        // this drawing; replacing it would allow an old copy (and its old
        // colour) to be merged back into the order.
        final detail = Map<String, dynamic>.from(rawDetail)
          ..remove('id_commandes');
        final drawingPath = detail['drawing_image_path']?.toString() ?? '';
        if (drawingPath.isNotEmpty &&
            (detail['drawing_image_base64']?.toString().isEmpty ?? true)) {
          try {
            final drawingFile = File(drawingPath);
            if (await drawingFile.exists()) {
              detail['drawing_image_base64'] = base64Encode(
                await drawingFile.readAsBytes(),
              );
            }
          } catch (_) {}
        }
        return detail;
      }),
    );

    final savedId = await myDb.transaction<int>((txn) async {
      final now = DateTime.now().toIso8601String();
      late final int orderId;

      if (idCommande == null) {
        final newOrderId = _nextDistributedId();
        final orderCode = await _reserveNextOrderCode(txn);
        await txn.insert('Commandes', {
          'id': newOrderId,
          'order_code': orderCode,
          'client_id': clientId,
          'status': status,
          'description': description,
          'remise': remise,
          'tva': tva,
          'total': total,
          'net_payable': netPayable,
          'advance_payment': 0.0,
          'payment_status': 'Unpaid',
          'created_at': createdAt,
          'updated_at': now,
          'project_id': projectId,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
        orderId = newOrderId;
      } else {
        orderId = idCommande;
        final existing = await txn.query(
          'Commandes',
          columns: ['advance_payment', 'order_code'],
          where: 'id = ? OR CAST(id AS TEXT) = ?',
          whereArgs: [orderId, orderId.toString()],
          limit: 1,
        );
        if (existing.isEmpty) {
          final orderCode = orderId > 0 && orderId < 100000
              ? orderId
              : await _reserveNextOrderCode(txn);
          await txn.insert('Commandes', {
            'id': orderId,
            'order_code': orderCode,
            'client_id': clientId,
            'status': status,
            'description': description,
            'remise': remise,
            'tva': tva,
            'total': total,
            'net_payable': netPayable,
            'advance_payment': 0.0,
            'payment_status': 'Unpaid',
            'created_at': createdAt,
            'updated_at': now,
            'project_id': projectId,
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        } else {
          final advance =
              (existing.first['advance_payment'] as num?)?.toDouble() ?? 0.0;
          final existingOrderCode = _positiveInt(existing.first['order_code']);
          final orderCode = existingOrderCode > 0
              ? existingOrderCode
              : await _reserveNextOrderCode(txn);
          final paymentStatus = advance >= netPayable
              ? 'Paid'
              : (advance > 0 ? 'Partial' : 'Unpaid');
          await txn.update(
            'Commandes',
            {
              'order_code': orderCode,
              'client_id': clientId,
              'description': description,
              'remise': remise,
              'tva': tva,
              'total': total,
              'net_payable': netPayable,
              'payment_status': paymentStatus,
              'created_at': createdAt,
              'updated_at': now,
              'project_id': projectId,
            },
            where: 'id = ? OR CAST(id AS TEXT) = ?',
            whereArgs: [orderId, orderId.toString()],
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
      }

      final existingDetails = await txn.query(
        'Commandes_details',
        columns: ['id'],
        where: 'id_commandes = ? OR CAST(id_commandes AS TEXT) = ?',
        whereArgs: [orderId, orderId.toString()],
      );
      final existingDetailIds = <int>{
        for (final row in existingDetails)
          if (detailIdFrom(row['id']) != null) detailIdFrom(row['id'])!,
      };
      final retainedDetailIds = <int>{};

      for (final detail in preparedDetails) {
        final existingDetailId = detailIdFrom(detail['id']);
        final row = Map<String, dynamic>.from(detail)
          ..remove('id')
          ..remove('id_commandes')
          ..['id_commandes'] = orderId
          ..['updated_at'] = now;

        if (existingDetailId != null &&
            existingDetailIds.contains(existingDetailId)) {
          await txn.update(
            'Commandes_details',
            row,
            where: 'id = ? OR CAST(id AS TEXT) = ?',
            whereArgs: [existingDetailId, existingDetailId.toString()],
          );
          retainedDetailIds.add(existingDetailId);
        } else {
          final newDetailId = _nextDistributedId();
          await txn.insert('Commandes_details', {
            ...row,
            'id': newDetailId,
          }, conflictAlgorithm: ConflictAlgorithm.replace);
          retainedDetailIds.add(newDetailId);
        }
      }

      // Delete only drawings that the user actually removed.  This keeps a
      // stable identity for the remaining drawings and produces tombstones
      // only for genuine removals.
      for (final existingDetailId in existingDetailIds) {
        if (retainedDetailIds.contains(existingDetailId)) continue;
        await txn.delete(
          'WorkerAllocations',
          where:
              'commande_detail_id = ? OR CAST(commande_detail_id AS TEXT) = ?',
          whereArgs: [existingDetailId, existingDetailId.toString()],
        );
        await txn.delete(
          'Commandes_details',
          where: 'id = ? OR CAST(id AS TEXT) = ?',
          whereArgs: [existingDetailId, existingDetailId.toString()],
        );
      }

      final countResult = await txn.rawQuery(
        'SELECT COUNT(*) AS count FROM Commandes_details '
        'WHERE id_commandes = ?',
        [orderId],
      );
      final savedDetails = (countResult.first['count'] as num?)?.toInt() ?? 0;
      if (savedDetails != preparedDetails.length) {
        throw StateError(
          'Ù„Ù… ØªÙØ­ÙØ¸ ÙƒÙ„ ØªÙØ§ØµÙŠÙ„ Ø§Ù„Ø·Ù„Ø¨ÙŠØ© '
          '(${preparedDetails.length} Ù…Ø·Ù„ÙˆØ¨Ø©ØŒ $savedDetails Ù…Ø­ÙÙˆØ¸Ø©).',
        );
      }
      return orderId;
    });

    CloudSyncService().notifyChangeImmediate();
    return savedId;
  }

  Future<int> insertCommande(
    int idClient,
    String status,
    String description,
    double remise,
    double tva,
    double total, {
    double advancePayment = 0.0,
    String? createdAt,
    int? projectId,
  }) async {
    final myDb = await db;
    if (myDb == null) {
      throw StateError('قاعدة بيانات الطلبات غير متاحة');
    }
    await _backfillOrderCodes(myDb);
    final netPayable = total - remise + ((total * tva) / 100);
    final now = DateTime.now().toIso8601String();
    final orderDate = createdAt ?? now;
    final distributedId = _nextDistributedId();
    final orderCode = await _reserveNextOrderCode(myDb);
    var res = await myDb.rawInsert(
      'INSERT INTO Commandes (id, order_code, client_id, status, description, remise, tva, total, net_payable, advance_payment, payment_status, created_at, updated_at, project_id) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [
        distributedId,
        orderCode,
        idClient,
        status,
        description,
        remise,
        tva,
        total,
        netPayable,
        advancePayment,
        advancePayment >= netPayable
            ? 'Paid'
            : (advancePayment > 0 ? 'Partial' : 'Unpaid'),
        orderDate,
        now,
        projectId,
      ],
    );
    if (advancePayment > _paymentTolerance) {
      await insertTreasury(
        'Encaissement',
        advancePayment,
        'دفعة افتتاحية للطلبية #$distributedId',
        referenceId: distributedId,
        entityType: 'Client',
        entityId: idClient,
        createdAt: orderDate,
      );
    }
    CloudSyncService().notifyChange();
    return res;
  }

  Future<int> updateCommande({
    required int idCommande,
    String? status,
    String? description,
    double? remise,
    double? tva,
    double? tax,
    double? total,
    double? totalGlobal,
    double? advancePayment,
    String? paymentStatus,
    String? dateCommande,
    double? netPayable,
    int? projectId,
    bool updateProjectId = false,
  }) async {
    Database? myDb = await db;
    final data = <String, dynamic>{};
    if (status != null) data['status'] = status;
    if (description != null) data['description'] = description;
    if (remise != null) data['remise'] = remise;
    if (tva != null) data['tva'] = tva;
    if (tax != null) data['tva'] = tax;
    if (total != null) data['total'] = total;
    if (totalGlobal != null) data['total'] = totalGlobal;
    // Financial amounts are derived from Treasury allocations. Keeping these
    // fields out of regular order edits prevents a payment that is invisible
    // in the cash register and customer statement.
    if (netPayable != null) data['net_payable'] = netPayable;
    if (dateCommande != null) data['created_at'] = dateCommande;
    if (updateProjectId) data['project_id'] = projectId;
    if (data.isNotEmpty) {
      data['updated_at'] = DateTime.now().toIso8601String();
      var res = await myDb!.update(
        'Commandes',
        data,
        where: 'id = ?',
        whereArgs: [idCommande],
      );
      CloudSyncService().notifyChange();
      return res;
    }
    return 0;
  }

  /// Returns true if any item from this commande has been consumed (used in inventory)
  /// i.e., there's a 'Sale' or 'Consumption' transaction referencing this commande
  Future<bool> isCommandeUsedInInventory(int commandeId) async {
    Database? myDb = await db;
    if (myDb == null) return false;
    try {
      final result = await myDb.query(
        'InventoryTransactions',
        where:
            "reference_id = ? AND transaction_type IN ('Sale', 'Consumption', 'Usage')",
        whereArgs: [commandeId],
        limit: 1,
      );
      return result.isNotEmpty;
    } catch (e) {
      return false;
    }
  }

  Future<int> deleteCommande(int id) {
    return _retryAfterDatabaseMove(() => _deleteCommandeOnce(id));
  }

  Future<int> _deleteCommandeOnce(int id) async {
    Database? myDb = await db;
    if (myDb == null) return 0;

    // Track every affected record before it is deleted so Firebase receives
    // the deletion as well, and keep the operation atomic on every device.
    await _ensureSyncTombstoneInfrastructure(myDb);
    final res = await myDb.transaction((txn) async {
      final details = await txn.query(
        'Commandes_details',
        columns: ['id'],
        where: 'id_commandes = ? OR CAST(id_commandes AS TEXT) = ?',
        whereArgs: [id, id.toString()],
      );

      // Some existing databases were created before foreign-key cascades were
      // enabled. Delete dependent rows explicitly so an order never leaves
      // old components, deliveries, or worker assignments behind.
      for (final detail in details) {
        final detailId = detail['id'];
        if (detailId == null) continue;
        await txn.delete(
          'WorkerAllocations',
          where:
              'commande_detail_id = ? OR CAST(commande_detail_id AS TEXT) = ?',
          whereArgs: [detailId, detailId.toString()],
        );
      }
      await txn.delete(
        'Commandes_deliveries',
        where: 'id_commandes = ? OR CAST(id_commandes AS TEXT) = ?',
        whereArgs: [id, id.toString()],
      );
      await txn.delete(
        'Commandes_details',
        where: 'id_commandes = ? OR CAST(id_commandes AS TEXT) = ?',
        whereArgs: [id, id.toString()],
      );
      await txn.delete(
        'Treasury',
        where: "reference_id = ? AND entity_type = 'Client'",
        whereArgs: [id],
      );
      return txn.delete('Commandes', where: 'id = ?', whereArgs: [id]);
    });
    if (res > 0) {
      await _writeDeletedOrderTombstoneToCloud(id);
      CloudSyncService().notifyChangeImmediate();
    }
    return res;
  }

  Future<void> _writeDeletedOrderTombstoneToCloud(int orderId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final workshopId = prefs.getString('workshop_code') ?? '';
      if (workshopId.isEmpty) return;
      await FirebaseFirestore.instance
          .collection('workshops')
          .doc(workshopId)
          .collection('deleted_orders')
          .doc(orderId.toString())
          .set({
            'id': orderId,
            'deleted_at': FieldValue.serverTimestamp(),
            'device_at': DateTime.now().toUtc().toIso8601String(),
            'deleted_by': FirebaseAuth.instance.currentUser?.uid,
          }, SetOptions(merge: true))
          .timeout(const Duration(seconds: 3));
    } catch (e) {
      debugPrint('Failed to write deleted_orders tombstone: $e');
    }
  }

  Future<int> deleteCommandeLocalOnly(int id) {
    return _retryAfterDatabaseMove(() => _deleteCommandeLocalOnlyOnce(id));
  }

  Future<int> _deleteCommandeLocalOnlyOnce(int id) async {
    final myDb = await db;
    if (myDb == null) return 0;
    await _ensureSyncTombstoneInfrastructure(myDb);

    return myDb.transaction((txn) async {
      await txn.update('_sync_runtime_flags', {
        'suppress_tombstones': 1,
      }, where: 'id = 1');
      try {
        final details = await txn.query(
          'Commandes_details',
          columns: ['id'],
          where: 'id_commandes = ? OR CAST(id_commandes AS TEXT) = ?',
          whereArgs: [id, id.toString()],
        );
        for (final detail in details) {
          final detailId = detail['id'];
          if (detailId == null) continue;
          await txn.delete(
            'WorkerAllocations',
            where:
                'commande_detail_id = ? OR CAST(commande_detail_id AS TEXT) = ?',
            whereArgs: [detailId, detailId.toString()],
          );
        }
        await txn.delete(
          'Commandes_deliveries',
          where: 'id_commandes = ? OR CAST(id_commandes AS TEXT) = ?',
          whereArgs: [id, id.toString()],
        );
        await txn.delete(
          'Commandes_details',
          where: 'id_commandes = ? OR CAST(id_commandes AS TEXT) = ?',
          whereArgs: [id, id.toString()],
        );
        await txn.delete(
          'Treasury',
          where: "reference_id = ? AND entity_type = 'Client'",
          whereArgs: [id],
        );
        return await txn.delete('Commandes', where: 'id = ?', whereArgs: [id]);
      } finally {
        await txn.update('_sync_runtime_flags', {
          'suppress_tombstones': 0,
        }, where: 'id = 1');
      }
    });
  }

  Future<int> deleteCommandeDetails(int commandeId) async {
    Database? myDb = await db;
    var res = await myDb!.rawDelete(
      'DELETE FROM Commandes_details WHERE id_commandes = ?',
      [commandeId],
    );
    CloudSyncService().notifyChange();
    return res;
  }

  Future<int> insertCommandeDetail({
    required int idCommande,
    required double largeur,
    required double hauteur,
    String game = '',
    int quantity = 1,
    String glass = '',
    String color = '',
    String volet = '',
    String accessories = '',
    String description = '',
    required double price,
    String windowType = '',
    String partitionsJson = '[]',
    String drawingImagePath = '',
  }) async {
    Database? myDb = await db;
    String? base64Str;
    if (drawingImagePath.isNotEmpty) {
      try {
        final file = File(drawingImagePath);
        if (await file.exists()) {
          final bytes = await file.readAsBytes();
          base64Str = base64Encode(bytes);
        }
      } catch (_) {}
    }

    var res = await myDb!.insert('Commandes_details', {
      'id': _nextDistributedId(),
      'id_commandes': idCommande,
      'largeur': largeur.toInt(),
      'hauteur': hauteur.toInt(),
      'game': game,
      'quantity': quantity,
      'glass': glass,
      'color': color,
      'volet': volet,
      'accessories': accessories,
      'description': description,
      'price': price,
      'window_type': windowType,
      'partitions_json': partitionsJson,
      'drawing_image_path': drawingImagePath,
      if (base64Str != null) 'drawing_image_base64': base64Str,
      'updated_at': DateTime.now().toIso8601String(),
    });
    CloudSyncService().notifyChange();
    return res;
  }

  Future<int> updateCommandeDetailImagePath(int idDetail, String path) async {
    Database? myDb = await db;
    String? base64Str;
    try {
      final file = File(path);
      if (await file.exists()) {
        final bytes = await file.readAsBytes();
        base64Str = base64Encode(bytes);
      }
    } catch (_) {}

    var res = await myDb!.update(
      'Commandes_details',
      {
        'drawing_image_path': path,
        if (base64Str != null) 'drawing_image_base64': base64Str,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [idDetail],
    );
    CloudSyncService().notifyChange();
    return res;
  }

  Future<int> updateCommandeDetailDeliveredQty(
    int idDetail,
    int newDeliveredQty,
  ) async {
    Database? myDb = await db;
    var res = await myDb!.update(
      'Commandes_details',
      {
        'delivered_qty': newDeliveredQty,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [idDetail],
    );
    CloudSyncService().notifyChange();
    return res;
  }

  Future<int> resetCommandeDeliveredQty(int idCommande) async {
    Database? myDb = await db;
    var res = await myDb!.update(
      'Commandes_details',
      {'delivered_qty': 0, 'updated_at': DateTime.now().toIso8601String()},
      where: 'id_commandes = ?',
      whereArgs: [idCommande],
    );
    CloudSyncService().notifyChange();
    return res;
  }

  Future<void> migrateLegacyTreasuryRecords() async {
    Database? myDb = await db;
    if (myDb == null) return;

    try {
      await myDb.execute('''
        CREATE TABLE IF NOT EXISTS Caisses (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL UNIQUE
        )
      ''');

      final checkMain = await myDb.query(
        'Caisses',
        where: "name = 'Ø§Ù„ØµÙ†Ø¯ÙˆÙ‚ Ø§Ù„Ø±Ø¦ÙŠØ³ÙŠ'",
      );
      if (checkMain.isEmpty)
        await myDb.insert(
          'Caisses',
          _withDistributedId({'name': 'Ø§Ù„ØµÙ†Ø¯ÙˆÙ‚ Ø§Ù„Ø±Ø¦ÙŠØ³ÙŠ'}),
        );
      final checkSecond = await myDb.query(
        'Caisses',
        where: "name = 'Ø§Ù„ØµÙ†Ø¯ÙˆÙ‚ Ø§Ù„Ø«Ø§Ù†ÙŠ'",
      );
      if (checkSecond.isEmpty)
        await myDb.insert(
          'Caisses',
          _withDistributedId({'name': 'Ø§Ù„ØµÙ†Ø¯ÙˆÙ‚ Ø§Ù„Ø«Ø§Ù†ÙŠ'}),
        );
      final checkBank = await myDb.query(
        'Caisses',
        where: "name = 'Ø§Ù„Ø¨Ù†Ùƒ'",
      );
      if (checkBank.isEmpty) {
        await myDb.insert(
          'Caisses',
          _withDistributedId({'name': 'Ø§Ù„Ø¨Ù†Ùƒ'}),
        );
      }

      await _ensurePaymentAllocationSchema(myDb);

      // Reconcile only records that pre-date PaymentAllocations. The old
      // implementation created a second Treasury receipt each time this
      // screen opened; the new path derives every order balance once from the
      // actual receipts, and creates a clearly-labelled legacy record only
      // when a historic advance has no cash entry at all.
      final legacyClients = await myDb.rawQuery('''
        SELECT DISTINCT client_id AS id FROM Commandes
        WHERE advance_payment > 0
        UNION
        SELECT DISTINCT entity_id AS id FROM Treasury
        WHERE entity_type = 'Client' AND transaction_type = 'Encaissement'
      ''');
      for (final row in legacyClients) {
        final clientId = _paymentRecordId(row['id']);
        if (clientId == null) continue;
        final existingAllocations = await myDb.rawQuery(
          '''
          SELECT COALESCE(SUM(pa.amount), 0) AS allocated
          FROM PaymentAllocations pa
          JOIN Treasury t ON t.id = pa.treasury_id
          WHERE t.entity_type = 'Client' AND t.entity_id = ?
        ''',
          [clientId],
        );
        final recordedAdvance = await myDb.rawQuery(
          'SELECT COALESCE(SUM(advance_payment), 0) AS paid '
          'FROM Commandes WHERE client_id = ?',
          [clientId],
        );
        if ((_paymentNumber(existingAllocations.first['allocated']) -
                    _paymentNumber(recordedAdvance.first['paid']))
                .abs() >
            _paymentTolerance) {
          await myDb.transaction(
            (txn) => _rebuildClientPaymentLedger(txn, clientId),
          );
        }
      }

      final legacySuppliers = await myDb.rawQuery('''
        SELECT DISTINCT supplier_id AS id FROM Achats
        WHERE paid_amount > 0 AND supplier_id IS NOT NULL
      ''');
      for (final row in legacySuppliers) {
        final supplierId = _paymentRecordId(row['id']);
        if (supplierId == null) continue;
        final existingAllocations = await myDb.rawQuery(
          '''
          SELECT COALESCE(SUM(pa.amount), 0) AS allocated
          FROM PaymentAllocations pa
          JOIN Treasury t ON t.id = pa.treasury_id
          WHERE t.entity_type = 'Supplier' AND t.entity_id = ?
        ''',
          [supplierId],
        );
        final recordedPaid = await myDb.rawQuery(
          'SELECT COALESCE(SUM(paid_amount), 0) AS paid '
          'FROM Achats WHERE supplier_id = ?',
          [supplierId],
        );
        if ((_paymentNumber(existingAllocations.first['allocated']) -
                    _paymentNumber(recordedPaid.first['paid']))
                .abs() >
            _paymentTolerance) {
          await myDb.transaction(
            (txn) => _rebuildSupplierPaymentLedger(txn, supplierId),
          );
        }
      }
    } catch (_) {}
  }

  Future<List<Map<String, dynamic>>> readCaisses() async {
    Database? myDb = await db;
    if (myDb == null) return [];
    try {
      await myDb.execute('''
        CREATE TABLE IF NOT EXISTS Caisses (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL UNIQUE
        )
      ''');
    } catch (_) {}
    var rows = await myDb.query('Caisses', orderBy: 'id ASC');
    var repairedAnyName = false;
    for (final row in rows) {
      final rawName = row['name']?.toString() ?? '';
      final repairedName = _repairLegacyTextEncoding(rawName);
      if (rawName.isEmpty || repairedName == rawName) continue;
      final id = row['id'];
      if (id == null) continue;
      await myDb.update(
        'Caisses',
        {'name': repairedName},
        where: 'id = ?',
        whereArgs: [id],
      );
      await myDb.update(
        'Treasury',
        {'caisse_name': repairedName},
        where: 'caisse_name = ?',
        whereArgs: [rawName],
      );
      repairedAnyName = true;
    }
    if (repairedAnyName) {
      CloudSyncService().notifyChange();
      rows = await myDb.query('Caisses', orderBy: 'id ASC');
    }
    return rows;
  }

  Future<int> insertCaisse(String name) async {
    Database? myDb = await db;
    if (myDb == null) return 0;
    final res = await myDb.insert(
      'Caisses',
      _withDistributedId({'name': name}),
    );
    CloudSyncService().notifyChange();
    return res;
  }

  Future<int> updateCaisseName(int id, String newName, String oldName) async {
    Database? myDb = await db;
    if (myDb == null) return 0;
    final res = await myDb.update(
      'Caisses',
      {'name': newName},
      where: 'id = ?',
      whereArgs: [id],
    );
    await myDb.update(
      'Treasury',
      {'caisse_name': newName},
      where: 'caisse_name = ?',
      whereArgs: [oldName],
    );
    CloudSyncService().notifyChange();
    return res;
  }

  Future<int> deleteCaisse(int id, String name) async {
    Database? myDb = await db;
    if (myDb == null) return 0;
    final res = await myDb.delete('Caisses', where: 'id = ?', whereArgs: [id]);
    final others = await readCaisses();
    if (others.isNotEmpty) {
      final fallbackName = others.first['name'].toString();
      await myDb.update(
        'Treasury',
        {'caisse_name': fallbackName},
        where: 'caisse_name = ?',
        whereArgs: [name],
      );
    }
    CloudSyncService().notifyChange();
    return res;
  }

  Future<int> insertCommandeDelivery(
    int idCommande,
    int clientId,
    String date,
    String itemsJson,
    double totalAmount,
  ) async {
    Database? myDb = await db;
    var res = await myDb!.insert(
      'Commandes_deliveries',
      _withDistributedId({
        'id_commandes': idCommande,
        'client_id': clientId,
        'delivery_date': date,
        'items_json': itemsJson,
        'total_amount': totalAmount,
      }),
    );
    CloudSyncService().notifyChange();
    return res;
  }

  Future<List<Map<String, dynamic>>> readCommandeDeliveries(
    int idCommande,
  ) async {
    Database? myDb = await db;
    return await myDb!.query(
      'Commandes_deliveries',
      where: 'id_commandes = ?',
      whereArgs: [idCommande],
      orderBy: 'id DESC',
    );
  }

  Future<int> updateCommandeDeliveryIsLoaded(
    int deliveryId,
    int isLoaded,
  ) async {
    Database? myDb = await db;
    var res = await myDb!.update(
      'Commandes_deliveries',
      {'is_loaded': isLoaded},
      where: 'id = ?',
      whereArgs: [deliveryId],
    );
    CloudSyncService().notifyChange();
    return res;
  }

  Future<int> addAdvanceToCommande(int idCommande, double amount) async {
    Database? myDb = await db;
    if (myDb == null || amount <= _paymentTolerance) return 0;
    final orderData = await myDb.query(
      'Commandes',
      where: 'id = ?',
      whereArgs: [idCommande],
    );
    if (orderData.isEmpty) return 0;
    final clientId = _paymentRecordId(orderData.first['client_id']);
    if (clientId == null) return 0;

    // Old callers can still add a deposit, but never by writing directly to
    // Commandes. The single Treasury record is allocated to this order.
    return insertTreasury(
      'Encaissement',
      amount,
      'دفعة للطلبية #$idCommande',
      referenceId: idCommande,
      entityType: 'Client',
      entityId: clientId,
    );
  }

  Future<int> insertAchat(
    String invoiceNumber,
    String supplierName,
    double total, {
    int? supplierId,
    int? locationId,
    String? imagePath,
    String? pdfPath,
  }) async {
    Database? myDb = await db;
    try {
      await myDb!.execute("ALTER TABLE Achats ADD COLUMN location_id INTEGER;");
    } catch (_) {}

    // Ensure invoice number is unique
    final existing = await myDb!.query(
      'Achats',
      where: 'invoice_number = ?',
      whereArgs: [invoiceNumber],
    );
    if (existing.isNotEmpty) {
      throw Exception(
        'â•ªâ–’â”˜Ã©â”˜Ã  â•ªÂºâ”˜Ã¤â”˜Ã¼â•ªÂºâ•ªÂ¬â”˜Ãªâ•ªâ–’â•ªâŒ ($invoiceNumber) â”˜Ã â•ªâ”‚â•ªÂ¬â•ªÂ«â•ªÂ»â”˜Ã  â”˜Ã â•ªâ”‚â•ªÂ¿â”˜Ã©â•ªÂºâ”˜Ã¯! â•ªÂºâ”˜Ã¤â•ªâ–’â•ªÂ¼â•ªÂºâ•ªÃ­ â•ªÃ‘â•ªÂ»â•ªÂ«â•ªÂºâ”˜Ã¤ â•ªâ–’â”˜Ã©â”˜Ã  â”˜Ã¼â•ªâ–’â”˜Ã¨â•ªÂ».',
      );
    }

    var res = await myDb.insert(
      'Achats',
      _withDistributedId({
        'invoice_number': invoiceNumber,
        'supplier_name': supplierName,
        'supplier_id': supplierId,
        'location_id': locationId,
        'status': 'Active',
        'total': total,
        'image_path': imagePath,
        'pdf_path': pdfPath,
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      }),
    );
    CloudSyncService().notifyChange();
    return res;
  }

  Future<bool> achatItemExists({
    required int achatId,
    required int itemId,
    required String itemType,
    int? colorId,
  }) async {
    Database? myDb = await db;
    final String where;
    final List<Object?> whereArgs;

    if (colorId == null) {
      where =
          'achat_id = ? AND item_id = ? AND item_type = ? AND color_id IS NULL';
      whereArgs = [achatId, itemId, itemType];
    } else {
      where = 'achat_id = ? AND item_id = ? AND item_type = ? AND color_id = ?';
      whereArgs = [achatId, itemId, itemType, colorId];
    }

    final rows = await myDb!.query(
      'Achat_items',
      columns: ['id'],
      where: where,
      whereArgs: whereArgs,
    );
    return rows.isNotEmpty;
  }

  Future<int> insertAchatItem({
    required int achatId,
    required String itemCode,
    required String itemName,
    required String itemType,
    required int itemId,
    int? colorId,
    required double quantity,
    required double price,
    bool allowDuplicateLine = false,
  }) async {
    Database? myDb = await db;

    if (!allowDuplicateLine &&
        await achatItemExists(
          achatId: achatId,
          itemId: itemId,
          itemType: itemType,
          colorId: colorId,
        )) {
      return 0;
    }

    var res = await myDb!.insert(
      'Achat_items',
      _withDistributedId({
        'achat_id': achatId,
        'item_code': itemCode,
        'item_name': itemName,
        'item_type': itemType,
        'item_id': itemId,
        'color_id': colorId,
        'quantity': quantity,
        'price': price,
      }),
    );
    CloudSyncService().notifyChange();
    return res;
  }

  Future<int> updateAchatItem(
    int id,
    double quantity,
    double price, {
    String? itemCode,
    String? itemName,
  }) async {
    Database? myDb = await db;
    final data = <String, Object?>{'quantity': quantity, 'price': price};
    if (itemCode != null) data['item_code'] = itemCode;
    if (itemName != null) data['item_name'] = itemName;
    var res = await myDb!.update(
      'Achat_items',
      data,
      where: 'id = ?',
      whereArgs: [id],
    );
    CloudSyncService().notifyChange();
    return res;
  }

  Future<List<Map<String, dynamic>>> readAchatItems(int achatId) async {
    Database? myDb = await db;
    return await myDb!.query(
      'Achat_items',
      where: 'achat_id = ?',
      whereArgs: [achatId],
    );
  }

  Future<int> updateAchatStatus(int id, String status) async {
    Database? myDb = await db;
    var res = await myDb!.update(
      'Achats',
      {'status': status, 'updated_at': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [id],
    );
    CloudSyncService().notifyChange();
    return res;
  }

  Future<int> updateAchatPayment(
    int id, {
    double? paidAmount,
    double? remainingAmount,
    String? status,
  }) async {
    Database? myDb = await db;
    final data = <String, Object?>{};
    if (paidAmount != null) data['paid_amount'] = paidAmount;
    if (remainingAmount != null) data['remaining_amount'] = remainingAmount;
    if (status != null) data['status'] = status;
    if (data.isEmpty) return 0;
    data['updated_at'] = DateTime.now().toIso8601String();
    var res = await myDb!.update(
      'Achats',
      data,
      where: 'id = ?',
      whereArgs: [id],
    );
    CloudSyncService().notifyChange();
    return res;
  }

  Future<int> updateAchatInfo(
    int id,
    String invoiceNumber,
    String supplierName,
  ) async {
    Database? myDb = await db;
    var res = await myDb!.update(
      'Achats',
      {
        'invoice_number': invoiceNumber,
        'supplier_name': supplierName,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    CloudSyncService().notifyChange();
    return res;
  }

  Future<int> updateAchatFiles(
    int id, {
    String? imagePath,
    String? pdfPath,
  }) async {
    Database? myDb = await db;
    final data = <String, Object?>{};
    if (imagePath != null) data['image_path'] = imagePath;
    if (pdfPath != null) data['pdf_path'] = pdfPath;
    if (data.isEmpty) return 0;
    data['updated_at'] = DateTime.now().toIso8601String();
    var res = await myDb!.update(
      'Achats',
      data,
      where: 'id = ?',
      whereArgs: [id],
    );
    CloudSyncService().notifyChange();
    return res;
  }

  Future<Map<String, dynamic>?> readAchatById(int achatId) async {
    Database? myDb = await db;
    final rows = await myDb!.query(
      'Achats',
      where: 'id = ?',
      whereArgs: [achatId],
      limit: 1,
    );
    return rows.isNotEmpty ? rows.first : null;
  }

  Future<String> getNextAchatInvoiceNumber() async {
    Database? myDb = await db;
    final rows = await myDb!.query('Achats', columns: ['invoice_number']);
    int maxSuffix = 0;
    final regex = RegExp(r'(\d+)$');

    for (final row in rows) {
      final invoice = (row['invoice_number'] ?? '').toString();
      final match = regex.firstMatch(invoice);
      if (match != null) {
        final suffix = int.tryParse(match.group(1)!) ?? 0;
        if (suffix > maxSuffix) {
          maxSuffix = suffix;
        }
      }
    }

    return 'ACH-${(maxSuffix + 1).toString().padLeft(4, '0')}';
  }

  Future<int> deleteAchat(int id) async {
    Database? myDb = await db;
    if (myDb == null) return 0;

    // Check inventory usage before deletion
    final items = await myDb.query(
      'Achat_items',
      where: 'achat_id = ?',
      whereArgs: [id],
    );

    // 1. Verify quantities
    for (var item in items) {
      double qty = (item['quantity'] as num).toDouble();

      final invRows = await myDb.query(
        'Inventory',
        where:
            'item_id = ? AND item_type = ? AND (color_id = ? OR (color_id IS NULL AND ? IS NULL)) AND location_id = ?',
        whereArgs: [
          item['item_id'],
          item['item_type'],
          item['color_id'],
          item['color_id'],
          1,
        ],
      );

      double currentQty = 0;
      if (invRows.isNotEmpty) {
        currentQty = (invRows.first['quantity'] as num).toDouble();
      }

      if (currentQty < qty) {
        throw Exception(
          "?? ???? ??? ???????? ???? ?? ??????? ??? ??????? ???? ?? ??????? ?? ????????.",
        );
      }
    }

    // 2. Silent deletion (as if it never existed)
    await myDb.transaction((txn) async {
      for (var item in items) {
        double qty = (item['quantity'] as num).toDouble();

        final invRows = await txn.query(
          'Inventory',
          where:
              'item_id = ? AND item_type = ? AND (color_id = ? OR (color_id IS NULL AND ? IS NULL)) AND location_id = ?',
          whereArgs: [
            item['item_id'],
            item['item_type'],
            item['color_id'],
            item['color_id'],
            1,
          ],
        );

        if (invRows.isNotEmpty) {
          double currentQty = (invRows.first['quantity'] as num).toDouble();
          double newQty = currentQty - qty;

          if (newQty <= 0) {
            await txn.delete(
              'Inventory',
              where: 'id = ?',
              whereArgs: [invRows.first['id']],
            );
          } else {
            await txn.update(
              'Inventory',
              {'quantity': newQty},
              where: 'id = ?',
              whereArgs: [invRows.first['id']],
            );
          }
        }

        await txn.delete(
          'InventoryTransactions',
          where:
              'reference_id = ? AND transaction_type = ? AND item_id = ? AND item_type = ?',
          whereArgs: [id, 'Purchase', item['item_id'], item['item_type']],
        );
      }

      await txn.delete('Achat_items', where: 'achat_id = ?', whereArgs: [id]);
      await txn.delete(
        'Treasury',
        where: "reference_id = ? AND entity_type = 'Supplier'",
        whereArgs: [id],
      );
      await txn.delete('Achats', where: 'id = ?', whereArgs: [id]);
    });

    CloudSyncService().notifyChange();

    // ??? ??? Achat ??? Firestore ??????? (???? ??? ???? legacy sync)
    try {
      final prefs = await SharedPreferences.getInstance();
      final workshopId = prefs.getString('workshop_code');
      if (workshopId != null && workshopId.isNotEmpty) {
        final wsRef = FirebaseFirestore.instance
            .collection('workshops')
            .doc(workshopId);
        // ??? ??? legacy path
        await FirebaseFirestore.instance
            .collection('users')
            .doc(workshopId)
            .collection('Achats')
            .doc('$id')
            .delete();
        // ??? tombstone ????? ??? ?????? ???
        await wsRef.collection('deleted_achats').doc('$id').set({
          'id': id,
          'deleted_at': FieldValue.serverTimestamp(),
        });
      }
    } catch (e) {
      debugPrint('Failed to delete Achat from Firestore legacy: $e');
    }

    return 1;
  }

  Future<List<Map<String, dynamic>>> readAchats() async {
    Database? myDb = await db;
    return await myDb!.query('Achats', orderBy: 'created_at DESC');
  }

  Future<List<Map<String, dynamic>>> readAchatsBySupplierName(
    String supplierName,
  ) async {
    Database? myDb = await db;
    return await myDb!.query(
      'Achats',
      where: 'supplier_name = ?',
      whereArgs: [supplierName],
      orderBy: 'created_at DESC',
    );
  }

  Future<List<Map<String, dynamic>>> readAchatsBySupplier(
    int supplierId,
  ) async {
    Database? myDb = await db;
    return await myDb!.query(
      'Achats',
      where: 'supplier_id = ?',
      whereArgs: [supplierId],
      orderBy: 'created_at DESC',
    );
  }

  Future<int> updateAchatTotal(int achatId, double total) async {
    Database? myDb = await db;
    var res = await myDb!.update(
      'Achats',
      {
        'total': total,
        'remaining_amount':
            total -
            (((await myDb.query(
                          'Achats',
                          where: 'id = ?',
                          whereArgs: [achatId],
                        )).first['paid_amount']
                        as num?) ??
                    0)
                .toDouble(),
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [achatId],
    );
    CloudSyncService().notifyChange();
    return res;
  }

  Future<void> returnAchatInvoice(
    int achatId,
    List<Map<String, dynamic>> returnedItems,
    double refundedAmount,
  ) async {
    Database? myDb = await db;
    if (myDb == null) return;

    for (var item in returnedItems) {
      final itemId = item['id'] as int;
      final returnQty = (item['returnQty'] as num).toDouble();
      final currentQty = (item['currentQty'] as num).toDouble();
      final remainingQty = currentQty - returnQty;

      if (remainingQty <= 0) {
        await myDb.delete('Achat_items', where: 'id = ?', whereArgs: [itemId]);
      } else {
        await myDb.update(
          'Achat_items',
          {'quantity': remainingQty},
          where: 'id = ?',
          whereArgs: [itemId],
        );
      }
    }

    if (refundedAmount > 0) {
      final achatRes = await myDb.query(
        'Achats',
        columns: ['supplier_id'],
        where: 'id = ?',
        whereArgs: [achatId],
      );
      int? supplierId;
      if (achatRes.isNotEmpty) {
        supplierId = achatRes.first['supplier_id'] as int?;
      }

      await myDb.insert(
        'Treasury',
        _withDistributedId({
          'transaction_type': 'Encaissement',
          'amount': refundedAmount,
          'description':
              'Ø§Ø³ØªØ±Ø¬Ø§Ø¹ Ù…Ù† Ø§Ù„Ù…ÙˆØ±Ø¯ - ÙØ§ØªÙˆØ±Ø© Ù…Ø´ØªØ±ÙŠØ§Øª Ø±Ù‚Ù… $achatId',
          'reference_id': achatId,
          'entity_type': 'Supplier',
          'entity_id': supplierId,
          'recorded_by': 'system',
          'created_at': DateTime.now().toIso8601String(),
          'old_balance': 0.0,
          'new_balance': 0.0,
          'caisse_name': 'Ø§Ù„ØµÙ†Ø¯ÙˆÙ‚ Ø§Ù„Ø±Ø¦ÙŠØ³ÙŠ',
          'payment_method': 'Ù†Ù‚Ø¯Ø§Ù‹ / EspÃ¨ce',
        }),
      );
    }

    final newItems = await myDb.query(
      'Achat_items',
      where: 'achat_id = ?',
      whereArgs: [achatId],
    );
    double newTotal = 0.0;
    for (var i in newItems) {
      newTotal +=
          ((i['quantity'] as num?)?.toDouble() ?? 0) *
          ((i['price'] as num?)?.toDouble() ?? 0);
    }

    String newStatus = newTotal == 0 ? 'Returned' : 'Partial Returned';

    final achatRows = await myDb.query(
      'Achats',
      where: 'id = ?',
      whereArgs: [achatId],
    );
    if (achatRows.isNotEmpty) {
      double currentPaid =
          (achatRows.first['paid_amount'] as num?)?.toDouble() ?? 0.0;
      double newPaid = (currentPaid - refundedAmount).clamp(
        0.0,
        double.infinity,
      );
      double newRemaining = (newTotal - newPaid).clamp(0.0, double.infinity);

      await myDb.update(
        'Achats',
        {
          'total': newTotal,
          'paid_amount': newPaid,
          'remaining_amount': newRemaining,
          'status': newStatus,
          'updated_at': DateTime.now().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [achatId],
      );
    }

    CloudSyncService().notifyChange();
  }

  Future<int> deleteAchatItem(int id) async {
    Database? myDb = await db;
    if (myDb == null) return 0;

    final items = await myDb.query(
      'Achat_items',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (items.isNotEmpty) {
      var item = items.first;
      double qty = (item['quantity'] as num).toDouble();
      await updateInventory(
        itemId: item['item_id'] as int,
        itemType: item['item_type'] as String,
        colorId: item['color_id'] as int?,
        locationId: 1,
        // â•ªÂºâ”˜Ã¤â”˜Ã â•ªâ”‚â•ªÂ¬â”˜Ãªâ•ªÂ»â•ªâ•£ â•ªÂºâ”˜Ã¤â•ªâ–’â•ªÂªâ”˜Ã¨â•ªâ”‚â”˜Ã¨ â”˜Ã¢â•ªÂºâ”˜Ã¼â•ªÂ¬â•ªâ–’â•ªÂºâ•ªâ•¢â”˜Ã¨
        quantityChange: -qty,
        // â•ªÂ«â•ªâ•¡â”˜Ã  â•ªÂºâ”˜Ã¤â”˜Ã¢â”˜Ã â”˜Ã¨â•ªâŒ
        transactionType: 'Purchase Item Deleted',
        referenceId: item['achat_id'] as int,
      );
    }

    var res = await myDb.delete(
      'Achat_items',
      where: 'id = ?',
      whereArgs: [id],
    );
    CloudSyncService().notifyChange();
    return res;
  }

  Future<List<Map<String, dynamic>>> readSuppliers() async {
    Database? myDb = await db;
    return await myDb!.query('Suppliers', orderBy: 'created_at DESC');
  }

  Future<int> insertSupplier(Map<String, dynamic> data) async {
    Database? myDb = await db;
    var res = await myDb!.insert(
      'Suppliers',
      _withDistributedId({
        'name': data['name'] ?? '',
        'phone': data['phone'] ?? '',
        'email': data['email'] ?? '',
        'notes': data['notes'] ?? '',
        'latitude': data['latitude'],
        'longitude': data['longitude'],
        'created_at': DateTime.now().toIso8601String(),
      }),
    );
    CloudSyncService().notifyChange();
    return res;
  }

  Future<int> updateSupplier(int id, Map<String, dynamic> data) async {
    Database? myDb = await db;
    var res = await myDb!.update(
      'Suppliers',
      {
        'name': data['name'] ?? '',
        'phone': data['phone'] ?? '',
        'email': data['email'] ?? '',
        'notes': data['notes'] ?? '',
        'latitude': data['latitude'],
        'longitude': data['longitude'],
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    CloudSyncService().notifyChange();
    return res;
  }

  Future<int> deleteSupplier(int id) async {
    Database? myDb = await db;
    var res = await myDb!.delete('Suppliers', where: 'id = ?', whereArgs: [id]);
    CloudSyncService().notifyChange();
    return res;
  }

  Future<int> insertWorkerTransaction(
    String workerUid,
    double amount,
    String transactionType,
    String note, {
    String? caisseName,
    String? recordedBy,
  }) async {
    Database? myDb = await db;
    final now = DateTime.now().toIso8601String();

    var res = await myDb!.insert(
      'WorkerTransactions',
      _withDistributedId({
        'worker_uid': workerUid,
        'amount': amount,
        'transaction_type': transactionType,
        'note': note,
        'created_at': now,
      }),
    );

    try {
      final List<Map<String, dynamic>> workers = await myDb.query(
        'Employees',
        where: 'uid = ?',
        whereArgs: [workerUid],
        limit: 1,
      );
      if (workers.isNotEmpty) {
        final worker = workers.first;
        final workerId = worker['id'] as int;
        final workerName = worker['name']?.toString() ?? '';

        String desc =
            (transactionType == 'advance'
                ? 'Ø³Ù„ÙØ© Ù„Ù„Ø¹Ø§Ù…Ù„ '
                : 'Ø£Ø¬Ø±Ø© Ù„Ù„Ø¹Ø§Ù…Ù„ ') +
            workerName;
        if (note.isNotEmpty) desc += ' - $note';

        await insertTreasury(
          'DÃ©caissement',
          amount,
          desc,
          entityType: 'Worker',
          entityId: workerId,
          recordedBy: recordedBy ?? 'system',
          caisseName: caisseName ?? 'Ø§Ù„ØµÙ†Ø¯ÙˆÙ‚ Ø§Ù„Ø±Ø¦ÙŠØ³ÙŠ',
          createdAt: now,
        );
      }
    } catch (e) {
      debugPrint('Error inserting worker transaction to treasury: $e');
    }

    CloudSyncService().notifyChangeImmediate();
    return res;
  }

  Future<List<Map<String, dynamic>>> readWorkerTransactions(
    String workerUid,
  ) async {
    Database? myDb = await db;
    if (myDb == null) return [];

    final cleanKey = workerUid.trim().toLowerCase();
    if (cleanKey.isEmpty) return [];

    return await myDb.rawQuery(
      '''
      SELECT wt.*
      FROM WorkerTransactions wt
      WHERE wt.worker_uid = ?
        OR LOWER(wt.worker_uid) = ?
        OR wt.worker_uid IN (
          SELECT CAST(id AS TEXT) FROM Employees WHERE (uid = ? OR LOWER(email) = ? OR CAST(id AS TEXT) = ?)
        )
        OR wt.worker_uid IN (
          SELECT uid FROM Employees WHERE (uid = ? OR LOWER(email) = ? OR CAST(id AS TEXT) = ?)
        )
        OR wt.worker_uid IN (
          SELECT email FROM Employees WHERE (uid = ? OR LOWER(email) = ? OR CAST(id AS TEXT) = ?)
        )
      ORDER BY wt.created_at DESC
    ''',
      [
        workerUid,
        cleanKey,
        cleanKey,
        cleanKey,
        cleanKey,
        cleanKey,
        cleanKey,
        cleanKey,
        cleanKey,
        cleanKey,
        cleanKey,
      ],
    );
  }

  Future<void> updateWorkerTransaction(
    int transactionId,
    String workerUid,
    int workerId,
    double oldAmount,
    double newAmount,
    String oldType,
    String newType,
    String oldNote,
    String newNote,
    String workerName,
  ) async {
    Database? myDb = await db;
    if (myDb == null) return;

    await myDb.update(
      'WorkerTransactions',
      {'amount': newAmount, 'transaction_type': newType, 'note': newNote},
      where: 'id = ?',
      whereArgs: [transactionId],
    );

    final List<Map<String, dynamic>> records = await myDb.query(
      'Treasury',
      where:
          "transaction_type = 'DÃ©caissement' AND entity_type = 'Worker' AND entity_id = ? AND amount = ?",
      whereArgs: [workerId, oldAmount],
      limit: 1,
    );

    if (records.isNotEmpty) {
      final treasuryId = records.first['id'] as int;
      String desc =
          (newType == 'advance'
              ? 'Ø³Ù„ÙØ© Ù„Ù„Ø¹Ø§Ù…Ù„ '
              : 'Ø£Ø¬Ø±Ø© Ù„Ù„Ø¹Ø§Ù…Ù„ ') +
          workerName;
      if (newNote.isNotEmpty) desc += ' - $newNote';

      await myDb.update(
        'Treasury',
        {'amount': newAmount, 'description': desc},
        where: 'id = ?',
        whereArgs: [treasuryId],
      );
    }
    CloudSyncService().notifyChange();
  }

  Future<void> deleteWorkerTransaction(
    int transactionId,
    int workerId,
    double amount,
  ) async {
    Database? myDb = await db;
    if (myDb == null) return;

    await myDb.delete(
      'WorkerTransactions',
      where: 'id = ?',
      whereArgs: [transactionId],
    );

    final List<Map<String, dynamic>> records = await myDb.query(
      'Treasury',
      where:
          "transaction_type = 'DÃ©caissement' AND entity_type = 'Worker' AND entity_id = ? AND amount = ?",
      whereArgs: [workerId, amount],
      limit: 1,
    );

    if (records.isNotEmpty) {
      final treasuryId = records.first['id'] as int;
      await myDb.delete('Treasury', where: 'id = ?', whereArgs: [treasuryId]);
    }
    CloudSyncService().notifyChange();
  }

  //////////////////////////////////// Colors //////////////////////////////////////
  Future<void> _repairKnownColorRows(Database myDb) async {
    if (_knownColorsRepaired) return;
    _knownColorsRepaired = true;
    var changed = false;
    try {
      final rows = await myDb.query('Colors');
      for (final row in rows) {
        final id = row['id'];
        if (id == null) continue;
        final rawName = row['name']?.toString() ?? '';
        final repairedName = _canonicalLegacyColorName(rawName);
        final rawHex = row['hex_code']?.toString() ?? '';
        final repairedHex = _canonicalKnownColorHex(repairedName, rawHex);
        if (repairedName == rawName && repairedHex == rawHex) continue;
        await myDb.update(
          'Colors',
          {'name': repairedName, 'hex_code': repairedHex},
          where: 'id = ?',
          whereArgs: [id],
        );
        changed = true;
      }
    } catch (_) {
      _knownColorsRepaired = false;
      return;
    }
    if (changed) CloudSyncService().notifyCatalogChange();
  }

  Future<List<Map<String, dynamic>>> readColors() async {
    Database? myDb = await db;
    await _repairKnownColorRows(myDb!);
    return myDb!.query(
      'Colors',
      where: 'is_active = 1 OR is_active IS NULL',
      orderBy: 'name COLLATE NOCASE ASC',
    );
  }

  Future<List<Map<String, dynamic>>> readAccessoryColors() async {
    Database? myDb = await db;
    var result = await myDb!.rawQuery('''
      SELECT DISTINCT Colors.* FROM Colors 
      INNER JOIN AccessoryColorPrices ON Colors.id = AccessoryColorPrices.color_id
      WHERE Colors.is_active = 1 OR Colors.is_active IS NULL
    ''');
    if (result.isEmpty) {
      return await readColors();
    }
    return result;
  }

  bool _isInsertingColors = false;

  Future<void> _insertDefaultColors(Database myDb) async {
    if (_isInsertingColors) return;
    _isInsertingColors = true;
    try {
      // Double check if it's still empty to prevent race condition
      var check = await myDb.query('Colors');
      if (check.isNotEmpty) return;

      final defaults = [
        {'name': 'أبيض', 'hex_code': '#FFFFFF', 'type': 'Global'},
        {'name': 'بني', 'hex_code': '#795548', 'type': 'Global'},
        {'name': 'رمادي', 'hex_code': '#9E9E9E', 'type': 'Global'},
        {'name': 'أسود', 'hex_code': '#000000', 'type': 'Global'},
        {'name': 'بيج', 'hex_code': '#F5F5DC', 'type': 'Global'},
        {'name': 'خام', 'hex_code': '#E0E0E0', 'type': 'Global'},
      ];
      for (var c in defaults) {
        await myDb.insert('Colors', c);
      }
    } finally {
      _isInsertingColors = false;
    }
  }

  Future<void> cleanDuplicateColors() async {
    Database? myDb = await db;
    if (myDb == null) return;

    await _repairKnownColorRows(myDb);

    var duplicates = await myDb.rawQuery('''
      SELECT name, COUNT(*) as count, MIN(id) as keep_id
      FROM Colors
      GROUP BY name
      HAVING count > 1
    ''');

    for (var dup in duplicates) {
      String name = dup['name'] as String;
      int keepId = dup['keep_id'] as int;

      var allIds = await myDb.query(
        'Colors',
        columns: ['id'],
        where: 'name = ? AND id != ?',
        whereArgs: [name, keepId],
      );
      for (var row in allIds) {
        int oldId = row['id'] as int;

        await myDb.rawUpdate(
          'UPDATE OR IGNORE SeriesColorPrices SET color_id = ? WHERE color_id = ?',
          [keepId, oldId],
        );
        await myDb.rawUpdate(
          'UPDATE OR IGNORE SectionColorPrices SET color_id = ? WHERE color_id = ?',
          [keepId, oldId],
        );
        await myDb.rawUpdate(
          'UPDATE OR IGNORE AccessoryColorPrices SET color_id = ? WHERE color_id = ?',
          [keepId, oldId],
        );
        await myDb.rawUpdate(
          'UPDATE OR IGNORE ProfileColors SET color_id = ? WHERE color_id = ?',
          [keepId, oldId],
        );

        await myDb.delete('Colors', where: 'id = ?', whereArgs: [oldId]);
      }
    }

    if (duplicates.isNotEmpty) CloudSyncService().notifyCatalogChange();
  }

  Future<int> insertColor(
    String name,
    String hexCode,
    String type, {
    double price = 0.0,
  }) async {
    Database? myDb = await db;
    final repairedName = _canonicalLegacyColorName(name);
    final repairedHex = _canonicalKnownColorHex(repairedName, hexCode);
    var res = await myDb!.insert('Colors', {
      'name': repairedName,
      'hex_code': repairedHex,
      'type': type,
      'price': price,
    });
    CloudSyncService().notifyCatalogChange();
    return res;
  }

  Future<int> updateColor(
    int id,
    String name,
    String hexCode,
    String type, {
    double price = 0.0,
  }) async {
    Database? myDb = await db;
    final repairedName = _canonicalLegacyColorName(name);
    final repairedHex = _canonicalKnownColorHex(repairedName, hexCode);
    var res = await myDb!.update(
      'Colors',
      {
        'name': repairedName,
        'hex_code': repairedHex,
        'type': type,
        'price': price,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    CloudSyncService().notifyCatalogChange();
    return res;
  }

  Future<int> updateColorIsGlass(int id, int isGlass) async {
    Database? myDb = await db;
    var res = await myDb!.update(
      'Colors',
      {'is_glass_color': isGlass},
      where: 'id = ?',
      whereArgs: [id],
    );
    CloudSyncService().notifyCatalogChange();
    return res;
  }

  Future<int> deleteColor(int id) async {
    Database? myDb = await db;
    var res = await myDb!.update(
      'Colors',
      {'is_active': 0},
      where: 'id = ?',
      whereArgs: [id],
    );
    CloudSyncService().notifyCatalogChange();
    return res;
  }

  Future<List<int>> getProfilesForColor(int colorId) async {
    Database? myDb = await db;
    if (myDb == null) return <int>[];
    await _ensureProfileColorsSyncIds(myDb);
    var res = await myDb!.query(
      'ProfileColors',
      where: 'color_id = ?',
      whereArgs: [colorId],
    );
    return res.map((e) => e['profile_id'] as int).toList();
  }

  Future<void> setProfilesForColor(int colorId, List<int> profileIds) async {
    Database? myDb = await db;
    if (myDb == null) return;
    await _ensureProfileColorsSyncIds(myDb);
    final targetProfileIds = profileIds.toSet();
    final existingRows = await myDb.query(
      'ProfileColors',
      columns: ['profile_id'],
      where: 'color_id = ?',
      whereArgs: [colorId],
    );
    final existingProfileIds = existingRows
        .map((row) => (row['profile_id'] as num).toInt())
        .toSet();
    await myDb.transaction((txn) async {
      for (final profileId in existingProfileIds.difference(targetProfileIds)) {
        await txn.delete(
          'ProfileColors',
          where: 'profile_id = ? AND color_id = ?',
          whereArgs: [profileId, colorId],
        );
        await txn.insert('ProfileColorConfig', {
          'id': profileId,
          'profile_id': profileId,
          'configured_at': DateTime.now().toUtc().toIso8601String(),
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      for (final profileId in targetProfileIds.difference(existingProfileIds)) {
        await txn.insert('ProfileColors', {
          'id': _profileColorSyncId(profileId, colorId),
          'profile_id': profileId,
          'color_id': colorId,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
        await txn.insert('ProfileColorConfig', {
          'id': profileId,
          'profile_id': profileId,
          'configured_at': DateTime.now().toUtc().toIso8601String(),
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      for (final profileId in targetProfileIds.intersection(
        existingProfileIds,
      )) {
        await txn.insert('ProfileColorConfig', {
          'id': profileId,
          'profile_id': profileId,
          'configured_at': DateTime.now().toUtc().toIso8601String(),
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
    CloudSyncService().notifyCatalogChange();
  }

  Future<void> setColorsForProfile(
    int profileId,
    Iterable<int> colorIds,
  ) async {
    final myDb = await db;
    if (myDb == null) return;
    await _ensureProfileColorsSyncIds(myDb);
    final uniqueColorIds = colorIds.toSet().toList()..sort();
    final existingRows = await myDb.query(
      'ProfileColors',
      columns: ['color_id'],
      where: 'profile_id = ?',
      whereArgs: [profileId],
    );
    final existingColorIds = existingRows
        .map((row) => (row['color_id'] as num).toInt())
        .toSet();
    final targetColorIds = uniqueColorIds.toSet();
    await myDb.transaction((txn) async {
      for (final colorId in existingColorIds.difference(targetColorIds)) {
        await txn.delete(
          'ProfileColors',
          where: 'profile_id = ? AND color_id = ?',
          whereArgs: [profileId, colorId],
        );
      }
      for (final colorId in targetColorIds.difference(existingColorIds)) {
        await txn.insert('ProfileColors', {
          'id': _profileColorSyncId(profileId, colorId),
          'profile_id': profileId,
          'color_id': colorId,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
      }
      await txn.insert('ProfileColorConfig', {
        'id': profileId,
        'profile_id': profileId,
        'configured_at': DateTime.now().toUtc().toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });
    CloudSyncService().notifyCatalogChange();
  }

  Future<void> setColorForProfile({
    required int profileId,
    required int colorId,
    required bool enabled,
  }) async {
    final myDb = await db;
    if (myDb == null) return;
    await _ensureProfileColorsSyncIds(myDb);
    await myDb.transaction((txn) async {
      if (enabled) {
        await txn.insert('ProfileColors', {
          'id': _profileColorSyncId(profileId, colorId),
          'profile_id': profileId,
          'color_id': colorId,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
      } else {
        await txn.delete(
          'ProfileColors',
          where: 'profile_id = ? AND color_id = ?',
          whereArgs: [profileId, colorId],
        );
      }
      await txn.insert('ProfileColorConfig', {
        'id': profileId,
        'profile_id': profileId,
        'configured_at': DateTime.now().toUtc().toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });
    CloudSyncService().notifyCatalogChange();
  }

  bool _isShutterDefaultPriceColorName(dynamic rawName) {
    final normalized = (rawName ?? '')
        .toString()
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[\s_\-]+'), '')
        .replaceAll('ى', 'ي');
    return const {'grey', 'gray', 'gris', 'رمادي'}.contains(normalized);
  }

  Future<int> _ensureShutterDefaultPriceColor(DatabaseExecutor executor) async {
    final colors = await executor.query(
      'Colors',
      columns: const ['id', 'name'],
      orderBy: 'id ASC',
    );
    for (final color in colors) {
      if (_isShutterDefaultPriceColorName(color['name'])) {
        final id = color['id'];
        if (id is num) return id.toInt();
        final parsed = int.tryParse('$id');
        if (parsed != null) return parsed;
      }
    }

    return executor.insert('Colors', {
      'name': 'رمادي',
      'hex_code': '#808080',
      'type': 'Global',
      'price': 0.0,
    });
  }

  /// Makes the grey colour the only base price for shutter components.
  ///
  /// The former `ShutterComponents.price` value is retained only as a mirror
  /// for old screens that still read that column directly.  The editable and
  /// authoritative value is always the row in `ShutterColorPrices` for the
  /// grey colour.
  Future<int> ensureShutterComponentsUseGreyPrice() async {
    final myDb = await db;
    if (myDb == null) {
      throw StateError('Shutter component database is not available.');
    }
    // Very old local catalogues may predate this compatibility mirror.  It is
    // no longer edited by the UI, but it remains available for older
    // calculation paths while their values are migrated to grey.
    try {
      await myDb.execute(
        'ALTER TABLE ShutterComponents ADD COLUMN price REAL NOT NULL DEFAULT 0.0;',
      );
    } catch (_) {
      // The current schema already contains the column.
    }
    await _ensureShutterColorTables(myDb);

    var changed = false;
    final greyColorId = await myDb.transaction<int>((txn) async {
      final defaultColorId = await _ensureShutterDefaultPriceColor(txn);
      final components = await txn.query(
        'ShutterComponents',
        columns: const ['id', 'price'],
      );

      for (final component in components) {
        final rawComponentId = component['id'];
        final componentId = rawComponentId is num
            ? rawComponentId.toInt()
            : int.tryParse('$rawComponentId');
        if (componentId == null) continue;

        final legacyPrice = _readStoredNumber(component['price']) ?? 0.0;
        final greyRows = await txn.query(
          'ShutterColorPrices',
          columns: const ['price'],
          where: 'shutter_component_id = ? AND color_id = ?',
          whereArgs: [componentId, defaultColorId],
          limit: 1,
        );
        final greyPrice = greyRows.isEmpty
            ? legacyPrice
            : (_readStoredNumber(greyRows.first['price']) ?? 0.0);

        if (greyRows.isEmpty) {
          await txn.insert('ShutterColorPrices', {
            'shutter_component_id': componentId,
            'color_id': defaultColorId,
            'price': greyPrice,
          });
          changed = true;
        }
        await txn.insert('ShutterComponentColors', {
          'shutter_component_id': componentId,
          'color_id': defaultColorId,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);

        // Keep legacy calculation paths coherent while the old column is
        // gradually retired.  It is never shown as an editable default price.
        if ((legacyPrice - greyPrice).abs() > 0.000001) {
          await txn.update(
            'ShutterComponents',
            {'price': greyPrice},
            where: 'id = ?',
            whereArgs: [componentId],
          );
          changed = true;
        }
      }
      return defaultColorId;
    });

    if (changed) CloudSyncService().notifyCatalogChange();
    return greyColorId;
  }

  Future<void> setShutterColorForComponent({
    required int shutterComponentId,
    required int colorId,
    required bool enabled,
    double price = 0.0,
  }) async {
    final myDb = await db;
    if (myDb == null) {
      throw StateError('Shutter component database is not available.');
    }

    // Every component has a grey base-colour price.  Other colours are
    // optional overrides.
    await _ensureShutterColorTables(myDb);
    final defaultColorId = await _ensureShutterDefaultPriceColor(myDb);
    if (!enabled && colorId == defaultColorId) {
      // The grey row is the base price and must remain available for the
      // catalogue and required-goods calculations.
      await ensureShutterComponentsUseGreyPrice();
      return;
    }
    final component = await myDb.query(
      'ShutterComponents',
      columns: const ['id'],
      where: 'id = ?',
      whereArgs: [shutterComponentId],
      limit: 1,
    );
    if (component.isEmpty) {
      throw StateError('The selected shutter component no longer exists.');
    }

    await myDb.transaction((txn) async {
      if (enabled) {
        await txn.insert('ShutterColorPrices', {
          'shutter_component_id': shutterComponentId,
          'color_id': colorId,
          'price': price,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
        await txn.insert('ShutterComponentColors', {
          'shutter_component_id': shutterComponentId,
          'color_id': colorId,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
        if (colorId == defaultColorId) {
          await txn.update(
            'ShutterComponents',
            {'price': price},
            where: 'id = ?',
            whereArgs: [shutterComponentId],
          );
        }
      } else {
        await txn.delete(
          'ShutterColorPrices',
          where: 'shutter_component_id = ? AND color_id = ?',
          whereArgs: [shutterComponentId, colorId],
        );
        await txn.delete(
          'ShutterComponentColors',
          where: 'shutter_component_id = ? AND color_id = ?',
          whereArgs: [shutterComponentId, colorId],
        );
      }
    });

    if (enabled) {
      final stored = await myDb.query(
        'ShutterColorPrices',
        columns: const ['price'],
        where: 'shutter_component_id = ? AND color_id = ?',
        whereArgs: [shutterComponentId, colorId],
        limit: 1,
      );
      final savedPrice = stored.isEmpty
          ? null
          : _readStoredNumber(stored.first['price']);
      if (stored.isEmpty ||
          savedPrice == null ||
          (savedPrice - price).abs() > 0.000001) {
        throw StateError('The shutter colour price was not persisted.');
      }
    }
    CloudSyncService().notifyCatalogChange();
  }

  Future<List<Map<String, dynamic>>> getColorsForProfile(int profileId) async {
    Database? myDb = await db;
    await _repairKnownColorRows(myDb!);
    final initialized = await _ensureProfileColorDefaults(
      myDb,
      profileId: profileId,
    );
    if (initialized) CloudSyncService().notifyCatalogChange();
    return myDb!.rawQuery(
      '''
      SELECT DISTINCT c.* FROM Colors c
      INNER JOIN ProfileColors pc
        ON c.id = pc.color_id AND pc.profile_id = ?
      WHERE (c.is_active = 1 OR c.is_active IS NULL)
      ORDER BY c.name COLLATE NOCASE ASC
    ''',
      [profileId],
    );
  }

  Future<Set<int>> getColorIdsForProfile(int profileId) async {
    final myDb = await db;
    if (myDb == null) return <int>{};
    await _ensureProfileColorsSyncIds(myDb);
    final rows = await myDb.query(
      'ProfileColors',
      columns: const ['color_id'],
      where: 'profile_id = ?',
      whereArgs: [profileId],
    );
    return rows
        .map((row) => (row['color_id'] as num?)?.toInt())
        .whereType<int>()
        .toSet();
  }

  //////////////////////////////////// Accessories //////////////////////////////////////
  Future<List<Map<String, dynamic>>> readAccessories() async {
    Database? myDb = await db;
    try {
      await myDb!.execute(
        "ALTER TABLE Accessories ADD COLUMN is_active INTEGER NOT NULL DEFAULT 1;",
      );
    } catch (_) {}
    try {
      await myDb!.execute(
        "UPDATE Accessories SET is_active = 1 WHERE is_active IS NULL;",
      );
    } catch (_) {}
    try {
      return await myDb!.query(
        'Accessories',
        where: 'is_active = 1 OR is_active IS NULL',
      );
    } catch (_) {
      try {
        return await myDb!.query('Accessories');
      } catch (e) {
        return [];
      }
    }
  }

  Future<int> insertAccessory(Map<String, dynamic> data) async {
    Database? myDb = await db;
    if (!data.containsKey('screw_count')) data['screw_count'] = 0;
    var res = await myDb!.insert('Accessories', data);
    CloudSyncService().notifyCatalogChange();
    return res;
  }

  Future<int> updateAccessory(int id, Map<String, dynamic> data) async {
    Database? myDb = await db;
    var res = await myDb!.update(
      'Accessories',
      data,
      where: 'id = ?',
      whereArgs: [id],
    );
    CloudSyncService().notifyCatalogChange();
    return res;
  }

  Future<int> deleteAccessory(int id) async {
    Database? myDb = await db;
    var res = await myDb!.update(
      'Accessories',
      {'is_active': 0},
      where: 'id = ?',
      whereArgs: [id],
    );
    CloudSyncService().notifyCatalogChange();
    return res;
  }

  //////////////////////////////////// Joints //////////////////////////////////////
  Future<List<Map<String, dynamic>>> readJoints() async {
    Database? myDb = await db;
    return await myDb!.query('Joints');
  }

  Future<int> insertJoint(
    String name,
    double thickness,
    double pricePerMeter,
  ) async {
    Database? myDb = await db;
    var res = await myDb!.insert('Joints', {
      'name': name,
      'thickness': thickness,
      'price_per_meter': pricePerMeter,
    });
    CloudSyncService().notifyChange();
    return res;
  }

  Future<int> updateJoint(
    int id,
    String name,
    double thickness,
    double pricePerMeter,
  ) async {
    Database? myDb = await db;
    var res = await myDb!.update(
      'Joints',
      {'name': name, 'thickness': thickness, 'price_per_meter': pricePerMeter},
      where: 'id = ?',
      whereArgs: [id],
    );
    CloudSyncService().notifyChange();
    return res;
  }

  Future<int> deleteJoint(int id) async {
    Database? myDb = await db;
    var res = await myDb!.delete('Joints', where: 'id = ?', whereArgs: [id]);
    CloudSyncService().notifyChange();
    return res;
  }

  //////////////////////////////////// Glass //////////////////////////////////////
  Future<List<Map<String, dynamic>>> readGlass() async {
    Database? myDb = await db;
    await _ensureDecorPanelDesignSchema(myDb!);
    return await myDb.query(
      'Glass',
      where: 'is_active = 1 OR is_active IS NULL',
    );
  }

  Future<int> insertGlass(
    String name,
    String type,
    double thickness,
    double pricePerSqm, {
    String color = '',
    String imagePath = '',
    String subtype = '',
    double height = 0.0,
    double? visibleWidth,
    String decorDesignCode = '',
  }) async {
    Database? myDb = await db;
    await _ensureDecorPanelDesignSchema(myDb!);
    var res = await myDb.insert('Glass', {
      'name': name,
      'type': type,
      'thickness': thickness,
      'price_per_sqm': pricePerSqm,
      'color': color,
      'image_path': imagePath,
      'subtype': subtype,
      'height': height,
      if (visibleWidth != null) 'visible_width': visibleWidth,
      'decor_design_code': decorDesignCode.trim(),
    });
    CloudSyncService().notifyChange();
    return res;
  }

  Future<int> updateGlass(
    int id,
    String name,
    String type,
    double thickness,
    double pricePerSqm, {
    String color = '',
    String imagePath = '',
    String subtype = '',
    double height = 0.0,
    double? visibleWidth,
    String? decorDesignCode,
  }) async {
    Database? myDb = await db;
    await _ensureDecorPanelDesignSchema(myDb!);
    var res = await myDb.update(
      'Glass',
      {
        'name': name,
        'type': type,
        'thickness': thickness,
        'price_per_sqm': pricePerSqm,
        'color': color,
        'image_path': imagePath,
        'subtype': subtype,
        'height': height,
        if (visibleWidth != null) 'visible_width': visibleWidth,
        if (decorDesignCode != null)
          'decor_design_code': decorDesignCode.trim(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    CloudSyncService().notifyChange();
    return res;
  }

  Future<int> deleteGlass(int id) async {
    Database? myDb = await db;
    var res = await myDb!.update(
      'Glass',
      {'is_active': 0},
      where: 'id = ?',
      whereArgs: [id],
    );
    CloudSyncService().notifyChange();

    // ??? tombstone ????? ??? ??? ?????? ???
    try {
      final prefs = await SharedPreferences.getInstance();
      final workshopId = prefs.getString('workshop_code');
      if (workshopId != null && workshopId.isNotEmpty) {
        await FirebaseFirestore.instance
            .collection('workshops')
            .doc(workshopId)
            .collection('deleted_glass_ids')
            .doc('$id')
            .set({'id': id, 'deleted_at': FieldValue.serverTimestamp()});
      }
    } catch (e) {
      debugPrint('Failed to write glass tombstone: $e');
    }

    return res;
  }

  Future<void> setGlassColorPrice(
    int glassId,
    String colorName,
    double price,
  ) async {
    Database? myDb = await db;
    await myDb!.insert('GlassColorPrices', {
      'glass_id': glassId,
      'color_name': colorName,
      'price': price,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    CloudSyncService().notifyChange();
  }

  //////////////////////////////////// ShutterComponents //////////////////////////////////////
  Future<List<Map<String, dynamic>>> readShutterComponents({
    bool includeInactive = false,
  }) async {
    Database? myDb = await db;
    try {
      await myDb!.execute(
        "ALTER TABLE ShutterComponents ADD COLUMN is_active INTEGER NOT NULL DEFAULT 1;",
      );
    } catch (_) {}
    try {
      await myDb!.execute(
        "ALTER TABLE ShutterComponents ADD COLUMN component_type TEXT NOT NULL DEFAULT 'Lame';",
      );
    } catch (_) {}
    try {
      await myDb!.execute(
        "ALTER TABLE ShutterComponents ADD COLUMN unit TEXT NOT NULL DEFAULT 'sqm';",
      );
    } catch (_) {}
    try {
      await myDb!.execute(
        "ALTER TABLE ShutterComponents ADD COLUMN shutter_subtype TEXT NOT NULL DEFAULT 'normal';",
      );
    } catch (_) {}
    try {
      await myDb!.execute(
        "ALTER TABLE ShutterComponents ADD COLUMN bar_length_m REAL NOT NULL DEFAULT 0.0;",
      );
    } catch (_) {}
    try {
      await myDb!.execute(
        "ALTER TABLE ShutterComponents ADD COLUMN motor_diameter TEXT DEFAULT '';",
      );
    } catch (_) {}
    try {
      await myDb!.execute(
        'ALTER TABLE ShutterComponents ADD COLUMN motor_has_emergency_crank INTEGER NOT NULL DEFAULT 0;',
      );
    } catch (_) {}
    try {
      await myDb!.execute(
        "ALTER TABLE ShutterComponents ADD COLUMN track_measurement TEXT DEFAULT '';",
      );
    } catch (_) {}
    try {
      await myDb!.execute(
        "UPDATE ShutterComponents SET is_active = 1 WHERE is_active IS NULL;",
      );
    } catch (_) {}
    try {
      if (includeInactive) {
        return await myDb!.query('ShutterComponents');
      }
      return await myDb!.query(
        'ShutterComponents',
        where: 'is_active = 1 OR is_active IS NULL',
      );
    } catch (_) {
      try {
        return await myDb!.query('ShutterComponents');
      } catch (e) {
        return [];
      }
    }
  }

  Future<int> insertShutterComponent(
    String name,
    String componentType,
    double price,
    String unit, {
    double? barLengthM,
    String? measurement,
    String? trackMeasurement,
    String? shutterSubtype,
    String? motorDiameter,
    bool motorHasEmergencyCrank = false,
    double capThickness = 0.0,
  }) async {
    Database? myDb = await db;
    final String? cleanMeasurement =
        (measurement == null ||
            measurement.trim().isEmpty ||
            measurement.trim().toLowerCase() == 'null')
        ? null
        : measurement.trim();
    final String? cleanMotorDiameter =
        (motorDiameter == null ||
            motorDiameter.trim().isEmpty ||
            motorDiameter.trim().toLowerCase() == 'null')
        ? null
        : motorDiameter.trim();
    final String? cleanTrackMeasurement =
        (trackMeasurement == null ||
            trackMeasurement.trim().isEmpty ||
            trackMeasurement.trim().toLowerCase() == 'null')
        ? null
        : trackMeasurement.trim();
    var res = await myDb!.insert('ShutterComponents', {
      'name': name,
      'component_type': componentType,
      'price': price,
      'unit': unit,
      'bar_length_m': barLengthM,
      'measurement': cleanMeasurement,
      'track_measurement': cleanTrackMeasurement,
      'shutter_subtype': shutterSubtype ?? 'normal',
      'motor_diameter': cleanMotorDiameter,
      'motor_has_emergency_crank': motorHasEmergencyCrank ? 1 : 0,
      'cap_thickness': capThickness,
    });
    // A new shutter component starts with its price in the mandatory grey
    // colour row, never in a separate editable default-price field.
    final greyColorId = await _ensureShutterDefaultPriceColor(myDb);
    await setShutterColorForComponent(
      shutterComponentId: res,
      colorId: greyColorId,
      enabled: true,
      price: price,
    );
    CloudSyncService().notifyCatalogChange();
    return res;
  }

  Future<int> updateShutterComponent(
    int id,
    String name,
    String componentType,
    double price,
    String unit, {
    double? barLengthM,
    String? measurement,
    String? trackMeasurement,
    String? shutterSubtype,
    String? motorDiameter,
    bool motorHasEmergencyCrank = false,
    double capThickness = 0.0,
  }) async {
    Database? myDb = await db;
    final String? cleanMeasurement =
        (measurement == null ||
            measurement.trim().isEmpty ||
            measurement.trim().toLowerCase() == 'null')
        ? null
        : measurement.trim();
    final String? cleanMotorDiameter =
        (motorDiameter == null ||
            motorDiameter.trim().isEmpty ||
            motorDiameter.trim().toLowerCase() == 'null')
        ? null
        : motorDiameter.trim();
    final String? cleanTrackMeasurement =
        (trackMeasurement == null ||
            trackMeasurement.trim().isEmpty ||
            trackMeasurement.trim().toLowerCase() == 'null')
        ? null
        : trackMeasurement.trim();
    var res = await myDb!.update(
      'ShutterComponents',
      {
        'name': name,
        'component_type': componentType,
        'price': price,
        'unit': unit,
        'bar_length_m': barLengthM,
        'measurement': cleanMeasurement,
        'track_measurement': cleanTrackMeasurement,
        'shutter_subtype': shutterSubtype ?? 'normal',
        'motor_diameter': cleanMotorDiameter,
        'motor_has_emergency_crank': motorHasEmergencyCrank ? 1 : 0,
        'cap_thickness': capThickness,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    if (res > 0) {
      // Product-edit forms still pass a price for backwards compatibility;
      // write it to the grey base-colour row as the authoritative value.
      final greyColorId = await _ensureShutterDefaultPriceColor(myDb);
      await setShutterColorForComponent(
        shutterComponentId: id,
        colorId: greyColorId,
        enabled: true,
        price: price,
      );
    }
    CloudSyncService().notifyCatalogChange();
    return res;
  }

  /// Legacy entry point kept for callers that have not yet moved to colour
  /// pricing. The value is stored in the mandatory grey colour row.
  Future<int> updateShutterComponentPrice(int id, double price) async {
    final myDb = await db;
    if (myDb == null) {
      throw StateError('Shutter component database is not available.');
    }
    if (!price.isFinite) {
      throw ArgumentError.value(
        price,
        'price',
        'Price must be a finite number',
      );
    }

    final component = await myDb.query(
      'ShutterComponents',
      columns: const ['id'],
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (component.isEmpty) {
      return 0;
    }
    final greyColorId = await _ensureShutterDefaultPriceColor(myDb);
    await setShutterColorForComponent(
      shutterComponentId: id,
      colorId: greyColorId,
      enabled: true,
      price: price,
    );
    return 1;
  }

  Future<int> deleteShutterComponent(int id) async {
    Database? myDb = await db;
    var res = await myDb!.update(
      'ShutterComponents',
      {'is_active': 0},
      where: 'id = ?',
      whereArgs: [id],
    );
    CloudSyncService().notifyCatalogChange();
    return res;
  }

  Future<int> deleteShutterComponentPermanently(int id) async {
    Database? myDb = await db;
    var res = await myDb!.delete(
      'ShutterComponents',
      where: 'id = ?',
      whereArgs: [id],
    );
    CloudSyncService().notifyCatalogChange();
    return res;
  }

  Future<int> restoreShutterComponent(int id) async {
    Database? myDb = await db;
    var res = await myDb!.update(
      'ShutterComponents',
      {'is_active': 1},
      where: 'id = ?',
      whereArgs: [id],
    );
    CloudSyncService().notifyCatalogChange();
    return res;
  }

  Future<double> getShutterSqmPrice(String bladeType, int colorId) async {
    Database? myDb = await db;
    if (myDb == null) return 0.0;
    try {
      final res = await myDb.query(
        'ShutterSqmPrices',
        columns: ['price_per_sqm'],
        where: 'blade_type = ? AND color_id = ?',
        whereArgs: [bladeType, colorId],
        limit: 1,
      );
      if (res.isNotEmpty) {
        return (res.first['price_per_sqm'] as num).toDouble();
      }
    } catch (_) {}
    return 0.0;
  }

  Future<int> insertOrUpdateShutterSqmPrice(
    String bladeType,
    int colorId,
    double price,
  ) async {
    Database? myDb = await db;
    if (myDb == null) return 0;
    var res = await myDb.insert('ShutterSqmPrices', {
      'blade_type': bladeType,
      'color_id': colorId,
      'price_per_sqm': price,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    CloudSyncService().notifyCatalogChange();
    return res;
  }

  Future<int> deleteShutterSqmPrice(String bladeType, int colorId) async {
    Database? myDb = await db;
    if (myDb == null) return 0;
    final res = await myDb.delete(
      'ShutterSqmPrices',
      where: 'blade_type = ? AND color_id = ?',
      whereArgs: [bladeType, colorId],
    );
    CloudSyncService().notifyCatalogChange();
    return res;
  }

  //////////////////////////////////// Employees //////////////////////////////////////
  Future<List<Map<String, dynamic>>> readEmployees() async {
    Database? myDb = await db;
    return await myDb!.query('Employees');
  }

  Future<int> insertEmployee(
    String uid,
    String email,
    String name,
    String permissionsJson, {
    String? salaryType,
    double? baseSalary,
    String? phone,
    String? address,
    String? jobRole,
  }) async {
    Database? myDb = await db;
    var res = await myDb!.insert(
      'Employees',
      _withDistributedId({
        'uid': uid,
        'email': email,
        'name': name,
        'permissions_json': permissionsJson,
        'salary_type': salaryType,
        'base_salary': baseSalary,
        'phone': phone,
        'address': address,
        'job_role': jobRole,
      }),
    );
    CloudSyncService().notifyChange();
    return res;
  }

  Future<int> updateEmployeePermissions(
    String uid,
    String permissionsJson,
  ) async {
    Database? myDb = await db;
    var res = await myDb!.update(
      'Employees',
      {'permissions_json': permissionsJson},
      where: 'uid = ?',
      whereArgs: [uid],
    );
    CloudSyncService().notifyChange();
    return res;
  }

  Future<int> updateEmployeeInfo(
    String uid, {
    required String name,
    required String phone,
    String? address,
    String? jobRole,
  }) async {
    Database? myDb = await db;
    final res = await myDb!.update(
      'Employees',
      {
        'name': name,
        'phone': phone,
        if (address != null) 'address': address,
        if (jobRole != null) 'job_role': jobRole,
      },
      where: 'uid = ?',
      whereArgs: [uid],
    );
    CloudSyncService().notifyChange();
    return res;
  }

  Future<void> linkLocalWorker(
    String localUid,
    String newUid,
    String email,
  ) async {
    Database? myDb = await db;
    if (myDb == null) return;
    await myDb.transaction((txn) async {
      await txn.update(
        'Employees',
        {'uid': newUid, 'email': email},
        where: 'uid = ?',
        whereArgs: [localUid],
      );
      await txn.update(
        'WorkerAllocations',
        {'worker_uid': newUid},
        where: 'worker_uid = ?',
        whereArgs: [localUid],
      );
      await txn.update(
        'WorkerAllocations',
        {'installation_worker_uid': newUid},
        where: 'installation_worker_uid = ?',
        whereArgs: [localUid],
      );
      await txn.update(
        'WorkerTransactions',
        {'worker_uid': newUid},
        where: 'worker_uid = ?',
        whereArgs: [localUid],
      );
      await txn.update(
        'Commandes_details',
        {'assigned_worker_uid': newUid},
        where: 'assigned_worker_uid = ?',
        whereArgs: [localUid],
      );
    });
    CloudSyncService().notifyChange();
  }

  Future<int> updateEmployeeFullInfo(
    String uid, {
    required String name,
    required String phone,
    String? email,
    String? address,
    String? jobRole,
    String? salaryType,
    double? baseSalary,
  }) async {
    Database? myDb = await db;
    final res = await myDb!.update(
      'Employees',
      {
        'name': name,
        'phone': phone,
        if (email != null) 'email': email,
        if (address != null) 'address': address,
        if (jobRole != null) 'job_role': jobRole,
        if (salaryType != null) 'salary_type': salaryType,
        if (baseSalary != null) 'base_salary': baseSalary,
      },
      where: 'uid = ?',
      whereArgs: [uid],
    );
    CloudSyncService().notifyChange();
    return res;
  }

  Future<int> deleteEmployee(String uid) async {
    Database? myDb = await db;
    var res = await myDb!.delete(
      'Employees',
      where: 'uid = ?',
      whereArgs: [uid],
    );
    CloudSyncService().notifyChange();
    return res;
  }

  //////////////////////////////////// Treasury //////////////////////////////////////
  Future<List<Map<String, dynamic>>> readTreasury() async {
    Database? myDb = await db;
    return await myDb!.query('Treasury', orderBy: 'created_at DESC');
  }

  /// Exact links between a treasury transaction and the orders or purchase
  /// invoices it settles. This makes Treasury the financial source of truth.
  Future<void> _ensurePaymentAllocationSchema(DatabaseExecutor executor) async {
    await executor.execute('''
      CREATE TABLE IF NOT EXISTS PaymentAllocations (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        treasury_id INTEGER NOT NULL,
        document_type TEXT NOT NULL,
        document_id INTEGER NOT NULL,
        amount REAL NOT NULL DEFAULT 0.0,
        created_at TEXT NOT NULL DEFAULT (datetime('now')),
        UNIQUE(treasury_id, document_type, document_id)
      )
    ''');
    await executor.execute('''
      CREATE INDEX IF NOT EXISTS idx_payment_allocations_treasury
      ON PaymentAllocations(treasury_id)
    ''');
    await executor.execute('''
      CREATE INDEX IF NOT EXISTS idx_payment_allocations_document
      ON PaymentAllocations(document_type, document_id)
    ''');
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

  Future<void> _insertPaymentAllocation(
    DatabaseExecutor executor, {
    required int treasuryId,
    required String documentType,
    required int documentId,
    required double amount,
  }) async {
    if (amount <= _paymentTolerance) return;
    await executor.insert(
      'PaymentAllocations',
      _withDistributedId({
        'treasury_id': treasuryId,
        'document_type': documentType,
        'document_id': documentId,
        'amount': amount,
        'created_at': DateTime.now().toIso8601String(),
      }),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> allocateClientPayment(int clientId, double amount) async {
    // Kept for old callers. Amount is already recorded in Treasury; rebuild
    // the document ledger from that canonical source instead of mutating an
    // arbitrary open order.
    await reconcileClientPayments(clientId);
  }

  Future<void> allocateSupplierPayment(int supplierId, double amount) async {
    await reconcileSupplierPayments(supplierId);
  }

  Future<void> deallocateClientPayment(int clientId, double amount) async {
    await reconcileClientPayments(clientId);
  }

  Future<void> deallocateSupplierPayment(int supplierId, double amount) async {
    await reconcileSupplierPayments(supplierId);
  }

  Future<void> _rebuildClientPaymentLedger(
    DatabaseExecutor executor,
    int clientId,
  ) async {
    await _ensurePaymentAllocationSchema(executor);
    final orders = await executor.query(
      'Commandes',
      where: 'client_id = ?',
      whereArgs: [clientId],
      orderBy: 'created_at ASC, id ASC',
    );
    final allTransactions = await executor.query(
      'Treasury',
      where: 'entity_type = ? AND entity_id = ?',
      whereArgs: ['Client', clientId],
      orderBy: 'created_at ASC, id ASC',
    );
    final receipts = allTransactions.where(_isClientReceipt).toList();

    // Bring forward only the part of historic advances that has no matching
    // cash receipt yet. This avoids the old duplicate-migration behaviour.
    var missingLegacy =
        orders.fold<double>(
          0.0,
          (sum, row) => sum + _paymentNumber(row['advance_payment']),
        ) -
        receipts.fold<double>(
          0.0,
          (sum, row) => sum + _paymentNumber(row['amount']),
        );
    if (missingLegacy > _paymentTolerance) {
      for (final order in orders) {
        if (missingLegacy <= _paymentTolerance) break;
        final orderId = _paymentRecordId(order['id']);
        final recordedAdvance = _paymentNumber(order['advance_payment']);
        if (orderId == null || recordedAdvance <= _paymentTolerance) continue;
        final amount = recordedAdvance < missingLegacy
            ? recordedAdvance
            : missingLegacy;
        final legacyId = _nextDistributedId();
        final createdAt = order['created_at']?.toString();
        await executor.insert(
          'Treasury',
          _withDistributedId({
            'id': legacyId,
            'transaction_type': 'Encaissement',
            'amount': amount,
            'description': 'ترحيل دفعة قديمة للطلبية #$orderId',
            'reference_id': orderId,
            'recorded_by': 'migration',
            'entity_type': 'Client',
            'entity_id': clientId,
            'old_balance': 0.0,
            'new_balance': 0.0,
            'caisse_name': 'الصندوق الرئيسي',
            'payment_method': 'نقداً / Espèce',
            'created_at': (createdAt == null || createdAt.trim().isEmpty)
                ? DateTime.now().toIso8601String()
                : createdAt,
          }),
        );
        receipts.add({
          'id': legacyId,
          'reference_id': orderId,
          'amount': amount,
          'created_at': createdAt ?? DateTime.now().toIso8601String(),
        });
        missingLegacy -= amount;
      }
    }

    receipts.sort((a, b) {
      final byDate = (a['created_at']?.toString() ?? '').compareTo(
        b['created_at']?.toString() ?? '',
      );
      return byDate != 0
          ? byDate
          : (_paymentRecordId(a['id']) ?? 0).compareTo(
              _paymentRecordId(b['id']) ?? 0,
            );
    });
    final receiptIds = receipts
        .map((row) => _paymentRecordId(row['id']))
        .whereType<int>()
        .toList();
    if (receiptIds.isNotEmpty) {
      final placeholders = List.filled(receiptIds.length, '?').join(',');
      await executor.rawDelete(
        'DELETE FROM PaymentAllocations WHERE treasury_id IN ($placeholders)',
        receiptIds,
      );
    }

    final settledByOrder = <int, double>{};
    double orderTotal(Map<String, dynamic> order) {
      final net = _paymentNumber(order['net_payable']);
      return net > 0 ? net : _paymentNumber(order['total']);
    }

    for (final receipt in receipts) {
      final treasuryId = _paymentRecordId(receipt['id']);
      if (treasuryId == null) continue;
      var amountLeft = _paymentNumber(receipt['amount']);
      final preferredId = _paymentRecordId(receipt['reference_id']);
      final referencedOrders = orders
          .where((row) => _paymentRecordId(row['id']) == preferredId)
          .toList();
      // An invoice-specific receipt must not silently settle a different
      // order. Any excess remains a visible customer credit in Treasury.
      final candidates = preferredId != null && referencedOrders.isNotEmpty
          ? referencedOrders
          : orders;
      for (final order in candidates) {
        if (amountLeft <= _paymentTolerance) break;
        final orderId = _paymentRecordId(order['id']);
        if (orderId == null) continue;
        final due = orderTotal(order) - (settledByOrder[orderId] ?? 0.0);
        if (due <= _paymentTolerance) continue;
        final allocated = amountLeft < due ? amountLeft : due;
        await _insertPaymentAllocation(
          executor,
          treasuryId: treasuryId,
          documentType: 'Commande',
          documentId: orderId,
          amount: allocated,
        );
        settledByOrder[orderId] = (settledByOrder[orderId] ?? 0.0) + allocated;
        amountLeft -= allocated;
      }
    }

    for (final order in orders) {
      final orderId = _paymentRecordId(order['id']);
      if (orderId == null) continue;
      final total = orderTotal(order);
      final paid = (settledByOrder[orderId] ?? 0.0)
          .clamp(0.0, total)
          .toDouble();
      final paymentStatus =
          total > _paymentTolerance && paid >= total - _paymentTolerance
          ? 'Paid'
          : paid > _paymentTolerance
          ? 'Partial'
          : 'Unpaid';
      if ((_paymentNumber(order['advance_payment']) - paid).abs() <=
              _paymentTolerance &&
          order['payment_status']?.toString() == paymentStatus) {
        continue;
      }
      await executor.update(
        'Commandes',
        {
          'advance_payment': paid,
          'payment_status': paymentStatus,
          'updated_at': DateTime.now().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [orderId],
      );
    }
  }

  Future<void> reconcileClientPayments(int clientId) async {
    final myDb = await db;
    if (myDb == null) return;
    await myDb.transaction(
      (transaction) => _rebuildClientPaymentLedger(transaction, clientId),
    );
    CloudSyncService().notifyChangeImmediate();
  }

  Future<void> _rebuildSupplierPaymentLedger(
    DatabaseExecutor executor,
    int supplierId,
  ) async {
    await _ensurePaymentAllocationSchema(executor);
    final purchases = await executor.query(
      'Achats',
      where: 'supplier_id = ?',
      whereArgs: [supplierId],
      orderBy: 'created_at ASC, id ASC',
    );
    final allTransactions = await executor.query(
      'Treasury',
      where: 'entity_type = ? AND entity_id = ?',
      whereArgs: ['Supplier', supplierId],
      orderBy: 'created_at ASC, id ASC',
    );
    final payments = allTransactions.where(_isSupplierPayment).toList();

    var missingLegacy =
        purchases.fold<double>(
          0.0,
          (sum, row) => sum + _paymentNumber(row['paid_amount']),
        ) -
        payments.fold<double>(
          0.0,
          (sum, row) => sum + _paymentNumber(row['amount']),
        );
    if (missingLegacy > _paymentTolerance) {
      for (final purchase in purchases) {
        if (missingLegacy <= _paymentTolerance) break;
        final purchaseId = _paymentRecordId(purchase['id']);
        final recordedPaid = _paymentNumber(purchase['paid_amount']);
        if (purchaseId == null || recordedPaid <= _paymentTolerance) continue;
        final amount = recordedPaid < missingLegacy
            ? recordedPaid
            : missingLegacy;
        final legacyId = _nextDistributedId();
        final createdAt = purchase['created_at']?.toString();
        await executor.insert(
          'Treasury',
          _withDistributedId({
            'id': legacyId,
            'transaction_type': 'Décaissement',
            'amount': amount,
            'description': 'ترحيل دفع قديم لفاتورة الشراء #$purchaseId',
            'reference_id': purchaseId,
            'recorded_by': 'migration',
            'entity_type': 'Supplier',
            'entity_id': supplierId,
            'old_balance': 0.0,
            'new_balance': 0.0,
            'caisse_name': 'الصندوق الرئيسي',
            'payment_method': 'نقداً / Espèce',
            'created_at': (createdAt == null || createdAt.trim().isEmpty)
                ? DateTime.now().toIso8601String()
                : createdAt,
          }),
        );
        payments.add({
          'id': legacyId,
          'reference_id': purchaseId,
          'amount': amount,
          'created_at': createdAt ?? DateTime.now().toIso8601String(),
        });
        missingLegacy -= amount;
      }
    }

    payments.sort((a, b) {
      final byDate = (a['created_at']?.toString() ?? '').compareTo(
        b['created_at']?.toString() ?? '',
      );
      return byDate != 0
          ? byDate
          : (_paymentRecordId(a['id']) ?? 0).compareTo(
              _paymentRecordId(b['id']) ?? 0,
            );
    });
    final paymentIds = payments
        .map((row) => _paymentRecordId(row['id']))
        .whereType<int>()
        .toList();
    if (paymentIds.isNotEmpty) {
      final placeholders = List.filled(paymentIds.length, '?').join(',');
      await executor.rawDelete(
        'DELETE FROM PaymentAllocations WHERE treasury_id IN ($placeholders)',
        paymentIds,
      );
    }

    final settledByPurchase = <int, double>{};
    for (final payment in payments) {
      final treasuryId = _paymentRecordId(payment['id']);
      if (treasuryId == null) continue;
      var amountLeft = _paymentNumber(payment['amount']);
      final preferredId = _paymentRecordId(payment['reference_id']);
      final referencedPurchases = purchases
          .where((row) => _paymentRecordId(row['id']) == preferredId)
          .toList();
      final candidates = preferredId != null && referencedPurchases.isNotEmpty
          ? referencedPurchases
          : purchases;
      for (final purchase in candidates) {
        if (amountLeft <= _paymentTolerance) break;
        final purchaseId = _paymentRecordId(purchase['id']);
        if (purchaseId == null) continue;
        final total = _paymentNumber(purchase['total']);
        final due = total - (settledByPurchase[purchaseId] ?? 0.0);
        if (due <= _paymentTolerance) continue;
        final allocated = amountLeft < due ? amountLeft : due;
        await _insertPaymentAllocation(
          executor,
          treasuryId: treasuryId,
          documentType: 'Achat',
          documentId: purchaseId,
          amount: allocated,
        );
        settledByPurchase[purchaseId] =
            (settledByPurchase[purchaseId] ?? 0.0) + allocated;
        amountLeft -= allocated;
      }
    }

    // Do not infer a purchase workflow status from payment; a confirmed
    // purchase may legitimately be only partially paid. Only its financial
    // figures are derived from Treasury here.
    for (final purchase in purchases) {
      final purchaseId = _paymentRecordId(purchase['id']);
      if (purchaseId == null) continue;
      final total = _paymentNumber(purchase['total']);
      final paid = (settledByPurchase[purchaseId] ?? 0.0)
          .clamp(0.0, total)
          .toDouble();
      final remaining = (total - paid).clamp(0.0, double.infinity).toDouble();
      if ((_paymentNumber(purchase['paid_amount']) - paid).abs() <=
              _paymentTolerance &&
          (_paymentNumber(purchase['remaining_amount']) - remaining).abs() <=
              _paymentTolerance) {
        continue;
      }
      await executor.update(
        'Achats',
        {
          'paid_amount': paid,
          'remaining_amount': remaining,
          'updated_at': DateTime.now().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [purchaseId],
      );
    }
  }

  Future<void> reconcileSupplierPayments(int supplierId) async {
    final myDb = await db;
    if (myDb == null) return;
    await myDb.transaction(
      (transaction) => _rebuildSupplierPaymentLedger(transaction, supplierId),
    );
    CloudSyncService().notifyChangeImmediate();
  }

  Future<void> deallocateWorkerPayment(
    int workerId,
    double amount,
    String createdAt,
  ) async {
    Database? myDb = await db;
    if (myDb == null) return;

    final workerRows = await myDb.query(
      'Employees',
      where: 'id = ?',
      whereArgs: [workerId],
    );
    if (workerRows.isEmpty) return;

    final emp = workerRows.first;
    final workerUid = (emp['uid']?.toString() ?? '').isNotEmpty
        ? emp['uid'].toString()
        : (emp['id']?.toString() ?? workerId.toString());
    final email = emp['email']?.toString() ?? '';

    List<String> allKeys = [];
    if (workerUid.isNotEmpty) allKeys.add(workerUid);
    if (workerId > 0 && !allKeys.contains(workerId.toString()))
      allKeys.add(workerId.toString());
    if (email.isNotEmpty && !allKeys.contains(email)) allKeys.add(email);

    final placeholders = List.filled(allKeys.length, '?').join(',');

    // 1. Unsettle all allocations for this worker (is_settled = 0, settled_at = null)
    await myDb.rawUpdate(
      "UPDATE WorkerAllocations SET is_settled = 0, settled_at = NULL WHERE worker_uid IN ($placeholders)",
      allKeys,
    );

    // 2. Unsettle all transactions for this worker (is_settled = 0, settled_at = null)
    await myDb.rawUpdate(
      "UPDATE WorkerTransactions SET is_settled = 0, settled_at = NULL WHERE worker_uid IN ($placeholders)",
      allKeys,
    );

    // 3. Delete salary payout transactions and carryover transactions created around settlement or with matching createdAt
    if (createdAt.isNotEmpty) {
      await myDb.rawDelete(
        "DELETE FROM WorkerTransactions WHERE worker_uid IN ($placeholders) AND (created_at = ? OR amount = ? OR transaction_type = 'salary' OR note LIKE '%ØªØ³ÙˆÙŠØ©%')",
        [...allKeys, createdAt, amount],
      );
    } else {
      await myDb.rawDelete(
        "DELETE FROM WorkerTransactions WHERE worker_uid IN ($placeholders) AND (transaction_type = 'salary' OR note LIKE '%ØªØ³ÙˆÙŠØ©%')",
        allKeys,
      );
    }

    CloudSyncService().notifyChangeImmediate();
  }

  Future<int> insertTreasury(
    String transactionType,
    double amount,
    String description, {
    int? referenceId,
    String? recordedBy,
    String? entityType,
    int? entityId,
    String? phone,
    double? oldBalance,
    double? newBalance,
    String? caisseName,
    String? paymentMethod,
    String? createdAt,
  }) async {
    Database? myDb = await db;
    if (myDb == null) return 0;
    final transactionAt = createdAt ?? DateTime.now().toIso8601String();
    final treasuryData = _withDistributedId({
      'transaction_type': transactionType,
      'amount': amount,
      'description': description,
      'reference_id': referenceId,
      'recorded_by': recordedBy ?? 'system',
      'entity_type': entityType,
      'entity_id': entityId,
      'phone': phone,
      'old_balance': oldBalance ?? 0.0,
      'new_balance': newBalance ?? 0.0,
      'caisse_name': caisseName ?? 'الصندوق الرئيسي',
      'payment_method': paymentMethod ?? 'نقداً / Espèce',
      'created_at': transactionAt,
    });
    final res = await myDb.transaction((txn) async {
      await _ensurePaymentAllocationSchema(txn);
      final id = await txn.insert('Treasury', treasuryData);
      if (_isClientReceipt(treasuryData) && entityId != null) {
        await _rebuildClientPaymentLedger(txn, entityId);
      } else if (_isSupplierPayment(treasuryData) && entityId != null) {
        await _rebuildSupplierPaymentLedger(txn, entityId);
      }
      return id;
    });

    if (entityType == 'Worker' &&
        _normalisedTreasuryType(transactionType) == 'decaissement' &&
        entityId != null &&
        referenceId == null) {
      final workerRows = await myDb.query(
        'Employees',
        where: 'id = ?',
        whereArgs: [entityId],
      );
      if (workerRows.isNotEmpty) {
        final workerUid = (workerRows.first['uid']?.toString() ?? '').isNotEmpty
            ? workerRows.first['uid'].toString()
            : (workerRows.first['id']?.toString() ?? entityId.toString());

        final txTime = transactionAt;
        final existingTxs = await myDb.query(
          'WorkerTransactions',
          where: 'created_at = ? AND amount = ?',
          whereArgs: [txTime, amount],
        );
        if (existingTxs.isEmpty) {
          await myDb.insert(
            'WorkerTransactions',
            _withDistributedId({
              'worker_uid': workerUid,
              'amount': amount,
              'transaction_type': 'advance',
              'note': description,
              'created_at': txTime,
              'is_settled': 0,
            }),
          );
        }
      }
    }

    CloudSyncService().notifyChangeImmediate();
    return res;
  }

  Future<int> deleteTreasury(int id) async {
    Database? myDb = await db;
    if (myDb == null) return 0;

    final List<Map<String, dynamic>> records = await myDb.query(
      'Treasury',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (records.isEmpty) return 0;
    final row = records.first;
    final amount = (row['amount'] as num?)?.toDouble() ?? 0.0;
    final entityId = _paymentRecordId(row['entity_id']);
    final isClientReceipt = _isClientReceipt(row);
    final isSupplierPayment = _isSupplierPayment(row);

    final res = await myDb.transaction((txn) async {
      await _ensurePaymentAllocationSchema(txn);
      final deleted = await txn.delete(
        'Treasury',
        where: 'id = ?',
        whereArgs: [id],
      );
      await txn.delete(
        'PaymentAllocations',
        where: 'treasury_id = ?',
        whereArgs: [id],
      );
      if (deleted > 0 && isClientReceipt && entityId != null) {
        await _rebuildClientPaymentLedger(txn, entityId);
      } else if (deleted > 0 && isSupplierPayment && entityId != null) {
        await _rebuildSupplierPaymentLedger(txn, entityId);
      }
      return deleted;
    });

    if (res > 0) {
      if (row['entity_type']?.toString() == 'Worker' && entityId != null) {
        await deallocateWorkerPayment(
          entityId,
          amount,
          row['created_at']?.toString() ?? '',
        );
      }
      CloudSyncService().notifyChangeImmediate();
    }
    return res;
  }

  Future<int> updateTreasury(
    int id, {
    required double newAmount,
    required String newDescription,
    required String newCaisse,
    required String newPaymentMethod,
    required String newCreatedAt,
  }) async {
    Database? myDb = await db;
    if (myDb == null) return 0;

    final List<Map<String, dynamic>> records = await myDb.query(
      'Treasury',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (records.isEmpty) return 0;
    final row = records.first;
    final entityId = _paymentRecordId(row['entity_id']);
    final isClientReceipt = _isClientReceipt(row);
    final isSupplierPayment = _isSupplierPayment(row);

    final res = await myDb.transaction((txn) async {
      await _ensurePaymentAllocationSchema(txn);
      final updated = await txn.update(
        'Treasury',
        {
          'amount': newAmount,
          'description': newDescription,
          'caisse_name': newCaisse,
          'payment_method': newPaymentMethod,
          'created_at': newCreatedAt,
        },
        where: 'id = ?',
        whereArgs: [id],
      );
      if (updated > 0 && isClientReceipt && entityId != null) {
        await _rebuildClientPaymentLedger(txn, entityId);
      } else if (updated > 0 && isSupplierPayment && entityId != null) {
        await _rebuildSupplierPaymentLedger(txn, entityId);
      }
      return updated;
    });

    if (res > 0) {
      CloudSyncService().notifyChangeImmediate();
    }
    return res;
  }

  /// Customer balance is calculated from invoices and the treasury ledger.
  /// `advance_payment` is only a cached allocation total, so subtracting it
  /// as well as Treasury would count every receipt twice.
  Future<double> getClientBalance(int clientId) async {
    final myDb = await db;
    if (myDb == null) return 0.0;

    final commandesRes = await myDb.rawQuery(
      '''
      SELECT
        COALESCE(SUM(
          CASE WHEN net_payable > 0 THEN net_payable ELSE total END
        ), 0) as invoices
      FROM Commandes WHERE client_id = ?
      ''',
      [clientId],
    );
    final totalInvoices =
        (commandesRes.first['invoices'] as num?)?.toDouble() ?? 0.0;
    final transactions = await myDb.query(
      'Treasury',
      where: 'entity_type = ? AND entity_id = ?',
      whereArgs: ['Client', clientId],
    );
    var receipts = 0.0;
    var refunds = 0.0;
    for (final row in transactions) {
      final amount = _paymentNumber(row['amount']);
      final type = _normalisedTreasuryType(
        row['transaction_type']?.toString() ?? '',
      );
      if (type == 'encaissement') {
        receipts += amount;
      } else if (type == 'decaissement') {
        refunds += amount;
      }
    }
    // Positive = the customer still owes the workshop.
    return totalInvoices - receipts + refunds;
  }

  /// Ø­Ø³Ø§Ø¨ Ø±ØµÙŠØ¯ Ø§Ù„Ù…ÙˆØ±Ø¯ = SUM(total) - SUM(paid_amount) Ù…Ù† Achats
  Future<double> getSupplierBalance(int supplierId) async {
    final myDb = await db;
    if (myDb == null) return 0.0;

    final res = await myDb.rawQuery(
      'SELECT COALESCE(SUM(total),0) as bought, COALESCE(SUM(paid_amount),0) as paid FROM Achats WHERE supplier_id = ?',
      [supplierId],
    );
    final bought = (res.first['bought'] as num?)?.toDouble() ?? 0.0;
    final paid = (res.first['paid'] as num?)?.toDouble() ?? 0.0;
    // Ù…ÙˆØ¬Ø¨ = Ù†Ø­Ù† Ù…Ø¯ÙŠÙ†ÙˆÙ† Ù„Ù„Ù…ÙˆØ±Ø¯
    return bought - paid;
  }

  /// Ø­Ø³Ø§Ø¨ Ø±ØµÙŠØ¯ Ø§Ù„Ø¹Ø§Ù…Ù„ = Ù…Ø¬Ù…ÙˆØ¹ Ø§Ù„Ù…Ø³ØªØ­Ù‚Ø§Øª - Ù…Ø¬Ù…ÙˆØ¹ Ù…Ø§ Ø¯ÙÙØ¹ Ù„Ù‡
  Future<double> getWorkerBalance(int workerId) async {
    final myDb = await db;
    if (myDb == null) return 0.0;

    // Ù…Ø¬Ù…ÙˆØ¹ Ù…Ø§ Ø¯ÙÙØ¹ Ù„Ù„Ø¹Ø§Ù…Ù„ Ù…Ù† Ø§Ù„Ø®Ø²ÙŠÙ†Ø©
    final paidRes = await myDb.rawQuery(
      "SELECT COALESCE(SUM(amount), 0) as total FROM Treasury WHERE entity_type = 'Worker' AND entity_id = ?",
      [workerId],
    );
    final totalPaid = (paidRes.first['total'] as num?)?.toDouble() ?? 0.0;

    // Ù…Ø¬Ù…ÙˆØ¹ Ø§Ù„Ù…Ø³ØªØ­Ù‚Ø§Øª Ù…Ù† WorkerTransactions (Ø£Ø¬ÙˆØ±)
    final earnedRes = await myDb.rawQuery(
      "SELECT COALESCE(SUM(amount), 0) as total FROM WorkerTransactions WHERE worker_uid = ? AND transaction_type = 'salary'",
      [workerId.toString()],
    );
    final totalEarned = (earnedRes.first['total'] as num?)?.toDouble() ?? 0.0;

    // Ù…ÙˆØ¬Ø¨ = Ø§Ù„Ù…Ø­Ù„ Ù…Ø¯ÙŠÙ† Ù„Ù„Ø¹Ø§Ù…Ù„
    return totalEarned - totalPaid;
  }

  Future<void> clearPersonalData() async {
    Database? myDb = await db;
    if (myDb == null) return;
    await myDb.transaction((txn) async {
      await _ensureSyncTombstoneInfrastructure(txn);
      await txn.update('_sync_runtime_flags', {
        'suppress_tombstones': 1,
      }, where: 'id = 1');
      final tablesToClear = [
        'Client',
        'Commandes',
        'Commandes_details',
        'Achats',
        'Achat_items',
        'Suppliers',
        'PaymentAllocations',
        'Treasury',
        'WorkerTransactions',
        'Employees',
      ];
      for (final table in tablesToClear) {
        try {
          await txn.delete(table);
        } catch (_) {}
      }
      await txn.update('_sync_runtime_flags', {
        'suppress_tombstones': 0,
      }, where: 'id = 1');
    });
  }

  Future<void> _ensureSyncTombstoneInfrastructure(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS SyncTombstones (
        table_name TEXT NOT NULL,
        row_id TEXT NOT NULL,
        deleted_at TEXT NOT NULL,
        PRIMARY KEY (table_name, row_id)
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS _sync_runtime_flags (
        id INTEGER PRIMARY KEY,
        suppress_tombstones INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.insert('_sync_runtime_flags', {
      'id': 1,
      'suppress_tombstones': 0,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
    await db.execute('''
      CREATE TABLE IF NOT EXISTS _sync_change_log (
        table_name TEXT NOT NULL,
        row_id TEXT NOT NULL,
        operation TEXT NOT NULL,
        changed_at TEXT NOT NULL,
        revision INTEGER NOT NULL DEFAULT 1,
        PRIMARY KEY (table_name, row_id)
      )
    ''');
    await _ensureProfileColorsSyncIds(db);

    final schemaRows = await db.rawQuery('''
      SELECT name
      FROM sqlite_master
      WHERE type = 'table'
        AND name NOT LIKE 'sqlite_%'
        AND name NOT LIKE '_sync_%'
        AND name != 'SyncTombstones'
        AND name != 'android_metadata'
    ''');
    for (final schemaRow in schemaRows) {
      final table = schemaRow['name']?.toString() ?? '';
      if (!_isSafeSqlIdentifier(table)) continue;
      final columns = await _tableColumns(db, table);
      if (!columns.contains('id')) continue;
      final tombstoneTrigger = 'sync_tombstone_delete_$table';
      try {
        await db.execute('''
          CREATE TRIGGER IF NOT EXISTS "$tombstoneTrigger"
          AFTER DELETE ON "$table"
          WHEN COALESCE(
            (SELECT suppress_tombstones
             FROM _sync_runtime_flags
             WHERE id = 1),
            0
          ) = 0
          BEGIN
            INSERT OR REPLACE INTO SyncTombstones (
              table_name,
              row_id,
              deleted_at
            ) VALUES (
              '$table',
              CAST(OLD.id AS TEXT),
              strftime('%Y-%m-%dT%H:%M:%fZ', 'now')
            );
          END
        ''');
      } catch (error) {
        debugPrint('Could not track deletions for $table: $error');
      }

      final insertTrigger = 'sync_cloud_insert_$table';
      final updateTrigger = 'sync_cloud_update_$table';
      final deleteTrigger = 'sync_cloud_delete_$table';
      try {
        await db.execute('''
          CREATE TRIGGER IF NOT EXISTS "$insertTrigger"
          AFTER INSERT ON "$table"
          WHEN COALESCE(
            (SELECT suppress_tombstones
             FROM _sync_runtime_flags
             WHERE id = 1),
            0
          ) = 0
          BEGIN
            INSERT OR REPLACE INTO _sync_change_log (
              table_name,
              row_id,
              operation,
              changed_at,
              revision
            ) VALUES (
              '$table',
              CAST(NEW.id AS TEXT),
              'upsert',
              strftime('%Y-%m-%dT%H:%M:%fZ', 'now'),
              COALESCE((
                SELECT revision
                FROM _sync_change_log
                WHERE table_name = '$table'
                  AND row_id = CAST(NEW.id AS TEXT)
              ), 0) + 1
            );
          END
        ''');
        await db.execute('''
          CREATE TRIGGER IF NOT EXISTS "$updateTrigger"
          AFTER UPDATE ON "$table"
          WHEN COALESCE(
            (SELECT suppress_tombstones
             FROM _sync_runtime_flags
             WHERE id = 1),
            0
          ) = 0
          BEGIN
            INSERT OR REPLACE INTO _sync_change_log (
              table_name,
              row_id,
              operation,
              changed_at,
              revision
            ) VALUES (
              '$table',
              CAST(NEW.id AS TEXT),
              'upsert',
              strftime('%Y-%m-%dT%H:%M:%fZ', 'now'),
              COALESCE((
                SELECT revision
                FROM _sync_change_log
                WHERE table_name = '$table'
                  AND row_id = CAST(NEW.id AS TEXT)
              ), 0) + 1
            );
          END
        ''');
        await db.execute('''
          CREATE TRIGGER IF NOT EXISTS "$deleteTrigger"
          AFTER DELETE ON "$table"
          WHEN COALESCE(
            (SELECT suppress_tombstones
             FROM _sync_runtime_flags
             WHERE id = 1),
            0
          ) = 0
          BEGIN
            INSERT OR REPLACE INTO _sync_change_log (
              table_name,
              row_id,
              operation,
              changed_at,
              revision
            ) VALUES (
              '$table',
              CAST(OLD.id AS TEXT),
              'delete',
              strftime('%Y-%m-%dT%H:%M:%fZ', 'now'),
              COALESCE((
                SELECT revision
                FROM _sync_change_log
                WHERE table_name = '$table'
                  AND row_id = CAST(OLD.id AS TEXT)
              ), 0) + 1
            );
          END
        ''');
      } catch (error) {
        debugPrint('Could not track cloud changes for $table: $error');
      }
    }
  }

  Future<PendingCloudChanges> exportPendingCloudChanges() async {
    final myDb = await db;
    if (myDb == null) {
      return const PendingCloudChanges(
        data: <String, dynamic>{},
        acknowledgements: <CloudChangeAcknowledgement>[],
        changedRows: 0,
        deletedRows: 0,
      );
    }
    await _ensureSyncTombstoneInfrastructure(myDb);
    if (!await isDatabaseHealthy()) {
      throw StateError('database image malformed (code 11)');
    }

    final logRows = await myDb.query(
      '_sync_change_log',
      orderBy: 'changed_at ASC, table_name ASC, row_id ASC',
    );
    if (logRows.isEmpty) {
      return const PendingCloudChanges(
        data: <String, dynamic>{},
        acknowledgements: <CloudChangeAcknowledgement>[],
        changedRows: 0,
        deletedRows: 0,
      );
    }

    final data = <String, dynamic>{};
    final acknowledgements = <CloudChangeAcknowledgement>[];
    final tombstones = <Map<String, dynamic>>[];
    final orderIdsToBundle = <String>{};
    var changedRows = 0;
    var deletedRows = 0;

    void upsertExportRow(String table, Map<String, dynamic> row) {
      final sanitized = _sanitizeCloudExportRow(
        table,
        Map<String, dynamic>.from(row),
      );
      final rowId = sanitized['id']?.toString();
      final list =
          data.putIfAbsent(table, () => <Map<String, dynamic>>[])
              as List<Map<String, dynamic>>;
      if (rowId != null && rowId.isNotEmpty) {
        final existingIndex = list.indexWhere(
          (existing) => existing['id']?.toString() == rowId,
        );
        if (existingIndex >= 0) {
          list[existingIndex] = sanitized;
          return;
        }
      }
      list.add(sanitized);
    }

    void rememberOrderId(dynamic value) {
      final text = value?.toString() ?? '';
      if (text.isNotEmpty) orderIdsToBundle.add(text);
    }

    Future<void> rememberOrderBundleForRow(
      String table,
      String rowId, [
      Map<String, dynamic>? row,
    ]) async {
      if (table == 'Commandes') {
        rememberOrderId(rowId);
        return;
      }
      if (table == 'Commandes_details' || table == 'Commandes_deliveries') {
        Map<String, dynamic>? currentRow = row;
        if (currentRow == null) {
          final currentRows = await myDb.query(
            table,
            where: 'id = ? OR CAST(id AS TEXT) = ?',
            whereArgs: [rowId, rowId],
            limit: 1,
          );
          if (currentRows.isNotEmpty) {
            currentRow = Map<String, dynamic>.from(currentRows.first);
          }
        }
        if (currentRow != null) {
          rememberOrderId(currentRow['id_commandes']);
        }
      }
    }

    for (final logRow in logRows) {
      final table = logRow['table_name']?.toString() ?? '';
      final rowId = logRow['row_id']?.toString() ?? '';
      final operation = logRow['operation']?.toString() ?? '';
      final revision = (logRow['revision'] as num?)?.toInt() ?? 0;
      if (!_isSafeSqlIdentifier(table) ||
          table.startsWith('_sync_') ||
          table == 'SyncTombstones' ||
          rowId.isEmpty ||
          revision <= 0) {
        continue;
      }

      acknowledgements.add(
        CloudChangeAcknowledgement(
          table: table,
          rowId: rowId,
          revision: revision,
        ),
      );

      if (operation == 'delete') {
        await rememberOrderBundleForRow(table, rowId);
        final matching = await myDb.query(
          'SyncTombstones',
          where: 'table_name = ? AND row_id = ?',
          whereArgs: [table, rowId],
          limit: 1,
        );
        tombstones.add(
          matching.isNotEmpty
              ? Map<String, dynamic>.from(matching.first)
              : <String, dynamic>{
                  'table_name': table,
                  'row_id': rowId,
                  'deleted_at':
                      logRow['changed_at']?.toString() ??
                      DateTime.now().toUtc().toIso8601String(),
                },
        );
        deletedRows++;
        continue;
      }

      final rows = await myDb.query(
        table,
        where: 'id = ?',
        whereArgs: [rowId],
        limit: 1,
      );
      if (rows.isEmpty) {
        final matching = await myDb.query(
          'SyncTombstones',
          where: 'table_name = ? AND row_id = ?',
          whereArgs: [table, rowId],
          limit: 1,
        );
        tombstones.add(
          matching.isNotEmpty
              ? Map<String, dynamic>.from(matching.first)
              : <String, dynamic>{
                  'table_name': table,
                  'row_id': rowId,
                  'deleted_at':
                      logRow['changed_at']?.toString() ??
                      DateTime.now().toUtc().toIso8601String(),
                },
        );
        deletedRows++;
        continue;
      }

      final currentRow = Map<String, dynamic>.from(rows.first);
      await rememberOrderBundleForRow(table, rowId, currentRow);
      upsertExportRow(table, currentRow);
      changedRows++;
    }

    for (final orderId in orderIdsToBundle) {
      final orderRows = await myDb.query(
        'Commandes',
        where: 'id = ? OR CAST(id AS TEXT) = ?',
        whereArgs: [orderId, orderId],
        limit: 1,
      );
      if (orderRows.isEmpty) continue;
      upsertExportRow('Commandes', Map<String, dynamic>.from(orderRows.first));

      final detailRows = await myDb.query(
        'Commandes_details',
        where: 'id_commandes = ? OR CAST(id_commandes AS TEXT) = ?',
        whereArgs: [orderId, orderId],
      );
      for (final detailRow in detailRows) {
        upsertExportRow(
          'Commandes_details',
          Map<String, dynamic>.from(detailRow),
        );
      }

      try {
        final deliveryRows = await myDb.query(
          'Commandes_deliveries',
          where: 'id_commandes = ? OR CAST(id_commandes AS TEXT) = ?',
          whereArgs: [orderId, orderId],
        );
        for (final deliveryRow in deliveryRows) {
          upsertExportRow(
            'Commandes_deliveries',
            Map<String, dynamic>.from(deliveryRow),
          );
        }
      } catch (_) {
        // Older databases may not have delivery rows yet.
      }
    }

    if (tombstones.isNotEmpty) {
      data['SyncTombstones'] = tombstones;
    }
    return PendingCloudChanges(
      data: data,
      acknowledgements: acknowledgements,
      changedRows: changedRows,
      deletedRows: deletedRows,
    );
  }

  Future<void> acknowledgePendingCloudChanges(
    List<CloudChangeAcknowledgement> acknowledgements,
  ) async {
    if (acknowledgements.isEmpty) return;
    final myDb = await db;
    if (myDb == null) return;
    await myDb.transaction((txn) async {
      for (final acknowledgement in acknowledgements) {
        await txn.delete(
          '_sync_change_log',
          where: 'table_name = ? AND row_id = ? AND revision = ?',
          whereArgs: [
            acknowledgement.table,
            acknowledgement.rowId,
            acknowledgement.revision,
          ],
        );
      }
    });
  }

  Future<void> clearPendingCloudChanges() async {
    final myDb = await db;
    if (myDb == null) return;
    await _ensureSyncTombstoneInfrastructure(myDb);
    await myDb.transaction((txn) async {
      await txn.delete('_sync_change_log');
      await txn.delete('SyncTombstones');
    });
  }

  Future<bool> hasPendingCloudChanges() async {
    final myDb = await db;
    if (myDb == null) return false;
    await _ensureSyncTombstoneInfrastructure(myDb);
    final rows = await myDb.rawQuery('SELECT 1 FROM _sync_change_log LIMIT 1');
    return rows.isNotEmpty;
  }

  Future<Map<String, int>> readSyncTableCounts(
    Iterable<String> tableNames,
  ) async {
    final myDb = await db;
    if (myDb == null) return const <String, int>{};
    final counts = <String, int>{};
    for (final table in tableNames) {
      if (!_isSafeSqlIdentifier(table)) continue;
      final exists = await myDb.rawQuery(
        "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ? LIMIT 1",
        [table],
      );
      if (exists.isEmpty) continue;
      final result = await myDb.rawQuery(
        'SELECT COUNT(*) AS count FROM $table',
      );
      counts[table] = (result.first['count'] as num?)?.toInt() ?? 0;
    }
    return counts;
  }

  Future<Map<String, dynamic>> exportAllData() async {
    Database? myDb = await db;
    final Map<String, dynamic> allData = {};
    if (myDb == null) return allData;
    await _ensureSyncSchema(myDb);
    if (!await isDatabaseHealthy()) {
      throw StateError(
        'database image malformed (code 11): '
        'Ù‚Ø§Ø¹Ø¯Ø© SQLite Ø§Ù„Ù…Ø­Ù„ÙŠØ© ØªØ§Ù„ÙØ©ØŒ ÙˆØªÙ… Ø¥ÙŠÙ‚Ø§Ù Ø§Ù„Ø±ÙØ¹ Ù„Ø­Ù…Ø§ÙŠØ© Ø§Ù„Ù†Ø³Ø®Ø© Ø§Ù„Ø³Ø­Ø§Ø¨ÙŠØ©.',
      );
    }

    // Discover the real SQLite schema instead of maintaining a partial list.
    // This automatically includes new business tables and, importantly,
    // Caisses, attendance, daily jobs, measurements and table configuration.
    final schemaRows = await myDb.rawQuery('''
      SELECT name
      FROM sqlite_master
      WHERE type = 'table'
        AND name NOT LIKE 'sqlite_%'
        AND name NOT LIKE '_sync_%'
        AND name != 'android_metadata'
      ORDER BY name
    ''');
    final tables = schemaRows
        .map((row) => row['name']?.toString() ?? '')
        .where(_isSafeSqlIdentifier)
        .toList();

    final failedTables = <String>[];
    for (final table in tables) {
      try {
        final rows = await myDb.query(table);
        allData[table] = rows
            .map(
              (row) => _sanitizeCloudExportRow(
                table,
                Map<String, dynamic>.from(row),
              ),
            )
            .toList(growable: false);
      } catch (_) {
        failedTables.add(table);
      }
    }
    if (failedTables.isNotEmpty) {
      throw StateError(
        'ØªØ¹Ø°Ø± Ù‚Ø±Ø§Ø¡Ø© Ø¬Ø¯Ø§ÙˆÙ„ Ù‚Ø§Ø¹Ø¯Ø© Ø§Ù„Ø¨ÙŠØ§Ù†Ø§Øª Ø§Ù„ØªØ§Ù„ÙŠØ© Ù„Ù„Ù†Ø³Ø® Ø§Ù„Ø³Ø­Ø§Ø¨ÙŠ: '
        '${failedTables.join(', ')}',
      );
    }
    return allData;
  }

  Map<String, dynamic> _sanitizeCloudExportRow(
    String table,
    Map<String, dynamic> row,
  ) {
    if (table == 'Commandes_details') {
      row.remove('drawing_image_base64');
      row.remove('drawing_image_path');
    }
    return row;
  }

  void _preserveLocalOnlyImportColumns(
    String table,
    Map<String, dynamic> imported,
    Map<String, Object?> local,
  ) {
    if (table == 'Commandes_details') {
      for (final key in const ['drawing_image_base64', 'drawing_image_path']) {
        final incoming = imported[key]?.toString() ?? '';
        final existing = local[key]?.toString() ?? '';
        if (incoming.isEmpty && existing.isNotEmpty) {
          imported[key] = existing;
        }
      }
      return;
    }

    if (table == 'WorkerAllocations') {
      int asInt(Object? value) {
        if (value is num) return value.toInt();
        return int.tryParse(value?.toString() ?? '') ?? 0;
      }

      final localTransferred = asInt(local['is_transferred_to_dist']) == 1;
      final incomingTransferred =
          asInt(imported['is_transferred_to_dist']) == 1;
      if (!localTransferred || incomingTransferred) return;

      final localMap = Map<String, dynamic>.from(local);
      final localTime = _rowUpdateTime(localMap);
      final incomingTime = _rowUpdateTime(imported);
      final incomingIsNewer =
          localTime != null &&
          incomingTime != null &&
          incomingTime.isAfter(localTime);
      if (incomingIsNewer) return;

      for (final key in const [
        'is_manufactured',
        'manufactured_at',
        'is_glass_installed',
        'glass_installed_at',
        'is_distributed',
        'distributed_at',
        'is_transferred_to_dist',
        'transferred_at',
        'is_installed',
        'installed_at',
        'installation_worker_uid',
        'installation_assigned_at',
        'is_completed',
        'completed_at',
        'has_reserve',
        'reserve_notes',
        'reserve_at',
        'archive_locked',
        'updated_at',
      ]) {
        if (local.containsKey(key)) {
          imported[key] = local[key];
        }
      }
    }
  }

  Future<void> _ensureSyncSchema(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS Client (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        client_code INTEGER NOT NULL DEFAULT 0,
        firstname TEXT NOT NULL,
        lastname TEXT NOT NULL,
        phone1 TEXT,
        phone2 TEXT,
        email TEXT,
        address TEXT,
        created_at TEXT NOT NULL DEFAULT (datetime('now')),
        updated_at TEXT NOT NULL DEFAULT (datetime('now')),
        creation_platform TEXT NOT NULL DEFAULT 'unknown'
      )
    ''');
    await _ensureClientCodeInfrastructure(db);
    await db.execute('''
      CREATE TABLE IF NOT EXISTS Commandes (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        order_code INTEGER NOT NULL DEFAULT 0,
        client_id INTEGER NOT NULL,
        status TEXT,
        description TEXT,
        remise REAL DEFAULT 0.0,
        tva REAL DEFAULT 0.0,
        total REAL NOT NULL DEFAULT 0.0,
        net_payable REAL NOT NULL DEFAULT 0.0,
        advance_payment REAL NOT NULL DEFAULT 0.0,
        payment_status TEXT NOT NULL DEFAULT 'Unpaid',
        created_at TEXT NOT NULL DEFAULT (datetime('now')),
        updated_at TEXT NOT NULL DEFAULT (datetime('now'))
      )
    ''');
    await _ensureOrderCodeInfrastructure(db);
    await db.execute('''
      CREATE TABLE IF NOT EXISTS Commandes_details (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        id_commandes INTEGER NOT NULL,
        largeur INTEGER NOT NULL DEFAULT 0,
        hauteur INTEGER NOT NULL DEFAULT 0,
        game TEXT NOT NULL DEFAULT '',
        quantity INTEGER NOT NULL DEFAULT 1,
        glass TEXT NOT NULL DEFAULT '',
        color TEXT NOT NULL DEFAULT '',
        volet TEXT NOT NULL DEFAULT '',
        accessories TEXT NOT NULL DEFAULT '',
        description TEXT NOT NULL DEFAULT '',
        price DECIMAL(10,2) NOT NULL DEFAULT 0.0,
        window_type TEXT,
        partitions_json TEXT,
        drawing_image_path TEXT,
        delivered_qty INTEGER DEFAULT 0,
        instances_json TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS Commandes_deliveries (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        id_commandes INTEGER NOT NULL,
        client_id INTEGER NOT NULL,
        delivery_date TEXT NOT NULL,
        items_json TEXT NOT NULL,
        total_amount REAL NOT NULL DEFAULT 0.0,
        FOREIGN KEY (id_commandes) REFERENCES Commandes(id) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS ShutterComponents (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        component_type TEXT NOT NULL DEFAULT 'Lame',
        name TEXT NOT NULL,
        price REAL NOT NULL DEFAULT 0.0,
        unit TEXT NOT NULL DEFAULT 'sqm',
        scope TEXT NOT NULL DEFAULT 'Global',
        series_id INTEGER,
        series_ids TEXT,
        visible_height_cm REAL NOT NULL DEFAULT 0.0,
        cutting_deduction_cm REAL NOT NULL DEFAULT 0.0,
        bar_length_m REAL NOT NULL DEFAULT 0.0,
        measurement TEXT DEFAULT '',
        track_measurement TEXT DEFAULT '',
        is_active INTEGER NOT NULL DEFAULT 1,
        shutter_subtype TEXT NOT NULL DEFAULT 'normal',
        motor_has_emergency_crank INTEGER NOT NULL DEFAULT 0,
        cap_thickness REAL NOT NULL DEFAULT 0.0,
        max_width_mm REAL NOT NULL DEFAULT 6000.0
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS Accessories (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        type TEXT NOT NULL,
        price REAL NOT NULL DEFAULT 0.0,
        material_type TEXT NOT NULL DEFAULT 'Aluminium',
        scope TEXT NOT NULL DEFAULT 'Global',
        series_id INTEGER,
        series_ids TEXT,
        screw_count INTEGER NOT NULL DEFAULT 0,
        is_active INTEGER NOT NULL DEFAULT 1
      )
    ''');
    await _ensureShutterColorTables(db);

    // ShutterSqmPrices â€” Ø³Ø¹Ø± Ø§Ù„Ù…ØªØ± Ø§Ù„Ù…Ø±Ø¨Ø¹ Ù„Ù„Ø³ØªØ§Ø± Ø­Ø³Ø¨ Ù†ÙˆØ¹ Ø§Ù„Ø´ÙØ±Ø© ÙˆØ§Ù„Ù„ÙˆÙ†
    await db.execute('''
      CREATE TABLE IF NOT EXISTS ShutterSqmPrices (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        blade_type TEXT NOT NULL,
        color_id INTEGER NOT NULL,
        price_per_sqm REAL NOT NULL DEFAULT 0.0,
        UNIQUE(blade_type, color_id)
      )
    ''');

    // Kit Bundle tables â€” exact schema matching _onUpgrade (v38)
    await db.execute('''
      CREATE TABLE IF NOT EXISTS KitBundles (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        description TEXT,
        per_leaf INTEGER NOT NULL DEFAULT 0,
        is_active INTEGER NOT NULL DEFAULT 1,
        is_selling_calculated INTEGER NOT NULL DEFAULT 1
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS KitBundleItems (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        kit_id INTEGER NOT NULL,
        component_type TEXT NOT NULL,
        qty_mode TEXT NOT NULL DEFAULT 'fixed',
        dimension TEXT,
        base_qty REAL NOT NULL DEFAULT 1,
        unit TEXT NOT NULL DEFAULT 'Ù‚Ø·Ø¹Ø©',
        mechanism_scope TEXT NOT NULL DEFAULT 'all',
        sort_order INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY (kit_id) REFERENCES KitBundles(id) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS KitItemRanges (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        item_id INTEGER NOT NULL,
        min_mm REAL NOT NULL,
        max_mm REAL NOT NULL,
        product_name TEXT NOT NULL,
        price REAL NOT NULL DEFAULT 0.0,
        qty REAL NOT NULL DEFAULT 1,
        compatibility_group INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY (item_id) REFERENCES KitBundleItems(id) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS KitItemVariants (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        item_id INTEGER NOT NULL,
        ouvrant_type TEXT NOT NULL,
        product_name TEXT NOT NULL,
        price REAL NOT NULL DEFAULT 0.0,
        qty REAL NOT NULL DEFAULT 1,
        FOREIGN KEY (item_id) REFERENCES KitBundleItems(id) ON DELETE CASCADE
      )
    ''');

    final alters = <String>[
      "ALTER TABLE ShutterComponents ADD COLUMN component_type TEXT NOT NULL DEFAULT 'Lame'",
      "ALTER TABLE ShutterComponents ADD COLUMN unit TEXT NOT NULL DEFAULT 'sqm'",
      "ALTER TABLE ShutterComponents ADD COLUMN scope TEXT NOT NULL DEFAULT 'Global'",
      "ALTER TABLE ShutterComponents ADD COLUMN series_id INTEGER",
      "ALTER TABLE ShutterComponents ADD COLUMN series_ids TEXT",
      "ALTER TABLE ShutterComponents ADD COLUMN visible_height_cm REAL NOT NULL DEFAULT 0.0",
      "ALTER TABLE ShutterComponents ADD COLUMN cutting_deduction_cm REAL NOT NULL DEFAULT 0.0",
      "ALTER TABLE ShutterComponents ADD COLUMN bar_length_m REAL NOT NULL DEFAULT 0.0",
      "ALTER TABLE ShutterComponents ADD COLUMN measurement TEXT DEFAULT ''",
      "ALTER TABLE ShutterComponents ADD COLUMN track_measurement TEXT DEFAULT ''",
      "ALTER TABLE ShutterComponents ADD COLUMN motor_has_emergency_crank INTEGER NOT NULL DEFAULT 0",
      "ALTER TABLE ShutterComponents ADD COLUMN is_active INTEGER NOT NULL DEFAULT 1",
      "ALTER TABLE Commandes ADD COLUMN advance_payment REAL NOT NULL DEFAULT 0.0",
      "ALTER TABLE Commandes ADD COLUMN payment_status TEXT NOT NULL DEFAULT 'Unpaid'",
      "ALTER TABLE Commandes ADD COLUMN created_at TEXT NOT NULL DEFAULT (datetime('now'))",
      "ALTER TABLE Commandes ADD COLUMN updated_at TEXT NOT NULL DEFAULT (datetime('now'))",
      "ALTER TABLE Commandes_details ADD COLUMN drawing_image_path TEXT",
      "ALTER TABLE Commandes_details ADD COLUMN window_type TEXT",
      "ALTER TABLE Commandes_details ADD COLUMN partitions_json TEXT",
      "ALTER TABLE Commandes_details ADD COLUMN updated_at TEXT",
      "ALTER TABLE Client ADD COLUMN creation_platform TEXT NOT NULL DEFAULT 'unknown'",
      "ALTER TABLE Accessories ADD COLUMN material_type TEXT NOT NULL DEFAULT 'Aluminium'",
      "ALTER TABLE Accessories ADD COLUMN scope TEXT NOT NULL DEFAULT 'Global'",
      "ALTER TABLE Accessories ADD COLUMN series_id INTEGER",
      "ALTER TABLE Accessories ADD COLUMN series_ids TEXT",
      "ALTER TABLE Accessories ADD COLUMN screw_count INTEGER NOT NULL DEFAULT 0",
      "ALTER TABLE Accessories ADD COLUMN is_moteur_screw INTEGER DEFAULT 0",
      "ALTER TABLE Accessories ADD COLUMN is_caisson_screw INTEGER DEFAULT 0",
      "ALTER TABLE Accessories ADD COLUMN is_batmo_screw INTEGER DEFAULT 0",
      "ALTER TABLE Accessories ADD COLUMN is_bouchon_batmo_screw INTEGER DEFAULT 0",
      "ALTER TABLE Accessories ADD COLUMN is_renfort_screw INTEGER DEFAULT 0",
      "ALTER TABLE Accessories ADD COLUMN is_manivelle_screw INTEGER DEFAULT 0",
      "ALTER TABLE Accessories ADD COLUMN is_tandem_screw INTEGER DEFAULT 0",
      "ALTER TABLE Accessories ADD COLUMN is_kit_screw INTEGER DEFAULT 0",
      "ALTER TABLE Accessories ADD COLUMN is_assembly_screw INTEGER DEFAULT 0",
      "ALTER TABLE Accessories ADD COLUMN is_accessory_screw INTEGER DEFAULT 0",
      "ALTER TABLE Accessories ADD COLUMN is_installation_screw INTEGER DEFAULT 0",
      "ALTER TABLE Accessories ADD COLUMN is_gache_simple INTEGER DEFAULT 0",
      "ALTER TABLE Accessories ADD COLUMN is_gache_double INTEGER DEFAULT 0",
      "ALTER TABLE Accessories ADD COLUMN is_gache_porte INTEGER DEFAULT 0",
      "ALTER TABLE Accessories ADD COLUMN is_lock_clef INTEGER DEFAULT 0",
      "ALTER TABLE Accessories ADD COLUMN is_lock_condamnation INTEGER DEFAULT 0",
      "ALTER TABLE Accessories ADD COLUMN is_active INTEGER NOT NULL DEFAULT 1",
      "ALTER TABLE Series ADD COLUMN has_three_piece_sash INTEGER NOT NULL DEFAULT 0",
      "ALTER TABLE WorkerAllocations ADD COLUMN is_transferred_to_dist INTEGER DEFAULT 0",
      "ALTER TABLE WorkerAllocations ADD COLUMN transferred_at TEXT",
      "ALTER TABLE WorkerAllocations ADD COLUMN archive_locked INTEGER DEFAULT 0",
      "ALTER TABLE WorkerAllocations ADD COLUMN installation_worker_uid TEXT",
      "ALTER TABLE WorkerAllocations ADD COLUMN installation_assigned_at TEXT",
      "ALTER TABLE WorkerAllocations ADD COLUMN updated_at TEXT",
    ];
    for (final sql in alters) {
      try {
        await db.execute(sql);
      } catch (_) {}
    }
    await _ensureSeriesDesignTables(db);
    await _ensurePaymentAllocationSchema(db);
    await _ensureSyncTombstoneInfrastructure(db);
  }

  Future<Set<String>> _tableColumns(DatabaseExecutor db, String table) async {
    if (!_isSafeSqlIdentifier(table)) return <String>{};
    final info = await db.rawQuery('PRAGMA table_info($table)');
    return info.map((row) => row['name'].toString()).toSet();
  }

  static bool _isSafeSqlIdentifier(String value) {
    return RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$').hasMatch(value);
  }

  Future<void> _ensureProfileColorsSyncIds(DatabaseExecutor executor) async {
    final exists = await executor.rawQuery(
      "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'ProfileColors' LIMIT 1",
    );
    if (exists.isEmpty) return;

    await executor.execute('''
      CREATE TABLE IF NOT EXISTS ProfileColorConfig (
        id INTEGER PRIMARY KEY,
        profile_id INTEGER NOT NULL UNIQUE,
        configured_at TEXT NOT NULL
      )
    ''');

    final columns = await _tableColumns(executor, 'ProfileColors');
    if (!columns.contains('id')) {
      try {
        await executor.execute('ALTER TABLE ProfileColors ADD COLUMN id TEXT');
      } catch (_) {}
    }
    await executor.rawUpdate('''
      UPDATE ProfileColors
      SET id = CAST(profile_id AS TEXT) || ':' || CAST(color_id AS TEXT)
      WHERE id IS NULL OR TRIM(CAST(id AS TEXT)) = ''
    ''');
    await executor.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_profile_colors_sync_id ON ProfileColors(id)',
    );
  }

  Future<int?> _defaultWhiteProfileColorId(DatabaseExecutor executor) async {
    final rows = await executor.rawQuery('''
      SELECT id FROM Colors
      WHERE ($_whiteColorSql)
        AND (is_active = 1 OR is_active IS NULL)
      ORDER BY id ASC
      LIMIT 1
    ''');
    if (rows.isEmpty) return null;
    final rawId = rows.first['id'];
    return rawId is num ? rawId.toInt() : int.tryParse(rawId?.toString() ?? '');
  }

  Future<bool> _ensureProfileColorDefaults(
    DatabaseExecutor executor, {
    int? profileId,
  }) async {
    await _ensureProfileColorsSyncIds(executor);
    final profiles = await executor.query(
      'Profile',
      columns: const ['id'],
      where: profileId == null ? null : 'id = ?',
      whereArgs: profileId == null ? null : [profileId],
    );
    if (profiles.isEmpty) return false;

    final whiteColorId = await _defaultWhiteProfileColorId(executor);
    var changed = false;
    for (final profile in profiles) {
      final rawProfileId = profile['id'];
      final pId = rawProfileId is num
          ? rawProfileId.toInt()
          : int.tryParse(rawProfileId?.toString() ?? '');
      if (pId == null) continue;

      final config = await executor.query(
        'ProfileColorConfig',
        columns: const ['id'],
        where: 'profile_id = ?',
        whereArgs: [pId],
        limit: 1,
      );
      if (config.isNotEmpty) continue;

      final existingColors = await executor.query(
        'ProfileColors',
        columns: const ['color_id'],
        where: 'profile_id = ?',
        whereArgs: [pId],
        limit: 1,
      );
      if (existingColors.isEmpty && whiteColorId != null) {
        await executor.insert('ProfileColors', {
          'id': _profileColorSyncId(pId, whiteColorId),
          'profile_id': pId,
          'color_id': whiteColorId,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
      }
      await executor.insert('ProfileColorConfig', {
        'id': pId,
        'profile_id': pId,
        'configured_at': DateTime.now().toUtc().toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      changed = true;
    }
    return changed;
  }

  Future<void> ensureProfileColorDefaults({int? profileId}) async {
    final myDb = await db;
    if (myDb == null) return;
    final changed = await myDb.transaction<bool>(
      (txn) => _ensureProfileColorDefaults(txn, profileId: profileId),
    );
    if (changed) CloudSyncService().notifyCatalogChange();
  }

  dynamic _sanitizeImportValue(dynamic value) {
    if (value == null) return null;
    if (value is Timestamp) return value.toDate().toIso8601String();
    if (value is DateTime) return value.toIso8601String();
    if (value is bool) return value ? 1 : 0;
    if (value is num || value is String) return value;
    if (value is Map) {
      return jsonEncode(value);
    }
    if (value is List) {
      return jsonEncode(value);
    }
    return value.toString();
  }

  Map<String, dynamic> _sanitizeImportRow(Map<String, dynamic> row) {
    final sanitized = <String, dynamic>{};
    for (final entry in row.entries) {
      final value = _sanitizeImportValue(entry.value);
      if (value != null) {
        sanitized[entry.key] = value;
      }
    }
    return sanitized;
  }

  String _tombstoneKey(String table, Object rowId) =>
      '$table\u0000${rowId.toString()}';

  bool _isIncomingDeletionNewer(String incoming, String existing) {
    final incomingDate = DateTime.tryParse(incoming);
    final existingDate = DateTime.tryParse(existing);
    if (incomingDate != null && existingDate != null) {
      return incomingDate.isAfter(existingDate);
    }
    return incoming.compareTo(existing) > 0;
  }

  DateTime? _rowUpdateTime(Map<String, dynamic> row) {
    const updateKeys = <String>[
      'updated_at',
      'updatedAt',
      'modified_at',
      'modifiedAt',
      'last_updated',
      'lastUpdated',
    ];
    for (final key in updateKeys) {
      final raw = row[key];
      if (raw == null) continue;
      if (raw is DateTime) return raw;
      if (raw is Timestamp) return raw.toDate();
      final parsed = DateTime.tryParse(raw.toString());
      if (parsed != null) return parsed;
    }
    return null;
  }

  bool _localRowIsNewer(
    Map<String, dynamic> local,
    Map<String, dynamic> incoming,
  ) {
    final localTime = _rowUpdateTime(local);
    final incomingTime = _rowUpdateTime(incoming);
    return localTime != null &&
        incomingTime != null &&
        localTime.isAfter(incomingTime);
  }

  Future<Set<String>> _mergeAndReadSyncTombstones(
    DatabaseExecutor db,
    dynamic incomingRows,
  ) async {
    if (incomingRows is List) {
      for (final rawRow in incomingRows) {
        if (rawRow is! Map) continue;
        final row = _sanitizeImportRow(Map<String, dynamic>.from(rawRow));
        final table = row['table_name']?.toString() ?? '';
        final rowId = row['row_id']?.toString() ?? '';
        final deletedAt = row['deleted_at']?.toString() ?? '';
        if (!_isSafeSqlIdentifier(table) ||
            rowId.isEmpty ||
            deletedAt.isEmpty) {
          continue;
        }

        final existing = await db.query(
          'SyncTombstones',
          where: 'table_name = ? AND row_id = ?',
          whereArgs: [table, rowId],
          limit: 1,
        );
        if (existing.isNotEmpty) {
          final existingDeletedAt =
              existing.first['deleted_at']?.toString() ?? '';
          if (!_isIncomingDeletionNewer(deletedAt, existingDeletedAt)) {
            continue;
          }
        }
        await db.insert('SyncTombstones', {
          'table_name': table,
          'row_id': rowId,
          'deleted_at': deletedAt,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    }

    final allRows = await db.query('SyncTombstones');
    return allRows
        .map(
          (row) => _tombstoneKey(
            row['table_name']?.toString() ?? '',
            row['row_id']?.toString() ?? '',
          ),
        )
        .toSet();
  }

  Future<void> _applySyncTombstones(
    DatabaseExecutor db,
    Set<String> tombstoneKeys,
  ) async {
    for (final key in tombstoneKeys) {
      final separator = key.indexOf('\u0000');
      if (separator <= 0 || separator >= key.length - 1) continue;
      final table = key.substring(0, separator);
      final rowId = key.substring(separator + 1);
      if (!_isSafeSqlIdentifier(table) ||
          table == 'SyncTombstones' ||
          table.startsWith('_sync_')) {
        continue;
      }
      final columns = await _tableColumns(db, table);
      if (!columns.contains('id')) continue;
      await db.delete(table, where: 'id = ?', whereArgs: [rowId]);
    }
  }

  /// Imports a cloud snapshot and retries once after reopening SQLite when the
  /// Android file handle has become stale (SQLITE_READONLY_DBMOVED / code
  /// 1032). This is the write path used by full restores and deltas.
  Future<void> importAllData(
    Map<String, dynamic> data, {
    bool replaceAllData = false,
    bool mergeAllData = false,
  }) {
    return _retryAfterDatabaseMove(
      () => _importAllDataOnce(
        data,
        replaceAllData: replaceAllData,
        mergeAllData: mergeAllData,
      ),
    );
  }

  Future<void> _importAllDataOnce(
    Map<String, dynamic> data, {
    bool replaceAllData = false,
    bool mergeAllData = false,
  }) async {
    Database? myDb = await db;
    if (myDb == null) return;
    final orderedTables = [
      'SyncTombstones',
      'Profile',
      'Series',
      'Sections',
      'SeriesTableConfig',
      'SeriesDesignConfig',
      'SeriesDesignRoles',
      'CatalogItemRules',
      'SectionJointLinks',
      'SeriesShutterRules',
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
      'Colors',
      'Accessories',
      'Joints',
      'Glass',
      'GlassColorPrices',
      'ShutterComponents',
      'ShutterColorPrices',
      'ShutterComponentColors',
      'ShutterSqmPrices',
      'ShutterBoxLimits',
      'CaissonTunnelPrices',
      'SeriesColorPrices',
      'SectionColorPrices',
      'AccessoryColorPrices',
      'ProfileColors',
      'ProfileColorConfig',
      'KitBundles',
      'KitBundleItems',
      'KitItemRanges',
      'KitItemVariants',
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
      'MaterialRemnants',
      'MaterialScrap',
    ];
    final importTables = <String>[
      ...orderedTables.where(data.containsKey),
      ...data.keys.where(
        (table) =>
            !orderedTables.contains(table) && _isSafeSqlIdentifier(table),
      ),
    ];

    // Ø§Ù„Ø¬Ø¯Ø§ÙˆÙ„ Ø§Ù„ØªÙŠ ØªØ­ØªÙˆÙŠ Ø¹Ù„Ù‰ Ø¨ÙŠØ§Ù†Ø§Øª Ø§Ù„Ù…Ø³ØªØ®Ø¯Ù… Ø§Ù„Ø­Ø³Ø§Ø³Ø©.
    // Ù„Ù† ÙŠØªÙ… Ù…Ø³Ø­ Ù‡Ø°Ù‡ Ø§Ù„Ø¬Ø¯Ø§ÙˆÙ„ Ø¥Ø°Ø§ ÙƒØ§Ù† Ø§Ù„Ù€ payload ÙŠØ¹ÙŠØ¯Ù‡Ø§ ÙØ§Ø±ØºØ© ØªÙ…Ø§Ù…Ø§Ù‹ØŒ
    // Ù„Ù„Ø­Ù…Ø§ÙŠØ© Ù…Ù† Ø­Ø°Ù Ø§Ù„Ø¨ÙŠØ§Ù†Ø§Øª Ø§Ù„Ù…Ø­Ù„ÙŠØ© Ø¨Ø³Ø¨Ø¨ Ø§Ø³ØªØ¹Ø§Ø¯Ø© Ù‚Ø§Ø¹Ø¯Ø© Ø¨ÙŠØ§Ù†Ø§Øª ÙØ§Ø±ØºØ© Ù…Ù† Ø§Ù„Ø³Ø­Ø§Ø¨Ø©.
    const sensitiveTransactionalTables = {
      'Client',
      'Projects',
      'Commandes',
      'Commandes_details',
      'Commandes_deliveries',
      'Achats',
      'Achat_items',
      'Achat_Details',
      'Suppliers',
      'Employees',
      'Measurements',
      'Caisses',
      'Treasury',
      'PaymentAllocations',
      'WorkerTransactions',
      'WorkerAllocations',
      'WorkerAttendance',
      'WorkerDailyJobs',
      'InventoryTransactions',
      'CurrentStock',
      'InventorySettings',
      'OrderCuttingSessions',
      'OrderInventoryIssueSessions',
      'MaterialRemnants',
      'MaterialScrap',
    };

    await myDb.transaction((txn) async {
      await txn.execute('PRAGMA foreign_keys = OFF');
      await _ensureSyncSchema(txn);
      await txn.update('_sync_runtime_flags', {
        'suppress_tombstones': 1,
      }, where: 'id = 1');
      final tombstoneKeys = await _mergeAndReadSyncTombstones(
        txn,
        data['SyncTombstones'],
      );

      for (final table in importTables) {
        if (table == 'SyncTombstones' || table.startsWith('_sync_')) {
          continue;
        }
        final rows = data[table] as List<dynamic>? ?? [];

        // Ø­Ù…Ø§ÙŠØ©: Ø¥Ø°Ø§ ÙƒØ§Ù† Ø§Ù„Ø¬Ø¯ÙˆÙ„ Ø­Ø³Ø§Ø³Ø§Ù‹ ÙˆØ§Ù„Ù€ payload ÙŠØ¹ÙŠØ¯Ù‡ ÙØ§Ø±ØºØ§Ù‹ØŒ
        // Ø§Ø­ØªÙØ¸ Ø¨Ø§Ù„Ø¨ÙŠØ§Ù†Ø§Øª Ø§Ù„Ù…Ø­Ù„ÙŠØ© ÙˆÙ„Ø§ ØªÙ…Ø³Ø­Ù‡Ø§.
        if (!replaceAllData &&
            sensitiveTransactionalTables.contains(table) &&
            rows.isEmpty) {
          print(
            'importAllData: Skipping wipe of "$table" â€” payload is empty, keeping local data.',
          );
          continue;
        }

        // ðŸ›¡ï¸ Ø­Ù…Ø§ÙŠØ© Ø§Ù„Ø¬Ø¯Ø§ÙˆÙ„ Ø§Ù„Ø­Ø³Ø§Ø³Ø© (Ø§Ù„ØµÙ†Ø¯ÙˆÙ‚ØŒ Ù…Ø¹Ø§Ù…Ù„Ø§Øª Ø§Ù„Ø¹Ù…Ø§Ù„ØŒ Ø§Ù„Ø¥Ø³Ù†Ø§Ø¯Ø§ØªØŒ Ø§Ù„Ø·Ù„Ø¨ÙŠØ§ØªØŒ Ø§Ù„Ø²Ø¨Ø§Ø¦Ù†ØŒ Ø¥Ù„Ø®):
        // Ù„Ø§ Ù†Ù…Ø³Ø­ Ù‡Ø°Ù‡ Ø§Ù„Ø¬Ø¯Ø§ÙˆÙ„ Ù…Ø­Ù„ÙŠØ§Ù‹ Ø¨Ù€ txn.delete(table) Ø¨Ù„ Ù†Ø¹ØªÙ…Ø¯ Ø§Ù„ØªØ¯Ù…ÙŠØ¬ Ø§Ù„Ø°ÙƒÙŠ (upsert) Ù„Ù„Ø­ÙØ§Ø¸ Ø¹Ù„Ù‰ Ø§Ù„Ù…Ø¹Ø§Ù…Ù„Ø§Øª Ø§Ù„Ù…Ø­Ù„ÙŠØ© Ø§Ù„Ø¬Ø¯ÙŠØ¯Ø©
        final shouldReplaceTable =
            replaceAllData ||
            (!mergeAllData && !sensitiveTransactionalTables.contains(table));
        if (shouldReplaceTable) {
          try {
            await txn.delete(table);
          } catch (e) {
            print('Could not clear table $table before import: $e');
          }
        }
        final columns = await _tableColumns(txn, table);
        for (final row in rows) {
          if (row is! Map) continue;
          try {
            final sanitized = _sanitizeImportRow(Map<String, dynamic>.from(row))
              ..removeWhere((key, value) => !columns.contains(key));
            if (table == 'ProfileColors') {
              final profileId = (sanitized['profile_id'] as num?)?.toInt();
              final colorId = (sanitized['color_id'] as num?)?.toInt();
              if (profileId != null && colorId != null) {
                sanitized['id'] = _profileColorSyncId(profileId, colorId);
              }
            }
            if (sanitized.isEmpty) continue;
            final rowId = sanitized['id'];
            if (rowId != null &&
                tombstoneKeys.contains(_tombstoneKey(table, rowId))) {
              continue;
            }
            if (mergeAllData && rowId != null) {
              final localRows = await txn.query(
                table,
                where: 'id = ? OR CAST(id AS TEXT) = ?',
                whereArgs: [rowId, rowId.toString()],
                limit: 1,
              );
              if (localRows.isNotEmpty) {
                if (_localRowIsNewer(localRows.first, sanitized)) {
                  continue;
                }
                _preserveLocalOnlyImportColumns(
                  table,
                  sanitized,
                  localRows.first,
                );
              }
            }
            await txn.insert(
              table,
              sanitized,
              conflictAlgorithm: ConflictAlgorithm.replace,
            );
          } catch (e) {
            print('Failed to import row into $table: $e');
          }
        }
      }
      await _applySyncTombstones(txn, tombstoneKeys);
      await txn.update('_sync_runtime_flags', {
        'suppress_tombstones': 0,
      }, where: 'id = 1');
      await txn.execute('PRAGMA foreign_keys = ON');
    });
    // Old cloud snapshots have no display code fields. Assign immutable codes
    // once immediately after restore, before any list is displayed.
    await _backfillClientCodes(myDb);
    await _backfillOrderCodes(myDb);
  }

  Future<Map<String, dynamic>> exportGlobalCatalog() async {
    final allData = await exportAllData();
    return Map.fromEntries(
      allData.entries.where((entry) => catalogTables.contains(entry.key)),
    );
  }

  Future<void> importGlobalCatalog(Map<String, dynamic> data) async {
    final catalogData = <String, dynamic>{};
    for (final table in catalogTables) {
      if (data.containsKey(table)) {
        catalogData[table] = data[table];
      }
    }
    if (catalogData.isEmpty) {
      throw Exception(
        'â”˜Ã¤â•ªÂº â•ªÂ¬â”˜Ãªâ•ªÂ¼â•ªÂ» â•ªÂ¿â”˜Ã¨â•ªÂºâ”˜Ã¥â•ªÂºâ•ªÂ¬ â”˜Ã¢â•ªÂ¬â•ªÂºâ”˜Ã¤â”˜Ãªâ•ªÂ¼ â•ªâ•¡â•ªÂºâ”˜Ã¤â•ªÂ¡â•ªâŒ â”˜Ã¤â”˜Ã¤â•ªÂºâ•ªâ”‚â•ªÂ¬â”˜Ã¨â•ªâ–’â•ªÂºâ•ªÂ».',
      );
    }
    await importAllData(catalogData);
  }

  Future<Map<String, dynamic>> exportWorkshopData() async {
    final allData = await exportAllData();
    return Map.fromEntries(
      allData.entries.where((entry) => workshopTables.contains(entry.key)),
    );
  }

  Future<void> importWorkshopData(
    Map<String, dynamic> data, {
    bool replaceAllData = false,
  }) async {
    final workshopData = <String, dynamic>{};
    for (final table in workshopTables) {
      if (data.containsKey(table)) {
        workshopData[table] = data[table];
      }
    }
    if (data.containsKey('SyncTombstones')) {
      workshopData['SyncTombstones'] = data['SyncTombstones'];
    }
    if (workshopData.isEmpty) return;
    await importAllData(
      workshopData,
      replaceAllData: replaceAllData,
      mergeAllData: !replaceAllData,
    );
  }

  Future<String> getDatabaseFilePath() async {
    String dbName = 'test.db';
    if (kIsWeb) {
      return dbName;
    } else {
      String dataPath = await _getWritableDatabasesPath();
      return join(dataPath, dbName);
    }
  }

  Future<void> exportDatabaseFile(BuildContext context) async {
    try {
      if (kIsWeb) {
        throw Exception(
          'Ø§Ù„Ù†Ø³Ø® Ø§Ù„Ø§Ø­ØªÙŠØ§Ø·ÙŠ Ø§Ù„Ù…Ø¨Ø§Ø´Ø± Ù„Ù…Ù„ÙØ§Øª Ù‚Ø§Ø¹Ø¯Ø© Ø§Ù„Ø¨ÙŠØ§Ù†Ø§Øª ØºÙŠØ± Ù…Ø¯Ø¹ÙˆÙ… Ø¹Ù„Ù‰ Ø§Ù„ÙˆÙŠØ¨. ÙŠØ±Ø¬Ù‰ Ø§Ø³ØªØ®Ø¯Ø§Ù… ØªØµØ¯ÙŠØ± JSON.',
        );
      }
      final dbPath = await getDatabaseFilePath();
      final dbFile = File(dbPath);
      if (!await dbFile.exists()) {
        throw Exception(
          'Ù…Ù„Ù Ù‚Ø§Ø¹Ø¯Ø© Ø§Ù„Ø¨ÙŠØ§Ù†Ø§Øª ØºÙŠØ± Ù…ÙˆØ¬ÙˆØ¯.',
        );
      }
      final tempDir = await getTemporaryDirectory();
      final tempFile = File('${tempDir.path}/al_erp_backup.db');
      await dbFile.copy(tempFile.path);

      final params = SaveFileDialogParams(sourceFilePath: tempFile.path);
      final finalPath = await FlutterFileDialog.saveFile(params: params);
      if (finalPath != null) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'ØªÙ… ØªØµØ¯ÙŠØ± Ù…Ù„Ù Ù‚Ø§Ø¹Ø¯Ø© Ø§Ù„Ø¨ÙŠØ§Ù†Ø§Øª Ø¨Ù†Ø¬Ø§Ø­!',
              style: TextStyle(fontFamily: 'Cairo'),
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'ÙØ´Ù„ Ø§Ù„ØªØµØ¯ÙŠØ±: $e',
            style: const TextStyle(fontFamily: 'Cairo'),
          ),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> runAutoDailyBackup() async {
    if (kIsWeb) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final lastBackupDate = prefs.getString('last_auto_backup_date');

      if (lastBackupDate == todayStr) {
        return;
      }

      final dbPath = await getDatabaseFilePath();
      final dbFile = File(dbPath);
      if (!await dbFile.exists()) {
        debugPrint('--- AutoBackup: Database file does not exist ---');
        return;
      }

      String? targetFolderPath;
      if (Platform.isAndroid) {
        // 1. Try Documents folder
        final documentsDir = Directory(
          '/storage/emulated/0/Documents/ÙˆØ±Ø´ØªÙŠ',
        );
        try {
          if (!await documentsDir.exists()) {
            await documentsDir.create(recursive: true);
          }
          targetFolderPath = documentsDir.path;
        } catch (_) {
          // 2. Try Download folder as fallback
          final downloadDir = Directory(
            '/storage/emulated/0/Download/ÙˆØ±Ø´ØªÙŠ',
          );
          try {
            if (!await downloadDir.exists()) {
              await downloadDir.create(recursive: true);
            }
            targetFolderPath = downloadDir.path;
          } catch (_) {
            // 3. Try app external storage files directory as ultimate fallback
            final extDir = await getExternalStorageDirectory();
            if (extDir != null) {
              final appCustomDir = Directory('${extDir.path}/ÙˆØ±Ø´ØªÙŠ');
              if (!await appCustomDir.exists()) {
                await appCustomDir.create(recursive: true);
              }
              targetFolderPath = appCustomDir.path;
            }
          }
        }
      } else {
        // iOS or Desktop
        final docDir = await getApplicationDocumentsDirectory();
        final customDir = Directory('${docDir.path}/ÙˆØ±Ø´ØªÙŠ');
        if (!await customDir.exists()) {
          await customDir.create(recursive: true);
        }
        targetFolderPath = customDir.path;
      }

      if (targetFolderPath != null) {
        final targetFile = File('$targetFolderPath/al_erp_backup.db');
        await dbFile.copy(targetFile.path);
        await prefs.setString('last_auto_backup_date', todayStr);
        debugPrint(
          '--- AutoBackup: Successfully exported to ${targetFile.path} ---',
        );
      }
    } catch (e) {
      debugPrint('--- AutoBackup: Failed to run auto daily backup: $e ---');
    }
  }

  Future<void> importDatabaseFile(BuildContext context) async {
    try {
      if (kIsWeb) {
        throw Exception(
          'Ø§Ø³ØªÙŠØ±Ø§Ø¯ Ù…Ù„Ù Ù‚Ø§Ø¹Ø¯Ø© Ø§Ù„Ø¨ÙŠØ§Ù†Ø§Øª Ø§Ù„Ù…Ø¨Ø§Ø´Ø± ØºÙŠØ± Ù…Ø¯Ø¹ÙˆÙ… Ø¹Ù„Ù‰ Ø§Ù„ÙˆÙŠØ¨. ÙŠØ±Ø¬Ù‰ Ø§Ø³ØªØ®Ø¯Ø§Ù… Ø§Ø³ØªÙŠØ±Ø§Ø¯ JSON.',
        );
      }
      final params = const OpenFileDialogParams();
      final filePath = await FlutterFileDialog.pickFile(params: params);
      if (filePath != null) {
        final dbPath = await getDatabaseFilePath();
        if (_db != null) {
          await _db!.close();
          _db = null;
        }
        final selectedFile = File(filePath);
        await selectedFile.copy(dbPath);
        _db = await initDb();
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'ØªÙ… Ø§Ø³ØªÙŠØ±Ø§Ø¯ Ù‚Ø§Ø¹Ø¯Ø© Ø§Ù„Ø¨ÙŠØ§Ù†Ø§Øª Ø¨Ù†Ø¬Ø§Ø­! ÙŠØ±Ø¬Ù‰ Ø¥Ø¹Ø§Ø¯Ø© ØªØ´ØºÙŠÙ„ Ø§Ù„ØªØ·Ø¨ÙŠÙ‚ Ù„ØªØ­Ø¯ÙŠØ« ÙƒØ§ÙØ© Ø§Ù„Ø´Ø§Ø´Ø§Øª.',
              style: TextStyle(fontFamily: 'Cairo'),
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'ÙØ´Ù„ Ø§Ù„Ø§Ø³ØªÙŠØ±Ø§Ø¯: $e',
            style: const TextStyle(fontFamily: 'Cairo'),
          ),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> exportJsonBackup(BuildContext context) async {
    try {
      final allData = await exportAllData();
      final jsonStr = jsonEncode(allData);

      if (kIsWeb) {
        // web download helper using Uri data scheme
        // compiles fine on mobile too
        final urlString =
            'data:application/json;charset=utf-8,${Uri.encodeComponent(jsonStr)}';

        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Ø¬Ø§Ø±ÙŠ Ø¨Ø¯Ø¡ Ø§Ù„ØªØ­Ù…ÙŠÙ„ Ø¹Ù„Ù‰ Ø§Ù„Ù…ØªØµÙØ­...',
              style: TextStyle(fontFamily: 'Cairo'),
            ),
            backgroundColor: Colors.blue,
          ),
        );

        await launchUrl(
          Uri.parse(urlString),
          mode: LaunchMode.externalApplication,
        );
      } else {
        final tempDir = await getTemporaryDirectory();
        final tempFile = File('${tempDir.path}/al_erp_backup.json');
        await tempFile.writeAsString(jsonStr);

        final params = SaveFileDialogParams(sourceFilePath: tempFile.path);
        final finalPath = await FlutterFileDialog.saveFile(params: params);
        if (finalPath != null) {
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'ØªÙ… ØªØµØ¯ÙŠØ± Ù†Ø³Ø®Ø© JSON Ø§Ù„Ø§Ø­ØªÙŠØ§Ø·ÙŠØ© Ø¨Ù†Ø¬Ø§Ø­!',
                style: TextStyle(fontFamily: 'Cairo'),
              ),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'ÙØ´Ù„ ØªØµØ¯ÙŠØ± JSON: $e',
            style: const TextStyle(fontFamily: 'Cairo'),
          ),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> importJsonBackup(BuildContext context) async {
    try {
      if (kIsWeb) {
        throw Exception(
          'Ø§Ù„Ø±Ø¬Ø§Ø¡ Ø§Ù„Ù‚ÙŠØ§Ù… Ø¨Ø§Ù„Ø§Ø³ØªÙŠØ±Ø§Ø¯ Ø¹Ø¨Ø± ØªØ·Ø¨ÙŠÙ‚ Ø§Ù„Ù…ÙˆØ¨Ø§ÙŠÙ„.',
        );
      } else {
        final params = const OpenFileDialogParams();
        final filePath = await FlutterFileDialog.pickFile(params: params);
        if (filePath != null) {
          final content = await File(filePath).readAsString();
          final data = jsonDecode(content);
          if (data is Map<String, dynamic>) {
            await importAllData(data);
            if (!context.mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'ØªÙ… Ø§Ø³ØªÙŠØ±Ø§Ø¯ Ù†Ø³Ø®Ø© JSON Ø§Ù„Ø§Ø­ØªÙŠØ§Ø·ÙŠØ© Ø¨Ù†Ø¬Ø§Ø­! ÙŠØ±Ø¬Ù‰ Ø¥Ø¹Ø§Ø¯Ø© ØªØ´ØºÙŠÙ„ Ø§Ù„ØªØ·Ø¨ÙŠÙ‚.',
                  style: TextStyle(fontFamily: 'Cairo'),
                ),
                backgroundColor: Colors.green,
              ),
            );
          } else {
            throw Exception(
              'ØªÙ†Ø³ÙŠÙ‚ Ù…Ù„Ù Ø§Ù„Ù†Ø³Ø®Ø© Ø§Ù„Ø§Ø­ØªÙŠØ§Ø·ÙŠØ© ØºÙŠØ± ØµØ§Ù„Ø­.',
            );
          }
        }
      }
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'ÙØ´Ù„ Ø§Ø³ØªÙŠØ±Ø§Ø¯ JSON: $e',
            style: const TextStyle(fontFamily: 'Cairo'),
          ),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<List<Map<String, dynamic>>> getRecentActivities() async {
    final database = await db;
    if (database == null) return [];

    List<Map<String, dynamic>> activities = [];

    try {
      final commandes = await database.query(
        'Commandes',
        orderBy: 'created_at DESC',
        limit: 5,
      );
      for (var c in commandes) {
        activities.add({
          'title': 'Ø·Ù„Ø¨ÙŠØ© #${c['id']} - Ø­Ø§Ù„Ø©: ${c['status']}',
          'date': c['created_at'],
          'type': 'commande',
        });
      }
    } catch (_) {}

    try {
      final achats = await database.query(
        'Achats',
        orderBy: 'created_at DESC',
        limit: 5,
      );
      for (var a in achats) {
        activities.add({
          'title':
              'ÙØ§ØªÙˆØ±Ø© Ù…Ø´ØªØ±ÙŠØ§Øª #${a['invoice_number']} - ${a['supplier_name']}',
          'date': a['created_at'],
          'type': 'achat',
        });
      }
    } catch (_) {}

    try {
      final clients = await database.query(
        'Client',
        orderBy: 'created_at DESC',
        limit: 5,
      );
      for (var c in clients) {
        activities.add({
          'title': 'Ø²Ø¨ÙˆÙ† Ø¬Ø¯ÙŠØ¯: ${c['firstname']} ${c['lastname']}',
          'date': c['created_at'],
          'type': 'client',
        });
      }
    } catch (_) {}

    activities.sort((a, b) {
      DateTime da = DateTime.tryParse(a['date'].toString()) ?? DateTime(2000);
      DateTime db = DateTime.tryParse(b['date'].toString()) ?? DateTime(2000);
      return db.compareTo(da);
    });

    return activities.take(5).toList();
  }

  Future<Map<String, dynamic>> getDashboardStats() async {
    final database = await db;
    if (database == null) {
      return {
        'cmdCount': '0',
        'cmdTrend': 'â€”',
        'cliCount': '0',
        'cliTrend': 'â€”',
      };
    }

    try {
      DateTime now = DateTime.now();
      DateTime seventyTwoHoursAgo = now.subtract(const Duration(hours: 72));

      // Commandes
      final cmds = await database.query('Commandes');
      int cmdRecent = 0;
      for (var row in cmds) {
        if (row['created_at'] != null) {
          try {
            DateTime dt = DateTime.parse(row['created_at'].toString());
            if (dt.isAfter(seventyTwoHoursAgo) ||
                dt.isAtSameMomentAs(seventyTwoHoursAgo)) {
              cmdRecent++;
            }
          } catch (_) {}
        }
      }

      String cmdTrend = 'â€”';
      if (cmdRecent > 0) {
        cmdTrend = '+$cmdRecent (new)';
      }

      // Clients
      final clis = await database.query('Client');
      int cliRecent = 0;
      for (var row in clis) {
        if (row['created_at'] != null) {
          try {
            DateTime dt = DateTime.parse(row['created_at'].toString());
            if (dt.isAfter(seventyTwoHoursAgo) ||
                dt.isAtSameMomentAs(seventyTwoHoursAgo)) {
              cliRecent++;
            }
          } catch (_) {}
        }
      }

      String cliTrend = 'â€”';
      if (cliRecent > 0) {
        cliTrend = '+$cliRecent (new_client)';
      }

      return {
        'cmdCount': cmds.length.toString(),
        'cmdTrend': cmdTrend,
        'cliCount': clis.length.toString(),
        'cliTrend': cliTrend,
      };
    } catch (e) {
      print("Error getting stats: $e");
      return {
        'cmdCount': '0',
        'cmdTrend': 'â€”',
        'cliCount': '0',
        'cliTrend': 'â€”',
      };
    }
  }

  /// Returns order counts grouped by status, plus last-6-months monthly totals.
  Future<Map<String, dynamic>> getOrderStatusStats() async {
    final database = await db;
    if (database == null) {
      return {'byStatus': <String, int>{}, 'monthly': <String, int>{}};
    }
    try {
      final rows = await database.query('Commandes');

      // â”€â”€ Ø­Ø³Ø¨ Ø§Ù„Ø­Ø§Ù„Ø© â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
      final Map<String, int> byStatus = {};
      // â”€â”€ Ø¢Ø®Ø± 6 Ø£Ø´Ù‡Ø± â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
      final Map<String, int> monthly = {};
      final now = DateTime.now();
      for (int i = 5; i >= 0; i--) {
        final m = DateTime(now.year, now.month - i, 1);
        final key = '${m.month}/${m.year}';
        monthly[key] = 0;
      }

      for (final row in rows) {
        // Ø­Ø³Ø¨ Ø§Ù„Ø­Ø§Ù„Ø©
        final status = (row['status'] as String?) ?? 'Unknown';
        byStatus[status] = (byStatus[status] ?? 0) + 1;

        // Ø­Ø³Ø¨ Ø§Ù„Ø´Ù‡Ø±
        if (row['created_at'] != null) {
          try {
            final dt = DateTime.parse(row['created_at'].toString());
            final key = '${dt.month}/${dt.year}';
            if (monthly.containsKey(key)) {
              monthly[key] = monthly[key]! + 1;
            }
          } catch (_) {}
        }
      }

      return {'byStatus': byStatus, 'monthly': monthly};
    } catch (e) {
      debugPrint('getOrderStatusStats error: $e');
      return {'byStatus': <String, int>{}, 'monthly': <String, int>{}};
    }
  }

  Future<Map<String, List<String>>> getShutterOptions() async {
    Database? myDb = await db;
    if (myDb == null) return {'lames': [], 'glissieres': []};

    // Query from ShutterComponents (where Lame/Glissiere/blade/track data actually lives)
    final items = await myDb.query(
      'ShutterComponents',
      where:
          "component_type IN ('Lame', 'Glissiere', 'blade', 'track') AND (is_active = 1 OR is_active IS NULL)",
    );

    List<String> lames = [];
    List<String> glissieres = [];

    for (var item in items) {
      final compType = item['component_type']?.toString() ?? '';
      final name = _cleanEncoding(item['name'].toString());
      if (compType == 'Lame' || compType == 'blade') {
        if (!lames.contains(name)) lames.add(name);
      } else if (compType == 'Glissiere' || compType == 'track') {
        if (!glissieres.contains(name)) glissieres.add(name);
      }
    }

    // Also check Accessories table for any Lame/Glissiere/blade/track entries
    try {
      final accItems = await myDb.query(
        'Accessories',
        where:
            "type IN ('Lame', 'Glissiere', 'blade', 'track') AND (is_active = 1 OR is_active IS NULL)",
      );
      for (var item in accItems) {
        final name = _cleanEncoding(item['name'].toString());
        final type = item['type']?.toString() ?? '';
        if ((type == 'Lame' || type == 'blade') && !lames.contains(name)) {
          lames.add(name);
        } else if ((type == 'Glissiere' || type == 'track') &&
            !glissieres.contains(name)) {
          glissieres.add(name);
        }
      }
    } catch (_) {}

    if (lames.isEmpty) lames = ['Lame InjectÃ©e', 'Lame ExtrudÃ©e'];
    if (glissieres.isEmpty)
      glissieres = ['GlissiÃ¨re 25', 'GlissiÃ¨re 120', 'GlissiÃ¨re 100'];

    return {'lames': lames, 'glissieres': glissieres};
  }

  Future<void> _ensureRemnantInventorySchema(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS InventorySettings (
        id INTEGER PRIMARY KEY,
        setting_key TEXT NOT NULL UNIQUE,
        numeric_value REAL,
        text_value TEXT,
        updated_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS OrderCuttingSessions (
        id INTEGER PRIMARY KEY,
        order_id INTEGER NOT NULL UNIQUE,
        plan_signature TEXT NOT NULL,
        minimum_reusable_length_mm REAL NOT NULL,
        location_id INTEGER NOT NULL,
        rack_code TEXT,
        shelf_code TEXT,
        bin_code TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS MaterialRemnants (
        id INTEGER PRIMARY KEY,
        ticket_code TEXT NOT NULL UNIQUE,
        item_id INTEGER NOT NULL,
        item_type TEXT NOT NULL,
        series_id INTEGER,
        color_id INTEGER,
        length_mm REAL NOT NULL,
        source_order_id INTEGER,
        source_bar_index INTEGER,
        location_id INTEGER NOT NULL,
        rack_code TEXT,
        shelf_code TEXT,
        bin_code TEXT,
        status TEXT NOT NULL DEFAULT 'available',
        reserved_order_id INTEGER,
        reserved_at TEXT,
        consumed_order_id INTEGER,
        consumed_at TEXT,
        note TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS MaterialScrap (
        id INTEGER PRIMARY KEY,
        ticket_code TEXT NOT NULL UNIQUE,
        item_id INTEGER NOT NULL,
        item_type TEXT NOT NULL,
        series_id INTEGER,
        color_id INTEGER,
        length_mm REAL NOT NULL,
        scrap_kind TEXT NOT NULL DEFAULT 'short_offcut',
        source_order_id INTEGER,
        source_bar_index INTEGER,
        location_id INTEGER NOT NULL,
        rack_code TEXT,
        shelf_code TEXT,
        bin_code TEXT,
        note TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_material_remnants_match '
      'ON MaterialRemnants(item_type, item_id, color_id, series_id, status, length_mm)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_material_scrap_source '
      'ON MaterialScrap(source_order_id, item_type, item_id)',
    );
  }

  Future<void> _ensureInventoryAlertSchema(DatabaseExecutor db) async {
    try {
      await db.execute(
        'ALTER TABLE CurrentStock ADD COLUMN low_stock_alert_enabled INTEGER NOT NULL DEFAULT 0;',
      );
    } catch (_) {}
  }

  Future<void> _ensureOrderInventoryIssueSchema(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS OrderInventoryIssueSessions (
        id INTEGER PRIMARY KEY,
        order_id INTEGER NOT NULL UNIQUE,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
  }

  Future<double?> readMinimumReusableLengthMm() async {
    final myDb = await db;
    if (myDb == null) return null;
    await _ensureRemnantInventorySchema(myDb);
    final rows = await myDb.query(
      'InventorySettings',
      columns: const ['numeric_value'],
      where: 'setting_key = ?',
      whereArgs: const ['minimum_reusable_length_mm'],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final value = _readStoredNumber(rows.first['numeric_value']);
    return value != null && value > 0 ? value : null;
  }

  Future<void> saveMinimumReusableLengthMm(double lengthMm) async {
    if (lengthMm <= 0) {
      throw ArgumentError.value(lengthMm, 'lengthMm', 'Must be positive');
    }
    final myDb = await db;
    if (myDb == null) return;
    await _ensureRemnantInventorySchema(myDb);
    final rows = await myDb.query(
      'InventorySettings',
      columns: const ['id'],
      where: 'setting_key = ?',
      whereArgs: const ['minimum_reusable_length_mm'],
      limit: 1,
    );
    final values = {
      'numeric_value': lengthMm,
      'updated_at': DateTime.now().toIso8601String(),
    };
    if (rows.isEmpty) {
      await myDb.insert(
        'InventorySettings',
        _withDistributedId({
          'setting_key': 'minimum_reusable_length_mm',
          ...values,
        }),
      );
    } else {
      await myDb.update(
        'InventorySettings',
        values,
        where: 'id = ?',
        whereArgs: [rows.first['id']],
      );
    }
    CloudSyncService().notifyChange();
  }

  String _materialTicketCode(String prefix, int orderId, int barIndex, int id) {
    final suffix = id.toString();
    return '$prefix-$orderId-${barIndex + 1}-${suffix.substring(max(0, suffix.length - 7))}';
  }

  /// Persists the physical result of an approved cutting plan exactly once.
  /// Each map needs item_id, item_type, color_id, series_id, bar_index,
  /// remainder_mm and kerf_loss_mm.
  Future<Map<String, dynamic>> saveOrderCuttingRemainders({
    required int orderId,
    required String planSignature,
    required List<Map<String, dynamic>> bars,
    required double minimumReusableLengthMm,
    required int locationId,
    String? rackCode,
    String? shelfCode,
    String? binCode,
  }) async {
    if (minimumReusableLengthMm <= 0) {
      throw ArgumentError('Minimum reusable length must be positive.');
    }
    final myDb = await db;
    if (myDb == null) return const {'saved': false};
    await _ensureRemnantInventorySchema(myDb);
    final createdRemnants = <Map<String, dynamic>>[];
    var scrapRows = 0;
    var alreadySaved = false;

    await myDb.transaction((txn) async {
      final existing = await txn.query(
        'OrderCuttingSessions',
        columns: const ['id', 'plan_signature'],
        where: 'order_id = ?',
        whereArgs: [orderId],
        limit: 1,
      );
      if (existing.isNotEmpty) {
        alreadySaved = true;
        return;
      }

      final timestamp = DateTime.now().toIso8601String();
      await txn.insert(
        'OrderCuttingSessions',
        _withDistributedId({
          'order_id': orderId,
          'plan_signature': planSignature,
          'minimum_reusable_length_mm': minimumReusableLengthMm,
          'location_id': locationId,
          'rack_code': rackCode?.trim(),
          'shelf_code': shelfCode?.trim(),
          'bin_code': binCode?.trim(),
          'created_at': timestamp,
          'updated_at': timestamp,
        }),
      );

      for (final bar in bars) {
        final itemId = (bar['item_id'] as num?)?.toInt();
        final itemType = bar['item_type']?.toString().trim() ?? '';
        final barIndex = (bar['bar_index'] as num?)?.toInt() ?? 0;
        final remainderMm = _readStoredNumber(bar['remainder_mm']) ?? 0;
        final kerfLossMm = _readStoredNumber(bar['kerf_loss_mm']) ?? 0;
        if (itemId == null || itemType.isEmpty) continue;

        final common = <String, dynamic>{
          'item_id': itemId,
          'item_type': itemType,
          'series_id': (bar['series_id'] as num?)?.toInt(),
          'color_id': (bar['color_id'] as num?)?.toInt(),
          'source_order_id': orderId,
          'source_bar_index': barIndex,
          'location_id': locationId,
          'rack_code': rackCode?.trim(),
          'shelf_code': shelfCode?.trim(),
          'bin_code': binCode?.trim(),
          'created_at': timestamp,
          'updated_at': timestamp,
        };

        if (remainderMm > 0.5) {
          final reusable = remainderMm + 0.01 >= minimumReusableLengthMm;
          final id = _nextDistributedId();
          final ticket = _materialTicketCode(
            reusable ? 'REM' : 'SCR',
            orderId,
            barIndex,
            id,
          );
          if (reusable) {
            final row = {
              'id': id,
              'ticket_code': ticket,
              ...common,
              'length_mm': remainderMm,
              'status': 'available',
            };
            await txn.insert('MaterialRemnants', row);
            createdRemnants.add(row);
          } else {
            await txn.insert('MaterialScrap', {
              'id': id,
              'ticket_code': ticket,
              ...common,
              'length_mm': remainderMm,
              'scrap_kind': 'short_offcut',
            });
            scrapRows++;
          }
        }

        if (kerfLossMm > 0.5) {
          final id = _nextDistributedId();
          await txn.insert('MaterialScrap', {
            'id': id,
            'ticket_code': _materialTicketCode('KERF', orderId, barIndex, id),
            ...common,
            'length_mm': kerfLossMm,
            'scrap_kind': 'saw_kerf',
          });
          scrapRows++;
        }
      }
    });
    if (!alreadySaved) CloudSyncService().notifyChange();
    return {
      'saved': !alreadySaved,
      'already_saved': alreadySaved,
      'remnants': createdRemnants,
      'scrap_count': scrapRows,
    };
  }

  Future<List<Map<String, dynamic>>> readAvailableMaterialRemnants({
    required int itemId,
    required String itemType,
    int? colorId,
    int? seriesId,
  }) async {
    final myDb = await db;
    if (myDb == null) return [];
    await _ensureRemnantInventorySchema(myDb);
    final where = StringBuffer(
      'r.item_id = ? AND r.item_type = ? AND r.status = ? '
      'AND (r.color_id = ? OR (r.color_id IS NULL AND ? IS NULL))',
    );
    final args = <Object?>[itemId, itemType, 'available', colorId, colorId];
    if (seriesId != null) {
      where.write(' AND (r.series_id = ? OR r.series_id IS NULL)');
      args.add(seriesId);
    }
    return myDb.rawQuery('''
      SELECT r.*, l.name AS location_name, c.name AS color_name,
             se.name AS series_name,
             COALESCE(s.name, sc.name, a.name, j.name, g.name) AS item_name,
             s.code AS item_code
      FROM MaterialRemnants r
      LEFT JOIN Locations l ON l.id = r.location_id
      LEFT JOIN Colors c ON c.id = r.color_id
      LEFT JOIN Sections s ON r.item_type = 'Section' AND s.id = r.item_id
      LEFT JOIN Series se ON se.id = COALESCE(r.series_id, s.series_id)
      LEFT JOIN ShutterComponents sc
        ON r.item_type = 'ShutterComponent' AND sc.id = r.item_id
      LEFT JOIN Accessories a ON r.item_type = 'Accessory' AND a.id = r.item_id
      LEFT JOIN Joints j ON r.item_type = 'Joints' AND j.id = r.item_id
      LEFT JOIN Glass g ON r.item_type = 'Glass' AND g.id = r.item_id
      WHERE $where
      ORDER BY r.length_mm ASC, r.created_at ASC
      ''', args);
  }

  Future<List<Map<String, dynamic>>> readAllAvailableMaterialRemnants({
    int? locationId,
  }) async {
    final myDb = await db;
    if (myDb == null) return [];
    await _ensureRemnantInventorySchema(myDb);
    final where = StringBuffer('r.status = ?');
    final args = <Object?>['available'];
    if (locationId != null) {
      where.write(' AND r.location_id = ?');
      args.add(locationId);
    }
    return myDb.rawQuery('''
      SELECT r.*, l.name AS location_name, c.name AS color_name,
             se.name AS series_name,
             COALESCE(s.name, sc.name, a.name, j.name, g.name) AS item_name,
             COALESCE(s.code, '') AS item_code
      FROM MaterialRemnants r
      LEFT JOIN Locations l ON l.id = r.location_id
      LEFT JOIN Colors c ON c.id = r.color_id
      LEFT JOIN Sections s ON r.item_type = 'Section' AND s.id = r.item_id
      LEFT JOIN Series se ON se.id = COALESCE(r.series_id, s.series_id)
      LEFT JOIN ShutterComponents sc
        ON r.item_type = 'ShutterComponent' AND sc.id = r.item_id
      LEFT JOIN Accessories a ON r.item_type = 'Accessory' AND a.id = r.item_id
      LEFT JOIN Joints j ON r.item_type = 'Joints' AND j.id = r.item_id
      LEFT JOIN Glass g ON r.item_type = 'Glass' AND g.id = r.item_id
      WHERE $where
      ORDER BY r.location_id ASC, r.item_type ASC, item_name ASC,
               r.length_mm DESC, r.created_at ASC
      ''', args);
  }

  Future<Map<String, dynamic>> applyOrderInventoryIssue({
    required int orderId,
    required List<int> remnantIds,
    required List<Map<String, dynamic>> stockDeductions,
  }) async {
    final myDb = await db;
    if (myDb == null) return const {'applied': false};
    await _ensureRemnantInventorySchema(myDb);
    await _ensureOrderInventoryIssueSchema(myDb);
    final uniqueRemnantIds = remnantIds.toSet().toList();
    var consumedRemnants = 0;
    var deductedRows = 0;
    var alreadyApplied = false;

    await myDb.transaction((txn) async {
      final existing = await txn.query(
        'OrderInventoryIssueSessions',
        columns: const ['id'],
        where: 'order_id = ?',
        whereArgs: [orderId],
        limit: 1,
      );
      if (existing.isNotEmpty) {
        alreadyApplied = true;
        return;
      }

      final timestamp = DateTime.now().toIso8601String();
      await txn.insert(
        'OrderInventoryIssueSessions',
        _withDistributedId({
          'order_id': orderId,
          'created_at': timestamp,
          'updated_at': timestamp,
        }),
      );

      for (final id in uniqueRemnantIds) {
        consumedRemnants += await txn.update(
          'MaterialRemnants',
          {
            'status': 'consumed',
            'consumed_order_id': orderId,
            'consumed_at': timestamp,
            'updated_at': timestamp,
          },
          where: 'id = ? AND status = ?',
          whereArgs: [id, 'available'],
        );
      }

      for (final row in stockDeductions) {
        final itemId = (row['item_id'] as num?)?.toInt();
        final itemType = row['item_type']?.toString();
        final locationId = (row['location_id'] as num?)?.toInt();
        final quantity = _readStoredNumber(row['quantity']) ?? 0;
        if (itemId == null ||
            itemType == null ||
            itemType.trim().isEmpty ||
            locationId == null ||
            quantity <= 0) {
          continue;
        }
        final colorId = (row['color_id'] as num?)?.toInt();
        final where = colorId == null
            ? 'item_id = ? AND item_type = ? AND color_id IS NULL AND location_id = ?'
            : 'item_id = ? AND item_type = ? AND color_id = ? AND location_id = ?';
        final whereArgs = colorId == null
            ? <Object?>[itemId, itemType, locationId]
            : <Object?>[itemId, itemType, colorId, locationId];
        final stockRows = await txn.query(
          'CurrentStock',
          columns: const ['quantity'],
          where: where,
          whereArgs: whereArgs,
          limit: 1,
        );
        if (stockRows.isEmpty) continue;
        final current = _readStoredNumber(stockRows.first['quantity']) ?? 0;
        final next = max(0.0, current - quantity);
        deductedRows += await txn.update(
          'CurrentStock',
          {'quantity': next, 'updated_at': timestamp},
          where: where,
          whereArgs: whereArgs,
        );
        await txn.insert(
          'InventoryTransactions',
          _withDistributedId({
            'item_id': itemId,
            'item_type': itemType,
            'color_id': colorId,
            'location_id': locationId,
            'quantity': -quantity,
            'transaction_type': 'order_issue',
            'reference_id': orderId,
            'note': 'صرف تلقائي للطلبية #$orderId',
            'created_at': timestamp,
          }),
        );
      }
    });

    if (!alreadyApplied) CloudSyncService().notifyChange();
    return {
      'applied': !alreadyApplied,
      'already_applied': alreadyApplied,
      'consumed_remnants': consumedRemnants,
      'deducted_rows': deductedRows,
    };
  }

  Future<List<Map<String, dynamic>>> readStockAvailability({
    required int itemId,
    required String itemType,
    int? colorId,
  }) async {
    final myDb = await db;
    if (myDb == null) return [];
    return myDb.rawQuery(
      '''
      SELECT cs.*, l.name AS location_name
      FROM CurrentStock cs
      LEFT JOIN Locations l ON l.id = cs.location_id
      WHERE cs.item_id = ? AND cs.item_type = ?
        AND (cs.color_id = ? OR (cs.color_id IS NULL AND ? IS NULL))
        AND cs.quantity > 0
      ORDER BY cs.quantity DESC, cs.location_id ASC
      ''',
      [itemId, itemType, colorId, colorId],
    );
  }

  Future<List<Map<String, dynamic>>> readMaterialRemnantsForOrder(
    int orderId,
  ) async {
    final myDb = await db;
    if (myDb == null) return [];
    await _ensureRemnantInventorySchema(myDb);
    return myDb.rawQuery(
      '''
      SELECT r.*, l.name AS location_name, c.name AS color_name,
             se.name AS series_name, s.name AS item_name, s.code AS item_code
      FROM MaterialRemnants r
      LEFT JOIN Locations l ON l.id = r.location_id
      LEFT JOIN Colors c ON c.id = r.color_id
      LEFT JOIN Sections s ON r.item_type = 'Section' AND s.id = r.item_id
      LEFT JOIN Series se ON se.id = COALESCE(r.series_id, s.series_id)
      WHERE r.source_order_id = ?
      ORDER BY r.source_bar_index ASC
      ''',
      [orderId],
    );
  }

  // ==================== INVENTORY MANAGEMENT ====================
  Future<List<Map<String, dynamic>>> readLocations() async {
    Database? myDb = await db;
    List<Map<String, dynamic>> locations = [];
    try {
      locations = await myDb!.query('Locations', orderBy: 'id ASC');
    } catch (e) {
      // Table might not exist if the upgrade script failed or was skipped
      await myDb!.execute('''
        CREATE TABLE IF NOT EXISTS Locations (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          type TEXT NOT NULL,
          is_active INTEGER NOT NULL DEFAULT 1,
          created_at TEXT NOT NULL DEFAULT (datetime('now'))
        )
      ''');
    }

    if (locations.isEmpty) {
      await myDb.insert(
        'Locations',
        _withDistributedId({
          'name':
              'â•ªÂºâ”˜Ã¤â”˜Ã â•ªÂ«â•ªâ–“â”˜Ã¥ â•ªÂºâ”˜Ã¤â•ªâ–’â•ªÂªâ”˜Ã¨â•ªâ”‚â”˜Ã¨',
          'type':
              'â”˜Ã â•ªâ”‚â•ªÂ¬â”˜Ãªâ•ªÂ»â•ªâ•£ â•ªâ–’â•ªÂªâ”˜Ã¨â•ªâ”‚â”˜Ã¨',
          'is_active': 1,
        }),
      );
      locations = await myDb.query('Locations', orderBy: 'id ASC');
      CloudSyncService().notifyChange();
    }
    for (final location in locations) {
      final name = location['name']?.toString() ?? '';
      final type = location['type']?.toString() ?? '';
      final hasBrokenEncoding =
          name.contains('Ã˜') ||
          name.contains('Ã™') ||
          name.contains('Ã¢') ||
          name.contains('â•ª') ||
          name.contains('â”˜') ||
          type.contains('Ã˜') ||
          type.contains('Ã™') ||
          type.contains('Ã¢') ||
          type.contains('â•ª') ||
          type.contains('â”˜');
      if (hasBrokenEncoding) {
        await myDb.update(
          'Locations',
          {
            'name': 'Ø§Ù„Ù…Ø³ØªÙˆØ¯Ø¹ Ø§Ù„Ø±Ø¦ÙŠØ³ÙŠ',
            'type': 'Ù…Ø³ØªÙˆØ¯Ø¹ Ø±Ø¦ÙŠØ³ÙŠ',
          },
          where: 'id = ?',
          whereArgs: [location['id']],
        );
      }
    }
    locations = await myDb.query('Locations', orderBy: 'id ASC');
    return locations;
  }

  Future<int> updateMinQty({
    required String itemType,
    required int itemId,
    int? colorId,
    required int locationId,
    required double minQty,
    required bool alertEnabled,
  }) async {
    Database? myDb = await db;
    if (myDb == null) return 0;
    await _ensureInventoryAlertSchema(myDb);

    final stock = await myDb.query(
      'CurrentStock',
      where:
          'item_type = ? AND item_id = ? AND (color_id = ? OR (color_id IS NULL AND ? IS NULL)) AND location_id = ?',
      whereArgs: [itemType, itemId, colorId, colorId, locationId],
    );

    int res;
    if (stock.isEmpty) {
      res = await myDb.insert(
        'CurrentStock',
        _withDistributedId({
          'item_type': itemType,
          'item_id': itemId,
          'color_id': colorId,
          'location_id': locationId,
          'quantity': 0.0,
          'min_qty': minQty,
          'low_stock_alert_enabled': alertEnabled ? 1 : 0,
          'updated_at': DateTime.now().toIso8601String(),
        }),
      );
    } else {
      res = await myDb.update(
        'CurrentStock',
        {
          'min_qty': minQty,
          'low_stock_alert_enabled': alertEnabled ? 1 : 0,
          'updated_at': DateTime.now().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [stock.first['id']],
      );
    }
    CloudSyncService().notifyChange();
    return res;
  }

  Future<void> updateInventory({
    required int itemId,
    required String itemType,
    int? colorId,
    required int locationId,
    required double quantityChange,
    required String transactionType,
    int? referenceId,
  }) async {
    Database? myDb = await db;
    if (myDb == null) return;

    await myDb.transaction((txn) async {
      // 1. Record the transaction
      await txn.insert(
        'InventoryTransactions',
        _withDistributedId({
          'item_id': itemId,
          'item_type': itemType,
          'color_id': colorId,
          'location_id': locationId,
          'quantity': quantityChange,
          'transaction_type': transactionType,
          'reference_id': referenceId,
          'created_at': DateTime.now().toIso8601String(),
        }),
      );

      // 2. Update current stock
      final String where;
      final List<Object?> whereArgs;

      if (colorId == null) {
        where =
            'item_id = ? AND item_type = ? AND color_id IS NULL AND location_id = ?';
        whereArgs = [itemId, itemType, locationId];
      } else {
        where =
            'item_id = ? AND item_type = ? AND color_id = ? AND location_id = ?';
        whereArgs = [itemId, itemType, colorId, locationId];
      }

      final stockRows = await txn.query(
        'CurrentStock',
        where: where,
        whereArgs: whereArgs,
      );

      if (stockRows.isNotEmpty) {
        double currentQty = (stockRows.first['quantity'] as num).toDouble();
        double newQty = currentQty + quantityChange;
        await txn.update(
          'CurrentStock',
          {'quantity': newQty, 'updated_at': DateTime.now().toIso8601String()},
          where: where,
          whereArgs: whereArgs,
        );
      } else {
        await txn.insert(
          'CurrentStock',
          _withDistributedId({
            'item_id': itemId,
            'item_type': itemType,
            'color_id': colorId,
            'location_id': locationId,
            'quantity': quantityChange,
            'updated_at': DateTime.now().toIso8601String(),
          }),
        );
      }
    });
    CloudSyncService().notifyChange();
  }

  Future<List<Map<String, dynamic>>> readAllPossibleStock(
    int locationId,
  ) async {
    Database? myDb = await db;
    if (myDb == null) return [];
    await _ensureInventoryAlertSchema(myDb);

    // 1. Fetch current stock for fast lookup
    final stock = await myDb.query(
      'CurrentStock',
      where: 'location_id = ?',
      whereArgs: [locationId],
    );

    Map<String, double> stockMap = {};
    Map<String, double> minQtyMap = {};
    Map<String, bool> alertMap = {};
    for (var row in stock) {
      String key =
          '${row['item_type']}_${row['item_id']}_${row['color_id'] ?? 0}';
      stockMap[key] = (row['quantity'] as num).toDouble();
      minQtyMap[key] = (row['min_qty'] as num?)?.toDouble() ?? 0.0;
      alertMap[key] =
          ((row['low_stock_alert_enabled'] as num?)?.toInt() ?? 0) == 1;
    }

    List<Map<String, dynamic>> allItems = [];

    // Colors cache
    final colors = await myDb.query('Colors');
    Map<int, String> colorMap = {
      for (var row in colors) row['id'] as int: row['name'].toString(),
    };

    // 2. Sections
    final sections = await myDb.query('Sections');
    final sectionColors = await myDb.query('SectionColorPrices');
    Map<int, List<int>> sectionColorMap = {};
    for (var row in sectionColors) {
      int sId = row['section_id'] as int;
      int cId = row['color_id'] as int;
      sectionColorMap.putIfAbsent(sId, () => []).add(cId);
    }
    for (var row in sections) {
      int id = row['id'] as int;
      String name = row['name'].toString();
      List<int> cIds = sectionColorMap[id] ?? [];
      if (cIds.isEmpty) cIds = [0]; // default no color

      for (int cId in cIds) {
        String key = 'Section_${id}_$cId';
        double qty = stockMap[key] ?? 0.0;
        String cName = cId == 0 ? '' : (colorMap[cId] ?? '');
        allItems.add({
          'item_type': 'Section',
          'item_id': id,
          'item_name': name,
          'color_id': cId == 0 ? null : cId,
          'color_name': cName,
          'quantity': qty,
        });
      }
    }

    // 3. Accessories
    final accessories = await myDb.query('Accessories');
    final accessoryColors = await myDb.query('AccessoryColorPrices');
    Map<int, List<int>> accessoryColorMap = {};
    for (var row in accessoryColors) {
      int aId = row['accessory_id'] as int;
      int cId = row['color_id'] as int;
      accessoryColorMap.putIfAbsent(aId, () => []).add(cId);
    }
    for (var row in accessories) {
      int id = row['id'] as int;
      String name = row['name'].toString();
      List<int> cIds = accessoryColorMap[id] ?? [];
      if (cIds.isEmpty) cIds = [0];

      for (int cId in cIds) {
        String key = 'Accessory_${id}_$cId';
        double qty = stockMap[key] ?? 0.0;
        String cName = cId == 0 ? '' : (colorMap[cId] ?? '');
        allItems.add({
          'item_type': 'Accessory',
          'item_id': id,
          'item_name': name,
          'color_id': cId == 0 ? null : cId,
          'color_name': cName,
          'quantity': qty,
        });
      }
    }

    // 4. Glass
    final glass = await myDb.query('Glass');
    for (var row in glass) {
      int id = row['id'] as int;
      String name = row['name'].toString();
      String key = 'Glass_${id}_0';
      double qty = stockMap[key] ?? 0.0;
      allItems.add({
        'item_type': 'Glass',
        'item_id': id,
        'item_name': name,
        'color_id': null,
        'color_name': '',
        'quantity': qty,
      });
    }

    // 5. ShutterComponents
    final shutter = await myDb.query('ShutterComponents');
    final shutterColors = await myDb.query('ShutterColorPrices');
    Map<int, List<int>> shutterColorMap = {};
    for (var row in shutterColors) {
      int sId = row['shutter_component_id'] as int;
      int cId = row['color_id'] as int;
      shutterColorMap.putIfAbsent(sId, () => []).add(cId);
    }
    for (var row in shutter) {
      int id = row['id'] as int;
      String name = row['name'].toString();
      List<int> cIds = shutterColorMap[id] ?? [];
      if (cIds.isEmpty) cIds = [0];

      for (int cId in cIds) {
        String key = 'ShutterComponent_${id}_$cId';
        double qty = stockMap[key] ?? 0.0;
        String cName = cId == 0 ? '' : (colorMap[cId] ?? '');
        allItems.add({
          'item_type': 'ShutterComponent',
          'item_id': id,
          'item_name': name,
          'color_id': cId == 0 ? null : cId,
          'color_name': cName,
          'quantity': qty,
        });
      }
    }

    // 6. Joints
    final joints = await myDb.query('Joints');
    for (var row in joints) {
      int id = row['id'] as int;
      String name = row['name'].toString();
      String key = 'Joints_${id}_0';
      double qty = stockMap[key] ?? 0.0;
      allItems.add({
        'item_type': 'Joints',
        'item_id': id,
        'item_name': name,
        'color_id': null,
        'color_name': '',
        'quantity': qty,
      });
    }

    // Add any remaining items from CurrentStock that weren't in the catalogs
    for (var row in stock) {
      String type = row['item_type'].toString();
      if (type == 'Profile') type = 'Section';
      if (type == 'Accessories') type = 'Accessory';
      if (type == 'Shutter Components') type = 'ShutterComponent';

      int id = row['item_id'] as int;
      int cId = (row['color_id'] as int?) ?? 0;
      // String key = '${type}_${id}_${cId}';

      bool found = allItems.any((item) {
        return item['item_type'] == type &&
            item['item_id'] == id &&
            (item['color_id'] ?? 0) == cId;
      });

      if (!found) {
        String itemName = 'Unknown';
        String cName = cId == 0 ? '' : (colorMap[cId] ?? '');

        if (type == 'Section') {
          final r = await myDb.query(
            'Sections',
            where: 'id = ?',
            whereArgs: [id],
          );
          if (r.isNotEmpty) itemName = r.first['name'].toString();
        } else if (type == 'Accessory') {
          final r = await myDb.query(
            'Accessories',
            where: 'id = ?',
            whereArgs: [id],
          );
          if (r.isNotEmpty) itemName = r.first['name'].toString();
        } else if (type == 'Glass') {
          final r = await myDb.query('Glass', where: 'id = ?', whereArgs: [id]);
          if (r.isNotEmpty) itemName = r.first['name'].toString();
        } else if (type == 'ShutterComponent') {
          final r = await myDb.query(
            'ShutterComponents',
            where: 'id = ?',
            whereArgs: [id],
          );
          if (r.isNotEmpty) itemName = r.first['name'].toString();
        } else if (type == 'Joints') {
          final r = await myDb.query(
            'Joints',
            where: 'id = ?',
            whereArgs: [id],
          );
          if (r.isNotEmpty) itemName = r.first['name'].toString();
        }

        allItems.add({
          'item_type': type,
          'item_id': id,
          'item_name': itemName,
          'color_id': cId == 0 ? null : cId,
          'color_name': cName,
          'quantity': (row['quantity'] as num).toDouble(),
        });
      }
    }

    for (var item in allItems) {
      final type = item['item_type'] as String;
      final id = item['item_id'] as int;
      final cId = item['color_id'] as int? ?? 0;
      final key = '${type}_${id}_$cId';
      item['min_qty'] = minQtyMap[key] ?? 0.0;
      item['low_stock_alert_enabled'] = alertMap[key] == true ? 1 : 0;
    }

    return allItems;
  }

  Future<List<Map<String, dynamic>>> readCurrentStock(int locationId) async {
    Database? myDb = await db;
    if (myDb == null) return [];
    await _ensureInventoryAlertSchema(myDb);

    final stock = await myDb.query(
      'CurrentStock',
      where: 'location_id = ? AND quantity != 0',
      whereArgs: [locationId],
    );
    List<Map<String, dynamic>> enrichedStock = [];
    Map<String, Map<String, dynamic>> groupedStock = {};

    for (var row in stock) {
      final itemType = row['item_type'] as String;
      final itemId = row['item_id'] as int;
      final colorId = row['color_id'] as int?;

      String itemName = 'â”˜Ã â•ªÂ¼â”˜Ã§â”˜Ãªâ”˜Ã¤';
      String colorName = '';

      if (colorId != null) {
        final colorRow = await myDb.query(
          'Colors',
          columns: ['name'],
          where: 'id = ?',
          whereArgs: [colorId],
        );
        if (colorRow.isNotEmpty) colorName = colorRow.first['name'].toString();
      }

      if (itemType == 'Profile') {
        final itemRow = await myDb.query(
          'Profile',
          columns: ['name'],
          where: 'id = ?',
          whereArgs: [itemId],
        );
        if (itemRow.isNotEmpty) itemName = itemRow.first['name'].toString();
      } else if (itemType == 'Accessory' || itemType == 'Accessories') {
        final itemRow = await myDb.query(
          'Accessories',
          columns: ['name'],
          where: 'id = ?',
          whereArgs: [itemId],
        );
        if (itemRow.isNotEmpty) itemName = itemRow.first['name'].toString();
      } else if (itemType == 'Glass') {
        final itemRow = await myDb.query(
          'Glass',
          columns: ['name'],
          where: 'id = ?',
          whereArgs: [itemId],
        );
        if (itemRow.isNotEmpty) itemName = itemRow.first['name'].toString();
      } else if (itemType == 'Shutter Component' ||
          itemType == 'ShutterComponents') {
        final itemRow = await myDb.query(
          'ShutterComponents',
          columns: ['name'],
          where: 'id = ?',
          whereArgs: [itemId],
        );
        if (itemRow.isNotEmpty) itemName = itemRow.first['name'].toString();
      } else if (itemType == 'Lame' ||
          itemType == 'Glissiere' ||
          itemType == 'Axe' ||
          itemType == 'Caisson') {
        final itemRow = await myDb.query(
          'ShutterComponents',
          columns: ['name'],
          where: 'id = ?',
          whereArgs: [itemId],
        );
        if (itemRow.isNotEmpty) itemName = itemRow.first['name'].toString();
      } else if (itemType == 'Sections' || itemType == 'Section') {
        final itemRow = await myDb.rawQuery(
          '''
          SELECT sec.name as section_name, sec.code as section_code, ser.name as series_name, p.name as profile_name
          FROM Sections sec
          LEFT JOIN Series ser ON sec.series_id = ser.id
          LEFT JOIN Profile p ON ser.profile_id = p.id
          WHERE sec.id = ?
        ''',
          [itemId],
        );
        if (itemRow.isNotEmpty) {
          final sName = itemRow.first['section_name']?.toString() ?? '';
          final sCode = itemRow.first['section_code']?.toString() ?? '';
          final serName = itemRow.first['series_name']?.toString() ?? '';
          final pName = itemRow.first['profile_name']?.toString() ?? '';
          // Format: ProfileName - SeriesName - [Code] SectionName
          final codeStr = sCode.isNotEmpty ? '[$sCode] ' : '';
          final parts = [pName, serName].where((s) => s.isNotEmpty).join(' - ');
          itemName = parts.isNotEmpty
              ? '$parts - $codeStr$sName'
              : '$codeStr$sName';
          if (itemName.trim().isEmpty) itemName = sName;
        }
      } else if (itemType == 'Joints' || itemType == 'Joint') {
        final itemRow = await myDb.query(
          'Joints',
          columns: ['name'],
          where: 'id = ?',
          whereArgs: [itemId],
        );
        if (itemRow.isNotEmpty) itemName = itemRow.first['name'].toString();
      }

      String key = '${itemName}_${colorName}_$itemType';
      if (groupedStock.containsKey(key)) {
        groupedStock[key]!['quantity'] += (row['quantity'] as num).toDouble();
        final rowAlert =
            ((row['low_stock_alert_enabled'] as num?)?.toInt() ?? 0) == 1;
        final existingAlert =
            ((groupedStock[key]!['low_stock_alert_enabled'] as num?)?.toInt() ??
                0) ==
            1;
        groupedStock[key]!['low_stock_alert_enabled'] =
            rowAlert || existingAlert ? 1 : 0;
      } else {
        groupedStock[key] = {
          ...row,
          'item_name': itemName,
          'color_name': colorName,
          'quantity': (row['quantity'] as num).toDouble(),
        };
      }
    }

    enrichedStock = groupedStock.values.toList();
    return enrichedStock;
  }

  Future<List<Map<String, dynamic>>> readInventoryTransactions({
    required int itemId,
    required String itemType,
    int? colorId,
    required int locationId,
  }) async {
    Database? myDb = await db;
    if (myDb == null) return [];

    final String where;
    final List<Object?> whereArgs;

    if (colorId == null) {
      where =
          'item_id = ? AND item_type = ? AND color_id IS NULL AND location_id = ?';
      whereArgs = [itemId, itemType, locationId];
    } else {
      where =
          'item_id = ? AND item_type = ? AND color_id = ? AND location_id = ?';
      whereArgs = [itemId, itemType, colorId, locationId];
    }

    return await myDb.query(
      'InventoryTransactions',
      where: where,
      whereArgs: whereArgs,
      orderBy: 'created_at DESC',
    );
  }

  Future<void> insertOrUpdateSafeLegacy(
    String table,
    Map<String, dynamic> rawData,
    String idColumn,
  ) async {
    final database = await db;
    if (database == null || !_isSafeSqlIdentifier(table)) return;

    try {
      final columns = await _tableColumns(database, table);
      final data = _sanitizeImportRow(Map<String, dynamic>.from(rawData))
        ..removeWhere((key, value) => !columns.contains(key));
      if (data.isEmpty) return;

      if (data.containsKey(idColumn) && data[idColumn] != null) {
        final existing = await database.query(
          table,
          where: '$idColumn = ?',
          whereArgs: [data[idColumn]],
        );
        if (existing.isNotEmpty) {
          await database.update(
            table,
            data,
            where: '$idColumn = ?',
            whereArgs: [data[idColumn]],
          );
          return;
        }
      }
      await database.insert(
        table,
        data,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (e) {
      print('Error in insertOrUpdateSafeLegacy: $e');
    }
  }

  Future<bool> hasLocalData() async {
    final database = await db;
    if (database == null) return false;

    try {
      final clientsCount =
          Sqflite.firstIntValue(
            await database.rawQuery('SELECT COUNT(*) FROM Client'),
          ) ??
          0;
      final cmdsCount =
          Sqflite.firstIntValue(
            await database.rawQuery('SELECT COUNT(*) FROM Commandes'),
          ) ??
          0;
      final achatsCount =
          Sqflite.firstIntValue(
            await database.rawQuery('SELECT COUNT(*) FROM Achats'),
          ) ??
          0;
      return (clientsCount > 0 || cmdsCount > 0 || achatsCount > 0);
    } catch (_) {
      return false;
    }
  }

  Future<List<Map<String, dynamic>>> getSectionsByType(
    String type, {
    int? seriesId,
  }) async {
    final database = await db;
    if (database == null) return [];

    String whereClause = 'type = ? AND (is_active = 1 OR is_active IS NULL)';
    List<dynamic> whereArgs = [type];

    if (seriesId != null) {
      whereClause += ' AND series_id = ?';
      whereArgs.add(seriesId);
    }

    return await database.query(
      'Sections',
      where: whereClause,
      whereArgs: whereArgs,
    );
  }

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

  Future<void> emptyInventory([dynamic idOrType]) async {
    final database = await db;
    if (database == null) return;

    if (idOrType != null) {
      if (idOrType is int) {
        await database.delete(
          'CurrentStock',
          where: 'location_id = ?',
          whereArgs: [idOrType],
        );
      } else if (idOrType is String && idOrType.isNotEmpty) {
        await database.delete(
          'CurrentStock',
          where: 'item_type = ?',
          whereArgs: [idOrType],
        );
      }
    } else {
      await database.delete('CurrentStock');
    }
    if (idOrType == null) {
      await database.delete('InventoryTransactions');
    }
  }

  Future<List<Map<String, dynamic>>> readAuditLogs({int limit = 50}) async {
    final database = await db;
    if (database == null) return [];
    try {
      return await database.query(
        'AuditLogs',
        orderBy: 'timestamp DESC',
        limit: limit,
      );
    } catch (e) {
      return [];
    }
  }

  // ========================= KIT BUNDLES CRUD =========================

  /// Ù‚Ø±Ø§Ø¡Ø© ÙƒÙ„ Ø§Ù„Ù€ Kits
  Future<List<Map<String, dynamic>>> readKitBundles() async {
    final database = await db;
    if (database == null) return [];
    await _ensureAdvancedKitCompatibilitySchema(database);
    return await database.query(
      'KitBundles',
      where: 'is_active = 1',
      orderBy: 'id ASC',
    );
  }

  /// Ø¥Ø¶Ø§ÙØ© Kit Ø¬Ø¯ÙŠØ¯
  Future<int> insertKitBundle({
    required String name,
    String? description,
    bool perLeaf = false,
  }) async {
    final database = await db;
    if (database == null) return -1;
    return await database.insert('KitBundles', {
      'name': name,
      'description': description,
      'per_leaf': perLeaf ? 1 : 0,
      'is_active': 1,
    });
  }

  /// ØªØ¹Ø¯ÙŠÙ„ Kit
  Future<void> updateKitBundle(
    int id, {
    required String name,
    String? description,
    required bool perLeaf,
  }) async {
    final database = await db;
    if (database == null) return;
    await database.update(
      'KitBundles',
      {'name': name, 'description': description, 'per_leaf': perLeaf ? 1 : 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Ø­Ø°Ù Kit (Ù†Ø§Ø¹Ù…)
  Future<void> deleteKitBundle(int id) async {
    final database = await db;
    if (database == null) return;
    await database.update(
      'KitBundles',
      {'is_active': 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // ========================= KIT BUNDLE FAMILIES CRUD =========================

  /// Families are optional small groups inside a Kit.  They do not represent
  /// stock themselves; only the child KitBundleItems do.
  Future<List<Map<String, dynamic>>> readKitBundleFamilies(int kitId) async {
    final database = await db;
    if (database == null) return [];
    await _ensureAdvancedKitCompatibilitySchema(database);
    return database.query(
      'KitBundleFamilies',
      where: 'kit_id = ? AND is_active = 1',
      whereArgs: [kitId],
      orderBy: 'sort_order ASC, id ASC',
    );
  }

  Future<int> insertKitBundleFamily({
    required int kitId,
    required String name,
    String mechanismScopes = 'belt,crank,motor',
    String bladeScope = 'all',
    bool perLeaf = false,
    int sortOrder = 0,
  }) async {
    final database = await db;
    if (database == null) return -1;
    await _ensureAdvancedKitCompatibilitySchema(database);
    final result = await database.insert('KitBundleFamilies', {
      'kit_id': kitId,
      'name': name.trim(),
      'mechanism_scopes': mechanismScopes,
      'blade_scope': bladeScope.toLowerCase() == 'x3d'
          ? 'extruded'
          : const {'normal', 'extruded'}.contains(bladeScope.toLowerCase())
          ? bladeScope.toLowerCase()
          : 'all',
      'per_leaf': perLeaf ? 1 : 0,
      'sort_order': sortOrder,
      'is_active': 1,
    });
    CloudSyncService().notifyCatalogChange();
    return result;
  }

  Future<void> updateKitBundleFamily(
    int id, {
    required String name,
    String mechanismScopes = 'belt,crank,motor',
    String bladeScope = 'all',
    required bool perLeaf,
    required int sortOrder,
  }) async {
    final database = await db;
    if (database == null) return;
    await _ensureAdvancedKitCompatibilitySchema(database);
    await database.update(
      'KitBundleFamilies',
      {
        'name': name.trim(),
        'mechanism_scopes': mechanismScopes,
        'blade_scope': bladeScope.toLowerCase() == 'x3d'
            ? 'extruded'
            : const {'normal', 'extruded'}.contains(bladeScope.toLowerCase())
            ? bladeScope.toLowerCase()
            : 'all',
        'per_leaf': perLeaf ? 1 : 0,
        'sort_order': sortOrder,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    CloudSyncService().notifyCatalogChange();
  }

  Future<void> deleteKitBundleFamily(int id) async {
    final database = await db;
    if (database == null) return;
    await _ensureAdvancedKitCompatibilitySchema(database);
    await database.transaction((txn) async {
      // Keep the components usable: removing a family returns its children
      // to the Kit root instead of deleting catalogue configuration.
      await txn.update(
        'KitBundleItems',
        {'family_id': null},
        where: 'family_id = ?',
        whereArgs: [id],
      );
      await txn.update(
        'KitBundleFamilies',
        {'is_active': 0},
        where: 'id = ?',
        whereArgs: [id],
      );
    });
    CloudSyncService().notifyCatalogChange();
  }

  // ========================= KIT BUNDLE ITEMS CRUD =========================

  /// Ù‚Ø±Ø§Ø¡Ø© Ù…Ø±ÙƒØ¨Ø§Øª Kit Ù…Ø­Ø¯Ø¯
  Future<List<Map<String, dynamic>>> readKitBundleItems(
    int kitId, {
    int? familyId,
    bool topLevelOnly = false,
  }) async {
    final database = await db;
    if (database == null) return [];
    await _ensureAdvancedKitCompatibilitySchema(database);
    String where = 'kit_id = ?';
    final whereArgs = <Object?>[kitId];
    if (familyId != null) {
      where += ' AND family_id = ?';
      whereArgs.add(familyId);
    } else if (topLevelOnly) {
      where += ' AND family_id IS NULL';
    }
    return await database.query(
      'KitBundleItems',
      where: where,
      whereArgs: whereArgs,
      orderBy: 'sort_order ASC, id ASC',
    );
  }

  /// Ø¥Ø¶Ø§ÙØ© Ù…Ø±ÙƒØ¨ Ù„Ù€ Kit
  Future<int> insertKitBundleItem({
    required int kitId,
    required String componentType,
    required String qtyMode, // 'fixed' | 'by_range' | 'by_variant'
    String? dimension, // 'leaf_height' | 'leaf_width' | null
    double baseQty = 1,
    String unit = 'Ù‚Ø·Ø¹Ø©',
    String mechanismScope = 'all',
    String mechanismScopes = 'belt,crank,motor',
    String bladeScope = 'all',
    int? familyId,
    int sortOrder = 0,
  }) async {
    final database = await db;
    if (database == null) return -1;
    await _ensureAdvancedKitCompatibilitySchema(database);
    final result = await database.insert('KitBundleItems', {
      'kit_id': kitId,
      'family_id': familyId,
      'component_type': componentType,
      'qty_mode': qtyMode,
      'dimension': dimension,
      'base_qty': baseQty,
      'unit': 'Ù‚Ø·Ø¹Ø©',
      'mechanism_scope': const {'belt', 'crank'}.contains(mechanismScope)
          ? mechanismScope
          : 'all',
      'mechanism_scopes': mechanismScopes,
      'blade_scope': bladeScope.toLowerCase() == 'x3d'
          ? 'extruded'
          : const {'normal', 'extruded'}.contains(bladeScope.toLowerCase())
          ? bladeScope.toLowerCase()
          : 'all',
      'sort_order': sortOrder,
    });
    CloudSyncService().notifyCatalogChange();
    return result;
  }

  /// ØªØ¹Ø¯ÙŠÙ„ Ù…Ø±ÙƒØ¨ Kit
  Future<void> updateKitBundleItem(
    int id, {
    required String componentType,
    required String qtyMode,
    String? dimension,
    required double baseQty,
    required String unit,
    String mechanismScope = 'all',
    String mechanismScopes = 'belt,crank,motor',
    String bladeScope = 'all',
    required int sortOrder,
  }) async {
    final database = await db;
    if (database == null) return;
    await _ensureAdvancedKitCompatibilitySchema(database);
    await database.update(
      'KitBundleItems',
      {
        'component_type': componentType,
        'qty_mode': qtyMode,
        'dimension': dimension,
        'base_qty': baseQty,
        'unit': 'Ù‚Ø·Ø¹Ø©',
        'mechanism_scope': const {'belt', 'crank'}.contains(mechanismScope)
            ? mechanismScope
            : 'all',
        'mechanism_scopes': mechanismScopes,
        'blade_scope': bladeScope.toLowerCase() == 'x3d'
            ? 'extruded'
            : const {'normal', 'extruded'}.contains(bladeScope.toLowerCase())
            ? bladeScope.toLowerCase()
            : 'all',
        'sort_order': sortOrder,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    CloudSyncService().notifyCatalogChange();
  }

  /// Ø­Ø°Ù Ù…Ø±ÙƒØ¨ Kit
  Future<void> deleteKitBundleItem(int id) async {
    final database = await db;
    if (database == null) return;
    await database.delete('KitBundleItems', where: 'id = ?', whereArgs: [id]);
    // ØªÙØ­Ø°Ù Ø§Ù„Ù†Ø·Ø§Ù‚Ø§Øª ÙˆØ§Ù„Ù…ØªØºÙŠØ±Ø§Øª ØªÙ„Ù‚Ø§Ø¦ÙŠØ§Ù‹ Ø¨Ø³Ø¨Ø¨ ON DELETE CASCADE
  }

  // ========================= KIT ITEM RANGES CRUD =========================

  /// Ù‚Ø±Ø§Ø¡Ø© Ù†Ø·Ø§Ù‚Ø§Øª Ù…Ø±ÙƒØ¨ Ù…Ø­Ø¯Ø¯
  Future<List<Map<String, dynamic>>> readKitItemRanges(int itemId) async {
    final database = await db;
    if (database == null) return [];
    await _ensureAdvancedKitCompatibilitySchema(database);
    final rows = await database.query(
      'KitItemRanges',
      where: 'item_id = ?',
      whereArgs: [itemId],
      orderBy: 'min_mm ASC',
    );
    final result = <Map<String, dynamic>>[];
    for (final raw in rows) {
      final row = Map<String, dynamic>.from(raw);
      final componentId = (row['shutter_component_id'] as num?)?.toInt();
      if (componentId != null) {
        final components = await database.query(
          'ShutterComponents',
          where: 'id = ?',
          whereArgs: [componentId],
          limit: 1,
        );
        if (components.isNotEmpty) {
          final component = Map<String, dynamic>.from(components.first);
          final prices = await database.query(
            'ShutterColorPrices',
            where: 'shutter_component_id = ?',
            whereArgs: [componentId],
          );
          row['product_name'] =
              component['name']?.toString() ?? row['product_name'];
          row['shutter_component'] = component;
          row['shutter_color_prices'] = prices
              .map((price) => Map<String, dynamic>.from(price))
              .toList();
        }
      }
      final familyId = (row['family_id'] as num?)?.toInt();
      if (familyId != null) {
        final families = await database.query(
          'KitBundleFamilies',
          where: 'id = ? AND is_active = 1',
          whereArgs: [familyId],
          limit: 1,
        );
        if (families.isNotEmpty) {
          final family = Map<String, dynamic>.from(families.first);
          row['product_name'] =
              family['name']?.toString() ?? row['product_name'];
          row['family'] = family;
        }
      }
      result.add(row);
    }
    return result;
  }

  /// Ø¥Ø¶Ø§ÙØ© Ù†Ø·Ø§Ù‚
  Future<int> insertKitItemRange({
    required int itemId,
    required double minMm,
    required double maxMm,
    required String productName,
    double price = 0.0,
    double qty = 1,
    int compatibilityGroup = 0,
    int? shutterComponentId,
    int? familyId,
  }) async {
    final database = await db;
    if (database == null) return -1;
    await _ensureAdvancedKitCompatibilitySchema(database);
    final linkedColumn = shutterComponentId != null
        ? 'shutter_component_id'
        : familyId != null
        ? 'family_id'
        : null;
    final linkedId = shutterComponentId ?? familyId;
    if (linkedColumn != null && linkedId != null) {
      final duplicate = await database.query(
        'KitItemRanges',
        columns: const ['id'],
        where:
            'item_id = ? AND $linkedColumn = ? AND min_mm < ? AND max_mm > ? AND compatibility_group = ?',
        whereArgs: [
          itemId,
          linkedId,
          maxMm,
          minMm,
          compatibilityGroup.clamp(0, 2),
        ],
        limit: 1,
      );
      if (duplicate.isNotEmpty) return -2;
    }
    final result = await database.insert('KitItemRanges', {
      'item_id': itemId,
      'min_mm': minMm,
      'max_mm': maxMm,
      'product_name': productName,
      'price': price,
      'qty': qty,
      'compatibility_group': compatibilityGroup.clamp(0, 2),
      'shutter_component_id': shutterComponentId,
      'family_id': familyId,
    });
    CloudSyncService().notifyCatalogChange();
    return result;
  }

  /// ØªØ¹Ø¯ÙŠÙ„ Ù†Ø·Ø§Ù‚
  Future<int> updateKitItemRange(
    int id, {
    required double minMm,
    required double maxMm,
    required String productName,
    required double price,
    required double qty,
    int compatibilityGroup = 0,
    int? shutterComponentId,
    int? familyId,
  }) async {
    final database = await db;
    if (database == null) return 0;
    await _ensureAdvancedKitCompatibilitySchema(database);
    final linkedColumn = shutterComponentId != null
        ? 'shutter_component_id'
        : familyId != null
        ? 'family_id'
        : null;
    final linkedId = shutterComponentId ?? familyId;
    if (linkedColumn != null && linkedId != null) {
      final duplicate = await database.query(
        'KitItemRanges',
        columns: const ['id'],
        where:
            'id != ? AND item_id = (SELECT item_id FROM KitItemRanges WHERE id = ?) '
            'AND $linkedColumn = ? AND min_mm < ? AND max_mm > ? '
            'AND compatibility_group = ?',
        whereArgs: [
          id,
          id,
          linkedId,
          maxMm,
          minMm,
          compatibilityGroup.clamp(0, 2),
        ],
        limit: 1,
      );
      if (duplicate.isNotEmpty) return -2;
    }
    final result = await database.update(
      'KitItemRanges',
      {
        'min_mm': minMm,
        'max_mm': maxMm,
        'product_name': productName,
        'price': price,
        'qty': qty,
        'compatibility_group': compatibilityGroup.clamp(0, 2),
        'shutter_component_id': shutterComponentId,
        'family_id': familyId,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    CloudSyncService().notifyCatalogChange();
    return result;
  }

  Future<void> updateKitCompatibilityGroupNames(
    int kitId, {
    required String group1Name,
    required String group2Name,
  }) async {
    final database = await db;
    if (database == null) return;
    await _ensureAdvancedKitCompatibilitySchema(database);
    await database.update(
      'KitBundles',
      {
        'compatibility_group_1_name': group1Name.trim().isEmpty
            ? 'Console Quissonnel Standard'
            : group1Name.trim(),
        'compatibility_group_2_name': group2Name.trim().isEmpty
            ? 'Console Quissonnel SpÃ©cial'
            : group2Name.trim(),
      },
      where: 'id = ?',
      whereArgs: [kitId],
    );
    CloudSyncService().notifyCatalogChange();
  }

  /// Ø­Ø°Ù Ù†Ø·Ø§Ù‚
  Future<void> deleteKitItemRange(int id) async {
    final database = await db;
    if (database == null) return;
    await database.delete('KitItemRanges', where: 'id = ?', whereArgs: [id]);
  }

  /// Ø§Ù„Ø¨Ø­Ø« Ø¹Ù† Ø§Ù„Ù†Ø·Ø§Ù‚ Ø§Ù„Ù…Ù†Ø§Ø³Ø¨ Ù„Ù‚ÙŠØ§Ø³ Ù…Ø¹ÙŠÙ†
  Future<Map<String, dynamic>?> findKitItemRangeForDimension(
    int itemId,
    double valueMm,
  ) async {
    final database = await db;
    if (database == null) return null;
    final results = await database.query(
      'KitItemRanges',
      where: 'item_id = ? AND min_mm <= ? AND max_mm > ?',
      whereArgs: [itemId, valueMm, valueMm],
      limit: 1,
    );
    return results.isNotEmpty ? results.first : null;
  }

  // ========================= KIT ITEM VARIANTS CRUD =========================

  /// Ù‚Ø±Ø§Ø¡Ø© Ù…ØªØºÙŠØ±Ø§Øª Ù…Ø±ÙƒØ¨ Ù…Ø­Ø¯Ø¯
  Future<List<Map<String, dynamic>>> readKitItemVariants(int itemId) async {
    final database = await db;
    if (database == null) return [];
    return await database.query(
      'KitItemVariants',
      where: 'item_id = ?',
      whereArgs: [itemId],
    );
  }

  /// Ø¥Ø¶Ø§ÙØ© Ù…ØªØºÙŠØ± (simple/double ouvrant)
  Future<int> insertKitItemVariant({
    required int itemId,
    required String ouvrantType, // 'simple' | 'double'
    required String productName,
    double price = 0.0,
    double qty = 1,
  }) async {
    final database = await db;
    if (database == null) return -1;
    return await database.insert('KitItemVariants', {
      'item_id': itemId,
      'ouvrant_type': ouvrantType,
      'product_name': productName,
      'price': price,
      'qty': qty,
    });
  }

  /// ØªØ¹Ø¯ÙŠÙ„ Ù…ØªØºÙŠØ±
  Future<void> updateKitItemVariant(
    int id, {
    required String ouvrantType,
    required String productName,
    required double price,
    required double qty,
  }) async {
    final database = await db;
    if (database == null) return;
    await database.update(
      'KitItemVariants',
      {
        'ouvrant_type': ouvrantType,
        'product_name': productName,
        'price': price,
        'qty': qty,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Ø­Ø°Ù Ù…ØªØºÙŠØ±
  Future<void> deleteKitItemVariant(int id) async {
    final database = await db;
    if (database == null) return;
    await database.delete('KitItemVariants', where: 'id = ?', whereArgs: [id]);
  }

  /// Ù‚Ø±Ø§Ø¡Ø© ÙƒÙ„ Ù…Ø±ÙƒØ¨Ø§Øª Kit Ù…Ø¹ Ù†Ø·Ø§Ù‚Ø§ØªÙ‡Ø§ ÙˆÙ…ØªØºÙŠØ±Ø§ØªÙ‡Ø§ â€” Ù„Ù„Ø­Ø³Ø§Ø¨ ÙÙŠ BOM
  Future<List<Map<String, dynamic>>> readKitBundleItemsWithDetails(
    int kitId, {
    int? familyId,
    bool topLevelOnly = false,
  }) async {
    final database = await db;
    if (database == null) return [];
    await _ensureAdvancedKitCompatibilitySchema(database);
    final items = await readKitBundleItems(
      kitId,
      familyId: familyId,
      topLevelOnly: topLevelOnly,
    );
    final families = await readKitBundleFamilies(kitId);
    final familyById = <int, Map<String, dynamic>>{
      for (final family in families)
        if (family['id'] is num)
          (family['id'] as num).toInt(): Map<String, dynamic>.from(family),
    };
    final result = <Map<String, dynamic>>[];
    for (final item in items) {
      final itemId = item['id'] as int;
      final ranges = await readKitItemRanges(itemId);
      final variants = await readKitItemVariants(itemId);
      final itemMap = Map<String, dynamic>.from(item);
      final rawFamilyId = itemMap['family_id'];
      final itemFamilyId = rawFamilyId is num
          ? rawFamilyId.toInt()
          : int.tryParse('$rawFamilyId');
      result.add({
        ...itemMap,
        'ranges': ranges,
        'variants': variants,
        if (itemFamilyId != null && familyById[itemFamilyId] != null)
          'family': familyById[itemFamilyId],
      });
    }

    // Families are selectable outcomes of a root item's ranges.  They are
    // deliberately not flattened into the root list, otherwise merely
    // creating a family would add every child to every BOM.
    if (familyId == null && topLevelOnly) {
      final selectedFamilyIds = <int>{};
      for (final item in result) {
        for (final rawRange in item['ranges'] as List? ?? const []) {
          if (rawRange is! Map) continue;
          final rawId = rawRange['family_id'];
          final id = rawId is num
              ? rawId.toInt()
              : int.tryParse(rawId?.toString() ?? '');
          if (id != null && familyById.containsKey(id)) {
            selectedFamilyIds.add(id);
          }
        }
      }
      final selectedFamilies = <int, Map<String, dynamic>>{};
      for (final id in selectedFamilyIds) {
        final family = Map<String, dynamic>.from(familyById[id]!);
        family['items'] = await readKitBundleItemsWithDetails(
          kitId,
          familyId: id,
        );
        selectedFamilies[id] = family;
      }
      for (final item in result) {
        final rawRanges = item['ranges'] as List? ?? const [];
        item['ranges'] = rawRanges.map((rawRange) {
          if (rawRange is! Map) return rawRange;
          final range = Map<String, dynamic>.from(rawRange);
          final rawId = range['family_id'];
          final id = rawId is num
              ? rawId.toInt()
              : int.tryParse(rawId?.toString() ?? '');
          if (id != null && selectedFamilies[id] != null) {
            range['family'] = selectedFamilies[id];
          }
          return range;
        }).toList();
      }
    }
    return result;
  }

  Future<List<Map<String, dynamic>>> readShutterBoxLimits() async {
    final myDb = await db;
    if (myDb == null) return [];
    return await myDb.rawQuery('''
      SELECT 
        l.id, 
        l.box_size, 
        l.blade_id, 
        l.max_height,
        c.max_width_mm AS blade_max_width,
        c.name as blade_name
      FROM ShutterBoxLimits l
      LEFT JOIN ShutterComponents c ON l.blade_id = c.id
      ORDER BY c.name ASC, l.box_size ASC
    ''');
  }

  Future<int> insertShutterBoxLimit(
    int boxSize,
    int bladeId,
    double maxHeight,
    double maxWidth,
  ) async {
    final myDb = await db;
    if (myDb == null) return -1;
    final res = await myDb.insert('ShutterBoxLimits', {
      'box_size': boxSize,
      'blade_id': bladeId,
      'max_height': maxHeight,
    });
    await myDb.update(
      'ShutterComponents',
      {'max_width_mm': maxWidth},
      where: 'id = ?',
      whereArgs: [bladeId],
    );
    CloudSyncService().notifyCatalogChange();
    return res;
  }

  Future<int> updateShutterBoxLimit(
    int id,
    int boxSize,
    int bladeId,
    double maxHeight,
    double maxWidth,
  ) async {
    final myDb = await db;
    if (myDb == null) return -1;
    final res = await myDb.update(
      'ShutterBoxLimits',
      {'box_size': boxSize, 'blade_id': bladeId, 'max_height': maxHeight},
      where: 'id = ?',
      whereArgs: [id],
    );
    await myDb.update(
      'ShutterComponents',
      {'max_width_mm': maxWidth},
      where: 'id = ?',
      whereArgs: [bladeId],
    );
    CloudSyncService().notifyCatalogChange();
    return res;
  }

  Future<int> deleteShutterBoxLimit(int id) async {
    final myDb = await db;
    if (myDb == null) return -1;
    final res = await myDb.delete(
      'ShutterBoxLimits',
      where: 'id = ?',
      whereArgs: [id],
    );
    CloudSyncService().notifyCatalogChange();
    return res;
  }

  // â”€â”€ Caisson Tunnel Prices â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  Future<List<Map<String, dynamic>>> getCaissonTunnelPrices() async {
    final myDb = await db;
    if (myDb == null) return [];
    try {
      return await myDb.rawQuery('''
        SELECT 
          ctp.id,
          ctp.color_id,
          ctp.profile_price_per_bar,
          ctp.bottom_cover_price_per_bar,
          ctp.price_per_meter,
          c.name as color_name,
          c.hex_code as color_hex
        FROM CaissonTunnelPrices ctp
        LEFT JOIN Colors c ON ctp.color_id = c.id
        ORDER BY c.name ASC
      ''');
    } catch (_) {
      return [];
    }
  }

  Future<void> upsertCaissonTunnelPrice({
    required int colorId,
    required double profilePricePerBar,
    required double bottomCoverPricePerBar,
    required double pricePerMeter,
  }) async {
    final myDb = await db;
    if (myDb == null) return;
    await myDb.execute(
      '''
      INSERT INTO CaissonTunnelPrices (color_id, profile_price_per_bar, bottom_cover_price_per_bar, price_per_meter)
      VALUES (?, ?, ?, ?)
      ON CONFLICT(color_id) DO UPDATE SET
        profile_price_per_bar = excluded.profile_price_per_bar,
        bottom_cover_price_per_bar = excluded.bottom_cover_price_per_bar,
        price_per_meter = excluded.price_per_meter
    ''',
      [colorId, profilePricePerBar, bottomCoverPricePerBar, pricePerMeter],
    );
    CloudSyncService().notifyCatalogChange();
  }

  Future<int> deleteCaissonTunnelPrice(int id) async {
    final myDb = await db;
    if (myDb == null) return -1;
    final res = await myDb.delete(
      'CaissonTunnelPrices',
      where: 'id = ?',
      whereArgs: [id],
    );
    CloudSyncService().notifyCatalogChange();
    return res;
  }

  // â”€â”€ Series Table Config â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  Future<Map<String, dynamic>?> getSeriesTableConfig(int seriesId) async {
    final myDb = await db;
    if (myDb == null) return null;
    try {
      final res = await myDb.query(
        'SeriesTableConfig',
        where: 'series_id = ?',
        whereArgs: [seriesId],
      );
      if (res.isNotEmpty) return res.first;
    } catch (e) {
      debugPrint('Error reading SeriesTableConfig: $e');
    }
    return null;
  }

  Future<void> upsertSeriesTableConfig({
    required int seriesId,
    required String allowedSectionTypes,
    required String allowedAccessoryIds,
    required String allowedAccessoryTypes,
    required String excludedAccessoryIds,
    double sashWDeduction2 = 0.0,
    double sashWDeduction3 = 0.0,
    double sashWDeduction4 = 0.0,
    double sashOverlapVal = 0.0,
    double glassWDeduction = 0.0,
    int slidingChicanePiecesPerJunction = 1,
    double slidingRailClearance = 1.0,
    String customFormulaNotes = '',
  }) async {
    final myDb = await db;
    if (myDb == null) return;
    await myDb.execute(
      '''
      INSERT INTO SeriesTableConfig (
        series_id, allowed_section_types, allowed_accessory_ids, allowed_accessory_types, excluded_accessory_ids,
        sash_w_deduction_2, sash_w_deduction_3, sash_w_deduction_4, sash_overlap_val, glass_w_deduction,
        sliding_chicane_pieces_per_junction, sliding_rail_clearance, custom_formula_notes, updated_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(series_id) DO UPDATE SET
        allowed_section_types = excluded.allowed_section_types,
        allowed_accessory_ids = excluded.allowed_accessory_ids,
        allowed_accessory_types = excluded.allowed_accessory_types,
        excluded_accessory_ids = excluded.excluded_accessory_ids,
        sash_w_deduction_2 = excluded.sash_w_deduction_2,
        sash_w_deduction_3 = excluded.sash_w_deduction_3,
        sash_w_deduction_4 = excluded.sash_w_deduction_4,
        sash_overlap_val = excluded.sash_overlap_val,
        glass_w_deduction = excluded.glass_w_deduction,
        sliding_chicane_pieces_per_junction = excluded.sliding_chicane_pieces_per_junction,
        sliding_rail_clearance = excluded.sliding_rail_clearance,
        custom_formula_notes = excluded.custom_formula_notes,
        updated_at = excluded.updated_at
    ''',
      [
        seriesId,
        allowedSectionTypes,
        allowedAccessoryIds,
        allowedAccessoryTypes,
        excludedAccessoryIds,
        sashWDeduction2,
        sashWDeduction3,
        sashWDeduction4,
        sashOverlapVal,
        glassWDeduction,
        slidingChicanePiecesPerJunction,
        slidingRailClearance,
        customFormulaNotes,
        DateTime.now().toIso8601String(),
      ],
    );
    CloudSyncService().notifyChange();
  }

  // ── Dynamic design definition (drawing + shutter) ───────────────────────

  Future<Map<String, dynamic>?> getSeriesDesignConfig(int seriesId) async {
    final myDb = await db;
    if (myDb == null) return null;
    await _ensureSeriesDesignTables(myDb);
    final rows = await myDb.query(
      'SeriesDesignConfig',
      where: 'series_id = ?',
      whereArgs: [seriesId],
      limit: 1,
    );
    return rows.isEmpty ? null : Map<String, dynamic>.from(rows.first);
  }

  Future<List<Map<String, dynamic>>> getSeriesDesignRoles(int seriesId) async {
    final myDb = await db;
    if (myDb == null) return [];
    await _ensureSeriesDesignTables(myDb);
    return myDb.rawQuery(
      '''
      SELECT r.*, s.code AS section_code, s.name AS section_name,
             s.type AS section_type, s.visible_width, s.thickness
      FROM SeriesDesignRoles r
      LEFT JOIN Sections s ON s.id = r.section_id
      WHERE r.series_id = ?
      ORDER BY r.sort_order ASC, r.is_default DESC, r.id ASC
    ''',
      [seriesId],
    );
  }

  /// Replaces only the profile-to-role mapping of a series.  It deliberately
  /// leaves drawing options and shutter rules untouched: a shutter is a
  /// separate product and must not be coupled to the aluminium series.
  Future<void> saveSeriesDesignRoles({
    required int seriesId,
    required List<Map<String, dynamic>> roles,
  }) async {
    final myDb = await db;
    if (myDb == null) return;
    await _ensureSeriesDesignTables(myDb);
    final now = DateTime.now().toIso8601String();
    await myDb.transaction((txn) async {
      await txn.delete(
        'SeriesDesignRoles',
        where: 'series_id = ?',
        whereArgs: [seriesId],
      );
      for (var index = 0; index < roles.length; index++) {
        final role = roles[index];
        final sectionId = (role['section_id'] as num?)?.toInt();
        final roleKey = role['role_key']?.toString().trim() ?? '';
        if (sectionId == null || roleKey.isEmpty) continue;
        await txn.insert('SeriesDesignRoles', {
          'series_id': seriesId,
          'role_key': roleKey,
          'section_id': sectionId,
          'usage_scope': role['usage_scope']?.toString() ?? 'auto',
          'show_when_glass': role['show_when_glass']?.toString() ?? 'any',
          'integrated_side_cover':
              role['integrated_side_cover'] == true ||
                  role['integrated_side_cover'] == 1
              ? 1
              : 0,
          'allows_side_cover':
              role['allows_side_cover'] == false ||
                  role['allows_side_cover'] == 0
              ? 0
              : 1,
          'allowed_with_shutter':
              role['allowed_with_shutter'] == false ||
                  role['allowed_with_shutter'] == 0
              ? 0
              : 1,
          'show_in_drawing':
              role['show_in_drawing'] == false || role['show_in_drawing'] == 0
              ? 0
              : 1,
          'show_in_quantity':
              role['show_in_quantity'] == false || role['show_in_quantity'] == 0
              ? 0
              : 1,
          'show_in_dialog':
              role['show_in_dialog'] == false || role['show_in_dialog'] == 0
              ? 0
              : 1,
          'width_adjust_mm': role['width_adjust_mm'] ?? 0.0,
          'height_adjust_mm': role['height_adjust_mm'] ?? 0.0,
          'formula_note': role['formula_note']?.toString() ?? '',
          'is_required': role['is_required'] == true || role['is_required'] == 1
              ? 1
              : 0,
          'is_default': role['is_default'] == true || role['is_default'] == 1
              ? 1
              : 0,
          'is_visible': role['is_visible'] == false || role['is_visible'] == 0
              ? 0
              : 1,
          'sort_order': index,
          'updated_at': now,
        });
      }
    });
    CloudSyncService().notifyCatalogChange();
  }

  Future<List<Map<String, dynamic>>> getSectionJointLinksForSeries(
    int seriesId,
  ) async {
    final myDb = await db;
    if (myDb == null) return [];
    await _ensureSeriesDesignTables(myDb);
    return myDb.rawQuery(
      '''
      SELECT l.*, j.name AS joint_name, j.thickness AS joint_thickness,
             j.price_per_meter AS joint_price_per_meter,
             j.gasket_type AS joint_gasket_type
      FROM SectionJointLinks l
      LEFT JOIN Joints j ON j.id = l.joint_id
      WHERE l.series_id = ?
      ORDER BY l.section_id ASC, l.position_key ASC,
               l.is_default DESC, l.sort_order ASC, l.id ASC
    ''',
      [seriesId],
    );
  }

  Future<void> saveSectionJointLinksForSeries({
    required int seriesId,
    required List<Map<String, dynamic>> links,
  }) async {
    final myDb = await db;
    if (myDb == null) return;
    await _ensureSeriesDesignTables(myDb);
    final now = DateTime.now().toIso8601String();
    await myDb.transaction((txn) async {
      await txn.delete(
        'SectionJointLinks',
        where: 'series_id = ?',
        whereArgs: [seriesId],
      );
      for (var index = 0; index < links.length; index++) {
        final link = links[index];
        final sectionId = (link['section_id'] as num?)?.toInt();
        final jointId = (link['joint_id'] as num?)?.toInt();
        final gasketType = link['gasket_type']?.toString().trim() ?? '';
        final positionKey = link['position_key']?.toString().trim() ?? '';
        if (sectionId == null ||
            (jointId == null && gasketType.isEmpty) ||
            positionKey.isEmpty) {
          continue;
        }
        await txn.insert('SectionJointLinks', {
          'series_id': seriesId,
          'section_id': sectionId,
          'joint_id': jointId ?? 0,
          'gasket_type': gasketType,
          'position_key': positionKey,
          'is_default': link['is_default'] == false || link['is_default'] == 0
              ? 0
              : 1,
          'sort_order': index,
          'updated_at': now,
        });
      }
    });
    CloudSyncService().notifyCatalogChange();
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

  Future<List<Map<String, dynamic>>> getSeriesShutterRules(int seriesId) async {
    final myDb = await db;
    if (myDb == null) return [];
    await _ensureSeriesDesignTables(myDb);
    return myDb.rawQuery(
      '''
      SELECT r.*, c.name AS component_name, c.component_type,
             c.measurement, c.shutter_subtype, c.unit
      FROM SeriesShutterRules r
      LEFT JOIN ShutterComponents c ON c.id = r.component_id
      WHERE r.series_id = ? AND r.is_active = 1
      ORDER BY r.component_role ASC, r.sort_order ASC, r.is_default DESC, r.id ASC
    ''',
      [seriesId],
    );
  }

  Future<List<Map<String, dynamic>>> getCatalogItemRules({
    String? itemTable,
    int? itemId,
    int? seriesId,
    Iterable<String> roleKeys = const [],
  }) async {
    final myDb = await db;
    if (myDb == null) return [];
    await _ensureSeriesDesignTables(myDb);
    final where = <String>['is_active = 1'];
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
      where.add('(series_id = ? OR series_id IS NULL)');
      args.add(seriesId);
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
          'CASE WHEN series_id IS NULL THEN 1 ELSE 0 END, sort_order ASC, is_default DESC, id ASC',
    );
  }

  Future<void> saveCatalogItemRules({
    required String itemTable,
    int? seriesId,
    required List<Map<String, dynamic>> rules,
  }) async {
    final myDb = await db;
    if (myDb == null) return;
    await _ensureSeriesDesignTables(myDb);
    final cleanTable = itemTable.trim();
    if (cleanTable.isEmpty) return;
    final now = DateTime.now().toIso8601String();
    await myDb.transaction((txn) async {
      if (seriesId == null) {
        await txn.delete(
          'CatalogItemRules',
          where: 'item_table = ? AND series_id IS NULL',
          whereArgs: [cleanTable],
        );
      } else {
        await txn.delete(
          'CatalogItemRules',
          where: 'item_table = ? AND series_id = ?',
          whereArgs: [cleanTable, seriesId],
        );
      }
      for (var index = 0; index < rules.length; index++) {
        final rule = rules[index];
        final itemId = (rule['item_id'] as num?)?.toInt();
        final roleKey = rule['role_key']?.toString().trim() ?? '';
        if (itemId == null || roleKey.isEmpty) continue;
        await txn.insert('CatalogItemRules', {
          'item_table': cleanTable,
          'item_id': itemId,
          'series_id': seriesId,
          'role_key': roleKey,
          'usage_scope': rule['usage_scope']?.toString() ?? 'global',
          'show_when_glass': rule['show_when_glass']?.toString() ?? 'any',
          'selection_mode': rule['selection_mode']?.toString() ?? 'always',
          'integrated_side_cover':
              rule['integrated_side_cover'] == true ||
                  rule['integrated_side_cover'] == 1
              ? 1
              : 0,
          'allows_side_cover':
              rule['allows_side_cover'] == false ||
                  rule['allows_side_cover'] == 0
              ? 0
              : 1,
          'allowed_with_shutter':
              rule['allowed_with_shutter'] == false ||
                  rule['allowed_with_shutter'] == 0
              ? 0
              : 1,
          'show_in_drawing':
              rule['show_in_drawing'] == false || rule['show_in_drawing'] == 0
              ? 0
              : 1,
          'show_in_quantity':
              rule['show_in_quantity'] == false || rule['show_in_quantity'] == 0
              ? 0
              : 1,
          'show_in_dialog':
              rule['show_in_dialog'] == false || rule['show_in_dialog'] == 0
              ? 0
              : 1,
          'width_adjust_mm': rule['width_adjust_mm'] ?? 0.0,
          'height_adjust_mm': rule['height_adjust_mm'] ?? 0.0,
          'formula_note': rule['formula_note']?.toString() ?? '',
          'is_default': rule['is_default'] == true || rule['is_default'] == 1
              ? 1
              : 0,
          'is_active': rule['is_active'] == false || rule['is_active'] == 0
              ? 0
              : 1,
          'sort_order': index,
          'updated_at': now,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
    CloudSyncService().notifyCatalogChange();
  }

  /// Saves an entire definition in one transaction. Replacing the rows keeps
  /// the page predictable: the exact set visible in Design is always the set
  /// selected by the administrator, with no old component left behind.
  Future<void> saveSeriesDesignDefinition({
    required int seriesId,
    required bool supportsShutter,
    required bool allowsDivisions,
    required List<String> allowedContents,
    required List<Map<String, dynamic>> roles,
    required List<Map<String, dynamic>> shutterRules,
  }) async {
    final myDb = await db;
    if (myDb == null) return;
    await _ensureSeriesDesignTables(myDb);
    final now = DateTime.now().toIso8601String();
    await myDb.transaction((txn) async {
      await txn.insert('SeriesDesignConfig', {
        'series_id': seriesId,
        'supports_shutter': supportsShutter ? 1 : 0,
        'allows_divisions': allowsDivisions ? 1 : 0,
        'allowed_contents_json': jsonEncode(allowedContents),
        'updated_at': now,
      }, conflictAlgorithm: ConflictAlgorithm.replace);

      await txn.delete(
        'SeriesDesignRoles',
        where: 'series_id = ?',
        whereArgs: [seriesId],
      );
      for (var index = 0; index < roles.length; index++) {
        final role = roles[index];
        final sectionId = (role['section_id'] as num?)?.toInt();
        final roleKey = role['role_key']?.toString().trim() ?? '';
        if (sectionId == null || roleKey.isEmpty) continue;
        await txn.insert('SeriesDesignRoles', {
          'series_id': seriesId,
          'role_key': roleKey,
          'section_id': sectionId,
          'usage_scope': role['usage_scope']?.toString() ?? 'auto',
          'show_when_glass': role['show_when_glass']?.toString() ?? 'any',
          'integrated_side_cover':
              role['integrated_side_cover'] == true ||
                  role['integrated_side_cover'] == 1
              ? 1
              : 0,
          'allows_side_cover':
              role['allows_side_cover'] == false ||
                  role['allows_side_cover'] == 0
              ? 0
              : 1,
          'allowed_with_shutter':
              role['allowed_with_shutter'] == false ||
                  role['allowed_with_shutter'] == 0
              ? 0
              : 1,
          'show_in_drawing':
              role['show_in_drawing'] == false || role['show_in_drawing'] == 0
              ? 0
              : 1,
          'show_in_quantity':
              role['show_in_quantity'] == false || role['show_in_quantity'] == 0
              ? 0
              : 1,
          'show_in_dialog':
              role['show_in_dialog'] == false || role['show_in_dialog'] == 0
              ? 0
              : 1,
          'width_adjust_mm': role['width_adjust_mm'] ?? 0.0,
          'height_adjust_mm': role['height_adjust_mm'] ?? 0.0,
          'formula_note': role['formula_note']?.toString() ?? '',
          'is_required': role['is_required'] == true || role['is_required'] == 1
              ? 1
              : 0,
          'is_default': role['is_default'] == true || role['is_default'] == 1
              ? 1
              : 0,
          'is_visible': role['is_visible'] == false || role['is_visible'] == 0
              ? 0
              : 1,
          'sort_order': index,
          'updated_at': now,
        });
      }

      await txn.delete(
        'SeriesShutterRules',
        where: 'series_id = ?',
        whereArgs: [seriesId],
      );
      for (var index = 0; index < shutterRules.length; index++) {
        final rule = shutterRules[index];
        final componentId = (rule['component_id'] as num?)?.toInt();
        final role = rule['component_role']?.toString().trim() ?? '';
        if (componentId == null || role.isEmpty) continue;
        await txn.insert('SeriesShutterRules', {
          'series_id': seriesId,
          'component_id': componentId,
          'component_role': role,
          'selection_mode': rule['selection_mode']?.toString() ?? 'always',
          'min_width_mm': rule['min_width_mm'],
          'max_width_mm': rule['max_width_mm'],
          'min_height_mm': rule['min_height_mm'],
          'max_height_mm': rule['max_height_mm'],
          'is_default': rule['is_default'] == true || rule['is_default'] == 1
              ? 1
              : 0,
          'is_active': rule['is_active'] == false || rule['is_active'] == 0
              ? 0
              : 1,
          'sort_order': index,
          'updated_at': now,
        });
      }
    });
    CloudSyncService().notifyCatalogChange();
  }

  Future<List<Map<String, dynamic>>> getDesignSectionsForRoles(
    int seriesId,
    Iterable<String> roleKeys, {
    bool requireDialog = true,
    bool requireQuantity = false,
  }) async {
    final keys = roleKeys.where((key) => key.trim().isNotEmpty).toList();
    if (keys.isEmpty) return [];
    final myDb = await db;
    if (myDb == null) return [];
    await _ensureSeriesDesignTables(myDb);
    final placeholders = List.filled(keys.length, '?').join(',');
    final surfaceFilters = <String>[
      'r.is_visible = 1',
      if (requireDialog) 'r.show_in_dialog = 1',
      if (requireQuantity) 'r.show_in_quantity = 1',
    ].join('\n        AND ');
    return myDb.rawQuery(
      '''
      SELECT s.*
      FROM Sections s
      INNER JOIN SeriesDesignRoles r ON r.section_id = s.id
      WHERE r.series_id = ?
        AND $surfaceFilters
        AND r.role_key IN ($placeholders)
        AND (s.is_active = 1 OR s.is_active IS NULL)
      ORDER BY r.sort_order ASC, r.is_default DESC, s.name ASC
    ''',
      [seriesId, ...keys],
    );
  }

  Future<Map<int, String>> getOrderAssignedWorkersMap() async {
    Database? myDb = await db;
    if (myDb == null) return {};
    try {
      final rows = await myDb.rawQuery('''
        SELECT cd.id_commandes as order_id, COALESCE(NULLIF(TRIM(e.name), ''), wa.worker_uid) as worker_name
        FROM WorkerAllocations wa
        JOIN Commandes_details cd ON wa.commande_detail_id = cd.id
        LEFT JOIN Employees e ON wa.worker_uid = CAST(e.id AS TEXT) OR wa.worker_uid = e.phone
      ''');
      final Map<int, Set<String>> orderWorkers = {};
      for (final row in rows) {
        final orderId = (row['order_id'] as num?)?.toInt() ?? 0;
        final name = row['worker_name']?.toString().trim() ?? '';
        if (orderId > 0 && name.isNotEmpty) {
          orderWorkers.putIfAbsent(orderId, () => {}).add(name);
        }
      }
      return orderWorkers.map((key, val) => MapEntry(key, val.join(', ')));
    } catch (_) {
      return {};
    }
  }
}
