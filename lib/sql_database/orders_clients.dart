part of '../sql_database.dart';

/// Orders, clients, projects, measurements, deliveries and activity logs.
extension SqlDatabaseOrders on SqlDatabase {
  Future<String> _currentOrderEditor() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString('user_display_name')?.trim() ?? '';
      final workshopName = prefs.getString('workshop_name')?.trim() ?? '';
      if (cached.isNotEmpty && cached != workshopName) return cached;
    } catch (_) {}

    try {
      final user = AppAuthService().currentUser;
      final displayName = user?.displayName?.trim() ?? '';
      if (displayName.isNotEmpty) return displayName;
      final email = user?.email?.trim() ?? '';
      if (email.isNotEmpty) return email;
    } catch (_) {}
    return 'system';
  }

  Future<int> _reserveNextClientCode(DatabaseExecutor executor) async {
    await _ensureClientCodeInfrastructure(executor);
    final sequenceRows = await executor.query(
      'ClientCodeSequence',
      columns: ['last_code'],
      where: 'id = 1',
      limit: 1,
    );
    final sequenceValue = sequenceRows.isEmpty
        ? 0
        : _positiveInt(sequenceRows.first['last_code']);
    final maxRows = await executor.rawQuery(
      'SELECT MAX(client_code) AS max_code FROM Client',
    );
    final maxExisting = maxRows.isEmpty
        ? 0
        : _positiveInt(maxRows.first['max_code']);
    final nextCode =
        (sequenceValue > maxExisting ? sequenceValue : maxExisting) + 1;
    await executor.update('ClientCodeSequence', {
      'last_code': nextCode,
    }, where: 'id = 1');
    return nextCode;
  }

  Future<bool> setOrderPinned({
    required int orderId,
    required bool pinned,
  }) async {
    final myDb = await db;
    if (myDb == null) return false;
    await _ensureOrderPinningInfrastructure(myDb);
    final changed = await myDb.update(
      'Commandes',
      {
        'is_pinned': pinned ? 1 : 0,
        'pinned_at': pinned ? DateTime.now().toUtc().toIso8601String() : null,
      },
      where: 'id = ?',
      whereArgs: [orderId],
    );
    if (changed > 0) {
      await CloudSyncService().notifyChangeImmediate();
    }
    return changed > 0;
  }

  Future<int> _reserveNextOrderCode(DatabaseExecutor executor) async {
    await _ensureOrderCodeInfrastructure(executor);
    final sequenceRows = await executor.query(
      'OrderCodeSequence',
      columns: ['last_code'],
      where: 'id = 1',
      limit: 1,
    );
    final sequenceValue = sequenceRows.isEmpty
        ? 0
        : _positiveInt(sequenceRows.first['last_code']);
    final maxRows = await executor.rawQuery(
      'SELECT MAX(order_code) AS max_code FROM Commandes',
    );
    final maxExisting = maxRows.isEmpty
        ? 0
        : _positiveInt(maxRows.first['max_code']);
    final nextCode =
        (sequenceValue > maxExisting ? sequenceValue : maxExisting) + 1;
    await executor.update('OrderCodeSequence', {
      'last_code': nextCode,
    }, where: 'id = 1');
    return nextCode;
  }

  Future<List<Map<String, dynamic>>> readClient() async {
    Database? myDb = await db;
    return await myDb!.rawQuery('SELECT * FROM Client');
  }

  /// Ensures an internal workshop customer exists for workshop+store activity
  Future<Map<String, dynamic>> ensureInternalWorkshopClient() async {
    final myDb = await db;
    if (myDb == null) return {};
    await _ensureClientBusinessSegment(myDb);
    final existing = await myDb.query(
      'Client',
      where: "business_segment = 'internal_workshop'",
      orderBy: 'id ASC',
    );
    if (existing.isNotEmpty) {
      if (existing.length > 1) {
        final primaryId = existing.first['id'];
        final duplicateIds = existing.skip(1).map((e) => e['id']).toList();
        final inClause = duplicateIds.map((id) => "'$id'").join(',');
        await myDb.rawUpdate(
          'UPDATE MaterialSales SET client_id = ? WHERE client_id IN ($inClause)',
          [primaryId],
        );
        await myDb.rawDelete('DELETE FROM Client WHERE id IN ($inClause)');
        CloudSyncService().notifyChangeImmediate();
      }
      return existing.first;
    }
    final now = DateTime.now().toUtc().toIso8601String();
    final clientCode = await _reserveNextClientCode(myDb);
    final newId = await myDb.insert(
      'Client',
      SqlDatabase._withDistributedId({
        'client_code': clientCode,
        'firstname': 'الورشة',
        'lastname': '(داخلي)',
        'phone1': '',
        'phone2': '',
        'email': '',
        'address': 'داخلي - ورشة المؤسسة',
        'business_segment': 'internal_workshop',
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

  Future<void> setClientBusinessSegment(int clientId, String segment) async {
    final myDb = await db;
    if (myDb == null) return;
    await _ensureClientBusinessSegment(myDb);
    final normalized =
        const {
          'windows',
          'materials',
          'both',
          'internal_workshop',
        }.contains(segment)
        ? segment
        : 'windows';
    await myDb.update(
      'Client',
      {
        'business_segment': normalized,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [clientId],
    );
    CloudSyncService().notifyChangeImmediate();
  }

  /// Client primary keys are intentionally large distributed IDs so records
  /// created offline on two devices cannot collide.  Screens and documents
  /// must show a short, human-friendly number instead of exposing that key.
  ///
  /// This method leaves [readClient] unchanged because synchronisation needs
  /// the exact database rows, without this computed display-only field.
  Future<List<Map<String, dynamic>>> readClientsForDisplay() async {
    final myDb = await db;
    if (myDb == null) return [];
    await _backfillClientCodes(myDb);
    return _queryClientsForDisplay(database: myDb);
  }

  Future<List<Map<String, dynamic>>> _queryClientsForDisplay({
    Database? database,
    String? whereClause,
    List<Object?>? whereArgs,
  }) async {
    final myDb = database ?? await db;
    if (myDb == null) return [];

    final where = (whereClause ?? '').trim();
    final filter = where.isEmpty ? '' : 'WHERE $where';
    return myDb.rawQuery('''
      SELECT c.*,
        c.client_code AS display_number
      FROM Client AS c
      $filter
      ORDER BY c.client_code ASC, c.id ASC
      ''', whereArgs);
  }

  String _normaliseClientName(String value) => value
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[إأآا]'), 'ا')
      .replaceAll('ة', 'ه')
      .replaceAll('ى', 'ي')
      .replaceAll(RegExp(r'[\u064B-\u065F\u0670]'), '')
      .replaceAll(RegExp(r'\s+'), ' ');

  String _normaliseClientPhone(String value) =>
      value.replaceAll(RegExp(r'\D'), '');

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
    if (myDb == null) throw StateError('قاعدة بيانات الزبائن غير متاحة');
    final clientId = SqlDatabase._nextDistributedId();
    await myDb.transaction((txn) async {
      await _ensureUniqueClientIdentity(
        txn,
        firstname: firstname,
        lastname: lastname,
        phone1: phone1,
        phone2: phone2,
      );
      await _backfillClientCodes(txn);
      final clientCode = await _reserveNextClientCode(txn);
      await txn.insert('Client', {
        'id': clientId,
        'client_code': clientCode,
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
        'created_at': now,
        'updated_at': now,
        'creation_platform': _currentCreationPlatform,
      });
    });
    CloudSyncService().notifyChangeImmediate();
    return clientId;
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
    if (myDb == null) throw StateError('قاعدة بيانات الزبائن غير متاحة');
    final res = await myDb.transaction((txn) async {
      await _ensureUniqueClientIdentity(
        txn,
        firstname: firstname,
        lastname: lastname,
        phone1: phone1,
        phone2: phone2,
        excludingId: id,
      );
      return txn.update(
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
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [id],
      );
    });
    CloudSyncService().notifyChangeImmediate();
    return res;
  }

  Future<int> updateClientCoordinates(
    int id,
    double? latitude,
    double? longitude,
  ) async {
    Database? myDb = await db;
    if (myDb == null) return 0;
    try {
      var res = await myDb.update(
        'Client',
        {
          'latitude': latitude,
          'longitude': longitude,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [id],
      );
      CloudSyncService().notifyChangeImmediate();
      return res;
    } catch (_) {
      return 0;
    }
  }

  Future<int> deleteClient(dynamic id) {
    return _retryAfterDatabaseMove(() => _deleteClientOnce(id));
  }

  Future<int> _deleteClientOnce(dynamic id) async {
    Database? myDb = await db;
    if (myDb == null) return 0;
    // Old installations may not have opened the database since deletion
    // tracking was introduced. Ensure the Client delete creates a tombstone
    // before it is queued for Firebase.
    await _ensureSyncTombstoneInfrastructure(myDb);
    final parsedInt = id is num
        ? id.toInt()
        : int.tryParse(id.toString().trim());
    final strVal = id.toString().trim();
    int res = 0;
    if (parsedInt != null) {
      res = await myDb.rawDelete(
        'DELETE FROM Client WHERE id = ? OR CAST(id AS TEXT) = ?',
        [parsedInt, strVal],
      );
    } else {
      res = await myDb.rawDelete(
        'DELETE FROM Client WHERE CAST(id AS TEXT) = ?',
        [strVal],
      );
    }
    if (res > 0) {
      CloudSyncService().notifyChangeImmediate();
    }
    return res;
  }

  //////////////////////////////////// Measurements //////////////////////////////////////
  Future<int> insertMeasurement(Map<String, dynamic> data) async {
    Database? myDb = await db;
    var res = await myDb!.insert('Measurements', SqlDatabase._withDistributedId(data));
    CloudSyncService().notifyChange();
    return res;
  }

  Future<List<Map<String, dynamic>>> readMeasurements() async {
    Database? myDb = await db;
    return await myDb!.query('Measurements', orderBy: 'id DESC');
  }

  Future<int> deleteMeasurement(int id) async {
    Database? myDb = await db;
    var res = await myDb!.delete(
      'Measurements',
      where: 'id = ?',
      whereArgs: [id],
    );
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

  /// Search variant for customer-facing lists.  The returned maps contain
  /// [display_number], while [id] remains the internal foreign-key value.
  Future<List<Map<String, dynamic>>> searchClientsForDisplay(
    String query,
  ) async {
    final myDb = await db;
    if (myDb == null) return [];
    await _backfillClientCodes(myDb);
    final terms = query
        .trim()
        .split(RegExp(r'\s+'))
        .where((term) => term.isNotEmpty)
        .toList();
    if (terms.isEmpty) return _queryClientsForDisplay(database: myDb);

    final whereClause = terms
        .map(
          (_) =>
              '(c.firstname LIKE ? OR c.lastname LIKE ? OR c.phone1 LIKE ? OR c.phone2 LIKE ? OR c.address LIKE ?)',
        )
        .join(' AND ');
    final whereArgs = <Object?>[];
    for (final term in terms) {
      whereArgs.addAll(['%$term%', '%$term%', '%$term%', '%$term%', '%$term%']);
    }
    return _queryClientsForDisplay(
      database: myDb,
      whereClause: whereClause,
      whereArgs: whereArgs,
    );
  }

  Future<List<Map<String, dynamic>>> getClientById(int id) async {
    final dbclient = await db;
    return await dbclient!.query('Client', where: 'id = ?', whereArgs: [id]);
  }

  ///////////////////////////////// Projects ////////////////////////////////
  Future<int> insertProject(
    String name,
    int clientId,
    String? description,
  ) async {
    Database? myDb = await db;
    final now = DateTime.now().toUtc().toIso8601String();
    var res = await myDb!.rawInsert(
      'INSERT INTO Projects (id, name, client_id, description, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?)',
      [SqlDatabase._nextDistributedId(), name, clientId, description, now, now],
    );
    CloudSyncService().notifyChangeImmediate();
    return res;
  }

  Future<int> updateProject(
    int id,
    String name,
    int clientId,
    String? description,
  ) async {
    Database? myDb = await db;
    var res = await myDb!.update(
      'Projects',
      {
        'name': name,
        'client_id': clientId,
        'description': description,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    CloudSyncService().notifyChangeImmediate();
    return res;
  }

  Future<int> deleteProject(int id) async {
    Database? myDb = await db;
    await myDb!.rawUpdate(
      'UPDATE Commandes SET project_id = NULL WHERE project_id = ?',
      [id],
    );
    var res = await myDb.rawDelete('DELETE FROM Projects WHERE id = ?', [id]);
    CloudSyncService().notifyChangeImmediate();
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
    final list = await myDb!.rawQuery(
      '''
      SELECT p.*, c.firstname, c.lastname, c.phone1 as phone, c.email
      FROM Projects p
      INNER JOIN Client c ON p.client_id = c.id
      WHERE p.id = ?
    ''',
      [id],
    );
    return list.isNotEmpty ? list.first : null;
  }

  Future<List<Map<String, dynamic>>> readCommandesForProject(
    int projectId,
  ) async {
    final myDb = await db;
    if (myDb == null) return [];
    await _backfillOrderCodes(myDb);
    return await myDb.rawQuery(
      '''
      SELECT co.*,
        co.order_code AS display_number,
        cl.firstname, cl.lastname 
      FROM Commandes co
      INNER JOIN Client cl ON co.client_id = cl.id
      WHERE co.project_id = ? AND (co.is_deleted IS NULL OR co.is_deleted = 0)
      ORDER BY co.created_at DESC
    ''',
      [projectId],
    );
  }

  Future<List<Map<String, dynamic>>> readProjectsForClient(int clientId) async {
    Database? myDb = await db;
    return await myDb!.rawQuery(
      'SELECT * FROM Projects WHERE client_id = ? ORDER BY updated_at DESC',
      [clientId],
    );
  }

  ///////////////////////////////// Commande ////////////////////////////////
  Future<List<Map<String, dynamic>>> readCommande() async {
    Database? myDb = await db;
    if (myDb == null) return [];
    await _ensureOrderTrashInfrastructure(myDb);
    return await myDb.rawQuery(
      'SELECT * FROM Commandes WHERE (is_deleted IS NULL OR is_deleted = 0)',
    );
  }

  Future<List<Map<String, dynamic>>> readCommandesWithClients() async {
    final myDb = await db;
    if (myDb == null) return [];
    try {
      await _ensureOrderQueryInfrastructure(myDb);
    } catch (e) {
      debugPrint('Error preparing order query infrastructure: $e');
    }

    try {
      return await myDb.rawQuery('''
        SELECT c.*,
          c.order_code AS display_number,
          COALESCE(NULLIF(TRIM(c.created_at), ''), NULLIF(TRIM(c.updated_at), '')) as created_at,
          cl.firstname, cl.lastname, cl.phone1 as phone,
          cl.address as client_address,
          cl.latitude as client_latitude,
          cl.longitude as client_longitude,
          p.name as project_name,
          p.description as project_description
        FROM Commandes c
        LEFT JOIN Client cl ON (c.client_id = cl.id OR CAST(c.client_id AS TEXT) = CAST(cl.id AS TEXT))
        LEFT JOIN Projects p ON c.project_id = p.id
        WHERE (c.is_deleted IS NULL OR c.is_deleted = 0)
        ORDER BY COALESCE(NULLIF(TRIM(c.created_at), ''), NULLIF(TRIM(c.updated_at), ''), c.id) DESC
      ''');
    } catch (e) {
      debugPrint(
        'Primary readCommandesWithClients query failed: $e, trying fallback...',
      );
      // Resilient fallback query in case of schema discrepancy
      try {
        return await myDb.rawQuery('''
          SELECT c.*,
            c.id AS display_number,
            cl.firstname, cl.lastname, cl.phone1 as phone,
            cl.address as client_address
          FROM Commandes c
          LEFT JOIN Client cl ON (c.client_id = cl.id OR CAST(c.client_id AS TEXT) = CAST(cl.id AS TEXT))
          WHERE (c.is_deleted IS NULL OR c.is_deleted = 0)
          ORDER BY c.id DESC
        ''');
      } catch (fallbackError) {
        debugPrint('Fallback order query also failed: $fallbackError');
        // Ultimate fallback: simple query on Commandes
        try {
          return await myDb.query('Commandes');
        } catch (_) {
          return [];
        }
      }
    }
  }

  Future<List<Map<String, dynamic>>> readTrashCommandesWithClients() async {
    final myDb = await db;
    if (myDb == null) return [];
    try {
      await _ensureOrderQueryInfrastructure(myDb);
    } catch (_) {}
    return await myDb.rawQuery('''
      SELECT c.*,
        c.order_code AS display_number,
        COALESCE(NULLIF(TRIM(c.created_at), ''), NULLIF(TRIM(c.updated_at), '')) as created_at,
        c.deleted_at,
        cl.firstname, cl.lastname, cl.phone1 as phone,
        cl.address as client_address,
        cl.latitude as client_latitude,
        cl.longitude as client_longitude,
        p.name as project_name,
        p.description as project_description
      FROM Commandes c
      LEFT JOIN Client cl ON (c.client_id = cl.id OR CAST(c.client_id AS TEXT) = CAST(cl.id AS TEXT))
      LEFT JOIN Projects p ON c.project_id = p.id
      WHERE c.is_deleted = 1
      ORDER BY COALESCE(NULLIF(TRIM(c.deleted_at), ''), NULLIF(TRIM(c.updated_at), ''), c.id) DESC
    ''');
  }

  Future<int> countTrashCommandes() async {
    final myDb = await db;
    if (myDb == null) return 0;
    await _ensureOrderTrashInfrastructure(myDb);
    final res = await myDb.rawQuery(
      'SELECT COUNT(*) as count FROM Commandes WHERE is_deleted = 1',
    );
    if (res.isNotEmpty) {
      return (res.first['count'] as num?)?.toInt() ?? 0;
    }
    return 0;
  }

  Future<int> updateCommandeStatus(
    int id,
    String newStatus, {
    bool skipAllocationSync = false,
    bool resetWorkerProgress = false,
  }) async {
    Database? myDb = await db;
    final updatedBy = await _currentOrderEditor();
    var res = await myDb!.update(
      'Commandes',
      {
        'status': newStatus,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
        'updated_by': updatedBy,
      },
      where: 'id = ?',
      whereArgs: [id],
    );

    if (!skipAllocationSync) {
      await syncAllocationsFromOrderStatus(
        id,
        newStatus,
        resetWorkerProgress: resetWorkerProgress,
      );
    }

    // The local database is authoritative for the current action. Cloud
    // delivery continues in the background and must never freeze the UI.
    unawaited(_uploadOrderStatusToCloud(id, newStatus, updatedBy: updatedBy));
    CloudSyncService().notifyChange();
    return res;
  }

  Future<int> updateCommandeDetailConfirmedMesures(
    int detailId,
    String instancesJson,
    String confirmedJson,
  ) async {
    Database? myDb = await db;
    if (myDb == null) return 0;

    final detailRows = await myDb.query(
      'Commandes_details',
      columns: ['id_commandes'],
      where: 'id = ?',
      whereArgs: [detailId],
      limit: 1,
    );
    final commandeId = detailRows.isEmpty
        ? null
        : (detailRows.first['id_commandes'] as num?)?.toInt();
    if (commandeId != null) {
      await snapshotCommande(
        commandeId,
        actionType: 'UPDATE',
        afterHeader: {
          'detail_id': detailId,
          'confirmed_measurements_changed': true,
        },
      );
    }

    var res = await myDb.update(
      'Commandes_details',
      {
        'instances_json': instancesJson,
        'confirmed_mesures_json': confirmedJson,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [detailId],
    );

    await _uploadConfirmedMeasurementsToCloud(
      detailId,
      instancesJson,
      confirmedJson,
    );
    CloudSyncService().notifyChange();
    return res;
  }

  /// Returns 1-based sequential order index for display/document numbering (1, 2, 3, 4...)
  Future<int> getOrderSequenceNumber(int orderId) async {
    try {
      final myDb = await db;
      if (myDb == null) return 1;
      await _backfillOrderCodes(myDb);
      final orderRows = await myDb.query(
        'Commandes',
        columns: ['order_code'],
        where: 'id = ? OR CAST(id AS TEXT) = ?',
        whereArgs: [orderId, orderId.toString()],
        limit: 1,
      );
      if (orderRows.isEmpty) return 1;
      final code = _positiveInt(orderRows.first['order_code']);
      if (code > 0) return code;
    } catch (e) {
      debugPrint('Error computing order sequence number: $e');
    }
    return (orderId % 1000).abs();
  }

  /// Returns the immutable customer number shown in tables and documents.
  /// This must never be derived from the current row count because deletion
  /// of another client must not alter a customer's identifier.
  Future<int> getClientSequenceNumber(int clientId) async {
    if (clientId <= 0) return 0;

    try {
      final myDb = await db;
      if (myDb == null) return 0;
      await _backfillClientCodes(myDb);
      final rows = await myDb.query(
        'Client',
        columns: ['client_code'],
        where: 'id = ? OR CAST(id AS TEXT) = ?',
        whereArgs: [clientId, clientId.toString()],
        limit: 1,
      );
      if (rows.isEmpty) return 0;
      return _positiveInt(rows.first['client_code']);
    } catch (e) {
      debugPrint('Error computing client sequence number: $e');
      return 0;
    }
  }

  Future<Map<String, dynamic>?> readCommandeWithClientById(int id) async {
    final myDb = await db;
    if (myDb == null) return null;
    await _backfillOrderCodes(myDb);
    final rows = await myDb.rawQuery(
      '''
      SELECT c.*,
        c.order_code AS display_number,
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

  Future<List<Map<String, dynamic>>> readCommandeDetails(
    dynamic idCommande,
  ) async {
    Database? myDb = await db;
    if (myDb == null) return [];
    final parsedInt = idCommande is num
        ? idCommande.toInt()
        : int.tryParse(idCommande.toString().trim());
    final strVal = idCommande.toString().trim();
    if (parsedInt != null) {
      return await myDb.query(
        'Commandes_details',
        where: 'id_commandes = ? OR CAST(id_commandes AS TEXT) = ?',
        whereArgs: [parsedInt, strVal],
        orderBy: 'sort_order ASC, id ASC',
      );
    }
    return await myDb.query(
      'Commandes_details',
      where: 'CAST(id_commandes AS TEXT) = ?',
      whereArgs: [strVal],
      orderBy: 'sort_order ASC, id ASC',
    );
  }

  Future<bool> isOrderFullyManufactured(int orderId) async {
    Database? myDb = await db;
    if (myDb == null || orderId <= 0) return false;

    final details = await myDb.query(
      'Commandes_details',
      where: 'id_commandes = ?',
      whereArgs: [orderId],
    );
    if (details.isEmpty) return false;

    int totalRequiredQty = 0;
    for (final d in details) {
      totalRequiredQty += (d['quantity'] as num?)?.toInt() ?? 0;
    }
    if (totalRequiredQty == 0) return false;

    final manufacturedAllocs = await myDb.rawQuery(
      '''
      SELECT SUM(wa.quantity) as total_mfg_qty
      FROM WorkerAllocations wa
      INNER JOIN Commandes_details cd ON wa.commande_detail_id = cd.id
      WHERE cd.id_commandes = ? AND wa.is_manufactured = 1
    ''',
      [orderId],
    );

    int totalMfgQty = 0;
    if (manufacturedAllocs.isNotEmpty &&
        manufacturedAllocs.first['total_mfg_qty'] != null) {
      totalMfgQty = (manufacturedAllocs.first['total_mfg_qty'] as num).toInt();
    }

    return totalMfgQty >= totalRequiredQty;
  }

  /// Saves the order header and every detail row as one SQLite transaction.
  /// If any row fails, SQLite rolls the whole operation back so an existing
  /// order can never keep its total while losing Commandes_details.
  Future<int> saveCommandeWithDetails({
    int? idCommande,
    required int clientId,
    required String status,
    required String description,
    required double remise,
    required double tva,
    required double total,
    required double netPayable,
    required String createdAt,
    int? projectId,
    required List<Map<String, dynamic>> details,
    String? updatedBy,
  }) async {
    final myDb = await db;
    if (myDb == null) {
      throw StateError('قاعدة البيانات غير متاحة.');
    }
    await _backfillOrderCodes(myDb);
    if (details.isEmpty) {
      throw StateError('لا يمكن حفظ طلبية بدون تفاصيل.');
    }
    if (!total.isFinite || !netPayable.isFinite) {
      throw StateError('مجموع الطلبية غير صالح.');
    }

    int? previousClientId;
    if (idCommande != null) {
      final previousOrder = await myDb.query(
        'Commandes',
        columns: ['client_id'],
        where: 'id = ? OR CAST(id AS TEXT) = ?',
        whereArgs: [idCommande, idCommande.toString()],
        limit: 1,
      );
      if (previousOrder.isNotEmpty) {
        previousClientId = SqlDatabase._paymentRecordId(previousOrder.first['client_id']);
      }
    }

    // File access is intentionally completed before starting the transaction.
    // The SQL transaction then stays short and cannot leave half an order.
    int? detailIdFrom(dynamic rawId) {
      if (rawId is int) return rawId;
      if (rawId is num) return rawId.toInt();
      return int.tryParse(rawId?.toString() ?? '');
    }

    final preparedDetails = await Future.wait(
      details.asMap().entries.map((entry) async {
        final rawDetail = entry.value;
        // Keep the detail ID while editing.  It is the cloud-sync identity of
        // this drawing; replacing it would allow an old copy (and its old
        // colour) to be merged back into the order.
        final detail = Map<String, dynamic>.from(rawDetail)
          ..remove('id_commandes')
          ..['sort_order'] = entry.key;
        final drawingPath = detail['drawing_image_path']?.toString() ?? '';
        if (drawingPath.isNotEmpty &&
            (detail['drawing_image_base64']?.toString().isEmpty ?? true)) {
          try {
            final drawingFile = File(drawingPath);
            if (await drawingFile.exists()) {
              detail['drawing_image_base64'] = base64Encode(
                await drawingFile.readAsBytes(),
              );
            }
          } catch (_) {}
        }
        return detail;
      }),
    );

    final editor = updatedBy?.trim().isNotEmpty == true
        ? updatedBy!.trim()
        : await _currentOrderEditor();
    var createdNewOrder = idCommande == null;
    final savedId = await myDb.transaction<int>((txn) async {
      final now = DateTime.now().toUtc().toIso8601String();
      late final int orderId;

      if (idCommande == null) {
        final newOrderId = SqlDatabase._nextDistributedId();
        final orderCode = await _reserveNextOrderCode(txn);
        final initialStatus =
            (status.trim().isEmpty ||
                status.trim().toLowerCase() == 'pending' ||
                status.trim().toLowerCase() == 'en attente' ||
                status.trim().toLowerCase() == 'en_attente' ||
                status.trim().contains('انتظار'))
            ? 'Nouveau'
            : status;
        await txn.insert('Commandes', {
          'id': newOrderId,
          'order_code': orderCode,
          'client_id': clientId,
          'status': initialStatus,
          'description': description,
          'remise': remise,
          'tva': tva,
          'total': total,
          'net_payable': netPayable,
          'advance_payment': 0.0,
          'payment_status': 'Unpaid',
          'created_at': createdAt,
          'updated_at': now,
          'updated_by': editor,
          'project_id': projectId,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
        orderId = newOrderId;
      } else {
        orderId = idCommande;
        final existing = await txn.query(
          'Commandes',
          columns: ['advance_payment', 'order_code'],
          where: 'id = ? OR CAST(id AS TEXT) = ?',
          whereArgs: [orderId, orderId.toString()],
          limit: 1,
        );
        if (existing.isEmpty) {
          createdNewOrder = true;
          final orderCode = orderId > 0 && orderId < 100000
              ? orderId
              : await _reserveNextOrderCode(txn);
          await txn.insert('Commandes', {
            'id': orderId,
            'order_code': orderCode,
            'client_id': clientId,
            'status': status,
            'description': description,
            'remise': remise,
            'tva': tva,
            'total': total,
            'net_payable': netPayable,
            'advance_payment': 0.0,
            'payment_status': 'Unpaid',
            'created_at': createdAt,
            'updated_at': now,
            'updated_by': editor,
            'project_id': projectId,
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        } else {
          final advance =
              (existing.first['advance_payment'] as num?)?.toDouble() ?? 0.0;
          final existingOrderCode = _positiveInt(existing.first['order_code']);
          final orderCode = existingOrderCode > 0
              ? existingOrderCode
              : await _reserveNextOrderCode(txn);
          final paymentStatus = advance >= netPayable
              ? 'Paid'
              : (advance > 0 ? 'Partial' : 'Unpaid');
          await txn.update(
            'Commandes',
            {
              'order_code': orderCode,
              'client_id': clientId,
              'description': description,
              'remise': remise,
              'tva': tva,
              'total': total,
              'net_payable': netPayable,
              'payment_status': paymentStatus,
              'created_at': createdAt,
              'updated_at': now,
              'updated_by': editor,
              'project_id': projectId,
            },
            where: 'id = ? OR CAST(id AS TEXT) = ?',
            whereArgs: [orderId, orderId.toString()],
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
      }

      final existingDetails = await txn.query(
        'Commandes_details',
        columns: ['id'],
        where: 'id_commandes = ? OR CAST(id_commandes AS TEXT) = ?',
        whereArgs: [orderId, orderId.toString()],
      );
      final existingDetailIds = <int>{
        for (final row in existingDetails)
          if (detailIdFrom(row['id']) != null) detailIdFrom(row['id'])!,
      };
      final retainedDetailIds = <int>{};

      for (final detail in preparedDetails) {
        final existingDetailId = detailIdFrom(detail['id']);
        final row = Map<String, dynamic>.from(detail)
          ..remove('id')
          ..remove('id_commandes')
          ..['id_commandes'] = orderId
          ..['updated_at'] = now;

        if (existingDetailId != null &&
            existingDetailIds.contains(existingDetailId)) {
          await txn.update(
            'Commandes_details',
            row,
            where: 'id = ? OR CAST(id AS TEXT) = ?',
            whereArgs: [existingDetailId, existingDetailId.toString()],
          );
          retainedDetailIds.add(existingDetailId);
        } else {
          final newDetailId = SqlDatabase._nextDistributedId();
          await txn.insert('Commandes_details', {
            ...row,
            'id': newDetailId,
          }, conflictAlgorithm: ConflictAlgorithm.replace);
          retainedDetailIds.add(newDetailId);
        }
      }

      // Delete only drawings that the user actually removed.  This keeps a
      // stable identity for the remaining drawings and produces tombstones
      // only for genuine removals.
      for (final existingDetailId in existingDetailIds) {
        if (retainedDetailIds.contains(existingDetailId)) continue;
        await txn.delete(
          'WorkerAllocations',
          where:
              'commande_detail_id = ? OR CAST(commande_detail_id AS TEXT) = ?',
          whereArgs: [existingDetailId, existingDetailId.toString()],
        );
        await txn.delete(
          'Commandes_details',
          where: 'id = ? OR CAST(id AS TEXT) = ?',
          whereArgs: [existingDetailId, existingDetailId.toString()],
        );
      }

      final countResult = await txn.rawQuery(
        'SELECT COUNT(*) AS count FROM Commandes_details '
        'WHERE id_commandes = ? OR CAST(id_commandes AS TEXT) = ?',
        [orderId, orderId.toString()],
      );
      final savedDetails = (countResult.first['count'] as num?)?.toInt() ?? 0;
      if (savedDetails != preparedDetails.length) {
        throw StateError(
          'لم تُحفظ كل تفاصيل الطلبية '
          '(${preparedDetails.length} مطلوبة، $savedDetails محفوظة).',
        );
      }
      return orderId;
    });

    // Apply any retained credit to this order without creating another cash
    // receipt. Also rebuild the old client's ledger if an order was moved.
    await reconcileClientPayments(clientId);
    if (previousClientId != null && previousClientId != clientId) {
      await reconcileClientPayments(previousClientId);
    }

    // The order is committed locally at this point. Upload and notify in the
    // background: waiting for the network and the push Edge Function (cold
    // start + FCM) made the final "save" button feel slow.
    unawaited(() async {
    var uploaded = false;
    try {
      await CloudSyncService().notifyChangeImmediate();
      uploaded = true;
    } catch (error) {
        debugPrint(
          'Order $savedId saved locally; cloud upload deferred: $error',
        );
    }
    if (uploaded) {
      _notifyOrderEventSafe(
        orderId: savedId,
        isNew: createdNewOrder,
        author: editor,
      );
      await _sendOrderPushEventSafe(
        orderId: savedId,
        action: createdNewOrder ? 'created' : 'updated',
        author: editor,
      );
    }
    }());
    return savedId;
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
    String? updatedBy,
  }) async {
    final myDb = await db;
    if (myDb == null) {
      throw StateError('قاعدة بيانات الطلبات غير متاحة');
    }
    await _backfillOrderCodes(myDb);
    final netPayable = total - remise + ((total * tva) / 100);
    final now = DateTime.now().toUtc().toIso8601String();
    final orderDate = createdAt ?? now;
    final editor = updatedBy?.trim().isNotEmpty == true
        ? updatedBy!.trim()
        : await _currentOrderEditor();
    final distributedId = SqlDatabase._nextDistributedId();
    final orderCode = await _reserveNextOrderCode(myDb);
    var res = await myDb.rawInsert(
      'INSERT INTO Commandes (id, order_code, client_id, status, description, remise, tva, total, net_payable, advance_payment, payment_status, created_at, updated_at, project_id, updated_by) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [
        distributedId,
        orderCode,
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
        editor,
      ],
    );
    if (advancePayment > SqlDatabase._paymentTolerance) {
      await insertTreasury(
        'Encaissement',
        advancePayment,
        'دفعة افتتاحية للطلبية #$orderCode',
        referenceId: distributedId,
        entityType: 'Client',
        entityId: idClient,
        createdAt: orderDate,
      );
    } else {
      // Consume credit retained from an earlier overpayment.
      await reconcileClientPayments(idClient);
    }
    unawaited(() async {
      try {
    await CloudSyncService().notifyChangeImmediate();
      } catch (error) {
        debugPrint('Order $distributedId upload deferred: $error');
        return;
      }
      _notifyOrderEventSafe(
        orderId: distributedId,
        isNew: true,
        author: editor,
      );
    await _sendOrderPushEventSafe(
      orderId: distributedId,
      action: 'created',
      author: editor,
    );
    }());
    unawaited(
      _recordDashboardActivity(
        activityType: 'order_added',
        entityId: distributedId,
        document: orderCode.toString(),
        userName: editor,
      ),
    );
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
    // Financial amounts are derived from Treasury allocations. Keeping these
    // fields out of regular order edits prevents a payment that is invisible
    // in the cash register and customer statement.
    if (netPayable != null) data['net_payable'] = netPayable;
    if (dateCommande != null) data['created_at'] = dateCommande;
    if (updateProjectId) data['project_id'] = projectId;
    if (data.isNotEmpty) {
      data['updated_at'] = DateTime.now().toUtc().toIso8601String();
      data['updated_by'] = await _currentOrderEditor();
      await snapshotCommande(
        idCommande,
        actionType: 'UPDATE',
        afterHeader: Map<String, dynamic>.from(data),
      );
      var res = await myDb!.update(
        'Commandes',
        data,
        where: 'id = ?',
        whereArgs: [idCommande],
      );
      if (netPayable != null || total != null || totalGlobal != null) {
        final order = await myDb.query(
          'Commandes',
          columns: ['client_id'],
          where: 'id = ?',
          whereArgs: [idCommande],
          limit: 1,
        );
        final clientId = SqlDatabase._paymentRecordId(
          order.isEmpty ? null : order.first['client_id'],
        );
        if (clientId != null) await reconcileClientPayments(clientId);
      }
      final updatedBy = data['updated_by']?.toString() ?? '';
      unawaited(() async {
        try {
      await CloudSyncService().notifyChangeImmediate();
        } catch (error) {
          debugPrint('Order $idCommande upload deferred: $error');
          return;
        }
      _notifyOrderEventSafe(
        orderId: idCommande,
        isNew: false,
          author: updatedBy,
      );
      await _sendOrderPushEventSafe(
        orderId: idCommande,
        action: 'updated',
          author: updatedBy,
      );
      }());
      unawaited(
        _recordDashboardActivity(
          activityType: 'order_updated',
          entityId: idCommande,
          document: (await _orderCodeForNotification(idCommande)).toString(),
          userName: data['updated_by']?.toString(),
        ),
      );
      return res;
    }
    return 0;
  }

  void _notifyOrderEventSafe({
    required int orderId,
    required bool isNew,
    required String author,
  }) {
    unawaited(() async {
      try {
        final workshopUuid = await OrderNotificationService.readWorkshopUuid();
        if (workshopUuid.isEmpty) return;

        final row = await readCommandeWithClientById(orderId);
        if (row == null) return;

        final clientName = '${row['firstname'] ?? ''} ${row['lastname'] ?? ''}'
            .trim();
        final orderCode =
            row['order_code']?.toString() ??
            row['display_number']?.toString() ??
            orderId.toString();

        await OrderNotificationService().broadcastOrderEvent(
          workshopUuid: workshopUuid,
          orderId: orderId,
          isNew: isNew,
          clientName: clientName.isNotEmpty ? clientName : 'عميل',
          orderCode: orderCode,
          authorName: author,
        );
      } catch (_) {
        // Ignored safely in test environments or offline
      }
    }());
  }

  Future<String> _orderCodeForNotification(int orderId) async {
    final row = await readCommandeWithClientById(orderId);
    return row?['order_code']?.toString() ??
        row?['display_number']?.toString() ??
        orderId.toString();
  }

  Future<String> _clientNameForOrderNotification(int orderId) async {
    final row = await readCommandeWithClientById(orderId);
    if (row == null) return 'عميل';
    final name = '${row['firstname'] ?? ''} ${row['lastname'] ?? ''}'.trim();
    return name.isEmpty ? 'عميل' : name;
  }

  Future<void> _sendOrderPushEventSafe({
    required int orderId,
    required String action,
    required String author,
  }) {
    return () async {
      try {
        await WorkerPushNotificationService.instance.sendOrderEvent(
          action: action,
          orderId: orderId,
          orderCode: await _orderCodeForNotification(orderId),
          clientName: await _clientNameForOrderNotification(orderId),
          author: author,
        );
      } catch (error) {
        debugPrint('Order push notification skipped: $error');
      }
    }();
  }

  Future<int> deleteCommande(int id, {bool permanent = false}) {
    if (permanent) {
      return deleteCommandePermanently(id);
    }
    return _retryAfterDatabaseMove(() => _softDeleteCommandeOnce(id));
  }

  Future<int> deleteCommandePermanently(int id) {
    return _retryAfterDatabaseMove(() => _deleteCommandeOnce(id));
  }

  Future<int> _softDeleteCommandeOnce(int id) async {
    Database? myDb = await db;
    if (myDb == null) return 0;
    await _ensureOrderTrashInfrastructure(myDb);
    await _ensureRemnantInventorySchema(myDb);
    await _ensureOrderStockReservationInfrastructure(myDb);
    final notificationRow = await readCommandeWithClientById(id);
    final order = await myDb.query(
      'Commandes',
      columns: ['client_id'],
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    final nowIso = DateTime.now().toUtc().toIso8601String();
    final deletedBy = await _currentOrderEditor();
    await snapshotCommande(id, actionType: 'DELETE');
    // A deleted order must not keep stock away from the others.
    final res = await myDb.transaction<int>((txn) async {
      await _releaseOrderStockHold(txn, id, nowIso);
      return txn.update(
        'Commandes',
        {
          'is_deleted': 1,
          'deleted_at': nowIso,
          'deleted_by': deletedBy,
          'updated_at': nowIso,
          'is_stock_reserved': 0,
          'stock_reserved_at': null,
        },
        where: 'id = ?',
        whereArgs: [id],
      );
    });
    if (res > 0) {
      final clientId = SqlDatabase._paymentRecordId(
        order.isEmpty ? null : order.first['client_id'],
      );
      if (clientId != null) await reconcileClientPayments(clientId);
      try {
        await CloudSyncService().notifyChangeImmediate();
      } catch (_) {}
      if (notificationRow != null) {
        final orderCodeStr =
            notificationRow['order_code']?.toString() ??
            notificationRow['display_number']?.toString() ??
            id.toString();
        final clientNameStr =
            '${notificationRow['firstname'] ?? ''} ${notificationRow['lastname'] ?? ''}'
                .trim();
        final totalAmount =
            notificationRow['net_payable'] ?? notificationRow['total'] ?? 0;
        unawaited(
          logAuditAction(
            actionType: 'DELETE',
            entityType: 'order',
            entityId: id.toString(),
            entityTitle: 'طلبية #$orderCodeStr للزبون $clientNameStr',
            details: 'المبلغ: $totalAmount دج - تم نقلها إلى سلة المحذوفات',
          ),
        );
        _notifyOrderDeletedSafe(notificationRow);
        unawaited(
          WorkerPushNotificationService.instance
              .sendOrderEvent(
            action: 'deleted',
            orderId: id,
            orderCode: orderCodeStr,
            clientName: clientNameStr,
            author: deletedBy,
              )
              .catchError((Object error) {
          debugPrint('Order deletion push notification skipped: $error');
              }),
        );
      } else {
        unawaited(
          logAuditAction(
            actionType: 'DELETE',
            entityType: 'order',
            entityId: id.toString(),
            entityTitle: 'طلبية #$id',
            details: 'تم نقلها إلى سلة المحذوفات',
          ),
        );
      }
    }
    return res;
  }

  void _notifyOrderDeletedSafe(Map<String, dynamic> row) {
    unawaited(() async {
      try {
        final workshopUuid = await OrderNotificationService.readWorkshopUuid();
        if (workshopUuid.isEmpty) return;
        final clientName = '${row['firstname'] ?? ''} ${row['lastname'] ?? ''}'
            .trim();
        final orderCode =
            row['order_code']?.toString() ??
            row['display_number']?.toString() ??
            row['id']?.toString() ??
            '';
        await OrderNotificationService().broadcastOrderDeleted(
          workshopUuid: workshopUuid,
          clientName: clientName.isEmpty ? 'عميل' : clientName,
          orderCode: orderCode,
          authorName: await _currentOrderEditor(),
        );
      } catch (_) {}
    }());
  }

  Future<int> restoreCommande(int id) {
    return _retryAfterDatabaseMove(() => _restoreCommandeOnce(id));
  }

  Future<int> _restoreCommandeOnce(int id) async {
    Database? myDb = await db;
    if (myDb == null) return 0;
    await _ensureOrderTrashInfrastructure(myDb);
    final order = await myDb.query(
      'Commandes',
      columns: ['client_id'],
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    final nowIso = DateTime.now().toUtc().toIso8601String();
    final res = await myDb.update(
      'Commandes',
      {
        'is_deleted': 0,
        'deleted_at': null,
        'deleted_by': null,
        'updated_at': nowIso,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    if (res > 0) {
      try {
        await myDb.delete(
          'SyncTombstones',
          where: 'table_name = ? AND (row_id = ? OR row_id = ?)',
          whereArgs: ['Commandes', id.toString(), id],
        );
      } catch (_) {}
      unawaited(_removeDeletedOrderTombstoneFromCloud(id));
      unawaited(
        logAuditAction(
          actionType: 'RESTORE',
          entityType: 'order',
          entityId: id.toString(),
          entityTitle: 'طلبية #$id',
          details: 'تم استرجاع الطلبية من سلة المحذوفات',
        ),
      );
      final clientId = SqlDatabase._paymentRecordId(
        order.isEmpty ? null : order.first['client_id'],
      );
      if (clientId != null) await reconcileClientPayments(clientId);
      try {
        CloudSyncService().notifyChangeImmediate();
      } catch (_) {}
    }
    return res;
  }

  Future<int> _deleteCommandeOnce(int id) async {
    Database? myDb = await db;
    if (myDb == null) return 0;

    // Track every affected record before it is deleted so Firebase receives
    // the deletion as well, and keep the operation atomic on every device.
    await _ensureSyncTombstoneInfrastructure(myDb);
    await _ensureRemnantInventorySchema(myDb);
    final res = await myDb.transaction((txn) async {
      await _releaseOrderStockHold(
        txn,
        id,
        DateTime.now().toUtc().toIso8601String(),
      );
      final details = await txn.query(
        'Commandes_details',
        columns: ['id'],
        where: 'id_commandes = ? OR CAST(id_commandes AS TEXT) = ?',
        whereArgs: [id, id.toString()],
      );

      // Some existing databases were created before foreign-key cascades were
      // enabled. Delete dependent rows explicitly so an order never leaves
      // old components, deliveries, or worker assignments behind.
      for (final detail in details) {
        final detailId = detail['id'];
        if (detailId == null) continue;
        await txn.delete(
          'WorkerAllocations',
          where:
              'commande_detail_id = ? OR CAST(commande_detail_id AS TEXT) = ?',
          whereArgs: [detailId, detailId.toString()],
        );
      }
      await txn.delete(
        'Commandes_deliveries',
        where: 'id_commandes = ? OR CAST(id_commandes AS TEXT) = ?',
        whereArgs: [id, id.toString()],
      );
      await txn.delete(
        'Commandes_details',
        where: 'id_commandes = ? OR CAST(id_commandes AS TEXT) = ?',
        whereArgs: [id, id.toString()],
      );
      await txn.delete(
        'Treasury',
        where: "reference_id = ? AND entity_type = 'Client'",
        whereArgs: [id],
      );
      return txn.delete('Commandes', where: 'id = ?', whereArgs: [id]);
    });
    if (res > 0) {
      await _writeDeletedOrderTombstoneToCloud(id);
      try {
        await CloudSyncService().notifyChangeImmediate();
      } catch (_) {}
    }
    return res;
  }

  Future<int> deleteCommandeLocalOnly(int id) {
    return _retryAfterDatabaseMove(() => _deleteCommandeLocalOnlyOnce(id));
  }

  Future<int> _deleteCommandeLocalOnlyOnce(int id) async {
    final myDb = await db;
    if (myDb == null) return 0;
    await _ensureSyncTombstoneInfrastructure(myDb);

    return myDb.transaction((txn) async {
      await txn.update('_sync_runtime_flags', {
        'suppress_tombstones': 1,
      }, where: 'id = 1');
      try {
        final details = await txn.query(
          'Commandes_details',
          columns: ['id'],
          where: 'id_commandes = ? OR CAST(id_commandes AS TEXT) = ?',
          whereArgs: [id, id.toString()],
        );
        for (final detail in details) {
          final detailId = detail['id'];
          if (detailId == null) continue;
          await txn.delete(
            'WorkerAllocations',
            where:
                'commande_detail_id = ? OR CAST(commande_detail_id AS TEXT) = ?',
            whereArgs: [detailId, detailId.toString()],
          );
        }
        await txn.delete(
          'Commandes_deliveries',
          where: 'id_commandes = ? OR CAST(id_commandes AS TEXT) = ?',
          whereArgs: [id, id.toString()],
        );
        await txn.delete(
          'Commandes_details',
          where: 'id_commandes = ? OR CAST(id_commandes AS TEXT) = ?',
          whereArgs: [id, id.toString()],
        );
        await txn.delete(
          'Treasury',
          where: "reference_id = ? AND entity_type = 'Client'",
          whereArgs: [id],
        );
        return await txn.delete('Commandes', where: 'id = ?', whereArgs: [id]);
      } finally {
        await txn.update('_sync_runtime_flags', {
          'suppress_tombstones': 0,
        }, where: 'id = 1');
      }
    });
  }

  Future<int> deleteCommandeDetails(int commandeId) async {
    Database? myDb = await db;
    await snapshotCommande(commandeId, actionType: 'UPDATE');
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
      'id': SqlDatabase._nextDistributedId(),
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
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
    CloudSyncService().notifyChange();
    return res;
  }

  Future<int> updateCommandeDetailImagePath(int idDetail, String path) async {
    Database? myDb = await db;
    final detailRows = await myDb!.query(
      'Commandes_details',
      columns: ['id_commandes'],
      where: 'id = ?',
      whereArgs: [idDetail],
      limit: 1,
    );
    final commandeId = detailRows.isEmpty
        ? null
        : (detailRows.first['id_commandes'] as num?)?.toInt();
    if (commandeId != null) {
      await snapshotCommande(
        commandeId,
        actionType: 'UPDATE',
        afterHeader: {'detail_id': idDetail, 'drawing_image_path': path},
      );
    }
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
        'updated_at': DateTime.now().toUtc().toIso8601String(),
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
    final detailRows = await myDb!.query(
      'Commandes_details',
      columns: ['id_commandes'],
      where: 'id = ?',
      whereArgs: [idDetail],
      limit: 1,
    );
    final commandeId = detailRows.isEmpty
        ? null
        : (detailRows.first['id_commandes'] as num?)?.toInt();
    if (commandeId != null) {
      await snapshotCommande(
        commandeId,
        actionType: 'UPDATE',
        afterHeader: {'detail_id': idDetail, 'delivered_qty': newDeliveredQty},
      );
    }
    var res = await myDb!.update(
      'Commandes_details',
      {
        'delivered_qty': newDeliveredQty,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [idDetail],
    );
    CloudSyncService().notifyChange();
    return res;
  }

  Future<int> resetCommandeDeliveredQty(int idCommande) async {
    Database? myDb = await db;
    await snapshotCommande(
      idCommande,
      actionType: 'UPDATE',
      afterHeader: {'reset_delivered_qty': true},
    );
    var res = await myDb!.update(
      'Commandes_details',
      {
        'delivered_qty': 0,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      where: 'id_commandes = ?',
      whereArgs: [idCommande],
    );
    CloudSyncService().notifyChange();
    return res;
  }

  Future<int> insertCommandeDelivery(
    int idCommande,
    int clientId,
    String date,
    String itemsJson,
    double totalAmount, {
    int isLoaded = 0,
    String? assignedWorkerUid,
    String? assignedWorkerName,
  }) async {
    Database? myDb = await db;
    await _ensureDeliveriesLoadedColumn(myDb!);
    int effectiveClientId = clientId;
    if (effectiveClientId <= 0 && idCommande > 0) {
      try {
        final orderRow = await myDb.query(
          'Commandes',
          columns: ['client_id'],
          where: 'id = ?',
          whereArgs: [idCommande],
          limit: 1,
        );
        if (orderRow.isNotEmpty) {
          effectiveClientId =
              (orderRow.first['client_id'] as num?)?.toInt() ?? 0;
        }
      } catch (_) {}
    }
    var res = await myDb.insert(
      'Commandes_deliveries',
      SqlDatabase._withDistributedId({
        'id_commandes': idCommande,
        'client_id': effectiveClientId,
        'delivery_date': date,
        'items_json': itemsJson,
        'total_amount': totalAmount,
        'is_loaded': isLoaded,
        'delivery_status': 'planned',
        'assigned_worker_uid': assignedWorkerUid,
        'assigned_worker_name': assignedWorkerName,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }),
    );
    CloudSyncService().notifyChange();
    unawaited(
      _recordDashboardActivity(
        activityType: 'delivery_added',
        entityId: res,
        relatedOrderId: idCommande,
        document: res.toString(),
      ),
    );
    final workerUid = assignedWorkerUid?.trim() ?? '';
    if (workerUid.isNotEmpty) {
      final quantity =
          (jsonDecode(itemsJson) as List?)?.fold<int>(
            0,
            (sum, item) =>
                sum +
                (int.tryParse(
                      item is Map ? item['quantity']?.toString() ?? '' : '',
                    ) ??
                    0),
          ) ??
          0;
      unawaited(
        WorkerPushNotificationService.instance
            .sendAssignmentToCurrentWorkshop(
              workerUid: workerUid,
              orderId: idCommande,
              orderNumber: idCommande,
              quantity: quantity,
            )
            .catchError((_) {}),
      );
    }
    unawaited(
      WorkerPushNotificationService.instance
          .sendManagerEvent(
            eventType: 'deliveries',
            title: 'خطة توزيع جديدة',
            body: 'تم إنشاء خطة توزيع للطلبية #$idCommande',
            data: {'order_id': idCommande.toString()},
          )
          .catchError((_) {}),
    );
    return res;
  }

  Future<int> updateCommandeDeliveryStatus(
    int deliveryId,
    String status, {
    String? note,
  }) async {
    final myDb = await db;
    if (myDb == null) return 0;
    await _ensureDeliveriesLoadedColumn(myDb);
    final now = DateTime.now().toUtc().toIso8601String();
    final values = <String, dynamic>{
      'delivery_status': status,
      'updated_at': now,
      if (status == 'en_route') 'started_at': now,
      if (note != null) 'delivery_note': note.trim(),
    };
    final result = await myDb.update(
      'Commandes_deliveries',
      values,
      where: 'id = ?',
      whereArgs: [deliveryId],
    );
    CloudSyncService().notifyChangeImmediate();
    return result;
  }

  Future<bool> completeCommandeDelivery(int deliveryId) async {
    final myDb = await db;
    if (myDb == null) return false;
    await _ensureDeliveriesLoadedColumn(myDb);
    var completed = false;
    await myDb.transaction((txn) async {
      final rows = await txn.query(
        'Commandes_deliveries',
        where: 'id = ?',
        whereArgs: [deliveryId],
        limit: 1,
      );
      if (rows.isEmpty || rows.first['delivery_status'] == 'delivered') return;
      final delivery = rows.first;
      final orderId = (delivery['id_commandes'] as num?)?.toInt() ?? 0;
      final decoded = jsonDecode(delivery['items_json']?.toString() ?? '[]');
      if (decoded is List) {
        for (final raw in decoded) {
          if (raw is! Map) continue;
          final itemId = int.tryParse(raw['id']?.toString() ?? '') ?? 0;
          final quantity = int.tryParse(raw['quantity']?.toString() ?? '') ?? 0;
          if (itemId <= 0 || quantity <= 0) continue;
          await txn.rawUpdate(
            '''
            UPDATE Commandes_details
            SET delivered_qty = MIN(
              COALESCE(quantity, 0),
              COALESCE(delivered_qty, 0) + ?
            )
            WHERE id = ? AND id_commandes = ?
          ''',
            [quantity, itemId, orderId],
          );
        }
      }
      final pending = await txn.rawQuery(
        '''
        SELECT COUNT(*) AS count
        FROM Commandes_details
        WHERE id_commandes = ?
          AND COALESCE(delivered_qty, 0) < COALESCE(quantity, 0)
      ''',
        [orderId],
      );
      final hasPending = ((pending.first['count'] as num?)?.toInt() ?? 0) > 0;
      final now = DateTime.now().toUtc().toIso8601String();
      await txn.update(
        'Commandes_deliveries',
        {
          'delivery_status': 'delivered',
          'delivered_at': now,
          'updated_at': now,
        },
        where: 'id = ?',
        whereArgs: [deliveryId],
      );
      await txn.update(
        'Commandes',
        {'status': hasPending ? 'Partial Distribution' : 'Full Distribution'},
        where: 'id = ?',
        whereArgs: [orderId],
      );
      completed = true;
    });
    if (completed) {
      CloudSyncService().notifyChangeImmediate();
      unawaited(
        WorkerPushNotificationService.instance
            .sendManagerEvent(
              eventType: 'deliveries',
              title: 'تم تسليم الطلبية',
              body: 'تم تأكيد خطة التوزيع بنجاح',
              data: {'delivery_id': deliveryId.toString()},
            )
            .catchError((_) {}),
      );
    }
    return completed;
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

  Future<List<Map<String, dynamic>>> readRecentCommandeDeliveries({
    int limit = 24,
  }) async {
    final database = await db;
    if (database == null) return [];
    return database.query(
      'Commandes_deliveries',
      orderBy: 'id DESC',
      limit: limit,
    );
  }

  Future<int> updateCommandeDeliveryIsLoaded(
    int deliveryId,
    int isLoaded,
  ) async {
    Database? myDb = await db;
    await _ensureDeliveriesLoadedColumn(myDb!);
    var res = await myDb.update(
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
    if (myDb == null || amount <= SqlDatabase._paymentTolerance) return 0;
    final orderData = await myDb.query(
      'Commandes',
      where: 'id = ?',
      whereArgs: [idCommande],
    );
    if (orderData.isEmpty) return 0;
    final clientId = SqlDatabase._paymentRecordId(orderData.first['client_id']);
    if (clientId == null) return 0;

    // Old callers can still add a deposit, but never by writing directly to
    // Commandes. The single Treasury record is allocated to this order.
    final orderCode = _positiveInt(orderData.first['order_code']);
    final displayNum = (orderCode != null && orderCode > 0)
        ? orderCode
        : idCommande;
    return insertTreasury(
      'Encaissement',
      amount,
      'دفعة للطلبية #$displayNum',
      referenceId: idCommande,
      entityType: 'Client',
      entityId: clientId,
    );
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
        'cmdTrend': 'â€”',
        'cliCount': '0',
        'cliTrend': 'â€”',
      };
    }

    try {
      DateTime now = DateTime.now();
      DateTime seventyTwoHoursAgo = now.subtract(const Duration(hours: 72));

      // Commandes
      final cmds = await database.query(
        'Commandes',
        where: '(is_deleted IS NULL OR is_deleted = 0)',
      );
      int cmdRecent = 0;
      for (var row in cmds) {
        if (row['created_at'] != null) {
          try {
            DateTime dt = DateTime.parse(row['created_at'].toString());
            if (dt.isAfter(seventyTwoHoursAgo) ||
                dt.isAtSameMomentAs(seventyTwoHoursAgo)) {
              cmdRecent++;
            }
          } catch (_) {}
        }
      }

      String cmdTrend = 'â€”';
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
            if (dt.isAfter(seventyTwoHoursAgo) ||
                dt.isAtSameMomentAs(seventyTwoHoursAgo)) {
              cliRecent++;
            }
          } catch (_) {}
        }
      }

      String cliTrend = 'â€”';
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
        'cmdTrend': 'â€”',
        'cliCount': '0',
        'cliTrend': 'â€”',
      };
    }
  }

  /// Returns order counts grouped by status, plus last-6-months monthly totals.
  Future<Map<String, dynamic>> getOrderStatusStats() async {
    final database = await db;
    if (database == null) {
      return {'byStatus': <String, int>{}, 'monthly': <String, int>{}};
    }
    try {
      final rows = await database.query(
        'Commandes',
        where: '(is_deleted IS NULL OR is_deleted = 0)',
      );

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

      return {
        'byStatus': canonicalizeOrderStatusCounts(byStatus),
        'monthly': monthly,
      };
    } catch (e) {
      debugPrint('getOrderStatusStats error: $e');
      return {'byStatus': <String, int>{}, 'monthly': <String, int>{}};
    }
  }

  Future<void> _recordDashboardActivity({
    required String activityType,
    required int entityId,
    String document = '',
    String party = '',
    int? relatedOrderId,
    String? userName,
  }) async {
    final database = await db;
    if (database == null || entityId <= 0) return;
    await _ensureDashboardActivitiesInfrastructure(database);
    final now = DateTime.now().toUtc().toIso8601String();
    await database.transaction((txn) async {
      await txn.insert('DashboardActivities', {
        'id': DateTime.now().microsecondsSinceEpoch,
        'activity_type': activityType,
        'entity_id': entityId,
        'related_order_id': relatedOrderId,
        'document': document,
        'party': party,
        'user_name': userName ?? await _currentOrderEditor(),
        'occurred_at': now,
      });
      await txn.rawDelete('''
        DELETE FROM DashboardActivities
        WHERE id NOT IN (
          SELECT id FROM DashboardActivities
          ORDER BY occurred_at DESC, id DESC
          LIMIT 12
        )
      ''');
    });
  }

  Future<List<Map<String, dynamic>>> readDashboardActivities() async {
    final database = await db;
    if (database == null) return [];
    await _ensureDashboardActivitiesInfrastructure(database);
    return database.query(
      'DashboardActivities',
      orderBy: 'occurred_at DESC, id DESC',
      limit: 12,
    );
  }

  Future<void> snapshotCommande(
    int commandeId, {
    required String actionType,
    Map<String, dynamic>? afterHeader,
    List<Map<String, dynamic>>? afterItems,
  }) async {
    final database = await db;
    if (database == null) return;
    final headers = await database.query(
      'Commandes',
      where: 'id = ?',
      whereArgs: [commandeId],
      limit: 1,
    );
    if (headers.isEmpty) return;
    final items = await database.query(
      'Commandes_details',
      where: 'id_commandes = ? OR CAST(id_commandes AS TEXT) = ?',
      whereArgs: [commandeId, commandeId.toString()],
      orderBy: 'id ASC',
    );
    final header = Map<String, dynamic>.from(headers.first);
    await logAuditAction(
      actionType: actionType,
      entityType: 'order',
      entityId: commandeId.toString(),
      entityTitle:
          'طلبية #${header['order_code'] ?? header['display_number'] ?? commandeId}',
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

  Future<void> logAuditAction({
    required String actionType,
    required String entityType,
    required String entityId,
    String? entityTitle,
    String? details,
  }) async {
    try {
      final database = await db;
      if (database == null) return;
      await _ensureAuditLogsInfrastructure(database);
      final author = await _currentOrderEditor();
      final nowUtc = DateTime.now().toUtc().toIso8601String();
      final uniqueId = SqlDatabase._nextDistributedId();
      await database.insert('AuditLogs', {
        'id': uniqueId,
        'action_type': actionType,
        'entity_type': entityType,
        'entity_id': entityId,
        'entity_title': entityTitle ?? '',
        'user_name': author,
        'details': details ?? '',
        'timestamp': nowUtc,
        'updated_at': nowUtc,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      // Audit rows are workshop data too. Trigger their own sync instead of
      // relying on a business mutation that may already have been uploaded.
      CloudSyncService().notifyChange();
    } catch (e) {
      debugPrint('Error writing audit log: $e');
    }
  }

  Future<List<Map<String, dynamic>>> readAuditLogs({int limit = 100}) async {
    final database = await db;
    if (database == null) return [];
    try {
      await _ensureAuditLogsInfrastructure(database);
      return await database.query(
        'AuditLogs',
        orderBy: 'timestamp DESC, id DESC',
        limit: limit,
      );
    } catch (e) {
      return [];
    }
  }
}
