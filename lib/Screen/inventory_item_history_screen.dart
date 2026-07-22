import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../settings/app_settings.dart';
import '../settings/localization.dart';
import 'package:intl/intl.dart' hide TextDirection;
import '../sql_database.dart';

class InventoryItemHistoryScreen extends StatefulWidget {
  final SqlDatabase db;
  final int itemId;
  final String itemType;
  final String itemName;
  final int? colorId;
  final String colorName;
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
  late Future<List<Map<String, dynamic>>> _transactionsFuture;

  // Colors
  static const _blue = Color(0xFF2563EB);
  static const _bg = Color(0xFFF8FAFC);
  static const _cardBg = Colors.white;
  static const _text = Color(0xFF1E293B);
  static const _textDim = Color(0xFF64748B);
  static const _divider = Color(0xFFE2E8F0);
  static const _green = Color(0xFF10B981);
  static const _red = Color(0xFFEF4444);

  @override
  void initState() {
    super.initState();
    _transactionsFuture = widget.db.readInventoryTransactions(
      itemId: widget.itemId,
      itemType: widget.itemType,
      colorId: widget.colorId,
      locationId: widget.locationId,
    );
  }

  String _formatDate(String dateStr) {
    try {
      final parsed = DateTime.parse(dateStr);
      return DateFormat('yyyy-MM-dd HH:mm').format(parsed);
    } catch (_) {
      return dateStr;
    }
  }

  Widget _buildTransactionIcon(double qtyChange) {
    if (qtyChange > 0) {
      return Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: _green.withValues(alpha: 0.15),
          shape: BoxShape.circle,
        ),
        child: const Icon(
          Icons.arrow_downward_rounded,
          color: _green,
          size: 20,
        ),
      );
    } else {
      return Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: _red.withValues(alpha: 0.15),
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.arrow_upward_rounded, color: _red, size: 20),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final lang = Provider.of<AppSettingsProvider>(context).language;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: _bg,
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          surfaceTintColor: Colors.transparent,
          iconTheme: const IconThemeData(color: _text),
          title: Text(
            Localization.translate('بطاقة حركة المادة', lang),
            style: const TextStyle(
              fontFamily: 'Cairo',
              fontWeight: FontWeight.bold,
              color: _text,
              fontSize: 18,
            ),
          ),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(1.0),
            child: Container(color: _divider, height: 1.0),
          ),
        ),
        body: Column(
          children: [
            // Header Card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              margin: const EdgeInsets.all(16),
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
                  Text(
                    widget.itemName,
                    style: const TextStyle(
                      fontFamily: 'Cairo',
                      fontWeight: FontWeight.w900,
                      fontSize: 18,
                      color: _text,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(
                        Icons.category_rounded,
                        size: 16,
                        color: _textDim,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        Localization.translate(widget.itemType, lang),
                        style: const TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 13,
                          color: _textDim,
                        ),
                      ),
                      const SizedBox(width: 16),
                      if (widget.colorName.isNotEmpty) ...[
                        const Icon(
                          Icons.color_lens_rounded,
                          size: 16,
                          color: _textDim,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          Localization.translate(widget.colorName, lang),
                          style: const TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 13,
                            color: _textDim,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(
                        Icons.storefront_rounded,
                        size: 16,
                        color: _textDim,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        widget.locationName,
                        style: const TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 13,
                          color: _textDim,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Align(
                alignment: Alignment.centerRight,
                child: Text(
                  Localization.translate('سجل الحركات:', lang),
                  style: const TextStyle(
                    fontFamily: 'Cairo',
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: _text,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),

            Expanded(
              child: FutureBuilder<List<Map<String, dynamic>>>(
                future: _transactionsFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  } else if (snapshot.hasError) {
                    return Center(
                      child: Text(
                        'خطأ: ${snapshot.error}',
                        style: const TextStyle(
                          fontFamily: 'Cairo',
                          color: _red,
                        ),
                      ),
                    );
                  }

                  final transactions = snapshot.data ?? [];

                  if (transactions.isEmpty) {
                    return Center(
                      child: Text(
                        Localization.translate('لا توجد حركات مسجلة لهذه المادة.', lang),
                        style: const TextStyle(fontFamily: 'Cairo', color: _textDim),
                      ),
                    );
                  }

                  return ListView.builder(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    itemCount: transactions.length,
                    itemBuilder: (context, index) {
                      final t = transactions[index];
                      final qtyChange = (t['quantity'] as num).toDouble();
                      final type = t['transaction_type'] ?? 'Unknown';
                      final ref = t['reference_id']?.toString() ?? '';
                      final date = _formatDate(t['created_at'] ?? '');

                      String title = '';
                      if (type == 'Purchase') {
                        title = "${Localization.translate('فاتورة شراء رقم ', lang)}$ref";
                      } else if (type == 'Purchase Adjustment') {
                        title = "${Localization.translate('تعديل مشتريات رقم ', lang)}$ref";
                      } else if (type == 'Purchase Deletion') {
                        title = "${Localization.translate('إلغاء مشتريات رقم ', lang)}$ref";
                      } else if (type == 'Order') {
                        title = "${Localization.translate('استهلاك في طلبية رقم ', lang)}$ref";
                      } else {
                        title = type;
                      }

                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: _cardBg,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: _divider),
                        ),
                        child: Row(
                          children: [
                            _buildTransactionIcon(qtyChange),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    title,
                                    style: const TextStyle(
                                      fontFamily: 'Cairo',
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                      color: _text,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    date,
                                    style: const TextStyle(
                                      fontFamily: 'Cairo',
                                      fontSize: 12,
                                      color: _textDim,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Text(
                              qtyChange > 0
                                  ? '+${qtyChange.toStringAsFixed(2)}'
                                  : qtyChange.toStringAsFixed(2),
                              style: TextStyle(
                                fontFamily: 'Cairo',
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                color: qtyChange > 0 ? _green : _red,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
