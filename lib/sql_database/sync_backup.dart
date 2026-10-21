part of '../sql_database.dart';

/// Cloud sync, export/import and backups of the local database.
extension SqlDatabaseSync on SqlDatabase {
  int createDistributedId() => SqlDatabase._nextDistributedId();

  Future<void> _uploadOrderStatusToCloud(
    int orderId,
    String status, {
    int? clientId,
    String? updatedBy,
  }) async {
    if (CloudSyncService.supabaseWorkshopDataOnly) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final workshopId = prefs.getString('workshop_code');
      if (workshopId != null && workshopId.isNotEmpty) {
        final payload = <String, dynamic>{
          'id': orderId,
          'status': status,
          'updated_at': FieldValue.serverTimestamp(),
          if (updatedBy != null && updatedBy.trim().isNotEmpty)
            'updated_by': updatedBy.trim(),
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
    if (CloudSyncService.supabaseWorkshopDataOnly) return false;
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
        final cloudUpdatedBy = data['updated_by']?.toString().trim() ?? '';

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
          if (cloudUpdatedBy.isNotEmpty &&
              cloudUpdatedBy != existing.first['updated_by']?.toString()) {
            updateMap['updated_by'] = cloudUpdatedBy;
          }

          if (updateMap.isNotEmpty) {
            updateMap['updated_at'] = DateTime.now().toUtc().toIso8601String();
            await myDb.update(
              'Commandes',
              updateMap,
              where: 'id = ?',
              whereArgs: [orderId],
            );
            if (updateMap.containsKey('status')) {
              await syncAllocationsFromOrderStatus(orderId, cloudStatus);
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
    if (CloudSyncService.supabaseWorkshopDataOnly) return;
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
    if (CloudSyncService.supabaseWorkshopDataOnly) return;
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

  /// Moves glass sizes that glass reception wrote into confirmed_mesures_json
  /// (an object instead of the list of window measurements) to their own
  /// column. The overwritten window measurements cannot be recovered.
  Future<void> _moveLegacyGlassOverrides(Database db) async {
    final rows = await db.query(
      'Commandes_details',
      columns: ['id', 'confirmed_mesures_json'],
      where: "TRIM(confirmed_mesures_json) LIKE '{%'",
    );
    for (final row in rows) {
      final raw = row['confirmed_mesures_json']?.toString() ?? '';
      Object? decoded;
      try {
        decoded = jsonDecode(raw);
      } catch (_) {
        continue;
      }
      if (decoded is! Map) continue;
      final hasGlass =
          decoded.containsKey('glass_height') ||
          decoded.containsKey('glass_width');
      await db.update(
        'Commandes_details',
        {
          if (hasGlass) 'glass_override_json': raw,
          'confirmed_mesures_json': null,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [row['id']],
      );
    }
  }

  /// Saves the glass sizes and specification corrected at glass reception.
  Future<void> updateCommandeDetailGlassOverride(
    int detailId, {
    required String glassText,
    required double glassHeight,
    required double glassWidth,
  }) async {
    final myDb = await db;
    if (myDb == null) return;
    await myDb.update(
      'Commandes_details',
      {
        'glass': glassText,
        'glass_override_json': jsonEncode({
          'glass_height': glassHeight,
          'glass_width': glassWidth,
          'custom_spec': glassText,
        }),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [detailId],
    );
    CloudSyncService().notifyChange();
  }

  Future<void> syncAllocationsFromOrderStatus(
    int orderId,
    String status, {
    bool resetWorkerProgress = false,
  }) async {
    Database? myDb = await db;
    if (myDb == null) return;

    final nowStr = DateTime.now().toUtc().toIso8601String();
    final details = await readCommandeDetails(orderId);
    if (details.isEmpty) return;
    final allocationIdsToUpload = <int>{};

    final sLower = status.trim().toLowerCase();

    final isMfgAll =
        sLower.contains('full manufacturing') ||
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

    final isDistAll =
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

    final isMfgPartial =
        sLower.contains('partial manufacturing') ||
        sLower.contains('تصنيع جزئي') ||
        sLower.contains('التصنيع الجزئي');
    final isDistPartial =
        sLower.contains('partial distribution') ||
        sLower.contains('توزيع جزئي') ||
        sLower.contains('التوزيع الجزئي');

    final isPreMfg =
        sLower == 'pending' ||
        sLower == 'draft' ||
        sLower == 'new' ||
        sLower == 'confirmed' ||
        sLower == 'in progress' ||
        sLower.contains('attente') ||
        sLower.contains('انتظار') ||
        sLower.contains('مؤكد') ||
        sLower.contains('قياسات');
    // Erasing worker progress is only allowed when the user confirmed it.
    // This sync also runs when the allocation screen opens and after cloud
    // downloads; those calls must never wipe what workers recorded.
    if (isPreMfg && !resetWorkerProgress) return;

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
          // ✅ Only set timestamp if not already recorded (preserve the exact button-press moment)
          if (current['manufactured_at'] == null ||
              current['manufactured_at'].toString().isEmpty) {
            updates['manufactured_at'] = nowStr;
          }
          updates['is_glass_installed'] = 1;
          // ✅ Only set timestamp if not already recorded
          if (current['glass_installed_at'] == null ||
              current['glass_installed_at'].toString().isEmpty) {
            updates['glass_installed_at'] = nowStr;
          }
        }

        if (isDistAll || (isDistPartial && i == 0 && j == 0)) {
          updates['is_distributed'] = 1;
          // ✅ Only set timestamp if not already recorded
          if (current['distributed_at'] == null ||
              current['distributed_at'].toString().isEmpty) {
            updates['distributed_at'] = nowStr;
          }
          if (isDistAll) {
            updates['is_transferred_to_dist'] = 1;
            if (current['transferred_at'] == null ||
                current['transferred_at'].toString().isEmpty) {
              updates['transferred_at'] = nowStr;
            }
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

    if (isDistAll && orderId > 0) {
      await myDb.rawUpdate(
        'UPDATE Commandes_details SET delivered_qty = quantity WHERE id_commandes = ?',
        [orderId],
      );
    }

    if (allocationIdsToUpload.isNotEmpty) {
      unawaited(
        Future.wait(allocationIdsToUpload.map(_uploadAllocationStatusToCloud)),
      );
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
          await syncAllocationsFromOrderStatus(orderId, status);
        }
      }
    } catch (e) {
      debugPrint('syncAllAllocationsFromAllOrderStatuses error: $e');
    }
  }

  Future<void> _deleteAllocationFromCloud(int allocationId) async {
    if (CloudSyncService.supabaseWorkshopDataOnly) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final workshopId = prefs.getString('workshop_code');
      final userRole = prefs.getString('user_role') ?? 'worker';
      if (workshopId != null && workshopId.isNotEmpty) {
        final workshopRef = FirebaseFirestore.instance
            .collection('workshops')
            .doc(workshopId);

        // 1. كتابة علامة حذف دائمة (tombstone) تمنع restore من إعادة الإسناد المحذوف
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

  /// 🧹 تصفير وحذف جميع المهام والإسنادات محلياً وفي السحابة للتطوير
  Future<void> clearAllWorkerAllocationsFromCloudAndLocal() async {
    return runUserDeletion<void>('clearAllWorkerAllocationsFromCloudAndLocal', () async {
      Database? myDb = await db;
      if (myDb != null) {
        await myDb.rawDelete('DELETE FROM WorkerAllocations');
      }

      if (CloudSyncService.supabaseWorkshopDataOnly) {
        CloudSyncService().notifyChangeImmediate();
        return;
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
    });
  }

  /// 🧹 تصفير بيانات التركيبات والعمليات الخارجية محلياً وفي السحابة للتطوير
  Future<void> clearAllInstallationDataFromCloudAndLocal() async {
    return runUserDeletion<void>('clearAllInstallationDataFromCloudAndLocal', () async {
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

      if (CloudSyncService.supabaseWorkshopDataOnly) {
        CloudSyncService().notifyChangeImmediate();
        return;
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
    });
  }

  /// 🧹 تصفير سجلات المحاسبة محلياً وفي السحابة للتطوير
  Future<void> clearAllWeeklySettlementsFromCloudAndLocal() async {
    return runUserDeletion<void>('clearAllWeeklySettlementsFromCloudAndLocal', () async {
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

      if (CloudSyncService.supabaseWorkshopDataOnly) {
        CloudSyncService().notifyChangeImmediate();
        return;
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
    });
  }

  Future<void> _uploadAllocationStatusToCloud(int allocationId) async {
    if (CloudSyncService.supabaseWorkshopDataOnly) return;
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
                    alloc['updated_at'] ??
                    DateTime.now().toUtc().toIso8601String(),
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
    if (CloudSyncService.supabaseWorkshopDataOnly) return;
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
                  data['assigned_at'] ??
                  DateTime.now().toUtc().toIso8601String(),
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
              'updated_at':
                  cloudUpdatedAt ?? DateTime.now().toUtc().toIso8601String(),
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

      // 1. حساب إجمالي الكميات المطلوبة في الطلبية من تفاصيلها الفعلية
      final orderDetails = await myDb.query(
        'Commandes_details',
        where: 'id_commandes = ?',
        whereArgs: [orderId],
      );
      if (orderDetails.isEmpty) return;

      int totalRequiredUnits = 0;
      for (final d in orderDetails) {
        totalRequiredUnits += (d['quantity'] as num?)?.toInt() ?? 0;
      }

      // 2. قراءة جميع مهام وإسنادات عمال هذه الطلبية
      final allOrderAllocs = await myDb.rawQuery(
        '''
        SELECT wa.* 
        FROM WorkerAllocations wa
        INNER JOIN Commandes_details cd ON wa.commande_detail_id = cd.id
        WHERE cd.id_commandes = ?
      ''',
        [orderId],
      );

      // إذا لم يكن هناك أي إسنادات مسجلة بعد، تبقى الطلبية في مرحلتها الإدارية الحالية
      if (allOrderAllocs.isEmpty) return;

      // العدد المرجعي الإجمالي للعناصر (إما مجموع كميات الطلبية أو عدد المهام المسندة)
      int effectiveTotal = totalRequiredUnits > 0
          ? (totalRequiredUnits > allOrderAllocs.length
                ? totalRequiredUnits
                : allOrderAllocs.length)
          : allOrderAllocs.length;

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

      // 3. تحديد الحالة الآلية حسب أحدث وأعلى ما أنجزه العمال على العناصر
      String? targetStatus;

      if (reserveAllocs > 0) {
        // ⚠️ إذا كان هناك أي تحفظ مسجل من عامل التركيب، تكون الأولوية للتحفظ
        targetStatus = 'Reserve';
      } else if ((completedAllocs >= effectiveTotal ||
              installAllocs >= effectiveTotal) &&
          effectiveTotal > 0 &&
          reserveAllocs == 0) {
        // ✅ إذا تم تركيب كل العناصر بالكامل أو اكتمالها دون أي تحفظ
        targetStatus = 'Done';
      } else if (installAllocs > 0) {
        // 🛠️ إذا بدأ العامل بالتركيب أو تم تركيب بعض العناصر بالموقع
        targetStatus = 'Installation';
      } else if (distAllocs >= effectiveTotal && effectiveTotal > 0) {
        // 🚚 تم توزيع كل عناصر الطلبية بالكامل للميدان
        targetStatus = 'Full Distribution';
      } else if (distAllocs > 0) {
        // 📦 تم توزيع عنصر واحد أو بعض العناصر وليس الكل
        targetStatus = 'Partial Distribution';
      } else if (mfgAllocs >= effectiveTotal && effectiveTotal > 0) {
        // 🏭 تم تصنيع جميع عناصر الطلبية بالكامل في الورشة
        targetStatus = 'Full Manufacturing';
      } else if (mfgAllocs > 0) {
        // ⚙️ تم تصنيع عنصر واحد على الأقل وتجاوز مرحلة تأكيد القياسات
        targetStatus = 'Partial Manufacturing';
      }

      // 4. تطبيق الحالة الجديدة إذا تغيرت وحفظها ومزامنتها سحابياً ولحظياً
      final orderRow = await myDb.query(
        'Commandes',
        where: 'id = ?',
        whereArgs: [orderId],
      );
      if (orderRow.isNotEmpty) {
        final currentStatus = orderRow.first['status']?.toString() ?? '';

        // إذا ألغى العامل حالة الصنع وعادت العناصر المصنعة إلى صفر، تعود الطلبية لمرحلة ما قبل التصنيع
        if (targetStatus == null &&
            (currentStatus == 'Partial Manufacturing' ||
                currentStatus == 'Full Manufacturing')) {
          targetStatus = 'In Progress';
        }

        if (targetStatus != null && currentStatus != targetStatus) {
          await updateCommandeStatus(
            orderId,
            targetStatus,
            skipAllocationSync: true,
          );
          debugPrint(
            'syncOrderAndAllocationsStatus: updated order #$orderId automatically from "$currentStatus" to "$targetStatus"',
          );
        }
      }
    } catch (e) {
      debugPrint('syncOrderAndAllocationsStatus error: $e');
    }
  }

  Future<void> _writeDeletedOrderTombstoneToCloud(int orderId) async {
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
          .set({
            'id': orderId,
            'deleted_at': FieldValue.serverTimestamp(),
            'device_at': DateTime.now().toUtc().toIso8601String(),
            'deleted_by': AppAuthService().currentUser?.uid,
          }, SetOptions(merge: true))
          .timeout(const Duration(seconds: 3));
    } catch (e) {
      debugPrint('Failed to write deleted_orders tombstone: $e');
    }
  }

  Future<Map<int, int>> readPendingDeliveryQuantities(int orderId) async {
    final myDb = await db;
    if (myDb == null) return {};
    await _ensureDeliveriesLoadedColumn(myDb);
    final rows = await myDb.query(
      'Commandes_deliveries',
      columns: ['items_json'],
      where:
          "id_commandes = ? AND COALESCE(delivery_status, 'planned') NOT IN ('delivered', 'cancelled', 'failed')",
      whereArgs: [orderId],
    );
    final totals = <int, int>{};
    for (final row in rows) {
      final decoded = jsonDecode(row['items_json']?.toString() ?? '[]');
      if (decoded is! List) continue;
      for (final raw in decoded) {
        if (raw is! Map) continue;
        final id = int.tryParse(raw['id']?.toString() ?? '') ?? 0;
        final quantity = int.tryParse(raw['quantity']?.toString() ?? '') ?? 0;
        if (id > 0 && quantity > 0) {
          totals[id] = (totals[id] ?? 0) + quantity;
        }
      }
    }
    return totals;
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
      // Their unsent changes would otherwise reach the server later.
      final marks = List.filled(tablesToClear.length, '?').join(',');
      await txn.delete(
        '_sync_change_log',
        where: 'table_name IN ($marks)',
        whereArgs: tablesToClear,
      );
      await txn.update('_sync_runtime_flags', {
        'suppress_tombstones': 0,
      }, where: 'id = 1');
    });
  }

  Future<PendingCloudChanges> exportPendingCloudChanges({
    Set<String>? allowedTables,
  }) async {
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

    final safeAllowedTables = allowedTables
        ?.where(SqlDatabase._isSafeSqlIdentifier)
        .toSet();
    if (safeAllowedTables != null && safeAllowedTables.isEmpty) {
      return const PendingCloudChanges(
        data: <String, dynamic>{},
        acknowledgements: <CloudChangeAcknowledgement>[],
        changedRows: 0,
        deletedRows: 0,
      );
    }
    final allowedTableList = safeAllowedTables?.toList(growable: false);
    final logRows = await myDb.query(
      '_sync_change_log',
      where: allowedTableList == null
          ? null
          : 'table_name IN (${List.filled(allowedTableList.length, '?').join(',')})',
      whereArgs: allowedTableList,
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
    final changedAtByRow = <String, String>{};
    var changedRows = 0;
    var deletedRows = 0;

    String syncRowKey(String table, String rowId) => '$table\u0000$rowId';

    for (final logRow in logRows) {
      final table = logRow['table_name']?.toString() ?? '';
      final rowId = logRow['row_id']?.toString() ?? '';
      final changedAt = logRow['changed_at']?.toString().trim() ?? '';
      if (table.isNotEmpty && rowId.isNotEmpty && changedAt.isNotEmpty) {
        changedAtByRow[syncRowKey(table, rowId)] = changedAt;
      }
    }

    void upsertExportRow(String table, Map<String, dynamic> row) {
      final rowId = row['id']?.toString() ?? '';
      final changedAt = changedAtByRow[syncRowKey(table, rowId)];
      // The row's own timestamp can be stale even though the SQLite trigger
      // recorded a fresh change. Publish the trigger timestamp so incremental
      // downloads on other devices cannot skip this update.
      if (changedAt != null) {
        row['updated_at'] = changedAt;
      }
      final sanitized = _sanitizeCloudExportRow(
        table,
        Map<String, dynamic>.from(row),
      );
      final sanitizedRowId = sanitized['id']?.toString();
      final list =
          data.putIfAbsent(table, () => <Map<String, dynamic>>[])
              as List<Map<String, dynamic>>;
      if (sanitizedRowId != null && sanitizedRowId.isNotEmpty) {
        final existingIndex = list.indexWhere(
          (existing) => existing['id']?.toString() == sanitizedRowId,
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
      if (!SqlDatabase._isSafeSqlIdentifier(table) ||
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

      final rows = operation == 'delete'
          ? const <Map<String, Object?>>[]
          : await myDb.query(
              table,
              where: 'id = ?',
              whereArgs: [rowId],
              limit: 1,
            );
      if (rows.isEmpty) {
        // Only a recorded deletion is sent. A row that disappeared without
        // one (a wipe, a restore, a clean-up) stays on the server; its change
        // is acknowledged and dropped.
        final matching = await myDb.query(
          'SyncTombstones',
          where: 'table_name = ? AND row_id = ?',
          whereArgs: [table, rowId],
          limit: 1,
        );
        if (matching.isEmpty) continue;
        await rememberOrderBundleForRow(table, rowId);
        tombstones.add(Map<String, dynamic>.from(matching.first));
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

      // Read only ids in the first response. Drawing images are base64 text
      // and returning all detail rows in one Android platform-channel message
      // can require a contiguous 70-110 MB allocation and kill the process.
      final detailIds = await myDb.query(
        'Commandes_details',
        columns: ['id'],
        where: 'id_commandes = ? OR CAST(id_commandes AS TEXT) = ?',
        whereArgs: [orderId, orderId],
      );
      for (final detailIdRow in detailIds) {
        final detailId = detailIdRow['id'];
        final detailRows = await myDb.query(
          'Commandes_details',
          where: 'id = ?',
          whereArgs: [detailId],
          limit: 1,
        );
        if (detailRows.isNotEmpty) {
          upsertExportRow(
            'Commandes_details',
            Map<String, dynamic>.from(detailRows.first),
          );
        }
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
      if (!SqlDatabase._isSafeSqlIdentifier(table)) continue;
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
        'قاعدة SQLite المحلية تالفة، وتم إيقاف الرفع لحماية النسخة السحابية.',
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
        .where(SqlDatabase._isSafeSqlIdentifier)
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
        'تعذر قراءة جداول قاعدة البيانات التالية للنسخ السحابي: '
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
      // The path is device-local and must never be synchronized: it points to
      // a cache/app-support file that does not exist on another phone.
      row.remove('drawing_image_path');
      final partitionsJson = row['partitions_json']?.toString().trim() ?? '';
      final base64Img = row['drawing_image_base64']?.toString() ?? '';
      final hasDecorPanel =
          partitionsJson.contains('paneauSandwitchDecore') ||
          partitionsJson.contains('decorDesignCode');
      // If partitions_json is present, the drawing is fully defined as a vector model
      // and will be rendered dynamically locally. Strip huge base64 strings (>100KB)
      // to keep sync fast, lightweight, and prevent PostgREST timeouts.
      if (partitionsJson.length > 20 &&
          partitionsJson != '{}' &&
          !hasDecorPanel &&
          base64Img.length > 100000) {
        row.remove('drawing_image_base64');
      }
    }
    if (table == 'Commandes_deliveries') {
      final itemsRaw = row['items_json'];
      if (itemsRaw is String && itemsRaw.isNotEmpty) {
        try {
          final decoded = jsonDecode(itemsRaw);
          if (decoded is List) {
            for (final item in decoded) {
              if (item is Map) {
                item.remove('drawing_image_base64');
                item.remove('drawing_image_path');
              }
            }
            row['items_json'] = jsonEncode(decoded);
          }
        } catch (_) {}
      }
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

  Future<Set<String>> _tableColumns(DatabaseExecutor db, String table) async {
    if (!SqlDatabase._isSafeSqlIdentifier(table)) return <String>{};
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
      'created_at',
      'createdAt',
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
        if (!SqlDatabase._isSafeSqlIdentifier(table) ||
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
      if (!SqlDatabase._isSafeSqlIdentifier(table) ||
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
  }) async {
    // A backup or workshop restore may replace the rule tables as well:
    // keep a local copy of them first.
    if (SqlDatabase.workshopCatalogConfigurationTables.any(data.containsKey)) {
      try {
        await saveCatalogConfigSnapshot(reason: 'data_import');
      } catch (error) {
        debugPrint('Rule snapshot before import skipped: $error');
      }
    }
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
      'SectionSharingRules',
      'CatalogItemRules',
      'AccessoryLinks',
      'AccessoryRoleLinks',
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
      'StockReservations',
      'MaterialRemnants',
      'MaterialScrap',
    ];
    final importTables = <String>[
      ...orderedTables.where(data.containsKey),
      ...data.keys.where(
        (table) =>
            !orderedTables.contains(table) && SqlDatabase._isSafeSqlIdentifier(table),
      ),
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
      'StockReservations',
      'MaterialRemnants',
      'MaterialScrap',
      'AuditLogs',
      'BusinessDayClosings',
    };

    await myDb.transaction((txn) async {
      await txn.execute('PRAGMA foreign_keys = OFF');
      await _ensureSyncSchema(txn);
      await txn.update('_sync_runtime_flags', {
        'suppress_tombstones': 1,
      }, where: 'id = 1');

      // A full workshop restore means that the active workshop has been
      // selected explicitly and the incoming snapshot is authoritative.
      // SyncTombstones is stored in the shared local database, so keeping
      // tombstones from a previously opened workshop can hide unrelated rows
      // that happen to use the same ID in the newly selected workshop.
      // Clear that old workshop state before importing this workshop's own
      // tombstones. Incremental downloads still merge tombstones normally.
      if (replaceAllData) {
        await txn.delete('SyncTombstones');
      }
      final tombstoneKeys = await _mergeAndReadSyncTombstones(
        txn,
        data['SyncTombstones'],
      );

      for (final table in importTables) {
        if (table == 'SyncTombstones' || table.startsWith('_sync_')) {
          continue;
        }
        final rows = data[table] as List<dynamic>? ?? [];

        // حماية: إذا كان الجدول حساساً والـ payload يعيده فارغاً،
        // احتفظ بالبيانات المحلية ولا تمسحها.
        if (!replaceAllData &&
            sensitiveTransactionalTables.contains(table) &&
            rows.isEmpty) {
          print(
            'importAllData: Skipping wipe of "$table" â€” payload is empty, keeping local data.',
          );
          continue;
        }

        // 🛡️ حماية الجداول الحساسة (الصندوق، معاملات العمال، الإسنادات، الطلبيات، الزبائن، إلخ):
        // لا نمسح هذه الجداول محلياً بـ txn.delete(table) بل نعتمد التدميج الذكي (upsert) للحفاظ على المعاملات المحلية الجديدة
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
                sanitized['id'] = SqlDatabase._profileColorSyncId(profileId, colorId);
              }
            }
            if (table == 'Sections') {
              sanitized['thickness'] ??= 45.0;
              sanitized['bar_length'] ??= 5.8;
              sanitized['glass_deduction'] ??= 0.0;
              sanitized['weight_per_meter'] ??= 0.0;
              sanitized['couvre_joint_width'] ??= 0.0;
              sanitized['couvre_joint_thickness'] ??= 0.0;
              sanitized['cutting_deduction'] ??= 0.0;
              sanitized['visible_width'] ??= 0.0;
              sanitized['visible_width_2'] ??= 0.0;
              sanitized['sash_overlap'] ??= 0.0;
              sanitized['max_glass_thickness'] ??= 0.0;
              // Older catalogues lack the parclose cut rule: keep the local
              // one rather than resetting it, but never insert a null.
              for (final (key, fallback) in const [
                ('parclose_cut_support', 'both'),
                ('parclose_default_cut', '45'),
              ]) {
                if (sanitized.containsKey(key)) sanitized[key] ??= fallback;
              }
              sanitized['allows_side_cover'] ??= 1;
              sanitized['is_frame'] ??= 0;
              sanitized['is_sash'] ??= 0;
              sanitized['is_mullion'] ??= 0;
              sanitized['is_active'] ??= 1;
              sanitized['type'] ??= 'frame';
              sanitized['name'] ??= '';
              sanitized['code'] ??= '';
            } else if (table == 'Profile') {
              sanitized['name'] ??= 'Unknown';
              sanitized['type'] ??= 'Aluminium';
              sanitized['default_bar_length'] ??= 5.8;
              sanitized['is_active'] ??= 1;
            } else if (table == 'Series') {
              sanitized['name'] ??= 'Unknown';
              sanitized['type'] ??= 'Aluminium';
              sanitized['price_per_meter'] ??= 0.0;
              sanitized['has_three_piece_sash'] ??= 0;
              sanitized['has_face_to_face'] ??= 0;
              sanitized['reinforcement_type'] ??= 'full_substitution';
              sanitized['is_active'] ??= 1;
            } else if (table == 'Accessories') {
              sanitized['price'] ??= 0.0;
              sanitized['is_active'] ??= 1;
              sanitized['material_type'] ??= 'Aluminium';
              sanitized['scope'] ??= 'Global';
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

  Future<Map<String, dynamic>> _exportSelectedTables(
    Iterable<String> selectedTables,
  ) async {
    final myDb = await db;
    final result = <String, dynamic>{};
    if (myDb == null) return result;
    if (!await isDatabaseHealthy()) {
      throw StateError('database image malformed (code 11)');
    }

    // sqflite_sqlcipher serializes every query result into one Android method
    // channel message. Keep that message bounded even when rows contain
    // drawing_image_base64 or other large text fields.
    const pageSize = 20;
    for (final table in selectedTables.where(SqlDatabase._isSafeSqlIdentifier)) {
      final exists = await myDb.rawQuery(
        "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ? LIMIT 1",
        [table],
      );
      if (exists.isEmpty) continue;

      final exportedRows = <Map<String, dynamic>>[];
      var offset = 0;
      while (true) {
        final page = await myDb.query(table, limit: pageSize, offset: offset);
        for (final row in page) {
          exportedRows.add(
            _sanitizeCloudExportRow(table, Map<String, dynamic>.from(row)),
          );
        }
        if (page.length < pageSize) break;
        offset += pageSize;
      }
      result[table] = exportedRows;
    }
    return result;
  }

  Future<Map<String, dynamic>> exportGlobalCatalog() async {
    return _exportSelectedTables(SqlDatabase.catalogTables);
  }

  Future<void> importGlobalCatalog(Map<String, dynamic> data) async {
    final catalogData = <String, dynamic>{};
    for (final table in SqlDatabase.catalogTables) {
      if (data.containsKey(table)) {
        catalogData[table] = data[table];
      }
    }
    if (catalogData.isEmpty) {
      throw Exception(
        'لا توجد بيانات كتالوج صالحة للاستيراد.',
      );
    }
    // الحفاظ على أسعار الورشة إذا كانت مزامنة الأسعار معطلة من طرف المدير
    await PriceSyncService.instance.preserveLocalPricesIfSyncDisabled(catalogData);
    // أسعار الورشة الخاصة (يدوية، من الشراء، أو من نشرة مقبولة) تبقى فوق الكتالوج
    await _overlayWorkshopBasePrices(catalogData);
    await importAllData(catalogData);
  }

  Future<Map<String, dynamic>> exportWorkshopData() async {
    return _exportSelectedTables(SqlDatabase.workshopTables);
  }

  Future<Map<String, dynamic>> exportWorkshopCatalogConfiguration() async {
    return _exportSelectedTables(SqlDatabase.workshopCatalogConfigurationTables);
  }

  /// Applies the workshop's remote rule tables. A copy that would remove
  /// many series roles or accessory rules is held back for the manager
  /// unless [force] is set (the manager chose it).
  Future<CatalogConfigImportResult> importWorkshopCatalogConfiguration(
    Map<String, dynamic> data, {
    bool force = false,
  }) async {
    final configuration = <String, dynamic>{};
    final myDb = await db;
    for (final table in SqlDatabase.workshopCatalogConfigurationTables) {
      if (!data.containsKey(table)) continue;
      final remote = data[table];
      // An empty remote table never wipes local rules: a device or account
      // without rules uploaded empty tables and every phone that synced
      // afterwards lost its series roles and accessory rules.
      if (remote is List && remote.isEmpty && myDb != null) {
        try {
          final local = await myDb.rawQuery(
            'SELECT COUNT(*) AS n FROM $table',
          );
          if (((local.first['n'] as num?) ?? 0) > 0) continue;
        } catch (_) {}
      }
      configuration[table] = remote;
    }
    if (configuration.isEmpty || myDb == null) {
      return CatalogConfigImportResult.unchanged;
    }
    if (!force &&
        await _holdBackShrinkingConfiguration(myDb, configuration)) {
      debugPrint(
        'Remote workshop rules would remove many local rules; '
        'kept local and waiting for the manager.',
      );
      return CatalogConfigImportResult.conflict;
    }
    await saveCatalogConfigSnapshot(reason: 'remote_configuration');
    // Configuration tables are replaceable: an explicit deletion made by the
    // manager must also delete the old row on the receiving phone.
    await importAllData(configuration);
    if (configuration.containsKey('ShutterCalcRules')) {
      await ShutterCalcRules.load(this);
    }
    // A newer copy that no longer shrinks the rules replaces an older
    // held-back one.
    await discardPendingCatalogConfigConflict();
    return CatalogConfigImportResult.applied;
  }

  /// Removes the local deletions of rows that Supabase now holds live, so
  /// the import that follows brings those rows back. A deletion that came
  /// from Supabase always gives way: Supabase holds one state per row and
  /// now says live. A deletion made here and not uploaded yet gives way only
  /// to a row stored after it ([supersedes] compares the two times).
  /// [liveRowTimes] maps a
  /// table to its row ids and their Supabase update time. Returns the number
  /// of deletions removed.
  Future<int> dropDeletionsSupersededByLiveRows(
    Map<String, Map<String, String>> liveRowTimes, {
    required bool Function(String liveUpdatedAt, String deletedAt) supersedes,
  }) async {
    if (liveRowTimes.isEmpty) return 0;
    final myDb = await db;
    if (myDb == null) return 0;
    var dropped = 0;
    await myDb.transaction((txn) async {
      await _ensureSyncTombstoneInfrastructure(txn);
      for (final entry in liveRowTimes.entries) {
        final table = entry.key;
        final ids = entry.value.keys.toList(growable: false);
        for (var start = 0; start < ids.length; start += 500) {
          final chunk = ids.sublist(start, min(start + 500, ids.length));
          final marks = List.filled(chunk.length, '?').join(',');
          final deletions = await txn.query(
            'SyncTombstones',
            columns: ['row_id', 'deleted_at'],
            where: 'table_name = ? AND row_id IN ($marks)',
            whereArgs: [table, ...chunk],
          );
          if (deletions.isEmpty) continue;
          // A deletion still waiting for upload was made here; the others
          // came from Supabase, which now holds the row live again.
          final pending = {
            for (final row in await txn.query(
              '_sync_change_log',
              columns: ['row_id'],
              where: 'table_name = ? AND row_id IN ($marks)',
              whereArgs: [table, ...chunk],
            ))
              row['row_id']?.toString() ?? '',
          };
          for (final deletion in deletions) {
            final rowId = deletion['row_id']?.toString() ?? '';
            final liveUpdatedAt = entry.value[rowId] ?? '';
            if (pending.contains(rowId) &&
                !supersedes(
                  liveUpdatedAt,
                  deletion['deleted_at']?.toString() ?? '',
                )) {
              continue;
            }
            dropped += await txn.delete(
              'SyncTombstones',
              where: 'table_name = ? AND row_id = ?',
              whereArgs: [table, rowId],
            );
          }
        }
      }
    });
    if (dropped > 0) {
      debugPrint('Sync: $dropped local deletions replaced by restored rows.');
    }
    return dropped;
  }

  Future<void> importWorkshopData(
    Map<String, dynamic> data, {
    bool replaceAllData = false,
  }) async {
    final workshopData = <String, dynamic>{};
    for (final table in SqlDatabase.workshopTables) {
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
    if (workshopData.containsKey('WorkshopPriceOverrides')) {
      await applyWorkshopBasePriceOverrides();
    }
  }

  Future<String> getDatabaseFilePath() async {
    String dbName = 'test.db';
    if (kIsWeb) {
      return dbName;
    } else {
      String dataPath = await SqlDatabase._getWritableDatabasesPath();
      return join(dataPath, dbName);
    }
  }

  Future<void> exportDatabaseFile(BuildContext context) async {
    try {
      if (kIsWeb) {
        throw Exception(
          'النسخ الاحتياطي المباشر لملفات قاعدة البيانات غير مدعوم على الويب. يرجى استخدام تصدير JSON.',
        );
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
            content: Text(
              'تم تصدير ملف قاعدة البيانات بنجاح!',
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
            'فشل التصدير: $e',
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
        debugPrint(
          '--- AutoBackup: Successfully exported to ${targetFile.path} ---',
        );
      }
    } catch (e) {
      debugPrint('--- AutoBackup: Failed to run auto daily backup: $e ---');
    }
  }

  Future<void> importDatabaseFile(
    BuildContext context, {
    String? successMessage,
    String? failurePrefix,
  }) async {
    try {
      if (kIsWeb) {
        throw Exception(
          'استيراد ملف قاعدة البيانات المباشر غير مدعوم على الويب. يرجى استخدام استيراد JSON.',
        );
      }
      final params = const OpenFileDialogParams();
      final filePath = await FlutterFileDialog.pickFile(params: params);
      if (filePath != null) {
        final dbPath = await getDatabaseFilePath();
        if (SqlDatabase._db != null) {
          await SqlDatabase._db!.close();
        }
        // Do not keep a completed/opening handle or SQLite WAL files from the
        // previous database. Reusing either after replacing the main file can
        // make screens continue to see the pre-import rows.
        SqlDatabase.resetDb();
        for (final suffix in const ['-wal', '-shm', '-journal']) {
          final sidecar = File('$dbPath$suffix');
          if (await sidecar.exists()) {
            try {
              await sidecar.delete();
            } catch (_) {}
          }
        }
        final selectedFile = File(filePath);
        await selectedFile.copy(dbPath);
        SqlDatabase._db = await initDb();
        // Refresh every mounted screen immediately and merge workshop rows
        // that exist only in the imported backup (for example orders 49-52)
        // into Supabase before a later cloud refresh can hide them again.
        await CloudSyncService().notifyDatabaseImported();
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              successMessage ??
                  '\u062a\u0645 \u0627\u0633\u062a\u064a\u0631\u0627\u062f \u0642\u0627\u0639\u062f\u0629 \u0627\u0644\u0628\u064a\u0627\u0646\u0627\u062a \u0628\u0646\u062c\u0627\u062d! \u064a\u0631\u062c\u0649 \u0625\u0639\u0627\u062f\u0629 \u062a\u0634\u063a\u064a\u0644 \u0627\u0644\u062a\u0637\u0628\u064a\u0642 \u0644\u062a\u062d\u062f\u064a\u062b \u0643\u0627\u0641\u0629 \u0627\u0644\u0634\u0627\u0634\u0627\u062a.',
              style: const TextStyle(fontFamily: 'Cairo'),
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
            '${failurePrefix ?? '\u0641\u0634\u0644 \u0627\u0644\u0627\u0633\u062a\u064a\u0631\u0627\u062f'}: $e',
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
              'جاري بدء التحميل على المتصفح...',
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
                'تم تصدير نسخة JSON الاحتياطية بنجاح!',
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
            'فشل تصدير JSON: $e',
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
                content: Text(
                  'تم استيراد نسخة JSON الاحتياطية بنجاح! يرجى إعادة تشغيل التطبيق.',
                  style: TextStyle(fontFamily: 'Cairo'),
                ),
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
          content: Text(
            'فشل استيراد JSON: $e',
            style: const TextStyle(fontFamily: 'Cairo'),
          ),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> insertOrUpdateSafeLegacy(
    String table,
    Map<String, dynamic> rawData,
    String idColumn,
  ) async {
    final database = await db;
    if (database == null || !SqlDatabase._isSafeSqlIdentifier(table)) return;

    try {
      final columns = await _tableColumns(database, table);
      final data = _sanitizeImportRow(Map<String, dynamic>.from(rawData))
        ..removeWhere((key, value) => !columns.contains(key));
      if (data.isEmpty) return;

      // Some legacy/cloud tombstones contain only the primary key. They are
      // not complete business rows and must not be inserted into tables with
      // required columns (notably Treasury), otherwise SQLite rejects the
      // INSERT with a NOT NULL constraint error.
      if (table == 'Treasury' &&
          (!data.containsKey('transaction_type') ||
              !data.containsKey('amount') ||
              !data.containsKey('recorded_by'))) {
        return;
      }

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

  /// Returns the database file size in bytes on disk (or 0 on web).
  Future<int> getDatabaseFileSizeBytes() async {
    if (kIsWeb) return 0;
    try {
      final dataPath = await SqlDatabase._getWritableDatabasesPath();
      final file = File(join(dataPath, 'test.db'));
      if (await file.exists()) {
        return await file.length();
      }
    } catch (_) {}
    return 0;
  }

  /// Reclaims unused disk space by running SQLite VACUUM.
  Future<void> vacuumDatabase() async {
    Database? myDb = await db;
    if (myDb == null) return;
    try {
      await myDb.execute('VACUUM');
    } catch (e) {
      debugPrint('Error running VACUUM: $e');
    }
  }

  /// Returns row counts for major database categories.
  Future<Map<String, int>> getStorageCategoryCounts() async {
    Database? myDb = await db;
    if (myDb == null) return {};

    Future<int> countTable(String table, [String? where]) async {
      try {
        final query = where != null
            ? 'SELECT COUNT(*) as c FROM $table WHERE $where'
            : 'SELECT COUNT(*) as c FROM $table';
        final res = await myDb.rawQuery(query);
        return (res.first['c'] as num?)?.toInt() ?? 0;
      } catch (_) {
        return 0;
      }
    }

    final int commandesCount =
        await countTable('Commandes') + await countTable('Commandes_details');
    final int achatsCount =
        await countTable('Achats') +
        await countTable('Achat_items') +
        await countTable('Achat_Details');
    final int inventoryCount =
        await countTable('InventoryTransactions') +
        await countTable('CurrentStock') +
        await countTable('MaterialRemnants');
    final int treasuryCount =
        await countTable('Treasury') +
        await countTable('WorkerTransactions') +
        await countTable('PaymentAllocations');
    final int catalogCount =
        await countTable('Profile') +
        await countTable('Series') +
        await countTable('ProfileColors');
    final int clientsSuppliersCount =
        await countTable('Client') +
        await countTable('Suppliers') +
        await countTable('Employees');
    final int trashCount =
        await countTable('Commandes', 'is_deleted = 1') +
        await countTable('Achats', 'is_deleted = 1');

    return {
      'commandes': commandesCount,
      'achats': achatsCount,
      'inventory': inventoryCount,
      'treasury': treasuryCount,
      'catalog': catalogCount,
      'clients_suppliers': clientsSuppliersCount,
      'trash': trashCount,
    };
  }
}
