import os
import json

dart_file = "lib/settings/locales/general_keys.dart"

new_keys = {
    'الشامبانيا': {'fr': 'Champagne', 'en': 'Champagne'},
    'الخشبي الفاتح': {'fr': 'Faux bois clair', 'en': 'Light Wood'},
    'الأزرق': {'fr': 'Bleu', 'en': 'Blue'},
    'أزرق بلجيكي': {'fr': 'Bleu Belge', 'en': 'Belgian Blue'},
    'رمادي بلجيكي': {'fr': 'Gris Belge', 'en': 'Belgian Grey'},
    'الذهبي': {'fr': 'Doré', 'en': 'Gold'},
    'الفضي': {'fr': 'Argent', 'en': 'Silver'},
    'الخشبي الداكن': {'fr': 'Faux bois foncé', 'en': 'Dark Wood'},
    
    # Let's add other common variations just in case
    'الأبيض': {'fr': 'Blanc', 'en': 'White'},
    'الأسود': {'fr': 'Noir', 'en': 'Black'},
    'الرمادي': {'fr': 'Gris', 'en': 'Grey'},
    'البني': {'fr': 'Marron', 'en': 'Brown'},
    'البيج': {'fr': 'Beige', 'en': 'Beige'},
    'الخام': {'fr': 'Brut', 'en': 'Raw'},
    'الأصفر': {'fr': 'Jaune', 'en': 'Yellow'},
    'الأحمر': {'fr': 'Rouge', 'en': 'Red'},
    'الأخضر': {'fr': 'Vert', 'en': 'Green'},
    'الخشبي': {'fr': 'Faux bois', 'en': 'Wood'},
}

with open(dart_file, 'r', encoding='utf-8') as f:
    content = f.read()

# Remove the trailing '};' so we can append
content = content.rstrip()
if content.endswith('};'):
    content = content[:-2]

# Prepare string to append
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
