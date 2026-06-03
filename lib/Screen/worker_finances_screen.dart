import 'package:flutter/material.dart';
import '../sql_database.dart';
import 'package:provider/provider.dart';
import '../settings/app_settings.dart';

class WorkerFinancesScreen extends StatefulWidget {
  final SqlDatabase db;

  const WorkerFinancesScreen({super.key, required this.db});

  @override
  State<WorkerFinancesScreen> createState() => _WorkerFinancesScreenState();
}

class _WorkerFinancesScreenState extends State<WorkerFinancesScreen> {
  List<Map<String, dynamic>> _workers = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final data = await widget.db.readEmployees();
    setState(() {
      _workers = data;
      _isLoading = false;
    });
  }

  void _showAddTransactionDialog(Map<String, dynamic> worker) {
    final amountCtrl = TextEditingController();
    final noteCtrl = TextEditingController();
    String type = 'advance'; // advance (سلفة) or salary (راتب)

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) => AlertDialog(
          title: Text('تسجيل مال للعامل: ${worker['name']}'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: type,
                  items: const [
                    DropdownMenuItem(value: 'advance', child: Text('سلفة (Advance)')),
                    DropdownMenuItem(value: 'salary', child: Text('أجرة (Salary)')),
                  ],
                  onChanged: (val) => setStateDialog(() => type = val!),
                  decoration: InputDecoration(labelText: 'نوع العملية', border: OutlineInputBorder()),
                ),
                SizedBox(height: 10),
                TextField(
                  controller: amountCtrl,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(labelText: 'المبلغ (سيُخصم من الصندوق)', border: OutlineInputBorder()),
                ),
                SizedBox(height: 10),
                TextField(
                  controller: noteCtrl,
                  decoration: InputDecoration(labelText: 'ملاحظة', border: OutlineInputBorder()),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: Text('إلغاء')),
            ElevatedButton(
              onPressed: () async {
                if (amountCtrl.text.isNotEmpty) {
                  final amount = double.tryParse(amountCtrl.text) ?? 0.0;
                  final role = Provider.of<AppSettingsProvider>(context, listen: false).userRole;
                  
                  // 1. تسجل في حساب العامل
                  await widget.db.insertWorkerTransaction(worker['uid'], amount, type, noteCtrl.text);
                  
                  // 2. تٌخصم من الصندوق
                  String desc = (type == 'advance' ? 'سلفة للعامل ' : 'أجرة للعامل ') + worker['name'];
                  await widget.db.insertTreasury('expense', amount, desc, recordedBy: role == 'manager' ? 'مدير الورشة' : 'عامل');
                  
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تم تسجيل العملية بنجاح وخصمها من الصندوق')));
                }
              },
              child: Text('حفظ'),
            ),
          ],
        ),
      ),
    );
  }

  void _viewWorkerHistory(Map<String, dynamic> worker) async {
    final transactions = await widget.db.readWorkerTransactions(worker['uid']);
    double totalReceived = 0.0;
    for (var t in transactions) {
      totalReceived += t['amount'];
    }

    if (!mounted) return;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('سجل العامل: ${worker['name']}'),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('إجمالي ما استلمه: $totalReceived د.ج', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              Divider(),
              Expanded(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: transactions.length,
                  itemBuilder: (context, index) {
                    final t = transactions[index];
                    return ListTile(
                      title: Text('${t['amount']} د.ج - ${t['transaction_type'] == 'advance' ? 'سلفة' : 'أجرة'}'),
                      subtitle: Text('${t['note']} \\n${t['created_at'].toString().split(' ')[0]}'),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text('إغلاق')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('سلفيات وأجور العمال')),
      body: _isLoading 
        ? Center(child: CircularProgressIndicator())
        : ListView.builder(
            itemCount: _workers.length,
            itemBuilder: (context, index) {
              final worker = _workers[index];
              return Card(
                margin: EdgeInsets.all(10),
                child: ListTile(
                  leading: CircleAvatar(child: Icon(Icons.person)),
                  title: Text(worker['name']),
                  subtitle: Text(worker['email']),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: Icon(Icons.history, color: Colors.blue),
                        onPressed: () => _viewWorkerHistory(worker),
                      ),
                      IconButton(
                        icon: Icon(Icons.payment, color: Colors.green),
                        onPressed: () => _showAddTransactionDialog(worker),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
    );
  }
}
