import re

file_path = "lib/Commande/window_painter.dart"
with open(file_path, "r", encoding="utf-8") as f:
    content = f.read()

# 1. Fix _drawShutterSlatsAndTracks coulisse bounds and slat bounds
old_slats = """  void _drawShutterSlatsAndTracks(
    Canvas canvas,
    double w,
    double h,
    double position,
    double boxSize,
  ) {
    const coulisseWidth = 25.0;

    // الكوليس يمتد من أعلى صندوق الستار (-boxSize) حتى أسفل النافذة (h)
    final double coulisseTop = -boxSize;
    final double coulisseHeight = h + boxSize;"""

new_slats = """  void _drawShutterSlatsAndTracks(
    Canvas canvas,
    double w,
    double h,
    double position,
    double boxSize,
  ) {
    const coulisseWidth = 25.0;

    // الكوليس يمتد من أسفل صندوق الستار (boxSize) حتى أسفل النافذة (h)
    final double coulisseTop = boxSize;
    final double coulisseHeight = h;"""

if old_slats in content:
    content = content.replace(old_slats, new_slats)
else:
    print("Could not find old_slats!")

old_slat_loop = """    // الشفرات (الداليفات) تظهر من أسفل صندوق الستار (y=0) نزولاً بحسب position
    final visibleSlatsHeight = h * position;
    canvas.save();
    final leftClip = model.removedShutterSides.contains('left')
        ? 0.0
        : coulisseWidth;
    final rightClip = model.removedShutterSides.contains('right')
        ? w
        : w - coulisseWidth;
    canvas.clipRect(Rect.fromLTRB(leftClip, 0, rightClip, visibleSlatsHeight));
    for (double y = 0; y < visibleSlatsHeight; y += 20.0) {
      if (model.removedShutterSides.contains('bottom') && (y + 20.0) >= h) {
        break;
      }"""

new_slat_loop = """    // الشفرات (الداليفات) تظهر من أسفل صندوق الستار (boxSize) نزولاً بحسب position
    final visibleSlatsHeight = h * position;
    canvas.save();
    final leftClip = model.removedShutterSides.contains('left')
        ? 0.0
        : coulisseWidth;
    final rightClip = model.removedShutterSides.contains('right')
        ? w
        : w - coulisseWidth;
    canvas.clipRect(Rect.fromLTRB(leftClip, boxSize, rightClip, boxSize + visibleSlatsHeight));
    for (double y = boxSize; y < boxSize + visibleSlatsHeight; y += 20.0) {
      if (model.removedShutterSides.contains('bottom') && (y + 20.0) >= boxSize + h) {
        break;
      }"""

if old_slat_loop in content:
    content = content.replace(old_slat_loop, new_slat_loop)
else:
    print("Could not find old_slat_loop!")

# 2. Fix the order in paint() for External View
# First, extract the whole paint method body and modify the else block.
# The else block currently is:
old_else_block = """    } else {
      if (!model.isShutterOnly) {
        _drawOuterFrame(canvas, w, h, t, boxSize);
        if (model.hasSideCovers) _drawSideCovers(canvas, w, h, boxSize, t, boxSize);
      }

      // 🟢 تصحيح 1: إخراج الصندوق من القص لكي يظهر ويتلون
      if (model.hasShutter) {
        _drawShutterBox(canvas, w, boxSize);
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
        }
      } else {
        canvas.save();
        canvas.clipPath(innerPath);
      }
      
      // 🟢 رسم الشفرات مرة واحدة داخل القص
      if (model.hasShutter) {
        _drawShutterSlatsAndTracks(canvas, w, h, model.shutterPosition, model.shutterBoxHeight);
      }
      canvas.restore();
    }"""

new_else_block = """    } else {
      if (!model.isShutterOnly) {
        _drawOuterFrame(canvas, w, h, t, boxSize);
        if (model.hasSideCovers) _drawSideCovers(canvas, w, h, boxSize, t, boxSize);

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
        }
        canvas.restore();
      }
      
      // 🟢 رسم الشفرات والصندوق بدون القص لكي تغطي الإطار
      if (model.hasShutter) {
        _drawShutterSlatsAndTracks(canvas, w, h, model.shutterPosition, boxSize);
        _drawShutterBox(canvas, w, boxSize);
      }
    }"""

if old_else_block in content:
    content = content.replace(old_else_block, new_else_block)
else:
    print("Could not find old_else_block!")

# 3. Fix side covers topY
old_side_covers = """  void _drawSideCovers(Canvas canvas, double w, double h, double boxSize, double t, double offsetY) {
    final topY = model.hasShutter ? 0.0 : 0.0; // Shutter box sits on top"""
new_side_covers = """  void _drawSideCovers(Canvas canvas, double w, double h, double boxSize, double t, double offsetY) {
    final topY = offsetY; // Shutter box sits on top"""

if old_side_covers in content:
    content = content.replace(old_side_covers, new_side_covers)
else:
    print("Could not find old_side_covers!")

# Finally, write the changes back
with open(file_path, "w", encoding="utf-8") as f:
    f.write(content)

print("Applied fixes for external view.")
