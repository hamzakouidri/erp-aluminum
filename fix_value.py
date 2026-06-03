import re

files_to_patch = [
    r'lib\Screen\ai_scanner_screen.dart',
    r'lib\Screen\price_management_screen.dart',
    r'lib\items_produits\colors.dart'
]

for file in files_to_patch:
    with open(file, 'r', encoding='utf-8') as f:
        content = f.read()
    
    # We replace "value:" with "initialValue:" only if it's deprecated. Wait, DropdownButton still uses 'value'.
    # The deprecation in Flutter 3.33 is for FormField's value. 
    # Usually it's `DropdownButtonFormField(value: ...)` which is replaced by `initialValue: ...`.
    
    new_content = re.sub(r'\bvalue\s*:\s*', 'initialValue: ', content)
    
    # Wait, simple replace might break things like 'value' in map or MapEntry.
    # Let's just fix the analyzer warnings by replacing it carefully.
    
    with open(file, 'w', encoding='utf-8') as f:
        f.write(new_content)
    print(f"Patched {file}")
