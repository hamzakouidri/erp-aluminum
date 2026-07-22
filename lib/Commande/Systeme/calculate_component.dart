// Force compile sync trigger 4
import 'package:database_data/Commande/Systeme/model.dart';
import 'dart:math' as math;

class BomItem {
  final String  category;
  final String  originalName;
  final String? profileCode;
  final String  name;
  final String? imagePath;
  final String? colorName;
  final double? length;
  final double? glassHeight;
  final double  quantity;
  final String  unit;
  final double  unitPrice;
  final bool    isMissing;

  final bool    isInteractive;
  final bool    isActive;
  final String? exclusionGroup;
  final List<double>? pieces;
  final String? cuttingList;
  final String? kitGroupName; // اسم Kit التابع له (مثال: System OB)
  final double? exactQuantity;

  BomItem({
    required this.category,
    required this.originalName,
    this.profileCode,
    required String name,
    this.imagePath,
    this.colorName,
    this.length,
    this.glassHeight,
    required this.quantity,
    required this.unit,
    required this.unitPrice,
    this.isMissing = false,
    this.isInteractive = false,
    this.isActive = true,
    this.exclusionGroup,
    this.pieces,
    this.cuttingList,
    this.kitGroupName,
    this.exactQuantity,
  }) : this.name = name.replaceAll(RegExp(r'\s*\(\s*جودة[^)]*\)'), '').trim();

  double get exactTotal {
    if (!isActive) return 0.0;
    if (category == 'glass' && length != null && glassHeight != null) {
      double w = length! / 1000.0;
      double h = glassHeight! / 1000.0;
      return (exactQuantity ?? quantity) * w * h * unitPrice;
    }
    return (exactQuantity ?? quantity) * unitPrice;
  }

  double get total {
    if (!isActive) return 0.0;
    if (category == 'glass' && length != null && glassHeight != null) {
      double w = length! / 1000.0;
      double h = glassHeight! / 1000.0;
      return quantity * w * h * unitPrice;
    }
    return quantity * unitPrice;
  }

  String getLocalizedName(String lang) {
    final original = originalName;
    if (lang == 'fr') {
      if (original == 'قائم جانبي معزز (Sash Lateral Renforcé)') return 'Sash Latéral Renforcé';
      if (original == 'قائم وسطي معزز (Sash Central Renforcé)') return 'Sash Central Renforcé';
      if (original == 'حديد التقسيم (Renfort Mullion)') return 'Renfort Traverse / Montant';
      if (original == 'حديد الباطمو (Renfort Batmo)') return 'Renfort Battement';
      if (original == 'الزجاج') return 'Vitrage';
      if (original.contains('إطار') || original.contains('Frame') || original.contains('Cadre') || original.contains('Dormant')) {
        return original.replaceAll('إطار', 'Dormant').replaceAll('Frame', 'Dormant').replaceAll('Cadre', 'Dormant');
      }
      if (original.contains('الظلفة') || original.contains('Sash') || original.contains('Ouvrant')) {
        return original.replaceAll('الظلفة', 'Ouvrant').replaceAll('Sash', 'Ouvrant');
      }
      if (original.contains('عرضي') || original.contains('Traverse')) {
        return original.replaceAll('عرضي', 'Traverse');
      }
      if (original.contains('قائم جانبي') || original.contains('Sash Lateral') || original.contains('Lateral')) {
        return original.replaceAll('قائم جانبي', 'Sash Latéral').replaceAll('Sash Lateral', 'Sash Latéral');
      }
      if (original.contains('قائم وسطي') || original.contains('Sash Central') || original.contains('Central')) {
        return original.replaceAll('قائم وسطي', 'Sash Central').replaceAll('Sash Central', 'Sash Central');
      }
      if (original.contains('الشيكان') || original.contains('Chicane')) {
        return original.replaceAll('الشيكان', 'Chicane');
      }
      if (original.contains('الري') || original.contains('Rail')) {
        return original.replaceAll('الري', 'Rail');
      }
      if (original.contains('سكة الظلفة') || original.contains('Sash Traverse')) {
        return original.replaceAll('سكة الظلفة', 'Traverse Ouvrant').replaceAll('Sash Traverse', 'Traverse Ouvrant');
      }
      if (original.contains('بلانت الظلفة') || original.contains('Plinthe Sash')) {
        return original.replaceAll('بلانت الظلفة', 'Plinthe Ouvrant').replaceAll('Plinthe Sash', 'Plinthe Ouvrant');
      }
      if (original.contains('الباتمو') || original.contains('Batmo')) {
        return original.replaceAll('الباتمو', 'Meneau');
      }
      if (original.contains('بوشون باتمو') || original.contains('Bouchon Batmo')) {
        return original.replaceAll('بوشون باتمو', 'Bouchon Meneau');
      }
      if (original.contains('حديد الإطار') || original.contains('Renfort Frame')) {
        return original.replaceAll('حديد الإطار', 'Renfort Dormant').replaceAll('Renfort Frame', 'Renfort Dormant');
      }
      if (original.contains('حديد الظلفة') || original.contains('Renfort Sash')) {
        return original.replaceAll('حديد الظلفة', 'Renfort Ouvrant').replaceAll('Renfort Sash', 'Renfort Ouvrant');
      }
      if (original.contains('حديد الظلفة الخاص بالمفاصل')) {
        return 'Renfort Ouvrant (Paumelles)';
      }
      if (original.contains('براغي حديد الدعم')) {
        return 'Vis pour Renfort';
      }
      if (original.contains('براغي الباتمو')) {
        return 'Vis Meneau';
      }
      if (original.contains('براغي بوشون باتمو')) {
        return 'Vis Bouchon Meneau';
      }
      if (original.contains('براغي الإكسسوارات')) {
        return 'Vis Accessoires';
      }
      if (original == 'الفيرو (Verrou)') return 'Verrou';
      if (original == 'Verrou Central') return 'Verrou Central';
      if (original == 'System OB') return 'Système OB';
      if (original == 'Demi System OB') return 'Demi Système OB';
      if (original.contains('إسبانيوليت') || original.contains('Espagnolette')) return 'Espagnolette';
      if (original == 'المقبض (Handle)') return 'Poignée Fenêtre';
      if (original == 'مقبض الباب (Poignée Porte à Clé)') return 'Poignée Porte à Clé';
      if (original == 'قفل الباب (Serrure)') return 'Serrure';
      if (original == 'الأسطوانة (Canon)') return 'Canon';
      if (original == 'قاش بورت (Gache Porte)') return 'Gâche Porte';
      if (original == 'المفاصل (Hinges)') return 'Paumelles';
      if (original == 'عجلات المنزلق (Roulettes)') return 'Roulettes';
      if (original == 'اسبانيولات المنزلق (Espagnolette)') return 'Espagnolette Coulissant';
      if (original == 'كاش كوليسون (Gache coulissant)') return 'Gâche Coulissante';
      if (original == 'Gâche coulissant TPR') return 'Gâche Coulissante TPR';
      if (original == 'كريمون (Cremone)') return 'Crémone';
      if (original == 'بوشون بارك لوز (Bouchon Parclose)') return 'Bouchon Parclose';
      if (original == 'قفل نقطة') return 'Serrure à point';
    } else if (lang == 'en') {
      if (original == 'قائم جانبي معزز (Sash Lateral Renforcé)') return 'Sash Lateral Reinforced';
      if (original == 'قائم وسطي معزز (Sash Central Renforcé)') return 'Sash Central Reinforced';
      if (original == 'حديد التقسيم (Renfort Mullion)') return 'Renfort Mullion';
      if (original == 'حديد الباطمو (Renfort Batmo)') return 'Renfort Batmo';
      if (original == 'الزجاج') return 'Glass';
      if (original.contains('إطار') || original.contains('Frame') || original.contains('Cadre') || original.contains('Dormant')) {
        return original.replaceAll('إطار', 'Frame').replaceAll('Cadre', 'Frame').replaceAll('Dormant', 'Frame');
      }
      if (original.contains('الظلفة') || original.contains('Sash') || original.contains('Ouvrant')) {
        return original.replaceAll('الظلفة', 'Sash').replaceAll('Ouvrant', 'Sash');
      }
      if (original.contains('عرضي') || original.contains('Traverse')) {
        return original.replaceAll('عرضي', 'Traverse');
      }
      if (original.contains('قائم جانبي') || original.contains('Sash Lateral') || original.contains('Lateral')) {
        return original.replaceAll('قائم جانبي', 'Sash Lateral');
      }
      if (original.contains('قائم وسطي') || original.contains('Sash Central') || original.contains('Central')) {
        return original.replaceAll('قائم وسطي', 'Sash Central');
      }
      if (original.contains('الشيكان') || original.contains('Chicane')) {
        return 'Chicane';
      }
      if (original.contains('الري') || original.contains('Rail')) {
        return 'Rail';
      }
      if (original.contains('سكة الظلفة') || original.contains('Sash Traverse')) {
        return 'Sash Traverse';
      }
      if (original.contains('بلانت الظلفة') || original.contains('Plinthe Sash')) {
        return 'Plinthe Sash';
      }
      if (original.contains('الباتمو') || original.contains('Batmo')) {
        return 'Batmo';
      }
      if (original.contains('بوشون باتمو') || original.contains('Bouchon Batmo')) {
        return 'Bouchon Batmo';
      }
      if (original.contains('حديد الإطار') || original.contains('Renfort Frame')) {
        return 'Renfort Frame';
      }
      if (original.contains('حديد الظلفة') || original.contains('Renfort Sash')) {
        return 'Renfort Sash';
      }
      if (original.contains('حديد الظلفة الخاص بالمفاصل')) {
        return 'Renfort Sash (Hinges)';
      }
      if (original.contains('براغي حديد الدعم')) {
        return 'Renfort Screws';
      }
      if (original.contains('براغي الباتمو')) {
        return 'Batmo Screws';
      }
      if (original.contains('براغي بوشون باتمو')) {
        return 'Bouchon Batmo Screws';
      }
      if (original.contains('براغي الإكسسوارات')) {
        return 'Accessory Screws';
      }
      if (original == 'الفيرو (Verrou)') return 'Verrou';
      if (original == 'Verrou Central') return 'Verrou Central';
      if (original == 'System OB') return 'System OB';
      if (original == 'Demi System OB') return 'Demi System OB';
      if (original.contains('إسبانيوليت') || original.contains('Espagnolette')) return 'Espagnolette';
      if (original == 'المقبض (Handle)') return 'Window Handle';
      if (original == 'مقبض الباب (Poignée Porte à Clé)') return 'Door Handle';
      if (original == 'قفل الباب (Serrure)') return 'Serrure (Lock)';
      if (original == 'الأسطوانة (Canon)') return 'Cylinder (Canon)';
      if (original == 'قاش بورت (Gache Porte)') return 'Door Strike Plate';
      if (original == 'المفاصل (Hinges)') return 'Hinges';
      if (original == 'عجلات المنزلق (Roulettes)') return 'Roulettes';
      if (original == 'اسبانيولات المنزلق (Espagnolette)') return 'Espagnolette';
      if (original == 'كاش كوليسون (Gache coulissant)') return 'Strike Plate';
      if (original == 'Gâche coulissant TPR') return 'Strike Plate TPR';
      if (original == 'كريمون (Cremone)') return 'Cremone';
      if (original == 'بوشون بارك لوز (Bouchon Parclose)') return 'Bouchon Parclose';
      if (original == 'قفل نقطة') return 'Point lock';
    }
    return originalName;
  }

  BomItem copyWith({
    bool? isActive,
    String? name,
    String? kitGroupName,
    double? qty,
    String? profileCode,
    String? imagePath,
  }) {
    return BomItem(
      category: category,
      originalName: originalName,
      profileCode: profileCode ?? this.profileCode,
      name: name ?? this.name,
      imagePath: imagePath ?? this.imagePath,
      colorName: colorName,
      length: length,
      glassHeight: glassHeight,
      quantity: qty ?? this.quantity,
      unit: unit,
      unitPrice: unitPrice,
      isMissing: isMissing,
      isInteractive: isInteractive,
      isActive: isActive ?? this.isActive,
      exclusionGroup: exclusionGroup,
      pieces: pieces,
      cuttingList: cuttingList,
      kitGroupName: kitGroupName ?? this.kitGroupName,
      exactQuantity: exactQuantity,
    );
  }
}

class ComponentCalculator {
  static Map<String, dynamic> optimizeCutting({
    required List<double> pieces,
    required double barLength,
    double bladeWaste = 0.004, // 4mm per cut
  }) {
    if (pieces.isEmpty) {
      return {'exactBars': 0.0, 'optimizedBars': 0};
    }

    // First-Fit Decreasing (FFD) Algorithm for 1D bin packing
    List<double> sortedPieces = List.from(pieces)
      ..sort((a, b) => b.compareTo(a));

    double smallestPiece = sortedPieces.isEmpty ? 0.0 : sortedPieces.last;

    List<double> bins = []; // Remaining space in each bin
    List<double> binUsed = []; // Total length of pieces cut in each bin

    for (double piece in sortedPieces) {
      if (piece <= 0) continue;
      double pieceWithWaste = piece + bladeWaste;
      bool placed = false;
      for (int i = 0; i < bins.length; i++) {
        if (bins[i] >= piece) {
          bins[i] -= pieceWithWaste;
          binUsed[i] += piece;
          placed = true;
          break;
        }
      }
      if (!placed) {
        bins.add(barLength - pieceWithWaste);
        binUsed.add(piece);
      }
    }

    double exactBars = 0.0;
    for (int i = 0; i < bins.length; i++) {
      double leftover = bins[i];
      if (leftover < smallestPiece) {
        // Leftover is too small to be used for any remaining pieces, count as 1.0 bar consumed
        exactBars += 1.0;
      } else {
        // Leftover is large enough to potentially be used, so only count fraction of bar used
        exactBars += binUsed[i] / barLength;
      }
    }

    return {
      'exactBars': exactBars,
      'optimizedBars': bins.isEmpty ? 0 : bins.length,
    };
  }

