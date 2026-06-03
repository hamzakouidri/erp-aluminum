import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class AdminUsersScreen extends StatelessWidget {
  const AdminUsersScreen({super.key});

  Future<void> _updateSubscription(BuildContext context, String uid, String email, int? days) async {
    try {
      if (days == null) {
        // Revoke
        await FirebaseFirestore.instance.collection('users').doc(uid).update({
          'trialEndDate': FieldValue.delete(),
          'subscriptionStatus': 'expired',
          'subscriptionExpiredDate': DateTime.now().toIso8601String(),
        });
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('تم إلغاء وسحب الاشتراك من $email')),
          );
        }
      } else {
        // Grant
        final expiryDate = DateTime.now().add(Duration(days: days));
        await FirebaseFirestore.instance.collection('users').doc(uid).update({
          'trialEndDate': expiryDate.toIso8601String(),
          'subscriptionStatus': 'trial',
          'subscriptionExpiredDate': FieldValue.delete(),
        });
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('تم تفعيل الاشتراك لمدة $days أيام للمستخدم $email')),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('حدث خطأ: $e')),
        );
      }
    }
  }

  Future<void> _updateMaxWorkers(BuildContext context, String workshopId, String email, int limit) async {
    try {
      await FirebaseFirestore.instance.collection('workshops').doc(workshopId).set({
        'maxWorkers': limit,
      }, SetOptions(merge: true));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(limit == 999 ? 'تم فتح الحد الأقصى للعمال للورشة الخاصة بـ $email' : 'تم تحديد الحد الأقصى بـ $limit عمال للورشة الخاصة بـ $email')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('حدث خطأ: $e')));
      }
    }
  }

  Future<void> _deleteWorkshop(BuildContext context, String uid, String email) async {
    // Show confirmation dialog first
    bool confirm = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تأكيد المسح النهائي'),
        content: Text('هل أنت متأكد أنك تريد مسح الورشة ($email)؟ هذا سيؤدي إلى حذف حساب المدير وجميع حسابات عماله من خوادم التطبيق ولا يمكن التراجع عنه.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('مسح نهائي', style: TextStyle(color: Colors.red))),
        ],
      ),
    ) ?? false;

    if (!confirm) return;

    try {
      // Find all workers of this workshop
      final workersQuery = await FirebaseFirestore.instance.collection('users').where('workshopId', isEqualTo: uid).get();
      
      // Delete all workers
      for (var doc in workersQuery.docs) {
        await FirebaseFirestore.instance.collection('users').doc(doc.id).delete();
      }
      
      // Delete manager's user doc
      await FirebaseFirestore.instance.collection('users').doc(uid).delete();
      
      // Delete workshop doc
      await FirebaseFirestore.instance.collection('workshops').doc(uid).delete();
      
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تم مسح الورشة ($email) وجميع عمالها بنجاح.')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('حدث خطأ أثناء المسح: $e')));
      }
    }
  }

  void _showSubscriptionDialog(BuildContext context, String uid, String email, bool isEligibleForDeletion) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('إدارة صلاحيات $email', style: const TextStyle(fontSize: 16)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('اختر المدة التي تريد منحها للمستخدم:'),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                children: [
                  ElevatedButton(
                    onPressed: () {
                      Navigator.pop(context);
                      _updateSubscription(context, uid, email, 3);
                    },
                    child: const Text('3 أيام'),
                  ),
                  ElevatedButton(
                    onPressed: () {
                      Navigator.pop(context);
                      _updateSubscription(context, uid, email, 7);
                    },
                    child: const Text('7 أيام'),
                  ),
                  ElevatedButton(
                    onPressed: () {
                      Navigator.pop(context);
                      _updateSubscription(context, uid, email, 15);
                    },
                    child: const Text('15 يوماً'),
                  ),
                  ElevatedButton(
                    onPressed: () {
                      Navigator.pop(context);
                      _updateSubscription(context, uid, email, 30);
                    },
                    child: const Text('30 يوماً'),
                  ),
                ],
              ),
              const Divider(height: 20),
              const Text('تحديد الحد الأقصى للعمال (للورشة):'),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                children: [
                  ElevatedButton(
                    onPressed: () {
                      Navigator.pop(context);
                      _updateMaxWorkers(context, uid, email, 3);
                    },
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, foregroundColor: Colors.white),
                    child: const Text('3 عمال'),
                  ),
                  ElevatedButton(
                    onPressed: () {
                      Navigator.pop(context);
                      _updateMaxWorkers(context, uid, email, 5);
                    },
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, foregroundColor: Colors.white),
                    child: const Text('5 عمال'),
                  ),
                  ElevatedButton(
                    onPressed: () {
                      Navigator.pop(context);
                      _updateMaxWorkers(context, uid, email, 10);
                    },
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, foregroundColor: Colors.white),
                    child: const Text('10 عمال'),
                  ),
                  ElevatedButton(
                    onPressed: () {
                      Navigator.pop(context);
                      _updateMaxWorkers(context, uid, email, 999);
                    },
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.purple, foregroundColor: Colors.white),
                    child: const Text('غير محدود'),
                  ),
                ],
              ),
              const Divider(height: 30),
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  _updateSubscription(context, uid, email, null);
                },
                icon: const Icon(Icons.block),
                label: const Text('سحب التطبيق (طرد/انتهاء اشتراك)'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 40),
                ),
              ),
              const SizedBox(height: 10),
              if (isEligibleForDeletion)
                ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    _deleteWorkshop(context, uid, email);
                  },
                  icon: const Icon(Icons.delete_forever),
                  label: const Text('مسح الورشة نهائياً من التطبيق'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(double.infinity, 40),
                  ),
                )
              else
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8.0),
                  child: Text(
                    'لا يمكن مسح الورشة إلا بعد مرور أكثر من 30 يوماً على انتهاء أو سحب الاشتراك.',
                    style: TextStyle(color: Colors.grey, fontSize: 13, fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('إدارة المستخدمين والاشتراكات'),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('users').snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(child: Text('حدث خطأ: ${snapshot.error}'));
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(child: Text('لا يوجد مستخدمين مسجلين'));
          }

          final users = snapshot.data!.docs;

          return ListView.builder(
            itemCount: users.length,
            itemBuilder: (context, index) {
              final userDoc = users[index];
              final data = userDoc.data() as Map<String, dynamic>;
              final email = data['email'] ?? 'بدون بريد إلكتروني';
              final role = data['role'] ?? 'worker';
              final trialEndDateStr = data['trialEndDate'] as String?;
              final subscriptionStatus = data['subscriptionStatus'] as String?;
              final expiredDateStr = data['subscriptionExpiredDate'] as String?;
              
              DateTime? trialEnd;
              if (trialEndDateStr != null) {
                try {
                  trialEnd = DateTime.parse(trialEndDateStr);
                } catch (_) {}
              }

              bool hasActiveSubscription = false;
              String statusText = 'مغلق (بدون اشتراك)';
              Color statusColor = Colors.red;

              if (subscriptionStatus == 'active') {
                hasActiveSubscription = true;
                statusText = 'اشتراك مدفوع وفعال';
                statusColor = Colors.green;
              } else if (trialEnd != null) {
                if (DateTime.now().isBefore(trialEnd)) {
                  hasActiveSubscription = true;
                  final daysLeft = trialEnd.difference(DateTime.now()).inDays;
                  statusText = 'تجريبي فعال (باقي $daysLeft يوم)';
                  statusColor = Colors.orange;
                } else {
                  statusText = 'منتهي الصلاحية';
                  statusColor = Colors.red;
                }
              }

              bool isEligibleForDeletion = true; // Temporarily bypassed for testing
              /*
              if (trialEnd != null && DateTime.now().isAfter(trialEnd) && DateTime.now().difference(trialEnd).inDays > 30) {
                isEligibleForDeletion = true;
              } else if (expiredDateStr != null) {
                try {
                  final expiredDate = DateTime.parse(expiredDateStr);
                  if (DateTime.now().difference(expiredDate).inDays > 30) {
                    isEligibleForDeletion = true;
                  }
                } catch (_) {}
              }
              */

              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: ListTile(
                  leading: const Icon(Icons.person),
                  title: Text(email, style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('الصلاحية: ${role == 'manager' ? 'مدير/مسؤول' : 'عامل'}'),
                      Text(
                        'الحالة: $statusText',
                        style: TextStyle(color: statusColor, fontWeight: FontWeight.bold),
                      ),
                      if (trialEnd != null)
                        Text('تاريخ الانتهاء: ${DateFormat('yyyy-MM-dd').format(trialEnd)}'),
                      if (role == 'manager')
                        StreamBuilder<DocumentSnapshot>(
                          stream: FirebaseFirestore.instance.collection('workshops').doc(userDoc.id).snapshots(),
                          builder: (context, wsSnapshot) {
                            int currentWorkers = users.where((u) {
                              final d = u.data() as Map<String, dynamic>;
                              return d['workshopId'] == userDoc.id && d['role'] == 'worker';
                            }).length;

                            int maxW = 3; // Default
                            if (wsSnapshot.hasData && wsSnapshot.data!.exists) {
                              final wsData = wsSnapshot.data!.data() as Map<String, dynamic>;
                              maxW = wsData['maxWorkers'] ?? 3;
                            }
                            
                            String maxText = maxW == 999 ? 'غير محدود' : maxW.toString();

                            return Padding(
                              padding: const EdgeInsets.only(top: 4.0),
                              child: Text(
                                'العمال: $currentWorkers / $maxText',
                                style: const TextStyle(color: Colors.teal, fontWeight: FontWeight.bold),
                              ),
                            );
                          },
                        ),
                    ],
                  ),
                  trailing: email == 'kouidrihamza45@gmail.com'
                      ? const Text('مدير النظام', style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold))
                      : ElevatedButton.icon(
                          onPressed: () => _showSubscriptionDialog(context, userDoc.id, email, isEligibleForDeletion),
                          icon: const Icon(Icons.settings),
                          label: const Text('إدارة الصلاحية'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue,
                            foregroundColor: Colors.white,
                          ),
                        ),
                  isThreeLine: true,
                ),
              );
            },
          );
        },
      ),
    );
  }
}
