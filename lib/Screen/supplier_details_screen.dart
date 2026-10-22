import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart' hide TextDirection;
import '../services/cloud_sync_service.dart';
import '../settings/app_settings.dart';
import '../sql_database.dart';
import 'achat_details_screen.dart';
import 'app_workspace_shell.dart';
import 'supplier_ledger_pdf_service.dart';
import 'receipt_pdf_service.dart';
import 'supplier_card_view.dart';

class SupplierDetailsScreen extends StatefulWidget {
  final Map<String, dynamic> supplier;

  const SupplierDetailsScreen({super.key, required this.supplier});

  @override
  State<SupplierDetailsScreen> createState() => _SupplierDetailsScreenState();
}

class _SupplierDetailsScreenState extends State<SupplierDetailsScreen> {
  final SqlDatabase db = SqlDatabase();
  final formatter = NumberFormat('#,##0.00');

  List<Map<String, dynamic>> _ledgerItems = [];
  bool _isLoading = true;
  String _selectedFilter = 'All'; // All, Purchase, Payment, Return
  String _searchQuery = '';

  double _totalPurchases = 0.0;
  double _totalPaid = 0.0;
  double _totalReturns = 0.0;
  double _remainingDebt = 0.0;
  StreamSubscription? _syncSub;

  @override
  void initState() {
    super.initState();
    _loadLedgerData();
    _syncSub = CloudSyncService().dbUpdateStream.listen((_) {
      if (mounted) {
        _loadLedgerData();
      }
    });
  }

  @override
  void dispose() {
    _syncSub?.cancel();
    super.dispose();
  }

  String _tr(String ar, String fr, String en, AppLanguage lang) {
    switch (lang) {
      case AppLanguage.french:
        return fr;
      case AppLanguage.arabic:
        return ar;
      default:
        return en;
    }
  }

