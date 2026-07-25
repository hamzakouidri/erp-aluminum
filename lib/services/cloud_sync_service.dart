import 'dart:async';
import 'dart:math';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
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
  StreamSubscription<DocumentSnapshot>? _listener;
  StreamSubscription<QuerySnapshot>? _statusListener;
  StreamSubscription<QuerySnapshot>? _orderStatusListener;
  StreamSubscription<QuerySnapshot>? _measurementsListener;
  bool _isRestoring = false;

  final StreamController<String> _dbUpdateController = StreamController<String>.broadcast();
  Stream<String> get dbUpdateStream => _dbUpdateController.stream;

  // Callback to refresh UI when auto-restore happens
  Function()? onDataRestored;

  String? _workshopId;
  String? get workshopId => _workshopId;
  String lastRestoreSummary = 'لم يتم الاسترجاع بعد';

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
          final role = data['role']?.toString() ?? 'worker';
          final wId = data['workshopId']?.toString() ?? '';
          if (role == 'worker' && wId.isNotEmpty && wId != user.uid) {
            _workshopId = wId;
          } else if (wId.isNotEmpty) {
            _workshopId = wId;
          } else {
            _workshopId = user.uid;
          }
          await prefs.setString('workshop_code', _workshopId!);
          await prefs.setString('user_role', role);
        } else {
          _workshopId = prefs.getString('workshop_code') ?? user.uid;
        }
      } catch (e) {
        print('Error fetching workshopId: $e');
        _workshopId = prefs.getString('workshop_code') ?? user.uid;
      }
    }
    print(
      "--- CloudSyncService: init() finished. workshopId = $_workshopId ---",
    );
  }

  void reset() {
    _workshopId = null;
    _listener?.cancel();
    _statusListener?.cancel();
    _orderStatusListener?.cancel();
    _measurementsListener?.cancel();
    _listener = null;
    _statusListener = null;
    _orderStatusListener = null;
    _measurementsListener = null;
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

      Map<String, dynamic> payload = doc.data() as Map<String, dynamic>;
      String sourceDevice = payload['deviceId']?.toString() ?? '';
      String status = payload['status']?.toString() ?? '';

      final prefs = await SharedPreferences.getInstance();
      final userRole = prefs.getString('user_role') ?? 'worker';
      final isWorker = (userRole == 'worker');

      bool shouldAutoRestore = false;
      if (isWorker) {
        shouldAutoRestore = (status == 'completed' && !_isRestoring);
      } else {
        shouldAutoRestore = (sourceDevice != _deviceId && !_isRestoring && status == 'completed');
      }

      if (shouldAutoRestore) {
        _isRestoring = true;
        try {
          await restoreFromCloud();
          if (onDataRestored != null) {
            onDataRestored!();
          }
        } catch (e) {
          print('Error auto-restoring from cloud: $e');
        } finally {
          _isRestoring = false;
        }
      }
    });

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
        if (onDataRestored != null) {
          onDataRestored!();
        }
      } catch (e) {
        print('Error syncing allocation status real-time: $e');
      }
    });

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
        if (onDataRestored != null) {
          onDataRestored!();
        }
      } catch (e) {
        print('Error syncing order status real-time: $e');
      }
    });

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
        if (onDataRestored != null) {
          onDataRestored!();
        }
      } catch (e) {
        print('Error syncing confirmed measurements real-time: $e');
      }
    });
  }

  /// إيقاف الاستماع
  void stopListening() {
    _listener?.cancel();
    _statusListener?.cancel();
    _orderStatusListener?.cancel();
    _measurementsListener?.cancel();
    _listener = null;
    _statusListener = null;
    _orderStatusListener = null;
    _measurementsListener = null;
  }

  /// إشعار بوجود تغيير محلي ليتم رفعه للسحابة (Debounced)
  void notifyChange() async {
    _dbUpdateController.add('');
    if (_isRestoring) return; // منع التكرار اللانهائي أثناء الاستعادة

    try {
      final prefs = await SharedPreferences.getInstance();
      final userRole = prefs.getString('user_role') ?? 'worker';
      if (userRole == 'worker') {
        // 🛑 العامل لا يعلم علامة "is_local_dirty" كي لا يمنع المزامنة التلقائية للمهام الواردة من المدير
        return;
      }
      await prefs.setBool('is_local_dirty', true);
    } catch (e) {
      print('Failed to set local dirty flag: $e');
    }

    if (_debounceTimer?.isActive ?? false) _debounceTimer!.cancel();
    _debounceTimer = Timer(const Duration(seconds: 1), () {
      _silentBackup();
    });
  }

  /// الرفع الصامت للسحابة
  Future<void> _silentBackup() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userRole = prefs.getString('user_role') ?? 'worker';
      if (userRole == 'worker') {
        // 🛑 منع العامل من الكتابة الصامتة فوق نسخة الورشة السحابية الخاضعة للمدير
        return;
      }
      await backupToCloud(isSilent: true);
    } catch (e) {
      print('Auto-sync backup failed: $e');
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
  Future<void> backupToCloud({bool isSilent = false}) async {
    await init();

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
    final role = prefs.getString('user_role') ?? '';

    final bool isWorker = (role == 'worker');
    if (isWorker) {
      bool hasBackupPerm = false;
      try {
        final userDoc = await _firestore.collection('users').doc(user.uid).get();
        if (userDoc.exists && userDoc.data() != null) {
          final pData = userDoc.data()!['permissions'];
          final pJson = userDoc.data()!['permissions_json'];
          if (pData is Map && pData['cloud_backup'] == true) {
            hasBackupPerm = true;
          } else if (pJson is String && pJson.contains('"cloud_backup":true')) {
            hasBackupPerm = true;
          }
        }
      } catch (_) {}

      if (!hasBackupPerm) {
        if (!isSilent) {
          throw Exception('حسابك لا يملك صلاحية الرفع إلى السحابة. يلزم مفتاح الصلاحية من المدير.');
        }
        return;
      }
    }

    Map<String, dynamic> allData = await _db.exportAllData();

    if (isSilent) {
      // فحص أولي: تجاهل الرفع إذا كانت جميع الجداول فارغة
      final hasAnyData = allData.values.any(
            (rows) => rows is List && rows.isNotEmpty,
      );
      if (!hasAnyData) return;

      // فحص ثانوي أكثر أماناً: لا ترفع إذا كانت جداول المعاملات الرئيسية كلها فارغة.
      final commandesRows = allData['Commandes'];
      final clientRows = allData['Client'];
      final commandesDetailsRows = allData['Commandes_details'];
      final workerAllocationsRows = allData['WorkerAllocations'];
      final hasTransactionalData =
          (commandesRows is List && commandesRows.isNotEmpty) ||
              (clientRows is List && clientRows.isNotEmpty) ||
              (commandesDetailsRows is List && commandesDetailsRows.isNotEmpty) ||
              (workerAllocationsRows is List && workerAllocationsRows.isNotEmpty);
      if (!hasTransactionalData) {
        print(
          'backupToCloud (silent): Aborting — no transactional data on this device. '
              'Will not overwrite cloud backup with an empty database.',
        );
        return;
      }
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
      }).timeout(const Duration(seconds: 15));

      // 2. رفع الأجزاء الجديدة مباشرة (كتابة فوق نفس الأسماء table_0, table_1...)
      // بدون أي قراءة أو حذف مسبق للأجزاء القديمة — هذا ما يجعل الرفع سريعاً
      // ومتناسباً فقط مع حجم بياناتك الحالية.
      Map<String, int> newChunkCounts = {};
      WriteBatch uploadBatch = _firestore.batch();
      int batchCount = 0;
      for (String table in allData.keys) {
        List<dynamic> rows = allData[table] ?? [];
        final chunks = _partitionRowsIntoChunks(rows);
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

      // 3. إنهاء الرفع وتغيير الحالة إلى "مكتمل" — البيانات الجديدة أصبحت
      // آمنة ومقروءة بالكامل بالسحابة بهذه المرحلة، بغض النظر عمّا سيحدث بعدها.
      await latestDocRef.update({'status': 'completed'}).timeout(const Duration(seconds: 10));

      await prefs.setBool('is_local_dirty', false);

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
          print('History backup failed: $e');
        }
      }

      // 5. تنظيف الأجزاء الزائدة من رفعات سابقة (لو قلّ عدد صفوف جدول ما، أو
      // اختفى جدول بالكامل). يتم بالخلفية (fire-and-forget) ولا يؤخر إتمام
      // الرفع للمستخدم، ولا يفشّل عملية الرفع لو حصل به خطأ.
      unawaited(
        _cleanupStaleChunks(chunkRef, newChunkCounts).catchError((e) {
          print('Chunk cleanup warning (non-fatal): $e');
        }),
      );
    } catch (e) {
      try {
        await latestDocRef.update({'status': 'failed'});
      } catch (_) {}
      throw Exception('فشل الرفع إلى السحابة: $e');
    }
  }

  /// حذف الأجزاء (chunks) الفائضة المتبقية من رفعة سابقة والتي لم تعد مطلوبة
  /// بعد الرفعة الجديدة الناجحة — إما لأن جدولاً معيناً اختفى بالكامل، أو لأن
  /// عدد أجزائه أصبح أقل من قبل. لا تُستدعى إلا بعد نجاح رفع البيانات الجديدة.
  Future<void> _cleanupStaleChunks(
      CollectionReference<Map<String, dynamic>> chunkRef,
      Map<String, int> newChunkCounts,
      ) async {
    final existingChunks = await chunkRef.get().timeout(const Duration(seconds: 60));
    if (existingChunks.docs.isEmpty) return;

    WriteBatch deleteBatch = _firestore.batch();
    int count = 0;
    for (var doc in existingChunks.docs) {
      final data = doc.data();
      final table = data['table']?.toString() ??
          doc.id.replaceAll(RegExp(r'_\d+$'), '');
      final chunkIndex = data['chunkIndex'] is int
          ? data['chunkIndex'] as int
          : int.tryParse(doc.id.split('_').last) ?? -1;
      final currentCount = newChunkCounts[table];

      // هذا الجزء فائض إذا: الجدول لم يعد موجوداً بالرفعة الجديدة إطلاقاً،
      // أو كان مؤشره خارج نطاق عدد أجزاء الرفعة الجديدة لنفس الجدول.
      final isStale = currentCount == null || chunkIndex >= currentCount;
      if (isStale) {
        deleteBatch.delete(doc.reference);
        count++;
        if (count >= 10) {
          await deleteBatch.commit().timeout(const Duration(seconds: 25));
          deleteBatch = _firestore.batch();
          count = 0;
        }
      }
    }
    if (count > 0) {
      await deleteBatch.commit().timeout(const Duration(seconds: 25));
    }
  }

  /// الاستعادة اليدوية/التلقائية من السحابة بنظام التجميع
  Future<void> fullRecoverySync() async {
    _isRestoring = true;
    try {
      await init();

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
      _isRestoring = false;
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

        var achatsSnapshot = await userDoc.collection('Achats').get();
        for (var doc in achatsSnapshot.docs) {
          try {
            final data = doc.data();
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

  Future<void> restoreFromCloud() async {
    print("--- CloudSyncService: restoreFromCloud() started ---");
    await init();

    final user = _auth.currentUser;
    if (user == null) throw Exception('يجب تسجيل الدخول لاستعادة البيانات');
    if (_workshopId == null) {
      throw Exception('لم يتم العثور على ورشة خاصة بك للمزامنة');
    }

    final latestDocRef = _firestore
        .collection('workshops')
        .doc(_workshopId)
        .collection('backups')
        .doc('latest');

    print("--- CloudSyncService: Fetching workshop/backups/latest... ---");
    DocumentSnapshot doc = await latestDocRef.get().timeout(
      const Duration(seconds: 20),
    );
    print("--- CloudSyncService: backups/latest fetched! ---");

    if (!doc.exists || doc.data() == null) {
      throw Exception('لم يتم العثور على نسخة احتياطية سابقة');
    }

    Map<String, dynamic> payload = doc.data() as Map<String, dynamic>;

    _isRestoring = true;
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
            .get()
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
        await _db.importAllData(assembledData);
        await _db.relinkCurrentWorkerAllocations();
        await _db.syncWorkerAllocationsStatusFromCloud();
        await _db.syncOrdersStatusFromCloud();
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
      _isRestoring = false;
    }
  }

  // ==================== Global Catalog ====================
  Future<void> backupGlobalCatalog() async {
    await init();

    final user = _auth.currentUser;
    if (user == null) {
      throw Exception('يجب تسجيل الدخول أولاً لرفع الكتالوج العام');
    }
    // if (!_isGlobalAdmin(user)) return;

    Map<String, dynamic> globalData = await _db.exportGlobalCatalog();
    final catalogRef = _firestore.collection('global_catalog').doc('latest');

    try {
      await catalogRef.set({
        'timestamp': FieldValue.serverTimestamp(),
        'deviceId': _deviceId,
        'status': 'uploading',
      }).timeout(const Duration(seconds: 15));

      final chunkRef = catalogRef.collection('chunks');
      final existingChunks = await chunkRef.get().timeout(const Duration(seconds: 25));
      if (existingChunks.docs.isNotEmpty) {
        WriteBatch deleteBatch = _firestore.batch();
        int count = 0;
        for (var doc in existingChunks.docs) {
          deleteBatch.delete(doc.reference);
          count++;
          if (count >= 10) {
            await deleteBatch.commit().timeout(const Duration(seconds: 25));
            deleteBatch = _firestore.batch();
            count = 0;
          }
        }
        if (count > 0) {
          await deleteBatch.commit().timeout(const Duration(seconds: 25));
        }
      }

      WriteBatch uploadBatch = _firestore.batch();
      int batchCount = 0;
      for (String table in globalData.keys) {
        List<dynamic> rows = globalData[table] ?? [];
        final chunks = _partitionRowsIntoChunks(rows);
        int chunksCount = chunks.length;

        for (int i = 0; i < chunksCount; i++) {
          final docRef = chunkRef.doc('${table}_$i');
          uploadBatch.set(docRef, {
            'table': table,
            'chunkIndex': i,
            'totalChunks': chunksCount,
            'data': chunks[i],
          });
          batchCount++;
          if (batchCount >= 2) {
            await uploadBatch.commit().timeout(const Duration(seconds: 30));
            uploadBatch = _firestore.batch();
            batchCount = 0;
          }
        }
      }
      if (batchCount > 0) {
        await uploadBatch.commit().timeout(const Duration(seconds: 30));
      }

      await catalogRef.update({'status': 'completed'}).timeout(const Duration(seconds: 10));
    } catch (e) {
      try {
        await catalogRef.update({'status': 'failed'});
      } catch (_) {}
      throw Exception('فشل رفع الكتالوج العام: $e');
    }
  }

  Future<void> downloadGlobalCatalog() async {
    print("--- CloudSyncService: downloadGlobalCatalog() started ---");
    await init();

    final catalogRef = _firestore.collection('global_catalog').doc('latest');
    print("--- CloudSyncService: Fetching global_catalog/latest... ---");
    DocumentSnapshot doc = await catalogRef.get().timeout(
      const Duration(seconds: 15),
    );
    print("--- CloudSyncService: global_catalog/latest fetched! ---");

    if (!doc.exists || doc.data() == null) {
      throw Exception('لم يتم العثور على الكتالوج العالمي في السيرفر.');
    }

    Map<String, dynamic> payload = doc.data() as Map<String, dynamic>;
    final status = payload['status']?.toString() ?? '';
    if (status.isNotEmpty && status != 'completed') {
      throw Exception(
        'الكتالوج قيد التحديث على السيرفر، حاول مرة أخرى لاحقاً.',
      );
    }

    _isRestoring = true;
    try {
      if (payload.containsKey('data')) {
        final raw = payload['data'];
        if (raw is! Map) {
          throw Exception('صيغة بيانات الكتالوج غير صالحة على السيرفر.');
        }
        await _db.importGlobalCatalog(Map<String, dynamic>.from(raw));
      } else {
        print("--- CloudSyncService: Fetching catalog chunks... ---");
        var snapshot = await catalogRef
            .collection('chunks')
            .get()
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

        await _db.importGlobalCatalog(assembledData);
      }
    } finally {
      _isRestoring = false;
    }
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