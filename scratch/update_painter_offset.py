import re

file_path = "lib/Commande/window_painter.dart"

with open(file_path, "r", encoding="utf-8") as f:
    content = f.read()

# 1. Update _buildOuterShapePath
content = re.sub(
    r"Path _buildOuterShapePath\(double w, double h\) \{",
    r"Path _buildOuterShapePath(double w, double h, double offsetY) {",
    content,
    count=1
)
content = re.sub(
    r"return Path\(\)\.\.addRect\(Rect\.fromLTWH\(0, 0, w, h\)\);",
    r"return Path()..addRect(Rect.fromLTWH(0, offsetY, w, h));",
    content,
    count=1
)
content = re.sub(
    r"p\.moveTo\(0, model\.topSlantLeftY\);",
    r"p.moveTo(0, offsetY + model.topSlantLeftY);",
    content,
    count=1
)
content = re.sub(
    r"model\.topSlantLeftY, model\.topSlantRightY\) -\n\s*\(model\.archHeight \* 2\),",
    r"model.topSlantLeftY, model.topSlantRightY) - (model.archHeight * 2) + offsetY,",
    content,
    count=1
)
content = re.sub(
    r"w,\n\s*model\.topSlantRightY,",
    r"w, offsetY + model.topSlantRightY,",
    content,
    count=1
)
content = re.sub(
    r"p\.lineTo\(w, model\.topSlantRightY\);",
    r"p.lineTo(w, offsetY + model.topSlantRightY);",
    content,
    count=1
)
content = re.sub(
    r"p\.lineTo\(w, h - model\.bottomSlantRightY\);",
    r"p.lineTo(w, offsetY + h - model.bottomSlantRightY);",
    content,
    count=1
)
content = re.sub(
    r"p\.lineTo\(0, h - model\.bottomSlantLeftY\);",
    r"p.lineTo(0, offsetY + h - model.bottomSlantLeftY);",
    content,
    count=1
)

# 2. Update _buildInnerShapePath
content = re.sub(
    r"Path _buildInnerShapePath\(double w, double h, double t\) \{",
    r"Path _buildInnerShapePath(double w, double h, double t, double offsetY) {",
    content,
    count=1
)
content = re.sub(
    r"return Path\(\)\.\.addRect\(Rect\.fromLTWH\(t, t, w - t \* 2, h - t \* 2\)\);",
    r"return Path()..addRect(Rect.fromLTWH(t, offsetY + t, w - t * 2, h - t * 2));",
    content,
    count=1
)
content = re.sub(
    r"p\.moveTo\(t, model\.topSlantLeftY \+ t\);",
    r"p.moveTo(t, offsetY + model.topSlantLeftY + t);",
    content,
    count=1
)
content = re.sub(
    r"model\.topSlantLeftY, model\.topSlantRightY\) -\n\s*\(model\.archHeight \* 2\) \+\n\s*t,",
    r"model.topSlantLeftY, model.topSlantRightY) - (model.archHeight * 2) + t + offsetY,",
    content,
    count=1
)
content = re.sub(
    r"w - t,\n\s*model\.topSlantRightY \+ t,",
    r"w - t, offsetY + model.topSlantRightY + t,",
    content,
    count=1
)
content = re.sub(
    r"p\.lineTo\(w - t, model\.topSlantRightY \+ t\);",
    r"p.lineTo(w - t, offsetY + model.topSlantRightY + t);",
    content,
    count=1
)
content = re.sub(
    r"p\.lineTo\(w - t, h - model\.bottomSlantRightY - t\);",
    r"p.lineTo(w - t, offsetY + h - model.bottomSlantRightY - t);",
    content,
    count=1
)
content = re.sub(
    r"p\.lineTo\(t, h - model\.bottomSlantLeftY - t\);",
    r"p.lineTo(t, offsetY + h - model.bottomSlantLeftY - t);",
    content,
    count=1
)

# 3. Update _drawOuterFrame
content = re.sub(
    r"void _drawOuterFrame\(Canvas canvas, double w, double h, double t\) \{",
    r"void _drawOuterFrame(Canvas canvas, double w, double h, double t, double offsetY) {",
    content,
    count=1
)
content = re.sub(
    r"final outerPath = _buildOuterShapePath\(w, h\);",
    r"final outerPath = _buildOuterShapePath(w, h, offsetY);",
    content,
    count=1
)
content = re.sub(
    r"final innerPath = _buildInnerShapePath\(w, h, t\);",
    r"final innerPath = _buildInnerShapePath(w, h, t, offsetY);",
    content,
    count=1
)
content = re.sub(
    r"final outerRect = Rect\.fromLTWH\(0, 0, w, h\);",
    r"final outerRect = Rect.fromLTWH(0, offsetY, w, h);",
    content,
    count=1
)
content = re.sub(
    r"Rect\.fromLTWH\(t, t, w - t \* 2, h - t \* 2\),",
    r"Rect.fromLTWH(t, offsetY + t, w - t * 2, h - t * 2),",
    content,
    count=1
)

# 4. Update _drawSideCovers
content = re.sub(
    r"void _drawSideCovers\(\n\s*Canvas canvas,\n\s*double w,\n\s*double h,\n\s*double boxSize,\n\s*double t,\n\s*\) \{",
    r"void _drawSideCovers(Canvas canvas, double w, double h, double boxSize, double t, double offsetY) {",
    content,
    count=1
)
content = re.sub(
    r"final topY = model\.hasShutter \? -boxSize : 0\.0;",
    r"final topY = model.hasShutter ? 0.0 : 0.0; // Shutter box sits on top",
    content,
    count=1
)
content = re.sub(
    r"hasB \? h \+ t : h\)",
    r"hasB ? offsetY + h + t : offsetY + h)",
    content,
    count=4
)
content = re.sub(
    r"0, h\)",
    r"0, offsetY + h)",
    content,
    count=2
)
content = re.sub(
    r"w, h\)",
    r"w, offsetY + h)",
    content,
    count=2
)


# 5. Update _drawShutterBox
content = re.sub(
    r"final boxRect = Rect\.fromLTWH\(0, -boxSize, w, boxSize\);",
    r"final boxRect = Rect.fromLTWH(0, 0, w, boxSize);",
    content,
    count=1
)

# 6. Update paint()
content = re.sub(
    r"final innerPath = _buildInnerShapePath\(w, h, t\);",
    r"final innerPath = _buildInnerShapePath(w, h, t, boxSize);",
    content,
    count=1
)
content = re.sub(
    r"_drawOuterFrame\(canvas, w, h, t\);",
    r"_drawOuterFrame(canvas, w, h, t, boxSize);",
    content,
    count=2
)
content = re.sub(
    r"if \(model\.hasSideCovers\) _drawSideCovers\(canvas, w, h, boxSize, t\);",
    r"if (model.hasSideCovers) _drawSideCovers(canvas, w, h, boxSize, t, boxSize);",
    content,
    count=2
)
content = re.sub(
    r"_drawWeepHoles\(canvas, Rect\.fromLTWH\(0, 0, w, h\), t\);",
    r"_drawWeepHoles(canvas, Rect.fromLTWH(0, boxSize, w, h), t);",
    content,
    count=1
)

with open(file_path, "w", encoding="utf-8") as f:
    f.write(content)
print("Done")
