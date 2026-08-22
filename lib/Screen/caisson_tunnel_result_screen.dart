import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../settings/app_settings.dart';
import '../settings/localization.dart';
import '../widgets/resizable_columns_table.dart';
import '../widgets/numeric_filter_search_field.dart';

class CaissonTunnelResultScreen extends StatefulWidget {
  final Map<String, dynamic> caissonData;

  const CaissonTunnelResultScreen({
    super.key,
    required this.caissonData,
  });

  @override
  State<CaissonTunnelResultScreen> createState() => _CaissonTunnelResultScreenState();
}

class _CaissonTunnelResultScreenState extends State<CaissonTunnelResultScreen> {
  static const Color _primaryBlue = Color(0xFF1565C0);
  static const Color _accentOrange = Color(0xFFFF9800);

  NumericFilterState _numericFilter = const NumericFilterState();

  Widget _buildSystemImage() {
    return Container(
      width: 44,
      height: 44,
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
                return const Icon(Icons.square_rounded, color: _primaryBlue, size: 26);
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
    final lang = Provider.of<AppSettingsProvider>(context).language;

    final String kitType = widget.caissonData['kitType'] ?? 'Kit 11 (+11cm)';
    final String kitLabel = kitType.contains('16') ? '+16 cm' : '+11 cm';
    final int grandTotalCaissonBars = widget.caissonData['grandTotalCaissonBars'] ?? 0;
    final int grandTotalBottomCoverBars = widget.caissonData['grandTotalBottomCoverBars'] ?? 0;
    final int grandTotalPairs = widget.caissonData['grandTotalPairs'] ?? 0;
    final Map<String, dynamic> sizeCalcs = Map<String, dynamic>.from(widget.caissonData['sizeCalculations'] ?? {});

    final columns = [
      ResizableTableColumn(
        id: 'img',
        label: Center(
          child: Text(
            Localization.translate('الصورة', lang),
            style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 13),
          ),
        ),
        initialWidth: 75,
        minWidth: 60,
        maxWidth: 120,
      ),
      ResizableTableColumn(
        id: 'size',
        label: Center(
          child: Text(
            Localization.translate('حجم الصندوق', lang),
            style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 13),
          ),
        ),
        initialWidth: 120,
        minWidth: 90,
        maxWidth: 200,
      ),
      ResizableTableColumn(
        id: 'pairs',
        label: Center(
          child: Text(
            Localization.translate('عدد أزواج Kit', lang),
            style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 13),
          ),
        ),
        initialWidth: 150,
        minWidth: 110,
        maxWidth: 260,
      ),
      ResizableTableColumn(
        id: 'caisson_bars',
        label: Center(
          child: Text(
            Localization.translate('بارات الصندوق (الكيسون)', lang),
            style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 13),
          ),
        ),
        initialWidth: 230,
        minWidth: 150,
        maxWidth: 400,
      ),
      ResizableTableColumn(
        id: 'cover_bars',
        label: Center(
          child: Text(
            Localization.translate('الغطاء السفلي والأغطية الجانبية', lang),
            style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 13),
          ),
        ),
        initialWidth: 280,
        minWidth: 180,
        maxWidth: 550,
      ),
    ];

    final rows = _buildGridTableRows(sizeCalcs, kitLabel, isDark, lang);

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF121212) : const Color(0xFFF3F5F8),
      appBar: AppBar(
        title: Text(
          Localization.translate('جدول كمية وتكلفة Caisson Tunnel', lang),
          style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, color: Colors.white),
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
                          Text(
                            Localization.translate('نظام Caisson Tunnel', lang),
                            style: const TextStyle(
                              fontFamily: 'Cairo',
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: _primaryBlue,
                            ),
                          ),
                          Text(
                            '${Localization.translate("نوع الأغطية (Kit):", lang)} $kitType  |  ${Localization.translate("زوج", lang)}: $grandTotalPairs',
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

            // Main Resizable Grid Table Card
            Card(
              elevation: 2,
              color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header Wrap
                    Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.table_chart_rounded, color: _primaryBlue, size: 22),
                            const SizedBox(width: 8),
                            Text(
                              Localization.translate('جدول كميات ومكونات Caisson Tunnel (أعمدة قابلة للتعديل):', lang),
                              style: const TextStyle(
                                fontFamily: 'Cairo',
                                fontWeight: FontWeight.bold,
                                fontSize: 14.5,
                              ),
                            ),
                          ],
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            NumericFilterSearchField(
                              hintText: Localization.translate('فلترة بعدد البارات (=, >, <)...', lang),
                              lang: lang,
                              initialState: _numericFilter,
                              width: 250,
                              onFilterChanged: (f) => setState(() => _numericFilter = f),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: _accentOrange.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                '${Localization.translate("إجمالي البارات:", lang)} ${grandTotalCaissonBars + grandTotalBottomCoverBars}',
                                style: const TextStyle(fontFamily: 'Cairo', fontSize: 12, fontWeight: FontWeight.bold, color: _accentOrange),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const Divider(height: 20),

                    // Resizable Table with Drag-to-Resize Columns
                    Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: isDark ? Colors.grey.shade800 : Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: ResizableColumnsTable(
                          columns: columns,
                          rows: rows,
                          headerColor: isDark ? const Color(0xFF2C2C2C) : Colors.blue.shade100,
                          borderColor: isDark ? Colors.grey.shade700 : Colors.grey.shade300,
                          rowColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                          headerMinHeight: 42,
                          rowMinHeight: 52,
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
                Navigator.of(context).pop(widget.caissonData);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(Localization.translate('تمت إضافة Caisson Tunnel إلى الطلب بنجاح', lang), style: const TextStyle(fontFamily: 'Cairo')),
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
              label: Text(
                Localization.translate('إضافة Caisson Tunnel إلى الطلب', lang),
                style: const TextStyle(fontFamily: 'Cairo', fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<ResizableTableRow> _buildGridTableRows(Map<String, dynamic> sizeCalcs, String kitLabel, bool isDark, AppLanguage lang) {
    final List<ResizableTableRow> rows = [];
    final cmStr = lang == AppLanguage.arabic ? 'سم' : 'cm';
    final mStr = lang == AppLanguage.arabic ? 'متر' : 'm';
    final pairStr = Localization.translate('زوج', lang);

    sizeCalcs.forEach((sizeStr, calc) {
      final int sizeCm = calc['sizeCm'] ?? int.tryParse(sizeStr) ?? 30;
      final int cBars = calc['caissonBars'] ?? 0;
      final int bBars = calc['bottomCoverBars'] ?? 0;
      final int pairs = calc['totalPairs'] ?? 0;
      final double cMeters = (calc['caissonMeters'] ?? 0.0).toDouble();
      final double bMeters = (calc['bottomCoverMeters'] ?? 0.0).toDouble();

      // Check numeric filter if active
      if (_numericFilter.isActive) {
        final totalRowBars = cBars + bBars;
        if (!_numericFilter.matches(totalRowBars) && !_numericFilter.matches(cBars) && !_numericFilter.matches(bBars) && !_numericFilter.matches(sizeCm)) {
          return;
        }
      }

      rows.add(
        ResizableTableRow(
          cells: [
            // Cell 1: Image
            Center(child: _buildSystemImage()),

            // Cell 2: Caisson Size
            Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: _primaryBlue.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '$sizeCm $cmStr',
                  style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, color: _primaryBlue, fontSize: 14),
                ),
              ),
            ),

            // Cell 3: Kit Count & Addition (e.g., 4 زوج (+11 سم))
            Center(
              child: Text(
                '$pairs $pairStr ($kitLabel)',
                style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 13, color: _primaryBlue),
              ),
            ),

            // Cell 4: Caisson Bars (Barres du Caisson - includes Kit Addition)
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$cBars ${Localization.translate("بارة (6م)", lang)}',
                  style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, color: _primaryBlue, fontSize: 13.5),
                ),
                Text(
                  '${Localization.translate("الطول:", lang)} ${cMeters.toStringAsFixed(2)} $mStr',
                  style: TextStyle(fontFamily: 'Cairo', fontSize: 11, color: isDark ? Colors.grey.shade400 : Colors.black54),
                ),
              ],
            ),

            // Cell 5: Bottom Cover Bars (NO Kit addition) & Side Cover Pairs
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${Localization.translate("غطاء سفلي:", lang)} $bBars ${Localization.translate("بارة (6م)", lang)} (${bMeters.toStringAsFixed(2)}$mStr)',
                  style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w600, fontSize: 11.5),
                ),
                const SizedBox(height: 2),
                Text(
                  '${Localization.translate("أغطية جانبية", lang)} $sizeCm$cmStr: $pairs $pairStr',
                  style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, color: _accentOrange, fontSize: 11.5),
                ),
              ],
            ),
          ],
        ),
      );
    });

    return rows;
  }
}
