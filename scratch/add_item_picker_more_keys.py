import sys

sys.stdout.reconfigure(encoding='utf-8')

path = 'lib/settings/locales/general_keys.dart'
content = open(path, encoding='utf-8').read()

new_keys = {
    'المستودع (إضافة للفاتورة)': {'ar': 'المستودع (إضافة للفاتورة)', 'fr': 'Dépôt (Ajouter à la facture)', 'en': 'Warehouse (Add to Invoice)'},
    'السلسلة (Série)': {'ar': 'السلسلة (Série)', 'fr': 'Série', 'en': 'Series'},
    'البحث عن المادة...': {'ar': 'البحث عن المادة...', 'fr': 'Rechercher l\'article...', 'en': 'Search item...'},
    'مثال: كادر، أوفرو...': {'ar': 'مثال: كادر، أوفرو...', 'fr': 'Ex: Cadre, Ouvrant...', 'en': 'e.g. Frame, Sash...'},
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
print(f"Appended {len(new_keys)} new item picker more keys.")

open(path, 'w', encoding='utf-8').write(content)
print("Done updating general_keys.dart with item picker more keys!")
