import 'package:flutter/material.dart';
import '../sql_database.dart';
import 'package:provider/provider.dart';
import '../settings/app_settings.dart';
import 'dart:convert';

import 'dart:async';
import '../services/cloud_sync_service.dart';
import 'worker_transactions_detail_screen.dart';

class WorkerFinancesScreen extends StatefulWidget {
  final SqlDatabase db;
  /// وضع العرض فقط — يخفي أزرار التعديل والإضافة
  final bool readOnly;

  const WorkerFinancesScreen({super.key, required this.db, this.readOnly = false});

  @override
  State<WorkerFinancesScreen> createState() => _WorkerFinancesScreenState();
}

class _WorkerFinancesScreenState extends State<WorkerFinancesScreen> {
  List<Map<String, dynamic>> _workers = [];
  bool _isLoading = false;
  StreamSubscription? _syncSub;

  @override
  void initState() {
    super.initState();
    _loadData();
    _syncSub = CloudSyncService().dbUpdateStream.listen((_) {
      if (mounted) {
        _loadData(silent: true);
      }
    });
  }

  @override
  void dispose() {
    _syncSub?.cancel();
    super.dispose();
  }

  Future<void> _loadData({bool silent = false}) async {
    if (!silent && _workers.isEmpty) {
      setState(() => _isLoading = true);
    }
    final data = await widget.db.readEmployees();
    if (mounted) {
      setState(() {
        _workers = data;
        _isLoading = false;
      });
    }
  }

