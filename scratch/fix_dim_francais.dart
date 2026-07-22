import 'dart:io';

void main() {
  var file = File('lib/Commande/Systeme/show_system_francais.dart');
  var content = file.readAsStringSync();

  content = content.replaceFirst(
'''
  void _paintDimensions(Canvas canvas, WindowModel model, Offset pos) {
    double offsetDistTop = 100.0;
    if (model.hasShutter) offsetDistTop += 150.0;
    if (model.hasSideCovers && !model.removedShutterSides.contains('top')) {
      offsetDistTop += 60.0;
    }
''',
'''
  void _paintDimensions(Canvas canvas, WindowModel model, Offset pos) {
    double offsetDistTop = 100.0;
    // model.hasShutter is already inside model.height, so we don't offset extra
    if (model.hasSideCovers && !model.removedShutterSides.contains('top')) {
      offsetDistTop += 60.0;
    }
'''
  );

  file.writeAsStringSync(content);
}
