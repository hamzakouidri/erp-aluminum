import sys

sys.stdout.reconfigure(encoding='utf-8')

path = 'lib/settings/locales/general_keys.dart'
content = open(path, encoding='utf-8').read()

new_keys = {
    'مورد جديد': {'ar': 'مورد جديد', 'fr': 'Nouveau fournisseur', 'en': 'New Supplier'},
    'إضافة مورد جديد': {'ar': 'إضافة مورد جديد', 'fr': 'Ajouter un nouveau fournisseur', 'en': 'Add New Supplier'},
    'تعديل بيانات المورد': {'ar': 'تعديل بيانات المورد', 'fr': 'Modifier les informations du fournisseur', 'en': 'Edit Supplier Details'},
    'اسم المورد': {'ar': 'اسم المورد', 'fr': 'Nom du fournisseur', 'en': 'Supplier Name'},
    'رقم الهاتف': {'ar': 'رقم الهاتف', 'fr': 'Numéro de téléphone', 'en': 'Phone Number'},
    'البريد الإلكتروني': {'ar': 'البريد الإلكتروني', 'fr': 'E-mail', 'en': 'Email Address'},
    'ملاحظات': {'ar': 'ملاحظات', 'fr': 'Remarques / Notes', 'en': 'Notes / Remarks'},
    'حفظ': {'ar': 'حفظ', 'fr': 'Enregistrer', 'en': 'Save'},
    'تأكيد الحذف': {'ar': 'تأكيد الحذف', 'fr': 'Confirmer la suppression', 'en': 'Confirm Deletion'},
    'هل أنت متأكد من حذف هذا المورد؟': {'ar': 'هل أنت متأكد من حذف هذا المورد؟', 'fr': 'Êtes-vous sûr de vouloir supprimer ce fournisseur ?', 'en': 'Are you sure you want to delete this supplier?'},
    'حذف': {'ar': 'حذف', 'fr': 'Supprimer', 'en': 'Delete'},
    'لا يوجد موردين مضافين حتى الآن.': {'ar': 'لا يوجد موردين مضافين حتى الآن.', 'fr': 'Aucun fournisseur ajouté pour le moment.', 'en': 'No suppliers added yet.'},
    'الاسم مطلوب': {'ar': 'الاسم مطلوب', 'fr': 'Le nom est requis', 'en': 'Name is required'},
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
print(f"Appended {len(new_keys)} new supplier keys.")

open(path, 'w', encoding='utf-8').write(content)
print("Done updating general_keys.dart with supplier keys!")
