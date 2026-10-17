part of '../sql_database.dart';

/// Purchases (achats) and suppliers.
extension SqlDatabasePurchases on SqlDatabase {
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

  Future<int> insertAchat(
    String invoiceNumber,
    String supplierName,
    double total, {
    int? supplierId,
    int? locationId,
    String? imagePath,
    String? pdfPath,
    String? createdAt,
    bool isWorkshop = true,
    String activityType = 'workshop',
    bool isInternal = false,
    int? linkedSaleId,
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
        'رقم الفاتورة ($invoiceNumber) مستخدم بالفعل! يرجى اختيار رقم آخر.',
      );
    }

    final now = DateTime.now().toUtc().toIso8601String();
    final author = await _currentOrderEditor();
    var res = await myDb.insert(
      'Achats',
      SqlDatabase._withDistributedId({
        'invoice_number': invoiceNumber,
        'supplier_name': supplierName,
        'supplier_id': supplierId,
        'location_id': locationId,
        'status': 'Active',
        'total': total,
        'image_path': imagePath,
        'pdf_path': pdfPath,
        'activity_type': activityType,
        'is_workshop': isWorkshop ? 1 : 0,
        'is_internal': isInternal ? 1 : 0,
        'linked_sale_id': linkedSaleId,
        'created_at': createdAt ?? now,
        'inserted_at': now,
        'updated_at': now,
        'created_by': author,
        'updated_by': author,
      }),
    );
    CloudSyncService().notifyChange();
    unawaited(
      _recordDashboardActivity(
        activityType: 'purchase_added',
        entityId: res,
        document: invoiceNumber,
        party: supplierName,
        userName: author,
      ),
    );
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

