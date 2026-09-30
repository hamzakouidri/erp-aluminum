import 'package:flutter/material.dart';
import 'package:database_data/settings/localization.dart';
import 'package:database_data/settings/app_settings.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../sql_database.dart';
import '../services/cloud_sync_service.dart';
import 'glass.dart';
import 'shutters.dart';
import 'colors.dart';
import 'accessoires.dart';
import 'joint.dart';
import 'kit_bundles_screen.dart';
import 'catalogue_manager.dart';
import 'catalog_rules_screen.dart';
import 'series_accessories_screen.dart';
import 'series_table_config_screen.dart';

class ProductsMenuScreen extends StatefulWidget {
  final SqlDatabase db;

  const ProductsMenuScreen({super.key, required this.db});

  @override
  State<ProductsMenuScreen> createState() => _ProductsMenuScreenState();
}

class _ProductsMenuScreenState extends State<ProductsMenuScreen> {
  bool _isSyncing = false;
  bool _hasLoadedCloudCatalog = false;
  Future<void>? _catalogSyncFuture;

  @override
  void initState() {
    super.initState();
    // ✅ مزامنة تلقائية من السحابة عند فتح الصفحة لضمان رؤية العامل لكل المنتجات
    // Keep product cards backed by the central catalog. Do not let a locally
    // created fallback catalog win over the cloud catalog.
    // A full import is manual. Running it while this page is rebuilt resets
    // the list position and keeps the progress indicator active.
  }

  Future<void> _syncFromCloud({bool force = false}) {
    if (!force && _hasLoadedCloudCatalog) return Future.value();
    return _catalogSyncFuture ??= _downloadCloudCatalog();
  }

  Future<void> _downloadCloudCatalog() async {
    setState(() => _isSyncing = true);
    try {
      // restoreFromCloud() restores a workshop backup. These product cards
      // must use the catalog that is published in global_catalog instead.
      await CloudSyncService().downloadGlobalCatalog();
      _hasLoadedCloudCatalog = true;
    } catch (e) {
      debugPrint('Products menu cloud sync failed: $e');
    } finally {
      _catalogSyncFuture = null;
      if (mounted) {
        setState(() => _isSyncing = false);
      }
    }
  }