  static List<BomItem> generateBom(
    WindowModel window,
    Map<String, bool> activeVariants, {
    Map<String, List<Map<String, dynamic>>> kitBundleData = const {},
    Map<String, bool> kitPerLeafMap = const {},
  }) {
    Map<String, dynamic>? getSlidingFrameSection() {
      if (window.slidingFrameOverride != null) return window.slidingFrameOverride;
      final series = window.activeSlidingSeries ?? window.activeSeries;
      if (series == null) return null;
      var slidingFrames = series.sections.where((s) {
        final name = s.name.toLowerCase();
        final type = s.type.toLowerCase();
        return (name.contains('coulissant') || name.contains('منزلق') || name.contains('sliding') ||
                type.contains('coulissant') || type.contains('sliding')) &&
               (type.contains('frame') || type.contains('cadre') || type.contains('إطار'));
      }).toList();
      if (slidingFrames.isNotEmpty) return slidingFrames.first.toMap();
      
      var anyFrames = series.sections.where((s) {
        final type = s.type.toLowerCase();
        return type.contains('frame') || type.contains('cadre') || type.contains('إطار');
      }).toList();
      if (anyFrames.isNotEmpty) return anyFrames.first.toMap();
      return null;
    }

    String? getKitKey(String baseName) {
      final List<String> aliases;
      if (baseName == 'System OB') {
        aliases = [
          'system ob',
          'system_ob',
          'systemob',
          'system kit ob',
          'systemkitob',
          'kit ob',
          'kitob',
          'kit system ob',
          'kitsystemob',
          'ob',
          'ob_group',
        ];
      } else if (baseName == 'Demi System OB') {
        aliases = [
          'demi system ob',
          'demi_system_ob',
          'system_dim_ob',
          'system dim ob',
          'systemdimob',
          'demisystemob',
          'demi ob',
          'demiob',
          'demi kit ob',
          'demikitob',
          'system demi ob',
          'systemdemiob',
          'kit demi ob',
          'kitdemiob',
          'kit demi system ob',
          'kitdemisystemob',
        ];
      } else if (baseName == 'Verrou Central') {
        aliases = [
          'verrou central',
          'verrou_central',
          'vero_central',
          'vero central',
          'verroucentral',
          'verocentral',
          'kit verrou central',
          'kitverroucentral',
          'kit verrou',
          'kitverrou',
          'verrou',
          'verro',
        ];
      } else {
        aliases = [baseName.toLowerCase()];
      }

      // 1. Try exact/alias normalized match
      for (final key in kitBundleData.keys) {
        final normalizedKey = key.toLowerCase().replaceAll(
          RegExp(r'[\s_-]'),
          '',
        );
        for (final alias in aliases) {
          final normalizedAlias = alias.toLowerCase().replaceAll(
            RegExp(r'[\s_-]'),
            '',
          );
          if (normalizedKey == normalizedAlias) {
            return key;
          }
        }
      }

      // 2. Fallback: Flexible keyword containment match
      final normalizedBase = baseName.toLowerCase().replaceAll(
        RegExp(r'[\s_-]'),
        '',
      );
      for (final key in kitBundleData.keys) {
        final normalizedKey = key.toLowerCase().replaceAll(
          RegExp(r'[\s_-]'),
          '',
        );
        if (normalizedBase == 'systemob') {
          if (normalizedKey.contains('ob') &&
              !normalizedKey.contains('demi') &&
              !normalizedKey.contains('dim')) {
            return key;
          }
        } else if (normalizedBase == 'demisystemob') {
          if (normalizedKey.contains('demi') || normalizedKey.contains('dim')) {
            return key;
          }
        } else if (normalizedBase == 'verroucentral') {
          if (normalizedKey.contains('verrou') ||
              normalizedKey.contains('vero') ||
              (normalizedKey.contains('central') &&
                  !normalizedKey.contains('system') &&
                  !normalizedKey.contains('ob'))) {
            return key;
          }
        }
      }

      return null;
    }

    BomItem createProfile(
      String originalName,
      String? color, {
      String unit = 'قطاع',
      double defaultPrice = 0,
      double qty = 0,
      double? length,
      List<double>? pieces,
      Map<String, dynamic>? overrideMap,
    }) {
      List<double>? multipliedPieces;
      if (pieces != null && pieces.isNotEmpty) {
        multipliedPieces = [];
        for (int q = 0; q < window.quantity; q++) {
          multipliedPieces.addAll(pieces);
        }
      }
      return _createProfile(
        window.componentOverrides,
        originalName,
        color,
        unit: unit,
        defaultPrice: defaultPrice,
        qty: qty * window.quantity,
        length: length,
        pieces: multipliedPieces,
        overrideMap: overrideMap,
      );
    }

    BomItem createAccessory(
      String originalName, {
      bool isActive = true,
      String? color,
      int qty = 0,
    }) => _createAccessory(
      window.componentOverrides,
      originalName,
      isActive: isActive,
      color: color,
      qty: qty * window.quantity,
    );
    BomItem createInteractiveAccessory(
      String originalName,
      String group, {
      bool isActive = false,
      double qty = 1,
      String? kitGroupName,
      String category = 'accessory',
    }) => _createInteractiveAccessory(
      window.componentOverrides,
      originalName,
      group,
      isActive: isActive,
      qty: qty * window.quantity,
      kitGroupName: kitGroupName,
      category: category,
    );
    BomItem createShutter(
      String originalName, {
      String? color,
      double qty = 0,
      String unit = 'حبة',
      List<double>? pieces,
      String? kitGroupName,
    }) {
      List<double>? multipliedPieces;
      if (pieces != null && pieces.isNotEmpty) {
        multipliedPieces = [];
        for (int q = 0; q < window.quantity; q++) {
          multipliedPieces.addAll(pieces);
        }
      }
      return _createShutter(
        window.componentOverrides,
        originalName,
        color: color,
        qty: qty * window.quantity,
        unit: unit,
        pieces: multipliedPieces,
        kitGroupName: kitGroupName,
        windowWidth: window.width.toDouble(),
        windowHeight: window.height.toDouble(),
        windowQuantity: window.quantity,
      );
    }

    BomItem createJoint(
      String originalName, {
      String? color,
      double qty = 0,
      String unit = 'بارة',
    }) => _createJoint(
      window.componentOverrides,
      originalName,
      color: color,
      qty: qty * window.quantity,
      unit: unit,
    );

    BomItem createOther(
      String originalName, {
      bool isActive = true,
      String? color,
      int qty = 0,
    }) => _createOther(
      window.componentOverrides,
      originalName,
      isActive: isActive,
      color: color,
      qty: qty * window.quantity,
    );

    List<BomItem> items = [];

    int doubleSashCount = window.zones
        .where((z) => z.content == ZoneContent.doubleSash)
        .length;
    int singleSashCount = window.zones
        .where((z) => z.content == ZoneContent.singleSash)
        .length;
    int slidingSashCount = window.zones
        .where((z) => z.content == ZoneContent.slidingSash)
        .length;

    bool hasDoubleSash = doubleSashCount > 0;
    bool hasSingleSash = singleSashCount > 0;
    bool hasSlidingSash = slidingSashCount > 0;
    bool hasShutter = window.hasShutter;

    // تحديد نوع الغطاء الجانبي:
    // مدمج: مقطع الإطار نفسه فيه couvreJointWidth > 0
    // غير مدمج: hasSideCovers = true لكن الإطار بدون couvreJoint مدمج
    bool frameHasIntegratedSideCover = window.isIntegratedFrame && window.isSideCoverAllowed;
    bool hasIntegratedSideCover =
        window.hasSideCovers && window.isSideCoverAllowed && frameHasIntegratedSideCover;
    bool hasNonIntegratedSideCover =
        window.hasSideCovers && window.isSideCoverAllowed && !hasIntegratedSideCover;

    // حساب netHeight: الارتفاع الصافي قبل حساب الإطار
    double netHeight;
    if (hasIntegratedSideCover) {
      // غطاء مدمج: لا نخصم صندوق الستارة
      netHeight = window.height;
    } else {
      // بدون غطاء مدمج: نخصم صندوق الستارة إذا وُجد
      netHeight = (window.hasShutter && !window.isCaissonTunnel)
          ? window.height - window.shutterBoxHeight
          : window.height;
    }

    String colorName = window.selectedDbColor != null
        ? window.selectedDbColor!['name']
        : window.frameColor.toString().split('.').last;

    int totalHandles = 0;
    int octoHandles = 0;
    int pointLocks = 0;
    int keyHandles = 0;
    int condamnationHandles = 0;
    int normalDoorHandles = 0;
    int marechal125Handles = 0;
    int marechal2mHandles = 0;
    int rollerLocks = 0;
    int pvcHandlesOnAlu = 0;
    int keyLocks = 0;
    int condamnationLocks = 0;
    int doorCanons = 0;
    int gachePortes = 0;
    int totalCompas = 0;
    int totalHinges = 0;
    int windowSingleSashCount = 0;
    int windowDoubleSashCount = 0;
    int doorSingleSashCount = 0;
    int doorDoubleSashCount = 0;

    List<double> slidingChicanePieces = [];
    List<double> slidingRailPieces = [];
    int slidingTotalRoulettes = 0;
    int slidingTotalEspagnolettes = 0;
    int slidingTotalHandles = 0;
    int slidingTotalGacheCoulissant = 0;
    double slidingTotalJointBrosse = 0.0;
    double pvcJointBrosseSum = 0.0;
    Map<String, double> slidingGlassJoints = {};

    for (var zone in window.zones) {
      if (zone.content == ZoneContent.singleSash ||
          zone.content == ZoneContent.doubleSash) {
        int sashes = (zone.content == ZoneContent.doubleSash) ? 2 : 1;
        final seriesName = window.activeSeries?.name.toLowerCase() ?? '';
        final isTPR = seriesName.contains('tpr');
        final isThinSash = !zone.isSash105;
        final hasAllowedLock = (zone.lockType == LockType.clef ||
                zone.lockType == LockType.condamnation ||
                zone.lockType == LockType.rouleau ||
                zone.lockType == LockType.rouleau2000) &&
            !(isTPR && isThinSash);

        final bool isDoor = (zone.isSash105 || hasAllowedLock) &&
            zone.lockType != LockType.none &&
            zone.useOctoHandle != true &&
            zone.usePvcHandleOnAlu != true;
        if (isDoor) {
          if (zone.content == ZoneContent.singleSash) {
            doorSingleSashCount++;
          } else {
            doorDoubleSashCount++;
          }
          final bool isCondamnation = zone.lockType == LockType.condamnation && !(isTPR && isThinSash);
          final bool isMarechal125 = zone.lockType == LockType.rouleau && !(isTPR && isThinSash);
          final bool isMarechal2m = zone.lockType == LockType.rouleau2000 && !(isTPR && isThinSash);
          
          if (isMarechal125) {
            marechal125Handles += 1;
            rollerLocks += 1;
          } else if (isMarechal2m) {
            marechal2mHandles += 1;
            rollerLocks += 1;
          } else if (isCondamnation) {
            condamnationHandles += 1;
            condamnationLocks += 1;
          } else if (zone.lockType == LockType.clef) {
            keyHandles += 1;
            keyLocks += 1;
            doorCanons += 1;
          } else {
            normalDoorHandles += 1;
          }
          gachePortes += 1;
        } else {
          if (zone.content == ZoneContent.singleSash) {
            windowSingleSashCount++;
          } else {
            windowDoubleSashCount++;
          }
          
          if (zone.content == ZoneContent.doubleSash) {
            if (zone.usePvcHandleOnAlu) {
              pvcHandlesOnAlu += 2;
            } else if (zone.useOctoHandle) {
              octoHandles += 2;
            } else {
              totalHandles += 2;
            }
          } else {
            if (zone.lockType == LockType.point) {
              pointLocks += 1;
            } else if (zone.usePvcHandleOnAlu) {
              pvcHandlesOnAlu += 1;
            } else if (zone.useOctoHandle) {
              octoHandles += 1;
            } else {
              totalHandles += 1;
            }
          }

          final isVerticalOpen = zone.openDirection == OpenDirection.top || zone.openDirection == OpenDirection.bottom;
          final isNotPano = zone.glass.structure != GlassStructure.closed;
          if (zone.useOctoHandle && isVerticalOpen && isNotPano) {
            totalCompas += (zone.content == ZoneContent.doubleSash) ? 2 : 1;
          }
        }

        int hingesPerSash = (zone.boundary.height > 2100)
            ? 4
            : (zone.boundary.height > 1000)
            ? 3
            : 2;

        if (zone.glass.structure == GlassStructure.double) {
          hingesPerSash += 1;
        }

        int sashesWithHinges = sashes;
        if (window.useSystemOB || window.useDemiOB) {
          if (zone.content == ZoneContent.singleSash) {
            sashesWithHinges = 0;
          } else if (zone.content == ZoneContent.doubleSash) {
            sashesWithHinges = 1;
          }
        }
        totalHinges += (hingesPerSash * sashesWithHinges);

        // Check for nested sashes in this zone
        final allCellKeys = <String>{};
        allCellKeys.addAll(
          zone.cellIsSash.keys.where((k) => zone.cellIsSash[k] == true),
        );
        allCellKeys.addAll(
          zone.cellIsDoubleSash.keys.where(
            (k) => zone.cellIsDoubleSash[k] == true,
          ),
        );

        for (var cellKey in allCellKeys) {
          int cellSashes = 0;
          if (zone.cellIsSash[cellKey] == true) {
            cellSashes = 1;
          } else if (zone.cellIsDoubleSash[cellKey] == true) {
            cellSashes = 2;
          }

          if (cellSashes > 0) {
            totalHandles += 1;
            totalHinges +=
                (2 * cellSashes); // standard 2 hinges per nested sash
          }
        }
      }
    }

    final bool useCremone = !window.isPVC && window.systemMode != 'sliding' && window.hasBottomFrame;
    int cremoneQty = 0;
    if (useCremone) {
      cremoneQty = totalHandles + keyHandles + condamnationHandles;
      totalHandles = 0;
      keyHandles = 0;
      condamnationHandles = 0;
      keyLocks = 0;
      condamnationLocks = 0;
      doorCanons = 0;
      gachePortes = 0;
    }

    // --- إضافة هذا المنطق داخل دالة generateBom ---

    // 1. تحديد هل الإطار من نوع 103
    bool isFrame103 =
        (window.frameOverride != null) &&
        (window.frameOverride!['name'].toString().contains('Cadre cj') ||
            window.frameOverride!['code'].toString().contains('103'));



    double rawEspaLen = hasShutter ? window.height - 350 : window.height - 200;
    double espaLength = 300;
    if (rawEspaLen >= 400) {
      int multiples = ((rawEspaLen - 400) / 200).floor();
      espaLength = 400 + (multiples * 200).toDouble();
    }
    if (espaLength > 1800) espaLength = 1800;

    int gacheQtyPerDoubleSash = 2;
    if (espaLength > 1400) {
      gacheQtyPerDoubleSash = 4;
    } else if (espaLength >= 1000) {
      gacheQtyPerDoubleSash = 3;
    }

    // --- 1. البروفيلات (Profiles) ---
    // ===== دالة مساعدة: تفجير مركبات Kit بناءً على قياسات الضلفة =====
    List<BomItem> expandKitBundle(
      String kitName,
      List<Map<String, dynamic>> kitItems, {
      double leafHeightMm = 0,
      double leafWidthMm = 0,
      bool isActive = true,
      int leafCount = 1,
      String category = 'accessory',
      String? variantValue,
    }) {
      final result = <BomItem>[];
      for (final item in kitItems) {
        final mode = item['qty_mode'] as String? ?? 'fixed';
        final dimension = item['dimension'] as String?;
        final unit = item['unit'] as String? ?? 'قطعة';
        final ranges =
            (item['ranges'] as List?)?.cast<Map<String, dynamic>>() ?? [];
        final variants =
            (item['variants'] as List?)?.cast<Map<String, dynamic>>() ?? [];

        if (mode == 'fixed') {
          final qty = ((item['base_qty'] as num?)?.toDouble() ?? 1) * leafCount;
          result.add(
            BomItem(
              category: category,
              originalName: '${kitName}_${item['component_type']}',
              name: item['component_type'] as String? ?? '',
              quantity: qty,
              unit: unit,
              unitPrice: (item['price'] as num?)?.toDouble() ?? 0.0,
              isActive: isActive,
              kitGroupName: kitName,
            ),
          );
        } else if (mode == 'by_range' && ranges.isNotEmpty) {
          final isHeight = dimension == 'leaf_height' || dimension == 'height';
          final dimValue = isHeight ? leafHeightMm : leafWidthMm;

          // Sort ranges by max_mm ascending so we pick the smallest matching range
          final sortedRanges = List<Map<String, dynamic>>.from(ranges);
          sortedRanges.sort((a, b) {
            final aMax = (a['max_mm'] as num?)?.toDouble() ?? double.infinity;
            final bMax = (b['max_mm'] as num?)?.toDouble() ?? double.infinity;
            return aMax.compareTo(bMax);
          });

          Map<String, dynamic>? matchedRange;
          for (final r in sortedRanges) {
            final mn = (r['min_mm'] as num?)?.toDouble() ?? 0;
            final mx = (r['max_mm'] as num?)?.toDouble() ?? double.infinity;
            // The range matches if dimValue falls within [mn, mx)
            if (dimValue >= mn && dimValue <= mx) {
              matchedRange = r;
              break;
            }
          }
          if (matchedRange != null) {
            final qty =
                ((matchedRange['qty'] as num?)?.toDouble() ?? 1) * leafCount;
            result.add(
              BomItem(
                category: category,
                originalName: '${kitName}_${matchedRange['product_name']}',
                name:
                    matchedRange['product_name'] as String? ??
                    item['component_type'] as String? ??
                    '',
                quantity: qty,
                unit: unit,
                unitPrice: (matchedRange['price'] as num?)?.toDouble() ?? 0,
                isActive: isActive,
                isMissing: false,
                kitGroupName: kitName,
              ),
            );
          } else {
            // لا يوجد نطاق مطابق - أضف كعنصر مفقود للتنبيه
            result.add(
              BomItem(
                category: category,
                originalName: '${kitName}_${item['component_type']}_missing',
                name: '⚠ ${item['component_type']} (قياس خارج النطاق)',
                quantity: 0,
                unit: unit,
                unitPrice: 0,
                isActive: isActive,
                isMissing: true,
                kitGroupName: kitName,
              ),
            );
          }
        } else if (mode == 'by_variant' && variants.isNotEmpty) {
          Map<String, dynamic>? matchedVariant;
          if (variantValue != null) {
            for (final v in variants) {
              if (v['ouvrant_type'] == variantValue) {
                matchedVariant = v;
                break;
              }
            }
          }
          matchedVariant ??= variants.first;

          final qty =
              ((matchedVariant['qty'] as num?)?.toDouble() ?? 1) * leafCount;
          result.add(
            BomItem(
              category: category,
              originalName: '${kitName}_${matchedVariant['product_name']}',
              name: matchedVariant['product_name'] as String? ?? '',
              quantity: qty,
              unit: unit,
              unitPrice: (matchedVariant['price'] as num?)?.toDouble() ?? 0,
              isActive: isActive,
              kitGroupName: kitName,
            ),
          );
        }
      }
      return result;
    }

    final double weldVal = window.isPVC ? 5.0 : 0.0;
    final double noBottomWeldVal = window.isPVC ? 3.0 : 0.0;

    double frameWidth;
    double frameNetHeight;

    if (hasIntegratedSideCover) {
      // ======= حالة 1: إطار بغطاء مدمج =======
      double sideCoverVisibleWidth = window.sideCoverWidth;
      // العرض: نضيف العرض الظاهر مرتين (لليمين واليسار) + تلحيم
      frameWidth = window.width + (2 * sideCoverVisibleWidth) + weldVal;

      // الارتفاع: نضيف العرض الظاهر مرتين (للأعلى والأسفل) إذا كان هناك إطار سفلي، أو مرة واحدة (للأعلى) إذا لم يكن هناك إطار سفلي + تلحيم
      if (window.hasBottomFrame) {
        frameNetHeight = netHeight + (2 * sideCoverVisibleWidth) + weldVal;
      } else {
        frameNetHeight = netHeight + sideCoverVisibleWidth + noBottomWeldVal;
      }
    } else if (hasNonIntegratedSideCover) {
      // ======= حالة 2: إطار بدون غطاء مدمج (غطاء منفصل) =======
      // نخصم سُمك الـ couvre-joint من العرض والارتفاع + نضيف 5 مم تلحيم
      double couvreJointThickness =
          window.selectedSideCover?.couvreJointThickness ?? 0.0;

      // العرض: نخصم السُمك من اليمين واليسار + تلحيم
      frameWidth = window.width - (couvreJointThickness * 2) + weldVal;

      // الارتفاع: نخصم السُمك (مع احترام hasBottomFrame) + تلحيم
      // netHeight = الارتفاع الكامل - الصندوق (إذا shutter) — تم حسابه أعلاه
      frameNetHeight =
          netHeight -
          couvreJointThickness // خصم السُمك من الأعلى دائماً
          -
          (window.hasBottomFrame
              ? couvreJointThickness
              : 0.0) // خصم من الأسفل فقط إذا hasBottomFrame
          +
          weldVal; // تلحيم
    } else {
      // ======= حالة 3: بدون غطاء جانبي =======
      frameWidth = window.width + weldVal;
      frameNetHeight = netHeight + (window.hasBottomFrame ? weldVal : noBottomWeldVal);
    }

    final String sName = window.activeSlidingSeries?.name.toLowerCase() ?? window.activeSeries?.name.toLowerCase() ?? '';
    final bool isTPRSeries = sName.contains('tpr');

    final frameRects = window.getFrameRects();
    List<double> framePieces = [];
    List<double> framePlinthePieces = [];
    List<double> renfortFramePieces = [];

    double renfortFrameDeduction = 140.0;
    if (window.frameOverride != null) {
      renfortFrameDeduction =
          (window.frameOverride!['renfort_deduction'] as num?)?.toDouble() ??
          140.0;
    }

    double integratedCoverW = window.sideCoverWidth;
    if (integratedCoverW <= 0 && window.frameOverride != null) {
      integratedCoverW = ((window.frameOverride!['couvre_joint_width'] ?? window.frameOverride!['visible_width']) as num?)?.toDouble() ?? 0.0;
    }
    if (integratedCoverW <= 0) {
      final sec = window.getSectionByType('frame');
      if (sec != null) {
        integratedCoverW = sec.couvreJointWidth > 0 ? sec.couvreJointWidth : (sec.visibleWidth ?? 0.0);
      }
    }

    final bool hasL = !window.removedShutterSides.contains('left');
    final bool hasR = !window.removedShutterSides.contains('right');
    final bool hasT = !window.removedShutterSides.contains('top');
    final bool hasB = !window.removedShutterSides.contains('bottom') && window.hasBottomFrame;

    for (final r in frameRects) {
      double fWidth = r.width + weldVal;
      double fHeight = r.height + (window.hasBottomFrame ? weldVal : noBottomWeldVal);

      if (window.isIntegratedFrame) {
        fWidth = r.width + (hasL ? integratedCoverW : 0.0) + (hasR ? integratedCoverW : 0.0) + weldVal;
        fHeight = r.height + (hasT ? integratedCoverW : 0.0) + (hasB ? integratedCoverW : 0.0) + (window.hasBottomFrame ? weldVal : noBottomWeldVal);
      }
      
      double hPiece = fHeight / 1000.0;
      double wPiece = fWidth / 1000.0;

      if (window.hasBottomFrame && !window.hasFramePlintheBottom) {
        framePieces.addAll([wPiece, wPiece, hPiece, hPiece]);
      } else {
        framePieces.addAll([wPiece, hPiece, hPiece]);
        if (window.hasFramePlintheBottom) {
          double fThickness = window.profileThickness;
          if (window.frameOverride != null) {
            fThickness = ((window.frameOverride!['visible_width'] ?? window.frameOverride!['thickness']) as num?)?.toDouble() ?? window.profileThickness;
          }
          framePlinthePieces.add((fWidth - (2 * fThickness)) / 1000.0);
        }
      }

      if (window.isPVC) {
        double rw = r.width - renfortFrameDeduction;
        double rh = r.height - renfortFrameDeduction;
        if (rw < 0.0) rw = 0.0;
        if (rh < 0.0) rh = 0.0;

        if (window.hasBottomFrame) {
          renfortFramePieces.addAll([rw / 1000.0, rw / 1000.0, rh / 1000.0, rh / 1000.0]);
        } else {
          renfortFramePieces.addAll([rw / 1000.0, rh / 1000.0, rh / 1000.0]);
        }
      }
    }

    items.add(
      createProfile(
        'الإطار (Frame)',
        colorName,
        pieces: framePieces,
        unit: 'قطاع',
        overrideMap: window.frameOverride,
      ),
    );

    if (framePlinthePieces.isNotEmpty) {
      items.add(
        createProfile(
          'بلانت الإطار (Plinthe Frame)',
          colorName,
          pieces: framePlinthePieces,
          unit: 'قطاع',
          overrideMap: window.componentOverrides['بلانت (Plinthe)'] ?? window.getSectionByType('plinthe')?.toMap(),
        ),
      );
    }

    if (window.isPVC) {
      items.add(
        createProfile(
          'حديد الإطار (Renfort Frame)',
          null,
          pieces: renfortFramePieces,
          unit: 'قطاع',
        ),
      );
    }

    bool showSideCover = window.hasSideCovers && window.isSideCoverAllowed && !window.isIntegratedFrame && !hasIntegratedSideCover;

    if (showSideCover) {
      double w = window.sideCoverWidth; // cover visible width in mm
      final double weldAllowance = window.isPVC ? 5.0 : 0.0; // 5 مم تلحيم (لحيم / تفخيم) لكل قطعة في PVC فقط

      final hasL = !window.removedShutterSides.contains('left');
      final hasR = !window.removedShutterSides.contains('right');
      final hasT = !window.removedShutterSides.contains('top');
      final hasB =
          !window.removedShutterSides.contains('bottom') &&
          window.hasBottomFrame;

      // الطول الرأسي: ارتفاع النافذة + عرض الغطاء العلوي/السفلي (إذا موجود) + 5 مم لحيم
      double verticalLen =
          window.height + (hasT ? w : 0.0) + (hasB ? w : 0.0) + weldAllowance;
      // الطول الأفقي: عرض النافذة + عرض الغطاء الأيسر/الأيمن (إذا موجود) + 5 مم لحيم
      double horizontalLen =
          window.width + (hasL ? w : 0.0) + (hasR ? w : 0.0) + weldAllowance;

      List<double> sideCoverPieces = [];
      if (hasL) sideCoverPieces.add(verticalLen / 1000.0);
      if (hasR) sideCoverPieces.add(verticalLen / 1000.0);
      if (hasT) sideCoverPieces.add(horizontalLen / 1000.0);
      if (hasB) sideCoverPieces.add(horizontalLen / 1000.0);

      if (sideCoverPieces.isNotEmpty) {
        items.add(
          createProfile(
            'الغطاء الجانبي (Side Cover)',
            colorName,
            pieces: sideCoverPieces,
            unit: 'قطاع',
            overrideMap: window.sideCoverOverride,
          ),
        );
      }
    }

    if (hasSingleSash || hasDoubleSash || hasSlidingSash) {
      final Map<String, Map<String, dynamic>> sashGroups = {};

      for (var zone in window.zones) {
        if (zone.content == ZoneContent.singleSash) {
          // No-op
        } else if (zone.content == ZoneContent.doubleSash) {
          // No-op
        }

        final allCellKeys = <String>{};
        allCellKeys.addAll(
          zone.cellIsSash.keys.where((k) => zone.cellIsSash[k] == true),
        );
        allCellKeys.addAll(
          zone.cellIsDoubleSash.keys.where(
            (k) => zone.cellIsDoubleSash[k] == true,
          ),
        );

        for (var cellKey in allCellKeys) {
          double cellQty = 0.0;
          if (zone.cellIsSash[cellKey] == true) {
            cellQty = 1.0;
          } else if (zone.cellIsDoubleSash[cellKey] == true) {
            cellQty = 2.0;
          }

          if (cellQty > 0) {
            final override = zone.cellSashOverrides[cellKey];
            if (override != null) {
              final String code = override['code'] ?? '';
              final String name = override['name'] ?? '';
              final String key = '${code}_$name'.trim();
              final double price =
                  (override['calculated_price'] ?? override['price'] ?? 0.0)
                      .toDouble();

              if (sashGroups.containsKey(key)) {
                sashGroups[key]!['qty'] =
                    (sashGroups[key]!['qty'] as double) + cellQty;
              } else {
                String displayName = '$code - $name'.trim();
                if (displayName.startsWith('- ')) {
                  displayName = displayName.substring(2);
                }
                sashGroups[key] = {
                  'name': displayName.isEmpty
                      ? 'ضلفة داخلية مخصصة'
                      : displayName,
                  'price': price,
                  'isMissing': false,
                  'qty': cellQty,
                };
              }
            } else {
              // No-op
            }
          }
        }
      }

      List<double> sashPieces = [];
      List<double> slidingSashPieces = [];
      List<double> slidingSashTraversePieces = [];
      List<double> slidingSashLateralPieces = [];
      List<double> slidingSashCentralPieces = [];
      List<double> sashPlinthePieces = [];
      for (var zone in window.zones) {
        double overlap = window.sashOverride != null
            ? (window.sashOverride!['sash_overlap'] ?? 8.0).toDouble()
            : 8.0;
        double clearW = zone.boundary.width;
        double clearH = zone.boundary.height;

        if (zone.content == ZoneContent.singleSash) {
          double sashW = clearW + overlap * 2;
          double sashH = clearH + overlap * 2;
          if (zone.hasSashPlintheBottom) {
            sashPieces.addAll([
              sashW / 1000.0,
              sashH / 1000.0,
              sashH / 1000.0,
            ]);
            sashPlinthePieces.add(sashW / 1000.0);
          } else {
            sashPieces.addAll([
              sashW / 1000.0,
              sashW / 1000.0,
              sashH / 1000.0,
              sashH / 1000.0,
            ]);
          }
        } else if (zone.content == ZoneContent.doubleSash) {
          double sashWLeft = clearW * zone.doubleSashRatio + overlap;
          double sashWRight = clearW * (1.0 - zone.doubleSashRatio) + overlap;
          double sashH = clearH + overlap * 2;
          if (zone.hasSashPlintheBottom) {
            sashPieces.addAll([
              sashWLeft / 1000.0,
              sashH / 1000.0,
              sashH / 1000.0,
            ]);
            sashPlinthePieces.add(sashWLeft / 1000.0);
            sashPieces.addAll([
              sashWRight / 1000.0,
              sashH / 1000.0,
              sashH / 1000.0,
            ]);
            sashPlinthePieces.add(sashWRight / 1000.0);
          } else {
            sashPieces.addAll([
              sashWLeft / 1000.0,
              sashWLeft / 1000.0,
              sashH / 1000.0,
              sashH / 1000.0,
            ]);
            sashPieces.addAll([
              sashWRight / 1000.0,
              sashWRight / 1000.0,
              sashH / 1000.0,
              sashH / 1000.0,
            ]);
          }
        } else if (zone.content == ZoneContent.slidingSash) {
          final slidingSashOverride = window.slidingSashOverride ?? window.sashOverride;
          double slidingOverlap = slidingSashOverride != null
              ? (slidingSashOverride['sash_overlap'] ?? 8.0).toDouble()
              : 8.0;
          double wForCalc = clearW;
          double hForCalc = clearH;

          final slidingFrame = getSlidingFrameSection();
          if (slidingFrame != null && window.zones.length > 1) {
            double frameT = (slidingFrame['visible_width'] as num?)?.toDouble() ?? 45.0;

            if (window.zones.length > 1) {
              double innerFrameW = clearW;
              double innerFrameH = clearH;
              List<double> innerFramePieces = [
                innerFrameW / 1000.0,
                innerFrameW / 1000.0,
                innerFrameH / 1000.0,
                innerFrameH / 1000.0,
              ];
              items.add(
                createProfile(
                  'إطار منزلق داخلي (Cadre Coulissant)',
                  colorName,
                  pieces: innerFramePieces,
                  unit: 'قطاع',
                  overrideMap: slidingFrame,
                ),
              );

              wForCalc = clearW - (frameT * 2.0);
              hForCalc = clearH - (frameT * 2.0);
            }
          }

          int sashes = zone.slidingSashesCount > 0
              ? zone.slidingSashesCount
              : 2;
          double sashW = (wForCalc + ((sashes - 1) * 26.0)) / sashes;
          if (window.isPVC) {
            sashW = (wForCalc + ((sashes - 1) * slidingOverlap)) / sashes;
          }
          double sashH = hForCalc + slidingOverlap * 2;
          final String seriesName = window.activeSlidingSeries?.name.toLowerCase() ?? window.activeSeries?.name.toLowerCase() ?? '';
          final bool isTPI67000 = seriesName.contains('67000') || seriesName.contains('tpi');
          bool hasThreePiece = (window.activeSlidingSeries?.hasThreePieceSash ?? false) || isTPI67000;
          if (hasThreePiece) {
            sashH = window.height - 64.0;
          } else {
            if (!window.isPVC) {
              sashH = window.height - 81.0;
            }
          }

          if (hasThreePiece) {
            // New formula for 3-piece sash traverses in sliding systems (e.g. TPR / HPS)
            double tLen = 0.0;
            if (sashes == 2) {
              tLen = (window.width - 154.0) / 2.0;
            } else if (sashes == 3) {
              tLen = (window.width - 160.0) / 3.0;
            } else {
              tLen = (window.width - 154.0) / 2.0; // fallback
            }
            if (tLen < 0) tLen = 0.0;

            // Traverse pieces (2 pieces per sash: top and bottom)
            for (int s = 0; s < sashes; s++) {
              slidingSashTraversePieces.addAll([
                tLen / 1000.0,
                tLen / 1000.0,
              ]);
            }

            // Lateral pieces (2 lateral profiles per window/sash assembly)
            for (int i = 0; i < 2; i++) {
              slidingSashLateralPieces.add(sashH / 1000.0);
            }

            // Central / chicane pieces (2 pieces for 2-sash, 4 pieces for 3-sash, 6 pieces for 4-sash)
            int centralsCount = (sashes * 2) - 2;
            for (int s = 0; s < centralsCount; s++) {
              slidingSashCentralPieces.add(sashH / 1000.0);
            }

            // joint brosse: 3 ضلفات H×8+W×12 ، غيرها (H×6+W×8) × (عدد الأزواج)
            if (sashes == 3) {
              slidingTotalJointBrosse += (sashH * 8 + sashW * 12) / 1000.0;
            } else {
              final int pairs = sashes ~/ 2;
              slidingTotalJointBrosse += pairs * (sashH * 6 + sashW * 8) / 1000.0;
            }
          } else {
            for (int s = 0; s < sashes; s++) {
              slidingSashPieces.addAll([
                sashW / 1000.0,
                sashW / 1000.0,
                sashH / 1000.0,
                sashH / 1000.0,
              ]);
            }
            // joint brosse موحد PVC والألمنيوم: 3 ضلفات H×8+W×12 ، غيرها × عدد الأزواج
            if (sashes == 3) {
              slidingTotalJointBrosse += (sashH * 8 + sashW * 12) / 1000.0;
            } else {
              final int pairs = sashes ~/ 2;
              slidingTotalJointBrosse += pairs * (sashH * 6 + sashW * 8) / 1000.0;
            }
          }

          slidingTotalRoulettes += (sashes * 2);
          slidingTotalEspagnolettes += 2;
          slidingTotalHandles += 2;
          
          double h = hForCalc;
          int gachesPerEspagnolette = 2;
          if (h >= 1000 && h <= 1400) {
            gachesPerEspagnolette = 3;
          } else if (h > 1400) {
            gachesPerEspagnolette = 4;
          }
          slidingTotalGacheCoulissant += gachesPerEspagnolette * 2;

          bool excludeChicane =
              (window.system?.name.toLowerCase().contains('tpr') ?? false) ||
              (window.system?.name.toLowerCase().contains('hps') ?? false);
          if (!excludeChicane) {
            for (int c = 0; c < sashes - 1; c++) {
              slidingChicanePieces.add(sashH / 1000.0);
            }
          }

          double frameT = window.profileThickness;
          if (window.frameOverride != null) {
            frameT = ((window.frameOverride!['visible_width'] ?? window.frameOverride!['thickness']) as num?)?.toDouble() ?? window.profileThickness;
          } else {
            final frameSection = window.getSectionByType('frame');
            if (frameSection != null) {
              frameT = ((frameSection.visibleWidth ?? frameSection.thickness) as num?)?.toDouble() ?? window.profileThickness;
            }
          }
          double railLen = isTPRSeries ? (window.width - (frameT * 2) - 1.0) / 1000.0 : (wForCalc - 5.0) / 1000.0;
          slidingRailPieces.add(railLen);
          slidingRailPieces.add(railLen);
        }
      }

      if (sashPieces.isNotEmpty) {
        items.add(
          createProfile(
            'الظلفة (Sash)',
            colorName,
            pieces: sashPieces,
            unit: 'قطاع',
            overrideMap: window.sashOverride,
          ),
        );
      }

      if (sashPlinthePieces.isNotEmpty) {
        items.add(
          createProfile(
            'بلانت الظلفة (Plinthe Sash)',
            colorName,
            pieces: sashPlinthePieces,
            unit: 'متر',
            overrideMap: window.componentOverrides['بلانت (Plinthe)'] ?? window.sashOverride,
          ),
        );
      }

      if (slidingSashPieces.isNotEmpty) {
        items.add(
          createProfile(
            'الظلفة المنزلقة (Sliding Sash)',
            colorName,
            pieces: slidingSashPieces,
            unit: 'قطاع',
            overrideMap: window.slidingSashOverride ?? window.sashOverride,
          ),
        );
      }

      if (slidingSashTraversePieces.isNotEmpty) {
        items.add(
          createProfile(
            'سكة الظلفة (Sash Traverse)',
            colorName,
            pieces: slidingSashTraversePieces,
            unit: 'قطاع',
            overrideMap: window.componentOverrides['عرضي (Traverse)'] ?? window.getSectionByType('sash_traverse')?.toMap() ?? window.sashOverride,
          ),
        );
      }


      if (slidingSashLateralPieces.isNotEmpty) {
        // Determine whether reinforcement is active for lateral
        bool isLateralReinforced = window.zones.any((z) =>
            z.slidingMontantReinforced['lateral_0'] == true ||
            z.slidingMontantReinforced['lateral_1'] == true);

        String lateralName = isLateralReinforced
            ? 'قائم جانبي معزز (Sash Lateral Renforcé)'
            : 'قائم جانبي (Sash Lateral)';

        // Fetch user override or default normal profile
        Map<String, dynamic>? baseLateral = window.componentOverrides[lateralName] ??
            window.componentOverrides['قائم جانبي (Sash Lateral)'] ??
            window.componentOverrides['قائم جانبي (Lateral)'] ??
            window.getSectionByType('sash_lateral')?.toMap() ??
            window.sashOverride;

        if (baseLateral != null) {
          if (isLateralReinforced) {
            final reinforced = findReinforcedSection(baseLateral, false, window);
            if (reinforced != null) {
              baseLateral = reinforced;
            }
          } else {
            final normal = findNormalSection(baseLateral, false, window);
            if (normal != null) {
              baseLateral = normal;
            }
          }
        }

        items.add(
          createProfile(
            lateralName,
            colorName,
            pieces: slidingSashLateralPieces,
            unit: 'قطاع',
            overrideMap: baseLateral,
          ),
        );
      }

      if (slidingSashCentralPieces.isNotEmpty) {
        // Determine whether reinforcement is active for central
        bool isCentralReinforced = window.zones.any((z) =>
            z.slidingMontantReinforced.entries.any((e) => e.key.startsWith('central_') && e.value == true));

        String centralName = isCentralReinforced
            ? 'قائم وسطي معزز (Sash Central Renforcé)'
            : 'قائم وسطي (Sash Central)';

        // Fetch user override or default normal profile
        Map<String, dynamic>? baseCentral = window.componentOverrides[centralName] ??
            window.componentOverrides['قائم وسطي (Sash Central)'] ??
            window.componentOverrides['قائم وسطي (Central)'] ??
            window.getSectionByType('sash_central')?.toMap() ??
            window.sashOverride;

        if (baseCentral != null) {
          if (isCentralReinforced) {
            final reinforced = findReinforcedSection(baseCentral, true, window);
            if (reinforced != null) {
              baseCentral = reinforced;
            }
          } else {
            final normal = findNormalSection(baseCentral, true, window);
            if (normal != null) {
              baseCentral = normal;
            }
          }
        }

        items.add(
          createProfile(
            centralName,
            colorName,
            pieces: slidingSashCentralPieces,
            unit: 'قطاع',
            overrideMap: baseCentral,
          ),
        );
      }

      if (slidingChicanePieces.isNotEmpty) {
        Map<String, dynamic>? baseChicane = window.componentOverrides['الشيكان (Chicane)'] ??
            window.getSectionByType('chicane')?.toMap() ??
            window.getSectionByType('sash_chicane')?.toMap();
        items.add(
          createProfile(
            'الشيكان (Chicane)',
            colorName,
            pieces: slidingChicanePieces,
            unit: 'قطاع',
            overrideMap: baseChicane,
          ),
        );
      }

      if (slidingRailPieces.isNotEmpty) {
        items.add(
          createProfile(
            'الري (Rail)',
            colorName,
            pieces: slidingRailPieces,
            unit: 'قطاع',
          ),
        );
      }

      // Removed 'أجوابروس (Ajoubruse)' profile completely as requested.

      sashGroups.forEach((key, group) {
        items.add(
          BomItem(
            category: 'profile',
            originalName: 'الظلفة (Sash)',
            name: group['name'],
            colorName: colorName,
            quantity: group['qty'],
            unit: 'قطاع',
            unitPrice: group['price'],
            isMissing: group['isMissing'],
          ),
        );
      });

      if (window.isPVC) {
        double renfortSashDeduction = 140.0;
        if (window.sashOverride != null) {
          renfortSashDeduction =
              (window.sashOverride!['renfort_deduction'] as num?)?.toDouble() ??
              140.0;
        }
        List<double> renfortSashPieces = sashPieces.map((p) {
          double len = p - (renfortSashDeduction / 1000.0);
          return len < 0.0 ? 0.0 : len;
        }).toList();
        items.add(
          createProfile(
            'حديد الظلفة (Renfort Sash)',
            null,
            pieces: renfortSashPieces,
            unit: 'قطاع',
          ),
        );

        double renfortSashMifsalDeduction = renfortSashDeduction;
        List<double> renfortSashMifsalPieces = [];
        for (var zone in window.zones) {
          double overlap = window.sashOverride != null
              ? (window.sashOverride!['sash_overlap'] ?? 8.0).toDouble()
              : 8.0;
          double clearH = zone.boundary.height;

          if (zone.content == ZoneContent.singleSash) {
            double sashH = clearH + overlap * 2;
            double len = (sashH / 1000.0) - (renfortSashMifsalDeduction / 1000.0);
            renfortSashMifsalPieces.add(len < 0.0 ? 0.0 : len);
          } else if (zone.content == ZoneContent.doubleSash) {
            double sashH = clearH + overlap * 2;
            double len = (sashH / 1000.0) - (renfortSashMifsalDeduction / 1000.0);
            double finalLen = len < 0.0 ? 0.0 : len;
            renfortSashMifsalPieces.addAll([finalLen, finalLen]);
          }
        }

        if (renfortSashMifsalPieces.isNotEmpty) {
          items.add(
            createProfile(
              'حديد الظلفة الخاص بالمفاصل',
              null,
              pieces: renfortSashMifsalPieces,
              unit: 'قطاع',
            ),
          );
        }
        int totalRenfortScrews = 0;
        double frameWidthScrews = ((window.width / 500.0) + 1).ceilToDouble();
        double frameHeightScrews = ((netHeight / 500.0) + 1).ceilToDouble();
        totalRenfortScrews += (frameWidthScrews * 2 + frameHeightScrews * 2)
            .toInt();

        for (var zone in window.zones) {
          if (zone.content == ZoneContent.singleSash) {
            double sashWidth = zone.boundary.width;
            double sashHeight = zone.boundary.height;
            double sashWidthScrews = (sashWidth / 1000.0).ceilToDouble();
            double sashHeightScrews = (sashHeight / 1000.0).ceilToDouble();
            totalRenfortScrews += (sashWidthScrews * 2 + sashHeightScrews * 2)
                .toInt();
          } else if (zone.content == ZoneContent.doubleSash) {
            double sashWidthLeft = zone.boundary.width * zone.doubleSashRatio;
            double sashWidthRight =
                zone.boundary.width * (1.0 - zone.doubleSashRatio);
            double sashHeight = zone.boundary.height;

            double leftWidthScrews = (sashWidthLeft / 1000.0).ceilToDouble();
            double leftHeightScrews = (sashHeight / 1000.0).ceilToDouble();
            double rightWidthScrews = (sashWidthRight / 1000.0).ceilToDouble();
            double rightHeightScrews = (sashHeight / 1000.0).ceilToDouble();

            totalRenfortScrews += (leftWidthScrews * 2 + leftHeightScrews * 2)
                .toInt();
            totalRenfortScrews += (rightWidthScrews * 2 + rightHeightScrews * 2)
                .toInt();
          }
        }

        items.add(createAccessory('براغي حديد الدعم', qty: totalRenfortScrews));
      }
    }

    if (hasDoubleSash) {
      List<double> batmoPieces = [];
      final batmoSectionMap = window.componentOverrides['الباتمو (Batmo)'];
      double batmoCuttingDeduction = 0.0;
      if (batmoSectionMap != null) {
        batmoCuttingDeduction =
            (batmoSectionMap['cutting_deduction'] as num?)?.toDouble() ?? 0.0;
      }

      for (var zone in window.zones) {
        if (zone.content == ZoneContent.doubleSash) {
          double clearH = zone.boundary.height;
          // batmo length = الطول الداخلي للإطار - الخصم الإضافي
          double pieceLength = clearH - batmoCuttingDeduction;
          batmoPieces.add(pieceLength / 1000.0); // converting to meters
        }
      }

      items.add(
        createProfile(
          'الباتمو (Batmo)',
          colorName,
          pieces: batmoPieces,
          unit: 'قطاع',
        ),
      );

      // Removed Renfort Batmo block
      int batmoScrews = 0;
      if (netHeight < 1000) {
        batmoScrews = 2;
      } else if (netHeight < 2000) {
        batmoScrews = 3;
      } else if (netHeight >= 2000) {
        batmoScrews = 4;
      }
      items.add(
        createAccessory('براغي الباتمو', qty: batmoScrews * doubleSashCount),
      );
      items.add(
        createProfile(
          'بوشون باتمو (Bouchon Batmo)',
          colorName,
          unit: 'حبة',
          defaultPrice: 0,
          qty: doubleSashCount.toDouble(),
        ),
      );
      items.add(
        createAccessory(
          'براغي بوشون باتمو',
          qty: (doubleSashCount * 2).toInt(),
        ),
      );
    }

    // --- 2. الإكسسوارات (Accessories) ---
    bool isVerrouCentralActive =
        activeVariants['Verrou Central'] ?? window.useVerrouCentral;
    bool isSystemObActive = activeVariants['System OB'] ?? window.useSystemOB;
    bool isDemiObActive = activeVariants['Demi System OB'] ?? window.useDemiOB;

    if (hasDoubleSash) {
      items.add(
        createAccessory(
          'الفيرو (Verrou)',
          isActive: !isVerrouCentralActive,
          qty: doubleSashCount * 2,
        ),
      );

      final verrouCentralKey = getKitKey('Verrou Central');
      if (verrouCentralKey != null &&
          (kitBundleData[verrouCentralKey]?.isNotEmpty ?? false)) {
        items.add(
          createInteractiveAccessory(
            'Verrou Central',
            'verrou_group',
            isActive: isVerrouCentralActive,
            qty: doubleSashCount.toDouble(),
            kitGroupName: 'Verrou Central',
          ),
        );
        final leafH = window.height.toDouble();
        final leafW = (hasSingleSash && !hasDoubleSash)
            ? window.width.toDouble()
            : (window.width / 2.0);
        final String windowVariant = hasDoubleSash ? 'double' : 'simple';
        final bool perLeaf = kitPerLeafMap[verrouCentralKey] ?? false;
        final int leafCount = perLeaf
            ? ((doubleSashCount * 2) + singleSashCount)
            : doubleSashCount.toInt();
        items.addAll(
          expandKitBundle(
            'Verrou Central',
            kitBundleData[verrouCentralKey]!,
            leafHeightMm: leafH,
            leafWidthMm: leafW,
            isActive: isVerrouCentralActive,
            leafCount: leafCount,
            variantValue: windowVariant,
          ),
        );
      } else {
        items.add(
          createInteractiveAccessory(
            'Verrou Central',
            'verrou_group',
            isActive: isVerrouCentralActive,
            qty: doubleSashCount.toDouble(),
            kitGroupName: 'Verrou Central',
          ),
        );
      }

      if (windowDoubleSashCount > 0 && window.isPVC) {
        items.add(
          createAccessory(
            'قاش دوبل (Gache Double Ouvrant)',
            isActive: !isVerrouCentralActive,
            qty: windowDoubleSashCount * gacheQtyPerDoubleSash,
          ),
        );
      }
    }

    if (windowSingleSashCount > 0 && window.isPVC) {
      items.add(
        createAccessory(
          'قاش سامبل (Gache Simple Ouvrant)',
          qty: windowSingleSashCount * gacheQtyPerDoubleSash,
        ),
      );
    }

    if (hasSingleSash || hasDoubleSash || hasSlidingSash) {
      bool isEspagnoletteActive = true;
      int activeObCount = (isSystemObActive ? 1 : 0) + (isDemiObActive ? 1 : 0);
      int espagnoletteQty = totalHandles - activeObCount;
      if (isSystemObActive || isDemiObActive) {
        isEspagnoletteActive = false;
        espagnoletteQty = totalHandles;
      }

      if (espagnoletteQty > 0 && window.isPVC) {
        double heightCm = window.height / 10.0;
        double targetH = window.hasShutter ? (heightCm - 35) : (heightCm - 20);

        int espLength = 30;
        if (targetH >= 180) {
          espLength = 180;
        } else if (targetH >= 40) {
          espLength = (targetH / 20.0).floor() * 20;
        } else if (targetH >= 30) {
          espLength = 30;
        }

        items.add(
          createAccessory(
            'إسبانيوليت $espLength (Espagnolette)',
            isActive: isEspagnoletteActive,
            qty: espagnoletteQty,
          ),
        );
      }

      // System OB — إما تفجير Kit أو عنصر واحد
      final systemObKey = getKitKey('System OB');
      if (systemObKey != null &&
          (kitBundleData[systemObKey]?.isNotEmpty ?? false)) {
        items.add(
          createInteractiveAccessory(
            'System OB',
            'ob_group',
            isActive: isSystemObActive,
            qty: 1,
            kitGroupName: 'System OB',
          ),
        );
        final leafH = window.height.toDouble();
        final leafW = (hasSingleSash && !hasDoubleSash)
            ? window.width.toDouble()
            : (window.width / 2.0);
        final String windowVariant = hasDoubleSash ? 'double' : 'simple';
        final bool perLeaf = kitPerLeafMap[systemObKey] ?? false;
        final int leafCount = perLeaf
            ? ((doubleSashCount * 2) + singleSashCount)
            : 1;
        items.addAll(
          expandKitBundle(
            'System OB',
            kitBundleData[systemObKey]!,
            leafHeightMm: leafH,
            leafWidthMm: leafW,
            isActive: isSystemObActive,
            leafCount: leafCount,
            variantValue: windowVariant,
          ),
        );
      } else {
        items.add(
          createInteractiveAccessory(
            'System OB',
            'ob_group',
            isActive: isSystemObActive,
            qty: 1,
            kitGroupName: 'System OB',
          ),
        );
      }

      // Demi System OB — إما تفجير Kit أو عنصر واحد
      final demiObKey = getKitKey('Demi System OB');
      if (demiObKey != null &&
          (kitBundleData[demiObKey]?.isNotEmpty ?? false)) {
        items.add(
          createInteractiveAccessory(
            'Demi System OB',
            'ob_group',
            isActive: isDemiObActive,
            qty: 1,
            kitGroupName: 'Demi System OB',
          ),
        );
        final leafH = window.height.toDouble();
        final leafW = (hasSingleSash && !hasDoubleSash)
            ? window.width.toDouble()
            : (window.width / 2.0);
        final String windowVariant = hasDoubleSash ? 'double' : 'simple';
        final bool perLeaf = kitPerLeafMap[demiObKey] ?? false;
        final int leafCount = perLeaf
            ? ((doubleSashCount * 2) + singleSashCount)
            : 1;
        items.addAll(
          expandKitBundle(
            'Demi System OB',
            kitBundleData[demiObKey]!,
            leafHeightMm: leafH,
            leafWidthMm: leafW,
            isActive: isDemiObActive,
            leafCount: leafCount,
            variantValue: windowVariant,
          ),
        );
      } else {
        items.add(
          createInteractiveAccessory(
            'Demi System OB',
            'ob_group',
            isActive: isDemiObActive,
            qty: 1,
            kitGroupName: 'Demi System OB',
          ),
        );
      }

      if (useCremone && cremoneQty > 0) {
        items.add(
          createAccessory('كريمون (Cremone)', color: colorName, qty: cremoneQty),
        );
      }

      if (octoHandles > 0 && window.systemMode != 'sliding') {
        items.add(
          createAccessory('مقبض أوكتو (Octo)', color: colorName, qty: octoHandles),
        );
      }
      if (pvcHandlesOnAlu > 0 && window.systemMode != 'sliding') {
        items.add(
          createAccessory('مقبض نافذة بي في سي (Poignée Fenêtre PVC)', color: colorName, qty: pvcHandlesOnAlu),
        );
      }
      if (totalHandles > 0 && window.systemMode != 'sliding') {
        if (window.isPVC) {
          items.add(
            createAccessory('مقبض نافذة (Poignée Fenêtre)', color: colorName, qty: totalHandles),
          );
        } else {
          items.add(
            createAccessory('المقبض (Handle)', color: colorName, qty: totalHandles),
          );
        }
      }

      if (totalCompas > 0) {
        items.add(
          createAccessory('كومباس (Compas)', color: colorName, qty: totalCompas),
        );
      }
      if (normalDoorHandles > 0 && window.systemMode != 'sliding') {
        items.add(
          createAccessory('مقبض الباب عادي (Poignée Porte)', color: colorName, qty: normalDoorHandles),
        );
      }
      if (marechal125Handles > 0 && window.systemMode != 'sliding') {
        items.add(
          createAccessory('مقبض كبير ماريشال 1.25 متر (Poignée Maréchal 1.25m)', color: colorName, qty: marechal125Handles),
        );
      }
      if (marechal2mHandles > 0 && window.systemMode != 'sliding') {
        items.add(
          createAccessory('مقبض كبير ماريشال 2 متر (Poignée Maréchal 2m)', color: colorName, qty: marechal2mHandles),
        );
      }
      if (rollerLocks > 0 && window.systemMode != 'sliding') {
        items.add(
          createAccessory('قفل رولون (Serrure à Rouleau)', color: colorName, qty: rollerLocks),
        );
      }
      if (keyHandles > 0 && window.systemMode != 'sliding') {
        items.add(
          createAccessory('مقبض الباب (Poignée Porte à Clé)', color: colorName, qty: keyHandles),
        );
      }
      if (condamnationHandles > 0 && window.systemMode != 'sliding') {
        items.add(
          createAccessory('مقبض الباب Condamnation (Poignée Condamnation)', color: colorName, qty: condamnationHandles),
        );
      }
      if (keyLocks > 0 && window.systemMode != 'sliding') {
        items.add(
          createAccessory('قفل الباب (Serrure)', color: colorName, qty: keyLocks),
        );
      }
      if (condamnationLocks > 0 && window.systemMode != 'sliding') {
        items.add(
          createAccessory('قفل الباب Condamnation (Serrure Condamnation)', color: colorName, qty: condamnationLocks),
        );
      }
      if (pointLocks > 0 && window.systemMode != 'sliding') {
        items.add(
          createAccessory('قفل نقطة', color: colorName, qty: pointLocks),
        );
      }
      if (doorCanons > 0 && window.systemMode != 'sliding') {
        items.add(
          createAccessory('الأسطوانة (Canon)', color: colorName, qty: doorCanons),
        );
      }
      if (gachePortes > 0 && window.systemMode != 'sliding') {
        items.add(
          createAccessory('قاش بورت (Gache Porte)', color: colorName, qty: gachePortes),
        );
      }
      if (totalHinges > 0 && window.systemMode != 'sliding') {
        items.add(
          createAccessory('المفاصل (Hinges)', color: colorName, qty: totalHinges),
        );
      }

        if (slidingTotalRoulettes > 0) {
          items.add(
            createAccessory(
              'عجلات المنزلق (Roulettes)',
              color: colorName,
              qty: slidingTotalRoulettes,
            ),
          );
          if (!window.isPVC) {
            final String seriesName = window.activeSlidingSeries?.name.toLowerCase() ?? '';
            String kitKey = 'كيت 67000 (Kit 67000)';
            if (seriesName.contains('76000')) {
              kitKey = 'كيت 76000 (Kit 76000)';
            } else if (seriesName.contains('40000')) {
              kitKey = 'كيت 40000 (Kit 40000)';
            } else if (seriesName.contains('67000')) {
              kitKey = 'كيت 67000 (Kit 67000)';
            }
            items.add(
              createOther(
                kitKey,
                color: colorName,
                qty: 1,
              ),
            );
          }
          final bool useEntrematique = !window.isPVC &&
              window.zones.any((z) =>
                  z.content == ZoneContent.slidingSash &&
                  z.useClassicHandle != true);

        if (useEntrematique) {
          items.add(
            createAccessory(
              'أونتروماتيك (Entrematique)',
              color: colorName,
              qty: slidingTotalHandles,
            ),
          );
        } else {
          items.add(
            createAccessory(
              'اسبانيولات المنزلق (Espagnolette)',
              color: colorName,
              qty: slidingTotalEspagnolettes,
            ),
          );
          items.add(
            createAccessory(
              'المقبض (Handle)',
              color: colorName,
              qty: slidingTotalHandles,
            ),
          );
          final String seriesName = window.activeSlidingSeries?.name.toLowerCase() ?? '';
          final bool isTPR = seriesName.contains('tpr') && !window.isPVC;
          if (isTPR) {
            items.add(
              createAccessory(
                'Gâche coulissant TPR',
                color: colorName,
                qty: slidingTotalEspagnolettes,
              ),
            );
          } else {
            items.add(
              createAccessory(
                'كاش كوليسون (Gache coulissant)',
                color: colorName,
                qty: slidingTotalGacheCoulissant,
              ),
            );
          }
        }

        // Add Gache Porte (قاش بورت) if it is a door
        final isDoor = window.system?.name.toLowerCase().contains('porte') ?? false;
        if (isDoor) {
          items.add(
            createAccessory(
              'قاش بورت (Gache Porte)',
              color: colorName,
              qty: 2,
            ),
          );
        }

        // الصيغة الموحدة لا تحتاج تبديل خاص بـ PVC

        items.add(
          createJoint(
            'جوان بروس للظلفة (Joint Brosse Sash)',
            color: colorName,
            qty: slidingTotalJointBrosse.ceilToDouble(),
            unit: 'متر',
          ),
        );

        slidingGlassJoints.forEach((jointName, totalLength) {
          items.add(
            createJoint(
              jointName,
              qty: totalLength.ceilToDouble(),
              unit: 'متر',
            ),
          );
        });
      }

      // Add Bouchon Parclose (بوشون بارك لوز) for opening systems
      if ((hasSingleSash || hasDoubleSash) && window.systemMode != 'sliding') {
        if (window.componentOverrides.containsKey('بوشون بارك لوز (Bouchon Parclose)')) {
          items.add(
            createAccessory(
              'بوشون بارك لوز (Bouchon Parclose)',
              color: colorName,
              qty: 4 * (singleSashCount + doubleSashCount),
            ),
          );
        }
        if (!useCremone && window.componentOverrides.containsKey('كريمون (Cremone)')) {
          items.add(
            createAccessory(
              'كريمون (Cremone)',
              color: colorName,
              qty: 0,
            ),
          );
        }
      }

    }

    // --- 3. الستائر (Shutters) ---
    if (hasShutter) {
      int caissonSize = window.shutterBoxHeight.toInt();
      double coulisseLengthM =
          (window.isCaissonTunnel
              ? (window.height + 20.0)
              : (window.height - caissonSize)) /
          1000.0;
      if (coulisseLengthM < 0) coulisseLengthM = 0;

      bool isTunnel = window.isCaissonTunnel;
      bool isMotor = window.shutterMechanism == 'محرك';

      bool isExtrudedBlade = false;
      if (window.componentOverrides.containsKey('الشرائح (Lames)')) {
        final override = window.componentOverrides['الشرائح (Lames)'];
        isExtrudedBlade =
            override != null && override['shutter_subtype'] == 'extruded';
      }

      bool showIndividualOptions = isTunnel || isExtrudedBlade;

      // Retrieve active variant states
      // Kit is always active for non-tunnel shutters (for all drive types)
      bool isKitActive = !isTunnel && (activeVariants['كيت (Kit)'] ?? true);
      bool isTandemActive =
          showIndividualOptions && (activeVariants['طانديم (Tandem)'] ?? true);
      bool isEmboutActive =
          showIndividualOptions && (activeVariants['الامبو (Embout)'] ?? false);
      bool isSupportRoulementActive =
          showIndividualOptions &&
          (activeVariants['سيبور رولمو (Support Roulement)'] ?? false);
      bool isSupportMoteurActive =
          showIndividualOptions &&
          (activeVariants['سيبور موتور (Support Moteur)'] ?? true);
      bool isBouchonLameActive = isTunnel
          ? true
          : (activeVariants['أغطية الشفرات (Bouchons Lames)'] ?? false);

      // ===== 1. الكيت (Kit) - أول مركب، فقط لغير النفق =====
      if (!isTunnel) {
        void addAndExpandKit(
          String uiKey,
          List<String> defaultKeywords,
          bool isMotorized, {
          bool filterAxeItems = true,
        }) {
          String? matchedKitName;
          String? actualKitName;
          if (window.componentOverrides.containsKey(uiKey)) {
            final overrideItem = window.componentOverrides[uiKey];
            actualKitName = overrideItem['name']?.toString();
          }

          List<String> searchPriority = [];
          if (actualKitName != null && actualKitName.isNotEmpty) {
            searchPriority.add(actualKitName);
          }
          searchPriority.addAll(defaultKeywords);

          // Pass 1: Exact key match in kitBundleData
          for (final possibleName in searchPriority) {
            if (kitBundleData.containsKey(possibleName) &&
                (kitBundleData[possibleName]?.isNotEmpty ?? false)) {
              matchedKitName = possibleName;
              break;
            }
          }

          // Pass 2: Partial substring match — handles 'Kit volet 1' → 'Kit volet 155'
          if (matchedKitName == null) {
            outer:
            for (final keyword in searchPriority) {
              final lowerKw = keyword.toLowerCase();
              for (final bundleKey in kitBundleData.keys) {
                if (bundleKey.toLowerCase().contains(lowerKw) &&
                    (kitBundleData[bundleKey]?.isNotEmpty ?? false)) {
                  matchedKitName = bundleKey;
                  break outer;
                }
              }
            }
          }

          // groupName used only for display fallback when bundle not found
          final String groupName = matchedKitName ?? uiKey;
          final bool perLeaf = kitPerLeafMap[groupName] ?? false;
          final double kitQty = perLeaf
              ? ((doubleSashCount * 2) + singleSashCount).toDouble()
              : 1.0;

          if (isMotorized) {
            items.add(
              createInteractiveAccessory(
                uiKey,
                groupName,
                isActive: true, // دائماً مفعَّل — لا يُشطَب أبداً
                qty: kitQty,
                kitGroupName: matchedKitName ?? uiKey,
                category: 'shutter', // ينتمي لقسم الستار، ليس الإكسسوارات
              ),
            );
          } else {
            items.add(
              createShutter(
                uiKey,
                color: colorName,
                qty: kitQty,
                kitGroupName: matchedKitName ?? uiKey,
              ),
            );
          }

          if (matchedKitName != null) {
            final String shutterVariant = isExtrudedBlade
                ? 'extruded'
                : 'normal';
            final int leafCount = perLeaf
                ? ((doubleSashCount * 2) + singleSashCount)
                : 1;
            var expandedItems = expandKitBundle(
              matchedKitName,
              kitBundleData[matchedKitName]!,
              leafHeightMm: window.height.toDouble(),
              leafWidthMm: window.width.toDouble(),
              isActive: true,
              // دائماً مفعَّل — لا تُشطَب عناصر الكيت
              leafCount: leafCount,
              category: 'shutter',
              variantValue: shutterVariant,
            );
            // If Axe is 60mm (separate row), exclude axe items already inside kit bundle
            if (filterAxeItems) {
              expandedItems = expandedItems.where((bi) {
                final n = bi.name.toLowerCase();
                final on = bi.originalName.toLowerCase();
                return !n.contains('laxe') &&
                    !n.contains('axe') &&
                    !n.contains('محور') &&
                    !n.contains('أوم') &&
                    !on.contains('laxe') &&
                    !on.contains('_laxe') &&
                    !on.contains('_axe') &&
                    !on.contains('محور');
              }).toList();
            }
            items.addAll(expandedItems);
          }
        }

        // ── Determine exact mechanism ────────────────────────────────────────────
        final mech = window.shutterMechanism;
        final bool isCrank =
            mech == 'منايفال' || mech == 'مانيفال' || mech == 'مانيفر';

        if (isMotor) {
          // ── Parse selected Axe diameter ──────────────────────────────────────────
          final axeOverride = window.componentOverrides['المحور (Axe)'];
          final axeNameRaw = axeOverride?['name']?.toString() ?? '';
          final axeDiamRaw = axeOverride?['motor_diameter']?.toString() ?? '';
          int selectedAxeDiam = 0;
          final diamStr = axeDiamRaw.isNotEmpty ? axeDiamRaw : axeNameRaw;
          final diamMatch = RegExp(r'(\d+)').firstMatch(diamStr);
          if (diamMatch != null) {
            selectedAxeDiam = int.tryParse(diamMatch.group(1)!) ?? 0;
          }
          final bool axeIsExternal =
              selectedAxeDiam == 60; // 60mm → separate row

          addAndExpandKit(
            'كيت فولي موتور (Kit Volet Moteur)',
            // DB: "Kit volet Moteur 155", "Kit volet moteur 185"
            ['Kit volet Moteur', 'Kit volet moteur', 'kit volet moteur'],
            true,
            filterAxeItems: true,
          );
        } else if (isCrank) {
          // منايفال (Manivelle)
          addAndExpandKit(
            'كيت فولي مانيفر (Kit Volet Manivelle)',
            // DB: "Kit volet manivelle"
            [
              'Kit volet manivelle',
              'kit volet manivelle',
              'Kit Volet Manivelle',
            ],
            true,
          );
          addAndExpandKit(
            'كيت مانيفر (Kit Manivelle)',
            // DB: "Kit Manivelle"
            ['Kit Manivelle', 'kit manivelle', 'kit_manivelle'],
            true,
          );
        } else {
          // حزام (Sangle): DB: "Kit volet 155", "Kit volet 185", "Kit volet 205"
          // الاسم الدقيق يؤخذ من componentOverrides تلقائياً، keywords هي فقط للاحتياط
          addAndExpandKit('كيت فولي (Kit Volet)', [
            'Kit volet 1',
            'Kit volet 2',
            'kit volet 1',
            'kit volet 2',
            'Kit volet 0',
          ], true);
        }
        // براغي الكيت
        items.add(createShutter('براغي الكيت', qty: 8));
      }

      // ===== 2. الصندوق وبراغيه (الصندوق يظهر دائماً ولكن النفق سعره 0) =====
      if (isTunnel) {
        List<double> caissonPieces = [window.width / 1000.0 - 0.01];
        final originalBox = createShutter(
          'الصندوق (Caisson)',
          color: colorName,
          pieces: caissonPieces,
          unit: 'بارة',
        );
        final boxItem = BomItem(
          category: originalBox.category,
          originalName: originalBox.originalName,
          name: "${originalBox.name} (صندوق نفق - لا يدخل في التكلفة)",
          imagePath: originalBox.imagePath,
          colorName: originalBox.colorName,
          length: originalBox.length,
          glassHeight: originalBox.glassHeight,
          quantity: originalBox.quantity,
          unit: originalBox.unit,
          unitPrice: 0.0,
          isMissing: originalBox.isMissing,
          isInteractive: originalBox.isInteractive,
          isActive: originalBox.isActive,
          exclusionGroup: originalBox.exclusionGroup,
          pieces: originalBox.pieces,
          cuttingList: originalBox.cuttingList,
          kitGroupName: originalBox.kitGroupName,
          exactQuantity: originalBox.exactQuantity,
        );
        items.add(boxItem);
        // براغي الصندوق لا تضاف في حالة Caisson Tunnel
      } else {
        List<double> caissonPieces = [window.width / 1000.0 - 0.01];
        items.add(
          createShutter(
            'الصندوق (Caisson)',
            color: colorName,
            pieces: caissonPieces,
            unit: 'بارة',
          ),
        );
        items.add(createShutter('براغي الصندوق', qty: 10));
      }

      // ===== 3. المحور (Axe) =====
      // Only add a separate Axe row if the selected Axe is 60mm (external).
      // For 40mm/44mm the Axe is already included inside the kit bundle.
      {
        final axeOvr = window.componentOverrides['المحور (Axe)'];
        final axeNm = axeOvr?['name']?.toString() ?? '';
        final axeDm = axeOvr?['motor_diameter']?.toString() ?? '';
        final axeStr = axeDm.isNotEmpty ? axeDm : axeNm;
        final axeMtch = RegExp(r'(\d+)').firstMatch(axeStr);
        final int selAxeDiam = axeMtch != null
            ? (int.tryParse(axeMtch.group(1)!) ?? 0)
            : 0;
        // Always add the axe separately as requested by the user to allow manual selection and prevent it from disappearing
        const bool addAxeSeparately = true;
        if (addAxeSeparately) {
          List<double> axePieces = [(window.width - 75) / 1000.0];
          items.add(
            createShutter('المحور (Axe)', pieces: axePieces, unit: 'بارة'),
          );
        }
      }

      // ===== 4. المحرك/المانيفال - مباشرة بعد المحور =====
      if (window.shutterMechanism == 'مانيفال') {
        items.add(
          createShutter('المانيفال (Manivelle)', color: colorName, qty: 1),
        );
        items.add(createShutter('براغي المانيفال', qty: isTunnel ? 1 : 4));
      } else if (window.shutterMechanism == 'محرك') {
        items.add(createShutter('المحرك (Moteur)', color: colorName, qty: 1));
        items.add(createShutter('براغي المحرك', qty: isTunnel ? 1 : 4));
        if (window.motorHasInterrupteur) {
          items.add(createShutter('قاطعة (Interrupteur)', qty: 1));
        }
        if (window.motorHasTelecommande) {
          items.add(createShutter('جهاز تحكم (Télécommande)', qty: 1));
        }
      }

      // ===== 5. الشفرات (Lames) =====
      int numBladesShutter = isTunnel
          ? ((window.height + 100) / 43.0).ceil()
          : ((window.height - window.shutterBoxHeight) / 43.0 + 2).ceil();
      if (numBladesShutter < 0) numBladesShutter = 0;

      double bladeLengthM = (window.width - 65) / 1000.0;
      // خصم سُمك أغطية الشفرات (4mm من كل جانب = 8mm إجمالاً) عند:
      //  - تفعيل أغطية الشفرات يدوياً (isBouchonLameActive)
      //  - أو وجود محرك (isMotor) لأنها إلزامية معه
      //  - أو صندوق نفق (isTunnel)
      if (isBouchonLameActive || isMotor || isTunnel) {
        double bladesCapThickness = 0.0;
        final bouchonOverride =
            window.componentOverrides['أغطية الشفرات (Bouchons Lames)'];
        if (bouchonOverride != null) {
          bladesCapThickness =
              (bouchonOverride['cap_thickness'] as num?)?.toDouble() ?? 0.0;
        }
        if (bladesCapThickness == 0.0) {
          final bladesOverride = window.componentOverrides['الشرائح (Lames)'];
          if (bladesOverride != null) {
            bladesCapThickness =
                (bladesOverride['cap_thickness'] as num?)?.toDouble() ?? 0.0;
          }
        }
        // الخصم الافتراضي 4mm من كل جانب إذا لم تُحدَّد قيمة في القاعدة
        if (bladesCapThickness == 0.0) bladesCapThickness = 4.0;
        bladeLengthM -= (2 * bladesCapThickness) / 1000.0;
      }
      List<double> bladePieces = List.filled(numBladesShutter, bladeLengthM);
      items.add(
        createShutter(
          'الشرائح (Lames)',
          color: colorName,
          pieces: bladePieces,
          unit: 'بارة',
        ),
      );

      // ===== 6. أغطية الشفرات (Bouchons Lames) =====
      // الكمية = عدد قطع الشفرات (نفس numBladesShutter تماماً)
      if (isTunnel || isMotor || isBouchonLameActive) {
        items.add(
          createInteractiveAccessory(
            'أغطية الشفرات (Bouchons Lames)',
            'bouchon_lame_group',
            isActive: isBouchonLameActive || isTunnel,
            qty: numBladesShutter * 1.0, // = عدد القطع وليس البارات
          ),
        );
      }

      // ===== 7. الشريحة النهائية (Lame Finale) =====
      double lameFinaleLengthM = (window.width - 65) / 1000.0;
      if (isBouchonLameActive || isMotor || isTunnel) {
        double finalBladeCapThickness = 0.0;
        final bouchonOverride =
            window.componentOverrides['أغطية الشفرات (Bouchons Lames)'];
        if (bouchonOverride != null) {
          finalBladeCapThickness =
              (bouchonOverride['cap_thickness'] as num?)?.toDouble() ?? 0.0;
        }
        if (finalBladeCapThickness == 0.0) {
          final finalBladeOverride =
              window.componentOverrides['الشريحة النهائية (Lame Finale)'];
          if (finalBladeOverride != null) {
            finalBladeCapThickness =
                (finalBladeOverride['cap_thickness'] as num?)?.toDouble() ??
                0.0;
          }
        }
        if (finalBladeCapThickness == 0.0) finalBladeCapThickness = 4.0;
        lameFinaleLengthM -= (2 * finalBladeCapThickness) / 1000.0;
      }
      List<double> lameFinalePieces = [lameFinaleLengthM];
      items.add(
        createShutter(
          'الشريحة النهائية (Lame Finale)',
          color: colorName,
          pieces: lameFinalePieces,
          unit: 'بارة',
        ),
      );

      // ===== 8. السكك (Coulisses) =====
      List<double> coulissePieces = [coulisseLengthM, coulisseLengthM];
      items.add(
        createShutter(
          'السكك (Coulisses)',
          color: colorName,
          pieces: coulissePieces,
          unit: 'بارة',
        ),
      );

      // ===== 9. جوان بروس (Joint Brosse) =====
      if (isTunnel) {
        items.add(
          createShutter(
            'جوان بروس للستار (Joint Brosse Shutter)',
            qty: (coulisseLengthM * 4).ceilToDouble(),
            unit: 'متر',
          ),
        );
      } else {
        items.add(
          createJoint(
            'جوان بروس للستار (Joint Brosse Shutter)',
            qty: (coulisseLengthM * 4).ceilToDouble(),
            unit: 'متر',
          ),
        );
      }

      // ===== 10. أطاش (Attache) =====
      int totalAttaches = (window.width <= 1200)
          ? 2
          : (window.width <= 2000 ? 3 : 4);
      if (isTunnel) {
        items.add(
          createShutter('أطاش (Attache)', qty: totalAttaches.toDouble()),
        );
      } else {
        if (isExtrudedBlade) {
          // في الشفرة الإكسترودي، لا يمكن استخدام الأطاش العادية المرفقة مع الكيت.
          // لذا، نقوم بإضافة إجمالي عدد الأطاش كعنصر منفصل خاص بالإكسترودي يتم شراؤه خارج الكيت.
          items.add(
            createShutter('أطاش (Attache)', qty: totalAttaches.toDouble()),
          );
        } else {
          // في الشفرة العادية، الكيت يحتوي بالفعل على 2 أطاش، ونحتاج فقط الأطاش الإضافية.
          int extraAttaches = totalAttaches - 2;
          if (extraAttaches > 0) {
            items.add(
              createShutter('أطاش (Attache)', qty: extraAttaches.toDouble()),
            );
          }
        }
      }

      // ===== 11. الإكسسوارات الفردية (Tandem, Embout, Support Roulement, Support Moteur) =====
      if (showIndividualOptions) {
        if (!isKitActive) {
          // Tandem
          items.add(
            createInteractiveAccessory(
              'طانديم (Tandem)',
              'tandem_group',
              isActive: isTandemActive,
              qty: 1,
            ),
          );

          // Embout and Support Roulement (only if Tandem is NOT active)
          if (!isTandemActive) {
            items.add(
              createInteractiveAccessory(
                'الامبو (Embout)',
                'embout_group',
                isActive: isEmboutActive,
                qty: 1,
              ),
            );
            items.add(
              createInteractiveAccessory(
                'سيبور رولمو (Support Roulement)',
                'roulement_group',
                isActive: isSupportRoulementActive,
                qty: 1,
              ),
            );
          }

          // Support Moteur
          items.add(
            createInteractiveAccessory(
              'سيبور موتور (Support Moteur)',
              'motor_support_group',
              isActive: isSupportMoteurActive,
              qty: 1,
            ),
          );
        }
      }
    }

    if (window.systemMode == 'sliding') {
      if (!window.isPVC) {
        final int assemblyScrewsQty = (slidingTotalRoulettes ~/ 2) * 4;
        if (assemblyScrewsQty > 0) {
          items.add(
            _createAccessory(
              window.componentOverrides,
              'براغي التجميع',
              qty: assemblyScrewsQty,
            ),
          );
        }
        final String seriesName = window.activeSlidingSeries?.name.toLowerCase() ?? window.activeSeries?.name.toLowerCase() ?? '';
        final bool isTPI67000 = seriesName.contains('67000') || seriesName.contains('tpi') || seriesName.contains('tpr');
        if (isTPI67000) {
          items.add(
            createAccessory(
              'Clam 67000',
              qty: 4,
            ),
          );
        }
      }
    } else {
      int totalAccessoryScrews = 0;
      for (var item in items) {
        if (item.category == 'accessory') {
          int screwCount = 0;
          if (window.componentOverrides.containsKey(item.originalName)) {
            var override = window.componentOverrides[item.originalName];
            if (override['screw_count'] != null) {
              screwCount = override['screw_count'] is int
                  ? override['screw_count']
                  : int.tryParse(override['screw_count'].toString()) ?? 0;
            }
          }
          totalAccessoryScrews += screwCount * item.quantity.toInt();
        }
      }
      if (totalAccessoryScrews > 0) {
        items.add(
          _createAccessory(
            window.componentOverrides,
            'براغي الإكسسوارات',
            qty: totalAccessoryScrews,
          ),
        );
      }
    }

    // =========================================================================
    // استخراج أبعاد العرض الظاهر
    // =========================================================================
    double sw = window.sashOverride != null
        ? (window.sashOverride!['visible_width'] ?? window.profileThickness)
              .toDouble()
        : window.profileThickness;

    // --- 3.5 حساب أعمدة التقسيم للألمنيوم (Traverse / Mullion) ---
    double totalMullionLengthMeters = 0.0;
    List<double> mullionPieces = [];

    // Collect all frame mullion segments from adjacent zones
    final List<_MullionSegment> horizontalSegments = [];
    final List<_MullionSegment> verticalSegments = [];
    final double mullionT = window.mullionThickness;

    for (int i = 0; i < window.zones.length; i++) {
      final z1 = window.zones[i];
      for (int j = i + 1; j < window.zones.length; j++) {
        final z2 = window.zones[j];

        // Check for horizontal boundary
        double overlapLeft = math.max(z1.boundary.left, z2.boundary.left);
        double overlapRight = math.min(z1.boundary.right, z2.boundary.right);
        if (overlapLeft < overlapRight - 5.0) {
          if ((z1.boundary.bottom - z2.boundary.top).abs() <= mullionT + 2.0 ||
              (z2.boundary.bottom - z1.boundary.top).abs() <= mullionT + 2.0) {
            double yCenter = (z1.boundary.bottom + z2.boundary.top) / 2;
            if ((z2.boundary.bottom - z1.boundary.top).abs() <=
                mullionT + 2.0) {
              yCenter = (z2.boundary.bottom + z1.boundary.top) / 2;
            }
            horizontalSegments.add(
              _MullionSegment(
                position: yCenter,
                start: overlapLeft,
                end: overlapRight,
              ),
            );
          }
        }

        // Check for vertical boundary
        double overlapTop = math.max(z1.boundary.top, z2.boundary.top);
        double overlapBottom = math.min(z1.boundary.bottom, z2.boundary.bottom);
        if (overlapTop < overlapBottom - 5.0) {
          if ((z1.boundary.right - z2.boundary.left).abs() <= mullionT + 2.0 ||
              (z2.boundary.right - z1.boundary.left).abs() <= mullionT + 2.0) {
            double xCenter = (z1.boundary.right + z2.boundary.left) / 2;
            if ((z2.boundary.right - z1.boundary.left).abs() <=
                mullionT + 2.0) {
              xCenter = (z2.boundary.right + z1.boundary.left) / 2;
            }
            verticalSegments.add(
              _MullionSegment(
                position: xCenter,
                start: overlapTop,
                end: overlapBottom,
              ),
            );
          }
        }
      }
    }

    final String effectivePrimary = window.primaryMullionAxis ?? 'h';

    List<_MullionSegment> finalH = [];
    List<_MullionSegment> finalV = [];

    if (effectivePrimary == 'h') {
      // Merge horizontal, keep vertical split
      finalH = _mergeMullionSegments(horizontalSegments, mullionT, true);
      finalV = verticalSegments;
    } else {
      // Merge vertical, keep horizontal split
      finalV = _mergeMullionSegments(verticalSegments, mullionT, false);
      finalH = horizontalSegments;
    }

    for (var seg in finalH) {
      double len = (seg.end - seg.start) / 1000.0;
      if (len > 0) {
        mullionPieces.add(len);
        totalMullionLengthMeters += len;
      }
    }

    for (var seg in finalV) {
      double len = (seg.end - seg.start) / 1000.0;
      if (len > 0) {
        mullionPieces.add(len);
        totalMullionLengthMeters += len;
      }
    }

    final sashSection = window.getSectionByType('sash');
    double sashVisibleWidth = sashSection?.visibleWidth ?? 70.0;
    if (sashVisibleWidth == 0.0) sashVisibleWidth = 70.0;

    double overlap = window.sashOverride != null
        ? (window.sashOverride!['sash_overlap'] ?? 8.0).toDouble()
        : 8.0;

    for (var zone in window.zones) {
      if (zone.content == ZoneContent.empty) continue;
      double clearW = zone.boundary.width;
      double clearH = zone.boundary.height;

      double leftSashW = clearW;
      double rightSashW = clearW;
      double verticalLenLeft = clearH;
      double verticalLenRight = clearH;

      if (zone.content == ZoneContent.singleSash) {
        double sashW = clearW + overlap * 2;
        double sashH = clearH + overlap * 2;
        leftSashW = sashW - (sashVisibleWidth * 2);
        rightSashW = leftSashW;
        verticalLenLeft = sashH - (sashVisibleWidth * 2);
        verticalLenRight = verticalLenLeft;
      } else if (zone.content == ZoneContent.doubleSash) {
        double sashWLeft = clearW * zone.doubleSashRatio + overlap;
        double sashWRight = clearW * (1.0 - zone.doubleSashRatio) + overlap;
        double sashH = clearH + overlap * 2;
        leftSashW = sashWLeft - (sashVisibleWidth * 2);
        rightSashW = sashWRight - (sashVisibleWidth * 2);
        verticalLenLeft = sashH - (sashVisibleWidth * 2);
        verticalLenRight = verticalLenLeft;
      } else if (zone.content == ZoneContent.slidingSash) {
        int sashesCount = zone.slidingSashesCount > 0
            ? zone.slidingSashesCount
            : 2;
        double sashW = (clearW + ((sashesCount - 1) * 26.0)) / sashesCount;
        double sashH = clearH + overlap * 2;
        leftSashW = sashW - (sashVisibleWidth * 2);
        rightSashW = leftSashW;
        verticalLenLeft = sashH - (sashVisibleWidth * 2);
        verticalLenRight = verticalLenLeft;
      }

      // التقسيمات الأفقية والعمودية للضلفة اليسرى (أو الوحيدة)
      if (zone.innerH > 0 || zone.innerV > 0) {
        final hPositions = List<double>.from(zone.innerHPositions);
        if (hPositions.isEmpty && zone.innerH > 0) {
          double stepY = 1.0 / (zone.innerH + 1);
          for (int i = 1; i <= zone.innerH; i++) {
            hPositions.add(stepY * i);
          }
        }
        final vPositions = List<double>.from(zone.innerVPositions);
        if (vPositions.isEmpty && zone.innerV > 0) {
          double stepX = 1.0 / (zone.innerV + 1);
          for (int i = 1; i <= zone.innerV; i++) {
            vPositions.add(stepX * i);
          }
        }

        int rows = hPositions.length + 1;
        int cols = vPositions.length + 1;

        final String? primaryAxis = zone.primaryDivisionAxis;
        final String effectivePrimary =
            primaryAxis ?? (zone.innerV > 0 ? 'v' : 'h');
        final double dividerThicknessMm = window.getSectionThickness(
          'mullion',
          fallback: sashVisibleWidth,
        );

        if (effectivePrimary == 'h') {
          // ==========================================
          // Horizontal is Primary (continuous)
          // ==========================================
          if (zone.innerH > 0) {
            for (int h = 0; h < hPositions.length; h++) {
              double pieceStart = -1;
              for (int c = 0; c < cols; c++) {
                bool segActive =
                    zone.disabledHorizontalDivisions["${c}_$h"] != true;
                double leftRatio = c == 0 ? 0.0 : vPositions[c - 1];
                double rightRatio = c == cols - 1 ? 1.0 : vPositions[c];

                if (segActive) {
                  if (pieceStart < 0) pieceStart = leftRatio;
                  bool endPiece =
                      (c == cols - 1) ||
                      (zone.disabledHorizontalDivisions["${c + 1}_$h"] == true);
                  if (endPiece) {
                    double len = (rightRatio - pieceStart) * leftSashW;
                    if (len > 0) {
                      mullionPieces.add(len / 1000.0);
                      totalMullionLengthMeters += len / 1000.0;
                    }
                    pieceStart = -1;
                  }
                } else {
                  pieceStart = -1;
                }
              }
            }
          }

          if (zone.innerV > 0) {
            for (int v = 0; v < vPositions.length; v++) {
              for (int r = 0; r < rows; r++) {
                bool segActive =
                    zone.disabledVerticalDivisions["${r}_$v"] != true;
                if (segActive) {
                  double topRatio = r == 0 ? 0.0 : hPositions[r - 1];
                  double bottomRatio = r == rows - 1 ? 1.0 : hPositions[r];
                  double len = (bottomRatio - topRatio) * verticalLenLeft;

                  // Subtract thickness where it meets active horizontal divisions
                  if (r > 0) {
                    bool hasHAbove =
                        zone.disabledHorizontalDivisions["${v}_${r - 1}"] !=
                            true ||
                        (v < vPositions.length &&
                            zone.disabledHorizontalDivisions["${v + 1}_${r - 1}"] !=
                                true);
                    if (hasHAbove) len -= dividerThicknessMm / 2;
                  }
                  if (r < rows - 1) {
                    bool hasHBelow =
                        zone.disabledHorizontalDivisions["${v}_$r"] != true ||
                        (v < vPositions.length &&
                            zone.disabledHorizontalDivisions["${v + 1}_$r"] !=
                                true);
                    if (hasHBelow) len -= dividerThicknessMm / 2;
                  }

                  if (len > 0) {
                    mullionPieces.add(len / 1000.0);
                    totalMullionLengthMeters += len / 1000.0;
                  }
                }
              }
            }
          }
        } else {
          // ==========================================
          // Vertical is Primary (continuous)
          // ==========================================
          if (zone.innerV > 0) {
            for (int v = 0; v < vPositions.length; v++) {
              double pieceTop = -1;
              for (int r = 0; r < rows; r++) {
                bool segActive =
                    zone.disabledVerticalDivisions["${r}_$v"] != true;
                double topRatio = r == 0 ? 0.0 : hPositions[r - 1];
                double bottomRatio = r == rows - 1 ? 1.0 : hPositions[r];

                if (segActive) {
                  if (pieceTop < 0) pieceTop = topRatio;
                  bool endPiece =
                      (r == rows - 1) ||
                      (zone.disabledVerticalDivisions["${r + 1}_$v"] == true);
                  if (endPiece) {
                    double len = (bottomRatio - pieceTop) * verticalLenLeft;
                    if (len > 0) {
                      mullionPieces.add(len / 1000.0);
                      totalMullionLengthMeters += len / 1000.0;
                    }
                    pieceTop = -1;
                  }
                } else {
                  pieceTop = -1;
                }
              }
            }
          }

          if (zone.innerH > 0) {
            for (int h = 0; h < hPositions.length; h++) {
              for (int c = 0; c < cols; c++) {
                bool segActive =
                    zone.disabledHorizontalDivisions["${c}_$h"] != true;
                if (segActive) {
                  double leftRatio = c == 0 ? 0.0 : vPositions[c - 1];
                  double rightRatio = c == cols - 1 ? 1.0 : vPositions[c];
                  double len = (rightRatio - leftRatio) * leftSashW;

                  // Subtract thickness where it meets active vertical divisions
                  if (c > 0) {
                    bool hasVLeft =
                        zone.disabledVerticalDivisions["${h}_${c - 1}"] !=
                            true ||
                        (h < hPositions.length &&
                            zone.disabledVerticalDivisions["${h + 1}_${c - 1}"] !=
                                true);
                    if (hasVLeft) len -= dividerThicknessMm / 2;
                  }
                  if (c < cols - 1) {
                    bool hasVRight =
                        zone.disabledVerticalDivisions["${h}_$c"] != true ||
                        (h < hPositions.length &&
                            zone.disabledVerticalDivisions["${h + 1}_$c"] !=
                                true);
                    if (hasVRight) len -= dividerThicknessMm / 2;
                  }

                  if (len > 0) {
                    mullionPieces.add(len / 1000.0);
                    totalMullionLengthMeters += len / 1000.0;
                  }
                }
              }
            }
          }
        }
      }

      // التقسيمات الأفقية والعمودية للضلفة اليمنى (doubleSash فقط)
      if (zone.content == ZoneContent.doubleSash &&
          (zone.rightInnerH > 0 || zone.rightInnerV > 0)) {
        final hPositions = List<double>.from(zone.rightInnerHPositions);
        if (hPositions.isEmpty && zone.rightInnerH > 0) {
          double stepY = 1.0 / (zone.rightInnerH + 1);
          for (int i = 1; i <= zone.rightInnerH; i++) {
            hPositions.add(stepY * i);
          }
        }
        final vPositions = List<double>.from(zone.rightInnerVPositions);
        if (vPositions.isEmpty && zone.rightInnerV > 0) {
          double stepX = 1.0 / (zone.rightInnerV + 1);
          for (int i = 1; i <= zone.rightInnerV; i++) {
            vPositions.add(stepX * i);
          }
        }

        int rows = hPositions.length + 1;
        int cols = vPositions.length + 1;

        final String? primaryAxis = zone.rightPrimaryDivisionAxis;
        final String effectivePrimary =
            primaryAxis ?? (zone.rightInnerV > 0 ? 'v' : 'h');
        final double dividerThicknessMm = window.getSectionThickness(
          'mullion',
          fallback: sashVisibleWidth,
        );

        if (effectivePrimary == 'h') {
          // ==========================================
          // Horizontal is Primary (continuous)
          // ==========================================
          if (zone.rightInnerH > 0) {
            for (int h = 0; h < hPositions.length; h++) {
              double pieceStart = -1;
              for (int c = 0; c < cols; c++) {
                bool segActive =
                    zone.disabledHorizontalDivisions["right_${c}_$h"] != true;
                double leftRatio = c == 0 ? 0.0 : vPositions[c - 1];
                double rightRatio = c == cols - 1 ? 1.0 : vPositions[c];

                if (segActive) {
                  if (pieceStart < 0) pieceStart = leftRatio;
                  bool endPiece =
                      (c == cols - 1) ||
                      (zone.disabledHorizontalDivisions["right_${c + 1}_$h"] ==
                          true);
                  if (endPiece) {
                    double len = (rightRatio - pieceStart) * rightSashW;
                    if (len > 0) {
                      mullionPieces.add(len / 1000.0);
                      totalMullionLengthMeters += len / 1000.0;
                    }
                    pieceStart = -1;
                  }
                } else {
                  pieceStart = -1;
                }
              }
            }
          }

          if (zone.rightInnerV > 0) {
            for (int v = 0; v < vPositions.length; v++) {
              for (int r = 0; r < rows; r++) {
                bool segActive =
                    zone.disabledVerticalDivisions["right_${r}_$v"] != true;
                if (segActive) {
                  double topRatio = r == 0 ? 0.0 : hPositions[r - 1];
                  double bottomRatio = r == rows - 1 ? 1.0 : hPositions[r];
                  double len = (bottomRatio - topRatio) * verticalLenRight;

                  // Subtract thickness where it meets active horizontal divisions
                  if (r > 0) {
                    bool hasHAbove =
                        zone.disabledHorizontalDivisions["right_${v}_${r - 1}"] !=
                            true ||
                        (v < vPositions.length &&
                            zone.disabledHorizontalDivisions["right_${v + 1}_${r - 1}"] !=
                                true);
                    if (hasHAbove) len -= dividerThicknessMm / 2;
                  }
                  if (r < rows - 1) {
                    bool hasHBelow =
                        zone.disabledHorizontalDivisions["right_${v}_$r"] !=
                            true ||
                        (v < vPositions.length &&
                            zone.disabledHorizontalDivisions["right_${v + 1}_$r"] !=
                                true);
                    if (hasHBelow) len -= dividerThicknessMm / 2;
                  }

                  if (len > 0) {
                    mullionPieces.add(len / 1000.0);
                    totalMullionLengthMeters += len / 1000.0;
                  }
                }
              }
            }
          }
        } else {
          // ==========================================
          // Vertical is Primary (continuous)
          // ==========================================
          if (zone.rightInnerV > 0) {
            for (int v = 0; v < vPositions.length; v++) {
              double pieceTop = -1;
              for (int r = 0; r < rows; r++) {
                bool segActive =
                    zone.disabledVerticalDivisions["right_${r}_$v"] != true;
                double topRatio = r == 0 ? 0.0 : hPositions[r - 1];
                double bottomRatio = r == rows - 1 ? 1.0 : hPositions[r];

                if (segActive) {
                  if (pieceTop < 0) pieceTop = topRatio;
                  bool endPiece =
                      (r == rows - 1) ||
                      (zone.disabledVerticalDivisions["right_${r + 1}_$v"] ==
                          true);
                  if (endPiece) {
                    double len = (bottomRatio - pieceTop) * verticalLenRight;
                    if (len > 0) {
                      mullionPieces.add(len / 1000.0);
                      totalMullionLengthMeters += len / 1000.0;
                    }
                    pieceTop = -1;
                  }
                } else {
                  pieceTop = -1;
                }
              }
            }
          }

          if (zone.rightInnerH > 0) {
            for (int h = 0; h < hPositions.length; h++) {
              for (int c = 0; c < cols; c++) {
                bool segActive =
                    zone.disabledHorizontalDivisions["right_${c}_$h"] != true;
                if (segActive) {
                  double leftRatio = c == 0 ? 0.0 : vPositions[c - 1];
                  double rightRatio = c == cols - 1 ? 1.0 : vPositions[c];
                  double len = (rightRatio - leftRatio) * rightSashW;

                  // Subtract thickness where it meets active vertical divisions
                  if (c > 0) {
                    bool hasVLeft =
                        zone.disabledVerticalDivisions["right_${h}_${c - 1}"] !=
                            true ||
                        (h < hPositions.length &&
                            zone.disabledVerticalDivisions["right_${h + 1}_${c - 1}"] !=
                                true);
                    if (hasVLeft) len -= dividerThicknessMm / 2;
                  }
                  if (c < cols - 1) {
                    bool hasVRight =
                        zone.disabledVerticalDivisions["right_${h}_$c"] !=
                            true ||
                        (h < hPositions.length &&
                            zone.disabledVerticalDivisions["right_${h + 1}_$c"] !=
                                true);
                    if (hasVRight) len -= dividerThicknessMm / 2;
                  }

                  if (len > 0) {
                    mullionPieces.add(len / 1000.0);
                    totalMullionLengthMeters += len / 1000.0;
                  }
                }
              }
            }
          }
        }
      }
    }

    if (totalMullionLengthMeters > 0) {
      items.add(
        createProfile(
          'تقسيم الزجاج (Mullion)',
          colorName,
          pieces: mullionPieces,
          unit: 'قطاع',
        ),
      );

      if (window.isPVC) {
        items.add(
          createProfile(
            'حديد التقسيم (Renfort Mullion)',
            null,
            pieces: mullionPieces,
            unit: 'قطاع',
          ),
        );
        // Add screws for this reinforcement
        int mullionRenfortScrews = 0;
        for (var p in mullionPieces) {
          mullionRenfortScrews += ((p * 1000.0 / 500.0) + 1).ceilToDouble().toInt();
        }

        int index = items.indexWhere((item) => item.originalName == 'براغي حديد الدعم');
        if (index != -1) {
          final existing = items[index];
          // Since the existing item already has the multiplied quantity, we multiply the new batch here before adding
          items[index] = existing.copyWith(qty: existing.quantity + (mullionRenfortScrews * window.quantity));
        } else {
          items.add(createAccessory('براغي حديد الدعم', qty: mullionRenfortScrews));
        }
      }
    }

    // --- 3.7 حساب إكسسوار الطاسو (Tasso) ---
    int tassoQty = 0;
    // Condition A: In divisions (mullions/transoms)
    final bool canHaveDivisionTasso = window.systemMode != 'sliding' && 
        !(window.system?.name.toLowerCase().contains('tpr') ?? false);
    if (canHaveDivisionTasso) {
      tassoQty += mullionPieces.length * 2;
    }

    // Condition B: PVC window with Shutter and monobloc/integrated frame
    final bool isFrameMonobloc = (window.frameOverride != null) &&
        (window.frameOverride!['name'].toString().contains('Cadre cj') ||
         window.frameOverride!['code'].toString().contains('103') ||
         window.frameOverride!['name'].toString().toLowerCase().contains('monobloc') ||
         window.frameOverride!['code'].toString().toLowerCase().contains('monobloc'));
    
    if (window.isPVC && hasShutter && isFrameMonobloc) {
      tassoQty += 2;
    }

    if (tassoQty > 0) {
      items.add(
        createAccessory(
          'الطاسو (Tasso)',
          qty: tassoQty,
          isActive: true,
        ),
      );
    }

    // =========================================================================
    // --- 4. الزجاج ---
    // الحساب الهندسي الدقيق مع تصحيح خطأ الظلفة المزدوجة ودمج القطع المتشابهة
    // =========================================================================
    double divW =
        window.componentOverrides.containsKey('تقسيم الزجاج (Mullion)')
        ? (window.componentOverrides['تقسيم الزجاج (Mullion)']['visible_width'] ??
                  40.0)
              .toDouble()
        : 40.0;
    if (divW <= 0) divW = 40.0;

    // قائمة مؤقتة لتجميع كل قطع الزجاج قبل الدمج
    List<BomItem> glassItems = [];
    List<double> bardagePieces = [];
    List<double> parcloseSimplePieces = [];
    List<double> parcloseDoublePieces = [];
    List<double> reducteurPieces = [];

    // ===== متغيرات جوانات نظام الفتح (ألمنيوم فقط) =====
    // Vitrage  = Bourrage = parcloseSimple×1 + parcloseDouble×2 (يُحسب في لحظة الإخراج)
    // Frappe   = محيط الظلفة + محيط الإطار (لكل فتحة بها ظلفة)
    // Central  = محيط الإطار (فتحات مزدوجة فقط)
    double swingFrappeSashPerim  = 0.0; // مجموع محيطات الظلفات (متر)
    double swingFrappeFramePerim = 0.0; // مجموع محيطات الإطارات للفتحات ذات الظلفات (متر)
    double swingCentralFramePerim = 0.0; // مجموع محيطات الإطارات للفتحات المزدوجة (متر)

    double getSlatWidthForSpec(GlassSpecification spec) {
      final bardageOverride = window.componentOverrides['البارداج (Bardage)'];
      if (bardageOverride != null) {
        final double vw = ((bardageOverride['visible_width'] ?? bardageOverride['thickness']) as num?)?.toDouble() ?? 0.0;
        if (vw > 0) return vw;
      }
      Map<String, dynamic> dbMatch = <String, dynamic>{};
      if (spec.panneauProductId != null) {
        dbMatch = window.allGlassCache.firstWhere(
          (g) => g['id'] == spec.panneauProductId,
          orElse: () => <String, dynamic>{},
        );
      }
      if (dbMatch.isEmpty && spec.panneauSubtype != null) {
        dbMatch = window.allGlassCache.firstWhere(
          (g) =>
              g['type'].toString().toLowerCase() == 'panneau' &&
              (g['subtype'] ?? '').toString().toLowerCase().contains('bardage'),
          orElse: () => <String, dynamic>{},
        );
      }
      double width = 0.0;
      if (dbMatch.isNotEmpty) {
        width = ((dbMatch['visible_width'] ?? dbMatch['thickness']) as num?)?.toDouble() ?? 0.0;
      }
      return width > 0 ? width : 100.0; // fallback to 100mm
    }
    double totalBaguetteLength = 0.0;
    int totalRosettesCount = 0;
    Map<String, dynamic>? selectedBaguetteProduct;
    Map<String, dynamic>? selectedRosetteProduct;

    for (var zone in window.zones) {

      if (zone.content == ZoneContent.empty) continue;

      // جلب قيمة التداخل من قاعدة البيانات أو الافتراضية
      double overlap = window.sashOverride != null
          ? (window.sashOverride!['sash_overlap'] ?? 8.0).toDouble()
          : 8.0;

      // ✅ التداخل الكلي = التداخل من الجهة اليمنى + الجهة اليسرى
      double totalOverlap = overlap * 2.0;

      double clearW = zone.boundary.width;
      double clearH = zone.boundary.height;

      double baseGw = 0.0;
      double baseGwLeft = 0.0;
      double baseGwRight = 0.0;
      double baseGh = 0.0;
      int sashesCount = 1;
      double videVerre = 10.0;

      // baseGw and baseGh are now calculated below after retrieving glassDeduction for casement windows
      double glassDeduction = 0.0;
      if (window.sashOverride != null) {
        glassDeduction = ((window.sashOverride!['glass_deduction'] ??
            window.sashOverride!['glassDeduction'] ?? 0.0) as num).toDouble();
      } else {
        final sashSec = window.getSectionByType('sash');
        if (sashSec != null) {
          glassDeduction = sashSec.glassDeduction;
        }
      }

      double deductionWidthTerm = - videVerre;
      double deductionHeightTerm = - videVerre;
      if (glassDeduction != 0.0) {
        deductionWidthTerm = (glassDeduction * 2.0) - 4.0;
        deductionHeightTerm = (glassDeduction * 2.0) - 4.0;
      }

      if (zone.content == ZoneContent.fixedGlass) {
        // الزجاج الثابت: يمتد داخل أخدود الإطار مباشرةً
        baseGw = clearW - videVerre;
        baseGh = clearH - videVerre;
      } else if (zone.content == ZoneContent.singleSash) {
        // ظلفة مفردة
        baseGw = (clearW + totalOverlap) - (sw * 2) + deductionWidthTerm;
        baseGh = (clearH + totalOverlap) - (sw * 2) + deductionHeightTerm;

        // جوانات نظام الفتح — ظلفة مفردة
        // Frappe = محيط الظلفة + محيط الإطار
        if (!window.isPVC) {
          final double sashPerimM  = ((baseGw + baseGh) * 2.0) / 1000.0;
          final double framePerimM = ((clearW + clearH) * 2.0) / 1000.0;
          swingFrappeSashPerim  += sashPerimM;
          swingFrappeFramePerim += framePerimM;
        }
      } else if (zone.content == ZoneContent.doubleSash) {
        // ✅ ظلفة مزدوجة — الإصلاح الرياضي:
        //    عرض الظلفة الواحدة = (الفراغ الصافي + totalOverlap + 6 [فراغ الباتمو]) / 2
        //    ثم نخصم عرض الظلفة من الجهتين وفراغ التخليص
        baseGwLeft =
            ((clearW + totalOverlap) * zone.doubleSashRatio) -
            (sw * 2) +
            deductionWidthTerm;
        baseGwRight =
            ((clearW + totalOverlap) * (1.0 - zone.doubleSashRatio)) -
            (sw * 2) +
            deductionWidthTerm;
        baseGh = (clearH + totalOverlap) - (sw * 2) + deductionHeightTerm;
        if (zone.hasSashPlintheBottom) {
          double plintheW = window.componentOverrides.containsKey('بلانت (Plinthe)') 
               ? (window.componentOverrides['بلانت (Plinthe)']['visible_width'] ?? 40.0).toDouble() 
               : 40.0;
          baseGh += sw;
          baseGh -= plintheW;
        }
        sashesCount = 2;

        // جوانات نظام الفتح — ظلفة مزدوجة
        // Frappe   = محيط كل ظلفة + محيط الإطار
        // Central  = محيط الإطار فقط
        if (!window.isPVC) {
          final double ghM  = baseGh / 1000.0;
          final double gwLM = baseGwLeft  / 1000.0;
          final double gwRM = baseGwRight / 1000.0;
          final double framePerimM = ((clearW + clearH) * 2.0) / 1000.0;
          // ظلفة يسرى + ظلفة يمنى
          swingFrappeSashPerim  += (ghM + gwLM) * 2.0;
          swingFrappeSashPerim  += (ghM + gwRM) * 2.0;
          swingFrappeFramePerim += framePerimM; // محيط الإطار مرة واحدة للفتحة
          // جوان وسطي = محيط الإطار
          swingCentralFramePerim += framePerimM;
        }
      } else if (zone.content == ZoneContent.slidingSash) {
        int sashes = zone.slidingSashesCount > 0 ? zone.slidingSashesCount : 2;
        double wForCalc = clearW;
        double hForCalc = clearH;
        if (window.zones.length > 1) {
          final slidingFrame = getSlidingFrameSection();
          double frameT = slidingFrame != null
              ? ((slidingFrame['visible_width'] ?? slidingFrame['thickness']) as num?)?.toDouble() ?? 45.0
              : 45.0;
          wForCalc = clearW - (frameT * 2.0);
          hForCalc = clearH - (frameT * 2.0);
        }
        baseGw =
            ((wForCalc + ((sashes - 1) * 26.0)) / sashes) - (sw * 2) - videVerre;
        baseGh = (hForCalc + 16.0) - (sw * 2) - videVerre;
        sashesCount = sashes;
      }

      // دالة داخلية لإضافة قطعة زجاج مع حساب التقسيمات الداخلية
      void addGlassItem(
        int hDivs,
        int vDivs,
        int multiplier,
        String labelSuffix,
        double customBaseGw,
        bool isRightSash,
      ) {
        // جلب الإحداثيات النسبية للتقسيمات
        List<double> hPositions = isRightSash
            ? zone.rightInnerHPositions
            : zone.innerHPositions;
        List<double> vPositions = isRightSash
            ? zone.rightInnerVPositions
            : zone.innerVPositions;

        // نسخ القوائم محلياً وملئها بالتقسيم المتساوي إذا كانت فارغة وهناك تقسيمات
        List<double> hPos = List.from(hPositions);
        if (hPos.isEmpty && hDivs > 0) {
          double stepY = 1.0 / (hDivs + 1);
          for (int i = 1; i <= hDivs; i++) {
            hPos.add(stepY * i);
          }
        }
        List<double> vPos = List.from(vPositions);
        if (vPos.isEmpty && vDivs > 0) {
          double stepX = 1.0 / (vDivs + 1);
          for (int i = 1; i <= vDivs; i++) {
            vPos.add(stepX * i);
          }
        }

        int rows = hPos.length + 1;
        int cols = vPos.length + 1;

        // مصفوفة لتعقب الخلايا المزارة أثناء الدمج
        final visited = List.generate(
          rows,
          (_) => List.generate(cols, (_) => false),
        );

        String getVKey(int r, int v) {
          if (zone.content == ZoneContent.doubleSash && isRightSash) {
            return "right_${r}_$v";
          }
          return "${r}_$v";
        }

        String getHKey(int c, int h) {
          if (zone.content == ZoneContent.doubleSash && isRightSash) {
            return "right_${c}_$h";
          }
          return "${c}_$h";
        }

        String sidePrefix = zone.content == ZoneContent.doubleSash
            ? (isRightSash ? 'right' : 'main')
            : 'main';
        if (zone.content == ZoneContent.doubleSash && !isRightSash) {
          sidePrefix = 'left';
        }

        // دالة مساعدة داخلية لإنشاء عنصر الزجاج وإضافته
        void addSingleGlassPiece(
          double cellGw,
          double cellGh,
          int pieceMultiplier,
          String cellKey,
        ) {
          if (cellGw <= 0 || cellGh <= 0) return;

          // استخدم مواصفات الزجاج الخاصة بالخلية إن وجدت
          final cellGlass = zone.getGlassForCell(cellKey);
          final isPanneau = cellGlass.structure == GlassStructure.closed ||
              zone.cellIsPanel[cellKey] == true;

          final isBardage = isPanneau &&
              (cellGlass.panneauSubtype?.toLowerCase().contains('bardage') == true ||
               cellGlass.finishOuter == GlassFinish.bardage);

          if (isBardage && window.componentOverrides.containsKey('البارداج (Bardage)')) {
            // البارداج يُحسب كبروفيل طولي في قسم البروفيلات، ولا يُضاف كبانو مساحي
            final double slatW = getSlatWidthForSpec(cellGlass);
            final bool isVertical = cellGlass.isVerticalBardage;
            
            final int slatsCount = isVertical
                ? (cellGw / slatW).ceil()
                : (cellGh / slatW).ceil();
            final double pieceLength = isVertical
                ? (cellGh / 1000.0)
                : (cellGw / 1000.0);

            for (int i = 0; i < slatsCount; i++) {
              for (int q = 0; q < pieceMultiplier; q++) {
                bardagePieces.add(pieceLength);
              }
            }

            // 🟢 البارداج سمكه غليظ (مثلاً 24 مم) فيحتاج باكيت زجاج مزدوج (Double Glazing Parclose)
            for (int q = 0; q < pieceMultiplier; q++) {
              parcloseDoublePieces.add(cellGw / 1000.0);
              parcloseDoublePieces.add(cellGw / 1000.0);
              parcloseDoublePieces.add(cellGh / 1000.0);
              parcloseDoublePieces.add(cellGh / 1000.0);
            }
            return;
          }

          final originalName = isPanneau ? 'البانو' : 'الزجاج';
          int totalPieces = pieceMultiplier * window.quantity;

          // 🟢 تحديد نوع الباكيت المطلوب بناءً على سمك الزجاج الفعلي لهذه الخلية
          final double cellThick = cellGlass.totalThickness(window.allGlassCache);
          if (window.systemMode == 'sliding') {
            if (!isPanneau && cellGlass.structure != GlassStructure.closed) {
              final double reducteurThick = (cellGlass.structure == GlassStructure.simple) ? 15.0 : 0.0;
              if (reducteurThick > 0) {
                for (int q = 0; q < totalPieces; q++) {
                  reducteurPieces.add(cellGw / 1000.0);
                  reducteurPieces.add(cellGw / 1000.0);
                  reducteurPieces.add(cellGh / 1000.0);
                  reducteurPieces.add(cellGh / 1000.0);
                }
              }
              double maxGlass = 24.0;
              final sashMap = (window.slidingSashOverride ?? window.getSectionByType('sash_sliding')) as Map<String, dynamic>?;
              if (sashMap != null) {
                final double mG = (sashMap['max_glass_thickness'] as num?)?.toDouble() ?? 0.0;
                if (mG > 0) maxGlass = mG;
              }
              double remaining = maxGlass - cellThick - reducteurThick;
              if (remaining <= 0) {
                remaining = 2.0; // fallback to ensure glass gasket is calculated
              }
              if (remaining > 0) {
                final double targetThick = cellGlass.jointTwoSides ? (remaining / 2.0) : remaining;
                String jointName = 'جوان الزجاج (Joint Vitrage)';
                final double perimeter = (cellGw * 2 + cellGh * 2) / 1000.0;
                final double qty = perimeter * (cellGlass.jointTwoSides ? 2 : 1) * totalPieces;
                slidingGlassJoints[jointName] = (slidingGlassJoints[jointName] ?? 0.0) + qty;
              }
            }
          } else {
            if (cellThick > 10.0) {
              for (int q = 0; q < pieceMultiplier; q++) {
                parcloseDoublePieces.add(cellGw / 1000.0);
                parcloseDoublePieces.add(cellGw / 1000.0);
                parcloseDoublePieces.add(cellGh / 1000.0);
                parcloseDoublePieces.add(cellGh / 1000.0);
              }
            } else {
              for (int q = 0; q < pieceMultiplier; q++) {
                parcloseSimplePieces.add(cellGw / 1000.0);
                parcloseSimplePieces.add(cellGw / 1000.0);
                parcloseSimplePieces.add(cellGh / 1000.0);
                parcloseSimplePieces.add(cellGh / 1000.0);
              }
            }
          }

          // 🟢 حساب الديكور باجيت والورود لهذه القطعة الفردية
          if (cellGlass.decorH > 0 || cellGlass.decorV > 0) {
            double cellBaguette = (cellGlass.decorH * cellGw + cellGlass.decorV * cellGh) / 1000.0;
            totalBaguetteLength += cellBaguette * totalPieces;

            if (cellGlass.hasRosettes) {
              totalRosettesCount += (cellGlass.decorH * cellGlass.decorV) * totalPieces;
            }

            if (selectedBaguetteProduct == null && cellGlass.decorBaguetteId != null) {
              selectedBaguetteProduct = window.allGlassCache.firstWhere(
                (g) => g['id'] == cellGlass.decorBaguetteId && g['color']?.toString().toLowerCase().trim() == cellGlass.decorColor.toLowerCase().trim(),
                orElse: () => window.allGlassCache.firstWhere(
                  (g) => g['id'] == cellGlass.decorBaguetteId,
                  orElse: () => <String, dynamic>{},
                ),
              );
            }
            if (selectedRosetteProduct == null && cellGlass.decorRosetteId != null) {
              selectedRosetteProduct = window.allGlassCache.firstWhere(
                (g) => g['id'] == cellGlass.decorRosetteId && g['color']?.toString().toLowerCase().trim() == cellGlass.decorColor.toLowerCase().trim(),
                orElse: () => window.allGlassCache.firstWhere(
                  (g) => g['id'] == cellGlass.decorRosetteId,
                  orElse: () => <String, dynamic>{},
                ),
              );
            }
          }

          String glassName = _buildGlassDescription(
            cellGlass,
            window,
            cellGw,
            cellGh,
          );
          if (labelSuffix.isNotEmpty) glassName = "$labelSuffix\n$glassName";

          glassItems.add(
            BomItem(
              category: isPanneau ? 'panneau' : 'glass',
              originalName: originalName,
              name: glassName,
              imagePath: (() {
                if (window.componentOverrides.containsKey(originalName)) {
                  final ov = window.componentOverrides[originalName];
                  return ov['image_path']?.toString();
                }
                return null;
              })(),
              colorName: cellGh.toStringAsFixed(1),
              length: cellGw,
              glassHeight: cellGh,
              quantity: totalPieces.toDouble(),
              unit: 'قطعة',
              unitPrice: (() {
                if (window.componentOverrides.containsKey(originalName)) {
                  final ov = window.componentOverrides[originalName];
                  return ((ov['calculated_price'] ??
                              ov['price'] ??
                              window.calculateTotalGlassPricePerSqmForZoneGlass(cellGlass))
                          as num)
                      .toDouble();
                }
                return window.calculateTotalGlassPricePerSqmForZoneGlass(cellGlass);
              })(),
              isMissing: false,
            ),
          );
        }


        // دمج الخلايا المتجاورة إذا كانت الفواصل معطلة (Greedy cell merging)
        for (int r = 0; r < rows; r++) {
          for (int c = 0; c < cols; c++) {
            if (visited[r][c]) continue;

            int w = 1;
            while (c + w < cols &&
                zone.disabledVerticalDivisions[getVKey(r, c + w - 1)] == true) {
              w++;
            }

            int h = 1;
            while (r + h < rows) {
              bool canMergeRow = true;
              for (int col = c; col < c + w; col++) {
                if (zone.disabledHorizontalDivisions[getHKey(col, r + h - 1)] !=
                    true) {
                  canMergeRow = false;
                  break;
                }
              }
              if (!canMergeRow) break;

              for (int col = c; col < c + w - 1; col++) {
                if (zone.disabledVerticalDivisions[getVKey(r + h, col)] !=
                    true) {
                  canMergeRow = false;
                  break;
                }
              }
              if (!canMergeRow) break;

              h++;
            }

            for (int currR = r; currR < r + h; currR++) {
              for (int currC = c; currC < c + w; currC++) {
                visited[currR][currC] = true;
              }
            }

            double leftRatio = c == 0 ? 0.0 : vPos[c - 1];
            double rightRatio = c + w - 1 == cols - 1 ? 1.0 : vPos[c + w - 1];
            double topRatio = r == 0 ? 0.0 : hPos[r - 1];
            double bottomRatio = r + h - 1 == rows - 1 ? 1.0 : hPos[r + h - 1];

            double left = customBaseGw * leftRatio;
            if (c > 0) left += divW / 2.0;
            double right = customBaseGw * rightRatio;
            if (c + w - 1 < cols - 1) right -= divW / 2.0;

            double top = baseGh * topRatio;
            if (r > 0) top += divW / 2.0;
            double bottom = baseGh * bottomRatio;
            if (r + h - 1 < rows - 1) bottom -= divW / 2.0;

            double cellW = right - left;
            double cellH = bottom - top;

            if (cellW <= 0 || cellH <= 0) continue;

            String cellKey = '${sidePrefix}_cell_${r}_$c';

            bool hasNestedSash = zone.cellIsSash[cellKey] == true;
            bool hasNestedDoubleSash = zone.cellIsDoubleSash[cellKey] == true;

            if (hasNestedSash) {
              double cellSw = sw;
              double cellGd = glassDeduction;
              if (zone.cellSashOverrides[cellKey] != null) {
                cellSw =
                    (zone.cellSashOverrides[cellKey]!['visible_width'] as num?)
                        ?.toDouble() ??
                    sw;
                cellGd = ((zone.cellSashOverrides[cellKey]!['glass_deduction'] ??
                    zone.cellSashOverrides[cellKey]!['glassDeduction'] ?? 0.0) as num).toDouble();
              }
              double cellDeductionW = - videVerre;
              double cellDeductionH = - videVerre;
              if (cellGd != 0.0) {
                cellDeductionW = (cellGd * 2.0) - 4.0;
                cellDeductionH = (cellGd * 2.0) - 4.0;
              }
              // خصم عرض مقطع الظلفة الداخلية والتخليص (videVerre أو rebate)
              double glassW = cellW - (cellSw * 2.0) + cellDeductionW;
              double glassH = cellH - (cellSw * 2.0) + cellDeductionH;
              addSingleGlassPiece(glassW, glassH, multiplier, cellKey);
            } else if (hasNestedDoubleSash) {
              double cellSw = sw;
              double cellGd = glassDeduction;
              if (zone.cellSashOverrides[cellKey] != null) {
                cellSw =
                    (zone.cellSashOverrides[cellKey]!['visible_width'] as num?)
                        ?.toDouble() ??
                    sw;
                cellGd = ((zone.cellSashOverrides[cellKey]!['glass_deduction'] ??
                    zone.cellSashOverrides[cellKey]!['glassDeduction'] ?? 0.0) as num).toDouble();
              }
              double cellDeductionW = - videVerre;
              double cellDeductionH = - videVerre;
              if (cellGd != 0.0) {
                cellDeductionW = (cellGd * 2.0) - 4.0;
                cellDeductionH = (cellGd * 2.0) - 4.0;
              }
              double sep = 4.0;
              // خصم عرض مقطع الظلفة وتخليص الفاصل المزدوج
              double glassW =
                  ((cellW - sep) / 2.0) - (cellSw * 2.0) + cellDeductionW;
              double glassH = cellH - (cellSw * 2.0) + cellDeductionH;
              addSingleGlassPiece(glassW, glassH, multiplier * 2, cellKey);
            } else {
              // زجاج ثابت أو لوح بدون ظلفة داخلية
              double glassW = cellW;
              double glassH = cellH;
              addSingleGlassPiece(glassW, glassH, multiplier, cellKey);
            }
          }
        }
      }

      if (zone.content == ZoneContent.doubleSash) {
        // الظلفة المزدوجة: ظلفة رئيسية وظلفة ثانوية قد تختلف في التقسيمات الداخلية
        bool isLeftMain = (zone.openDirection == OpenDirection.left);
        double gwMain = isLeftMain ? baseGwLeft : baseGwRight;
        double gwSec = isLeftMain ? baseGwRight : baseGwLeft;
        addGlassItem(
          isLeftMain ? zone.innerH : zone.rightInnerH,
          isLeftMain ? zone.innerV : zone.rightInnerV,
          1,
          'الظلفة الرئيسية',
          gwMain,
          !isLeftMain,
        );
        addGlassItem(
          isLeftMain ? zone.rightInnerH : zone.innerH,
          isLeftMain ? zone.rightInnerV : zone.innerV,
          1,
          'الظلفة الثانوية',
          gwSec,
          isLeftMain,
        );
      } else {
        addGlassItem(zone.innerH, zone.innerV, sashesCount, '', baseGw, false);
      }
    }

    // =========================================================================
    // ✅ دمج الزجاجات المتشابهة: نفس الأبعاد + نفس السعر + نفس نوع الاستهلاك (ثابت/ظلفة) + نفس الخصائص → تظهر مرة واحدة
    //    والكمية تُجمع بدلاً من إظهار سطرين منفصلين
    // =========================================================================
    Map<String, BomItem> mergedGlass = {};
    for (var g in glassItems) {
      // المفتاح يعتمد فقط على الأبعاد والسعر — لا على الاسم
      // بهذا تُدمج الظلفة الرئيسية والثانوية إذا كان لهما نفس القياس والسعر
      String key =
          '${g.originalName}_'
          '${g.length?.toStringAsFixed(1)}_'
          '${g.glassHeight?.toStringAsFixed(1)}_'
          '${g.unitPrice.toStringAsFixed(2)}';

      if (mergedGlass.containsKey(key)) {
        // نفس الزجاج موجود مسبقاً → نجمع الكمية فقط
        final existing = mergedGlass[key]!;
        mergedGlass[key] = BomItem(
          category: existing.category,
          originalName: existing.originalName,
          name: _mergeGlassName(existing.name, g.name),
          colorName: existing.colorName,
          length: existing.length,
          glassHeight: existing.glassHeight,
          quantity: existing.quantity + g.quantity,
          unit: existing.unit,
          unitPrice: existing.unitPrice,
          isMissing: existing.isMissing,
        );
      } else {
        mergedGlass[key] = g;
      }
    }

    // ✅ إضافة قطع الزجاج والبانو المدمجة إلى كشف المواد الإجمالي ليظهر في الجدول
    items.addAll(mergedGlass.values);


    // --- 5. الباكيت (Parclose) ---
    final chosenParclose = window.componentOverrides['باكيت الزجاج (Parclose)'];
    Map<String, dynamic>? parcloseSimple;
    Map<String, dynamic>? parcloseDouble;

    final activeSeries = window.activeSeries;
    if (activeSeries != null) {
      if (chosenParclose != null) {
        // المستخدم اختار باكيت محدد — نحدد نوعه ونبحث عن المقابل
        final double maxG = (chosenParclose['max_glass_thickness'] as num?)?.toDouble() ?? 0.0;
        if (maxG > 10.0) {
          parcloseDouble = chosenParclose;
          // البحث عن باكيت السامبل في نفس السلسلة
          try {
            final sampleSec = activeSeries.sections.firstWhere(
              (s) => (s.type.toLowerCase().contains('parclose') || s.name.contains('باكيت')) && s.maxGlassThickness <= 10.0 && s.maxGlassThickness > 0.0,
            );
            parcloseSimple = sampleSec.toMap();
          } catch (_) {
            // إذا لم نجد simple، نستخدم نفس الـ double (أفضل من لا شيء)
            parcloseSimple = chosenParclose;
          }
        } else {
          parcloseSimple = chosenParclose;
          // البحث عن باكيت الدوبل — أولاً عبر الرابط المباشر
          final int? linkedId = chosenParclose['linked_parclose_double_id'] as int?;
          if (linkedId != null && linkedId > 0) {
            try {
              final linkedSec = activeSeries.sections.firstWhere((s) => s.id == linkedId);
              parcloseDouble = linkedSec.toMap();
            } catch (_) {}
          }
          if (parcloseDouble == null) {
            try {
              final doubleSec = activeSeries.sections.firstWhere(
                (s) => (s.type.toLowerCase().contains('parclose') || s.name.contains('باكيت')) && s.maxGlassThickness > 10.0,
              );
              parcloseDouble = doubleSec.toMap();
            } catch (_) {
              // إذا لم نجد double، نستخدم نفس الـ simple
              parcloseDouble = chosenParclose;
            }
          }
        }
      } else {
        // لم يختر المستخدم — بحث تلقائي في السلسلة المحملة
        try {
          final simpleSec = activeSeries.sections.firstWhere(
            (s) => (s.type.toLowerCase().contains('parclose') || s.name.contains('باكيت')) && s.maxGlassThickness <= 10.0 && s.maxGlassThickness > 0.0,
          );
          parcloseSimple = simpleSec.toMap();
        } catch (_) {
          // لا يوجد باكيت simple في السلسلة
        }
        try {
          final doubleSec = activeSeries.sections.firstWhere(
            (s) => (s.type.toLowerCase().contains('parclose') || s.name.contains('باكيت')) && s.maxGlassThickness > 10.0,
          );
          parcloseDouble = doubleSec.toMap();
        } catch (_) {
          // لا يوجد باكيت double في السلسلة
        }
      }
    }

    if (parcloseSimplePieces.isNotEmpty) {
      final targetOverride = parcloseSimple ?? chosenParclose;
      if (targetOverride != null) {
        items.add(
          createProfile(
            'باكيت زجاج مفرد (Parclose Simple)',
            colorName,
            pieces: parcloseSimplePieces,
            unit: 'قطاع',
            overrideMap: targetOverride,
          ),
        );
      }
    }

    if (parcloseDoublePieces.isNotEmpty) {
      final targetOverride = parcloseDouble ?? chosenParclose;
      if (targetOverride != null) {
        items.add(
          createProfile(
            'باكيت زجاج مزدوج (Parclose Double)',
            colorName,
            pieces: parcloseDoublePieces,
            unit: 'قطاع',
            overrideMap: targetOverride,
          ),
        );
      }
    }

    // ===== جوانات نظام الفتح (ألمنيوم فقط) =====
    if (!window.isPVC) {
      // حساب الكميات المشتركة بين Vitrage و Bourrage
      final double simplePerim = parcloseSimplePieces.fold(0.0, (s, p) => s + p); // محيط زجاج مفرد (×1)
      final double doublePerim = parcloseDoublePieces.fold(0.0, (s, p) => s + p); // محيط زجاج مزدوج (×2)
      final double vitrageQty  = simplePerim * 1.0 + doublePerim * 2.0;

      // Joint Vitrage = محيط الزجاج ×1 (مفرد) أو ×2 (مزدوج)
      if (vitrageQty > 0) {
        items.add(
          createJoint(
            'جوان الزجاج (Joint Vitrage)',
            qty: vitrageQty,
            unit: 'متر',
          ),
        );
      }

      // Joint Bourrage = نفس Joint Vitrage تماماً
      if (vitrageQty > 0) {
        items.add(
          createJoint(
            'جوان البوراج (Joint Bourrage)',
            qty: vitrageQty,
            unit: 'متر',
          ),
        );
      }

      // Joint Frappe = محيط الظلفة + محيط الإطار
      final double frappeQty = swingFrappeSashPerim + swingFrappeFramePerim;
      if (frappeQty > 0) {
        items.add(
          createJoint(
            'جوان الضرب (Joint Frappe)',
            qty: (frappeQty * 1000).ceil() / 1000.0,
            unit: 'متر',
          ),
        );
      }

      // Joint Central = محيط الإطار (فتحات مزدوجة فقط)
      if (swingCentralFramePerim > 0) {
        items.add(
          createJoint(
            'جوان الوسط (Joint Central)',
            qty: (swingCentralFramePerim * 1000).ceil() / 1000.0,
            unit: 'متر',
          ),
        );
      }
    }

    if (reducteurPieces.isNotEmpty) {
      items.add(
        createProfile(
          'ريديكتور (Réducteur)',
          colorName,
          pieces: reducteurPieces,
          unit: 'قطاع',
          overrideMap: window.componentOverrides['ريديكتور (Réducteur)'],
        ),
      );
    }

    // =========================================================================
    // --- 4.6 البارداج كبروفيل (Bardage Profile) ---
    // =========================================================================
    if (bardagePieces.isNotEmpty && window.componentOverrides.containsKey('البارداج (Bardage)')) {
      items.add(
        createProfile(
          'البارداج (Bardage)',
          colorName,
          pieces: bardagePieces,
          unit: 'قطاع',
        ),
      );
    }


    // =========================================================================


    if (selectedBaguetteProduct == null || selectedBaguetteProduct!.isEmpty) {
      selectedBaguetteProduct = window.allGlassCache.firstWhere(
        (g) => g['type'].toString().toLowerCase().contains('baguette'),
        orElse: () => <String, dynamic>{},
      );
    }
    if (selectedRosetteProduct == null || selectedRosetteProduct!.isEmpty) {
      selectedRosetteProduct = window.allGlassCache.firstWhere(
        (g) => g['type'].toString().toLowerCase().contains('rosette'),
        orElse: () => <String, dynamic>{},
      );
    }

    if (totalBaguetteLength > 0 && selectedBaguetteProduct != null && selectedBaguetteProduct!.isNotEmpty) {
      double baguettePrice = (selectedBaguetteProduct!['price_per_sqm'] as num?)?.toDouble() ?? 0.0;
      String bName = selectedBaguetteProduct!['name'].toString();
      String thickness = selectedBaguetteProduct!['thickness']?.toString() ?? '';
      String thicknessText = thickness.isNotEmpty ? 'حجم: $thickness مم - ' : '';
      items.add(
        BomItem(
          category: 'glass',
          originalName: 'باجيت ديكور',
          name: 'باجيت ديكور\n$thicknessText$bName',
          colorName: colorName,
          length: totalBaguetteLength,
          quantity: totalBaguetteLength,
          unit: 'متر',
          unitPrice: baguettePrice,
          isMissing: false,
        ),
      );
    }

    if (totalRosettesCount > 0 && selectedRosetteProduct != null && selectedRosetteProduct!.isNotEmpty) {
      double rosettePrice = (selectedRosetteProduct!['price_per_sqm'] as num?)?.toDouble() ?? 0.0;
      String rName = selectedRosetteProduct!['name'].toString();
      String size = selectedRosetteProduct!['size']?.toString() ?? '';
      String sizeText = size.isNotEmpty ? 'مقاس: $size - ' : '';
      items.add(
        BomItem(
          category: 'glass',
          originalName: 'وردة ديكور',
          name: 'وردة ديكور\n$sizeText$rName',
          colorName: colorName,
          quantity: totalRosettesCount.toDouble(),
          unit: 'قطعة',
          unitPrice: rosettePrice,

          isMissing: false,
        ),
      );
    }

    // Do NOT filter out items that are not in the database (isMissing == true)
    // We want them to display in the table with a warning icon so the user can easily swap/map them
    for (int i = 0; i < items.length; i++) {
      final item = items[i];
      if (item.category == 'profile') {
        String? code = item.profileCode;
        String? path = item.imagePath;

        if (code == null || code.isEmpty || path == null || path.isEmpty) {
          String? type;
          final orig = item.originalName.toLowerCase();
          if (orig.contains('إطار') || orig.contains('frame') || orig.contains('cadre')) {
            type = 'frame';
          } else if (orig.contains('ظلفة') || orig.contains('sash') || orig.contains('ouvrant')) {
            type = 'sash';
          } else if (orig.contains('بلانت') || orig.contains('plinthe')) {
            type = 'plinthe';
          } else if (orig.contains('عرضي') || orig.contains('traverse')) {
            type = 'sash_traverse';
          } else if (orig.contains('تقسيم') || orig.contains('mullion')) {
            type = 'mullion';
          } else if (orig.contains('باركوز') || orig.contains('parclose')) {
            type = 'parclose';
          } else if (orig.contains('باتمو') || orig.contains('batmo')) {
            type = 'batmo';
          } else if (orig.contains('شيكان') || orig.contains('chicane')) {
            type = 'chicane';
          }

          if (type != null) {
            final sec = window.getSectionByType(type);
            if (sec != null) {
              code ??= sec.code;
              path ??= sec.imagePath;
            }
          }
        }

        if ((code != null && code != item.profileCode) || (path != null && path != item.imagePath)) {
          items[i] = item.copyWith(
            profileCode: code,
            imagePath: path,
          );
        }
      }
    }
    return items;
  }

