import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:database_data/sql_database.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseWorkshopSyncService {
  SupabaseWorkshopSyncService._internal();

  static final SupabaseWorkshopSyncService _instance =
      SupabaseWorkshopSyncService._internal();

  factory SupabaseWorkshopSyncService() => _instance;

  static const Duration _pollInterval = Duration(seconds: 2);
  static const Duration _uploadDebounce = Duration(milliseconds: 250);
  static const int _batchSize = 200;
  static const int _downloadPageSize = 500;

  final SqlDatabase _db = SqlDatabase();
  final Random _random = Random.secure();
  final StreamController<Map<String, dynamic>> _permissionsController =
      StreamController<Map<String, dynamic>>.broadcast();

  Timer? _pollTimer;
  Timer? _uploadTimer;
  RealtimeChannel? _permissionsChannel;
  Future<void>? _activeUpload;
  Future<void>? _activeDownload;
  bool _uploadQueued = false;
  bool _isApplyingRemoteData = false;
  String? _workshopUuid;
  String? _workshopCode;
  String? _permissionsChannelName;
  String _deviceId = '';
  void Function()? _onDataChanged;

  String lastUploadSummary = '';
  String lastDownloadSummary = '';

  SupabaseClient get _client => Supabase.instance.client;

  Stream<Map<String, dynamic>> get permissionsStream =>
      _permissionsController.stream;

  bool get isSignedIn => _client.auth.currentUser != null;

  bool get isReady => isSignedIn && _workshopUuid != null;

  void start({void Function()? onDataChanged}) {
    _onDataChanged = onDataChanged ?? _onDataChanged;
    unawaited(_startAsync());
  }

  void stop() {
    _pollTimer?.cancel();
    _uploadTimer?.cancel();
    final permissionsChannel = _permissionsChannel;
    if (permissionsChannel != null) {
      unawaited(_client.removeChannel(permissionsChannel));
    }
    _pollTimer = null;
    _uploadTimer = null;
    _permissionsChannel = null;
    _permissionsChannelName = null;
  }

  void notifyLocalChange({bool immediate = false}) {
    if (_isApplyingRemoteData) return;
    if (immediate) {
      _uploadTimer?.cancel();
      unawaited(uploadPendingChanges());
      return;
    }

    _uploadTimer?.cancel();
    _uploadTimer = Timer(_uploadDebounce, () {
      unawaited(uploadPendingChanges());
    });
  }

  Future<void> uploadFullWorkshopData() async {
    await _ensureReady();
    final workshopUuid = _workshopUuid!;
    final user = _client.auth.currentUser!;
    final pendingBeforeUpload = await _db.exportPendingCloudChanges();
    final data = await _db.exportWorkshopData();
    final rows = _flattenDataForUpload(
      data,
      workshopUuid: workshopUuid,
      userId: user.id,
      fullUpload: true,
    );

    if (rows.isEmpty) {
      throw Exception('لا توجد بيانات ورشة محلية لرفعها.');
    }

    await _client
        .from('workshop_sync_rows')
        .delete()
        .eq('workshop_id', workshopUuid);
    await _upsertRows(rows);

    await _acknowledgeSyncedChanges(pendingBeforeUpload);
    await _saveLastSyncAt(DateTime.now().toUtc().toIso8601String());

    lastUploadSummary =
        'تم رفع ${rows.length} سجل: '
        '${_countRows(data, 'Client')} زبون، '
        '${_countRows(data, 'Commandes')} طلبية، '
        '${_countRows(data, 'Commandes_details')} تفاصيل.';
  }

  Future<void> uploadPendingChanges() {
    final activeUpload = _activeUpload;
    if (activeUpload != null) {
      _uploadQueued = true;
      return activeUpload;
    }

    final task = _runSerializedUpload();
    _activeUpload = task;
    return task;
  }

  Future<void> downloadWorkshopData({bool full = false}) {
    final activeDownload = _activeDownload;
    if (activeDownload != null) return activeDownload;

    final task = _downloadChanges(full: full);
    _activeDownload = task;
    return task.whenComplete(() {
      if (identical(_activeDownload, task)) {
        _activeDownload = null;
      }
    });
  }

  Future<void> _startAsync() async {
    try {
      await _ensureReady();
      _subscribeToPermissionChanges();
      await refreshCurrentPermissions();
      await uploadPendingChanges();
      await downloadWorkshopData();
      _pollTimer?.cancel();
      _pollTimer = Timer.periodic(_pollInterval, (_) {
        unawaited(downloadWorkshopData());
        unawaited(refreshCurrentPermissions());
      });
    } catch (error) {
      // Supabase sync is optional until the account/workshop is configured.
      // Keep the app usable and let the manual Settings buttons show the error.
      print('Supabase workshop sync not started: $error');
    }
  }

  Future<void> refreshCurrentPermissions() async {
    await _ensureReady();
    final workshopUuid = _workshopUuid!;
    final user = _client.auth.currentUser!;

    final row = await _client
        .from('workshop_members')
        .select('role,permissions,blocked,updated_at')
        .eq('workshop_id', workshopUuid)
        .eq('user_id', user.id)
        .maybeSingle();

    if (row == null) return;

    final rawPermissions = row['permissions'];
    final permissions = rawPermissions is Map
        ? Map<String, dynamic>.from(rawPermissions)
        : <String, dynamic>{};
    if (_permissionTruthy(row['blocked'])) {
      permissions['isBlocked'] = true;
    }

    final appRole = _mapSupabaseRoleToAppRole(
      row['role']?.toString() ?? 'worker',
      permissions,
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_role', appRole);
    await prefs.setString('permissions_json', jsonEncode(permissions));
    await prefs.setString(
      'permissions_cloud_fingerprint',
      jsonEncode(permissions),
    );

    _permissionsController.add({
      'role': appRole,
      'permissions': permissions,
      'updated_at': row['updated_at']?.toString() ?? '',
    });
  }

  void _subscribeToPermissionChanges() {
    final user = _client.auth.currentUser;
    final workshopUuid = _workshopUuid;
    if (user == null || workshopUuid == null) return;

    final channelName = 'workshop_permissions_${workshopUuid}_${user.id}';
    if (_permissionsChannelName == channelName && _permissionsChannel != null) {
      return;
    }

    final oldChannel = _permissionsChannel;
    if (oldChannel != null) {
      unawaited(_client.removeChannel(oldChannel));
    }

    _permissionsChannelName = channelName;
    _permissionsChannel = _client
        .channel(channelName)
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'workshop_members',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: user.id,
          ),
          callback: (_) {
            unawaited(refreshCurrentPermissions());
          },
        )
        .subscribe();
  }

  Future<void> updateMemberPermissionsByEmail({
    required String email,
    required String role,
    required Map<String, dynamic> permissions,
  }) async {
    final cleanEmail = email.trim().toLowerCase();
    if (cleanEmail.isEmpty) return;

    await _ensureReady();
    final code = _workshopCode;
    if (code == null || code.isEmpty) {
      throw Exception('تعذر تحديد كود الورشة في Supabase.');
    }

    await _client.rpc(
      'update_workshop_member_permissions',
      params: {
        'target_code': code,
        'member_email': cleanEmail,
        'member_role': _normalizeSupabaseRole(role),
        'member_permissions': permissions,
        'member_blocked': _permissionTruthy(permissions['isBlocked']),
      },
    );
  }

  Future<List<Map<String, dynamic>>> fetchWorkshopMembers() async {
    await _ensureReady();
    final code = _workshopCode;
    if (code == null || code.isEmpty) return <Map<String, dynamic>>[];

    final result = await _client.rpc(
      'list_workshop_members',
      params: {'target_code': code},
    );
    if (result is! List) return <Map<String, dynamic>>[];
    return result
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList(growable: false);
  }

  Future<void> _runSerializedUpload() async {
    try {
      do {
        _uploadQueued = false;
        await _performPendingUpload();
      } while (_uploadQueued);
    } finally {
      _activeUpload = null;
    }
  }

  Future<void> _performPendingUpload() async {
    await _ensureReady();
    final pending = await _db.exportPendingCloudChanges();
    if (pending.isEmpty) return;

    final workshopUuid = _workshopUuid!;
    final user = _client.auth.currentUser!;
    final data = _filterWorkshopTables(pending.data);
    final rows = _flattenDataForUpload(
      data,
      workshopUuid: workshopUuid,
      userId: user.id,
      fullUpload: false,
    );

    if (rows.isEmpty) return;

    await _upsertRows(rows);
    await _acknowledgeSyncedChanges(pending);

    lastUploadSummary =
        'تم رفع ${rows.length} تغيير سريع إلى Supabase '
        '(${pending.changedRows} تعديل، ${pending.deletedRows} حذف).';
  }

  Future<void> _downloadChanges({required bool full}) async {
    await _ensureReady();
    final workshopUuid = _workshopUuid!;
    final since = full ? null : await _readLastSyncAt();
    final data = <String, dynamic>{};
    final tombstones = <Map<String, dynamic>>[];
    var start = 0;
    var downloadedRows = 0;
    String? newestUpdate;

    while (true) {
      final rows = since != null && since.isNotEmpty
          ? await _client
                .from('workshop_sync_rows')
                .select(
                  'table_name,row_id,payload,updated_at,deleted_at,device_id',
                )
                .eq('workshop_id', workshopUuid)
                .gt('updated_at', since)
                .order('updated_at', ascending: true)
                .range(start, start + _downloadPageSize - 1)
          : await _client
                .from('workshop_sync_rows')
                .select(
                  'table_name,row_id,payload,updated_at,deleted_at,device_id',
                )
                .eq('workshop_id', workshopUuid)
                .order('updated_at', ascending: true)
                .range(start, start + _downloadPageSize - 1);
      if (rows.isEmpty) break;

      for (final rawRow in rows) {
        final row = Map<String, dynamic>.from(rawRow);
        final table = row['table_name']?.toString() ?? '';
        final rowId = row['row_id']?.toString() ?? '';
        if (!_isWorkshopTable(table) || rowId.isEmpty) continue;

        final updatedAt = row['updated_at']?.toString();
        if (updatedAt != null &&
            (newestUpdate == null || updatedAt.compareTo(newestUpdate) > 0)) {
          newestUpdate = updatedAt;
        }

        final deletedAt = row['deleted_at']?.toString();
        if (deletedAt != null && deletedAt.isNotEmpty) {
          tombstones.add({
            'table_name': table,
            'row_id': rowId,
            'deleted_at': deletedAt,
          });
          downloadedRows++;
          continue;
        }

        final payload = row['payload'];
        if (payload is Map) {
          final list =
              data.putIfAbsent(table, () => <Map<String, dynamic>>[])
                  as List<Map<String, dynamic>>;
          list.add(Map<String, dynamic>.from(payload));
          downloadedRows++;
        }
      }

      if (rows.length < _downloadPageSize) break;
      start += _downloadPageSize;
    }

    if (tombstones.isNotEmpty) {
      data['SyncTombstones'] = tombstones;
    }

    if (data.isNotEmpty) {
      _isApplyingRemoteData = true;
      try {
        await _db.importWorkshopData(data);
      } finally {
        _isApplyingRemoteData = false;
      }
      _onDataChanged?.call();
    }

    if (newestUpdate != null) {
      await _saveLastSyncAt(newestUpdate);
    }

    lastDownloadSummary = downloadedRows == 0
        ? 'لا توجد تغييرات جديدة في Supabase.'
        : 'تم تنزيل $downloadedRows تغيير من Supabase.';
  }

  Future<void> _ensureReady() async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw Exception('يجب تسجيل الدخول إلى Supabase أولاً.');
    }

    final prefs = await SharedPreferences.getInstance();
    var deviceId = prefs.getString('device_id');
    if (deviceId == null || deviceId.isEmpty) {
      deviceId =
          'device_${DateTime.now().millisecondsSinceEpoch}_${_random.nextInt(100000)}';
      await prefs.setString('device_id', deviceId);
    }
    _deviceId = deviceId;

    final code = (prefs.getString('workshop_code') ?? user.id).trim();
    if (_workshopUuid != null && _workshopCode == code) return;

    final cachedUuid = prefs.getString('supabase_workshop_uuid_$code');
    if (cachedUuid != null && cachedUuid.isNotEmpty) {
      _workshopUuid = cachedUuid;
      _workshopCode = code;
      await _cacheWorkshopIdentity(cachedUuid, prefs);
      return;
    }

    final workshopName = (prefs.getString('workshop_name') ?? code).trim();
    final workshopUuid = await _resolveWorkshopUuid(code, workshopName);
    _workshopUuid = workshopUuid;
    _workshopCode = code;
    await prefs.setString('supabase_workshop_uuid_$code', workshopUuid);
    await _cacheWorkshopIdentity(workshopUuid, prefs);
  }

  Future<String> _resolveWorkshopUuid(String code, String workshopName) async {
    try {
      final result = await _client.rpc(
        'ensure_my_workshop',
        params: {
          'target_code': code,
          'target_name': workshopName.trim().isEmpty ? code : workshopName,
        },
      );
      final id = result?.toString() ?? '';
      if (id.isNotEmpty) return id;
    } catch (error) {
      print('Supabase ensure_my_workshop RPC failed, trying tables: $error');
    }

    final existing = await _client
        .from('workshops')
        .select('id')
        .eq('code', code)
        .maybeSingle();
    final existingId = existing?['id']?.toString() ?? '';
    if (existingId.isNotEmpty) return existingId;

    final user = _client.auth.currentUser!;
    final inserted = await _client
        .from('workshops')
        .insert({'code': code, 'name': code, 'owner_uid': user.id})
        .select('id')
        .single();
    final id = inserted['id']?.toString() ?? '';
    if (id.isEmpty) {
      throw Exception('تعذر إنشاء ورشة Supabase.');
    }
    try {
      await _client.from('workshop_members').upsert({
        'workshop_id': id,
        'user_id': user.id,
        'role': 'owner',
      }, onConflict: 'workshop_id,user_id');
    } catch (_) {}
    return id;
  }

  Future<void> _cacheWorkshopIdentity(
    String workshopUuid,
    SharedPreferences prefs,
  ) async {
    try {
      final row = await _client
          .from('workshops')
          .select('code,name')
          .eq('id', workshopUuid)
          .maybeSingle();
      if (row == null) return;

      final code = row['code']?.toString().trim() ?? '';
      final name = row['name']?.toString().trim() ?? '';
      if (code.isNotEmpty) {
        await prefs.setString('workshop_code', code);
        _workshopCode = code;
      }
      if (name.isNotEmpty) {
        await prefs.setString('workshop_name', name);
        await prefs.setString('user_display_name', name);
      }
    } catch (error) {
      print('Supabase workshop identity cache skipped: $error');
    }
  }

  Future<void> _upsertRows(List<Map<String, dynamic>> rows) async {
    for (var start = 0; start < rows.length; start += _batchSize) {
      final end = min(start + _batchSize, rows.length);
      await _client
          .from('workshop_sync_rows')
          .upsert(
            rows.sublist(start, end),
            onConflict: 'workshop_id,table_name,row_id',
          );
    }
  }

  List<Map<String, dynamic>> _flattenDataForUpload(
    Map<String, dynamic> data, {
    required String workshopUuid,
    required String userId,
    required bool fullUpload,
  }) {
    final now = DateTime.now().toUtc().toIso8601String();
    final rows = <Map<String, dynamic>>[];

    for (final entry in data.entries) {
      final table = entry.key;
      final rawRows = entry.value;
      if (table == 'SyncTombstones') {
        if (rawRows is! List || fullUpload) continue;
        for (final rawRow in rawRows) {
          if (rawRow is! Map) continue;
          final tombstone = Map<String, dynamic>.from(rawRow);
          final deletedTable = tombstone['table_name']?.toString() ?? '';
          final rowId = tombstone['row_id']?.toString() ?? '';
          if (!_isWorkshopTable(deletedTable) || rowId.isEmpty) continue;
          rows.add({
            'workshop_id': workshopUuid,
            'table_name': deletedTable,
            'row_id': rowId,
            'payload': {'id': rowId},
            'updated_at': tombstone['deleted_at']?.toString() ?? now,
            'deleted_at': tombstone['deleted_at']?.toString() ?? now,
            'device_id': _deviceId,
            'revision': DateTime.now().microsecondsSinceEpoch,
          });
        }
        continue;
      }

      if (!_isWorkshopTable(table) || rawRows is! List) continue;
      for (final rawRow in rawRows) {
        if (rawRow is! Map) continue;
        final row = Map<String, dynamic>.from(rawRow);
        final rowId = row['id']?.toString() ?? '';
        if (rowId.isEmpty) continue;
        rows.add({
          'workshop_id': workshopUuid,
          'table_name': table,
          'row_id': rowId,
          'payload': row,
          'updated_at': now,
          'deleted_at': null,
          'device_id': _deviceId,
          'revision': DateTime.now().microsecondsSinceEpoch,
        });
      }
    }

    return rows;
  }

  Map<String, dynamic> _filterWorkshopTables(Map<String, dynamic> data) {
    final filtered = <String, dynamic>{};
    for (final entry in data.entries) {
      if (entry.key == 'SyncTombstones') {
        final tombstones = <Map<String, dynamic>>[];
        final rows = entry.value;
        if (rows is List) {
          for (final rawRow in rows) {
            if (rawRow is! Map) continue;
            final row = Map<String, dynamic>.from(rawRow);
            if (_isWorkshopTable(row['table_name']?.toString() ?? '')) {
              tombstones.add(row);
            }
          }
        }
        if (tombstones.isNotEmpty) filtered[entry.key] = tombstones;
      } else if (_isWorkshopTable(entry.key)) {
        filtered[entry.key] = entry.value;
      }
    }
    return filtered;
  }

  Future<void> _acknowledgeSyncedChanges(PendingCloudChanges pending) async {
    final acknowledgements = pending.acknowledgements
        .where((ack) => _isWorkshopTable(ack.table))
        .toList(growable: false);
    if (acknowledgements.isNotEmpty) {
      await _db.acknowledgePendingCloudChanges(acknowledgements);
    }
  }

  Future<String?> _readLastSyncAt() async {
    final code = _workshopCode;
    if (code == null || code.isEmpty) return null;
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('supabase_workshop_last_sync_$code');
  }

  Future<void> _saveLastSyncAt(String value) async {
    final code = _workshopCode;
    if (code == null || code.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('supabase_workshop_last_sync_$code', value);
  }

  bool _isWorkshopTable(String table) {
    return SqlDatabase.workshopTables.contains(table);
  }

  int _countRows(Map<String, dynamic> data, String table) {
    final rows = data[table];
    return rows is List ? rows.length : 0;
  }

  String _mapSupabaseRoleToAppRole(
    String role,
    Map<String, dynamic> permissions,
  ) {
    final normalized = _normalizeSupabaseRole(role);
    if (normalized == 'owner' ||
        normalized == 'manager' ||
        normalized == 'admin') {
      return 'manager';
    }
    if (normalized == 'co_manager' ||
        _permissionTruthy(permissions['full_manager_permissions']) ||
        _permissionTruthy(permissions['co_manager'])) {
      return 'co_manager';
    }
    return 'worker';
  }

  String _normalizeSupabaseRole(String role) {
    final normalized = role.trim().toLowerCase();
    if (normalized == 'owner' ||
        normalized == 'manager' ||
        normalized == 'co_manager' ||
        normalized == 'admin' ||
        normalized == 'worker') {
      return normalized;
    }
    return 'worker';
  }

  bool _permissionTruthy(dynamic value) {
    if (value == true || value == 1) return true;
    if (value is String) {
      final normalized = value.trim().toLowerCase();
      return normalized == 'true' || normalized == '1';
    }
    return false;
  }
}
