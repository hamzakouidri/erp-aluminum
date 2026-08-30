import 'dart:io';
import 'dart:convert';
import 'dart:async';
import 'dart:typed_data';
import 'package:database_data/sql_database.dart';
import 'package:database_data/services/cloud_sync_service.dart';
import 'package:flutter/material.dart';
import 'package:database_data/Commande/order_workspace_screen.dart';
import 'package:database_data/settings/localization.dart';
import 'package:database_data/settings/app_settings.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:database_data/Commande/pdf_fiche_coupe_api.dart';
import 'package:database_data/Commande/order_date_utils.dart';
import 'package:database_data/Commande/devis_builder.dart';
import 'package:database_data/Commande/devis_preview_screen.dart';
import 'package:database_data/Commande/capture_image.dart';
import 'package:database_data/Commande/order_picture_pdf_service.dart';
import 'package:database_data/Commande/Systeme/model.dart';
import 'package:database_data/Commande/Systeme/model_serialization.dart';
import 'package:database_data/Commande/order_required_goods_screen.dart';
import 'package:database_data/Commande/order_measurements_confirm_screen.dart';
import 'package:database_data/Commande/partial_proforma_screen.dart';
import 'package:database_data/Screen/order_allocation_screen.dart';
import 'package:database_data/widgets/resizable_columns_table.dart';
import 'package:database_data/widgets/numeric_filter_search_field.dart';
import 'package:database_data/widgets/table_date_range_filter.dart';

class Commande extends StatefulWidget {
  /// Opens the normal new-order form after the orders page has appeared.
  /// The dashboard uses this so its add action behaves like the page action.
  final bool openAddOrderOnStart;

  const Commande({super.key, this.openAddOrderOnStart = false});

  @override
  State<Commande> createState() => _CommandeState();
}

class _CommandeState extends State<Commande> {
  final SqlDatabase db = SqlDatabase();
  final ScrollController _scrollController = ScrollController();
  late Future<List<Map<String, dynamic>>> _data;
  List<Map<String, dynamic>>? _cachedCommandes;
  String _searchQuery = '';
  BuildContext? _loadingDialogContext;
  StreamSubscription? _dbUpdateSubscription;
  Timer? _syncRefreshDebounce;
  bool _permissionRedirectScheduled = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final settings = Provider.of<AppSettingsProvider>(context);
    if (settings.isManager || settings.canViewOrders()) {
      _permissionRedirectScheduled = false;
      return;
    }

