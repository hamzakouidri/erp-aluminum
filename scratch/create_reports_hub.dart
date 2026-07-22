import 'dart:io';

void main() {
  String path = 'lib/Screen/reports_hub_screen.dart';
  
  String content = '''import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../settings/app_settings.dart';
import '../sql_database.dart';
import 'global_consumption_report_screen.dart';
import 'worker_finances_screen.dart';
import 'achat_screen.dart';
import 'suppliers_screen.dart';
import 'treasury_screen.dart';

class ReportsHubScreen extends StatelessWidget {
  final SqlDatabase db;

  const ReportsHubScreen({Key? key, required this.db}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<AppSettingsProvider>(context);

    // List of reports
    final List<Map<String, dynamic>> reports = [];

    // 1. Global Consumption Report
    if (settings.canViewStatistics()) {
      reports.add({
        'title': 'تقرير النواقص الشامل',
        'subtitle': 'نواقص كل الطلبيات (Aluminium, Verre, Acc)',
        'icon': Icons.inventory_2_rounded,
        'color': Colors.indigo,
        'onTap': () => Navigator.push(context, MaterialPageRoute(builder: (_) => GlobalConsumptionReportScreen(db: db))),
      });
    }

    // 2. Worker Finances (Salaries and Advances)
    if (settings.canViewStatistics()) { // Actually, statistics or a specific permission
      reports.add({
        'title': 'أجور وسلفيات العمال',
        'subtitle': 'إدارة رواتب العمال والخصم من الصندوق',
        'icon': Icons.engineering_rounded,
        'color': Colors.orange,
        'onTap': () => Navigator.push(context, MaterialPageRoute(builder: (_) => WorkerFinancesScreen(db: db))),
      });
    }

    // 3. Purchase Invoices
    if (settings.canRegisterPurchases()) {
      reports.add({
        'title': 'مشتريات الورشة',
        'subtitle': 'فواتير الشراء وإدارة المصاريف',
        'icon': Icons.shopping_cart_rounded,
        'color': Colors.teal,
        'onTap': () => Navigator.push(context, MaterialPageRoute(builder: (_) => AchatScreen(db: db))),
      });
    }

    // 4. Supplier Accounts
    if (settings.canViewSuppliers()) {
      reports.add({
        'title': 'حسابات الموردين',
        'subtitle': 'الديون ومدفوعات الموردين',
        'icon': Icons.local_shipping_rounded,
        'color': Colors.redAccent,
        'onTap': () => Navigator.push(context, MaterialPageRoute(builder: (_) => SuppliersScreen(db: db))),
      });
    }

    // 5. Treasury (Customer Payments & Expenses)
    if (settings.canAccessTreasury()) {
      reports.add({
        'title': 'الخزينة والمالية',
        'subtitle': 'الصندوق، مدفوعات الزبائن، والأرباح',
        'icon': Icons.account_balance_wallet_rounded,
        'color': Colors.green,
        'onTap': () => Navigator.push(context, MaterialPageRoute(builder: (_) => TreasuryScreen(db: db))),
      });
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: AppBar(
        title: const Text('مركز التقارير والمالية', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
      ),
      body: reports.isEmpty
          ? const Center(child: Text('لا توجد لديك صلاحيات لرؤية أي تقارير', style: TextStyle(fontSize: 18, color: Colors.grey)))
          : GridView.builder(
              padding: const EdgeInsets.all(16),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
                childAspectRatio: 0.9,
              ),
              itemCount: reports.length,
              itemBuilder: (context, index) {
                final report = reports[index];
                return _buildReportCard(report);
              },
            ),
    );
  }

  Widget _buildReportCard(Map<String, dynamic> report) {
    return GestureDetector(
      onTap: report['onTap'],
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE2E8F0)),
          boxShadow: [
            BoxShadow(
              color: report['color'].withOpacity(0.1),
              blurRadius: 10,
              offset: const Offset(0, 4),
            )
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: report['color'].withOpacity(0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(report['icon'], color: report['color'], size: 30),
              ),
              const SizedBox(height: 16),
              Text(
                report['title'],
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1E293B),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                report['subtitle'],
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 11,
                  color: Color(0xFF64748B),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
''';

  File(path).writeAsStringSync(content);
  print("Created reports_hub_screen.dart");
}
