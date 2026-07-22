import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../sql_database.dart';

class WorkersManagementScreen extends StatefulWidget {
  final SqlDatabase db;

  const WorkersManagementScreen({super.key, required this.db});

  @override
  State<WorkersManagementScreen> createState() =>
      _WorkersManagementScreenState();
}

class _WorkersManagementScreenState extends State<WorkersManagementScreen> {
  List<Map<String, dynamic>> _workers = [];
  bool _isLoading = false;
  String _joinCode = 'جاري التحميل...';

  @override
  void initState() {
    super.initState();
    _loadWorkers();
  }

  Future<void> _loadWorkers() async {
    setState(() => _isLoading = true);
    try {
      final rawData = await widget.db.readEmployees();
      List<Map<String, dynamic>> data = List<Map<String, dynamic>>.from(
        rawData,
      );

      final user = FirebaseAuth.instance.currentUser;

      // Remove manager if accidentally added to local DB
      if (user != null) {
        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();
        if (doc.exists && doc.data() != null) {
          _joinCode = doc.data()!['joinCode'] ?? user.uid;
        }

        final managerInDb = data.where((w) => w['uid'] == user.uid).toList();
        for (var m in managerInDb) {
          await widget.db.deleteEmployee(m['uid']);
        }
        data.removeWhere((w) => w['uid'] == user.uid);
      }

      // ✅ فلترة وتصفية القائمة: لا نعرض العمال المحليين (local_worker_) ولا من ليس لديهم إيميل حقيقي
      data.removeWhere((w) {
        final uid = w['uid']?.toString() ?? '';
        final email = (w['email'] ?? '').toString().trim().toLowerCase();
        return uid.startsWith('local_worker_') || email.isEmpty || email == 'no email' || email == 'no_email';
      });


      setState(() {
        _workers = data;
      });
    } catch (e) {
      print('Error loading workers: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _fetchWorkersFromCloud() async {
    setState(() => _isLoading = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .where('workshopId', isEqualTo: user.uid)
          .get();

      final existingWorkers = await widget.db.readEmployees();
      final existingUids = existingWorkers
          .map((w) => w['uid'].toString())
          .toSet();

      for (var doc in snapshot.docs) {
        if (doc.id == user.uid) continue; // Exclude the manager

        final data = doc.data();
        if (!existingUids.contains(doc.id)) {
          final cloudEmail = (data['email'] ?? '').toString().trim().toLowerCase();
          Map<String, dynamic>? matchingLocalWorker;
          if (cloudEmail.isNotEmpty && cloudEmail != 'no email') {
            for (var ew in existingWorkers) {
              final ewUid = ew['uid'].toString();
              final ewEmail = (ew['email'] ?? '').toString().trim().toLowerCase();
              if (ewUid.startsWith('local_worker_') && ewEmail == cloudEmail) {
                matchingLocalWorker = ew;
                break;
              }
            }
          }

          if (matchingLocalWorker != null) {
            // Link local worker to the Firebase account automatically
            await widget.db.linkLocalWorker(
              matchingLocalWorker['uid'].toString(),
              doc.id,
              data['email'] ?? 'No Email',
            );
          } else {
            // New worker found in cloud, insert
            final defaultPermissions = jsonEncode({
              'view_clients': false,
              'create_clients': false,
              'view_orders': false,
              'create_orders': false,
              'view_client_details': false,
              'view_order_details': false,
              'change_prices': false,
              'treasury': false,
              'manage_workers': false,
              'purchases': false,
              'add_purchases': false,
              'edit_purchases': false,
              'delete_purchases': false,
              'delete_orders': false,
              'statistics': false,
              'isBlocked': false,
              'view_suppliers': false,
            });
            await widget.db.insertEmployee(
              doc.id,
              data['email'] ?? 'No Email',
              data['name'] ?? 'عامل جديد',
              defaultPermissions,
            );
          }
        }
      }

      await _loadWorkers();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تم مزامنة العمال بنجاح'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('خطأ في الاتصال بالسحابة: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('إدارة صلاحيات الفريق'),
        backgroundColor: Theme.of(context).brightness == Brightness.dark
            ? Theme.of(context).appBarTheme.backgroundColor
            : Colors.blue,
        actions: [
          IconButton(
            icon: Icon(Icons.cloud_download),
            onPressed: _fetchWorkersFromCloud,
            tooltip: 'تحديث من السحابة',
          ),
        ],
      ),
      body: Column(
        children: [
          if (_workers.isEmpty)
            Container(
              padding: EdgeInsets.all(16),
              color: Theme.of(context).primaryColor.withValues(alpha: 0.1),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: Theme.of(context).primaryColor),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'لكي ينضم إليك أي عامل، اطلب منه تحميل التطبيق والتسجيل كعامل، ثم إدخال "كود الورشة" الخاص بك:\n$_joinCode',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: _isLoading
                ? Center(child: CircularProgressIndicator())
                : _workers.isEmpty
                ? Center(child: Text('لا يوجد عمال مسجلين في ورشتك حالياً'))
                : ListView.builder(
                    itemCount: _workers.length,
                    itemBuilder: (context, index) {
                      final worker = _workers[index];
                      return WorkerCard(
                        worker: worker,
                        db: widget.db,
                        onRefresh: _loadWorkers,
                        onDelete: () async {
                          bool? confirm = await showDialog<bool>(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: const Text(
                                'تأكيد الحذف',
                                style: TextStyle(color: Colors.red),
                              ),
                              content: const Text(
                                'هل أنت متأكد من أنك تريد طرد/حذف هذا العامل نهائياً من ورشتك؟ لن يتمكن من الدخول إلى التطبيق كعامل لديك بعد الآن.',
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () =>
                                      Navigator.pop(context, false),
                                  child: const Text('إلغاء'),
                                ),
                                ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.red,
                                  ),
                                  onPressed: () => Navigator.pop(context, true),
                                  child: const Text(
                                    'حذف',
                                    style: TextStyle(color: Colors.white),
                                  ),
                                ),
                              ],
                            ),
                          );

                          if (confirm == true) {
                            // Disconnect from Firebase so they don't get fetched again
                            try {
                              await FirebaseFirestore.instance
                                  .collection('users')
                                  .doc(worker['uid'])
                                  .delete();
                            } catch (e) {
                              debugPrint(
                                'Failed to delete worker from cloud: $e',
                              );
                            }
                            // Delete from local SQLite
                            await widget.db.deleteEmployee(worker['uid']);
                            _loadWorkers();
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'تم حذف العامل بنجاح',
                                  style: TextStyle(color: Colors.white),
                                ),
                                backgroundColor: Colors.green,
                              ),
                            );
                          }
                        },
                      );

                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class WorkerCard extends StatefulWidget {
  final Map<String, dynamic> worker;
  final SqlDatabase db;
  final VoidCallback onDelete;
  final VoidCallback onRefresh;

  const WorkerCard({
    super.key,
    required this.worker,
    required this.db,
    required this.onDelete,
    required this.onRefresh,
  });

  @override
  _WorkerCardState createState() => _WorkerCardState();
}

class _WorkerCardState extends State<WorkerCard> {
  late Map<String, dynamic> perms;

