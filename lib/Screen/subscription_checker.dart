import 'dart:convert';
import 'package:database_data/services/auth_service.dart';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'subscription_expired_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../settings/app_settings.dart';
import '../settings/localization.dart';
import 'app_workspace_shell.dart';
import 'package:database_data/sql_database.dart';
import 'package:database_data/services/cloud_sync_service.dart';
import 'package:database_data/services/supabase_workshop_sync_service.dart';
import 'package:database_data/services/supabase_account_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:async';
import '../widgets/subscription_deadline.dart';

class SubscriptionChecker extends StatefulWidget {
  const SubscriptionChecker({super.key});

  @override
  State<SubscriptionChecker> createState() => _SubscriptionCheckerState();
}

class _SubscriptionCheckerState extends State<SubscriptionChecker> {
  String _t(String key) => Localization.translate(
    key,
    Provider.of<AppSettingsProvider>(context, listen: false).language,
  );

  DateTime? _cloudDate(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value == null) return null;
    return DateTime.tryParse(value.toString());
  }

  bool _hasActiveSubscription(Map<String, dynamic> data) {
    final status = data['subscriptionStatus']?.toString().toLowerCase().trim();
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

    // An explicit active status without an expiry is the permanent plan used
    // by the administrator. An active status with an expiry was handled
    // above and must stop working as soon as that date is reached.
    if (status == 'active') return true;
    // Missing subscription data must not silently grant access. The account
    // needs an explicit activation or a future end date.
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final user = AppAuthService().currentUser;
    if (user == null) {
      return Scaffold(
        body: Center(child: Text(_t('عذراً، يجب تسجيل الدخول.'))),
      );
    }

    // Supabase is the only active gate. The legacy Firestore branch below is
    // intentionally retained as a rollback reference, but is unreachable in
    // the production path.
    return const SupabaseSubscriptionGate();

    // ignore: dead_code
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
              child: Text(
                '${_t('حدث خطأ أثناء فحص الاشتراك:')} ${snapshot.error}',
              ),
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
                          context
                              .read<WorkspaceController>()
                              .resetForSignedOut();
                          await AppAuthService().signOut();
                          await AppAuthService().signOutGoogleSession();
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
          final currentDisplayName = prefs.getString('user_display_name');
          final currentPermissionsFingerprint =
              prefs.getString('permissions_cloud_fingerprint') ?? '';

          // Permission changes do not necessarily change a worker's role or
          // workshop. Keep an explicit fingerprint so the computer reloads
          // permissions for every manager-side switch change.
          // Firestore's Map is authoritative when present. The JSON field is
          // retained for old documents only and may lag behind the Map.
          final permissionsFingerprint = data['permissions'] is Map
              ? jsonEncode(data['permissions'])
              : data['permissions_json'] is String
              ? data['permissions_json'] as String
              : '';

          // The workshop profile is supplied by Supabase. Firebase is used
          // here only for account role, membership and subscription checks.
          if (currentRole != role ||
              currentWorkshop != workshopId ||
              currentDisplayName != displayName ||
              currentPermissionsFingerprint != permissionsFingerprint) {
            await prefs.setString('user_role', role);
            await prefs.setString('workshop_code', workshopId);
            await prefs.setString(
              'permissions_cloud_fingerprint',
              permissionsFingerprint,
            );
            // Workshop name/logo are supplied by Supabase workshop profile
            // sync, never copied from a Firebase user document.
            await prefs.setString('user_display_name', displayName);
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
          return SyncGateway(
            key: const ValueKey('sync_gateway'),
            initialWorkshopId: workshopId.isNotEmpty ? workshopId : user.uid,
            initialWorkshopName: '',
            initialUserRole: role,
          );
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
                          context
                              .read<WorkspaceController>()
                              .resetForSignedOut();
                          await AppAuthService().signOut();
                          await AppAuthService().signOutGoogleSession();
                          await SqlDatabase.clearAllLocalData();
                        } catch (e) {
                          debugPrint('Sign out error: $e');
                        }
                      },
                      child: Text(_t('تسجيل الخروج')),
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
            return Scaffold(
              body: Center(
                child: Text(_t('خطأ: لم يتم العثور على بيانات الورشة.')),
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
                                context
                                    .read<WorkspaceController>()
                                    .resetForSignedOut();
                                await AppAuthService().signOut();
                                await AppAuthService().signOutGoogleSession();
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
                return SyncGateway(
                  key: const ValueKey('sync_gateway'),
                  initialWorkshopId: managerId,
                  initialWorkshopName: '',
                  initialUserRole: role,
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
                                await AppAuthService().signOut();
                                await AppAuthService().signOutGoogleSession();
                                await SqlDatabase.clearAllLocalData();
                              } catch (e) {
                                debugPrint('Sign out error: $e');
                              }
                            },
                            child: Text(_t('تسجيل الخروج')),
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
          return SyncGateway(
            key: const ValueKey('sync_gateway'),
            initialWorkshopId: workshopId.isNotEmpty ? workshopId : user.uid,
            initialWorkshopName: '',
            initialUserRole: role,
          );
        }

        return const SubscriptionExpiredScreen();
      },
    );
  }
}

