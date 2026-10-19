import 'dart:async';

import 'package:database_data/widgets/app_material.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:provider/provider.dart';
import '../settings/app_settings.dart';
import '../settings/document_status_localization.dart';
import '../settings/localization.dart';
import '../sql_database.dart';
import '../services/cloud_sync_service.dart';
import '../services/material_sale_pdf_service.dart';
import '../utils/decimal_text_input_formatter.dart';
import '../widgets/resizable_columns_table.dart';

class MaterialSaleEditorScreen extends StatefulWidget {
  final SqlDatabase db;
  final int? saleId; // null = create new
  final String? initialDocType;

  const MaterialSaleEditorScreen({
    super.key,
    required this.db,
    this.saleId,
    this.initialDocType,
  });

  @override
  State<MaterialSaleEditorScreen> createState() =>
      _MaterialSaleEditorScreenState();
}

class _MaterialSaleEditorScreenState extends State<MaterialSaleEditorScreen> {
  static const _blue = Color(0xFF2563EB); // Modern Royal Blue
  static const _cyan = Color(0xFF06B6D4);
  static const _green = Color(0xFF10B981);
  static const _red = Color(0xFFEF4444);

  final _fmt = NumberFormat('#,##0.00');

  /// A catalogue colour name in the app language.
  String _tColor(Object? name) => Localization.colorName(
    name,
    Provider.of<AppSettingsProvider>(context, listen: false).language,
  );

  String _t(String key) {
    final lang = Provider.of<AppSettingsProvider>(
      context,
      listen: false,
    ).language;
    return Localization.translate(key, lang);
  }

  String _trans(String ar, String fr, [String? en]) {
    final lang = Provider.of<AppSettingsProvider>(
      context,
      listen: false,
    ).language;
    if (lang == AppLanguage.french) return fr;
    if (lang == AppLanguage.english) return en ?? fr;
    return ar;
  }

  bool _forceEditing = false;

  // ── Sale header fields ────────────────────────────────────────────────────
  String _saleCode = '';
  String _docType = 'bon_commande';
  String _status = 'draft';
  int? _clientId;
  String _clientName = '';
  String _clientPhone = '';
  String _notes = '';
  DateTime _saleDate = DateTime.now();

  int? _locationId;
  int? _destLocationId;
  bool _isInternal = false;
  int? _linkedAchatId;
  int? _sourceSaleId;
  int? _convertedToSaleId;
  List<Map<String, dynamic>> _storeLocations = [];
  List<Map<String, dynamic>> _workshopLocations = [];

  // Financials
  double _discountAmount = 0.0;
  double _paidAmount = 0.0;

  /// Paid amount stored for this document when it was loaded or last saved.
  /// Raising «المبلغ المسدد» records the difference in the shop cash box.
  double _storedPaidAmount = 0.0;

  // ── Items ─────────────────────────────────────────────────────────────────
  final List<Map<String, dynamic>> _items = [];

  // ── Loading ───────────────────────────────────────────────────────────────
  bool _isLoading = false;
  bool _isSaving = false;

  // ── Controllers ───────────────────────────────────────────────────────────
  final _clientCtrl = TextEditingController();
  final _clientPhoneCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  final _discountCtrl = TextEditingController(text: '0');
  final _paidCtrl = TextEditingController(text: '0');
  final _horizontalTableScrollCtrl = ScrollController();
  final _itemsListScrollCtrl = ScrollController();
  final _headerActionsScrollCtrl = ScrollController();
  final _totalsChipsScrollCtrl = ScrollController();

  // ── Clients list ─────────────────────────────────────────────────────────
  List<Map<String, dynamic>> _clients = [];

  bool get _isInternalClient {
    if (_isInternal) return true;
    final client = _clients.firstWhere(
      (c) => c['id'] == _clientId,
      orElse: () => <String, dynamic>{},
    );
    return client['business_segment'] == 'internal_workshop';
  }

  @override
  void initState() {
    super.initState();
    if (widget.saleId == null && widget.initialDocType != null) {
      _docType = widget.initialDocType!;
    }
    _loadData();
  }

