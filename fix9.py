import sys

with open('lib/Screen/drawer.dart', 'r', encoding='utf-8') as f:
    content = f.read()

# Add imports
imports = """import 'package:database_data/Screen/workers_management_screen.dart';
import 'package:database_data/Screen/treasury_screen.dart';
import 'package:database_data/Screen/worker_finances_screen.dart';
"""
content = content.replace("import 'package:database_data/Screen/workers_management_screen.dart';", imports)

old_admin_menu = """                  if (Provider.of<AppSettingsProvider>(context).isManager) ...[
                    ListTile(
                      leading: const Icon(Icons.people),
                      title: const Text('إدارة العمال (الصلاحيات)'),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const WorkersManagementScreen(),
                          ),
                        );
                      },
                    ),
                  ],"""

new_admin_menu = """                  if (Provider.of<AppSettingsProvider>(context).isManager) ...[
                    ListTile(
                      leading: const Icon(Icons.people),
                      title: const Text('إدارة العمال (الصلاحيات)'),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const WorkersManagementScreen(),
                          ),
                        );
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.account_balance_wallet),
                      title: const Text('الصندوق المالي'),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => TreasuryScreen(db: db),
                          ),
                        );
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.money),
                      title: const Text('سلفيات وأجور العمال'),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => WorkerFinancesScreen(db: db),
                          ),
                        );
                      },
                    ),
                  ],"""

content = content.replace(old_admin_menu, new_admin_menu)

with open('lib/Screen/drawer.dart', 'w', encoding='utf-8') as f:
    f.write(content)
