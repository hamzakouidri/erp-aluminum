import 'dart:async';
import 'dart:math';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart' show FirebaseException;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:database_data/sql_database.dart';
import 'package:database_data/services/supabase_workshop_sync_service.dart';

import 'package:shared_preferences/shared_preferences.dart';

enum CloudSyncFeedbackType {
  syncReady,
  uploadStarted,
  uploadSucceeded,
  uploadFailed,
  uploadSkipped,
  downloadStarted,
  downloadSucceeded,
  downloadFailed,
}

class CloudSyncFeedback {
  const CloudSyncFeedback({
    required this.type,
    required this.message,
    this.details = '',
  });

  final CloudSyncFeedbackType type;
  final String message;
  final String details;
}

class NoWorkshopBackupException implements Exception {
  final String message;

  const NoWorkshopBackupException([
    this.message = 'لم يتم العثور على نسخة احتياطية سابقة',
  ]);

  @override
  String toString() => message;
}

class _CloudChunkWrite {
  const _CloudChunkWrite({required this.docId, required this.payload});

  final String docId;
  final Map<String, dynamic> payload;
}

class CloudSyncService {
  // Singleton pattern so we only have one listener and one deviceId
  static final CloudSyncService _instance = CloudSyncService._internal();
  static const bool supabaseWorkshopDataOnly = true;
  static const int _maxChunkCharacters = 150000;
  static const int _maxUploadBatchWrites = 25;
  static const int _maxUploadBatchBytes = 3000000;
  static const int _maxFirestoreDocumentBytes = 900000;
  static const int _maxLiveEventDocumentBytes = 120000;
  static const int _liveEventListenerLimit = 8;

  // ⚠️ [توفير حصة Firebase]: يحدّ هذا الرقم أقصى عدد مستندات delta تُقرأ في
  // أي استعلام واحد (سواء المستمع اللحظي أو الفحص الدوري)، بدل قراءة كل ما
  // تراكم من مستندات (حتى لو كانت آلاف). راجع _deleteCompactedDeltaDocuments
  // للتنظيف الدائم الذي يمنع هذا التراكم من الأساس.
  static const int _deltaQueryLimit = 200;

  // نفس الفكرة لعدد النسخ الكاملة (snapshot_*) القديمة التي تُبقى كاحتياط
  // بعد نشر نسخة جديدة، قبل حذفها في الخلفية.
  static const int _keepPreviousFullSnapshots = 1;
  static const int _largeFieldInlineBytes = 180000;
  static const int _largeFieldPartCharacters = 180000;

  // Firestore sends a query result through Android's platform channel in one
  // message. Downloading every chunk in one query can exceed the Android heap
  // before Dart receives it, even though every individual chunk is small.
  static const int _chunkDownloadPageSize = 8;
  static const String _largeFieldMarkerKey = '__cloudLargeField';
  static const String _largeFieldPartKind = 'large_field_part';
  static const Duration _chunkUploadTimeout = Duration(seconds: 60);
  static const List<String> _watchedTransactionalCountTables = <String>[
    'Commandes',
    'Commandes_details',
    'Client',
    'Treasury',
  ];

  factory CloudSyncService() => _instance;

  CloudSyncService._internal();

  FirebaseFirestore get _firestore => FirebaseFirestore.instance;

  FirebaseAuth get _auth => FirebaseAuth.instance;
  final SqlDatabase _db = SqlDatabase();

  String _deviceId = '';
  Timer? _debounceTimer;
  Timer? _backupRetryTimer;
  Timer? _catalogDebounceTimer;
  Timer? _catalogRetryTimer;
  Timer? _realtimeRetryTimer;
  Timer? _realtimeHealthTimer;
  Timer? _pendingCloudChangePollTimer;
  Timer? _pendingTransactionUploadTimer;
  StreamSubscription<DocumentSnapshot>? _listener;
  StreamSubscription<DocumentSnapshot>? _catalogListener;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _deltaListener;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _statusListener;
  StreamSubscription<QuerySnapshot>? _orderStatusListener;
  StreamSubscription<QuerySnapshot>? _measurementsListener;
  StreamSubscription<QuerySnapshot>?
  _deletionsListener; // ⚡ لحدف الإسنادات فورياً على جميع الأجهزة
  StreamSubscription<QuerySnapshot>?
  _orderDeletionsListener; // ⚡ لحذف الطلبيات فورياً على جميع الأجهزة
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
  _permissionsListener; // ⚡ لتحديث صلاحيات العامل فورياً على هذا الجهاز
  int _restoreDepth = 0;
  bool _refreshQueuedAfterRestore = false;
  bool _catalogRefreshQueuedAfterRestore = false;
  bool _localSyncQueuedAfterRestore = false;
  Completer<void>? _restoreIdleCompleter;
  int _localWriteDepth = 0;
  bool _refreshQueuedAfterLocalWrite = false;
  bool _backupQueuedAfterLocalWrite = false;

  bool get _isRestoring => _restoreDepth > 0;

  bool get _isLocalWriteInProgress => _localWriteDepth > 0;
  bool _isSilentBackupRunning = false;
  bool _silentBackupQueued = false;
  bool _isCheckingCloudChanges = false;
  String? _lastHandledBackupFingerprint;
  String? _lastHandledCatalogFingerprint;
  final Set<String> _ownUploadIds = <String>{};
  final Set<String> _handledDeltaIds = <String>{};
  final Set<String> _processingDeltaIds = <String>{};
  Future<void> _deltaApplyChain = Future<void>.value();
  String? _loadedDeltaWorkshopId;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _liveEventListener;
  final Set<String> _handledLiveEventIds = <String>{};
  final Set<String> _processingLiveEventIds = <String>{};
  Future<void> _liveEventApplyChain = Future<void>.value();
  Future<void> _allocationStatusApplyChain = Future<void>.value();
  String? _loadedLiveEventWorkshopId;
  DateTime? _latestFullSnapshotCompletedAt;
  final Set<String> _latestFullCompactedDeltaIds = <String>{};
  String? _lastAnnouncedListenerWorkshopId;
  DateTime? _lastRealtimeErrorFeedbackAt;
  Future<void>? _activeBackup;
  Future<void>? _activeLiveEventUpload;
  bool _liveEventUploadQueued = false;
  Future<void>? _activeCatalogBackup;
  Future<void>? _activeRestore;
  Future<void>? _activeFullRecovery;
  bool _catalogBackupQueued = false;
  bool _hasPendingLocalCatalogChanges = false;
  int _catalogChangeGeneration = 0;
  bool _hasPendingTransactionalChanges = false;
  int _transactionChangeGeneration = 0;
  bool _isReconcilingTransactionalCounts = false;
  DateTime? _lastTransactionalCountReconcileAt;
  Map<String, dynamic> _currentPermissions = <String, dynamic>{};
  String? _lastHandledPermissionsFingerprint;

  final StreamController<String> _dbUpdateController =
      StreamController<String>.broadcast();

  Stream<String> get dbUpdateStream => _dbUpdateController.stream;
  final StreamController<CloudSyncFeedback> _syncFeedbackController =
      StreamController<CloudSyncFeedback>.broadcast();

  Stream<CloudSyncFeedback> get syncFeedbackStream =>
      _syncFeedbackController.stream;
  final StreamController<Map<String, dynamic>> _permissionsController =
      StreamController<Map<String, dynamic>>.broadcast();

  /// يبث خريطة الصلاحيات الحالية فور تغييرها في Firestore (بدون إعادة تشغيل
  /// التطبيق). الشاشات التي تعتمد على صلاحية معينة (رؤية/تعديل الزبائن،
  /// رؤية/تعديل المنتجات...) تستمع لهذا الـ Stream لتحدّث نفسها فورياً.
  Stream<Map<String, dynamic>> get permissionsStream =>
      _permissionsController.stream;

  /// آخر خريطة صلاحيات معروفة لهذا الحساب (قراءة متزامنة فورية بدون انتظار).
  Map<String, dynamic> get currentPermissions =>
      Map<String, dynamic>.unmodifiable(_currentPermissions);

  /// اختصار شائع: هل يملك الحساب الحالي صلاحية معينة؟
  bool hasPermission(String key) => _currentPermissions[key] == true;

  // Callback to refresh UI when auto-restore happens
  Function()? onDataRestored;

  String? _workshopId;

  String? get workshopId => _workshopId;
  String lastBackupUploadSummary = '';
  String lastCatalogUploadSummary = '';
  String lastRestoreSummary = 'لم يتم الاسترجاع بعد';

  String _newUploadId() {
    final randomPart = Random().nextInt(1 << 32).toRadixString(16);
    return '${DateTime.now().microsecondsSinceEpoch}_$randomPart';
  }

  void _rememberOwnUpload(String uploadId) {
    _ownUploadIds.add(uploadId);
    while (_ownUploadIds.length > 20) {
      _ownUploadIds.remove(_ownUploadIds.first);
    }
  }

  void _sendSyncFeedback(
    CloudSyncFeedbackType type,
    String message, {
    String details = '',
  }) {
    _syncFeedbackController.add(
      CloudSyncFeedback(type: type, message: message, details: details),
    );
  }

