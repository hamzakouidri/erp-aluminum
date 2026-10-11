import 'package:database_data/Cliente/client.dart';
import 'package:database_data/Commande/commande.dart';
import 'package:database_data/Screen/achat_screen.dart';
import 'package:database_data/Screen/admin_users_screen.dart';
import 'package:database_data/Screen/client_chrono_search_screen.dart';
import 'package:database_data/Screen/distribution_tracking_screen.dart';
import 'package:database_data/Screen/external_operations_hub_screen.dart';
import 'package:database_data/Screen/global_consumption_report_screen.dart';
import 'package:database_data/Screen/inventory_screen.dart';
import 'package:database_data/Screen/measurements_screen.dart';
import 'package:database_data/Screen/price_management_screen.dart';
import 'package:database_data/Screen/projects_screen.dart';
import 'package:database_data/Screen/reports_hub_screen.dart';
import 'package:database_data/Screen/sales_screen.dart';
import 'package:database_data/Screen/selected_systems_screen.dart';
import 'package:database_data/Screen/settings_screen.dart';
import 'package:database_data/Screen/support_dialog.dart';
import 'package:database_data/Screen/suppliers_screen.dart';
import 'package:database_data/Screen/treasury_screen.dart';
import 'package:database_data/Screen/worker_archive_screen.dart';
import 'package:database_data/Screen/worker_finances_screen.dart';
import 'package:database_data/Screen/worker_tasks_screen.dart';
import 'package:database_data/Screen/worker_weekly_settlement_screen.dart';
import 'package:database_data/Screen/workers_management_screen.dart';
import 'package:database_data/items_produits/products_menu_screen.dart';
import 'package:database_data/services/cloud_sync_service.dart';
import 'package:database_data/services/supabase_workshop_sync_service.dart';
import 'package:database_data/settings/app_settings.dart';
import 'package:database_data/sql_database.dart';
import 'package:database_data/widgets/app_material.dart';
import 'package:provider/provider.dart';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:database_data/services/auth_service.dart';

import '../Screen/app_workspace_shell.dart';

/// A Windows-only command bar.  It deliberately lives inside the app's
/// navigator, below the permanent workspace tabs, so menus open like a normal
/// desktop application while the original side drawer remains available.
class DesktopCommandBar extends StatelessWidget {
  final void Function(String title, IconData icon, Widget screen) onOpen;

  const DesktopCommandBar({super.key, required this.onOpen});

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
    final settings = context.watch<AppSettingsProvider>();
    final lang = settings.language;
    final db = SqlDatabase();
    final groups = <_DesktopCommandGroup>[];

    final salesActions = <_DesktopCommandAction>[];
    if (settings.canViewOrders()) {
      salesActions.add(
        _DesktopCommandAction(
          title: _label(
            lang,
            arabic: 'طلبيات الزبائن',
            french: 'Commandes clients',
            english: 'Customer orders',
          ),
          icon: Icons.receipt_long_rounded,
          onSelected: () =>
              onOpen('commandes', Icons.receipt_long_rounded, Commande()),
        ),
      );
    }
    if (settings.canViewSales()) {
      salesActions.add(
        _DesktopCommandAction(
          title: _label(
            lang,
            arabic: 'المبيعات',
            french: 'Ventes',
            english: 'Sales',
          ),
          icon: Icons.point_of_sale_rounded,
          onSelected: () =>
              onOpen('vente', Icons.point_of_sale_rounded, SalesScreen(db: db)),
        ),
      );
    }
    if (settings.canAccessDistributionTracking()) {
      salesActions.add(
        _DesktopCommandAction(
          title: _label(
            lang,
            arabic: 'التوزيع والتتبع',
            french: 'Distribution et suivi',
            english: 'Distribution and tracking',
          ),
          icon: Icons.local_shipping_rounded,
          onSelected: () => onOpen(
            'distribution_tracking',
            Icons.local_shipping_rounded,
            const DistributionTrackingScreen(),
          ),
        ),
      );
    }
    if (settings.canAccessMeasurements()) {
      salesActions.add(
        _DesktopCommandAction(
          title: _label(
            lang,
            arabic: 'رفع القياسات',
            french: 'Saisie des mesures',
            english: 'Measurements',
          ),
          icon: Icons.straighten_rounded,
          onSelected: () => onOpen(
            'measurements',
            Icons.straighten_rounded,
            MeasurementsScreen(db: db),
          ),
        ),
      );
    }
    if (salesActions.isNotEmpty) {
      groups.add(
        _DesktopCommandGroup(
          title: _label(
            lang,
            arabic: 'الطلبات والمبيعات',
            french: 'Commandes et ventes',
            english: 'Orders and sales',
          ),
          icon: Icons.shopping_cart_checkout_rounded,
          color: const Color(0xFF0F766E),
          actions: salesActions,
        ),
      );
    }

