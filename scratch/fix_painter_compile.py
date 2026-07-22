import re

file_path = "lib/Commande/window_painter.dart"

with open(file_path, "r", encoding="utf-8") as f:
    content = f.read()

# Fix undefined offsetY in paint
content = re.sub(
    r"final innerPath = _buildInnerShapePath\(w, h, t, offsetY\);",
    r"final innerPath = _buildInnerShapePath(w, h, t, boxSize);",
    content,
    count=1
)
content = re.sub(
    r"_drawWeepHoles\(canvas, Rect\.fromLTWH\(0, 0, w, offsetY \+ h\), t\);",
    r"_drawWeepHoles(canvas, Rect.fromLTWH(0, boxSize, w, h), t);",
    content,
    count=1
)

content = re.sub(
    r"_drawWeepHoles\(canvas, Rect\.fromLTWH\(0, boxSize, w, h\), t\);",
    r"_drawWeepHoles(canvas, Rect.fromLTWH(0, boxSize, w, h), t);", # ensure it's correct
    content,
    count=1
)

# Fix 1675 undefined boxSize or missing arguments
content = re.sub(
    r"Rect _getEffectiveZoneRect\(Rect original, double h, double t\) \{",
    r"Rect _getEffectiveZoneRect(Rect original, double h, double t) {",
    content
)

# Also fix `WorkspacePainter` missing `offsetY`
# Let's search for `_buildOuterShapePath` in WorkspacePainter
content = re.sub(
    r"_buildOuterShapePath\(w, h\)",
    r"_buildOuterShapePath(w, h, 0.0)", # in WorkspacePainter, assuming offsetY = 0
    content
)

with open(file_path, "w", encoding="utf-8") as f:
    f.write(content)
print("Done")
