import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../Commande/Systeme/consumption_manager.dart';
import '../sql_database.dart';
import '../settings/app_settings.dart';
import '../settings/localization.dart';

/// Modal dialog providing comprehensive job costing, bill-of-materials cost breakdown,
/// and net profit margin analysis for an order.
class OrderProfitabilityDialog extends StatefulWidget {
  final Map<String, dynamic> orderData;
  final SqlDatabase db;

  const OrderProfitabilityDialog({
    super.key,
    required this.orderData,
    required this.db,
  });

  static Future<void> show(
    BuildContext context, {
    required Map<String, dynamic> orderData,
    required SqlDatabase db,
  }) {
    return showDialog(
      context: context,
      builder: (_) => OrderProfitabilityDialog(
        orderData: orderData,
        db: db,
      ),
    );
  }

  @override
  State<OrderProfitabilityDialog> createState() => _OrderProfitabilityDialogState();
}

class _OrderProfitabilityDialogState extends State<OrderProfitabilityDialog> {
  bool _isLoading = true;
  String? _errorMessage;

  double _sellingPrice = 0.0;
  double _materialCostExact = 0.0;
  double _materialCostFullBar = 0.0;
  double _aluminumCost = 0.0;
  double _glassCost = 0.0;
  double _accessoryCost = 0.0;
  double _laborCost = 0.0;
  double _netProfit = 0.0;
  double _marginPercent = 0.0;

  final NumberFormat _fmt = NumberFormat('#,##0.00');

  String _t(String key) {
    final lang = Provider.of<AppSettingsProvider>(context, listen: false).language;
    return Localization.translate(key, lang);
  }

  @override
  void initState() {
    super.initState();
    _loadCostingData();
  }

  Future<void> _loadCostingData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final orderId = (widget.orderData['id'] as num?)?.toInt() ?? 0;
      final rawSelling = widget.orderData['total_price'] ??
          widget.orderData['prix_total'] ??
          widget.orderData['total'];
      _sellingPrice = (rawSelling is num) ? rawSelling.toDouble() : double.tryParse('$rawSelling') ?? 0.0;

      // 1. Generate BOM consumption report
      final manager = ConsumptionManager(widget.db);
      final report = await manager.generateReport(orderId);

      _materialCostExact = report.exactCost;
      _materialCostFullBar = report.fullBarCost;

      // Breakdown by category
      double alum = 0.0;
      for (final item in report.aluminumItems) {
        alum += (item.price * item.quantity);
      }
      _aluminumCost = alum;

      double gl = 0.0;
      for (final item in report.glassItems) {
        gl += (item.price * item.quantity);
      }
      _glassCost = gl;

      double acc = 0.0;
      for (final item in report.accessoryItems) {
        acc += (item.price * item.quantity);
      }
      _accessoryCost = acc;

      // 2. Fetch associated worker labor transactions for this order if present
      try {
        final myDb = await widget.db.db;
        if (myDb != null) {
          final workerTx = await myDb.query(
            'WorkerTransactions',
            where: 'order_id = ?',
            whereArgs: [orderId],
          );
          double labor = 0.0;
          for (final tx in workerTx) {
            labor += (tx['amount'] as num?)?.toDouble() ?? 0.0;
          }
          _laborCost = labor;
        }
      } catch (_) {}

      // Fallback selling price from BOM if order had 0 saved
      if (_sellingPrice <= 0 && report.totalSellingPrice > 0) {
        _sellingPrice = report.totalSellingPrice;
      }

      // Net margin calculation: Selling price minus exact material cost minus labor
      final totalDirectCost = _materialCostExact + _laborCost;
      _netProfit = _sellingPrice - totalDirectCost;
      _marginPercent = _sellingPrice > 0 ? (_netProfit / _sellingPrice) * 100 : 0.0;