  /// دمج أسماء قطع الزجاج عند تشابه أبعادها:
  /// إذا كان الاسمان متطابقين → نبقيه كما هو.
  /// إذا كانا مختلفين (مثلاً ظلفة رئيسية / ثانوية) → نحذف التسمية ونبقي وصف الزجاج فقط.
  static String _mergeGlassName(String existingName, String newName) {
    if (existingName == newName) return existingName;

    // نحاول استخراج جزء وصف الزجاج (السطر الذي يبدأ بـ "زجاج")
    final lines = existingName.split('\n');
    final glassDescLines = lines.where(
      (l) =>
          l.trimLeft().startsWith('زجاج') ||
          l.trimLeft().startsWith('القياس') ||
          l.trimLeft().startsWith('-'),
    );
    if (glassDescLines.isNotEmpty) {
      return glassDescLines.join('\n');
    }
    return existingName;
  }

  static String _buildGlassDescription(
    GlassSpecification glass,
    WindowModel window,
    double gw,
    double gh,
  ) {
    String dimText =
        'القياس (العرض × الارتفاع): ${gw.toStringAsFixed(1)} × ${gh.toStringAsFixed(1)} ملم';
    String result;
    if (glass.structure == GlassStructure.simple) {
      double thickness = glass.thicknessOuter ?? window.getThicknessForFinish(
        glass.finishOuter,
        glass.colorOuter,
      );
      double price = window.calculateTotalGlassPricePerSqmForZoneGlass(glass);
      String namePart = "";
      if (glass.processingOuter == GlassProcessing.laminated) {
        String lamCol = "شفاف";
        if (glass.laminatedColorOuter == 'white') lamCol = "أبيض";
        else if (glass.laminatedColorOuter == 'blue') lamCol = "أزرق";
        namePart = "مورق ($lamCol)";
      } else {
        String outerFinish = window.getFinishName(glass.finishOuter).trim();
        String outerColor = window.getArabicColorName(glass.colorOuter).trim();
        namePart = outerFinish == outerColor
            ? outerFinish
            : '$outerFinish $outerColor';
      }
      if (glass.processingOuter == GlassProcessing.tempered || glass.temperedOuter) {
        namePart += ' + مقص (Trempé)';
      }
      result = 'زجاج مفرد\n${thickness.toStringAsFixed(0)}مم: $namePart (${price.toStringAsFixed(0)} دج/م²)\n$dimText';
    } else if (glass.structure == GlassStructure.closed) {
      double price = window.calculateTotalGlassPricePerSqmForZoneGlass(glass);
      
      String getArabicSubtypeName(String sub) {
        final s = sub.toLowerCase();
        if (s.contains('resine') || s.contains('ارزين') || s.contains('أرزين')) return 'ارزين';
        if (s.contains('plexi')) return 'بليكسي';
        if (s.contains('decore') || s.contains('ديكور')) return 'بانو ديكور';
        if (s.contains('sandwitch') || s.contains('sandwich') || s == 'panneau' || s == 'بانو') return 'بانو';
        if (s.contains('aluco') || s.contains('الوكو')) return 'الوكو';
        if (s.contains('bardage') || s.contains('بارداش')) return 'بارداش';
        return sub;
      }
      
      String subtype = getArabicSubtypeName(glass.panneauSubtype ?? window.getFinishName(glass.finishOuter));
      String color = glass.panneauColor ?? window.getClosedColoreName(glass.colorP);
      result = 'بانو (Panneau)\n- النوع: $subtype - اللون: $color (${price.toStringAsFixed(0)} دج/م²)\n$dimText';
    } else {
      double intercallPrice = window.getPriceForIntercall(
        glass.intercallThickness,
      );
      double gasPrice = glass.hasGas
          ? window.getPriceForGas(glass.intercallThickness)
          : 0.0;

      double innerThickness = glass.thicknessInner ?? window.getThicknessForFinish(
        glass.finishInner,
        glass.colorInner,
      );
      double outerThickness = glass.thicknessOuter ?? window.getThicknessForFinish(
        glass.finishOuter,
        glass.colorOuter,
      );
      double intercallThickness = glass.intercallThickness.toDouble();
      double totalThickness =
          innerThickness + outerThickness + intercallThickness;

      double totalSqmPrice = window.calculateTotalGlassPricePerSqmForZoneGlass(glass);

      String outDesc = "";
      if (glass.processingOuter == GlassProcessing.laminated) {
        String lamCol = "شفاف";
        if (glass.laminatedColorOuter == 'white') lamCol = "أبيض";
        else if (glass.laminatedColorOuter == 'blue') lamCol = "أزرق";
        outDesc = "مورق ($lamCol)";
      } else {
        String outerFinish = window.getFinishName(glass.finishOuter).trim();
        final outC = window.getArabicColorName(glass.colorOuter).trim();
        outDesc = outerFinish == outC ? outerFinish : '$outerFinish $outC';
      }
      if (glass.processingOuter == GlassProcessing.tempered || glass.temperedOuter) {
        outDesc += ' + مقص (Trempé)';
      }

      String inDesc = "";
      if (glass.processingInner == GlassProcessing.laminated) {
        String lamCol = "شفاف";
        if (glass.laminatedColorInner == 'white') lamCol = "أبيض";
        else if (glass.laminatedColorInner == 'blue') lamCol = "أزرق";
        inDesc = "مورق ($lamCol)";
      } else {
        String innerFinish = window.getFinishName(glass.finishInner).trim();
        final inC = window.getArabicColorName(glass.colorInner).trim();
        inDesc = innerFinish == inC ? innerFinish : '$innerFinish $inC';
      }
      if (glass.processingInner == GlassProcessing.tempered || glass.temperedInner) {
        inDesc += ' + مقص (Trempé)';
      }

      String desc =
          'زجاج مزدوج ${totalThickness.toStringAsFixed(0)}مم\n'
          '- خارجي: ${outerThickness.toStringAsFixed(0)}مم، $outDesc\n'
          '- داخلي: ${innerThickness.toStringAsFixed(0)}مم، $inDesc\n'
          '- فاصل: ${intercallThickness.toStringAsFixed(0)}مم (${intercallPrice.toStringAsFixed(0)} دج)';

      if (glass.hasGas) {
        desc += '\n- غاز: نعم (${gasPrice.toStringAsFixed(0)} دج)';
      }

      desc +=
          '\n- سعر المتر المربع: ${totalSqmPrice.toStringAsFixed(0)} دج\n$dimText';
      result = desc;
    }

    // Append decoration details (baguette and rosette) if configured
    if (glass.decorH > 0 || glass.decorV > 0) {
      String decorText = '\n- ديكور داخلي: ${glass.decorH}×${glass.decorV}';
      if (glass.decorColor.isNotEmpty) {
        decorText += ' (اللون: ${glass.decorColor})';
      }
      if (glass.hasRosettes) {
        decorText += ' - مع ورود الديكور (Rosettes)';
      }
      result += decorText;
    }

    final totalT = glass.totalThickness(window.allGlassCache);
    // مطابقة سمك الزجاج مع الباكيت المناسب
    // نستخدم max_glass_thickness من DB مباشرة دون عتبة ثابتة.
    final isDouble = totalT > 10.0;
    Map<String, dynamic>? matchingParclose;
    final chosenParclose = window.componentOverrides['باكيت الزجاج (Parclose)'];
    final activeSeries = window.activeSeries;

    if (activeSeries != null) {
      // جمع كل باركلوزات السلسلة وترتيبها
      final allParcloseSections = activeSeries.sections.where((s) =>
        (s.type.toLowerCase().contains('parclose') || s.name.contains('باكيت')) &&
        s.maxGlassThickness > 0.0,
      ).toList();
      allParcloseSections.sort((a, b) => a.maxGlassThickness.compareTo(b.maxGlassThickness));

      if (allParcloseSections.isNotEmpty) {
        if (chosenParclose != null) {
          // المستخدم اختار — نحدد هل المختار يتطابق سمك الزجاج
          final double chosenMax = (chosenParclose['max_glass_thickness'] as num?)?.toDouble() ?? 0.0;
          // هل المختار simple أو double بالمقارنة مع أصغر max متاح
          final double seriesMinMax = allParcloseSections.first.maxGlassThickness;
          final bool chosenIsSimple = (chosenMax <= seriesMinMax) || allParcloseSections.length == 1;
          final bool chosenMatchesGlass = isDouble ? !chosenIsSimple : chosenIsSimple;

          if (chosenMatchesGlass) {
            matchingParclose = chosenParclose;
          } else {
            // المختار لا يتطابق — نبحث عن المناسب في السلسلة
            if (isDouble) {
              // نحتاج double — آخر واحد بأكبر max
              matchingParclose = allParcloseSections.last.toMap();
            } else {
              // نحتاج simple — أول واحد بأصغر max
              matchingParclose = allParcloseSections.first.toMap();
            }
          }
        } else {
          // لم يختر — بحث تلقائي
          if (isDouble) {
            matchingParclose = allParcloseSections.last.toMap();
          } else {
            matchingParclose = allParcloseSections.first.toMap();
          }
        }
      } else if (chosenParclose != null) {
        // السلسلة ليس فيها باركلوز — المختار يُستخدم
        matchingParclose = chosenParclose;
      }
    } else if (chosenParclose != null) {
      matchingParclose = chosenParclose;
    }

    if (matchingParclose != null) {
      final double maxG = (matchingParclose['max_glass_thickness'] as num?)?.toDouble() ?? 0.0;
      if (maxG > 0) {
        final bool isClosed = glass.structure == GlassStructure.closed;
        final String label = isClosed ? 'البانو' : 'الزجاج';
        if (totalT > maxG) {
          result += '\n⚠️ تنبيه: سمك $label ($totalT مم) أكبر من سعة البيركلوز (${matchingParclose['name']}) ($maxG مم)';
        } else if (totalT < maxG - 2.0) {
          result += '\n⚠️ تنبيه: سمك $label ($totalT مم) أصغر من سعة البيركلوز (${matchingParclose['name']}) ($maxG مم)';
        }
      }
    }
    return result;
  }

