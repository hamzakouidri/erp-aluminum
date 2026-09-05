import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import '../settings/app_settings.dart';
import '../settings/localization.dart';
import '../services/subscription_service.dart';
import 'package:database_data/services/auth_service.dart';
import 'package:database_data/services/supabase_account_service.dart';
import 'package:database_data/services/cloud_sync_service.dart';
import 'package:database_data/services/supabase_workshop_sync_service.dart';

class AdminUsersScreen extends StatefulWidget {
  const AdminUsersScreen({super.key});

  @override
  State<AdminUsersScreen> createState() => _AdminUsersScreenState();
}

class _AdminUsersScreenState extends State<AdminUsersScreen>
    with SingleTickerProviderStateMixin {
  static const List<int?> _subscriptionDurations = <int?>[
    // Test-only values: negative numbers represent minutes, keeping the
    // production day-based values and database format unchanged.
    -1,
    -2,
    -4,
    1,
    2,
    3,
    7,
    30,
    60,
    180,
    365,
  ];

  static const List<int> _allowedWorkerCounts = <int>[1, 2, 3, 4, 5, 10];

  late TabController _tabController;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _baridiMobRipController = TextEditingController();
  bool _isSavingPaymentSettings = false;

  String _t(String key) => Localization.translate(
    key,
    Provider.of<AppSettingsProvider>(context, listen: false).language,
  );

  String _tf(String key, Map<String, Object> values) {
    var result = _t(key);
    values.forEach((name, value) {
      result = result.replaceAll('{$name}', value.toString());
    });
    return result;
  }

  String _subscriptionDurationLabel(int? days) {
    switch (days) {
      case -1:
        return _t('اختبار: دقيقة واحدة');
      case -2:
        return _t('اختبار: دقيقتان');
      case -4:
        return _t('اختبار: 4 دقائق');
      case 1:
        return _t('يوم واحد');
      case 2:
        return _t('يومان');
      case 3:
        return _t('3 أيام');
      case 7:
        return _t('أسبوع');
      case 30:
        return _t('شهر');
      case 60:
        return _t('شهران');
      case 180:
        return _t('6 أشهر');
      case 365:
        return _t('سنة');
      default:
        return _t('اشتراك دائم');
    }
  }

  Duration? _subscriptionDuration(int? value) => value == null
      ? null
      : value < 0
      ? Duration(minutes: -value)
      : Duration(days: value);

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    if (isApplicationAdminEmail(AppAuthService().currentUser?.email)) {
      _loadPaymentSettings();
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    _baridiMobRipController.dispose();
    super.dispose();
  }

  Future<void> _loadPaymentSettings() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection(SubscriptionPaymentSettings.collectionName)
          .doc(SubscriptionPaymentSettings.documentName)
          .get();
      if (!mounted) return;
      _baridiMobRipController.text =
          snapshot.data()?['baridiMobRip']?.toString() ?? '';
    } catch (error) {
      debugPrint('Could not load subscription payment settings: $error');
    }
  }

  Future<void> _savePaymentSettings() async {
    if (!isApplicationAdminEmail(AppAuthService().currentUser?.email)) {
      return;
    }
    final rip = _baridiMobRipController.text.trim();
    if (rip.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_t('أدخل رقم CCP/RIP أولاً.'))));
      return;
    }
    setState(() => _isSavingPaymentSettings = true);
    try {
      await SubscriptionPaymentSettings().saveBaridiMobRip(rip);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_t('تم حفظ رقم CCP/RIP. سيظهر للمستخدمين مباشرة.')),
          backgroundColor: Colors.green,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${_t('تعذر حفظ رقم CCP/RIP:')} $error')),
      );
    } finally {
      if (mounted) setState(() => _isSavingPaymentSettings = false);
    }
  }

  Widget _buildPaymentSettingsCard() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
      child: Card(
        elevation: 1,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                _t('بيانات دفع الاشتراك'),
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text(
                _t(
                  'ضع رقم الحساب البريدي الجاري الذي سيدفع إليه المشتركون. سيظهر لهم في مراجعة الاشتراك.',
                ),
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _baridiMobRipController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: _t('رقم CCP / RIP لـ BaridiMob'),
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.account_balance_rounded),
                ),
              ),
              const SizedBox(height: 10),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: FilledButton.icon(
                  onPressed: _isSavingPaymentSettings
                      ? null
                      : _savePaymentSettings,
                  icon: _isSavingPaymentSettings
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_rounded),
                  label: Text(_t('حفظ رقم الدفع')),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ──────────────── Subscription helpers ────────────────

  /// Returns true if the manager's subscription is currently valid.
  bool _isActive(Map<String, dynamic> data) {
    final status = data['subscriptionStatus']?.toString().toLowerCase().trim();
    if (status == 'expired' ||
        status == 'blocked' ||
        status == 'cancelled' ||
        status == 'canceled') {
      return false;
    }
    final trialStr =
        (data['trialEndDate'] ??
                data['subscriptionEndDate'] ??
                data['subscriptionExpiresAt'] ??
                data['expiresAt'])
            ?.toString();
    if (trialStr != null) {
      try {
        final end = DateTime.parse(trialStr);
        return DateTime.now().isBefore(end);
      } catch (_) {}
    }
    if (status == 'active') return true;
    // Old accounts with no fields at all — treat as needing activation
    return false;
  }

  /// Human-readable status string + colour
  (String, Color) _statusInfo(Map<String, dynamic> data) {
    final status = data['subscriptionStatus']?.toString().toLowerCase().trim();
    final trialStr =
        (data['trialEndDate'] ??
                data['subscriptionEndDate'] ??
                data['subscriptionExpiresAt'] ??
                data['expiresAt'])
            ?.toString();
    if (trialStr != null) {
      try {
        final end = DateTime.parse(trialStr);
        if (DateTime.now().isBefore(end)) {
          final left = end.difference(DateTime.now()).inDays;
          return (
            _tf('تجريبي – باقي {days} يوم 🟡', {'days': left}),
            Colors.orange,
          );
        } else {
          final expiredAgo = DateTime.now().difference(end).inDays;
          return (
            _tf('منتهي منذ {days} يوم ❌', {'days': expiredAgo}),
            Colors.red,
          );
        }
      } catch (_) {}
    }
    if (status == 'trialing') {
      return (_t('تجريبي منتهٍ (trialing) ❌'), Colors.red);
    }
    if (status == 'expired') return (_t('منتهي الصلاحية ❌'), Colors.red);
    if (status == 'active') return (_t('اشتراك مدفوع ✅'), Colors.green);
    return (_t('غير مفعّل ❌'), Colors.red);
  }

  // ──────────────── Actions ────────────────

  Future<void> _saveSubscriptionSettings(
    BuildContext ctx,
    String uid,
    String email, {
    required int? durationDays,
    int? maxUsers,
    required bool isManager,
  }) async {
    final endsAt = _subscriptionDuration(durationDays) == null
        ? null
        : DateTime.now().add(_subscriptionDuration(durationDays)!);
    final status = durationDays == null ? 'active' : 'trialing';
    final planType = durationDays == null ? 'lifetime' : 'trial';

    try {
      if (AppAuthService().usesSupabase) {
        await SupabaseAccountService().setSubscriptionForOwnerUid(
          ownerUid: uid,
          status: status,
          planType: planType,
          endsAt: endsAt,
          maxUsers: maxUsers,
        );
      } else {
        final userUpdate = <String, dynamic>{
          'subscriptionStatus': durationDays == null ? 'active' : 'trial',
        };
        if (endsAt == null) {
          userUpdate.addAll({
            'trialEndDate': FieldValue.delete(),
            'subscriptionEndDate': FieldValue.delete(),
            'subscriptionExpiresAt': FieldValue.delete(),
            'expiresAt': FieldValue.delete(),
            'subscriptionExpiredDate': FieldValue.delete(),
          });
        } else {
          userUpdate.addAll({
            'trialEndDate': endsAt.toIso8601String(),
            'subscriptionExpiredDate': FieldValue.delete(),
          });
        }
        await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .update(userUpdate);
        if (isManager && maxUsers != null) {
          await FirebaseFirestore.instance.collection('workshops').doc(uid).set(
            {'maxUsers': maxUsers},
            SetOptions(merge: true),
          );
        }
      }

      if (ctx.mounted) {
        final durationText = durationDays == null
            ? _t('اشتراك دائم')
            : durationDays! < 0
            ? _tf('اختبار لمدة {minutes} دقيقة', {'minutes': -durationDays})
            : _tf('لمدة {days} يومًا', {'days': durationDays});
        final usersText = maxUsers == null || maxUsers >= 999
            ? _t('بلا حدود')
            : _tf('{count} مستخدمين', {'count': maxUsers});
        ScaffoldMessenger.of(ctx).showSnackBar(
          SnackBar(
            content: Text(
              _tf('تم حفظ اشتراك {email}: {duration}، الحد {users}', {
                'email': email,
                'duration': durationText,
                'users': usersText,
              }),
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (error) {
      if (ctx.mounted) {
        ScaffoldMessenger.of(
          ctx,
        ).showSnackBar(SnackBar(content: Text('${_t('خطأ:')} $error')));
      }
    }
  }

  Future<void> _revokeSubscription(
    BuildContext ctx,
    String uid,
    String email,
  ) async {
    try {
      if (AppAuthService().usesSupabase) {
        await SupabaseAccountService().setSubscriptionForOwnerUid(
          ownerUid: uid,
          status: 'expired',
          planType: 'trial',
          endsAt: DateTime.now(),
        );
        if (ctx.mounted) {
          ScaffoldMessenger.of(ctx).showSnackBar(
            SnackBar(
              content: Text(_tf('تم سحب اشتراك {email}', {'email': email})),
            ),
          );
        }
        return;
      }
      await FirebaseFirestore.instance.collection('users').doc(uid).update({
        'trialEndDate': FieldValue.delete(),
        'subscriptionStatus': 'expired',
        'subscriptionExpiredDate': DateTime.now().toUtc().toIso8601String(),
      });
      if (mounted && ctx.mounted) {
        ScaffoldMessenger.of(ctx).showSnackBar(
          SnackBar(
            content: Text(_tf('تم سحب اشتراك {email}', {'email': email})),
          ),
        );
      }
    } catch (e) {
      if (ctx.mounted) {
        ScaffoldMessenger.of(
          ctx,
        ).showSnackBar(SnackBar(content: Text('${_t('خطأ:')} $e')));
      }
    }
  }

  Future<void> _updateMaxWorkers(
    BuildContext ctx,
    String workshopId,
    String email,
    int limit,
  ) async {
    try {
      if (AppAuthService().usesSupabase) {
        await SupabaseAccountService().setSubscriptionForOwnerUid(
          ownerUid: workshopId,
          status: 'active',
          planType: 'yearly',
          maxUsers: limit,
        );
        if (ctx.mounted) {
          ScaffoldMessenger.of(ctx).showSnackBar(
            SnackBar(
              content: Text(
                limit == 999
                    ? _tf('فُتح الحد الأقصى لورشة {email}', {'email': email})
                    : _tf('الحد الأقصى = {limit} مستخدمين لورشة {email}', {
                        'limit': limit,
                        'email': email,
                      }),
              ),
              backgroundColor: Colors.teal,
            ),
          );
        }
        return;
      }
      await FirebaseFirestore.instance
          .collection('workshops')
          .doc(workshopId)
          .set({'maxUsers': limit}, SetOptions(merge: true));
      if (mounted && ctx.mounted) {
        ScaffoldMessenger.of(ctx).showSnackBar(
          SnackBar(
            content: Text(
              limit == 999
                  ? _tf('فُتح الحد الأقصى لورشة {email}', {'email': email})
                  : _tf('الحد الأقصى = {limit} مستخدمين لورشة {email}', {
                      'limit': limit,
                      'email': email,
                    }),
            ),
            backgroundColor: Colors.teal,
          ),
        );
      }
    } catch (e) {
      if (ctx.mounted) {
        ScaffoldMessenger.of(
          ctx,
        ).showSnackBar(SnackBar(content: Text('${_t('خطأ:')} $e')));
      }
    }
  }

  Future<void> _updateWorkshopLimit(
    BuildContext ctx,
    String workshopId,
    String email,
    String field,
    int limit,
    String label,
  ) async {
    try {
      if (AppAuthService().usesSupabase) {
        final maxUsers = field == 'maxUsers' ? limit : null;
        final maxSystems = field == 'maxSystems' ? limit : null;
        final maxProfiles = field == 'maxProfiles' ? limit : null;
        await SupabaseAccountService().setSubscriptionForOwnerUid(
          ownerUid: workshopId,
          status: 'active',
          planType: 'yearly',
          maxUsers: maxUsers,
          maxSystems: maxSystems,
          maxProfiles: maxProfiles,
        );
        if (ctx.mounted) {
          ScaffoldMessenger.of(ctx).showSnackBar(
            SnackBar(
              content: Text(
                limit == 999
                    ? _tf('تم إلغاء حد {label} لورشة {email}', {
                        'label': label,
                        'email': email,
                      })
                    : _tf('حد {label} = {limit} لورشة {email}', {
                        'label': label,
                        'limit': limit,
                        'email': email,
                      }),
              ),
              backgroundColor: Colors.teal,
            ),
          );
        }
        return;
      }
      await FirebaseFirestore.instance
          .collection('workshops')
          .doc(workshopId)
          .set({field: limit}, SetOptions(merge: true));
      if (mounted && ctx.mounted) {
        ScaffoldMessenger.of(ctx).showSnackBar(
          SnackBar(
            content: Text(
              limit == 999
                  ? _tf('تم إلغاء حد {label} لورشة {email}', {
                      'label': label,
                      'email': email,
                    })
                  : _tf('حد {label} = {limit} لورشة {email}', {
                      'label': label,
                      'limit': limit,
                      'email': email,
                    }),
            ),
            backgroundColor: Colors.teal,
          ),
        );
      }
    } catch (e) {
      if (mounted && ctx.mounted) {
        ScaffoldMessenger.of(ctx).showSnackBar(
          SnackBar(content: Text('${_t('خطأ في حفظ حد')} $label: $e')),
        );
      }
    }
  }

  Future<void> _deleteWorkshop(
    BuildContext ctx,
    String uid,
    String email,
  ) async {
    final confirm =
        await showDialog<bool>(
          context: ctx,
          builder: (dialogCtx) => AlertDialog(
            title: Text(_t('تأكيد المسح النهائي')),
            content: Text(
              '${_t('مسح ورشة')} $email ${_t('وجميع مستخدميها؟ لا يمكن التراجع.')}',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogCtx, false),
                child: Text(_t('إلغاء')),
              ),
              TextButton(
                onPressed: () => Navigator.pop(dialogCtx, true),
                child: Text(
                  _t('مسح نهائي'),
                  style: TextStyle(color: Colors.red),
                ),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirm) return;
    try {
      final workers = await FirebaseFirestore.instance
          .collection('users')
          .where('workshopId', isEqualTo: uid)
          .get();
      for (var d in workers.docs) {
        await d.reference.delete();
      }
      await FirebaseFirestore.instance.collection('users').doc(uid).delete();
      await FirebaseFirestore.instance
          .collection('workshops')
          .doc(uid)
          .delete();
      if (mounted && ctx.mounted) {
        ScaffoldMessenger.of(ctx).showSnackBar(
          SnackBar(content: Text(_tf('تم مسح ورشة {email}', {'email': email}))),
        );
      }
    } catch (e) {
      if (ctx.mounted) {
        ScaffoldMessenger.of(
          ctx,
        ).showSnackBar(SnackBar(content: Text('${_t('خطأ:')} $e')));
      }
    }
  }

  // ──────────────── Dialogs ────────────────

  void _showSubscriptionSettingsDialog(
    BuildContext ctx,
    String uid,
    String email,
    bool isManager,
  ) {
    int? selectedDays = 30;
    var selectedMaxUsers = 4;
    showDialog(
      context: ctx,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (dialogCtx, setDialogState) => AlertDialog(
          title: Text(_t('إعداد الاشتراك')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  _t('مدة الاشتراك:'),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _subscriptionDurations
                      .map(
                        (days) => ChoiceChip(
                          label: Text(_subscriptionDurationLabel(days)),
                          selected: selectedDays == days,
                          onSelected: (value) {
                            if (value) {
                              setDialogState(() => selectedDays = days);
                            }
                          },
                        ),
                      )
                      .toList(),
                ),
                if (isManager) ...[
                  const SizedBox(height: 16),
                  Text(
                    _t('عدد المستخدمين المسموح به (يشمل المدير):'),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _allowedWorkerCounts
                        .map(
                          (count) => ChoiceChip(
                            label: Text(
                              _tf('{count} مستخدمين', {'count': count}),
                            ),
                            selected: selectedMaxUsers == count,
                            onSelected: (value) {
                              if (value) {
                                setDialogState(() => selectedMaxUsers = count);
                              }
                            },
                          ),
                        )
                        .toList(),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: Text(_t('إلغاء')),
            ),
            FilledButton.icon(
              onPressed: () {
                Navigator.pop(dialogCtx);
                _saveSubscriptionSettings(
                  ctx,
                  uid,
                  email,
                  durationDays: selectedDays,
                  maxUsers: isManager ? selectedMaxUsers : null,
                  isManager: isManager,
                );
              },
              icon: const Icon(Icons.save),
              label: Text(_t('حفظ الاشتراك')),
            ),
          ],
        ),
      ),
    );
  }

  void _showManageDialog(
    BuildContext ctx,
    String uid,
    String email,
    bool isManager,
  ) {
    showDialog(
      context: ctx,
      builder: (dialogCtx) => AlertDialog(
        title: Text(
          '${_t('إدارة:')} $email',
          style: const TextStyle(fontSize: 15),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                _t('⏱ إعداد مدة الاشتراك وحد المستخدمين:'),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () {
                  Navigator.pop(dialogCtx);
                  _showSubscriptionSettingsDialog(ctx, uid, email, isManager);
                },
                icon: const Icon(Icons.tune),
                label: Text(_t('اختيار المدة وعدد المستخدمين')),
              ),
              const Divider(height: 24),
              if (isManager) ...[
                Text(
                  'حد مستخدمي الورشة (يشمل مدير الورشة):',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children:
                      [3, 4, 5, 6, 10, 20]
                          .map(
                            (n) => ElevatedButton(
                              onPressed: () {
                                Navigator.pop(dialogCtx);
                                _updateMaxWorkers(ctx, uid, email, n);
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.teal,
                                foregroundColor: Colors.white,
                              ),
                              child: Text(
                                _tf('{count} مستخدمين', {'count': n}),
                              ),
                            ),
                          )
                          .toList()
                        ..add(
                          ElevatedButton(
                            onPressed: () {
                              Navigator.pop(dialogCtx);
                              _updateMaxWorkers(ctx, uid, email, 999);
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.teal,
                              foregroundColor: Colors.white,
                            ),
                            child: Text(_t('بلا حدود')),
                          ),
                        ),
                ),
                const SizedBox(height: 8),
                Text(
                  'حد أنظمة العمل:',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children:
                      [1, 2, 3, 4, 5, 6]
                          .map(
                            (n) => ElevatedButton(
                              onPressed: () {
                                Navigator.pop(dialogCtx);
                                _updateWorkshopLimit(
                                  ctx,
                                  uid,
                                  email,
                                  'maxSystems',
                                  n,
                                  'أنظمة العمل',
                                );
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.indigo,
                                foregroundColor: Colors.white,
                              ),
                              child: Text('$n'),
                            ),
                          )
                          .toList()
                        ..add(
                          ElevatedButton(
                            onPressed: () {
                              Navigator.pop(dialogCtx);
                              _updateWorkshopLimit(
                                ctx,
                                uid,
                                email,
                                'maxSystems',
                                999,
                                'أنظمة العمل',
                              );
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.indigo,
                              foregroundColor: Colors.white,
                            ),
                            child: Text(_t('بلا حدود')),
                          ),
                        ),
                ),
                const SizedBox(height: 8),
                Text(
                  'حد البروفيلات:',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children:
                      [1, 2, 3, 4, 5, 6, 10]
                          .map(
                            (n) => ElevatedButton(
                              onPressed: () {
                                Navigator.pop(dialogCtx);
                                _updateWorkshopLimit(
                                  ctx,
                                  uid,
                                  email,
                                  'maxProfiles',
                                  n,
                                  'بروفيلات',
                                );
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.deepPurple,
                                foregroundColor: Colors.white,
                              ),
                              child: Text('$n'),
                            ),
                          )
                          .toList()
                        ..add(
                          ElevatedButton(
                            onPressed: () {
                              Navigator.pop(dialogCtx);
                              _updateWorkshopLimit(
                                ctx,
                                uid,
                                email,
                                'maxProfiles',
                                999,
                                'بروفيلات',
                              );
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.deepPurple,
                              foregroundColor: Colors.white,
                            ),
                            child: Text(_t('بلا حدود')),
                          ),
                        ),
                ),
                const Divider(height: 24),
                ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(dialogCtx);
                    _deleteWorkshop(ctx, uid, email);
                  },
                  icon: const Icon(Icons.delete_forever),
                  label: Text(_t('مسح الورشة نهائياً')),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(double.infinity, 44),
                  ),
                ),
              ],
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () {
                  Navigator.pop(dialogCtx);
                  _revokeSubscription(ctx, uid, email);
                },
                icon: const Icon(
                  Icons.remove_circle_outline,
                  color: Colors.red,
                ),
                label: Text(
                  _t('سحب الاشتراك'),
                  style: const TextStyle(color: Colors.red),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: Text(_t('إغلاق')),
          ),
        ],
      ),
    );
  }

  // ──────────────── Widgets ────────────────

  Widget _buildWorkshopCard(
    BuildContext ctx,
    String wId,
    List<QueryDocumentSnapshot> wUsers,
  ) {
    QueryDocumentSnapshot? managerDoc;
    try {
      managerDoc = wUsers.firstWhere(
        (u) => (u.data() as Map<String, dynamic>)['role'] == 'manager',
      );
    } catch (_) {}

    final workers = wUsers
        .where((u) => (u.data() as Map<String, dynamic>)['role'] == 'worker')
        .toList();
    final others = wUsers.where((u) {
      final r = (u.data() as Map<String, dynamic>)['role'];
      return r != 'manager' && r != 'worker';
    }).toList();

    final mgrData = managerDoc != null
        ? (managerDoc.data() as Map<String, dynamic>)
        : (wUsers.isNotEmpty
              ? (wUsers.first.data() as Map<String, dynamic>)
              : <String, dynamic>{});

    final workshopName =
        mgrData['workshopName'] ?? mgrData['name'] ?? 'ورشة بدون اسم';
    final mgrEmail = mgrData['email'] ?? 'غير معروف';
    final active = _isActive(mgrData);
    final (statusText, statusColor) = _statusInfo(mgrData);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: active ? Colors.transparent : Colors.red.shade300,
          width: active ? 0 : 2,
        ),
      ),
      elevation: active ? 2 : 5,
      child: ExpansionTile(
        leading: CircleAvatar(
          backgroundColor: active ? Colors.blue.shade600 : Colors.red.shade400,
          child: Icon(
            active ? Icons.storefront : Icons.lock_clock,
            color: Colors.white,
            size: 20,
          ),
        ),
        title: Text(
          workshopName,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              mgrEmail,
              style: const TextStyle(fontSize: 12, color: Colors.blueGrey),
            ),
            const SizedBox(height: 2),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withAlpha(30),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: statusColor.withAlpha(80)),
                  ),
                  child: Text(
                    statusText,
                    style: TextStyle(
                      fontSize: 11,
                      color: statusColor,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${wUsers.length} مستخدمين',
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                ),
              ],
            ),
          ],
        ),
        // Quick activation button visible without expanding
        trailing: !active
            ? ElevatedButton(
                onPressed: () {
                  if (managerDoc != null) {
                    _showManageDialog(ctx, managerDoc.id, mgrEmail, true);
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  textStyle: const TextStyle(fontSize: 12),
                ),
                child: Text(_t('تفعيل')),
              )
            : null,
        children: [
          // Manager row
          if (managerDoc != null) _buildUserRow(ctx, managerDoc, true),
          if (workers.isNotEmpty) ...[
            const Divider(height: 1, indent: 16, endIndent: 16),
            ...workers.map((w) => _buildUserRow(ctx, w, false)),
          ],
          if (others.isNotEmpty) ...[
            const Divider(height: 1, indent: 16, endIndent: 16),
            ...others.map((w) => _buildUserRow(ctx, w, false)),
          ],
          // Workshop details
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Divider(),
                if (mgrData['workshopLocation'] != null)
                  Text(
                    '📍 ${mgrData['workshopLocation']}',
                    style: const TextStyle(fontSize: 13),
                  ),
                if (mgrData['workshopSpecialties'] != null)
                  Text(
                    '🛠 ${mgrData['workshopSpecialties']}',
                    style: const TextStyle(fontSize: 13),
                  ),
                Text(
                  '🆔 UID: $wId',
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUserRow(
    BuildContext ctx,
    QueryDocumentSnapshot doc,
    bool isManager,
  ) {
    final data = doc.data() as Map<String, dynamic>;
    final email = data['email'] ?? 'بدون بريد';
    final name = data['name'] ?? data['displayName'] ?? 'بدون اسم';
    final (statusText, statusColor) = _statusInfo(data);

    return ListTile(
      leading: Icon(
        isManager ? Icons.manage_accounts : Icons.person,
        color: isManager ? Colors.blue : Colors.grey,
      ),
      title: Text(
        name,
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(email, style: const TextStyle(fontSize: 12)),
          Text(
            statusText,
            style: TextStyle(
              color: statusColor,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
      trailing: IconButton(
        icon: const Icon(Icons.settings),
        color: isManager ? Colors.blue : Colors.grey,
        tooltip: _t('إدارة الحساب'),
        onPressed: () => _showManageDialog(ctx, doc.id, email, isManager),
      ),
      isThreeLine: true,
    );
  }

  Map<String, dynamic> _supabaseSubscriptionData(Map<String, dynamic> row) {
    return {
      'subscriptionStatus': row['status'],
      'subscriptionType': row['plan_type'],
      'subscriptionStartDate': row['starts_at'],
      'subscriptionEndDate': row['ends_at'],
      'maxUsers': row['max_users'],
      'maxSystems': row['max_systems'],
      'maxProfiles': row['max_profiles'],
    };
  }

  String _supabaseWorkshopGroupKey(Map<String, dynamic> row) {
    final workshopId =
        row['workshop_id']?.toString().trim() ??
        row['id']?.toString().trim() ??
        '';
    if (workshopId.isNotEmpty) return 'workshop:$workshopId';
    final code = row['code']?.toString().trim() ?? '';
    if (code.isNotEmpty) return 'code:$code';
    final ownerUid = row['owner_uid']?.toString().trim() ?? '';
    if (ownerUid.isNotEmpty) return 'owner:$ownerUid';
    final name = row['name']?.toString().trim().toLowerCase() ?? '';
    final email = row['owner_email']?.toString().trim().toLowerCase() ?? '';
    return 'group:$name|$email';
  }

  String _supabaseWorkshopName(List<Map<String, dynamic>> rows) {
    for (final row in rows) {
      final name = row['name']?.toString().trim() ?? '';
      if (name.isNotEmpty) return name;
    }
    return _t('ورشة بدون اسم');
  }

  String _supabaseWorkshopEmail(List<Map<String, dynamic>> rows) {
    for (final row in rows) {
      final email = row['owner_email']?.toString().trim() ?? '';
      if (email.isNotEmpty) return email;
    }
    return _t('بدون بريد إلكتروني');
  }

  Map<String, dynamic> _supabaseStatusRow(List<Map<String, dynamic>> rows) {
    for (final row in rows) {
      if (_isActive(_supabaseSubscriptionData(row))) return row;
    }
    return rows.first;
  }

  int _supabaseMemberCount(List<Map<String, dynamic>> rows) {
    var count = 0;
    for (final row in rows) {
      final value = int.tryParse(row['member_count']?.toString() ?? '') ?? 0;
      if (value > count) count = value;
    }
    return count;
  }

  List<String> _supabaseWorkshopCodes(List<Map<String, dynamic>> rows) {
    return rows
        .map((row) => row['code']?.toString().trim() ?? '')
        .where((code) => code.isNotEmpty)
        .toSet()
        .toList(growable: false);
  }

  Future<void> _setSupabaseSubscriptionForGroup(
    BuildContext ctx,
    List<Map<String, dynamic>> rows, {
    required String status,
    required String planType,
    DateTime? endsAt,
    int? maxUsers,
    required String message,
  }) async {
    try {
      for (final row in rows) {
        final workshopId = row['workshop_id']?.toString().trim() ?? '';
        if (workshopId.isEmpty) continue;
        await SupabaseAccountService().setSubscriptionForWorkshopId(
          workshopId: workshopId,
          status: status,
          planType: planType,
          endsAt: endsAt,
          maxUsers: maxUsers,
        );
      }
      if (ctx.mounted) {
        ScaffoldMessenger.of(ctx).showSnackBar(
          SnackBar(content: Text(message), backgroundColor: Colors.green),
        );
        setState(() {});
      }
    } catch (error) {
      if (ctx.mounted) {
        ScaffoldMessenger.of(
          ctx,
        ).showSnackBar(SnackBar(content: Text('${_t('خطأ:')} $error')));
      }
    }
  }

  void _showSupabaseSubscriptionSettingsDialog(
    BuildContext ctx,
    List<Map<String, dynamic>> rows,
  ) {
    final current = _supabaseSubscriptionData(_supabaseStatusRow(rows));
    int? selectedDays = 30;
    var selectedMaxUsers =
        int.tryParse(current['maxUsers']?.toString() ?? '') ?? 4;
    if (selectedMaxUsers <= 0) selectedMaxUsers = 4;

    showDialog(
      context: ctx,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (dialogCtx, setDialogState) => AlertDialog(
          title: Text(_t('إعداد الاشتراك')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  _t('مدة الاشتراك:'),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _subscriptionDurations
                      .map(
                        (days) => ChoiceChip(
                          label: Text(_subscriptionDurationLabel(days)),
                          selected: selectedDays == days,
                          onSelected: (value) {
                            if (value) {
                              setDialogState(() => selectedDays = days);
                            }
                          },
                        ),
                      )
                      .toList(),
                ),
                const SizedBox(height: 16),
                Text(
                  _t('عدد المستخدمين المسموح به (يشمل المدير):'),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _allowedWorkerCounts
                      .map(
                        (count) => ChoiceChip(
                          label: Text(
                            _tf('{count} مستخدمين', {'count': count}),
                          ),
                          selected: selectedMaxUsers == count,
                          onSelected: (value) {
                            if (value) {
                              setDialogState(() => selectedMaxUsers = count);
                            }
                          },
                        ),
                      )
                      .toList(),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: Text(_t('إلغاء')),
            ),
            FilledButton.icon(
              onPressed: () {
                Navigator.pop(dialogCtx);
                final endsAt = _subscriptionDuration(selectedDays) == null
                    ? null
                    : DateTime.now().add(_subscriptionDuration(selectedDays)!);
                _setSupabaseSubscriptionForGroup(
                  ctx,
                  rows,
                  status: selectedDays == null ? 'active' : 'trialing',
                  planType: selectedDays == null ? 'lifetime' : 'trial',
                  endsAt: endsAt,
                  maxUsers: selectedMaxUsers,
                  message: selectedDays == null
                      ? _t('تم حفظ الاشتراك الدائم وحد المستخدمين.')
                      : _tf(
                          selectedDays! < 0
                              ? 'تم حفظ اشتراك الاختبار لمدة {minutes} دقيقة وحد المستخدمين.'
                              : 'تم حفظ الاشتراك لمدة {days} يومًا وحد المستخدمين.',
                          selectedDays! < 0
                              ? {'minutes': -selectedDays!}
                              : {'days': selectedDays!},
                        ),
                );
              },
              icon: const Icon(Icons.save),
              label: Text(_t('حفظ الاشتراك')),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openSupabaseWorkshop(
    BuildContext ctx,
    List<Map<String, dynamic>> rows,
  ) async {
    final code = _supabaseWorkshopCodes(rows).firstOrNull ?? '';
    final name = _supabaseWorkshopName(rows);
    if (code.isEmpty) return;
    try {
      final account = await SupabaseAccountService()
          .loadSelectedApplicationAdminWorkshop(code: code, name: name);
      if (account == null) {
        throw Exception('لم يتم العثور على الورشة المحددة في Supabase.');
      }
      CloudSyncService().reset();
      final sync = SupabaseWorkshopSyncService();
      final ready = await sync.ensureStarted(
        timeout: const Duration(seconds: 20),
      );
      if (!ready) {
        throw Exception('تعذر تجهيز اتصال الورشة المحددة.');
      }
      await sync.downloadWorkshopData(full: true);
      final diagnostics = await sync.inspectWorkshopData();
      await CloudSyncService().init();
      if (ctx.mounted) {
        final hasRemoteData = diagnostics.syncRows > 0;
        ScaffoldMessenger.of(ctx).showSnackBar(
          SnackBar(
            content: Text(
              hasRemoteData
                  ? 'تم فتح ${account.workshopName} (${account.workshopCode}). '
                        '${sync.lastDownloadSummary}\n'
                        'السجلات: ${diagnostics.syncRows}، الملف: '
                        '${diagnostics.profileExists ? 'موجود' : 'غير موجود'}، '
                        'المستخدمون: ${diagnostics.members}'
                  : 'تم تحديد الورشة، لكن لم توجد سجلات بيانات لها. '
                        'الكود: ${diagnostics.workshopCode}، '
                        'UUID: ${diagnostics.workshopUuid}، '
                        'UID: ${diagnostics.userId}',
            ),
            backgroundColor: hasRemoteData ? Colors.green : Colors.orange,
            duration: const Duration(seconds: 8),
          ),
        );
        setState(() {});
      }
    } catch (error) {
      if (ctx.mounted) {
        ScaffoldMessenger.of(ctx).showSnackBar(
          SnackBar(
            content: Text('تعذر فتح بيانات الورشة: $error'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 8),
          ),
        );
      }
    }
  }

  Future<List<Map<String, dynamic>>> _loadAdminWorkshopMembers(
    List<Map<String, dynamic>> rows,
  ) async {
    final members = <Map<String, dynamic>>[];
    final seen = <String>{};
    for (final code in _supabaseWorkshopCodes(rows)) {
      final loaded = await SupabaseAccountService().fetchAdminWorkshopMembers(
        code,
      );
      for (final member in loaded) {
        final email = member['email']?.toString().trim().toLowerCase() ?? '';
        final userId = member['user_id']?.toString().trim() ?? '';
        final key = userId.isNotEmpty ? 'uid:$userId' : 'email:$email';
        if (key == 'email:' || !seen.add(key)) continue;
        members.add({...member, '_sourceCode': code});
      }
    }
    return members;
  }

  Future<void> _showSupabaseMemberDialog(
    BuildContext ctx,
    Map<String, dynamic> member,
  ) async {
    final email = member['email']?.toString().trim() ?? '';
    if (email.isEmpty) return;
    var blocked = member['blocked'] == true;
    var role = member['role']?.toString().trim() ?? 'worker';
    if (!const ['worker', 'manager', 'co_manager', 'admin'].contains(role)) {
      role = 'worker';
    }
    final permissions = member['permissions'] is Map
        ? Map<String, dynamic>.from(member['permissions'] as Map)
        : <String, dynamic>{};
    var saving = false;

    final updated = await showDialog<bool>(
      context: ctx,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (dialogCtx, setDialogState) {
          return AlertDialog(
            title: Text(_t('إدارة العامل')),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(email, style: const TextStyle(fontSize: 13)),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: role,
                  decoration: InputDecoration(labelText: _t('الدور')),
                  items: [
                    DropdownMenuItem(value: 'worker', child: Text(_t('عامل'))),
                    DropdownMenuItem(
                      value: 'co_manager',
                      child: Text(_t('نائب مدير')),
                    ),
                    DropdownMenuItem(value: 'manager', child: Text(_t('مدير'))),
                    DropdownMenuItem(value: 'admin', child: Text(_t('مسؤول'))),
                  ],
                  onChanged: saving
                      ? null
                      : (value) {
                          if (value != null) setDialogState(() => role = value);
                        },
                ),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: Text(_t('حظر الحساب')),
                  value: blocked,
                  onChanged: saving
                      ? null
                      : (value) => setDialogState(() => blocked = value),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: saving ? null : () => Navigator.pop(dialogCtx),
                child: Text(_t('إلغاء')),
              ),
              FilledButton.icon(
                onPressed: saving
                    ? null
                    : () async {
                        setDialogState(() => saving = true);
                        try {
                          await SupabaseAccountService()
                              .updateAdminWorkshopMember(
                                workshopCode:
                                    member['_sourceCode']?.toString() ?? '',
                                email: email,
                                role: role,
                                permissions: {
                                  ...permissions,
                                  'isBlocked': blocked,
                                  'full_manager_permissions':
                                      role == 'co_manager',
                                  'co_manager': role == 'co_manager',
                                },
                                blocked: blocked,
                              );
                          if (dialogCtx.mounted) {
                            Navigator.pop(dialogCtx, true);
                          }
                        } catch (error) {
                          setDialogState(() => saving = false);
                          if (dialogCtx.mounted) {
                            ScaffoldMessenger.of(dialogCtx).showSnackBar(
                              SnackBar(content: Text('${_t('خطأ:')} $error')),
                            );
                          }
                        }
                      },
                icon: saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save),
                label: Text(_t('حفظ')),
              ),
            ],
          );
        },
      ),
    );
    if (updated == true && ctx.mounted) {
      ScaffoldMessenger.of(ctx).showSnackBar(
        SnackBar(
          content: Text(_t('تم حفظ إعدادات العامل.')),
          backgroundColor: Colors.green,
        ),
      );
      setState(() {});
    }
  }

  Widget _buildSupabaseMembersSection(
    BuildContext ctx,
    List<Map<String, dynamic>> rows,
    String subscriptionStatusText,
  ) {
    final managerEmail = _supabaseWorkshopEmail(rows);
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _loadAdminWorkshopMembers(rows),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.all(18),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Text('${_t('تعذر تحميل أعضاء الورشة:')} ${snapshot.error}'),
          );
        }
        final members = snapshot.data ?? const <Map<String, dynamic>>[];
        return Column(
          children: [
            ListTile(
              dense: true,
              leading: const Icon(Icons.manage_accounts, color: Colors.blue),
              title: Text(_t('مدير الورشة')),
              subtitle: Text(
                '$managerEmail\n${_t('الاشتراك الموحّد للورشة')}: $subscriptionStatusText',
              ),
            ),
            if (members.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(
                    _t('لا يوجد عمال أو مشتركون داخل هذه الورشة.'),
                    style: const TextStyle(color: Colors.grey),
                  ),
                ),
              )
            else
              ...members.map(
                (member) => ListTile(
                  dense: true,
                  leading: Icon(
                    member['is_pending'] == true
                        ? Icons.mail_outline
                        : Icons.person_outline,
                    color: member['blocked'] == true
                        ? Colors.red
                        : Colors.grey.shade700,
                  ),
                  title: Text(member['email']?.toString() ?? _t('بدون بريد')),
                  subtitle: Text(
                    '${member['is_pending'] == true ? '${_t('دعوة معلقة')} • ' : ''}'
                    '${member['role'] ?? 'worker'} • ${_t('تابع لاشتراك الورشة')}'
                    '${member['blocked'] == true ? ' • ${_t('محظور')}' : ''}',
                  ),
                  trailing: IconButton(
                    tooltip: _t('إدارة العامل'),
                    icon: const Icon(Icons.settings_outlined),
                    onPressed: () => _showSupabaseMemberDialog(ctx, member),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildSupabaseWorkshopCard(
    BuildContext ctx,
    List<Map<String, dynamic>> rows,
  ) {
    final statusRow = _supabaseStatusRow(rows);
    final statusData = _supabaseSubscriptionData(statusRow);
    final active = _isActive(statusData);
    final (statusText, statusColor) = _statusInfo(statusData);
    final codes = _supabaseWorkshopCodes(rows);
    final email = _supabaseWorkshopEmail(rows);
    final count = _supabaseMemberCount(rows);

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: active ? Colors.transparent : Colors.red.shade300,
          width: active ? 0 : 2,
        ),
      ),
      child: ExpansionTile(
        leading: Icon(
          active ? Icons.storefront : Icons.lock_clock,
          color: active ? Colors.green : Colors.red,
        ),
        title: Text(
          _supabaseWorkshopName(rows),
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        subtitle: Text('$email  •  $count ${_t('مستخدمين')}'),
        trailing: Chip(
          label: Text(
            statusText,
            style: TextStyle(color: statusColor, fontSize: 11),
          ),
          backgroundColor: statusColor.withAlpha(25),
          side: BorderSide(color: statusColor.withAlpha(80)),
        ),
        children: [
          _buildSupabaseMembersSection(ctx, rows, statusText),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: OutlinedButton.icon(
                onPressed: () => _openSupabaseWorkshop(ctx, rows),
                icon: const Icon(Icons.cloud_download_rounded),
                label: Text(_t('فتح وتنزيل بيانات الورشة')),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Divider(),
                Text(
                  '${_t('أكواد الورشة')}: ${codes.isEmpty ? _t('غير متوفر') : codes.join('، ')}',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () =>
                          _showSupabaseSubscriptionSettingsDialog(ctx, rows),
                      icon: const Icon(Icons.tune),
                      label: Text(_t('اختيار المدة وعدد المستخدمين')),
                    ),
                    FilledButton(
                      onPressed: () => _setSupabaseSubscriptionForGroup(
                        ctx,
                        rows,
                        status: 'trialing',
                        planType: 'trial',
                        endsAt: DateTime.now().add(const Duration(days: 30)),
                        message: _t('تم تفعيل الورشة لمدة 30 يومًا.'),
                      ),
                      child: Text(_t('30 يومًا')),
                    ),
                    OutlinedButton(
                      onPressed: () => _setSupabaseSubscriptionForGroup(
                        ctx,
                        rows,
                        status: 'active',
                        planType: 'lifetime',
                        message: _t('تم تفعيل الورشة بشكل دائم.'),
                      ),
                      child: Text(_t('تفعيل دائم')),
                    ),
                    TextButton(
                      onPressed: () => _setSupabaseSubscriptionForGroup(
                        ctx,
                        rows,
                        status: 'expired',
                        planType: 'trial',
                        endsAt: DateTime.now(),
                        message: _t('تم سحب اشتراك الورشة.'),
                      ),
                      child: Text(
                        _t('سحب الاشتراك'),
                        style: const TextStyle(color: Colors.red),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSupabaseAdminBody() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: SupabaseAccountService().fetchAdminWorkshops(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: Text(
              '${_t('تعذر تحميل الورش من Supabase:')}\n${snapshot.error}',
            ),
          );
        }
        var rows = snapshot.data ?? const <Map<String, dynamic>>[];
        if (_searchQuery.trim().isNotEmpty) {
          final query = _searchQuery.trim().toLowerCase();
          rows = rows
              .where((row) {
                final text =
                    '${row['name']} ${row['code']} ${row['owner_email']}'
                        .toLowerCase();
                return text.contains(query);
              })
              .toList(growable: false);
        }
        if (rows.isEmpty) {
          return Center(child: Text(_t('لا يوجد مستخدمون في قاعدة البيانات')));
        }

        final grouped = <String, List<Map<String, dynamic>>>{};
        for (final row in rows) {
          grouped
              .putIfAbsent(_supabaseWorkshopGroupKey(row), () => [])
              .add(row);
        }
        final groups = grouped.values.toList()
          ..sort((a, b) {
            final aActive = _isActive(
              _supabaseSubscriptionData(_supabaseStatusRow(a)),
            );
            final bActive = _isActive(
              _supabaseSubscriptionData(_supabaseStatusRow(b)),
            );
            if (aActive != bActive) return aActive ? 1 : -1;
            return _supabaseWorkshopName(a).compareTo(_supabaseWorkshopName(b));
          });

        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
          itemCount: groups.length,
          itemBuilder: (context, index) =>
              _buildSupabaseWorkshopCard(context, groups[index]),
        );
      },
    );
  }

  // ──────────────── Build ────────────────

  @override
  Widget build(BuildContext context) {
    final isAppAdmin = isApplicationAdminEmail(
      AppAuthService().currentUser?.email,
    );
    if (AppAuthService().usesSupabase && isAppAdmin) {
      return Scaffold(
        appBar: AppBar(
          title: Text(_t('إدارة المشتركين والورشات')),
          centerTitle: true,
        ),
        body: Column(
          children: [
            _buildPaymentSettingsCard(),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: _t('بحث بالاسم أو البريد الإلكتروني...'),
                  prefixIcon: const Icon(Icons.search),
                  border: const OutlineInputBorder(),
                ),
                onChanged: (value) =>
                    setState(() => _searchQuery = value.toLowerCase()),
              ),
            ),
            Expanded(child: _buildSupabaseAdminBody()),
          ],
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(_t('إدارة المشتركين والورشات')),
        centerTitle: true,
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(text: _t('الكل')),
            Tab(
              text: _t('منتهية / بحاجة تفعيل'),
              icon: Icon(Icons.warning_amber_rounded, size: 16),
            ),
            Tab(text: _t('فعّالة')),
          ],
        ),
      ),
      body: NestedScrollView(
        // The payment card and search field must be part of the outer scroll
        // view so the CCP field can be brought above the on-screen keyboard.
        headerSliverBuilder: (context, innerBoxIsScrolled) => [
          if (isAppAdmin)
            SliverToBoxAdapter(child: _buildPaymentSettingsCard()),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: _t('بحث بالاسم أو البريد الإلكتروني...'),
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _searchQuery = '');
                          },
                        )
                      : null,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 8),
                  isDense: true,
                ),
                onChanged: (v) =>
                    setState(() => _searchQuery = v.toLowerCase()),
              ),
            ),
          ),
        ],
        body: StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance.collection('users').snapshots(),
          builder: (ctx, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.error_outline,
                      color: Colors.red,
                      size: 48,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'خطأ في قراءة البيانات:\n${snapshot.error}',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'تأكد من أن قواعد Firestore تسمح للمسؤول بقراءة جميع المستخدمين.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                  ],
                ),
              );
            }
            if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
              return Center(
                child: Text(_t('لا يوجد مستخدمون في قاعدة البيانات')),
              );
            }

            // Filter out admin's own account
            final allUsers = snapshot.data!.docs.where((doc) {
              final d = doc.data() as Map<String, dynamic>;
              return !isApplicationAdminEmail(d['email']?.toString()) &&
                  d['role'] != 'admin';
            }).toList();

            // Apply search
            final filtered = _searchQuery.isEmpty
                ? allUsers
                : allUsers.where((doc) {
                    final d = doc.data() as Map<String, dynamic>;
                    final email = (d['email'] ?? '').toString().toLowerCase();
                    final name = (d['name'] ?? d['displayName'] ?? '')
                        .toString()
                        .toLowerCase();
                    final workshop = (d['workshopName'] ?? '')
                        .toString()
                        .toLowerCase();
                    return email.contains(_searchQuery) ||
                        name.contains(_searchQuery) ||
                        workshop.contains(_searchQuery);
                  }).toList();

            // Group by workshopId
            final Map<String, List<QueryDocumentSnapshot>> workshops = {};
            for (var user in filtered) {
              final d = user.data() as Map<String, dynamic>;
              final wId = (d['workshopId'] as String?)?.isNotEmpty == true
                  ? d['workshopId'] as String
                  : user.id;
              workshops.putIfAbsent(wId, () => []).add(user);
            }

            // Get manager data for each workshop for filtering
            bool workshopIsActive(String wId) {
              final wUsers = workshops[wId]!;
              QueryDocumentSnapshot? mgr;
              try {
                mgr = wUsers.firstWhere(
                  (u) =>
                      (u.data() as Map<String, dynamic>)['role'] == 'manager',
                );
              } catch (_) {}
              final d = mgr != null
                  ? (mgr.data() as Map<String, dynamic>)
                  : (wUsers.isNotEmpty
                        ? (wUsers.first.data() as Map<String, dynamic>)
                        : <String, dynamic>{});
              return _isActive(d);
            }

            final allIds = workshops.keys.toList()
              ..sort((a, b) {
                // Expired workshops first
                final aActive = workshopIsActive(a);
                final bActive = workshopIsActive(b);
                if (aActive == bActive) return 0;
                return aActive ? 1 : -1;
              });

            final expiredIds = allIds
                .where((id) => !workshopIsActive(id))
                .toList();
            final activeIds = allIds
                .where((id) => workshopIsActive(id))
                .toList();

            Widget buildList(List<String> ids) {
              if (ids.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.check_circle_outline,
                        color: Colors.green,
                        size: 48,
                      ),
                      const SizedBox(height: 12),
                      Text(_t('لا توجد ورشات في هذه الفئة')),
                    ],
                  ),
                );
              }
              return ListView.builder(
                itemCount: ids.length,
                itemBuilder: (_, i) =>
                    _buildWorkshopCard(ctx, ids[i], workshops[ids[i]]!),
              );
            }

            return TabBarView(
              controller: _tabController,
              children: [
                // Tab 0 – All
                Column(
                  children: [
                    Container(
                      color: Colors.grey.shade100,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 6,
                      ),
                      child: Row(
                        children: [
                          Text(
                            'إجمالي الورشات: ${allIds.length}',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Text(
                            'منتهية: ${expiredIds.length}',
                            style: const TextStyle(
                              fontSize: 13,
                              color: Colors.red,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(child: buildList(allIds)),
                  ],
                ),
                // Tab 1 – Expired / need activation
                Column(
                  children: [
                    if (expiredIds.isNotEmpty)
                      Container(
                        color: Colors.red.shade50,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.warning_amber_rounded,
                              color: Colors.orange,
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '${expiredIds.length} ورشة بحاجة للتفعيل – اضغط "تفعيل" على أي بطاقة',
                              style: const TextStyle(
                                color: Colors.red,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    Expanded(child: buildList(expiredIds)),
                  ],
                ),
                // Tab 2 – Active
                buildList(activeIds),
              ],
            );
          },
        ),
      ),
    );
  }
}
