import os
import re

dart_file = "lib/settings/locales/general_keys.dart"

new_keys = {
    'دج': {'fr': 'D.A.', 'en': 'D.A.'},
}

with open(dart_file, 'r', encoding='utf-8') as f:
    content = f.read()

content = content.rstrip()
if content.endswith('};'):
    content = content[:-2]

appends = ""
for ar, langs in new_keys.items():
    fr_val = langs["fr"].replace("'", "\\'")
    en_val = langs["en"].replace("'", "\\'")
    
    replacement = "  '{0}': {{\n    AppLanguage.arabic: '{0}',\n    AppLanguage.french: '{1}',\n    AppLanguage.english: '{2}',\n  }},".format(ar, fr_val, en_val)
    
    pattern = "'{0}': \\{{[^\\}}]+\\}},".format(ar)
    if re.search("'{0}': \\{{".format(ar), content):
        content = re.sub(pattern, replacement, content)
    else:
        appends += replacement + "\n"

if appends:
    content += "\n" + appends

content += "\n};\n"

with open(dart_file, 'w', encoding='utf-8') as f:
    f.write(content)
print("Updated currency keys.")
