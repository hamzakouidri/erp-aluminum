import 'dart:io';

void main() {
  String path = 'lib/Screen/consumption_report_screen.dart';
  String content = File(path).readAsStringSync();

  // We add the PDF generation logic here
  String oldBtn = '''            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('سيتم تفعيل ميزة شراء النواقص لاحقاً')),
              );
            },''';

  String newBtn = '''            onPressed: () {
              _generatePurchasePdf(report);
            },''';
            
  content = content.replaceFirst(oldBtn, newBtn);
  
  // Add pdf import
  if (!content.contains('import \'package:pdf/widgets.dart\' as pw;')) {
    content = content.replaceFirst(
      "import 'package:flutter/material.dart';", 
      "import 'package:flutter/material.dart';\nimport 'package:pdf/pdf.dart';\nimport 'package:pdf/widgets.dart' as pw;\nimport 'package:printing/printing.dart';\nimport 'dart:typed_data';\nimport 'package:flutter/services.dart';"
    );
  }

  // Add the _generatePurchasePdf method
  String newMethod = '''  Future<void> _generatePurchasePdf(ConsumptionReport report) async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('جاري إنشاء قائمة الشراء PDF...')),
    );

    final pdf = pw.Document();
    
    // Load font for Arabic
    final fontData = await rootBundle.load('assets/fonts/Cairo-Regular.ttf');
    final ttf = pw.Font.ttf(fontData);

    // Filter missing items
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
                  pw.Text('قائمة شراء النواقص (Bon de Commande)', style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold, font: ttf)),
                  pw.Text('الطلبية: \${widget.clientName}', style: pw.TextStyle(fontSize: 16, font: ttf)),
                ]
              ),
            ),
            pw.SizedBox(height: 20),
            
            if (missingAlum.isNotEmpty) _buildPdfSection('قطاعات الألمنيوم (Aluminium)', missingAlum, ttf),
            if (missingGlass.isNotEmpty) _buildPdfSection('الزجاج (Verre)', missingGlass, ttf),
            if (missingAcc.isNotEmpty) _buildPdfSection('الإكسسوارات (Accessoires)', missingAcc, ttf),
            
            pw.SizedBox(height: 30),
            pw.Divider(),
            pw.Text('تاريخ الإنشاء: \${DateTime.now().toString().substring(0, 16)}', style: pw.TextStyle(fontSize: 12, font: ttf)),
          ];
        },
      ),
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
      name: 'Purchase_List_\${widget.clientName}.pdf',
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
          headers: ['الاسم', 'الطول', 'العرض', 'الكمية المطلوبة'],
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
''';

  if (!content.contains('_generatePurchasePdf')) {
    int lastBracketIndex = content.lastIndexOf('}');
    content = content.substring(0, lastBracketIndex) + newMethod + '}\n';
  }

  File(path).writeAsStringSync(content);
  print("Updated PDF logic in consumption_report_screen.dart");
}
