import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:database_data/sql_database.dart';
import 'package:database_data/settings/app_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:database_data/settings/shortcut_bindings.dart';
import 'package:database_data/services/order_notification_service.dart';
import 'package:database_data/services/worker_push_notification_service.dart';
import 'package:database_data/services/app_admin_status_service.dart';
import 'package:database_data/services/cloud_sync_service.dart';

class WorkshopDataDiagnostics {
  const WorkshopDataDiagnostics({
    required this.userId,
    required this.workshopUuid,
    required this.workshopCode,
    required this.remoteWorkshopExists,
    required this.remoteWorkshopName,
    required this.syncRows,
    required this.members,
    required this.profileExists,
    required this.profileName,
  });

  final String userId;
  final String workshopUuid;
  final String workshopCode;
  final bool remoteWorkshopExists;
  final String remoteWorkshopName;
  final int syncRows;
  final int members;
  final bool profileExists;
  final String profileName;
}

class SupabaseWorkshopSyncService {
  SupabaseWorkshopSyncService._internal();

  static final SupabaseWorkshopSyncService _instance =
      SupabaseWorkshopSyncService._internal();

  factory SupabaseWorkshopSyncService() => _instance;

  @visibleForTesting
  static bool shouldDownloadFullOnStartup({
    required bool bootstrapComplete,
    required bool hasSyncCursor,
  }) {
    return !bootstrapComplete || !hasSyncCursor;
  }

  @visibleForTesting
  static bool shouldCompleteFullBootstrap({
    required int downloadedBusinessRows,
  }) {
    return downloadedBusinessRows > 0;
  }

  @visibleForTesting
  static bool shouldApplyWorkshopCatalogConfiguration({
    required bool hasPendingLocalChanges,
  }) {
    // A pending local snapshot is the user's newest known edit. Applying a
    // remote whole-table snapshot first can erase it before the retry uploads
    // it, so defer the download until the durable pending upload succeeds.
    return !hasPendingLocalChanges;
  }

  Future<bool> _canApplyRemoteWorkshopCatalogConfiguration() async {
    final prefs = await SharedPreferences.getInstance();
    return shouldApplyWorkshopCatalogConfiguration(
      hasPendingLocalChanges:
          prefs.getBool('has_pending_workshop_catalog_configuration') ?? false,
    );
  }

  static const Duration _uploadDebounce = Duration(milliseconds: 250);

  // Realtime handles normal changes. This slow pass only repairs a missed
  // event after sleep/network loss and must not behave like a UI refresh loop.
  static const Duration _backgroundSyncInterval = Duration(minutes: 3);

  // A workshop row contains a complete JSON payload.  A 200-row PostgREST
  // upsert can exceed the server statement timeout even though the row count
  // itself looks modest, particularly for order details and stock history.
  static const int _uploadBatchSize = 25;
  static const int _uploadBatchRetryCount = 3;

  // Keep each decoded response and the matching PostgREST query small.
  // Workshop rows embed JSON payloads, so a full restore after installation
  // must not request hundreds of orders/stock rows in one response.
  static const int _downloadPageSize = 25;
  static const String _workshopProfileTable = '__WorkshopProfile';
  static const String _workshopProfileRowId = 'current';
  static const String _workshopCatalogConfigurationTable =
      '__WorkshopCatalogConfiguration';
  static const String _workshopCatalogConfigurationRowId = 'current';

  final SqlDatabase _db = SqlDatabase();
  final Random _random = Random.secure();
  final StreamController<Map<String, dynamic>> _permissionsController =
      StreamController<Map<String, dynamic>>.broadcast();

  Timer? _uploadTimer;
  Timer? _backgroundSyncTimer;
  Timer? _permissionsRefreshTimer;
  RealtimeChannel? _permissionsChannel;
  Future<void>? _startTask;
  Future<void>? _activeUpload;
  Future<void>? _activeDownload;
  bool _activeDownloadIsFull = false;
  bool _lastFullDownloadHadBusinessRows = false;
  bool _uploadQueued = false;
  bool _isApplyingRemoteData = false;
  String? _workshopUuid;
  String? _workshopCode;
  DateTime? _lastMembershipVerifiedAt;
  static const Duration _membershipCacheValidity = Duration(minutes: 15);
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

  bool get isSignedIn {
    try {
      return _client.auth.currentUser != null;
    } catch (_) {
      return false;
    }
  }

  bool get isReady => isSignedIn && _workshopUuid != null;

  String get currentWorkshopUuid => _workshopUuid ?? '';

  String get currentWorkshopCode => _workshopCode ?? '';

