import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

class SectionImageWidget extends StatelessWidget {
  final String? code;
  final String? name;
  final String? imagePath;
  final double size;
  final Color? fallbackColor;
  final IconData? fallbackIcon;
  final bool invertInDarkMode;

  const SectionImageWidget({
    super.key,
    this.code,
    this.name,
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
    final String codeWithoutExtension = rawCode.replaceFirst(
      RegExp(r'\.(png|jpe?g|jpeg|svg|webp)$', caseSensitive: false),
      '',
    );
    final String cleanCode = codeWithoutExtension
        .replaceAll(' ', '')
        .replaceAll('-', '')
        .replaceAll('/', '')
        .toUpperCase();
    final String path = (imagePath ?? '').trim();
    final String lowerPath = path.toLowerCase();
    final bool isAssetReference =
        lowerPath.startsWith('assets/') || lowerPath.startsWith('asset/');

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
      } else if (isAssetReference) {
        // Asset references are resolved below together with the code-based
        // candidates. This lets a bad stored path fall back to N242.png.
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
    if (loadedWidget == null) {
      final exactAssetPaths = <String>[];
      void addUnique(String candidate) {
        if (candidate.isNotEmpty && !exactAssetPaths.contains(candidate)) {
          exactAssetPaths.add(candidate);
        }
      }

      void addAssetFileCandidates(String rawValue) {
        final value = rawValue.trim().replaceAll('\\', '/');
        if (value.isEmpty) return;
        final filename = value.split('/').last.trim();
        if (filename.isEmpty) return;
        // Several catalogue records used different filenames for the exact
        // same image. Keep one bundled file and resolve all legacy names to
        // that canonical asset.
        final stem = filename
            .replaceFirst(
              RegExp(r'\.(svg|png|jpe?g|webp)$', caseSensitive: false),
              '',
            )
            .toLowerCase();
        const imageAliases = <String, String>{
          'roulette_double': 'roulette.png',
          'roulettes': 'roulette.png',
          'roullette': 'roulette.png',
          'رولات': 'roulette.png',
          'عجلات_المنزلق': 'roulette.png',
          'joint bross': 'joint_brosse.png',
          'joint_bross': 'joint_brosse.png',
          'joint_brosse_sash': 'joint_brosse.png',
          'joint_brosse_shutter': 'joint_brosse.png',
          'entrematique': 'intramatique.png',
          'أونتروماتيك': 'intramatique.png',
          'انتروماتيك': 'intramatique.png',
          'andramatique': 'intramatique.png',
          '514c': '514.png',
          '511c': '511.png',
          '116b': '11690.png',
          'gache colissante tpr': 'gache_colissante_tpr.png',
          'gache_coulissant_tpr': 'gache_colissante_tpr.png',
          'joint_vitrage': 'N242.png',
          'vis': 'visse.png',
          'براغي': 'visse.png',
        };
        final canonicalFilename = imageAliases[stem];
        if (canonicalFilename != null) {
          addUnique('assets/sections/$canonicalFilename');
          addUnique('assets/images/$canonicalFilename');
          return;
        }

        // Do not generate a long chain of impossible asset requests for an
        // Arabic display label. Explicit asset paths are still handled above.
        if (!RegExp(r'[A-Za-z0-9]').hasMatch(filename)) return;

        final hasExtension = RegExp(
          r'\.(svg|png|jpe?g|webp)$',
          caseSensitive: false,
        ).hasMatch(filename);
        final filenames = hasExtension
            ? <String>[filename]
            : <String>[
                '$filename.svg',
                '$filename.png',
                '$filename.jpg',
                '$filename.jpeg',
                '$filename.webp',
              ];
        // Keep the exact spelling first, then support assets whose stored
        // catalog name differs only by letter case (for example Cremone /
        // cremone.png).
        final lowerCaseFilenames = filenames
            .map((file) => file.toLowerCase())
            .toSet()
            .toList();
        final allFilenames = [...filenames, ...lowerCaseFilenames];
        for (final file in allFilenames) {
          addUnique('assets/sections/$file');
          addUnique('assets/images/$file');
        }
      }

      if (isAssetReference) {
        addUnique(
          lowerPath.startsWith('asset/') ? 'assets/${path.substring(6)}' : path,
        );
        // A database may store only the filename or a Windows path. Also try
        // the bundled asset folders using its basename.
        addAssetFileCandidates(path);
      } else if (path.isNotEmpty &&
          !path.startsWith('http') &&
          !path.startsWith('blob:') &&
          !path.startsWith('data:')) {
        // Product images are commonly stored as "N242.png" or as a local
        // Windows path. They are bundled under assets/sections.
        addAssetFileCandidates(path);
      }
      if (cleanCode.isNotEmpty) {
        addAssetFileCandidates(codeWithoutExtension);
        addAssetFileCandidates(cleanCode);
      }

      // Accessories historically had no code/image_path column. When their
      // catalog name contains the image filename (for example N242 or
      // "Cremone"), use it as a final asset lookup key as well.
      final nameLines = (name ?? '').split(RegExp(r'[\r\n]+'));
      for (final line in nameLines) {
        final value = line.trim();
        if (value.isEmpty) continue;
        addAssetFileCandidates(value);
        for (final part in value.split(RegExp(r'\s[-–—]\s|[()]'))) {
          final token = part.trim();
          if (token.isNotEmpty) addAssetFileCandidates(token);
        }
      }
      if (exactAssetPaths.isEmpty &&
          path.contains('.') &&
          !path.startsWith('http') &&
          !path.startsWith('blob:') &&
          !path.startsWith('data:')) {
        final filename = path.replaceAll('\\', '/').split('/').last;
        addUnique('assets/sections/$filename');
      }
      if (exactAssetPaths.isEmpty) return fallbackWidget;

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

    if (loadedWidget != null) {
      if (isDark) {
        return Container(
          width: size + 6,
          height: size + 6,
          padding: const EdgeInsets.all(3.0),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(6.0),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.25),
                blurRadius: 4,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: loadedWidget,
        );
      }
      return loadedWidget;
    }

    return fallbackWidget;
  }
}
