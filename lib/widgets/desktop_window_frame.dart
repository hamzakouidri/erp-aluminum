import 'dart:io';

import 'package:database_data/Cliente/client.dart';
import 'package:database_data/Commande/commande.dart';
import 'package:database_data/Screen/achat_screen.dart';
import 'package:database_data/Screen/app_workspace_shell.dart';
import 'package:database_data/Screen/client_chrono_search_screen.dart';
import 'package:database_data/Screen/distribution_tracking_screen.dart';
import 'package:database_data/Screen/global_consumption_report_screen.dart';
import 'package:database_data/Screen/inventory_screen.dart';
import 'package:database_data/Screen/material_remnants_screen.dart';
import 'package:database_data/Screen/material_sales_screen.dart';
import 'package:database_data/Screen/price_management_screen.dart';
import 'package:database_data/Screen/sales_screen.dart';
import 'package:database_data/Screen/selected_systems_screen.dart';
import 'package:database_data/Screen/settings_screen.dart';
import 'package:database_data/Screen/storage_dashboard_screen.dart';
import 'package:database_data/Screen/support_dialog.dart';
import 'package:database_data/Screen/suppliers_screen.dart';
import 'package:database_data/Screen/treasury_screen.dart';
import 'package:database_data/Screen/worker_finances_screen.dart';
import 'package:database_data/Screen/worker_weekly_settlement_screen.dart';
import 'package:database_data/Screen/worker_tasks_screen.dart';
import 'package:database_data/Screen/worker_archive_screen.dart';
import 'package:database_data/Screen/electronic_payment_screen.dart';
import 'package:database_data/Screen/subscription_review_dialog.dart';
import 'package:database_data/Screen/workers_management_screen.dart';
import 'package:database_data/Screen/workshop_profile_screen.dart';
import 'package:database_data/items_produits/products_menu_screen.dart';
import 'package:database_data/services/auth_service.dart';
import 'package:database_data/services/cloud_sync_service.dart';
import 'package:database_data/services/supabase_workshop_sync_service.dart';
import 'package:database_data/sql_database.dart';
import 'package:database_data/widgets/app_material.dart';
import 'package:window_manager/window_manager.dart';
import 'package:provider/provider.dart';
import '../settings/app_settings.dart';
import '../settings/localization.dart';

/// The Windows caption area is drawn by Flutter so the window controls remain
/// visible even when the pointer is not hovering over the title bar.
class DesktopWindowFrame extends StatefulWidget {
  final Widget child;
  final Widget? topBar;

  /// Called when a menu item requests opening a workspace entry.
  /// Signature matches [WorkspaceController.open].
  final void Function(String title, IconData icon, Widget screen)? onOpen;

  const DesktopWindowFrame({
    super.key,
    required this.child,
    this.topBar,
    this.onOpen,
  });

  @override
  State<DesktopWindowFrame> createState() => _DesktopWindowFrameState();
}

