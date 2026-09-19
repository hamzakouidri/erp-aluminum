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
    final bool isN245Code = cleanCode == 'N245';
    final bool isN245Path =
        lowerPath
            .replaceAll('\\', '/')
            .split('/')
            .last
            .replaceFirst(RegExp(r'\.(png|jpe?g|jpeg|svg|webp)$'), '')
            .replaceAll(RegExp(r'[\s_-]+'), '') ==
        'n245';
    final bool isAssetReference =
        lowerPath.startsWith('assets/') || lowerPath.startsWith('asset/');
    final String semanticLabel = '$rawCode ${name ?? ''} $path'.toLowerCase();
    final bool isFrappeJoint =
        (semanticLabel.contains('frappe') ||
            semanticLabel.contains('فراب') ||
            semanticLabel.contains('ضرب')) &&
        (semanticLabel.contains('joint') ||
            semanticLabel.contains('جوان') ||
            semanticLabel.contains('gasket'));
    final bool isJointSemantic =
        semanticLabel.contains('joint') ||
        semanticLabel.contains('جوان') ||
        semanticLabel.contains('gasket');
    final bool isCentralJoint =
        !isFrappeJoint &&
        (isN245Code ||
            (isJointSemantic &&
                (semanticLabel.contains('central') ||
                    semanticLabel.contains('سنترال') ||
                    semanticLabel.contains('سنطرال') ||
                    semanticLabel.contains('joint_central'))));
    final bool isBourrageJoint =
        !isFrappeJoint &&
        (semanticLabel.contains('bourrage') ||
            semanticLabel.contains('بوراج') ||
            semanticLabel.contains('joint_bourrage'));
    final bool isScrew =
        semanticLabel.contains('visse') ||
        semanticLabel.contains('screw') ||
        semanticLabel.contains('برغي') ||
        semanticLabel.contains('براغ') ||
        semanticLabel.contains('فيس');
    final bool isSashReinforcement =
        semanticLabel.contains('sash') ||
        semanticLabel.contains('ouvrant') ||
        semanticLabel.contains('battant') ||
        semanticLabel.contains('ظرفة') ||
        semanticLabel.contains('ضلفة') ||
        semanticLabel.contains('ظرفه') ||
        semanticLabel.contains('تدعيم الظ') ||
        semanticLabel.contains('حديد الظ');
    final bool isGeneralReinforcement =
        !isSashReinforcement &&
        (semanticLabel.contains('renfort') ||
            semanticLabel.contains('reinforc') ||
            semanticLabel.contains('حديد الدعم') ||
            semanticLabel.contains('حديد التدعيم') ||
            semanticLabel.contains('تدعيم'));

    Widget fallbackWidget = Icon(
      fallbackIcon ?? Icons.image_not_supported_rounded,
      size: size,
      color: fallbackColor ?? (isDark ? Colors.grey.shade400 : Colors.grey),
    );

    Widget? loadedWidget;

    // Joint Frappe has one canonical image. Catalogue rows may carry an old
    // code or an incorrect image path, so the semantic joint type wins here
    // and every screen displays the same photo.
    if (isFrappeJoint) {
      loadedWidget = Image.asset(
        'assets/sections/joint_frappe.png',
        width: size,
        height: size,
        fit: BoxFit.contain,
        gaplessPlayback: true,
        errorBuilder: (context, error, stackTrace) => fallbackWidget,
      );
    }

    if (loadedWidget == null && isCentralJoint) {
      loadedWidget = SvgPicture.asset(
        'assets/sections/N245.svg',
        width: size,
        height: size,
        fit: BoxFit.contain,
        placeholderBuilder: (context) => fallbackWidget,
      );
    }

    if (loadedWidget == null && isBourrageJoint) {
      loadedWidget = SvgPicture.asset(
        'assets/sections/N52034.svg',
        width: size,
        height: size,
        fit: BoxFit.contain,
        placeholderBuilder: (context) => fallbackWidget,
      );
    }

    // All screw catalogue items share the supplied canonical illustration,
    // regardless of their individual code or legacy image filename.
    if (loadedWidget == null && isScrew) {
      loadedWidget = SvgPicture.asset(
        'assets/sections/vis.svg',
        width: size,
        height: size,
        fit: BoxFit.contain,
        placeholderBuilder: (context) => fallbackWidget,
      );
    }

    // Show the U-channel illustration for general reinforcements. Sash
    // reinforcement is intentionally excluded because it has its own role.
    if (loadedWidget == null && isGeneralReinforcement) {
      loadedWidget = SvgPicture.asset(
        'assets/sections/renfort_u.svg',
        width: size,
        height: size,
        fit: BoxFit.contain,
        placeholderBuilder: (context) => fallbackWidget,
      );
    }

    // 1. إحضار الصورة بناءً على المسار المربوط صراحة للمطع
    // N245 is the central gasket illustration. A legacy section row may have
    // inherited N245.svg as its image_path, but a central montant/profile
    // must never display the gasket image. Ignore that stale path unless the
    // row is actually identified as the N245 gasket above.
    if (loadedWidget == null &&
        path.isNotEmpty &&
        (!isN245Path || isCentralJoint)) {
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
                gaplessPlayback: true,
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
            gaplessPlayback: true,
            errorBuilder: (context, error, stackTrace) => fallbackWidget,
          );
        }
      } else {
        try {
          final file = File(path);
          if (file.existsSync()) {
            final isSvg = file.path.toLowerCase().endsWith('.svg');
            loadedWidget = isSvg
                ? SvgPicture.file(
                    file,
                    width: size,
                    height: size,
                    fit: BoxFit.contain,
                    placeholderBuilder: (context) => fallbackWidget,
                  )
                : Image.file(
                    file,
                    width: size,
                    height: size,
                    fit: BoxFit.contain,
                    gaplessPlayback: true,
                    errorBuilder: (context, error, stackTrace) =>
                        fallbackWidget,
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
        // A stale N245 image path must not override the real image of a
        // montant/ouvrant. N245 is reserved for the central gasket code.
        if (stem.replaceAll(RegExp(r'[\s_-]+'), '') == 'n245' &&
            !isCentralJoint) {
          return;
        }
        const imageAliases = <String, String>{
          'roulette_double': 'roulette.png',
          'roulettes': 'roulette.png',
          'roullette': 'roulette.png',
          'رولات': 'roulette.png',
          'عجلات_المنزلق': 'roulette.png',
          'tasso': 'tasso.png',
          'طاسو': 'tasso.png',
          'الطاسو': 'tasso.png',
          'joint bross': 'joint_brosse.png',
          'joint_bross': 'joint_brosse.png',
          'joint_brosse_sash': 'joint_brosse.png',
          'joint_brosse_shutter': 'joint_brosse.png',
          'joint frappe': 'joint_frappe.png',
          'joint_frappe': 'joint_frappe.png',
          'joint_frappe_sash': 'joint_frappe.png',
          'joint_frappe_frame': 'joint_frappe.png',
          'جوان فراب': 'joint_frappe.png',
          'جوان الضرب': 'joint_frappe.png',
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
          'vis': 'vis.svg',
          'visse': 'vis.svg',
          'براغي': 'vis.svg',
          'فيس': 'vis.svg',
          'renfort': 'renfort_u.svg',
          'reinforcement': 'renfort_u.svg',
          'حديد الدعم': 'renfort_u.svg',
          'تدعيم': 'renfort_u.svg',
          'n245': 'N245.svg',
          'n52034': 'N52034.svg',
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
        final stemWithoutExt = filename.replaceFirst(
          RegExp(r'\.(svg|png|jpe?g|webp)$', caseSensitive: false),
          '',
        );
        final filenames = <String>[
          if (hasExtension) filename,
          '$stemWithoutExt.svg',
          '$stemWithoutExt.png',
          '$stemWithoutExt.jpg',
          '$stemWithoutExt.jpeg',
          '$stemWithoutExt.webp',
        ];
        final cleanStem = stemWithoutExt.replaceAll(' ', '');
        filenames.add('$cleanStem.svg');
        filenames.add('$cleanStem.png');
        if (cleanStem.toUpperCase().startsWith('B90')) {
          final bsStem = cleanStem.replaceFirst(
            RegExp(r'^B90', caseSensitive: false),
            'BS90',
          );
          filenames.add('$bsStem.svg');
          filenames.add('$bsStem.png');
          final bsSpaceStem = stemWithoutExt.replaceFirst(
            RegExp(r'^B90', caseSensitive: false),
            'BS90 ',
          );
          filenames.add('$bsSpaceStem.svg');
          filenames.add('$bsSpaceStem.png');
        } else if (cleanStem.toUpperCase().startsWith('BS90')) {
          final bStem = cleanStem.replaceFirst(
            RegExp(r'^BS90', caseSensitive: false),
            'B90',
          );
          filenames.add('$bStem.svg');
          filenames.add('$bStem.png');
          final bSpaceStem = stemWithoutExt.replaceFirst(
            RegExp(r'^BS90\s*', caseSensitive: false),
            'B90 ',
          );
          filenames.add('$bSpaceStem.svg');
          filenames.add('$bSpaceStem.png');
        }
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
        if (!isN245Path || isCentralJoint) {
          addUnique(
            lowerPath.startsWith('asset/')
                ? 'assets/${path.substring(6)}'
                : path,
          );
        }
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

      Widget? buildExactChain(int index) {
        if (index >= exactAssetPaths.length) {
          return null;
        }

        final assetPath = exactAssetPaths[index];
        final isSvg = assetPath.toLowerCase().endsWith('.svg');

        // On desktop / local file system, first check if the file exists directly on disk
        if (!kIsWeb) {
          final filename = assetPath.split('/').last;
          final candidateFiles = [
            File(assetPath),
            File('assets/sections/$filename'),
            File('assets/images/$filename'),
            File(
              'C:/Users/hp/Desktop/erp-alum/erp-aluminum-main/assets/sections/$filename',
            ),
            File('C:/Users/hp/Desktop/LISTE DE PRIX BS90/$filename'),
          ];
          try {
            final exeDir = File(Platform.resolvedExecutable).parent.path;
            candidateFiles.add(
              File('$exeDir/data/flutter_assets/assets/sections/$filename'),
            );
          } catch (_) {}
          for (final f in candidateFiles) {
            try {
              if (f.existsSync()) {
                return isSvg
                    ? SvgPicture.file(
                        f,
                        width: size,
                        height: size,
                        fit: BoxFit.contain,
                        placeholderBuilder: (context) => fallbackWidget,
                      )
                    : Image.file(
                        f,
                        width: size,
                        height: size,
                        fit: BoxFit.contain,
                        gaplessPlayback: true,
                        errorBuilder: (context, error, stackTrace) =>
                            buildExactChain(index + 1) ?? fallbackWidget,
                      );
              }
            } catch (_) {}
          }
        }

        if (isSvg) {
          return SvgPicture.asset(
            assetPath,
            width: size,
            height: size,
            fit: BoxFit.contain,
            placeholderBuilder: (context) => fallbackWidget,
            errorBuilder: (context, error, stackTrace) {
              return buildExactChain(index + 1) ?? fallbackWidget;
            },
          );
        } else {
          return Image.asset(
            assetPath,
            width: size,
            height: size,
            fit: BoxFit.contain,
            gaplessPlayback: true,
            errorBuilder: (context, error, stackTrace) {
              return buildExactChain(index + 1) ?? fallbackWidget;
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
                color: Colors.black.withValues(alpha: 0.25),
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
