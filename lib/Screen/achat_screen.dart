import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:database_data/settings/localization.dart';
import '../sql_database.dart';
import 'achat_details_screen.dart';
import 'achat_return_screen.dart';
import 'ai_scanner_screen.dart';
import 'package:database_data/settings/app_settings.dart';
import 'package:provider/provider.dart';

class AchatScreen extends StatefulWidget {
  final SqlDatabase db;
  /// وضع العرض فقط — يخفي FAB وأزرار التعديل/الحذف
  final bool readOnly;

  const AchatScreen({super.key, required this.db, this.readOnly = false});

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

  // ── Palette ───────────────────────────────────────────────────────────────
  static const _blue = Color(0xFF2563EB);
  static const _blueLight = Color(0xFF3B82F6);
  static const _cyan = Color(0xFF0EA5E9);
  Color get _cardBg => Theme.of(context).cardColor;
  Color get _bg => Theme.of(context).scaffoldBackgroundColor;
  static const _green = Color(0xFF10B981);
  static const _red = Color(0xFFEF4444);
  static const _orange = Color(0xFFF59E0B);
  Color get _text => Theme.of(context).colorScheme.onSurface;
  Color get _textDim => Theme.of(context).colorScheme.onSurface.withOpacity(0.7);
  Color get _divider => Theme.of(context).dividerColor;

  @override
  void initState() {
    super.initState();
    _refreshList();
  }

  void _refreshList() {
    setState(() {
      _achatsFuture = widget.db.readAchats();
      _expandedAchatId = null;
    });
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
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: _bg,
        body: CustomScrollView(
          slivers: [
            _buildAppBar(),
            SliverToBoxAdapter(
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

                        // ── فلاتر الحالة ──
                        _buildFilterChips(),
                        SizedBox(height: 16),

                        // ── قائمة فواتير المشتريات ──
                        filteredData.isEmpty
                            ? _buildEmptyState()
                            : ListView.builder(
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
          ],
        ),
        floatingActionButton:
            (!widget.readOnly && Provider.of<AppSettingsProvider>(context).canAddPurchases())
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
      ),
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
      leading: Navigator.canPop(context)
          ? IconButton(
              icon: Icon(Icons.arrow_back_ios_rounded),
              onPressed: () => Navigator.pop(context),
            )
          : null,
      actions: [
        IconButton(
          icon: Icon(Icons.document_scanner_rounded),
          tooltip: 'مسح الفاتورة بالذكاء الاصطناعي',
          onPressed: _openAiScanner,
        ),
        SizedBox(width: 8),
      ],
      flexibleSpace: FlexibleSpaceBar(
        background: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: Theme.of(context).brightness == Brightness.dark ? [Color(0xFF111827), Color(0xFF070E1D)] : [_blue, _cyan], begin: Alignment.topLeft,
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
        title: Text(
          Localization.translate(
            'إدارة المشتريات (Achat)',
            Provider.of<AppSettingsProvider>(context).language,
          ),
          style: TextStyle(
            fontFamily: 'Cairo',
            fontWeight: FontWeight.bold,
            fontSize: 18,
            color: Colors.white,
          ),
        ),
        titlePadding: EdgeInsets.only(right: 56, bottom: 16),
        centerTitle: false,
      ),
    );
  }

