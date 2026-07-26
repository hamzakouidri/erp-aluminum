import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../sql_database.dart';
import '../settings/app_settings.dart';
import '../settings/localization.dart';
import '../Commande/add_commande.dart';
import '../widgets/lazy_window_image.dart';
import 'package:intl/intl.dart';
import '../services/cloud_sync_service.dart';

String _tr(String ar, String fr, String en, AppLanguage lang) {
  if (lang == AppLanguage.french) return fr;
  if (lang == AppLanguage.english) return en;
  return ar;
}

class WorkerWeeklySettlementScreen extends StatefulWidget {
  final SqlDatabase db;
  /// وضع العرض فقط — يخفي زر تسوية الحساب
  final bool readOnly;

  const WorkerWeeklySettlementScreen({
    super.key,
    required this.db,
    this.readOnly = false,
  });

  @override
  State<WorkerWeeklySettlementScreen> createState() =>
      _WorkerWeeklySettlementScreenState();
}

class _WorkerWeeklySettlementScreenState
    extends State<WorkerWeeklySettlementScreen> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _workers = [];
  Map<String, Map<String, double>> _workerSummaries = {};
  StreamSubscription? _syncSub;

  @override
  void initState() {
    super.initState();
    _loadData();
    _syncSub = CloudSyncService().dbUpdateStream.listen((_) {
      if (mounted) {
        _loadData(silent: true);
      }
    });
  }

  @override
  void dispose() {
    _syncSub?.cancel();
    super.dispose();
  }

  Future<void> _loadData({bool silent = false}) async {
    if (!silent && _workers.isEmpty) {
      setState(() => _isLoading = true);
    }
    try {
      final rawWorkers = await widget.db.readEmployees();
      final Map<String, Map<String, double>> summaries = {};

      for (var w in rawWorkers) {
        final uid = w['uid']?.toString() ?? '';
        final empIdStr = w['id']?.toString() ?? '';
        final empEmail = w['email']?.toString() ?? '';

        final targetKey = uid.isNotEmpty ? uid : (empEmail.isNotEmpty ? empEmail : empIdStr);
        if (targetKey.isEmpty) continue;

        // 1. Unsettled work/earnings
        final allocs = await widget.db.readWorkerUnsettledAllocations(targetKey);
        double totalEarned = 0.0;
        for (var a in allocs) {
          if (a['is_manufactured'] == 1) {
            final qty = (a['quantity'] as num?)?.toDouble() ?? 0.0;
            final price = (a['worker_price'] as num?)?.toDouble() ?? 0.0;
            totalEarned += qty * price;
          }
        }

        // 2. Unsettled advances/loans
        final txs = await widget.db.readWorkerTransactions(targetKey);
        double totalAdvances = 0.0;
        for (var t in txs) {
          if (t['is_settled'] == 0 || t['is_settled'] == '0') {
            totalAdvances += (t['amount'] as num?)?.toDouble() ?? 0.0;
          }
        }

        final summaryData = {
          'earned': totalEarned,
          'advances': totalAdvances,
          'due': totalEarned - totalAdvances,
        };

        if (uid.isNotEmpty) summaries[uid] = summaryData;
        if (empIdStr.isNotEmpty) summaries[empIdStr] = summaryData;
        if (empEmail.isNotEmpty) summaries[empEmail] = summaryData;
      }

      if (mounted) {
        setState(() {
          _workers = List<Map<String, dynamic>>.from(rawWorkers);
          _workerSummaries = summaries;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading weekly settlement workers: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _confirmResetWeeklySettlementData(BuildContext context, AppLanguage lang) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          lang == AppLanguage.arabic ? 'تأكيد تصفير المحاسبة الأسبوعية' : 'Reset Settlement Data',
          style: const TextStyle(fontWeight: FontWeight.bold, fontFamily: 'Cairo'),
        ),
        content: Text(
          lang == AppLanguage.arabic 
            ? 'هل أنت تأكد من تصفير كافة تسويات وسجلات المحاسبة الأسبوعية للعمال ومستحقاتهم بالتطوير؟'
            : 'Voulez-vous réinitialiser toutes les données de règlement des ouvriers ?',
          style: const TextStyle(fontFamily: 'Cairo'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(lang == AppLanguage.arabic ? 'إلغاء' : 'Annuler'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              lang == AppLanguage.arabic ? 'مسح كلي 🧹' : 'Effacer tout 🧹',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await widget.db.clearAllWeeklySettlementsFromCloudAndLocal();
      await _loadData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(lang == AppLanguage.arabic ? 'تم تصفير ومسح بيانات المحاسبة الأسبوعية للعمال بنجاح 🧹' : 'Données de règlement réinitialisées 🧹'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final settings = Provider.of<AppSettingsProvider>(context);
    final lang = settings.language;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(
          lang == AppLanguage.arabic ? 'المحاسبة الأسبوعية للعمال' : 'Calcul Hebdomadaire',
          style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 18),
        ),
        centerTitle: true,
        backgroundColor: isDark ? Theme.of(context).appBarTheme.backgroundColor : Colors.blue,
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_sweep, color: Colors.white),
            tooltip: lang == AppLanguage.arabic ? 'تصفير المحاسبة (للتطوير)' : 'Réinitialiser règlements (Dev)',
            onPressed: () => _confirmResetWeeklySettlementData(context, lang),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            color: Colors.red.shade900,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  lang == AppLanguage.arabic ? '🧪 تصفير المحاسبة (للتطوير)' : '🧪 Réinitialiser (Dev)',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontFamily: 'Cairo', fontSize: 13),
                ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.red.shade900,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  ),
                  onPressed: () => _confirmResetWeeklySettlementData(context, lang),
                  icon: const Icon(Icons.delete_sweep, size: 18),
                  label: Text(
                    lang == AppLanguage.arabic ? 'تصفير المحاسبة 🧹' : 'Effacer Tout 🧹',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontFamily: 'Cairo', fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _workers.isEmpty
                    ? Center(
                        child: Text(
                          lang == AppLanguage.arabic ? 'لا يوجد عمال مسجلون حالياً' : 'Aucun ouvrier',
                          style: const TextStyle(fontFamily: 'Cairo', fontSize: 15),
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _loadData,
                        child: ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _workers.length,
                          itemBuilder: (context, index) {
                      final worker = _workers[index];
                      final uid = worker['uid']?.toString() ?? '';
                      final summary = _workerSummaries[uid] ??
                          {'earned': 0.0, 'advances': 0.0, 'due': 0.0};

                      final double earned = summary['earned']!;
                      final double advances = summary['advances']!;
                      final double due = summary['due']!;

                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        elevation: 2,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16)),
                        color: Theme.of(context).cardColor,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: () async {
                            await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) =>
                                    WorkerSettlementDetailScreen(
                                  worker: worker,
                                  db: widget.db,
                                  readOnly: widget.readOnly,
                                ),
                              ),
                            );
                            _loadData();
                          },
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    CircleAvatar(
                                      radius: 24,
                                      backgroundColor: isDark
                                          ? Colors.blue.shade900
                                          : Colors.blue.shade50,
                                      child: Text(
                                        (worker['name']?.toString() ?? 'U')
                                            .substring(0, 1)
                                            .toUpperCase(),
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontFamily: 'Cairo',
                                          color: isDark
                                              ? Colors.blue.shade200
                                              : Colors.blue.shade700,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            worker['name']?.toString() ?? '',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 16,
                                              fontFamily: 'Cairo',
                                            ),
                                          ),
                                          Text(
                                            worker['job_role']?.toString() ??
                                                (lang == AppLanguage.arabic
                                                    ? 'عامل'
                                                    : 'Ouvrier'),
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.grey.shade600,
                                              fontFamily: 'Cairo',
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Icon(
                                      Icons.arrow_forward_ios_rounded,
                                      size: 16,
                                      color: Colors.grey.shade400,
                                    ),
                                  ],
                                ),
                                const Divider(height: 24),
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceAround,
                                  children: [
                                    _buildSummaryItem(
                                      title: lang == AppLanguage.arabic
                                          ? 'عمل هذا الأسبوع'
                                          : 'Production',
                                      value: '$earned د.ج',
                                      color: Colors.blue.shade700,
                                    ),
                                    _buildSummaryItem(
                                      title: lang == AppLanguage.arabic
                                          ? 'سلفات وسحوبات'
                                          : 'Avances',
                                      value: '$advances د.ج',
                                      color: Colors.orange.shade700,
                                    ),
                                    _buildSummaryItem(
                                      title: lang == AppLanguage.arabic
                                          ? 'صافي المستحق'
                                          : 'Net dû',
                                      value: '$due د.ج',
                                      color: due >= 0
                                          ? Colors.green.shade700
                                          : Colors.red.shade700,
                                      isBold: true,
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryItem({
    required String title,
    required String value,
    required Color color,
    bool isBold = false,
  }) {
    return Column(
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey.shade500,
            fontFamily: 'Cairo',
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
            color: color,
            fontFamily: 'Cairo',
          ),
        ),
      ],
    );
  }
}

