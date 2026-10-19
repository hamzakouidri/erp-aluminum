part of '../sql_database.dart';

/// Parses the `member_ids` column of ProfileCompatibilityGroups.
Set<int> parseProfileGroupMembers(Object? value) => (value?.toString() ?? '')
    .split(',')
    .map((part) => int.tryParse(part.trim()))
    .whereType<int>()
    .toSet();

/// Catalogue: profiles, series, sections, colours, accessories, joints, glass, shutters, kits and series design rules.
extension SqlDatabaseCatalog on SqlDatabase {
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
      'SELECT * FROM Profile WHERE is_active = 1 OR is_active IS NULL ORDER BY name ASC',
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
    if (myDb == null) return 0;
    var res = await myDb.update(
      'Profile',
      {'is_active': 0},
      where: 'id = ?',
      whereArgs: [id],
    );
    // Cascade archive to child series and sections
    try {
      final seriesList = await myDb.query(
        'Series',
        columns: ['id'],
        where: 'profile_id = ?',
        whereArgs: [id],
      );
      for (final s in seriesList) {
        final sId = s['id'] as int?;
        if (sId != null) {
          await myDb.update(
            'Sections',
            {'is_active': 0},
            where: 'series_id = ?',
            whereArgs: [sId],
          );
        }
      }
      await myDb.update(
        'Series',
        {'is_active': 0},
        where: 'profile_id = ?',
        whereArgs: [id],
      );
    } catch (e) {
      debugPrint('Error cascading profile deactivation: $e');
    }
    try {
      CloudSyncService().notifyChange();
    } catch (_) {}
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
      where: 'profile_id = ? AND (is_active = 1 OR is_active IS NULL)',
      whereArgs: [profileId],
    );
  }

  Future<int> insertSeries(
    int profileId,
    String name,
    String type, {
    double pricePerMeter = 0.0,
    int hasThreePieceSash = 0,
    String? reinforcementType,
  }) async {
    Database? myDb = await db;
    var res = await myDb!.insert('Series', {
      'profile_id': profileId,
      'name': name,
      'type': type,
      'price_per_meter': pricePerMeter,
      'has_three_piece_sash': hasThreePieceSash,
      if (reinforcementType != null) 'reinforcement_type': reinforcementType,
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

  Future<List<Map<String, dynamic>>> getProfileCalculationRules() async {
    final myDb = await db;
    if (myDb == null) return [];
    await _ensureProfileCalculationRulesTable(myDb);
    return myDb.query('ProfileCalculationRules');
  }

  Future<void> saveProfileCalculationRule({
    required int sectionId,
    required String calculationMode,
    required double linearMeterMultiplier,
    bool excludeFromPricing = false,
  }) async {
    final myDb = await db;
    if (myDb == null) return;
    await _ensureProfileCalculationRulesTable(myDb);
    final mode =
        const {'auto', 'linear_meter', 'base_price'}.contains(calculationMode)
        ? calculationMode
        : 'auto';
    final multiplier =
        linearMeterMultiplier.isFinite && linearMeterMultiplier > 0
        ? linearMeterMultiplier
        : 1.0;
    await myDb.insert('ProfileCalculationRules', {
      'section_id': sectionId,
      'calculation_mode': mode,
      'linear_meter_multiplier': multiplier,
      'exclude_from_pricing': excludeFromPricing ? 1 : 0,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    await CloudSyncService().notifyCatalogChange(uploadImmediately: true);
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
    await recordWorkshopPrice(
      myDb,
      table: 'SeriesColorPrices',
      rowKey: SqlDatabase.priceRowKey([seriesId, colorId]),
      column: 'price',
      price: price,
      source: 'manual',
    );
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
    await recordWorkshopPrice(
      myDb,
      table: 'SectionColorPrices',
      rowKey: SqlDatabase.priceRowKey([sectionId, colorId]),
      column: 'price',
      price: price,
      source: 'manual',
    );
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
    await recordWorkshopPrice(
      myDb,
      table: 'AccessoryColorPrices',
      rowKey: SqlDatabase.priceRowKey([accessoryId, colorId]),
      column: 'price',
      price: price,
      source: 'manual',
    );
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
    String? reinforcementType,
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
        if (reinforcementType != null) 'reinforcement_type': reinforcementType,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    CloudSyncService().notifyChange();
    return res;
  }

  Future<int> deleteSeries(int id) async {
    Database? myDb = await db;
    if (myDb == null) return 0;
    var res = await myDb.update(
      'Series',
      {'is_active': 0},
      where: 'id = ?',
      whereArgs: [id],
    );
    // Cascade archive to child sections
    try {
      await myDb.update(
        'Sections',
        {'is_active': 0},
        where: 'series_id = ?',
        whereArgs: [id],
      );
    } catch (e) {
      debugPrint('Error cascading series deactivation: $e');
    }
    try {
      CloudSyncService().notifyChange();
    } catch (_) {}
    return res;
  }

  /// Returns local sections plus sections explicitly shared with this series.
  /// A shared section is never promoted to every series in the same profile
  /// system: sharing is a directed source-section -> target-series relation.
  Future<List<Map<String, dynamic>>> readAvailableSectionsBySeries(
    int seriesId, {
    String? roleKey,
    String? usageScope,
  }) async {
    final myDb = await db;
    if (myDb == null) return [];
    await _ensureSectionSharingSchema(myDb);

    final where = StringBuffer('''
      (s.is_active = 1 OR s.is_active IS NULL)
      AND (ownerSer.is_active = 1 OR ownerSer.is_active IS NULL)
      AND (ownerProfile.is_active = 1 OR ownerProfile.is_active IS NULL)
      AND r.is_active = 1
      AND r.target_scope = 'series'
      AND r.target_id = ?
    ''');
    final args = <Object?>[seriesId];
    final normalizedRole = roleKey?.trim();
    if (normalizedRole != null && normalizedRole.isNotEmpty) {
      where.write(' AND r.role_key = ?');
      args.add(normalizedRole);
    }
    final normalizedScope = usageScope?.trim().toLowerCase();
    if (normalizedScope != null && normalizedScope.isNotEmpty) {
      where.write(" AND r.usage_scope IN ('global', 'both', ?)");
      args.add(normalizedScope);
    }

    final local = await readSectionsBySeries(seriesId);
    final shared = await myDb.rawQuery('''
      SELECT s.*, 1 AS is_shared, r.id AS sharing_rule_id,
             r.role_key AS sharing_role_key,
             r.usage_scope AS sharing_usage_scope,
             r.target_scope AS sharing_target_scope,
             r.target_id AS sharing_target_id,
             ownerSer.id AS source_series_id,
             ownerSer.profile_id AS source_profile_id,
             ownerSer.name AS source_series_name,
             ownerProfile.name AS source_profile_name
      FROM SectionSharingRules r
      JOIN Sections s ON s.id = r.source_section_id
      JOIN Series ownerSer ON ownerSer.id = s.series_id
      JOIN Profile ownerProfile ON ownerProfile.id = ownerSer.profile_id
      WHERE ${where.toString()}
      ORDER BY r.is_default DESC, r.sort_order ASC, r.id ASC
      ''', args);

    final result = <Map<String, dynamic>>[...local];
    final seen = local
        .map((row) => (row['id'] as num?)?.toInt())
        .whereType<int>()
        .toSet();
    for (final row in shared) {
      final id = (row['id'] as num?)?.toInt();
      if (id == null || seen.add(id))
        result.add(Map<String, dynamic>.from(row));
    }
    return result;
  }

  Future<List<Map<String, dynamic>>> readSectionSharingRules({
    int? sourceSectionId,
    String? targetScope,
    int? targetId,
    String? roleKey,
  }) async {
    final myDb = await db;
    if (myDb == null) return [];
    await _ensureSectionSharingSchema(myDb);
    final conditions = <String>['r.is_active = 1'];
    final args = <Object?>[];
    if (sourceSectionId != null) {
      conditions.add('r.source_section_id = ?');
      args.add(sourceSectionId);
    }
    if (targetScope != null && targetScope.trim().isNotEmpty) {
      conditions.add('r.target_scope = ?');
      args.add(targetScope.trim().toLowerCase());
    }
    if (targetId != null) {
      conditions.add('r.target_id = ?');
      args.add(targetId);
    }
    if (roleKey != null && roleKey.trim().isNotEmpty) {
      conditions.add('r.role_key = ?');
      args.add(roleKey.trim());
    }
    return myDb.rawQuery('''
      SELECT r.*, s.code AS source_section_code,
             s.name AS source_section_name,
             ser.name AS source_series_name,
             p.name AS source_profile_name
      FROM SectionSharingRules r
      JOIN Sections s ON s.id = r.source_section_id
      JOIN Series ser ON ser.id = s.series_id
      JOIN Profile p ON p.id = ser.profile_id
      WHERE ${conditions.join(' AND ')}
      ORDER BY r.target_scope ASC, r.target_id ASC,
               r.role_key ASC, r.sort_order ASC, r.id ASC
      ''', args);
  }

  Future<int> saveSectionSharingRule({
    required int sourceSectionId,
    required String targetScope,
    required int targetId,
    required String roleKey,
    String usageScope = 'global',
    bool isDefault = false,
    int sortOrder = 0,
  }) async {
    final myDb = await db;
    if (myDb == null) return 0;
    await _ensureSectionSharingSchema(myDb);
    final normalizedTarget = targetScope.trim().toLowerCase();
    if (normalizedTarget != 'series') {
      throw ArgumentError(
        'Sections can only be shared with one explicit target series',
      );
    }
    final normalizedRole = roleKey.trim();
    if (normalizedRole.isEmpty) throw ArgumentError('roleKey is required');
    final normalizedUsage = usageScope.trim().toLowerCase();
    final now = DateTime.now().toUtc().toIso8601String();
    await myDb.rawInsert(
      '''
      INSERT INTO SectionSharingRules
        (source_section_id, target_scope, target_id, role_key, usage_scope,
         is_default, is_active, sort_order, updated_at)
      VALUES (?, ?, ?, ?, ?, ?, 1, ?, ?)
      ON CONFLICT(source_section_id, target_scope, target_id, role_key, usage_scope)
      DO UPDATE SET is_default = excluded.is_default,
                    is_active = 1,
                    sort_order = excluded.sort_order,
                    updated_at = excluded.updated_at
      ''',
      [
        sourceSectionId,
        normalizedTarget,
        targetId,
        normalizedRole,
        normalizedUsage.isEmpty ? 'global' : normalizedUsage,
        isDefault ? 1 : 0,
        sortOrder,
        now,
      ],
    );
    // The local rule is immediately available. Upload it in the background so
    // a slow connection does not delay the success feedback in the series UI.
    unawaited(() async {
      try {
    await CloudSyncService().notifyCatalogChange(uploadImmediately: true);
      } catch (error) {
        debugPrint('Deferred section-sharing sync failed: $error');
      }
    }());
    final rows = await myDb.rawQuery(
      '''
      SELECT id FROM SectionSharingRules
      WHERE source_section_id = ? AND target_scope = ? AND target_id = ?
        AND role_key = ? AND usage_scope = ?
      LIMIT 1
      ''',
      [
        sourceSectionId,
        normalizedTarget,
        targetId,
        normalizedRole,
        normalizedUsage.isEmpty ? 'global' : normalizedUsage,
      ],
    );
    return (rows.first['id'] as num?)?.toInt() ?? 0;
  }

  Future<void> deleteSectionSharingRule(int id) async {
    final myDb = await db;
    if (myDb == null) return;
    await _ensureSectionSharingSchema(myDb);
    await myDb.update(
      'SectionSharingRules',
      {'is_active': 0, 'updated_at': DateTime.now().toUtc().toIso8601String()},
      where: 'id = ?',
      whereArgs: [id],
    );
    await CloudSyncService().notifyCatalogChange(uploadImmediately: true);
  }

  Future<List<Map<String, dynamic>>> readFrameJoinRules() async {
    final myDb = await db;
    if (myDb == null) return [];
    await _ensureSeriesDesignTables(myDb);
    return myDb.rawQuery('''
      SELECT r.id, r.section_a_id, r.section_b_id, r.is_active, r.updated_at,
             sA.id AS a_id, sA.code AS a_code, sA.name AS a_name,
             sA.thickness AS a_thickness, sA.visible_width AS a_visible_width,
             serA.id AS a_series_id, serA.name AS a_series_name,
             pA.name AS a_profile_name,
             sB.id AS b_id, sB.code AS b_code, sB.name AS b_name,
             sB.thickness AS b_thickness, sB.visible_width AS b_visible_width,
             serB.id AS b_series_id, serB.name AS b_series_name,
             pB.name AS b_profile_name
      FROM FrameJoinRules r
      JOIN Sections sA ON sA.id = r.section_a_id
      JOIN Series serA ON serA.id = sA.series_id
      JOIN Profile pA ON pA.id = serA.profile_id
      JOIN Sections sB ON sB.id = r.section_b_id
      JOIN Series serB ON serB.id = sB.series_id
      JOIN Profile pB ON pB.id = serB.profile_id
      WHERE r.is_active = 1
      ORDER BY pA.name ASC, serA.name ASC, sA.name ASC
    ''');
  }

  /// Returns the other frames of [sectionId]'s compatibility group: every
  /// frame linked to it, directly or through other linked frames (1 ↔ 2 and
  /// 2 ↔ 3 put 1, 2 and 3 in one group), and, with [includeGroups], every
  /// profile of its compatibility groups.
  Future<Set<int>> readFrameJoinPartnerIds(
    int sectionId, {
    bool includeGroups = true,
  }) async {
    final myDb = await db;
    if (myDb == null) return {};
    await _ensureSeriesDesignTables(myDb);
    final rows = await myDb.rawQuery(
      'SELECT section_a_id, section_b_id FROM FrameJoinRules WHERE is_active = 1',
    );
    final links = <int, Set<int>>{};
    for (final row in rows) {
      final a = (row['section_a_id'] as num?)?.toInt();
      final b = (row['section_b_id'] as num?)?.toInt();
      if (a == null || b == null || a == b) continue;
      links.putIfAbsent(a, () => {}).add(b);
      links.putIfAbsent(b, () => {}).add(a);
    }
    final group = <int>{sectionId};
    final pending = [sectionId];
    while (pending.isNotEmpty) {
      for (final next in links[pending.removeLast()] ?? const <int>{}) {
        if (group.add(next)) pending.add(next);
      }
    }
    if (includeGroups) {
      group.addAll(await readProfileCompatibilityPartnerIds(sectionId));
    }
    return group..remove(sectionId);
  }

  /// The workshop's shutter calculation values, by rule key.
  Future<Map<String, double>> readShutterCalcRules() async {
    final myDb = await db;
    if (myDb == null) return {};
    await _ensureSeriesDesignTables(myDb);
    final rows = await myDb.query('ShutterCalcRules');
    return {
      for (final row in rows)
        if (row['rule_key'] != null && row['value'] is num)
          row['rule_key'].toString(): (row['value'] as num).toDouble(),
    };
  }

  Future<void> saveShutterCalcRules(Map<String, double> values) async {
    final myDb = await db;
    if (myDb == null) return;
    await _ensureSeriesDesignTables(myDb);
    final now = DateTime.now().toUtc().toIso8601String();
    for (final entry in values.entries) {
      await myDb.rawInsert(
        '''
        INSERT INTO ShutterCalcRules (rule_key, value, updated_at)
        VALUES (?, ?, ?)
        ON CONFLICT(rule_key)
        DO UPDATE SET value = excluded.value, updated_at = excluded.updated_at
      ''',
        [entry.key, entry.value, now],
      );
    }
    await CloudSyncService().notifyCatalogChange(uploadImmediately: true);
  }

  /// The compatibility groups defined for [seriesId], each with its
  /// `members` (Sections ids) parsed.
  Future<List<Map<String, dynamic>>> readProfileCompatibilityGroups(
    int seriesId,
  ) async {
    final myDb = await db;
    if (myDb == null) return [];
    await _ensureSeriesDesignTables(myDb);
    final rows = await myDb.query(
      'ProfileCompatibilityGroups',
      where: 'series_id = ? AND is_active = 1',
      whereArgs: [seriesId],
      orderBy: 'id ASC',
    );
    return [
      for (final row in rows)
        {...row, 'members': parseProfileGroupMembers(row['member_ids'])},
    ];
  }

  /// Every profile sharing a compatibility group with [sectionId], whatever
  /// series the group was defined in.
  Future<Set<int>> readProfileCompatibilityPartnerIds(int sectionId) async {
    final myDb = await db;
    if (myDb == null) return {};
    await _ensureSeriesDesignTables(myDb);
    final rows = await myDb.query(
      'ProfileCompatibilityGroups',
      columns: ['member_ids'],
      where: 'is_active = 1',
    );
    final result = <int>{};
    for (final row in rows) {
      final members = parseProfileGroupMembers(row['member_ids']);
      if (members.contains(sectionId)) result.addAll(members);
    }
    return result..remove(sectionId);
  }

  /// Creates the group when [id] is null, else replaces its name and
  /// members. Returns the group id.
  Future<int> saveProfileCompatibilityGroup({
    int? id,
    required int seriesId,
    required String name,
    required Iterable<int> memberIds,
  }) async {
    final myDb = await db;
    if (myDb == null) return 0;
    await _ensureSeriesDesignTables(myDb);
    final values = {
      'series_id': seriesId,
      'name': name.trim(),
      'member_ids': memberIds.toSet().join(','),
      'is_active': 1,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
    final savedId = id == null
        ? await myDb.insert('ProfileCompatibilityGroups', values)
        : await myDb
              .update(
                'ProfileCompatibilityGroups',
                values,
                where: 'id = ?',
                whereArgs: [id],
              )
              .then((_) => id);
    await CloudSyncService().notifyCatalogChange(uploadImmediately: true);
    return savedId;
  }

  Future<void> deleteProfileCompatibilityGroup(int id) async {
    final myDb = await db;
    if (myDb == null) return;
    await _ensureSeriesDesignTables(myDb);
    await myDb.update(
      'ProfileCompatibilityGroups',
      {'is_active': 0, 'updated_at': DateTime.now().toUtc().toIso8601String()},
      where: 'id = ?',
      whereArgs: [id],
    );
    await CloudSyncService().notifyCatalogChange(uploadImmediately: true);
  }

  /// Takes [sectionId] out of its compatibility group: drops its links to
  /// every frame of [group].
  Future<void> removeFrameFromJoinGroup(int sectionId, Set<int> group) async {
    final myDb = await db;
    if (myDb == null) return;
    await _ensureSeriesDesignTables(myDb);
    final now = DateTime.now().toUtc().toIso8601String();
    for (final other in group) {
      if (other == sectionId) continue;
      final lo = sectionId < other ? sectionId : other;
      final hi = sectionId < other ? other : sectionId;
      await myDb.update(
        'FrameJoinRules',
        {'is_active': 0, 'updated_at': now},
        where: 'section_a_id = ? AND section_b_id = ?',
        whereArgs: [lo, hi],
      );
    }
    await CloudSyncService().notifyCatalogChange(uploadImmediately: true);
  }

  Future<int> saveFrameJoinRule(int sectionAId, int sectionBId) async {
    final myDb = await db;
    if (myDb == null) return 0;
    await _ensureSeriesDesignTables(myDb);
    final lo = sectionAId < sectionBId ? sectionAId : sectionBId;
    final hi = sectionAId < sectionBId ? sectionBId : sectionAId;
    final now = DateTime.now().toUtc().toIso8601String();
    await myDb.rawInsert(
      '''
      INSERT INTO FrameJoinRules (section_a_id, section_b_id, is_active, updated_at)
      VALUES (?, ?, 1, ?)
      ON CONFLICT(section_a_id, section_b_id)
      DO UPDATE SET is_active = 1, updated_at = excluded.updated_at
    ''',
      [lo, hi, now],
    );
    await CloudSyncService().notifyCatalogChange(uploadImmediately: true);
    final rows = await myDb.rawQuery(
      'SELECT id FROM FrameJoinRules WHERE section_a_id = ? AND section_b_id = ? LIMIT 1',
      [lo, hi],
    );
    return (rows.firstOrNull?['id'] as num?)?.toInt() ?? 0;
  }

  Future<void> deleteFrameJoinRule(int id) async {
    final myDb = await db;
    if (myDb == null) return;
    await _ensureSeriesDesignTables(myDb);
    await myDb.update(
      'FrameJoinRules',
      {'is_active': 0, 'updated_at': DateTime.now().toUtc().toIso8601String()},
      where: 'id = ?',
      whereArgs: [id],
    );
    await CloudSyncService().notifyCatalogChange(uploadImmediately: true);
  }

  Future<void> deleteFrameJoinRuleBetween(
    int sectionAId,
    int sectionBId,
  ) async {
    final myDb = await db;
    if (myDb == null) return;
    await _ensureSeriesDesignTables(myDb);
    final lo = sectionAId < sectionBId ? sectionAId : sectionBId;
    final hi = sectionAId < sectionBId ? sectionBId : sectionAId;
    final now = DateTime.now().toUtc().toIso8601String();
    await myDb.update(
      'FrameJoinRules',
      {'is_active': 0, 'updated_at': now},
      where: 'section_a_id = ? AND section_b_id = ?',
      whereArgs: [lo, hi],
    );
    await CloudSyncService().notifyCatalogChange(uploadImmediately: true);
  }

  Future<List<Map<String, dynamic>>> searchSectionsWithProfile(
    String query,
  ) async {
    final dbClient = await db;
    String q = query.toLowerCase();

    return await dbClient!.rawQuery(
      '''
      SELECT s.*, p.name as profile_name,
             ser.name as series_name, ser.profile_id as source_profile_id,
             ser.id as source_series_id
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
    var res = await myDb.insert('Sections', {
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
    var res = await myDb.update(
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
    if (myDb == null) return 0;
    var res = await myDb.update(
      'Sections',
      {'is_active': 0},
      where: 'id = ?',
      whereArgs: [id],
    );
    try {
      CloudSyncService().notifyChange();
    } catch (_) {}
    return res;
  }

  int _positiveInt(Object? value) {
    if (value is num) {
      final number = value.toInt();
      return number > 0 ? number : 0;
    }
    final parsed = int.tryParse(value?.toString().trim() ?? '') ?? 0;
    return parsed > 0 ? parsed : 0;
  }

  /// تعطيل سجل زجاج محلياً فقط (is_active=0) — يُستخدم بعد restore
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

  Future<List<Map<String, dynamic>>> readColors() async {
    Database? myDb = await db;
    await _repairKnownColorRows(myDb!);
    return myDb.query(
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
        {'name': 'Faux Bois Marron', 'hex_code': '#A9774E', 'type': 'Global'},
      ];
      for (var c in defaults) {
        await myDb.insert('Colors', c);
      }
    } finally {
      _isInsertingColors = false;
    }
  }

  Future<int> insertColor(
    String name,
    String hexCode,
    String type, {
    double price = 0.0,
    bool notifySync = true,
  }) async {
    Database? myDb = await db;
    final repairedName = SqlDatabase._canonicalLegacyColorName(name);
    final repairedHex = SqlDatabase._canonicalKnownColorHex(repairedName, hexCode);
    var res = await myDb!.insert('Colors', {
      'name': repairedName,
      'hex_code': repairedHex,
      'type': type,
      'price': price,
    });
    if (notifySync) CloudSyncService().notifyCatalogChange();
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
    final repairedName = SqlDatabase._canonicalLegacyColorName(name);
    final repairedHex = SqlDatabase._canonicalKnownColorHex(repairedName, hexCode);
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
    var res = await myDb.query(
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
          'id': SqlDatabase._profileColorSyncId(profileId, colorId),
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
    Iterable<int> colorIds, {
    bool notifySync = true,
  }) async {
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
          'id': SqlDatabase._profileColorSyncId(profileId, colorId),
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
    if (notifySync) CloudSyncService().notifyCatalogChange();
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
          'id': SqlDatabase._profileColorSyncId(profileId, colorId),
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

        final legacyPrice = SqlDatabase._readStoredNumber(component['price']) ?? 0.0;
        final greyRows = await txn.query(
          'ShutterColorPrices',
          columns: const ['price'],
          where: 'shutter_component_id = ? AND color_id = ?',
          whereArgs: [componentId, defaultColorId],
          limit: 1,
        );
        final greyPrice = greyRows.isEmpty
            ? legacyPrice
            : (SqlDatabase._readStoredNumber(greyRows.first['price']) ?? 0.0);

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
          : SqlDatabase._readStoredNumber(stored.first['price']);
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
    return myDb.rawQuery(
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
  Future<List<Map<String, dynamic>>> readAccessories({
    bool includeInactive = false,
  }) async {
    Database? myDb = await db;
    if (myDb != null) {
      await _ensureAccessoryRulesColumns(myDb);
      await _ensureAccessoryLinksSchema(myDb);
      try {
        await myDb.execute(
          "ALTER TABLE Accessories ADD COLUMN is_active INTEGER NOT NULL DEFAULT 1;",
        );
      } catch (_) {}
      try {
        await myDb.execute(
          "UPDATE Accessories SET is_active = 1 WHERE is_active IS NULL;",
        );
      } catch (_) {}
    }
    try {
      return await myDb!.query(
        'Accessories',
        where: includeInactive ? null : 'is_active = 1 OR is_active IS NULL',
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
    if (myDb != null) {
      await _ensureAccessoryRulesColumns(myDb);
    }
    if (!data.containsKey('screw_count')) data['screw_count'] = 0;
    var res = await myDb!.insert('Accessories', data);
    CloudSyncService().notifyCatalogChange();
    return res;
  }

  Future<int> updateAccessory(
    int id,
    Map<String, dynamic> data, {
    bool notifySync = true,
  }) async {
    Database? myDb = await db;
    if (myDb != null) {
      await _ensureAccessoryRulesColumns(myDb);
    }
    var res = await myDb!.update(
      'Accessories',
      data,
      where: 'id = ?',
      whereArgs: [id],
    );
    if (notifySync) CloudSyncService().notifyCatalogChange();
    return res;
  }

  /// Makes one accessory the default for its category/material scope.  The
  /// category is the part before the quality suffix in `type`, so changing a
  /// quality variant does not leave several competing defaults behind.
  Future<void> setAccessoryDefault(int id, bool enabled) async {
    final myDb = await db;
    if (myDb == null) return;
    final rows = await myDb.query(
      'Accessories',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return;
    final row = rows.first;
    if (enabled) {
      final rawType = row['type']?.toString() ?? '';
      final category = rawType.split('|').first.trim();
      final material = row['material_type']?.toString() ?? 'Aluminium';
      final scope = row['scope']?.toString() ?? 'Global';
      await myDb.transaction((txn) async {
        await txn.update(
          'Accessories',
          {'is_default': 0},
          where:
              "(type = ? OR type LIKE ?) AND material_type = ? AND scope = ?",
          whereArgs: [category, '$category|%', material, scope],
        );
        await txn.update(
          'Accessories',
          {'is_default': 1},
          where: 'id = ?',
          whereArgs: [id],
        );
      });
    } else {
      await myDb.update(
        'Accessories',
        {'is_default': 0},
        where: 'id = ?',
        whereArgs: [id],
      );
    }
    CloudSyncService().notifyCatalogChange(uploadImmediately: true);
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
    double? panelWidth,
    double? panelHeight,
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
      if (panelWidth != null) 'panel_width': panelWidth,
      if (panelHeight != null) 'panel_height': panelHeight,
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
    double? panelWidth,
    double? panelHeight,
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
        if (panelWidth != null) 'panel_width': panelWidth,
        if (panelHeight != null) 'panel_height': panelHeight,
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
    if (CloudSyncService.supabaseWorkshopDataOnly) return res;

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
    // Update in place so the row keeps its synchronised id.
    final updated = await myDb!.update(
      'GlassColorPrices',
      {'price': price},
      where: 'glass_id = ? AND color_name = ?',
      whereArgs: [glassId, colorName],
    );
    if (updated == 0) {
      await myDb.insert(
        'GlassColorPrices',
        SqlDatabase._withDistributedId({
      'glass_id': glassId,
      'color_name': colorName,
      'price': price,
        }),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await recordWorkshopPrice(
      myDb,
      table: 'GlassColorPrices',
      rowKey: SqlDatabase.priceRowKey([glassId, colorName]),
      column: 'price',
      price: price,
      source: 'manual',
    );
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
        'ALTER TABLE ShutterComponents ADD COLUMN max_width_mm REAL NOT NULL DEFAULT 6000.0;',
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
    double? maxWidthMm,
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
      'max_width_mm': maxWidthMm == null || maxWidthMm <= 0
          ? 6000.0
          : maxWidthMm,
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
    double? maxWidthMm,
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
        'max_width_mm': maxWidthMm == null || maxWidthMm <= 0
            ? 6000.0
            : maxWidthMm,
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

  /// Price per m² of [bladeType] in [colorId]: the colour's own price when
  /// it has one, else the price of every colour (colour 0).
  Future<double> getShutterSqmPriceForColor(
    String bladeType,
    int? colorId,
  ) async {
    if (colorId != null && colorId > 0) {
      final colorPrice = await getShutterSqmPrice(bladeType, colorId);
      if (colorPrice > 0) return colorPrice;
    }
    return getShutterSqmPrice(bladeType, 0);
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

  Future<int?> _defaultWhiteProfileColorId(DatabaseExecutor executor) async {
    final rows = await executor.rawQuery('''
      SELECT id FROM Colors
      WHERE (${SqlDatabase._whiteColorSql})
        AND (is_active = 1 OR is_active IS NULL)
      ORDER BY id ASC
      LIMIT 1
    ''');
    if (rows.isEmpty) return null;
    final rawId = rows.first['id'];
    return rawId is num ? rawId.toInt() : int.tryParse(rawId?.toString() ?? '');
  }

  Future<void> ensureProfileColorDefaults({int? profileId}) async {
    final myDb = await db;
    if (myDb == null) return;
    final changed = await myDb.transaction<bool>(
      (txn) => _ensureProfileColorDefaults(txn, profileId: profileId),
    );
    if (changed) CloudSyncService().notifyCatalogChange();
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

    if (lames.isEmpty) lames = ['Lame Injectée', 'Lame Extrudée'];
    if (glissieres.isEmpty)
      glissieres = ['Glissière 25', 'Glissière 120', 'Glissière 100'];

    return {'lames': lames, 'glissieres': glissieres};
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

  /// قراءة كل الـ Kits
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

  /// إضافة Kit جديد
  Future<int> insertKitBundle({
    required String name,
    String? description,
    bool perLeaf = false,
    String materialType = 'all',
  }) async {
    final database = await db;
    if (database == null) return -1;
    return await database.insert('KitBundles', {
      'name': name,
      'description': description,
      'per_leaf': perLeaf ? 1 : 0,
      'material_type': materialType,
      'is_active': 1,
    });
  }

  /// تعديل Kit
  Future<void> updateKitBundle(
    int id, {
    required String name,
    String? description,
    required bool perLeaf,
    String? materialType,
  }) async {
    final database = await db;
    if (database == null) return;
    final data = <String, dynamic>{
      'name': name,
      'description': description,
      'per_leaf': perLeaf ? 1 : 0,
    };
    if (materialType != null) {
      data['material_type'] = materialType;
    }
    await database.update('KitBundles', data, where: 'id = ?', whereArgs: [id]);
  }

  /// Ø­Ø°Ù  Kit (Ù†Ø§Ø¹Ù…)
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

  /// تحديث سعر Kit الإجمالي
  Future<void> updateKitBundlePrice(int id, double price) async {
    final database = await db;
    if (database == null) {
      throw StateError('Database is not available');
    }
    if (!price.isFinite || price < 0) {
      throw ArgumentError.value(price, 'price', 'Invalid Kit bundle price');
    }
    await _ensureAdvancedKitCompatibilitySchema(database);
    final updatedRows = await database.update(
      'KitBundles',
      {'price': price},
      where: 'id = ?',
      whereArgs: [id],
    );
    if (updatedRows != 1) {
      throw StateError(
        'Kit bundle price was not saved (id: $id, rows: $updatedRows)',
      );
    }
    final savedRows = await database.query(
      'KitBundles',
      columns: const ['price'],
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    final savedPrice = savedRows.isEmpty
        ? null
        : (savedRows.first['price'] as num?)?.toDouble();
    if (savedPrice == null || (savedPrice - price).abs() > 0.000001) {
      throw StateError(
        'Kit bundle price verification failed (id: $id, expected: $price, actual: $savedPrice)',
      );
    }
    // KitBundles belongs to the shared catalogue. A generic workshop-data
    // notification leaves the catalogue marked clean, so the next catalogue
    // download can restore the old price and make the save appear ineffective.
    await CloudSyncService().notifyCatalogChange();
  }

  Future<void> saveAccessoryLinks(
    int sourceAccessoryId,
    List<Map<String, dynamic>> links, {
    bool syncCatalog = true,
  }) async {
    final myDb = await db;
    if (myDb == null) return;
    await _ensureAccessoryLinksSchema(myDb);
    await myDb.transaction((txn) async {
      await txn.delete(
        'AccessoryRoleLinks',
        where: 'source_accessory_id = ?',
        whereArgs: [sourceAccessoryId],
      );
      for (final link in links) {
        final targetRole = link['target_role_key']?.toString().trim() ?? '';
        final quantity = (link['quantity'] as num?)?.toInt() ?? 0;
        if (targetRole.isEmpty || quantity <= 0) {
          continue;
        }
        await txn.insert('AccessoryRoleLinks', {
          'source_accessory_id': sourceAccessoryId,
          'target_role_key': targetRole,
          'quantity': quantity,
          'is_active': 1,
        });
      }
    });
    if (syncCatalog) CloudSyncService().notifyCatalogChange();
  }

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

  /// قراءة مركبات Kit محدد
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

  /// إضافة مركب لـ Kit
  Future<int> insertKitBundleItem({
    required int kitId,
    required String componentType,
    required String qtyMode, // 'fixed' | 'by_range' | 'by_variant'
    String? dimension, // 'leaf_height' | 'leaf_width' | null
    double baseQty = 1,
    String unit = 'قطعة',
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
      'unit': 'قطعة',
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

  /// تعديل مركب Kit
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
        'unit': 'قطعة',
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

  /// حذف مركب Kit
  Future<void> deleteKitBundleItem(int id) async {
    final database = await db;
    if (database == null) return;
    await database.delete('KitBundleItems', where: 'id = ?', whereArgs: [id]);
    // تُحذف النطاقات والمتغيرات تلقائياً بسبب ON DELETE CASCADE
  }

  /// قراءة نطاقات مركب محدد
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
      var componentId = (row['shutter_component_id'] as num?)?.toInt();
      var familyId = (row['family_id'] as num?)?.toInt();

      // A range is either linked to one component or one family, never both.
      // Normalize legacy malformed rows while reading as a second line of
      // defense for databases created before the exclusivity fix.
      if (componentId != null && familyId != null) {
        final activeFamily = await database.query(
          'KitBundleFamilies',
          columns: const ['id'],
          where: 'id = ? AND is_active = 1',
          whereArgs: [familyId],
          limit: 1,
        );
        if (activeFamily.isNotEmpty) {
          componentId = null;
          row['shutter_component_id'] = null;
        } else {
          familyId = null;
          row['family_id'] = null;
        }
      }
      if (componentId == null &&
          row['product_name'] != null &&
          row['product_name'].toString().trim().isNotEmpty) {
        final fallbackRows = await database.query(
          'ShutterComponents',
          where: 'LOWER(TRIM(name)) = LOWER(TRIM(?))',
          whereArgs: [row['product_name'].toString().trim()],
          limit: 1,
        );
        if (fallbackRows.isNotEmpty) {
          componentId = (fallbackRows.first['id'] as num?)?.toInt();
          row['shutter_component_id'] = componentId;
        }
      }
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

  /// إضافة نطاق
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
    // Enforce the model at the persistence boundary as well: callers may
    // never store a component and a family on the same range.
    final normalizedComponentId = shutterComponentId;
    final normalizedFamilyId = shutterComponentId == null ? familyId : null;
    final linkedColumn = normalizedComponentId != null
        ? 'shutter_component_id'
        : normalizedFamilyId != null
        ? 'family_id'
        : null;
    final linkedId = normalizedComponentId ?? normalizedFamilyId;
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
      'shutter_component_id': normalizedComponentId,
      'family_id': normalizedFamilyId,
    });
    CloudSyncService().notifyCatalogChange();
    return result;
  }

  /// تعديل نطاق
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
    // Keep updates mutually exclusive too, including updates made by import
    // or older callers that still provide both IDs.
    final normalizedComponentId = shutterComponentId;
    final normalizedFamilyId = shutterComponentId == null ? familyId : null;
    final linkedColumn = normalizedComponentId != null
        ? 'shutter_component_id'
        : normalizedFamilyId != null
        ? 'family_id'
        : null;
    final linkedId = normalizedComponentId ?? normalizedFamilyId;
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
        'shutter_component_id': normalizedComponentId,
        'family_id': normalizedFamilyId,
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
            ? 'Console Quissonnel Spécial'
            : group2Name.trim(),
      },
      where: 'id = ?',
      whereArgs: [kitId],
    );
    CloudSyncService().notifyCatalogChange();
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
    await database.delete('KitItemVariants', where: 'id = ?', whereArgs: [id]);
  }

  /// قراءة كل مركبات Kit مع نطاقاتها ومتغيراتها — للحساب في BOM
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

      if (itemMap['qty_mode'] == 'fixed' &&
          ((itemMap['price'] as num?)?.toDouble() ?? 0.0) <= 0) {
        final compType = (itemMap['component_type'] ?? '').toString().trim();
        if (compType.isNotEmpty) {
          final compRows = await database.query(
            'ShutterComponents',
            columns: const ['id', 'name', 'price'],
            where:
                'LOWER(TRIM(name)) = LOWER(TRIM(?)) OR LOWER(TRIM(component_type)) = LOWER(TRIM(?))',
            whereArgs: [compType, compType],
            limit: 1,
          );
          if (compRows.isNotEmpty) {
            itemMap['price'] = compRows.first['price'];
            itemMap['shutter_component_id'] = compRows.first['id'];
          }
        }
      }

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
    await recordWorkshopPrice(
      myDb,
      table: 'CaissonTunnelPrices',
      rowKey: SqlDatabase.priceRowKey([colorId]),
      column: 'price_per_meter',
      price: pricePerMeter,
      source: 'manual',
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
    int maxSlidingSashes = 0,
    bool notifySync = true,
  }) async {
    final myDb = await db;
    if (myDb == null) return;
    await myDb.execute(
      '''
      INSERT INTO SeriesTableConfig (
        series_id, allowed_section_types, allowed_accessory_ids, allowed_accessory_types, excluded_accessory_ids,
        sash_w_deduction_2, sash_w_deduction_3, sash_w_deduction_4, sash_overlap_val, glass_w_deduction,
        sliding_chicane_pieces_per_junction, sliding_rail_clearance, custom_formula_notes, max_sliding_sashes, updated_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
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
        max_sliding_sashes = excluded.max_sliding_sashes,
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
        maxSlidingSashes,
        DateTime.now().toUtc().toIso8601String(),
      ],
    );
    if (notifySync) CloudSyncService().notifyCatalogChange();
  }

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

  /// Replaces only the profile-to-role mapping of a series.  It deliberately
  /// leaves drawing options and shutter rules untouched: a shutter is a
  /// separate product and must not be coupled to the aluminium series.
  Future<void> saveSeriesDesignRoles({
    required int seriesId,
    required List<Map<String, dynamic>> roles,
    bool syncCatalog = true,
  }) async {
    final myDb = await db;
    if (myDb == null) return;
    await _ensureSeriesDesignTables(myDb);
    await _ensureSectionSharingSchema(myDb);
    final localSections = await readSectionsBySeries(seriesId);
    final sharingRules = await readSectionSharingRules(
      targetScope: 'series',
      targetId: seriesId,
    );
    final localSectionIds = localSections
        .map((section) => (section['id'] as num?)?.toInt())
        .whereType<int>()
        .toSet();
    final sharedRolesBySection = <int, Set<String>>{};
    for (final rule in sharingRules) {
      final sectionId = (rule['source_section_id'] as num?)?.toInt();
      final sharedRole = rule['role_key']?.toString().trim() ?? '';
      if (sectionId != null && sharedRole.isNotEmpty) {
        sharedRolesBySection
            .putIfAbsent(sectionId, () => <String>{})
            .add(sharedRole);
      }
    }
    final now = DateTime.now().toUtc().toIso8601String();
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
        final belongsToSeries = localSectionIds.contains(sectionId);
        final explicitlySharedForRole =
            sharedRolesBySection[sectionId]?.contains(roleKey) == true;
        if (!belongsToSeries && !explicitlySharedForRole) continue;
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
          'skip_glazing_bead':
              role['skip_glazing_bead'] == true ||
                  role['skip_glazing_bead'] == 1
              ? 1
              : 0,
          'requires_plant':
              role['requires_plant'] == true || role['requires_plant'] == 1
              ? 1
              : 0,
          'joint_length_multiplier': role['joint_length_multiplier'] ?? 1.0,
          'track_mode': role['track_mode']?.toString() ?? '',
          'track_count': role['track_count'] ?? 0,
          'track_adds': role['track_adds'] ?? 0,
          'supported_track_counts':
              role['supported_track_counts']?.toString() ?? '',
          'compatible_frame_ids':
              role['compatible_frame_ids']?.toString() ?? '',
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
    if (syncCatalog) {
      await CloudSyncService().notifyCatalogChange(uploadImmediately: true);
    }
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
    bool syncCatalog = true,
  }) async {
    final myDb = await db;
    if (myDb == null) return;
    await _ensureSeriesDesignTables(myDb);
    final now = DateTime.now().toUtc().toIso8601String();
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
    if (syncCatalog) {
      await CloudSyncService().notifyCatalogChange(uploadImmediately: true);
    }
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

  /// Reuses a screw role in every series explicitly selected on the
  /// accessory itself. This bridges legacy catalogues where the role row was
  /// saved for the first series only while `series_ids` already lists two or
  /// more compatible series.
  Future<List<Map<String, dynamic>>> getAssignedAccessoryScrewRuleFallbacks(
    int seriesId,
  ) async {
    final myDb = await db;
    if (myDb == null) return [];
    await _ensureSeriesDesignTables(myDb);
    return myDb.rawQuery(
      '''
      SELECT r.*
      FROM CatalogItemRules r
      INNER JOIN Accessories a ON a.id = r.item_id
      WHERE r.item_table = 'Accessories'
        AND r.is_active = 1
        AND r.role_key IN ('assembly_screw', 'installation_screw')
        AND (
          a.series_id = ?
          OR (a.series_ids IS NOT NULL
              AND TRIM(a.series_ids) != ''
              AND ',' || REPLACE(a.series_ids, ' ', '') || ',' LIKE ?)
        )
        AND NOT EXISTS (
          SELECT 1 FROM CatalogItemRules exact_rule
          WHERE exact_rule.item_table = r.item_table
            AND exact_rule.item_id = r.item_id
            AND exact_rule.series_id = ?
        )
      ORDER BY r.is_default DESC, r.sort_order ASC, r.id ASC
      ''',
      [seriesId, '%,$seriesId,%', seriesId],
    );
  }

  Future<void> saveCatalogItemRules({
    required String itemTable,
    int? seriesId,
    required List<Map<String, dynamic>> rules,
    bool syncCatalog = true,
  }) async {
    final myDb = await db;
    if (myDb == null) return;
    await _ensureSeriesDesignTables(myDb);
    final cleanTable = itemTable.trim();
    if (cleanTable.isEmpty) return;
    final now = DateTime.now().toUtc().toIso8601String();
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
          'assembly_target': rule['assembly_target']?.toString() ?? '',
          'top_corner_qty': rule['top_corner_qty'] ?? 1,
          'bottom_corner_qty': rule['bottom_corner_qty'] ?? 1,
          'assembly_section_id': rule['assembly_section_id'],
          'assembly_section_ids':
              rule['assembly_section_ids']?.toString() ?? '',
          'assembly_section_quantities':
              rule['assembly_section_quantities']?.toString() ?? '',
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
          'min_height_mm': rule['min_height_mm'],
          'max_height_mm': rule['max_height_mm'],
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
    if (syncCatalog) {
      await CloudSyncService().notifyCatalogChange(uploadImmediately: true);
    }
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
    final now = DateTime.now().toUtc().toIso8601String();
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
          'skip_glazing_bead':
              role['skip_glazing_bead'] == true ||
                  role['skip_glazing_bead'] == 1
              ? 1
              : 0,
          'requires_plant':
              role['requires_plant'] == true || role['requires_plant'] == 1
              ? 1
              : 0,
          'joint_length_multiplier': role['joint_length_multiplier'] ?? 1.0,
          'track_mode': role['track_mode']?.toString() ?? '',
          'track_count': role['track_count'] ?? 0,
          'track_adds': role['track_adds'] ?? 0,
          'supported_track_counts':
              role['supported_track_counts']?.toString() ?? '',
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
    await CloudSyncService().notifyCatalogChange(uploadImmediately: true);
  }

  Future<void> ensureProfileCalculationRulesTable() async {
    final myDb = await db;
    if (myDb == null) return;
    await _ensureProfileCalculationRulesTable(myDb);
  }

  /// Resolves profiles for the drawing surface only.  The drawing must obey
  /// both the role assignment and its opening/sliding scope; section names
  /// are not a substitute for either rule.
  Future<List<Map<String, dynamic>>> getDesignSectionsForDrawingRoles(
    int seriesId,
    Iterable<String> roleKeys, {
    required String usageScope,
  }) async {
    return _getDesignSectionsForRoles(
      seriesId,
      roleKeys,
      requireDialog: false,
      requireDrawing: true,
      usageScope: usageScope,
    );
  }

  Future<List<Map<String, dynamic>>> _getDesignSectionsForRoles(
    int seriesId,
    Iterable<String> roleKeys, {
    bool requireDialog = true,
    bool requireQuantity = false,
    bool requireVisible = true,
    bool requireDrawing = false,
    String? usageScope,
  }) async {
    final keys = roleKeys.where((key) => key.trim().isNotEmpty).toList();
    if (keys.isEmpty) return [];
    final myDb = await db;
    if (myDb == null) return [];
    await _ensureSeriesDesignTables(myDb);
    await _ensureSectionSharingSchema(myDb);
    final placeholders = List.filled(keys.length, '?').join(',');
    final surfaceFilters = <String>[
      if (requireVisible) 'r.is_visible = 1',
      if (requireDialog) 'r.show_in_dialog = 1',
      if (requireQuantity) 'r.show_in_quantity = 1',
      if (requireDrawing) 'r.show_in_drawing = 1',
      if (usageScope != null) "r.usage_scope IN ('auto', 'both', ?)",
    ];
    // Functional drawing roles such as Montant Slim and its top/bottom
    // complement deliberately bypass visibility and dialog flags. In that
    // case there may be no surface filter at all; never emit an empty
    // `AND ... AND` SQL fragment, as it makes their selector return nothing.
    final surfaceClause = surfaceFilters.isEmpty
        ? ''
        : 'AND ${surfaceFilters.join('\n        AND ')}';
    return myDb.rawQuery(
      '''
      SELECT s.*,
             r.role_key AS design_role_key,
             r.show_when_glass AS design_show_when_glass,
             r.usage_scope AS design_usage_scope,
             r.integrated_side_cover AS design_integrated_side_cover,
             r.allows_side_cover AS design_allows_side_cover,
             r.allowed_with_shutter AS design_allowed_with_shutter,
             r.width_adjust_mm AS design_width_adjust_mm,
             r.height_adjust_mm AS design_height_adjust_mm,
             r.formula_note AS design_formula_note,
             r.skip_glazing_bead AS design_skip_glazing_bead,
             r.requires_plant AS design_requires_plant,
             r.joint_length_multiplier AS design_joint_length_multiplier,
             r.track_mode AS design_track_mode,
             r.track_count AS design_track_count,
             r.track_adds AS design_track_adds,
             r.supported_track_counts AS design_supported_track_counts,
             r.is_default AS design_is_default
      FROM Sections s
      INNER JOIN SeriesDesignRoles r ON r.section_id = s.id
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
        $surfaceClause
        AND r.role_key IN ($placeholders)
        AND (s.is_active = 1 OR s.is_active IS NULL)
      ORDER BY r.is_default DESC, r.sort_order ASC, s.name ASC
    ''',
      [
        seriesId,
        seriesId,
        seriesId,
        if (usageScope != null) usageScope,
        ...keys,
      ],
    );
  }
}