  /// Reads the remote identity and the first batch of remote data without
  /// changing the local database. This prevents a false "downloaded"
  /// message when the selected code points to an empty or different workshop.
  Future<WorkshopDataDiagnostics> inspectWorkshopData() async {
    await _ensureReady();
    final user = _client.auth.currentUser!;
    final workshopUuid = _workshopUuid!;

    final workshop = await _client
        .from('workshops')
        .select('id,code,join_code,name')
        .eq('id', workshopUuid)
        .maybeSingle();

    final profileRow = await _client
        .from('workshop_sync_rows')
        .select('payload')
        .eq('workshop_id', workshopUuid)
        .eq('table_name', _workshopProfileTable)
        .eq('row_id', _workshopProfileRowId)
        .maybeSingle();

    var profileExists = false;
    var profileName = '';
    final profilePayload = profileRow?['payload'];
    if (profilePayload is Map) {
      profileExists = true;
      profileName = profilePayload['workshop_name']?.toString().trim() ?? '';
    }

    int syncRows = 0;
    try {
      final countResult = await _client
          .from('workshop_sync_rows')
          .count(CountOption.exact)
          .eq('workshop_id', workshopUuid);
      syncRows = countResult;
    } catch (_) {
      try {
        final lightRows = await _client
            .from('workshop_sync_rows')
            .select('row_id')
            .eq('workshop_id', workshopUuid)
            .limit(1000);
        syncRows = lightRows.length;
      } catch (_) {}
    }

    int membersCount = 0;
    try {
      final members = await _client
          .from('workshop_members')
          .select('user_id')
          .eq('workshop_id', workshopUuid)
          .limit(100);
      membersCount = members.length;
    } catch (_) {}

    return WorkshopDataDiagnostics(
      userId: user.id,
      workshopUuid: workshopUuid,
      workshopCode: _workshopCode ?? '',
      remoteWorkshopExists: workshop != null,
      remoteWorkshopName: workshop?['name']?.toString().trim() ?? '',
      syncRows: syncRows,
      members: membersCount,
      profileExists: profileExists,
      profileName: profileName,
    );
  }

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
      if (error.toString().contains('WORKSHOP_USER_LIMIT_REACHED')) rethrow;
    }
    return isReady;
  }

  /// Creates a workshop only from the explicit "new workshop" registration
  /// flow. Startup, login, and background synchronization never call this.
  Future<String> createWorkshopForCurrentUser({
    required String joinCode,
    required String workshopName,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw Exception('يجب تسجيل الدخول قبل إنشاء الورشة.');
    }
    final cleanCode = joinCode.trim().toUpperCase();
    final cleanName = workshopName.trim();
    if (cleanCode.isEmpty || cleanName.isEmpty) {
      throw Exception('كود واسم الورشة مطلوبان.');
    }

    // This is the only client-side workshop creation path. Never fall back to
    // ensure_my_workshop here: older deployments used that RPC to create a
    // workshop when a code was missing, which caused duplicate workshops on
    // ordinary login/startup. If the explicit creation RPC is unavailable,
    // fail clearly and require the database migration instead.
    final result = await _client.rpc(
      'create_my_workshop',
      params: {'requested_join_code': cleanCode, 'requested_name': cleanName},
    );

    final workshopId = result?.toString().trim() ?? '';
    if (workshopId.isEmpty) {
      throw Exception('تعذر إنشاء الورشة الجديدة في Supabase.');
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('workshop_code', cleanCode);
    await prefs.setString('workshop_name', cleanName);
    await prefs.setString('selected_supabase_workshop_id', workshopId);
    await prefs.setString('supabase_workshop_uuid_$cleanCode', workshopId);
    return workshopId;
  }

  void stop() {
    _uploadTimer?.cancel();
    _backgroundSyncTimer?.cancel();
    _permissionsRefreshTimer?.cancel();
    final permissionsChannel = _permissionsChannel;
    if (permissionsChannel != null) {
      unawaited(_client.removeChannel(permissionsChannel));
    }
    final workshopDataChannel = _workshopDataChannel;
    if (workshopDataChannel != null) {
      unawaited(_client.removeChannel(workshopDataChannel));
    }
    _uploadTimer = null;
    _backgroundSyncTimer = null;
    _permissionsRefreshTimer = null;
    _permissionsChannel = null;
    _permissionsChannelName = null;
    _workshopDataChannel = null;
    _workshopDataChannelName = null;
    // Do not let the next login reuse the previous account's workshop
    // identity. This is especially important when a new worker signs in on
    // the same phone after pressing "logout and return".
    _workshopUuid = null;
    _workshopCode = null;
    _lastMembershipVerifiedAt = null;
    _deviceId = '';
  }

  void notifyLocalChange({bool immediate = false}) {
    if (_isApplyingRemoteData) return;
    if (immediate) {
      _uploadTimer?.cancel();
      unawaited(
        uploadPendingChanges().catchError((e) {
          debugPrint('uploadPendingChanges immediate error: ');
        }),
      );
      return;
    }

    _uploadTimer?.cancel();
    _uploadTimer = Timer(_uploadDebounce, () {
      unawaited(
        uploadPendingChanges().catchError((e) {
          debugPrint('uploadPendingChanges debounced error: ');
        }),
      );
    });
  }

  Future<void> uploadFullWorkshopData() async {
    await _ensureReady();
    final workshopUuid = _workshopUuid!;
    final user = _client.auth.currentUser!;
    final pendingBeforeUpload = await _db.exportPendingCloudChanges(
      allowedTables: SqlDatabase.workshopTables.toSet(),
    );
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
    final pendingBeforeUpload = await _db.exportPendingCloudChanges(
      allowedTables: SqlDatabase.workshopTables.toSet(),
    );
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
    final user = _client.auth.currentUser;
    final profileName = profile['workshop_name']?.toString().trim() ?? '';

    // Keep the canonical workshop identity in sync with the printable header.
    // Only the owner may rename the workshop; workers still receive the name
    // through the profile row below.
    if (user != null && profileName.isNotEmpty) {
      await _client
          .from('workshops')
          .update({'name': profileName, 'updated_at': now})
          .eq('id', workshopUuid)
          .eq('owner_uid', user.id);
    }

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

  Future<void> uploadPendingShortcutBindings() async {
    final prefs = await SharedPreferences.getInstance();
    final code = (_workshopCode ?? prefs.getString('workshop_code') ?? '')
        .trim();
    if (code.isEmpty) return;
    final pendingKey = 'pending_workshop_shortcuts_$code';
    final pending = prefs.getString(pendingKey);
    if (pending == null) return;
    final decoded = jsonDecode(pending);
    if (decoded is! Map) return;
    final current = await readWorkshopProfile();
    await saveWorkshopProfile({
      ...current,
      'workshop_shortcuts': Map<String, String>.from(decoded),
    });
    if (prefs.getString(pendingKey) == pending) await prefs.remove(pendingKey);
  }

  /// Mirrors series-role and catalogue-rule configuration to members of this
  /// workshop. Product definitions themselves remain in the global catalogue;
  /// this row carries only the workshop's configuration of those products.
  Future<void> saveWorkshopCatalogConfiguration(
    Map<String, dynamic> configuration,
  ) async {
    await _ensureReady();
    final workshopUuid = _workshopUuid!;
    final now = DateTime.now().toUtc().toIso8601String();
    await _client.from('workshop_sync_rows').upsert({
      'workshop_id': workshopUuid,
      'table_name': _workshopCatalogConfigurationTable,
      'row_id': _workshopCatalogConfigurationRowId,
      'payload': <String, dynamic>{'tables': configuration, 'updated_at': now},
      'updated_at': now,
      'deleted_at': null,
      'device_id': _deviceId,
      'revision': DateTime.now().microsecondsSinceEpoch,
    }, onConflict: 'workshop_id,table_name,row_id');
  }

  /// تحميل وتطبيق قواعد إكسسوارات وكتالوج الورشة فورياً ومباشرة في قاعدة البيانات
  Future<void> loadAndApplyWorkshopCatalogConfiguration() async {
    try {
      await _ensureReady();
      final row = await _client
          .from('workshop_sync_rows')
          .select('payload')
          .eq('workshop_id', _workshopUuid!)
          .eq('table_name', _workshopCatalogConfigurationTable)
          .eq('row_id', _workshopCatalogConfigurationRowId)
          .maybeSingle();

      final payload = row?['payload'];
      if (payload is Map && payload['tables'] is Map) {
        if (!await _canApplyRemoteWorkshopCatalogConfiguration()) {
          debugPrint(
            'Skipping remote workshop rules while a newer local upload is pending.',
          );
          return;
        }
        final config = Map<String, dynamic>.from(payload['tables'] as Map);
        _isApplyingRemoteData = true;
        try {
          await _db.importWorkshopCatalogConfiguration(config);
          debugPrint(
            '✅ تم بنجاح تنزيل وتطبيق قواعد إكسسوارات الورشة من السحابة',
          );
        } finally {
          _isApplyingRemoteData = false;
        }
      }
    } catch (e) {
      debugPrint('تنبيه: تعذر تحميل قواعد الكتالوج من السحابة: $e');
    }
  }

  /// Claims an old Firebase workshop using the stable legacy code. The SQL
  /// function validates the current Supabase email and creates the owner
  /// membership without ever storing a Firebase UID in a Supabase FK.
  Future<String> claimLegacyWorkshopOwner({
    required String code,
    required String name,
    required String legacyOwnerEmail,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) throw Exception('يجب تسجيل الدخول إلى Supabase أولاً.');

    final result = await _client.rpc(
      'claim_legacy_workshop',
      params: {
        'target_code': code.trim(),
        'target_name': name.trim(),
        'legacy_owner_email': legacyOwnerEmail.trim().toLowerCase(),
      },
    );
    final workshopUuid = result?.toString().trim() ?? '';
    if (workshopUuid.isEmpty) {
      throw Exception('تعذر ربط الورشة القديمة في Supabase.');
    }

    final prefs = await SharedPreferences.getInstance();
    _workshopUuid = workshopUuid;
    _workshopCode = code.trim();
    await prefs.setString(
      'supabase_workshop_uuid_${code.trim()}',
      workshopUuid,
    );
    await _cacheWorkshopIdentity(workshopUuid, prefs);
    return workshopUuid;
  }

  /// Saves the complete list of systems selected for this workshop.
  ///
  /// System selection is workshop configuration, not a local device setting.
  /// Keep it in the same Supabase profile row so Realtime can deliver both
  /// additions and removals to every member of the workshop.
  Future<void> saveWorkshopSystems({
    required Map<String, bool> systemModes,
    required List<int> activeProfileIds,
    List<String> activeProfileCodes = const [],
    List<String> activeProfileNames = const [],
  }) async {
    await _ensureReady();
    final currentProfile = await readWorkshopProfile();
    await saveWorkshopProfile({
      ...currentProfile,
      'workshop_systems': {
        'modes': <String, bool>{...systemModes},
        'active_profile_ids': activeProfileIds.toList(growable: false),
        'active_profile_codes': activeProfileCodes.toList(growable: false),
        'active_profile_names': activeProfileNames.toList(growable: false),
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

  /// Refresh the public join code from the shared workshop row. The code is
  /// an identity property of the workshop, not a value owned by one device.
  Future<void> refreshWorkshopIdentity() async {
    final workshopUuid = _workshopUuid;
    if (workshopUuid == null || workshopUuid.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final previousCode = prefs.getString('workshop_code') ?? '';
    final previousName = prefs.getString('workshop_name') ?? '';
    await _cacheWorkshopIdentity(workshopUuid, prefs);
    if (previousCode != (prefs.getString('workshop_code') ?? '') ||
        previousName != (prefs.getString('workshop_name') ?? '')) {
      _onDataChanged?.call();
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

    bool isUsable(String value) =>
        value.isNotEmpty &&
        value != code &&
        value != 'ورشة النجارة' &&
        value != 'ورشة الألمنيوم';

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
    if (activeDownload != null) {
      // Startup normally begins with an incremental download. If the user
      // pulls to refresh while that task is still running, returning it here
      // silently drops the requested full restore. Queue the full pass after
      // the current download so the workshop data is actually refreshed.
      // A fresh Android install already starts with a full bootstrap. A
      // second full-recovery request must join that same task; queuing full
      // behind full can recursively start complete downloads forever.
      if (full && !_activeDownloadIsFull) {
        return activeDownload.then<void>(
          (_) => downloadWorkshopData(full: true),
        );
      }
      return activeDownload;
    }

    final task = _downloadChanges(full: full);
    _activeDownloadIsFull = full;
    late Future<void> trackedTask;
    trackedTask = task.whenComplete(() {
      if (identical(_activeDownload, trackedTask)) {
        _activeDownload = null;
        _activeDownloadIsFull = false;
      }
    });
    _activeDownload = trackedTask;
    return trackedTask;
  }

  Future<void> _startAsync() async {
    try {
      await _ensureReady();
      await refreshWorkshopIdentity();
      _subscribeToWorkshopDataChanges();
      _subscribeToPermissionChanges();
      // Subscribe to order-event notifications for this workshop.
      _subscribeToOrderNotifications();
      _startBackgroundSync();
      // A temporary permission/RLS read failure must not abort the workshop
      // data download. The permission listener and the next sync cycle will
      // retry it; business data must continue to sync independently.
      try {
        await refreshCurrentPermissions();
      } catch (error) {
        print('Supabase permission refresh skipped during startup: $error');
      }
      final needsFullBootstrap = await _needsFullBootstrapDownload();
      // A full workshop snapshot is intentionally a one-time bootstrap. Using
      // the presence of clients or orders as an initialization signal made an
      // empty/new workshop download every remote row again on each launch.
      // SharedPreferences and the local database share the app lifecycle, so
      // reinstall/clear-data removes this marker and correctly triggers a new
      // bootstrap. Explicit recovery remains available through the full
      // restore action.
      if (needsFullBootstrap) {
        await downloadWorkshopData(full: true);
      } else {
        await downloadWorkshopData();
      }
      if (needsFullBootstrap && _lastFullDownloadHadBusinessRows) {
        await _markFullBootstrapComplete();
      }
      // تحميل قواعد الإكسسوارات لضمان وجودها دائماً في هاتف العامل
      await loadAndApplyWorkshopCatalogConfiguration();
      await uploadPendingChanges();
      await uploadPendingShortcutBindings();
      await _seedLegacyLocalDataOnce();
    } catch (error) {
      // Supabase sync is optional until the account/workshop is configured.
      // Keep the app usable and let the manual Settings buttons show the error.
      print('Supabase workshop sync not started: $error');
      // تجنب rethrow هنا لأن الدالة تعمل كـ unawaited في الخلفية وأي استثناء غير ملتقط يغلق التطبيق
    }
  }

  /// هل التطبيق في الخلفية حالياً؟
  /// يُستخدم لمنع دورة الـ background sync من العمل أثناء وجود التطبيق في الخلفية،
  /// مما يُقلل من استهلاك البطارية ويمنع استيقاظ العملية بشكل غير ضروري.
  bool _isInBackground = false;

  /// يُستدعى من main.dart عند انتقال التطبيق للخلفية (paused/detached).
  /// يوقف الـ timer تماماً حتى لا يُبقي العملية مستيقظة.
  void pauseBackgroundSync() {
    _isInBackground = true;
    _backgroundSyncTimer?.cancel();
    _backgroundSyncTimer = null;
    _permissionsRefreshTimer?.cancel();
    _permissionsRefreshTimer = null;
    debugPrint('SupabaseWorkshopSyncService: background sync paused.');
  }

  /// يُستدعى من main.dart عند رجوع التطبيق للمقدمة (resumed).
  /// يعيد تشغيل الـ timer إذا كانت الخدمة جاهزة.
  void resumeBackgroundSync() {
    _isInBackground = false;
    if (isReady && _backgroundSyncTimer == null) {
      _startBackgroundSync();
      _startPermissionsRefreshFallback();
      unawaited(_runBackgroundSyncCycle());
      unawaited(refreshCurrentPermissions());
      debugPrint('SupabaseWorkshopSyncService: background sync resumed.');
    }
  }

  void _startBackgroundSync() {
    _backgroundSyncTimer?.cancel();
    _backgroundSyncTimer = Timer.periodic(_backgroundSyncInterval, (_) {
      unawaited(_runBackgroundSyncCycle());
    });
  }

  void _startPermissionsRefreshFallback() {
    _permissionsRefreshTimer?.cancel();
    _permissionsRefreshTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (_isInBackground || !isReady) return;
      unawaited(
        refreshCurrentPermissions().catchError((error) {
          debugPrint('Periodic permission refresh skipped: $error');
        }),
      );
    });
  }

  Future<void> _runBackgroundSyncCycle() async {
    // Realtime and explicit local-write notifications are the primary sync
    // triggers. This pass is only a recovery mechanism and must never overlap
    // an upload/download already in progress.
    if (_isInBackground ||
        !isReady ||
        _isApplyingRemoteData ||
        _activeDownload != null ||
        _activeUpload != null) {
      return;
    }
    try {
      // Realtime normally triggers this immediately. The periodic pass is a
      // recovery path for sleeping devices, dropped channels, and failed
      // uploads whose local change log must remain retryable.
      final needsFullBootstrap = await _needsFullBootstrapDownload();
      await downloadWorkshopData(full: needsFullBootstrap);
      if (needsFullBootstrap && _lastFullDownloadHadBusinessRows) {
        await _markFullBootstrapComplete();
      }
      try {
        await loadAndApplyWorkshopCatalogConfiguration();
      } catch (e) {
        debugPrint(
          'loadAndApplyWorkshopCatalogConfiguration in background sync error: ',
        );
      }
      await uploadPendingChanges();
      await uploadPendingShortcutBindings();
    } catch (error) {
      print('Supabase background sync retry failed: $error');
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

    final isApplicationAdmin = await AppAdminStatusService.instance
        .isCurrentUserAdmin();

    final rawPermissions = row['permissions'];
    final permissions = rawPermissions is Map
        ? Map<String, dynamic>.from(rawPermissions)
        : <String, dynamic>{};
    if (_permissionTruthy(row['blocked'])) {
      permissions['isBlocked'] = true;
    }

    final appRole = isApplicationAdmin
        ? 'admin'
        : _mapSupabaseRoleToAppRole(
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
            unawaited(
              refreshCurrentPermissions().catchError((e) {
                debugPrint(
                  'Realtime permission refresh skipped (offline/error): $e',
                );
              }),
            );
          },
        )
        .subscribe((status, [error]) {
          if (error != null) {
            debugPrint(
              'Realtime permission channel status: $status, error: $error',
            );
          }
        });
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
            unawaited(
              downloadWorkshopData()
                  .then((_) {
                    unawaited(
                      loadAndApplyWorkshopCatalogConfiguration().catchError((
                        e,
                      ) {
                        debugPrint('Realtime loadAndApply failed: $e');
                      }),
                    );
                  })
                  .catchError((e) {
                    debugPrint(
                      'Realtime downloadWorkshopData skipped (offline/error): $e',
                    );
                  }),
            );
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'workshops',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: workshopUuid,
          ),
          callback: (_) {
            unawaited(
              refreshWorkshopIdentity().catchError((e) {
                debugPrint(
                  'Realtime refreshWorkshopIdentity skipped (offline/error): $e',
                );
              }),
            );
          },
        )
        .subscribe((status, [error]) {
          if (error != null) {
            debugPrint(
              'Realtime workshop channel status: $status, error: $error',
            );
          }
          if (status == RealtimeSubscribeStatus.subscribed) {
            unawaited(
              downloadWorkshopData().catchError((e) {
                debugPrint('Initial subscribed download error: $e');
              }),
            );
          }
        });
  }

  void _subscribeToOrderNotifications() {
    final workshopUuid = _workshopUuid;
    if (workshopUuid == null || workshopUuid.isEmpty) return;
    unawaited(
      OrderNotificationService().subscribeToWorkshop(workshopUuid).catchError((
        e,
      ) {
        debugPrint('OrderNotif subscription skipped: $e');
      }),
    );
    unawaited(
      WorkerPushNotificationService.instance.refreshRegistration().catchError((
        e,
      ) {
        debugPrint('Worker push token registration skipped: $e');
      }),
    );
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
    Object? deferredError;
    StackTrace? deferredStackTrace;
    try {
      do {
        _uploadQueued = false;
        try {
          await _performPendingUpload();
        } catch (uploadError, stackTrace) {
          debugPrint(
            'Supabase pending upload deferred (offline/network): $uploadError',
          );
          deferredError = uploadError;
          deferredStackTrace = stackTrace;
          break;
        }
      } while (_uploadQueued);
    } finally {
      _activeUpload = null;
    }
    if (deferredError != null) {
      Error.throwWithStackTrace(deferredError, deferredStackTrace!);
    }
  }

  Future<void> _performPendingUpload() async {
    await _ensureReady();
    final pending = await _db.exportPendingCloudChanges(
      allowedTables: SqlDatabase.workshopTables.toSet(),
    );
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
    Map<String, dynamic>? catalogConfiguration;
    var profileChanged = false;
    var catalogConfigurationChanged = false;
    var start = 0;
    var downloadedRows = 0;
    var downloadedBusinessRows = 0;
    String? newestUpdate;

    void processRow(Map<String, dynamic> row) {
      final table = row['table_name']?.toString() ?? '';
      final rowId = row['row_id']?.toString() ?? '';
      if (rowId.isEmpty) return;

      final updatedAt = row['updated_at']?.toString();
      if (updatedAt != null &&
          (newestUpdate == null || updatedAt.compareTo(newestUpdate!) > 0)) {
        newestUpdate = updatedAt;
      }

      final deletedAt = row['deleted_at']?.toString();
      if (deletedAt != null && deletedAt.isNotEmpty) {
        if (table == _workshopProfileTable) return;
        if (!_isWorkshopTable(table)) return;
        tombstones.add({
          'table_name': table,
          'row_id': rowId,
          'deleted_at': deletedAt,
        });
        downloadedRows++;
        return;
      }

      final payload = row['payload'];
      if (table == _workshopProfileTable) {
        if (rowId == _workshopProfileRowId && payload is Map) {
          unawaited(_applyWorkshopProfile(Map<String, dynamic>.from(payload)));
          profileChanged = true;
          downloadedRows++;
        }
        return;
      }
      if (table == _workshopCatalogConfigurationTable) {
        if (rowId == _workshopCatalogConfigurationRowId &&
            payload is Map &&
            payload['tables'] is Map) {
          catalogConfiguration = Map<String, dynamic>.from(
            payload['tables'] as Map,
          );
          catalogConfigurationChanged = true;
          downloadedRows++;
        }
        return;
      }
      if (!_isWorkshopTable(table)) return;
      if (payload is Map) {
        final list =
            data.putIfAbsent(table, () => <Map<String, dynamic>>[])
                as List<Map<String, dynamic>>;
        list.add(Map<String, dynamic>.from(payload));
        downloadedRows++;
        downloadedBusinessRows++;
      }
    }

    if (full) {
      // 1. Workshop Profile row
      try {
        final profileRow = await _client
            .from('workshop_sync_rows')
            .select('table_name,row_id,payload,updated_at,deleted_at,device_id')
            .eq('workshop_id', workshopUuid)
            .eq('table_name', _workshopProfileTable)
            .eq('row_id', _workshopProfileRowId)
            .maybeSingle();
        if (profileRow != null) {
          final rowMap = Map<String, dynamic>.from(profileRow);
          final p = rowMap['payload'];
          if (p is Map) {
            await _applyWorkshopProfile(Map<String, dynamic>.from(p));
            profileChanged = true;
            downloadedRows++;
          }
        }
      } catch (e) {
        debugPrint('Full restore profile fetch error: $e');
      }

      // 2. Workshop Catalog Configuration row
      try {
        final configRow = await _client
            .from('workshop_sync_rows')
            .select('table_name,row_id,payload,updated_at,deleted_at,device_id')
            .eq('workshop_id', workshopUuid)
            .eq('table_name', _workshopCatalogConfigurationTable)
            .eq('row_id', _workshopCatalogConfigurationRowId)
            .maybeSingle();
        if (configRow != null) {
          final rowMap = Map<String, dynamic>.from(configRow);
          final p = rowMap['payload'];
          if (p is Map && p['tables'] is Map) {
            catalogConfiguration = Map<String, dynamic>.from(
              p['tables'] as Map,
            );
            catalogConfigurationChanged = true;
            downloadedRows++;
          }
        }
      } catch (e) {
        debugPrint('Full restore catalog configuration fetch error: $e');
      }

      // 3. Business tables fetched table by table with adaptive batch sizes
      for (final table in SqlDatabase.workshopTables) {
        final isHeavy =
            table == 'Commandes_details' || table == 'Commandes_deliveries';
        final tableBatchSize = isHeavy ? 5 : 50;
        var offset = 0;
        while (true) {
          List<dynamic> rows = const [];
          try {
            rows = await _client
                .from('workshop_sync_rows')
                .select(
                  'table_name,row_id,payload,updated_at,deleted_at,device_id',
                )
                .eq('workshop_id', workshopUuid)
                .eq('table_name', table)
                .order('updated_at', ascending: true)
                .range(offset, offset + tableBatchSize - 1);
          } catch (batchError) {
            debugPrint(
              'Batch error on table $table at offset $offset: $batchError',
            );
            if (isHeavy) {
              // Fallback: fetch single rows for this batch range to isolate any timeout
              Object? fallbackError;
              for (
                var single = offset;
                single < offset + tableBatchSize;
                single++
              ) {
                try {
                  final singleRows = await _client
                      .from('workshop_sync_rows')
                      .select(
                        'table_name,row_id,payload,updated_at,deleted_at,device_id',
                      )
                      .eq('workshop_id', workshopUuid)
                      .eq('table_name', table)
                      .order('updated_at', ascending: true)
                      .range(single, single);
                  if (singleRows.isEmpty) break;
                  processRow(
                    Map<String, dynamic>.from(singleRows.first as Map),
                  );
                } catch (singleError) {
                  fallbackError ??= singleError;
                  debugPrint(
                    'Single row fetch error on $table at $single: $singleError',
                  );
                }
              }
              if (fallbackError != null) {
                throw Exception(
                  'تعذر استرجاع جدول $table بالكامل: $fallbackError',
                );
              }
              offset += tableBatchSize;
              continue;
            } else {
              throw Exception('تعذر استرجاع جدول $table: $batchError');
            }
          }

          if (rows.isEmpty) break;
          for (final rawRow in rows) {
            processRow(Map<String, dynamic>.from(rawRow as Map));
          }
          if (rows.length < tableBatchSize) break;
          offset += tableBatchSize;
        }
      }
    } else {
      const incrementalBatchSize = 10;
      while (true) {
        final rows = await _client
            .from('workshop_sync_rows')
            .select('table_name,row_id,payload,updated_at,deleted_at,device_id')
            .eq('workshop_id', workshopUuid)
            .gt('updated_at', since!)
            .order('updated_at', ascending: true)
            .range(start, start + incrementalBatchSize - 1);
        if (rows.isEmpty) break;

        for (final rawRow in rows) {
          processRow(Map<String, dynamic>.from(rawRow as Map));
        }

        if (rows.length < incrementalBatchSize) break;
        start += incrementalBatchSize;
      }
    }

    if (!full && data.containsKey('Commandes')) {
      final orders = data['Commandes'] as List<Map<String, dynamic>>?;
      if (orders != null && orders.isNotEmpty) {
        for (final order in orders) {
          final deleted =
              order['is_deleted'] == true ||
              order['is_deleted'] == 1 ||
              order['deleted_at']?.toString().trim().isNotEmpty == true;
          if (deleted) continue;
          final orderDeviceId = order['device_id']?.toString() ?? '';
          if (orderDeviceId.isNotEmpty && orderDeviceId == _deviceId) continue;
          final currentUserId = _client.auth.currentUser?.id;
          final orderUserId = order['user_id']?.toString() ?? '';
          if (currentUserId != null &&
              currentUserId.isNotEmpty &&
              orderUserId.isNotEmpty &&
              currentUserId == orderUserId) {
            continue;
          }
          final clientName = ' '.trim();
          final orderCode =
              order['order_code']?.toString() ??
              order['display_number']?.toString() ??
              '';
          final author =
              order['created_by']?.toString() ??
              order['updated_by']?.toString() ??
              '';
          final orderId =
              (order['id'] as num?)?.toInt() ??
              int.tryParse(order['id']?.toString() ?? '') ??
              0;
          // Creation is determined by whether this device already has the
          // order. Comparing created_at with updated_at incorrectly marked a
          // newly-created order as edited whenever its business date differed
          // from the cloud upload timestamp.
          final existedLocally =
              orderId != 0 &&
              await _db.readCommandeWithClientById(orderId) != null;
          unawaited(
            OrderNotificationService().showOrderNotificationFromSync(
              orderId: orderId,
              clientName: clientName,
              orderCode: orderCode,
              author: author,
              isNew: !existedLocally,
            ),
          );
        }
      }
    }

    if (tombstones.isNotEmpty) {
      data['SyncTombstones'] = tombstones;
    }

    final finalCatalogConfig = catalogConfiguration;
    if (finalCatalogConfig != null &&
        await _canApplyRemoteWorkshopCatalogConfiguration()) {
      _isApplyingRemoteData = true;
      try {
        await _db.importWorkshopCatalogConfiguration(finalCatalogConfig);
      } finally {
        _isApplyingRemoteData = false;
      }
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
    if (catalogConfigurationChanged && data.isEmpty) {
      _onDataChanged?.call();
    }

    if (full) {
      _lastFullDownloadHadBusinessRows = shouldCompleteFullBootstrap(
        downloadedBusinessRows: downloadedBusinessRows,
      );
    }

    if (newestUpdate != null && (!full || downloadedBusinessRows > 0)) {
      await _saveLastSyncAt(newestUpdate!);
    }

    lastDownloadSummary = downloadedRows == 0
        ? 'لا توجد تغييرات جديدة في Supabase.'
        : full && downloadedBusinessRows == 0
        ? 'تم تنزيل إعدادات الورشة فقط؛ لا توجد بيانات أعمال في Supabase بعد.'
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
    if (storedCode.isEmpty && isApplicationAdminEmail(user.email)) {
      throw Exception(
        'مدير التطبيق لا يملك ورشة محددة. اختر ورشة من لوحة الإدارة أولاً.',
      );
    }
    final code = storedCode.isNotEmpty ? storedCode : user.id;
    if (_workshopUuid != null && _workshopCode == code) return;

    final selectedWorkshopUuid =
        (prefs.getString('selected_supabase_workshop_id') ?? '').trim();
    final codeScopedUuid = code.isEmpty
        ? ''
        : (prefs.getString('supabase_workshop_uuid_$code') ?? '').trim();
    final legacyCachedUuid = (prefs.getString('cached_workshop_uuid') ?? '')
        .trim();
    final cachedUuid = selectedWorkshopUuid.isNotEmpty
        ? selectedWorkshopUuid
        : codeScopedUuid.isNotEmpty
        ? codeScopedUuid
        : legacyCachedUuid.isNotEmpty
        ? legacyCachedUuid
        : null;
    if (cachedUuid != null && cachedUuid.isNotEmpty) {
      // إذا تم التحقق من العضوية مؤخراً (أقل من 15 دقيقة) وكانت الورشة الحالية مطابقة،
      // نعتمد على الكاش المحلي دون إرسال طلب جديد لـ Supabase لتوفير الباندويث
      final lastVerified = _lastMembershipVerifiedAt;
      final isCacheValid =
          lastVerified != null &&
          DateTime.now().difference(lastVerified) < _membershipCacheValidity;

      if (isCacheValid &&
          _workshopUuid == cachedUuid &&
          _workshopCode == code) {
        return;
      }

      // A UUID cached on this device is valid only when Supabase confirms
      // that the current user is still a member of that workshop.
      Map<String, dynamic>? membership;
      var networkError = false;
      try {
        final row = await _client
            .from('workshop_members')
            .select('workshop_id')
            .eq('workshop_id', cachedUuid)
            .eq('user_id', user.id)
            .maybeSingle();
        membership = row == null ? null : Map<String, dynamic>.from(row);
      } catch (e) {
        networkError = true;
        debugPrint('Checking membership network error (offline): ');
      }
      if (membership != null || networkError) {
        _workshopUuid = cachedUuid;
        _workshopCode = code;
        _lastMembershipVerifiedAt = DateTime.now();
        await prefs.setString('cached_workshop_uuid', cachedUuid);
        unawaited(_cacheWorkshopIdentity(cachedUuid, prefs));
        _subscribeToOrderNotifications();
        return;
      }
      if (code.isNotEmpty) {
        await prefs.remove('supabase_workshop_uuid_$code');
      }
      await prefs.remove('selected_supabase_workshop_id');
      await prefs.remove('cached_workshop_uuid');
    }

    final workshopName = (prefs.getString('workshop_name') ?? code).trim();
    final workshopUuid = await _resolveWorkshopUuid(code, workshopName);
    _workshopUuid = workshopUuid;
    _workshopCode = code;
    await prefs.setString('supabase_workshop_uuid_$code', workshopUuid);
    await prefs.setString('selected_supabase_workshop_id', workshopUuid);
    await _cacheWorkshopIdentity(workshopUuid, prefs);
  }

  Future<String> _resolveWorkshopUuid(String code, String workshopName) async {
    // Prove that the workshop exists before invoking the membership RPC.
    // Older deployed versions of ensure_my_workshop created a workshop when
    // the supplied code was missing; looking it up first makes the client safe
    // even before the database migration is applied.
    Map<String, dynamic>? existing;
    try {
      final result = await _client
          .from('workshops')
          .select('id')
          .or('code.eq.$code,join_code.eq.$code')
          .maybeSingle();
      existing = result == null ? null : Map<String, dynamic>.from(result);
    } catch (_) {
      final result = await _client
          .from('workshops')
          .select('id')
          .eq('code', code)
          .maybeSingle();
      existing = result == null ? null : Map<String, dynamic>.from(result);
    }
    final existingId = existing?['id']?.toString() ?? '';
    if (existingId.isNotEmpty) {
      try {
        final result = await _client.rpc(
          'ensure_my_workshop',
          params: {
            'target_code': code,
            'target_name': workshopName.trim().isEmpty ? code : workshopName,
          },
        );
        final resolvedId = result?.toString() ?? '';
        if (resolvedId == existingId) return resolvedId;
      } catch (error) {
        print('Supabase existing-workshop membership RPC failed: $error');
      }

      final user = _client.auth.currentUser;
      if (user != null) {
        try {
          final membership = await _client
              .from('workshop_members')
              .select('workshop_id')
              .eq('workshop_id', existingId)
              .eq('user_id', user.id)
              .maybeSingle();
          if (membership == null) {
            throw Exception(
              'لم تُنشأ عضوية الورشة. طبّق ملف '
              'supabase/workshop_join_code_migration.sql في Supabase.',
            );
          }
        } catch (error) {
          throw Exception(
            'تعذر التحقق من عضوية الورشة. طبّق ملف '
            'supabase/workshop_join_code_migration.sql في Supabase: $error',
          );
        }
      }
      return existingId;
    }

    // Opening, registration and background synchronization are lookup-only.
    // A stale/incorrect code must never create an empty workshop and make the
    // user's real data appear lost. Workshops are provisioned administratively
    // outside the client application.
    throw Exception(
      'لم يتم العثور على الورشة في Supabase. تحقق من كود الورشة أو اطلب من '
      'الإدارة ربط الحساب بالورشة الموجودة.',
    );
  }

  Future<void> _cacheWorkshopIdentity(
    String workshopUuid,
    SharedPreferences prefs,
  ) async {
    try {
      Map<String, dynamic>? row;
      try {
        final result = await _client
            .from('workshops')
            .select('code,name,join_code')
            .eq('id', workshopUuid)
            .maybeSingle();
        row = result == null ? null : Map<String, dynamic>.from(result);
      } catch (_) {
        final result = await _client
            .from('workshops')
            .select('code,name')
            .eq('id', workshopUuid)
            .maybeSingle();
        row = result == null ? null : Map<String, dynamic>.from(result);
      }
      if (row == null) return;

      final internalCode = row['code']?.toString().trim() ?? '';
      final code = row['join_code']?.toString().trim().isNotEmpty == true
          ? row['join_code'].toString().trim()
          : internalCode;
      final name = row['name']?.toString().trim() ?? '';
      final cachedName = (prefs.getString('workshop_name') ?? '').trim();
      if (code.isNotEmpty) {
        await prefs.setString('workshop_code', code);
        await prefs.setString('cached_workshop_uuid', workshopUuid);
        _workshopCode = code;
        _subscribeToOrderNotifications();
      }
      if (name.isNotEmpty) {
        // A legacy fallback could have stored the workshop code in the
        // workshops.name column. Never let that overwrite the real local
        // workshop name used by document headers.
        final remoteNameIsCode =
            (code.isNotEmpty && name == code) ||
            name == 'ورشة النجارة' ||
            name == 'ورشة الألمنيوم';
        final usableName = remoteNameIsCode
            ? (cachedName.isNotEmpty && cachedName != code ? cachedName : '')
            : name;
        if (usableName.isNotEmpty && usableName != code) {
          await prefs.setString('workshop_name', usableName);
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
      final remoteUpdatedAt = await _fetchRemoteUpdatedAt(targetRows: rows);
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
    for (
      var start = 0;
      start < rowsToUpload.length;
      start += _uploadBatchSize
    ) {
      final end = min(start + _uploadBatchSize, rowsToUpload.length);
      final batch = rowsToUpload.sublist(start, end);
      Object? lastError;
      for (var attempt = 0; attempt < _uploadBatchRetryCount; attempt++) {
        try {
          await _client
              .from('workshop_sync_rows')
              .upsert(batch, onConflict: 'workshop_id,table_name,row_id');
          lastError = null;
          break;
        } catch (error) {
          lastError = error;
          // Upsert is idempotent for this unique key. A short backoff makes
          // transient PostgREST/PostgreSQL statement timeouts recoverable
          // without duplicating business rows.
          if (attempt + 1 < _uploadBatchRetryCount) {
            await Future<void>.delayed(
              Duration(milliseconds: 400 * (attempt + 1)),
            );
          }
        }
      }
      if (lastError != null) {
        Error.throwWithStackTrace(lastError, StackTrace.current);
      }
    }
  }

  Future<Map<String, DateTime>> _fetchRemoteUpdatedAt({
    List<Map<String, dynamic>>? targetRows,
  }) async {
    final workshopUuid = _workshopUuid;
    if (workshopUuid == null || workshopUuid.isEmpty) {
      return <String, DateTime>{};
    }

    final result = <String, DateTime>{};

    // Fast path: if specific target rows are provided (incremental upload),
    // query only those row_ids instead of scanning the entire workshop database.
    if (targetRows != null &&
        targetRows.isNotEmpty &&
        targetRows.length <= 200) {
      final targetRowIds = targetRows
          .map((r) => r['row_id']?.toString() ?? '')
          .where((id) => id.isNotEmpty)
          .toSet()
          .toList(growable: false);
      if (targetRowIds.isNotEmpty) {
        try {
          final rows = await _client
              .from('workshop_sync_rows')
              .select('table_name,row_id,updated_at')
              .eq('workshop_id', workshopUuid)
              .inFilter('row_id', targetRowIds);
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
          return result;
        } catch (error) {
          debugPrint(
            'Fast remote updated_at lookup failed; falling back to full query: $error',
          );
        }
      }
    }

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
    // Bump this key when the sync format/restore path changes. Existing
    // phones then perform one complete workshop download after updating the
    // app instead of trusting an old bootstrap marker.
    return 'supabase_workshop_full_bootstrap_v4_$code';
  }

  Future<void> _applyWorkshopProfile(Map<String, dynamic> profile) async {
    final prefs = await SharedPreferences.getInstance();
    final codeForShortcuts =
        (_workshopCode ?? prefs.getString('workshop_code') ?? '').trim();
    final shortcuts = profile['workshop_shortcuts'];
    if (shortcuts is Map &&
        prefs.getString('pending_workshop_shortcuts_$codeForShortcuts') ==
            null) {
      for (final command in ShortcutBindings.commands.keys) {
        final value = shortcuts[command];
        if (value is String && value.isNotEmpty) {
          await prefs.setString('shortcut_$command', value);
        } else {
          await prefs.remove('shortcut_$command');
        }
      }
      await prefs.remove('shortcut_drawing_mode');
      await ShortcutBindings.instance.reload();
    }

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
    final rawActiveCodes = systems['active_profile_codes'];
    final rawActiveNames = systems['active_profile_names'];

    if (rawActiveProfiles is! List &&
        rawActiveCodes is! List &&
        rawActiveNames is! List) {
      return;
    }

    final activeIds = (rawActiveProfiles is List)
        ? rawActiveProfiles
              .map(
                (value) => value is num
                    ? value.toInt()
                    : int.tryParse(value.toString()),
              )
              .whereType<int>()
              .toSet()
        : <int>{};

    final activeCodes = (rawActiveCodes is List)
        ? rawActiveCodes
              .map((value) => value?.toString().trim() ?? '')
              .where((c) => c.isNotEmpty)
              .toSet()
        : <String>{};

    final activeNames = (rawActiveNames is List)
        ? rawActiveNames
              .map((value) => value?.toString().trim().toLowerCase() ?? '')
              .where((n) => n.isNotEmpty)
              .toSet()
        : <String>{};

    final dbInstance = await _db.db;
    if (dbInstance == null) return;

    // Replace the complete selection, so a system removed by the manager is
    // also disabled on every worker device.
    // Readers must see the old or the complete new selection, never the
    // intermediate all-disabled state (also survives process termination).
    await dbInstance.transaction((txn) async {
      await txn.update('Profile', {'is_active': 0});
      await txn.update('Series', {'is_active': 0});

      final allProfiles = await txn.query(
        'Profile',
        columns: ['id', 'code', 'name'],
      );
      final matchedProfileIds = <int>{};

      for (final p in allProfiles) {
        final pId = p['id'] is int
            ? p['id'] as int
            : int.tryParse(p['id'].toString());
        final pCode = (p['code'] ?? '').toString().trim();
        final pName = (p['name'] ?? '').toString().trim().toLowerCase();

        bool isMatch = false;
        if (pId != null && activeIds.contains(pId)) isMatch = true;
        if (pCode.isNotEmpty && activeCodes.contains(pCode)) isMatch = true;
        if (pName.isNotEmpty && activeNames.contains(pName)) isMatch = true;

        if (isMatch && pId != null) {
          matchedProfileIds.add(pId);
          await txn.update(
            'Profile',
            {'is_active': 1},
            where: 'id = ?',
            whereArgs: [pId],
          );
          await txn.update(
            'Series',
            {'is_active': 1},
            where: 'profile_id = ? OR id = ?',
            whereArgs: [pId, pId],
          );
        }
      }

      // Also activate any profile whose id was explicitly sent even if not matched in query
      for (final id in activeIds) {
        if (!matchedProfileIds.contains(id)) {
          await txn.update(
            'Profile',
            {'is_active': 1},
            where: 'id = ?',
            whereArgs: [id],
          );
          await txn.update(
            'Series',
            {'is_active': 1},
            where: 'profile_id = ? OR id = ?',
            whereArgs: [id, id],
          );
        }
      }

      // Activate series by name matching
      for (final name in activeNames) {
        await txn.update(
          'Series',
          {'is_active': 1},
          where: 'LOWER(TRIM(name)) = ?',
          whereArgs: [name],
        );
      }
    });
    _onDataChanged?.call();
    CloudSyncService().notifyChange();
    CloudSyncService().notifyCatalogChange();
  }

  Future<bool> _needsFullBootstrapDownload() async {
    final key = _bootstrapKey();
    if (key == null) return false;
    final prefs = await SharedPreferences.getInstance();
    final bootstrapComplete = prefs.getBool(key) ?? false;
    final syncCursor = await _readLastSyncAt();
    return shouldDownloadFullOnStartup(
      bootstrapComplete: bootstrapComplete,
      hasSyncCursor: syncCursor != null && syncCursor.trim().isNotEmpty,
    );
  }

  Future<void> _markFullBootstrapComplete() async {
    final key = _bootstrapKey();
    if (key == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, true);
  }

  Future<void> _seedLegacyLocalDataOnce() async {
    final workshopUuid = _workshopUuid;
    if (workshopUuid == null || workshopUuid.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final key = 'supabase_legacy_seed_v1_$workshopUuid';
    if (prefs.getBool(key) ?? false) return;

    final role = (prefs.getString('user_role') ?? '').trim().toLowerCase();
    if (!{'owner', 'manager', 'co_manager', 'admin'}.contains(role)) {
      await prefs.setBool(key, true);
      return;
    }

    final data = await _db.exportWorkshopData();
    final localRows = SqlDatabase.workshopTables.fold<int>(
      0,
      (total, table) => total + _countRows(data, table),
    );
    if (localRows > 0) {
      // This migration runs once on an existing manager device. It uploads
      // only rows missing remotely, preserving newer cloud copies.
      await uploadLocalWorkshopDataMerge();
    }
    await prefs.setBool(key, true);
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
