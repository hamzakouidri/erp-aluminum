import re

dart_file = "lib/Screen/welcom_screen.dart"

with open(dart_file, 'r', encoding='utf-8') as f:
    content = f.read()

# Add final lang = Provider.of<AppSettingsProvider>(context).language; inside _OrdersChartCardState.build
# First, check if it's already there
if "final total = widget.byStatus.values.fold(0, (a, b) => a + b);" in content:
    replacement = """    final lang = Provider.of<AppSettingsProvider>(context).language;
    final total = widget.byStatus.values.fold(0, (a, b) => a + b);"""
    content = content.replace("    final total = widget.byStatus.values.fold(0, (a, b) => a + b);", replacement, 1)

# Now replace the hardcoded strings with Localization.translate(..., lang)
replacements = {
    "'حالة الطلبيات'": "Localization.translate('حالة الطلبيات', lang)",
    "'دائري'": "Localization.translate('دائري', lang)",
    "'أشهر'": "Localization.translate('أشهر', lang)",
    "'منحنى بياني'": "Localization.translate('منحنى بياني', lang)",
    "_sectionLabel('تحليل الطلبيات')": "_sectionLabel(Localization.translate('تحليل الطلبيات', lang))",
}

for old, new in replacements.items():
    content = content.replace(old, new)

# For _statusAr, it's defined as a static const map on line 1385.
# We can't use `lang` inside a static const map, but we CAN translate it when it's displayed!
# Let's find where _statusAr is used.
# Let's write the updated content back to search for _statusAr
with open(dart_file, 'w', encoding='utf-8') as f:
    f.write(content)

print("Replaced strings in welcom_screen.dart.")
