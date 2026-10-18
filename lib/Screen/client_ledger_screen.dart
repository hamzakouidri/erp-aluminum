import 'package:database_data/widgets/app_material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../sql_database.dart';
import '../settings/localization.dart';
import '../settings/app_settings.dart';
import 'dart:convert';
import '../Commande/order_workspace_screen.dart';
import '../Commande/devis_builder.dart';
import '../Commande/devis_preview_screen.dart';
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
  List<Map<String, dynamic>> _ordersList = [];
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
      final ordersList = await myDb.query(
        'Commandes',
        where: 'client_id = ? AND (is_deleted IS NULL OR is_deleted = 0)',
        whereArgs: [widget.clientId],
      );
      _ordersList = ordersList;

      // 3. Get Client Payments (Treasury)
      // Shop payments settle shop documents, not the window orders listed
      // here; counting them made the client look in credit.
      final treasuryList = await myDb.query(
        'Treasury',
        where:
            "entity_type = 'Client' AND entity_id = ? "
            'AND (document_type IS NULL OR document_type != ?)',
        whereArgs: [widget.clientId, SqlDatabase.materialSaleDocumentType],
      );

      // 4. Load Order details if detailed view is used (we pre-fetch details for all orders)
      // One query for all orders instead of one query per order.
      final Map<int, List<Map<String, dynamic>>> orderDetailsMap = {};
      final orderIds = [for (final order in ordersList) order['id'] as int];
      const chunkSize = 500; // SQLite bound-variable limit.
      for (var start = 0; start < orderIds.length; start += chunkSize) {
        final chunk = orderIds.sublist(
          start,
          (start + chunkSize).clamp(0, orderIds.length),
        );
        final details = await myDb.query(
          'Commandes_details',
          where:
              'id_commandes IN (${List.filled(chunk.length, '?').join(', ')})',
          whereArgs: chunk,
        );
        for (final detail in details) {
          final orderId = (detail['id_commandes'] as num?)?.toInt();
          if (orderId == null) continue;
          orderDetailsMap.putIfAbsent(orderId, () => []).add(detail);
        }
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
        final displayCode = (order['order_code'] as num?)?.toInt() ??
            (order['display_number'] as num?)?.toInt() ??
            (orderId < 100000 ? orderId : '?');

        tempItems.add({
          'id': orderId,
          'displayCode': displayCode,
          'date': date,
          'type': 'Order',
          'label': 'طلب شراء / Commande #$displayCode',
          'debit': amount,
          'credit': 0.0,
          'details': orderDetailsMap[orderId] ?? [],
          'rawData': order,
        });
      }

      // 3.5. Get Client Deliveries (Commandes_deliveries)
      List<Map<String, dynamic>> deliveriesList = [];
      try {
        deliveriesList = await myDb.rawQuery('''
          SELECT d.*, c.order_code, c.order_code AS display_number, COALESCE(p.name, '') AS project_name, c.status as order_status
          FROM Commandes_deliveries d
          LEFT JOIN Commandes c ON CAST(d.id_commandes AS TEXT) = CAST(c.id AS TEXT)
          LEFT JOIN Projects p ON c.project_id = p.id
          WHERE (c.is_deleted IS NULL OR c.is_deleted = 0)
            AND (CAST(d.client_id AS TEXT) = ? OR CAST(c.client_id AS TEXT) = ? OR d.id_commandes IN (SELECT id FROM Commandes WHERE client_id = ? AND (is_deleted IS NULL OR is_deleted = 0)))
          ORDER BY d.id DESC
        ''', [widget.clientId.toString(), widget.clientId.toString(), widget.clientId]);
      } catch (e) {
        debugPrint('Error loading deliveries in ledger: $e');
      }

      for (var d in deliveriesList) {
        final dateStr = d['delivery_date']?.toString() ?? '';
        DateTime date = DateTime.now();
        try {
          date = DateTime.parse(dateStr);
        } catch (_) {
          try {
            date = DateFormat('yyyy-MM-dd HH:mm').parse(dateStr);
          } catch (_) {}
        }

        final orderId = (d['id_commandes'] as num?)?.toInt() ?? 0;
        final matchingOrder = ordersList.firstWhere(
          (o) => (o['id'] as num?)?.toInt() == orderId,
          orElse: () => <String, dynamic>{},
        );
        final orderDisplayCode = (matchingOrder['order_code'] as num?)?.toInt() ??
            (d['order_code'] as num?)?.toInt() ??
            (orderId < 100000 && orderId > 0 ? orderId : '?');

        final deliveryId = (d['id'] as num?)?.toInt() ?? 0;
        final isLoaded = (d['is_loaded'] as num?)?.toInt() == 1;

        tempItems.add({
          'id': deliveryId,
          'orderId': orderId,
          'displayCode': orderDisplayCode,
          'date': date,
          'type': 'Delivery',
          'label': 'وصل تسليم / Bon de livraison #$deliveryId (الطلبية #$orderDisplayCode)',
          'debit': 0.0,
          'credit': 0.0,
          'isLoaded': isLoaded,
          'details': null,
          'rawData': d,
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

  Future<void> _openDeliveryPreview(Map<String, dynamic> delivery) async {
    final orderId = (delivery['id_commandes'] as num?)?.toInt() ?? 0;
    final order = _ordersList.firstWhere(
      (o) => (o['id'] as num?)?.toInt() == orderId,
      orElse: () => <String, dynamic>{},
    );
    if (order.isEmpty) return;

    List<Map<String, dynamic>> items = [];
    try {
      final raw = jsonDecode(delivery['items_json']?.toString() ?? '[]');
      if (raw is List) {
        items = raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }
    } catch (_) {}

    final workshop = await DevisBuilder.loadWorkshopInfo().timeout(
      const Duration(seconds: 10),
      onTimeout: () => DevisWorkshopInfo.empty,
    );

    final orderStatus = (order['status'] ?? '').toString();
    final bool isPartial = (delivery['is_partial'] as num?)?.toInt() == 1 ||
        orderStatus == 'Partial Distribution';

    final devis = await DevisBuilder.build(
      order: order,
      items: items,
      workshop: workshop,
      isPartial: isPartial,
      documentTitleKey: isPartial ? 'doc_bon_livraison_partiel' : 'doc_bon_livraison',
    );

    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => DevisPreviewScreen(
          data: devis,
          deliveryId: delivery['id'] as int?,
          initialIsLoaded: (delivery['is_loaded'] as num?)?.toInt() == 1,
        ),
      ),
    ).then((_) => _loadLedgerData());
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
                              displayLabel = '${Localization.translate('طلب شراء', lang)} #${item['displayCode'] ?? item['id']}';
                            } else if (type == 'Delivery') {
                              avatarIcon = Icons.local_shipping_rounded;
                              iconColor = Colors.teal;
                              amountColor = Colors.teal.shade700;
                              amountPrefix = '';
                              displayAmount = 0.0;
                              final orderCode = item['displayCode'] ?? '';
                              final delivId = item['id'];
                              displayLabel = lang == AppLanguage.french
                                  ? 'Bon de livraison #$delivId (Cmd #$orderCode)'
                                  : '${Localization.translate('وصل تسليم (BL)', lang)} #$delivId (${Localization.translate('الطلبية', lang)} #$orderCode)';
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
                                    if (type != 'Delivery')
                                      Text(
                                        '${Localization.translate('رصيد جاري', lang)}: ${formatter.format(running)} $currency',
                                        style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7), fontWeight: FontWeight.w500, fontFamily: 'Cairo'),
                                      )
                                    else
                                      Text(
                                        lang == AppLanguage.french ? 'Marchandise sortie / livrée' : 'تم خروج وتسليم السلع للزبون',
                                        style: TextStyle(fontSize: 11, color: Colors.teal.shade700, fontWeight: FontWeight.w500, fontFamily: 'Cairo'),
                                      ),
                                  ],
                                ),
                                trailing: type == 'Delivery'
                                    ? Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: (item['isLoaded'] == true ? Colors.green : Colors.teal).withOpacity(0.12),
                                          borderRadius: BorderRadius.circular(8),
                                          border: Border.all(
                                            color: (item['isLoaded'] == true ? Colors.green : Colors.teal).shade300,
                                            width: 0.8,
                                          ),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              item['isLoaded'] == true ? Icons.check_circle : Icons.inventory_2_outlined,
                                              size: 13,
                                              color: (item['isLoaded'] == true ? Colors.green : Colors.teal).shade700,
                                            ),
                                            const SizedBox(width: 4),
                                            Text(
                                              item['isLoaded'] == true
                                                  ? (lang == AppLanguage.french ? 'Livré' : 'مُسلَّم')
                                                  : (lang == AppLanguage.french ? 'En cours' : 'قيد التسليم'),
                                              style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 11,
                                                color: (item['isLoaded'] == true ? Colors.green : Colors.teal).shade800,
                                                fontFamily: 'Cairo',
                                              ),
                                            ),
                                          ],
                                        ),
                                      )
                                    : Text(
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
                                    openOrderInWorkspaceTab(
                                      context,
                                      db: db,
                                      editCommandeId: item['id'] as int,
                                      onSaved: _loadLedgerData,
                                    );
                                  } else if (type == 'Delivery') {
                                    _openDeliveryPreview(item['rawData'] as Map<String, dynamic>);
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
