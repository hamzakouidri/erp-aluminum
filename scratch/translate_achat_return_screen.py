import sys

sys.stdout.reconfigure(encoding='utf-8')

path = 'lib/Screen/achat_return_screen.dart'
content = open(path, encoding='utf-8').read()

# Make the changes
content = content.replace("Text(\n                                          name,", "Text(\n                                          Localization.translate(name, lang),")
content = content.replace("'فاتورة: $invoice'", "'${Localization.translate('فاتورة: ', lang)}$invoice'")
content = content.replace("'الكمية المتاحة: $currentQty'", "'${Localization.translate('الكمية المتاحة: ', lang)}$currentQty'")
content = content.replace("'السعر: ${currencyFormat.format(price)} دج'", "'${Localization.translate('السعر: ', lang)}${currencyFormat.format(price)} ${Localization.translate('دج', lang)}'")
content = content.replace("'المراد إرجاعه: '", "Localization.translate('المراد إرجاعه: ', lang)")

open(path, 'w', encoding='utf-8').write(content)
print("Done translating achat return screen!")
