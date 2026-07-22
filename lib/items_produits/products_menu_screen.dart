import 'package:flutter/material.dart';
import 'package:database_data/settings/localization.dart';
import 'package:database_data/settings/app_settings.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../sql_database.dart';
import 'glass.dart';
import 'shutters.dart';
import 'colors.dart';
import 'accessoires.dart';
import 'joint.dart';
import 'kit_bundles_screen.dart';
import 'catalogue_manager.dart';
import 'series_accessories_screen.dart';
import 'series_table_config_screen.dart';

class ProductsMenuScreen extends StatelessWidget {
  final SqlDatabase db;

  const ProductsMenuScreen({super.key, required this.db});

  @override
  Widget build(BuildContext context) {
    AppLanguage lang = Provider.of<AppSettingsProvider>(context).language;

    return Scaffold(
      appBar: AppBar(
        title: Text(Localization.translate("المنتجات", lang)),
        backgroundColor: Theme.of(context).brightness == Brightness.dark
            ? Theme.of(context).appBarTheme.backgroundColor
            : Colors.blue,
        centerTitle: true,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        child: Container(
          padding: const EdgeInsets.all(24.0),
          color: Theme.of(context).scaffoldBackgroundColor,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                Localization.translate(
                  "حدد فئة المنتجات التي تريد إدارتها",
                  lang,
                ),
                style: TextStyle(
                  fontFamily: GoogleFonts.cairo().fontFamily,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.white
                      : Theme.of(context).primaryColor,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              // البروفيلات والسيستمات
              _buildMenuCard(
                context,
                title: Localization.translate("البروفيلات والانظمة", lang),
                icon: Icons.format_shapes_rounded,
                color: Colors.blue,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => CatalogManagerScreen(db: db),
                    ),
                  );
                },
              ),
              const SizedBox(height: 16),
              _buildMenuCard(
                context,
                title: Localization.translate("زجاج", lang),
                icon: Icons.window_rounded,
                color: Colors.lightBlue,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => GlassScreen(db: db),
                    ),
                  );
                },
              ),
              const SizedBox(height: 16),
              _buildMenuCard(
                context,
                title: Localization.translate("ستار", lang),
                icon: Icons.view_sidebar_rounded,
                color: Colors.indigo,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => ShuttersScreen(db: db),
                    ),
                  );
                },
              ),
              const SizedBox(height: 16),
              _buildMenuCard(
                context,
                title: Localization.translate("الألوان", lang),
                icon: Icons.color_lens_rounded,
                color: Colors.purple,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => ColorsScreen(db: db),
                    ),
                  );
                },
              ),
              const SizedBox(height: 16),
              _buildMenuCard(
                context,
                title: Localization.translate("الإكسسوارات", lang),
                icon: Icons.construction_rounded,
                color: Colors.orange,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => AccessoriesScreen(db: db),
                    ),
                  );
                },
              ),
              const SizedBox(height: 16),
              _buildMenuCard(
                context,
                title: Localization.translate("إكسسوارات السلاسل", lang),
                icon: Icons.account_tree_rounded,
                color: Colors.deepOrange,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => SeriesAccessoriesScreen(db: db),
                    ),
                  );
                },
              ),
              const SizedBox(height: 16),
              _buildMenuCard(
                context,
                title: Localization.translate("الجوانات", lang),
                icon: Icons.line_weight_rounded,
                color: Colors.teal,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => JointsScreen(db: db),
                    ),
                  );
                },
              ),
              const SizedBox(height: 16),
              _buildMenuCard(
                context,
                title: Localization.translate("مجموعات الكيت (Kit)", lang),
                icon: Icons.inventory_2_rounded,
                color: Colors.deepPurple,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => KitBundlesScreen(db: db),
                    ),
                  );
                },
              ),
              const SizedBox(height: 16),
              _buildMenuCard(
                context,
                title: Localization.translate("تخصيص جدول الكمية والتكلفة", lang),
                icon: Icons.table_chart_rounded,
                color: Colors.green,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => SeriesTableConfigScreen(db: db),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMenuCard(
    BuildContext context, {
    required String title,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 24),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.1),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
          border: Border.all(color: color.withValues(alpha: 0.3), width: 1.5),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 28),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontFamily: GoogleFonts.cairo().fontFamily,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).textTheme.bodyLarge?.color,
                ),
              ),
            ),
            Icon(
              Icons.arrow_forward_ios_rounded,
              color: Colors.grey.shade400,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}
