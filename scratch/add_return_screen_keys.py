import sys

sys.stdout.reconfigure(encoding='utf-8')

path = 'lib/settings/locales/general_keys.dart'
content = open(path, encoding='utf-8').read()

new_keys = {
    'فاتورة: ': {'ar': 'فاتورة: ', 'fr': 'Facture : ', 'en': 'Invoice: '},
    'الكمية المتاحة: ': {'ar': 'الكمية المتاحة: ', 'fr': 'Quantité disponible : ', 'en': 'Available quantity: '},
    'المراد إرجاعه: ': {'ar': 'المراد إرجاعه: ', 'fr': 'À retourner : ', 'en': 'To return: '},
}

new_entries = []
for term, trans in new_keys.items():
    ar_esc = trans['ar'].replace("'", "\\'")
    fr_esc = trans['fr'].replace("'", "\\'")
    en_esc = trans['en'].replace("'", "\\'")
    entry = f"""  '{term}': {{
    AppLanguage.arabic: '{ar_esc}',
    AppLanguage.french: '{fr_esc}',
    AppLanguage.english: '{en_esc}',
  }},"""
    new_entries.append(entry)

new_entries_str = "\n".join(new_entries)
content = content.replace("};", new_entries_str + "\n};")
print(f"Appended {len(new_keys)} new return screen keys.")

open(path, 'w', encoding='utf-8').write(content)
print("Done updating general_keys.dart with return screen keys!")
