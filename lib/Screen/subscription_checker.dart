import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'subscription_expired_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../settings/app_settings.dart';
import 'app_workspace_shell.dart';
import 'package:database_data/sql_database.dart';
import 'package:database_data/services/cloud_sync_service.dart';

class SubscriptionChecker extends StatefulWidget {
  const SubscriptionChecker({super.key});

  @override
  State<SubscriptionChecker> createState() => _SubscriptionCheckerState();
}

class _SubscriptionCheckerState extends State<SubscriptionChecker> {
  Timer? _subscriptionClock;

  @override
  void initState() {
    super.initState();
    _subscriptionClock = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _subscriptionClock?.cancel();
    super.dispose();
  }

  DateTime? _cloudDate(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value == null) return null;
    return DateTime.tryParse(value.toString());
  }

  bool _hasActiveSubscription(Map<String, dynamic> data) {
    final status = data['subscriptionStatus']?.toString().toLowerCase().trim();
    if (status == 'active') return true;
    if (status == 'expired' ||
        status == 'blocked' ||
        status == 'cancelled' ||
        status == 'canceled') {
      return false;
    }

    final expiresAt = _cloudDate(
      data['trialEndDate'] ??
          data['subscriptionEndDate'] ??
          data['subscriptionExpiresAt'] ??
          data['expiresAt'],
    );
    if (expiresAt != null) {
      return DateTime.now().isBefore(expiresAt);
    }

    return status == null || status.isEmpty;
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Scaffold(
        body: Center(child: Text('عذراً، يجب تسجيل الدخول.')),
      );
    }

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const Scaffold(
            backgroundColor: Colors.white,
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (snapshot.hasError) {
          return Scaffold(
            body: Center(
              child: Text('حدث خطأ أثناء فحص الاشتراك: ${snapshot.error}'),
            ),
          );
        }

        if (!snapshot.hasData) {
          return const Scaffold(
            backgroundColor: Colors.white,
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (!snapshot.data!.exists) {
          if (isApplicationAdminEmail(user.email)) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              FirebaseFirestore.instance
                  .collection('users')
                  .doc(user.uid)
                  .set({
                    'email': user.email,
                    'role': 'admin',
                    'subscriptionStatus': 'active',
                    'isBlocked': false,
                    'workshopId': user.uid,
                  }, SetOptions(merge: true))
                  .catchError((error) {
                    debugPrint('Admin bootstrap error: $error');
                  });
            });
            return const Scaffold(
              backgroundColor: Colors.white,
              body: Center(child: CircularProgressIndicator()),
            );
          }
          return Scaffold(
            backgroundColor: Colors.white,
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.error_outline,
                      color: Colors.red,
                      size: 80,
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      'الحساب غير مسجل',
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.red,
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'لم يتم العثور على حساب مسجل لهذا البريد الإلكتروني في النظام. يرجى إنشاء حساب جديد أولاً.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 16,
                        color: Colors.black54,
                      ),
                    ),
                    const SizedBox(height: 32),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 12,
                        ),
                      ),
                      onPressed: () async {
                        try {
                          await FirebaseAuth.instance.signOut();
                          await GoogleSignIn().signOut();
                          await SqlDatabase.clearAllLocalData();
                        } catch (e) {
                          debugPrint('Sign out error: $e');
                        }
                      },
                      icon: const Icon(Icons.logout),
                      label: const Text(
                        'تسجيل الخروج والعودة',
                        style: TextStyle(fontFamily: 'Cairo', fontSize: 16),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        final data = snapshot.data!.data() as Map<String, dynamic>;

        // Safety fix: Auto-correct Firestore document if admin has incorrect role/workshopId
        if (isApplicationAdminEmail(user.email)) {
          if (data['role'] != 'admin' || data['workshopId'] != user.uid) {
            FirebaseFirestore.instance
                .collection('users')
                .doc(user.uid)
                .update({'role': 'admin', 'workshopId': user.uid})
                .catchError((_) {});
          }
        }

        final bool isAdmin =
            (data['role'] == 'admin' || isApplicationAdminEmail(user.email));

        // Sync role to SharedPreferences and trigger AppSettingsProvider
        // ✅ الافتراضي هو 'worker' وليس 'manager' لمنع الوصول غير المصرح به
        final rawRole = data['role']?.toString();
        final role = isAdmin
            ? 'admin'
            : ((rawRole == 'manager' || data['workshopId'] == user.uid)
                  ? 'manager'
                  : (rawRole == 'co_manager' ? 'co_manager' : 'worker'));
        final workshopId = data['workshopId']?.toString() ?? '';
        final workshopName = data['workshopName']?.toString() ?? '';

        final String displayName =
            (data['displayName'] as String?)?.trim().isNotEmpty == true
            ? data['displayName'].toString()
            : (user.displayName?.trim().isNotEmpty == true
                  ? user.displayName!
                  : (data['role'] == 'manager' ? 'مدير الورشة' : 'عامل'));

        WidgetsBinding.instance.addPostFrameCallback((_) async {
          final prefs = await SharedPreferences.getInstance();
          final currentRole = prefs.getString('user_role');
          final currentWorkshop = prefs.getString('workshop_code');
          final currentWorkshopName = prefs.getString('workshop_name');
          final currentDisplayName = prefs.getString('user_display_name');
          final currentPermissionsFingerprint =
              prefs.getString('permissions_cloud_fingerprint') ?? '';

          // Permission changes do not necessarily change a worker's role or
          // workshop. Keep an explicit fingerprint so the computer reloads
          // permissions for every manager-side switch change.
          final rawPermissionsJson = data['permissions_json'];
          final permissionsFingerprint = rawPermissionsJson is String
              ? rawPermissionsJson
              : data['permissions'] is Map
              ? jsonEncode(data['permissions'])
              : '';

          String logoBase64 =
              data['workshopLogoUrl']?.toString() ??
              data['logoUrl']?.toString() ??
              '';
          String resolvedWorkshopName = workshopName;
          if (resolvedWorkshopName == workshopId) {
            resolvedWorkshopName =
                ''; // إذا كان اسم الورشة مساوياً للكود، نعيد تعيينه لجلبه الصحيح من حساب المدير
          }

          // ✅ بالنسبة للعامل — إذا كان اللوغو أو اسم الورشة غير موجود في حسابه، نجلب معلومات مدير الورشة
          if ((logoBase64.isEmpty || resolvedWorkshopName.isEmpty) &&
              workshopId.isNotEmpty &&
              role == 'worker') {
            try {
              final managerDoc = await FirebaseFirestore.instance
                  .collection('users')
                  .doc(workshopId)
                  .get();
              if (managerDoc.exists && managerDoc.data() != null) {
                final mData = managerDoc.data()!;
                if (logoBase64.isEmpty) {
                  logoBase64 =
                      mData['workshopLogoUrl']?.toString() ??
                      mData['logoUrl']?.toString() ??
                      '';
                }
                final mName = mData['workshopName']?.toString() ?? '';
                if (mName.isNotEmpty && mName != workshopId) {
                  resolvedWorkshopName = mName;
                  // تحديث حقل اسم الورشة لدى العامل في الفايربيس لتفادي جلب الكود باسم الورشة
                  FirebaseFirestore.instance
                      .collection('users')
                      .doc(user.uid)
                      .update({'workshopName': resolvedWorkshopName})
                      .catchError((_) {});
                }
              }
            } catch (e) {
              debugPrint(
                'Error fetching manager details for worker logo & name: $e',
              );
            }
          }

          final currentLogo = prefs.getString('workshop_logo_base64');
          if (currentRole != role ||
              currentWorkshop != workshopId ||
              currentWorkshopName != resolvedWorkshopName ||
              currentDisplayName != displayName ||
              currentLogo != logoBase64 ||
              currentPermissionsFingerprint != permissionsFingerprint) {
            await prefs.setString('user_role', role);
            await prefs.setString('workshop_code', workshopId);
            await prefs.setString(
              'permissions_cloud_fingerprint',
              permissionsFingerprint,
            );
            if (resolvedWorkshopName.isNotEmpty) {
              await prefs.setString('workshop_name', resolvedWorkshopName);
            }
            await prefs.setString('user_display_name', displayName);
            if (logoBase64.isNotEmpty) {
              await prefs.setString('workshop_logo_base64', logoBase64);
            }
            if (context.mounted) {
              Provider.of<AppSettingsProvider>(
                context,
                listen: false,
              ).reloadPermissions();
            }
          }
        });

        // 0. التحقق من الإدارة العليا (الأدمن يدخل دائماً)
        if (isAdmin) {
          return const SyncGateway(key: ValueKey('sync_gateway'));
        }

        // 1. التحقق من الحظر الشخصي
        if (data['isBlocked'] == true) {
          return Scaffold(
            backgroundColor: Colors.white,
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.block, color: Colors.red, size: 80),
                    const SizedBox(height: 20),
                    const Text(
                      'تم إيقاف حسابك',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.red,
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'تم منعك من الدخول للتطبيق من قبل مدير الورشة أو الإدارة.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 16),
                    ),
                    const SizedBox(height: 30),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () async {
                        try {
                          await FirebaseAuth.instance.signOut();
                          await GoogleSignIn().signOut();
                          await SqlDatabase.clearAllLocalData();
                        } catch (e) {
                          debugPrint('Sign out error: $e');
                        }
                      },
                      child: const Text('تسجيل الخروج'),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        // -------------------------------------------------------------
        // 2. معالجة حالة العامل (ربط العامل باشتراك المدير لغلق الثغرة)
        // -------------------------------------------------------------
        if (data['role'] == 'worker' || data['role'] == 'co_manager') {
          final managerId = data['workshopId']?.toString();

          if (managerId == null || managerId.isEmpty) {
            return const Scaffold(
              body: Center(
                child: Text('خطأ: لم يتم العثور على بيانات الورشة.'),
              ),
            );
          }

          // نستمع لحظياً لبيانات المدير صاحب الورشة
          return StreamBuilder<DocumentSnapshot>(
            stream: FirebaseFirestore.instance
                .collection('users')
                .doc(managerId)
                .snapshots(),
            builder: (context, managerSnap) {
              if (managerSnap.connectionState == ConnectionState.waiting &&
                  !managerSnap.hasData) {
                return const Scaffold(
                  backgroundColor: Colors.white,
                  body: Center(child: CircularProgressIndicator()),
                );
              }
              if (!managerSnap.hasData) {
                return const Scaffold(
                  backgroundColor: Colors.white,
                  body: Center(child: CircularProgressIndicator()),
                );
              }

              if (!managerSnap.data!.exists) {
                return Scaffold(
                  backgroundColor: Colors.white,
                  body: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.error_outline,
                            color: Colors.red,
                            size: 80,
                          ),
                          const SizedBox(height: 24),
                          const Text(
                            'خطأ في بيانات الورشة',
                            style: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Colors.red,
                            ),
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'عذراً، لم يتم العثور على بيانات الورشة التابع لها هذا العامل في النظام.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 16,
                              color: Colors.black54,
                            ),
                          ),
                          const SizedBox(height: 32),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24,
                                vertical: 12,
                              ),
                            ),
                            onPressed: () async {
                              try {
                                await FirebaseAuth.instance.signOut();
                                await GoogleSignIn().signOut();
                                await SqlDatabase.clearAllLocalData();
                              } catch (e) {
                                debugPrint('Sign out error: $e');
                              }
                            },
                            icon: const Icon(Icons.logout),
                            label: const Text(
                              'تسجيل الخروج والعودة',
                              style: TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 16,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }

              final managerData =
                  managerSnap.data!.data() as Map<String, dynamic>;

              final isManagerSubscribed = _hasActiveSubscription(managerData);

              if (isManagerSubscribed) {
                final wName = managerData['workshopName']?.toString() ?? '';
                WidgetsBinding.instance.addPostFrameCallback((_) async {
                  final prefs = await SharedPreferences.getInstance();
                  final currentWorkshopName = prefs.getString('workshop_name');
                  if (currentWorkshopName != wName) {
                    await prefs.setString('workshop_name', wName);
                  }
                });
                return const SyncGateway(
                  key: ValueKey('sync_gateway'),
                ); // المدير مشترك = العامل يدخل
              } else {
                // واجهة مخصصة للعامل تخبره بأن المشكلة من اشتراك مديره
                return Scaffold(
                  backgroundColor: Colors.white,
                  body: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(20.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.timer_off,
                            color: Colors.orange,
                            size: 80,
                          ),
                          const SizedBox(height: 20),
                          const Text(
                            'انتهى اشتراك الورشة',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: Colors.orange,
                            ),
                          ),
                          const SizedBox(height: 10),
                          const Text(
                            'نعتذر، لا يمكنك الدخول لأن اشتراك مدير الورشة قد انتهى.\nيرجى التواصل مع المدير لتجديد الاشتراك.',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 16),
                          ),
                          const SizedBox(height: 30),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.orange,
                              foregroundColor: Colors.white,
                            ),
                            onPressed: () async {
                              try {
                                await FirebaseAuth.instance.signOut();
                                await GoogleSignIn().signOut();
                                await SqlDatabase.clearAllLocalData();
                              } catch (e) {
                                debugPrint('Sign out error: $e');
                              }
                            },
                            child: const Text('تسجيل الخروج'),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }
            },
          );
        }

        // -------------------------------------------------------------
        // 3. معالجة حالة المدير (يفحص اشتراكه الشخصي)
        // -------------------------------------------------------------
        if (_hasActiveSubscription(data)) {
          return const SyncGateway(key: ValueKey('sync_gateway'));
        }

        return const SubscriptionExpiredScreen();
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SyncGateway: بوابّة المزامنة للتأكد من تعبئة البيانات الفارغة عند الإقلاع
// ─────────────────────────────────────────────────────────────────────────────
class SyncGateway extends StatefulWidget {
  const SyncGateway({super.key});