  static BomItem _createProfile(
    Map<String, dynamic> overrides,
    String originalName,
    String? color, {
    String unit = 'قطاع',
    double defaultPrice = 0,
    double qty = 0,
    double? length,
    List<double>? pieces,
    Map<String, dynamic>? overrideMap,
  }) {
    bool isLinked = overrideMap != null
        ? true
        : overrides.containsKey(originalName);
    double price = defaultPrice;
    double finalQty = qty;
    double? finalLength = length;
    String? cuttingListText;
    String? profileCode;
    String? imagePath;
    String subName = '';
    if (isLinked) {
      final ov = overrideMap ?? overrides[originalName];
      profileCode = ov['code']?.toString();
      imagePath = ov['image_path']?.toString();
      subName = '${ov['code'] ?? ''} - ${ov['name']}'.trim();
      if (subName.startsWith('- ')) subName = subName.substring(2);
      price = (ov['calculated_price'] ?? ov['price'] ?? defaultPrice).toDouble();
    }
    double? exactBars;
    if (pieces != null && pieces.isNotEmpty) {
      double barLength = 5.8;
      if (isLinked) {
        final ov = overrideMap ?? overrides[originalName];
        barLength = (ov['bar_length'] as num?)?.toDouble() ?? 5.8;
      } else if (originalName.contains('حديد') ||
          originalName.contains('Renfort')) {
        barLength = 6.0;
      }
 
      final optimization = optimizeCutting(
        pieces: pieces,
        barLength: barLength,
      );
      exactBars = optimization['exactBars'];
      int optimizedBars = optimization['optimizedBars'];
 
      finalQty = optimizedBars.toDouble();
      finalLength = barLength;
 
      // Format cutting list
      Map<int, int> counts = {};
      for (double p in pieces) {
        int mm = (p * 1000).round();
        if (mm <= 0) continue;
        counts[mm] = (counts[mm] ?? 0) + 1;
      }
      List<int> sortedMm = counts.keys.toList()..sort((a, b) => b.compareTo(a));
      List<String> parts = [];
      for (int mm in sortedMm) {
        parts.add('${counts[mm]} × $mm مم');
      }
      cuttingListText = 'قطع القص: ${parts.join(' ، ')}';
    }
 
    // Build the final display name:
    String name = originalName;
    if (subName.isNotEmpty) {
      name += '\n$subName';
    }
    if (exactBars != null) {
      name += '\n(المطلوب الفعلي: ${exactBars.toStringAsFixed(2)} بارة / ${exactBars.toStringAsFixed(2)} bar)';
    }
 
    if (isLinked && (finalLength == null || finalLength == 0.0)) {
      final ov = overrideMap ?? overrides[originalName];
      finalLength = (ov['bar_length'] as num?)?.toDouble() ?? 5.8;
    }
 
    return BomItem(
      category: 'profile',
      originalName: originalName,
      profileCode: profileCode,
      name: name,
      imagePath: imagePath,
      colorName: color,
      length: finalLength ?? 0.0,
      quantity: finalQty,
      exactQuantity: exactBars ?? finalQty,
      unit: unit,
      unitPrice: price,
      isMissing: !isLinked,
      pieces: pieces,
      cuttingList: cuttingListText,
    );
  }

