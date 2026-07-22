import re

file_path = "lib/Commande/Systeme/show_system_francais.dart"
with open(file_path, "r", encoding="utf-8") as f:
    content = f.read()

# 1. Update _handleHandleDrag to use ScaleUpdateDetails instead of DragUpdateDetails
old_handle_drag = """  void _handleHandleDrag(DragUpdateDetails details, WindowZone zone) {
    if (zone.openDirection == null) return;
    double dx = details.delta.dx / widget.model.canvasScale;
    double dy = details.delta.dy / widget.model.canvasScale;"""

new_handle_drag = """  void _handleHandleDrag(ScaleUpdateDetails details, WindowZone zone) {
    if (zone.openDirection == null) return;
    double dx = details.focalPointDelta.dx / widget.model.canvasScale;
    double dy = details.focalPointDelta.dy / widget.model.canvasScale;"""

content = content.replace(old_handle_drag, new_handle_drag)

# 2. Replace the gesture handling inside LayoutBuilder
old_gesture = """                      onPanStart: (details) {
                        final modelPos = Offset(
                          (details.localPosition.dx - widget.model.canvasDx) /
                              widget.model.canvasScale,
                          (details.localPosition.dy - widget.model.canvasDy) /
                              widget.model.canvasScale,
                        );
                        if (widget.model.isDrawingMode &&
                            widget.model.selection.type !=
                                SelectionType.mullion) {
                          widget.model.startDrawing(modelPos);
                        } else if (widget.model.selectedZone != null &&
                            widget.model.selectedZone!.boundary.contains(
                              modelPos,
                            )) {
                          _isDraggingHandle = true;
                        }
                      },
                      onPanUpdate: (details) {
                        final modelPos = Offset(
                          (details.localPosition.dx - widget.model.canvasDx) /
                              widget.model.canvasScale,
                          (details.localPosition.dy - widget.model.canvasDy) /
                              widget.model.canvasScale,
                        );
                        if (widget.model.drawingStart != null) {
                          widget.model.updateDrawing(modelPos);
                        } else if (widget.model.selection.type ==
                                SelectionType.mullion &&
                            !widget.model.isDrawingMode) {
                          widget.model.moveSelectedMullion(
                            (widget.model.selection.isHorizontalMullion!
                                    ? details.delta.dy
                                    : details.delta.dx) /
                                widget.model.canvasScale,
                          );
                        } else if (_isDraggingHandle &&
                            widget.model.selectedZone != null) {
                          _handleHandleDrag(
                            details,
                            widget.model.selectedZone!,
                          );
                        }
                      },
                      onPanEnd: (details) {
                        if (widget.model.drawingStart != null) {
                          widget.model.endDrawing();
                        }
                        _isDraggingHandle = false;
                      },
                      onPanCancel: () {
                        _isDraggingHandle = false;
                      },"""

new_gesture = """                      onScaleStart: (details) {
                        if (details.pointerCount == 1) {
                          final modelPos = Offset(
                            (details.localFocalPoint.dx - widget.model.canvasDx) /
                                widget.model.canvasScale,
                            (details.localFocalPoint.dy - widget.model.canvasDy) /
                                widget.model.canvasScale,
                          );
                          if (widget.model.isDrawingMode &&
                              widget.model.selection.type !=
                                  SelectionType.mullion) {
                            widget.model.startDrawing(modelPos);
                          } else if (widget.model.selectedZone != null &&
                              widget.model.selectedZone!.boundary.contains(
                                modelPos,
                              )) {
                            _isDraggingHandle = true;
                          }
                        } else {
                          // For zooming, store initial scale
                          widget.model.startPanZoom();
                        }
                      },
                      onScaleUpdate: (details) {
                        if (details.pointerCount == 1) {
                          final modelPos = Offset(
                            (details.localFocalPoint.dx - widget.model.canvasDx) /
                                widget.model.canvasScale,
                            (details.localFocalPoint.dy - widget.model.canvasDy) /
                                widget.model.canvasScale,
                          );
                          if (widget.model.drawingStart != null) {
                            widget.model.updateDrawing(modelPos);
                          } else if (widget.model.selection.type ==
                                  SelectionType.mullion &&
                              !widget.model.isDrawingMode) {
                            widget.model.moveSelectedMullion(
                              (widget.model.selection.isHorizontalMullion!
                                      ? details.focalPointDelta.dy
                                      : details.focalPointDelta.dx) /
                                  widget.model.canvasScale,
                            );
                          } else if (_isDraggingHandle &&
                              widget.model.selectedZone != null) {
                            _handleHandleDrag(
                              details,
                              widget.model.selectedZone!,
                            );
                          }
                        } else {
                          // Pan and Zoom
                          widget.model.updatePanZoom(details.focalPointDelta, details.scale);
                        }
                      },
                      onScaleEnd: (details) {
                        if (widget.model.drawingStart != null) {
                          widget.model.endDrawing();
                        }
                        _isDraggingHandle = false;
                        widget.model.endPanZoom();
                      },"""

content = content.replace(old_gesture, new_gesture)

with open(file_path, "w", encoding="utf-8") as f:
    f.write(content)

print("GestureDetector replaced.")
