import re

file_path = "lib/Commande/window_painter.dart"
with open(file_path, "r", encoding="utf-8") as f:
    content = f.read()

# Fix _buildOuterShapePath
old_outer = "return Path()..addRect(Rect.fromLTWH(0, offsetY, w, offsetY + h));"
new_outer = "return Path()..addRect(Rect.fromLTWH(0, offsetY, w, h));"

if old_outer in content:
    content = content.replace(old_outer, new_outer)

# Also fix the selection highlight to use _getEffectiveZoneRect and be clipped
# Currently it's at the end of paint()
# We should clip the selection highlight to innerPath
# But we don't have innerPath available outside, actually we do! `innerPath` is a local variable in paint()
# Let's see the highlight code:
old_highlight_start = "    for (final zone in model.zones) {\n      if (model.selectedZone != null && model.selectedZone!.id == zone.id) {"
new_highlight_start = "    canvas.save();\n    canvas.clipPath(innerPath);\n    for (final zone in model.zones) {\n      if (model.selectedZone != null && model.selectedZone!.id == zone.id) {"

old_highlight_end = "      }\n      _drawInnerDimensions(canvas, zone);\n    }"
new_highlight_end = "      }\n    }\n    canvas.restore();\n    for (final zone in model.zones) {\n      _drawInnerDimensions(canvas, zone);\n    }"

if old_highlight_start in content and old_highlight_end in content:
    content = content.replace(old_highlight_start, new_highlight_start)
    content = content.replace(old_highlight_end, new_highlight_end)

with open(file_path, "w", encoding="utf-8") as f:
    f.write(content)

print("Fixed _buildOuterShapePath and selection clipping")
