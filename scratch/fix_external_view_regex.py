import re

file_path = "lib/Commande/window_painter.dart"
with open(file_path, "r", encoding="utf-8") as f:
    content = f.read()

# Fix side covers
content = re.sub(
    r"void _drawSideCovers.*?\{\s*final topY = .*?;",
    r"void _drawSideCovers(Canvas canvas, double w, double h, double boxSize, double t, double offsetY) {\n    final topY = offsetY;",
    content,
    flags=re.DOTALL
)

# Fix else block in paint
# The else block is from `} else {` until `canvas.restore();` and `}` for paint
# I'll just use regex for the whole block from "} else {" to the end of paint.
old_else_pattern = r"\} else \{\s*if \(\!model\.isShutterOnly\).*?canvas\.restore\(\);\s*\}"

new_else_block = """} else {
      if (!model.isShutterOnly) {
        _drawOuterFrame(canvas, w, h, t, boxSize);
        if (model.hasSideCovers) _drawSideCovers(canvas, w, h, boxSize, t, boxSize);
      }

      if (!model.isShutterOnly) {
        canvas.save();
        canvas.clipPath(innerPath);
        _drawMullions(canvas, w, h, t);
        canvas.restore();

        if (model.hasBottomFrame) {
          _drawWeepHoles(canvas, Rect.fromLTWH(0, boxSize, w, h), t);
        }

        canvas.save();
        canvas.clipPath(innerPath);
        for (final zone in model.zones) {
          _drawZoneContent(canvas, zone, h, t);
          if (zone.content == ZoneContent.singleSash ||
              zone.content == ZoneContent.doubleSash) {
            if (zone.content == ZoneContent.singleSash &&
                zone.openDirection != null) {
              _drawWindowDrawHandle(
                canvas,
                _getEffectiveZoneRect(zone.boundary, h, t),
                zone.openDirection!,
                zone.handlePositionRatio ?? 0.5,
              );
            }
          }
        }
        canvas.restore();
      }

      // 🟢 رسم الشفرات والصندوق في النهاية لكي تغطي الإطار
      if (model.hasShutter) {
        _drawShutterSlatsAndTracks(canvas, w, h, model.shutterPosition, boxSize);
        _drawShutterBox(canvas, w, boxSize);
      }
    }"""

content = re.sub(old_else_pattern, new_else_block, content, flags=re.DOTALL)

with open(file_path, "w", encoding="utf-8") as f:
    f.write(content)
print("Regex replace applied.")
