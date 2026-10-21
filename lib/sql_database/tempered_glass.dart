part of '../sql_database.dart';

/// Tempered glass items, systems, kits and rules.
extension SqlDatabaseTemperedGlass on SqlDatabase {
  Future<void> ensureTemperedGlassItemsTable() async {
    final myDb = await db;
    if (myDb == null) return;
    await _ensureTemperedGlassItemsTable(myDb);
    await seedDefaultTemperedGlassItems();
  }

  Future<List<Map<String, dynamic>>> getTemperedGlassItems({
    String? category,
    String? type,
  }) async {
    final myDb = await db;
    if (myDb == null) return [];
    await _ensureTemperedGlassItemsTable(myDb);
    await seedDefaultTemperedGlassItems();
    await _ensureVROHandlesAndColorsSeeded(myDb);
    await _ensureTemperedGlassServicesSeeded(myDb);

    String where = 'is_active = 1';
    List<dynamic> args = [];
    if (category != null && category.isNotEmpty && category != 'all') {
      where += ' AND category = ?';
      args.add(category);
    }
    if (type != null && type.isNotEmpty && type != 'all') {
      where += ' AND type = ?';
      args.add(type);
    }
    return await myDb.query(
      'TemperedGlassItems',
      where: where,
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'id ASC',
    );
  }

  Future<int> insertTemperedGlassItem(Map<String, dynamic> item) async {
    final myDb = await db;
    if (myDb == null) return 0;
    await _ensureTemperedGlassItemsTable(myDb);
    return await myDb.insert('TemperedGlassItems', item);
  }

