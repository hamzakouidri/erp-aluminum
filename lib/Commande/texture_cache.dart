import 'dart:ui' as ui;
import 'package:flutter/services.dart' show rootBundle;
import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart'; // For Matrix4

class TextureCache {
  static Future<void>? _initTask;
  static ui.Image? woodTexture;
  static ui.Image? woodTextureD0;
  static ui.Image? woodTextureAntique;

  // Static cached shaders to avoid allocations during drawing
  static ui.Shader? _shaderD0;
  static ui.Shader? _shaderMahogany;
  static ui.Shader? _shaderAntique;

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
    } catch (e) {
      print("Error loading wood textures: $e");
    }
  }

  /// Starts decoding only when a drawing actually requests a wood texture.
  /// Keeping the future prevents several painters from decoding the same
  /// assets concurrently on memory-constrained phones.
  static void ensureLoading() {
    _initTask ??= init();
  }

  static ui.Shader? getShaderD0() {
    if (woodTextureD0 == null) ensureLoading();
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
    if (woodTexture == null) ensureLoading();
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
    if (woodTextureAntique == null) ensureLoading();
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
}
