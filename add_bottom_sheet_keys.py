import os
import re

dart_file = "lib/settings/locales/general_keys.dart"

new_keys = {
    'فاتورة تقديرية (Facture Proforma)': {'fr': 'Facture Proforma', 'en': 'Proforma Invoice'},
    'فاتورة تقديرية جزئية (Proforma Partielle)': {'fr': 'Facture proforma partielle', 'en': 'Partial Proforma Invoice'},
    'ورقة التقطيع (Fiche de Coupe)': {'fr': 'Fiche de coupe', 'en': 'Cutting Sheet'},
    'سلع الطلبية وموادها (تقرير النواقص)': {'fr': 'Rapport des articles manquants', 'en': 'Missing Items Report'},
    'السلع المطلوبة': {'fr': 'Articles demandés', 'en': 'Requested Items'},
    'مجموع سلع جميع المنتجات مجمّعة': {'fr': 'Total des articles, tous produits confondus', 'en': 'Total of all items combined'},
    'تأكيد القياسات والملصقات (Stickers)': {'fr': 'Confirmation des mesures et étiquettes', 'en': 'Confirm Measurements & Stickers'},
    'تعديل القياسات الفعلية للموقع وطباعة الباركود لكل قطعة': {'fr': 'Modification des mesures réelles des sites et impression des codes-barres par pièce', 'en': 'Edit actual site measurements and print barcode per piece'},
    'تأكيد الطلبية (Confirmer)': {'fr': 'Confirmer la commande', 'en': 'Confirm Order'},
    'تغيير الحالة المخصص': {'fr': 'Modifier le statut personnalisé', 'en': 'Change Custom Status'},
    'تكرار الطلبية (Duplicate)': {'fr': 'Dupliquer la commande', 'en': 'Duplicate Order'},
    'مسح الطلبية (Supprimer)': {'fr': 'Supprimer la commande', 'en': 'Delete Order'},
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
print("Updated bottom sheet keys.")
