import re

f = r"lib\services\cloud_sync_service.dart"

with open(f, 'r', encoding='utf-8') as file:
    content = file.read()

# Remove the isSilent check that prevents backup if there are no clients/commandes
pattern = r"""\s*if \(isSilent\) \{\s*bool hasData =\s*\(allData\['Client'\]\?\.isNotEmpty \?\? false\) \|\|\s*\(allData\['Commandes'\]\?\.isNotEmpty \?\? false\) \|\|\s*\(allData\['Achats'\]\?\.isNotEmpty \?\? false\);\s*if \(!hasData\) return;\s*\}"""

content = re.sub(pattern, "", content)

with open(f, 'w', encoding='utf-8') as file:
    file.write(content)

print("Cloud sync bug fixed.")
