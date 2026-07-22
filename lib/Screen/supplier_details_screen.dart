import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../settings/app_settings.dart';
import '../settings/localization.dart';
import '../sql_database.dart';
import 'package:intl/intl.dart';
// import 'achat_screen.dart'; // Will be used when opening a specific purchase if needed

class SupplierDetailsScreen extends StatefulWidget {
  final Map<String, dynamic> supplier;

  const SupplierDetailsScreen({super.key, required this.supplier});

  @override
  State<SupplierDetailsScreen> createState() => _SupplierDetailsScreenState();
}

class _SupplierDetailsScreenState extends State<SupplierDetailsScreen> {
  final SqlDatabase db = SqlDatabase();
  List<Map<String, dynamic>> _invoices = [];
  bool _isLoading = true;

  double _totalBought = 0;
  double _totalPaid = 0;
  double _remainingDebt = 0;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final achats = await db.readAchatsBySupplier(widget.supplier['id']);

    double tBought = 0;
    double tPaid = 0;

    for (var a in achats) {
      tBought += (a['total'] as num?)?.toDouble() ?? 0;
      tPaid += (a['paid_amount'] as num?)?.toDouble() ?? 0;
    }

    setState(() {
      _invoices = achats;
      _totalBought = tBought;
      _totalPaid = tPaid;
      _remainingDebt = tBought - tPaid;
      _isLoading = false;
    });
  }

  String formatDate(String date) {
    try {
      final parsed = DateTime.parse(date);
      return DateFormat('yyyy-MM-dd HH:mm').format(parsed);
    } catch (e) {
      return date;
    }
  }

  @override
  Widget build(BuildContext context) {
    final lang = Provider.of<AppSettingsProvider>(context).language;
    return Scaffold(
      appBar: AppBar(
        title: Text('${Localization.translate('ملف المورد: ', lang)}${widget.supplier['name']}'),
        backgroundColor: Colors.blue.shade800,
        elevation: 0,
      ),
      body: Column(
        children: [
          // Header / Ledger Info
          Container(
            color: Colors.blue.shade800,
            padding: const EdgeInsets.only(bottom: 20, left: 16, right: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildStatCard(
                  Localization.translate('إجمالي المشتريات', lang),
                  _totalBought,
                  Colors.blue.shade100,
                  Colors.blue.shade900,
                ),
                _buildStatCard(
                  Localization.translate('المدفوع', lang),
                  _totalPaid,
                  Colors.green.shade100,
                  Colors.green.shade900,
                ),
                _buildStatCard(
                  Localization.translate('الديون', lang),
                  _remainingDebt,
                  Colors.red.shade100,
                  Colors.red.shade900,
                ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Align(
              alignment: Alignment.centerRight,
              child: Text(
                Localization.translate('سجل الفواتير', lang),
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
          ),

          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _invoices.isEmpty
                    ? Center(child: Text(Localization.translate('لا توجد فواتير مسجلة لهذا المورد', lang)))
                    : ListView.builder(
                        itemCount: _invoices.length,
                        itemBuilder: (context, index) {
                          final invoice = _invoices[index];
                          final total = (invoice['total'] as num?)?.toDouble() ?? 0;
                          final paid = (invoice['paid_amount'] as num?)?.toDouble() ?? 0;
                          final status = invoice['status'] ?? 'Active';

                          return Card(
                            margin: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 5,
                            ),
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: status == 'Confirmed' ? Colors.green : Colors.orange,
                                child: const Icon(
                                  Icons.receipt,
                                  color: Colors.white,
                                ),
                              ),
                              title: Text(
                                '${Localization.translate('فاتورة #', lang)}${invoice['invoice_number']}',
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                              subtitle: Text(
                                '${formatDate(invoice['created_at'])}\n${Localization.translate('الحالة: ', lang)}${status == 'Confirmed' ? Localization.translate('مؤكدة', lang) : Localization.translate('قيد التعديل', lang)}',
                              ),
                              trailing: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    '${Localization.translate('الإجمالي: ', lang)}$total د.ج',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                    ),
                                  ),
                                  Text(
                                    '${Localization.translate('المدفوع: ', lang)}$paid د.ج',
                                    style: TextStyle(
                                      color: paid >= total ? Colors.green : Colors.red,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                              isThreeLine: true,
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(
    String title,
    double amount,
    Color bgColor,
    Color textColor,
  ) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          Text(
            title,
            style: TextStyle(color: textColor, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 5),
          Text(
            '${amount.toStringAsFixed(2)} د.ج',
            style: TextStyle(
              color: textColor,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }
}
