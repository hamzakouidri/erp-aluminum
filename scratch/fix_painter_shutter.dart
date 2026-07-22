import 'dart:io';

void main() {
  var file = File('lib/Commande/window_painter.dart');
  var content = file.readAsStringSync();

  // Fix `_buildOuterShapePath`
  content = content.replaceFirst(
'''
  Path _buildOuterShapePath(double w, double h) {
    if (model.archHeight == 0 &&
        model.topSlantLeftY == 0 &&
        model.topSlantRightY == 0 &&
        model.bottomSlantLeftY == 0 &&
        model.bottomSlantRightY == 0) {
      return Path()..addRect(Rect.fromLTWH(0, 0, w, h));
    }
    Path p = Path();
    p.moveTo(0, model.topSlantLeftY);
''',
'''
  Path _buildOuterShapePath(double w, double h) {
    double topOffset = model.hasShutter ? model.shutterBoxHeight : 0.0;
    if (model.archHeight == 0 &&
        model.topSlantLeftY == 0 &&
        model.topSlantRightY == 0 &&
        model.bottomSlantLeftY == 0 &&
        model.bottomSlantRightY == 0) {
      return Path()..addRect(Rect.fromLTRB(0, topOffset, w, h));
    }
    Path p = Path();
    p.moveTo(0, topOffset + model.topSlantLeftY);
'''
  );

  // Still in `_buildOuterShapePath`
  content = content.replaceFirst(
'''
    if (model.archHeight > 0) {
      p.quadraticBezierTo(
        w / 2,
        math.min(model.topSlantLeftY, model.topSlantRightY) -
            (model.archHeight * 2),
        w,
        model.topSlantRightY,
      );
    } else {
      p.lineTo(w, model.topSlantRightY);
    }
''',
'''
    if (model.archHeight > 0) {
      p.quadraticBezierTo(
        w / 2,
        topOffset + math.min(model.topSlantLeftY, model.topSlantRightY) -
            (model.archHeight * 2),
        w,
        topOffset + model.topSlantRightY,
      );
    } else {
      p.lineTo(w, topOffset + model.topSlantRightY);
    }
'''
  );

  // Fix `_buildInnerShapePath`
  content = content.replaceFirst(
'''
  Path _buildInnerShapePath(double w, double h, double t) {
    if (model.archHeight == 0 &&
        model.topSlantLeftY == 0 &&
        model.topSlantRightY == 0 &&
        model.bottomSlantLeftY == 0 &&
        model.bottomSlantRightY == 0) {
      return Path()..addRect(Rect.fromLTWH(t, t, w - t * 2, h - t * 2));
    }
    Path p = Path();
    p.moveTo(t, model.topSlantLeftY + t);
''',
'''
  Path _buildInnerShapePath(double w, double h, double t) {
    double topOffset = model.hasShutter ? model.shutterBoxHeight : 0.0;
    if (model.archHeight == 0 &&
        model.topSlantLeftY == 0 &&
        model.topSlantRightY == 0 &&
        model.bottomSlantLeftY == 0 &&
        model.bottomSlantRightY == 0) {
      return Path()..addRect(Rect.fromLTRB(t, topOffset + t, w - t, h - t));
    }
    Path p = Path();
    p.moveTo(t, topOffset + model.topSlantLeftY + t);
'''
  );

  // Still in `_buildInnerShapePath`
  content = content.replaceFirst(
'''
    if (model.archHeight > 0) {
      p.quadraticBezierTo(
        w / 2,
        math.min(model.topSlantLeftY, model.topSlantRightY) -
            (model.archHeight * 2) +
            t,
        w - t,
        model.topSlantRightY + t,
      );
    } else {
      p.lineTo(w - t, model.topSlantRightY + t);
    }
''',
'''
    if (model.archHeight > 0) {
      p.quadraticBezierTo(
        w / 2,
        topOffset + math.min(model.topSlantLeftY, model.topSlantRightY) -
            (model.archHeight * 2) +
            t,
        w - t,
        topOffset + model.topSlantRightY + t,
      );
    } else {
      p.lineTo(w - t, topOffset + model.topSlantRightY + t);
    }
'''
  );

  // Fix outerRect in _drawOuterFrame
  content = content.replaceFirst(
'''
    final outerRect = Rect.fromLTWH(0, 0, w, h);
    canvas.drawPath(path, Paint()..shader = _fsGlobal(outerRect));
''',
'''
    double topOffset = model.hasShutter ? model.shutterBoxHeight : 0.0;
    final outerRect = Rect.fromLTRB(0, topOffset, w, h);
    canvas.drawPath(path, Paint()..shader = _fsGlobal(outerRect));
'''
  );
  
  content = content.replaceFirst(
'''
    _drawMiterCorners(
      canvas,
      outerRect,
      Rect.fromLTWH(t, t, w - t * 2, h - t * 2),
      t,
    );
''',
'''
    _drawMiterCorners(
      canvas,
      outerRect,
      Rect.fromLTRB(t, topOffset + t, w - t, h - t),
      t,
    );
'''
  );

  // Fix _drawMullions
  content = content.replaceFirst(
'''
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(t, t, w - t * 2, h - t * 2));

    canvas.drawPath(combinedPath, paint);
''',
'''
    canvas.save();
    double topOffset = model.hasShutter ? model.shutterBoxHeight : 0.0;
    canvas.clipRect(Rect.fromLTRB(t, topOffset + t, w - t, h - t));

    canvas.drawPath(combinedPath, paint);
'''
  );

  // Fix _drawSideCovers. Side covers normally start at `topY`
  // Actually side covers ALREADY do `topY = model.hasShutter ? -boxSize : 0.0;`
  // Wait, if the outer frame is shifted down to `boxSize`, then the side covers should start from `0` when there's a shutter?
  // Let's check `_drawSideCovers`:
  //    final topY = model.hasShutter ? -boxSize : 0.0;
  // Oh, previously, if there was a shutter, the window was drawn at 0 to h, and the shutter box was drawn from 0 to boxSize OVERLAPPING the window!
  // And the side covers started at -boxSize (above the window)!
  // But now the window starts at `boxSize` to `h`.
  // So the shutter box should be drawn from `0` to `boxSize`.
  // And the side covers should start at `0` (if hasShutter) or `0` (if no shutter), BUT they should go down to `h`.
  // Let's modify `_drawSideCovers`.
  content = content.replaceFirst(
'''
  void _drawSideCovers(
    Canvas canvas,
    double w,
    double h,
    double boxSize,
    double t,
  ) {
    final topY = model.hasShutter ? -boxSize : 0.0;
''',
'''
  void _drawSideCovers(
    Canvas canvas,
    double w,
    double h,
    double boxSize,
    double t,
  ) {
    // Shutter box is now drawn from 0 to boxSize. Window starts at boxSize.
    // So side covers should start at 0 if there's a shutter.
    final topY = 0.0;
'''
  );

  file.writeAsStringSync(content);
}
