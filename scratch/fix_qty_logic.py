import re

f = r"lib\Commande\Systeme\material_consumption_screen.dart"

with open(f, 'r', encoding='utf-8') as file:
    content = file.read()

# Fix totalHandles
pattern_handles = r"int totalHandles = totalSashesFrappe;\s*//(.*?)\s*if \(totalPoigneePorte > 0 && totalHandles > 0\) \{"
replacement_handles = """int totalHandles = singleCount + doubleCount; // One handle per sash opening
      
      if (totalPoigneePorte > 0 && totalHandles > 0) {"""
content = re.sub(pattern_handles, replacement_handles, content, flags=re.DOTALL)

# Fix isGacheDouble to be more resilient
pattern_gache = r"bool isGacheDouble =\s*accName\.contains\('.*?'\) \|\| accName\.contains\('g.*che double'\);"
replacement_gache = """bool isGacheDouble = accName.contains('gache double') || accName.contains('gâche double') || accName.contains('قاش دوبل') || accName.contains('gache') && accName.contains('double');"""
content = re.sub(pattern_gache, replacement_gache, content)

with open(f, 'w', encoding='utf-8') as file:
    file.write(content)

print("Handles and gache logic fixed.")
