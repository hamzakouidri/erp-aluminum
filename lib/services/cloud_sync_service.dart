import 'dart:async';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:database_data/sql_database.dart';

import 'package:shared_preferences/shared_preferences.dart';

class CloudSyncService {
  // Singleton pattern so we only have one listener and one deviceId
  static final CloudSyncService _instance = CloudSyncService._internal();
  factory CloudSyncService() => _instance;
  
  CloudSyncService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final SqlDatabase _db = SqlDatabase();

  String _deviceId = '';
  Timer? _debounceTimer;
  StreamSubscription<DocumentSnapshot>? _listener;
  bool _isRestoring = false;

  // Callback to refresh UI when auto-restore happens
  Function()? onDataRestored;
  
  String? _workshopId;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    String? storedId = prefs.getString('device_id');
    if (storedId == null) {
      final rnd = Random();
      storedId = 'device_${DateTime.now().millisecondsSinceEpoch}_${rnd.nextInt(100000)}';
      await prefs.setString('device_id', storedId);
    }
    _deviceId = storedId;

    final user = _auth.currentUser;
    if (user != null) {
      try {
        final doc = await _firestore.collection('users').doc(user.uid).get();
        if (doc.exists) {
          _workshopId = doc.data()?['workshopId'];
        }
      } catch (e) {
        print('Error fetching workshopId: $e');
      }
    }
  }



  /// بدء الاستماع لتحديثات السحابة لتطبيق المزامنة التلقائية (توضع في بداية التطبيق)
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
      String sourceDevice = payload['deviceId'] ?? '';
      
      // إذا كان التحديث من جهاز آخر وليس من هاتفي الحالي
      if (sourceDevice != _deviceId && !_isRestoring) {
        _isRestoring = true;
        try {
          Map<String, dynamic> data = payload['data'] as Map<String, dynamic>;
          await _db.importAllData(data);
          // تنبيه واجهة المستخدم بضرورة التحديث
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
  void notifyChange() {
    if (_isRestoring) return; // لا نرفع شيء أثناء الاستعادة التلقائية لكي لا يحدث تكرار لانهائي
    
    // الانتظار 3 ثوانٍ، وإذا حدث تغيير آخر خلالها يتم إلغاء القديم وتوقيت 3 ثوانٍ جديدة
    if (_debounceTimer?.isActive ?? false) _debounceTimer!.cancel();
    _debounceTimer = Timer(const Duration(seconds: 3), () {
      _silentBackup();
    });
  }

  /// الرفع الصامت للسحابة (يُستخدم في المزامنة التلقائية)
  Future<void> _silentBackup() async {
    try {
      await backupToCloud();
      final user = _auth.currentUser;
      if (user != null && user.email == 'kouidrihamza45@gmail.com') {
        await backupGlobalCatalog();
      }
    } catch (e) {
      print('Auto-sync backup failed: $e');
    }
  }

  /// الرفع اليدوي/الأساسي للسحابة
  Future<void> backupToCloud() async {
    final user = _auth.currentUser;
    if (user == null) {
      throw Exception('يجب تسجيل الدخول لعمل نسخة احتياطية');
    }
    if (_workshopId == null) {
      throw Exception('لم يتم العثور على ورشة خاصة بك للمزامنة');
    }

    // 1. قراءة كل البيانات من الجداول المحلية
    Map<String, dynamic> allData = await _db.exportAllData();

    // 2. تجهيز البيانات ووضع معرف الجهاز
    Map<String, dynamic> backupPayload = {
      'timestamp': FieldValue.serverTimestamp(),
      'deviceId': _deviceId,
      'data': allData,
    };

    // 3. رفع البيانات إلى فايرستور مع حد أقصى للوقت (15 ثانية)
    await _firestore
        .collection('workshops')
        .doc(_workshopId)
        .collection('backups')
        .doc('latest')
        .set(backupPayload)
        .timeout(const Duration(seconds: 15), onTimeout: () {
          throw Exception('انتهى وقت الاتصال بالسيرفر. تأكد من جودة الإنترنت وحاول مجدداً.');
        });
  }

  /// الاستعادة اليدوية من السحابة
  Future<void> restoreFromCloud() async {
    final user = _auth.currentUser;
    if (user == null) {
      throw Exception('يجب تسجيل الدخول لاستعادة البيانات');
    }
    if (_workshopId == null) {
      throw Exception('لم يتم العثور على ورشة خاصة بك للمزامنة');
    }

    DocumentSnapshot doc = await _firestore
        .collection('workshops')
        .doc(_workshopId)
        .collection('backups')
        .doc('latest')
        .get();

    if (!doc.exists || doc.data() == null) {
      throw Exception('لم يتم العثور على نسخة احتياطية سابقة');
    }

    Map<String, dynamic> payload = doc.data() as Map<String, dynamic>;
    Map<String, dynamic> data = payload['data'] as Map<String, dynamic>;

    _isRestoring = true;
    try {
      await _db.importAllData(data);
    } finally {
      _isRestoring = false;
    }
  }

  // ==================== Global Catalog ====================
  Future<void> backupGlobalCatalog() async {
    final user = _auth.currentUser;
    if (user == null || user.email != 'kouidrihamza45@gmail.com') {
      return;
    }

    Map<String, dynamic> globalData = await _db.exportGlobalCatalog();

    Map<String, dynamic> backupPayload = {
      'timestamp': FieldValue.serverTimestamp(),
      'deviceId': _deviceId,
      'data': globalData,
    };

    await _firestore
        .collection('global_catalog')
        .doc('latest')
        .set(backupPayload)
        .timeout(const Duration(seconds: 15), onTimeout: () {
          print('Global catalog backup timeout');
        });
  }

  Future<void> downloadGlobalCatalog() async {
    DocumentSnapshot doc = await _firestore
        .collection('global_catalog')
        .doc('latest')
        .get();

    if (!doc.exists || doc.data() == null) {
      throw Exception('لم يتم العثور على الكتالوج العالمي في السيرفر.');
    }

    Map<String, dynamic> payload = doc.data() as Map<String, dynamic>;
    Map<String, dynamic> data = payload['data'] as Map<String, dynamic>;

    _isRestoring = true;
    try {
      await _db.importGlobalCatalog(data);
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
}
