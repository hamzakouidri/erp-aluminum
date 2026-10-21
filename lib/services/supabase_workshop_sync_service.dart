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
import 'package:database_data/services/notification_texts.dart';
import 'package:database_data/services/app_admin_status_service.dart';
import 'package:database_data/services/system_publication_service.dart';
import 'package:database_data/services/supabase_account_service.dart';

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

/// What a full download does with the local workshop rows first.
enum FullDownloadPlan {
  /// The local rows are this workshop's: the ones Supabase lacks are
  /// uploaded, then the download is merged over them.
  uploadLocalThenMerge,

  /// The local rows belong to another workshop opened earlier on this
  /// device: they are cleared (after the file copy), then the download is
  /// merged into the empty tables.
  clearOtherWorkshopThenMerge,
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

  /// [localDataOwner] is the workshop whose rows the local tables hold
  /// (empty on devices that predate the marker: their rows are taken as the
  /// current workshop's, which the workshop-change check at sign-in already
  /// guarantees).
  @visibleForTesting
  static FullDownloadPlan planFullDownload({
    required String localDataOwner,
    required String workshopUuid,
  }) {
    final owner = localDataOwner.trim();
    return owner.isEmpty || owner == workshopUuid
        ? FullDownloadPlan.uploadLocalThenMerge
        : FullDownloadPlan.clearOtherWorkshopThenMerge;
  }

  /// A local row is uploaded before a full download when Supabase does not
  /// hold it. A row Supabase holds as deleted stays deleted, unless the
  /// manager kept it against that deletion ([reviveRows]).
  @visibleForTesting
  static bool shouldUploadMissingRow({
    required String key,
    required Set<String> remoteLive,
    required Set<String> remoteDeleted,
    Set<String> reviveRows = const {},
  }) {
    if (remoteLive.contains(key)) return false;
    return !remoteDeleted.contains(key) || reviveRows.contains(key);
  }

  /// The local rows Supabase holds as deleted: after a device restored its
  /// database from a file, these rows exist here but every other device
  /// treats them as deleted.
  @visibleForTesting
  static Set<String> localRowsDeletedOnServer({
    required Iterable<String> localKeys,
    required Set<String> remoteDeleted,
  }) {
    return localKeys.where(remoteDeleted.contains).toSet();
  }

  /// A live row downloaded from Supabase replaces a local deletion of the
  /// same row only when Supabase stored it after that deletion. An unknown
  /// time keeps the deletion.
  @visibleForTesting
  static bool liveRowSupersedesDeletion({
    required String liveUpdatedAt,
    required String deletedAt,
  }) {
    final live = DateTime.tryParse(liveUpdatedAt.trim());
    final deleted = DateTime.tryParse(deletedAt.trim());
    if (live == null || deleted == null) return false;
    return live.isAfter(deleted);
  }

  /// True when the deletions this device is about to send ([deleted], per
  /// table) would remove too many of the workshop's clients, orders or
  /// treasury rows; [remaining] is what this device still holds.
  @visibleForTesting
  static bool deletionUploadNeedsApproval({
    required Map<String, int> deleted,
    required Map<String, int> remaining,
  }) {
    for (final table in SqlDatabaseBusinessDataGuard.guardedTables) {
      final lost = deleted[table] ?? 0;
      if (SqlDatabaseBusinessDataGuard.losesTooMany(
        localRows: (remaining[table] ?? 0) + lost,
        lostRows: lost,
      )) {
        return true;
      }
    }
    return false;
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

  Timer? _pricePushTimer;
  int _pendingPricePushRows = 0;

  static const Set<String> priceTables = {
    'GlassColorPrices',
    'ShutterColorPrices',
    'ShutterSqmPrices',
    'ShutterBoxLimits',
    'CaissonTunnelPrices',
    'SeriesColorPrices',
    'SectionColorPrices',
    'AccessoryColorPrices',
    'WorkshopPriceOverrides',
  };

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
    // The download cursor is not moved here: jumping it to this device's
    // clock skipped every row other devices uploaded since the last
    // download. Reading this device's own rows back only re-applies
    // identical data.

    lastUploadSummary =
        'تم دمج ${rows.length} سجل بأمان في Supabase: '
        '${_countRows(data, 'Client')} زبون، '
        '${_countRows(data, 'Commandes')} طلبية، '
        '${_countRows(data, 'Commandes_details')} تفاصيل.';
  }

