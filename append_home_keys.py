import os
import re

dart_file = "lib/settings/locales/general_keys.dart"

new_keys = {
    'إدارة الكتالوج (Profiles & Sections)': {'fr': 'Gestion du catalogue', 'en': 'Catalog Management'},
    'إدارة الكتالوج': {'fr': 'Gestion du catalogue', 'en': 'Catalog Management'},
    'تحليل الطلبيات': {'fr': 'Analyse des commandes', 'en': 'Orders Analysis'},
    'حالة الطلبيات': {'fr': 'Statut des commandes', 'en': 'Orders Status'},
    'دائري': {'fr': 'Circulaire', 'en': 'Pie Chart'},
    'أشهر': {'fr': 'Mois', 'en': 'Months'},
    'منحنى بياني': {'fr': 'Graphique linéaire', 'en': 'Line Chart'},
    'قيد الانتظار': {'fr': 'En attente', 'en': 'Pending'},
    'مؤكدة': {'fr': 'Confirmée', 'en': 'Confirmed'},
    'جارية': {'fr': 'En cours', 'en': 'In Progress'},
    'تركيب': {'fr': 'Installation', 'en': 'Installation'},
    'منتهية': {'fr': 'Terminée', 'en': 'Done'},
    'جديدة': {'fr': 'Nouvelle', 'en': 'New'},
    'أخرى': {'fr': 'Autre', 'en': 'Other'},
    'إجمالي': {'fr': 'Total', 'en': 'Total'},
}

with open(dart_file, 'r', encoding='utf-8') as f:
    content = f.read()

content = content.rstrip()
if content.endswith('};'):
    content = content[:-2]

appends = ""
for ar, langs in new_keys.items():
    if f"'{ar}'" not in content and f'"{ar}"' not in content:
        appends += f"  '{ar}': {{\n"
        appends += f"    AppLanguage.arabic: '{ar}',\n"
        appends += f"    AppLanguage.french: '{langs['fr'].replace('\'', '\\\'')}',\n"
        appends += f"    AppLanguage.english: '{langs['en'].replace('\'', '\\\'')}',\n"
        appends += "  },\n"

if appends:
    new_content = content + "\n" + appends + "};\n"
    with open(dart_file, 'w', encoding='utf-8') as f:
        f.write(new_content)
    print(f"Added {appends.count('AppLanguage.arabic')} new keys.")
else:
    print("No new keys to add.")
