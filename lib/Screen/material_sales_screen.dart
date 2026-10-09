import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:provider/provider.dart';
import '../sql_database.dart';
import '../services/cloud_sync_service.dart';
import '../settings/app_settings.dart';
import '../settings/localization.dart';
import 'material_sale_editor_screen.dart';
import '../services/material_sale_pdf_service.dart';
import 'inventory_screen.dart';

enum _SalesSection {
  dashboard,
  orders,
  reservations,
  deliveries,
  invoices,
  proformas,
  journal,
  stock,
}

class MaterialSalesScreen extends StatefulWidget {
  final SqlDatabase db;
  const MaterialSalesScreen({super.key, required this.db});

  @override
  State<MaterialSalesScreen> createState() => _MaterialSalesScreenState();
}

class _MaterialSalesScreenState extends State<MaterialSalesScreen>
    with SingleTickerProviderStateMixin {
  // ─── Colors ───────────────────────────────────────────────────────────────
  static const _blue = Color(0xFF1E3A8A);
  static const _cyan = Color(0xFF06B6D4);
  static const _green = Color(0xFF10B981);
  static const _red = Color(0xFFEF4444);
  static const _orange = Color(0xFFF59E0B);

  // ─── State ────────────────────────────────────────────────────────────────
  SqlDatabase get _db => widget.db;
  _SalesSection _section = _SalesSection.dashboard;
  String _searchQuery = '';
  bool _showSearch = false;
  final TextEditingController _searchCtrl = TextEditingController();

  List<Map<String, dynamic>> _sales = [];
  bool _loading = true;
  String? _error;

  StreamSubscription<String>? _syncSub;

  // ─── Formatters ───────────────────────────────────────────────────────────
  final _amountFmt = NumberFormat('#,##0.00');
  final _dateFmt = DateFormat('dd/MM/yyyy');

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
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await _db.readMaterialSales();
      if (mounted)
        setState(() {
          _sales = data;
          _loading = false;
        });
    } catch (e) {
      if (mounted)
        setState(() {
          _error = e.toString();
          _loading = false;
        });
    }
  }

  void _refresh() => _loadSales();

  // ─── Stats ────────────────────────────────────────────────────────────────
  List<Map<String, dynamic>> get _visibleSales {
    Iterable<Map<String, dynamic>> rows = _sales;
    switch (_section) {
      case _SalesSection.orders:
        rows = rows.where((r) => r['doc_type'] == 'bon_commande');
        break;
      case _SalesSection.reservations:
        rows = rows.where((r) => r['status'] == 'reserved');
        break;
      case _SalesSection.deliveries:
        rows = rows.where(
          (r) =>
              r['doc_type'] == 'bon_livraison' || r['doc_type'] == 'bon_route',
        );
        break;
      case _SalesSection.invoices:
        rows = rows.where((r) => r['doc_type'] == 'facture');
        break;
      case _SalesSection.proformas:
        rows = rows.where((r) => r['doc_type'] == 'devis');
        break;
      case _SalesSection.dashboard:
      case _SalesSection.journal:
      case _SalesSection.stock:
        break;
    }
    final query = _searchQuery.toLowerCase();
    if (query.isNotEmpty) {
      rows = rows.where(
        (r) =>
            (r['sale_code'] ?? '').toString().toLowerCase().contains(query) ||
            (r['client_name'] ?? '').toString().toLowerCase().contains(query),
      );
    }
    return rows.toList();
  }

  double _sumField(String field, {bool? externalOnly}) => _visibleSales.fold(
    0.0,
    (s, r) {
      if (externalOnly == true && r['is_internal'] == 1) return s;
      return s + ((r[field] as num?) ?? 0).toDouble();
    },
  );

  // ─── Actions ─────────────────────────────────────────────────────────────
  Future<void> _createNew() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MaterialSaleEditorScreen(
          db: _db,
          initialDocType: _initialDocTypeForSection(),
        ),
      ),
    );
    _refresh();
  }

  String _initialDocTypeForSection() {
    switch (_section) {
      case _SalesSection.deliveries:
        return 'bon_livraison';
      case _SalesSection.invoices:
        return 'facture';
      case _SalesSection.proformas:
        return 'devis';
      default:
        return 'bon_commande';
    }
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
      await MaterialSalePdfService.printOrShare(
        bytes,
        sale['sale_code'] as String,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'خطأ في الطباعة: $e',
            style: const TextStyle(fontFamily: 'Cairo'),
          ),
          backgroundColor: _red,
        ),
      );
    }
  }

  Future<void> _confirmDelete(Map<String, dynamic> sale) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          _t('تأكيد الحذف'),
          style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold),
        ),
        content: Text(
          '${_t('هل أنت متأكد من حذف الوثيقة')} ${sale['sale_code']}؟',
          style: const TextStyle(fontFamily: 'Cairo'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              _t('إلغاء'),
              style: const TextStyle(fontFamily: 'Cairo', color: Colors.grey),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: _red),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              _t('حذف'),
              style: const TextStyle(fontFamily: 'Cairo', color: Colors.white),
            ),
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
            content: Text(
              'خطأ في الحذف: $e',
              style: const TextStyle(fontFamily: 'Cairo'),
            ),
            backgroundColor: _red,
          ),
        );
      }
    }
  }

  String _t(String key) {
    final lang = Provider.of<AppSettingsProvider>(context, listen: false).language;
    return Localization.translate(key, lang);
  }

  // ─── Label/color helpers ──────────────────────────────────────────────────
  String _docTypeLabel(String? type) {
    switch (type) {
      case 'bon_livraison':
        return _t('وصل تسليم مواد');
      case 'facture':
        return _t('فاتورة مواد');
      case 'bon_commande':
        return _t('طلب مواد');
      case 'bon_route':
        return _t('وصل مسار مواد');
      case 'devis':
        return _t('فاتورة أولية مواد');
      default:
        return type ?? '—';
    }
  }

  Color _docTypeColor(String? type) {
    switch (type) {
      case 'bon_livraison':
        return _cyan;
      case 'facture':
        return _blue;
      case 'bon_commande':
        return _orange;
      case 'bon_route':
        return const Color(0xFF7C3AED);
      case 'devis':
        return Colors.teal;
      default:
        return Colors.grey;
    }
  }

  String _statusLabel(String? status) {
    switch (status) {
      case 'draft':
        return _t('مسودة');
      case 'reserved':
        return _t('محجوز');
      case 'confirmed':
        return _t('مؤكد');
      case 'delivered':
        return _t('تم التسليم');
      case 'paid':
        return _t('مدفوع');
      case 'cancelled':
        return _t('ملغى');
      default:
        return status ?? '—';
    }
  }

  Color _statusColor(String? status) {
    switch (status) {
      case 'draft':
        return Colors.grey;
      case 'reserved':
        return _orange;
      case 'confirmed':
        return _blue;
      case 'delivered':
        return _green;
      case 'paid':
        return _green;
      case 'cancelled':
        return _red;
      default:
        return Colors.grey;
    }
  }

  String _fmtAmount(dynamic v) =>
      '${_amountFmt.format((v as num?)?.toDouble() ?? 0.0)} DA';

  String _fmtDate(String? iso) {
    if (iso == null || iso.isEmpty) return '—';
    try {
      return _dateFmt.format(DateTime.parse(iso));
    } catch (_) {
      return iso;
    }
  }

  // ─── Build ────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: _buildAppBar(),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final desktop = constraints.maxWidth >= 850;
          if (desktop) {
            return Row(
              children: [
                _buildDesktopNavigation(),
                const VerticalDivider(width: 1),
                Expanded(child: _buildSectionContent()),
              ],
            );
          }
          return Column(
            children: [
              _buildMobileNavigation(),
              Expanded(child: _buildSectionContent()),
            ],
          );
        },
      ),
      floatingActionButton: _section == _SalesSection.stock
          ? null
          : FloatingActionButton(
              backgroundColor: _cyan,
              onPressed: _createNew,
              tooltip: _t('إنشاء وثيقة'),
              child: const Icon(Icons.add, color: Colors.white),
            ),
    );
  }

  String _sectionLabel(_SalesSection section) {
    switch (section) {
      case _SalesSection.dashboard:
        return _t('لوحة المتابعة');
      case _SalesSection.orders:
        return _t('الطلبات');
      case _SalesSection.reservations:
        return _t('الحجوزات');
      case _SalesSection.deliveries:
        return _t('التسليمات');
      case _SalesSection.invoices:
        return _t('الفواتير');
      case _SalesSection.proformas:
        return _t('عروض الأسعار');
      case _SalesSection.journal:
        return _t('سجل المبيعات');
      case _SalesSection.stock:
        return _t('المخزون المتاح');
    }
  }

  static const _sectionIcons = <_SalesSection, IconData>{
    _SalesSection.dashboard: Icons.dashboard_rounded,
    _SalesSection.orders: Icons.shopping_cart_checkout_rounded,
    _SalesSection.reservations: Icons.bookmark_added_rounded,
    _SalesSection.deliveries: Icons.local_shipping_rounded,
    _SalesSection.invoices: Icons.receipt_long_rounded,
    _SalesSection.proformas: Icons.request_quote_rounded,
    _SalesSection.journal: Icons.menu_book_rounded,
    _SalesSection.stock: Icons.inventory_2_rounded,
  };

  Widget _buildDesktopNavigation() {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: 230,
      color: colors.surfaceContainerLow,
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: ListView(
        children: _SalesSection.values.map((section) {
          final selected = section == _section;
          return ListTile(
            selected: selected,
            selectedTileColor: _cyan.withOpacity(0.12),
            leading: Icon(
              _sectionIcons[section],
              color: selected ? _blue : colors.onSurfaceVariant,
            ),
            title: Text(
              _sectionLabel(section),
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 13,
                fontWeight: selected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
            onTap: () => setState(() => _section = section),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildMobileNavigation() {
    return Material(
      color: _blue,
      child: SizedBox(
        height: 52,
        child: ListView.separated(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
          scrollDirection: Axis.horizontal,
          itemCount: _SalesSection.values.length,
          separatorBuilder: (_, __) => const SizedBox(width: 6),
          itemBuilder: (context, index) {
            final section = _SalesSection.values[index];
            final selected = section == _section;
            return ChoiceChip(
              selected: selected,
              showCheckmark: false,
              avatar: Icon(
                _sectionIcons[section],
                size: 17,
                color: selected ? Colors.white : _blue,
              ),
              label: Text(
                _sectionLabel(section),
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 11,
                  color: selected ? Colors.white : _blue,
                ),
              ),
              selectedColor: _cyan,
              backgroundColor: Colors.white,
              onSelected: (_) => setState(() => _section = section),
            );
          },
        ),
      ),
    );
  }

  Widget _buildSectionContent() {
    if (_section == _SalesSection.stock) return _buildStockSection();
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return _buildError();
    return Column(
      children: [
        _buildStatsRow(),
        Expanded(child: _buildSalesList()),
      ],
    );
  }

  Widget _buildStockSection() {
    final colors = Theme.of(context).colorScheme;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.inventory_2_rounded, size: 58, color: _cyan),
              const SizedBox(height: 14),
              Text(
                _t('المخزون المتاح للبيع'),
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: colors.onSurface,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                _t('يعرض نفس مخزون الورشة المتاح للبيع، دون إنشاء مخزون منفصل.'),
                style: TextStyle(
                  fontFamily: 'Cairo',
                  color: colors.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => InventoryScreen(db: _db)),
                ),
                icon: const Icon(Icons.open_in_new_rounded),
                label: Text(
                  _t('فتح المخزون'),
                  style: const TextStyle(fontFamily: 'Cairo'),
                ),
              ),
            ],
          ),
        ),
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
              decoration: InputDecoration(
                hintText: _t('بحث...'),
                hintStyle: const TextStyle(
                  fontFamily: 'Cairo',
                  color: Colors.white54,
                ),
                border: InputBorder.none,
              ),
              onChanged: (v) {
                setState(() => _searchQuery = v.trim());
              },
            )
          : Text(
              _t('بيع المواد والمستلزمات'),
              style: const TextStyle(
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
              }
            });
          },
        ),
      ],
    );
  }

  // ─── Stats row ────────────────────────────────────────────────────────────
  Widget _buildStatsRow() {
    final count = _visibleSales.length;
    final externalRevenue = _sumField('net_total', externalOnly: true);
    final paid = _sumField('paid_amount', externalOnly: true);
    final remaining = _sumField('remaining_amount', externalOnly: true);
    final internalTransfers = _visibleSales
        .where((r) => r['is_internal'] == 1)
        .fold(0.0, (s, r) => s + ((r['net_total'] as num?) ?? 0).toDouble());

    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _statCard(
              _t('الوثائق'),
              count.toString(),
              Icons.description_rounded,
              _blue,
            ),
            _statCard(
              _t('الإيرادات'),
              _fmtAmount(externalRevenue),
              Icons.attach_money_rounded,
              _green,
            ),
            _statCard(
              _t('المدفوع'),
              _fmtAmount(paid),
              Icons.check_circle_rounded,
              _cyan,
            ),
            _statCard(
              _t('المتبقي'),
              _fmtAmount(remaining),
              Icons.pending_rounded,
              _orange,
            ),
            if (internalTransfers > 0)
              _statCard(
                _t('تحويلات داخلية للورشة'),
                _fmtAmount(internalTransfers),
                Icons.swap_horiz_rounded,
                Colors.purple,
              ),
          ],
        ),
      ),
    );
  }

  Widget _statCard(String label, String value, IconData icon, Color color) {
    return Container(
      width: 160,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
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
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
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
    final sales = _visibleSales;
    if (sales.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inbox_rounded, size: 64, color: Colors.grey.shade300),
            const SizedBox(height: 12),
            Text(
              _t('لا توجد وثائق'),
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
      itemCount: sales.length,
      itemBuilder: (ctx, i) => _buildSaleCard(sales[i]),
    );
  }

  Widget _buildSaleCard(Map<String, dynamic> sale) {
    final docType = sale['doc_type'] as String?;
    final status = sale['status'] as String?;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 5),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: 7,
              runSpacing: 7,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  sale['sale_code'] as String? ?? '—',
                  style: const TextStyle(
                    fontFamily: 'Cairo',
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                _chip(_docTypeLabel(docType), _docTypeColor(docType)),
                _chip(_statusLabel(status), _statusColor(status)),
                Text(
                  _fmtAmount(sale['net_total']),
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: Theme.of(context).brightness == Brightness.dark
                        ? _cyan
                        : _blue,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            // ── Row 2: client + date ─────────────────────────────────────
            Row(
              children: [
                const Icon(Icons.person_rounded, size: 14, color: Colors.grey),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    sale['client_name'] as String? ?? '—',
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const Icon(
                  Icons.calendar_today_rounded,
                  size: 12,
                  color: Colors.grey,
                ),
                const SizedBox(width: 4),
                Text(
                  _fmtDate(sale['sale_date'] as String?),
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
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
                  label: _t('طباعة'),
                  color: _blue,
                  onTap: () => _printPdf(sale),
                ),
                const SizedBox(width: 6),
                _actionBtn(
                  icon: Icons.edit_rounded,
                  label: _t('تعديل'),
                  color: _cyan,
                  onTap: () => _openEditor(sale),
                ),
                const SizedBox(width: 6),
                _actionBtn(
                  icon: Icons.delete_rounded,
                  label: _t('حذف'),
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
          const Icon(Icons.error_outline_rounded, size: 48, color: _red),
          const SizedBox(height: 12),
          Text(
            _t('حدث خطأ أثناء التحميل'),
            style: const TextStyle(
              fontFamily: 'Cairo',
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _error!,
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 12,
              color: Colors.grey.shade600,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: _blue),
            onPressed: _refresh,
            icon: const Icon(Icons.refresh_rounded, color: Colors.white),
            label: Text(
              _t('إعادة المحاولة'),
              style: const TextStyle(fontFamily: 'Cairo', color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}
