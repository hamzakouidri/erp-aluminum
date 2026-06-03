import re

# 1. Update localization.dart
loc_file = "lib/settings/localization.dart"
with open(loc_file, "r", encoding="utf-8") as f:
    loc_content = f.read()

new_translations = """
    'إدارة الأسعار': {
      AppLanguage.arabic: 'إدارة الأسعار',
      AppLanguage.french: 'Gérer les prix',
      AppLanguage.english: 'Manage Prices',
    },
    'الألمنيوم (السلاسل)': {
      AppLanguage.arabic: 'الألمنيوم (السلاسل)',
      AppLanguage.french: 'Aluminium (Séries)',
      AppLanguage.english: 'Aluminum (Series)',
    },
    'الألوان': {
      AppLanguage.arabic: 'الألوان',
      AppLanguage.french: 'Couleurs',
      AppLanguage.english: 'Colors',
    },
    'الزجاج': {
      AppLanguage.arabic: 'الزجاج',
      AppLanguage.french: 'Verre',
      AppLanguage.english: 'Glass',
    },
    'الستائر': {
      AppLanguage.arabic: 'الستائر',
      AppLanguage.french: 'Volets',
      AppLanguage.english: 'Shutters',
    },
    'الإكسسوارات': {
      AppLanguage.arabic: 'الإكسسوارات',
      AppLanguage.french: 'Accessoires',
      AppLanguage.english: 'Accessories',
    },
    'الجوانات': {
      AppLanguage.arabic: 'الجوانات',
      AppLanguage.french: 'Joints',
      AppLanguage.english: 'Joints',
    },
    'سعر المتر الطولي': {
      AppLanguage.arabic: 'سعر المتر الطولي',
      AppLanguage.french: 'Prix au mètre linéaire',
      AppLanguage.english: 'Price per linear meter',
    },
    'سعر المتر المربع': {
      AppLanguage.arabic: 'سعر المتر المربع',
      AppLanguage.french: 'Prix au mètre carré',
      AppLanguage.english: 'Price per square meter',
    },
    'السعر': {
      AppLanguage.arabic: 'السعر',
      AppLanguage.french: 'Prix',
      AppLanguage.english: 'Price',
    },
    'حفظ': {
      AppLanguage.arabic: 'حفظ',
      AppLanguage.french: 'Enregistrer',
      AppLanguage.english: 'Save',
    },
    'لم يتم العثور على سلاسل. يرجى إضافة سلاسل أولاً.': {
      AppLanguage.arabic: 'لم يتم العثور على سلاسل. يرجى إضافة سلاسل أولاً.',
      AppLanguage.french: 'Aucune série trouvée. Veuillez ajouter des séries.',
      AppLanguage.english: 'No series found. Please add series first.',
    },
    'لم يتم العثور على ألوان. يرجى إضافة ألوان من قائمة المنتجات أولاً.': {
      AppLanguage.arabic: 'لم يتم العثور على ألوان. يرجى إضافة ألوان من قائمة المنتجات أولاً.',
      AppLanguage.french: 'Aucune couleur trouvée. Veuillez en ajouter.',
      AppLanguage.english: 'No colors found. Please add colors from the products menu first.',
    },
    'لا توجد عناصر. يرجى إضافتها من قائمة المنتجات أولاً.': {
      AppLanguage.arabic: 'لا توجد عناصر. يرجى إضافتها من قائمة المنتجات أولاً.',
      AppLanguage.french: 'Aucun article trouvé. Veuillez les ajouter d\\'abord.',
      AppLanguage.english: 'No items found. Please add them from the products menu first.',
    },
    'تم تحديث السعر بنجاح': {
      AppLanguage.arabic: 'تم تحديث السعر بنجاح',
      AppLanguage.french: 'Prix mis à jour avec succès',
      AppLanguage.english: 'Price updated successfully',
    },
  };

  static String translate(String key, AppLanguage lang) {"""

# Replace the end of the dictionary
# Wait, I need to make sure I don't replace the garbled text if it wasn't added yet.
# Since I didn't run the script yet, the file still has the original `}; \n static String translate...`
loc_content = re.sub(r'  \};\n\n  static String translate\(String key, AppLanguage lang\) \{', new_translations, loc_content)

with open(loc_file, "w", encoding="utf-8") as f:
    f.write(loc_content)

# 2. Update price_management_screen.dart
price_file = "lib/Screen/price_management_screen.dart"
with open(price_file, "r", encoding="utf-8") as f:
    price_content = f.read()

# Replace texts
replacements = {
    "Text('Manage Prices')": "Text(Localization.translate('إدارة الأسعار', lang))",
    "Text('Aluminum (Series)')": "Text(Localization.translate('الألمنيوم (السلاسل)', lang))",
    "Text('Colors')": "Text(Localization.translate('الألوان', lang))",
    "Text('Glass')": "Text(Localization.translate('الزجاج', lang))",
    "Text('Shutters')": "Text(Localization.translate('الستائر', lang))",
    "Text('Accessories')": "Text(Localization.translate('الإكسسوارات', lang))",
    "Text('Joints')": "Text(Localization.translate('الجوانات', lang))",
    "'No series found. Please add series first.'": "Localization.translate('لم يتم العثور على سلاسل. يرجى إضافة سلاسل أولاً.', lang)",
    "'No colors found. Please add colors from the products menu first.'": "Localization.translate('لم يتم العثور على ألوان. يرجى إضافة ألوان من قائمة المنتجات أولاً.', lang)",
    "'No items found. Please add them from the products menu first.'": "Localization.translate('لا توجد عناصر. يرجى إضافتها من قائمة المنتجات أولاً.', lang)",
    "'Price updated successfully'": "Localization.translate('تم تحديث السعر بنجاح', lang)",
    "'Price per linear meter'": "Localization.translate('سعر المتر الطولي', lang)",
    "'Price per square meter'": "Localization.translate('سعر المتر المربع', lang)",
    "'Price'": "Localization.translate('السعر', lang)",
    "Text('Save'": "Text(Localization.translate('حفظ', lang)"
}

for old, new in replacements.items():
    price_content = price_content.replace(old, new)

with open(price_file, "w", encoding="utf-8") as f:
    f.write(price_content)
