with open('lib/Screen/achat_item_picker.dart', 'r', encoding='utf-8') as f:
    content = f.read()

# 1. Translate categoryLabel
old_cat = """                              child: Text(
                                categoryLabel,
                                style: TextStyle("""

new_cat = """                              child: Text(
                                Localization.translate(categoryLabel, lang),
                                style: TextStyle("""

# 2. Translate colorName
old_color = """                                    Text(
                                      colorName,
                                      style: const TextStyle("""

new_color = """                                    Text(
                                      Localization.translate(colorName, lang),
                                      style: const TextStyle("""

# 3. Translate price label
old_price = """                              Text(
                                price > 0
                                    ? '${price.toStringAsFixed(2)} دج'
                                    : 'السعر: --',"""

new_price = """                              Text(
                                price > 0
                                    ? '${price.toStringAsFixed(2)} ${Localization.translate('دج', lang)}'
                                    : Localization.translate('السعر: --', lang),"""

content = content.replace(old_cat, new_cat, 1)
content = content.replace(old_color, new_color, 1)
content = content.replace(old_price, new_price, 1)

with open('lib/Screen/achat_item_picker.dart', 'w', encoding='utf-8', newline='') as f:
    f.write(content)

print('SUCCESS ITEM PICKER')