    // didChangeDependencies can run more than once while a route is closing.
    // Capture the navigator while this context is active; do not look it up
    // from the deactivated page context in the post-frame callback.
    if (_permissionRedirectScheduled) return;
    _permissionRedirectScheduled = true;
    final navigator = Navigator.maybeOf(context);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _permissionRedirectScheduled = false;
      if (!mounted || navigator == null || !navigator.mounted) return;
      if (navigator.canPop()) {
        navigator.pop();
      }
    });
  }

  String formatDate(Map<String, dynamic> order) {
    return formatOrderDate(order['created_at'], fallback: order['updated_at']);
  }

  String _translateStatus(String status, AppLanguage lang) {
    return Localization.translate(status, lang);
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'Confirmed':
        return const Color(0xFF2E7D32); // أخضر داكن
      case 'Pending':
        return const Color(0xFFE65100); // برتقالي
      case 'In Progress':
        return const Color(0xFF1565C0); // أزرق
      case 'Partial Manufacturing':
        return const Color(0xFF0288D1); // أزرق فاتح
      case 'Full Manufacturing':
        return const Color(0xFF00796B); // تيل داكن
      case 'Partial Distribution':
        return const Color(0xFFF57C00); // برتقالي داكن
      case 'Full Distribution':
        return const Color(0xFF388E3C); // أخضر
      case 'Installation':
        return const Color(0xFF6A1B9A); // بنفسجي
      case 'Reserve':
        return const Color(0xFFD84315); // برتقالي محروق / تحت التحفظ
      case 'Done':
        return const Color(0xFF00695C); // تيل/أخضر مائل
      case 'New':
      default:
        return const Color(0xFF546E7A); // رمادي مزرق
    }
  }

  int _displayOrderNumber(Map<String, dynamic> order) {
    for (final key in const ['display_number', 'order_code']) {
      final value = order[key];
      final number = value is num
          ? value.toInt()
          : int.tryParse(value?.toString().trim() ?? '');
      if (number != null && number > 0) return number;
    }
    final id = order['id'];
    return id is num ? id.toInt() : int.tryParse(id?.toString() ?? '') ?? 0;
  }

  String _displayOrderLabel(Map<String, dynamic> order) =>
      '#${_displayOrderNumber(order)}';

  double _readMoney(dynamic value) {
    if (value is num) return value.toDouble();
    final normalized = value?.toString().trim().replaceAll(',', '.') ?? '';
    return double.tryParse(normalized) ?? 0.0;
  }

  int? _readId(dynamic value) {
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString().trim() ?? '');
  }

  String _orderClientName(Map<String, dynamic> order) {
    final direct =
        order['client_name']?.toString().trim() ??
        order['client_display']?.toString().trim() ??
        '';
    if (direct.isNotEmpty) return direct;
    final first = order['firstname']?.toString().trim() ?? '';
    final last = order['lastname']?.toString().trim() ?? '';
    final full = '$first $last'.trim();
    return full.isEmpty ? 'Client' : full;
  }

  void _showAddOrderPaymentDialog(
    Map<String, dynamic> orderData,
    AppLanguage lang,
  ) {
    final orderId = _readId(orderData['id']);
    final clientId = _readId(orderData['client_id']);
    if (orderId == null || clientId == null) return;

    final total = _readMoney(orderData['net_payable'] ?? orderData['total']);
    final paid = _readMoney(orderData['advance_payment']);
    final remaining = (total - paid).clamp(0.0, double.infinity).toDouble();
    final clientName = _orderClientName(orderData);
    final amountCtrl = TextEditingController();
    final settings = Provider.of<AppSettingsProvider>(context, listen: false);
    var isSavingPayment = false;

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          title: Text(
            '${Localization.translate('Add payment to order', lang)} ${_displayOrderLabel(orderData)}',
            style: const TextStyle(
              fontFamily: 'Cairo',
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          content: TextField(
            controller: amountCtrl,
            autofocus: true,
            enabled: !isSavingPayment,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: Localization.translate('Amount paid', lang),
              hintText:
                  '${Localization.translate('Remaining:', lang)} ${remaining.toStringAsFixed(2)} د.ج',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              prefixIcon: const Icon(Icons.payments_outlined),
            ),
          ),
          actions: [
            TextButton(
              onPressed: isSavingPayment
                  ? null
                  : () => Navigator.pop(dialogContext),
              child: Text(Localization.translate('Cancel', lang)),
            ),
            ElevatedButton(
              onPressed: isSavingPayment
                  ? null
                  : () async {
                      final amount = _readMoney(amountCtrl.text);
                      if (amount <= 0) return;

                      final navigator = Navigator.of(dialogContext);
                      setDialogState(() => isSavingPayment = true);
                      try {
                        await db.insertTreasury(
                          'Encaissement',
                          amount,
                          'دفعة لطلبية رقم $orderId من الزبون: $clientName',
                          referenceId: orderId,
                          entityType: 'Client',
                          entityId: clientId,
                          recordedBy: settings.userDisplayName,
                        );
                        if (navigator.mounted && navigator.canPop()) {
                          navigator.pop();
                        }
                        if (mounted) _fetchCommandes();
                      } catch (error) {
                        if (dialogContext.mounted) {
                          setDialogState(() => isSavingPayment = false);
                        }
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                '${Localization.translate('فشل حفظ الدفعة', lang)}: $error',
                              ),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      }
                    },
              child: isSavingPayment
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(Localization.translate('Save payment', lang)),
            ),
          ],
        ),
      ),
    ).whenComplete(amountCtrl.dispose);
  }

  TextSpan highlightText(String text, String query) {
    if (query.isEmpty) {
      return TextSpan(text: text);
    }

    List<String> queryWords = query
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((s) => s.isNotEmpty)
        .toList();
    if (queryWords.isEmpty) return TextSpan(text: text);

    String pattern = queryWords.map((w) => RegExp.escape(w)).join('|');
    RegExp regExp = RegExp('($pattern)', caseSensitive: false);

    List<TextSpan> spans = [];
    int start = 0;
    for (var match in regExp.allMatches(text)) {
      if (match.start > start) {
        spans.add(TextSpan(text: text.substring(start, match.start)));
      }
      spans.add(
        TextSpan(
          text: match.group(0),
          style: TextStyle(
            color: Colors.blue,
            fontWeight: FontWeight.bold,
            backgroundColor: Colors.yellow.withValues(alpha: 0.3),
          ),
        ),
      );
      start = match.end;
    }
    if (start < text.length) {
      spans.add(TextSpan(text: text.substring(start)));
    }

    return TextSpan(children: spans);
  }

  @override
  void initState() {
    super.initState();
    _fetchCommandes();
    _dbUpdateSubscription = CloudSyncService().dbUpdateStream.listen((_) {
      _scheduleCloudRefresh();
    });
    if (widget.openAddOrderOnStart) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _openNewOrderForm();
      });
    }
  }

  Future<void> _openNewOrderForm() async {
    await openOrderInWorkspaceTab(context, db: db, onSaved: _fetchCommandes);
  }

  void _fetchCommandes() {
    final future = db.readCommandesWithClients();
    _data = future.then((list) {
      if (mounted) {
        setState(() {
          _cachedCommandes = list;
        });
      }
      return list;
    });
  }

  /// SQLite result lists can be read-only. Replacing the active list keeps
  /// the user on the same page and preserves the current scroll position.
  void _removeCommandeFromView(Object? commandeId) {
    final current = _cachedCommandes ?? const <Map<String, dynamic>>[];
    final remaining = current
        .where((commande) => commande['id'].toString() != commandeId.toString())
        .map((commande) => Map<String, dynamic>.from(commande))
        .toList(growable: false);

    setState(() {
      _cachedCommandes = remaining;
      _data = Future<List<Map<String, dynamic>>>.value(remaining);
    });
  }

  void _scheduleCloudRefresh() {
    _syncRefreshDebounce?.cancel();
    _syncRefreshDebounce = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      _fetchCommandes();
    });
  }

  final Map<String, TextEditingController> _orderColumnControllers = {
    'id': TextEditingController(),
    'client_project': TextEditingController(),
    'date': TextEditingController(),
    'total': TextEditingController(),
    'advance': TextEditingController(),
    'remaining': TextEditingController(),
    'status': TextEditingController(),
    'creator': TextEditingController(),
  };
  final Map<String, NumericFilterState> _orderNumericFilters = {};
  TableDateRange _orderDateRange = const TableDateRange();

  String? _orderSortColumn;
  bool _orderSortAscending = true;

  @override
  void dispose() {
    _syncRefreshDebounce?.cancel();
    _dbUpdateSubscription?.cancel();
    _scrollController.dispose();
    for (final controller in _orderColumnControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _clearAllOrderColumnFilters() {
    setState(() {
      for (final controller in _orderColumnControllers.values) {
        controller.clear();
      }
      _orderSortColumn = null;
      _orderSortAscending = true;
    });
  }

  bool get _hasActiveOrderColumnFilters {
    return _orderSortColumn != null ||
        _orderDateRange.isActive ||
        _orderNumericFilters.values.any((f) => f.isActive) ||
        _orderColumnControllers.values.any((c) => c.text.trim().isNotEmpty);
  }

  List<Map<String, dynamic>> _applyOrderFiltersAndSort(
    List<Map<String, dynamic>> rawData,
    AppLanguage lang,
  ) {
    List<Map<String, dynamic>> filtered = rawData.where((d) {
      final query = _searchQuery.toLowerCase().trim();
      if (query.isNotEmpty) {
        final first = (d['firstname'] ?? '').toString().toLowerCase();
        final last = (d['lastname'] ?? '').toString().toLowerCase();
        final phone = (d['phone'] ?? '').toString().toLowerCase();
        final full = '$first $last $phone';
        if (!query.split(' ').every((term) => full.contains(term))) {
          return false;
        }
      }

      // Date Range Filter
      if (_orderDateRange.isActive) {
        final dStr = (d['created_at'] ?? d['date'] ?? '').toString();
        final dt = DateTime.tryParse(dStr);
        if (!_orderDateRange.isWithinRange(dt)) return false;
      }

      // Numeric Filters (id, total, advance, remaining)
      if (_orderNumericFilters['id']?.isActive == true) {
        final idNum = (d['id'] as num?)?.toDouble() ?? 0.0;
        if (!_orderNumericFilters['id']!.matches(idNum)) return false;
      }

      final netPayable =
          (d['net_payable'] as num?)?.toDouble() ??
          (d['total'] as num?)?.toDouble() ??
          0.0;
      final advance = (d['advance_payment'] as num?)?.toDouble() ?? 0.0;
      final remaining = netPayable - advance;

      if (_orderNumericFilters['total']?.isActive == true) {
        if (!_orderNumericFilters['total']!.matches(netPayable)) return false;
      }
      if (_orderNumericFilters['advance']?.isActive == true) {
        if (!_orderNumericFilters['advance']!.matches(advance)) return false;
      }
      if (_orderNumericFilters['remaining']?.isActive == true) {
        if (!_orderNumericFilters['remaining']!.matches(remaining))
          return false;
      }

      // Text column filters
      for (final entry in _orderColumnControllers.entries) {
        final colKey = entry.key;
        final filterVal = entry.value.text.toLowerCase().trim();
        if (filterVal.isEmpty) continue;

        switch (colKey) {
          case 'id':
            if (_orderNumericFilters['id']?.isActive != true) {
              final idStr = (d['id'] ?? '').toString().toLowerCase();
              if (!idStr.contains(filterVal)) return false;
            }
            break;
          case 'client_project':
            final clientFirst = (d['firstname'] ?? '').toString().toLowerCase();
            final clientLast = (d['lastname'] ?? '').toString().toLowerCase();
            final clientName = '$clientFirst $clientLast'.trim();
            final projectName = (d['project_name'] ?? '')
                .toString()
                .toLowerCase();
            final cpStr = '$clientName $projectName'.trim();
            if (!cpStr.contains(filterVal)) return false;
            break;
          case 'date':
            final dt = formatDate(d).toLowerCase();
            if (!dt.contains(filterVal)) return false;
            break;
          case 'total':
            if (_orderNumericFilters['total']?.isActive != true) {
              final tStr = netPayable.toStringAsFixed(0);
              if (!tStr.contains(filterVal)) return false;
            }
            break;
          case 'advance':
            if (_orderNumericFilters['advance']?.isActive != true) {
              final aStr = advance.toStringAsFixed(0);
              if (!aStr.contains(filterVal)) return false;
            }
            break;
          case 'remaining':
            if (_orderNumericFilters['remaining']?.isActive != true) {
              final rStr = remaining.toStringAsFixed(0);
              if (!rStr.contains(filterVal)) return false;
            }
            break;
          case 'status':
            final rawStatus = (d['status'] ?? 'Pending').toString();
            final statusStr = _translateStatus(rawStatus, lang).toLowerCase();
            if (!statusStr.contains(filterVal) &&
                !rawStatus.toLowerCase().contains(filterVal)) {
              return false;
            }
            break;
          case 'creator':
            final rawPlatform = d['creation_platform']?.toString();
            final creatorStr = _formatCreatorDisplay(rawPlatform).toLowerCase();
            if (!creatorStr.contains(filterVal) &&
                !(rawPlatform ?? '').toLowerCase().contains(filterVal)) {
              return false;
            }
            break;
        }
      }
      return true;
    }).toList();

    if (_orderSortColumn != null) {
      filtered.sort((a, b) {
        int comp = 0;
        switch (_orderSortColumn) {
          case 'id':
            final aId = (a['id'] as num?)?.toInt() ?? 0;
            final bId = (b['id'] as num?)?.toInt() ?? 0;
            comp = aId.compareTo(bId);
            break;
          case 'client_project':
            final aName =
                '${a['firstname'] ?? ''} ${a['lastname'] ?? ''} ${a['project_name'] ?? ''}';
            final bName =
                '${b['firstname'] ?? ''} ${b['lastname'] ?? ''} ${b['project_name'] ?? ''}';
            comp = aName.compareTo(bName);
            break;
          case 'date':
            final aDate = (a['created_at'] ?? a['date'] ?? '').toString();
            final bDate = (b['created_at'] ?? b['date'] ?? '').toString();
            comp = aDate.compareTo(bDate);
            break;
          case 'total':
            final aTot =
                (a['net_payable'] as num?)?.toDouble() ??
                (a['total'] as num?)?.toDouble() ??
                0.0;
            final bTot =
                (b['net_payable'] as num?)?.toDouble() ??
                (b['total'] as num?)?.toDouble() ??
                0.0;
            comp = aTot.compareTo(bTot);
            break;
          case 'advance':
            final aAdv = (a['advance_payment'] as num?)?.toDouble() ?? 0.0;
            final bAdv = (b['advance_payment'] as num?)?.toDouble() ?? 0.0;
            comp = aAdv.compareTo(bAdv);
            break;
          case 'remaining':
            final aRem =
                ((a['net_payable'] as num?)?.toDouble() ??
                    (a['total'] as num?)?.toDouble() ??
                    0.0) -
                ((a['advance_payment'] as num?)?.toDouble() ?? 0.0);
            final bRem =
                ((b['net_payable'] as num?)?.toDouble() ??
                    (b['total'] as num?)?.toDouble() ??
                    0.0) -
                ((b['advance_payment'] as num?)?.toDouble() ?? 0.0);
            comp = aRem.compareTo(bRem);
            break;
          case 'status':
            final aSt = (a['status'] ?? '').toString();
            final bSt = (b['status'] ?? '').toString();
            comp = aSt.compareTo(bSt);
            break;
          case 'creator':
            final aCr = _formatCreatorDisplay(
              a['creation_platform']?.toString(),
            );
            final bCr = _formatCreatorDisplay(
              b['creation_platform']?.toString(),
            );
            comp = aCr.compareTo(bCr);
            break;
        }
        return _orderSortAscending ? comp : -comp;
      });
    }

    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<AppSettingsProvider>(context);
    final lang = settings.language;
    final isDesktop =
        MediaQuery.of(context).size.width >= 900 || Platform.isWindows;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(Localization.translate("Commande", lang)),
        centerTitle: !isDesktop,
        backgroundColor: Theme.of(context).brightness == Brightness.dark
            ? Theme.of(context).appBarTheme.backgroundColor
            : Colors.blue,
        actions: [
          if (isDesktop && settings.canCreateOrders())
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: ElevatedButton.icon(
                onPressed: () {
                  openOrderInWorkspaceTab(
                    context,
                    db: db,
                    onSaved: _fetchCommandes,
                  );
                },
                icon: const Icon(Icons.add_circle_outline_rounded, size: 18),
                label: Text(
                  lang == AppLanguage.arabic
                      ? 'إضافة طلبية جديدة'
                      : (lang == AppLanguage.french
                            ? 'Nouvelle commande'
                            : 'Add New Order'),
                  style: const TextStyle(
                    fontFamily: 'Cairo',
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: const Color(0xFF2563EB),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          // 🔍 Filters — shown only on Mobile
          if (!(MediaQuery.of(context).size.width >= 900 || Platform.isWindows))
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              margin: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                border: Border.all(
                  width: 1,
                  color: Theme.of(context).dividerColor,
                ),
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      const Icon(Icons.filter_alt_outlined, color: Colors.blue),
                      const SizedBox(width: 10),
                      Text(
                        Localization.translate(
                          "Filters Commandes",
                          Provider.of<AppSettingsProvider>(context).language,
                        ),
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    onChanged: (val) {
                      setState(() {
                        _searchQuery = val;
                      });
                    },
                    decoration: InputDecoration(
                      hintText: Localization.translate(
                        "Search",
                        Provider.of<AppSettingsProvider>(context).language,
                      ),
                      prefixIcon: const Icon(Icons.search),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: Container(
              margin: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
              ),
              child: FutureBuilder<List<Map<String, dynamic>>>(
                future: _data,
                builder: (context, snapshot) {
                  if (snapshot.hasData) {
                    _cachedCommandes = snapshot.data;
                  }

                  if (snapshot.connectionState == ConnectionState.waiting &&
                      _cachedCommandes == null) {
                    return const Center(child: CircularProgressIndicator());
                  } else if (snapshot.hasError && _cachedCommandes == null) {
                    // 🟢 التصميم التفاعلي لحالة الخطأ (بدون أكواد SQL مرعبة)
                    return Center(
                      child: SingleChildScrollView(
                        child: Padding(
                          padding: const EdgeInsets.all(20.0),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(25),
                                decoration: BoxDecoration(
                                  color: Colors.red.withValues(alpha: 0.1),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  Icons.warning_amber_rounded,
                                  size: 70,
                                  color: Colors.red.shade400,
                                ),
                              ),
                              const SizedBox(height: 25),
                              Text(
                                'عذراً، حدث خطأ غير متوقع!',
                                style: TextStyle(
                                  color: Colors.red.shade800,
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 15),
                              Container(
                                padding: const EdgeInsets.all(15),
                                decoration: BoxDecoration(
                                  color: Colors.red.shade50,
                                  borderRadius: BorderRadius.circular(15),
                                  border: Border.all(
                                    color: Colors.red.shade200,
                                  ),
                                ),
                                child: Text(
                                  // 🟢 الرسالة المفهومة للمستخدم بدلاً من snapshot.error
                                  'تعذر تحميل البيانات حالياً. يرجى التأكد من استقرار النظام أو تحديث الصفحة للمحاولة مرة أخرى.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: Colors.red.shade700,
                                    fontSize: 15,
                                    height: 1.5,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 30),
                              ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.white,
                                  foregroundColor: Colors.red.shade600,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 30,
                                    vertical: 12,
                                  ),
                                  elevation: 0,
                                  side: BorderSide(
                                    color: Colors.red.shade200,
                                    width: 1.5,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(30),
                                  ),
                                ),
                                onPressed: () {
                                  setState(() {
                                    _data = db.readCommandesWithClients();
                                  });
                                },
                                icon: const Icon(
                                  Icons.refresh_rounded,
                                  size: 22,
                                ),
                                label: const Text(
                                  'تحديث الصفحة',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }

                  final rawData = snapshot.hasData
                      ? snapshot.data!
                      : (_cachedCommandes ?? <Map<String, dynamic>>[]);

                  // 🟢 التصميم التفاعلي لحالة عدم وجود طلبات
                  if (rawData.isEmpty) {
                    return Center(
                      child: SingleChildScrollView(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(30),
                              decoration: BoxDecoration(
                                color: Colors.blue.withValues(alpha: 0.1),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.receipt_long_outlined,
                                size: 80,
                                color: Colors.blue.shade400,
                              ),
                            ),
                            const SizedBox(height: 25),
                            Text(
                              Localization.translate(
                                "No Data",
                                Provider.of<AppSettingsProvider>(
                                  context,
                                ).language,
                              ),
                              style: TextStyle(
                                color: Colors.blueGrey.shade800,
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              'لا توجد أي طلبيات مسجلة حالياً.\nابدأ الآن بإنشاء أول فاتورة أو ورقة تقطيع للعميل.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.grey.shade600,
                                fontSize: 15,
                                height: 1.5,
                              ),
                            ),
                            const SizedBox(height: 35),
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.blue.shade600,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 30,
                                  vertical: 15,
                                ),
                                elevation: 4,
                                shadowColor: Colors.blue.withValues(alpha: 0.4),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(30),
                                ),
                              ),
                              onPressed: () {
                                openOrderInWorkspaceTab(
                                  context,
                                  db: db,
                                  onSaved: _fetchCommandes,
                                );
                              },
                              icon: const Icon(
                                Icons.add_circle_outline,
                                size: 24,
                              ),
                              label: const Text(
                                'إنشاء طلبية جديدة',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }
                  final data = rawData.where((d) {
                    final query = _searchQuery.toLowerCase().trim();
                    if (query.isEmpty) return true;
                    final first = (d['firstname'] ?? '')
                        .toString()
                        .toLowerCase();
                    final last = (d['lastname'] ?? '').toString().toLowerCase();
                    final phone = (d['phone'] ?? '').toString().toLowerCase();
                    final full = '$first $last $phone';
                    return query
                        .split(' ')
                        .every((term) => full.contains(term));
                  }).toList();

                  if (data.isEmpty) {
                    return const Center(
                      child: Text(
                        'لا توجد نتائج مطابقة للبحث',
                        style: TextStyle(fontSize: 16),
                      ),
                    );
                  }

                  if (MediaQuery.of(context).size.width >= 900 ||
                      Platform.isWindows) {
                    return _buildDesktopOrdersTableView(context, rawData, lang);
                  }

                  return ListView.builder(
                    controller: _scrollController,
                    itemCount: data.length,
                    itemBuilder: (context, index) {
                      final clientFirst = data[index]['firstname'] ?? '';
                      final clientLast = data[index]['lastname'] ?? '';

                      final clientPhone = data[index]['phone'];
                      final bool hasPhone =
                          clientPhone != null &&
                          clientPhone.toString().trim().isNotEmpty &&
                          clientPhone.toString() != 'null';

                      final clientName = '$clientFirst $clientLast'.trim();
                      final clientDisplay = clientName.isEmpty
                          ? 'زبون غير معروف'
                          : clientName;

                      final netPayable =
                          (data[index]['net_payable'] as num?)?.toDouble() ??
                          0.0;
                      final rawTotal =
                          (data[index]['total'] as num?)?.toDouble() ?? 0.0;
                      final total = netPayable > 0.0 ? netPayable : rawTotal;
                      final status = data[index]['status'] ?? 'New';
                      final isWindows = Platform.isWindows;

                      return Card(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(15),
                        ),
                        elevation: 2,
                        margin: const EdgeInsets.symmetric(vertical: 8),
                        child: ListTile(
                          contentPadding: const EdgeInsets.all(15),
                          leading: CircleAvatar(
                            radius: 25,
                            backgroundColor: Colors.blue.shade100,
                            child: const Icon(
                              Icons.receipt_long,
                              color: Colors.blue,
                            ),
                          ),
                          title: RichText(
                            text: TextSpan(
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                color: Theme.of(
                                  context,
                                ).textTheme.bodyLarge?.color,
                              ),
                              children: [
                                highlightText(clientDisplay, _searchQuery),
                              ],
                            ),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 5),
                              Text(
                                formatDate(data[index]),
                                style: TextStyle(
                                  color: Theme.of(
                                    context,
                                  ).textTheme.bodySmall?.color,
                                ),
                              ),
                              if (hasPhone)
                                RichText(
                                  text: TextSpan(
                                    style: TextStyle(
                                      color: Theme.of(
                                        context,
                                      ).textTheme.bodySmall?.color,
                                      fontSize: 14,
                                    ),
                                    children: [
                                      highlightText(
                                        clientPhone.toString(),
                                        _searchQuery,
                                      ),
                                    ],
                                  ),
                                ),
                              if (data[index]['project_name'] != null &&
                                  data[index]['project_name']
                                      .toString()
                                      .isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    Flexible(
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.blue.shade50,
                                          borderRadius: BorderRadius.circular(
                                            6,
                                          ),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              Icons.folder,
                                              size: 12,
                                              color: Colors.blue.shade700,
                                            ),
                                            const SizedBox(width: 4),
                                            Flexible(
                                              child: Text(
                                                data[index]['project_name']
                                                    .toString(),
                                                overflow: TextOverflow.ellipsis,
                                                maxLines: 1,
                                                style: TextStyle(
                                                  color: Colors.blue.shade800,
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                              // On Windows, keep the order group and status
                              // independent. ListTile's trailing area can make
                              // the central content too narrow on desktop.
                              if (isWindows) ...[
                                const SizedBox(height: 8),
                                Wrap(
                                  spacing: 10,
                                  runSpacing: 6,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    Text(
                                      '${total.toStringAsFixed(2)} دج',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: Colors.green,
                                        fontSize: 16,
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 3,
                                      ),
                                      decoration: BoxDecoration(
                                        color: _getStatusColor(status),
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: Text(
                                        _translateStatus(
                                          status,
                                          Provider.of<AppSettingsProvider>(
                                            context,
                                            listen: false,
                                          ).language,
                                        ),
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                          trailing: isWindows
                              ? null
                              : Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      '${total.toStringAsFixed(2)} دج',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: Colors.green,
                                        fontSize: 16,
                                      ),
                                    ),
                                    const SizedBox(height: 5),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 3,
                                      ),
                                      decoration: BoxDecoration(
                                        color: _getStatusColor(status),
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: Text(
                                        _translateStatus(
                                          status,
                                          Provider.of<AppSettingsProvider>(
                                            context,
                                            listen: false,
                                          ).language,
                                        ),
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                          onTap: settings.canViewOrderDetails()
                              ? () {
                                  _showOrderOptions(context, data[index]);
                                }
                              : null,
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

      floatingActionButton: (!isDesktop && settings.canCreateOrders())
          ? FloatingActionButton(
              onPressed: () {
                openOrderInWorkspaceTab(
                  context,
                  db: db,
                  onSaved: _fetchCommandes,
                );
              },
              child: const Icon(Icons.add),
            )
          : null,
    );
  }

  void _showOrderOptions(
    BuildContext context,
    Map<String, dynamic> orderData,
  ) async {
    final orderId = (orderData['id'] as num?)?.toInt() ?? 0;
    // The list row can legitimately be one repaint behind a live detail
    // update. Documents must always use the newest order header as well as
    // the freshly read Commandes_details rows, otherwise edit and pricing can
    // show two different versions of the same order.
    if (orderId > 0) {
      final freshOrder = await db.readCommandeWithClientById(orderId);
      if (freshOrder != null) {
        orderData = {...orderData, ...freshOrder};
      }
    }
    final isFullyManufactured = await db.isOrderFullyManufactured(orderId);
    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext ctx) {
        final settings = Provider.of<AppSettingsProvider>(
          context,
          listen: false,
        );
        final lang = settings.language;
        final currentStatus = orderData['status']?.toString() ?? 'Pending';
        final statusRaw = (orderData['status']?.toString() ?? '')
            .trim()
            .toLowerCase();
        final isPending =
            statusRaw == 'en attente' ||
            statusRaw == 'في الانتظار' ||
            statusRaw == 'pending' ||
            statusRaw == 'draft' ||
            statusRaw == 'new' ||
            statusRaw == 'en_attente';
        final isConfirmedOrBeyond = !isPending;
        final isManufacturingOrBeyond =
            isConfirmedOrBeyond &&
            statusRaw != 'confirmed' &&
            statusRaw != 'مؤكدة' &&
            statusRaw != 'مؤكد';

        final isDistributedOrBeyond =
            isFullyManufactured ||
            statusRaw.contains('full manufacturing') ||
            statusRaw.contains('تصنيع كلي') ||
            statusRaw.contains('distribution') ||
            statusRaw.contains('توزيع') ||
            statusRaw.contains('installation') ||
            statusRaw.contains('تركيب') ||
            statusRaw.contains('reserve') ||
            statusRaw.contains('تحفظ') ||
            statusRaw.contains('done') ||
            statusRaw.contains('انتهاء') ||
            statusRaw.contains('منتهية');

        return ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(ctx).size.height * 0.85,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 50,
                  height: 5,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                const SizedBox(height: 15),

                // Beautiful Header showing Order details & Status
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${lang == AppLanguage.french ? "Commande" : "طلب"} ${_displayOrderLabel(orderData)}',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                fontFamily: 'Cairo',
                                color:
                                    Theme.of(context).brightness ==
                                        Brightness.dark
                                    ? Colors.white
                                    : Colors.black87,
                              ),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              orderData['client_name']?.toString() ??
                                  orderData['client_display']?.toString() ??
                                  "Client",
                              style: TextStyle(
                                color:
                                    Theme.of(context).brightness ==
                                        Brightness.dark
                                    ? Colors.grey.shade400
                                    : Colors.grey.shade600,
                                fontSize: 13,
                                fontFamily: 'Cairo',
                              ),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: _getStatusColor(currentStatus),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          _translateStatus(currentStatus, lang),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'Cairo',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(),
                const SizedBox(height: 10),

                // 1. الوثائق والمستندات الرسمية للطلبية
                // 1. الوثائق والمستندات الرسمية للطلبية
                ListTile(
                  leading: const Icon(Icons.picture_as_pdf, color: Colors.red),
                  title: Text(Localization.translate('doc_devis_menu', lang)),
                  onTap: () async {
                    Navigator.pop(ctx);
                    await _showHeavyLoadingDialog(context, lang);
                    try {
                      final rawItems = await db
                          .readCommandeDetails(orderData['id'])
                          .timeout(const Duration(seconds: 10));
                      final List<Map<String, dynamic>> items = rawItems
                          .map((item) => Map<String, dynamic>.from(item))
                          .toList();

                      await _restoreDocumentImagesFromStoredBytes(items);

                      final workshop = await DevisBuilder.loadWorkshopInfo()
                          .timeout(const Duration(seconds: 6));
                      final devis = await DevisBuilder.build(
                        order: orderData,
                        items: items,
                        workshop: workshop,
                        documentTitleKey: 'doc_devis',
                      ).timeout(const Duration(seconds: 10));
                      _dismissHeavyLoadingDialog();
                      if (!mounted) return;
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => DevisPreviewScreen(data: devis),
                        ),
                      );
                    } catch (e) {
                      _dismissHeavyLoadingDialog();
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('خطأ أثناء توليد الفاتورة: $e'),
                            backgroundColor: Colors.red,
                          ),
                        );
                      }
                    }
                  },
                ),

                if (settings.canViewOrderDocuments())
                  ListTile(
                    leading: const Icon(
                      Icons.photo_library_outlined,
                      color: Colors.deepPurple,
                    ),
                    title: Text(Localization.translate('Picture', lang)),
                    subtitle: Text(
                      Localization.translate(
                        'صور النوافذ مع التفاصيل والمقاسات',
                        lang,
                      ),
                      style: const TextStyle(fontSize: 11),
                    ),
                    onTap: () {
                      Navigator.pop(ctx);
                      _exportOrderPicturePdf(context, orderData, lang);
                    },
                  ),

                if (isConfirmedOrBeyond &&
                    (settings.canEditPayments() ||
                        settings.canAccessTreasury()))
                  ListTile(
                    leading: const Icon(
                      Icons.payments_outlined,
                      color: Colors.green,
                    ),
                    title: Text(Localization.translate('Add payment', lang)),
                    subtitle: Text(
                      '${Localization.translate('Remaining:', lang)} ${(_readMoney(orderData['net_payable'] ?? orderData['total']) - _readMoney(orderData['advance_payment'])).clamp(0.0, double.infinity).toStringAsFixed(2)} د.ج',
                      style: const TextStyle(fontSize: 11),
                    ),
                    onTap: () {
                      Navigator.pop(ctx);
                      _showAddOrderPaymentDialog(orderData, lang);
                    },
                  ),

                // 1.3. Facture Officielle / Proforma
                if (settings.canViewOrderDocuments())
                  ListTile(
                    leading: const Icon(
                      Icons.description,
                      color: Colors.indigo,
                    ),
                    title: Text(
                      Localization.translate('فاتورة رسمية / أولية', lang),
                    ),
                    onTap: () async {
                      Navigator.pop(ctx);
                      await _showHeavyLoadingDialog(context, lang);
                      try {
                        final rawItems = await db.readCommandeDetails(
                          orderData['id'],
                        );
                        final List<Map<String, dynamic>> items = rawItems
                            .map((item) => Map<String, dynamic>.from(item))
                            .toList();
                        final workshop = await DevisBuilder.loadWorkshopInfo();
                        final devis = await DevisBuilder.build(
                          order: orderData,
                          items: items,
                          workshop: workshop,
                          isProForma: true,
                        );
                        _dismissHeavyLoadingDialog();
                        if (!mounted) return;
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) =>
                                DevisPreviewScreen(data: devis),
                          ),
                        );
                      } catch (e) {
                        _dismissHeavyLoadingDialog();
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('خطأ أثناء توليد الفاتورة: $e'),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      }
                    },
                  ),

                // Facture de Vente
                if (settings.canViewOrderDocuments() && isConfirmedOrBeyond)
                  ListTile(
                    leading: const Icon(
                      Icons.receipt_rounded,
                      color: Colors.teal,
                    ),
                    title: Text(
                      lang == AppLanguage.french
                          ? 'Facture de Vente'
                          : 'فاتورة بيع / Facture de Vente',
                    ),
                    onTap: () async {
                      Navigator.pop(ctx);
                      await _showHeavyLoadingDialog(context, lang);
                      try {
                        final rawItems = await db.readCommandeDetails(
                          orderData['id'],
                        );
                        final List<Map<String, dynamic>> items = rawItems
                            .map((item) => Map<String, dynamic>.from(item))
                            .toList();
                        final workshop = await DevisBuilder.loadWorkshopInfo();
                        final devis = await DevisBuilder.build(
                          order: orderData,
                          items: items,
                          workshop: workshop,
                          isProForma: false,
                          documentTitleKey: 'FACTURE_VENTE',
                        );
                        _dismissHeavyLoadingDialog();
                        if (!mounted) return;
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) =>
                                DevisPreviewScreen(data: devis),
                          ),
                        );
                      } catch (e) {
                        _dismissHeavyLoadingDialog();
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('خطأ أثناء توليد الفاتورة: $e'),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      }
                    },
                  ),

                // Bon de Route
                if (settings.canViewOrderDocuments() && isConfirmedOrBeyond)
                  ListTile(
                    leading: const Icon(
                      Icons.directions_car_outlined,
                      color: Colors.blueAccent,
                    ),
                    title: Text(
                      lang == AppLanguage.french
                          ? 'Bon de Route'
                          : 'بون دو روت / Bon de Route',
                    ),
                    onTap: () async {
                      Navigator.pop(ctx);
                      await _showHeavyLoadingDialog(context, lang);
                      try {
                        final rawItems = await db.readCommandeDetails(
                          orderData['id'],
                        );
                        final List<Map<String, dynamic>> items = rawItems
                            .map((item) => Map<String, dynamic>.from(item))
                            .toList();
                        final workshop = await DevisBuilder.loadWorkshopInfo();
                        final devis = await DevisBuilder.build(
                          order: orderData,
                          items: items,
                          workshop: workshop,
                          isProForma: false,
                          documentTitleKey: 'BON_ROUTE',
                        );
                        _dismissHeavyLoadingDialog();
                        if (!mounted) return;
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) =>
                                DevisPreviewScreen(data: devis),
                          ),
                        );
                      } catch (e) {
                        _dismissHeavyLoadingDialog();
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('خطأ أثناء توليد المستند: $e'),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      }
                    },
                  ),

                // Bon de livraison
                if (settings.canViewOrderDocuments() && isConfirmedOrBeyond)
                  ListTile(
                    leading: const Icon(Icons.assignment, color: Colors.blue),
                    title: Text(
                      Localization.translate('doc_bon_livraison_menu', lang),
                    ),
                    onTap: () async {
                      Navigator.pop(ctx);
                      await _showHeavyLoadingDialog(context, lang);
                      try {
                        final rawItems = await db.readCommandeDetails(
                          orderData['id'],
                        );
                        final List<Map<String, dynamic>> items = rawItems
                            .map((item) => Map<String, dynamic>.from(item))
                            .toList();

                        for (var item in items) {
                          final path =
                              item['drawing_image_path']?.toString() ?? '';
                          if (path.isEmpty || !File(path).existsSync()) {
                            final jsonRaw = item['partitions_json'];
                            if (jsonRaw != null) {
                              try {
                                Map<String, dynamic> modelMap = {};
                                if (jsonRaw is Map<String, dynamic>) {
                                  modelMap = jsonRaw;
                                } else if (jsonRaw is Map) {
                                  modelMap = Map<String, dynamic>.from(jsonRaw);
                                } else {
                                  final str = jsonRaw.toString().trim();
                                  if (str.length >= 5) {
                                    modelMap =
                                        jsonDecode(str) as Map<String, dynamic>;
                                  }
                                }
                                if (modelMap.isNotEmpty) {
                                  final model = WindowModel(db: db);
                                  await applyWindowModelAndLoadCatalog(
                                    model,
                                    modelMap,
                                  );
                                  final newPath = await saveWindowImageToDisk(
                                    model,
                                  );
                                  if (newPath.isNotEmpty) {
                                    await db.updateCommandeDetailImagePath(
                                      item['id'] as int,
                                      newPath,
                                    );
                                    item['drawing_image_path'] = newPath;
                                  }
                                }
                              } catch (err) {
                                debugPrint(
                                  'Error generating missing image: $err',
                                );
                              }
                            }
                          }
                        }

                        final workshop = await DevisBuilder.loadWorkshopInfo();
                        final devis = await DevisBuilder.build(
                          order: orderData,
                          items: items,
                          workshop: workshop,
                          hidePrices: false,
                          documentTitleKey: 'doc_bon_livraison',
                        );
                        _dismissHeavyLoadingDialog();
                        if (!mounted) return;
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) =>
                                DevisPreviewScreen(data: devis),
                          ),
                        );
                      } catch (e) {
                        _dismissHeavyLoadingDialog();
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('خطأ أثناء توليد الفاتورة: $e'),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      }
                    },
                  ),

                // Bon de livraison sans prix
                if (settings.canViewOrderDocuments() && isConfirmedOrBeyond)
                  ListTile(
                    leading: const Icon(
                      Icons.print_disabled,
                      color: Colors.blueGrey,
                    ),
                    title: Text(
                      Localization.translate(
                        'doc_bon_livraison_sans_prix_menu',
                        lang,
                      ),
                    ),
                    onTap: () async {
                      Navigator.pop(ctx);
                      await _showHeavyLoadingDialog(context, lang);
                      try {
                        final rawItems = await db.readCommandeDetails(
                          orderData['id'],
                        );
                        final List<Map<String, dynamic>> items = rawItems
                            .map((item) => Map<String, dynamic>.from(item))
                            .toList();

                        for (var item in items) {
                          final path =
                              item['drawing_image_path']?.toString() ?? '';
                          if (path.isEmpty || !File(path).existsSync()) {
                            final jsonRaw = item['partitions_json'];
                            if (jsonRaw != null) {
                              try {
                                Map<String, dynamic> modelMap = {};
                                if (jsonRaw is Map<String, dynamic>) {
                                  modelMap = jsonRaw;
                                } else if (jsonRaw is Map) {
                                  modelMap = Map<String, dynamic>.from(jsonRaw);
                                } else {
                                  final str = jsonRaw.toString().trim();
                                  if (str.length >= 5) {
                                    modelMap =
                                        jsonDecode(str) as Map<String, dynamic>;
                                  }
                                }
                                if (modelMap.isNotEmpty) {
                                  final model = WindowModel(db: db);
                                  await applyWindowModelAndLoadCatalog(
                                    model,
                                    modelMap,
                                  );
                                  final newPath = await saveWindowImageToDisk(
                                    model,
                                  );
                                  if (newPath.isNotEmpty) {
                                    await db.updateCommandeDetailImagePath(
                                      item['id'] as int,
                                      newPath,
                                    );
                                    item['drawing_image_path'] = newPath;
                                  }
                                }
                              } catch (err) {
                                debugPrint(
                                  'Error generating missing image: $err',
                                );
                              }
                            }
                          }
                        }

                        final workshop = await DevisBuilder.loadWorkshopInfo();
                        final devis = await DevisBuilder.build(
                          order: orderData,
                          items: items,
                          workshop: workshop,
                          hidePrices: true,
                          documentTitleKey: 'doc_bon_livraison_sans_prix',
                        );
                        _dismissHeavyLoadingDialog();
                        if (!mounted) return;
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) =>
                                DevisPreviewScreen(data: devis),
                          ),
                        );
                      } catch (e) {
                        _dismissHeavyLoadingDialog();
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('خطأ أثناء توليد الفاتورة: $e'),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      }
                    },
                  ),

                // Bon de livraison partiel
                if (settings.canViewOrderDocuments() && isConfirmedOrBeyond)
                  ListTile(
                    leading: const Icon(
                      Icons.picture_as_pdf_outlined,
                      color: Colors.blue,
                    ),
                    title: Text(
                      Localization.translate(
                        'doc_bon_livraison_partiel_menu',
                        lang,
                      ),
                    ),
                    onTap: () {
                      Navigator.pop(ctx);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => PartialProformaScreen(
                            order: orderData,
                            documentTitleKey: 'doc_bon_livraison_partiel',
                          ),
                        ),
                      );
                    },
                  ),

                // Bon de livraison partiel sans prix
                if (settings.canViewOrderDocuments() && isConfirmedOrBeyond)
                  ListTile(
                    leading: const Icon(
                      Icons.print_disabled_outlined,
                      color: Colors.blueGrey,
                    ),
                    title: Text(
                      Localization.translate(
                        'doc_bon_livraison_partiel_sans_prix_menu',
                        lang,
                      ),
                    ),
                    onTap: () {
                      Navigator.pop(ctx);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => PartialProformaScreen(
                            order: orderData,
                            hidePrices: true,
                            documentTitleKey:
                                'doc_bon_livraison_partiel_sans_prix',
                          ),
                        ),
                      );
                    },
                  ),

                // Bon de charge
                if (settings.canViewOrderDocuments() && isManufacturingOrBeyond)
                  ListTile(
                    leading: const Icon(
                      Icons.local_shipping,
                      color: Colors.teal,
                    ),
                    title: Text(
                      Localization.translate('doc_bon_charge_menu', lang),
                    ),
                    onTap: () async {
                      Navigator.pop(ctx);

                      final choice = await showDialog<String>(
                        context: context,
                        builder: (dialogCtx) => AlertDialog(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          title: Row(
                            children: [
                              const Icon(
                                Icons.local_shipping,
                                color: Colors.teal,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                lang == AppLanguage.french
                                    ? 'Type de Bon d\'expédition'
                                    : 'نوع فاتورة الشحن',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontFamily: 'Cairo',
                                  fontSize: 16,
                                ),
                              ),
                            ],
                          ),
                          content: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              ListTile(
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  side: BorderSide(color: Colors.grey.shade300),
                                ),
                                leading: const Icon(
                                  Icons.inventory_2,
                                  color: Colors.blue,
                                ),
                                title: Text(
                                  lang == AppLanguage.french
                                      ? 'Expédition complète (Toutes les fenêtres)'
                                      : lang == AppLanguage.english
                                      ? 'Full Shipping (All windows)'
                                      : 'فاتورة شحن كلية (جميع النوافذ)',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontFamily: 'Cairo',
                                    fontSize: 13,
                                  ),
                                ),
                                onTap: () => Navigator.pop(dialogCtx, 'FULL'),
                              ),
                              const SizedBox(height: 10),
                              ListTile(
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  side: BorderSide(color: Colors.grey.shade300),
                                ),
                                leading: const Icon(
                                  Icons.local_shipping_outlined,
                                  color: Colors.orange,
                                ),
                                title: Text(
                                  lang == AppLanguage.french
                                      ? 'Expédition partielle (Par bon de livraison)'
                                      : lang == AppLanguage.english
                                      ? 'Partial Shipping (By delivery note)'
                                      : 'فاتورة شحن جزئية (حسب وصل الشحن الجزئي)',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontFamily: 'Cairo',
                                    fontSize: 13,
                                  ),
                                ),
                                onTap: () =>
                                    Navigator.pop(dialogCtx, 'PARTIAL'),
                              ),
                            ],
                          ),
                        ),
                      );

                      if (choice == null) return;

                      if (choice == 'PARTIAL') {
                        final orderId = orderData['id'] as int;
                        final deliveries = await db.readCommandeDeliveries(
                          orderId,
                        );

                        if (deliveries.isEmpty) {
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                lang == AppLanguage.french
                                    ? 'Aucun bon d\'expédition partiel trouvé. Redirection...'
                                    : 'لا توجد وصولات شحن جزئية مسبقة! سيتم التوجيه لتحديد العناصر المراد شحنها.',
                                style: const TextStyle(fontFamily: 'Cairo'),
                              ),
                              backgroundColor: Colors.orange,
                            ),
                          );
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => PartialProformaScreen(
                                order: orderData,
                                hidePrices: true,
                                documentTitleKey: 'doc_bon_livraison_partiel',
                                autoOpenBonDeChargeOnSave: true,
                              ),
                            ),
                          );
                          return;
                        }

                        if (!mounted) return;
                        final selectedResult = await showModalBottomSheet<dynamic>(
                          context: context,
                          isScrollControlled: true,
                          shape: const RoundedRectangleBorder(
                            borderRadius: BorderRadius.vertical(
                              top: Radius.circular(16),
                            ),
                          ),
                          builder: (bottomSheetCtx) {
                            return Container(
                              padding: const EdgeInsets.all(16),
                              constraints: BoxConstraints(
                                maxHeight:
                                    MediaQuery.of(context).size.height * 0.7,
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Text(
                                    lang == AppLanguage.french
                                        ? 'Sélectionner un Bon de livraison partiel'
                                        : 'اختر وصل تسليم جزئي للتحميل',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                      fontFamily: 'Cairo',
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  Expanded(
                                    child: ListView.separated(
                                      shrinkWrap: true,
                                      itemCount: deliveries.length,
                                      separatorBuilder: (_, _) =>
                                          const Divider(height: 1),
                                      itemBuilder: (context, index) {
                                        final del = deliveries[index];
                                        final isLoaded =
                                            (del['is_loaded'] == 1);
                                        List items = [];
                                        try {
                                          items = jsonDecode(del['items_json']);
                                        } catch (_) {}
                                        final itemCount = items.length;
                                        return ListTile(
                                          leading: Icon(
                                            isLoaded
                                                ? Icons.check_circle
                                                : Icons.local_shipping,
                                            color: isLoaded
                                                ? Colors.green
                                                : Colors.orange,
                                          ),
                                          title: Text(
                                            'وصل بتاريخ: ${del['delivery_date']}',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 13,
                                              fontFamily: 'Cairo',
                                            ),
                                          ),
                                          subtitle: Text(
                                            'عدد القطع: $itemCount نافذة',
                                            style: const TextStyle(
                                              fontSize: 11,
                                              fontFamily: 'Cairo',
                                            ),
                                          ),
                                          trailing: Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 4,
                                            ),
                                            decoration: BoxDecoration(
                                              color: isLoaded
                                                  ? Colors.green.shade100
                                                  : Colors.orange.shade100,
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                            ),
                                            child: Text(
                                              isLoaded
                                                  ? (lang == AppLanguage.french
                                                        ? 'Chargé'
                                                        : 'تم التحميل')
                                                  : (lang == AppLanguage.french
                                                        ? 'En attente'
                                                        : 'معلق'),
                                              style: TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.bold,
                                                color: isLoaded
                                                    ? Colors.green.shade900
                                                    : Colors.orange.shade900,
                                                fontFamily: 'Cairo',
                                              ),
                                            ),
                                          ),
                                          onTap: () {
                                            Navigator.pop(bottomSheetCtx, del);
                                          },
                                        );
                                      },
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.teal,
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 12,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                    ),
                                    onPressed: () {
                                      Navigator.pop(bottomSheetCtx, {
                                        'action': 'NEW',
                                      });
                                    },
                                    icon: const Icon(
                                      Icons.add,
                                      color: Colors.white,
                                    ),
                                    label: Text(
                                      lang == AppLanguage.french
                                          ? '+ Nouveau bon de livraison partiel'
                                          : '+ إنشاء توصيل جزئي جديد',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontFamily: 'Cairo',
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        );

                        if (selectedResult == null) return;

                        if (selectedResult is Map &&
                            selectedResult['action'] == 'NEW') {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => PartialProformaScreen(
                                order: orderData,
                                hidePrices: true,
                                documentTitleKey: 'doc_bon_livraison_partiel',
                                autoOpenBonDeChargeOnSave: true,
                              ),
                            ),
                          );
                          return;
                        }

                        if (selectedResult is Map<String, dynamic>) {
                          await _showHeavyLoadingDialog(context, lang);
                          try {
                            final itemsJsonStr =
                                selectedResult['items_json']?.toString() ??
                                '[]';
                            final List<dynamic> rawDecoded = jsonDecode(
                              itemsJsonStr,
                            );
                            final List<Map<String, dynamic>> items = rawDecoded
                                .map((it) => Map<String, dynamic>.from(it))
                                .toList();

                            for (var item in items) {
                              final path =
                                  item['drawing_image_path']?.toString() ?? '';
                              if (path.isEmpty || !File(path).existsSync()) {
                                final jsonRaw = item['partitions_json'];
                                if (jsonRaw != null) {
                                  try {
                                    Map<String, dynamic> modelMap = {};
                                    if (jsonRaw is Map<String, dynamic>) {
                                      modelMap = jsonRaw;
                                    } else if (jsonRaw is Map) {
                                      modelMap = Map<String, dynamic>.from(
                                        jsonRaw,
                                      );
                                    } else {
                                      final str = jsonRaw.toString().trim();
                                      if (str.length >= 5) {
                                        modelMap =
                                            jsonDecode(str)
                                                as Map<String, dynamic>;
                                      }
                                    }
                                    if (modelMap.isNotEmpty) {
                                      final model = WindowModel(db: db);
                                      await applyWindowModelAndLoadCatalog(
                                        model,
                                        modelMap,
                                      );
                                      final newPath =
                                          await saveWindowImageToDisk(model);
                                      if (newPath.isNotEmpty) {
                                        await db.updateCommandeDetailImagePath(
                                          item['id'] as int,
                                          newPath,
                                        );
                                        item['drawing_image_path'] = newPath;
                                      }
                                    }
                                  } catch (err) {
                                    debugPrint(
                                      'Error generating missing image: $err',
                                    );
                                  }
                                }
                              }
                            }

                            final workshop =
                                await DevisBuilder.loadWorkshopInfo();
                            final devis = await DevisBuilder.build(
                              order: orderData,
                              items: items,
                              workshop: workshop,
                              hidePrices: true,
                              documentTitleKey: 'BON_CHARGE',
                            );
                            _dismissHeavyLoadingDialog();
                            if (!mounted) return;
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => DevisPreviewScreen(
                                  data: devis,
                                  deliveryId: selectedResult['id'] as int?,
                                  initialIsLoaded:
                                      (selectedResult['is_loaded'] == 1),
                                ),
                              ),
                            );
                          } catch (e) {
                            _dismissHeavyLoadingDialog();
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('خطأ أثناء توليد الفاتورة: $e'),
                                  backgroundColor: Colors.red,
                                ),
                              );
                            }
                          }
                          return;
                        }
                      }

                      // Full loading flow (FULL)
                      await _showHeavyLoadingDialog(context, lang);
                      try {
                        final rawItems = await db.readCommandeDetails(
                          orderData['id'],
                        );
                        final List<Map<String, dynamic>> items = rawItems
                            .map((item) => Map<String, dynamic>.from(item))
                            .toList();

                        for (var item in items) {
                          final path =
                              item['drawing_image_path']?.toString() ?? '';
                          if (path.isEmpty || !File(path).existsSync()) {
                            final jsonRaw = item['partitions_json'];
                            if (jsonRaw != null) {
                              try {
                                Map<String, dynamic> modelMap = {};
                                if (jsonRaw is Map<String, dynamic>) {
                                  modelMap = jsonRaw;
                                } else if (jsonRaw is Map) {
                                  modelMap = Map<String, dynamic>.from(jsonRaw);
                                } else {
                                  final str = jsonRaw.toString().trim();
                                  if (str.length >= 5) {
                                    modelMap =
                                        jsonDecode(str) as Map<String, dynamic>;
                                  }
                                }
                                if (modelMap.isNotEmpty) {
                                  final model = WindowModel(db: db);
                                  await applyWindowModelAndLoadCatalog(
                                    model,
                                    modelMap,
                                  );
                                  final newPath = await saveWindowImageToDisk(
                                    model,
                                  );
                                  if (newPath.isNotEmpty) {
                                    await db.updateCommandeDetailImagePath(
                                      item['id'] as int,
                                      newPath,
                                    );
                                    item['drawing_image_path'] = newPath;
                                  }
                                }
                              } catch (err) {
                                debugPrint(
                                  'Error generating missing image: $err',
                                );
                              }
                            }
                          }
                        }

                        final workshop = await DevisBuilder.loadWorkshopInfo();
                        final devis = await DevisBuilder.build(
                          order: orderData,
                          items: items,
                          workshop: workshop,
                          hidePrices: true,
                          documentTitleKey: 'BON_CHARGE',
                        );
                        _dismissHeavyLoadingDialog();
                        if (!mounted) return;
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) =>
                                DevisPreviewScreen(data: devis),
                          ),
                        );
                      } catch (e) {
                        _dismissHeavyLoadingDialog();
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('خطأ أثناء توليد الفاتورة: $e'),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      }
                    },
                  ),
                if (isConfirmedOrBeyond) const Divider(),

                // 2. Fiche de Coupe
                if (settings.canViewFicheDeCoupe())
                  ListTile(
                    leading: const Icon(Icons.cut, color: Colors.orange),
                    title: Text(
                      Localization.translate(
                        'ورقة التقطيع (Fiche de Coupe)',
                        lang,
                      ),
                    ),
                    onTap: () async {
                      Navigator.pop(ctx);
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              Localization.translate(
                                'جاري تجهيز جدول التقطيع...',
                                lang,
                              ),
                            ),
                          ),
                        );
                      }
                      try {
                        final items = await db.readCommandeDetails(
                          orderData['id'],
                        );
                        final prefs = await SharedPreferences.getInstance();
                        final workshopName =
                            prefs.getString('workshop_name') ?? 'ورشتي';
                        await PdfFicheCoupeApi.generateAndPrintFicheCoupe(
                          order: orderData,
                          items: items,
                          workshopName: workshopName,
                          db: db,
                        );
                      } catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                '${Localization.translate('خطأ أثناء توليد الفاتورة:', lang)} $e',
                              ),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      }
                    },
                  ),

                // 3. Fiche de Consommation & المواد والسلع المطلوبة
                if (settings.canViewOrderMaterials()) ...[
                  ListTile(
                    leading: const Icon(
                      Icons.inventory_2,
                      color: Colors.indigo,
                    ),
                    title: Text(
                      Localization.translate('كمية السلع المطلوبة', lang),
                    ),
                    subtitle: Text(
                      Localization.translate(
                        'محسوبة من نفس جدول الكمية والتكلفة',
                        lang,
                      ),
                      style: const TextStyle(fontSize: 11),
                    ),
                    onTap: () {
                      Navigator.pop(ctx);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => OrderRequiredGoodsScreen(
                            orderData: orderData,
                            db: db,
                          ),
                        ),
                      );
                    },
                  ),
                ],

                // 3.8 تأكيد القياسات والملصقات
                if (settings.canConfirmMeasurements())
                  ListTile(
                    leading: const Icon(
                      Icons.line_weight_rounded,
                      color: Colors.indigoAccent,
                    ),
                    title: Text(
                      Localization.translate(
                        'تأكيد القياسات والملصقات (Stickers)',
                        lang,
                      ),
                    ),
                    subtitle: Text(
                      Localization.translate(
                        'تعديل القياسات الفعلية للموقع وطباعة الباركود لكل قطعة',
                        lang,
                      ),
                      style: const TextStyle(fontSize: 11),
                    ),
                    onTap: () {
                      Navigator.pop(ctx);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => OrderMeasurementsConfirmScreen(
                            orderData: orderData,
                            db: db,
                          ),
                        ),
                      );
                    },
                  ),

                // 3.9 توزيع المهام وإسناد العمل للعمال (تختفي عند التصنيع الكلي، التوزيع، التركيب، التحفظات أو الانتهاء)
                if (settings.canAllocateTasks() && !isDistributedOrBeyond)
                  ListTile(
                    leading: const Icon(
                      Icons.engineering_rounded,
                      color: Colors.purple,
                    ),
                    title: Text(
                      lang == AppLanguage.french
                          ? 'Affectation des tâches aux ouvriers'
                          : 'توزيع المهام على العمال (إسناد الورشة)',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(
                      lang == AppLanguage.french
                          ? 'Répartir la fabrication des éléments sur l\'équipe'
                          : 'توزيع النوافذ وتحديد أجر تصنيع كل عنصر للعمال',
                      style: const TextStyle(fontSize: 11),
                    ),
                    onTap: () {
                      Navigator.pop(ctx);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => OrderAllocationScreen(
                            orderData: orderData,
                            db: db,
                          ),
                        ),
                      );
                    },
                  ),

                const Divider(),

                // 4. Move to Next Stage (نقل إلى المرحلة التالية)
                if (settings.canPassNextStage())
                  ListTile(
                    leading: const Icon(
                      Icons.forward_rounded,
                      color: Colors.green,
                    ),
                    title: Text(
                      lang == AppLanguage.french
                          ? 'Passer à l\'étape suivante'
                          : 'نقل إلى المرحلة التالية',
                    ),
                    subtitle: Text(
                      lang == AppLanguage.french
                          ? 'Passer la commande de "${_translateStatus(currentStatus, lang)}" à l\'étape suivante'
                          : 'نقل الطلبية من حالة "${_translateStatus(currentStatus, lang)}" إلى المرحلة التي تليها',
                      style: const TextStyle(fontSize: 11),
                    ),
                    onTap: () async {
                      Navigator.pop(ctx);
                      const stagesSequence = [
                        'Pending',
                        'Confirmed',
                        'In Progress',
                        'Partial Manufacturing',
                        'Partial Distribution',
                        'Full Manufacturing',
                        'Full Distribution',
                        'Installation',
                        'Reserve',
                        'Done',
                      ];

                      final normalizedStatus =
                          (currentStatus == 'en_attente' ||
                              currentStatus == 'في الانتظار' ||
                              currentStatus == 'Draft' ||
                              currentStatus == 'New')
                          ? 'Pending'
                          : currentStatus;

                      int currentIndex = stagesSequence.indexOf(
                        normalizedStatus,
                      );
                      if (currentIndex == -1) {
                        if (normalizedStatus.toLowerCase().contains(
                              'attente',
                            ) ||
                            normalizedStatus.toLowerCase().contains('انتظار')) {
                          currentIndex = 0;
                        } else if (normalizedStatus.toLowerCase().contains(
                          'confirm',
                        )) {
                          currentIndex = 1;
                        } else {
                          currentIndex = 0;
                        }
                      }

                      if (currentIndex < stagesSequence.length - 1) {
                        final nextStatus = stagesSequence[currentIndex + 1];

                        if (normalizedStatus == 'In Progress') {
                          if (!mounted) return;
                          showDialog(
                            context: context,
                            barrierDismissible: false,
                            builder: (_) => PopScope(
                              canPop: false,
                              child: AlertDialog(
                                content: Row(
                                  children: [
                                    const CircularProgressIndicator(),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: Text(
                                        lang == AppLanguage.french
                                            ? 'Vérification des mesures…'
                                            : 'جاري التحقق من القياسات…',
                                        style: const TextStyle(
                                          fontFamily: 'Cairo',
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                          await WidgetsBinding.instance.endOfFrame;
                          var allConfirmed = false;
                          Object? measurementCheckError;
                          try {
                            allConfirmed = await _areAllMeasurementsConfirmed(
                              orderData['id'],
                            ).timeout(const Duration(seconds: 15));
                          } catch (error) {
                            measurementCheckError = error;
                          } finally {
                            if (mounted) {
                              Navigator.of(context, rootNavigator: true).pop();
                            }
                          }
                          if (measurementCheckError != null) {
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    lang == AppLanguage.french
                                        ? 'Impossible de vérifier les mesures de cette commande.'
                                        : 'تعذر التحقق من قياسات هذه الطلبية. راجع بيانات القياسات ثم حاول مجددًا.',
                                    style: const TextStyle(fontFamily: 'Cairo'),
                                  ),
                                  backgroundColor: Colors.redAccent,
                                ),
                              );
                            }
                            return;
                          }
                          if (!allConfirmed) {
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    lang == AppLanguage.french
                                        ? 'Impossible de passer à la fabrication sans valider les mesures !'
                                        : 'لا يمكن الانتقال للتصنيع إن لم تقم بتأكيد القياسات!',
                                  ),
                                  backgroundColor: Colors.redAccent,
                                ),
                              );
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) =>
                                      OrderMeasurementsConfirmScreen(
                                        orderData: orderData,
                                        db: db,
                                      ),
                                ),
                              );
                            }
                            return;
                          }
                        }

                        if (!mounted) return;
                        showDialog(
                          context: context,
                          barrierDismissible: false,
                          builder: (_) => PopScope(
                            canPop: false,
                            child: AlertDialog(
                              content: Row(
                                children: [
                                  const CircularProgressIndicator(),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Text(
                                      lang == AppLanguage.french
                                          ? 'Mise à jour de la commande…'
                                          : 'جاري تحديث حالة الطلبية…',
                                      style: const TextStyle(
                                        fontFamily: 'Cairo',
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );

                        await WidgetsBinding.instance.endOfFrame;
                        Object? statusUpdateError;
                        try {
                          await db
                              .updateCommandeStatus(orderData['id'], nextStatus)
                              .timeout(const Duration(seconds: 30));
                        } catch (error) {
                          statusUpdateError = error;
                        } finally {
                          if (mounted) {
                            Navigator.of(context, rootNavigator: true).pop();
                          }
                        }

                        if (statusUpdateError != null) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  lang == AppLanguage.french
                                      ? 'Échec du passage à l’étape suivante. Veuillez réessayer.'
                                      : 'تعذر نقل الطلبية إلى المرحلة التالية. يرجى المحاولة مجددًا.',
                                  style: const TextStyle(fontFamily: 'Cairo'),
                                ),
                                backgroundColor: Colors.redAccent,
                              ),
                            );
                          }
                          return;
                        }
                        if (!mounted) return;
                        setState(() {
                          _data = db.readCommandesWithClients();
                        });

                        if (nextStatus == 'In Progress') {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  lang == AppLanguage.french
                                      ? 'Commande passée à: Confirmation des mesures'
                                      : 'تم نقل الطلبية إلى مرحلة تأكيد القياسات. يرجى تأكيد المقاسات.',
                                ),
                                backgroundColor: Colors.indigo,
                              ),
                            );
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => OrderMeasurementsConfirmScreen(
                                  orderData: orderData,
                                  db: db,
                                ),
                              ),
                            );
                          }
                        } else {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  lang == AppLanguage.french
                                      ? 'Commande passée à l\'étape: ${_translateStatus(nextStatus, lang)}'
                                      : 'تم نقل الطلبية بنجاح إلى مرحلة: ${_translateStatus(nextStatus, lang)}',
                                ),
                                backgroundColor: Colors.green,
                              ),
                            );
                          }
                        }
                      } else {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                lang == AppLanguage.french
                                    ? 'La commande est déjà dans la dernière étape (Done)!'
                                    : 'الطلبية وصلت بالفعل للمرحلة الأخيرة!',
                              ),
                              backgroundColor: Colors.orange,
                            ),
                          );
                        }
                      }
                    },
                  ),

                // 5. Change Status (تغيير الحالة المخصص يدوياً)
                if (settings.canChangeOrderStatus())
                  ListTile(
                    leading: const Icon(Icons.swap_horiz, color: Colors.blue),
                    title: Text(
                      Localization.translate('تغيير الحالة المخصص', lang),
                    ),
                    onTap: () {
                      Navigator.pop(ctx);
                      _showChangeStatusDialog(orderData);
                    },
                  ),

                // 6. Modification
                if (settings.canEditOrders())
                  ListTile(
                    leading: const Icon(Icons.edit, color: Colors.blue),
                    title: Text(Localization.translate("Edit Order", lang)),
                    onTap: () {
                      Navigator.pop(ctx);
                      openOrderInWorkspaceTab(
                        context,
                        db: db,
                        editCommandeId: (orderData['id'] as num?)?.toInt(),
                        onSaved: _fetchCommandes,
                      );
                    },
                  ),

                // NEW: 6.5 Duplicate
                if (settings.canDuplicateOrders())
                  ListTile(
                    leading: const Icon(Icons.copy, color: Colors.blueGrey),
                    title: Text(
                      Localization.translate('تكرار الطلبية (Duplicate)', lang),
                    ),
                    onTap: () async {
                      Navigator.pop(ctx);
                      try {
                        await _duplicateOrder(orderData);
                        setState(() {
                          _data = db.readCommandesWithClients();
                        });
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                Localization.translate(
                                  'تم تكرار الطلبية بنجاح!',
                                  lang,
                                ),
                              ),
                              backgroundColor: Colors.green,
                            ),
                          );
                        }
                      } catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                '${Localization.translate('حدث خطأ أثناء التكرار:', lang)} $e',
                              ),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      }
                    },
                  ),

                const Divider(),

                // 7. Supprimer
                Consumer<AppSettingsProvider>(
                  builder: (ctx2, settings, _) {
                    if (!settings.canDeleteOrders()) {
                      return const SizedBox.shrink();
                    }
                    return ListTile(
                      leading: const Icon(
                        Icons.delete,
                        color: Colors.redAccent,
                      ),
                      title: Text(
                        Localization.translate('مسح الطلبية (Supprimer)', lang),
                      ),
                      onTap: () {
                        Navigator.pop(ctx);
                        _showDeleteConfirmDialog(orderData['id']);
                      },
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _exportOrderPicturePdf(
    BuildContext context,
    Map<String, dynamic> orderData,
    AppLanguage lang,
  ) async {
    if (!mounted || !context.mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _OrderPicturePdfPreviewPage(
          db: db,
          orderData: Map<String, dynamic>.from(orderData),
          lang: lang,
        ),
      ),
    );
  }

  Future<void> _duplicateOrder(Map<String, dynamic> orderData) async {
    final oldId = (orderData['id'] as num?)?.toInt();
    final clientId = (orderData['client_id'] as num?)?.toInt();
    if (oldId == null || clientId == null) {
      throw StateError('بيانات الطلبية أو العميل غير صالحة.');
    }

    final description = orderData['description']?.toString() ?? '';
    final remise = (orderData['remise'] as num?)?.toDouble() ?? 0.0;
    final tva = (orderData['tva'] as num?)?.toDouble() ?? 0.0;
    final total = (orderData['total'] as num?)?.toDouble() ?? 0.0;
    final items = await db.readCommandeDetails(oldId);
    if (items.isEmpty) {
      throw StateError(
        'لا يمكن نسخ هذه الطلبية لأنها لا تحتوي على سطور تفاصيل محفوظة.',
      );
    }

    final copiedDetails = items
        .map(
          (item) => <String, dynamic>{
            'largeur': (item['largeur'] as num?)?.toInt() ?? 0,
            'hauteur': (item['hauteur'] as num?)?.toInt() ?? 0,
            'game': item['game']?.toString() ?? '',
            'quantity': (item['quantity'] as num?)?.toInt() ?? 1,
            'glass': item['glass']?.toString() ?? '',
            'color': item['color']?.toString() ?? '',
            'volet': item['volet']?.toString() ?? '',
            'accessories': item['accessories']?.toString() ?? '',
            'description': item['description']?.toString() ?? '',
            'price': (item['price'] as num?)?.toDouble() ?? 0.0,
            'window_type': item['window_type']?.toString() ?? '',
            'partitions_json': item['partitions_json']?.toString() ?? '{}',
            'drawing_image_path': item['drawing_image_path']?.toString() ?? '',
            if (item['drawing_image_base64'] != null)
              'drawing_image_base64': item['drawing_image_base64'],
          },
        )
        .toList(growable: false);

    await db.saveCommandeWithDetails(
      clientId: clientId,
      status: 'New',
      description: description,
      remise: remise,
      tva: tva,
      total: total,
      netPayable: total - remise + ((total * tva) / 100),
      createdAt: DateTime.now().toIso8601String(),
      details: copiedDetails,
    );
  }

  void _showDeleteConfirmDialog(int id) async {
    // 1. التحقق أولاً من أن عناصر الفاتورة لم تُستخدم في المخزون
    final isUsed = await db.isCommandeUsedInInventory(id);
    if (!mounted) return;

    if (isUsed) {
      // ✋ ممنوع الحذف: العناصر تُستخدم
      showDialog(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Row(
            children: [
              const Icon(Icons.block, color: Colors.red),
              const SizedBox(width: 8),
              const Text('لا يمكن الحذف'),
            ],
          ),
          content: const Text(
            'هذه الطلبية لا يمكن حذفها لأن بعض عناصرها قد تم استخدامها أو خصمها من المخزون.\n\nيمكنك تغيير حالتها بدلاً من حذفها.',
            textAlign: TextAlign.right,
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('موافق'),
            ),
          ],
        ),
      );
      return;
    }

    // 2. التحقق من الصلاحية (المدير فقط)
    final settings = Provider.of<AppSettingsProvider>(context, listen: false);
    if (!settings.canDeleteOrders()) {
      showDialog(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Row(
            children: [
              const Icon(Icons.lock, color: Colors.orange),
              const SizedBox(width: 8),
              const Text('غير مصرح'),
            ],
          ),
          content: const Text(
            'ليس لديك صلاحية حذف الطلبيات.\nتواصل مع المدير للحصول على هذه الصلاحية.',
            textAlign: TextAlign.right,
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('موافق'),
            ),
          ],
        ),
      );
      return;
    }

    // 3. تأكيد الحذف النهائي
    bool? confirm = await showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('تأكيد الحذف'),
        content: const Text(
          'هل أنت متأكد من حذف هذه الطلبية؟\nلا يمكن التراجع عن هذا الإجراء.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('إلغاء'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('حذف', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirm == true) {
      try {
        final deletedRows = await db.deleteCommande(id);
        if (!mounted) return;

        if (deletedRows == 0) {
          // The record may already have been removed by another device.
          // Remove only this stale row, without reloading the page.
          _removeCommandeFromView(id);
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(
              const SnackBar(
                content: Text('الطلبية لم تعد موجودة في قاعدة البيانات.'),
                backgroundColor: Colors.orange,
              ),
            );
          return;
        }

        _removeCommandeFromView(id);
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(
              content: Text('تم حذف الطلبية بنجاح.'),
              backgroundColor: Colors.green,
            ),
          );
      } catch (error) {
        if (!mounted) return;
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text('تعذر حذف الطلبية: $error'),
              backgroundColor: Colors.red,
            ),
          );
      }
    }
  }

  Future<bool> _areAllMeasurementsConfirmed(int orderId) async {
    final details = await db.readCommandeDetails(orderId);
    if (details.isEmpty) return true;
    for (final detail in details) {
      final jsonStr = detail['instances_json']?.toString() ?? '';
      if (jsonStr.isEmpty) {
        return false;
      }
      try {
        final List decoded = jsonDecode(jsonStr);
        int sum = 0;
        for (final inst in decoded) {
          sum += (inst['qty'] as int? ?? 0);
        }
        if (sum != (detail['quantity'] as int)) {
          return false;
        }
      } catch (_) {
        return false;
      }
    }
    return true;
  }

  Future<void> _restoreDocumentImagesFromStoredBytes(
    List<Map<String, dynamic>> items,
  ) async {
    final missingImages = items
        .where((item) {
          final path = item['drawing_image_path']?.toString() ?? '';
          return path.isEmpty || !File(path).existsSync();
        })
        .toList(growable: false);
    if (missingImages.isEmpty) return;

    // A path uploaded by another phone is not valid on this device. Use the
    // image bytes already stored with the row instead of rebuilding the whole
    // window model, which can be very expensive for complex orders.
    late final Directory cacheDirectory;
    try {
      cacheDirectory = await getTemporaryDirectory().timeout(
        const Duration(seconds: 3),
      );
    } catch (_) {
      for (final item in missingImages) {
        item['drawing_image_path'] = '';
      }
      return;
    }

    final writes = missingImages.map((item) async {
      item['drawing_image_path'] = '';
      final raw = item['drawing_image_base64']?.toString().trim() ?? '';
      if (raw.isEmpty) return;

      try {
        final separator = raw.indexOf(',');
        final encoded = raw.startsWith('data:image') && separator >= 0
            ? raw.substring(separator + 1)
            : raw;
        final bytes = base64Decode(encoded);
        if (bytes.isEmpty) return;

        final detailId =
            (item['id'] as num?)?.toInt() ?? encoded.hashCode.abs();
        final file = File(
          '${cacheDirectory.path}${Platform.pathSeparator}'
          'devis_item_$detailId.img',
        );
        if (!await file.exists() || await file.length() != bytes.length) {
          await file
              .writeAsBytes(bytes, flush: false)
              .timeout(const Duration(seconds: 4));
        }
        item['drawing_image_path'] = file.path;
      } catch (error) {
        debugPrint('Unable to restore Devis image: $error');
      }
    });

    try {
      await Future.wait(writes).timeout(const Duration(seconds: 10));
    } catch (error) {
      // A single problematic image must never prevent the Devis from opening.
      debugPrint('Devis image restoration timed out: $error');
    }
  }

  void _showChangeStatusDialog(Map<String, dynamic> orderData) {
    final String currentStatus = orderData['status'] ?? 'Pending';
    final statuses = [
      'Pending',
      'Confirmed',
      'In Progress',
      'Partial Manufacturing',
      'Partial Distribution',
      'Full Manufacturing',
      'Full Distribution',
      'Installation',
      'Reserve',
      'Done',
    ];

    final lang = Provider.of<AppSettingsProvider>(
      context,
      listen: false,
    ).language;

    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              const Icon(Icons.swap_horiz, color: Colors.blue),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  Localization.translate('تغيير حالة الطلبية', lang),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    fontFamily: 'Cairo',
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          content: Container(
            width: double.maxFinite,
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.6,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: statuses.map((stageKey) {
                  final bool isCurrent =
                      (stageKey.toLowerCase() == currentStatus.toLowerCase()) ||
                      (stageKey == 'Pending' &&
                          (currentStatus == 'en_attente' ||
                              currentStatus == 'في الانتظار' ||
                              currentStatus == 'Draft' ||
                              currentStatus == 'New'));
                  final color = _getStatusColor(stageKey);
                  return Container(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    decoration: BoxDecoration(
                      color: isCurrent
                          ? color.withValues(alpha: 0.12)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isCurrent ? color : Colors.grey.shade300,
                        width: isCurrent ? 2 : 1,
                      ),
                    ),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 4,
                      ),
                      leading: CircleAvatar(
                        radius: 12,
                        backgroundColor: color,
                        child: isCurrent
                            ? const Icon(
                                Icons.check,
                                size: 14,
                                color: Colors.white,
                              )
                            : null,
                      ),
                      title: Text(
                        _translateStatus(stageKey, lang),
                        style: TextStyle(
                          fontWeight: isCurrent
                              ? FontWeight.bold
                              : FontWeight.normal,
                          color: isCurrent
                              ? color
                              : (Theme.of(context).brightness == Brightness.dark
                                    ? Colors.white70
                                    : Colors.black87),
                          fontFamily: 'Cairo',
                          fontSize: 14,
                        ),
                      ),
                      trailing: isCurrent
                          ? Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: color,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                lang == AppLanguage.french
                                    ? 'Actuel'
                                    : 'الحالية',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  fontFamily: 'Cairo',
                                ),
                              ),
                            )
                          : const Icon(
                              Icons.chevron_right,
                              size: 18,
                              color: Colors.grey,
                            ),
                      onTap: () async {
                        final progressIndex = statuses.indexOf('In Progress');
                        final targetIndex = statuses.indexOf(stageKey);

                        if (targetIndex > progressIndex) {
                          final allConfirmed =
                              await _areAllMeasurementsConfirmed(
                                orderData['id'],
                              );
                          if (!allConfirmed) {
                            Navigator.pop(dialogContext);
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    lang == AppLanguage.french
                                        ? 'Impossible de passer à la fabrication sans valider les mesures !'
                                        : 'لا يمكن الانتقال للتصنيع إن لم تقم بتأكيد القياسات!',
                                  ),
                                  backgroundColor: Colors.redAccent,
                                ),
                              );
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) =>
                                      OrderMeasurementsConfirmScreen(
                                        orderData: orderData,
                                        db: db,
                                      ),
                                ),
                              );
                            }
                            return;
                          }
                        }

                        Navigator.pop(dialogContext);
                        await db.updateCommandeStatus(
                          orderData['id'],
                          stageKey,
                        );
                        setState(() {
                          _data = db.readCommandesWithClients();
                        });

                        if (stageKey == 'In Progress') {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  lang == AppLanguage.french
                                      ? 'Commande passée à: Confirmation des mesures'
                                      : 'تم نقل الطلبية إلى مرحلة تأكيد القياسات. يرجى تأكيد المقاسات.',
                                ),
                                backgroundColor: Colors.indigo,
                              ),
                            );
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => OrderMeasurementsConfirmScreen(
                                  orderData: orderData,
                                  db: db,
                                ),
                              ),
                            );
                          }
                        } else {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  lang == AppLanguage.french
                                      ? 'Statut changé à: ${_translateStatus(stageKey, lang)}'
                                      : 'تم تغيير حالة الطلبية إلى: ${_translateStatus(stageKey, lang)}',
                                ),
                                backgroundColor: Colors.green,
                              ),
                            );
                          }
                        }
                      },
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(
                Localization.translate('إلغاء', lang),
                style: const TextStyle(fontFamily: 'Cairo'),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showHeavyLoadingDialog(
    BuildContext context,
    AppLanguage lang,
  ) async {
    final ready = Completer<void>();
    BuildContext? shownDialogContext;
    final dialogFuture = showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogCtx) {
        shownDialogContext = dialogCtx;
        _loadingDialogContext = dialogCtx;
        if (!ready.isCompleted) ready.complete();
        return PopScope(
          canPop: false,
          child: AlertDialog(
            content: Row(
              children: [
                const CircularProgressIndicator(),
                const SizedBox(width: 20),
                Text(
                  lang == AppLanguage.french
                      ? 'Génération du document...'
                      : 'جاري تحضير المستند...',
                  style: const TextStyle(fontFamily: 'Cairo'),
                ),
              ],
            ),
          ),
        );
      },
    );
    unawaited(
      dialogFuture.whenComplete(() {
        if (identical(_loadingDialogContext, shownDialogContext)) {
          _loadingDialogContext = null;
        }
        if (!ready.isCompleted) ready.complete();
      }),
    );
    await ready.future;
  }

  String _formatCreatorDisplay(String? rawPlatform) {
    String raw = (rawPlatform ?? '').trim();
    if (raw.isNotEmpty &&
        raw != 'unknown' &&
        raw != 'تطبيق' &&
        raw != 'phone' &&
        raw != 'computer' &&
        raw != 'web' &&
        raw != 'هاتف' &&
        raw != 'كمبيوتر') {
      return raw;
    }
    return 'المدير / عامل الورشة';
  }

  Widget _buildOrderSortableHeaderCell({
    int flex = 1,
    required String label,
    required String colKey,
    required Color mutedColor,
  }) {
    final isSorted = _orderSortColumn == colKey;
    return InkWell(
      onTap: () {
        setState(() {
          if (_orderSortColumn == colKey) {
            if (_orderSortAscending) {
              _orderSortAscending = false;
            } else {
              _orderSortColumn = null;
              _orderSortAscending = true;
            }
          } else {
            _orderSortColumn = colKey;
            _orderSortAscending = true;
          }
        });
      },
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: isSorted ? const Color(0xFF2563EB) : mutedColor,
                  fontFamily: 'Cairo',
                  fontSize: 11,
                  fontWeight: isSorted ? FontWeight.w900 : FontWeight.bold,
                ),
              ),
            ),
            if (isSorted) ...[
              const SizedBox(width: 2),
              Icon(
                _orderSortAscending
                    ? Icons.arrow_upward_rounded
                    : Icons.arrow_downward_rounded,
                size: 13,
                color: const Color(0xFF2563EB),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildOrderFilterInputCell({
    required int flex,
    required TextEditingController controller,
    required String hintText,
    required BuildContext context,
  }) {
    return Expanded(
      flex: flex,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: SizedBox(
          height: 42,
          child: TextField(
            controller: controller,
            onChanged: (_) => setState(() {}),
            style: TextStyle(
              fontSize: 13,
              fontFamily: 'Cairo',
              color: Theme.of(context).textTheme.bodyLarge?.color,
            ),
            decoration: InputDecoration(
              hintText: hintText,
              hintStyle: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade400,
                fontFamily: 'Cairo',
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 7,
              ),
              filled: true,
              fillColor: Theme.of(context).cardColor,
              isDense: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(
                  color: Colors.grey.withValues(alpha: 0.3),
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(
                  color: Colors.grey.withValues(alpha: 0.2),
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(
                  color: Color(0xFF2563EB),
                  width: 1.5,
                ),
              ),
              suffixIcon: controller.text.isNotEmpty
                  ? InkWell(
                      onTap: () {
                        controller.clear();
                        setState(() {});
                      },
                      child: const Icon(
                        Icons.close,
                        size: 17,
                        color: Colors.red,
                      ),
                    )
                  : null,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDesktopOrdersTableView(
    BuildContext context,
    List<Map<String, dynamic>> rawData,
    AppLanguage lang,
  ) {
    final cardColor = Theme.of(context).cardColor;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final contentColor =
        Theme.of(context).textTheme.bodyLarge?.color ?? Colors.black;
    final mutedColor =
        Theme.of(context).textTheme.bodySmall?.color ?? Colors.grey;
    final borderColor = isDark ? Colors.grey.shade800 : Colors.blue.shade100;

    final data = _applyOrderFiltersAndSort(rawData, lang);

    final columns = [
      ResizableTableColumn(
        id: 'id',
        label: _buildOrderSortableHeaderCell(
          label: '#',
          colKey: 'id',
          mutedColor: mutedColor,
        ),
        filter: CompactTableFilterField(
          hintText: '#...',
          isNumeric: true,
          lang: lang,
          initialNumericState:
              _orderNumericFilters['id'] ?? const NumericFilterState(),
          onNumericFilterChanged: (f) =>
              setState(() => _orderNumericFilters['id'] = f),
        ),
        initialWidth: 75,
        minWidth: 55,
        maxWidth: 130,
      ),
      ResizableTableColumn(
        id: 'client_project',
        label: _buildOrderSortableHeaderCell(
          label: Localization.translate('الزبون والمشروع', lang),
          colKey: 'client_project',
          mutedColor: mutedColor,
        ),
        filter: CompactTableFilterField(
          hintText: 'زبون / مشروع...',
          controller: _orderColumnControllers['client_project'],
          lang: lang,
          onTextChanged: (_) => setState(() {}),
        ),
        initialWidth: 220,
        minWidth: 140,
        maxWidth: 380,
      ),
      ResizableTableColumn(
        id: 'date',
        label: _buildOrderSortableHeaderCell(
          label: Localization.translate('تاريخ الإنشاء', lang),
          colKey: 'date',
          mutedColor: mutedColor,
        ),
        filter: CompactTableFilterField(
          hintText: 'سنة-شهر...',
          controller: _orderColumnControllers['date'],
          lang: lang,
          onTextChanged: (_) => setState(() {}),
        ),
        initialWidth: 125,
        minWidth: 95,
        maxWidth: 200,
      ),
      ResizableTableColumn(
        id: 'total',
        label: _buildOrderSortableHeaderCell(
          label: Localization.translate('المجموع الكلي (د.ج)', lang),
          colKey: 'total',
          mutedColor: mutedColor,
        ),
        filter: CompactTableFilterField(
          hintText: 'المجموع...',
          isNumeric: true,
          lang: lang,
          initialNumericState:
              _orderNumericFilters['total'] ?? const NumericFilterState(),
          onNumericFilterChanged: (f) =>
              setState(() => _orderNumericFilters['total'] = f),
        ),
        initialWidth: 130,
        minWidth: 95,
        maxWidth: 220,
      ),
      ResizableTableColumn(
        id: 'advance',
        label: _buildOrderSortableHeaderCell(
          label: Localization.translate('المدفوع', lang),
          colKey: 'advance',
          mutedColor: mutedColor,
        ),
        filter: CompactTableFilterField(
          hintText: 'المدفوع...',
          isNumeric: true,
          lang: lang,
          initialNumericState:
              _orderNumericFilters['advance'] ?? const NumericFilterState(),
          onNumericFilterChanged: (f) =>
              setState(() => _orderNumericFilters['advance'] = f),
        ),
        initialWidth: 120,
        minWidth: 90,
        maxWidth: 200,
      ),
      ResizableTableColumn(
        id: 'remaining',
        label: _buildOrderSortableHeaderCell(
          label: Localization.translate('المتبقي', lang),
          colKey: 'remaining',
          mutedColor: mutedColor,
        ),
        filter: CompactTableFilterField(
          hintText: 'المتبقي...',
          isNumeric: true,
          lang: lang,
          initialNumericState:
              _orderNumericFilters['remaining'] ?? const NumericFilterState(),
          onNumericFilterChanged: (f) =>
              setState(() => _orderNumericFilters['remaining'] = f),
        ),
        initialWidth: 120,
        minWidth: 90,
        maxWidth: 200,
      ),
      ResizableTableColumn(
        id: 'status',
        label: _buildOrderSortableHeaderCell(
          label: Localization.translate('حالة الورشة', lang),
          colKey: 'status',
          mutedColor: mutedColor,
        ),
        filter: CompactTableFilterField(
          hintText: 'حالة الورشة...',
          controller: _orderColumnControllers['status'],
          lang: lang,
          onTextChanged: (_) => setState(() {}),
        ),
        initialWidth: 130,
        minWidth: 95,
        maxWidth: 220,
      ),
      ResizableTableColumn(
        id: 'creator',
        label: _buildOrderSortableHeaderCell(
          label: Localization.translate('المُدخل', lang),
          colKey: 'creator',
          mutedColor: mutedColor,
        ),
        filter: CompactTableFilterField(
          hintText: 'المُدخل...',
          controller: _orderColumnControllers['creator'],
          lang: lang,
          onTextChanged: (_) => setState(() {}),
        ),
        initialWidth: 130,
        minWidth: 95,
        maxWidth: 240,
      ),
      ResizableTableColumn(
        id: 'actions',
        label: Center(
          child: Text(
            Localization.translate('إجراءات', lang),
            style: TextStyle(
              color: mutedColor,
              fontFamily: 'Cairo',
              fontSize: 11.5,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        filter: _hasActiveOrderColumnFilters
            ? Center(
                child: InkWell(
                  onTap: _clearAllOrderColumnFilters,
                  borderRadius: BorderRadius.circular(4),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.clear_all,
                          size: 13,
                          color: Colors.red,
                        ),
                        const SizedBox(width: 2),
                        Text(
                          Localization.translate('مسح', lang),
                          style: const TextStyle(
                            fontSize: 10,
                            color: Colors.red,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              )
            : null,
        initialWidth: 95,
        minWidth: 75,
        maxWidth: 150,
      ),
    ];

    final rows = data.map((order) {
      final clientFirst = order['firstname'] ?? '';
      final clientLast = order['lastname'] ?? '';
      final clientName = '$clientFirst $clientLast'.trim();
      final projectName = (order['project_name'] ?? '').toString().trim();
      final clientProject = projectName.isNotEmpty
          ? '$clientName ($projectName)'
          : (clientName.isEmpty ? 'زبون عام' : clientName);

      final netPayable =
          (order['net_payable'] as num?)?.toDouble() ??
          (order['total'] as num?)?.toDouble() ??
          0.0;
      final advance = (order['advance_payment'] as num?)?.toDouble() ?? 0.0;
      final remaining = netPayable - advance;
      final status = (order['status'] ?? 'Pending').toString();
      final statusColor = _getStatusColor(status);
      final creator = _formatCreatorDisplay(
        order['creation_platform']?.toString(),
      );

      return ResizableTableRow(
        onTap: () => _showOrderOptions(context, order),
        cells: [
          // ID
          Text(
            _displayOrderLabel(order),
            style: const TextStyle(
              color: Color(0xFF2563EB),
              fontFamily: 'Cairo',
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
          // Client & Project
          Text(
            clientProject,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 12.5,
              fontWeight: FontWeight.bold,
              color: contentColor,
            ),
          ),
          // Date
          Text(
            formatDate(order),
            style: TextStyle(
              color: mutedColor,
              fontFamily: 'Cairo',
              fontSize: 11.5,
            ),
          ),
          // Total
          Text(
            '${netPayable.toStringAsFixed(0)} د.ج',
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: contentColor,
            ),
          ),
          // Advance
          Text(
            '${advance.toStringAsFixed(0)} د.ج',
            style: const TextStyle(
              color: Color(0xFF10B981),
              fontFamily: 'Cairo',
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
          // Remaining
          Text(
            '${remaining.toStringAsFixed(0)} د.ج',
            style: TextStyle(
              color: remaining > 0
                  ? const Color(0xFFEF4444)
                  : const Color(0xFF10B981),
              fontFamily: 'Cairo',
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
          // Status
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              _translateStatus(status, lang),
              style: TextStyle(
                color: statusColor,
                fontFamily: 'Cairo',
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          // Creator
          Text(
            creator,
            style: TextStyle(
              color: mutedColor,
              fontFamily: 'Cairo',
              fontSize: 11.5,
            ),
            overflow: TextOverflow.ellipsis,
          ),
          // Actions
          Center(
            child: IconButton(
              icon: const Icon(Icons.more_horiz_rounded, size: 18),
              onPressed: () => _showOrderOptions(context, order),
              tooltip: Localization.translate('خيارات الطلبية', lang),
              visualDensity: VisualDensity.compact,
            ),
          ),
        ],
      );
    }).toList();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Date Range Filter Bar for Desktop ──
          TableDateRangeFilterBar(
            initialRange: _orderDateRange,
            lang: lang,
            compact: true,
            onRangeChanged: (range) {
              setState(() => _orderDateRange = range);
            },
          ),
          const SizedBox(height: 8),

          // ── Desktop Resizable Table with zero vertical overflow ──
          Expanded(
            child: data.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.search_off_rounded,
                          size: 48,
                          color: Colors.grey.shade400,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          Localization.translate("No matching results", lang),
                          style: TextStyle(
                            fontSize: 15,
                            color: Colors.grey.shade600,
                            fontFamily: 'Cairo',
                          ),
                        ),
                        if (_hasActiveOrderColumnFilters) ...[
                          const SizedBox(height: 8),
                          TextButton.icon(
                            onPressed: _clearAllOrderColumnFilters,
                            icon: const Icon(Icons.refresh, size: 16),
                            label: const Text(
                              'إعادة ضبط البحث والتصفية',
                              style: TextStyle(fontFamily: 'Cairo'),
                            ),
                          ),
                        ],
                      ],
                    ),
                  )
                : Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: borderColor),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: SingleChildScrollView(
                        controller: _scrollController,
                        child: ResizableColumnsTable(
                          columns: columns,
                          rows: rows,
                          headerColor: const Color(
                            0xFF2563EB,
                          ).withValues(alpha: 0.08),
                          filterRowColor: isDark
                              ? const Color(0xFF1E293B)
                              : const Color(0xFFF8FAFC),
                          borderColor: borderColor,
                          rowColor: cardColor,
                          headerMinHeight: 38,
                          filterRowMinHeight: 34,
                          rowMinHeight: 46,
                        ),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  void _dismissHeavyLoadingDialog() {
    final dialogContext = _loadingDialogContext;
    _loadingDialogContext = null;
    if (dialogContext == null || !dialogContext.mounted) return;
    Navigator.of(dialogContext).pop();
  }
}

class _OrderPicturePdfPayload {
  const _OrderPicturePdfPayload({required this.bytes, required this.filename});

  final Uint8List bytes;
  final String filename;
}

class _OrderPicturePreviewPayload {
  const _OrderPicturePreviewPayload({
    required this.orderData,
    required this.filename,
    required this.items,
  });

  final Map<String, dynamic> orderData;
  final String filename;
  final List<_OrderPicturePreviewItem> items;
}

class _OrderPicturePreviewItem {
  const _OrderPicturePreviewItem({
    required this.title,
    required this.details,
    required this.quantity,
    required this.width,
    required this.height,
    required this.color,
    required this.imageBytes,
  });

  final String title;
  final List<String> details;
  final int quantity;
  final int width;
  final int height;
  final String color;
  final Uint8List? imageBytes;
}

class _OrderPicturePdfPreviewPage extends StatefulWidget {
  const _OrderPicturePdfPreviewPage({
    required this.db,
    required this.orderData,
    required this.lang,
  });

  final SqlDatabase db;
  final Map<String, dynamic> orderData;
  final AppLanguage lang;

  @override
  State<_OrderPicturePdfPreviewPage> createState() =>
      _OrderPicturePdfPreviewPageState();
}

class _OrderPicturePdfPreviewPageState
    extends State<_OrderPicturePdfPreviewPage> {
  late Future<_OrderPicturePreviewPayload> _future;
  _OrderPicturePdfPayload? _pdfPayload;
  bool _isPdfBusy = false;

  @override
  void initState() {
    super.initState();
    _future = _buildPayload();
  }

  Future<_OrderPicturePreviewPayload> _buildPayload() async {
    var orderData = Map<String, dynamic>.from(widget.orderData);
    final freshOrderId = (orderData['id'] as num?)?.toInt() ?? 0;
    if (freshOrderId > 0) {
      final freshOrder = await widget.db.readCommandeWithClientById(
        freshOrderId,
      );
      if (freshOrder != null) {
        orderData = {...orderData, ...freshOrder};
      }
    }

    final rawItems = freshOrderId > 0
        ? await widget.db.readCommandeDetails(freshOrderId)
        : const <Map<String, dynamic>>[];
    final items = <_OrderPicturePreviewItem>[];
    for (final raw in rawItems) {
      final item = Map<String, dynamic>.from(raw);
      final line = DevisBuilder.buildLineItemFromDetail(
        item,
        overrideLang: widget.lang,
        forceGeneratedDetails: false,
      );
      final imageBytes = await _readPreviewImageBytes(
        item,
      ).timeout(const Duration(seconds: 8), onTimeout: () => null);
      items.add(
        _OrderPicturePreviewItem(
          title: line.title,
          details: line.details,
          quantity: line.quantity,
          width: line.width,
          height: line.height,
          color: line.color,
          imageBytes: imageBytes,
        ),
      );
      await Future.delayed(Duration.zero);
    }

    return _OrderPicturePreviewPayload(
      orderData: orderData,
      filename: OrderPicturePdfService.fileNameFor(orderData, widget.lang),
      items: items,
    );
  }

  void _retry() {
    setState(() {
      _pdfPayload = null;
      _future = _buildPayload();
    });
  }

  Future<_OrderPicturePdfPayload> _ensurePdfPayload(
    _OrderPicturePreviewPayload preview,
  ) async {
    final existing = _pdfPayload;
    if (existing != null) return existing;
    final bytes = await OrderPicturePdfService.buildPdfBytes(
      db: widget.db,
      order: preview.orderData,
      lang: widget.lang,
    ).timeout(const Duration(seconds: 90));
    final payload = _OrderPicturePdfPayload(
      bytes: bytes,
      filename: preview.filename,
    );
    if (mounted) {
      setState(() => _pdfPayload = payload);
    }
    return payload;
  }

  Future<void> _runPdfAction(
    _OrderPicturePreviewPayload preview,
    Future<void> Function(_OrderPicturePdfPayload payload) action,
  ) async {
    if (_isPdfBusy) return;
    setState(() => _isPdfBusy = true);
    try {
      final payload = await _ensurePdfPayload(preview);
      await action(payload);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${Localization.translate('فشل توليد ملف PDF', widget.lang)}: $error',
          ),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isPdfBusy = false);
    }
  }

  Future<void> _save(_OrderPicturePdfPayload payload) async {
    final savedPath = await OrderPicturePdfService.savePdf(
      bytes: payload.bytes,
      filename: payload.filename,
    );
    if (!mounted || savedPath == null) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          Localization.translate('تم حفظ ملف الصور بنجاح', widget.lang),
        ),
        backgroundColor: Colors.green,
      ),
    );
  }

  Future<void> _share(_OrderPicturePdfPayload payload) async {
    await OrderPicturePdfService.sharePdf(
      bytes: payload.bytes,
      filename: payload.filename,
    );
  }

  Future<void> _print(_OrderPicturePdfPayload payload) async {
    await OrderPicturePdfService.printPdf(
      bytes: payload.bytes,
      filename: payload.filename,
    );
  }

  Future<Uint8List?> _readPreviewImageBytes(Map<String, dynamic> item) async {
    // Prefer the exact image saved with the order. Rebuilding the model first
    // can change the drawing after a catalogue/defaults update.
    final path = item['drawing_image_path']?.toString().trim() ?? '';
    if (path.isNotEmpty) {
      try {
        final file = File(path);
        if (await file.exists()) return file.readAsBytes();
      } catch (_) {}
    }

    final raw = item['drawing_image_base64']?.toString().trim() ?? '';
    if (raw.isNotEmpty) {
      try {
        final separator = raw.indexOf(',');
        final encoded = raw.startsWith('data:image') && separator >= 0
            ? raw.substring(separator + 1)
            : raw;
        return base64Decode(encoded);
      } catch (_) {}
    }

    final jsonRaw = item['partitions_json'];
    if (jsonRaw != null) {
      try {
        final decoded = jsonRaw is Map
            ? Map<String, dynamic>.from(jsonRaw)
            : Map<String, dynamic>.from(jsonDecode(jsonRaw.toString()));
        final model = WindowModel(db: widget.db);
        await applyWindowModelAndLoadCatalog(model, decoded);
        return captureWindowImage(
          model,
          maxSide: 3200,
          showDrawingDimensions: true,
        );
      } catch (_) {}
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_OrderPicturePreviewPayload>(
      future: _future,
      builder: (context, snapshot) {
        final payload = snapshot.data;
        return Scaffold(
          appBar: AppBar(
            title: Text(Localization.translate('Picture', widget.lang)),
            actions: [
              if (payload != null) ...[
                IconButton(
                  tooltip: Localization.translate(
                    'حفظ Picture PDF',
                    widget.lang,
                  ),
                  icon: _isPdfBusy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_alt),
                  onPressed: _isPdfBusy
                      ? null
                      : () => _runPdfAction(payload, _save),
                ),
                IconButton(
                  tooltip: Localization.translate(
                    'مشاركة Picture PDF',
                    widget.lang,
                  ),
                  icon: const Icon(Icons.share),
                  onPressed: _isPdfBusy
                      ? null
                      : () => _runPdfAction(payload, _share),
                ),
                IconButton(
                  tooltip: Localization.translate(
                    'طباعة Picture PDF',
                    widget.lang,
                  ),
                  icon: const Icon(Icons.print),
                  onPressed: _isPdfBusy
                      ? null
                      : () => _runPdfAction(payload, _print),
                ),
              ],
            ],
          ),
          body: _buildBody(snapshot, payload),
        );
      },
    );
  }

  Widget _buildBody(
    AsyncSnapshot<_OrderPicturePreviewPayload> snapshot,
    _OrderPicturePreviewPayload? payload,
  ) {
    if (snapshot.hasError) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: Colors.red, size: 42),
              const SizedBox(height: 12),
              Text(
                '${Localization.translate('خطأ أثناء توليد ملف الصور: ', widget.lang)}${snapshot.error}',
                textAlign: TextAlign.center,
                style: const TextStyle(fontFamily: 'Cairo'),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _retry,
                icon: const Icon(Icons.refresh),
                label: Text(
                  Localization.translate('إعادة المحاولة', widget.lang),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (payload == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 14),
            Text(
              Localization.translate('جار تجهيز الصور', widget.lang),
              style: const TextStyle(fontFamily: 'Cairo'),
            ),
          ],
        ),
      );
    }

    if (payload.items.isEmpty) {
      return Center(
        child: Text(
          Localization.translate('لا توجد صور لهذه الطلبية', widget.lang),
          style: const TextStyle(fontFamily: 'Cairo'),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(14),
      itemCount: payload.items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 14),
      itemBuilder: (context, index) {
        final item = payload.items[index];
        return _buildPreviewCard(item, index + 1);
      },
    );
  }

  Widget _buildPreviewCard(_OrderPicturePreviewItem item, int index) {
    final details = item.details
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList(growable: false);
    final meta = <String>[
      if (item.width > 0 || item.height > 0)
        '${Localization.translate('الأبعاد', widget.lang)}: ${item.width} x ${item.height} mm',
      '${Localization.translate('الكمية', widget.lang)}: ${item.quantity}',
      if (item.color.trim().isNotEmpty)
        '${Localization.translate('اللون', widget.lang)}: ${item.color}',
    ];

    return Card(
      clipBehavior: Clip.antiAlias,
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '$index. ${item.title}',
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontFamily: 'Cairo',
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            if (meta.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                meta.join('   |   '),
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontFamily: 'Cairo',
                  color: Colors.grey.shade700,
                  fontSize: 12,
                ),
              ),
            ],
            const SizedBox(height: 10),
            SizedBox(
              height: MediaQuery.sizeOf(context).height * 0.74,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: item.imageBytes == null
                    ? Center(
                        child: Text(
                          Localization.translate(
                            'لا توجد صورة محفوظة لهذا العنصر',
                            widget.lang,
                          ),
                          style: const TextStyle(fontFamily: 'Cairo'),
                        ),
                      )
                    : InteractiveViewer(
                        minScale: 0.7,
                        maxScale: 5,
                        child: Center(
                          child: Image.memory(
                            item.imageBytes!,
                            fit: BoxFit.contain,
                            gaplessPlayback: true,
                          ),
                        ),
                      ),
              ),
            ),
            if (details.isNotEmpty) ...[
              const SizedBox(height: 10),
              ...details.map(
                (line) => Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Text(
                    line,
                    textAlign: TextAlign.right,
                    style: const TextStyle(fontFamily: 'Cairo', fontSize: 12),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
