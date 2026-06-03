import re

file_path = "lib/Commande/Systeme/model.dart"
with open(file_path, "r", encoding="utf-8") as f:
    content = f.read()

# 1. Add slidingSashesCount to WindowZone
if "int slidingSashesCount;" not in content:
    content = content.replace("  int innerH;\n  int innerV;", "  int innerH;\n  int innerV;\n  int slidingSashesCount;")
    content = content.replace("    this.innerH = 0,\n    this.innerV = 0,", "    this.innerH = 0,\n    this.innerV = 0,\n    this.slidingSashesCount = 2,")
    content = content.replace("    int? innerH,\n    int? innerV,", "    int? innerH,\n    int? innerV,\n    int? slidingSashesCount,")
    content = content.replace("      innerH: innerH ?? this.innerH,\n      innerV: innerV ?? this.innerV,", "      innerH: innerH ?? this.innerH,\n      innerV: innerV ?? this.innerV,\n      slidingSashesCount: slidingSashesCount ?? this.slidingSashesCount,")
    content = content.replace("      innerH: innerH,\n      innerV: innerV,", "      innerH: innerH,\n      innerV: innerV,\n      slidingSashesCount: slidingSashesCount,")
    content = content.replace("      innerH: z.innerH,\n      innerV: z.innerV,", "      innerH: z.innerH,\n      innerV: z.innerV,\n      slidingSashesCount: z.slidingSashesCount,")

# 2. Add setSlidingSashesCount method to WindowModel
set_sashes_method = """
  void setSlidingSashesCount(int count) {
    if (selectedZone == null) return;
    _saveSnapshot();
    selectedZone!.slidingSashesCount = count;
    notifyListeners();
  }
"""
if "void setSlidingSashesCount(int count)" not in content:
    content = content.replace("  void setSelectedZoneContent(ZoneContent content) {", set_sashes_method + "\n  void setSelectedZoneContent(ZoneContent content) {")

# 3. Change ZoneContent.empty to ZoneContent.fixedGlass in the drawing mode by default, wait, I shouldn't mess up empty entirely if it's the default!
# Actually, the user says "we don't choose empty, but fixed glass, it will never be empty". So when a new zone is created, it should default to fixedGlass?
# "أبدا لن تكون فارغة" (it will never be empty). Let's change default `content` in WindowZone constructor from `empty` to `fixedGlass`.
if "this.content = ZoneContent.empty" in content:
    content = content.replace("this.content = ZoneContent.empty", "this.content = ZoneContent.fixedGlass")

with open(file_path, "w", encoding="utf-8") as f:
    f.write(content)
