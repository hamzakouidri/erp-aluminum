import 'package:database_data/Screen/workers_management_screen.dart';
import 'package:database_data/Screen/treasury_screen.dart';
import 'package:database_data/Screen/worker_finances_screen.dart';
import '../items_produits/products_menu_screen.dart';
import 'admin_users_screen.dart';
import 'dart:math' as dart_math;
import 'package:database_data/Screen/support_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../Cliente/client.dart';
import '../Commande/commande.dart';
import '../sql_database.dart';
import 'achat_screen.dart';
import 'settings_screen.dart';
import 'price_management_screen.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../login_screen.dart';
import 'package:provider/provider.dart';
import '../settings/app_settings.dart';
import '../settings/localization.dart';

class AppDrawer extends StatelessWidget {
  SqlDatabase db = SqlDatabase();

  AppDrawer({super.key});

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
              String? logoUrl;

              String? joinCode;
              String? role;

              if (snapshot.hasData && snapshot.data!.exists) {
                final data = snapshot.data!.data() as Map<String, dynamic>;
                workshopName = data['workshopName'] ?? workshopName;
                logoUrl = data['logoUrl'];
                joinCode = data['joinCode'];
                role = data['role'];
              }

              return UserAccountsDrawerHeader(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF2563EB), Color(0xFF0EA5E9)],
                  ),
                ),
                accountName: Text(
                  workshopName,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
                accountEmail: Text(userEmail),
                currentAccountPicture: CircleAvatar(
                  backgroundColor: Colors.white,
                  backgroundImage: logoUrl != null
                      ? NetworkImage(logoUrl)
                      : null,
                  child: logoUrl == null
                      ? const Icon(
                          Icons.storefront,
                          size: 40,
                          color: Color(0xFF2563EB),
                        )
                      : null,
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

                if (role == 'manager') {
                  if (joinCode != null && joinCode.isNotEmpty) {
                    return Container(
                      color: Colors.blue.shade50,
                      child: ListTile(
                        leading: const Icon(Icons.qr_code, color: Colors.blue),
                        title: const Text(
                          'كود انضمام العمال',
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
                              const SnackBar(
                                content: Text('تم نسخ كود الورشة بنجاح!'),
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
                        title: const Text('توليد كود الورشة', style: TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: const Text('انقر هنا لإنشاء كود لعمالك'),
                        trailing: ElevatedButton(
                          onPressed: () async {
                            final uid = FirebaseAuth.instance.currentUser!.uid;
                            const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
                            final rnd = dart_math.Random();
                            final newCode = String.fromCharCodes(Iterable.generate(6, (_) => chars.codeUnitAt(rnd.nextInt(chars.length))));
                            
                            try {
                              await FirebaseFirestore.instance.collection('users').doc(uid).update({'joinCode': newCode});
                              await FirebaseFirestore.instance.collection('workshops').doc(uid).set({'joinCode': newCode, 'managerUid': uid}, SetOptions(merge: true));
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم إنشاء الكود بنجاح!')));
                              }
                            } catch (e) {
                              print('Error generating code: $e');
                            }
                          },
                          child: const Text('توليد الآن'),
                        ),
                      ),
                    );
                  }
                }
              }
              return const SizedBox.shrink();
            },
          ),
          if (settings.canViewOrders())
            ListTile(
              leading: const Icon(Icons.list),
              title: Text(Localization.translate('commandes', lang)),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => Commande()),
                );
              },
            ),

          if (settings.canViewClients())
            ListTile(
              leading: const Icon(Icons.groups),
              title: Text(Localization.translate('clients', lang)),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => Customers()),
                );
              },
            ),
          if (settings.canRegisterPurchases())
            ListTile(
              leading: const Icon(Icons.shopping_bag_rounded),
              title: Text(Localization.translate('achat', lang)),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => AchatScreen(db: SqlDatabase()),
                  ),
                );
              },
            ),
          // Vente might be orders creation or just another view, assuming viewOrders
          if (settings.canViewOrders())
            ListTile(
              leading: const Icon(Icons.back_hand),
              title: Text(Localization.translate('vente', lang)),
              onTap: () {
                Navigator.pop(context);
              },
            ),
          ListTile(
            leading: const Icon(Icons.production_quantity_limits),
            title: Text(Localization.translate('produits', lang)),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => (ProductsMenuScreen(db: db)),
                ),
              );
            },
          ),
          if (settings.canAccessTreasury())
            ListTile(
              leading: const Icon(Icons.money),
              title: Text(Localization.translate('caisse', lang)),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => TreasuryScreen(db: SqlDatabase()),
                  ),
                );
              },
            ),
          if (settings.canManageWorkers())
            ListTile(
              leading: const Icon(Icons.engineering),
              title: Text(Localization.translate('ouvrier', lang)),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) =>
                        WorkersManagementScreen(db: SqlDatabase()),
                  ),
                );
              },
            ),
          if (settings.canViewStatistics())
            ListTile(
              leading: const Icon(Icons.calculate),
              title: Text(Localization.translate('statistiques', lang)),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => WorkerFinancesScreen(db: SqlDatabase()),
                  ),
                );
              },
            ),

          if (settings.canChangePrices())
            ListTile(
              leading: const Icon(Icons.monetization_on),
              title: Text(Localization.translate('Manage Prices', lang)),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => PriceManagementScreen(),
                  ),
                );
              },
            ),
          if (isAdmin)
            ListTile(
              leading: const Icon(
                Icons.admin_panel_settings,
                color: Colors.blue,
              ),
              title: const Text(
                'إدارة المستخدمين والاشتراكات',
                style: TextStyle(
                  color: Colors.blue,
                  fontWeight: FontWeight.bold,
                ),
              ),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const AdminUsersScreen(),
                  ),
                );
              },
            ),
          ListTile(
            leading: const Icon(Icons.settings),
            title: Text(Localization.translate('settings', lang)),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const SettingsScreen()),
              );
            },
          ),

          const Divider(),
          ListTile(
            leading: const Icon(Icons.support_agent, color: Colors.green),
            title: Text('مراسلة الإدارة وتقييم التطبيق'),
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
              // تسجيل الخروج من Firebase
              await FirebaseAuth.instance.signOut();
              SqlDatabase.resetDb();
              // الانتقال إلى شاشة تسجيل الدخول وحذف جميع الشاشات السابقة
              if (context.mounted) {
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(builder: (context) => const LoginScreen()),
                  (route) => false,
                );
              }
            },
          ),
        ],
      ),
    );
  }
}