    final purchaseActions = <_DesktopCommandAction>[];
    if (settings.canRegisterPurchases()) {
      purchaseActions.add(
        _DesktopCommandAction(
          title: _label(
            lang,
            arabic: 'تسجيل المشتريات',
            french: 'Saisir un achat',
            english: 'Register purchase',
          ),
          icon: Icons.add_shopping_cart_rounded,
          onSelected: () =>
              onOpen('achat', Icons.shopping_bag_rounded, AchatScreen(db: db)),
        ),
      );
    }
    if (settings.canViewSuppliers()) {
      purchaseActions.add(
        _DesktopCommandAction(
          title: _label(
            lang,
            arabic: 'الموردون',
            french: 'Fournisseurs',
            english: 'Suppliers',
          ),
          icon: Icons.local_shipping_rounded,
          onSelected: () => onOpen(
            'suppliers',
            Icons.local_shipping_rounded,
            SuppliersScreen(db: db),
          ),
        ),
      );
    }
    if (purchaseActions.isNotEmpty) {
      groups.add(
        _DesktopCommandGroup(
          title: _label(
            lang,
            arabic: 'المشتريات',
            french: 'Achats',
            english: 'Purchases',
          ),
          icon: Icons.shopping_bag_rounded,
          color: const Color(0xFFC2410C),
          actions: purchaseActions,
        ),
      );
    }

    final inventoryActions = <_DesktopCommandAction>[];
    if (settings.canViewMyAccreditations()) {
      inventoryActions.add(
        _DesktopCommandAction(
          title: _label(
            lang,
            arabic: 'المنتجات',
            french: 'Produits',
            english: 'Products',
          ),
          icon: Icons.category_rounded,
          onSelected: () => onOpen(
            'produits',
            Icons.category_rounded,
            ProductsMenuScreen(db: db),
          ),
        ),
      );
    }
    if (settings.canAccessInventory()) {
      inventoryActions.add(
        _DesktopCommandAction(
          title: _label(
            lang,
            arabic: 'المخزون',
            french: 'Stock',
            english: 'Inventory',
          ),
          icon: Icons.warehouse_rounded,
          onSelected: () => onOpen(
            'inventory',
            Icons.warehouse_rounded,
            InventoryScreen(db: db),
          ),
        ),
      );
    }
    if (settings.canViewGlobalConsumption()) {
      inventoryActions.add(
        _DesktopCommandAction(
          title: _label(
            lang,
            arabic: 'تقرير النواقص',
            french: 'Rapport des manques',
            english: 'Shortage report',
          ),
          icon: Icons.inventory_2_rounded,
          onSelected: () => onOpen(
            'global_consumption',
            Icons.inventory_2_rounded,
            GlobalConsumptionReportScreen(db: db),
          ),
        ),
      );
    }
    if (inventoryActions.isNotEmpty) {
      groups.add(
        _DesktopCommandGroup(
          title: _label(
            lang,
            arabic: 'المخزون والمنتجات',
            french: 'Stock et produits',
            english: 'Inventory and products',
          ),
          icon: Icons.warehouse_rounded,
          color: const Color(0xFF7C3AED),
          actions: inventoryActions,
        ),
      );
    }