      if (mounted) {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = e.toString();
        });
      }
    }
  }

  Color _getMarginColor(double percent) {
    if (percent >= 30.0) return const Color(0xFF10B981); // Emerald / High profit
    if (percent >= 15.0) return const Color(0xFF3B82F6); // Blue / Healthy profit
    if (percent >= 5.0) return const Color(0xFFF59E0B);  // Amber / Low margin
    return const Color(0xFFEF4444);                     // Red / Loss or danger
  }

  String _getMarginLabel(double percent) {
    if (percent >= 30.0) return _t('هامش ربح ممتاز');
    if (percent >= 15.0) return _t('هامش ربح جيد');
    if (percent >= 5.0) return _t('هامش ربح ضعيف');
    if (percent >= 0.0) return _t('هامش حرج جداً');
    return _t('تنبيه: خسارة في الطلبية!');
  }

  @override
  Widget build(BuildContext context) {
    final orderNum = widget.orderData['num_commande'] ?? widget.orderData['id'] ?? '';
    final clientName = widget.orderData['client_name'] ??
        widget.orderData['firstname'] ??
        widget.orderData['client'] ??
        '';

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF0F172A) : Colors.white;
    final cardBg = isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC);
    final textCol = isDark ? Colors.white : const Color(0xFF0F172A);
    final textDim = isDark ? Colors.white60 : Colors.black54;

    final marginColor = _getMarginColor(_marginPercent);

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 580, maxHeight: 720),
          child: Container(
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isDark ? Colors.white.withValues(alpha: 0.1) : Colors.black12,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 25,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: marginColor.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.analytics_rounded,
                        color: marginColor,
                        size: 26,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${_t('تحليل تكلفة وربحية الطلبية')} #$orderNum',
                            style: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: textCol,
                            ),
                          ),
                          if (clientName.toString().isNotEmpty)
                            Text(
                              '${_t('العميل')}: $clientName',
                              style: TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 13,
                                color: textDim,
                              ),
                            ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: Icon(Icons.close_rounded, color: textDim),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // Content Body
                if (_isLoading)
                  const Expanded(
                    child: Center(
                      child: CircularProgressIndicator(),
                    ),
                  )
                else if (_errorMessage != null)
                  Expanded(
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.error_outline, color: Colors.redAccent, size: 48),
                          const SizedBox(height: 12),
                          Text(
                            _errorMessage!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontFamily: 'Cairo', color: Colors.redAccent),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Top Banner: Net Profit and Margin %
                          Container(
                            padding: const EdgeInsets.all(18),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  marginColor.withValues(alpha: 0.15),
                                  marginColor.withValues(alpha: 0.05),
                                ],
                              ),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: marginColor.withValues(alpha: 0.3)),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        _getMarginLabel(_marginPercent),
                                        style: TextStyle(
                                          fontFamily: 'Cairo',
                                          fontSize: 13,
                                          fontWeight: FontWeight.bold,
                                          color: marginColor,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '${_fmt.format(_netProfit)} DZD',
                                        style: TextStyle(
                                          fontFamily: 'Cairo',
                                          fontSize: 26,
                                          fontWeight: FontWeight.w900,
                                          color: textCol,
                                        ),
                                      ),
                                      Text(
                                        _t('صافي الربح التقديري للطلبية'),
                                        style: TextStyle(
                                          fontFamily: 'Cairo',
                                          fontSize: 12,
                                          color: textDim,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                  decoration: BoxDecoration(
                                    color: marginColor,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Column(
                                    children: [
                                      Text(
                                        '${_marginPercent.toStringAsFixed(1)}%',
                                        style: const TextStyle(
                                          fontFamily: 'Cairo',
                                          fontSize: 22,
                                          fontWeight: FontWeight.w900,
                                          color: Colors.white,
                                        ),
                                      ),
                                      Text(
                                        _t('هامش الربح'),
                                        style: const TextStyle(
                                          fontFamily: 'Cairo',
                                          fontSize: 11,
                                          color: Colors.white70,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 18),

                          // Overview Cards (Selling vs Total Cost)
                          Row(
                            children: [
                              Expanded(
                                child: _buildStatCard(
                                  title: _t('سعر البيع للعميل'),
                                  value: '${_fmt.format(_sellingPrice)} DZD',
                                  icon: Icons.point_of_sale_rounded,
                                  color: Colors.blueAccent,
                                  cardBg: cardBg,
                                  textCol: textCol,
                                  textDim: textDim,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _buildStatCard(
                                  title: _t('إجمالي التكلفة المباشرة'),
                                  value: '${_fmt.format(_materialCostExact + _laborCost)} DZD',
                                  icon: Icons.payments_outlined,
                                  color: Colors.orangeAccent,
                                  cardBg: cardBg,
                                  textCol: textCol,
                                  textDim: textDim,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 18),

                          // Breakdown Sections
                          Text(
                            _t('تفصيل تكلفة المواد والإنتاج'),
                            style: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: textCol,
                            ),
                          ),
                          const SizedBox(height: 10),

                          Container(
                            decoration: BoxDecoration(
                              color: cardBg,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.black12,
                              ),
                            ),
                            child: Column(
                              children: [
                                _buildCostRow(
                                  label: _t('الألمنيوم والمقاطع'),
                                  amount: _aluminumCost,
                                  totalCost: _materialCostExact + _laborCost,
                                  icon: Icons.view_sidebar_rounded,
                                  color: const Color(0xFF38BDF8),
                                  textCol: textCol,
                                  textDim: textDim,
                                ),
                                Divider(height: 1, color: isDark ? Colors.white10 : Colors.black12),
                                _buildCostRow(
                                  label: _t('الزجاج والحشوات'),
                                  amount: _glassCost,
                                  totalCost: _materialCostExact + _laborCost,
                                  icon: Icons.grid_view_rounded,
                                  color: const Color(0xFF34D399),
                                  textCol: textCol,
                                  textDim: textDim,
                                ),
                                Divider(height: 1, color: isDark ? Colors.white10 : Colors.black12),
                                _buildCostRow(
                                  label: _t('الإكسسوارات والمفصلات والجوانات'),
                                  amount: _accessoryCost,
                                  totalCost: _materialCostExact + _laborCost,
                                  icon: Icons.build_circle_outlined,
                                  color: const Color(0xFFA78BFA),
                                  textCol: textCol,
                                  textDim: textDim,
                                ),
                                Divider(height: 1, color: isDark ? Colors.white10 : Colors.black12),
                                _buildCostRow(
                                  label: _t('أجور العمالة المباشرة'),
                                  amount: _laborCost,
                                  totalCost: _materialCostExact + _laborCost,
                                  icon: Icons.engineering_outlined,
                                  color: const Color(0xFFFB923C),
                                  textCol: textCol,
                                  textDim: textDim,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 14),

                          // Note on full bar cost vs exact cutting cost
                          if (_materialCostFullBar > _materialCostExact) ...[
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.blue.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: Colors.blue.withValues(alpha: 0.2)),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Icon(Icons.info_outline, color: Colors.blueAccent, size: 18),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      '${_t('ملاحظة هامة')}: ${_t('تكلفة المواد أعلاه محسوبة بالقطع الصافي. في حال عدم إعادة استخدام الفضلات واحتساب البارات الكاملة بالكامل تبلغ التكلفة:')} ${_fmt.format(_materialCostFullBar)} DZD.',
                                      style: TextStyle(
                                        fontFamily: 'Cairo',
                                        fontSize: 11,
                                        color: isDark ? Colors.white70 : Colors.black87,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),

                // Footer button
                const SizedBox(height: 14),
                ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blueAccent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: Text(
                    _t('إغلاق'),
                    style: const TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
    required Color cardBg,
    required Color textCol,
    required Color textDim,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 12,
                    color: textDim,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: textCol,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCostRow({
    required String label,
    required double amount,
    required double totalCost,
    required IconData icon,
    required Color color,
    required Color textCol,
    required Color textDim,
  }) {
    final percent = totalCost > 0 ? (amount / totalCost) * 100 : 0.0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 18, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: textCol,
                  ),
                ),
                Text(
                  '${percent.toStringAsFixed(1)}% ${_t('من إجمالي التكلفة')}',
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 11,
                    color: textDim,
                  ),
                ),
              ],
            ),
          ),
          Text(
            '${_fmt.format(amount)} DZD',
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: textCol,
            ),
          ),
        ],
      ),
    );
  }
}
