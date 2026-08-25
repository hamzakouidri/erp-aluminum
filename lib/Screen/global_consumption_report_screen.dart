import 'package:flutter/material.dart';
import 'package:database_data/Commande/Systeme/consumption_manager.dart';
import 'package:database_data/sql_database.dart';
import 'package:database_data/Commande/Systeme/cutting_calculator.dart';
import 'package:database_data/widgets/resizable_columns_table.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:flutter/services.dart';

class GlobalConsumptionReportScreen extends StatefulWidget {
  final SqlDatabase db;

  const GlobalConsumptionReportScreen({super.key, required this.db});

  @override
  State<GlobalConsumptionReportScreen> createState() =>
      _GlobalConsumptionReportScreenState();
}

class _GlobalConsumptionReportScreenState
    extends State<GlobalConsumptionReportScreen> {
  late Future<ConsumptionReport> _reportFuture;

  @override
  void initState() {
    super.initState();
    _reportFuture = _generateGlobalReport();
  }

  Future<ConsumptionReport> _generateGlobalReport() async {
    final manager = ConsumptionManager(widget.db);
    final allOrders = await widget.db.readCommandesWithClients();

    // Filter active orders
    final activeOrders = allOrders
        .where(
          (o) =>
              o['status'] == 'Confirmed' ||
              o['status'] == 'In Progress' ||
              o['status'] == 'Pending',
        )
        .toList();

    List<CuttingItem> allAlum = [];
    List<CuttingItem> allGlass = [];
    List<CuttingItem> allAcc = [];

    for (var order in activeOrders) {
      final report = await manager.generateReport(order['id']);
      allAlum.addAll(report.aluminumItems);
      allGlass.addAll(report.glassItems);
      allAcc.addAll(report.accessoryItems);
    }

    // Aggregate globally
    return ConsumptionReport(
      aluminumItems: _aggregateItems(allAlum),
      glassItems: _aggregateItems(allGlass),
      accessoryItems: _aggregateItems(allAcc),
      totalSellingPrice: 0,
      exactCost: 0,
      fullBarCost: 0,
      totalScrewsCount: 0,
    );
  }

  List<CuttingItem> _aggregateItems(List<CuttingItem> items) {
    Map<String, CuttingItem> map = {};
    for (var item in items) {
      String key =
          '${item.name}_${item.width.toStringAsFixed(1)}_${item.height.toStringAsFixed(1)}';
      if (map.containsKey(key)) {
        var existing = map[key]!;
        map[key] = CuttingItem(
          name: existing.name,
          description: existing.description,
          width: existing.width,
          height: existing.height,
          quantity: existing.quantity + item.quantity,
          type: existing.type,
          isMissing: true, // Everything is missing until DB is checked
        );
      } else {
        map[key] = item;
      }
    }
    return map.values.toList();
  }

  Future<void> _generatePurchasePdf(ConsumptionReport report) async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('جاري إنشاء قائمة الشراء PDF الشاملة...')),
    );

    final pdf = pw.Document();
    final fontData = await rootBundle.load('assets/fonts/Cairo-Regular.ttf');
    final ttf = pw.Font.ttf(fontData);

    List<CuttingItem> missingAlum = report.aluminumItems.where((i) => i.isMissing).toList();
    List<CuttingItem> missingGlass = report.glassItems.where((i) => i.isMissing).toList();
    List<CuttingItem> missingAcc = report.accessoryItems.where((i) => i.isMissing).toList();

    if (missingAlum.isEmpty && missingGlass.isEmpty && missingAcc.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('لا توجد نواقص لشرائها! جميع المواد متوفرة.')),
        );
      }
      return;
    }

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        textDirection: pw.TextDirection.rtl,
        theme: pw.ThemeData.withFont(base: ttf),
        build: (pw.Context context) {
          return [
            pw.Header(
              level: 0,
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('قائمة شراء النواقص الشاملة', style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold, font: ttf)),
                  pw.Text('لكل الطلبيات النشطة', style: pw.TextStyle(fontSize: 16, font: ttf)),
                ]
              ),
            ),
            pw.SizedBox(height: 20),
            
            if (missingAlum.isNotEmpty) _buildPdfSection('قطاعات الألمنيوم (Aluminium)', missingAlum, ttf),
            if (missingGlass.isNotEmpty) _buildPdfSection('الزجاج (Verre)', missingGlass, ttf),
            if (missingAcc.isNotEmpty) _buildPdfSection('الإكسسوارات (Accessoires)', missingAcc, ttf),
            
            pw.SizedBox(height: 30),
            pw.Divider(),
            pw.Text('تاريخ الإنشاء: ${DateTime.now().toString().substring(0, 16)}', style: pw.TextStyle(fontSize: 12, font: ttf)),
          ];
        },
      ),
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
      name: 'Global_Purchase_List.pdf',
    );
  }

  pw.Widget _buildPdfSection(String title, List<CuttingItem> items, pw.Font ttf) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(title, style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, font: ttf)),
        pw.SizedBox(height: 10),
        pw.TableHelper.fromTextArray(
          context: null,
          cellAlignment: pw.Alignment.centerRight,
          headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
          headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, font: ttf),
          cellStyle: pw.TextStyle(font: ttf),
          headers: ['الاسم', 'الطول', 'العرض', 'الكمية الإجمالية'],
          data: items.map((item) {
            return [
              item.name,
              item.width > 0 ? item.width.toStringAsFixed(1) : '-',
              item.height > 0 ? item.height.toStringAsFixed(1) : '-',
              item.quantity.toString(),
            ];
          }).toList(),
        ),
        pw.SizedBox(height: 20),
      ]
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text('تقرير النواقص الشامل', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        actions: [
          ElevatedButton.icon(
            icon: const Icon(Icons.shopping_cart, color: Colors.white),
            label: const Text("شراء كل النواقص", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () async {
              final report = await _reportFuture;
              _generatePurchasePdf(report);
            },
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: FutureBuilder<ConsumptionReport>(
        future: _reportFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('حدث خطأ: ${snapshot.error}'));
          }

          final report = snapshot.data!;
          
          if (report.aluminumItems.isEmpty && report.glassItems.isEmpty && report.accessoryItems.isEmpty) {
            return const Center(child: Text('لا توجد نواقص في أي طلبية نشطة!', style: TextStyle(fontSize: 18, color: Colors.green)));
          }

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (report.aluminumItems.isNotEmpty)
                _buildSectionCard('قطاعات الألمنيوم (Aluminium)', Icons.straighten, Colors.blue, report.aluminumItems),
              const SizedBox(height: 16),
              if (report.glassItems.isNotEmpty)
                _buildSectionCard('الزجاج (Verre)', Icons.window, Colors.teal, report.glassItems),
              const SizedBox(height: 16),
              if (report.accessoryItems.isNotEmpty)
                _buildSectionCard('الإكسسوارات (Accessoires)', Icons.build, Colors.orange, report.accessoryItems),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSectionCard(String title, IconData icon, Color color, List<CuttingItem> items) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: Row(
              children: [
                Icon(icon, color: color),
                const SizedBox(width: 8),
                Text(title, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: ResizableColumnsTable(
              headerColor: Colors.blueGrey.shade800,
              borderColor: Colors.grey.shade300,
              rowColor: Colors.white,
              headerMinHeight: 38,
              rowMinHeight: 42,
              cellPadding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 7,
              ),
              columns: const [
                ResizableTableColumn(
                  id: 'name',
                  label: Text(
                    'الاسم',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  initialWidth: 320,
                  minWidth: 180,
                  maxWidth: 620,
                ),
                ResizableTableColumn(
                  id: 'width',
                  label: Text(
                    'الطول (ملم)',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  initialWidth: 130,
                  minWidth: 95,
                  maxWidth: 220,
                ),
                ResizableTableColumn(
                  id: 'height',
                  label: Text(
                    'العرض (ملم)',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  initialWidth: 130,
                  minWidth: 95,
                  maxWidth: 220,
                ),
                ResizableTableColumn(
                  id: 'quantity',
                  label: Text(
                    'العدد',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  initialWidth: 100,
                  minWidth: 80,
                  maxWidth: 180,
                ),
              ],
              rows: items.map((item) {
                final textColor = item.isMissing ? Colors.red : Colors.black87;
                final textStyle = TextStyle(color: textColor);
                return ResizableTableRow(
                  cells: [
                    Text(
                      item.name,
                      overflow: TextOverflow.ellipsis,
                      style: textStyle,
                    ),
                    Text(
                      item.width > 0 ? item.width.toStringAsFixed(1) : '-',
                      style: textStyle,
                    ),
                    Text(
                      item.height > 0 ? item.height.toStringAsFixed(1) : '-',
                      style: textStyle,
                    ),
                    Text(
                      item.quantity.toString(),
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: textColor,
                      ),
                    ),
                  ],
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}
