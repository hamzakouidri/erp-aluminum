part of '../sql_database.dart';

/// Stock, locations, remnants, sheets and material sales.
extension SqlDatabaseInventory on SqlDatabase {
  /// Reserves (or releases) the stock an order needs.
  ///
  /// [stockDeductions] uses the same rows as [applyOrderInventoryIssue]
  /// (item_id, item_type, color_id, location_id, quantity). Reserving replaces
  /// the order's previous hold and fails without changing anything when a
  /// balance cannot cover it after other orders' reservations, or when a
  /// remnant is no longer free. Releasing frees every active hold.
  Future<bool> setOrderStockReservation({
    required int orderId,
    required bool reserved,
    List<int>? remnantIds,
    List<Map<String, dynamic>>? stockDeductions,
  }) async {
    final myDb = await db;
    if (myDb == null) return false;
    await _ensureOrderStockReservationInfrastructure(myDb);
    await _ensureRemnantInventorySchema(myDb);
    await _ensureOrderInventoryIssueSchema(myDb);
    final author = await _currentOrderEditor();

    await myDb.transaction((txn) async {
      final now = DateTime.now().toUtc().toIso8601String();
      if (reserved) {
        final issued = await txn.query(
          'OrderInventoryIssueSessions',
          columns: const ['id'],
          where: 'order_id = ?',
          whereArgs: [orderId],
          limit: 1,
        );
        if (issued.isNotEmpty) {
          throw StateError(
            'تم صرف مخزون الطلبية #$orderId مسبقاً، فلا حاجة إلى حجزه.',
          );
        }
      }

      // Drop the previous hold first so a re-reservation is checked against
      // the new quantities only.
      await _releaseOrderStockHold(txn, orderId, now);

      if (reserved) {
        final requested = <String, Map<String, dynamic>>{};
        for (final row in stockDeductions ?? const <Map<String, dynamic>>[]) {
          final itemId = (row['item_id'] as num?)?.toInt();
          final itemType = row['item_type']?.toString().trim();
          final locationId = (row['location_id'] as num?)?.toInt();
          final quantity = SqlDatabase._readStoredNumber(row['quantity']) ?? 0;
          if (itemId == null ||
              itemType == null ||
              itemType.isEmpty ||
              locationId == null ||
              quantity <= 0) {
            continue;
          }
          final colorId = (row['color_id'] as num?)?.toInt();
          final key = '$itemId|$itemType|${colorId ?? ''}|$locationId';
          final entry = requested.putIfAbsent(
            key,
            () => {
              'item_id': itemId,
              'item_type': itemType,
              'color_id': colorId,
              'location_id': locationId,
              'quantity': 0.0,
            },
          );
          entry['quantity'] = (entry['quantity'] as double) + quantity;
        }

        for (final entry in requested.values) {
          final itemId = entry['item_id'] as int;
          final itemType = entry['item_type'] as String;
          final colorId = entry['color_id'] as int?;
          final locationId = entry['location_id'] as int;
          final quantity = entry['quantity'] as double;
          await _ensureUnreservedStock(
            txn,
            itemId: itemId,
            itemType: itemType,
            colorId: colorId,
            locationId: locationId,
            quantity: quantity,
            excludeOrderId: orderId,
          );
          await txn.insert(
            'StockReservations',
            SqlDatabase._withDistributedId({
              'order_id': orderId,
              'item_id': itemId,
              'item_type': itemType,
              'color_id': colorId,
              'location_id': locationId,
              'quantity': quantity,
              'status': 'active',
              'created_at': now,
              'updated_at': now,
              'created_by': author,
            }),
          );
        }

        for (final id in (remnantIds ?? const <int>[]).toSet()) {
          final updated = await txn.update(
            'MaterialRemnants',
            {
              'status': 'reserved',
              'reserved_order_id': orderId,
              'reserved_at': now,
              'updated_at': now,
            },
            where: 'id = ? AND status = ?',
            whereArgs: [id, 'available'],
          );
          if (updated == 0) {
            throw StateError(
              'الفضلة رقم $id غير متاحة: محجوزة لطلبية أخرى أو سبق صرفها.',
            );
          }
        }
      }

      await txn.update(
        'Commandes',
        {
          'is_stock_reserved': reserved ? 1 : 0,
          'stock_reserved_at': reserved ? now : null,
        },
        where: 'id = ?',
        whereArgs: [orderId],
      );
    });

    CloudSyncService().notifyChange();
    return true;
  }

  /// Frees everything [orderId] holds: active stock reservations and
  /// reserved remnants. The caller updates the order's reservation flag.
  Future<void> _releaseOrderStockHold(
    DatabaseExecutor executor,
    int orderId,
    String timestamp,
  ) async {
    await executor.update(
      'StockReservations',
      {'status': 'released', 'updated_at': timestamp},
      where: 'order_id = ? AND status = ?',
      whereArgs: [orderId, 'active'],
    );
    await executor.update(
      'MaterialRemnants',
      {
        'status': 'available',
        'reserved_order_id': null,
        'reserved_at': null,
        'updated_at': timestamp,
      },
      where: 'reserved_order_id = ? AND status = ?',
      whereArgs: [orderId, 'reserved'],
    );
  }

  /// Total held by active reservations on one CurrentStock balance.
  /// [excludeOrderId] leaves out that order's own hold, so an order can
  /// always use what it reserved.
  Future<double> _activeReservedQuantity(
    DatabaseExecutor executor, {
    required int itemId,
    required String itemType,
    int? colorId,
    required int locationId,
    int? excludeOrderId,
  }) async {
    final rows = await executor.rawQuery(
      '''
      SELECT COALESCE(SUM(quantity), 0) AS reserved
      FROM StockReservations
      WHERE status = 'active' AND item_id = ? AND item_type = ?
        AND (color_id = ? OR (color_id IS NULL AND ? IS NULL))
        AND location_id = ?
        ${excludeOrderId == null ? '' : 'AND order_id != ?'}
      ''',
      [
        itemId,
        itemType,
        colorId,
        colorId,
        locationId,
        if (excludeOrderId != null) excludeOrderId,
      ],
    );
    return SqlDatabase._readStoredNumber(rows.first['reserved']) ?? 0;
  }

  /// Throws when taking [quantity] from a balance would use stock reserved
  /// for another order. [currentQuantity] is read from CurrentStock when not
  /// given. Callers must have run [_ensureRemnantInventorySchema].
  Future<void> _ensureUnreservedStock(
    DatabaseExecutor executor, {
    required int itemId,
    required String itemType,
    int? colorId,
    required int locationId,
    required double quantity,
    double? currentQuantity,
    int? excludeOrderId,
    String? label,
  }) async {
    var current = currentQuantity;
    if (current == null) {
      final rows = await executor.query(
        'CurrentStock',
        columns: const ['quantity'],
        where: colorId == null
            ? 'item_id = ? AND item_type = ? AND color_id IS NULL AND location_id = ?'
            : 'item_id = ? AND item_type = ? AND color_id = ? AND location_id = ?',
        whereArgs: colorId == null
            ? [itemId, itemType, locationId]
            : [itemId, itemType, colorId, locationId],
        limit: 1,
      );
      current = rows.isEmpty
          ? 0.0
          : (SqlDatabase._readStoredNumber(rows.first['quantity']) ?? 0);
    }
    final reserved = await _activeReservedQuantity(
      executor,
      itemId: itemId,
      itemType: itemType,
      colorId: colorId,
      locationId: locationId,
      excludeOrderId: excludeOrderId,
    );
    final free = current - reserved;
    if (free + 0.000001 < quantity) {
      final name = label ?? '$itemId ($itemType)';
      throw StateError(
        reserved > 0.000001
            ? 'الكمية غير متاحة للصنف $name: المتوفر $current منها $reserved محجوزة لطلبيات أخرى، والمتاح ${free < 0 ? 0 : free} والمطلوب $quantity. ألغِ الحجز أو وفّر كمية إضافية.'
            : 'المخزون غير كافٍ للصنف $name: المطلوب $quantity والمتاح $current.',
      );
    }
  }

  Future<bool> isOrderStockReserved(int orderId) async {
    final myDb = await db;
    if (myDb == null) return false;
    await _ensureOrderStockReservationInfrastructure(myDb);
    final rows = await myDb.query(
      'Commandes',
      columns: ['is_stock_reserved'],
      where: 'id = ?',
      whereArgs: [orderId],
    );
    if (rows.isEmpty) return false;
    return (rows.first['is_stock_reserved'] as num?)?.toInt() == 1;
  }

  /// Material customers are separated from window customers while still
  /// sharing one customer record and one financial history.
  Future<List<Map<String, dynamic>>> readMaterialClients({
    bool includeWindowClients = false,
    bool includeInternalWorkshop = false,
  }) async {
    final myDb = await db;
    if (myDb == null) return [];
    await _ensureClientBusinessSegment(myDb);
    final allowedSegments = <String>['materials', 'both'];
    if (includeInternalWorkshop) {
      allowedSegments.add('internal_workshop');
    }
    final inList = allowedSegments.map((s) => "'$s'").join(', ');
    final rows = await myDb.query(
      'Client',
      where: includeWindowClients ? null : "business_segment IN ($inList)",
      orderBy: 'firstname COLLATE NOCASE, lastname COLLATE NOCASE',
    );
    // إذا وجد أكثر من سطر للورشة داخلي قبل التنظيف، نظهر واحداً فقط
    final seenInternal = <String>{};
    return rows.where((client) {
      if (client['business_segment'] == 'internal_workshop') {
        if (seenInternal.isNotEmpty) return false;
        seenInternal.add('internal');
      }
      return true;
    }).toList();
  }

