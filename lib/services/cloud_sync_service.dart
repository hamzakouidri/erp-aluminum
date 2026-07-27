import 'dart:async';
import 'dart:math';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart' show FirebaseException;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:database_data/sql_database.dart';

import 'package:shared_preferences/shared_preferences.dart';

class CloudSyncService {
  // Singleton pattern so we only have one listener and one deviceId
  static final CloudSyncService _instance = CloudSyncService._internal();

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
  Timer? _pendingTransactionUploadTimer;
  StreamSubscription<DocumentSnapshot>? _listener;
  StreamSubscription<DocumentSnapshot>? _catalogListener;
  StreamSubscription<QuerySnapshot>? _statusListener;
  StreamSubscription<QuerySnapshot>? _orderStatusListener;
  StreamSubscription<QuerySnapshot>? _measurementsListener;
  StreamSubscription<QuerySnapshot>? _deletionsListener; // ⚡ لحدف الإسنادات فورياً على جميع الأجهزة
  int _restoreDepth = 0;
  bool _refreshQueuedAfterRestore = false;
  bool _localSyncQueuedAfterRestore = false;
  bool get _isRestoring => _restoreDepth > 0;
  bool _isSilentBackupRunning = false;
  bool _silentBackupQueued = false;
  bool _isCheckingCloudChanges = false;
  String? _lastHandledBackupFingerprint;
  String? _lastHandledCatalogFingerprint;
  Future<void>? _activeBackup;
  Future<void>? _activeCatalogBackup;
  bool _catalogBackupQueued = false;
  bool _hasPendingLocalCatalogChanges = false;
  int _catalogChangeGeneration = 0;
  bool _hasPendingTransactionalChanges = false;
  int _transactionChangeGeneration = 0;

  final StreamController<String> _dbUpdateController = StreamController<String>.broadcast();
  Stream<String> get dbUpdateStream => _dbUpdateController.stream;

  // Callback to refresh UI when auto-restore happens
  Function()? onDataRestored;

  String? _workshopId;
  String? get workshopId => _workshopId;
  String lastBackupUploadSummary = '';
  String lastCatalogUploadSummary = '';
  String lastRestoreSummary = 'لم يتم الاسترجاع بعد';

  DocumentReference<Map<String, dynamic>> _catalogDocument() {
    // Product definitions (colours, profiles and shutter components) are a
    // single shared catalogue. They must not be split between workshops.
    return _firestore.collection('global_catalog').doc('latest');
  }

  bool _canPublishGlobalCatalog(String role) {
    // `admin` is the general manager role. It is already treated as a
    // manager by AppSettings, so the catalogue service must honour it too.
    return role == 'manager' || role == 'admin';
  }

