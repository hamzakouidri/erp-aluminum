import 'dart:ui' as ui;
import 'package:flutter/services.dart' show rootBundle;
import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart'; // For Matrix4

class TextureCache {
  static ui.Image? woodTexture;
  static ui.Image? woodTextureD0;
  static ui.Image? woodTextureAntique;
  static ui.Image? woodTextureDark;
  static ui.Image? woodTextureGrey;

  // Static cached shaders to avoid allocations during drawing
  static ui.Shader? _shaderD0;
  static ui.Shader? _shaderMahogany;
  static ui.Shader? _shaderAntique;
  static ui.Shader? _shaderDark;
  static ui.Shader? _shaderGrey;

  static Future<void> init() async {
    try {
      if (woodTexture == null) {
        final ByteData data = await rootBundle.load(
          'assets/images/wood_texture.png',
        );
        final Completer<ui.Image> completer = Completer();
        ui.decodeImageFromList(data.buffer.asUint8List(), (ui.Image img) {
          completer.complete(img);
        });
        woodTexture = await completer.future;
      }

      if (woodTextureD0 == null) {
        final ByteData data = await rootBundle.load(
          'assets/images/wood_texture_d0.png',
        );
        final Completer<ui.Image> completer = Completer();
        ui.decodeImageFromList(data.buffer.asUint8List(), (ui.Image img) {
          completer.complete(img);
        });
        woodTextureD0 = await completer.future;
      }

      if (woodTextureAntique == null) {
        final ByteData data = await rootBundle.load(
          'assets/images/wood_texture_antique.png',
        );
        final Completer<ui.Image> completer = Completer();
        ui.decodeImageFromList(data.buffer.asUint8List(), (ui.Image img) {
          completer.complete(img);
        });
        woodTextureAntique = await completer.future;
      }

      if (woodTextureDark == null) {
        final ByteData data = await rootBundle.load(
          'assets/images/wood_texture_dark.png',
        );
        final Completer<ui.Image> completer = Completer();
        ui.decodeImageFromList(data.buffer.asUint8List(), (ui.Image img) {
          completer.complete(img);
        });
        woodTextureDark = await completer.future;
      }

      if (woodTextureGrey == null) {
        final ByteData data = await rootBundle.load(
          'assets/images/wood_texture_grey.png',
        );
        final Completer<ui.Image> completer = Completer();
        ui.decodeImageFromList(data.buffer.asUint8List(), (ui.Image img) {
          completer.complete(img);
        });
        woodTextureGrey = await completer.future;
      }
      
      // Pre-compile the shaders
      if (woodTextureD0 != null) {
        _shaderD0 = ui.ImageShader(
          woodTextureD0!,
          ui.TileMode.repeated,
          ui.TileMode.repeated,
          Matrix4.identity().scaled(0.5).storage,
        );
      }
      if (woodTexture != null) {
        _shaderMahogany = ui.ImageShader(
          woodTexture!,
          ui.TileMode.repeated,
          ui.TileMode.repeated,
          Matrix4.identity().scaled(0.5).storage,
        );
      }
      if (woodTextureAntique != null) {
        _shaderAntique = ui.ImageShader(
          woodTextureAntique!,
          ui.TileMode.repeated,
          ui.TileMode.repeated,
          Matrix4.identity().scaled(0.5).storage,
        );
      }
      if (woodTextureDark != null) {
        _shaderDark = ui.ImageShader(
          woodTextureDark!,
          ui.TileMode.repeated,
          ui.TileMode.repeated,
          Matrix4.identity().scaled(0.5).storage,
        );
      }
      if (woodTextureGrey != null) {
        _shaderGrey = ui.ImageShader(
          woodTextureGrey!,
          ui.TileMode.repeated,
          ui.TileMode.repeated,
          Matrix4.identity().scaled(0.5).storage,
        );
      }
    } catch (e) {
      print("Error loading wood textures: $e");
    }
  }

  static ui.Shader? getShaderD0() {
    if (_shaderD0 == null && woodTextureD0 != null) {
      _shaderD0 = ui.ImageShader(
        woodTextureD0!,
        ui.TileMode.repeated,
        ui.TileMode.repeated,
        Matrix4.identity().scaled(0.5).storage,
      );
    }
    return _shaderD0;
  }

  static ui.Shader? getShaderMahogany() {
    if (_shaderMahogany == null && woodTexture != null) {
      _shaderMahogany = ui.ImageShader(
        woodTexture!,
        ui.TileMode.repeated,
        ui.TileMode.repeated,
        Matrix4.identity().scaled(0.5).storage,
      );
    }
    return _shaderMahogany;
  }

  static ui.Shader? getShaderAntique() {
    if (_shaderAntique == null && woodTextureAntique != null) {
      _shaderAntique = ui.ImageShader(
        woodTextureAntique!,
        ui.TileMode.repeated,
        ui.TileMode.repeated,
        Matrix4.identity().scaled(0.5).storage,
      );
    }
    return _shaderAntique;
  }

  static ui.Shader? getShaderDark() {
    if (_shaderDark == null && woodTextureDark != null) {
      _shaderDark = ui.ImageShader(
        woodTextureDark!,
        ui.TileMode.repeated,
        ui.TileMode.repeated,
        Matrix4.identity().scaled(0.5).storage,
      );
    }
    return _shaderDark;
  }

  static ui.Shader? getShaderGrey() {
    if (_shaderGrey == null && woodTextureGrey != null) {
      _shaderGrey = ui.ImageShader(
        woodTextureGrey!,
        ui.TileMode.repeated,
        ui.TileMode.repeated,
        Matrix4.identity().scaled(0.5).storage,
      );
    }
    return _shaderGrey;
  }
}
