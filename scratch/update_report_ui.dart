import 'dart:io';

void main() {
  String path = 'lib/Screen/consumption_report_screen.dart';
  String content = File(path).readAsStringSync();

  // 1. Update the AppBar to add the "Buy" button
  String oldAppBar = '''      appBar: AppBar(
        title: Text('تقرير الاستهلاك - \${widget.clientName}', style: const TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.picture_as_pdf),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('سيتم تفعيل ميزة تصدير PDF لاحقاً')),
              );
            },
          ),
        ],
      ),''';

  String newAppBar = '''      appBar: AppBar(
        title: Text('تقرير الاستهلاك - \${widget.clientName}', style: const TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        actions: [
          ElevatedButton.icon(
            icon: const Icon(Icons.shopping_cart, color: Colors.white),
            label: const Text("شراء النواقص", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () {
              // TODO: Navigate to Purchase List UI
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('سيتم تفعيل ميزة شراء النواقص لاحقاً')),
              );
            },
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.picture_as_pdf),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('سيتم تفعيل ميزة تصدير PDF لاحقاً')),
              );
            },
          ),
        ],
      ),''';
      
  content = content.replaceFirst(oldAppBar, newAppBar);

  // 2. Update the DataRow text color based on isMissing
  String oldDataRow = '''              rows: items.map((item) {
                return DataRow(cells: [
                  DataCell(Text(item.name)),
                  DataCell(Text(item.width > 0 ? item.width.toStringAsFixed(1) : '-')),
                  DataCell(Text(item.height > 0 ? item.height.toStringAsFixed(1) : '-')),
                  DataCell(Text(item.quantity.toString(), style: const TextStyle(fontWeight: FontWeight.bold))),
                ]);
              }).toList(),''';

  String newDataRow = '''              rows: items.map((item) {
                final textColor = item.isMissing ? Colors.red : Colors.black87;
                final textStyle = TextStyle(color: textColor);
                return DataRow(cells: [
                  DataCell(Text(item.name, style: textStyle)),
                  DataCell(Text(item.width > 0 ? item.width.toStringAsFixed(1) : '-', style: textStyle)),
                  DataCell(Text(item.height > 0 ? item.height.toStringAsFixed(1) : '-', style: textStyle)),
                  DataCell(Text(item.quantity.toString(), style: TextStyle(fontWeight: FontWeight.bold, color: textColor))),
                ]);
              }).toList(),''';

  content = content.replaceFirst(oldDataRow, newDataRow);

  File(path).writeAsStringSync(content);
  print("Updated UI in consumption_report_screen.dart");
}
