import sys

sys.stdout.reconfigure(encoding='utf-8')

path = 'lib/settings/locales/general_keys.dart'
content = open(path, encoding='utf-8').read()

new_keys = {
    'تراجع عن التعديلات': {'ar': 'تراجع عن التعديلات', 'fr': 'Annuler les modifications', 'en': 'Discard Changes'},
    'صورة الفاتورة المرفقة': {'ar': 'صورة الفاتورة المرفقة', 'fr': 'Image de facture jointe', 'en': 'Attached Invoice Image'},
    'ملف PDF محفوظ': {'ar': 'ملف PDF محفوظ', 'fr': 'Fichier PDF enregistré', 'en': 'Saved PDF File'},
    'فتح': {'ar': 'فتح', 'fr': 'Ouvrir', 'en': 'Open'},
    'إرفاق صورة': {'ar': 'إرفاق صورة', 'fr': 'Joindre une image', 'en': 'Attach Image'},
    'حفظ PDF': {'ar': 'حفظ PDF', 'fr': 'Enregistrer en PDF', 'en': 'Save PDF'},
    'إجمالي العناصر: ': {'ar': 'إجمالي العناصر: ', 'fr': 'Total des articles : ', 'en': 'Total Items: '},
    'المتبقي: ': {'ar': 'المتبقي: ', 'fr': 'Reste : ', 'en': 'Remaining: '},
    'لا توجد عناصر مضافة بعد.': {'ar': 'لا توجد عناصر مضافة بعد.', 'fr': 'Aucun article ajouté pour le moment.', 'en': 'No items added yet.'},
    'عنصر': {'ar': 'عنصر', 'fr': 'Article', 'en': 'Item'},
    'النوع: ': {'ar': 'النوع: ', 'fr': 'Type : ', 'en': 'Type: '},
    'اللون: ': {'ar': 'اللون: ', 'fr': 'Couleur : ', 'en': 'Color: '},
    'الكمية: ': {'ar': 'الكمية: ', 'fr': 'Quantité : ', 'en': 'Quantity: '},
    'سعر الوحدة: ': {'ar': 'سعر الوحدة: ', 'fr': 'Prix unitaire : ', 'en': 'Unit Price: '},
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
print(f"Appended {len(new_keys)} new purchase details more keys.")

open(path, 'w', encoding='utf-8').write(content)
print("Done updating general_keys.dart with purchase details more keys!")
