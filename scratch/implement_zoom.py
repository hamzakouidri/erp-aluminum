import re

file_path = "lib/Commande/Systeme/show_system_francais.dart"

with open(file_path, "r", encoding="utf-8") as f:
    content = f.read()

# Replace onPanStart -> onScaleStart
content = re.sub(
    r"onPanStart: \(details\) \{",
    r"""onScaleStart: (details) {
                        if (details.pointerCount >= 2) {
                          _initialScale = widget.model.canvasScale;
                          return;
                        }""",
    content
)

# Replace onPanUpdate -> onScaleUpdate
content = re.sub(
    r"onPanUpdate: \(details\) \{",
    r"""onScaleUpdate: (details) {
                        if (details.pointerCount >= 2) {
                          setState(() {
                            widget.model.canvasScale = (_initialScale * details.scale).clamp(0.1, 5.0);
                            widget.model.canvasDx += details.focalPointDelta.dx;
                            widget.model.canvasDy += details.focalPointDelta.dy;
                          });
                          return;
                        }""",
    content
)

# Replace onPanEnd -> onScaleEnd
content = re.sub(
    r"onPanEnd: \(details\) \{",
    r"onScaleEnd: (details) {",
    content
)

# Replace onPanCancel -> onScaleCancel
# Actually, no need to replace onPanCancel, let's just do it to be safe
content = re.sub(
    r"onPanCancel: \(\) \{",
    r"// No need for onScaleCancel usually, but just in case, \n                      // ",
    content
)

# We need to add `double _initialScale = 1.0;` to _WorkspaceSectionState
content = re.sub(
    r"class _WorkspaceSectionState extends State<WorkspaceSection> \{",
    r"class _WorkspaceSectionState extends State<WorkspaceSection> {\n  double _initialScale = 1.0;",
    content
)

# wait, I should just do a very precise search and replace using dart's `InteractiveViewer`?
# NO, GestureDetector with `onScale` is perfectly what the user asked for (two finger zoom/pan).
# Wait, if we replace `onPanCancel` with `//` we will have a syntax error.
content = re.sub(
    r"// No need for onScaleCancel usually, but just in case, \\n                      // ",
    r"/* ",
    content
)
# Ah wait I can just use string replace.
with open(file_path, "w", encoding="utf-8") as f:
    f.write(content)

print("Done")