  /// Returns the most recently entered purchase price for a catalogue item.
  /// Purchase history is deliberately kept separate from catalogue prices.
  Future<double?> getLatestPurchasePrice({
    required int itemId,
    required String itemType,
    int? colorId,
  }) async {
    final myDb = await db;
    if (myDb == null) return null;
    final typeAliases = <String>{itemType};
    if (itemType == 'Accessories' || itemType == 'Accessory') {
      typeAliases.addAll(['Accessories', 'Accessory']);
    }
    if (itemType == 'Sections' ||
        itemType == 'Section' ||
        itemType == 'Profiles' ||
        itemType == 'Profile') {
      typeAliases.addAll(['Sections', 'Section', 'Profiles', 'Profile']);
    }
    if (itemType == 'ShutterComponents' || itemType == 'ShutterComponent') {
      typeAliases.addAll(['ShutterComponents', 'ShutterComponent']);
    }
    if (itemType == 'Joints' || itemType == 'Joint') {
      typeAliases.addAll(['Joints', 'Joint']);
    }
    if (itemType == 'Glass') {
      typeAliases.addAll(['Glass', 'glass']);
    }
    final typeMarks = List.filled(typeAliases.length, '?').join(', ');
    final rows = await myDb.query(
      'Achat_items',
      columns: const ['price'],
      where: colorId == null
          ? 'item_id = ? AND item_type IN ($typeMarks) AND (color_id IS NULL OR color_id = 0)'
          : 'item_id = ? AND item_type IN ($typeMarks) AND color_id = ?',
      whereArgs: colorId == null
          ? [itemId, ...typeAliases]
          : [itemId, ...typeAliases, colorId],
      orderBy: 'id DESC',
      limit: 1,
    );
    if (rows.isNotEmpty) {
      final value = rows.first['price'];
      final parsed = value is num
          ? value.toDouble()
          : double.tryParse('$value');
      if (parsed != null && parsed > 0) return parsed;
    }

    // Fallback: If no purchase with the exact color was found, get the latest
    // purchase price of this item regardless of color
    if (colorId != null) {
      final fallbackRows = await myDb.query(
        'Achat_items',
        columns: const ['price'],
        where: 'item_id = ? AND item_type IN ($typeMarks)',
        whereArgs: [itemId, ...typeAliases],
        orderBy: 'id DESC',
        limit: 1,
      );
      if (fallbackRows.isNotEmpty) {
        final value = fallbackRows.first['price'];
        final parsed = value is num
            ? value.toDouble()
            : double.tryParse('$value');
        if (parsed != null && parsed > 0) return parsed;
      }
    }
    return null;
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
      SqlDatabase._withDistributedId({
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
    final current = await myDb!.query(
      'Achat_items',
      columns: ['achat_id'],
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    final achatId = current.isEmpty
        ? null
        : (current.first['achat_id'] as num?)?.toInt();
    if (achatId != null) {
      await snapshotAchat(
        achatId,
        actionType: 'UPDATE',
        afterHeader: {'changed_item_id': id, ...data},
      );
    }
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
    await snapshotAchat(
      id,
      actionType: 'UPDATE',
      afterHeader: {'status': status},
    );
    var res = await myDb!.update(
      'Achats',
      {
        'status': status,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
        'updated_by': await _currentOrderEditor(),
      },
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
    await snapshotAchat(
      id,
      actionType: 'UPDATE',
      afterHeader: {
        'invoice_number': invoiceNumber,
        'supplier_name': supplierName,
      },
    );
    var res = await myDb!.update(
      'Achats',
      {
        'invoice_number': invoiceNumber,
        'supplier_name': supplierName,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
        'updated_by': await _currentOrderEditor(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    CloudSyncService().notifyChange();
    return res;
  }

  Future<int> updateAchatDate(int id, String createdAt) async {
    Database? myDb = await db;
    await snapshotAchat(
      id,
      actionType: 'UPDATE',
      afterHeader: {'created_at': createdAt},
    );
    final res = await myDb!.update(
      'Achats',
      {
        'created_at': createdAt,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
        'updated_by': await _currentOrderEditor(),
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
    data['updated_at'] = DateTime.now().toUtc().toIso8601String();
    data['updated_by'] = await _currentOrderEditor();
    await snapshotAchat(
      id,
      actionType: 'UPDATE',
      afterHeader: Map<String, dynamic>.from(data),
    );
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

  Future<bool> achatInvoiceNumberExists(String invoiceNumber) async {
    Database? myDb = await db;
    if (myDb == null) return false;
    final rows = await myDb.query(
      'Achats',
      columns: ['id'],
      where: 'invoice_number = ?',
      whereArgs: [invoiceNumber],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  Future<String> getNextAchatInvoiceNumber() async {
    Database? myDb = await db;
    if (myDb == null) return 'ACH-0001';
    final rows = await myDb.query('Achats', columns: ['invoice_number']);
    int maxSuffix = 0;
    final regex = RegExp(r'(\d+)');
    final existingSet = <String>{};

    for (final row in rows) {
      final invoice = (row['invoice_number'] ?? '').toString().trim();
      if (invoice.isNotEmpty) {
        existingSet.add(invoice.toUpperCase());
      }
      for (final match in regex.allMatches(invoice)) {
        final suffix = int.tryParse(match.group(1)!) ?? 0;
        if (suffix > maxSuffix) {
          maxSuffix = suffix;
        }
      }
    }

    int candidate = maxSuffix + 1;
    while (true) {
      final numStr = 'ACH-${candidate.toString().padLeft(4, '0')}';
      final upper = numStr.toUpperCase();
      if (!existingSet.contains(upper) &&
          !existingSet.contains('$upper-M') &&
          !existingSet.contains('$upper-G')) {
        return numStr;
      }
      candidate++;
    }
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
    if (CloudSyncService.supabaseWorkshopDataOnly) return 1;

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

  Future<int> deleteAchatToTrash(int id) async {
    Database? myDb = await db;
    if (myDb == null) return 0;
    await _ensureAchatTrashInfrastructure(myDb);
    final achatRows = await myDb.query(
      'Achats',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (achatRows.isEmpty) return 0;
    final achat = achatRows.first;
    final previousStatus = achat['status']?.toString() ?? 'Active';
    final reversesStock =
        previousStatus == 'Confirmed' || previousStatus == 'Partial Returned';
    final now = DateTime.now().toUtc().toIso8601String();
    final deletedBy = await _currentOrderEditor();
    await snapshotAchat(id, actionType: 'DELETE');
    final res = await myDb.transaction<int>((txn) async {
      if (reversesStock) {
        final items = await txn.query(
          'Achat_items',
          where: 'achat_id = ?',
          whereArgs: [id],
        );
        final locationId = (achat['location_id'] as num?)?.toInt() ?? 1;
        for (final item in items) {
          final itemId = (item['item_id'] as num?)?.toInt() ?? 0;
          final itemType = item['item_type']?.toString() ?? '';
          final colorId = (item['color_id'] as num?)?.toInt();
          final qty = (item['quantity'] as num?)?.toDouble() ?? 0;
          final where = colorId == null
              ? 'item_id = ? AND item_type = ? AND color_id IS NULL AND location_id = ?'
              : 'item_id = ? AND item_type = ? AND color_id = ? AND location_id = ?';
          final args = colorId == null
              ? [itemId, itemType, locationId]
              : [itemId, itemType, colorId, locationId];
          final stock = await txn.query(
            'CurrentStock',
            where: where,
            whereArgs: args,
            limit: 1,
          );
          final available = stock.isEmpty
              ? 0.0
              : (stock.first['quantity'] as num?)?.toDouble() ?? 0;
          if (available + 0.000001 < qty) {
            throw StateError(
              'لا يمكن حذف فاتورة الشراء لأن جزءاً من مخزون ${item['item_name'] ?? item['item_code'] ?? 'العنصر'} قد تم استهلاكه.',
            );
          }
          await txn.update(
            'CurrentStock',
            {'quantity': available - qty, 'updated_at': now},
            where: where,
            whereArgs: args,
          );
          await txn.insert(
            'InventoryTransactions',
            SqlDatabase._withDistributedId({
              'item_id': itemId,
              'item_type': itemType,
              'color_id': colorId,
              'location_id': locationId,
              'quantity': -qty,
              'transaction_type': 'Purchase Soft Delete Reversal',
              'reference_id': id,
              'created_at': now,
            }),
          );
        }
      }
      return txn.update(
        'Achats',
        {
          'is_deleted': 1,
          'deleted_at': now,
          'deleted_by': deletedBy,
          'status_before_delete': previousStatus,
          'stock_reversed_on_delete': reversesStock ? 1 : 0,
          'status': 'Cancelled',
          'updated_at': now,
        },
        where: 'id = ?',
        whereArgs: [id],
      );
    });
    CloudSyncService().notifyChangeImmediate();
    await logAuditAction(
      actionType: 'DELETE',
      entityType: 'purchase',
      entityId: id.toString(),
      entityTitle: 'فاتورة شراء #$id',
      details: 'تم نقل فاتورة الشراء إلى سلة المحذوفات.',
    );
    return res;
  }

  Future<int> restoreAchat(int id) async {
    Database? myDb = await db;
    if (myDb == null) return 0;
    await _ensureAchatTrashInfrastructure(myDb);
    final rows = await myDb.query(
      'Achats',
      where: 'id = ? AND is_deleted = 1',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return 0;
    final achat = rows.first;
    final restoreStock =
        (achat['stock_reversed_on_delete'] as num?)?.toInt() == 1;
    final previousStatus =
        achat['status_before_delete']?.toString() ?? 'Active';
    final now = DateTime.now().toUtc().toIso8601String();
    final res = await myDb.transaction<int>((txn) async {
      if (restoreStock) {
        final items = await txn.query(
          'Achat_items',
          where: 'achat_id = ?',
          whereArgs: [id],
        );
        final locationId = (achat['location_id'] as num?)?.toInt() ?? 1;
        for (final item in items) {
          final itemId = (item['item_id'] as num?)?.toInt() ?? 0;
          final itemType = item['item_type']?.toString() ?? '';
          final colorId = (item['color_id'] as num?)?.toInt();
          final qty = (item['quantity'] as num?)?.toDouble() ?? 0;
          final where = colorId == null
              ? 'item_id = ? AND item_type = ? AND color_id IS NULL AND location_id = ?'
              : 'item_id = ? AND item_type = ? AND color_id = ? AND location_id = ?';
          final args = colorId == null
              ? [itemId, itemType, locationId]
              : [itemId, itemType, colorId, locationId];
          final stock = await txn.query(
            'CurrentStock',
            where: where,
            whereArgs: args,
            limit: 1,
          );
          if (stock.isEmpty) {
            await txn.insert(
              'CurrentStock',
              SqlDatabase._withDistributedId({
                'item_id': itemId,
                'item_type': itemType,
                'color_id': colorId,
                'location_id': locationId,
                'quantity': qty,
                'updated_at': now,
              }),
            );
          } else {
            final current = (stock.first['quantity'] as num?)?.toDouble() ?? 0;
            await txn.update(
              'CurrentStock',
              {'quantity': current + qty, 'updated_at': now},
              where: where,
              whereArgs: args,
            );
          }
          await txn.insert(
            'InventoryTransactions',
            SqlDatabase._withDistributedId({
              'item_id': itemId,
              'item_type': itemType,
              'color_id': colorId,
              'location_id': locationId,
              'quantity': qty,
              'transaction_type': 'Purchase Restore',
              'reference_id': id,
              'created_at': now,
            }),
          );
        }
      }
      return txn.update(
        'Achats',
        {
          'is_deleted': 0,
          'deleted_at': null,
          'deleted_by': null,
          'status': previousStatus,
          'stock_reversed_on_delete': 0,
          'updated_at': now,
        },
        where: 'id = ?',
        whereArgs: [id],
      );
    });
    if (res > 0) {
      try {
        await myDb.delete(
          'SyncTombstones',
          where: 'table_name = ? AND (row_id = ? OR row_id = ?)',
          whereArgs: ['Achats', id.toString(), id],
        );
      } catch (_) {}
      CloudSyncService().notifyChangeImmediate();
      await logAuditAction(
        actionType: 'RESTORE',
        entityType: 'purchase',
        entityId: id.toString(),
        entityTitle: 'فاتورة شراء #$id',
        details: 'تم استرجاع فاتورة الشراء من سلة المحذوفات.',
      );
    }
    return res;
  }

  Future<List<Map<String, dynamic>>> readTrashAchats() async {
    Database? myDb = await db;
    if (myDb == null) return [];
    await _ensureAchatTrashInfrastructure(myDb);
    return await myDb.rawQuery(
      'SELECT * FROM Achats WHERE is_deleted = 1 ORDER BY deleted_at DESC, created_at DESC',
    );
  }

  Future<int> countTrashAchats() async {
    Database? myDb = await db;
    if (myDb == null) return 0;
    await _ensureAchatTrashInfrastructure(myDb);
    final res = await myDb.rawQuery(
      'SELECT COUNT(*) as count FROM Achats WHERE is_deleted = 1',
    );
    if (res.isEmpty) return 0;
    return (res.first['count'] as num?)?.toInt() ?? 0;
  }

  Future<int> emptyAchatTrash() async {
    Database? myDb = await db;
    if (myDb == null) return 0;
    await _ensureAchatTrashInfrastructure(myDb);
    final trashed = await readTrashAchats();
    int count = 0;
    for (final a in trashed) {
      final id = a['id'] as int?;
      if (id != null) {
        try {
          await deleteAchat(id);
          count++;
        } catch (_) {}
      }
    }
    return count;
  }

  Future<List<Map<String, dynamic>>> readAchats({
    bool? isWorkshop,
    String? activityType,
  }) async {
    Database? myDb = await db;
    if (myDb == null) return [];
    await _ensureAchatTrashInfrastructure(myDb);
    final whereClauses = <String>['is_deleted IS NULL OR is_deleted = 0'];
    final whereArgs = <dynamic>[];
    if (isWorkshop != null) {
      if (isWorkshop) {
        whereClauses.add('(is_workshop = 1 OR is_workshop IS NULL)');
      } else {
        whereClauses.add('is_workshop = 0');
      }
    }
    if (activityType != null && activityType.isNotEmpty) {
      whereClauses.add('activity_type = ?');
      whereArgs.add(activityType);
    }
    return await myDb.query(
      'Achats',
      where: whereClauses.join(' AND '),
      whereArgs: whereArgs.isEmpty ? null : whereArgs,
      orderBy: 'created_at DESC',
    );
  }

  Future<List<Map<String, dynamic>>> readWorkshopAchats() =>
      readAchats(isWorkshop: true);

  Future<List<Map<String, dynamic>>> readStoreAchats() =>
      readAchats(isWorkshop: false);

  Future<List<Map<String, dynamic>>> readAchatsBySupplierName(
    String supplierName, {
    bool? isWorkshop,
  }) async {
    Database? myDb = await db;
    if (myDb == null) return [];
    await _ensureAchatTrashInfrastructure(myDb);
    final clauses = <String>[
      'supplier_name = ?',
      '(is_deleted IS NULL OR is_deleted = 0)',
      if (isWorkshop == true) '(is_workshop = 1 OR is_workshop IS NULL)',
      if (isWorkshop == false) 'is_workshop = 0',
    ];
    return await myDb.query(
      'Achats',
      where: clauses.join(' AND '),
      whereArgs: [supplierName],
      orderBy: 'created_at DESC',
    );
  }

  Future<List<Map<String, dynamic>>> readAchatsBySupplier(
    int supplierId,
  ) async {
    Database? myDb = await db;
    if (myDb == null) return [];
    await _ensureAchatTrashInfrastructure(myDb);
    return await myDb.query(
      'Achats',
      where: 'supplier_id = ? AND (is_deleted IS NULL OR is_deleted = 0)',
      whereArgs: [supplierId],
      orderBy: 'created_at DESC',
    );
  }

  Future<int> updateAchatTotal(int achatId, double total) async {
    Database? myDb = await db;
    await snapshotAchat(
      achatId,
      actionType: 'UPDATE',
      afterHeader: {'total': total},
    );
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
        'updated_at': DateTime.now().toUtc().toIso8601String(),
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
    await snapshotAchat(
      achatId,
      actionType: 'RETURN',
      afterHeader: {
        'returned_items': returnedItems,
        'refunded_amount': refundedAmount,
      },
    );

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
        SqlDatabase._withDistributedId({
          'transaction_type': 'Encaissement',
          'amount': refundedAmount,
          'description': 'استرجاع من المورد - فاتورة مشتريات رقم $achatId',
          'reference_id': achatId,
          'entity_type': 'Supplier',
          'entity_id': supplierId,
          'recorded_by': 'system',
          'created_at': DateTime.now().toUtc().toIso8601String(),
          'old_balance': 0.0,
          'new_balance': 0.0,
          'caisse_name': 'الصندوق الرئيسي',
          'payment_method': 'نقداً / Espèce',
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
          'updated_at': DateTime.now().toUtc().toIso8601String(),
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
      final purchaseId = (item['achat_id'] as num?)?.toInt();
      if (purchaseId != null) {
        await snapshotAchat(
          purchaseId,
          actionType: 'UPDATE',
          afterHeader: {'deleted_item_id': id},
        );
      }
      final achatRows = await myDb.query(
        'Achats',
        columns: ['status', 'location_id'],
        where: 'id = ?',
        whereArgs: [item['achat_id']],
        limit: 1,
      );
      final status = achatRows.isEmpty
          ? ''
          : achatRows.first['status']?.toString() ?? '';
      // Draft/active purchase lines have never entered inventory. Only posted
      // purchases may reverse stock, and always at their real location.
      if (status == 'Confirmed' || status == 'Partial Returned') {
        final qty = (item['quantity'] as num).toDouble();
        final locationId = achatRows.isEmpty
            ? 1
            : (achatRows.first['location_id'] as num?)?.toInt() ?? 1;
        await updateInventory(
          itemId: item['item_id'] as int,
          itemType: item['item_type'] as String,
          colorId: item['color_id'] as int?,
          locationId: locationId,
          quantityChange: -qty,
          transactionType: 'Purchase Item Deleted',
          referenceId: item['achat_id'] as int,
        );
      }
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
      SqlDatabase._withDistributedId({
        'name': data['name'] ?? '',
        'phone': data['phone'] ?? '',
        'email': data['email'] ?? '',
        'notes': data['notes'] ?? '',
        'latitude': data['latitude'],
        'longitude': data['longitude'],
        'created_at': DateTime.now().toUtc().toIso8601String(),
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

  Future<void> snapshotAchat(
    int achatId, {
    required String actionType,
    Map<String, dynamic>? afterHeader,
    List<Map<String, dynamic>>? afterItems,
  }) async {
    final database = await db;
    if (database == null) return;
    final headers = await database.query(
      'Achats',
      where: 'id = ?',
      whereArgs: [achatId],
      limit: 1,
    );
    if (headers.isEmpty) return;
    final items = await database.query(
      'Achat_items',
      where: 'achat_id = ?',
      whereArgs: [achatId],
      orderBy: 'id ASC',
    );
    final header = Map<String, dynamic>.from(headers.first);
    await logAuditAction(
      actionType: actionType,
      entityType: 'purchase',
      entityId: achatId.toString(),
      entityTitle: 'فاتورة شراء ${header['invoice_number'] ?? achatId}',
      details: jsonEncode({
        'before': {
          'header': header,
          'items': items.map((e) => Map<String, dynamic>.from(e)).toList(),
        },
        if (afterHeader != null || afterItems != null)
          'after': {
            if (afterHeader != null) 'header': afterHeader,
            if (afterItems != null) 'items': afterItems,
          },
      }),
    );
  }
}
