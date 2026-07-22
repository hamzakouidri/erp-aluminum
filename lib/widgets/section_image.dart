import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

class SectionImageWidget extends StatelessWidget {
  final String? code;
  final String? imagePath;
  final double size;
  final Color? fallbackColor;
  final IconData? fallbackIcon;

  const SectionImageWidget({
    super.key,
    this.code,
    this.imagePath,
    this.size = 32.0,
    this.fallbackColor,
    this.fallbackIcon,
  });

  @override
  Widget build(BuildContext context) {
    final String rawCode = (code ?? '').trim();
    final String cleanCode = rawCode.replaceAll(' ', '').replaceAll('-', '').replaceAll('/', '').toUpperCase();
    final String path = (imagePath ?? '').trim();

    Widget fallbackWidget = Icon(
      fallbackIcon ?? Icons.image_not_supported_rounded,
      size: size,
      color: fallbackColor ?? Colors.grey,
    );

    // 1. If we have a Base64 data URL or local/uploaded path, try to display it
    if (path.isNotEmpty) {
      if (path.startsWith('data:image/')) {
        try {
          final uri = Uri.parse(path);
          final bytes = uri.data?.contentAsBytes();
          if (bytes != null) {
            final isSvg = path.contains('image/svg');
            if (isSvg) {
              fallbackWidget = SvgPicture.memory(
                bytes,
                width: size,
                height: size,
                fit: BoxFit.contain,
                placeholderBuilder: (context) => fallbackWidget,
              );
            } else {
              fallbackWidget = Image.memory(
                bytes,
                width: size,
                height: size,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) => fallbackWidget,
              );
            }
          }
        } catch (_) {}
      } else if (kIsWeb) {
        if (path.startsWith('http') || path.startsWith('blob:')) {
          fallbackWidget = Image.network(
            path,
            width: size,
            height: size,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) => fallbackWidget,
          );
        }
      } else {
        try {
          final file = File(path);
          if (file.existsSync()) {
            fallbackWidget = Image.file(
              file,
              width: size,
              height: size,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => fallbackWidget,
            );
          }
        } catch (_) {}
      }
    }

    // 2. If code is empty, return local file/fallback directly
    if (cleanCode.isEmpty) {
      return fallbackWidget;
    }

    // 3. Try to match by code in assets
    final List<String> tryAssetPaths = [
      'assets/images/$cleanCode.svg',
      'assets/images/$rawCode.svg',
      'assets/sections/$cleanCode.svg',
      'assets/images/$cleanCode.png',
      'assets/images/$rawCode.png',
      'assets/sections/$cleanCode.png',
    ];

    Widget buildChain(int index) {
      if (index >= tryAssetPaths.length) {
        return fallbackWidget;
      }

      final assetPath = tryAssetPaths[index];
      if (assetPath.endsWith('.svg')) {
        return SvgPicture.asset(
          assetPath,
          width: size,
          height: size,
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) {
            return buildChain(index + 1);
          },
        );
      } else {
        return Image.asset(
          assetPath,
          width: size,
          height: size,
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) {
            return buildChain(index + 1);
          },
        );
      }
    }

    return buildChain(0);
  }
}
