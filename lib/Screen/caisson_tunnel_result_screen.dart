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

  Widget _buildSystemImage() {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: _primaryBlue.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _primaryBlue.withValues(alpha: 0.3)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.asset(
          'Icon/caisson_tunnel.jpg',
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            return Image.asset(
              'assets/Icon/caisson_tunnel.jpg',
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) {
                return const Icon(Icons.square_rounded, color: _primaryBlue, size: 28);
              },
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final String kitType = caissonData['kitType'] ?? 'Kit 11';
    final int grandTotalCaissonBars = caissonData['grandTotalCaissonBars'] ?? 0;
    final int grandTotalBottomCoverBars = caissonData['grandTotalBottomCoverBars'] ?? 0;
    final int grandTotalPairs = caissonData['grandTotalPairs'] ?? 0;
    final Map<String, dynamic> sizeCalcs = Map<String, dynamic>.from(caissonData['sizeCalculations'] ?? {});

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF121212) : const Color(0xFFF3F5F8),
      appBar: AppBar(
        title: const Text(
          'جدول كمية وتكلفة كيسون النفق',
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
            // Header Summary Card
            Card(
              elevation: 2,
              color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    _buildSystemImage(),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'نظام كيسون النفق (Caisson Tunnel)',
                            style: TextStyle(
                              fontFamily: 'Cairo',
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: _primaryBlue,
                            ),
                          ),
                          Text(
                            'نوع الكيت: $kitType  |  إجمالي أزواج الأغطية: $grandTotalPairs زوج',
                            style: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 12,
                              color: isDark ? Colors.grey.shade300 : Colors.black87,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),

            // Main 5-Column Data Table Card
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
                            Icon(Icons.view_list_rounded, color: _primaryBlue, size: 22),
                            SizedBox(width: 8),
                            Text(
                              'جدول الكميات والمكونات لكيسون النفق:',
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
                            color: _accentOrange.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            'إجمالي البارات: ${grandTotalCaissonBars + grandTotalBottomCoverBars} بارة',
                            style: const TextStyle(fontFamily: 'Cairo', fontSize: 12, fontWeight: FontWeight.bold, color: _accentOrange),
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 20),

                    // Interactive 5-Column Data Table
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                        columnSpacing: 18,
                        headingRowHeight: 46,
                        dataRowMinHeight: 65,
                        dataRowMaxHeight: 85,
                        headingRowColor: WidgetStateProperty.all(
                          isDark ? const Color(0xFF2C2C2C) : Colors.blue.shade50,
                        ),
                        columns: const [
                          DataColumn(label: Text('الصورة', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold))),
                          DataColumn(label: Text('حجم الصندوق', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold))),
                          DataColumn(label: Text('الـ Kit', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold))),
                          DataColumn(label: Text('بارات الصندوق (الكيسون)', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold))),
                          DataColumn(label: Text('الغطاء السفلي والأغطية الجانبية', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold))),
                        ],
                        rows: _build5ColumnTableRows(sizeCalcs, kitType, isDark),
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
                'إضافة كيسون النفق إلى الطلب',
                style: TextStyle(fontFamily: 'Cairo', fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<DataRow> _build5ColumnTableRows(Map<String, dynamic> sizeCalcs, String kitType, bool isDark) {
    final List<DataRow> rows = [];

    sizeCalcs.forEach((sizeStr, calc) {
      final int sizeCm = calc['sizeCm'] ?? int.tryParse(sizeStr) ?? 30;
      final int cBars = calc['caissonBars'] ?? 0;
      final int bBars = calc['bottomCoverBars'] ?? 0;
      final int pairs = calc['totalPairs'] ?? 0;
      final double cMeters = (calc['caissonMeters'] ?? 0.0).toDouble();
      final double bMeters = (calc['bottomCoverMeters'] ?? 0.0).toDouble();

      rows.add(
        DataRow(cells: [
          // Column 1: System Image
          DataCell(_buildSystemImage()),

          // Column 2: Caisson Size
          DataCell(
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: _primaryBlue.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '$sizeCm سم',
                style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, color: _primaryBlue, fontSize: 14),
              ),
            ),
          ),

          // Column 3: Kit Type
          DataCell(
            Text(
              kitType,
              style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w600, fontSize: 13),
            ),
          ),

          // Column 4: Caisson Bars (Barres du Caisson)
          DataCell(
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$cBars بارة (6م)',
                  style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, color: _primaryBlue, fontSize: 14),
                ),
                Text(
                  'الطول: ${cMeters.toStringAsFixed(2)} متر',
                  style: TextStyle(fontFamily: 'Cairo', fontSize: 11, color: isDark ? Colors.grey.shade400 : Colors.black54),
                ),
              ],
            ),
          ),

          // Column 5: Bottom Cover & Side Covers (Couvercle inférieur & Embouts)
          DataCell(
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'غطاء سفلي: $bBars بارة 6م (${bMeters.toStringAsFixed(2)}م)',
                  style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w600, fontSize: 12),
                ),
                const SizedBox(height: 2),
                Text(
                  'أغطية جانبية $sizeCmسم: $pairs زوج (Paire)',
                  style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, color: _accentOrange, fontSize: 12),
                ),
              ],
            ),
          ),
        ]),
      );
    });

    return rows;
  }
}
