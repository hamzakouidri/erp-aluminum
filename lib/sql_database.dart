import 'dart:convert';
import 'dart:async';
import 'dart:io';
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

class SqlDatabase {
  static Database? _db;

  static DatabaseFactory get _dbFactory {
    if (kIsWeb) {
      return databaseFactoryFfiWeb;
    }
    if (!kIsWeb && Platform.environment.containsKey('FLUTTER_TEST')) {
      sqflite_common.sqfliteFfiInit();
      return sqflite_common.databaseFactoryFfi;
    }
    return databaseFactory;
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
    'ShutterColorPrices',
    'ShutterComponentColors',
    'ShutterSqmPrices',
    'ShutterBoxLimits',
    'CaissonTunnelPrices',
    'SeriesColorPrices',
    'SectionColorPrices',
    'AccessoryColorPrices',
    'ProfileColors',
    'KitBundles',
    'KitBundleItems',
    'KitItemRanges',
    'KitItemVariants',
  ];

  static void resetDb() {
    _db = null;
  }

  static Future<void> clearAllLocalData() async {
    // Close database
    if (_db != null) {
      try {
        await _db!.close();
      } catch (_) {}
      _db = null;
    }
    // Delete SQLite file
    try {
      final dbName = 'test.db';
      final dataPath = await _dbFactory.getDatabasesPath();
      final path = join(dataPath, dbName);
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
        debugPrint('Database file test.db deleted successfully.');
      }
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
      debugPrint('SharedPreferences cleared successfully (settings preserved).');
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
    if (kIsWeb || _dbFactory == sqflite_common.databaseFactoryFfi || (!kIsWeb && Platform.environment.containsKey('FLUTTER_TEST'))) {
      return _dbFactory.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 49,
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
      version: 49,
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
          await db.execute("ALTER TABLE Glass ADD COLUMN height REAL NOT NULL DEFAULT 0.0;");
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
          await db.execute(
            "ALTER TABLE Joints ADD COLUMN gasket_type TEXT;",
          );
        } catch (_) {}

        // Treasury: أعمدة الجهة والرصيد
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
          await db.execute("ALTER TABLE Treasury ADD COLUMN old_balance REAL DEFAULT 0.0;");
        } catch (_) {}
        try {
          await db.execute("ALTER TABLE Treasury ADD COLUMN new_balance REAL DEFAULT 0.0;");
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
          // Migrate any existing 'بدون لون / اللون الخام' to 'خام'
          await db.update(
            'Colors',
            {'name': 'خام'},
            where: "name = ?",
            whereArgs: ['بدون لون / اللون الخام'],
          );
          await db.update(
            'GlassColorPrices',
            {'color_name': 'خام'},
            where: "color_name = ?",
            whereArgs: ['بدون لون / اللون الخام'],
          );
          try {
            await db.update(
              'Commandes_details',
              {'color': 'خام'},
              where: "color = ?",
              whereArgs: ['بدون لون / اللون الخام'],
            );
          } catch (_) {}
          try {
            await db.update(
              'Glass',
              {'color': 'خام'},
              where: "color = ?",
              whereArgs: ['بدون لون / اللون الخام'],
            );
          } catch (_) {}

          final check = await db.query(
            'Colors',
            where: "name = ?",
            whereArgs: ['خام'],
          );
          if (check.isEmpty) {
            await db.insert('Colors', {
              'name': 'خام',
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
              custom_formula_notes TEXT DEFAULT '',
              updated_at TEXT NOT NULL DEFAULT ''
            )
          ''');
        } catch (_) {}
        try {
          await db.execute("ALTER TABLE SeriesTableConfig ADD COLUMN sash_w_deduction_2 REAL DEFAULT 0.0;");
        } catch (_) {}
        try {
          await db.execute("ALTER TABLE SeriesTableConfig ADD COLUMN sash_w_deduction_3 REAL DEFAULT 0.0;");
        } catch (_) {}
        try {
          await db.execute("ALTER TABLE SeriesTableConfig ADD COLUMN sash_w_deduction_4 REAL DEFAULT 0.0;");
        } catch (_) {}
        try {
          await db.execute("ALTER TABLE SeriesTableConfig ADD COLUMN sash_overlap_val REAL DEFAULT 0.0;");
        } catch (_) {}
        try {
          await db.execute("ALTER TABLE SeriesTableConfig ADD COLUMN glass_w_deduction REAL DEFAULT 0.0;");
        } catch (_) {}
        try {
          await db.execute("ALTER TABLE SeriesTableConfig ADD COLUMN custom_formula_notes TEXT DEFAULT '';");
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
            "ALTER TABLE ShutterComponents ADD COLUMN cap_thickness REAL NOT NULL DEFAULT 0.0;",
          );
        } catch (_) {}
        try {
          await db.execute(
            "ALTER TABLE ShutterComponents ADD COLUMN weight_per_sqm REAL NOT NULL DEFAULT 0.0;",
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
            if (subtype == 'extruded' || nameLower.contains('extruded') || nameLower.contains('إكسترودي')) {
              defaultWeight = 12.0;
            } else if (nameLower.contains('55') || currentMeas == '55' || currentMeas == '550' || nameLower.contains('٥٥')) {
              defaultWeight = 4.0;
            } else if (nameLower.contains('lame') || nameLower.contains('شريح') || nameLower.contains('شريحة') || nameLower.contains('final')) {
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
          await db.execute(
            "ALTER TABLE Glass ADD COLUMN color TEXT DEFAULT '';",
          );
        } catch (_) {}

        // Ensure Achats has location_id
        try {
          await db.execute(
            "ALTER TABLE Achats ADD COLUMN location_id INTEGER;",
          );
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
            status TEXT NOT NULL DEFAULT 'نشطة',
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
              component_type TEXT NOT NULL,
              qty_mode TEXT NOT NULL DEFAULT 'fixed',
              dimension TEXT,
              base_qty REAL NOT NULL DEFAULT 1,
              unit TEXT NOT NULL DEFAULT 'قطعة',
              sort_order INTEGER NOT NULL DEFAULT 0,
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
            'مفاصل': 'Paumelles',
            'مقبض': 'Poignée Fenêtre',
            'قفل': 'Serrure',
            'قاش': 'Gâche',
            'فيرو': 'Verrou',
            'إسبانيوليت': 'Espagnolette',
            'كانو': 'Canon',
            'سيستم أو بي': 'System OB',
            'ديمي سيستم أو بي': 'Demi System OB',
            'فيرو سنترال': 'Verrou Central',
            'كاش بورت': 'Gâche Porte',
            'كاش كوليسون': 'Gâche Coulissante',
            'كريمون': 'Crémone',
            'بوشون بارك لوز': 'Bouchon Parclose',
            'البراغي': 'Visse',
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
          await db.execute(
            "ALTER TABLE Commandes ADD COLUMN project_id INTEGER;",
          );
        } catch (_) {}

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
        .replaceAll('├⌐', 'é')
        .replaceAll('├¿', 'è')
        .replaceAll('Ã©', 'é')
        .replaceAll('Ã¨', 'è')
        // Replace corrupted Arabic names
        .replaceAll('╪│╪¬╪º╪▒ ╪ú╪¿┘è╪╢', 'ستار أبيض')
        .replaceAll('╪│╪¬╪º╪▒ ╪«╪┤╪¿┘è', 'ستار خشبي')
        .replaceAll('╪│╪¬╪º╪▒ ╪¿┘å┘è/╪«╪┤╪¿┘è', 'ستار بني/خشبي')
        .replaceAll('╪│╪¬╪º╪▒ ╪¿┘å┘è / ╪«╪┤╪¿┘è', 'ستار بني/خشبي')
        .replaceAll('Injecte', 'Injectée')
        .replaceAll('Extrude', 'Extrudée')
        .replaceAll('Glissire', 'Glissière');

    // Ensure common variations are fully normalized
    if (cleaned.toLowerCase() == 'lame injectee' || cleaned.toLowerCase() == 'lame injectée') {
      cleaned = 'Lame Injectée';
    }
    if (cleaned.toLowerCase() == 'lame extrudee' || cleaned.toLowerCase() == 'lame extrudée') {
      cleaned = 'Lame Extrudée';
    }
    if (cleaned.toLowerCase() == 'glissiere 25' || cleaned.toLowerCase() == 'glissière 25') {
      cleaned = 'Glissière 25';
    }
    if (cleaned.toLowerCase() == 'glissiere 120' || cleaned.toLowerCase() == 'glissière 120') {
      cleaned = 'Glissière 120';
    }
    if (cleaned.toLowerCase() == 'glissiere 100' || cleaned.toLowerCase() == 'glissière 100') {
      cleaned = 'Glissière 100';
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
    await _ensureShutterComponentSeeds(db);
  }

  Future<void> _ensureShutterComponentSeeds(DatabaseExecutor db) async {
    final List<Map<String, dynamic>> itemsToSeed = [
      {
        'name': 'المحرك (Moteur)',
        'component_type': 'Moteur',
        'price': 0.0,
        'unit': 'pcs',
        'is_active': 1,
      },
      {
        'name': 'المانيفال (Manivelle)',
        'component_type': 'Manivelle',
        'price': 0.0,
        'unit': 'pcs',
        'is_active': 1,
      },
      {
        'name': 'السكك (Coulisses)',
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
    if (_db != null) return _db!;
    _db = await initDb();
    return _db;
  }

  Future<Database> initDb() async {
    String dbName = 'test.db';

    String path;
    if (kIsWeb) {
      path = dbName;
    } else {
      String dataPath = await _dbFactory.getDatabasesPath();
      path = join(dataPath, dbName);
    }
    final dbPassword = await _resolveDbPassword(dbName);

    if (!kIsWeb) {
      try {
        final dataPath = await _dbFactory.getDatabasesPath();
        final directory = Directory(dataPath);
        if (await directory.exists()) {
          final files = directory.listSync();
          final corruptFiles = files
              .where((f) => f.path.contains('$dbName.corrupt_'))
              .toList()
            ..sort((a, b) => b.path.compareTo(a.path));

          for (var corruptFile in corruptFiles) {
            try {
              final testDb = await _openEncryptedDb(corruptFile.path, dbPassword);
              await testDb.close();

              final activeFile = File(path);
              if (await activeFile.exists()) {
                await activeFile.delete();
              }
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
    if (oldVersion < 18) {
      try {
        await db.execute('''
          CREATE UNIQUE INDEX IF NOT EXISTS idx_achat_items_unique
          ON Achat_items (achat_id, item_id, item_type, color_id)
        ''');
      } catch (e) {
        Text('Could not create unique index on Achat_items: $e');
      }
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
          shutter_subtype TEXT NOT NULL DEFAULT 'normal',
          bar_length_m REAL NOT NULL DEFAULT 0.0,
          motor_diameter TEXT DEFAULT '',
          cap_thickness REAL NOT NULL DEFAULT 0.0
        )
      ''');

      final List<Map<String, dynamic>> shutterSeeds = [
        {
          'name': 'ستار أبيض',
          'type': 'Lame',
          'price': 8000.0,
          'material_type': 'Aluminium',
        },
        {
          'name': 'ستار خشبي',
          'type': 'Lame',
          'price': 12000.0,
          'material_type': 'Aluminium',
        },
      ];
      for (var seed in shutterSeeds) {
        await db.insert('ShutterComponents', seed);
      }
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

    if (oldVersion < 44) {
      try {
        await db.execute(
          "ALTER TABLE Joints ADD COLUMN gasket_type TEXT;",
        );
      } catch (_) {}
    }

    if (oldVersion < 45) {
      try {
        await db.execute(
          "ALTER TABLE Suppliers ADD COLUMN latitude REAL;",
        );
      } catch (_) {}
      try {
        await db.execute(
          "ALTER TABLE Suppliers ADD COLUMN longitude REAL;",
        );
      } catch (_) {}
    }

    if (oldVersion < 46) {
      try {
        await db.execute("ALTER TABLE Client ADD COLUMN nif TEXT NOT NULL DEFAULT '';");
      } catch (_) {}
      try {
        await db.execute("ALTER TABLE Client ADD COLUMN nis TEXT NOT NULL DEFAULT '';");
      } catch (_) {}
      try {
        await db.execute("ALTER TABLE Client ADD COLUMN rc TEXT NOT NULL DEFAULT '';");
      } catch (_) {}
      try {
        await db.execute("ALTER TABLE Client ADD COLUMN ai TEXT NOT NULL DEFAULT '';");
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
        await db.execute("ALTER TABLE Treasury ADD COLUMN old_balance REAL DEFAULT 0.0;");
      } catch (_) {}
      try {
        await db.execute("ALTER TABLE Treasury ADD COLUMN new_balance REAL DEFAULT 0.0;");
      } catch (_) {}
      try {
        await db.execute("ALTER TABLE Treasury ADD COLUMN caisse_name TEXT;");
      } catch (_) {}
      try {
        await db.execute("ALTER TABLE Treasury ADD COLUMN payment_method TEXT;");
      } catch (_) {}
    }

    if (oldVersion < 48) {
      try {
        await db.execute("ALTER TABLE Commandes_deliveries ADD COLUMN is_loaded INTEGER DEFAULT 0;");
      } catch (_) {}
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
      FOREIGN KEY (series_id) REFERENCES Series(id) ON DELETE CASCADE
    )
    ''');

    await db.execute('''
    CREATE TABLE Client (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
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
      updated_at TEXT NOT NULL
    )
    ''');

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
      CREATE UNIQUE INDEX IF NOT EXISTS idx_achat_items_unique
      ON Achat_items (achat_id, item_id, item_type, color_id)
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
      shutter_subtype TEXT NOT NULL DEFAULT 'normal',
      bar_length_m REAL NOT NULL DEFAULT 0.0,
      motor_diameter TEXT DEFAULT '',
      cap_thickness REAL NOT NULL DEFAULT 0.0
    )
    ''');

    final List<Map<String, dynamic>> initialShutters = [
      {
        'name': 'ستار أبيض',
        'component_type': 'Lame',
        'price': 8000.0,
        'unit': 'sqm',
      },
      {
        'name': 'ستار بني/خشبي',
        'component_type': 'Lame',
        'price': 12000.0,
        'unit': 'sqm',
      },
    ];
    for (var shutter in initialShutters) {
      await db.insert('ShutterComponents', shutter);
    }

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
        updated_at TEXT NOT NULL DEFAULT (datetime('now')),
        UNIQUE(item_id, item_type, color_id, location_id)
      )
    ''');

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
        unit TEXT NOT NULL DEFAULT 'قطعة',
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
    return await myDb!.rawQuery(
      'SELECT * FROM Profile ORDER BY name ASC',
    );
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

  Future<List<Map<String, dynamic>>> readAllSeriesByProfile(int profileId) async {
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

  Future<List<Map<String, dynamic>>> getAccessoriesWithPrices(int? seriesId, int? colorId) async {
    final myDb = await db;
    if (myDb == null) return [];

    final List<Map<String, dynamic>> rawAccessories = await myDb.query(
      'Accessories',
      where: 'is_active = 1',
    );

    List<Map<String, dynamic>> result = [];
    for (var acc in rawAccessories) {
      int accId = acc['id'] as int;
      double finalPrice = (acc['price'] as num).toDouble();

      if (colorId != null) {
        final List<Map<String, dynamic>> colorPriceRows = await myDb.query(
          'AccessoryColorPrices',
          columns: ['price'],
          where: 'accessory_id = ? AND color_id = ?',
          whereArgs: [accId, colorId],
        );
        if (colorPriceRows.isNotEmpty) {
          finalPrice = (colorPriceRows.first['price'] as num).toDouble();
        }
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
    var res = await myDb!.insert('SectionColorPrices', {
      'section_id': sectionId,
      'color_id': colorId,
      'price': price,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
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
  }) async {
    Database? myDb = await db;
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
    });
    CloudSyncService().notifyChange();
    return res;
  }

  Future<int> updateSection(int id, Map<String, dynamic> data) async {
    Database? myDb = await db;
    try {
      await myDb!.execute(
        "ALTER TABLE Sections ADD COLUMN allows_side_cover INTEGER NOT NULL DEFAULT 1;",
      );
    } catch (_) {}
    var res = await myDb!.update(
      'Sections',
      data,
      where: 'id = ?',
      whereArgs: [id],
    );
    CloudSyncService().notifyChange();
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
  Future<List<Map<String, dynamic>>> readClient() async {
    Database? myDb = await db;
    return await myDb!.rawQuery('SELECT * FROM Client');
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
    var res = await myDb!.rawInsert(
      'INSERT INTO Client (firstname, lastname, phone1, phone2, email, address, nif, nis, rc, ai, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [firstname, lastname, phone1, phone2, email, address, nif, nis, rc, ai, now, now],
    );
    CloudSyncService().notifyChange();
    return res;
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
    CloudSyncService().notifyChange();
    return res;
  }

  Future<int> deleteClient(int id) async {
    Database? myDb = await db;
    var res = await myDb!.rawDelete('DELETE FROM Client WHERE id = ?', [id]);
    CloudSyncService().notifyChange();
    return res;
  }

  //////////////////////////////////// Measurements //////////////////////////////////////
  Future<int> insertMeasurement(Map<String, dynamic> data) async {
    Database? myDb = await db;
    var res = await myDb!.insert('Measurements', data);
    CloudSyncService().notifyChange();
    return res;
  }

  Future<List<Map<String, dynamic>>> readMeasurements() async {
    Database? myDb = await db;
    return await myDb!.query('Measurements', orderBy: 'id DESC');
  }

  Future<int> deleteMeasurement(int id) async {
    Database? myDb = await db;
    var res = await myDb!.delete('Measurements', where: 'id = ?', whereArgs: [id]);
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

  Future<List<Map<String, dynamic>>> getClientById(int id) async {
    final dbclient = await db;
    return await dbclient!.query('Client', where: 'id = ?', whereArgs: [id]);
  }

  ///////////////////////////////// Projects ////////////////////////////////
  Future<int> insertProject(String name, int clientId, String? description) async {
    Database? myDb = await db;
    final now = DateTime.now().toIso8601String();
    var res = await myDb!.rawInsert(
      'INSERT INTO Projects (name, client_id, description, created_at, updated_at) VALUES (?, ?, ?, ?, ?)',
      [name, clientId, description, now, now],
    );
    CloudSyncService().notifyChange();
    return res;
  }

  Future<int> updateProject(int id, String name, int clientId, String? description) async {
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
    CloudSyncService().notifyChange();
    return res;
  }

  Future<int> deleteProject(int id) async {
    Database? myDb = await db;
    await myDb!.rawUpdate('UPDATE Commandes SET project_id = NULL WHERE project_id = ?', [id]);
    var res = await myDb.rawDelete('DELETE FROM Projects WHERE id = ?', [id]);
    CloudSyncService().notifyChange();
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
    final list = await myDb!.rawQuery('''
      SELECT p.*, c.firstname, c.lastname, c.phone1 as phone, c.email
      FROM Projects p
      INNER JOIN Client c ON p.client_id = c.id
      WHERE p.id = ?
    ''', [id]);
    return list.isNotEmpty ? list.first : null;
  }

  Future<List<Map<String, dynamic>>> readCommandesForProject(int projectId) async {
    Database? myDb = await db;
    return await myDb!.rawQuery('''
      SELECT co.*, cl.firstname, cl.lastname 
      FROM Commandes co
      INNER JOIN Client cl ON co.client_id = cl.id
      WHERE co.project_id = ?
      ORDER BY co.created_at DESC
    ''', [projectId]);
  }

  Future<List<Map<String, dynamic>>> readProjectsForClient(int clientId) async {
    Database? myDb = await db;
    return await myDb!.rawQuery('SELECT * FROM Projects WHERE client_id = ? ORDER BY updated_at DESC', [clientId]);
  }

  ///////////////////////////////// Commande ////////////////////////////////
  Future<List<Map<String, dynamic>>> readCommande() async {
    Database? myDb = await db;
    return await myDb!.rawQuery('SELECT * FROM Commandes');
  }

  Future<List<Map<String, dynamic>>> readCommandesWithClients() async {
    Database? myDb = await db;
    return await myDb!.rawQuery('''
      SELECT c.*,
        COALESCE(NULLIF(TRIM(c.created_at), ''), NULLIF(TRIM(c.updated_at), '')) as created_at,
        cl.firstname, cl.lastname, cl.phone1 as phone,
        p.name as project_name
      FROM Commandes c
      LEFT JOIN Client cl ON c.client_id = cl.id
      LEFT JOIN Projects p ON c.project_id = p.id
      ORDER BY COALESCE(NULLIF(TRIM(c.created_at), ''), NULLIF(TRIM(c.updated_at), ''), c.id) DESC
    ''');
  }

  Future<int> updateCommandeStatus(int id, String newStatus, {bool skipAllocationSync = false}) async {
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

    await _uploadOrderStatusToCloud(id, newStatus);
    CloudSyncService().notifyChange();
    return res;
  }

  Future<void> _uploadOrderStatusToCloud(int orderId, String status) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final workshopId = prefs.getString('workshop_code');
      if (workshopId != null && workshopId.isNotEmpty) {
        await FirebaseFirestore.instance
            .collection('workshops')
            .doc(workshopId)
            .collection('orders_status')
            .doc(orderId.toString())
            .set({
              'id': orderId,
              'status': status,
              'updated_at': FieldValue.serverTimestamp(),
            }, SetOptions(merge: true));
        debugPrint('--- SqlDatabase: Uploaded order status $orderId ($status) to cloud ---');
      }
    } catch (e) {
      debugPrint('Error uploading order status to cloud: $e');
    }
  }

  Future<void> syncOrdersStatusFromCloud() async {
    final prefs = await SharedPreferences.getInstance();
    final workshopId = prefs.getString('workshop_code');
    if (workshopId == null || workshopId.isEmpty) return;

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('workshops')
          .doc(workshopId)
          .collection('orders_status')
          .get();

      Database? myDb = await db;
      if (myDb == null) return;

      for (var doc in snapshot.docs) {
        final orderId = int.tryParse(doc.id);
        if (orderId == null) continue;
        final data = doc.data();
        final cloudStatus = data['status']?.toString() ?? '';
        if (cloudStatus.isEmpty) continue;

        final existing = await myDb.query('Commandes', where: 'id = ?', whereArgs: [orderId]);
        if (existing.isNotEmpty) {
          final currentStatus = existing.first['status']?.toString() ?? '';
          if (currentStatus != cloudStatus) {
            await myDb.update('Commandes', {'status': cloudStatus}, where: 'id = ?', whereArgs: [orderId]);
            await _syncAllocationsFromOrderStatus(orderId, cloudStatus);
          }
        }
      }
      debugPrint('--- SqlDatabase: Synced orders status from cloud successfully ---');
    } catch (e) {
      debugPrint('Error syncing orders status from cloud: $e');
    }
  }

  Future<void> _uploadConfirmedMeasurementsToCloud(int detailId, String instancesJson, String confirmedJson) async {
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
        debugPrint('--- SqlDatabase: Uploaded confirmed measurements for detail $detailId to cloud ---');
      }
    } catch (e) {
      debugPrint('Error uploading confirmed measurements to cloud: $e');
    }
  }

  Future<void> syncConfirmedMeasurementsFromCloud() async {
    final prefs = await SharedPreferences.getInstance();
    final workshopId = prefs.getString('workshop_code');
    if (workshopId == null || workshopId.isEmpty) return;

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('workshops')
          .doc(workshopId)
          .collection('confirmed_measurements')
          .get();

      Database? myDb = await db;
      if (myDb == null) return;

      for (var doc in snapshot.docs) {
        final detailId = int.tryParse(doc.id);
        if (detailId == null) continue;
        final data = doc.data();
        final instancesStr = data['instances_json']?.toString() ?? '';
        final confirmedStr = data['confirmed_mesures_json']?.toString() ?? '';
        if (instancesStr.isEmpty && confirmedStr.isEmpty) continue;

        final existing = await myDb.query('Commandes_details', where: 'id = ?', whereArgs: [detailId]);
        if (existing.isNotEmpty) {
          Map<String, dynamic> updates = {};
          if (instancesStr.isNotEmpty) updates['instances_json'] = instancesStr;
          if (confirmedStr.isNotEmpty) updates['confirmed_mesures_json'] = confirmedStr;

          if (updates.isNotEmpty) {
            await myDb.update('Commandes_details', updates, where: 'id = ?', whereArgs: [detailId]);
          }
        }
      }
      debugPrint('--- SqlDatabase: Synced confirmed measurements from cloud successfully ---');
    } catch (e) {
      debugPrint('Error syncing confirmed measurements from cloud: $e');
    }
  }

  Future<int> updateCommandeDetailConfirmedMesures(int detailId, String instancesJson, String confirmedJson) async {
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

    await _uploadConfirmedMeasurementsToCloud(detailId, instancesJson, confirmedJson);
    CloudSyncService().notifyChange();
    return res;
  }

  Future<void> _syncAllocationsFromOrderStatus(int orderId, String status) async {
    Database? myDb = await db;
    if (myDb == null) return;

    final nowStr = DateTime.now().toIso8601String();
    final details = await readCommandeDetails(orderId);
    if (details.isEmpty) return;

    final sLower = status.trim().toLowerCase();

    final isMfgAll = sLower.contains('full manufacturing') ||
                     sLower.contains('تصنيع كلي') ||
                     sLower.contains('التصنيع الكلي') ||
                     sLower.contains('fabrication totale') ||
                     sLower.contains('full distribution') ||
                     sLower.contains('توزيع كلي') ||
                     sLower.contains('التوزيع الكلي') ||
                     sLower.contains('livraison totale') ||
                     sLower.contains('livré') ||
                     sLower.contains('installation') ||
                     sLower.contains('التركيب') ||
                     sLower.contains('pose') ||
                     sLower.contains('reserve') ||
                     sLower.contains('محجوزة') ||
                     sLower.contains('done') ||
                     sLower.contains('منتهية') ||
                     sLower.contains('تمت');

    final isDistAll = sLower.contains('full distribution') ||
                      sLower.contains('توزيع كلي') ||
                      sLower.contains('التوزيع الكلي') ||
                      sLower.contains('livraison totale') ||
                      sLower.contains('livré') ||
                      sLower.contains('installation') ||
                      sLower.contains('التركيب') ||
                      sLower.contains('pose') ||
                      sLower.contains('reserve') ||
                      sLower.contains('محجوزة') ||
                      sLower.contains('done') ||
                      sLower.contains('منتهية') ||
                      sLower.contains('تمت');

    final isMfgPartial = sLower.contains('partial manufacturing') || sLower.contains('تصنيع جزئي') || sLower.contains('التصنيع الجزئي');
    final isDistPartial = sLower.contains('partial distribution') || sLower.contains('توزيع جزئي') || sLower.contains('التوزيع الجزئي');

    final isPreMfg = sLower == 'pending' ||
                     sLower == 'draft' ||
                     sLower == 'new' ||
                     sLower == 'confirmed' ||
                     sLower == 'in progress' ||
                     sLower.contains('attente') ||
                     sLower.contains('انتظار') ||
                     sLower.contains('مؤكد') ||
                     sLower.contains('قياسات');

    for (var i = 0; i < details.length; i++) {
      final detailId = (details[i]['id'] as num?)?.toInt() ?? 0;
      if (detailId <= 0) continue;
      final allocs = await readWorkerAllocations(detailId);
      for (var j = 0; j < allocs.length; j++) {
        final allocId = (allocs[j]['id'] as num?)?.toInt() ?? 0;
        if (allocId <= 0) continue;
        Map<String, dynamic> updates = {};

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
          updates['manufactured_at'] = nowStr;
          updates['is_glass_installed'] = 1;
          updates['glass_installed_at'] = nowStr;
        }

        if (isDistAll || (isDistPartial && i == 0 && j == 0)) {
          updates['is_distributed'] = 1;
          updates['distributed_at'] = nowStr;
        }

        if (updates.isNotEmpty) {
          await myDb.update('WorkerAllocations', updates, where: 'id = ?', whereArgs: [allocId]);
          await _uploadAllocationStatusToCloud(allocId);
        }
      }
    }
  }

  /// مزامنة آلية لجميع الإسنادات بناءً على حالات جميع الطلبيات المسجلة
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
    final res = await myDb!.rawQuery('''
      SELECT SUM(d.quantity) as total_windows
      FROM Commandes_details d
      JOIN Commandes c ON d.id_commandes = c.id
      WHERE c.id < ? 
        AND c.status NOT IN ('En attente', 'في الانتظار', 'Pending', 'Draft', 'ملغاة')
    ''', [targetOrderId]);

    if (res.isNotEmpty && res.first['total_windows'] != null) {
      return (res.first['total_windows'] as num).toInt();
    }
    return 0;
  }

  Future<Map<String, dynamic>?> readCommandeWithClientById(int id) async {
    Database? myDb = await db;
    final rows = await myDb!.rawQuery(
      '''
      SELECT c.*,
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

