import 'package:database_data/Screen/workers_management_screen.dart';
import 'package:database_data/Screen/treasury_screen.dart';
import 'package:database_data/Screen/worker_finances_screen.dart';
import '../items_produits/products_menu_screen.dart';
import 'admin_users_screen.dart';
import 'projects_screen.dart';
import 'sales_screen.dart';
import 'dart:math' as dart_math;
import 'package:database_data/Screen/support_dialog.dart';
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
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../login_screen.dart';
import 'inventory_screen.dart';
import 'package:provider/provider.dart';
import '../settings/app_settings.dart';
import '../settings/localization.dart';
import 'dart:convert';
import 'worker_tasks_screen.dart';
import 'worker_weekly_settlement_screen.dart';


class AppDrawer extends StatefulWidget {
  const AppDrawer({super.key});

  @override
  State<AppDrawer> createState() => _AppDrawerState();
}

class _AppDrawerState extends State<AppDrawer> {
  SqlDatabase db = SqlDatabase();

  void _openScreen(String title, IconData icon, Widget screen, {String? titleKey}) {
    Navigator.pop(context);
    Future.delayed(Duration.zero, () {
      if (!mounted) return;
      openAdaptiveScreen(context, title: titleKey ?? title, icon: icon, screen: screen);
    });
  }

  Future<void> _updateDisplayName(
    BuildContext context,
    String currentName,
  ) async {
    final lang = Provider.of<AppSettingsProvider>(context, listen: false).language;
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
                        SnackBar(content: Text(Localization.translate('تم تحديث الاسم بنجاح', lang))),
                      );
                    }
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('${Localization.translate('خطأ في التحديث: ', lang)}$e')),
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

  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<AppSettingsProvider>(context);
    final lang = settings.language;
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
                workshopName = data['workshopName'] ?? workshopName;
                logoBase64 = data['workshopLogoUrl'];
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
                    colors: Theme.of(context).brightness == Brightness.dark ? [Color(0xFF111827), Color(0xFF070E1D)] : [Color(0xFF2563EB), Color(0xFF0EA5E9)], ),
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
                    final hasLogo = logoBase64 != null && logoBase64.isNotEmpty;
                    return CircleAvatar(
                      radius: 40,
                      backgroundColor: Theme.of(context).cardColor,
                      backgroundImage: hasLogo
                          ? MemoryImage(base64Decode(logoBase64 ?? ''))
                          : null,
                      child: !hasLogo
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
                    return Container(
                      color: Colors.blue.shade50,
                      child: ListTile(
                        leading: const Icon(Icons.qr_code, color: Colors.blue),
                        title: Text(
                          Localization.translate('كود انضمام العمال', lang),
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.blue,
                          ),
                        ),
                        subtitle: Text(
                          joinCode,
                          style: const TextStyle(
                            fontSize: 18,
                            letterSpacing: 2,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.copy, color: Colors.blue),
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: joinCode));
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(Localization.translate('تم نسخ كود الورشة بنجاح!', lang)),
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
                        subtitle: Text(Localization.translate('انقر هنا لإنشاء كود لعمالك', lang)),
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
                                    content: Text(Localization.translate('تم إنشاء الكود بنجاح!', lang)),
                                  ),
                                );
                              }
                            } catch (e) {
                              print('Error generating code: $e');
                            }
                          },
                          child: Text(Localization.translate('توليد الآن', lang)),
                        ),
                      ),
                    );
                  }
                }
              }
              return const SizedBox.shrink();
            },
          ),
          if (settings.userRole == 'worker' || settings.isManager)
            ListTile(
              leading: const Icon(Icons.engineering_rounded, color: Colors.indigo),
              title: Text(lang == AppLanguage.arabic ? 'مهامي وتصنيعاتي' : 'Mes Tâches'),
              onTap: () {
                _openScreen(
                  lang == AppLanguage.arabic ? 'مهامي وتصنيعاتي' : 'Mes Tâches',
                  Icons.engineering_rounded,
                  WorkerTasksScreen(db: db),
                  titleKey: lang == AppLanguage.arabic ? 'مهامي وتصنيعاتي' : 'Mes Tâches',
                );
              },
            ),
          ListTile(
            leading: const Icon(Icons.construction_rounded, color: Colors.teal),
            title: Text(lang == AppLanguage.arabic
                ? 'الأعمال والمهمات الخارجية'
                : (lang == AppLanguage.french ? 'Opérations Externe' : 'External Operations')),
            onTap: () {
              _openScreen(
                lang == AppLanguage.arabic ? 'الأعمال والمهمات الخارجية' : 'Opérations Externe',
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

          if (settings.canViewOrders())
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
          if (settings.canViewClients())
            ListTile(
              leading: const Icon(Icons.history_edu_rounded, color: Colors.blue),
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
          if (settings.canViewOrders())
            ListTile(
              leading: const Icon(Icons.delivery_dining_rounded, color: Colors.blue),
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
          // Vente might be orders creation or just another view, assuming viewOrders
          if (settings.canViewOrders())
            ListTile(
              leading: const Icon(Icons.monetization_on_rounded, color: Colors.teal),
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
          if (settings.isManager)
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
          if (settings.isManager)
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
          if (settings.canViewStatistics())
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
          if (settings.canViewStatistics())
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

          if (settings.canViewStatistics())
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
          ListTile(
            leading: const Icon(Icons.dashboard_customize_rounded, color: Colors.teal),
            title: Text(Localization.translate('تحديد الأنظمة المستعملة', lang)),
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
                Localization.translate(Localization.translate('إدارة المستخدمين والاشتراكات', lang), lang),
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
          if (settings.isManager)
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

          const Divider(),
          ListTile(
            leading: const Icon(Icons.support_agent, color: Colors.green),
            title: Text(Localization.translate('مراسلة الإدارة وتقييم التطبيق', lang)),
            onTap: () {
              Navigator.pop(context);
              showDialog(context: context, builder: (_) => SupportDialog());
            },
          ),
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
