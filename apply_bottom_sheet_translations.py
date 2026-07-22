import os

dart_file = "lib/Commande/commande.dart"

replacements = {
    "title: const Text('فاتورة تقديرية (Facture Proforma)')": "title: Text(Localization.translate('فاتورة تقديرية (Facture Proforma)', Provider.of<AppSettingsProvider>(context, listen: false).language))",
    "title: const Text('فاتورة تقديرية جزئية (Proforma Partielle)')": "title: Text(Localization.translate('فاتورة تقديرية جزئية (Proforma Partielle)', Provider.of<AppSettingsProvider>(context, listen: false).language))",
    "title: const Text('ورقة التقطيع (Fiche de Coupe)')": "title: Text(Localization.translate('ورقة التقطيع (Fiche de Coupe)', Provider.of<AppSettingsProvider>(context, listen: false).language))",
    "title: const Text('سلع الطلبية وموادها (تقرير النواقص)')": "title: Text(Localization.translate('سلع الطلبية وموادها (تقرير النواقص)', Provider.of<AppSettingsProvider>(context, listen: false).language))",
    "title: const Text('السلع المطلوبة')": "title: Text(Localization.translate('السلع المطلوبة', Provider.of<AppSettingsProvider>(context, listen: false).language))",
    "subtitle: const Text(\n                  'مجموع سلع جميع المنتجات مجمّعة',": "subtitle: Text(\n                  Localization.translate('مجموع سلع جميع المنتجات مجمّعة', Provider.of<AppSettingsProvider>(context, listen: false).language),",
    "title: const Text('تأكيد القياسات والملصقات (Stickers)')": "title: Text(Localization.translate('تأكيد القياسات والملصقات (Stickers)', Provider.of<AppSettingsProvider>(context, listen: false).language))",
    "subtitle: const Text(\n                  'تعديل القياسات الفعلية للموقع وطباعة الباركود لكل قطعة',": "subtitle: Text(\n                  Localization.translate('تعديل القياسات الفعلية للموقع وطباعة الباركود لكل قطعة', Provider.of<AppSettingsProvider>(context, listen: false).language),",
    "title: const Text('تأكيد الطلبية (Confirmer)')": "title: Text(Localization.translate('تأكيد الطلبية (Confirmer)', Provider.of<AppSettingsProvider>(context, listen: false).language))",
    "title: const Text('تغيير الحالة المخصص')": "title: Text(Localization.translate('تغيير الحالة المخصص', Provider.of<AppSettingsProvider>(context, listen: false).language))",
    "title: const Text('تكرار الطلبية (Duplicate)')": "title: Text(Localization.translate('تكرار الطلبية (Duplicate)', Provider.of<AppSettingsProvider>(context, listen: false).language))",
    "title: const Text('مسح الطلبية (Supprimer)')": "title: Text(Localization.translate('مسح الطلبية (Supprimer)', Provider.of<AppSettingsProvider>(context, listen: false).language))",
}

with open(dart_file, 'r', encoding='utf-8') as f:
    content = f.read()

for old, new in replacements.items():
    content = content.replace(old, new)

with open(dart_file, 'w', encoding='utf-8') as f:
    f.write(content)

print("Applied UI translations in commande.dart")
