import 'package:database_data/Screen/workers_management_screen.dart';
import 'package:database_data/Screen/treasury_screen.dart';
import 'package:database_data/Screen/worker_finances_screen.dart';
import '../services/cloud_sync_service.dart';
import '../items_produits/products_menu_screen.dart';
import 'admin_users_screen.dart';
import 'projects_screen.dart';
import 'sales_screen.dart';
import 'dart:math' as dart_math;
import 'package:database_data/Screen/support_dialog.dart';
import 'package:database_data/Screen/subscription_review_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../Cliente/client.dart';
import '../Commande/commande.dart';
import '../sql_database.dart';
import 'achat_screen.dart';
import 'settings_screen.dart';
import 'selected_systems_screen.dart';
import 'price_management_screen.dart';
import 'global_consumption_report_screen.dart';
import 'app_workspace_shell.dart';
import 'distribution_tracking_screen.dart';
import 'external_operations_hub_screen.dart';
import 'client_chrono_search_screen.dart';
import '../login_screen.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'inventory_screen.dart';
import 'worker_archive_screen.dart';
import 'package:provider/provider.dart';
import '../settings/app_settings.dart';
import '../settings/localization.dart';
import 'dart:convert';
import 'worker_tasks_screen.dart';
import 'worker_weekly_settlement_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppDrawer extends StatefulWidget {
  /// Used by the permanent desktop sidebar.  Mobile drawers still close with
  /// the normal Navigator behaviour, while the desktop shell can collapse the
  /// sidebar without losing the currently open page.
  final VoidCallback? onCollapse;

  const AppDrawer({super.key, this.onCollapse});

  @override
  State<AppDrawer> createState() => _AppDrawerState();
}

class _AppDrawerState extends State<AppDrawer> {
  SqlDatabase db = SqlDatabase();
  String? _savedLogoBase64;
  String? _savedWorkshopName;

  @override
  void initState() {
    super.initState();
    _loadLocalWorkshopInfo();
  }

