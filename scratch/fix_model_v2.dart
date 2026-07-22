import 'dart:io';

void main() {
  var file = File('lib/Commande/Systeme/model.dart');
  var content = file.readAsStringSync();

  // Revert resizeWindow
  content = content.replaceFirst(
'''
  void resizeWindow(double newW, double newH) {
    _saveSnapshot();
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

    double oldInnerW = width - (profileThickness * 2);
    double oldInnerH = height - topOffset - (profileThickness * 2);
    double newInnerW = newW - (profileThickness * 2);
    double newInnerH = newH - topOffset - (profileThickness * 2);
    
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
          topOffset + profileThickness + (z.boundary.top - (topOffset + profileThickness)) * scaleY;
      double right =
          profileThickness + (z.boundary.right - profileThickness) * scaleX;
      double bottom =
          topOffset + profileThickness + (z.boundary.bottom - (topOffset + profileThickness)) * scaleY;
      z.boundary = Rect.fromLTRB(left, top, right, bottom);
    }
    width = newW;
    height = newH;
    notifyListeners();
  }
''',
'''
  void resizeWindow(double newW, double newH) {
    _saveSnapshot();
    
    double currentFrameH = hasShutter ? (height - shutterBoxHeight) : height;
    double newFrameH = hasShutter ? (newH - shutterBoxHeight) : newH;

    if (zones.isEmpty) {
      zones.add(
        WindowZone(
          id: UniqueKey().toString(),
          boundary: Rect.fromLTRB(
            profileThickness,
            profileThickness,
            newW - profileThickness,
            newFrameH - profileThickness,
          ),
        ),
      );
      width = newW;
      height = newH;
      notifyListeners();
      return;
    }

    double oldInnerW = width - (profileThickness * 2);
    double oldInnerH = currentFrameH - (profileThickness * 2);
    double newInnerW = newW - (profileThickness * 2);
    double newInnerH = newFrameH - (profileThickness * 2);
    
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
          profileThickness + (z.boundary.top - profileThickness) * scaleY;
      double right =
          profileThickness + (z.boundary.right - profileThickness) * scaleX;
      double bottom =
          profileThickness + (z.boundary.bottom - profileThickness) * scaleY;
      z.boundary = Rect.fromLTRB(left, top, right, bottom);
    }
    width = newW;
    height = newH;
    notifyListeners();
  }
'''
  );

  // Revert toggleShutter
  content = content.replaceFirst(
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
''',
'''
  void toggleShutter(bool value) {
    if (hasShutter == value) return;
    _saveSnapshot();
    
    double oldFrameH = hasShutter ? (height - shutterBoxHeight) : height;
    hasShutter = value;
    double newFrameH = hasShutter ? (height - shutterBoxHeight) : height;
    
    if (!value) removedShutterSides.clear();
    
    // Scale zones vertically to adjust for shutter
    if (zones.isNotEmpty && height > 0) {
      double oldInnerH = oldFrameH - (profileThickness * 2);
      double newInnerH = newFrameH - (profileThickness * 2);
      if (oldInnerH > 0 && newInnerH > 0) {
        double scaleY = newInnerH / oldInnerH;
        for (var z in zones) {
          double top = profileThickness + (z.boundary.top - profileThickness) * scaleY;
          double bottom = profileThickness + (z.boundary.bottom - profileThickness) * scaleY;
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
