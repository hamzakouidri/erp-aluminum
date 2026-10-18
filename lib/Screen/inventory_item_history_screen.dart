import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:provider/provider.dart';

import '../Commande/order_measurements_details_screen.dart';
import '../services/product_movement_export_service.dart';
import '../settings/app_settings.dart';
import '../settings/localization.dart';
import '../sql_database.dart';
import 'achat_details_screen.dart';
import 'client_ledger_screen.dart';
import 'material_sale_editor_screen.dart';
import 'supplier_details_screen.dart';

/// بطاقة حركة المنتج: every movement of one item (and colour) in the store
/// and the workshop, with its source, destination, document and party.
class InventoryItemHistoryScreen extends StatefulWidget {
  final SqlDatabase db;
  final int itemId;
  final String itemType;
  final String itemName;
  final int? colorId;
  final String colorName;

  /// The warehouse the card was opened from. The card covers every
  /// warehouse; this one is only highlighted in the balances.
  final int locationId;
  final String locationName;

  const InventoryItemHistoryScreen({
    super.key,
    required this.db,
    required this.itemId,
    required this.itemType,
    required this.itemName,
    this.colorId,
    required this.colorName,
    required this.locationId,
    required this.locationName,
  });

  @override
  State<InventoryItemHistoryScreen> createState() =>
      _InventoryItemHistoryScreenState();
}

