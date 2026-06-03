import re

with open("lib/items_produits/products_menu_screen.dart", "r", encoding="utf-8") as f:
    content = f.read()

content = content.replace("fintsIze:", "fontSize:")
content = content.replace("SizedBoy(", "SizedBox(")
content = content.replace("shade40,", "shade400,")

with open("lib/items_produits/products_menu_screen.dart", "w", encoding="utf-8") as f:
    f.write(content)