  /// يوحّد قراءة الصلاحيات من الحقلين المحتملين في مستند المستخدم:
  /// - `permissions` (Map في Firestore، الشكل الحديث)
  /// - `permissions_json` (نص JSON، الشكل القديم المتوافق مع نسخ سابقة)
  /// نص permissions_json يُقرأ فقط إذا لم يوجد Map صالح، حتى لا يُستبدل حقل
  /// حديث بقيمة قديمة متبقية بالخطأ في نفس المستند.
  Map<String, dynamic> _parsePermissions(Map<String, dynamic> userData) {
    final rawMap = userData['permissions'];
    if (rawMap is Map) {
      return rawMap.map((key, value) => MapEntry(key.toString(), value));
    }
    final rawJson = userData['permissions_json'];
    if (rawJson is String && rawJson.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(rawJson);
        if (decoded is Map) {
          return decoded.map((key, value) => MapEntry(key.toString(), value));
        }
      } catch (e) {
        print('Failed to decode permissions_json: $e');
      }
    }
    return <String, dynamic>{};
  }

  String _permissionsFingerprint(Map<String, dynamic> permissions) {
    final sortedKeys = permissions.keys.toList()..sort();
    final buffer = StringBuffer();
    for (final key in sortedKeys) {
      buffer.write('$key=${permissions[key]};');
    }
    return buffer.toString();
  }

  Future<void> _applyPermissionsUpdate(Map<String, dynamic> userData) async {
    final permissions = _parsePermissions(userData);
    final fingerprint = _permissionsFingerprint(permissions);
    if (fingerprint == _lastHandledPermissionsFingerprint) return;
    _lastHandledPermissionsFingerprint = fingerprint;
    _currentPermissions = permissions;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('permissions_json', jsonEncode(permissions));
    } catch (e) {
      print('Failed to persist updated permissions locally: $e');
    }

    _permissionsController.add(Map<String, dynamic>.unmodifiable(permissions));
    _dbUpdateController.add('permissions_updated');
  }

  /// تحميل الصلاحيات المخزّنة محلياً (من آخر مزامنة) فور بدء التطبيق، قبل أن
  /// يصل أول حدث من Firestore. يمنع هذا ظهور واجهة بلا صلاحيات للحظة قصيرة.
  Future<void> _loadCachedPermissions() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('permissions_json');
      if (raw == null || raw.trim().isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        _currentPermissions = decoded.map(
          (key, value) => MapEntry(key.toString(), value),
        );
        _lastHandledPermissionsFingerprint = _permissionsFingerprint(
          _currentPermissions,
        );
      }
    } catch (e) {
      print('Failed to load cached permissions: $e');
    }
  }

  String _describeBackupContents(Map<String, dynamic> allData) {
    final totalRows = allData.values.fold<int>(0, (total, rows) {
      return total + (rows is List ? rows.length : 0);
    });
    final nonEmptyTables = allData.values.where((rows) {
      return rows is List && rows.isNotEmpty;
    }).length;
    const keyTables = <String, String>{
      'Commandes': 'طلبات',
      'Client': 'زبائن',
      'Achats': 'مشتريات',
      'Caisses': 'صناديق',
      'Treasury': 'حركات الخزينة',
      'WorkerAllocations': 'إسنادات العمال',
      'WorkerTransactions': 'معاملات العمال',
      'WorkerAttendance': 'حضور العمال',
      'WorkerDailyJobs': 'أعمال العمال اليومية',
    };
    final importantCounts = keyTables.entries
        .map((entry) {
          final rows = allData[entry.key];
          final count = rows is List ? rows.length : 0;
          return count > 0 ? '${entry.value}: $count' : '';
        })
        .where((text) => text.isNotEmpty)
        .toList();

    final databaseSummary =
        'كل قاعدة البيانات: ${allData.length} جدول '
        '($nonEmptyTables غير فارغ) • $totalRows سجل';
    final details = importantCounts.isEmpty
        ? databaseSummary
        : '$databaseSummary\n${importantCounts.join(' • ')}';
    return '$details\nالورشة: ${_workshopId ?? 'غير محددة'}';
  }

  /// Groups a multi-step local save (such as an order plus all its lines).
  /// Cloud restore and upload wait until the complete local operation ends.
  Future<void> beginLocalWrite() async {
    if (_isRestoring) {
      await _restoreIdleCompleter?.future;
    }
    _localWriteDepth++;
    _debounceTimer?.cancel();
  }

  void endLocalWrite() {
    if (_localWriteDepth > 0) _localWriteDepth--;
    if (_localWriteDepth != 0) return;

    final shouldRefresh = _refreshQueuedAfterLocalWrite;
    final shouldBackup = _backupQueuedAfterLocalWrite;
    _refreshQueuedAfterLocalWrite = false;
    _backupQueuedAfterLocalWrite = false;

    scheduleMicrotask(() async {
      if (shouldRefresh) {
        await refreshFromCloudIfChanged();
      }
      final supabaseWorkshopSync = SupabaseWorkshopSyncService();
      if (supabaseWorkshopSync.isSignedIn) {
        if (shouldBackup || await _db.hasPendingCloudChanges()) {
          supabaseWorkshopSync.notifyLocalChange(immediate: true);
        }
        await _clearFirebaseTransactionalPendingFlag();
        return;
      }
      if (shouldBackup || await _hasPendingTransactions()) {
        _queueImmediateLiveEventUpload();
        await _silentBackup();
      }
    });
  }

  DocumentReference<Map<String, dynamic>> _catalogDocument() {
    // Product definitions (colours, profiles and shutter components) are a
    // single shared catalogue. They must not be split between workshops.
    return _firestore.collection('global_catalog').doc('latest');
  }

  Future<void> _clearFirebaseTransactionalPendingFlag() async {
    _hasPendingTransactionalChanges = false;
    try {
      final prefs = await SharedPreferences.getInstance();
      final workshopId = _workshopId ?? prefs.getString('workshop_code');
      if (workshopId != null && workshopId.isNotEmpty) {
        await prefs.setBool(_transactionPendingKey(workshopId), false);
      }
      await prefs.setBool('has_pending_transaction_changes', false);
      await prefs.setBool('is_local_dirty', false);
    } catch (error) {
      print('Could not clear legacy Firebase pending marker: $error');
    }
  }

  DocumentReference<Map<String, dynamic>> _transactionalSyncStateDocument() {
    final workshopId = _workshopId;
    if (workshopId == null || workshopId.isEmpty) {
      throw StateError('Cloud sync state requires a valid workshop.');
    }
    return _firestore
        .collection('workshops')
        .doc(workshopId)
        .collection('sync_state')
        .doc('transactional_counts');
  }

  Future<void> _publishTransactionalSyncState({
    required Map<String, int> tableRowCounts,
    required String uploadId,
    required String sourceKind,
  }) async {
    if (_workshopId == null || _workshopId!.isEmpty) return;
    final user = _auth.currentUser;
    try {
      await _transactionalSyncStateDocument()
          .set({
            'status': 'completed',
            'updatedAt': FieldValue.serverTimestamp(),
            'uploadId': uploadId,
            'sourceKind': sourceKind,
            'deviceId': _deviceId,
            if (user != null) 'uploaderUid': user.uid,
            'tableRowCounts': tableRowCounts,
          }, SetOptions(merge: true))
          .timeout(const Duration(seconds: 10));
    } catch (error) {
      print('Could not publish live transactional sync state: $error');
    }
  }

  bool _canPublishGlobalCatalog(String role) {
    // Only the application administrator may publish this catalogue because
    // it is shared by every workshop.
    return role == 'admin';
  }

  Future<void> _markCatalogDirty() async {
    _hasPendingLocalCatalogChanges = true;
    _catalogChangeGeneration++;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('has_pending_catalog_changes', true);
    } catch (error) {
      print('Failed to persist pending catalog change: $error');
    }
  }

  Future<bool> _hasUnpublishedCatalogChanges() async {
    if (_hasPendingLocalCatalogChanges) return true;
    final prefs = await SharedPreferences.getInstance();
    _hasPendingLocalCatalogChanges =
        prefs.getBool('has_pending_catalog_changes') ?? false;
    return _hasPendingLocalCatalogChanges;
  }

  Future<void> _markCatalogUploadConfirmed(int uploadedGeneration) async {
    // A newer colour/profile edit occurred while this upload was in flight.
    // It must remain dirty so the next queued upload includes it.
    if (_catalogChangeGeneration != uploadedGeneration) return;
    _hasPendingLocalCatalogChanges = false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('has_pending_catalog_changes', false);
  }

  String _transactionPendingKey(String workshopId) =>
      'has_pending_transaction_changes_$workshopId';

  Future<void> _markTransactionalChangesPending(SharedPreferences prefs) async {
    _hasPendingTransactionalChanges = true;
    _transactionChangeGeneration++;
    final workshopId = _workshopId ?? prefs.getString('workshop_code');
    if (workshopId == null || workshopId.isEmpty) {
      // This can happen only during the first seconds after login. Keep a
      // temporary marker instead of losing a worker's first change.
      await prefs.setBool('has_pending_transaction_changes', true);
      return;
    }
    await prefs.setBool(_transactionPendingKey(workshopId), true);
  }

  Future<bool> _hasPendingTransactions() async {
    if (_hasPendingTransactionalChanges) return true;
    final prefs = await SharedPreferences.getInstance();
    final workshopId = _workshopId ?? prefs.getString('workshop_code');
    _hasPendingTransactionalChanges =
        (workshopId != null && workshopId.isNotEmpty
            ? prefs.getBool(_transactionPendingKey(workshopId)) ?? false
            : false) ||
        (prefs.getBool('has_pending_transaction_changes') ?? false);
    return _hasPendingTransactionalChanges;
  }

  Future<void> _markTransactionalUploadConfirmed(int uploadedGeneration) async {
    // A new save may have happened while this snapshot was uploading. In that
    // case leave the marker set so the next upload contains the new rows.
    if (_transactionChangeGeneration != uploadedGeneration) return;
    _hasPendingTransactionalChanges = false;
    final prefs = await SharedPreferences.getInstance();
    final workshopId = _workshopId ?? prefs.getString('workshop_code');
    if (workshopId != null && workshopId.isNotEmpty) {
      await prefs.setBool(_transactionPendingKey(workshopId), false);
    }
    await prefs.setBool('has_pending_transaction_changes', false);
  }

  /// Makes every cloud restore safe for a manager and a worker alike.
  ///
  /// A full snapshot is required here instead of a delta: the restore source
  /// is `backups/latest`, so the phone-only rows must be part of that confirmed
  /// snapshot before any local table can be replaced by cloud data.
  Future<bool> _publishPendingTransactionsBeforeCloudRestore() async {
    if (!await _hasPendingTransactions()) return false;

    _sendSyncFeedback(
      CloudSyncFeedbackType.uploadStarted,
      'يجري تأمين تغييرات هذا الجهاز قبل تنزيل تحديث الورشة.',
      details: 'لن يُستبدل أي سجل محلي قبل تأكيد رفعه إلى Firebase.',
    );
    await backupToCloud(
      isSilent: true,
      forceFullSnapshot: true,
      verifyOnServer: true,
    );

    // A user may have saved another record while the full snapshot was
    // uploading. Preserve such a late change during the restore and queue it
    // for the next upload instead of allowing a download to erase it.
    return await _hasPendingTransactions();
  }

  void _resumePendingTransactionalUpload() {
    _pendingTransactionUploadTimer?.cancel();
    _pendingTransactionUploadTimer = Timer(
      const Duration(seconds: 2),
      () async {
        final supabaseWorkshopSync = SupabaseWorkshopSyncService();
        if (supabaseWorkshopSync.isSignedIn) {
          if (await _db.hasPendingCloudChanges()) {
            supabaseWorkshopSync.notifyLocalChange(immediate: true);
          }
          await _clearFirebaseTransactionalPendingFlag();
          return;
        }
        if (await _hasPendingTransactions()) {
          await _silentBackup();
        }
      },
    );
  }

  Future<void> _ensureCloudCatalogCanBeApplied(
    int downloadGeneration,
    bool discardPendingLocalChanges,
  ) async {
    if (discardPendingLocalChanges) return;
    if (_catalogChangeGeneration != downloadGeneration ||
        await _hasUnpublishedCatalogChanges()) {
      throw StateError(
        'تم تعديل الكتالوج محليًا أثناء التنزيل؛ لن يتم استبداله بالنسخة السحابية.',
      );
    }
  }

  Future<void> _rejectUnexpectedEmptyCatalogTables(
    Map<String, dynamic> incomingCatalog,
    bool discardPendingLocalChanges,
  ) async {
    // An empty catalogue from an outdated device must never silently erase a
    // usable colour or shutter catalogue on this device. Empty tables are
    // allowed only during the first setup (when the local table is empty too).
    if (discardPendingLocalChanges) return;
    final localDb = await _db.db;
    if (localDb == null) return;

    for (final table in const ['Colors', 'ShutterComponents']) {
      final incomingRows = incomingCatalog[table];
      if (incomingRows is! List || incomingRows.isNotEmpty) continue;
      final result = await localDb.rawQuery(
        'SELECT COUNT(*) AS count FROM $table',
      );
      final localCount = (result.first['count'] as num?)?.toInt() ?? 0;
      if (localCount > 0) {
        throw StateError(
          'رفضت الكتالوج السحابي الفارغ حتى لا يمسح $table من هذا الجهاز.',
        );
      }
    }

    // Shutter components are soft-deleted, so a healthy central catalogue
    // keeps its historical rows (including inactive rows).  A smaller remote
    // list is therefore a stale or incomplete upload, not a valid update.
    // Never let the single old component visible in Firebase replace the
    // complete local catalogue on the manager's device.
    final remoteShutterRows = incomingCatalog['ShutterComponents'];
    if (remoteShutterRows is! List) return;
    final localShutterCount = await localDb.rawQuery(
      'SELECT COUNT(*) AS count FROM ShutterComponents',
    );
    final localCount = (localShutterCount.first['count'] as num?)?.toInt() ?? 0;
    if (localCount > 0 && remoteShutterRows.length < localCount) {
      throw StateError(
        'رفضت كتالوج مركبات الستائر الناقص '
        '(${remoteShutterRows.length} من أصل $localCount محلياً) حتى لا '
        'يستبدل السجلّات الكاملة بنسخة قديمة.',
      );
    }
  }

  String _describeCloudWriteFailure(Object error) {
    if (SqlDatabase.isDatabaseMovedError(error)) {
      return 'اتصال SQLite المحلي أصبح قديماً بعد تغيير ملف القاعدة (code 1032). '
          'سيعيد التطبيق فتح القاعدة ثم يعيد محاولة التحديث.';
    }
    if (SqlDatabase.isCorruptionError(error)) {
      return 'قاعدة SQLite المحلية على هذا الهاتف تالفة (code 11). '
          'سيحاول التطبيق إنشاء قاعدة سليمة واستعادة النسخة السحابية تلقائياً.';
    }
    if (error is TimeoutException) {
      return 'انتهت مهلة الاتصال بالسحابة. ستتم إعادة المحاولة تلقائياً؛ تحقق من ثبات الإنترنت إذا تكرر الخطأ.';
    }
    if (error is FirebaseException) {
      switch (error.code) {
        case 'permission-denied':
          return 'رفضت قواعد Firebase القراءة أو الكتابة داخل هذه الورشة. يجب السماح للحساب بالوصول إلى backups/latest وإلى مجلد chunks.';
        case 'unauthenticated':
          return 'انتهت جلسة تسجيل الدخول؛ أعد تسجيل الدخول ثم أعد الرفع.';
        case 'unavailable':
          return 'خدمة Firebase غير متاحة حالياً أو لا يوجد اتصال ثابت بالإنترنت.';
        case 'resource-exhausted':
          return 'تجاوزت العملية حد Firebase المسموح مؤقتاً؛ ستتم إعادة المحاولة.';
      }
    }
    return error.toString();
  }

  int _estimateJsonBytes(Object? value) {
    try {
      return utf8.encode(jsonEncode(value)).length;
    } catch (_) {
      return _maxChunkCharacters;
    }
  }

  String _formatBytes(int bytes) {
    if (bytes >= 1000000) {
      return '${(bytes / 1000000).toStringAsFixed(1)} MB';
    }
    if (bytes >= 1000) {
      return '${(bytes / 1000).toStringAsFixed(0)} KB';
    }
    return '$bytes B';
  }

  String _largeFieldId(
    String table,
    int chunkIndex,
    int rowIndex,
    String field,
  ) {
    final safeField = field.replaceAll(RegExp(r'[^A-Za-z0-9_]'), '_');
    return '${table}_${chunkIndex}_${rowIndex}_$safeField';
  }

  List<_CloudChunkWrite> _buildChunkWrites({
    required String table,
    required int chunkIndex,
    required int totalChunks,
    required List<dynamic> rows,
    required String uploadId,
  }) {
    final extraWrites = <_CloudChunkWrite>[];
    final preparedRows = <dynamic>[];

    for (var rowIndex = 0; rowIndex < rows.length; rowIndex++) {
      final row = rows[rowIndex];
      if (row is! Map) {
        preparedRows.add(row);
        continue;
      }

      final preparedRow = Map<String, dynamic>.from(row);
      for (final entry in row.entries) {
        final field = entry.key.toString();
        final value = entry.value;
        if (value is! String ||
            value.isEmpty ||
            _estimateJsonBytes(value) <= _largeFieldInlineBytes) {
          continue;
        }

        final largeId = _largeFieldId(table, chunkIndex, rowIndex, field);
        final parts = <String>[];
        for (
          var start = 0;
          start < value.length;
          start += _largeFieldPartCharacters
        ) {
          final end = min(start + _largeFieldPartCharacters, value.length);
          parts.add(value.substring(start, end));
        }

        preparedRow[field] = {
          _largeFieldMarkerKey: true,
          'largeId': largeId,
          'totalParts': parts.length,
        };

        for (var partIndex = 0; partIndex < parts.length; partIndex++) {
          extraWrites.add(
            _CloudChunkWrite(
              docId: '__large_${largeId}_$partIndex',
              payload: {
                'kind': _largeFieldPartKind,
                'uploadId': uploadId,
                'largeId': largeId,
                'table': table,
                'chunkIndex': chunkIndex,
                'rowIndex': rowIndex,
                'field': field,
                'partIndex': partIndex,
                'totalParts': parts.length,
                'data': parts[partIndex],
              },
            ),
          );
        }
      }

      preparedRows.add(preparedRow);
    }

    final normalPayload = <String, dynamic>{
      'uploadId': uploadId,
      'table': table,
      'chunkIndex': chunkIndex,
      'totalChunks': totalChunks,
      'data': preparedRows,
    };

    return [
      _CloudChunkWrite(docId: '${table}_$chunkIndex', payload: normalPayload),
      ...extraWrites,
    ];
  }

  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _fetchChunkPages(
    CollectionReference<Map<String, dynamic>> chunkRef, {
    Duration timeout = const Duration(seconds: 25),
  }) async {
    final chunks = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    DocumentSnapshot<Map<String, dynamic>>? lastDocument;

    while (true) {
      Query<Map<String, dynamic>> query = chunkRef
          .orderBy(FieldPath.documentId)
          .limit(_chunkDownloadPageSize);
      if (lastDocument != null) {
        query = query.startAfterDocument(lastDocument);
      }

      QuerySnapshot<Map<String, dynamic>> page;
      try {
        page = await query
            .get(GetOptions(source: Source.server))
            .timeout(timeout);
      } catch (_) {
        page = await query.get().timeout(timeout);
      }

      if (page.docs.isEmpty) break;
      chunks.addAll(page.docs);
      lastDocument = page.docs.last;
      if (page.docs.length < _chunkDownloadPageSize) break;

      // Let the UI and the platform channel release the previous page before
      // requesting the next one on memory-constrained phones.
      await Future<void>.delayed(Duration.zero);
    }

    return chunks;
  }

  Map<String, List<dynamic>> _assembleChunkedData(
    Iterable<QueryDocumentSnapshot<Map<String, dynamic>>> chunkDocs, {
    String? uploadId,
  }) {
    final largeFieldParts = <String, Map<int, String>>{};
    final normalChunks = <MapEntry<String, Map<String, dynamic>>>[];

    for (final chunkDoc in chunkDocs) {
      final chunkData = chunkDoc.data();
      if (uploadId != null &&
          uploadId.isNotEmpty &&
          chunkData['uploadId']?.toString() != uploadId) {
        continue;
      }
      if (chunkData['kind']?.toString() == _largeFieldPartKind) {
        final largeId = chunkData['largeId']?.toString() ?? '';
        final partIndex = (chunkData['partIndex'] as num?)?.toInt() ?? -1;
        final data = chunkData['data'];
        if (largeId.isNotEmpty && partIndex >= 0 && data is String) {
          largeFieldParts.putIfAbsent(largeId, () => {})[partIndex] = data;
        }
        continue;
      }
      normalChunks.add(MapEntry(chunkDoc.id, chunkData));
    }

    final assembledData = <String, List<dynamic>>{};
    for (final chunkEntry in normalChunks) {
      final chunkData = chunkEntry.value;
      String table = chunkData['table']?.toString() ?? '';
      if (table.isEmpty) {
        table = chunkEntry.key.replaceAll(RegExp(r'_\d+$'), '');
      }
      if (table.isEmpty || table.startsWith('__large_')) continue;

      assembledData.putIfAbsent(table, () => []);
      final rows = chunkData['data'];
      if (rows is! List) continue;

      for (final row in rows) {
        if (row is! Map) {
          assembledData[table]!.add(row);
          continue;
        }

        final restoredRow = Map<String, dynamic>.from(row);
        for (final entry in row.entries) {
          final value = entry.value;
          if (value is! Map || value[_largeFieldMarkerKey] != true) continue;

          final marker = Map<String, dynamic>.from(value);
          final largeId = marker['largeId']?.toString() ?? '';
          final totalParts = (marker['totalParts'] as num?)?.toInt() ?? 0;
          final parts = largeFieldParts[largeId];
          if (largeId.isEmpty || totalParts <= 0 || parts == null) {
            throw StateError('صورة أو رسم غير مكتمل في $table (${entry.key}).');
          }

          final buffer = StringBuffer();
          var complete = true;
          for (var partIndex = 0; partIndex < totalParts; partIndex++) {
            final part = parts[partIndex];
            if (part == null) {
              complete = false;
              break;
            }
            buffer.write(part);
          }
          if (!complete) {
            throw StateError('صورة أو رسم غير مكتمل في $table (${entry.key}).');
          }
          restoredRow[entry.key] = buffer.toString();
        }
        assembledData[table]!.add(restoredRow);
      }
    }

    return assembledData;
  }

  Future<Map<String, int>> _uploadChunkedTables({
    required Map<String, dynamic> data,
    required CollectionReference<Map<String, dynamic>> chunkRef,
    required void Function(String stage) setStage,
    required String uploadId,
  }) async {
    final newChunkCounts = <String, int>{};
    var uploadBatch = _firestore.batch();
    var batchCount = 0;
    var batchBytes = 0;
    var batchNumber = 1;
    var lastChunkLabel = '';

    Future<void> commitCurrentBatch() async {
      if (batchCount == 0) return;
      setStage(
        'إرسال دفعة $batchNumber حتى $lastChunkLabel '
        '($batchCount جزء، ${_formatBytes(batchBytes)})',
      );
      await uploadBatch.commit().timeout(_chunkUploadTimeout);
      uploadBatch = _firestore.batch();
      batchCount = 0;
      batchBytes = 0;
      batchNumber++;
    }

    for (final table in data.keys) {
      final rawRows = data[table];
      final rows = rawRows is List ? rawRows : <dynamic>[];
      final rawChunks = _partitionRowsIntoChunks(rows);
      final chunks = rawChunks.isEmpty
          ? <List<dynamic>>[<dynamic>[]]
          : rawChunks;
      final chunksCount = chunks.length;
      newChunkCounts[table] = chunksCount;

      for (var i = 0; i < chunksCount; i++) {
        lastChunkLabel = '$table ${i + 1}/$chunksCount';
        setStage('تجهيز جدول $table: جزء ${i + 1}/$chunksCount');

        final chunkWrites = _buildChunkWrites(
          table: table,
          chunkIndex: i,
          totalChunks: chunksCount,
          rows: chunks[i],
          uploadId: uploadId,
        );

        for (final write in chunkWrites) {
          final payloadBytes = _estimateJsonBytes(write.payload);
          if (payloadBytes > _maxFirestoreDocumentBytes) {
            throw StateError(
              'جزء كبير جداً في جدول $table (${_formatBytes(payloadBytes)}). '
              'غالباً توجد صورة/رسم كبير داخل سجل واحد.',
            );
          }

          if (batchCount > 0 &&
              (batchCount >= _maxUploadBatchWrites ||
                  batchBytes + payloadBytes > _maxUploadBatchBytes)) {
            await commitCurrentBatch();
          }

          uploadBatch.set(chunkRef.doc(write.docId), write.payload);
          batchCount++;
          batchBytes += payloadBytes;
        }
      }
    }

    await commitCurrentBatch();
    return newChunkCounts;
  }

  Future<void> init() async {
    print("--- CloudSyncService: init() started ---");
    final prefs = await SharedPreferences.getInstance();
    String? storedId = prefs.getString('device_id');
    if (storedId == null) {
      final rnd = Random();
      storedId =
          'device_${DateTime.now().millisecondsSinceEpoch}_${rnd.nextInt(100000)}';
      await prefs.setString('device_id', storedId);
    }
    _deviceId = storedId;
    print("--- CloudSyncService: deviceId = $_deviceId ---");

    if (_lastHandledPermissionsFingerprint == null) {
      await _loadCachedPermissions();
    }

    final user = _auth.currentUser;
    print("--- CloudSyncService: currentUser = ${user?.uid} ---");
    if (user != null) {
      try {
        final doc = await _firestore
            .collection('users')
            .doc(user.uid)
            .get()
            .timeout(const Duration(seconds: 10));
        if (doc.exists && doc.data() != null) {
          final data = doc.data()!;
          final rawRole = data['role']?.toString() ?? 'worker';
          final wId = data['workshopId']?.toString() ?? '';
          final storedWorkshopId = prefs.getString('workshop_code') ?? '';
          final role = rawRole;
          final isManagerDoc = role == 'manager' || wId == user.uid;
          final isWorkshopMember =
              !isManagerDoc && (role == 'worker' || role == 'co_manager');

          await _applyPermissionsUpdate(data);

          if (isWorkshopMember && (wId.isEmpty || wId == user.uid)) {
            // A worker must never upload to a personal workshop path. Use a
            // previously verified workshop id when available; otherwise stop
            // and wait for the manager to link the account correctly.
            if (storedWorkshopId.isNotEmpty && storedWorkshopId != user.uid) {
              _workshopId = storedWorkshopId;
              await prefs.setString('user_role', role);
              print(
                'Worker init: using cached workshopId=$storedWorkshopId for ${user.uid}',
              );
            } else {
              // ⚠️ [تشخيص]: حساب العامل لا يحتوي على workshopId صحيح في Firestore.
              // يجب على المدير إضافة هذا العامل من شاشة إدارة العمال حتى تعمل المزامنة.
              _workshopId = null;
              lastBackupUploadSummary =
                  'المزامنة متوقفة: حساب العامل (${user.email ?? user.uid}) غير مرتبط بورشة.\n'
                  'يجب على المدير إضافة هذا العامل من شاشة "إدارة العمال" في التطبيق.\n'
                  'أو إضافة حقل workshopId = uid_المدير يدوياً في Firebase Console.';
              await prefs.setString('workshop_code', '');
              await prefs.setString('user_role', role);
              print(
                '[CloudSync] Worker sync BLOCKED — missing workshopId for uid=${user.uid} email=${user.email}\n'
                'Fix: In Firestore, set users/${user.uid}/workshopId = <manager_uid>',
              );
              // إصدار تغذية راجعة مرئية في واجهة المستخدم
              _sendSyncFeedback(
                CloudSyncFeedbackType.uploadFailed,
                'المزامنة متوقفة لهذا الجهاز.',
                details:
                    'حساب العامل (${user.email ?? user.uid}) غير مرتبط بورشة في Firebase.\n'
                    'الحل: اطلب من المدير إضافتك من شاشة "إدارة العمال".',
              );
              return;
            }
          } else if (wId.isNotEmpty) {
            _workshopId = wId;
          } else {
            _workshopId = user.uid;
          }
          await prefs.setString('workshop_code', _workshopId!);
          await prefs.setString('user_role', role);
          final workshopName = data['workshopName']?.toString().trim() ?? '';
          final displayName = data['displayName']?.toString().trim() ?? '';
          if (workshopName.isNotEmpty) {
            await prefs.setString('workshop_name', workshopName);
          }
          if (displayName.isNotEmpty) {
            await prefs.setString('user_display_name', displayName);
          }
        } else {
          _workshopId = prefs.getString('workshop_code') ?? user.uid;
          if (_workshopId == user.uid) {
            await prefs.setString('user_role', 'manager');
          }
        }
      } catch (e) {
        print('Error fetching workshopId: $e');
        _workshopId = prefs.getString('workshop_code') ?? user.uid;
        if (_workshopId == user.uid) {
          await prefs.setString('user_role', 'manager');
        }
      }
      if (_workshopId != null && _workshopId!.isNotEmpty) {
        _lastHandledBackupFingerprint = prefs.getString(
          _handledBackupPreferenceKey(_workshopId!),
        );
      } else {
        _lastHandledBackupFingerprint = null;
      }
    }
    print(
      "--- CloudSyncService: init() finished. workshopId = $_workshopId ---",
    );
  }

  void reset() {
    SupabaseWorkshopSyncService().stop();
    _workshopId = null;
    _debounceTimer?.cancel();
    _backupRetryTimer?.cancel();
    _catalogDebounceTimer?.cancel();
    _catalogRetryTimer?.cancel();
    _realtimeRetryTimer?.cancel();
    _realtimeHealthTimer?.cancel();
    _pendingCloudChangePollTimer?.cancel();
    _pendingTransactionUploadTimer?.cancel();
    _listener?.cancel();
    _catalogListener?.cancel();
    _deltaListener?.cancel();
    _liveEventListener?.cancel();
    _statusListener?.cancel();
    _orderStatusListener?.cancel();
    _measurementsListener?.cancel();
    _deletionsListener?.cancel();
    _orderDeletionsListener?.cancel();
    _permissionsListener?.cancel();
    _listener = null;
    _catalogListener = null;
    _deltaListener = null;
    _liveEventListener = null;
    _statusListener = null;
    _orderStatusListener = null;
    _measurementsListener = null;
    _deletionsListener = null;
    _orderDeletionsListener = null;
    _permissionsListener = null;
    _pendingCloudChangePollTimer = null;
    _pendingTransactionUploadTimer = null;
    _lastHandledBackupFingerprint = null;
    _lastHandledCatalogFingerprint = null;
    _lastHandledPermissionsFingerprint = null;
    _currentPermissions = <String, dynamic>{};
    _ownUploadIds.clear();
    _handledDeltaIds.clear();
    _processingDeltaIds.clear();
    _deltaApplyChain = Future<void>.value();
    _loadedDeltaWorkshopId = null;
    _handledLiveEventIds.clear();
    _processingLiveEventIds.clear();
    _liveEventApplyChain = Future<void>.value();
    _allocationStatusApplyChain = Future<void>.value();
    _loadedLiveEventWorkshopId = null;
    _latestFullSnapshotCompletedAt = null;
    _latestFullCompactedDeltaIds.clear();
    _lastAnnouncedListenerWorkshopId = null;
    _lastRealtimeErrorFeedbackAt = null;
    _activeBackup = null;
    _activeLiveEventUpload = null;
    _liveEventUploadQueued = false;
    _activeCatalogBackup = null;
    _activeRestore = null;
    _activeFullRecovery = null;
    _catalogBackupQueued = false;
    _hasPendingLocalCatalogChanges = false;
    _catalogChangeGeneration = 0;
    _hasPendingTransactionalChanges = false;
    _transactionChangeGeneration = 0;
    if (!(_restoreIdleCompleter?.isCompleted ?? true)) {
      _restoreIdleCompleter!.complete();
    }
    _restoreIdleCompleter = null;
    _restoreDepth = 0;
    _localWriteDepth = 0;
    _refreshQueuedAfterLocalWrite = false;
    _backupQueuedAfterLocalWrite = false;
    _refreshQueuedAfterRestore = false;
    _catalogRefreshQueuedAfterRestore = false;
    _localSyncQueuedAfterRestore = false;
  }

  /// بدء الاستماع لتحديثات السحابة لتطبيق المزامنة التلقائية اللحظية لجميع الحسابات
  void startListeningForUpdates(Function() onUpdateCallback) {
    onDataRestored = onUpdateCallback;
    final supabaseWorkshopSync = SupabaseWorkshopSyncService();
    supabaseWorkshopSync.start(onDataChanged: onUpdateCallback);
    final user = _auth.currentUser;
    if (user == null) return;

    // ⚡ الاستماع الفوري واللحظي لتحديثات صلاحيات هذا الحساب (permissions).
    // يعمل بشكل مستقل عن معرّف الورشة، لأن مستند users/{uid} يخص هذا الحساب
    // فقط، ويجب أن يتحدث حتى قبل ربط العامل بورشة صحيحة.
    _permissionsListener?.cancel();
    _permissionsListener = _firestore
        .collection('users')
        .doc(user.uid)
        .snapshots()
        .listen(
          (doc) async {
            if (!doc.exists || doc.data() == null) return;
            await _applyPermissionsUpdate(doc.data()!);
          },
          onError: _scheduleRealtimeListenerRetry,
          onDone: _scheduleRealtimeListenerRetry,
        );

    if (supabaseWorkshopDataOnly) {
      _listener?.cancel();
      _catalogListener?.cancel();
      _deltaListener?.cancel();
      _liveEventListener?.cancel();
      _statusListener?.cancel();
      _orderStatusListener?.cancel();
      _measurementsListener?.cancel();
      _deletionsListener?.cancel();
      _orderDeletionsListener?.cancel();
      _listener = null;
      _catalogListener = null;
      _deltaListener = null;
      _liveEventListener = null;
      _statusListener = null;
      _orderStatusListener = null;
      _measurementsListener = null;
      _deletionsListener = null;
      _orderDeletionsListener = null;
      unawaited(
        supabaseWorkshopSync
            .ensureStarted(onDataChanged: onUpdateCallback)
            .then((ready) {
              if (!ready) {
                _sendSyncFeedback(
                  CloudSyncFeedbackType.downloadFailed,
                  'تعذر تشغيل مزامنة Supabase.',
                  details:
                      'جلسة Supabase أو معرّف الورشة غير جاهز. سجّل الدخول ثم أعد المحاولة.',
                );
                return;
              }
              if (_lastAnnouncedListenerWorkshopId != 'supabase:$_workshopId') {
                _lastAnnouncedListenerWorkshopId = 'supabase:$_workshopId';
                _sendSyncFeedback(
                  CloudSyncFeedbackType.syncReady,
                  'تم تفعيل مزامنة الورشة عبر Supabase.',
                  details: 'مصدر بيانات الورشة أصبح Supabase فقط.',
                );
              }
            }),
      );
      return;
    }

    if (_workshopId == null || _workshopId!.isEmpty) {
      _sendSyncFeedback(
        CloudSyncFeedbackType.uploadFailed,
        'المزامنة غير مفعلة لهذا الحساب.',
        details:
            'حسابك غير مرتبط بورشة صحيحة في Firebase. تحقق من workshopId للعامل.',
      );
      return;
    }

    if (supabaseWorkshopSync.isSignedIn) {
      _listener?.cancel();
      _catalogListener?.cancel();
      _deltaListener?.cancel();
      _liveEventListener?.cancel();
      _statusListener?.cancel();
      _orderStatusListener?.cancel();
      _measurementsListener?.cancel();
      _deletionsListener?.cancel();
      _orderDeletionsListener?.cancel();
      _listener = null;
      _catalogListener = null;
      _deltaListener = null;
      _liveEventListener = null;
      _statusListener = null;
      _orderStatusListener = null;
      _measurementsListener = null;
      _deletionsListener = null;
      _orderDeletionsListener = null;
      _clearFirebaseTransactionalPendingFlag();
      if (_lastAnnouncedListenerWorkshopId != 'supabase:$_workshopId') {
        _lastAnnouncedListenerWorkshopId = 'supabase:$_workshopId';
        _sendSyncFeedback(
          CloudSyncFeedbackType.syncReady,
          'تم تفعيل مزامنة الورشة عبر Supabase.',
          details: 'معرّف الورشة: $_workshopId',
        );
      }
      return;
    }

    // 1. الاستماع لتغييرات نسخة السحابة الكاملة (Latest Backup)
    _listener?.cancel();
    _listener = _firestore
        .collection('workshops')
        .doc(_workshopId)
        .collection('backups')
        .doc('latest')
        .snapshots()
        .listen(
          (doc) async {
            if (!doc.exists || doc.data() == null) return;

            final Map<String, dynamic> payload = Map<String, dynamic>.from(
              doc.data() as Map,
            );
            await _applyLatestBackupUpdate(payload);
          },
          onError: _scheduleRealtimeListenerRetry,
          onDone: _scheduleRealtimeListenerRetry,
        );

    // Small immutable delta documents carry only rows changed by a phone.
    // Keeping each delta as its own document means several phones can publish
    // together without overwriting one another or waiting for the full-backup
    // queue.
    //
    // ⚠️ [توفير حصة Firebase]: هذا الاستعلام كان بدون أي حد أقصى (limit)، فكل
    // مستند delta قديم متراكم (حتى لو عولج ودُمج في نسخة كاملة سابقاً) كان
    // يُقرأ من جديد في كل مرة يتغيّر فيها أي مستند بالمجموعة. إضافة limit مع
    // الترتيب حسب معرّف المستند (لا يحتاج فهرساً إضافياً في Firestore، بعكس
    // الترتيب حسب حقل آخر مع شرط where) تحدّ التكلفة بشكل ثابت ومضمون.
    _deltaListener?.cancel();
    _deltaListener = _firestore
        .collection('workshops')
        .doc(_workshopId)
        .collection('backups')
        .where('kind', isEqualTo: 'delta')
        .orderBy(FieldPath.documentId, descending: true)
        .limit(_deltaQueryLimit)
        .snapshots()
        .listen(
          _queueDeltaSnapshot,
          onError: _scheduleRealtimeListenerRetry,
          onDone: _scheduleRealtimeListenerRetry,
        );

    // Fast path: tiny row-level events for changes users expect to see now
    // (cash register, worker finance, customers, orders, allocations, etc.).
    // The durable delta/full backup path still runs after this as reconciliation.
    _liveEventListener?.cancel();
    _liveEventListener = _firestore
        .collection('workshops')
        .doc(_workshopId)
        .collection('live_events')
        .orderBy('createdAt', descending: true)
        .limit(_liveEventListenerLimit)
        .snapshots()
        .listen(
          _queueLiveEventSnapshot,
          onError: _scheduleRealtimeListenerRetry,
          onDone: _scheduleRealtimeListenerRetry,
        );

    if (_lastAnnouncedListenerWorkshopId != _workshopId) {
      _lastAnnouncedListenerWorkshopId = _workshopId;
      _sendSyncFeedback(
        CloudSyncFeedbackType.syncReady,
        'تم تفعيل استقبال تحديثات الورشة.',
        details: 'معرّف الورشة: $_workshopId',
      );
    }

    _catalogListener?.cancel();
    _catalogListener = _catalogDocument().snapshots().listen((doc) async {
      if (!doc.exists || doc.data() == null) return;
      await _applyGlobalCatalogUpdate(
        Map<String, dynamic>.from(doc.data() as Map),
      );
    }, onError: _scheduleRealtimeListenerRetry);

    // 2. ⚡ الاستماع الفوري واللحظي لتحديثات حالات الإسناد من أي هاتف في الورشة
    _statusListener?.cancel();
    _statusListener = _firestore
        .collection('workshops')
        .doc(_workshopId)
        .collection('worker_allocations_status')
        .snapshots()
        .listen((snapshot) {
          if (_isRestoring) return;
          final changedRows = <Map<String, dynamic>>[];
          for (final change in snapshot.docChanges) {
            if (change.type == DocumentChangeType.removed) continue;
            final data = change.doc.data();
            if (data == null) continue;
            final row = Map<String, dynamic>.from(data);
            row['__allocation_id'] = change.doc.id;
            changedRows.add(row);
          }
          if (changedRows.isEmpty) return;

          // Firestore can deliver several snapshots while one write is in
          // flight. Apply them in order so a slower older snapshot cannot
          // overwrite the newest local row.
          _allocationStatusApplyChain = _allocationStatusApplyChain.then((
            _,
          ) async {
            try {
              await _db.syncWorkerAllocationsStatusFromCloud(
                changedRows: changedRows,
              );
              _dbUpdateController.add('status_updated');
            } catch (e) {
              print('Error syncing allocation status real-time: $e');
            }
          });
        }, onError: _scheduleRealtimeListenerRetry);

    // 3. ⚡ الاستماع الفوري واللحظي لتحديثات حالات الطلبيات من أي هاتف في الورشة
    _orderStatusListener?.cancel();
    _orderStatusListener = _firestore
        .collection('workshops')
        .doc(_workshopId)
        .collection('orders_status')
        .snapshots()
        .listen((snapshot) async {
          if (_isRestoring) return;
          try {
            final didChange = await _db.syncOrdersStatusFromCloud();
            if (didChange) {
              _dbUpdateController.add('order_status_updated');
            }
            // ملاحظة: لا نستدعي onDataRestored() هنا لتجنب الترميش.
          } catch (e) {
            print('Error syncing order status real-time: $e');
          }
        }, onError: _scheduleRealtimeListenerRetry);

    // 4. ⚡ الاستماع الفوري واللحظي لتأكيد قياسات الموقع من أي هاتف في الورشة
    _measurementsListener?.cancel();
    _measurementsListener = _firestore
        .collection('workshops')
        .doc(_workshopId)
        .collection('confirmed_measurements')
        .snapshots()
        .listen((snapshot) async {
          if (_isRestoring) return;
          try {
            await _db.syncConfirmedMeasurementsFromCloud();
            _dbUpdateController.add('measurements_updated');
            // ملاحظة: لا نستدعي onDataRestored() هنا لتجنب الترميش.
          } catch (e) {
            print('Error syncing confirmed measurements real-time: $e');
          }
        }, onError: _scheduleRealtimeListenerRetry);

    // 5. ⚡ الاستماع اللحظي لحذف الإسنادات من أي جهاز (بما فيها هاتف العامل)
    _deletionsListener?.cancel();
    _deletionsListener = _firestore
        .collection('workshops')
        .doc(_workshopId)
        .collection('deleted_allocations')
        .snapshots()
        .listen((snapshot) async {
          if (_isRestoring) return;
          // عند إضافة tombstone جديد (حذف إسناد) نحذفه فوراً من SQLite على هذا الجهاز
          for (final change in snapshot.docChanges) {
            if (change.type == DocumentChangeType.added) {
              try {
                final data = change.doc.data();
                if (data == null) continue;
                final id =
                    (data['id'] as num?)?.toInt() ??
                    int.tryParse(change.doc.id) ??
                    0;
                if (id > 0) {
                  await _db.deleteWorkerAllocationLocalOnly(id);
                }
              } catch (e) {
                print('Error applying deletion tombstone real-time: $e');
              }
            }
          }
          _dbUpdateController.add('allocation_deleted');
        }, onError: _scheduleRealtimeListenerRetry);

    // 6. ⚡ الاستماع اللحظي لحذف الطلبيات. هذا مسار صغير ومباشر مثل
    // الصلاحيات، فلا ينتظر تنزيل backup/delta كامل حتى تختفي الطلبية.
    _orderDeletionsListener?.cancel();
    _orderDeletionsListener = _firestore
        .collection('workshops')
        .doc(_workshopId)
        .collection('deleted_orders')
        .snapshots()
        .listen((snapshot) async {
          if (_isRestoring) return;
          var didDelete = false;
          for (final change in snapshot.docChanges) {
            if (change.type != DocumentChangeType.added) continue;
            try {
              final data = change.doc.data();
              final id =
                  (data?['id'] as num?)?.toInt() ??
                  int.tryParse(change.doc.id) ??
                  0;
              if (id <= 0) continue;
              final deleted = await _db.deleteCommandeLocalOnly(id);
              didDelete = didDelete || deleted > 0;
            } catch (e) {
              print('Error applying order deletion tombstone real-time: $e');
            }
          }
          if (didDelete) {
            _dbUpdateController.add('order_deleted');
            onDataRestored?.call();
          }
        }, onError: _scheduleRealtimeListenerRetry);

    _startRealtimeHealthCheck();
    _startPendingCloudChangePoll();
    _resumePendingTransactionalUpload();
  }

  /// إيقاف الاستماع
  String _backupFingerprint(Map<String, dynamic> payload) {
    return [
      payload['uploadId']?.toString() ?? '',
      payload['timestamp']?.toString() ?? '',
      payload['deviceId']?.toString() ?? '',
      payload['status']?.toString() ?? '',
    ].join('|');
  }

  String _catalogFingerprint(Map<String, dynamic> payload) {
    return [
      payload['uploadId']?.toString() ?? '',
      payload['timestamp']?.toString() ?? '',
      payload['deviceId']?.toString() ?? '',
      payload['status']?.toString() ?? '',
    ].join('|');
  }

  String _handledDeltasPreferenceKey(String workshopId) =>
      'handled_cloud_deltas_$workshopId';

  String _handledLiveEventsPreferenceKey(String workshopId) =>
      'handled_live_events_$workshopId';

  String _handledBackupPreferenceKey(String workshopId) =>
      'handled_cloud_backup_$workshopId';

  Future<void> _rememberHandledBackupFingerprint(String fingerprint) async {
    if (fingerprint.isEmpty) return;
    final workshopId = _workshopId;
    if (workshopId == null || workshopId.isEmpty) return;
    _lastHandledBackupFingerprint = fingerprint;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _handledBackupPreferenceKey(workshopId),
        fingerprint,
      );
    } catch (error) {
      print('Could not persist handled backup fingerprint: $error');
    }
  }

  DateTime? _firestoreDate(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value == null) return null;
    return DateTime.tryParse(value.toString());
  }

  void _rememberFullSnapshotMetadata(Map<String, dynamic> payload) {
    _latestFullSnapshotCompletedAt = _firestoreDate(
      payload['completedAt'] ?? payload['timestamp'],
    );
    final rawCompactedIds = payload['compactedDeltaIds'];
    _latestFullCompactedDeltaIds
      ..clear()
      ..addAll(
        (rawCompactedIds is List ? rawCompactedIds : const <dynamic>[])
            .map((value) => value.toString())
            .where((value) => value.isNotEmpty),
      );
  }

  Future<void> _ensureHandledDeltasLoaded() async {
    final workshopId = _workshopId;
    if (workshopId == null ||
        workshopId.isEmpty ||
        _loadedDeltaWorkshopId == workshopId) {
      return;
    }
    _loadedDeltaWorkshopId = workshopId;
    _handledDeltaIds.clear();
    final prefs = await SharedPreferences.getInstance();
    _handledDeltaIds.addAll(
      prefs.getStringList(_handledDeltasPreferenceKey(workshopId)) ??
          const <String>[],
    );
  }

  Future<void> _markDeltaHandled(String deltaId) async {
    if (deltaId.isEmpty) return;
    await _ensureHandledDeltasLoaded();
    _handledDeltaIds.add(deltaId);
    while (_handledDeltaIds.length > 400) {
      _handledDeltaIds.remove(_handledDeltaIds.first);
    }
    final workshopId = _workshopId;
    if (workshopId == null || workshopId.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _handledDeltasPreferenceKey(workshopId),
      _handledDeltaIds.toList(),
    );
  }

  Future<void> _ensureHandledLiveEventsLoaded() async {
    final workshopId = _workshopId;
    if (workshopId == null ||
        workshopId.isEmpty ||
        _loadedLiveEventWorkshopId == workshopId) {
      return;
    }
    _loadedLiveEventWorkshopId = workshopId;
    _handledLiveEventIds.clear();
    final prefs = await SharedPreferences.getInstance();
    _handledLiveEventIds.addAll(
      prefs.getStringList(_handledLiveEventsPreferenceKey(workshopId)) ??
          const <String>[],
    );
  }

  Future<void> _markLiveEventHandled(String eventId) async {
    if (eventId.isEmpty) return;
    await _ensureHandledLiveEventsLoaded();
    _handledLiveEventIds.add(eventId);
    while (_handledLiveEventIds.length > 600) {
      _handledLiveEventIds.remove(_handledLiveEventIds.first);
    }
    final workshopId = _workshopId;
    if (workshopId == null || workshopId.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _handledLiveEventsPreferenceKey(workshopId),
      _handledLiveEventIds.toList(),
    );
  }

  Future<DateTime?> _readLatestFullSnapshotWatermark() async {
    if (_latestFullSnapshotCompletedAt != null) {
      return _latestFullSnapshotCompletedAt;
    }
    final workshopId = _workshopId;
    if (workshopId == null || workshopId.isEmpty) return null;
    try {
      final latest = await _firestore
          .collection('workshops')
          .doc(workshopId)
          .collection('backups')
          .doc('latest')
          .get(GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 10));
      final payload = latest.data();
      if (payload?['status']?.toString() == 'completed') {
        _rememberFullSnapshotMetadata(payload!);
      }
    } catch (error) {
      print('Could not read full snapshot watermark: $error');
    }
    return _latestFullSnapshotCompletedAt;
  }

  void _queueLiveEventSnapshot(QuerySnapshot<Map<String, dynamic>> snapshot) {
    final completed =
        snapshot.docChanges.map((change) => change.doc).where((doc) {
          final data = doc.data();
          return data != null && data['status']?.toString() == 'completed';
        }).toList()..sort((left, right) {
          final leftTime =
              _firestoreDate(
                left.data()!['completedAt'] ?? left.data()!['createdAt'],
              )?.millisecondsSinceEpoch ??
              0;
          final rightTime =
              _firestoreDate(
                right.data()!['completedAt'] ?? right.data()!['createdAt'],
              )?.millisecondsSinceEpoch ??
              0;
          final timeResult = leftTime.compareTo(rightTime);
          return timeResult != 0 ? timeResult : left.id.compareTo(right.id);
        });

    for (final document in completed) {
      final eventId = document.id;
      if (_processingLiveEventIds.contains(eventId) ||
          _handledLiveEventIds.contains(eventId)) {
        continue;
      }
      _processingLiveEventIds.add(eventId);
      _liveEventApplyChain = _liveEventApplyChain
          .catchError((Object error, StackTrace stackTrace) {
            print('Previous live event failed: $error');
          })
          .then((_) => _applyLiveEventDocument(document))
          .whenComplete(() => _processingLiveEventIds.remove(eventId));
    }
  }

  Future<void> _applyLiveEventDocument(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) async {
    final payload = document.data();
    if (payload == null || payload['status']?.toString() != 'completed') {
      return;
    }
    await _ensureHandledLiveEventsLoaded();
    if (_handledLiveEventIds.contains(document.id)) return;

    final uploadId = payload['uploadId']?.toString() ?? '';
    if (uploadId.isNotEmpty && _ownUploadIds.contains(uploadId)) {
      await _markLiveEventHandled(document.id);
      return;
    }

    final latestFullSnapshotAt = await _readLatestFullSnapshotWatermark();
    final eventCompletedAt = _firestoreDate(
      payload['completedAt'] ?? payload['createdAt'],
    );
    if (latestFullSnapshotAt != null &&
        eventCompletedAt != null &&
        !eventCompletedAt.isAfter(latestFullSnapshotAt)) {
      await _markLiveEventHandled(document.id);
      return;
    }

    final rawData = payload['data'];
    if (rawData is! Map) {
      await _markLiveEventHandled(document.id);
      return;
    }
    final data = <String, dynamic>{};
    for (final entry in rawData.entries) {
      final table = entry.key.toString();
      final rows = entry.value;
      if (table.isEmpty || rows is! List) continue;
      data[table] = rows;
    }
    if (data.isEmpty) {
      await _markLiveEventHandled(document.id);
      return;
    }

    while (_isLocalWriteInProgress) {
      await Future<void>.delayed(const Duration(milliseconds: 75));
    }

    _beginRestore();
    try {
      await _db.importAllData(data, mergeAllData: true);
      await _markLiveEventHandled(document.id);
      _dbUpdateController.add('live_event_applied');
      onDataRestored?.call();
      if (await _hasPendingTransactions()) {
        _localSyncQueuedAfterRestore = true;
      }
    } catch (error) {
      print('Could not apply live event ${document.id}: $error');
      rethrow;
    } finally {
      _endRestore();
    }
  }

  void _queueDeltaSnapshot(QuerySnapshot<Map<String, dynamic>> snapshot) {
    final completed =
        snapshot.docChanges.map((change) => change.doc).where((doc) {
          final data = doc.data();
          if (data == null || data['status']?.toString() != 'completed') {
            return false;
          }
          if (_latestFullCompactedDeltaIds.contains(doc.id)) {
            return false;
          }
          final latestSnapshotAt = _latestFullSnapshotCompletedAt;
          final deltaCompletedAt = _firestoreDate(
            data['completedAt'] ?? data['createdAt'],
          );
          if (latestSnapshotAt != null &&
              deltaCompletedAt != null &&
              !deltaCompletedAt.isAfter(latestSnapshotAt)) {
            return false;
          }
          return true;
        }).toList()..sort((left, right) {
          final leftTime =
              _firestoreDate(
                left.data()!['completedAt'],
              )?.millisecondsSinceEpoch ??
              0;
          final rightTime =
              _firestoreDate(
                right.data()!['completedAt'],
              )?.millisecondsSinceEpoch ??
              0;
          final timeResult = leftTime.compareTo(rightTime);
          return timeResult != 0 ? timeResult : left.id.compareTo(right.id);
        });

    for (final document in completed) {
      final deltaId = document.id;
      if (_processingDeltaIds.contains(deltaId) ||
          _handledDeltaIds.contains(deltaId)) {
        continue;
      }
      _processingDeltaIds.add(deltaId);
      _deltaApplyChain = _deltaApplyChain
          .catchError((Object error, StackTrace stackTrace) {
            print('Previous cloud delta failed: $error');
          })
          .then((_) => _applyDeltaDocument(document))
          .whenComplete(() => _processingDeltaIds.remove(deltaId));
    }
  }

  Future<void> _applyDeltaDocument(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) async {
    final payload = document.data();
    if (payload == null || payload['status']?.toString() != 'completed') {
      return;
    }
    await _ensureHandledDeltasLoaded();
    if (_handledDeltaIds.contains(document.id)) return;

    final uploadId = payload['uploadId']?.toString() ?? '';
    if (uploadId.isNotEmpty && _ownUploadIds.contains(uploadId)) {
      await _markDeltaHandled(document.id);
      return;
    }

    final latestFullSnapshotAt = await _readLatestFullSnapshotWatermark();
    if (_latestFullCompactedDeltaIds.contains(document.id)) {
      // This change is already contained in the newer full recovery snapshot.
      await _markDeltaHandled(document.id);
      return;
    }
    final deltaCompletedAt = _firestoreDate(
      payload['completedAt'] ?? payload['createdAt'],
    );
    if (latestFullSnapshotAt != null &&
        deltaCompletedAt != null &&
        !deltaCompletedAt.isAfter(latestFullSnapshotAt)) {
      // Old delta documents may remain in Firestore. A newer full snapshot has
      // already folded them in, so replaying them on every app start only slows
      // new devices and desktop clients down.
      await _markDeltaHandled(document.id);
      return;
    }

    while (_isLocalWriteInProgress) {
      await Future<void>.delayed(const Duration(milliseconds: 75));
    }

    _beginRestore();
    try {
      final chunks = await _fetchChunkPages(
        document.reference.collection('chunks'),
        timeout: const Duration(seconds: 30),
      );
      final assembledData = _assembleChunkedData(chunks, uploadId: uploadId);
      final expectedCounts = payload['tableRowCounts'];
      if (expectedCounts is Map) {
        for (final entry in expectedCounts.entries) {
          final expected = (entry.value as num?)?.toInt();
          if (expected == null) continue;
          final actual = assembledData[entry.key.toString()]?.length ?? 0;
          if (actual != expected) {
            throw StateError(
              'Incomplete delta table ${entry.key}: '
              'expected $expected, received $actual.',
            );
          }
        }
      }

      await _db.importAllData(assembledData, mergeAllData: true);
      await _markDeltaHandled(document.id);
      _dbUpdateController.add('cloud_delta_applied');
      onDataRestored?.call();
      if (await _hasPendingTransactions()) {
        _localSyncQueuedAfterRestore = true;
      }
    } catch (error) {
      print('Could not apply cloud delta ${document.id}: $error');
      rethrow;
    } finally {
      _endRestore();
    }
  }

  Future<Set<String>> _refreshDeltasFromCloud() async {
    final workshopId = _workshopId;
    if (workshopId == null || workshopId.isEmpty) return <String>{};
    final snapshot = await _firestore
        .collection('workshops')
        .doc(workshopId)
        .collection('backups')
        .where('kind', isEqualTo: 'delta')
        .orderBy(FieldPath.documentId, descending: true)
        .limit(_deltaQueryLimit)
        .get(GetOptions(source: Source.server))
        .timeout(const Duration(seconds: 20));
    _queueDeltaSnapshot(snapshot);
    await _deltaApplyChain;
    return snapshot.docs
        .where((doc) => doc.data()['status']?.toString() == 'completed')
        .map((doc) => doc.id)
        .toSet();
  }

  /// يحذف مستندات الـdelta التي أصبحت جزءاً من نسخة كاملة مؤكدة (موجودة في
  /// compactedDeltaIds)، بما فيها مجلد chunks الفرعي لكل واحد منها.
  ///
  /// ⚠️ [توفير حصة Firebase]: بدون هذا التنظيف، تتراكم مستندات الـdelta إلى
  /// ما لا نهاية، وتُقرأ (كلها أو جزء كبير منها) في كل استعلام delta لاحق حتى
  /// لو كانت قديمة ومُعالجة أصلاً — وهذا كان السبب الرئيسي لتجاوز حصة القراءة
  /// اليومية. يعمل هذا التنظيف في الخلفية بعد نجاح كل نسخة كاملة، ولا يوقف أو
  /// يُبطئ عملية الرفع نفسها إن فشل لأي سبب.
  Future<void> _deleteCompactedDeltaDocuments(Set<String> deltaIds) async {
    if (deltaIds.isEmpty || _workshopId == null || _workshopId!.isEmpty) {
      return;
    }
    final backupsRef = _firestore
        .collection('workshops')
        .doc(_workshopId)
        .collection('backups');

    for (final deltaId in deltaIds) {
      try {
        final deltaRef = backupsRef.doc(deltaId);
        final chunkDocs = await deltaRef
            .collection('chunks')
            .get(GetOptions(source: Source.server))
            .timeout(const Duration(seconds: 20));
        if (chunkDocs.docs.isNotEmpty) {
          var deleteBatch = _firestore.batch();
          var count = 0;
          for (final chunkDoc in chunkDocs.docs) {
            deleteBatch.delete(chunkDoc.reference);
            count++;
            if (count >= 300) {
              await deleteBatch.commit().timeout(const Duration(seconds: 25));
              deleteBatch = _firestore.batch();
              count = 0;
            }
          }
          if (count > 0) {
            await deleteBatch.commit().timeout(const Duration(seconds: 25));
          }
        }
        await deltaRef.delete().timeout(const Duration(seconds: 10));
      } catch (error) {
        // Best-effort cleanup only. A delta that fails to delete simply stays
        // around for the next cleanup attempt; it never blocks a backup.
        print('Could not delete compacted delta $deltaId: $error');
      }
    }
  }

  /// يحذف مستندات النسخ الكاملة القديمة (`snapshot_*`) وملفاتها الفرعية
  /// (chunks) بعد أن تصبح نسخة جديدة هي المعتمدة (`activeSnapshotId`)،
  /// ويُبقي فقط على [_keepPreviousFullSnapshots] نسخة سابقة كاحتياط أمان.
  ///
  /// ⚠️ [توفير حصة Firebase]: بدون هذا التنظيف، تبقى كل نسخة كاملة قديمة إلى
  /// الأبد في السحابة (تستهلك مساحة تخزين، وتُحسب ضمن أي عملية جرد/فحص
  /// مستقبلية على المجموعة). يعمل في الخلفية ولا يوقف نجاح الرفع الحالي.
  Future<void> _cleanupObsoleteFullSnapshots(
    DocumentReference<Map<String, dynamic>> latestDocRef, {
    required String keepSnapshotId,
  }) async {
    if (_workshopId == null || _workshopId!.isEmpty) return;
    try {
      final backupsRef = latestDocRef.parent;
      // Prefix query on the document id: every full-snapshot document id
      // starts with "snapshot_", so this range matches exactly that family
      // without needing any extra field or composite index.
      final snapshotDocs = await backupsRef
          .where(FieldPath.documentId, isGreaterThanOrEqualTo: 'snapshot_')
          .where(FieldPath.documentId, isLessThan: 'snapshot_\uf8ff')
          .orderBy(FieldPath.documentId, descending: true)
          .get(GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 25));

      var keptExtra = 0;
      for (final doc in snapshotDocs.docs) {
        if (doc.id == keepSnapshotId) continue;
        if (keptExtra < _keepPreviousFullSnapshots) {
          keptExtra++;
          continue;
        }
        try {
          final chunkDocs = await doc.reference
              .collection('chunks')
              .get(GetOptions(source: Source.server))
              .timeout(const Duration(seconds: 25));
          if (chunkDocs.docs.isNotEmpty) {
            var deleteBatch = _firestore.batch();
            var count = 0;
            for (final chunkDoc in chunkDocs.docs) {
              deleteBatch.delete(chunkDoc.reference);
              count++;
              if (count >= 300) {
                await deleteBatch.commit().timeout(const Duration(seconds: 25));
                deleteBatch = _firestore.batch();
                count = 0;
              }
            }
            if (count > 0) {
              await deleteBatch.commit().timeout(const Duration(seconds: 25));
            }
          }
          await doc.reference.delete().timeout(const Duration(seconds: 10));
        } catch (error) {
          print('Could not delete obsolete snapshot ${doc.id}: $error');
        }
      }
    } catch (error) {
      print('Obsolete full snapshot cleanup failed: $error');
    }
  }

  Future<void> _applyLatestBackupUpdate(Map<String, dynamic> payload) async {
    if (payload['status']?.toString() != 'completed') return;
    final supabaseWorkshopSync = SupabaseWorkshopSyncService();
    if (supabaseWorkshopSync.isSignedIn) {
      try {
        await supabaseWorkshopSync.downloadWorkshopData();
      } catch (error) {
        print('Supabase preferred workshop refresh failed: $error');
      }
      return;
    }
    _rememberFullSnapshotMetadata(payload);
    if (_isLocalWriteInProgress) {
      _refreshQueuedAfterLocalWrite = true;
      return;
    }
    if (_isRestoring) {
      _refreshQueuedAfterRestore = true;
      return;
    }

    final fingerprint = _backupFingerprint(payload);
    if (fingerprint.isEmpty || fingerprint == _lastHandledBackupFingerprint) {
      return;
    }

    final uploadId = payload['uploadId']?.toString() ?? '';

    // uploadId is unique to this running app process. Unlike a persisted
    // deviceId, it cannot accidentally be duplicated when Android restores
    // application preferences onto another phone.
    final isOwnUpload = uploadId.isNotEmpty && _ownUploadIds.contains(uploadId);
    if (isOwnUpload) {
      await _rememberHandledBackupFingerprint(fingerprint);
      return;
    }

    // A small live event/delta is the authoritative fast path for a local
    // change. Do not start a full snapshot preflight here: it can wait behind
    // a large backup and produce the misleading "protected local data"
    // warning even though the changed rows are already being published.
    // The 20-second health check will apply this full snapshot after the
    // pending delta is acknowledged.
    if (await _hasPendingTransactions()) {
      _queueImmediateLiveEventUpload();
      return;
    }

    // An incoming update must not replace a record that exists only on this
    // phone. This applies to background real-time downloads as well as the
    // manual refresh button: publish and verify local work first.
    bool hasPendingLocalChanges;
    try {
      hasPendingLocalChanges =
          await _publishPendingTransactionsBeforeCloudRestore();
    } catch (error) {
      _sendSyncFeedback(
        CloudSyncFeedbackType.uploadFailed,
        'تم إيقاف تنزيل تحديث الورشة لحماية بيانات هذا الجهاز.',
        details:
            '${_describeCloudWriteFailure(error)}\n'
            'سيُعاد التنزيل فقط بعد تأكيد رفع التغييرات المحلية.',
      );
      return;
    }

    final rowCounts = payload['tableRowCounts'];
    final ordersCount = rowCounts is Map
        ? (rowCounts['Commandes'] as num?)?.toInt()
        : null;
    final clientsCount = rowCounts is Map
        ? (rowCounts['Client'] as num?)?.toInt()
        : null;
    final caissesCount = rowCounts is Map
        ? (rowCounts['Caisses'] as num?)?.toInt()
        : null;
    final treasuryCount = rowCounts is Map
        ? (rowCounts['Treasury'] as num?)?.toInt()
        : null;
    final receivedTableCount = rowCounts is Map ? rowCounts.length : null;
    final receivedRowCount = rowCounts is Map
        ? rowCounts.values.fold<int>(
            0,
            (total, value) => total + ((value as num?)?.toInt() ?? 0),
          )
        : null;
    final uploaderRole = payload['uploaderRole']?.toString() ?? '';
    final uploaderLabel = switch (uploaderRole) {
      'worker' => 'عامل',
      'co_manager' => 'مدير مساعد',
      'manager' => 'مدير ورشة',
      'admin' => 'مدير التطبيق',
      _ => '',
    };
    _sendSyncFeedback(
      CloudSyncFeedbackType.downloadStarted,
      'تم اكتشاف تحديث جديد، يجري تنزيله الآن…',
      details: [
        if (receivedTableCount != null && receivedRowCount != null)
          'قاعدة كاملة: $receivedTableCount جدول • $receivedRowCount سجل',
        if (ordersCount != null) 'الطلبات: $ordersCount',
        if (clientsCount != null) 'الزبائن: $clientsCount',
        if (caissesCount != null) 'الصناديق: $caissesCount',
        if (treasuryCount != null) 'حركات الخزينة: $treasuryCount',
        if (uploaderLabel.isNotEmpty) 'المصدر: $uploaderLabel',
        'الورشة: $_workshopId',
      ].join(' • '),
    );

    _beginRestore();
    try {
      await restoreFromCloud(
        keepPendingChanges: hasPendingLocalChanges,
        publishPendingChangesFirst: false,
      );
      await _rememberHandledBackupFingerprint(fingerprint);
      _dbUpdateController.add('cloud_restored');
      _sendSyncFeedback(
        CloudSyncFeedbackType.downloadSucceeded,
        'تم استلام تحديث جديد من السحابة.',
        details: 'الورشة: $_workshopId',
      );
      onDataRestored?.call();
      if (hasPendingLocalChanges) {
        // importAllData merges transactional tables. Publish that merged local
        // result only after the incoming snapshot has been applied.
        _localSyncQueuedAfterRestore = true;
      }
    } catch (e) {
      print('Error auto-restoring from cloud: $e');
      _sendSyncFeedback(
        CloudSyncFeedbackType.downloadFailed,
        'وصل التحديث، لكن فشل تنزيله على هذا الهاتف.',
        details:
            '${_describeCloudWriteFailure(e)}\n'
            'المسار: workshops/$_workshopId/backups/latest/chunks',
      );
    } finally {
      _endRestore();
    }
  }

  void _beginRestore() {
    if (_restoreDepth == 0) {
      _restoreIdleCompleter = Completer<void>();
    }
    _restoreDepth++;
  }

  void _endRestore() {
    if (_restoreDepth > 0) _restoreDepth--;
    if (_restoreDepth != 0) return;
    if (!(_restoreIdleCompleter?.isCompleted ?? true)) {
      _restoreIdleCompleter!.complete();
    }
    _restoreIdleCompleter = null;

    if (_localSyncQueuedAfterRestore) {
      _localSyncQueuedAfterRestore = false;
      _queueImmediateLiveEventUpload();
      scheduleMicrotask(_silentBackup);
    }

    if (_catalogRefreshQueuedAfterRestore) {
      _catalogRefreshQueuedAfterRestore = false;
      scheduleMicrotask(_refreshGlobalCatalogFromCloudIfChanged);
    }

    if (_refreshQueuedAfterRestore) {
      _refreshQueuedAfterRestore = false;
      scheduleMicrotask(refreshFromCloudIfChanged);
    }
  }

  Future<void> _applyGlobalCatalogUpdate(Map<String, dynamic> payload) async {
    if (payload['status']?.toString() != 'completed') return;
    if (_isRestoring) {
      // The listener's first event can arrive while the yellow start screen is
      // still importing workshop data. Queue it instead of discarding the
      // catalogue update, especially on a worker's first login.
      _catalogRefreshQueuedAfterRestore = true;
      return;
    }

    final fingerprint = _catalogFingerprint(payload);
    if (fingerprint.isEmpty || fingerprint == _lastHandledCatalogFingerprint) {
      return;
    }
    final uploadId = payload['uploadId']?.toString() ?? '';
    if (uploadId.isNotEmpty && _ownUploadIds.contains(uploadId)) {
      _lastHandledCatalogFingerprint = fingerprint;
      return;
    }
    if (await _hasUnpublishedCatalogChanges()) {
      print('Ignoring cloud catalog while local catalog changes await upload.');
      return;
    }
    try {
      await downloadGlobalCatalog();
      _lastHandledCatalogFingerprint = fingerprint;
    } catch (error) {
      print('Automatic catalog download failed: $error');
    }
  }

  Future<void> _refreshGlobalCatalogFromCloudIfChanged() async {
    if (_isRestoring) {
      _catalogRefreshQueuedAfterRestore = true;
      return;
    }
    try {
      final doc = await _catalogDocument()
          .get(GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 15));
      if (!doc.exists || doc.data() == null) return;
      await _applyGlobalCatalogUpdate(
        Map<String, dynamic>.from(doc.data() as Map),
      );
    } catch (error) {
      print('Catalog sync health check failed: $error');
    }
  }

  /// Public fallback used on app resume and by the periodic health check.
  /// It repairs a dropped Firestore listener instead of leaving an old local
  /// database visible for hours.
  Future<void> refreshFromCloudIfChanged() async {
    if (_isLocalWriteInProgress) {
      _refreshQueuedAfterLocalWrite = true;
      return;
    }
    if (_isRestoring || _isCheckingCloudChanges || _workshopId == null) return;
    if (_auth.currentUser == null) return;

    _isCheckingCloudChanges = true;
    try {
      final supabaseWorkshopSync = SupabaseWorkshopSyncService();
      if (supabaseWorkshopSync.isSignedIn) {
        await supabaseWorkshopSync.downloadWorkshopData();
        await _refreshPermissionsFromCloudIfChanged();
        return;
      }

      final doc = await _firestore
          .collection('workshops')
          .doc(_workshopId)
          .collection('backups')
          .doc('latest')
          .get(GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 15));
      if (doc.exists && doc.data() != null) {
        await _applyLatestBackupUpdate(
          Map<String, dynamic>.from(doc.data() as Map),
        );
      }

      // A worker normally reaches the manager through an immutable delta, not
      // by replacing `backups/latest`. If a real-time callback was briefly
      // interrupted on the manager's phone, checking only `latest` would miss
      // that worker addition forever. Re-read unapplied completed deltas as a
      // reliable fallback; handled IDs make this safe and idempotent.
      await _refreshDeltasFromCloud();

      // نفس منطق الحماية ينطبق على الصلاحيات: لو انقطع مستمع Firestore
      // للحظات (استئناف التطبيق من الخلفية مثلاً)، نعيد قراءة مستند
      // المستخدم من الخادم هنا حتى لا تبقى صلاحية قديمة معروضة للعامل.
      await _refreshPermissionsFromCloudIfChanged();
    } catch (e) {
      print('Cloud sync health check failed: $e');
    } finally {
      _isCheckingCloudChanges = false;
    }
  }

  /// إعادة قراءة صلاحيات هذا الحساب من الخادم مباشرة (وليس من الكاش
  /// المحلي لـ Firestore) كحل احتياطي عندما ينقطع مستمع `_permissionsListener`.
  Future<void> _refreshPermissionsFromCloudIfChanged() async {
    final user = _auth.currentUser;
    if (user == null) return;
    try {
      final doc = await _firestore
          .collection('users')
          .doc(user.uid)
          .get(GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 10));
      if (!doc.exists || doc.data() == null) return;
      await _applyPermissionsUpdate(doc.data()!);
    } catch (error) {
      print('Permissions sync health check failed: $error');
    }
  }

  void _scheduleRealtimeListenerRetry([Object? error, StackTrace? stackTrace]) {
    if (error != null) {
      print('Realtime listener stopped: $error');
      final now = DateTime.now();
      if (_lastRealtimeErrorFeedbackAt == null ||
          now.difference(_lastRealtimeErrorFeedbackAt!) >
              const Duration(seconds: 30)) {
        _lastRealtimeErrorFeedbackAt = now;
        _sendSyncFeedback(
          CloudSyncFeedbackType.downloadFailed,
          'توقف استقبال تحديثات الورشة مؤقتاً.',
          details:
              '${_describeCloudWriteFailure(error)}\n'
              'ستتم إعادة المحاولة تلقائياً • الورشة: $_workshopId',
        );
      }
    }
    _realtimeRetryTimer?.cancel();
    _realtimeRetryTimer = Timer(const Duration(seconds: 5), () async {
      if (_auth.currentUser == null) return;
      startListeningForUpdates(onDataRestored ?? () {});
    });
  }

  // ⚠️ [توفير حصة Firebase]: كانت هذه القيمة 20 ثانية، وهي كافية جداً كشبكة
  // أمان احتياطية لأن التحديثات الحقيقية تصل أصلاً بشكل لحظي عبر المستمعين
  // (_listener, _deltaListener, _liveEventListener, _permissionsListener).
  // فحص كل 20 ثانية لكل جهاز متصل يستهلك آلاف عمليات القراءة يومياً لكل جهاز
  // بمفرده، ويتجاوز حد خطة Spark المجاني (50 ألف قراءة/يوم) بسرعة كبيرة مع
  // عدة عمال متصلين. رُفعت المدة إلى 3 دقائق لتقليل الاستهلاك اليومي بنسبة
  // تفوق 99% دون أي تأثير ملموس على سرعة المزامنة اللحظية الفعلية.
  static const Duration _realtimeHealthCheckInterval = Duration(minutes: 3);

  void _startRealtimeHealthCheck() {
    _realtimeHealthTimer?.cancel();
    _realtimeHealthTimer = Timer.periodic(_realtimeHealthCheckInterval, (_) {
      _runRealtimeHealthCheck();
    });
    _runRealtimeHealthCheck();
  }

  void _startPendingCloudChangePoll() {
    _pendingCloudChangePollTimer?.cancel();
    _pendingCloudChangePollTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => _publishPendingLocalRowsIfNeeded(),
    );
  }

  Future<void> _publishPendingLocalRowsIfNeeded() async {
    if (_isRestoring ||
        _isLocalWriteInProgress ||
        _isSilentBackupRunning ||
        _auth.currentUser == null ||
        _workshopId == null ||
        _workshopId!.isEmpty) {
      return;
    }

    try {
      if (await _db.hasPendingCloudChanges()) {
        _silentBackup();
      }
    } catch (error) {
      print('Pending local cloud-change poll failed: $error');
    }
  }

  /// A database trigger records every local row change, but older screens do
  /// not all call [notifyChange] after writing their data.  Do not leave those
  /// worker-side changes on one phone forever: the periodic health check also
  /// checks the durable change log and publishes it when necessary.
  Future<void> _runRealtimeHealthCheck() async {
    await refreshFromCloudIfChanged();
    if (_isRestoring || _isLocalWriteInProgress) return;

    try {
      final supabaseWorkshopSync = SupabaseWorkshopSyncService();
      if (supabaseWorkshopSync.isSignedIn) {
        if (await _db.hasPendingCloudChanges()) {
          supabaseWorkshopSync.notifyLocalChange(immediate: true);
        }
        await _clearFirebaseTransactionalPendingFlag();
        return;
      }
      final hasUnpublishedRows = await _db.hasPendingCloudChanges();
      if (hasUnpublishedRows || await _hasPendingTransactions()) {
        await _silentBackup();
      } else {
        await _reconcileTransactionalCountsWithCloud();
      }
    } catch (error) {
      print('Local cloud-change health check failed: $error');
    }
  }

  Future<void> _reconcileTransactionalCountsWithCloud() async {
    if (_isReconcilingTransactionalCounts ||
        _isRestoring ||
        _isLocalWriteInProgress ||
        _isSilentBackupRunning ||
        _auth.currentUser == null ||
        _workshopId == null ||
        _workshopId!.isEmpty) {
      return;
    }

    final now = DateTime.now();
    final lastRun = _lastTransactionalCountReconcileAt;
    if (lastRun != null &&
        now.difference(lastRun) < const Duration(seconds: 45)) {
      return;
    }

    _isReconcilingTransactionalCounts = true;
    _lastTransactionalCountReconcileAt = now;
    try {
      Map<String, dynamic>? payload;
      try {
        final state = await _transactionalSyncStateDocument()
            .get(GetOptions(source: Source.server))
            .timeout(const Duration(seconds: 10));
        payload = state.data();
      } catch (error) {
        print('Could not read live transactional sync state: $error');
      }

      if (payload == null || payload['status']?.toString() != 'completed') {
        final latest = await _firestore
            .collection('workshops')
            .doc(_workshopId)
            .collection('backups')
            .doc('latest')
            .get(GetOptions(source: Source.server))
            .timeout(const Duration(seconds: 10));
        payload = latest.data();
        if (payload == null || payload['status']?.toString() != 'completed') {
          return;
        }
      }

      final rowCounts = payload['tableRowCounts'];
      if (rowCounts is! Map) return;

      final localCounts = await _db.readSyncTableCounts(
        _watchedTransactionalCountTables,
      );

      var localHasRowsMissingFromCloud = false;
      var cloudHasRowsMissingLocally = false;
      final differences = <String>[];
      for (final table in _watchedTransactionalCountTables) {
        final local = localCounts[table] ?? 0;
        final cloud = (rowCounts[table] as num?)?.toInt();
        if (cloud == null) continue;
        if (local > cloud) {
          localHasRowsMissingFromCloud = true;
          differences.add('$table: local $local > cloud $cloud');
        } else if (cloud > local) {
          cloudHasRowsMissingLocally = true;
          differences.add('$table: cloud $cloud > local $local');
        }
      }

      if (localHasRowsMissingFromCloud) {
        _sendSyncFeedback(
          CloudSyncFeedbackType.uploadStarted,
          'تم اكتشاف فرق في عدد الطلبات، يجري تصحيح نسخة السحابة.',
          details: differences.join(' • '),
        );
        await backupToCloud(isSilent: true, forceFullSnapshot: true);
      } else if (cloudHasRowsMissingLocally) {
        _sendSyncFeedback(
          CloudSyncFeedbackType.downloadStarted,
          'تم اكتشاف بيانات أحدث في السحابة، يجري تنزيلها.',
          details: differences.join(' • '),
        );
        await refreshFromCloudIfChanged();
      }
    } catch (error) {
      print('Transactional count reconciliation failed: $error');
    } finally {
      _isReconcilingTransactionalCounts = false;
    }
  }

  void stopListening() {
    _realtimeRetryTimer?.cancel();
    _realtimeHealthTimer?.cancel();
    _pendingCloudChangePollTimer?.cancel();
    _pendingTransactionUploadTimer?.cancel();
    _listener?.cancel();
    _catalogListener?.cancel();
    _deltaListener?.cancel();
    _liveEventListener?.cancel();
    _statusListener?.cancel();
    _orderStatusListener?.cancel();
    _measurementsListener?.cancel();
    _deletionsListener?.cancel();
    _orderDeletionsListener?.cancel();
    _permissionsListener?.cancel();
    _listener = null;
    _catalogListener = null;
    _deltaListener = null;
    _liveEventListener = null;
    _statusListener = null;
    _orderStatusListener = null;
    _measurementsListener = null;
    _deletionsListener = null;
    _orderDeletionsListener = null;
    _permissionsListener = null;
    _pendingCloudChangePollTimer = null;
    _pendingTransactionUploadTimer = null;
  }

  /// إشعار بوجود تغيير محلي ليتم رفعه للسحابة (Debounced)
  void notifyChange() async {
    _dbUpdateController.add('');
    final supabaseWorkshopSync = SupabaseWorkshopSyncService();
    _backupRetryTimer?.cancel();

    if (supabaseWorkshopSync.isSignedIn) {
      if (_isLocalWriteInProgress) {
        _backupQueuedAfterLocalWrite = true;
        return;
      }
      if (_isRestoring) {
        _localSyncQueuedAfterRestore = true;
        return;
      }
      supabaseWorkshopSync.notifyLocalChange();
      await _clearFirebaseTransactionalPendingFlag();
      return;
    }

    if (supabaseWorkshopDataOnly) {
      _sendSyncFeedback(
        CloudSyncFeedbackType.uploadSkipped,
        'لم يتم رفع التغيير لأن جلسة Supabase غير مفتوحة.',
        details: 'تم إيقاف مسار Firebase لبيانات الورشة نهائياً.',
      );
      return;
    }

    _queueImmediateLiveEventUpload();

    try {
      final prefs = await SharedPreferences.getInstance();
      await _markTransactionalChangesPending(prefs);
      final userRole = prefs.getString('user_role') ?? 'worker';
      if (userRole == 'worker') {
        // Do not mark a worker's local copy as authoritative (that would
        // block incoming manager updates), but do schedule the upload.
      } else {
        await prefs.setBool('is_local_dirty', true);
      }
    } catch (e) {
      print('Failed to set local dirty flag: $e');
    }

    if (_isLocalWriteInProgress) {
      _backupQueuedAfterLocalWrite = true;
      return;
    }

    if (_isRestoring) {
      // Do not lose a save made while the first cloud restore is still
      // running. This was especially visible on worker phones just after
      // opening the app.
      _localSyncQueuedAfterRestore = true;
      return;
    }

    if (_debounceTimer?.isActive ?? false) _debounceTimer!.cancel();
    // A normal save (an order, customer or payment) must reach the workshop
    // immediately. A short debounce still groups the rows created together
    // while saving one order, without leaving a worker's change pending.
    _debounceTimer = Timer(const Duration(milliseconds: 250), () {
      _silentBackup();
    });
  }

  /// إشعار بوجود تغيير عاجل محلياً (كعمليات الصندوق والمعاملات المالية) والرفع الفوري للسحابة بدون انتظار
  void notifyChangeImmediate() async {
    _dbUpdateController.add('');
    final supabaseWorkshopSync = SupabaseWorkshopSyncService();
    _backupRetryTimer?.cancel();

    if (supabaseWorkshopSync.isSignedIn) {
      if (_isLocalWriteInProgress) {
        _backupQueuedAfterLocalWrite = true;
        return;
      }
      if (_isRestoring) {
        _localSyncQueuedAfterRestore = true;
        return;
      }
      supabaseWorkshopSync.notifyLocalChange(immediate: true);
      await _clearFirebaseTransactionalPendingFlag();
      return;
    }

    if (supabaseWorkshopDataOnly) {
      _sendSyncFeedback(
        CloudSyncFeedbackType.uploadSkipped,
        'لم يتم رفع التغيير لأن جلسة Supabase غير مفتوحة.',
        details: 'تم إيقاف مسار Firebase لبيانات الورشة نهائياً.',
      );
      return;
    }

    _queueImmediateLiveEventUpload();

    try {
      final prefs = await SharedPreferences.getInstance();
      await _markTransactionalChangesPending(prefs);
      final userRole = prefs.getString('user_role') ?? 'worker';
      if (userRole != 'worker') {
        await prefs.setBool('is_local_dirty', true);
      }
    } catch (e) {
      print('Failed to set local dirty flag: $e');
    }

    if (_isLocalWriteInProgress) {
      _backupQueuedAfterLocalWrite = true;
      return;
    }

    if (_isRestoring) {
      _localSyncQueuedAfterRestore = true;
      return;
    }

    if (_debounceTimer?.isActive ?? false) _debounceTimer!.cancel();
    _silentBackup();
  }

  /// Saves every local catalogue edit to the workshop backup. Publishing to
  /// the central catalogue is an additional, admin-only operation.
  Future<void> notifyCatalogChange({bool uploadImmediately = false}) async {
    // Catalogue tables are database tables too, so every editor's changes
    // belong in their workshop backup, regardless of role.
    notifyChange();
    _dbUpdateController.add('catalog_changed');

    try {
      await init();
      final prefs = await SharedPreferences.getInstance();
      if (!_canPublishGlobalCatalog(prefs.getString('user_role') ?? 'worker')) {
        // Non-admin edits are already queued above, but must not overwrite
        // the application-wide catalogue.
        print('Skipping central catalog publish for a non-admin account.');
        return;
      }
    } catch (e) {
      print('Failed to schedule catalog sync: $e');
      return;
    }

    // Mark the local edit before the listener can import an older catalogue.
    await _markCatalogDirty();

    if (uploadImmediately) {
      _catalogDebounceTimer?.cancel();
      unawaited(
        backupGlobalCatalog().catchError((e) {
          print('Immediate catalog sync failed: $e');
          _scheduleCatalogUploadRetry();
        }),
      );
      return;
    }

    _catalogDebounceTimer?.cancel();
    _catalogDebounceTimer = Timer(const Duration(seconds: 2), () async {
      try {
        await backupGlobalCatalog();
      } catch (e) {
        print('Automatic catalog sync failed: $e');
        _scheduleCatalogUploadRetry();
      }
    });
  }

  /// إشعار بتعديل صلاحيات عامل من شاشة "إدارة العمال" (يستدعيها المدير فقط).
  /// يكتب مباشرة إلى مستند users/{workerUid} في Firestore، بحيث يستلم هاتف
  /// العامل التحديث فوراً عبر [_permissionsListener] دون انتظار أي نسخة
  /// احتياطية كاملة أو إعادة تشغيل التطبيق.
  Future<void> updateWorkerPermissions({
    required String workerUid,
    required Map<String, dynamic> permissions,
  }) async {
    final manager = _auth.currentUser;
    if (manager == null) {
      throw Exception('يجب تسجيل الدخول أولاً لتعديل صلاحيات العامل');
    }
    try {
      await _firestore.collection('users').doc(workerUid).set({
        'permissions': permissions,
        'permissions_updated_at': FieldValue.serverTimestamp(),
        'permissions_updated_by': manager.uid,
      }, SetOptions(merge: true));
    } catch (e) {
      throw Exception(
        'فشل تحديث صلاحيات العامل: ${_describeCloudWriteFailure(e)}',
      );
    }
  }

  void _scheduleCatalogUploadRetry() {
    _catalogRetryTimer?.cancel();
    _catalogRetryTimer = Timer(const Duration(seconds: 30), () async {
      if (!await _hasUnpublishedCatalogChanges()) return;
      try {
        await backupGlobalCatalog();
      } catch (error) {
        print('Catalog upload retry failed: $error');
        _scheduleCatalogUploadRetry();
      }
    });
  }

  /// الرفع الصامت للسحابة
  Future<void> _silentBackup() async {
    if (_isRestoring) {
      _localSyncQueuedAfterRestore = true;
      return;
    }
    final supabaseWorkshopSync = SupabaseWorkshopSyncService();
    if (supabaseWorkshopSync.isSignedIn) {
      try {
        await supabaseWorkshopSync.uploadPendingChanges();
        await _clearFirebaseTransactionalPendingFlag();
      } catch (error) {
        print('Supabase auto-sync upload failed: $error');
      }
      return;
    }
    if (supabaseWorkshopDataOnly) return;
    if (_isSilentBackupRunning) {
      // Preserve only one follow-up upload. It contains the newest local
      // state and prevents older, overlapping snapshots from winning.
      _silentBackupQueued = true;
      return;
    }

    try {
      _isSilentBackupRunning = true;
      do {
        _silentBackupQueued = false;
        await backupToCloud(isSilent: true);
      } while (_silentBackupQueued && !_isRestoring);
    } catch (e) {
      print('Auto-sync backup failed: $e');
      _scheduleBackupRetry();
    } finally {
      _isSilentBackupRunning = false;
    }
  }

  void _scheduleBackupRetry() {
    _backupRetryTimer?.cancel();
    _backupRetryTimer = Timer(const Duration(seconds: 5), () {
      _silentBackup();
    });
  }

  /// Publishes the changed rows independently of the durable backup queue.
  ///
  /// A full snapshot can legitimately take longer on a large workshop. It
  /// must never delay a one-row customer/order/payment change, so recipients
  /// receive this small event first and the delta/full backup confirms it
  /// afterwards.
  void _queueImmediateLiveEventUpload() {
    final supabaseWorkshopSync = SupabaseWorkshopSyncService();
    if (supabaseWorkshopSync.isSignedIn) {
      if (_isRestoring || _isLocalWriteInProgress) {
        _liveEventUploadQueued = true;
        return;
      }
      supabaseWorkshopSync.notifyLocalChange(immediate: true);
      _clearFirebaseTransactionalPendingFlag();
      return;
    }
    if (supabaseWorkshopDataOnly) return;
    if (_isRestoring || _isLocalWriteInProgress) {
      _liveEventUploadQueued = true;
      return;
    }
    if (_activeLiveEventUpload != null) {
      _liveEventUploadQueued = true;
      return;
    }

    final task = _publishPendingLiveChangesNow();
    _activeLiveEventUpload = task;
    task.whenComplete(() {
      if (!identical(_activeLiveEventUpload, task)) return;
      _activeLiveEventUpload = null;
      if (_liveEventUploadQueued && !_isRestoring && !_isLocalWriteInProgress) {
        _liveEventUploadQueued = false;
        scheduleMicrotask(_queueImmediateLiveEventUpload);
      }
    });
  }

  Future<void> _publishPendingLiveChangesNow() async {
    try {
      if (_auth.currentUser == null) return;
      if (_workshopId == null || _workshopId!.isEmpty) {
        await init();
      }
      if (_workshopId == null ||
          _workshopId!.isEmpty ||
          _isRestoring ||
          _isLocalWriteInProgress) {
        return;
      }

      final pending = await _db.exportPendingCloudChanges();
      if (pending.isEmpty) return;
      final prefs = await SharedPreferences.getInstance();
      final uploadId = _newUploadId();
      _rememberOwnUpload(uploadId);
      await _publishLiveEvent(
        pending: pending,
        uploadId: uploadId,
        prefs: prefs,
      );
    } catch (error) {
      // The durable delta path remains responsible for retrying this change.
      // A transient live-event failure must not interrupt the user's save.
      print('Immediate live change publish failed: $error');
    }
  }

  Future<void> _acquireWorkshopUploadLease(
    DocumentReference<Map<String, dynamic>> latestDocRef,
    String uploadId,
  ) async {
    final deadline = DateTime.now().add(const Duration(seconds: 15));
    var acquiredLease = false;
    try {
      while (DateTime.now().isBefore(deadline)) {
        try {
          final acquired = await _firestore
              .runTransaction<bool>((transaction) async {
                final snapshot = await transaction.get(latestDocRef);
                final data = snapshot.data();
                final now = DateTime.now();

                final queue = <String, Map<String, dynamic>>{};
                final rawQueue = data?['syncUploadQueue'];
                if (rawQueue is Map) {
                  for (final entry in rawQueue.entries) {
                    if (entry.value is! Map) continue;
                    final item = Map<String, dynamic>.from(entry.value as Map);
                    final rawItemExpiry = item['expiresAt'];
                    final itemExpiry = rawItemExpiry is Timestamp
                        ? rawItemExpiry.toDate()
                        : null;
                    if (itemExpiry != null && itemExpiry.isAfter(now)) {
                      queue[entry.key.toString()] = item;
                    }
                  }
                }

                var queueSequence =
                    (data?['syncQueueSequence'] as num?)?.toInt() ?? 0;
                int? inheritedSequence;
                final duplicateEntries = queue.entries
                    .where(
                      (entry) =>
                          entry.key != uploadId &&
                          entry.value['deviceId']?.toString() == _deviceId,
                    )
                    .toList();
                for (final duplicate in duplicateEntries) {
                  final sequence =
                      (duplicate.value['sequence'] as num?)?.toInt() ?? 0;
                  if (sequence > 0 &&
                      (inheritedSequence == null ||
                          sequence < inheritedSequence)) {
                    inheritedSequence = sequence;
                  }
                  queue.remove(duplicate.key);
                }

                final existingQueueItem = queue[uploadId];
                if (existingQueueItem == null) {
                  final sequence = inheritedSequence ?? ++queueSequence;
                  queue[uploadId] = <String, dynamic>{
                    'sequence': sequence,
                    'deviceId': _deviceId,
                    'expiresAt': Timestamp.fromDate(
                      now.add(const Duration(seconds: 12)),
                    ),
                  };
                } else {
                  existingQueueItem['deviceId'] = _deviceId;
                  existingQueueItem['expiresAt'] = Timestamp.fromDate(
                    now.add(const Duration(seconds: 12)),
                  );
                }

                final currentOwner = data?['syncLockOwner']?.toString() ?? '';
                final rawLockExpiry = data?['syncLockExpiresAt'];
                final lockExpiry = rawLockExpiry is Timestamp
                    ? rawLockExpiry.toDate()
                    : null;
                final lockIsFree =
                    currentOwner.isEmpty ||
                    currentOwner == uploadId ||
                    lockExpiry == null ||
                    lockExpiry.isBefore(now);

                if (lockIsFree) {
                  queue.remove(uploadId);
                  transaction.set(latestDocRef, {
                    'syncLockOwner': uploadId,
                    'syncLockExpiresAt': Timestamp.fromDate(
                      now.add(const Duration(seconds: 20)),
                    ),
                    'syncUploadQueue': queue,
                    'syncQueueSequence': queueSequence,
                  }, SetOptions(merge: true));
                  return true;
                }

                transaction.set(latestDocRef, {
                  'syncUploadQueue': queue,
                  'syncQueueSequence': queueSequence,
                }, SetOptions(merge: true));
                return false;
              })
              .timeout(const Duration(seconds: 8));

          if (acquired) {
            acquiredLease = true;
            return;
          }
        } catch (e) {
          print('Workshop lease acquisition retry attempt: $e');
        }

        await Future<void>.delayed(
          Duration(milliseconds: 500 + Random().nextInt(300)),
        );
      }
    } finally {
      if (!acquiredLease) {
        await _removeWorkshopUploadQueueEntry(latestDocRef, uploadId);
      }
    }
    throw TimeoutException(
      'طال انتظار دور هذا الهاتف في مزامنة الورشة. ستتم إعادة المحاولة تلقائياً.',
    );
  }

  Future<void> _removeWorkshopUploadQueueEntry(
    DocumentReference<Map<String, dynamic>> latestDocRef,
    String uploadId,
  ) async {
    try {
      await _firestore
          .runTransaction<void>((transaction) async {
            final snapshot = await transaction.get(latestDocRef);
            final data = snapshot.data();
            final rawQueue = data?['syncUploadQueue'];
            if (rawQueue is! Map || !rawQueue.containsKey(uploadId)) return;
            final queue = Map<String, dynamic>.from(rawQueue);
            queue.remove(uploadId);
            transaction.set(latestDocRef, {
              'syncUploadQueue': queue,
            }, SetOptions(merge: true));
          })
          .timeout(const Duration(seconds: 10));
    } catch (error) {
      print('Could not remove workshop sync queue entry: $error');
    }
  }

  Future<void> _renewWorkshopUploadLease(
    DocumentReference<Map<String, dynamic>> latestDocRef,
    String uploadId,
  ) async {
    try {
      await _firestore
          .runTransaction<void>((transaction) async {
            final snapshot = await transaction.get(latestDocRef);
            if (snapshot.data()?['syncLockOwner']?.toString() != uploadId) {
              return;
            }
            transaction.set(latestDocRef, {
              'syncLockExpiresAt': Timestamp.fromDate(
                DateTime.now().add(const Duration(seconds: 20)),
              ),
            }, SetOptions(merge: true));
          })
          .timeout(const Duration(seconds: 8));
    } catch (error) {
      print('Could not renew workshop sync lease: $error');
    }
  }

  Future<void> _releaseWorkshopUploadLease(
    DocumentReference<Map<String, dynamic>> latestDocRef,
    String uploadId,
  ) async {
    try {
      await _firestore
          .runTransaction<void>((transaction) async {
            final snapshot = await transaction.get(latestDocRef);
            if (snapshot.data()?['syncLockOwner']?.toString() != uploadId) {
              return;
            }
            transaction.set(latestDocRef, {
              'syncLockOwner': FieldValue.delete(),
              'syncLockExpiresAt': FieldValue.delete(),
            }, SetOptions(merge: true));
          })
          .timeout(const Duration(seconds: 10));
    } catch (error) {
      print('Could not release workshop sync lease: $error');
    }
  }

  Future<void> forceClearWorkshopSyncLock() async {
    final workshopId = _workshopId;
    if (workshopId == null || workshopId.isEmpty) return;
    try {
      final docRef = _firestore
          .collection('workshops')
          .doc(workshopId)
          .collection('backups')
          .doc('latest');
      await docRef.set({
        'syncLockOwner': FieldValue.delete(),
        'syncLockExpiresAt': FieldValue.delete(),
        'syncUploadQueue': <String, dynamic>{},
      }, SetOptions(merge: true));
    } catch (e) {
      print('Error forcing clear sync lock: $e');
    }
  }

  Future<void> _mergeLatestWorkshopBeforeUpload(
    DocumentReference<Map<String, dynamic>> latestDocRef,
    String uploadId,
  ) async {
    final latest = await latestDocRef
        .get(GetOptions(source: Source.server))
        .timeout(const Duration(seconds: 20));
    final payload = latest.data();
    if (!latest.exists ||
        payload == null ||
        payload['status']?.toString() != 'completed' ||
        payload['uploadId']?.toString() == uploadId) {
      return;
    }

    _beginRestore();
    try {
      // Local rows use distributed IDs, so incoming additions and still-local
      // additions can coexist even when both phones saved at the same moment.
      // This restore happens inside the full-upload lease. Calling the public
      // wrapper here would first request another backup and wait for this very
      // upload, so use the internal no-preflight path instead.
      await _runRestoreFromCloud(
        keepPendingChanges: true,
        publishPendingChangesFirst: false,
      );
      _lastHandledBackupFingerprint = _backupFingerprint(payload);
      _dbUpdateController.add('cloud_restored');
      onDataRestored?.call();
    } finally {
      _endRestore();
    }
  }

  /// الرفع اليدوي/الأساسي للسحابة بنظام التجزئة لتجاوز حد الـ 1MB
  ///
  /// [تم الإصلاح]: الإستراتيجية القديمة كانت "اجلب كل الأجزاء القديمة ثم امسحها
  /// بالكامل ثم ارفع الجديد"، وهذا كان بطيئاً جداً (وأحياناً يتسبب بـ TimeoutException)
  /// لأن حجم القراءة/الحذف يعتمد على كمية البيانات المتراكمة بالسحابة من رفعات سابقة،
  /// وليس على حجم البيانات الحالية على الجهاز. كما أن حذف القديم قبل اكتمال رفع
  /// الجديد كان يعرّض البيانات للضياع لو انقطع الاتصال في المنتصف.
  ///
  /// الإستراتيجية الجديدة: نكتب الأجزاء الجديدة مباشرة فوق نفس أسماء المستندات
  /// (بدون أي قراءة أو حذف مسبق)، فسرعة الرفع تعتمد فقط على حجم بياناتك الحالية.
  /// تنظيف الأجزاء الزائدة (الفائضة عن الرفعة الجديدة) يتم بعد نجاح الرفع وفي
  /// الخلفية دون انتظار المستخدم، وبدون التأثير على نجاح/فشل عملية الرفع نفسها.
  /// Serializes every upload, including the Settings button, so an older
  /// database snapshot cannot finish after a newer one and overwrite it.
  Future<void> backupToCloud({
    bool isSilent = false,
    bool forceFullSnapshot = false,
    bool verifyOnServer = false,
  }) {
    if (supabaseWorkshopDataOnly) {
      final supabaseWorkshopSync = SupabaseWorkshopSyncService();
      if (supabaseWorkshopSync.isSignedIn) {
        return supabaseWorkshopSync.uploadFullWorkshopData().then((_) {
          lastBackupUploadSummary = supabaseWorkshopSync.lastUploadSummary;
        });
      }
      return Future.error(
        Exception(
          'مزامنة بيانات الورشة أصبحت عبر Supabase فقط. '
          'سجّل الدخول إلى Supabase ثم أعد المحاولة.',
        ),
      );
    }

    final activeBackup = _activeBackup;
    if (activeBackup != null) {
      // A recovery preflight needs a confirmed full snapshot.  Waiting for an
      // in-flight delta alone is not enough because `backups/latest` would
      // still omit that delta when the following restore starts.
      if (forceFullSnapshot || verifyOnServer) {
        return activeBackup.then<void>(
          (_) => backupToCloud(
            isSilent: isSilent,
            forceFullSnapshot: forceFullSnapshot,
            verifyOnServer: verifyOnServer,
          ),
          onError: (_, __) => backupToCloud(
            isSilent: isSilent,
            forceFullSnapshot: forceFullSnapshot,
            verifyOnServer: verifyOnServer,
          ),
        );
      }
      if (isSilent) {
        _silentBackupQueued = true;
        return activeBackup;
      }
      return activeBackup.then<void>(
        (_) => backupToCloud(isSilent: isSilent),
        onError: (_, __) => backupToCloud(isSilent: isSilent),
      );
    }

    final task = _runSerializedBackup(
      isSilent: isSilent,
      forceFullSnapshot: forceFullSnapshot,
      verifyOnServer: verifyOnServer,
    );
    _activeBackup = task;
    return task;
  }

  Future<void> _runSerializedBackup({
    required bool isSilent,
    required bool forceFullSnapshot,
    required bool verifyOnServer,
  }) async {
    try {
      await _performBackupToCloud(
        isSilent: isSilent,
        forceFullSnapshot: forceFullSnapshot,
        verifyOnServer: verifyOnServer,
      );
    } finally {
      _activeBackup = null;
    }
  }

  /// Publishes only rows captured by the local insert/update/delete triggers.
  ///
  /// A false result means the pending marker predates the change log (or the
  /// changed table has no stable `id`), so one full recovery snapshot is
  /// required to guarantee that no database table is omitted.
  Future<void> _publishLiveEvent({
    required PendingCloudChanges pending,
    required String uploadId,
    required SharedPreferences prefs,
  }) async {
    if (pending.isEmpty || _workshopId == null || _workshopId!.isEmpty) {
      return;
    }

    final user = _auth.currentUser;
    if (user == null) return;

    final data = <String, dynamic>{};
    for (final entry in pending.data.entries) {
      final table = entry.key;
      final rows = entry.value;
      if (rows is List && rows.isNotEmpty) {
        data[table] = rows;
      }
    }
    if (data.isEmpty) return;

    Map<String, dynamic> buildPayload(Map<String, dynamic> chunk) {
      return {
        'kind': 'live_event',
        'status': 'uploading',
        'uploadId': uploadId,
        'deviceId': _deviceId,
        'uploaderUid': user.uid,
        'uploaderRole': prefs.getString('user_role') ?? 'worker',
        'createdAt': DateTime.now().toUtc().toIso8601String(),
        'tables': chunk.keys.toList(),
        'changedRows': pending.changedRows,
        'deletedRows': pending.deletedRows,
        'data': chunk,
      };
    }

    // Split large changes by row. This keeps a large order or catalogue edit
    // on the same fast path instead of dropping its live event altogether.
    // The durable delta remains the source of truth and will retry any single
    // row that is itself larger than the Firestore live-event budget.
    final chunks = <Map<String, dynamic>>[];
    var current = <String, dynamic>{};
    for (final entry in data.entries) {
      final rows = entry.value;
      if (rows is! List) continue;
      for (final rawRow in rows) {
        if (rawRow is! Map) continue;
        final row = Map<String, dynamic>.from(rawRow);
        final candidate = <String, dynamic>{
          ...current,
          entry.key: [
            ...(current[entry.key] is List
                ? current[entry.key] as List
                : const <dynamic>[]),
            row,
          ],
        };
        if (_estimateJsonBytes(buildPayload(candidate)) >
                _maxLiveEventDocumentBytes &&
            current.isNotEmpty) {
          chunks.add(current);
          current = <String, dynamic>{
            entry.key: [row],
          };
        } else {
          current = candidate;
        }
      }
    }
    if (current.isNotEmpty) chunks.add(current);

    for (var index = 0; index < chunks.length; index++) {
      final chunk = chunks[index];
      final eventId = chunks.length == 1
          ? 'live_$uploadId'
          : 'live_${uploadId}_$index';
      final estimatedPayload = buildPayload(chunk);
      final estimatedBytes = _estimateJsonBytes(estimatedPayload);
      if (estimatedBytes > _maxLiveEventDocumentBytes) {
        print(
          'Skipping oversized live event $eventId: '
          '${_formatBytes(estimatedBytes)}. Durable delta will retry it.',
        );
        continue;
      }

      final eventRef = _firestore
          .collection('workshops')
          .doc(_workshopId)
          .collection('live_events')
          .doc(eventId);
      await eventRef
          .set({...estimatedPayload, 'createdAt': FieldValue.serverTimestamp()})
          .timeout(const Duration(seconds: 8));
      await eventRef
          .update({
            'status': 'completed',
            'completedAt': FieldValue.serverTimestamp(),
          })
          .timeout(const Duration(seconds: 8));
      await _markLiveEventHandled(eventId);
    }
  }

  Future<bool> _performDeltaBackupToCloud() async {
    await init();
    final uploadedGeneration = _transactionChangeGeneration;
    final user = _auth.currentUser;
    if (user == null) {
      throw StateError('Cloud delta upload requires an authenticated user.');
    }
    if (_workshopId == null || _workshopId!.isEmpty) {
      throw StateError('Cloud delta upload requires a valid workshop.');
    }

    final pending = await _db.exportPendingCloudChanges();
    if (pending.isEmpty) {
      return !await _hasPendingTransactions();
    }

    final prefs = await SharedPreferences.getInstance();
    final uploadId = _newUploadId();
    final deltaId = 'delta_$uploadId';
    _rememberOwnUpload(uploadId);
    final deltaRef = _firestore
        .collection('workshops')
        .doc(_workshopId)
        .collection('backups')
        .doc(deltaId);
    final expectedRowCounts = <String, int>{
      for (final entry in pending.data.entries)
        entry.key: entry.value is List ? (entry.value as List).length : 0,
    };
    var uploadStage = 'preparing changed rows';

    try {
      uploadStage = 'opening delta upload';
      await deltaRef
          .set({
            'kind': 'delta',
            'status': 'uploading',
            'uploadId': uploadId,
            'deviceId': _deviceId,
            'uploaderUid': user.uid,
            'uploaderRole': prefs.getString('user_role') ?? 'worker',
            'createdAt': FieldValue.serverTimestamp(),
            'tables': pending.data.keys.toList(),
            'changedRows': pending.changedRows,
            'deletedRows': pending.deletedRows,
          })
          .timeout(const Duration(seconds: 10));

      try {
        await _publishLiveEvent(
          pending: pending,
          uploadId: uploadId,
          prefs: prefs,
        );
      } catch (error) {
        print('Live event publish failed; durable delta will continue: $error');
      }

      uploadStage = 'uploading changed rows';
      final chunkCounts = await _uploadChunkedTables(
        data: pending.data,
        chunkRef: deltaRef.collection('chunks'),
        setStage: (stage) => uploadStage = stage,
        uploadId: uploadId,
      );

      uploadStage = 'completing delta upload';
      await deltaRef
          .update({
            'status': 'completed',
            'completedAt': FieldValue.serverTimestamp(),
            'tableChunkCounts': chunkCounts,
            'tableRowCounts': expectedRowCounts,
          })
          .timeout(const Duration(seconds: 10));
      await _publishTransactionalSyncState(
        tableRowCounts: await _db.readSyncTableCounts(
          _watchedTransactionalCountTables,
        ),
        uploadId: uploadId,
        sourceKind: 'delta',
      );

      await _db.acknowledgePendingCloudChanges(pending.acknowledgements);
      await _markDeltaHandled(deltaId);
      final stillPending = await _db.hasPendingCloudChanges();
      if (stillPending) {
        _silentBackupQueued = true;
      } else {
        await prefs.setBool('is_local_dirty', false);
        await _markTransactionalUploadConfirmed(uploadedGeneration);
      }
      lastBackupUploadSummary =
          'Changes: ${pending.changedRows}, deletions: ${pending.deletedRows}';
      return true;
    } catch (error) {
      print('Delta upload failed at $uploadStage: $error');
      try {
        await deltaRef
            .update({
              'status': 'failed',
              'failedAt': FieldValue.serverTimestamp(),
            })
            .timeout(const Duration(seconds: 5));
      } catch (_) {}
      rethrow;
    }
  }

  Future<void> _performBackupToCloud({
    bool isSilent = false,
    bool forceFullSnapshot = false,
    bool verifyOnServer = false,
  }) async {
    final supabaseWorkshopSync = SupabaseWorkshopSyncService();
    if (supabaseWorkshopSync.isSignedIn) {
      if (isSilent && !forceFullSnapshot && !verifyOnServer) {
        await supabaseWorkshopSync.uploadPendingChanges();
      } else {
        await supabaseWorkshopSync.uploadFullWorkshopData();
      }
      await _clearFirebaseTransactionalPendingFlag();
      return;
    }
    if (isSilent && !forceFullSnapshot) {
      final handledAsDelta = await _performDeltaBackupToCloud();
      if (handledAsDelta) return;
    }
    await _performFullBackupToCloud(
      isSilent: isSilent,
      verifyOnServer: verifyOnServer,
    );
  }

  Future<void> _performFullBackupToCloud({
    bool isSilent = false,
    bool verifyOnServer = false,
  }) async {
    await init();
    final uploadedGeneration = _transactionChangeGeneration;

    final user = _auth.currentUser;
    if (user == null) {
      _sendSyncFeedback(
        CloudSyncFeedbackType.uploadFailed,
        'لم يبدأ الرفع: يجب تسجيل الدخول أولاً.',
      );
      if (!isSilent || verifyOnServer)
        throw Exception(
          'يجب تسجيل الدخول أولاً لعمل نسخة احتياطية على السحابة',
        );
      return;
    }
    if (_workshopId == null || _workshopId!.isEmpty) {
      _sendSyncFeedback(
        CloudSyncFeedbackType.uploadFailed,
        'لم يبدأ الرفع: حسابك غير مرتبط بورشة صحيحة.',
        details: 'تحقق من workshopId في حساب العامل داخل Firebase.',
      );
      if (!isSilent || verifyOnServer)
        throw Exception('لم يتم العثور على معرف الورشة الخاص بك للمزامنة');
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    // Every workshop member publishes transactional changes (orders,
    // customers, payments, etc.).  `cloud_backup` is intentionally not used
    // as a gate here: it must never leave a worker's change on one phone.

    final latestDocRef = _firestore
        .collection('workshops')
        .doc(_workshopId)
        .collection('backups')
        .doc('latest');
    var uploadStage = 'بدء الاتصال بـ Firebase';
    final uploadId = _newUploadId();
    // Upload into an immutable sibling document first.  The `latest` document
    // remains the last known-good pointer while chunks are still arriving, so
    // a failed upload can never make every other device lose its download.
    final snapshotId = 'snapshot_$uploadId';
    final snapshotRef = latestDocRef.parent.doc(snapshotId);
    final chunkRef = snapshotRef.collection('chunks');
    _rememberOwnUpload(uploadId);
    Timer? leaseHeartbeat;
    var leaseAcquired = false;
    var publishAttempted = false;

    try {
      // Only one workshop device may publish a full snapshot at a time. The
      // second phone waits, downloads the first phone's completed snapshot,
      // merges it into its pending local additions, then publishes both.
      uploadStage = 'انتظار دور المزامنة داخل الورشة';
      await _acquireWorkshopUploadLease(latestDocRef, uploadId);
      leaseAcquired = true;
      leaseHeartbeat = Timer.periodic(const Duration(seconds: 10), (_) {
        _renewWorkshopUploadLease(latestDocRef, uploadId);
      });

      uploadStage = 'دمج أحدث إضافات الأجهزة الأخرى';
      await _mergeLatestWorkshopBeforeUpload(latestDocRef, uploadId);
      final compactedDeltaIds = await _refreshDeltasFromCloud();

      final fullChangeSnapshot = await _db.exportPendingCloudChanges();
      final allData = await _db.exportAllData();
      final expectedRowCounts = <String, int>{
        for (final entry in allData.entries)
          entry.key: entry.value is List ? (entry.value as List).length : 0,
      };

      if (isSilent) {
        final hasAnyData = allData.values.any(
          (rows) => rows is List && rows.isNotEmpty,
        );
        if (!hasAnyData) {
          _sendSyncFeedback(
            CloudSyncFeedbackType.uploadSkipped,
            'لا توجد بيانات محلية لرفعها الآن.',
            details: 'الورشة: $_workshopId',
          );
          return;
        }
      }

      final uploadDetails = _describeBackupContents(allData);
      _sendSyncFeedback(
        CloudSyncFeedbackType.uploadStarted,
        'يتم الآن رفع بيانات الورشة إلى السحابة…',
        details: uploadDetails,
      );

      // 1. Create a staged snapshot. Do not change `latest` yet: readers must
      // continue to see the previously completed snapshot until this one is
      // fully written and verified on the server.
      uploadStage = 'بدء جلسة الرفع في السحابة';
      await snapshotRef
          .set({
            'timestamp': FieldValue.serverTimestamp(),
            'uploadId': uploadId,
            'deviceId': _deviceId,
            'uploaderUid': user.uid,
            'uploaderRole': prefs.getString('user_role') ?? 'worker',
            'status': 'uploading',
            'tables': allData.keys.toList(),
          }, SetOptions(merge: true))
          .timeout(const Duration(seconds: 15));

      // 2. Upload every chunk to the staged snapshot, never over the chunks
      // used by the current `latest` pointer.
      uploadStage = 'رفع الجداول والسجلات';
      final newChunkCounts = await _uploadChunkedTables(
        data: allData,
        chunkRef: chunkRef,
        setStage: (stage) => uploadStage = stage,
        uploadId: uploadId,
      );

      // A WriteBatch commit already fails when Firestore has not accepted the
      // write. For automatic sync, do not then read every chunk one-by-one:
      // on a large workshop that verification delayed a single worker order
      // for minutes and kept every other phone waiting for `completed`.
      // The Settings button and recovery preflight keep the full server-side
      // verification below.
      final shouldVerifyOnServer = !isSilent || verifyOnServer;
      final verifiedCounts = shouldVerifyOnServer
          ? await _verifyUploadedChunks(
              chunkRef: chunkRef,
              expectedChunkCounts: newChunkCounts,
              expectedRowCounts: expectedRowCounts,
              uploadId: uploadId,
            )
          : expectedRowCounts;

      // 3. Finish the staged snapshot, then publish one small pointer update.
      // That final update is the only event that makes this version visible to
      // other phones.
      uploadStage = 'تأكيد اكتمال النسخة في السحابة';
      await snapshotRef
          .update({
            'status': 'completed',
            'completedAt': FieldValue.serverTimestamp(),
            'tableChunkCounts': newChunkCounts,
            'tableRowCounts': verifiedCounts,
            'compactedDeltaIds': compactedDeltaIds.toList(),
          })
          .timeout(const Duration(seconds: 10));

      publishAttempted = true;
      await latestDocRef
          .set({
            'timestamp': FieldValue.serverTimestamp(),
            'uploadId': uploadId,
            'activeSnapshotId': snapshotId,
            'deviceId': _deviceId,
            'uploaderUid': user.uid,
            'uploaderRole': prefs.getString('user_role') ?? 'worker',
            'status': 'completed',
            'completedAt': FieldValue.serverTimestamp(),
            'tables': allData.keys.toList(),
            'tableChunkCounts': newChunkCounts,
            'tableRowCounts': verifiedCounts,
            'compactedDeltaIds': compactedDeltaIds.toList(),
          }, SetOptions(merge: true))
          .timeout(const Duration(seconds: 10));
      await _publishTransactionalSyncState(
        tableRowCounts: Map<String, int>.fromEntries(
          _watchedTransactionalCountTables.map(
            (table) => MapEntry(table, verifiedCounts[table] ?? 0),
          ),
        ),
        uploadId: uploadId,
        sourceKind: 'snapshot',
      );

      // تنظيف الخلفية: حذف مستندات delta المدمجة في هذه النسخة، وحذف النسخ
      // الكاملة القديمة غير المستخدمة. هذا هو الإصلاح الأساسي لمشكلة تجاوز
      // حصة القراءة اليومية على Firebase — لا ينتظره المستخدم ولا يمنع نجاح
      // الرفع الحالي حتى لو فشل التنظيف نفسه لأي سبب.
      _deleteCompactedDeltaDocuments(compactedDeltaIds).catchError((error) {
        print('Background delta cleanup warning: $error');
      });
      _cleanupObsoleteFullSnapshots(
        latestDocRef,
        keepSnapshotId: snapshotId,
      ).catchError((error) {
        print('Background snapshot cleanup warning: $error');
      });

      // A successful Firestore write already means that the server accepted
      // the automatic upload. Avoid a second server-only read here: on some
      // worker devices that read waited 15 seconds despite the write having
      // completed, then incorrectly reported the upload as failed.
      if (shouldVerifyOnServer) {
        uploadStage = 'قراءة تأكيد النسخة من الخادم';
        final confirmation = await latestDocRef
            .get(GetOptions(source: Source.server))
            .timeout(const Duration(seconds: 15));
        final confirmationData = confirmation.data();
        if (!confirmation.exists ||
            confirmationData?['status'] != 'completed' ||
            confirmationData?['uploadId'] != uploadId) {
          throw Exception('لم يؤكد الخادم اكتمال رفع نسخة الورشة.');
        }
        final confirmedCounts = confirmationData?['tableRowCounts'];
        if (confirmedCounts is! Map ||
            confirmedCounts['Commandes'] != expectedRowCounts['Commandes'] ||
            confirmedCounts['Client'] != expectedRowCounts['Client']) {
          throw Exception(
            'لم يؤكد الخادم وصول الطلبات والزبائن إلى النسخة السحابية.',
          );
        }
      }
      lastBackupUploadSummary = uploadDetails;

      await _db.acknowledgePendingCloudChanges(
        fullChangeSnapshot.acknowledgements,
      );
      await prefs.setBool('is_local_dirty', false);
      await _markTransactionalUploadConfirmed(uploadedGeneration);
      _sendSyncFeedback(
        CloudSyncFeedbackType.uploadSucceeded,
        'تم رفع بيانات الورشة بنجاح.',
        details: uploadDetails,
      );

      // 4. حفظ نسخة في الـ History
      if (!isSilent) {
        try {
          String historyId = DateTime.now().toIso8601String().replaceAll(
            ':',
            '-',
          );
          await _firestore
              .collection('workshops')
              .doc(_workshopId)
              .collection('backups_history')
              .doc(historyId)
              .set({
                'timestamp': FieldValue.serverTimestamp(),
                'note': 'Manual Backup',
              })
              .timeout(const Duration(seconds: 10));
        } catch (e) {
          print('History snapshot warning: $e');
        }
      }
    } catch (e) {
      print('backupToCloud failed: $e');
      // Once publication is attempted the result can be ambiguous if the
      // network drops after Firestore accepted the pointer. Leave the staged
      // snapshot completed in that case; it is either the active version or
      // an unreachable orphan, never a replacement for a good version.
      if (!publishAttempted) {
        try {
          await snapshotRef.set({
            'status': 'failed',
            'failedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        } catch (_) {}
      }
      if (!isSilent) {
        _sendSyncFeedback(
          CloudSyncFeedbackType.uploadFailed,
          'فشل رفع بيانات الورشة إلى السحابة.',
          details:
              'مرحلة الفشل: $uploadStage\n${_describeCloudWriteFailure(e)}\nالورشة: $_workshopId',
        );
      }
      throw Exception(
        'فشل رفع النسخة إلى '
        'workshops/${_workshopId}/backups/latest: '
        '${_describeCloudWriteFailure(e)}',
      );
    } finally {
      leaseHeartbeat?.cancel();
      if (leaseAcquired) {
        await _releaseWorkshopUploadLease(latestDocRef, uploadId);
      }
    }
  }

  /// الاستعادة اليدوية/التلقائية من السحابة بنظام التجميع
  /// Runs at most one full recovery at a time.  The yellow startup screen,
  /// pull-to-refresh and the top refresh button can all request a recovery;
  /// allowing them to import SQLite tables concurrently can terminate the app
  /// on some devices.  Later callers wait for the active recovery instead.
  Future<void> fullRecoverySync({bool initialRestore = false}) {
    final activeRecovery = _activeFullRecovery;
    if (activeRecovery != null) return activeRecovery;

    final task = _runFullRecoverySync(initialRestore: initialRestore);
    _activeFullRecovery = task;
    return task;
  }

  Future<void> _runFullRecoverySync({bool initialRestore = false}) async {
    _beginRestore();
    try {
      await init();

      // A pending local change is first merged with the latest workshop state,
      // published as a verified full snapshot, then restored from that server
      // snapshot. This preserves phone-only records during a manual refresh.
      var hasPendingLocalChanges = false;
      if (!initialRestore) {
        try {
          hasPendingLocalChanges =
              await _publishPendingTransactionsBeforeCloudRestore();
        } catch (error) {
          _sendSyncFeedback(
            CloudSyncFeedbackType.uploadFailed,
            'تم إيقاف التحديث لحماية البيانات المحلية غير المرفوعة.',
            details:
                '${_describeCloudWriteFailure(error)}\n'
                'لن يتم تنزيل أي نسخة سحابية قبل تأكيد رفع بيانات هذا الجهاز.',
          );
          rethrow;
        }
      }

      // A remaining pending marker means that a new save happened while the
      // preflight upload was running. It is merged, never replaced, and is
      // uploaded automatically after the restore completes.
      if (hasPendingLocalChanges) {
        _localSyncQueuedAfterRestore = true;
      }

      bool restoreSuccess = false;
      Object? restoreError;
      StackTrace? restoreStackTrace;
      bool isNoBackup = false;

      // 1. Supabase هو المصدر الأساسي الآن لبيانات الورشة.
      // في تثبيت جديد لا توجد بيانات محلية، لذلك يجب تنزيل النسخة كاملة من
      // السيرفر مباشرة بدل المرور أولاً على نسخة Firebase القديمة.
      final supabaseWorkshopSync = SupabaseWorkshopSyncService();
      if (supabaseWorkshopSync.isSignedIn) {
        try {
          if (initialRestore) {
            await supabaseWorkshopSync.downloadWorkshopData(full: true);
          } else {
            await supabaseWorkshopSync.downloadWorkshopData();
            await supabaseWorkshopSync.uploadPendingChanges();
          }
          try {
            await supabaseWorkshopSync.refreshCurrentPermissions();
          } catch (permissionError) {
            print(
              'Supabase permission refresh after restore failed: '
              '$permissionError',
            );
          }
          restoreSuccess = true;
          lastRestoreSummary =
              supabaseWorkshopSync.lastDownloadSummary.isNotEmpty
              ? supabaseWorkshopSync.lastDownloadSummary
              : 'تم تنزيل بيانات الورشة من Supabase.';
          if (hasPendingLocalChanges) {
            _localSyncQueuedAfterRestore = true;
          }
        } catch (e, stackTrace) {
          print('Supabase workshop restore failed: $e');
          restoreError = e;
          restoreStackTrace = stackTrace;
          if (initialRestore) {
            Error.throwWithStackTrace(e, stackTrace);
          }
        }
      } else if (initialRestore) {
        throw Exception(
          'لم يتم فتح جلسة Supabase لهذا الحساب. '
          'سجّل الدخول بالبريد وكلمة المرور حتى يتم تنزيل بيانات الورشة من Supabase.',
        );
      } else if (supabaseWorkshopDataOnly) {
        throw Exception(
          'تم إيقاف Firebase لبيانات الورشة. '
          'لا يمكن التحديث إلا بعد فتح جلسة Supabase.',
        );
      }

      // 2. احتياط قديم فقط عند عدم وجود جلسة Supabase.
      if (!restoreSuccess &&
          !supabaseWorkshopSync.isSignedIn &&
          !supabaseWorkshopDataOnly) {
        try {
          await restoreFromCloud(
            keepPendingChanges: hasPendingLocalChanges,
            publishPendingChangesFirst: false,
          );
          restoreSuccess = true;
          if (hasPendingLocalChanges) {
            _localSyncQueuedAfterRestore = true;
          }
        } catch (e, stackTrace) {
          print('New chunk sync failed: $e');
          if (e is NoWorkshopBackupException ||
              e.toString().contains('لم يتم العثور على نسخة احتياطية سابقة')) {
            isNoBackup = true;
          }
          restoreError = e;
          restoreStackTrace = stackTrace;
        }
      }

      // 3. جلب البيانات من المجلد العام (Global Catalog) فقط إذا كانت قاعدة البيانات فارغة تماماً من الكتالوج
      if (!restoreSuccess) {
        try {
          final myDb = await _db.db;
          if (myDb != null) {
            final profiles = await myDb.query('Profile', limit: 1);
            final series = await myDb.query('Series', limit: 1);
            if (profiles.isEmpty && series.isEmpty) {
              await downloadGlobalCatalog();
            }
          }
        } catch (e) {
          print('Global catalog fallback check failed: $e');
        }
      }

      // 4. استرجاع البيانات القديمة فقط عند عدم توفر Supabase.
      if (!restoreSuccess &&
          !supabaseWorkshopSync.isSignedIn &&
          !supabaseWorkshopDataOnly) {
        final restoredFromLegacy = await _legacySync();
        if (restoredFromLegacy) {
          restoreSuccess = true;
          lastRestoreSummary =
              'تمت استعادة البيانات من النسخة السحابية السابقة.';
        } else if (isNoBackup) {
          // حالة طبيعية لورشة جديدة فارغة لا تحتوي على نسخة سحابية بعد
          restoreSuccess = true;
          lastRestoreSummary = 'تمت تهيئة الورشة الجديدة بنجاح.';
        } else if (restoreError != null) {
          Error.throwWithStackTrace(restoreError, restoreStackTrace!);
        }
      }
      if (!restoreSuccess && restoreError != null) {
        Error.throwWithStackTrace(restoreError, restoreStackTrace!);
      }
      _dbUpdateController.add('');
    } finally {
      _endRestore();
      _activeFullRecovery = null;
    }
  }

  Future<bool> _legacySync() async {
    var restoredBusinessData = false;
    try {
      final user = _auth.currentUser;
      if (user != null) {
        final targetUid = (_workshopId != null && _workshopId!.isNotEmpty)
            ? _workshopId!
            : user.uid;
        final userDoc = _firestore.collection('users').doc(targetUid);

        var clientsSnapshot = await userDoc.collection('Client').get();
        restoredBusinessData =
            restoredBusinessData || clientsSnapshot.docs.isNotEmpty;
        for (var doc in clientsSnapshot.docs) {
          try {
            final data = doc.data();
            await _db.insertOrUpdateSafeLegacy('Client', data, 'id');
          } catch (e) {
            print('Failed to sync legacy Client doc: $e');
          }
        }

        var cmdsSnapshot = await userDoc.collection('Commandes').get();
        restoredBusinessData =
            restoredBusinessData || cmdsSnapshot.docs.isNotEmpty;
        for (var doc in cmdsSnapshot.docs) {
          try {
            final data = doc.data();
            await _db.insertOrUpdateSafeLegacy('Commandes', data, 'id');
          } catch (e) {
            print('Failed to sync legacy Commandes doc: $e');
          }
        }

        // جلب معاملات العمال (WorkerTransactions)
        var wtSnapshot = await userDoc.collection('WorkerTransactions').get();
        for (var doc in wtSnapshot.docs) {
          try {
            final data = doc.data();
            await _db.insertOrUpdateSafeLegacy(
              'WorkerTransactions',
              data,
              'id',
            );
          } catch (e) {
            print('Failed to sync legacy WorkerTransactions doc: $e');
          }
        }

        // جلب إسنادات العمال (WorkerAllocations)
        var waSnapshot = await userDoc.collection('WorkerAllocations').get();
        for (var doc in waSnapshot.docs) {
          try {
            final data = doc.data();
            await _db.insertOrUpdateSafeLegacy('WorkerAllocations', data, 'id');
          } catch (e) {
            print('Failed to sync legacy WorkerAllocations doc: $e');
          }
        }

        // جلب الخزينة والصناديق (Treasury)
        var treasurySnapshot = await userDoc.collection('Treasury').get();
        for (var doc in treasurySnapshot.docs) {
          try {
            final data = doc.data();
            await _db.insertOrUpdateSafeLegacy('Treasury', data, 'id');
          } catch (e) {
            print('Failed to sync legacy Treasury doc: $e');
          }
        }

        // جلب قائمة Achats المحذوفة (tombstones) قبل الاستيراد
        final Set<int> deletedAchatIds = {};
        if (_workshopId != null) {
          try {
            final delSnap = await _firestore
                .collection('workshops')
                .doc(_workshopId)
                .collection('deleted_achats')
                .get()
                .timeout(const Duration(seconds: 5));
            for (final d in delSnap.docs) {
              final id =
                  (d.data()['id'] as num?)?.toInt() ?? int.tryParse(d.id) ?? 0;
              if (id > 0) deletedAchatIds.add(id);
            }
          } catch (_) {}
        }

        var achatsSnapshot = await userDoc.collection('Achats').get();
        for (var doc in achatsSnapshot.docs) {
          try {
            final data = doc.data();
            final achatId =
                (data['id'] as num?)?.toInt() ?? int.tryParse(doc.id) ?? 0;
            // تخطي Achats المحذوفة (tombstoned)
            if (deletedAchatIds.contains(achatId)) continue;
            await _db.insertOrUpdateSafeLegacy('Achats', data, 'id');
          } catch (e) {
            print('Failed to sync legacy Achats doc: $e');
          }
        }

        // جلب تفاصيل الطلبات — كانت مفقودة من المزامنة القديمة
        var detailsSnapshot = await userDoc
            .collection('Commandes_details')
            .get();
        for (var doc in detailsSnapshot.docs) {
          try {
            final data = doc.data();
            await _db.insertOrUpdateSafeLegacy('Commandes_details', data, 'id');
          } catch (e) {
            print('Failed to sync legacy Commandes_details doc: $e');
          }
        }

        // جلب تفاصيل المشتريات
        var achatItemsSnapshot = await userDoc.collection('Achat_items').get();
        for (var doc in achatItemsSnapshot.docs) {
          try {
            final data = doc.data();
            // تخطي Achat_items لـ Achats محذوفة
            final achatId = (data['achat_id'] as num?)?.toInt() ?? 0;
            if (deletedAchatIds.contains(achatId)) continue;
            await _db.insertOrUpdateSafeLegacy('Achat_items', data, 'id');
          } catch (e) {
            print('Failed to sync legacy Achat_items doc: $e');
          }
        }

        var achatDetailsSnapshot = await userDoc
            .collection('Achat_Details')
            .get();
        for (var doc in achatDetailsSnapshot.docs) {
          try {
            final data = doc.data();
            await _db.insertOrUpdateSafeLegacy('Achat_Details', data, 'id');
          } catch (e) {
            print('Failed to sync legacy Achat_Details doc: $e');
          }
        }
      }
    } catch (e) {
      print('Legacy sync failed: $e');
    }
    return restoredBusinessData;
  }

  Future<void> _importWorkshopSnapshot(
    Map<String, dynamic> data, {
    required bool keepPendingChanges,
  }) async {
    // 🛡️ [إصلاح]: استخدام mergeAllData=true دائماً لحماية البيانات المحلية الحساسة
    // (الطلبيات، الزبائن، الصندوق، العمال) من الحذف العرضي عند تنزيل نسخة السحابة.
    // الجداول الحساسة (sensitiveTransactionalTables) تُدمج دائماً.
    // الجداول غير الحساسة (Profile, Series, Colors...) تُستبدل بالكامل كما ينبغي.
    try {
      if (!await _db.isDatabaseHealthy()) {
        throw StateError('database image malformed (code 11)');
      }
      await _db.importAllData(
        data,
        replaceAllData: false,
        mergeAllData: true, // دائماً merge — لمنع حذف أي بيانات محلية حساسة
      );
    } catch (error) {
      if (SqlDatabase.isDatabaseMovedError(error)) {
        _sendSyncFeedback(
          CloudSyncFeedbackType.downloadStarted,
          'تمت إعادة فتح قاعدة بيانات هذا الهاتف لإكمال التحديث…',
          details:
              'تم اكتشاف اتصال SQLite قديم (code 1032)، وستتم إعادة محاولة تنزيل النسخة نفسها.',
        );
        await _db.reopenAfterDatabaseMoved();
        await _db.importAllData(
          data,
          replaceAllData: false,
          mergeAllData: true, // دائماً merge — لمنع حذف أي بيانات محلية حساسة
        );
        return;
      }
      if (!SqlDatabase.isCorruptionError(error)) rethrow;

      _sendSyncFeedback(
        CloudSyncFeedbackType.downloadStarted,
        'تم اكتشاف تلف في قاعدة هذا الهاتف، ويجري إصلاحها الآن…',
        details:
            'لن تُمس النسخة السحابية. سيُحفظ الملف التالف للتشخيص ثم تُنشأ قاعدة سليمة.',
      );
      final diagnosticPath = await _db.recreateCorruptedDatabase();

      // The old local file is corrupt and cannot be merged reliably. Restore
      // the already verified cloud snapshot into the clean database.
      await _db.importAllData(data, replaceAllData: true);
      _sendSyncFeedback(
        CloudSyncFeedbackType.downloadStarted,
        'تم إصلاح قاعدة الهاتف، ويجري تطبيق بيانات الورشة الكاملة…',
        details: diagnosticPath == null
            ? 'تم إنشاء قاعدة SQLite جديدة وسليمة.'
            : 'تم الاحتفاظ بنسخة تشخيصية من الملف التالف.',
      );
    }
  }

  /// Serializes all database restores, including the Settings restore action
  /// and real-time Firestore updates.  SQLite imports are destructive enough
  /// that two overlapping restores can corrupt the open database handle.
  Future<void> restoreFromCloud({
    bool preserveLocalChanges = false,
    bool keepPendingChanges = false,
    bool publishPendingChangesFirst = true,
  }) {
    if (supabaseWorkshopDataOnly) {
      final supabaseWorkshopSync = SupabaseWorkshopSyncService();
      if (supabaseWorkshopSync.isSignedIn) {
        return supabaseWorkshopSync.downloadWorkshopData(full: true).then((_) {
          lastRestoreSummary = supabaseWorkshopSync.lastDownloadSummary;
        });
      }
      return Future.error(
        Exception(
          'استرجاع بيانات الورشة أصبح عبر Supabase فقط. '
          'سجّل الدخول إلى Supabase ثم أعد المحاولة.',
        ),
      );
    }

    final activeRestore = _activeRestore;
    if (activeRestore != null) return activeRestore;

    late final Future<void> task;
    task =
        _runRestoreFromCloud(
          preserveLocalChanges: preserveLocalChanges,
          keepPendingChanges: keepPendingChanges,
          publishPendingChangesFirst: publishPendingChangesFirst,
        ).whenComplete(() {
          // Failures before the SQLite import (for example a missing backup or a
          // permission error) must also release the serialization slot.
          if (identical(_activeRestore, task)) {
            _activeRestore = null;
          }
        });
    _activeRestore = task;
    return task;
  }

  Future<void> _runRestoreFromCloud({
    bool preserveLocalChanges = false,
    bool keepPendingChanges = false,
    bool publishPendingChangesFirst = true,
  }) async {
    print("--- CloudSyncService: restoreFromCloud() started ---");
    await init();

    final user = _auth.currentUser;
    if (user == null) throw Exception('يجب تسجيل الدخول لاستعادة البيانات');
    if (_workshopId == null) {
      throw Exception('لم يتم العثور على ورشة خاصة بك للمزامنة');
    }

    var effectiveKeepPendingChanges = keepPendingChanges;
    if (publishPendingChangesFirst) {
      // Every public restore, including Settings and a worker task refresh,
      // follows the same publish-before-download rule. The caller cannot
      // accidentally erase a phone-only order by using a different button.
      final savedWhilePublishing =
          await _publishPendingTransactionsBeforeCloudRestore();
      if (savedWhilePublishing) {
        effectiveKeepPendingChanges = true;
        _localSyncQueuedAfterRestore = true;
      }
    }

    final latestDocRef = _firestore
        .collection('workshops')
        .doc(_workshopId)
        .collection('backups')
        .doc('latest');

    print("--- CloudSyncService: Fetching workshop/backups/latest... ---");
    DocumentSnapshot doc;
    try {
      doc = await latestDocRef
          .get(GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 15));
    } catch (_) {
      doc = await latestDocRef.get().timeout(const Duration(seconds: 15));
    }
    print("--- CloudSyncService: backups/latest fetched! ---");

    if (!doc.exists || doc.data() == null) {
      throw const NoWorkshopBackupException(
        'لم يتم العثور على نسخة احتياطية سابقة',
      );
    }

    Map<String, dynamic> payload = doc.data() as Map<String, dynamic>;
    _rememberFullSnapshotMetadata(payload);
    if (payload['status']?.toString() != 'completed') {
      throw StateError(
        'النسخة السحابية ما زالت قيد الرفع؛ سيعاد فحصها عند اكتمالها.',
      );
    }
    final activeSnapshotId = payload['activeSnapshotId']?.toString() ?? '';

    _beginRestore();
    try {
      // التوافقية مع النظام القديم (في حال وجود البيانات في المستند الرئيسي)
      if (activeSnapshotId.isEmpty && payload.containsKey('data')) {
        Map<String, dynamic> data = payload['data'] as Map<String, dynamic>;
        print("--- CloudSyncService: importing legacy data ---");
        await _importWorkshopSnapshot(
          data,
          keepPendingChanges: effectiveKeepPendingChanges,
        );
        await _db.relinkCurrentWorkerAllocations();
        print("--- CloudSyncService: Legacy data imported! ---");
        lastRestoreSummary = 'تم استرجاع النظام القديم (${data.length} جدول)';
      } else {
        // The active pointer selects an immutable, already-completed snapshot.
        // Headers created by older app versions have no pointer, so their
        // `latest/chunks` location remains a backwards-compatible fallback.
        CollectionReference<Map<String, dynamic>> sourceChunkRef = latestDocRef
            .collection('chunks');
        if (activeSnapshotId.isNotEmpty) {
          final activeSnapshotRef = latestDocRef.parent.doc(activeSnapshotId);
          DocumentSnapshot<Map<String, dynamic>> activeSnapshot;
          try {
            activeSnapshot = await activeSnapshotRef
                .get(GetOptions(source: Source.server))
                .timeout(const Duration(seconds: 15));
          } catch (_) {
            activeSnapshot = await activeSnapshotRef.get().timeout(
              const Duration(seconds: 15),
            );
          }
          final activeData = activeSnapshot.data();
          if (!activeSnapshot.exists ||
              activeData == null ||
              activeData['status']?.toString() != 'completed' ||
              activeData['uploadId']?.toString() !=
                  payload['uploadId']?.toString()) {
            throw StateError(
              'النسخة السحابية المعلنة غير مكتملة أو لا تطابق مؤشرها؛ لن يتم تنزيل بيانات جزئية.',
            );
          }
          sourceChunkRef = activeSnapshotRef.collection('chunks');
        }

        // النظام الجديد: جلب الأجزاء (Chunks) وتجميعها
        print("--- CloudSyncService: Fetching workshop backup chunks... ---");
        final chunks = await _fetchChunkPages(sourceChunkRef);
        print(
          "--- CloudSyncService: backup chunks fetched (${chunks.length}) ---",
        );
        final uploadId = payload['uploadId']?.toString();
        final assembledData = _assembleChunkedData(chunks, uploadId: uploadId);
        final publishedTables = payload['tables'];
        if (publishedTables is List) {
          for (final table in publishedTables) {
            if (table is String && table.isNotEmpty) {
              assembledData.putIfAbsent(table, () => []);
            }
          }
        }
        final expectedCounts = payload['tableRowCounts'];
        if (expectedCounts is Map) {
          for (final entry in expectedCounts.entries) {
            final table = entry.key.toString();
            final expected = (entry.value as num?)?.toInt();
            if (expected == null) continue;
            final actual = assembledData[table]?.length ?? 0;
            if (actual != expected) {
              throw StateError(
                'النسخة المستلمة غير مكتملة في جدول $table '
                '(المتوقع $expected، وصل $actual).',
              );
            }
          }
        }
        await _importWorkshopSnapshot(
          assembledData,
          keepPendingChanges: effectiveKeepPendingChanges,
        );
        await _db.relinkCurrentWorkerAllocations();
        await _db.syncWorkerAllocationsStatusFromCloud();
        await _db.syncOrdersStatusFromCloud();
        // ⚠️ تطبيق علامات الحذف الدائمة بعد الاستيراد مباشرة
        await _applyDeletedAllocationsTombstones();
        await _applyDeletedAchatsTombstones(); // منع عودة المشتريات المحذوفة
        await _applyDeletedGlassTombstones(); // منع ظهور الزجاج المحذوف
        final summaryList = assembledData.entries
            .where((e) => e.value.isNotEmpty)
            .map((e) => '${e.key}: ${e.value.length}')
            .toList();
        lastRestoreSummary = 'مسترجع:\n' + summaryList.join('\n');
      }
      await _rememberHandledBackupFingerprint(_backupFingerprint(payload));
      _dbUpdateController.add('');
      onDataRestored?.call();
      if (!effectiveKeepPendingChanges) {
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setBool('is_local_dirty', false);
        } catch (e) {
          print('Failed to clear local dirty flag after restore: $e');
        }
      }
    } finally {
      _endRestore();
    }
  }

  // ==================== Tombstone Helpers ====================

  /// حذف الإسنادات المحذوفة (tombstones) من SQLite بعد كل restore
  Future<void> _applyDeletedAllocationsTombstones() async {
    try {
      if (_workshopId == null) return;
      final snap = await _firestore
          .collection('workshops')
          .doc(_workshopId)
          .collection('deleted_allocations')
          .get()
          .timeout(const Duration(seconds: 10));
      if (snap.docs.isEmpty) return;
      for (final doc in snap.docs) {
        final id =
            (doc.data()['id'] as num?)?.toInt() ?? int.tryParse(doc.id) ?? 0;
        if (id > 0) {
          await _db.deleteWorkerAllocationLocalOnly(id);
        }
      }
    } catch (e) {
      print('Error applying deleted_allocations tombstones: $e');
    }
  }

  /// حذف المشتريات المحذوفة (tombstones) من SQLite بعد كل restore
  Future<void> _applyDeletedAchatsTombstones() async {
    try {
      if (_workshopId == null) return;
      final snap = await _firestore
          .collection('workshops')
          .doc(_workshopId)
          .collection('deleted_achats')
          .get()
          .timeout(const Duration(seconds: 8));
      for (final doc in snap.docs) {
        final id =
            (doc.data()['id'] as num?)?.toInt() ?? int.tryParse(doc.id) ?? 0;
        if (id > 0) {
          await _db.deleteAchatLocalOnly(id);
        }
      }
    } catch (e) {
      print('Error applying deleted_achats tombstones: $e');
    }
  }

  /// تعطيل سجلات الزجاج المحذوفة (tombstones) من SQLite بعد كل restore
  Future<void> _applyDeletedGlassTombstones() async {
    try {
      if (_workshopId == null) return;
      final snap = await _firestore
          .collection('workshops')
          .doc(_workshopId)
          .collection('deleted_glass_ids')
          .get()
          .timeout(const Duration(seconds: 8));
      for (final doc in snap.docs) {
        final id =
            (doc.data()['id'] as num?)?.toInt() ?? int.tryParse(doc.id) ?? 0;
        if (id > 0) {
          await _db.setGlassInactiveLocalOnly(id);
        }
      }
    } catch (e) {
      print('Error applying deleted_glass tombstones: $e');
    }
  }

  Future<void> backupGlobalCatalog() {
    final activeCatalogBackup = _activeCatalogBackup;
    if (activeCatalogBackup != null) {
      _catalogBackupQueued = true;
      return activeCatalogBackup;
    }

    final task = _runSerializedCatalogBackup();
    _activeCatalogBackup = task;
    return task;
  }

  Future<void> _runSerializedCatalogBackup() async {
    try {
      do {
        _catalogBackupQueued = false;
        await _performGlobalCatalogBackup();
      } while (_catalogBackupQueued);
    } finally {
      _activeCatalogBackup = null;
    }
  }

  Future<void> _performGlobalCatalogBackup() async {
    await init();
    await _hasUnpublishedCatalogChanges();
    final catalogGeneration = _catalogChangeGeneration;

    final user = _auth.currentUser;
    if (user == null) {
      throw Exception('يجب تسجيل الدخول أولاً لرفع الكتالوج العام');
    }
    final prefs = await SharedPreferences.getInstance();
    final role = prefs.getString('user_role') ?? 'worker';
    if (!_canPublishGlobalCatalog(role)) {
      throw Exception('رفع الكتالوج العام متاح لمدير التطبيق فقط.');
    }

    Map<String, dynamic> globalData = await _db.exportGlobalCatalog();
    for (final requiredTable in const ['Colors', 'ShutterComponents']) {
      if (!globalData.containsKey(requiredTable) ||
          globalData[requiredTable] is! List) {
        throw StateError(
          'تعذر قراءة جدول $requiredTable محلياً؛ لم يتم رفع كتالوج ناقص.',
        );
      }
    }
    final catalogRef = _catalogDocument();
    final expectedRowCounts = <String, int>{
      for (final entry in globalData.entries)
        entry.key: entry.value is List ? (entry.value as List).length : 0,
    };

    var uploadStage = 'بدء الاتصال بـ Firebase';
    final uploadId = _newUploadId();
    // Keep the public `latest` document on the last confirmed catalogue until
    // this immutable version is complete. Workers therefore never see a
    // half-uploaded catalogue or lose a usable prior version.
    final catalogVersionId = 'version_$uploadId';
    final catalogVersionRef = catalogRef.parent.doc(catalogVersionId);
    final chunkRef = catalogVersionRef.collection('chunks');
    _rememberOwnUpload(uploadId);
    var publishAttempted = false;
    try {
      uploadStage = 'بدء جلسة رفع الكتالوج العام';
      await catalogVersionRef
          .set({
            'timestamp': FieldValue.serverTimestamp(),
            'uploadId': uploadId,
            'deviceId': _deviceId,
            'uploaderUid': user.uid,
            'uploaderRole': role,
            'status': 'uploading',
            'tables': globalData.keys.toList(),
          })
          .timeout(const Duration(seconds: 15));

      uploadStage = 'رفع جداول الكتالوج العام';
      final newChunkCounts = await _uploadChunkedTables(
        data: globalData,
        chunkRef: chunkRef,
        setStage: (stage) => uploadStage = stage,
        uploadId: uploadId,
      );

      // Do not consider the catalogue uploaded merely because the header was
      // written. Read every newly written chunk from the server and compare
      // its row count with the local table before reporting success.
      final verifiedCounts = await _verifyUploadedChunks(
        chunkRef: chunkRef,
        expectedChunkCounts: newChunkCounts,
        expectedRowCounts: expectedRowCounts,
        uploadId: uploadId,
      );

      uploadStage = 'تأكيد اكتمال الكتالوج العام';
      await catalogVersionRef
          .update({
            'status': 'completed',
            'completedAt': FieldValue.serverTimestamp(),
            'tableChunkCounts': newChunkCounts,
            'tableRowCounts': verifiedCounts,
          })
          .timeout(const Duration(seconds: 10));

      // Publishing this pointer is atomic from the readers' perspective: all
      // chunks have already been verified above, and no worker follows the new
      // version before this one write succeeds.
      publishAttempted = true;
      await catalogRef
          .set({
            'timestamp': FieldValue.serverTimestamp(),
            'uploadId': uploadId,
            'activeCatalogVersionId': catalogVersionId,
            'deviceId': _deviceId,
            'uploaderUid': user.uid,
            'uploaderRole': role,
            'status': 'completed',
            'completedAt': FieldValue.serverTimestamp(),
            'tables': globalData.keys.toList(),
            'tableChunkCounts': newChunkCounts,
            'tableRowCounts': verifiedCounts,
          }, SetOptions(merge: true))
          .timeout(const Duration(seconds: 10));

      final confirmation = await catalogRef
          .get(GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 15));
      final confirmationData = confirmation.data();
      if (!confirmation.exists ||
          confirmationData?['status'] != 'completed' ||
          confirmationData?['uploadId'] != uploadId) {
        throw Exception('لم يؤكد الخادم اكتمال رفع الكتالوج.');
      }
      final confirmedCounts = confirmationData?['tableRowCounts'];
      if (confirmedCounts is! Map ||
          confirmedCounts['Colors'] != expectedRowCounts['Colors'] ||
          confirmedCounts['ShutterComponents'] !=
              expectedRowCounts['ShutterComponents']) {
        throw Exception('لم يؤكد الخادم وصول جدول الألوان ومركبات الستائر.');
      }
      lastCatalogUploadSummary =
          'الألوان: ${verifiedCounts['Colors'] ?? 0}، '
          'مركبات الستائر: ${verifiedCounts['ShutterComponents'] ?? 0} '
          '(الكتالوج العام)';
      await _markCatalogUploadConfirmed(catalogGeneration);
    } catch (e) {
      // Do not mark `latest` failed: that would hide the catalogue currently
      // used by every worker. A failed staged version is safely unreachable.
      if (!publishAttempted) {
        try {
          await catalogVersionRef.set({
            'status': 'failed',
            'failedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        } catch (_) {}
      }
      throw Exception(
        'فشل رفع الكتالوج إلى '
        'global_catalog/latest: '
        'مرحلة الفشل: $uploadStage. '
        '${_describeCloudWriteFailure(e)}',
      );
    }
  }

  Future<Map<String, int>> _verifyUploadedChunks({
    required CollectionReference<Map<String, dynamic>> chunkRef,
    required Map<String, int> expectedChunkCounts,
    required Map<String, int> expectedRowCounts,
    required String uploadId,
  }) async {
    final verifiedCounts = <String, int>{};

    for (final entry in expectedChunkCounts.entries) {
      final table = entry.key;
      final expectedChunks = entry.value;
      var receivedRows = 0;

      for (var index = 0; index < expectedChunks; index++) {
        final chunk = await chunkRef
            .doc('${table}_$index')
            .get(GetOptions(source: Source.server))
            .timeout(const Duration(seconds: 15));
        final data = chunk.data();
        if (!chunk.exists ||
            data == null ||
            data['uploadId']?.toString() != uploadId ||
            data['table']?.toString() != table ||
            data['chunkIndex'] != index ||
            data['totalChunks'] != expectedChunks ||
            data['data'] is! List) {
          throw Exception('تعذر التحقق من رفع جدول $table.');
        }
        receivedRows += (data['data'] as List).length;
      }

      final expectedRows = expectedRowCounts[table] ?? 0;
      if (receivedRows != expectedRows) {
        throw Exception(
          'عدد سجلات $table في السحابة ($receivedRows) '
          'لا يطابق الجهاز ($expectedRows).',
        );
      }
      verifiedCounts[table] = receivedRows;
    }

    return verifiedCounts;
  }

  Future<void> downloadGlobalCatalog({
    bool discardPendingLocalChanges = false,
  }) async {
    print("--- CloudSyncService: downloadGlobalCatalog() started ---");
    await init();

    if (!discardPendingLocalChanges && await _hasUnpublishedCatalogChanges()) {
      throw StateError(
        'يوجد تعديل محلي في الكتالوج لم يُرفع بعد؛ لن يتم استبداله ببيانات سحابية قديمة.',
      );
    }
    final downloadGeneration = _catalogChangeGeneration;

    final catalogRef = _catalogDocument();
    print("--- CloudSyncService: Fetching global_catalog/latest... ---");
    // The product catalogue must always be read from the server. Reading the
    // default Firestore cache here can re-import an old set of colours or
    // shutter components after the manager has already updated the catalogue.
    DocumentSnapshot doc = await catalogRef
        .get(GetOptions(source: Source.server))
        .timeout(const Duration(seconds: 15));
    print("--- CloudSyncService: global_catalog/latest fetched! ---");

    if (!doc.exists || doc.data() == null) {
      final prefs = await SharedPreferences.getInstance();
      final role = prefs.getString('user_role') ?? 'worker';
      if (!_canPublishGlobalCatalog(role)) {
        throw Exception(
          'الكتالوج العام لم يُنشر بعد. يجب أن ينشره مدير التطبيق أولاً.',
        );
      }

      // On first use, only the application administrator may publish the
      // shared catalogue, then read that confirmed server copy.
      await backupGlobalCatalog();
      doc = await catalogRef
          .get(GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 15));
      if (!doc.exists || doc.data() == null) {
        throw Exception('تعذر إنشاء الكتالوج العام في السحابة.');
      }
    }

    Map<String, dynamic> payload = doc.data() as Map<String, dynamic>;
    final status = payload['status']?.toString() ?? '';
    if (status.isNotEmpty && status != 'completed') {
      throw Exception(
        'الكتالوج المعلن على السيرفر غير مكتمل. يجب أن يعيد مدير التطبيق نشره؛ لن يتم تنزيل بيانات جزئية.',
      );
    }
    final activeCatalogVersionId =
        payload['activeCatalogVersionId']?.toString() ?? '';

    _beginRestore();
    try {
      if (activeCatalogVersionId.isEmpty && payload.containsKey('data')) {
        final raw = payload['data'];
        if (raw is! Map) {
          throw Exception('صيغة بيانات الكتالوج غير صالحة على السيرفر.');
        }
        await _ensureCloudCatalogCanBeApplied(
          downloadGeneration,
          discardPendingLocalChanges,
        );
        final catalogData = Map<String, dynamic>.from(raw);
        await _rejectUnexpectedEmptyCatalogTables(
          catalogData,
          discardPendingLocalChanges,
        );
        await _db.importGlobalCatalog(catalogData);
      } else {
        // New catalogues are read from the immutable version selected by the
        // completed `latest` pointer. Legacy uploads continue to use the old
        // chunks location until a manager publishes the next catalogue.
        CollectionReference<Map<String, dynamic>> sourceChunkRef = catalogRef
            .collection('chunks');
        if (activeCatalogVersionId.isNotEmpty) {
          final activeCatalogVersionRef = catalogRef.parent.doc(
            activeCatalogVersionId,
          );
          final activeCatalogVersion = await activeCatalogVersionRef
              .get(GetOptions(source: Source.server))
              .timeout(const Duration(seconds: 15));
          final activeVersionData = activeCatalogVersion.data();
          if (!activeCatalogVersion.exists ||
              activeVersionData == null ||
              activeVersionData['status']?.toString() != 'completed' ||
              activeVersionData['uploadId']?.toString() !=
                  payload['uploadId']?.toString()) {
            throw StateError(
              'الكاتالوج المعلن غير مكتمل أو لا يطابق مؤشره؛ لن يتم تنزيل بيانات جزئية.',
            );
          }
          sourceChunkRef = activeCatalogVersionRef.collection('chunks');
        }

        print("--- CloudSyncService: Fetching catalog chunks... ---");
        final chunks = await _fetchChunkPages(
          sourceChunkRef,
          timeout: const Duration(seconds: 30),
        );
        print("--- CloudSyncService: chunks fetched (${chunks.length}) ---");
        if (chunks.isEmpty) {
          throw Exception('الكتالوج على السيرفر فارغ.');
        }

        final assembledData = _assembleChunkedData(
          chunks,
          uploadId: payload['uploadId']?.toString(),
        );

        if (assembledData.isEmpty) {
          throw Exception('لم يتم العثور على أجزاء كتالوج صالحة للتحميل.');
        }

        final publishedTables = payload['tables'];
        if (publishedTables is List) {
          for (final table in publishedTables) {
            if (table is String && table.isNotEmpty) {
              assembledData.putIfAbsent(table, () => []);
            }
          }
        }
        final expectedCounts = payload['tableRowCounts'];
        if (expectedCounts is Map) {
          for (final entry in expectedCounts.entries) {
            final table = entry.key.toString();
            final expected = (entry.value as num?)?.toInt();
            if (expected == null) continue;
            final actual = assembledData[table]?.length ?? 0;
            if (actual != expected) {
              throw StateError(
                'الكتالوج المستلم غير مكتمل في جدول $table '
                '(المتوقع $expected، وصل $actual).',
              );
            }
          }
        }

        await _ensureCloudCatalogCanBeApplied(
          downloadGeneration,
          discardPendingLocalChanges,
        );
        await _rejectUnexpectedEmptyCatalogTables(
          assembledData,
          discardPendingLocalChanges,
        );
        await _db.importGlobalCatalog(assembledData);
      }
    } finally {
      _endRestore();
    }
    _lastHandledCatalogFingerprint = _catalogFingerprint(payload);
    _dbUpdateController.add('catalog_downloaded');
  }

  Future<bool> hasBackup() async {
    final user = _auth.currentUser;
    if (user == null || _workshopId == null) return false;

    DocumentSnapshot doc = await _firestore
        .collection('workshops')
        .doc(_workshopId)
        .collection('backups')
        .doc('latest')
        .get();

    return doc.exists;
  }

  List<List<dynamic>> _partitionRowsIntoChunks(List<dynamic> rows) {
    if (rows.isEmpty) return [];
    // limit size to ~150 KB for instant lightning fast Firestore writes without timeouts
    final List<List<dynamic>> chunks = [];
    List<dynamic> currentChunk = [];
    int currentChunkSize = 0;

    for (var rawRow in rows) {
      Map<String, dynamic> row = {};
      if (rawRow is Map) {
        rawRow.forEach((key, val) {
          final String k = key.toString();
          if (val is num || val is String || val is bool || val == null) {
            row[k] = val;
          } else {
            row[k] = val.toString();
          }
        });
      }

      int rowSize = 0;
      try {
        rowSize = _estimateJsonBytes(row);
      } catch (_) {
        rowSize = 1000;
      }

      if (currentChunk.isNotEmpty &&
          currentChunkSize + rowSize > _maxChunkCharacters) {
        chunks.add(currentChunk);
        currentChunk = [];
        currentChunkSize = 0;
      }

      currentChunk.add(row);
      currentChunkSize += rowSize;
    }

    if (currentChunk.isNotEmpty) {
      chunks.add(currentChunk);
    }
    return chunks;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // إعدادات الورشة — الأنظمة
  // ─────────────────────────────────────────────────────────────────────────

  /// يحفظ إعدادات الأنظمة في Firestore تحت:
  /// workshops/{workshopId}/settings  →  { systems: {...}, active_profiles: [...] }
  Future<void> saveWorkshopSystems({
    required Map<String, bool> systemModes,
    required List<int> activeProfileIds,
  }) async {
    if (_workshopId == null || _workshopId!.isEmpty) return;
    try {
      await _firestore.collection('workshops').doc(_workshopId).set({
        'settings': {
          'systems': systemModes,
          'active_profiles': activeProfileIds,
          'updated_at': FieldValue.serverTimestamp(),
        },
      }, SetOptions(merge: true));
      print('--- CloudSyncService: Workshop systems saved to Firestore ---');
    } catch (e) {
      print('Error saving workshop systems: $e');
    }
  }

  /// يجلب إعدادات الأنظمة من Firestore ويكتبها في SharedPreferences المحلي
  /// يُستدعى عند init() لكل مستخدم (مدير أو عامل)
  Future<void> loadAndApplyWorkshopSystems() async {
    if (_workshopId == null || _workshopId!.isEmpty) return;
    try {
      final doc = await _firestore
          .collection('workshops')
          .doc(_workshopId)
          .get()
          .timeout(const Duration(seconds: 8));

      if (!doc.exists) return;
      final data = doc.data();
      if (data == null) return;

      final settings = data['settings'] as Map<String, dynamic>?;
      if (settings == null) return;

      final prefs = await SharedPreferences.getInstance();

      // 1. تطبيق System Modes
      final systemsMap = settings['systems'] as Map<String, dynamic>?;
      if (systemsMap != null) {
        for (var entry in systemsMap.entries) {
          await prefs.setBool(
            'system_active_${entry.key}',
            entry.value as bool? ?? true,
          );
        }
        print(
          '--- CloudSyncService: Workshop system modes applied from Firestore ---',
        );
      }

      // 2. تطبيق Active Profiles على SQLite
      final activeProfiles = settings['active_profiles'];
      if (activeProfiles != null) {
        final List<int> activeIds = (activeProfiles as List)
            .map((e) => (e as num).toInt())
            .toList();
        final dbInstance = await _db.db;
        if (dbInstance != null) {
          // أوقف الكل أولاً
          await dbInstance.update('Profile', {'is_active': 0});
          await dbInstance.update('Series', {'is_active': 0});
          // فعّل المختارين
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
          print(
            '--- CloudSyncService: Workshop active profiles applied (${activeIds.length} active) ---',
          );
        }
      }
    } catch (e) {
      print('Error loading workshop systems: $e');
    }
  }
}
