import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../sql_database.dart';

class WorkersManagementScreen extends StatefulWidget {
  final SqlDatabase db;

  const WorkersManagementScreen({super.key, required this.db});

  @override
  State<WorkersManagementScreen> createState() => _WorkersManagementScreenState();
}

class _WorkersManagementScreenState extends State<WorkersManagementScreen> {
  List<Map<String, dynamic>> _workers = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadWorkers();
  }

  Future<void> _loadWorkers() async {
    setState(() => _isLoading = true);
    try {
      final data = await widget.db.readEmployees();
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
          .where('workshopCode', isEqualTo: user.uid)
          .get();

      final existingWorkers = await widget.db.readEmployees();
      final existingUids = existingWorkers.map((w) => w['uid'].toString()).toSet();

      for (var doc in snapshot.docs) {
        final data = doc.data();
        if (!existingUids.contains(doc.id)) {
          // New worker found in cloud
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
            'statistics': false,
            'isBlocked': false,
          });
          await widget.db.insertEmployee(
            doc.id,
            data['email'] ?? 'No Email',
            data['name'] ?? 'عامل جديد',
            defaultPermissions,
          );
        }
      }

      await _loadWorkers();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تم مزامنة العمال بنجاح'), backgroundColor: Colors.green),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('خطأ في الاتصال بالسحابة'), backgroundColor: Colors.red),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final workshopCode = user?.uid ?? 'غير متوفر';

    return Scaffold(
      appBar: AppBar(
        title: Text('إدارة العمال والصلاحيات'),
        actions: [
          IconButton(
            icon: Icon(Icons.cloud_download),
            onPressed: _fetchWorkersFromCloud,
            tooltip: 'تحديث من السحابة',
          )
        ],
      ),
      body: Column(
        children: [
          Container(
            padding: EdgeInsets.all(16),
            color: Colors.blue.shade50,
            child: Row(
              children: [
                Icon(Icons.info_outline, color: Colors.blue),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'لكي ينضم إليك أي عامل، اطلب منه تحميل التطبيق والتسجيل كعامل، ثم إدخال "كود الورشة" الخاص بك:\n$workshopCode',
                    style: TextStyle(fontSize: 13),
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
                        onDelete: () async {
                          await widget.db.deleteEmployee(worker['uid']);
                          _loadWorkers();
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

  const WorkerCard({Key? key, required this.worker, required this.db, required this.onDelete}) : super(key: key);

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
        'view_clients': false, 'create_clients': false, 'view_orders': false, 'create_orders': false,
        'view_client_details': false, 'view_order_details': false, 'change_prices': false, 'treasury': false,
        'manage_workers': false, 'purchases': false, 'statistics': false, 'isBlocked': false,
    };
    defaults.forEach((key, value) {
      if (!perms.containsKey(key)) perms[key] = value;
    });
  }

  Future<void> _updatePermission(String key, bool val) async {
    setState(() {
      perms[key] = val;
    });
    await widget.db.updateEmployeePermissions(widget.worker['uid'], jsonEncode(perms));
    
    // Update Firebase immediately for instant blocking/unblocking
    if (key == 'isBlocked') {
      try {
        await FirebaseFirestore.instance.collection('users').doc(widget.worker['uid']).update({
          'isBlocked': val
        });
      } catch (e) {
        debugPrint('Error updating isBlocked in Firebase: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      child: ExpansionTile(
        initiallyExpanded: true,
        leading: const CircleAvatar(
          backgroundColor: Colors.blueGrey,
          child: Icon(Icons.person, color: Colors.white),
        ),
        title: Text(widget.worker['name'] ?? widget.worker['email']),
        subtitle: Text(widget.worker['email']),
        trailing: IconButton(
          icon: const Icon(Icons.delete, color: Colors.red),
          onPressed: widget.onDelete,
        ),
        children: [
          Container(
            color: Colors.red.shade50,
            child: SwitchListTile(
              title: const Text('حظر العامل من التطبيق نهائياً', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
              value: perms['isBlocked'] ?? false,
              activeThumbColor: Colors.red,
              onChanged: (val) => _updatePermission('isBlocked', val),
            ),
          ),
          const Divider(height: 1),
          SwitchListTile(title: const Text('رؤية الزبائن'), value: perms['view_clients'] ?? false, onChanged: (val) => _updatePermission('view_clients', val)),
          SwitchListTile(title: const Text('إنشاء الزبائن'), value: perms['create_clients'] ?? false, onChanged: (val) => _updatePermission('create_clients', val)),
          SwitchListTile(title: const Text('رؤية الطلبيات (Commandes)'), value: perms['view_orders'] ?? false, onChanged: (val) => _updatePermission('view_orders', val)),
          SwitchListTile(title: const Text('إنشاء طلبيات'), value: perms['create_orders'] ?? false, onChanged: (val) => _updatePermission('create_orders', val)),
          SwitchListTile(title: const Text('رؤية تفاصيل الزبون'), value: perms['view_client_details'] ?? false, onChanged: (val) => _updatePermission('view_client_details', val)),
          SwitchListTile(title: const Text('رؤية تفاصيل الطلبية'), value: perms['view_order_details'] ?? false, onChanged: (val) => _updatePermission('view_order_details', val)),
          SwitchListTile(title: const Text('تغيير الأسعار (في الإعدادات)'), value: perms['change_prices'] ?? false, onChanged: (val) => _updatePermission('change_prices', val)),
          SwitchListTile(title: const Text('التعامل مع الصندوق (الخزينة)'), value: perms['treasury'] ?? false, onChanged: (val) => _updatePermission('treasury', val)),
          SwitchListTile(title: const Text('إدارة العمال'), value: perms['manage_workers'] ?? false, onChanged: (val) => _updatePermission('manage_workers', val)),
          SwitchListTile(title: const Text('تسجيل المشتريات'), value: perms['purchases'] ?? false, onChanged: (val) => _updatePermission('purchases', val)),
          SwitchListTile(title: const Text('دخول الإحصائيات'), value: perms['statistics'] ?? false, onChanged: (val) => _updatePermission('statistics', val)),
        ],
      ),
    );
  }
}