  static BomItem _createAccessory(
    Map<String, dynamic> overrides,
    String originalName, {
    bool isActive = true,
    String? color,
    int qty = 0,
  }) {
    String lookupKey = originalName;
    if (!overrides.containsKey(lookupKey) && lookupKey.startsWith('إسبانيوليت ') && lookupKey.endsWith(' (Espagnolette)')) {
      lookupKey = 'إسبانيوليت (Espagnolette)';
    }
    bool isLinked = overrides.containsKey(lookupKey);
    String name = originalName;
    double price = 0.0;
    String? profileCode;
    String? imagePath;
    if (isLinked) {
      final ov = overrides[lookupKey];
      profileCode = ov['code']?.toString();
      imagePath = ov['image_path']?.toString();
      final code = ov['code'] ?? '';
      final cName = ov['name'] ?? originalName;
      final details = code.toString().isNotEmpty ? '$code - $cName' : cName;
      name = '$originalName\n$details';
      price =
          (ov['calculated_price'] ??
                  ov['price'] ??
                  0.0)
              .toDouble();
    }
    return BomItem(
      category: 'accessory',
      originalName: originalName,
      profileCode: profileCode,
      name: name,
      imagePath: imagePath,
      colorName: color,
      quantity: qty.toDouble(),
      unit: 'حبة',
      unitPrice: price,
      isMissing: !isLinked,
      isActive: isActive,
    );
  }