  @override
  void initState() {
    super.initState();
    _initPerms();
  }

  @override
  void didUpdateWidget(WorkerCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.worker != widget.worker) {
      _initPerms();
    }
  }

  void _initPerms() {
    try {
      perms = jsonDecode(widget.worker['permissions_json'] ?? '{}');
    } catch (e) {
      perms = {};
    }
    final defaults = {
      'view_clients': false,
      'create_clients': false,
      'view_orders': false,
      'create_orders': false,
      'view_client_details': false,
      'view_order_details': false,
      'change_prices': false,
      'treasury': false,
      'manage_workers': false,
      'purchases': false,
      'add_purchases': false,
      'edit_purchases': false,
      'delete_purchases': false,
      'delete_orders': false,
      'statistics': false,
      'isBlocked': false,
      'view_suppliers': false,
    };
    defaults.forEach((key, value) {
      if (!perms.containsKey(key)) perms[key] = value;
    });
  }

  Future<void> _updatePermission(String key, bool val) async {
    setState(() {
      perms[key] = val;
    });
    await widget.db.updateEmployeePermissions(
      widget.worker['uid'],
      jsonEncode(perms),
    );

    // Update Firebase immediately for instant blocking/unblocking
    if (key == 'isBlocked') {
      try {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(widget.worker['uid'])
            .update({'isBlocked': val});
      } catch (e) {
        debugPrint('Error updating isBlocked in Firebase: $e');
      }
    }
  }