    final financeActions = <_DesktopCommandAction>[];
    if (settings.canAccessTreasury()) {
      financeActions.add(
        _DesktopCommandAction(
          title: _label(
            lang,
            arabic: 'الصندوق والخزينة',
            french: 'Caisse',
            english: 'Treasury',
          ),
          icon: Icons.account_balance_wallet_rounded,
          onSelected: () => onOpen(
            'caisse',
            Icons.account_balance_wallet_rounded,
            TreasuryScreen(db: db),
          ),
        ),
      );
    }
    if (settings.canViewWorkerFinances()) {
      financeActions.add(
        _DesktopCommandAction(
          title: _label(
            lang,
            arabic: 'أجور العمال',
            french: 'Salaires employés',
            english: 'Worker finances',
          ),
          icon: Icons.people_alt_rounded,
          onSelected: () => onOpen(
            'worker_finances',
            Icons.people_alt_rounded,
            WorkerFinancesScreen(db: db),
          ),
        ),
      );
    }
    if (settings.canViewWorkerWeeklySettlement()) {
      financeActions.add(
        _DesktopCommandAction(
          title: _label(
            lang,
            arabic: 'المحاسبة الأسبوعية',
            french: 'Comptabilité hebdomadaire',
            english: 'Weekly settlement',
          ),
          icon: Icons.calculate_rounded,
          onSelected: () => onOpen(
            'worker_settlement',
            Icons.calculate_rounded,
            WorkerWeeklySettlementScreen(db: db),
          ),
        ),
      );
    }
    if (financeActions.isNotEmpty) {
      groups.add(
        _DesktopCommandGroup(
          title: _label(
            lang,
            arabic: 'الصندوق والحسابات',
            french: 'Caisse et comptes',
            english: 'Treasury and accounts',
          ),
          icon: Icons.account_balance_wallet_rounded,
          color: const Color(0xFF15803D),
          actions: financeActions,
        ),
      );
    }

    if (settings.canViewStatistics()) {
      groups.add(
        _DesktopCommandGroup(
          title: _label(
            lang,
            arabic: 'التقارير',
            french: 'Rapports',
            english: 'Reports',
          ),
          icon: Icons.analytics_rounded,
          color: const Color(0xFF4F46E5),
          actions: [
            _DesktopCommandAction(
              title: _label(
                lang,
                arabic: 'مركز التقارير',
                french: 'Centre de rapports',
                english: 'Reports center',
              ),
              icon: Icons.bar_chart_rounded,
              onSelected: () => onOpen(
                'reports',
                Icons.analytics_rounded,
                ReportsHubScreen(db: db),
              ),
            ),
          ],
        ),
      );
    }

    final customerActions = <_DesktopCommandAction>[];
    if (settings.canViewClients()) {
      customerActions.add(
        _DesktopCommandAction(
          title: _label(
            lang,
            arabic: 'الزبائن',
            french: 'Clients',
            english: 'Customers',
          ),
          icon: Icons.groups_rounded,
          onSelected: () => onOpen(
            'clients',
            Icons.groups_rounded,
            Customers(
              storeOnly:
                  settings.workingSection == WorkingSection.materialsStore,
            ),
          ),
        ),
      );
    }
    if (settings.workingSection != WorkingSection.materialsStore &&
        settings.canViewClientLedger()) {
      customerActions.add(
        _DesktopCommandAction(
          title: _label(
            lang,
            arabic: 'كشف حساب الزبائن',
            french: 'Relevé clients',
            english: 'Customer ledger',
          ),
          icon: Icons.history_edu_rounded,
          onSelected: () => onOpen(
            'client_ledger',
            Icons.history_edu_rounded,
            const ClientChronoSearchScreen(),
          ),
        ),
      );
    }
    if (customerActions.isNotEmpty) {
      groups.add(
        _DesktopCommandGroup(
          title: _label(
            lang,
            arabic: 'الزبائن',
            french: 'Clients',
            english: 'Customers',
          ),
          icon: Icons.groups_rounded,
          color: const Color(0xFF2563EB),
          actions: customerActions,
        ),
      );
    }

    if (settings.canViewProjects()) {
      groups.add(
        _DesktopCommandGroup(
          title: _label(
            lang,
            arabic: 'المشاريع',
            french: 'Projets',
            english: 'Projects',
          ),
          icon: Icons.folder_shared_rounded,
          color: const Color(0xFF0369A1),
          actions: [
            _DesktopCommandAction(
              title: _label(
                lang,
                arabic: 'كل المشاريع',
                french: 'Tous les projets',
                english: 'All projects',
              ),
              icon: Icons.folder_open_rounded,
              onSelected: () => onOpen(
                'projects',
                Icons.folder_shared_rounded,
                ProjectsScreen(db: db),
              ),
            ),
          ],
        ),
      );
    }

