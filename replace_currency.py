import os
import re

files_to_update = [
    "lib/Cliente/show_client.dart",
    "lib/Commande/partial_proforma_screen.dart",
    "lib/Screen/supplier_details_screen.dart",
    "lib/Screen/worker_finances_screen.dart",
    "lib/Commande/Systeme/material_consumption_screen.dart",
    "lib/Commande/Systeme/volet.dart",
    "lib/Commande/add_commande.dart",
    "lib/Commande/commande.dart",
    "lib/Commande/order_required_goods_screen.dart",
    "lib/Commande/order_table_edit_screen.dart",
    "lib/Screen/achat_return_screen.dart",
    "lib/Screen/achat_screen.dart",
]

def replace_currency(content):
    # Regex to find ` دج` or ` د.ج` inside Dart strings
    # We'll just replace literal " دج" or " د.ج" inside string literals with " ${Localization.translate('دج', lang)}"
    # Be careful not to replace them if they are not in a string interpolation.
    
    # Let's replace:
    # ' دج' -> ' ${Localization.translate('دج', lang)}'
    # " دج" -> " ${Localization.translate('دج', lang)}"
    # ' د.ج' -> ' ${Localization.translate('دج', lang)}'
    # " د.ج" -> " ${Localization.translate('دج', lang)}"
    
    content = content.replace(" دج'", " ${Localization.translate('دج', lang)}'")
    content = content.replace(' دج"', ' ${Localization.translate(\'دج\', lang)}"')
    content = content.replace(" د.ج'", " ${Localization.translate('دج', lang)}'")
    content = content.replace(' د.ج"', ' ${Localization.translate(\'دج\', lang)}"')
    
    # Also replace where it's not at the end of the string, e.g., ' دج/م²'
    content = content.replace(" دج/", " ${Localization.translate('دج', lang)}/")
    content = content.replace(" دج\\", " ${Localization.translate('دج', lang)}\\")
    content = content.replace(" د.ج -", " ${Localization.translate('دج', lang)} -")
    return content

for file_path in files_to_update:
    if not os.path.exists(file_path):
        continue
    
    with open(file_path, "r", encoding="utf-8") as f:
        content = f.read()
    
    # Ensure lang is defined where we make these replacements.
    # We will do a naive replace first, then run flutter analyze to see if it breaks.
    new_content = replace_currency(content)
    
    with open(file_path, "w", encoding="utf-8") as f:
        f.write(new_content)

print("Currency replacement complete.")
