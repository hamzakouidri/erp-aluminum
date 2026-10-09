import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../settings/app_settings.dart';
import '../settings/localization.dart';
import '../sql_database.dart';

class UnifiedFinancialReportScreen extends StatefulWidget {
  final SqlDatabase db;

  const UnifiedFinancialReportScreen({super.key, required this.db});

  @override
  State<UnifiedFinancialReportScreen> createState() =>
      _UnifiedFinancialReportScreenState();
}

class _UnifiedFinancialReportScreenState
    extends State<UnifiedFinancialReportScreen> {
  bool _isLoading = true;
  Map<String, dynamic> _data = {};

  DateTime? _startDate;
  DateTime? _endDate;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final startStr = _startDate != null
        ? DateFormat('yyyy-MM-dd').format(_startDate!)
        : null;
    final endStr = _endDate != null
        ? DateFormat('yyyy-MM-dd').format(_endDate!.add(const Duration(days: 1)))
        : null;

    final result = await widget.db.getEnterpriseUnifiedFinancialSummary(
      startDate: startStr,
      endDate: endStr,
    );
    if (mounted) {
      setState(() {
        _data = result;
        _isLoading = false;
      });
    }
  }

  String _t(String key) => Localization.translate(
        key,
        Provider.of<AppSettingsProvider>(context, listen: false).language,
      );

  String _fmt(dynamic value) {
    final numVal = (value as num?)?.toDouble() ?? 0.0;
    return NumberFormat('#,##0.00').format(numVal);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = Theme.of(context).scaffoldBackgroundColor;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        title: Text(
          _t('التقرير المالي الموحد للمؤسسة'),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.date_range_rounded),
            tooltip: _t('تحديد الفترة'),
            onPressed: _pickDateRange,
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loadData,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadData,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (_startDate != null || _endDate != null)
                    _buildActiveFilterChip(),

                  // 1. Consolidated Enterprise Summary (الأداء المجمع المستبعد منه الهامش الداخلي)
                  _buildConsolidatedCard(isDark),
                  const SizedBox(height: 16),

                  // 2. Materials Store Activity Result
                  _buildStoreCard(isDark),
                  const SizedBox(height: 16),

                  // 3. Workshop Manufacturing Activity Result
                  _buildWorkshopCard(isDark),
                  const SizedBox(height: 24),
                ],
              ),
            ),
    );
  }

  Widget _buildActiveFilterChip() {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.blue.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            '${_startDate != null ? DateFormat('yyyy-MM-dd').format(_startDate!) : '...'}  →  ${_endDate != null ? DateFormat('yyyy-MM-dd').format(_endDate!) : '...'}',
            style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue),
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded, size: 18),
            onPressed: () {
              setState(() {
                _startDate = null;
                _endDate = null;
              });
              _loadData();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildConsolidatedCard(bool isDark) {
    final revenue = _data['consolidated_revenue'] ?? 0.0;
    final collected = _data['consolidated_cash_collected'] ?? 0.0;
    final purchases = _data['consolidated_external_purchases'] ?? 0.0;
    final netCash = _data['consolidated_net_cash_flow'] ?? 0.0;
    final eliminated = _data['eliminated_internal_margin'] ?? 0.0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDark
              ? [const Color(0xFF1E293B), const Color(0xFF0F172A)]
              : [const Color(0xFF1E3A8A), const Color(0xFF2563EB)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.account_balance_rounded, color: Colors.amber, size: 24),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _t('النتيجة المجمعة للمؤسسة (بدون تحويلات داخلية)'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _metricBox(
                  _t('إجمالي إيراد المؤسسة الخارجي'),
                  _fmt(revenue),
                  Colors.white,
                  Colors.white70,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _metricBox(
                  _t('التحصيل الفعلي (نقدًا)'),
                  _fmt(collected),
                  Colors.lightGreenAccent,
                  Colors.white70,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _metricBox(
                  _t('مشتريات خارجية فعلية'),
                  _fmt(purchases),
                  Colors.orangeAccent,
                  Colors.white70,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _metricBox(
                  _t('صافي السيولة المجمعة'),
                  _fmt(netCash),
                  netCash >= 0 ? Colors.greenAccent : Colors.redAccent,
                  Colors.white70,
                ),
              ),
            ],
          ),
          if (eliminated > 0) ...[
            const Divider(color: Colors.white24, height: 24),
            Row(
              children: [
                const Icon(Icons.info_outline_rounded, color: Colors.amber, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${_t('تم استبعاد تحويلات داخلية بقيمة')}: ${_fmt(eliminated)} ${_t('دج')} ${_t('منعاً لاحتساب أرباح وهمية قبل البيع للزبون النهائي.')}',
                    style: const TextStyle(color: Colors.white70, fontSize: 11),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStoreCard(bool isDark) {
    final sales = _data['store_external_sales'] ?? 0.0;
    final paid = _data['store_external_paid'] ?? 0.0;
    final unpaid = _data['store_external_unpaid'] ?? 0.0;
    final transfers = _data['store_internal_transfers'] ?? 0.0;
    final purchases = _data['store_purchases'] ?? 0.0;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.storefront_rounded, color: Colors.deepOrange),
                ),
                const SizedBox(width: 10),
                Text(
                  _t('نشاط محل بيع المواد المستقل'),
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _summaryRow(_t('مبيعات الزبائن الخارجيين'), _fmt(sales), Colors.blue),
            _summaryRow(_t('المدفوع من الزبائن'), _fmt(paid), Colors.green),
            _summaryRow(_t('ديون الزبائن للمحل'), _fmt(unpaid), Colors.orange),
            _summaryRow(_t('مشتريات المحل من الموردين'), _fmt(purchases), Colors.redAccent),
            const Divider(),
            _summaryRow(_t('تحويلات داخلية للورشة (بسعر التحويل)'), _fmt(transfers), Colors.purple, isBold: true),
          ],
        ),
      ),
    );
  }

  Widget _buildWorkshopCard(bool isDark) {
    final revenue = _data['workshop_orders_revenue'] ?? 0.0;
    final advances = _data['workshop_orders_advances'] ?? 0.0;
    final unpaid = _data['workshop_orders_unpaid'] ?? 0.0;
    final extPurchases = _data['workshop_external_purchases'] ?? 0.0;
    final intPurchases = _data['workshop_internal_purchases'] ?? 0.0;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.blue.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.precision_manufacturing_rounded, color: Colors.blue),
                ),
                const SizedBox(width: 10),
                Text(
                  _t('نشاط ورشة النجارة والتصنيع'),
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _summaryRow(_t('إجمالي قيمة طلبيات النوافذ'), _fmt(revenue), Colors.blue),
            _summaryRow(_t('المقبوضات والعربونات من العملاء'), _fmt(advances), Colors.green),
            _summaryRow(_t('المتبقي بذمة عملاء الطلبيات'), _fmt(unpaid), Colors.orange),
            _summaryRow(_t('مشتريات الورشة المباشرة من الموردين'), _fmt(extPurchases), Colors.redAccent),
            const Divider(),
            _summaryRow(_t('استلام مواد داخلي من المحل'), _fmt(intPurchases), Colors.purple, isBold: true),
          ],
        ),
      ),
    );
  }

  Widget _metricBox(String title, String val, Color valColor, Color titleColor) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(color: titleColor, fontSize: 11)),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              val,
              style: TextStyle(
                color: valColor,
                fontSize: 17,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryRow(String label, String val, Color color, {bool isBold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          Text(
            '$val ${_t('دج')}',
            style: TextStyle(
              fontSize: 14,
              fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
      initialDateRange: _startDate != null && _endDate != null
          ? DateTimeRange(start: _startDate!, end: _endDate!)
          : null,
    );
    if (picked != null) {
      setState(() {
        _startDate = picked.start;
        _endDate = picked.end;
      });
      _loadData();
    }
  }
}
