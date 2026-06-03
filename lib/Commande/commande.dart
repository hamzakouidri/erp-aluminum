import 'package:database_data/sql_database.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'add_commande.dart';
import 'package:database_data/settings/localization.dart';
import 'package:database_data/settings/app_settings.dart';
import 'package:provider/provider.dart';

class Commande extends StatefulWidget {
  const Commande({super.key});

  @override
  State<Commande> createState() => _CommandeState();
}

class _CommandeState extends State<Commande> {
  final SqlDatabase db = SqlDatabase();
  late Future<List<Map<String, dynamic>>> _data;

  //late Future<List<String>> _clientNames;

  String formatDate(String date) {
    final parsed = DateTime.parse(date);
    return DateFormat('yyyy-MM-dd').format(parsed);
  }

  @override
  void initState() {
    super.initState();
    _data = db.readCommandesWithClients();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: Text(Localization.translate("Commande", Provider.of<AppSettingsProvider>(context).language)),
        centerTitle: true,
        backgroundColor: Colors.blue,
      ),
      body: Column(
        children: [
          // 🔍 Filters
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
                Row(
                  children: [
                    Icon(Icons.filter_alt_outlined, color: Colors.blue),
                    SizedBox(width: 10),
                    Text(Localization.translate("Filters Commandes", Provider.of<AppSettingsProvider>(context).language),
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 10),
                TextField(
                  decoration: InputDecoration(
                    hintText: Localization.translate("Search", Provider.of<AppSettingsProvider>(context).language),
                    prefixIcon: Icon(Icons.search),
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Container(
              margin: EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
              ),
              child: FutureBuilder<List<Map<String, dynamic>>>(
                future: _data,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return Center(child: CircularProgressIndicator());
                  } else if (snapshot.hasError) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.error_outline, size: 60, color: Colors.red.shade300),
                          const SizedBox(height: 16),
                          Text('حدث خطأ أثناء جلب الطلبيات', style: TextStyle(color: Colors.grey.shade700, fontSize: 18, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 8),
                          Text('${snapshot.error}', style: const TextStyle(color: Colors.red), textAlign: TextAlign.center),
                        ],
                      ),
                    );
                  }
                  if (!snapshot.hasData || snapshot.data!.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.inbox_rounded, size: 80, color: Colors.grey.shade300),
                          const SizedBox(height: 16),
                          Text(Localization.translate("No Data", Provider.of<AppSettingsProvider>(context).language),
                            style: TextStyle(color: Colors.grey.shade600, fontSize: 20, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 8),
                          Text('لم تقم بإضافة أي طلبيات بعد', style: TextStyle(color: Colors.grey.shade500, fontSize: 14)),
                        ],
                      ),
                    );
                  }
                  final data = snapshot.data!;

                  return ListView.builder(
                    itemCount: data.length,
                    itemBuilder: (context, index) {
                      final id = data[index]['id'];
                      final clientFirst = data[index]['firstname'] ?? '';
                      final clientLast = data[index]['lastname'] ?? '';
                      final clientPhone = data[index]['phone'] ?? '';
                      final clientName = '$clientFirst $clientLast'.trim();
                      final clientDisplay = clientName.isEmpty ? 'زبون غير معروف' : clientName;
                      
                      final total = data[index]['total'] ?? 0.0;
                      final status = data[index]['status'] ?? 'New';
                      return Card(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                        elevation: 2,
                        margin: const EdgeInsets.symmetric(vertical: 8),
                        child: ListTile(
                          contentPadding: const EdgeInsets.all(15),
                          leading: CircleAvatar(
                            radius: 25,
                            backgroundColor: Colors.blue.shade100,
                            child: const Icon(Icons.receipt_long, color: Colors.blue),
                          ),
                          title: Text(clientDisplay, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 5),
                              Text("تاريخ الإنشاء: ${formatDate(data[index]['created_at'])}", style: const TextStyle(color: Colors.black54)),
                              if (clientPhone.toString().isNotEmpty) 
                                Text("الهاتف: $clientPhone", style: const TextStyle(color: Colors.black54)),
                            ],
                          ),
                          trailing: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text('${total.toStringAsFixed(2)} دج', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green, fontSize: 16)),
                              const SizedBox(height: 5),
                              Text(status, style: const TextStyle(color: Colors.grey, fontSize: 12)),
                            ],
                          ),
                          onLongPress: () async {
                            bool? confirm = await showDialog(
                              context: context,
                              builder: (context) => AlertDialog(
                                title: const Text('تأكيد الحذف'),
                                content: const Text('هل أنت متأكد من حذف هذه الطلبية؟'),
                                actions: [
                                  TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
                                  TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('حذف', style: TextStyle(color: Colors.red))),
                                ],
                              ),
                            );
                            if (confirm == true) {
                               await db.deleteCommande(id);
                               setState(() {
                                 _data = db.readCommandesWithClients();
                               });
                            }
                          },
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ),
        ],
      ),

      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final result = await Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => CommandePage(db: db)),
          );
          if (result == true) {
            setState(() {
              _data = db.readCommandesWithClients();
            });
          }
        },
        child: const Icon(Icons.add),
      ),
    );
  }

  Future<List<String>> getClientNames() async {
    final data = await db.readClient(); // تجيب كل العملاء

    return List.generate(data.length, (index) {
      return "${data[index]['firstname']} ${data[index]['lastname']}";
    });
  }
}
