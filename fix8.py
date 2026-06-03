import sys

with open('lib/Cliente/show_client.dart', 'r', encoding='utf-8') as f:
    content = f.read()

# Replace the body builder to fetch orders and display them
old_body_start = '''    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: Text(Localization.translate("Client Details", Provider.of<AppSettingsProvider>(context).language)),
        backgroundColor: Colors.grey[200],
        centerTitle: true,
      ),
      body: FutureBuilder('''

new_body_start = '''    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: Text(Localization.translate("Client Details", Provider.of<AppSettingsProvider>(context).language)),
        backgroundColor: Colors.grey[200],
        centerTitle: true,
      ),
      body: FutureBuilder(
        future: Future.wait([
          data,
          db.myDb!.query('Commandes', where: 'client_id = ?', whereArgs: [widget.clientId])
        ]),'''

content = content.replace(old_body_start, new_body_start)

old_snapshot_check = '''        builder: (context, asyncSnapshot) {
          if (asyncSnapshot.connectionState == ConnectionState.waiting) {
            return Center(child: CircularProgressIndicator());
          } else if (asyncSnapshot.hasError) {
            return Center(child: Text('Error: ${asyncSnapshot.error}'));
          } else if (asyncSnapshot.hasData && asyncSnapshot.data!.isNotEmpty) {
            final client = asyncSnapshot.data![0]; // o. O1U.USU, U^O O-O_'''

new_snapshot_check = '''        builder: (context, AsyncSnapshot<List<dynamic>> asyncSnapshot) {
          if (asyncSnapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
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
            }'''

content = content.replace(old_snapshot_check, new_snapshot_check)

old_totals = '''                          child: Column(
                            children: [Text('0.00'), Text(Localization.translate('Total Orders', Provider.of<AppSettingsProvider>(context).language))],
                          ),
                        ),
                      ),
                      Expanded(
                        child: Container(
                          padding: EdgeInsets.all(30),
                          margin: EdgeInsets.all(5),
                          decoration: BoxDecoration(
                            border: Border(
                              left: BorderSide(width: 8, color: Colors.green),
                            ),
                            borderRadius: BorderRadius.circular(20),
                            color: Colors.white,
                          ),
                          child: Column(
                            children: [Text('0.00'), Text(Localization.translate('Total Payments', Provider.of<AppSettingsProvider>(context).language))],'''

new_totals = '''                          child: Column(
                            children: [Text(totalOrders.toStringAsFixed(2)), Text(Localization.translate('Total Orders', Provider.of<AppSettingsProvider>(context).language))],
                          ),
                        ),
                      ),
                      Expanded(
                        child: Container(
                          padding: EdgeInsets.all(30),
                          margin: EdgeInsets.all(5),
                          decoration: BoxDecoration(
                            border: Border(
                              left: BorderSide(width: 8, color: Colors.green),
                            ),
                            borderRadius: BorderRadius.circular(20),
                            color: Colors.white,
                          ),
                          child: Column(
                            children: [Text(totalPayments.toStringAsFixed(2)), Text(Localization.translate('Total Payments', Provider.of<AppSettingsProvider>(context).language))],'''

content = content.replace(old_totals, new_totals)

old_red_box = '''                  Container(
                    width: double.infinity,
                    padding: EdgeInsets.all(30),
                    margin: EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      border: Border(
                        left: BorderSide(width: 8, color: Colors.red),
                      ),
                      borderRadius: BorderRadius.circular(20),
                      color: Colors.white,
                    ),
                    child: Column(
                      children: [Text('0.00'), Text(Localization.translate('Remainder', Provider.of<AppSettingsProvider>(context).language))],
                    ),
                  )'''

new_red_box = '''                  Container(
                    width: double.infinity,
                    padding: EdgeInsets.all(30),
                    margin: EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      border: Border(
                        left: BorderSide(width: 8, color: Colors.red),
                      ),
                      borderRadius: BorderRadius.circular(20),
                      color: Colors.white,
                    ),
                    child: Column(
                      children: [Text((totalOrders - totalPayments).toStringAsFixed(2)), Text(Localization.translate('Remainder', Provider.of<AppSettingsProvider>(context).language))],
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
                              _showAddPaymentDialog(context, order['id'], orderTotal - orderAdvance);
                            },
                            child: Text('إضافة دفعة'),
                          ) : Icon(Icons.check_circle, color: Colors.green),
                        ),
                      );
                    },
                  )'''

content = content.replace(old_red_box, new_red_box)

new_dialog_method = '''
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
'''

content = content.replace('class _ShowClientState extends State<ShowClient> {', 'class _ShowClientState extends State<ShowClient> {' + new_dialog_method)

with open('lib/Cliente/show_client.dart', 'w', encoding='utf-8') as f:
    f.write(content)
