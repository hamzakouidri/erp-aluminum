part of '../sql_database.dart';

/// Treasury, cash boxes, payments, balances and day closing.
extension SqlDatabaseFinance on SqlDatabase {
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
    var changedAnyName = false;
    final canonicalIds = <String, dynamic>{};
    for (final row in rows) {
      final rawName = row['name']?.toString() ?? '';
      final id = row['id'];
      if (id == null) continue;
      final repairedName = SqlDatabase._repairLegacyTextEncoding(rawName).trim();
      final canonicalName = SqlDatabase._canonicalCaisseName(repairedName);

      if (canonicalName != null) {
        final firstId = canonicalIds[canonicalName];
        if (firstId != null) {
          // Old launches could create the same default caisse more than once.
          // Keep the first row and move its movements before removing the
          // duplicate, so the financial history is preserved.
          await myDb.update(
            'Treasury',
            {'caisse_name': canonicalName},
            where: 'caisse_name = ?',
            whereArgs: [rawName],
          );
          await myDb.delete('Caisses', where: 'id = ?', whereArgs: [id]);
          changedAnyName = true;
          continue;
        }
        final existingCanonical = await myDb.query(
          'Caisses',
          columns: ['id'],
          where: 'name = ?',
          whereArgs: [canonicalName],
          limit: 1,
        );
        final existingCanonicalId = existingCanonical.isEmpty
            ? null
            : existingCanonical.first['id'];
        if (existingCanonicalId != null && existingCanonicalId != id) {
          await myDb.update(
            'Treasury',
            {'caisse_name': canonicalName},
            where: 'caisse_name = ?',
            whereArgs: [rawName],
          );
          await myDb.delete('Caisses', where: 'id = ?', whereArgs: [id]);
          changedAnyName = true;
          continue;
        }
        canonicalIds[canonicalName] = id;
        if (rawName != canonicalName) {
          await myDb.update(
            'Caisses',
            {'name': canonicalName},
            where: 'id = ?',
            whereArgs: [id],
          );
          await myDb.update(
            'Treasury',
            {'caisse_name': canonicalName},
            where: 'caisse_name = ?',
            whereArgs: [rawName],
          );
          changedAnyName = true;
        }
        continue;
      }

      if (SqlDatabase._looksLikeUnreadableCaisseName(rawName) ||
          SqlDatabase._looksLikeUnreadableCaisseName(repairedName)) {
        // These rows are encoding/identifier artefacts, not a user-created
        // caisse. Reassign their movements before removing the artefact.
        await myDb.update(
          'Treasury',
          {'caisse_name': SqlDatabase._mainCaisseName},
          where: 'caisse_name = ?',
          whereArgs: [rawName],
        );
        await myDb.delete('Caisses', where: 'id = ?', whereArgs: [id]);
        changedAnyName = true;
        continue;
      }

      if (rawName != repairedName && repairedName.isNotEmpty) {
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
        changedAnyName = true;
      }
    }
    if (changedAnyName) {
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
      SqlDatabase._withDistributedId({'name': name}),
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

  //////////////////////////////////// Treasury //////////////////////////////////////
  Future<List<Map<String, dynamic>>> readTreasury() async {
    Database? myDb = await db;
    return await myDb!.query('Treasury', orderBy: 'created_at DESC');
  }

  Future<void> _insertPaymentAllocation(
    DatabaseExecutor executor, {
    required int treasuryId,
    required String documentType,
    required int documentId,
    required double amount,
  }) async {
    if (amount <= SqlDatabase._paymentTolerance) return;
    await executor.insert(
      'PaymentAllocations',
      SqlDatabase._withDistributedId({
        'treasury_id': treasuryId,
        'document_type': documentType,
        'document_id': documentId,
        'amount': amount,
        'created_at': DateTime.now().toUtc().toIso8601String(),
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
      where: 'client_id = ? AND (is_deleted IS NULL OR is_deleted = 0)',
      whereArgs: [clientId],
      orderBy: 'created_at ASC, id ASC',
    );
    // A receipt attached to a trashed order stays stored for a possible
    // restore, but it must not become client credit nor be allocated to a
    // different active order.
    final allTransactions = await executor.rawQuery(
      '''
      SELECT t.* FROM Treasury t
      LEFT JOIN Commandes c ON c.id = t.reference_id
      WHERE t.entity_type = ? AND t.entity_id = ?
        AND (t.reference_id IS NULL OR c.id IS NULL
             OR c.is_deleted IS NULL OR c.is_deleted = 0)
        AND (t.document_type IS NULL OR t.document_type != ?)
      ORDER BY t.created_at ASC, t.id ASC
      ''',
      ['Client', clientId, SqlDatabase.materialSaleDocumentType],
    );
    final receipts = allTransactions.where(SqlDatabase._isClientReceipt).toList();

    // Bring forward only the part of historic advances that has no matching
    // cash receipt yet. This avoids the old duplicate-migration behaviour.
    var missingLegacy =
        orders.fold<double>(
          0.0,
          (sum, row) => sum + SqlDatabase._paymentNumber(row['advance_payment']),
        ) -
        receipts.fold<double>(
          0.0,
          (sum, row) => sum + SqlDatabase._paymentNumber(row['amount']),
        );
    if (missingLegacy > SqlDatabase._paymentTolerance) {
      for (final order in orders) {
        if (missingLegacy <= SqlDatabase._paymentTolerance) break;
        final orderId = SqlDatabase._paymentRecordId(order['id']);
        final recordedAdvance = SqlDatabase._paymentNumber(order['advance_payment']);
        if (orderId == null || recordedAdvance <= SqlDatabase._paymentTolerance) continue;
        final amount = recordedAdvance < missingLegacy
            ? recordedAdvance
            : missingLegacy;
        final legacyId = SqlDatabase._nextDistributedId();
        final createdAt = order['created_at']?.toString();
        final orderCode = _positiveInt(order['order_code']);
        final displayCode = (orderCode != null && orderCode > 0)
            ? orderCode
            : orderId;
        await executor.insert(
          'Treasury',
          SqlDatabase._withDistributedId({
            'id': legacyId,
            'transaction_type': 'Encaissement',
            'amount': amount,
            'description': 'ترحيل دفعة قديمة للطلبية #$displayCode',
            'reference_id': orderId,
            'recorded_by': 'migration',
            'entity_type': 'Client',
            'entity_id': clientId,
            'old_balance': 0.0,
            'new_balance': 0.0,
            'caisse_name': 'الصندوق الرئيسي',
            'payment_method': 'نقداً / Espèce',
            'created_at': (createdAt == null || createdAt.trim().isEmpty)
                ? DateTime.now().toUtc().toIso8601String()
                : createdAt,
          }),
        );
        receipts.add({
          'id': legacyId,
          'reference_id': orderId,
          'amount': amount,
          'created_at': createdAt ?? DateTime.now().toUtc().toIso8601String(),
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
          : (SqlDatabase._paymentRecordId(a['id']) ?? 0).compareTo(
              SqlDatabase._paymentRecordId(b['id']) ?? 0,
            );
    });
    final receiptIds = receipts
        .map((row) => SqlDatabase._paymentRecordId(row['id']))
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
      final net = SqlDatabase._paymentNumber(order['net_payable']);
      return net > 0 ? net : SqlDatabase._paymentNumber(order['total']);
    }

    for (final receipt in receipts) {
      final treasuryId = SqlDatabase._paymentRecordId(receipt['id']);
      if (treasuryId == null) continue;
      var amountLeft = SqlDatabase._paymentNumber(receipt['amount']);
      final preferredId = SqlDatabase._paymentRecordId(receipt['reference_id']);
      final referencedOrders = orders
          .where((row) => SqlDatabase._paymentRecordId(row['id']) == preferredId)
          .toList();
      // Settle the selected order first. Any excess is a real Treasury
      // receipt and becomes customer credit, so let it flow to the client's
      // other (including subsequently-created) open orders.
      final candidates = preferredId != null && referencedOrders.isNotEmpty
          ? <Map<String, dynamic>>[
              ...referencedOrders,
              ...orders.where(
                (row) => SqlDatabase._paymentRecordId(row['id']) != preferredId,
              ),
            ]
          : orders;
      for (final order in candidates) {
        if (amountLeft <= SqlDatabase._paymentTolerance) break;
        final orderId = SqlDatabase._paymentRecordId(order['id']);
        if (orderId == null) continue;
        final due = orderTotal(order) - (settledByOrder[orderId] ?? 0.0);
        if (due <= SqlDatabase._paymentTolerance) continue;
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
      final orderId = SqlDatabase._paymentRecordId(order['id']);
      if (orderId == null) continue;
      final total = orderTotal(order);
      final paid = (settledByOrder[orderId] ?? 0.0)
          .clamp(0.0, total)
          .toDouble();
      final paymentStatus =
          total > SqlDatabase._paymentTolerance && paid >= total - SqlDatabase._paymentTolerance
          ? 'Paid'
          : paid > SqlDatabase._paymentTolerance
          ? 'Partial'
          : 'Unpaid';
      if ((SqlDatabase._paymentNumber(order['advance_payment']) - paid).abs() <=
              SqlDatabase._paymentTolerance &&
          order['payment_status']?.toString() == paymentStatus) {
        continue;
      }
      await executor.update(
        'Commandes',
        {
          'advance_payment': paid,
          'payment_status': paymentStatus,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
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
    await _ensureAchatTrashInfrastructure(executor);
    // Invoices in the trash are cancelled: supplier payments must not be
    // allocated to them (the client ledger already skips deleted orders).
    final purchases = await executor.query(
      'Achats',
      where: 'supplier_id = ? AND (is_deleted IS NULL OR is_deleted = 0)',
      whereArgs: [supplierId],
      orderBy: 'created_at ASC, id ASC',
    );
    final allTransactions = await executor.query(
      'Treasury',
      where: 'entity_type = ? AND entity_id = ?',
      whereArgs: ['Supplier', supplierId],
      orderBy: 'created_at ASC, id ASC',
    );
    final payments = allTransactions.where(SqlDatabase._isSupplierPayment).toList();

    var missingLegacy =
        purchases.fold<double>(
          0.0,
          (sum, row) => sum + SqlDatabase._paymentNumber(row['paid_amount']),
        ) -
        payments.fold<double>(
          0.0,
          (sum, row) => sum + SqlDatabase._paymentNumber(row['amount']),
        );
    if (missingLegacy > SqlDatabase._paymentTolerance) {
      for (final purchase in purchases) {
        if (missingLegacy <= SqlDatabase._paymentTolerance) break;
        final purchaseId = SqlDatabase._paymentRecordId(purchase['id']);
        final recordedPaid = SqlDatabase._paymentNumber(purchase['paid_amount']);
        if (purchaseId == null || recordedPaid <= SqlDatabase._paymentTolerance) continue;
        final amount = recordedPaid < missingLegacy
            ? recordedPaid
            : missingLegacy;
        final legacyId = SqlDatabase._nextDistributedId();
        final createdAt = purchase['created_at']?.toString();
        await executor.insert(
          'Treasury',
          SqlDatabase._withDistributedId({
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
                ? DateTime.now().toUtc().toIso8601String()
                : createdAt,
          }),
        );
        payments.add({
          'id': legacyId,
          'reference_id': purchaseId,
          'amount': amount,
          'created_at': createdAt ?? DateTime.now().toUtc().toIso8601String(),
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
          : (SqlDatabase._paymentRecordId(a['id']) ?? 0).compareTo(
              SqlDatabase._paymentRecordId(b['id']) ?? 0,
            );
    });
    final paymentIds = payments
        .map((row) => SqlDatabase._paymentRecordId(row['id']))
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
      final treasuryId = SqlDatabase._paymentRecordId(payment['id']);
      if (treasuryId == null) continue;
      var amountLeft = SqlDatabase._paymentNumber(payment['amount']);
      final preferredId = SqlDatabase._paymentRecordId(payment['reference_id']);
      final referencedPurchases = purchases
          .where((row) => SqlDatabase._paymentRecordId(row['id']) == preferredId)
          .toList();
      final candidates = preferredId != null && referencedPurchases.isNotEmpty
          ? referencedPurchases
          : purchases;
      for (final purchase in candidates) {
        if (amountLeft <= SqlDatabase._paymentTolerance) break;
        final purchaseId = SqlDatabase._paymentRecordId(purchase['id']);
        if (purchaseId == null) continue;
        final total = SqlDatabase._paymentNumber(purchase['total']);
        final due = total - (settledByPurchase[purchaseId] ?? 0.0);
        if (due <= SqlDatabase._paymentTolerance) continue;
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
      final purchaseId = SqlDatabase._paymentRecordId(purchase['id']);
      if (purchaseId == null) continue;
      final total = SqlDatabase._paymentNumber(purchase['total']);
      final paid = (settledByPurchase[purchaseId] ?? 0.0)
          .clamp(0.0, total)
          .toDouble();
      final remaining = (total - paid).clamp(0.0, double.infinity).toDouble();
      if ((SqlDatabase._paymentNumber(purchase['paid_amount']) - paid).abs() <=
              SqlDatabase._paymentTolerance &&
          (SqlDatabase._paymentNumber(purchase['remaining_amount']) - remaining).abs() <=
              SqlDatabase._paymentTolerance) {
        continue;
      }
      await executor.update(
        'Achats',
        {
          'paid_amount': paid,
          'remaining_amount': remaining,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
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
        "DELETE FROM WorkerTransactions WHERE worker_uid IN ($placeholders) AND (created_at = ? OR amount = ? OR transaction_type = 'salary' OR note LIKE '%تسوية%')",
        [...allKeys, createdAt, amount],
      );
    } else {
      await myDb.rawDelete(
        "DELETE FROM WorkerTransactions WHERE worker_uid IN ($placeholders) AND (transaction_type = 'salary' OR note LIKE '%تسوية%')",
        allKeys,
      );
    }

    CloudSyncService().notifyChangeImmediate();
  }

  Future<void> _ensureTreasuryDocumentType(Database database) =>
      _ensureSchemaOnce(database, '_ensureTreasuryDocumentType', () async {
        var columnAdded = false;
        try {
          await database.execute(
            'ALTER TABLE Treasury ADD COLUMN document_type TEXT;',
          );
          columnAdded = true;
        } catch (_) {
          // The column already exists.
        }
        if (columnAdded) {
          await _separateLegacyShopReceipts(database);
        }
      });

  /// One-time repair of receipts recorded by the shop editor before
  /// `document_type` existed: they were also allocated to the client's window
  /// orders, which counted the same payment twice.
  Future<void> _separateLegacyShopReceipts(Database database) async {
    try {
      await _ensurePaymentAllocationSchema(database);
      await database.transaction((txn) async {
        final shopReceipts = await txn.rawQuery('''
          SELECT t.id, t.entity_id FROM Treasury t
          WHERE LOWER(TRIM(COALESCE(t.entity_type, ''))) = 'client'
            AND t.document_type IS NULL
            AND t.reference_id IN (SELECT id FROM MaterialSales)
            AND t.reference_id NOT IN (SELECT id FROM Commandes)
            AND (t.caisse_name = 'صندوق المحل'
                 OR t.description LIKE 'دفعة مبيعات مواد%')
        ''');
        if (shopReceipts.isEmpty) return;
        final receiptIds = [
          for (final row in shopReceipts) SqlDatabase._paymentRecordId(row['id']),
        ].whereType<int>().toList();
        final clientIds = {
          for (final row in shopReceipts) SqlDatabase._paymentRecordId(row['entity_id']),
        }.whereType<int>();
        for (var start = 0; start < receiptIds.length; start += 500) {
          final chunk = receiptIds.sublist(
            start,
            (start + 500).clamp(0, receiptIds.length),
          );
          final marks = List.filled(chunk.length, '?').join(', ');
          // Remove the shop money from the orders it was wrongly applied to;
          // the ledger rebuild below then recomputes the remaining payments.
          await txn.rawUpdate('''
            UPDATE Commandes SET advance_payment = MAX(0,
              COALESCE(advance_payment, 0) - COALESCE((
                SELECT SUM(pa.amount) FROM PaymentAllocations pa
                WHERE pa.document_type = 'Commande'
                  AND pa.document_id = Commandes.id
                  AND pa.treasury_id IN ($marks)
              ), 0))
            WHERE id IN (
              SELECT document_id FROM PaymentAllocations
              WHERE document_type = 'Commande' AND treasury_id IN ($marks)
            )
          ''', [...chunk, ...chunk]);
          await txn.rawDelete(
            'DELETE FROM PaymentAllocations WHERE treasury_id IN ($marks)',
            chunk,
          );
          await txn.rawUpdate(
            'UPDATE Treasury SET document_type = ? WHERE id IN ($marks)',
            [SqlDatabase.materialSaleDocumentType, ...chunk],
          );
        }
        for (final clientId in clientIds) {
          await _rebuildClientPaymentLedger(txn, clientId);
        }
      });
    } catch (error) {
      debugPrint('Legacy shop receipt separation skipped: $error');
    }
  }

  /// Sum of the treasury receipts recorded for a shop document.
  Future<double> materialSaleReceiptsTotal(int saleId) async {
    final myDb = await db;
    if (myDb == null) return 0.0;
    final rows = await myDb.rawQuery(
      'SELECT transaction_type, amount FROM Treasury '
      'WHERE document_type = ? AND reference_id = ?',
      [SqlDatabase.materialSaleDocumentType, saleId],
    );
    var total = 0.0;
    for (final row in rows) {
      final type = SqlDatabase._normalisedTreasuryType(
        row['transaction_type']?.toString() ?? '',
      );
      final amount = SqlDatabase._paymentNumber(row['amount']);
      total += type == 'encaissement' ? amount : -amount;
    }
    return total;
  }

  /// Records in the shop cash box the part of a shop document's paid amount
  /// that the user just added in the editor ([newPaid] − [previousPaid]),
  /// so the document and the cash box always agree. Only the increase made
  /// now is recorded: old documents whose paid amount predates the treasury
  /// link are left as they are.
  Future<void> recordMaterialSalePaidIncrease({
    required int saleId,
    required double previousPaid,
    required double newPaid,
    required String saleCode,
    int? clientId,
    String clientName = '',
    String clientPhone = '',
  }) async {
    final increase = newPaid - previousPaid;
    if (increase <= SqlDatabase._paymentTolerance) return;
    await insertTreasury(
      'encaissement',
      double.parse(increase.toStringAsFixed(2)),
      'دفعة مبيعات مواد: $saleCode ($clientName)',
      referenceId: saleId,
      recordedBy: 'user',
      entityType: 'Client',
      entityId: clientId,
      phone: clientPhone,
      caisseName: 'صندوق المحل',
      documentType: SqlDatabase.materialSaleDocumentType,
    );
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
    String? documentType,
  }) async {
    Database? myDb = await db;
    if (myDb == null) return 0;
    final transactionAt = createdAt ?? DateTime.now().toUtc().toIso8601String();
    final treasuryData = SqlDatabase._withDistributedId({
      if (documentType != null) 'document_type': documentType,
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
      'updated_at': transactionAt,
    });
    final res = await myDb.transaction((txn) async {
      await _ensurePaymentAllocationSchema(txn);
      final id = await txn.insert('Treasury', treasuryData);
      if (SqlDatabase._isClientReceipt(treasuryData) && entityId != null) {
        await _rebuildClientPaymentLedger(txn, entityId);
      } else if (SqlDatabase._isSupplierPayment(treasuryData) && entityId != null) {
        await _rebuildSupplierPaymentLedger(txn, entityId);
      }
      return id;
    });

    if (entityType == 'Worker' &&
        SqlDatabase._normalisedTreasuryType(transactionType) == 'decaissement' &&
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
            SqlDatabase._withDistributedId({
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
    final isPayment = entityType == 'Client' || entityType == 'Supplier';
    unawaited(
      WorkerPushNotificationService.instance
          .sendManagerEvent(
            eventType: isPayment ? 'payments' : 'cashbox',
            data: {
              'treasury_id': res.toString(),
              'transaction_type': transactionType,
              'amount': amount.toString(),
              'description': description,
            },
          )
          .catchError((_) {}),
    );
    return res;
  }

  Future<int> deleteTreasury(int id) async {
    Database? myDb = await db;
    if (myDb == null) return 0;

    // Legacy databases restored from Firebase can predate the generic sync
    // triggers. Ensure the infrastructure exists before deleting; otherwise
    // Supabase still owns a live copy and restores the transaction on the
    // next download.
    await _ensureSyncTombstoneInfrastructure(myDb);

    final List<Map<String, dynamic>> records = await myDb.query(
      'Treasury',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (records.isEmpty) return 0;
    final row = records.first;
    final amount = (row['amount'] as num?)?.toDouble() ?? 0.0;
    final entityId = SqlDatabase._paymentRecordId(row['entity_id']);
    final isClientReceipt = SqlDatabase._isClientReceipt(row);
    final isSupplierPayment = SqlDatabase._isSupplierPayment(row);

    final res = await myDb.transaction((txn) async {
      await _ensurePaymentAllocationSchema(txn);
      final deleted = await txn.delete(
        'Treasury',
        where: 'id = ?',
        whereArgs: [id],
      );
      if (deleted > 0) {
        final deletedAt = DateTime.now().toUtc().toIso8601String();
        // Write this explicitly as well as relying on the trigger. INSERT OR
        // REPLACE keeps it idempotent and guarantees migrated rows receive a
        // cloud deletion marker.
        await txn.insert('SyncTombstones', {
          'table_name': 'Treasury',
          'row_id': id.toString(),
          'deleted_at': deletedAt,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
        await txn.insert('_sync_change_log', {
          'table_name': 'Treasury',
          'row_id': id.toString(),
          'operation': 'delete',
          'changed_at': deletedAt,
          'revision': 1,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await txn.delete(
        'PaymentAllocations',
        where: 'treasury_id = ?',
        whereArgs: [id],
      );
      final saleId = SqlDatabase._paymentRecordId(row['reference_id']);
      if (deleted > 0 &&
          isClientReceipt &&
          row['document_type']?.toString() == SqlDatabase.materialSaleDocumentType &&
          saleId != null) {
        // The shop document loses the payment that was just removed from
        // the cash box, so both keep the same amount.
        await txn.rawUpdate(
          '''
          UPDATE MaterialSales
          SET paid_amount = MAX(0, paid_amount - ?),
              remaining_amount = MAX(0, net_total - MAX(0, paid_amount - ?)),
              updated_at = ?
          WHERE id = ?
          ''',
          [amount, amount, DateTime.now().toUtc().toIso8601String(), saleId],
        );
      }
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
    final entityId = SqlDatabase._paymentRecordId(row['entity_id']);
    final isClientReceipt = SqlDatabase._isClientReceipt(row);
    final isSupplierPayment = SqlDatabase._isSupplierPayment(row);

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
          'updated_at': DateTime.now().toUtc().toIso8601String(),
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
      FROM Commandes WHERE client_id = ? AND (is_deleted IS NULL OR is_deleted = 0)
      ''',
      [clientId],
    );
    final totalInvoices =
        (commandesRes.first['invoices'] as num?)?.toDouble() ?? 0.0;
    final transactions = await myDb.rawQuery(
      '''
      SELECT t.* FROM Treasury t
      LEFT JOIN Commandes c ON c.id = t.reference_id
      WHERE t.entity_type = ? AND t.entity_id = ?
        AND (t.reference_id IS NULL OR c.id IS NULL
             OR c.is_deleted IS NULL OR c.is_deleted = 0)
      ''',
      ['Client', clientId],
    );
    var receipts = 0.0;
    var refunds = 0.0;
    for (final row in transactions) {
      final amount = SqlDatabase._paymentNumber(row['amount']);
      final type = SqlDatabase._normalisedTreasuryType(
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

  Future<Map<String, double>> calculateBusinessDayReconciliation({
    required String businessDate,
    required String scope,
  }) async {
    final database = await db;
    if (database == null) return const {};
    await _ensureRemnantInventorySchema(database);
    final cashboxScope = scope == 'store'
        ? "AND caisse_name = 'صندوق المحل'"
        : "AND COALESCE(caisse_name, '') <> 'صندوق المحل'";
    final treasuryRows = await database.rawQuery(
      '''
      SELECT
        COALESCE(SUM(CASE
          WHEN LOWER(transaction_type) IN ('encaissement', 'income', 'receipt')
            THEN amount ELSE 0 END), 0) AS income_total,
        COALESCE(SUM(CASE
          WHEN LOWER(transaction_type) IN ('décaissement', 'decaissement', 'expense', 'payment')
            THEN amount ELSE 0 END), 0) AS expense_total
      FROM Treasury
      WHERE SUBSTR(created_at, 1, 10) = ?
        $cashboxScope
    ''',
      [businessDate],
    );
    final income =
        (treasuryRows.first['income_total'] as num?)?.toDouble() ?? 0;
    final expense =
        (treasuryRows.first['expense_total'] as num?)?.toDouble() ?? 0;
    final salesRows = scope == 'store'
        ? await database.rawQuery(
            '''
            SELECT COALESCE(SUM(net_total), 0) AS total
            FROM MaterialSales
            WHERE SUBSTR(sale_date, 1, 10) = ?
              AND COALESCE(is_deleted, 0) = 0
              AND status NOT IN ('draft', 'cancelled')
          ''',
            [businessDate],
          )
        : await database.rawQuery(
            '''
            SELECT COALESCE(SUM(COALESCE(net_payable, total, 0)), 0) AS total
            FROM Commandes
            WHERE SUBSTR(created_at, 1, 10) = ?
              AND COALESCE(is_deleted, 0) = 0
          ''',
            [businessDate],
          );
    return {
      'income': income,
      'expense': expense,
      'expected': income - expense,
      'sales': (salesRows.first['total'] as num?)?.toDouble() ?? 0,
    };
  }

  Future<void> closeBusinessDay({
    required String businessDate,
    required String scope,
    required double countedCash,
    String notes = '',
  }) async {
    final database = await db;
    if (database == null) return;
    await _ensureRemnantInventorySchema(database);
    final totals = await calculateBusinessDayReconciliation(
      businessDate: businessDate,
      scope: scope,
    );
    final expected = totals['expected'] ?? 0;
    final now = DateTime.now().toUtc().toIso8601String();
    final values = {
      'business_date': businessDate,
      'scope': scope,
      'expected_cash': expected,
      'counted_cash': countedCash,
      'difference': countedCash - expected,
      'sales_total': totals['sales'] ?? 0,
      'income_total': totals['income'] ?? 0,
      'expense_total': totals['expense'] ?? 0,
      'closed_by': await _currentOrderEditor(),
      'notes': notes,
      'updated_at': now,
    };
    await database.insert('BusinessDayClosings', {
      ...SqlDatabase._withDistributedId(values),
      'created_at': now,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    await logAuditAction(
      actionType: 'daily_close',
      entityType: scope == 'store' ? 'Store' : 'Workshop',
      entityId: businessDate,
      entityTitle: businessDate,
      details: jsonEncode(values),
    );
    CloudSyncService().notifyChangeImmediate();
  }

  /// Calculates the unified financial and profit margin report for the enterprise.
  /// Separates Workshop from Materials Store and strictly eliminates inter-unit
  /// transfer margins from the combined consolidated enterprise total.
  Future<Map<String, dynamic>> getEnterpriseUnifiedFinancialSummary({
    String? startDate,
    String? endDate,
  }) async {
    final myDb = await db;
    if (myDb == null) {
      return {
        'store_external_sales': 0.0,
        'store_external_paid': 0.0,
        'store_external_unpaid': 0.0,
        'store_internal_transfers': 0.0,
        'store_purchases': 0.0,
        'workshop_orders_revenue': 0.0,
        'workshop_orders_advances': 0.0,
        'workshop_orders_unpaid': 0.0,
        'workshop_external_purchases': 0.0,
        'workshop_internal_purchases': 0.0,
        'consolidated_revenue': 0.0,
        'consolidated_cash_collected': 0.0,
        'consolidated_external_purchases': 0.0,
        'consolidated_net_cash_flow': 0.0,
        'eliminated_internal_margin': 0.0,
      };
    }

    String whereOrders = 'is_deleted = 0';
    String whereMaterialSales = "status != 'cancelled'";
    String whereAchats = "status != 'Cancelled'";
    List<dynamic> argsOrders = [];
    List<dynamic> argsSales = [];
    List<dynamic> argsAchats = [];

    if (startDate != null && startDate.isNotEmpty) {
      whereOrders += ' AND created_at >= ?';
      whereMaterialSales += ' AND sale_date >= ?';
      whereAchats += ' AND created_at >= ?';
      argsOrders.add(startDate);
      argsSales.add(startDate);
      argsAchats.add(startDate);
    }
    if (endDate != null && endDate.isNotEmpty) {
      whereOrders += ' AND created_at <= ?';
      whereMaterialSales += ' AND sale_date <= ?';
      whereAchats += ' AND created_at <= ?';
      argsOrders.add(endDate);
      argsSales.add(endDate);
      argsAchats.add(endDate);
    }

    // 1. Material Store Sales
    final salesRows = await myDb.rawQuery(
      'SELECT is_internal, net_total, paid_amount, remaining_amount FROM MaterialSales WHERE $whereMaterialSales',
      argsSales,
    );
    double storeExternalSales = 0.0;
    double storeExternalPaid = 0.0;
    double storeExternalUnpaid = 0.0;
    double storeInternalTransfers = 0.0;

    for (final row in salesRows) {
      final isInternal = (row['is_internal'] as num?)?.toInt() == 1;
      final net = (row['net_total'] as num?)?.toDouble() ?? 0.0;
      final paid = (row['paid_amount'] as num?)?.toDouble() ?? 0.0;
      final remaining = (row['remaining_amount'] as num?)?.toDouble() ?? 0.0;
      if (isInternal) {
        storeInternalTransfers += net;
      } else {
        storeExternalSales += net;
        storeExternalPaid += paid;
        storeExternalUnpaid += remaining;
      }
    }

    // 2. Workshop Orders (Commandes)
    final orderRows = await myDb.rawQuery(
      'SELECT net_payable, total, advance_payment FROM Commandes WHERE $whereOrders',
      argsOrders,
    );
    double workshopOrdersRevenue = 0.0;
    double workshopOrdersAdvances = 0.0;

    for (final row in orderRows) {
      final net =
          (row['net_payable'] as num?)?.toDouble() ??
          (row['total'] as num?)?.toDouble() ??
          0.0;
      final adv = (row['advance_payment'] as num?)?.toDouble() ?? 0.0;
      workshopOrdersRevenue += net;
      workshopOrdersAdvances += adv;
    }
    final workshopOrdersUnpaid =
        (workshopOrdersRevenue - workshopOrdersAdvances).clamp(
          0.0,
          double.infinity,
        );

    // 3. Purchases (Achats)
    final achatRows = await myDb.rawQuery(
      'SELECT is_workshop, is_internal, total, paid_amount FROM Achats WHERE $whereAchats',
      argsAchats,
    );
    double storePurchases = 0.0;
    double workshopExternalPurchases = 0.0;
    double workshopInternalPurchases = 0.0;

    for (final row in achatRows) {
      final isWorkshop = (row['is_workshop'] as num?)?.toInt() == 1;
      final isInternal = (row['is_internal'] as num?)?.toInt() == 1;
      final tot = (row['total'] as num?)?.toDouble() ?? 0.0;

      if (isInternal) {
        workshopInternalPurchases += tot;
      } else if (isWorkshop) {
        workshopExternalPurchases += tot;
      } else {
        storePurchases += tot;
      }
    }

    // 4. Consolidated Enterprise Figures (Eliminating internal transactions)
    final consolidatedRevenue = storeExternalSales + workshopOrdersRevenue;
    final consolidatedCashCollected =
        storeExternalPaid + workshopOrdersAdvances;
    final consolidatedExternalPurchases =
        storePurchases + workshopExternalPurchases;
    final consolidatedNetCashFlow =
        consolidatedCashCollected - consolidatedExternalPurchases;

    return {
      'store_external_sales': storeExternalSales,
      'store_external_paid': storeExternalPaid,
      'store_external_unpaid': storeExternalUnpaid,
      'store_internal_transfers': storeInternalTransfers,
      'store_purchases': storePurchases,
      'workshop_orders_revenue': workshopOrdersRevenue,
      'workshop_orders_advances': workshopOrdersAdvances,
      'workshop_orders_unpaid': workshopOrdersUnpaid,
      'workshop_external_purchases': workshopExternalPurchases,
      'workshop_internal_purchases': workshopInternalPurchases,
      'consolidated_revenue': consolidatedRevenue,
      'consolidated_cash_collected': consolidatedCashCollected,
      'consolidated_external_purchases': consolidatedExternalPurchases,
      'consolidated_net_cash_flow': consolidatedNetCashFlow,
      'eliminated_internal_margin': storeInternalTransfers,
    };
  }
}
