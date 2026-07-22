import 'dart:io';

void main() {
  _updatePaintDimensions('lib/Commande/window_painter.dart');
  _updatePaintDimensions('lib/Commande/Systeme/show_system_francais.dart');
}

void _updatePaintDimensions(String filePath) {
  var file = File(filePath);
  if (!file.existsSync()) return;
  
  var content = file.readAsStringSync();
  
  String original = '''
    Offset hMid = Offset(
      pos.dx - offsetDistLeft - 30.0,
      pos.dy + model.height / 2,
    );
    _drawText(canvas, '\${model.height.toInt()} mm', hMid, isVertical: true);
    _drawArrow(
      canvas,
      Offset(pos.dx - offsetDistLeft, pos.dy),
      Offset(pos.dx - offsetDistLeft, pos.dy + model.height),
      isVerticalLine: true,
    );
  }
''';

  String replacement = '''
    if (model.hasShutter) {
      // Draw caisson dimension
      double boxSize = model.shutterBoxHeight;
      Offset boxMid = Offset(
        pos.dx - offsetDistLeft - 30.0,
        pos.dy + boxSize / 2,
      );
      _drawText(canvas, '\${boxSize.toInt()} mm', boxMid, isVertical: true, isSmall: true);
      _drawArrow(
        canvas,
        Offset(pos.dx - offsetDistLeft, pos.dy),
        Offset(pos.dx - offsetDistLeft, pos.dy + boxSize),
        isVerticalLine: true,
      );

      // Draw window dimension
      double windowHeight = model.height - boxSize;
      Offset windowMid = Offset(
        pos.dx - offsetDistLeft - 30.0,
        pos.dy + boxSize + windowHeight / 2,
      );
      _drawText(canvas, '\${windowHeight.toInt()} mm', windowMid, isVertical: true);
      _drawArrow(
        canvas,
        Offset(pos.dx - offsetDistLeft, pos.dy + boxSize),
        Offset(pos.dx - offsetDistLeft, pos.dy + model.height),
        isVerticalLine: true,
      );
    } else {
      Offset hMid = Offset(
        pos.dx - offsetDistLeft - 30.0,
        pos.dy + model.height / 2,
      );
      _drawText(canvas, '\${model.height.toInt()} mm', hMid, isVertical: true);
      _drawArrow(
        canvas,
        Offset(pos.dx - offsetDistLeft, pos.dy),
        Offset(pos.dx - offsetDistLeft, pos.dy + model.height),
        isVerticalLine: true,
      );
    }
  }
''';

  content = content.replaceAll(original, replacement);
  
  // Now modify `_drawText` signature to accept `isSmall` parameter
  String drawTextOriginal = '''
  void _drawText(
    Canvas canvas,
    String text,
    Offset center, {
    bool isVertical = false,
  }) {
''';

  String drawTextReplacement = '''
  void _drawText(
    Canvas canvas,
    String text,
    Offset center, {
    bool isVertical = false,
    bool isSmall = false,
  }) {
''';

  content = content.replaceAll(drawTextOriginal, drawTextReplacement);

  // Update text size based on isSmall
  String textSizeOriginal = '''
          fontSize: 60,
''';
  if (filePath.contains('window_painter')) {
    textSizeOriginal = '''
          fontSize: 80,
''';
  }

  String textSizeReplacement = '''
          fontSize: isSmall ? 40 : ${filePath.contains('window_painter') ? '80' : '60'},
''';

  content = content.replaceAll(textSizeOriginal, textSizeReplacement);

  file.writeAsStringSync(content);
}
