import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart' hide TextDirection;
import '../settings/app_settings.dart';
import '../sql_database.dart';

class WorkerTransactionsDetailScreen extends StatefulWidget {
  final Map<String, dynamic> worker;
  final SqlDatabase db;

  const WorkerTransactionsDetailScreen({
    super.key,
    required this.worker,
    required this.db,
  });

  @override
  State<WorkerTransactionsDetailScreen> createState() =>
      _WorkerTransactionsDetailScreenState();
}

class _WorkerTransactionsDetailScreenState
    extends State<WorkerTransactionsDetailScreen> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _transactions = [];
  List<Map<String, dynamic>> _allocations = [];
  final NumberFormat _currencyFormatter = NumberFormat('#,##0.00');

  String _selectedFilter = 'All'; // All, Advance, Salary
  String _searchQuery = '';
  DateTime? _startDate;
  DateTime? _endDate;

  double _totalEarned = 0.0;
  double _totalAdvances = 0.0;
  double _netBalance = 0.0;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  String _tr(String ar, String fr, String en, AppLanguage lang) {
    switch (lang) {
      case AppLanguage.french:
        return fr;
      case AppLanguage.english:
        return en;
      case AppLanguage.arabic:
        return ar;
    }
  }

  String _formatNote(String rawNote, AppLanguage lang) {
    if (rawNote.contains('رصيد مرحل') || rawNote.contains('رصيد مرحّل')) {
      return _tr(
        'رصيد مرحل من الأسبوع السابق',
        'Solde reporté de la semaine précédente',
        'Carried forward balance from previous week',
        lang,
      );
    }
    return rawNote;
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final uid = widget.worker['uid']?.toString() ?? '';
      final empId = widget.worker['id']?.toString() ?? '';
      final email = widget.worker['email']?.toString() ?? '';

      final targetKey =
          uid.isNotEmpty ? uid : (email.isNotEmpty ? email : empId);

      // Load transactions
      final txs = await widget.db.readWorkerTransactions(targetKey);
      // Load allocations
      final allocs = await widget.db.readWorkerUnsettledAllocations(targetKey);

      double totalEarned = 0.0;
      for (var a in allocs) {
        if (a['is_manufactured'] == 1) {
          final qty = (a['quantity'] as num?)?.toDouble() ?? 0.0;
          final price = (a['worker_price'] as num?)?.toDouble() ?? 0.0;
          totalEarned += qty * price;
        }
      }

      double totalAdv = 0.0;
      for (var t in txs) {
        totalAdv += (t['amount'] as num?)?.toDouble() ?? 0.0;
      }

      if (mounted) {
        setState(() {
          _transactions = List<Map<String, dynamic>>.from(txs);
          _allocations = List<Map<String, dynamic>>.from(allocs);
          _totalEarned = totalEarned;
          _totalAdvances = totalAdv;
          _netBalance = totalEarned - totalAdv;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading worker transactions: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _showAddTransactionDialog() async {
    final amountCtrl = TextEditingController();
    final noteCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final settings = Provider.of<AppSettingsProvider>(context, listen: false);
    final lang = settings.language;

    String type = 'advance'; // advance, salary
    String paymentSource = 'الصندوق الرئيسي'; // الصندوق الرئيسي, الصندوق المفرد, الحساب البنكي / البنك, يدوي (بدون اقتطاع)

    List<String> caisseNames = ['الصندوق الرئيسي', 'الصندوق المفرد', 'الحساب البنكي / البنك', 'يدوي (بدون اقتطاع صندوق)'];
    try {
      final caissesData = await widget.db.readCaisses();
      final names = caissesData.map((c) => c['name']?.toString() ?? '').where((n) => n.isNotEmpty).toList();
      if (names.isNotEmpty) {
        caisseNames = [...names, 'الحساب البنكي / البنك', 'يدوي (بدون اقتطاع صندوق)'];
      }
    } catch (_) {}

    if (!mounted) return;

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: Text(
            _tr('إضافة معاملة جديدة للعامل', 'Nouvelle transaction ouvrier', 'New Worker Transaction', lang),
            style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 16),
          ),
          content: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Type selection
                  DropdownButtonFormField<String>(
                    value: type,
                    decoration: InputDecoration(
                      labelText: _tr('نوع المعاملة', 'Type de transaction', 'Transaction Type', lang),
                      border: const OutlineInputBorder(),
                    ),
                    items: [
                      DropdownMenuItem(
                        value: 'advance',
                        child: Text(_tr('سلفة / تسقيع', 'Avance', 'Advance', lang)),
                      ),
                      DropdownMenuItem(
                        value: 'salary',
                        child: Text(_tr('دفعة أجر / تسوية', 'Paiement salaire', 'Salary Payout', lang)),
                      ),
                    ],
                    onChanged: (v) => setDlg(() => type = v!),
                  ),
                  const SizedBox(height: 12),

                  // Payment source dropdown
                  DropdownButtonFormField<String>(
                    value: paymentSource,
                    decoration: InputDecoration(
                      labelText: _tr('مصدر الدفع / الصندوق', 'Source de paiement', 'Payment Source', lang),
                      border: const OutlineInputBorder(),
                    ),
                    items: caisseNames.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                    onChanged: (v) => setDlg(() => paymentSource = v!),
                  ),
                  const SizedBox(height: 12),

                  // Amount
                  TextFormField(
                    controller: amountCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: _tr('المبلغ (دج)', 'Montant (DA)', 'Amount (DA)', lang),
                      border: const OutlineInputBorder(),
                      suffixText: 'دج',
                    ),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return _tr('المبلغ مطلوب', 'Montant requis', 'Amount required', lang);
                      if (double.tryParse(v.trim()) == null || double.parse(v.trim()) <= 0) {
                        return _tr('أدخل مبلغاً صحيحاً', 'Montant invalide', 'Invalid amount', lang);
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),

                  // Notes
                  TextFormField(
                    controller: noteCtrl,
                    decoration: InputDecoration(
                      labelText: _tr('ملاحظات / البيان', 'Remarques / Note', 'Notes / Description', lang),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(_tr('إلغاء', 'Annuler', 'Cancel', lang)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.blue.shade700, foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(_tr('حفظ المعاملة', 'Enregistrer', 'Save Transaction', lang)),
            ),
          ],
        ),
      ),
    );

    if (result == true && mounted) {
      final amount = double.parse(amountCtrl.text.trim());
      final note = noteCtrl.text.trim();
      final uid = widget.worker['uid']?.toString() ?? '';
      final empId = widget.worker['id'] as int? ?? 0;
      final workerName = widget.worker['name']?.toString() ?? '';

      // 1. Insert into WorkerTransactions
      await widget.db.insertWorkerTransaction(
        uid,
        amount,
        type,
        note.isNotEmpty ? note : (type == 'advance' ? 'سلفة مالية' : 'دفعة أجر'),
        caisseName: paymentSource,
      );

      // 2. If source is a Treasury Caisse, record in Treasury as Décaissement
      if (!paymentSource.contains('يدوي')) {
        await widget.db.insertTreasury(
          'Décaissement',
          amount,
          'إلى العامل: $workerName - ${type == 'advance' ? 'سلفة' : 'دفعة أجر'} (${note.isNotEmpty ? note : 'بدون ملاحظات'})',
          entityType: 'Worker',
          entityId: empId,
          caisseName: paymentSource,
          recordedBy: 'system',
        );
      }

      await _loadData();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_tr('تم تسليم وسجل المعاملة بنجاح', 'Transaction enregistrée', 'Transaction recorded', lang)),
            backgroundColor: Colors.green,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<AppSettingsProvider>(context);
    final lang = settings.language;
    final isDark = settings.isDarkMode;
    final primaryColor = isDark ? Colors.blue.shade400 : Colors.blue.shade800;

    final filteredTxs = _transactions.where((t) {
      final type = t['transaction_type']?.toString() ?? '';
      final note = t['note']?.toString().toLowerCase() ?? '';
      if (_selectedFilter == 'Advance' && type != 'advance') return false;
      if (_selectedFilter == 'Salary' && type != 'salary') return false;
      if (_searchQuery.isNotEmpty) {
        if (!note.contains(_searchQuery.toLowerCase()) && !t['amount'].toString().contains(_searchQuery)) {
          return false;
        }
      }
      // ── فلتر التاريخ ───────────────────────────────────────
      if (_startDate != null || _endDate != null) {
        final createdAtStr = t['created_at']?.toString() ?? '';
        DateTime? txDate;
        try { txDate = DateTime.parse(createdAtStr); } catch (_) {}
        if (txDate == null) return false;
        if (_startDate != null && txDate.isBefore(_startDate!)) return false;
        if (_endDate != null && txDate.isAfter(DateTime(_endDate!.year, _endDate!.month, _endDate!.day, 23, 59, 59))) return false;
      }
      return true;
    }).toList();

    return Directionality(
      textDirection: lang == AppLanguage.arabic ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: isDark ? const Color(0xFF121212) : Colors.grey.shade100,
        appBar: AppBar(
          title: Text(
            '${_tr('معاملات وسلف العامل: ', 'Finances Ouvrier: ', 'Worker Finances: ', lang)}${widget.worker['name']}',
            style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 16),
          ),
          backgroundColor: primaryColor,
          foregroundColor: Colors.white,
          elevation: 0,
          actions: [
            // ── فلتر بالتاريخ ─────────────────────────────────
            IconButton(
              icon: Icon(
                (_startDate != null || _endDate != null)
                    ? Icons.date_range
                    : Icons.date_range_outlined,
                color: (_startDate != null || _endDate != null) ? Colors.amber : Colors.white,
              ),
              tooltip: _tr('فلتر بالتاريخ', 'Filtrer par date', 'Filter by date', lang),
              onPressed: () => _showDateFilterDialog(lang),
            ),
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _loadData,
              tooltip: _tr('تحديث', 'Actualiser', 'Refresh', lang),
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _showAddTransactionDialog,
          backgroundColor: Colors.blue.shade700,
          foregroundColor: Colors.white,
          icon: const Icon(Icons.add),
          label: Text(
            _tr('تسجيل سلفة / دفعة جديدة', 'Nouvelle avance/paiement', 'New Advance/Payout', lang),
            style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold),
          ),
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  // 1. Header Summary Cards
                  Container(
                    color: primaryColor,
                    padding: const EdgeInsets.only(bottom: 16, left: 12, right: 12, top: 8),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: _buildSummaryCard(
                                title: _tr('إجمالي المستحقات (المصنعة)', 'Gains (Fabriqués)', 'Total Earned', lang),
                                amount: _totalEarned,
                                icon: Icons.trending_up,
                                color: Colors.green.shade100,
                                textColor: Colors.green.shade900,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _buildSummaryCard(
                                title: _tr('إجمالي السلف والمدفوعات', 'Avances & Paiements', 'Total Advances', lang),
                                amount: _totalAdvances,
                                icon: Icons.payments,
                                color: Colors.orange.shade100,
                                textColor: Colors.orange.shade900,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        _buildSummaryCard(
                          title: _tr('صافي الرصيد المستحق للعامل', 'Solde Net Dû', 'Net Remaining Balance', lang),
                          amount: _netBalance,
                          icon: Icons.account_balance_wallet,
                          color: _netBalance >= 0 ? Colors.teal.shade100 : Colors.red.shade100,
                          textColor: _netBalance >= 0 ? Colors.teal.shade900 : Colors.red.shade900,
                          fullWidth: true,
                        ),
                      ],
                    ),
                  ),

                  // 2. Search & Filter Bar
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                    child: Column(
                      children: [
                        TextField(
                          onChanged: (v) => setState(() => _searchQuery = v),
                          decoration: InputDecoration(
                            hintText: _tr('بحث بالمبلغ أو الملاحظات...', 'Rechercher par montant ou note...', 'Search by amount or note...', lang),
                            hintStyle: const TextStyle(fontFamily: 'Cairo', fontSize: 13),
                            prefixIcon: const Icon(Icons.search, size: 20),
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                        const SizedBox(height: 8),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              _buildFilterChip('All', _tr('كل المعاملات', 'Toutes', 'All', lang)),
                              _buildFilterChip('Advance', _tr('السلفيات فقط', 'Avances seules', 'Advances Only', lang)),
                              _buildFilterChip('Salary', _tr('دفعات الأجر والتسويات', 'Paiements salaire', 'Salary Payouts', lang)),
                            ],
                          ),
                        ),
                        // ── شارة الفلتر النشط بالتاريخ ─────────────────────
                        if (_startDate != null || _endDate != null) ...[
                          const SizedBox(height: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: Colors.amber.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.amber.shade700),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.date_range, size: 14, color: Colors.amber),
                                const SizedBox(width: 4),
                                Text(
                                  '${_startDate != null ? '${_startDate!.day}/${_startDate!.month}/${_startDate!.year}' : '•••'}  →  ${_endDate != null ? '${_endDate!.day}/${_endDate!.month}/${_endDate!.year}' : '•••'}',
                                  style: const TextStyle(fontFamily: 'Cairo', fontSize: 11, color: Colors.amber, fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(width: 6),
                                GestureDetector(
                                  onTap: () => setState(() { _startDate = null; _endDate = null; }),
                                  child: const Icon(Icons.close, size: 14, color: Colors.amber),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),

                  // 3. Transactions List
                  Expanded(
                    child: filteredTxs.isEmpty
                        ? Center(
                            child: Text(
                              _tr('لا توجد معاملات مسجلة لهذا العامل', 'Aucune transaction enregistrée', 'No transactions found', lang),
                              style: const TextStyle(fontFamily: 'Cairo', fontSize: 14, color: Colors.grey),
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.all(10),
                            itemCount: filteredTxs.length,
                            itemBuilder: (context, index) {
                              final item = filteredTxs[index];
                              return _buildTransactionCard(item, isDark, lang);
                            },
                          ),
                  ),
                ],
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
    bool fullWidth = false,
  }) {
    return Container(
      width: fullWidth ? double.infinity : null,
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
                  style: TextStyle(fontFamily: 'Cairo', fontSize: 10, fontWeight: FontWeight.bold, color: textColor.withOpacity(0.8)),
                ),
                Text(
                  '${_currencyFormatter.format(amount)} دج',
                  style: TextStyle(fontFamily: 'Cairo', fontSize: 13, fontWeight: FontWeight.bold, color: textColor),
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
        label: Text(label, style: TextStyle(fontFamily: 'Cairo', fontSize: 12, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
        selected: isSelected,
        onSelected: (_) => setState(() => _selectedFilter = filterKey),
        selectedColor: Colors.blue.shade700,
        labelStyle: TextStyle(color: isSelected ? Colors.white : Colors.black87),
      ),
    );
  }

  Widget _buildTransactionCard(Map<String, dynamic> item, bool isDark, AppLanguage lang) {
    final type = item['transaction_type']?.toString() ?? 'advance';
    final amount = (item['amount'] as num?)?.toDouble() ?? 0.0;
    final note = item['note']?.toString() ?? '';
    final createdAt = item['created_at']?.toString() ?? '';
    final isSettled = (item['is_settled'] == 1 || item['is_settled'] == '1');

    DateTime date = DateTime.now();
    try {
      date = DateTime.parse(createdAt);
    } catch (_) {}

    final dateStr = DateFormat('yyyy-MM-dd HH:mm').format(date);

    final isAdvance = type == 'advance';
    final typeTitle = isAdvance
        ? _tr('سلفة مالية', 'Avance financière', 'Cash Advance', lang)
        : _tr('دفعة أجر / تسوية', 'Paiement salaire', 'Salary Settlement', lang);

    final typeColor = isAdvance ? Colors.orange.shade700 : Colors.teal.shade700;
    final iconBg = isAdvance ? Colors.orange : Colors.teal;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: iconBg,
              radius: 20,
              child: Icon(isAdvance ? Icons.money_off : Icons.task_alt, color: Colors.white, size: 20),
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
                        typeTitle,
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                      Text(
                        '- ${_currencyFormatter.format(amount)} دج',
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: typeColor,
                        ),
                      ),
                    ],
                  ),
                  if (note.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      _formatNote(note, lang),
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 12,
                        color: isDark ? Colors.grey.shade400 : Colors.grey.shade700,
                      ),
                    ),
                  ],
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '📅 $dateStr',
                        style: const TextStyle(fontSize: 10, color: Colors.grey),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: isSettled ? Colors.green.withOpacity(0.15) : Colors.amber.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: isSettled ? Colors.green : Colors.amber),
                        ),
                        child: Text(
                          isSettled
                              ? _tr('تمت المحاسبة', 'Réglé', 'Settled', lang)
                              : _tr('غير محاسب', 'Non réglé', 'Unsettled', lang),
                          style: TextStyle(
                            fontSize: 9,
                            fontFamily: 'Cairo',
                            fontWeight: FontWeight.bold,
                            color: isSettled ? Colors.green.shade800 : Colors.amber.shade900,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── ديالوج فلتر التاريخ ─────────────────────────────────────────────
  Future<void> _showDateFilterDialog(AppLanguage lang) async {
    DateTime? tempStart = _startDate;
    DateTime? tempEnd = _endDate;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: Row(
            children: [
              const Icon(Icons.date_range, color: Colors.blue),
              const SizedBox(width: 8),
              Text(
                _tr('فلتر بالتاريخ', 'Filtrer par date', 'Filter by date', lang),
                style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── تاريخ البداية ─────────────────────────────────────
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.play_arrow_rounded, color: Colors.green),
                title: Text(
                  _tr('تاريخ البداية', 'Date de début', 'Start Date', lang),
                  style: const TextStyle(fontFamily: 'Cairo', fontSize: 13),
                ),
                subtitle: Text(
                  tempStart != null
                      ? '${tempStart!.day}/${tempStart!.month}/${tempStart!.year}'
                      : _tr('غير محدد', 'Non spécifié', 'Not set', lang),
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 12,
                    color: tempStart != null ? Colors.green : Colors.grey,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                trailing: tempStart != null
                    ? IconButton(
                        icon: const Icon(Icons.close, size: 16, color: Colors.red),
                        onPressed: () => setDlg(() => tempStart = null),
                      )
                    : null,
                onTap: () async {
                  final picked = await showDatePicker(
                    context: ctx,
                    initialDate: tempStart ?? DateTime.now(),
                    firstDate: DateTime(2020),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                  );
                  if (picked != null) setDlg(() => tempStart = picked);
                },
              ),
              const Divider(),
              // ── تاريخ النهاية ──────────────────────────────────────
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.stop_rounded, color: Colors.red),
                title: Text(
                  _tr('تاريخ النهاية', 'Date de fin', 'End Date', lang),
                  style: const TextStyle(fontFamily: 'Cairo', fontSize: 13),
                ),
                subtitle: Text(
                  tempEnd != null
                      ? '${tempEnd!.day}/${tempEnd!.month}/${tempEnd!.year}'
                      : _tr('غير محدد', 'Non spécifié', 'Not set', lang),
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 12,
                    color: tempEnd != null ? Colors.red : Colors.grey,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                trailing: tempEnd != null
                    ? IconButton(
                        icon: const Icon(Icons.close, size: 16, color: Colors.red),
                        onPressed: () => setDlg(() => tempEnd = null),
                      )
                    : null,
                onTap: () async {
                  final picked = await showDatePicker(
                    context: ctx,
                    initialDate: tempEnd ?? DateTime.now(),
                    firstDate: DateTime(2020),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                  );
                  if (picked != null) setDlg(() => tempEnd = picked);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => setDlg(() { tempStart = null; tempEnd = null; }),
              child: Text(_tr('مسح الفلتر', 'Effacer', 'Clear', lang), style: const TextStyle(color: Colors.red, fontFamily: 'Cairo')),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(_tr('إلغاء', 'Annuler', 'Cancel', lang), style: const TextStyle(fontFamily: 'Cairo')),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.blue.shade700, foregroundColor: Colors.white),
              onPressed: () {
                setState(() {
                  _startDate = tempStart;
                  _endDate = tempEnd;
                });
                Navigator.pop(ctx);
              },
              child: Text(_tr('تطبيق الفلتر', 'Appliquer', 'Apply', lang), style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }
}
