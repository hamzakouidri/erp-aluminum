import sys

sys.stdout.reconfigure(encoding='utf-8')

path = 'lib/settings/locales/general_keys.dart'
content = open(path, encoding='utf-8').read()

new_keys = {
    'المتوفر فقط': {'ar': 'المتوفر فقط', 'fr': 'En stock uniquement', 'en': 'In Stock Only'},
    'كل العناصر': {'ar': 'كل العناصر', 'fr': 'Tous les articles', 'en': 'All Items'},
    'البحث عن عنصر، مقطع، لون...': {'ar': 'البحث عن عنصر، مقطع، لون...', 'fr': 'Rechercher un article, profil, couleur...', 'en': 'Search item, profile, color...'},
    'تصفير المخزون (فترة تجريبية)': {'ar': 'تصفير المخزون (فترة تجريبية)', 'fr': 'Réinitialiser le stock (Période d\'essai)', 'en': 'Reset Stock (Trial Period)'},
    'تصفير المخزون!': {'ar': 'تصفير المخزون!', 'fr': 'Réinitialiser le stock !', 'en': 'Reset Stock!'},
    'هل أنت متأكد أنك تريد تصفير المخزون بالكامل وجعل كل الكميات 0؟\n\nلا يمكن التراجع عن هذا الإجراء!': {
        'ar': 'هل أنت متأكد أنك تريد تصفير المخزون بالكامل وجعل كل الكميات 0؟\n\nلا يمكن التراجع عن هذا الإجراء!',
        'fr': 'Êtes-vous sûr de vouloir réinitialiser tout le stock à 0 ?\n\nCette action est irréversible !',
        'en': 'Are you sure you want to reset the entire stock to 0?\n\nThis action cannot be undone!'
    },
    'تأكيد التصفير': {'ar': 'تأكيد التصفير', 'fr': 'Confirmer la réinitialisation', 'en': 'Confirm Reset'},
    'تم تصفير المخزون بنجاح': {'ar': 'تم تصفير المخزون بنجاح', 'fr': 'Le stock a été réinitialisé avec succès', 'en': 'Stock reset successfully'},
    'جرد سنوي / تعديل المخزون': {'ar': 'جرد سنوي / تعديل المخزون', 'fr': 'Inventaire annuel / Ajustement du stock', 'en': 'Annual Inventory / Stock Adjustment'},
    'القيمة الإجمالية للمخزون': {'ar': 'القيمة الإجمالية للمخزون', 'fr': 'Valeur totale du stock', 'en': 'Total Stock Value'},
    'لا توجد عناصر في هذا المخزون': {'ar': 'لا توجد عناصر في هذا المخزون', 'fr': 'Aucun article dans ce stock', 'en': 'No items in this stock'},
    'الرصيد': {'ar': 'الرصيد', 'fr': 'Solde / Qté', 'en': 'Balance / Qty'},
    'جرد المخزون: ': {'ar': 'جرد المخزون: ', 'fr': 'Ajustement du stock : ', 'en': 'Stock Count: '},
    'حفظ التعديلات': {'ar': 'حفظ التعديلات', 'fr': 'Enregistrer les modifications', 'en': 'Save Changes'},
    'تم حفظ تسوية المخزون بنجاح!': {'ar': 'تم حفظ تسوية المخزون بنجاح!', 'fr': 'Ajustement du stock enregistré avec succès !', 'en': 'Stock adjustment saved successfully!'},
    'بطاقة حركة المادة': {'ar': 'بطاقة حركة المادة', 'fr': 'Fiche de mouvement de l\'article', 'en': 'Item Movement Card'},
    'سجل الحركات:': {'ar': 'سجل الحركات:', 'fr': 'Historique des mouvements :', 'en': 'Movement Log:'},
    'لا توجد حركات مسجلة لهذه المادة.': {'ar': 'لا توجد حركات مسجلة لهذه المادة.', 'fr': 'Aucun mouvement enregistré pour cet article.', 'en': 'No movements registered for this item.'},
    'فاتورة شراء رقم ': {'ar': 'فاتورة شراء رقم ', 'fr': 'Facture d\'achat n° ', 'en': 'Purchase Invoice #'},
    'تعديل مشتريات رقم ': {'ar': 'تعديل مشتريات رقم ', 'fr': 'Modification d\'achat n° ', 'en': 'Purchase Edit #'},
    'إلغاء مشتريات رقم ': {'ar': 'إلغاء مشتريات رقم ', 'fr': 'Annulation d\'achat n° ', 'en': 'Purchase Deletion #'},
    'استهلاك في طلبية رقم ': {'ar': 'استهلاك في طلبية رقم ', 'fr': 'Consommation dans la commande n° ', 'en': 'Consumption in Order #'},
}

new_entries = []
for term, trans in new_keys.items():
    # Escape single quotes in translation texts
    ar_esc = trans['ar'].replace("'", "\\'")
    fr_esc = trans['fr'].replace("'", "\\'")
    en_esc = trans['en'].replace("'", "\\'")
    
    # We use triple quotes if the text contains newlines
    if "\n" in term:
        entry = f"""  r'''{term}''': {{
    AppLanguage.arabic: r'''{trans['ar']}''',
    AppLanguage.french: r'''{trans['fr']}''',
    AppLanguage.english: r'''{trans['en']}''',
  }},"""
    else:
        entry = f"""  '{term}': {{
    AppLanguage.arabic: '{ar_esc}',
    AppLanguage.french: '{fr_esc}',
    AppLanguage.english: '{en_esc}',
  }},"""
    new_entries.append(entry)

new_entries_str = "\n".join(new_entries)
content = content.replace("};", new_entries_str + "\n};")
print(f"Appended {len(new_keys)} new inventory keys.")

open(path, 'w', encoding='utf-8').write(content)
print("Done updating general_keys.dart with inventory keys!")