  // ── Stats Row ──────────────────────────────────────────────────────────────
  Widget _buildStatsRow(Map<String, dynamic> stats) {
    final lang = Provider.of<AppSettingsProvider>(context, listen: false).language;
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
    final lang = Provider.of<AppSettingsProvider>(context, listen: false).language;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          Localization.translate(
            'فواتير الشراء المستوردة',
            lang,
          ),
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
              hintText: Localization.translate('البحث برقم الفاتورة أو اسم المورد...', lang),
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
    final lang = Provider.of<AppSettingsProvider>(context, listen: false).language;
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
    String statusLabel = 'نشطة';

    if (isCancelled) {
      statusColor = _red;
      statusLabel = 'ملغاة';
    } else if (isReturned) {
      statusColor = Colors.purple;
      statusLabel = 'مردودة كلياً';
    } else if (isPartialReturned) {
      statusColor = Colors.deepOrange;
      statusLabel = 'مردودة جزئياً';
    } else if (isPaid) {
      statusColor = _green;
      statusLabel = 'مؤكدة / مدفوعة';
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
          onTap: () async {
            // Navigator to AchatDetailsScreen
            await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => AchatDetailsScreen(
                  achatId: id,
                  invoiceNumber: invoiceNumber,
                  supplierName: supplierName,
                ),
              ),
            );
            _refreshList(); // Reload stats after returning
          },
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
                        if (!widget.readOnly && Provider.of<AppSettingsProvider>(
                          context,
                          listen: false,
                        ).canEditPurchases())
                          TextButton.icon(
                            style: TextButton.styleFrom(foregroundColor: _blue),
                            onPressed: () async {
                              await Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => AchatDetailsScreen(
                                    achatId: id,
                                    invoiceNumber: invoiceNumber,
                                    supplierName: supplierName,
                                  ),
                                ),
                              );
                              _refreshList();
                            },
                            icon: const Icon(Icons.edit, size: 18),
                            label: Text(
                              Localization.translate('تعديل', lang),
                              style: const TextStyle(fontFamily: 'Cairo'),
                            ),
                          ),
                        const SizedBox(width: 8),
                        if (!widget.readOnly && Provider.of<AppSettingsProvider>(
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
    final lang = Provider.of<AppSettingsProvider>(context, listen: false).language;
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

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          if (!isLoaded) {
            Future.wait([
              widget.db.readSuppliers(),
              widget.db.readLocations(),
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
                    selectedLocationId = locations.first['id'];
                    selectedLocationName = locations.first['name'];
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
                Localization.translate(
                  'تسجيل فاتورة مشتريات جديدة',
                  lang,
                ),
                style: const TextStyle(
                  fontFamily: 'Cairo',
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              content: SingleChildScrollView(
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextFormField(
                        controller: invoiceCtrl,
                        decoration: InputDecoration(
                          labelText: Localization.translate('رقم الفاتورة *', lang),
                          helperText: invoiceGenerated
                              ? Localization.translate('يتم إنشاؤه تلقائياً ويمكنك تعديله', lang)
                              : Localization.translate('جارٍ توليد رقم الفاتورة...', lang),
                          labelStyle: const TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 13,
                          ),
                          prefixIcon: const Icon(Icons.receipt_long_rounded),
                          border: const OutlineInputBorder(),
                        ),
                        validator: (value) =>
                            (value == null || value.trim().isEmpty)
                            ? Localization.translate('يرجى إدخال رقم الفاتورة', lang)
                            : null,
                      ),
                      const SizedBox(height: 12),
                      suppliers.isEmpty
                          ? Text(
                              Localization.translate('لا يوجد موردين مسجلين، يرجى إضافة مورد أولاً من صفحة إدارة الموردين.', lang),
                              style: const TextStyle(color: Colors.red, fontSize: 12),
                            )
                          : DropdownButtonFormField<int>(
                              isExpanded: true,
                              // 🟢 منع الأوفر فلو لأسماء الموردين الطويلة
                              initialValue: selectedSupplierId,
                              decoration: InputDecoration(
                                labelText: Localization.translate('المورد *', lang),
                                prefixIcon: const Icon(Icons.business_rounded),
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
                              validator: (value) =>
                                  value == null ? Localization.translate('اختر مورد', lang) : null,
                            ),
                      const SizedBox(height: 12),
                      locations.isEmpty
                          ? Text(
                              Localization.translate('لا توجد مستودعات مسجلة.', lang),
                              style: const TextStyle(color: Colors.red, fontSize: 12),
                            )
                          : DropdownButtonFormField<int>(
                              isExpanded: true,
                              initialValue: selectedLocationId,
                              decoration: InputDecoration(
                                labelText: Localization.translate('مكان التخزين (المستودع) *', lang),
                                prefixIcon: const Icon(Icons.storefront_rounded),
                                border: const OutlineInputBorder(),
                              ),
                              items: locations.map((loc) {
                                return DropdownMenuItem<int>(
                                  value: loc['id'],
                                  child: Text(
                                    loc['name'],
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
                              validator: (value) =>
                                  value == null ? Localization.translate('اختر مكان التخزين', lang) : null,
                            ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(
                    Localization.translate(
                      'إلغاء',
                      lang,
                    ),
                    style: TextStyle(fontFamily: 'Cairo', color: _textDim),
                  ),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _blue,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onPressed: () async {
                    if (!formKey.currentState!.validate()) return;
                    if (selectedSupplierId == null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(Localization.translate('الرجاء اختيار المورد', lang))),
                      );
                      return;
                    }
                    if (selectedLocationId == null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(Localization.translate('الرجاء اختيار مكان التخزين', lang)),
                        ),
                      );
                      return;
                    }

                    try {
                      final newAchatId = await widget.db.insertAchat(
                        invoiceCtrl.text.trim(),
                        selectedSupplierName ?? 'Unknown',
                        0.0, // Initial total is 0 until items are added
                        supplierId: selectedSupplierId,
                        locationId: selectedLocationId,
                      );

                      _refreshList();
                      if (!context.mounted) return;
                      Navigator.pop(context);
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => AchatDetailsScreen(
                            achatId: newAchatId,
                            invoiceNumber: invoiceCtrl.text.trim(),
                            supplierName: selectedSupplierName!,
                          ),
                        ),
                      );
                      _refreshList();
                    } catch (e) {
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('${Localization.translate('حدث خطأ أثناء الحفظ: ', lang)}$e')),
                      );
                    }
                  },
                  child: Text(
                    Localization.translate(
                      'حفظ وتسجيل',
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
            title: Text(
              Localization.translate(
                'حذف نهائي للفاتورة',
                lang,
              ),
              style: TextStyle(
                fontFamily: 'Cairo',
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: _red,
              ),
            ),
            content: Text(
              "${Localization.translate('هل أنت متأكد من رغبتك في حذف الفاتورة رقم: ', lang)}$invoiceNumber${Localization.translate(' نهائياً من قاعدة البيانات؟ لا يمكن التراجع عن هذا الإجراء.', lang)}",
              style: const TextStyle(fontFamily: 'Cairo', fontSize: 13, height: 1.5),
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
                await widget.db.deleteAchat(id);
                _refreshList();
                if (context.mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        Localization.translate(
                          'تم حذف الفاتورة نهائياً',
                          Provider.of<AppSettingsProvider>(context).language,
                        ),
                        style: TextStyle(fontFamily: 'Cairo'),
                      ),
                      backgroundColor: Colors.black87,
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              },
              child: Text(
                Localization.translate(
                  'حذف نهائي',
                  Provider.of<AppSettingsProvider>(context).language,
                ),
                style: TextStyle(fontFamily: 'Cairo', color: Colors.white),
              ),
            ),
          ],
        ),
      );
    },
  );
}
}