class _DesktopWindowFrameState extends State<DesktopWindowFrame>
    with WindowListener {
  bool _isMaximized = false;
  bool _isFullScreen = false;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _readWindowState());
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowMaximize() {
    if (mounted) setState(() => _isMaximized = true);
  }

  @override
  void onWindowUnmaximize() {
    if (mounted) setState(() => _isMaximized = false);
  }

  @override
  void onWindowRestore() {
    _readWindowState();
  }

  @override
  void onWindowResize() {
    _readWindowState();
  }

  Future<void> _readWindowState() async {
    try {
      final bounds = await windowManager.getBounds();
      final isMax = await windowManager.isMaximized();
      final effectivelyMax =
          isMax && (bounds.width >= 1400 || bounds.height >= 900);
      if (mounted && _isMaximized != effectivelyMax) {
        setState(() => _isMaximized = effectivelyMax);
      }
    } catch (_) {}
  }

  Future<void> _toggleMaximize() async {
    try {
      final bounds = await windowManager.getBounds();
      final isMax = await windowManager.isMaximized();
      final effectivelyMax =
          isMax && (bounds.width >= 1400 || bounds.height >= 900);
      if (effectivelyMax) {
        await windowManager.unmaximize();
        if (mounted) setState(() => _isMaximized = false);
      } else {
        await windowManager.maximize();
        if (mounted) setState(() => _isMaximized = true);
      }
    } catch (e) {
      debugPrint('Error toggling maximize: $e');
    }
  }

  @override
  void onWindowClose() async {
    try {
      await windowManager.destroy();
    } catch (_) {}
    exit(0);
  }

  Future<void> _closeApp() async {
    try {
      await windowManager.destroy();
    } catch (_) {}
    exit(0);
  }

  Future<void> _toggleFullScreen() async {
    final next = !_isFullScreen;
    await windowManager.setFullScreen(next);
    if (mounted) setState(() => _isFullScreen = next);
  }

  Future<void> _signOut() async {
    try {
      final workspace = context.read<WorkspaceController>();
      workspace.resetForSignedOut();
      await AppAuthService().signOut();
      await AppAuthService().signOutGoogleSession();
      CloudSyncService().reset();
      SupabaseWorkshopSyncService().stop();
      await CloudSyncService().clearCachedWorkshopContext();
    } catch (error) {
      debugPrint('Sign out error: $error');
    }
  }

  void _showAbout() {
    showAboutDialog(
      context: context,
      applicationName: Localization.translate(
        'ورشتي',
        Provider.of<AppSettingsProvider>(context, listen: false).language,
      ),
      applicationVersion: Provider.of<AppSettingsProvider>(
        context,
        listen: false,
      ).appVersion,
      applicationIcon: Image.asset(
        'web/favicon.png',
        width: 54,
        height: 54,
        fit: BoxFit.contain,
      ),
    );
  }

  /// Safely invoke [widget.onOpen].
  void _open(String title, IconData icon, Widget screen) {
    widget.onOpen?.call(title, icon, screen);
  }

  String _label(
    AppLanguage language, {
    required String arabic,
    required String french,
    required String english,
  }) {
    return switch (language) {
      AppLanguage.arabic => arabic,
      AppLanguage.french => french,
      _ => english,
    };
  }

  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<AppSettingsProvider>(context);
    final lang = settings.language;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final foreground = isDark ? Colors.white : const Color(0xFF172033);
    final background = isDark ? const Color(0xFF111827) : Colors.white;
    final db = SqlDatabase();

    final allowWorkshop = settings.isWorkingInWorkshop;
    final allowStore = settings.isWorkingInStore;

    // ── Fichier (ملف) ────────────────────────────────────────────────────────
    final fichierItems = <_DesktopMenuItem>[
      _DesktopMenuItem(
        label: Localization.translate('الصفحة الرئيسية', lang),
        icon: Icons.home_rounded,
        onSelected: () {
          context.read<WorkspaceController>().activateHome();
        },
      ),
      _DesktopMenuItem(
        label: Localization.translate('deconnexion', lang),
        icon: Icons.logout_rounded,
        onSelected: _signOut,
      ),
      _DesktopMenuItem(
        label: _label(
          lang,
          arabic: 'إغلاق التطبيق',
          french: "Quitter l'application",
          english: 'Exit application',
        ),
        icon: Icons.close_rounded,
        onSelected: _closeApp,
      ),
    ];

    // ── Vente (المبيعات والزبائن) ───────────────────────────────────────────
    final venteItems = <_DesktopMenuItem>[
      if (allowWorkshop && settings.canViewOrders())
        _DesktopMenuItem(
          label: Localization.translate('commandes', lang),
          icon: Icons.receipt_long_rounded,
          onSelected: () =>
              _open('commandes', Icons.receipt_long_rounded, Commande()),
        ),
      if (allowStore && settings.canMaterialSales())
        _DesktopMenuItem(
          label: _label(
            lang,
            arabic: 'طلب وبيع المواد',
            french: 'Commande & Vente Matériaux',
            english: 'Material orders & sales',
          ),
          icon: Icons.storefront_rounded,
          onSelected: () => _open(
            'material_sales',
            Icons.storefront_rounded,
            MaterialSalesScreen(db: db),
          ),
        ),
      if (allowWorkshop && settings.canViewSales())
        _DesktopMenuItem(
          label: Localization.translate('vente', lang),
          icon: Icons.point_of_sale_rounded,
          onSelected: () => _open(
            Localization.translate('vente', lang),
            Icons.point_of_sale_rounded,
            SalesScreen(db: db),
          ),
        ),
      if (settings.canViewClients())
        _DesktopMenuItem(
          label: Localization.translate('clients', lang),
          icon: Icons.groups_rounded,
          onSelected: () => _open(
            'clients',
            Icons.groups_rounded,
            Customers(
              storeOnly:
                  settings.workingSection == WorkingSection.materialsStore,
            ),
          ),
        ),
      if (settings.workingSection != WorkingSection.materialsStore &&
          settings.canViewClientLedger())
        _DesktopMenuItem(
          label: Localization.translate('كشف حساب الزبائن', lang),
          icon: Icons.history_edu_rounded,
          onSelected: () => _open(
            Localization.translate('كشف حساب الزبائن', lang),
            Icons.history_edu_rounded,
            const ClientChronoSearchScreen(),
          ),
        ),
      if (allowWorkshop && settings.canAccessDistributionTracking())
        _DesktopMenuItem(
          label: _label(
            lang,
            arabic: 'التوزيع والتتبع',
            french: 'Distribution et suivi',
            english: 'Distribution and tracking',
          ),
          icon: Icons.local_shipping_rounded,
          onSelected: () => _open(
            'distribution_tracking',
            Icons.local_shipping_rounded,
            const DistributionTrackingScreen(),
          ),
        ),
    ];

    // ── Achat (المشتريات والموردون) ─────────────────────────────────────────
    final achatItems = <_DesktopMenuItem>[
      if (allowWorkshop && settings.canAccessWorkshopPurchases())
        _DesktopMenuItem(
          label: Localization.translate(
            settings.isDualActivity ? 'مشتريات الورشة' : 'المشتريات',
            lang,
          ),
          icon: Icons.precision_manufacturing_rounded,
          onSelected: () => _open(
            'achat_workshop',
            Icons.precision_manufacturing_rounded,
            AchatScreen(db: db, isWorkshop: true),
          ),
        ),
      if (allowStore && settings.canAccessStorePurchases())
        _DesktopMenuItem(
          label: Localization.translate(
            settings.isDualActivity ? 'مشتريات محل المواد' : 'المشتريات',
            lang,
          ),
          icon: Icons.shopping_bag_rounded,
          onSelected: () => _open(
            'achat_store',
            Icons.shopping_bag_rounded,
            AchatScreen(db: db, isWorkshop: false),
          ),
        ),
      if (settings.canViewSuppliers())
        _DesktopMenuItem(
          label: _label(
            lang,
            arabic: 'الموردون',
            french: 'Fournisseurs',
            english: 'Suppliers',
          ),
          icon: Icons.local_shipping_rounded,
          onSelected: () => _open(
            'الموردين',
            Icons.local_shipping_rounded,
            SuppliersScreen(db: db),
          ),
        ),
    ];

    // ── Stock (المخزون والمنتجات) ───────────────────────────────────────────
    final stockItems = <_DesktopMenuItem>[
      if (settings.canViewMyAccreditations())
        _DesktopMenuItem(
          label: Localization.translate('produits', lang),
          icon: Icons.category_rounded,
          onSelected: () => _open(
            'produits',
            Icons.category_rounded,
            ProductsMenuScreen(db: db),
          ),
        ),
      if (settings.canAccessInventory()) ...[
        if (allowWorkshop)
          _DesktopMenuItem(
            label: Localization.translate(
              settings.isDualActivity ? 'مخزون الورشة' : 'المخزون',
              lang,
            ),
            icon: Icons.precision_manufacturing_rounded,
            onSelected: () => _open(
              'inventory_workshop',
              Icons.precision_manufacturing_rounded,
              InventoryScreen(db: db, isWorkshop: true),
            ),
          ),
        if (allowStore)
          _DesktopMenuItem(
            label: Localization.translate(
              settings.isDualActivity ? 'مخزون محل المواد' : 'المخزون',
              lang,
            ),
            icon: Icons.warehouse_rounded,
            onSelected: () => _open(
              'inventory_store',
              Icons.warehouse_rounded,
              InventoryScreen(db: db, isWorkshop: false),
            ),
          ),
      ],
      if (allowWorkshop && settings.canAccessInventory())
        _DesktopMenuItem(
          label: _label(
            lang,
            arabic: 'إدارة فضلات الألواح والمقاطع',
            french: 'Gestion des chutes (Panneaux & Profilés)',
            english: 'Remnants management',
          ),
          icon: Icons.recycling_rounded,
          onSelected: () => _open(
            'material_remnants',
            Icons.recycling_rounded,
            const MaterialRemnantsScreen(),
          ),
        ),
      if (allowWorkshop && settings.canViewGlobalConsumption())
        _DesktopMenuItem(
          label: Localization.translate('تقرير النواقص الشامل', lang),
          icon: Icons.inventory_2_rounded,
          onSelected: () => _open(
            'global_consumption',
            Icons.inventory_2_rounded,
            GlobalConsumptionReportScreen(db: db),
          ),
        ),
    ];

    // ── Tâche (المهام والتنفيذ) ──────────────────────────────────────────────
    final tacheItems = <_DesktopMenuItem>[
      if (allowWorkshop) ...[
        _DesktopMenuItem(
          label: _label(
            lang,
            arabic: 'مهام العمال',
            french: 'Tâches des ouvriers',
            english: 'Worker tasks',
          ),
          icon: Icons.engineering_rounded,
          onSelected: () => _open(
            'worker_tasks',
            Icons.engineering_rounded,
            WorkerTasksScreen(db: db),
          ),
        ),
        _DesktopMenuItem(
          label: _label(
            lang,
            arabic: 'أرشيف مهام العمال',
            french: 'Archive des tâches',
            english: 'Tasks archive',
          ),
          icon: Icons.archive_rounded,
          onSelected: () => _open(
            'worker_archive',
            Icons.archive_rounded,
            WorkerArchiveScreen(db: db),
          ),
        ),
        if (settings.canAccessDistributionTracking())
          _DesktopMenuItem(
            label: _label(
              lang,
              arabic: 'التوزيع والتتبع',
              french: 'Distribution et suivi',
              english: 'Distribution and tracking',
            ),
            icon: Icons.local_shipping_rounded,
            onSelected: () => _open(
              'distribution_tracking',
              Icons.local_shipping_rounded,
              const DistributionTrackingScreen(),
            ),
          ),
      ],
    ];

    // ── Trésorerie (الخزينة والصناديق والأجور) ────────────────────────────────
    final tresorerieItems = <_DesktopMenuItem>[
      if (settings.canAccessTreasury()) ...[
        _DesktopMenuItem(
          label: Localization.translate('caisse', lang),
          icon: Icons.account_balance_wallet_rounded,
          onSelected: () => _open(
            'caisse',
            Icons.account_balance_wallet_rounded,
            TreasuryScreen(db: db),
          ),
        ),
        _DesktopMenuItem(
          label: _label(
            lang,
            arabic: 'قبض جديد (Encaissement)',
            french: 'Encaissement',
            english: 'Encashment / Income',
          ),
          icon: Icons.arrow_downward_rounded,
          onSelected: () => TreasuryScreen.showQuickTransactionDialog(
            context,
            db: db,
            initialType: 'Encaissement',
          ),
        ),
        _DesktopMenuItem(
          label: _label(
            lang,
            arabic: 'دفع جديد (Décaissement)',
            french: 'Décaissement',
            english: 'Disbursement / Expense',
          ),
          icon: Icons.arrow_upward_rounded,
          onSelected: () => TreasuryScreen.showQuickTransactionDialog(
            context,
            db: db,
            initialType: 'Décaissement',
          ),
        ),
      ],
      if (settings.canViewWorkerFinances())
        _DesktopMenuItem(
          label: Localization.translate('إدارة شؤون وأجور العمال', lang),
          icon: Icons.people_alt_rounded,
          onSelected: () => _open(
            'worker_finances',
            Icons.people_alt_rounded,
            WorkerFinancesScreen(db: db),
          ),
        ),
      if (settings.canViewWorkerWeeklySettlement())
        _DesktopMenuItem(
          label: Localization.translate('المحاسبة الأسبوعية للعمال', lang),
          icon: Icons.calculate_rounded,
          onSelected: () => _open(
            'worker_settlement',
            Icons.calculate_rounded,
            WorkerWeeklySettlementScreen(db: db),
          ),
        ),
    ];

    // ── Compte (الحسابات والاشتراكات وإدارة الحسابات) ────────────────────────
    final compteItems = <_DesktopMenuItem>[
      if (settings.canViewSubscription()) ...[
        _DesktopMenuItem(
          label: _label(
            lang,
            arabic: 'اشتراكي (Mon abonnement)',
            french: 'Mon abonnement',
            english: 'My subscription',
          ),
          icon: Icons.card_membership_rounded,
          onSelected: () => showSubscriptionReviewDialog(context),
        ),
        _DesktopMenuItem(
          label: _label(
            lang,
            arabic: 'الدفع الإلكتروني وتجديد الاشتراك (Payment online)',
            french: 'Paiement en ligne & abonnements',
            english: 'Online payment & renewals',
          ),
          icon: Icons.credit_card_rounded,
          onSelected: () => _open(
            'electronic_payment',
            Icons.credit_card_rounded,
            const ElectronicPaymentScreen(),
          ),
        ),
      ],
      if (settings.canManageWorkers())
        _DesktopMenuItem(
          label: _label(
            lang,
            arabic: 'إدارة حسابات وصلاحيات المستخدمين',
            french: 'Gestion des comptes et utilisateurs',
            english: 'Manage accounts and users',
          ),
          icon: Icons.manage_accounts_rounded,
          onSelected: () => _open(
            'worker_management',
            Icons.manage_accounts_rounded,
            WorkersManagementScreen(db: db),
          ),
        ),
      if (settings.canViewWorkerFinances())
        _DesktopMenuItem(
          label: _label(
            lang,
            arabic: 'إدارة شؤون وأجور العمال',
            french: 'Gestion financière des ouvriers',
            english: 'Worker finances',
          ),
          icon: Icons.people_alt_rounded,
          onSelected: () => _open(
            'worker_finances',
            Icons.people_alt_rounded,
            WorkerFinancesScreen(db: db),
          ),
        ),
      _DesktopMenuItem(
        label: _label(
          lang,
          arabic: 'معلومات وحساب الورشة',
          french: "Profil et compte de l'atelier",
          english: 'Workshop profile and account',
        ),
        icon: Icons.storefront_rounded,
        onSelected: () => _open(
          'workshop_profile',
          Icons.storefront_rounded,
          const WorkshopProfileScreen(),
        ),
      ),
    ];

    // ── Affichage (العرض والمظهر والشريط) ────────────────────────────────────
    final affichageItems = <_DesktopMenuItem>[
      _DesktopMenuItem(
        label: isDark
            ? _label(
                lang,
                arabic: 'الوضع الفاتح',
                french: 'Mode clair',
                english: 'Light mode',
              )
            : _label(
                lang,
                arabic: 'الوضع الداكن',
                french: 'Mode sombre',
                english: 'Dark mode',
              ),
        icon: isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
        onSelected: () => Provider.of<AppSettingsProvider>(
          context,
          listen: false,
        ).setTheme(isDark ? ThemeMode.light : ThemeMode.dark),
      ),
      _DesktopMenuItem(
        label: _isFullScreen
            ? _label(
                lang,
                arabic: 'إلغاء ملء الشاشة',
                french: 'Quitter le plein écran',
                english: 'Exit full screen',
              )
            : _label(
                lang,
                arabic: 'ملء الشاشة',
                french: 'Plein écran',
                english: 'Full screen',
              ),
        icon: _isFullScreen
            ? Icons.fullscreen_exit_rounded
            : Icons.fullscreen_rounded,
        onSelected: _toggleFullScreen,
      ),
      _DesktopMenuItem(
        label: context.watch<WorkspaceController>().isSidebarOpen
            ? _label(
                lang,
                arabic: 'إخفاء القائمة الجانبية',
                french: 'Masquer le menu',
                english: 'Hide sidebar',
              )
            : _label(
                lang,
                arabic: 'إظهار القائمة الجانبية',
                french: 'Afficher le menu',
                english: 'Show sidebar',
              ),
        icon: Icons.view_sidebar_rounded,
        onSelected: () {
          context.read<WorkspaceController>().toggleSidebar();
        },
      ),
    ];

    // ── Paramètres (الإعدادات والإدارة) ──────────────────────────────────────
    final parametresItems = <_DesktopMenuItem>[
      _DesktopMenuItem(
        label: Localization.translate('معلومات الورشة', lang),
        icon: Icons.storefront_rounded,
        onSelected: () => _open(
          'workshop_profile',
          Icons.storefront_rounded,
          const WorkshopProfileScreen(),
        ),
      ),
      if (settings.canManageWorkers())
        _DesktopMenuItem(
          label: Localization.translate('إدارة صلاحيات المستخدمين', lang),
          icon: Icons.manage_accounts_rounded,
          onSelected: () => _open(
            'worker_management',
            Icons.manage_accounts_rounded,
            WorkersManagementScreen(db: db),
          ),
        ),
      if (allowWorkshop && settings.canSelectSystems())
        _DesktopMenuItem(
          label: Localization.translate('تحديد الأنظمة المستعملة', lang),
          icon: Icons.dashboard_customize_rounded,
          onSelected: () => _open(
            'selected_systems',
            Icons.dashboard_customize_rounded,
            const SelectedSystemsScreen(),
          ),
        ),
      if (allowWorkshop && settings.canChangePrices())
        _DesktopMenuItem(
          label: Localization.translate('Manage Prices', lang),
          icon: Icons.monetization_on_rounded,
          onSelected: () => _open(
            'Manage Prices',
            Icons.monetization_on_rounded,
            PriceManagementScreen(),
          ),
        ),
      if (settings.canAccessSettings())
        _DesktopMenuItem(
          label: Localization.translate('settings', lang),
          icon: Icons.settings_rounded,
          onSelected: () =>
              _open('settings', Icons.settings_rounded, const SettingsScreen()),
        ),
      _DesktopMenuItem(
        label: _label(
          lang,
          arabic: 'استهلاك التخزين والذاكرة',
          french: 'Stockage & Mémoire',
          english: 'Storage & Memory',
        ),
        icon: Icons.pie_chart_outline_rounded,
        onSelected: () => _open(
          'storage_dashboard',
          Icons.pie_chart_outline_rounded,
          StorageDashboardScreen(db: db),
        ),
      ),
    ];

    // ── Aide (المساعدة والدعم) ────────────────────────────────────────────────
    final aideItems = <_DesktopMenuItem>[
      _DesktopMenuItem(
        label: _label(
          lang,
          arabic: 'حول التطبيق',
          french: 'À propos',
          english: 'About',
        ),
        icon: Icons.info_outline_rounded,
        onSelected: _showAbout,
      ),
      _DesktopMenuItem(
        label: Localization.translate('مراسلة الإدارة وتقييم التطبيق', lang),
        icon: Icons.support_agent_rounded,
        onSelected: () {
          showDialog(context: context, builder: (_) => SupportDialog());
        },
      ),
    ];

    // ──────────────────────────────────────────────────────────────────────────
    return Column(
      children: [
        Material(
          color: background,
          child: Container(
            height: 42,
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: isDark
                      ? const Color(0xFF334155)
                      : const Color(0xFFE2E8F0),
                ),
              ),
            ),
            child: Row(
              children: [
                // ── Logo + app name (draggable) ────────────────────────────
                SizedBox(
                  width: 142,
                  child: DragToMoveArea(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onDoubleTap: _toggleMaximize,
                      child: Padding(
                        padding: const EdgeInsetsDirectional.only(start: 14),
                        child: Row(
                          children: [
                            Image.asset(
                              'web/favicon.png',
                              width: 23,
                              height: 23,
                              fit: BoxFit.contain,
                              errorBuilder: (_, __, ___) => const Icon(
                                Icons.window_rounded,
                                size: 18,
                                color: Color(0xFF2563EB),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              Localization.translate('ورشتي', lang),
                              style: TextStyle(
                                color: foreground,
                                fontFamily: 'Cairo',
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

                // ── Menus ─────────────────────────────────────────────────
                // Keep the fixed logo and window controls visible, while
                // allowing the menu strip to scroll on narrow windows.
                // ── Menus (Responsive without scrollbars) ─────────────────
                if (widget.onOpen != null)
                  Expanded(
                    child: _DesktopResponsiveMenuBar(
                      menus: [
                        _DesktopMenuData(label: 'Fichier', items: fichierItems),
                        if (venteItems.isNotEmpty)
                          _DesktopMenuData(label: 'Vente', items: venteItems),
                        if (achatItems.isNotEmpty)
                          _DesktopMenuData(label: 'Achat', items: achatItems),
                        if (stockItems.isNotEmpty)
                          _DesktopMenuData(label: 'Stock', items: stockItems),
                        if (tacheItems.isNotEmpty)
                          _DesktopMenuData(label: 'Tâche', items: tacheItems),
                        if (tresorerieItems.isNotEmpty)
                          _DesktopMenuData(
                            label: 'Trésorerie',
                            items: tresorerieItems,
                          ),
                        if (compteItems.isNotEmpty)
                          _DesktopMenuData(label: 'Compte', items: compteItems),
                        _DesktopMenuData(
                          label: 'Affichage',
                          items: affichageItems,
                        ),
                        if (parametresItems.isNotEmpty)
                          _DesktopMenuData(
                            label: 'Paramètres',
                            items: parametresItems,
                          ),
                        _DesktopMenuData(label: 'Aide', items: aideItems),
                      ],
                      onDoubleTap: _toggleMaximize,
                    ),
                  )
                else
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onDoubleTap: _toggleMaximize,
                      child: DragToMoveArea(child: const SizedBox.expand()),
                    ),
                  ),

                // ── Window control buttons ──────────────────────────────────
                _CaptionButton(
                  tooltip: Localization.translate('تصغير', lang),
                  iconBuilder: (_) =>
                      Container(width: 10, height: 1.2, color: foreground),
                  onPressed: () => windowManager.minimize(),
                ),
                _CaptionButton(
                  tooltip: Localization.translate(
                    _isMaximized ? 'استعادة الحجم' : 'تكبير',
                    lang,
                  ),
                  iconBuilder: (_) => _isMaximized
                      ? _buildRestoreIcon(foreground, isDark)
                      : _buildMaximizeIcon(foreground),
                  onPressed: _toggleMaximize,
                ),
                _CaptionButton(
                  tooltip: Localization.translate('إغلاق', lang),
                  closeButton: true,
                  iconBuilder: (hovered) => Icon(
                    Icons.close_rounded,
                    size: 17,
                    color: hovered ? Colors.white : const Color(0xFFDC2626),
                  ),
                  onPressed: _closeApp,
                ),
              ],
            ),
          ),
        ),
        if (widget.topBar != null)
          Material(
            color: background,
            child: SizedBox(height: 42, child: widget.topBar!),
          ),
        Expanded(child: widget.child),
      ],
    );
  }

  Widget _buildMaximizeIcon(Color color) {
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(border: Border.all(color: color, width: 1.2)),
    );
  }

  Widget _buildRestoreIcon(Color color, bool isDark) {
    return SizedBox(
      width: 11,
      height: 11,
      child: Stack(
        children: [
          Positioned(
            top: 0,
            right: 0,
            child: Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                border: Border.all(color: color, width: 1.2),
              ),
            ),
          ),
          Positioned(
            bottom: 0,
            left: 0,
            child: Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF111827) : Colors.white,
                border: Border.all(color: color, width: 1.2),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Internal data classes ──────────────────────────────────────────────────────

class _DesktopMenuItem {
  const _DesktopMenuItem({
    required this.label,
    required this.icon,
    required this.onSelected,
  });

  final String label;
  final IconData icon;
  final VoidCallback onSelected;
}

class _DesktopMenuData {
  const _DesktopMenuData({required this.label, required this.items});

  final String label;
  final List<_DesktopMenuItem> items;
}

// ── Responsive Menu Bar (Zero scrollbar, dynamic overflow) ─────────────────────

class _DesktopResponsiveMenuBar extends StatelessWidget {
  const _DesktopResponsiveMenuBar({
    required this.menus,
    required this.onDoubleTap,
  });

  final List<_DesktopMenuData> menus;
  final VoidCallback onDoubleTap;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth;
        // Average width per top-level menu label + padding is ~74px
        const double approxItemWidth = 74.0;
        const double overflowBtnWidth = 42.0;

        int visibleCount = menus.length;
        if (menus.length * approxItemWidth > availableWidth) {
          visibleCount = ((availableWidth - overflowBtnWidth) / approxItemWidth)
              .floor();
          if (visibleCount < 1) visibleCount = 1;
          if (visibleCount > menus.length) visibleCount = menus.length;
        }

        final visibleMenus = menus.take(visibleCount).toList();
        final overflowMenus = menus.skip(visibleCount).toList();

        return Row(
          children: [
            ...visibleMenus.map(
              (m) => _DesktopMenu(label: m.label, items: m.items),
            ),
            if (overflowMenus.isNotEmpty)
              _DesktopOverflowMenu(menus: overflowMenus),
            // The remainder is fully draggable
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onDoubleTap: onDoubleTap,
                child: DragToMoveArea(child: const SizedBox.expand()),
              ),
            ),
          ],
        );
      },
    );
  }
}