  void _showAddWorkerDialog() {
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final addressCtrl = TextEditingController();
    final jobRoleCtrl = TextEditingController();
    final salaryCtrl = TextEditingController();
    String salaryType = 'manual';

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) => AlertDialog(
          title: const Text(
            'إضافة عامل جديد',
            style: TextStyle(fontFamily: 'Cairo'),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'اسم العامل (إجباري)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: phoneCtrl,
                  decoration: const InputDecoration(
                    labelText: 'رقم الهاتف (اختياري)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: emailCtrl,
                  decoration: const InputDecoration(
                    labelText: 'البريد الإلكتروني (اختياري)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: addressCtrl,
                  decoration: const InputDecoration(
                    labelText: 'العنوان (اختياري)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: jobRoleCtrl,
                  decoration: const InputDecoration(
                    labelText: 'المنصب أو الاختصاص (اختياري)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  value: salaryType,
                  items: const [
                    DropdownMenuItem(
                      value: 'manual',
                      child: Text(
                        'سحب متفرق (بدون راتب ثابت)',
                        style: TextStyle(fontFamily: 'Cairo'),
                      ),
                    ),
                    DropdownMenuItem(
                      value: 'fixed',
                      child: Text(
                        'راتب شهري ثابت',
                        style: TextStyle(fontFamily: 'Cairo'),
                      ),
                    ),
                  ],
                  onChanged: (val) => setStateDialog(() => salaryType = val!),
                  decoration: const InputDecoration(
                    labelText: 'طريقة الدفع',
                    border: OutlineInputBorder(),
                  ),
                ),
                if (salaryType == 'fixed') ...[
                  const SizedBox(height: 10),
                  TextField(
                    controller: salaryCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'الراتب الشهري (د.ج)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (nameCtrl.text.isNotEmpty) {
                  final uid =
                      'local_worker_${DateTime.now().millisecondsSinceEpoch}';
                  final baseSalary = double.tryParse(salaryCtrl.text) ?? 0.0;

                  await widget.db.insertEmployee(
                    uid,
                    emailCtrl.text,
                    nameCtrl.text,
                    jsonEncode({}),
                    salaryType: salaryType,
                    baseSalary: baseSalary,
                    phone: phoneCtrl.text,
                    address: addressCtrl.text,
                    jobRole: jobRoleCtrl.text,
                  );
                  Navigator.pop(context);
                  _loadData();
                }
              },
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );
  }

  void _showEditWorkerDialog(Map<String, dynamic> worker) {
    final nameCtrl = TextEditingController(text: worker['name'] ?? '');
    final phoneCtrl = TextEditingController(text: worker['phone'] ?? '');
    final emailCtrl = TextEditingController(text: worker['email'] ?? '');
    final addressCtrl = TextEditingController(text: worker['address'] ?? '');
    final jobRoleCtrl = TextEditingController(text: worker['job_role'] ?? '');
    final salaryCtrl = TextEditingController(text: (worker['base_salary'] ?? 0.0).toString());
    String salaryType = worker['salary_type'] ?? 'manual';

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) => AlertDialog(
          title: const Text(
            'تعديل بيانات العامل',
            style: TextStyle(fontFamily: 'Cairo'),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'اسم العامل (إجباري)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: phoneCtrl,
                  decoration: const InputDecoration(
                    labelText: 'رقم الهاتف (اختياري)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: emailCtrl,
                  decoration: const InputDecoration(
                    labelText: 'البريد الإلكتروني (اختياري)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: addressCtrl,
                  decoration: const InputDecoration(
                    labelText: 'العنوان (اختياري)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: jobRoleCtrl,
                  decoration: const InputDecoration(
                    labelText: 'المنصب أو الاختصاص (اختياري)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  value: salaryType,
                  items: const [
                    DropdownMenuItem(
                      value: 'manual',
                      child: Text(
                        'سحب متفرق (بدون راتب ثابت)',
                        style: TextStyle(fontFamily: 'Cairo'),
                      ),
                    ),
                    DropdownMenuItem(
                      value: 'fixed',
                      child: Text(
                        'راتب شهري ثابت',
                        style: TextStyle(fontFamily: 'Cairo'),
                      ),
                    ),
                  ],
                  onChanged: (val) => setStateDialog(() => salaryType = val!),
                  decoration: const InputDecoration(
                    labelText: 'طريقة الدفع',
                    border: OutlineInputBorder(),
                  ),
                ),
                if (salaryType == 'fixed') ...[
                  const SizedBox(height: 10),
                  TextField(
                    controller: salaryCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'الراتب الشهري (د.ج)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (nameCtrl.text.isNotEmpty) {
                  final baseSalary = double.tryParse(salaryCtrl.text) ?? 0.0;

                  await widget.db.updateEmployeeFullInfo(
                    worker['uid'],
                    name: nameCtrl.text.trim(),
                    phone: phoneCtrl.text.trim(),
                    email: emailCtrl.text.trim(),
                    address: addressCtrl.text.trim(),
                    jobRole: jobRoleCtrl.text.trim(),
                    salaryType: salaryType,
                    baseSalary: baseSalary,
                  );
                  Navigator.pop(context);
                  _loadData();
                }
              },
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );
  }


  void _showAddTransactionDialog(Map<String, dynamic> worker) async {
    final amountCtrl = TextEditingController();
    final noteCtrl = TextEditingController();
    String type = 'advance'; // advance (سلفة) or salary (راتب)
    String paymentSource = 'الصندوق الرئيسي';
    List<String> caisseNames = ['الصندوق الرئيسي', 'الصندوق المفرد', 'الحساب البنكي / البنك', 'يدوي (بدون اقتطاع صندوق)'];

    try {
      final caissesData = await widget.db.readCaisses();
      final names = caissesData.map((c) => c['name']?.toString() ?? '').where((n) => n.isNotEmpty).toList();
      if (names.isNotEmpty) {
        caisseNames = [...names, 'الحساب البنكي / البنك', 'يدوي (بدون اقتطاع صندوق)'];
      }
    } catch (_) {}

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) => AlertDialog(
          title: Text(
            'تسجيل مال للعامل: ${worker['name']}',
            style: const TextStyle(fontFamily: 'Cairo'),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  value: type,
                  items: const [
                    DropdownMenuItem(
                      value: 'advance',
                      child: Text('سلفة (Advance)', style: TextStyle(fontFamily: 'Cairo')),
                    ),
                    DropdownMenuItem(
                      value: 'salary',
                      child: Text('أجرة (Salary)', style: TextStyle(fontFamily: 'Cairo')),
                    ),
                  ],
                  onChanged: (val) => setStateDialog(() => type = val!),
                  decoration: const InputDecoration(
                    labelText: 'نوع العملية',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                // ── اختيار الصندوق (Caisse) ────────────────────────────
                DropdownButtonFormField<String>(
                  value: paymentSource,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'مصدر الدفع / الصندوق',
                    border: OutlineInputBorder(),
                  ),
                  items: caisseNames
                      .map((c) => DropdownMenuItem(value: c, child: Text(c, overflow: TextOverflow.ellipsis)))
                      .toList(),
                  onChanged: (v) => setStateDialog(() => paymentSource = v!),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: amountCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'المبلغ (دج)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: noteCtrl,
                  decoration: const InputDecoration(
                    labelText: 'ملاحظة',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (amountCtrl.text.isNotEmpty) {
                  final rawText = amountCtrl.text
                      .replaceAll('،', '')
                      .replaceAll(',', '')
                      .replaceAll(' ', '')
                      .replaceAll('\u00a0', '');
                  final amount = double.tryParse(rawText) ?? 0.0;
                  final settings = Provider.of<AppSettingsProvider>(context, listen: false);
                  final workerName = worker['name']?.toString() ?? '';
                  final empId = worker['id'] as int? ?? 0;

                  // 1. Record in worker's account
                  await widget.db.insertWorkerTransaction(
                    worker['uid'],
                    amount,
                    type,
                    noteCtrl.text.isNotEmpty ? noteCtrl.text : (type == 'advance' ? 'سلفة مالية' : 'دفعة أجر'),
                    recordedBy: settings.userDisplayName,
                    caisseName: paymentSource,
                  );

                  // 2. If source is a real caisse, record Décaissement in Treasury
                  if (!paymentSource.contains('يدوي')) {
                    await widget.db.insertTreasury(
                      'Décaissement',
                      amount,
                      'إلى العامل: $workerName - ${type == 'advance' ? 'سلفة' : 'دفعة أجر'} (${noteCtrl.text.isNotEmpty ? noteCtrl.text : 'بدون ملاحظات'})',
                      entityType: 'Worker',
                      entityId: empId,
                      caisseName: paymentSource,
                      recordedBy: settings.userDisplayName,
                    );
                  }

                  Navigator.pop(context);
                  if (mounted) {
                    _loadData();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('تم تسجيل العملية بنجاح وخصمها من الصندوق'),
                        backgroundColor: Colors.green,
                      ),
                    );
                  }
                }
              },
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDeleteTransaction(Map<String, dynamic> worker, Map<String, dynamic> trans) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تأكيد حذف العملية', style: TextStyle(fontFamily: 'Cairo')),
        content: Text(
          'هل أنت متأكد من حذف هذه العملية بقيمة ${trans['amount']} د.ج؟ سيتم إلغاء الحركة واسترجاع المبلغ إلى الصندوق تلقائياً.',
          style: const TextStyle(fontFamily: 'Cairo'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              await widget.db.deleteWorkerTransaction(
                trans['id'] as int,
                worker['id'] as int,
                trans['amount'] as double,
              );
              Navigator.pop(context); // Close confirm
              Navigator.pop(context); // Close history list
              _loadData();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('تم حذف العملية بنجاح وإعادة المبلغ للصندوق'),
                    backgroundColor: Colors.green,
                  ),
                );
              }
            },
            child: const Text('حذف', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showEditTransactionDialog(Map<String, dynamic> worker, Map<String, dynamic> trans) {
    final amountCtrl = TextEditingController(text: trans['amount'].toString());
    final noteCtrl = TextEditingController(text: trans['note'] ?? '');
    String type = trans['typeRaw'] ?? 'advance';

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) => AlertDialog(
          title: Text(
            'تعديل عملية: ${worker['name']}',
            style: const TextStyle(fontFamily: 'Cairo'),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  value: type,
                  items: const [
                    DropdownMenuItem(
                      value: 'advance',
                      child: Text('سلفة (Advance)', style: TextStyle(fontFamily: 'Cairo')),
                    ),
                    DropdownMenuItem(
                      value: 'salary',
                      child: Text('أجرة (Salary)', style: TextStyle(fontFamily: 'Cairo')),
                    ),
                  ],
                  onChanged: (val) => setStateDialog(() => type = val!),
                  decoration: const InputDecoration(
                    labelText: 'نوع العملية',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: amountCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'المبلغ (سيُعدل بالصندوق)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: noteCtrl,
                  decoration: const InputDecoration(
                    labelText: 'ملاحظة',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (amountCtrl.text.isNotEmpty) {
                  final rawText = amountCtrl.text
                      .replaceAll('،', '')
                      .replaceAll(',', '')
                      .replaceAll(' ', '')
                      .replaceAll('\u00a0', '');
                  final newAmount = double.tryParse(rawText) ?? 0.0;

                  await widget.db.updateWorkerTransaction(
                    trans['id'] as int,
                    worker['uid'],
                    worker['id'] as int,
                    trans['amount'] as double,
                    newAmount,
                    trans['typeRaw'] as String,
                    type,
                    trans['note'] as String,
                    noteCtrl.text,
                    worker['name'],
                  );

                  Navigator.pop(context); // Close edit dialog
                  Navigator.pop(context); // Close history dialog
                  _loadData();
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('تم تعديل العملية بنجاح وتحديث الصندوق'),
                        backgroundColor: Colors.green,
                      ),
                    );
                  }
                }
              },
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );
  }

  void _viewWorkerHistory(Map<String, dynamic> worker) async {
    final wTrans = await widget.db.readWorkerTransactions(worker['uid']);

    final List<Map<String, dynamic>> combined = [];
    for (var t in wTrans) {
      final createdAt = t['created_at']?.toString() ?? '';
      DateTime date = DateTime.now();
      try {
        date = DateTime.parse(createdAt);
      } catch (_) {}
      combined.add({
        'id': t['id'],
        'date': date,
        'amount': (t['amount'] as num?)?.toDouble() ?? 0.0,
        'type': t['transaction_type'] == 'advance' ? 'سلفة' : 'أجرة',
        'typeRaw': t['transaction_type'] ?? 'advance',
        'note': t['note'] ?? '',
      });
    }

    combined.sort((a, b) => b['date'].compareTo(a['date']));

    double totalReceived = 0.0;
    for (var t in combined) {
      totalReceived += t['amount'];
    }

    if (!mounted) return;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          'سجل العامل: ${worker['name']}',
          style: const TextStyle(fontFamily: 'Cairo'),
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'إجمالي ما استلمه: $totalReceived د.ج',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              if (worker['salary_type'] == 'fixed') ...[
                const SizedBox(height: 5),
                Text(
                  'الراتب الشهري الثابت: ${worker['base_salary']} د.ج',
                  style: const TextStyle(fontSize: 14, color: Colors.teal),
                ),
              ],
              const Divider(),
              Expanded(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: combined.length,
                  itemBuilder: (context, index) {
                    final t = combined[index];
                    return ListTile(
                      title: Text(
                        '${t['amount']} د.ج - ${t['type']}',
                        style: const TextStyle(fontFamily: 'Cairo'),
                      ),
                      subtitle: Text(
                        '${t['note']} \n${t['date'].toString().split(' ')[0]}',
                        style: const TextStyle(fontSize: 12),
                      ),
                      trailing: PopupMenuButton<String>(
                        onSelected: (value) {
                          if (value == 'edit') {
                            _showEditTransactionDialog(worker, t);
                          } else if (value == 'delete') {
                            _confirmDeleteTransaction(worker, t);
                          }
                        },
                        itemBuilder: (context) => [
                          const PopupMenuItem(
                            value: 'edit',
                            child: Row(
                              children: [
                                Icon(Icons.edit, color: Colors.orange, size: 18),
                                SizedBox(width: 8),
                                Text('تعديل', style: TextStyle(fontFamily: 'Cairo')),
                              ],
                            ),
                          ),
                          const PopupMenuItem(
                            value: 'delete',
                            child: Row(
                              children: [
                                Icon(Icons.delete, color: Colors.red, size: 18),
                                SizedBox(width: 8),
                                Text('حذف', style: TextStyle(fontFamily: 'Cairo')),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إغلاق', style: TextStyle(fontFamily: 'Cairo')),
          ),
        ],
      ),
    );
  }



  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'إدارة شؤون وأجور العمال',
          style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold),
        ),
        backgroundColor: isDark
            ? Theme.of(context).appBarTheme.backgroundColor
            : Colors.orange,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              itemCount: _workers.length,
              itemBuilder: (context, index) {
                final worker = _workers[index];
                return Card(
                  margin: const EdgeInsets.all(10),
                  child: ListTile(
                    leading: const CircleAvatar(
                      backgroundColor: Colors.orange,
                      child: Icon(Icons.engineering, color: Colors.white),
                    ),
                    title: Text(
                      worker['name'],
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontFamily: 'Cairo',
                      ),
                    ),
                    subtitle: Text(
                      worker['salary_type'] == 'fixed'
                          ? 'راتب ثابت: ${worker['base_salary']} د.ج'
                          : 'سحب متفرق',
                      style: TextStyle(
                        color: isDark ? Colors.grey[400] : Colors.grey[700],
                        fontFamily: 'Cairo',
                      ),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (!widget.readOnly)
                          IconButton(
                            icon: const Icon(Icons.edit_outlined, color: Colors.orange),
                            onPressed: () => _showEditWorkerDialog(worker),
                          ),
                        IconButton(
                          icon: const Icon(Icons.account_balance_wallet_outlined, color: Colors.blue),
                          tooltip: 'عرض وسجل معاملات العامل',
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => WorkerTransactionsDetailScreen(
                                  worker: worker,
                                  db: widget.db,
                                ),
                              ),
                            ).then((_) => _loadData());
                          },
                        ),
                        if (!widget.readOnly)
                          IconButton(
                            icon: const Icon(Icons.payment, color: Colors.green),
                            onPressed: () => _showAddTransactionDialog(worker),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
      floatingActionButton: widget.readOnly ? null : FloatingActionButton.extended(
        onPressed: _showAddWorkerDialog,
        backgroundColor: isDark ? Colors.orange[800] : Colors.orange,
        icon: const Icon(Icons.person_add),
        label: const Text('إضافة عامل', style: TextStyle(fontFamily: 'Cairo')),
      ),
    );
  }
}
