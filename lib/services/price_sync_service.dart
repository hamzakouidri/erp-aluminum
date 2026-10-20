import 'dart:async';
import 'package:database_data/sql_database.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_sqlcipher/sqflite.dart' show DatabaseExecutor;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:database_data/Commande/Systeme/installation_fees.dart';
import '../settings/app_settings.dart';
import 'app_admin_status_service.dart';
import 'supabase_workshop_sync_service.dart';

class PriceSyncCategory {
  final String key;
  final String titleAr;
  final String titleFr;
  final String tableName;
  final IconData icon;

  const PriceSyncCategory({
    required this.key,
    required this.titleAr,
    required this.titleFr,
    required this.tableName,
    required this.icon,
  });
}

/// One local table that stores prices of a category.
class PriceTableSpec {
  final String table;
  final List<String> keyColumns;
  final List<String> priceColumns;

  /// Catalogue tables: only update existing rows, never create products.
  final bool updateOnly;

  /// Rows of [table] shared with another category: only the rows whose
  /// [keyColumn] starts with one of [prefixes] or equals one of [values]
  /// belong here, or, with [exclude], only those that match none of them.
  final String? keyColumn;
  final List<String> prefixes;
  final List<String> values;
  final bool exclude;

  const PriceTableSpec(
    this.table,
    this.keyColumns,
    this.priceColumns, {
    this.updateOnly = false,
    this.keyColumn,
    this.prefixes = const [],
    this.values = const [],
    this.exclude = false,
  });

  bool get _isFiltered =>
      keyColumn != null && (prefixes.isNotEmpty || values.isNotEmpty);

  /// Whether [row] belongs to this category.
  bool accepts(Map<dynamic, dynamic> row) {
    if (!_isFiltered) return true;
    final value = (row[keyColumn] ?? '').toString();
    final matches =
        prefixes.any(value.startsWith) || values.contains(value);
    return matches != exclude;
  }

  /// SQL filter equivalent to [accepts], or null.
  String? get whereClause {
    if (!_isFiltered) return null;
    final column = keyColumn!;
    final match = [
      for (final _ in prefixes) "$column LIKE ? ESCAPE '!'",
      if (values.isNotEmpty)
        '$column IN (${List.filled(values.length, '?').join(', ')})',
    ].join(' OR ');
    return exclude
        ? '($column IS NULL OR NOT ($match))'
        : '($match)';
  }

  List<Object?> get whereArgs => [
    for (final prefix in prefixes) '${escapeLike(prefix)}%',
    ...values,
  ];

  /// [text] as a literal inside a `LIKE ... ESCAPE '!'` pattern: `_` is a
  /// wildcard otherwise, so "Install_" would also match "Installx".
  static String escapeLike(String text) =>
      text.replaceAllMapped(RegExp(r'[!%_]'), (match) => '!${match[0]}');
}

/// Outcome of applying an administrator publication.
class PriceApplyResult {
  /// Price rows written into the local tables.
  final int updated;

  /// Rows skipped because the workshop set that price itself (manually or
  /// from a purchase) and asked to keep its own prices.
  final int kept;

  const PriceApplyResult({required this.updated, required this.kept});

  PriceApplyResult operator +(PriceApplyResult other) => PriceApplyResult(
    updated: updated + other.updated,
    kept: kept + other.kept,
  );

  static const zero = PriceApplyResult(updated: 0, kept: 0);
}

class PricePublication {
  final int id;
  final String category;
  final int rowCount;
  final String note;
  final DateTime publishedAt;

  const PricePublication({
    required this.id,
    required this.category,
    required this.rowCount,
    required this.note,
    required this.publishedAt,
  });
}

class PriceSyncService {
  PriceSyncService._internal();
  static final PriceSyncService instance = PriceSyncService._internal();

