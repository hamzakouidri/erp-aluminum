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

    final String kitType = caissonData['kitType'] ?? 'Kit 11 (+11cm)';
    final String kitLabel = kitType.contains('16') ? '+16 سم' : '+11 سم';
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

            // Main 5-Column Grid Table Card
            Card(
              elevation: 2,
              color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header Wrap (Prevents title overflow on small screens)
                    Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.grid_on_rounded, color: _primaryBlue, size: 22),
                            SizedBox(width: 8),
                            Text(
                              'جدول كميات ومكونات كيسون النفق:',
                              style: TextStyle(
                                fontFamily: 'Cairo',
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
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

                    // Grid Table with explicit vertical & horizontal dividing lines
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Container(
                        constraints: const BoxConstraints(minWidth: 650),
                        child: Table(
                          border: TableBorder.all(
                            color: isDark ? Colors.grey.shade700 : Colors.grey.shade400,
                            width: 1.2,
                          ),
                          columnWidths: const {
                            0: FixedColumnWidth(70),  // Image
                            1: FlexColumnWidth(1.2), // Caisson Size
                            2: FlexColumnWidth(1.4), // Kit Count & Type
                            3: FlexColumnWidth(2.2), // Caisson Bars
                            4: FlexColumnWidth(2.6), // Bottom Cover & Side Covers
                          },
                          children: [
                            // Header Row
                            TableRow(
                              decoration: BoxDecoration(
                                color: isDark ? const Color(0xFF2C2C2C) : Colors.blue.shade100,
                              ),
                              children: const [
                                TableCell(
                                  verticalAlignment: TableCellVerticalAlignment.middle,
                                  child: Padding(
                                    padding: EdgeInsets.symmetric(vertical: 10, horizontal: 6),
                                    child: Center(child: Text('الصورة', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 13))),
                                  ),
                                ),
                                TableCell(
                                  verticalAlignment: TableCellVerticalAlignment.middle,
                                  child: Padding(
                                    padding: EdgeInsets.symmetric(vertical: 10, horizontal: 6),
                                    child: Center(child: Text('حجم الصندوق', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 13))),
                                  ),
                                ),
                                TableCell(
                                  verticalAlignment: TableCellVerticalAlignment.middle,
                                  child: Padding(
                                    padding: EdgeInsets.symmetric(vertical: 10, horizontal: 6),
                                    child: Center(child: Text('عدد أزواج Kit', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 13))),
                                  ),
                                ),
                                TableCell(
                                  verticalAlignment: TableCellVerticalAlignment.middle,
                                  child: Padding(
                                    padding: EdgeInsets.symmetric(vertical: 10, horizontal: 6),
                                    child: Center(child: Text('بارات الصندوق (الكيسون)', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 13))),
                                  ),
                                ),
                                TableCell(
                                  verticalAlignment: TableCellVerticalAlignment.middle,
                                  child: Padding(
                                    padding: EdgeInsets.symmetric(vertical: 10, horizontal: 6),
                                    child: Center(child: Text('الغطاء السفلي والأغطية الجانبية', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 13))),
                                  ),
                                ),
                              ],
                            ),
                            // Data Rows
                            ..._buildGridTableRows(sizeCalcs, kitLabel, isDark),
                          ],
                        ),
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

  List<TableRow> _buildGridTableRows(Map<String, dynamic> sizeCalcs, String kitLabel, bool isDark) {
    final List<TableRow> rows = [];

    sizeCalcs.forEach((sizeStr, calc) {
      final int sizeCm = calc['sizeCm'] ?? int.tryParse(sizeStr) ?? 30;
      final int cBars = calc['caissonBars'] ?? 0;
      final int bBars = calc['bottomCoverBars'] ?? 0;
      final int pairs = calc['totalPairs'] ?? 0;
      final double cMeters = (calc['caissonMeters'] ?? 0.0).toDouble();
      final double bMeters = (calc['bottomCoverMeters'] ?? 0.0).toDouble();

      rows.add(
        TableRow(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
          ),
          children: [
            // Cell 1: Image
            TableCell(
              verticalAlignment: TableCellVerticalAlignment.middle,
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Center(child: _buildSystemImage()),
              ),
            ),

            // Cell 2: Caisson Size
            TableCell(
              verticalAlignment: TableCellVerticalAlignment.middle,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Center(
                  child: Container(
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
              ),
            ),

            // Cell 3: Kit Count & Addition (e.g., 4 زوج (+11 سم))
            TableCell(
              verticalAlignment: TableCellVerticalAlignment.middle,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Center(
                  child: Text(
                    '$pairs زوج ($kitLabel)',
                    style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 13, color: _primaryBlue),
                  ),
                ),
              ),
            ),

            // Cell 4: Caisson Bars (Barres du Caisson - includes Kit Addition)
            TableCell(
              verticalAlignment: TableCellVerticalAlignment.middle,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Column(
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
            ),

            // Cell 5: Bottom Cover Bars (NO Kit addition) & Side Cover Pairs
            TableCell(
              verticalAlignment: TableCellVerticalAlignment.middle,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Column(
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
            ),
          ],
        ),
      );
    });

    return rows;
  }
}