  static BomItem _createOther(
    Map<String, dynamic> overrides,
    String originalName, {
    bool isActive = true,
    String? color,
    int qty = 0,
  }) {
    String lookupKey = originalName;
    bool isLinked = overrides.containsKey(lookupKey);
    String name = originalName;
    double price = 0.0;
    String? profileCode;
    String? imagePath;
    if (isLinked) {
      final ov = overrides[lookupKey];
      profileCode = ov['code']?.toString();
      imagePath = ov['image_path']?.toString();
      final code = ov['code'] ?? '';
      final cName = ov['name'] ?? originalName;
      final details = code.toString().isNotEmpty ? '$code - $cName' : cName;
      name = '$originalName\n$details';
      price =
          (ov['calculated_price'] ??
                  ov['price'] ??
                  0.0)
              .toDouble();
    }
    return BomItem(
      category: 'other',
      originalName: originalName,
      profileCode: profileCode,
      name: name,
      imagePath: imagePath,
      colorName: color,
      quantity: qty.toDouble(),
      unit: 'حبة',
      unitPrice: price,
      isMissing: !isLinked,
      isActive: isActive,
    );
  }

  static BomItem _createInteractiveAccessory(
    Map<String, dynamic> overrides,
    String originalName,
    String group, {
    bool isActive = false,
    double qty = 1,
    String? kitGroupName,
    String category = 'accessory',
  }) {
    String lookupKey = originalName;
    if (!overrides.containsKey(lookupKey) && lookupKey.startsWith('إسبانيوليت ') && lookupKey.endsWith(' (Espagnolette)')) {
      lookupKey = 'إسبانيوليت (Espagnolette)';
    }
    bool isLinked = overrides.containsKey(lookupKey);
    String name = originalName;
    double price = 0.0;
    String? profileCode;
    String? imagePath;
    if (isLinked) {
      final ov = overrides[lookupKey];
      profileCode = ov['code']?.toString();
      imagePath = ov['image_path']?.toString();
      final code = ov['code'] ?? '';
      final cName = ov['name'] ?? originalName;
      final details = code.toString().isNotEmpty ? '$code - $cName' : cName;
      name = '$originalName\n$details';
      price =
          (ov['calculated_price'] ??
                  ov['price'] ??
                  0.0)
              .toDouble();
    }
    return BomItem(
      category: category,
      originalName: originalName,
      profileCode: profileCode,
      name: name,
      imagePath: imagePath,
      quantity: qty,
      unit: 'حبة',
      unitPrice: price,
      isMissing: !isLinked,
      isInteractive: true,
      isActive: isActive,
      exclusionGroup: group,
      kitGroupName: kitGroupName,
    );
  }