  Future<void> _openCloudCatalogPage(Widget Function() pageBuilder) async {
    try {
      // Never block the product pages on the server. They open from the
      // current local workshop catalogue and redraw when the background
      // download finishes.
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => pageBuilder()),
      );
    } catch (e) {
      if (!mounted) return;
      final message = e.toString().replaceFirst('Exception: ', '');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            message.isEmpty
                ? 'تعذر تحميل كتالوج الورشة؛ لم تُفتح الصفحة لتجنب عرض بيانات قديمة.'
                : message,
          ),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<AppSettingsProvider>(context);
    final bool isAllowed =
        settings.isManager || settings.canViewMyAccreditations();
    final AppLanguage lang = settings.language;

    if (!isAllowed) {
      return Scaffold(
        appBar: AppBar(
          title: Text(Localization.translate("المنتجات", lang)),
          backgroundColor: Theme.of(context).brightness == Brightness.dark
              ? Theme.of(context).appBarTheme.backgroundColor
              : Colors.blue,
          centerTitle: true,
          elevation: 0,
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Text(
              Localization.translate(
                'عذراً، ليس لديك صلاحية للوصول إلى هذه الشاشة.',
                lang,
              ),
              textAlign: TextAlign.center,
              style: const TextStyle(fontFamily: 'Cairo', fontSize: 16),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(Localization.translate("المنتجات", lang)),
        backgroundColor: Theme.of(context).brightness == Brightness.dark
            ? Theme.of(context).appBarTheme.backgroundColor
            : Colors.blue,
        centerTitle: true,
        elevation: 0,
        actions: [
          if (settings.canSyncGlobalCatalog())
            _isSyncing
                ? const Padding(
                    padding: EdgeInsets.all(14),
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    ),
                  )
                : IconButton(
                    icon: const Icon(Icons.cloud_download_rounded),
                    tooltip: Localization.translate(
                      'مزامنة واستيراد الكتالوج العالمي من السحابة',
                      lang,
                    ),
                    onPressed: () =>
                        _syncFromCloud(force: true).catchError((_) {}),
                  ),
        ],
      ),
      body: SingleChildScrollView(
        key: const PageStorageKey<String>('products-menu-scroll'),
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
              // \u0627\u0644\u0628\u0631\u0648\u0641\u064a\u0644\u0627\u062a \u0648\u0627\u0644\u0633\u064a\u0633\u062a\u0645\u0627\u062a
              if (settings.canViewProfiles()) ...[
                _buildMenuCard(
                  context,
                  title: Localization.translate(
                    "\u0627\u0644\u0628\u0631\u0648\u0641\u064a\u0644\u0627\u062a \u0648\u0627\u0644\u0627\u0646\u0638\u0645\u0629",
                    lang,
                  ),
                  icon: Icons.format_shapes_rounded,
                  color: Colors.blue,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) =>
                            CatalogManagerScreen(db: widget.db),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 16),
              ],
              // Keep this administrator setup close to the catalogue entry so
              // it is visible immediately in the desktop products screen.
              if (settings.isAdmin) ...[
                _buildMenuCard(
                  context,
                  title: _seriesDesignTitle(lang),
                  icon: Icons.architecture_rounded,
                  color: Colors.green,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) =>
                            SeriesTableConfigScreen(db: widget.db),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 16),
              ],
              if (settings.isAdmin || settings.canViewAccessories()) ...[
                _buildMenuCard(
                  context,
                  title: _catalogRulesTitle(lang),
                  icon: Icons.rule_rounded,
                  color: Colors.blueGrey,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => CatalogRulesScreen(db: widget.db),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 16),
              ],
              if (settings.canViewGlass()) ...[
                _buildMenuCard(
                  context,
                  title: Localization.translate(
                    "\u0632\u062c\u0627\u062c",
                    lang,
                  ),
                  icon: Icons.window_rounded,
                  color: Colors.lightBlue,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => GlassScreen(db: widget.db),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 16),
              ],
              if (settings.canViewShutters()) ...[
                _buildMenuCard(
                  context,
                  title: Localization.translate(
                    "\u0633\u062a\u0627\u0631",
                    lang,
                  ),
                  icon: Icons.view_sidebar_rounded,
                  color: Colors.indigo,
                  onTap: () => _openCloudCatalogPage(
                    () => ShuttersScreen(db: widget.db),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              if (settings.canViewColors()) ...[
                _buildMenuCard(
                  context,
                  title: Localization.translate(
                    "\u0627\u0644\u0623\u0644\u0648\u0627\u0646",
                    lang,
                  ),
                  icon: Icons.color_lens_rounded,
                  color: Colors.purple,
                  onTap: () =>
                      _openCloudCatalogPage(() => ColorsScreen(db: widget.db)),
                ),
                const SizedBox(height: 16),
              ],
              if (settings.canViewAccessories()) ...[
                _buildMenuCard(
                  context,
                  title: Localization.translate(
                    "\u0627\u0644\u0625\u0643\u0633\u0633\u0648\u0627\u0631\u0627\u062a",
                    lang,
                  ),
                  icon: Icons.construction_rounded,
                  color: Colors.orange,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => AccessoriesScreen(db: widget.db),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 16),
              ],
              if (settings.canViewSeriesAccessories()) ...[
                _buildMenuCard(
                  context,
                  title: Localization.translate(
                    "\u0625\u0643\u0633\u0633\u0648\u0627\u0631\u0627\u062a \u0627\u0644\u0633\u0644\u0627\u0633\u0644",
                    lang,
                  ),
                  icon: Icons.account_tree_rounded,
                  color: Colors.deepOrange,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) =>
                            SeriesAccessoriesScreen(db: widget.db),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 16),
              ],
              if (settings.canViewJoints()) ...[
                _buildMenuCard(
                  context,
                  title: Localization.translate(
                    "\u0627\u0644\u062c\u0648\u0627\u0646\u0627\u062a",
                    lang,
                  ),
                  icon: Icons.line_weight_rounded,
                  color: Colors.teal,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => JointsScreen(db: widget.db),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 16),
              ],
              if (settings.canViewKitBundles()) ...[
                _buildMenuCard(
                  context,
                  title: Localization.translate(
                    "\u0645\u062c\u0645\u0648\u0639\u0627\u062a \u0627\u0644\u0643\u064a\u062a (Kit)",
                    lang,
                  ),
                  icon: Icons.inventory_2_rounded,
                  color: Colors.deepPurple,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => KitBundlesScreen(db: widget.db),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 16),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _seriesDesignTitle(AppLanguage language) => switch (language) {
    AppLanguage.arabic => 'مكوّنات وحسابات السلسلة',
    AppLanguage.french => 'Composants et calculs de la série',
    AppLanguage.english => 'Series components and calculations',
  };

  String _catalogRulesTitle(AppLanguage language) => switch (language) {
    AppLanguage.arabic => 'قواعد الكتالوج العامة',
    AppLanguage.french => 'Règles du catalogue',
    AppLanguage.english => 'Catalog rules',
  };

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
