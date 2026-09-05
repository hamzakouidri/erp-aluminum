import 'package:database_data/Screen/workers_management_screen.dart';
import 'package:database_data/Screen/treasury_screen.dart';
import 'package:database_data/Screen/worker_finances_screen.dart';
import '../services/cloud_sync_service.dart';
import '../items_produits/products_menu_screen.dart';
import 'admin_users_screen.dart';
import 'projects_screen.dart';
import 'sales_screen.dart';
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
import 'package:cloud_firestore/cloud_firestore.dart';
import 'inventory_screen.dart';
import 'worker_archive_screen.dart';
import 'package:flutter/gestures.dart';
import 'package:provider/provider.dart';
import '../settings/app_settings.dart';
import '../settings/localization.dart';
import 'dart:convert';
import 'dart:async';
import 'worker_tasks_screen.dart';
import 'worker_weekly_settlement_screen.dart';
import '../services/supabase_workshop_sync_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:database_data/services/auth_service.dart';
import 'package:database_data/services/supabase_account_service.dart';
import 'dart:async';

class AppDrawer extends StatefulWidget {
  /// Used by the permanent desktop sidebar.  Mobile drawers still close with
  /// the normal Navigator behaviour, while the desktop shell can collapse the
  /// sidebar without losing the currently open page.
  final VoidCallback? onCollapse;
  final String? expandedGroup;

  const AppDrawer({super.key, this.onCollapse, this.expandedGroup});

  @override
  State<AppDrawer> createState() => _AppDrawerState();
}

class _AppDrawerState extends State<AppDrawer> {
  SqlDatabase db = SqlDatabase();
  final ScrollController _drawerScrollController = ScrollController();
  String? _savedLogoBase64;
  String? _savedWorkshopName;
  String? _savedWorkshopCode;
  String? _savedUserRole;
  String? _savedUserDisplayName;
  StreamSubscription<String>? _workshopProfileSubscription;

  @override
  void initState() {
    super.initState();
    _loadLocalWorkshopInfo();
    _workshopProfileSubscription = CloudSyncService().dbUpdateStream.listen((
      event,
    ) {
      if (event == 'workshop_profile_updated' ||
          event == 'cloud_restored' ||
          event == 'supabase_data_updated') {
        _loadLocalWorkshopInfo();
      }
    });
  }

  Future<void> _loadLocalWorkshopInfo() async {
    final prefs = await SharedPreferences.getInstance();
    final savedCode = prefs.getString('workshop_code');
    final localWorkshopName = _usableWorkshopName(
      prefs.getString('workshop_name'),
      code: savedCode,
    );
    if (mounted) {
      setState(() {
        _savedLogoBase64 = prefs.getString('workshop_logo_base64');
        _savedWorkshopName = localWorkshopName.isEmpty
            ? null
            : localWorkshopName;
        _savedWorkshopCode = savedCode;
        _savedUserRole = prefs.getString('user_role');
        final authUser = AppAuthService().currentUser;
        final email = authUser?.email?.trim() ?? '';
        final authName = authUser?.displayName?.trim() ?? '';
        final storedUserName =
            (prefs.getString('user_display_name') ?? '').trim();
        _savedUserDisplayName = storedUserName.isNotEmpty
            ? storedUserName
            : (authName.isNotEmpty
                  ? authName
                  : (email.contains('@') ? email.split('@').first : email));
      });
    }

    // The drawer can also be opened before the legacy Firebase profile has
    // loaded. Resolve the name from the same Supabase account used by the
    // home tab, then cache it for the next rebuild/offline opening.
    try {
      final account = await SupabaseAccountService().loadCurrentAccount();
      final accountName = _usableWorkshopName(
        account?.workshopName,
        code: account?.workshopCode,
      );
      final resolvedName = localWorkshopName.isNotEmpty
          ? localWorkshopName
          : accountName;
      if (resolvedName.isEmpty) return;
      await prefs.setString('workshop_name', resolvedName);
      if (!mounted) return;
      setState(() {
        _savedWorkshopName = resolvedName;
        if (account?.workshopCode.trim().isNotEmpty == true) {
          _savedWorkshopCode = account!.workshopCode.trim();
        }
      });
    } catch (error) {
      debugPrint('Could not load drawer workshop name: $error');
    }
  }

  @override
  void dispose() {
    _workshopProfileSubscription?.cancel();
    _drawerScrollController.dispose();
    super.dispose();
  }

