import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;
import '../sql_database.dart';
import '../services/cloud_sync_service.dart';
import 'material_sale_editor_screen.dart';
import '../services/material_sale_pdf_service.dart';

class MaterialSalesScreen extends StatefulWidget {
  final SqlDatabase db;
  const MaterialSalesScreen({super.key, required this.db});

  @override
  State<MaterialSalesScreen> createState() => _MaterialSalesScreenState();
}

class _MaterialSalesScreenState extends State<MaterialSalesScreen>
    with SingleTickerProviderStateMixin {
  // ─── Colors ───────────────────────────────────────────────────────────────
  static const _blue   = Color(0xFF1E3A8A);
  static const _cyan   = Color(0xFF06B6D4);
  static const _green  = Color(0xFF10B981);
  static const _red    = Color(0xFFEF4444);
  static const _orange = Color(0xFFF59E0B);

  // ─── Filter options ───────────────────────────────────────────────────────
  static const _filterLabels = [
    'الكل', 'وصل تسليم', 'فاتورة', 'طلب بيع', 'وصل شحن', 'عرض سعر'
  ];
  static const _filterValues = [
    '', 'bon_livraison', 'facture', 'bon_commande', 'bon_route', 'devis'
  ];

  // ─── State ────────────────────────────────────────────────────────────────
  SqlDatabase get _db => widget.db;
  String _selectedDocType = '';
  String _searchQuery = '';
  bool _showSearch = false;
  final TextEditingController _searchCtrl = TextEditingController();

  List<Map<String, dynamic>> _sales = [];
  bool _loading = true;
  String? _error;

  StreamSubscription<String>? _syncSub;

  // ─── Formatters ───────────────────────────────────────────────────────────
  final _amountFmt = NumberFormat('#,##0.00');
  final _dateFmt   = DateFormat('dd/MM/yyyy');

  // ─── Lifecycle ────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _loadSales();

    // Subscribe to cloud sync events and refresh on data changes
    _syncSub = CloudSyncService().dbUpdateStream.listen((_) {
      if (mounted) _refresh();
    });
  }

  @override
  void dispose() {
    _syncSub?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  // ─── Data helpers ─────────────────────────────────────────────────────────
  Future<void> _loadSales() async {
    if (!mounted) return;
    setState(() { _loading = true; _error = null; });
    try {
      final data = await _db.readMaterialSales(
        docType: _selectedDocType.isEmpty ? null : _selectedDocType,
        searchQuery: _searchQuery.isEmpty ? null : _searchQuery,
      );
      if (mounted) setState(() { _sales = data; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  void _refresh() => _loadSales();

  // ─── Stats ────────────────────────────────────────────────────────────────
  double _sumField(String field) =>
      _sales.fold(0.0, (s, r) => s + ((r[field] as num?) ?? 0).toDouble());

  // ─── Actions ─────────────────────────────────────────────────────────────
  Future<void> _createNew() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MaterialSaleEditorScreen(db: _db),
      ),
    );
    _refresh();
  }

  Future<void> _openEditor(Map<String, dynamic> sale) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MaterialSaleEditorScreen(db: _db, saleId: sale['id']),
      ),
    );
    _refresh();
  }

  Future<void> _printPdf(Map<String, dynamic> sale) async {
    try {
      final items = await _db.readMaterialSaleItems(sale['id']);
      final bytes = await MaterialSalePdfService.generate(
        sale: sale,
        items: items,
      );
      await MaterialSalePdfService.printOrShare(bytes, sale['sale_code'] as String);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('خطأ في الطباعة: $e',
              style: const TextStyle(fontFamily: 'Cairo')),
          backgroundColor: _red,
        ),
      );
    }
  }

  Future<void> _confirmDelete(Map<String, dynamic> sale) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تأكيد الحذف',
            style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
        content: Text(
          'هل أنت متأكد من حذف الوثيقة ${sale['sale_code']}؟',
          style: const TextStyle(fontFamily: 'Cairo'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء',
                style: TextStyle(fontFamily: 'Cairo', color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: _red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('حذف',
                style: TextStyle(fontFamily: 'Cairo', color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await _db.deleteMaterialSale(sale['id']);
        _refresh();
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ في الحذف: $e',
                style: const TextStyle(fontFamily: 'Cairo')),
            backgroundColor: _red,
          ),
        );
      }
    }
  }

  // ─── Label/color helpers ──────────────────────────────────────────────────
  String _docTypeLabel(String? type) {
    switch (type) {
      case 'bon_livraison': return 'وصل تسليم';
      case 'facture':       return 'فاتورة';
      case 'bon_commande':  return 'طلب بيع';
      case 'bon_route':     return 'وصل شحن';
      case 'devis':         return 'عرض سعر';
      default:              return type ?? '—';
    }
  }

  Color _docTypeColor(String? type) {
    switch (type) {
      case 'bon_livraison': return _cyan;
      case 'facture':       return _blue;
      case 'bon_commande':  return _orange;
      case 'bon_route':     return const Color(0xFF7C3AED);
      case 'devis':         return Colors.teal;
      default:              return Colors.grey;
    }
  }

  String _statusLabel(String? status) {
    switch (status) {
      case 'draft':      return 'مسودة';
      case 'confirmed':  return 'مؤكد';
      case 'delivered':  return 'تم التسليم';
      case 'paid':       return 'مدفوع';
      case 'cancelled':  return 'ملغى';
      default:           return status ?? '—';
    }
  }

  Color _statusColor(String? status) {
    switch (status) {
      case 'draft':      return Colors.grey;
      case 'confirmed':  return _blue;
      case 'delivered':  return _green;
      case 'paid':       return _green;
      case 'cancelled':  return _red;
      default:           return Colors.grey;
    }
  }

  String _fmtAmount(dynamic v) =>
      '${_amountFmt.format((v as num?)?.toDouble() ?? 0.0)} DA';

  String _fmtDate(String? iso) {
    if (iso == null || iso.isEmpty) return '—';
    try { return _dateFmt.format(DateTime.parse(iso)); } catch (_) { return iso; }
  }

  // ─── Build ────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: _buildAppBar(),
      body: Column(
        children: [
          _buildFilterBar(),
          if (_loading)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else if (_error != null)
            Expanded(child: _buildError())
          else ...[
            _buildStatsRow(),
            Expanded(child: _buildSalesList()),
          ],
        ],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: _cyan,
        onPressed: _createNew,
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  // ─── AppBar ───────────────────────────────────────────────────────────────
  AppBar _buildAppBar() {
    return AppBar(
      backgroundColor: _blue,
      elevation: 0,
      title: _showSearch
          ? TextField(
              controller: _searchCtrl,
              autofocus: true,
              style: const TextStyle(fontFamily: 'Cairo', color: Colors.white),
              cursorColor: _cyan,
              decoration: const InputDecoration(
                hintText: 'بحث...',
                hintStyle: TextStyle(fontFamily: 'Cairo', color: Colors.white54),
                border: InputBorder.none,
              ),
              onChanged: (v) {
                _searchQuery = v.trim();
                _loadSales();
              },
            )
          : const Text(
              'بيع المواد والمستلزمات',
              style: TextStyle(
                fontFamily: 'Cairo',
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
      actions: [
        IconButton(
          icon: Icon(
            _showSearch ? Icons.close : Icons.search_rounded,
            color: Colors.white,
          ),
          onPressed: () {
            setState(() {
              _showSearch = !_showSearch;
              if (!_showSearch) {
                _searchCtrl.clear();
                _searchQuery = '';
                _loadSales();
              }
            });
          },
        ),
      ],
    );
  }

  // ─── Filter bar ───────────────────────────────────────────────────────────
  Widget _buildFilterBar() {
    return Container(
      color: _blue,
      padding: const EdgeInsets.only(bottom: 10, left: 8, right: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: List.generate(_filterLabels.length, (i) {
            final selected = _selectedDocType == _filterValues[i];
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: FilterChip(
                label: Text(
                  _filterLabels[i],
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 12,
                    color: selected ? Colors.white : _blue,
                    fontWeight:
                        selected ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
                selected: selected,
                onSelected: (_) {
                  setState(() => _selectedDocType = _filterValues[i]);
                  _loadSales();
                },
                backgroundColor: Colors.white,
                selectedColor: _cyan,
                checkmarkColor: Colors.white,
                showCheckmark: false,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                  side: BorderSide(
                      color: selected ? _cyan : Colors.white54, width: 1.5),
                ),
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              ),
            );
          }),
        ),
      ),
    );
  }

  // ─── Stats row ────────────────────────────────────────────────────────────
  Widget _buildStatsRow() {
    final count     = _sales.length;
    final revenue   = _sumField('net_total');
    final paid      = _sumField('paid_amount');
    final remaining = _sumField('remaining_amount');

    return Container(
      color: Colors.grey.shade100,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _statCard('الوثائق', count.toString(), Icons.description_rounded,
                _blue),
            _statCard('الإيرادات', _fmtAmount(revenue),
                Icons.attach_money_rounded, _green),
            _statCard('المدفوع', _fmtAmount(paid),
                Icons.check_circle_rounded, _cyan),
            _statCard('المتبقي', _fmtAmount(remaining),
                Icons.pending_rounded, _orange),
          ],
        ),
      ),
    );
  }

  Widget _statCard(
      String label, String value, IconData icon, Color color) {
    return Container(
      width: 160,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.15),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
        border: Border(left: BorderSide(color: color, width: 4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 18),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 11,
                    color: Colors.grey.shade600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  // ─── Sales list ───────────────────────────────────────────────────────────
  Widget _buildSalesList() {
    if (_sales.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inbox_rounded,
                size: 64, color: Colors.grey.shade300),
            const SizedBox(height: 12),
            Text(
              'لا توجد وثائق',
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 16,
                color: Colors.grey.shade500,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 80),
      itemCount: _sales.length,
      itemBuilder: (ctx, i) => _buildSaleCard(_sales[i]),
    );
  }

  Widget _buildSaleCard(Map<String, dynamic> sale) {
    final docType = sale['doc_type'] as String?;
    final status  = sale['status']   as String?;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 5),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Row 1: code + chips + amount ──────────────────────────────
            Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          sale['sale_code'] as String? ?? '—',
                          style: const TextStyle(
                            fontFamily: 'Cairo',
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 6),
                      _chip(_docTypeLabel(docType), _docTypeColor(docType)),
                      const SizedBox(width: 4),
                      _chip(_statusLabel(status), _statusColor(status)),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  _fmtAmount(sale['net_total']),
                  style: const TextStyle(
                    fontFamily: 'Cairo',
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: _blue,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            // ── Row 2: client + date ─────────────────────────────────────
            Row(
              children: [
                const Icon(Icons.person_rounded,
                    size: 14, color: Colors.grey),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    sale['client_name'] as String? ?? '—',
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 12,
                      color: Colors.grey.shade700,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const Icon(Icons.calendar_today_rounded,
                    size: 12, color: Colors.grey),
                const SizedBox(width: 4),
                Text(
                  _fmtDate(sale['sale_date'] as String?),
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 12,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Divider(height: 1),
            const SizedBox(height: 4),
            // ── Row 3: action buttons ────────────────────────────────────
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                _actionBtn(
                  icon: Icons.print_rounded,
                  label: 'طباعة',
                  color: _blue,
                  onTap: () => _printPdf(sale),
                ),
                const SizedBox(width: 6),
                _actionBtn(
                  icon: Icons.edit_rounded,
                  label: 'تعديل',
                  color: _cyan,
                  onTap: () => _openEditor(sale),
                ),
                const SizedBox(width: 6),
                _actionBtn(
                  icon: Icons.delete_rounded,
                  label: 'حذف',
                  color: _red,
                  onTap: () => _confirmDelete(sale),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.4), width: 0.8),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: 'Cairo',
          fontSize: 10,
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _actionBtn({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 11,
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Error state ──────────────────────────────────────────────────────────
  Widget _buildError() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline_rounded,
              size: 48, color: _red),
          const SizedBox(height: 12),
          Text(
            'حدث خطأ أثناء التحميل',
            style: const TextStyle(
                fontFamily: 'Cairo',
                fontSize: 16,
                fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          Text(
            _error!,
            style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 12,
                color: Colors.grey.shade600),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: _blue),
            onPressed: _refresh,
            icon: const Icon(Icons.refresh_rounded, color: Colors.white),
            label: const Text('إعادة المحاولة',
                style: TextStyle(fontFamily: 'Cairo', color: Colors.white)),
          ),
        ],
      ),
    );
  }
}
