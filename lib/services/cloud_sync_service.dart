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
      final savedCode = prefs.getString('workshop_code');
      if (savedCode != null && savedCode.isNotEmpty) {
        _workshopId = savedCode;
        print("--- CloudSyncService: Loaded workshopId from SharedPreferences: $_workshopId ---");
      } else {
        try {
          print("--- CloudSyncService: Fetching user doc from Firestore... ---");
          final doc = await _firestore
              .collection('users')
              .doc(user.uid)
              .get()
              .timeout(const Duration(seconds: 10));
          print("--- CloudSyncService: User doc fetched! ---");
          if (doc.exists && doc.data()?['workshopId'] != null) {
            _workshopId = doc.data()?['workshopId']?.toString();
            await prefs.setString('workshop_code', _workshopId!);
          } else {
            _workshopId = user.uid; // Fallback to user UID if not explicitly set
          }
        } catch (e) {
          print('Error fetching workshopId: $e');
          _workshopId = user.uid; // Fallback on error
        }
      }
    }
    print(
      "--- CloudSyncService: init() finished. workshopId = $_workshopId ---",
    );
  }

  /// بدء الاستماع لتحديثات السحابة لتطبيق المزامنة التلقائية
  void startListeningForUpdates(Function() onUpdateCallback) {
    onDataRestored = onUpdateCallback;
    final user = _auth.currentUser;
    if (user == null || _workshopId == null) return;

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
          final isDirty = prefs.getBool('is_local_dirty') ?? false;

          // نستمع فقط عندما تنتهي عملية الرفع (status == completed)
          // ولا نسترجع تلقائياً إذا كانت هناك تعديلات محلية لم تُرفع بعد لتفادي مسحها
          if (sourceDevice != _deviceId &&
              !_isRestoring &&
              !isDirty &&
              status == 'completed') {
            _isRestoring = true;
            try {
              // استدعاء دالة الاستعادة الموحدة
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
  }

  /// إيقاف الاستماع
  void stopListening() {
    _listener?.cancel();
  }

  /// إشعار بوجود تغيير محلي ليتم رفعه للسحابة (Debounced)
  void notifyChange() async {
    _dbUpdateController.add('');
    if (_isRestoring) return; // منع التكرار اللانهائي أثناء الاستعادة

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('is_local_dirty', true);
    } catch (e) {
      print('Failed to set local dirty flag: $e');
    }

    if (_debounceTimer?.isActive ?? false) _debounceTimer!.cancel();
    _debounceTimer = Timer(const Duration(seconds: 3), () {
      _silentBackup();
    });
  }

  /// الرفع الصامت للسحابة
  Future<void> _silentBackup() async {
    try {
      await backupToCloud(isSilent: true);
      // [تم الإصلاح]: إزالة التحقق من البريد الإلكتروني الثابت
      // يجب استخدام نظام صلاحيات صحيح بدلاً من ذلك
      // final user = _auth.currentUser;
      // if (user != null && _isGlobalAdmin(user)) {
      //   await backupGlobalCatalog();
      // }
    } catch (e) {
      print('Auto-sync backup failed: $e');
    }
  }

  /// الرفع اليدوي/الأساسي للسحابة بنظام التجزئة لتجاوز حد الـ 1MB
  /// الرفع اليدوي/الأساسي للسحابة بنظام التجزئة الدقيق والدفعي (WriteBatch)
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

    // إذا كان الحساب مسجلاً صراحة كـ "عامل" وليس مديراً أو مالكاً
    final bool isWorker = (role == 'worker');
    if (isWorker) {
      if (!isSilent) {
        throw Exception('حسابك كعامل لا يملك صلاحية الرفع إلى السحابة. يلزم حساب المدير.');
      }
      return;
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
      final hasTransactionalData =
          (commandesRows is List && commandesRows.isNotEmpty) ||
          (clientRows is List && clientRows.isNotEmpty) ||
          (commandesDetailsRows is List && commandesDetailsRows.isNotEmpty);
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

    try {
      // 1. تغيير الحالة إلى "جاري الرفع"
      await latestDocRef.set({
        'timestamp': FieldValue.serverTimestamp(),
        'deviceId': _deviceId,
        'status': 'uploading',
      }).timeout(const Duration(seconds: 15));

      final chunkRef = latestDocRef.collection('chunks');
      
      // 2. مسح الأجزاء القديمة دفعة واحدة (WriteBatch)
      final existingChunks = await chunkRef.get().timeout(const Duration(seconds: 15));
      if (existingChunks.docs.isNotEmpty) {
        WriteBatch deleteBatch = _firestore.batch();
        int count = 0;
        for (var doc in existingChunks.docs) {
          deleteBatch.delete(doc.reference);
          count++;
          if (count >= 400) {
            await deleteBatch.commit().timeout(const Duration(seconds: 15));
            deleteBatch = _firestore.batch();
            count = 0;
          }
        }
        if (count > 0) {
          await deleteBatch.commit().timeout(const Duration(seconds: 15));
        }
      }

      // 3. رفع الأجزاء الجديدة دفعة واحدة (WriteBatch) لسرعة فائقة بدون تعليق
      WriteBatch uploadBatch = _firestore.batch();
      int batchCount = 0;
      for (String table in allData.keys) {
        List<dynamic> rows = allData[table] ?? [];
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
          if (batchCount >= 400) {
            await uploadBatch.commit().timeout(const Duration(seconds: 20));
            uploadBatch = _firestore.batch();
            batchCount = 0;
          }
        }
      }
      if (batchCount > 0) {
        await uploadBatch.commit().timeout(const Duration(seconds: 20));
      }

      // 4. إنهاء الرفع وتغيير الحالة إلى "مكتمل"
      await latestDocRef.update({'status': 'completed'}).timeout(const Duration(seconds: 10));

      await prefs.setBool('is_local_dirty', false);

      // 5. حفظ نسخة في الـ History
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
    } catch (e) {
      try {
        await latestDocRef.update({'status': 'failed'});
      } catch (_) {}
      throw Exception('فشل الرفع إلى السحابة: $e');
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

      // 2. جلب البيانات من المجلد العام (Global Catalog) (يمسح ويعيد مركبات الستار)
      // نقوم بتحميل الكتالوج العام فقط إذا لم ننجح في استعادة النسخة الاحتياطية للورشة (مثلاً ورشة جديدة)
      if (!restoreSuccess) {
        try {
          await downloadGlobalCatalog();
        } catch (e) {
          print('Global catalog sync failed: $e');
        }
      }

      // 3. استرجاع البيانات القديمة (الزبائن والطلبيات) بطريقة الدمج الذكي لتفادي الحذف
      await _legacySync();

      notifyChange();
    } finally {
      _isRestoring = false;
    }
  }

  Future<void> _legacySync() async {
    try {
      final user = _auth.currentUser;
      if (user != null) {
        final userDoc = _firestore.collection('users').doc(user.uid);

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
      const Duration(seconds: 15),
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
        print("--- CloudSyncService: Legacy data imported! ---");
        lastRestoreSummary = 'تم استرجاع النظام القديم (${data.length} جدول)';
      } else {
        // النظام الجديد: جلب الأجزاء (Chunks) وتجميعها
        print("--- CloudSyncService: Fetching workshop backup chunks... ---");
        var snapshot = await latestDocRef
            .collection('chunks')
            .get()
            .timeout(const Duration(seconds: 30));
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
        await _db.syncWorkerAllocationsStatusFromCloud();
        final summaryList = assembledData.entries
            .where((e) => e.value.isNotEmpty)
            .map((e) => '${e.key}: ${e.value.length}')
            .toList();
        lastRestoreSummary = 'مسترجع:\n' + summaryList.join('\n');
      }
      _dbUpdateController.add('');
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
    // [تم الإصلاح]: إزالة التحقق من البريد الإلكتروني الثابت
    // يجب استخدام نظام صلاحيات صحيح
    if (user == null) return;
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
      final existingChunks = await chunkRef.get().timeout(const Duration(seconds: 15));
      if (existingChunks.docs.isNotEmpty) {
        WriteBatch deleteBatch = _firestore.batch();
        int count = 0;
        for (var doc in existingChunks.docs) {
          deleteBatch.delete(doc.reference);
          count++;
          if (count >= 400) {
            await deleteBatch.commit().timeout(const Duration(seconds: 15));
            deleteBatch = _firestore.batch();
            count = 0;
          }
        }
        if (count > 0) {
          await deleteBatch.commit().timeout(const Duration(seconds: 15));
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
          if (batchCount >= 400) {
            await uploadBatch.commit().timeout(const Duration(seconds: 20));
            uploadBatch = _firestore.batch();
            batchCount = 0;
          }
        }
      }
      if (batchCount > 0) {
        await uploadBatch.commit().timeout(const Duration(seconds: 20));
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
    if (rows.isEmpty) return [[]];
    // limit size to ~500 KB to fit comfortably within Firestore 1MB document limit
    const int maxChunkCharacters = 500000;
    final List<List<dynamic>> chunks = [];
    List<dynamic> currentChunk = [];
    int currentChunkSize = 0;

    for (var row in rows) {
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
}
