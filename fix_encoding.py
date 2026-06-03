import os

file_path = "lib/Screen/price_management_screen.dart"
with open(file_path, "r", encoding="utf-8") as f:
    content = f.read()

content = content.replace('O"O-OO1O_ O U,OO3O OO1', 'Manage Prices')
content = content.replace('U.U+ OO-O_USO O U,O3O O1 O"U+OOO-', 'Price updated successfully')
content = content.replace('U,O OU^OO_ O"USOU+OO', 'No data found')
content = content.replace('O U,OU,U?U+USU^U? (Series)', 'Aluminum (Series)')
content = content.replace('O U,OU,U^OU+', 'Colors')
content = content.replace('O U,O2OOO', 'Glass')
content = content.replace('O U,O3OOOO1', 'Shutters')
content = content.replace('O U,U?U?OO_U,', 'Joints')
content = content.replace('O U,OU,O3O3U^OO1OO', 'Accessories')
content = content.replace('O U,O3O O1 U,U,U?OO1 O U,OU^U,US', 'Price per linear meter')
content = content.replace('O3O O1 O"O_OU?US OU,U? U,U,U?OO1', 'Additional price')
content = content.replace('O U,O3O O1 U,U,U?OO1 O U,U?O1O"O ', 'Price per square meter')
content = content.replace('O U,O3O O1 U,U,U,OO O_', 'Price per piece')

with open(file_path, "w", encoding="utf-8") as f:
    f.write(content)

drawer_path = "lib/Screen/drawer.dart"
with open(drawer_path, "r", encoding="utf-8") as f:
    content = f.read()

content = content.replace('O"O-OO1O_ O U,OO3O OO1', 'Manage Prices')
with open(drawer_path, "w", encoding="utf-8") as f:
    f.write(content)

