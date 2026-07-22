import sys

sys.stdout.reconfigure(encoding='utf-8')

path = 'lib/settings/locales/general_keys.dart'
content = open(path, encoding='utf-8').read()

new_keys = {
    'إضافة للفاتورة': {'ar': 'إضافة للفاتورة', 'fr': 'Ajouter à la facture', 'en': 'Add to Invoice'},
    'إضافة: ': {'ar': 'إضافة: ', 'fr': 'Ajouter : ', 'en': 'Add: '},
    'الكمية (عدد)': {'ar': 'الكمية (عدد)', 'fr': 'Quantité (Nombre)', 'en': 'Quantity (Count)'},
    'السعر للوحدة': {'ar': 'السعر للوحدة', 'fr': 'Prix unitaire', 'en': 'Unit Price'},
    'هذا العنصر موجود بالفعل في الفاتورة': {'ar': 'هذا العنصر موجود بالفعل في الفاتورة', 'fr': 'Cet article existe déjà dans la facture', 'en': 'This item already exists in the invoice'},
    'تم إضافة العنصر بنجاح!': {'ar': 'تم إضافة العنصر بنجاح!', 'fr': 'Article ajouté avec succès !', 'en': 'Item added successfully!'},
    'لا توجد عناصر مطابقة': {'ar': 'لا توجد عناصر مطابقة', 'fr': 'Aucun élément correspondant', 'en': 'No matching items'},
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
print(f"Appended {len(new_keys)} new item picker final keys.")

open(path, 'w', encoding='utf-8').write(content)
print("Done updating general_keys.dart with item picker final keys!")