  Future<int> updateTemperedGlassItem(int id, Map<String, dynamic> item) async {
    final myDb = await db;
    if (myDb == null) return 0;
    return await myDb.update(
      'TemperedGlassItems',
      item,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> deleteTemperedGlassItem(int id) async {
    return runUserDeletion<int>('deleteTemperedGlassItem', () async {
      final myDb = await db;
      if (myDb == null) return 0;
      return await myDb.update(
        'TemperedGlassItems',
        {'is_active': 0},
        where: 'id = ?',
        whereArgs: [id],
      );
    });
  }

  Future<int> updateTemperedGlassItemPrice(int id, double price) async {
    final myDb = await db;
    if (myDb == null) return 0;
    return await myDb.update(
      'TemperedGlassItems',
      {'price': price},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> ensureTemperedGlassSystemsAndRulesTables() async {
    final myDb = await db;
    if (myDb == null) return;
    await _ensureTemperedGlassSystemsAndRulesTables(myDb);
    await seedDefaultTemperedGlassSystemsAndKits();
  }

  Future<List<Map<String, dynamic>>> getTemperedGlassSystems({
    bool onlyActive = false,
  }) async {
    final myDb = await db;
    if (myDb == null) return [];
    await _ensureTemperedGlassSystemsAndRulesTables(myDb);
    await seedDefaultTemperedGlassSystemsAndKits();

    final where = onlyActive ? 'is_active = 1' : null;
    return await myDb.query(
      'TemperedGlassSystems',
      where: where,
      orderBy: 'display_order ASC, id ASC',
    );
  }

  Future<int> insertTemperedGlassSystem(Map<String, dynamic> system) async {
    final myDb = await db;
    if (myDb == null) return 0;
    await _ensureTemperedGlassSystemsAndRulesTables(myDb);
    return await myDb.insert('TemperedGlassSystems', system);
  }

  Future<int> updateTemperedGlassSystem(
    int id,
    Map<String, dynamic> system,
  ) async {
    final myDb = await db;
    if (myDb == null) return 0;
    return await myDb.update(
      'TemperedGlassSystems',
      system,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> deleteTemperedGlassSystem(int id) async {
    return runUserDeletion<int>('deleteTemperedGlassSystem', () async {
      final myDb = await db;
      if (myDb == null) return 0;
      return await myDb.update(
        'TemperedGlassSystems',
        {'is_active': 0},
        where: 'id = ?',
        whereArgs: [id],
      );
    });
  }

  Future<List<Map<String, dynamic>>> getTemperedGlassKits({
    String? systemCode,
    bool onlyActive = false,
  }) async {
    final myDb = await db;
    if (myDb == null) return [];
    await _ensureTemperedGlassSystemsAndRulesTables(myDb);
    await seedDefaultTemperedGlassSystemsAndKits();

    String? where;
    List<dynamic>? args;

    if (onlyActive && systemCode != null && systemCode.isNotEmpty) {
      where =
          'is_active = 1 AND (system_code = ? OR system_code = "" OR system_code IS NULL)';
      args = [systemCode];
    } else if (onlyActive) {
      where = 'is_active = 1';
    } else if (systemCode != null && systemCode.isNotEmpty) {
      where = 'system_code = ? OR system_code = "" OR system_code IS NULL';
      args = [systemCode];
    }

    return await myDb.query(
      'TemperedGlassKits',
      where: where,
      whereArgs: args,
      orderBy: 'id ASC',
    );
  }

  Future<int> insertTemperedGlassKit(Map<String, dynamic> kit) async {
    final myDb = await db;
    if (myDb == null) return 0;
    await _ensureTemperedGlassSystemsAndRulesTables(myDb);
    return await myDb.insert('TemperedGlassKits', kit);
  }

  Future<int> updateTemperedGlassKit(int id, Map<String, dynamic> kit) async {
    final myDb = await db;
    if (myDb == null) return 0;
    return await myDb.update(
      'TemperedGlassKits',
      kit,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> deleteTemperedGlassKit(int id) async {
    return runUserDeletion<int>('deleteTemperedGlassKit', () async {
      final myDb = await db;
      if (myDb == null) return 0;
      await myDb.delete(
        'TemperedGlassKitHoles',
        where: 'kit_id = ?',
        whereArgs: [id],
      );
      await myDb.delete(
        'TemperedGlassSystemRules',
        where: 'kit_id = ?',
        whereArgs: [id],
      );
      await myDb.delete(
        'TemperedGlassKitComponents',
        where: 'kit_id = ?',
        whereArgs: [id],
      );
      return await myDb.delete(
        'TemperedGlassKits',
        where: 'id = ?',
        whereArgs: [id],
      );
    });
  }

  Future<List<Map<String, dynamic>>> getTemperedGlassKitHoles(int kitId) async {
    final myDb = await db;
    if (myDb == null) return [];
    await _ensureTemperedGlassSystemsAndRulesTables(myDb);
    return await myDb.query(
      'TemperedGlassKitHoles',
      where: 'kit_id = ?',
      whereArgs: [kitId],
      orderBy: 'hole_index ASC, id ASC',
    );
  }

  Future<void> saveTemperedGlassKitHoles(
    int kitId,
    List<Map<String, dynamic>> holes,
  ) async {
    final myDb = await db;
    if (myDb == null) return;
    await _ensureTemperedGlassSystemsAndRulesTables(myDb);

    await myDb.transaction((txn) async {
      await txn.delete(
        'TemperedGlassKitHoles',
        where: 'kit_id = ?',
        whereArgs: [kitId],
      );
      for (var i = 0; i < holes.length; i++) {
        final hole = Map<String, dynamic>.from(holes[i]);
        hole['kit_id'] = kitId;
        hole['hole_index'] = i + 1;
        await txn.insert('TemperedGlassKitHoles', hole);
      }
    });
  }

  Future<List<Map<String, dynamic>>> getTemperedGlassKitComponents(
    int kitId,
  ) async {
    final myDb = await db;
    if (myDb == null) return [];
    await _ensureTemperedGlassSystemsAndRulesTables(myDb);
    return myDb.rawQuery(
      '''
      SELECT c.*, i.name AS item_name, i.category AS item_category,
             i.price AS item_price, i.unit AS item_unit, i.notes AS item_notes
      FROM TemperedGlassKitComponents c
      JOIN TemperedGlassItems i ON i.id = c.item_id
      WHERE c.kit_id = ?
      ORDER BY i.category ASC, i.name ASC
    ''',
      [kitId],
    );
  }

  Future<void> saveTemperedGlassKitComponents(
    int kitId,
    List<Map<String, dynamic>> components,
  ) async {
    final myDb = await db;
    if (myDb == null) return;
    await _ensureTemperedGlassSystemsAndRulesTables(myDb);
    await myDb.transaction((txn) async {
      await txn.delete(
        'TemperedGlassKitComponents',
        where: 'kit_id = ?',
        whereArgs: [kitId],
      );
      for (final source in components) {
        final row = Map<String, dynamic>.from(source)
          ..remove('id')
          ..remove('item_name')
          ..remove('item_category')
          ..remove('item_price')
          ..remove('item_unit')
          ..remove('item_notes')
          ..['kit_id'] = kitId;
        await txn.insert('TemperedGlassKitComponents', row);
      }
    });
  }

  Future<List<Map<String, dynamic>>> getTemperedGlassSystemRules(
    String systemCode, {
    double? glassThicknessMm,
  }) async {
    final myDb = await db;
    if (myDb == null) return [];
    await _ensureTemperedGlassSystemsAndRulesTables(myDb);
    await seedDefaultTemperedGlassSystemsAndKits();

    String query = '''
      SELECT r.*, 
             k.name as kit_name, k.code as kit_code, k.target_panel as kit_target_panel,
             i.name as item_name, i.category as item_category, i.price as item_price, i.unit as item_unit, i.notes as item_notes
      FROM TemperedGlassSystemRules r
      LEFT JOIN TemperedGlassKits k ON r.kit_id = k.id
      LEFT JOIN TemperedGlassItems i ON r.item_id = i.id
      WHERE r.system_code = ? AND r.is_active = 1
    ''';
    List<dynamic> args = [systemCode];

    if (glassThicknessMm != null && glassThicknessMm > 0) {
      query += ' AND (r.glass_thickness_mm = 0 OR r.glass_thickness_mm = ?)';
      args.add(glassThicknessMm);
    }

    query += ' ORDER BY r.rule_type ASC, r.is_default DESC, r.id ASC';
    return await myDb.rawQuery(query, args);
  }

  Future<int> insertTemperedGlassSystemRule(Map<String, dynamic> rule) async {
    final myDb = await db;
    if (myDb == null) return 0;
    await _ensureTemperedGlassSystemsAndRulesTables(myDb);
    return await myDb.insert('TemperedGlassSystemRules', rule);
  }

  Future<int> updateTemperedGlassSystemRule(
    int id,
    Map<String, dynamic> rule,
  ) async {
    final myDb = await db;
    if (myDb == null) return 0;
    return await myDb.update(
      'TemperedGlassSystemRules',
      rule,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> deleteTemperedGlassSystemRule(int id) async {
    return runUserDeletion<int>('deleteTemperedGlassSystemRule', () async {
      final myDb = await db;
      if (myDb == null) return 0;
      return await myDb.delete(
        'TemperedGlassSystemRules',
        where: 'id = ?',
        whereArgs: [id],
      );
    });
  }

  Future<void> toggleTemperedGlassSystemRule({
    required String systemCode,
    int? kitId,
    int? itemId,
    required String ruleType,
    required bool isActive,
    double glassThicknessMm = 0.0,
  }) async {
    final myDb = await db;
    if (myDb == null) return;
    await _ensureTemperedGlassSystemsAndRulesTables(myDb);

    String where = 'system_code = ? AND rule_type = ?';
    List<dynamic> args = [systemCode, ruleType];

    if (kitId != null) {
      where += ' AND kit_id = ?';
      args.add(kitId);
    } else if (itemId != null) {
      where += ' AND item_id = ?';
      args.add(itemId);
    }

    final existing = await myDb.query(
      'TemperedGlassSystemRules',
      where: where,
      whereArgs: args,
    );
    if (existing.isNotEmpty) {
      await myDb.update(
        'TemperedGlassSystemRules',
        {'is_active': isActive ? 1 : 0, 'glass_thickness_mm': glassThicknessMm},
        where: where,
        whereArgs: args,
      );
    } else if (isActive) {
      await myDb.insert('TemperedGlassSystemRules', {
        'system_code': systemCode,
        'kit_id': kitId,
        'item_id': itemId,
        'rule_type': ruleType,
        'glass_thickness_mm': glassThicknessMm,
        'is_default': 0,
        'is_active': 1,
      });
    }
  }
}
