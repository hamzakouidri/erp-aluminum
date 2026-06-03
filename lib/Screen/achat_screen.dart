import 'package:flutter/material.dart';
import 'package:database_data/sql_database.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'ai_scanner_screen.dart';
import 'package:database_data/settings/localization.dart';
import 'package:database_data/settings/app_settings.dart';
import 'package:provider/provider.dart';

class AchatScreen extends StatefulWidget {
  final SqlDatabase db;

  const AchatScreen({super.key, required this.db});

  @override
  State<AchatScreen> createState() => _AchatScreenState();
}

class _AchatScreenState extends State<AchatScreen>
    with SingleTickerProviderStateMixin {
  late Future<List<Map<String, dynamic>>> _achatsFuture;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  int? _expandedAchatId;

  // ── Palette ───────────────────────────────────────────────────────────────
  static const _blue = Color(0xFF2563EB);
  static const _blueLight = Color(0xFF3B82F6);
  static const _cyan = Color(0xFF0EA5E9);
  static const _cardBg = Colors.white;
  static const _bg = Color(0xFFF8FAFC);
  static const _green = Color(0xFF10B981);
  static const _red = Color(0xFFEF4444);
  static const _text = Color(0xFF1E293B);
  static const _textDim = Color(0xFF64748B);
  static const _divider = Color(0xFFE2E8F0);

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

  // حساب الإحصائيات بناءً على البيانات المسترجعة
  Map<String, dynamic> _calculateStats(List<Map<String, dynamic>> data) {
    double totalActive = 0.0;
    int activeCount = 0;
    int cancelledCount = 0;

    for (var row in data) {
      final status = row['status'] ?? 'Active';
      final total = (row['total'] as num?)?.toDouble() ?? 0.0;

      if (status == 'Active') {
        totalActive += total;
        activeCount++;
      } else {
        cancelledCount++;
      }
    }

    return {
      'totalActive': totalActive,
      'activeCount': activeCount,
      'cancelledCount': cancelledCount,
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
                        child: Text('حدث خطأ: ${snapshot.error}',
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            color: _red,
                          ),
                        ),
                      ),
                    );
                  }

                  final allData = snapshot.data ?? [];
                  final stats = _calculateStats(allData);

                  // تطبيق فلتر البحث
                  final filteredData = allData.where((item) {
                    final supplier = (item['supplier_name'] ?? '')
                        .toString()
                        .toLowerCase();
                    final invoice = (item['invoice_number'] ?? '')
                        .toString()
                        .toLowerCase();
                    final query = _searchQuery.toLowerCase();
                    return supplier.contains(query) || invoice.contains(query);
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
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _showAddAchatDialog,
          backgroundColor: _blue,
          elevation: 4,
          icon: Icon(Icons.add_rounded, color: Colors.white),
          label: Text(Localization.translate('فاتورة جديدة', Provider.of<AppSettingsProvider>(context).language),
            style: TextStyle(
              fontFamily: 'Cairo',
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }

  // ── Sliver App Bar with Gradient ──────────────────────────────────────────
  Widget _buildAppBar() {
    return SliverAppBar(
      expandedHeight: 150.0,
      pinned: true,
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      leading: IconButton(
        icon: Icon(Icons.arrow_back_ios_rounded, color: Colors.white),
        onPressed: () => Navigator.pop(context),
      ),
      actions: [
        IconButton(
          icon: Icon(Icons.document_scanner_rounded, color: Colors.white),
          tooltip: 'مسح الفاتورة بالذكاء الاصطناعي',
          onPressed: _openAiScanner,
        ),
        SizedBox(width: 8),
      ],
      flexibleSpace: FlexibleSpaceBar(
        background: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [_blue, _cyan],
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
        title: Text(Localization.translate('إدارة المشتريات (Achat)', Provider.of<AppSettingsProvider>(context).language),
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
    final currencyFormat = NumberFormat('#,##0.00', 'en_US');
    return Row(
      children: [
        Expanded(
          flex: 5,
          child: _buildStatItem(
            icon: Icons.monetization_on_rounded,
            label: 'إجمالي المشتريات',
            value: '${currencyFormat.format(stats['totalActive'])} دج',
            color: _blueLight,
          ),
        ),
        SizedBox(width: 8),
        Expanded(
          flex: 3,
          child: _buildStatItem(
            icon: Icons.check_circle_rounded,
            label: 'نشط',
            value: stats['activeCount'].toString(),
            color: _green,
          ),
        ),
        SizedBox(width: 8),
        Expanded(
          flex: 3,
          child: _buildStatItem(
            icon: Icons.cancel_rounded,
            label: 'ملغى',
            value: stats['cancelledCount'].toString(),
            color: _red,
          ),
        ),
      ],
    );
  }

  Widget _buildStatItem({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: EdgeInsets.all(12),
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
          Text(
            value,
            style: TextStyle(
              fontFamily: 'Cairo',
              fontWeight: FontWeight.w800,
              fontSize: 14,
              color: _text,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            label,
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 9,
              color: _textDim,
            ),
          ),
        ],
      ),
    );
  }

  // ── Search & Section Title ──────────────────────────────────────────────────
  Widget _buildSearchAndTitle() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(Localization.translate('فواتير الشراء المستوردة', Provider.of<AppSettingsProvider>(context).language),
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
              hintText: 'البحث برقم الفاتورة أو اسم المورد...',
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
    final id = item['id'] as int;
    final invoiceNumber = item['invoice_number'] ?? '';
    final supplierName = item['supplier_name'] ?? '';
    final status = item['status'] ?? 'Active';
    final total = (item['total'] as num?)?.toDouble() ?? 0.0;
    final createdAt = item['created_at'] ?? '';

    final isActive = status == 'Active';
    final currencyFormat = NumberFormat('#,##0.00', 'en_US');
    final isExpanded = _expandedAchatId == id;

    return Container(
      margin: EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isActive
              ? (isExpanded ? _blue : _divider)
              : _red.withValues(alpha: 0.2),
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
          onTap: () {
            setState(() {
              _expandedAchatId = isExpanded ? null : id;
            });
          },
          child: Container(
            decoration: BoxDecoration(
              border: Border(
                right: BorderSide(color: isActive ? _blue : _red, width: 6),
              ),
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
                            Text('فاتورة رقم: $invoiceNumber',
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
                          color: (isActive ? _green : _red).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          isActive ? 'نشط' : 'ملغى',
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            fontWeight: FontWeight.bold,
                            fontSize: 10,
                            color: isActive ? _green : _red,
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
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(Localization.translate('القيمة الإجمالية', Provider.of<AppSettingsProvider>(context).language),
                            style: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 11,
                              color: _textDim,
                            ),
                          ),
                          Text('${currencyFormat.format(total)} دج',
                            style: TextStyle(
                              fontFamily: 'Cairo',
                              fontWeight: FontWeight.w900,
                              fontSize: 16,
                              color: isActive ? _text : _textDim,
                              decoration: isActive
                                  ? null
                                  : TextDecoration.lineThrough,
                            ),
                          ),
                        ],
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(Localization.translate('تاريخ التسجيل', Provider.of<AppSettingsProvider>(context).language),
                            style: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 11,
                              color: _textDim,
                            ),
                          ),
                          Text(
                            _formatDate(createdAt),
                            style: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 12,
                              color: _text,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  if (isExpanded) ...[_buildAchatItemsList(id)],
                  if (isActive) ...[
                    SizedBox(height: 12),
                    Divider(height: 1, color: _divider),
                    SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton.icon(
                          style: TextButton.styleFrom(
                            foregroundColor: _red,
                            padding: EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          onPressed: () =>
                              _confirmCancelAchat(id, invoiceNumber),
                          icon: Icon(Icons.cancel_outlined, size: 16),
                          label: Text(Localization.translate('إلغاء الشراء', Provider.of<AppSettingsProvider>(context).language),
                            style: TextStyle(
                              fontFamily: 'Cairo',
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        SizedBox(width: 8),
                        IconButton(
                          style: IconButton.styleFrom(
                            foregroundColor: _textDim,
                          ),
                          onPressed: () =>
                              _confirmDeleteAchat(id, invoiceNumber),
                          icon: Icon(
                            Icons.delete_outline_rounded,
                            size: 18,
                          ),
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
          Text(Localization.translate('لا توجد فواتير مشتريات مسجلة', Provider.of<AppSettingsProvider>(context).language),
            style: TextStyle(
              fontFamily: 'Cairo',
              fontWeight: FontWeight.bold,
              fontSize: 14,
              color: _text,
            ),
          ),
          SizedBox(height: 4),
          Text(Localization.translate('انقر على "فاتورة جديدة" لإضافة فاتورة واردة.', Provider.of<AppSettingsProvider>(context).language),
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

  // ── Add Achat Dialog ───────────────────────────────────────────────────────
  void _showAddAchatDialog() {
    final formKey = GlobalKey<FormState>();
    final invoiceCtrl = TextEditingController();
    final supplierCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          title: Text(Localization.translate('تسجيل فاتورة مشتريات جديدة', Provider.of<AppSettingsProvider>(context).language),
            style: TextStyle(
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
                      labelText: 'رقم الفاتورة *',
                      labelStyle: TextStyle(fontFamily: 'Cairo', fontSize: 13),
                      prefixIcon: Icon(Icons.receipt_long_rounded),
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) =>
                        (value == null || value.trim().isEmpty)
                        ? 'يرجى إدخال رقم الفاتورة'
                        : null,
                  ),
                  SizedBox(height: 12),
                  TextFormField(
                    controller: supplierCtrl,
                    decoration: InputDecoration(
                      labelText: 'اسم المورد *',
                      labelStyle: TextStyle(fontFamily: 'Cairo', fontSize: 13),
                      prefixIcon: Icon(Icons.business_rounded),
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) =>
                        (value == null || value.trim().isEmpty)
                        ? 'يرجى إدخال اسم المورد'
                        : null,
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(Localization.translate('إلغاء', Provider.of<AppSettingsProvider>(context).language),
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
                if (formKey.currentState!.validate()) {
                  await widget.db.insertAchat(
                    invoiceCtrl.text.trim(),
                    supplierCtrl.text.trim(),
                    0.0, // Initial total is 0 until items are added
                  );
                  _refreshList();
                  if (context.mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(Localization.translate('تم تسجيل الفاتورة بنجاح', Provider.of<AppSettingsProvider>(context).language),
                          style: TextStyle(fontFamily: 'Cairo'),
                        ),
                        backgroundColor: _green,
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  }
                }
              },
              child: Text(Localization.translate('حفظ وتسجيل', Provider.of<AppSettingsProvider>(context).language),
                style: TextStyle(fontFamily: 'Cairo', color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Confirm Cancel Achat ───────────────────────────────────────────────────
  void _confirmCancelAchat(int id, String invoiceNumber) {
    showDialog(
      context: context,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Text(Localization.translate('تأكيد إلغاء الشراء', Provider.of<AppSettingsProvider>(context).language),
            style: TextStyle(
              fontFamily: 'Cairo',
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          content: Text('هل أنت متأكد من رغبتك في إلغاء عملية الشراء للفاتورة رقم: $invoiceNumber؟ \nسيؤدي هذا إلى تجميد الفاتورة واستبعاد قيمتها من إجمالي الإحصائيات.',
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 13,
              height: 1.5,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(Localization.translate('تراجع', Provider.of<AppSettingsProvider>(context).language),
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
                await widget.db.updateAchatStatus(id, 'Cancelled');
                _refreshList();
                if (context.mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(Localization.translate('تم إلغاء فاتورة الشراء بنجاح', Provider.of<AppSettingsProvider>(context).language),
                        style: TextStyle(fontFamily: 'Cairo'),
                      ),
                      backgroundColor: _red,
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              },
              child: Text(Localization.translate('تأكيد الإلغاء', Provider.of<AppSettingsProvider>(context).language),
                style: TextStyle(fontFamily: 'Cairo', color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Confirm Delete Achat ───────────────────────────────────────────────────
  void _confirmDeleteAchat(int id, String invoiceNumber) {
    showDialog(
      context: context,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Text(Localization.translate('حذف نهائي للفاتورة', Provider.of<AppSettingsProvider>(context).language),
            style: TextStyle(
              fontFamily: 'Cairo',
              fontWeight: FontWeight.bold,
              fontSize: 16,
              color: _red,
            ),
          ),
          content: Text('هل أنت متأكد من رغبتك في حذف الفاتورة رقم: $invoiceNumber نهائياً من قاعدة البيانات؟ لا يمكن التراجع عن هذا الإجراء.',
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 13,
              height: 1.5,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(Localization.translate('تراجع', Provider.of<AppSettingsProvider>(context).language),
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
                      content: Text(Localization.translate('تم حذف الفاتورة نهائياً', Provider.of<AppSettingsProvider>(context).language),
                        style: TextStyle(fontFamily: 'Cairo'),
                      ),
                      backgroundColor: Colors.black87,
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              },
              child: Text(Localization.translate('حذف نهائي', Provider.of<AppSettingsProvider>(context).language),
                style: TextStyle(fontFamily: 'Cairo', color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── بناء قائمة عناصر الفاتورة عند توسيع الكارد ────────────────────────────
  Widget _buildAchatItemsList(int achatId) {
    // هذه الدالة ستعرض تفاصيل إضافية للفاتورة إذا كانت موجودة،
    // أو يمكنك تخصيصها لجلب العناصر من جدول آخر في قاعدة البيانات
    return Container(
      margin: EdgeInsets.only(top: 12),
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _divider),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(Localization.translate('المواد:', Provider.of<AppSettingsProvider>(context).language),
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 12,
                  color: _textDim,
                ),
              ),
              Text(Localization.translate('لا توجد تفاصيل إضافية', Provider.of<AppSettingsProvider>(context).language),
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 12,
                  color: _text,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