  /// ─── حوار تعديل بيانات العامل ────────────────────────────────────────────
  Future<void> _showEditDialog() async {
    final nameCtrl    = TextEditingController(text: widget.worker['name']     ?? '');
    final emailCtrl   = TextEditingController(text: widget.worker['email']    ?? '');
    final phoneCtrl   = TextEditingController(text: widget.worker['phone']    ?? '');
    final roleCtrl    = TextEditingController(text: widget.worker['job_role'] ?? '');
    final addressCtrl = TextEditingController(text: widget.worker['address']  ?? '');
    final formKey = GlobalKey<FormState>();

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const CircleAvatar(
              backgroundColor: Color(0xFF2563EB),
              radius: 18,
              child: Icon(Icons.edit, color: Colors.white, size: 18),
            ),
            const SizedBox(width: 10),
            const Text(
              'تعديل بيانات العامل',
              style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // الاسم
                TextFormField(
                  controller: nameCtrl,
                  decoration: InputDecoration(
                    labelText: 'الاسم الكامل',
                    prefixIcon: const Icon(Icons.person_outline),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    filled: true,
                  ),
                  textDirection: TextDirection.rtl,
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'الاسم مطلوب' : null,
                ),
                const SizedBox(height: 12),
                // البريد الإلكتروني
                TextFormField(
                  controller: emailCtrl,
                  decoration: InputDecoration(
                    labelText: 'البريد الإلكتروني',
                    prefixIcon: const Icon(Icons.email_outlined),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    filled: true,
                  ),
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: 12),
                // رقم الهاتف
                TextFormField(
                  controller: phoneCtrl,
                  decoration: InputDecoration(
                    labelText: 'رقم الهاتف (واتساب)',
                    prefixIcon: const Icon(Icons.phone_outlined),
                    hintText: '0555 123 456 أو +213555123456',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    filled: true,
                  ),
                  keyboardType: TextInputType.phone,
                ),
                const SizedBox(height: 12),
                // المنصب
                TextFormField(
                  controller: roleCtrl,
                  decoration: InputDecoration(
                    labelText: 'المنصب / الدور',
                    prefixIcon: const Icon(Icons.work_outline),
                    hintText: 'مثال: نجار، مركّب، مندوب...',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    filled: true,
                  ),
                  textDirection: TextDirection.rtl,
                ),
                const SizedBox(height: 12),
                // العنوان
                TextFormField(
                  controller: addressCtrl,
                  decoration: InputDecoration(
                    labelText: 'العنوان',
                    prefixIcon: const Icon(Icons.location_on_outlined),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    filled: true,
                  ),
                  textDirection: TextDirection.rtl,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء', style: TextStyle(fontFamily: 'Cairo')),
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.save_rounded, size: 18),
            label: const Text('حفظ', style: TextStyle(fontFamily: 'Cairo')),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2563EB),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.pop(ctx, true);
              }
            },
          ),
        ],
      ),
    );

    if (saved == true && mounted) {
      final uid = widget.worker['uid'].toString();
      final name = nameCtrl.text.trim();
      final email = emailCtrl.text.trim();
      final phone = phoneCtrl.text.trim();
      final address = addressCtrl.text.trim();
      final jobRole = roleCtrl.text.trim();

      await widget.db.updateEmployeeFullInfo(
        uid,
        name:    name,
        email:   email,
        phone:   phone,
        address: address,
        jobRole: jobRole,
      );

      // Update Firestore immediately to prevent revert on sync
      try {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .update({
          'name': name,
          'email': email,
          'phone': phone,
          'address': address,
          'job_role': jobRole,
        });
      } catch (e) {
        debugPrint('Error updating worker in Firestore: $e');
      }

      widget.onRefresh();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ تم تحديث بيانات العامل', style: TextStyle(fontFamily: 'Cairo')),
            backgroundColor: Colors.green,
          ),
        );
      }
    }
  }

  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    final phone = widget.worker['phone']?.toString() ?? '';
    final role  = widget.worker['job_role']?.toString() ?? '';
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Column(
        children: [
          // ── رأس البطاقة ──────────────────────────────────────────
          InkWell(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  // أيقونة العامل
                  GestureDetector(
                    onLongPress: _showEditDialog,
                    child: const CircleAvatar(
                      backgroundColor: Colors.blueGrey,
                      radius: 22,
                      child: Icon(Icons.person, color: Colors.white),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // اسم + بريد + هاتف + منصب
                  Expanded(
                    child: GestureDetector(
                      onLongPress: _showEditDialog,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.worker['name'] ?? widget.worker['email'] ?? '',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                          ),
                          Text(
                            widget.worker['email'] ?? '',
                            style: TextStyle(fontSize: 12, color: isDark ? Colors.grey[400] : Colors.grey[600]),
                          ),
                          if (phone.isNotEmpty)
                            Row(children: [
                              const Icon(Icons.phone, size: 12, color: Colors.green),
                              const SizedBox(width: 3),
                              Text(phone, style: const TextStyle(fontSize: 12, color: Colors.green)),
                            ]),
                          if (role.isNotEmpty)
                            Text(role, style: const TextStyle(fontSize: 11, color: Colors.blueGrey)),
                        ],
                      ),
                    ),
                  ),
                  // ── زر التعديل ─────────────────────────────────────
                  IconButton(
                    icon: const Icon(Icons.edit_outlined, color: Color(0xFF2563EB), size: 22),
                    tooltip: 'تعديل البيانات',
                    onPressed: _showEditDialog,
                  ),
                  // ── زر الحذف ───────────────────────────────────────
                  IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.red, size: 22),
                    tooltip: 'حذف العامل',
                    onPressed: widget.onDelete,
                  ),
                  // ── سهم التوسيع ────────────────────────────────────
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    color: Colors.grey,
                  ),
                ],
              ),
            ),
          ),
          // ── قسم الصلاحيات (قابل للإخفاء) ───────────────────────
          if (_expanded) ...[
            const Divider(height: 1),
            Container(
              color: Theme.of(context).brightness == Brightness.dark
                  ? Colors.red.withOpacity(0.15)
                  : Colors.red.shade50,
              child: SwitchListTile(
                title: const Text(
                  'حظر العامل من التطبيق نهائياً',
                  style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
                ),
                value: perms['isBlocked'] ?? false,
                activeThumbColor: Colors.red,
                onChanged: (val) => _updatePermission('isBlocked', val),
              ),
            ),
            const Divider(height: 1),
            SwitchListTile(
              title: const Text('رؤية الزبائن'),
              value: perms['view_clients'] ?? false,
              onChanged: (val) => _updatePermission('view_clients', val),
            ),
            SwitchListTile(
              title: const Text('إنشاء الزبائن'),
              value: perms['create_clients'] ?? false,
              onChanged: (val) => _updatePermission('create_clients', val),
            ),
            SwitchListTile(
              title: const Text('رؤية الطلبيات (Commandes)'),
              value: perms['view_orders'] ?? false,
              onChanged: (val) => _updatePermission('view_orders', val),
            ),
            SwitchListTile(
              title: const Text('إنشاء طلبيات'),
              value: perms['create_orders'] ?? false,
              onChanged: (val) => _updatePermission('create_orders', val),
            ),
            SwitchListTile(
              title: const Text('رؤية تفاصيل الزبون'),
              value: perms['view_client_details'] ?? false,
              onChanged: (val) => _updatePermission('view_client_details', val),
            ),
            SwitchListTile(
              title: const Text('رؤية تفاصيل الطلبية'),
              value: perms['view_order_details'] ?? false,
              onChanged: (val) => _updatePermission('view_order_details', val),
            ),
            SwitchListTile(
              title: const Text('تغيير الأسعار (في الإعدادات)'),
              value: perms['change_prices'] ?? false,
              onChanged: (val) => _updatePermission('change_prices', val),
            ),
            SwitchListTile(
              title: const Text('التعامل مع الصندوق (الخزينة)'),
              value: perms['treasury'] ?? false,
              onChanged: (val) => _updatePermission('treasury', val),
            ),
            SwitchListTile(
              title: const Text('إدارة العمال والصلاحيات'),
              value: perms['manage_workers'] ?? false,
              onChanged: (val) => _updatePermission('manage_workers', val),
            ),
            SwitchListTile(
              title: const Text('رؤية المشتريات'),
              value: perms['purchases'] ?? false,
              onChanged: (val) => _updatePermission('purchases', val),
            ),
            SwitchListTile(
              title: const Text('إضافة فواتير مشتريات'),
              value: perms['add_purchases'] ?? false,
              onChanged: (val) => _updatePermission('add_purchases', val),
            ),
            SwitchListTile(
              title: const Text('تعديل الفواتير'),
              value: perms['edit_purchases'] ?? false,
              onChanged: (val) => _updatePermission('edit_purchases', val),
            ),
            SwitchListTile(
              title: const Text('مسح الفواتير (الشراء)'),
              value: perms['delete_purchases'] ?? false,
              onChanged: (val) => _updatePermission('delete_purchases', val),
            ),
            SwitchListTile(
              title: const Text('حذف طلبيات البيع (Commandes)'),
              subtitle: const Text(
                'خطير: يسمح للعامل بحذف الطلبيات',
                style: TextStyle(color: Colors.orange, fontSize: 12),
              ),
              value: perms['delete_orders'] ?? false,
              onChanged: (val) => _updatePermission('delete_orders', val),
            ),
            SwitchListTile(
              title: const Text('إسراع الفواتير المؤكدة'),
              value: perms['accelerate_confirmed_invoices'] ?? false,
              onChanged: (val) =>
                  _updatePermission('accelerate_confirmed_invoices', val),
            ),
            SwitchListTile(
              title: const Text('دخول الإحصائيات'),
              value: perms['statistics'] ?? false,
              onChanged: (val) => _updatePermission('statistics', val),
            ),
            SwitchListTile(
              title: const Text('إدارة الموردين'),
              value: perms['view_suppliers'] ?? false,
              onChanged: (val) => _updatePermission('view_suppliers', val),
            ),
          ],
        ],
      ),
    );
  }
}