// ── Overflow Menu Button (•••) ─────────────────────────────────────────────────

class _DesktopOverflowMenu extends StatelessWidget {
  const _DesktopOverflowMenu({required this.menus});

  final List<_DesktopMenuData> menus;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final foreground = isDark ? Colors.white70 : const Color(0xFF475569);

    final entries = <dynamic>[];
    for (final menu in menus) {
      entries.add(menu.label); // Header string
      for (final item in menu.items) {
        entries.add(item); // _DesktopMenuItem
      }
    }

    return PopupMenuButton<int>(
      tooltip: 'Plus',
      position: PopupMenuPosition.under,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 240, maxHeight: 460),
      onSelected: (index) {
        final entry = entries[index];
        if (entry is _DesktopMenuItem) {
          entry.onSelected();
        }
      },
      itemBuilder: (context) => List.generate(entries.length, (index) {
        final entry = entries[index];
        if (entry is String) {
          return PopupMenuItem<int>(
            enabled: false,
            height: 32,
            child: Container(
              padding: const EdgeInsets.only(top: 6, bottom: 2),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: isDark ? Colors.white12 : Colors.black12,
                  ),
                ),
              ),
              child: Text(
                entry,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white38 : Colors.blueGrey.shade700,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          );
        }

        final item = entry as _DesktopMenuItem;
        return PopupMenuItem<int>(
          value: index,
          height: 38,
          child: Row(
            children: [
              Icon(item.icon, size: 16),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  item.label,
                  style: const TextStyle(fontSize: 12.5),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        );
      }),
      child: SizedBox(
        height: 42,
        width: 38,
        child: Center(
          child: Icon(Icons.more_horiz_rounded, size: 20, color: foreground),
        ),
      ),
    );
  }
}

