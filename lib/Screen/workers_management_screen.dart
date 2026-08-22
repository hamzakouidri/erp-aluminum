import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../settings/app_settings.dart';
import '../sql_database.dart';

String _tr(String ar, String fr, String en, AppLanguage lang) {
  if (lang == AppLanguage.french) return fr;
  if (lang == AppLanguage.english) return en;
  return ar;
}

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
      String? workshopId;

      // Remove manager if accidentally added to local DB
      if (user != null) {
        final prefs = await SharedPreferences.getInstance();
        final managerUid =
            (prefs.getString('workshop_code')?.isNotEmpty == true)
            ? prefs.getString('workshop_code')!
            : user.uid;
        workshopId = managerUid;

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
        return uid.startsWith('local_worker_') ||
            email.isEmpty ||
            email == 'no email' ||
            email == 'no_email';
      });

      if (workshopId != null && workshopId.isNotEmpty) {
        await _repairWorkerWorkshopLinks(data, workshopId);
      }

      setState(() {
        _workers = data;
      });
    } catch (e) {
      print('Error loading workers: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  /// Repairs older worker documents that were created without the manager's
  /// workshop id. Without this value a worker would upload to a private path
  /// instead of the shared workshop backup.
  Future<void> _repairWorkerWorkshopLinks(
    List<Map<String, dynamic>> workers,
    String workshopId,
  ) async {
    try {
      var batch = FirebaseFirestore.instance.batch();
      var count = 0;
      for (final worker in workers) {
        final uid = worker['uid']?.toString() ?? '';
        if (uid.isEmpty || uid.startsWith('local_worker_')) continue;
        batch.set(
          FirebaseFirestore.instance.collection('users').doc(uid),
          {'workshopId': workshopId},
          SetOptions(merge: true),
        );
        count++;
        if (count == 400) {
          await batch.commit();
          batch = FirebaseFirestore.instance.batch();
          count = 0;
        }
      }
      if (count > 0) await batch.commit();
    } catch (e) {
      debugPrint('Unable to repair worker workshop links: $e');
    }
  }

  Future<void> _fetchWorkersFromCloud() async {
    setState(() => _isLoading = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final prefs = await SharedPreferences.getInstance();
      final targetWorkshopId =
          (prefs.getString('workshop_code')?.isNotEmpty == true)
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
        if (doc.id == targetWorkshopId || doc.id == user.uid)
          continue; // Exclude manager & self

        final data = doc.data();
        if (!existingUids.contains(doc.id)) {
          final cloudEmail = (data['email'] ?? '')
              .toString()
              .trim()
              .toLowerCase();
          Map<String, dynamic>? matchingLocalWorker;
          if (cloudEmail.isNotEmpty && cloudEmail != 'no email') {
            for (var ew in existingWorkers) {
              final ewUid = ew['uid'].toString();
              final ewEmail = (ew['email'] ?? '')
                  .toString()
                  .trim()
                  .toLowerCase();
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
            if (data['permissions_json'] is String &&
                (data['permissions_json'] as String).isNotEmpty) {
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
          final cloudDisplayName =
              (data['displayName'] as String?)?.trim() ?? '';
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
            final currentName = (existingWorker['name'] ?? '')
                .toString()
                .trim();
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
        title: Text(
          _tr(
            'إدارة شؤون وأجور العمال',
            'Gestion du Personnel & Salaires',
            'Personnel & Payroll Management',
            Provider.of<AppSettingsProvider>(context).language,
          ),
          style: const TextStyle(
            fontFamily: 'Cairo',
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
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
                  Icon(
                    Icons.info_outline,
                    color: Theme.of(context).primaryColor,
                  ),
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
  static const _fullManagerJobRole = 'نائب مدير (صلاحيات كاملة)';

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
    perms = {};
    try {
      final rawPermissions = widget.worker['permissions_json'];
      if (rawPermissions is String && rawPermissions.isNotEmpty) {
        final decoded = jsonDecode(rawPermissions);
        if (decoded is Map) {
          perms = Map<String, dynamic>.from(decoded);
        }
      }
    } catch (e) {
      perms = {};
    }
    if (perms.isEmpty && widget.worker['permissions'] is Map) {
      perms = Map<String, dynamic>.from(widget.worker['permissions'] as Map);
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
      'view_all_worker_tasks': false,
      'view_all_tasks': false,
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
      'view_cost_price': false,
      'change_transaction_dates': false,
      'treasury': false,
      'manage_workers': false,
      'edit_worker': false,
      'delete_worker': false,
      'purchases': false,
      'add_purchases': false,
      'edit_purchases': false,
      'delete_purchases': false,
      'edit_payments': false,
      'delete_payments': false,
      'manage_caisses': false,
      'statistics': false,
      'accelerate_confirmed_invoices': false,
      'isBlocked': false,
      'view_suppliers': false,
      'cloud_backup': false,
      'sync_global_catalog': false,
      'local_json_backup': false,
      'full_manager_permissions': false,
      'co_manager': false,
    };
    defaults.forEach((key, value) {
      if (!perms.containsKey(key)) perms[key] = value;
    });
  }

  bool _isPermissionEnabled(dynamic value) {
    if (value == true || value == 1) return true;
    if (value is String) {
      final normalized = value.trim().toLowerCase();
      return normalized == 'true' || normalized == '1';
    }
    return false;
  }

  bool get _hasFullManagerPermissions =>
      _isPermissionEnabled(perms['full_manager_permissions']) ||
      _isPermissionEnabled(perms['co_manager']);

  Future<void> _updatePermission(String key, bool val) async {
    final workerUid = widget.worker['uid'].toString();
    final workerRef = FirebaseFirestore.instance
        .collection('users')
        .doc(workerUid);

    final previousPerms = Map<String, dynamic>.from(perms);
    final updatedPerms = Map<String, dynamic>.from(perms)..[key] = val;

    // A co-manager can be converted to a limited manager by turning off an
    // individual permission.  Keep their other selected permissions, but
    // remove the bypass that previously granted every page on Windows.
    if (!val &&
        key != 'full_manager_permissions' &&
        key != 'co_manager' &&
        _hasFullManagerPermissions) {
      updatedPerms['full_manager_permissions'] = false;
      updatedPerms['co_manager'] = false;
    }

    final prefs = await SharedPreferences.getInstance();
    final workshopId = prefs.getString('workshop_code') ?? '';
    setState(() {
      perms = updatedPerms;
    });

    try {
      await workerRef.set({
        'isBlocked': updatedPerms['isBlocked'] ?? false,
        'permissions': updatedPerms,
        'permissions_json': jsonEncode(updatedPerms),
        'permissions_updated_at': FieldValue.serverTimestamp(),
        if (workshopId.isNotEmpty) 'workshopId': workshopId,
      }, SetOptions(merge: true));
      await widget.db.updateEmployeePermissions(
        workerUid,
        jsonEncode(updatedPerms),
      );
    } catch (e) {
      debugPrint('Error updating permissions in Firebase: $e');
      if (mounted) {
        setState(() {
          perms = previousPerms;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تعذر حفظ الصلاحية في السحابة؛ لم يتم تغييرها.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// 👑 منح أو إلغاء صلاحيات كمدير بالكامل لهذا الشخص
  Future<void> _toggleFullManagerPermissions(bool grant) async {
    final previousPerms = Map<String, dynamic>.from(perms);
    final Map<String, dynamic> updatedPerms = Map<String, dynamic>.from(perms);

    updatedPerms['full_manager_permissions'] = grant;
    updatedPerms['co_manager'] = grant;

    if (grant) {
      updatedPerms.forEach((k, v) {
        if (k != 'isBlocked') {
          updatedPerms[k] = true;
        }
      });
    } else {
      // A demoted co-manager must not retain the individual permissions that
      // were enabled when full access was granted.
      updatedPerms.updateAll(
        (key, value) => key == 'isBlocked' ? value : false,
      );
    }

    setState(() {
      perms = updatedPerms;
    });

    final uid = widget.worker['uid'].toString();
    final prefs = await SharedPreferences.getInstance();
    final workshopId = prefs.getString('workshop_code') ?? '';
    final currentJobRole = widget.worker['job_role']?.toString().trim() ?? '';
    final nextJobRole = grant
        ? _fullManagerJobRole
        : (currentJobRole == _fullManagerJobRole ? '' : currentJobRole);

    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'role': grant ? 'co_manager' : 'worker',
        'permissions': updatedPerms,
        'permissions_json': jsonEncode(updatedPerms),
        'permissions_updated_at': FieldValue.serverTimestamp(),
        'job_role': nextJobRole,
        if (workshopId.isNotEmpty) 'workshopId': workshopId,
      }, SetOptions(merge: true));
      await widget.db.updateEmployeePermissions(uid, jsonEncode(updatedPerms));
      await widget.db.updateEmployeeFullInfo(
        uid,
        name: widget.worker['name']?.toString() ?? '',
        email: widget.worker['email']?.toString() ?? '',
        phone: widget.worker['phone']?.toString() ?? '',
        address: widget.worker['address']?.toString() ?? '',
        jobRole: nextJobRole,
      );
    } catch (e) {
      debugPrint('Error updating co_manager in Firebase: $e');
      if (mounted) {
        setState(() {
          perms = previousPerms;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'تعذر حفظ صلاحيات المدير في السحابة؛ لم يتم تغييرها.',
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    widget.onRefresh();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            grant
                ? '✅ تم إعطاء مهام وصلاحيات المدير بالكامل لهذا الشخص 👑'
                : 'ℹ️ تم إلغاء صلاحيات المدير وإعادة الحساب كعامل عادي',
            style: const TextStyle(
              fontFamily: 'Cairo',
              fontWeight: FontWeight.bold,
            ),
          ),
          backgroundColor: grant ? Colors.green : Colors.orange,
        ),
      );
    }
  }

  /// ─── حوار تعديل بيانات العامل ────────────────────────────────────────────
  Future<void> _showEditDialog() async {
    final nameCtrl = TextEditingController(text: widget.worker['name'] ?? '');
    final emailCtrl = TextEditingController(text: widget.worker['email'] ?? '');
    final phoneCtrl = TextEditingController(text: widget.worker['phone'] ?? '');
    final roleCtrl = TextEditingController(
      text: widget.worker['job_role'] ?? '',
    );
    final addressCtrl = TextEditingController(
      text: widget.worker['address'] ?? '',
    );
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
              style: TextStyle(
                fontFamily: 'Cairo',
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
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
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    filled: true,
                  ),
                  textDirection: TextDirection.rtl,
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'الاسم مطلوب' : null,
                ),
                const SizedBox(height: 12),
                // البريد الإلكتروني
                TextFormField(
                  controller: emailCtrl,
                  decoration: InputDecoration(
                    labelText: 'البريد الإلكتروني',
                    prefixIcon: const Icon(Icons.email_outlined),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
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
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
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
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
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
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
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
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
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
        name: name,
        email: email,
        phone: phone,
        address: address,
        jobRole: jobRole,
      );

      // Update Firestore immediately to prevent revert on sync
      try {
        await FirebaseFirestore.instance.collection('users').doc(uid).update({
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
            content: Text(
              '✅ تم تحديث بيانات العامل',
              style: TextStyle(fontFamily: 'Cairo'),
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    }
  }

  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<AppSettingsProvider>(context);
    final lang = settings.language;
    final phone = widget.worker['phone']?.toString() ?? '';
    final role = widget.worker['job_role']?.toString() ?? '';
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final blueDivider = Divider(
      height: 1,
      color: isDark
          ? const Color(0xFF3B82F6).withValues(alpha: 0.4)
          : const Color(0xFF2563EB).withValues(alpha: 0.3),
    );

    final titleStyle = TextStyle(
      fontWeight: FontWeight.bold,
      fontFamily: 'Cairo',
      color: isDark ? Colors.white : Colors.black87,
    );

    final switchTitleStyle = TextStyle(
      fontFamily: 'Cairo',
      color: isDark ? Colors.white : Colors.black87,
    );

    final switchSubTitleStyle = TextStyle(
      fontFamily: 'Cairo',
      fontSize: 11,
      color: isDark ? Colors.white70 : Colors.black54,
    );

    return Card(
      color: isDark ? const Color(0xFF1E293B) : Colors.white,
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isDark ? const Color(0xFF334155) : Colors.grey.shade200,
        ),
      ),
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
                    child: CircleAvatar(
                      backgroundColor: isDark
                          ? const Color(0xFF334155)
                          : Colors.blueGrey,
                      radius: 22,
                      child: const Icon(Icons.person, color: Colors.white),
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
                            widget.worker['name'] ??
                                _tr('بدون اسم', 'Sans nom', 'No name', lang),
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              fontFamily: 'Cairo',
                              color: isDark ? Colors.white : Colors.black87,
                            ),
                          ),
                          if (phone.isNotEmpty)
                            Text(
                              phone,
                              style: TextStyle(
                                fontSize: 12,
                                color: isDark
                                    ? Colors.white70
                                    : Colors.grey.shade600,
                              ),
                            ),
                          if (role.isNotEmpty)
                            Text(
                              '${_tr("المنصب:", "Poste:", "Role:", lang)} $role',
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
                  if (!widget.isDeputyManager ||
                      (perms['edit_worker'] ?? false))
                    IconButton(
                      icon: const Icon(Icons.edit_outlined, color: Colors.blue),
                      tooltip: _tr(
                        'تعديل بيانات العامل',
                        'Modifier l\'ouvrier',
                        'Edit worker data',
                        lang,
                      ),
                      onPressed: _showEditDialog,
                    ),
                  // ── زر طي / سدل القائمة ────────────────────────────
                  IconButton(
                    icon: Icon(
                      _expanded
                          ? Icons.keyboard_arrow_up
                          : Icons.keyboard_arrow_down,
                      color: isDark ? Colors.white70 : Colors.black54,
                    ),
                    onPressed: () => setState(() => _expanded = !_expanded),
                  ),
                  // ── زر الحذف ───────────────────────────────────────
                  if (!widget.isDeputyManager ||
                      (perms['delete_worker'] ?? false))
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
                final bool isFullManager = _hasFullManagerPermissions;
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
                        color: (isFullManager ? Colors.green : Colors.amber)
                            .withValues(alpha: 0.35),
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
                            isFullManager
                                ? Icons.workspace_premium_rounded
                                : Icons.admin_panel_settings_rounded,
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
                                      ? _tr(
                                          'تم منح مهام نفس مهام المدير 👑',
                                          'Permissions de Directeur Accordées 👑',
                                          'Full Manager Permissions Granted 👑',
                                          lang,
                                        )
                                      : _tr(
                                          'إعطاء مهام نفس مهام المدير 👑',
                                          'Accorder les permissions de directeur 👑',
                                          'Grant Full Manager Permissions 👑',
                                          lang,
                                        ),
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
                                      ? _tr(
                                          'هذا الشخص يستطيع الوصول لأي شيء في التطبيق مثله مثل المدير (بما فيها إضافة البروفايلات والسلاسل والمقاطع)',
                                          'Cet utilisateur a accès à toutes les fonctionnalités de l\'application comme le directeur',
                                          'This user has full access to all app features like the manager',
                                          lang,
                                        )
                                      : _tr(
                                          'اضغط هنا لتمكين الوصول الشامل لأي شيء في التطبيق مثله مثل المدير (حتى إضافة البروفايلات والسلاسل والمقاطع)',
                                          'Appuyez pour accorder l\'accès complet à toutes les fonctionnalités comme le directeur',
                                          'Tap here to grant full access to all app features like the manager',
                                          lang,
                                        ),
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
                            isFullManager
                                ? Icons.lock_reset_rounded
                                : Icons.verified_user_rounded,
                            color: isFullManager
                                ? Colors.red.shade700
                                : const Color(0xFFD97706),
                          ),
                          label: Text(
                            isFullManager
                                ? _tr(
                                    'إلغاء صلاحيات المدير (إعادة كعامل عادي)',
                                    'Révoquer l\'accès de directeur',
                                    'Revoke Manager Access',
                                    lang,
                                  )
                                : _tr(
                                    'إعطاء مهام نفس مهام المدير 👑',
                                    'Accorder les accès de directeur 👑',
                                    'Grant Manager Access 👑',
                                    lang,
                                  ),
                            style: TextStyle(
                              fontFamily: 'Cairo',
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              color: isFullManager
                                  ? Colors.red.shade700
                                  : const Color(0xFF78350F),
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: isFullManager
                                ? Colors.red.shade700
                                : const Color(0xFF78350F),
                            elevation: 3,
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          onPressed: () =>
                              _toggleFullManagerPermissions(!isFullManager),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
            blueDivider,

            Container(
              color: isDark ? Colors.red.withOpacity(0.15) : Colors.red.shade50,
              child: SwitchListTile(
                title: Text(
                  _tr(
                    'حظر العامل من التطبيق نهائياً',
                    'Bloquer l\'accès de l\'ouvrier',
                    'Block worker from app',
                    lang,
                  ),
                  style: const TextStyle(
                    color: Colors.red,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Cairo',
                  ),
                ),
                value: perms['isBlocked'] ?? false,
                activeThumbColor: Colors.red,
                onChanged: (val) => _updatePermission('isBlocked', val),
              ),
            ),
            blueDivider,

            // 1️⃣ تصنيف صلاحيات الزبائن
            ExpansionTile(
              leading: const Icon(
                Icons.people_alt_rounded,
                color: Color(0xFF7C3AED),
              ),
              title: Text(
                _tr(
                  'صلاحيات الزبائن (Clients)',
                  'Permissions Clients',
                  'Client Permissions',
                  lang,
                ),
                style: titleStyle,
              ),
              children: [
                SwitchListTile(
                  title: Text(
                    _tr(
                      'رؤية قائمة الزبائن',
                      'Voir la liste des clients',
                      'View clients list',
                      lang,
                    ),
                    style: switchTitleStyle,
                  ),
                  value: perms['view_clients'] ?? false,
                  onChanged: (val) => _updatePermission('view_clients', val),
                ),
                SwitchListTile(
                  title: Text(
                    _tr(
                      'رؤية كشف حساب الزبائن التفصيلي (Chrono)',
                      'Voir le relevé de compte (Chrono)',
                      'View detailed client ledger',
                      lang,
                    ),
                    style: switchTitleStyle,
                  ),
                  value: perms['view_client_ledger'] ?? false,
                  onChanged: (val) =>
                      _updatePermission('view_client_ledger', val),
                ),
                SwitchListTile(
                  title: Text(
                    _tr(
                      'إنشاء زبون جديد',
                      'Créer un nouveau client',
                      'Create new client',
                      lang,
                    ),
                    style: switchTitleStyle,
                  ),
                  value: perms['create_clients'] ?? false,
                  onChanged: (val) => _updatePermission('create_clients', val),
                ),
                SwitchListTile(
                  title: Text(
                    _tr(
                      'تعديل بيانات الزبائن',
                      'Modifier les données des clients',
                      'Edit clients data',
                      lang,
                    ),
                    style: switchTitleStyle,
                  ),
                  value: perms['edit_clients'] ?? false,
                  onChanged: (val) => _updatePermission('edit_clients', val),
                ),
                SwitchListTile(
                  title: Text(
                    _tr(
                      'مسح / حذف الزبائن',
                      'Supprimer les clients',
                      'Delete clients',
                      lang,
                    ),
                    style: switchTitleStyle,
                  ),
                  value: perms['delete_clients'] ?? false,
                  onChanged: (val) => _updatePermission('delete_clients', val),
                ),
                SwitchListTile(
                  title: Text(
                    _tr(
                      'رؤية تفاصيل الزبون',
                      'Voir les détails du client',
                      'View client details',
                      lang,
                    ),
                    style: switchTitleStyle,
                  ),
                  value: perms['view_client_details'] ?? false,
                  onChanged: (val) =>
                      _updatePermission('view_client_details', val),
                ),
              ],
            ),
            blueDivider,

            // 2️⃣ تصنيف صلاحيات الطلبيات والمشاريع
            ExpansionTile(
              leading: const Icon(
                Icons.receipt_long_rounded,
                color: Color(0xFF2563EB),
              ),
              title: Text(
                _tr(
                  'صلاحيات الطلبيات والمشاريع (Commandes & Projets)',
                  'Commandes & Projets',
                  'Orders & Projects Permissions',
                  lang,
                ),
                style: titleStyle,
              ),
              children: [
                SwitchListTile(
                  title: Text(
                    _tr(
                      'رؤية قائمة الطلبيات',
                      'Voir la liste des commandes',
                      'View orders list',
                      lang,
                    ),
                    style: switchTitleStyle,
                  ),
                  value: perms['view_orders'] ?? false,
                  onChanged: (val) => _updatePermission('view_orders', val),
                ),
                SwitchListTile(
                  title: Text(
                    _tr(
                      'رؤية قائمة المشاريع (Projets)',
                      'Voir les projets',
                      'View projects list',
                      lang,
                    ),
                    style: switchTitleStyle,
                  ),
                  value: perms['view_projects'] ?? false,
                  onChanged: (val) => _updatePermission('view_projects', val),
                ),
                SwitchListTile(
                  title: Text(
                    _tr(
                      'خطط التوزيع والتتبع',
                      'Suivi de distribution',
                      'Distribution tracking',
                      lang,
                    ),
                    style: switchTitleStyle,
                  ),
                  value: perms['distribution_tracking'] ?? false,
                  onChanged: (val) =>
                      _updatePermission('distribution_tracking', val),
                ),
                SwitchListTile(
                  title: Text(
                    _tr(
                      'رؤية سجل المبيعات (Vente)',
                      'Historique des ventes',
                      'Sales history',
                      lang,
                    ),
                    style: switchTitleStyle,
                  ),
                  value: perms['sales'] ?? false,
                  onChanged: (val) => _updatePermission('sales', val),
                ),
                SwitchListTile(
                  title: Text(
                    _tr(
                      'إنشاء طلبيات جديدة',
                      'Créer de nouvelles commandes',
                      'Create new orders',
                      lang,
                    ),
                    style: switchTitleStyle,
                  ),
                  value: perms['create_orders'] ?? false,
                  onChanged: (val) => _updatePermission('create_orders', val),
                ),
                SwitchListTile(
                  title: Text(
                    _tr(
                      'تعديل الطلبيات',
                      'Modifier les commandes',
                      'Edit orders',
                      lang,
                    ),
                    style: switchTitleStyle,
                  ),
                  value: perms['edit_orders'] ?? false,
                  onChanged: (val) => _updatePermission('edit_orders', val),
                ),
                SwitchListTile(
                  title: Text(
                    _tr(
                      'حذف الطلبيات',
                      'Supprimer les commandes',
                      'Delete orders',
                      lang,
                    ),
                    style: switchTitleStyle,
                  ),
                  subtitle: Text(
                    _tr(
                      'خطير: يسمح للعامل بحذف الطلبيات',
                      'Attention: Autorise la suppression de commandes',
                      'Warning: Allows worker to delete orders',
                      lang,
                    ),
                    style: const TextStyle(
                      color: Colors.orange,
                      fontSize: 11,
                      fontFamily: 'Cairo',
                    ),
                  ),
                  value: perms['delete_orders'] ?? false,
                  onChanged: (val) => _updatePermission('delete_orders', val),
                ),
                SwitchListTile(
                  title: Text(
                    _tr(
                      'رؤية تفاصيل الطلبية وخياراتها',
                      'Voir les détails de la commande',
                      'View order details',
                      lang,
                    ),
                    style: switchTitleStyle,
                  ),
                  value: perms['view_order_details'] ?? false,
                  onChanged: (val) =>
                      _updatePermission('view_order_details', val),
                ),
                SwitchListTile(
                  title: Text(
                    _tr(
                      'رؤية وطباعة وثائق الطلبية (الفواتير، Devis...)',
                      'Documents de commande (Devis, Fiche)',
                      'View & print order documents & devis',
                      lang,
                    ),
                    style: switchTitleStyle,
                  ),
                  value: perms['view_order_documents'] ?? false,
                  onChanged: (val) =>
                      _updatePermission('view_order_documents', val),
                ),
                SwitchListTile(
                  title: Text(
                    _tr(
                      'استخراج ورقة التقطيع (Fiche de Coupe)',
                      'Fiche de coupe',
                      'Extract cutting sheet (Fiche de Coupe)',
                      lang,
                    ),
                    style: switchTitleStyle,
                  ),
                  value: perms['fiche_de_coupe'] ?? false,
                  onChanged: (val) => _updatePermission('fiche_de_coupe', val),
                ),
                SwitchListTile(
                  title: Text(
                    _tr(
                      'رؤية سلع ومواد الطلبية وتقارير النواقص',
                      'Matériaux & Manquants',
                      'View order materials & missing items',
                      lang,
                    ),
                    style: switchTitleStyle,
                  ),
                  value: perms['view_order_materials'] ?? false,
                  onChanged: (val) =>
                      _updatePermission('view_order_materials', val),
                ),
                SwitchListTile(
                  title: Text(
                    _tr(
                      'تغيير حالة الطلبية (يدوياً)',
                      'Changer le statut de la commande',
                      'Change order status manually',
                      lang,
                    ),
                    style: switchTitleStyle,
                  ),
                  value: perms['change_order_status'] ?? false,
                  onChanged: (val) =>
                      _updatePermission('change_order_status', val),
                ),
                SwitchListTile(
                  title: Text(
                    _tr(
                      'النقل للمرحلة التالية (Passer à l\'étape suivante)',
                      'Passer à l\'étape suivante',
                      'Pass to next stage',
                      lang,
                    ),
                    style: switchTitleStyle,
                  ),
                  value: perms['pass_to_next_stage'] ?? false,
                  onChanged: (val) =>
                      _updatePermission('pass_to_next_stage', val),
                ),
                SwitchListTile(
                  title: Text(
                    _tr(
                      'تكرار / نسخ الطلبية (Duplicate)',
                      'Dupliquer la commande',
                      'Duplicate order',
                      lang,
                    ),
                    style: switchTitleStyle,
                  ),
                  value: perms['duplicate_orders'] ?? false,
                  onChanged: (val) =>
                      _updatePermission('duplicate_orders', val),
                ),
                SwitchListTile(
                  title: Text(
                    _tr(
                      'توزيع المهام وإسناد العمل للعمال',
                      'Attribution des tâches aux ouvriers',
                      'Assign tasks to workers',
                      lang,
                    ),
                    style: switchTitleStyle,
                  ),
                  value: perms['order_allocation'] ?? false,
                  onChanged: (val) =>
                      _updatePermission('order_allocation', val),
                ),
                SwitchListTile(
                  title: Text(
                    _tr(
                      'رؤية جميع إسنادات ومهام العمال',
                      'Voir toutes les tâches de l\'atelier',
                      'View all worker assigned tasks',
                      lang,
                    ),
                    style: switchTitleStyle,
                  ),
                  subtitle: Text(
                    _tr(
                      'تسمح للمشرف أو نائب المدير بمتابعة وإدراج كل المهام المسندة لجميع عمال الورشة',
                      'Permet de voir toutes les tâches attribuées à l\'équipe',
                      'Allows supervisor/co-manager to monitor all assigned tasks',
                      lang,
                    ),
                    style: switchSubTitleStyle,
                  ),
                  value: perms['view_all_worker_tasks'] ?? false,
                  onChanged: (val) =>
                      _updatePermission('view_all_worker_tasks', val),
                ),
              ],
            ),
            blueDivider,

            // 📐 بطاقة قياسات الموقع الذكية
            ExpansionTile(
              leading: const Icon(
                Icons.architecture_rounded,
                color: Color(0xFF0EA5E9),
              ),
              title: Text(
                _tr(
                  'رفع القياسات الذكية (الموقع)',
                  'Prise de Mesures (Site)',
                  'Smart Site Measurements',
                  lang,
                ),
                style: titleStyle,
              ),
              children: [
                SwitchListTile(
                  title: Text(
                    _tr(
                      'دخول بطاقة رفع القياسات الذكية (الموقع)',
                      'Accès carte de mesure site',
                      'Access site measurements card',
                      lang,
                    ),
                    style: switchTitleStyle,
                  ),
                  value: perms['measurements_card'] ?? false,
                  onChanged: (val) =>
                      _updatePermission('measurements_card', val),
                ),
                SwitchListTile(
                  title: Text(
                    _tr(
                      'تأكيد قياسات الموقع وتوليد ملصقات الباركود',
                      'Confirmer les mesures & QR/Code-barres',
                      'Confirm site measurements & generate QR/Barcodes',
                      lang,
                    ),
                    style: switchTitleStyle,
                  ),
                  value: perms['confirm_measurements'] ?? false,
                  onChanged: (val) =>
                      _updatePermission('confirm_measurements', val),
                ),
              ],
            ),
            blueDivider,

            // 3️⃣ تصنيف مهامي وتصنيع اعتماداتي والمهام الخارجية
            ExpansionTile(
              leading: const Icon(
                Icons.assignment_turned_in_rounded,
                color: Color(0xFF14B8A6),
              ),
              title: Text(
                _tr(
                  'مهامي وتصنيع اعتماداتي والمهام الخارجية',
                  'Mes Tâches & Catalogue',
                  'My Tasks & Catalogue',
                  lang,
                ),
                style: titleStyle,
              ),
              children: [
                SwitchListTile(
                  title: Text(
                    _tr(
                      'مهامي وتصنيعاتي (مهام العمل المسندة)',
                      'Mes tâches attribuées',
                      'My assigned work tasks',
                      lang,
                    ),
                    style: switchTitleStyle,
                  ),
                  value: perms['view_my_tasks'] ?? false,
                  onChanged: (val) => _updatePermission('view_my_tasks', val),
                ),
                SwitchListTile(
                  title: Text(
                    _tr(
                      'تصنيع اعتماداتي (شاشة المنتجات والكتالوج)',
                      'Produits & Catalogue',
                      'Products & Catalogue screen',
                      lang,
                    ),
                    style: switchTitleStyle,
                  ),
                  value: perms['view_my_accreditations'] ?? false,
                  onChanged: (val) =>
                      _updatePermission('view_my_accreditations', val),
                ),
                if (perms['view_my_accreditations'] ?? false) ...[
                  Padding(
                    padding: const EdgeInsets.only(right: 16, left: 16),
                    child: Column(
                      children: [
                        SwitchListTile(
                          title: Text(
                            _tr(
                              '• البروفيلات والأنظمة',
                              '• Profilés & Systèmes',
                              '• Profiles & Systems',
                              lang,
                            ),
                            style: switchTitleStyle,
                          ),
                          dense: true,
                          value: perms['view_profiles'] ?? false,
                          onChanged: (val) =>
                              _updatePermission('view_profiles', val),
                        ),
                        SwitchListTile(
                          title: Text(
                            _tr(
                              '• صفحة الزجاج',
                              '• Verre',
                              '• Glass page',
                              lang,
                            ),
                            style: switchTitleStyle,
                          ),
                          dense: true,
                          value: perms['view_glass'] ?? false,
                          onChanged: (val) =>
                              _updatePermission('view_glass', val),
                        ),
                        SwitchListTile(
                          title: Text(
                            _tr(
                              '• صفحة الستائر',
                              '• Volets roulants',
                              '• Shutters page',
                              lang,
                            ),
                            style: switchTitleStyle,
                          ),
                          dense: true,
                          value: perms['view_shutters'] ?? false,
                          onChanged: (val) =>
                              _updatePermission('view_shutters', val),
                        ),
                        SwitchListTile(
                          title: Text(
                            _tr(
                              '• صفحة الألوان',
                              '• Couleurs',
                              '• Colors page',
                              lang,
                            ),
                            style: switchTitleStyle,
                          ),
                          dense: true,
                          value: perms['view_colors'] ?? false,
                          onChanged: (val) =>
                              _updatePermission('view_colors', val),
                        ),
                        SwitchListTile(
                          title: Text(
                            _tr(
                              '• صفحة الإكسسوارات',
                              '• Accessoires',
                              '• Accessories page',
                              lang,
                            ),
                            style: switchTitleStyle,
                          ),
                          dense: true,
                          value: perms['view_accessories'] ?? false,
                          onChanged: (val) =>
                              _updatePermission('view_accessories', val),
                        ),
                        SwitchListTile(
                          title: Text(
                            _tr(
                              '• إكسسوارات السلاسل',
                              '• Accessoires de séries',
                              '• Series accessories',
                              lang,
                            ),
                            style: switchTitleStyle,
                          ),
                          dense: true,
                          value: perms['view_series_accessories'] ?? false,
                          onChanged: (val) =>
                              _updatePermission('view_series_accessories', val),
                        ),
                        SwitchListTile(
                          title: Text(
                            _tr(
                              '• صفحة الجوانات',
                              '• Joints',
                              '• Joints page',
                              lang,
                            ),
                            style: switchTitleStyle,
                          ),
                          dense: true,
                          value: perms['view_joints'] ?? false,
                          onChanged: (val) =>
                              _updatePermission('view_joints', val),
                        ),
                        SwitchListTile(
                          title: Text(
                            _tr(
                              '• مجموعات الكيت (Kit)',
                              '• Kits & Bundles',
                              '• Kit bundles page',
                              lang,
                            ),
                            style: switchTitleStyle,
                          ),
                          dense: true,
                          value: perms['view_kit_bundles'] ?? false,
                          onChanged: (val) =>
                              _updatePermission('view_kit_bundles', val),
                        ),
                      ],
                    ),
                  ),
                ],
                SwitchListTile(
                  title: Text(
                    _tr(
                      'الأعمال والمهمات الخارجية (Opérations Externe)',
                      'Opérations Externe',
                      'External Operations',
                      lang,
                    ),
                    style: switchTitleStyle,
                  ),
                  value: perms['external_operations'] ?? false,
                  onChanged: (val) =>
                      _updatePermission('external_operations', val),
                ),
              ],
            ),
            blueDivider,

            // 🛡️ إدارة صلاحيات الفريق (نائب المدير)
            ExpansionTile(
              leading: const Icon(
                Icons.admin_panel_settings_rounded,
                color: Color(0xFFD97706),
              ),
              title: Text(
                _tr(
                  'إدارة صلاحيات الفريق (نائب المدير)',
                  'Gestion d\'Équipe (Co-Directeur)',
                  'Team Management (Co-Manager)',
                  lang,
                ),
                style: titleStyle,
              ),
              children: [
                if (!widget.isDeputyManager)
                  SwitchListTile(
                    title: Text(
                      _tr(
                        'تفويض إدارة صلاحيات الفريق (نائب المدير)',
                        'Délégation gestion d\'équipe',
                        'Delegate team management',
                        lang,
                      ),
                      style: switchTitleStyle,
                    ),
                    subtitle: Text(
                      _tr(
                        'يسمح لهذا العامل بإدارة صلاحيات بقية الفريق بدلاً من المدير',
                        'Permet d\'administrer les permissions de l\'équipe',
                        'Allows worker to manage team permissions',
                        lang,
                      ),
                      style: switchSubTitleStyle,
                    ),
                    value: perms['manage_workers'] ?? false,
                    onChanged: (val) =>
                        _updatePermission('manage_workers', val),
                  ),
                if (!widget.isDeputyManager ||
                    (perms['manage_workers'] ?? false))
                  SwitchListTile(
                    title: Text(
                      _tr(
                        'تعديل بيانات العامل',
                        'Modifier les données de l\'ouvrier',
                        'Edit worker data',
                        lang,
                      ),
                      style: switchTitleStyle,
                    ),
                    subtitle: Text(
                      _tr(
                        'السماح بتعديل اسم العامل وبريده وهاتفه ومنصبه',
                        'Autoriser la modification du profil',
                        'Allow editing worker profile & contact',
                        lang,
                      ),
                      style: switchSubTitleStyle,
                    ),
                    value: perms['edit_worker'] ?? false,
                    onChanged: (val) => _updatePermission('edit_worker', val),
                  ),
                if (!widget.isDeputyManager ||
                    (perms['manage_workers'] ?? false))
                  SwitchListTile(
                    title: Text(
                      _tr(
                        'حذف / طرد العامل من الورشة',
                        'Supprimer l\'ouvrier de l\'atelier',
                        'Delete worker from workshop',
                        lang,
                      ),
                      style: switchTitleStyle,
                    ),
                    subtitle: Text(
                      _tr(
                        'السماح بحذف العامل نهائياً من قائمة الفريق',
                        'Autoriser la suppression définitive de l\'ouvrier',
                        'Allow deleting worker from workshop',
                        lang,
                      ),
                      style: switchSubTitleStyle,
                    ),
                    value: perms['delete_worker'] ?? false,
                    onChanged: (val) => _updatePermission('delete_worker', val),
                  ),
                SwitchListTile(
                  title: Text(
                    _tr(
                      'النسخ الاحتياطي على السحابة',
                      'Sauvegarde cloud',
                      'Cloud backup',
                      lang,
                    ),
                    style: switchTitleStyle,
                  ),
                  subtitle: Text(
                    _tr(
                      'السماح برفع وحفظ نسخة احتياطية من الورشة للسحابة',
                      'Autoriser la sauvegarde de l\'atelier sur le cloud',
                      'Allow backing up workshop data to cloud',
                      lang,
                    ),
                    style: switchSubTitleStyle,
                  ),
                  value: perms['cloud_backup'] ?? false,
                  onChanged: (val) => _updatePermission('cloud_backup', val),
                ),
                SwitchListTile(
                  title: Text(
                    _tr(
                      'مزامنة واستيراد الكتالوج العالمي',
                      'Importer catalogue global',
                      'Import global catalog',
                      lang,
                    ),
                    style: switchTitleStyle,
                  ),
                  subtitle: Text(
                    _tr(
                      'السماح بمزامنة الأنظمة والكتالوج العالمي من السحابة',
                      'Autoriser la synchronisation du catalogue global',
                      'Allow syncing global systems catalog from cloud',
                      lang,
                    ),
                    style: switchSubTitleStyle,
                  ),
                  value: perms['sync_global_catalog'] ?? false,
                  onChanged: (val) =>
                      _updatePermission('sync_global_catalog', val),
                ),
                SwitchListTile(
                  title: Text(
                    _tr(
                      'النسخ الاحتياطي المحلي (ملف JSON)',
                      'Sauvegarde locale JSON',
                      'Local JSON backup',
                      lang,
                    ),
                    style: switchTitleStyle,
                  ),
                  subtitle: Text(
                    _tr(
                      'السماح بتصدير واستيراد ملفات النسخ الاحتياطي بصيغة JSON على الهاتف',
                      'Autoriser l\'importation/exportation de fichiers JSON',
                      'Allow importing/exporting JSON backup files',
                      lang,
                    ),
                    style: switchSubTitleStyle,
                  ),
                  value: perms['local_json_backup'] ?? false,
                  onChanged: (val) =>
                      _updatePermission('local_json_backup', val),
                ),
              ],
            ),
            blueDivider,

            // 4️⃣ تصنيف الإعدادات وأنظمة الورشة
            ExpansionTile(
              leading: const Icon(
                Icons.settings_rounded,
                color: Color(0xFF64748B),
              ),
              title: Text(
                _tr(
                  'الإعدادات وأنظمة الورشة (Paramètres & Systèmes)',
                  'Paramètres & Systèmes',
                  'Settings & Systems',
                  lang,
                ),
                style: titleStyle,
              ),
              children: [
                SwitchListTile(
                  title: Text(
                    _tr(
                      'الدخول لصفحة الإعدادات',
                      'Accès aux paramètres',
                      'Access settings page',
                      lang,
                    ),
                    style: switchTitleStyle,
                  ),
                  value: perms['settings'] ?? false,
                  onChanged: (val) => _updatePermission('settings', val),
                ),
                SwitchListTile(
                  title: Text(
                    _tr(
                      'تحديد الأنظمة المستعملة بالورشة',
                      'Sélection des systèmes de l\'atelier',
                      'Select active workshop systems',
                      lang,
                    ),
                    style: switchTitleStyle,
                  ),
                  value: perms['select_systems'] ?? false,
                  onChanged: (val) => _updatePermission('select_systems', val),
                ),
              ],
            ),
            blueDivider,

            // 5️⃣ تصنيف المالية والصناديق والأجور
            ExpansionTile(
              leading: const Icon(
                Icons.account_balance_wallet_rounded,
                color: Color(0xFF059669),
              ),
              title: Text(
                _tr(
                  'المالية والصناديق والأسعار والأجور (Trésorerie & Paie)',
                  'Trésorerie, Prix & Paie',
                  'Financials, Treasury & Wages',
                  lang,
                ),
                style: titleStyle,
              ),
              children: [
                SwitchListTile(
                  title: Text(
                    _tr(
                      'تغيير وتحديث الأسعار',
                      'Modifier et mettre à jour les prix',
                      'Change & update prices',
                      lang,
                    ),
                    style: switchTitleStyle,
                  ),
                  value: perms['change_prices'] ?? false,
                  onChanged: (val) => _updatePermission('change_prices', val),
                ),
                SwitchListTile(
                  title: Text(
                    _tr(
                      'رؤية سعر التكلفة',
                      'Voir le prix de revient',
                      'View cost price',
                      lang,
                    ),
                    style: switchTitleStyle,
                  ),
                  value: perms['view_cost_price'] ?? false,
                  onChanged: (val) => _updatePermission('view_cost_price', val),
                ),
                SwitchListTile(
                  title: Text(
                    _tr(
                      'تغيير تواريخ المعاملات (الصندوق والمالية)',
                      'Modifier la date des transactions (Trésorerie)',
                      'Change transaction dates (Treasury & Finances)',
                      lang,
                    ),
                    style: switchTitleStyle,
                  ),
                  subtitle: Text(
                    _tr(
                      'السماح للعامل بتغيير وتعديل تاريخ المعاملات والمدفوعات',
                      'Autoriser la modification de la date des opérations',
                      'Allows changing dates of financial transactions',
                      lang,
                    ),
                    style: switchSubTitleStyle,
                  ),
                  value: perms['change_transaction_dates'] ?? false,
                  onChanged: (val) =>
                      _updatePermission('change_transaction_dates', val),
                ),
                SwitchListTile(
                  title: Text(
                    _tr(
                      'التعامل مع الصندوق (الخزينة)',
                      'Accès à la trésorerie',
                      'Treasury access',
                      lang,
                    ),
                    style: switchTitleStyle,
                  ),
                  value: perms['treasury'] ?? false,
                  onChanged: (val) => _updatePermission('treasury', val),
                ),
                SwitchListTile(
                  title: Text(
                    _tr(
                      'إدارة الصناديق',
                      'Gérer les caisses',
                      'Manage cash boxes',
                      lang,
                    ),
                    style: switchTitleStyle,
                  ),
                  value: perms['manage_caisses'] ?? false,
                  onChanged: (val) => _updatePermission('manage_caisses', val),
                ),
                SwitchListTile(
                  title: Text(
                    _tr(
                      'تعديل المدفوعات والمعاملات',
                      'Modifier les paiements',
                      'Edit payments and transactions',
                      lang,
                    ),
                    style: switchTitleStyle,
                  ),
                  value: perms['edit_payments'] ?? false,
                  onChanged: (val) => _updatePermission('edit_payments', val),
                ),
                SwitchListTile(
                  title: Text(
                    _tr(
                      'حذف المدفوعات والمعاملات',
                      'Supprimer les paiements',
                      'Delete payments and transactions',
                      lang,
                    ),
                    style: switchTitleStyle,
                  ),
                  value: perms['delete_payments'] ?? false,
                  onChanged: (val) => _updatePermission('delete_payments', val),
                ),
                SwitchListTile(
                  title: Text(
                    _tr(
                      'إدارة شؤون وأجور العمال',
                      'Gestion des salaires des ouvriers',
                      'Worker finances & wages',
                      lang,
                    ),
                    style: switchTitleStyle,
                  ),
                  value: perms['worker_finances'] ?? false,
                  onChanged: (val) => _updatePermission('worker_finances', val),
                ),
                SwitchListTile(
                  title: Text(
                    _tr(
                      'المحاسبة الأسبوعية للعمال',
                      'Règlement hebdomadaire des ouvriers',
                      'Weekly worker settlement',
                      lang,
                    ),
                    style: switchTitleStyle,
                  ),
                  value: perms['worker_settlement'] ?? false,
                  onChanged: (val) =>
                      _updatePermission('worker_settlement', val),
                ),
              ],
            ),
            blueDivider,

            // 6️⃣ تصنيف المخزون والمشتريات والموردين
            ExpansionTile(
              leading: const Icon(
                Icons.local_shipping_rounded,
                color: Color(0xFFE11D48),
              ),
              title: Text(
                _tr(
                  'المخزون والمشتريات والموردين (Stock, Achats & Fournisseurs)',
                  'Stock, Achats & Fournisseurs',
                  'Inventory, Purchases & Suppliers',
                  lang,
                ),
                style: titleStyle,
              ),
              children: [
                SwitchListTile(
                  title: Text(
                    _tr(
                      'دخول ورؤية وإدارة المخزون (Stock)',
                      'Gestion du stock',
                      'Inventory stock management',
                      lang,
                    ),
                    style: switchTitleStyle,
                  ),
                  value: perms['inventory'] ?? false,
                  onChanged: (val) => _updatePermission('inventory', val),
                ),
                SwitchListTile(
                  title: Text(
                    _tr(
                      'إدارة ورؤية الموردين',
                      'Voir et gérer les fournisseurs',
                      'View & manage suppliers',
                      lang,
                    ),
                    style: switchTitleStyle,
                  ),
                  value: perms['view_suppliers'] ?? false,
                  onChanged: (val) => _updatePermission('view_suppliers', val),
                ),
                SwitchListTile(
                  title: Text(
                    _tr(
                      'رؤية المشتريات',
                      'Voir les achats',
                      'View purchases',
                      lang,
                    ),
                    style: switchTitleStyle,
                  ),
                  value: perms['purchases'] ?? false,
                  onChanged: (val) => _updatePermission('purchases', val),
                ),
                SwitchListTile(
                  title: Text(
                    _tr(
                      'إضافة فواتير مشتريات جديدة',
                      'Ajouter de nouvelles factures d\'achats',
                      'Add new purchase invoices',
                      lang,
                    ),
                    style: switchTitleStyle,
                  ),
                  value: perms['add_purchases'] ?? false,
                  onChanged: (val) => _updatePermission('add_purchases', val),
                ),
                SwitchListTile(
                  title: Text(
                    _tr(
                      'تعديل فواتير المشتريات',
                      'Modifier les factures d\'achats',
                      'Edit purchase invoices',
                      lang,
                    ),
                    style: switchTitleStyle,
                  ),
                  value: perms['edit_purchases'] ?? false,
                  onChanged: (val) => _updatePermission('edit_purchases', val),
                ),
                SwitchListTile(
                  title: Text(
                    _tr(
                      'مسح / حذف فواتير المشتريات',
                      'Supprimer les factures d\'achats',
                      'Delete purchase invoices',
                      lang,
                    ),
                    style: switchTitleStyle,
                  ),
                  value: perms['delete_purchases'] ?? false,
                  onChanged: (val) =>
                      _updatePermission('delete_purchases', val),
                ),
                SwitchListTile(
                  title: Text(
                    _tr(
                      'تقرير النواقص والاستهلاك الشامل',
                      'Rapport de consommation globale',
                      'Global consumption & missing report',
                      lang,
                    ),
                    style: switchTitleStyle,
                  ),
                  value: perms['global_consumption'] ?? false,
                  onChanged: (val) =>
                      _updatePermission('global_consumption', val),
                ),
              ],
            ),
            blueDivider,

            // 7️⃣ تصنيف الإحصائيات والتقارير
            ExpansionTile(
              leading: const Icon(
                Icons.bar_chart_rounded,
                color: Color(0xFF06B6D4),
              ),
              title: Text(
                _tr(
                  'الإحصائيات والتقارير (Statistiques & Rapports)',
                  'Statistiques & Rapports',
                  'Statistics & Reports',
                  lang,
                ),
                style: titleStyle,
              ),
              children: [
                SwitchListTile(
                  title: Text(
                    _tr(
                      'دخول الإحصائيات والتقارير',
                      'Accès aux statistiques',
                      'Access statistics & reports',
                      lang,
                    ),
                    style: switchTitleStyle,
                  ),
                  value: perms['statistics'] ?? false,
                  onChanged: (val) => _updatePermission('statistics', val),
                ),
                SwitchListTile(
                  title: Text(
                    _tr(
                      'إسراع الفواتير المؤكدة',
                      'Accélérer les factures confirmées',
                      'Accelerate confirmed invoices',
                      lang,
                    ),
                    style: switchTitleStyle,
                  ),
                  value: perms['accelerate_confirmed_invoices'] ?? false,
                  onChanged: (val) =>
                      _updatePermission('accelerate_confirmed_invoices', val),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
