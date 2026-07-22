import 'dart:io';

void main() {
  var file = File('lib/Commande/window_painter.dart');
  var content = file.readAsStringSync();

  // 1. Remove all topOffset logic from window_painter.dart paths
  content = content.replaceFirst(
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
    p.lineTo(w, h - model.bottomSlantRightY);
    p.lineTo(0, h - model.bottomSlantLeftY);
    p.close();
    return p;
  }
''',
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
    p.lineTo(w, h - model.bottomSlantRightY);
    p.lineTo(0, h - model.bottomSlantLeftY);
    p.close();
    return p;
  }
'''
  );

  content = content.replaceFirst(
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
    p.lineTo(w - t, h - model.bottomSlantRightY - t);
    p.lineTo(t, h - model.bottomSlantLeftY - t);
    p.close();
    return p;
  }
''',
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
    p.lineTo(w - t, h - model.bottomSlantRightY - t);
    p.lineTo(t, h - model.bottomSlantLeftY - t);
    p.close();
    return p;
  }
'''
  );

  content = content.replaceFirst(
'''
    double topOffset = model.hasShutter ? model.shutterBoxHeight : 0.0;
    final outerRect = Rect.fromLTRB(0, topOffset, w, h);
    canvas.drawPath(path, Paint()..shader = _fsGlobal(outerRect));
''',
'''
    final outerRect = Rect.fromLTWH(0, 0, w, h);
    canvas.drawPath(path, Paint()..shader = _fsGlobal(outerRect));
'''
  );

  content = content.replaceFirst(
'''
    _drawMiterCorners(
      canvas,
      outerRect,
      Rect.fromLTRB(t, topOffset + t, w - t, h - t),
      t,
    );
''',
'''
    _drawMiterCorners(
      canvas,
      outerRect,
      Rect.fromLTWH(t, t, w - t * 2, h - t * 2),
      t,
    );
'''
  );

  content = content.replaceFirst(
'''
    canvas.save();
    double topOffset = model.hasShutter ? model.shutterBoxHeight : 0.0;
    canvas.clipRect(Rect.fromLTRB(t, topOffset + t, w - t, h - t));

    canvas.drawPath(combinedPath, paint);
''',
'''
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(t, t, w - t * 2, h - t * 2));

    canvas.drawPath(combinedPath, paint);
'''
  );

  content = content.replaceFirst(
'''
    // Shutter box is now drawn from 0 to boxSize. Window starts at boxSize.
    // So side covers should start at 0 if there's a shutter.
    final topY = 0.0;
''',
'''
    final topY = model.hasShutter ? -boxSize : 0.0;
'''
  );

  content = content.replaceFirst(
'''
  void _drawShutterBox(Canvas canvas, double w, double boxSize) {
    // Draw shutter box from 0 to boxSize
    final boxRect = Rect.fromLTWH(0, 0, w, boxSize);
''',
'''
  void _drawShutterBox(Canvas canvas, double w, double boxSize) {
    final boxRect = Rect.fromLTWH(0, -boxSize, w, boxSize);
'''
  );

  content = content.replaceFirst(
'''
    double topOffset = model.hasShutter ? model.shutterBoxHeight : 0.0;
    double trackHeight = h - topOffset;

    if (!model.removedShutterSides.contains('left')) {
      canvas.drawRect(Rect.fromLTWH(0, topOffset, coulisseWidth, trackHeight), coulissePaint);
      canvas.drawRect(Rect.fromLTWH(0, topOffset, coulisseWidth, trackHeight), coulisseBorder);
    }
    if (!model.removedShutterSides.contains('right')) {
      canvas.drawRect(
        Rect.fromLTWH(w - coulisseWidth, topOffset, coulisseWidth, trackHeight),
        coulissePaint,
      );
      canvas.drawRect(
        Rect.fromLTWH(w - coulisseWidth, topOffset, coulisseWidth, trackHeight),
        coulisseBorder,
      );
    }

    final visibleSlatsHeight = trackHeight * position;
    canvas.save();
    final leftClip = model.removedShutterSides.contains('left')
        ? 0.0
        : coulisseWidth;
    final rightClip = model.removedShutterSides.contains('right')
        ? w
        : w - coulisseWidth;
    canvas.clipRect(Rect.fromLTRB(leftClip, topOffset, rightClip, topOffset + visibleSlatsHeight));
    for (double y = topOffset; y < topOffset + visibleSlatsHeight; y += 20.0) {
''',
'''
    const coulisseWidth = 25.0;

    if (!model.removedShutterSides.contains('left')) {
      canvas.drawRect(Rect.fromLTWH(0, 0, coulisseWidth, h), coulissePaint);
      canvas.drawRect(Rect.fromLTWH(0, 0, coulisseWidth, h), coulisseBorder);
    }
    if (!model.removedShutterSides.contains('right')) {
      canvas.drawRect(
        Rect.fromLTWH(w - coulisseWidth, 0, coulisseWidth, h),
        coulissePaint,
      );
      canvas.drawRect(
        Rect.fromLTWH(w - coulisseWidth, 0, coulisseWidth, h),
        coulisseBorder,
      );
    }

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
'''
  );

  // NOW THE MOST IMPORTANT FIX:
  // Let's modify the paint method to use the correct `h`
  content = content.replaceFirst(
'''
  void paint(Canvas canvas, Size size) {
    final w = model.width, h = model.height, t = model.profileThickness;
    double boxSize = model.hasShutter ? model.shutterBoxHeight : 0.0;
''',
'''
  void paint(Canvas canvas, Size size) {
    final w = model.width;
    final h = model.hasShutter ? (model.height - model.shutterBoxHeight) : model.height;
    final t = model.profileThickness;
    double boxSize = model.hasShutter ? model.shutterBoxHeight : 0.0;
'''
  );

  // NOW let's fix the dimension drawing arrows!
  // In `show_system_francais.dart` and `window_painter.dart` `_paintDimensions`!
  // If the shutter box is at -boxSize to 0, then the shutter box dimensions should start from -boxSize and go to 0!
  // And the window dimensions should start from 0 and go to model.height - boxSize!

  file.writeAsStringSync(content);
}