  /// Generic material-store customer for walk-in sales without a buyer name.
  Future<Map<String, dynamic>> ensureDiversMaterialClient() async {
    final myDb = await db;
    if (myDb == null) return {};
    await _ensureClientBusinessSegment(myDb);
    final existing = await myDb.query(
      'Client',
      where:
          "LOWER(TRIM(firstname)) = 'divers' AND business_segment IN ('materials', 'both')",
      limit: 1,
    );
    if (existing.isNotEmpty) return existing.first;

    final now = DateTime.now().toUtc().toIso8601String();
    final clientCode = await _reserveNextClientCode(myDb);
    final newId = await myDb.insert(
      'Client',
      SqlDatabase._withDistributedId({
        'client_code': clientCode,
        'firstname': 'Divers',
        'lastname': '',
        'phone1': '',
        'phone2': '',
        'email': '',
        'address': '',
        'business_segment': 'materials',
        'created_at': now,
        'updated_at': now,
        'creation_platform': 'desktop',
      }),
    );
    CloudSyncService().notifyChangeImmediate();
    final created = await myDb.query(
      'Client',
      where: 'id = ?',
      whereArgs: [newId],
    );
    return created.isNotEmpty ? created.first : {};
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
            "reference_id = ? AND transaction_type IN ('Sale', 'Consumption', 'Usage', 'order_issue', 'order_issue_remnant')",
        whereArgs: [commandeId],
        limit: 1,
      );
      return result.isNotEmpty;
    } catch (e) {
      return false;
    }
  }

  Future<bool> hasOrderInventoryIssue(int orderId) async {
    final myDb = await db;
    if (myDb == null) return false;
    await _ensureOrderInventoryIssueSchema(myDb);
    final rows = await myDb.query(
      'OrderInventoryIssueSessions',
      columns: const ['id'],
      where: 'order_id = ?',
      whereArgs: [orderId],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  Future<double?> _readInventorySettingNumber(String key) async {
    final myDb = await db;
    if (myDb == null) return null;
    await _ensureRemnantInventorySchema(myDb);
    final rows = await myDb.query(
      'InventorySettings',
      columns: const ['numeric_value'],
      where: 'setting_key = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final value = SqlDatabase._readStoredNumber(rows.first['numeric_value']);
    return value != null && value > 0 ? value : null;
  }

  Future<void> _saveInventorySettingNumber(String key, double value) async {
    if (value <= 0) {
      throw ArgumentError.value(value, 'value', 'Must be positive');
    }
    final myDb = await db;
    if (myDb == null) return;
    await _ensureRemnantInventorySchema(myDb);
    final rows = await myDb.query(
      'InventorySettings',
      columns: const ['id'],
      where: 'setting_key = ?',
      whereArgs: [key],
      limit: 1,
    );
    final values = {
      'numeric_value': value,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
    if (rows.isEmpty) {
      await myDb.insert(
        'InventorySettings',
        SqlDatabase._withDistributedId({'setting_key': key, ...values}),
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

  Future<double?> readSawKerfMm() => _readInventorySettingNumber('saw_kerf_mm');

  Future<void> saveSawKerfMm(double kerfMm) =>
      _saveInventorySettingNumber('saw_kerf_mm', kerfMm);

  String _minimumReusableLengthSettingKey(String? itemKey) {
    final normalized = itemKey?.trim().toLowerCase() ?? '';
    return normalized.isEmpty
        ? 'minimum_reusable_length_mm'
        : 'minimum_reusable_length_mm:$normalized';
  }

  Future<double?> readMinimumReusableLengthMm({String? itemKey}) =>
      _readInventorySettingNumber(_minimumReusableLengthSettingKey(itemKey));

  Future<Map<String, double>> readMinimumReusableLengthsMm() async {
    final myDb = await db;
    if (myDb == null) return {};
    await _ensureRemnantInventorySchema(myDb);
    final rows = await myDb.query(
      'InventorySettings',
      columns: const ['setting_key', 'numeric_value'],
      where: "setting_key LIKE 'minimum_reusable_length_mm:%'",
    );
    final result = <String, double>{};
    for (final row in rows) {
      final key = row['setting_key']?.toString();
      final value = SqlDatabase._readStoredNumber(row['numeric_value']);
      if (key != null && key.isNotEmpty && value != null && value > 0) {
        result[key.substring('minimum_reusable_length_mm:'.length)] = value;
      }
    }
    return result;
  }

  Future<void> saveMinimumReusableLengthMm(
    double lengthMm, {
    String? itemKey,
  }) => _saveInventorySettingNumber(
    _minimumReusableLengthSettingKey(itemKey),
    lengthMm,
  );

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
    await _ensureOrderInventoryIssueSchema(myDb);
    final createdRemnants = <Map<String, dynamic>>[];
    var scrapRows = 0;
    var alreadySaved = false;
    var issueAlreadyApplied = false;

    await myDb.transaction((txn) async {
      final issueSession = await txn.query(
        'OrderInventoryIssueSessions',
        columns: const ['id'],
        where: 'order_id = ?',
        whereArgs: [orderId],
        limit: 1,
      );
      issueAlreadyApplied = issueSession.isNotEmpty;
      final existing = await txn.query(
        'OrderCuttingSessions',
        columns: const ['id', 'plan_signature'],
        where: 'order_id = ?',
        whereArgs: [orderId],
        limit: 1,
      );
      if (existing.isNotEmpty) {
        alreadySaved = true;
        if (issueAlreadyApplied) {
          await txn.update(
            'MaterialRemnants',
            {
              'status': 'available',
              'updated_at': DateTime.now().toUtc().toIso8601String(),
            },
            where: 'source_order_id = ? AND status = ?',
            whereArgs: [orderId, 'pending'],
          );
          await txn.update(
            'MaterialScrap',
            {
              'status': 'posted',
              'updated_at': DateTime.now().toUtc().toIso8601String(),
            },
            where: 'source_order_id = ? AND status = ?',
            whereArgs: [orderId, 'pending'],
          );
        }
        return;
      }

      final timestamp = DateTime.now().toUtc().toIso8601String();
      await txn.insert(
        'OrderCuttingSessions',
        SqlDatabase._withDistributedId({
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
        final remainderMm = SqlDatabase._readStoredNumber(bar['remainder_mm']) ?? 0;
        final kerfLossMm = SqlDatabase._readStoredNumber(bar['kerf_loss_mm']) ?? 0;
        final barMinimum =
            SqlDatabase._readStoredNumber(bar['minimum_reusable_length_mm']) ??
            minimumReusableLengthMm;
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
          final reusable = remainderMm + 0.01 >= barMinimum;
          final id = SqlDatabase._nextDistributedId();
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
              // A cutting plan is not inventory.  The remainder becomes
              // available only after the order issue has consumed the bar.
              'status': issueAlreadyApplied ? 'available' : 'pending',
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
              'status': issueAlreadyApplied ? 'posted' : 'pending',
            });
            scrapRows++;
          }
        }

        if (kerfLossMm > 0.5) {
          final id = SqlDatabase._nextDistributedId();
          await txn.insert('MaterialScrap', {
            'id': id,
            'ticket_code': _materialTicketCode('KERF', orderId, barIndex, id),
            ...common,
            'length_mm': kerfLossMm,
            'scrap_kind': 'saw_kerf',
            'status': issueAlreadyApplied ? 'posted' : 'pending',
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
    int? forOrderId,
  }) async {
    final myDb = await db;
    if (myDb == null) return [];
    await _ensureRemnantInventorySchema(myDb);
    // Remnants reserved for [forOrderId] remain part of that order's plan.
    final where = StringBuffer(
      'r.item_id = ? AND r.item_type = ? '
      "AND (r.status = 'available' OR "
      "(r.status = 'reserved' AND r.reserved_order_id = ?)) "
      'AND (r.color_id = ? OR (r.color_id IS NULL AND ? IS NULL))',
    );
    final args = <Object?>[itemId, itemType, forOrderId, colorId, colorId];
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

  /// Marks a physical remainder as waste without deleting its audit trail.
  /// The original ticket remains traceable in MaterialScrap.
  Future<Map<String, dynamic>> markMaterialRemnantAsScrap({
    required int remnantId,
    String? note,
  }) async {
    final myDb = await db;
    if (myDb == null) return const {'marked': false};
    await _ensureRemnantInventorySchema(myDb);
    var marked = false;
    await myDb.transaction((txn) async {
      final rows = await txn.query(
        'MaterialRemnants',
        where: 'id = ? AND status = ?',
        whereArgs: [remnantId, 'available'],
        limit: 1,
      );
      if (rows.isEmpty) return;
      final row = rows.first;
      final timestamp = DateTime.now().toUtc().toIso8601String();
      await txn.insert('MaterialScrap', {
        'id': SqlDatabase._nextDistributedId(),
        'ticket_code': row['ticket_code'],
        'item_id': row['item_id'],
        'item_type': row['item_type'],
        'series_id': row['series_id'],
        'color_id': row['color_id'],
        'length_mm': row['length_mm'],
        'scrap_kind': 'manual_waste',
        'status': 'posted',
        'source_order_id': row['source_order_id'],
        'source_bar_index': row['source_bar_index'],
        'location_id': row['location_id'],
        'rack_code': row['rack_code'],
        'shelf_code': row['shelf_code'],
        'bin_code': row['bin_code'],
        'note': note?.trim(),
        'created_at': timestamp,
        'updated_at': timestamp,
      });
      await txn.update(
        'MaterialRemnants',
        {'status': 'scrapped', 'note': note?.trim(), 'updated_at': timestamp},
        where: 'id = ? AND status = ?',
        whereArgs: [remnantId, 'available'],
      );
      marked = true;
    });
    if (marked) CloudSyncService().notifyChange();
    return {'marked': marked};
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
             COALESCE(s.code, '') AS item_code,
             COALESCE(s.image_path, sc.image_path, a.image_path,
                      j.image_path, g.image_path, '') AS item_image_path
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

  Future<int> insertStandardSheet(Map<String, dynamic> row) async {
    final myDb = await db;
    if (myDb == null) return -1;
    final now = DateTime.now().toIso8601String();
    final data = Map<String, dynamic>.from(row);
    data['created_at'] = now;
    data['updated_at'] = now;
    final id = await myDb.insert('StandardSheets', data);
    CloudSyncService().notifyChange();
    return id;
  }

  Future<int> updateStandardSheet(int id, Map<String, dynamic> row) async {
    final myDb = await db;
    if (myDb == null) return 0;
    final data = Map<String, dynamic>.from(row);
    data['updated_at'] = DateTime.now().toIso8601String();
    final count = await myDb.update(
      'StandardSheets',
      data,
      where: 'id = ?',
      whereArgs: [id],
    );
    if (count > 0) CloudSyncService().notifyChange();
    return count;
  }

  Future<int> deleteStandardSheet(int id) async {
    return runUserDeletion<int>('deleteStandardSheet', () async {
      final myDb = await db;
      if (myDb == null) return 0;
      final count = await myDb.delete(
        'StandardSheets',
        where: 'id = ?',
        whereArgs: [id],
      );
      if (count > 0) CloudSyncService().notifyChange();
      return count;
    });
  }

  Future<List<Map<String, dynamic>>> readStandardSheets({
    String? materialType,
  }) async {
    final myDb = await db;
    if (myDb == null) return [];
    if (materialType != null && materialType.isNotEmpty) {
      return myDb.query(
        'StandardSheets',
        where: 'material_type = ?',
        whereArgs: [materialType],
        orderBy: 'length_mm DESC, width_mm DESC',
      );
    }
    return myDb.query(
      'StandardSheets',
      orderBy: 'material_type ASC, length_mm DESC, width_mm DESC',
    );
  }

  Future<List<Map<String, dynamic>>> readAvailableSheetRemnants({
    String? materialType,
    int? colorId,
  }) async {
    final myDb = await db;
    if (myDb == null) return [];
    await _ensureRemnantInventorySchema(myDb);
    final where = StringBuffer("r.status = 'available' AND r.width_mm > 0");
    final args = <Object?>[];
    if (materialType != null && materialType.isNotEmpty) {
      where.write(' AND r.material_type = ?');
      args.add(materialType);
    }
    if (colorId != null) {
      where.write(' AND (r.color_id = ? OR r.color_id IS NULL)');
      args.add(colorId);
    }
    return myDb.rawQuery('''
      SELECT r.*, l.name AS location_name, c.name AS color_name,
             COALESCE(s.name, sc.name, a.name, j.name, g.name, r.item_type) AS item_name
      FROM MaterialRemnants r
      LEFT JOIN Locations l ON l.id = r.location_id
      LEFT JOIN Colors c ON c.id = r.color_id
      LEFT JOIN Sections s ON r.item_type = 'Section' AND s.id = r.item_id
      LEFT JOIN ShutterComponents sc ON r.item_type = 'ShutterComponent' AND sc.id = r.item_id
      LEFT JOIN Accessories a ON r.item_type = 'Accessory' AND a.id = r.item_id
      LEFT JOIN Joints j ON r.item_type = 'Joints' AND j.id = r.item_id
      LEFT JOIN Glass g ON r.item_type = 'Glass' AND g.id = r.item_id
      WHERE $where
      ORDER BY r.width_mm * r.length_mm DESC, r.created_at ASC
    ''', args);
  }

  Future<Map<String, dynamic>> applyOrderInventoryIssue({
    required int orderId,
    required List<int> remnantIds,
    required List<Map<String, dynamic>> stockDeductions,
    String? customerName,
    bool completeIssue = true,
  }) async {
    final myDb = await db;
    if (myDb == null) return const {'applied': false};
    await _ensureRemnantInventorySchema(myDb);
    await _ensureOrderInventoryIssueSchema(myDb);
    await _ensureOrderStockReservationInfrastructure(myDb);
    final actor = await _currentStockActor();
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
        if (completeIssue) {
          await txn.update(
            'MaterialRemnants',
            {
              'status': 'available',
              'updated_at': DateTime.now().toUtc().toIso8601String(),
            },
            where: 'source_order_id = ? AND status = ?',
            whereArgs: [orderId, 'pending'],
          );
          await txn.update(
            'MaterialScrap',
            {
              'status': 'posted',
              'updated_at': DateTime.now().toUtc().toIso8601String(),
            },
            where: 'source_order_id = ? AND status = ?',
            whereArgs: [orderId, 'pending'],
          );
        }
        return;
      }

      final timestamp = DateTime.now().toUtc().toIso8601String();

      // Validate the whole issue before changing anything.  Clamping a
      // negative result to zero hides a shortage and corrupts stock totals.
      final remnantRows = <Map<String, Object?>>[];
      for (final id in uniqueRemnantIds) {
        // A remnant this order reserved is still usable by this order.
        final rows = await txn.query(
          'MaterialRemnants',
          where:
              "id = ? AND (status = 'available' OR "
              "(status = 'reserved' AND reserved_order_id = ?))",
          whereArgs: [id, orderId],
          limit: 1,
        );
        if (rows.isEmpty) {
          throw StateError('الفضلة رقم $id غير متاحة أو سبق صرفها.');
        }
        remnantRows.add(Map<String, Object?>.from(rows.first));
      }

      final validatedDeductions = <Map<String, dynamic>>[];
      final projectedDeductions = <String, double>{};
      for (final row in stockDeductions) {
        final itemId = (row['item_id'] as num?)?.toInt();
        final itemType = row['item_type']?.toString().trim();
        final locationId = (row['location_id'] as num?)?.toInt();
        final quantity = SqlDatabase._readStoredNumber(row['quantity']) ?? 0;
        if (itemId == null ||
            itemType == null ||
            itemType.isEmpty ||
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
        final current = stockRows.isEmpty
            ? 0.0
            : (SqlDatabase._readStoredNumber(stockRows.first['quantity']) ?? 0);
        final balanceKey = '$itemId|$itemType|${colorId ?? ''}|$locationId';
        final alreadyProjected = projectedDeductions[balanceKey] ?? 0;
        if (stockRows.isEmpty ||
            current + 0.000001 < alreadyProjected + quantity) {
          throw StateError(
            'المخزون غير كافٍ للصنف $itemId ($itemType): المطلوب $quantity والمتاح $current.',
          );
        }
        await _ensureUnreservedStock(
          txn,
          itemId: itemId,
          itemType: itemType,
          colorId: colorId,
          locationId: locationId,
          quantity: alreadyProjected + quantity,
          currentQuantity: current,
          excludeOrderId: orderId,
        );
        projectedDeductions[balanceKey] = alreadyProjected + quantity;
        validatedDeductions.add({
          ...row,
          'item_id': itemId,
          'item_type': itemType,
          'location_id': locationId,
          'color_id': colorId,
          '_where': where,
          '_whereArgs': whereArgs,
        });
      }

      await txn.insert(
        'OrderInventoryIssueSessions',
        SqlDatabase._withDistributedId({
          'order_id': orderId,
          'created_at': timestamp,
          'updated_at': timestamp,
        }),
      );

      final order = await txn.query(
        'Commandes',
        where: 'id = ?',
        whereArgs: [orderId],
        limit: 1,
      );
      final orderCode = order.isEmpty
          ? 0
          : (order.first['order_code'] as num?)?.toInt() ?? 0;
      for (final row in remnantRows) {
        final id = (row['id'] as num).toInt();
        consumedRemnants += await txn.update(
          'MaterialRemnants',
          {
            'status': 'consumed',
            'consumed_order_id': orderId,
            'consumed_at': timestamp,
            'updated_at': timestamp,
          },
          where:
              "id = ? AND (status = 'available' OR "
              "(status = 'reserved' AND reserved_order_id = ?))",
          whereArgs: [id, orderId],
        );
        // Remnants are tracked in MaterialRemnants, not CurrentStock, so
        // this movement records the issue without changing a balance.
        await txn.insert(
          'InventoryTransactions',
          SqlDatabase._withDistributedId({
            'item_id': row['item_id'],
            'item_type': row['item_type'],
            'color_id': row['color_id'],
            'location_id': row['location_id'],
            'quantity': -((SqlDatabase._readStoredNumber(row['length_mm']) ?? 0) / 1000),
            'unit': 'm',
            'transaction_type': 'order_issue_remnant',
            'movement_type': SqlDatabase.movementRemnant,
            'from_location_id': row['location_id'],
            'reference_id': orderId,
            'document_type': 'order',
            'document_id': orderId,
            'document_code': orderCode > 0 ? '$orderCode' : '$orderId',
            'order_id': orderId,
            'client_id': order.isEmpty ? null : order.first['client_id'],
            'performed_by': actor.name,
            'performed_by_uid': actor.uid,
            'note':
                'صرف فضلة ${row['ticket_code'] ?? ''} للطلبية #$orderId${customerName == null || customerName.trim().isEmpty ? '' : ' - ${customerName.trim()}'}',
            'occurred_at': timestamp,
            'created_at': timestamp,
          }),
        );
      }

      for (final row in validatedDeductions) {
        await _postStockMovement(
          txn,
          itemId: row['item_id'] as int,
          itemType: row['item_type'] as String,
          colorId: row['color_id'] as int?,
          locationId: row['location_id'] as int,
          quantity: -(SqlDatabase._readStoredNumber(row['quantity']) ?? 0),
          transactionType: 'order_issue',
          movementType: SqlDatabase.movementProductionIssue,
          actor: actor,
          timestamp: timestamp,
          documentType: 'order',
          documentId: orderId,
          workOrderId: (row['work_order_id'] as num?)?.toInt(),
          reservationOrderId: orderId,
          note:
              'صرف تلقائي للطلبية #$orderId${customerName == null || customerName.trim().isEmpty ? '' : ' - ${customerName.trim()}'}',
        );
        deductedRows++;
      }

      // The issue replaces the order's hold: the stock it reserved has just
      // left the warehouse, and reserved remnants it did not use are free.
      await txn.update(
        'StockReservations',
        {'status': 'consumed', 'updated_at': timestamp},
        where: 'order_id = ? AND status = ?',
        whereArgs: [orderId, 'active'],
      );
      await _releaseOrderStockHold(txn, orderId, timestamp);
      await txn.update(
        'Commandes',
        {'is_stock_reserved': 0, 'stock_reserved_at': null},
        where: 'id = ?',
        whereArgs: [orderId],
      );

      if (completeIssue) {
        await txn.update(
          'MaterialRemnants',
          {'status': 'available', 'updated_at': timestamp},
          where: 'source_order_id = ? AND status = ?',
          whereArgs: [orderId, 'pending'],
        );
        await txn.update(
          'MaterialScrap',
          {'status': 'posted', 'updated_at': timestamp},
          where: 'source_order_id = ? AND status = ?',
          whereArgs: [orderId, 'pending'],
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

  /// Stock balances of one item that can still be used. `quantity` is what is
  /// left after other orders' active reservations ([forOrderId]'s own hold
  /// stays usable); `physical_quantity` and `reserved_quantity` give the
  /// breakdown.
  Future<List<Map<String, dynamic>>> readStockAvailability({
    required int itemId,
    required String itemType,
    int? colorId,
    int? forOrderId,
  }) async {
    final myDb = await db;
    if (myDb == null) return [];
    await _ensureRemnantInventorySchema(myDb);
    final rows = await myDb.rawQuery(
      '''
      SELECT cs.*, l.name AS location_name,
             COALESCE((
               SELECT SUM(r.quantity)
               FROM StockReservations r
               WHERE r.status = 'active'
                 AND r.item_id = cs.item_id
                 AND r.item_type = cs.item_type
                 AND (r.color_id = cs.color_id
                      OR (r.color_id IS NULL AND cs.color_id IS NULL))
                 AND r.location_id = cs.location_id
                 AND (? IS NULL OR r.order_id != ?)
             ), 0) AS reserved_quantity
      FROM CurrentStock cs
      LEFT JOIN Locations l ON l.id = cs.location_id
      WHERE cs.item_id = ? AND cs.item_type = ?
        AND (cs.color_id = ? OR (cs.color_id IS NULL AND ? IS NULL))
        AND cs.quantity > 0
      ''',
      [forOrderId, forOrderId, itemId, itemType, colorId, colorId],
    );
    final available = <Map<String, dynamic>>[];
    for (final row in rows) {
      final physical = SqlDatabase._readStoredNumber(row['quantity']) ?? 0;
      final reserved = SqlDatabase._readStoredNumber(row['reserved_quantity']) ?? 0;
      final free = physical - reserved;
      if (free <= 0.000001) continue;
      available.add({
        ...row,
        'physical_quantity': physical,
        'reserved_quantity': reserved,
        'quantity': free,
      });
    }
    available.sort((a, b) {
      final byQuantity = (b['quantity'] as double).compareTo(
        a['quantity'] as double,
      );
      if (byQuantity != 0) return byQuantity;
      return ((a['location_id'] as num?)?.toInt() ?? 0).compareTo(
        (b['location_id'] as num?)?.toInt() ?? 0,
      );
    });
    return available;
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

  Future<void> confirmMaterialRemnant({
    required int remnantId,
    required double actualLengthMm,
    String? rackCode,
    String? shelfCode,
    String? binCode,
  }) async {
    final myDb = await db;
    if (myDb == null) return;
    await _ensureRemnantInventorySchema(myDb);
    final timestamp = DateTime.now().toUtc().toIso8601String();
    await myDb.update(
      'MaterialRemnants',
      {
        'length_mm': actualLengthMm,
        'status': 'available',
        'rack_code': rackCode?.trim(),
        'shelf_code': shelfCode?.trim(),
        'bin_code': binCode?.trim(),
        'updated_at': timestamp,
      },
      where: 'id = ?',
      whereArgs: [remnantId],
    );
    CloudSyncService().notifyChange();
  }

  Future<int> insertMaterialRemnant(Map<String, dynamic> data) async {
    final myDb = await db;
    if (myDb == null) return 0;
    await _ensureRemnantInventorySchema(myDb);
    final now = DateTime.now().toUtc().toIso8601String();
    final row = Map<String, dynamic>.from(data);
    row.putIfAbsent('id', () => SqlDatabase._nextDistributedId());
    row.putIfAbsent(
      'ticket_code',
      () => 'RM-${DateTime.now().millisecondsSinceEpoch % 100000}',
    );
    row.putIfAbsent('status', () => 'available');
    row.putIfAbsent('created_at', () => now);
    row.putIfAbsent('updated_at', () => now);
    final id = await myDb.insert('MaterialRemnants', row);
    CloudSyncService().notifyChange();
    return id;
  }

  Future<void> scrapMaterialRemnant({
    required int remnantId,
    String? reason,
  }) async {
    final myDb = await db;
    if (myDb == null) return;
    await _ensureRemnantInventorySchema(myDb);
    final timestamp = DateTime.now().toUtc().toIso8601String();
    final rows = await myDb.query(
      'MaterialRemnants',
      where: 'id = ?',
      whereArgs: [remnantId],
      limit: 1,
    );
    if (rows.isEmpty) return;
    final r = rows.first;
    await myDb.transaction((txn) async {
      await txn.update(
        'MaterialRemnants',
        {
          'status': 'scrapped',
          'note': reason ?? 'خطأ في القص تم تحويله لهالك',
          'updated_at': timestamp,
        },
        where: 'id = ?',
        whereArgs: [remnantId],
      );
      final scrapId = SqlDatabase._nextDistributedId();
      await txn.insert('MaterialScrap', {
        'id': scrapId,
        'ticket_code': 'SCR-ERR-${r['id']}',
        'item_id': r['item_id'],
        'item_type': r['item_type'],
        'series_id': r['series_id'],
        'color_id': r['color_id'],
        'length_mm': r['length_mm'],
        'scrap_kind': 'cutting_error_scrap',
        'status': 'posted',
        'source_order_id': r['source_order_id'],
        'source_bar_index': r['source_bar_index'],
        'location_id': r['location_id'],
        'note': reason ?? 'خطأ عامل أثناء القص',
        'created_at': timestamp,
        'updated_at': timestamp,
      });
    });
    CloudSyncService().notifyChange();
  }

  Future<int> registerCuttingErrorExtraBar({
    required int orderId,
    required int sectionId,
    required int locationId,
    int? colorId,
    int? seriesId,
    double? newRemnantLengthMm,
    String? rackCode,
    String? shelfCode,
    String? binCode,
    String? note,
  }) async {
    final myDb = await db;
    if (myDb == null) return 0;
    await _ensureRemnantInventorySchema(myDb);
    final timestamp = DateTime.now().toUtc().toIso8601String();
    final actor = await _currentStockActor();
    var createdRemnantId = 0;

    await myDb.transaction((txn) async {
      // 1. تسجيل سحب بارة إضافية بسبب الخطأ: a bar leaves the stock.
      await _postStockMovement(
        txn,
        itemId: sectionId,
        itemType: 'Section',
        colorId: colorId,
        locationId: locationId,
        quantity: -1.0,
        transactionType: 'cutting_error_extra_bar',
        movementType: SqlDatabase.movementDamage,
        actor: actor,
        timestamp: timestamp,
        documentType: 'order',
        documentId: orderId,
        reservationOrderId: orderId,
        reason: 'خطأ في القص',
        note: note ?? 'سحب بارة إضافية لتعويض خطأ في القص',
      );

      // 2. إذا كانت هناك فضلة متبقية من البارة الإضافية، نسجلها كفضلة متاحة
      if (newRemnantLengthMm != null && newRemnantLengthMm > 50) {
        createdRemnantId = SqlDatabase._nextDistributedId();
        final ticket = 'REM-ERR-$orderId-$createdRemnantId';
        await txn.insert('MaterialRemnants', {
          'id': createdRemnantId,
          'ticket_code': ticket,
          'item_id': sectionId,
          'item_type': 'Section',
          'series_id': seriesId,
          'color_id': colorId,
          'length_mm': newRemnantLengthMm,
          'source_order_id': orderId,
          'location_id': locationId,
          'rack_code': rackCode?.trim(),
          'shelf_code': shelfCode?.trim(),
          'bin_code': binCode?.trim(),
          'status': 'available',
          'note': 'فضلة من بارة إضافية (تعويض خطأ قص)',
          'created_at': timestamp,
          'updated_at': timestamp,
        });
      }
    });

    CloudSyncService().notifyChange();
    return createdRemnantId;
  }

  // ==================== INVENTORY MANAGEMENT ====================
  Future<List<Map<String, dynamic>>> readLocations({bool? isWorkshop}) async {
    final myDb = await db;
    if (myDb == null) return [];
    const principalName = 'المستودع الرئيسي';
    const principalType = 'مستودع رئيسي';
    List<Map<String, dynamic>> locations = [];
    try {
      locations = await myDb.query(
        'Locations',
        where: 'is_active IS NULL OR is_active != 0',
        orderBy: 'id ASC',
      );
    } catch (e) {
      // Table might not exist if the upgrade script failed or was skipped
      await myDb.execute('''
        CREATE TABLE IF NOT EXISTS Locations (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          type TEXT NOT NULL,
          is_active INTEGER NOT NULL DEFAULT 1,
          is_workshop INTEGER NOT NULL DEFAULT 0,
          allow_direct_issue INTEGER NOT NULL DEFAULT 1,
          created_at TEXT NOT NULL DEFAULT (datetime('now'))
        )
      ''');
    }

    try {
      await myDb.execute(
        'ALTER TABLE Locations ADD COLUMN is_workshop INTEGER NOT NULL DEFAULT 0;',
      );
    } catch (_) {}
    try {
      await myDb.execute(
        'ALTER TABLE Locations ADD COLUMN allow_direct_issue INTEGER NOT NULL DEFAULT 1;',
      );
    } catch (_) {}

    if (locations.isEmpty) {
      await myDb.insert(
        'Locations',
        SqlDatabase._withDistributedId({
          'name': 'المستودع الرئيسي',
          'type': 'مستودع رئيسي',
          'is_active': 1,
          'is_workshop': 1,
          'allow_direct_issue': 1,
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
          {'name': 'المستودع الرئيسي', 'type': 'مستودع رئيسي'},
          where: 'id = ?',
          whereArgs: [location['id']],
        );
      }
    }
    // The previous repair code itself wrote mojibake. Normalize those legacy
    // values to real Unicode Arabic before returning the list.
    var repairedLegacyLocation = false;
    for (final location in locations) {
      final name = location['name']?.toString() ?? '';
      final type = location['type']?.toString() ?? '';
      final hasBrokenEncoding =
          name.contains('Ø') ||
          name.contains('Ù') ||
          name.contains('Ã') ||
          name.contains('Â') ||
          name.contains('â') ||
          type.contains('Ø') ||
          type.contains('Ù') ||
          type.contains('Ã') ||
          type.contains('Â') ||
          type.contains('â');
      if (hasBrokenEncoding) {
        await myDb.update(
          'Locations',
          {'name': principalName, 'type': principalType},
          where: 'id = ?',
          whereArgs: [location['id']],
        );
        repairedLegacyLocation = true;
      }
    }

    if (repairedLegacyLocation) {
      CloudSyncService().notifyChange();
    }

    locations = await myDb.query(
      'Locations',
      where: 'is_active IS NULL OR is_active != 0',
      orderBy: 'id ASC',
    );

    // Old synchronized databases can contain the same warehouse many times.
    // Keep only the first row in the UI while preserving the stored records.
    final seenNames = <String>{};
    return locations.where((location) {
      final name = (location['name']?.toString() ?? '').trim();
      if (name.isEmpty || !seenNames.add(name.toLowerCase())) return false;
      if (isWorkshop != null) {
        final locIsWorkshop = (location['is_workshop'] as num?)?.toInt() ?? 0;
        if (isWorkshop) {
          return locIsWorkshop == 1;
        } else {
          return locIsWorkshop == 0;
        }
      }
      return true;
    }).toList();
  }

  Future<List<Map<String, dynamic>>> readWorkshopLocations() =>
      readLocations(isWorkshop: true);

  Future<List<Map<String, dynamic>>> readStoreLocations() async {
    final list = await readLocations(isWorkshop: false);
    if (list.isNotEmpty) return list;
    // Auto-create a default store warehouse if none exists
    await insertLocation(
      'المستودع الرئيسي للمحل',
      type: 'مستودع محل المواد',
      isWorkshop: false,
    );
    return readLocations(isWorkshop: false);
  }

  /// Adds a warehouse without imposing a fixed number of warehouses.
  /// Existing names are returned instead of creating another duplicate row.
  Future<int> insertLocation(
    String name, {
    String type = 'مستودع',
    bool isWorkshop = false,
    bool allowDirectIssue = true,
  }) async {
    final myDb = await db;
    if (myDb == null) return 0;

    final cleanName = name.trim();
    if (cleanName.isEmpty) return 0;
    await readLocations();

    final existing = await myDb.query(
      'Locations',
      columns: const ['id'],
      where:
          'LOWER(TRIM(name)) = LOWER(?) AND (is_active IS NULL OR is_active != 0)',
      whereArgs: [cleanName],
      orderBy: 'id ASC',
      limit: 1,
    );
    if (existing.isNotEmpty) {
      return (existing.first['id'] as num).toInt();
    }

    final id = await myDb.insert(
      'Locations',
      SqlDatabase._withDistributedId({
        'name': cleanName,
        'type': type.trim().isEmpty ? 'مستودع' : type.trim(),
        'is_active': 1,
        'is_workshop': isWorkshop ? 1 : 0,
        'allow_direct_issue': allowDirectIssue ? 1 : 0,
      }),
    );
    CloudSyncService().notifyChange();
    return id;
  }

  Future<void> updateLocationSettings(
    int id, {
    required bool isWorkshop,
    required bool allowDirectIssue,
  }) async {
    final myDb = await db;
    if (myDb == null) return;
    await myDb.update(
      'Locations',
      {
        'is_workshop': isWorkshop ? 1 : 0,
        'allow_direct_issue': allowDirectIssue ? 1 : 0,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    CloudSyncService().notifyChange();
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
        SqlDatabase._withDistributedId({
          'item_type': itemType,
          'item_id': itemId,
          'color_id': colorId,
          'location_id': locationId,
          'quantity': 0.0,
          'min_qty': minQty,
          'low_stock_alert_enabled': alertEnabled ? 1 : 0,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        }),
      );
    } else {
      res = await myDb.update(
        'CurrentStock',
        {
          'min_qty': minQty,
          'low_stock_alert_enabled': alertEnabled ? 1 : 0,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [stock.first['id']],
      );
    }
    CloudSyncService().notifyChange();
    return res;
  }

  /// The account a stock movement is attributed to.
  Future<({String? uid, String name})> _currentStockActor() async =>
      (uid: SqlDatabase.currentEditorUid(), name: await _currentOrderEditor());

  /// Posts one movement on one CurrentStock balance inside [txn]: checks the
  /// balance (and, for an outgoing movement, other orders' reservations),
  /// updates CurrentStock and writes the InventoryTransactions row with the
  /// balance before and after. Returns the movement id.
  ///
  /// [quantity] is signed: positive enters [locationId], negative leaves it.
  /// The supplier, client, order and code are read from the document when
  /// not given, so the movement keeps ids and the card shows current names.
  /// Callers must have run [_ensureRemnantInventorySchema].
  Future<int> _postStockMovement(
    DatabaseExecutor txn, {
    required int itemId,
    required String itemType,
    int? colorId,
    required int locationId,
    required double quantity,
    required String transactionType,
    required ({String? uid, String name}) actor,
    String? movementType,
    String? timestamp,
    String? unit,
    double? unitCost,
    int? fromLocationId,
    int? toLocationId,
    String? transferId,
    String? documentType,
    int? documentId,
    String? documentCode,
    String? linkedDocumentType,
    int? linkedDocumentId,
    int? supplierId,
    int? clientId,
    int? orderId,
    int? workOrderId,
    int? reversesTransactionId,
    String? reason,
    String? note,
    int? referenceId,
    int? reservationOrderId,
    bool checkReservations = true,
    String? label,
  }) async {
    final now = timestamp ?? DateTime.now().toUtc().toIso8601String();
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
    final before = stockRows.isEmpty
        ? 0.0
        : (SqlDatabase._readStoredNumber(stockRows.first['quantity']) ?? 0);
    final name = label ?? '$itemId ($itemType)';
    if (quantity < 0) {
      if (stockRows.isEmpty || before + 0.000001 < -quantity) {
        throw StateError(
          'الرصيد غير كافٍ للصنف $name: المتوفر $before والمطلوب ${-quantity}.',
        );
      }
      if (checkReservations) {
        await _ensureUnreservedStock(
          txn,
          itemId: itemId,
          itemType: itemType,
          colorId: colorId,
          locationId: locationId,
          quantity: -quantity,
          currentQuantity: before,
          excludeOrderId: reservationOrderId,
          label: label,
        );
      }
    }
    final after = before + quantity;
    if (stockRows.isEmpty) {
      await txn.insert(
        'CurrentStock',
        SqlDatabase._withDistributedId({
          'item_id': itemId,
          'item_type': itemType,
          'color_id': colorId,
          'location_id': locationId,
          'quantity': after,
          'updated_at': now,
        }),
      );
    } else {
      await txn.update(
        'CurrentStock',
        {'quantity': after, 'updated_at': now},
        where: where,
        whereArgs: whereArgs,
      );
    }

    // Fill the parties from the document itself.
    var code = documentCode;
    var supplier = supplierId;
    var client = clientId;
    var order = orderId;
    Future<Map<String, Object?>?> readDocument(String table) async {
      if (documentId == null) return null;
      try {
        final rows = await txn.query(
          table,
          where: 'id = ?',
          whereArgs: [documentId],
          limit: 1,
        );
        return rows.isEmpty ? null : rows.first;
      } catch (_) {
        return null;
      }
    }

    switch (documentType) {
      case 'purchase':
        final row = await readDocument('Achats');
        supplier ??= (row?['supplier_id'] as num?)?.toInt();
        code ??= row?['invoice_number']?.toString();
      case 'sale':
        final row = await readDocument('MaterialSales');
        client ??= (row?['client_id'] as num?)?.toInt();
        code ??= row?['sale_code']?.toString();
      case 'order':
        final row = await readDocument('Commandes');
        order ??= documentId;
        client ??= (row?['client_id'] as num?)?.toInt();
        final orderCode = (row?['order_code'] as num?)?.toInt() ?? 0;
        code ??= orderCode > 0 ? '$orderCode' : '$documentId';
    }

    return txn.insert(
      'InventoryTransactions',
      SqlDatabase._withDistributedId({
        'item_id': itemId,
        'item_type': itemType,
        'color_id': colorId,
        'location_id': locationId,
        'transaction_type': transactionType,
        'movement_type':
            movementType ?? SqlDatabase.movementTypeForTransaction(transactionType),
        'quantity': quantity,
        'unit': unit,
        'balance_before': before,
        'balance_after': after,
        'unit_cost': unitCost,
        'total_cost': unitCost == null ? null : unitCost * quantity.abs(),
        'from_location_id': quantity < 0 ? locationId : fromLocationId,
        'to_location_id': quantity > 0 ? locationId : toLocationId,
        'transfer_id': transferId,
        'reference_id': referenceId ?? documentId,
        'document_type': documentType,
        'document_id': documentId,
        'document_code': code,
        'linked_document_type': linkedDocumentType,
        'linked_document_id': linkedDocumentId,
        'supplier_id': supplier,
        'client_id': client,
        'order_id': order,
        'work_order_id': workOrderId,
        'reverses_transaction_id': reversesTransactionId,
        'reason': reason,
        'note': note,
        'performed_by': actor.name,
        'performed_by_uid': actor.uid,
        'occurred_at': now,
        'created_at': now,
      }),
    );
  }

  /// The latest movement written by a document for one balance, so a
  /// reversal can point at the movement it cancels.
  Future<int?> _originalMovementId(
    DatabaseExecutor txn, {
    required int referenceId,
    required String transactionType,
    required int itemId,
    required String itemType,
    int? colorId,
    required int locationId,
  }) async {
    final rows = await txn.query(
      'InventoryTransactions',
      columns: const ['id'],
      where:
          'reference_id = ? AND transaction_type = ? AND item_id = ? '
          'AND item_type = ? AND location_id = ? '
          'AND (color_id = ? OR (color_id IS NULL AND ? IS NULL))',
      whereArgs: [
        referenceId,
        transactionType,
        itemId,
        itemType,
        locationId,
        colorId,
        colorId,
      ],
      orderBy: 'created_at DESC',
      limit: 1,
    );
    return rows.isEmpty ? null : (rows.first['id'] as num?)?.toInt();
  }

  Future<void> updateInventory({
    required int itemId,
    required String itemType,
    int? colorId,
    required int locationId,
    required double quantityChange,
    required String transactionType,
    int? referenceId,
    double? unitPrice,
    String? note,
    String? reason,
  }) async {
    Database? myDb = await db;
    if (myDb == null) return;
    await _ensureRemnantInventorySchema(myDb);
    final actor = await _currentStockActor();
    await myDb.transaction(
      (txn) => _applyInventoryChange(
        txn,
        actor: actor,
        itemId: itemId,
        itemType: itemType,
        colorId: colorId,
        locationId: locationId,
        quantityChange: quantityChange,
        transactionType: transactionType,
        referenceId: referenceId,
        unitPrice: unitPrice,
        note: note,
        reason: reason,
      ),
    );
    CloudSyncService().notifyChange();
  }

  /// Receives every line of a purchase invoice into its warehouse and marks
  /// it [status] in one transaction, so an invoice is never half received.
  Future<void> receiveAchatStock(
    int achatId, {
    String status = 'Confirmed',
  }) async {
    final myDb = await db;
    if (myDb == null) return;
    await _ensureRemnantInventorySchema(myDb);
    final actor = await _currentStockActor();
    final editor = await _currentOrderEditor();
    await snapshotAchat(
      achatId,
      actionType: 'UPDATE',
      afterHeader: {'status': status},
    );
    await myDb.transaction((txn) async {
      final achats = await txn.query(
        'Achats',
        where: 'id = ?',
        whereArgs: [achatId],
        limit: 1,
      );
      if (achats.isEmpty) throw StateError('فاتورة الشراء غير موجودة.');
      final locationId = (achats.first['location_id'] as num?)?.toInt() ?? 1;
      final lines = await txn.query(
        'Achat_items',
        where: 'achat_id = ?',
        whereArgs: [achatId],
      );
      for (final line in lines) {
        final quantity = (line['quantity'] as num?)?.toDouble() ?? 0.0;
        final itemId = (line['item_id'] as num?)?.toInt() ?? 0;
        if (quantity <= 0 || itemId <= 0) continue;
        final unitPrice = (line['price'] as num?)?.toDouble() ?? 0.0;
        await _applyInventoryChange(
          txn,
          actor: actor,
          itemId: itemId,
          itemType: line['item_type']?.toString() ?? 'Other',
          colorId: (line['color_id'] as num?)?.toInt(),
          locationId: locationId,
          quantityChange: quantity,
          transactionType: 'Purchase',
          referenceId: achatId,
          unitPrice: unitPrice > 0 ? unitPrice : null,
        );
      }
      await txn.update(
        'Achats',
        {
          'status': status,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
          'updated_by': editor,
        },
        where: 'id = ?',
        whereArgs: [achatId],
      );
    });
    CloudSyncService().notifyChange();
  }

  /// Body of [updateInventory]: one movement plus, for a priced receipt,
  /// the weighted average cost of the catalogue item.
  Future<void> _applyInventoryChange(
    DatabaseExecutor txn, {
    required ({String? uid, String name}) actor,
    required int itemId,
    required String itemType,
    int? colorId,
    required int locationId,
    required double quantityChange,
    required String transactionType,
    int? referenceId,
    double? unitPrice,
    String? note,
    String? reason,
  }) async {
    final type = transactionType.toLowerCase();
    // Purchase screens pass the invoice id as the reference.
    final isPurchaseDocument =
        referenceId != null &&
        referenceId > 0 &&
        (type.startsWith('purchase') || type.contains('supplier'));
    // 1-2. Movement and balance, validated together.
    final isCostedPurchase =
        quantityChange > 0 && unitPrice != null && unitPrice > 0;
    // Stock of every location before this purchase: the average cost is a
    // single price per item and colour, not a per-location price.
    final stockBeforePurchase = isCostedPurchase
        ? await _totalStockQuantity(txn, itemId, itemType, colorId)
        : 0.0;

    await _postStockMovement(
      txn,
      itemId: itemId,
      itemType: itemType,
      colorId: colorId,
      locationId: locationId,
      quantity: quantityChange,
      transactionType: transactionType,
      actor: actor,
      unitCost: unitPrice,
      documentType: isPurchaseDocument ? 'purchase' : null,
      documentId: isPurchaseDocument ? referenceId : null,
      referenceId: referenceId,
      note: note,
      reason: reason,
    );

    // 3. Purchase price → cost price (weighted average cost, CMP).
    if (isCostedPurchase) {
      await _applyPurchaseCost(
        txn,
        itemId: itemId,
        itemType: itemType,
        colorId: colorId,
        quantity: quantityChange,
        unitPrice: unitPrice,
        stockBefore: stockBeforePurchase,
      );
    }
  }

  Future<double> _totalStockQuantity(
    DatabaseExecutor txn,
    int itemId,
    String itemType,
    int? colorId,
  ) async {
    final aliases = SqlDatabase._inventoryTypeAliases(itemType).toList();
    final marks = List.filled(aliases.length, '?').join(', ');
    final hasColor = colorId != null && colorId > 0;
    final rows = await txn.rawQuery(
      'SELECT COALESCE(SUM(quantity), 0) AS qty FROM CurrentStock '
      'WHERE item_id = ? AND item_type IN ($marks) AND '
      '${hasColor ? 'color_id = ?' : '(color_id IS NULL OR color_id = 0)'}',
      [itemId, ...aliases, if (hasColor) colorId],
    );
    final qty = (rows.first['qty'] as num?)?.toDouble() ?? 0.0;
    return qty > 0 ? qty : 0.0;
  }

  /// Weighted average cost (CMP). With no stock left, the new purchase price
  /// becomes the price directly; otherwise the old stock and the purchased
  /// quantity are averaged: (stock × old + qty × new) / (stock + qty).
  ///
  /// The price is written where the quantity & cost table reads it (colour
  /// price, else catalogue base price) and marked as a purchase price so a
  /// catalogue refresh or an administrator publication keeps it.
  Future<void> _applyPurchaseCost(
    DatabaseExecutor txn, {
    required int itemId,
    required String itemType,
    required int? colorId,
    required double quantity,
    required double unitPrice,
    required double stockBefore,
  }) async {
    final aliases = SqlDatabase._inventoryTypeAliases(itemType);
    final hasColor = colorId != null && colorId > 0;
    String baseTable;
    String baseColumn;
    String? colorTable;
    String? colorKeyColumn;
    if (aliases.contains('Sections')) {
      baseTable = 'Sections';
      baseColumn = 'price_dzd';
      colorTable = 'SectionColorPrices';
      colorKeyColumn = 'section_id';
    } else if (aliases.contains('Accessories')) {
      baseTable = 'Accessories';
      baseColumn = 'price';
      colorTable = 'AccessoryColorPrices';
      colorKeyColumn = 'accessory_id';
    } else if (aliases.contains('ShutterComponents')) {
      baseTable = 'ShutterComponents';
      baseColumn = 'price';
      colorTable = 'ShutterColorPrices';
      colorKeyColumn = 'shutter_component_id';
    } else if (aliases.contains('Joints')) {
      baseTable = 'Joints';
      baseColumn = 'price_per_meter';
    } else if (aliases.contains('Glass')) {
      baseTable = 'Glass';
      baseColumn = 'price_per_sqm';
    } else {
      return;
    }

    final baseColumns = await _tableColumns(txn, baseTable);
    var oldPrice = 0.0;
    if (baseColumns.contains(baseColumn)) {
      final baseRows = await txn.query(
        baseTable,
        columns: [baseColumn],
        where: 'id = ?',
        whereArgs: [itemId],
        limit: 1,
      );
      if (baseRows.isNotEmpty) {
        oldPrice = (baseRows.first[baseColumn] as num?)?.toDouble() ?? 0.0;
      }
    }
    final useColorTable =
        hasColor && colorTable != null && colorKeyColumn != null;
    if (useColorTable) {
      final colorRows = await txn.query(
        colorTable,
        columns: const ['price'],
        where: '$colorKeyColumn = ? AND color_id = ?',
        whereArgs: [itemId, colorId],
        limit: 1,
      );
      final colorPrice = colorRows.isEmpty
          ? 0.0
          : (colorRows.first['price'] as num?)?.toDouble() ?? 0.0;
      if (colorPrice > 0) oldPrice = colorPrice;
    }

    var averagePrice = unitPrice;
    if (stockBefore > 0 && oldPrice > 0) {
      averagePrice =
          (stockBefore * oldPrice + quantity * unitPrice) /
          (stockBefore + quantity);
    }
    averagePrice = (averagePrice * 100).roundToDouble() / 100;
    if (averagePrice <= 0) return;

    if (useColorTable) {
      final table = colorTable;
      final keyColumn = colorKeyColumn;
      final updated = await txn.update(
        table,
        {'price': averagePrice},
        where: '$keyColumn = ? AND color_id = ?',
        whereArgs: [itemId, colorId],
      );
      if (updated == 0) {
        await txn.insert(
          table,
          SqlDatabase._withDistributedId({
            keyColumn: itemId,
            'color_id': colorId,
            'price': averagePrice,
          }),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await recordWorkshopPrice(
        txn,
        table: table,
        rowKey: SqlDatabase.priceRowKey([itemId, colorId]),
        column: 'price',
        price: averagePrice,
        source: 'purchase',
      );
      return;
    }

    if (!baseColumns.contains(baseColumn)) return;
    await txn.update(
      baseTable,
      {baseColumn: averagePrice},
      where: 'id = ?',
      whereArgs: [itemId],
    );
    await recordWorkshopPrice(
      txn,
      table: baseTable,
      rowKey: SqlDatabase.priceRowKey([itemId]),
      column: baseColumn,
      price: averagePrice,
      source: 'purchase',
    );
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

    String canonicalStockType(Object? value) {
      final type = value?.toString().trim() ?? '';
      switch (type) {
        case 'Profile':
        case 'Sections':
          return 'Section';
        case 'Accessories':
          return 'Accessory';
        case 'Shutter Components':
        case 'ShutterComponents':
          return 'ShutterComponent';
        case 'Joint':
          return 'Joints';
        default:
          return type;
      }
    }

    Map<String, double> stockMap = {};
    Map<String, double> minQtyMap = {};
    Map<String, bool> alertMap = {};
    for (var row in stock) {
      String key =
          '${canonicalStockType(row['item_type'])}_${row['item_id']}_${row['color_id'] ?? 0}';
      // Legacy aliases (Profile/Sections, etc.) can collapse into the same
      // logical stock identity. Sum them instead of keeping whichever row
      // happened to be read last.
      stockMap[key] =
          (stockMap[key] ?? 0.0) + (row['quantity'] as num).toDouble();
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

    // 2. Sections — join Series + Profile to expose code / series / system name
    final sectionRows = await myDb.rawQuery('''
      SELECT sec.id, sec.name, sec.code,
             ser.name  AS series_name,
             p.name    AS profile_name
      FROM Sections sec
      LEFT JOIN Series  ser ON sec.series_id  = ser.id
      LEFT JOIN Profile p   ON ser.profile_id = p.id
    ''');
    final sectionColors = await myDb.query('SectionColorPrices');
    Map<int, List<int>> sectionColorMap = {};
    for (var row in sectionColors) {
      int sId = row['section_id'] as int;
      int cId = row['color_id'] as int;
      sectionColorMap.putIfAbsent(sId, () => []).add(cId);
    }
    for (var row in sectionRows) {
      int id = row['id'] as int;
      final rawName = row['name']?.toString() ?? '';
      final rawCode = row['code']?.toString() ?? '';
      final serName = row['series_name']?.toString() ?? '';
      final profName = row['profile_name']?.toString() ?? '';
      // Build disambiguating display name identical to readCurrentStock
      final codeStr = rawCode.isNotEmpty ? '[$rawCode] ' : '';
      final prefix = [profName, serName].where((s) => s.isNotEmpty).join(' - ');
      final displayName = prefix.isNotEmpty
          ? '$prefix - $codeStr$rawName'
          : '$codeStr$rawName';
      List<int> cIds = sectionColorMap[id] ?? [];
      if (cIds.isEmpty) cIds = [0]; // default no color

      for (int cId in cIds) {
        String key = 'Section_${id}_$cId';
        double qty = stockMap[key] ?? 0.0;
        String cName = cId == 0 ? '' : (colorMap[cId] ?? '');
        allItems.add({
          'item_type': 'Section',
          'item_id': id,
          'item_name': displayName,
          'item_code': rawCode,
          'series_name': serName,
          'profile_name': profName,
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
          final r = await myDb.rawQuery(
            '''
            SELECT sec.name, sec.code,
                   ser.name AS series_name,
                   p.name   AS profile_name
            FROM Sections sec
            LEFT JOIN Series  ser ON sec.series_id  = ser.id
            LEFT JOIN Profile p   ON ser.profile_id = p.id
            WHERE sec.id = ?
          ''',
            [id],
          );
          if (r.isNotEmpty) {
            final rawName = r.first['name']?.toString() ?? '';
            final rawCode = r.first['code']?.toString() ?? '';
            final serName = r.first['series_name']?.toString() ?? '';
            final profName = r.first['profile_name']?.toString() ?? '';
            final codeStr = rawCode.isNotEmpty ? '[$rawCode] ' : '';
            final prefix = [
              profName,
              serName,
            ].where((s) => s.isNotEmpty).join(' - ');
            itemName = prefix.isNotEmpty
                ? '$prefix - $codeStr$rawName'
                : '$codeStr$rawName';
          }
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

    // Names are read once per table instead of one or two queries per stock
    // row (thousands of queries for a large warehouse on every dashboard load).
    final itemTypes = {for (final row in stock) row['item_type']?.toString()};
    Future<Map<int, String>> namesOf(String table) async {
      final rows = await myDb.query(table, columns: const ['id', 'name']);
      return {
        for (final r in rows)
          if (r['id'] is int) r['id'] as int: r['name']?.toString() ?? '',
      };
      }

    bool hasAny(Set<String> types) => itemTypes.any(types.contains);
    const shutterTypes = {
      'Shutter Component',
          'ShutterComponents',
      'Lame',
      'Glissiere',
      'Axe',
      'Caisson',
    };
    final colorNames = stock.any((row) => row['color_id'] != null)
        ? await namesOf('Colors')
        : const <int, String>{};
    final profileNames = hasAny(const {'Profile'})
        ? await namesOf('Profile')
        : const <int, String>{};
    final accessoryNames = hasAny(const {'Accessory', 'Accessories'})
        ? await namesOf('Accessories')
        : const <int, String>{};
    final glassNames = hasAny(const {'Glass'})
        ? await namesOf('Glass')
        : const <int, String>{};
    final shutterNames = hasAny(shutterTypes)
        ? await namesOf('ShutterComponents')
        : const <int, String>{};
    final jointNames = hasAny(const {'Joints', 'Joint'})
        ? await namesOf('Joints')
        : const <int, String>{};
    final sectionNames = <int, String>{};
    if (hasAny(const {'Sections', 'Section'})) {
      final rows = await myDb.rawQuery('''
          SELECT sec.id AS id, sec.name as section_name, sec.code as section_code, ser.name as series_name, p.name as profile_name
          FROM Sections sec
          LEFT JOIN Series ser ON sec.series_id = ser.id
          LEFT JOIN Profile p ON ser.profile_id = p.id
        ''');
      for (final r in rows) {
        final id = r['id'];
        if (id is! int) continue;
        final sName = r['section_name']?.toString() ?? '';
        final sCode = r['section_code']?.toString() ?? '';
        final serName = r['series_name']?.toString() ?? '';
        final pName = r['profile_name']?.toString() ?? '';
          // Format: ProfileName - SeriesName - [Code] SectionName
          final codeStr = sCode.isNotEmpty ? '[$sCode] ' : '';
          final parts = [pName, serName].where((s) => s.isNotEmpty).join(' - ');
        var name = parts.isNotEmpty
              ? '$parts - $codeStr$sName'
              : '$codeStr$sName';
        if (name.trim().isEmpty) name = sName;
        sectionNames[id] = name;
        }
      }

    for (var row in stock) {
      final itemType = row['item_type'] as String;
      final itemId = row['item_id'] as int;
      final colorId = row['color_id'] as int?;

      final colorName = colorId == null ? '' : colorNames[colorId] ?? '';
      final String? resolvedName = switch (itemType) {
        'Profile' => profileNames[itemId],
        'Accessory' || 'Accessories' => accessoryNames[itemId],
        'Glass' => glassNames[itemId],
        'Sections' || 'Section' => sectionNames[itemId],
        'Joints' || 'Joint' => jointNames[itemId],
        _ when shutterTypes.contains(itemType) => shutterNames[itemId],
        _ => null,
      };
      final itemName = resolvedName ?? 'مجهول';

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

  /// Everything the product movement card shows for one item (and colour)
  /// across every warehouse of the store and the workshop.
  ///
  /// `movements` are in chronological order. The two legs of a transfer are
  /// merged into one row from the source to the destination. Each row has
  /// the document, party and order resolved from their ids (older rows
  /// without those columns are resolved from `reference_id`), and
  /// `running_balance`: the total over all warehouses after the movement.
  /// `balances` are the current per-warehouse quantities with their
  /// reservations; `last_purchase` and `average_cost` come from the
  /// purchase receipts.
  Future<Map<String, dynamic>> readProductMovementCard({
    required int itemId,
    required String itemType,
    int? colorId,
  }) async {
    final myDb = await db;
    if (myDb == null) return const {};
    await _ensureRemnantInventorySchema(myDb);
    await _ensureOrderCodeInfrastructure(myDb);

    final rows = await myDb.rawQuery(
      '''
      WITH m AS (
        SELECT t.*,
               COALESCE(t.occurred_at, t.created_at) AS moved_at,
               COALESCE(t.document_type, CASE
                 WHEN t.transaction_type LIKE 'Purchase%'
                   OR t.transaction_type = 'Return to Supplier'
                   OR t.transaction_type LIKE 'Internal Transfer In%'
                   OR t.transaction_type = 'Reversal: Internal Return Out of Workshop'
                   THEN 'purchase'
                 WHEN t.transaction_type LIKE 'Material Sale%'
                   OR t.transaction_type LIKE 'Internal Transfer Out%'
                   OR t.transaction_type LIKE 'Reversal: Internal Return (%'
                   THEN 'sale'
                 WHEN t.transaction_type LIKE 'order_issue%'
                   OR t.transaction_type = 'cutting_error_extra_bar'
                   THEN 'order'
               END) AS doc_type,
               COALESCE(t.document_id, t.reference_id) AS doc_id
        FROM InventoryTransactions t
        WHERE t.item_id = ? AND t.item_type = ?
          AND (t.color_id = ? OR (t.color_id IS NULL AND ? IS NULL))
      )
      SELECT m.*,
             l.name AS location_name,
             lf.name AS from_location_name,
             lt.name AS to_location_name,
             COALESCE(m.supplier_id, a.supplier_id) AS party_supplier_id,
             COALESCE(s.name, a.supplier_name) AS supplier_name,
             COALESCE(m.client_id, ms.client_id, cmd.client_id) AS party_client_id,
             COALESCE(
               NULLIF(TRIM(COALESCE(c.firstname, '') || ' ' ||
                           COALESCE(c.lastname, '')), ''),
               NULLIF(ms.client_name, '')
             ) AS client_name,
             COALESCE(m.order_id,
                      CASE WHEN m.doc_type = 'order' THEN m.doc_id END)
               AS resolved_order_id,
             cmd.order_code AS order_code,
             COALESCE(m.document_code, a.invoice_number, ms.sale_code,
                      CAST(cmd.order_code AS TEXT)) AS doc_code
      FROM m
      LEFT JOIN Locations l ON l.id = m.location_id
      LEFT JOIN Locations lf ON lf.id = m.from_location_id
      LEFT JOIN Locations lt ON lt.id = m.to_location_id
      LEFT JOIN Achats a ON m.doc_type = 'purchase' AND a.id = m.doc_id
      LEFT JOIN MaterialSales ms ON m.doc_type = 'sale' AND ms.id = m.doc_id
      LEFT JOIN Commandes cmd ON cmd.id = COALESCE(m.order_id,
               CASE WHEN m.doc_type = 'order' THEN m.doc_id END)
      LEFT JOIN Suppliers s
        ON s.id = COALESCE(m.supplier_id, a.supplier_id)
      LEFT JOIN Client c
        ON c.id = COALESCE(m.client_id, ms.client_id, cmd.client_id)
      ORDER BY m.moved_at ASC, m.id ASC
      ''',
      [itemId, itemType, colorId, colorId],
    );

    // Normalise every row, then merge transfer legs.
    final normalised = <Map<String, dynamic>>[];
    for (final raw in rows) {
      final row = Map<String, dynamic>.from(raw);
      final quantity = SqlDatabase._readStoredNumber(row['quantity']) ?? 0;
      final transactionType = row['transaction_type']?.toString() ?? '';
      final movementType =
          (row['movement_type']?.toString().isNotEmpty ?? false)
          ? row['movement_type'].toString()
          : SqlDatabase.movementTypeForTransaction(transactionType);
      row['movement_type'] = movementType;
      row['quantity'] = quantity;
      row['from_location_id'] ??= quantity < 0 ? row['location_id'] : null;
      row['from_location_name'] ??= quantity < 0 ? row['location_name'] : null;
      row['to_location_id'] ??= quantity > 0 ? row['location_id'] : null;
      row['to_location_name'] ??= quantity > 0 ? row['location_name'] : null;
      // Remnant issues are recorded in metres from MaterialRemnants; they
      // never changed a CurrentStock balance.
      row['affects_balance'] = movementType != SqlDatabase.movementRemnant;
      normalised.add(row);
    }

    String? transferKey(Map<String, dynamic> row) {
      if (row['movement_type'] != SqlDatabase.movementInternalTransfer) return null;
      final id = row['transfer_id']?.toString() ?? '';
      if (id.isNotEmpty) return id;
      // Older transfers wrote both legs with one timestamp.
      return 'legacy|${row['moved_at']}|${row['doc_type']}';
    }

    final movements = <Map<String, dynamic>>[];
    final openTransfers = <String, Map<String, dynamic>>{};
    for (final row in normalised) {
      final key = transferKey(row);
      final quantity = row['quantity'] as double;
      if (key == null) {
        movements.add(row);
        continue;
      }
      final open = openTransfers.remove(key);
      if (open == null) {
        final merged = Map<String, dynamic>.from(row)
          ..['is_transfer'] = true
          ..['transfer_quantity'] = quantity.abs()
          ..['legs'] = [row];
        openTransfers[key] = merged;
        movements.add(merged);
        continue;
      }
      final out = quantity < 0 ? row : (open['legs'] as List).first as Map;
      final inbound = quantity < 0
          ? (open['legs'] as List).first as Map
          : row;
      open
        ..['legs'] = [out, inbound]
        ..['from_location_id'] = out['location_id']
        ..['from_location_name'] = out['location_name']
        ..['to_location_id'] = inbound['location_id']
        ..['to_location_name'] = inbound['location_name']
        ..['quantity'] = 0.0
        ..['transfer_quantity'] = (inbound['quantity'] as double).abs()
        ..['out_document_type'] = out['doc_type']
        ..['out_document_id'] = out['doc_id']
        ..['out_document_code'] = out['doc_code']
        ..['in_document_type'] = inbound['doc_type']
        ..['in_document_id'] = inbound['doc_id']
        ..['in_document_code'] = inbound['doc_code'];
    }
    // A single unmatched leg still moves stock in or out.
    for (final open in openTransfers.values) {
      final leg = (open['legs'] as List).first as Map;
      open['quantity'] = leg['quantity'];
    }

    var running = 0.0;
    for (final row in movements) {
      if (row['affects_balance'] == true) {
        running += row['quantity'] as double;
      }
      row['running_balance'] = running;
    }

    // Current balances and reservations per warehouse.
    final balanceRows = await myDb.rawQuery(
      '''
      SELECT cs.location_id, l.name AS location_name,
             COALESCE(l.is_workshop, 0) AS is_workshop,
             cs.quantity,
             COALESCE((
               SELECT SUM(r.quantity) FROM StockReservations r
               WHERE r.status = 'active'
                 AND r.item_id = cs.item_id AND r.item_type = cs.item_type
                 AND (r.color_id = cs.color_id
                      OR (r.color_id IS NULL AND cs.color_id IS NULL))
                 AND r.location_id = cs.location_id
             ), 0) AS reserved_quantity
      FROM CurrentStock cs
      LEFT JOIN Locations l ON l.id = cs.location_id
      WHERE cs.item_id = ? AND cs.item_type = ?
        AND (cs.color_id = ? OR (cs.color_id IS NULL AND ? IS NULL))
      ORDER BY cs.location_id
      ''',
      [itemId, itemType, colorId, colorId],
    ).catchError((_) async {
      // Old databases may not have Locations.is_workshop yet.
      return myDb.rawQuery(
        '''
        SELECT cs.location_id, l.name AS location_name, 0 AS is_workshop,
               cs.quantity, 0 AS reserved_quantity
        FROM CurrentStock cs
        LEFT JOIN Locations l ON l.id = cs.location_id
        WHERE cs.item_id = ? AND cs.item_type = ?
          AND (cs.color_id = ? OR (cs.color_id IS NULL AND ? IS NULL))
        ''',
        [itemId, itemType, colorId, colorId],
      );
    });
    final balances = [
      for (final row in balanceRows)
        {
          ...row,
          'quantity': SqlDatabase._readStoredNumber(row['quantity']) ?? 0,
          'reserved_quantity': SqlDatabase._readStoredNumber(row['reserved_quantity']) ?? 0,
        },
    ];

    final receipts = movements
        .where(
          (row) =>
              row['movement_type'] == SqlDatabase.movementPurchaseReceipt &&
              (row['quantity'] as double) > 0,
        )
        .toList();
    var costQuantity = 0.0;
    var costTotal = 0.0;
    for (final row in receipts) {
      final cost = SqlDatabase._readStoredNumber(row['unit_cost']);
      if (cost == null || cost <= 0) continue;
      costQuantity += row['quantity'] as double;
      costTotal += cost * (row['quantity'] as double);
    }

    return {
      'movements': movements,
      'balances': balances,
      'total_quantity': balances.fold<double>(
        0,
        (sum, row) => sum + (row['quantity'] as double),
      ),
      'reserved_quantity': balances.fold<double>(
        0,
        (sum, row) => sum + (row['reserved_quantity'] as double),
      ),
      'last_purchase': receipts.isEmpty ? null : receipts.last,
      'average_cost': costQuantity > 0 ? costTotal / costQuantity : null,
    };
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

  /// Zeroes stock balances. For one location or item type this posts an
  /// adjustment movement for every balance (refused while a balance is
  /// reserved for an order), so the product history still explains the
  /// zero. Without an argument the whole inventory and its history are
  /// reset, which is the workshop reset, not a stock operation.
  Future<void> emptyInventory([dynamic idOrType]) async {
    return runUserDeletion<void>('emptyInventory', () async {
      final database = await db;
      if (database == null) return;

      if (idOrType == null) {
        await database.delete('CurrentStock');
        await database.delete('InventoryTransactions');
        CloudSyncService().notifyChange();
        return;
      }
      final String where;
      if (idOrType is int) {
        where = 'location_id = ?';
      } else if (idOrType is String && idOrType.isNotEmpty) {
        where = 'item_type = ?';
      } else {
        return;
      }
      await _ensureRemnantInventorySchema(database);
      final actor = await _currentStockActor();
      await database.transaction((txn) async {
        final rows = await txn.query(
          'CurrentStock',
          where: '$where AND quantity > 0',
          whereArgs: [idOrType],
        );
        final now = DateTime.now().toUtc().toIso8601String();
        for (final row in rows) {
          await _postStockMovement(
            txn,
            itemId: (row['item_id'] as num).toInt(),
            itemType: row['item_type'].toString(),
            colorId: (row['color_id'] as num?)?.toInt(),
            locationId: (row['location_id'] as num).toInt(),
            quantity: -(SqlDatabase._readStoredNumber(row['quantity']) ?? 0),
            transactionType: 'Adjustment',
            movementType: SqlDatabase.movementAdjustment,
            actor: actor,
            timestamp: now,
            reason: 'تصفير المخزون',
          );
        }
      });
      CloudSyncService().notifyChange();
    });
  }

  /// Generate the next sequential sale code (e.g. VS-26-001)
  Future<String> nextMaterialSaleCode() async {
    final myDb = await db;
    if (myDb == null) return 'VS-00-001';
    await _ensureRemnantInventorySchema(myDb);
    final year2 = (DateTime.now().year % 100).toString().padLeft(2, '0');
    final rows = await myDb.rawQuery(
      "SELECT sale_code FROM MaterialSales WHERE sale_code LIKE 'VS-$year2-%'",
    );
    var maxSequence = 0;
    final pattern = RegExp(r'-(\d+)$');
    for (final row in rows) {
      final match = pattern.firstMatch(row['sale_code']?.toString() ?? '');
      final sequence = int.tryParse(match?.group(1) ?? '') ?? 0;
      if (sequence > maxSequence) maxSequence = sequence;
    }
    return 'VS-$year2-${(maxSequence + 1).toString().padLeft(3, '0')}';
  }

  Future<String> _uniqueMaterialSaleCode(
    DatabaseExecutor executor,
    String preferred,
  ) async {
    final clean = preferred.trim().isEmpty ? 'VS-00-001' : preferred.trim();
    var candidate = clean;
    final suffixPattern = RegExp(r'^(.*?)-(\d+)$');
    final match = suffixPattern.firstMatch(clean);
    final prefix = match?.group(1) ?? clean;
    var sequence = int.tryParse(match?.group(2) ?? '') ?? 1;
    while ((await executor.query(
      'MaterialSales',
      columns: ['id'],
      where: 'sale_code = ?',
      whereArgs: [candidate],
      limit: 1,
    )).isNotEmpty) {
      sequence++;
      candidate = '$prefix-${sequence.toString().padLeft(3, '0')}';
    }
    return candidate;
  }

  /// Resolves visible-number collisions created by two offline devices. The
  /// distributed/internal ids remain untouched; only the later document gets
  /// the next free human-readable sequence.
  Future<void> reconcileMaterialSaleDisplayCodes() async {
    final database = await db;
    if (database == null) return;
    await _ensureRemnantInventorySchema(database);
    var changed = false;
    await database.transaction((txn) async {
      final rows = await txn.query(
        'MaterialSales',
        columns: ['id', 'sale_code', 'created_at'],
        orderBy: 'created_at ASC, id ASC',
      );
      final used = <String>{};
      final suffixPattern = RegExp(r'^(.*?)-(\d+)$');
      for (final row in rows) {
        final id = (row['id'] as num?)?.toInt();
        final code = row['sale_code']?.toString().trim() ?? '';
        if (id == null || code.isEmpty) continue;
        if (used.add(code)) continue;
        final match = suffixPattern.firstMatch(code);
        final prefix = match?.group(1) ?? code;
        var sequence = int.tryParse(match?.group(2) ?? '') ?? 1;
        String candidate;
        do {
          sequence++;
          candidate = '$prefix-${sequence.toString().padLeft(3, '0')}';
        } while (used.contains(candidate));
        await txn.update(
          'MaterialSales',
          {
            'sale_code': candidate,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          },
          where: 'id = ?',
          whereArgs: [id],
        );
        used.add(candidate);
        changed = true;
      }
    });
    if (changed) CloudSyncService().notifyChange();
  }

  /// Insert a new MaterialSale header row and return its new id.
  Future<int> insertMaterialSale({
    required String saleCode,
    int? clientId,
    required String clientName,
    String clientPhone = '',
    required String docType,
    String status = 'draft',
    double subtotal = 0.0,
    double discountAmount = 0.0,
    double netTotal = 0.0,
    double paidAmount = 0.0,
    double remainingAmount = 0.0,
    int locationId = 1,
    int stockDeducted = 0,
    String notes = '',
    String? saleDate,
  }) async {
    final myDb = await db;
    if (myDb == null) return 0;
    await _ensureRemnantInventorySchema(myDb);
    final now = DateTime.now().toUtc().toIso8601String();
    final author = await _currentOrderEditor();
    final id = await myDb.transaction<int>((txn) async {
      final visibleCode = await _uniqueMaterialSaleCode(txn, saleCode);
      return txn.insert(
        'MaterialSales',
        SqlDatabase._withDistributedId({
          'sale_code': visibleCode,
          'client_id': clientId,
          'client_name': clientName,
          'client_phone': clientPhone,
          'doc_type': docType,
          'status': status,
          'subtotal': subtotal,
          'discount_amount': discountAmount,
          'net_total': netTotal,
          'paid_amount': paidAmount,
          'remaining_amount': remainingAmount,
          'location_id': locationId,
          'stock_deducted': stockDeducted,
          'notes': notes,
          'sale_date': saleDate ?? now,
          'created_at': now,
          'updated_at': now,
          'created_by': author,
          'updated_by': author,
        }),
      );
    });
    CloudSyncService().notifyChange();
    unawaited(
      _recordDashboardActivity(
        activityType: 'sale_added',
        entityId: id,
        document: saleCode,
        party: clientName,
        userName: author,
      ),
    );
    return id;
  }

  /// Update a MaterialSale header row.
  Future<void> updateMaterialSale(
    int saleId, {
    String? clientName,
    String? clientPhone,
    int? clientId,
    String? docType,
    String? status,
    double? subtotal,
    double? discountAmount,
    double? netTotal,
    double? paidAmount,
    double? remainingAmount,
    int? stockDeducted,
    String? notes,
    String? saleDate,
  }) async {
    final myDb = await db;
    if (myDb == null) return;
    final data = <String, dynamic>{
      'updated_at': DateTime.now().toUtc().toIso8601String(),
      'updated_by': await _currentOrderEditor(),
    };
    if (clientName != null) data['client_name'] = clientName;
    if (clientPhone != null) data['client_phone'] = clientPhone;
    if (clientId != null) data['client_id'] = clientId;
    if (docType != null) data['doc_type'] = docType;
    if (status != null) data['status'] = status;
    if (subtotal != null) data['subtotal'] = subtotal;
    if (discountAmount != null) data['discount_amount'] = discountAmount;
    if (netTotal != null) data['net_total'] = netTotal;
    if (paidAmount != null) data['paid_amount'] = paidAmount;
    if (remainingAmount != null) data['remaining_amount'] = remainingAmount;
    if (stockDeducted != null) data['stock_deducted'] = stockDeducted;
    if (notes != null) data['notes'] = notes;
    if (saleDate != null) data['sale_date'] = saleDate;
    await myDb.update(
      'MaterialSales',
      data,
      where: 'id = ?',
      whereArgs: [saleId],
    );
    CloudSyncService().notifyChange();
    unawaited(
      _recordDashboardActivity(
        activityType: 'sale_updated',
        entityId: saleId,
        party: clientName ?? '',
        userName: data['updated_by']?.toString(),
      ),
    );
  }

  /// Soft-deletes a store sale and reverses posted stock. ERP documents are
  /// never physically erased during normal operation.
  Future<void> deleteMaterialSale(int saleId) async {
    return runUserDeletion<void>('deleteMaterialSale', () async {
      final myDb = await db;
      if (myDb == null) return;
      await _ensureRemnantInventorySchema(myDb);
      final rows = await myDb.query(
        'MaterialSales',
        where: 'id = ?',
        whereArgs: [saleId],
      );
      if (rows.isEmpty) return;
      final sale = rows.first;
      if ((sale['is_deleted'] as num?)?.toInt() == 1) return;
      // A customer return already put part of the goods back into stock.
      // Reversing the whole sale as well would count those goods twice and
      // leave the return attached to a deleted document.
      final activeReturns = await myDb.rawQuery(
        '''
        SELECT 1 FROM MaterialSales
        WHERE doc_type = 'retour' AND source_sale_id = ?
          AND (is_deleted IS NULL OR is_deleted = 0)
        LIMIT 1
        ''',
        [saleId],
      );
      if (activeReturns.isNotEmpty) {
        throw StateError(
          'لا يمكن حذف وثيقة لها مرتجعات. احذف وثيقة المرتجع أولاً.',
        );
      }
      await snapshotMaterialSale(saleId, actionType: 'before_delete');
      final isInternal = (sale['is_internal'] as num?)?.toInt() == 1;
      final deletedBy = await _currentOrderEditor();
      final actor = await _currentStockActor();
      // The stock reversal and the soft delete succeed or fail together, so a
      // failed reversal never leaves a cancelled document with stock still out.
      await myDb.transaction((txn) async {
        if (isInternal && (sale['stock_deducted'] as num?)?.toInt() == 1) {
          await _reverseInternalMaterialSaleTransfer(txn, saleId, actor);
        } else if ((sale['stock_deducted'] as num?)?.toInt() == 1) {
          final items = await txn.query(
            'MaterialSaleItems',
            where: 'sale_id = ?',
            whereArgs: [saleId],
          );
          final locationId = (sale['location_id'] as num?)?.toInt() ?? 1;
          final now = DateTime.now().toUtc().toIso8601String();
          for (final item in items) {
            final itemId = (item['item_id'] as num?)?.toInt() ?? 0;
            final itemType = item['item_type']?.toString() ?? '';
            final colorId = (item['color_id'] as num?)?.toInt();
            final qty = (item['quantity'] as num?)?.toDouble() ?? 0.0;
            if (itemId <= 0 || qty <= 0) continue;
            await _postStockMovement(
              txn,
              itemId: itemId,
              itemType: itemType,
              colorId: colorId,
              locationId: locationId,
              quantity: qty,
              transactionType: 'Material Sale Reversal',
              movementType: SqlDatabase.movementReturn,
              actor: actor,
              timestamp: now,
              unitCost: (item['unit_price'] as num?)?.toDouble(),
              documentType: 'sale',
              documentId: saleId,
              reversesTransactionId: await _originalMovementId(
                txn,
                referenceId: saleId,
                transactionType: 'Material Sale',
                itemId: itemId,
                itemType: itemType,
                colorId: colorId,
                locationId: locationId,
              ),
              reason: 'إلغاء وثيقة البيع',
            );
          }
        }
        final now = DateTime.now().toUtc().toIso8601String();
        await txn.update(
          'MaterialSales',
          {
            'is_deleted': 1,
            'deleted_at': now,
            'deleted_by': deletedBy,
            'status_before_delete': sale['status']?.toString() ?? 'draft',
            'status': 'cancelled',
            'stock_deducted': 0,
            'updated_at': now,
          },
          where: 'id = ?',
          whereArgs: [saleId],
        );
      });
      await logAuditAction(
        actionType: 'delete',
        entityType: 'MaterialSale',
        entityId: saleId.toString(),
        entityTitle: sale['sale_code']?.toString(),
        details: 'Soft deleted; stock movement reversed and document retained.',
      );
      CloudSyncService().notifyChange();
    });
  }

  Future<List<Map<String, dynamic>>> readTrashMaterialSales() async {
    final database = await db;
    if (database == null) return [];
    await _ensureRemnantInventorySchema(database);
    return database.query(
      'MaterialSales',
      where: 'is_deleted = 1',
      orderBy: 'deleted_at DESC, id DESC',
    );
  }

  /// Empties the store-sales bin: the sales already deleted (whose stock was
  /// returned at deletion) and their lines are removed for good. Returns how
  /// many sales were removed; one that fails never stops the others.
  Future<int> emptyMaterialSalesTrash() async {
    return runUserDeletion<int>('emptyMaterialSalesTrash', () async {
      final database = await db;
      if (database == null) return 0;
      await _ensureRemnantInventorySchema(database);
      await _ensureSyncTombstoneInfrastructure(database);
      final trashed = await database.query(
        'MaterialSales',
        columns: ['id'],
        where: 'is_deleted = 1',
      );
      var removed = 0;
      for (final row in trashed) {
        final id = (row['id'] as num?)?.toInt();
        if (id == null) continue;
        try {
          await database.transaction((txn) async {
            await txn.delete(
              'MaterialSaleItems',
              where: 'sale_id = ?',
              whereArgs: [id],
            );
            await txn.delete(
              'MaterialSales',
              where: 'id = ? AND is_deleted = 1',
              whereArgs: [id],
            );
          });
          removed++;
        } catch (error) {
          debugPrint('emptyMaterialSalesTrash: sale $id kept: $error');
        }
      }
      if (removed > 0) CloudSyncService().notifyChange();
      return removed;
    });
  }

  Future<void> restoreMaterialSale(int saleId) async {
    final database = await db;
    if (database == null) return;
    await _ensureRemnantInventorySchema(database);
    final rows = await database.query(
      'MaterialSales',
      where: 'id = ? AND is_deleted = 1',
      whereArgs: [saleId],
      limit: 1,
    );
    if (rows.isEmpty) return;
    final sale = rows.first;
    final now = DateTime.now().toUtc().toIso8601String();
    // Restore as a draft: the manager can verify quantities and explicitly
    // confirm it again. This avoids silently removing stock a second time.
    await database.update(
      'MaterialSales',
      {
        'is_deleted': 0,
        'deleted_at': null,
        'deleted_by': null,
        'status': 'draft',
        'stock_deducted': 0,
        'updated_at': now,
      },
      where: 'id = ?',
      whereArgs: [saleId],
    );
    await logAuditAction(
      actionType: 'restore',
      entityType: 'MaterialSale',
      entityId: saleId.toString(),
      entityTitle: sale['sale_code']?.toString(),
      details: 'Restored as draft; requires explicit confirmation.',
    );
    CloudSyncService().notifyChangeImmediate();
  }

  /// Creates the next official sales document while preserving the source.
  /// Commande -> Bon de livraison -> Facture. The source is never overwritten.
  Future<int> transferMaterialSaleDocument(int sourceSaleId) async {
    final myDb = await db;
    if (myDb == null) return 0;
    await _ensureRemnantInventorySchema(myDb);
    return myDb
        .transaction<int>((txn) async {
          final rows = await txn.query(
            'MaterialSales',
            where: 'id = ?',
            whereArgs: [sourceSaleId],
          );
          if (rows.isEmpty) throw StateError('Source document not found');
          final source = rows.first;
          final existing = (source['converted_to_sale_id'] as num?)?.toInt();
          if (existing != null) return existing;
          final sourceType = source['doc_type']?.toString() ?? '';
          final targetType = sourceType == 'bon_commande'
              ? 'bon_livraison'
              : (sourceType == 'bon_livraison' || sourceType == 'devis')
              ? 'facture'
              : null;
          if (targetType == null) {
            throw StateError('This document cannot be transferred further');
          }
          final now = DateTime.now().toUtc().toIso8601String();
          final year2 = (DateTime.now().year % 100).toString().padLeft(2, '0');
          final prefix = targetType == 'bon_livraison' ? 'BL' : 'FV';
          final targetCode = await _uniqueMaterialSaleCode(
            txn,
            '$prefix-$year2-001',
          );
          final target = Map<String, dynamic>.from(source)
            ..remove('id')
            ..remove('distributed_id')
            ..['sale_code'] = targetCode
            ..['doc_type'] = targetType
            // The next official document is deliberately a draft. Stock is
            // validated atomically when the user confirms it.
            ..['status'] = 'draft'
            ..['source_sale_id'] = sourceSaleId
            ..['converted_to_sale_id'] = null
            ..['stock_deducted'] = 0
            ..['linked_achat_id'] = null
            ..['created_at'] = now
            ..['updated_at'] = now;
          final targetId = await txn.insert(
            'MaterialSales',
            SqlDatabase._withDistributedId(target),
          );
          final items = await txn.query(
            'MaterialSaleItems',
            where: 'sale_id = ?',
            whereArgs: [sourceSaleId],
          );
          for (final row in items) {
            final copy = Map<String, dynamic>.from(row)
              ..remove('id')
              ..remove('distributed_id')
              ..['sale_id'] = targetId;
            await txn.insert('MaterialSaleItems', copy);
          }
          await txn.update(
            'MaterialSales',
            {
              'converted_to_sale_id': targetId,
              'status': sourceType == 'bon_livraison'
                  ? 'delivered'
                  : 'confirmed',
              'updated_at': now,
            },
            where: 'id = ?',
            whereArgs: [sourceSaleId],
          );
          return targetId;
        })
        .then((id) {
          CloudSyncService().notifyChange();
          return id;
        });
  }

  /// Read all MaterialSale rows, newest first.
  Future<List<Map<String, dynamic>>> readMaterialSales({
    String? docType,
    String? status,
    String? searchQuery,
  }) async {
    final myDb = await db;
    if (myDb == null) return [];
    await _ensureRemnantInventorySchema(myDb);
    await reconcileMaterialSaleDisplayCodes();
    final conditions = <String>['COALESCE(sale.is_deleted, 0) = 0'];
    final args = <dynamic>[];
    if (docType != null && docType.isNotEmpty) {
      conditions.add('sale.doc_type = ?');
      args.add(docType);
    }
    if (status != null && status.isNotEmpty) {
      conditions.add('sale.status = ?');
      args.add(status);
    }
    if (searchQuery != null && searchQuery.isNotEmpty) {
      conditions.add('(sale.client_name LIKE ? OR sale.sale_code LIKE ?)');
      args.add('%$searchQuery%');
      args.add('%$searchQuery%');
    }
    final where = conditions.isEmpty ? null : conditions.join(' AND ');
    final whereSql = where == null ? '' : 'WHERE $where';
    return myDb.rawQuery('''
      SELECT
        sale.*,
        source_document.sale_code AS linked_source_code,
        target_document.sale_code AS linked_target_code
      FROM MaterialSales AS sale
      LEFT JOIN MaterialSales AS source_document
        ON source_document.id = sale.source_sale_id
      LEFT JOIN MaterialSales AS target_document
        ON target_document.id = sale.converted_to_sale_id
      $whereSql
      ORDER BY sale.sale_date DESC, sale.id DESC
    ''', args);
  }

  /// Read a single MaterialSale by id.
  Future<Map<String, dynamic>?> readMaterialSaleById(int saleId) async {
    final myDb = await db;
    if (myDb == null) return null;
    final rows = await myDb.query(
      'MaterialSales',
      where: 'id = ?',
      whereArgs: [saleId],
    );
    return rows.isEmpty ? null : rows.first;
  }

  /// Read all items for a given sale.
  Future<List<Map<String, dynamic>>> readMaterialSaleItems(int saleId) async {
    final myDb = await db;
    if (myDb == null) return [];
    return myDb.rawQuery(
      '''
      SELECT msi.*,
             COALESCE(NULLIF(msi.system_name, ''), pro.name, '') AS system_name,
             COALESCE(NULLIF(msi.series_name, ''), ser.name, '') AS series_name
      FROM MaterialSaleItems msi
      LEFT JOIN Sections sec
        ON msi.item_type IN ('Section', 'Sections')
       AND sec.id = msi.item_id
      LEFT JOIN Series ser ON ser.id = sec.series_id
      LEFT JOIN Profile pro ON pro.id = ser.profile_id
      WHERE msi.sale_id = ?
      ORDER BY msi.id ASC
      ''',
      [saleId],
    );
  }

  /// Remaining quantities that may still be returned by the customer.
  Future<List<Map<String, dynamic>>> readReturnableMaterialSaleItems(
    int saleId,
  ) async {
    final myDb = await db;
    if (myDb == null) return [];
    return _readReturnableMaterialSaleItemsWith(myDb, saleId);
  }

  Future<List<Map<String, dynamic>>> _readReturnableMaterialSaleItemsWith(
    dynamic executor,
    int saleId,
  ) async {
    final items = List<Map<String, dynamic>>.from(
      await executor.query(
        'MaterialSaleItems',
        where: 'sale_id = ?',
        whereArgs: [saleId],
        orderBy: 'id ASC',
      ),
    );
    final returnedRows = List<Map<String, dynamic>>.from(
      await executor.rawQuery(
        '''
      SELECT ri.item_type, ri.item_id, ri.item_code, ri.color_id,
             SUM(ri.quantity) AS returned_quantity
      FROM MaterialSaleItems ri
      JOIN MaterialSales r ON r.id = ri.sale_id
      WHERE r.doc_type = 'retour' AND r.source_sale_id = ?
        AND (r.is_deleted IS NULL OR r.is_deleted = 0)
      GROUP BY ri.item_type, ri.item_id, ri.item_code, ri.color_id
      ''',
        [saleId],
      ),
    );
    String key(Map<String, dynamic> row) =>
        '${row['item_type']}|${row['item_id']}|${row['item_code']}|${row['color_id']}';
    final returned = <String, double>{
      for (final row in returnedRows)
        key(row): (row['returned_quantity'] as num?)?.toDouble() ?? 0.0,
    };
    return items
        .map((item) {
          final sold = (item['quantity'] as num?)?.toDouble() ?? 0.0;
          final alreadyReturned = returned[key(item)] ?? 0.0;
          return {
            ...item,
            'returned_quantity': alreadyReturned,
            'returnable_quantity': (sold - alreadyReturned)
                .clamp(0.0, sold)
                .toDouble(),
          };
        })
        .where((item) => (item['returnable_quantity'] as double) > 0)
        .toList();
  }

  /// Creates an immutable customer return document and puts the selected
  /// quantities back into the same stock location as the original sale.
  Future<int> returnMaterialSaleItems(
    int sourceSaleId,
    List<Map<String, dynamic>> returnedItems,
  ) async {
    final myDb = await db;
    if (myDb == null || returnedItems.isEmpty) return 0;
    await _ensureRemnantInventorySchema(myDb);
    final editor = await _currentOrderEditor();
    final actor = await _currentStockActor();
    final now = DateTime.now().toUtc().toIso8601String();
    final returnId = await myDb.transaction<int>((txn) async {
      final sourceRows = await txn.query(
        'MaterialSales',
        where: 'id = ? AND (is_deleted IS NULL OR is_deleted = 0)',
        whereArgs: [sourceSaleId],
        limit: 1,
      );
      if (sourceRows.isEmpty)
        throw StateError('وثيقة البيع الأصلية غير موجودة.');
      final source = sourceRows.first;
      if ((source['stock_deducted'] as num?)?.toInt() != 1) {
        throw StateError('لا يمكن إرجاع مواد لم تخرج من المخزون.');
      }
      final available = await _readReturnableMaterialSaleItemsWith(
        txn,
        sourceSaleId,
      );
      String key(Map<String, dynamic> row) =>
          '${row['item_type']}|${row['item_id']}|${row['item_code']}|${row['color_id']}';
      final availableByKey = {for (final row in available) key(row): row};
      var total = 0.0;
      for (final request in returnedItems) {
        final original = availableByKey[key(request)];
        final qty = (request['quantity'] as num?)?.toDouble() ?? 0.0;
        final maxQty =
            (original?['returnable_quantity'] as num?)?.toDouble() ?? 0.0;
        if (original == null || qty <= 0 || qty > maxQty + 0.000001) {
          throw StateError('كمية الإرجاع غير صالحة أو أكبر من الكمية المباعة.');
        }
        total += qty * ((original['unit_price'] as num?)?.toDouble() ?? 0.0);
      }
      final code = await _uniqueMaterialSaleCode(
        txn,
        'RET-${DateFormat('yyyyMMdd-HHmmss').format(DateTime.now())}',
      );
      final id = await txn.insert(
        'MaterialSales',
        SqlDatabase._withDistributedId({
          'sale_code': code,
          'client_id': source['client_id'],
          'client_name': source['client_name'],
          'client_phone': source['client_phone'],
          'doc_type': 'retour',
          'status': 'confirmed',
          'subtotal': total,
          'discount_amount': 0.0,
          'net_total': total,
          'paid_amount': total,
          'remaining_amount': 0.0,
          'location_id': source['location_id'],
          'stock_deducted': 0,
          'source_sale_id': sourceSaleId,
          'notes': 'Customer return for ${source['sale_code']}',
          'sale_date': now,
          'created_at': now,
          'updated_at': now,
          'created_by': editor,
          'updated_by': editor,
        }),
      );
      final locationId = (source['location_id'] as num?)?.toInt() ?? 1;
      for (final request in returnedItems) {
        final original = availableByKey[key(request)]!;
        final qty = (request['quantity'] as num).toDouble();
        final unitPrice = (original['unit_price'] as num?)?.toDouble() ?? 0.0;
        await txn.insert('MaterialSaleItems', {
          'sale_id': id,
          'item_type': original['item_type'],
          'item_id': original['item_id'],
          'item_code': original['item_code'] ?? '',
          'item_name': original['item_name'] ?? '',
          'system_name': original['system_name'] ?? '',
          'series_name': original['series_name'] ?? '',
          'color_id': original['color_id'],
          'color_name': original['color_name'] ?? '',
          'unit': original['unit'] ?? 'pcs',
          'length_mm': original['length_mm'] ?? 0.0,
          'width_mm': original['width_mm'] ?? 0.0,
          'quantity': qty,
          'unit_price': unitPrice,
          'tax_rate': original['tax_rate'] ?? 0.0,
          'total_price': qty * unitPrice,
          'notes': 'Returned from sale ${source['sale_code']}',
        });
        // The customer's goods re-enter the store, linked to the return
        // document and to the sale it reverses.
        await _postStockMovement(
          txn,
          itemId: (original['item_id'] as num).toInt(),
          itemType: original['item_type'].toString(),
          colorId: (original['color_id'] as num?)?.toInt(),
          locationId: locationId,
          quantity: qty,
          transactionType: 'Material Sale Return',
          movementType: SqlDatabase.movementReturn,
          actor: actor,
          timestamp: now,
          unit: original['unit']?.toString(),
          unitCost: unitPrice,
          documentType: 'sale',
          documentId: id,
          linkedDocumentType: 'sale',
          linkedDocumentId: sourceSaleId,
          reason: 'مرتجع زبون',
        );
      }
      final remaining = await _readReturnableMaterialSaleItemsWith(
        txn,
        sourceSaleId,
      );
      final fullyReturned = remaining.isEmpty;
      await txn.update(
        'MaterialSales',
        {
          'status': fullyReturned ? 'returned' : 'partially_returned',
          'updated_at': now,
          'updated_by': editor,
        },
        where: 'id = ?',
        whereArgs: [sourceSaleId],
      );
      return id;
    });
    CloudSyncService().notifyChange();
    return returnId;
  }

  /// Insert a single item line into a sale.
  Future<int> insertMaterialSaleItem({
    required int saleId,
    required String itemType,
    required int itemId,
    required String itemCode,
    required String itemName,
    String systemName = '',
    String seriesName = '',
    int? colorId,
    String colorName = '',
    required String unit,
    double lengthMm = 0.0,
    double widthMm = 0.0,
    required double quantity,
    required double unitPrice,
    required double totalPrice,
    String notes = '',
  }) async {
    final myDb = await db;
    if (myDb == null) return 0;
    final id = await myDb.insert('MaterialSaleItems', {
      'sale_id': saleId,
      'item_type': itemType,
      'item_id': itemId,
      'item_code': itemCode,
      'item_name': itemName,
      'system_name': systemName,
      'series_name': seriesName,
      'color_id': colorId,
      'color_name': colorName,
      'unit': unit,
      'length_mm': lengthMm,
      'width_mm': widthMm,
      'quantity': quantity,
      'unit_price': unitPrice,
      'total_price': totalPrice,
      'notes': notes,
    });
    CloudSyncService().notifyChange();
    return id;
  }

  /// Delete a single item from a sale.
  Future<void> deleteMaterialSaleItem(int itemId) async {
    return runUserDeletion<void>('deleteMaterialSaleItem', () async {
      final myDb = await db;
      if (myDb == null) return;
      await myDb.delete(
        'MaterialSaleItems',
        where: 'id = ?',
        whereArgs: [itemId],
      );
      CloudSyncService().notifyChange();
    });
  }

  /// Replace all items of a sale and recalculate totals.
  Future<void> saveMaterialSaleWithItems({
    required int saleId,
    required List<Map<String, dynamic>> items,
    required double subtotal,
    required double discountAmount,
    required double netTotal,
    required double paidAmount,
  }) async {
    return runUserDeletion<void>('saveMaterialSaleWithItems', () async {
      final myDb = await db;
      if (myDb == null) return;
      final now = DateTime.now().toUtc().toIso8601String();
      final editor = await _currentOrderEditor();
      await myDb.transaction((txn) async {
        await txn.delete(
          'MaterialSaleItems',
          where: 'sale_id = ?',
          whereArgs: [saleId],
        );
        for (final item in items) {
          await txn.insert('MaterialSaleItems', {
            'sale_id': saleId,
            'item_type': item['item_type'] ?? 'Other',
            'item_id': item['item_id'] ?? 0,
            'item_code': item['item_code'] ?? '',
            'item_name': item['item_name'] ?? '',
            'system_name': item['system_name'] ?? '',
            'series_name': item['series_name'] ?? '',
            'color_id': item['color_id'],
            'color_name': item['color_name'] ?? '',
            'unit': item['unit'] ?? 'pcs',
            'length_mm': (item['length_mm'] as num?)?.toDouble() ?? 0.0,
            'width_mm': (item['width_mm'] as num?)?.toDouble() ?? 0.0,
            'quantity': (item['quantity'] as num?)?.toDouble() ?? 1.0,
            'unit_price': (item['unit_price'] as num?)?.toDouble() ?? 0.0,
            'tax_rate': (item['tax_rate'] as num?)?.toDouble() ?? 0.0,
            'total_price': (item['total_price'] as num?)?.toDouble() ?? 0.0,
            'notes': item['notes'] ?? '',
          });
        }
        await txn.update(
          'MaterialSales',
          {
            'subtotal': subtotal,
            'discount_amount': discountAmount,
            'net_total': netTotal,
            'paid_amount': paidAmount,
            'remaining_amount': (netTotal - paidAmount).clamp(
              0.0,
              double.infinity,
            ),
            'updated_at': now,
            'updated_by': editor,
          },
          where: 'id = ?',
          whereArgs: [saleId],
        );
      });
      try {
        // A sale saved right after it was created stays one "sale added".
        await _recordDashboardActivity(
          activityType: 'sale_updated',
          entityId: saleId,
          userName: editor,
          mergeInto: const {'sale_added'},
        );
      } catch (_) {}
      CloudSyncService().notifyChange();
    });
  }

  /// Saves a complete immutable before/after snapshot in the shared audit log.
  /// The operational tables stay compact while managers can reconstruct every
  /// version of a store document, including all line items.
  Future<void> snapshotMaterialSale(
    int saleId, {
    required String actionType,
    Map<String, dynamic>? afterHeader,
    List<Map<String, dynamic>>? afterItems,
  }) async {
    final database = await db;
    if (database == null) return;
    await _ensureAuditLogsInfrastructure(database);
    final headerRows = await database.query(
      'MaterialSales',
      where: 'id = ?',
      whereArgs: [saleId],
      limit: 1,
    );
    if (headerRows.isEmpty) return;
    final beforeItems = await database.query(
      'MaterialSaleItems',
      where: 'sale_id = ?',
      whereArgs: [saleId],
      orderBy: 'id ASC',
    );
    await logAuditAction(
      actionType: actionType,
      entityType: 'MaterialSale',
      entityId: saleId.toString(),
      entityTitle: headerRows.first['sale_code']?.toString() ?? '',
      details: jsonEncode({
        'before': {
          'header': Map<String, dynamic>.from(headerRows.first),
          'items': beforeItems.map(Map<String, dynamic>.from).toList(),
        },
        if (afterHeader != null || afterItems != null)
          'after': {
            if (afterHeader != null) 'header': afterHeader,
            if (afterItems != null) 'items': afterItems,
          },
      }),
    );
  }

  /// Deduct stock for all items in a confirmed sale (stock_deducted must be 0).
  /// Posts the stock of a shop document.
  ///
  /// * First posting: deducts every line from [locationId] and stores that
  ///   warehouse on the document, so a later deletion or return goes back to
  ///   the same warehouse.
  /// * Already posted (e.g. lines rewritten while confirming): only the
  ///   difference between the current lines and what was already deducted is
  ///   applied, from the document's own warehouse.
  ///
  /// Lines of the same item are summed before the availability check, so two
  /// lines can never take more than the warehouse holds.
  Future<void> deductStockForMaterialSale(
    int saleId, {
    int locationId = 1,
  }) async {
    final myDb = await db;
    if (myDb == null) return;
    await _ensureRemnantInventorySchema(myDb);
    final actor = await _currentStockActor();
    await myDb.transaction((txn) async {
      final saleRows = await txn.query(
        'MaterialSales',
        where: 'id = ?',
        whereArgs: [saleId],
      );
      if (saleRows.isEmpty) throw StateError('وثيقة البيع غير موجودة.');
      final sale = saleRows.first;
      final alreadyPosted = (sale['stock_deducted'] as num?)?.toInt() == 1;
      final items = await txn.query(
        'MaterialSaleItems',
        where: 'sale_id = ?',
        whereArgs: [saleId],
      );
      if (items.isEmpty) throw StateError('لا يمكن تأكيد وثيقة بدون عناصر.');
      final now = DateTime.now().toUtc().toIso8601String();
      final stockLocation = alreadyPosted
          ? (sale['location_id'] as num?)?.toInt() ?? locationId
          : locationId;

      String keyOf(String type, int id, int? color) => '$type|$id|${color ?? ''}';
      final required = <String, double>{};
      final keyParts = <String, (String, int, int?)>{};
      final labels = <String, String>{};
      final units = <String, String?>{};
      final unitPrices = <String, double?>{};
      for (final item in items) {
        final itemType = item['item_type']?.toString() ?? '';
        final itemId = (item['item_id'] as num?)?.toInt() ?? 0;
        final colorId = (item['color_id'] as num?)?.toInt();
        final qty = (item['quantity'] as num?)?.toDouble() ?? 0.0;
        final label =
            item['item_name']?.toString() ??
            item['item_code']?.toString() ??
            'عنصر';
        if (itemId <= 0 || qty <= 0) {
          throw StateError('العنصر $label بلا صنف أو كمية صالحة.');
        }
        final key = keyOf(itemType, itemId, colorId);
        required[key] = (required[key] ?? 0.0) + qty;
        keyParts[key] = (itemType, itemId, colorId);
        labels[key] = label;
        units[key] = item['unit']?.toString();
        unitPrices[key] = (item['unit_price'] as num?)?.toDouble();
      }

      // What this document already took from stock.
      final deducted = <String, double>{};
      if (alreadyPosted) {
        final movements = await txn.query(
          'InventoryTransactions',
          where:
              "reference_id = ? AND transaction_type IN "
              "('Material Sale', 'Material Sale Adjustment', "
              "'Material Sale Reversal')",
          whereArgs: [saleId],
        );
        // Documents posted before the movements were recorded cannot be
        // reconciled safely: keep the stock as it is. (A reversal belongs to
        // an earlier deletion that a restore posted again.)
        if (movements.isEmpty) return;
        for (final move in movements) {
          final itemType = move['item_type']?.toString() ?? '';
          final itemId = (move['item_id'] as num?)?.toInt() ?? 0;
          final colorId = (move['color_id'] as num?)?.toInt();
          final key = keyOf(itemType, itemId, colorId);
          deducted[key] =
              (deducted[key] ?? 0.0) -
              ((move['quantity'] as num?)?.toDouble() ?? 0.0);
          keyParts.putIfAbsent(key, () => (itemType, itemId, colorId));
          labels.putIfAbsent(
            key,
            () => move['item_type']?.toString() ?? 'عنصر',
          );
        }
      }

      final changes = <String, double>{
        for (final key in {...required.keys, ...deducted.keys})
          key: (required[key] ?? 0.0) - (deducted[key] ?? 0.0),
      }..removeWhere((_, change) => change.abs() <= 0.000001);

      // Validate every extra deduction first: nothing is written if even one
      // item is short (reservations included), so unavailable lines are never
      // silently omitted.
      for (final entry in changes.entries) {
        if (entry.value <= 0) continue;
        final (itemType, itemId, colorId) = keyParts[entry.key]!;
        final where = colorId == null
            ? 'item_id = ? AND item_type = ? AND color_id IS NULL AND location_id = ?'
            : 'item_id = ? AND item_type = ? AND color_id = ? AND location_id = ?';
        final args = colorId == null
            ? <Object?>[itemId, itemType, stockLocation]
            : <Object?>[itemId, itemType, colorId, stockLocation];
        final stock = await txn.query(
          'CurrentStock',
          where: where,
          whereArgs: args,
          limit: 1,
        );
        final available = stock.isEmpty
            ? 0.0
            : (stock.first['quantity'] as num?)?.toDouble() ?? 0.0;
        if (available + 0.000001 < entry.value) {
          throw StateError(
            'المخزون غير كافٍ لـ ${labels[entry.key]}: المتوفر $available والمطلوب ${entry.value}.',
          );
        }
        await _ensureUnreservedStock(
          txn,
          itemId: itemId,
          itemType: itemType,
          colorId: colorId,
          locationId: stockLocation,
          quantity: entry.value,
          currentQuantity: available,
          label: labels[entry.key],
        );
      }

      for (final entry in changes.entries) {
        final (itemType, itemId, colorId) = keyParts[entry.key]!;
        // Already validated above, reservations included.
        await _postStockMovement(
          txn,
          itemId: itemId,
          itemType: itemType,
          colorId: colorId,
          locationId: stockLocation,
          quantity: -entry.value,
          transactionType: alreadyPosted
              ? 'Material Sale Adjustment'
              : 'Material Sale',
          movementType: entry.value > 0
              ? SqlDatabase.movementSaleIssue
              : SqlDatabase.movementReturn,
          actor: actor,
          timestamp: now,
          unit: units[entry.key],
          unitCost: unitPrices[entry.key],
          documentType: 'sale',
          documentId: saleId,
          checkReservations: false,
          label: labels[entry.key],
        );
      }
      await txn.update(
        'MaterialSales',
        {
          'stock_deducted': 1,
          'location_id': stockLocation,
          'updated_at': now,
        },
        where: 'id = ?',
        whereArgs: [saleId],
      );
    });
    CloudSyncService().notifyChange();
  }

  /// Atomically executes an internal sale transfer from store to workshop warehouse.
  /// Single-transaction double-entry inventory and document creation.
  Future<int> executeInternalMaterialSaleTransfer({
    required int saleId,
    required int destLocationId,
  }) async {
    final myDb = await db;
    if (myDb == null) return 0;
    await _ensureRemnantInventorySchema(myDb);
    final actor = await _currentStockActor();
    final transferId = SqlDatabase._newTransferId();

    final createdAchatId = await myDb.transaction<int>((txn) async {
      final saleRows = await txn.query(
        'MaterialSales',
        where: 'id = ?',
        whereArgs: [saleId],
      );
      if (saleRows.isEmpty) throw Exception('Material sale not found');
      final sale = saleRows.first;
      if ((sale['stock_deducted'] as num?)?.toInt() == 1) {
        final existingLinked = (sale['linked_achat_id'] as num?)?.toInt();
        if (existingLinked != null) return existingLinked;
        throw StateError('تم تنفيذ حركة مخزون هذه الوثيقة مسبقاً.');
      }
      final storeLocationId = (sale['location_id'] as num?)?.toInt() ?? 1;
      final saleCode = sale['sale_code']?.toString() ?? 'SALE';
      final netTotal = (sale['net_total'] as num?)?.toDouble() ?? 0.0;
      final now = DateTime.now().toUtc().toIso8601String();

      final items = await txn.query(
        'MaterialSaleItems',
        where: 'sale_id = ?',
        whereArgs: [saleId],
      );
      if (items.isEmpty) throw Exception('No items in sale');

      final linkedInvoice = 'INT-$saleCode';
      final existingAchat = await txn.query(
        'Achats',
        where: 'invoice_number = ?',
        whereArgs: [linkedInvoice],
      );

      int achatId;
      if (existingAchat.isNotEmpty) {
        achatId = (existingAchat.first['id'] as num).toInt();
      } else {
        achatId = await txn.insert(
          'Achats',
          SqlDatabase._withDistributedId({
            'invoice_number': linkedInvoice,
            'supplier_name': 'محل بيع المواد (تحويل داخلي)',
            'location_id': destLocationId,
            'status': 'Confirmed',
            'total': netTotal,
            'paid_amount': netTotal,
            'remaining_amount': 0.0,
            'activity_type': 'workshop_internal',
            'is_workshop': 1,
            'is_internal': 1,
            'linked_sale_id': saleId,
            'created_at': now,
            'updated_at': now,
          }),
        );
      }

      for (final item in items) {
        final itemType = item['item_type'] as String? ?? 'Other';
        final itemId = (item['item_id'] as num?)?.toInt() ?? 0;
        final colorId = (item['color_id'] as num?)?.toInt();
        final qty = (item['quantity'] as num?)?.toDouble() ?? 0.0;
        final unitPrice = (item['unit_price'] as num?)?.toDouble() ?? 0.0;
        final itemCode = item['item_code']?.toString() ?? '';
        final itemName = item['item_name']?.toString() ?? '';

        if (itemId > 0 && qty > 0) {
          // 1-2. Both legs of the transfer, written together and sharing
          // one transfer id: out of the store, into the workshop.
          final label = itemCode.isEmpty ? itemName : itemCode;
          await _postStockMovement(
            txn,
            itemId: itemId,
            itemType: itemType,
            colorId: colorId,
            locationId: storeLocationId,
            quantity: -qty,
            transactionType: 'Internal Transfer Out (Store -> Workshop)',
            movementType: SqlDatabase.movementInternalTransfer,
            actor: actor,
            timestamp: now,
            unitCost: unitPrice,
            toLocationId: destLocationId,
            transferId: transferId,
            documentType: 'sale',
            documentId: saleId,
            linkedDocumentType: 'purchase',
            linkedDocumentId: achatId,
            label: label,
          );
          await _postStockMovement(
            txn,
            itemId: itemId,
            itemType: itemType,
            colorId: colorId,
            locationId: destLocationId,
            quantity: qty,
            transactionType: 'Internal Transfer In (Store -> Workshop)',
            movementType: SqlDatabase.movementInternalTransfer,
            actor: actor,
            timestamp: now,
            unitCost: unitPrice,
            fromLocationId: storeLocationId,
            transferId: transferId,
            documentType: 'purchase',
            documentId: achatId,
            linkedDocumentType: 'sale',
            linkedDocumentId: saleId,
            label: label,
          );

          // 3. Insert into Achat_items for workshop
          await txn.insert(
            'Achat_items',
            SqlDatabase._withDistributedId({
              'achat_id': achatId,
              'item_id': itemId,
              'item_code': itemCode,
              'item_name': itemName,
              'item_type': itemType,
              'color_id': colorId,
              'quantity': qty,
              'price': unitPrice,
              'total_price': qty * unitPrice,
              'received_quantity': qty,
              'created_at': now,
            }),
          );
        }
      }

      // Update MaterialSales header
      await txn.update(
        'MaterialSales',
        {
          'status': 'delivered',
          'dest_location_id': destLocationId,
          'stock_deducted': 1,
          'linked_achat_id': achatId,
          'is_internal': 1,
          'updated_at': now,
        },
        where: 'id = ?',
        whereArgs: [saleId],
      );

      return achatId;
    });

    CloudSyncService().notifyChange();
    return createdAchatId;
  }

  /// Reverses an internal sale transfer and documents counter-movements.
  Future<void> cancelOrReverseInternalMaterialSaleTransfer({
    required int saleId,
  }) async {
    final myDb = await db;
    if (myDb == null) return;
    await _ensureRemnantInventorySchema(myDb);
    final actor = await _currentStockActor();
    await myDb.transaction(
      (txn) => _reverseInternalMaterialSaleTransfer(txn, saleId, actor),
    );
    CloudSyncService().notifyChange();
  }

  /// Body of [cancelOrReverseInternalMaterialSaleTransfer], so other document
  /// operations can include the reversal in their own transaction.
  Future<void> _reverseInternalMaterialSaleTransfer(
    DatabaseExecutor txn,
    int saleId,
    ({String? uid, String name}) actor,
  ) async {
    final saleRows = await txn.query(
      'MaterialSales',
      where: 'id = ?',
      whereArgs: [saleId],
    );
    if (saleRows.isEmpty) return;
    final sale = saleRows.first;
    final storeLocationId = (sale['location_id'] as num?)?.toInt() ?? 1;
    final destLocationId = (sale['dest_location_id'] as num?)?.toInt();
    final linkedAchatId = (sale['linked_achat_id'] as num?)?.toInt();
    final stockDeducted = (sale['stock_deducted'] as num?)?.toInt() ?? 0;
    final now = DateTime.now().toUtc().toIso8601String();

    if (stockDeducted == 1 && destLocationId != null) {
      final items = await txn.query(
        'MaterialSaleItems',
        where: 'sale_id = ?',
        whereArgs: [saleId],
      );
      for (final item in items) {
        final itemType = item['item_type'] as String? ?? 'Other';
        final itemId = (item['item_id'] as num?)?.toInt() ?? 0;
        final colorId = (item['color_id'] as num?)?.toInt();
        final qty = (item['quantity'] as num?)?.toDouble() ?? 0.0;

        if (itemId > 0 && qty > 0) {
          // Both reverse legs share a new transfer id: out of the workshop
          // first (it must still hold the quantity), back into the store.
          final transferId = SqlDatabase._newTransferId();
          final label = (item['item_code'] ?? item['item_name'])?.toString();
          try {
            await _postStockMovement(
              txn,
              itemId: itemId,
              itemType: itemType,
              colorId: colorId,
              locationId: destLocationId,
              quantity: -qty,
              transactionType: 'Reversal: Internal Return Out of Workshop',
              movementType: SqlDatabase.movementInternalTransfer,
              actor: actor,
              timestamp: now,
              toLocationId: storeLocationId,
              transferId: transferId,
              documentType: linkedAchatId == null ? 'sale' : 'purchase',
              documentId: linkedAchatId ?? saleId,
              linkedDocumentType: 'sale',
              linkedDocumentId: saleId,
              reason: 'إلغاء التحويل الداخلي',
              label: label,
            );
          } on StateError catch (error) {
            throw StateError(
              'لا يمكن إلغاء التحويل لأن الورشة استهلكت جزءاً من الكمية أو حجزته. ${error.message}',
            );
          }
          await _postStockMovement(
            txn,
            itemId: itemId,
            itemType: itemType,
            colorId: colorId,
            locationId: storeLocationId,
            quantity: qty,
            transactionType: 'Reversal: Internal Return (Workshop -> Store)',
            movementType: SqlDatabase.movementInternalTransfer,
            actor: actor,
            timestamp: now,
            fromLocationId: destLocationId,
            transferId: transferId,
            documentType: 'sale',
            documentId: saleId,
            linkedDocumentType: linkedAchatId == null ? null : 'purchase',
            linkedDocumentId: linkedAchatId,
            reason: 'إلغاء التحويل الداخلي',
            label: label,
          );
        }
      }
    }

    await txn.update(
      'MaterialSales',
      {'status': 'cancelled', 'updated_at': now},
      where: 'id = ?',
      whereArgs: [saleId],
    );

    if (linkedAchatId != null) {
      await txn.update(
        'Achats',
        {'status': 'Cancelled', 'updated_at': now},
        where: 'id = ?',
        whereArgs: [linkedAchatId],
      );
    }
  }
}
