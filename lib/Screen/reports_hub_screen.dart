import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../settings/app_settings.dart';
import '../sql_database.dart';
import 'global_consumption_report_screen.dart';
import 'worker_finances_screen.dart';
import 'achat_screen.dart';
import 'suppliers_screen.dart';
import 'treasury_screen.dart';
import 'worker_weekly_settlement_screen.dart';
import '../settings/localization.dart';

class ReportsHubScreen extends StatelessWidget {
  final SqlDatabase db;

  const ReportsHubScreen({Key? key, required this.db}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<AppSettingsProvider>(context);
    final lang = settings.language;

    // List of reports
    final List<Map<String, dynamic>> reports = [];

    // 1. Global Consumption Report
    if (settings.canViewStatistics()) {
      reports.add({
        'title': Localization.translate('تقرير النواقص الشامل', lang),
        'subtitle': Localization.translate('نواقص كل الطلبيات (Aluminium, Verre, Acc)', lang),
        'icon': Icons.inventory_2_rounded,
        'color': Colors.indigo,
        'onTap': () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => GlobalConsumptionReportScreen(db: db)),
        ),
      });
    }

    // 2. Worker Finances (Salaries and Advances)
    if (settings.canViewStatistics()) {
      reports.add({
        'title': Localization.translate('أجور وسلفيات العمال', lang),
        'subtitle': Localization.translate('إدارة رواتب العمال والخصم من الصندوق', lang),
        'icon': Icons.engineering_rounded,
        'color': Colors.orange,
        'onTap': () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => WorkerFinancesScreen(db: db)),
        ),
      });
    }

    // 2b. Worker Weekly Settlement (Calcul Hebdomadaire)
    if (settings.canViewStatistics()) {
      reports.add({
        'title': Localization.translate('المحاسبة الأسبوعية للعمال', lang),
        'subtitle': Localization.translate('حساب مستحقات العمال أسبوعياً ودفع الأجور', lang),
        'icon': Icons.calculate_rounded,
        'color': Colors.purple,
        'onTap': () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => WorkerWeeklySettlementScreen(db: db)),
        ),
      });
    }

    // 3. Purchase Invoices
    if (settings.canRegisterPurchases()) {
      reports.add({
        'title': Localization.translate('مشتريات الورشة', lang),
        'subtitle': Localization.translate('فواتير الشراء وإدارة المصاريف', lang),
        'icon': Icons.shopping_cart_rounded,
        'color': Colors.teal,
        'onTap': () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => AchatScreen(db: db)),
        ),
      });
    }

    // 4. Supplier Accounts
    if (settings.canViewSuppliers()) {
      reports.add({
        'title': Localization.translate('حسابات الموردين', lang),
        'subtitle': Localization.translate('الديون ومدفوعات الموردين', lang),
        'icon': Icons.local_shipping_rounded,
        'color': Colors.redAccent,
        'onTap': () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => SuppliersScreen(db: db)),
        ),
      });
    }

    // 5. Treasury (Customer Payments & Expenses)
    if (settings.canAccessTreasury()) {
      reports.add({
        'title': Localization.translate('الخزينة والمالية', lang),
        'subtitle': Localization.translate('الصندوق، مدفوعات الزبائن، والأرباح', lang),
        'icon': Icons.account_balance_wallet_rounded,
        'color': Colors.green,
        'onTap': () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => TreasuryScreen(db: db)),
        ),
      });
    }

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(
          Localization.translate('مركز التقارير والمالية', lang),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        backgroundColor: Theme.of(context).brightness == Brightness.dark
            ? Theme.of(context).appBarTheme.backgroundColor
            : Colors.white,
        surfaceTintColor: Colors.transparent,
      ),
      body: reports.isEmpty
          ? Center(
              child: Text(
                Localization.translate('لا توجد لديك صلاحيات لرؤية أي تقارير', lang),
                style: const TextStyle(fontSize: 18, color: Colors.grey),
              ),
            )
          : GridView.builder(
              padding: const EdgeInsets.all(16),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
                childAspectRatio: 0.78,
              ),
              itemCount: reports.length,
              itemBuilder: (context, index) {
                final report = reports[index];
                return _buildReportCard(context, report);
              },
            ),
    );
  }

  Widget _buildReportCard(BuildContext context, Map<String, dynamic> report) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: report['onTap'],
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
          ),
          boxShadow: [
            BoxShadow(
              color: (report['color'] as Color).withValues(alpha: 0.1),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 12.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: (report['color'] as Color).withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(report['icon'] as IconData, color: report['color'] as Color, size: 24),
              ),
              const SizedBox(height: 12),
              Text(
                report['title'] as String,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).textTheme.bodyLarge?.color,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                report['subtitle'] as String,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10,
                  color: Theme.of(context).textTheme.bodySmall?.color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