  void _handleDrawerPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent || !_drawerScrollController.hasClients) {
      return;
    }

    final delta = event.scrollDelta.dy != 0
        ? event.scrollDelta.dy
        : event.scrollDelta.dx;
    if (delta == 0) return;

    GestureBinding.instance.pointerSignalResolver.register(event, (_) {
      if (_drawerScrollController.hasClients) {
        _drawerScrollController.position.pointerScroll(delta);
      }
    });
  }

  Widget _buildScrollableDrawerList({required List<Widget> children}) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerSignal: _handleDrawerPointerSignal,
      child: ListView(
        controller: _drawerScrollController,
        primary: false,
        padding: EdgeInsets.zero,
        children: children,
      ),
    );
  }

  /// Only the public workshop join code belongs in the menu. Internal
  /// Supabase UUIDs (or any other long identifier) must never be displayed as
  /// the worker-facing workshop code.
  String _shortWorkshopCode(String? value) {
    final code = value?.replaceAll(RegExp(r'\s+'), ' ').trim() ?? '';
    return RegExp(r'^[A-Za-z0-9]{2,8}(?:[ -][A-Za-z0-9]{1,8})?$').hasMatch(code)
        ? code
        : '';
  }

  String _usableWorkshopName(dynamic value, {String? code}) {
    final name = value?.toString().trim() ?? '';
    final normalizedCode = code?.trim() ?? '';
    const placeholders = {
      'ورشة النجارة',
      'ورشة الألمنيوم',
      'اسم الورشة',
      'menu_principal',
    };
    if (name.isEmpty || name == normalizedCode || placeholders.contains(name)) {
      return '';
    }
    return name;
  }

  Widget _singleLineCodeText(
    String code, {
    TextStyle? style,
    int? maxLines,
    TextOverflow? overflow,
  }) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Text(
          code,
          maxLines: maxLines ?? 1,
          softWrap: false,
          overflow: overflow,
          style: style,
        ),
      ),
    );
  }

  bool _canManageWorkshop(String? role) {
    return const {
      'admin',
      'manager',
      'owner',
      'co_manager',
    }.contains(role?.trim().toLowerCase());
  }

  String _workshopCodeErrorMessage(AppLanguage language, Object error) {
    final details = error.toString().toLowerCase();
    final migrationIsMissing =
        details.contains('workshop_join_code_management.sql') ||
        details.contains('join_code') ||
        details.contains('set_my_workshop_join_code');
    if (migrationIsMissing) {
      return _desktopLabel(
        language,
        arabic:
            'تعذر إنشاء الكود: يجب تطبيق تحديث workshop_join_code_management.sql في Supabase مرة واحدة.',
        french:
            "Impossible de créer le code : appliquez une fois la mise à jour workshop_join_code_management.sql dans Supabase.",
        english:
            'The code could not be created. Apply workshop_join_code_management.sql once in Supabase.',
      );
    }
    return _desktopLabel(
      language,
      arabic: 'تعذر إنشاء كود الورشة. تحقق من الاتصال والصلاحيات.',
      french:
          "Impossible de créer le code de l’atelier. Vérifiez la connexion et les droits.",
      english:
          'Unable to create the workshop code. Check the connection and permissions.',
    );
  }

  Future<String> _createWorkshopJoinCode() async {
    final code = await SupabaseAccountService().createWorkshopJoinCode();
    if (mounted) {
      setState(() => _savedWorkshopCode = code);
    }
    return code;
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
                        .doc(AppAuthService().currentUser!.uid)
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
        // Drawer labels can be long in French (for example sales/distribution
        // descriptions). Let them use a second line instead of overflowing
        // the fixed-width desktop sidebar.
        maxLines: 2,
        softWrap: true,
        overflow: TextOverflow.visible,
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
    required String groupKey,
    required String title,
    required IconData icon,
    required List<Widget> children,
    Color? color,
  }) {
    return ExpansionTile(
      initiallyExpanded: widget.expandedGroup == groupKey,
      leading: Icon(icon, color: Colors.white),
      title: Text(
        title,
        maxLines: 2,
        softWrap: true,
        overflow: TextOverflow.visible,
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
    return FutureBuilder<SupabaseAccountSnapshot?>(
      future: SupabaseAccountService().loadCurrentAccount(),
      builder: (context, snapshot) {
        final account = snapshot.data;
        final accountName = account?.workshopName.trim() ?? '';
        final savedName = _savedWorkshopName?.trim() ?? '';
        final savedCode = _shortWorkshopCode(_savedWorkshopCode);
        final rawAccountCode = account?.workshopCode.trim() ?? '';
        final accountCode = _shortWorkshopCode(rawAccountCode);
        final isSyntheticAdminAccount =
            account != null &&
            account.workshopId == account.userId &&
            rawAccountCode == account.userId;
        final workshopCode = isSyntheticAdminAccount
            ? savedCode
            : (accountCode.isNotEmpty ? accountCode : savedCode);
        final workshopName =
            accountName.isNotEmpty &&
                accountName != account?.workshopCode.trim()
            ? accountName
            : (savedName.isNotEmpty && savedName != savedCode
                  ? savedName
                  : _desktopLabel(
                      lang,
                      arabic: 'القائمة الرئيسية',
                      french: 'Menu principal',
                      english: 'Main menu',
                    ));
        final role =
            account?.role ??
            (isApplicationAdminEmail(AppAuthService().currentUser?.email)
                ? 'admin'
                : (_savedUserRole ?? 'worker'));
        final roleLabel = role == 'admin'
            ? _desktopLabel(
                lang,
                arabic: 'مدير التطبيق',
                french: 'Administrateur',
                english: 'Administrator',
              )
            : _canManageWorkshop(role)
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
        final userEmail = AppAuthService().currentUser?.email?.trim() ?? '';
        final savedUserName = _savedUserDisplayName?.trim() ?? '';
        final userName = savedUserName.isNotEmpty &&
                savedUserName != workshopName
            ? savedUserName
            : (userEmail.contains('@')
                  ? userEmail.split('@').first
                  : roleLabel);

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
                      userName,
                      style: const TextStyle(
                        color: Color(0xFFE0F2FE),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      userEmail,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFFE0F2FE),
                        fontSize: 11,
                      ),
                    ),
                    if (workshopCode.isNotEmpty)
                      _singleLineCodeText(
                        '${_desktopLabel(lang, arabic: 'كود الورشة', french: "Code de l'atelier", english: 'Workshop code')}: $workshopCode',
                        overflow: TextOverflow.visible,
                        style: const TextStyle(
                          color: Color(0xFFE0F2FE),
                          fontSize: 11,
                          letterSpacing: 0.5,
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
    return FutureBuilder<SupabaseAccountSnapshot?>(
      future: SupabaseAccountService().loadCurrentAccount(),
      builder: (context, snapshot) {
        final account = snapshot.data;
        final role =
            account?.role ??
            (isApplicationAdminEmail(AppAuthService().currentUser?.email)
                ? 'admin'
                : (_savedUserRole ?? 'worker'));
        if (!_canManageWorkshop(role)) {
          return const SizedBox.shrink();
        }
        final rawAccountCode = account?.workshopCode.trim() ?? '';
        final accountCode = _shortWorkshopCode(rawAccountCode);
        final isSyntheticAdminAccount =
            account != null &&
            account.workshopId == account.userId &&
            rawAccountCode == account.userId;
        final joinCode = isSyntheticAdminAccount
            ? _shortWorkshopCode(_savedWorkshopCode)
            : (accountCode.isNotEmpty
                  ? accountCode
                  : _shortWorkshopCode(_savedWorkshopCode));
        final hasCode = joinCode.isNotEmpty;

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
              ? _singleLineCodeText(
                  joinCode,
                  overflow: TextOverflow.visible,
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
                  style: TextButton.styleFrom(foregroundColor: Colors.white),
                  onPressed: () async {
                    try {
                      await _createWorkshopJoinCode();
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
                      debugPrint('Workshop join code creation failed: $error');
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              _workshopCodeErrorMessage(lang, error),
                            ),
                          ),
                        );
                      }
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
      context.read<WorkspaceController>().resetForSignedOut();
      // Notify the root auth gate first. Waiting for cloud/local cleanup here
      // can leave Android showing only the launcher/background while the
      // sync service still owns database listeners.
      await AppAuthService().signOut();
      await AppAuthService().signOutGoogleSession();
      CloudSyncService().reset();
      SupabaseWorkshopSyncService().stop();
      unawaited(CloudSyncService().clearCachedWorkshopContext());
      unawaited(SqlDatabase.clearAllLocalData());
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
          groupKey: 'orders',
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
          groupKey: 'purchases',
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
          groupKey: 'inventory',
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
          groupKey: 'finance',
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
          groupKey: 'clients',
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
            maxLines: 2,
            softWrap: true,
            overflow: TextOverflow.visible,
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
          groupKey: 'tasks',
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
        groupKey: 'management',
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
        groupKey: 'account',
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
          child: _buildScrollableDrawerList(children: menu),
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
      child: _buildScrollableDrawerList(
        children: [
          StreamBuilder<DocumentSnapshot>(
            stream: AppAuthService().currentUser != null
                ? FirebaseFirestore.instance
                      .collection('users')
                      .doc(AppAuthService().currentUser!.uid)
                      .snapshots()
                : null,
            builder: (context, snapshot) {
              String workshopName = _usableWorkshopName(_savedWorkshopName);
              if (workshopName.isEmpty) {
                workshopName = Localization.translate('اسم الورشة', lang);
              }
              String userEmail = AppAuthService().currentUser?.email ?? '';
              String? logoBase64;
              String? joinCode;
              String? role;
              String displayName = '';

              if (snapshot.hasData && snapshot.data!.exists) {
                final data = snapshot.data!.data() as Map<String, dynamic>;
                // Firebase is legacy data. It may contain the old default
                // name, so it must not overwrite the Supabase/local name.
                final savedName = _usableWorkshopName(_savedWorkshopName);
                final legacyName = _usableWorkshopName(
                  data['workshopName'],
                  code: _savedWorkshopCode,
                );
                workshopName = savedName.isNotEmpty
                    ? savedName
                    : (legacyName.isNotEmpty ? legacyName : workshopName);
                logoBase64 =
                    (data['workshopLogoUrl'] as String?)?.isNotEmpty == true
                    ? data['workshopLogoUrl']
                    : _savedLogoBase64;
                joinCode = data['joinCode'];
                role = data['role'];
                final legacyDisplayName =
                    data['displayName']?.toString().trim() ?? '';
                final savedUserName = _savedUserDisplayName?.trim() ?? '';
                final authDisplayName =
                    AppAuthService().currentUser?.displayName?.trim() ?? '';
                displayName = savedUserName.isNotEmpty
                    ? savedUserName
                    : (authDisplayName.isNotEmpty
                          ? authDisplayName
                          : legacyDisplayName);
              }

              if (displayName.trim().isEmpty ||
                  displayName.trim() == workshopName.trim()) {
                displayName = userEmail.contains('@')
                    ? userEmail.split('@').first
                    : Localization.translate('المستخدم', lang);
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
          FutureBuilder<SupabaseAccountSnapshot?>(
            future: SupabaseAccountService().loadCurrentAccount(),
            builder: (context, snapshot) {
              final account = snapshot.data;
              final joinCode = _shortWorkshopCode(
                account?.workshopCode.isNotEmpty == true
                    ? account!.workshopCode
                    : _savedWorkshopCode,
              );
              final role =
                  isApplicationAdminEmail(AppAuthService().currentUser?.email)
                  ? 'admin'
                  : (account?.role ?? _savedUserRole);

              if (_canManageWorkshop(role)) {
                if (joinCode.isNotEmpty) {
                  final visibleCode = joinCode;
                  final isDark =
                      Theme.of(context).brightness == Brightness.dark;
                  return Container(
                    color: isDark
                        ? const Color(0xFF1E293B)
                        : Colors.blue.shade50,
                    child: ListTile(
                      leading: Icon(
                        Icons.qr_code,
                        color: isDark ? Colors.lightBlue.shade300 : Colors.blue,
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
                      subtitle: _singleLineCodeText(
                        visibleCode,
                        overflow: TextOverflow.visible,
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
                          Clipboard.setData(ClipboardData(text: visibleCode));
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
                      leading: const Icon(Icons.qr_code, color: Colors.orange),
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
                        style: ElevatedButton.styleFrom(
                          foregroundColor: Colors.white,
                          backgroundColor: const Color(0xFF2563EB),
                          minimumSize: const Size(118, 40),
                        ),
                        onPressed: () async {
                          try {
                            await _createWorkshopJoinCode();
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
                            debugPrint(
                              'Workshop join code creation failed: $e',
                            );
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    _workshopCodeErrorMessage(lang, e),
                                  ),
                                ),
                              );
                            }
                          }
                        },
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            Localization.translate('توليد الآن', lang),
                            maxLines: 1,
                            softWrap: false,
                          ),
                        ),
                      ),
                    ),
                  );
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
          if (AppAuthService().currentUser == null)
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
                  context.read<WorkspaceController>().resetForSignedOut();
                  await AppAuthService().signOut();
                  await AppAuthService().signOutGoogleSession();
                  CloudSyncService().reset();
                  SupabaseWorkshopSyncService().stop();
                  unawaited(CloudSyncService().clearCachedWorkshopContext());
                  unawaited(SqlDatabase.clearAllLocalData());
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
