part of '../sql_database.dart';

/// Employees, workers, allocations, attendance and settlements.
extension SqlDatabaseWorkers on SqlDatabase {
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
          'الكمية المسندة تجاوزت الحد المسموح به ($maxAllowed قطعة). المتبقي للإسناد: ${maxAllowed - currentAllocatedSum}',
        );
      }
    }

    // ðŸ›¡ï¸ 2. Clean slate initialization: reset all status flags for new allocation
    final nowStr = DateTime.now().toUtc().toIso8601String();
    int isMfg = 0;
    int isGlass = 0;
    int isDist = 0;
    int isTrans = 0;
    try {
      final cd = await myDb.query(
        'Commandes_details',
        columns: ['id_commandes'],
        where: 'id = ?',
        whereArgs: [detailId],
      );
      if (cd.isNotEmpty) {
        final orderId = (cd.first['id_commandes'] as num?)?.toInt() ?? 0;
        if (orderId > 0) {
          final ord = await myDb.query(
            'Commandes',
            columns: ['status'],
            where: 'id = ?',
            whereArgs: [orderId],
          );
          if (ord.isNotEmpty) {
            final s = (ord.first['status'] ?? '')
                .toString()
                .toLowerCase()
                .trim();
            final isMfgAll =
                s.contains('full manufacturing') ||
                s.contains('تصنيع كلي') ||
                s.contains('التصنيع الكلي') ||
                s.contains('fabrication totale') ||
                s.contains('full distribution') ||
                s.contains('توزيع كلي') ||
                s.contains('livré') ||
                s.contains('installation') ||
                s.contains('التركيب') ||
                s.contains('completed') ||
                s.contains('مكتمل') ||
                s.contains('done') ||
                s.contains('منتهية');
            final isDistAll =
                s.contains('full distribution') ||
                s.contains('توزيع كلي') ||
                s.contains('livré') ||
                s.contains('completed') ||
                s.contains('مكتمل') ||
                s.contains('done') ||
                s.contains('منتهية');
            if (isMfgAll) {
              isMfg = 1;
              isGlass = 1;
            }
            if (isDistAll) {
              isDist = 1;
              isTrans = 1;
            }
          }
        }
      }
    } catch (_) {}

    final Map<String, dynamic> row = {
      'commande_detail_id': detailId,
      'worker_uid': workerUid,
      'quantity': quantity,
      'worker_price': workerPrice,
      'assigned_at': nowStr,
      'is_settled': 0,
      'is_manufactured': isMfg,
      'manufactured_at': isMfg == 1 ? nowStr : null,
      'is_glass_installed': isGlass,
      'glass_installed_at': isGlass == 1 ? nowStr : null,
      'is_distributed': isDist,
      'distributed_at': isDist == 1 ? nowStr : null,
      'is_transferred_to_dist': isTrans,
      'transferred_at': isTrans == 1 ? nowStr : null,
      'updated_at': nowStr,
    };
    if (unitIndex != null) row['unit_index'] = unitIndex;
    if (unitPosition != null && unitPosition.isNotEmpty)
      row['unit_position'] = unitPosition;
    if (unitWidth != null && unitWidth > 0) row['unit_width'] = unitWidth;
    if (unitHeight != null && unitHeight > 0) row['unit_height'] = unitHeight;

    final res = await myDb.insert('WorkerAllocations', SqlDatabase._withDistributedId(row));
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
              'الكمية المسندة تجاوزت الحد المسموح به ($maxAllowed قطعة). المتبقي للإسناد: ${maxAllowed - currentAllocatedSum}',
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
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [allocationId],
    );

    await _uploadAllocationStatusToCloud(allocationId);
    CloudSyncService().notifyChange();
    return res;
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
      await myDb.delete(
        'WorkerAllocations',
        where: 'id = ?',
        whereArgs: [allocationId],
      );
    } catch (e) {
      debugPrint('deleteWorkerAllocationLocalOnly error: $e');
    }
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
        AND (c.is_deleted IS NULL OR c.is_deleted = 0)
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
        AND (c.is_deleted IS NULL OR c.is_deleted = 0)
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
    await _backfillOrderCodes(myDb);
    final cleanEmail = workerEmail.trim().toLowerCase();
    final cleanUid = workerUid.trim().toLowerCase();

    // 1. استعلام دقيق يضمن فلترة وحصر الإسنادات المسندة لهذا العامل فقط بدون تسريب إسنادات غيره
    final List<Map<String, dynamic>> results;
    if (cleanEmail.isNotEmpty) {
      results = await myDb.rawQuery(
        '''
        SELECT wa.*, cd.window_type, cd.largeur, cd.hauteur, cd.color, cd.glass, cd.drawing_image_path, cd.drawing_image_base64, cd.partitions_json, cd.confirmed_mesures_json,
               cd.id_commandes, c.order_code AS display_number, cd.accessories, cd.description, cd.quantity as detail_quantity,
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
               cd.id_commandes, c.order_code AS display_number, cd.accessories, cd.description, cd.quantity as detail_quantity,
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

  /// ربط إسنادات العامل بـ UID الصحيح بعد الاستعادة من السحابة
  Future<void> relinkCurrentWorkerAllocations() async {
    try {
      final user = AppAuthService().currentUser;
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
    await _backfillOrderCodes(myDb);
    return await myDb.rawQuery('''
      SELECT wa.*, cd.window_type, cd.largeur, cd.hauteur, cd.color, cd.glass, cd.drawing_image_path, cd.drawing_image_base64, cd.partitions_json, cd.id_commandes, c.order_code AS display_number, cd.accessories, cd.description, cl.firstname, cl.lastname, e.name as worker_name
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
                  'updated_at': DateTime.now().toUtc().toIso8601String(),
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

  Future<void> updateWorkerAllocationManufactured(
    int allocationId,
    int isManufactured,
  ) => updateWorkerAllocationManufacturing(allocationId, isManufactured);

  Future<void> updateWorkerAllocationGlassInstalled(
    int allocationId,
    int isGlassInstalled,
  ) => updateWorkerAllocationGlass(allocationId, isGlassInstalled);

  Future<void> updateWorkerAllocationManufacturing(
    int allocationId,
    int isManufactured,
  ) async {
    Database? myDb = await db;
    if (myDb == null) return;
    final nowStr = DateTime.now().toUtc().toIso8601String();

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
    final nowStr = DateTime.now().toUtc().toIso8601String();

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
    final nowStr = DateTime.now().toUtc().toIso8601String();

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
    final nowStr = DateTime.now().toUtc().toIso8601String();

    // ✔️ عند التحويل إلى التوزيع: نضبط حقل التحويل فقط → العنصر ينتقل لصفحة التركيبات الميدانية
    // ✔️ عند الإلغاء (إرجاع من الأرشيف): نصفّر جميع حقول التركيب/الاكتمال حتى يمر العنصر بمرحلة التركيبات الميدانية مرة أخرى
    final Map<String, dynamic> updateFields = isTransferred == 1
        ? {
            'is_transferred_to_dist': 1,
            'transferred_at': nowStr,
            'updated_at': nowStr,
          }
        : {
            'is_transferred_to_dist': 0,
            'transferred_at': null,
            // ✅ أساسي: عند الإرجاع من الأرشيف يجب مسح حالة التركيب والاكتمال ليعود للتركيبات الميدانية بعد ذلك
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

    // ⚡️ تشغيل syncOrder في الخلفية دون حظر الواجهة (تحسين السرعة)
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
                if (isTransferred == 1) {
                  await recordAllocationDeliveryNote(orderId, detailRow.first);
                }
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

  /// تسجيل وصل تسليم تلقائي في Commandes_deliveries عند خروج نافذة أو عنصر من الورشة
  Future<void> recordAllocationDeliveryNote(
    int orderId,
    Map<String, dynamic> detail,
  ) async {
    try {
      Database? myDb = await db;
      if (myDb == null) return;
      final orderRow = await myDb.query(
        'Commandes',
        where: 'id = ?',
        whereArgs: [orderId],
      );
      if (orderRow.isEmpty) return;
      final clientId = (orderRow.first['client_id'] as num?)?.toInt() ?? 0;
      if (clientId <= 0) return;

      final now = DateTime.now();
      final dateStr = DateFormat('yyyy-MM-dd HH:mm').format(now);
      final detailId = (detail['id'] as num?)?.toInt() ?? 0;

      final itemMap = {
        'id': detailId,
        'name': detail['window_type']?.toString() ?? 'نافذة',
        'quantity': 1,
        'price': (detail['prix'] as num?)?.toDouble() ?? 0.0,
        'width': (detail['largeur'] as num?)?.toDouble() ?? 0.0,
        'height': (detail['hauteur'] as num?)?.toDouble() ?? 0.0,
        'color': detail['color']?.toString() ?? '',
        'glass': detail['glass']?.toString() ?? '',
        'description': detail['description']?.toString() ?? '',
        'drawing_image_path': detail['drawing_image_path']?.toString() ?? '',
      };

      final existingDeliveries = await myDb.query(
        'Commandes_deliveries',
        where: 'id_commandes = ?',
        whereArgs: [orderId],
        orderBy: 'id DESC',
      );

      bool alreadyDelivered = false;
      for (final d in existingDeliveries) {
        try {
          final items = jsonDecode(d['items_json']?.toString() ?? '[]');
          if (items is List) {
            for (final it in items) {
              if ((it['id'] as num?)?.toInt() == detailId) {
                alreadyDelivered = true;
                break;
              }
            }
          }
        } catch (_) {}
        if (alreadyDelivered) break;
      }

      if (!alreadyDelivered) {
        await insertCommandeDelivery(
          orderId,
          clientId,
          dateStr,
          jsonEncode([itemMap]),
          (itemMap['price'] as double),
          isLoaded: 1,
        );
        await myDb.rawUpdate(
          'UPDATE Commandes_details SET delivered_qty = MIN(quantity, COALESCE(delivered_qty, 0) + 1) WHERE id = ?',
          [detailId],
        );
        await syncOrderAndAllocationsStatus(orderId);
      }
    } catch (e) {
      debugPrint('recordAllocationDeliveryNote error: $e');
    }
  }

  /// تحديث حالة إسنادات العناصر عند تأكيد وصل التسليم في صفحة المعاينة
  Future<void> markItemsAllocationsTransferred(
    int orderId,
    List<Map<String, dynamic>> items, {
    bool isFullOrder = false,
  }) async {
    try {
      Database? myDb = await db;
      if (myDb == null) return;
      final nowStr = DateTime.now().toUtc().toIso8601String();
      for (final it in items) {
        final detailId = (it['id'] as num?)?.toInt() ?? 0;
        final qty = (it['quantity'] as num?)?.toInt() ?? 1;
        if (detailId > 0) {
          await myDb.update(
            'WorkerAllocations',
            {
              'is_transferred_to_dist': 1,
              'transferred_at': nowStr,
              'is_distributed': 1,
              'distributed_at': nowStr,
              'updated_at': nowStr,
            },
            where: 'commande_detail_id = ?',
            whereArgs: [detailId],
          );
          if (isFullOrder) {
            await myDb.rawUpdate(
              'UPDATE Commandes_details SET delivered_qty = quantity WHERE id = ?',
              [detailId],
            );
          } else {
            await myDb.rawUpdate(
              'UPDATE Commandes_details SET delivered_qty = MIN(quantity, COALESCE(delivered_qty, 0) + ?) WHERE id = ?',
              [qty, detailId],
            );
          }
        }
      }
      if (isFullOrder && orderId > 0) {
        await myDb.rawUpdate(
          'UPDATE Commandes_details SET delivered_qty = quantity WHERE id_commandes = ?',
          [orderId],
        );
      }
    } catch (e) {
      debugPrint('markItemsAllocationsTransferred error: $e');
    }
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
        AND (c.is_deleted IS NULL OR c.is_deleted = 0)
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
    final nowStr = DateTime.now().toUtc().toIso8601String();
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
    final nowStr = DateTime.now().toUtc().toIso8601String();
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
    final nowStr = DateTime.now().toUtc().toIso8601String();
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
    final nowStr = DateTime.now().toUtc().toIso8601String();
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
        AND (c.is_deleted IS NULL OR c.is_deleted = 0)
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
                  'updated_at': DateTime.now().toUtc().toIso8601String(),
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
    dynamic allocationId,
    double price,
  ) async {
    Database? myDb = await db;
    if (myDb == null) return;
    final idInt = allocationId is int
        ? allocationId
        : int.tryParse(allocationId?.toString() ?? '') ?? 0;
    if (idInt <= 0) return;

    await myDb.update(
      'WorkerAllocations',
      {
        'worker_price': price,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      where: 'id = ? OR CAST(id AS TEXT) = ?',
      whereArgs: [idInt, idInt.toString()],
    );
    await _uploadAllocationStatusToCloud(idInt);
    CloudSyncService().notifyChange();
  }

  // ── الحضور والغياب (WorkerAttendance) ──────────────────────────────────────────────
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
      // 🗑️ إذا كانت البيانات فارغة، احذف السجل لتصفير خيار الحضور والغياب (فارغ ⚪)
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
        SqlDatabase._withDistributedId({
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

  // ── الأعمال اليومية (WorkerDailyJobs - عمل يومي) ──────────────────────────
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
      SqlDatabase._withDistributedId({
        'worker_uid': workerUid,
        'work_date': workDate,
        'title': title.trim().isEmpty ? 'عمل يومي' : title.trim(),
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

    final now = DateTime.now().toUtc().toIso8601String();
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

    // 1b. Calculate total earned from unsettled daily jobs (عمل يومي)
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
      SqlDatabase._withDistributedId({
        'worker_uid': primaryKey,
        'amount': paymentAmount,
        'transaction_type': 'salary',
        'note': 'تسوية أسبوعية - دفع أسبوعي',
        'created_at': now,
        'is_settled': 1,
        'settled_at': now,
      }),
    );

    // 6. Record in Treasury as Decaissement (ALWAYS record full payout in selected Caisse)
    if (paymentAmount != 0.0) {
      await insertTreasury(
        'Décaissement',
        paymentAmount.abs(),
        'تسوية أسبوعية للعامل $workerName',
        entityType: 'Worker',
        entityId: workerId > 0 ? workerId : null,
        recordedBy: recordedBy,
        caisseName: caisseName ?? 'الصندوق الرئيسي',
        referenceId: -1,
        createdAt: now,
      );
    }

    // 7. Calculate carryover (the difference)
    final double carryover = paymentAmount - netDueBefore;
    if (carryover != 0.0) {
      await myDb.insert(
        'WorkerTransactions',
        SqlDatabase._withDistributedId({
          'worker_uid': primaryKey,
          'amount': carryover,
          'transaction_type': 'advance',
          'note': 'رصيد مرحّل من الأسبوع السابق',
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
            ? DateTime.now().toUtc().toIso8601String()
            : null,
      },
      where: 'id = ?',
      whereArgs: [detailId],
    );
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
    final now = DateTime.now().toUtc().toIso8601String();

    var res = await myDb!.insert(
      'WorkerTransactions',
      SqlDatabase._withDistributedId({
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
            (transactionType == 'advance' ? 'سلفة للعامل ' : 'أجرة للعامل ') +
            workerName;
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
          "transaction_type = 'Décaissement' AND entity_type = 'Worker' AND entity_id = ? AND amount = ?",
      whereArgs: [workerId, oldAmount],
      limit: 1,
    );

    if (records.isNotEmpty) {
      final treasuryId = records.first['id'] as int;
      String desc =
          (newType == 'advance' ? 'سلفة للعامل ' : 'أجرة للعامل ') + workerName;
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
          "transaction_type = 'Décaissement' AND entity_type = 'Worker' AND entity_id = ? AND amount = ?",
      whereArgs: [workerId, amount],
      limit: 1,
    );

    if (records.isNotEmpty) {
      final treasuryId = records.first['id'] as int;
      await myDb.delete('Treasury', where: 'id = ?', whereArgs: [treasuryId]);
    }
    CloudSyncService().notifyChange();
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
      SqlDatabase._withDistributedId({
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
      await txn.update(
        'Commandes_deliveries',
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
