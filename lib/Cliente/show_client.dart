import 'package:flutter/material.dart';
import '../sql_database.dart';
import 'package:database_data/settings/localization.dart';
import 'package:database_data/settings/app_settings.dart';
import 'package:provider/provider.dart';

class ShowClient extends StatefulWidget {
  final int clientId;

  const ShowClient({super.key, required this.clientId});

  @override
  State<ShowClient> createState() => _ShowClientState();
}

class _ShowClientState extends State<ShowClient> {
  final SqlDatabase db = SqlDatabase();
  late Future<List<Map<String, dynamic>>> data;

  void _showAddPaymentDialog(BuildContext context, int orderId, double remaining) {
    final amountCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('إضافة دفعة لطلبية #$orderId'),
        content: TextField(
          controller: amountCtrl,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(labelText: 'المبلغ المدفوع', hintText: 'المتبقي: $remaining د.ج', border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text('إلغاء')),
          ElevatedButton(
            onPressed: () async {
              if (amountCtrl.text.isNotEmpty) {
                double amount = double.tryParse(amountCtrl.text) ?? 0.0;
                if (amount > 0) {
                  await db.addAdvanceToCommande(orderId, amount);
                  final role = Provider.of<AppSettingsProvider>(context, listen: false).userRole;
                  await db.insertTreasury('income', amount, 'دفعة لطلبية رقم $orderId', referenceId: orderId, recordedBy: role == 'manager' ? 'مدير الورشة' : 'عامل');
                  Navigator.pop(context);
                  setState(() {
                    data = db.getClientById(widget.clientId); // Reload screen
                  });
                }
              }
            },
            child: Text('حفظ الدفعة'),
          ),
        ],
      ),
    );
  }

  Future<List<dynamic>> _loadData() async {
    final myDb = await db.db;
    final cData = await myDb!.query('Client', where: 'id = ?', whereArgs: [widget.clientId]);
    final orders = await myDb.query('Commandes', where: 'client_id = ?', whereArgs: [widget.clientId]);
    return [cData, orders];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: Text(Localization.translate("Client Details", Provider.of<AppSettingsProvider>(context).language)),
        backgroundColor: Colors.grey[200],
        centerTitle: true,
      ),
      body: FutureBuilder<List<dynamic>>(
        future: _loadData(),
        builder: (context, asyncSnapshot) {
          if (asyncSnapshot.connectionState == ConnectionState.waiting) {
            return Center(child: CircularProgressIndicator());
          } else if (asyncSnapshot.hasError) {
            return Center(child: Text('Error: ${asyncSnapshot.error}'));
          } else if (asyncSnapshot.hasData) {
            final clientData = asyncSnapshot.data![0] as List<Map<String, dynamic>>;
            if (clientData.isEmpty) return const Center(child: Text('Client not found'));
            final client = clientData[0];
            final orders = asyncSnapshot.data![1] as List<Map<String, dynamic>>;
            
            double totalOrders = 0.0;
            double totalPayments = 0.0;
            for (var order in orders) {
              totalOrders += (order['total'] as num?)?.toDouble() ?? 0.0;
              totalPayments += (order['advance_payment'] as num?)?.toDouble() ?? 0.0;
            }

            return SingleChildScrollView(
              child: Column(
                children: [
                  Container(
                    width: double.infinity,
                    padding: EdgeInsets.all(20),
                    margin: EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      border: Border.all(width: 1, color: Colors.grey),
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            border: Border.all(width: 1, color: Colors.black12),
                            color: Colors.blue[50],
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(Icons.person, size: 50, color: Colors.blue),
                        ),
                        SizedBox(width: 10),
                        Text(client['firstname'], style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                        SizedBox(width: 5),
                        Text(client['lastname'], style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),

                  Divider(color: Colors.orangeAccent, thickness: 1),
                  Container(
                    width: double.infinity,
                    padding: EdgeInsets.all(20),
                    margin: EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      border: Border.all(width: 1, color: Colors.grey),
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Column(
                      children: [
                        Text(Localization.translate("Client Information", Provider.of<AppSettingsProvider>(context).language),
                          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                        ),
                        SizedBox(height: 10),
                        Row(
                          children: [
                            Icon(Icons.place, color: Colors.blue),
                            SizedBox(width: 10),
                            Text("Address: "),
                            Text(client['address'], style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
                          ],
                        ),
                        SizedBox(height: 10),
                        Divider(),
                        SizedBox(height: 10),
                        Row(
                          children: [
                            Icon(Icons.phone, color: Colors.blue),
                            SizedBox(width: 10),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(Localization.translate("Phone Numbers:", Provider.of<AppSettingsProvider>(context).language)),
                                Text(client['phone1'].toString()),
                                Text(client['phone2'].toString()),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          padding: EdgeInsets.all(30),
                          margin: EdgeInsets.all(5),
                          decoration: BoxDecoration(
                            border: Border(left: BorderSide(width: 8, color: Colors.blue)),
                            borderRadius: BorderRadius.circular(20),
                            color: Colors.white,
                          ),
                          child: Column(
                            children: [Text(totalOrders.toStringAsFixed(2)), Text(Localization.translate('Total Orders', Provider.of<AppSettingsProvider>(context).language))],
                          ),
                        ),
                      ),
                      Expanded(
                        child: Container(
                          padding: EdgeInsets.all(30),
                          margin: EdgeInsets.all(5),
                          decoration: BoxDecoration(
                            border: Border(left: BorderSide(width: 8, color: Colors.green)),
                            borderRadius: BorderRadius.circular(20),
                            color: Colors.white,
                          ),
                          child: Column(
                            children: [Text(totalPayments.toStringAsFixed(2)), Text(Localization.translate('Total Payments', Provider.of<AppSettingsProvider>(context).language))],
                          ),
                        ),
                      ),
                    ],
                  ),

                  Container(
                    width: double.infinity,
                    padding: EdgeInsets.all(30),
                    margin: EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      border: Border(left: BorderSide(width: 8, color: Colors.red)),
                      borderRadius: BorderRadius.circular(20),
                      color: Colors.white,
                    ),
                    child: Column(
                      children: [Text((totalOrders - totalPayments).toStringAsFixed(2)), Text(Localization.translate("Rest of the order", Provider.of<AppSettingsProvider>(context).language))],
                    ),
                  ),

                  // Orders List
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Text('طلبيات الزبون', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  ),
                  ListView.builder(
                    shrinkWrap: true,
                    physics: NeverScrollableScrollPhysics(),
                    itemCount: orders.length,
                    itemBuilder: (context, index) {
                      final order = orders[index];
                      double orderTotal = (order['total'] as num?)?.toDouble() ?? 0.0;
                      double orderAdvance = (order['advance_payment'] as num?)?.toDouble() ?? 0.0;
                      return Card(
                        margin: EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        child: ListTile(
                          title: Text('طلبية #${order['id']} - ${order['payment_status'] == 'Paid' ? 'خالصة' : 'غير خالصة'}'),
                          subtitle: Text('الإجمالي: $orderTotal د.ج\\nالمدفوع: $orderAdvance د.ج'),
                          trailing: orderAdvance < orderTotal ? ElevatedButton(
                            onPressed: () {
                              _showAddPaymentDialog(context, order['id'] as int, orderTotal - orderAdvance);
                            },
                            child: Text('إضافة دفعة'),
                          ) : Icon(Icons.check_circle, color: Colors.green),
                        ),
                      );
                    },
                  )

                ],
              ),
            );
          }
          return Center(child: Text(Localization.translate("No Data", Provider.of<AppSettingsProvider>(context).language)));
        },
      ),
    );
  }
}