  @override
  void dispose() {
    _clientCtrl.dispose();
    _clientPhoneCtrl.dispose();
    _notesCtrl.dispose();
    _discountCtrl.dispose();
    _paidCtrl.dispose();
    _horizontalTableScrollCtrl.dispose();
    _itemsListScrollCtrl.dispose();
    _headerActionsScrollCtrl.dispose();
    _totalsChipsScrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final settings = Provider.of<AppSettingsProvider>(context, listen: false);
      await widget.db.ensureDiversMaterialClient();
      _storeLocations = await widget.db.readStoreLocations();
      if (_storeLocations.isNotEmpty) {
        final defaultStoreId = settings.defaultStoreLocationId;
        final match = _storeLocations.firstWhere(
          (l) => l['id'] == defaultStoreId,
          orElse: () => _storeLocations.first,
        );
        _locationId ??= match['id'];
      }

      if (settings.isDualActivity) {
        await widget.db.ensureInternalWorkshopClient();
        _clients = await widget.db.readMaterialClients(
          includeInternalWorkshop: true,
        );
        _workshopLocations = await widget.db.readWorkshopLocations();
        if (_workshopLocations.isNotEmpty) {
          final defaultWsId = settings.defaultWorkshopLocationId;
          final match = _workshopLocations.firstWhere(
            (l) => l['id'] == defaultWsId,
            orElse: () => _workshopLocations.first,
          );
          _destLocationId ??= match['id'];
        }
      } else {
        _clients = await widget.db.readMaterialClients(
          includeInternalWorkshop: false,
        );
      }

      if (widget.saleId != null) {
        final sale = await widget.db.readMaterialSaleById(widget.saleId!);
        if (sale != null) {
          _saleCode = sale['sale_code'] ?? '';
          _docType = sale['doc_type'] ?? 'bon_commande';
          _status = sale['status'] ?? 'draft';
          _clientId = sale['client_id'] as int?;
          _clientName = sale['client_name'] ?? '';
          _clientPhone = sale['client_phone'] ?? '';
          _notes = sale['notes'] ?? '';
          _discountAmount =
              (sale['discount_amount'] as num?)?.toDouble() ?? 0.0;
          _paidAmount = (sale['paid_amount'] as num?)?.toDouble() ?? 0.0;
          _storedPaidAmount = _paidAmount;
          _locationId = (sale['location_id'] as num?)?.toInt() ?? _locationId;
          _destLocationId =
              (sale['dest_location_id'] as num?)?.toInt() ?? _destLocationId;
          _isInternal = (sale['is_internal'] as num?)?.toInt() == 1;
          _linkedAchatId = (sale['linked_achat_id'] as num?)?.toInt();
          _sourceSaleId = (sale['source_sale_id'] as num?)?.toInt();
          _convertedToSaleId = (sale['converted_to_sale_id'] as num?)?.toInt();
          final saleDateStr = sale['sale_date'] as String? ?? '';
          if (saleDateStr.isNotEmpty) {
            _saleDate = DateTime.tryParse(saleDateStr) ?? DateTime.now();
          }
          _clientCtrl.text = _clientName;
          _clientPhoneCtrl.text = _clientPhone;
          _notesCtrl.text = _notes;
          _discountCtrl.text = _discountAmount.toStringAsFixed(2);
          _paidCtrl.text = _paidAmount.toStringAsFixed(2);

          final items = await widget.db.readMaterialSaleItems(widget.saleId!);
          _items.addAll(items.map((i) => Map<String, dynamic>.from(i)));
          await _refreshItemAvailability();
        }
      } else {
        _saleCode = await widget.db.nextMaterialSaleCode();
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // ── Calculations ─────────────────────────────────────────────────────────
  double get _subtotal => _items.fold(
    0.0,
    (s, i) => s + ((i['total_price'] as num?)?.toDouble() ?? 0.0),
  );

  double get _subtotalHT => _items.fold(
    0.0,
    (s, i) => s + ((i['total_ht'] as num?)?.toDouble() ?? 0.0),
  );

  double get _totalTax => (_subtotal - _subtotalHT).clamp(0.0, double.infinity);

  double get _netTotal =>
      (_subtotal - _discountAmount).clamp(0.0, double.infinity);

  double get _remainingAmount =>
      (_netTotal - _paidAmount).clamp(0.0, double.infinity);

  bool get _shouldDeductStock {
    if (_status != 'confirmed' && _status != 'delivered') return false;
    return _docType == 'bon_livraison' ||
        _docType == 'bon_route' ||
        _docType == 'facture';
  }

  /// The paid amount may not go below what the cash box already received
  /// for this document: that money would vanish from the document only.
  Future<bool> _paidAmountCanBeSaved() async {
    final saleId = widget.saleId;
    if (saleId == null || _paidAmount >= _storedPaidAmount - 0.01) return true;
    final receipts = await widget.db.materialSaleReceiptsTotal(saleId);
    if (_paidAmount >= receipts - 0.01) return true;
    _showSnack(
      _trans(
        'لا يمكن خفض المبلغ المسدد تحت مجموع الدفعات المسجلة في الصندوق (${_fmt.format(receipts)} DA). احذف الدفعة من الخزينة أولاً.',
        'Le montant payé ne peut pas être inférieur aux paiements déjà encaissés (${_fmt.format(receipts)} DA). Supprimez d’abord le paiement dans la trésorerie.',
        'The paid amount cannot be lower than the payments already received (${_fmt.format(receipts)} DA). Delete the payment in the treasury first.',
      ),
      isError: true,
    );
    return false;
  }

  /// Records in the shop cash box the amount the user added to «المبلغ
  /// المسدد» since the document was loaded, so the document and the cash box
  /// agree. Internal workshop transfers involve no cash.
  Future<void> _recordPaidIncrease(
    int saleId, {
    required double previousPaid,
  }) async {
    if (!_isInternalClient) {
      await widget.db.recordMaterialSalePaidIncrease(
        saleId: saleId,
        previousPaid: previousPaid,
        newPaid: _paidAmount,
        saleCode: _saleCode,
        clientId: _clientId,
        clientName: _clientName,
        clientPhone: _clientPhone,
      );
    }
    _storedPaidAmount = _paidAmount;
  }

  void _recalc() => setState(() {
    _discountAmount =
        double.tryParse(_discountCtrl.text.replaceAll(',', '.')) ?? 0.0;
    _paidAmount = double.tryParse(_paidCtrl.text.replaceAll(',', '.')) ?? 0.0;
  });

  bool get _isLocked =>
      !Provider.of<AppSettingsProvider>(context, listen: false)
              .canEditStoreSales() ||
      ((_convertedToSaleId != null ||
              _status == 'confirmed' ||
              _status == 'delivered' ||
              _status == 'paid') &&
          !_forceEditing);

  void _updateItemCalculations(Map<String, dynamic> item) {
    final qty = (item['quantity'] as num?)?.toDouble() ?? 1.0;
    final unitPriceHT = (item['unit_price'] as num?)?.toDouble() ?? 0.0;
    final taxRate = (item['tax_rate'] as num?)?.toDouble() ?? 0.0;

    // Parse remise (% or flat DA)
    final discountInput = item['discount_input']?.toString().trim() ?? '';
    double itemDiscount = 0.0;
    if (discountInput.endsWith('%')) {
      final cleanPercent = discountInput
          .replaceAll('%', '')
          .replaceAll(',', '.')
          .trim();
      final percent = double.tryParse(cleanPercent) ?? 0.0;
      itemDiscount = (qty * unitPriceHT) * (percent / 100.0);
    } else if (discountInput.isNotEmpty) {
      itemDiscount = double.tryParse(discountInput.replaceAll(',', '.')) ?? 0.0;
    } else {
      itemDiscount = (item['discount_amount'] as num?)?.toDouble() ?? 0.0;
    }
    item['discount_amount'] = itemDiscount;

    final lineBaseHT = ((qty * unitPriceHT) - itemDiscount).clamp(
      0.0,
      double.infinity,
    );
    final lineTotalTTC = lineBaseHT * (1.0 + (taxRate / 100.0));
    final unitPriceTTC = unitPriceHT * (1.0 + (taxRate / 100.0));

    item['total_price'] = lineTotalTTC;
    item['total_ht'] = lineBaseHT;
    item['unit_price_ttc'] = unitPriceTTC;
  }

  Future<void> _refreshItemAvailability() async {
    if (_locationId == null || _items.isEmpty) return;
    final stock = await widget.db.readCurrentStock(_locationId!);
    final Map<String, double> stockMap = {};
    for (final row in stock) {
      final key = "${row['item_id']}_${row['item_type']}_${row['color_id']}";
      stockMap[key] =
          (stockMap[key] ?? 0.0) +
          ((row['quantity'] as num?)?.toDouble() ?? 0.0);
    }
    for (final item in _items) {
      final itemId = (item['item_id'] as num?)?.toInt() ?? 0;
      final itemType = item['item_type']?.toString() ?? '';
      final colorId = (item['color_id'] as num?)?.toInt();
      final key = "${itemId}_${itemType}_${colorId}";
      item['available_quantity'] = stockMap[key] ?? 0.0;
      item['reserved_quantity'] ??= 0.0;
      item['blocked_quantity'] ??= 0.0;
      item['discount_amount'] ??= 0.0;
      _updateItemCalculations(item);
    }
    if (mounted) setState(() {});
  }

  bool _validateBeforePersist() {
    if (_clientName.trim().isEmpty) {
      _showSnack(_t('يرجى اختيار العميل'), isError: true);
      return false;
    }
    if (_hasDuplicateItems) {
      _showSnack(
        _t('يوجد عنصر مكرر. احتفظ بسطر واحد وعدّل كميته.'),
        isError: true,
      );
      return false;
    }
    if (_items.isEmpty) {
      _showSnack(_t('يجب إضافة عنصر واحد على الأقل قبل الحفظ أو التأكيد.'), isError: true);
      return false;
    }
    return true;
  }

  Future<int?> _createCurrentDocument({required String status}) async {
    if (!_validateBeforePersist()) return null;
    final deductsStock =
        (status == 'confirmed' || status == 'delivered') &&
        (_docType == 'bon_livraison' ||
            _docType == 'bon_route' ||
            _docType == 'facture');
    // A new posted document is first persisted as a draft. Its final status is
    // applied only after the complete stock validation/deduction succeeds.
    // Therefore a shortage can never leave a confirmed document without stock.
    final initialStatus = deductsStock ? 'draft' : status;
    final saleId = await widget.db.insertMaterialSale(
      saleCode: _saleCode,
      clientId: _clientId,
      clientName: _clientName,
      clientPhone: _clientPhone,
      docType: _docType,
      status: initialStatus,
      subtotal: _subtotal,
      discountAmount: _discountAmount,
      netTotal: _netTotal,
      paidAmount: _paidAmount,
      remainingAmount: _remainingAmount,
      locationId: _locationId ?? 1,
      notes: _notes,
      saleDate: _saleDate.toUtc().toIso8601String(),
    );
    if (saleId <= 0) return null;
    await widget.db.saveMaterialSaleWithItems(
      saleId: saleId,
      items: _items,
      subtotal: _subtotal,
      discountAmount: _discountAmount,
      netTotal: _netTotal,
      paidAmount: _paidAmount,
    );
    if (_isInternalClient && _destLocationId != null && deductsStock) {
      await widget.db.executeInternalMaterialSaleTransfer(
        saleId: saleId,
        destLocationId: _destLocationId!,
      );
    } else if (deductsStock) {
      await widget.db.deductStockForMaterialSale(
        saleId,
        locationId: _locationId ?? 1,
      );
    }
    if (deductsStock && !(_isInternalClient && _destLocationId != null)) {
      await widget.db.updateMaterialSale(saleId, status: status);
    }
    await _recordPaidIncrease(saleId, previousPaid: 0.0);
    CloudSyncService().notifyChange();
    return saleId;
  }

  Future<void> _validateDocument() async {
    if (!context.read<AppSettingsProvider>().canConfirmStoreSales()) {
      _showSnack(_t('ليست لديك صلاحية تأكيد أو تسليم وثائق المحل'), isError: true);
      return;
    }
    if (_convertedToSaleId != null) return;
    final nextStatus = _docType == 'bon_livraison' ? 'delivered' : 'confirmed';
    setState(() => _isSaving = true);
    try {
      if (widget.saleId == null) {
        final newId = await _createCurrentDocument(status: nextStatus);
        if (newId == null || !mounted) return;
        _showSnack('${_t('تم تأكيد الوثيقة')} ✔', isError: false);
        await Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) =>
                MaterialSaleEditorScreen(db: widget.db, saleId: newId),
          ),
        );
      } else {
        if (!_validateBeforePersist()) return;
        if (!await _paidAmountCanBeSaved()) return;
        await widget.db.snapshotMaterialSale(
          widget.saleId!,
          actionType: 'before_confirm',
          afterHeader: {'status': nextStatus},
          afterItems: _items,
        );
        await widget.db.updateMaterialSale(
          widget.saleId!,
          clientId: _clientId,
          clientName: _clientName,
          clientPhone: _clientPhone,
          docType: _docType,
          subtotal: _subtotal,
          discountAmount: _discountAmount,
          netTotal: _netTotal,
          paidAmount: _paidAmount,
          remainingAmount: _remainingAmount,
          notes: _notes,
          saleDate: _saleDate.toUtc().toIso8601String(),
        );
        await widget.db.saveMaterialSaleWithItems(
          saleId: widget.saleId!,
          items: _items,
          subtotal: _subtotal,
          discountAmount: _discountAmount,
          netTotal: _netTotal,
          paidAmount: _paidAmount,
        );
        final deductsStock =
            (_docType == 'bon_livraison' ||
                _docType == 'bon_route' ||
                _docType == 'facture');
        if (deductsStock) {
          if (_isInternalClient && _destLocationId != null) {
            await widget.db.executeInternalMaterialSaleTransfer(
              saleId: widget.saleId!,
              destLocationId: _destLocationId!,
            );
          } else {
            await widget.db.deductStockForMaterialSale(
              widget.saleId!,
              locationId: _locationId ?? 1,
            );
          }
        }
        if (!(_isInternalClient && _destLocationId != null && deductsStock)) {
          await widget.db.updateMaterialSale(
            widget.saleId!,
            status: nextStatus,
          );
        }
        await _recordPaidIncrease(
          widget.saleId!,
          previousPaid: _storedPaidAmount,
        );
        if (!mounted) return;
        setState(() => _status = nextStatus);
        _showSnack('${_t('تم تأكيد الوثيقة')} ✔', isError: false);
      }
    } catch (e) {
      _showSnack('${_t('خطأ في الحفظ')}: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _transferDocument() async {
    if (_convertedToSaleId != null) return;
    if (_docType != 'bon_commande' &&
        _docType != 'bon_livraison' &&
        _docType != 'devis') {
      return;
    }
    setState(() => _isSaving = true);
    try {
      final sourceId =
          widget.saleId ?? await _createCurrentDocument(status: _status);
      if (sourceId == null) return;
      final targetId = await widget.db.transferMaterialSaleDocument(sourceId);
      if (!mounted) return;
      setState(() => _convertedToSaleId = targetId);
      _showSnack(
        '${_t('تم تحويل الوثيقة وإنشاء الوثيقة التالية')} ✔',
        isError: false,
      );
      await Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) =>
              MaterialSaleEditorScreen(db: widget.db, saleId: targetId),
        ),
      );
    } catch (e) {
      _showSnack('${_t('تعذر تحويل الوثيقة')}: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // ── Régler / Encaissement (صندوق المحل) ──────────────────────────────────────
  Future<void> _showPaymentDialog() async {
    if (!context.read<AppSettingsProvider>().canRegisterStorePayments()) {
      _showSnack(_t('ليست لديك صلاحية تسجيل تحصيلات المحل'), isError: true);
      return;
    }
    if (widget.saleId == null) {
      _showSnack(
        _trans(
          'يرجى حفظ الوثيقة أولاً قبل تسجيل الدفعة في الصندوق',
          'Veuillez enregistrer le document avant d\'enregistrer le paiement',
        ),
        isError: true,
      );
      return;
    }

    final remaining = _remainingAmount;
    final defaultAmount = remaining > 0 ? remaining : _netTotal;
    final amountCtrl = TextEditingController(
      text: defaultAmount > 0 ? defaultAmount.toStringAsFixed(2) : '',
    );
    final notesCtrl = TextEditingController(
      text: 'دفعة لوثيقة $_saleCode - $_clientName',
    );
    String selectedMethod = 'نقداً / Espèce';

    final result = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            title: Row(
              children: [
                const Icon(
                  Icons.point_of_sale_rounded,
                  color: _green,
                  size: 24,
                ),
                const SizedBox(width: 8),
                Text(
                  _trans('تسجيل دفعة (صندوق المحل)', 'Régler / Encaissement'),
                  style: const TextStyle(
                    fontFamily: 'Cairo',
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: _blue.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: _blue.withValues(alpha: 0.3)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${_trans('الوثيقة', 'Document')}: $_saleCode | ${_trans('الزبون', 'Client')}: $_clientName',
                          style: const TextStyle(
                            fontFamily: 'Cairo',
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              '${_trans('الصافي', 'Net')}: ${_fmt.format(_netTotal)} DA',
                              style: const TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 11,
                              ),
                            ),
                            Text(
                              '${_trans('المدفوع', 'Payé')}: ${_fmt.format(_paidAmount)} DA',
                              style: const TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 11,
                                color: _green,
                              ),
                            ),
                            Text(
                              '${_trans('المتبقي', 'Reste')}: ${_fmt.format(_remainingAmount)} DA',
                              style: TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: _remainingAmount > 0 ? _red : _green,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  // Amount field
                  TextField(
                    controller: amountCtrl,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: const [DecimalTextInputFormatter()],
                    decoration: InputDecoration(
                      labelText: _trans(
                        'المبلغ المسدد (DA)',
                        'Montant payé (DA)',
                      ),
                      labelStyle: const TextStyle(fontFamily: 'Cairo'),
                      isDense: true,
                      prefixIcon: const Icon(
                        Icons.attach_money_rounded,
                        color: _green,
                      ),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  // Payment method dropdown
                  DropdownButtonFormField<String>(
                    value: selectedMethod,
                    decoration: InputDecoration(
                      labelText: _trans('طريقة الدفع', 'Mode de paiement'),
                      labelStyle: const TextStyle(fontFamily: 'Cairo'),
                      isDense: true,
                      border: const OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'نقداً / Espèce',
                        child: Text(
                          'نقداً / Espèce',
                          style: TextStyle(fontFamily: 'Cairo'),
                        ),
                      ),
                      DropdownMenuItem(
                        value: 'شيك / Chèque',
                        child: Text(
                          'شيك / Chèque',
                          style: TextStyle(fontFamily: 'Cairo'),
                        ),
                      ),
                      DropdownMenuItem(
                        value: 'تحويل بنكي / Virement',
                        child: Text(
                          'تحويل بنكي / Virement',
                          style: TextStyle(fontFamily: 'Cairo'),
                        ),
                      ),
                    ],
                    onChanged: (val) {
                      if (val != null)
                        setDialogState(() => selectedMethod = val);
                    },
                  ),
                  const SizedBox(height: 10),
                  // Caisse name (dedicated store cashbox)
                  InputDecorator(
                    decoration: InputDecoration(
                      labelText: _trans('الصندوق المستهدف', 'Caisse cible'),
                      labelStyle: const TextStyle(fontFamily: 'Cairo'),
                      isDense: true,
                      border: const OutlineInputBorder(),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.store_rounded,
                          size: 18,
                          color: Colors.teal,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          _trans(
                            'صندوق المحل (Caisse Magasin)',
                            'Caisse Magasin',
                          ),
                          style: const TextStyle(
                            fontFamily: 'Cairo',
                            fontWeight: FontWeight.bold,
                            color: Colors.teal,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  // Notes
                  TextField(
                    controller: notesCtrl,
                    decoration: InputDecoration(
                      labelText: _trans(
                        'البيان / ملاحظات الدفعة',
                        'Description / Notes',
                      ),
                      labelStyle: const TextStyle(fontFamily: 'Cairo'),
                      isDense: true,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogCtx, false),
                child: Text(
                  _trans('إلغاء', 'Annuler'),
                  style: const TextStyle(fontFamily: 'Cairo'),
                ),
              ),
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: _green),
                icon: const Icon(Icons.check_rounded, size: 18),
                label: Text(
                  _trans('تأكيد الدفع', 'Valider paiement'),
                  style: const TextStyle(
                    fontFamily: 'Cairo',
                    fontWeight: FontWeight.bold,
                  ),
                ),
                onPressed: () {
                  final amount =
                      double.tryParse(amountCtrl.text.replaceAll(',', '.')) ??
                      0.0;
                  if (amount <= 0 || amount > _remainingAmount + 0.000001) {
                    return;
                  }
                  Navigator.pop(dialogCtx, true);
                },
              ),
            ],
          );
        },
      ),
    );

    if (result != true) return;
    final payAmount =
        double.tryParse(amountCtrl.text.replaceAll(',', '.')) ?? 0.0;
    if (payAmount <= 0 || payAmount > _remainingAmount + 0.000001) {
      _showSnack(
        _trans(
          'مبلغ الدفع أكبر من المتبقي في الوثيقة',
          'Le paiement dépasse le reste du document',
        ),
        isError: true,
      );
      return;
    }

    try {
      setState(() => _isSaving = true);
      await widget.db.insertTreasury(
        'encaissement',
        payAmount,
        notesCtrl.text.trim().isNotEmpty
            ? notesCtrl.text.trim()
            : 'دفعة مبيعات مواد: $_saleCode (${_clientName})',
        referenceId: widget.saleId,
        recordedBy: 'user',
        entityType: 'Client',
        entityId: _clientId,
        phone: _clientPhone,
        caisseName: 'صندوق المحل',
        paymentMethod: selectedMethod,
        documentType: SqlDatabase.materialSaleDocumentType,
      );

      final newPaid = _paidAmount + payAmount;
      final newRemaining = (_netTotal - newPaid).clamp(0.0, double.infinity);
      _paidAmount = newPaid;
      _storedPaidAmount = newPaid;
      _paidCtrl.text = _paidAmount.toStringAsFixed(2);

      await widget.db.updateMaterialSale(
        widget.saleId!,
        paidAmount: _paidAmount,
        remainingAmount: newRemaining,
      );

      CloudSyncService().notifyChange();
      _showSnack(
        _trans(
          'تم تسجيل الدفعة (${_fmt.format(payAmount)} DA) في صندوق المحل بنجاح ✔',
          'Paiement (${_fmt.format(payAmount)} DA) enregistré dans la Caisse Magasin ✔',
        ),
        isError: false,
      );
      setState(() {});
    } catch (e) {
      _showSnack(
        '${_trans('خطأ أثناء تسجيل الدفعة', 'Erreur de paiement')}: $e',
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  String _statusHelpText() {
    switch (_status) {
      case 'draft':
        return _t('مسودة: الوثيقة قيد التحضير ولا تغيّر المخزون.');
      case 'reserved':
        return _t('محجوز: الكمية مخصّصة للعميل ولم تُسلّم بعد.');
      case 'confirmed':
        return _t('مؤكد: تم اعتماد الوثيقة وأصبحت جاهزة للتنفيذ.');
      case 'delivered':
        return _t('تم التسليم: خرجت المواد وسُلّمت للعميل.');
      case 'paid':
        return _t('مدفوع: تم تسديد المبلغ الكامل للوثيقة.');
      case 'cancelled':
        return _t('ملغى: الوثيقة متوقفة ولا تُنفّذ.');
      default:
        return '';
    }
  }

  bool _sameSaleItem(Map<String, dynamic> first, Map<String, dynamic> second) {
    return ((first['item_id'] as num?)?.toInt() ?? 0) ==
            ((second['item_id'] as num?)?.toInt() ?? 0) &&
        (first['item_type']?.toString() ?? '') ==
            (second['item_type']?.toString() ?? '') &&
        (first['color_id'] as num?)?.toInt() ==
            (second['color_id'] as num?)?.toInt();
  }

  bool get _hasDuplicateItems {
    for (var i = 0; i < _items.length; i++) {
      for (var j = i + 1; j < _items.length; j++) {
        if (_sameSaleItem(_items[i], _items[j])) return true;
      }
    }
    return false;
  }

  // ── Save ──────────────────────────────────────────────────────────────────
  Future<void> _save() async {
    final settings = context.read<AppSettingsProvider>();
    if (widget.saleId == null
        ? !settings.canCreateStoreSales()
        : !settings.canEditStoreSales()) {
      _showSnack(_t('ليست لديك صلاحية حفظ تعديلات وثائق المحل'), isError: true);
      return;
    }
    if (widget.saleId != null &&
        (_status == 'confirmed' ||
            _status == 'delivered' ||
            _status == 'paid')) {
      _showSnack(
        _t('لا يمكن تعديل عناصر وثيقة مُرحّلة مباشرة. ألغِ الحركة أو أنشئ وثيقة تصحيح للحفاظ على سلامة المخزون والسجل.'),
        isError: true,
      );
      return;
    }
    if (_clientName.trim().isEmpty) {
      _showSnack(_t('يرجى اختيار العميل'), isError: true);
      return;
    }
    if (_hasDuplicateItems) {
      _showSnack(
        _t('يوجد عنصر مكرر. احتفظ بسطر واحد وعدّل كميته.'),
        isError: true,
      );
      return;
    }
    setState(() => _isSaving = true);
    try {
      final saleDateStr = _saleDate.toUtc().toIso8601String();

      final isInternal = _isInternalClient;
      if (widget.saleId == null) {
        // Create new
        final newId = await widget.db.insertMaterialSale(
          saleCode: _saleCode,
          clientId: _clientId,
          clientName: _clientName,
          clientPhone: _clientPhone,
          docType: _docType,
          status: _status,
          subtotal: _subtotal,
          discountAmount: _discountAmount,
          netTotal: _netTotal,
          paidAmount: _paidAmount,
          remainingAmount: _remainingAmount,
          locationId: _locationId ?? 1,
          notes: _notes,
          saleDate: saleDateStr,
        );
        if (newId > 0) {
          await widget.db.saveMaterialSaleWithItems(
            saleId: newId,
            items: _items,
            subtotal: _subtotal,
            discountAmount: _discountAmount,
            netTotal: _netTotal,
            paidAmount: _paidAmount,
          );
          if (isInternal && _destLocationId != null && _shouldDeductStock) {
            await widget.db.executeInternalMaterialSaleTransfer(
              saleId: newId,
              destLocationId: _destLocationId!,
            );
          } else if (_shouldDeductStock) {
            await widget.db.deductStockForMaterialSale(
              newId,
              locationId: _locationId ?? 1,
            );
          }
          await _recordPaidIncrease(newId, previousPaid: 0.0);
        }
      } else {
        // Update existing
        if (!await _paidAmountCanBeSaved()) return;
        await widget.db.snapshotMaterialSale(
          widget.saleId!,
          actionType: 'before_update',
          afterHeader: {
            'client_id': _clientId,
            'client_name': _clientName,
            'client_phone': _clientPhone,
            'doc_type': _docType,
            'status': _status,
            'subtotal': _subtotal,
            'discount_amount': _discountAmount,
            'net_total': _netTotal,
            'paid_amount': _paidAmount,
            'remaining_amount': _remainingAmount,
            'notes': _notes,
            'sale_date': saleDateStr,
          },
          afterItems: _items,
        );
        await widget.db.updateMaterialSale(
          widget.saleId!,
          clientId: _clientId,
          clientName: _clientName,
          clientPhone: _clientPhone,
          docType: _docType,
          status: _status,
          subtotal: _subtotal,
          discountAmount: _discountAmount,
          netTotal: _netTotal,
          paidAmount: _paidAmount,
          remainingAmount: _remainingAmount,
          notes: _notes,
          saleDate: saleDateStr,
        );
        await widget.db.saveMaterialSaleWithItems(
          saleId: widget.saleId!,
          items: _items,
          subtotal: _subtotal,
          discountAmount: _discountAmount,
          netTotal: _netTotal,
          paidAmount: _paidAmount,
        );
        if (isInternal && _destLocationId != null && _shouldDeductStock) {
          await widget.db.executeInternalMaterialSaleTransfer(
            saleId: widget.saleId!,
            destLocationId: _destLocationId!,
          );
        } else if (_shouldDeductStock) {
          await widget.db.deductStockForMaterialSale(
            widget.saleId!,
            locationId: _locationId ?? 1,
          );
        }
        await _recordPaidIncrease(
          widget.saleId!,
          previousPaid: _storedPaidAmount,
        );
      }

      CloudSyncService().notifyChange();
      if (mounted) {
        _showSnack('${_t('تم الحفظ بنجاح')} ✔', isError: false);
        Navigator.pop(context, true);
      }
    } catch (e) {
      _showSnack('${_t('خطأ في الحفظ')}: $e', isError: true);
    } finally {
      setState(() => _isSaving = false);
    }
  }

  // ── Reverse Internal Transfer (إلغاء التحويل واسترجاع المواد للمحل) ───────────
  Future<void> _reverseInternalTransfer() async {
    if (widget.saleId == null) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          _t('إلغاء التحويل الداخلي'),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        content: Text(
          _t(
            'هل أنت متأكد من إلغاء هذا التحويل الداخلي؟ سيتم إرجاع المواد من مستودع الورشة إلى مستودع المحل وتوثيق حركة عكسية دون حذف السجل التاريخي.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(_t('تراجع')),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: _red,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(_t('تأكيد الإرجاع للمحل')),
          ),
        ],
      ),
    );

    if (confirm != true) return;
    setState(() => _isSaving = true);
    try {
      await widget.db.cancelOrReverseInternalMaterialSaleTransfer(
        saleId: widget.saleId!,
      );
      if (mounted) {
        _showSnack(
          '${_t('تم إرجاع المواد وإلغاء التحويل الداخلي بنجاح')} ✔',
          isError: false,
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      _showSnack('${_t('خطأ أثناء إلغاء التحويل')}: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // ── Print ─────────────────────────────────────────────────────────────────
  Future<void> _printDoc() async {
    if (widget.saleId == null && _items.isEmpty) {
      _showSnack(_t('يرجى إضافة عنصر واحد على الأقل'), isError: true);
      return;
    }
    final sale = {
      'sale_code': _saleCode,
      'client_name': _clientName,
      'client_phone': _clientPhone,
      'doc_type': _docType,
      'status': _status,
      'subtotal': _subtotal,
      'discount_amount': _discountAmount,
      'net_total': _netTotal,
      'paid_amount': _paidAmount,
      'remaining_amount': _remainingAmount,
      'notes': _notes,
      'sale_date': _saleDate.toIso8601String(),
    };
    try {
      final bytes = await MaterialSalePdfService.generate(
        sale: sale,
        items: _items,
      );
      await MaterialSalePdfService.printOrShare(bytes, _saleCode);
    } catch (e) {
      _showSnack('${_t('خطأ في الطباعة')}: $e', isError: true);
    }
  }

  void _showSnack(String msg, {required bool isError}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(fontFamily: 'Cairo')),
        backgroundColor: isError ? _red : _green,
      ),
    );
  }

  // ── Add item ──────────────────────────────────────────────────────────────
  void _openItemPicker() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => Dialog(
        insetPadding: const EdgeInsets.all(18),
        clipBehavior: Clip.antiAlias,
        child: _ItemPickerSheet(
          db: widget.db,
          onItemSelected: (item) {
            final alreadyAdded = _items.any(
              (existing) => _sameSaleItem(existing, item),
            );
            if (alreadyAdded) {
              _showSnack(
                _t('هذا العنصر مضاف مسبقًا. عدّل كميته من السطر الموجود.'),
                isError: true,
              );
              return;
            }
            setState(() => _items.add(item));
          },
        ),
      ),
    );
  }

  // ── Remove item ───────────────────────────────────────────────────────────
  void _removeItem(int index) {
    setState(() => _items.removeAt(index));
  }

  // ── Edit item quantity/price inline ───────────────────────────────────────
  void _editItemDialog(int index) {
    final item = _items[index];
    final qtyCtrl = TextEditingController(
      text: (item['quantity'] as num?)?.toStringAsFixed(2) ?? '1',
    );
    final priceCtrl = TextEditingController(
      text: (item['unit_price'] as num?)?.toStringAsFixed(2) ?? '0',
    );
    final taxCtrl = TextEditingController(
      text: (item['tax_rate'] as num?)?.toStringAsFixed(2) ?? '0',
    );
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(
          item['item_name'] ?? '',
          style: const TextStyle(fontFamily: 'Cairo', fontSize: 14),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: qtyCtrl,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: const [
                DecimalTextInputFormatter(decimalDigits: 3),
              ],
              decoration: InputDecoration(
                labelText: _t('الكمية'),
                labelStyle: const TextStyle(fontFamily: 'Cairo'),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: taxCtrl,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: const [DecimalTextInputFormatter()],
              decoration: InputDecoration(
                labelText: '${_t('الضريبة')} (%)',
                labelStyle: const TextStyle(fontFamily: 'Cairo'),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: priceCtrl,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: const [DecimalTextInputFormatter()],
              decoration: InputDecoration(
                labelText: _t('سعر الوحدة'),
                labelStyle: const TextStyle(fontFamily: 'Cairo'),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              _t('إلغاء'),
              style: const TextStyle(fontFamily: 'Cairo'),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: _blue),
            onPressed: () {
              final qty =
                  double.tryParse(qtyCtrl.text.replaceAll(',', '.')) ?? 1.0;
              final price =
                  double.tryParse(priceCtrl.text.replaceAll(',', '.')) ?? 0.0;
              final tax =
                  double.tryParse(taxCtrl.text.replaceAll(',', '.')) ?? 0.0;
              setState(() {
                _items[index]['quantity'] = qty;
                _items[index]['unit_price'] = price;
                _items[index]['tax_rate'] = tax;
                _items[index]['total_price'] = qty * price * (1 + tax / 100);
              });
              Navigator.pop(context);
            },
            child: Text(
              _t('حفظ'),
              style: const TextStyle(fontFamily: 'Cairo', color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  // ── Client picker dialog ───────────────────────────────────────────────────
  String _clientDisplayName(Map<String, dynamic> client) {
    if (client['business_segment'] == 'internal_workshop') {
      return _t('الورشة (داخلي)');
    }
    final rawFirst = (client['firstname'] ?? '').toString().trim();
    if (rawFirst.toLowerCase() == 'divers' &&
        (client['lastname'] ?? '').toString().trim().isEmpty) {
      return _trans('Divers (زبون عام)', 'Divers', 'General customer (Divers)');
    }
    final direct = client['name']?.toString().trim() ?? '';
    if (direct.isNotEmpty) return direct;
    return [client['firstname'], client['lastname']]
        .map((value) => value?.toString().trim() ?? '')
        .where((value) => value.isNotEmpty)
        .join(' ');
  }


  String _clientPhoneOf(Map<String, dynamic> client) =>
      (client['phone1'] ?? client['phone'] ?? '').toString();

  Future<Map<String, dynamic>?> _addMaterialClient(
    BuildContext parentContext,
  ) async {
    final firstNameCtrl = TextEditingController();
    final lastNameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final result = await showDialog<Map<String, String>>(
      context: parentContext,
      barrierDismissible: false,
      useRootNavigator: false,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          _t('إضافة زبون مواد جديد'),
          style: const TextStyle(fontFamily: 'Cairo'),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: firstNameCtrl,
              decoration: InputDecoration(labelText: _t('الاسم')),
            ),
            TextField(
              controller: lastNameCtrl,
              decoration: InputDecoration(labelText: _t('اللقب')),
            ),
            TextField(
              controller: phoneCtrl,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(labelText: _t('رقم الهاتف')),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(_t('إلغاء')),
          ),
          FilledButton(
            onPressed: () {
              if (firstNameCtrl.text.trim().isEmpty) return;
              Navigator.pop(dialogContext, {
                'firstname': firstNameCtrl.text.trim(),
                'lastname': lastNameCtrl.text.trim(),
                'phone': phoneCtrl.text.trim(),
              });
            },
            child: Text(_t('إضافة')),
          ),
        ],
      ),
    );
    firstNameCtrl.dispose();
    lastNameCtrl.dispose();
    phoneCtrl.dispose();
    if (result == null) return null;
    final id = await widget.db.insertClient(
      result['firstname']!,
      result['lastname']!,
      result['phone']!,
      '',
      '',
      '',
    );
    await widget.db.setClientBusinessSegment(id, 'materials');
    final settings = Provider.of<AppSettingsProvider>(
      context,
      listen: false,
    );
    final clients = await widget.db.readMaterialClients(
      includeInternalWorkshop: settings.isDualActivity,
    );
    _clients = clients;
    for (final client in clients) {
      if (client['id'] == id) return client;
    }
    return null;
  }

  Future<void> _selectMaterialClient(Map<String, dynamic> client) async {
    final isInternal = client['business_segment'] == 'internal_workshop';
    if (client['business_segment'] == 'windows') {
      await widget.db.setClientBusinessSegment(client['id'] as int, 'both');
    }
    if (!mounted) return;
    setState(() {
      _clientId = client['id'] as int?;
      _clientName = _clientDisplayName(client);
      _clientPhone = _clientPhoneOf(client);
      _isInternal = isInternal;
      _clientCtrl.text = _clientName;
      _clientPhoneCtrl.text = _clientPhone;
    });
  }

  Future<void> _openClientPicker() async {
    final search = TextEditingController();
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      useRootNavigator: false,
      builder: (pickerContext) {
        List<Map<String, dynamic>> filtered = List.from(_clients);
        var includeWindowClients = false;
        return StatefulBuilder(
          builder: (ctx, setS) {
            void applySearch(List<Map<String, dynamic>> source) {
              final q = search.text.trim().toLowerCase();
              filtered = source.where((client) {
                return _clientDisplayName(client).toLowerCase().contains(q) ||
                    _clientPhoneOf(client).toLowerCase().contains(q);
              }).toList();
            }

            return AlertDialog(
              title: Text(
                _t('اختر عميلاً'),
                style: const TextStyle(fontFamily: 'Cairo', fontSize: 14),
              ),
              content: SizedBox(
                width: 350,
                height: 400,
                child: Column(
                  children: [
                    TextField(
                      controller: search,
                      decoration: InputDecoration(
                        hintText: _t('بحث...'),
                        hintStyle: const TextStyle(fontFamily: 'Cairo'),
                        prefixIcon: const Icon(Icons.search),
                      ),
                      onChanged: (v) {
                        setS(() => applySearch(_clients));
                      },
                    ),
                    SwitchListTile.adaptive(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      value: includeWindowClients,
                      title: Text(
                        _t('إظهار زبائن النوافذ أيضًا'),
                        style: const TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 12,
                        ),
                      ),
                      onChanged: (value) async {
                        final settings = Provider.of<AppSettingsProvider>(
                          context,
                          listen: false,
                        );
                        final clients = await widget.db.readMaterialClients(
                          includeWindowClients: value,
                          includeInternalWorkshop: settings.isDualActivity,
                        );
                        if (!ctx.mounted) return;
                        setS(() {
                          includeWindowClients = value;
                          _clients = clients;
                          applySearch(clients);
                        });
                      },
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: ListView.builder(
                        itemCount: filtered.length,
                        itemBuilder: (_, i) {
                          final c = filtered[i];
                          return ListTile(
                            title: Text(
                              _clientDisplayName(c),
                              style: const TextStyle(fontFamily: 'Cairo'),
                            ),
                            subtitle: Text(
                              _clientPhoneOf(c),
                              style: const TextStyle(fontFamily: 'Cairo'),
                            ),
                            trailing: Text(
                              c['business_segment'] == 'internal_workshop'
                                  ? _t('داخلي (الورشة)')
                                  : c['business_segment'] == 'both'
                                  ? _t('مشترك')
                                  : c['business_segment'] == 'materials'
                                  ? _t('مواد')
                                  : _t('نوافذ'),
                              style: TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 10,
                                fontWeight:
                                    c['business_segment'] == 'internal_workshop'
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                                color:
                                    c['business_segment'] == 'internal_workshop'
                                    ? Colors.amber.shade800
                                    : null,
                              ),
                            ),
                            onTap: () async {
                              await _selectMaterialClient(c);
                              if (ctx.mounted) Navigator.of(ctx).pop();
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton.icon(
                  onPressed: () async {
                    final client = await _addMaterialClient(ctx);
                    if (client == null || !ctx.mounted) return;
                    await _selectMaterialClient(client);
                    if (ctx.mounted) Navigator.of(ctx).pop();
                  },
                  icon: const Icon(Icons.person_add_alt_1_rounded),
                  label: Text(_t('زبون مواد جديد')),
                ),
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: Text(
                    _t('إلغاء'),
                    style: const TextStyle(fontFamily: 'Cairo'),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
    search.dispose();
  }

  // ── BUILD ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final isNew = widget.saleId == null;
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: _blue,
        foregroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.white),
        actionsIconTheme: const IconThemeData(color: Colors.white),
        title: Text(
          isNew
              ? _trans('وثيقة جديدة', 'Nouveau document')
              : '${_trans('تعديل الوثيقة', 'Document')} / $_saleCode',
          style: const TextStyle(
            fontFamily: 'Cairo',
            fontSize: 15,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        actions: [
          if (widget.saleId != null &&
              (_convertedToSaleId != null || _status == 'delivered'))
            IconButton(
              icon: Icon(
                _forceEditing
                    ? Icons.lock_open_rounded
                    : Icons.edit_note_rounded,
                color: Colors.white,
              ),
              tooltip: _forceEditing
                  ? _trans('إلغاء وضع التعديل', 'Verrouiller')
                  : _trans('تعديل الوثيقة', 'Éditer'),
              onPressed: () {
                setState(() => _forceEditing = !_forceEditing);
                _showSnack(
                  _forceEditing
                      ? _trans(
                          'تم تفعيل وضع التعديل على الوثيقة ✔',
                          'Mode édition déverrouillé ✔',
                        )
                      : _trans('تم قفل الوثيقة مجددًا', 'Document verrouillé'),
                  isError: false,
                );
              },
            ),
          if (widget.saleId != null && _isInternal && _status == 'delivered')
            IconButton(
              icon: const Icon(Icons.undo_rounded, color: Colors.orangeAccent),
              tooltip: _trans(
                'إرجاع المواد وإلغاء التحويل',
                'Annuler le transfert interne',
              ),
              onPressed: _reverseInternalTransfer,
            ),
          IconButton(
            icon: const Icon(Icons.print_rounded, color: Colors.white),
            tooltip: _trans('طباعة', 'Imprimer'),
            onPressed: _printDoc,
          ),
          if (_isSaving)
            const Padding(
              padding: EdgeInsets.all(12),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.save_rounded, color: Colors.white),
              tooltip: _trans('حفظ', 'Enregistrer'),
              onPressed: _save,
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // ── Header form (Compact Single Row) ─────────────────────────
                _buildHeaderCard(),
                // ── Unified Horizontal Scrollable Table ───────────────────────
                Expanded(
                  child: ResizableColumnsTable(
                    persistenceKey: 'material_sale_editor_items',
                    horizontalController: _horizontalTableScrollCtrl,
                    verticalController: _itemsListScrollCtrl,
                    headerMinHeight: 48,
                    rowMinHeight: 52,
                    cellPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 5,
                    ),
                    columns: _buildResizableItemColumns(),
                    rows: _buildResizableItemRows(),
                    emptyPlaceholder: _buildItemsList(),
                  ),
                ),
                // ── Totals footer + Notes ────────────────────────────────────
                _buildTotalsBar(),
              ],
            ),
      floatingActionButton: _isLocked
          ? null
          : FloatingActionButton(
              mini: true,
              backgroundColor: _cyan,
              foregroundColor: Colors.white,
              tooltip: _trans('إضافة عنصر', 'Ajouter un article'),
              onPressed: _openItemPicker,
              child: const Icon(Icons.add_rounded, color: Colors.white),
            ),
    );
  }

  // ── Header card (Compact Layout) ──────────────────────────────────────────
  Widget _buildHeaderCard() {
    final fieldTextColor = Theme.of(context).colorScheme.onSurface;
    final surfaceColor = Theme.of(context).colorScheme.surface;
    final isLocked = _isLocked;

    return Container(
      margin: const EdgeInsets.fromLTRB(10, 6, 10, 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: Theme.of(context).dividerColor.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Row 1: Sale Code + Date + Quick Actions (Valider / Transférer / Régler)
          LayoutBuilder(
            builder: (context, headerConstraints) {
              final isNarrow = headerConstraints.maxWidth < 750;
              final rowChildren = <Widget>[
                Text(
                  _saleCode,
                  style: const TextStyle(
                    fontFamily: 'Cairo',
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                    color: _blue,
                  ),
                ),
                const SizedBox(width: 14),
                InkWell(
                  onTap: isLocked
                      ? null
                      : () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: _saleDate,
                            firstDate: DateTime(2020),
                            lastDate: DateTime(2030),
                          );
                          if (picked != null)
                            setState(() => _saleDate = picked);
                        },
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.calendar_today_rounded,
                        size: 14,
                        color: _blue,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        DateFormat('dd/MM/yyyy').format(_saleDate),
                        style: const TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                if (!isNarrow) const Spacer() else const SizedBox(width: 16),
                if (widget.saleId != null &&
                    (_convertedToSaleId != null || _status == 'delivered')) ...[
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      foregroundColor: _forceEditing
                          ? Colors.orange.shade800
                          : _blue,
                      side: BorderSide(
                        color: _forceEditing ? Colors.orange : _blue,
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                    ),
                    icon: Icon(
                      _forceEditing
                          ? Icons.lock_open_rounded
                          : Icons.edit_note_rounded,
                      size: 16,
                    ),
                    label: Text(
                      _forceEditing
                          ? _trans('إلغاء وضع التعديل', 'Verrouiller')
                          : _trans('تعديل الوثيقة (Éditer)', 'Éditer'),
                      style: const TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 11.5,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    onPressed: () {
                      setState(() => _forceEditing = !_forceEditing);
                      _showSnack(
                        _forceEditing
                            ? _trans(
                                'تم فتح الوثيقة للتعديل ✔',
                                'Mode édition actif ✔',
                              )
                            : _trans('تم قفل الوثيقة', 'Document verrouillé'),
                        isError: false,
                      );
                    },
                  ),
                  const SizedBox(width: 8),
                ],
                if (_convertedToSaleId == null && !isLocked) ...[
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      foregroundColor: _blue,
                      side: const BorderSide(color: _blue),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 2,
                      ),
                    ),
                    icon: const Icon(
                      Icons.check_circle_outline_rounded,
                      size: 16,
                    ),
                    label: Text(
                      _trans('Valider (تأكيد)', 'Valider'),
                      style: const TextStyle(fontFamily: 'Cairo', fontSize: 12),
                    ),
                    onPressed: _validateDocument,
                  ),
                  const SizedBox(width: 8),
                ],
                if (_convertedToSaleId == null &&
                    (_docType == 'bon_commande' ||
                        _docType == 'bon_livraison' ||
                        _docType == 'devis')) ...[
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      backgroundColor: _green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 2,
                      ),
                    ),
                    icon: const Icon(Icons.swap_horiz_rounded, size: 16),
                    label: Text(
                      _trans('Transférer (تحويل)', 'Transférer'),
                      style: const TextStyle(fontFamily: 'Cairo', fontSize: 12),
                    ),
                    onPressed: _transferDocument,
                  ),
                  const SizedBox(width: 8),
                ],
                // Payment is recorded from the delivery note, not the order.
                if (_docType == 'bon_livraison')
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      backgroundColor: const Color(0xFF059669),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 2,
                      ),
                    ),
                    icon: const Icon(
                      Icons.payments_rounded,
                      size: 16,
                      color: Colors.white,
                    ),
                    label: Text(
                      _trans('دفع (صندوق المحل)', 'Régler (Caisse)'),
                      style: const TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    onPressed: _showPaymentDialog,
                  ),
              ];

              if (isNarrow) {
                return SingleChildScrollView(
                  controller: _headerActionsScrollCtrl,
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: rowChildren,
                  ),
                );
              }
              return Row(children: rowChildren);
            },
          ),
          const SizedBox(height: 6),
          // Document data becomes two columns on phones, with the client on a
          // full-width row so long names remain readable.
          LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 720;
              final halfWidth = (constraints.maxWidth - 8) / 2;
              final desktopClientWidth =
                  (constraints.maxWidth -
                          230 -
                          110 -
                          (_storeLocations.isEmpty ? 0 : 170) -
                          24)
                      .clamp(180.0, constraints.maxWidth)
                      .toDouble();
              return Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  // 1. Doc Type
                  SizedBox(
                    width: compact ? halfWidth : 230,
                    child: DropdownButtonFormField<String>(
                      value: _docType,
                      isExpanded: true,
                      dropdownColor: surfaceColor,
                      iconEnabledColor: fieldTextColor,
                      decoration: InputDecoration(
                        labelText: _trans('نوع الوثيقة', 'Type de document'),
                        labelStyle: const TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 11,
                        ),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        border: const OutlineInputBorder(),
                      ),
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 12,
                        color: fieldTextColor,
                        fontWeight: FontWeight.w600,
                      ),
                      items: [
                        DropdownMenuItem(
                          value: 'bon_commande',
                          child: Text(
                            _trans('طلب مواد (Commande)', 'Commande Matériaux'),
                          ),
                        ),
                        DropdownMenuItem(
                          value: 'bon_livraison',
                          child: Text(
                            _trans(
                              'وصل تسليم مواد (Livraison)',
                              'Bon de Livraison',
                            ),
                          ),
                        ),
                        DropdownMenuItem(
                          value: 'bon_route',
                          child: Text(
                            _trans('وصل مسار مواد (Route)', 'Bon de Route'),
                          ),
                        ),
                        DropdownMenuItem(
                          value: 'facture',
                          child: Text(
                            _trans(
                              'فاتورة مواد (Facture)',
                              'Facture Matériaux',
                            ),
                          ),
                        ),
                        DropdownMenuItem(
                          value: 'devis',
                          child: Text(
                            _trans('فاتورة أولية (Devis)', 'Devis Matériaux'),
                          ),
                        ),
                      ],
                      onChanged: isLocked
                          ? null
                          : (v) => setState(() => _docType = v ?? _docType),
                    ),
                  ),
                  // 2. Status
                  SizedBox(
                    width: compact ? halfWidth : 110,
                    child: InputDecorator(
                      decoration: InputDecoration(
                        labelText: _trans('الحالة', 'Statut'),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        border: const OutlineInputBorder(),
                      ),
                      child: Text(
                        localizeDocumentStatus(
                          _status,
                          Provider.of<AppSettingsProvider>(
                            context,
                            listen: false,
                          ).language,
                        ),
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          color: fieldTextColor,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  // 3. Client: always full width on a phone.
                  SizedBox(
                    width: compact ? constraints.maxWidth : desktopClientWidth,
                    child: GestureDetector(
                      onTap: isLocked ? null : _openClientPicker,
                      child: AbsorbPointer(
                        child: TextField(
                          controller: _clientCtrl,
                          minLines: 1,
                          maxLines: compact ? 2 : 1,
                          decoration: InputDecoration(
                            labelText: _trans('العميل', 'Client'),
                            labelStyle: const TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 11,
                            ),
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 8,
                            ),
                            border: const OutlineInputBorder(),
                            suffixIcon: const Icon(
                              Icons.person_search_rounded,
                              color: _blue,
                              size: 20,
                            ),
                          ),
                          style: const TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                          onChanged: (v) => setState(() => _clientName = v),
                        ),
                      ),
                    ),
                  ),
                  // 4. Warehouse location
                  if (_storeLocations.isNotEmpty)
                    SizedBox(
                      width: compact ? constraints.maxWidth : 170,
                      child: DropdownButtonFormField<int>(
                        value: _locationId,
                        isDense: true,
                        decoration: InputDecoration(
                          labelText: _trans('مستودع المحل', 'Dépôt'),
                          labelStyle: const TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 11,
                          ),
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 8,
                          ),
                          border: const OutlineInputBorder(),
                        ),
                        items: _storeLocations.map((loc) {
                          return DropdownMenuItem<int>(
                            value: (loc['id'] as num).toInt(),
                            child: Text(
                              loc['name']?.toString() ?? '',
                              style: const TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 12,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          );
                        }).toList(),
                        onChanged: isLocked
                            ? null
                            : (val) async {
                                setState(() => _locationId = val);
                                await _refreshItemAvailability();
                              },
                      ),
                    ),
                ],
              );
            },
          ),
          // Locked Notice
          if (_convertedToSaleId != null || _status == 'delivered') ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: _forceEditing
                    ? Colors.orange.shade50
                    : Colors.amber.shade50,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: _forceEditing
                      ? Colors.orange.shade400
                      : Colors.amber.shade400,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    _forceEditing
                        ? Icons.lock_open_rounded
                        : Icons.lock_rounded,
                    size: 16,
                    color: _forceEditing
                        ? Colors.orange.shade800
                        : Colors.amber.shade900,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _forceEditing
                          ? _trans(
                              'وضع التعديل مفعل: يمكنك تعديل المنتجات والأسعار والكميات بحرية.',
                              'Mode édition actif: vous pouvez modifier les lignes.',
                            )
                          : (_convertedToSaleId != null
                                ? '${_trans('هذه الطلبية مرتبطة بوصل تسليم رقم', 'Liée au bon de livraison')} (#$_convertedToSaleId) - ${_trans('مقفلة ضد التعديل.', 'Verrouillé.')}'
                                : _trans(
                                    'تم تسليم هذه الوثيقة - مقفلة ضد التعديل.',
                                    'Document livré - Verrouillé.',
                                  )),
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 11.5,
                        fontWeight: FontWeight.bold,
                        color: _forceEditing
                            ? Colors.orange.shade900
                            : Colors.amber.shade900,
                      ),
                    ),
                  ),
                  TextButton(
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    onPressed: () {
                      setState(() => _forceEditing = !_forceEditing);
                    },
                    child: Text(
                      _forceEditing
                          ? _trans('قفل الوثيقة', 'Verrouiller')
                          : _trans('فتح للتعديل (Éditer)', 'Éditer'),
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontWeight: FontWeight.bold,
                        fontSize: 11.5,
                        color: _forceEditing ? Colors.red : _blue,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── Items header (Synchronized Columns with HT & TTC) ─────────────────────
  List<ResizableTableColumn> _buildResizableItemColumns() {
    Widget title(String ar, String fr, {Color? color, TextAlign? align}) => Text(
      _trans(ar, fr),
      textAlign: align,
      style: TextStyle(
        fontFamily: 'Cairo',
        fontSize: 11.5,
        fontWeight: FontWeight.bold,
        color: color,
      ),
    );

    return [
      ResizableTableColumn(
        id: 'article',
        label: title('المنتج', 'Article'),
        initialWidth: 240,
        minWidth: 150,
      ),
      ResizableTableColumn(
        id: 'code',
        label: title('الرمز', 'Code', align: TextAlign.center),
        initialWidth: 85,
        minWidth: 65,
        alignment: Alignment.center,
      ),
      ResizableTableColumn(
        id: 'unit',
        label: title('الوحدة', 'Unité', align: TextAlign.center),
        initialWidth: 70,
        minWidth: 55,
        alignment: Alignment.center,
      ),
      ResizableTableColumn(
        id: 'available',
        label: title('المتوفر', 'Dispo', color: Colors.blueGrey),
        initialWidth: 85,
        alignment: Alignment.center,
      ),
      ResizableTableColumn(
        id: 'reserved',
        label: title('محجوز', 'Réservé', color: Colors.deepOrange),
        initialWidth: 90,
        alignment: Alignment.center,
      ),
      ResizableTableColumn(
        id: 'blocked',
        label: title('معطل', 'Bloqué', color: Colors.redAccent),
        initialWidth: 80,
        alignment: Alignment.center,
      ),
      ResizableTableColumn(
        id: 'quantity',
        label: title('الكمية المطلوبة', 'Qté demandée', color: _blue),
        initialWidth: 110,
        minWidth: 90,
        alignment: Alignment.center,
      ),
      ResizableTableColumn(
        id: 'discount',
        label: title('الخصم (%/DA)', 'Remise (%/DA)', color: Colors.purple),
        initialWidth: 105,
        minWidth: 85,
        alignment: Alignment.center,
      ),
      ResizableTableColumn(
        id: 'tax',
        label: title('الضريبة', 'TVA %'),
        initialWidth: 75,
        alignment: Alignment.center,
      ),
      ResizableTableColumn(
        id: 'price_ht',
        label: title('سعر HT', 'Prix HT'),
        initialWidth: 110,
        alignment: Alignment.centerRight,
      ),
      ResizableTableColumn(
        id: 'price_ttc',
        label: title('سعر TTC', 'Prix TTC', color: Colors.indigo),
        initialWidth: 110,
        alignment: Alignment.centerRight,
      ),
      ResizableTableColumn(
        id: 'total_ht',
        label: title('إجمالي HT', 'Total HT'),
        initialWidth: 125,
        alignment: Alignment.centerRight,
      ),
      ResizableTableColumn(
        id: 'total_ttc',
        label: title('إجمالي TTC', 'Total TTC', color: _blue),
        initialWidth: 130,
        alignment: Alignment.centerRight,
      ),
      ResizableTableColumn(
        id: 'actions',
        label: const Icon(Icons.more_horiz_rounded, size: 18),
        initialWidth: 58,
        minWidth: 48,
        maxWidth: 90,
        alignment: Alignment.center,
      ),
    ];
  }

  List<ResizableTableRow> _buildResizableItemRows() {
    final isLocked = _isLocked;
    return List<ResizableTableRow>.generate(_items.length, (i) {
      final item = _items[i];
      final total = (item['total_price'] as num?)?.toDouble() ?? 0.0;
      final totalHT = (item['total_ht'] as num?)?.toDouble() ?? 0.0;
      final unitPriceTTC =
          (item['unit_price_ttc'] as num?)?.toDouble() ?? 0.0;
      final qty = (item['quantity'] as num?)?.toDouble() ?? 1.0;
      final price = (item['unit_price'] as num?)?.toDouble() ?? 0.0;
      final tax = (item['tax_rate'] as num?)?.toDouble() ?? 0.0;
      final remise = (item['discount_amount'] as num?)?.toDouble() ?? 0.0;
      final available =
          (item['available_quantity'] as num?)?.toDouble() ?? 0.0;
      final reserved =
          (item['reserved_quantity'] as num?)?.toDouble() ?? 0.0;
      final blocked =
          (item['blocked_quantity'] as num?)?.toDouble() ?? 0.0;
      final colorName = item['color_name'] as String? ?? '';
      final systemName = (item['system_name'] ?? '').toString().trim();
      final seriesName = (item['series_name'] ?? '').toString().trim();
      final systemAndSeries = <String>[
        if (systemName.isNotEmpty) systemName,
        if (seriesName.isNotEmpty && seriesName != systemName) seriesName,
      ].join(' / ');
      final hasShortage = qty > (available - reserved - blocked);

      const regular = TextStyle(fontFamily: 'Cairo', fontSize: 11.5);
      Widget centered(String value, {Color? color, FontWeight? weight}) => Text(
        value,
        textAlign: TextAlign.center,
        style: regular.copyWith(color: color, fontWeight: weight),
      );
      Widget numericField({
        required String initialValue,
        required ValueChanged<String> onChanged,
        TextInputType keyboardType = TextInputType.text,
        Color? color,
        bool shortage = false,
        TextAlign textAlign = TextAlign.center,
      }) => TextFormField(
        key: ValueKey('${item['id'] ?? i}-$initialValue'),
        initialValue: initialValue,
        textAlign: textAlign,
        keyboardType: keyboardType,
        inputFormatters: keyboardType == TextInputType.text
            ? null
            : const [DecimalTextInputFormatter()],
        decoration: InputDecoration(
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 5, vertical: 7),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
          filled: shortage,
          fillColor: shortage ? Colors.red.withValues(alpha: 0.08) : null,
        ),
        style: regular.copyWith(
          color: shortage ? Colors.red : color,
          fontWeight: FontWeight.bold,
        ),
        onChanged: onChanged,
      );

      return ResizableTableRow(
        reorderId: (item['id'] ?? 'new_$i').toString(),
        color: i.isEven ? null : Theme.of(context).colorScheme.surfaceContainerLowest,
        cells: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                item['item_name'] ?? '',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: regular.copyWith(fontSize: 12.5, fontWeight: FontWeight.w600),
              ),
              if (systemAndSeries.isNotEmpty)
                Text(
                  systemAndSeries,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: regular.copyWith(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: _blue,
                  ),
                ),
              if (colorName.isNotEmpty)
                Text(_tColor(colorName), style: regular.copyWith(fontSize: 10.5, color: Colors.blueGrey)),
            ],
          ),
          centered((item['item_code'] ?? '—').toString()),
          centered(item['unit'] ?? ''),
          centered(
            _fmt.format(available),
            color: available <= 0 ? Colors.red : Colors.blueGrey,
            weight: FontWeight.bold,
          ),
          centered(_fmt.format(reserved), color: Colors.deepOrange),
          centered(_fmt.format(blocked), color: blocked > 0 ? Colors.red : Colors.grey),
          isLocked
              ? centered(_fmt.format(qty), weight: FontWeight.bold)
              : numericField(
                  initialValue: qty.toStringAsFixed(2),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  shortage: hasShortage,
                  onChanged: (value) {
                    item['quantity'] = double.tryParse(value.replaceAll(',', '.')) ?? 0.0;
                    setState(() => _updateItemCalculations(item));
                  },
                ),
          isLocked
              ? centered(item['discount_input']?.toString() ?? _fmt.format(remise))
              : numericField(
                  initialValue: item['discount_input']?.toString() ??
                      (remise > 0 ? remise.toStringAsFixed(2) : '0'),
                  color: Colors.purple,
                  onChanged: (value) {
                    item['discount_input'] = value;
                    setState(() => _updateItemCalculations(item));
                  },
                ),
          centered(_fmt.format(tax)),
          isLocked
              ? Text(_fmt.format(price), textAlign: TextAlign.right, style: regular)
              : numericField(
                  initialValue: price.toStringAsFixed(2),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  textAlign: TextAlign.right,
                  onChanged: (value) {
                    item['unit_price'] = double.tryParse(value.replaceAll(',', '.')) ?? 0.0;
                    setState(() => _updateItemCalculations(item));
                  },
                ),
          Text(
            _fmt.format(unitPriceTTC),
            textAlign: TextAlign.right,
            style: regular.copyWith(fontWeight: FontWeight.w600, color: Colors.indigo),
          ),
          Text(
            '${_fmt.format(totalHT)} DA',
            textAlign: TextAlign.right,
            style: regular.copyWith(color: Colors.blueGrey),
          ),
          Text(
            '${_fmt.format(total)} DA',
            textAlign: TextAlign.right,
            style: regular.copyWith(fontSize: 12.5, fontWeight: FontWeight.bold, color: _blue),
          ),
          isLocked
              ? const SizedBox.shrink()
              : IconButton(
                  icon: const Icon(Icons.remove_circle_outline_rounded, color: Colors.red, size: 18),
                  onPressed: () => _removeItem(i),
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                ),
        ],
      );
    });
  }

  Widget _buildItemsHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: _blue.withValues(alpha: 0.08),
      child: Row(
        children: [
          SizedBox(
            width: 200,
            child: Text(
              _trans('المنتج', 'Article'),
              style: const TextStyle(
                fontFamily: 'Cairo',
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          SizedBox(
            width: 65,
            child: Text(
              _trans('الرمز', 'Code'),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: 'Cairo',
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          SizedBox(
            width: 50,
            child: Text(
              _trans('الوحدة', 'Unité'),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: 'Cairo',
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          SizedBox(
            width: 65,
            child: Text(
              _trans('المتوفر', 'Dispo'),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: 'Cairo',
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Colors.blueGrey,
              ),
            ),
          ),
          SizedBox(
            width: 70,
            child: Text(
              _trans('محجوز', 'Réservé'),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: 'Cairo',
                fontSize: 11.5,
                fontWeight: FontWeight.bold,
                color: Colors.deepOrange,
              ),
            ),
          ),
          SizedBox(
            width: 60,
            child: Text(
              _trans('معطل', 'Bloqué'),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: 'Cairo',
                fontSize: 11.5,
                fontWeight: FontWeight.bold,
                color: Colors.redAccent,
              ),
            ),
          ),
          SizedBox(
            width: 85,
            child: Text(
              _trans('الكمية المطلوبة', 'Qté demandée'),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: 'Cairo',
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: _blue,
              ),
            ),
          ),
          SizedBox(
            width: 80,
            child: Text(
              _trans('الخصم (%/DA)', 'Remise (%/DA)'),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: 'Cairo',
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: Colors.purple,
              ),
            ),
          ),
          SizedBox(
            width: 60,
            child: Text(
              '${_trans('الضريبة', 'TVA')} %',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: 'Cairo',
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          SizedBox(
            width: 90,
            child: Text(
              _trans('سعر HT', 'Prix HT'),
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontFamily: 'Cairo',
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          SizedBox(
            width: 90,
            child: Text(
              _trans('سعر TTC', 'Prix TTC'),
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontFamily: 'Cairo',
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Colors.indigo,
              ),
            ),
          ),
          SizedBox(
            width: 100,
            child: Text(
              _trans('إجمالي HT', 'Total HT'),
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontFamily: 'Cairo',
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          SizedBox(
            width: 105,
            child: Text(
              _trans('إجمالي TTC', 'Total TTC'),
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontFamily: 'Cairo',
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: _blue,
              ),
            ),
          ),
          const SizedBox(width: 45),
        ],
      ),
    );
  }

  // ── Items list (Inline Editing + HT/TTC calculations) ─────────────────────
  Widget _buildItemsList() {
    if (_items.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.inventory_2_outlined,
              size: 54,
              color: Colors.grey.shade300,
            ),
            const SizedBox(height: 10),
            Text(
              '${_trans('لا توجد عناصر مضافة بعد', 'Aucun article ajouté')}\n${_trans('أضف منتجات من الزر في الأسفل (+)', 'Ajoutez des articles avec le bouton (+)')}',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: 'Cairo',
                color: Colors.grey,
                fontSize: 13,
              ),
            ),
          ],
        ),
      );
    }

    final isLocked = _isLocked;

    return ListView.builder(
      controller: _itemsListScrollCtrl,
      primary: false,
      padding: const EdgeInsets.only(bottom: 12),
      itemCount: _items.length,
      itemBuilder: (_, i) {
        final item = _items[i];
        final total = (item['total_price'] as num?)?.toDouble() ?? 0.0;
        final totalHT = (item['total_ht'] as num?)?.toDouble() ?? 0.0;
        final unitPriceTTC =
            (item['unit_price_ttc'] as num?)?.toDouble() ?? 0.0;
        final qty = (item['quantity'] as num?)?.toDouble() ?? 1.0;
        final price = (item['unit_price'] as num?)?.toDouble() ?? 0.0;
        final tax = (item['tax_rate'] as num?)?.toDouble() ?? 0.0;
        final remise = (item['discount_amount'] as num?)?.toDouble() ?? 0.0;
        final available =
            (item['available_quantity'] as num?)?.toDouble() ?? 0.0;
        final reserved = (item['reserved_quantity'] as num?)?.toDouble() ?? 0.0;
        final blocked = (item['blocked_quantity'] as num?)?.toDouble() ?? 0.0;
        final colorName = item['color_name'] as String? ?? '';
        final hasShortage = qty > (available - reserved - blocked);

        return Container(
          decoration: BoxDecoration(
            color: i.isEven
                ? Theme.of(context).colorScheme.surface
                : Theme.of(context).colorScheme.surfaceContainerLow,
            border: Border(
              bottom: BorderSide(
                color: Theme.of(context).dividerColor.withValues(alpha: 0.5),
                width: 0.5,
              ),
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Row(
            children: [
              // 1. Article & Color
              SizedBox(
                width: 200,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      item['item_name'] ?? '',
                      style: const TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (colorName.isNotEmpty)
                      Text(
                        _tColor(colorName),
                        style: const TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 10.5,
                          color: Colors.blueGrey,
                        ),
                      ),
                  ],
                ),
              ),
              // 2. Code
              SizedBox(
                width: 65,
                child: Text(
                  (item['item_code'] ?? '—').toString(),
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontFamily: 'Cairo', fontSize: 11),
                ),
              ),
              // 3. Unit
              SizedBox(
                width: 50,
                child: Text(
                  item['unit'] ?? '',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontFamily: 'Cairo', fontSize: 11),
                ),
              ),
              // 4. Available Stock
              SizedBox(
                width: 65,
                child: Text(
                  _fmt.format(available),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 11.5,
                    fontWeight: FontWeight.bold,
                    color: available <= 0 ? Colors.red : Colors.blueGrey,
                  ),
                ),
              ),
              // 5. Reserved "محجوز"
              SizedBox(
                width: 70,
                child: Text(
                  _fmt.format(reserved),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 11,
                    color: Colors.deepOrange,
                  ),
                ),
              ),
              // 6. Blocked "معطل"
              SizedBox(
                width: 60,
                child: Text(
                  _fmt.format(blocked),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 11,
                    color: blocked > 0 ? Colors.red : Colors.grey,
                  ),
                ),
              ),
              // 7. Quantity (Inline Editable)
              SizedBox(
                width: 85,
                child: isLocked
                    ? Text(
                        _fmt.format(qty),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontFamily: 'Cairo',
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      )
                    : TextFormField(
                        initialValue: qty.toStringAsFixed(2),
                        textAlign: TextAlign.center,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        inputFormatters: const [DecimalTextInputFormatter()],
                        decoration: InputDecoration(
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 6,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(6),
                          ),
                          fillColor: hasShortage
                              ? Colors.red.withValues(alpha: 0.08)
                              : null,
                          filled: hasShortage,
                        ),
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: hasShortage ? Colors.red : null,
                        ),
                        onChanged: (val) {
                          final parsed =
                              double.tryParse(val.replaceAll(',', '.')) ?? 0.0;
                          setState(() {
                            item['quantity'] = parsed;
                            _updateItemCalculations(item);
                          });
                        },
                      ),
              ),
              // 8. Remise Ligne (% or flat DA, Inline Editable)
              SizedBox(
                width: 80,
                child: isLocked
                    ? Text(
                        item['discount_input']?.toString() ??
                            _fmt.format(remise),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 11,
                        ),
                      )
                    : TextFormField(
                        initialValue:
                            item['discount_input']?.toString() ??
                            (remise > 0 ? remise.toStringAsFixed(2) : '0'),
                        textAlign: TextAlign.center,
                        keyboardType: TextInputType.text,
                        decoration: InputDecoration(
                          isDense: true,
                          hintText: '0 / %',
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 6,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                        style: const TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 11.5,
                          color: Colors.purple,
                          fontWeight: FontWeight.bold,
                        ),
                        onChanged: (val) {
                          setState(() {
                            item['discount_input'] = val;
                            _updateItemCalculations(item);
                          });
                        },
                      ),
              ),
              // 9. Tax %
              SizedBox(
                width: 60,
                child: Text(
                  _fmt.format(tax),
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontFamily: 'Cairo', fontSize: 11),
                ),
              ),
              // 10. Unit Price HT (Inline Editable)
              SizedBox(
                width: 90,
                child: isLocked
                    ? Text(
                        _fmt.format(price),
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 12,
                        ),
                      )
                    : TextFormField(
                        initialValue: price.toStringAsFixed(2),
                        textAlign: TextAlign.right,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        inputFormatters: const [DecimalTextInputFormatter()],
                        decoration: InputDecoration(
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 6,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                        style: const TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 12,
                        ),
                        onChanged: (val) {
                          final parsed =
                              double.tryParse(val.replaceAll(',', '.')) ?? 0.0;
                          setState(() {
                            item['unit_price'] = parsed;
                            _updateItemCalculations(item);
                          });
                        },
                      ),
              ),
              // 11. Unit Price TTC (Calculated)
              SizedBox(
                width: 90,
                child: Text(
                  _fmt.format(unitPriceTTC),
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.indigo,
                  ),
                ),
              ),
              // 12. Line Total HT
              SizedBox(
                width: 100,
                child: Text(
                  '${_fmt.format(totalHT)} DA',
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 12,
                    color: Colors.blueGrey,
                  ),
                ),
              ),
              // 13. Line Total TTC
              SizedBox(
                width: 105,
                child: Text(
                  '${_fmt.format(total)} DA',
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 12.5,
                    fontWeight: FontWeight.bold,
                    color: _blue,
                  ),
                ),
              ),
              // 14. Delete Action
              SizedBox(
                width: 45,
                child: isLocked
                    ? null
                    : IconButton(
                        icon: const Icon(
                          Icons.remove_circle_outline_rounded,
                          color: Colors.red,
                          size: 18,
                        ),
                        onPressed: () => _removeItem(i),
                        padding: EdgeInsets.zero,
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ── Totals footer + Notes (Enlarged Notes & Full HT/TTC Summary) ───────────
  Widget _buildTotalsBar() {
    final isLocked = _isLocked;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).shadowColor.withValues(alpha: 0.10),
            blurRadius: 6,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Row 1: Notes (Larger multiline flex 3) + Global Discount + Paid amount
          LayoutBuilder(
            builder: (context, constraints) {
              final isNarrow = constraints.maxWidth < 700;
              final notesField = TextField(
                controller: _notesCtrl,
                readOnly: isLocked,
                minLines: 2,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: _trans('ملاحظات الوثيقة', 'Notes / Remarques'),
                  labelStyle: const TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 11,
                  ),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  border: const OutlineInputBorder(),
                ),
                style: const TextStyle(fontFamily: 'Cairo', fontSize: 12),
                onChanged: (v) => _notes = v,
              );
              final discountField = TextField(
                controller: _discountCtrl,
                readOnly: isLocked,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: const [DecimalTextInputFormatter()],
                decoration: InputDecoration(
                  labelText: '${_trans('خصم إجمالي', 'Remise')} (DA)',
                  labelStyle: const TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 11,
                  ),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  border: const OutlineInputBorder(),
                ),
                style: const TextStyle(fontFamily: 'Cairo', fontSize: 12),
                onChanged: (_) => _recalc(),
              );
              final paidField = TextField(
                controller: _paidCtrl,
                readOnly: isLocked,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: const [DecimalTextInputFormatter()],
                decoration: InputDecoration(
                  labelText: _trans('المبلغ المسدد', 'Montant payé'),
                  labelStyle: const TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 11,
                  ),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  border: const OutlineInputBorder(),
                ),
                style: const TextStyle(fontFamily: 'Cairo', fontSize: 12),
                onChanged: (_) => _recalc(),
              );

              if (isNarrow) {
                return Column(
                  children: [
                    notesField,
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(child: discountField),
                        const SizedBox(width: 8),
                        Expanded(child: paidField),
                      ],
                    ),
                  ],
                );
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 3, child: notesField),
                  const SizedBox(width: 8),
                  Expanded(child: discountField),
                  const SizedBox(width: 8),
                  Expanded(child: paidField),
                ],
              );
            },
          ),
          const SizedBox(height: 8),
          // Row 2: Totals Chips (Total HT, TVA, Total TTC, Remise, Net TTC, Reste)
          SingleChildScrollView(
            controller: _totalsChipsScrollCtrl,
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _totalChip(
                  _trans('إجمالي بدون ضريبة (HT)', 'Total HT'),
                  _fmt.format(_subtotalHT),
                  Colors.grey.shade700,
                ),
                const SizedBox(width: 8),
                _totalChip(
                  _trans('مجموع الضريبة (TVA)', 'Total TVA'),
                  _fmt.format(_totalTax),
                  Colors.teal.shade700,
                ),
                const SizedBox(width: 8),
                _totalChip(
                  _trans('المجموع الشامل (TTC)', 'Total TTC'),
                  _fmt.format(_subtotal),
                  Colors.indigo.shade800,
                ),
                const SizedBox(width: 8),
                _totalChip(
                  _trans('الخصم الإجمالي', 'Remise'),
                  _fmt.format(_discountAmount),
                  _red,
                ),
                const SizedBox(width: 8),
                _totalChip(
                  _trans('المبلغ الصافي', 'Net à payer'),
                  _fmt.format(_netTotal),
                  _blue,
                  isBold: true,
                ),
                const SizedBox(width: 8),
                _totalChip(
                  _trans('المبلغ المتبقي', 'Reste à payer'),
                  _fmt.format(_remainingAmount),
                  _remainingAmount > 0 ? _red : _green,
                  isBold: true,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _totalChip(
    String label,
    String value,
    Color color, {
    bool isBold = false,
  }) {
    return SizedBox(
      width: 190,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              label,
              style: TextStyle(fontFamily: 'Cairo', fontSize: 10, color: color),
            ),
            Text(
              '$value DA',
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: isBold ? 13 : 12,
                fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// ITEM PICKER BOTTOM SHEET
// ═══════════════════════════════════════════════════════════════════════════

class _ItemPickerSheet extends StatefulWidget {
  final SqlDatabase db;
  final void Function(Map<String, dynamic>) onItemSelected;

  const _ItemPickerSheet({required this.db, required this.onItemSelected});

  @override
  State<_ItemPickerSheet> createState() => _ItemPickerSheetState();
}

class _ItemPickerSheetState extends State<_ItemPickerSheet> {
  static const _blue = Color(0xFF1E3A8A);

  String _t(String key) {
    final lang = Provider.of<AppSettingsProvider>(
      context,
      listen: true,
    ).language;
    return Localization.translate(key, lang);
  }

  String _selectedCategory = 'All';
  String _selectedProfile = '';
  final _searchCtrl = TextEditingController();
  final _searchFocus = FocusNode();
  List<Map<String, dynamic>> _items = [];
  List<String> _profileNames = [];
  final Map<int, List<Map<String, dynamic>>> _sectionColorsByProfile = {};
  final Map<String, double> _stockQuantities = {};
  Map<String, dynamic>? _selectedItem;
  List<Map<String, dynamic>> _selectedItemColors = const [];
  int? _selectedColorId;
  String _selectedColorName = '';
  final _quantityCtrl = TextEditingController(text: '1');
  final _priceCtrl = TextEditingController(text: '0.00');
  bool _loading = false;
  bool _stockLoaded = false;
  bool _showSearchResults = true;
  Timer? _searchDebounce;

  List<Map<String, String>> get _categories => [
    {'id': 'All', 'label': _t('كل شيء'), 'icon': 'apps'},
    {'id': 'Sections', 'label': _t('مقاطع'), 'icon': 'architecture'},
    {'id': 'Accessories', 'label': _t('إكسسوارات'), 'icon': 'handyman'},
    {'id': 'Glass', 'label': _t('زجاج'), 'icon': 'window'},
    {'id': 'Joints', 'label': _t('جوانات'), 'icon': 'linear_scale'},
    {'id': 'ShutterComponents', 'label': _t('ستائر'), 'icon': 'blinds'},
    {'id': 'Sheets', 'label': _t('ألواح'), 'icon': 'view_agenda'},
  ];

  @override
  void initState() {
    super.initState();
    // Show the catalogue immediately. Previously the initial load deliberately
    // returned an empty list until the search field was tapped, which looked
    // like a broken/empty catalogue to the user.
    _loadItems(showAll: true);
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchCtrl.dispose();
    _searchFocus.dispose();
    _quantityCtrl.dispose();
    _priceCtrl.dispose();
    super.dispose();
  }

  String _canonicalStockType(String category) {
    switch (category) {
      case 'Sections':
        return 'Section';
      case 'Accessories':
        return 'Accessory';
      case 'ShutterComponents':
        return 'ShutterComponent';
      default:
        return category;
    }
  }

  String _stockKey(String category, int itemId, int? colorId) =>
      '${_canonicalStockType(category)}_${itemId}_${colorId ?? 0}';

  String _categoryForItem(Map<String, dynamic> item) =>
      item['_picker_category']?.toString() ?? _selectedCategory;

  Future<void> _loadStockQuantities() async {
    if (_stockLoaded) return;
    try {
      final rows = await widget.db.readAllPossibleStock(1);
      for (final row in rows) {
        final type = row['item_type']?.toString() ?? '';
        final id = (row['item_id'] as num?)?.toInt() ?? 0;
        final colorId = (row['color_id'] as num?)?.toInt();
        _stockQuantities['${type}_${id}_${colorId ?? 0}'] =
            (row['quantity'] as num?)?.toDouble() ?? 0.0;
      }
    } catch (error) {
      // Stock availability is supplementary information. A damaged/missing
      // stock row must never hide the product catalogue itself.
      debugPrint('Could not load picker stock quantities: $error');
    } finally {
      _stockLoaded = true;
    }
  }

  double _stockFor(Map<String, dynamic> item, {int? colorId}) {
    final id = (item['id'] as num?)?.toInt() ?? 0;
    final selectedColor =
        colorId ?? (item['_selected_color_id'] as num?)?.toInt();
    return _stockQuantities[_stockKey(
          _categoryForItem(item),
          id,
          selectedColor,
        )] ??
        0.0;
  }

  Future<List<Map<String, dynamic>>> _readCategoryItems(String category) async {
    try {
      final List<Map<String, dynamic>> rows;
      switch (category) {
        case 'Sections':
          rows = await widget.db.searchSectionsWithProfile('');
          break;
        case 'Accessories':
          rows = await widget.db.readAccessories();
          break;
        case 'Glass':
          rows = await widget.db.readGlass();
          break;
        case 'Joints':
          rows = await widget.db.readJoints();
          break;
        case 'ShutterComponents':
          rows = await widget.db.readShutterComponents();
          break;
        case 'Sheets':
          rows = await widget.db.readStandardSheets();
          break;
        default:
          rows = <Map<String, dynamic>>[];
      }
      return rows
          .map((row) => <String, dynamic>{...row, '_picker_category': category})
          .toList();
    } catch (error) {
      // One optional catalogue table may not yet exist on an older database.
      // Keep the remaining categories available instead of blanking the whole
      // picker because Future.wait received one error.
      debugPrint('Could not load picker category $category: $error');
      return <Map<String, dynamic>>[];
    }
  }

  String _normalizeSearch(String value) {
    var normalized = value.toLowerCase();
    const replacements = <String, String>{
      'à': 'a',
      'á': 'a',
      'â': 'a',
      'ä': 'a',
      'ã': 'a',
      'ç': 'c',
      'è': 'e',
      'é': 'e',
      'ê': 'e',
      'ë': 'e',
      'ì': 'i',
      'í': 'i',
      'î': 'i',
      'ï': 'i',
      'ò': 'o',
      'ó': 'o',
      'ô': 'o',
      'ö': 'o',
      'õ': 'o',
      'ù': 'u',
      'ú': 'u',
      'û': 'u',
      'ü': 'u',
      'ÿ': 'y',
      'أ': 'ا',
      'إ': 'ا',
      'آ': 'ا',
      'ى': 'ي',
      'ة': 'ه',
      'ؤ': 'و',
      'ئ': 'ي',
    };
    replacements.forEach((from, to) {
      normalized = normalized.replaceAll(from, to);
    });
    normalized = normalized.replaceAll(RegExp(r'[\u064B-\u065F\u0670]'), '');
    return normalized
        .replaceAll(RegExp(r'[^a-z0-9\u0600-\u06ff]+'), ' ')
        .trim()
        .replaceAll(RegExp(r'\s+'), ' ');
  }

  int _editDistance(String a, String b) {
    if (a == b) return 0;
    if (a.isEmpty) return b.length;
    if (b.isEmpty) return a.length;
    var previous = List<int>.generate(b.length + 1, (i) => i);
    for (var i = 0; i < a.length; i++) {
      final current = <int>[i + 1];
      for (var j = 0; j < b.length; j++) {
        current.add(
          [
            current[j] + 1,
            previous[j + 1] + 1,
            previous[j] + (a.codeUnitAt(i) == b.codeUnitAt(j) ? 0 : 1),
          ].reduce((x, y) => x < y ? x : y),
        );
      }
      previous = current;
    }
    return previous.last;
  }

  bool _smartSearchMatch(Map<String, dynamic> item, String query) {
    final searchable = _normalizeSearch(
      [
        item['name'],
        item['type'],
        item['code'],
        item['profile_name'],
        item['series_name'],
        item['_selected_color_name'],
      ].where((value) => value != null).join(' '),
    );
    final normalizedQuery = _normalizeSearch(query);
    if (normalizedQuery.isEmpty) return true;

    final compactText = searchable.replaceAll(' ', '');
    final compactQuery = normalizedQuery.replaceAll(' ', '');
    if (searchable.contains(normalizedQuery) ||
        compactText.contains(compactQuery)) {
      return true;
    }

    final words = searchable.split(' ').where((word) => word.isNotEmpty);
    return normalizedQuery.split(' ').where((word) => word.isNotEmpty).every((
      queryWord,
    ) {
      return words.any((word) {
        if (word.contains(queryWord) || queryWord.contains(word)) {
          return true;
        }
        final allowedErrors = queryWord.length >= 7
            ? 2
            : queryWord.length >= 4
            ? 1
            : 0;
        return allowedErrors > 0 &&
            (word.length - queryWord.length).abs() <= allowedErrors &&
            _editDistance(word, queryWord) <= allowedErrors;
      });
    });
  }

  Future<void> _loadItems({bool showAll = false}) async {
    setState(() => _loading = true);
    try {
      await _loadStockQuantities();
      final q = _searchCtrl.text.trim();
      List<Map<String, dynamic>> items = [];
      if (_selectedCategory == 'All') {
        final groups = await Future.wait(
          _categories
              .where((category) => category['id'] != 'All')
              .map((category) => _readCategoryItems(category['id']!)),
        );
        items = groups.expand((group) => group).toList();
      } else {
        items = await _readCategoryItems(_selectedCategory);
      }
      if (_selectedCategory == 'Sections' || _selectedCategory == 'All') {
        final profiles =
            items
                .map((item) => item['profile_name']?.toString().trim() ?? '')
                .where((name) => name.isNotEmpty)
                .toSet()
                .toList()
              ..sort();
        _profileNames = profiles;
        if (_selectedProfile.isNotEmpty &&
            !_profileNames.contains(_selectedProfile)) {
          _selectedProfile = '';
        }
        if (_selectedCategory == 'Sections' && _selectedProfile.isNotEmpty) {
          items = items
              .where(
                (item) => item['profile_name']?.toString() == _selectedProfile,
              )
              .toList();
        }

        // A section is sold as a section/colour combination.  Showing one
        // row per available profile colour makes the selected stock variant
        // explicit before the quantity dialog is opened.
        final expanded = <Map<String, dynamic>>[];
        for (final item in items) {
          if (_categoryForItem(item) != 'Sections') {
            expanded.add(item);
            continue;
          }
          final profileId = (item['source_profile_id'] as num?)?.toInt();
          if (profileId == null) {
            expanded.add(item);
            continue;
          }
          final colors = _sectionColorsByProfile[profileId] ??= await widget.db
              .getColorsForProfile(profileId);
          if (colors.isEmpty) {
            expanded.add(item);
            continue;
          }
          for (final color in colors) {
            final variant = Map<String, dynamic>.from(item);
            variant['_selected_color_id'] = (color['id'] as num?)?.toInt();
            variant['_selected_color_name'] = color['name']?.toString() ?? '';
            variant['_selected_color_hex'] =
                color['hex_code']?.toString() ?? '';
            expanded.add(variant);
          }
        }
        items = expanded;
      } else {
        _selectedProfile = '';
        _profileNames = [];
      }
      if (q.isNotEmpty) {
        items = items.where((item) => _smartSearchMatch(item, q)).toList();
      } else if (!showAll) {
        items = [];
      }
      if (mounted) setState(() => _items = items);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<double> _resolvePrice(
    Map<String, dynamic> item, {
    int? colorId,
  }) async {
    final itemId = (item['id'] as num?)?.toInt() ?? 0;
    final latest = await widget.db.getLatestPurchasePrice(
      itemId: itemId,
      itemType: _categoryForItem(item),
      colorId: colorId,
    );
    if (latest != null && latest > 0) return latest;
    if (_categoryForItem(item) == 'Sections' && colorId != null) {
      final catalogue = await widget.db.getSectionColorPrice(itemId, colorId);
      if (catalogue > 0) return catalogue;
    }
    return _getDefaultPrice(item);
  }

  Future<void> _selectItem(Map<String, dynamic> item) async {
    final colorId = (item['_selected_color_id'] as num?)?.toInt();
    final colorName = item['_selected_color_name']?.toString() ?? '';
    final profileId = (item['source_profile_id'] as num?)?.toInt();
    final availableColors = profileId == null
        ? const <Map<String, dynamic>>[]
        : (_sectionColorsByProfile[profileId] ??
              await widget.db.getColorsForProfile(profileId));
    final initialPrice = await _resolvePrice(item, colorId: colorId);
    if (!mounted) return;
    setState(() {
      _selectedItem = item;
      _selectedItemColors = availableColors;
      _selectedColorId = colorId;
      _selectedColorName = colorName;
      _quantityCtrl.text = '1';
      _priceCtrl.text = initialPrice.toStringAsFixed(2);
      // Keep the chosen row and all current results visible. The user can now
      // inspect the complete details, quantity, price, colour and stock before
      // adding it. Starting a new search clears the selection in onChanged.
      _showSearchResults = true;
    });
  }

  void _hideSearchResults() {
    if (!_showSearchResults) return;
    setState(() => _showSearchResults = false);
  }

  void _addSelectedItem() {
    final item = _selectedItem;
    if (item == null) return;
    final qty = double.tryParse(_quantityCtrl.text.replaceAll(',', '.')) ?? 1.0;
    final price = double.tryParse(_priceCtrl.text.replaceAll(',', '.')) ?? 0.0;
    widget.onItemSelected({
      'item_type': _categoryForItem(item),
      'item_id': item['id'] ?? 0,
      'item_code': item['code'] ?? item['name'] ?? '',
      'item_name': item['name'] ?? item['type'] ?? '',
      'system_name':
          item['system_name'] ?? item['profile_name'] ?? item['gamme_name'] ?? '',
      'series_name':
          item['series_name'] ?? item['system_name'] ?? item['gamme_name'] ?? '',
      'color_id': _selectedColorId,
      'color_name': _selectedColorName,
      'unit': _getUnit(item),
      'length_mm': (item['length_mm'] as num?)?.toDouble() ?? 0.0,
      'width_mm': (item['width_mm'] as num?)?.toDouble() ?? 0.0,
      'quantity': qty,
      'unit_price': price,
      'tax_rate': 0.0,
      'available_quantity': _stockFor(item, colorId: _selectedColorId),
      'total_price': qty * price,
      'notes': '',
    });
  }

  Widget _colorSwatch(String? hex) {
    var value = (hex ?? '').replaceFirst('#', '');
    if (value.length == 6) value = 'FF$value';
    final parsed = int.tryParse(value, radix: 16);
    return Container(
      width: 18,
      height: 18,
      decoration: BoxDecoration(
        color: parsed == null ? Colors.grey.shade300 : Color(parsed),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.black26),
      ),
    );
  }

  double _getDefaultPrice(Map<String, dynamic> item) {
    final p =
        item['price'] ??
        item['price_per_sqm'] ??
        item['price_per_sheet'] ??
        0.0;
    return (p as num?)?.toDouble() ?? 0.0;
  }

  String _getUnit([Map<String, dynamic>? item]) {
    switch (item == null ? _selectedCategory : _categoryForItem(item)) {
      case 'Sections':
        return 'barre';
      case 'Accessories':
        return 'pcs';
      case 'Glass':
        return 'm²';
      case 'Joints':
        return 'm';
      case 'ShutterComponents':
        return 'pcs';
      case 'Sheets':
        return 'feuille';
      default:
        return 'pcs';
    }
  }

  TextSpan _highlightedSpan(String text) {
    final query = _searchCtrl.text.trim();
    if (query.isEmpty) return TextSpan(text: text);
    final lowerText = text.toLowerCase();
    final lowerQuery = query.toLowerCase();
    final spans = <TextSpan>[];
    var start = 0;
    while (true) {
      final index = lowerText.indexOf(lowerQuery, start);
      if (index < 0) {
        spans.add(TextSpan(text: text.substring(start)));
        break;
      }
      if (index > start) {
        spans.add(TextSpan(text: text.substring(start, index)));
      }
      spans.add(
        TextSpan(
          text: text.substring(index, index + query.length),
          style: const TextStyle(
            backgroundColor: Color(0xFFFFE082),
            color: Colors.black,
            fontWeight: FontWeight.w800,
          ),
        ),
      );
      start = index + query.length;
    }
    return TextSpan(children: spans);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final isDesktop = MediaQuery.of(context).size.width >= 800;
    final selected = _selectedItem;
    final selectedStock = selected == null
        ? 0.0
        : _stockFor(selected, colorId: _selectedColorId);
    return SizedBox(
      width: 920,
      height: MediaQuery.of(context).size.height * 0.9,
      child: Container(
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          children: [
            Container(
              decoration: BoxDecoration(
                color: isDesktop ? const Color(0xFF111111) : Colors.transparent,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
              ),
              padding: const EdgeInsets.fromLTRB(20, 12, 12, 12),
              child: Row(
                children: [
                  Icon(
                    Icons.inventory_2_outlined,
                    color: isDesktop ? Colors.white : _blue,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _t('اختر منتجاً'),
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: isDesktop ? Colors.white : colors.onSurface,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: Icon(
                      Icons.close,
                      color: isDesktop ? Colors.white : colors.onSurface,
                    ),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final compact = constraints.maxWidth < 600;
                  final categoryField = SizedBox(
                    width: compact ? constraints.maxWidth : 210,
                    child: DropdownButtonFormField<String>(
                      initialValue: _selectedCategory,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: _t('البحث في'),
                        prefixIcon: const Icon(Icons.tune_rounded),
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: _categories
                          .map(
                            (category) => DropdownMenuItem<String>(
                              value: category['id'],
                              child: Text(
                                category['label']!,
                                style: const TextStyle(fontFamily: 'Cairo'),
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value == null) return;
                        setState(() {
                          _selectedCategory = value;
                          _selectedProfile = '';
                          _selectedItem = null;
                          _searchCtrl.clear();
                          _showSearchResults = true;
                        });
                        _loadItems(showAll: true);
                      },
                    ),
                  );
                  final searchField = TextField(
                    focusNode: _searchFocus,
                    controller: _searchCtrl,
                    autofocus: !compact,
                    decoration: InputDecoration(
                      hintText: _t('اكتب الاسم أو الرمز للبحث...'),
                      hintStyle: const TextStyle(fontFamily: 'Cairo'),
                      prefixIcon: const Icon(Icons.search, color: _blue),
                      suffixIcon: _searchCtrl.text.isEmpty
                          ? const Icon(Icons.arrow_drop_down_rounded)
                          : IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                _searchCtrl.clear();
                                setState(() {
                                  _selectedItem = null;
                                  _showSearchResults = true;
                                });
                                _loadItems(showAll: true);
                              },
                            ),
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                    onTap: () {
                      if (!_showSearchResults) {
                        setState(() => _showSearchResults = true);
                        _loadItems(
                          showAll:
                              _selectedItem != null ||
                              _searchCtrl.text.trim().isEmpty,
                        );
                      }
                    },
                    onChanged: (_) {
                      setState(() {
                        _selectedItem = null;
                        _showSearchResults = true;
                      });
                      _searchDebounce?.cancel();
                      _searchDebounce = Timer(
                        const Duration(milliseconds: 180),
                        () => _loadItems(
                          showAll: _searchCtrl.text.trim().isEmpty,
                        ),
                      );
                    },
                  );
                  if (compact) {
                    return Column(
                      children: [
                        categoryField,
                        const SizedBox(height: 10),
                        searchField,
                      ],
                    );
                  }
                  return Row(
                    children: [
                      categoryField,
                      const SizedBox(width: 10),
                      Expanded(child: searchField),
                    ],
                  );
                },
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(color: colors.outlineVariant),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: !_showSearchResults
                      ? Center(
                          child: Text(
                            selected == null
                                ? _t('اضغط على حقل البحث لاختيار منتج')
                                : _t('تم اختيار المنتج'),
                            style: const TextStyle(fontFamily: 'Cairo'),
                          ),
                        )
                      : _loading
                      ? const Center(child: CircularProgressIndicator())
                      : _items.isEmpty
                      ? Center(
                          child: Text(
                            _t('لا توجد نتائج'),
                            style: const TextStyle(fontFamily: 'Cairo'),
                          ),
                        )
                      : ListView.separated(
                          itemCount: _items.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (_, i) {
                            final item = _items[i];
                            final name = item['name'] ?? item['type'] ?? '';
                            final code = item['code'] ?? '';
                            final family =
                                item['profile_name']?.toString() ?? '';
                            final series =
                                item['series_name']?.toString() ?? '';
                            final colorName =
                                item['_selected_color_name']?.toString() ?? '';
                            final colorHex = item['_selected_color_hex']
                                ?.toString();
                            final stock = _stockFor(item);
                            final isSelected =
                                _selectedItem != null &&
                                (item['id'] as num?)?.toInt() ==
                                    (_selectedItem!['id'] as num?)?.toInt() &&
                                _categoryForItem(item) ==
                                    _categoryForItem(_selectedItem!) &&
                                (item['_selected_color_id'] as num?)?.toInt() ==
                                    (_selectedItem!['_selected_color_id'] as num?)
                                        ?.toInt();
                            return ListTile(
                              selected: isSelected,
                              selectedTileColor: _blue.withOpacity(0.08),
                              leading: colorName.isNotEmpty
                                  ? _colorSwatch(colorHex)
                                  : CircleAvatar(
                                      backgroundColor: _blue.withOpacity(0.1),
                                      child: Text(
                                        _categoryForItem(item).substring(0, 1),
                                        style: const TextStyle(
                                          color: _blue,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                              title: RichText(
                                text: TextSpan(
                                  style: TextStyle(
                                    color: colors.onSurface,
                                    fontFamily: 'Cairo',
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  children: [_highlightedSpan(name.toString())],
                                ),
                              ),
                              subtitle: RichText(
                                text: TextSpan(
                                  style: TextStyle(
                                    color: colors.onSurfaceVariant,
                                    fontFamily: 'Cairo',
                                    fontSize: 11,
                                  ),
                                  children: [
                                    _highlightedSpan(
                                      [code, family, series, colorName]
                                          .where(
                                            (value) =>
                                                value.toString().isNotEmpty,
                                          )
                                          .join(' · '),
                                    ),
                                  ],
                                ),
                              ),
                              trailing: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    _t('المتوفر'),
                                    style: TextStyle(
                                      fontFamily: 'Cairo',
                                      fontSize: 9,
                                      color: colors.onSurfaceVariant,
                                    ),
                                  ),
                                  Text(
                                    NumberFormat('#,##0.##').format(stock),
                                    style: TextStyle(
                                      fontFamily: 'Cairo',
                                      fontWeight: FontWeight.bold,
                                      color: stock > 0
                                          ? Colors.green
                                          : Colors.red,
                                    ),
                                  ),
                                ],
                              ),
                              onTap: () => _selectItem(item),
                            );
                          },
                        ),
                ),
              ),
            ),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: selected == null
                  ? const SizedBox(height: 14)
                  : Container(
                      key: ValueKey('${selected['id']}_$_selectedColorId'),
                      margin: const EdgeInsets.fromLTRB(20, 10, 20, 16),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: colors.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: colors.outlineVariant),
                      ),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  selected['name'] ?? selected['type'] ?? '',
                                  style: const TextStyle(
                                    fontFamily: 'Cairo',
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              Text(
                                '${_t('المتوفر')}: ${NumberFormat('#,##0.##').format(selectedStock)} ${_t(_getUnit(selected))}',
                                style: TextStyle(
                                  fontFamily: 'Cairo',
                                  color: selectedStock > 0
                                      ? Colors.green
                                      : Colors.red,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Align(
                            alignment: AlignmentDirectional.centerStart,
                            child: Text(
                              [
                                selected['code'],
                                selected['profile_name'] ??
                                    selected['system_name'],
                                selected['series_name'],
                                _selectedColorName,
                                _t(_getUnit(selected)),
                              ]
                                  .where(
                                    (value) =>
                                        value != null &&
                                        value.toString().trim().isNotEmpty,
                                  )
                                  .join(' · '),
                              style: TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 11,
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          LayoutBuilder(
                            builder: (context, constraints) {
                              final compact = constraints.maxWidth < 620;
                              final halfWidth = (constraints.maxWidth - 10) / 2;
                              return Wrap(
                                spacing: 10,
                                runSpacing: 10,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  if (_selectedItemColors.isNotEmpty) ...[
                                    SizedBox(
                                      width: compact
                                          ? constraints.maxWidth
                                          : 260,
                                      child: DropdownButtonFormField<int>(
                                        initialValue: _selectedColorId,
                                        isExpanded: true,
                                        decoration: InputDecoration(
                                          labelText: _t('اللون'),
                                          border: const OutlineInputBorder(),
                                          isDense: true,
                                        ),
                                        items: _selectedItemColors.map((color) {
                                          final id = (color['id'] as num)
                                              .toInt();
                                          return DropdownMenuItem<int>(
                                            value: id,
                                            child: Row(
                                              children: [
                                                _colorSwatch(
                                                  color['hex_code']?.toString(),
                                                ),
                                                const SizedBox(width: 6),
                                                Flexible(
                                                  child: Text(
                                                    color['name']?.toString() ??
                                                        '',
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          );
                                        }).toList(),
                                        onChanged: (value) async {
                                          _hideSearchResults();
                                          if (value == null) return;
                                          final color = _selectedItemColors
                                              .firstWhere(
                                                (entry) =>
                                                    (entry['id'] as num)
                                                        .toInt() ==
                                                    value,
                                              );
                                          final price = await _resolvePrice(
                                            selected,
                                            colorId: value,
                                          );
                                          if (!mounted) return;
                                          setState(() {
                                            _selectedColorId = value;
                                            _selectedColorName =
                                                color['name']?.toString() ?? '';
                                            _priceCtrl.text = price
                                                .toStringAsFixed(2);
                                          });
                                        },
                                      ),
                                    ),
                                  ],
                                  SizedBox(
                                    width: compact ? halfWidth : 150,
                                    child: TextField(
                                      controller: _quantityCtrl,
                                      onTap: _hideSearchResults,
                                      keyboardType:
                                          const TextInputType.numberWithOptions(
                                            decimal: true,
                                          ),
                                      inputFormatters: const [
                                        DecimalTextInputFormatter(
                                          decimalDigits: 3,
                                        ),
                                      ],
                                      decoration: InputDecoration(
                                        labelText: _t('الكمية'),
                                        border: const OutlineInputBorder(),
                                        isDense: true,
                                      ),
                                    ),
                                  ),
                                  SizedBox(
                                    width: compact ? halfWidth : 170,
                                    child: TextField(
                                      controller: _priceCtrl,
                                      onTap: _hideSearchResults,
                                      keyboardType:
                                          const TextInputType.numberWithOptions(
                                            decimal: true,
                                          ),
                                      inputFormatters: const [
                                        DecimalTextInputFormatter(),
                                      ],
                                      decoration: InputDecoration(
                                        labelText: _t('سعر الوحدة'),
                                        suffixText: _t('د.ج'),
                                        border: const OutlineInputBorder(),
                                        isDense: true,
                                      ),
                                    ),
                                  ),
                                  FilledButton.icon(
                                    onPressed: _addSelectedItem,
                                    icon: const Icon(
                                      Icons.add_shopping_cart_rounded,
                                    ),
                                    label: Text(
                                      _t('إضافة'),
                                      style: const TextStyle(
                                        fontFamily: 'Cairo',
                                      ),
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
