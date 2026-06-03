import re

file_path = "lib/Commande/Systeme/model.dart"
with open(file_path, "r", encoding="utf-8") as f:
    content = f.read()

override_code = """
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AluminumSeries && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}
"""

if "@override\n  bool operator ==" not in content.split("class AluminumSeries")[1].split("class AluminumProfileSystem")[0]:
    content = content.replace("  }\n}\n\nclass AluminumProfileSystem", "  }\n" + override_code + "\nclass AluminumProfileSystem")
    with open(file_path, "w", encoding="utf-8") as f:
        f.write(content)
