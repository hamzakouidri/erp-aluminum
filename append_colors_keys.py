import os
import json

dart_file = "lib/settings/locales/general_keys.dart"

new_keys = {
    'إضافة لون جديد': {'fr': 'Ajouter une nouvelle couleur', 'en': 'Add New Color'},
    'اسم اللون': {'fr': 'Nom de la couleur', 'en': 'Color Name'},
    'إلغاء': {'fr': 'Annuler', 'en': 'Cancel'},
    'حفظ': {'fr': 'Sauvegarder', 'en': 'Save'},
    'تعديل اسم اللون': {'fr': 'Modifier le nom de la couleur', 'en': 'Edit Color Name'},
    'تخصيص الألوان حسب البروفيلات': {'fr': 'Personnaliser les couleurs par profil', 'en': 'Customize Colors by Profile'},
    'اختر البروفيل': {'fr': 'Sélectionner le profil', 'en': 'Select Profile'},
    'إغلاق': {'fr': 'Fermer', 'en': 'Close'},
    'تخصيص ألوان الإكسسوارات': {'fr': 'Personnaliser les couleurs des accessoires', 'en': 'Customize Accessories Colors'},
    'بحث عن إكسسوار...': {'fr': 'Rechercher un accessoire...', 'en': 'Search for accessory...'},
    'تخصيص ألوان مركبات الستائر': {'fr': 'Personnaliser les couleurs des volets roulants', 'en': 'Customize Roller Shutter Colors'},
    'اختر المكون': {'fr': 'Sélectionner le composant', 'en': 'Select Component'},
    'الألوان': {'fr': 'Couleurs', 'en': 'Colors'},
    'تخصيص للزجاج': {'fr': 'Personnaliser le verre', 'en': 'Customize Glass'},
    'تخصيص البروفيل': {'fr': 'Personnaliser le profil', 'en': 'Customize Profile'},
    'تخصيص الإكسسوارات': {'fr': 'Personnaliser les accessoires', 'en': 'Customize Accessories'},
    'تخصيص مركبات الستائر': {'fr': 'Personnaliser les volets roulants', 'en': 'Customize Roller Shutters'},
    'لا توجد بيانات': {'fr': 'Aucune donnée', 'en': 'No Data'},
    'أبيض': {'fr': 'Blanc', 'en': 'White'},
    'بني': {'fr': 'Marron', 'en': 'Brown'},
    'رمادي': {'fr': 'Gris', 'en': 'Grey'},
    'أسود': {'fr': 'Noir', 'en': 'Black'},
    'بيج': {'fr': 'Beige', 'en': 'Beige'},
    'خام': {'fr': 'Brut', 'en': 'Raw'},
    'فضي': {'fr': 'Argent', 'en': 'Silver'},
    'أصفر': {'fr': 'Jaune', 'en': 'Yellow'},
    'أحمر': {'fr': 'Rouge', 'en': 'Red'},
    'أزرق': {'fr': 'Bleu', 'en': 'Blue'},
    'أخضر': {'fr': 'Vert', 'en': 'Green'},
    'خشبي': {'fr': 'Faux bois', 'en': 'Wood'},
    'ذهبي': {'fr': 'Doré', 'en': 'Gold'},
    'شامبانيا': {'fr': 'Champagne', 'en': 'Champagne'},
    'مخصص': {'fr': 'Personnalisé', 'en': 'Custom'},
    'خيارات الطباعة': {'fr': "Options d'impression", 'en': 'Printing Options'},
    'هل تريد طباعة كل النسخ أم نسخة محددة؟': {'fr': 'Voulez-vous imprimer toutes les copies ou une copie spécifique?', 'en': 'Do you want to print all copies or a specific one?'},
    'طباعة الكل': {'fr': 'Tout imprimer', 'en': 'Print All'},
    'طباعة كل النسخ': {'fr': 'Imprimer toutes les copies', 'en': 'Print All Copies'},
    'نسخة': {'fr': 'Copie', 'en': 'Copy'},
    'طباعة النسخة رقم': {'fr': 'Imprimer la copie numéro', 'en': 'Print Copy Number'},
    'يرجى حفظ القياسات قبل الطباعة': {'fr': "Veuillez enregistrer les mesures avant d'imprimer", 'en': 'Please save measurements before printing'},
    'طباعة العنصر': {'fr': "Imprimer l'élément", 'en': 'Print Element'},
}

with open(dart_file, 'r', encoding='utf-8') as f:
    content = f.read()

# Remove the trailing '};' so we can append
content = content.rstrip()
if content.endswith('};'):
    content = content[:-2]

# Prepare string to append
appends = ""
for ar, langs in new_keys.items():
    if f"'{ar}'" not in content and f'"{ar}"' not in content:
        appends += f"  '{ar}': {{\n"
        appends += f"    AppLanguage.arabic: '{ar}',\n"
        appends += f"    AppLanguage.french: '{langs['fr'].replace('\'', '\\\'')}',\n"
        appends += f"    AppLanguage.english: '{langs['en'].replace('\'', '\\\'')}',\n"
        appends += "  },\n"

if appends:
    new_content = content + "\n" + appends + "};\n"
    with open(dart_file, 'w', encoding='utf-8') as f:
        f.write(new_content)
    print(f"Added {appends.count('AppLanguage.arabic')} new keys.")
else:
    print("No new keys to add.")
