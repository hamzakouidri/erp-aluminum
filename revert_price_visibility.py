import re

with open('lib/Commande/Systeme/material_consumption_screen.dart', 'r', encoding='utf-8') as f:
    content = f.read()

# Remove the visibility condition for the selling price
content = content.replace('if (_isPriceVisible)\n              Padding(', 'Padding(')

# Remove the IconButton and the SizedBox next to it
pattern = re.compile(r'\s*IconButton\(\s*icon: Icon\(\s*_isPriceVisible \? Icons\.visibility_off : Icons\.visibility,\s*color: Colors\.grey\.shade700,\s*\),\s*onPressed: \(\) \{\s*setState\(\(\) \{\s*_isPriceVisible = !_isPriceVisible;\s*\}\);\s*\},\s*\),\s*const SizedBox\(width: 4\),')
content = pattern.sub('', content)

with open('lib/Commande/Systeme/material_consumption_screen.dart', 'w', encoding='utf-8') as f:
    f.write(content)
