import re

file_path = "lib/Commande/Systeme/show_system_francais.dart"
with open(file_path, "r", encoding="utf-8") as f:
    content = f.read()

# Fix the else if bug in french properly
content = re.sub(r"\]\s+else\s+if\s+\(widget\.systemMode\s*==\s*'french'\)\s*\.\.\.\[", "]\n                  if (widget.systemMode == 'french') ...[", content)

with open(file_path, "w", encoding="utf-8") as f:
    f.write(content)