  static const List<PriceSyncCategory> categories = [
    PriceSyncCategory(
      key: 'profiles',
      titleAr: 'أسعار البروفيلات والمقاطع',
      titleFr: 'Prix des profilés et sections',
      tableName: 'SectionColorPrices',
      icon: Icons.view_sidebar_rounded,
    ),
    PriceSyncCategory(
      key: 'series',
      titleAr: 'أسعار بيع السلاسل (سعر المتر الخطي)',
      titleFr: 'Prix de vente des séries (au mètre linéaire)',
      tableName: 'Series',
      icon: Icons.linear_scale_rounded,
    ),
    PriceSyncCategory(
      key: 'accessories',
      titleAr: 'أسعار الإكسسوارات',
      titleFr: 'Prix des accessoires',
      tableName: 'Accessories',
      icon: Icons.construction_rounded,
    ),
    // Each price page is its own category, so accepting one page never
    // changes another (e.g. shutter m² selling prices vs. components).
    PriceSyncCategory(
      key: 'shutters',
      titleAr: 'أسعار مركبات الستائر',
      titleFr: 'Prix des composants de volets',
      tableName: 'ShutterComponents',
      icon: Icons.window_rounded,
    ),
    PriceSyncCategory(
      key: 'shutter_sqm',
      titleAr: 'أسعار بيع المتر المربع للستائر',
      titleFr: 'Prix de vente du m² des volets',
      tableName: 'ShutterSqmPrices',
      icon: Icons.square_foot_rounded,
    ),
    PriceSyncCategory(
      key: 'moustiquaire',
      titleAr: 'أسعار الناموسية (Moustiquaire) للمتر المربع',
      titleFr: 'Prix des moustiquaires au m²',
      tableName: 'ShutterSqmPrices',
      icon: Icons.grid_on_rounded,
    ),
    PriceSyncCategory(
      key: 'installation',
      titleAr: 'أجور التركيب (اليد العاملة)',
      titleFr: 'Prix de pose (main-d’œuvre)',
      tableName: 'ShutterSqmPrices',
      icon: Icons.handyman_rounded,
    ),
    PriceSyncCategory(
      key: 'caisson_tunnel',
      titleAr: 'أسعار صناديق Caisson Tunnel',
      titleFr: 'Prix des caissons tunnel',
      tableName: 'CaissonTunnelPrices',
      icon: Icons.inventory_2_rounded,
    ),
    PriceSyncCategory(
      key: 'joints',
      titleAr: 'أسعار الجوانات (المتر الطولي)',
      titleFr: 'Prix des joints (mètre linéaire)',
      tableName: 'Joints',
      icon: Icons.line_style_rounded,
    ),
    PriceSyncCategory(
      key: 'glass',
      titleAr: 'أسعار الزجاج',
      titleFr: 'Prix du vitrage',
      tableName: 'Glass',
      icon: Icons.crop_square_rounded,
    ),
    PriceSyncCategory(
      key: 'tempered_glass',
      titleAr: 'أسعار إكسسوارات الزجاج المقسّى',
      titleFr: 'Prix des accessoires verre trempé',
      tableName: 'TemperedGlassItems',
      icon: Icons.shield_moon_rounded,
    ),
  ];

