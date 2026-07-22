import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:database_data/settings/app_settings.dart';

class CaissonTunnelResultScreen extends StatelessWidget {
  final Map<String, dynamic> caissonData;

  const CaissonTunnelResultScreen({
    super.key,
    required this.caissonData,
  });

  static const Color _primaryBlue = Color(0xFF1565C0);
  static const Color _accentOrange = Color(0xFFFF9800);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final String kitType = caissonData['kitType'] ?? 'Kit 11';
    final String inputUnit = caissonData['inputUnit'] ?? 'mm';
    final int grandTotalCaissonBars = caissonData['grandTotalCaissonBars'] ?? 0;
    final int grandTotalBottomCoverBars = caissonData['grandTotalBottomCoverBars'] ?? 0;
    final int grandTotalPairs = caissonData['grandTotalPairs'] ?? 0;
    final Map<String, dynamic> sizeCalcs = Map<String, dynamic>.from(caissonData['sizeCalculations'] ?? {});

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF121212) : const Color(0xFFF3F5F8),
      appBar: AppBar(
        title: const Text(
          'جدول نتائج كيسون النفق',
          style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, color: Colors.white),
        ),
        centerTitle: true,
        backgroundColor: isDark ? const Color(0xFF1E1E1E) : _primaryBlue,
        foregroundColor: Colors.white,
        elevation: 1.0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Top Summary Cards
            Row(
              children: [
                _buildMetricCard(
                  title: 'بارات الكيسون (6م)',
                  value: '$grandTotalCaissonBars بارة',
                  icon: Icons.view_day_rounded,
                  color: _primaryBlue,
                  isDark: isDark,
                ),
                const SizedBox(width: 8),
                _buildMetricCard(
                  title: 'بارات الغطاء (6م)',
                  value: '$grandTotalBottomCoverBars بارة',
                  icon: Icons.horizontal_rule_rounded,
                  color: _accentOrange,
                  isDark: isDark,
                ),
                const SizedBox(width: 8),
                _buildMetricCard(
                  title: 'أزواج الأغطية',
                  value: '$grandTotalPairs زوج',
                  icon: Icons.square_rounded,
                  color: Colors.green.shade700,
                  isDark: isDark,
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Main Results Data Table
            Card(
              elevation: 2,
              color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.table_chart_rounded, color: _primaryBlue, size: 22),
                            SizedBox(width: 8),
                            Text(
                              'جدول توزيع البارات والأغطية الجانبية:',
                              style: TextStyle(
                                fontFamily: 'Cairo',
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: _primaryBlue.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            'نوع الكيت: $kitType',
                            style: const TextStyle(fontFamily: 'Cairo', fontSize: 11, fontWeight: FontWeight.bold, color: _primaryBlue),
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 20),

                    // Interactive Data Table
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                        columnSpacing: 16,
                        headingRowColor: WidgetStateProperty.all(
                          isDark ? const Color(0xFF2C2C2C) : Colors.grey.shade100,
                        ),
                        columns: const [
                          DataColumn(label: Text('نوع العنصر', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold))),
                          DataColumn(label: Text('حجم الصندوق', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold))),
                          DataColumn(label: Text('الطول الإجمالي (متر)', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold))),
                          DataColumn(label: Text('عدد البارات (6م) / أزواج', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold))),
                        ],
                        rows: _buildTableRows(sizeCalcs, isDark),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Action Button: Add to Order
            ElevatedButton.icon(
              onPressed: () {
                Navigator.of(context).pop(caissonData);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('تمت إضافة كيسون النفق إلى الطلب بنجاح', style: TextStyle(fontFamily: 'Cairo')),
                    backgroundColor: Colors.green,
                  ),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green.shade700,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              icon: const Icon(Icons.add_shopping_cart_rounded, color: Colors.white, size: 24),
              label: const Text(
                'إضافة إلى الطلب (حفظ الحساب)',
                style: TextStyle(fontFamily: 'Cairo', fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
    required bool isDark,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.3)),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 6),
          ],
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                fontFamily: 'Cairo',
                fontWeight: FontWeight.bold,
                fontSize: 14,
                color: color,
              ),
            ),
            Text(
              title,
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 10,
                color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  List<DataRow> _buildTableRows(Map<String, dynamic> sizeCalcs, bool isDark) {
    final List<DataRow> rows = [];

    sizeCalcs.forEach((sizeStr, calc) {
      final int sizeCm = calc['sizeCm'] ?? int.tryParse(sizeStr) ?? 30;
      final int cBars = calc['caissonBars'] ?? 0;
      final int bBars = calc['bottomCoverBars'] ?? 0;
      final int pairs = calc['totalPairs'] ?? 0;
      final double cMeters = (calc['caissonMeters'] ?? 0.0).toDouble();
      final double bMeters = (calc['bottomCoverMeters'] ?? 0.0).toDouble();

      // Row 1: Caisson Profile Bars
      rows.add(
        DataRow(cells: [
          const DataCell(Text('بارات كيسون النفق', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w600))),
          DataCell(Text('$sizeCm سم', style: const TextStyle(fontFamily: 'Cairo'))),
          DataCell(Text('${cMeters.toStringAsFixed(2)} م', style: const TextStyle(fontFamily: 'Cairo'))),
          DataCell(Text('$cBars بارة (6م)', style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, color: _primaryBlue))),
        ]),
      );

      // Row 2: Bottom Cover Bars
      rows.add(
        DataRow(cells: [
          const DataCell(Text('بارات غطاء سفلي', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w600))),
          DataCell(Text('$sizeCm سم', style: const TextStyle(fontFamily: 'Cairo'))),
          DataCell(Text('${bMeters.toStringAsFixed(2)} م', style: const TextStyle(fontFamily: 'Cairo'))),
          DataCell(Text('$bBars بارة (6م)', style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, color: _accentOrange))),
        ]),
      );

      // Row 3: Side Cover Pairs
      rows.add(
        DataRow(cells: [
          const DataCell(Text('أغطية جانبية (Paire)', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w600))),
          DataCell(Text('$sizeCm سم', style: const TextStyle(fontFamily: 'Cairo'))),
          const DataCell(Text('-', style: TextStyle(fontFamily: 'Cairo'))),
          DataCell(Text('$pairs زوج', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, color: Colors.green.shade700))),
        ]),
      );
    });

    return rows;
  }
}
