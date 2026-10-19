part of '../sql_database.dart';

/// Opening the database, creating and upgrading its schema, legacy repairs and seeds.
extension SqlDatabaseSchema on SqlDatabase {
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
      return SqlDatabase._dbFactory.openDatabase(
        path,
        // FFI/web require their own options implementation. SQLCipher's
        // similarly named options fail the factory's runtime type cast.
        options: sqflite_common.OpenDatabaseOptions(
          version: 71,
          onConfigure: (db) async {
            // Enable WAL mode (Write-Ahead Logging) so concurrent reads do not block
            // writes and background sync transactions do not freeze the UI thread.
            await db.rawQuery('PRAGMA journal_mode = WAL;');
            await db.rawQuery('PRAGMA busy_timeout = 30000;');
            await db.rawQuery('PRAGMA synchronous = NORMAL;');
          },
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
      version: 71,
      password: password,
      onConfigure: (db) async {
        await db.rawQuery('PRAGMA journal_mode = WAL;');
        await db.rawQuery('PRAGMA busy_timeout = 30000;');
        await db.rawQuery('PRAGMA synchronous = NORMAL;');
      },
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
      'Joints',
      'Glass',
      'ShutterComponents',
      'Locations',
    ];
    try {
      await db.execute("ALTER TABLE Profile ADD COLUMN code TEXT DEFAULT '';");
    } catch (_) {}
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
      // Preserve the order chosen by the user when an order is edited.
      await db.execute(
        "ALTER TABLE Commandes_details ADD COLUMN sort_order INTEGER NOT NULL DEFAULT 0;",
      );
    } catch (_) {}
    try {
      // Glass sizes corrected at glass reception. They used to overwrite
      // confirmed_mesures_json, which holds the window measurements.
      await db.execute(
        "ALTER TABLE Commandes_details ADD COLUMN glass_override_json TEXT;",
      );
    } catch (_) {}
    try {
      await _moveLegacyGlassOverrides(db);
    } catch (error) {
      debugPrint('Legacy glass override migration skipped: $error');
    }
    try {
      await db.execute("ALTER TABLE Commandes ADD COLUMN updated_by TEXT;");
    } catch (_) {}
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
    await _migratePendingOrdersToNouveau(db);
    await _ensureDeliveriesLoadedColumn(db);
    await _ensureAccessoryRulesColumns(db);
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
    try {
      await db.execute('ALTER TABLE Client ADD COLUMN latitude REAL;');
    } catch (_) {}
    try {
      await db.execute('ALTER TABLE Client ADD COLUMN longitude REAL;');
    } catch (_) {}

    // Migrations for Achats (workshop vs store separation & internal purchases)
    try {
      await db.execute(
        "ALTER TABLE Achats ADD COLUMN activity_type TEXT NOT NULL DEFAULT 'workshop';",
      );
    } catch (_) {}
    try {
      await db.execute(
        "ALTER TABLE Achats ADD COLUMN is_workshop INTEGER NOT NULL DEFAULT 1;",
      );
    } catch (_) {}
    try {
      await db.execute(
        "ALTER TABLE Achats ADD COLUMN is_internal INTEGER NOT NULL DEFAULT 0;",
      );
    } catch (_) {}
    try {
      await db.execute("ALTER TABLE Achats ADD COLUMN linked_sale_id INTEGER;");
    } catch (_) {}
    for (final statement in [
      "ALTER TABLE Achats ADD COLUMN created_by TEXT NOT NULL DEFAULT '';",
      "ALTER TABLE Achats ADD COLUMN updated_by TEXT NOT NULL DEFAULT '';",
      "ALTER TABLE Achats ADD COLUMN inserted_at TEXT NOT NULL DEFAULT '';",
      "ALTER TABLE MaterialSales ADD COLUMN created_by TEXT NOT NULL DEFAULT '';",
      "ALTER TABLE MaterialSales ADD COLUMN updated_by TEXT NOT NULL DEFAULT '';",
    ]) {
      try {
        await db.execute(statement);
      } catch (_) {}
    }

    // Migrations for MaterialSales (internal sales to workshop)
    try {
      await db.execute(
        "ALTER TABLE MaterialSales ADD COLUMN is_internal INTEGER NOT NULL DEFAULT 0;",
      );
    } catch (_) {}
    try {
      await db.execute(
        "ALTER TABLE MaterialSales ADD COLUMN dest_location_id INTEGER;",
      );
    } catch (_) {}
    try {
      await db.execute(
        "ALTER TABLE MaterialSales ADD COLUMN linked_achat_id INTEGER;",
      );
    } catch (_) {}
    try {
      await db.execute(
        "ALTER TABLE MaterialSales ADD COLUMN source_sale_id INTEGER;",
      );
    } catch (_) {}
    try {
      await db.execute(
        "ALTER TABLE MaterialSales ADD COLUMN converted_to_sale_id INTEGER;",
      );
    } catch (_) {}
    try {
      await db.execute(
        "ALTER TABLE MaterialSaleItems ADD COLUMN tax_rate REAL NOT NULL DEFAULT 0.0;",
      );
    } catch (_) {}
    try {
      await db.execute(
        "ALTER TABLE MaterialSaleItems ADD COLUMN series_name TEXT NOT NULL DEFAULT '';",
      );
    } catch (_) {}
    try {
      await db.execute(
        "ALTER TABLE MaterialSaleItems ADD COLUMN system_name TEXT NOT NULL DEFAULT '';",
      );
    } catch (_) {}

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