  /// The real price storage of every category. Selling prices live in the
  /// per-colour tables (workshop data); the catalogue tables only carry a
  /// base price column. The previous implementation wrote to columns that do
  /// not exist (`Sections.price`, `Glass.price`), which raised
  /// "no such column" on every workshop phone that tried to receive prices.
  static const Map<String, List<PriceTableSpec>> priceTables = {
    'profiles': [
      // Fallback price of a section when it has no colour price.
      PriceTableSpec('Sections', ['id'], ['price_dzd'], updateOnly: true),
      PriceTableSpec('SectionColorPrices', [
        'section_id',
        'color_id',
      ], ['price']),
    ],
    'series': [
      PriceTableSpec('Series', ['id'], ['price_per_meter'], updateOnly: true),
      PriceTableSpec('SeriesColorPrices', ['series_id', 'color_id'], ['price']),
    ],
    'accessories': [
      PriceTableSpec('Accessories', ['id'], ['price'], updateOnly: true),
      PriceTableSpec('AccessoryColorPrices', [
        'accessory_id',
        'color_id',
      ], ['price']),
    ],
    'shutters': [
      PriceTableSpec('ShutterComponents', ['id'], ['price'], updateOnly: true),
      PriceTableSpec('ShutterColorPrices', [
        'shutter_component_id',
        'color_id',
      ], ['price']),
    ],
    // Mosquito-net m² prices (keys "Moustiquaire_*") and installation
    // prices share ShutterSqmPrices but are their own categories: a workshop
    // accepts one without the others.
    'shutter_sqm': [
      PriceTableSpec(
        'ShutterSqmPrices',
        ['blade_type', 'color_id'],
        ['price_per_sqm'],
        keyColumn: 'blade_type',
        prefixes: ['Moustiquaire_', InstallationFees.keyPrefix],
        values: InstallationFees.legacyKeys,
        exclude: true,
      ),
    ],
    'moustiquaire': [
      PriceTableSpec(
        'ShutterSqmPrices',
        ['blade_type', 'color_id'],
        ['price_per_sqm'],
        keyColumn: 'blade_type',
        prefixes: ['Moustiquaire_'],
      ),
    ],
    'installation': [
      PriceTableSpec(
        'ShutterSqmPrices',
        ['blade_type', 'color_id'],
        ['price_per_sqm'],
        keyColumn: 'blade_type',
        prefixes: [InstallationFees.keyPrefix],
        values: InstallationFees.legacyKeys,
      ),
    ],
    'caisson_tunnel': [
      PriceTableSpec('CaissonTunnelPrices', ['color_id'], [
        'profile_price_per_bar',
        'bottom_cover_price_per_bar',
        'price_per_meter',
      ]),
    ],
    'joints': [
      PriceTableSpec('Joints', ['id'], ['price_per_meter'], updateOnly: true),
    ],
    'glass': [
      PriceTableSpec('Glass', ['id'], ['price_per_sqm'], updateOnly: true),
      PriceTableSpec('GlassColorPrices', ['glass_id', 'color_name'], ['price']),
    ],
    'tempered_glass': [
      PriceTableSpec(
        'TemperedGlassItems',
        ['id'],
        ['price', 'cost_price'],
        updateOnly: true,
      ),
    ],
  };

  static const _managerRoles = {'owner', 'manager', 'co_manager', 'admin'};

  bool isCategoryEnabled(AppSettingsProvider settings, String key) {
    switch (key) {
      case 'profiles':
        return settings.syncPriceProfiles;
      case 'series':
        return settings.syncPriceSeries;
      case 'accessories':
        return settings.syncPriceAccessories;
      case 'shutters':
        return settings.syncPriceShutters;
      case 'joints':
        return settings.syncPriceJoints;
      case 'glass':
        return settings.syncPriceGlass;
      default:
        return settings.isExtraPriceSyncEnabled(key);
    }
  }

  Future<void> setCategoryEnabled(
    AppSettingsProvider settings,
    String key,
    bool value,
  ) async {
    switch (key) {
      case 'profiles':
        await settings.setSyncPriceProfiles(value);
        break;
      case 'series':
        await settings.setSyncPriceSeries(value);
        break;
      case 'accessories':
        await settings.setSyncPriceAccessories(value);
        break;
      case 'shutters':
        await settings.setSyncPriceShutters(value);
        break;
      case 'joints':
        await settings.setSyncPriceJoints(value);
        break;
      case 'glass':
        await settings.setSyncPriceGlass(value);
        break;
      default:
        await settings.setExtraPriceSyncEnabled(key, value);
    }
  }

  Future<bool> isCurrentUserAdmin() async {
    return AppAdminStatusService.instance.isCurrentUserAdmin();
  }

  PriceSyncCategory categoryFor(String key) => categories.firstWhere(
    (c) => c.key == key,
    orElse: () => categories.first,
  );

  String categoryTitle(String key, AppLanguage lang) {
    final category = categoryFor(key);
    return lang == AppLanguage.arabic ? category.titleAr : category.titleFr;
  }

  Future<Set<String>> _columns(DatabaseExecutor db, String table) async {
    final rows = await db.rawQuery('PRAGMA table_info("$table")');
    return rows.map((r) => r['name'].toString()).toSet();
  }