// ── Menu button ────────────────────────────────────────────────────────────────

class _DesktopMenu extends StatelessWidget {
  const _DesktopMenu({required this.label, required this.items});

  final String label;
  final List<_DesktopMenuItem> items;

  @override
  Widget build(BuildContext context) {
    final foreground = Theme.of(context).brightness == Brightness.dark
        ? Colors.white70
        : const Color(0xFF475569);
    return PopupMenuButton<int>(
      tooltip: label,
      position: PopupMenuPosition.under,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 220),
      onSelected: (index) => items[index].onSelected(),
      itemBuilder: (context) => List.generate(items.length, (index) {
        final item = items[index];
        return PopupMenuItem<int>(
          value: index,
          height: 42,
          child: Row(
            children: [
              Icon(item.icon, size: 18),
              const SizedBox(width: 12),
              Expanded(child: Text(item.label)),
            ],
          ),
        );
      }),
      child: SizedBox(
        height: 42,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: foreground,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Caption window-control button ──────────────────────────────────────────────

class _CaptionButton extends StatefulWidget {
  final String tooltip;
  final Widget Function(bool isHovered) iconBuilder;
  final VoidCallback onPressed;
  final bool closeButton;

  const _CaptionButton({
    required this.tooltip,
    required this.iconBuilder,
    required this.onPressed,
    this.closeButton = false,
  });

  @override
  State<_CaptionButton> createState() => _CaptionButtonState();
}

class _CaptionButtonState extends State<_CaptionButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: widget.tooltip,
      button: true,
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: Material(
          color: widget.closeButton && _isHovered
              ? const Color(0xFFE81123)
              : Colors.transparent,
          child: InkWell(
            onTap: widget.onPressed,
            hoverColor: widget.closeButton
                ? const Color(0xFFE81123)
                : Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
            child: SizedBox(
              width: 46,
              height: double.infinity,
              child: Center(child: widget.iconBuilder(_isHovered)),
            ),
          ),
        ),
      ),
    );
  }
}
