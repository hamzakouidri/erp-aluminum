import re

file_path = "lib/Screen/drawer.dart"
with open(file_path, "r", encoding="utf-8") as f:
    content = f.read()

import_statement = "import 'price_management_screen.dart';\n"
if "price_management_screen.dart" not in content:
    content = content.replace("import 'settings_screen.dart';", "import 'settings_screen.dart';\n" + import_statement)

list_tile = """
          ListTile(
            leading: const Icon(Icons.monetization_on),
            title: Text(Localization.translate('O"O-OO1O_ O U,OO3O OO1', lang)),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => PriceManagementScreen()),
              );
            },
          ),
"""

if "PriceManagementScreen" not in content:
    content = content.replace("          ListTile(\n            leading: const Icon(Icons.settings),", list_tile + "          ListTile(\n            leading: const Icon(Icons.settings),")

with open(file_path, "w", encoding="utf-8") as f:
    f.write(content)
