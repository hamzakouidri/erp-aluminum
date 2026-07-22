import os

dart_file = "lib/settings/locales/general_keys.dart"

new_keys = {
    'الأزرق البلجيكي': {'fr': 'Bleu Belge', 'en': 'Belgian Blue'},
    'الازرق البلجيكي': {'fr': 'Bleu Belge', 'en': 'Belgian Blue'},
    'ازرق بلجيكي': {'fr': 'Bleu Belge', 'en': 'Belgian Blue'},
    'الرمادي البلجيكي': {'fr': 'Gris Belge', 'en': 'Belgian Grey'},
    'رمادي بلجيكي': {'fr': 'Gris Belge', 'en': 'Belgian Grey'},
    'الاخضر': {'fr': 'Vert', 'en': 'Green'},
    'الازرق': {'fr': 'Bleu', 'en': 'Blue'},
    'الأبيض': {'fr': 'Blanc', 'en': 'White'},
    'الابيض': {'fr': 'Blanc', 'en': 'White'},
    'الأسود': {'fr': 'Noir', 'en': 'Black'},
    'الاسود': {'fr': 'Noir', 'en': 'Black'},
    'الاحمر': {'fr': 'Rouge', 'en': 'Red'},
    'الاصفر': {'fr': 'Jaune', 'en': 'Yellow'},
    'أخضر': {'fr': 'Vert', 'en': 'Green'},
    'شومبانيا': {'fr': 'Champagne', 'en': 'Champagne'},
    'الشامبني': {'fr': 'Champagne', 'en': 'Champagne'},
    'الشامبان': {'fr': 'Champagne', 'en': 'Champagne'},
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