  Future<List<Map<String, dynamic>>> readCommandeDetails(int idCommande) async {
    Database? myDb = await db;
    return await myDb!.query(
      'Commandes_details',
      where: 'id_commandes = ?',
      whereArgs: [idCommande],
      orderBy: 'id ASC',
    );
  }

  // ── WorkerAllocations Helpers ─────────────────────────────────────
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
  }) async {
    Database? myDb = await db;
    if (myDb == null) return 0;

    // 🛡️ 1. Hard constraint check: ensure total allocated quantity for this detail does not exceed detail.quantity
    final details = await myDb.query('Commandes_details', where: 'id = ?', whereArgs: [detailId]);
    if (details.isNotEmpty) {
      final totalAllowedQty = (details.first['quantity'] ?? details.first['nbr'] ?? 1) as int;
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
        throw Exception('الكمية المسندة تجاوزت الحد المسموح به ($maxAllowed قطعة). المتبقي للإسناد: ${maxAllowed - currentAllocatedSum}');
      }
    }

    // 🛡️ 2. Clean slate initialization: reset all status flags for new allocation
    final Map<String, dynamic> row = {
      'commande_detail_id': detailId,
      'worker_uid': workerUid,
      'quantity': quantity,
      'worker_price': workerPrice,
      'assigned_at': DateTime.now().toIso8601String(),
      'is_settled': 0,
      'is_manufactured': 0,
      'manufactured_at': null,
      'is_glass_installed': 0,
      'glass_installed_at': null,
      'is_distributed': 0,
      'distributed_at': null,
      'is_transferred_to_dist': 0,
      'transferred_at': null,
    };
    if (unitIndex != null) row['unit_index'] = unitIndex;
    if (unitPosition != null && unitPosition.isNotEmpty) row['unit_position'] = unitPosition;

    final res = await myDb.insert('WorkerAllocations', row);
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

    final allocRow = await myDb.query('WorkerAllocations', where: 'id = ?', whereArgs: [allocationId]);
    if (allocRow.isNotEmpty) {
      final detailId = (allocRow.first['commande_detail_id'] as num?)?.toInt() ?? 0;
      final unitIndex = allocRow.first['unit_index'];
      if (detailId > 0) {
        final details = await myDb.query('Commandes_details', where: 'id = ?', whereArgs: [detailId]);
        if (details.isNotEmpty) {
          final totalAllowedQty = (details.first['quantity'] ?? details.first['nbr'] ?? 1) as int;
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
            throw Exception('الكمية المسندة تجاوزت الحد المسموح به ($maxAllowed قطعة). المتبقي للإسناد: ${maxAllowed - currentAllocatedSum}');
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
        final workshopRef = FirebaseFirestore.instance.collection('workshops').doc(workshopId);

        // 1. كتابة علامة حذف دائمة (tombstone) تمنع restore من إعادة الإسناد المحذوف
        try {
          await workshopRef
              .collection('deleted_allocations')
              .doc(allocationId.toString())
              .set({'deleted_at': FieldValue.serverTimestamp(), 'id': allocationId})
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
                rows.removeWhere((r) => r is Map && ((r['id'] as num?)?.toInt() == allocationId));
                if (rows.length < initialLen) {
                  if (rows.isEmpty) {
                    await chunkDoc.reference.delete().timeout(const Duration(seconds: 5));
                  } else {
                    await chunkDoc.reference.update({'data': rows}).timeout(const Duration(seconds: 5));
                  }
                }
              }
            }
          } catch (e) {
            debugPrint('Error updating chunks for deleted allocation: $e');
          }
        }
        debugPrint('--- SqlDatabase: Deleted allocation $allocationId from cloud ---');
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
      final allocRow = await myDb.query('WorkerAllocations', where: 'id = ?', whereArgs: [allocationId]);
      if (allocRow.isNotEmpty) {
        final detailId = (allocRow.first['commande_detail_id'] as num?)?.toInt() ?? 0;
        if (detailId > 0) {
          final detailRow = await myDb.query('Commandes_details', where: 'id = ?', whereArgs: [detailId]);
          if (detailRow.isNotEmpty) {
            orderId = (detailRow.first['id_commandes'] as num?)?.toInt() ?? 0;
          }
        }
      }
    } catch (_) {}

    // 1. حذف من SQLite أولاً (فوري)
    final res = await myDb.delete(
      'WorkerAllocations',
      where: 'id = ?',
      whereArgs: [allocationId],
    );

    // 2. حذف من السحابة وتسجيل علامة الحذف الدائمة
    await _deleteAllocationFromCloud(allocationId);

    if (orderId > 0) {
      await syncOrderAndAllocationsStatus(orderId);
    }

    // ملاحظة: لا نستدعي backupToCloud() هنا لتجنب التأخر 20+ ثانية.
    // notifyChange() يعمل بـ debounce 1 ثانية ويطلق _silentBackup() تلقائياً.
    CloudSyncService().notifyChange();
    return res;
  }

  /// حذف إسناد محلياً فقط (بدون أي اتصال سحابة) — يُستخدم عند تطبيق tombstones بعد الـ restore
  Future<void> deleteWorkerAllocationLocalOnly(int allocationId) async {
    try {
      Database? myDb = await db;
      if (myDb == null) return;
      await myDb.delete('WorkerAllocations', where: 'id = ?', whereArgs: [allocationId]);
    } catch (e) {
      debugPrint('deleteWorkerAllocationLocalOnly error: $e');
    }
  }

  /// حذف Achat وعناصره محلياً فقط (لا يُشغّل backup) — يُستخدم بعد restore
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

  /// تعطيل سجل زجاج محلياً فقط (is_active=0) — يُستخدم بعد restore
  Future<void> setGlassInactiveLocalOnly(int id) async {
    try {
      Database? myDb = await db;
      if (myDb == null) return;
      await myDb.update('Glass', {'is_active': 0}, where: 'id = ?', whereArgs: [id]);
    } catch (e) {
      debugPrint('setGlassInactiveLocalOnly error: $e');
    }
  }

  /// 🧹 تصفير وحذف جميع المهام والإسنادات محلياً وفي السحابة للتطوير
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
        final workshopRef = FirebaseFirestore.instance.collection('workshops').doc(workshopId);

        // 1. Delete all status docs
        try {
          final statusDocs = await workshopRef.collection('worker_allocations_status').get().timeout(const Duration(seconds: 5));
          for (var doc in statusDocs.docs) {
            await doc.reference.delete().timeout(const Duration(seconds: 3));
          }
        } catch (e) {
          debugPrint('Error clearing status docs: $e');
        }

        // 2. Delete all allocs docs
        try {
          final allocDocs = await workshopRef.collection('allocations').get().timeout(const Duration(seconds: 5));
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
                await doc.reference.delete().timeout(const Duration(seconds: 5));
              }
            }
          } catch (e) {
            debugPrint('Error deleting chunk docs: $e');
          }

          // 4. Update latest backup metadata
          try {
            final latestRef = workshopRef.collection('backups').doc('latest');
            final latestSnap = await latestRef.get().timeout(const Duration(seconds: 5));
            if (latestSnap.exists && latestSnap.data() != null) {
              final map = latestSnap.data()!;
              if (map.containsKey('data_json')) {
                final rawJson = map['data_json']?.toString() ?? '{}';
                try {
                  final Map<String, dynamic> allData = jsonDecode(rawJson);
                  allData['WorkerAllocations'] = [];
                  await latestRef.set({
                    'data_json': jsonEncode(allData),
                    'updated_at': FieldValue.serverTimestamp(),
                  }, SetOptions(merge: true)).timeout(const Duration(seconds: 5));
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

  /// 🧹 تصفير بيانات التركيبات والعمليات الخارجية محلياً وفي السحابة للتطوير
  Future<void> clearAllInstallationDataFromCloudAndLocal() async {
    Database? myDb = await db;
    if (myDb != null) {
      // 1. تصفير حالات التركيب والتحفظ والزجاج بالكامل في WorkerAllocations
      await myDb.rawUpdate('''
        UPDATE WorkerAllocations 
        SET is_transferred_to_dist = 0, transferred_at = NULL,
            is_distributed = 0, distributed_at = NULL,
            is_installed = 0, installed_at = NULL,
            is_glass_installed = 0, glass_installed_at = NULL,
            is_completed = 0, completed_at = NULL,
            has_reserve = 0, reserve_notes = NULL, reserve_at = NULL
      ''');

      // 2. تصفير بيانات استلام الزجاج والمشتريات والنواقص في Commandes_details
      try {
        await myDb.rawUpdate('''
          UPDATE Commandes_details 
          SET glass_status = NULL, glass_received_qty = 0, glass_received_at = NULL,
              glass_supplier = NULL, is_purchased = 0, purchase_status = NULL
        ''');
      } catch (_) {}

      // 3. حذف أي سجلات مستقلة للزجاج والمشتريات
      try { await myDb.rawDelete('DELETE FROM GlassOrders'); } catch (_) {}
      try { await myDb.rawDelete('DELETE FROM Achats'); } catch (_) {}
      try { await myDb.rawDelete('DELETE FROM Commandes_achat'); } catch (_) {}
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

        final latestSnap = await latestRef.get().timeout(const Duration(seconds: 5));
        if (latestSnap.exists && latestSnap.data() != null) {
          final map = latestSnap.data()!;
          if (map.containsKey('data_json')) {
            final rawJson = map['data_json']?.toString() ?? '{}';
            try {
              final Map<String, dynamic> allData = jsonDecode(rawJson);
              if (allData.containsKey('WorkerAllocations') && allData['WorkerAllocations'] is List) {
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
              if (allData.containsKey('Commandes_details') && allData['Commandes_details'] is List) {
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

              await latestRef.set({
                'data_json': jsonEncode(allData),
                'updated_at': FieldValue.serverTimestamp(),
              }, SetOptions(merge: true)).timeout(const Duration(seconds: 5));
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

  /// 🧹 تصفير سجلات المحاسبة محلياً وفي السحابة للتطوير
  Future<void> clearAllWeeklySettlementsFromCloudAndLocal() async {
    Database? myDb = await db;
    if (myDb != null) {
      await myDb.rawUpdate('UPDATE WorkerAllocations SET is_settled = 0, settlement_id = NULL');
      await myDb.rawUpdate('UPDATE WorkerTransactions SET is_settled = 0, settlement_id = NULL');
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
              if (allData.containsKey('WorkerAllocations') && allData['WorkerAllocations'] is List) {
                final List allocs = allData['WorkerAllocations'];
                for (var a in allocs) {
                  if (a is Map) {
                    a['is_settled'] = 0;
                    a['settlement_id'] = null;
                  }
                }
                allData['WorkerAllocations'] = allocs;
              }
              if (allData.containsKey('WorkerTransactions') && allData['WorkerTransactions'] is List) {
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
    return await myDb!.rawQuery('''
      SELECT wa.*, cd.window_type, cd.largeur, cd.hauteur, cd.color, cd.glass, cd.id_commandes, cd.partitions_json, cd.drawing_image_path, cd.drawing_image_base64,
             cl.firstname, cl.lastname
      FROM WorkerAllocations wa
      INNER JOIN Commandes_details cd ON wa.commande_detail_id = cd.id
      INNER JOIN Commandes c ON cd.id_commandes = c.id
      LEFT JOIN Client cl ON c.client_id = cl.id
      WHERE wa.worker_uid = ? AND wa.is_settled = 0
      ORDER BY wa.assigned_at DESC
    ''', [workerUid]);
  }

  Future<List<Map<String, dynamic>>> readWorkerSettledAllocations(
    String workerUid,
  ) async {
    Database? myDb = await db;
    return await myDb!.rawQuery('''
      SELECT wa.*, cd.window_type, cd.largeur, cd.hauteur, cd.color, cd.glass, cd.id_commandes, cd.partitions_json, cd.drawing_image_path, cd.drawing_image_base64,
             cl.firstname, cl.lastname
      FROM WorkerAllocations wa
      INNER JOIN Commandes_details cd ON wa.commande_detail_id = cd.id
      INNER JOIN Commandes c ON cd.id_commandes = c.id
      LEFT JOIN Client cl ON c.client_id = cl.id
      WHERE wa.worker_uid = ? AND wa.is_settled = 1
      ORDER BY wa.settled_at DESC
    ''', [workerUid]);
  }

  Future<List<Map<String, dynamic>>> readWorkerSettledTransactions(
    String workerUid,
  ) async {
    Database? myDb = await db;
    return await myDb!.query(
      'WorkerTransactions',
      where: 'worker_uid = ? AND is_settled = 1',
      orderBy: 'settled_at DESC',
    );
  }

  Future<List<Map<String, dynamic>>> readAllWorkerAllocations(String workerUid, String workerEmail) async {
    Database? myDb = await db;
    if (myDb == null) return [];
    final cleanEmail = workerEmail.trim().toLowerCase();

    // 1. ربط حقيقي للعامل بجميع المعرفات المحتملة (UID، البريد الإلكتروني، أو الاسم)
    try {
      final user = FirebaseAuth.instance.currentUser;
      final cleanName = (user?.displayName ?? '').trim().toLowerCase();

      final allEmps = await myDb.query('Employees');
      for (var emp in allEmps) {
        final eUid = emp['uid']?.toString() ?? '';
        final eEmail = (emp['email']?.toString() ?? '').trim().toLowerCase();
        final eName = (emp['name']?.toString() ?? '').trim().toLowerCase();

        bool isMatch = false;
        if (cleanEmail.isNotEmpty && eEmail.isNotEmpty && cleanEmail == eEmail) {
          isMatch = true;
        } else if (cleanName.isNotEmpty && eName.isNotEmpty && (cleanName == eName || eName.contains(cleanName) || cleanName.contains(eName))) {
          isMatch = true;
        }

        if (isMatch && eUid.isNotEmpty && eUid != workerUid) {
          await linkLocalWorker(eUid, workerUid, cleanEmail.isNotEmpty ? cleanEmail : eEmail);
        }
      }
    } catch (e) {
      debugPrint('Auto link worker allocations error: $e');
    }

    if (cleanEmail.isNotEmpty) {
      try {
        await myDb.rawUpdate('''
          UPDATE WorkerAllocations
          SET worker_uid = ?
          WHERE worker_uid IN (SELECT uid FROM Employees WHERE LOWER(email) = ?)
             OR LOWER(worker_uid) = ?
        ''', [workerUid, cleanEmail, cleanEmail]);
      } catch (e) {
        debugPrint('Auto link worker allocations error: $e');
      }
    }

    // 1.5 مزامنة آلية للإسنادات بناءً على حالات الطلبيات الرئيسية (مثل التصنيع الكلي أو التوزيع الكلي)
    await syncAllAllocationsFromAllOrderStatuses();

    // 2. جلب جميع إسنادات هذا العامل المطابقة بـ UID أو بالبريد الإلكتروني أو معرّف الموظف
    final results = await myDb.rawQuery('''
      SELECT wa.*, cd.window_type, cd.largeur, cd.hauteur, cd.color, cd.glass, cd.drawing_image_path, cd.drawing_image_base64, cd.partitions_json, cd.confirmed_mesures_json,
             cd.id_commandes, cd.accessories, cd.description, cd.quantity as detail_quantity,
             cl.firstname, cl.lastname, e.name as worker_name
      FROM WorkerAllocations wa
      LEFT JOIN Commandes_details cd ON wa.commande_detail_id = cd.id
      LEFT JOIN Commandes c ON cd.id_commandes = c.id
      LEFT JOIN Client cl ON c.client_id = cl.id
      LEFT JOIN Employees e ON (wa.worker_uid = e.uid OR (e.email IS NOT NULL AND LOWER(e.email) = ?) OR CAST(e.id AS TEXT) = wa.worker_uid)
      WHERE (wa.worker_uid = ?
         OR LOWER(wa.worker_uid) = ?
         OR (e.email IS NOT NULL AND e.email != '' AND LOWER(e.email) = ?)
         OR wa.worker_uid IN (SELECT CAST(id AS TEXT) FROM Employees WHERE LOWER(email) = ? OR uid = ?)
         OR wa.worker_uid IN (SELECT uid FROM Employees WHERE LOWER(email) = ? OR CAST(id AS TEXT) = ?))
        AND (wa.is_transferred_to_dist IS NULL OR wa.is_transferred_to_dist = 0)
      ORDER BY wa.assigned_at DESC
    ''', [cleanEmail, workerUid, cleanEmail, cleanEmail, cleanEmail, workerUid, cleanEmail, workerUid]);

    return results;
  }

  /// ربط إسنادات العامل بـ UID الصحيح بعد الاستعادة من السحابة
  Future<void> relinkCurrentWorkerAllocations() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final prefs = await SharedPreferences.getInstance();
      final role = prefs.getString('user_role') ?? 'worker';
      if (role == 'manager' || role == 'admin') return;

      Database? myDb = await db;
      if (myDb == null) return;

      final currentUid = user.uid;
      final currentEmail = (user.email ?? '').trim().toLowerCase();
      if (currentEmail.isEmpty) return;

      final allEmps = await myDb.query('Employees');
      for (var emp in allEmps) {
        final eUid = emp['uid']?.toString() ?? '';
        if (eUid == currentUid) continue;

        final eEmail = (emp['email']?.toString() ?? '').trim().toLowerCase();

        if (eEmail.isNotEmpty && currentEmail == eEmail) {
          debugPrint('relinkCurrentWorkerAllocations: linking $eUid -> $currentUid for email $currentEmail');
          await myDb.transaction((txn) async {
            await txn.update('Employees', {'uid': currentUid},
                where: 'uid = ?', whereArgs: [eUid]);
            await txn.update('WorkerAllocations', {'worker_uid': currentUid},
                where: 'worker_uid = ?', whereArgs: [eUid]);
            await txn.update('WorkerTransactions', {'worker_uid': currentUid},
                where: 'worker_uid = ?', whereArgs: [eUid]);
          });
        }
      }

      await myDb.rawUpdate('''
        UPDATE WorkerAllocations
        SET worker_uid = ?
        WHERE LOWER(worker_uid) = ?
      ''', [currentUid, currentEmail]);

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
      LEFT JOIN Employees e ON wa.worker_uid = e.uid
      WHERE (wa.is_transferred_to_dist IS NULL OR wa.is_transferred_to_dist = 0)
      ORDER BY wa.assigned_at DESC
    ''');
  }

  Future<List<Map<String, dynamic>>> readAllArchivedAllocationsForManager() async {
    Database? myDb = await db;
    if (myDb == null) return [];
    await purgeOldArchivedAllocations();

    final results = await myDb.rawQuery('''
      SELECT wa.*, cd.window_type, cd.largeur, cd.hauteur, cd.color, cd.glass, cd.drawing_image_path, cd.drawing_image_base64, cd.partitions_json,
             cd.id_commandes, cd.accessories, cd.description, cd.quantity as detail_quantity,
             cl.firstname, cl.lastname, e.name as worker_name, c.status as order_status
      FROM WorkerAllocations wa
      LEFT JOIN Commandes_details cd ON wa.commande_detail_id = cd.id
      LEFT JOIN Commandes c ON cd.id_commandes = c.id
      LEFT JOIN Client cl ON c.client_id = cl.id
      LEFT JOIN Employees e ON wa.worker_uid = e.uid
      WHERE wa.is_transferred_to_dist = 1
      ORDER BY wa.transferred_at DESC, wa.assigned_at DESC
    ''');

    final now = DateTime.now();
    final List<Map<String, dynamic>> processed = [];
    for (var row in results) {
      final mutable = Map<String, dynamic>.from(row);
      final transferredAtStr = row['transferred_at']?.toString();
      bool isLocked = (row['archive_locked'] as num?)?.toInt() == 1;
      if (!isLocked && transferredAtStr != null && transferredAtStr.isNotEmpty) {
        try {
          final dt = DateTime.parse(transferredAtStr);
          if (now.difference(dt).inDays >= 7) {
            isLocked = true;
            final allocId = (row['id'] as num?)?.toInt() ?? 0;
            if (allocId > 0) {
              await myDb.update('WorkerAllocations', {'archive_locked': 1}, where: 'id = ?', whereArgs: [allocId]);
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
      Database? myDb = await db;
      if (myDb == null) return;
      
      final row = await myDb.query(
        'WorkerAllocations',
        where: 'id = ?',
        whereArgs: [allocationId],
      );
      if (row.isNotEmpty) {
        final prefs = await SharedPreferences.getInstance();
        final workshopId = prefs.getString('workshop_code');
        if (workshopId != null && workshopId.isNotEmpty) {
          final alloc = row.first;
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
                'is_manufactured': alloc['is_manufactured'] ?? 0,
                'manufactured_at': alloc['manufactured_at'],
                'is_glass_installed': alloc['is_glass_installed'] ?? 0,
                'glass_installed_at': alloc['glass_installed_at'],
                'is_distributed': alloc['is_distributed'] ?? 0,
                'distributed_at': alloc['distributed_at'],
                'is_transferred_to_dist': alloc['is_transferred_to_dist'] ?? 0,
                'transferred_at': alloc['transferred_at'],
                'updated_at': FieldValue.serverTimestamp(),
              }, SetOptions(merge: true));
          debugPrint('--- SqlDatabase: Uploaded allocation status $allocationId to cloud ---');
        }
      }
    } catch (e) {
      debugPrint('Error uploading allocation status to cloud: $e');
    }
  }

  Future<void> syncWorkerAllocationsStatusFromCloud() async {
    final prefs = await SharedPreferences.getInstance();
    final workshopId = prefs.getString('workshop_code');
    if (workshopId == null || workshopId.isEmpty) return;

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('workshops')
          .doc(workshopId)
          .collection('worker_allocations_status')
          .get();

      Database? myDb = await db;
      if (myDb == null) return;

      await myDb.transaction((txn) async {
        for (var doc in snapshot.docs) {
          final allocationId = int.tryParse(doc.id);
          if (allocationId == null) continue;
          final data = doc.data();

          final existing = await txn.query('WorkerAllocations', where: 'id = ?', whereArgs: [allocationId]);
          if (existing.isNotEmpty) {
            await txn.update(
              'WorkerAllocations',
              {
                'worker_uid': data['worker_uid'] ?? existing.first['worker_uid'],
                'quantity': data['quantity'] ?? existing.first['quantity'],
                'worker_price': data['worker_price'] ?? existing.first['worker_price'],
                'unit_index': data['unit_index'] ?? existing.first['unit_index'],
                'unit_position': data['unit_position'] ?? existing.first['unit_position'],
                'is_manufactured': data['is_manufactured'] ?? 0,
                'manufactured_at': data['manufactured_at'],
                'is_glass_installed': data['is_glass_installed'] ?? 0,
                'glass_installed_at': data['glass_installed_at'],
                'is_distributed': data['is_distributed'] ?? 0,
                'distributed_at': data['distributed_at'],
                'is_transferred_to_dist': data['is_transferred_to_dist'] ?? 0,
                'transferred_at': data['transferred_at'],
              },
              where: 'id = ?',
              whereArgs: [allocationId],
            );
          } else if (data['commande_detail_id'] != null && data['worker_uid'] != null) {
            await txn.insert('WorkerAllocations', {
              'id': allocationId,
              'commande_detail_id': data['commande_detail_id'],
              'worker_uid': data['worker_uid'],
              'quantity': data['quantity'] ?? 1,
              'worker_price': data['worker_price'] ?? 0.0,
              'assigned_at': data['assigned_at'] ?? DateTime.now().toIso8601String(),
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
            });
          }
        }
      });
      debugPrint('--- SqlDatabase: Synced allocations status from cloud successfully ---');
    } catch (e) {
      debugPrint('Error syncing worker allocations status: $e');
    }
  }

  Future<void> syncOrderAndAllocationsStatus(int orderId) async {
    try {
      Database? myDb = await db;
      if (myDb == null || orderId <= 0) return;

      final allOrderAllocs = await myDb.rawQuery('''
        SELECT wa.* 
        FROM WorkerAllocations wa
        INNER JOIN Commandes_details cd ON wa.commande_detail_id = cd.id
        WHERE cd.id_commandes = ?
      ''', [orderId]);

      if (allOrderAllocs.isEmpty) return;

      int totalAllocs = allOrderAllocs.length;
      int mfgAllocs = allOrderAllocs.where((wa) => (wa['is_manufactured'] as num?)?.toInt() == 1).length;
      int distAllocs = allOrderAllocs.where((wa) => (wa['is_distributed'] as num?)?.toInt() == 1 || (wa['is_transferred_to_dist'] as num?)?.toInt() == 1).length;
      int installAllocs = allOrderAllocs.where((wa) => (wa['is_installed'] as num?)?.toInt() == 1).length;
      int reserveAllocs = allOrderAllocs.where((wa) => (wa['has_reserve'] as num?)?.toInt() == 1).length;
      int completedAllocs = allOrderAllocs.where((wa) => (wa['is_completed'] as num?)?.toInt() == 1).length;

      String? targetStatus;
      if (completedAllocs >= totalAllocs && totalAllocs > 0 && reserveAllocs == 0) {
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
        final orderRow = await myDb.query('Commandes', where: 'id = ?', whereArgs: [orderId]);
        if (orderRow.isNotEmpty) {
          final currentStatus = orderRow.first['status']?.toString() ?? '';
          if (currentStatus != targetStatus) {
            await updateCommandeStatus(orderId, targetStatus, skipAllocationSync: true);
            debugPrint('syncOrderAndAllocationsStatus: updated order #$orderId status from $currentStatus to $targetStatus');
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

    final details = await myDb.query('Commandes_details', where: 'id_commandes = ?', whereArgs: [orderId]);
    if (details.isEmpty) return false;

    int totalRequiredQty = 0;
    for (final d in details) {
      totalRequiredQty += (d['quantity'] as num?)?.toInt() ?? 0;
    }
    if (totalRequiredQty == 0) return false;

    final manufacturedAllocs = await myDb.rawQuery('''
      SELECT SUM(wa.quantity) as total_mfg_qty
      FROM WorkerAllocations wa
      INNER JOIN Commandes_details cd ON wa.commande_detail_id = cd.id
      WHERE cd.id_commandes = ? AND wa.is_manufactured = 1
    ''', [orderId]);

    int totalMfgQty = 0;
    if (manufacturedAllocs.isNotEmpty && manufacturedAllocs.first['total_mfg_qty'] != null) {
      totalMfgQty = (manufacturedAllocs.first['total_mfg_qty'] as num).toInt();
    }

    return totalMfgQty >= totalRequiredQty;
  }

  Future<void> updateWorkerAllocationManufacturing(int allocationId, int isManufactured) async {
    Database? myDb = await db;
    if (myDb == null) return;
    final nowStr = DateTime.now().toIso8601String();
    
    await myDb.update(
      'WorkerAllocations',
      {
        'is_manufactured': isManufactured,
        'manufactured_at': isManufactured == 1 ? nowStr : null,
      },
      where: 'id = ?',
      whereArgs: [allocationId],
    );

    final allocRow = await myDb.query('WorkerAllocations', where: 'id = ?', whereArgs: [allocationId]);
    if (allocRow.isNotEmpty) {
      final detailId = (allocRow.first['commande_detail_id'] as num?)?.toInt() ?? 0;
      if (detailId > 0) {
        final detailRow = await myDb.query('Commandes_details', where: 'id = ?', whereArgs: [detailId]);
        if (detailRow.isNotEmpty) {
          final orderId = (detailRow.first['id_commandes'] as num?)?.toInt() ?? 0;
          if (orderId > 0) {
            await syncOrderAndAllocationsStatus(orderId);
          }
        }
      }
    }

    await _uploadAllocationStatusToCloud(allocationId);
    CloudSyncService().notifyChange();
  }

  Future<void> updateWorkerAllocationGlass(int allocationId, int isGlassInstalled) async {
    Database? myDb = await db;
    if (myDb == null) return;
    final nowStr = DateTime.now().toIso8601String();
    
    await myDb.update(
      'WorkerAllocations',
      {
        'is_glass_installed': isGlassInstalled,
        'glass_installed_at': isGlassInstalled == 1 ? nowStr : null,
      },
      where: 'id = ?',
      whereArgs: [allocationId],
    );

    final allocRow = await myDb.query('WorkerAllocations', where: 'id = ?', whereArgs: [allocationId]);
    if (allocRow.isNotEmpty) {
      final detailId = (allocRow.first['commande_detail_id'] as num?)?.toInt() ?? 0;
      if (detailId > 0) {
        final detailRow = await myDb.query('Commandes_details', where: 'id = ?', whereArgs: [detailId]);
        if (detailRow.isNotEmpty) {
          final orderId = (detailRow.first['id_commandes'] as num?)?.toInt() ?? 0;
          if (orderId > 0) {
            await syncOrderAndAllocationsStatus(orderId);
          }
        }
      }
    }

    await _uploadAllocationStatusToCloud(allocationId);
    CloudSyncService().notifyChange();
  }

  Future<void> updateWorkerAllocationDistribution(int allocationId, int isDistributed) async {
    Database? myDb = await db;
    if (myDb == null) return;
    final nowStr = DateTime.now().toIso8601String();
    
    await myDb.update(
      'WorkerAllocations',
      {
        'is_distributed': isDistributed,
        'distributed_at': isDistributed == 1 ? nowStr : null,
      },
      where: 'id = ?',
      whereArgs: [allocationId],
    );

    final allocRow = await myDb.query('WorkerAllocations', where: 'id = ?', whereArgs: [allocationId]);
    if (allocRow.isNotEmpty) {
      final detailId = (allocRow.first['commande_detail_id'] as num?)?.toInt() ?? 0;
      if (detailId > 0) {
        final detailRow = await myDb.query('Commandes_details', where: 'id = ?', whereArgs: [detailId]);
        if (detailRow.isNotEmpty) {
          final orderId = (detailRow.first['id_commandes'] as num?)?.toInt() ?? 0;
          if (orderId > 0) {
            await syncOrderAndAllocationsStatus(orderId);
          }
        }
      }
    }

    await _uploadAllocationStatusToCloud(allocationId);
    CloudSyncService().notifyChange();
  }

  Future<void> updateWorkerAllocationTransfer(int allocationId, int isTransferred) async {
    Database? myDb = await db;
    if (myDb == null) return;
    final nowStr = DateTime.now().toIso8601String();
    await myDb.update(
      'WorkerAllocations',
      {
        'is_transferred_to_dist': isTransferred,
        'transferred_at': isTransferred == 1 ? nowStr : null,
      },
      where: 'id = ?',
      whereArgs: [allocationId],
    );

    final allocRow = await myDb.query('WorkerAllocations', where: 'id = ?', whereArgs: [allocationId]);
    if (allocRow.isNotEmpty) {
      final detailId = (allocRow.first['commande_detail_id'] as num?)?.toInt() ?? 0;
      if (detailId > 0) {
        final detailRow = await myDb.query('Commandes_details', where: 'id = ?', whereArgs: [detailId]);
        if (detailRow.isNotEmpty) {
          final orderId = (detailRow.first['id_commandes'] as num?)?.toInt() ?? 0;
          if (orderId > 0) {
            await syncOrderAndAllocationsStatus(orderId);
          }
        }
      }
    }

    await _uploadAllocationStatusToCloud(allocationId);
    CloudSyncService().notifyChange();
  }

  Future<List<Map<String, dynamic>>> readFieldInstallationAllocations() async {
    Database? myDb = await db;
    if (myDb == null) return [];

    final results = await myDb.rawQuery('''
      SELECT wa.*, cd.window_type, cd.largeur, cd.hauteur, cd.color, cd.glass, cd.drawing_image_path, cd.drawing_image_base64, cd.partitions_json,
             cd.id_commandes, cd.accessories, cd.description, cd.quantity as detail_quantity,
             cl.firstname, cl.lastname, cl.id as client_id, e.name as worker_name, c.status as order_status
      FROM WorkerAllocations wa
      INNER JOIN Commandes_details cd ON wa.commande_detail_id = cd.id
      INNER JOIN Commandes c ON cd.id_commandes = c.id
      LEFT JOIN Client cl ON c.client_id = cl.id
      LEFT JOIN Employees e ON wa.worker_uid = e.uid
      WHERE wa.is_transferred_to_dist = 1
        AND (wa.is_completed IS NULL OR wa.is_completed = 0)
      ORDER BY cl.lastname ASC, cl.firstname ASC, cd.id_commandes ASC, wa.id ASC
    ''');
    return results.map((r) => Map<String, dynamic>.from(r)).toList();
  }

  Future<void> updateWorkerAllocationInstallation(int allocationId, int isInstalled) async {
    Database? myDb = await db;
    if (myDb == null) return;
    final nowStr = DateTime.now().toIso8601String();
    await myDb.update(
      'WorkerAllocations',
      {
        'is_installed': isInstalled,
        'installed_at': isInstalled == 1 ? nowStr : null,
      },
      where: 'id = ?',
      whereArgs: [allocationId],
    );

    final allocRow = await myDb.query('WorkerAllocations', where: 'id = ?', whereArgs: [allocationId]);
    if (allocRow.isNotEmpty) {
      final detailId = (allocRow.first['commande_detail_id'] as num?)?.toInt() ?? 0;
      if (detailId > 0) {
        final detailRow = await myDb.query('Commandes_details', where: 'id = ?', whereArgs: [detailId]);
        if (detailRow.isNotEmpty) {
          final orderId = (detailRow.first['id_commandes'] as num?)?.toInt() ?? 0;
          if (orderId > 0) {
            await syncOrderAndAllocationsStatus(orderId);
          }
        }
      }
    }

    await _uploadAllocationStatusToCloud(allocationId);
    CloudSyncService().notifyChange();
  }

  Future<void> updateWorkerAllocationCompletion(int allocationId, int isCompleted) async {
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
      },
      where: 'id = ?',
      whereArgs: [allocationId],
    );

    final allocRow = await myDb.query('WorkerAllocations', where: 'id = ?', whereArgs: [allocationId]);
    if (allocRow.isNotEmpty) {
      final detailId = (allocRow.first['commande_detail_id'] as num?)?.toInt() ?? 0;
      if (detailId > 0) {
        final detailRow = await myDb.query('Commandes_details', where: 'id = ?', whereArgs: [detailId]);
        if (detailRow.isNotEmpty) {
          final orderId = (detailRow.first['id_commandes'] as num?)?.toInt() ?? 0;
          if (orderId > 0) {
            await syncOrderAndAllocationsStatus(orderId);
          }
        }
      }
    }

    await _uploadAllocationStatusToCloud(allocationId);
    CloudSyncService().notifyChange();
  }

  Future<void> updateWorkerAllocationReserve(int allocationId, int hasReserve, String? reserveNotes) async {
    Database? myDb = await db;
    if (myDb == null) return;
    final nowStr = DateTime.now().toIso8601String();
    await myDb.update(
      'WorkerAllocations',
      {
        'has_reserve': hasReserve,
        'reserve_notes': hasReserve == 1 ? reserveNotes : null,
        'reserve_at': hasReserve == 1 ? nowStr : null,
      },
      where: 'id = ?',
      whereArgs: [allocationId],
    );

    final allocRow = await myDb.query('WorkerAllocations', where: 'id = ?', whereArgs: [allocationId]);
    if (allocRow.isNotEmpty) {
      final detailId = (allocRow.first['commande_detail_id'] as num?)?.toInt() ?? 0;
      if (detailId > 0) {
        final detailRow = await myDb.query('Commandes_details', where: 'id = ?', whereArgs: [detailId]);
        if (detailRow.isNotEmpty) {
          final orderId = (detailRow.first['id_commandes'] as num?)?.toInt() ?? 0;
          if (orderId > 0) {
            if (hasReserve == 1) {
              await updateCommandeStatus(orderId, 'Reserve', skipAllocationSync: true);
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
             cl.firstname, cl.lastname, cl.id as client_id, e.name as worker_name, c.status as order_status
      FROM WorkerAllocations wa
      INNER JOIN Commandes_details cd ON wa.commande_detail_id = cd.id
      INNER JOIN Commandes c ON cd.id_commandes = c.id
      LEFT JOIN Client cl ON c.client_id = cl.id
      LEFT JOIN Employees e ON wa.worker_uid = e.uid
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
      final sixMonthsAgo = DateTime.now().subtract(const Duration(days: 180)).toIso8601String();
      await myDb.rawDelete('''
        DELETE FROM WorkerAllocations 
        WHERE is_transferred_to_dist = 1 
          AND transferred_at IS NOT NULL 
          AND transferred_at < ?
      ''', [sixMonthsAgo]);
    } catch (e) {
      debugPrint('purgeOldArchivedAllocations error: $e');
    }
  }

  Future<List<Map<String, dynamic>>> readWorkerArchivedAllocations(String workerUid, String workerEmail) async {
    Database? myDb = await db;
    if (myDb == null) return [];
    await purgeOldArchivedAllocations();
    final cleanEmail = workerEmail.trim().toLowerCase();

    final results = await myDb.rawQuery('''
      SELECT wa.*, cd.window_type, cd.largeur, cd.hauteur, cd.color, cd.glass, cd.drawing_image_path, cd.drawing_image_base64, cd.partitions_json,
             cd.id_commandes, cd.accessories, cd.description, cd.quantity as detail_quantity,
             cl.firstname, cl.lastname, e.name as worker_name, c.status as order_status
      FROM WorkerAllocations wa
      LEFT JOIN Commandes_details cd ON wa.commande_detail_id = cd.id
      LEFT JOIN Commandes c ON cd.id_commandes = c.id
      LEFT JOIN Client cl ON c.client_id = cl.id
      LEFT JOIN Employees e ON (wa.worker_uid = e.uid OR (e.email IS NOT NULL AND LOWER(e.email) = ?))
      WHERE (wa.worker_uid = ?
         OR LOWER(wa.worker_uid) = ?
         OR (e.email IS NOT NULL AND e.email != '' AND LOWER(e.email) = ?))
        AND wa.is_transferred_to_dist = 1
      ORDER BY wa.transferred_at DESC, wa.assigned_at DESC
    ''', [cleanEmail, workerUid, cleanEmail, cleanEmail]);

    final now = DateTime.now();
    final List<Map<String, dynamic>> processed = [];
    for (var row in results) {
      final mutable = Map<String, dynamic>.from(row);
      final transferredAtStr = row['transferred_at']?.toString();
      bool isLocked = (row['archive_locked'] as num?)?.toInt() == 1;
      if (!isLocked && transferredAtStr != null && transferredAtStr.isNotEmpty) {
        try {
          final dt = DateTime.parse(transferredAtStr);
          if (now.difference(dt).inDays >= 7) {
            isLocked = true;
            final allocId = (row['id'] as num?)?.toInt() ?? 0;
            if (allocId > 0) {
              await myDb.update('WorkerAllocations', {'archive_locked': 1}, where: 'id = ?', whereArgs: [allocId]);
            }
          }
        } catch (_) {}
      }
      mutable['is_locked_after_week'] = isLocked;
      processed.add(mutable);
    }
    return processed;
  }

  Future<void> updateWorkerAllocationPrice(int allocationId, double price) async {
    Database? myDb = await db;
    if (myDb == null) return;
    await myDb.update(
      'WorkerAllocations',
      {'worker_price': price},
      where: 'id = ?',
      whereArgs: [allocationId],
    );
    await _uploadAllocationStatusToCloud(allocationId);
    CloudSyncService().notifyChange();
  }

  Future<void> settleWorkerWeek(
    String workerUid,
    int workerId,
    double paymentAmount,
    String recordedBy,
    String workerName,
  ) async {
    Database? myDb = await db;
    if (myDb == null) return;

    final now = DateTime.now().toIso8601String();

    // 1. Calculate total earned from unsettled allocations (only manufactured)
    final List<Map<String, dynamic>> allocations = await myDb.rawQuery(
      "SELECT COALESCE(SUM(quantity * worker_price), 0) as total FROM WorkerAllocations WHERE worker_uid = ? AND is_settled = 0 AND is_manufactured = 1",
      [workerUid],
    );
    final double totalEarned = (allocations.first['total'] as num?)?.toDouble() ?? 0.0;

    // 2. Calculate total advances/loans/payments taken (unsettled)
    final List<Map<String, dynamic>> transactions = await myDb.rawQuery(
      "SELECT COALESCE(SUM(amount), 0) as total FROM WorkerTransactions WHERE worker_uid = ? AND is_settled = 0",
      [workerUid],
    );
    final double totalPaidBefore = (transactions.first['total'] as num?)?.toDouble() ?? 0.0;

    // Net due to worker before this settlement payment
    final double netDueBefore = totalEarned - totalPaidBefore;

    // 3. Mark all current unsettled, manufactured allocations as settled
    await myDb.update(
      'WorkerAllocations',
      {
        'is_settled': 1,
        'settled_at': now,
      },
      where: 'worker_uid = ? AND is_settled = 0 AND is_manufactured = 1',
      whereArgs: [workerUid],
    );

    // 4. Mark all current unsettled transactions as settled
    await myDb.update(
      'WorkerTransactions',
      {
        'is_settled': 1,
        'settled_at': now,
      },
      where: 'worker_uid = ? AND is_settled = 0',
      whereArgs: [workerUid],
    );

    // 5. Record the actual payment made in SQLite WorkerTransactions
    await myDb.insert('WorkerTransactions', {
      'worker_uid': workerUid,
      'amount': paymentAmount,
      'transaction_type': 'salary',
      'note': 'تسوية أسبوعية - دفع أسبوعي',
      'created_at': now,
      'is_settled': 1,
      'settled_at': now,
    });

    // 6. Record in Treasury as Decaissement
    await insertTreasury(
      'Décaissement',
      paymentAmount,
      'تسوية أسبوعية للعامل $workerName',
      entityType: 'Worker',
      entityId: workerId,
      recordedBy: recordedBy,
      createdAt: now,
    );

    // 7. Calculate carryover (the difference)
    final double carryover = paymentAmount - netDueBefore;
    if (carryover != 0.0) {
      await myDb.insert('WorkerTransactions', {
        'worker_uid': workerUid,
        'amount': carryover,
        'transaction_type': 'advance',
        'note': 'رصيد مرحّل من الأسبوع السابق',
        'created_at': now,
        'is_settled': 0,
      });
    }

    CloudSyncService().notifyChange();
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
        'assigned_at': workerUid != null ? DateTime.now().toIso8601String() : null,
      },
      where: 'id = ?',
      whereArgs: [detailId],
    );
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
    Database? myDb = await db;
    final netPayable = total - remise + ((total * tva) / 100);
    final now = DateTime.now().toIso8601String();
    final orderDate = createdAt ?? now;
    var res = await myDb!.rawInsert(
      'INSERT INTO Commandes (client_id, status, description, remise, tva, total, net_payable, advance_payment, payment_status, created_at, updated_at, project_id) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [
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
    if (advancePayment != null) data['advance_payment'] = advancePayment;
    if (paymentStatus != null) data['payment_status'] = paymentStatus;
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

  Future<int> deleteCommande(int id) async {
    Database? myDb = await db;
    if (myDb == null) return 0;
    await myDb.delete(
      'Treasury',
      where: "reference_id = ? AND entity_type = 'Client'",
      whereArgs: [id],
    );
    var res = await myDb.delete('Commandes', where: 'id = ?', whereArgs: [id]);
    CloudSyncService().notifyChange();
    return res;
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
      {'delivered_qty': newDeliveredQty},
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
      {'delivered_qty': 0},
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
      
      final checkMain = await myDb.query('Caisses', where: "name = 'الصندوق الرئيسي'");
      if (checkMain.isEmpty) await myDb.insert('Caisses', {'name': 'الصندوق الرئيسي'});
      final checkSecond = await myDb.query('Caisses', where: "name = 'الصندوق الثاني'");
      if (checkSecond.isEmpty) await myDb.insert('Caisses', {'name': 'الصندوق الثاني'});
      final checkBank = await myDb.query('Caisses', where: "name = 'البنك'");
      if (checkBank.isEmpty) await myDb.insert('Caisses', {'name': 'البنك'});

      // Migrate legacy advance payments from Commandes to Treasury
      final orders = await myDb.query(
        'Commandes',
        where: 'advance_payment > 0',
      );
      for (var order in orders) {
        final orderId = order['id'] as int;
        final advance = (order['advance_payment'] as num).toDouble();
        final clientId = order['client_id'] as int?;
        final createdAt = order['created_at']?.toString() ?? DateTime.now().toIso8601String();

        // Check if there is already a Treasury transaction for this order's payment
        final existing = await myDb.query(
          'Treasury',
          where: "entity_type = 'Client' AND reference_id = ? AND transaction_type = 'Encaissement'",
          whereArgs: [orderId],
        );

        if (existing.isEmpty) {
          // Get client info to add to description
          String clientDesc = 'دفعة لطلبية رقم $orderId';
          if (clientId != null) {
            try {
              final clientRow = await myDb.query('Client', where: 'id = ?', whereArgs: [clientId]);
              if (clientRow.isNotEmpty) {
                final fname = clientRow.first['firstname'] ?? '';
                final lname = clientRow.first['lastname'] ?? '';
                clientDesc = 'دفعة لطلبية رقم $orderId من الزبون: $lname $fname';
              }
            } catch (_) {}
          }

          await myDb.insert('Treasury', {
            'transaction_type': 'Encaissement',
            'amount': advance,
            'description': clientDesc,
            'reference_id': orderId,
            'recorded_by': 'migration',
            'entity_type': 'Client',
            'entity_id': clientId,
            'old_balance': 0.0,
            'new_balance': 0.0,
            'caisse_name': 'الصندوق الرئيسي',
            'payment_method': 'نقداً / Espèce',
            'created_at': createdAt,
          });
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
    return await myDb.query('Caisses', orderBy: 'id ASC');
  }

  Future<int> insertCaisse(String name) async {
    Database? myDb = await db;
    if (myDb == null) return 0;
    final res = await myDb.insert('Caisses', {'name': name});
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
    final res = await myDb.delete(
      'Caisses',
      where: 'id = ?',
      whereArgs: [id],
    );
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
    var res = await myDb!.insert('Commandes_deliveries', {
      'id_commandes': idCommande,
      'client_id': clientId,
      'delivery_date': date,
      'items_json': itemsJson,
      'total_amount': totalAmount,
    });
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

  Future<int> updateCommandeDeliveryIsLoaded(int deliveryId, int isLoaded) async {
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
    var orderData = await myDb!.query(
      'Commandes',
      where: 'id = ?',
      whereArgs: [idCommande],
    );
    if (orderData.isNotEmpty) {
      double currentAdvance =
          (orderData[0]['advance_payment'] as num?)?.toDouble() ?? 0.0;
      double total = (orderData[0]['total'] as num?)?.toDouble() ?? 0.0;
      double newAdvance = currentAdvance + amount;
      String newStatus = newAdvance >= total ? 'Paid' : 'Partial';
      var res = await myDb.update(
        'Commandes',
        {'advance_payment': newAdvance, 'payment_status': newStatus},
        where: 'id = ?',
        whereArgs: [idCommande],
      );
      CloudSyncService().notifyChange();
      return res;
    }
    return 0;
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
        '╪▒┘é┘à ╪º┘ä┘ü╪º╪¬┘ê╪▒╪⌐ ($invoiceNumber) ┘à╪│╪¬╪«╪»┘à ┘à╪│╪¿┘é╪º┘ï! ╪º┘ä╪▒╪¼╪º╪í ╪Ñ╪»╪«╪º┘ä ╪▒┘é┘à ┘ü╪▒┘è╪».',
      );
    }

    var res = await myDb.insert('Achats', {
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
    });
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
  }) async {
    Database? myDb = await db;

    if (await achatItemExists(
      achatId: achatId,
      itemId: itemId,
      itemType: itemType,
      colorId: colorId,
    )) {
      return 0;
    }

    var res = await myDb!.insert('Achat_items', {
      'achat_id': achatId,
      'item_code': itemCode,
      'item_name': itemName,
      'item_type': itemType,
      'item_id': itemId,
      'color_id': colorId,
      'quantity': quantity,
      'price': price,
    });
    CloudSyncService().notifyChange();
    return res;
  }

  Future<int> updateAchatItem(int id, double quantity, double price) async {
    Database? myDb = await db;
    var res = await myDb!.update(
      'Achat_items',
      {'quantity': quantity, 'price': price},
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
      await txn.delete('Treasury', where: "reference_id = ? AND entity_type = 'Supplier'", whereArgs: [id]);
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
      final achatRes = await myDb.query('Achats', columns: ['supplier_id'], where: 'id = ?', whereArgs: [achatId]);
      int? supplierId;
      if (achatRes.isNotEmpty) {
        supplierId = achatRes.first['supplier_id'] as int?;
      }

      await myDb.insert('Treasury', {
        'transaction_type': 'Encaissement',
        'amount': refundedAmount,
        'description': 'استرجاع من المورد - فاتورة مشتريات رقم $achatId',
        'reference_id': achatId,
        'entity_type': 'Supplier',
        'entity_id': supplierId,
        'recorded_by': 'system',
        'created_at': DateTime.now().toIso8601String(),
        'old_balance': 0.0,
        'new_balance': 0.0,
        'caisse_name': 'الصندوق الرئيسي',
        'payment_method': 'نقداً / Espèce',
      });
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
        // ╪º┘ä┘à╪│╪¬┘ê╪»╪╣ ╪º┘ä╪▒╪ª┘è╪│┘è ┘â╪º┘ü╪¬╪▒╪º╪╢┘è
        quantityChange: -qty,
        // ╪«╪╡┘à ╪º┘ä┘â┘à┘è╪⌐
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
    var res = await myDb!.insert('Suppliers', {
      'name': data['name'] ?? '',
      'phone': data['phone'] ?? '',
      'email': data['email'] ?? '',
      'notes': data['notes'] ?? '',
      'latitude': data['latitude'],
      'longitude': data['longitude'],
      'created_at': DateTime.now().toIso8601String(),
    });
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
    
    var res = await myDb!.insert('WorkerTransactions', {
      'worker_uid': workerUid,
      'amount': amount,
      'transaction_type': transactionType,
      'note': note,
      'created_at': now,
    });

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
        
        String desc = (transactionType == 'advance' ? 'سلفة للعامل ' : 'أجرة للعامل ') + workerName;
        if (note.isNotEmpty) desc += ' - $note';

        await insertTreasury(
          'Décaissement',
          amount,
          desc,
          entityType: 'Worker',
          entityId: workerId,
          recordedBy: recordedBy ?? 'system',
          caisseName: caisseName ?? 'الصندوق الرئيسي',
          createdAt: now,
        );
      }
    } catch (e) {
      debugPrint('Error inserting worker transaction to treasury: $e');
    }

    CloudSyncService().notifyChange();
    return res;
  }

  Future<List<Map<String, dynamic>>> readWorkerTransactions(
    String workerUid,
  ) async {
    Database? myDb = await db;
    return await myDb!.query(
      'WorkerTransactions',
      where: 'worker_uid = ?',
      whereArgs: [workerUid],
      orderBy: 'created_at DESC',
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
      {
        'amount': newAmount,
        'transaction_type': newType,
        'note': newNote,
      },
      where: 'id = ?',
      whereArgs: [transactionId],
    );

    final List<Map<String, dynamic>> records = await myDb.query(
      'Treasury',
      where: "transaction_type = 'Décaissement' AND entity_type = 'Worker' AND entity_id = ? AND amount = ?",
      whereArgs: [workerId, oldAmount],
      limit: 1,
    );

    if (records.isNotEmpty) {
      final treasuryId = records.first['id'] as int;
      String desc = (newType == 'advance' ? 'سلفة للعامل ' : 'أجرة للعامل ') + workerName;
      if (newNote.isNotEmpty) desc += ' - $newNote';

      await myDb.update(
        'Treasury',
        {
          'amount': newAmount,
          'description': desc,
        },
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
      where: "transaction_type = 'Décaissement' AND entity_type = 'Worker' AND entity_id = ? AND amount = ?",
      whereArgs: [workerId, amount],
      limit: 1,
    );

    if (records.isNotEmpty) {
      final treasuryId = records.first['id'] as int;
      await myDb.delete(
        'Treasury',
        where: 'id = ?',
        whereArgs: [treasuryId],
      );
    }
    CloudSyncService().notifyChange();
  }


  //////////////////////////////////// Colors //////////////////////////////////////
  Future<List<Map<String, dynamic>>> readColors() async {
    Database? myDb = await db;
    var result = await myDb!.query('Colors', where: 'is_active = 1');
    if (result.isEmpty) {
      await _insertDefaultColors(myDb);
      result = await myDb.query('Colors', where: 'is_active = 1');
    }

    // Clean up any existing duplicates silently
    await cleanDuplicateColors();
    result = await myDb.query('Colors');

    return result;
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
        {'name': '╪ú╪¿┘è╪╢', 'hex_code': '#FFFFFF', 'type': 'Global'},
        {'name': '╪¿┘å┘è', 'hex_code': '#795548', 'type': 'Global'},
        {'name': '╪▒┘à╪º╪»┘è', 'hex_code': '#9E9E9E', 'type': 'Global'},
        {'name': '╪ú╪│┘ê╪»', 'hex_code': '#000000', 'type': 'Global'},
        {'name': '╪¿┘è╪¼', 'hex_code': '#F5F5DC', 'type': 'Global'},
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

    // --- ONE-TIME COLOR MIGRATION ---
    var white = await myDb.query(
      'Colors',
      where: "name COLLATE NOCASE IN ('white', '┘ê╪º┘è╪¬')",
    );
    if (white.isNotEmpty) {
      var abiad = await myDb.query(
        'Colors',
        where: "name = ?",
        whereArgs: ["╪ú╪¿┘è╪╢"],
      );
      if (abiad.isNotEmpty) {
        // Rename old "╪ú╪¿┘è╪╢" (with wrong prices) to "╪┤╪º┘à╪¿╪º┘å"
        await myDb.update(
          'Colors',
          {'name': '╪┤╪º┘à╪¿╪º┘å', 'hex_code': '#F5E6C8'},
          where: "id = ?",
          whereArgs: [abiad.first['id']],
        );
      }
      // Rename English "White" (with correct prices) to "╪ú╪¿┘è╪╢"
      await myDb.update(
        'Colors',
        {'name': '╪ú╪¿┘è╪╢', 'hex_code': '#FFFFFF'},
        where: "id = ?",
        whereArgs: [white.first['id']],
      );

      // Fix Desert Oak & Antique hex codes
      await myDb.rawUpdate(
        "UPDATE Colors SET hex_code = '#CD853F' WHERE name LIKE '%╪»┘è╪▓╪▒%' OR name LIKE '%desert%'",
      );
      await myDb.rawUpdate(
        "UPDATE Colors SET hex_code = '#6E5D4F' WHERE name LIKE '%╪º┘å╪¬┘è┘â%' OR name LIKE '%antique%'",
      );
      await myDb.rawUpdate(
        "UPDATE Colors SET hex_code = '#4E2A14' WHERE name LIKE '%fonce%' OR name LIKE '%foncé%' OR name LIKE '%dark%' OR name LIKE '%╪»╪º┘â┘å%'",
      );
    }
    // ----------------------------------

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

    // --- Ensure Antique, Desert Oak, and Gris 9007 exist and are linked to profiles ---
    try {
      var checkAntique = await myDb.query('Colors', where: "name LIKE '%antique%' OR name LIKE '%انتيك%' OR name LIKE '%╪º┘å╪¬┘è┘â%'");
      int antiqueId;
      if (checkAntique.isEmpty) {
        antiqueId = await myDb.insert('Colors', {
          'name': 'antique - انتيك',
          'hex_code': '#6E5D4F',
          'type': 'Global',
          'is_active': 1,
        });
      } else {
        antiqueId = checkAntique.first['id'] as int;
      }

      var checkDesert = await myDb.query('Colors', where: "name LIKE '%desert%' OR name LIKE '%Oak%' OR name LIKE '%ديزرت%'");
      int desertId;
      if (checkDesert.isEmpty) {
        desertId = await myDb.insert('Colors', {
          'name': 'desert oak - ديزرت اوك',
          'hex_code': '#CD853F',
          'type': 'Global',
          'is_active': 1,
        });
      } else {
        desertId = checkDesert.first['id'] as int;
      }

      var checkGris9007 = await myDb.query('Colors', where: "name LIKE '%9007%' OR name LIKE '%رمادي 9007%'");
      int gris9007Id;
      if (checkGris9007.isEmpty) {
        gris9007Id = await myDb.insert('Colors', {
          'name': 'Gris 9007 / رمادي 9007',
          'hex_code': '#9E9E9E',
          'type': 'Global',
          'is_active': 1,
        });
      } else {
        gris9007Id = checkGris9007.first['id'] as int;
      }

      var profiles = await myDb.query('Profiles');
      for (var p in profiles) {
        final pId = p['id'] as int;
        var linkAntique = await myDb.query('ProfileColors', where: 'profile_id = ? AND color_id = ?', whereArgs: [pId, antiqueId]);
        if (linkAntique.isEmpty) {
          await myDb.insert('ProfileColors', {'profile_id': pId, 'color_id': antiqueId});
        }
        var linkDesert = await myDb.query('ProfileColors', where: 'profile_id = ? AND color_id = ?', whereArgs: [pId, desertId]);
        if (linkDesert.isEmpty) {
          await myDb.insert('ProfileColors', {'profile_id': pId, 'color_id': desertId});
        }
        var linkGris = await myDb.query('ProfileColors', where: 'profile_id = ? AND color_id = ?', whereArgs: [pId, gris9007Id]);
        if (linkGris.isEmpty) {
          await myDb.insert('ProfileColors', {'profile_id': pId, 'color_id': gris9007Id});
        }
      }
    } catch (e) {
      print("Error inserting default profile colors: $e");
    }
  }

  Future<int> insertColor(
    String name,
    String hexCode,
    String type, {
    double price = 0.0,
  }) async {
    Database? myDb = await db;
    var res = await myDb!.insert('Colors', {
      'name': name,
      'hex_code': hexCode,
      'type': type,
      'price': price,
    });
    CloudSyncService().notifyChange();
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
    var res = await myDb!.update(
      'Colors',
      {'name': name, 'hex_code': hexCode, 'type': type, 'price': price},
      where: 'id = ?',
      whereArgs: [id],
    );
    CloudSyncService().notifyChange();
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
    CloudSyncService().notifyChange();
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
    CloudSyncService().notifyChange();
    return res;
  }

  Future<List<int>> getProfilesForColor(int colorId) async {
    Database? myDb = await db;
    var res = await myDb!.query(
      'ProfileColors',
      where: 'color_id = ?',
      whereArgs: [colorId],
    );
    return res.map((e) => e['profile_id'] as int).toList();
  }

  Future<void> setProfilesForColor(int colorId, List<int> profileIds) async {
    Database? myDb = await db;
    await myDb!.delete(
      'ProfileColors',
      where: 'color_id = ?',
      whereArgs: [colorId],
    );
    for (int profileId in profileIds) {
      await myDb.insert('ProfileColors', {
        'profile_id': profileId,
        'color_id': colorId,
      });
    }
  }

  Future<List<Map<String, dynamic>>> getColorsForProfile(int profileId) async {
    Database? myDb = await db;

    var all = await myDb!.query('Colors');
    if (all.isEmpty) {
      await _insertDefaultColors(myDb);
    }

    return await myDb.rawQuery(
      '''
      SELECT c.* FROM Colors c
      INNER JOIN ProfileColors pc ON c.id = pc.color_id
      WHERE pc.profile_id = ? AND c.is_active = 1
      GROUP BY c.id
    ''',
      [profileId],
    );
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
    CloudSyncService().notifyChange();
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
    CloudSyncService().notifyChange();
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
    CloudSyncService().notifyChange();
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
    return await myDb!.query(
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
  }) async {
    Database? myDb = await db;
    var res = await myDb!.insert('Glass', {
      'name': name,
      'type': type,
      'thickness': thickness,
      'price_per_sqm': pricePerSqm,
      'color': color,
      'image_path': imagePath,
      'subtype': subtype,
      'height': height,
      if (visibleWidth != null) 'visible_width': visibleWidth,
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
  }) async {
    Database? myDb = await db;
    var res = await myDb!.update(
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
            .set({
          'id': id,
          'deleted_at': FieldValue.serverTimestamp(),
        });
      }
    } catch (e) {
      debugPrint('Failed to write glass tombstone: $e');
    }

    return res;
  }

  Future<void> setGlassColorPrice(int glassId, String colorName, double price) async {
    Database? myDb = await db;
    await myDb!.insert(
      'GlassColorPrices',
      {
        'glass_id': glassId,
        'color_name': colorName,
        'price': price,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    CloudSyncService().notifyChange();
  }

  //////////////////////////////////// ShutterComponents //////////////////////////////////////
  Future<List<Map<String, dynamic>>> readShutterComponents({bool includeInactive = false}) async {
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
    String? shutterSubtype,
    String? motorDiameter,
    double capThickness = 0.0,
  }) async {
    Database? myDb = await db;
    final String? cleanMeasurement = (measurement == null ||
            measurement.trim().isEmpty ||
            measurement.trim().toLowerCase() == 'null')
        ? null
        : measurement.trim();
    final String? cleanMotorDiameter = (motorDiameter == null ||
            motorDiameter.trim().isEmpty ||
            motorDiameter.trim().toLowerCase() == 'null')
        ? null
        : motorDiameter.trim();
    var res = await myDb!.insert('ShutterComponents', {
      'name': name,
      'component_type': componentType,
      'price': price,
      'unit': unit,
      'bar_length_m': barLengthM,
      'measurement': cleanMeasurement,
      'shutter_subtype': shutterSubtype ?? 'normal',
      'motor_diameter': cleanMotorDiameter,
      'cap_thickness': capThickness,
    });
    CloudSyncService().notifyChange();
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
    String? shutterSubtype,
    String? motorDiameter,
    double capThickness = 0.0,
  }) async {
    Database? myDb = await db;
    final String? cleanMeasurement = (measurement == null ||
            measurement.trim().isEmpty ||
            measurement.trim().toLowerCase() == 'null')
        ? null
        : measurement.trim();
    final String? cleanMotorDiameter = (motorDiameter == null ||
            motorDiameter.trim().isEmpty ||
            motorDiameter.trim().toLowerCase() == 'null')
        ? null
        : motorDiameter.trim();
    var res = await myDb!.update(
      'ShutterComponents',
      {
        'name': name,
        'component_type': componentType,
        'price': price,
        'unit': unit,
        'bar_length_m': barLengthM,
        'measurement': cleanMeasurement,
        'shutter_subtype': shutterSubtype ?? 'normal',
        'motor_diameter': cleanMotorDiameter,
        'cap_thickness': capThickness,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    CloudSyncService().notifyChange();
    return res;
  }

  Future<int> deleteShutterComponent(int id) async {
    Database? myDb = await db;
    var res = await myDb!.update(
      'ShutterComponents',
      {'is_active': 0},
      where: 'id = ?',
      whereArgs: [id],
    );
    CloudSyncService().notifyChange();
    return res;
  }

  Future<int> deleteShutterComponentPermanently(int id) async {
    Database? myDb = await db;
    var res = await myDb!.delete(
      'ShutterComponents',
      where: 'id = ?',
      whereArgs: [id],
    );
    CloudSyncService().notifyChange();
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
    CloudSyncService().notifyChange();
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

  Future<int> insertOrUpdateShutterSqmPrice(String bladeType, int colorId, double price) async {
    Database? myDb = await db;
    if (myDb == null) return 0;
    var res = await myDb.insert(
      'ShutterSqmPrices',
      {
        'blade_type': bladeType,
        'color_id': colorId,
        'price_per_sqm': price,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    CloudSyncService().notifyChange();
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
    CloudSyncService().notifyChange();
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
    var res = await myDb!.insert('Employees', {
      'uid': uid,
      'email': email,
      'name': name,
      'permissions_json': permissionsJson,
      'salary_type': salaryType,
      'base_salary': baseSalary,
      'phone': phone,
      'address': address,
      'job_role': jobRole,
    });
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

  Future<void> linkLocalWorker(String localUid, String newUid, String email) async {
    Database? myDb = await db;
    if (myDb == null) return;
    await myDb.transaction((txn) async {
      await txn.update(
        'Employees',
        {
          'uid': newUid,
          'email': email,
        },
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

  Future<void> allocateClientPayment(int clientId, double amount) async {
    Database? myDb = await db;
    if (myDb == null || amount <= 0) return;

    // Fetch all client orders that are not fully paid
    // i.e. advance_payment < net_payable (or total if net_payable <= 0)
    final orders = await myDb.query(
      'Commandes',
      where: 'client_id = ? AND advance_payment < CASE WHEN net_payable > 0 THEN net_payable ELSE total END',
      whereArgs: [clientId],
      orderBy: 'id ASC', // oldest first
    );

    double remainingPayment = amount;
    for (var row in orders) {
      if (remainingPayment <= 0) break;
      final orderId = row['id'] as int;
      final net = (row['net_payable'] as num?)?.toDouble() ?? 0.0;
      final raw = (row['total'] as num?)?.toDouble() ?? 0.0;
      final total = net > 0 ? net : raw;
      final advance = (row['advance_payment'] as num?)?.toDouble() ?? 0.0;
      
      final needed = total - advance;
      if (needed <= 0) continue;

      if (remainingPayment >= needed) {
        // This order is fully paid
        await myDb.update(
          'Commandes',
          {'advance_payment': total, 'payment_status': 'Paid'},
          where: 'id = ?',
          whereArgs: [orderId],
        );
        remainingPayment -= needed;
      } else {
        // This order is partially paid
        final newAdvance = advance + remainingPayment;
        await myDb.update(
          'Commandes',
          {'advance_payment': newAdvance, 'payment_status': 'Partial'},
          where: 'id = ?',
          whereArgs: [orderId],
        );
        remainingPayment = 0;
      }
    }
  }

  Future<void> allocateSupplierPayment(int supplierId, double amount) async {
    Database? myDb = await db;
    if (myDb == null || amount <= 0) return;

    // Fetch all supplier purchases that are not fully paid
    // i.e. paid_amount < total
    final purchases = await myDb.query(
      'Achats',
      where: 'supplier_id = ? AND paid_amount < total',
      whereArgs: [supplierId],
      orderBy: 'id ASC', // oldest first
    );

    double remainingPayment = amount;
    for (var row in purchases) {
      if (remainingPayment <= 0) break;
      final purchaseId = row['id'] as int;
      final total = (row['total'] as num?)?.toDouble() ?? 0.0;
      final paid = (row['paid_amount'] as num?)?.toDouble() ?? 0.0;
      
      final needed = total - paid;
      if (needed <= 0) continue;

      if (remainingPayment >= needed) {
        // This purchase is fully paid
        await myDb.update(
          'Achats',
          {'paid_amount': total},
          where: 'id = ?',
          whereArgs: [purchaseId],
        );
        remainingPayment -= needed;
      } else {
        // This purchase is partially paid
        final newPaid = paid + remainingPayment;
        await myDb.update(
          'Achats',
          {'paid_amount': newPaid},
          where: 'id = ?',
          whereArgs: [purchaseId],
        );
        remainingPayment = 0;
      }
    }
  }

  Future<void> deallocateClientPayment(int clientId, double amount) async {
    Database? myDb = await db;
    if (myDb == null || amount <= 0) return;

    final orders = await myDb.query(
      'Commandes',
      where: 'client_id = ? AND advance_payment > 0',
      whereArgs: [clientId],
      orderBy: 'id DESC',
    );

    double remainingToReclaim = amount;
    for (var row in orders) {
      if (remainingToReclaim <= 0) break;
      final orderId = row['id'] as int;
      final advance = (row['advance_payment'] as num?)?.toDouble() ?? 0.0;

      if (advance <= 0) continue;

      if (remainingToReclaim >= advance) {
        await myDb.update(
          'Commandes',
          {'advance_payment': 0.0, 'payment_status': 'Unpaid'},
          where: 'id = ?',
          whereArgs: [orderId],
        );
        remainingToReclaim -= advance;
      } else {
        final newAdvance = advance - remainingToReclaim;
        await myDb.update(
          'Commandes',
          {
            'advance_payment': newAdvance,
            'payment_status': newAdvance > 0 ? 'Partial' : 'Unpaid'
          },
          where: 'id = ?',
          whereArgs: [orderId],
        );
        remainingToReclaim = 0;
      }
    }
  }

  Future<void> deallocateSupplierPayment(int supplierId, double amount) async {
    Database? myDb = await db;
    if (myDb == null || amount <= 0) return;

    final purchases = await myDb.query(
      'Achats',
      where: 'supplier_id = ? AND paid_amount > 0',
      whereArgs: [supplierId],
      orderBy: 'id DESC',
    );

    double remainingToReclaim = amount;
    for (var row in purchases) {
      if (remainingToReclaim <= 0) break;
      final purchaseId = row['id'] as int;
      final paid = (row['paid_amount'] as num?)?.toDouble() ?? 0.0;

      if (paid <= 0) continue;

      if (remainingToReclaim >= paid) {
        await myDb.update(
          'Achats',
          {'paid_amount': 0.0},
          where: 'id = ?',
          whereArgs: [purchaseId],
        );
        remainingToReclaim -= paid;
      } else {
        final newPaid = paid - remainingToReclaim;
        await myDb.update(
          'Achats',
          {'paid_amount': newPaid},
          where: 'id = ?',
          whereArgs: [purchaseId],
        );
        remainingToReclaim = 0;
      }
    }
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
    var res = await myDb!.insert('Treasury', {
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
      'created_at': createdAt ?? DateTime.now().toIso8601String(),
    });

    if (entityType == 'Client' && transactionType == 'Encaissement' && entityId != null && referenceId == null) {
      await allocateClientPayment(entityId, amount);
    } else if (entityType == 'Supplier' && transactionType == 'Décaissement' && entityId != null && referenceId == null) {
      await allocateSupplierPayment(entityId, amount);
    }
    
    CloudSyncService().notifyChange();
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
    final type = row['transaction_type'] as String;
    final amount = (row['amount'] as num?)?.toDouble() ?? 0.0;
    final entityType = row['entity_type'] as String?;
    final entityId = row['entity_id'] as int?;

    final res = await myDb.delete(
      'Treasury',
      where: 'id = ?',
      whereArgs: [id],
    );

    if (res > 0) {
      if (entityType == 'Client' && type == 'Encaissement' && entityId != null) {
        await deallocateClientPayment(entityId, amount);
      } else if (entityType == 'Supplier' && type == 'Décaissement' && entityId != null) {
        await deallocateSupplierPayment(entityId, amount);
      }
      CloudSyncService().notifyChange();
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
    final type = row['transaction_type'] as String;
    final oldAmount = (row['amount'] as num?)?.toDouble() ?? 0.0;
    final entityType = row['entity_type'] as String?;
    final entityId = row['entity_id'] as int?;

    final res = await myDb.update(
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

    if (res > 0) {
      final delta = newAmount - oldAmount;
      if (entityType == 'Client' && type == 'Encaissement' && entityId != null) {
        if (delta > 0) {
          await allocateClientPayment(entityId, delta);
        } else if (delta < 0) {
          await deallocateClientPayment(entityId, -delta);
        }
      } else if (entityType == 'Supplier' && type == 'Décaissement' && entityId != null) {
        if (delta > 0) {
          await allocateSupplierPayment(entityId, delta);
        } else if (delta < 0) {
          await deallocateSupplierPayment(entityId, -delta);
        }
      }
      CloudSyncService().notifyChange();
    }
    return res;
  }

  /// حساب رصيد الزبون = مجموع net_payable - advance_payment - مدفوعات الخزينة
  Future<double> getClientBalance(int clientId) async {
    final myDb = await db;
    if (myDb == null) return 0.0;

    // إجمالي الفواتير: net_payable (أو total إذا كان 0) مطروحاً منه advance_payment
    final commandesRes = await myDb.rawQuery(
      '''
      SELECT
        COALESCE(SUM(
          CASE WHEN net_payable > 0 THEN net_payable ELSE total END
        ), 0) as invoices,
        COALESCE(SUM(advance_payment), 0) as advances
      FROM Commandes WHERE client_id = ?
      ''',
      [clientId],
    );
    final totalInvoices = (commandesRes.first['invoices'] as num?)?.toDouble() ?? 0.0;
    final totalAdvances = (commandesRes.first['advances'] as num?)?.toDouble() ?? 0.0;

    // إجمالي ما دُفع من خلال معاملات الخزينة المرتبطة بهذا الزبون
    final treasuryRes = await myDb.rawQuery(
      "SELECT COALESCE(SUM(amount), 0) as total FROM Treasury WHERE entity_type = 'Client' AND entity_id = ? AND transaction_type = 'Encaissement'",
      [clientId],
    );
    final totalTreasuryPaid = (treasuryRes.first['total'] as num?)?.toDouble() ?? 0.0;

    // الرصيد = (فواتير) - (سلفة) - (مدفوعات خزينة). موجب = الزبون مدين للمحل
    return totalInvoices - totalAdvances - totalTreasuryPaid;
  }

  /// حساب رصيد المورد = SUM(total) - SUM(paid_amount) من Achats
  Future<double> getSupplierBalance(int supplierId) async {
    final myDb = await db;
    if (myDb == null) return 0.0;

    final res = await myDb.rawQuery(
      'SELECT COALESCE(SUM(total),0) as bought, COALESCE(SUM(paid_amount),0) as paid FROM Achats WHERE supplier_id = ?',
      [supplierId],
    );
    final bought = (res.first['bought'] as num?)?.toDouble() ?? 0.0;
    final paid = (res.first['paid'] as num?)?.toDouble() ?? 0.0;
    // موجب = نحن مدينون للمورد
    return bought - paid;
  }

  /// حساب رصيد العامل = مجموع المستحقات - مجموع ما دُفع له
  Future<double> getWorkerBalance(int workerId) async {
    final myDb = await db;
    if (myDb == null) return 0.0;

    // مجموع ما دُفع للعامل من الخزينة
    final paidRes = await myDb.rawQuery(
      "SELECT COALESCE(SUM(amount), 0) as total FROM Treasury WHERE entity_type = 'Worker' AND entity_id = ?",
      [workerId],
    );
    final totalPaid = (paidRes.first['total'] as num?)?.toDouble() ?? 0.0;

    // مجموع المستحقات من WorkerTransactions (أجور)
    final earnedRes = await myDb.rawQuery(
      "SELECT COALESCE(SUM(amount), 0) as total FROM WorkerTransactions WHERE worker_uid = ? AND transaction_type = 'salary'",
      [workerId.toString()],
    );
    final totalEarned = (earnedRes.first['total'] as num?)?.toDouble() ?? 0.0;

    // موجب = المحل مدين للعامل
    return totalEarned - totalPaid;
  }

  Future<void> clearPersonalData() async {
    Database? myDb = await db;
    if (myDb == null) return;
    await myDb.transaction((txn) async {
      final tablesToClear = [
        'Client',
        'Commandes',
        'Commandes_details',
        'Achats',
        'Achat_items',
        'Suppliers',
        'Treasury',
        'WorkerTransactions',
        'Employees',
      ];
      for (final table in tablesToClear) {
        try {
          await txn.delete(table);
        } catch (_) {}
      }
    });
  }

  Future<Map<String, dynamic>> exportAllData() async {
    Database? myDb = await db;
    final Map<String, dynamic> allData = {};
    if (myDb == null) return allData;
    await _ensureSyncSchema(myDb);
    final List<String> tables = [
      'Profile',
      'Series',
      'Sections',
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
      'SeriesColorPrices',
      'SectionColorPrices',
      'AccessoryColorPrices',
      'ProfileColors',
      'KitBundles',
      'KitBundleItems',
      'KitItemRanges',
      'KitItemVariants',
      'Treasury',
      'WorkerTransactions',
      'WorkerAllocations',
      'Locations',
      'InventoryTransactions',
      'CurrentStock',
    ];
    for (final table in tables) {
      try {
        final rows = await myDb.query(table);
        allData[table] = rows;
      } catch (_) {
        // If a table is still unavailable, do not upload an empty replacement
        // that can wipe another device during restore.
      }
    }
    return allData;
  }

  Future<void> _ensureSyncSchema(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS Client (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        firstname TEXT NOT NULL,
        lastname TEXT NOT NULL,
        phone1 TEXT,
        phone2 TEXT,
        email TEXT,
        address TEXT,
        created_at TEXT NOT NULL DEFAULT (datetime('now')),
        updated_at TEXT NOT NULL DEFAULT (datetime('now'))
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS Commandes (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
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
        is_active INTEGER NOT NULL DEFAULT 1,
        shutter_subtype TEXT NOT NULL DEFAULT 'normal',
        cap_thickness REAL NOT NULL DEFAULT 0.0
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

    // ShutterSqmPrices — سعر المتر المربع للستار حسب نوع الشفرة واللون
    await db.execute('''
      CREATE TABLE IF NOT EXISTS ShutterSqmPrices (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        blade_type TEXT NOT NULL,
        color_id INTEGER NOT NULL,
        price_per_sqm REAL NOT NULL DEFAULT 0.0,
        UNIQUE(blade_type, color_id)
      )
    ''');

    // Kit Bundle tables — exact schema matching _onUpgrade (v38)
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
        unit TEXT NOT NULL DEFAULT 'قطعة',
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
      "ALTER TABLE ShutterComponents ADD COLUMN is_active INTEGER NOT NULL DEFAULT 1",
      "ALTER TABLE Commandes ADD COLUMN advance_payment REAL NOT NULL DEFAULT 0.0",
      "ALTER TABLE Commandes ADD COLUMN payment_status TEXT NOT NULL DEFAULT 'Unpaid'",
      "ALTER TABLE Commandes ADD COLUMN created_at TEXT NOT NULL DEFAULT (datetime('now'))",
      "ALTER TABLE Commandes ADD COLUMN updated_at TEXT NOT NULL DEFAULT (datetime('now'))",
      "ALTER TABLE Commandes_details ADD COLUMN drawing_image_path TEXT",
      "ALTER TABLE Commandes_details ADD COLUMN window_type TEXT",
      "ALTER TABLE Commandes_details ADD COLUMN partitions_json TEXT",
      "ALTER TABLE Accessories ADD COLUMN material_type TEXT NOT NULL DEFAULT 'Aluminium'",
      "ALTER TABLE Accessories ADD COLUMN scope TEXT NOT NULL DEFAULT 'Global'",
      "ALTER TABLE Accessories ADD COLUMN series_id INTEGER",
      "ALTER TABLE Accessories ADD COLUMN series_ids TEXT",
      "ALTER TABLE Accessories ADD COLUMN screw_count INTEGER NOT NULL DEFAULT 0",
      "ALTER TABLE Accessories ADD COLUMN is_active INTEGER NOT NULL DEFAULT 1",
      "ALTER TABLE Series ADD COLUMN has_three_piece_sash INTEGER NOT NULL DEFAULT 0",
      "ALTER TABLE WorkerAllocations ADD COLUMN is_transferred_to_dist INTEGER DEFAULT 0",
      "ALTER TABLE WorkerAllocations ADD COLUMN transferred_at TEXT",
      "ALTER TABLE WorkerAllocations ADD COLUMN archive_locked INTEGER DEFAULT 0",
    ];
    for (final sql in alters) {
      try {
        await db.execute(sql);
      } catch (_) {}
    }
  }

  Future<Set<String>> _tableColumns(DatabaseExecutor db, String table) async {
    final info = await db.rawQuery('PRAGMA table_info($table)');
    return info.map((row) => row['name'].toString()).toSet();
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

  Future<void> importAllData(Map<String, dynamic> data) async {
    Database? myDb = await db;
    if (myDb == null) return;
    final orderedTables = [
      'Profile',
      'Series',
      'Sections',
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
      'SeriesColorPrices',
      'SectionColorPrices',
      'AccessoryColorPrices',
      'ProfileColors',
      'KitBundles',
      'KitBundleItems',
      'KitItemRanges',
      'KitItemVariants',
      'Treasury',
      'WorkerTransactions',
      'WorkerAllocations',
      'Locations',
      'InventoryTransactions',
      'CurrentStock',
    ];

    // الجداول التي تحتوي على بيانات المستخدم الحساسة.
    // لن يتم مسح هذه الجداول إذا كان الـ payload يعيدها فارغة تماماً،
    // للحماية من حذف البيانات المحلية بسبب استعادة قاعدة بيانات فارغة من السحابة.
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
      'Treasury',
      'WorkerTransactions',
      'WorkerAllocations',
      'InventoryTransactions',
      'CurrentStock',
    };

    await myDb.transaction((txn) async {
      await txn.execute('PRAGMA foreign_keys = OFF');
      await _ensureSyncSchema(txn);

      for (final table in orderedTables.where(data.containsKey)) {
        final rows = data[table] as List<dynamic>? ?? [];

        // حماية: إذا كان الجدول حساساً والـ payload يعيده فارغاً،
        // احتفظ بالبيانات المحلية ولا تمسحها.
        if (sensitiveTransactionalTables.contains(table) && rows.isEmpty) {
          print(
            'importAllData: Skipping wipe of "$table" — payload is empty, keeping local data.',
          );
          continue;
        }

        try {
          await txn.delete(table);
        } catch (e) {
          print('Could not clear table $table before import: $e');
        }
        final columns = await _tableColumns(txn, table);
        for (final row in rows) {
          if (row is! Map) continue;
          try {
            final sanitized = _sanitizeImportRow(Map<String, dynamic>.from(row))
              ..removeWhere((key, value) => !columns.contains(key));
            if (sanitized.isEmpty) continue;
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
      await txn.execute('PRAGMA foreign_keys = ON');
    });
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
        '┘ä╪º ╪¬┘ê╪¼╪» ╪¿┘è╪º┘å╪º╪¬ ┘â╪¬╪º┘ä┘ê╪¼ ╪╡╪º┘ä╪¡╪⌐ ┘ä┘ä╪º╪│╪¬┘è╪▒╪º╪».',
      );
    }
    await importAllData(catalogData);
  }

  Future<String> getDatabaseFilePath() async {
    String dbName = 'test.db';
    if (kIsWeb) {
      return dbName;
    } else {
      String dataPath = await _dbFactory.getDatabasesPath();
      return join(dataPath, dbName);
    }
  }

  Future<void> exportDatabaseFile(BuildContext context) async {
    try {
      if (kIsWeb) {
        throw Exception('النسخ الاحتياطي المباشر لملفات قاعدة البيانات غير مدعوم على الويب. يرجى استخدام تصدير JSON.');
      }
      final dbPath = await getDatabaseFilePath();
      final dbFile = File(dbPath);
      if (!await dbFile.exists()) {
        throw Exception('ملف قاعدة البيانات غير موجود.');
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
            content: Text('تم تصدير ملف قاعدة البيانات بنجاح!', style: TextStyle(fontFamily: 'Cairo')),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('فشل التصدير: $e', style: const TextStyle(fontFamily: 'Cairo')),
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
        final documentsDir = Directory('/storage/emulated/0/Documents/ورشتي');
        try {
          if (!await documentsDir.exists()) {
            await documentsDir.create(recursive: true);
          }
          targetFolderPath = documentsDir.path;
        } catch (_) {
          // 2. Try Download folder as fallback
          final downloadDir = Directory('/storage/emulated/0/Download/ورشتي');
          try {
            if (!await downloadDir.exists()) {
              await downloadDir.create(recursive: true);
            }
            targetFolderPath = downloadDir.path;
          } catch (_) {
            // 3. Try app external storage files directory as ultimate fallback
            final extDir = await getExternalStorageDirectory();
            if (extDir != null) {
              final appCustomDir = Directory('${extDir.path}/ورشتي');
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
        final customDir = Directory('${docDir.path}/ورشتي');
        if (!await customDir.exists()) {
          await customDir.create(recursive: true);
        }
        targetFolderPath = customDir.path;
      }

      if (targetFolderPath != null) {
        final targetFile = File('$targetFolderPath/al_erp_backup.db');
        await dbFile.copy(targetFile.path);
        await prefs.setString('last_auto_backup_date', todayStr);
        debugPrint('--- AutoBackup: Successfully exported to ${targetFile.path} ---');
      }
    } catch (e) {
      debugPrint('--- AutoBackup: Failed to run auto daily backup: $e ---');
    }
  }

  Future<void> importDatabaseFile(BuildContext context) async {
    try {
      if (kIsWeb) {
        throw Exception('استيراد ملف قاعدة البيانات المباشر غير مدعوم على الويب. يرجى استخدام استيراد JSON.');
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
        await initDb();
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم استيراد قاعدة البيانات بنجاح! يرجى إعادة تشغيل التطبيق لتحديث كافة الشاشات.', style: TextStyle(fontFamily: 'Cairo')),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('فشل الاستيراد: $e', style: const TextStyle(fontFamily: 'Cairo')),
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
        final urlString = 'data:application/json;charset=utf-8,${Uri.encodeComponent(jsonStr)}';
        
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('جاري بدء التحميل على المتصفح...', style: TextStyle(fontFamily: 'Cairo')),
            backgroundColor: Colors.blue,
          ),
        );
        
        await launchUrl(Uri.parse(urlString), mode: LaunchMode.externalApplication);
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
              content: Text('تم تصدير نسخة JSON الاحتياطية بنجاح!', style: TextStyle(fontFamily: 'Cairo')),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('فشل تصدير JSON: $e', style: const TextStyle(fontFamily: 'Cairo')),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> importJsonBackup(BuildContext context) async {
    try {
      if (kIsWeb) {
        throw Exception('الرجاء القيام بالاستيراد عبر تطبيق الموبايل.');
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
                content: Text('تم استيراد نسخة JSON الاحتياطية بنجاح! يرجى إعادة تشغيل التطبيق.', style: TextStyle(fontFamily: 'Cairo')),
                backgroundColor: Colors.green,
              ),
            );
          } else {
            throw Exception('تنسيق ملف النسخة الاحتياطية غير صالح.');
          }
        }
      }
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('فشل استيراد JSON: $e', style: const TextStyle(fontFamily: 'Cairo')),
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
          'title': 'طلبية #${c['id']} - حالة: ${c['status']}',
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
              'فاتورة مشتريات #${a['invoice_number']} - ${a['supplier_name']}',
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
          'title': 'زبون جديد: ${c['firstname']} ${c['lastname']}',
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
        'cmdTrend': '—',
        'cliCount': '0',
        'cliTrend': '—',
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
            if (dt.isAfter(seventyTwoHoursAgo) || dt.isAtSameMomentAs(seventyTwoHoursAgo)) {
              cmdRecent++;
            }
          } catch (_) {}
        }
      }

      String cmdTrend = '—';
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
            if (dt.isAfter(seventyTwoHoursAgo) || dt.isAtSameMomentAs(seventyTwoHoursAgo)) {
              cliRecent++;
            }
          } catch (_) {}
        }
      }

      String cliTrend = '—';
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
        'cmdTrend': '—',
        'cliCount': '0',
        'cliTrend': '—',
      };
    }
  }

  /// Returns order counts grouped by status, plus last-6-months monthly totals.
  Future<Map<String, dynamic>> getOrderStatusStats() async {
    final database = await db;
    if (database == null) {
      return {
        'byStatus': <String, int>{},
        'monthly': <String, int>{},
      };
    }
    try {
      final rows = await database.query('Commandes');

      // ── حسب الحالة ─────────────────────────────────────────────────────────
      final Map<String, int> byStatus = {};
      // ── آخر 6 أشهر ─────────────────────────────────────────────────────────
      final Map<String, int> monthly = {};
      final now = DateTime.now();
      for (int i = 5; i >= 0; i--) {
        final m = DateTime(now.year, now.month - i, 1);
        final key = '${m.month}/${m.year}';
        monthly[key] = 0;
      }

      for (final row in rows) {
        // حسب الحالة
        final status = (row['status'] as String?) ?? 'Unknown';
        byStatus[status] = (byStatus[status] ?? 0) + 1;

        // حسب الشهر
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
      where: "component_type IN ('Lame', 'Glissiere', 'blade', 'track') AND (is_active = 1 OR is_active IS NULL)",
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
        where: "type IN ('Lame', 'Glissiere', 'blade', 'track') AND (is_active = 1 OR is_active IS NULL)",
      );
      for (var item in accItems) {
        final name = _cleanEncoding(item['name'].toString());
        final type = item['type']?.toString() ?? '';
        if ((type == 'Lame' || type == 'blade') && !lames.contains(name)) {
          lames.add(name);
        } else if ((type == 'Glissiere' || type == 'track') && !glissieres.contains(name)) {
          glissieres.add(name);
        }
      }
    } catch (_) {}

    if (lames.isEmpty) lames = ['Lame Injectée', 'Lame Extrudée'];
    if (glissieres.isEmpty) glissieres = ['Glissière 25', 'Glissière 120', 'Glissière 100'];

    return {'lames': lames, 'glissieres': glissieres};
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
      await myDb.insert('Locations', {
        'name': '╪º┘ä┘à╪«╪▓┘å ╪º┘ä╪▒╪ª┘è╪│┘è',
        'type': '┘à╪│╪¬┘ê╪»╪╣ ╪▒╪ª┘è╪│┘è',
        'is_active': 1,
      });
      locations = await myDb.query('Locations', orderBy: 'id ASC');
      CloudSyncService().notifyChange();
    }
    for (final location in locations) {
      final name = location['name']?.toString() ?? '';
      final type = location['type']?.toString() ?? '';
      final hasBrokenEncoding =
          name.contains('Ø') ||
          name.contains('Ù') ||
          name.contains('â') ||
          name.contains('╪') ||
          name.contains('┘') ||
          type.contains('Ø') ||
          type.contains('Ù') ||
          type.contains('â') ||
          type.contains('╪') ||
          type.contains('┘');
      if (hasBrokenEncoding) {
        await myDb.update(
          'Locations',
          {'name': 'المستودع الرئيسي', 'type': 'مستودع رئيسي'},
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
  }) async {
    Database? myDb = await db;
    if (myDb == null) return 0;

    final stock = await myDb.query(
      'CurrentStock',
      where: 'item_type = ? AND item_id = ? AND (color_id = ? OR (color_id IS NULL AND ? IS NULL)) AND location_id = ?',
      whereArgs: [itemType, itemId, colorId, colorId, locationId],
    );

    int res;
    if (stock.isEmpty) {
      res = await myDb.insert('CurrentStock', {
        'item_type': itemType,
        'item_id': itemId,
        'color_id': colorId,
        'location_id': locationId,
        'quantity': 0.0,
        'min_qty': minQty,
        'updated_at': DateTime.now().toIso8601String(),
      });
    } else {
      res = await myDb.update(
        'CurrentStock',
        {
          'min_qty': minQty,
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
      await txn.insert('InventoryTransactions', {
        'item_id': itemId,
        'item_type': itemType,
        'color_id': colorId,
        'location_id': locationId,
        'quantity': quantityChange,
        'transaction_type': transactionType,
        'reference_id': referenceId,
        'created_at': DateTime.now().toIso8601String(),
      });

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
        await txn.insert('CurrentStock', {
          'item_id': itemId,
          'item_type': itemType,
          'color_id': colorId,
          'location_id': locationId,
          'quantity': quantityChange,
          'updated_at': DateTime.now().toIso8601String(),
        });
      }
    });
    CloudSyncService().notifyChange();
  }

  Future<List<Map<String, dynamic>>> readAllPossibleStock(
    int locationId,
  ) async {
    Database? myDb = await db;
    if (myDb == null) return [];

    // 1. Fetch current stock for fast lookup
    final stock = await myDb.query(
      'CurrentStock',
      where: 'location_id = ?',
      whereArgs: [locationId],
    );

    Map<String, double> stockMap = {};
    Map<String, double> minQtyMap = {};
    for (var row in stock) {
      String key =
          '${row['item_type']}_${row['item_id']}_${row['color_id'] ?? 0}';
      stockMap[key] = (row['quantity'] as num).toDouble();
      minQtyMap[key] = (row['min_qty'] as num?)?.toDouble() ?? 0.0;
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
    }

    return allItems;
  }

  Future<List<Map<String, dynamic>>> readCurrentStock(int locationId) async {
    Database? myDb = await db;
    if (myDb == null) return [];

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

      String itemName = '┘à╪¼┘ç┘ê┘ä';
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
    Map<String, dynamic> data,
    String idColumn,
  ) async {
    final database = await db;
    if (database == null) return;

    try {
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
      await database.insert(table, data);
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

  /// قراءة كل الـ Kits
  Future<List<Map<String, dynamic>>> readKitBundles() async {
    final database = await db;
    if (database == null) return [];
    return await database.query(
      'KitBundles',
      where: 'is_active = 1',
      orderBy: 'id ASC',
    );
  }

  /// إضافة Kit جديد
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

  /// تعديل Kit
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
      {
        'name': name,
        'description': description,
        'per_leaf': perLeaf ? 1 : 0,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// حذف Kit (ناعم)
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

  // ========================= KIT BUNDLE ITEMS CRUD =========================

  /// قراءة مركبات Kit محدد
  Future<List<Map<String, dynamic>>> readKitBundleItems(int kitId) async {
    final database = await db;
    if (database == null) return [];
    return await database.query(
      'KitBundleItems',
      where: 'kit_id = ?',
      whereArgs: [kitId],
      orderBy: 'sort_order ASC, id ASC',
    );
  }

  /// إضافة مركب لـ Kit
  Future<int> insertKitBundleItem({
    required int kitId,
    required String componentType,
    required String qtyMode, // 'fixed' | 'by_range' | 'by_variant'
    String? dimension,       // 'leaf_height' | 'leaf_width' | null
    double baseQty = 1,
    String unit = 'قطعة',
    int sortOrder = 0,
  }) async {
    final database = await db;
    if (database == null) return -1;
    return await database.insert('KitBundleItems', {
      'kit_id': kitId,
      'component_type': componentType,
      'qty_mode': qtyMode,
      'dimension': dimension,
      'base_qty': baseQty,
      'unit': unit,
      'sort_order': sortOrder,
    });
  }

  /// تعديل مركب Kit
  Future<void> updateKitBundleItem(
    int id, {
    required String componentType,
    required String qtyMode,
    String? dimension,
    required double baseQty,
    required String unit,
    required int sortOrder,
  }) async {
    final database = await db;
    if (database == null) return;
    await database.update(
      'KitBundleItems',
      {
        'component_type': componentType,
        'qty_mode': qtyMode,
        'dimension': dimension,
        'base_qty': baseQty,
        'unit': unit,
        'sort_order': sortOrder,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// حذف مركب Kit
  Future<void> deleteKitBundleItem(int id) async {
    final database = await db;
    if (database == null) return;
    await database.delete('KitBundleItems', where: 'id = ?', whereArgs: [id]);
    // تُحذف النطاقات والمتغيرات تلقائياً بسبب ON DELETE CASCADE
  }

  // ========================= KIT ITEM RANGES CRUD =========================

  /// قراءة نطاقات مركب محدد
  Future<List<Map<String, dynamic>>> readKitItemRanges(int itemId) async {
    final database = await db;
    if (database == null) return [];
    return await database.query(
      'KitItemRanges',
      where: 'item_id = ?',
      whereArgs: [itemId],
      orderBy: 'min_mm ASC',
    );
  }

  /// إضافة نطاق
  Future<int> insertKitItemRange({
    required int itemId,
    required double minMm,
    required double maxMm,
    required String productName,
    double price = 0.0,
    double qty = 1,
  }) async {
    final database = await db;
    if (database == null) return -1;
    return await database.insert('KitItemRanges', {
      'item_id': itemId,
      'min_mm': minMm,
      'max_mm': maxMm,
      'product_name': productName,
      'price': price,
      'qty': qty,
    });
  }

  /// تعديل نطاق
  Future<void> updateKitItemRange(
    int id, {
    required double minMm,
    required double maxMm,
    required String productName,
    required double price,
    required double qty,
  }) async {
    final database = await db;
    if (database == null) return;
    await database.update(
      'KitItemRanges',
      {
        'min_mm': minMm,
        'max_mm': maxMm,
        'product_name': productName,
        'price': price,
        'qty': qty,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// حذف نطاق
  Future<void> deleteKitItemRange(int id) async {
    final database = await db;
    if (database == null) return;
    await database.delete('KitItemRanges', where: 'id = ?', whereArgs: [id]);
  }

  /// البحث عن النطاق المناسب لقياس معين
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

  /// قراءة متغيرات مركب محدد
  Future<List<Map<String, dynamic>>> readKitItemVariants(int itemId) async {
    final database = await db;
    if (database == null) return [];
    return await database.query(
      'KitItemVariants',
      where: 'item_id = ?',
      whereArgs: [itemId],
    );
  }

  /// إضافة متغير (simple/double ouvrant)
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

  /// تعديل متغير
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

  /// حذف متغير
  Future<void> deleteKitItemVariant(int id) async {
    final database = await db;
    if (database == null) return;
    await database.delete(
      'KitItemVariants',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// قراءة كل مركبات Kit مع نطاقاتها ومتغيراتها — للحساب في BOM
  Future<List<Map<String, dynamic>>> readKitBundleItemsWithDetails(
    int kitId,
  ) async {
    final database = await db;
    if (database == null) return [];
    final items = await readKitBundleItems(kitId);
    final result = <Map<String, dynamic>>[];
    for (final item in items) {
      final itemId = item['id'] as int;
      final ranges = await readKitItemRanges(itemId);
      final variants = await readKitItemVariants(itemId);
      result.add({
        ...item,
        'ranges': ranges,
        'variants': variants,
      });
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
        c.name as blade_name
      FROM ShutterBoxLimits l
      LEFT JOIN ShutterComponents c ON l.blade_id = c.id
      ORDER BY c.name ASC, l.box_size ASC
    ''');
  }

  Future<int> insertShutterBoxLimit(int boxSize, int bladeId, double maxHeight) async {
    final myDb = await db;
    if (myDb == null) return -1;
    final res = await myDb.insert('ShutterBoxLimits', {
      'box_size': boxSize,
      'blade_id': bladeId,
      'max_height': maxHeight,
    });
    CloudSyncService().notifyChange();
    return res;
  }

  Future<int> updateShutterBoxLimit(int id, int boxSize, int bladeId, double maxHeight) async {
    final myDb = await db;
    if (myDb == null) return -1;
    final res = await myDb.update(
      'ShutterBoxLimits',
      {
        'box_size': boxSize,
        'blade_id': bladeId,
        'max_height': maxHeight,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    CloudSyncService().notifyChange();
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
    CloudSyncService().notifyChange();
    return res;
  }

  // ── Caisson Tunnel Prices ─────────────────────────────────────────────────

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
    await myDb.execute('''
      INSERT INTO CaissonTunnelPrices (color_id, profile_price_per_bar, bottom_cover_price_per_bar, price_per_meter)
      VALUES (?, ?, ?, ?)
      ON CONFLICT(color_id) DO UPDATE SET
        profile_price_per_bar = excluded.profile_price_per_bar,
        bottom_cover_price_per_bar = excluded.bottom_cover_price_per_bar,
        price_per_meter = excluded.price_per_meter
    ''', [colorId, profilePricePerBar, bottomCoverPricePerBar, pricePerMeter]);
    CloudSyncService().notifyChange();
  }

  Future<int> deleteCaissonTunnelPrice(int id) async {
    final myDb = await db;
    if (myDb == null) return -1;
    final res = await myDb.delete(
      'CaissonTunnelPrices',
      where: 'id = ?',
      whereArgs: [id],
    );
    CloudSyncService().notifyChange();
    return res;
  }

  // ── Series Table Config ───────────────────────────────────────────────────

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
    String customFormulaNotes = '',
  }) async {
    final myDb = await db;
    if (myDb == null) return;
    await myDb.execute('''
      INSERT INTO SeriesTableConfig (
        series_id, allowed_section_types, allowed_accessory_ids, allowed_accessory_types, excluded_accessory_ids,
        sash_w_deduction_2, sash_w_deduction_3, sash_w_deduction_4, sash_overlap_val, glass_w_deduction, custom_formula_notes, updated_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
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
        custom_formula_notes = excluded.custom_formula_notes,
        updated_at = excluded.updated_at
    ''', [
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
      customFormulaNotes,
      DateTime.now().toIso8601String(),
    ]);
    CloudSyncService().notifyChange();
  }
}