  static BomItem _createJoint(
    Map<String, dynamic> overrides,
    String originalName, {
    String? color,
    double qty = 0,
    String unit = 'متر',
  }) {
    bool isLinked = overrides.containsKey(originalName);
    String name = originalName;
    double price = 0.0;
    String? profileCode;
    String? imagePath;
    if (isLinked) {
      final ov = overrides[originalName];
      profileCode = ov['code']?.toString();
      imagePath = ov['image_path']?.toString();
      final code = ov['code'] ?? '';
      final cName = ov['name'] ?? originalName;
      final details = code.toString().isNotEmpty ? '$code - $cName' : cName;
      name = '$originalName\n$details';
      price =
          (ov['price_per_meter'] ??
                  ov['calculated_price'] ??
                  0.0)
              .toDouble();
    }
    return BomItem(
      category: 'joint',
      originalName: originalName,
      profileCode: profileCode,
      name: name,
      imagePath: imagePath,
      colorName: color,
      quantity: qty,
      unit: unit,
      unitPrice: price,
      isMissing: !isLinked,
      isActive: true,
    );
  }

  static BomItem _createShutter(
    Map<String, dynamic> overrides,
    String originalName, {
    String? color,
    double qty = 0,
    String unit = 'حبة',
    List<double>? pieces,
    String? kitGroupName,
    double? windowWidth,
    double? windowHeight,
    int windowQuantity = 1,
  }) {
    bool isLinked = overrides.containsKey(originalName);
    String name = originalName;
    double price = 0.0;
    double finalQty = qty;
    double? finalLength;
    String? cuttingListText;
    String? profileCode;
    String? imagePath;

    if (isLinked) {
      final ov = overrides[originalName];
      profileCode = ov['code']?.toString();
      imagePath = ov['image_path']?.toString();
      name = '${ov['code'] ?? ''} - ${ov['name']}'.trim();
      if (name.startsWith('- ')) name = name.substring(2);
      price = (ov['calculated_price'] ?? ov['price'] ?? 0.0).toDouble();
    }

    bool isSqmOrLinear = false;
    String finalUnit = unit;
    if (isLinked) {
      final ov = overrides[originalName];
      final dbUnit = (ov['unit'] ?? '').toString().toLowerCase().trim();

      if (dbUnit == 'sqm') {
        finalUnit = 'م²';
        isSqmOrLinear = true;
        if (windowWidth != null && windowHeight != null) {
          final double areaSqm = (windowWidth / 1000.0) * (windowHeight / 1000.0);
          finalQty = areaSqm * windowQuantity;
        }
      } else if (dbUnit == 'm' || dbUnit == 'ml' || dbUnit == 'linear') {
        finalUnit = 'متر';
        isSqmOrLinear = true;
        if (pieces != null && pieces.isNotEmpty) {
          finalQty = pieces.fold(0.0, (sum, p) => sum + p);
        }
      } else if (dbUnit == 'pcs' || dbUnit == 'pc' || dbUnit == 'piece') {
        finalUnit = 'حبة';
      }
    }

    if (pieces != null && pieces.isNotEmpty) {
      double barLength = 5.8;
      if (isLinked) {
        final ov = overrides[originalName];
        double? dbLen =
            (ov['bar_length_m'] as num?)?.toDouble() ??
            (ov['bar_length'] as num?)?.toDouble();
        if (dbLen != null && dbLen > 0) {
          barLength = dbLen;
        }
      }

      final optimization = optimizeCutting(
        pieces: pieces,
        barLength: barLength,
      );
      double exactBars = optimization['exactBars'];
      int optimizedBars = optimization['optimizedBars'];

      if (!isSqmOrLinear) {
        finalQty = optimizedBars.toDouble();
      }
      finalLength = barLength;

      // Append subtext to name
      name = "$name\n(المطلوب الفعلي: ${exactBars.toStringAsFixed(2)} قطاع)";

      // Format cutting list
      Map<int, int> counts = {};
      for (double p in pieces) {
        int mm = (p * 1000).round();
        if (mm <= 0) continue;
        counts[mm] = (counts[mm] ?? 0) + 1;
      }
      List<int> sortedMm = counts.keys.toList()..sort((a, b) => b.compareTo(a));
      List<String> parts = [];
      for (int mm in sortedMm) {
        parts.add('${counts[mm]} × $mm مم');
      }
      cuttingListText = 'قطع القص: ${parts.join(' ، ')}';
    }
    if (isLinked && (finalLength == null || finalLength == 0.0)) {
      final ov = overrides[originalName];
      finalLength =
          (ov['bar_length_m'] as num?)?.toDouble() ??
          (ov['bar_length'] as num?)?.toDouble() ??
          5.8;
    }

    return BomItem(
      category: 'shutter',
      originalName: originalName,
      profileCode: profileCode,
      name: name,
      imagePath: imagePath,
      colorName: color,
      length: finalLength,
      quantity: finalQty,
      unit: finalUnit,
      unitPrice: price,
      isMissing: !isLinked,
      pieces: pieces,
      cuttingList: cuttingListText,
      kitGroupName: kitGroupName,
    );
  }

