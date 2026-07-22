import 'dart:io';

void main() {
  var file = File('lib/Commande/window_painter.dart');
  var content = file.readAsStringSync();

  // Fix `_drawShutterBox`
  content = content.replaceFirst(
'''
  void _drawShutterBox(Canvas canvas, double w, double boxSize) {
    final boxRect = Rect.fromLTWH(0, -boxSize, w, boxSize);
''',
'''
  void _drawShutterBox(Canvas canvas, double w, double boxSize) {
    // Draw shutter box from 0 to boxSize
    final boxRect = Rect.fromLTWH(0, 0, w, boxSize);
'''
  );

  // Fix `_drawShutterSlatsAndTracks`
  content = content.replaceFirst(
'''
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
''',
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
'''
  );

  // Fix dimensions painter `WorkspacePainter._paintDimensions`
  // since the shutter box is now INCLUDED in `model.height`
  // `offsetDistTop` doesn't need `if (model.hasShutter) offsetDistTop += 150.0;`
  content = content.replaceFirst(
'''
    double offsetDistTop = 100.0;
    double dynamicCoverWidth = model.selectedSideCover?.couvreJointWidth ?? 60.0;
    if (model.hasShutter) offsetDistTop += 150.0;
    if (model.hasSideCovers && !model.removedShutterSides.contains('top')) {
''',
'''
    double offsetDistTop = 100.0;
    double dynamicCoverWidth = model.selectedSideCover?.couvreJointWidth ?? 60.0;
    // Shutter is now included in model.height, so we don't offset the top dimension arrow extra
    if (model.hasSideCovers && !model.removedShutterSides.contains('top')) {
'''
  );

  file.writeAsStringSync(content);
}