    // ── جدول الأعمال اليومية (عمل يومي) ──────────────────────────────────
    try {
      await db.execute('''
            CREATE TABLE IF NOT EXISTS WorkerDailyJobs (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              worker_uid TEXT NOT NULL,
              work_date TEXT NOT NULL,
              title TEXT NOT NULL DEFAULT 'عمل يومي',
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
    try {
      await db.execute(
        'ALTER TABLE Sections ADD COLUMN visible_width_2 REAL NOT NULL DEFAULT 0.0;',
      );
    } catch (_) {}
    try {
      await db.execute(
        'ALTER TABLE Sections ADD COLUMN bar_length REAL NOT NULL DEFAULT 5.8;',
      );
    } catch (_) {}
    try {
      await db.execute(
        'ALTER TABLE Profile ADD COLUMN default_bar_length REAL NOT NULL DEFAULT 5.8;',
      );
    } catch (_) {}
    try {
      await db.execute(
        'ALTER TABLE Series ADD COLUMN price_per_meter REAL NOT NULL DEFAULT 0.0;',
      );
    } catch (_) {}
    try {
      await db.execute(
        'ALTER TABLE Series ADD COLUMN has_three_piece_sash INTEGER NOT NULL DEFAULT 0;',
      );
    } catch (_) {}
    try {
      await db.execute(
        'ALTER TABLE Series ADD COLUMN has_face_to_face INTEGER NOT NULL DEFAULT 0;',
      );
    } catch (_) {}
    try {
      await db.execute(
        "ALTER TABLE Series ADD COLUMN reinforcement_type TEXT DEFAULT 'full_substitution';",
      );
    } catch (_) {}

    await _ensureSeriesDesignTables(db);
    await _ensureSectionSharingSchema(db);
    await _ensureProfileCalculationRulesTable(db);
    await _ensureClientCodeInfrastructure(db);
    await _ensureOrderCodeInfrastructure(db);
    await _ensureOrderTrashInfrastructure(db);
    await _ensureOrderPinningInfrastructure(db);
    await _ensureAchatTrashInfrastructure(db);
    await _ensureRemnantInventorySchema(db);
    await _ensureAdvancedKitCompatibilitySchema(db);
    await _ensureDecorPanelDesignSchema(db);
    await _ensurePaymentAllocationSchema(db);
    await _ensureTreasuryDocumentType(db);
    await _ensureSyncTombstoneInfrastructure(db);
    await _ensureTemperedGlassItemsTable(db);
    await _ensureTemperedGlassSystemsAndRulesTables(db);
    await _ensureVROHandlesAndColorsSeeded(db);
    await _ensureTemperedGlassServicesSeeded(db);
    await _backfillClientCodes(db);
    await _backfillOrderCodes(db);
    await _ensurePerformanceIndexes(db);

    // Automatically link section and profile images based on their codes
    try {
      final sections = await db.query('Sections');
      for (var sec in sections) {
        final id = sec['id'];
        final code = sec['code']?.toString() ?? '';
        if (code.isNotEmpty) {
          final normalizedCode = code.replaceFirst(
            RegExp(r'\.(png|jpe?g|jpeg|svg|webp)$', caseSensitive: false),
            '',
          );
          final expectedPath = 'assets/sections/$normalizedCode.png';
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
          final normalizedCode = code.replaceFirst(
            RegExp(r'\.(png|jpe?g|jpeg|svg|webp)$', caseSensitive: false),
            '',
          );
          final expectedPath = 'assets/sections/$normalizedCode.png';
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
              sliding_chicane_pieces_per_junction INTEGER DEFAULT 1,
              sliding_rail_clearance REAL DEFAULT 1.0,
              custom_formula_notes TEXT DEFAULT '',
              max_sliding_sashes INTEGER DEFAULT 0,
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
    try {
      await db.execute(
        'ALTER TABLE SeriesTableConfig ADD COLUMN max_sliding_sashes INTEGER DEFAULT 0;',
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
            nameLower.contains('إكسترودي')) {
          defaultWeight = 12.0;
        } else if (nameLower.contains('55') ||
            currentMeas == '55' ||
            currentMeas == '550' ||
            nameLower.contains('٥٥')) {
          defaultWeight = 4.0;
        } else if (nameLower.contains('lame') ||
            nameLower.contains('شريح') ||
            nameLower.contains('شريحة') ||
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
            status TEXT NOT NULL DEFAULT 'نشطة',
            created_at TEXT NOT NULL DEFAULT (datetime('now')),
            updated_at TEXT NOT NULL DEFAULT (datetime('now')),
            created_by TEXT NOT NULL DEFAULT '',
            updated_by TEXT NOT NULL DEFAULT '',
            inserted_at TEXT NOT NULL DEFAULT (datetime('now')),
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
              unit TEXT NOT NULL DEFAULT 'قطعة',
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
              accessory_id INTEGER,
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
        .replaceAll('â•ªâ”‚â•ªÂ¬â•ªÂºâ•ªâ–’ â•ªÃºâ•ªÂ¿â”˜Ã¨â•ªâ•¢', 'ستار أبيض')
        .replaceAll('â•ªâ”‚â•ªÂ¬â•ªÂºâ•ªâ–’ â•ªÂ«â•ªâ”¤â•ªÂ¿â”˜Ã¨', 'ستار خشبي')
        .replaceAll(
          'â•ªâ”‚â•ªÂ¬â•ªÂºâ•ªâ–’ â•ªÂ¿â”˜Ã¥â”˜Ã¨/â•ªÂ«â•ªâ”¤â•ªÂ¿â”˜Ã¨',
          'ستار بني/خشبي',
        )
        .replaceAll(
          'â•ªâ”‚â•ªÂ¬â•ªÂºâ•ªâ–’ â•ªÂ¿â”˜Ã¥â”˜Ã¨ / â•ªÂ«â•ªâ”¤â•ªÂ¿â”˜Ã¨',
          'ستار بني/خشبي',
        )
        .replaceAll('Injecte', 'Injectée')
        .replaceAll('Extrude', 'Extrudée')
        .replaceAll('Glissire', 'Glissière');

    // Ensure common variations are fully normalized
    if (cleaned.toLowerCase() == 'lame injectee' ||
        cleaned.toLowerCase() == 'lame injectée') {
      cleaned = 'Lame Injectée';
    }
    if (cleaned.toLowerCase() == 'lame extrudee' ||
        cleaned.toLowerCase() == 'lame extrudée') {
      cleaned = 'Lame Extrudée';
    }
    if (cleaned.toLowerCase() == 'glissiere 25' ||
        cleaned.toLowerCase() == 'glissière 25') {
      cleaned = 'Glissière 25';
    }
    if (cleaned.toLowerCase() == 'glissiere 120' ||
        cleaned.toLowerCase() == 'glissière 120') {
      cleaned = 'Glissière 120';
    }
    if (cleaned.toLowerCase() == 'glissiere 100' ||
        cleaned.toLowerCase() == 'glissière 100') {
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

  Future<void> _ensureShutterColorTables(DatabaseExecutor db) =>
      _ensureSchemaOnce(db, '_ensureShutterColorTables', () => _ensureShutterColorTablesUncached(db));

  Future<void> _ensureShutterColorTablesUncached(DatabaseExecutor db) async {
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
  Future<void> _ensureSeriesDesignTables(DatabaseExecutor db) {
    final cachedTask = SqlDatabase._seriesDesignSchemaTask;
    if (identical(SqlDatabase._seriesDesignSchemaOwner, db) && cachedTask != null) {
      return cachedTask;
    }
    final task = _ensureSeriesDesignTablesImpl(db);
    SqlDatabase._seriesDesignSchemaOwner = db;
    SqlDatabase._seriesDesignSchemaTask = task;
    return task;
  }

  Future<void> _ensureSeriesDesignTablesImpl(DatabaseExecutor db) async {
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
        skip_glazing_bead INTEGER NOT NULL DEFAULT 0,
        requires_plant INTEGER NOT NULL DEFAULT 0,
        joint_length_multiplier REAL NOT NULL DEFAULT 1.0,
        track_mode TEXT NOT NULL DEFAULT '',
        track_count INTEGER NOT NULL DEFAULT 0,
        track_adds INTEGER NOT NULL DEFAULT 0,
        supported_track_counts TEXT NOT NULL DEFAULT '',
        compatible_frame_ids TEXT NOT NULL DEFAULT '',
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
        assembly_target TEXT NOT NULL DEFAULT '',
        top_corner_qty INTEGER NOT NULL DEFAULT 1,
        bottom_corner_qty INTEGER NOT NULL DEFAULT 1,
        assembly_section_id INTEGER,
        assembly_section_ids TEXT NOT NULL DEFAULT '',
        assembly_section_quantities TEXT NOT NULL DEFAULT '',
        integrated_side_cover INTEGER NOT NULL DEFAULT 0,
        allows_side_cover INTEGER NOT NULL DEFAULT 1,
        allowed_with_shutter INTEGER NOT NULL DEFAULT 1,
        min_height_mm REAL,
        max_height_mm REAL,
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
    await db.execute('''
      CREATE TABLE IF NOT EXISTS FrameJoinRules (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        section_a_id INTEGER NOT NULL,
        section_b_id INTEGER NOT NULL,
        is_active INTEGER NOT NULL DEFAULT 1,
        updated_at TEXT NOT NULL DEFAULT '',
        UNIQUE(section_a_id, section_b_id)
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_frame_join_a ON FrameJoinRules(section_a_id);',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_frame_join_b ON FrameJoinRules(section_b_id);',
    );
    // A group of profiles that fit together (frames with or without side
    // cover, mullions...): every member is compatible with every other.
    // member_ids lists Sections ids, comma separated.
    await db.execute('''
      CREATE TABLE IF NOT EXISTS ProfileCompatibilityGroups (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        series_id INTEGER NOT NULL,
        name TEXT NOT NULL DEFAULT '',
        member_ids TEXT NOT NULL DEFAULT '',
        is_active INTEGER NOT NULL DEFAULT 1,
        updated_at TEXT NOT NULL DEFAULT ''
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_profile_compat_series ON ProfileCompatibilityGroups(series_id, is_active);',
    );
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
      'ALTER TABLE SeriesDesignRoles ADD COLUMN skip_glazing_bead INTEGER NOT NULL DEFAULT 0;',
      'ALTER TABLE SeriesDesignRoles ADD COLUMN requires_plant INTEGER NOT NULL DEFAULT 0;',
      'ALTER TABLE SeriesDesignRoles ADD COLUMN joint_length_multiplier REAL NOT NULL DEFAULT 1.0;',
      "ALTER TABLE SeriesDesignRoles ADD COLUMN track_mode TEXT NOT NULL DEFAULT '';",
      'ALTER TABLE SeriesDesignRoles ADD COLUMN track_count INTEGER NOT NULL DEFAULT 0;',
      'ALTER TABLE SeriesDesignRoles ADD COLUMN track_adds INTEGER NOT NULL DEFAULT 0;',
      "ALTER TABLE SeriesDesignRoles ADD COLUMN supported_track_counts TEXT NOT NULL DEFAULT '';",
      "ALTER TABLE SeriesDesignRoles ADD COLUMN compatible_frame_ids TEXT NOT NULL DEFAULT '';",
    ]) {
      try {
        await db.execute(statement);
      } catch (_) {}
    }
    for (final statement in const [
      "ALTER TABLE CatalogItemRules ADD COLUMN usage_scope TEXT NOT NULL DEFAULT 'global';",
      "ALTER TABLE CatalogItemRules ADD COLUMN show_when_glass TEXT NOT NULL DEFAULT 'any';",
      "ALTER TABLE CatalogItemRules ADD COLUMN selection_mode TEXT NOT NULL DEFAULT 'always';",
      "ALTER TABLE CatalogItemRules ADD COLUMN assembly_target TEXT NOT NULL DEFAULT '';",
      'ALTER TABLE CatalogItemRules ADD COLUMN top_corner_qty INTEGER NOT NULL DEFAULT 1;',
      'ALTER TABLE CatalogItemRules ADD COLUMN bottom_corner_qty INTEGER NOT NULL DEFAULT 1;',
      'ALTER TABLE CatalogItemRules ADD COLUMN assembly_section_id INTEGER;',
      "ALTER TABLE CatalogItemRules ADD COLUMN assembly_section_ids TEXT NOT NULL DEFAULT '';",
      "ALTER TABLE CatalogItemRules ADD COLUMN assembly_section_quantities TEXT NOT NULL DEFAULT '';",
      'ALTER TABLE CatalogItemRules ADD COLUMN integrated_side_cover INTEGER NOT NULL DEFAULT 0;',
      'ALTER TABLE CatalogItemRules ADD COLUMN allows_side_cover INTEGER NOT NULL DEFAULT 1;',
      'ALTER TABLE CatalogItemRules ADD COLUMN allowed_with_shutter INTEGER NOT NULL DEFAULT 1;',
      'ALTER TABLE CatalogItemRules ADD COLUMN min_height_mm REAL;',
      'ALTER TABLE CatalogItemRules ADD COLUMN max_height_mm REAL;',
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

  /// Allows one catalogue section to be assigned to another series or to an
  /// entire profile system without duplicating the section row.
  Future<void> _ensureSectionSharingSchema(DatabaseExecutor db) =>
      _ensureSchemaOnce(db, '_ensureSectionSharingSchema', () => _ensureSectionSharingSchemaUncached(db));

  Future<void> _ensureSectionSharingSchemaUncached(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS SectionSharingRules (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        source_section_id INTEGER NOT NULL,
        target_scope TEXT NOT NULL CHECK(target_scope IN ('series', 'profile')),
        target_id INTEGER NOT NULL,
        role_key TEXT NOT NULL,
        usage_scope TEXT NOT NULL DEFAULT 'global',
        is_default INTEGER NOT NULL DEFAULT 0,
        is_active INTEGER NOT NULL DEFAULT 1,
        sort_order INTEGER NOT NULL DEFAULT 0,
        updated_at TEXT NOT NULL DEFAULT '',
        UNIQUE(source_section_id, target_scope, target_id, role_key, usage_scope)
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_section_sharing_target ON SectionSharingRules(target_scope, target_id, role_key, is_active);',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_section_sharing_source ON SectionSharingRules(source_section_id);',
    );
  }

  Future<void> _ensureAdvancedKitCompatibilitySchema(DatabaseExecutor db) {
    final cachedTask = SqlDatabase._advancedKitSchemaTask;
    if (identical(SqlDatabase._advancedKitSchemaOwner, db) && cachedTask != null) {
      return cachedTask;
    }
    final task = _ensureAdvancedKitCompatibilitySchemaImpl(db);
    SqlDatabase._advancedKitSchemaOwner = db;
    SqlDatabase._advancedKitSchemaTask = task;
    return task;
  }

  Future<void> _ensureAdvancedKitCompatibilitySchemaImpl(
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
      // Axe deduction (mm) of a tunnel box with each console.
      'ALTER TABLE KitBundles ADD COLUMN compatibility_group_1_axe_deduction REAL NOT NULL DEFAULT 75;',
      'ALTER TABLE KitBundles ADD COLUMN compatibility_group_2_axe_deduction REAL NOT NULL DEFAULT 75;',
      "ALTER TABLE KitBundles ADD COLUMN price REAL NOT NULL DEFAULT 0.0;",
      "ALTER TABLE KitBundles ADD COLUMN material_type TEXT NOT NULL DEFAULT 'all';",
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

    // Repair legacy ranges that accidentally stored both targets.  Prefer an
    // active family when it exists; otherwise preserve the component link.
    try {
      await db.execute('''
        UPDATE KitItemRanges
        SET shutter_component_id = NULL
        WHERE shutter_component_id IS NOT NULL
          AND family_id IS NOT NULL
          AND EXISTS (
            SELECT 1 FROM KitBundleFamilies
            WHERE KitBundleFamilies.id = KitItemRanges.family_id
              AND KitBundleFamilies.is_active = 1
          )
      ''');
      await db.execute('''
        UPDATE KitItemRanges
        SET family_id = NULL
        WHERE shutter_component_id IS NOT NULL
          AND family_id IS NOT NULL
      ''');
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
    if (SqlDatabase._decorPanelDesignSchemaReady) return;
    try {
      final cols = await db.rawQuery('PRAGMA table_info(Glass)');
      final existingCols = cols
          .map((c) => c['name'].toString().toLowerCase())
          .toSet();
      if (!existingCols.contains('visible_width')) {
        await db.execute(
          'ALTER TABLE Glass ADD COLUMN visible_width REAL DEFAULT NULL;',
        );
      }
      if (!existingCols.contains('decor_design_code')) {
        await db.execute(
          "ALTER TABLE Glass ADD COLUMN decor_design_code TEXT NOT NULL DEFAULT '';",
        );
      }
      if (!existingCols.contains('panel_width')) {
        await db.execute(
          'ALTER TABLE Glass ADD COLUMN panel_width REAL DEFAULT NULL;',
        );
      }
      if (!existingCols.contains('panel_height')) {
        await db.execute(
          'ALTER TABLE Glass ADD COLUMN panel_height REAL DEFAULT NULL;',
        );
      }
      SqlDatabase._decorPanelDesignSchemaReady = true;
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

  Future<Database> initDb() async {
    String dbName = 'test.db';

    String path;
    if (kIsWeb) {
      path = dbName;
    } else {
      String dataPath = await SqlDatabase._getWritableDatabasesPath();
      path = join(dataPath, dbName);
    }
    final dbPassword = await _resolveDbPassword(dbName);

    if (!kIsWeb) {
      try {
        final dataPath = await SqlDatabase._getWritableDatabasesPath();
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
      // A busy/locked database is still valid. Never rename the live file or
      // create a replacement for a transient lock, permissions or open error.
      if (!SqlDatabase.isCorruptionError(e)) rethrow;
      if (!kIsWeb && await SqlDatabase._dbFactory.databaseExists(path)) {
        try {
          final file = File(path);
          final backupPath =
              '$path.corrupt_${DateTime.now().millisecondsSinceEpoch}';
          await file.rename(backupPath);
          Text('Renamed unreadable database to $backupPath');
        } catch (renameError) {
          Text('Could not rename corrupt database: $renameError');
        }
        SqlDatabase.resetDb();
        return await _openEncryptedDb(path, dbPassword);
      }
      rethrow;
    }
  }

  Future<void> reopenAfterDatabaseMoved() {
    final activeTask = SqlDatabase._databaseReopenTask;
    if (activeTask != null) return activeTask;

    late final Future<void> task;
    task = _reopenAfterDatabaseMoved().whenComplete(() {
      if (identical(SqlDatabase._databaseReopenTask, task)) {
        SqlDatabase._databaseReopenTask = null;
      }
    });
    SqlDatabase._databaseReopenTask = task;
    return task;
  }

  Future<void> _reopenAfterDatabaseMoved() async {
    final staleDb = SqlDatabase._db;
    SqlDatabase._db = null;
    SqlDatabase._openingDb = null;
    if (staleDb != null) {
      try {
        await staleDb.close();
      } catch (_) {}
    }
    SqlDatabase._db = await initDb();
  }

  Future<bool> isDatabaseHealthy({bool force = false}) async {
    try {
      final currentDb = await db;
      if (currentDb == null) return false;
      final lastCheck = SqlDatabase._lastHealthyCheckAt;
      if (!force &&
          lastCheck != null &&
          DateTime.now().difference(lastCheck) < SqlDatabase._healthCheckInterval) {
        return true;
      }
      final check = await currentDb.rawQuery('PRAGMA quick_check');
      final healthy =
          check.isNotEmpty &&
          check.every(
            (row) => row.values.any(
              (value) => value.toString().toLowerCase() == 'ok',
            ),
          );
      SqlDatabase._lastHealthyCheckAt = healthy ? DateTime.now() : null;
      return healthy;
    } catch (error) {
      // Do not label a moved open handle as corruption. The sync layer can
      // safely close and reopen it, whereas treating it as corruption would
      // unnecessarily discard a perfectly valid database file.
      if (SqlDatabase.isDatabaseMovedError(error)) rethrow;
      return false;
    }
  }

  /// Preserves the unreadable SQLite file for diagnostics, creates a clean
  /// database with the same encryption key, and keeps login/workshop settings.
  Future<String?> recreateCorruptedDatabase() async {
    const dbName = 'test.db';
    final path = await getDatabaseFilePath();
    String? diagnosticBackupPath;

    final currentDb = SqlDatabase._db;
    SqlDatabase._db = null;
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
    await SqlDatabase._dbFactory.deleteDatabase(path);
    final password = await _resolveDbPassword(dbName);
    SqlDatabase._db = await _openEncryptedDb(path, password);
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
          is_default INTEGER NOT NULL DEFAULT 0,
          gache_accessory_id INTEGER,
          gache_count INTEGER NOT NULL DEFAULT 0,
          linked_accessory_id INTEGER,
          linked_accessory_count INTEGER NOT NULL DEFAULT 0,
          screw_accessory_id INTEGER,
          triangle_deduction_mm REAL NOT NULL DEFAULT 0.0,
          triangle_position_mode TEXT NOT NULL DEFAULT 'center',
          triangle_position_mm REAL NOT NULL DEFAULT 0.0,
          triangle_link_mode TEXT NOT NULL DEFAULT 'none',
          triangle_quantity INTEGER NOT NULL DEFAULT 1,
          is_active INTEGER NOT NULL DEFAULT 1
        )
      ''');
      await db.execute('''
        CREATE TABLE Joints (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          is_active INTEGER NOT NULL DEFAULT 1,
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
    await _ensureOrderTrashInfrastructure(db);
    if (oldVersion < 65) {
      for (final sql in const [
        'ALTER TABLE Accessories ADD COLUMN is_default INTEGER NOT NULL DEFAULT 0',
        'ALTER TABLE Accessories ADD COLUMN gache_accessory_id INTEGER',
        'ALTER TABLE Accessories ADD COLUMN gache_count INTEGER NOT NULL DEFAULT 0',
        'ALTER TABLE Accessories ADD COLUMN screw_accessory_id INTEGER',
        'ALTER TABLE Accessories ADD COLUMN triangle_deduction_mm REAL NOT NULL DEFAULT 0.0',
        "ALTER TABLE Accessories ADD COLUMN triangle_position_mode TEXT NOT NULL DEFAULT 'center'",
        'ALTER TABLE Accessories ADD COLUMN triangle_position_mm REAL NOT NULL DEFAULT 0.0',
      ]) {
        try {
          await db.execute(sql);
        } catch (_) {}
      }
    }
    if (oldVersion < 66) {
      await _ensureSectionSharingSchema(db);
    }
    if (oldVersion < 67) {
      for (final sql in const [
        "ALTER TABLE Accessories ADD COLUMN triangle_link_mode TEXT NOT NULL DEFAULT 'none'",
        'ALTER TABLE Accessories ADD COLUMN triangle_quantity INTEGER NOT NULL DEFAULT 1',
      ]) {
        try {
          await db.execute(sql);
        } catch (_) {}
      }
    }
    if (oldVersion < 68) {
      try {
        await db.execute(
          "ALTER TABLE Commandes_deliveries ADD COLUMN is_loaded INTEGER DEFAULT 0;",
        );
      } catch (_) {}
    }
    if (oldVersion < 69) {
      await _ensureAccessoryRulesColumns(db);
    }
    if (oldVersion < 70) {
      await _ensureRemnantInventorySchema(db);
    }
    if (oldVersion < 71) {
      await _ensureOrderPinningInfrastructure(db);
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
    updated_at TEXT NOT NULL DEFAULT (datetime('now')),
    updated_by TEXT,
    project_id INTEGER,
    is_deleted INTEGER NOT NULL DEFAULT 0,
    deleted_at TEXT
    ,is_pinned INTEGER NOT NULL DEFAULT 0
    ,pinned_at TEXT
  )
''');
    await _ensureOrderCodeInfrastructure(db);
    await _ensureOrderTrashInfrastructure(db);

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
    sort_order INTEGER NOT NULL DEFAULT 0,
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
        is_loaded INTEGER DEFAULT 0,
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
      is_active INTEGER NOT NULL DEFAULT 1,
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
        unit TEXT NOT NULL DEFAULT 'قطعة',
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
    await _ensureSectionSharingSchema(db);
  }

  //////////////////////////////////// Client //////////////////////////////////////
  /// Adds the immutable, user-facing client ID infrastructure.  [id] remains
  /// a distributed technical key for synchronisation; [client_code] is the
  /// business ID shown to people (1, 2, 3...) and is never recalculated.
  Future<void> _ensureClientCodeInfrastructure(DatabaseExecutor executor) =>
      _ensureSchemaOnce(executor, '_ensureClientCodeInfrastructure', () => _ensureClientCodeInfrastructureUncached(executor));

  Future<void> _ensureClientCodeInfrastructureUncached(DatabaseExecutor executor) async {
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

  Future<void> _ensureOrderPinningInfrastructure(
    DatabaseExecutor executor,
  ) async {
    if (SqlDatabase._orderPinningInfrastructureReady) return;
    try {
      await executor.execute(
        'ALTER TABLE Commandes ADD COLUMN is_pinned INTEGER NOT NULL DEFAULT 0;',
      );
    } catch (_) {}
    try {
      await executor.execute(
        'ALTER TABLE Commandes ADD COLUMN pinned_at TEXT;',
      );
    } catch (_) {}
    SqlDatabase._orderPinningInfrastructureReady = true;
  }

  /// Ensures soft-delete columns (is_deleted, deleted_at) exist on Commandes
  /// to support the recycle bin (سلة المهملات).
  Future<void> _ensureOrderTrashInfrastructure(
    DatabaseExecutor executor,
  ) async {
    if (SqlDatabase._orderTrashInfrastructureReady) return;
    try {
      await executor.execute(
        'ALTER TABLE Commandes ADD COLUMN is_deleted INTEGER NOT NULL DEFAULT 0;',
      );
    } catch (_) {
      // Column already exists
    }
    try {
      await executor.execute(
        'ALTER TABLE Commandes ADD COLUMN deleted_at TEXT;',
      );
    } catch (_) {
      // Column already exists
    }
    try {
      await executor.execute(
        'ALTER TABLE Commandes ADD COLUMN deleted_by TEXT;',
      );
    } catch (_) {
      // Column already exists
    }
    SqlDatabase._orderTrashInfrastructureReady = true;
  }

  /// Ensures stock reservation columns exist on Commandes
  /// to support stock booking (حجز السلع للطلبية).
  Future<void> _ensureOrderStockReservationInfrastructure(
    DatabaseExecutor executor,
  ) async {
    if (_orderStockReservationInfrastructureReady) return;
    try {
      await executor.execute(
        'ALTER TABLE Commandes ADD COLUMN is_stock_reserved INTEGER NOT NULL DEFAULT 0;',
      );
    } catch (_) {}
    try {
      await executor.execute(
        'ALTER TABLE Commandes ADD COLUMN stock_reserved_at TEXT;',
      );
    } catch (_) {}
    _orderStockReservationInfrastructureReady = true;
  }

  /// Adds the immutable, user-facing order number infrastructure.  [id] can be
  /// a large distributed sync key; [order_code] is the short number people see.
  Future<void> _ensureOrderCodeInfrastructure(DatabaseExecutor executor) async {
    if (SqlDatabase._orderCodeInfrastructureReady) return;
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
    SqlDatabase._orderCodeInfrastructureReady = true;
  }

  /// Gives restored or legacy orders a permanent display number once.  Old
  /// AUTOINCREMENT IDs such as #21 are preserved; distributed IDs get #22...
  /// based on creation order.
  Future<void> _backfillOrderCodes(DatabaseExecutor executor) async {
    await _ensureOrderCodeInfrastructure(executor);
    try {
      final needsBackfill = await executor.rawQuery(
        'SELECT 1 FROM Commandes WHERE order_code IS NULL OR order_code <= 0 LIMIT 1',
      );
      if (needsBackfill.isEmpty) return;
    } catch (_) {
      // If column query fails, proceed with normal logic
    }
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

  Future<void> _ensureClientBusinessSegment(DatabaseExecutor database) async {
    await _ensureSchemaOnce(database, '_ensureClientBusinessSegment', () async {
    try {
      await database.execute(
        "ALTER TABLE Client ADD COLUMN business_segment TEXT NOT NULL DEFAULT 'windows'",
      );
    } catch (_) {}
    });
    await database.rawUpdate(
      "UPDATE Client SET business_segment = 'windows' "
      "WHERE business_segment IS NULL OR TRIM(business_segment) = ''",
    );
  }

  Future<void> _ensureUniqueClientIdentity(
    DatabaseExecutor database, {
    required String firstname,
    required String lastname,
    required String phone1,
    required String phone2,
    int? excludingId,
  }) async {
    final rows = await database.query(
      'Client',
      columns: ['id', 'firstname', 'lastname', 'phone1', 'phone2'],
      where: excludingId == null ? null : 'id != ?',
      whereArgs: excludingId == null ? null : [excludingId],
    );
    final requestedName = _normaliseClientName('$firstname $lastname');
    final requestedPhones = {
      _normaliseClientPhone(phone1),
      _normaliseClientPhone(phone2),
    }..remove('');

    for (final row in rows) {
      final existingName = _normaliseClientName(
        '${row['firstname'] ?? ''} ${row['lastname'] ?? ''}',
      );
      if (requestedName.isNotEmpty && existingName == requestedName) {
        throw DuplicateClientException('name', '$firstname $lastname'.trim());
      }
      final existingPhones = {
        _normaliseClientPhone(row['phone1']?.toString() ?? ''),
        _normaliseClientPhone(row['phone2']?.toString() ?? ''),
      }..remove('');
      final duplicatePhones = requestedPhones.intersection(existingPhones);
      if (duplicatePhones.isNotEmpty) {
        throw DuplicateClientException('phone', duplicatePhones.first);
      }
    }
  }

  Future<void> _ensureOrderQueryInfrastructure(DatabaseExecutor myDb) async {
    await _ensureSchemaOnce(
      myDb,
      '_ensureOrderQueryInfrastructure',
      () => _ensureOrderQueryInfrastructureUncached(myDb),
    );
    // Synced orders may arrive without a display code: keep this check (it
    // stops after one cheap query when nothing is missing).
    await _backfillOrderCodes(myDb);
  }

  Future<void> _ensureOrderQueryInfrastructureUncached(
    DatabaseExecutor myDb,
  ) async {
    await _ensureOrderTrashInfrastructure(myDb);
    await _ensureOrderStockReservationInfrastructure(myDb);
    await _ensureOrderPinningInfrastructure(myDb);

    // Ensure Projects table exists
    try {
      await myDb.execute('''
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

    // Ensure Commandes columns exist
    final orderAlters = [
      'ALTER TABLE Commandes ADD COLUMN project_id INTEGER;',
      'ALTER TABLE Commandes ADD COLUMN order_code INTEGER NOT NULL DEFAULT 0;',
      'ALTER TABLE Commandes ADD COLUMN is_deleted INTEGER NOT NULL DEFAULT 0;',
      'ALTER TABLE Commandes ADD COLUMN deleted_at TEXT;',
      'ALTER TABLE Commandes ADD COLUMN is_pinned INTEGER NOT NULL DEFAULT 0;',
      'ALTER TABLE Commandes ADD COLUMN pinned_at TEXT;',
      'ALTER TABLE Commandes ADD COLUMN is_stock_reserved INTEGER NOT NULL DEFAULT 0;',
      'ALTER TABLE Commandes ADD COLUMN stock_reserved_at TEXT;',
      'ALTER TABLE Commandes ADD COLUMN advance_payment REAL NOT NULL DEFAULT 0.0;',
      "ALTER TABLE Commandes ADD COLUMN payment_status TEXT NOT NULL DEFAULT 'Unpaid';",
      'ALTER TABLE Commandes ADD COLUMN updated_by TEXT;',
      "ALTER TABLE Commandes ADD COLUMN created_at TEXT NOT NULL DEFAULT (datetime('now'));",
      "ALTER TABLE Commandes ADD COLUMN updated_at TEXT NOT NULL DEFAULT (datetime('now'));",
    ];
    for (final sql in orderAlters) {
      try {
        await myDb.execute(sql);
      } catch (_) {}
    }

    // Ensure Client columns exist
    final clientAlters = [
      'ALTER TABLE Client ADD COLUMN latitude REAL;',
      'ALTER TABLE Client ADD COLUMN longitude REAL;',
      'ALTER TABLE Client ADD COLUMN address TEXT;',
      'ALTER TABLE Client ADD COLUMN phone1 TEXT;',
      'ALTER TABLE Client ADD COLUMN phone2 TEXT;',
      'ALTER TABLE Client ADD COLUMN email TEXT;',
      "ALTER TABLE Client ADD COLUMN creation_platform TEXT NOT NULL DEFAULT 'unknown';",
    ];
    for (final sql in clientAlters) {
      try {
        await myDb.execute(sql);
      } catch (_) {}
    }
  }

  Future<void> _migratePendingOrdersToNouveau(DatabaseExecutor db) async {
    try {
      await db.execute('''
        UPDATE Commandes 
        SET status = 'Nouveau' 
        WHERE LOWER(TRIM(status)) IN ('pending', 'en attente', 'en_attente', 'في الانتظار', 'قيد الانتظار', 'في حالة انتظار')
           OR status IS NULL 
           OR TRIM(status) = '';
      ''');
    } catch (e) {
      debugPrint('Error in _migratePendingOrdersToNouveau: $e');
    }
  }

  /// Migrates all existing orders in 'Pending' / 'En attente' to 'Nouveau'
  /// and notifies listeners and cloud sync safely.
  Future<int> migrateAllPendingOrdersToNouveau() async {
    final myDb = await db;
    if (myDb == null) return 0;
    try {
      final rows = await myDb.rawQuery('''
        SELECT id FROM Commandes 
        WHERE LOWER(TRIM(status)) IN ('pending', 'en attente', 'en_attente', 'في الانتظار', 'قيد الانتظار', 'في حالة انتظار')
           OR status IS NULL 
           OR TRIM(status) = ''
      ''');
      if (rows.isEmpty) return 0;
      final count = await myDb.rawUpdate('''
        UPDATE Commandes 
        SET status = 'Nouveau',
            updated_at = '${DateTime.now().toUtc().toIso8601String()}'
        WHERE LOWER(TRIM(status)) IN ('pending', 'en attente', 'en_attente', 'في الانتظار', 'قيد الانتظار', 'في حالة انتظار')
           OR status IS NULL 
           OR TRIM(status) = ''
      ''');
      for (final row in rows) {
        final id = (row['id'] as num?)?.toInt();
        if (id != null) {
          unawaited(_uploadOrderStatusToCloud(id, 'Nouveau'));
        }
      }
      CloudSyncService().notifyChange();
      return count;
    } catch (e) {
      debugPrint('migrateAllPendingOrdersToNouveau error: $e');
      return 0;
    }
  }

  Future<void> _removeDeletedOrderTombstoneFromCloud(int orderId) async {
    if (CloudSyncService.supabaseWorkshopDataOnly) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final workshopId = prefs.getString('workshop_code') ?? '';
      if (workshopId.isEmpty) return;
      await FirebaseFirestore.instance
          .collection('workshops')
          .doc(workshopId)
          .collection('deleted_orders')
          .doc(orderId.toString())
          .delete()
          .timeout(const Duration(seconds: 3));
    } catch (e) {
      debugPrint('Failed to remove deleted_orders tombstone: $e');
    }
  }

  String _repairMojibakeString(String text) {
    if (text.isEmpty ||
        (!text.contains('Ø') &&
            !text.contains('Ã') &&
            !text.contains('Â') &&
            !text.contains('Ù'))) {
      return text;
    }
    try {
      final bytes = <int>[];
      for (final rune in text.runes) {
        if (rune <= 0xFF) {
          bytes.add(rune);
        } else if (SqlDatabase._unicodeToWin1252Map.containsKey(rune)) {
          bytes.add(SqlDatabase._unicodeToWin1252Map[rune]!);
        } else {
          return text;
        }
      }
      final repaired = utf8.decode(bytes, allowMalformed: false);
      return repaired.contains('�') ? text : repaired;
    } catch (_) {
      return text;
    }
  }

  Future<void> _repairCorruptedMojibakeAndLongIdsInTreasury(
    Database myDb,
  ) async {
    try {
      // 1. Repair Mojibake and replace huge Order IDs in Treasury
      final treasuryRows = await myDb.query('Treasury');

      // Build order_id -> order_code lookup map for fast replacement
      final orderRows = await myDb.rawQuery(
        'SELECT id, order_code FROM Commandes WHERE order_code > 0',
      );
      final Map<int, int> orderCodeMap = {};
      for (final o in orderRows) {
        final id = (o['id'] as num?)?.toInt();
        final code = (o['order_code'] as num?)?.toInt();
        if (id != null && code != null && code > 0) {
          orderCodeMap[id] = code;
        }
      }

      final longNumberRegex = RegExp(r'\b\d{6,}\b');

      for (final row in treasuryRows) {
        final id = row['id'] as int;
        var desc = (row['description'] ?? '').toString();
        var type = (row['transaction_type'] ?? '').toString();
        var caisse = (row['caisse_name'] ?? '').toString();
        var recordedBy = (row['recorded_by'] ?? '').toString();
        bool changed = false;

        // A. Repair Mojibake in text columns
        final cleanDesc = _repairMojibakeString(desc);
        if (cleanDesc != desc) {
          desc = cleanDesc;
          changed = true;
        }
        final cleanType = _repairMojibakeString(type);
        if (cleanType != type) {
          type = cleanType;
          changed = true;
        }
        final cleanCaisse = _repairMojibakeString(caisse);
        if (cleanCaisse != caisse) {
          caisse = cleanCaisse;
          changed = true;
        }
        final cleanRecorded = _repairMojibakeString(recordedBy);
        if (cleanRecorded != recordedBy) {
          recordedBy = cleanRecorded;
          changed = true;
        }

        // B. Replace any large distributed order ID (6+ digits) in description with small order_code
        if (longNumberRegex.hasMatch(desc)) {
          final newDesc = desc.replaceAllMapped(longNumberRegex, (match) {
            final numStr = match.group(0)!;
            final candidateId = int.tryParse(numStr);
            if (candidateId != null && orderCodeMap.containsKey(candidateId)) {
              return orderCodeMap[candidateId].toString();
            }
            return numStr;
          });
          if (newDesc != desc) {
            desc = newDesc;
            changed = true;
          }
        }

        // Also if reference_id points to an order and description has #refId or رقم refId
        final refId = (row['reference_id'] as num?)?.toInt();
        if (refId != null &&
            refId > 100000 &&
            orderCodeMap.containsKey(refId)) {
          final code = orderCodeMap[refId]!;
          if (desc.contains(refId.toString())) {
            desc = desc.replaceAll(refId.toString(), code.toString());
            changed = true;
          }
        }

        if (changed) {
          await myDb.update(
            'Treasury',
            {
              'description': desc,
              'transaction_type': type,
              'caisse_name': caisse,
              'recorded_by': recordedBy,
            },
            where: 'id = ?',
            whereArgs: [id],
          );
        }
      }

      // 2. Repair Mojibake in WorkerTransactions notes
      final workerTxns = await myDb.rawQuery(
        "SELECT id, note FROM WorkerTransactions WHERE note LIKE '%Ø%' OR note LIKE '%Ã%' OR note LIKE '%Ù%'",
      );
      for (final w in workerTxns) {
        final wId = w['id'] as int;
        final note = (w['note'] ?? '').toString();
        final cleanNote = _repairMojibakeString(note);
        if (cleanNote != note) {
          await myDb.update(
            'WorkerTransactions',
            {'note': cleanNote},
            where: 'id = ?',
            whereArgs: [wId],
          );
        }
      }

      // 3. Repair Mojibake in Caisses names
      final caisseRows = await myDb.rawQuery(
        "SELECT id, name FROM Caisses WHERE name LIKE '%Ø%' OR name LIKE '%Ã%' OR name LIKE '%Ù%'",
      );
      for (final c in caisseRows) {
        final cId = c['id'] as int;
        final name = (c['name'] ?? '').toString();
        final cleanName = _repairMojibakeString(name);
        if (cleanName != name) {
          await myDb.update(
            'Caisses',
            {'name': cleanName},
            where: 'id = ?',
            whereArgs: [cId],
          );
        }
      }
    } catch (e) {
      debugPrint('Error auto-repairing Treasury/Mojibake: $e');
    }
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

      // Repair/remove old caisse rows before ensuring the three defaults. This
      // prevents a repaired legacy row from colliding with a newly inserted
      // canonical row because of the UNIQUE(name) constraint.
      await readCaisses();

      final checkMain = await myDb.query(
        'Caisses',
        where: 'name = ?',
        whereArgs: [SqlDatabase._mainCaisseName],
      );
      if (checkMain.isEmpty)
        await myDb.insert(
          'Caisses',
          SqlDatabase._withDistributedId({'name': SqlDatabase._mainCaisseName}),
        );
      final checkSecond = await myDb.query(
        'Caisses',
        where: 'name = ?',
        whereArgs: [SqlDatabase._secondCaisseName],
      );
      if (checkSecond.isEmpty)
        await myDb.insert(
          'Caisses',
          SqlDatabase._withDistributedId({'name': SqlDatabase._secondCaisseName}),
        );
      final checkBank = await myDb.query(
        'Caisses',
        where: 'name = ?',
        whereArgs: [SqlDatabase._bankCaisseName],
      );
      if (checkBank.isEmpty) {
        await myDb.insert(
          'Caisses',
          SqlDatabase._withDistributedId({'name': SqlDatabase._bankCaisseName}),
        );
      }

      await _ensurePaymentAllocationSchema(myDb);
      await _repairCorruptedMojibakeAndLongIdsInTreasury(myDb);

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
        final clientId = SqlDatabase._paymentRecordId(row['id']);
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
          'FROM Commandes WHERE client_id = ? AND (is_deleted IS NULL OR is_deleted = 0)',
          [clientId],
        );
        if ((SqlDatabase._paymentNumber(existingAllocations.first['allocated']) -
                    SqlDatabase._paymentNumber(recordedAdvance.first['paid']))
                .abs() >
            SqlDatabase._paymentTolerance) {
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
        final supplierId = SqlDatabase._paymentRecordId(row['id']);
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
        if ((SqlDatabase._paymentNumber(existingAllocations.first['allocated']) -
                    SqlDatabase._paymentNumber(recordedPaid.first['paid']))
                .abs() >
            SqlDatabase._paymentTolerance) {
          await myDb.transaction(
            (txn) => _rebuildSupplierPaymentLedger(txn, supplierId),
          );
        }
      }
    } catch (_) {}
  }

  Future<void> _ensureDeliveriesLoadedColumn(Database db) =>
      _ensureSchemaOnce(db, '_ensureDeliveriesLoadedColumn', () => _ensureDeliveriesLoadedColumnUncached(db));

  Future<void> _ensureDeliveriesLoadedColumnUncached(Database db) async {
    try {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS Commandes_deliveries (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          id_commandes INTEGER NOT NULL,
          client_id INTEGER NOT NULL,
          delivery_date TEXT NOT NULL,
          items_json TEXT NOT NULL,
          total_amount REAL NOT NULL DEFAULT 0.0,
          is_loaded INTEGER DEFAULT 0,
          FOREIGN KEY (id_commandes) REFERENCES Commandes(id) ON DELETE CASCADE
        )
      ''');
    } catch (_) {}
    try {
      await db.execute(
        "ALTER TABLE Commandes_deliveries ADD COLUMN is_loaded INTEGER DEFAULT 0;",
      );
    } catch (_) {}
    for (final statement in const [
      "ALTER TABLE Commandes_deliveries ADD COLUMN delivery_status TEXT NOT NULL DEFAULT 'planned'",
      'ALTER TABLE Commandes_deliveries ADD COLUMN assigned_worker_uid TEXT',
      'ALTER TABLE Commandes_deliveries ADD COLUMN assigned_worker_name TEXT',
      'ALTER TABLE Commandes_deliveries ADD COLUMN started_at TEXT',
      'ALTER TABLE Commandes_deliveries ADD COLUMN delivered_at TEXT',
      'ALTER TABLE Commandes_deliveries ADD COLUMN delivery_note TEXT',
      'ALTER TABLE Commandes_deliveries ADD COLUMN updated_at TEXT',
    ]) {
      try {
        await db.execute(statement);
      } catch (_) {}
    }
  }

  Future<void> _ensureAccessoryRulesColumns(Database db) =>
      _ensureSchemaOnce(db, '_ensureAccessoryRulesColumns', () => _ensureAccessoryRulesColumnsUncached(db));

  Future<void> _ensureAccessoryRulesColumnsUncached(Database db) async {
    for (final statement in const [
      'ALTER TABLE Accessories ADD COLUMN is_default INTEGER NOT NULL DEFAULT 0',
      'ALTER TABLE Accessories ADD COLUMN screw_count INTEGER NOT NULL DEFAULT 0',
      'ALTER TABLE Accessories ADD COLUMN screw_accessory_id INTEGER',
      'ALTER TABLE Accessories ADD COLUMN gache_accessory_id INTEGER',
      'ALTER TABLE Accessories ADD COLUMN gache_count INTEGER NOT NULL DEFAULT 0',
      'ALTER TABLE Accessories ADD COLUMN linked_accessory_id INTEGER',
      'ALTER TABLE Accessories ADD COLUMN linked_accessory_count INTEGER NOT NULL DEFAULT 0',
      'ALTER TABLE Accessories ADD COLUMN triangle_deduction_mm REAL NOT NULL DEFAULT 0.0',
      "ALTER TABLE Accessories ADD COLUMN triangle_position_mode TEXT NOT NULL DEFAULT 'center'",
      'ALTER TABLE Accessories ADD COLUMN triangle_position_mm REAL NOT NULL DEFAULT 0.0',
      "ALTER TABLE Accessories ADD COLUMN triangle_link_mode TEXT NOT NULL DEFAULT 'none'",
      'ALTER TABLE Accessories ADD COLUMN triangle_quantity INTEGER NOT NULL DEFAULT 1',
    ]) {
      try {
        await db.execute(statement);
      } catch (_) {}
    }
  }

  Future<void> _ensureAchatTrashInfrastructure(
    DatabaseExecutor executor,
  ) async {
    if (SqlDatabase._achatTrashInfrastructureReady) return;
    try {
      await executor.execute(
        'ALTER TABLE Achats ADD COLUMN is_deleted INTEGER NOT NULL DEFAULT 0;',
      );
    } catch (_) {}
    try {
      await executor.execute('ALTER TABLE Achats ADD COLUMN deleted_at TEXT;');
    } catch (_) {}
    try {
      await executor.execute('ALTER TABLE Achats ADD COLUMN deleted_by TEXT;');
    } catch (_) {}
    try {
      await executor.execute(
        'ALTER TABLE Achats ADD COLUMN status_before_delete TEXT;',
      );
    } catch (_) {}
    try {
      await executor.execute(
        'ALTER TABLE Achats ADD COLUMN stock_reversed_on_delete INTEGER NOT NULL DEFAULT 0;',
      );
    } catch (_) {}
    SqlDatabase._achatTrashInfrastructureReady = true;
  }

  //////////////////////////////////// Colors //////////////////////////////////////
  Future<void> _repairKnownColorRows(Database myDb) async {
    if (SqlDatabase._knownColorsRepaired) return;
    SqlDatabase._knownColorsRepaired = true;
    var changed = false;
    try {
      final rows = await myDb.query('Colors');
      for (final row in rows) {
        final id = row['id'];
        if (id == null) continue;
        final rawName = row['name']?.toString() ?? '';
        final repairedName = SqlDatabase._canonicalLegacyColorName(rawName);
        final rawHex = row['hex_code']?.toString() ?? '';
        final repairedHex = SqlDatabase._canonicalKnownColorHex(repairedName, rawHex);
        if (repairedName == rawName && repairedHex == rawHex) continue;
        await myDb.update(
          'Colors',
          {'name': repairedName, 'hex_code': repairedHex},
          where: 'id = ?',
          whereArgs: [id],
        );
        changed = true;
      }
      final hasFauxBoisMarron = rows.any((r) {
        final n = (r['name']?.toString() ?? '').toLowerCase().trim();
        return n == 'faux bois marron' ||
            n == 'marron faux bois' ||
            n == 'خشبي بني' ||
            n == 'خشبي بني (faux bois marron)';
      });
      if (!hasFauxBoisMarron) {
        await myDb.insert('Colors', {
          'name': 'Faux Bois Marron',
          'hex_code': '#A9774E',
          'type': 'Global',
          'price': 0.0,
          'is_glass_color': 0,
        });
        changed = true;
      }
      if (await _mergeDuplicateColorRows(myDb)) changed = true;
    } catch (_) {
      SqlDatabase._knownColorsRepaired = false;
      return;
    }
    if (changed) CloudSyncService().notifyCatalogChange();
  }

  /// One colour can exist several times under spellings of the same name
  /// (Champagne / شامبانيا / شمبانيا, or the same name twice). The copy used
  /// most keeps the prices and profile links of the others, which are then
  /// deactivated the way the colour screen deletes a colour (synced, and
  /// still readable by saved orders and stock rows that point to them).
  Future<bool> _mergeDuplicateColorRows(Database myDb) async {
    final rows = await myDb.query(
      'Colors',
      where: 'is_active = 1 OR is_active IS NULL',
      orderBy: 'id ASC',
    );
    final groups = <String, List<Map<String, dynamic>>>{};
    for (final row in rows) {
      final key = SqlDatabase.colorIdentityKey(row['name']);
      if (key.isEmpty) continue;
      final glass = '${row['is_glass_color'] ?? 0}';
      (groups['$glass|$key'] ??= []).add(row);
    }
    // Pricing and configuration rows follow the kept colour; stock, purchase
    // and remnant rows keep their original colour id.
    const tables = [
      'ProfileColors',
      'SeriesColorPrices',
      'SectionColorPrices',
      'AccessoryColorPrices',
      'ShutterColorPrices',
      'ShutterComponentColors',
    ];
    var changed = false;
    for (final group in groups.values) {
      if (group.length < 2) continue;
      final usage = <int, int>{};
      for (final row in group) {
        final id = (row['id'] as num).toInt();
        var count = 0;
        for (final table in tables) {
          try {
            final result = await myDb.rawQuery(
              'SELECT COUNT(*) AS c FROM $table WHERE color_id = ?',
              [id],
            );
            count += (result.first['c'] as num?)?.toInt() ?? 0;
          } catch (_) {}
        }
        usage[id] = count;
      }
      final ids = usage.keys.toList()
        ..sort((a, b) {
          final byUse = usage[b]!.compareTo(usage[a]!);
          return byUse != 0 ? byUse : a.compareTo(b);
        });
      final keep = ids.first;
      await myDb.transaction((txn) async {
        for (final old in ids.skip(1)) {
          for (final table in tables) {
            try {
              await txn.rawUpdate(
                'UPDATE OR IGNORE $table SET color_id = ? WHERE color_id = ?',
                [keep, old],
              );
            } catch (_) {}
          }
          await txn.update(
            'Colors',
            {'is_active': 0},
            where: 'id = ?',
            whereArgs: [old],
          );
        }
      });
      changed = true;
    }
    return changed;
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

  /// Exact links between a treasury transaction and the orders or purchase
  /// invoices it settles. This makes Treasury the financial source of truth.
  Future<void> _ensurePaymentAllocationSchema(DatabaseExecutor executor) =>
      _ensureSchemaOnce(executor, '_ensurePaymentAllocationSchema', () => _ensurePaymentAllocationSchemaUncached(executor));

  Future<void> _ensurePaymentAllocationSchemaUncached(DatabaseExecutor executor) async {
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

  /// Stamps every local order write with the signed-in account, so the
  /// orders list can show an edit as unread to the other accounts of the
  /// workshop but not to its author. The account comes from
  /// `_sync_runtime_flags.local_editor_uid` (kept current by [db]). Rows
  /// arriving from the cloud are written with tombstones suppressed and keep
  /// the author they were synced with.
  ///
  /// [last_editor_version] is the `updated_at` the stamp belongs to: an edit
  /// from an app version without this trigger changes `updated_at` but not
  /// the stamp, and must still count as someone else's edit.
  Future<void> _ensureOrderEditorTracking(DatabaseExecutor db) async {
    for (final statement in const [
      'ALTER TABLE _sync_runtime_flags ADD COLUMN local_editor_uid TEXT;',
      'ALTER TABLE Commandes ADD COLUMN last_editor_uid TEXT;',
      'ALTER TABLE Commandes ADD COLUMN last_editor_version TEXT;',
    ]) {
      try {
        await db.execute(statement);
      } catch (_) {}
    }
    const stamp = '''
      UPDATE Commandes
      SET last_editor_uid = (
            SELECT local_editor_uid FROM _sync_runtime_flags WHERE id = 1
          ),
          last_editor_version = NEW.updated_at
      WHERE id = NEW.id;
    ''';
    const localWrite = '''
      COALESCE(
        (SELECT suppress_tombstones FROM _sync_runtime_flags WHERE id = 1),
        0
      ) = 0
    ''';
    try {
      await db.execute('''
        CREATE TRIGGER IF NOT EXISTS order_local_editor_insert
        AFTER INSERT ON Commandes
        WHEN $localWrite
        BEGIN $stamp END
      ''');
      await db.execute('''
        CREATE TRIGGER IF NOT EXISTS order_local_editor_update
        AFTER UPDATE OF updated_at ON Commandes
        WHEN $localWrite AND NEW.updated_at IS NOT OLD.updated_at
        BEGIN $stamp END
      ''');
    } catch (error) {
      debugPrint('Could not track order editors: $error');
    }
  }

  /// Keeps `_sync_runtime_flags.local_editor_uid` equal to the signed-in
  /// account. Not awaited: sqflite runs it before later writes on the same
  /// connection, and awaiting it here could wait on a caller's transaction.
  void _refreshLocalEditorUid(Database database) {
    final uid = SqlDatabase.currentEditorUid();
    if (identical(SqlDatabase._localEditorUidOwner, database) &&
        SqlDatabase._localEditorUidWritten == uid) {
      return;
    }
    SqlDatabase._localEditorUidOwner = database;
    SqlDatabase._localEditorUidWritten = uid;
    unawaited(
      database
          .update('_sync_runtime_flags', {
            'local_editor_uid': uid,
          }, where: 'id = 1')
          .then<void>((_) {})
          .catchError((Object error) {
            SqlDatabase._localEditorUidOwner = null;
            debugPrint('Could not record the local order editor: $error');
          }),
    );
  }

  Future<String> _syncSchemaSignature(DatabaseExecutor db) async {
    final rows = await db.rawQuery('''
      SELECT
        (SELECT COUNT(*) FROM sqlite_master WHERE type = 'table') AS tables,
        (SELECT COUNT(*) FROM sqlite_master WHERE type = 'trigger') AS triggers,
        (SELECT COALESCE(SUM(LENGTH(sql)), 0)
         FROM sqlite_master WHERE type = 'table') AS definitions
    ''');
    final row = rows.first;
    return '${row['tables']}:${row['triggers']}:${row['definitions']}';
  }

  Future<void> _ensureSyncTombstoneInfrastructure(DatabaseExecutor db) async {
    if (SqlDatabase._syncInfrastructureSignature != null &&
        await _syncSchemaSignature(db) == SqlDatabase._syncInfrastructureSignature) {
      return;
    }
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
    await _ensureOrderEditorTracking(db);
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
    try {
      await _ensureWorkshopPriceSchema(db);
    } catch (error) {
      debugPrint('Could not prepare workshop price tables: $error');
    }
    try {
      final treasuryCols = await _tableColumns(db, 'Treasury');
      if (treasuryCols.isNotEmpty && !treasuryCols.contains('updated_at')) {
        await db.execute("ALTER TABLE Treasury ADD COLUMN updated_at TEXT;");
      }
    } catch (_) {}

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
      if (!SqlDatabase._isSafeSqlIdentifier(table)) continue;
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
    SqlDatabase._syncInfrastructureSignature = await _syncSchemaSignature(db);
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
        updated_at TEXT NOT NULL DEFAULT (datetime('now')),
        updated_by TEXT,
        is_deleted INTEGER NOT NULL DEFAULT 0,
        deleted_at TEXT
        ,is_pinned INTEGER NOT NULL DEFAULT 0
        ,pinned_at TEXT
      )
    ''');
    await _ensureOrderCodeInfrastructure(db);
    await _ensureOrderTrashInfrastructure(db);
    await _ensureOrderPinningInfrastructure(db);
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
        sort_order INTEGER NOT NULL DEFAULT 0,
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
        is_loaded INTEGER DEFAULT 0,
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
        is_default INTEGER NOT NULL DEFAULT 0,
        gache_accessory_id INTEGER,
        gache_count INTEGER NOT NULL DEFAULT 0,
        linked_accessory_id INTEGER,
        linked_accessory_count INTEGER NOT NULL DEFAULT 0,
        screw_accessory_id INTEGER,
        triangle_deduction_mm REAL NOT NULL DEFAULT 0.0,
        triangle_position_mode TEXT NOT NULL DEFAULT 'center',
        triangle_position_mm REAL NOT NULL DEFAULT 0.0,
        triangle_link_mode TEXT NOT NULL DEFAULT 'none',
        triangle_quantity INTEGER NOT NULL DEFAULT 1,
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
        unit TEXT NOT NULL DEFAULT 'قطعة',
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
      "ALTER TABLE Commandes_details ADD COLUMN sort_order INTEGER NOT NULL DEFAULT 0",
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
      "ALTER TABLE Profile ADD COLUMN is_active INTEGER NOT NULL DEFAULT 1",
      "ALTER TABLE Profile ADD COLUMN default_bar_length REAL NOT NULL DEFAULT 5.8",
      "ALTER TABLE Series ADD COLUMN is_active INTEGER NOT NULL DEFAULT 1",
      "ALTER TABLE Series ADD COLUMN price_per_meter REAL NOT NULL DEFAULT 0.0",
      "ALTER TABLE Series ADD COLUMN has_three_piece_sash INTEGER NOT NULL DEFAULT 0",
      "ALTER TABLE Series ADD COLUMN has_face_to_face INTEGER NOT NULL DEFAULT 0",
      "ALTER TABLE Series ADD COLUMN reinforcement_type TEXT DEFAULT 'full_substitution'",
      "ALTER TABLE Sections ADD COLUMN is_active INTEGER NOT NULL DEFAULT 1",
      "ALTER TABLE Sections ADD COLUMN bar_length REAL NOT NULL DEFAULT 5.8",
      "ALTER TABLE Sections ADD COLUMN couvre_joint_width REAL NOT NULL DEFAULT 0.0",
      "ALTER TABLE Sections ADD COLUMN couvre_joint_thickness REAL NOT NULL DEFAULT 0.0",
      "ALTER TABLE Sections ADD COLUMN glass_deduction REAL NOT NULL DEFAULT 0.0",
      "ALTER TABLE Sections ADD COLUMN weight_per_meter REAL NOT NULL DEFAULT 0.0",
      "ALTER TABLE Sections ADD COLUMN cutting_deduction REAL NOT NULL DEFAULT 0.0",
      "ALTER TABLE Sections ADD COLUMN visible_width REAL NOT NULL DEFAULT 0.0",
      "ALTER TABLE Sections ADD COLUMN visible_width_2 REAL NOT NULL DEFAULT 0.0",
      "ALTER TABLE Sections ADD COLUMN sash_overlap REAL NOT NULL DEFAULT 0.0",
      "ALTER TABLE Sections ADD COLUMN max_glass_thickness REAL NOT NULL DEFAULT 0.0",
      "ALTER TABLE Sections ADD COLUMN allows_side_cover INTEGER NOT NULL DEFAULT 1",
      "ALTER TABLE Sections ADD COLUMN is_frame INTEGER NOT NULL DEFAULT 0",
      "ALTER TABLE Sections ADD COLUMN is_sash INTEGER NOT NULL DEFAULT 0",
      "ALTER TABLE Sections ADD COLUMN is_mullion INTEGER NOT NULL DEFAULT 0",
      "ALTER TABLE Sections ADD COLUMN image_path TEXT",
      "ALTER TABLE Sections ADD COLUMN renfort_deduction REAL NOT NULL DEFAULT 140.0",

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
          'id': SqlDatabase._profileColorSyncId(pId, whiteColorId),
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

  Future<void> _ensureRemnantInventorySchema(DatabaseExecutor db) async {
    // This schema is already checked while the database is opened. Several
    // inventory and material-sales reads call this helper defensively as well,
    // so cache the work per connection instead of repeatedly issuing the same
    // CREATE/ALTER/INDEX statements. Re-running those statements on every
    // sales refresh can monopolise SQLite's executor and make the screen look
    // frozen, especially while cloud-sync events are arriving.
    if (SqlDatabase._remnantInventorySchemaOwner != db) {
      SqlDatabase._remnantInventorySchemaOwner = db;
      SqlDatabase._remnantInventorySchemaTask = null;
    }
    final task = SqlDatabase._remnantInventorySchemaTask ??=
        _createOrMigrateRemnantInventorySchema(db);
    try {
      await task;
    } catch (_) {
      // Do not permanently cache a failed migration. A transient database
      // lock should be recoverable on the next access.
      if (SqlDatabase._remnantInventorySchemaOwner == db &&
          identical(SqlDatabase._remnantInventorySchemaTask, task)) {
        SqlDatabase._remnantInventorySchemaTask = null;
      }
      rethrow;
    }
  }

  Future<void> _createOrMigrateRemnantInventorySchema(
    DatabaseExecutor db,
  ) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS InventorySettings (
        id INTEGER PRIMARY KEY,
        setting_key TEXT NOT NULL UNIQUE,
        numeric_value REAL,
        text_value TEXT,
        updated_at TEXT NOT NULL,
        created_by TEXT NOT NULL DEFAULT '',
        updated_by TEXT NOT NULL DEFAULT ''
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
    // Traceability of every stock movement (بطاقة حركة المنتج). The ids are
    // the reference; names are read from the documents when displayed.
    for (final column in const [
      'occurred_at TEXT',
      'movement_type TEXT',
      'unit TEXT',
      'balance_before REAL',
      'balance_after REAL',
      'unit_cost REAL',
      'total_cost REAL',
      'from_location_id INTEGER',
      'to_location_id INTEGER',
      'transfer_id TEXT',
      'document_type TEXT',
      'document_id INTEGER',
      'document_code TEXT',
      'linked_document_type TEXT',
      'linked_document_id INTEGER',
      'supplier_id INTEGER',
      'client_id INTEGER',
      'order_id INTEGER',
      'work_order_id INTEGER',
      'reverses_transaction_id INTEGER',
      'reason TEXT',
      'performed_by TEXT',
      'performed_by_uid TEXT',
      'attachment_path TEXT',
    ]) {
      try {
        await db.execute(
          'ALTER TABLE InventoryTransactions ADD COLUMN $column;',
        );
      } catch (_) {}
    }
    try {
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_inventory_transactions_item '
        'ON InventoryTransactions(item_type, item_id, color_id, occurred_at)',
      );
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_inventory_transactions_transfer '
        'ON InventoryTransactions(transfer_id)',
      );
      // A posted movement is never edited; a correction is a new reverse
      // movement. Cloud imports run with tombstones suppressed and may still
      // replace rows they own.
      await db.execute('''
        CREATE TRIGGER IF NOT EXISTS inventory_transactions_immutable
        BEFORE UPDATE ON InventoryTransactions
        WHEN COALESCE(
          (SELECT suppress_tombstones FROM _sync_runtime_flags WHERE id = 1),
          0
        ) = 0
        BEGIN
          SELECT RAISE(ABORT, 'لا يمكن تعديل حركة مخزون معتمدة؛ سجّل حركة عكسية.');
        END
      ''');
    } catch (error) {
      debugPrint('Could not prepare stock movement history: $error');
    }

    // Quantities held for an order (حجز السلع). An active row lowers the
    // stock that every other order, sale or transfer may take from the same
    // CurrentStock balance until the order issues it or the hold is released.
    await db.execute('''
      CREATE TABLE IF NOT EXISTS StockReservations (
        id INTEGER PRIMARY KEY,
        order_id INTEGER NOT NULL,
        item_id INTEGER NOT NULL,
        item_type TEXT NOT NULL,
        color_id INTEGER,
        location_id INTEGER NOT NULL,
        quantity REAL NOT NULL,
        status TEXT NOT NULL DEFAULT 'active',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        created_by TEXT NOT NULL DEFAULT ''
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_stock_reservations_balance '
      'ON StockReservations(item_id, item_type, color_id, location_id, status)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_stock_reservations_order '
      'ON StockReservations(order_id, status)',
    );
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
        status TEXT NOT NULL DEFAULT 'posted',
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
    try {
      await db.execute(
        "ALTER TABLE MaterialScrap ADD COLUMN status TEXT NOT NULL DEFAULT 'posted';",
      );
    } catch (_) {}
    try {
      await db.execute(
        'ALTER TABLE MaterialRemnants ADD COLUMN width_mm REAL NOT NULL DEFAULT 0.0;',
      );
    } catch (_) {}
    try {
      await db.execute(
        "ALTER TABLE MaterialRemnants ADD COLUMN material_type TEXT NOT NULL DEFAULT 'profile';",
      );
    } catch (_) {}
    try {
      await db.execute(
        'ALTER TABLE MaterialRemnants ADD COLUMN allow_rotation INTEGER NOT NULL DEFAULT 1;',
      );
    } catch (_) {}
    await db.execute('''
      CREATE TABLE IF NOT EXISTS StandardSheets (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        material_type TEXT NOT NULL,
        name TEXT NOT NULL,
        length_mm REAL NOT NULL,
        width_mm REAL NOT NULL,
        thickness_mm REAL DEFAULT 0.0,
        price_per_sheet REAL DEFAULT 0.0,
        price_per_sqm REAL DEFAULT 0.0,
        color TEXT DEFAULT '',
        allow_rotation INTEGER NOT NULL DEFAULT 1,
        notes TEXT DEFAULT '',
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
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_standard_sheets_type '
      'ON StandardSheets(material_type)',
    );
    // ── Material Sales (بيع المواد والمستلزمات) ────────────────────────────
    await db.execute('''
      CREATE TABLE IF NOT EXISTS MaterialSales (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        sale_code TEXT NOT NULL,
        client_id INTEGER,
        client_name TEXT NOT NULL DEFAULT '',
        client_phone TEXT NOT NULL DEFAULT '',
        doc_type TEXT NOT NULL DEFAULT 'bon_livraison',
        status TEXT NOT NULL DEFAULT 'draft',
        subtotal REAL NOT NULL DEFAULT 0.0,
        discount_amount REAL NOT NULL DEFAULT 0.0,
        net_total REAL NOT NULL DEFAULT 0.0,
        paid_amount REAL NOT NULL DEFAULT 0.0,
        remaining_amount REAL NOT NULL DEFAULT 0.0,
        location_id INTEGER NOT NULL DEFAULT 1,
        stock_deducted INTEGER NOT NULL DEFAULT 0,
        source_sale_id INTEGER,
        converted_to_sale_id INTEGER,
        notes TEXT NOT NULL DEFAULT '',
        sale_date TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        created_by TEXT NOT NULL DEFAULT '',
        updated_by TEXT NOT NULL DEFAULT ''
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS MaterialSaleItems (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        sale_id INTEGER NOT NULL,
        item_type TEXT NOT NULL,
        item_id INTEGER NOT NULL DEFAULT 0,
        item_code TEXT NOT NULL DEFAULT '',
        item_name TEXT NOT NULL,
        system_name TEXT NOT NULL DEFAULT '',
        series_name TEXT NOT NULL DEFAULT '',
        color_id INTEGER,
        color_name TEXT NOT NULL DEFAULT '',
        unit TEXT NOT NULL DEFAULT 'pcs',
        length_mm REAL NOT NULL DEFAULT 0.0,
        width_mm REAL NOT NULL DEFAULT 0.0,
        quantity REAL NOT NULL DEFAULT 1.0,
        unit_price REAL NOT NULL DEFAULT 0.0,
        tax_rate REAL NOT NULL DEFAULT 0.0,
        total_price REAL NOT NULL DEFAULT 0.0,
        notes TEXT NOT NULL DEFAULT '',
        FOREIGN KEY (sale_id) REFERENCES MaterialSales(id) ON DELETE CASCADE
      )
    ''');
    try {
      await db.execute(
        "ALTER TABLE MaterialSaleItems ADD COLUMN series_name TEXT NOT NULL DEFAULT '';",
      );
    } catch (_) {}
    try {
      await db.execute(
        "ALTER TABLE MaterialSaleItems ADD COLUMN system_name TEXT NOT NULL DEFAULT '';",
      );
    } catch (_) {}
    try {
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_material_sales_date '
        'ON MaterialSales(sale_date)',
      );
    } catch (_) {}
    try {
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_material_sale_items_sale '
        'ON MaterialSaleItems(sale_id)',
      );
    } catch (_) {}
    for (final statement in <String>[
      'ALTER TABLE MaterialSales ADD COLUMN is_deleted INTEGER NOT NULL DEFAULT 0;',
      'ALTER TABLE MaterialSales ADD COLUMN deleted_at TEXT;',
      'ALTER TABLE MaterialSales ADD COLUMN deleted_by TEXT;',
      'ALTER TABLE MaterialSales ADD COLUMN status_before_delete TEXT;',
    ]) {
      try {
        await db.execute(statement);
      } catch (_) {}
    }
    await db.execute('''
      CREATE TABLE IF NOT EXISTS BusinessDayClosings (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        distributed_id TEXT,
        business_date TEXT NOT NULL,
        scope TEXT NOT NULL,
        expected_cash REAL NOT NULL DEFAULT 0.0,
        counted_cash REAL NOT NULL DEFAULT 0.0,
        difference REAL NOT NULL DEFAULT 0.0,
        sales_total REAL NOT NULL DEFAULT 0.0,
        income_total REAL NOT NULL DEFAULT 0.0,
        expense_total REAL NOT NULL DEFAULT 0.0,
        closed_by TEXT NOT NULL DEFAULT '',
        notes TEXT NOT NULL DEFAULT '',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        UNIQUE(business_date, scope)
      )
    ''');
  }

  Future<void> _ensureInventoryAlertSchema(DatabaseExecutor db) =>
      _ensureSchemaOnce(db, '_ensureInventoryAlertSchema', () => _ensureInventoryAlertSchemaUncached(db));

  Future<void> _ensureInventoryAlertSchemaUncached(DatabaseExecutor db) async {
    try {
      await db.execute(
        'ALTER TABLE CurrentStock ADD COLUMN low_stock_alert_enabled INTEGER NOT NULL DEFAULT 0;',
      );
    } catch (_) {}
  }

  Future<void> _ensureOrderInventoryIssueSchema(DatabaseExecutor db) =>
      _ensureSchemaOnce(db, '_ensureOrderInventoryIssueSchema', () => _ensureOrderInventoryIssueSchemaUncached(db));

  Future<void> _ensureOrderInventoryIssueSchemaUncached(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS OrderInventoryIssueSessions (
        id INTEGER PRIMARY KEY,
        order_id INTEGER NOT NULL UNIQUE,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
  }

  Future<void> _ensureDashboardActivitiesInfrastructure(
    DatabaseExecutor executor,
  ) async {
    if (SqlDatabase._dashboardActivitiesInfrastructureReady) return;
    await executor.execute('''
      CREATE TABLE IF NOT EXISTS DashboardActivities (
        id INTEGER PRIMARY KEY,
        activity_type TEXT NOT NULL,
        entity_id INTEGER NOT NULL,
        related_order_id INTEGER,
        document TEXT NOT NULL DEFAULT '',
        party TEXT NOT NULL DEFAULT '',
        user_name TEXT NOT NULL DEFAULT '',
        occurred_at TEXT NOT NULL
      )
    ''');
    SqlDatabase._dashboardActivitiesInfrastructureReady = true;
  }

  Future<void> _ensureAuditLogsInfrastructure(DatabaseExecutor executor) async {
    if (SqlDatabase._auditLogsInfrastructureReady) return;
    await executor.execute('''
      CREATE TABLE IF NOT EXISTS AuditLogs (
        id INTEGER PRIMARY KEY,
        action_type TEXT NOT NULL,
        entity_type TEXT NOT NULL,
        entity_id TEXT NOT NULL,
        entity_title TEXT,
        user_name TEXT,
        details TEXT,
        timestamp TEXT NOT NULL,
        updated_at TEXT NOT NULL DEFAULT ''
      )
    ''');
    try {
      await executor.execute(
        'ALTER TABLE AuditLogs ADD COLUMN updated_at TEXT NOT NULL DEFAULT "";',
      );
    } catch (_) {}
    // The audit screen pages newest-first; without this index every page
    // sorts the whole table, including its large JSON snapshots.
    await executor.execute(
      'CREATE INDEX IF NOT EXISTS idx_audit_logs_timestamp ON AuditLogs(timestamp DESC, id DESC);',
    );
    SqlDatabase._auditLogsInfrastructureReady = true;
  }

  Future<void> _ensureAccessoryLinksSchema(DatabaseExecutor executor) {
    final cachedTask = SqlDatabase._accessoryLinksSchemaTask;
    if (identical(SqlDatabase._accessoryLinksSchemaOwner, executor) && cachedTask != null) {
      return cachedTask;
    }
    final task = _ensureAccessoryLinksSchemaImpl(executor);
    SqlDatabase._accessoryLinksSchemaOwner = executor;
    SqlDatabase._accessoryLinksSchemaTask = task;
    return task;
  }

  Future<void> _ensureAccessoryLinksSchemaImpl(
    DatabaseExecutor executor,
  ) async {
    await executor.execute('''
      CREATE TABLE IF NOT EXISTS AccessoryLinks (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        source_accessory_id INTEGER NOT NULL,
        target_accessory_id INTEGER NOT NULL,
        quantity INTEGER NOT NULL DEFAULT 1,
        is_active INTEGER NOT NULL DEFAULT 1,
        UNIQUE(source_accessory_id, target_accessory_id)
      )
    ''');
    await executor.execute('''
      INSERT OR IGNORE INTO AccessoryLinks
        (source_accessory_id, target_accessory_id, quantity, is_active)
      SELECT id, linked_accessory_id,
             CASE WHEN linked_accessory_count > 0 THEN linked_accessory_count ELSE 1 END,
             1
      FROM Accessories
      WHERE linked_accessory_id IS NOT NULL
    ''');
    await executor.execute('''
      INSERT OR IGNORE INTO AccessoryLinks
        (source_accessory_id, target_accessory_id, quantity, is_active)
      SELECT id, gache_accessory_id,
             CASE WHEN gache_count > 0 THEN gache_count ELSE 1 END,
             1
      FROM Accessories
      WHERE gache_accessory_id IS NOT NULL
    ''');
    await executor.execute('''
      CREATE TABLE IF NOT EXISTS AccessoryRoleLinks (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        source_accessory_id INTEGER NOT NULL,
        target_role_key TEXT NOT NULL,
        quantity INTEGER NOT NULL DEFAULT 1,
        is_active INTEGER NOT NULL DEFAULT 1,
        UNIQUE(source_accessory_id, target_role_key)
      )
    ''');
    // Convert legacy product-to-product links into role links whenever the
    // target already has a configured catalogue role.
    await executor.execute('''
      INSERT OR IGNORE INTO AccessoryRoleLinks
        (source_accessory_id, target_role_key, quantity, is_active)
      SELECT l.source_accessory_id, r.role_key, l.quantity, l.is_active
      FROM AccessoryLinks l
      INNER JOIN CatalogItemRules r
        ON r.item_table = 'Accessories'
       AND r.item_id = l.target_accessory_id
       AND r.is_active = 1
      WHERE TRIM(COALESCE(r.role_key, '')) != ''
    ''');
  }

  /// Per-profile pricing classification used by the material calculator.
  /// A row is optional: when absent, the calculator keeps its legacy role
  /// classification (frame/sash/mullion/plant...).
  Future<void> _ensureProfileCalculationRulesTable(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS ProfileCalculationRules (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        section_id INTEGER NOT NULL UNIQUE,
        calculation_mode TEXT NOT NULL DEFAULT 'auto',
        linear_meter_multiplier REAL NOT NULL DEFAULT 1.0,
        exclude_from_pricing INTEGER NOT NULL DEFAULT 0,
        updated_at TEXT NOT NULL DEFAULT ''
      )
    ''');
    // Upgrade the short-lived first schema, if it was created before the
    // table became part of the catalogue sync contract.
    try {
      await db.execute(
        'ALTER TABLE ProfileCalculationRules ADD COLUMN id INTEGER;',
      );
      await db.execute(
        'UPDATE ProfileCalculationRules SET id = section_id WHERE id IS NULL;',
      );
    } catch (_) {}
    try {
      await db.execute(
        'ALTER TABLE ProfileCalculationRules ADD COLUMN exclude_from_pricing INTEGER NOT NULL DEFAULT 0',
      );
    } catch (_) {}
  }

  /// Creates useful first-run values for every catalogue profile without
  /// overwriting a rule previously customized by the administrator.
  Future<void> seedDefaultProfileCalculationRules() async {
    final myDb = await db;
    if (myDb == null) return;
    await _ensureProfileCalculationRulesTable(myDb);
    try {
      final existing = await myDb.rawQuery(
        'SELECT 1 FROM ProfileCalculationRules LIMIT 1',
      );
      if (existing.isNotEmpty) return;
    } catch (_) {}
    List<Map<String, dynamic>> sections;
    try {
      sections = await myDb.query(
        'Sections',
        columns: [
          'id',
          'type',
          'name',
          'code',
          'is_frame',
          'is_sash',
          'is_mullion',
        ],
      );
    } catch (_) {
      sections = await myDb.query(
        'Sections',
        columns: ['id', 'type', 'name', 'code'],
      );
    }
    await myDb.transaction((txn) async {
      for (final section in sections) {
        final sectionId = (section['id'] as num?)?.toInt();
        if (sectionId == null) continue;
        final role = '${section['type'] ?? ''}'.trim().toLowerCase();
        final profileText =
            '$role ${section['name'] ?? ''} ${section['code'] ?? ''}'
                .toLowerCase();
        final isMainProfile =
            section['is_frame'] == 1 ||
            section['is_sash'] == 1 ||
            section['is_mullion'] == 1 ||
            profileText.contains('frame') ||
            profileText.contains('cadre') ||
            profileText.contains('ouvrant') ||
            profileText.contains('sash') ||
            profileText.contains('mullion') ||
            profileText.contains('traverse') ||
            profileText.contains('batmo') ||
            profileText.contains('batbo') ||
            profileText.contains('إطار') ||
            profileText.contains('ظلفة') ||
            profileText.contains('تقسيم') ||
            profileText.contains('باتمو') ||
            profileText.contains('باتبو') ||
            profileText.contains('بلانت');
        final isPlant =
            profileText.contains('plant') ||
            profileText.contains('plinthe') ||
            profileText.contains('بلانت');
        await txn.insert('ProfileCalculationRules', {
          'section_id': sectionId,
          'calculation_mode': isMainProfile ? 'linear_meter' : 'base_price',
          'linear_meter_multiplier': isPlant ? 2.0 : 1.0,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
      }
    });
  }

  Future<void> _ensureTemperedGlassItemsTable(Database dbInstance) =>
      _ensureSchemaOnce(dbInstance, '_ensureTemperedGlassItemsTable', () => _ensureTemperedGlassItemsTableUncached(dbInstance));

  Future<void> _ensureTemperedGlassItemsTableUncached(Database dbInstance) async {
    await dbInstance.execute('''
      CREATE TABLE IF NOT EXISTS TemperedGlassItems (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        category TEXT NOT NULL,
        category_name TEXT,
        type TEXT NOT NULL DEFAULT 'accessoire',
        unit TEXT NOT NULL DEFAULT 'piece',
        price REAL NOT NULL DEFAULT 0.0,
        cost_price REAL NOT NULL DEFAULT 0.0,
        default_qty INTEGER NOT NULL DEFAULT 1,
        holes_count INTEGER DEFAULT 0,
        entraxe REAL DEFAULT 0.0,
        image_path TEXT DEFAULT '',
        handle_design_code TEXT DEFAULT '',
        notes TEXT DEFAULT '',
        is_active INTEGER NOT NULL DEFAULT 1
      )
    ''');
    try {
      await dbInstance.execute(
        "ALTER TABLE TemperedGlassItems ADD COLUMN handle_design_code TEXT DEFAULT ''",
      );
    } catch (_) {}
    // Stable identity of a workshop service (edge finishing, frosting); the
    // cost table looks services up by this code, never by their name.
    try {
      await dbInstance.execute(
        "ALTER TABLE TemperedGlassItems ADD COLUMN service_code TEXT DEFAULT ''",
      );
    } catch (_) {}
    // Drilling pattern of an accessory (see GlassAccessoryTemplate), where
    // it is mounted, the glass thickness it is made for, and the family of
    // a gasket or the role of a profile.
    for (final column in const [
      "hole_diameters TEXT DEFAULT ''",
      "hole_spacings TEXT DEFAULT ''",
      "hole_layout TEXT DEFAULT 'horizontal'",
      "mount_target TEXT DEFAULT 'all'",
      'glass_thickness_mm REAL DEFAULT 0.0',
      "joint_type TEXT DEFAULT ''",
      "profile_role TEXT DEFAULT ''",
      // JSON list of {color, price}: the accessory's price in each colour.
      "color_prices TEXT DEFAULT ''",
    ]) {
      try {
        await dbInstance.execute(
          'ALTER TABLE TemperedGlassItems ADD COLUMN $column',
        );
      } catch (_) {}
    }
  }

  /// Adds the edge-finishing and frosting services at the rates the cost
  /// table used to hard-code, so the workshop can set its own prices. A
  /// service is added again when its code is missing (a catalogue download
  /// replaces this table); to stop using one, deactivate it instead.
  Future<void> _ensureTemperedGlassServicesSeeded(
    DatabaseExecutor myDb,
  ) async {
    const services = [
      {
        'service_code': SqlDatabase.temperedGlassEdgeSmoothService,
        'name': 'شطب الحواف - ناعم (Façonnage poli)',
        'unit': 'meter',
        'price': 350.0,
      },
      {
        'service_code': SqlDatabase.temperedGlassEdgeExtraSmoothService,
        'name': 'شطب الحواف - ناعم جدًا (Façonnage extra poli)',
        'unit': 'meter',
        'price': 600.0,
      },
      {
        'service_code': SqlDatabase.temperedGlassFrostingService,
        'name': 'السفع الرملي (Sablage)',
        'unit': 'sqm',
        'price': 1200.0,
      },
    ];
    for (final service in services) {
      final existing = await myDb.query(
        'TemperedGlassItems',
        columns: const ['id'],
        where: 'service_code = ?',
        whereArgs: [service['service_code']],
        limit: 1,
      );
      if (existing.isNotEmpty) continue;
      await myDb.insert('TemperedGlassItems', {
        ...service,
        'category': 'faconnage',
        'category_name': 'الخدمات والتشطيب',
        'type': 'service',
        'cost_price': 0.0,
        'default_qty': 1,
        'is_active': 1,
      });
    }
  }

  Future<void> seedDefaultTemperedGlassItems() async {
    final myDb = await db;
    if (myDb == null) return;
    await _ensureTemperedGlassItemsTable(myDb);
    final count =
        Sqflite.firstIntValue(
          await myDb.rawQuery('SELECT COUNT(*) FROM TemperedGlassItems'),
        ) ??
        0;
    if (count > 0) return;

    final defaultItems = [
      // Handles (مقابض)
      {
        'name': 'مقبض باب زجاجي ستانلس 30 سم (Poignée inox 30cm)',
        'category': 'poignee',
        'category_name': 'المقابض',
        'type': 'accessoire',
        'unit': 'piece',
        'price': 4500.0,
        'cost_price': 3200.0,
        'default_qty': 1,
        'holes_count': 2,
        'entraxe': 200.0,
        'notes': 'Entraxe 200 mm - Ø25 mm',
      },
      {
        'name': 'مقبض باب زجاجي ستانلس 45 سم (Poignée inox 45cm)',
        'category': 'poignee',
        'category_name': 'المقابض',
        'type': 'accessoire',
        'unit': 'piece',
        'price': 5800.0,
        'cost_price': 4200.0,
        'default_qty': 1,
        'holes_count': 2,
        'entraxe': 300.0,
        'notes': 'Entraxe 300 mm - Ø25 mm',
      },
      {
        'name': 'مقبض دائري مفرد للباب (Bouton rond inox)',
        'category': 'poignee',
        'category_name': 'المقابض',
        'type': 'accessoire',
        'unit': 'piece',
        'price': 2200.0,
        'cost_price': 1500.0,
        'default_qty': 1,
        'holes_count': 1,
        'entraxe': 0.0,
        'notes': 'Trou unique Ø10-12 mm',
      },
      {
        'name': 'مقبض مناشف كابين دوش (Porte-serviette douche)',
        'category': 'poignee',
        'category_name': 'المقابض',
        'type': 'accessoire',
        'unit': 'piece',
        'price': 4800.0,
        'cost_price': 3500.0,
        'default_qty': 1,
        'holes_count': 2,
        'entraxe': 450.0,
        'notes': 'Entraxe 450 mm',
      },
      // Hinges & Clamps (مفصلات ومشابك)
      {
        'name': 'مفصلة زجاج / جدار 90° ستانلس (Charnière verre/mur 90°)',
        'category': 'charniere',
        'category_name': 'المفصلات',
        'type': 'accessoire',
        'unit': 'piece',
        'price': 3800.0,
        'cost_price': 2700.0,
        'default_qty': 2,
        'holes_count': 2,
        'entraxe': 58.0,
        'notes': 'Inox 304 pour douche',
      },
      {
        'name': 'مفصلة زجاج / زجاج 180° (Charnière verre/verre 180°)',
        'category': 'charniere',
        'category_name': 'المفصلات',
        'type': 'accessoire',
        'unit': 'piece',
        'price': 4200.0,
        'cost_price': 3000.0,
        'default_qty': 2,
        'holes_count': 4,
        'entraxe': 58.0,
        'notes': 'Inox 304',
      },
      {
        'name': 'مفصلة زجاج / زجاج 90° (Charnière verre/verre 90°)',
        'category': 'charniere',
        'category_name': 'المفصلات',
        'type': 'accessoire',
        'unit': 'piece',
        'price': 4400.0,
        'cost_price': 3100.0,
        'default_qty': 2,
        'holes_count': 4,
        'entraxe': 58.0,
        'notes': 'Angle 90 degrés',
      },
      {
        'name': 'مفصلة أرضية محورية لفاترين (Pivot de sol / Pivot bas)',
        'category': 'charniere',
        'category_name': 'المفصلات',
        'type': 'accessoire',
        'unit': 'piece',
        'price': 14000.0,
        'cost_price': 10500.0,
        'default_qty': 1,
        'holes_count': 0,
        'entraxe': 0.0,
        'notes': 'Pour porte vitrine lourde',
      },
      {
        'name': 'مربط / مشبك زجاج حائطي (Pince à verre mur)',
        'category': 'fixation',
        'category_name': 'التثبيت والمشابك',
        'type': 'accessoire',
        'unit': 'piece',
        'price': 1800.0,
        'cost_price': 1200.0,
        'default_qty': 3,
        'holes_count': 1,
        'entraxe': 0.0,
        'notes': 'Fixation fixe sans encoche ou avec trou',
      },
      {
        'name': 'مربط زجاج / زجاج (Pince verre/verre)',
        'category': 'fixation',
        'category_name': 'التثبيت والمشابك',
        'type': 'accessoire',
        'unit': 'piece',
        'price': 2200.0,
        'cost_price': 1500.0,
        'default_qty': 2,
        'holes_count': 2,
        'entraxe': 0.0,
        'notes': 'Liaison deux panneaux fixes',
      },
      // Profiles & Rails (القطاعات والسكك)
      {
        'name': 'بروفيل ألومنيوم U للزجاج 15×15 مم (Profilé U 15x15)',
        'category': 'profile',
        'category_name': 'القطاعات والسكك',
        'type': 'profile',
        'unit': 'meter',
        'price': 1200.0,
        'cost_price': 850.0,
        'default_qty': 2,
        'holes_count': 0,
        'entraxe': 0.0,
        'notes': 'Pour verre 8-10 mm',
      },
      {
        'name': 'بروفيل ألومنيوم U للزجاج 20×20 مم (Profilé U 20x20)',
        'category': 'profile',
        'category_name': 'القطاعات والسكك',
        'type': 'profile',
        'unit': 'meter',
        'price': 1600.0,
        'cost_price': 1100.0,
        'default_qty': 2,
        'holes_count': 0,
        'entraxe': 0.0,
        'notes': 'Pour verre 10-12 mm',
      },
      {
        'name': 'سكة علوية كابين دوش مع رولات (Rail haut + Chariots roulettes)',
        'category': 'profile',
        'category_name': 'القطاعات والسكك',
        'type': 'profile',
        'unit': 'piece',
        'price': 16500.0,
        'cost_price': 12000.0,
        'default_qty': 1,
        'holes_count': 2,
        'entraxe': 0.0,
        'notes': 'Système coulissant complet inox',
      },
      {
        'name': 'أنبوب تثبيت علوي ستانلس Ø25 مم (Tube raidisseur inox Ø25)',
        'category': 'profile',
        'category_name': 'القطاعات والسكك',
        'type': 'profile',
        'unit': 'meter',
        'price': 3500.0,
        'cost_price': 2500.0,
        'default_qty': 1,
        'holes_count': 0,
        'entraxe': 0.0,
        'notes': 'Tringle de maintien haute',
      },
      // Seals (جوانات وعوازل)
      {
        'name': 'جوان مغناطيسي للباب 90° زاوية (Joint magnétique 90°)',
        'category': 'joint',
        'category_name': 'الجوانات والعوازل',
        'type': 'accessoire',
        'unit': 'piece',
        'price': 2100.0,
        'cost_price': 1450.0,
        'default_qty': 1,
        'holes_count': 0,
        'entraxe': 0.0,
        'notes': 'Fermeture magnétique 90° entre deux portes ou porte/fixe',
      },
      {
        'name': 'جوان مغناطيسي للباب 180° مستقيم (Joint magnétique 180°)',
        'category': 'joint',
        'category_name': 'الجوانات والعوازل',
        'type': 'accessoire',
        'unit': 'piece',
        'price': 1900.0,
        'cost_price': 1300.0,
        'default_qty': 1,
        'holes_count': 0,
        'entraxe': 0.0,
        'notes': 'Longueur 2.20m fermeture droite',
      },
      {
        'name': 'جوان حرف F مانع للماء (Joint profil F anti-éclaboussures)',
        'category': 'joint',
        'category_name': 'الجوانات والعوازل',
        'type': 'accessoire',
        'unit': 'piece',
        'price': 1600.0,
        'cost_price': 1100.0,
        'default_qty': 1,
        'holes_count': 0,
        'entraxe': 0.0,
        'notes': 'Profil en F d\'étanchéité latérale',
      },
      {
        'name': 'جوان شفة سفلية مانع تسرب الماء (Joint bas bavette)',
        'category': 'joint',
        'category_name': 'الجوانات والعوازل',
        'type': 'accessoire',
        'unit': 'piece',
        'price': 1500.0,
        'cost_price': 950.0,
        'default_qty': 1,
        'holes_count': 0,
        'entraxe': 0.0,
        'notes': 'Longueur 1.00m',
      },
      // Locks & Latches (أقفال ومزاليج)
      {
        'name': 'قفل زجاج سفلي مع ركيزة أرضية (Serrure basse verre sol)',
        'category': 'serrure',
        'category_name': 'الأقفال',
        'type': 'accessoire',
        'unit': 'piece',
        'price': 4800.0,
        'cost_price': 3400.0,
        'default_qty': 1,
        'holes_count': 1,
        'entraxe': 0.0,
        'notes': 'Verrouillage au sol pour vitrine ou porte',
      },
    ];

    for (final item in defaultItems) {
      await myDb.insert('TemperedGlassItems', item);
    }
  }

  Future<void> _ensureVROHandlesAndColorsSeeded(DatabaseExecutor myDb) async {
    // 1. Ensure V-RO handles in TemperedGlassItems
    final vroItems = [
      {
        'name': 'Poignée V-RO Ronde 200 mm (مقبض V-RO دائري)',
        'category': 'poignee',
        'category_name': 'المقابض',
        'type': 'accessoire',
        'unit': 'piece',
        'price': 1000.0,
        'cost_price': 0.0,
        'default_qty': 1,
        'holes_count': 2,
        'entraxe': 200.0,
        'image_path': 'assets/images/poignee_ro_ronde.png',
        'notes': 'Entraxe 200 mm - Trou Ø12 mm - Inox brossé',
        'is_active': 1,
      },
      {
        'name': 'Poignée V-RO Carrée 200 mm (مقبض V-RO مربع)',
        'category': 'poignee',
        'category_name': 'المقابض',
        'type': 'accessoire',
        'unit': 'piece',
        'price': 1000.0,
        'cost_price': 0.0,
        'default_qty': 1,
        'holes_count': 2,
        'entraxe': 200.0,
        'image_path': 'assets/images/poignee_ro_carree.png',
        'notes': 'Entraxe 200 mm - Trou Ø10 mm - Inox brossé',
        'is_active': 1,
      },
      {
        'name':
            'Barre porte-serviettes V-RO Ronde 400 mm (مقبض مناشف V-RO دائري)',
        'category': 'poignee',
        'category_name': 'المقابض',
        'type': 'accessoire',
        'unit': 'piece',
        'price': 1000.0,
        'cost_price': 0.0,
        'default_qty': 1,
        'holes_count': 2,
        'entraxe': 400.0,
        'image_path': 'assets/images/porte_serviettes_ro_rond.png',
        'notes': 'Entraxe 400 mm - Trou Ø12 mm - Inox brossé',
        'is_active': 1,
      },
      {
        'name':
            'Barre porte-serviettes V-RO Carrée 400 mm (مقبض مناشف V-RO مربع)',
        'category': 'poignee',
        'category_name': 'المقابض',
        'type': 'accessoire',
        'unit': 'piece',
        'price': 1000.0,
        'cost_price': 0.0,
        'default_qty': 1,
        'holes_count': 2,
        'entraxe': 400.0,
        'image_path': 'assets/images/porte_serviettes_ro_carre.png',
        'notes': 'Entraxe 400 mm - Trou Ø10 mm - Inox brossé',
        'is_active': 1,
      },
    ];

    for (final item in vroItems) {
      final rows = await myDb.query(
        'TemperedGlassItems',
        where: 'name = ?',
        whereArgs: [item['name']],
      );
      if (rows.isEmpty) {
        await myDb.insert('TemperedGlassItems', item);
      } else {
        final current = rows.first;
        final currentImg = current['image_path']?.toString() ?? '';
        if (currentImg.isEmpty) {
          await myDb.update(
            'TemperedGlassItems',
            {'image_path': item['image_path']},
            where: 'id = ?',
            whereArgs: [current['id']],
          );
        }
      }
    }

    // 2. Ensure Colors matching image (Inox brossé, Champagne, Bronze)
    final newColors = [
      {
        'name': 'Inox brossé (ستانلس ستيل)',
        'hex_code': '#B0B5B9',
        'type': 'Global',
      },
      {'name': 'Champagne (شامبانيا)', 'hex_code': '#C5A059', 'type': 'Global'},
      {'name': 'Bronze (برونزي)', 'hex_code': '#614E3F', 'type': 'Global'},
    ];
    for (final c in newColors) {
      final rows = await myDb.query(
        'Colors',
        where: 'name = ?',
        whereArgs: [c['name']],
      );
      if (rows.isEmpty) {
        await myDb.insert('Colors', c);
      }
    }
  }

  Future<void> _ensureTemperedGlassSystemsAndRulesTables(
    Database dbInstance,
  ) async {
    await dbInstance.execute('''
      CREATE TABLE IF NOT EXISTS TemperedGlassSystems (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        code TEXT NOT NULL UNIQUE,
        name_ar TEXT NOT NULL,
        name_fr TEXT DEFAULT '',
        name_en TEXT DEFAULT '',
        category TEXT DEFAULT 'douche',
        icon_name TEXT DEFAULT 'shower',
        description TEXT DEFAULT '',
        default_kit_code TEXT DEFAULT '',
        is_active INTEGER NOT NULL DEFAULT 1,
        display_order INTEGER DEFAULT 0
      )
    ''');

    await dbInstance.execute('''
      CREATE TABLE IF NOT EXISTS TemperedGlassKits (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        code TEXT NOT NULL UNIQUE,
        name TEXT NOT NULL,
        system_code TEXT DEFAULT '',
        target_panel TEXT NOT NULL DEFAULT 'door',
        description TEXT DEFAULT '',
        is_active INTEGER NOT NULL DEFAULT 1
      )
    ''');

    await dbInstance.execute('''
      CREATE TABLE IF NOT EXISTS TemperedGlassKitHoles (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        kit_id INTEGER NOT NULL,
        hole_index INTEGER NOT NULL DEFAULT 1,
        diameter_mm REAL NOT NULL DEFAULT 20.0,
        ref_x TEXT NOT NULL DEFAULT 'left',
        offset_x_mm REAL NOT NULL DEFAULT 80.0,
        ref_y TEXT NOT NULL DEFAULT 'top',
        offset_y_mm REAL NOT NULL DEFAULT 35.0,
        reference_mode TEXT NOT NULL DEFAULT 'edge',
        min_panel_width_mm REAL DEFAULT 0.0,
        max_panel_width_mm REAL DEFAULT 0.0,
        purpose TEXT DEFAULT 'kit_roller',
        target_panel TEXT NOT NULL DEFAULT 'door'
      )
    ''');

    await dbInstance.execute('''
      CREATE TABLE IF NOT EXISTS TemperedGlassKitComponents (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        kit_id INTEGER NOT NULL,
        item_id INTEGER NOT NULL,
        component_type TEXT NOT NULL DEFAULT 'accessory',
        target_panel TEXT NOT NULL DEFAULT 'all',
        quantity REAL NOT NULL DEFAULT 1.0,
        glass_thickness_mm REAL NOT NULL DEFAULT 0.0,
        is_default INTEGER NOT NULL DEFAULT 1,
        notes TEXT DEFAULT '',
        UNIQUE(kit_id, item_id),
        FOREIGN KEY (kit_id) REFERENCES TemperedGlassKits(id) ON DELETE CASCADE,
        FOREIGN KEY (item_id) REFERENCES TemperedGlassItems(id) ON DELETE CASCADE
      )
    ''');

    final kitHoleColumns = await _tableColumns(
      dbInstance,
      'TemperedGlassKitHoles',
    );
    if (!kitHoleColumns.contains('target_panel')) {
      await dbInstance.execute(
        "ALTER TABLE TemperedGlassKitHoles ADD COLUMN target_panel TEXT NOT NULL DEFAULT 'door'",
      );
      await dbInstance.execute('''
        UPDATE TemperedGlassKitHoles
        SET target_panel = COALESCE(
          (SELECT target_panel
           FROM TemperedGlassKits
           WHERE TemperedGlassKits.id = TemperedGlassKitHoles.kit_id),
          'door'
        )
      ''');
    }

    await dbInstance.execute('''
      CREATE TABLE IF NOT EXISTS TemperedGlassSystemRules (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        system_code TEXT NOT NULL,
        item_id INTEGER,
        kit_id INTEGER,
        rule_type TEXT NOT NULL,
        glass_thickness_mm REAL DEFAULT 0.0,
        is_default INTEGER NOT NULL DEFAULT 0,
        is_active INTEGER NOT NULL DEFAULT 1,
        notes TEXT DEFAULT ''
      )
    ''');
  }

  Future<void> seedDefaultTemperedGlassSystemsAndKits() async {
    final myDb = await db;
    if (myDb == null) return;
    await _ensureTemperedGlassSystemsAndRulesTables(myDb);

    final sysCount =
        Sqflite.firstIntValue(
          await myDb.rawQuery('SELECT COUNT(*) FROM TemperedGlassSystems'),
        ) ??
        0;

    if (sysCount == 0) {
      final defaultSystems = [
        {
          'code': 'coulissante',
          'name_ar': 'كابينة دوش منزلقة (I)',
          'name_fr': 'Cabine de douche coulissante (I)',
          'name_en': 'Sliding shower cabin (I)',
          'category': 'douche',
          'icon_name': 'compare_arrows',
          'description':
              'كابينة دوش مستقيمة منزلقة تتكون من لوح ثابت ولوح باب منزلق',
          'default_kit_code': 'kit_alfa',
          'is_active': 1,
          'display_order': 1,
        },
        {
          'code': 'cabine_l',
          'name_ar': 'كابينة دوش زاوية (L)',
          'name_fr': 'Cabine de douche d’angle (L)',
          'name_en': 'Corner shower cabin (L)',
          'category': 'douche',
          'icon_name': 'shower',
          'description': 'كابينة دوش على شكل زاوية L مع جانب ثابت وباب',
          'default_kit_code': 'kit_alfa',
          'is_active': 1,
          'display_order': 2,
        },
        {
          'code': 'cabine_porte',
          'name_ar': 'كابينة دوش بباب واحد',
          'name_fr': 'Cabine de douche porte simple',
          'name_en': 'Single door shower cabin',
          'category': 'douche',
          'icon_name': 'door_front_door_outlined',
          'description': 'كابينة دوش بباب مفصلي واحد',
          'default_kit_code': 'kit_charniere_mur',
          'is_active': 1,
          'display_order': 3,
        },
        {
          'code': 'cabine_fixe_porte',
          'name_ar': 'كابينة دوش ثابت مع باب',
          'name_fr': 'Cabine de douche fixe + porte',
          'name_en': 'Fixed panel + door shower cabin',
          'category': 'douche',
          'icon_name': 'meeting_room_outlined',
          'description': 'كابينة دوش تتكون من لوح ثابت مع باب مفصلي',
          'default_kit_code': 'kit_charniere_verre',
          'is_active': 1,
          'display_order': 4,
        },
        {
          'code': 'cabine_u',
          'name_ar': 'كابينة دوش زاوية (U)',
          'name_fr': 'Cabine de douche en U',
          'name_en': 'U-shaped shower cabin',
          'category': 'douche',
          'icon_name': 'check_box_outline_blank',
          'description': 'كابينة دوش محاطة بثلاث جهات ثابتة وباب',
          'default_kit_code': 'kit_alfa',
          'is_active': 1,
          'display_order': 5,
        },
        {
          'code': 'vitrine_1p',
          'name_ar': 'فيترين بباب واحد',
          'name_fr': 'Vitrine à une porte',
          'name_en': 'One-door storefront',
          'category': 'vitrine',
          'icon_name': 'storefront',
          'description': 'واجهة زجاجية بمحور دوران أو مفصلات مع باب واحد',
          'default_kit_code': 'kit_pivot',
          'is_active': 1,
          'display_order': 6,
        },
        {
          'code': 'vitrine_2p',
          'name_ar': 'فيترين ببابين',
          'name_fr': 'Vitrine à deux portes',
          'name_en': 'Two-door storefront',
          'category': 'vitrine',
          'icon_name': 'meeting_room_outlined',
          'description': 'واجهة زجاجية ببابين مزدوجين',
          'default_kit_code': 'kit_pivot',
          'is_active': 1,
          'display_order': 7,
        },
        {
          'code': 'paroi_fixe',
          'name_ar': 'حاجز دوش ثابت (Paroi fixe)',
          'name_fr': 'Paroi de douche fixe',
          'name_en': 'Fixed shower screen',
          'category': 'douche',
          'icon_name': 'crop_portrait',
          'description': 'لوح زجاجي ثابت لحماية الدوش بدون أبواب متحركة',
          'default_kit_code': '',
          'is_active': 1,
          'display_order': 8,
        },
      ];

      for (final sys in defaultSystems) {
        await myDb.insert('TemperedGlassSystems', sys);
      }
    }

    final kitCount =
        Sqflite.firstIntValue(
          await myDb.rawQuery('SELECT COUNT(*) FROM TemperedGlassKits'),
        ) ??
        0;

    if (kitCount == 0) {
      final defaultKits = [
        {
          'code': 'kit_alfa',
          'name': 'كيت ألفا (Kit Alfa)',
          'system_code': 'coulissante',
          'target_panel': 'door',
          'description':
              'كيت كابينة دوش كوليسا قياسي - ثقبان علويان للرولمان في الباب',
          'is_active': 1,
        },
        {
          'code': 'kit_beta',
          'name': 'كيت بيتا (Kit Beta)',
          'system_code': 'coulissante',
          'target_panel': 'door',
          'description':
              'كيت كابينة كوليسا للرولمانات الكبيرة Ø25 مم وخلوص 100 مم',
          'is_active': 1,
        },
        {
          'code': 'kit_pivot',
          'name': 'كيت محور دوران (Kit Pivot)',
          'system_code': 'vitrine_1p',
          'target_panel': 'door',
          'description': 'محور دوران أرضي وعلوي لأبواب الواجهات والفيترين',
          'is_active': 1,
        },
        {
          'code': 'kit_charniere_mur',
          'name': 'كيت مفصلات زجاج / جدار (Charnières Verre-Mur)',
          'system_code': 'cabine_porte',
          'target_panel': 'door',
          'description': 'مفصلتان لتثبيت باب الزجاج على الجدار مباشرة',
          'is_active': 1,
        },
        {
          'code': 'kit_charniere_verre',
          'name': 'كيت مفصلات زجاج / زجاج 180° (Charnières Verre-Verre)',
          'system_code': 'cabine_fixe_porte',
          'target_panel': 'door',
          'description': 'مفصلتان لتثبيت باب الزجاج على لوح زجاجي ثابت',
          'is_active': 1,
        },
      ];

      for (final kit in defaultKits) {
        final kitId = await myDb.insert('TemperedGlassKits', kit);
        final code = kit['code'] as String;

        if (code == 'kit_alfa') {
          // Hole 1: Top-Left roller
          await myDb.insert('TemperedGlassKitHoles', {
            'kit_id': kitId,
            'hole_index': 1,
            'diameter_mm': 20.0,
            'ref_x': 'left',
            'offset_x_mm': 80.0,
            'ref_y': 'top',
            'offset_y_mm': 35.0,
            'reference_mode': 'edge', // from edge to edge of hole
            'min_panel_width_mm': 0.0,
            'max_panel_width_mm': 0.0,
            'purpose': 'door_top_left',
          });
          // Hole 2: Top-Right roller
          await myDb.insert('TemperedGlassKitHoles', {
            'kit_id': kitId,
            'hole_index': 2,
            'diameter_mm': 20.0,
            'ref_x': 'right',
            'offset_x_mm': 80.0,
            'ref_y': 'top',
            'offset_y_mm': 35.0,
            'reference_mode': 'edge',
            'min_panel_width_mm': 0.0,
            'max_panel_width_mm': 0.0,
            'purpose': 'door_top_right',
          });
          // Conditional Hole 3: Center roller if door width >= 1200 mm
          await myDb.insert('TemperedGlassKitHoles', {
            'kit_id': kitId,
            'hole_index': 3,
            'diameter_mm': 20.0,
            'ref_x': 'center',
            'offset_x_mm': 0.0,
            'ref_y': 'top',
            'offset_y_mm': 35.0,
            'reference_mode': 'center',
            'min_panel_width_mm': 1200.0,
            'max_panel_width_mm': 0.0,
            'purpose': 'door_top_center',
          });
        } else if (code == 'kit_beta') {
          await myDb.insert('TemperedGlassKitHoles', {
            'kit_id': kitId,
            'hole_index': 1,
            'diameter_mm': 25.0,
            'ref_x': 'left',
            'offset_x_mm': 100.0,
            'ref_y': 'top',
            'offset_y_mm': 40.0,
            'reference_mode': 'edge',
            'min_panel_width_mm': 0.0,
            'max_panel_width_mm': 0.0,
            'purpose': 'door_top_left',
          });
          await myDb.insert('TemperedGlassKitHoles', {
            'kit_id': kitId,
            'hole_index': 2,
            'diameter_mm': 25.0,
            'ref_x': 'right',
            'offset_x_mm': 100.0,
            'ref_y': 'top',
            'offset_y_mm': 40.0,
            'reference_mode': 'edge',
            'min_panel_width_mm': 0.0,
            'max_panel_width_mm': 0.0,
            'purpose': 'door_top_right',
          });
        } else if (code == 'kit_pivot') {
          // Bottom pivot
          await myDb.insert('TemperedGlassKitHoles', {
            'kit_id': kitId,
            'hole_index': 1,
            'diameter_mm': 20.0,
            'ref_x': 'left',
            'offset_x_mm': 60.0,
            'ref_y': 'bottom',
            'offset_y_mm': 60.0,
            'reference_mode': 'center',
            'min_panel_width_mm': 0.0,
            'max_panel_width_mm': 0.0,
            'purpose': 'pivot_bottom',
          });
          // Top pivot
          await myDb.insert('TemperedGlassKitHoles', {
            'kit_id': kitId,
            'hole_index': 2,
            'diameter_mm': 20.0,
            'ref_x': 'left',
            'offset_x_mm': 60.0,
            'ref_y': 'top',
            'offset_y_mm': 60.0,
            'reference_mode': 'center',
            'min_panel_width_mm': 0.0,
            'max_panel_width_mm': 0.0,
            'purpose': 'pivot_top',
          });
        } else if (code == 'kit_charniere_mur' ||
            code == 'kit_charniere_verre') {
          await myDb.insert('TemperedGlassKitHoles', {
            'kit_id': kitId,
            'hole_index': 1,
            'diameter_mm': 16.0,
            'ref_x': 'left',
            'offset_x_mm': 45.0,
            'ref_y': 'top',
            'offset_y_mm': 200.0,
            'reference_mode': 'edge',
            'min_panel_width_mm': 0.0,
            'max_panel_width_mm': 0.0,
            'purpose': 'hinge_top',
          });
          await myDb.insert('TemperedGlassKitHoles', {
            'kit_id': kitId,
            'hole_index': 2,
            'diameter_mm': 16.0,
            'ref_x': 'left',
            'offset_x_mm': 45.0,
            'ref_y': 'bottom',
            'offset_y_mm': 200.0,
            'reference_mode': 'edge',
            'min_panel_width_mm': 0.0,
            'max_panel_width_mm': 0.0,
            'purpose': 'hinge_bottom',
          });
        }
      }
    }

    // Default System Rules seed
    final rulesCount =
        Sqflite.firstIntValue(
          await myDb.rawQuery('SELECT COUNT(*) FROM TemperedGlassSystemRules'),
        ) ??
        0;

    if (rulesCount == 0) {
      // Find Kit Alfa ID and Beta ID
      final kits = await myDb.query('TemperedGlassKits');
      final kitMap = {for (var k in kits) k['code'] as String: k['id'] as int};

      // Find Items
      final items = await myDb.query('TemperedGlassItems');
      final itemsByCategory = <String, List<Map<String, dynamic>>>{};
      for (final item in items) {
        final cat = item['category'] as String? ?? '';
        itemsByCategory.putIfAbsent(cat, () => []).add(item);
      }

      // Link coulissante:
      if (kitMap.containsKey('kit_alfa')) {
        await myDb.insert('TemperedGlassSystemRules', {
          'system_code': 'coulissante',
          'kit_id': kitMap['kit_alfa'],
          'rule_type': 'kit',
          'glass_thickness_mm': 0.0,
          'is_default': 1,
          'is_active': 1,
          'notes': 'Default kit for sliding shower cabin',
        });
      }
      if (kitMap.containsKey('kit_beta')) {
        await myDb.insert('TemperedGlassSystemRules', {
          'system_code': 'coulissante',
          'kit_id': kitMap['kit_beta'],
          'rule_type': 'kit',
          'glass_thickness_mm': 0.0,
          'is_default': 0,
          'is_active': 1,
          'notes': 'Heavy duty kit for sliding shower cabin',
        });
      }

      // Link handles and towel handles to coulissante
      for (final handle in itemsByCategory['poignee'] ?? []) {
        await myDb.insert('TemperedGlassSystemRules', {
          'system_code': 'coulissante',
          'item_id': handle['id'],
          'rule_type': 'handle',
          'glass_thickness_mm': 0.0,
          'is_default': (handle['name'] ?? '').toString().contains('30 سم')
              ? 1
              : 0,
          'is_active': 1,
          'notes': '',
        });
      }

      // Link thickness-dependent profiles
      for (final prof in itemsByCategory['profile'] ?? []) {
        final name = (prof['name'] ?? '').toString();
        double thickness = 0.0;
        if (name.contains('15×15')) {
          thickness = 8.0; // 8mm to 10mm
        } else if (name.contains('20×20')) {
          thickness = 10.0; // 10mm to 12mm
        }
        await myDb.insert('TemperedGlassSystemRules', {
          'system_code': 'coulissante',
          'item_id': prof['id'],
          'rule_type': 'profile',
          'glass_thickness_mm': thickness,
          'is_default': 1,
          'is_active': 1,
          'notes': '',
        });
      }
    }
  }
}
