import sys

sys.stdout.reconfigure(encoding='utf-8')

path = 'lib/settings/locales/general_keys.dart'
content = open(path, encoding='utf-8').read()

new_keys = {
    'ملف المورد: ': {'ar': 'ملف المورد: ', 'fr': 'Profil du fournisseur : ', 'en': 'Supplier Profile: '},
    'إجمالي المشتريات': {'ar': 'إجمالي المشتريات', 'fr': 'Total achats', 'en': 'Total Purchases'},
    'الديون': {'ar': 'الديون', 'fr': 'Dettes', 'en': 'Debts'},
    'سجل الفواتير': {'ar': 'سجل الفواتير', 'fr': 'Historique des factures', 'en': 'Invoices History'},
    'لا توجد فواتير مسجلة لهذا المورد': {'ar': 'لا توجد فواتير مسجلة لهذا المورد', 'fr': 'Aucune facture enregistrée pour ce fournisseur', 'en': 'No invoices registered for this supplier'},
    'فاتورة #': {'ar': 'فاتورة #', 'fr': 'Facture N° ', 'en': 'Invoice #'},
    'الحالة: ': {'ar': 'الحالة: ', 'fr': 'Statut : ', 'en': 'Status: '},
    'مؤكدة': {'ar': 'مؤكدة', 'fr': 'Confirmée', 'en': 'Confirmed'},
    'قيد التعديل': {'ar': 'قيد التعديل', 'fr': 'En cours de modification', 'en': 'Pending Modification'},
    'الإجمالي: ': {'ar': 'الإجمالي: ', 'fr': 'Total : ', 'en': 'Total: '},
    'المدفوع: ': {'ar': 'المدفوع: ', 'fr': 'Payé : ', 'en': 'Paid: '},
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
print(f"Appended {len(new_keys)} new supplier details keys.")

open(path, 'w', encoding='utf-8').write(content)
print("Done updating general_keys.dart with supplier details keys!")
