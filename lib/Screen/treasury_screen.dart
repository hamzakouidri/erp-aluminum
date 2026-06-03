import 'package:flutter/material.dart';
import '../sql_database.dart';
import 'package:provider/provider.dart';
import '../settings/app_settings.dart';

class TreasuryScreen extends StatefulWidget {
  final SqlDatabase db;

  const TreasuryScreen({super.key, required this.db});

  @override
  State<TreasuryScreen> createState() => _TreasuryScreenState();
}

class _TreasuryScreenState extends State<TreasuryScreen> {
  List<Map<String, dynamic>> _transactions = [];
  bool _isLoading = false;
  double _totalBalance = 0.0;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final data = await widget.db.readTreasury();
    
    double balance = 0.0;
    for (var row in data) {
      if (row['transaction_type'] == 'income') {
        balance += row['amount'];
      } else {
        balance -= row['amount'];
      }
    }

    setState(() {
      _transactions = data;
      _totalBalance = balance;
      _isLoading = false;
    });
  }

  void _showAddTransactionDialog() {
    final amountCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    String type = 'income';

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) => AlertDialog(
          title: Text('إضافة معاملة للصندوق'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: type,
                  items: const [
                    DropdownMenuItem(value: 'income', child: Text('مدخول (إضافة)')),
                    DropdownMenuItem(value: 'expense', child: Text('مصروف (سحب)')),
                  ],
                  onChanged: (val) => setStateDialog(() => type = val!),
                  decoration: InputDecoration(labelText: 'نوع المعاملة', border: OutlineInputBorder()),
                ),
                SizedBox(height: 10),
                TextField(
                  controller: amountCtrl,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(labelText: 'المبلغ', border: OutlineInputBorder()),
                ),
                SizedBox(height: 10),
                TextField(
                  controller: descCtrl,
                  decoration: InputDecoration(labelText: 'البيان (مثال: شراء زجاج، دفع كهرباء)', border: OutlineInputBorder()),
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
                  await widget.db.insertTreasury(type, amount, descCtrl.text, recordedBy: role == 'manager' ? 'مدير الورشة' : 'عامل');
                  Navigator.pop(context);
                  _loadData();
                }
              },
              child: Text('حفظ'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('الصندوق المالي')),
      body: Column(
        children: [
          Container(
            padding: EdgeInsets.all(20),
            color: _totalBalance >= 0 ? Colors.green.shade100 : Colors.red.shade100,
            width: double.infinity,
            child: Column(
              children: [
                Text('الرصيد الإجمالي', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                Text('${_totalBalance.toStringAsFixed(2)} د.ج', style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: _totalBalance >= 0 ? Colors.green.shade800 : Colors.red.shade800)),
              ],
            ),
          ),
          Expanded(
            child: _isLoading 
              ? Center(child: CircularProgressIndicator())
              : ListView.builder(
                  itemCount: _transactions.length,
                  itemBuilder: (context, index) {
                    final t = _transactions[index];
                    final isIncome = t['transaction_type'] == 'income';
                    return Card(
                      margin: EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: isIncome ? Colors.green : Colors.red,
                          child: Icon(isIncome ? Icons.arrow_downward : Icons.arrow_upward, color: Colors.white),
                        ),
                        title: Text('${t['amount']} د.ج', style: TextStyle(fontWeight: FontWeight.bold, color: isIncome ? Colors.green : Colors.red)),
                        subtitle: Text('${t['description']} \nسجلها: ${t['recorded_by'] ?? 'غير معروف'}'),
                        trailing: Text(t['created_at'].toString().split(' ')[0]),
                      ),
                    );
                  },
                ),
          )
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddTransactionDialog,
        icon: Icon(Icons.add),
        label: Text('معاملة جديدة'),
      ),
    );
  }
}