  /// Uploads the local rows Supabase does not hold, without touching the
  /// rows it already has. A row the workshop deleted on another device is not
  /// uploaded again, unless its key is in [reviveRows] (`tablerow_id`):
  /// the manager kept it against those deletions.
  Future<void> uploadLocalWorkshopDataMerge({
    Set<String> reviveRows = const {},
  }) async {
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

    final remote = await _fetchRemoteRowKeys(workshopUuid);
    final missingRows = rows
        .where((row) {
          final table = row['table_name']?.toString() ?? '';
          final rowId = row['row_id']?.toString() ?? '';
          final key = _rowKey(table, rowId);
          return table.isNotEmpty &&
              rowId.isNotEmpty &&
              shouldUploadMissingRow(
                key: key,
                remoteLive: remote.live,
                remoteDeleted: remote.deleted,
                reviveRows: reviveRows,
              );
        })
        .toList(growable: false);

    if (missingRows.isEmpty) {
      lastUploadSummary =
          'لا توجد سجلات محلية ناقصة في Supabase؛ لم يتم رفع أي نسخة قديمة فوق السيرفر.';
      return;
    }

    // A kept row must be newer than the deletion Supabase holds, or the
    // keep-newer trigger skips it.
    if (reviveRows.isNotEmpty) {
      final now = DateTime.now().toUtc().toIso8601String();
      for (final row in missingRows) {
        final key = _rowKey(
          row['table_name']?.toString() ?? '',
          row['row_id']?.toString() ?? '',
        );
        if (reviveRows.contains(key)) row['updated_at'] = now;
      }
    }
    await _upsertRows(missingRows);
    // Only the changes of rows uploaded here are done; an edit of a row the
    // server already holds still waits for the normal upload.
    final uploadedKeys = {
      for (final row in missingRows)
        _rowKey(
          row['table_name']?.toString() ?? '',
          row['row_id']?.toString() ?? '',
        ),
    };
    await _acknowledgeSyncedChanges(
      PendingCloudChanges(
        data: const {},
        acknowledgements: pendingBeforeUpload.acknowledgements
            .where((ack) => uploadedKeys.contains(_rowKey(ack.table, ack.rowId)))
            .toList(growable: false),
        changedRows: 0,
        deletedRows: 0,
      ),
    );

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
          // A copy that would remove many local rules is held back for the
          // manager instead of being applied.
          final result = await _db.importWorkshopCatalogConfiguration(config);
          if (result == CatalogConfigImportResult.applied) {
            debugPrint(
              '✅ تم بنجاح تنزيل وتطبيق قواعد إكسسوارات الورشة من السحابة',
            );
          }
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
    // A system the owner published or hid since the last time changes what
    // is switched on, so the workshop selection is applied again.
    if (await SystemPublicationService.instance.refresh()) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('last_applied_remote_workshop_systems');
    }
    final profile = await readWorkshopProfile();
    final systems = profile['workshop_systems'];
    if (systems is Map) {
      await _applyWorkshopSystems(Map<String, dynamic>.from(systems));
    } else {
      final dbInstance = await _db.db;
      if (dbInstance != null) {
        await SystemPublicationService.instance.applyToProfiles(dbInstance);
      }
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
      // Realtime is the fast path, but mobile networks can silently drop a
      // channel. Start the lightweight permission poll on the first session
      // too (previously it only started after background/resume).
      _startPermissionsRefreshFallback();
      // A temporary permission/RLS read failure must not abort the workshop
      // data download. The permission listener and the next sync cycle will
      // retry it; business data must continue to sync independently.
      try {
        await refreshCurrentPermissions();
      } catch (error) {
        print('Supabase permission refresh skipped during startup: $error');
      }
      // Systems the owner published or hid while this device was closed.
      unawaited(
        loadAndApplyWorkshopSystems().catchError((Object error) {
          print('Workshop systems not refreshed during startup: $error');
        }),
      );
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

    // Other account consumers must not keep the previous two-minute account
    // snapshot after a live role/permission change.
    SupabaseAccountService().invalidateCurrentAccountCache();

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

  /// Sends one push to the other managers after a burst of price edits made
  /// on this device (the price screens save cell by cell).
  void _schedulePricePush(int changedRows) {
    if (changedRows <= 0) return;
    _pendingPricePushRows += changedRows;
    _pricePushTimer?.cancel();
    _pricePushTimer = Timer(const Duration(seconds: 4), () {
      final count = _pendingPricePushRows;
      _pendingPricePushRows = 0;
      _pricePushTimer = null;
      unawaited(_sendPricePush(count));
    });
  }

  Future<void> _sendPricePush(int count) async {
    try {
      await WorkerPushNotificationService.instance.sendManagerEvent(
        eventType: 'prices',
        data: {'count': count.toString()},
      );
    } catch (error) {
      // A worker without manager rights is refused by the function, and a
      // workshop without managers has no recipients; both are expected.
      debugPrint('Price push skipped: $error');
    }
  }

  Future<void> _showIncomingPriceNotification(int count) async {
    if (count <= 0 || _isInBackground) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final role = prefs.getString('user_role') ?? 'worker';
      if (!const {'owner', 'manager', 'co_manager', 'admin'}.contains(role)) {
        return;
      }
      final enabled = await WorkerPushNotificationService.instance
          .loadPreferences(const ['prices']);
      if (enabled['prices'] == false) return;
      final text = NotificationTexts.prices(
        count,
        await AppSettingsProvider.loadSavedLanguage(),
      );
      await OrderNotificationService().showAssignmentNotification(
        title: text.title,
        body: text.body,
        data: const {'type': 'prices'},
      );
    } catch (error) {
      debugPrint('Price notification skipped: $error');
    }
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

    final saved = await _client.rpc(
      'update_workshop_member_permissions',
      params: {
        'target_code': code,
        'member_email': cleanEmail,
        'member_role': _normalizeSupabaseRole(role),
        'member_permissions': permissions,
        'member_blocked': _permissionTruthy(permissions['isBlocked']),
      },
    );
    if (saved != true) {
      throw StateError('لم يؤكد Supabase حفظ صلاحيات العامل.');
    }
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

  Future<void> rejectPendingMemberByEmail({required String email}) async {
    final cleanEmail = email.trim().toLowerCase();
    if (cleanEmail.isEmpty) return;
    await updateMemberPermissionsByEmail(
      email: cleanEmail,
      role: 'worker',
      permissions: const <String, dynamic>{
        'is_pending': false,
        'is_approved': false,
        'is_rejected': true,
        'isBlocked': true,
        'view_clients': false,
        'view_orders': false,
        'view_client_details': false,
        'view_order_details': false,
        'view_my_tasks': false,
        'view_my_accreditations': false,
        'access_workshop': false,
        'access_store': false,
      },
    );
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
    var pending = await _db.exportPendingCloudChanges(
      allowedTables: SqlDatabase.workshopTables.toSet(),
    );
    if (pending.isEmpty) return;
    pending = await _withoutUnapprovedMassDeletions(pending);
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
    // Any price written on this device (price screen, purchase cost update,
    // accepted publication...) reaches the other managers as a push.
    _schedulePricePush(
      rows
          .where((row) => priceTables.contains(row['table_name']?.toString()))
          .length,
    );

    lastUploadSummary =
        'تم رفع ${rows.length} تغيير سريع إلى Supabase '
        '(${pending.changedRows} تعديل، ${pending.deletedRows} حذف).';
  }

  static const String _localDataOwnerKey =
      SqlDatabaseBusinessDataGuard.localDataOwnerKey;

  /// Records the open workshop as the owner of the local rows when no owner
  /// is known yet. Called before the application admin opens another
  /// workshop, so the next full download knows the local rows are not that
  /// workshop's.
  Future<void> rememberLocalDataOwnerIfUnknown() async {
    final workshopUuid = _workshopUuid;
    if (workshopUuid == null || workshopUuid.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    if ((prefs.getString(_localDataOwnerKey) ?? '').trim().isEmpty) {
      await prefs.setString(_localDataOwnerKey, workshopUuid);
    }
  }

  /// Runs before every full download. The database file is copied first.
  /// Then, when the local rows are this workshop's, the pending changes and
  /// the rows Supabase lacks are uploaded, so that the download (a merge)
  /// brings back a complete workshop. A failed upload stops nothing: the
  /// merge keeps those rows locally and the pending changes stay queued.
  Future<void> _prepareFullDownload(String workshopUuid) async {
    final backup = await _db.backupDatabaseFile(reason: 'before_full_download');
    debugPrint(
      backup == null
          ? 'Full download: no database copy could be written.'
          : 'Full download: database copied to $backup',
    );
    final prefs = await SharedPreferences.getInstance();
    final plan = planFullDownload(
      localDataOwner: prefs.getString(_localDataOwnerKey) ?? '',
      workshopUuid: workshopUuid,
    );
    if (plan == FullDownloadPlan.clearOtherWorkshopThenMerge) {
      if (backup == null) {
        throw Exception(
          'تعذر أخذ نسخة من قاعدة البيانات؛ لم يتم مسح بيانات الورشة السابقة.',
        );
      }
      await SqlDatabase.clearWorkshopDataOnly();
    } else {
      try {
        await uploadPendingChanges();
      } catch (error) {
        debugPrint('Full download: pending upload deferred: $error');
      }
      final role = (prefs.getString('user_role') ?? '').trim().toLowerCase();
      if ({'owner', 'manager', 'co_manager', 'admin'}.contains(role)) {
        try {
          await uploadLocalWorkshopDataMerge();
        } catch (error) {
          debugPrint('Full download: missing rows not uploaded: $error');
        }
      }
    }
    await prefs.setString(_localDataOwnerKey, workshopUuid);
  }

  /// Per table, the rows of this device that Supabase holds as deleted.
  Future<Map<String, int>> countLocalRowsDeletedOnServer() async {
    final keys = await _readLocalRowsDeletedOnServer();
    final counts = <String, int>{};
    for (final key in keys) {
      final table = key.substring(0, key.indexOf('\x1f'));
      counts[table] = (counts[table] ?? 0) + 1;
    }
    return counts;
  }

  /// The manager confirmed that this device's rows are the workshop's copy:
  /// the rows Supabase holds as deleted are uploaded again, newer than their
  /// deletion, so every device gets them back. The database file is copied
  /// first. Returns the number of rows revived.
  Future<int> reviveLocalRowsDeletedOnServer() async {
    await _ensureReady();
    final prefs = await SharedPreferences.getInstance();
    final role = (prefs.getString('user_role') ?? '').trim().toLowerCase();
    if (!{'owner', 'manager', 'co_manager', 'admin'}.contains(role)) {
      throw Exception('هذه العملية متاحة لمدير الورشة فقط.');
    }
    final keys = await _readLocalRowsDeletedOnServer();
    if (keys.isEmpty) return 0;
    final backup = await _db.backupDatabaseFile(reason: 'before_revive_rows');
    if (backup == null) {
      throw Exception('تعذر أخذ نسخة من قاعدة البيانات؛ لم يُرفع أي سجل.');
    }
    await uploadLocalWorkshopDataMerge(reviveRows: keys);
    return keys.length;
  }

  Future<Set<String>> _readLocalRowsDeletedOnServer() async {
    await _ensureReady();
    final data = await _db.exportWorkshopData();
    final localKeys = <String>[];
    for (final entry in data.entries) {
      final rows = entry.value;
      if (!_isWorkshopTable(entry.key) || rows is! List) continue;
      for (final row in rows) {
        final rowId = row is Map ? row['id']?.toString() ?? '' : '';
        if (rowId.isNotEmpty) localKeys.add(_rowKey(entry.key, rowId));
      }
    }
    if (localKeys.isEmpty) return const {};
    final remote = await _fetchRemoteRowKeys(_workshopUuid!);
    return localRowsDeletedOnServer(
      localKeys: localKeys,
      remoteDeleted: remote.deleted,
    );
  }

  /// The manager kept the local clients/orders/treasury rows against the
  /// held-back remote deletions: they are uploaded again over them.
  Future<void> keepLocalBusinessRows() async {
    final keys = await _db.discardPendingBusinessDataLoss();
    if (keys.isEmpty) return;
    await uploadLocalWorkshopDataMerge(reviveRows: keys);
  }

  static const String _heldDeletionUploadKey = 'held_deletion_upload_summary';
  static const String _deletionUploadApprovedUntilKey =
      'deletion_upload_approved_until';

  /// Bumped when this device holds back its own deletions for the manager.
  static final ValueNotifier<int> deletionUploadSignal = ValueNotifier<int>(0);

  /// Removes the deletions from [pending] when they would remove too many
  /// clients, orders or treasury rows and no manager approved them. They stay
  /// queued (not acknowledged) and the manager is asked.
  Future<PendingCloudChanges> _withoutUnapprovedMassDeletions(
    PendingCloudChanges pending,
  ) async {
    final tombstones = pending.data['SyncTombstones'];
    if (tombstones is! List || tombstones.isEmpty) return pending;
    final deleted = <String, int>{};
    final deletionKeys = <String>{};
    for (final raw in tombstones.whereType<Map>()) {
      final table = raw['table_name']?.toString() ?? '';
      final rowId = raw['row_id']?.toString() ?? '';
      deleted[table] = (deleted[table] ?? 0) + 1;
      deletionKeys.add(_rowKey(table, rowId));
    }
    final remaining = await _db.countGuardedBusinessRows();
    final prefs = await SharedPreferences.getInstance();
    if (!deletionUploadNeedsApproval(deleted: deleted, remaining: remaining)) {
      await prefs.remove(_heldDeletionUploadKey);
      return pending;
    }
    final approvedUntil = DateTime.tryParse(
      prefs.getString(_deletionUploadApprovedUntilKey) ?? '',
    );
    if (approvedUntil != null && approvedUntil.isAfter(DateTime.now())) {
      return pending;
    }

    await prefs.setString(
      _heldDeletionUploadKey,
      jsonEncode({'deleted': deleted, 'remaining': remaining}),
    );
    deletionUploadSignal.value++;
    final data = Map<String, dynamic>.from(pending.data)
      ..remove('SyncTombstones');
    return PendingCloudChanges(
      data: data,
      acknowledgements: pending.acknowledgements
          .where((ack) => !deletionKeys.contains(_rowKey(ack.table, ack.rowId)))
          .toList(growable: false),
      changedRows: pending.changedRows,
      deletedRows: 0,
    );
  }

  /// Deletions of this device waiting for the manager: per table, how many
  /// would be sent and how many rows the device still holds. Null when none.
  Future<({Map<String, int> deleted, Map<String, int> remaining})?>
  readHeldDeletionUpload() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_heldDeletionUploadKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw) as Map;
      Map<String, int> counts(Object? value) => {
        if (value is Map)
          for (final entry in value.entries)
            entry.key.toString(): (entry.value as num?)?.toInt() ?? 0,
      };
      return (
        deleted: counts(decoded['deleted']),
        remaining: counts(decoded['remaining']),
      );
    } catch (_) {
      return null;
    }
  }

  /// The manager confirmed the deletions: they are sent now (Supabase is
  /// told to accept a large deletion from this workshop for ten minutes).
  Future<void> approveHeldDeletionUpload() async {
    await _ensureReady();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _deletionUploadApprovedUntilKey,
      DateTime.now().add(const Duration(minutes: 10)).toIso8601String(),
    );
    await prefs.remove(_heldDeletionUploadKey);
    try {
      await _client.rpc(
        'allow_workshop_mass_deletion',
        params: {'p_workshop_id': _workshopUuid, 'p_minutes': 10},
      );
    } catch (error) {
      // The server guard may not be installed yet; the deletions still go.
      debugPrint('Mass deletion allowance not set on Supabase: $error');
    }
    await uploadPendingChanges();
  }

  /// The manager refused the deletions: they are dropped without being sent
  /// and the deleted rows are brought back from Supabase.
  Future<void> cancelHeldDeletionUpload() async {
    await _db.dropUnsentDeletions();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_heldDeletionUploadKey);
    await downloadWorkshopData(full: true);
  }

  Future<void> _downloadChanges({required bool full}) async {
    await _ensureReady();
    final workshopUuid = _workshopUuid!;
    if (full) await _prepareFullDownload(workshopUuid);
    final since = full ? null : await _readLastSyncAt();
    final serverCursor = full ? null : await _readServerCursor();
    // Taken before reading anything, so rows written during this download
    // are fetched again by the next incremental pass.
    final serverHighWater = full || serverCursor == null
        ? await _fetchServerHighWater(workshopUuid)
        : null;
    String? nextServerCursor;
    Map<String, String>? nextAppliedRows;
    final data = <String, dynamic>{};
    final tombstones = <Map<String, dynamic>>[];
    // When Supabase stored each downloaded live row, per table and row id.
    final liveRowTimes = <String, Map<String, String>>{};
    Map<String, dynamic>? catalogConfiguration;
    Map<String, dynamic>? pendingProfilePayload;
    var profileChanged = false;
    var catalogConfigurationChanged = false;
    var start = 0;
    var downloadedRows = 0;
    var downloadedBusinessRows = 0;
    var incomingPriceRows = 0;
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

      final fromOtherDevice =
          (row['device_id']?.toString() ?? '') != _deviceId;
      if (!full && fromOtherDevice && priceTables.contains(table)) {
        incomingPriceRows++;
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
          pendingProfilePayload = Map<String, dynamic>.from(payload);
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
        if (updatedAt != null) {
          liveRowTimes.putIfAbsent(table, () => {})[rowId] = updatedAt;
        }
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
                // Rows uploaded together share updated_at; without a unique
                // tie-breaker, offset pages can skip or repeat them.
                .order('row_id', ascending: true)
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
                      .order('row_id', ascending: true)
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
      var usedServerCursor = false;
      if (serverCursor != null && _serverCursorSupported != false) {
        try {
          final applied = await _readRecentlyAppliedRows();
          final from = withServerCursorOverlap(serverCursor);
          var newest = serverCursor;
          while (true) {
            final rows = await _client
                .from('workshop_sync_rows')
                .select(
                  'table_name,row_id,payload,updated_at,deleted_at,device_id,'
                  'revision,server_updated_at',
                )
                .eq('workshop_id', workshopUuid)
                .gte('server_updated_at', from)
                .order('server_updated_at', ascending: true)
                .order('table_name', ascending: true)
                .order('row_id', ascending: true)
                .range(start, start + incrementalBatchSize - 1);
            if (rows.isEmpty) break;

            for (final rawRow in rows) {
              final row = Map<String, dynamic>.from(rawRow as Map);
              final serverTime = row['server_updated_at']?.toString() ?? '';
              // The overlap window returns rows already applied by the
              // previous pass; applying them again would repeat order
              // notifications.
              final marker = _appliedRowMarker(row);
              if (applied.containsKey(marker)) continue;
              applied[marker] = serverTime;
              processRow(row);
              if (isLaterSyncTimestamp(serverTime, newest)) newest = serverTime;
            }

            if (rows.length < incrementalBatchSize) break;
            start += incrementalBatchSize;
          }
          nextServerCursor = newest;
          nextAppliedRows = applied;
          usedServerCursor = true;
        } on PostgrestException catch (error) {
          if (!_isMissingServerCursorColumn(error)) rethrow;
          _serverCursorSupported = false;
          start = 0;
        }
      }

      if (!usedServerCursor) {
        while (true) {
          final rows = await _client
              .from('workshop_sync_rows')
              .select(
                'table_name,row_id,payload,updated_at,deleted_at,device_id',
              )
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

    // Deletions that would remove many local clients, orders or treasury
    // rows wait for the manager instead of being applied.
    final allowedTombstones = await _db.holdBackLargeBusinessDeletions(
      tombstones,
    );
    if (allowedTombstones.isNotEmpty) {
      data['SyncTombstones'] = allowedTombstones;
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

    // A full download is a merge, never a replacement: Supabase may hold
    // only the rows this device uploaded so far. A local row is removed only
    // by a deletion Supabase recorded, never because Supabase lacks it, and
    // the pending changes stay queued until they are uploaded.
    if (data.isNotEmpty) {
      _isApplyingRemoteData = true;
      try {
        // A row restored on another device after its deletion must come back
        // here too; otherwise the old local deletion hides it for ever.
        await _db.dropDeletionsSupersededByLiveRows(
          liveRowTimes,
          supersedes: (liveUpdatedAt, deletedAt) => liveRowSupersedesDeletion(
            liveUpdatedAt: liveUpdatedAt,
            deletedAt: deletedAt,
          ),
        );
        await _db.importWorkshopData(data);
      } finally {
        _isApplyingRemoteData = false;
      }
      _onDataChanged?.call();
    }

    final profilePayload = pendingProfilePayload;
    if (profilePayload != null) {
      await _applyWorkshopProfile(profilePayload);
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
    final serverCursorToSave = nextServerCursor ?? serverHighWater;
    if (serverCursorToSave != null && (!full || downloadedBusinessRows > 0)) {
      await _saveServerCursor(
        serverCursorToSave,
        appliedRows: nextAppliedRows ?? const {},
      );
    }


    if (incomingPriceRows > 0) {
      unawaited(_showIncomingPriceNotification(incomingPriceRows));
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

  Future<({Set<String> live, Set<String> deleted})> _fetchRemoteRowKeys(
    String workshopUuid,
  ) async {
    final keys = <String>{};
    final deletedKeys = <String>{};
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
        if (table.isEmpty || rowId.isEmpty) continue;
        (deletedAt.isEmpty ? keys : deletedKeys).add(_rowKey(table, rowId));
      }
      if (rows.length < _downloadPageSize) break;
      start += _downloadPageSize;
    }
    return (live: keys, deleted: deletedKeys);
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
            // Who deleted the row and from where. Supabase keeps the last
            // copy of the row and stores this beside it
            // (supabase/sync_deletion_guard.sql).
            'payload': {
              'id': rowId,
              'deleted_by': tombstone['deleted_by']?.toString() ?? userId,
              'delete_source': tombstone['delete_source']?.toString() ?? '',
            },
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

  // ── Server-time download cursor (supabase/sync_server_cursor.sql) ──
  //
  // `updated_at` is the device's modification time: a row edited offline or
  // on a device with a late clock is uploaded "in the past" and an
  // `updated_at > cursor` query never returns it. The cursor below uses the
  // database time of the write instead. Until the migration is applied the
  // column is missing and the legacy cursor keeps working.

  /// Rows committed slightly out of order around the cursor are fetched again
  /// within this window and skipped through [_readRecentlyAppliedRows].
  static const Duration _serverCursorOverlap = Duration(minutes: 2);
  bool? _serverCursorSupported;

  String? _serverCursorKey() {
    final code = _workshopCode;
    return code == null || code.isEmpty
        ? null
        : 'supabase_workshop_server_cursor_$code';
  }

  String? _appliedRowsKey() {
    final code = _workshopCode;
    return code == null || code.isEmpty
        ? null
        : 'supabase_workshop_applied_rows_$code';
  }

  Future<String?> _readServerCursor() async {
    final key = _serverCursorKey();
    if (key == null) return null;
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(key);
  }

  Future<Map<String, String>> _readRecentlyAppliedRows() async {
    final key = _appliedRowsKey();
    if (key == null) return <String, String>{};
    final prefs = await SharedPreferences.getInstance();
    try {
      final decoded = jsonDecode(prefs.getString(key) ?? '{}');
      if (decoded is Map) {
        return decoded.map(
          (marker, time) => MapEntry(marker.toString(), time.toString()),
        );
      }
    } catch (_) {
      // A damaged list only costs one repeated application of a few rows.
    }
    return <String, String>{};
  }

  Future<void> _saveServerCursor(
    String cursor, {
    required Map<String, String> appliedRows,
  }) async {
    final cursorKey = _serverCursorKey();
    final appliedKey = _appliedRowsKey();
    if (cursorKey == null || appliedKey == null) return;
    final from = withServerCursorOverlap(cursor);
    final kept = <String, String>{
      for (final entry in appliedRows.entries)
        if (!isLaterSyncTimestamp(from, entry.value)) entry.key: entry.value,
    };
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(appliedKey, jsonEncode(kept));
    await prefs.setString(cursorKey, cursor);
  }

  /// Latest server write time of the workshop, or null when the server has
  /// no `server_updated_at` column yet.
  Future<String?> _fetchServerHighWater(String workshopUuid) async {
    if (_serverCursorSupported == false) return null;
    try {
      final row = await _client
          .from('workshop_sync_rows')
          .select('server_updated_at')
          .eq('workshop_id', workshopUuid)
          .order('server_updated_at', ascending: false)
          .limit(1)
          .maybeSingle();
      _serverCursorSupported = true;
      // An empty workshop has no server time yet; never fall back to this
      // device's clock, which may be ahead of the server.
      return row?['server_updated_at']?.toString();
    } on PostgrestException catch (error) {
      if (_isMissingServerCursorColumn(error)) {
        _serverCursorSupported = false;
        return null;
      }
      rethrow;
    }
  }

  static bool _isMissingServerCursorColumn(PostgrestException error) =>
      error.code == '42703' || error.message.contains('server_updated_at');

  static String _appliedRowMarker(Map<String, dynamic> row) =>
      '${row['table_name']}\x1f${row['row_id']}\x1f${row['revision']}'
      '\x1f${row['deleted_at'] ?? ''}';

  @visibleForTesting
  static String withServerCursorOverlap(String cursor) {
    final parsed = DateTime.tryParse(cursor);
    if (parsed == null) return cursor;
    return parsed.toUtc().subtract(_serverCursorOverlap).toIso8601String();
  }

  /// Whether [candidate] is strictly after [reference]; unparsable values
  /// never win.
  @visibleForTesting
  static bool isLaterSyncTimestamp(String candidate, String reference) {
    final a = DateTime.tryParse(candidate);
    final b = DateTime.tryParse(reference);
    if (a == null) return false;
    if (b == null) return true;
    return a.isAfter(b);
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
    final systemsJson = jsonEncode(systems);
    final lastApplied = prefs.getString('last_applied_remote_workshop_systems');
    if (lastApplied == systemsJson) {
      return;
    }

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
      final dbInstance = await _db.db;
      if (dbInstance != null) {
        await SystemPublicationService.instance.applyToProfiles(dbInstance);
      }
      await prefs.setString('last_applied_remote_workshop_systems', systemsJson);
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
    final unpublished = await SystemPublicationService.instance
        .hiddenForCurrentUser();

    // Replace the complete selection, so a system removed by the manager is
    // also disabled on every worker device.
    // Readers must see the old or the complete new selection, never the
    // intermediate all-disabled state (also survives process termination).
    await dbInstance.transaction((txn) async {
      await txn.update('Profile', {'is_active': 0});
      await txn.update('Series', {'is_active': 0});

      final profileCols = await txn.rawQuery('PRAGMA table_info(Profile)');
      final profileColNames = profileCols.map((c) => c['name'].toString().toLowerCase()).toSet();
      final hasCodeCol = profileColNames.contains('code');

      final allProfiles = await txn.query(
        'Profile',
        columns: hasCodeCol ? ['id', 'code', 'name'] : ['id', 'name'],
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

      // Systems the owner has not published stay off for this user.
      await SystemPublicationService.applyHiddenProfiles(txn, unpublished);
    });
    await prefs.setString('last_applied_remote_workshop_systems', systemsJson);
    _onDataChanged?.call();
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
