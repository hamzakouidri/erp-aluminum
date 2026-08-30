import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import '../settings/app_settings.dart';
import '../settings/localization.dart';
import '../services/subscription_service.dart';

class AdminUsersScreen extends StatefulWidget {
  const AdminUsersScreen({super.key});

  @override
  State<AdminUsersScreen> createState() => _AdminUsersScreenState();
}

class _AdminUsersScreenState extends State<AdminUsersScreen>
    with SingleTickerProviderStateMixin {
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

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    if (isApplicationAdminEmail(FirebaseAuth.instance.currentUser?.email)) {
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
    if (!isApplicationAdminEmail(FirebaseAuth.instance.currentUser?.email)) {
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

  Future<void> _grantDays(
    BuildContext ctx,
    String uid,
    String email,
    int days,
  ) async {
    final expiry = DateTime.now().add(Duration(days: days));
    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).update({
        'trialEndDate': expiry.toIso8601String(),
        'subscriptionStatus': 'trial',
        'subscriptionExpiredDate': FieldValue.delete(),
      });
      if (ctx.mounted) {
        ScaffoldMessenger.of(ctx).showSnackBar(
          SnackBar(
            content: Text(
              _tf('✅ تم تفعيل {email} لمدة {days} أيام', {
                'email': email,
                'days': days,
              }),
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (ctx.mounted) {
        ScaffoldMessenger.of(ctx).showSnackBar(
          SnackBar(
            content: Text('${_t('خطأ:')} $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _grantActive(BuildContext ctx, String uid, String email) async {
    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).update({
        'subscriptionStatus': 'active',
        'trialEndDate': FieldValue.delete(),
        'subscriptionEndDate': FieldValue.delete(),
        'subscriptionExpiresAt': FieldValue.delete(),
        'expiresAt': FieldValue.delete(),
        'subscriptionExpiredDate': FieldValue.delete(),
      });
      if (ctx.mounted) {
        ScaffoldMessenger.of(ctx).showSnackBar(
          SnackBar(
            content: Text(
              _tf('✅ تم تفعيل {email} كاشتراك دائم', {'email': email}),
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (ctx.mounted) {
        ScaffoldMessenger.of(ctx).showSnackBar(
          SnackBar(
            content: Text('${_t('خطأ:')} $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _revokeSubscription(
    BuildContext ctx,
    String uid,
    String email,
  ) async {
    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).update({
        'trialEndDate': FieldValue.delete(),
        'subscriptionStatus': 'expired',
        'subscriptionExpiredDate': DateTime.now().toIso8601String(),
      });
      if (ctx.mounted) {
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
      await FirebaseFirestore.instance
          .collection('workshops')
          .doc(workshopId)
          .set({'maxUsers': limit}, SetOptions(merge: true));
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
      await FirebaseFirestore.instance
          .collection('workshops')
          .doc(workshopId)
          .set({field: limit}, SetOptions(merge: true));
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
    } catch (e) {
      if (ctx.mounted) {
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
      if (ctx.mounted) {
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
                _t('⏱ منح فترة تجريبية:'),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [3, 7, 15, 30, 60, 90]
                    .map(
                      (d) => ElevatedButton(
                        onPressed: () {
                          Navigator.pop(dialogCtx);
                          _grantDays(ctx, uid, email, d);
                        },
                        child: Text(_tf('{days} يوم', {'days': d})),
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(dialogCtx);
                  _grantActive(ctx, uid, email);
                },
                icon: const Icon(Icons.verified),
                label: Text(_t('اشتراك نشط دائم (مدفوع)')),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                ),
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

  // ──────────────── Build ────────────────

  @override
  Widget build(BuildContext context) {
    final isAppAdmin = isApplicationAdminEmail(
      FirebaseAuth.instance.currentUser?.email,
    );
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
      body: Column(
        children: [
          if (isAppAdmin) _buildPaymentSettingsCard(),
          // Search bar
          Padding(
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
              onChanged: (v) => setState(() => _searchQuery = v.toLowerCase()),
            ),
          ),
          // Tab content
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .snapshots(),
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
                        final email = (d['email'] ?? '')
                            .toString()
                            .toLowerCase();
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
                          (u.data() as Map<String, dynamic>)['role'] ==
                          'manager',
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
        ],
      ),
    );
  }
}
