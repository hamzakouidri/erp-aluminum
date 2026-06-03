import 'dart:ui' as ui;
import 'package:flutter/services.dart' show rootBundle;
import 'dart:async';
import 'dart:typed_data';

class TextureCache {
  static ui.Image? woodTexture;
  
  static Future<void> init() async {
    if (woodTexture != null) return;
    try {
      final ByteData data = await rootBundle.load('assets/images/wood_texture.png');
      final Completer<ui.Image> completer = Completer();
      ui.decodeImageFromList(data.buffer.asUint8List(), (ui.Image img) {
        return completer.complete(img);
      });
      woodTexture = await completer.future;
    } catch (e) {
      print("Error loading wood texture: $e");
    }
  }
}
