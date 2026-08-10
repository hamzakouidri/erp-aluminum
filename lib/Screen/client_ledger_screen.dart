import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../sql_database.dart';
import '../settings/localization.dart';
import '../settings/app_settings.dart';
import '../Commande/add_commande.dart'; // CommandePage for edit
import 'client_ledger_pdf_service.dart';
import 'receipt_pdf_service.dart';

class ClientLedgerScreen extends StatefulWidget {
  final int clientId;

  const ClientLedgerScreen({super.key, required this.clientId});

  @override
  State<ClientLedgerScreen> createState() => _ClientLedgerScreenState();
}

class _ClientLedgerScreenState extends State<ClientLedgerScreen> {
  final SqlDatabase db = SqlDatabase();
  final formatter = NumberFormat('#,##0.00');

  Map<String, dynamic>? _client;
  List<Map<String, dynamic>> _ledgerItems = [];
  bool _isLoading = true;

  double _totalDebit = 0.0;
  double _totalCredit = 0.0;
  double _netBalance = 0.0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final settings = Provider.of<AppSettingsProvider>(context);
    if (!settings.isManager && !settings.canViewClientLedger()) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && Navigator.canPop(context)) {
          Navigator.pop(context);
        }
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _loadLedgerData();
  }

  Future<void> _loadLedgerData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      await db.migrateLegacyTreasuryRecords();
      final myDb = await db.db;

      // 1. Get Client Info
      final clientList = await myDb!.query('Client', where: 'id = ?', whereArgs: [widget.clientId]);
      if (clientList.isNotEmpty) {
        _client = clientList.first;
      }

      // 2. Get Client Orders (Commandes)
      final ordersList = await myDb.query('Commandes', where: 'client_id = ?', whereArgs: [widget.clientId]);

      // 3. Get Client Payments (Treasury)
      final treasuryList = await myDb.query('Treasury', where: "entity_type = 'Client' AND entity_id = ?", whereArgs: [widget.clientId]);

      // 4. Load Order details if detailed view is used (we pre-fetch details for all orders)
      final Map<int, List<Map<String, dynamic>>> orderDetailsMap = {};
      for (var order in ordersList) {
        final orderId = order['id'] as int;
        final details = await myDb.query('Commandes_details', where: 'id_commandes = ?', whereArgs: [orderId]);
        orderDetailsMap[orderId] = details;
      }

      // 5. Combine and Sort chronologically
      final List<Map<String, dynamic>> tempItems = [];

      // Add orders as debits
      for (var order in ordersList) {
        final double netPayable = (order['net_payable'] as num?)?.toDouble() ?? 0.0;
        final double total = (order['total'] as num?)?.toDouble() ?? 0.0;
        final double amount = netPayable > 0 ? netPayable : total;

        final createdAt = order['created_at']?.toString() ?? '';
        DateTime date = DateTime.now();
        try {
          date = DateTime.parse(createdAt);
        } catch (_) {}

        final orderId = order['id'] as int;

        tempItems.add({
          'id': orderId,
          'date': date,
          'type': 'Order',
          'label': 'طلب شراء / Commande #$orderId',
          'debit': amount,
          'credit': 0.0,
          'details': orderDetailsMap[orderId] ?? [],
          'rawData': order,
        });
      }

      // Add payments and refunds from treasury
      for (var t in treasuryList) {
        final String tType = t['transaction_type']?.toString() ?? 'Encaissement';
        final double amount = (t['amount'] as num?)?.toDouble() ?? 0.0;

        final createdAt = t['created_at']?.toString() ?? '';
        DateTime date = DateTime.now();
        try {
          date = DateTime.parse(createdAt);
        } catch (_) {}

        if (tType == 'Encaissement') {
          // Client payment -> credit
          tempItems.add({
            'id': t['id'] as int,
            'date': date,
            'type': 'Payment',
            'label': 'دفعة مالية / Paiement (${t['payment_method'] ?? 'Espèce'})',
            'debit': 0.0,
            'credit': amount,
            'details': null,
            'rawData': t,
          });
        } else if (tType == 'Décaissement') {
          // Refund to client -> debit
          tempItems.add({
            'id': t['id'] as int,
            'date': date,
            'type': 'Refund',
            'label': 'مسترجع نقدي / Remboursement (${t['payment_method'] ?? 'Espèce'})',
            'debit': amount,
            'credit': 0.0,
            'details': null,
            'rawData': t,
          });
        }
      }

      // Sort ascending by DateTime
      tempItems.sort((a, b) => (a['date'] as DateTime).compareTo(b['date'] as DateTime));

      // Calculate running balance and totals
      double balance = 0.0;
      double debitTotal = 0.0;
      double creditTotal = 0.0;

      for (var i = 0; i < tempItems.length; i++) {
        final d = tempItems[i]['debit'] as double;
        final c = tempItems[i]['credit'] as double;
        balance = balance + d - c;
        tempItems[i]['runningBalance'] = balance;
        debitTotal += d;
        creditTotal += c;
      }

      setState(() {
        _ledgerItems = tempItems;
        _totalDebit = debitTotal;
        _totalCredit = creditTotal;
        _netBalance = debitTotal - creditTotal;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _showReceiptOptions(BuildContext context, Map<String, dynamic> treasuryItem) {
    final lang = Provider.of<AppSettingsProvider>(context, listen: false).language;
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.print, color: Colors.teal),
                title: Text(
                  Localization.translate('طباعة الوصل', lang),
                  style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold),
                ),
                onTap: () async {
                  Navigator.pop(ctx);
                  await ReceiptPdfService.printReceiptWithFeedback(
                    treasuryItem,
                    context,
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.save, color: Colors.blue),
                title: Text(
                  Localization.translate('حفظ', lang),
                  style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold),
                ),
                onTap: () async {
                  Navigator.pop(ctx);
                  await ReceiptPdfService.saveReceiptWithFeedback(
                    treasuryItem,
                    context,
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.share, color: Colors.orange),
                title: Text(
                  Localization.translate('مشاركة', lang),
                  style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold),
                ),
                onTap: () async {
                  Navigator.pop(ctx);
                  await ReceiptPdfService.shareReceiptWithFeedback(
                    treasuryItem,
                    context,
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _choosePdfTypeAndExecute(BuildContext context, Function(bool detailed) action) {
    final lang = Provider.of<AppSettingsProvider>(context, listen: false).language;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          Localization.translate('نوع كشف الحساب', lang),
          style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 16),
          textAlign: TextAlign.center,
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.blue,
                minimumSize: const Size(double.infinity, 44),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                side: const BorderSide(color: Colors.blue),
              ),
              onPressed: () {
                Navigator.pop(ctx);
                action(true); // detailed
              },
              child: Text(
                Localization.translate('كشف حساب تفصيلي (بالنوافذ والمقاسات)', lang),
                style: const TextStyle(fontFamily: 'Cairo', fontSize: 13),
              ),
            ),
            const SizedBox(height: 10),
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.blue,
                minimumSize: const Size(double.infinity, 44),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                side: const BorderSide(color: Colors.blue),
              ),
              onPressed: () {
                Navigator.pop(ctx);
                action(false); // summary
              },
              child: Text(
                Localization.translate('كشف حساب مختصر (بالأرقام فقط)', lang),
                style: const TextStyle(fontFamily: 'Cairo', fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final lang = Provider.of<AppSettingsProvider>(context).language;
    final String clientName = _client != null
        ? '${_client!['lastname'] ?? ''} ${_client!['firstname'] ?? ''}'.trim()
        : '...';

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(
          Localization.translate('كشف حساب الزبون', lang),
          style: const TextStyle(fontWeight: FontWeight.w600, fontFamily: 'Cairo'),
        ),
        centerTitle: true,
        backgroundColor: Theme.of(context).brightness == Brightness.dark ? Theme.of(context).appBarTheme.backgroundColor : Colors.blue,
        foregroundColor: Theme.of(context).cardColor,
        elevation: 0,
        actions: _client == null
            ? []
            : [
                IconButton(
                  icon: const Icon(Icons.print),
                  tooltip: Localization.translate('طباعة كشف الحساب', lang),
                  onPressed: () => _choosePdfTypeAndExecute(
                    context,
                    (detailed) => ClientLedgerPdfService.printClientLedger(_client!, _ledgerItems, detailed: detailed, lang: lang),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.share),
                  tooltip: Localization.translate('مشاركة كشف الحساب', lang),
                  onPressed: () => _choosePdfTypeAndExecute(
                    context,
                    (detailed) => ClientLedgerPdfService.shareClientLedger(_client!, _ledgerItems, detailed: detailed, lang: lang),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.save),
                  tooltip: Localization.translate('حفظ كشف الحساب', lang),
                  onPressed: () => _choosePdfTypeAndExecute(
                    context,
                    (detailed) => ClientLedgerPdfService.saveClientLedger(_client!, _ledgerItems, context, detailed: detailed, lang: lang),
                  ),
                ),
              ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // 1. Client Header Info Card
                Container(
                  width: double.infinity,
                  color: Theme.of(context).brightness == Brightness.dark
                      ? (Theme.of(context).appBarTheme.backgroundColor ?? const Color(0xFF1E293B))
                      : Colors.blue,
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).brightness == Brightness.dark
                          ? Colors.white.withOpacity(0.08)
                          : Theme.of(context).cardColor.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.person, color: Colors.white, size: 18),
                            const SizedBox(width: 8),
                            Text(
                              '${Localization.translate('الزبون', lang)}: $clientName',
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15, fontFamily: 'Cairo'),
                            ),
                          ],
                        ),
                        if (_client != null && _client!['phone1'] != null && _client!['phone1'].toString().isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              const Icon(Icons.phone, color: Colors.white70, size: 14),
                              const SizedBox(width: 8),
                              Text(
                                _client!['phone1'].toString(),
                                style: const TextStyle(color: Colors.white70, fontSize: 13),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),

                // 2. Financial Totals Row
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Card(
                          margin: EdgeInsets.zero,
                          elevation: 1,
                          child: Padding(
                            padding: const EdgeInsets.all(10),
                            child: Column(
                              children: [
                                Text(Localization.translate('إجمالي الطلبيات', lang), style: const TextStyle(fontSize: 11, fontFamily: 'Cairo', color: Colors.grey)),
                                const SizedBox(height: 4),
                                Text(
                                  '${formatter.format(_totalDebit)} ${lang == AppLanguage.arabic ? "د.ج" : "DA"}',
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.blue),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Card(
                          margin: EdgeInsets.zero,
                          elevation: 1,
                          child: Padding(
                            padding: const EdgeInsets.all(10),
                            child: Column(
                              children: [
                                Text(Localization.translate('إجمالي المقبوضات', lang), style: const TextStyle(fontSize: 11, fontFamily: 'Cairo', color: Colors.grey)),
                                const SizedBox(height: 4),
                                Text(
                                  '${formatter.format(_totalCredit)} ${lang == AppLanguage.arabic ? "د.ج" : "DA"}',
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.green),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Card(
                          margin: EdgeInsets.zero,
                          elevation: 1,
                          child: Padding(
                            padding: const EdgeInsets.all(10),
                            child: Column(
                              children: [
                                Text(Localization.translate('الرصيد المتبقي', lang), style: const TextStyle(fontSize: 11, fontFamily: 'Cairo', color: Colors.grey)),
                                const SizedBox(height: 4),
                                Text(
                                  '${formatter.format(_netBalance)} ${lang == AppLanguage.arabic ? "د.ج" : "DA"}',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                    color: _netBalance > 0 ? Colors.red : Colors.green,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // 3. Chronological Operations Title
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        Localization.translate('السجل الزمني للمعاملات', lang),
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, fontFamily: 'Cairo', color: Theme.of(context).colorScheme.onSurface),
                      ),
                      Text(
                        '(${_ledgerItems.length} ${Localization.translate('معاملة', lang)})',
                        style: const TextStyle(fontSize: 11, color: Colors.grey, fontFamily: 'Cairo'),
                      ),
                    ],
                  ),
                ),

                // 4. Timeline list
                Expanded(
                  child: _ledgerItems.isEmpty
                      ? Center(
                          child: Text(
                            Localization.translate('لا توجد معاملات مسجلة بعد لهذا الزبون', lang),
                            style: const TextStyle(fontFamily: 'Cairo', color: Colors.grey),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          itemCount: _ledgerItems.length,
                          itemBuilder: (context, index) {
                            final item = _ledgerItems[index];
                            final String type = item['type'];
                            final date = item['date'] as DateTime;
                            final double debit = item['debit'];
                            final double credit = item['credit'];
                            final double running = item['runningBalance'];

                            // Icons and Colors based on transaction type
                            IconData avatarIcon = Icons.help;
                            Color iconColor = Colors.grey;
                            Color amountColor = Colors.black;
                            String amountPrefix = '';
                            double displayAmount = 0.0;

                            String displayLabel = '';
                            final currency = lang == AppLanguage.arabic ? 'د.ج' : 'DA';

                            if (type == 'Order') {
                              avatarIcon = Icons.receipt_long_rounded;
                              iconColor = Colors.blue;
                              amountColor = Colors.blue.shade700;
                              amountPrefix = '+';
                              displayAmount = debit;
                              displayLabel = '${Localization.translate('طلب شراء', lang)} #${item['id']}';
                            } else if (type == 'Payment') {
                              avatarIcon = Icons.check_circle_rounded;
                              iconColor = Colors.green;
                              amountColor = Colors.green.shade700;
                              amountPrefix = '-';
                              displayAmount = credit;
                              final method = item['rawData']?['payment_method']?.toString() ?? 'Espèce';
                              final methodTrans = Localization.translate(method, lang);
                              displayLabel = '${Localization.translate('دفعة مالية', lang)} ($methodTrans)';
                            } else if (type == 'Refund') {
                              avatarIcon = Icons.assignment_return_rounded;
                              iconColor = Colors.red;
                              amountColor = Colors.red.shade700;
                              amountPrefix = '+';
                              displayAmount = debit;
                              final method = item['rawData']?['payment_method']?.toString() ?? 'Espèce';
                              final methodTrans = Localization.translate(method, lang);
                              displayLabel = '${Localization.translate('مسترجع نقدي', lang)} ($methodTrans)';
                            }

                            final dateStr = DateFormat('dd/MM/yyyy HH:mm').format(date);

                            return Card(
                              elevation: 0.5,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              margin: const EdgeInsets.symmetric(vertical: 4),
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: iconColor.withOpacity(0.1),
                                  child: Icon(avatarIcon, color: iconColor, size: 20),
                                ),
                                title: Text(
                                  displayLabel,
                                  style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 13),
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(dateStr, style: const TextStyle(fontSize: 10, color: Colors.grey)),
                                    const SizedBox(height: 2),
                                    Text(
                                      '${Localization.translate('رصيد جاري', lang)}: ${formatter.format(running)} $currency',
                                      style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7), fontWeight: FontWeight.w500, fontFamily: 'Cairo'),
                                    ),
                                  ],
                                ),
                                trailing: Text(
                                  '$amountPrefix${formatter.format(displayAmount)} $currency',
                                  style: TextStyle(fontWeight: FontWeight.bold, color: amountColor, fontSize: 13),
                                ),
                                onTap: () {
                                  if (type == 'Order') {
                                    final settings = Provider.of<AppSettingsProvider>(context, listen: false);
                                    if (!settings.canViewOrderDetails()) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            Localization.translate('رؤية تفاصيل الطلبية غير مفعلة لديك', lang),
                                            style: const TextStyle(fontFamily: 'Cairo'),
                                          ),
                                          backgroundColor: Colors.orange,
                                        ),
                                      );
                                      return;
                                    }
                                    // Navigate to order details screen
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) => CommandePage(db: db, editCommandeId: item['id'] as int),
                                      ),
                                    ).then((_) {
                                      // Reload ledger data on return in case order details changed
                                      _loadLedgerData();
                                    });
                                  } else {
                                    // Open options dialog for payment/refund receipt print
                                    _showReceiptOptions(context, item['rawData'] as Map<String, dynamic>);
                                  }
                                },
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}