  @override
  State<SyncGateway> createState() => _SyncGatewayState();
}

class _SyncGatewayState extends State<SyncGateway> {
  bool _isSyncing = false;
  String? _syncError;
  String _syncStatus = 'جاري فحص قاعدة البيانات المحلية...';

  @override
  void initState() {
    super.initState();
    _checkAndSync();
  }

  Future<void> _checkAndSync() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final currentUid = FirebaseAuth.instance.currentUser?.uid ?? '';
      final activeUid = prefs.getString('active_cloud_user_uid') ?? '';
      final activeWorkshop = _storedActiveWorkshop(prefs);
      final db = SqlDatabase();
      final myDb = await db.db;
      if (myDb == null) {
        throw StateError('تعذر فتح قاعدة البيانات المحلية.');
      }

      final hasLocalBusinessData = await _hasLocalBusinessData(myDb);
      if (hasLocalBusinessData &&
          currentUid.isNotEmpty &&
          activeUid == currentUid &&
          activeWorkshop.isNotEmpty) {
        _enterApp(startListening: false);
        _syncSameAccountInBackground(db);
        return;
      }
      if (hasLocalBusinessData &&
          currentUid.isNotEmpty &&
          (activeUid.isEmpty || activeUid == currentUid) &&
          activeWorkshop.isEmpty) {
        _enterApp(startListening: false);
        _syncSameAccountInBackground(db);
        return;
      }