  static Map<String, dynamic>? findReinforcedSection(
    Map<String, dynamic> baseSection,
    bool isCentral,
    WindowModel window,
  ) {
    final activeSeries = window.activeSlidingSeries ?? window.activeSeries;
    if (activeSeries == null) return null;
    final String baseCode = baseSection['code']?.toString() ?? '';

    String? targetSuffix;
    if (isCentral) {
      if (baseCode.endsWith('105')) targetSuffix = '107';
    } else {
      if (baseCode.endsWith('104')) targetSuffix = '108';
    }

    if (targetSuffix != null) {
      try {
        final sec = activeSeries.sections.firstWhere((s) => s.code.endsWith(targetSuffix!));
        return sec.toMap();
      } catch (_) {}
    }

    try {
      final sec = activeSeries.sections.firstWhere((s) {
        final name = s.name.toLowerCase();
        final type = s.type.toLowerCase();
        final isMatch = isCentral
            ? (name.contains('central') || name.contains('chicane') || name.contains('وسطي'))
            : (name.contains('lateral') || name.contains('جانبي'));
        final isRenforced = name.contains('renforc') || name.contains('renforcé') || name.contains('معزز') || type.contains('renforc');
        return isMatch && isRenforced;
      });
      return sec.toMap();
    } catch (_) {}

    return null;
  }

  static Map<String, dynamic>? findNormalSection(
    Map<String, dynamic> baseSection,
    bool isCentral,
    WindowModel window,
  ) {
    final activeSeries = window.activeSlidingSeries ?? window.activeSeries;
    if (activeSeries == null) return null;
    final String baseCode = baseSection['code']?.toString() ?? '';

    String? targetSuffix;
    if (isCentral) {
      if (baseCode.endsWith('107')) targetSuffix = '105';
    } else {
      if (baseCode.endsWith('108')) targetSuffix = '104';
    }

    if (targetSuffix != null) {
      try {
        final sec = activeSeries.sections.firstWhere((s) => s.code.endsWith(targetSuffix!));
        return sec.toMap();
      } catch (_) {}
    }

    try {
      final sec = activeSeries.sections.firstWhere((s) {
        final name = s.name.toLowerCase();
        final type = s.type.toLowerCase();
        final isMatch = isCentral
            ? (name.contains('central') || name.contains('chicane') || name.contains('وسطي'))
            : (name.contains('lateral') || name.contains('جانبي'));
        final isNormal = !name.contains('renforc') && !name.contains('renforcé') && !name.contains('معزز') && !type.contains('renforc');
        return isMatch && isNormal;
      });
      return sec.toMap();
    } catch (_) {}

    return null;
  }
}

class _MullionSegment {
  final double position;
  final double start;
  final double end;

  _MullionSegment({
    required this.position,
    required this.start,
    required this.end,
  });
}

List<_MullionSegment> _mergeMullionSegments(
  List<_MullionSegment> segments,
  double thickness,
  bool isHorizontal,
) {
  if (segments.isEmpty) return [];

  List<_MullionSegment> sorted = List.from(segments);
  sorted.sort((a, b) {
    int cmp = a.position.compareTo(b.position);
    if (cmp != 0) return cmp;
    return a.start.compareTo(b.start);
  });

  List<_MullionSegment> merged = [];
  _MullionSegment current = sorted[0];

  for (int i = 1; i < sorted.length; i++) {
    _MullionSegment next = sorted[i];

    if ((next.position - current.position).abs() < 2.0 &&
        next.start <= current.end + thickness + 5.0) {
      current = _MullionSegment(
        position: current.position,
        start: current.start,
        end: math.max(current.end, next.end),
      );
    } else {
      merged.add(current);
      current = next;
    }
  }
  merged.add(current);
  return merged;
}
