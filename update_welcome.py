import re

with open('lib/Screen/welcom_screen.dart', 'r', encoding='utf-8') as f:
    text = f.read()

# Add import
import_stmt = "import '../items_produits/products_menu_screen.dart';"
if import_stmt not in text:
    text = text.replace("import '../items_produits/catalogue_manager.dart';", "import '../items_produits/catalogue_manager.dart';\n" + import_stmt)

# Change navigation
text = text.replace(
    "Navigator.push(context, _slide(CatalogManagerScreen(db: db)));",
    "Navigator.push(context, _slide(ProductsMenuScreen(db: db)));"
)

with open('lib/Screen/welcom_screen.dart', 'w', encoding='utf-8') as f:
    f.write(text)
