import re

with open('lib/Commande/Systeme/material_consumption_screen.dart', 'r', encoding='utf-8') as f:
    content = f.read()

content = content.replace('totalCostNoWaste.toStringAsFixed(0)', 'totalCostNoWaste.toStringAsFixed(2)')
content = content.replace('totalCostWithWaste.toStringAsFixed(0)', 'totalCostWithWaste.toStringAsFixed(2)')
content = content.replace('sellingPrice.toStringAsFixed(0)', 'sellingPrice.toStringAsFixed(2)')
content = content.replace('total.toStringAsFixed(0)', 'total.toStringAsFixed(2)')

with open('lib/Commande/Systeme/material_consumption_screen.dart', 'w', encoding='utf-8') as f:
    f.write(content)
