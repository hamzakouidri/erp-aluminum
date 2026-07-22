import sys

sys.stdout.reconfigure(encoding='utf-8')

path = 'lib/settings/locales/general_keys.dart'
content = open(path, encoding='utf-8').read()

new_key = """  'موقع النافذة (مثال: المطبخ - الطابق 2)': {
    AppLanguage.arabic: 'موقع النافذة (مثال: المطبخ - الطابق 2)',
    AppLanguage.french: 'Emplacement de la fenêtre (Ex: Cuisine - 2ème Étage)',
    AppLanguage.english: 'Window Location (e.g., Kitchen - 2nd Floor)',
  },"""

content = content.replace("};", new_key + "\n};")
open(path, 'w', encoding='utf-8').write(content)
print("Done adding position input translation to general_keys.dart!")
