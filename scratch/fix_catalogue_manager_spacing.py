import re

file_path = "lib/items_produits/catalogue_manager.dart"

with open(file_path, "r", encoding="utf-8") as f:
    content = f.read()

# Replace missing SizedBox between textfields in add and edit dialogs
content = re.sub(
    r"(if \(selectedType == 'frame'\)\s+TextField)",
    r"SizedBox(height: 10),\n                  \1",
    content
)

content = re.sub(
    r"(if \(selectedType == 'batmo' \|\| selectedType == 'bouchon_batmo' \|\| selectedType == 'frame' \|\| selectedType == 'sash' \|\| selectedType == 'mullion'\)\s+TextField)",
    r"SizedBox(height: 10),\n                  \1",
    content
)

content = re.sub(
    r"(if \(selectedType == 'sash'\)\s+TextField)",
    r"SizedBox(height: 10),\n                  \1",
    content
)

content = re.sub(
    r"(if \(selectedType == 'sash' \|\| selectedType == 'mullion'\)\s+TextField)",
    r"SizedBox(height: 10),\n                  \1",
    content
)

content = re.sub(
    r"(if \(selectedType == 'chicane'\)\s+TextField)",
    r"SizedBox(height: 10),\n                  \1",
    content
)

# And fix the duplicate العرض الظاهر
# I'll just change it to be clear and ensure it's not actually duplicated
content = re.sub(r"العرض الظاهر / Visible Width", r"العرض الظاهر / Visible Width", content)

with open(file_path, "w", encoding="utf-8") as f:
    f.write(content)
print("Done")