  void _markCatalogDirty() {
    _hasPendingLocalCatalogChanges = true;
    _catalogChangeGeneration++;
    SharedPreferences.getInstance()
        .then((prefs) => prefs.setBool('has_pending_catalog_changes', true))
        .catchError((error) {
      print('Failed to persist pending catalog change: $error');
    });
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

  Future<void> _markTransactionalChangesPending(
    SharedPreferences prefs,
  ) async {
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

  Future<void> _markTransactionalUploadConfirmed(
    int uploadedGeneration,
  ) async {
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

  void _resumePendingTransactionalUpload() {
    _pendingTransactionUploadTimer?.cancel();
    _pendingTransactionUploadTimer = Timer(const Duration(seconds: 2), () async {
      if (await _hasPendingTransactions()) {
        await _silentBackup();
      }
    });
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
  }

  String _describeCloudWriteFailure(Object error) {
    if (error is FirebaseException) {
      switch (error.code) {
        case 'permission-denied':
          return 'رفضت قواعد Firebase الكتابة. يجب السماح لهذا المستخدم بالكتابة داخل ورشته.';
        case 'unauthenticated':
          return 'انتهت جلسة تسجيل الدخول؛ أعد تسجيل الدخول ثم أعد الرفع.';
        case 'unavailable':
          return 'خدمة Firebase غير متاحة حالياً أو لا يوجد اتصال ثابت بالإنترنت.';
      }
    }
    return error.toString();
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
          final isWorkshopMember = role == 'worker' || role == 'co_manager';

          if (isWorkshopMember && (wId.isEmpty || wId == user.uid)) {
            // A worker must never upload to a personal workshop path. Use a
            // previously verified workshop id when available; otherwise stop
            // and wait for the manager to link the account correctly.
            if (storedWorkshopId.isNotEmpty && storedWorkshopId != user.uid) {
              _workshopId = storedWorkshopId;
            } else {
              _workshopId = null;
              lastBackupUploadSummary =
                  'حساب العامل غير مرتبط بورشة صحيحة في Firebase.';
              await prefs.setString('workshop_code', '');
              await prefs.setString('user_role', role);
              print('Worker sync blocked: missing or invalid workshopId for ${user.uid}');
              return;
            }
          } else if (wId.isNotEmpty) {
            _workshopId = wId;
          } else {
            _workshopId = user.uid;
          }
          await prefs.setString('workshop_code', _workshopId!);
          await prefs.setString('user_role', role);
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
    }
    print(
      "--- CloudSyncService: init() finished. workshopId = $_workshopId ---",
    );
  }

  void reset() {
    _workshopId = null;
    _debounceTimer?.cancel();
    _backupRetryTimer?.cancel();
    _catalogDebounceTimer?.cancel();
    _catalogRetryTimer?.cancel();
    _realtimeRetryTimer?.cancel();
    _realtimeHealthTimer?.cancel();
    _pendingTransactionUploadTimer?.cancel();
    _listener?.cancel();
    _catalogListener?.cancel();
    _statusListener?.cancel();
    _orderStatusListener?.cancel();
    _measurementsListener?.cancel();
    _deletionsListener?.cancel();
    _listener = null;
    _catalogListener = null;
    _statusListener = null;
    _orderStatusListener = null;
    _measurementsListener = null;
    _deletionsListener = null;
    _lastHandledBackupFingerprint = null;
    _lastHandledCatalogFingerprint = null;
    _activeBackup = null;
    _activeCatalogBackup = null;
    _catalogBackupQueued = false;
    _hasPendingLocalCatalogChanges = false;
    _catalogChangeGeneration = 0;
    _hasPendingTransactionalChanges = false;
    _transactionChangeGeneration = 0;
    _restoreDepth = 0;
    _refreshQueuedAfterRestore = false;
    _localSyncQueuedAfterRestore = false;
  }

  /// بدء الاستماع لتحديثات السحابة لتطبيق المزامنة التلقائية اللحظية لجميع الحسابات
  void startListeningForUpdates(Function() onUpdateCallback) {
    onDataRestored = onUpdateCallback;
    final user = _auth.currentUser;
    if (user == null || _workshopId == null) return;

    // 1. الاستماع لتغييرات نسخة السحابة الكاملة (Latest Backup)
    _listener?.cancel();
    _listener = _firestore
        .collection('workshops')
        .doc(_workshopId)
        .collection('backups')
        .doc('latest')
        .snapshots()
        .listen((doc) async {
      if (!doc.exists || doc.data() == null) return;

      final Map<String, dynamic> payload =
          Map<String, dynamic>.from(doc.data() as Map);
      await _applyLatestBackupUpdate(payload);
    }, onError: _scheduleRealtimeListenerRetry, onDone: _scheduleRealtimeListenerRetry);

    _catalogListener?.cancel();
    _catalogListener = _catalogDocument().snapshots().listen((doc) async {
      if (_isRestoring || !doc.exists || doc.data() == null) return;
      final payload = Map<String, dynamic>.from(doc.data() as Map);
      if (payload['status']?.toString() != 'completed') return;

      final fingerprint = _catalogFingerprint(payload);
      if (fingerprint == _lastHandledCatalogFingerprint) return;
      if (payload['deviceId']?.toString() == _deviceId) {
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
      } catch (e) {
        print('Automatic catalog download failed: $e');
      }
    }, onError: _scheduleRealtimeListenerRetry);

    // 2. ⚡ الاستماع الفوري واللحظي لتحديثات حالات الإسناد من أي هاتف في الورشة
    _statusListener?.cancel();
    _statusListener = _firestore
        .collection('workshops')
        .doc(_workshopId)
        .collection('worker_allocations_status')
        .snapshots()
        .listen((snapshot) async {
      if (_isRestoring) return;
      try {
        await _db.syncWorkerAllocationsStatusFromCloud();
        _dbUpdateController.add('status_updated');
        // ملاحظة: لا نستدعي onDataRestored() هنا لتجنب الترميش وإعادة البناء الثقيلة.
        // واجهات المستخدم تستمع لـ dbUpdateStream مباشرةً.
      } catch (e) {
        print('Error syncing allocation status real-time: $e');
      }
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
        await _db.syncOrdersStatusFromCloud();
        _dbUpdateController.add('order_status_updated');
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
            final id = (data['id'] as num?)?.toInt() ?? int.tryParse(change.doc.id) ?? 0;
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

    _startRealtimeHealthCheck();
    _resumePendingTransactionalUpload();
  }

  /// إيقاف الاستماع
  String _backupFingerprint(Map<String, dynamic> payload) {
    return [
      payload['timestamp']?.toString() ?? '',
      payload['deviceId']?.toString() ?? '',
      payload['status']?.toString() ?? '',
    ].join('|');
  }

  String _catalogFingerprint(Map<String, dynamic> payload) {
    return [
      payload['timestamp']?.toString() ?? '',
      payload['deviceId']?.toString() ?? '',
      payload['status']?.toString() ?? '',
    ].join('|');
  }

  Future<void> _applyLatestBackupUpdate(
    Map<String, dynamic> payload,
  ) async {
    if (payload['status']?.toString() != 'completed') return;
    if (_isRestoring) {
      _refreshQueuedAfterRestore = true;
      return;
    }

    final fingerprint = _backupFingerprint(payload);
    if (fingerprint.isEmpty || fingerprint == _lastHandledBackupFingerprint) {
      return;
    }

    // A device already has the data it just uploaded. Skipping its own
    // snapshot avoids an unnecessary restore and protects in-progress edits.
    if (payload['deviceId']?.toString() == _deviceId) {
      _lastHandledBackupFingerprint = fingerprint;
      return;
    }

    // Do not let an incoming full snapshot erase work that a worker or
    // co-manager has already saved locally but Firebase has not confirmed.
    if (await _hasPendingTransactions()) {
      await _silentBackup();
      return;
    }

    _beginRestore();
    try {
      await restoreFromCloud();
      _lastHandledBackupFingerprint = fingerprint;
      _dbUpdateController.add('cloud_restored');
      onDataRestored?.call();
    } catch (e) {
      print('Error auto-restoring from cloud: $e');
    } finally {
      _endRestore();
    }
  }

  void _beginRestore() {
    _restoreDepth++;
  }

  void _endRestore() {
    if (_restoreDepth > 0) _restoreDepth--;
    if (_restoreDepth != 0) return;

    if (_localSyncQueuedAfterRestore) {
      _localSyncQueuedAfterRestore = false;
      scheduleMicrotask(_silentBackup);
    }

    if (!_refreshQueuedAfterRestore) return;
    _refreshQueuedAfterRestore = false;
    scheduleMicrotask(refreshFromCloudIfChanged);
  }

  /// Public fallback used on app resume and by the periodic health check.
  /// It repairs a dropped Firestore listener instead of leaving an old local
  /// database visible for hours.
  Future<void> refreshFromCloudIfChanged() async {
    if (_isRestoring || _isCheckingCloudChanges || _workshopId == null) return;
    if (_auth.currentUser == null) return;

    // Upload a member's queued local work before accepting another device's
    // snapshot. This runs on app resume and in the lightweight health check,
    // so an interrupted worker upload is retried without any manual button.
    if (await _hasPendingTransactions()) {
      await _silentBackup();
      return;
    }

    _isCheckingCloudChanges = true;
    try {
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
    } catch (e) {
      print('Cloud sync health check failed: $e');
    } finally {
      _isCheckingCloudChanges = false;
    }
  }

  void _scheduleRealtimeListenerRetry([
    Object? error,
    StackTrace? stackTrace,
  ]) {
    if (error != null) {
      print('Realtime listener stopped: $error');
    }
    _realtimeRetryTimer?.cancel();
    _realtimeRetryTimer = Timer(const Duration(seconds: 5), () async {
      if (_auth.currentUser == null || _workshopId == null) return;
      startListeningForUpdates(onDataRestored ?? () {});
    });
  }

  void _startRealtimeHealthCheck() {
    _realtimeHealthTimer?.cancel();
    _realtimeHealthTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      refreshFromCloudIfChanged();
    });
    refreshFromCloudIfChanged();
  }

  void stopListening() {
    _realtimeRetryTimer?.cancel();
    _realtimeHealthTimer?.cancel();
    _listener?.cancel();
    _catalogListener?.cancel();
    _statusListener?.cancel();
    _orderStatusListener?.cancel();
    _measurementsListener?.cancel();
    _deletionsListener?.cancel();
    _listener = null;
    _catalogListener = null;
    _statusListener = null;
    _orderStatusListener = null;
    _measurementsListener = null;
    _deletionsListener = null;
  }

  /// إشعار بوجود تغيير محلي ليتم رفعه للسحابة (Debounced)
  void notifyChange() async {
    _dbUpdateController.add('');
    _backupRetryTimer?.cancel();

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
    _backupRetryTimer?.cancel();

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

    if (_isRestoring) {
      _localSyncQueuedAfterRestore = true;
      return;
    }

    if (_debounceTimer?.isActive ?? false) _debounceTimer!.cancel();
    _silentBackup();
  }

  /// Publishes product catalog changes for manager accounts. This is separate
  /// from the workshop backup because product pages deliberately read the
  /// central catalog, not another device's transactional backup.
  void notifyCatalogChange() async {
    try {
      await init();
      final prefs = await SharedPreferences.getInstance();
      if (!_canPublishGlobalCatalog(
        prefs.getString('user_role') ?? 'worker',
      )) {
        // A worker must keep accepting the manager's shared catalogue rather
        // than marking an unpublishable local edit as pending forever.
        print('Ignoring global catalog change from a non-manager account.');
        return;
      }
    } catch (e) {
      print('Failed to schedule catalog sync: $e');
      return;
    }

    // Mark the local edit before the listener can import an older catalogue.
    _markCatalogDirty();
    notifyChange();
    _dbUpdateController.add('catalog_changed');

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
    _backupRetryTimer = Timer(const Duration(seconds: 15), () {
      _silentBackup();
    });
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
  Future<void> backupToCloud({bool isSilent = false}) {
    final activeBackup = _activeBackup;
    if (activeBackup != null) {
      return activeBackup.then<void>(
        (_) => backupToCloud(isSilent: isSilent),
        onError: (_, __) => backupToCloud(isSilent: isSilent),
      );
    }

    final task = _runSerializedBackup(isSilent: isSilent);
    _activeBackup = task;
    return task;
  }

  Future<void> _runSerializedBackup({required bool isSilent}) async {
    try {
      await _performBackupToCloud(isSilent: isSilent);
    } finally {
      _activeBackup = null;
    }
  }

  Future<void> _performBackupToCloud({bool isSilent = false}) async {
    await init();
    final uploadedGeneration = _transactionChangeGeneration;

    final user = _auth.currentUser;
    if (user == null) {
      if (!isSilent) throw Exception('يجب تسجيل الدخول أولاً لعمل نسخة احتياطية على السحابة');
      return;
    }
    if (_workshopId == null || _workshopId!.isEmpty) {
      if (!isSilent) throw Exception('لم يتم العثور على معرف الورشة الخاص بك للمزامنة');
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    // Every workshop member publishes transactional changes (orders,
    // customers, payments, etc.).  `cloud_backup` is intentionally not used
    // as a gate here: it must never leave a worker's change on one phone.

    Map<String, dynamic> allData = await _db.exportAllData();
    final expectedRowCounts = <String, int>{
      for (final entry in allData.entries)
        entry.key: entry.value is List ? (entry.value as List).length : 0,
    };

    if (isSilent) {
      // فحص أولي: تجاهل الرفع إذا كانت جميع الجداول فارغة
      final hasAnyData = allData.values.any(
            (rows) => rows is List && rows.isNotEmpty,
      );
      if (!hasAnyData) return;

    }

    final latestDocRef = _firestore
        .collection('workshops')
        .doc(_workshopId)
        .collection('backups')
        .doc('latest');

    final chunkRef = latestDocRef.collection('chunks');

    try {
      // 1. تغيير الحالة إلى "جاري الرفع"
      await latestDocRef.set({
        'timestamp': FieldValue.serverTimestamp(),
        'deviceId': _deviceId,
        'status': 'uploading',
        'tables': allData.keys.toList(),
      }).timeout(const Duration(seconds: 15));

      // 2. رفع الأجزاء الجديدة مباشرة (كتابة فوق نفس الأسماء table_0, table_1...)
      // بدون أي قراءة أو حذف مسبق للأجزاء القديمة — هذا ما يجعل الرفع سريعاً
      // ومتناسباً فقط مع حجم بياناتك الحالية.
      Map<String, int> newChunkCounts = {};
      WriteBatch uploadBatch = _firestore.batch();
      int batchCount = 0;
      for (String table in allData.keys) {
        List<dynamic> rows = allData[table] ?? [];
        final rawChunks = _partitionRowsIntoChunks(rows);
        final chunks = rawChunks.isEmpty
            ? <List<dynamic>>[<dynamic>[]]
            : rawChunks;
        int chunksCount = chunks.length;
        newChunkCounts[table] = chunksCount;

        for (int i = 0; i < chunksCount; i++) {
          final docRef = chunkRef.doc('${table}_$i');
          uploadBatch.set(docRef, {
            'table': table,
            'chunkIndex': i,
            'totalChunks': chunksCount,
            'data': chunks[i],
          });
          batchCount++;
          if (batchCount >= 300) {
            await uploadBatch.commit().timeout(const Duration(seconds: 30));
            uploadBatch = _firestore.batch();
            batchCount = 0;
          }
        }
      }
      if (batchCount > 0) {
        await uploadBatch.commit().timeout(const Duration(seconds: 30));
      }

      // A WriteBatch commit already fails when Firestore has not accepted the
      // write. For automatic sync, do not then read every chunk one-by-one:
      // on a large workshop that verification delayed a single worker order
      // for minutes and kept every other phone waiting for `completed`.
      // The Settings button keeps the full server-side verification below.
      final verifiedCounts = isSilent
          ? expectedRowCounts
          : await _verifyUploadedChunks(
              chunkRef: chunkRef,
              expectedChunkCounts: newChunkCounts,
              expectedRowCounts: expectedRowCounts,
            );

      // 3. إنهاء الرفع وتغيير الحالة إلى "مكتمل" — البيانات الجديدة أصبحت
      // آمنة ومقروءة بالكامل بالسحابة بهذه المرحلة، بغض النظر عمّا سيحدث بعدها.
      await latestDocRef
          .update({
            'status': 'completed',
            'tableRowCounts': verifiedCounts,
          })
          .timeout(const Duration(seconds: 10));

      final confirmation = await latestDocRef
          .get(GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 15));
      final confirmationData = confirmation.data();
      if (!confirmation.exists ||
          confirmationData?['status'] != 'completed' ||
          confirmationData?['deviceId'] != _deviceId) {
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
      lastBackupUploadSummary =
          'الطلبات: ${verifiedCounts['Commandes'] ?? 0}، '
          'الزبائن: ${verifiedCounts['Client'] ?? 0} '
          '(الورشة: $_workshopId)';

      await prefs.setBool('is_local_dirty', false);
      await _markTransactionalUploadConfirmed(uploadedGeneration);

      // 4. حفظ نسخة في الـ History
      if (!isSilent) {
        try {
          String historyId = DateTime.now().toIso8601String().replaceAll(':', '-');
          await _firestore
              .collection('workshops')
              .doc(_workshopId)
              .collection('backups_history')
              .doc(historyId)
              .set({
            'timestamp': FieldValue.serverTimestamp(),
            'note': 'Manual Backup',
          }).timeout(const Duration(seconds: 10));
        } catch (e) {
          print('History snapshot warning: $e');
        }
      }

      // 5. تنظيف الأجزاء الفائضة بالسحابة (في الخلفية دون تعطيل المستخدم)
      _cleanupObsoleteCloudChunks(chunkRef, newChunkCounts).catchError((e) {
        print('Background chunk cleanup warning: $e');
      });

    } catch (e) {
      print('backupToCloud failed: $e');
      throw Exception(
        'فشل رفع النسخة إلى '
        'workshops/${_workshopId}/backups/latest: '
        '${_describeCloudWriteFailure(e)}',
      );
    }
  }

  /// تنظيف الأجزاء الزائدة من الرفعة السابقة (مثل تحويل الجدول من 3 أجزاء إلى جزء واحد)
  Future<void> _cleanupObsoleteCloudChunks(
      CollectionReference chunkRef,
      Map<String, int> newChunkCounts,
      ) async {
    final oldSnap = await chunkRef.get().timeout(const Duration(seconds: 25));
    WriteBatch deleteBatch = _firestore.batch();
    int count = 0;

    for (var doc in oldSnap.docs) {
      final data = doc.data() as Map<String, dynamic>?;
      if (data == null) continue;
      String table = data['table']?.toString() ?? '';
      int idx = (data['chunkIndex'] as num?)?.toInt() ?? -1;

      if (table.isNotEmpty && idx >= 0) {
        int maxNewChunks = newChunkCounts[table] ?? 0;
        if (idx >= maxNewChunks) {
          deleteBatch.delete(doc.reference);
          count++;
        }
      }
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


  /// الاستعادة اليدوية/التلقائية من السحابة بنظام التجميع
  Future<void> fullRecoverySync() async {
    _beginRestore();
    try {
      await init();

      // If this device was closed while a worker's change was still waiting
      // for Firebase, publish it before downloading another phone's snapshot.
      // This keeps clients, orders, projects and task progress durable across
      // app restarts for every workshop member.
      if (await _hasPendingTransactions()) {
        try {
          await backupToCloud(isSilent: true);
        } catch (e) {
          print('Pending transaction upload before restore failed: $e');
        }
      }

      bool restoreSuccess = false;
      // 1. استرجاع النسخة الاحتياطية الخاصة بالورشة (تمسح الجداول وتعيدها)
      try {
        await restoreFromCloud();
        restoreSuccess = true;
      } catch (e) {
        print('New chunk sync failed: $e');
      }

      // 2. جلب البيانات من المجلد العام (Global Catalog) فقط إذا كانت قاعدة البيانات فارغة تماماً من الكتالوج
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

      // 3. استرجاع البيانات القديمة (الزبائن والطلبيات) بطريقة الدمج الذكي لتفادي الحذف
      await _legacySync();
      _dbUpdateController.add('');
    } finally {
      _endRestore();
    }
  }

  Future<void> _legacySync() async {
    try {
      final user = _auth.currentUser;
      if (user != null) {
        final targetUid = (_workshopId != null && _workshopId!.isNotEmpty) ? _workshopId! : user.uid;
        final userDoc = _firestore.collection('users').doc(targetUid);

        var clientsSnapshot = await userDoc.collection('Client').get();
        for (var doc in clientsSnapshot.docs) {
          try {
            final data = doc.data();
            await _db.insertOrUpdateSafeLegacy('Client', data, 'id');
          } catch (e) {
            print('Failed to sync legacy Client doc: $e');
          }
        }

        var cmdsSnapshot = await userDoc.collection('Commandes').get();
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
            await _db.insertOrUpdateSafeLegacy('WorkerTransactions', data, 'id');
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
              final id = (d.data()['id'] as num?)?.toInt() ?? int.tryParse(d.id) ?? 0;
              if (id > 0) deletedAchatIds.add(id);
            }
          } catch (_) {}
        }

        var achatsSnapshot = await userDoc.collection('Achats').get();
        for (var doc in achatsSnapshot.docs) {
          try {
            final data = doc.data();
            final achatId = (data['id'] as num?)?.toInt() ?? int.tryParse(doc.id) ?? 0;
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
        var achatItemsSnapshot = await userDoc
            .collection('Achat_items')
            .get();
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
  }

  Future<void> restoreFromCloud({bool preserveLocalChanges = false}) async {
    print("--- CloudSyncService: restoreFromCloud() started ---");
    await init();

    final user = _auth.currentUser;
    if (user == null) throw Exception('يجب تسجيل الدخول لاستعادة البيانات');
    if (_workshopId == null) {
      throw Exception('لم يتم العثور على ورشة خاصة بك للمزامنة');
    }

    final prefs = await SharedPreferences.getInstance();
    final isDirty = prefs.getBool('is_local_dirty') ?? false;
    final role = prefs.getString('user_role') ?? 'worker';

    // A restore is an explicit request to receive the cloud version. Do not
    // let an old local snapshot overwrite a newer order on another device.
    // Callers that truly need to preserve local edits can opt in explicitly.
    if (preserveLocalChanges && isDirty && role != 'worker') {
      print("--- CloudSyncService: Local changes exist (is_local_dirty). Uploading local data first before restore... ---");
      try {
        await backupToCloud(isSilent: true);
      } catch (e) {
        print('Pre-restore backup warning: $e');
      }
    }

    final latestDocRef = _firestore
        .collection('workshops')
        .doc(_workshopId)
        .collection('backups')
        .doc('latest');

    print("--- CloudSyncService: Fetching workshop/backups/latest... ---");
    DocumentSnapshot doc = await latestDocRef
        .get(GetOptions(source: Source.server))
        .timeout(
      const Duration(seconds: 20),
    );
    print("--- CloudSyncService: backups/latest fetched! ---");

    if (!doc.exists || doc.data() == null) {
      throw Exception('لم يتم العثور على نسخة احتياطية سابقة');
    }

    Map<String, dynamic> payload = doc.data() as Map<String, dynamic>;

    _beginRestore();
    try {
      // التوافقية مع النظام القديم (في حال وجود البيانات في المستند الرئيسي)
      if (payload.containsKey('data')) {
        Map<String, dynamic> data = payload['data'] as Map<String, dynamic>;
        print("--- CloudSyncService: importing legacy data ---");
        await _db.importAllData(data);
        await _db.relinkCurrentWorkerAllocations();
        print("--- CloudSyncService: Legacy data imported! ---");
        lastRestoreSummary = 'تم استرجاع النظام القديم (${data.length} جدول)';
      } else {
        // النظام الجديد: جلب الأجزاء (Chunks) وتجميعها
        print("--- CloudSyncService: Fetching workshop backup chunks... ---");
        var snapshot = await latestDocRef
            .collection('chunks')
            .get(GetOptions(source: Source.server))
            .timeout(const Duration(seconds: 35));
        print(
          "--- CloudSyncService: backup chunks fetched (${snapshot.docs.length}) ---",
        );
        Map<String, List<dynamic>> assembledData = {};

        for (var chunkDoc in snapshot.docs) {
          final chunkData = chunkDoc.data();
          String table = chunkData['table']?.toString() ?? '';
          if (table.isEmpty) {
            table = chunkDoc.id.replaceAll(RegExp(r'_\d+$'), '');
          }
          if (table.isEmpty) continue;

          assembledData.putIfAbsent(table, () => []);
          final rows = chunkData['data'];
          if (rows is List) {
            assembledData[table]!.addAll(rows);
          }
        }
        final publishedTables = payload['tables'];
        if (publishedTables is List) {
          for (final table in publishedTables) {
            if (table is String && table.isNotEmpty) {
              assembledData.putIfAbsent(table, () => []);
            }
          }
        }
        await _db.importAllData(assembledData);
        await _db.relinkCurrentWorkerAllocations();
        await _db.syncWorkerAllocationsStatusFromCloud();
        await _db.syncOrdersStatusFromCloud();
        // ⚠️ تطبيق علامات الحذف الدائمة بعد الاستيراد مباشرة
        await _applyDeletedAllocationsTombstones();
        await _applyDeletedAchatsTombstones();  // منع عودة المشتريات المحذوفة
        await _applyDeletedGlassTombstones();   // منع ظهور الزجاج المحذوف
        final summaryList = assembledData.entries
            .where((e) => e.value.isNotEmpty)
            .map((e) => '${e.key}: ${e.value.length}')
            .toList();
        lastRestoreSummary = 'مسترجع:\n' + summaryList.join('\n');
      }
      _dbUpdateController.add('');
      onDataRestored?.call();
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('is_local_dirty', false);
      } catch (e) {
        print('Failed to clear local dirty flag after restore: $e');
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
        final id = (doc.data()['id'] as num?)?.toInt() ?? int.tryParse(doc.id) ?? 0;
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
        final id = (doc.data()['id'] as num?)?.toInt() ?? int.tryParse(doc.id) ?? 0;
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
        final id = (doc.data()['id'] as num?)?.toInt() ?? int.tryParse(doc.id) ?? 0;
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
      throw Exception('رفع الكتالوج العام متاح للمدير فقط.');
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

    try {
      await catalogRef.set({
        'timestamp': FieldValue.serverTimestamp(),
        'deviceId': _deviceId,
        'status': 'uploading',
        'tables': globalData.keys.toList(),
      }).timeout(const Duration(seconds: 15));

      final chunkRef = catalogRef.collection('chunks');
      final newChunkCounts = <String, int>{};
      WriteBatch uploadBatch = _firestore.batch();
      int batchCount = 0;
      for (String table in globalData.keys) {
        List<dynamic> rows = globalData[table] ?? [];
        final rawChunks = _partitionRowsIntoChunks(rows);
        final chunks = rawChunks.isEmpty
            ? <List<dynamic>>[<dynamic>[]]
            : rawChunks;
        int chunksCount = chunks.length;
        newChunkCounts[table] = chunksCount;

        for (int i = 0; i < chunksCount; i++) {
          final docRef = chunkRef.doc('${table}_$i');
          uploadBatch.set(docRef, {
            'table': table,
            'chunkIndex': i,
            'totalChunks': chunksCount,
            'data': chunks[i],
          });
          batchCount++;
          if (batchCount >= 300) {
            await uploadBatch.commit().timeout(const Duration(seconds: 30));
            uploadBatch = _firestore.batch();
            batchCount = 0;
          }
        }
      }
      if (batchCount > 0) {
        await uploadBatch.commit().timeout(const Duration(seconds: 30));
      }

      // Do not consider the catalogue uploaded merely because the header was
      // written. Read every newly written chunk from the server and compare
      // its row count with the local table before reporting success.
      final verifiedCounts = await _verifyUploadedChunks(
        chunkRef: chunkRef,
        expectedChunkCounts: newChunkCounts,
        expectedRowCounts: expectedRowCounts,
      );

      await catalogRef
          .update({
            'status': 'completed',
            'tableRowCounts': verifiedCounts,
          })
          .timeout(const Duration(seconds: 10));

      final confirmation = await catalogRef
          .get(GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 15));
      final confirmationData = confirmation.data();
      if (!confirmation.exists ||
          confirmationData?['status'] != 'completed' ||
          confirmationData?['deviceId'] != _deviceId) {
        throw Exception('لم يؤكد الخادم اكتمال رفع الكتالوج.');
      }
      final confirmedCounts = confirmationData?['tableRowCounts'];
      if (confirmedCounts is! Map ||
          confirmedCounts['Colors'] != expectedRowCounts['Colors'] ||
          confirmedCounts['ShutterComponents'] !=
              expectedRowCounts['ShutterComponents']) {
        throw Exception(
          'لم يؤكد الخادم وصول جدول الألوان ومركبات الستائر.',
        );
      }
      lastCatalogUploadSummary =
          'الألوان: ${verifiedCounts['Colors'] ?? 0}، '
          'مركبات الستائر: ${verifiedCounts['ShutterComponents'] ?? 0} '
          '(الكتالوج العام)';
      await _markCatalogUploadConfirmed(catalogGeneration);
      _cleanupObsoleteCloudChunks(chunkRef, newChunkCounts).catchError((e) {
        print('Background catalog chunk cleanup warning: $e');
      });
    } catch (e) {
      try {
        await catalogRef.update({'status': 'failed'});
      } catch (_) {}
      throw Exception(
        'فشل رفع الكتالوج إلى '
        'global_catalog/latest: '
        '${_describeCloudWriteFailure(e)}',
      );
    }
  }

  Future<Map<String, int>> _verifyUploadedChunks({
    required CollectionReference<Map<String, dynamic>> chunkRef,
    required Map<String, int> expectedChunkCounts,
    required Map<String, int> expectedRowCounts,
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

  Future<void> downloadGlobalCatalog({bool discardPendingLocalChanges = false}) async {
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
        .timeout(
      const Duration(seconds: 15),
    );
    print("--- CloudSyncService: global_catalog/latest fetched! ---");

    if (!doc.exists || doc.data() == null) {
      final prefs = await SharedPreferences.getInstance();
      final role = prefs.getString('user_role') ?? 'worker';
      if (role == 'worker') {
        throw Exception(
          'الكتالوج العام لم يُنشر بعد. افتح صفحة المنتجات من هاتف المدير أولاً.',
        );
      }

      // First use: publish the manager's shared catalogue, then read that
      // confirmed server copy.
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
        'الكتالوج قيد التحديث على السيرفر، حاول مرة أخرى لاحقاً.',
      );
    }

    _beginRestore();
    try {
      if (payload.containsKey('data')) {
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
        print("--- CloudSyncService: Fetching catalog chunks... ---");
        var snapshot = await catalogRef
            .collection('chunks')
            .get(GetOptions(source: Source.server))
            .timeout(const Duration(seconds: 30));
        print(
          "--- CloudSyncService: chunks fetched (${snapshot.docs.length}) ---",
        );
        if (snapshot.docs.isEmpty) {
          throw Exception('الكتالوج على السيرفر فارغ.');
        }

        Map<String, List<dynamic>> assembledData = {};

        for (var chunkDoc in snapshot.docs) {
          final chunkData = chunkDoc.data();
          String table = chunkData['table']?.toString() ?? '';
          if (table.isEmpty) {
            table = chunkDoc.id.replaceAll(RegExp(r'_\d+$'), '');
          }
          if (table.isEmpty) continue;

          assembledData.putIfAbsent(table, () => []);
          final rows = chunkData['data'];
          if (rows is List) {
            assembledData[table]!.addAll(rows);
          }
        }

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
    const int maxChunkCharacters = 150000;
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
        rowSize = jsonEncode(row).length;
      } catch (_) {
        rowSize = 1000;
      }

      if (currentChunk.isNotEmpty && currentChunkSize + rowSize > maxChunkCharacters) {
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
      await _firestore
          .collection('workshops')
          .doc(_workshopId)
          .set({
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
          await prefs.setBool('system_active_${entry.key}', entry.value as bool? ?? true);
        }
        print('--- CloudSyncService: Workshop system modes applied from Firestore ---');
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
          print('--- CloudSyncService: Workshop active profiles applied (${activeIds.length} active) ---');
        }
      }
    } catch (e) {
      print('Error loading workshop systems: $e');
    }
  }
}
