import 'package:flutter/material.dart';
import '../sql_database.dart';
import 'package:database_data/settings/localization.dart';
import 'package:database_data/settings/app_settings.dart';
import 'package:provider/provider.dart';


import 'colors.dart';
import 'accessoires.dart';
import 'joint.dart';
import 'glass.dart';
import 'shutters.dart';
import 'kit_bundles_screen.dart';
import 'series_requirements_report_screen.dart';

class ProduitsDashboard extends StatelessWidget {
  final SqlDatabase db;
  const ProduitsDashboard({super.key, required this.db});

  Widget _buildMenuCard(
    BuildContext context,
    String titleKey,
    IconData icon,
    Widget targetScreen,
  ) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => targetScreen),
          );
        },
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 48, color: Colors.blue),
              SizedBox(height: 12),
              Text(
                Localization.translate(
                  titleKey,
                  Provider.of<AppSettingsProvider>(context).language,
                ),
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          Localization.translate(
            'المنتجات',
            Provider.of<AppSettingsProvider>(context).language,
          ),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: GridView.count(
          crossAxisCount: 2,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
          children: [
            _buildMenuCard(
              context,
              'إدارة الإكسسوارات',
              Icons.build_circle,
              AccessoriesScreen(db: db),
            ),
            _buildMenuCard(
              context,
              'إدارة الزجاج',
              Icons.window,
              GlassScreen(db: db),
            ),
            _buildMenuCard(
              context,
              'الجوانات / الجلدات',
              Icons.line_style,
              JointsScreen(db: db),
            ),
            _buildMenuCard(
              context,
              'إدارة الستائر',
              Icons.blinds,
              ShuttersScreen(db: db),
            ),
            _buildMenuCard(
              context,
              'الألوان',
              Icons.color_lens,
              ColorsScreen(db: db),
            ),
            _buildMenuCard(
              context,
              'مجموعات الكيت (Kit)',
              Icons.inventory_2_outlined,
              KitBundlesScreen(db: db),
            ),
            if (Provider.of<AppSettingsProvider>(context)
                .canViewSeriesRequirementsReport())
              _buildMenuCard(
                context,
                'تقارير متطلبات واستعمال السلاسل',
                Icons.analytics_outlined,
                SeriesRequirementsReportScreen(db: db),
              ),
          ],
        ),
      ),
    );
  }
}