  /// يطبق فلتر الحفاظ على الأسعار المحلية إذا كانت المزامنة معطلة لهذا القسم.
  /// Only catalogue base-price columns travel with the global catalogue; the
  /// columns are checked first so a missing column can no longer break the
  /// catalogue download.
  Future<void> preserveLocalPricesIfSyncDisabled(
    Map<String, dynamic> catalogData,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final db = await SqlDatabase().db;
    if (db == null) return;

    for (final entry in priceTables.entries) {
      final enabled = prefs.getBool('sync_price_${entry.key}') ?? true;
      if (enabled) continue;
      for (final spec in entry.value) {
        if (!spec.updateOnly) continue;
        final incoming = catalogData[spec.table];
        if (incoming is! List) continue;
        final columns = await _columns(db, spec.table);
        final priceColumns = spec.priceColumns.where(columns.contains).toList();
        if (priceColumns.isEmpty || !columns.contains('id')) continue;
        final local = await db.query(
          spec.table,
          columns: ['id', ...priceColumns],
        );
        final localById = {for (final r in local) '${r['id']}': r};
        for (final item in incoming) {
          if (item is! Map) continue;
          final localRow = localById['${item['id']}'];
          if (localRow == null) continue;
          for (final column in priceColumns) {
            item[column] = localRow[column] ?? item[column];
          }
        }
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Publishing (application administrator)
  // ---------------------------------------------------------------------------

  Future<Map<String, List<Map<String, dynamic>>>> _readLocalPrices(
    String categoryKey,
  ) async {
    final db = await SqlDatabase().db;
    if (db == null) throw Exception('تعذر فتح قاعدة البيانات المحلية.');
    final result = <String, List<Map<String, dynamic>>>{};
    for (final spec in priceTables[categoryKey] ?? const <PriceTableSpec>[]) {
      final columns = await _columns(db, spec.table);
      if (!spec.keyColumns.every(columns.contains)) continue;
      final priceColumns = spec.priceColumns.where(columns.contains).toList();
      if (priceColumns.isEmpty) continue;
      final rows = await db.query(
        spec.table,
        columns: [...spec.keyColumns, ...priceColumns],
        where: spec.whereClause,
        whereArgs: spec.whereClause == null ? null : spec.whereArgs,
      );
      result[spec.table] = rows
          .map((r) => Map<String, dynamic>.from(r))
          .toList(growable: false);
    }
    return result;
  }

  /// Publishes the administrator's current prices of [categoryKey] and
  /// notifies every workshop manager. Returns the number of price rows.
  Future<int> publishCategoryPrices(
    String categoryKey, {
    String note = '',
  }) async {
    final client = Supabase.instance.client;
    final user = client.auth.currentUser;
    if (user == null) {
      throw Exception('يجب تسجيل الدخول لنشر الأسعار.');
    }
    if (!await isCurrentUserAdmin()) {
      throw Exception('نشر الأسعار متاح لمدير التطبيق فقط.');
    }
    final payload = await _readLocalPrices(categoryKey);
    final rowCount = payload.values.fold<int>(
      0,
      (sum, rows) => sum + rows.length,
    );
    if (rowCount == 0) {
      throw Exception('لا توجد أسعار محلية في هذا القسم لنشرها.');
    }
    final inserted = await _withPublicationTables(
      () => client
          .from('shared_price_publications')
          .insert({
            'category': categoryKey,
            'payload': payload,
            'row_count': rowCount,
            'note': note,
            'published_by': user.id,
          })
          .select('id')
          .single(),
    );
    final publicationId = inserted['id']?.toString() ?? '';

    final category = categoryFor(categoryKey);
    try {
      await client.functions.invoke(
        'send-worker-assignment',
        body: {
          'audience': 'all_managers',
          'event_type': 'price_publication',
          'preference_type': 'prices',
          'title': 'أسعار جديدة متوفرة',
          'body':
              'نشر مدير التطبيق تحديثاً في: ${category.titleAr}. '
              'افتح التطبيق لقبوله أو تجاهله.',
          'data': {'category': categoryKey, 'publication_id': publicationId},
        },
      );
    } catch (error) {
      // The publication is stored; managers still see it when they open the
      // application, so a push failure must not undo the publication.
      debugPrint('Price publication push skipped: $error');
    }
    return rowCount;
  }

  // ---------------------------------------------------------------------------
  // Receiving (workshop managers)
  // ---------------------------------------------------------------------------

  Future<String> _currentWorkshopId() async {
    final live = SupabaseWorkshopSyncService().currentWorkshopUuid;
    if (live.isNotEmpty) return live;
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getString('selected_supabase_workshop_id') ?? '').trim();
  }

  Future<bool> isCurrentUserWorkshopManager() async {
    final prefs = await SharedPreferences.getInstance();
    final role = (prefs.getString('user_role') ?? '').trim().toLowerCase();
    return _managerRoles.contains(role);
  }

  /// Newest undecided publication per category for this workshop, limited to
  /// the categories accepted in the price-sync settings. Workers and the
  /// application administrator never get a prompt.
  Future<List<PricePublication>> fetchPendingPublications() async {
    final client = Supabase.instance.client;
    if (client.auth.currentUser == null) return const [];
    if (await isCurrentUserAdmin()) return const [];
    if (!await isCurrentUserWorkshopManager()) return const [];
    final workshopId = await _currentWorkshopId();
    if (workshopId.isEmpty) return const [];

    final publications = await client
        .from('shared_price_publications')
        .select('id,category,row_count,note,published_at')
        .order('published_at', ascending: false)
        .limit(60);
    final decisions = await client
        .from('price_publication_decisions')
        .select('publication_id')
        .eq('workshop_id', workshopId);
    final decided = {
      for (final row in decisions) row['publication_id'].toString(),
    };
    final prefs = await SharedPreferences.getInstance();

    final result = <PricePublication>[];
    final seenCategories = <String>{};
    for (final row in publications) {
      final category = row['category']?.toString() ?? '';
      // Only the newest publication of a category matters; once it has been
      // decided, older ones are obsolete as well.
      if (category.isEmpty || !seenCategories.add(category)) continue;
      if (decided.contains(row['id'].toString())) continue;
      if (!(prefs.getBool('sync_price_$category') ?? true)) continue;
      result.add(
        PricePublication(
          id: (row['id'] as num).toInt(),
          category: category,
          rowCount: (row['row_count'] as num?)?.toInt() ?? 0,
          note: row['note']?.toString() ?? '',
          publishedAt:
              DateTime.tryParse(row['published_at']?.toString() ?? '') ??
              DateTime.now(),
        ),
      );
    }
    return result;
  }

  Future<void> _recordDecision(int publicationId, String status) async {
    final client = Supabase.instance.client;
    final workshopId = await _currentWorkshopId();
    if (workshopId.isEmpty) return;
    await client.from('price_publication_decisions').upsert({
      'workshop_id': workshopId,
      'publication_id': publicationId,
      'status': status,
      'decided_by': client.auth.currentUser?.id,
      'decided_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  Future<void> dismissPublication(int publicationId) =>
      _recordDecision(publicationId, 'dismissed');

  /// Writes the publication into the local price tables. The local change
  /// triggers then upload it to the workshop, so every worker receives it.
  ///
  /// With [keepWorkshopPrices], prices the workshop set itself (typed by the
  /// manager or derived from a purchase) are left untouched. Accepted
  /// catalogue base prices are stored as workshop prices, so they reach every
  /// phone of the workshop and survive the next catalogue refresh.
  Future<PriceApplyResult> applyPublication(
    int publicationId, {
    bool keepWorkshopPrices = true,
  }) async {
    final client = Supabase.instance.client;
    final row = await client
        .from('shared_price_publications')
        .select('category,payload')
        .eq('id', publicationId)
        .single();
    final category = row['category']?.toString() ?? '';
    final payload = row['payload'];
    if (payload is! Map) {
      throw Exception('بيانات الأسعار المنشورة غير صالحة.');
    }
    final result = await applyPricePayload(
      category,
      payload,
      keepWorkshopPrices: keepWorkshopPrices,
    );
    try {
      await _recordDecision(publicationId, 'applied');
    } catch (error) {
      // The prices are already written locally; a failed decision record
      // only means the prompt may be shown again (applying is idempotent).
      debugPrint('Price publication decision not recorded: $error');
    }
    SupabaseWorkshopSyncService().notifyLocalChange(immediate: true);
    return result;
  }

  /// Applies a published price [payload] of [category] to the local tables.
  ///
  /// Rows are updated in place and only inserted when missing (no
  /// `ON CONFLICT`): older databases may lack the unique constraint on the
  /// colour-price tables, and an upsert then fails for the whole category.
  @visibleForTesting
  Future<PriceApplyResult> applyPricePayload(
    String category,
    Map<dynamic, dynamic> payload, {
    bool keepWorkshopPrices = true,
  }) async {
    final sqlDb = SqlDatabase();
    final db = await sqlDb.db;
    if (db == null) throw Exception('تعذر فتح قاعدة البيانات المحلية.');

    var updated = 0;
    var kept = 0;
    await db.transaction((txn) async {
      final ownPrices = keepWorkshopPrices
          ? await sqlDb.readOwnWorkshopPriceKeys(txn)
          : const <String>{};
      for (final spec in priceTables[category] ?? const <PriceTableSpec>[]) {
        final rows = payload[spec.table];
        if (rows is! List) continue;
        final columns = await _columns(txn, spec.table);
        if (!spec.keyColumns.every(columns.contains)) continue;
        final priceColumns = spec.priceColumns.where(columns.contains).toList();
        if (priceColumns.isEmpty) continue;
        final hasId = columns.contains('id') && !spec.keyColumns.contains('id');
        final keyWhere = spec.keyColumns.map((k) => '$k = ?').join(' AND ');
        for (final raw in rows) {
          if (raw is! Map) continue;
          if (!spec.accepts(raw)) continue;
          final keys = [for (final k in spec.keyColumns) raw[k]];
          if (keys.any((k) => k == null)) continue;
          final rowKey = SqlDatabase.priceRowKey(keys);
          if (ownPrices.contains('${spec.table}\x1f$rowKey')) {
            kept++;
            continue;
          }
          final prices = <String, Object?>{
            for (final c in priceColumns) c: _toDouble(raw[c]),
          };
          var written = await txn.update(
            spec.table,
            prices,
            where: keyWhere,
            whereArgs: keys,
          );
          if (written == 0 && !spec.updateOnly) {
            // New rows get a distributed id: a small local id could collide
            // with another phone's row once the workshop sync merges them.
            await txn.insert(spec.table, {
              if (hasId) 'id': sqlDb.createDistributedId(),
              for (var i = 0; i < spec.keyColumns.length; i++)
                spec.keyColumns[i]: keys[i],
              ...prices,
            });
            written = 1;
          }
          if (written == 0) continue;
          updated++;
          for (final column in priceColumns) {
            await sqlDb.recordWorkshopPrice(
              txn,
              table: spec.table,
              rowKey: rowKey,
              column: column,
              price: prices[column] as double,
              source: 'publication',
            );
          }
        }
      }
    });
    return PriceApplyResult(updated: updated, kept: kept);
  }

  /// The price-sharing tables are created by
  /// `supabase/shared_price_publications.sql`. Until that file is run in the
  /// Supabase SQL editor every request fails with PGRST205; say so plainly
  /// instead of showing the raw server error.
  static Future<T> _withPublicationTables<T>(Future<T> Function() request) async {
    try {
      return await request();
    } on PostgrestException catch (error) {
      if (error.code == 'PGRST205' || error.code == '42P01') {
        throw Exception(
          'جداول مشاركة الأسعار غير موجودة في Supabase بعد. '
          'يجب تشغيل الملف supabase/shared_price_publications.sql مرة واحدة '
          'في محرر SQL الخاص بـ Supabase.',
        );
      }
      rethrow;
    }
  }

  static double _toDouble(Object? value) => value is num
      ? value.toDouble()
      : double.tryParse(value?.toString() ?? '') ?? 0.0;

  /// Applies the newest publication of a category ("refresh now" button).
  Future<PriceApplyResult> syncCategoryPricesFromCloud(
    String categoryKey, {
    bool keepWorkshopPrices = true,
  }) async {
    final client = Supabase.instance.client;
    if (client.auth.currentUser == null) {
      throw Exception('يجب تسجيل الدخول لمزامنة الأسعار من السحابة.');
    }
    if (!await isCurrentUserWorkshopManager()) {
      // Workers receive the prices through the workshop sync once their
      // manager accepts them.
      throw Exception('تحديث الأسعار من مدير التطبيق متاح لمدير الورشة فقط.');
    }
    final latest = await _withPublicationTables(
      () => client
          .from('shared_price_publications')
          .select('id')
          .eq('category', categoryKey)
          .order('published_at', ascending: false)
          .limit(1)
          .maybeSingle(),
    );
    if (latest == null) {
      throw Exception('لم ينشر مدير التطبيق أسعاراً لهذا القسم بعد.');
    }
    return applyPublication(
      (latest['id'] as num).toInt(),
      keepWorkshopPrices: keepWorkshopPrices,
    );
  }
}
