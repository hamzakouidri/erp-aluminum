import sys

sys.stdout.reconfigure(encoding='utf-8')

path = 'lib/Screen/achat_item_picker.dart'
content = open(path, encoding='utf-8').read()

# 1. Imports
old_imports = """import 'package:flutter/material.dart';
import '../sql_database.dart';"""

new_imports = """import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../sql_database.dart';
import '../settings/app_settings.dart';
import '../settings/localization.dart';"""

content = content.replace(old_imports, new_imports)

# 2. Retrieve lang in build method
old_build_start = """  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,"""

new_build_start = """  @override
  Widget build(BuildContext context) {
    final lang = Provider.of<AppSettingsProvider>(context).language;
    return PopScope(
      canPop: false,"""

content = content.replace(old_build_start, new_build_start)

# 3. AppBar Title
old_appbar_title = """              child: Text(
                'المستودع (إضافة للفاتورة)',"""

new_appbar_title = """              child: Text(
                Localization.translate('المستودع (إضافة للفاتورة)', lang),"""

content = content.replace(old_appbar_title, new_appbar_title)

# 4. Dropdowns and Input fields
content = content.replace("labelText: 'الصنف',", "labelText: Localization.translate('الصنف', lang),")
content = content.replace("c['label']!,", "Localization.translate(c['label']!, lang),")
content = content.replace("labelText: 'البروفيل',", "labelText: Localization.translate('البروفيل', lang),")
content = content.replace("labelText: 'السلسلة (Série)',", "labelText: Localization.translate('السلسلة (Série)', lang),")
content = content.replace("labelText: 'البحث عن المادة...',", "labelText: Localization.translate('البحث عن المادة...', lang),")
content = content.replace("hintText: 'مثال: كادر، أوفرو...',", "hintText: Localization.translate('مثال: كادر، أوفرو...', lang),")
content = content.replace("'لا توجد عناصر مطابقة',", "Localization.translate('لا توجد عناصر مطابقة', lang),")

# 5. Dialog title and fields inside _showAddItemDialog
# Let's retrieve lang at the start of _showAddItemDialog or inside the builder.
# Since _showAddItemDialog uses showDialog, let's find the builder block and inject lang.
old_dialog_builder = """      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: StatefulBuilder(
          builder: (context, setDialogState) {"""

new_dialog_builder = """      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: StatefulBuilder(
          builder: (context, setDialogState) {
            final lang = Provider.of<AppSettingsProvider>(context).language;"""

content = content.replace(old_dialog_builder, new_dialog_builder)

# Replace dialog texts
old_dialog_title = """              title: Text(
                'إضافة: ${item['name'] ?? item['type']}',"""

new_dialog_title = """              title: Text(
                '${Localization.translate('إضافة: ', lang)}${Localization.translate(item['name'] ?? item['type'] ?? '', lang)}',"""

content = content.replace(old_dialog_title, new_dialog_title)

content = content.replace("labelText: 'اللون',", "labelText: Localization.translate('اللون', lang),")
content = content.replace("c['name'],", "Localization.translate(c['name'], lang),")

old_dialog_qty = """                        labelText: _selectedCategory == 'Sections'
                            ? 'الكمية (عدد)'
                            : 'الكمية',"""

new_dialog_qty = """                        labelText: _selectedCategory == 'Sections'
                            ? Localization.translate('الكمية (عدد)', lang)
                            : Localization.translate('الكمية', lang),"""

content = content.replace(old_dialog_qty, new_dialog_qty)

content = content.replace("labelText: 'السعر للوحدة',", "labelText: Localization.translate('السعر للوحدة', lang),")
content = content.replace("""                  child: const Text(
                    'إلغاء',
                    style: TextStyle(fontFamily: 'Cairo'),
                  ),""", """                  child: Text(
                    Localization.translate('إلغاء', lang),
                    style: const TextStyle(fontFamily: 'Cairo'),
                  ),""")

# Already exists SnackBar
old_exists_snackbar = """                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'هذا العنصر موجود بالفعل في الفاتورة',
                                style: TextStyle(fontFamily: 'Cairo'),
                              ),
                              backgroundColor: Colors.orange,
                              duration: Duration(seconds: 2),
                            ),
                          );"""

new_exists_snackbar = """                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                Localization.translate('هذا العنصر موجود بالفعل في الفاتورة', lang),
                                style: const TextStyle(fontFamily: 'Cairo'),
                              ),
                              backgroundColor: Colors.orange,
                              duration: const Duration(seconds: 2),
                            ),
                          );"""

content = content.replace(old_exists_snackbar, new_exists_snackbar)

# Added successfully SnackBar
old_success_snackbar = """                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'تم إضافة العنصر بنجاح!',
                              style: TextStyle(fontFamily: 'Cairo'),
                            ),
                            backgroundColor: Colors.green,
                            duration: Duration(seconds: 1),
                          ),
                        );"""

new_success_snackbar = """                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              Localization.translate('تم إضافة العنصر بنجاح!', lang),
                              style: const TextStyle(fontFamily: 'Cairo'),
                            ),
                            backgroundColor: Colors.green,
                            duration: const Duration(seconds: 1),
                          ),
                        );"""

content = content.replace(old_success_snackbar, new_success_snackbar)

# Add to invoice button
old_add_to_invoice_btn = """                  child: const Text(
                    'إضافة للفاتورة',
                    style: TextStyle(
                      color: Colors.white,
                      fontFamily: 'Cairo',
                      fontWeight: FontWeight.bold,
                    ),
                  ),"""

new_add_to_invoice_btn = """                  child: Text(
                    Localization.translate('إضافة للفاتورة', lang),
                    style: const TextStyle(
                      color: Colors.white,
                      fontFamily: 'Cairo',
                      fontWeight: FontWeight.bold,
                    ),
                  ),"""

content = content.replace(old_add_to_invoice_btn, new_add_to_invoice_btn)

# Translate items in result list
# We can translate title using Localization.translate(title, lang) or similar
old_title_expr = "String title = item['name'] ?? item['type'] ?? '';"
new_title_expr = """String title = Localization.translate(item['name'] ?? item['type'] ?? '', lang);"""
content = content.replace(old_title_expr, new_title_expr)

old_profileName_expr = "profileName = _profiles.firstWhere(\n                                (p) => p['id'] == _selectedProfileId,\n                              )['name'];"
new_profileName_expr = "profileName = Localization.translate(_profiles.firstWhere(\n                                (p) => p['id'] == _selectedProfileId,\n                              )['name'] ?? '', lang);"
content = content.replace(old_profileName_expr, new_profileName_expr)

open(path, 'w', encoding='utf-8').write(content)
print("Done translating achat item picker screen!")
