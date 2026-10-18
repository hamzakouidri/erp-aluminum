import 'dart:async';
import 'package:database_data/widgets/app_material.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:database_data/settings/localization.dart';
import 'package:database_data/settings/document_status_localization.dart';
import '../services/cloud_sync_service.dart';
import '../sql_database.dart';
import 'achat_details_screen.dart';
import 'achat_return_screen.dart';
import 'ai_scanner_screen.dart';
import 'trash_screen.dart';
import 'app_workspace_shell.dart';
import '../widgets/home_back_boundary.dart';
import '../widgets/resizable_columns_table.dart';
import 'package:database_data/settings/app_settings.dart';
import 'package:provider/provider.dart';

enum _AchatViewMode { cards, table }

class AchatScreen extends StatefulWidget {
  final SqlDatabase db;

  /// وضع العرض فقط — يخفي FAB وأزرار التعديل/الحذف
  final bool readOnly;

  /// true: مشتريات الورشة فقط, false: مشتريات محل المواد فقط, null: تلقائي حسب نوع النشاط
  final bool? isWorkshop;

  const AchatScreen({
    super.key,
    required this.db,
    this.readOnly = false,
    this.isWorkshop,
  });

  @override
  State<AchatScreen> createState() => _AchatScreenState();
}

class _AchatScreenState extends State<AchatScreen>
    with SingleTickerProviderStateMixin {
  late Future<List<Map<String, dynamic>>> _achatsFuture;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String _selectedStatusFilter = 'الكل';
  int? _expandedAchatId;
  StreamSubscription? _syncSub;
  bool? _selectedModeIsWorkshop;
  _AchatViewMode _viewMode = _AchatViewMode.cards;
  int? _selectedAchatId;

  bool get _effectiveIsWorkshop {
    if (_selectedModeIsWorkshop != null) return _selectedModeIsWorkshop!;
    if (widget.isWorkshop != null) return widget.isWorkshop!;
    final settings = Provider.of<AppSettingsProvider>(context, listen: false);
    if (!settings.hasWorkshop && settings.hasMaterialsStore) return false;
    if (settings.hasWorkshop && !settings.hasMaterialsStore) return true;
    if (settings.workingSection == WorkingSection.materialsStore) return false;
    return true;
  }

  // ── Palette ───────────────────────────────────────────────────────────────
  static const _blue = Color(0xFF2563EB);
  static const _blueLight = Color(0xFF3B82F6);
  static const _cyan = Color(0xFF0EA5E9);

  Color get _cardBg => Theme.of(context).cardColor;

  Color get _bg => Theme.of(context).scaffoldBackgroundColor;
  static const _green = Color(0xFF10B981);
  static const _red = Color(0xFFEF4444);
  static const _orange = Color(0xFFF59E0B);

  void _openAchatDetails({
    required int achatId,
    required String invoiceNumber,
    required String supplierName,
    bool autoOpenPicker = false,
  }) {
    final lang = Provider.of<AppSettingsProvider>(
      context,
      listen: false,
    ).language;
    openAdaptiveScreen(
      context,
      title:
          '$supplierName • ${Localization.translate('تفاصيل الشراء', lang)} #$invoiceNumber',
      icon: Icons.receipt_long_rounded,
      entryId: 'achat_details_$achatId',
      screen: AchatDetailsScreen(
        achatId: achatId,
        invoiceNumber: invoiceNumber,
        supplierName: supplierName,
        autoOpenPicker: autoOpenPicker,
      ),
    );
    _refreshList();
  }

  Color get _text => Theme.of(context).colorScheme.onSurface;

  Color get _textDim =>
      Theme.of(context).colorScheme.onSurface.withOpacity(0.7);

  Color get _divider => Theme.of(context).dividerColor;

  @override
  void initState() {
    super.initState();
    _refreshList();
    _syncSub = CloudSyncService().dbUpdateStream.listen((_) {
      if (mounted) {
        _refreshList();
      }
    });
  }

  void _refreshList() {
    setState(() {
      _achatsFuture = widget.db.readAchats(isWorkshop: _effectiveIsWorkshop);
      _expandedAchatId = null;
    });
  }

  void _openPurchaseReturns() {
    final lang = context.read<AppSettingsProvider>().language;
    openAdaptiveScreen(
      context,
      title: Localization.translate('مردودات المشتريات (Retours)', lang),
      icon: Icons.assignment_return_rounded,
      entryId: 'purchase_returns_${_effectiveIsWorkshop ? 'workshop' : 'store'}',
      screen: AchatReturnScreen(
        db: widget.db,
        isWorkshop: _effectiveIsWorkshop,
      ),
    );
    _refreshList();
  }

  void _openAiScanner() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => AiScannerScreen(db: widget.db)),
    );
    if (result == true) {
      _refreshList();
    }
  }

  @override
  void dispose() {
    _syncSub?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  String _formatDate(String dateStr) {
    try {
      final parsed = DateTime.parse(dateStr);
      return DateFormat('yyyy-MM-dd HH:mm').format(parsed);
    } catch (_) {
      return dateStr;
    }
  }

  // 🟢 تصحيح حساب الإحصائيات ليدعم الحالات المتعددة (مؤكد/مدفوع/ملغى/نشط)
  Map<String, dynamic> _calculateStats(List<Map<String, dynamic>> data) {
    double totalActive = 0.0;
    int activeCount = 0;
    int cancelledCount = 0;
    int paidCount = 0;

    for (var row in data) {
      final status = row['status'] ?? 'Active';
      final total = (row['total'] as num?)?.toDouble() ?? 0.0;

      if (status == 'Cancelled' || status == 'ملغى') {
        cancelledCount++;
      } else if (status == 'Paid' ||
          status == 'Confirmed' ||
          status == 'مؤكد') {
        totalActive += total;
        paidCount++;
      } else {
        totalActive += total;
        activeCount++;
      }
    }

    return {
      'totalActive': totalActive,
      'activeCount': activeCount,
      'cancelledCount': cancelledCount,
      'paidCount': paidCount,
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: CustomScrollView(
        slivers: [
          _buildAppBar(),
          SliverToBoxAdapter(
            child: Directionality(
              textDirection: TextDirection.rtl,
              child: FutureBuilder<List<Map<String, dynamic>>>(
                future: _achatsFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return Padding(
                      padding: EdgeInsets.only(top: 80.0),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  } else if (snapshot.hasError) {
                    return Padding(
                      padding: EdgeInsets.only(top: 80.0),
                      child: Center(
                        child: Text(
                          'حدث خطأ: ${snapshot.error}',
                          style: TextStyle(fontFamily: 'Cairo', color: _red),
                        ),
                      ),
                    );
                  }

                  final allData = snapshot.data ?? [];
                  final stats = _calculateStats(allData);

                  // تطبيق فلتر البحث والحالة
                  final filteredData = allData.where((item) {
                    final supplier = (item['supplier_name'] ?? '')
                        .toString()
                        .toLowerCase();
                    final invoice = (item['invoice_number'] ?? '')
                        .toString()
                        .toLowerCase();
                    final query = _searchQuery.toLowerCase();
                    final status = item['status'] ?? 'Active';

                    bool matchesSearch =
                        supplier.contains(query) || invoice.contains(query);
                    bool matchesFilter = true;

                    if (_selectedStatusFilter == 'نشطة') {
                      matchesFilter = status == 'Active';
                    } else if (_selectedStatusFilter == 'مدفوعة') {
                      matchesFilter =
                          status == 'Paid' ||
                          status == 'Confirmed' ||
                          status == 'مؤكد';
                    } else if (_selectedStatusFilter == 'ملغاة') {
                      matchesFilter = status == 'Cancelled' || status == 'ملغى';
                    } else if (_selectedStatusFilter == 'مردودة') {
                      matchesFilter =
                          status == 'Returned' || status == 'Partial Returned';
                    }

                    return matchesSearch && matchesFilter;
                  }).toList();
                  Map<String, dynamic>? selectedAchat;
                  for (final item in filteredData) {
                    if (item['id'] == _selectedAchatId) {
                      selectedAchat = item;
                      break;
                    }
                  }

                  return Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: 16.0,
                      vertical: 16.0,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // ── بطاقات الإحصائيات ──
                        _buildStatsRow(stats),
                        SizedBox(height: 24),

                        // ── شريط البحث وعنوان الفواتير ──
                        _buildSearchAndTitle(),
                        SizedBox(height: 12),

                        _buildViewModeSelector(),
                        if (_viewMode == _AchatViewMode.table &&
                            selectedAchat != null)
                          _buildSelectedAchatActions(selectedAchat),
                        SizedBox(height: 12),

                        // ── فلاتر الحالة ──
                        _buildFilterChips(),
                        SizedBox(height: 16),

                        // ── قائمة فواتير المشتريات ──
                        filteredData.isEmpty
                            ? _buildEmptyState()
                            : _viewMode == _AchatViewMode.table
                            ? _buildAchatTable(filteredData)
                            : ListView.builder(
                                primary: false,
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                itemCount: filteredData.length,
                                itemBuilder: (context, index) {
                                  final item = filteredData[index];
                                  return _buildAchatCard(item);
                                },
                              ),
                        SizedBox(height: 80), // مساحة للـ FloatingActionButton
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
      floatingActionButton:
          (!widget.readOnly &&
              Provider.of<AppSettingsProvider>(context).canAddPurchases())
          ? FloatingActionButton.extended(
              onPressed: _showAddAchatDialog,
              backgroundColor: _blue,
              elevation: 4,
              icon: Icon(Icons.add_rounded, color: Colors.white),
              label: Text(
                Localization.translate(
                  'فاتورة جديدة',
                  Provider.of<AppSettingsProvider>(context).language,
                ),
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            )
          : null,
    );
  }

  Widget _buildViewModeSelector() {
    final lang = Provider.of<AppSettingsProvider>(
      context,
      listen: false,
    ).language;
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: SegmentedButton<_AchatViewMode>(
        segments: [
          ButtonSegment(
            value: _AchatViewMode.cards,
            icon: const Icon(Icons.view_agenda_rounded, size: 18),
            label: Text(Localization.translate('عرض كبطاقات', lang)),
          ),
          ButtonSegment(
            value: _AchatViewMode.table,
            icon: const Icon(Icons.table_rows_rounded, size: 18),
            label: Text(Localization.translate('عرض كجدول', lang)),
          ),
        ],
        selected: {_viewMode},
        onSelectionChanged: (selection) => setState(() {
          _viewMode = selection.first;
          if (_viewMode == _AchatViewMode.cards) _selectedAchatId = null;
        }),
      ),
    );
  }

  Widget _buildSelectedAchatActions(Map<String, dynamic> achat) {
    final lang = Provider.of<AppSettingsProvider>(
      context,
      listen: false,
    ).language;
    final id = (achat['id'] as num).toInt();
    final invoice = (achat['invoice_number'] ?? '').toString();
    final supplier = (achat['supplier_name'] ?? '').toString();
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      color: _blue.withOpacity(0.07),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '$supplier • $invoice',
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontFamily: 'Cairo',
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          TextButton.icon(
            onPressed: () => _openAchatDetails(
              achatId: id,
              invoiceNumber: invoice,
              supplierName: supplier,
            ),
            icon: const Icon(Icons.edit_rounded),
            label: Text(Localization.translate('تعديل', lang)),
          ),
          if (!widget.readOnly)
            TextButton.icon(
              onPressed: () => _confirmDeleteAchat(id, invoice),
              icon: const Icon(Icons.delete_rounded, color: _red),
              label: Text(
                Localization.translate('حذف', lang),
                style: const TextStyle(color: _red),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildAchatTable(List<Map<String, dynamic>> achats) {
    final lang = Provider.of<AppSettingsProvider>(
      context,
      listen: false,
    ).language;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final headerStyle = TextStyle(
      color: isDark ? Colors.white : const Color(0xFF18233B),
      fontWeight: FontWeight.bold,
      fontSize: 12,
      fontFamily: 'Cairo',
    );
    bool wasModified(Map<String, dynamic> achat) {
      final created = DateTime.tryParse(achat['created_at']?.toString() ?? '');
      final updated = DateTime.tryParse(achat['updated_at']?.toString() ?? '');
      if (created == null || updated == null) return false;
      return updated.difference(created).abs() > const Duration(seconds: 5);
    }
    return ResizableColumnsTable(
      persistenceKey: 'material_purchase_documents_v2',
      headerColor: isDark ? Colors.grey.shade900 : Colors.blueGrey.shade800,
      borderColor: isDark ? Colors.grey.shade800 : Colors.grey.shade300,
      rowColor: isDark ? const Color(0xFF171721) : Colors.white,
      headerMinHeight: 52,
      rowMinHeight: 64,
      maxBodyHeight: 560,
      columns: [
        ResizableTableColumn(
          id: 'invoice',
          label: Text(
            Localization.translate('رقم الوثيقة', lang),
            style: headerStyle,
          ),
          initialWidth: 170,
        ),
        ResizableTableColumn(
          id: 'supplier',
          label: Text(
            Localization.translate('المورد', lang),
            style: headerStyle,
          ),
          initialWidth: 280,
        ),
        ResizableTableColumn(
          id: 'created_at',
          label: Text(Localization.translate('تاريخ الإنشاء', lang), style: headerStyle),
          initialWidth: 180,
        ),
        ResizableTableColumn(
          id: 'created_by',
          label: Text(Localization.translate('أدخل من طرف', lang), style: headerStyle),
          initialWidth: 170,
        ),
        ResizableTableColumn(
          id: 'updated_at',
          label: Text(Localization.translate('تاريخ التعديل', lang), style: headerStyle),
          initialWidth: 180,
        ),
        ResizableTableColumn(
          id: 'updated_by',
          label: Text(Localization.translate('عُدل من طرف', lang), style: headerStyle),
          initialWidth: 170,
        ),
        ResizableTableColumn(
          id: 'status',
          label: Text(
            Localization.translate('الحالة', lang),
            style: headerStyle,
          ),
          initialWidth: 150,
        ),
        ResizableTableColumn(
          id: 'amount',
          label: Text(
            Localization.translate('المبلغ', lang),
            style: headerStyle,
          ),
          initialWidth: 180,
        ),
        ResizableTableColumn(
          id: 'actions',
          label: Text(
            Localization.translate('إجراء', lang),
            style: headerStyle,
          ),
          initialWidth: 150,
          alignment: Alignment.center,
        ),
      ],
      rows: achats.map((achat) {
        final id = (achat['id'] as num).toInt();
        final invoice = (achat['invoice_number'] ?? '—').toString();
        final supplier = (achat['supplier_name'] ?? '—').toString();
        final modified = wasModified(achat);
        return ResizableTableRow(
          reorderId: id.toString(),
          color: id == _selectedAchatId ? _blue.withOpacity(0.09) : null,
          onTap: () => setState(() => _selectedAchatId = id),
          onDoubleTap: () => _openAchatDetails(
            achatId: id,
            invoiceNumber: invoice,
            supplierName: supplier,
          ),
          cells: [
            Text(invoice, style: const TextStyle(fontWeight: FontWeight.bold)),
            Text(supplier, overflow: TextOverflow.ellipsis),
            Text(_formatDate((achat['created_at'] ?? '').toString())),
            Text((achat['created_by'] ?? '—').toString()),
            Text(modified ? _formatDate((achat['updated_at'] ?? '').toString()) : '—'),
            Text(modified ? (achat['updated_by'] ?? '—').toString() : '—'),
            Text(localizeDocumentStatus(achat['status'] ?? 'Active', lang)),
            Text(
              '${NumberFormat('#,##0.00', 'en_US').format((achat['total'] as num?)?.toDouble() ?? 0)} DZD',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  tooltip: Localization.translate('تعديل', lang),
                  onPressed: () => _openAchatDetails(
                    achatId: id,
                    invoiceNumber: invoice,
                    supplierName: supplier,
                  ),
                  icon: const Icon(Icons.edit_rounded, size: 19),
                ),
                if (!widget.readOnly)
                  IconButton(
                    tooltip: Localization.translate('حذف', lang),
                    onPressed: () => _confirmDeleteAchat(id, invoice),
                    icon: const Icon(
                      Icons.delete_outline_rounded,
                      size: 19,
                      color: _red,
                    ),
                  ),
              ],
            ),
          ],
        );
      }).toList(),
    );
  }

  // ── Sliver App Bar with Gradient ──────────────────────────────────────────
  Widget _buildAppBar() {
    return SliverAppBar(
      expandedHeight: 150.0,
      pinned: true,
      backgroundColor: Theme.of(context).cardColor,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      iconTheme: IconThemeData(
        color: Theme.of(context).brightness == Brightness.dark
            ? Colors.white
            : Colors.white,
      ),
      automaticallyImplyLeading: false,
      leading: HomeBackScope.of(context) != null
          ? const SizedBox(width: kToolbarHeight)
          : (Navigator.canPop(context)
                ? const BackButton(color: Colors.white)
                : null),
      actions: [
        IconButton(
          icon: const Icon(Icons.assignment_return_rounded),
          tooltip: Localization.translate(
            'مردودات المشتريات (Retours)',
            Provider.of<AppSettingsProvider>(context, listen: false).language,
          ),
          onPressed: _openPurchaseReturns,
        ),
        IconButton(
          icon: const Icon(Icons.refresh_rounded),
          tooltip: Localization.translate(
            'تحديث',
            Provider.of<AppSettingsProvider>(context, listen: false).language,
          ),
          onPressed: () async {
            await CloudSyncService().syncPendingNow();
            _refreshList();
          },
        ),
        IconButton(
          icon: Icon(Icons.document_scanner_rounded),
          tooltip: Localization.translate(
            'مسح الفاتورة بالذكاء الاصطناعي',
            Provider.of<AppSettingsProvider>(context, listen: false).language,
          ),
          onPressed: _openAiScanner,
        ),
        if (Provider.of<AppSettingsProvider>(
          context,
          listen: false,
        ).canAccessTrash())
          IconButton(
            icon: const Icon(Icons.auto_delete_rounded),
            tooltip: Localization.translate(
              'سلة مهملات فواتير الشراء',
              Provider.of<AppSettingsProvider>(context, listen: false).language,
            ),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => TrashScreen(
                    db: widget.db,
                    initialIndex: 1,
                    onOrderRestored: _refreshList,
                  ),
                ),
              ).then((_) => _refreshList());
            },
          ),
        SizedBox(width: 8),
      ],
      flexibleSpace: FlexibleSpaceBar(
        background: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: Theme.of(context).brightness == Brightness.dark
                  ? [Color(0xFF111827), Color(0xFF070E1D)]
                  : [_blue, _cyan],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: const Stack(
            children: [
              Positioned(
                right: -20,
                top: -20,
                child: CircleAvatar(
                  radius: 80,
                  backgroundColor: Colors.white10,
                ),
              ),
              Positioned(
                left: 10,
                bottom: -30,
                child: CircleAvatar(
                  radius: 60,
                  backgroundColor: Colors.white10,
                ),
              ),
            ],
          ),
        ),
        title: Row(
          children: [
            Text(
              Localization.translate(
                _effectiveIsWorkshop ? 'مشتريات الورشة' : 'مشتريات محل المواد',
                Provider.of<AppSettingsProvider>(context).language,
              ),
              style: const TextStyle(
                fontFamily: 'Cairo',
                fontWeight: FontWeight.bold,
                fontSize: 18,
                color: Colors.white,
              ),
            ),
            if (widget.isWorkshop == null &&
                Provider.of<AppSettingsProvider>(context).isDualActivity) ...[
              const SizedBox(width: 12),
              InkWell(
                onTap: () {
                  setState(() {
                    _selectedModeIsWorkshop = !_effectiveIsWorkshop;
                    _refreshList();
                  });
                },
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white30),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.swap_horiz_rounded,
                        size: 16,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        Localization.translate(
                          _effectiveIsWorkshop ? 'محل المواد' : 'الورشة',
                          Provider.of<AppSettingsProvider>(context).language,
                        ),
                        style: const TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 12,
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
        titlePadding: const EdgeInsets.only(left: 56, bottom: 16, right: 16),
        centerTitle: false,
      ),
    );
  }

  // ── Stats Row ──────────────────────────────────────────────────────────────
  Widget _buildStatsRow(Map<String, dynamic> stats) {
    final lang = Provider.of<AppSettingsProvider>(
      context,
      listen: false,
    ).language;
    final currencyFormat = NumberFormat('#,##0.00', 'en_US');
    return Row(
      children: [
        Expanded(
          flex: 4,
          child: _buildStatItem(
            icon: Icons.monetization_on_rounded,
            label: Localization.translate('إجمالي المشتريات', lang),
            value: '${currencyFormat.format(stats['totalActive'])} دج',
            color: _blueLight,
          ),
        ),
        SizedBox(width: 8),
        Expanded(
          flex: 3,
          child: _buildStatItem(
            icon: Icons.check_circle_rounded,
            label: Localization.translate('مؤكد/نشط', lang),
            value: '${stats['activeCount'] + stats['paidCount']}',
            color: _green,
          ),
        ),
        SizedBox(width: 8),
        Expanded(
          flex: 2,
          child: _buildStatItem(
            icon: Icons.cancel_rounded,
            label: Localization.translate('ملغى', lang),
            value: stats['cancelledCount'].toString(),
            color: _red,
          ),
        ),
      ],
    );
  }

  // 🟢 استخدام FittedBox لمنع أي أوفر فلو في النصوص أو الأرقام الكبيرة
  Widget _buildStatItem({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _divider),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 16),
          ),
          SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerRight,
            child: Text(
              value,
              style: TextStyle(
                fontFamily: 'Cairo',
                fontWeight: FontWeight.w800,
                fontSize: 14,
                color: _text,
              ),
            ),
          ),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerRight,
            child: Text(
              label,
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 10,
                color: _textDim,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Search & Section Title ──────────────────────────────────────────────────
  Widget _buildSearchAndTitle() {
    final lang = Provider.of<AppSettingsProvider>(
      context,
      listen: false,
    ).language;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          Localization.translate('فواتير الشراء المستوردة', lang),
          style: TextStyle(
            fontFamily: 'Cairo',
            fontWeight: FontWeight.bold,
            fontSize: 16,
            color: _text,
          ),
        ),
        SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: _cardBg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _divider),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.01),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: TextField(
            controller: _searchController,
            onChanged: (value) {
              setState(() {
                _searchQuery = value;
              });
            },
            decoration: InputDecoration(
              hintText: Localization.translate(
                'البحث برقم الفاتورة أو اسم المورد...',
                lang,
              ),
              hintStyle: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 13,
                color: _textDim,
              ),
              prefixIcon: Icon(Icons.search_rounded, color: _textDim),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: Icon(Icons.clear_rounded, color: _textDim),
                      onPressed: () {
                        _searchController.clear();
                        setState(() {
                          _searchQuery = '';
                        });
                      },
                    )
                  : null,
              border: InputBorder.none,
              contentPadding: EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ),
      ],
    );
  }

  // ── Achat Card ─────────────────────────────────────────────────────────────
  Widget _buildAchatCard(Map<String, dynamic> item) {
    final lang = Provider.of<AppSettingsProvider>(
      context,
      listen: false,
    ).language;
    final id = item['id'] as int;
    final invoiceNumber = item['invoice_number'] ?? '';
    final supplierName = item['supplier_name'] ?? '';
    final status = item['status'] ?? 'Active';
    final total = (item['total'] as num?)?.toDouble() ?? 0.0;
    final createdAt = item['created_at'] ?? '';

    // 🟢 التصحيح الجذري للتعرف على الحالات
    final isCancelled = status == 'Cancelled' || status == 'ملغى';
    final isPaid =
        status == 'Paid' || status == 'Confirmed' || status == 'مؤكد';
    final isReturned = status == 'Returned';
    final isPartialReturned = status == 'Partial Returned';

    // تحديد لون ونصوص الحالة ديناميكياً
    Color statusColor = _orange;
    String statusLabel = localizeDocumentStatus(status, lang);

    if (isCancelled) {
      statusColor = _red;
      statusLabel = localizeDocumentStatus('Cancelled', lang);
    } else if (isReturned) {
      statusColor = Colors.purple;
      statusLabel = localizeDocumentStatus('Returned', lang);
    } else if (isPartialReturned) {
      statusColor = Colors.deepOrange;
      statusLabel = localizeDocumentStatus('Partial Returned', lang);
    } else if (isPaid) {
      statusColor = _green;
      statusLabel = localizeDocumentStatus(status, lang);
    }

    final currencyFormat = NumberFormat('#,##0.00', 'en_US');

    return Container(
      margin: EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isCancelled ? _red.withValues(alpha: 0.2) : _divider,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.015),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: () => _openAchatDetails(
            achatId: id,
            invoiceNumber: invoiceNumber,
            supplierName: supplierName,
          ),
          child: Container(
            decoration: BoxDecoration(
              border: Border(right: BorderSide(color: statusColor, width: 6)),
            ),
            child: Padding(
              padding: EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // المورد ورقم الفاتورة
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.business_rounded,
                                  color: _blue,
                                  size: 18,
                                ),
                                SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    supplierName,
                                    style: TextStyle(
                                      fontFamily: 'Cairo',
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15,
                                      color: _text,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                            SizedBox(height: 4),
                            Text(
                              '${Localization.translate('فاتورة رقم: ', lang)}$invoiceNumber',
                              style: TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 12,
                                color: _textDim,
                              ),
                            ),
                          ],
                        ),
                      ),
                      // شارة الحالة
                      Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          Localization.translate(statusLabel, lang),
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            fontWeight: FontWeight.bold,
                            fontSize: 10,
                            color: statusColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 12),
                  Divider(height: 1, color: _divider),
                  SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              Localization.translate(
                                'القيمة الإجمالية',
                                Provider.of<AppSettingsProvider>(
                                  context,
                                ).language,
                              ),
                              style: TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 11,
                                color: _textDim,
                              ),
                            ),
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerRight,
                              child: Text(
                                '${currencyFormat.format(total)} دج',
                                style: TextStyle(
                                  fontFamily: 'Cairo',
                                  fontWeight: FontWeight.w900,
                                  fontSize: 16,
                                  color: isCancelled ? _textDim : _text,
                                  decoration: isCancelled
                                      ? TextDecoration.lineThrough
                                      : null,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              Localization.translate(
                                'تاريخ التسجيل',
                                Provider.of<AppSettingsProvider>(
                                  context,
                                ).language,
                              ),
                              style: TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 11,
                                color: _textDim,
                              ),
                            ),
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text(
                                _formatDate(createdAt),
                                style: TextStyle(
                                  fontFamily: 'Cairo',
                                  fontSize: 12,
                                  color: _text,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  // 🟢 استخدام Wrap لمنع الأوفر فلو إذا كانت الشاشة ضيقة
                  if (!isCancelled) ...[
                    SizedBox(height: 12),
                    Divider(height: 1, color: _divider),
                    SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        if (!widget.readOnly &&
                            Provider.of<AppSettingsProvider>(
                              context,
                              listen: false,
                            ).canEditPurchases())
                          TextButton.icon(
                            style: TextButton.styleFrom(foregroundColor: _blue),
                            onPressed: () => _openAchatDetails(
                              achatId: id,
                              invoiceNumber: invoiceNumber,
                              supplierName: supplierName,
                            ),
                            icon: const Icon(Icons.edit, size: 18),
                            label: Text(
                              Localization.translate('تعديل', lang),
                              style: const TextStyle(fontFamily: 'Cairo'),
                            ),
                          ),
                        const SizedBox(width: 8),
                        if (!widget.readOnly &&
                            Provider.of<AppSettingsProvider>(
                              context,
                              listen: false,
                            ).canDeletePurchases())
                          IconButton(
                            style: IconButton.styleFrom(
                              foregroundColor: Colors.red,
                            ),
                            onPressed: () =>
                                _confirmDeleteAchat(id, invoiceNumber),
                            icon: Icon(Icons.delete_outline_rounded, size: 18),
                          ),
                      ],
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

  // ── Filter Chips ─────────────────────────────────────────────────────────
  Widget _buildFilterChips() {
    final lang = Provider.of<AppSettingsProvider>(
      context,
      listen: false,
    ).language;
    final filters = ['الكل', 'نشطة', 'مدفوعة', 'مردودة', 'ملغاة'];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: filters.map((filter) {
          final isSelected = _selectedStatusFilter == filter;
          return Padding(
            padding: const EdgeInsets.only(left: 8.0),
            child: ChoiceChip(
              label: Text(
                Localization.translate(filter, lang),
                style: TextStyle(
                  fontFamily: 'Cairo',
                  color: isSelected ? Colors.white : _textDim,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
              selected: isSelected,
              selectedColor: _blue,
              backgroundColor: _cardBg,
              side: BorderSide(color: isSelected ? _blue : _divider),
              onSelected: (selected) {
                if (selected) {
                  setState(() {
                    _selectedStatusFilter = filter;
                  });
                }
              },
            ),
          );
        }).toList(),
      ),
    );
  }

  // ── Empty State ────────────────────────────────────────────────────────────
  Widget _buildEmptyState() {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(vertical: 48),
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _divider),
      ),
      child: Column(
        children: [
          Icon(Icons.inventory_2_outlined, size: 48, color: _textDim),
          SizedBox(height: 16),
          Text(
            Localization.translate(
              'لا توجد فواتير مشتريات مسجلة',
              Provider.of<AppSettingsProvider>(context).language,
            ),
            style: TextStyle(
              fontFamily: 'Cairo',
              fontWeight: FontWeight.bold,
              fontSize: 14,
              color: _text,
            ),
          ),
          SizedBox(height: 4),
          Text(
            Localization.translate(
              'انقر على "فاتورة جديدة" لإضافة فاتورة واردة.',
              Provider.of<AppSettingsProvider>(context).language,
            ),
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 12,
              color: _textDim,
            ),
          ),
        ],
      ),
    );
  }

  void _showAddAchatDialog() {
    final formKey = GlobalKey<FormState>();
    final invoiceCtrl = TextEditingController();

    int? selectedSupplierId;
    String? selectedSupplierName;
    List<Map<String, dynamic>> suppliers = [];

    int? selectedLocationId;
    String? selectedLocationName;
    List<Map<String, dynamic>> locations = [];

    bool isLoaded = false;
    bool invoiceGenerated = false;
    DateTime selectedDate = DateTime.now();

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          if (!isLoaded) {
            final isWs = _effectiveIsWorkshop;
            final settings = Provider.of<AppSettingsProvider>(
              context,
              listen: false,
            );
            Future.wait([
              widget.db.readSuppliers(),
              isWs
                  ? widget.db.readWorkshopLocations()
                  : widget.db.readStoreLocations(),
              widget.db.getNextAchatInvoiceNumber(),
            ]).then((results) {
              if (mounted) {
                setDialogState(() {
                  suppliers = results[0] as List<Map<String, dynamic>>;
                  if (suppliers.isNotEmpty) {
                    selectedSupplierId = suppliers.first['id'];
                    selectedSupplierName = suppliers.first['name'];
                  }

                  locations = results[1] as List<Map<String, dynamic>>;
                  if (locations.isNotEmpty) {
                    final defaultLocId = isWs
                        ? settings.defaultWorkshopLocationId
                        : settings.defaultStoreLocationId;
                    final match = locations.firstWhere(
                      (l) => l['id'] == defaultLocId,
                      orElse: () => locations.first,
                    );
                    selectedLocationId = match['id'];
                    selectedLocationName = match['name'];
                  }

                  invoiceCtrl.text = results[2] as String;
                  invoiceGenerated = true;
                  isLoaded = true;
                });
              }
            });
            isLoaded = true; // Set true immediately to prevent duplicate calls
          }

          final lang = Provider.of<AppSettingsProvider>(context).language;
          return Directionality(
            textDirection: TextDirection.rtl,
            child: AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
              title: Text(
                Localization.translate('تسجيل فاتورة مشتريات جديدة', lang),
                style: const TextStyle(
                  fontFamily: 'Cairo',
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              content: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560, minWidth: 420),
                child: SingleChildScrollView(
                  child: Form(
                    key: formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextFormField(
                          controller: invoiceCtrl,
                          decoration: InputDecoration(
                            labelText: Localization.translate(
                              'رقم الفاتورة *',
                              lang,
                            ),
                            helperText: invoiceGenerated
                                ? Localization.translate(
                                    'يتم إنشاؤه تلقائياً ويمكنك تعديله',
                                    lang,
                                  )
                                : Localization.translate(
                                    'جارٍ توليد رقم الفاتورة...',
                                    lang,
                                  ),
                            labelStyle: const TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 13,
                            ),
                            prefixIcon: const Icon(Icons.receipt_long_rounded),
                            border: const OutlineInputBorder(),
                          ),
                          validator: (value) =>
                              (value == null || value.trim().isEmpty)
                              ? Localization.translate(
                                  'يرجى إدخال رقم الفاتورة',
                                  lang,
                                )
                              : null,
                        ),
                        const SizedBox(height: 12),
                        Builder(
                          builder: (dateContext) {
                            final canChangeDate =
                                Provider.of<AppSettingsProvider>(
                                  dateContext,
                                  listen: false,
                                ).canChangePurchaseDates();
                            return InkWell(
                              onTap: canChangeDate
                                  ? () async {
                                      final picked = await showDatePicker(
                                        context: dateContext,
                                        initialDate: selectedDate,
                                        firstDate: DateTime(2020),
                                        lastDate: DateTime(2030),
                                      );
                                      if (picked != null) {
                                        setDialogState(() {
                                          selectedDate = DateTime(
                                            picked.year,
                                            picked.month,
                                            picked.day,
                                            selectedDate.hour,
                                            selectedDate.minute,
                                          );
                                        });
                                      }
                                    }
                                  : null,
                              child: InputDecorator(
                                decoration: InputDecoration(
                                  labelText: Localization.translate(
                                    'تاريخ المشتريات',
                                    lang,
                                  ),
                                  prefixIcon: const Icon(Icons.calendar_today),
                                  suffixIcon: Icon(
                                    canChangeDate
                                        ? Icons.edit_calendar_outlined
                                        : Icons.lock_outline,
                                    color: canChangeDate ? _blue : _textDim,
                                  ),
                                  border: const OutlineInputBorder(),
                                ),
                                child: Text(
                                  DateFormat('dd/MM/yyyy').format(selectedDate),
                                  style: TextStyle(
                                    color: canChangeDate ? _text : _textDim,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 12),
                        suppliers.isEmpty
                            ? Text(
                                Localization.translate(
                                  'لا يوجد موردين مسجلين، يرجى إضافة مورد أولاً من صفحة إدارة الموردين.',
                                  lang,
                                ),
                                style: const TextStyle(
                                  color: Colors.red,
                                  fontSize: 12,
                                ),
                              )
                            : DropdownButtonFormField<int>(
                                isExpanded: true,
                                initialValue: selectedSupplierId,
                                decoration: InputDecoration(
                                  labelText: Localization.translate(
                                    'المورد *',
                                    lang,
                                  ),
                                  prefixIcon: const Icon(
                                    Icons.business_rounded,
                                  ),
                                  border: const OutlineInputBorder(),
                                ),
                                items: suppliers.map((s) {
                                  return DropdownMenuItem<int>(
                                    value: s['id'],
                                    child: Text(
                                      s['name'],
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  );
                                }).toList(),
                                onChanged: (val) {
                                  setDialogState(() {
                                    selectedSupplierId = val;
                                    selectedSupplierName = suppliers.firstWhere(
                                      (s) => s['id'] == val,
                                    )['name'];
                                  });
                                },
                                validator: (value) => value == null
                                    ? Localization.translate('اختر مورد', lang)
                                    : null,
                              ),
                        const SizedBox(height: 12),
                        locations.isEmpty
                            ? Text(
                                Localization.translate(
                                  'لا توجد مستودعات مسجلة.',
                                  lang,
                                ),
                                style: const TextStyle(
                                  color: Colors.red,
                                  fontSize: 12,
                                ),
                              )
                            : DropdownButtonFormField<int>(
                                isExpanded: true,
                                initialValue: selectedLocationId,
                                decoration: InputDecoration(
                                  labelText: Localization.translate(
                                    'مكان التخزين (المستودع) *',
                                    lang,
                                  ),
                                  prefixIcon: const Icon(
                                    Icons.storefront_rounded,
                                  ),
                                  border: const OutlineInputBorder(),
                                ),
                                items: locations.map((loc) {
                                  final rawName = loc['name']?.toString() ?? '';
                                  final displayName = (rawName == 'المستودع الرئيسي' || rawName.trim().isEmpty)
                                      ? Localization.translate('المستودع الرئيسي', lang)
                                      : rawName;
                                  return DropdownMenuItem<int>(
                                    value: loc['id'],
                                    child: Text(
                                      displayName,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  );
                                }).toList(),
                                onChanged: (val) {
                                  setDialogState(() {
                                    selectedLocationId = val;
                                    selectedLocationName = locations.firstWhere(
                                      (l) => l['id'] == val,
                                    )['name'];
                                  });
                                },
                                validator: (value) => value == null
                                    ? Localization.translate(
                                        'اختر مكان التخزين',
                                        lang,
                                      )
                                    : null,
                              ),
                      ],
                    ),
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(
                    Localization.translate('إلغاء', lang),
                    style: TextStyle(fontFamily: 'Cairo', color: _textDim),
                  ),
                ),
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _blue,
                    side: BorderSide(color: _blue),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onPressed: () async {
                    if (!formKey.currentState!.validate()) return;
                    if (selectedSupplierId == null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            Localization.translate(
                              'الرجاء اختيار المورد',
                              lang,
                            ),
                          ),
                        ),
                      );
                      return;
                    }
                    if (selectedLocationId == null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            Localization.translate(
                              'الرجاء اختيار مكان التخزين',
                              lang,
                            ),
                          ),
                        ),
                      );
                      return;
                    }

                    try {
                      final newAchatId = await widget.db.insertAchat(
                        invoiceCtrl.text.trim(),
                        selectedSupplierName ?? 'Unknown',
                        0.0,
                        supplierId: selectedSupplierId,
                        locationId: selectedLocationId,
                        createdAt: selectedDate.toIso8601String(),
                        isWorkshop: _effectiveIsWorkshop,
                        activityType: _effectiveIsWorkshop
                            ? 'workshop'
                            : 'store',
                      );

                      _refreshList();
                      if (!context.mounted) return;
                      Navigator.pop(context);
                      _openAchatDetails(
                        achatId: newAchatId,
                        invoiceNumber: invoiceCtrl.text.trim(),
                        supplierName: selectedSupplierName!,
                      );
                    } catch (e) {
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            '${Localization.translate('حدث خطأ أثناء الحفظ: ', lang)}$e',
                          ),
                        ),
                      );
                    }
                  },
                  child: Text(
                    Localization.translate('حفظ وتسجيل', lang),
                    style: const TextStyle(fontFamily: 'Cairo'),
                  ),
                ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF10B981),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  icon: const Icon(Icons.add_shopping_cart_rounded, size: 18),
                  label: Text(
                    Localization.translate('حفظ وإضافة عناصر', lang),
                    style: const TextStyle(
                      fontFamily: 'Cairo',
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  onPressed: () async {
                    if (!formKey.currentState!.validate()) return;
                    if (selectedSupplierId == null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            Localization.translate(
                              'الرجاء اختيار المورد',
                              lang,
                            ),
                          ),
                        ),
                      );
                      return;
                    }
                    if (selectedLocationId == null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            Localization.translate(
                              'الرجاء اختيار مكان التخزين',
                              lang,
                            ),
                          ),
                        ),
                      );
                      return;
                    }

                    try {
                      final newAchatId = await widget.db.insertAchat(
                        invoiceCtrl.text.trim(),
                        selectedSupplierName ?? 'Unknown',
                        0.0,
                        supplierId: selectedSupplierId,
                        locationId: selectedLocationId,
                        createdAt: selectedDate.toIso8601String(),
                        isWorkshop: _effectiveIsWorkshop,
                        activityType: _effectiveIsWorkshop
                            ? 'workshop'
                            : 'store',
                      );

                      _refreshList();
                      if (!context.mounted) return;
                      Navigator.pop(context);
                      _openAchatDetails(
                        achatId: newAchatId,
                        invoiceNumber: invoiceCtrl.text.trim(),
                        supplierName: selectedSupplierName!,
                        autoOpenPicker: true,
                      );
                    } catch (e) {
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            '${Localization.translate('حدث خطأ أثناء الحفظ: ', lang)}$e',
                          ),
                        ),
                      );
                    }
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // ── Confirm Delete Achat ───────────────────────────────────────────────────
  void _confirmDeleteAchat(int id, String invoiceNumber) {
    showDialog(
      context: context,
      builder: (context) {
        final lang = Provider.of<AppSettingsProvider>(context).language;
        return Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: Row(
              children: [
                const Icon(Icons.delete_outline_rounded, color: Colors.red),
                const SizedBox(width: 8),
                Text(
                  Localization.translate('نقل الفاتورة إلى سلة المهملات', lang),
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: _red,
                  ),
                ),
              ],
            ),
            content: Text(
              "${Localization.translate('هل أنت متأكد من رغبتك في نقل الفاتورة رقم: ', lang)}$invoiceNumber${Localization.translate(' إلى سلة المهملات؟ يمكنك استرجاعها لاحقاً من سلة المهملات.', lang)}",
              style: const TextStyle(
                fontFamily: 'Cairo',
                fontSize: 13,
                height: 1.5,
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(
                  Localization.translate(
                    'تراجع',
                    Provider.of<AppSettingsProvider>(context).language,
                  ),
                  style: TextStyle(fontFamily: 'Cairo', color: _textDim),
                ),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _red,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                onPressed: () async {
                  Navigator.pop(context);
                  await widget.db.deleteAchatToTrash(id);
                  _refreshList();
                  if (mounted) {
                    ScaffoldMessenger.of(context).hideCurrentSnackBar();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          Localization.translate(
                            'تم نقل الفاتورة إلى سلة المهملات',
                            Provider.of<AppSettingsProvider>(
                              context,
                              listen: false,
                            ).language,
                          ),
                          style: const TextStyle(fontFamily: 'Cairo'),
                        ),
                        duration: const Duration(milliseconds: 2500),
                        showCloseIcon: true,
                        closeIconColor: Colors.white70,
                        dismissDirection: DismissDirection.horizontal,
                        // An action keeps a SnackBar open until it is dismissed.
                        persist: false,
                        action: SnackBarAction(
                          label: Localization.translate('استرجاع', lang),
                          textColor: Colors.amberAccent,
                          onPressed: () async {
                            ScaffoldMessenger.of(context).hideCurrentSnackBar();
                            await widget.db.restoreAchat(id);
                            _refreshList();
                          },
                        ),
                        backgroundColor: Colors.black87,
                        behavior: SnackBarBehavior.floating,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    );
                  }
                },
                child: Text(
                  Localization.translate(
                    'نقل إلى السلة',
                    Provider.of<AppSettingsProvider>(context).language,
                  ),
                  style: const TextStyle(
                    fontFamily: 'Cairo',
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
