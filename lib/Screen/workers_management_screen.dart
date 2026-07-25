import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../settings/app_settings.dart';
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

  /// هل المستخدم الحالي نائب مدير (عامل بصلاحية manage_workers) وليس المدير الأصلي؟
  bool get _isDeputyManager {
    final settings = Provider.of<AppSettingsProvider>(context, listen: false);
    return !settings.isManager && settings.canManageWorkers();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final settings = Provider.of<AppSettingsProvider>(context);
    // إغلاق الصفحة فوراً إذا سُحبت صلاحية إدارة الفريق
    if (!settings.isManager && !settings.canManageWorkers()) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && Navigator.canPop(context)) Navigator.pop(context);
      });
    }
  }

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
        final prefs = await SharedPreferences.getInstance();
        final managerUid = (prefs.getString('workshop_code')?.isNotEmpty == true)
            ? prefs.getString('workshop_code')!
            : user.uid;

        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(managerUid)
            .get();
        if (doc.exists && doc.data() != null) {
          _joinCode = doc.data()!['joinCode'] ?? managerUid;
        } else {
          _joinCode = managerUid;
        }

        final managerInDb = data.where((w) => w['uid'] == managerUid).toList();
        for (var m in managerInDb) {
          await widget.db.deleteEmployee(m['uid']);
        }
        data.removeWhere((w) => w['uid'] == managerUid || w['uid'] == user.uid);
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

      final prefs = await SharedPreferences.getInstance();
      final targetWorkshopId = (prefs.getString('workshop_code')?.isNotEmpty == true)
          ? prefs.getString('workshop_code')!
          : user.uid;

      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .where('workshopId', isEqualTo: targetWorkshopId)
          .get();

      final existingWorkers = await widget.db.readEmployees();
      final existingUids = existingWorkers
          .map((w) => w['uid'].toString())
          .toSet();

      for (var doc in snapshot.docs) {
        if (doc.id == targetWorkshopId || doc.id == user.uid) continue; // Exclude manager & self

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
            // New worker found in cloud, preserve their cloud permissions if present, else use default
            String workerPermissionsJson;
            if (data['permissions_json'] is String && (data['permissions_json'] as String).isNotEmpty) {
              workerPermissionsJson = data['permissions_json'];
            } else if (data['permissions'] is Map) {
              workerPermissionsJson = jsonEncode(data['permissions']);
            } else {
              workerPermissionsJson = jsonEncode({
                'view_clients': true,
                'create_clients': false,
                'view_orders': true,
                'create_orders': false,
                'view_client_details': true,
                'view_order_details': true,
                'view_my_tasks': true,
                'view_my_accreditations': true,
                'isBlocked': false,
              });
            }

            await widget.db.insertEmployee(
              doc.id,
              data['email'] ?? 'No Email',
              (data['displayName'] as String?)?.trim().isNotEmpty == true
                  ? data['displayName'].toString().trim()
                  : (data['name'] as String?)?.trim().isNotEmpty == true
                      ? data['name'].toString().trim()
                      : 'عامل جديد',
              workerPermissionsJson,
            );
          }
        } else {
          // ✅ العامل موجود مسبقاً — نحدّث اسمه إذا كان "عامل جديد" أو فارغاً
          final cloudDisplayName = (data['displayName'] as String?)?.trim() ?? '';
          final cloudName = (data['name'] as String?)?.trim() ?? '';
          final resolvedName = cloudDisplayName.isNotEmpty
              ? cloudDisplayName
              : cloudName.isNotEmpty
                  ? cloudName
                  : '';
          if (resolvedName.isNotEmpty) {
            final existingWorker = existingWorkers.firstWhere(
              (w) => w['uid'].toString() == doc.id,
              orElse: () => {},
            );
            final currentName = (existingWorker['name'] ?? '').toString().trim();
            if (currentName.isEmpty || currentName == 'عامل جديد') {
              final dbInstance = await widget.db.db;
              await dbInstance?.update(
                'Employees',
                {'name': resolvedName},
                where: 'uid = ?',
                whereArgs: [doc.id],
              );
            }
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
    final isDeputy = _isDeputyManager;
    return Scaffold(
      appBar: AppBar(
        title: const Text('إدارة صلاحيات الفريق'),
        backgroundColor: Theme.of(context).brightness == Brightness.dark
            ? Theme.of(context).appBarTheme.backgroundColor
            : Colors.blue,
        actions: [
          IconButton(
            icon: const Icon(Icons.cloud_download),
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
                        isDeputyManager: isDeputy,
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
  /// إذا كان true، فالمستخدم الحالي نائب مدير (صلاحية محدودة)
  final bool isDeputyManager;

  const WorkerCard({
    super.key,
    required this.worker,
    required this.db,
    required this.onDelete,
    required this.onRefresh,
    this.isDeputyManager = false,
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
      'view_client_ledger': false,
      'create_clients': false,
      'edit_clients': false,
      'delete_clients': false,
      'view_orders': false,
      'view_projects': false,
      'distribution_tracking': false,
      'sales': false,
      'inventory': false,
      'global_consumption': false,
      'worker_finances': false,
      'worker_settlement': false,
      'create_orders': false,
      'edit_orders': false,
      'delete_orders': false,
      'view_client_details': false,
      'view_order_details': false,
      'view_order_documents': false,
      'fiche_de_coupe': false,
      'view_order_materials': false,
      'confirm_measurements': false,
      'measurements_card': false,
      'change_order_status': false,
      'pass_to_next_stage': false,
      'duplicate_orders': false,
      'view_my_tasks': false,
      'view_my_accreditations': false,
      'view_profiles': false,
      'view_glass': false,
      'view_shutters': false,
      'view_colors': false,
      'view_accessories': false,
      'view_series_accessories': false,
      'view_joints': false,
      'view_kit_bundles': false,
      'external_operations': false,
      'order_allocation': false,
      'settings': false,
      'select_systems': false,
      'change_prices': false,
      'treasury': false,
      'manage_workers': false,
      'edit_worker': false,
      'delete_worker': false,
      'purchases': false,
      'add_purchases': false,
      'edit_purchases': false,
      'delete_purchases': false,
      'statistics': false,
      'isBlocked': false,
      'view_suppliers': false,
      'full_manager_permissions': false,
      'co_manager': false,
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

    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.worker['uid'])
          .set({
            'isBlocked': perms['isBlocked'] ?? false,
            'permissions': perms,
            'permissions_json': jsonEncode(perms),
          }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Error updating permissions in Firebase: $e');
    }
  }

  /// 👑 منح أو إلغاء صلاحيات كمدير بالكامل لهذا الشخص
  Future<void> _toggleFullManagerPermissions(bool grant) async {
    final Map<String, dynamic> updatedPerms = Map<String, dynamic>.from(perms);

    updatedPerms['full_manager_permissions'] = grant;
    updatedPerms['co_manager'] = grant;

    if (grant) {
      updatedPerms.forEach((k, v) {
        if (k != 'isBlocked') {
          updatedPerms[k] = true;
        }
      });
    }

    setState(() {
      perms = updatedPerms;
    });

    final uid = widget.worker['uid'].toString();

    await widget.db.updateEmployeePermissions(uid, jsonEncode(updatedPerms));

    if (grant) {
      await widget.db.updateEmployeeFullInfo(
        uid,
        name: widget.worker['name']?.toString() ?? '',
        email: widget.worker['email']?.toString() ?? '',
        phone: widget.worker['phone']?.toString() ?? '',
        address: widget.worker['address']?.toString() ?? '',
        jobRole: 'نائب مدير (صلاحيات كاملة)',
      );
    }

    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'role': grant ? 'co_manager' : 'worker',
        'permissions': updatedPerms,
        'permissions_json': jsonEncode(updatedPerms),
        if (grant) 'job_role': 'نائب مدير (صلاحيات كاملة)',
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Error updating co_manager in Firebase: $e');
    }

    widget.onRefresh();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            grant
                ? '✅ تم إعطاء مهام وصلاحيات المدير بالكامل لهذا الشخص 👑'
                : 'ℹ️ تم إلغاء صلاحيات المدير وإعادة الحساب كعامل عادي',
            style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold),
          ),
          backgroundColor: grant ? Colors.green : Colors.orange,
        ),
      );
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

  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final phone = widget.worker['phone']?.toString() ?? '';
    final role  = widget.worker['job_role']?.toString() ?? '';
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final blueDivider = Divider(
      height: 1,
      color: isDark
          ? const Color(0xFF3B82F6).withValues(alpha: 0.4)
          : const Color(0xFF2563EB).withValues(alpha: 0.3),
    );

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
                            widget.worker['name'] ?? 'بدون اسم',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              fontFamily: 'Cairo',
                            ),
                          ),
                          if (phone.isNotEmpty)
                            Text(
                              phone,
                              style: TextStyle(
                                fontSize: 12,
                                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                              ),
                            ),
                          if (role.isNotEmpty)
                            Text(
                              'المنصب: $role',
                              style: const TextStyle(
                                fontSize: 11,
                                color: Colors.blue,
                                fontWeight: FontWeight.w600,
                                fontFamily: 'Cairo',
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  // ── زر تعديل بيانات العامل ────────────────────────
                  // للمدير الأصلي دائما، أو للنائب إذا منحت صلاحية edit_worker
                  if (!widget.isDeputyManager || (perms['edit_worker'] ?? false))
                    IconButton(
                      icon: const Icon(Icons.edit_outlined, color: Colors.blue),
                      tooltip: 'تعديل بيانات العامل',
                      onPressed: _showEditDialog,
                    ),
                  // ── زر طي / سدل القائمة ────────────────────────────
                  IconButton(
                    icon: Icon(
                      _expanded
                          ? Icons.keyboard_arrow_up
                          : Icons.keyboard_arrow_down,
                    ),
                    onPressed: () => setState(() => _expanded = !_expanded),
                  ),
                  // ── زر الحذف ───────────────────────────────────────
                  // للمدير الأصلي دائما، أو للنائب إذا منحت صلاحية delete_worker
                  if (!widget.isDeputyManager || (perms['delete_worker'] ?? false))
                    IconButton(
                      icon: const Icon(Icons.delete_outline, color: Colors.red),
                      onPressed: widget.onDelete,
                    ),
                ],
              ),
            ),
          ),
          // ── قسم الصلاحيات (قابل للإخفاء) ───────────────────────
          if (_expanded) ...[
            blueDivider,

            // 👑 بطاقة زر "إعطاء مهام نفس مهام المدير"
            Builder(
              builder: (ctx) {
                final bool isFullManager = (perms['full_manager_permissions'] == true) || (perms['co_manager'] == true);
                return Container(
                  margin: const EdgeInsets.all(10),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: isFullManager
                          ? [const Color(0xFF059669), const Color(0xFF10B981)]
                          : [const Color(0xFFD97706), const Color(0xFFF59E0B)],
                    ),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: (isFullManager ? Colors.green : Colors.amber).withValues(alpha: 0.35),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Icon(
                            isFullManager ? Icons.workspace_premium_rounded : Icons.admin_panel_settings_rounded,
                            color: Colors.white,
                            size: 32,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  isFullManager
                                      ? 'تم منح مهام نفس مهام المدير 👑'
                                      : 'إعطاء مهام نفس مهام المدير',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                    fontFamily: 'Cairo',
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  isFullManager
                                      ? 'هذا الشخص يستطيع الوصول لأي شيء في التطبيق مثله مثل المدير (بما فيها إضافة البروفايلات والسلاسل والمقاطع)'
                                      : 'اضغط هنا لتمكين الوصول الشامل لأي شيء في التطبيق مثله مثل المدير (حتى إضافة البروفايلات والسلاسل والمقاطع)',
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.9),
                                    fontSize: 11,
                                    fontFamily: 'Cairo',
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          icon: Icon(
                            isFullManager ? Icons.lock_reset_rounded : Icons.verified_user_rounded,
                            color: isFullManager ? Colors.red.shade700 : const Color(0xFFD97706),
                          ),
                          label: Text(
                            isFullManager ? 'إلغاء صلاحيات المدير (إعادة كعامل عادي)' : 'إعطاء مهام نفس مهام المدير 👑',
                            style: TextStyle(
                              fontFamily: 'Cairo',
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              color: isFullManager ? Colors.red.shade700 : const Color(0xFF78350F),
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: isFullManager ? Colors.red.shade700 : const Color(0xFF78350F),
                            elevation: 3,
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          onPressed: () => _toggleFullManagerPermissions(!isFullManager),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
            blueDivider,

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
            blueDivider,

            // 1️⃣ تصنيف صلاحيات الزبائن
            ExpansionTile(
              leading: const Icon(Icons.people_alt_rounded, color: Color(0xFF7C3AED)),
              title: const Text('صلاحيات الزبائن (Clients)', style: TextStyle(fontWeight: FontWeight.bold)),
              children: [
                SwitchListTile(
                  title: const Text('رؤية قائمة الزبائن'),
                  value: perms['view_clients'] ?? false,
                  onChanged: (val) => _updatePermission('view_clients', val),
                ),
                SwitchListTile(
                  title: const Text('رؤية كشف حساب الزبائن التفصيلي (Chrono)'),
                  value: perms['view_client_ledger'] ?? false,
                  onChanged: (val) => _updatePermission('view_client_ledger', val),
                ),
                SwitchListTile(
                  title: const Text('إنشاء زبون جديد'),
                  value: perms['create_clients'] ?? false,
                  onChanged: (val) => _updatePermission('create_clients', val),
                ),
                SwitchListTile(
                  title: const Text('تعديل بيانات الزبائن'),
                  value: perms['edit_clients'] ?? false,
                  onChanged: (val) => _updatePermission('edit_clients', val),
                ),
                SwitchListTile(
                  title: const Text('مسح / حذف الزبائن'),
                  value: perms['delete_clients'] ?? false,
                  onChanged: (val) => _updatePermission('delete_clients', val),
                ),
                SwitchListTile(
                  title: const Text('رؤية تفاصيل الزبون'),
                  value: perms['view_client_details'] ?? false,
                  onChanged: (val) => _updatePermission('view_client_details', val),
                ),
              ],
            ),
            blueDivider,

            // 2️⃣ تصنيف صلاحيات الطلبيات والمشاريع
            ExpansionTile(
              leading: const Icon(Icons.receipt_long_rounded, color: Color(0xFF2563EB)),
              title: const Text('صلاحيات الطلبيات والمشاريع (Commandes & Projets)', style: TextStyle(fontWeight: FontWeight.bold)),
              children: [
                SwitchListTile(
                  title: const Text('رؤية قائمة الطلبيات'),
                  value: perms['view_orders'] ?? false,
                  onChanged: (val) => _updatePermission('view_orders', val),
                ),
                SwitchListTile(
                  title: const Text('رؤية قائمة المشاريع (Projets)'),
                  value: perms['view_projects'] ?? false,
                  onChanged: (val) => _updatePermission('view_projects', val),
                ),
                SwitchListTile(
                  title: const Text('خطط التوزيع والتتبع'),
                  value: perms['distribution_tracking'] ?? false,
                  onChanged: (val) => _updatePermission('distribution_tracking', val),
                ),
                SwitchListTile(
                  title: const Text('رؤية سجل المبيعات (Vente)'),
                  value: perms['sales'] ?? false,
                  onChanged: (val) => _updatePermission('sales', val),
                ),
                SwitchListTile(
                  title: const Text('إنشاء طلبيات جديدة'),
                  value: perms['create_orders'] ?? false,
                  onChanged: (val) => _updatePermission('create_orders', val),
                ),
                SwitchListTile(
                  title: const Text('تعديل الطلبيات'),
                  value: perms['edit_orders'] ?? false,
                  onChanged: (val) => _updatePermission('edit_orders', val),
                ),
                SwitchListTile(
                  title: const Text('حذف الطلبيات'),
                  subtitle: const Text('خطير: يسمح للعامل بحذف الطلبيات', style: TextStyle(color: Colors.orange, fontSize: 11)),
                  value: perms['delete_orders'] ?? false,
                  onChanged: (val) => _updatePermission('delete_orders', val),
                ),
                SwitchListTile(
                  title: const Text('رؤية تفاصيل الطلبية وخياراتها'),
                  value: perms['view_order_details'] ?? false,
                  onChanged: (val) => _updatePermission('view_order_details', val),
                ),
                SwitchListTile(
                  title: const Text('رؤية وطباعة وثائق الطلبية (الفواتير، Devis...)'),
                  value: perms['view_order_documents'] ?? false,
                  onChanged: (val) => _updatePermission('view_order_documents', val),
                ),
                SwitchListTile(
                  title: const Text('استخراج ورقة التقطيع (Fiche de Coupe)'),
                  value: perms['fiche_de_coupe'] ?? false,
                  onChanged: (val) => _updatePermission('fiche_de_coupe', val),
                ),
                SwitchListTile(
                  title: const Text('رؤية سلع ومواد الطلبية وتقارير النواقص'),
                  value: perms['view_order_materials'] ?? false,
                  onChanged: (val) => _updatePermission('view_order_materials', val),
                ),
                SwitchListTile(
                  title: const Text('تغيير حالة الطلبية (يدوياً)'),
                  value: perms['change_order_status'] ?? false,
                  onChanged: (val) => _updatePermission('change_order_status', val),
                ),
                SwitchListTile(
                  title: const Text('النقل للمرحلة التالية (Passer à l\'étape suivante)'),
                  value: perms['pass_to_next_stage'] ?? false,
                  onChanged: (val) => _updatePermission('pass_to_next_stage', val),
                ),
                SwitchListTile(
                  title: const Text('تكرار / نسخ الطلبية (Duplicate)'),
                  value: perms['duplicate_orders'] ?? false,
                  onChanged: (val) => _updatePermission('duplicate_orders', val),
                ),
                SwitchListTile(
                  title: const Text('توزيع المهام وإسناد العمل للعمال'),
                  value: perms['order_allocation'] ?? false,
                  onChanged: (val) => _updatePermission('order_allocation', val),
                ),
              ],
            ),
            blueDivider,

            // 📐 بطاقة جديدة مستقلة: رفع القياسات الذكية (الموقع)
            ExpansionTile(
              leading: const Icon(Icons.architecture_rounded, color: Color(0xFF0EA5E9)),
              title: const Text('رفع القياسات الذكية (الموقع)', style: TextStyle(fontWeight: FontWeight.bold)),
              children: [
                SwitchListTile(
                  title: const Text('دخول بطاقة رفع القياسات الذكية (الموقع)'),
                  value: perms['measurements_card'] ?? false,
                  onChanged: (val) => _updatePermission('measurements_card', val),
                ),
                SwitchListTile(
                  title: const Text('تأكيد قياسات الموقع وتوليد ملصقات الباركود'),
                  value: perms['confirm_measurements'] ?? false,
                  onChanged: (val) => _updatePermission('confirm_measurements', val),
                ),
              ],
            ),
            blueDivider,

            // 3️⃣ تصنيف مهامي وتصنيع اعتماداتي والمهام الخارجية
            ExpansionTile(
              leading: const Icon(Icons.assignment_turned_in_rounded, color: Color(0xFF14B8A6)),
              title: const Text('مهامي وتصنيع اعتماداتي والمهام الخارجية', style: TextStyle(fontWeight: FontWeight.bold)),
              children: [
                SwitchListTile(
                  title: const Text('مهامي وتصنيعاتي (مهام العمل المسندة)'),
                  value: perms['view_my_tasks'] ?? false,
                  onChanged: (val) => _updatePermission('view_my_tasks', val),
                ),
                SwitchListTile(
                  title: const Text('تصنيع اعتماداتي (شاشة المنتجات والكتالوج)'),
                  value: perms['view_my_accreditations'] ?? false,
                  onChanged: (val) => _updatePermission('view_my_accreditations', val),
                ),
                // صلاحيات فرعية: تظهر فقط إذا كانت view_my_accreditations مفعّلة
                if (perms['view_my_accreditations'] ?? false) ...[
                  Padding(
                    padding: const EdgeInsets.only(right: 16),
                    child: Column(
                      children: [
                        SwitchListTile(
                          title: const Text('• البروفيلات والأنظمة'),
                          dense: true,
                          value: perms['view_profiles'] ?? false,
                          onChanged: (val) => _updatePermission('view_profiles', val),
                        ),
                        SwitchListTile(
                          title: const Text('• صفحة الزجاج'),
                          dense: true,
                          value: perms['view_glass'] ?? false,
                          onChanged: (val) => _updatePermission('view_glass', val),
                        ),
                        SwitchListTile(
                          title: const Text('• صفحة الستائر'),
                          dense: true,
                          value: perms['view_shutters'] ?? false,
                          onChanged: (val) => _updatePermission('view_shutters', val),
                        ),
                        SwitchListTile(
                          title: const Text('• صفحة الألوان'),
                          dense: true,
                          value: perms['view_colors'] ?? false,
                          onChanged: (val) => _updatePermission('view_colors', val),
                        ),
                        SwitchListTile(
                          title: const Text('• صفحة الإكسسوارات'),
                          dense: true,
                          value: perms['view_accessories'] ?? false,
                          onChanged: (val) => _updatePermission('view_accessories', val),
                        ),
                        SwitchListTile(
                          title: const Text('• إكسسوارات السلاسل'),
                          dense: true,
                          value: perms['view_series_accessories'] ?? false,
                          onChanged: (val) => _updatePermission('view_series_accessories', val),
                        ),
                        SwitchListTile(
                          title: const Text('• صفحة الجوانات'),
                          dense: true,
                          value: perms['view_joints'] ?? false,
                          onChanged: (val) => _updatePermission('view_joints', val),
                        ),
                        SwitchListTile(
                          title: const Text('• مجموعات الكيت (Kit)'),
                          dense: true,
                          value: perms['view_kit_bundles'] ?? false,
                          onChanged: (val) => _updatePermission('view_kit_bundles', val),
                        ),
                      ],
                    ),
                  ),
                ],
                SwitchListTile(
                  title: const Text('الأعمال والمهمات الخارجية (Opérations Externe)'),
                  value: perms['external_operations'] ?? false,
                  onChanged: (val) => _updatePermission('external_operations', val),
                ),
              ],
            ),
            blueDivider,

            // 🛡️ بطاقة جديدة مستقلة: إدارة صلاحيات الفريق (نائب المدير)
            ExpansionTile(
              leading: const Icon(Icons.admin_panel_settings_rounded, color: Color(0xFFD97706)),
              title: const Text('إدارة صلاحيات الفريق (نائب المدير)', style: TextStyle(fontWeight: FontWeight.bold)),
              children: [
                // صلاحية تفويض إدارة الفريق: يمنحها المدير الأصلي فقط
                if (!widget.isDeputyManager)
                  SwitchListTile(
                    title: const Text('تفويض إدارة صلاحيات الفريق (نائب المدير)'),
                    subtitle: const Text(
                      'يسمح لهذا العامل بإدارة صلاحيات بقية الفريق بدلاً من المدير',
                      style: TextStyle(fontSize: 11),
                    ),
                    value: perms['manage_workers'] ?? false,
                    onChanged: (val) => _updatePermission('manage_workers', val),
                  ),
                // صلاحية تعديل بيانات العامل
                if (!widget.isDeputyManager || (perms['manage_workers'] ?? false))
                  SwitchListTile(
                    title: const Text('تعديل بيانات العامل'),
                    subtitle: const Text(
                      'السماح بتعديل اسم العامل وبريده وهاتفه ومنصبه',
                      style: TextStyle(fontSize: 11),
                    ),
                    value: perms['edit_worker'] ?? false,
                    onChanged: (val) => _updatePermission('edit_worker', val),
                  ),
                // صلاحية حذف / طرد العامل
                if (!widget.isDeputyManager || (perms['manage_workers'] ?? false))
                  SwitchListTile(
                    title: const Text('حذف / طرد العامل من الورشة'),
                    subtitle: const Text(
                      'السماح بحذف العامل نهائياً من قائمة الفريق',
                      style: TextStyle(fontSize: 11),
                    ),
                    value: perms['delete_worker'] ?? false,
                    onChanged: (val) => _updatePermission('delete_worker', val),
                  ),
                // صلاحية النسخ الاحتياطي على السحابة
                SwitchListTile(
                  title: const Text('النسخ الاحتياطي على السحابة'),
                  subtitle: const Text(
                    'السماح برفع وحفظ نسخة احتياطية من الورشة للسحابة',
                    style: TextStyle(fontSize: 11),
                  ),
                  value: perms['cloud_backup'] ?? false,
                  onChanged: (val) => _updatePermission('cloud_backup', val),
                ),
                // صلاحية مزامنة واستيراد الكتالوج العالمي
                SwitchListTile(
                  title: const Text('مزامنة واستيراد الكتالوج العالمي'),
                  subtitle: const Text(
                    'السماح بمزامنة الأنظمة والكتالوج العالمي من السحابة',
                    style: TextStyle(fontSize: 11),
                  ),
                  value: perms['sync_global_catalog'] ?? false,
                  onChanged: (val) => _updatePermission('sync_global_catalog', val),
                ),
                // صلاحية النسخ الاحتياطي المحلي والتصدير كملف JSON
                SwitchListTile(
                  title: const Text('النسخ الاحتياطي المحلي (ملف JSON)'),
                  subtitle: const Text(
                    'السماح بتصدير واستيراد ملفات النسخ الاحتياطي بصيغة JSON على الهاتف',
                    style: TextStyle(fontSize: 11),
                  ),
                  value: perms['local_json_backup'] ?? false,
                  onChanged: (val) => _updatePermission('local_json_backup', val),
                ),
              ],
            ),
            blueDivider,

            // 4️⃣ تصنيف الإعدادات وأنظمة الورشة
            ExpansionTile(
              leading: const Icon(Icons.settings_rounded, color: Color(0xFF64748B)),
              title: const Text('الإعدادات وأنظمة الورشة (Paramètres & Systèmes)', style: TextStyle(fontWeight: FontWeight.bold)),
              children: [
                SwitchListTile(
                  title: const Text('الدخول لصفحة الإعدادات'),
                  value: perms['settings'] ?? false,
                  onChanged: (val) => _updatePermission('settings', val),
                ),
                SwitchListTile(
                  title: const Text('تحديد الأنظمة المستعملة بالورشة'),
                  value: perms['select_systems'] ?? false,
                  onChanged: (val) => _updatePermission('select_systems', val),
                ),
              ],
            ),
            blueDivider,

            // 5️⃣ تصنيف المالية والصناديق والأجور
            ExpansionTile(
              leading: const Icon(Icons.account_balance_wallet_rounded, color: Color(0xFF059669)),
              title: const Text('المالية والصناديق والأسعار والأجور (Trésorerie & Paie)', style: TextStyle(fontWeight: FontWeight.bold)),
              children: [
                SwitchListTile(
                  title: const Text('تغيير وتحديث الأسعار'),
                  value: perms['change_prices'] ?? false,
                  onChanged: (val) => _updatePermission('change_prices', val),
                ),
                SwitchListTile(
                  title: const Text('التعامل مع الصندوق (الخزينة)'),
                  value: perms['treasury'] ?? false,
                  onChanged: (val) => _updatePermission('treasury', val),
                ),
                SwitchListTile(
                  title: const Text('إدارة شؤون وأجور العمال'),
                  value: perms['worker_finances'] ?? false,
                  onChanged: (val) => _updatePermission('worker_finances', val),
                ),
                SwitchListTile(
                  title: const Text('المحاسبة الأسبوعية للعمال'),
                  value: perms['worker_settlement'] ?? false,
                  onChanged: (val) => _updatePermission('worker_settlement', val),
                ),
              ],
            ),
            blueDivider,

            // 6️⃣ تصنيف المخزون والمشتريات والموردين
            ExpansionTile(
              leading: const Icon(Icons.local_shipping_rounded, color: Color(0xFFE11D48)),
              title: const Text('المخزون والمشتريات والموردين (Stock, Achats & Fournisseurs)', style: TextStyle(fontWeight: FontWeight.bold)),
              children: [
                SwitchListTile(
                  title: const Text('دخول ورؤية وإدارة المخزون (Stock)'),
                  value: perms['inventory'] ?? false,
                  onChanged: (val) => _updatePermission('inventory', val),
                ),
                SwitchListTile(
                  title: const Text('إدارة ورؤية الموردين'),
                  value: perms['view_suppliers'] ?? false,
                  onChanged: (val) => _updatePermission('view_suppliers', val),
                ),
                SwitchListTile(
                  title: const Text('رؤية المشتريات'),
                  value: perms['purchases'] ?? false,
                  onChanged: (val) => _updatePermission('purchases', val),
                ),
                SwitchListTile(
                  title: const Text('إضافة فواتير مشتريات جديدة'),
                  value: perms['add_purchases'] ?? false,
                  onChanged: (val) => _updatePermission('add_purchases', val),
                ),
                SwitchListTile(
                  title: const Text('تعديل فواتير المشتريات'),
                  value: perms['edit_purchases'] ?? false,
                  onChanged: (val) => _updatePermission('edit_purchases', val),
                ),
                SwitchListTile(
                  title: const Text('مسح / حذف فواتير المشتريات'),
                  value: perms['delete_purchases'] ?? false,
                  onChanged: (val) => _updatePermission('delete_purchases', val),
                ),
                SwitchListTile(
                  title: const Text('تقرير النواقص والاستهلاك الشامل'),
                  value: perms['global_consumption'] ?? false,
                  onChanged: (val) => _updatePermission('global_consumption', val),
                ),
              ],
            ),
            blueDivider,

            // 7️⃣ تصنيف الإحصائيات والتقارير
            ExpansionTile(
              leading: const Icon(Icons.bar_chart_rounded, color: Color(0xFF06B6D4)),
              title: const Text('الإحصائيات والتقارير (Statistiques & Rapports)', style: TextStyle(fontWeight: FontWeight.bold)),
              children: [
                SwitchListTile(
                  title: const Text('دخول الإحصائيات والتقارير'),
                  value: perms['statistics'] ?? false,
                  onChanged: (val) => _updatePermission('statistics', val),
                ),
                SwitchListTile(
                  title: const Text('إسراع الفواتير المؤكدة'),
                  value: perms['accelerate_confirmed_invoices'] ?? false,
                  onChanged: (val) => _updatePermission('accelerate_confirmed_invoices', val),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

