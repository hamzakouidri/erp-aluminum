import re

file_path = "lib/Commande/Systeme/show_system_francais.dart"
with open(file_path, "r", encoding="utf-8") as f:
    content = f.read()

# Replace GestureDetector with InteractiveViewer wrapping it
old_gesture = """                    return GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTapUp: (details) {"""

new_gesture = """                    return InteractiveViewer(
                      panEnabled: false,
                      scaleEnabled: true,
                      minScale: 0.5,
                      maxScale: 4.0,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTapUp: (details) {"""

content = content.replace(old_gesture, new_gesture)

# Add closing parenthesis for InteractiveViewer
old_end = """                          painter: AppWorkspacePainter(model: widget.model),
                        ),
                      ),
                    );
                  },
                ),"""

new_end = """                          painter: AppWorkspacePainter(model: widget.model),
                        ),
                      ),
                    ));
                  },
                ),"""

content = content.replace(old_end, new_end)

with open(file_path, "w", encoding="utf-8") as f:
    f.write(content)

print("InteractiveViewer added successfully.")
