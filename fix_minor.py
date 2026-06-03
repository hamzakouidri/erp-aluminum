import os
import re

def fix_imports(path):
    with open(path, 'r', encoding='utf-8') as f:
        lines = f.readlines()
    
    seen_imports = set()
    new_lines = []
    for line in lines:
        if line.startswith('import '):
            if line in seen_imports:
                continue
            seen_imports.add(line)
        new_lines.append(line)
        
    with open(path, 'w', encoding='utf-8') as f:
        f.writelines(new_lines)

fix_imports('lib/Screen/welcom_screen.dart')
fix_imports('lib/home.dart')
fix_imports('lib/Screen/show_dialog.dart')

def fix_empty_catches():
    path = 'lib/Screen/price_management_screen.dart'
    with open(path, 'r', encoding='utf-8') as f:
        content = f.read()
    content = content.replace('catch (e) {\n\n    }', 'catch (e) {\n      print(e);\n    }')
    content = content.replace('catch (e) {\n    }', 'catch (e) {\n      print(e);\n    }')
    with open(path, 'w', encoding='utf-8') as f:
        f.write(content)
fix_empty_catches()
