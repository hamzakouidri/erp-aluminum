import 'dart:io';

void main() {
  var file = File('lib/Commande/Systeme/model.dart');
  var content = file.readAsStringSync();

  // 1. In resizeWindow, we must account for shutterBoxHeight if hasShutter is true
  // Let's replace the zones.isEmpty branch:
  content = content.replaceFirst(
'''
    if (zones.isEmpty) {
      zones.add(
        WindowZone(
          id: UniqueKey().toString(),
          boundary: Rect.fromLTRB(
            profileThickness,
            profileThickness,
            newW - profileThickness,
            newH - profileThickness,
          ),
        ),
      );
      width = newW;
      height = newH;
      notifyListeners();
      return;
    }
''',
'''
    double topOffset = hasShutter ? shutterBoxHeight : 0.0;
    if (zones.isEmpty) {
      zones.add(
        WindowZone(
          id: UniqueKey().toString(),
          boundary: Rect.fromLTRB(
            profileThickness,
            topOffset + profileThickness,
            newW - profileThickness,
            newH - profileThickness,
          ),
        ),
      );
      width = newW;
      height = newH;
      notifyListeners();
      return;
    }
'''
  );

  // 2. In resizeWindow, we must account for topOffset for scaling
  content = content.replaceFirst(
'''
    double oldInnerW = width - (profileThickness * 2);
    double oldInnerH = height - (profileThickness * 2);
    double newInnerW = newW - (profileThickness * 2);
    double newInnerH = newH - (profileThickness * 2);
    double scaleX = newInnerW / oldInnerW;
    double scaleY = newInnerH / oldInnerH;

    for (var z in zones) {
      double left =
          profileThickness + (z.boundary.left - profileThickness) * scaleX;
      double top =
          profileThickness + (z.boundary.top - profileThickness) * scaleY;
      double right =
          profileThickness + (z.boundary.right - profileThickness) * scaleX;
      double bottom =
          profileThickness + (z.boundary.bottom - profileThickness) * scaleY;
''',
'''
    double oldTopOffset = hasShutter ? shutterBoxHeight : 0.0; 
    // Wait, if hasShutter wasn't toggled during resizeWindow, oldTopOffset is the same as newTopOffset.
    double newTopOffset = hasShutter ? shutterBoxHeight : 0.0;

    double oldInnerW = width - (profileThickness * 2);
    double oldInnerH = height - oldTopOffset - (profileThickness * 2);
    double newInnerW = newW - (profileThickness * 2);
    double newInnerH = newH - newTopOffset - (profileThickness * 2);
    
    // Safety check for divisions by zero or negative inner heights
    if (oldInnerH <= 0) oldInnerH = 1;
    if (newInnerH <= 0) newInnerH = 1;
    if (oldInnerW <= 0) oldInnerW = 1;
    if (newInnerW <= 0) newInnerW = 1;

    double scaleX = newInnerW / oldInnerW;
    double scaleY = newInnerH / oldInnerH;

    for (var z in zones) {
      double left =
          profileThickness + (z.boundary.left - profileThickness) * scaleX;
      double top =
          newTopOffset + profileThickness + (z.boundary.top - (oldTopOffset + profileThickness)) * scaleY;
      double right =
          profileThickness + (z.boundary.right - profileThickness) * scaleX;
      double bottom =
          newTopOffset + profileThickness + (z.boundary.bottom - (oldTopOffset + profileThickness)) * scaleY;
'''
  );

  // 3. toggleShutter method: scale zones based on the new shutter state
  content = content.replaceFirst(
'''
  void toggleShutter(bool value) {
    _saveSnapshot();
    hasShutter = value;
    if (!value) removedShutterSides.clear();
    notifyListeners();
  }
''',
'''
  void toggleShutter(bool value) {
    if (hasShutter == value) return;
    _saveSnapshot();
    
    double oldTopOffset = hasShutter ? shutterBoxHeight : 0.0;
    hasShutter = value;
    double newTopOffset = hasShutter ? shutterBoxHeight : 0.0;
    
    if (!value) removedShutterSides.clear();
    
    // Scale zones vertically to adjust for shutter
    if (zones.isNotEmpty && height > 0) {
      double oldInnerH = height - oldTopOffset - (profileThickness * 2);
      double newInnerH = height - newTopOffset - (profileThickness * 2);
      if (oldInnerH > 0 && newInnerH > 0) {
        double scaleY = newInnerH / oldInnerH;
        for (var z in zones) {
          double top = newTopOffset + profileThickness + (z.boundary.top - (oldTopOffset + profileThickness)) * scaleY;
          double bottom = newTopOffset + profileThickness + (z.boundary.bottom - (oldTopOffset + profileThickness)) * scaleY;
          z.boundary = Rect.fromLTRB(z.boundary.left, top, z.boundary.right, bottom);
        }
      }
    }
    
    notifyListeners();
  }
'''
  );

  file.writeAsStringSync(content);
}