class _InventoryItemHistoryScreenState
    extends State<InventoryItemHistoryScreen> {
  static const _blue = Color(0xFF2563EB);
  static const _bg = Color(0xFFF8FAFC);
  static const _cardBg = Colors.white;
  static const _text = Color(0xFF1E293B);
  static const _textDim = Color(0xFF64748B);
  static const _divider = Color(0xFFE2E8F0);
  static const _green = Color(0xFF10B981);
  static const _red = Color(0xFFEF4444);
  static const _amber = Color(0xFFF59E0B);

  static const _movementLabels = {
    SqlDatabase.movementPurchaseReceipt: 'شراء',
    SqlDatabase.movementSaleIssue: 'بيع مواد',
    SqlDatabase.movementInternalTransfer: 'تحويل داخلي',
    SqlDatabase.movementProductionIssue: 'صرف للتصنيع',
    SqlDatabase.movementReturn: 'مرتجع أو إلغاء',
    SqlDatabase.movementAdjustment: 'تسوية جرد',
    SqlDatabase.movementRemnant: 'صرف فضلة',
    SqlDatabase.movementDamage: 'تالف أو خطأ قص',
  };

  static const _documentLabels = {
    'purchase': 'شراء',
    'sale': 'بيع',
    'order': 'طلبية',
  };

  late Future<Map<String, dynamic>> _cardFuture;
  final _horizontal = ScrollController();

  DateTimeRange? _range;
  int? _locationFilter;
  String? _movementFilter;
  int? _supplierFilter;
  int? _clientFilter;
  int? _orderFilter;
  String? _performerFilter;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _horizontal.dispose();
    super.dispose();
  }

  void _load() {
    _cardFuture = widget.db.readProductMovementCard(
      itemId: widget.itemId,
      itemType: widget.itemType,
      colorId: widget.colorId,
    );
  }

  AppLanguage get _lang =>
      Provider.of<AppSettingsProvider>(context, listen: false).language;

  String _t(String key) => Localization.translate(key, _lang);

  String _qty(num value) {
    final v = value.toDouble();
    return v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(2);
  }

  String _money(num? value) =>
      value == null ? '—' : NumberFormat('#,##0.00').format(value);

  String _date(Object? value) {
    final parsed = DateTime.tryParse(value?.toString() ?? '');
    if (parsed == null) return value?.toString() ?? '';
    return DateFormat('yyyy-MM-dd HH:mm').format(parsed.toLocal());
  }

  // ── Row texts ─────────────────────────────────────────────────────────

  String _movementLabel(Map<String, dynamic> row) =>
      _t(_movementLabels[row['movement_type']] ?? 'حركة');

  String _from(Map<String, dynamic> row) {
    final name = row['from_location_name']?.toString();
    if (name != null && name.isNotEmpty) return name;
    return switch (row['movement_type']) {
      SqlDatabase.movementPurchaseReceipt => _t('المورد'),
      SqlDatabase.movementReturn when row['doc_type'] == 'sale' => _t('الزبون'),
      _ => '—',
    };
  }

  String _to(Map<String, dynamic> row) {
    final name = row['to_location_name']?.toString();
    if (name != null && name.isNotEmpty) return name;
    return switch (row['movement_type']) {
      SqlDatabase.movementSaleIssue => _t('الزبون'),
      SqlDatabase.movementProductionIssue ||
      SqlDatabase.movementRemnant => _t('الطلبية / أمر التشغيل'),
      SqlDatabase.movementDamage => _t('هالك'),
      SqlDatabase.movementReturn when row['doc_type'] == 'purchase' => _t(
        'المورد',
      ),
      _ => '—',
    };
  }

  String _quantityText(Map<String, dynamic> row) {
    if (row['is_transfer'] == true && (row['legs'] as List).length == 2) {
      final q = _qty(row['transfer_quantity'] as double);
      return '-$q / +$q';
    }
    final q = row['quantity'] as double;
    final unit = row['movement_type'] == SqlDatabase.movementRemnant
        ? ' ${_t('م')}'
        : '';
    return '${q > 0 ? '+' : ''}${_qty(q)}$unit';
  }

  Color _quantityColor(Map<String, dynamic> row) {
    if (row['is_transfer'] == true && (row['legs'] as List).length == 2) {
      return _blue;
    }
    return (row['quantity'] as double) >= 0 ? _green : _red;
  }

  String _party(Map<String, dynamic> row) {
    final supplier = row['supplier_name']?.toString() ?? '';
    if (supplier.isNotEmpty) return supplier;
    final client = row['client_name']?.toString() ?? '';
    if (client.isNotEmpty) return client;
    if (row['is_transfer'] == true) return _t('الورشة');
    return '—';
  }

  String _document(Map<String, dynamic> row) {
    if (row['is_transfer'] == true) {
      final code = row['out_document_code'] ?? row['doc_code'];
      return '${_t('تحويل')} ${code ?? ''}'.trim();
    }
    final type = row['doc_type']?.toString();
    final code = row['doc_code']?.toString() ?? '';
    if (type == null && code.isEmpty) return '—';
    return '${_t(_documentLabels[type] ?? '')} $code'.trim();
  }

  String _order(Map<String, dynamic> row) {
    final code = row['order_code'] ?? row['resolved_order_id'];
    return code == null ? '—' : '$code';
  }

  String _performer(Map<String, dynamic> row) {
    final name = row['performed_by']?.toString() ?? '';
    return name.isEmpty ? '—' : name;
  }

  // ── Filtering ─────────────────────────────────────────────────────────

  bool _matches(Map<String, dynamic> row) {
    if (_range != null) {
      final at = DateTime.tryParse(row['moved_at']?.toString() ?? '');
      if (at == null) return false;
      final local = at.toLocal();
      final end = _range!.end.add(const Duration(days: 1));
      if (local.isBefore(_range!.start) || !local.isBefore(end)) return false;
    }
    if (_locationFilter != null &&
        row['from_location_id'] != _locationFilter &&
        row['to_location_id'] != _locationFilter) {
      return false;
    }
    if (_movementFilter != null && row['movement_type'] != _movementFilter) {
      return false;
    }
    if (_supplierFilter != null &&
        row['party_supplier_id'] != _supplierFilter) {
      return false;
    }
    if (_clientFilter != null && row['party_client_id'] != _clientFilter) {
      return false;
    }
    if (_orderFilter != null && row['resolved_order_id'] != _orderFilter) {
      return false;
    }
    if (_performerFilter != null && _performer(row) != _performerFilter) {
      return false;
    }
    return true;
  }

  bool get _hasFilters =>
      _range != null ||
      _locationFilter != null ||
      _movementFilter != null ||
      _supplierFilter != null ||
      _clientFilter != null ||
      _orderFilter != null ||
      _performerFilter != null;

  void _clearFilters() => setState(() {
    _range = null;
    _locationFilter = null;
    _movementFilter = null;
    _supplierFilter = null;
    _clientFilter = null;
    _orderFilter = null;
    _performerFilter = null;
  });

  // ── Navigation ────────────────────────────────────────────────────────

  Future<void> _openDocument(String? type, Object? rawId) async {
    final id = (rawId as num?)?.toInt();
    if (type == null || id == null || id <= 0) return;
    Widget? page;
    switch (type) {
      case 'purchase':
        final achat = await widget.db.readAchatById(id);
        if (achat == null) break;
        page = AchatDetailsScreen(
          db: widget.db,
          achatId: id,
          invoiceNumber: achat['invoice_number']?.toString() ?? '',
          supplierName: achat['supplier_name']?.toString() ?? '',
        );
      case 'sale':
        page = MaterialSaleEditorScreen(db: widget.db, saleId: id);
      case 'order':
        final order = await widget.db.readCommandeWithClientById(id);
        if (order == null) break;
        page = OrderMeasurementsDetailsScreen(orderData: order, db: widget.db);
    }
    if (!mounted) return;
    if (page == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_t('الوثيقة الأصلية غير موجودة.'))),
      );
      return;
    }
    await Navigator.push(context, MaterialPageRoute(builder: (_) => page!));
  }

  Future<void> _openRow(Map<String, dynamic> row) async {
    if (row['is_transfer'] == true && (row['legs'] as List).length == 2) {
      final choice = await showModalBottomSheet<String>(
        context: context,
        builder: (sheetContext) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.call_made_rounded, color: _red),
                title: Text(
                  '${_t('وثيقة الخروج')}: ${row['out_document_code'] ?? '—'}',
                ),
                onTap: () => Navigator.pop(sheetContext, 'out'),
              ),
              ListTile(
                leading: const Icon(Icons.call_received_rounded, color: _green),
                title: Text(
                  '${_t('وثيقة الدخول')}: ${row['in_document_code'] ?? '—'}',
                ),
                onTap: () => Navigator.pop(sheetContext, 'in'),
              ),
            ],
          ),
        ),
      );
      if (choice == null) return;
      await _openDocument(
        row['${choice}_document_type']?.toString(),
        row['${choice}_document_id'],
      );
      return;
    }
    final orderId = row['resolved_order_id'];
    await _openDocument(
      row['doc_type']?.toString() ?? (orderId == null ? null : 'order'),
      row['doc_id'] ?? orderId,
    );
  }

  Future<void> _openParty(Map<String, dynamic> row) async {
    final supplierId = (row['party_supplier_id'] as num?)?.toInt();
    if (supplierId != null) {
      final suppliers = await widget.db.readSuppliers();
      final supplier = suppliers
          .where((s) => (s['id'] as num?)?.toInt() == supplierId)
          .firstOrNull;
      if (supplier == null || !mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => SupplierDetailsScreen(supplier: supplier),
        ),
      );
      return;
    }
    final clientId = (row['party_client_id'] as num?)?.toInt();
    if (clientId == null || !mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ClientLedgerScreen(clientId: clientId)),
    );
  }

  // ── Export ────────────────────────────────────────────────────────────

  List<String> get _headers => [
    _t('التاريخ'),
    _t('الحركة'),
    _t('من'),
    _t('إلى'),
    _t('الكمية'),
    _t('الطرف'),
    _t('الوثيقة'),
    _t('الطلبية'),
    _t('المنفذ'),
    _t('الرصيد'),
  ];

  List<String> _cells(Map<String, dynamic> row) => [
    _date(row['moved_at']),
    _movementLabel(row),
    _from(row),
    _to(row),
    _quantityText(row),
    _party(row),
    _document(row),
    _order(row),
    _performer(row),
    _qty(row['running_balance'] as double),
  ];

  String get _fileStem {
    final safe = widget.itemName.replaceAll(RegExp(r'[\\/:*?"<>|\s]+'), '_');
    return '${_t('حركة')}_${safe}_${DateFormat('yyyyMMdd').format(DateTime.now())}';
  }

  Future<void> _export(
    List<Map<String, dynamic>> rows,
    Map<String, dynamic> card,
    bool pdf,
  ) async {
    try {
      final data = rows.map(_cells).toList();
      if (pdf) {
        final bytes = await ProductMovementExportService.buildPdf(
          title: '${_t('بطاقة حركة المنتج')}: ${widget.itemName}',
          summary: _summaryLines(card),
          headers: _headers,
          rows: data,
          rtl: _lang == AppLanguage.arabic,
        );
        await ProductMovementExportService.printPdf(bytes, '$_fileStem.pdf');
        return;
      }
      final bytes = ProductMovementExportService.buildCsv(_headers, data);
      final path = await ProductMovementExportService.save(
        bytes,
        '$_fileStem.csv',
        'csv',
      );
      if (path == null || !mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('${_t('تم حفظ الملف')}: $path')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${_t('تعذر التصدير')}: $error'),
          backgroundColor: _red,
        ),
      );
    }
  }

  List<String> _summaryLines(Map<String, dynamic> card) {
    final total = card['total_quantity'] as double? ?? 0;
    final reserved = card['reserved_quantity'] as double? ?? 0;
    final balances = (card['balances'] as List? ?? const [])
        .cast<Map<String, dynamic>>();
    return [
      if (widget.colorName.isNotEmpty)
        '${_t('اللون')}: ${Localization.translate(widget.colorName, _lang)}',
      '${_t('الرصيد الكلي')}: ${_qty(total)} · ${_t('المتاح')}: ${_qty(total - reserved)} · ${_t('المحجوز')}: ${_qty(reserved)}',
      for (final row in balances)
        '${row['location_name'] ?? row['location_id']}: ${_qty(row['quantity'] as double)}',
    ];
  }

  // ── Build ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<AppSettingsProvider>(context);
    final lang = settings.language;
    return Directionality(
      textDirection: lang == AppLanguage.arabic
          ? TextDirection.rtl
          : TextDirection.ltr,
      child: FutureBuilder<Map<String, dynamic>>(
        future: _cardFuture,
        builder: (context, snapshot) {
          final card = snapshot.data ?? const <String, dynamic>{};
          final movements = (card['movements'] as List? ?? const [])
              .cast<Map<String, dynamic>>();
          final filtered = movements.where(_matches).toList();
          return Scaffold(
            backgroundColor: _bg,
            appBar: AppBar(
              backgroundColor: Colors.white,
              elevation: 0,
              surfaceTintColor: Colors.transparent,
              iconTheme: const IconThemeData(color: _text),
              title: Text(
                _t('بطاقة حركة المنتج'),
                style: const TextStyle(
                  fontFamily: 'Cairo',
                  fontWeight: FontWeight.bold,
                  color: _text,
                  fontSize: 18,
                ),
              ),
              actions: [
                IconButton(
                  tooltip: _t('تصدير Excel'),
                  icon: const Icon(Icons.table_view_rounded, color: _green),
                  onPressed: filtered.isEmpty
                      ? null
                      : () => _export(filtered.reversed.toList(), card, false),
                ),
                IconButton(
                  tooltip: _t('تصدير PDF'),
                  icon: const Icon(Icons.picture_as_pdf_rounded, color: _red),
                  onPressed: filtered.isEmpty
                      ? null
                      : () => _export(filtered.reversed.toList(), card, true),
                ),
                IconButton(
                  tooltip: _t('تحديث'),
                  icon: const Icon(Icons.refresh_rounded),
                  onPressed: () => setState(_load),
                ),
              ],
              bottom: PreferredSize(
                preferredSize: const Size.fromHeight(1.0),
                child: Container(color: _divider, height: 1.0),
              ),
            ),
            body: switch (snapshot.connectionState) {
              ConnectionState.waiting => const Center(
                child: CircularProgressIndicator(),
              ),
              _ when snapshot.hasError => Center(
                child: Text(
                  '${_t('خطأ')}: ${snapshot.error}',
                  style: const TextStyle(fontFamily: 'Cairo', color: _red),
                ),
              ),
              _ => CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(
                    child: _buildSummary(card, settings.canViewCostPrice()),
                  ),
                  SliverToBoxAdapter(child: _buildFilters(movements)),
                  if (filtered.isEmpty)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: Center(
                        child: Text(
                          _t(
                            movements.isEmpty
                                ? 'لا توجد حركات مسجلة لهذه المادة.'
                                : 'لا توجد حركات تطابق المرشحات.',
                          ),
                          style: const TextStyle(
                            fontFamily: 'Cairo',
                            color: _textDim,
                          ),
                        ),
                      ),
                    )
                  else
                    SliverToBoxAdapter(
                      // Newest first; the running balance is chronological.
                      child: _buildTable(filtered.reversed.toList()),
                    ),
                ],
              ),
            },
          );
        },
      ),
    );
  }

  Widget _panel({required Widget child}) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
    decoration: BoxDecoration(
      color: _cardBg,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: _divider),
    ),
    child: child,
  );

  Widget _stat(String label, String value, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontFamily: 'Cairo',
            fontSize: 12,
            color: _textDim,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontFamily: 'Cairo',
            fontSize: 17,
            fontWeight: FontWeight.w800,
            color: color,
          ),
        ),
      ],
    ),
  );

  Widget _buildSummary(Map<String, dynamic> card, bool canViewCost) {
    final total = card['total_quantity'] as double? ?? 0;
    final reserved = card['reserved_quantity'] as double? ?? 0;
    final balances = (card['balances'] as List? ?? const [])
        .cast<Map<String, dynamic>>();
    final lastPurchase = card['last_purchase'] as Map<String, dynamic>?;
    final lastCost = lastPurchase == null
        ? null
        : (lastPurchase['unit_cost'] as num?);
    return _panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.itemName,
            style: const TextStyle(
              fontFamily: 'Cairo',
              fontWeight: FontWeight.w900,
              fontSize: 18,
              color: _text,
            ),
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 16,
            children: [
              Text(
                Localization.translate(widget.itemType, _lang),
                style: const TextStyle(fontFamily: 'Cairo', color: _textDim),
              ),
              if (widget.colorName.isNotEmpty)
                Text(
                  Localization.translate(widget.colorName, _lang),
                  style: const TextStyle(fontFamily: 'Cairo', color: _textDim),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _stat(_t('الرصيد الكلي'), _qty(total), _blue),
              _stat(_t('المتاح'), _qty(total - reserved), _green),
              _stat(_t('المحجوز لطلبيات'), _qty(reserved), _amber),
            ],
          ),
          if (balances.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              _t('الرصيد في كل مستودع'),
              style: const TextStyle(
                fontFamily: 'Cairo',
                fontWeight: FontWeight.bold,
                color: _text,
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final row in balances)
                  Chip(
                    backgroundColor: row['location_id'] == widget.locationId
                        ? _blue.withValues(alpha: 0.12)
                        : _bg,
                    side: const BorderSide(color: _divider),
                    label: Text(
                      '${row['location_name'] ?? row['location_id']}: '
                      '${_qty(row['quantity'] as double)}'
                      '${(row['reserved_quantity'] as double) > 0 ? ' (${_t('محجوز')} ${_qty(row['reserved_quantity'] as double)})' : ''}',
                      style: const TextStyle(fontFamily: 'Cairo', fontSize: 13),
                    ),
                  ),
              ],
            ),
          ],
          if (lastPurchase != null) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 18,
              runSpacing: 6,
              children: [
                Text(
                  '${_t('آخر مورد')}: ${lastPurchase['supplier_name'] ?? '—'}',
                  style: const TextStyle(fontFamily: 'Cairo', color: _text),
                ),
                Text(
                  '${_t('آخر شراء')}: ${_date(lastPurchase['moved_at'])} · ${lastPurchase['doc_code'] ?? ''}',
                  style: const TextStyle(fontFamily: 'Cairo', color: _text),
                ),
                if (canViewCost) ...[
                  Text(
                    '${_t('آخر تكلفة شراء')}: ${_money(lastCost)}',
                    style: const TextStyle(fontFamily: 'Cairo', color: _text),
                  ),
                  Text(
                    '${_t('متوسط التكلفة')}: ${_money(card['average_cost'] as num?)}',
                    style: const TextStyle(fontFamily: 'Cairo', color: _text),
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _filterDropdown<T>({
    required String label,
    required T? value,
    required Map<T, String> options,
    required ValueChanged<T?> onChanged,
  }) {
    if (options.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      width: 190,
      child: DropdownButtonFormField<T?>(
        initialValue: options.containsKey(value) ? value : null,
        isExpanded: true,
        isDense: true,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 10,
            vertical: 8,
          ),
        ),
        items: [
          DropdownMenuItem<T?>(value: null, child: Text(_t('الكل'))),
          for (final entry in options.entries)
            DropdownMenuItem<T?>(
              value: entry.key,
              child: Text(entry.value, overflow: TextOverflow.ellipsis),
            ),
        ],
        onChanged: (selected) => setState(() => onChanged(selected)),
      ),
    );
  }

  Widget _buildFilters(List<Map<String, dynamic>> movements) {
    final locations = <int, String>{};
    final types = <String, String>{};
    final suppliers = <int, String>{};
    final clients = <int, String>{};
    final orders = <int, String>{};
    final performers = <String, String>{};
    for (final row in movements) {
      for (final side in const ['from', 'to']) {
        final id = (row['${side}_location_id'] as num?)?.toInt();
        final name = row['${side}_location_name']?.toString();
        if (id != null && name != null) locations[id] = name;
      }
      types[row['movement_type'] as String] = _movementLabel(row);
      final supplierId = (row['party_supplier_id'] as num?)?.toInt();
      if (supplierId != null) {
        suppliers[supplierId] =
            row['supplier_name']?.toString() ?? '$supplierId';
      }
      final clientId = (row['party_client_id'] as num?)?.toInt();
      if (clientId != null) {
        clients[clientId] = row['client_name']?.toString() ?? '$clientId';
      }
      final orderId = (row['resolved_order_id'] as num?)?.toInt();
      if (orderId != null) orders[orderId] = _order(row);
      final performer = _performer(row);
      if (performer != '—') performers[performer] = performer;
    }
    return _panel(
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          OutlinedButton.icon(
            icon: const Icon(Icons.date_range_rounded, size: 18),
            label: Text(
              _range == null
                  ? _t('الفترة الزمنية')
                  : '${DateFormat('yyyy-MM-dd').format(_range!.start)} → '
                        '${DateFormat('yyyy-MM-dd').format(_range!.end)}',
            ),
            onPressed: () async {
              final now = DateTime.now();
              final picked = await showDateRangePicker(
                context: context,
                firstDate: DateTime(2000),
                lastDate: DateTime(now.year + 1),
                initialDateRange: _range,
              );
              if (picked != null) setState(() => _range = picked);
            },
          ),
          _filterDropdown<int>(
            label: _t('المستودع (مصدر أو وجهة)'),
            value: _locationFilter,
            options: locations,
            onChanged: (v) => _locationFilter = v,
          ),
          _filterDropdown<String>(
            label: _t('نوع الحركة'),
            value: _movementFilter,
            options: types,
            onChanged: (v) => _movementFilter = v,
          ),
          _filterDropdown<int>(
            label: _t('المورد'),
            value: _supplierFilter,
            options: suppliers,
            onChanged: (v) => _supplierFilter = v,
          ),
          _filterDropdown<int>(
            label: _t('الزبون'),
            value: _clientFilter,
            options: clients,
            onChanged: (v) => _clientFilter = v,
          ),
          _filterDropdown<int>(
            label: _t('الطلبية'),
            value: _orderFilter,
            options: orders,
            onChanged: (v) => _orderFilter = v,
          ),
          _filterDropdown<String>(
            label: _t('المنفذ'),
            value: _performerFilter,
            options: performers,
            onChanged: (v) => _performerFilter = v,
          ),
          if (_hasFilters)
            TextButton.icon(
              icon: const Icon(Icons.filter_alt_off_rounded, size: 18),
              label: Text(_t('مسح المرشحات')),
              onPressed: _clearFilters,
            ),
        ],
      ),
    );
  }

  static const _columnWidths = <double>[
    130,
    120,
    140,
    140,
    100,
    170,
    140,
    100,
    110,
    90,
  ];

  Widget _cell(
    String text,
    int column, {
    Color color = _text,
    FontWeight weight = FontWeight.normal,
    VoidCallback? onTap,
  }) {
    final content = Text(
      text,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontFamily: 'Cairo',
        fontSize: 13,
        color: onTap == null ? color : _blue,
        fontWeight: weight,
        decoration: onTap == null ? null : TextDecoration.underline,
      ),
    );
    return SizedBox(
      width: _columnWidths[column],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: onTap == null ? content : InkWell(onTap: onTap, child: content),
      ),
    );
  }

  Widget _buildTable(List<Map<String, dynamic>> rows) {
    final width = _columnWidths.fold<double>(0, (sum, w) => sum + w);
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _divider),
      ),
      clipBehavior: Clip.antiAlias,
      // Desktop: the wheel scrolls the page, dragging with the mouse or the
      // scrollbar moves the table sideways.
      child: ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(
          dragDevices: {
            PointerDeviceKind.touch,
            PointerDeviceKind.mouse,
            PointerDeviceKind.trackpad,
            PointerDeviceKind.stylus,
          },
        ),
        child: Scrollbar(
          controller: _horizontal,
          thumbVisibility: true,
          child: SingleChildScrollView(
            controller: _horizontal,
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: width,
              child: Column(
                children: [
                  Container(
                    color: _bg,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Row(
                      children: [
                        for (var i = 0; i < _headers.length; i++)
                          _cell(_headers[i], i, weight: FontWeight.bold),
                      ],
                    ),
                  ),
                  for (final row in rows) ...[
                    const Divider(height: 1, color: _divider),
                    InkWell(
                      onTap: () => _openRow(row),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: Row(
                          children: [
                            _cell(_date(row['moved_at']), 0),
                            _cell(
                              _movementLabel(row),
                              1,
                              weight: FontWeight.w600,
                            ),
                            _cell(_from(row), 2),
                            _cell(_to(row), 3),
                            _cell(
                              _quantityText(row),
                              4,
                              color: _quantityColor(row),
                              weight: FontWeight.w800,
                            ),
                            _cell(
                              _party(row),
                              5,
                              onTap:
                                  row['party_supplier_id'] != null ||
                                      row['party_client_id'] != null
                                  ? () => _openParty(row)
                                  : null,
                            ),
                            _cell(_document(row), 6),
                            _cell(_order(row), 7),
                            _cell(_performer(row), 8, color: _textDim),
                            _cell(
                              _qty(row['running_balance'] as double),
                              9,
                              weight: FontWeight.w700,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
