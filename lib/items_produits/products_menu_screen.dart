import 'package:flutter/material.dart';
import 'package:database_data/settings/localization.dart';
import 'package:database_data/settings/app_settings.dart';
import 'package:provider/provider.dart';

import '../sql_database.dart';
import 'catalogue_manager.dart';
import 'glass.dart';
import 'shutters.dart';
import 'colors.dart';
import 'accessoires.dart';
import 'joint.dart';

class ProductsMenuScreen extends StatelessWidget {
  final SqlDatabase db;

  const ProductsMenuScreen({super.key, required this.db});

  @override
  Widget build(BuildContext context) {
    AppLanguage lang = Provider.of<AppSettingsProvider>(context).language;

    return Scaffold(
      appBar: AppBar(
        title: Text(Localization.translate("المنتجات", lang)),
        backgroundColor: Colors.blue, centerTitle: true,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        child: Container(
          padding: const EdgeInsets.all(24.0),
          decoration: BoxDecoration(color: Colors.grey[100]),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                Localization.translate(
                  "حدد فئة المنتجات التی تريد إدارتها",
                  lang,
                ),
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.blue.shade900,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            _buildMenuCard(
              context,
              title: Localization.translate("بروفيلات الألمنیوم", lang),
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
                  MaterialPageRoute(builder: (context) => GlassScreen(db: db)),
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
                  MaterialPageRoute(builder: (context) => ColorsScreen(db: db)),
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
              title: Localization.translate("الجوانات", lang),
              icon: Icons.line_weight_rounded,
              color: Colors.teal,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => JointsScreen(db: db)),
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
          color: Colors.white,
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
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
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