    final taskActions = <_DesktopCommandAction>[];
    if (settings.canViewMyTasks()) {
      taskActions.add(
        _DesktopCommandAction(
          title: _label(
            lang,
            arabic: 'مهامي وتصنيعاتي',
            french: 'Mes tâches et fabrications',
            english: 'My tasks and manufacturing',
          ),
          icon: Icons.engineering_rounded,
          onSelected: () => onOpen(
            'worker_tasks',
            Icons.engineering_rounded,
            WorkerTasksScreen(db: db),
          ),
        ),
      );
      taskActions.add(
        _DesktopCommandAction(
          title: _label(
            lang,
            arabic: 'أرشيف المهام والتوزيع',
            french: 'Archives et distribution',
            english: 'Tasks and distribution archive',
          ),
          icon: Icons.archive_rounded,
          onSelected: () => onOpen(
            'worker_archive',
            Icons.archive_rounded,
            WorkerArchiveScreen(db: db),
          ),
        ),
      );
    }
    if (settings.canAccessExternalOperations()) {
      taskActions.add(
        _DesktopCommandAction(
          title: _label(
            lang,
            arabic: 'المهام الخارجية',
            french: 'Opérations externes',
            english: 'External operations',
          ),
          icon: Icons.construction_rounded,
          onSelected: () => onOpen(
            'external_operations',
            Icons.construction_rounded,
            ExternalOperationsHubScreen(db: db),
          ),
        ),
      );
    }
    if (taskActions.isNotEmpty) {
      groups.add(
        _DesktopCommandGroup(
          title: _label(
            lang,
            arabic: 'المهام والتنفيذ',
            french: 'Tâches et exécution',
            english: 'Tasks and execution',
          ),
          icon: Icons.task_alt_rounded,
          color: const Color(0xFF4338CA),
          actions: taskActions,
        ),
      );
    }

    final managementActions = <_DesktopCommandAction>[];
    if (settings.canManageWorkers()) {
      managementActions.add(
        _DesktopCommandAction(
          title: _label(
            lang,
            arabic: 'صلاحيات المستخدمين',
            french: 'Gestion des utilisateurs',
            english: 'User permissions',
          ),
          icon: Icons.manage_accounts_rounded,
          onSelected: () => onOpen(
            'worker_management',
            Icons.manage_accounts_rounded,
            WorkersManagementScreen(db: db),
          ),
        ),
      );
    }
    if (settings.canChangePrices()) {
      managementActions.add(
        _DesktopCommandAction(
          title: _label(
            lang,
            arabic: 'إدارة الأسعار',
            french: 'Gestion des prix',
            english: 'Price management',
          ),
          icon: Icons.monetization_on_rounded,
          onSelected: () => onOpen(
            'Manage Prices',
            Icons.monetization_on_rounded,
            PriceManagementScreen(),
          ),
        ),
      );
    }
    if (settings.canSelectSystems()) {
      managementActions.add(
        _DesktopCommandAction(
          title: _label(
            lang,
            arabic: 'الأنظمة المستعملة',
            french: 'Systèmes utilisés',
            english: 'Selected systems',
          ),
          icon: Icons.dashboard_customize_rounded,
          onSelected: () => onOpen(
            'selected_systems',
            Icons.dashboard_customize_rounded,
            const SelectedSystemsScreen(),
          ),
        ),
      );
    }
    if (isAdmin) {
      managementActions.add(
        _DesktopCommandAction(
          title: _label(
            lang,
            arabic: 'المستخدمون والاشتراكات',
            french: 'Utilisateurs et abonnements',
            english: 'Users and subscriptions',
          ),
          icon: Icons.admin_panel_settings_rounded,
          onSelected: () => onOpen(
            'admin_users',
            Icons.admin_panel_settings_rounded,
            const AdminUsersScreen(),
          ),
        ),
      );
    }
    if (settings.canAccessSettings()) {
      managementActions.add(
        _DesktopCommandAction(
          title: _label(
            lang,
            arabic: 'إعدادات التطبيق',
            french: "Paramètres de l'application",
            english: 'Application settings',
          ),
          icon: Icons.settings_rounded,
          onSelected: () => onOpen(
            'settings',
            Icons.settings_rounded,
            const SettingsScreen(),
          ),
        ),
      );
    }
    if (managementActions.isNotEmpty) {
      groups.add(
        _DesktopCommandGroup(
          title: _label(
            lang,
            arabic: 'الإعدادات والإدارة',
            french: 'Paramètres et gestion',
            english: 'Settings and management',
          ),
          icon: Icons.settings_suggest_rounded,
          color: const Color(0xFF475569),
          actions: managementActions,
        ),
      );
    }

