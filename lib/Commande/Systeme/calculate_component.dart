// Force compile sync trigger 4
import 'package:database_data/Commande/Systeme/model.dart';
import 'package:database_data/Commande/Systeme/cutting_settings.dart';
import 'dart:math' as math;

class BomItem {
  final String category;
  final String originalName;
  final String? profileCode;
  final String name;
  final String? imagePath;
  final String? colorName;
  final double? length;
  final double? glassHeight;
  final double quantity;
  final String unit;
  final double unitPrice;
  final bool isMissing;

  final bool isInteractive;
  final bool isActive;
  final String? exclusionGroup;
  final List<double>? pieces;
  final String? cuttingList;
  final String? kitGroupName; // اسم Kit التابع له (مثال: System OB)
  final double? exactQuantity;
  final int? catalogItemId;
  final String? inventoryItemType;
  final int? colorId;
  final String? overrideKey;
  final String? selectorCategory;
  final String? selectorType;
  final String? roleKey;
  final int? sourceSeriesId;
  final String? materialType;
  final double? targetThicknessMm;

  /// Quantity actually required for pricing. For profiles this can be a
  /// fractional number of bars, unlike the rounded purchase quantity.
  double get requiredQuantity => exactQuantity ?? quantity;

  /// Quantity that must actually be purchased or reserved from stock.
  ///
  /// Costing can use a fractional consumption such as 1.20 bars, but stock
  /// cannot provide a fraction of a bar/profile. Count-based catalogue units
  /// therefore always round up: 1.20 profiles become 2 profiles.
  double get purchaseQuantity {
    if (quantity <= 0) return 0;
    final normalizedUnit = unit.toLowerCase().trim();
    final requiresWholeUnits =
        category == 'profile' ||
        const <String>{
          'قطاع',
          'بارة',
          'قطعة',
          'حبة',
          'طقم',
          'kit',
          'pcs',
          'pc',
          'piece',
          'bar',
          'section',
        }.contains(normalizedUnit);
    return requiresWholeUnits
        ? (quantity - 0.000000001).ceilToDouble()
        : quantity;
  }

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
    this.catalogItemId,
    this.inventoryItemType,
    this.colorId,
    this.overrideKey,
    this.selectorCategory,
    this.selectorType,
    this.roleKey,
    this.sourceSeriesId,
    this.materialType,
    this.targetThicknessMm,
  }) : this.name = name.replaceAll(RegExp(r'\s*\(\s*جودة[^)]*\)'), '').trim();

  double get exactTotal {
    if (!isActive) return 0.0;
    // Glass rows expressed in m² already carry their total surface in
    // `quantity`. Multiplying again by the width and height made a double
    // glazing row behave as if it contained only part of one pane.
    if (category == 'glass' && unit == 'م²') {
      return requiredQuantity * unitPrice;
    }
    if (category == 'glass' && length != null && glassHeight != null) {
      double w = length! / 1000.0;
      double h = glassHeight! / 1000.0;
      return requiredQuantity * w * h * unitPrice;
    }
    return requiredQuantity * unitPrice;
  }

  double get total {
    if (!isActive) return 0.0;
    // See exactTotal: surface-based glass must be priced directly from its
    // accumulated square metres. Each different glass composition remains a
    // separate BOM row with its own per-square-metre price.
    if (category == 'glass' && unit == 'م²') {
      return requiredQuantity * unitPrice;
    }
    if (category == 'glass' && length != null && glassHeight != null) {
      double w = length! / 1000.0;
      double h = glassHeight! / 1000.0;
      return requiredQuantity * w * h * unitPrice;
    }
    return requiredQuantity * unitPrice;
  }

  String getLocalizedName(String lang) {
    final original = originalName;
    if (lang == 'fr') {
      if (original == 'قائم جانبي معزز (Sash Lateral Renforcé)') {
        return 'Sash Latéral Renforcé';
      }
      if (original == 'قائم وسطي معزز (Sash Central Renforcé)') {
        return 'Sash Central Renforcé';
      }
      if (original == 'حديد التقسيم (Renfort Mullion)') {
        return 'Renfort Traverse / Montant';
      }
      if (original == 'حديد الباطمو (Renfort Batmo)') {
        return 'Renfort Battement';
      }
      if (original == 'الزجاج') return 'Vitrage';
      if (original.contains('إطار') ||
          original.contains('Frame') ||
          original.contains('Cadre') ||
          original.contains('Dormant')) {
        return original
            .replaceAll('إطار', 'Dormant')
            .replaceAll('Frame', 'Dormant')
            .replaceAll('Cadre', 'Dormant');
      }
      if (original.contains('الظلفة') ||
          original.contains('Sash') ||
          original.contains('Ouvrant')) {
        return original
            .replaceAll('الظلفة', 'Ouvrant')
            .replaceAll('Sash', 'Ouvrant');
      }
      if (original.contains('عرضي') || original.contains('Traverse')) {
        return original.replaceAll('عرضي', 'Traverse');
      }
      if (original.contains('قائم جانبي') ||
          original.contains('Sash Lateral') ||
          original.contains('Lateral')) {
        return original
            .replaceAll('قائم جانبي', 'Sash Latéral')
            .replaceAll('Sash Lateral', 'Sash Latéral');
      }
      if (original.contains('قائم وسطي') ||
          original.contains('Sash Central') ||
          original.contains('Central')) {
        return original
            .replaceAll('قائم وسطي', 'Sash Central')
            .replaceAll('Sash Central', 'Sash Central');
      }
      if (original.contains('الشيكان') || original.contains('Chicane')) {
        return original.replaceAll('الشيكان', 'Chicane');
      }
      if (original.contains('الري') || original.contains('Rail')) {
        return original.replaceAll('الري', 'Rail');
      }
      if (original.contains('سكة الظلفة') ||
          original.contains('Sash Traverse')) {
        return original
            .replaceAll('سكة الظلفة', 'Traverse Ouvrant')
            .replaceAll('Sash Traverse', 'Traverse Ouvrant');
      }
      if (original.contains('بلانت الظلفة') ||
          original.contains('Plinthe Sash')) {
        return original
            .replaceAll('بلانت الظلفة', 'Plinthe Ouvrant')
            .replaceAll('Plinthe Sash', 'Plinthe Ouvrant');
      }
      if (original.contains('الباتمو') || original.contains('Batmo')) {
        return original.replaceAll('الباتمو', 'Meneau');
      }
      if (original.contains('بوشون باتمو') ||
          original.contains('Bouchon Batmo')) {
        return original.replaceAll('بوشون باتمو', 'Bouchon Meneau');
      }
      if (original.contains('حديد الإطار') ||
          original.contains('Renfort Frame')) {
        return original
            .replaceAll('حديد الإطار', 'Renfort Dormant')
            .replaceAll('Renfort Frame', 'Renfort Dormant');
      }
      if (original.contains('حديد الظلفة') ||
          original.contains('Renfort Sash')) {
        return original
            .replaceAll('حديد الظلفة', 'Renfort Ouvrant')
            .replaceAll('Renfort Sash', 'Renfort Ouvrant');
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
      if (original.contains('إسبانيوليت') ||
          original.contains('Espagnolette')) {
        return 'Espagnolette';
      }
      if (original == 'المقبض (Handle)') return 'Poignée Fenêtre';
      if (original == 'مقبض منزلق (Poignée Coulissante)') {
        return 'Poignée Coulissante';
      }
      if (original == 'مقبض الباب (Poignée Porte à Clé)') {
        return 'Poignée Porte à Clé';
      }
      if (original == 'قفل الباب (Serrure)') return 'Serrure';
      if (original == 'الأسطوانة (Canon)') return 'Canon';
      if (original == 'قاش بورت (Gache Porte)') return 'Gâche Porte';
      if (original == 'المفاصل (Hinges)') return 'Paumelles';
      if (original == 'عجلات المنزلق (Roulettes)') return 'Roulettes';
      if (original == 'اسبانيولات المنزلق (Espagnolette)') {
        return 'Espagnolette Coulissant';
      }
      if (original == 'كاش كوليسون (Gache coulissant)') {
        return 'Gâche Coulissante';
      }
      if (original == 'Gâche coulissant TPR') return 'Gâche Coulissante TPR';
      if (original == 'كريمون (Cremone)') return 'Crémone';
      if (original == 'تراينغل الكريمون (Triangle)') return 'Tringle crémone';
      if (original == 'بوشون بارك لوز (Bouchon Parclose)') {
        return 'Bouchon Parclose';
      }
      if (original == 'قفل نقطة') return 'Serrure à point';
    } else if (lang == 'en') {
      if (original == 'قائم جانبي معزز (Sash Lateral Renforcé)') {
        return 'Sash Lateral Reinforced';
      }
      if (original == 'قائم وسطي معزز (Sash Central Renforcé)') {
        return 'Sash Central Reinforced';
      }
      if (original == 'حديد التقسيم (Renfort Mullion)') {
        return 'Renfort Mullion';
      }
      if (original == 'حديد الباطمو (Renfort Batmo)') return 'Renfort Batmo';
      if (original == 'الزجاج') return 'Glass';
      if (original.contains('إطار') ||
          original.contains('Frame') ||
          original.contains('Cadre') ||
          original.contains('Dormant')) {
        return original
            .replaceAll('إطار', 'Frame')
            .replaceAll('Cadre', 'Frame')
            .replaceAll('Dormant', 'Frame');
      }
      if (original.contains('الظلفة') ||
          original.contains('Sash') ||
          original.contains('Ouvrant')) {
        return original
            .replaceAll('الظلفة', 'Sash')
            .replaceAll('Ouvrant', 'Sash');
      }
      if (original.contains('عرضي') || original.contains('Traverse')) {
        return original.replaceAll('عرضي', 'Traverse');
      }
      if (original.contains('قائم جانبي') ||
          original.contains('Sash Lateral') ||
          original.contains('Lateral')) {
        return original.replaceAll('قائم جانبي', 'Sash Lateral');
      }
      if (original.contains('قائم وسطي') ||
          original.contains('Sash Central') ||
          original.contains('Central')) {
        return original.replaceAll('قائم وسطي', 'Sash Central');
      }
      if (original.contains('الشيكان') || original.contains('Chicane')) {
        return 'Chicane';
      }
      if (original.contains('الري') || original.contains('Rail')) {
        return 'Rail';
      }
      if (original.contains('سكة الظلفة') ||
          original.contains('Sash Traverse')) {
        return 'Sash Traverse';
      }
      if (original.contains('بلانت الظلفة') ||
          original.contains('Plinthe Sash')) {
        return 'Plinthe Sash';
      }
      if (original.contains('الباتمو') || original.contains('Batmo')) {
        return 'Batmo';
      }
      if (original.contains('بوشون باتمو') ||
          original.contains('Bouchon Batmo')) {
        return 'Bouchon Batmo';
      }
      if (original.contains('حديد الإطار') ||
          original.contains('Renfort Frame')) {
        return 'Renfort Frame';
      }
      if (original.contains('حديد الظلفة') ||
          original.contains('Renfort Sash')) {
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
      if (original.contains('إسبانيوليت') ||
          original.contains('Espagnolette')) {
        return 'Espagnolette';
      }
      if (original == 'المقبض (Handle)') return 'Window Handle';
      if (original == 'مقبض منزلق (Poignée Coulissante)') {
        return 'Sliding Window Handle';
      }
      if (original == 'مقبض الباب (Poignée Porte à Clé)') return 'Door Handle';
      if (original == 'قفل الباب (Serrure)') return 'Serrure (Lock)';
      if (original == 'الأسطوانة (Canon)') return 'Cylinder (Canon)';
      if (original == 'قاش بورت (Gache Porte)') return 'Door Strike Plate';
      if (original == 'المفاصل (Hinges)') return 'Hinges';
      if (original == 'عجلات المنزلق (Roulettes)') return 'Roulettes';
      if (original == 'اسبانيولات المنزلق (Espagnolette)') {
        return 'Espagnolette';
      }
      if (original == 'كاش كوليسون (Gache coulissant)') return 'Strike Plate';
      if (original == 'Gâche coulissant TPR') return 'Strike Plate TPR';
      if (original == 'كريمون (Cremone)') return 'Cremone';
      if (original == 'تراينغل الكريمون (Triangle)') return 'Cremone Tringle';
      if (original == 'بوشون بارك لوز (Bouchon Parclose)') {
        return 'Bouchon Parclose';
      }
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
    int? catalogItemId,
    String? inventoryItemType,
    int? colorId,
    String? overrideKey,
    String? selectorCategory,
    String? selectorType,
    String? roleKey,
    int? sourceSeriesId,
    String? materialType,
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
      catalogItemId: catalogItemId ?? this.catalogItemId,
      inventoryItemType: inventoryItemType ?? this.inventoryItemType,
      colorId: colorId ?? this.colorId,
      overrideKey: overrideKey ?? this.overrideKey,
      selectorCategory: selectorCategory ?? this.selectorCategory,
      selectorType: selectorType ?? this.selectorType,
      roleKey: roleKey ?? this.roleKey,
      sourceSeriesId: sourceSeriesId ?? this.sourceSeriesId,
      materialType: materialType ?? this.materialType,
      targetThicknessMm: targetThicknessMm ?? this.targetThicknessMm,
    );
  }
}

class ComponentCalculator {
  static bool _textHasAny(String value, Iterable<String> needles) {
    final lower = value.toLowerCase();
    for (final needle in needles) {
      final normalizedNeedle = needle.toLowerCase();
      if (value.contains(needle) || lower.contains(normalizedNeedle)) {
        return true;
      }
    }
    return false;
  }

  static String _selectorTypeForProfile(String originalName) {
    if (_textHasAny(originalName, const [
      'إطار',
      'frame',
      'cadre',
      'dormant',
    ])) {
      return 'frame';
    }
    if (_textHasAny(originalName, const [
      'الغطاء الجانبي',
      'side cover',
      'couvre joint',
      'couvre-joint',
    ])) {
      return 'side_cover';
    }
    if (_textHasAny(originalName, const [
      'قائم جانبي',
      'sash lateral',
      'ouvrant laterale',
      'ouvrant latérale',
      'lateral',
      'latéral',
    ])) {
      return 'sash_lateral';
    }
    if (_textHasAny(originalName, const [
      'قائم وسطي',
      'sash central',
      'ouvrant central',
      'central',
    ])) {
      return 'sash_central';
    }
    if (_textHasAny(originalName, const [
      'سكة الظلفة',
      'sash traverse',
      'traverse ouvrant',
      'traverse haut',
      'traverse bas',
    ])) {
      return 'sash_traverse';
    }
    if (_textHasAny(originalName, const ['الظلفة', 'sash', 'ouvrant'])) {
      return 'sash';
    }
    if (_textHasAny(originalName, const [
      'حديد',
      'الدعم',
      'renfort',
      'renfore',
    ])) {
      return 'renfort';
    }
    if (_textHasAny(originalName, const ['traverse', 'تقسيم', 'mullion'])) {
      return 'mullion';
    }
    if (_textHasAny(originalName, const ['batmo', 'باتمو'])) {
      return 'batmo';
    }
    if (_textHasAny(originalName, const ['plinthe', 'بلانت'])) {
      return 'plant';
    }
    if (_textHasAny(originalName, const [
      'porte-joint',
      'porte joint',
      'حامل الجوان',
    ])) {
      return 'porte_joint';
    }
    if (_textHasAny(originalName, const [
      'triangle',
      'تراينغل',
      'تريانغل',
      'مثلث',
    ])) {
      return 'triangle';
    }
    if (_textHasAny(originalName, const [
      'reducteur',
      'réducteur',
      'ريديكتور',
      'مخفض',
    ])) {
      return '67114';
    }
    if (_textHasAny(originalName, const ['parclose', 'باكيت', 'بيركلوز'])) {
      if (_textHasAny(originalName, const ['منزلق', 'coulissant', 'sliding'])) {
        if (_textHasAny(originalName, const ['مزدوج', 'double'])) {
          return 'sliding_parclose_double';
        }
        if (_textHasAny(originalName, const ['مفرد', 'simple'])) {
          return 'sliding_parclose_simple';
        }
      }
      if (_textHasAny(originalName, const ['مزدوج', 'double'])) {
        return 'parclose_double';
      }
      if (_textHasAny(originalName, const ['مفرد', 'simple'])) {
        return 'parclose_simple';
      }
      return 'parclose';
    }
    if (_textHasAny(originalName, const ['rail', 'الري'])) {
      return 'rail';
    }
    return originalName;
  }

  static String _selectorTypeForAccessory(String originalName) {
    final lower = originalName.toLowerCase();
    final isScrew =
        originalName.contains('براغي') ||
        originalName.contains('برغي') ||
        lower.contains('screw') ||
        lower.contains('vis');
    if (isScrew && _textHasAny(originalName, const ['حديد الدعم', 'renfort'])) {
      return 'is_renfort_screw';
    }
    if (isScrew &&
        _textHasAny(originalName, const ['بوشون باتمو', 'bouchon batmo'])) {
      return 'is_bouchon_batmo_screw';
    }
    if (isScrew && _textHasAny(originalName, const ['الباتمو', 'batmo'])) {
      return 'is_batmo_screw';
    }
    if (isScrew && _textHasAny(originalName, const ['الكيت', 'kit'])) {
      return 'is_kit_screw';
    }
    if (isScrew &&
        _textHasAny(originalName, const ['المانيفال', 'manivelle'])) {
      return 'is_manivelle_screw';
    }
    if (isScrew &&
        _textHasAny(originalName, const ['المحرك', 'moteur', 'motor'])) {
      return 'is_moteur_screw';
    }
    if (isScrew &&
        _textHasAny(originalName, const ['الصندوق', 'caisson', 'box'])) {
      return 'is_caisson_screw';
    }
    if (isScrew && _textHasAny(originalName, const ['التجميع', 'assembly'])) {
      return 'is_assembly_screw';
    }
    if (isScrew &&
        _textHasAny(originalName, const ['التركيب', 'installation'])) {
      return 'is_installation_screw';
    }
    if (isScrew &&
        _textHasAny(originalName, const ['الإكسسوارات', 'accessory'])) {
      return 'is_accessory_screw';
    }
    if (isScrew) return 'is_accessory_screw';
    if (_textHasAny(originalName, const ['بوشون باتمو', 'bouchon batmo'])) {
      return 'bouchon_batmo';
    }
    if (_textHasAny(originalName, const [
      'kit 67000',
      'kit 76000',
      'kit 40000',
      'كيت 67000',
      'كيت 76000',
      'كيت 40000',
    ])) {
      return 'sliding_kit';
    }
    if (_textHasAny(originalName, const ['clamp', 'clam', 'كلامب', 'كلام'])) {
      return 'clamp';
    }
    if (_textHasAny(originalName, const ['قاش دوبل', 'gache double'])) {
      return 'is_gache_double';
    }
    if (_textHasAny(originalName, const ['قاش سامبل', 'gache simple'])) {
      return 'is_gache_simple';
    }
    if (_textHasAny(originalName, const ['قاش بورت', 'gache porte'])) {
      return 'is_gache_porte';
    }
    if (_textHasAny(originalName, const [
      'gache coulisse',
      'gâche coulisse',
      'gache coulissant',
      'gâche coulissant',
      'كاش كوليسون',
    ])) {
      return 'كاش كوليسون';
    }
    if (_textHasAny(originalName, const [
      'poignée coulissante',
      'poignee coulissante',
      'مقبض منزلق',
    ])) {
      return 'poignee coulissante';
    }
    if (_textHasAny(originalName, const ['poignée porte à clé'])) {
      return 'is_poign_clef';
    }
    if (_textHasAny(originalName, const [
      'serrure condamnation',
      'قفل الباب condamnation',
    ])) {
      return 'is_lock_condamnation';
    }
    if (_textHasAny(originalName, const ['condamnation'])) {
      return 'is_poign_condamnation';
    }
    if (_textHasAny(originalName, const ['canon', 'الأسطوانة'])) {
      return 'is_canon';
    }
    if (_textHasAny(originalName, const ['قفل بمفتاح', 'clef'])) {
      return 'is_lock_clef';
    }
    if (_textHasAny(originalName, const ['serrure'])) return 'is_lock_clef';
    if (_textHasAny(originalName, const ['اسبانيوليت', 'إسبانيوليت'])) {
      return 'اسبانيوليت';
    }
    if (_textHasAny(originalName, const ['مفاصل', 'hinges'])) return 'مفاصل';
    if (_textHasAny(originalName, const ['فيرو', 'verrou'])) return 'فيرو';
    if (_textHasAny(originalName, const [
      'tringle',
      'tangle',
      'triangle',
      'تراينغل',
      'تريانغل',
    ])) {
      return 'tringle';
    }
    if (_textHasAny(originalName, const ['كريمون', 'cremone', 'crémone'])) {
      return 'cremone';
    }
    if (_textHasAny(originalName, const [
      'المقبض (handle)',
      'مقبض نافذة',
      'poignée fenêtre',
      'poignee fenetre',
    ])) {
      return 'is_window_handle';
    }
    if (_textHasAny(originalName, const ['مقبض', 'handle', 'poignée'])) {
      return 'مقبض';
    }
    if (_textHasAny(originalName, const ['الطاسو', 'tasso'])) return 'tasso';
    if (_textHasAny(originalName, const ['عجلات', 'roulette'])) {
      return 'roulette';
    }
    if (_textHasAny(originalName, const [
      'أونتروماتيك',
      'entrematique',
      'انتراميتيك',
      'intra',
    ])) {
      return 'entrematique';
    }
    return originalName;
  }

  static String _selectorTypeForShutter(String originalName) {
    if (_textHasAny(originalName, const ['براغي'])) {
      return _selectorTypeForAccessory(originalName);
    }
    if (_textHasAny(originalName, const ['مانيفال', 'manivelle'])) {
      return 'مانيفال';
    }
    if (_textHasAny(originalName, const ['محرك', 'moteur'])) return 'محرك';
    if (_textHasAny(originalName, const ['صندوق', 'caisson'])) return 'صندوق';
    if (_textHasAny(originalName, const ['كيت', 'kit'])) return 'كيت';
    if (_textHasAny(originalName, const ['سكك', 'coulisse'])) return 'سكك';
    if (_textHasAny(originalName, const ['lame finale', 'نهائية'])) {
      return 'شريحة نهائية';
    }
    if (_textHasAny(originalName, const ['شرائح', 'lame'])) return 'شريحة';
    if (_textHasAny(originalName, const ['محور', 'axe'])) return 'محور';
    if (_textHasAny(originalName, const ['أطاش', 'attache'])) return 'أطاش';
    if (_textHasAny(originalName, const [
      'سيبور موتور',
      'support_moteur',
      'support moteur',
    ])) {
      return 'سيبور موتور';
    }
    if (_textHasAny(originalName, const ['الامبو', 'embout'])) {
      return 'الامبو';
    }
    if (_textHasAny(originalName, const [
      'سيبور رولمو',
      'support_roulement',
      'support roulement',
    ])) {
      return 'سيبور رولمو';
    }
    if (_textHasAny(originalName, const [
      'أغطية الشفرات',
      'bouchons lames',
      'bouchon lame',
    ])) {
      return 'أغطية الشفرات';
    }
    return originalName;
  }

  static String _selectorTypeForJoint(String originalName) {
    if (_textHasAny(originalName, const ['بروس', 'bross', 'brosse'])) {
      return 'Joint bross';
    }
    if (_textHasAny(originalName, const ['bronze', 'برونز'])) {
      return 'joint bronze';
    }
    if (_textHasAny(originalName, const ['vitrage', 'فيتراج'])) {
      return 'joint de vitrage';
    }
    if (_textHasAny(originalName, const ['bourrage', 'بوراج'])) {
      return 'joint bourrage';
    }
    if (_textHasAny(originalName, const ['frappe', 'فراب', 'ضرب'])) {
      return 'joint frappe';
    }
    if (_textHasAny(originalName, const ['centrale', 'central', 'سنترال'])) {
      return 'joint centrale';
    }
    return originalName;
  }

  static String? _roleKeyForProfileSelector(String selectorType) {
    switch (selectorType.toLowerCase().trim()) {
      case 'frame':
        return 'frame';
      case 'sash':
        return 'sash';
      case 'sash_lateral':
        return 'sash_lateral';
      case 'sash_central':
        return 'sash_central';
      case 'sash_traverse':
        return 'sash_traverse';
      case 'mullion':
        return 'mullion';
      case 'parclose':
      case 'parclose_simple':
      case 'parclose_double':
      case 'sliding_parclose_simple':
      case 'sliding_parclose_double':
        return 'glazing_bead';
      case '67114':
        return 'reducer';
      case 'side_cover':
        return 'side_cover';
      case 'rail':
        return 'rail';
      case 'batmo':
        return 'batmo';
      case 'plant':
        return 'plant';
      case 'porte_joint':
        return 'porte_joint';
      case 'triangle':
        return 'triangle';
      case 'renfort':
        return 'renfort';
      case 'other_profile':
        return 'other_profile';
    }
    return null;
  }

  static String? _roleKeyForAccessorySelector(String selectorType) {
    switch (selectorType.toLowerCase().trim()) {
      case 'is_kit_screw':
        return 'kit_screw';
      case 'is_caisson_screw':
        return 'box_screw';
      case 'is_moteur_screw':
        return 'motor_screw';
      case 'is_batmo_screw':
        return 'batmo_screw';
      case 'is_bouchon_batmo_screw':
        return 'bouchon_batmo_screw';
      case 'bouchon_batmo':
      case 'bouchon batmo':
        return 'bouchon_batmo';
      case 'is_renfort_screw':
        return 'renfort_screw';
      case 'is_manivelle_screw':
        return 'manivelle_screw';
      case 'is_assembly_screw':
        return 'assembly_screw';
      case 'is_accessory_screw':
        return 'accessory_screw';
      case 'is_installation_screw':
        return 'installation_screw';
      case 'sliding_kit':
        return 'sliding_kit';
      case 'clamp':
        return 'sliding_clamp';
      case 'is_gache_simple':
        return 'gache_simple';
      case 'is_gache_double':
        return 'gache_double';
      case 'is_gache_porte':
        return 'gache_door';
      case 'كاش كوليسون':
        return 'sliding_lock';
      case 'poignee coulissante':
        return 'handle';
      case 'فيرو':
      case 'verrou':
        return 'verrou';
      case 'is_lock_clef':
        return 'lock_clef';
      case 'is_lock_condamnation':
        return 'lock_condamnation';
      case 'is_poign_clef':
        return 'door_handle_key';
      case 'is_poign_condamnation':
        return 'door_handle_condamnation';
      case 'is_canon':
        return 'canon';
      case 'اسبانيوليت':
        return 'espagnolette';
      case 'cremone':
        return 'cremone';
      case 'tringle':
        return 'tringle';
      case 'tasso':
        return 'tasso';
      case 'roulette':
        return 'roulette';
      case 'entrematique':
        return 'entrematique';
    }
    return null;
  }

  static String? _roleKeyForJointSelector(String selectorType) {
    switch (selectorType.toLowerCase().trim()) {
      case 'joint de vitrage':
        return 'joint_vitrage';
      case 'joint bourrage':
        return 'joint_bourrage';
      case 'joint frappe':
        return 'joint_frappe';
      case 'joint centrale':
        return 'joint_central';
      case 'joint bross':
        return 'joint_brosse';
      case 'joint bronze':
        return 'joint_bronze';
    }
    return null;
  }

  static String? _roleKeyForShutterSelector(String selectorType) {
    final lower = selectorType.toLowerCase().trim();
    if (lower == 'كيت') return 'kit';
    if (lower == 'صندوق') return 'caisson';
    if (lower == 'سكك') return 'coulisse';
    if (lower == 'شريحة') return 'lame';
    if (lower == 'شريحة نهائية') return 'lame_finale';
    if (lower == 'محور') return 'axe';
    if (lower == 'محرك') return 'moteur';
    if (lower == 'مانيفال') return 'manivelle';
    return _roleKeyForAccessorySelector(selectorType);
  }

  static bool _profileSelectorUsesSlidingSeries(
    WindowModel window,
    String selectorType,
  ) {
    final lower = selectorType.toLowerCase().trim();

    // 1. هل يحتوي الرسم على أي منطقة/خلية سحاب (سواء النافذة كاملة سحاب أو جزء منها)؟
    final bool hasSlidingZones = window.zones.any(
      (z) => z.content == ZoneContent.slidingSash,
    );
    final bool isEntireWindowSliding = window.systemMode == 'sliding';

    // 2. إذا كانت النافذة بالكامل من نوع سحاب، فجميع قطاعاتها الأساسية تتبع سلسلة السحاب
    if (isEntireWindowSliding) {
      return true;
    }

    // 3. التعرف المرن على أي قطاع سحاب حصري (شامل لكل اللغات والأنظمة: سكة، شيكان، قوائم، مونوراي...)
    final bool isExplicitSlidingProfile =
        lower.contains('sliding') ||
        lower.contains('couliss') ||
        lower.contains('rail') ||
        lower.contains('chicane') ||
        lower.contains('monorail') ||
        lower == 'sash_lateral' ||
        lower == 'sash_central' ||
        lower == 'sash_traverse';

    if (isExplicitSlidingProfile) {
      return true;
    }

    // 4. معالجة النوافذ المختلطة (نافذة عادية بها ضلفة سحاب PVC موحدة sash):
    // إذا كان الرسم يحتوي على منطقة سحاب، والقطاع المطلوب هو ضلفة (sash) أو سكة أو شيكان
    if (hasSlidingZones && (lower == 'sash' || lower.contains('sash'))) {
      return true;
    }

    // في باقي الحالات (إطار النافذة الأساسي المفصلي، القواطع المفصلية، إلخ)
    return false;
  }

  //دورها هو الإجابة عن سؤال: "ما هو الرقم المعرّف (ID) للسلسلة في قاعدة البيانات التي يجب أن نسحب منها هذا البروفيل بالتحديد؟"
  static int? _sourceSeriesIdForProfile(
    WindowModel window,
    String selectorType,
  ) {
    return _profileSelectorUsesSlidingSeries(window, selectorType)
        ? (window.activeSlidingSeries?.id ?? window.activeSeries?.id)
        : window.activeSeries?.id;
  }

  // هذه الدالة _materialTypeForProfile هي "محدّد مادة تصنيع القطاع" (Material Resolver)،
  // ودورها هو الإجابة عن سؤال حاسم: "هل هذا القطاع المحدد مصنوع من الألمنيوم
  static String _materialTypeForProfile(
    WindowModel window,
    String selectorType,
  ) {
    return _profileSelectorUsesSlidingSeries(window, selectorType)
        ? (window.isSlidingPVC ? 'pvc' : 'aluminium')
        : (window.isPVC ? 'pvc' : 'aluminium');
  }

  /// Exact clear opening of the selected outer frame. The top caisson and the
  /// current frame width are read afresh instead of trusting a zone boundary
  /// that may still contain dimensions from a formerly selected profile.
  /// //🎯 ما هو دور هذه الدالة؟
  // دورها هو حساب الفراغ الداخلي الصافي (عرضاً وارتفاعاً بالميليمتر) المتبقي داخل النافذة بعد خصم سماكة بروفايل الإطار وصندوق الستار وأي عتبة سفلية (Plinthe).
  //
  // هذه الفتحة الصافية هي الأساس الهندسي الذي يُبنى عليه:
  //
  // قياسات قص الضلف (Sashes).
  // قياسات قص القواطع والتقسيمات (Mullions).
  // أبعاد ومساحة ألواح الزجاج (Glass).
  static Map<String, double> outerFrameClearOpening({
    required double finishedWidth,
    required double finishedHeight,
    required double frameWidth,
    required double shutterBoxHeight,
    required bool hasBottomFrame,
    double bottomPlintheHeight = 0.0,
    //finishedWidth: العرض الكلي الخارجي للنافذة (بالـ mm).
    // finishedHeight: الارتفاع الكلي الخارجي للنافذة (بالـ mm).
    // frameWidth: سماكة/عرض عود الإطار (البروفيل الخارجي).
    // shutterBoxHeight: ارتفاع صندوق الستار (الكيسون)، ويكون 0 إذا لم يكن هناك ستار.
    // hasBottomFrame: هل يوجد إطار سفلي (نعم في النوافذ، ولا في بعض الأبواب والمداخل).
    // bottomPlintheHeight: ارتفاع البلانط/العتبة السفلية إن وُجدت (خاصة في الأبواب).
  }) {
    return {
      'width': math.max(0.0, finishedWidth - frameWidth * 2),
      'height': math.max(
        0.0,
        finishedHeight -
            shutterBoxHeight -
            frameWidth -
            (hasBottomFrame ? frameWidth : 0.0) -
            bottomPlintheHeight,
      ),
    };
  }

  /// Every physical division uses two Tasso pieces. PVC adds one exceptional
  /// pair only for a regular caisson installed above the window, combined
  /// with the selected integrated-cover frame. A caisson tunnel (behind the
  /// window), or a shutter without a regular caisson, never adds that pair.
  /// هذه الدالة tassoQuantity هي "حاسبة عدد قطع التاسو" ، ودورها هو حساب العدد الدقيق لقطع التاسو المطلوبة لكل تقسيم في الستارة.
  static int tassoQuantity({
    required int divisionPieceCount,
    required bool isPvc,
    required bool hasRegularCaissonAboveWindow,
    required bool selectedFrameHasIntegratedCover,
  }) {
    return (divisionPieceCount * 2) +
        (isPvc &&
                hasRegularCaissonAboveWindow &&
                selectedFrameHasIntegratedCover
            ? 2
            : 0);
  }

  /// Physical weight of the shutter curtain, calculated from the actual
  /// blade count and cut length used by the BOM.
  /// دورها هو حساب الوزن الإجمالي الحقيقي لشفرات الستار (Lames) بالكيلوغرام بدقة متناهية.
  static double shutterCurtainWeightKg({
    required double windowWidthMm,
    required double windowHeightMm,
    required double shutterBoxHeightMm,
    required bool isTunnel,
    required double bladeHeightMm,
    required double bladeWeightPerSqm,
    double bladeEndCapThicknessMm = 0.0,
  }) {
    if (bladeHeightMm <= 0 || bladeWeightPerSqm <= 0) return 0.0;
    final bladeCount = isTunnel
        ? ((windowHeightMm + 100.0) / bladeHeightMm).ceil()
        : ((windowHeightMm - shutterBoxHeightMm) / bladeHeightMm + 2).ceil();
    if (bladeCount <= 0) return 0.0;
    final bladeLengthM = math.max(
      0.0,
      (windowWidthMm - 65.0 - (2.0 * bladeEndCapThicknessMm)) / 1000.0,
    );
    final curtainAreaSqm = bladeLengthM * bladeCount * (bladeHeightMm / 1000.0);
    return curtainAreaSqm * bladeWeightPerSqm;
  }

  /// Chooses one complete compatibility family for all weight-driven kit
  /// components. Group 0 is common and can participate in either family.
  static int? selectKitCompatibilityGroup({
    required List<Map<String, dynamic>> kitItems,
    required double shutterWeightKg,
    String mechanismScope = 'all',
    Set<String>? mechanismScopes,
    String bladeScope = 'normal',
  }) {
    final selectedMechanismScopes =
        mechanismScopes ?? <String>{normalizeKitMechanismScope(mechanismScope)};
    final weightItems = kitItems.where((item) {
      return (item['qty_mode'] as String? ?? 'fixed') == 'by_range' &&
          item['dimension'] == 'shutter_weight' &&
          kitItemAppliesToMechanisms(item, selectedMechanismScopes) &&
          kitItemAppliesToBlade(item, bladeScope);
    }).toList();
    if (weightItems.isEmpty) return null;
    if (shutterWeightKg <= 0) return null;
    int? bestGroup;
    var bestMissingItems = 1 << 20;
    var bestFamilyMatches = -1;
    for (final group in const [1, 2]) {
      var familyMatches = 0;
      var missingItems = 0;
      for (final item in weightItems) {
        final ranges =
            (item['ranges'] as List?)?.cast<Map<String, dynamic>>() ?? [];
        final participatesInGroup = ranges.any((range) {
          final rangeGroup =
              ((range['compatibility_group'] as num?)?.toInt() ?? 0).clamp(
                0,
                2,
              );
          return rangeGroup == group || rangeGroup == 0;
        });
        if (!participatesInGroup) continue;

        final matches = ranges.where((range) {
          final rangeGroup =
              ((range['compatibility_group'] as num?)?.toInt() ?? 0).clamp(
                0,
                2,
              );
          final min = (range['min_mm'] as num?)?.toDouble() ?? 0;
          final max = (range['max_mm'] as num?)?.toDouble() ?? double.infinity;
          return (rangeGroup == 0 || rangeGroup == group) &&
              shutterWeightKg >= min &&
              shutterWeightKg <= max;
        }).toList();
        if (matches.isEmpty) {
          missingItems++;
          continue;
        }
        familyMatches += matches.where((range) {
          final rangeGroup =
              ((range['compatibility_group'] as num?)?.toInt() ?? 0).clamp(
                0,
                2,
              );
          return rangeGroup == group;
        }).length;
      }
      if (familyMatches == 0) continue;
      if (missingItems < bestMissingItems ||
          (missingItems == bestMissingItems &&
              familyMatches > bestFamilyMatches)) {
        bestGroup = group;
        bestMissingItems = missingItems;
        bestFamilyMatches = familyMatches;
      }
    }
    return bestGroup;
  }

  ///دورها هو تحويل طريقة تشغيل الستار (سواء كُتبت بالعربية أو الفرنسية أو الإنجليزية أو حتى لو حدث خطأ في ترميز الحروف)
  /// إلى رمز تقني موحد وثابت يفهمه محرك الكيتات وقاعدة البيانات.
  static String shutterMechanismScope(String mechanism) {
    final normalized = mechanism.toLowerCase().trim();
    if (normalized.contains('moteur') ||
        normalized.contains('motor') ||
        normalized.contains('محرك')) {
      return 'motor';
    }
    if (normalized.contains('maniv') ||
        normalized.contains('مانيف') ||
        normalized.contains('منايف')) {
      return 'crank';
    }
    if (normalized.contains('sangle') ||
        normalized.contains('belt') ||
        normalized.contains('حزام')) {
      return 'belt';
    }
    return 'all';
  }

  static String normalizeKitMechanismScope(String scope) {
    final normalized = scope.toLowerCase().trim().replaceAll(
      RegExp(r'[\s-]+'),
      '_',
    );
    if (normalized.contains('secours') ||
        normalized.contains('emergency') ||
        normalized.contains('sos') ||
        normalized.contains('سوكور') ||
        normalized.contains('احتياط')) {
      if (normalized.contains('sans') ||
          normalized.contains('without') ||
          normalized.contains('no_') ||
          normalized.contains('بدون')) {
        return 'motor_plain';
      }
      return 'motor_emergency';
    }
    if (normalized.contains('plain') ||
        normalized.contains('standard_motor') ||
        normalized.contains('motor_plain') ||
        normalized.contains('motor_without')) {
      return 'motor_plain';
    }
    if (normalized.contains('moteur') ||
        normalized.contains('motor') ||
        normalized.contains('محرك') ||
        normalized.contains('Ù…Ø­Ø±Ùƒ')) {
      return 'motor';
    }
    if (normalized.contains('maniv') ||
        normalized.contains('crank') ||
        normalized.contains('مانيف') ||
        normalized.contains('منايف')) {
      return 'crank';
    }
    if (normalized.contains('sangle') ||
        normalized.contains('belt') ||
        normalized.contains('حزام')) {
      return 'belt';
    }
    return normalized.isEmpty ? 'all' : normalized;
  }

  static Set<String> shutterMechanismScopes(
    String mechanism, {
    bool motorHasEmergencyCrank = false,
  }) {
    final primary = shutterMechanismScope(mechanism);
    if (primary != 'motor') return {primary};
    return {
      'motor',
      motorHasEmergencyCrank ? 'motor_emergency' : 'motor_plain',
    };
  }

  static bool kitItemAppliesToMechanism(
    Map<String, dynamic> item,
    String mechanismScope,
  ) {
    return kitItemAppliesToMechanisms(item, {
      normalizeKitMechanismScope(mechanismScope),
    });
  }

  static bool kitItemAppliesToMechanisms(
    Map<String, dynamic> item,
    Set<String> mechanismScopes,
  ) {
    final selectedScopes = mechanismScopes
        .map(normalizeKitMechanismScope)
        .where((scope) => scope.isNotEmpty)
        .toSet();
    if (selectedScopes.contains('all')) return true;
    // Filter the stored CSV before normalising it.  Normalising an empty
    // string yields `all` for user-facing inputs, but an absent multi-scope
    // column must fall back to the legacy single `mechanism_scope` instead.
    final scopes = (item['mechanism_scopes'] ?? '')
        .toString()
        .split(',')
        .map((scope) => scope.trim())
        .where((scope) => scope.isNotEmpty)
        .map(normalizeKitMechanismScope)
        .toSet();
    if (scopes.isNotEmpty) {
      return scopes.contains('all') ||
          scopes.any((scope) => selectedScopes.contains(scope));
    }
    final itemScope = normalizeKitMechanismScope(
      item['mechanism_scope']?.toString() ?? 'all',
    );
    return itemScope == 'all' || selectedScopes.contains(itemScope);
  }

  ///هذه الدوال الأربع تُشكّل معاً "نظام التصفية والمطابقة المتقدم لملحقات كيت الستار" (Kit Mechanism Filtering Sub-system) داخل مل

  static bool kitItemAppliesToBlade(
    Map<String, dynamic> item,
    String bladeScope,
  ) {
    String normalize(dynamic value) {
      final normalized = value?.toString().trim().toLowerCase() ?? 'all';
      if (normalized == 'x3d' || normalized.startsWith('extrud')) {
        return 'extruded';
      }
      return normalized == 'normal' ? 'normal' : 'all';
    }

    final required = normalize(item['blade_scope']);
    final selected = normalize(bladeScope);
    return required == 'all' || required == selected;
  }

  /// Cut length in millimetres for a customised standalone side-cover piece.
  /// A 45-degree miter adds the cover visible width at every outer corner it
  /// reaches: full-side pieces add it twice, edge pieces once, middle pieces
  /// not at all.
  ///دور الدالة هو: معرفة ما إذا كانت قطعة الغطاء تصل إلى زوايا النافذة الخارجية أم لا، وإضافة الزيادة الهندسية لقص الزواية
  static double standaloneSideCoverSegmentCutLength({
    required double sideLength,
    required double start,
    required double end,
    required double visibleWidth,
    required double weldingAllowance,
  }) {
    final safeStart = start.clamp(0.0, sideLength).toDouble();
    final safeEnd = end.clamp(0.0, sideLength).toDouble();
    if (safeEnd <= safeStart) return 0.0;
    final touchesStartEdge = safeStart <= 0.1;
    final touchesEndEdge = (sideLength - safeEnd).abs() <= 0.1;
    final miterEnds =
        (touchesStartEdge ? 1.0 : 0.0) + (touchesEndEdge ? 1.0 : 0.0);
    return safeEnd - safeStart + (visibleWidth * miterEnds) + weldingAllowance;
  }

  ///هذه الدالة optimizeCutting هي "محرك تحسين مخطط القص وتقليل الهدر" (1D Cutting Stock Optimizer) لقطاعات الألمنيوم والـ PVC داخل ملف
  ///BOM. دورها هو حساب عدد القضبان (Bars) المطلوبة لقص جميع القطع المطلوبة بأقل هدر ممكن، مع مراعاة سمك الشفرة (Blade Waste) لكل عملية قص.
  static Map<String, dynamic> optimizeCutting({
    required List<double> pieces,
    required double barLength,
    double? bladeWaste,
  }) {
    final effectiveBladeWaste = bladeWaste ?? CuttingSettings.sawKerfMeters;
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
      double pieceWithWaste = piece + effectiveBladeWaste;
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
    Map<String, double> kitBundlePrices = const {},
    Map<String, Map<String, dynamic>> kitBundleMetadata = const {},
  }) {
    int? catalogueId(dynamic component) {
      if (component is! Map) return null;
      final rawId = component['id'];
      return rawId is num ? rawId.toInt() : int.tryParse('$rawId');
    }

    int? catalogueColorId(String? itemColor, {bool accessory = false}) {
      Map<String, dynamic>? selected = accessory
          ? window.selectedAccessoryColor
          : window.selectedDbColor;
      if (itemColor != null && itemColor.trim().isNotEmpty) {
        final normalized = itemColor.trim().toLowerCase();
        for (final color in window.availableColors) {
          final name = (color['name'] ?? color['color_name'] ?? '')
              .toString()
              .trim()
              .toLowerCase();
          if (name == normalized) {
            selected = color;
            break;
          }
        }
      }
      return catalogueId(selected);
    }

    Map<String, dynamic>? glassCatalogueProduct(
      GlassFinish finish,
      GlassColor color,
      double thickness,
    ) {
      final finishKeywords = window.getFinishKeywords(finish);
      final colorKeywords = window.getColorKeywords(color);
      bool matchesColor(Map<String, dynamic> product) {
        final name = (product['name'] ?? '').toString().toLowerCase();
        final productColor = (product['color'] ?? '').toString().toLowerCase();
        return colorKeywords.any((keyword) {
          if (keyword.isEmpty) {
            return productColor.isEmpty ||
                productColor.contains('clair') ||
                productColor.contains('transparent') ||
                name.contains('clair') ||
                name.contains('transparent');
          }
          return productColor == keyword ||
              productColor.contains(keyword) ||
              name.contains(keyword);
        });
      }

      bool matchesFinish(Map<String, dynamic> product) {
        final type = (product['type'] ?? '').toString().toLowerCase();
        final name = (product['name'] ?? '').toString().toLowerCase();
        return finishKeywords.any(
          (keyword) => type.contains(keyword) || name.contains(keyword),
        );
      }

      for (final product in window.allGlassCache) {
        final productThickness =
            (product['thickness'] as num?)?.toDouble() ?? 0.0;
        if (matchesFinish(product) &&
            matchesColor(product) &&
            (productThickness - thickness).abs() < 0.01) {
          return product;
        }
      }
      for (final product in window.allGlassCache) {
        if (matchesFinish(product) && matchesColor(product)) return product;
      }
      return null;
    }

    Map<String, dynamic>? getSlidingFrameSection() {
      if (window.slidingFrameOverride != null) {
        return window.slidingFrameOverride;
      }
      final series = window.activeSlidingSeries ?? window.activeSeries;
      if (series == null) return null;
      var slidingFrames = series.sections.where((s) {
        final name = s.name.toLowerCase();
        final type = s.type.toLowerCase();
        return (name.contains('coulissant') ||
                name.contains('منزلق') ||
                name.contains('sliding') ||
                type.contains('coulissant') ||
                type.contains('sliding')) &&
            (type.contains('frame') ||
                type.contains('cadre') ||
                type.contains('إطار'));
      }).toList();
      if (slidingFrames.isNotEmpty) return slidingFrames.first.toMap();

      var anyFrames = series.sections.where((s) {
        final type = s.type.toLowerCase();
        return type.contains('frame') ||
            type.contains('cadre') ||
            type.contains('إطار');
      }).toList();
      if (anyFrames.isNotEmpty) return anyFrames.first.toMap();
      return null;
    }

    Map<String, dynamic>? slidingOverrideFor(Iterable<String> keys) {
      for (final key in keys) {
        final override = window.getSlidingComponentOverride(key);
        if (override != null) return override;
      }
      return null;
    }

    String? getKitKey(String baseName) {
      String? descriptionCode;
      if (baseName == 'System OB' || baseName == 'Demi System OB') {
        descriptionCode = 'OB';
      } else if (baseName == 'Verrou Central') {
        descriptionCode = 'VC';
      }
      if (descriptionCode != null && kitBundleMetadata.isNotEmpty) {
        final coded = kitBundleMetadata.entries.where(
          (entry) => kitHasDescriptionCode(entry.value, descriptionCode!),
        );
        for (final entry in coded) {
          final normalizedName = entry.key.toLowerCase();
          final isDemi =
              normalizedName.contains('demi') ||
              normalizedName.contains('dim') ||
              normalizedName.contains('نصف');
          if (baseName == 'Demi System OB' && isDemi) return entry.key;
          if (baseName == 'System OB' && !isDemi) return entry.key;
          if (baseName == 'Verrou Central') return entry.key;
        }
      }

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
      bool preferOverrideMap = false,
      bool priceByWholeBar = false,
      String? selectorType,
    }) {
      final savedOverride = window.componentOverrides[originalName];
      final selectedOverride = preferOverrideMap && overrideMap != null
          ? overrideMap
          : savedOverride is Map
          ? Map<String, dynamic>.from(savedOverride)
          : overrideMap;
      List<double>? multipliedPieces;
      if (pieces != null && pieces.isNotEmpty) {
        multipliedPieces = [];
        for (int q = 0; q < window.quantity; q++) {
          multipliedPieces.addAll(pieces);
        }
      }
      final resolvedSelectorType =
          selectorType ?? _selectorTypeForProfile(originalName);
      return _createProfile(
        window.componentOverrides,
        originalName,
        color,
        unit: unit,
        defaultPrice: defaultPrice,
        qty: qty * window.quantity,
        length: length,
        pieces: multipliedPieces,
        overrideMap: selectedOverride,
        preferOverrideMap: selectedOverride != null,
        priceByWholeBar: priceByWholeBar,
        catalogItemId: catalogueId(selectedOverride),
        colorId: catalogueColorId(color),
        overrideKey: originalName,
        selectorCategory: 'profile',
        selectorType: resolvedSelectorType,
        roleKey: _roleKeyForProfileSelector(resolvedSelectorType),
        sourceSeriesId: _sourceSeriesIdForProfile(window, resolvedSelectorType),
        materialType: _materialTypeForProfile(window, resolvedSelectorType),
      );
    }

    BomItem createAccessory(
      String originalName, {
      bool isActive = true,
      String? color,
      int qty = 0,
    }) {
      final selectorType = _selectorTypeForAccessory(originalName);
      return _createAccessory(
        window.componentOverrides,
        originalName,
        isActive: isActive,
        color: color,
        qty: qty * window.quantity,
        catalogItemId: catalogueId(window.componentOverrides[originalName]),
        colorId: catalogueColorId(color, accessory: true),
        overrideKey: originalName,
        selectorCategory: 'accessory',
        selectorType: selectorType,
        roleKey: _roleKeyForAccessorySelector(selectorType),
        sourceSeriesId: window.systemMode == 'sliding'
            ? (window.activeSlidingSeries?.id ?? window.activeSeries?.id)
            : window.activeSeries?.id,
        materialType: window.isPVC ? 'pvc' : 'aluminium',
      );
    }

    BomItem createInteractiveAccessory(
      String originalName,
      String group, {
      bool isActive = false,
      double qty = 1,
      String? kitGroupName,
      String category = 'accessory',
    }) {
      final selectorType = category == 'shutter'
          ? _selectorTypeForShutter(originalName)
          : _selectorTypeForAccessory(originalName);
      return _createInteractiveAccessory(
        window.componentOverrides,
        originalName,
        group,
        isActive: isActive,
        qty: qty * window.quantity,
        kitGroupName: kitGroupName,
        category: category,
        catalogItemId: catalogueId(window.componentOverrides[originalName]),
        inventoryItemType: category == 'shutter'
            ? 'ShutterComponent'
            : 'Accessory',
        colorId: catalogueColorId(null, accessory: category != 'shutter'),
        overrideKey: originalName,
        selectorCategory: category,
        selectorType: selectorType,
        roleKey: category == 'shutter'
            ? _roleKeyForShutterSelector(selectorType)
            : _roleKeyForAccessorySelector(selectorType),
        sourceSeriesId: category == 'shutter'
            ? null
            : (window.systemMode == 'sliding'
                  ? (window.activeSlidingSeries?.id ?? window.activeSeries?.id)
                  : window.activeSeries?.id),
        materialType: category == 'shutter'
            ? 'shutter'
            : (window.isPVC ? 'pvc' : 'aluminium'),
      );
    }

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
      final selectorType = _selectorTypeForShutter(originalName);
      return _createShutter(
        window.componentOverrides,
        originalName,
        color: color,
        qty: unit == 'متر'
            ? ((qty * window.quantity) * 100).round() / 100.0
            : qty * window.quantity,
        unit: unit,
        pieces: multipliedPieces,
        kitGroupName: kitGroupName,
        windowWidth: window.width.toDouble(),
        windowHeight: window.height.toDouble(),
        windowQuantity: window.quantity,
        catalogItemId: catalogueId(window.componentOverrides[originalName]),
        colorId: catalogueColorId(color),
        overrideKey: originalName,
        selectorCategory: _textHasAny(originalName, const ['براغي'])
            ? 'accessory'
            : 'shutter',
        selectorType: selectorType,
        roleKey: _textHasAny(originalName, const ['براغي'])
            ? _roleKeyForAccessorySelector(selectorType)
            : _roleKeyForShutterSelector(selectorType),
        materialType: 'shutter',
      );
    }

    /// A shutter kit is configured on the Kits page, while its selling price
    /// comes from the identically named `kit` product in ShutterComponents.
    /// The saved logical key is internal only: the visible label remains the
    /// exact French name of the selected bundle.
    BomItem createKitBundle(
      String logicalKey,
      String bundleName, {
      required double qty,
    }) {
      final savedOverride = window.componentOverrides[logicalKey];
      final metadata = kitBundleMetadata[bundleName];
      return BomItem(
        category: 'shutter',
        originalName: logicalKey,
        name: bundleName,
        quantity: qty * window.quantity,
        unit: 'kit',
        unitPrice: kitBundlePrices[bundleName] ?? 0,
        isInteractive: true,
        isActive: true,
        exclusionGroup: bundleName,
        kitGroupName: bundleName,
        catalogItemId: catalogueId(savedOverride) ?? catalogueId(metadata),
        inventoryItemType: 'KitBundle',
        overrideKey: logicalKey,
        selectorCategory: 'shutter',
        selectorType: 'كيت',
        roleKey: 'kit',
        materialType: 'shutter',
      );
    }

    BomItem createJoint(
      String originalName, {
      String? color,
      double qty = 0,
      String unit = 'بارة',
      double? targetThicknessMm,
      String? overrideKey,
    }) {
      final selectorType = _selectorTypeForJoint(originalName);
      final isShutterJoint = _textHasAny(originalName, const [
        'للستار',
        'shutter',
        'volet',
      ]);
      final exactQty = ((qty * window.quantity) * 100).round() / 100.0;
      final normalizedUnit = unit.toLowerCase().trim();
      final purchaseQty =
          (normalizedUnit.contains('متر') ||
              normalizedUnit.contains('meter') ||
              normalizedUnit == 'm' ||
              normalizedUnit == 'ml')
          ? (exactQty <= 0 ? 0.0 : exactQty.ceilToDouble())
          : exactQty;
      final effectiveKey = overrideKey ?? originalName;
      return _createJoint(
        window.componentOverrides,
        originalName,
        color: color,
        qty: purchaseQty,
        unit: unit,
        exactQuantity: exactQty,
        catalogItemId: catalogueId(window.componentOverrides[effectiveKey]),
        overrideKey: effectiveKey,
        selectorCategory: 'joint',
        selectorType: selectorType,
        roleKey: isShutterJoint
            ? 'shutter_joint_brosse'
            : _roleKeyForJointSelector(selectorType),
        targetThicknessMm: targetThicknessMm,
        sourceSeriesId: isShutterJoint
            ? null
            : window.systemMode == 'sliding'
            ? (window.activeSlidingSeries?.id ?? window.activeSeries?.id)
            : window.activeSeries?.id,
        materialType: isShutterJoint
            ? 'shutter'
            : window.systemMode == 'sliding'
            ? (window.isSlidingPVC ? 'pvc' : 'aluminium')
            : (window.isPVC ? 'pvc' : 'aluminium'),
      );
    }

    // The catalogue value is shared by every opening-sash calculation. Add it
    // to both sides of the clear opening (10 mm + 10 mm in the usual case),
    // then distribute that complete cut size between double leaves. It is
    // never replaced by a hard-coded default.
    final double seriesSashOverlap = window.openingSashOverlap;

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
    // كل رسم يحتاج إلى إطار، حتى الرسومات القديمة التي لم تحفظ اختيار
    // القطاع ضمن `frameOverride`. نأخذ أول إطار/ظلفة صالح من السلسلة
    // الفعلية حتى يظهر البروفيل في جدول الكمية والتكلفة.
    Map<String, dynamic>? defaultProfileFromSeries(
      AluminumSeries? series,
      bool Function(AluminumSection section) matches,
    ) {
      if (series == null) return null;
      for (final section in series.sections) {
        if (matches(section)) return section.toMap();
      }
      return null;
    }

    final outerFrameOverride =
        window.activeFrameOverride ??
        defaultProfileFromSeries(window.activeFrameSeries, (section) {
          final type = section.type.toLowerCase();
          final name = section.name.toLowerCase();
          return section.isFrame ||
              type.contains('frame') ||
              type.contains('cadre') ||
              name.contains('frame') ||
              name.contains('cadre') ||
              name.contains('إطار');
        });
    final openingSashOverride =
        window.sashOverride ??
        defaultProfileFromSeries(window.activeSeries, (section) {
          final type = section.type.toLowerCase();
          final name = section.name.toLowerCase();
          return section.isSash ||
              type.contains('sash') ||
              type.contains('ouvrant') ||
              name.contains('sash') ||
              name.contains('ouvrant') ||
              name.contains('ظلفة');
        });
    final isOuterFramePvc = window.isFramePVC;

    double selectedOuterFrameWidth() {
      for (final key in const ['visible_width', 'thickness']) {
        final rawValue = outerFrameOverride?[key];
        final value = rawValue is num
            ? rawValue.toDouble()
            : double.tryParse(rawValue?.toString() ?? '') ?? 0.0;
        if (value > 0) return value;
      }
      return window.profileThickness;
    }

    final selectedFrameWidth = selectedOuterFrameWidth();
    final fullOpening = outerFrameClearOpening(
      finishedWidth: window.width,
      finishedHeight: window.height,
      frameWidth: selectedFrameWidth,
      shutterBoxHeight: window.hasShutter && !window.isCaissonTunnel
          ? window.shutterBoxHeight
          : 0.0,
      hasBottomFrame: window.hasBottomFrame,
    );

    // تحديد نوع الغطاء الجانبي:
    // مدمج: مقطع الإطار نفسه فيه couvreJointWidth > 0
    // غير مدمج: hasSideCovers = true لكن الإطار بدون couvreJoint مدمج
    double selectedFrameIntegratedCoverWidth() {
      if (outerFrameOverride != null) {
        final value = outerFrameOverride['couvre_joint_width'];
        return value is num
            ? value.toDouble()
            : double.tryParse(value?.toString() ?? '') ?? 0.0;
      }
      return window.getSectionByType('frame')?.couvreJointWidth ?? 0.0;
    }

    final integratedFrameCoverWidth = selectedFrameIntegratedCoverWidth();
    // The selected frame owns an integrated cover. This rule is shared by
    // PVC, aluminium, and TPR; the model disables it for aluminium shutters.
    final bool hasIntegratedSideCover =
        integratedFrameCoverWidth > 0 && window.isIntegratedFrame;
    bool hasNonIntegratedSideCover =
        window.hasSideCovers &&
        window.canUseStandaloneSideCover &&
        !hasIntegratedSideCover;
    // Both integrated and standalone covers are workshop/drawing details.
    // A standalone cover has its own cutting row and its thickness shortens
    // the frame once for every side where it is installed.
    final bool customSideCoverLayout = window.useCustomSideCoverLayout;

    // A separate couvre-joint must always be read from the exact section that
    // was selected for this series.  Do not reuse the width of an integrated
    // cover on the frame: the two profiles can have different widths and
    // thicknesses even in the same PVC series.
    AluminumSection? resolveSelectedSeparateSideCover() {
      final series = window.activeFrameSeries ?? window.activeSeries;
      if (series == null) return window.selectedSideCover;

      AluminumSection? findInSeries({int? id, String? code, String? name}) {
        if (id != null) {
          for (final section in series.sections) {
            if (section.id == id) return section;
          }
        }
        if (code != null && code.trim().isNotEmpty) {
          for (final section in series.sections) {
            if (section.code.trim().toLowerCase() ==
                code.trim().toLowerCase()) {
              return section;
            }
          }
        }
        if (name != null && name.trim().isNotEmpty) {
          for (final section in series.sections) {
            if (section.name.trim().toLowerCase() ==
                name.trim().toLowerCase()) {
              return section;
            }
          }
        }
        return null;
      }

      final selected = window.selectedSideCover;
      final fromSelected = findInSeries(
        id: selected?.id,
        code: selected?.code,
        name: selected?.name,
      );
      if (fromSelected != null) return fromSelected;

      final override = window.sideCoverOverride;
      if (override != null) {
        final rawId = override['id'];
        final id = rawId is num
            ? rawId.toInt()
            : int.tryParse(rawId?.toString() ?? '');
        final fromOverride = findInSeries(
          id: id,
          code: override['code']?.toString(),
          name: override['name']?.toString(),
        );
        if (fromOverride != null) return fromOverride;
      }

      return selected;
    }

    final selectedSeparateSideCover = hasNonIntegratedSideCover
        ? resolveSelectedSeparateSideCover()
        : null;

    double selectedSeparateCoverWidth() {
      final cover = selectedSeparateSideCover;
      if (cover != null) {
        // A standalone cover can have two usable faces. The first face is
        // couvreJointWidth and the second is visibleWidth. Respect the user's
        // orientation choice, falling back only when that face is zero.
        final selectedWidth = window.sideCoverUseSecondWidth
            ? cover.visibleWidth
            : cover.couvreJointWidth;
        final otherWidth = window.sideCoverUseSecondWidth
            ? cover.couvreJointWidth
            : cover.visibleWidth;
        if (selectedWidth > 0) return selectedWidth;
        if (otherWidth > 0) return otherWidth;
      }

      final override = window.sideCoverOverride;
      if (override != null) {
        double read(String key) {
          final value = override[key];
          return value is num
              ? value.toDouble()
              : double.tryParse(value?.toString() ?? '') ?? 0.0;
        }

        final firstWidth = read('couvre_joint_width');
        final secondWidth = read('visible_width');
        final selectedWidth = window.sideCoverUseSecondWidth
            ? secondWidth
            : firstWidth;
        final otherWidth = window.sideCoverUseSecondWidth
            ? firstWidth
            : secondWidth;
        if (selectedWidth > 0) return selectedWidth;
        return otherWidth;
      }

      return 0.0;
    }

    final separateCoverWidth = selectedSeparateCoverWidth();
    double selectedSeparateCoverThickness() {
      if (selectedSeparateSideCover != null) {
        return selectedSeparateSideCover.couvreJointThickness;
      }
      final value = window.sideCoverOverride?['couvre_joint_thickness'];
      return value is num
          ? value.toDouble()
          : double.tryParse(value?.toString() ?? '') ?? 0.0;
    }

    final separateCoverThickness = selectedSeparateCoverThickness();

    bool hasSeparateCoverOn(String side) {
      if (!hasNonIntegratedSideCover) return false;
      if (side == 'bottom' && !window.hasBottomFrame) return false;
      if (customSideCoverLayout) {
        return window.effectiveSideCoverSegments.any(
          (segment) =>
              segment.side == side && segment.endOffset > segment.startOffset,
        );
      }
      return !window.removedShutterSides.contains(side);
    }

    final hasSeparateCoverLeft = hasSeparateCoverOn('left');
    final hasSeparateCoverRight = hasSeparateCoverOn('right');
    final hasSeparateCoverTop = hasSeparateCoverOn('top');
    final hasSeparateCoverBottom = hasSeparateCoverOn('bottom');

    Map<String, dynamic>? selectedSeparateCoverMap;
    if (selectedSeparateSideCover != null) {
      selectedSeparateCoverMap = selectedSeparateSideCover.toMap();
      final savedCover = window.sideCoverOverride;
      if (savedCover != null &&
          savedCover['id']?.toString() ==
              selectedSeparateSideCover.id.toString()) {
        selectedSeparateCoverMap['calculated_price'] =
            savedCover['calculated_price'] ??
            savedCover['price_dzd'] ??
            savedCover['price'];
      }
    } else {
      selectedSeparateCoverMap = window.sideCoverOverride;
    }

    // حساب netHeight: الارتفاع الصافي قبل حساب الإطار
    final double netHeight = (window.hasShutter && !window.isCaissonTunnel)
        ? window.height - window.shutterBoxHeight
        : window.height;

    String colorName = window.selectedDbColor != null
        ? window.selectedDbColor!['name']
        : window.frameColor.toString().split('.').last;
    // Accessories follow the profile colour automatically, unless the user
    // chose a separate accessory colour in the drawing properties.
    final String accessoryColorName = window.selectedAccessoryColor != null
        ? (window.selectedAccessoryColor!['name'] ?? colorName).toString()
        : colorName;
    final String shutterColorName = window.selectedAccessoryColor != null
        ? (window.selectedAccessoryColor!['name'] ?? colorName).toString()
        : colorName;

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
    List<double> internalSlidingSideCoverPieces = [];
    int slidingTotalRoulettes = 0;
    int slidingTotalEspagnolettes = 0;
    int slidingTotalHandles = 0;
    int slidingTotalGacheCoulissant = 0;
    double slidingTotalJointBrosse = 0.0;
    double pvcJointBrosseSum = 0.0;
    Map<String, double> slidingGlassJoints = {};

    // PVC sliding systems have their own cutting rules.  They deliberately
    // live on the *sliding* series so a mixed drawing cannot inherit the
    // opening-series overlap or width formula.
    final Map<String, dynamic> slidingTableConfig =
        window.slidingSeriesTableConfig ?? window.seriesTableConfig ?? const {};
    double slidingRuleNumber(String key, {double fallback = 0.0}) {
      final value = slidingTableConfig[key];
      if (value is num) return value.toDouble();
      return double.tryParse(value?.toString() ?? '') ?? fallback;
    }

    final int pvcChicanePiecesPerJunction = math
        .max(
          1,
          slidingRuleNumber(
            'sliding_chicane_pieces_per_junction',
            fallback: 1.0,
          ).round(),
        )
        .toInt();
    for (var zone in window.zones) {
      if (zone.content == ZoneContent.singleSash ||
          zone.content == ZoneContent.doubleSash) {
        int sashes = (zone.content == ZoneContent.doubleSash) ? 2 : 1;
        final seriesName = window.activeSeries?.name.toLowerCase() ?? '';
        final isTPR = seriesName.contains('tpr');
        final isThinSash = !zone.isSash105;
        final hasAllowedLock =
            (zone.lockType == LockType.clef ||
                zone.lockType == LockType.condamnation ||
                zone.lockType == LockType.rouleau ||
                zone.lockType == LockType.rouleau2000) &&
            !(isTPR && isThinSash);

        final bool isDoor =
            (zone.isSash105 || hasAllowedLock) &&
            zone.lockType != LockType.none &&
            zone.useOctoHandle != true &&
            zone.usePvcHandleOnAlu != true;
        if (isDoor) {
          if (zone.content == ZoneContent.singleSash) {
            doorSingleSashCount++;
          } else {
            doorDoubleSashCount++;
          }
          final bool isCondamnation =
              zone.lockType == LockType.condamnation && !(isTPR && isThinSash);
          final bool isMarechal125 =
              zone.lockType == LockType.rouleau && !(isTPR && isThinSash);
          final bool isMarechal2m =
              zone.lockType == LockType.rouleau2000 && !(isTPR && isThinSash);

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

          // A double sash has one active handle by default.  The second
          // handle is counted only when the user explicitly enables it in
          // the drawing ("two handles").
          final int handleCount = zone.content == ZoneContent.doubleSash
              ? (zone.doubleSashHasTwoHandles ? 2 : 1)
              : 1;

          // A thick sash can deliberately use a normal window handle
          // (Poignée fenêtre). It is not the specialised PVC-on-aluminium
          // accessory, so it belongs in the ordinary window-handle row.
          final usesWindowHandleOnDoor =
              zone.isSash105 && zone.usePvcHandleOnAlu;
          if (zone.content == ZoneContent.doubleSash) {
            if (zone.usePvcHandleOnAlu && !usesWindowHandleOnDoor) {
              pvcHandlesOnAlu += handleCount;
            } else if (zone.useOctoHandle) {
              octoHandles += handleCount;
            } else {
              totalHandles += handleCount;
            }
          } else {
            if (zone.lockType == LockType.point) {
              pointLocks += 1;
            } else if (zone.usePvcHandleOnAlu && !usesWindowHandleOnDoor) {
              pvcHandlesOnAlu += 1;
            } else if (zone.useOctoHandle) {
              octoHandles += 1;
            } else {
              totalHandles += 1;
            }
          }

          final isVerticalOpen =
              zone.openDirection == OpenDirection.top ||
              zone.openDirection == OpenDirection.bottom;
          final isNotPano = zone.glass.structure != GlassStructure.closed;
          if (zone.useOctoHandle && isVerticalOpen && isNotPano) {
            totalCompas += (zone.content == ZoneContent.doubleSash) ? 2 : 1;
          }
        }

        final hingesPerSash = standardHingeCountForSash(
          sashHeight: zone.boundary.height,
          glassStructure: zone.glass.structure,
        );

        int sashesWithHinges = sashes;
        if (window.effectiveUseSystemOB || window.effectiveUseDemiOB) {
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

    final bool useCremone =
        !window.isPVC &&
        window.systemMode != 'sliding' &&
        window.hasBottomFrame;
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
      double shutterWeightKg = 0,
      String mechanismScope = 'all',
      Set<String>? mechanismScopes,
      String bladeScope = 'normal',
      bool isActive = true,
      int leafCount = 1,
      String category = 'accessory',
      String? variantValue,
      bool includeFamilyItems = false,
      bool groupExpandedItems = true,
    }) {
      final result = <BomItem>[];
      final String? expandedItemGroupName = groupExpandedItems ? kitName : null;
      String selectorTypeForKitChild(String value) => category == 'shutter'
          ? _selectorTypeForShutter(value)
          : _selectorTypeForAccessory(value);
      String selectorCategoryForKitChild(String value) =>
          selectorTypeForKitChild(value).contains('_screw')
          ? 'accessory'
          : category;
      String? roleKeyForKitChild(String value) {
        final selectorType = selectorTypeForKitChild(value);
        return selectorCategoryForKitChild(value) == 'accessory'
            ? _roleKeyForAccessorySelector(selectorType)
            : _roleKeyForShutterSelector(selectorType);
      }

      int? sourceSeriesIdForKitChild(String value) {
        return selectorCategoryForKitChild(value) == 'accessory' &&
                category != 'shutter'
            ? (window.systemMode == 'sliding'
                  ? (window.activeSlidingSeries?.id ?? window.activeSeries?.id)
                  : window.activeSeries?.id)
            : null;
      }

      String materialTypeForKitChild(String value) {
        return category == 'shutter'
            ? 'shutter'
            : (window.isPVC ? 'pvc' : 'aluminium');
      }

      final selectedMechanismScopes =
          mechanismScopes ??
          <String>{normalizeKitMechanismScope(mechanismScope)};
      Map<String, dynamic>? itemFamily(Map<String, dynamic> item) {
        final rawFamily = item['family'];
        return rawFamily is Map ? Map<String, dynamic>.from(rawFamily) : null;
      }

      bool familyApplies(Map<String, dynamic> item) {
        final family = itemFamily(item);
        if (family == null) return true;
        return kitItemAppliesToMechanisms(family, selectedMechanismScopes) &&
            kitItemAppliesToBlade(family, bladeScope);
      }

      final applicableKitItems = kitItems.where(familyApplies).toList();
      final selectedCompatibilityGroup = selectKitCompatibilityGroup(
        kitItems: applicableKitItems,
        shutterWeightKg: shutterWeightKg,
        mechanismScope: mechanismScope,
        mechanismScopes: selectedMechanismScopes,
        bladeScope: bladeScope,
      );
      for (final item in kitItems) {
        final family = itemFamily(item);
        // A family is a selectable result of a kit range. Its children are
        // not auto-selected merely because the family exists in the kit.
        if (family != null && !includeFamilyItems) continue;
        if (!familyApplies(item)) continue;
        if (!kitItemAppliesToMechanisms(item, selectedMechanismScopes)) {
          continue;
        }
        if (!kitItemAppliesToBlade(item, bladeScope)) continue;
        // A family is one small assembly inside its parent Kit.  Its child
        // components are used once by default; it may explicitly opt into
        // one occurrence per leaf.
        final familyPerLeaf = (family?['per_leaf'] as num?)?.toInt() == 1;
        final itemLeafCount = family == null || familyPerLeaf ? leafCount : 1;
        final mode = item['qty_mode'] as String? ?? 'fixed';
        final dimension = item['dimension'] as String?;
        const unit = 'قطعة';
        final ranges =
            (item['ranges'] as List?)?.cast<Map<String, dynamic>>() ?? [];
        final variants =
            (item['variants'] as List?)?.cast<Map<String, dynamic>>() ?? [];

        if (mode == 'fixed') {
          final qty =
              ((item['base_qty'] as num?)?.toDouble() ?? 1) * itemLeafCount;
          final componentName = item['component_type'] as String? ?? '';
          result.add(
            BomItem(
              category: category,
              originalName: '${kitName}_${item['component_type']}',
              name: componentName,
              quantity: qty,
              unit: unit,
              unitPrice: (item['price'] as num?)?.toDouble() ?? 0.0,
              isActive: isActive,
              kitGroupName: expandedItemGroupName,
              selectorCategory: selectorCategoryForKitChild(componentName),
              selectorType: selectorTypeForKitChild(componentName),
              roleKey: roleKeyForKitChild(componentName),
              sourceSeriesId: sourceSeriesIdForKitChild(componentName),
              materialType: materialTypeForKitChild(componentName),
            ),
          );
        } else if (mode == 'by_range' && ranges.isNotEmpty) {
          final isWeight = dimension == 'shutter_weight';
          final isHeight = dimension == 'leaf_height' || dimension == 'height';
          final dimValue = isWeight
              ? shutterWeightKg
              : (isHeight ? leafHeightMm : leafWidthMm);

          // Sort ranges by max_mm ascending so we pick the smallest matching range
          final sortedRanges = List<Map<String, dynamic>>.from(ranges);
          sortedRanges.sort((a, b) {
            final aMax = (a['max_mm'] as num?)?.toDouble() ?? double.infinity;
            final bMax = (b['max_mm'] as num?)?.toDouble() ?? double.infinity;
            return aMax.compareTo(bMax);
          });

          final matchedRanges = <Map<String, dynamic>>[];
          for (final r in sortedRanges) {
            final mn = (r['min_mm'] as num?)?.toDouble() ?? 0;
            final mx = (r['max_mm'] as num?)?.toDouble() ?? double.infinity;
            final rangeGroup =
                ((r['compatibility_group'] as num?)?.toInt() ?? 0).clamp(0, 2);
            final groupMatches =
                !isWeight ||
                selectedCompatibilityGroup == null ||
                (selectedCompatibilityGroup != null &&
                    (rangeGroup == 0 ||
                        rangeGroup == selectedCompatibilityGroup));
            // The range matches if dimValue falls within [mn, mx)
            if (groupMatches && dimValue >= mn && dimValue <= mx) {
              matchedRanges.add(r);
              if (!isWeight) break;
            }
          }
          if (matchedRanges.isNotEmpty) {
            for (final matchedRange in matchedRanges) {
              final rangeQty = (matchedRange['qty'] as num?)?.toDouble() ?? 1;
              final rawSelectedFamily = matchedRange['family'];
              final selectedFamily = rawSelectedFamily is Map
                  ? Map<String, dynamic>.from(rawSelectedFamily)
                  : null;
              final selectedFamilyItems =
                  (selectedFamily?['items'] as List? ?? const <dynamic>[])
                      .whereType<Map>()
                      .map((child) => Map<String, dynamic>.from(child))
                      .toList();
              if (selectedFamily != null && selectedFamilyItems.isNotEmpty) {
                final familyPerLeaf =
                    (selectedFamily['per_leaf'] as num?)?.toInt() == 1;
                final familyItems = expandKitBundle(
                  kitName,
                  selectedFamilyItems,
                  leafHeightMm: leafHeightMm,
                  leafWidthMm: leafWidthMm,
                  shutterWeightKg: shutterWeightKg,
                  mechanismScope: mechanismScope,
                  mechanismScopes: selectedMechanismScopes,
                  bladeScope: bladeScope,
                  isActive: isActive,
                  // A family marked "once" stays once for the whole Kit,
                  // even when the containing Kit is configured per leaf.
                  leafCount: familyPerLeaf ? leafCount : 1,
                  category: category,
                  variantValue: variantValue,
                  includeFamilyItems: true,
                  groupExpandedItems: groupExpandedItems,
                );
                result.addAll(
                  familyItems.map(
                    (familyItem) => familyItem.copyWith(
                      qty: familyItem.quantity * rangeQty,
                    ),
                  ),
                );
                continue;
              }
              final qty = rangeQty * itemLeafCount;
              final rawLinkedComponent = matchedRange['shutter_component'];
              final linkedComponent = rawLinkedComponent is Map
                  ? Map<String, dynamic>.from(rawLinkedComponent)
                  : null;
              final linkedColorPrices =
                  (matchedRange['shutter_color_prices'] as List?)
                      ?.whereType<Map>()
                      .map((row) => Map<String, dynamic>.from(row))
                      .toList() ??
                  const <Map<String, dynamic>>[];
              final linkedId = catalogueId(linkedComponent);
              final linkedName = linkedComponent?['name']?.toString().trim();
              final productName = matchedRange['product_name'] as String? ?? '';
              final displayName = linkedName?.isNotEmpty == true
                  ? linkedName!
                  : productName.isNotEmpty
                  ? productName
                  : item['component_type'] as String? ?? '';
              final linkedPrice = linkedComponent == null
                  ? (matchedRange['price'] as num?)?.toDouble() ?? 0
                  : resolveShutterComponentUnitPrice(
                      component: linkedComponent,
                      colorPrices: linkedColorPrices,
                      selectedColorId: catalogueColorId(null),
                    );
              result.add(
                BomItem(
                  category: category,
                  originalName: '${kitName}_${matchedRange['product_name']}',
                  name: displayName,
                  quantity: qty,
                  unit: unit,
                  unitPrice: linkedPrice,
                  isActive: isActive,
                  isMissing: linkedId == null,
                  kitGroupName: expandedItemGroupName,
                  catalogItemId: linkedId,
                  inventoryItemType: linkedId == null
                      ? null
                      : 'ShutterComponent',
                  colorId: linkedId == null ? null : catalogueColorId(null),
                  selectorCategory: selectorCategoryForKitChild(displayName),
                  selectorType: selectorTypeForKitChild(displayName),
                  roleKey: roleKeyForKitChild(displayName),
                  sourceSeriesId: sourceSeriesIdForKitChild(displayName),
                  materialType: materialTypeForKitChild(displayName),
                ),
              );
            }
          } else {
            // لا يوجد نطاق مطابق - أضف كعنصر مفقود للتنبيه
            result.add(
              BomItem(
                category: category,
                originalName: '${kitName}_${item['component_type']}_missing',
                name: isWeight && shutterWeightKg <= 0
                    ? '⚠ ${item['component_type']} (وزن الشفرة غير محدد)'
                    : isWeight && selectedCompatibilityGroup == null
                    ? '⚠ ${item['component_type']} (لا توجد مجموعة توافق مكتملة لهذا الوزن)'
                    : '⚠ ${item['component_type']} (قياس خارج النطاق)',
                quantity: 0,
                unit: unit,
                unitPrice: 0,
                isActive: isActive,
                isMissing: true,
                kitGroupName: expandedItemGroupName,
                selectorCategory: selectorCategoryForKitChild(
                  item['component_type'] as String? ?? '',
                ),
                selectorType: selectorTypeForKitChild(
                  item['component_type'] as String? ?? '',
                ),
                roleKey: roleKeyForKitChild(
                  item['component_type'] as String? ?? '',
                ),
                sourceSeriesId: sourceSeriesIdForKitChild(
                  item['component_type'] as String? ?? '',
                ),
                materialType: materialTypeForKitChild(
                  item['component_type'] as String? ?? '',
                ),
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
              ((matchedVariant['qty'] as num?)?.toDouble() ?? 1) *
              itemLeafCount;
          final productName = matchedVariant['product_name'] as String? ?? '';
          result.add(
            BomItem(
              category: category,
              originalName: '${kitName}_${matchedVariant['product_name']}',
              name: productName,
              quantity: qty,
              unit: unit,
              unitPrice: (matchedVariant['price'] as num?)?.toDouble() ?? 0,
              isActive: isActive,
              kitGroupName: expandedItemGroupName,
              selectorCategory: selectorCategoryForKitChild(productName),
              selectorType: selectorTypeForKitChild(productName),
              roleKey: roleKeyForKitChild(productName),
              sourceSeriesId: sourceSeriesIdForKitChild(productName),
              materialType: materialTypeForKitChild(productName),
            ),
          );
        }
      }
      return result;
    }

    final double weldVal = isOuterFramePvc ? 5.0 : 0.0;
    final double noBottomWeldVal = isOuterFramePvc ? 5.0 : 0.0;

    // An integrated couvre-joint is cut around the finished window on all four
    // sides. Add its visible width at both ends of each frame piece, plus the
    // PVC welding allowance where applicable. A separate cover remains its
    // own profile and only its thickness shortens the plain frame.
    final double integratedCoverCutExtension = hasIntegratedSideCover
        ? integratedFrameCoverWidth * 2
        : 0.0;
    final double frameWidth =
        window.width +
        integratedCoverCutExtension +
        weldVal -
        (hasSeparateCoverLeft ? separateCoverThickness : 0.0) -
        (hasSeparateCoverRight ? separateCoverThickness : 0.0);
    // For an integrated cover, the requested base is the actual window
    // height, not the net height after deducting a shutter box.
    final double frameBaseHeight = hasIntegratedSideCover
        ? window.height
        : netHeight;
    final double frameNetHeight =
        frameBaseHeight +
        integratedCoverCutExtension +
        (window.hasBottomFrame ? weldVal : noBottomWeldVal) -
        (hasSeparateCoverTop ? separateCoverThickness : 0.0) -
        (hasSeparateCoverBottom ? separateCoverThickness : 0.0);

    final frameRects = window.getFrameRects();
    final minFrameLeft = frameRects.isEmpty
        ? 0.0
        : frameRects.map((rect) => rect.left).reduce(math.min);
    final maxFrameRight = frameRects.isEmpty
        ? 0.0
        : frameRects.map((rect) => rect.right).reduce(math.max);
    final minFrameTop = frameRects.isEmpty
        ? 0.0
        : frameRects.map((rect) => rect.top).reduce(math.min);
    final maxFrameBottom = frameRects.isEmpty
        ? 0.0
        : frameRects.map((rect) => rect.bottom).reduce(math.max);
    List<double> framePieces = [];
    List<double> slidingOuterFramePieces = [];
    List<double> renfortFramePieces = [];

    double renfortFrameDeduction = 140.0;
    if (outerFrameOverride != null) {
      renfortFrameDeduction =
          (outerFrameOverride['renfort_deduction'] as num?)?.toDouble() ??
          140.0;
    }

    for (final r in frameRects) {
      bool frameRectIsSlidingOnly() {
        if (frameRects.length <= 1) return false;
        final innerLeft = r.left + window.profileThickness - 2.0;
        final innerTop = r.top + window.profileThickness - 2.0;
        final innerRight = r.right - window.profileThickness + 2.0;
        final innerBottom = r.bottom - window.profileThickness + 2.0;
        final frameZones = window.zones
            .where(
              (zone) =>
                  zone.boundary.left >= innerLeft &&
                  zone.boundary.top >= innerTop &&
                  zone.boundary.right <= innerRight &&
                  zone.boundary.bottom <= innerBottom,
            )
            .toList();
        return frameZones.isNotEmpty &&
            frameZones.every((zone) => zone.content == ZoneContent.slidingSash);
      }

      // A complete window is cut from the real drawing dimensions.  For a
      // multi-frame drawing, retain each group's own dimensions while using
      // the same cover formula.
      final isCompleteFrame = frameRects.length == 1;
      final useSlidingOuterFrame = frameRectIsSlidingOnly();
      double fWidth = isCompleteFrame
          ? frameWidth
          : r.width +
                integratedCoverCutExtension +
                weldVal -
                (hasSeparateCoverLeft && (r.left - minFrameLeft).abs() < 0.1
                    ? separateCoverThickness
                    : 0.0) -
                (hasSeparateCoverRight && (r.right - maxFrameRight).abs() < 0.1
                    ? separateCoverThickness
                    : 0.0);
      double fHeight = isCompleteFrame
          ? frameNetHeight
          : r.height +
                integratedCoverCutExtension +
                (window.hasBottomFrame ? weldVal : noBottomWeldVal) -
                (hasSeparateCoverTop && (r.top - minFrameTop).abs() < 0.1
                    ? separateCoverThickness
                    : 0.0) -
                (hasSeparateCoverBottom &&
                        (r.bottom - maxFrameBottom).abs() < 0.1
                    ? separateCoverThickness
                    : 0.0);

      double hPiece = fHeight / 1000.0;
      double wPiece = fWidth / 1000.0;
      final targetFramePieces = useSlidingOuterFrame
          ? slidingOuterFramePieces
          : framePieces;

      if (window.hasBottomFrame) {
        targetFramePieces.addAll([wPiece, wPiece, hPiece, hPiece]);
      } else {
        targetFramePieces.addAll([wPiece, hPiece, hPiece]);
      }

      if (isOuterFramePvc) {
        double rw = r.width - renfortFrameDeduction;
        double rh = r.height - renfortFrameDeduction;
        if (rw < 0.0) rw = 0.0;
        if (rh < 0.0) rh = 0.0;

        if (window.hasBottomFrame) {
          renfortFramePieces.addAll([
            rw / 1000.0,
            rw / 1000.0,
            rh / 1000.0,
            rh / 1000.0,
          ]);
        } else {
          renfortFramePieces.addAll([rw / 1000.0, rh / 1000.0, rh / 1000.0]);
        }
      }
    }

    if (!window.hasBottomFrame) {
      for (final zone in window.zones) {
        final isBottomBound =
            (zone.boundary.bottom - (window.height - window.profileThickness))
                    .abs() <
                5.0 ||
            zone.boundary.bottom >= window.height - window.profileThickness;
        final isFixed =
            zone.content == ZoneContent.fixedGlass ||
            zone.content == ZoneContent.empty;
        if (!isBottomBound || !isFixed) continue;
        final segLeft =
            (zone.boundary.left - window.profileThickness).abs() < 5.0
            ? 0.0
            : zone.boundary.left;
        final segRight =
            (zone.boundary.right - (window.width - window.profileThickness))
                    .abs() <
                5.0
            ? window.width
            : zone.boundary.right;
        final length = math.max(0.0, segRight - segLeft);
        if (length > 0) framePieces.add(length / 1000.0);
      }
    }

    if (framePieces.isNotEmpty) {
      items.add(
        createProfile(
          'الإطار (Frame)',
          colorName,
          pieces: framePieces,
          unit: 'قطاع',
          overrideMap: outerFrameOverride,
          // The frame selected in the drawing is authoritative. A stale table
          // value from an earlier selection must not replace it.
          preferOverrideMap: true,
        ),
      );
    }

    if (slidingOuterFramePieces.isNotEmpty) {
      items.add(
        createProfile(
          'إطار منزلق (Cadre Coulissant)',
          colorName,
          pieces: slidingOuterFramePieces,
          unit: 'قطاع',
          overrideMap: getSlidingFrameSection(),
          preferOverrideMap: true,
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

    // Only a separately selected cover gets its own table row. An integrated
    // PVC cover is already included in the frame profile above.
    bool showSideCover = hasNonIntegratedSideCover;

    if (showSideCover) {
      final double pvcWeldingAllowance = isOuterFramePvc ? 5.0 : 0.0;
      List<double> sideCoverPieces = [];

      if (customSideCoverLayout) {
        // The input length is the covered span on the frame. For a standalone
        // custom piece, add its visible width for each outer edge it reaches
        // because every outside corner is cut at 45 degrees. A piece whose
        // start and end are both in the middle gets no visible-width extension.
        for (final segment in window.effectiveSideCoverSegments) {
          if (segment.side == 'bottom' && !window.hasBottomFrame) continue;
          final sideLength = window.sideCoverSideLength(segment.side);
          if (sideLength <= 0) continue;
          final start = segment.startOffset.clamp(0.0, sideLength).toDouble();
          final end = segment.endOffset.clamp(0.0, sideLength).toDouble();
          if (end <= start) continue;
          final visible = segment.visibleWidth > 0
              ? segment.visibleWidth
              : separateCoverWidth;
          final cutLength = standaloneSideCoverSegmentCutLength(
            sideLength: sideLength,
            start: start,
            end: end,
            visibleWidth: visible,
            weldingAllowance: pvcWeldingAllowance,
          );
          sideCoverPieces.add(cutLength / 1000.0);
        }
      } else {
        final double w = separateCoverWidth;
        // The standalone couvre-joint is cut using its visible width: that
        // width is included at both ends. PVC also needs 5 mm for welding;
        // aluminium does not. An integrated cover never enters this branch.

        final verticalLen = window.height + (2 * w) + pvcWeldingAllowance;
        final horizontalLen = window.width + (2 * w) + pvcWeldingAllowance;
        if (hasSeparateCoverLeft) {
          sideCoverPieces.add(verticalLen / 1000.0);
        }
        if (hasSeparateCoverRight) {
          sideCoverPieces.add(verticalLen / 1000.0);
        }
        if (hasSeparateCoverTop) {
          sideCoverPieces.add(horizontalLen / 1000.0);
        }
        if (hasSeparateCoverBottom) {
          sideCoverPieces.add(horizontalLen / 1000.0);
        }
      }

      if (sideCoverPieces.isNotEmpty) {
        items.add(
          createProfile(
            'الغطاء الجانبي (Side Cover)',
            colorName,
            pieces: sideCoverPieces,
            unit: 'قطاع',
            overrideMap: selectedSeparateCoverMap,
            preferOverrideMap: true,
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
        final double overlap = seriesSashOverlap;
        double clearW = zone.boundary.width;
        double clearH = zone.boundary.height;

        // A single visible zone is the complete frame opening. Recalculate it
        // directly from the finished window, selected caisson and selected
        // frame so old drawing geometry cannot shorten its sash cuts.
        if (window.zones.length == 1 &&
            (zone.content == ZoneContent.singleSash ||
                zone.content == ZoneContent.doubleSash)) {
          clearW = fullOpening['width']!;
          clearH = fullOpening['height']!;
        }

        if (zone.content == ZoneContent.singleSash) {
          double sashW = clearW + overlap * 2;
          double sashH = clearH + overlap * 2;
          if (zone.hasSashPlintheBottom) {
            sashPieces.addAll([sashW / 1000.0, sashH / 1000.0, sashH / 1000.0]);
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
          // The overlap belongs to the complete clear opening first.  Only
          // after adding it on both sides do we distribute the cutting width
          // between the two leaves.  This also remains correct when the
          // leaves are not 50/50.
          final totalSashWidth = clearW + overlap * 2;
          double sashWLeft = totalSashWidth * zone.doubleSashRatio;
          double sashWRight = totalSashWidth * (1.0 - zone.doubleSashRatio);
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
          final slidingSashOverride = window.slidingSashOverride;
          double slidingOverlap = slidingSashOverride != null
              ? (slidingSashOverride['sash_overlap'] ?? 8.0).toDouble()
              : 8.0;
          final configuredSlidingOverlap = slidingRuleNumber(
            'sash_overlap_val',
          );
          if (window.isSlidingPVC && configuredSlidingOverlap > 0) {
            slidingOverlap = configuredSlidingOverlap;
          }
          double wForCalc = clearW;
          double hForCalc = clearH;

          final slidingFrame = getSlidingFrameSection();
          final isNestedSliding = window.isSlidingZoneNestedInSingleFrame(zone);
          if (slidingFrame != null && isNestedSliding) {
            double frameT =
                (slidingFrame['visible_width'] as num?)?.toDouble() ?? 45.0;

            double innerFrameW = math.max(
              0.0,
              clearW - window.slidingRebateDeduction(zone, horizontal: true),
            );
            double innerFrameH = math.max(
              0.0,
              clearH - window.slidingRebateDeduction(zone, horizontal: false),
            );
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
            if (window.hasInternalSlidingSideCover &&
                window.effectiveInternalSlidingSideCoverMap != null) {
              final coverWidth = window.internalSlidingSideCoverWidth;
              if (coverWidth > 0) {
                final coverW = (innerFrameW + (coverWidth * 2.0)) / 1000.0;
                final coverH = (innerFrameH + (coverWidth * 2.0)) / 1000.0;
                internalSlidingSideCoverPieces.addAll([
                  coverW,
                  coverW,
                  coverH,
                  coverH,
                ]);
              }
            }

            wForCalc = innerFrameW - (frameT * 2.0);
            hForCalc = innerFrameH - (frameT * 2.0);
          }
          wForCalc = math.max(0.0, wForCalc);
          hForCalc = math.max(0.0, hForCalc);

          int sashes = zone.slidingSashesCount > 0
              ? zone.slidingSashesCount
              : 2;
          final configuredSashDeduction = window.slidingSashWidthDeduction(
            sashes,
          );
          double sashW = configuredSashDeduction > 0
              ? (wForCalc - configuredSashDeduction) / sashes
              : (wForCalc + ((sashes - 1) * 26.0)) / sashes;
          double sashH = hForCalc + slidingOverlap * 2;
          final String seriesName =
              window.activeSlidingSeries?.name.toLowerCase() ??
              window.activeSeries?.name.toLowerCase() ??
              '';
          final bool isTPI67000 =
              seriesName.contains('67000') || seriesName.contains('tpi');
          bool hasThreePiece =
              !window.isSlidingPVC &&
              ((window.activeSlidingSeries?.hasThreePieceSash ?? false) ||
                  isTPI67000);
          if (hasThreePiece) {
            sashH = window.height - 64.0;
          } else {
            if (window.isSlidingPVC) {
              // PVC: sash height = internal frame height + one overlap.
              sashH = hForCalc + slidingOverlap;
            } else {
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
              slidingSashTraversePieces.addAll([tLen / 1000.0, tLen / 1000.0]);
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
              slidingTotalJointBrosse +=
                  pairs * (sashH * 6 + sashW * 8) / 1000.0;
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
              slidingTotalJointBrosse +=
                  pairs * (sashH * 6 + sashW * 8) / 1000.0;
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
              !window.isSlidingPVC &&
              ((window.system?.name.toLowerCase().contains('tpr') ?? false) ||
                  (window.system?.name.toLowerCase().contains('hps') ?? false));
          if (!excludeChicane) {
            final int chicaneCount = math.max(
              2,
              window.isSlidingPVC
                  ? (sashes - 1) * pvcChicanePiecesPerJunction
                  : 2,
            );
            final double chicaneLength = sashH;
            for (int c = 0; c < chicaneCount; c++) {
              slidingChicanePieces.add(chicaneLength / 1000.0);
            }
          }

          double frameT = window.profileThickness;
          if (window.slidingFrameOverride != null) {
            frameT =
                ((window.slidingFrameOverride!['visible_width'] ??
                            window.slidingFrameOverride!['thickness'])
                        as num?)
                    ?.toDouble() ??
                window.profileThickness;
          } else {
            final frameSection = window.getSlidingSectionByType('frame');
            if (frameSection != null) {
              frameT =
                  ((frameSection.visibleWidth ?? frameSection.thickness)
                          as num?)
                      ?.toDouble() ??
                  window.profileThickness;
            }
          }
          final railFrameWidth = isNestedSliding
              ? (slidingFrame == null
                    ? zone.boundary.width
                    : math.max(
                        0.0,
                        clearW -
                            window.slidingRebateDeduction(
                              zone,
                              horizontal: true,
                            ),
                      ))
              : window.width.toDouble();
          double railLen = (railFrameWidth - (frameT * 2.0)) / 1000.0;
          if (railLen < 0) railLen = 0;
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
            overrideMap: openingSashOverride,
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
            // Plinthe is its own catalogue role. Never fall back to the
            // selected sash profile, otherwise a thick sash can replace the
            // plant when the drawing changes sash type.
            overrideMap: window.componentOverrides['بلانت (Plinthe)'] ??
                window.getSectionByType('plinthe')?.toMap(),
          ),
        );
        items.add(
          createProfile(
            'حامل الجوان (Porte-joint)',
            colorName,
            pieces: sashPlinthePieces,
            unit: 'متر',
            overrideMap: window.componentOverrides['حامل الجوان (Porte-joint)'],
            selectorType: 'porte_joint',
          ),
        );
        final porteJointLength = sashPlinthePieces.fold<double>(
          0.0,
          (sum, piece) => sum + piece,
        );
        if (porteJointLength > 0) {
          items.add(
            createJoint(
              'جوان برونز (Joint Bronze)',
              qty: porteJointLength * 2.0,
              unit: 'متر',
            ),
          );
        }
      }

      if (slidingSashPieces.isNotEmpty) {
        items.add(
          createProfile(
            'الظلفة المنزلقة (Sliding Sash)',
            colorName,
            pieces: slidingSashPieces,
            unit: 'قطاع',
            overrideMap:
                window.slidingSashOverride ??
                window.getSlidingSectionByType('sash')?.toMap(),
            preferOverrideMap: true,
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
            overrideMap:
                slidingOverrideFor(['عرضي (Traverse)']) ??
                window.getSlidingSectionByType('sash_traverse')?.toMap() ??
                window.getSlidingSectionByType('traverse')?.toMap(),
            preferOverrideMap: true,
          ),
        );
      }

      if (slidingSashLateralPieces.isNotEmpty) {
        // Determine whether reinforcement is active for lateral
        bool isLateralReinforced = window.zones.any(
          (z) =>
              z.slidingMontantReinforced['lateral_0'] == true ||
              z.slidingMontantReinforced['lateral_1'] == true,
        );

        String lateralName = isLateralReinforced
            ? 'قائم جانبي معزز (Sash Lateral Renforcé)'
            : 'قائم جانبي (Sash Lateral)';

        // Fetch user override or default normal profile
        Map<String, dynamic>? baseLateral =
            slidingOverrideFor([
              lateralName,
              'قائم جانبي (Sash Lateral)',
              'قائم جانبي (Lateral)',
            ]) ??
            window.getSlidingSectionByType('sash_lateral')?.toMap() ??
            window.getSlidingSectionByType('lateral')?.toMap();

        if (baseLateral != null) {
          final baseIsReinforced = window.isSlidingMontantReinforced(
            baseLateral,
            central: false,
          );
          if (isLateralReinforced) {
            if (!baseIsReinforced) {
              final reinforced = findReinforcedSection(
                baseLateral,
                false,
                window,
              );
              if (reinforced != null) {
                baseLateral = reinforced;
              }
            }
          } else {
            if (baseIsReinforced) {
              final normal = findNormalSection(baseLateral, false, window);
              if (normal != null) {
                baseLateral = normal;
              }
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
            preferOverrideMap: true,
          ),
        );
      }

      if (slidingSashCentralPieces.isNotEmpty) {
        // Determine whether reinforcement is active for central
        bool isCentralReinforced = window.zones.any(
          (z) => z.slidingMontantReinforced.entries.any(
            (e) => e.key.startsWith('central_') && e.value == true,
          ),
        );

        String centralName = isCentralReinforced
            ? 'قائم وسطي معزز (Sash Central Renforcé)'
            : 'قائم وسطي (Sash Central)';

        // Fetch user override or default normal profile
        Map<String, dynamic>? baseCentral =
            slidingOverrideFor([
              centralName,
              'قائم وسطي (Sash Central)',
              'قائم وسطي (Central)',
            ]) ??
            window.getSlidingSectionByType('sash_central')?.toMap() ??
            window.getSlidingSectionByType('central')?.toMap();

        if (baseCentral != null) {
          final baseIsReinforced = window.isSlidingMontantReinforced(
            baseCentral,
            central: true,
          );
          if (isCentralReinforced) {
            if (!baseIsReinforced) {
              final reinforced = findReinforcedSection(
                baseCentral,
                true,
                window,
              );
              if (reinforced != null) {
                baseCentral = reinforced;
              }
            }
          } else {
            if (baseIsReinforced) {
              final normal = findNormalSection(baseCentral, true, window);
              if (normal != null) {
                baseCentral = normal;
              }
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
            preferOverrideMap: true,
          ),
        );
      }

      if (slidingChicanePieces.isNotEmpty) {
        Map<String, dynamic>? baseChicane =
            slidingOverrideFor(['الشيكان (Chicane)']) ??
            window.getSlidingSectionByType('chicane')?.toMap() ??
            window.getSlidingSectionByType('sash_chicane')?.toMap();
        items.add(
          createProfile(
            'الشيكان (Chicane)',
            colorName,
            pieces: slidingChicanePieces,
            unit: 'قطاع',
            overrideMap: baseChicane,
            preferOverrideMap: true,
          ),
        );
      }

      if (slidingRailPieces.isNotEmpty) {
        final railOverride =
            slidingOverrideFor(['الري (Rail)']) ??
            window.getSlidingSectionByType('rail')?.toMap();
        if (railOverride != null) {
          items.add(
            createProfile(
              'الري (Rail)',
              colorName,
              pieces: slidingRailPieces,
              unit: 'قطاع',
              overrideMap: railOverride,
              preferOverrideMap: true,
            ),
          );
        }
      }

      if (internalSlidingSideCoverPieces.isNotEmpty) {
        items.add(
          createProfile(
            'غطاء إطار منزلق داخلي (Couvre-joint Coulissant)',
            colorName,
            pieces: internalSlidingSideCoverPieces,
            unit: 'قطاع',
            overrideMap: window.effectiveInternalSlidingSideCoverMap,
            preferOverrideMap: true,
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
            overrideKey: 'الظلفة (Sash)',
            selectorCategory: 'profile',
            selectorType: 'sash',
          ),
        );
      });

      if (window.isPVC) {
        double renfortSashDeduction = 140.0;
        final pvcSashOverride = window.isSlidingPVC
            ? window.slidingSashOverride
            : window.sashOverride;
        if (pvcSashOverride != null) {
          renfortSashDeduction =
              (pvcSashOverride['renfort_deduction'] as num?)?.toDouble() ??
              140.0;
        }
        final pvcSashPieces = window.isSlidingPVC
            ? <double>[...sashPieces, ...slidingSashPieces]
            : sashPieces;
        List<double> renfortSashPieces = pvcSashPieces.map((p) {
          double len = p - (renfortSashDeduction / 1000.0);
          return len < 0.0 ? 0.0 : len;
        }).toList();
        if (renfortSashPieces.isNotEmpty) {
          items.add(
            createProfile(
              'حديد الظلفة (Renfort Sash)',
              null,
              pieces: renfortSashPieces,
              unit: 'قطاع',
            ),
          );
        }

        double renfortSashMifsalDeduction = renfortSashDeduction;
        List<double> renfortSashMifsalPieces = [];
        for (var zone in window.zones) {
          final double overlap = seriesSashOverlap;
          double clearH = zone.boundary.height;

          if (zone.content == ZoneContent.singleSash) {
            double sashH = clearH + overlap * 2;
            double len =
                (sashH / 1000.0) - (renfortSashMifsalDeduction / 1000.0);
            renfortSashMifsalPieces.add(len < 0.0 ? 0.0 : len);
          } else if (zone.content == ZoneContent.doubleSash) {
            double sashH = clearH + overlap * 2;
            double len =
                (sashH / 1000.0) - (renfortSashMifsalDeduction / 1000.0);
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
        createAccessory(
          'بوشون باتمو (Bouchon Batmo)',
          color: accessoryColorName,
          qty: doubleSashCount,
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
        window.canUseOpeningOnlyOptions &&
        (activeVariants['Verrou Central'] ?? window.useVerrouCentral);
    bool isSystemObActive =
        window.canUseOpeningOnlyOptions &&
        (activeVariants['System OB'] ?? window.effectiveUseSystemOB);
    final bool canUseDemiOb = window.canUseDemiOB;
    bool isDemiObActive =
        canUseDemiOb &&
        (activeVariants['Demi System OB'] ?? window.effectiveUseDemiOB);

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
      // Every normal window handle requires one espagnolette.  OB/Demi-OB
      // only changes whether the ordinary espagnolette is active; it must
      // never silently reduce its quantity.
      final bool isEspagnoletteActive = !isSystemObActive && !isDemiObActive;
      final int espagnoletteQty = totalHandles;

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

      if (canUseDemiOb) {
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
      }

      if (useCremone && cremoneQty > 0) {
        items.add(
          createAccessory(
            'كريمون (Cremone)',
            color: accessoryColorName,
            qty: cremoneQty,
          ),
        );
        items.add(
          createAccessory(
            'تراينغل الكريمون (Triangle)',
            color: accessoryColorName,
            qty: cremoneQty,
          ),
        );
      }

      if (octoHandles > 0 && window.systemMode != 'sliding') {
        items.add(
          createAccessory(
            'مقبض أوكتو (Octo)',
            color: accessoryColorName,
            qty: octoHandles,
          ),
        );
      }
      if (pvcHandlesOnAlu > 0 && window.systemMode != 'sliding') {
        items.add(
          createAccessory(
            'مقبض نافذة بي في سي (Poignée Fenêtre PVC)',
            color: accessoryColorName,
            qty: pvcHandlesOnAlu,
          ),
        );
      }
      if (totalHandles > 0 && window.systemMode != 'sliding') {
        if (window.isPVC) {
          items.add(
            createAccessory(
              'مقبض نافذة (Poignée Fenêtre)',
              color: accessoryColorName,
              qty: totalHandles,
            ),
          );
        } else {
          items.add(
            createAccessory(
              'المقبض (Handle)',
              color: accessoryColorName,
              qty: totalHandles,
            ),
          );
        }
      }

      if (totalCompas > 0) {
        items.add(
          createAccessory(
            'كومباس (Compas)',
            color: accessoryColorName,
            qty: totalCompas,
          ),
        );
      }
      if (normalDoorHandles > 0 && window.systemMode != 'sliding') {
        items.add(
          createAccessory(
            'مقبض الباب عادي (Poignée Porte)',
            color: accessoryColorName,
            qty: normalDoorHandles,
          ),
        );
      }
      if (marechal125Handles > 0 && window.systemMode != 'sliding') {
        items.add(
          createAccessory(
            'مقبض كبير ماريشال 1.25 متر (Poignée Maréchal 1.25m)',
            color: accessoryColorName,
            qty: marechal125Handles,
          ),
        );
      }
      if (marechal2mHandles > 0 && window.systemMode != 'sliding') {
        items.add(
          createAccessory(
            'مقبض كبير ماريشال 2 متر (Poignée Maréchal 2m)',
            color: accessoryColorName,
            qty: marechal2mHandles,
          ),
        );
      }
      if (rollerLocks > 0 && window.systemMode != 'sliding') {
        items.add(
          createAccessory(
            'قفل رولون (Serrure à Rouleau)',
            color: accessoryColorName,
            qty: rollerLocks,
          ),
        );
      }
      if (keyHandles > 0 && window.systemMode != 'sliding') {
        items.add(
          createAccessory(
            'مقبض الباب (Poignée Porte à Clé)',
            color: accessoryColorName,
            qty: keyHandles,
          ),
        );
      }
      if (condamnationHandles > 0 && window.systemMode != 'sliding') {
        items.add(
          createAccessory(
            'مقبض الباب Condamnation (Poignée Condamnation)',
            color: accessoryColorName,
            qty: condamnationHandles,
          ),
        );
      }
      if (keyLocks > 0 && window.systemMode != 'sliding') {
        items.add(
          createAccessory(
            'قفل الباب (Serrure)',
            color: accessoryColorName,
            qty: keyLocks,
          ),
        );
      }
      if (condamnationLocks > 0 && window.systemMode != 'sliding') {
        items.add(
          createAccessory(
            'قفل الباب Condamnation (Serrure Condamnation)',
            color: accessoryColorName,
            qty: condamnationLocks,
          ),
        );
      }
      if (pointLocks > 0 && window.systemMode != 'sliding') {
        items.add(
          createAccessory(
            'قفل نقطة',
            color: accessoryColorName,
            qty: pointLocks,
          ),
        );
      }
      if (doorCanons > 0 && window.systemMode != 'sliding') {
        items.add(
          createAccessory(
            'الأسطوانة (Canon)',
            color: accessoryColorName,
            qty: doorCanons,
          ),
        );
      }
      if (gachePortes > 0 && window.systemMode != 'sliding') {
        items.add(
          createAccessory(
            'قاش بورت (Gache Porte)',
            color: accessoryColorName,
            qty: gachePortes,
          ),
        );
      }
      if (totalHinges > 0 && window.systemMode != 'sliding') {
        items.add(
          createAccessory(
            'المفاصل (Hinges)',
            color: accessoryColorName,
            qty: totalHinges,
          ),
        );
      }

      if (slidingTotalRoulettes > 0) {
        items.add(
          createAccessory(
            'عجلات المنزلق (Roulettes)',
            color: accessoryColorName,
            qty: slidingTotalRoulettes,
          ),
        );
        if (!window.isSlidingPVC) {
          final String seriesName =
              window.activeSlidingSeries?.name.toLowerCase() ?? '';
          String kitKey = 'كيت 67000 (Kit 67000)';
          if (seriesName.contains('76000')) {
            kitKey = 'كيت 76000 (Kit 76000)';
          } else if (seriesName.contains('40000')) {
            kitKey = 'كيت 40000 (Kit 40000)';
          } else if (seriesName.contains('67000')) {
            kitKey = 'كيت 67000 (Kit 67000)';
          }
          items.add(createAccessory(kitKey, color: accessoryColorName, qty: 1));
        }
        final bool useEntrematique =
            !window.isSlidingPVC &&
            window.zones.any(
              (z) =>
                  z.content == ZoneContent.slidingSash &&
                  z.useClassicHandle != true,
            );

        if (useEntrematique) {
          items.add(
            createAccessory(
              'أونتروماتيك (Entrematique)',
              color: accessoryColorName,
              qty: slidingTotalHandles,
            ),
          );
        } else {
          items.add(
            createAccessory(
              'اسبانيولات المنزلق (Espagnolette)',
              color: accessoryColorName,
              qty: slidingTotalEspagnolettes,
            ),
          );
          items.add(
            createAccessory(
              // PVC sliding uses the same window handle catalogue as the
              // French-opening system.  Only aluminium keeps a dedicated
              // sliding-handle key.
              window.isSlidingPVC
                  ? 'مقبض نافذة (Poignée Fenêtre)'
                  : 'مقبض منزلق (Poignée Coulissante)',
              color: accessoryColorName,
              qty: slidingTotalHandles,
            ),
          );
          final String seriesName =
              window.activeSlidingSeries?.name.toLowerCase() ?? '';
          final bool isTPR = seriesName.contains('tpr') && !window.isSlidingPVC;
          if (isTPR) {
            items.add(
              createAccessory(
                'Gâche coulissant TPR',
                color: accessoryColorName,
                qty: slidingTotalEspagnolettes,
              ),
            );
            items.add(
              createAccessory(
                'تراينغل الكريمون (Triangle)',
                color: accessoryColorName,
                qty: slidingTotalEspagnolettes,
              ),
            );
          } else {
            items.add(
              createAccessory(
                'كاش كوليسون (Gache coulissant)',
                color: accessoryColorName,
                qty: slidingTotalGacheCoulissant,
              ),
            );
          }
        }

        // Add Gache Porte (قاش بورت) if it is a door
        final isDoor =
            window.system?.name.toLowerCase().contains('porte') ?? false;
        if (isDoor) {
          items.add(
            createAccessory(
              'قاش بورت (Gache Porte)',
              color: accessoryColorName,
              qty: 2,
            ),
          );
        }

        // الصيغة الموحدة لا تحتاج تبديل خاص بـ PVC

        // 🟢 جوان بروس للظلفة: لا يُضاف تلقائياً لسلاسل الألمنيوم مثل TPR 67000
        // إلا إذا كان خيار جوان البروس مخصصاً ومحدداً صراحة لهذه السلسلة أو إذا كان النظام PVC
        if (window.isSlidingPVC ||
            window.componentOverrides.containsKey(
              'جوان بروس للظلفة (Joint Brosse Sash)',
            )) {
          items.add(
            createJoint(
              'جوان بروس للظلفة (Joint Brosse Sash)',
              color: colorName,
              qty: slidingTotalJointBrosse,
              unit: 'متر',
            ),
          );
        }

        slidingGlassJoints.forEach((jointName, totalLength) {
          items.add(createJoint(jointName, qty: totalLength, unit: 'متر'));
        });
      }

      // Add Bouchon Parclose (بوشون بارك لوز) for opening systems
      if ((hasSingleSash || hasDoubleSash) && window.systemMode != 'sliding') {
        if (window.componentOverrides.containsKey(
          'بوشون بارك لوز (Bouchon Parclose)',
        )) {
          items.add(
            createAccessory(
              'بوشون بارك لوز (Bouchon Parclose)',
              color: accessoryColorName,
              qty: 4 * (singleSashCount + doubleSashCount),
            ),
          );
        }
        if (!useCremone &&
            window.componentOverrides.containsKey('كريمون (Cremone)')) {
          items.add(
            createAccessory(
              'كريمون (Cremone)',
              color: accessoryColorName,
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
      final selectedBlade = window.componentOverrides['الشرائح (Lames)'];
      if (selectedBlade != null) {
        final bladeText =
            '${selectedBlade['name'] ?? ''} ${selectedBlade['shutter_subtype'] ?? ''}'
                .toLowerCase();
        // X3D and Extrudé are two catalogue labels for the same heavy blade.
        isExtrudedBlade =
            bladeText.contains('x3d') ||
            bladeText.contains('extrud') ||
            bladeText.contains('إكسترودي') ||
            bladeText.contains('اكسترودي');
      }
      final bool isX3dPvcAssembly =
          isExtrudedBlade && window.isPVC && !isTunnel;

      bool showIndividualOptions = isTunnel || isExtrudedBlade;

      // A shutter kit is enabled by default. Its actual logical key depends
      // on the mechanism, so checking only the old generic "كيت (Kit)" key
      // made the Attache calculation ignore a visible Kit Volet.
      const shutterKitKeys = [
        'كيت (Kit)',
        'كيت فولي موتور (Kit Volet Moteur)',
        'كيت فولي مانيفر (Kit Volet Manivelle)',
        'كيت مانيفر (Kit Manivelle)',
        'كيت حزام (Kit Sangle)',
        'كيت فولي (Kit Volet)',
      ];
      final explicitKitStates = shutterKitKeys
          .where(activeVariants.containsKey)
          .map((key) => activeVariants[key]!)
          .toList();
      final bool isKitActive =
          !isTunnel &&
          (explicitKitStates.isEmpty ||
              explicitKitStates.any((value) => value));
      bool isTandemActive =
          !isX3dPvcAssembly &&
          showIndividualOptions &&
          (activeVariants['طانديم (Tandem)'] ?? true);
      bool isEmboutActive =
          isX3dPvcAssembly ||
          (showIndividualOptions &&
              (activeVariants['الامبو (Embout)'] ?? false));
      bool isSupportRoulementActive =
          isX3dPvcAssembly ||
          (showIndividualOptions &&
              (activeVariants['سيبور رولمو (Support Roulement)'] ?? false));
      final selectedMotor = window.componentOverrides['المحرك (Moteur)'];
      final rawEmergencyCrank = selectedMotor?['motor_has_emergency_crank'];
      final motorHasEmergencyCrank = rawEmergencyCrank is bool
          ? rawEmergencyCrank
          : rawEmergencyCrank is num
          ? rawEmergencyCrank != 0
          : const [
              '1',
              'true',
              'yes',
              'oui',
              'نعم',
            ].contains(rawEmergencyCrank?.toString().trim().toLowerCase());
      bool isSupportMoteurActive = isX3dPvcAssembly
          ? isMotor && !motorHasEmergencyCrank
          : (showIndividualOptions &&
                (activeVariants['سيبور موتور (Support Moteur)'] ?? true));
      final rawBladeEndCap =
          window.componentOverrides['أغطية الشفرات (Bouchons Lames)'];
      final linkedBladeEndCap =
          selectedBlade != null &&
              rawBladeEndCap != null &&
              WindowModel.isBladeEndCapLinkedTo(
                Map<String, dynamic>.from(rawBladeEndCap),
                Map<String, dynamic>.from(selectedBlade),
              )
          ? Map<String, dynamic>.from(rawBladeEndCap)
          : null;
      final isBouchonLameActive = linkedBladeEndCap != null;
      final bladeWeightPerSqm =
          (selectedBlade?['weight_per_sqm'] as num?)?.toDouble() ??
          double.tryParse(selectedBlade?['weight_per_sqm']?.toString() ?? '') ??
          0.0;
      final bladeMeasurementText = (selectedBlade?['measurement'] ?? '')
          .toString()
          .trim();
      final bladeMeasurementMatch = RegExp(
        r'\d+(?:[.,]\d+)?',
      ).firstMatch(bladeMeasurementText);
      final selectedBladeHeightMm = bladeMeasurementMatch == null
          ? 43.0
          : (double.tryParse(
                  bladeMeasurementMatch.group(0)!.replaceAll(',', '.'),
                ) ??
                43.0);
      final bladeCapThicknessMm = linkedBladeEndCap == null
          ? 0.0
          : ((linkedBladeEndCap['cap_thickness'] as num?)?.toDouble() ??
                double.tryParse(
                  linkedBladeEndCap['cap_thickness']?.toString() ?? '',
                ) ??
                0.0);
      final shutterWeightKg = shutterCurtainWeightKg(
        windowWidthMm: window.width.toDouble(),
        windowHeightMm: window.height.toDouble(),
        shutterBoxHeightMm: window.shutterBoxHeight,
        isTunnel: isTunnel,
        bladeHeightMm: selectedBladeHeightMm,
        bladeWeightPerSqm: bladeWeightPerSqm,
        bladeEndCapThicknessMm: bladeCapThicknessMm,
      );

      // ===== 1. الكيت (Kit) - أول مركب، فقط لغير النفق =====
      void addAndExpandKit(
        String uiKey,
        String descriptionCode, {
        bool filterAxeItems = true,
        bool sizeBound = true,
        bool showKitRow = true,
        List<String> preferredKitTokens = const [],
      }) {
        String? matchedKitName;
        String? actualKitName;
        if (window.componentOverrides.containsKey(uiKey)) {
          final overrideItem = window.componentOverrides[uiKey];
          // Ignore legacy values that were incorrectly saved from
          // ShutterComponents.  Only a KitBundles selection is allowed to
          // override the actual bundle chosen below.
          if (overrideItem['catalog_source'] == 'KitBundles') {
            actualKitName = overrideItem['name']?.toString();
          }
        }

        final candidates = compatibleKitBundles(
          kits: kitBundleMetadata.values,
          descriptionCode: descriptionCode,
          minimumSizeMm: sizeBound ? window.shutterBoxHeight : null,
          allowWithoutSize: !sizeBound,
        );
        final normalizedPreferredTokens = preferredKitTokens
            .map((token) => token.trim().toLowerCase())
            .where((token) => token.isNotEmpty)
            .toList(growable: false);
        final preferredCandidates = normalizedPreferredTokens.isEmpty
            ? const <Map<String, dynamic>>[]
            : candidates.where((kit) {
                final searchable = [
                  kit['name'],
                  kit['measurement'],
                  kit['description'],
                ].whereType<Object>().join(' ').toLowerCase();
                return normalizedPreferredTokens.any(
                  (token) => searchable.contains(token),
                );
              }).toList(growable: false);
        final orderedCandidates = preferredCandidates.isNotEmpty
            ? preferredCandidates
            : candidates;
        if (actualKitName != null && actualKitName.isNotEmpty) {
          final manual = candidates.where(
            (kit) => (kit['name'] ?? '').toString() == actualKitName,
          );
          if (manual.isNotEmpty) {
            matchedKitName = actualKitName;
          }
        }
        matchedKitName ??= orderedCandidates.isEmpty
            ? null
            : (orderedCandidates.first['name'] ?? '').toString();

        // Compatibility fallback for orders saved before description codes
        // were introduced. New catalogues always use the code above.
        if (matchedKitName == null && kitBundleMetadata.isEmpty) {
          final targetSize = window.shutterBoxHeight;
          final legacy =
              kitBundleData.keys.where((name) {
                final normalized = name.toLowerCase();
                if (descriptionCode == 'MT') {
                  return normalized.contains('moteur');
                }
                return normalized.contains('kit volet') &&
                    !normalized.contains('moteur');
              }).toList()..sort((a, b) {
                final aSize = kitBundleSizeMm({'name': a}) ?? double.infinity;
                final bSize = kitBundleSizeMm({'name': b}) ?? double.infinity;
                return aSize.compareTo(bSize);
              });
          for (final name in legacy) {
            final size = kitBundleSizeMm({'name': name});
            if (size != null && size + 0.5 >= targetSize) {
              matchedKitName = name;
              break;
            }
          }
        }

        // A kit must always come from KitBundles. Do not invent a generic
        // "Kit" line from Accessories/ShutterComponents when no configured
        // bundle exists on the Kits page.
        if (matchedKitName == null) return;
        final String groupName = matchedKitName;
        final bool perLeaf = kitPerLeafMap[groupName] ?? false;
        final double kitQty = perLeaf
            ? ((doubleSashCount * 2) + singleSashCount).toDouble()
            : 1.0;

        // `isMotorized` describes the mechanism, but every kit uses the
        // same source: its KitBundles record and exact stored French name.
        // The tunnel kit is only a configuration container; its real child
        // parts are listed directly instead of creating a fictitious BOM row.
        if (showKitRow) {
          items.add(createKitBundle(uiKey, groupName, qty: kitQty));
        }

        final matchedKitItems = kitBundleData[groupName];
        if (matchedKitItems?.isNotEmpty == true) {
          final String shutterVariant = isExtrudedBlade ? 'extruded' : 'normal';
          final int leafCount = perLeaf
              ? ((doubleSashCount * 2) + singleSashCount)
              : 1;
          var expandedItems = expandKitBundle(
            groupName,
            matchedKitItems!,
            leafHeightMm: window.height.toDouble(),
            leafWidthMm: window.width.toDouble(),
            shutterWeightKg: shutterWeightKg,
            mechanismScope: shutterMechanismScope(window.shutterMechanism),
            mechanismScopes: shutterMechanismScopes(
              window.shutterMechanism,
              motorHasEmergencyCrank: motorHasEmergencyCrank,
            ),
            bladeScope: isExtrudedBlade ? 'extruded' : 'normal',
            isActive: true,
            // دائماً مفعَّل — لا تُشطَب عناصر الكيت
            leafCount: leafCount,
            category: 'shutter',
            variantValue: shutterVariant,
            groupExpandedItems: showKitRow,
          );
          // If Axe is 60mm (separate row), exclude axe items already inside kit bundle
          if (filterAxeItems) {
            expandedItems = expandedItems.where((bi) {
              final n = bi.name.toLowerCase();
              final on = bi.originalName.toLowerCase();
              return !n.contains('laxe') &&
                  !n.contains('axe') &&
                  !n.contains('محور') &&
                  !on.contains('laxe') &&
                  !on.contains('_laxe') &&
                  !on.contains('_axe') &&
                  !on.contains('محور');
            }).toList();
          }
          items.addAll(expandedItems);
        }
      }

      if (!isTunnel) {
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
            'MT',
            filterAxeItems: true,
          );
        } else if (isCrank) {
          // Belt and crank share one shutter kit. Each component declares
          // whether it is common, belt-only or crank-only.
          addAndExpandKit('كيت فولي مانيفر (Kit Volet Manivelle)', 'V');
          addAndExpandKit('كيت مانيفر (Kit Manivelle)', 'M', sizeBound: false);
        } else {
          // حزام (Sangle): DB: "Kit volet 155", "Kit volet 185", "Kit volet 205"
          // الاسم الدقيق يؤخذ من componentOverrides تلقائياً، keywords هي فقط للاحتياط
          addAndExpandKit('كيت فولي (Kit Volet)', 'V');
        }
        // براغي الكيت
        items.add(createShutter('براغي الكيت', qty: 8));
      } else {
        // Select the configured CT bundle matching the selected tunnel kit and
        // tunnel height when the catalogue contains more than one variant.
        final tunnelKitType =
            window.caissonPayload?['kitType']?.toString().toLowerCase() ?? '';
        final tunnelSize = window.caissonTunnelHeight.toInt().toString();
        addAndExpandKit(
          'كيت صندوق النفق (Kit Caisson Tunnel)',
          'CT',
          sizeBound: false,
          filterAxeItems: false,
          showKitRow: true,
          preferredKitTokens: [tunnelKitType, tunnelSize],
        );
      }

      // The tunnel kit supplies the tunnel-specific profiles. The ordinary
      // shutter rows still have to be calculated from the actual shutter
      // width/height and selected blade, motor and rail catalogue entries.
      // Only the regular overhead caisson itself is omitted in tunnel mode;
      // it is represented by the configured CT kit above.
      // ===== 2. الصندوق وبراغيه =====
      if (!isTunnel) {
        List<double> caissonPieces = [window.width / 1000.0 - 0.01];
        items.add(
          createShutter(
            'الصندوق (Caisson)',
            color: shutterColorName,
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
            createShutter(
              'المانيفال (Manivelle)',
              color: shutterColorName,
              qty: 1,
            ),
          );
          items.add(createShutter('براغي المانيفال', qty: isTunnel ? 1 : 4));
        } else if (window.shutterMechanism == 'محرك') {
          items.add(
            createShutter('المحرك (Moteur)', color: shutterColorName, qty: 1),
          );
          items.add(createShutter('براغي المحرك', qty: isTunnel ? 1 : 4));
          if (window.motorHasInterrupteur) {
            items.add(createShutter('قاطعة (Interrupteur)', qty: 1));
          }
          if (window.motorHasTelecommande) {
            items.add(createShutter('جهاز تحكم (Télécommande)', qty: 1));
          }
        }

        // ===== 5. الشفرات (Lames) =====
        // The blade catalogue measurement is its physical height in mm.  It
        // drives the number of blades; old records without a value retain the
        // former 43 mm fallback.
        final bladeHeightSource = (selectedBlade?['measurement'] ?? '')
            .toString()
            .trim();
        final bladeHeightMatch = RegExp(
          r'\d+(?:[.,]\d+)?',
        ).firstMatch(bladeHeightSource);
        final bladeHeightMm = bladeHeightMatch == null
            ? 43.0
            : (double.tryParse(
                    bladeHeightMatch.group(0)!.replaceAll(',', '.'),
                  ) ??
                  43.0);
        final safeBladeHeightMm = bladeHeightMm > 0 ? bladeHeightMm : 43.0;
        int numBladesShutter = isTunnel
            ? ((window.height + 100) / safeBladeHeightMm).ceil()
            : ((window.height - window.shutterBoxHeight) / safeBladeHeightMm +
                      2)
                  .ceil();
        if (numBladesShutter < 0) numBladesShutter = 0;

        double bladeLengthM = (window.width - 65) / 1000.0;
        // The exact cap linked to this blade shortens every blade at both ends.
        // No generic cap or hard-coded thickness is allowed as a fallback.
        if (linkedBladeEndCap != null) {
          final rawThickness = linkedBladeEndCap['cap_thickness'];
          final bladesCapThickness = rawThickness is num
              ? rawThickness.toDouble()
              : double.tryParse(rawThickness?.toString() ?? '') ?? 0.0;
          bladeLengthM -= (2 * bladesCapThickness) / 1000.0;
        }
        List<double> bladePieces = List.filled(numBladesShutter, bladeLengthM);
        items.add(
          createShutter(
            'الشرائح (Lames)',
            color: shutterColorName,
            pieces: bladePieces,
            unit: 'بارة',
          ),
        );

        // ===== 6. أغطية الشفرات (Bouchons Lames) =====
        // الكمية يجب أن تكون زوجية دائماً: إذا كان عدد اللامات فردياً
        // نأخذ العدد الزوجي الأدنى (31 -> 30).
        // End caps are automatic and are shown only in the quantity/cost table.
        // They are never a blade choice or a user-toggleable variant.
        if (isBouchonLameActive) {
          final int bladeEndCapQty = numBladesShutter.isOdd
              ? numBladesShutter - 1
              : numBladesShutter;
          items.add(
            createShutter(
              'أغطية الشفرات (Bouchons Lames)',
              qty: math.max(0, bladeEndCapQty).toDouble(),
              unit: 'حبة',
            ),
          );
        }

        // ===== 7. الشريحة النهائية (Lame Finale) =====
        double lameFinaleLengthM = (window.width - 65) / 1000.0;
        if (linkedBladeEndCap != null) {
          final rawThickness = linkedBladeEndCap['cap_thickness'];
          final finalBladeCapThickness = rawThickness is num
              ? rawThickness.toDouble()
              : double.tryParse(rawThickness?.toString() ?? '') ?? 0.0;
          lameFinaleLengthM -= (2 * finalBladeCapThickness) / 1000.0;
        }
        List<double> lameFinalePieces = [lameFinaleLengthM];
        items.add(
          createShutter(
            'الشريحة النهائية (Lame Finale)',
            color: shutterColorName,
            pieces: lameFinalePieces,
            unit: 'بارة',
          ),
        );

        // ===== 8. السكك (Coulisses) =====
        List<double> coulissePieces = [coulisseLengthM, coulisseLengthM];
        items.add(
          createShutter(
            'السكك (Coulisses)',
            color: shutterColorName,
            pieces: coulissePieces,
            unit: 'بارة',
          ),
        );

        // ===== 9. جوان بروس (Joint Brosse) =====
        if (isTunnel) {
          items.add(
            createShutter(
              'جوان بروس للستار (Joint Brosse Shutter)',
              qty: coulisseLengthM * 4,
              unit: 'متر',
            ),
          );
        } else {
          items.add(
            createJoint(
              'جوان بروس للستار (Joint Brosse Shutter)',
              qty: coulisseLengthM * 4,
              unit: 'متر',
            ),
          );
        }

        // ===== 10. أطاش (Attache) =====
        // Every active shutter kit contains two Attaches. Count the total from
        // shutter width, then list only the remaining standalone Attaches:
        // 2 below 1200 mm, 3 from 1200 mm, 4 from 1600 mm, and 5 from 2000 mm.
        final int totalAttaches = window.width >= 2000
            ? 5
            : (window.width >= 1600 ? 4 : (window.width >= 1200 ? 3 : 2));
        final int attachesIncludedByKit = isKitActive ? 2 : 0;
        final int attachesToAdd = (totalAttaches - attachesIncludedByKit)
            .clamp(0, totalAttaches)
            .toInt();
        if (attachesToAdd > 0) {
          items.add(
            createShutter('أطاش (Attache)', qty: attachesToAdd.toDouble()),
          );
        }

        // ===== 11. الإكسسوارات الفردية (Tandem, Embout, Support Roulement, Support Moteur) =====
      if (showIndividualOptions) {
          // X3D parts are required in addition to the standard motor kit, so
          // they must remain visible even when a kit is active.
          if (!isKitActive || isX3dPvcAssembly) {
            if (!isX3dPvcAssembly) {
              // Tandem is not part of the X3D PVC assembly.
              items.add(
                createInteractiveAccessory(
                  'طانديم (Tandem)',
                  'tandem_group',
                  isActive: isTandemActive,
                  qty: 1,
                  category: 'shutter',
                ),
              );
            }

            // Embout and Support Roulement (only if Tandem is NOT active)
            if (!isTandemActive || isX3dPvcAssembly) {
              items.add(
                createInteractiveAccessory(
                  'الامبو (Embout)',
                  'embout_group',
                  isActive: isEmboutActive,
                  qty: 1,
                  category: 'shutter',
                ),
              );
              items.add(
                createInteractiveAccessory(
                  'سيبور رولمو (Support Roulement)',
                  'roulement_group',
                  isActive: isSupportRoulementActive,
                  qty: 1,
                  category: 'shutter',
                ),
              );
            }

            // Support Moteur is needed for X3D only when the selected motor
            // has no emergency manivelle.
            if (!isX3dPvcAssembly || isSupportMoteurActive) {
              items.add(
                createInteractiveAccessory(
                  'سيبور موتور (Support Moteur)',
                  'motor_support_group',
                  isActive: isSupportMoteurActive,
                  qty: 1,
                  category: 'shutter',
                ),
              );
            }
          }
      }
    }

    if (hasSlidingSash) {
      if (!window.isSlidingPVC) {
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
        final String seriesName =
            window.activeSlidingSeries?.name.toLowerCase() ??
            window.activeSeries?.name.toLowerCase() ??
            '';
        final bool isTPI67000 =
            seriesName.contains('67000') ||
            seriesName.contains('tpi') ||
            seriesName.contains('tpr');
        if (isTPI67000) {
          items.add(createAccessory('Clam 67000', qty: 4));
        }
      }
    }

    if (hasSingleSash || hasDoubleSash) {
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
    final selectedSashSection = window.getSectionByType('sash');
    double sw = window.sashOverride != null
        ? (window.sashOverride!['visible_width'] ?? window.profileThickness)
              .toDouble()
        : (selectedSashSection?.visibleWidth ??
              window.getSectionThickness(
                'sash',
                fallback: window.profileThickness,
              ));
    if (sw <= 0) sw = window.profileThickness;

    // --- 3.5 حساب أعمدة التقسيم للألمنيوم (Traverse / Mullion) ---
    double totalMullionLengthMeters = 0.0;
    List<double> mullionPieces = [];
    final Map<String, List<double>> selectedMullionPieces = {};
    final Map<String, Map<String, dynamic>> selectedMullionSections = {};

    void addOuterMullionPiece(_MullionSegment segment, bool isHorizontal) {
      final length = (segment.end - segment.start) / 1000.0;
      if (length <= 0) return;

      final section = window.effectiveMullionSectionAt(
        isHorizontal,
        segment.position,
      );
      final isDoubleFrame = window.isDoubleFrameMullionAt(
        isHorizontal,
        segment.position,
      );
      if (section == null) {
        mullionPieces.add(length);
        totalMullionLengthMeters += length;
        return;
      }

      final sectionId = section['id']?.toString() ?? 'custom';
      final groupKey = '$sectionId:${isDoubleFrame ? 'double' : 'single'}';
      final pieces = selectedMullionPieces.putIfAbsent(groupKey, () => []);
      final physicalPieces = isDoubleFrame ? 2 : 1;
      for (var i = 0; i < physicalPieces; i++) {
        pieces.add(length);
      }
      selectedMullionSections[groupKey] = section;
      totalMullionLengthMeters += length * physicalPieces;
    }

    // Collect all frame mullion segments from adjacent zones
    final List<_MullionSegment> horizontalSegments = [];
    final List<_MullionSegment> verticalSegments = [];
    final double mullionT = window.maximumMullionThickness;

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
      addOuterMullionPiece(seg, true);
    }

    for (var seg in finalV) {
      addOuterMullionPiece(seg, false);
    }

    final sashSection = window.getSectionByType('sash');
    double sashVisibleWidth = sashSection?.visibleWidth ?? 70.0;
    if (sashVisibleWidth == 0.0) sashVisibleWidth = 70.0;

    final double overlap = seriesSashOverlap;

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
        final totalSashWidth = clearW + overlap * 2;
        double sashWLeft = totalSashWidth * zone.doubleSashRatio;
        double sashWRight = totalSashWidth * (1.0 - zone.doubleSashRatio);
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
                bool segActive = true;
                double leftRatio = c == 0 ? 0.0 : vPositions[c - 1];
                double rightRatio = c == cols - 1 ? 1.0 : vPositions[c];

                if (segActive) {
                  if (pieceStart < 0) pieceStart = leftRatio;
                  bool endPiece = c == cols - 1;
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
                    bool hasHAbove = true;
                    if (hasHAbove) len -= dividerThicknessMm / 2;
                  }
                  if (r < rows - 1) {
                    bool hasHBelow = true;
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
                bool segActive = true;
                double topRatio = r == 0 ? 0.0 : hPositions[r - 1];
                double bottomRatio = r == rows - 1 ? 1.0 : hPositions[r];

                if (segActive) {
                  if (pieceTop < 0) pieceTop = topRatio;
                  bool endPiece = r == rows - 1;
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
                    bool hasVLeft = true;
                    if (hasVLeft) len -= dividerThicknessMm / 2;
                  }
                  if (c < cols - 1) {
                    bool hasVRight = true;
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
                bool segActive = true;
                double leftRatio = c == 0 ? 0.0 : vPositions[c - 1];
                double rightRatio = c == cols - 1 ? 1.0 : vPositions[c];

                if (segActive) {
                  if (pieceStart < 0) pieceStart = leftRatio;
                  bool endPiece = c == cols - 1;
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
                    bool hasHAbove = true;
                    if (hasHAbove) len -= dividerThicknessMm / 2;
                  }
                  if (r < rows - 1) {
                    bool hasHBelow = true;
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
                bool segActive = true;
                double topRatio = r == 0 ? 0.0 : hPositions[r - 1];
                double bottomRatio = r == rows - 1 ? 1.0 : hPositions[r];

                if (segActive) {
                  if (pieceTop < 0) pieceTop = topRatio;
                  bool endPiece = r == rows - 1;
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
                    bool hasVLeft = true;
                    if (hasVLeft) len -= dividerThicknessMm / 2;
                  }
                  if (c < cols - 1) {
                    bool hasVRight = true;
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
      final allMullionPieces = <double>[
        ...mullionPieces,
        for (final pieces in selectedMullionPieces.values) ...pieces,
      ];

      if (mullionPieces.isNotEmpty) {
        items.add(
          createProfile(
            'تقسيم الزجاج (Mullion)',
            colorName,
            pieces: mullionPieces,
            unit: 'قطاع',
          ),
        );
      }
      for (final entry in selectedMullionPieces.entries) {
        final section = selectedMullionSections[entry.key]!;
        final isDoubleFrame = entry.key.endsWith(':double');
        final label = isDoubleFrame
            ? 'Cadre doublé — ${section['code'] ?? section['name'] ?? ''}'
            : 'تقسيم الزجاج (Mullion) — ${section['code'] ?? section['name'] ?? ''}';
        items.add(
          createProfile(
            label,
            colorName,
            pieces: entry.value,
            unit: 'قطاع',
            overrideMap: section,
            preferOverrideMap: true,
          ),
        );
      }

      if (window.isPVC) {
        items.add(
          createProfile(
            'حديد التقسيم (Renfort Mullion)',
            null,
            pieces: allMullionPieces,
            unit: 'قطاع',
          ),
        );
        // Add screws for this reinforcement
        int mullionRenfortScrews = 0;
        for (var p in allMullionPieces) {
          mullionRenfortScrews += ((p * 1000.0 / 500.0) + 1)
              .ceilToDouble()
              .toInt();
        }

        int index = items.indexWhere(
          (item) => item.originalName == 'براغي حديد الدعم',
        );
        if (index != -1) {
          final existing = items[index];
          // Since the existing item already has the multiplied quantity, we multiply the new batch here before adding
          items[index] = existing.copyWith(
            qty: existing.quantity + (mullionRenfortScrews * window.quantity),
          );
        } else {
          items.add(
            createAccessory('براغي حديد الدعم', qty: mullionRenfortScrews),
          );
        }
      }
    }

    // --- 3.7 حساب إكسسوار الطاسو (Tasso) ---
    final divisionPieceCount =
        mullionPieces.length +
        selectedMullionPieces.values.fold<int>(
          0,
          (sum, pieces) => sum + pieces.length,
        );
    final int tassoQty = tassoQuantity(
      divisionPieceCount: divisionPieceCount,
      isPvc: isOuterFramePvc,
      // The regular caisson is drawn above the window.  A tunnel caisson is
      // installed behind it, so it must not receive the PVC Tasso pair.
      hasRegularCaissonAboveWindow: hasShutter && !window.isCaissonTunnel,
      selectedFrameHasIntegratedCover: integratedFrameCoverWidth > 0,
    );

    if (tassoQty > 0) {
      items.add(
        createAccessory('الطاسو (Tasso)', qty: tassoQty, isActive: true),
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
    final Map<String, List<double>> bardagePiecesByColor = {};
    final Map<String, String> bardageColorNames = {};
    final Map<String, Map<String, dynamic>?> bardageColorData = {};
    List<double> parcloseSimplePieces = [];
    List<double> parcloseDoublePieces = [];
    double requiredOpeningParcloseDoubleThickness = 0.0;
    double maxOpeningSimpleGlassPackThickness = 0.0;
    double maxOpeningDoubleGlassPackThickness = 0.0;
    // Sliding and opening systems may use different parclose profiles even
    // when they share the same drawing. Keep their cutting lists separate so
    // each one is resolved from its own active series.
    List<double> slidingParcloseSimplePieces = [];
    List<double> slidingParcloseDoublePieces = [];
    double requiredSlidingParcloseDoubleThickness = 0.0;
    List<double> reducteurPieces = [];
    bool hasSimpleGlassReducerPieces = false;
    bool truthyOption(Object? value) {
      if (value is bool) return value;
      if (value is num) return value != 0;
      final text = value?.toString().trim().toLowerCase() ?? '';
      return text == '1' || text == 'true' || text == 'yes' || text == 'oui';
    }

    bool profileSkipsGlazingBead(Map<String, dynamic>? profile) {
      if (profile == null) return false;
      return truthyOption(profile['design_skip_glazing_bead']) ||
          truthyOption(profile['skip_glazing_bead']);
    }

    final bool openingSashSkipsGlazingBead = profileSkipsGlazingBead(
      window.sashOverride,
    );

    // ===== متغيرات جوانات نظام الفتح (ألمنيوم فقط) =====
    // Vitrage and Bourrage can be linked to different physical gasket types.
    // Keep them as separate BOM rows even when their length is derived from
    // the same glazing/parclose perimeter.
    // Frappe   = محيط الظلفة + محيط الإطار (لكل فتحة بها ظلفة)
    // Central  = محيط الإطار (فتحات مزدوجة فقط)
    double swingFrappeSashPerim = 0.0; // مجموع محيطات الظلفات (متر)
    double swingFrappeFramePerim =
        0.0; // مجموع محيطات الإطارات للفتحات ذات الظلفات (متر)
    double swingCentralFramePerim =
        0.0; // مجموع محيطات الإطارات للفتحات المزدوجة (متر)

    // Bardage is a profile from the active series, never a priced panel from
    // the glass catalogue. Its visible width controls the slat count and its
    // thickness selects the matching parclose.
    double bardageProfileValue(String key) {
      final override = window.componentOverrides['البارداج (Bardage)'];
      final value = override?[key];
      return value is num
          ? value.toDouble()
          : double.tryParse(value?.toString() ?? '') ?? 0.0;
    }

    double getBardageVisibleWidth() => bardageProfileValue('visible_width');

    double getBardageThickness() => bardageProfileValue('thickness');

    String bardageColorKey(Map<String, dynamic>? colorData, String colorName) {
      final id = colorData?['id'];
      if (id != null) return 'id:$id';
      return 'name:${colorName.toLowerCase().trim()}';
    }

    void addBardagePiece(GlassSpecification glass, double pieceLength) {
      final selectedColor = window.getBardageColorForSpec(glass);
      final selectedName = window.getBardageColorNameForSpec(glass);
      final key = bardageColorKey(selectedColor, selectedName);
      bardagePiecesByColor.putIfAbsent(key, () => <double>[]).add(pieceLength);
      bardageColorNames[key] = selectedName;
      bardageColorData[key] = selectedColor == null
          ? null
          : Map<String, dynamic>.from(selectedColor);
    }

    double totalBaguetteLength = 0.0;
    int totalRosettesCount = 0;
    Map<String, dynamic>? selectedBaguetteProduct;
    Map<String, dynamic>? selectedRosetteProduct;

    for (var zone in window.zones) {
      if (zone.content == ZoneContent.empty) continue;

      // جلب قيمة التداخل من قاعدة البيانات أو الافتراضية
      final double overlap = seriesSashOverlap;

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
        glassDeduction =
            ((window.sashOverride!['glass_deduction'] ??
                        window.sashOverride!['glassDeduction'] ??
                        0.0)
                    as num)
                .toDouble();
      } else {
        final sashSec = window.getSectionByType('sash');
        if (sashSec != null) {
          glassDeduction = sashSec.glassDeduction;
        }
      }

      // The glass starts from the exact sash-cut length. It loses the two
      // sash faces and the 10 mm safety clearance; PVC additionally loses
      // 5 mm once welded. With a 60 mm sash this is 135 mm, so a 570 mm
      // sash cut produces a 435 mm glass cut.
      final double sashGlassDeduction =
          (sw * 2.0) + videVerre + (window.isPVC ? 5.0 : 0.0);

      if (zone.content == ZoneContent.fixedGlass) {
        // الزجاج الثابت: يمتد داخل أخدود الإطار مباشرةً
        baseGw = clearW - videVerre;
        baseGh = clearH - videVerre;
      } else if (zone.content == ZoneContent.singleSash) {
        // Derive glass directly from the two sash-cut pieces.
        final double sashCutW = clearW + totalOverlap;
        final double sashCutH = clearH + totalOverlap;
        baseGw = sashCutW - sashGlassDeduction;
        baseGh = sashCutH - sashGlassDeduction;
        if (window.canUseOpeningOnlyOptions && zone.hasSashPlintheBottom) {
          double plintheW = window.plintheHeight > 0
              ? window.plintheHeight
              : 40.0;
          baseGh += sw;
          baseGh -= plintheW;
        }

        // جوانات نظام الفتح — ظلفة مفردة
        // Frappe = محيط الظلفة + محيط الإطار
        if (!window.isPVC) {
          final double sashPerimM = ((baseGw + baseGh) * 2.0) / 1000.0;
          final double framePerimM = ((clearW + clearH) * 2.0) / 1000.0;
          swingFrappeSashPerim += sashPerimM;
          swingFrappeFramePerim += framePerimM;
        }
      } else if (zone.content == ZoneContent.doubleSash) {
        // Each sash is cut first, then its glass loses the same glazing
        // deduction. This keeps glass cuts identical to the displayed sash
        // cuts: 570 - 135 = 435 and 1185 - 135 = 1050 (PVC/60 mm).
        final double totalSashCutW = clearW + totalOverlap;
        final double sashCutWLeft = totalSashCutW * zone.doubleSashRatio;
        final double sashCutWRight =
            totalSashCutW * (1.0 - zone.doubleSashRatio);
        final double sashCutH = clearH + totalOverlap;
        baseGwLeft = sashCutWLeft - sashGlassDeduction;
        baseGwRight = sashCutWRight - sashGlassDeduction;
        baseGh = sashCutH - sashGlassDeduction;
        if (window.canUseOpeningOnlyOptions && zone.hasSashPlintheBottom) {
          double plintheW = window.plintheHeight > 0
              ? window.plintheHeight
              : 40.0;
          baseGh += sw;
          baseGh -= plintheW;
        }
        sashesCount = 2;

        // جوانات نظام الفتح — ظلفة مزدوجة
        // Frappe   = محيط كل ظلفة + محيط الإطار
        // Central  = محيط الإطار فقط
        if (!window.isPVC) {
          final double ghM = baseGh / 1000.0;
          final double gwLM = baseGwLeft / 1000.0;
          final double gwRM = baseGwRight / 1000.0;
          final double framePerimM = ((clearW + clearH) * 2.0) / 1000.0;
          // ظلفة يسرى + ظلفة يمنى
          swingFrappeSashPerim += (ghM + gwLM) * 2.0;
          swingFrappeSashPerim += (ghM + gwRM) * 2.0;
          swingFrappeFramePerim += framePerimM; // محيط الإطار مرة واحدة للفتحة
          // جوان وسطي = محيط الإطار
          swingCentralFramePerim += framePerimM;
        }
      } else if (zone.content == ZoneContent.slidingSash) {
        int sashes = zone.slidingSashesCount > 0 ? zone.slidingSashesCount : 2;
        double wForCalc = clearW;
        double hForCalc = clearH;
        if (window.isSlidingZoneNestedInSingleFrame(zone)) {
          final slidingFrame = getSlidingFrameSection();
          double frameT = slidingFrame != null
              ? ((slidingFrame['visible_width'] ?? slidingFrame['thickness'])
                            as num?)
                        ?.toDouble() ??
                    45.0
              : 45.0;
          wForCalc =
              clearW -
              window.slidingRebateDeduction(zone, horizontal: true) -
              (frameT * 2.0);
          hForCalc =
              clearH -
              window.slidingRebateDeduction(zone, horizontal: false) -
              (frameT * 2.0);
        }
        wForCalc = math.max(0.0, wForCalc);
        hForCalc = math.max(0.0, hForCalc);
        final slidingSashMap =
            window.slidingSashOverride ??
            window.getSlidingSectionByType('sash_sliding')?.toMap() ??
            window.getSlidingSectionByType('sash')?.toMap();
        final configuredSlidingSashVisibleWidth =
            (slidingSashMap?['visible_width'] as num?)?.toDouble() ?? 0.0;
        final double slidingSashVisibleWidth =
            configuredSlidingSashVisibleWidth > 0
            ? configuredSlidingSashVisibleWidth
            : sw;
        final configuredSashDeduction = window.slidingSashWidthDeduction(
          sashes,
        );
        final double sashCutW = configuredSashDeduction > 0
            ? (wForCalc - configuredSashDeduction) / sashes
            : (wForCalc + ((sashes - 1) * 26.0)) / sashes;
        final configuredGlassSafety = slidingRuleNumber('glass_w_deduction');
        final glassSafety = configuredGlassSafety > 0
            ? configuredGlassSafety
            : videVerre;
        baseGw = configuredSashDeduction > 0 || window.isSlidingPVC
            ? sashCutW - slidingSashVisibleWidth - glassSafety
            : sashCutW - (sw * 2) - videVerre;
        // The height formula stays unchanged for the sliding glazing groove.
        // PVC has a series-specific sash overlap only on the sash height; it
        // must not modify this established glazing-length calculation.
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
        final bool parentUsesOpeningSashProfile =
            window.systemMode != 'sliding' &&
            (zone.content == ZoneContent.singleSash ||
                zone.content == ZoneContent.doubleSash);

        // دالة مساعدة داخلية لإنشاء عنصر الزجاج وإضافته
        void addSingleGlassPiece(
          double cellGw,
          double cellGh,
          int pieceMultiplier,
          String cellKey, {
          bool usesOpeningSashProfile = false,
        }) {
          if (cellGw <= 0 || cellGh <= 0) return;

          // استخدم مواصفات الزجاج الخاصة بالخلية إن وجدت
          final cellGlass = zone.getGlassForCell(cellKey);
          final isPanneau =
              cellGlass.structure == GlassStructure.closed ||
              zone.cellIsPanel[cellKey] == true;
          final isDecorPanneau =
              isPanneau &&
              (isDecorPanelSubtype(cellGlass.panneauSubtype) ||
                  cellGlass.finishOuter == GlassFinish.paneauSandwitchDecore);

          final isBardage =
              isPanneau &&
              (cellGlass.panneauSubtype?.toLowerCase().contains('bardage') ==
                      true ||
                  cellGlass.finishOuter == GlassFinish.bardage);

          if (isBardage &&
              window.componentOverrides.containsKey('البارداج (Bardage)')) {
            // البارداج مادة بروفيل، لكن تسعيره يكون بعدد قطع المخزون
            // الكاملة وليس بالمتر الخطي، ولا يُضاف كبانو مساحي.
            final double slatW = getBardageVisibleWidth();
            if (slatW <= 0) return;
            final bool isVertical = cellGlass.isVerticalBardage;

            final int slatsCount = isVertical
                ? (cellGw / slatW).ceil()
                : (cellGh / slatW).ceil();
            final double pieceLength = isVertical
                ? (cellGh / 1000.0)
                : (cellGw / 1000.0);

            for (int i = 0; i < slatsCount; i++) {
              for (int q = 0; q < pieceMultiplier; q++) {
                addBardagePiece(cellGlass, pieceLength);
              }
            }

            // The bardage profile's own thickness determines its parclose;
            // it must not inherit a sandwich/decor panel thickness.
            if (!(usesOpeningSashProfile && openingSashSkipsGlazingBead)) {
              final targetParclosePieces = getBardageThickness() > 10.0
                  ? parcloseDoublePieces
                  : parcloseSimplePieces;
              if (getBardageThickness() > 10.0) {
                requiredOpeningParcloseDoubleThickness = math.max(
                  requiredOpeningParcloseDoubleThickness,
                  getBardageThickness(),
                );
              }
              for (int q = 0; q < pieceMultiplier; q++) {
                targetParclosePieces.add(cellGw / 1000.0);
                targetParclosePieces.add(cellGw / 1000.0);
                targetParclosePieces.add(cellGh / 1000.0);
                targetParclosePieces.add(cellGh / 1000.0);
              }
            }
            return;
          }

          final originalName = isDecorPanneau
              ? 'البانو ديكور'
              : isPanneau
              ? 'البانو'
              : 'الزجاج';
          int totalPieces = pieceMultiplier * window.quantity;
          final panneauProduct = isPanneau
              ? window.getPanneauProductForSpec(cellGlass)
              : null;
          final outerGlassProduct = !isPanneau
              ? glassCatalogueProduct(
                  cellGlass.finishOuter,
                  cellGlass.colorOuter,
                  cellGlass.thicknessOuter ?? 4.0,
                )
              : null;
          final effectiveGlassCatalogId = catalogueId(
            panneauProduct ?? outerGlassProduct,
          );

          // 🟢 تحديد نوع الباكيت المطلوب بناءً على سمك الزجاج الفعلي لهذه الخلية
          final double cellThick = window
              .glassPackThicknessIncludingVitrageJoint(cellGlass);
          final bool needsDoubleParclose =
              cellGlass.structure == GlassStructure.double;
          final bool isSlidingSystem =
              window.systemMode == 'sliding' ||
              window.systemMode == 'coulissant' ||
              window.systemMode == 'منزلق' ||
              zone.content == ZoneContent.slidingSash;
          final bool isPvcSlidingSystem =
              isSlidingSystem && window.isSlidingPVC;
          final String slidingSeriesLabel =
              '${window.activeSlidingSeries?.name ?? ''} '
                      '${window.activeSlidingSeries?.type ?? ''} '
                      '${window.activeSeries?.name ?? ''} '
                      '${window.activeSeries?.type ?? ''} '
                      '${window.system?.name ?? ''}'
                  .toLowerCase();
          final slidingFamily = window.slidingSeriesFamily(
            series: window.activeSlidingSeries ?? window.activeSeries,
          );
          final bool isTprLikeSlidingSystem =
              isSlidingSystem &&
              !isPvcSlidingSystem &&
              (slidingSeriesLabel.contains('tpr') ||
                  slidingSeriesLabel.contains('atpr') ||
                  slidingSeriesLabel.contains('tpi') ||
                  slidingFamily != null);
          final AluminumSeries? reducerSeries =
              window.activeSlidingSeries ?? window.activeSeries;
          final bool reducerConfigured = window.seriesUsesReducer(
            reducerSeries,
          );
          final bool reducerConfigExists = window.seriesHasConfiguredRoles(
            reducerSeries,
          );
          final bool reducerAllowed =
              reducerConfigured ||
              (!reducerConfigExists && isSlidingSystem && !isPvcSlidingSystem);

          void addReducteurPieces(int multiplier) {
            hasSimpleGlassReducerPieces = true;
            for (int q = 0; q < multiplier; q++) {
              reducteurPieces.add(cellGw / 1000.0);
              reducteurPieces.add(cellGw / 1000.0);
              reducteurPieces.add(cellGh / 1000.0);
              reducteurPieces.add(cellGh / 1000.0);
            }
          }

          void addSlidingVitrageJoint() {
            final double perimeter = (cellGw * 2 + cellGh * 2) / 1000.0;
            final double sides = cellGlass.jointTwoSides ? 2.0 : 1.0;
            final double qty = perimeter * sides * totalPieces;
            const jointName = 'جوان الزجاج (Joint Vitrage)';
            slidingGlassJoints[jointName] =
                (slidingGlassJoints[jointName] ?? 0.0) + qty;
          }

          if (isSlidingSystem) {
            if (isPvcSlidingSystem) {
              // PVC sliding systems always retain glass with a parclose.
              // A reducteur is an aluminium-only profile and must never be
              // injected into their bill of materials.
              final targetParclosePieces = needsDoubleParclose
                  ? slidingParcloseDoublePieces
                  : slidingParcloseSimplePieces;
              if (needsDoubleParclose) {
                requiredSlidingParcloseDoubleThickness = math.max(
                  requiredSlidingParcloseDoubleThickness,
                  cellThick,
                );
              }
              for (int q = 0; q < pieceMultiplier; q++) {
                targetParclosePieces.add(cellGw / 1000.0);
                targetParclosePieces.add(cellGw / 1000.0);
                targetParclosePieces.add(cellGh / 1000.0);
                targetParclosePieces.add(cellGh / 1000.0);
              }
            }
            if (isTprLikeSlidingSystem &&
                !isPanneau &&
                cellGlass.structure != GlassStructure.closed) {
              // TPR parclose is cut in the catalogue's order: two pieces are
              // the inner sash length, while the other two are the inner sash
              // width minus 2 x 20 mm parclose overlap.
              final targetParclosePieces = needsDoubleParclose
                  ? slidingParcloseDoublePieces
                  : slidingParcloseSimplePieces;
              if (needsDoubleParclose) {
                requiredSlidingParcloseDoubleThickness = math.max(
                  requiredSlidingParcloseDoubleThickness,
                  cellThick,
                );
              }
              final double tprWidth = math.max(0.0, cellGw - 40.0);
              for (int q = 0; q < pieceMultiplier; q++) {
                targetParclosePieces.add(cellGh / 1000.0);
                targetParclosePieces.add(cellGh / 1000.0);
                targetParclosePieces.add(tprWidth / 1000.0);
                targetParclosePieces.add(tprWidth / 1000.0);
              }
              if (reducerAllowed &&
                  cellGlass.structure == GlassStructure.simple) {
                addReducteurPieces(pieceMultiplier);
              }
              addSlidingVitrageJoint();
            } else if (!isPvcSlidingSystem &&
                !isPanneau &&
                cellGlass.structure != GlassStructure.closed) {
              final double reducteurThick =
                  (reducerAllowed &&
                      cellGlass.structure == GlassStructure.simple)
                  ? 15.0
                  : 0.0;
              if (reducteurThick > 0) {
                addReducteurPieces(pieceMultiplier);
              }
              double maxGlass = 24.0;
              final sashMap =
                  window.slidingSashOverride ??
                  window.getSlidingSectionByType('sash_sliding')?.toMap() ??
                  window.getSlidingSectionByType('sash')?.toMap();
              if (sashMap != null) {
                final double mG =
                    (sashMap['max_glass_thickness'] as num?)?.toDouble() ?? 0.0;
                if (mG > 0) maxGlass = mG;
              }
              // 🟢 الفراغ الصافي للزجاج: إذا استعملنا reducteur يصبح مجرى الزجاج 15 مم
              final double pocketWidth = (reducteurThick > 0)
                  ? 15.0
                  : (maxGlass - reducteurThick);
              double remaining = pocketWidth - cellThick;
              if (remaining <= 0) {
                remaining =
                    2.0; // fallback to ensure glass gasket is calculated
              }
              if (remaining > 0) addSlidingVitrageJoint();
            }
          } else {
            if (!isPanneau && cellGlass.structure != GlassStructure.closed) {
              final double perimeter = (cellGw * 2 + cellGh * 2) / 1000.0;
              final double mult = cellGlass.jointTwoSides ? 2.0 : 1.0;
              final double gasketQty = perimeter * mult * totalPieces;
              String gName = 'جوان البوراج (Joint Bourrage)';
              slidingGlassJoints[gName] =
                  (slidingGlassJoints[gName] ?? 0.0) + gasketQty;
            }
            if (usesOpeningSashProfile && openingSashSkipsGlazingBead) {
              // This sash profile is explicitly configured without parclose.
            } else if (needsDoubleParclose) {
              maxOpeningDoubleGlassPackThickness = math.max(
                maxOpeningDoubleGlassPackThickness,
                cellThick,
              );
              requiredOpeningParcloseDoubleThickness = math.max(
                requiredOpeningParcloseDoubleThickness,
                cellThick,
              );
              for (int q = 0; q < pieceMultiplier; q++) {
                parcloseDoublePieces.add(cellGw / 1000.0);
                parcloseDoublePieces.add(cellGw / 1000.0);
                parcloseDoublePieces.add(cellGh / 1000.0);
                parcloseDoublePieces.add(cellGh / 1000.0);
              }
            } else {
              maxOpeningSimpleGlassPackThickness = math.max(
                maxOpeningSimpleGlassPackThickness,
                cellThick,
              );
              for (int q = 0; q < pieceMultiplier; q++) {
                parcloseSimplePieces.add(cellGw / 1000.0);
                parcloseSimplePieces.add(cellGw / 1000.0);
                parcloseSimplePieces.add(cellGh / 1000.0);
                parcloseSimplePieces.add(cellGh / 1000.0);
              }
            }
          }

          // The drawing renders baguettes and rosettes for double glazing
          // only. Keep the quantity table on exactly the same rule so stale
          // decoration settings from a former double pane are never priced
          // after the user removes them or changes the pane type.
          final hasVisibleDoubleGlassDecor =
              cellGlass.structure == GlassStructure.double &&
              (cellGlass.decorH > 0 || cellGlass.decorV > 0);

          // 🟢 حساب الديكور باجيت والورود لهذه القطعة الفردية
          if (hasVisibleDoubleGlassDecor) {
            double cellBaguette =
                (cellGlass.decorH * cellGw + cellGlass.decorV * cellGh) /
                1000.0;
            totalBaguetteLength += cellBaguette * totalPieces;

            if (cellGlass.hasRosettes) {
              totalRosettesCount +=
                  (cellGlass.decorH * cellGlass.decorV) * totalPieces;
            }

            if (selectedBaguetteProduct == null &&
                cellGlass.decorBaguetteId != null) {
              selectedBaguetteProduct = window.allGlassCache.firstWhere(
                (g) =>
                    g['id'] == cellGlass.decorBaguetteId &&
                    g['color']?.toString().toLowerCase().trim() ==
                        cellGlass.decorColor.toLowerCase().trim(),
                orElse: () => window.allGlassCache.firstWhere(
                  (g) => g['id'] == cellGlass.decorBaguetteId,
                  orElse: () => <String, dynamic>{},
                ),
              );
            }
            if (selectedRosetteProduct == null &&
                cellGlass.decorRosetteId != null) {
              selectedRosetteProduct = window.allGlassCache.firstWhere(
                (g) =>
                    g['id'] == cellGlass.decorRosetteId &&
                    g['color']?.toString().toLowerCase().trim() ==
                        cellGlass.decorColor.toLowerCase().trim(),
                orElse: () => window.allGlassCache.firstWhere(
                  (g) => g['id'] == cellGlass.decorRosetteId,
                  orElse: () => <String, dynamic>{},
                ),
              );
            }
          }

          // الزجاج المزدوج يتكون من زجاج خارجي وزجاج داخلي مستقلين. لكل
          // طبقة سعرها ومساحتها الصحيحة، ويضاف الغاز كسطر مستقل عند اختياره.
          // لا نضع سعر الفاصل بين الطبقتين ضمن أحد الزجاجين.
          final double totalAreaSqm =
              (cellGw * cellGh / 1000000.0) * totalPieces;

          double layerThickness({required bool isOuter}) {
            final selectedThickness = isOuter
                ? cellGlass.thicknessOuter
                : cellGlass.thicknessInner;
            if (selectedThickness != null && selectedThickness > 0) {
              return selectedThickness;
            }
            return window.getThicknessForFinish(
              isOuter ? cellGlass.finishOuter : cellGlass.finishInner,
              isOuter ? cellGlass.colorOuter : cellGlass.colorInner,
            );
          }

          bool layerIsTempered({required bool isOuter}) {
            final processing = isOuter
                ? cellGlass.processingOuter
                : cellGlass.processingInner;
            final isTempered = isOuter
                ? cellGlass.temperedOuter
                : cellGlass.temperedInner;
            return processing == GlassProcessing.tempered || isTempered;
          }

          double layerMaterialPrice({required bool isOuter}) {
            final thickness = layerThickness(isOuter: isOuter);
            final processing = isOuter
                ? cellGlass.processingOuter
                : cellGlass.processingInner;
            final finish = isOuter
                ? cellGlass.finishOuter
                : cellGlass.finishInner;
            final glassColor = isOuter
                ? cellGlass.colorOuter
                : cellGlass.colorInner;
            final laminatedColor = isOuter
                ? cellGlass.laminatedColorOuter
                : cellGlass.laminatedColorInner;
            return processing == GlassProcessing.laminated
                ? window.getLaminatedPrice(thickness, laminatedColor)
                : window.getPriceForFinish(
                    finish,
                    glassColor,
                    chosenThickness: thickness,
                  );
          }

          double layerTemperingPrice({required bool isOuter}) {
            if (!layerIsTempered(isOuter: isOuter)) return 0.0;
            return window.getTemperingPricePerSqm(
              layerThickness(isOuter: isOuter),
            );
          }

          double layerPrice({required bool isOuter}) {
            return layerMaterialPrice(isOuter: isOuter) +
                layerTemperingPrice(isOuter: isOuter);
          }

          String layerDescription({required bool isOuter}) {
            final processing = isOuter
                ? cellGlass.processingOuter
                : cellGlass.processingInner;
            final finish = isOuter
                ? cellGlass.finishOuter
                : cellGlass.finishInner;
            final glassColor = isOuter
                ? cellGlass.colorOuter
                : cellGlass.colorInner;
            final laminatedColor = isOuter
                ? cellGlass.laminatedColorOuter
                : cellGlass.laminatedColorInner;
            String material = processing == GlassProcessing.laminated
                ? 'مورق ($laminatedColor)'
                : '${window.getFinishName(finish)} ${window.getArabicColorName(glassColor)}'
                      .trim();
            return material;
          }

          if (!isPanneau &&
              (cellGlass.structure == GlassStructure.double ||
                  cellGlass.structure == GlassStructure.simple)) {
            final prefix = labelSuffix.isEmpty ? '' : '$labelSuffix\n';
            final outerPrice = layerPrice(isOuter: true);
            final outerMaterialPrice = layerMaterialPrice(isOuter: true);
            final outerTemperingPrice = layerTemperingPrice(isOuter: true);
            final outerIsTempered = layerIsTempered(isOuter: true);
            final innerPrice = cellGlass.structure == GlassStructure.double
                ? layerPrice(isOuter: false)
                : 0.0;
            final innerMaterialPrice =
                cellGlass.structure == GlassStructure.double
                ? layerMaterialPrice(isOuter: false)
                : 0.0;
            final innerTemperingPrice =
                cellGlass.structure == GlassStructure.double
                ? layerTemperingPrice(isOuter: false)
                : 0.0;
            final innerIsTempered =
                cellGlass.structure == GlassStructure.double &&
                layerIsTempered(isOuter: false);
            final intercallPrice = cellGlass.structure == GlassStructure.double
                ? window.getPriceForIntercall(cellGlass.intercallThickness)
                : 0.0;
            final gasPrice =
                cellGlass.structure == GlassStructure.double && cellGlass.hasGas
                ? window.getPriceForGas(cellGlass.intercallThickness)
                : 0.0;
            final totalGlassPrice =
                outerPrice + innerPrice + intercallPrice + gasPrice;
            final dimensions =
                '${cellGw.toStringAsFixed(0)} × ${cellGh.toStringAsFixed(0)} مم';

            String glassName;
            if (cellGlass.structure == GlassStructure.double) {
              glassName =
                  '${prefix}- Face extérieure / الوجه الخارجي: ${layerDescription(isOuter: true)} '
                  '(${outerMaterialPrice.toStringAsFixed(2)} دج/م²)'
                  '${outerIsTempered ? '\n- Trempé / التقسية (${outerTemperingPrice.toStringAsFixed(2)} دج/م²)' : ''}\n'
                  '- Face intérieure / الوجه الداخلي: ${layerDescription(isOuter: false)} '
                  '(${innerMaterialPrice.toStringAsFixed(2)} دج/م²)'
                  '${innerIsTempered ? '\n- Trempé / التقسية (${innerTemperingPrice.toStringAsFixed(2)} دج/م²)' : ''}\n'
                  '- Intercalaire / الفاصل: ${cellGlass.intercallThickness} مم '
                  '(${intercallPrice.toStringAsFixed(2)} دج/م²)'
                  '${cellGlass.hasGas ? '\n- Gaz / الغاز (${gasPrice.toStringAsFixed(2)} دج/م²)' : ''}'
                  '\n- Dimensions / القياس: $dimensions';
            } else {
              glassName =
                  '${prefix}- Face extérieure / الوجه الخارجي: ${layerDescription(isOuter: true)} '
                  '(${outerMaterialPrice.toStringAsFixed(2)} دج/م²)'
                  '${outerIsTempered ? '\n- Trempé / التقسية (${outerTemperingPrice.toStringAsFixed(2)} دج/م²)' : ''}\n'
                  '- Dimensions / القياس: $dimensions';
            }

            glassItems.add(
              BomItem(
                category: 'glass',
                originalName: 'الزجاج',
                name: glassName,
                imagePath: window.componentOverrides['الزجاج']?['image_path']
                    ?.toString(),
                colorName: cellGh.toStringAsFixed(1),
                length: cellGw,
                glassHeight: cellGh,
                quantity: totalAreaSqm,
                unit: 'م²',
                unitPrice: totalGlassPrice,
                isMissing: false,
                catalogItemId: effectiveGlassCatalogId,
                inventoryItemType: 'Glass',
              ),
            );
          } else {
            String glassName = _buildGlassDescription(
              cellGlass,
              window,
              cellGw,
              cellGh,
              seriesOverride: isSlidingSystem
                  ? window.activeSlidingSeries
                  : window.activeSeries,
            );
            if (labelSuffix.isNotEmpty) glassName = "$labelSuffix\n$glassName";
            glassItems.add(
              BomItem(
                category: 'panneau',
                originalName: originalName,
                name: glassName,
                imagePath: panneauProduct?['image_path']?.toString(),
                colorName: cellGh.toStringAsFixed(1),
                length: cellGw,
                glassHeight: cellGh,
                quantity: isDecorPanneau
                    ? totalPieces.toDouble()
                    : totalAreaSqm,
                unit: isDecorPanneau ? 'قطعة' : 'م²',
                unitPrice: window.calculateTotalGlassPricePerSqmForZoneGlass(
                  cellGlass,
                ),
                isMissing: false,
                catalogItemId: effectiveGlassCatalogId,
                inventoryItemType: 'Glass',
              ),
            );
          }
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
                cellGd =
                    ((zone.cellSashOverrides[cellKey]!['glass_deduction'] ??
                                zone.cellSashOverrides[cellKey]!['glassDeduction'] ??
                                0.0)
                            as num)
                        .toDouble();
              }
              double cellDeductionW = -videVerre;
              double cellDeductionH = -videVerre;
              if (cellGd != 0.0) {
                cellDeductionW = (cellGd * 2.0) - videVerre;
                cellDeductionH = (cellGd * 2.0) - videVerre;
              }
              // خصم عرض مقطع الظلفة الداخلية والتخليص (videVerre أو rebate)
              double glassW = cellW - (cellSw * 2.0) + cellDeductionW;
              double glassH = cellH - (cellSw * 2.0) + cellDeductionH;
              addSingleGlassPiece(
                glassW,
                glassH,
                multiplier,
                cellKey,
                usesOpeningSashProfile: true,
              );
            } else if (hasNestedDoubleSash) {
              double cellSw = sw;
              double cellGd = glassDeduction;
              if (zone.cellSashOverrides[cellKey] != null) {
                cellSw =
                    (zone.cellSashOverrides[cellKey]!['visible_width'] as num?)
                        ?.toDouble() ??
                    sw;
                cellGd =
                    ((zone.cellSashOverrides[cellKey]!['glass_deduction'] ??
                                zone.cellSashOverrides[cellKey]!['glassDeduction'] ??
                                0.0)
                            as num)
                        .toDouble();
              }
              double cellDeductionW = -videVerre;
              double cellDeductionH = -videVerre;
              if (cellGd != 0.0) {
                cellDeductionW = (cellGd * 2.0) - videVerre;
                cellDeductionH = (cellGd * 2.0) - videVerre;
              }
              double sep = 4.0;
              // خصم عرض مقطع الظلفة وتخليص الفاصل المزدوج
              double glassW =
                  ((cellW - sep) / 2.0) - (cellSw * 2.0) + cellDeductionW;
              double glassH = cellH - (cellSw * 2.0) + cellDeductionH;
              addSingleGlassPiece(
                glassW,
                glassH,
                multiplier * 2,
                cellKey,
                usesOpeningSashProfile: true,
              );
            } else {
              // زجاج ثابت أو لوح بدون ظلفة داخلية
              double glassW = cellW;
              double glassH = cellH;
              addSingleGlassPiece(
                glassW,
                glassH,
                multiplier,
                cellKey,
                usesOpeningSashProfile: parentUsesOpeningSashProfile,
              );
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
          '${g.category == 'panneau' ? g.name : ''}_'
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
          imagePath: existing.imagePath,
          colorName: existing.colorName,
          length: existing.length,
          glassHeight: existing.glassHeight,
          quantity: existing.quantity + g.quantity,
          unit: existing.unit,
          unitPrice: existing.unitPrice,
          isMissing: existing.isMissing,
          catalogItemId: existing.catalogItemId,
          inventoryItemType: existing.inventoryItemType,
          colorId: existing.colorId,
        );
      } else {
        mergedGlass[key] = g;
      }
    }

    // ✅ إضافة قطع الزجاج والبانو المدمجة إلى كشف المواد الإجمالي ليظهر في الجدول
    items.addAll(mergedGlass.values);

    // Sliding glass gaskets are discovered while glass cells are calculated,
    // so they must be appended after the glass loop.  The earlier accessory
    // section runs before this data exists.
    final pendingSlidingVitrageJoints = slidingGlassJoints.entries
        .where(
          (entry) => _selectorTypeForJoint(entry.key) == 'joint de vitrage',
        )
        .toList();
    final modelQuantity = window.quantity <= 0 ? 1 : window.quantity;
    for (final entry in pendingSlidingVitrageJoints) {
      if (entry.value > 0) {
        items.add(
          createJoint(entry.key, qty: entry.value / modelQuantity, unit: 'متر'),
        );
      }
      slidingGlassJoints.remove(entry.key);
    }

    // --- 5. الباكيت (Parclose) ---
    final chosenParclose = window.componentOverrides['باكيت الزجاج (Parclose)'];

    Map<String, dynamic>? resolveParcloseForSeries(
      AluminumSeries? series, {
      required double requiredDoubleThickness,
    }) {
      if (series == null) return null;
      bool isParcloseSection(AluminumSection section) {
        final type = section.type.toLowerCase();
        final name = section.name.toLowerCase();
        return section.code.trim() == '514' ||
            type.contains('parclose') ||
            name.contains('parclose') ||
            type.contains('باكيت') ||
            name.contains('باكيت');
      }

      AluminumSection? findSimpleParclose() {
        final candidates = series.sections.where(isParcloseSection).toList();
        for (final section in candidates) {
          if (section.code.trim() == '514') return section;
        }
        for (final section in candidates) {
          if (section.maxGlassThickness > 0 &&
              section.maxGlassThickness <= 14) {
            return section;
          }
        }
        return null;
      }

      AluminumSection? findDoubleParclose() {
        final minimumCapacity = math.max(10.0, requiredDoubleThickness);
        final candidates =
            series.sections
                .where(
                  (section) =>
                      isParcloseSection(section) &&
                      section.maxGlassThickness >= minimumCapacity,
                )
                .toList()
              ..sort(
                (a, b) => a.maxGlassThickness.compareTo(b.maxGlassThickness),
              );
        if (candidates.isNotEmpty) return candidates.first;

        final fallback =
            series.sections
                .where(
                  (section) =>
                      isParcloseSection(section) &&
                      section.maxGlassThickness > 10,
                )
                .toList()
              ..sort(
                (a, b) => a.maxGlassThickness.compareTo(b.maxGlassThickness),
              );
        return fallback.isEmpty ? null : fallback.last;
      }

      Map<String, dynamic> pricedMap(AluminumSection section) =>
          window.sectionMapWithSelectedColorPrice(section);
      Map<String, dynamic> pricedOverride(Map<String, dynamic> source) {
        final result = Map<String, dynamic>.from(source);
        final rawId = result['id'];
        final id = rawId is num
            ? rawId.toInt()
            : int.tryParse(rawId?.toString() ?? '');
        final price = id == null
            ? null
            : window.sectionPricesForSelectedColor[id];
        if (price != null) result['calculated_price'] = price;
        return result;
      }

      final chosenId = chosenParclose?['id'];
      final chosenSeriesId = chosenParclose?['series_id'];
      final chosenBelongsToSeries =
          chosenParclose == null ||
          (chosenSeriesId != null &&
              chosenSeriesId.toString() == series.id.toString()) ||
          (chosenId != null &&
              series.sections.any(
                (s) => s.id.toString() == chosenId.toString(),
              ));

      Map<String, dynamic>? simple;
      Map<String, dynamic>? doubled;
      if (chosenParclose != null && chosenBelongsToSeries) {
        final double maxG =
            (chosenParclose['max_glass_thickness'] as num?)?.toDouble() ?? 0.0;
        if (maxG > 10.0 && maxG >= requiredDoubleThickness) {
          doubled = pricedOverride(chosenParclose);
          final simpleSection = findSimpleParclose();
          simple = simpleSection == null
              ? pricedOverride(chosenParclose)
              : pricedMap(simpleSection);
        } else {
          final simpleSection = findSimpleParclose();
          simple =
              chosenParclose['code']?.toString().trim() == '514' ||
                  simpleSection == null
              ? pricedOverride(chosenParclose)
              : pricedMap(simpleSection);
          final int? linkedId =
              chosenParclose['linked_parclose_double_id'] as int?;
          if (linkedId != null && linkedId > 0) {
            try {
              final linkedSec = series.sections.firstWhere(
                (s) => s.id == linkedId,
              );
              if (linkedSec.maxGlassThickness >= requiredDoubleThickness) {
                doubled = pricedMap(linkedSec);
              }
            } catch (_) {}
          }
          if (doubled == null) {
            final doubleSection = findDoubleParclose();
            doubled = doubleSection == null
                ? pricedOverride(chosenParclose)
                : pricedMap(doubleSection);
          }
        }
      } else {
        final simpleSection = findSimpleParclose();
        final doubleSection = findDoubleParclose();
        if (simpleSection != null) simple = pricedMap(simpleSection);
        if (doubleSection != null) doubled = pricedMap(doubleSection);
      }

      return {'simple': simple, 'double': doubled};
    }

    final openingParclose = resolveParcloseForSeries(
      window.activeSeries,
      requiredDoubleThickness: requiredOpeningParcloseDoubleThickness,
    );
    final slidingParclose = resolveParcloseForSeries(
      window.activeSlidingSeries,
      requiredDoubleThickness: requiredSlidingParcloseDoubleThickness,
    );
    final parcloseSimple = openingParclose?['simple'] as Map<String, dynamic>?;
    final parcloseDouble = openingParclose?['double'] as Map<String, dynamic>?;
    final slidingParcloseSimple =
        slidingParclose?['simple'] as Map<String, dynamic>?;
    final slidingParcloseDouble =
        slidingParclose?['double'] as Map<String, dynamic>?;
    Map<String, dynamic>? overrideMap(String key) {
      final value = window.componentOverrides[key];
      if (value is Map<String, dynamic>) return value;
      if (value is Map) return Map<String, dynamic>.from(value);
      return null;
    }

    final selectedParcloseSimple = overrideMap(
      'باكيت زجاج مفرد (Parclose Simple)',
    );
    final selectedParcloseDouble = overrideMap(
      'باكيت زجاج مزدوج (Parclose Double)',
    );
    final selectedSlidingParcloseSimple = overrideMap(
      'باكيت زجاج منزلق مفرد (Parclose Simple Coulissant)',
    );
    final selectedSlidingParcloseDouble = overrideMap(
      'باكيت زجاج منزلق مزدوج (Parclose Double Coulissant)',
    );

    bool genericParcloseMatches({required bool doubleGlass}) {
      final maxGlass =
          (chosenParclose?['max_glass_thickness'] as num?)?.toDouble() ?? 0.0;
      return chosenParclose != null &&
          (doubleGlass ? maxGlass > 10.0 : maxGlass <= 10.0);
    }

    if (parcloseSimplePieces.isNotEmpty) {
      final targetOverride =
          selectedParcloseSimple ??
          parcloseSimple ??
          (genericParcloseMatches(doubleGlass: false)
              ? chosenParclose
              : null) ??
          (parcloseDouble != null ? parcloseDouble : chosenParclose);
      if (targetOverride != null) {
        items.add(
          createProfile(
            'باكيت زجاج مفرد (Parclose Simple)',
            colorName,
            pieces: parcloseSimplePieces,
            unit: 'قطاع',
            overrideMap: targetOverride,
            selectorType: 'parclose_simple',
          ),
        );
      }
    }

    if (parcloseDoublePieces.isNotEmpty) {
      final targetOverride =
          selectedParcloseDouble ??
          parcloseDouble ??
          (genericParcloseMatches(doubleGlass: true) ? chosenParclose : null) ??
          (parcloseSimple != null ? parcloseSimple : chosenParclose);
      if (targetOverride != null) {
        items.add(
          createProfile(
            'باكيت زجاج مزدوج (Parclose Double)',
            colorName,
            pieces: parcloseDoublePieces,
            unit: 'قطاع',
            overrideMap: targetOverride,
            selectorType: 'parclose_double',
          ),
        );
      }
    }

    if (slidingParcloseSimplePieces.isNotEmpty) {
      final targetOverride =
          selectedSlidingParcloseSimple ??
          slidingParcloseSimple ??
          (genericParcloseMatches(doubleGlass: false)
              ? chosenParclose
              : null) ??
          selectedParcloseSimple ??
          parcloseSimple ??
          chosenParclose;
      if (targetOverride != null) {
        items.add(
          createProfile(
            'باكيت زجاج منزلق مفرد (Parclose Simple Coulissant)',
            colorName,
            pieces: slidingParcloseSimplePieces,
            unit: 'قطاع',
            overrideMap: targetOverride,
            selectorType: 'sliding_parclose_simple',
          ),
        );
      }
    }

    if (slidingParcloseDoublePieces.isNotEmpty) {
      final targetOverride =
          selectedSlidingParcloseDouble ??
          slidingParcloseDouble ??
          (genericParcloseMatches(doubleGlass: true) ? chosenParclose : null) ??
          selectedParcloseDouble ??
          parcloseDouble ??
          chosenParclose;
      if (targetOverride != null) {
        items.add(
          createProfile(
            'باكيت زجاج منزلق مزدوج (Parclose Double Coulissant)',
            colorName,
            pieces: slidingParcloseDoublePieces,
            unit: 'قطاع',
            overrideMap: targetOverride,
            selectorType: 'sliding_parclose_double',
          ),
        );
      }
    }

    double maxGlassCapacity(Map<String, dynamic>? profile) {
      return (profile?['max_glass_thickness'] as num?)?.toDouble() ?? 0.0;
    }

    final double vitrageJointThick = window.isPVC
        ? 0.0
        : window.selectedVitrageJointThickness(fallback: 3.0);

    double bourrageThicknessNeed({
      required Map<String, dynamic>? parclose,
      required double glassPackThickness,
    }) {
      final capacity = maxGlassCapacity(parclose);
      if (capacity <= 0 || glassPackThickness <= 0) return 0.0;
      final totalPack = glassPackThickness + vitrageJointThick;
      return math.max(0.0, capacity - totalPack);
    }

    final double simpleBourrageTargetThickness = bourrageThicknessNeed(
      parclose: selectedParcloseSimple ?? parcloseSimple ?? chosenParclose,
      glassPackThickness: maxOpeningSimpleGlassPackThickness,
    );

    final double doubleBourrageTargetThickness = bourrageThicknessNeed(
      parclose: selectedParcloseDouble ?? parcloseDouble ?? chosenParclose,
      glassPackThickness: maxOpeningDoubleGlassPackThickness,
    );

    // ===== جوانات نظام الفتح (ألمنيوم فقط) =====
    if (!window.isPVC) {
      // حساب الكميات المشتركة بين Vitrage و Bourrage
      final double simplePerim = parcloseSimplePieces.fold(
        0.0,
        (s, p) => s + p,
      ); // محيط زجاج مفرد (×1)
      final double doublePerim = parcloseDoublePieces.fold(
        0.0,
        (s, p) => s + p,
      ); // طول باكلوز الزجاج المزدوج
      final double vitrageQty = simplePerim + doublePerim;

      if (vitrageQty > 0) {
        items.add(
          createJoint(
            'جوان الزجاج (Joint Vitrage)',
            qty: vitrageQty,
            unit: 'متر',
          ),
        );

        // إذا كان في النافذة زجاج مفرد وزجاج مزدوج معاً، يُفصل كل نوع في بند مستقل:
        final bool haveBothDistinct = simplePerim > 0 && doublePerim > 0;

        if (haveBothDistinct) {
          items.add(
            createJoint(
              'جوان البوراج للزجاج المفرد (Joint Bourrage Simple)',
              qty: simplePerim,
              unit: 'متر',
              targetThicknessMm: simpleBourrageTargetThickness > 0
                  ? simpleBourrageTargetThickness
                  : 4.0,
              overrideKey: 'جوان البوراج للزجاج المفرد (Joint Bourrage Simple)',
            ),
          );
          items.add(
            createJoint(
              'جوان البوراج للزجاج المزدوج (Joint Bourrage Double)',
              qty: doublePerim,
              unit: 'متر',
              targetThicknessMm: doubleBourrageTargetThickness > 0
                  ? doubleBourrageTargetThickness
                  : 2.0,
              overrideKey:
                  'جوان البوراج للزجاج المزدوج (Joint Bourrage Double)',
            ),
          );
        } else {
          final double targetThick = simplePerim > 0 && doublePerim <= 0
              ? (simpleBourrageTargetThickness > 0
                    ? simpleBourrageTargetThickness
                    : 4.0)
              : (doublePerim > 0 && simplePerim <= 0
                    ? (doubleBourrageTargetThickness > 0
                          ? doubleBourrageTargetThickness
                          : 2.0)
                    : math.max(
                        simpleBourrageTargetThickness,
                        doubleBourrageTargetThickness,
                      ));

          final String originalName = targetThick <= 2.5
              ? 'جوان البوراج للزجاج المزدوج (Joint Bourrage Double)'
              : (targetThick <= 4.5
                    ? 'جوان البوراج للزجاج المفرد (Joint Bourrage Simple)'
                    : 'جوان البوراج (Joint Bourrage)');

          items.add(
            createJoint(
              originalName,
              qty: vitrageQty,
              unit: 'متر',
              targetThicknessMm: targetThick,
              overrideKey: originalName,
            ),
          );
        }
      }

      // Joint Frappe = محيط الظلفة + محيط الإطار
      final double frappeQty = swingFrappeSashPerim + swingFrappeFramePerim;
      if (frappeQty > 0) {
        items.add(
          createJoint('جوان الضرب (Joint Frappe)', qty: frappeQty, unit: 'متر'),
        );
      }

      // Joint Central = محيط الإطار (فتحات مزدوجة فقط)
      if (swingCentralFramePerim > 0) {
        items.add(
          createJoint(
            'جوان الوسط (Joint Central)',
            qty: swingCentralFramePerim,
            unit: 'متر',
          ),
        );
      }
    }

    final bool reducerGlassIsStrictlySimple =
        hasSimpleGlassReducerPieces &&
        window.hasSimpleGlassForReducer &&
        !window.hasDoubleGlassForRules;

    if (reducteurPieces.isNotEmpty && reducerGlassIsStrictlySimple) {
      Map<String, dynamic>? reducteurOverride =
          window.componentOverrides['ريديكتور (Réducteur)'] ??
          window.componentOverrides['مخفض الزجاج (Réducteur)'];

      final reductionSeries = window.activeSlidingSeries ?? window.activeSeries;
      final bool reducerAllowedForSeries =
          window.seriesUsesReducer(reductionSeries) ||
          !window.seriesHasConfiguredRoles(reductionSeries);
      if (reducerAllowedForSeries &&
          reducteurOverride == null &&
          reductionSeries != null) {
        bool isReducteurSection(dynamic s) {
          final n = s.name.toLowerCase();
          final t = s.type.toLowerCase();
          final c = s.code.toLowerCase();
          return (c.contains('67114') ||
                  n.contains('reduct') ||
                  n.contains('مخفض') ||
                  n.contains('ريديكتور') ||
                  t.contains('reduct')) &&
              !t.contains('rail') &&
              !t.contains('cadre') &&
              !t.contains('frame') &&
              !n.contains('rail') &&
              !n.contains('سكة') &&
              !n.contains('cadre') &&
              !n.contains('إطار');
        }

        // البحث عن قطاع reducteur صريح (كود 67114 أو reducteur) واستبعاد الباركلوز والسكة
        try {
          final redSec = reductionSeries.sections.firstWhere(
            isReducteurSection,
          );
          reducteurOverride = redSec.toMap();
        } catch (_) {}
      }

      if (reducerAllowedForSeries) {
        items.add(
          createProfile(
            'ريديكتور (Réducteur)',
            colorName,
            pieces: reducteurPieces,
            unit: 'قطاع',
            overrideMap: reducteurOverride,
          ),
        );
      }
    }

    // =========================================================================
    // --- 4.6 البارداج كبروفيل (Bardage Profile) ---
    // =========================================================================
    if (bardagePiecesByColor.isNotEmpty &&
        window.componentOverrides.containsKey('البارداج (Bardage)')) {
      final rawBardageOverride =
          window.componentOverrides['البارداج (Bardage)'];
      for (final entry in bardagePiecesByColor.entries) {
        final selectedName = bardageColorNames[entry.key] ?? colorName;
        final selectedColor = bardageColorData[entry.key];
        final pricedOverride = rawBardageOverride is Map
            ? Map<String, dynamic>.from(rawBardageOverride)
            : <String, dynamic>{};
        pricedOverride['calculated_price'] = window.getBardagePriceForColor(
          selectedColor,
          selectedName,
        );
        items.add(
          createProfile(
            'البارداج (Bardage)',
            selectedName,
            pieces: entry.value,
            unit: 'قطعة',
            overrideMap: pricedOverride,
            preferOverrideMap: true,
            priceByWholeBar: true,
          ),
        );
      }
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

    if (totalBaguetteLength > 0 &&
        selectedBaguetteProduct != null &&
        selectedBaguetteProduct!.isNotEmpty) {
      double baguettePrice =
          (selectedBaguetteProduct!['price_per_sqm'] as num?)?.toDouble() ??
          0.0;
      String bName = selectedBaguetteProduct!['name'].toString();
      String thickness =
          selectedBaguetteProduct!['thickness']?.toString() ?? '';
      String thicknessText = thickness.isNotEmpty
          ? 'حجم: $thickness مم - '
          : '';
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

    if (totalRosettesCount > 0 &&
        selectedRosetteProduct != null &&
        selectedRosetteProduct!.isNotEmpty) {
      double rosettePrice =
          (selectedRosetteProduct!['price_per_sqm'] as num?)?.toDouble() ?? 0.0;
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
          if (orig.contains('إطار') ||
              orig.contains('frame') ||
              orig.contains('cadre')) {
            type = 'frame';
          } else if (orig.contains('ظلفة') ||
              orig.contains('sash') ||
              orig.contains('ouvrant')) {
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

        if ((code != null && code != item.profileCode) ||
            (path != null && path != item.imagePath)) {
          items[i] = item.copyWith(profileCode: code, imagePath: path);
        }
      }
    }

    if (window.isShutterOnly) {
      return items.where((item) => item.category == 'shutter').toList();
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
    double gh, {
    AluminumSeries? seriesOverride,
  }) {
    String dimText =
        'القياس (العرض × الارتفاع): ${gw.toStringAsFixed(1)} × ${gh.toStringAsFixed(1)} ملم';
    String result;
    if (glass.structure == GlassStructure.simple) {
      double thickness =
          glass.thicknessOuter ??
          window.getThicknessForFinish(glass.finishOuter, glass.colorOuter);
      double price = window.calculateTotalGlassPricePerSqmForZoneGlass(glass);
      String namePart = "";
      if (glass.processingOuter == GlassProcessing.laminated) {
        String lamCol = "شفاف";
        if (glass.laminatedColorOuter == 'white') {
          lamCol = "أبيض";
        } else if (glass.laminatedColorOuter == 'blue')
          lamCol = "أزرق";
        namePart = "مورق ($lamCol)";
      } else {
        String outerFinish = window.getFinishName(glass.finishOuter).trim();
        String outerColor = window.getArabicColorName(glass.colorOuter).trim();
        namePart = outerFinish == outerColor
            ? outerFinish
            : '$outerFinish $outerColor';
      }
      if (glass.processingOuter == GlassProcessing.tempered ||
          glass.temperedOuter) {
        namePart += ' + Trempé';
      }
      result =
          'زجاج مفرد\n${thickness.toStringAsFixed(0)}مم: $namePart (${price.toStringAsFixed(0)} دج/م²)\n$dimText';
    } else if (glass.structure == GlassStructure.closed) {
      double price = window.calculateTotalGlassPricePerSqmForZoneGlass(glass);
      final isDecor =
          isDecorPanelSubtype(glass.panneauSubtype) ||
          glass.finishOuter == GlassFinish.paneauSandwitchDecore;
      final panneauProduct = window.getPanneauProductForSpec(glass);

      String getArabicSubtypeName(String sub) {
        final s = sub.toLowerCase();
        if (s.contains('resine') ||
            s.contains('ارزين') ||
            s.contains('أرزين')) {
          return 'ارزين';
        }
        if (s.contains('plexi')) return 'بليكسي';
        if (s.contains('decore') || s.contains('ديكور')) return 'بانو ديكور';
        if (s.contains('sandwitch') ||
            s.contains('sandwich') ||
            s == 'panneau' ||
            s == 'بانو') {
          return 'بانو';
        }
        if (s.contains('aluco') || s.contains('الوكو')) return 'الوكو';
        if (s.contains('bardage') || s.contains('بارداش')) return 'بارداش';
        return sub;
      }

      String subtype = getArabicSubtypeName(
        glass.panneauSubtype ?? window.getFinishName(glass.finishOuter),
      );
      String color =
          glass.panneauColor ?? window.getClosedColoreName(glass.colorP);
      final productName = (panneauProduct?['name'] ?? '').toString().trim();
      final productLine = isDecor && productName.isNotEmpty
          ? '\n- الرسم: $productName'
          : '';
      final priceUnit = isDecor ? 'دج/قطعة' : 'دج/م²';
      result =
          'بانو (Panneau)\n- النوع: $subtype - اللون: $color$productLine (${price.toStringAsFixed(0)} $priceUnit)\n$dimText';
    } else {
      double intercallPrice = window.getPriceForIntercall(
        glass.intercallThickness,
      );
      double gasPrice = glass.hasGas
          ? window.getPriceForGas(glass.intercallThickness)
          : 0.0;

      double innerThickness =
          glass.thicknessInner ??
          window.getThicknessForFinish(glass.finishInner, glass.colorInner);
      double outerThickness =
          glass.thicknessOuter ??
          window.getThicknessForFinish(glass.finishOuter, glass.colorOuter);
      double intercallThickness = glass.intercallThickness.toDouble();
      double totalThickness =
          innerThickness + outerThickness + intercallThickness;

      double totalSqmPrice = window.calculateTotalGlassPricePerSqmForZoneGlass(
        glass,
      );

      String outDesc = "";
      if (glass.processingOuter == GlassProcessing.laminated) {
        String lamCol = "شفاف";
        if (glass.laminatedColorOuter == 'white') {
          lamCol = "أبيض";
        } else if (glass.laminatedColorOuter == 'blue')
          lamCol = "أزرق";
        outDesc = "مورق ($lamCol)";
      } else {
        String outerFinish = window.getFinishName(glass.finishOuter).trim();
        final outC = window.getArabicColorName(glass.colorOuter).trim();
        outDesc = outerFinish == outC ? outerFinish : '$outerFinish $outC';
      }
      if (glass.processingOuter == GlassProcessing.tempered ||
          glass.temperedOuter) {
        outDesc += ' + Trempé';
      }

      String inDesc = "";
      if (glass.processingInner == GlassProcessing.laminated) {
        String lamCol = "شفاف";
        if (glass.laminatedColorInner == 'white') {
          lamCol = "أبيض";
        } else if (glass.laminatedColorInner == 'blue')
          lamCol = "أزرق";
        inDesc = "مورق ($lamCol)";
      } else {
        String innerFinish = window.getFinishName(glass.finishInner).trim();
        final inC = window.getArabicColorName(glass.colorInner).trim();
        inDesc = innerFinish == inC ? innerFinish : '$innerFinish $inC';
      }
      if (glass.processingInner == GlassProcessing.tempered ||
          glass.temperedInner) {
        inDesc += ' + Trempé';
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

    // Append decoration details only when they are visible in the drawing.
    if (glass.structure == GlassStructure.double &&
        (glass.decorH > 0 || glass.decorV > 0)) {
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
    Map<String, dynamic>? matchingParclose;
    final chosenParclose = window.componentOverrides['باكيت الزجاج (Parclose)'];
    final activeSeries = seriesOverride ?? window.activeSeries;
    final chosenId = chosenParclose?['id'];
    final chosenSeriesId = chosenParclose?['series_id'];
    final selectedParclose = chosenParclose == null || activeSeries == null
        ? chosenParclose
        : ((chosenSeriesId != null &&
                  chosenSeriesId.toString() == activeSeries.id.toString()) ||
              (chosenId != null &&
                  activeSeries.sections.any(
                    (s) => s.id.toString() == chosenId.toString(),
                  )))
        ? chosenParclose
        : null;

    if (activeSeries != null) {
      // جمع كل باركلوزات السلسلة وترتيبها
      final allParcloseSections = activeSeries.sections
          .where(
            (s) =>
                (s.type.toLowerCase().contains('parclose') ||
                    s.name.contains('باكيت')) &&
                s.maxGlassThickness > 0.0,
          )
          .toList();
      allParcloseSections.sort(
        (a, b) => a.maxGlassThickness.compareTo(b.maxGlassThickness),
      );

      if (allParcloseSections.isNotEmpty) {
        Map<String, dynamic>? firstCapacityAtLeast(double required) {
          for (final section in allParcloseSections) {
            if (section.maxGlassThickness >= required) {
              return section.toMap();
            }
          }
          return null;
        }

        if (selectedParclose != null) {
          // المستخدم اختار — نحتفظ به فقط إذا كان يتحمل سمك الزجاج فعليًا.
          final double chosenMax =
              (selectedParclose['max_glass_thickness'] as num?)?.toDouble() ??
              0.0;
          final bool chosenMatchesGlass = chosenMax >= totalT;

          if (chosenMatchesGlass) {
            matchingParclose = selectedParclose;
          } else {
            // المختار صغير — ننتقل إلى أقرب سماكة أكبر داخل نفس السلسلة.
            matchingParclose =
                firstCapacityAtLeast(totalT) ??
                allParcloseSections.last.toMap();
          }
        } else {
          // لم يختر — بحث تلقائي حسب السمك الفعلي.
          matchingParclose =
              firstCapacityAtLeast(totalT) ?? allParcloseSections.first.toMap();
        }
      } else if (selectedParclose != null) {
        // السلسلة ليس فيها باركلوز — المختار يُستخدم
        matchingParclose = selectedParclose;
      }
    } else if (selectedParclose != null) {
      matchingParclose = selectedParclose;
    }

    // Use an explicitly selected parclose only when it is still compatible
    // with the current glass. If the drawing changed to double glazing, the
    // catalogue double parclose must become the warning/description target.
    if (selectedParclose != null && matchingParclose == null) {
      matchingParclose = selectedParclose;
    }

    if (matchingParclose != null) {
      final double maxG =
          (matchingParclose['max_glass_thickness'] as num?)?.toDouble() ?? 0.0;
      if (maxG > 0) {
        final bool isClosed = glass.structure == GlassStructure.closed;
        final String label = isClosed ? 'البانو' : 'الزجاج';
        if (totalT > maxG) {
          result +=
              '\n⚠️ تنبيه: سمك $label ($totalT مم) أكبر من سعة البيركلوز (${matchingParclose['name']}) ($maxG مم)';
        } else if (totalT < maxG - 0.01) {
          result +=
              '\n⚠️ تنبيه: سمك $label ($totalT مم) أصغر من سعة البيركلوز (${matchingParclose['name']}) ($maxG مم)';
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
    bool preferOverrideMap = false,
    bool priceByWholeBar = false,
    int? catalogItemId,
    int? colorId,
    String? overrideKey,
    String? selectorCategory,
    String? selectorType,
    String? roleKey,
    int? sourceSeriesId,
    String? materialType,
  }) {
    final Map<String, dynamic>? savedOverride =
        overrides.containsKey(originalName)
        ? overrides[originalName] as Map<String, dynamic>?
        : null;
    final Map<String, dynamic>? selectedOverride =
        preferOverrideMap && overrideMap != null
        ? overrideMap
        : savedOverride ?? overrideMap;
    bool isLinked = selectedOverride != null;
    double price = defaultPrice;
    double finalQty = qty;
    double? finalLength = length;
    String? cuttingListText;
    String? profileCode;
    String? imagePath;
    String subName = '';
    if (isLinked) {
      final ov = selectedOverride!;
      profileCode = ov['code']?.toString();
      imagePath = ov['image_path']?.toString();
      subName = '${ov['code'] ?? ''} - ${ov['name']}'.trim();
      if (subName.startsWith('- ')) subName = subName.substring(2);
      final rawPrice =
          ov['calculated_price'] ??
          ov['price_dzd'] ??
          ov['price'] ??
          defaultPrice;
      price = rawPrice is num
          ? rawPrice.toDouble()
          : double.tryParse(rawPrice.toString()) ?? defaultPrice;
    }
    double? exactBars;
    if (pieces != null && pieces.isNotEmpty) {
      double barLength = 5.8;
      if (isLinked) {
        final ov = selectedOverride!;
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
      name +=
          '\n(المطلوب الفعلي: ${exactBars.toStringAsFixed(2)} بارة / ${exactBars.toStringAsFixed(2)} bar)';
    }

    if (isLinked && (finalLength == null || finalLength == 0.0)) {
      final ov = selectedOverride!;
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
      // Most profiles keep the exact fractional consumption for costing.
      // Bardage is sold by complete stock pieces, so its rounded purchase
      // quantity is also its priced quantity.
      exactQuantity: priceByWholeBar ? finalQty : exactBars ?? finalQty,
      catalogItemId:
          catalogItemId ??
          (selectedOverride?['id'] is num
              ? (selectedOverride!['id'] as num).toInt()
              : int.tryParse('${selectedOverride?['id'] ?? ''}')),
      inventoryItemType: 'Section',
      colorId: colorId,
      overrideKey: overrideKey ?? originalName,
      selectorCategory: selectorCategory ?? 'profile',
      selectorType: selectorType ?? _selectorTypeForProfile(originalName),
      roleKey: roleKey,
      sourceSeriesId: sourceSeriesId,
      materialType: materialType,
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
    int? catalogItemId,
    int? colorId,
    String? overrideKey,
    String? selectorCategory,
    String? selectorType,
    String? roleKey,
    int? sourceSeriesId,
    String? materialType,
  }) {
    String lookupKey = originalName;
    if (!overrides.containsKey(lookupKey) &&
        lookupKey.startsWith('إسبانيوليت ') &&
        lookupKey.endsWith(' (Espagnolette)')) {
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
      price = (ov['calculated_price'] ?? ov['price'] ?? 0.0).toDouble();
    }
    final linkedCatalogueId =
        catalogItemId ??
        (isLinked && overrides[lookupKey]['id'] is num
            ? (overrides[lookupKey]['id'] as num).toInt()
            : int.tryParse(
                '${isLinked ? overrides[lookupKey]['id'] ?? '' : ''}',
              ));
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
      catalogItemId: linkedCatalogueId,
      inventoryItemType: 'Accessory',
      colorId: colorId,
      overrideKey: overrideKey ?? lookupKey,
      selectorCategory: selectorCategory ?? 'accessory',
      selectorType: selectorType ?? _selectorTypeForAccessory(originalName),
      roleKey: roleKey,
      sourceSeriesId: sourceSeriesId,
      materialType: materialType,
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
    int? catalogItemId,
    String? inventoryItemType,
    int? colorId,
    String? overrideKey,
    String? selectorCategory,
    String? selectorType,
    String? roleKey,
    int? sourceSeriesId,
    String? materialType,
  }) {
    String lookupKey = originalName;
    if (!overrides.containsKey(lookupKey) &&
        lookupKey.startsWith('إسبانيوليت ') &&
        lookupKey.endsWith(' (Espagnolette)')) {
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
      price = (ov['calculated_price'] ?? ov['price'] ?? 0.0).toDouble();
    }
    final linkedCatalogueId =
        catalogItemId ??
        (isLinked && overrides[lookupKey]['id'] is num
            ? (overrides[lookupKey]['id'] as num).toInt()
            : int.tryParse(
                '${isLinked ? overrides[lookupKey]['id'] ?? '' : ''}',
              ));
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
      catalogItemId: linkedCatalogueId,
      inventoryItemType: inventoryItemType ?? 'Accessory',
      colorId: colorId,
      overrideKey: overrideKey ?? lookupKey,
      selectorCategory: selectorCategory ?? category,
      selectorType:
          selectorType ??
          (category == 'shutter'
              ? _selectorTypeForShutter(originalName)
              : _selectorTypeForAccessory(originalName)),
      roleKey: roleKey,
      sourceSeriesId: sourceSeriesId,
      materialType: materialType,
    );
  }

  static BomItem _createJoint(
    Map<String, dynamic> overrides,
    String originalName, {
    String? color,
    double qty = 0,
    String unit = 'متر',
    double? exactQuantity,
    int? catalogItemId,
    String? overrideKey,
    String? selectorCategory,
    String? selectorType,
    String? roleKey,
    int? sourceSeriesId,
    String? materialType,
    double? targetThicknessMm,
  }) {
    final keyToUse = overrideKey ?? originalName;
    final ov = overrides[keyToUse] ?? overrides[originalName];
    bool isLinked = ov is Map;
    String name = originalName;
    double price = 0.0;
    String? profileCode;
    String? imagePath;
    if (isLinked) {
      profileCode = ov['code']?.toString();
      imagePath = ov['image_path']?.toString();
      final code = ov['code'] ?? '';
      final cName = ov['name'] ?? originalName;
      final details = code.toString().isNotEmpty ? '$code - $cName' : cName;
      name = '$originalName\n$details';
      price = (ov['price_per_meter'] ?? ov['calculated_price'] ?? 0.0)
          .toDouble();
    }
    final normalizedUnit = unit.toLowerCase().trim();
    final exactQty = exactQuantity ?? qty;
    if (exactQty > 0 &&
        (normalizedUnit.contains('متر') ||
            normalizedUnit.contains('meter') ||
            normalizedUnit == 'm' ||
            normalizedUnit == 'ml')) {
      name = '$name\n(المطلوب الفعلي: ${exactQty.toStringAsFixed(2)} $unit)';
    }
    final linkedCatalogueId =
        catalogItemId ??
        (isLinked && overrides[originalName]['id'] is num
            ? (overrides[originalName]['id'] as num).toInt()
            : int.tryParse(
                '${isLinked ? overrides[originalName]['id'] ?? '' : ''}',
              ));
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
      exactQuantity: exactQty,
      catalogItemId: linkedCatalogueId,
      inventoryItemType: 'Joints',
      overrideKey: overrideKey ?? originalName,
      selectorCategory: selectorCategory ?? 'joint',
      selectorType: selectorType ?? _selectorTypeForJoint(originalName),
      roleKey: roleKey,
      sourceSeriesId: sourceSeriesId,
      materialType: materialType,
      targetThicknessMm: targetThicknessMm,
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
    int? catalogItemId,
    int? colorId,
    String? overrideKey,
    String? selectorCategory,
    String? selectorType,
    String? roleKey,
    int? sourceSeriesId,
    String? materialType,
  }) {
    bool isLinked = overrides.containsKey(originalName);
    String name = originalName;
    double price = 0.0;
    double finalQty = qty;
    double? finalLength;
    double? finalExactQuantity;
    String? cuttingListText;
    String? profileCode;
    String? imagePath;

    if (isLinked) {
      final ov = overrides[originalName];
      profileCode = ov['code']?.toString();
      imagePath = ov['image_path']?.toString();
      name = '${ov['code'] ?? ''} - ${ov['name']}'.trim();
      if (name.startsWith('- ')) name = name.substring(2);
      final rawPrice =
          ov['calculated_price'] ?? ov['price_dzd'] ?? ov['price'] ?? 0.0;
      price = rawPrice is num
          ? rawPrice.toDouble()
          : double.tryParse(rawPrice.toString()) ?? 0.0;
    }
    final linkedCatalogueId =
        catalogItemId ??
        (isLinked && overrides[originalName]['id'] is num
            ? (overrides[originalName]['id'] as num).toInt()
            : int.tryParse(
                '${isLinked ? overrides[originalName]['id'] ?? '' : ''}',
              ));

    bool isSqmOrLinear = false;
    String finalUnit = unit;
    if (isLinked) {
      final ov = overrides[originalName];
      final dbUnit = (ov['unit'] ?? '').toString().toLowerCase().trim();

      if (dbUnit == 'sqm') {
        finalUnit = 'م²';
        isSqmOrLinear = true;
        if (windowWidth != null && windowHeight != null) {
          final double areaSqm =
              (windowWidth / 1000.0) * (windowHeight / 1000.0);
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
    final lowerOriginal = originalName.toLowerCase();
    final lowerName = name.toLowerCase();
    final isMeterJoint =
        finalUnit.toLowerCase().contains('متر') &&
        (lowerOriginal.contains('joint') ||
            lowerOriginal.contains('جوان') ||
            lowerOriginal.contains('brosse') ||
            lowerName.contains('joint') ||
            lowerName.contains('جوان') ||
            lowerName.contains('brosse'));
    if (isMeterJoint && finalQty > 0) {
      finalExactQuantity = ((finalQty * 100).round()) / 100.0;
      finalQty = finalExactQuantity.ceilToDouble();
      name =
          '$name\n(المطلوب الفعلي: ${finalExactQuantity.toStringAsFixed(2)} $finalUnit)';
    }
    final linkedOverride = isLinked ? overrides[originalName] : null;
    final isAccessoryOverride =
        linkedOverride is Map &&
        (linkedOverride.containsKey('material_type') ||
            linkedOverride.containsKey('screw_count') ||
            linkedOverride.containsKey('is_kit_screw') ||
            linkedOverride.containsKey('is_caisson_screw') ||
            linkedOverride.containsKey('is_moteur_screw')) &&
        !linkedOverride.containsKey('component_type');

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
      exactQuantity: finalExactQuantity,
      catalogItemId: linkedCatalogueId,
      inventoryItemType: isAccessoryOverride ? 'Accessory' : 'ShutterComponent',
      colorId: colorId,
      overrideKey: overrideKey ?? originalName,
      selectorCategory:
          selectorCategory ??
          (isAccessoryOverride || _textHasAny(originalName, const ['براغي'])
              ? 'accessory'
              : 'shutter'),
      selectorType: selectorType ?? _selectorTypeForShutter(originalName),
      roleKey: roleKey,
      sourceSeriesId: sourceSeriesId,
      materialType: materialType,
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
        final sec = activeSeries.sections.firstWhere(
          (s) => s.code.endsWith(targetSuffix!),
        );
        return sec.toMap();
      } catch (_) {}
    }

    try {
      final sec = activeSeries.sections.firstWhere((s) {
        final code = s.code.toLowerCase();
        final name = s.name.toLowerCase();
        final type = s.type.toLowerCase();
        if (isCentral) {
          return code.contains('67107') ||
              code.endsWith('107') ||
              name.contains('chicane') ||
              name.contains('central');
        } else {
          return code.contains('67108') ||
              code.endsWith('108') ||
              (name.contains('lateral') &&
                  (name.contains('renforc') || type.contains('renforc')));
        }
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

    try {
      final sec = activeSeries.sections.firstWhere((s) {
        final code = s.code.toLowerCase();
        if (isCentral) {
          return code.contains('67105') || code.endsWith('105');
        } else {
          return code.contains('67104') || code.endsWith('104');
        }
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