      // Resolve the workshop from the signed-in Firebase account before
      // deciding whether local data belongs to this workshop.
      await CloudSyncService().init();
      final clearedDifferentWorkshop = await _clearLocalDataIfWorkshopChanged();
      final effectiveDb = clearedDifferentWorkshop ? SqlDatabase() : db;
      final effectiveMyDb = clearedDifferentWorkshop
          ? await effectiveDb.db
          : myDb;
      if (effectiveMyDb == null) {
        throw StateError('تعذر فتح قاعدة البيانات المحلية.');
      }

      final userRole = prefs.getString('user_role') ?? 'worker';
      final isWorker = userRole == 'worker';

      final hasEffectiveLocalData = await _hasLocalBusinessData(effectiveMyDb);

      if (hasEffectiveLocalData) {
        // ✅ إذا كانت قاعدة البيانات تحتوي على بيانات: الدخول فوراً للتطبيق بدون انتظار!
        _enterApp();
        // تشغيل المزامنة في الخلفية بصمت
        CloudSyncService()
            .fullRecoverySync()
            .timeout(const Duration(seconds: 45), onTimeout: () {})
            .catchError((_) {});
        CloudSyncService()
            .loadAndApplyWorkshopSystems()
            .timeout(const Duration(seconds: 20), onTimeout: () {})
            .catchError((_) {});
      } else {
        // ⏳ عند تثبيت جديد قد توجد السلاسل الافتراضية فقط. ننتظر هنا حتى
        // تنتهي استعادة بيانات الورشة، حتى لا تظهر الواجهة فارغة مؤقتاً.
        setState(() {
          _isSyncing = true;
          _syncStatus = isWorker
              ? 'جاري تهيئة بيانات الورشة لأول مرة...'
              : 'جاري مزامنة بيانات الورشة...';
        });
        // A newly installed phone has no business records to protect yet.
        // Download first; attempting an upload before this restore can block
        // the initial import (or publish an empty local snapshot).
        await CloudSyncService().fullRecoverySync(initialRestore: true);
        await CloudSyncService().loadAndApplyWorkshopSystems().timeout(
          const Duration(seconds: 20),
          onTimeout: () {},
        );
        _enterApp();
      }
      effectiveDb.runAutoDailyBackup().catchError((_) {});
      await _rememberActiveWorkshop();
    } catch (e) {
      debugPrint('Sync gateway error: $e');
      if (!mounted) return;
      setState(() {
        _isSyncing = false;
        _syncError =
            'تعذر تنزيل بيانات الورشة. لم يتم إنشاء أو حذف أي بيانات.\n'
            'تحقق من الاتصال ثم اضغط «إعادة المحاولة».\n\n'
            '${CloudSyncService().lastRestoreSummary}';
      });
    }
  }

  Future<bool> _hasLocalBusinessData(dynamic myDb) async {
    // الإعدادات الأساسية (Profile وSeries) تُنشأ محلياً حتى بعد تثبيت
    // التطبيق من جديد، لذلك لا يصح اعتبارها دليلاً على أن بيانات الورشة
    // قد استُعيدت. نعتمد فقط على بيانات العمل الفعلية هنا.
    try {
      final clients = await myDb.query('Client', limit: 1);
      final orders = await myDb.query('Commandes', limit: 1);
      return clients.isNotEmpty || orders.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  String _storedActiveWorkshop(SharedPreferences prefs) {
    final direct = prefs.getString('active_cloud_workshop_id') ?? '';
    if (direct.isNotEmpty) return direct;
    final legacy = prefs.getString('active_cloud_session_key') ?? '';
    final separator = legacy.indexOf('|');
    if (separator >= 0 && separator < legacy.length - 1) {
      return legacy.substring(separator + 1);
    }
    return '';
  }

  Future<String> _currentWorkshopKey() async {
    final user = FirebaseAuth.instance.currentUser;
    final prefs = await SharedPreferences.getInstance();
    return CloudSyncService().workshopId ??
        prefs.getString('workshop_code') ??
        user?.uid ??
        '';
  }

  Future<bool> _clearLocalDataIfWorkshopChanged() async {
    final prefs = await SharedPreferences.getInstance();
    final previousWorkshop = _storedActiveWorkshop(prefs);
    final currentWorkshop = await _currentWorkshopKey();
    if (previousWorkshop.isEmpty || previousWorkshop == currentWorkshop) {
      return false;
    }

    CloudSyncService().reset();
    await SqlDatabase.clearAllLocalData();
    await CloudSyncService().init();
    return true;
  }

  Future<void> _rememberActiveWorkshop() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'active_cloud_workshop_id',
      await _currentWorkshopKey(),
    );
    await prefs.setString(
      'active_cloud_user_uid',
      FirebaseAuth.instance.currentUser?.uid ?? '',
    );
  }

  void _syncSameAccountInBackground(SqlDatabase db) {
    () async {
      try {
        await CloudSyncService().init();
        if (!mounted) return;
        CloudSyncService().startListeningForUpdates(() {});
        await _rememberActiveWorkshop();
        CloudSyncService()
            .fullRecoverySync()
            .timeout(const Duration(seconds: 45), onTimeout: () {})
            .catchError((_) {});
        CloudSyncService()
            .loadAndApplyWorkshopSystems()
            .timeout(const Duration(seconds: 20), onTimeout: () {})
            .catchError((_) {});
        db.runAutoDailyBackup().catchError((_) {});
      } catch (error) {
        debugPrint('Background same-account sync error: $error');
      }
    }();
  }

  void _enterApp({bool startListening = true}) {
    if (mounted) {
      setState(() {
        _isSyncing = false;
      });
      // بدء المزامنة التلقائية الصامتة في الخلفية
      if (startListening) {
        CloudSyncService().startListeningForUpdates(() {});
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_syncError != null) {
      return Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.cloud_off_rounded,
                    color: Colors.orange,
                    size: 64,
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'لم تُسترجع بيانات الورشة بعد',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontWeight: FontWeight.bold,
                      fontSize: 20,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _syncError!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontFamily: 'Cairo', height: 1.6),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    onPressed: () {
                      setState(() {
                        _syncError = null;
                        _isSyncing = true;
                        _syncStatus = 'جاري إعادة تنزيل بيانات الورشة...';
                      });
                      _checkAndSync();
                    },
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text(
                      'إعادة المحاولة',
                      style: TextStyle(fontFamily: 'Cairo'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }
    if (_isSyncing) {
      return Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.cloud_sync_rounded,
                  color: Colors.blue,
                  size: 80,
                ),
                const SizedBox(height: 24),
                const CircularProgressIndicator(),
                const SizedBox(height: 24),
                Text(
                  _syncStatus,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Cairo',
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'يرجى الانتظار قليلاً لحين إعداد كتالوج الورشة والطلبيات.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey,
                    fontFamily: 'Cairo',
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return const AppWorkspaceShell();
  }
}