  Future<void> _loadLedgerData() async {
    setState(() => _isLoading = true);

    try {
      await db.migrateLegacyTreasuryRecords();
      final myDb = await db.db;
      final supplierId = widget.supplier['id'] as int;
      final supplierName = widget.supplier['name']?.toString() ?? '';

      // 1. Fetch Purchases (Achats)
      final achatsList = await myDb!.query(
        'Achats',
        where: 'supplier_id = ? OR supplier_name = ?',
        whereArgs: [supplierId, supplierName],
      );

      // 2. Fetch Supplier Payments (Treasury)
      final treasuryList = await myDb.query(
        'Treasury',
        where:
            "(entity_type = 'Supplier' AND entity_id = ?) OR (description LIKE ?)",
        whereArgs: [supplierId, '%$supplierName%'],
      );

      final List<Map<String, dynamic>> tempItems = [];
      double tPurchases = 0.0;
      double tPaid = 0.0;
      double tReturns = 0.0;

      // Process Purchases
      for (var a in achatsList) {
        final double total = (a['total'] as num?)?.toDouble() ?? 0.0;
        final double paid = (a['paid_amount'] as num?)?.toDouble() ?? 0.0;
        final String createdAt = a['created_at']?.toString() ?? '';
        DateTime date = DateTime.now();
        try {
          date = DateTime.parse(createdAt);
        } catch (_) {}

        tPurchases += total;

        tempItems.add({
          'id': a['id'],
          'date': date,
          'type': 'Purchase',
          'typeLabel': 'فاتورة شراء / Achat',
          'number': a['invoice_number']?.toString() ?? a['id'].toString(),
          'description': 'فاتورة مشتريات #${a['invoice_number'] ?? a['id']}',
          'debit': total, // Debit = Purchase amount owed
          'credit': 0.0,
          'paid': paid,
          'status': a['status'] ?? 'Active',
          'raw': a,
        });
      }

      // Process Payments & Refunds from Treasury
      for (var t in treasuryList) {
        final double amount = (t['amount'] as num?)?.toDouble() ?? 0.0;
        final String type = t['transaction_type']?.toString() ?? '';
        final String desc = t['description']?.toString() ?? '';
        final String createdAt = t['created_at']?.toString() ?? '';
        DateTime date = DateTime.now();
        try {
          date = DateTime.parse(createdAt);
        } catch (_) {}

        if (type == 'Décaissement' ||
            type == 'DÃ©caissement' ||
            desc.contains('للمورد') ||
            desc.contains('تسديد')) {
          tPaid += amount;
          tempItems.add({
            'id': t['id'],
            'date': date,
            'type': 'Payment',
            'typeLabel': 'دفعة للمورد / Paiement',
            'number': (t['id'] is num && (t['id'] as num) < 100000)
                ? t['id'].toString()
                : '—',
            'description': desc.isEmpty ? 'تسديد دفعة للمورد' : desc,
            'debit': 0.0,
            'credit': amount, // Credit = Paid to supplier
            'paid': amount,
            'caisse': t['caisse_name'] ?? 'الصندوق الرئيسي',
            'paymentMethod': t['payment_method'] ?? 'نقداً / Espèce',
            'raw': t,
          });
        } else if (type == 'Encaissement' || desc.contains('استرجاع')) {
          tReturns += amount;
          tempItems.add({
            'id': t['id'],
            'date': date,
            'type': 'Return',
            'typeLabel': 'إرجاع مشتريات / Retour',
            'number': (t['id'] is num && (t['id'] as num) < 100000)
                ? t['id'].toString()
                : '—',
            'description': desc.isEmpty ? 'استرجاع مشتريات من المورد' : desc,
            'debit': 0.0,
            'credit': amount, // Credit = Refund received from supplier
            'paid': amount,
            'caisse': t['caisse_name'] ?? 'الصندوق الرئيسي',
            'raw': t,
          });
        }
      }

      // Sort items chronologically (newest first)
      tempItems.sort(
        (a, b) => (b['date'] as DateTime).compareTo(a['date'] as DateTime),
      );

      if (mounted) {
        setState(() {
          _ledgerItems = tempItems;
          _totalPurchases = tPurchases;
          _totalPaid = tPaid;
          _totalReturns = tReturns;
          // A supplier refund reduces the net amount paid, so it is added
          // back when calculating what remains due to that supplier.
          _remainingDebt = tPurchases - tPaid + tReturns;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading supplier ledger: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showReceiptOptions(BuildContext context, Map<String, dynamic> item) {
    final settings = Provider.of<AppSettingsProvider>(context, listen: false);
    final lang = settings.language;
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.print, color: Colors.teal),
                title: Text(
                  _tr('طباعة الوصل', 'Imprimer reçu', 'Print Receipt', lang),
                  style: const TextStyle(
                    fontFamily: 'Cairo',
                    fontWeight: FontWeight.bold,
                  ),
                ),
                onTap: () async {
                  Navigator.pop(ctx);
                  await ReceiptPdfService.printReceiptWithFeedback(
                    item,
                    context,
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.share, color: Colors.orange),
                title: Text(
                  _tr('مشاركة', 'Partager', 'Share', lang),
                  style: const TextStyle(
                    fontFamily: 'Cairo',
                    fontWeight: FontWeight.bold,
                  ),
                ),
                onTap: () async {
                  Navigator.pop(ctx);
                  await ReceiptPdfService.shareReceiptWithFeedback(
                    item,
                    context,
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.download, color: Colors.blue),
                title: Text(
                  _tr('حفظ الوصل', 'Enregistrer reçu', 'Save Receipt', lang),
                  style: const TextStyle(
                    fontFamily: 'Cairo',
                    fontWeight: FontWeight.bold,
                  ),
                ),
                onTap: () async {
                  Navigator.pop(ctx);
                  await ReceiptPdfService.saveReceiptWithFeedback(
                    item,
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

  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<AppSettingsProvider>(context);
    final lang = settings.language;
    final isDark = settings.isDarkMode;
    final primaryColor = isDark ? Colors.blue.shade400 : Colors.blue.shade800;

    final filteredItems = _ledgerItems.where((item) {
      if (_selectedFilter != 'All' && item['type'] != _selectedFilter) {
        return false;
      }
      if (_searchQuery.isNotEmpty) {
        final query = _searchQuery.toLowerCase();
        final desc = item['description']?.toString().toLowerCase() ?? '';
        final numStr = item['number']?.toString().toLowerCase() ?? '';
        return desc.contains(query) || numStr.contains(query);
      }
      return true;
    }).toList();

    return Directionality(
      textDirection: lang == AppLanguage.arabic
          ? TextDirection.rtl
          : TextDirection.ltr,
      child: DefaultTabController(
        length: 2,
        child: Scaffold(
          backgroundColor: isDark
              ? const Color(0xFF121212)
              : Colors.grey.shade100,
          appBar: AppBar(
            title: Text(
              '${_tr('بطاقة المورد: ', 'Fiche fournisseur : ', 'Supplier card: ', lang)}${widget.supplier['name']}',
              style: const TextStyle(
                fontFamily: 'Cairo',
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            backgroundColor: primaryColor,
            foregroundColor: Colors.white,
            elevation: 0,
            bottom: TabBar(
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white70,
              indicatorColor: Colors.white,
              tabs: [
                Tab(
                  icon: const Icon(Icons.badge_rounded),
                  text: _tr('البطاقة', 'Fiche', 'Card', lang),
                ),
                Tab(
                  icon: const Icon(Icons.account_balance_wallet_rounded),
                  text: _tr(
                    'كشف الحساب',
                    'Extrait de compte',
                    'Statement',
                    lang,
                  ),
                ),
              ],
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.refresh, color: Colors.white),
                tooltip: _tr('تحديث', 'Actualiser', 'Refresh', lang),
                onPressed: () async {
                  await CloudSyncService().syncPendingNow();
                  _loadLedgerData();
                },
              ),
              PopupMenuButton<String>(
                icon: const Icon(Icons.picture_as_pdf, color: Colors.white),
                tooltip: _tr(
                  'تصدير كشف الحساب',
                  'Exporter extrait',
                  'Export Statement',
                  lang,
                ),
                onSelected: (val) {
                  if (val == 'print') {
                    SupplierLedgerPdfService.printSupplierLedger(
                      widget.supplier,
                      _ledgerItems,
                      lang: lang,
                    );
                  } else if (val == 'share') {
                    SupplierLedgerPdfService.shareSupplierLedger(
                      widget.supplier,
                      _ledgerItems,
                      lang: lang,
                    );
                  } else if (val == 'save') {
                    SupplierLedgerPdfService.saveSupplierLedger(
                      widget.supplier,
                      _ledgerItems,
                      context,
                      lang: lang,
                    );
                  }
                },
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: 'print',
                    child: Row(
                      children: [
                        const Icon(Icons.print, color: Colors.teal),
                        const SizedBox(width: 10),
                        Text(
                          _tr('طباعة PDF', 'Imprimer PDF', 'Print PDF', lang),
                          style: const TextStyle(fontFamily: 'Cairo'),
                        ),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'share',
                    child: Row(
                      children: [
                        const Icon(Icons.share, color: Colors.orange),
                        const SizedBox(width: 10),
                        Text(
                          _tr('مشاركة PDF', 'Partager PDF', 'Share PDF', lang),
                          style: const TextStyle(fontFamily: 'Cairo'),
                        ),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'save',
                    child: Row(
                      children: [
                        const Icon(Icons.download, color: Colors.blue),
                        const SizedBox(width: 10),
                        Text(
                          _tr('حفظ PDF', 'Enregistrer PDF', 'Save PDF', lang),
                          style: const TextStyle(fontFamily: 'Cairo'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
          body: TabBarView(
            children: [
              SupplierCardView(db: db, supplier: widget.supplier),
              _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : Column(
                      children: [
                        // 1. Header Summary Cards
                        Container(
                          color: primaryColor,
                          padding: const EdgeInsets.only(
                            bottom: 16,
                            left: 12,
                            right: 12,
                            top: 8,
                          ),
                          child: Column(
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: _buildSummaryCard(
                                      title: _tr(
                                        'إجمالي المشتريات',
                                        'Total Achats',
                                        'Total Purchases',
                                        lang,
                                      ),
                                      amount: _totalPurchases,
                                      icon: Icons.shopping_cart,
                                      color: Colors.blue.shade100,
                                      textColor: Colors.blue.shade900,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: _buildSummaryCard(
                                      title: _tr(
                                        'المدفوع',
                                        'Total Payé',
                                        'Total Paid',
                                        lang,
                                      ),
                                      amount: _totalPaid,
                                      icon: Icons.payments,
                                      color: Colors.green.shade100,
                                      textColor: Colors.green.shade900,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Expanded(
                                    child: _buildSummaryCard(
                                      title: _tr(
                                        'المرتجعات',
                                        'Total Retours',
                                        'Total Returns',
                                        lang,
                                      ),
                                      amount: _totalReturns,
                                      icon: Icons.settings_backup_restore,
                                      color: Colors.orange.shade100,
                                      textColor: Colors.orange.shade900,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: _buildSummaryCard(
                                      title: _tr(
                                        'الديون / المستحق',
                                        'Solde Dû',
                                        'Remaining Due',
                                        lang,
                                      ),
                                      amount: _remainingDebt,
                                      icon: Icons.account_balance_wallet,
                                      color: _remainingDebt > 0
                                          ? Colors.red.shade100
                                          : Colors.teal.shade100,
                                      textColor: _remainingDebt > 0
                                          ? Colors.red.shade900
                                          : Colors.teal.shade900,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),

                        // 2. Search & Filter Bar
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          color: isDark
                              ? const Color(0xFF1E1E1E)
                              : Colors.white,
                          child: Column(
                            children: [
                              TextField(
                                onChanged: (v) =>
                                    setState(() => _searchQuery = v),
                                decoration: InputDecoration(
                                  hintText: _tr(
                                    'بحث برقم الفاتورة أو الوصف...',
                                    'Rechercher par N° ou description...',
                                    'Search invoice or desc...',
                                    lang,
                                  ),
                                  hintStyle: const TextStyle(
                                    fontFamily: 'Cairo',
                                    fontSize: 13,
                                  ),
                                  prefixIcon: const Icon(
                                    Icons.search,
                                    size: 20,
                                  ),
                                  isDense: true,
                                  contentPadding: const EdgeInsets.symmetric(
                                    vertical: 10,
                                    horizontal: 12,
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: Row(
                                  children: [
                                    _buildFilterChip(
                                      'All',
                                      _tr('الكل', 'Tous', 'All', lang),
                                    ),
                                    _buildFilterChip(
                                      'Purchase',
                                      _tr(
                                        'فواتير الشراء',
                                        'Achats',
                                        'Purchases',
                                        lang,
                                      ),
                                    ),
                                    _buildFilterChip(
                                      'Payment',
                                      _tr(
                                        'المدفوعات',
                                        'Paiements',
                                        'Payments',
                                        lang,
                                      ),
                                    ),
                                    _buildFilterChip(
                                      'Return',
                                      _tr(
                                        'المرتجعات',
                                        'Retours',
                                        'Returns',
                                        lang,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),

                        // 3. Transactions List
                        Expanded(
                          child: filteredItems.isEmpty
                              ? Center(
                                  child: Text(
                                    _tr(
                                      'لا توجد معاملات مسجلة لهذا المورد',
                                      'Aucune transaction trouvée',
                                      'No transactions found',
                                      lang,
                                    ),
                                    style: const TextStyle(
                                      fontFamily: 'Cairo',
                                      fontSize: 14,
                                      color: Colors.grey,
                                    ),
                                  ),
                                )
                              : ListView.builder(
                                  padding: const EdgeInsets.all(10),
                                  itemCount: filteredItems.length,
                                  itemBuilder: (context, index) {
                                    final item = filteredItems[index];
                                    return _buildTransactionCard(
                                      item,
                                      isDark,
                                      lang,
                                    );
                                  },
                                ),
                        ),
                      ],
                    ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSummaryCard({
    required String title,
    required double amount,
    required IconData icon,
    required Color color,
    required Color textColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(icon, color: textColor, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: textColor.withOpacity(0.8),
                  ),
                ),
                Text(
                  '${formatter.format(amount)} دج',
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: textColor,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String filterKey, String label) {
    final isSelected = _selectedFilter == filterKey;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ChoiceChip(
        label: Text(
          label,
          style: TextStyle(
            fontFamily: 'Cairo',
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
        selected: isSelected,
        onSelected: (_) => setState(() => _selectedFilter = filterKey),
        selectedColor: Colors.blue.shade700,
        labelStyle: TextStyle(
          color: isSelected ? Colors.white : Colors.black87,
        ),
      ),
    );
  }

  Widget _buildTransactionCard(
    Map<String, dynamic> item,
    bool isDark,
    AppLanguage lang,
  ) {
    final String type = item['type'] ?? '';
    final double debit = (item['debit'] as num?)?.toDouble() ?? 0.0;
    final double credit = (item['credit'] as num?)?.toDouble() ?? 0.0;
    final DateTime date = item['date'] as DateTime;
    final String dateStr = DateFormat('yyyy-MM-dd HH:mm').format(date);
    final String typeLabel = item['typeLabel'] ?? '';
    final String description = item['description'] ?? '';

    IconData icon;
    Color iconBg;
    Color amountColor;
    String amountText;

    if (type == 'Purchase') {
      icon = Icons.shopping_bag;
      iconBg = Colors.blue;
      amountColor = Colors.blue.shade700;
      amountText = '+ ${formatter.format(debit)} دج';
    } else if (type == 'Payment') {
      icon = Icons.payment;
      iconBg = Colors.green;
      amountColor = Colors.green.shade700;
      amountText = '- ${formatter.format(credit)} دج';
    } else {
      icon = Icons.replay;
      iconBg = Colors.orange;
      amountColor = Colors.orange.shade700;
      amountText = '- ${formatter.format(credit)} دج';
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          if (type == 'Purchase') {
            final raw = item['raw'] as Map<String, dynamic>;
            final invoiceNumber = raw['invoice_number']?.toString() ?? '';
            final supplierName = widget.supplier['name']?.toString() ?? '';
            openAdaptiveScreen(
              context,
              title: '$supplierName • Détails des achats #$invoiceNumber',
              icon: Icons.receipt_long_rounded,
              entryId: 'achat_details_${raw['id']}',
              screen: AchatDetailsScreen(
                achatId: raw['id'],
                invoiceNumber: invoiceNumber,
                supplierName: supplierName,
              ),
            );
            _loadLedgerData();
          } else if (type == 'Payment' || type == 'Return') {
            final raw = item['raw'] as Map<String, dynamic>;
            _showReceiptOptions(context, raw);
          }
        },
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: iconBg,
                radius: 20,
                child: Icon(icon, color: Colors.white, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          typeLabel,
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                        ),
                        Text(
                          amountText,
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: amountColor,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      description,
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 12,
                        color: isDark
                            ? Colors.grey.shade400
                            : Colors.grey.shade700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '📅 $dateStr',
                          style: const TextStyle(
                            fontSize: 10,
                            color: Colors.grey,
                          ),
                        ),
                        Row(
                          children: [
                            Text(
                              _tr(
                                'تفاعلي - انقر للتفاصيل ➔',
                                'Cliquer pour détails ➔',
                                'Click for details ➔',
                                lang,
                              ),
                              style: TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 10,
                                color: Colors.blue.shade400,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
