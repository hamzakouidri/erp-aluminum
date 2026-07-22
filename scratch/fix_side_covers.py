import re

file_path = "lib/Commande/window_painter.dart"
with open(file_path, "r", encoding="utf-8") as f:
    content = f.read()

# Fix right cover
old_right = """    if (hasR) {
      canvas.drawPath(
        Path()
          ..moveTo(w, topY)
          ..lineTo(w + t, hasT ? topY - t : topY)
          ..lineTo(w + t, hasB ? offsetY + h + t : offsetY + h)
          ..lineTo(w, h)
          ..close(),
        paint,
      );
      canvas.drawPath(
        Path()
          ..moveTo(w, topY)
          ..lineTo(w + t, hasT ? topY - t : topY)
          ..lineTo(w + t, hasB ? offsetY + h + t : offsetY + h)
          ..lineTo(w, h)
          ..close(),
        borderPaint,
      );
    }"""
new_right = """    if (hasR) {
      canvas.drawPath(
        Path()
          ..moveTo(w, topY)
          ..lineTo(w + t, hasT ? topY - t : topY)
          ..lineTo(w + t, hasB ? offsetY + h + t : offsetY + h)
          ..lineTo(w, offsetY + h)
          ..close(),
        paint,
      );
      canvas.drawPath(
        Path()
          ..moveTo(w, topY)
          ..lineTo(w + t, hasT ? topY - t : topY)
          ..lineTo(w + t, hasB ? offsetY + h + t : offsetY + h)
          ..lineTo(w, offsetY + h)
          ..close(),
        borderPaint,
      );
    }"""

# Fix bottom cover
old_bottom = """    if (hasB) {
      canvas.drawPath(
        Path()
          ..moveTo(0, h)
          ..lineTo(hasL ? -t : 0.0, h + t)
          ..lineTo(hasR ? w + t : w, h + t)
          ..lineTo(w, h)
          ..close(),
        paint,
      );
      canvas.drawPath(
        Path()
          ..moveTo(0, h)
          ..lineTo(hasL ? -t : 0.0, h + t)
          ..lineTo(hasR ? w + t : w, h + t)
          ..lineTo(w, h)
          ..close(),
        borderPaint,
      );
    }"""
new_bottom = """    if (hasB) {
      canvas.drawPath(
        Path()
          ..moveTo(0, offsetY + h)
          ..lineTo(hasL ? -t : 0.0, offsetY + h + t)
          ..lineTo(hasR ? w + t : w, offsetY + h + t)
          ..lineTo(w, offsetY + h)
          ..close(),
        paint,
      );
      canvas.drawPath(
        Path()
          ..moveTo(0, offsetY + h)
          ..lineTo(hasL ? -t : 0.0, offsetY + h + t)
          ..lineTo(hasR ? w + t : w, offsetY + h + t)
          ..lineTo(w, offsetY + h)
          ..close(),
        borderPaint,
      );
    }"""

if old_right in content:
    content = content.replace(old_right, new_right)
if old_bottom in content:
    content = content.replace(old_bottom, new_bottom)

with open(file_path, "w", encoding="utf-8") as f:
    f.write(content)

print("Fixed side covers")
