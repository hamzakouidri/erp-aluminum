import re

file_path = "lib/Commande/window_painter.dart"
with open(file_path, "r", encoding="utf-8") as f:
    content = f.read()

# Replace the sashRect definition in _drawSlidingSash
old_sashRect = "        Rect sashRect = Rect.fromLTRB(left, r.top, right, r.bottom);"
# We subtract traverseT * 0.8 from top so it gets clipped by the innerPath, simulating it going into the top track
new_sashRect = "        Rect sashRect = Rect.fromLTRB(left, r.top - (traverseT * 0.8), right, r.bottom);"

if old_sashRect in content:
    content = content.replace(old_sashRect, new_sashRect)
    
    with open(file_path, "w", encoding="utf-8") as f:
        f.write(content)
    print("Sash rect shifted up to hide top rail.")
else:
    print("Could not find old_sashRect.")
