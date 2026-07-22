import os
import re

dart_file = "lib/settings/locales/general_keys.dart"

new_keys = {
    'دائري': {'fr': 'Circulaire', 'en': 'Pie'},
    'أشهر': {'fr': 'Mois', 'en': 'Months'},
    'منحنى بياني': {'fr': 'Lignes', 'en': 'Lines'},
    
    'D.N.A. جزائري': {'fr': 'D.A.', 'en': 'D.A.'},
    'د.ج': {'fr': 'D.A.', 'en': 'D.A.'},
    'دينار جزائري': {'fr': 'D.A.', 'en': 'D.A.'},
    'ملغى': {'fr': 'Annulé', 'en': 'Canceled'},
    'الكل': {'fr': 'Tout', 'en': 'All'},
    'مدفوعة': {'fr': 'Payée', 'en': 'Paid'},
    'مردودة': {'fr': 'Remboursée', 'en': 'Refunded'},
    
    'الخزينة (Caisse)': {'fr': 'Caisse', 'en': 'Treasury'},
    'الخزينة': {'fr': 'Caisse', 'en': 'Treasury'},
    'الرصيد الإجمالي': {'fr': 'Solde Total', 'en': 'Total Balance'},
    'دفع من المورد': {'fr': 'Paiement du fournisseur', 'en': 'Payment from supplier'},
    'بحث بالاسم أو البيان': {'fr': 'Recherche par nom ou description', 'en': 'Search by name or description'},
    'الفاتورة': {'fr': 'Facture', 'en': 'Invoice'},
    'فاتورة': {'fr': 'Facture', 'en': 'Invoice'},
    'عامل (أجر/سلفة)': {'fr': 'Employé (Salaire/Avance)', 'en': 'Worker (Salary/Advance)'},
    'عامل': {'fr': 'Employé', 'en': 'Worker'},
    'دفع فاتورة مشتريات للمورد': {'fr': 'Paiement facture achat', 'en': 'Purchase invoice payment'},
    'معاملة جديدة': {'fr': 'Nouvelle transaction', 'en': 'New Transaction'},
    'إضافة معاملة للصندوق': {'fr': 'Ajouter une transaction', 'en': 'Add transaction'},
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
print("Updated keys.")
