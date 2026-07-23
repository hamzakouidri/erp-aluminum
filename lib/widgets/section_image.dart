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
  final bool invertInDarkMode;

  const SectionImageWidget({
    super.key,
    this.code,
    this.imagePath,
    this.size = 32.0,
    this.fallbackColor,
    this.fallbackIcon,
    this.invertInDarkMode = true,
  });

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final String rawCode = (code ?? '').trim();
    final String cleanCode = rawCode
        .replaceAll(' ', '')
        .replaceAll('-', '')
        .replaceAll('/', '')
        .toUpperCase();
    final String path = (imagePath ?? '').trim();

    Widget fallbackWidget = Icon(
      fallbackIcon ?? Icons.image_not_supported_rounded,
      size: size,
      color: fallbackColor ?? (isDark ? Colors.grey.shade400 : Colors.grey),
    );

    Widget? loadedWidget;

    // 1. إحضار الصورة بناءً على المسار المربوط صراحة للمطع
    if (path.isNotEmpty) {
      if (path.startsWith('data:image/')) {
        try {
          final uri = Uri.parse(path);
          final bytes = uri.data?.contentAsBytes();
          if (bytes != null) {
            final isSvg = path.contains('image/svg');
            if (isSvg) {
              loadedWidget = SvgPicture.memory(
                bytes,
                width: size,
                height: size,
                fit: BoxFit.contain,
                placeholderBuilder: (context) => fallbackWidget,
              );
            } else {
              loadedWidget = Image.memory(
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
          loadedWidget = Image.network(
            path,
            width: size,
            height: size,
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) => fallbackWidget,
          );
        }
      } else {
        try {
          final file = File(path);
          if (file.existsSync()) {
            loadedWidget = Image.file(
              file,
              width: size,
              height: size,
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) => fallbackWidget,
            );
          }
        } catch (_) {}
      }
    }

    // 2. إذا لم يكن هناك مسار ملف مرفق ومباشر، نبحث فقط بالرمز التجاري الدقيق والاسم المباشر بدون تخمين
    if (loadedWidget == null && cleanCode.isNotEmpty) {
      final List<String> exactAssetPaths = [
        'assets/sections/$cleanCode.svg',
        'assets/sections/$rawCode.svg',
        'assets/images/$cleanCode.svg',
        'assets/images/$rawCode.svg',
        'assets/sections/$cleanCode.png',
        'assets/sections/$rawCode.png',
        'assets/images/$cleanCode.png',
        'assets/images/$rawCode.png',
      ];

      Widget buildExactChain(int index) {
        if (index >= exactAssetPaths.length) {
          return fallbackWidget;
        }

        final assetPath = exactAssetPaths[index];
        if (assetPath.endsWith('.svg')) {
          return SvgPicture.asset(
            assetPath,
            width: size,
            height: size,
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) {
              return buildExactChain(index + 1);
            },
          );
        } else {
          return Image.asset(
            assetPath,
            width: size,
            height: size,
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) {
              return buildExactChain(index + 1);
            },
          );
        }
      }

      loadedWidget = buildExactChain(0);
    }

    final Widget finalImage = loadedWidget ?? fallbackWidget;

    // 3. في الوضع الليلي (Dark Mode)، يتم تلوين رسم المقطع باللون الأبيض الناصع (Pure White) ليظهر بوضوح فائق وجذاب
    if (isDark && invertInDarkMode && loadedWidget != null) {
      return ColorFiltered(
        colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
        child: finalImage,
      );
    }

    return finalImage;
  }
}