    groups.add(
      _DesktopCommandGroup(
        title: _label(
          lang,
          arabic: 'الحساب',
          french: 'Compte',
          english: 'Account',
        ),
        icon: Icons.account_circle_rounded,
        color: const Color(0xFF64748B),
        actions: [
          _DesktopCommandAction(
            title: _label(
              lang,
              arabic: 'الدعم والتقييم',
              french: 'Assistance et avis',
              english: 'Support and feedback',
            ),
            icon: Icons.support_agent_rounded,
            onSelected: () =>
                showDialog(context: context, builder: (_) => SupportDialog()),
          ),
          _DesktopCommandAction(
            title: _label(
              lang,
              arabic: 'تسجيل الخروج',
              french: 'Déconnexion',
              english: 'Sign out',
            ),
            icon: Icons.logout_rounded,
            destructive: true,
            onSelected: () async {
              try {
                final workspace = context.read<WorkspaceController>();
                // Change the auth state first so main.dart replaces the
                // workspace with LoginScreen immediately. Cleanup must not
                // block that transition on desktop.
                await AppAuthService().signOut();
                // Let the auth gate dispose the old navigators before their
                // keys and tabs are reset. Sign-out never restores/minimizes
                // the native window: it only replaces its Flutter content.
                await WidgetsBinding.instance.endOfFrame;
                workspace.resetForSignedOut();
                await AppAuthService().signOutGoogleSession();
                CloudSyncService().reset();
                SupabaseWorkshopSyncService().stop();
                await CloudSyncService().clearCachedWorkshopContext();
              } catch (error) {
                debugPrint('Sign out error: $error');
              }
            },
          ),
        ],
      ),
    );

    return Material(
      color: Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF172033)
          : Colors.white,
      child: Container(
        height: 48,
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: Theme.of(context).brightness == Brightness.dark
                  ? const Color(0xFF334155)
                  : const Color(0xFFE2E8F0),
            ),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 5,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Stack(
          children: [
            const PositionedDirectional(
              end: 18,
              top: 0,
              bottom: 0,
              child: IgnorePointer(child: _WorkshopLogoWatermark()),
            ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsetsDirectional.symmetric(horizontal: 8),
              child: Row(
                children: [
                  for (final group in groups)
                    _DesktopCommandButton(group: group),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WorkshopLogoWatermark extends StatelessWidget {
  const _WorkshopLogoWatermark();

  @override
  Widget build(BuildContext context) {
    final user = AppAuthService().currentUser;
    if (user == null) return const SizedBox.shrink();

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .snapshots(),
      builder: (context, snapshot) {
        final logo = snapshot.data?.data()?['workshopLogoUrl'] as String?;
        ImageProvider? image;
        if (logo != null && logo.isNotEmpty) {
          if (logo.startsWith('http')) {
            image = NetworkImage(logo);
          } else {
            try {
              final bytes = base64Decode(logo);
              if (bytes.isNotEmpty) image = MemoryImage(bytes);
            } catch (_) {
              image = null;
            }
          }
        }

        return Opacity(
          opacity: 0.08,
          child: Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              image: image == null
                  ? null
                  : DecorationImage(image: image, fit: BoxFit.contain),
            ),
            child: image == null
                ? const Icon(Icons.storefront_rounded, size: 38)
                : null,
          ),
        );
      },
    );
  }
}

class _DesktopCommandButton extends StatelessWidget {
  final _DesktopCommandGroup group;

  const _DesktopCommandButton({required this.group});

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<_DesktopCommandAction>(
      onSelected: (action) => action.onSelected(),
      offset: const Offset(0, 42),
      itemBuilder: (context) => [
        for (final action in group.actions)
          PopupMenuItem<_DesktopCommandAction>(
            value: action,
            height: 44,
            child: Row(
              children: [
                Icon(
                  action.icon,
                  size: 19,
                  color: action.destructive ? Colors.red : group.color,
                ),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    action.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
      ],
      child: Container(
        height: 40,
        margin: const EdgeInsetsDirectional.only(end: 2),
        padding: const EdgeInsetsDirectional.symmetric(horizontal: 10),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(8)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(group.icon, size: 18, color: group.color),
            const SizedBox(width: 6),
            Text(
              group.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            ),
            const SizedBox(width: 2),
            Icon(Icons.arrow_drop_down_rounded, size: 19, color: group.color),
          ],
        ),
      ),
    );
  }
}

class _DesktopCommandGroup {
  final String title;
  final IconData icon;
  final Color color;
  final List<_DesktopCommandAction> actions;

  const _DesktopCommandGroup({
    required this.title,
    required this.icon,
    required this.color,
    required this.actions,
  });
}

class _DesktopCommandAction {
  final String title;
  final IconData icon;
  final VoidCallback onSelected;
  final bool destructive;

  const _DesktopCommandAction({
    required this.title,
    required this.icon,
    required this.onSelected,
    this.destructive = false,
  });
}
