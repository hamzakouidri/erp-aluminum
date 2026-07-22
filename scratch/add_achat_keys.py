import sys

sys.stdout.reconfigure(encoding='utf-8')

path = 'lib/settings/locales/general_keys.dart'
content = open(path, encoding='utf-8').read()

new_keys = {
    'البحث برقم الفاتورة أو اسم المورد...': {'ar': 'البحث برقم الفاتورة أو اسم المورد...', 'fr': 'Rechercher par n° de facture ou nom du fournisseur...', 'en': 'Search by invoice number or supplier name...'},
    'نشطة': {'ar': 'نشطة', 'fr': 'Active', 'en': 'Active'},
    'مردودة كلياً': {'ar': 'مردودة كلياً', 'fr': 'Retournée totalement', 'en': 'Fully Returned'},
    'مردودة جزئياً': {'ar': 'مردودة جزئياً', 'fr': 'Retournée partiellement', 'en': 'Partially Returned'},
    'مؤكدة / مدفوعة': {'ar': 'مؤكدة / مدفوعة', 'fr': 'Confirmée / Payée', 'en': 'Confirmed / Paid'},
    'مؤكد/نشط': {'ar': 'مؤكد/نشط', 'fr': 'Confirmé/Actif', 'en': 'Confirmed/Active'},
    'ملغى': {'ar': 'ملغى', 'fr': 'Annulé', 'en': 'Cancelled'},
    'ملغاة': {'ar': 'ملغاة', 'fr': 'Annulée', 'en': 'Cancelled'},
    'فاتورة رقم: ': {'ar': 'فاتورة رقم: ', 'fr': 'Facture N°: ', 'en': 'Invoice No: '},
    'رقم الفاتورة *': {'ar': 'رقم الفاتورة *', 'fr': 'N° Facture *', 'en': 'Invoice Number *'},
    'يتم إنشاؤه تلقائياً ويمكنك تعديله': {'ar': 'يتم إنشاؤه تلقائياً ويمكنك تعديله', 'fr': 'Généré automatiquement et modifiable', 'en': 'Automatically generated and editable'},
    'جارٍ توليد رقم الفاتورة...': {'ar': 'جارٍ توليد رقم الفاتورة...', 'fr': 'Génération du numéro de facture...', 'en': 'Generating invoice number...'},
    'يرجى إدخال رقم الفاتورة': {'ar': 'يرجى إدخال رقم الفاتورة', 'fr': 'Veuillez saisir le numéro de facture', 'en': 'Please enter the invoice number'},
    'لا يوجد موردين مسجلين، يرجى إضافة مورد أولاً من صفحة إدارة الموردين.': {'ar': 'لا يوجد موردين مسجلين، يرجى إضافة مورد أولاً من صفحة إدارة الموردين.', 'fr': 'Aucun fournisseur enregistré, veuillez d\'abord en ajouter un.', 'en': 'No registered suppliers, please add a supplier first.'},
    'المورد *': {'ar': 'المورد *', 'fr': 'Fournisseur *', 'en': 'Supplier *'},
    'اختر مورد': {'ar': 'اختر مورد', 'fr': 'Choisir un fournisseur', 'en': 'Choose a supplier'},
    'لا توجد مستودعات مسجلة.': {'ar': 'لا توجد مستودعات مسجلة.', 'fr': 'Aucun entrepôt enregistré.', 'en': 'No registered warehouses.'},
    'مكان التخزين (المستودع) *': {'ar': 'مكان التخزين (المستودع) *', 'fr': 'Lieu de stockage (Dépôt) *', 'en': 'Storage Location (Warehouse) *'},
    'اختر مكان التخزين': {'ar': 'اختر مكان التخزين', 'fr': 'Choisir le lieu de stockage', 'en': 'Choose storage location'},
    'الرجاء اختيار المورد': {'ar': 'الرجاء اختيار المورد', 'fr': 'Veuillez choisir le fournisseur', 'en': 'Please choose the supplier'},
    'الرجاء اختيار مكان التخزين': {'ar': 'الرجاء اختيار مكان التخزين', 'fr': 'Veuillez choisir le lieu de stockage', 'en': 'Please choose the storage location'},
    'حدث خطأ أثناء الحفظ: ': {'ar': 'حدث خطأ أثناء الحفظ: ', 'fr': 'Une erreur est survenue lors de l\'enregistrement : ', 'en': 'An error occurred while saving: '},
    'هل أنت متأكد من رغبتك في حذف الفاتورة رقم: ': {'ar': 'هل أنت متأكد من رغبتك في حذف الفاتورة رقم: ', 'fr': 'Êtes-vous sûr de vouloir supprimer la facture N°: ', 'en': 'Are you sure you want to delete invoice number: '},
    ' نهائياً من قاعدة البيانات؟ لا يمكن التراجع عن هذا الإجراء.': {'ar': ' نهائياً من قاعدة البيانات؟ لا يمكن التراجع عن هذا الإجراء.', 'fr': ' définitivement de la base de données ? Cette action est irréversible.', 'en': ' permanently from the database? This action cannot be undone.'},
    'تراجع': {'ar': 'تراجع', 'fr': 'Annuler / Retour', 'en': 'Cancel / Back'},
    'تم حذف الفاتورة نهائياً': {'ar': 'تم حذف الفاتورة نهائياً', 'fr': 'La facture a été supprimée définitivement', 'en': 'The invoice has been permanently deleted'},
    'حذف نهائي': {'ar': 'حذف نهائي', 'fr': 'Supprimer définitivement', 'en': 'Permanently Delete'},
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
print(f"Appended {len(new_keys)} new achat keys.")

open(path, 'w', encoding='utf-8').write(content)
print("Done updating general_keys.dart with purchase/achat keys!")