class WorkerSettlementDetailScreen extends StatefulWidget {
  final Map<String, dynamic> worker;
  final SqlDatabase db;
  final bool readOnly;

  const WorkerSettlementDetailScreen({
    super.key,
    required this.worker,
    required this.db,
    this.readOnly = false,
  });

  @override
  State<WorkerSettlementDetailScreen> createState() =>
      _WorkerSettlementDetailScreenState();
}

class _WorkerSettlementDetailScreenState
    extends State<WorkerSettlementDetailScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isLoading = true;

  // Current unsettled
  List<Map<String, dynamic>> _unsettledAllocs = [];
  List<Map<String, dynamic>> _unsettledTxs = [];

  // Archive (last 6 months)
  List<Map<String, dynamic>> _settledAllocs = [];
  List<Map<String, dynamic>> _settledTxs = [];

  StreamSubscription? _syncSub;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadDetails();
    _syncSub = CloudSyncService().dbUpdateStream.listen((_) {
      if (mounted) {
        _loadDetails(silent: true);
      }
    });
  }

  @override
  void dispose() {
    _syncSub?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadDetails({bool silent = false}) async {
    if (!silent && _unsettledAllocs.isEmpty && _unsettledTxs.isEmpty) {
      setState(() => _isLoading = true);
    }
    try {
      final uid = widget.worker['uid']?.toString() ?? '';
      final empIdStr = widget.worker['id']?.toString() ?? '';
      final empEmail = widget.worker['email']?.toString() ?? '';

      final targetKey = uid.isNotEmpty ? uid : (empEmail.isNotEmpty ? empEmail : empIdStr);

      // Unsettled allocations
      List<Map<String, dynamic>> uAllocs = [];
      if (targetKey.isNotEmpty) {
        uAllocs = await widget.db.readWorkerUnsettledAllocations(targetKey);
      }

      // Transactions
      List<Map<String, dynamic>> rawTxs = [];
      if (targetKey.isNotEmpty) {
        rawTxs = await widget.db.readWorkerTransactions(targetKey);
      }

      final List<Map<String, dynamic>> uTxs = [];
      for (var t in rawTxs) {
        if (t['is_settled'] == 0 || t['is_settled'] == '0') {
          uTxs.add(t);
        }
      }

      // Settled
      List<Map<String, dynamic>> sAllocs = [];
      List<Map<String, dynamic>> sTxs = [];
      if (targetKey.isNotEmpty) {
        sAllocs = await widget.db.readWorkerSettledAllocations(targetKey);
        sTxs = await widget.db.readWorkerSettledTransactions(targetKey);
      }

      if (mounted) {
        setState(() {
          _unsettledAllocs = uAllocs;
          _unsettledTxs = uTxs;
          _settledAllocs = sAllocs;
          _settledTxs = sTxs;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading worker accounting details: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _showPaymentDialog(double netDue) async {
    final payCtrl = TextEditingController(text: netDue.toString());
    final formKey = GlobalKey<FormState>();
    final settings = Provider.of<AppSettingsProvider>(context, listen: false);
    final lang = settings.language;

    List<String> caisseNames = ['الصندوق الرئيسي', 'الصندوق المفرد', 'الحساب البنكي / البنك'];
    try {
      final caissesData = await widget.db.readCaisses();
      final names = caissesData.map((c) => c['name']?.toString() ?? '').where((n) => n.isNotEmpty).toList();
      if (names.isNotEmpty) {
        caisseNames = names;
        if (!caisseNames.contains('الحساب البنكي / البنك')) {
          caisseNames.add('الحساب البنكي / البنك');
        }
      }
    } catch (_) {}

    String selectedCaisse = caisseNames.first;

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) => AlertDialog(
          title: Text(
            _tr('تسجيل دفعة وتسوية الحساب', 'Enregistrer un paiement & régler', 'Record Payment & Settle Account', lang),
            style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 16),
          ),
          content: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${_tr("صافي المستحق للعامل:", "Solde net dû à l'ouvrier:", "Net due to worker:", lang)} ${NumberFormat('#,##0.00').format(netDue)} د.ج\n${_tr("المبلغ المكتوب أدناه سيسجل بالكامل كدفع في الصندوق المختار.", "Le montant ci-dessous sera intégralement déduit de la caisse sélectionnée.", "The amount below will be fully recorded as a payout in the selected caisse.", lang)}',
                    style: const TextStyle(fontFamily: 'Cairo', fontSize: 13),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: payCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: _tr('المبلغ المدفوع فعلياً (د.ج)', 'Montant payé (DZD)', 'Actual Amount Paid (DZD)', lang),
                      border: const OutlineInputBorder(),
                    ),
                    validator: (val) {
                      if (val == null || val.trim().isEmpty) return _tr('يرجى إدخال المبلغ', 'Veuillez entrer le montant', 'Please enter amount', lang);
                      if (double.tryParse(val.trim()) == null) return _tr('الرجاء إدخال رقم صحيح', 'Veuillez entrer un nombre valide', 'Please enter a valid number', lang);
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    value: selectedCaisse,
                    decoration: InputDecoration(
                      labelText: _tr('الدفع من صندوق / الخزينة', 'Caisse de paiement', 'Pay from Caisse', lang),
                      border: const OutlineInputBorder(),
                    ),
                    items: caisseNames
                        .map((cName) => DropdownMenuItem<String>(
                              value: cName,
                              child: Text(
                                Localization.translate(cName, lang),
                                style: const TextStyle(fontFamily: 'Cairo', fontSize: 13),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ))
                        .toList(),
                    onChanged: (val) {
                      if (val != null) {
                        setStateDialog(() => selectedCaisse = val);
                      }
                    },
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(_tr('إلغاء', 'Annuler', 'Cancel', lang), style: const TextStyle(fontFamily: 'Cairo')),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF059669),
                foregroundColor: Colors.white,
              ),
              onPressed: () async {
                if (formKey.currentState!.validate()) {
                  final amt = double.parse(payCtrl.text.trim());
                  Navigator.pop(context);

                  setState(() => _isLoading = true);

                  await widget.db.settleWorkerWeek(
                    widget.worker['uid']?.toString() ?? '',
                    (widget.worker['id'] as num?)?.toInt() ?? 0,
                    amt,
                    settings.userDisplayName,
                    widget.worker['name']?.toString() ?? '',
                    caisseName: selectedCaisse,
                  );

                  await _loadDetails();
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(_tr('تمت تسوية أسبوع العامل بنجاح وخصم المبلغ من الصندوق', 'Règlement effectué avec succès et déduit de la caisse', 'Worker settlement successfully recorded and deducted from Caisse', lang)),
                        backgroundColor: Colors.green,
                      ),
                    );
                  }
                }
              },
              child: Text(_tr('تسوية ودفع', 'Régler & Payer', 'Settle & Pay', lang), style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDateTime(String? isoString) {
    if (isoString == null || isoString.isEmpty) return '';
    try {
      final dt = DateTime.parse(isoString);
      final dayNames = {
        DateTime.monday: 'الإثنين',
        DateTime.tuesday: 'الثلاثاء',
        DateTime.wednesday: 'الأربعاء',
        DateTime.thursday: 'الخميس',
        DateTime.friday: 'الجمعة',
        DateTime.saturday: 'السبت',
        DateTime.sunday: 'الأحد',
      };
      final dayName = dayNames[dt.weekday] ?? '';
      final timeStr = '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
      final dateStr = '${dt.day}/${dt.month}/${dt.year}';
      return '$dayName - الساعة $timeStr - $dateStr';
    } catch (_) {
      return isoString;
    }
  }

  void _showAllocationDetailsDialog(Map<String, dynamic> alloc) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final settings = Provider.of<AppSettingsProvider>(context, listen: false);
    final lang = settings.language;

    final windowType = alloc['window_type']?.toString() ?? 'Window';
    final int largeur = (alloc['largeur'] as num?)?.toInt() ?? 0;
    final int hauteur = (alloc['hauteur'] as num?)?.toInt() ?? 0;
    final int qty = (alloc['quantity'] as num?)?.toInt() ?? 0;
    final color = alloc['color']?.toString() ?? '';
    final glass = alloc['glass']?.toString() ?? '';
    final clientName = '${alloc['firstname'] ?? ''} ${alloc['lastname'] ?? ''}'.trim();
    final double currentPrice = (alloc['worker_price'] as num?)?.toDouble() ?? 0.0;
    final int detailId = (alloc['commande_detail_id'] as num?)?.toInt() ?? 0;
    final int allocId = (alloc['id'] as num?)?.toInt() ?? 0;
    final int cmdId = (alloc['id_commandes'] as num?)?.toInt() ?? 0;
    
    final priceCtrl = TextEditingController(text: currentPrice > 0 ? currentPrice.toString() : '');
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              scrollable: true,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Row(
                children: [
                  const Icon(Icons.info_outline, color: Colors.blue),
                  const SizedBox(width: 8),
                  Text(
                    lang == AppLanguage.arabic ? 'تفاصيل النافذة المنجزة' : 'Détails de l\'ouvrage',
                    style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ],
              ),
              content: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Window image preview
                    Container(
                      height: 150,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF0F172A) : Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.all(8),
                      child: LazyWindowImage(
                        db: widget.db,
                        detailId: detailId,
                        initialImagePath: alloc['drawing_image_path']?.toString() ?? '',
                        partitionsJson: alloc['partitions_json'],
                        drawingImageBase64: alloc['drawing_image_base64']?.toString(),
                        height: 130,
                        width: double.infinity,
                        fit: BoxFit.contain,
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Dimensions and details
                    Text(
                      '${Localization.translate(windowType, lang)} ($largeur x $hauteur مم)',
                      style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    const SizedBox(height: 6),
                    if (color.isNotEmpty) ...[
                      Text('${lang == AppLanguage.arabic ? "اللون:" : "Couleur:"} $color', style: const TextStyle(fontSize: 12)),
                      const SizedBox(height: 2),
                    ],
                    if (glass.isNotEmpty) ...[
                      Text('${lang == AppLanguage.arabic ? "الزجاج:" : "Vitrage:"} $glass', style: const TextStyle(fontSize: 12)),
                      const SizedBox(height: 2),
                    ],
                    Text('${lang == AppLanguage.arabic ? "الكمية المنجزة:" : "Quantité réalisée:"} $qty ${lang == AppLanguage.arabic ? "قطع" : "pcs"}', style: const TextStyle(fontSize: 12)),
                    const SizedBox(height: 2),
                    Text(
                      '${lang == AppLanguage.arabic ? "حالة التصنيع:" : "Statut:"} ${alloc['is_manufactured'] == 1 ? (lang == AppLanguage.arabic ? "تم التصنيع ✅" : "Terminé") : (lang == AppLanguage.arabic ? "لم يتم التصنيع بعد ⏳" : "En cours")}',
                      style: TextStyle(
                        fontSize: 12,
                        color: alloc['is_manufactured'] == 1 ? Colors.green : Colors.orange,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'Cairo',
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${lang == AppLanguage.arabic ? "الأجر المحتسب:" : "Gain:"} ${alloc['is_manufactured'] == 1 ? "${qty * currentPrice} د.ج" : (lang == AppLanguage.arabic ? "0 د.ج (غير مصنع بعد)" : "0 DA (non fabriqué)")}',
                      style: TextStyle(
                        fontSize: 12,
                        color: alloc['is_manufactured'] == 1 ? Colors.blue : Colors.blueGrey,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'Cairo',
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${lang == AppLanguage.arabic ? "اسم الزبون:" : "Client:"} ${clientName.isNotEmpty ? clientName : (lang == AppLanguage.arabic ? "غير محدد" : "Non spécifié")}',
                      style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 12, color: Colors.blueGrey),
                    ),
                    const Divider(height: 20),

                    // Price input section
                    if (currentPrice == 0.0) ...[
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.orange.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                lang == AppLanguage.arabic 
                                  ? 'سعر العامل غير مدخل! لن يتم احتسابه في المستحقات حتى تحدد سعراً.'
                                  : 'Prix ouvrier non défini !',
                                style: const TextStyle(fontFamily: 'Cairo', fontSize: 11, color: Colors.orange, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],

                    TextFormField(
                      controller: priceCtrl,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: lang == AppLanguage.arabic ? 'أجر تصنيع القطعة الواحدة (د.ج)' : 'Tarif par pièce (DA)',
                        border: const OutlineInputBorder(),
                        prefixIcon: const Icon(Icons.monetization_on_outlined, size: 20),
                      ),
                      validator: (val) {
                        if (val == null || val.trim().isEmpty) {
                          return lang == AppLanguage.arabic ? 'يرجى إدخال السعر' : 'Entrez le tarif';
                        }
                        if (double.tryParse(val.trim()) == null) {
                          return lang == AppLanguage.arabic ? 'أدخل رقماً صحيحاً' : 'Nombre invalide';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.blue,
                          side: const BorderSide(color: Colors.blue),
                        ),
                        onPressed: () {
                          Navigator.pop(context);
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => CommandePage(
                                db: widget.db,
                                editCommandeId: cmdId,
                              ),
                            ),
                          );
                        },
                        icon: const Icon(Icons.folder_open_outlined, size: 18),
                        label: Text(
                          lang == AppLanguage.arabic ? 'الذهاب إلى صفحة الطلبية بالكامل' : 'Voir la commande complète',
                          style: const TextStyle(fontFamily: 'Cairo', fontSize: 12),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(lang == AppLanguage.arabic ? 'إلغاء' : 'Annuler', style: const TextStyle(fontFamily: 'Cairo')),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () async {
                    if (formKey.currentState!.validate()) {
                      final newPrice = double.parse(priceCtrl.text.trim());
                      Navigator.pop(context);
                      
                      setState(() => _isLoading = true);
                      await widget.db.updateWorkerAllocationPrice(allocId, newPrice);
                      await _loadDetails();

                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(lang == AppLanguage.arabic ? 'تم تحديث أجر العامل بنجاح 💰' : 'Tarif mis à jour successfully'),
                            backgroundColor: Colors.green,
                          ),
                        );
                      }
                    }
                  },
                  child: Text(lang == AppLanguage.arabic ? 'حفظ السعر' : 'Enregistrer', style: const TextStyle(fontFamily: 'Cairo')),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final settings = Provider.of<AppSettingsProvider>(context);
    final lang = settings.language;

    // Calculate unsettled totals
    double earnedTotal = 0.0;
    for (var a in _unsettledAllocs) {
      if (a['is_manufactured'] == 1) {
        final q = (a['quantity'] as num?)?.toDouble() ?? 0.0;
        final p = (a['worker_price'] as num?)?.toDouble() ?? 0.0;
        earnedTotal += q * p;
      }
    }

    double advancesTotal = 0.0;
    for (var t in _unsettledTxs) {
      advancesTotal += (t['amount'] as num?)?.toDouble() ?? 0.0;
    }

    final double netDue = earnedTotal - advancesTotal;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(
          widget.worker['name']?.toString() ?? '',
          style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 18),
        ),
        bottom: TabBar(
          controller: _tabController,
          labelStyle: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold),
          unselectedLabelStyle: const TextStyle(fontFamily: 'Cairo'),
          tabs: [
            Tab(text: lang == AppLanguage.arabic ? 'الأسبوع الحالي' : 'Semaine Actuelle'),
            Tab(text: lang == AppLanguage.arabic ? 'الأرشيف (آخر 6 أشهر)' : 'Archives'),
          ],
        ),
        backgroundColor: isDark ? Theme.of(context).appBarTheme.backgroundColor : Colors.blue,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                // TAB 1: Current Week (Unsettled)
                Column(
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Section: Manufactured items
                            Text(
                              lang == AppLanguage.arabic ? '🛠️ النوافذ والأبواب المنجزة هذا الأسبوع:' : 'Ouvrages réalisés:',
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontFamily: 'Cairo',
                                  fontSize: 15,
                                  color: Colors.blue),
                            ),
                            const SizedBox(height: 8),
                            _unsettledAllocs.isEmpty
                                ? Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.all(16),
                                    decoration: BoxDecoration(
                                      color: isDark ? Colors.grey[900] : Colors.grey[100],
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      lang == AppLanguage.arabic
                                          ? 'لم يتم تسجيل عمل منجز هذا الأسبوع بعد'
                                          : 'Aucun travail enregistré',
                                      style: const TextStyle(
                                          fontFamily: 'Cairo',
                                          fontSize: 13,
                                          color: Colors.grey),
                                      textAlign: TextAlign.center,
                                    ),
                                  )
                                : ListView.builder(
                                    shrinkWrap: true,
                                    physics: const NeverScrollableScrollPhysics(),
                                    itemCount: _unsettledAllocs.length,
                                    itemBuilder: (context, idx) {
                                      final a = _unsettledAllocs[idx];
                                      final windowType = a['window_type']?.toString() ?? 'Window';
                                      final int largeur = (a['largeur'] as num?)?.toInt() ?? 0;
                                      final int hauteur = (a['hauteur'] as num?)?.toInt() ?? 0;
                                      final int qty = (a['quantity'] as num?)?.toInt() ?? 0;
                                      final price = (a['worker_price'] as num?)?.toDouble() ?? 0.0;
                                      final total = qty * price;
                                      final dateStr = _formatDateTime(a['assigned_at']);

                                      return Card(
                                        margin: const EdgeInsets.only(bottom: 8),
                                        elevation: 1,
                                        shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(12)),
                                        child: ListTile(
                                          title: Text(
                                            '${Localization.translate(windowType, lang)} ($largeur x $hauteur) | $qty قطعة',
                                            style: const TextStyle(
                                                fontFamily: 'Cairo',
                                                fontWeight: FontWeight.bold,
                                                fontSize: 13),
                                          ),
                                          subtitle: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                'الزبون: ${a['firstname'] ?? ''} ${a['lastname'] ?? ''}'.trim().isNotEmpty 
                                                    ? 'الزبون: ${a['firstname'] ?? ''} ${a['lastname'] ?? ''}'.trim()
                                                    : 'الزبون: غير محدد',
                                                style: const TextStyle(
                                                    fontFamily: 'Cairo',
                                                    fontWeight: FontWeight.bold,
                                                    color: Colors.blueGrey,
                                                    fontSize: 12),
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                price == 0.0
                                                    ? '⚠️ السعر غير مدخل!'
                                                    : (a['is_manufactured'] == 1 
                                                        ? 'سعر القطعة: $price د.ج | المجموع: $total د.ج' 
                                                        : 'سعر القطعة: $price د.ج | المجموع: 0 د.ج (لم تصنع بعد ⏳)'),
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  color: price == 0.0 ? Colors.red : (a['is_manufactured'] == 1 ? null : Colors.orange),
                                                  fontWeight: price == 0.0 ? FontWeight.bold : null,
                                                ),
                                              ),
                                              Text(
                                                '📅 $dateStr',
                                                style: const TextStyle(fontSize: 11),
                                              ),
                                              const SizedBox(height: 4),
                                              Row(
                                                children: [
                                                  Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                    decoration: BoxDecoration(
                                                      color: a['is_manufactured'] == 1 ? Colors.green.withOpacity(0.12) : Colors.orange.withOpacity(0.12),
                                                      borderRadius: BorderRadius.circular(6),
                                                    ),
                                                    child: Text(
                                                      a['is_manufactured'] == 1 ? 'تم الصنع ✅' : 'لم يصنع بعد ⏳',
                                                      style: TextStyle(
                                                        color: a['is_manufactured'] == 1 ? Colors.green : Colors.orange,
                                                        fontSize: 11,
                                                        fontWeight: FontWeight.bold,
                                                        fontFamily: 'Cairo',
                                                      ),
                                                    ),
                                                  ),
                                                  const SizedBox(width: 6),
                                                  Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                    decoration: BoxDecoration(
                                                      color: a['is_glass_installed'] == 1 ? Colors.blue.withOpacity(0.12) : Colors.orange.withOpacity(0.12),
                                                      borderRadius: BorderRadius.circular(6),
                                                    ),
                                                    child: Text(
                                                      a['is_glass_installed'] == 1 ? 'تم تركيب الزجاج 💎' : 'لم يركب الزجاج ⏳',
                                                      style: TextStyle(
                                                        color: a['is_glass_installed'] == 1 ? Colors.blue : Colors.orange,
                                                        fontSize: 11,
                                                        fontWeight: FontWeight.bold,
                                                        fontFamily: 'Cairo',
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
                                          leading: price == 0.0
                                              ? TextButton.icon(
                                                  style: TextButton.styleFrom(
                                                    foregroundColor: Colors.red,
                                                    backgroundColor: Colors.red.withOpacity(0.08),
                                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                    shape: RoundedRectangleBorder(
                                                      borderRadius: BorderRadius.circular(8),
                                                    ),
                                                  ),
                                                  onPressed: () => _showAllocationDetailsDialog(a),
                                                  icon: const Icon(Icons.edit, size: 14),
                                                  label: const Text(
                                                    'إدخال السعر',
                                                    style: TextStyle(fontFamily: 'Cairo', fontSize: 11, fontWeight: FontWeight.bold),
                                                  ),
                                                )
                                              : const Icon(Icons.open_in_new, size: 16, color: Colors.blue),
                                          onTap: () => _showAllocationDetailsDialog(a),
                                        ),
                                      );
                                    },
                                  ),

                            const SizedBox(height: 24),

                            // Section: Advances / Transactions
                            Text(
                              lang == AppLanguage.arabic ? '💰 سلفات ومدفوعات هذا الأسبوع:' : 'Avances de la semaine:',
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontFamily: 'Cairo',
                                  fontSize: 15,
                                  color: Colors.orange),
                            ),
                            const SizedBox(height: 8),
                            _unsettledTxs.isEmpty
                                ? Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.all(16),
                                    decoration: BoxDecoration(
                                      color: isDark ? Colors.grey[900] : Colors.grey[100],
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      lang == AppLanguage.arabic
                                          ? 'لا توجد سلفات مسجلة هذا الأسبوع'
                                          : 'Aucune avance cette semaine',
                                      style: const TextStyle(
                                          fontFamily: 'Cairo',
                                          fontSize: 13,
                                          color: Colors.grey),
                                      textAlign: TextAlign.center,
                                    ),
                                  )
                                : ListView.builder(
                                    shrinkWrap: true,
                                    physics: const NeverScrollableScrollPhysics(),
                                    itemCount: _unsettledTxs.length,
                                    itemBuilder: (context, idx) {
                                      final t = _unsettledTxs[idx];
                                      final amt = (t['amount'] as num?)?.toDouble() ?? 0.0;
                                      final note = t['note']?.toString() ?? '';
                                      final type = t['transaction_type'] == 'advance'
                                          ? 'سلفة'
                                          : 'دفعة أجر';
                                      final dateStr = t['created_at'] != null
                                          ? t['created_at'].toString().split('T')[0]
                                          : '';

                                      return Card(
                                        margin: const EdgeInsets.only(bottom: 8),
                                        elevation: 1,
                                        shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(12)),
                                        child: ListTile(
                                          title: Text(
                                            '$amt د.ج ($type)',
                                            style: const TextStyle(
                                                fontFamily: 'Cairo',
                                                fontWeight: FontWeight.bold,
                                                fontSize: 13,
                                                color: Colors.red),
                                          ),
                                          subtitle: Text(
                                            '$note\n📅 $dateStr',
                                            style: const TextStyle(fontSize: 11),
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                          ],
                        ),
                      ),
                    ),
                    // Net accounting summary and Settle button
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: isDark ? Colors.grey[900] : Colors.grey[100],
                        border: Border(
                          top: BorderSide(
                              color: isDark
                                  ? Colors.grey.shade800
                                  : Colors.grey.shade300),
                        ),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                lang == AppLanguage.arabic ? 'صافي المستحق للأسبوع:' : 'Net dû pour la semaine :',
                                style: const TextStyle(
                                    fontFamily: 'Cairo',
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15),
                              ),
                              Text(
                                '$netDue د.ج',
                                style: TextStyle(
                                  fontFamily: 'Cairo',
                                  fontWeight: FontWeight.bold,
                                  fontSize: 18,
                                  color: netDue >= 0
                                      ? Colors.green.shade600
                                      : Colors.red.shade600,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          if (!widget.readOnly)
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                onPressed: () => _showPaymentDialog(netDue),
                                icon: const Icon(Icons.handshake),
                                label: Text(
                                  lang == AppLanguage.arabic
                                      ? 'تسجيل دفعة وتسوية الحساب'
                                      : 'Enregistrer paiement & Clôturer',
                                  style: const TextStyle(
                                      fontFamily: 'Cairo',
                                      fontWeight: FontWeight.bold),
                                ),
                                style: ElevatedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                  backgroundColor: Colors.teal,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),

                // TAB 2: Archives (Settled)
                SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Section: Settled items
                      Text(
                        lang == AppLanguage.arabic ? '🛠️ الأعمال المؤرشفة المسواة (آخر 6 أشهر):' : 'Travaux archivés (6 mois) :',
                        style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontFamily: 'Cairo',
                            fontSize: 15,
                            color: Colors.blueGrey),
                      ),
                      const SizedBox(height: 8),
                      _settledAllocs.isEmpty
                          ? Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: isDark ? Colors.grey[900] : Colors.grey[100],
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                lang == AppLanguage.arabic
                                    ? 'لا يوجد أرشيف أعمال لهذا العامل'
                                    : 'Aucune archive disponible',
                                style: const TextStyle(
                                    fontFamily: 'Cairo',
                                    fontSize: 13,
                                    color: Colors.grey),
                                textAlign: TextAlign.center,
                              ),
                            )
                          : ListView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: _settledAllocs.length,
                              itemBuilder: (context, idx) {
                                final a = _settledAllocs[idx];
                                final windowType = a['window_type']?.toString() ?? 'Window';
                                final int largeur = (a['largeur'] as num?)?.toInt() ?? 0;
                                final int hauteur = (a['hauteur'] as num?)?.toInt() ?? 0;
                                final int qty = (a['quantity'] as num?)?.toInt() ?? 0;
                                final price = (a['worker_price'] as num?)?.toDouble() ?? 0.0;
                                final total = qty * price;
                                final dateStr = _formatDateTime(a['settled_at']);

                                return Card(
                                  margin: const EdgeInsets.only(bottom: 8),
                                  elevation: 1,
                                  color: isDark ? Colors.grey[900] : Colors.grey[50],
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12)),
                                  child: ListTile(
                                    title: Text(
                                      '${Localization.translate(windowType, lang)} ($largeur x $hauteur) | $qty قطعة',
                                      style: const TextStyle(
                                          fontFamily: 'Cairo',
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13),
                                    ),
                                    subtitle: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'الزبون: ${a['firstname'] ?? ''} ${a['lastname'] ?? ''}'.trim().isNotEmpty 
                                              ? 'الزبون: ${a['firstname'] ?? ''} ${a['lastname'] ?? ''}'.trim()
                                              : 'الزبون: غير محدد',
                                          style: const TextStyle(
                                              fontFamily: 'Cairo',
                                              fontWeight: FontWeight.bold,
                                              color: Colors.blueGrey,
                                              fontSize: 12),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          'سعر القطعة: $price د.ج | المجموع: $total د.ج\n📅 تاريخ التسوية: $dateStr',
                                          style: const TextStyle(fontSize: 11),
                                        ),
                                      ],
                                    ),
                                    leading: price == 0.0
                                        ? TextButton.icon(
                                            style: TextButton.styleFrom(
                                              foregroundColor: Colors.red,
                                              backgroundColor: Colors.red.withOpacity(0.08),
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                              shape: RoundedRectangleBorder(
                                                borderRadius: BorderRadius.circular(8),
                                              ),
                                            ),
                                            onPressed: () => _showAllocationDetailsDialog(a),
                                            icon: const Icon(Icons.edit, size: 14),
                                            label: const Text(
                                              'إدخال السعر',
                                              style: TextStyle(fontFamily: 'Cairo', fontSize: 11, fontWeight: FontWeight.bold),
                                            ),
                                          )
                                        : const Icon(Icons.open_in_new, size: 16, color: Colors.blue),
                                    onTap: () => _showAllocationDetailsDialog(a),
                                  ),
                                );
                              },
                            ),

                      const SizedBox(height: 24),

                      // Section: Settled Transactions
                      Text(
                        lang == AppLanguage.arabic ? '💰 المدفوعات والسلف المؤرشفة (آخر 6 أشهر):' : 'Transactions archivées (6 mois) :',
                        style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontFamily: 'Cairo',
                            fontSize: 15,
                            color: Colors.blueGrey),
                      ),
                      const SizedBox(height: 8),
                      _settledTxs.isEmpty
                          ? Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: isDark ? Colors.grey[900] : Colors.grey[100],
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                lang == AppLanguage.arabic
                                    ? 'لا يوجد أرشيف مدفوعات لهذا العامل'
                                    : 'Aucune archive disponible',
                                style: const TextStyle(
                                    fontFamily: 'Cairo',
                                    fontSize: 13,
                                    color: Colors.grey),
                                textAlign: TextAlign.center,
                              ),
                            )
                          : ListView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: _settledTxs.length,
                              itemBuilder: (context, idx) {
                                final t = _settledTxs[idx];
                                final amt = (t['amount'] as num?)?.toDouble() ?? 0.0;
                                final note = t['note']?.toString() ?? '';
                                final dateStr = _formatDateTime(t['settled_at']);

                                return Card(
                                  margin: const EdgeInsets.only(bottom: 8),
                                  elevation: 1,
                                  color: isDark ? Colors.grey[900] : Colors.grey[50],
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12)),
                                  child: ListTile(
                                    title: Text(
                                      '$amt د.ج',
                                      style: const TextStyle(
                                          fontFamily: 'Cairo',
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13),
                                    ),
                                    subtitle: Text(
                                      '$note\n📅 تاريخ التسوية: $dateStr',
                                      style: const TextStyle(fontSize: 11),
                                    ),
                                  ),
                                );
                              },
                            ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}