  Future<void> _loadLocalWorkshopInfo() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _savedLogoBase64 = prefs.getString('workshop_logo_base64');
        _savedWorkshopName = prefs.getString('workshop_name');
      });
    }
  }

  void _openScreen(
    String title,
    IconData icon,
    Widget screen, {
    String? titleKey,
  }) {
    if (Navigator.canPop(context)) {
      final rootNavigator = Navigator.of(context, rootNavigator: true);
      final navigationContext = rootNavigator.context;
      Navigator.pop(context);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!rootNavigator.mounted) return;
        openAdaptiveScreen(
          navigationContext,
          title: titleKey ?? title,
          icon: icon,
          screen: screen,
        );
      });
    } else {
      openAdaptiveScreen(
        context,
        title: titleKey ?? title,
        icon: icon,
        screen: screen,
      );
    }
  }

  Future<void> _updateDisplayName(
    BuildContext context,
    String currentName,
  ) async {
    final lang = Provider.of<AppSettingsProvider>(
      context,
      listen: false,
    ).language;
    final TextEditingController nameController = TextEditingController(
      text: currentName,
    );

    await showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(Localization.translate('تغيير اسم المستخدم', lang)),
          content: TextField(
            controller: nameController,
            decoration: InputDecoration(
              labelText: Localization.translate('الاسم الجديد', lang),
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(Localization.translate('إلغاء', lang)),
            ),
            ElevatedButton(
              onPressed: () async {
                final newName = nameController.text.trim();
                if (newName.isNotEmpty) {
                  try {
                    await FirebaseFirestore.instance
                        .collection('users')
                        .doc(FirebaseAuth.instance.currentUser!.uid)
                        .update({'displayName': newName});
                    if (context.mounted) {
                      Navigator.pop(ctx);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            Localization.translate(
                              'تم تحديث الاسم بنجاح',
                              lang,
                            ),
                          ),
                        ),
                      );
                    }
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            '${Localization.translate('خطأ في التحديث: ', lang)}$e',
                          ),
                        ),
                      );
                    }
                  }
                }
              },
              child: Text(Localization.translate('حفظ', lang)),
            ),
          ],
        );
      },
    );
  }

  String _desktopLabel(
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

  Widget _desktopMenuItem({
    required String title,
    required IconData icon,
    required VoidCallback onTap,
    Color? color,
  }) {
    return ListTile(
      dense: true,
      minVerticalPadding: 2,
      contentPadding: const EdgeInsetsDirectional.only(start: 44, end: 14),
      leading: Icon(icon, color: Colors.white),
      title: Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: Colors.white,
          fontFamily: 'Arial',
          fontWeight: FontWeight.w600,
        ),
      ),
      onTap: onTap,
    );
  }

  Widget _desktopGroup({
    required String title,
    required IconData icon,
    required List<Widget> children,
    Color? color,
  }) {
    return ExpansionTile(
      leading: Icon(icon, color: Colors.white),
      title: Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: Colors.white,
          fontFamily: 'Arial',
          fontWeight: FontWeight.w700,
        ),
      ),
      iconColor: Colors.white,
      collapsedIconColor: Colors.white,
      textColor: Colors.white,
      collapsedTextColor: Colors.white,
      backgroundColor: Colors.white.withValues(alpha: 0.07),
      collapsedBackgroundColor: Colors.transparent,
      childrenPadding: const EdgeInsets.only(bottom: 4),
      children: children,
    );
  }

  Widget _buildWindowsHeader(AppLanguage lang) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseAuth.instance.currentUser != null
          ? FirebaseFirestore.instance
                .collection('users')
                .doc(FirebaseAuth.instance.currentUser!.uid)
                .snapshots()
          : null,
      builder: (context, snapshot) {
        final data = snapshot.hasData && snapshot.data!.exists
            ? snapshot.data!.data() as Map<String, dynamic>
            : <String, dynamic>{};
        final workshopName =
            (data['workshopName'] as String?)?.trim().isNotEmpty == true
            ? data['workshopName'] as String
            : (_savedWorkshopName?.trim().isNotEmpty == true
                  ? _savedWorkshopName!
                  : _desktopLabel(
                      lang,
                      arabic: 'القائمة الرئيسية',
                      french: 'Menu principal',
                      english: 'Main menu',
                    ));
        final role = data['role'] as String?;
        final roleLabel = role == 'admin'
            ? _desktopLabel(
                lang,
                arabic: 'مدير التطبيق',
                french: 'Administrateur',
                english: 'Administrator',
              )
            : role == 'manager'
            ? _desktopLabel(
                lang,
                arabic: 'مدير الورشة',
                french: 'Responsable atelier',
                english: 'Workshop manager',
              )
            : _desktopLabel(
                lang,
                arabic: 'عامل',
                french: 'Employé',
                english: 'Worker',
              );

        final isDark = Theme.of(context).brightness == Brightness.dark;
        return Container(
          padding: const EdgeInsets.fromLTRB(18, 22, 18, 18),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: isDark
                  ? const [Color(0xFF1E3A8A), Color(0xFF172554)]
                  : const [Color(0xFF506CF0), Color(0xFF3E55D9)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Row(
            children: [
              if (widget.onCollapse != null) ...[
                IconButton(
                  tooltip: _desktopLabel(
                    lang,
                    arabic: 'إخفاء القائمة',
                    french: 'Masquer le menu',
                    english: 'Hide menu',
                  ),
                  onPressed: widget.onCollapse,
                  icon: const Icon(Icons.menu_open_rounded),
                  color: Colors.white,
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.white.withValues(alpha: 0.12),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              const CircleAvatar(
                radius: 24,
                backgroundColor: Colors.white,
                child: Icon(
                  Icons.storefront_rounded,
                  color: Color(0xFF2563EB),
                  size: 28,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      workshopName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      roleLabel,
                      style: const TextStyle(
                        color: Color(0xFFE0F2FE),
                        fontSize: 12,
                      ),
                    ),
                    Text(
                      FirebaseAuth.instance.currentUser?.email ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFFE0F2FE),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildWindowsWorkshopCode(AppLanguage lang) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseAuth.instance.currentUser != null
          ? FirebaseFirestore.instance
                .collection('users')
                .doc(FirebaseAuth.instance.currentUser!.uid)
                .snapshots()
          : null,
      builder: (context, snapshot) {
        if (!snapshot.hasData || !snapshot.data!.exists) {
          return const SizedBox.shrink();
        }
        final data = snapshot.data!.data() as Map<String, dynamic>;
        final role = data['role'] as String?;
        if (role != 'manager' && role != 'admin') {
          return const SizedBox.shrink();
        }
        final joinCode = data['joinCode'] as String?;
        final hasCode = joinCode != null && joinCode.isNotEmpty;

        return ListTile(
          dense: true,
          contentPadding: const EdgeInsetsDirectional.only(start: 54, end: 14),
          leading: const Icon(Icons.qr_code_rounded, color: Colors.blue),
          title: Text(
            hasCode
                ? _desktopLabel(
                    lang,
                    arabic: 'كود انضمام العمال',
                    french: "Code d'accès employés",
                    english: 'Worker join code',
                  )
                : _desktopLabel(
                    lang,
                    arabic: 'إنشاء كود الورشة',
                    french: "Créer le code de l'atelier",
                    english: 'Create workshop code',
                  ),
          ),
          subtitle: hasCode
              ? Text(
                  joinCode,
                  style: const TextStyle(
                    letterSpacing: 2,
                    fontWeight: FontWeight.bold,
                  ),
                )
              : Text(
                  _desktopLabel(
                    lang,
                    arabic: 'أنشئ كوداً لربط أجهزة العمال',
                    french: 'Créer un code pour vos employés',
                    english: 'Create a code to link worker devices',
                  ),
                ),
          trailing: hasCode
              ? IconButton(
                  tooltip: _desktopLabel(
                    lang,
                    arabic: 'نسخ',
                    french: 'Copier',
                    english: 'Copy',
                  ),
                  icon: const Icon(Icons.copy_rounded),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: joinCode));
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          _desktopLabel(
                            lang,
                            arabic: 'تم نسخ كود الورشة',
                            french: "Code d'atelier copié",
                            english: 'Workshop code copied',
                          ),
                        ),
                      ),
                    );
                  },
                )
              : TextButton(
                  onPressed: () async {
                    final user = FirebaseAuth.instance.currentUser;
                    if (user == null) return;
                    const characters = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
                    final random = dart_math.Random();
                    final newCode = String.fromCharCodes(
                      Iterable.generate(
                        6,
                        (_) => characters.codeUnitAt(
                          random.nextInt(characters.length),
                        ),
                      ),
                    );
                    try {
                      await FirebaseFirestore.instance
                          .collection('users')
                          .doc(user.uid)
                          .update({'joinCode': newCode});
                      await FirebaseFirestore.instance
                          .collection('workshops')
                          .doc(user.uid)
                          .set({
                            'joinCode': newCode,
                            'managerUid': user.uid,
                          }, SetOptions(merge: true));
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              _desktopLabel(
                                lang,
                                arabic: 'تم إنشاء كود الورشة',
                                french: "Code d'atelier créé",
                                english: 'Workshop code created',
                              ),
                            ),
                          ),
                        );
                      }
                    } catch (error) {
                      debugPrint('Error generating workshop code: $error');
                    }
                  },
                  child: Text(
                    _desktopLabel(
                      lang,
                      arabic: 'إنشاء',
                      french: 'Créer',
                      english: 'Create',
                    ),
                  ),
                ),
        );
      },
    );
  }

  void _openSupportDialog() {
    final rootNavigator = Navigator.of(context, rootNavigator: true);
    final navigationContext = rootNavigator.context;
    Navigator.pop(context);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (rootNavigator.mounted) {
        showDialog(context: navigationContext, builder: (_) => SupportDialog());
      }
    });
  }

  Future<void> _signOut() async {
    Navigator.pop(context);
    try {
      CloudSyncService().reset();
      await FirebaseAuth.instance.signOut();
      await GoogleSignIn().signOut();
      await SqlDatabase.clearAllLocalData();
    } catch (error) {
      debugPrint('Sign out error: $error');
    }
  }

  Widget _buildWindowsDrawer(
    BuildContext context,
    AppSettingsProvider settings,
    AppLanguage lang,
  ) {
    final orderItems = <Widget>[];
    if (settings.canViewOrders()) {
      orderItems.add(
        _desktopMenuItem(
          title: _desktopLabel(
            lang,
            arabic: 'طلبيات الزبائن',
            french: 'Commandes clients',
            english: 'Customer orders',
          ),
          icon: Icons.receipt_long_rounded,
          onTap: () => _openScreen(
            'commandes',
            Icons.receipt_long_rounded,
            Commande(),
            titleKey: 'commandes',
          ),
        ),
      );
    }
    if (settings.canViewSales()) {
      orderItems.add(
        _desktopMenuItem(
          title: Localization.translate('vente', lang),
          icon: Icons.point_of_sale_rounded,
          onTap: () => _openScreen(
            Localization.translate('vente', lang),
            Icons.point_of_sale_rounded,
            SalesScreen(db: db),
            titleKey: 'vente',
          ),
          color: Colors.teal,
        ),
      );
    }
    if (settings.canAccessDistributionTracking()) {
      orderItems.add(
        _desktopMenuItem(
          title: _desktopLabel(
            lang,
            arabic: 'التوزيع والتتبع',
            french: 'Distribution et suivi',
            english: 'Distribution and tracking',
          ),
          icon: Icons.local_shipping_rounded,
          onTap: () => _openScreen(
            'distribution_tracking',
            Icons.local_shipping_rounded,
            const DistributionTrackingScreen(),
            titleKey: 'distribution_tracking',
          ),
          color: Colors.blue,
        ),
      );
    }

    final purchaseItems = <Widget>[];
    if (settings.canRegisterPurchases()) {
      purchaseItems.add(
        _desktopMenuItem(
          title: _desktopLabel(
            lang,
            arabic: 'المشتريات',
            french: 'Achats',
            english: 'Purchases',
          ),
          icon: Icons.shopping_bag_rounded,
          onTap: () => _openScreen(
            'achat',
            Icons.shopping_bag_rounded,
            AchatScreen(db: SqlDatabase()),
            titleKey: 'achat',
          ),
        ),
      );
    }

    final inventoryItems = <Widget>[];
    if (settings.canViewMyAccreditations()) {
      inventoryItems.add(
        _desktopMenuItem(
          title: Localization.translate('produits', lang),
          icon: Icons.category_rounded,
          onTap: () => _openScreen(
            'produits',
            Icons.category_rounded,
            ProductsMenuScreen(db: db),
            titleKey: 'produits',
          ),
        ),
      );
    }
    if (settings.canAccessInventory()) {
      inventoryItems.add(
        _desktopMenuItem(
          title: _desktopLabel(
            lang,
            arabic: 'المخزون',
            french: 'Stock',
            english: 'Inventory',
          ),
          icon: Icons.warehouse_rounded,
          onTap: () => _openScreen(
            'inventory',
            Icons.warehouse_rounded,
            InventoryScreen(db: db),
            titleKey: 'inventory',
          ),
          color: const Color(0xFF8B5CF6),
        ),
      );
    }
    if (settings.canViewGlobalConsumption()) {
      inventoryItems.add(
        _desktopMenuItem(
          title: _desktopLabel(
            lang,
            arabic: 'تقرير النواقص الشامل',
            french: 'Rapport global des manques',
            english: 'Global shortage report',
          ),
          icon: Icons.inventory_2_rounded,
          onTap: () => _openScreen(
            'global_consumption',
            Icons.inventory_2_rounded,
            GlobalConsumptionReportScreen(db: SqlDatabase()),
            titleKey: 'global_consumption',
          ),
          color: Colors.indigo,
        ),
      );
    }

    final financeItems = <Widget>[];
    if (settings.canAccessTreasury()) {
      financeItems.add(
        _desktopMenuItem(
          title: _desktopLabel(
            lang,
            arabic: 'الصندوق والخزينة',
            french: 'Caisse',
            english: 'Treasury',
          ),
          icon: Icons.account_balance_wallet_rounded,
          onTap: () => _openScreen(
            'caisse',
            Icons.account_balance_wallet_rounded,
            TreasuryScreen(db: SqlDatabase()),
            titleKey: 'caisse',
          ),
          color: Colors.green,
        ),
      );
    }
    if (settings.canViewWorkerFinances()) {
      financeItems.add(
        _desktopMenuItem(
          title: _desktopLabel(
            lang,
            arabic: 'شؤون وأجور العمال',
            french: 'Salaires des employés',
            english: 'Worker finances',
          ),
          icon: Icons.people_alt_rounded,
          onTap: () => _openScreen(
            'worker_finances',
            Icons.people_alt_rounded,
            WorkerFinancesScreen(db: SqlDatabase()),
            titleKey: 'worker_finances',
          ),
        ),
      );
    }
    if (settings.canViewWorkerWeeklySettlement()) {
      financeItems.add(
        _desktopMenuItem(
          title: _desktopLabel(
            lang,
            arabic: 'المحاسبة الأسبوعية للعمال',
            french: 'Comptabilité hebdomadaire',
            english: 'Weekly worker settlement',
          ),
          icon: Icons.calculate_rounded,
          onTap: () => _openScreen(
            'worker_settlement',
            Icons.calculate_rounded,
            WorkerWeeklySettlementScreen(db: SqlDatabase()),
            titleKey: 'worker_settlement',
          ),
        ),
      );
    }

    final clientItems = <Widget>[];
    if (settings.canViewClients()) {
      clientItems.add(
        _desktopMenuItem(
          title: Localization.translate('clients', lang),
          icon: Icons.groups_rounded,
          onTap: () => _openScreen(
            'clients',
            Icons.groups_rounded,
            Customers(),
            titleKey: 'clients',
          ),
        ),
      );
    }
    if (settings.canViewClientLedger()) {
      clientItems.add(
        _desktopMenuItem(
          title: _desktopLabel(
            lang,
            arabic: 'كشف حساب الزبائن',
            french: 'Relevé clients',
            english: 'Customer ledger',
          ),
          icon: Icons.history_edu_rounded,
          onTap: () => _openScreen(
            'client_ledger',
            Icons.history_edu_rounded,
            const ClientChronoSearchScreen(),
            titleKey: 'client_ledger',
          ),
          color: Colors.blue,
        ),
      );
    }

    final taskItems = <Widget>[];
    if (settings.canViewMyTasks()) {
      taskItems.add(
        _desktopMenuItem(
          title: _desktopLabel(
            lang,
            arabic: 'مهامي وتصنيعاتي',
            french: 'Mes tâches et fabrications',
            english: 'My tasks and manufacturing',
          ),
          icon: Icons.engineering_rounded,
          onTap: () => _openScreen(
            'worker_tasks',
            Icons.engineering_rounded,
            WorkerTasksScreen(db: db),
            titleKey: 'worker_tasks',
          ),
          color: Colors.indigo,
        ),
      );
      taskItems.add(
        _desktopMenuItem(
          title: _desktopLabel(
            lang,
            arabic: 'أرشيف التوزيع والمهام',
            french: 'Archives et distribution',
            english: 'Tasks and distribution archive',
          ),
          icon: Icons.archive_rounded,
          onTap: () => _openScreen(
            'worker_archive',
            Icons.archive_rounded,
            WorkerArchiveScreen(db: db),
            titleKey: 'worker_archive',
          ),
          color: Colors.deepOrange,
        ),
      );
    }
    if (settings.canAccessExternalOperations()) {
      taskItems.add(
        _desktopMenuItem(
          title: _desktopLabel(
            lang,
            arabic: 'الأعمال والمهام الخارجية',
            french: 'Opérations externes',
            english: 'External operations',
          ),
          icon: Icons.construction_rounded,
          onTap: () => _openScreen(
            'external_operations',
            Icons.construction_rounded,
            ExternalOperationsHubScreen(db: db),
            titleKey: 'external_operations',
          ),
          color: Colors.teal,
        ),
      );
    }

    final managementItems = <Widget>[];
    managementItems.add(_buildWindowsWorkshopCode(lang));
    if (settings.canManageWorkers()) {
      managementItems.add(
        _desktopMenuItem(
          title: _desktopLabel(
            lang,
            arabic: 'إدارة صلاحيات المستخدمين',
            french: 'Gestion des utilisateurs',
            english: 'User permissions',
          ),
          icon: Icons.manage_accounts_rounded,
          onTap: () => _openScreen(
            'worker_management',
            Icons.manage_accounts_rounded,
            WorkersManagementScreen(db: SqlDatabase()),
            titleKey: 'worker_management',
          ),
        ),
      );
    }
    if (settings.canChangePrices()) {
      managementItems.add(
        _desktopMenuItem(
          title: Localization.translate('Manage Prices', lang),
          icon: Icons.monetization_on_rounded,
          onTap: () => _openScreen(
            'Manage Prices',
            Icons.monetization_on_rounded,
            PriceManagementScreen(),
            titleKey: 'Manage Prices',
          ),
        ),
      );
    }
    if (settings.canSelectSystems()) {
      managementItems.add(
        _desktopMenuItem(
          title: _desktopLabel(
            lang,
            arabic: 'الأنظمة المستعملة',
            french: 'Systèmes utilisés',
            english: 'Selected systems',
          ),
          icon: Icons.dashboard_customize_rounded,
          onTap: () => _openScreen(
            'selected_systems',
            Icons.dashboard_customize_rounded,
            const SelectedSystemsScreen(),
            titleKey: 'selected_systems',
          ),
        ),
      );
    }
    if (isAdmin) {
      managementItems.add(
        _desktopMenuItem(
          title: _desktopLabel(
            lang,
            arabic: 'المستخدمون والاشتراكات',
            french: 'Utilisateurs et abonnements',
            english: 'Users and subscriptions',
          ),
          icon: Icons.admin_panel_settings_rounded,
          onTap: () => _openScreen(
            'admin_users',
            Icons.admin_panel_settings_rounded,
            const AdminUsersScreen(),
            titleKey: 'admin_users',
          ),
          color: Colors.blue,
        ),
      );
    }
    if (settings.canAccessSettings()) {
      managementItems.add(
        _desktopMenuItem(
          title: Localization.translate('settings', lang),
          icon: Icons.settings_rounded,
          onTap: () => _openScreen(
            'settings',
            Icons.settings_rounded,
            const SettingsScreen(),
            titleKey: 'settings',
          ),
        ),
      );
    }

    final accountItems = <Widget>[
      if (settings.canViewSubscription())
        _desktopMenuItem(
          title: _desktopLabel(
            lang,
            arabic: 'مراجعة الاشتراك',
            french: 'Mon abonnement',
            english: 'Subscription review',
          ),
          icon: Icons.card_membership_rounded,
          onTap: () => showSubscriptionReviewDialog(context),
          color: Colors.amber,
        ),
      _desktopMenuItem(
        title: _desktopLabel(
          lang,
          arabic: 'مراسلة الإدارة وتقييم التطبيق',
          french: 'Assistance et avis',
          english: 'Support and feedback',
        ),
        icon: Icons.support_agent_rounded,
        onTap: _openSupportDialog,
        color: Colors.green,
      ),
      _desktopMenuItem(
        title: Localization.translate('deconnexion', lang),
        icon: Icons.logout_rounded,
        onTap: _signOut,
        color: Colors.red,
      ),
    ];

    final menu = <Widget>[_buildWindowsHeader(lang), const Divider(height: 1)];
    if (orderItems.isNotEmpty) {
      menu.add(
        _desktopGroup(
          title: _desktopLabel(
            lang,
            arabic: 'الطلبات والمبيعات',
            french: 'Commandes et ventes',
            english: 'Orders and sales',
          ),
          icon: Icons.shopping_cart_checkout_rounded,
          color: Colors.teal,
          children: orderItems,
        ),
      );
    }
    if (purchaseItems.isNotEmpty) {
      menu.add(
        _desktopGroup(
          title: _desktopLabel(
            lang,
            arabic: 'المشتريات',
            french: 'Achats',
            english: 'Purchases',
          ),
          icon: Icons.shopping_bag_rounded,
          color: Colors.orange,
          children: purchaseItems,
        ),
      );
    }
    if (inventoryItems.isNotEmpty) {
      menu.add(
        _desktopGroup(
          title: _desktopLabel(
            lang,
            arabic: 'المخزون والمنتجات',
            french: 'Stock et produits',
            english: 'Inventory and products',
          ),
          icon: Icons.warehouse_rounded,
          color: const Color(0xFF8B5CF6),
          children: inventoryItems,
        ),
      );
    }
    if (financeItems.isNotEmpty) {
      menu.add(
        _desktopGroup(
          title: _desktopLabel(
            lang,
            arabic: 'الصندوق والحسابات',
            french: 'Caisse et comptes',
            english: 'Treasury and accounts',
          ),
          icon: Icons.account_balance_wallet_rounded,
          color: Colors.green,
          children: financeItems,
        ),
      );
    }
    if (clientItems.isNotEmpty) {
      menu.add(
        _desktopGroup(
          title: _desktopLabel(
            lang,
            arabic: 'الزبائن',
            french: 'Clients',
            english: 'Customers',
          ),
          icon: Icons.groups_rounded,
          color: Colors.blue,
          children: clientItems,
        ),
      );
    }
    if (settings.canViewProjects()) {
      menu.add(
        ListTile(
          leading: const Icon(Icons.folder_shared_rounded, color: Colors.white),
          title: Text(
            _desktopLabel(
              lang,
              arabic: 'المشاريع',
              french: 'Projets',
              english: 'Projects',
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          onTap: () => _openScreen(
            'projects',
            Icons.folder_shared_rounded,
            ProjectsScreen(db: db),
            titleKey: 'projects',
          ),
        ),
      );
    }
    if (taskItems.isNotEmpty) {
      menu.add(
        _desktopGroup(
          title: _desktopLabel(
            lang,
            arabic: 'المهام والتنفيذ',
            french: 'Tâches et exécution',
            english: 'Tasks and execution',
          ),
          icon: Icons.task_alt_rounded,
          color: Colors.indigo,
          children: taskItems,
        ),
      );
    }
    menu.add(
      _desktopGroup(
        title: _desktopLabel(
          lang,
          arabic: 'الإعدادات والإدارة',
          french: 'Paramètres et gestion',
          english: 'Settings and management',
        ),
        icon: Icons.settings_suggest_rounded,
        color: Colors.blueGrey,
        children: managementItems,
      ),
    );
    menu.add(
      _desktopGroup(
        title: _desktopLabel(
          lang,
          arabic: 'الحساب',
          french: 'Compte',
          english: 'Account',
        ),
        icon: Icons.account_circle_rounded,
        color: const Color(0xFF6366F1),
        children: accountItems,
      ),
    );

    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Drawer(
      width: 290,
      backgroundColor: isDark
          ? const Color(0xFF172554)
          : const Color(0xFF4561E8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: isDark
                ? const [Color(0xFF1E3A8A), Color(0xFF172554)]
                : const [Color(0xFF506CF0), Color(0xFF3E55D9)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Theme(
          data: Theme.of(context).copyWith(
            dividerColor: Colors.white.withValues(alpha: 0.16),
            listTileTheme: const ListTileThemeData(
              iconColor: Colors.white,
              textColor: Colors.white,
              dense: true,
            ),
          ),
          child: ListView(padding: EdgeInsets.zero, children: menu),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<AppSettingsProvider>(context);
    final lang = settings.language;
    final isDesktopSidebar = MediaQuery.sizeOf(context).width >= 900;
    if (isDesktopSidebar) {
      return _buildWindowsDrawer(context, settings, lang);
    }
    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          StreamBuilder<DocumentSnapshot>(
            stream: FirebaseAuth.instance.currentUser != null
                ? FirebaseFirestore.instance
                      .collection('users')
                      .doc(FirebaseAuth.instance.currentUser!.uid)
                      .snapshots()
                : null,
            builder: (context, snapshot) {
              String workshopName = Localization.translate(
                'menu_principal',
                lang,
              );
              String userEmail = FirebaseAuth.instance.currentUser?.email ?? '';
              String? logoBase64;
              String? joinCode;
              String? role;
              String displayName = '';

              if (snapshot.hasData && snapshot.data!.exists) {
                final data = snapshot.data!.data() as Map<String, dynamic>;
                workshopName =
                    (data['workshopName'] as String?)?.isNotEmpty == true
                    ? data['workshopName']
                    : (_savedWorkshopName?.isNotEmpty == true
                          ? _savedWorkshopName!
                          : workshopName);
                logoBase64 =
                    (data['workshopLogoUrl'] as String?)?.isNotEmpty == true
                    ? data['workshopLogoUrl']
                    : _savedLogoBase64;
                joinCode = data['joinCode'];
                role = data['role'];
                displayName =
                    data['displayName'] ??
                    (role == 'admin'
                        ? 'مدير التطبيق'
                        : (role == 'manager'
                              ? Localization.translate('مدير الورشة', lang)
                              : Localization.translate('عامل', lang)));
              }

              return UserAccountsDrawerHeader(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: Theme.of(context).brightness == Brightness.dark
                        ? [Color(0xFF111827), Color(0xFF070E1D)]
                        : [Color(0xFF2563EB), Color(0xFF0EA5E9)],
                  ),
                ),
                accountName: Text(
                  workshopName,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
                accountEmail: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      displayName,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    Text(userEmail, style: const TextStyle(fontSize: 12)),
                  ],
                ),
                currentAccountPicture: Builder(
                  builder: (ctx) {
                    ImageProvider? imageProvider;
                    final logo = logoBase64;
                    if (logo != null && logo.isNotEmpty) {
                      if (logo.startsWith('http')) {
                        imageProvider = NetworkImage(logo);
                      } else {
                        try {
                          final bytes = base64Decode(logo);
                          if (bytes.isNotEmpty) {
                            imageProvider = MemoryImage(bytes);
                          }
                        } catch (e) {
                          debugPrint('Error decoding drawer logo base64: $e');
                        }
                      }
                    }

                    return CircleAvatar(
                      radius: 40,
                      backgroundColor: Theme.of(context).cardColor,
                      backgroundImage: imageProvider,
                      child: imageProvider == null
                          ? const Icon(
                              Icons.storefront,
                              size: 40,
                              color: Color(0xFF2563EB),
                            )
                          : null,
                    );
                  },
                ),
              );
            },
          ),
          StreamBuilder<DocumentSnapshot>(
            stream: FirebaseAuth.instance.currentUser != null
                ? FirebaseFirestore.instance
                      .collection('users')
                      .doc(FirebaseAuth.instance.currentUser!.uid)
                      .snapshots()
                : null,
            builder: (context, snapshot) {
              if (snapshot.hasData && snapshot.data!.exists) {
                final data = snapshot.data!.data() as Map<String, dynamic>;
                String? joinCode = data['joinCode'];
                String? role = data['role'];

                if (role == 'manager' || role == 'admin') {
                  if (joinCode != null && joinCode.isNotEmpty) {
                    final isDark =
                        Theme.of(context).brightness == Brightness.dark;
                    return Container(
                      color: isDark
                          ? const Color(0xFF1E293B)
                          : Colors.blue.shade50,
                      child: ListTile(
                        leading: Icon(
                          Icons.qr_code,
                          color: isDark
                              ? Colors.lightBlue.shade300
                              : Colors.blue,
                        ),
                        title: Text(
                          Localization.translate('كود انضمام العمال', lang),
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: isDark
                                ? Colors.lightBlue.shade300
                                : Colors.blue,
                          ),
                        ),
                        subtitle: Text(
                          joinCode,
                          style: TextStyle(
                            fontSize: 18,
                            letterSpacing: 2,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                        ),
                        trailing: IconButton(
                          icon: Icon(
                            Icons.copy,
                            color: isDark
                                ? Colors.lightBlue.shade300
                                : Colors.blue,
                          ),
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: joinCode));
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  Localization.translate(
                                    'تم نسخ كود الورشة بنجاح!',
                                    lang,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    );
                  } else {
                    return Container(
                      color: Colors.orange.shade50,
                      child: ListTile(
                        leading: const Icon(
                          Icons.qr_code,
                          color: Colors.orange,
                        ),
                        title: Text(
                          Localization.translate('توليد كود الورشة', lang),
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text(
                          Localization.translate(
                            'انقر هنا لإنشاء كود لعمالك',
                            lang,
                          ),
                        ),
                        trailing: ElevatedButton(
                          onPressed: () async {
                            final uid = FirebaseAuth.instance.currentUser!.uid;
                            const chars =
                                'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
                            final rnd = dart_math.Random();
                            final newCode = String.fromCharCodes(
                              Iterable.generate(
                                6,
                                (_) =>
                                    chars.codeUnitAt(rnd.nextInt(chars.length)),
                              ),
                            );

                            try {
                              await FirebaseFirestore.instance
                                  .collection('users')
                                  .doc(uid)
                                  .update({'joinCode': newCode});
                              await FirebaseFirestore.instance
                                  .collection('workshops')
                                  .doc(uid)
                                  .set({
                                    'joinCode': newCode,
                                    'managerUid': uid,
                                  }, SetOptions(merge: true));
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      Localization.translate(
                                        'تم إنشاء الكود بنجاح!',
                                        lang,
                                      ),
                                    ),
                                  ),
                                );
                              }
                            } catch (e) {
                              print('Error generating code: $e');
                            }
                          },
                          child: Text(
                            Localization.translate('توليد الآن', lang),
                          ),
                        ),
                      ),
                    );
                  }
                }
              }
              return const SizedBox.shrink();
            },
          ),
          if (settings.canViewMyTasks())
            ListTile(
              leading: const Icon(
                Icons.engineering_rounded,
                color: Colors.indigo,
              ),
              title: Text(Localization.translate('مهامي وتصنيعاتي', lang)),
              onTap: () {
                _openScreen(
                  Localization.translate('مهامي وتصنيعاتي', lang),
                  Icons.engineering_rounded,
                  WorkerTasksScreen(db: db),
                  titleKey: 'مهامي وتصنيعاتي',
                );
              },
            ),
          if (settings.canViewMyTasks())
            ListTile(
              leading: const Icon(
                Icons.archive_rounded,
                color: Colors.deepOrange,
              ),
              title: Text(
                lang == AppLanguage.arabic
                    ? 'أرشيف التوزيع والمهام'
                    : (lang == AppLanguage.french
                          ? 'Archives & Distribution'
                          : 'Tasks & Distribution Archive'),
              ),
              onTap: () {
                _openScreen(
                  lang == AppLanguage.arabic
                      ? 'أرشيف التوزيع والمهام'
                      : (lang == AppLanguage.french
                            ? 'Archives & Distribution'
                            : 'Tasks & Distribution Archive'),
                  Icons.archive_rounded,
                  WorkerArchiveScreen(db: db),
                  titleKey: 'worker_archive',
                );
              },
            ),
          if (settings.canAccessExternalOperations())
            ListTile(
              leading: const Icon(
                Icons.construction_rounded,
                color: Colors.teal,
              ),
              title: Text(
                lang == AppLanguage.arabic
                    ? 'الأعمال والمهمات الخارجية'
                    : (lang == AppLanguage.french
                          ? 'Opérations Externe'
                          : 'External Operations'),
              ),
              onTap: () {
                _openScreen(
                  lang == AppLanguage.arabic
                      ? 'الأعمال والمهمات الخارجية'
                      : 'Opérations Externe',
                  Icons.construction_rounded,
                  ExternalOperationsHubScreen(db: db),
                  titleKey: 'external_operations',
                );
              },
            ),
          if (settings.canViewOrders())
            ListTile(
              leading: const Icon(Icons.list),
              title: Text(Localization.translate('commandes', lang)),
              onTap: () {
                _openScreen(
                  'commandes',
                  Icons.list,
                  Commande(),
                  titleKey: 'commandes',
                );
              },
            ),

          if (settings.canViewProjects())
            ListTile(
              leading: const Icon(Icons.folder_shared_rounded),
              title: Text(Localization.translate('المشاريع', lang)),
              onTap: () {
                _openScreen(
                  'المشاريع',
                  Icons.folder_shared_rounded,
                  ProjectsScreen(db: db),
                  titleKey: 'المشاريع',
                );
              },
            ),

          if (settings.canViewClients())
            ListTile(
              leading: const Icon(Icons.groups),
              title: Text(Localization.translate('clients', lang)),
              onTap: () {
                _openScreen(
                  'clients',
                  Icons.groups,
                  Customers(),
                  titleKey: 'clients',
                );
              },
            ),
          if (settings.canViewClientLedger())
            ListTile(
              leading: const Icon(
                Icons.history_edu_rounded,
                color: Colors.blue,
              ),
              title: Text(Localization.translate('كشف حساب الزبائن', lang)),
              onTap: () {
                _openScreen(
                  Localization.translate('كشف حساب الزبائن', lang),
                  Icons.history_edu_rounded,
                  const ClientChronoSearchScreen(),
                  titleKey: 'كشف حساب الزبائن',
                );
              },
            ),
          if (settings.canAccessDistributionTracking())
            ListTile(
              leading: const Icon(
                Icons.delivery_dining_rounded,
                color: Colors.blue,
              ),
              title: Text(Localization.translate('خطط التوزيع والتتبع', lang)),
              onTap: () {
                _openScreen(
                  Localization.translate('خطط التوزيع والتتبع', lang),
                  Icons.delivery_dining_rounded,
                  const DistributionTrackingScreen(),
                  titleKey: 'خطط التوزيع والتتبع',
                );
              },
            ),
          if (settings.canRegisterPurchases())
            ListTile(
              leading: const Icon(Icons.shopping_bag_rounded),
              title: Text(Localization.translate('achat', lang)),
              onTap: () {
                _openScreen(
                  'achat',
                  Icons.shopping_bag_rounded,
                  AchatScreen(db: SqlDatabase()),
                  titleKey: 'achat',
                );
              },
            ),
          if (settings.canViewSales())
            ListTile(
              leading: const Icon(
                Icons.monetization_on_rounded,
                color: Colors.teal,
              ),
              title: Text(Localization.translate('vente', lang)),
              onTap: () {
                _openScreen(
                  Localization.translate('vente', lang),
                  Icons.monetization_on_rounded,
                  SalesScreen(db: db),
                  titleKey: 'vente',
                );
              },
            ),
          if (settings.canViewMyAccreditations())
            ListTile(
              leading: const Icon(Icons.production_quantity_limits),
              title: Text(Localization.translate('produits', lang)),
              onTap: () {
                _openScreen(
                  'produits',
                  Icons.production_quantity_limits,
                  ProductsMenuScreen(db: db),
                  titleKey: 'produits',
                );
              },
            ),
          if (settings.canAccessInventory())
            ListTile(
              leading: const Icon(
                Icons.warehouse_rounded,
                color: Color(0xFF8B5CF6),
              ),
              title: Text(Localization.translate('المخزون', lang)),
              onTap: () {
                _openScreen(
                  'المخزون',
                  Icons.warehouse_rounded,
                  InventoryScreen(db: db),
                  titleKey: 'المخزون',
                );
              },
            ),
          if (settings.canAccessTreasury())
            ListTile(
              leading: const Icon(Icons.money),
              title: Text(Localization.translate('caisse', lang)),
              onTap: () {
                _openScreen(
                  'caisse',
                  Icons.money,
                  TreasuryScreen(db: SqlDatabase()),
                  titleKey: 'caisse',
                );
              },
            ),
          if (settings.canManageWorkers())
            ListTile(
              leading: const Icon(Icons.engineering),
              title: Text(
                Localization.translate('إدارة صلاحيات المستخدمين', lang),
              ),
              onTap: () {
                _openScreen(
                  'إدارة صلاحيات المستخدمين',
                  Icons.engineering,
                  WorkersManagementScreen(db: SqlDatabase()),
                  titleKey: 'إدارة صلاحيات المستخدمين',
                );
              },
            ),
          if (settings.canViewGlobalConsumption())
            ListTile(
              leading: const Icon(Icons.inventory_2, color: Colors.indigo),
              title: Text(
                Localization.translate('تقرير النواقص الشامل', lang),
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.indigo,
                ),
              ),
              onTap: () {
                _openScreen(
                  'تقرير النواقص الشامل',
                  Icons.inventory_2,
                  GlobalConsumptionReportScreen(db: SqlDatabase()),
                  titleKey: 'تقرير النواقص الشامل',
                );
              },
            ),
          if (settings.canViewWorkerFinances())
            ListTile(
              leading: const Icon(Icons.people_alt),
              title: Text(
                Localization.translate('إدارة شؤون وأجور العمال', lang),
              ),
              onTap: () {
                _openScreen(
                  'إدارة شؤون وأجور العمال',
                  Icons.people_alt,
                  WorkerFinancesScreen(db: SqlDatabase()),
                  titleKey: 'إدارة شؤون وأجور العمال',
                );
              },
            ),

          if (settings.canViewWorkerWeeklySettlement())
            ListTile(
              leading: const Icon(Icons.calculate_rounded),
              title: Text(
                Localization.translate('المحاسبة الأسبوعية للعمال', lang),
              ),
              onTap: () {
                _openScreen(
                  'المحاسبة الأسبوعية للعمال',
                  Icons.calculate_rounded,
                  WorkerWeeklySettlementScreen(db: SqlDatabase()),
                  titleKey: 'المحاسبة الأسبوعية للعمال',
                );
              },
            ),

          if (settings.canChangePrices())
            ListTile(
              leading: const Icon(Icons.monetization_on),
              title: Text(Localization.translate('Manage Prices', lang)),
              onTap: () {
                _openScreen(
                  'Manage Prices',
                  Icons.monetization_on,
                  PriceManagementScreen(),
                  titleKey: 'Manage Prices',
                );
              },
            ),
          if (settings.canSelectSystems())
            ListTile(
              leading: const Icon(
                Icons.dashboard_customize_rounded,
                color: Colors.teal,
              ),
              title: Text(
                Localization.translate('تحديد الأنظمة المستعملة', lang),
              ),
              onTap: () {
                _openScreen(
                  Localization.translate('تحديد الأنظمة المستعملة', lang),
                  Icons.dashboard_customize_rounded,
                  const SelectedSystemsScreen(),
                  titleKey: 'تحديد الأنظمة المستعملة',
                );
              },
            ),
          if (isAdmin)
            ListTile(
              leading: const Icon(
                Icons.admin_panel_settings,
                color: Colors.blue,
              ),
              title: Text(
                Localization.translate(
                  Localization.translate('إدارة المستخدمين والاشتراكات', lang),
                  lang,
                ),
                style: TextStyle(
                  color: Colors.blue,
                  fontWeight: FontWeight.bold,
                ),
              ),
              onTap: () {
                _openScreen(
                  Localization.translate('إدارة المستخدمين والاشتراكات', lang),
                  Icons.admin_panel_settings,
                  const AdminUsersScreen(),
                  titleKey: 'إدارة المستخدمين والاشتراكات',
                );
              },
            ),
          if (settings.canAccessSettings())
            ListTile(
              leading: const Icon(Icons.settings),
              title: Text(Localization.translate('settings', lang)),
              onTap: () {
                _openScreen(
                  'settings',
                  Icons.settings,
                  const SettingsScreen(),
                  titleKey: 'settings',
                );
              },
            ),

          if (settings.canViewSubscription()) ...[
            const Divider(),
            ListTile(
              leading: const Icon(
                Icons.card_membership_rounded,
                color: Color(0xFF2563EB),
              ),
              title: Text(
                Localization.translate('مراجعة الاشتراك', lang),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              onTap: () {
                Navigator.pop(context);
                showSubscriptionReviewDialog(context);
              },
            ),
          ],
          ListTile(
            leading: const Icon(Icons.support_agent, color: Colors.green),
            title: Text(
              Localization.translate('مراسلة الإدارة وتقييم التطبيق', lang),
            ),
            onTap: () {
              Navigator.pop(context);
              showDialog(context: context, builder: (_) => SupportDialog());
            },
          ),
          if (FirebaseAuth.instance.currentUser == null)
            ListTile(
              leading: const Icon(Icons.login_rounded, color: Colors.green),
              title: Text(
                Localization.translate('تسجيل الدخول / فتح الجلسة', lang),
                style: const TextStyle(
                  color: Colors.green,
                  fontWeight: FontWeight.bold,
                ),
              ),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                );
              },
            )
          else
            ListTile(
              leading: const Icon(Icons.logout, color: Colors.red),
              title: Text(
                Localization.translate('deconnexion', lang),
                style: const TextStyle(color: Colors.red),
              ),
              onTap: () async {
                // إغلاق القائمة الجانبية أولاً
                Navigator.pop(context);
                // تسجيل الخروج من Firebase و Google
                try {
                  CloudSyncService().reset();
                  await FirebaseAuth.instance.signOut();
                  await GoogleSignIn().signOut();
                  await SqlDatabase.clearAllLocalData();
                } catch (e) {
                  debugPrint('Sign out error: $e');
                }
              },
            ),
        ],
      ),
    );
  }
}
