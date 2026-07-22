import os

dart_file = "lib/settings/locales/general_keys.dart"

new_keys = {
    'جديد': {'fr': 'Nouveau', 'en': 'New'},
    'المستودع الرئيسي': {'fr': 'Entrepôt principal', 'en': 'Main Warehouse'},
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
