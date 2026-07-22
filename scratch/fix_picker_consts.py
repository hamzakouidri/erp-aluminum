import sys

sys.stdout.reconfigure(encoding='utf-8')

path = 'lib/Screen/achat_item_picker.dart'
content = open(path, encoding='utf-8').read()

# Make the changes
content = content.replace(
    "const InputDecoration(\n                          labelText: Localization.translate('اللون', lang),",
    "InputDecoration(\n                          labelText: Localization.translate('اللون', lang),"
)

content = content.replace(
    "const InputDecoration(\n                        labelText: Localization.translate('السعر للوحدة', lang),",
    "InputDecoration(\n                        labelText: Localization.translate('السعر للوحدة', lang),"
)

content = content.replace(
    "const FittedBox(\n              fit: BoxFit.scaleDown,\n              child: Text(\n                Localization.translate('المستودع (إضافة للفاتورة)', lang),",
    "FittedBox(\n              fit: BoxFit.scaleDown,\n              child: Text(\n                Localization.translate('المستودع (إضافة للفاتورة)', lang),"
)

content = content.replace(
    "const InputDecoration(\n                          labelText: Localization.translate('الصنف', lang),",
    "InputDecoration(\n                          labelText: Localization.translate('الصنف', lang),"
)

content = content.replace(
    "const InputDecoration(\n                            labelText: Localization.translate('البروفيل', lang),",
    "InputDecoration(\n                            labelText: Localization.translate('البروفيل', lang),"
)

content = content.replace(
    "const InputDecoration(\n                      labelText: Localization.translate('السلسلة (Série)', lang),",
    "InputDecoration(\n                      labelText: Localization.translate('السلسلة (Série)', lang),"
)

open(path, 'w', encoding='utf-8').write(content)
print("Done fixing const expressions in achat item picker!")