class SupabaseSubscriptionGate extends StatefulWidget {
  const SupabaseSubscriptionGate({super.key});

  @override
  State<SupabaseSubscriptionGate> createState() =>
      _SupabaseSubscriptionGateState();
}

class _SupabaseSubscriptionGateState extends State<SupabaseSubscriptionGate> {
  static const _accountCachePrefix = 'supabase_account_cache_v1_';
  Timer? _expiryTimer;
  Timer? _subscriptionCheckTimer;
  RealtimeChannel? _subscriptionChannel;
  String? _subscriptionWorkshopId;
  late Future<SupabaseAccountSnapshot?> _accountFuture;

  @override
  void initState() {
    super.initState();
    _accountFuture = _loadCachedAccountFirst();
    unawaited(_refreshAccountInBackground());
    _subscriptionCheckTimer = Timer.periodic(const Duration(hours: 24), (_) {
      if (mounted) unawaited(_refreshAccountInBackground());
    });
  }

  String? get _currentUserId => AppAuthService().currentUser?.uid;

  Future<SupabaseAccountSnapshot?> _loadCachedAccountFirst() async {
    final userId = _currentUserId;
    if (userId == null || userId.isEmpty) return null;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('');
      if (raw != null && raw.isNotEmpty) {
        final map = jsonDecode(raw);
        if (map is Map && map['userId']?.toString() == userId) {
          return _accountFromMap(Map<String, dynamic>.from(map));
        }
      }

      // Offline fallback: allow local access if the workshop code is cached
      final workshopCode = prefs.getString('workshop_code') ?? '';
      final role = prefs.getString('user_role') ?? 'worker';
      final workshopName = prefs.getString('workshop_name') ?? '';
      if (workshopCode.isNotEmpty) {
        return SupabaseAccountSnapshot(
          userId: userId,
          email: AppAuthService().currentUser?.email ?? '',
          role: role,
          workshopId:
              prefs.getString('cached_workshop_uuid') ??
              prefs.getString('selected_supabase_workshop_id') ??
              workshopCode,
          workshopCode: workshopCode,
          workshopName: workshopName,
          permissions: const <String, dynamic>{},
          blocked: false,
          subscription: const <String, dynamic>{'status': 'active'},
        );
      }
    } catch (error) {
      debugPrint('Cached Supabase account could not be read: ');
    }
    try {
      final account = await SupabaseAccountService().loadCurrentAccount();
      if (account != null) await _cacheAccount(account);
      return account;
    } catch (e) {
      debugPrint('SupabaseAccountService loadCurrentAccount offline error: ');
      return null;
    }
  }

  SupabaseAccountSnapshot _accountFromMap(Map<String, dynamic> map) {
    Map<String, dynamic> objectMap(dynamic value) =>
        value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};
    return SupabaseAccountSnapshot(
      userId: map['userId']?.toString() ?? '',
      email: map['email']?.toString() ?? '',
      role: map['role']?.toString() ?? 'worker',
      workshopId: map['workshopId']?.toString() ?? '',
      workshopCode: map['workshopCode']?.toString() ?? '',
      workshopName: map['workshopName']?.toString() ?? '',
      permissions: objectMap(map['permissions']),
      blocked: map['blocked'] == true,
      subscription: objectMap(map['subscription']),
    );
  }

  Future<void> _cacheAccount(SupabaseAccountSnapshot account) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      '$_accountCachePrefix${account.userId}',
      jsonEncode({
        'userId': account.userId,
        'email': account.email,
        'role': account.role,
        'workshopId': account.workshopId,
        'workshopCode': account.workshopCode,
        'workshopName': account.workshopName,
        'permissions': account.permissions,
        'blocked': account.blocked,
        'subscription': account.subscription,
      }),
    );
  }

  Future<void> _refreshAccountInBackground() async {
    try {
      final account = await SupabaseAccountService().loadCurrentAccount();
      if (!mounted) return;
      if (account != null) await _cacheAccount(account);
      if (!mounted) return;
      setState(() => _accountFuture = Future.value(account));
      if (account != null) _scheduleSubscriptionExpiry(account);
      await _bindSubscriptionRealtime();
    } catch (error) {
      // The cached account keeps the local app usable while offline. A later
      // periodic or realtime refresh will apply the server state.
      debugPrint('Background Supabase account refresh skipped: $error');
      unawaited(_bindSubscriptionRealtime());
    }
  }

  @override
  void dispose() {
    _expiryTimer?.cancel();
    _subscriptionCheckTimer?.cancel();
    final channel = _subscriptionChannel;
    if (channel != null) {
      unawaited(Supabase.instance.client.removeChannel(channel));
    }
    super.dispose();
  }

  Future<void> _bindSubscriptionRealtime() async {
    try {
      final account = await _accountFuture;
      if (!mounted || account == null || account.workshopId.trim().isEmpty) {
        return;
      }
      _scheduleSubscriptionExpiry(account);
      final workshopId = account.workshopId.trim();
      if (_subscriptionWorkshopId == workshopId &&
          _subscriptionChannel != null) {
        return;
      }
      final oldChannel = _subscriptionChannel;
      if (oldChannel != null) {
        await Supabase.instance.client.removeChannel(oldChannel);
      }
      _subscriptionWorkshopId = workshopId;
      _subscriptionChannel = Supabase.instance.client
          .channel('subscription_gate_$workshopId')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'workshop_subscriptions',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'workshop_id',
              value: workshopId,
            ),
            callback: (_) {
              if (!mounted) return;
              unawaited(
                _refreshAccountInBackground().catchError((e) {
                  debugPrint('Realtime subscription refresh skipped: $e');
                }),
              );
            },
          )
          .subscribe((status, [error]) {
            if (error != null) {
              debugPrint(
                'Subscription realtime status: $status, error: $error',
              );
            }
          });
    } catch (error) {
      debugPrint('Subscription realtime setup skipped: $error');
    }
  }

  void _scheduleSubscriptionExpiry(SupabaseAccountSnapshot account) {
    _expiryTimer?.cancel();
    final raw = account.subscription['ends_at']?.toString().trim() ?? '';
    if (raw.isEmpty || raw == 'null') return;
    final endsAt = DateTime.tryParse(raw)?.toLocal();
    if (endsAt == null) return;
    final delay = endsAt.difference(DateTime.now());
    _expiryTimer = Timer(
      delay.isNegative || delay == Duration.zero ? Duration.zero : delay,
      _reloadAccountSilently,
    );
  }

  void _reloadAccountSilently() {
    if (!mounted) return;
    unawaited(_refreshAccountInBackground());
  }

  String _t(BuildContext context, String key) =>
      Localization.translate(key, context.read<AppSettingsProvider>().language);

  bool _isActive(SupabaseAccountSnapshot account) {
    if (account.role == 'admin') return true;
    final status = account.subscription['status']
        ?.toString()
        .toLowerCase()
        .trim();
    if (status == 'expired' ||
        status == 'blocked' ||
        status == 'cancelled' ||
        status == 'canceled') {
      return false;
    }
    final rawEndsAt = account.subscription['ends_at']?.toString();
    final endsAt = rawEndsAt == null ? null : DateTime.tryParse(rawEndsAt);
    if (endsAt != null) return DateTime.now().toUtc().isBefore(endsAt.toUtc());
    return status == 'active';
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<SupabaseAccountSnapshot?>(
      future: _accountFuture,
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
            backgroundColor: Colors.white,
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'تعذر تحميل بيانات الحساب من Supabase:\n${snapshot.error}',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          );
        }

        final account = snapshot.data;
        if (account == null) {
          return _message(
            context,
            icon: Icons.error_outline,
            color: Colors.red,
            title: _t(context, 'الحساب غير مرتبط بورشة'),
            body: _t(
              context,
              'أكمل التسجيل أو اطلب من مدير الورشة إرسال دعوة قبل الدخول.',
            ),
          );
        }
        if (account.blocked) {
          return _message(
            context,
            icon: Icons.block,
            color: Colors.red,
            title: _t(context, 'تم إيقاف حسابك'),
            body: _t(
              context,
              'تم منعك من الدخول إلى هذه الورشة من قبل المدير.',
            ),
          );
        }

        WidgetsBinding.instance.addPostFrameCallback((_) async {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('workshop_code', account.workshopCode);
          final accountName = account.workshopName.trim();
          final accountCode = account.workshopCode.trim();
          if (accountName.isNotEmpty && accountName != accountCode) {
            await prefs.setString('workshop_name', accountName);
          } else if ((prefs.getString('workshop_name') ?? '').trim() ==
              accountCode) {
            await prefs.remove('workshop_name');
          }
          await prefs.setString('user_role', account.role);
          await prefs.setString(
            'permissions_json',
            jsonEncode(account.permissions),
          );
          if (context.mounted) {
            await Provider.of<AppSettingsProvider>(
              context,
              listen: false,
            ).reloadPermissions();
          }
        });

        if (_isActive(account)) {
          return SubscriptionDeadline(
            endsAt: account.role == 'admin'
                ? null
                : DateTime.tryParse(
                    account.subscription['ends_at']?.toString() ?? '',
                  ),
            expired: const SubscriptionExpiredScreen(),
            child: SyncGateway(
              // A global administrator can open several workshops with the same
              // user account. Recreate the gateway when the selected workshop
              // changes; keying it by the user alone would keep the previous
              // workshop's local database and synchronization state alive.
              key: ValueKey(
                'supabase_sync_gateway:${account.userId}:${account.workshopId}',
              ),
              initialWorkshopId: account.workshopCode,
              initialWorkshopName: account.workshopName,
              initialUserRole: account.role,
            ),
          );
        }
        return const SubscriptionExpiredScreen();
      },
    );
  }

  Widget _message(
    BuildContext context, {
    required IconData icon,
    required Color color,
    required String title,
    required String body,
  }) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color, size: 72),
              const SizedBox(height: 20),
              Text(title, style: TextStyle(color: color, fontSize: 22)),
              const SizedBox(height: 12),
              Text(body, textAlign: TextAlign.center),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: () async {
                  context.read<WorkspaceController>().resetForSignedOut();
                  await CloudSyncService().clearCachedWorkshopContext();
                  await AppAuthService().signOut();
                  await SqlDatabase.clearAllLocalData();
                },
                icon: const Icon(Icons.logout),
                label: Text(_t(context, 'تسجيل الخروج')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SyncGateway: بوابّة المزامنة للتأكد من تعبئة البيانات الفارغة عند الإقلاع
// ─────────────────────────────────────────────────────────────────────────────
class SyncGateway extends StatefulWidget {
  const SyncGateway({
    super.key,
    this.initialWorkshopId,
    this.initialWorkshopName,
    this.initialUserRole,
  });

  final String? initialWorkshopId;
  final String? initialWorkshopName;
  final String? initialUserRole;

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
      await _primeCloudIdentity(prefs);
      // Start Supabase only after the workshop code has been primed. Starting
      // it earlier from the login screen could bind the desktop to the
      // account uid before the real workshop identity was known.
      SupabaseWorkshopSyncService().start();
      final currentUid = AppAuthService().currentUser?.uid ?? '';
      final activeUid = prefs.getString('active_cloud_user_uid') ?? '';
      final activeWorkshop = _storedActiveWorkshop(prefs);
      final requestedWorkshop =
          (widget.initialWorkshopId?.trim().isNotEmpty ?? false)
          ? widget.initialWorkshopId!.trim()
          : (prefs.getString('workshop_code') ?? '').trim();
      final db = SqlDatabase();
      final myDb = await db.db;
      if (myDb == null) {
        throw StateError('تعذر فتح قاعدة البيانات المحلية.');
      }

      final hasLocalBusinessData = await _hasLocalBusinessData(myDb);
      final sameUser =
          currentUid.isNotEmpty &&
          (activeUid.isEmpty || activeUid == currentUid);
      final sameWorkshop =
          activeWorkshop.isEmpty ||
          requestedWorkshop.isEmpty ||
          activeWorkshop.trim().toLowerCase() ==
              requestedWorkshop.trim().toLowerCase();

      if (hasLocalBusinessData && sameUser && sameWorkshop) {
        await _preparePermissionsBeforeEnter();
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

      final hasEffectiveLocalData = await _hasLocalBusinessData(effectiveMyDb);

      // Resolve permissions before creating the page tree. The business-data
      // restore remains in the background, but every page starts with the
      // correct role and no permission-related rebuild/flash is needed.
      await _preparePermissionsBeforeEnter();
      _enterApp();
      effectiveDb.runAutoDailyBackup().catchError((_) {});
      await _rememberActiveWorkshop();
      _startBackgroundWorkshopSync(hasLocalData: hasEffectiveLocalData);
    } catch (e) {
      debugPrint('Sync gateway error: $e');
      if (!mounted) return;
      // A cloud outage must not lock the worker out of the local app. Keep
      // the dashboard usable and let the realtime/background retry recover
      // the workshop data when connectivity or membership becomes available.
      _enterApp();
    }
  }

  void _startBackgroundWorkshopSync({required bool hasLocalData}) {
    () async {
      try {
        final supabase = SupabaseWorkshopSyncService();
        // The restore is deliberately silent. Do not call setState from a
        // realtime callback: SyncGateway remains mounted while it hosts the
        // dashboard, so that would repaint the whole app on every row change.
        await supabase.ensureStarted(timeout: const Duration(seconds: 20));
        await _refreshPermissionsInBackground();
        await CloudSyncService().init();
        CloudSyncService().startListeningForUpdates(() {});

        if (!hasLocalData) {
          // التنزيل الكامل من الصفر يُطلب فقط إذا كانت قاعدة البيانات فارغة تماماً
          await CloudSyncService()
              .fullRecoverySync(initialRestore: false)
              .timeout(const Duration(seconds: 90), onTimeout: () {});
        } else {
          // إذا كانت البيانات موجودة، يتم تحديث التغييرات الجديدة فقط بخفة وسرعة
          await CloudSyncService()
              .refreshFromCloudIfChanged()
              .timeout(const Duration(seconds: 30), onTimeout: () {})
              .catchError((_) {});
        }
        await CloudSyncService().loadAndApplyWorkshopSystems().timeout(
          const Duration(seconds: 30),
          onTimeout: () {},
        );
        await _refreshPermissionsInBackground();
      } catch (error) {
        debugPrint(
          'Background workshop sync skipped '
          '(local data: $hasLocalData): $error',
        );
      }
    }();
  }

  Future<void> _preparePermissionsBeforeEnter() async {
    try {
      await SupabaseWorkshopSyncService().ensureStarted(
        timeout: const Duration(seconds: 20),
      );
      await Provider.of<AppSettingsProvider>(
        context,
        listen: false,
      ).reloadPermissions();
      await CloudSyncService().loadAndApplyWorkshopSystems().timeout(
        const Duration(seconds: 4),
        onTimeout: () {},
      );
    } catch (error) {
      // Login must remain usable during a temporary cloud failure; the
      // background listener will retry without rebuilding the page tree.
      debugPrint('Initial permission load skipped: $error');
    }
  }

  Future<void> _primeCloudIdentity(SharedPreferences prefs) async {
    final workshopId = widget.initialWorkshopId?.trim() ?? '';
    final workshopName = widget.initialWorkshopName?.trim() ?? '';
    final userRole = widget.initialUserRole?.trim() ?? '';
    final user = AppAuthService().currentUser;
    final displayName = user?.displayName?.trim() ?? '';
    final email = user?.email?.trim() ?? '';
    final accountName = displayName.isNotEmpty
        ? displayName
        : (email.contains('@') ? email.split('@').first.trim() : email);

    // Keep the account person's name independent from the workshop identity.
    // This is used by the local database for "Entered by" and "Modified by".
    if (accountName.isNotEmpty) {
      await prefs.setString('user_display_name', accountName);
    }

    if (workshopId.isNotEmpty) {
      await prefs.setString('workshop_code', workshopId);
    }
    // The workshop id/code is an internal identifier. It must never be
    // copied into workshop_name, because that value is printed on documents.
    if (workshopName.isNotEmpty &&
        (workshopId.isEmpty || workshopName != workshopId)) {
      await prefs.setString('workshop_name', workshopName);
    } else if (workshopId.isNotEmpty && workshopName == workshopId) {
      final savedName = (prefs.getString('workshop_name') ?? '').trim();
      if (savedName == workshopId) {
        await prefs.remove('workshop_name');
      }
    }
    if (userRole.isNotEmpty) {
      await prefs.setString('user_role', userRole);
    }
  }

  Future<bool> _hasLocalBusinessData(dynamic myDb) async {
    // الإعدادات الأساسية (Profile وSeries) تُنشأ محلياً حتى بعد تثبيت
    // التطبيق من جديد، لذلك لا يصح اعتبارها دليلاً على أن بيانات الورشة
    // قد استُعيدت. نعتمد فقط على بيانات العمل الفعلية هنا.
    try {
      final clients = await myDb.query('Client', limit: 1);
      final orders = await myDb.query('Commandes', limit: 1);
      if (clients.isNotEmpty || orders.isNotEmpty) return true;
      // A workshop can have its catalogue ready before its first customer.
      // Profile/Series defaults alone are not evidence of a restored cache.
      final sections = await myDb.query('Sections', limit: 1);
      return sections.isNotEmpty;
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
    final user = AppAuthService().currentUser;
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
      AppAuthService().currentUser?.uid ?? '',
    );
  }

  void _syncSameAccountInBackground(SqlDatabase db) {
    () async {
      try {
        await CloudSyncService().init();
        if (!mounted) return;
        CloudSyncService().startListeningForUpdates(() {});
        await _rememberActiveWorkshop();
        await SupabaseWorkshopSyncService().ensureStarted(
          timeout: const Duration(seconds: 20),
        );
        await _refreshPermissionsInBackground();
        // Keep the system-selection application behind the protected restore.
        // Running both futures at once allowed the dashboard to read the old
        // active-profile flags while the workshop snapshot was still being
        // imported.
        // A normal restart uses the saved database and incremental updates.
        // Full recovery is reserved for first setup and explicit recovery.
        await CloudSyncService()
            .refreshFromCloudIfChanged()
            .timeout(const Duration(seconds: 90), onTimeout: () {})
            .catchError((_) {});
        await CloudSyncService()
            .loadAndApplyWorkshopSystems()
            .timeout(const Duration(seconds: 30), onTimeout: () {})
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

  Future<void> _refreshPermissionsInBackground() async {
    if (!mounted) return;
    try {
      await Provider.of<AppSettingsProvider>(
        context,
        listen: false,
      ).reloadPermissions();
    } catch (error) {
      debugPrint('Background permission refresh skipped: $error');
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
