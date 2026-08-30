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

  static const Duration _uploadDebounce = Duration(milliseconds: 250);
  static const int _batchSize = 200;
  static const int _downloadPageSize = 500;
  static const String _workshopProfileTable = '__WorkshopProfile';
  static const String _workshopProfileRowId = 'current';

  final SqlDatabase _db = SqlDatabase();
  final Random _random = Random.secure();
  final StreamController<Map<String, dynamic>> _permissionsController =
      StreamController<Map<String, dynamic>>.broadcast();

  Timer? _uploadTimer;
  RealtimeChannel? _permissionsChannel;
  Future<void>? _startTask;
  Future<void>? _activeUpload;
  Future<void>? _activeDownload;
  bool _uploadQueued = false;
  bool _isApplyingRemoteData = false;
  String? _workshopUuid;
  String? _workshopCode;
  String? _permissionsChannelName;
  RealtimeChannel? _workshopDataChannel;
  String? _workshopDataChannelName;
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
    _startTask ??= _startAsync().whenComplete(() {
      _startTask = null;
    });
  }

  Future<bool> ensureStarted({
    void Function()? onDataChanged,
    Duration timeout = const Duration(seconds: 12),
  }) async {
    start(onDataChanged: onDataChanged);
    try {
      await _startTask?.timeout(timeout);
    } catch (error) {
      print('Supabase workshop sync start timeout/error: $error');
    }
    return isReady;
  }

  void stop() {
    _uploadTimer?.cancel();
    final permissionsChannel = _permissionsChannel;
    if (permissionsChannel != null) {
      unawaited(_client.removeChannel(permissionsChannel));
    }
    final workshopDataChannel = _workshopDataChannel;
    if (workshopDataChannel != null) {
      unawaited(_client.removeChannel(workshopDataChannel));
    }
    _uploadTimer = null;
    _permissionsChannel = null;
    _permissionsChannelName = null;
    _workshopDataChannel = null;
    _workshopDataChannelName = null;
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
    final uploadData = <String, dynamic>{...data};
    final pendingTombstones = pendingBeforeUpload.data['SyncTombstones'];
    if (pendingTombstones is List && pendingTombstones.isNotEmpty) {
      uploadData['SyncTombstones'] = pendingTombstones;
    }
    final rows = _flattenDataForUpload(
      uploadData,
      workshopUuid: workshopUuid,
      userId: user.id,
      fullUpload: false,
    );

    if (rows.isEmpty) {
      throw Exception('لا توجد بيانات ورشة محلية لرفعها.');
    }

    // A full backup must never erase the remote workshop based on one phone's
    // incomplete local snapshot. Merge the local rows and protect remote rows
    // that were modified more recently on another device.
    await _upsertRows(rows, preserveNewerRemote: true);

    await _acknowledgeSyncedChanges(pendingBeforeUpload);
    await _saveLastSyncAt(DateTime.now().toUtc().toIso8601String());

    lastUploadSummary =
        'تم دمج ${rows.length} سجل بأمان في Supabase: '
        '${_countRows(data, 'Client')} زبون، '
        '${_countRows(data, 'Commandes')} طلبية، '
        '${_countRows(data, 'Commandes_details')} تفاصيل.';
  }

  Future<void> uploadLocalWorkshopDataMerge() async {
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

    if (rows.isEmpty) return;

    final remoteKeys = await _fetchRemoteLiveRowKeys(workshopUuid);
    final missingRows = rows
        .where((row) {
          final table = row['table_name']?.toString() ?? '';
          final rowId = row['row_id']?.toString() ?? '';
          return table.isNotEmpty &&
              rowId.isNotEmpty &&
              !remoteKeys.contains(_rowKey(table, rowId));
        })
        .toList(growable: false);

    if (missingRows.isEmpty) {
      lastUploadSummary =
          'لا توجد سجلات محلية ناقصة في Supabase؛ لم يتم رفع أي نسخة قديمة فوق السيرفر.';
      return;
    }

    await _upsertRows(missingRows);
    await _acknowledgeSyncedChanges(pendingBeforeUpload);

    lastUploadSummary =
        'تم رفع ${missingRows.length} سجل محلي ناقص إلى Supabase بدون تعديل السجلات الموجودة: '
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

  /// Saves the manager's workshop header in the existing workshop sync table.
  /// This keeps the profile available to every workshop member without adding
  /// another Supabase table or coupling it to a worker's local preferences.
  Future<void> saveWorkshopProfile(Map<String, dynamic> profile) async {
    await _ensureReady();
    final workshopUuid = _workshopUuid!;
    final now = DateTime.now().toUtc().toIso8601String();
    await _client.from('workshop_sync_rows').upsert({
      'workshop_id': workshopUuid,
      'table_name': _workshopProfileTable,
      'row_id': _workshopProfileRowId,
      'payload': <String, dynamic>{...profile, 'updated_at': now},
      'updated_at': now,
      'deleted_at': null,
      'device_id': _deviceId,
      'revision': DateTime.now().microsecondsSinceEpoch,
    }, onConflict: 'workshop_id,table_name,row_id');
  }

  /// Saves the complete list of systems selected for this workshop.
  ///
  /// System selection is workshop configuration, not a local device setting.
  /// Keep it in the same Supabase profile row so Realtime can deliver both
  /// additions and removals to every member of the workshop.
  Future<void> saveWorkshopSystems({
    required Map<String, bool> systemModes,
    required List<int> activeProfileIds,
  }) async {
    await _ensureReady();
    final currentProfile = await readWorkshopProfile();
    await saveWorkshopProfile({
      ...currentProfile,
      'workshop_systems': {
        'modes': <String, bool>{...systemModes},
        'active_profile_ids': activeProfileIds.toList(growable: false),
      },
    });
  }

  Future<Map<String, dynamic>> readWorkshopProfile() async {
    await _ensureReady();
    final row = await _client
        .from('workshop_sync_rows')
        .select('payload')
        .eq('workshop_id', _workshopUuid!)
        .eq('table_name', _workshopProfileTable)
        .eq('row_id', _workshopProfileRowId)
        .maybeSingle();
    final payload = row?['payload'];
    return payload is Map
        ? Map<String, dynamic>.from(payload)
        : <String, dynamic>{};
  }

  /// Applies the latest workshop system selection immediately on this device.
  /// This is used by the manual refresh button; normal devices receive the
  /// same profile automatically through the Realtime download listener.
  Future<void> loadAndApplyWorkshopSystems() async {
    await _ensureReady();
    final profile = await readWorkshopProfile();
    final systems = profile['workshop_systems'];
    if (systems is Map) {
      await _applyWorkshopSystems(Map<String, dynamic>.from(systems));
    }
  }

  /// Returns the real workshop display name, never the workshop code.
  ///
  /// Older workshop rows used the code as their name. Documents must not
  /// expose that technical identifier, so check the synced profile and the
  /// workshop identity separately and return null when neither has a real
  /// human-readable name.
  Future<String?> readWorkshopDisplayName() async {
    await _ensureReady();
    final prefs = await SharedPreferences.getInstance();
    final code = (_workshopCode ?? prefs.getString('workshop_code') ?? '')
        .trim();

    bool isUsable(String value) => value.isNotEmpty && value != code;

    final cachedName = (prefs.getString('workshop_name') ?? '').trim();
    if (isUsable(cachedName)) return cachedName;

    try {
      final profile = await readWorkshopProfile();
      final profileName = profile['workshop_name']?.toString().trim() ?? '';
      if (isUsable(profileName)) {
        await prefs.setString('workshop_name', profileName);
        return profileName;
      }
    } catch (_) {}

    try {
      final row = await _client
          .from('workshops')
          .select('name')
          .eq('id', _workshopUuid!)
          .maybeSingle();
      final remoteName = row?['name']?.toString().trim() ?? '';
      if (isUsable(remoteName)) {
        await prefs.setString('workshop_name', remoteName);
        return remoteName;
      }
    } catch (_) {}

    return null;
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
      _subscribeToWorkshopDataChanges();
      _subscribeToPermissionChanges();
      await refreshCurrentPermissions();
      final needsFullBootstrap = await _needsFullBootstrapDownload();
      final hasLocalBusinessData = await _hasLocalBusinessData();
      if (needsFullBootstrap && !hasLocalBusinessData) {
        await downloadWorkshopData(full: true);
      } else {
        await downloadWorkshopData();
      }
      if (needsFullBootstrap) {
        await _markFullBootstrapComplete();
      }
      await uploadPendingChanges();
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

  void _subscribeToWorkshopDataChanges() {
    final workshopUuid = _workshopUuid;
    if (workshopUuid == null || workshopUuid.isEmpty) return;

    final channelName = 'workshop_data_$workshopUuid';
    if (_workshopDataChannelName == channelName &&
        _workshopDataChannel != null) {
      return;
    }

    final oldChannel = _workshopDataChannel;
    if (oldChannel != null) {
      unawaited(_client.removeChannel(oldChannel));
    }

    _workshopDataChannelName = channelName;
    _workshopDataChannel = _client
        .channel(channelName)
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'workshop_sync_rows',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'workshop_id',
            value: workshopUuid,
          ),
          callback: (_) {
            // Realtime carries only the change notification. The normal
            // incremental downloader remains the single place that applies
            // rows, tombstones, and workshop profile values safely.
            unawaited(downloadWorkshopData());
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

    // A status/payment change can bundle the order's detail rows for
    // consistency.  Those details may be older on this device, so never let
    // them overwrite a newer copy already stored in Supabase.
    await _upsertRows(rows, preserveNewerRemote: true);
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
    var profileChanged = false;
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
        if (rowId.isEmpty) continue;

        final updatedAt = row['updated_at']?.toString();
        if (updatedAt != null &&
            (newestUpdate == null || updatedAt.compareTo(newestUpdate) > 0)) {
          newestUpdate = updatedAt;
        }

        final deletedAt = row['deleted_at']?.toString();
        if (deletedAt != null && deletedAt.isNotEmpty) {
          if (table == _workshopProfileTable) continue;
          if (!_isWorkshopTable(table)) continue;
          tombstones.add({
            'table_name': table,
            'row_id': rowId,
            'deleted_at': deletedAt,
          });
          downloadedRows++;
          continue;
        }

        final payload = row['payload'];
        if (table == _workshopProfileTable) {
          if (rowId == _workshopProfileRowId && payload is Map) {
            await _applyWorkshopProfile(Map<String, dynamic>.from(payload));
            profileChanged = true;
            downloadedRows++;
          }
          continue;
        }
        if (!_isWorkshopTable(table)) continue;
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

    // The profile row is metadata, not a business table. It must not make a
    // full bootstrap clear a worker's local business data when the workshop
    // has only a profile and no synced orders/clients yet.
    final shouldReplaceLocalWorkshop =
        full && (data.isNotEmpty || tombstones.isNotEmpty);
    if (shouldReplaceLocalWorkshop) {
      for (final table in SqlDatabase.workshopTables) {
        data.putIfAbsent(table, () => <Map<String, dynamic>>[]);
      }
    }

    if (data.isNotEmpty) {
      _isApplyingRemoteData = true;
      try {
        await _db.importWorkshopData(
          data,
          replaceAllData: shouldReplaceLocalWorkshop,
        );
        if (shouldReplaceLocalWorkshop) {
          await _db.clearPendingCloudChanges();
        }
      } finally {
        _isApplyingRemoteData = false;
      }
      _onDataChanged?.call();
    }

    // A profile-only update has no business-table rows, but it still must
    // refresh the visible workshop name/logo/address on every device.
    if (profileChanged && data.isEmpty) {
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

    final storedCode = (prefs.getString('workshop_code') ?? '').trim();
    final code = storedCode.isNotEmpty ? storedCode : user.id;
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
        .insert({
          'code': code,
          'name': workshopName.trim().isEmpty ? code : workshopName.trim(),
          'owner_uid': user.id,
        })
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
      final cachedName = (prefs.getString('workshop_name') ?? '').trim();
      if (code.isNotEmpty) {
        await prefs.setString('workshop_code', code);
        _workshopCode = code;
      }
      if (name.isNotEmpty) {
        // A legacy fallback could have stored the workshop code in the
        // workshops.name column. Never let that overwrite the real local
        // workshop name used by document headers.
        final remoteNameIsCode = code.isNotEmpty && name == code;
        final usableName = remoteNameIsCode
            ? (cachedName.isNotEmpty && cachedName != code ? cachedName : '')
            : name;
        if (usableName.isNotEmpty && usableName != code) {
          await prefs.setString('workshop_name', usableName);
          await prefs.setString('user_display_name', usableName);
        } else if (remoteNameIsCode) {
          // Do not leave the technical code in the local display-name slot.
          await prefs.remove('workshop_name');
        }
      }
    } catch (error) {
      print('Supabase workshop identity cache skipped: $error');
    }
  }

  Future<void> _upsertRows(
    List<Map<String, dynamic>> rows, {
    bool preserveNewerRemote = false,
  }) async {
    var rowsToUpload = rows;
    if (preserveNewerRemote && rows.isNotEmpty) {
      final remoteUpdatedAt = await _fetchRemoteUpdatedAt();
      rowsToUpload = rows
          .where((row) {
            final table = row['table_name']?.toString() ?? '';
            final rowId = row['row_id']?.toString() ?? '';
            final incoming = DateTime.tryParse(
              row['updated_at']?.toString() ?? '',
            );
            final remote = remoteUpdatedAt[_rowKey(table, rowId)];
            // Rows without a valid timestamp are retained for compatibility with
            // old databases.  A valid remote timestamp still protects against a
            // clearly older incoming row.
            if (incoming == null || remote == null) return true;
            return !remote.isAfter(incoming);
          })
          .toList(growable: false);
    }

    if (rowsToUpload.isEmpty) return;
    for (var start = 0; start < rowsToUpload.length; start += _batchSize) {
      final end = min(start + _batchSize, rowsToUpload.length);
      await _client
          .from('workshop_sync_rows')
          .upsert(
            rowsToUpload.sublist(start, end),
            onConflict: 'workshop_id,table_name,row_id',
          );
    }
  }

  Future<Map<String, DateTime>> _fetchRemoteUpdatedAt() async {
    final workshopUuid = _workshopUuid;
    if (workshopUuid == null || workshopUuid.isEmpty) {
      return <String, DateTime>{};
    }

    final result = <String, DateTime>{};
    var start = 0;
    while (true) {
      final rows = await _client
          .from('workshop_sync_rows')
          .select('table_name,row_id,updated_at')
          .eq('workshop_id', workshopUuid)
          .order('table_name', ascending: true)
          .order('row_id', ascending: true)
          .range(start, start + _downloadPageSize - 1);
      if (rows.isEmpty) break;
      for (final rawRow in rows) {
        final row = Map<String, dynamic>.from(rawRow);
        final table = row['table_name']?.toString() ?? '';
        final rowId = row['row_id']?.toString() ?? '';
        final updatedAt = DateTime.tryParse(
          row['updated_at']?.toString() ?? '',
        );
        if (table.isNotEmpty && rowId.isNotEmpty && updatedAt != null) {
          result[_rowKey(table, rowId)] = updatedAt;
        }
      }
      if (rows.length < _downloadPageSize) break;
      start += _downloadPageSize;
    }
    return result;
  }

  Future<Set<String>> _fetchRemoteLiveRowKeys(String workshopUuid) async {
    final keys = <String>{};
    var start = 0;
    while (true) {
      final rows = await _client
          .from('workshop_sync_rows')
          .select('table_name,row_id,deleted_at')
          .eq('workshop_id', workshopUuid)
          .order('table_name', ascending: true)
          .order('row_id', ascending: true)
          .range(start, start + _downloadPageSize - 1);
      if (rows.isEmpty) break;
      for (final rawRow in rows) {
        final row = Map<String, dynamic>.from(rawRow);
        final table = row['table_name']?.toString() ?? '';
        final rowId = row['row_id']?.toString() ?? '';
        final deletedAt = row['deleted_at']?.toString() ?? '';
        if (table.isNotEmpty && rowId.isNotEmpty && deletedAt.isEmpty) {
          keys.add(_rowKey(table, rowId));
        }
      }
      if (rows.length < _downloadPageSize) break;
      start += _downloadPageSize;
    }
    return keys;
  }

  String _rowKey(String table, String rowId) => '$table\x1f$rowId';

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
        final storedUpdatedAt = row['updated_at']?.toString().trim() ?? '';
        rows.add({
          'workshop_id': workshopUuid,
          'table_name': table,
          'row_id': rowId,
          'payload': row,
          // Keep the row's own modification time.  Using the upload time here
          // made an old bundled detail look newer than the manager's detail
          // and could restore quantity/price as zero on other devices.
          'updated_at': storedUpdatedAt.isNotEmpty ? storedUpdatedAt : now,
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

  String? _bootstrapKey() {
    final code = _workshopCode;
    if (code == null || code.isEmpty) return null;
    return 'supabase_workshop_full_bootstrap_v2_$code';
  }

  Future<void> _applyWorkshopProfile(Map<String, dynamic> profile) async {
    final prefs = await SharedPreferences.getInstance();

    Future<void> saveString(String key, Object? value) async {
      final text = value?.toString().trim() ?? '';
      // Write empty values too, so clearing a field on the manager device
      // also clears the old value on worker devices.
      await prefs.setString(key, text);
    }

    final incomingName = profile['workshop_name']?.toString().trim() ?? '';
    final currentName = (prefs.getString('workshop_name') ?? '').trim();
    final code = (_workshopCode ?? prefs.getString('workshop_code') ?? '')
        .trim();
    if (incomingName.isNotEmpty && incomingName != code) {
      await saveString('workshop_name', incomingName);
    } else if (currentName == code) {
      // Do not replace an existing real name with an empty value or a code.
      await prefs.remove('workshop_name');
    }
    await saveString('workshop_address', profile['workshop_address']);
    await saveString('phone', profile['phone']);
    await saveString('workshop_specialties', profile['workshop_specialties']);
    await saveString('workshop_manager_name', profile['manager_name']);
    await saveString('workshop_rc', profile['rc']);
    await saveString('workshop_nif', profile['nif']);
    await saveString('workshop_nis', profile['nis']);
    await saveString('workshop_ai', profile['ai']);
    await saveString('workshop_rib', profile['rib']);
    await saveString('workshop_logo_base64', profile['logo']);
    await saveString('workshop_worker_count', profile['worker_count']);

    final systems = profile['workshop_systems'];
    if (systems is Map) {
      await _applyWorkshopSystems(Map<String, dynamic>.from(systems));
    }
  }

  Future<void> _applyWorkshopSystems(Map<String, dynamic> systems) async {
    final prefs = await SharedPreferences.getInstance();

    final rawModes = systems['modes'];
    if (rawModes is Map) {
      for (final entry in rawModes.entries) {
        final value = entry.value;
        final enabled = value is bool
            ? value
            : value is num
            ? value != 0
            : value?.toString().toLowerCase() == 'true';
        await prefs.setBool('system_active_${entry.key}', enabled);
      }
    }

    final rawActiveProfiles = systems['active_profile_ids'];
    if (rawActiveProfiles is! List) return;

    final activeIds = rawActiveProfiles
        .map(
          (value) =>
              value is num ? value.toInt() : int.tryParse(value.toString()),
        )
        .whereType<int>()
        .toSet();
    final dbInstance = await _db.db;
    if (dbInstance == null) return;

    // Replace the complete selection, so a system removed by the manager is
    // also disabled on every worker device.
    await dbInstance.update('Profile', {'is_active': 0});
    await dbInstance.update('Series', {'is_active': 0});
    for (final id in activeIds) {
      await dbInstance.update(
        'Profile',
        {'is_active': 1},
        where: 'id = ?',
        whereArgs: [id],
      );
      await dbInstance.update(
        'Series',
        {'is_active': 1},
        where: 'profile_id = ? OR id = ?',
        whereArgs: [id, id],
      );
    }
  }

  Future<bool> _needsFullBootstrapDownload() async {
    final key = _bootstrapKey();
    if (key == null) return false;
    final prefs = await SharedPreferences.getInstance();
    return !(prefs.getBool(key) ?? false);
  }

  Future<void> _markFullBootstrapComplete() async {
    final key = _bootstrapKey();
    if (key == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, true);
  }

  bool _isWorkshopTable(String table) {
    return SqlDatabase.workshopTables.contains(table);
  }

  Future<bool> _hasLocalBusinessData() async {
    final myDb = await _db.db;
    if (myDb == null) return false;
    try {
      final clients = await myDb.query('Client', limit: 1);
      final orders = await myDb.query('Commandes', limit: 1);
      return clients.isNotEmpty || orders.isNotEmpty;
    } catch (_) {
      return false;
    }
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
