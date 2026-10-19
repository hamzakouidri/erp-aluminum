// Force compile sync trigger 4
import 'package:database_data/Commande/Systeme/model.dart';
import 'package:database_data/Commande/Systeme/cutting_settings.dart';
import 'dart:math' as math;
import 'dart:ui' show Offset, Rect;
import 'package:collection/collection.dart';

String _withoutAccessoryQualityLabel(String value) => value
    .replaceAll(
      RegExp(
        r'\s*\([^)]*(?:جودة|قياسية|رفيعة|تجارية|qualit[ée]|quality|standard|premium|commercial)[^)]*\)',
        caseSensitive: false,
      ),
      '',
    )
    .trim();

/// Whether a profile row saved from the quantity table still describes the
/// section currently selected in the drawing. Rows without an id (legacy
/// price-only edits) and rows of the same section remain valid.
bool savedProfileOverrideMatchesSection(
  Map<dynamic, dynamic> saved,
  Map<String, dynamic>? selected,
) {
  int? idOf(Object? value) =>
      value is num ? value.toInt() : int.tryParse('${value ?? ''}'.trim());
  final savedId = idOf(saved['id']);
  final selectedId = idOf(selected?['id']);
  return savedId == null || selectedId == null || savedId == selectedId;
}

/// Area of the moustiquaire add-on, in m², for all units of the line. The
/// screen is cut 2 mm smaller than the frame on each axis, and the quantity
/// table shows the area rounded to 0.01 m²; the selling price must use the
/// same rounded area so both columns agree.
double moustiquaireAddonAreaSqm(WindowModel window) {
  final width = math.max(0.0, window.width - 2.0);
  final height = math.max(0.0, window.height - 2.0);
  return double.parse(
    (((width / 1000.0) * (height / 1000.0)) * window.quantity)
        .toStringAsFixed(2),
  );
}

class BomItem {
  final String category;
  final String originalName;
  final String? profileCode;
  final String name;
  final String? imagePath;
  final String? colorName;
  final double? length;
  final double? glassHeight;
  final int? pieceCount;
  final double quantity;
  final String unit;
  final double unitPrice;
  final bool isMissing;

  final bool isInteractive;
  final bool isActive;
  final String? exclusionGroup;
  final List<double>? pieces;

  /// Cutting angles aligned with [pieces], stored as `left/right` degrees.
  final List<String>? pieceCutAngles;
  final String? cuttingList;
  /// Workshop-only instruction rendered on the cutting sheet, never in the
  /// quantity/cost table or price editor.
  final String? productionNote;
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

  /// Total linear metres represented by the real cuts in this BOM row.
  /// `pieces` is already expressed in metres and includes the drawing
  /// quantity. This is separate from [requiredQuantity], which may be a
  /// fractional number of stock bars (for example 1.20 bars).
  double? get actualUsedMeters {
    final cuts = pieces;
    if (cuts != null && cuts.isNotEmpty) {
      final total =
          cuts.fold<double>(0.0, (sum, piece) => sum + piece) *
          linearMeterMultiplier;
      return total > 0 ? total : null;
    }

    final normalizedUnit = unit.toLowerCase().trim();
    final isLinearUnit =
        normalizedUnit == 'متر' ||
        normalizedUnit == 'm' ||
        normalizedUnit == 'ml' ||
        normalizedUnit == 'meter' ||
        normalizedUnit == 'meters';
    if (isLinearUnit && requiredQuantity > 0) {
      return requiredQuantity * linearMeterMultiplier;
    }
    return null;
  }

  /// Multiplier used when this profile participates in the linear-metre
  /// calculation. A plinthe is installed as two linear runs in the current
  /// construction rule, so one physical metre is counted twice.
  double get linearMeterMultiplier {
    final role = (roleKey ?? selectorType ?? '').trim().toLowerCase();
    return role == 'plant' ? 2.0 : 1.0;
  }

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
    this.pieceCount,
    required this.quantity,
    required this.unit,
    required this.unitPrice,
    this.isMissing = false,
    this.isInteractive = false,
    this.isActive = true,
    this.exclusionGroup,
    this.pieces,
    this.pieceCutAngles,
    this.cuttingList,
    this.productionNote,
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
  }) : this.name = _withoutAccessoryQualityLabel(name);

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
    // Catalogue labels can contain a quality suffix such as
    // "(جودة قياسية)". Use the cleaned value for the primary display too;
    // otherwise non-Kit rows that localize [originalName] would reintroduce
    // the suffix after [name] had already been cleaned.
    final original = _withoutAccessoryQualityLabel(originalName);

    // The BOM role is the stable heading. The selected catalogue row already
    // carries its exact size/name on the second line, so repeating a computed
    // size in the heading produces misleading pairs such as
    // "Espagnolette 160 / Esp 180".
    if (original.contains('إسبانيوليت') ||
        original.contains('اسبانيولات') ||
        original.contains('Espagnolette')) {
      final sliding = original.contains('منزلق');
      if (lang == 'fr') {
        return sliding ? 'Espagnolette Coulissante' : 'Espagnolette';
      }
      if (lang == 'en') {
        return sliding ? 'Sliding Espagnolette' : 'Espagnolette';
      }
      return sliding ? 'إسبانيوليت منزلق' : 'إسبانيوليت';
    }

    // 1. Screws
    if (original.contains('براغي الصندوق')) {
      if (lang == 'fr') return 'Vis de caisson';
      if (lang == 'en') return 'Box screws';
      return 'براغي الصندوق (Vis de caisson)';
    }
    if (original == 'براغي التجميع' ||
        original == "براغي التجميع (vis d'assemblage)") {
      if (lang == 'fr') return "vis d'assemblage";
      if (lang == 'en') return 'Assembly screws';
      return "براغي التجميع (vis d'assemblage)";
    }

    // 2. Stiles: Central and Lateral (Normal and Reinforced)
    if (original == 'قائم وسطي معزز (Sash Central Renforcé)' ||
        original == 'قائم وسطي معزز (Central Renforcé)' ||
        original == 'قائم وسطي معزز' ||
        original == 'Sash Central Renforcé') {
      if (lang == 'fr') return 'Central Renforcé';
      if (lang == 'en') return 'Central Reinforced';
      return 'قائم وسطي معزز (Central Renforcé)';
    }

    if (original == 'قائم جانبي معزز (Sash Lateral Renforcé)' ||
        original == 'قائم جانبي معزز (Latéral Renforcé)' ||
        original == 'قائم جانبي معزز' ||
        original == 'Sash Lateral Renforcé') {
      if (lang == 'fr') return 'Latéral Renforcé';
      if (lang == 'en') return 'Lateral Reinforced';
      return 'قائم جانبي معزز (Latéral Renforcé)';
    }

    if (original == 'قائم وسطي (Sash Central)' ||
        original == 'قائم وسطي (Central)' ||
        original == 'قائم وسطي' ||
        original == 'Sash Central') {
      if (lang == 'fr') return 'Central';
      if (lang == 'en') return 'Central';
      return 'قائم وسطي (Central)';
    }

    if (original == 'قائم جانبي (Sash Lateral)' ||
        original == 'قائم جانبي (Lateral)' ||
        original == 'قائم جانبي (Latéral)' ||
        original == 'قائم جانبي' ||
        original == 'Sash Lateral') {
      if (lang == 'fr') return 'Latéral';
      if (lang == 'en') return 'Lateral';
      return 'قائم جانبي (Latéral)';
    }

    if (original.contains('أغطية القائم الوسطي المعزز') ||
        original.contains('Bouchons Montant Central Renforcé')) {
      if (lang == 'fr') return 'Bouchons Central Renforcé';
      if (lang == 'en') return 'Central Reinforced End Caps';
      return 'أغطية القائم الوسطي المعزز (Bouchons Central Renforcé)';
    }

    if (original.contains('أغطية القائم الجانبي المعزز') ||
        original.contains('Bouchons Montant Latéral Renforcé')) {
      if (lang == 'fr') return 'Bouchons Latéral Renforcé';
      if (lang == 'en') return 'Lateral Reinforced End Caps';
      return 'أغطية القائم الجانبي المعزز (Bouchons Latéral Renforcé)';
    }

    if (original.contains('كيت العمود الوسطي المعزز') ||
        original.contains('Kit Central Renforcé')) {
      if (lang == 'fr') return 'Kit Central Renforcé';
      if (lang == 'en') return 'Central Reinforced Kit';
      return 'كيت العمود الوسطي المعزز (Kit Central Renforcé)';
    }

    if (original.contains('كيت العمود الجانبي المعزز') ||
        original.contains('Kit Lateral Renforcé')) {
      if (lang == 'fr') return 'Kit Latéral Renforcé';
      if (lang == 'en') return 'Lateral Reinforced Kit';
      return 'كيت العمود الجانبي المعزز (Kit Latéral Renforcé)';
    }

    // 3. Sliding Frame (Coulissant)
    if (original == 'إطار منزلق (Cadre Coulissant)' ||
        original == 'إطار منزلق (Coulissant)' ||
        original == 'إطار منزلق' ||
        original == 'منزلق' ||
        original == 'Cadre Coulissant') {
      if (lang == 'fr') return 'Coulissant';
      if (lang == 'en') return 'Sliding Frame';
      return 'إطار منزلق (Coulissant)';
    }

    // 4. Corner Angle Frames & Profiles
    if (original == 'إطار فتح لجهة بروفيل الزاوية (Dormant côté angle)' ||
        original.contains('فتح لجهة بروفيل الزاوية')) {
      if (lang == 'fr') return 'Dormant côté angle';
      if (lang == 'en') return 'Opening Frame (Corner)';
      return 'إطار فتح لجهة بروفيل الزاوية (Dormant côté angle)';
    }

    if (original ==
            'إطار منزلق لجهة بروفيل الزاوية (Cadre coulissant côté angle)' ||
        original.contains('منزلق لجهة بروفيل الزاوية')) {
      if (lang == 'fr') return 'Cadre coulissant côté angle';
      if (lang == 'en') return 'Sliding Frame (Corner)';
      return 'إطار منزلق لجهة بروفيل الزاوية (Cadre coulissant côté angle)';
    }

    if (original.contains('بروفيل الزاوية 90°') ||
        original.contains("Profil d'angle / Tube carré")) {
      if (lang == 'fr') return "Profil d'angle 90°";
      if (lang == 'en') return 'Corner Profile 90°';
      return "بروفيل الزاوية 90° (Profil d'angle)";
    }

    if (original.contains('بروفيل الزاوية') ||
        original.contains("Profil d'angle")) {
      if (lang == 'fr') return "Profil d'angle";
      if (lang == 'en') return 'Corner Profile';
      return "بروفيل الزاوية (Profil d'angle)";
    }

    // 5. Custom Frame Sides (إطار جهة ...)
    if (original.contains('إطار جهة') || original.contains('Frame side')) {
      final List<String> frSides = [];
      if (original.contains('علوي')) frSides.add('haut');
      if (original.contains('يمين')) frSides.add('droit');
      if (original.contains('سفلي')) frSides.add('bas');
      if (original.contains('يسار')) frSides.add('gauche');
      final frLabel = frSides.isEmpty ? '' : ' côté ${frSides.join(' + ')}';
      if (lang == 'fr') {
        return 'Dormant$frLabel';
      }
      if (lang == 'en') {
        final List<String> enSides = [];
        if (original.contains('علوي')) enSides.add('top');
        if (original.contains('يمين')) enSides.add('right');
        if (original.contains('سفلي')) enSides.add('bottom');
        if (original.contains('يسار')) enSides.add('left');
        final enLabel = enSides.isEmpty ? '' : ' (${enSides.join(' + ')})';
        return 'Frame side$enLabel';
      }
      final arabicSides = original
          .split('(')
          .first
          .replaceFirst('إطار جهة', '')
          .trim();
      return 'إطار جهة $arabicSides (Dormant$frLabel)';
    }

    // 6. Standard Frame (الإطار)
    if (original == 'الإطار (Frame)' ||
        original == 'إطار (Frame)' ||
        original == 'الإطار (Dormant)' ||
        original == 'إطار (Dormant)' ||
        original == 'الإطار' ||
        original == 'إطار') {
      if (lang == 'fr') return 'Dormant';
      if (lang == 'en') return 'Frame';
      return 'الإطار (Dormant)';
    }

    // 7. Opening Sash (الضلفة / الظلفة)
    if (original == 'الظلفة (Sash)' ||
        original == 'الضلفة (Sash)' ||
        original == 'الظلفة (Ouvrant)' ||
        original == 'الضلفة (Ouvrant)' ||
        original == 'الظلفة' ||
        original == 'الضلفة') {
      if (lang == 'fr') return 'Ouvrant';
      if (lang == 'en') return 'Sash';
      return 'الضلفة (Ouvrant)';
    }

    // 'الظلفة المنزلقة (Sliding Sash)' is the BOM key itself; it reached the
    // generic replacement below and was shown as "Sliding Ouvrant".
    if (original == 'الظلفة المنزلقة' ||
        original == 'الضلفة المنزلقة' ||
        original == 'الظلفة المنزلقة (Sliding Sash)' ||
        original == 'الضلفة المنزلقة (Sliding Sash)' ||
        original.toLowerCase() == 'sliding sash') {
      if (lang == 'fr') return 'Ouvrant Coulissant';
      if (lang == 'en') return 'Sliding Sash';
      return 'الضلفة المنزلقة (Ouvrant Coulissant)';
    }

    final lowerOriginal = original.toLowerCase();

    // Specific profile translations requested for clean display across languages:
    if (lowerOriginal.contains('cache dormant') ||
        lowerOriginal.contains('cache_dormant') ||
        original.contains('كاش دورمو') ||
        original.contains('كاش الإطار')) {
      if (lang == 'fr') return 'Cache dormant';
      if (lang == 'ar') return 'كاش دورمو (Cache dormant)';
      return 'Frame Cover';
    }
    if (lowerOriginal.contains('seuil') ||
        original.contains('سوي') ||
        original.contains('عتبة')) {
      if (lang == 'fr') return 'Seuil';
      if (lang == 'ar') return 'سوي (Seuil)';
      return 'Threshold';
    }
    if (lowerOriginal.contains('cache-rail') ||
        lowerOriginal.contains('cache rail') ||
        lowerOriginal.contains('cache_rail') ||
        original.contains('كاش راي')) {
      if (lang == 'fr') return 'Cache-rail';
      if (lang == 'ar') return 'كاش راي (Cache-rail)';
      return 'Rail Cover';
    }
    if (lowerOriginal.contains('chicane') ||
        original.contains('شيكان') ||
        original.contains('الشيكان')) {
      final isReinforced =
          lowerOriginal.contains('renforc') || original.contains('معزز');
      if (isReinforced) {
        if (lang == 'fr') return 'Chicane Renforcée';
        if (lang == 'ar') return 'شيكان معزز (Chicane Renforcée)';
        return 'Reinforced Chicane';
      }
      if (lang == 'fr') return 'Chicane';
      if (lang == 'ar') return 'شيكان (Chicane)';
      return 'Chicane';
    }
    if (lowerOriginal.contains('renfort rapport') ||
        original.contains('عمود تدعيم مستقل') ||
        original.contains('عمود مدعم مستقل')) {
      if (lang == 'fr') return 'Profilé Renfort Rapporté';
      if (lang == 'ar') return 'عمود تدعيم مستقل (Profilé Renfort Rapporté)';
      return 'Independent Reinforcement Profile';
    }
    if (original.contains('براغي تثبيت العمود المدعم') ||
        lowerOriginal.contains('vis de renfort')) {
      if (lang == 'fr') return 'Vis Renfort 3.9×38';
      if (lang == 'ar') return 'براغي تدعيم 3.9×38 (Vis Renfort)';
      return 'Reinforcement Screws 3.9×38';
    }
    if (original.contains('أغطية العمود المدعم') ||
        lowerOriginal.contains('caches / bouchons de renfort') ||
        lowerOriginal.contains('caches renfort')) {
      if (lang == 'fr') return 'Caches Renfort';
      if (lang == 'ar') return 'أغطية العمود المدعم (Caches Renfort)';
      return 'Reinforcement End Caps';
    }
    if (lowerOriginal.contains('sliding frame extension') ||
        lowerOriginal.contains('frame extension') ||
        lowerOriginal.contains('complément dormant') ||
        lowerOriginal.contains('complement dormant') ||
        lowerOriginal.contains('dormant ajouté') ||
        lowerOriginal.contains('dormant ajoute') ||
        original.contains('مكمل الإطار') ||
        original.contains('كومبليمو دورمو') ||
        original.contains('دورمو أجوت')) {
      if (lang == 'fr') return 'Complément Dormant';
      if (lang == 'ar') return 'كومبليمو دورمو (Complément Dormant)';
      return 'Frame Extension';
    }
    if (lowerOriginal.contains('cache-rainure') ||
        lowerOriginal.contains('cache rainure') ||
        lowerOriginal.contains('cache_rainure') ||
        original.contains('كاش رينور')) {
      if (lang == 'fr') return 'Cache-rainure';
      if (lang == 'ar') return 'كاش رينور (Cache-rainure)';
      return 'Groove Cover';
    }
    if (lowerOriginal.contains('bavette') || original.contains('بافيت')) {
      if (lang == 'fr') return 'Bavette';
      if (lang == 'ar') return 'بافيت (Bavette)';
      return 'Weatherboard';
    }
    if (lowerOriginal.contains('cache-caniveau') ||
        lowerOriginal.contains('cache caniveau') ||
        original.contains('كاش كانيفو')) {
      if (lang == 'fr') return 'Cache-caniveau';
      if (lang == 'ar') return 'كاش كانيفو (Cache-caniveau)';
      return 'Gutter Cover';
    }
    if (lowerOriginal.contains('caniveau') || original.contains('كانيفو')) {
      if (lang == 'fr') return 'Caniveau';
      if (lang == 'ar') return 'كانيفو (Caniveau)';
      return 'Gutter';
    }

    if (lang == 'fr') {
      if (original == 'سكة الظلفة (Sash Traverse)' ||
          original == 'عرضي الظلفة') {
        return 'Traverse Ouvrant';
      }
      if (original == 'بلانت الظلفة (Plinthe Sash)') {
        return 'Plinthe Ouvrant';
      }
      if (original == 'حديد الباطمو (Renfort Batmo)') {
        return 'Renfort Battement';
      }
      if (original == 'الباتمو (Batmo)' ||
          original == 'الباتمو' ||
          original == 'الباطمو') {
        return 'Meneau';
      }
      if (original == 'بوشون باتمو (Bouchon Batmo)') {
        return 'Bouchon Meneau';
      }
      if (original == 'حديد الإطار (Renfort Frame)') {
        return 'Renfort Dormant';
      }
      if (original.contains('حديد الظلفة الخاص بالمفاصل')) {
        return 'Renfort Ouvrant (Paumelles)';
      }
      if (original == 'حديد الظلفة' ||
          original == 'حديد الظلفة (Renfort Sash)') {
        return 'Renfort Ouvrant';
      }
      if (original == 'حديد التقسيم (Renfort Mullion)') {
        return 'Renfort Traverse / Montant';
      }
      if (original == 'الزجاج') return 'Vitrage';
      if (original.contains('براغي حديد الدعم')) return 'Vis pour Renfort';
      if (original.contains('براغي الباتمو')) return 'Vis Meneau 3.9×50';
      if (original.contains('براغي بوشون باتمو')) return 'Vis Bouchon Meneau';
      if (original.contains('براغي الإكسسوارات')) return 'Vis Accessoires';
      if (original == 'الفيرو (Verrou)') return 'Verrou';
      if (original == 'Verrou Central') return 'Verrou Central';
      if (original == 'System OB') return 'Système OB';
      if (original == 'Demi System OB') return 'Demi Système OB';
      if (original.contains('إسبانيوليت') ||
          original.contains('اسبانيولات') ||
          original.contains('Espagnolette')) {
        final sizes = RegExp(
          r'(?<!\d)(\d+(?:[.,]\d+)?)(?:\s*(?:mm|cm))?(?!\d)',
          caseSensitive: false,
        ).allMatches(original).map((m) => m.group(1)!).toList();
        final suffix = sizes.isEmpty ? '' : ' ${sizes.last}';
        final sliding = original.contains('منزلق') ? ' Coulissant' : '';
        return 'Espagnolette$sliding$suffix';
      }
      if (original == 'المقبض (Handle)') return 'Poignée Fenêtre';
      if (original == 'مقبض منزلق (Poignée Coulissante)') {
        return 'Poignée Coulissante';
      }
      if (original == 'مقبض مدمج (Poignée Encastrée)') {
        return 'Poignée Encastrée';
      }
      if (original == 'مقبض الباب (Poignée Porte à Clé)') {
        return 'Poignée Porte à Clé';
      }
      if (original == 'قفل الباب (Serrure)') return 'Serrure';
      if (original == 'الأسطوانة (Canon)') return 'Canon';
      if (original == 'قاش بورت (Gache Porte)') return 'Gâche Porte';
      if (original == 'المفاصل (Hinges)') return 'Paumelles';
      if (original == 'عجلات المنزلق (Roulettes)') return 'Roulettes';
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

      final open = original.indexOf('(');
      final close = original.lastIndexOf(')');
      if (open >= 0 && close > open) {
        var foreign = original.substring(open + 1, close).trim();
        foreign = foreign
            .replaceAll('Sash Central Renforcé', 'Central Renforcé')
            .replaceAll('Sash Lateral Renforcé', 'Latéral Renforcé')
            .replaceAll('Sash Central', 'Central')
            .replaceAll('Sash Lateral', 'Latéral')
            .replaceAll('Montant Central', 'Central')
            .replaceAll('Montant Latéral', 'Latéral')
            .replaceAll('Cadre Coulissant', 'Coulissant')
            .replaceAll('Frame', 'Dormant')
            .replaceAll('Sash', 'Ouvrant');
        if (foreign.isNotEmpty &&
            !RegExp(r'[\u0600-\u06FF]').hasMatch(foreign)) {
          return foreign;
        }
      }

      var cleaned = original
          .replaceAll('إطار', 'Dormant')
          .replaceAll('الإطار', 'Dormant')
          .replaceAll('منزلق', 'Coulissant')
          .replaceAll('قائم وسطي معزز', 'Central Renforcé')
          .replaceAll('قائم جانبي معزز', 'Latéral Renforcé')
          .replaceAll('قائم وسطي', 'Central')
          .replaceAll('قائم جانبي', 'Latéral')
          .replaceAll('الضلفة', 'Ouvrant')
          .replaceAll('الظلفة', 'Ouvrant')
          .replaceAll('عرضي', 'Traverse')
          .replaceAll('الري', 'Rail')
          .replaceAll('الشيكان', 'Chicane')
          .replaceAll('شيكان', 'Chicane')
          .replaceAll('زاوية', 'Angle')
          .replaceAll('براغي', 'Vis');
      cleaned = cleaned.replaceAll(RegExp(r'[\u0600-\u06FF]'), '').trim();
      cleaned = cleaned.replaceAll(RegExp(r'^\(+|\)+$'), '').trim();
      if (cleaned.isNotEmpty) return cleaned;
    } else if (lang == 'en') {
      if (original == 'سكة الظلفة (Sash Traverse)' ||
          original == 'عرضي الظلفة') {
        return 'Sash Traverse';
      }
      if (original == 'بلانت الظلفة (Plinthe Sash)') {
        return 'Plinthe Sash';
      }
      if (original == 'حديد الباطمو (Renfort Batmo)') return 'Renfort Batmo';
      if (original == 'الباتمو (Batmo)' ||
          original == 'الباتمو' ||
          original == 'الباطمو') {
        return 'Batmo';
      }
      if (original == 'بوشون باتمو (Bouchon Batmo)') {
        return 'Bouchon Batmo';
      }
      if (original == 'حديد الإطار (Renfort Frame)') {
        return 'Renfort Frame';
      }
      if (original.contains('حديد الظلفة الخاص بالمفاصل')) {
        return 'Renfort Sash (Hinges)';
      }
      if (original == 'حديد الظلفة' ||
          original == 'حديد الظلفة (Renfort Sash)') {
        return 'Renfort Sash';
      }
      if (original == 'حديد التقسيم (Renfort Mullion)') {
        return 'Renfort Mullion';
      }
      if (original == 'الزجاج') return 'Vitrage';
      if (original.contains('براغي حديد الدعم')) return 'Renfort Screws';
      if (original.contains('براغي الباتمو')) return 'Batmo Screws 3.9×50';
      if (original.contains('براغي بوشون باتمو')) return 'Bouchon Batmo Screws';
      if (original.contains('براغي الإكسسوارات')) return 'Accessory Screws';
      if (original == 'الفيرو (Verrou)') return 'Verrou';
      if (original == 'Verrou Central') return 'Verrou Central';
      if (original == 'System OB') return 'System OB';
      if (original == 'Demi System OB') return 'Demi System OB';
      if (original.contains('إسبانيوليت') ||
          original.contains('اسبانيولات') ||
          original.contains('Espagnolette')) {
        final sizes = RegExp(
          r'(?<!\d)(\d+(?:[.,]\d+)?)(?:\s*(?:mm|cm))?(?!\d)',
          caseSensitive: false,
        ).allMatches(original).map((m) => m.group(1)!).toList();
        final suffix = sizes.isEmpty ? '' : ' ${sizes.last}';
        final sliding = original.contains('منزلق') ? ' Sliding' : '';
        return 'Espagnolette$sliding$suffix';
      }
      if (original == 'المقبض (Handle)') return 'Window Handle';
      if (original == 'مقبض منزلق (Poignée Coulissante)') {
        return 'Sliding Window Handle';
      }
      if (original == 'مقبض مدمج (Poignée Encastrée)') {
        return 'Recessed Handle';
      }
      if (original == 'مقبض الباب (Poignée Porte à Clé)') return 'Door Handle';
      if (original == 'قفل الباب (Serrure)') return 'Serrure (Lock)';
      if (original == 'الأسطوانة (Canon)') return 'Cylinder (Canon)';
      if (original == 'قاش بورت (Gache Porte)') return 'Door Strike Plate';
      if (original == 'المفاصل (Hinges)') return 'Hinges';
      if (original == 'عجلات المنزلق (Roulettes)') return 'Roulettes';
      if (original == 'كاش كوليسون (Gache coulissant)') return 'Strike Plate';
      if (original == 'Gâche coulissant TPR') return 'Strike Plate TPR';
      if (original == 'كريمون (Cremone)') return 'Cremone';
      if (original == 'تراينغل الكريمون (Triangle)') return 'Cremone Tringle';
      if (original == 'بوشون بارك لوز (Bouchon Parclose)') {
        return 'Bouchon Parclose';
      }
      if (original == 'قفل نقطة') return 'Point lock';

      final open = original.indexOf('(');
      final close = original.lastIndexOf(')');
      if (open >= 0 && close > open) {
        final foreign = original.substring(open + 1, close).trim();
        if (foreign.isNotEmpty) return foreign;
      }
    }

    if (lang == 'ar') {
      // In Arabic mode, display Arabic with French in parentheses: "العربية (Français)"
      var arText = original;
      arText = arText
          .replaceAll('(Frame)', '(Dormant)')
          .replaceAll('(Sash Central Renforcé)', '(Central Renforcé)')
          .replaceAll('(Sash Lateral Renforcé)', '(Latéral Renforcé)')
          .replaceAll('(Sash Central)', '(Central)')
          .replaceAll('(Sash Lateral)', '(Latéral)')
          .replaceAll('(Cadre Coulissant)', '(Coulissant)')
          .replaceAll('(Sash)', '(Ouvrant)')
          .replaceAll('(Montant Central)', '(Central)')
          .replaceAll('(Montant Latéral)', '(Latéral)');
      return arText;
    }

    return original;
  }

  static String localizeSubText(String text, String lang) {
    if (text.contains('المطلوب الفعلي:')) {
      // The Arabic line may also contain the full-bars/remaining-centimetres
      // breakdown. Keep it intact instead of truncating it at the first unit.
      if (lang == 'ar') return text;
      final reg = RegExp(
        r'المطلوب الفعلي:\s*([0-9\.]+)\s*([^\s\)\/]+)(?:\s*\/\s*([0-9\.]+)\s*([^\s\)]+))?',
      );
      final match = reg.firstMatch(text);
      if (match != null) {
        final num1 = match.group(1) ?? '';
        final unit1 = match.group(2) ?? '';
        final num2 = match.group(3);
        final unit2 = match.group(4);

        if (lang == 'fr') {
          String frUnit = 'bar';
          if (unit2 != null && unit2.isNotEmpty) {
            frUnit = unit2;
          } else if (unit1.contains('متر') || unit1 == 'm') {
            frUnit = 'm';
          } else if (unit1.contains('قطعة') || unit1 == 'pièce') {
            frUnit = 'pièce';
          }
          final numberStr = num2 ?? num1;
          return '(Besoin réel: $numberStr $frUnit)';
        } else if (lang == 'en') {
          String enUnit = 'bar';
          if (unit2 != null && unit2.isNotEmpty) {
            enUnit = unit2;
          } else if (unit1.contains('متر') || unit1 == 'm') {
            enUnit = 'm';
          } else if (unit1.contains('قطعة') || unit1 == 'pcs') {
            enUnit = 'pcs';
          }
          final numberStr = num2 ?? num1;
          return '(Actual requirement: $numberStr $enUnit)';
        } else {
          String arUnit = unit1;
          if (arUnit == 'bar' || arUnit == 'barre') arUnit = 'بارة';
          return '(المطلوب الفعلي: $num1 $arUnit)';
        }
      }
    }
    return text;
  }

  String? getLocalizedCuttingList(String lang) {
    if (cuttingList == null || cuttingList!.isEmpty) return cuttingList;
    final text = cuttingList!;
    if (lang == 'fr') {
      return text
          .replaceAll('قطع القص:', 'Liste de coupe:')
          .replaceAll('مم', 'mm')
          .replaceAll('جهة سفلية فقط', 'Côté bas uniquement')
          .replaceAll('الجهات الأربع', 'Les 4 côtés')
          .replaceAll(
            'جهة خارجية أسفل الإطار',
            'Côté extérieur sous le dormant',
          )
          .replaceAll(
            'داخل + خارج لكل التقاء إطارين',
            'Intérieur + extérieur par jonction',
          );
    } else if (lang == 'en') {
      return text
          .replaceAll('قطع القص:', 'Cutting list:')
          .replaceAll('مم', 'mm')
          .replaceAll('جهة سفلية فقط', 'Bottom side only')
          .replaceAll('الجهات الأربع', 'All 4 sides')
          .replaceAll('جهة خارجية أسفل الإطار', 'Outside under frame')
          .replaceAll(
            'داخل + خارج لكل التقاء إطارين',
            'Inside + outside per frame junction',
          );
    }
    return text;
  }

  BomItem copyWith({
    bool? isActive,
    String? name,
    String? kitGroupName,
    double? qty,
    double? unitPrice,
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
    int? pieceCount,
    String? cuttingList,
    String? productionNote,
    List<String>? pieceCutAngles,
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
      pieceCount: pieceCount ?? this.pieceCount,
      quantity: qty ?? this.quantity,
      unit: unit,
      unitPrice: unitPrice ?? this.unitPrice,
      isMissing: isMissing,
      isInteractive: isInteractive,
      isActive: isActive ?? this.isActive,
      exclusionGroup: exclusionGroup,
      pieces: pieces,
      pieceCutAngles: pieceCutAngles ?? this.pieceCutAngles,
      cuttingList: cuttingList ?? this.cuttingList,
      productionNote: productionNote ?? this.productionNote,
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
  /// The optional-part switches (kits, tandem, embout, supports...) every
  /// consumer of [generateBom] must use unless the user changed them in the
  /// quantity table. The table, cutting sheet, required goods, consumption
  /// report and cutting optimisers used to build their own maps with
  /// different values, so one drawing could count a tandem in one document
  /// and an embout in another.
  /// The kit the user selected, matched by its KitBundles id so a renamed
  /// kit stays selected. The saved name is used only for selections stored
  /// without an id (older orders). Returns null when the selection is not in
  /// [pool].
  static Map<String, dynamic>? selectedKitBundle(
    Object? savedSelection,
    Iterable<Map<String, dynamic>> pool,
  ) {
    if (savedSelection is! Map ||
        savedSelection['catalog_source'] != 'KitBundles') {
      return null;
    }
    int? readId(Object? raw) =>
        raw is num ? raw.toInt() : int.tryParse('${raw ?? ''}'.trim());
    final savedId = readId(savedSelection['id']);
    if (savedId != null) {
      for (final kit in pool) {
        if (readId(kit['id']) == savedId) return kit;
      }
      return null;
    }
    final savedName = savedSelection['name']?.toString() ?? '';
    if (savedName.isEmpty) return null;
    for (final kit in pool) {
      if ((kit['name'] ?? '').toString() == savedName) return kit;
    }
    return null;
  }

  /// Whether [value] falls in a kit range. Ranges are half-open
  /// `[min_mm, max_mm)`, as the overlap check uses when they are saved, so
  /// touching ranges such as 10–20 kg and 20–30 kg give 20 kg to the second
  /// one only. The upper bound still counts when no range of the same
  /// compatibility group starts there (the last range). Matching both ends
  /// made a weight on a boundary select two ranges and count the part twice.
  static bool kitRangeContains(
    Map<String, dynamic> range,
    double value,
    Iterable<Map<String, dynamic>> siblings,
  ) {
    double? read(Map<String, dynamic> row, String key) {
      final raw = row[key];
      return raw is num ? raw.toDouble() : double.tryParse('${raw ?? ''}');
    }

    int group(Map<String, dynamic> row) =>
        ((row['compatibility_group'] as num?)?.toInt() ?? 0).clamp(0, 2);

    final min = read(range, 'min_mm') ?? 0;
    final max = read(range, 'max_mm') ?? double.infinity;
    if (value < min || value > max) return false;
    if (value < max) return true;
    final rangeGroup = group(range);
    return !siblings.any(
      (other) =>
          !identical(other, range) &&
          group(other) == rangeGroup &&
          (read(other, 'min_mm') ?? 0) == max,
    );
  }

  /// Switches kept on the model itself or derived from a selected component;
  /// they are never stored as user variant choices.
  static const Set<String> modelBackedVariantKeys = {
    'Verrou Central',
    'System OB',
    'Demi System OB',
    'أغطية الشفرات (Bouchons Lames)',
  };

  /// Identifies the shutter mechanism and box a set of user variant choices
  /// was made for.
  static String shutterVariantContext(WindowModel window) =>
      '${window.shutterMechanism}|${window.isCaissonTunnel}';

  /// The rule-based switches, with the user's choices from the quantity
  /// table applied on top when they were made for the current mechanism.
  /// [includeUserChoices] false returns the rules alone.
  static Map<String, bool> standardActiveVariants(
    WindowModel window, {
    bool includeUserChoices = true,
  }) {
    final variants = _ruleActiveVariants(window);
    if (includeUserChoices &&
        window.shutterVariantChoicesContext == shutterVariantContext(window)) {
      window.shutterVariantChoices.forEach((key, value) {
        if (variants.containsKey(key) &&
            !modelBackedVariantKeys.contains(key)) {
          variants[key] = value;
        }
      });
    }
    return variants;
  }

  static Map<String, bool> _ruleActiveVariants(WindowModel window) {
    final isTunnel = window.isCaissonTunnel;
    final mechanism = window.shutterMechanism;
    final isMotor = mechanism == 'محرك';
    final isCrank =
        mechanism == 'منايفال' || mechanism == 'مانيفال' || mechanism == 'مانيفر';
    final blade = window.componentOverrides['الشرائح (Lames)'];
    final bladeText = blade is Map
        ? '${blade['name'] ?? ''} ${blade['shutter_subtype'] ?? ''}'
              .toLowerCase()
        : '';
    final isX3dBlade =
        bladeText.contains('x3d') ||
        bladeText.contains('extrud') ||
        bladeText.contains('إكسترودي') ||
        bladeText.contains('اكسترودي');
    final isX3dPvc = !isTunnel && window.isPVC && isX3dBlade;
    final motor = window.componentOverrides['المحرك (Moteur)'];
    final rawCrank = motor is Map ? motor['motor_has_emergency_crank'] : null;
    final motorHasEmergencyCrank = rawCrank is bool
        ? rawCrank
        : rawCrank is num
        ? rawCrank != 0
        : const [
            '1',
            'true',
            'yes',
            'oui',
            'نعم',
          ].contains(rawCrank?.toString().trim().toLowerCase());

    return {
      'Verrou Central': window.useVerrouCentral,
      'System OB': window.effectiveUseSystemOB,
      'Demi System OB': window.effectiveUseDemiOB,
      'كيت (Kit)': false,
      'كيت فولي موتور (Kit Volet Moteur)': !isTunnel && isMotor,
      'كيت فولي مانيفر (Kit Volet Manivelle)': !isTunnel && isCrank,
      'كيت مانيفر (Kit Manivelle)': !isTunnel && isCrank,
      'كيت صندوق النفق (Kit Caisson Tunnel)': isTunnel,
      'كيت فولي (Kit Volet)': !isTunnel && !isMotor && !isCrank,
      'كيت حزام (Kit Sangle)': false,
      'طانديم (Tandem)': isTunnel,
      'الامبو (Embout)': isMotor,
      'سيبور رولمو (Support Roulement)': isMotor,
      'سيبور موتور (Support Moteur)': isMotor
          ? (!isX3dPvc || !motorHasEmergencyCrank)
          : isTunnel,
      'أغطية الشفرات (Bouchons Lames)': window.componentOverrides.containsKey(
        'أغطية الشفرات (Bouchons Lames)',
      ),
    };
  }

  /// Returns the lower and upper Tringle cuts driven by one Cremone.
  ///
  /// The deduction is applied to the total usable length. The handle's
  /// displacement from the sash centre is then shared equally by the two
  /// cuts, so the two returned lengths always add up to `height - deduction`.
  static List<double> cremoneTringleCutsMm({
    required double heightMm,
    required double deductionMm,
    required double handleRatio,
  }) {
    final height = math.max(0.0, heightMm).toDouble();
    final usableLength = math.max(0.0, height - math.max(0.0, deductionMm));
    final normalizedHandleRatio = handleRatio.clamp(0.0, 1.0).toDouble();
    final handleDisplacement = (normalizedHandleRatio - 0.5) * height;
    final lowerCut = ((usableLength / 2.0) + (handleDisplacement / 2.0))
        .clamp(0.0, usableLength)
        .toDouble();
    return <double>[lowerCut, usableLength - lowerCut];
  }

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
      "profil d'angle",
      "profile d'angle",
      'profil angle',
      'profile_angle',
      'زاوية',
    ])) {
      return 'profile_angle';
    }
    if (_textHasAny(originalName, const [
      'cache-caniveau',
      'cache caniveau',
      'cache_caniveau',
    ])) {
      return 'cache_caniveau';
    }
    if (_textHasAny(originalName, const ['caniveau', 'كانيڤو', 'كاني'])) {
      return 'caniveau';
    }
    if (_textHasAny(originalName, const ['cache dormant', 'cache_dormant'])) {
      return 'cache_dormant';
    }
    if (_textHasAny(originalName, const [
      'chch renfort',
      'cache renfort',
      'cache_renfort',
    ])) {
      return 'cache_renfort';
    }
    if (_textHasAny(originalName, const [
      'montant central slim',
      'montant_central_slim',
      'central slim',
    ])) {
      return 'montant_central_slim';
    }
    if (_textHasAny(originalName, const [
      'complement haut',
      'complément haut',
      'complement_haut_base',
      'haut et bas',
    ])) {
      return 'complement_haut_base';
    }
    if (_textHasAny(originalName, const [
      'مكمل الإطار',
      'كومبليمو دورمو',
      'دورمو أجوت',
      'complement dormant',
      'complément dormant',
      'dormant ajoute',
      'dormant ajouté',
      'sliding frame extension',
      'frame extension',
    ])) {
      return 'frame_extension';
    }
    if (_textHasAny(originalName, const ['bardage', 'بارداج', 'بارداش'])) {
      return 'bardage';
    }
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
      'cache-rainure',
      'cache rainure',
      'كاش رينور',
    ])) {
      return 'cache_rainure';
    }
    if (_textHasAny(originalName, const [
      'cache-rail',
      'cache rail',
      'كاش راي',
    ])) {
      return 'cache_rail';
    }
    if (_textHasAny(originalName, const ['bavette', 'بافيت'])) {
      return 'bavette';
    }
    if (_textHasAny(originalName, const ['seuil', 'سوي', 'عتبة'])) {
      return 'seuil';
    }
    if (originalName.trim().toLowerCase() == 'c') return 'c';
    // Legacy catalogue rows named Pattes now belong to Triangle.
    if (_textHasAny(originalName, const ['pattes', 'patte'])) {
      return 'triangle';
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
    // A sash plinthe is also named "بلانت الظلفة".  Check it before the
    // generic sash matcher, otherwise the BOM stores it as a sash and the
    // swap dialog opens the wrong catalogue.
    if (_textHasAny(originalName, const ['plinthe', 'بلانت'])) {
      return 'plant';
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
    if (_textHasAny(originalName, const [
      'bouchon batmo',
      'بوشون باتمو',
      'بوشون الباتمو',
    ])) {
      return 'bouchon_batmo';
    }
    if (_textHasAny(originalName, const [
      'bouchon montant central renforce',
      'bouchon central renforce',
      'غطاء قائم وسطي معزز',
      'أغطية القائم الوسطي المعزز',
    ])) {
      return 'bouchon_montant_central_renforce';
    }
    if (_textHasAny(originalName, const [
      'bouchon montant lateral renforce',
      'bouchon lateral renforce',
      'غطاء قائم جانبي معزز',
      'أغطية القائم الجانبي المعزز',
    ])) {
      return 'bouchon_montant_lateral_renforce';
    }
    if (_textHasAny(originalName, const [
      'bouchon renfort rapporte',
      'bouchon renfort',
      'غطاء عمود تدعيم مستقل',
      'أغطية عمود التدعيم المستقل',
      'أغطية العمود المدعم',
    ])) {
      return 'bouchon_renfort_rapporte';
    }
    if (_textHasAny(originalName, const ['batmo', 'باتمو'])) {
      return 'batmo';
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
    if (_textHasAny(originalName, const [
      'بوشون الكانيفو',
      'بوشون كانيفو',
      'bouchon caniveau',
      'cache caniveau',
    ])) {
      return 'bouchon_caniveau';
    }
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
    if (_textHasAny(originalName, const ['kit', 'كيت'])) return 'kit';
    if (_textHasAny(originalName, const ['clamp', 'clam', 'كلامب', 'كلام'])) {
      return 'clam';
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
    if (_textHasAny(originalName, const [
      'اسبانيوليت',
      'إسبانيوليت',
      'espagnolette',
    ])) {
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
    // PVC recessed handle, before the generic handle words.
    if (_textHasAny(originalName, const ['encastr', 'مدمج'])) {
      return 'poignee_encastree';
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
    if (_textHasAny(originalName, const [
      'الإيكار',
      'ايكار',
      'إيكار',
      'ekar',
      'ikar',
    ])) {
      return 'ekar';
    }
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
    if (_textHasAny(originalName, const ['n245', 'n 245'])) {
      return 'joint centrale';
    }
    if (_textHasAny(originalName, const ['بروس', 'bross', 'brosse'])) {
      return 'Joint bross';
    }
    if (_textHasAny(originalName, const ['bronze', 'برونز'])) {
      return 'joint bronze';
    }
    if (_textHasAny(originalName, const [
      'vitrage',
      'فيتراج',
      'جوان الزجاج',
      'joint glass',
    ])) {
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
      case 'profile_angle':
      case "profil d'angle":
      case "profile d'angle":
        return 'profile_angle';
      case 'caniveau':
        return 'caniveau';
      case 'cache_caniveau':
      case 'cache-caniveau':
      case 'cache caniveau':
        return 'cache_caniveau';
      case 'cache_dormant':
      case 'cache dormant':
        return 'cache_dormant';
      case 'cache_renfort':
      case 'cache renfort':
      case 'chch renfort':
        return 'cache_renfort';
      case 'montant_central_slim':
      case 'montant central slim':
        return 'montant_central_slim';
      case 'complement_haut_base':
      case 'complément haut et bas':
      case 'complement haut et bas':
        return 'complement_haut_base';
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
      case 'c':
        return 'c';
      case 'pattes':
      case 'patte':
        return 'triangle';
      case 'cache_rainure':
      case 'cache-rainure':
      case 'cache rainure':
        return 'cache_rainure';
      case 'cache_rail':
      case 'cache-rail':
      case 'cache rail':
        return 'cache_rail';
      case 'bavette':
        return 'bavette';
      case 'seuil':
        return 'seuil';
      case 'frame_extension':
        return 'frame_extension';
      case '67114':
        return 'reducer';
      case 'side_cover':
        return 'side_cover';
      case 'bardage':
        return 'bardage';
      case 'rail':
        return 'rail';
      case 'batmo':
        return 'batmo';
      case 'bouchon_batmo':
      case 'bouchon batmo':
        return 'bouchon_batmo';
      case 'bouchon_caniveau':
      case 'bouchon caniveau':
        return 'bouchon_caniveau';
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
      case 'bouchon_montant_central_renforce':
        return 'bouchon_montant_central_renforce';
      case 'bouchon_montant_lateral_renforce':
        return 'bouchon_montant_lateral_renforce';
      case 'bouchon_renfort_rapporte':
        return 'bouchon_renfort_rapporte';
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
      case 'kit':
        return 'kit';
      case 'clam':
      case 'clamp':
        return 'clam';
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
      case 'ekar':
        return 'ekar';
      case 'roulette':
        return 'roulette';
      case 'entrematique':
        return 'entrematique';
      case 'poignee_encastree':
        return 'poignee_encastree';
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
      case 'n245':
      case 'n 245':
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

    // Opening battements keep their opening-series role even when the
    // drawing's primary system is sliding.
    if (lower == 'batmo' || lower == 'bouchon_batmo') return false;

    // Réducteure is a sliding-series role. Its selector uses the catalogue
    // code 67114, so it must resolve against the sliding series even inside a
    // mixed opening/sliding drawing.
    if (lower == '67114' ||
        lower == 'reducer' ||
        lower == 'réducteur' ||
        lower == 'réducteure' ||
        lower == 'reducteur') {
      return true;
    }

    // Slim central montant and its 10 cm top/bottom complement only exist
    // in the sliding construction. They must not inherit an opening series
    // merely because the drawing itself is mixed.
    if (lower == 'montant_central_slim' ||
        lower == 'sash_central_slim' ||
        lower == 'complement_haut_base' ||
        lower.contains('montant slim') ||
        lower.contains('مونتوسليم') ||
        lower.contains('complément haut') ||
        lower.contains('complement haut')) {
      return true;
    }

    // 1. هل يحتوي الرسم على أي منطقة/خلية سحاب (سواء النافذة كاملة سحاب أو جزء منها)؟
    final bool hasOpeningZones = window.zones.any(
      (z) =>
          z.content == ZoneContent.singleSash ||
          z.content == ZoneContent.doubleSash,
    );
    final bool isEntireWindowSliding =
        window.usesSlidingPrimaryProfiles && !hasOpeningZones;

    // 2. إذا كانت النافذة بالكامل من نوع سحاب، فجميع قطاعاتها الأساسية تتبع سلسلة السحاب
    if (isEntireWindowSliding) {
      return true;
    }

    // In a mixed drawing, a drawing that contains only sliding zones is still
    // a sliding primary system. The outer frame must use the sliding role and
    // series as well; otherwise a single sliding frame falls back to the
    // opening-frame source.
    if (window.usesSlidingPrimaryProfiles &&
        (lower == 'frame' || lower == 'cadre' || lower == 'إطار')) {
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

    // Generic sash demand belongs to the opening construction. Sliding
    // sashes already use explicit sliding selectors above; their presence
    // must never redirect an opening sash to the sliding catalogue.

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
  static ({int tasso, int ekar}) divisionConnectorQuantities({
    required int divisionPieceCount,
    required bool isPvc,
    required bool hasRegularCaissonAboveWindow,
    required bool selectedFrameHasIntegratedCover,
  }) {
    if (divisionPieceCount <= 0) return (tasso: 0, ekar: 0);
    if (isPvc) {
      return (
        tasso:
            (divisionPieceCount * 2) +
            (hasRegularCaissonAboveWindow && selectedFrameHasIntegratedCover
                ? 2
                : 0),
        ekar: 0,
      );
    }
    return (
      tasso: divisionPieceCount + 1,
      ekar: math.max(0, 2 * (divisionPieceCount - 1)),
    );
  }

  /// Backward-compatible Tasso-only helper used by older callers and tests.
  /// The complete aluminium calculation uses [divisionConnectorQuantities],
  /// because it must return both Tasso and Ekar quantities.
  static int tassoQuantity({
    required int divisionPieceCount,
    required bool isPvc,
    required bool hasRegularCaissonAboveWindow,
    required bool selectedFrameHasIntegratedCover,
  }) {
    final count = math.max(0, divisionPieceCount);
    final pvcCaissonException =
        isPvc &&
        hasRegularCaissonAboveWindow &&
        selectedFrameHasIntegratedCover;

    if (isPvc) {
      return (count * 2) + (pvcCaissonException ? 2 : 0);
    }
    return count * 2;
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
          return (rangeGroup == 0 || rangeGroup == group) &&
              kitRangeContains(range, shutterWeightKg, ranges);
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
  /// A 45-degree miter adds the profile's original, uncut visible face at
  /// every outer corner it reaches. A per-side customised projection affects
  /// the façade drawing only; it must never reduce this cutting allowance.
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

    List<double> bins = []; // Remaining space in each bin
    double totalUsedMeters = 0.0;

    for (double piece in sortedPieces) {
      if (piece <= 0) continue;
      totalUsedMeters += piece;
      double pieceWithWaste = piece + effectiveBladeWaste;
      bool placed = false;
      for (int i = 0; i < bins.length; i++) {
        if (bins[i] >= pieceWithWaste) {
          bins[i] -= pieceWithWaste;
          placed = true;
          break;
        }
      }
      if (!placed) {
        bins.add(barLength - pieceWithWaste);
      }
    }
    // "Actual requirement" means the sum of the pieces really used. Waste
    // and the unusable remainder of the last stock bar never inflate it.
    final exactBars = barLength > 0 ? totalUsedMeters / barLength : 0.0;

    return {
      'exactBars': exactBars,
      'optimizedBars': bins.isEmpty ? 0 : bins.length,
      'usedMeters': totalUsedMeters,
    };
  }

  static String formatProfileUsageDetails({
    required double usedMeters,
    required double barLength,
  }) {
    if (barLength <= 0 || usedMeters <= 0) return '';
    final exactBars = usedMeters / barLength;
    var completeBars = (usedMeters / barLength).floor();
    var remainingCm = ((usedMeters - completeBars * barLength) * 100).round();
    final barCm = (barLength * 100).round();
    if (remainingCm >= barCm) {
      completeBars++;
      remainingCm = 0;
    }
    final detail = remainingCm == 0
        ? '$completeBars بارة كاملة'
        : '$completeBars بارة كاملة + $remainingCm سم من البارة الأخيرة';
    return '(المطلوب الفعلي: ${exactBars.toStringAsFixed(2)} بارة — $detail)';
  }

  static List<BomItem> generateBom(
    WindowModel window,
    Map<String, bool> activeVariants, {
    Map<String, List<Map<String, dynamic>>> kitBundleData = const {},
    Map<String, bool> kitPerLeafMap = const {},
    Map<String, double> kitBundlePrices = const {},
    Map<String, Map<String, dynamic>> kitBundleMetadata = const {},
  }) {
    // Shared by the side-cover rules and the frame-piece calculations below.
    // Keep this in the generateBom scope so nested helpers can use it too.
    final frameRects = window.getFrameRects();

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
      final selectedBase = window.getSlidingBaseFrameSection();
      return selectedBase?.toMap();
    }

    Map<String, dynamic>? slidingOverrideFor(Iterable<String> keys) {
      for (final key in keys) {
        final override = window.getSlidingComponentOverride(key);
        if (override != null) return override;
      }
      return null;
    }

    String? getKitKey(String baseName) {
      final isObKit = baseName == 'System OB' || baseName == 'Demi System OB';
      bool matchesKitMaterial(Map<String, dynamic>? meta, String kitKey) {
        if (!isObKit) return true;
        final rawMat =
            meta?['material_type']?.toString().toLowerCase().trim() ?? '';
        if (rawMat.isEmpty || rawMat == 'all') {
          // Check if name explicitly mentions PVC or Aluminium
          final lower = kitKey.toLowerCase();
          if (window.isPVC) {
            if (lower.contains('aluminium') || lower.contains('alu'))
              return false;
          } else {
            if (lower.contains('pvc')) return false;
          }
          return true;
        }
        if (window.isPVC) {
          return rawMat == 'pvc';
        } else {
          return rawMat == 'aluminium' || rawMat == 'aluminum';
        }
      }

      String? descriptionCode;
      if (baseName == 'System OB' || baseName == 'Demi System OB') {
        descriptionCode = 'OB';
      } else if (baseName == 'Verrou Central') {
        descriptionCode = 'VC';
      }
      if (descriptionCode != null && kitBundleMetadata.isNotEmpty) {
        final coded = kitBundleMetadata.entries.where(
          (entry) =>
              kitHasDescriptionCode(entry.value, descriptionCode!) &&
              matchesKitMaterial(entry.value, entry.key),
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
      List<String>? pieceCutAngles,
      Map<String, dynamic>? overrideMap,
      bool preferOverrideMap = false,
      bool priceByWholeBar = false,
      String? selectorType,
      String? roleKey,
      bool ignoreSavedOverride = false,
    }) {
      // Section overrides always carry the Sections schema. Ignore a legacy
      // Accessories row saved under the same Bouchon Batmo name; otherwise
      // moving that item to Profiles would keep the old accessory id/price.

      final savedOverride = ignoreSavedOverride
          ? null
          : (window.componentOverrides[originalName] ??
                window.componentOverrides[selectorType ?? '']);
      // A saved table row (manual price edit) belongs to one catalogue
      // section. Once the drawing selects another section, for example after
      // a series change, that row must not replace the section id, code or
      // price of the current selection.
      final savedOverrideIsStale =
          savedOverride is Map &&
          !savedProfileOverrideMatchesSection(savedOverride, overrideMap);
      final savedProfileOverride = savedOverride is Map && !savedOverrideIsStale
          ? Map<String, dynamic>.from(savedOverride)
          : null;
      final resolvedSelectorType =
          selectorType ?? _selectorTypeForProfile(originalName);
      final resolvedRoleKey =
          roleKey ?? _roleKeyForProfileSelector(resolvedSelectorType);
      final usesSlidingSeries =
          _profileSelectorUsesSlidingSeries(window, originalName) ||
          _profileSelectorUsesSlidingSeries(window, resolvedSelectorType);
      final configuredOverride = window
          .getConfiguredSectionForRole(
            resolvedRoleKey ?? resolvedSelectorType,
            useSlidingSeries: usesSlidingSeries,
          )
          ?.toMap();
      // إذا كان المستخدم قد عدّل السعر يدوياً في componentOverrides نعطيه الأولوية القصوى
      final selectedOverride = savedProfileOverride != null
          ? (overrideMap != null
                ? (Map<String, dynamic>.from(overrideMap)
                    ..addAll(savedProfileOverride))
                : savedProfileOverride)
          : (overrideMap ?? configuredOverride);
      // A standalone couvre-joint may be shared by the opening and sliding
      // series of one drawing.  Its own `series_id` is therefore the only
      // reliable source for catalogue validation and stock accounting. Using
      // the currently active frame series made a valid cover disappear when
      // that cover belonged to the companion series (most visibly in sliding
      // and mixed drawings).
      int? selectedSectionSeriesId;
      final rawSelectedSeriesId = selectedOverride?['series_id'];
      if (rawSelectedSeriesId is num) {
        selectedSectionSeriesId = rawSelectedSeriesId.toInt();
      } else {
        selectedSectionSeriesId = int.tryParse(
          rawSelectedSeriesId?.toString() ?? '',
        );
      }
      List<double>? multipliedPieces;
      List<String>? multipliedPieceCutAngles;
      if (pieces != null && pieces.isNotEmpty) {
        multipliedPieces = [];
        if (pieceCutAngles != null && pieceCutAngles.length == pieces.length) {
          multipliedPieceCutAngles = [];
        }
        for (int q = 0; q < window.quantity; q++) {
          multipliedPieces.addAll(pieces);
          multipliedPieceCutAngles?.addAll(pieceCutAngles!);
        }
      }
      return _createProfile(
        ignoreSavedOverride || savedOverrideIsStale
            ? const <String, dynamic>{}
            : window.componentOverrides,
        originalName,
        color,
        unit: unit,
        defaultPrice: defaultPrice,
        qty: qty * window.quantity,
        length: length,
        pieces: multipliedPieces,
        pieceCutAngles: multipliedPieceCutAngles,
        overrideMap: selectedOverride,
        preferOverrideMap: selectedOverride != null,
        priceByWholeBar: priceByWholeBar,
        catalogItemId: catalogueId(selectedOverride),
        colorId: catalogueColorId(color),
        // Keep the plinthe override independent from the displayed row name.
        // This prevents a later sash change from replacing the selected
        // plinthe profile during BOM rebuilds.
        overrideKey: resolvedSelectorType == 'plant'
            ? 'بلانت (Plinthe)'
            : originalName,
        selectorCategory: 'profile',
        selectorType: resolvedSelectorType,
        roleKey: resolvedRoleKey,
        sourceSeriesId: resolvedRoleKey == 'side_cover'
            ? (selectedSectionSeriesId ??
                  (usesSlidingSeries
                      ? (window.activeSlidingSeries?.id ??
                            window.activeSeries?.id)
                      : window.activeSeries?.id))
            : (usesSlidingSeries
                  ? (window.activeSlidingSeries?.id ?? window.activeSeries?.id)
                  : window.activeSeries?.id),
        materialType: _materialTypeForProfile(window, resolvedSelectorType),
      );
    }

    BomItem createAccessory(
      String originalName, {
      bool isActive = true,
      String? color,
      int qty = 0,
      List<double>? pieces,
      String? cuttingList,
      String unit = 'حبة',
      bool sliding = false,
      String? roleKeyOverride,
      String? selectorTypeOverride,
    }) {
      final selectorType =
          selectorTypeOverride ?? _selectorTypeForAccessory(originalName);
      final roleKey =
          roleKeyOverride ?? _roleKeyForAccessorySelector(selectorType);
      final overrideItem =
          window.componentOverrides[originalName] ??
          (roleKey != null ? window.componentOverrides[roleKey] : null) ??
          (originalName.contains('براغي الباتمو')
              ? (window.componentOverrides['براغي الباتمو'] ??
                    window.componentOverrides['براغي الباتمو 3.9*50'])
              : null) ??
          (originalName.contains('براغي بوشون باتمو')
              ? window.componentOverrides['براغي بوشون باتمو']
              : null);
      return _createAccessory(
        window.componentOverrides,
        originalName,
        isActive: isActive,
        color: color,
        qty: qty * window.quantity,
        catalogItemId: catalogueId(overrideItem),
        colorId: catalogueColorId(color, accessory: true),
        overrideKey: originalName,
        selectorCategory: 'accessory',
        selectorType: selectorType,
        roleKey: roleKey,
        sourceSeriesId: sliding || window.systemMode == 'sliding'
            ? (window.activeSlidingSeries?.id ?? window.activeSeries?.id)
            : window.activeSeries?.id,
        materialType: sliding
            ? (window.isSlidingPVC ? 'pvc' : 'aluminium')
            : (window.isPVC ? 'pvc' : 'aluminium'),
        pieces: pieces,
        cuttingList: cuttingList,
        unit: unit,
      );
    }

    BomItem createRelatedAccessory(
      String sourceKey,
      String fallbackName, {
      required int qty,
      bool isActive = true,
      bool sliding = false,
    }) {
      final source = window.componentOverrides[sourceKey];
      final related = source is Map
          ? source['linked_accessory'] ?? source['gache_accessory']
          : null;
      if (related is Map) {
        // The parent accessory has already selected this exact catalogue
        // product through an explicit relationship (for example an
        // Espagnolette -> Gâche coulissant relation).  Keep that identity in
        // the BOM so the final rule filter does not discard it merely because
        // the child has a different dialog/section scope from its parent.
        // BomEngine treats this prefix as an authoritative linked row.
        final relatedId = catalogueId(related);
        final linkedKey = relatedId == null
            ? 'linked-accessory:$sourceKey:$fallbackName'
            : 'linked-accessory:$sourceKey:$relatedId';
        final relatedOverrides =
            Map<String, dynamic>.from(window.componentOverrides)
              ..[fallbackName] = Map<String, dynamic>.from(related)
              ..[linkedKey] = Map<String, dynamic>.from(related);
        return _createAccessory(
          relatedOverrides,
          fallbackName,
          isActive: isActive,
          qty: qty * window.quantity,
          catalogItemId: relatedId,
          colorId: catalogueColorId(null, accessory: true),
          overrideKey: linkedKey,
          selectorCategory: 'accessory',
          selectorType: _selectorTypeForAccessory(fallbackName),
          roleKey: _roleKeyForAccessorySelector(
            _selectorTypeForAccessory(fallbackName),
          ),
          sourceSeriesId: sliding || window.systemMode == 'sliding'
              ? (window.activeSlidingSeries?.id ?? window.activeSeries?.id)
              : window.activeSeries?.id,
          materialType: sliding
              ? (window.isSlidingPVC ? 'pvc' : 'aluminium')
              : (window.isPVC ? 'pvc' : 'aluminium'),
        );
      }
      // The fallback still belongs to the same physical system as its parent.
      // Losing this flag made Gâche coulissant resolve against the opening
      // series in mixed drawings and disappear even with an enabled BS90 rule.
      return createAccessory(
        fallbackName,
        isActive: isActive,
        qty: qty,
        sliding: sliding,
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
        colorId:
            int.tryParse('${window.effectiveShutterColor?['id'] ?? ''}') ??
            catalogueColorId(color),
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
        profileCode:
            savedOverride?['code']?.toString() ?? metadata?['code']?.toString(),
        name: bundleName,
        imagePath:
            savedOverride?['image_path']?.toString() ??
            metadata?['image_path']?.toString(),
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
      bool sliding = false,
      String? color,
      double qty = 0,
      String unit = 'بارة',
      double? targetThicknessMm,
      String? overrideKey,
      String? kitGroupName,
      String? roleKeyOverride,
      String? selectorTypeOverride,
    }) {
      final selectorType =
          selectorTypeOverride ?? _selectorTypeForJoint(originalName);
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
        roleKey:
            roleKeyOverride ??
            (isShutterJoint
                ? 'shutter_joint_brosse'
                : _roleKeyForJointSelector(selectorType)),
        targetThicknessMm: targetThicknessMm,
        sourceSeriesId: isShutterJoint
            ? null
            : sliding || window.systemMode == 'sliding'
            ? (window.activeSlidingSeries?.id ?? window.activeSeries?.id)
            : window.activeSeries?.id,
        materialType: isShutterJoint
            ? 'shutter'
            : sliding || window.systemMode == 'sliding'
            ? (window.isSlidingPVC ? 'pvc' : 'aluminium')
            : (window.isPVC ? 'pvc' : 'aluminium'),
        kitGroupName: kitGroupName,
      );
    }

    // The catalogue value is shared by every opening-sash calculation. Add it
    // to both sides of the clear opening (10 mm + 10 mm in the usual case),
    // then distribute that complete cut size between double leaves. It is
    // never replaced by a hard-coded default.
    final double seriesSashOverlap = window.openingSashOverlap;

    List<BomItem> items = [];
    List<String> uniformAngles(List<double> pieces, String angles) =>
        List<String>.filled(pieces.length, angles);

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
    // A drawing may use only profiles explicitly assigned to a role in the
    // selected series. Never recreate a missing profile from legacy section
    // names or types.
    final outerFrameOverride = window.activeFrameOverride;
    final openingSashOverride = window.sashOverride;
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
    // Read the integrated projection from the selected frame, never from a
    // separately selected cover profile.
    final bool hasIntegratedSideCover =
        window.hasSideCovers && integratedFrameCoverWidth > 0;
    bool hasNonIntegratedSideCover =
        window.hasSideCovers &&
        window.canUseStandaloneSideCover &&
        !hasIntegratedSideCover;
    // Both integrated and standalone covers are workshop/drawing details.
    // A standalone cover has its own cutting row and its thickness shortens
    // the frame once for every side where it is installed.
    final bool customSideCoverLayout = window.useCustomSideCoverLayout;

    // A separate couvre-joint must always be read from the exact section that
    // was selected from the shared cover catalog. Do not reuse the width of
    // an integrated cover on the frame: the two profiles can have different
    // widths and thicknesses even in the same drawing.
    AluminumSection? resolveSelectedSeparateSideCover() {
      final candidates = window.availableSideCovers;

      AluminumSection? findInSeries({int? id, String? code, String? name}) {
        if (id != null) {
          for (final section in candidates) {
            if (section.id == id) return section;
          }
        }
        if (code != null && code.trim().isNotEmpty) {
          for (final section in candidates) {
            if (section.code.trim().toLowerCase() ==
                code.trim().toLowerCase()) {
              return section;
            }
          }
        }
        if (name != null && name.trim().isNotEmpty) {
          for (final section in candidates) {
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
      if (!window.canSideUseSideCover(side)) return false;
      if (side == 'bottom' && !window.hasBottomFrame) return false;
      if (frameRects.length > 1) {
        return window.getExposedFrameEdgeSegments().any(
          (edge) =>
              edge.side == side &&
              !window.hiddenSideCoverSegments.contains(edge.side) &&
              !window.removedShutterSides.contains(edge.side),
        );
      }
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

    String? customSideCoverNote({required bool integrated}) {
      if (integrated && !hasIntegratedSideCover) return null;
      if (!integrated && !hasNonIntegratedSideCover) return null;
      // Shared with the fiche de coupe so the table and the PDF always give
      // the workshop the same start/end instruction for each cover piece.
      return window.sideCoverWarningText(
        integrated: integrated,
        fallbackWidth: integrated
            ? integratedFrameCoverWidth
            : separateCoverWidth,
      );
    }

    BomItem appendSideCoverNote(BomItem item, {required bool integrated}) {
      final note = customSideCoverNote(integrated: integrated);
      if (note == null) return item;
      return item.copyWith(productionNote: note);
    }

    Map<String, dynamic>? selectedSeparateCoverMap;
    if (selectedSeparateSideCover != null) {
      selectedSeparateCoverMap = selectedSeparateSideCover.toMap();
      final savedCover = window.sideCoverOverride ??
          (window.componentOverrides['side_cover'] is Map
              ? window.componentOverrides['side_cover']
              : null) ??
          (window.componentOverrides['الغطاء الجانبي (Side Cover)'] is Map
              ? window.componentOverrides['الغطاء الجانبي (Side Cover)']
              : null);
      if (savedCover != null) {
        final priceVal = savedCover['calculated_price'] ??
            savedCover['price_dzd'] ??
            savedCover['price'];
        if (priceVal != null) {
          selectedSeparateCoverMap['calculated_price'] = priceVal;
          selectedSeparateCoverMap['price'] = priceVal;
        }
      }
    } else {
      selectedSeparateCoverMap = window.sideCoverOverride ??
          (window.componentOverrides['side_cover'] is Map
              ? window.componentOverrides['side_cover']
              : null) ??
          (window.componentOverrides['الغطاء الجانبي (Side Cover)'] is Map
              ? window.componentOverrides['الغطاء الجانبي (Side Cover)']
              : null);
    }

    // حساب netHeight: الارتفاع الصافي قبل حساب الإطار
    final double netHeight = (window.hasShutter && !window.isCaissonTunnel)
        ? window.height - window.shutterBoxHeight
        : window.height;

    String colorName = window.selectedDbColor != null
        ? window.selectedDbColor!['name']
        : window.frameColor.toString().split('.').last;
    // An accessory colour is independent from the profile colour.  A missing
    // accessory colour means that the catalogue item is colourless; never
    // make it look coloured by inheriting the selected profile colour.
    final rawAccessoryColorName = window.selectedAccessoryColor?['name']
        ?.toString()
        .trim();
    final String? accessoryColorName =
        rawAccessoryColorName == null || rawAccessoryColorName.isEmpty
        ? null
        : rawAccessoryColorName;
    final String shutterColorName = window.effectiveShutterColor != null
        ? (window.effectiveShutterColor!['name'] ?? colorName).toString()
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
    // PVC recessed handles of opening sashes.
    int encastreeHandles = 0;
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
    // One entry per Cremone/Triangle assembly coming from the drawing.  The
    // handle ratio is kept so the two Triangle cuts follow the real handle
    // position instead of always using the whole window height.
    final triangleDrawingRuns = <Map<String, double>>[];

    void addTriangleDrawingRuns(WindowZone zone, int count) {
      for (var i = 0; i < count; i++) {
        triangleDrawingRuns.add({
          'height_mm': math.max(0.0, zone.boundary.height).toDouble(),
          'width_mm': math.max(0.0, zone.boundary.width).toDouble(),
          'handle_ratio': (zone.handlePositionRatio ?? 0.5)
              .clamp(0.0, 1.0)
              .toDouble(),
        });
      }
    }

    List<double> slidingChicanePieces = [];
    List<double> slidingChicaneRenforceePieces = [];
    List<double> slidingIndependentRenfortPieces = [];
    List<double> slidingRailPieces = [];
    List<double> slidingMonorailPieces = [];
    // Keep the extension cuts with the sliding zone that requested them.
    // In a mixed drawing the outer frame is held in `framePieces`, not in
    // `slidingOuterFramePieces`; counting only a global copy number therefore
    // made a valid extension vanish from the quantity table.
    List<double> slidingFrameExtensionPieces = [];
    List<String> slidingFrameExtensionAngles = [];
    List<double> internalSlidingSideCoverPieces = [];
    int slidingTotalRoulettes = 0;
    int slidingTotalEspagnolettes = 0;
    int slidingTotalHandles = 0;
    // Handles and espagnolettes by handle type, for windows whose handle
    // places were chosen one by one (WindowZone.slidingHandleTypes).
    final slidingHandlesByType = <String, int>{};
    final slidingEspagnolettesByType = <String, int>{};
    int slidingTotalKits = 0;
    int slidingTotalReinforcedLateralKits = 0;
    int slidingTotalReinforcedCentralKits = 0;
    int slidingTotalGacheCoulissant = 0;
    double slidingTotalJointBrosse = 0.0;
    double pvcJointBrosseSum = 0.0;
    Map<String, double> slidingGlassJoints = {};
    final openingGlassJoints = <String, double>{};
    double fittedSimplePerimeter = 0;
    double fittedDoublePerimeter = 0;
    double slidingBourrageTargetThickness = 0.0;

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
            addTriangleDrawingRuns(zone, 1);
          } else if (zone.lockType == LockType.clef) {
            keyHandles += 1;
            keyLocks += 1;
            doorCanons += 1;
            addTriangleDrawingRuns(zone, 1);
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
            } else if (window.isPVC && zone.useEncastreeHandle) {
              encastreeHandles += handleCount;
            } else if (zone.useOctoHandle) {
              octoHandles += handleCount;
            } else {
              totalHandles += handleCount;
              addTriangleDrawingRuns(zone, handleCount);
            }
          } else {
            if (zone.lockType == LockType.point) {
              pointLocks += 1;
            } else if (zone.usePvcHandleOnAlu && !usesWindowHandleOnDoor) {
              pvcHandlesOnAlu += 1;
            } else if (window.isPVC && zone.useEncastreeHandle) {
              encastreeHandles += 1;
            } else if (zone.useOctoHandle) {
              octoHandles += 1;
            } else {
              totalHandles += 1;
              addTriangleDrawingRuns(zone, 1);
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

        // Per leaf, from the same layout the drawing shows (automatic or
        // placed by hand). With OB the handle leaf's hinges come in its kit.
        final usesOb = window.effectiveUseSystemOB || window.effectiveUseDemiOB;
        final obLeaf = window.isHandleLeaf(zone, 0) ? 0 : 1;
        for (var leaf = 0; leaf < sashes; leaf++) {
          if (usesOb && leaf == obLeaf) continue;
          totalHinges += window.hingeCountForLeaf(zone, leaf);
        }

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

    final bool useCremone = !window.isPVC && window.systemMode != 'sliding';
    int cremoneQty = 0;
    if (useCremone) {
      cremoneQty = totalHandles;
      // Nested sash handles are included in totalHandles but do not have an
      // independent WindowZone boundary. Use the drawing height as a safe
      // fallback for those legacy/nested cases, keeping the count aligned.
      while (triangleDrawingRuns.length < cremoneQty) {
        triangleDrawingRuns.add({
          'height_mm': math.max(0.0, window.height.toDouble()).toDouble(),
          'width_mm': math.max(0.0, window.width.toDouble()).toDouble(),
          'handle_ratio': 0.5,
        });
      }
      if (triangleDrawingRuns.length > cremoneQty) {
        triangleDrawingRuns.removeRange(cremoneQty, triangleDrawingRuns.length);
      }
      if (!window.componentOverrides.containsKey('مقبض نافذة (Poignée)') &&
          !window.componentOverrides.containsKey('المقبض (Handle)') &&
          !window.componentOverrides.containsKey(
            'مقبض نافذة (Poignée Fenêtre)',
          )) {
        totalHandles = 0;
      }
    }

    int configuredGacheCount(Iterable<String> keys) {
      for (final key in keys) {
        final override = window.componentOverrides[key];
        if (override is! Map) continue;
        final value =
            override['linked_accessory_count'] ?? override['gache_count'];
        final count = value is num
            ? value.toInt()
            : int.tryParse(value?.toString() ?? '') ?? 0;
        if (count > 0) return count;
      }
      return 1;
    }

    final gacheQtyPerDoubleSash = configuredGacheCount([
      'إسبانيوليت (Espagnolette)',
      'اسبانيولات المنزلق (Espagnolette)',
    ]);
    final activeSeriesName =
        '${window.activeSeries?.name ?? ''} '
                '${window.activeSeries?.type ?? ''} '
                '${window.activeSlidingSeries?.name ?? ''} '
                '${window.activeSlidingSeries?.type ?? ''} '
                '${window.system?.name ?? ''}'
            .toLowerCase();
    final isTprSeries =
        activeSeriesName.contains('tpr') ||
        activeSeriesName.contains('tpi') ||
        activeSeriesName.contains('hps');

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
            final rangeGroup =
                ((r['compatibility_group'] as num?)?.toInt() ?? 0).clamp(0, 2);
            final groupMatches =
                !isWeight ||
                selectedCompatibilityGroup == null ||
                ((rangeGroup == 0 || rangeGroup == selectedCompatibilityGroup));
            if (groupMatches &&
                kitRangeContains(r, dimValue, sortedRanges)) {
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
    List<String> framePieceAngles = [];
    List<double> slidingOuterFramePieces = [];
    List<String> slidingOuterFramePieceAngles = [];
    final frameCutsByRect = <Rect, List<double>>{};
    final customFrameSidePieces = <String, List<double>>{};
    final customFrameSideAngles = <String, List<String>>{};
    final customFrameSideProfiles = <String, Map<String, dynamic>>{};
    final customFrameSideNames = <String, Set<String>>{};
    List<double> renfortFramePieces = [];
    List<double> fixedPlinthePieces = [];

    double renfortFrameDeduction = 140.0;
    if (outerFrameOverride != null) {
      renfortFrameDeduction =
          (outerFrameOverride['renfort_deduction'] as num?)?.toDouble() ??
          140.0;
    }

    for (final r in frameRects) {
      // A complete window is cut from the real drawing dimensions.  For a
      // multi-frame drawing, retain each group's own dimensions while using
      // the same cover formula.
      final isCompleteFrame = frameRects.length == 1;
      // Use the model's physical-frame classifier. The former inset-boundary
      // test rejected zones whose stored boundary includes the outer frame,
      // so a mixed drawing could put the Coulissant cuts into the opening
      // Dormant item and make its own frame disappear from the BOM.
      final useSlidingOuterFrame = window.frameUsesSlidingSeries(r);
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

      final frameCuts = window.hasBottomFrameForRect(r)
          ? <double>[wPiece, wPiece, hPiece, hPiece]
          : <double>[wPiece, hPiece, hPiece];
      frameCutsByRect[r] = frameCuts;

      void addFrameSide(String side, double length, String angles) {
        final override = window.frameSideOverrideForRect(r, side);
        final baseId = (window.frameSectionForRect(r)?.id)?.toString();
        final overrideId = override?['id']?.toString();
        if (override == null || overrideId == null || overrideId == baseId) {
          targetFramePieces.add(length);
          (useSlidingOuterFrame
                  ? slidingOuterFramePieceAngles
                  : framePieceAngles)
              .add(angles);
          return;
        }
        final rawCustomCover = override['couvre_joint_width'];
        final customCoverWidth = rawCustomCover is num
            ? rawCustomCover.toDouble()
            : double.tryParse(rawCustomCover?.toString() ?? '') ?? 0.0;
        final adjustedLength = math.max(
          0.0,
          length +
              ((customCoverWidth > 0 ? customCoverWidth * 2 : 0.0) -
                      integratedCoverCutExtension) /
                  1000.0,
        );
        final key =
            '${useSlidingOuterFrame ? 'sliding' : 'opening'}:$overrideId';
        customFrameSideProfiles[key] = override;
        customFrameSidePieces
            .putIfAbsent(key, () => <double>[])
            .add(adjustedLength);
        customFrameSideAngles.putIfAbsent(key, () => <String>[]).add(angles);
        customFrameSideNames.putIfAbsent(key, () => <String>{}).add(side);
      }

      final hasBottom = window.hasBottomFrameForRect(r);
      addFrameSide('top', wPiece, '45/45');
      if (hasBottom) addFrameSide('bottom', wPiece, '45/45');
      addFrameSide('left', hPiece, hasBottom ? '45/45' : '45/90');
      addFrameSide('right', hPiece, hasBottom ? '45/45' : '45/90');

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
        if (length > 0) {
          final usesPlinthe =
              window.hasFramePlintheBottom || zone.hasSashPlintheBottom;
          if (usesPlinthe) {
            fixedPlinthePieces.add(length / 1000.0);
          } else {
            framePieces.add(length / 1000.0);
            framePieceAngles.add('90/90');
          }
        }
      }
    }

    final angleJunctionFramePieces = <String, List<double>>{};
    final angleJunctionFrameAngles = <String, List<String>>{};
    final angleJunctionFrames = <String, AluminumSection>{};
    final angleJunctionSliding = <String, bool>{};
    if (window.usesProfileAngle &&
        window.hasSideCovers &&
        !window.isIntegratedFrame) {
      void substituteJunctionSide(Rect frame) {
        final currentFrame = window.frameSectionForRect(frame);
        if (currentFrame == null) return;
        final sliding = window.frameUsesSlidingSeries(frame);
        final compatible = window.findCompatibleNoCoverFrame(
          currentFrame: currentFrame,
          sliding: sliding,
        );
        // A null result means that the selected frame is already explicitly
        // compatible with the tube carré; it must remain unchanged.
        if (compatible == null) return;

        final cuts = frameCutsByRect[frame];
        if (cuts == null || cuts.length < 3) return;
        final verticalCut = cuts.last;
        final sourcePieces = sliding ? slidingOuterFramePieces : framePieces;
        final sourceAngles = sliding
            ? slidingOuterFramePieceAngles
            : framePieceAngles;
        final sourceIndex = sourcePieces.indexOf(verticalCut);
        if (sourceIndex < 0) return;
        sourcePieces.removeAt(sourceIndex);
        final removedAngles = sourceAngles.removeAt(sourceIndex);
        final itemKey = '${sliding ? 'sliding' : 'opening'}:${compatible.id}';
        angleJunctionFrames[itemKey] = compatible;
        angleJunctionSliding[itemKey] = sliding;
        angleJunctionFramePieces
            .putIfAbsent(itemKey, () => <double>[])
            .add(verticalCut);
        angleJunctionFrameAngles
            .putIfAbsent(itemKey, () => <String>[])
            .add(removedAngles);
      }

      final junctions = window.getAdjacentFrameJunctions();
      for (final junction in junctions) {
        if (!window.activeProfileAngleJunctions.contains(junction.index)) {
          continue;
        }
        // Only the two faces that touch the tube carré are changed: the
        // right jamb of the first frame and the left jamb of the second.
        substituteJunctionSide(junction.firstFrame);
        substituteJunctionSide(junction.secondFrame);
      }

      // The legacy outer-edge mode has no frame-to-frame junction. Apply it
      // to the corresponding outer jambs only.
      if (junctions.isEmpty && frameRects.isNotEmpty) {
        if (window.profileAngleMode == 2 || window.profileAngleMode == 3) {
          substituteJunctionSide(frameRects.first);
        }
        if (window.profileAngleMode == 1 || window.profileAngleMode == 3) {
          substituteJunctionSide(frameRects.last);
        }
      }
    }

    if (framePieces.isNotEmpty) {
      items.add(
        appendSideCoverNote(
          createProfile(
            'الإطار (Frame)',
            colorName,
            pieces: framePieces,
            pieceCutAngles: framePieceAngles,
            unit: 'قطاع',
            overrideMap: outerFrameOverride,
            // The frame selected in the drawing is authoritative. A stale table
            // value from an earlier selection must not replace it.
            preferOverrideMap: true,
          ),
          integrated: true,
        ),
      );
    }

    for (final entry in customFrameSidePieces.entries) {
      final override = customFrameSideProfiles[entry.key];
      if (override == null || entry.value.isEmpty) continue;
      final sideLabels = customFrameSideNames[entry.key] ?? const <String>{};
      String sideName(String side) => switch (side) {
        'top' => 'علوي',
        'right' => 'يمين',
        'bottom' => 'سفلي',
        'left' => 'يسار',
        _ => side,
      };
      final label = sideLabels.map(sideName).join(' + ');
      items.add(
        createProfile(
          'إطار جهة $label (Frame side)',
          colorName,
          pieces: entry.value,
          pieceCutAngles: customFrameSideAngles[entry.key],
          unit: 'قطاع',
          overrideMap: override,
          preferOverrideMap: true,
        ),
      );
    }

    for (final entry in angleJunctionFramePieces.entries) {
      final angleJunctionFrame = angleJunctionFrames[entry.key];
      if (angleJunctionFrame == null || entry.value.isEmpty) continue;
      final sliding = angleJunctionSliding[entry.key] == true;
      items.add(
        createProfile(
          sliding
              ? 'إطار منزلق لجهة بروفيل الزاوية (Cadre coulissant côté angle)'
              : 'إطار فتح لجهة بروفيل الزاوية (Dormant côté angle)',
          colorName,
          pieces: entry.value,
          pieceCutAngles: angleJunctionFrameAngles[entry.key],
          unit: 'قطاع',
          overrideMap: angleJunctionFrame.toMap(),
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
          pieceCutAngles: slidingOuterFramePieceAngles,
          unit: 'قطاع',
          overrideMap: getSlidingFrameSection(),
          preferOverrideMap: true,
        ),
      );
    }

    // Keep the series identity of each physical frame throughout costing.
    for (final sliding in [false, true]) {
      final scopedFrames = frameRects.where(
        (frame) => window.frameUsesSlidingSeries(frame) == sliding,
      );
      for (final role in ['cache_dormant', 'seuil', 'cache_rail']) {
        if (role == 'cache_rail' && !sliding) continue;
        if (!window.usesFrameRole(role, sliding: sliding)) continue;
        final section = window.getConfiguredSectionForRole(
          role,
          useSlidingSeries: sliding,
        );
        if (section == null) continue;
        final pieces = <double>[];
        final pieceAngles = <String>[];
        for (final frame in scopedFrames) {
          if (role == 'cache_dormant') {
            // Reuse the actual frame cuts, including deductions and welding.
            final frameCuts = frameCutsByRect[frame] ?? const <double>[];
            pieces.addAll(frameCuts);
            final hasBottom = window.hasBottomFrameForRect(frame);
            pieceAngles.addAll(
              hasBottom
                  ? List<String>.filled(frameCuts.length, '45/45')
                  : const <String>['45/45', '45/90', '45/90'],
            );
          } else if (role == 'seuil') {
            final count = sliding
                ? window.slidingSeuilPieceCount(
                    window.slidingTrackCountForRect(frame),
                  )
                : 1;
            pieces.addAll(List.filled(count, frame.width / 1000.0));
            pieceAngles.addAll(List<String>.filled(count, '90/90'));
          } else {
            final counts = window.cacheRailCountsForRect(frame);
            final count = counts.$1 + counts.$2;
            pieces.addAll(List.filled(count, frame.height / 1000.0));
            pieceAngles.addAll(List<String>.filled(count, '90/90'));
          }
        }
        if (pieces.isEmpty) continue;
        final label = role == 'cache_dormant'
            ? 'Cache dormant'
            : role == 'seuil'
            ? 'Seuil'
            : 'Cache-rail';
        final scope = sliding ? 'Coulissant' : 'Ouvrant';
        items.add(
          createProfile(
            '$label ($scope)',
            colorName,
            pieces: pieces,
            pieceCutAngles: pieceAngles,
            overrideMap: section.toMap(),
            preferOverrideMap: true,
            selectorType: role,
            roleKey: role,
          ).copyWith(
            sourceSeriesId:
                (sliding ? window.activeSlidingSeries : window.activeSeries)
                    ?.id,
            materialType: (sliding ? window.isSlidingPVC : window.isPVC)
                ? 'pvc'
                : 'aluminium',
          ),
        );
      }
    }

    // Cache-rainure closes the seam between two independent outer frames.
    // Each eligible seam receives two equal cuts: one on the inside and one
    // on the outside. Contacts already exclude frames with an integrated
    // cover or frames that do not accept a separate cover.
    final cacheRainurePieces = <bool, List<double>>{
      false: <double>[],
      true: <double>[],
    };
    for (final contact in window.getCacheRainureContacts()) {
      final lengthM = contact.length / 1000.0;
      if (lengthM <= 0) continue;
      // One cut per face.  The two faces can belong to different compatible
      // series, so do not force both cuts onto the first frame's profile.
      cacheRainurePieces[contact.insideUsesSlidingSeries]!.add(lengthM);
      cacheRainurePieces[contact.outsideUsesSlidingSeries]!.add(lengthM);
    }
    for (final segment in window.getCadreDoubleRainureSegments()) {
      final lengthM = segment.length / 1000.0;
      if (lengthM <= 0) continue;
      // Inside + outside cuts for Cadre double mullion
      cacheRainurePieces[segment.usesSlidingSeries]!.add(lengthM);
      cacheRainurePieces[segment.usesSlidingSeries]!.add(lengthM);
    }
    for (final sliding in [false, true]) {
      final pieces = cacheRainurePieces[sliding]!;
      if (pieces.isEmpty) continue;
      final section =
          window.getConfiguredSectionForRole(
            'cache_rainure',
            useSlidingSeries: sliding,
          ) ??
          (sliding
              ? window.getSlidingSectionByType('cache_rainure')
              : window.getSectionByType('cache_rainure'));
      if (section == null) continue;
      final baseItem = createProfile(
        'Cache-rainure (${sliding ? 'Coulissant' : 'Ouvrant'})',
        colorName,
        pieces: pieces,
        pieceCutAngles: uniformAngles(pieces, '90/90'),
        unit: 'قطاع',
        overrideMap: section.toMap(),
        preferOverrideMap: true,
        selectorType: 'cache_rainure',
        roleKey: 'cache_rainure',
      );
      final cutPiecesText =
          baseItem.cuttingList ??
          'قطع القص: ${pieces.map((p) => '${(p * 1000).round()} مم').join(' ، ')}';
      items.add(
        baseItem.copyWith(
          sourceSeriesId:
              (sliding ? window.activeSlidingSeries : window.activeSeries)?.id,
          materialType: (sliding ? window.isSlidingPVC : window.isPVC)
              ? 'pvc'
              : 'aluminium',
          cuttingList: '$cutPiecesText (داخل + خارج)',
        ),
      );
    }

    // Bavette is an optional cover profile. Mode 1 follows the lower edge;
    // mode 2 follows all four edges of every physical frame.
    if (window.usesBavette) {
      final bavettePieces = <bool, List<double>>{
        false: <double>[],
        true: <double>[],
      };
      for (final frame in frameRects) {
        final sliding = window.frameUsesSlidingSeries(frame);
        final pieces = bavettePieces[sliding]!;
        pieces.add(frame.width / 1000.0);
        if (window.optionalBavetteMode == 2) {
          pieces.add(frame.width / 1000.0);
          pieces.add(frame.height / 1000.0);
          pieces.add(frame.height / 1000.0);
        }
      }
      for (final sliding in [false, true]) {
        final pieces = bavettePieces[sliding]!;
        if (pieces.isEmpty) continue;
        final section = window.getConfiguredSectionForRole(
          'bavette',
          useSlidingSeries: sliding,
        );
        if (section == null) continue;
        final scope = sliding ? 'Coulissant' : 'Ouvrant';
        items.add(
          createProfile(
            'Bavette ($scope)',
            colorName,
            pieces: pieces,
            unit: 'قطاع',
            overrideMap: section.toMap(),
            preferOverrideMap: true,
            selectorType: 'bavette',
            roleKey: 'bavette',
          ).copyWith(
            sourceSeriesId:
                (sliding ? window.activeSlidingSeries : window.activeSeries)
                    ?.id,
            materialType: (sliding ? window.isSlidingPVC : window.isPVC)
                ? 'pvc'
                : 'aluminium',
            cuttingList: window.optionalBavetteMode == 1
                ? 'جهة سفلية فقط'
                : 'الجهات الأربع',
          ),
        );
      }
    }

    if (window.usesProfileAngle) {
      final sliding = window.systemMode == 'sliding';
      final section =
          window.getConfiguredSectionForRole(
            'profile_angle',
            useSlidingSeries: sliding,
          ) ??
          window.getConfiguredSectionForRole(
            'profile_angle',
            useSlidingSeries: !sliding,
          ) ??
          window.getSectionByType('profile_angle') ??
          window.getSlidingSectionByType('profile_angle') ??
          window.getSectionByType('tube_carre') ??
          window.getSlidingSectionByType('tube_carre');
      final override =
          slidingOverrideFor([
            "بروفيل الزاوية 90° (Profil d'angle)",
            "بروفيل الزاوية (Profil d'angle)",
            'profile_angle',
            "profil d'angle",
            'tube_carre',
          ]) ??
          section?.toMap();

      final anglePieces = <double>[];
      final labels = <String>[];

      // Multi-frame junctions
      final junctions = window.getAdjacentFrameJunctions();
      final activeJunctions = window.activeProfileAngleJunctions;
      for (final j in junctions) {
        if (activeJunctions.contains(j.index)) {
          anglePieces.add(j.height / 1000.0);
          labels.add(j.label);
        }
      }

      // Outer edge / single-frame mode
      if (window.profileAngleMode > 0) {
        final int outerCount = window.profileAngleMode == 3 ? 2 : 1;
        for (int i = 0; i < outerCount; i++) {
          anglePieces.add(window.height / 1000.0);
        }
        final outerLabel = window.profileAngleMode == 1
            ? 'يمين (90°)'
            : (window.profileAngleMode == 2 ? 'يسار (90°)' : 'الجهتين (90°)');
        labels.add(outerLabel);
      }

      if (anglePieces.isNotEmpty) {
        final cuttingListLabel = labels.join(' + ');
        items.add(
          createProfile(
            "بروفيل الزاوية 90° (Profil d'angle / Tube carré)",
            colorName,
            pieces: anglePieces,
            pieceCutAngles: uniformAngles(anglePieces, '90/90'),
            unit: 'قطاع',
            overrideMap: override,
            preferOverrideMap: true,
            selectorType: 'profile_angle',
            roleKey: 'profile_angle',
          ).copyWith(
            sourceSeriesId:
                (sliding ? window.activeSlidingSeries : window.activeSeries)
                    ?.id,
            materialType: (sliding ? window.isSlidingPVC : window.isPVC)
                ? 'pvc'
                : 'aluminium',
            cuttingList: cuttingListLabel,
          ),
        );
      }
    }

    // Caniveau is an outside-only channel fixed under an existing lower
    // frame. Its upper cache follows the same width, while two Bouchons close
    // the left and right ends of every physical frame using the channel.
    final caniveauPieces = <bool, List<double>>{
      false: <double>[],
      true: <double>[],
    };
    final cacheCaniveauPieces = <bool, List<double>>{
      false: <double>[],
      true: <double>[],
    };
    final caniveauCapCounts = <bool, int>{false: 0, true: 0};
    for (final frame in frameRects) {
      if (!window.usesCaniveauForRect(frame)) continue;
      final sliding = window.frameUsesSlidingSeries(frame);
      final length = frame.width / 1000.0;
      caniveauPieces[sliding]!.add(length);
      cacheCaniveauPieces[sliding]!.add(length);
      caniveauCapCounts[sliding] = caniveauCapCounts[sliding]! + 2;
    }
    for (final sliding in [false, true]) {
      final channel = caniveauPieces[sliding]!;
      if (channel.isEmpty) continue;
      final caniveau = window.getConfiguredSectionForRole(
        'caniveau',
        useSlidingSeries: sliding,
      );
      final cache = window.getConfiguredSectionForRole(
        'cache_caniveau',
        useSlidingSeries: sliding,
      );
      // [usesCaniveauForRect] guarantees both sections; retain this guard for
      // restored drawings whose old configuration is incomplete.
      if (caniveau == null || cache == null) continue;
      final scope = sliding ? 'Coulissant' : 'Ouvrant';
      items.add(
        createProfile(
          'Caniveau ($scope)',
          colorName,
          pieces: channel,
          pieceCutAngles: uniformAngles(channel, '90/90'),
          unit: 'قطاع',
          overrideMap: caniveau.toMap(),
          preferOverrideMap: true,
          selectorType: 'caniveau',
          roleKey: 'caniveau',
        ).copyWith(
          sourceSeriesId:
              (sliding ? window.activeSlidingSeries : window.activeSeries)?.id,
          materialType: (sliding ? window.isSlidingPVC : window.isPVC)
              ? 'pvc'
              : 'aluminium',
          cuttingList: 'جهة خارجية أسفل الإطار',
        ),
      );
      items.add(
        createProfile(
          'Cache-caniveau ($scope)',
          colorName,
          pieces: cacheCaniveauPieces[sliding],
          pieceCutAngles: uniformAngles(cacheCaniveauPieces[sliding]!, '90/90'),
          unit: 'قطاع',
          overrideMap: cache.toMap(),
          preferOverrideMap: true,
          selectorType: 'cache_caniveau',
          roleKey: 'cache_caniveau',
        ).copyWith(
          sourceSeriesId:
              (sliding ? window.activeSlidingSeries : window.activeSeries)?.id,
          materialType: (sliding ? window.isSlidingPVC : window.isPVC)
              ? 'pvc'
              : 'aluminium',
        ),
      );
      items.add(
        createAccessory(
          'بوشون الكانيفو (Bouchon Caniveau)',
          color: accessoryColorName,
          qty: caniveauCapCounts[sliding]!,
          sliding: sliding,
          roleKeyOverride: 'bouchon_caniveau',
          selectorTypeOverride: 'bouchon_caniveau',
        ),
      );
    }

    if (window.isPVC) {
      items.add(
        createProfile(
          'حديد الإطار (Renfort Frame)',
          null,
          pieces: renfortFramePieces,
          pieceCutAngles: uniformAngles(renfortFramePieces, '90/90'),
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
      List<String> sideCoverAngles = [];

      void addSideCoverPiece(
        double lengthMeters, {
        required bool startMiter,
        required bool endMiter,
      }) {
        sideCoverPieces.add(lengthMeters);
        sideCoverAngles.add('${startMiter ? 45 : 90}/${endMiter ? 45 : 90}');
      }

      if (customSideCoverLayout) {
        if (frameRects.length > 1) {
          // A customised cover still follows the real outside perimeter of
          // every physical frame. The old branch used the four global side
          // lengths, so a partial upper frame or a recessed corner was
          // missing from the cover quantity even when it was drawn.
          final exposedEdges = window.getExposedFrameEdgeSegments();
          bool isHorizontal(String side) => side == 'top' || side == 'bottom';

          bool isEndpointAt(FrameEdgeSegment edge, double x, double y) {
            final startX = isHorizontal(edge.side)
                ? edge.start
                : edge.coordinate;
            final startY = isHorizontal(edge.side)
                ? edge.coordinate
                : edge.start;
            final endX = isHorizontal(edge.side) ? edge.end : edge.coordinate;
            final endY = isHorizontal(edge.side) ? edge.coordinate : edge.end;
            return (startX - x).abs() <= 2.0 && (startY - y).abs() <= 2.0 ||
                (endX - x).abs() <= 2.0 && (endY - y).abs() <= 2.0;
          }

          bool isEdgeAllowed(FrameEdgeSegment edge) {
            if (window.hiddenSideCoverSegments.contains(edge.side) ||
                window.removedShutterSides.contains(edge.side) ||
                (edge.side == 'bottom' && !window.hasBottomFrame) ||
                !window.isSideCoverSegmentEnabled(edge.side)) {
              return false;
            }
            if (edge.frameRect != null &&
                !window.frameSideAllowsSideCover(edge.frameRect!, edge.side)) {
              return false;
            }
            return true;
          }

          bool hasMiterAt(FrameEdgeSegment edge, double axis) {
            final x = isHorizontal(edge.side) ? axis : edge.coordinate;
            final y = isHorizontal(edge.side) ? edge.coordinate : axis;
            return exposedEdges.any(
              (other) =>
                  isEdgeAllowed(other) &&
                  isHorizontal(other.side) != isHorizontal(edge.side) &&
                  isEndpointAt(other, x, y),
            );
          }

          for (final edge in exposedEdges.where(isEdgeAllowed)) {
            for (final segment in window.effectiveSideCoverSegments.where(
              (segment) => segment.side == edge.side,
            )) {
              final start = math.max(edge.start, segment.startOffset);
              final end = math.min(edge.end, segment.endOffset);
              if (end <= start) continue;
              final miterCount =
                  ((start - edge.start).abs() <= 2.0 && hasMiterAt(edge, start)
                      ? 1
                      : 0) +
                  ((end - edge.end).abs() <= 2.0 && hasMiterAt(edge, end)
                      ? 1
                      : 0);
              final startMiter =
                  (start - edge.start).abs() <= 2.0 && hasMiterAt(edge, start);
              final endMiter =
                  (end - edge.end).abs() <= 2.0 && hasMiterAt(edge, end);
              addSideCoverPiece(
                ((end - start) +
                        separateCoverWidth * miterCount +
                        pvcWeldingAllowance) /
                    1000.0,
                startMiter: startMiter,
                endMiter: endMiter,
              );
            }
          }
        } else {
          // The input length is the covered span on the frame. For a
          // standalone custom piece, add its visible width for each outer
          // corner it reaches because every outside corner is cut at 45
          // degrees. A piece whose ends are both in the middle gets no
          // visible-width extension.
          for (final segment in window.effectiveSideCoverSegments) {
            if (segment.side == 'bottom' && !window.hasBottomFrame) continue;
            final sideLength = window.sideCoverSideLength(segment.side);
            if (sideLength <= 0) continue;
            final start = segment.startOffset.clamp(0.0, sideLength).toDouble();
            final end = segment.endOffset.clamp(0.0, sideLength).toDouble();
            if (end <= start) continue;
            final cutLength = standaloneSideCoverSegmentCutLength(
              sideLength: sideLength,
              start: start,
              end: end,
              // The customised projection controls what remains visible on
              // the façade. The miter allowance always comes from the full,
              // uncut face of the selected cover profile.
              visibleWidth: separateCoverWidth,
              weldingAllowance: pvcWeldingAllowance,
            );
            final reachesStart = start <= 0.01;
            final reachesEnd = (end - sideLength).abs() <= 0.01;
            final verticalSide =
                segment.side == 'left' || segment.side == 'right';
            final startMiter = reachesStart;
            final endMiter =
                reachesEnd && (!verticalSide || window.hasBottomFrame);
            addSideCoverPiece(
              cutLength / 1000.0,
              startMiter: startMiter,
              endMiter: endMiter,
            );
          }
        }
      } else {
        final double w = separateCoverWidth;
        // The standalone couvre-joint is cut using its visible width: that
        // width is included at both ends. PVC also needs 5 mm for welding;
        // aluminium does not. An integrated cover never enters this branch.
        if (frameRects.length > 1) {
          // The cover is one continuous perimeter around the union of all
          // touching physical frames, not one rectangle per frame.
          final exposedEdges = window.getExposedFrameEdgeSegments();
          bool isHorizontal(String side) => side == 'top' || side == 'bottom';

          bool isEdgeAllowed(FrameEdgeSegment edge) {
            if (window.hiddenSideCoverSegments.contains(edge.side) ||
                window.removedShutterSides.contains(edge.side) ||
                (edge.side == 'bottom' && !window.hasBottomFrame) ||
                !window.isSideCoverSegmentEnabled(edge.side)) {
              return false;
            }
            if (edge.frameRect != null &&
                !window.frameSideAllowsSideCover(edge.frameRect!, edge.side)) {
              return false;
            }
            return true;
          }

          final activeEdges = exposedEdges.where(isEdgeAllowed).toList();

          bool hasActiveMiterAt(FrameEdgeSegment edge, double axis) {
            final x = isHorizontal(edge.side) ? axis : edge.coordinate;
            final y = isHorizontal(edge.side) ? edge.coordinate : axis;
            return activeEdges.any(
              (other) =>
                  isHorizontal(other.side) != isHorizontal(edge.side) &&
                  (((isHorizontal(other.side)
                                          ? other.start
                                          : other.coordinate) -
                                      x)
                                  .abs() <=
                              5.0 &&
                          ((isHorizontal(other.side)
                                          ? other.coordinate
                                          : other.start) -
                                      y)
                                  .abs() <=
                              5.0 ||
                      ((isHorizontal(other.side)
                                          ? other.end
                                          : other.coordinate) -
                                      x)
                                  .abs() <=
                              5.0 &&
                          ((isHorizontal(other.side)
                                          ? other.coordinate
                                          : other.end) -
                                      y)
                                  .abs() <=
                              5.0),
            );
          }

          for (final edge in activeEdges) {
            final miterCount =
                (hasActiveMiterAt(edge, edge.start) ? 1 : 0) +
                (hasActiveMiterAt(edge, edge.end) ? 1 : 0);
            addSideCoverPiece(
              (edge.length + (miterCount * w) + pvcWeldingAllowance) / 1000.0,
              startMiter: hasActiveMiterAt(edge, edge.start),
              endMiter: hasActiveMiterAt(edge, edge.end),
            );
          }
        } else {
          final leftMiterCount =
              (hasSeparateCoverTop ? 1 : 0) + (hasSeparateCoverBottom ? 1 : 0);
          final rightMiterCount =
              (hasSeparateCoverTop ? 1 : 0) + (hasSeparateCoverBottom ? 1 : 0);
          final topMiterCount =
              (hasSeparateCoverLeft ? 1 : 0) + (hasSeparateCoverRight ? 1 : 0);
          final bottomMiterCount =
              (hasSeparateCoverLeft ? 1 : 0) + (hasSeparateCoverRight ? 1 : 0);

          if (hasSeparateCoverLeft) {
            addSideCoverPiece(
              (window.height + (leftMiterCount * w) + pvcWeldingAllowance) /
                  1000.0,
              startMiter: hasSeparateCoverTop,
              endMiter: hasSeparateCoverBottom && window.hasBottomFrame,
            );
          }
          if (hasSeparateCoverRight) {
            addSideCoverPiece(
              (window.height + (rightMiterCount * w) + pvcWeldingAllowance) /
                  1000.0,
              startMiter: hasSeparateCoverTop,
              endMiter: hasSeparateCoverBottom && window.hasBottomFrame,
            );
          }
          if (hasSeparateCoverTop) {
            addSideCoverPiece(
              (window.width + (topMiterCount * w) + pvcWeldingAllowance) /
                  1000.0,
              startMiter: true,
              endMiter: true,
            );
          }
          if (hasSeparateCoverBottom) {
            addSideCoverPiece(
              (window.width + (bottomMiterCount * w) + pvcWeldingAllowance) /
                  1000.0,
              startMiter: window.hasBottomFrame,
              endMiter: window.hasBottomFrame,
            );
          }
        }
      }

      if (sideCoverPieces.isNotEmpty) {
        items.add(
          appendSideCoverNote(
            createProfile(
              'الغطاء الجانبي (Side Cover)',
              colorName,
              pieces: sideCoverPieces,
              pieceCutAngles: sideCoverAngles,
              unit: 'قطاع',
              overrideMap: selectedSeparateCoverMap,
              preferOverrideMap: true,
              // This row is a separate stock profile. Make its catalogue role
              // explicit instead of relying on its translated display name, so
              // it survives strict BOM filtering and remains selectable.
              selectorType: 'side_cover',
              roleKey: 'side_cover',
            ),
            integrated: false,
          ),
        );
      }
    }

    if (hasSingleSash ||
        hasDoubleSash ||
        hasSlidingSash ||
        fixedPlinthePieces.isNotEmpty) {
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
      List<String> sashPieceAngles = [];
      List<double> slidingSashPieces = [];
      List<String> slidingSashPieceAngles = [];
      List<double> slidingSashTraversePieces = [];
      List<double> slidingSashLateralPieces = [];
      List<double> slidingSashLateralReinforcedPieces = [];
      List<double> slidingSashLateralNormalPieces = [];
      List<double> slidingSashCentralPieces = [];
      List<double> slidingSashCentralReinforcedPieces = [];
      List<double> slidingSashCentralSlimPieces = [];
      List<double> slidingFaceToFacePieces = [];
      List<double> slidingSlimCleatPieces = [];
      List<double> slidingSashTraverse4590Pieces = [];
      List<double> slidingSashTraverse9090Pieces = [];
      List<double> sashPlinthePieces = [];

      // The plinthe is cut inside the sash, not across the complete sash
      // outside width.  Use the visible width of the selected opening sash
      // on both sides; this is the same inner-opening principle used by the
      // glass calculation, without inventing a fixed 10 mm deduction.
      double plintheSashVisibleWidth = 0.0;
      final selectedOpeningSash = window.sashOverride;
      final rawVisibleWidth = selectedOpeningSash?['visible_width'];
      plintheSashVisibleWidth = rawVisibleWidth is num
          ? rawVisibleWidth.toDouble()
          : double.tryParse(rawVisibleWidth?.toString() ?? '') ?? 0.0;
      if (plintheSashVisibleWidth <= 0) {
        // In a mixed drawing the active primary series can be sliding while
        // this plinthe still belongs to the opening series.
        final openingSeries = window.activeSeries;
        if (openingSeries != null) {
          for (final section in openingSeries.sections) {
            final type = section.type.toLowerCase();
            final name = section.name.toLowerCase();
            if (section.isSash ||
                type == 'sash' ||
                type.contains('ouvrant') ||
                name.contains('sash') ||
                name.contains('ouvrant') ||
                name.contains('ظلفة')) {
              plintheSashVisibleWidth = section.visibleWidth;
              if (plintheSashVisibleWidth > 0) break;
            }
          }
        }
      }
      if (plintheSashVisibleWidth <= 0) {
        plintheSashVisibleWidth = window.profileThickness;
      }

      double plintheCutWidth(double sashOuterWidth) =>
          math.max(0.0, sashOuterWidth - (plintheSashVisibleWidth * 2.0));

      final Map<String, List<double>> sashPiecesByProfile = {};
      final Map<String, List<String>> sashAnglesByProfile = {};
      final Map<String, Map<String, dynamic>> sashOverrideByProfile = {};

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

        final zoneSashOverride = zone.sashOverride ?? openingSashOverride;
        final profileKey =
            zoneSashOverride?['id']?.toString() ??
            zoneSashOverride?['code']?.toString() ??
            (zone.isSash105 ? '105' : '104');
        if (zoneSashOverride != null) {
          sashOverrideByProfile[profileKey] = zoneSashOverride;
        }
        final zoneSashPieces = sashPiecesByProfile.putIfAbsent(
          profileKey,
          () => <double>[],
        );
        final zoneSashAngles = sashAnglesByProfile.putIfAbsent(
          profileKey,
          () => <String>[],
        );

        if (zone.content == ZoneContent.singleSash) {
          double sashW = clearW + overlap * 2;
          double sashH = clearH + overlap * 2;
          if (zone.hasSashPlintheBottom) {
            final cuts = [sashW / 1000.0, sashH / 1000.0, sashH / 1000.0];
            sashPieces.addAll(cuts);
            zoneSashPieces.addAll(cuts);
            const angles = ['45/45', '45/90', '45/90'];
            sashPieceAngles.addAll(angles);
            zoneSashAngles.addAll(angles);
            sashPlinthePieces.add(plintheCutWidth(sashW) / 1000.0);
          } else {
            final cuts = [
              sashW / 1000.0,
              sashW / 1000.0,
              sashH / 1000.0,
              sashH / 1000.0,
            ];
            sashPieces.addAll(cuts);
            zoneSashPieces.addAll(cuts);
            final angles = List<String>.filled(4, '45/45');
            sashPieceAngles.addAll(angles);
            zoneSashAngles.addAll(angles);
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
            final cuts = [
              sashWLeft / 1000.0,
              sashH / 1000.0,
              sashH / 1000.0,
              sashWRight / 1000.0,
              sashH / 1000.0,
              sashH / 1000.0,
            ];
            sashPieces.addAll(cuts);
            zoneSashPieces.addAll(cuts);
            const angles = [
              '45/45',
              '45/90',
              '45/90',
              '45/45',
              '45/90',
              '45/90',
            ];
            sashPieceAngles.addAll(angles);
            zoneSashAngles.addAll(angles);
            sashPlinthePieces.add(plintheCutWidth(sashWLeft) / 1000.0);
            sashPlinthePieces.add(plintheCutWidth(sashWRight) / 1000.0);
          } else {
            final cuts = [
              sashWLeft / 1000.0,
              sashWLeft / 1000.0,
              sashH / 1000.0,
              sashH / 1000.0,
              sashWRight / 1000.0,
              sashWRight / 1000.0,
              sashH / 1000.0,
              sashH / 1000.0,
            ];
            sashPieces.addAll(cuts);
            zoneSashPieces.addAll(cuts);
            final angles = List<String>.filled(8, '45/45');
            sashPieceAngles.addAll(angles);
            zoneSashAngles.addAll(angles);
          }
        } else if (zone.content == ZoneContent.slidingSash) {
          final slidingSashOverride = window.slidingSashOverride;
          double slidingOverlap = slidingSashOverride != null
              ? (slidingSashOverride['sash_overlap'] as num?)?.toDouble() ?? 0.0
              : (window.getSlidingSectionByType('sash')?.sashOverlap ?? 0.0);
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
                ((slidingFrame['visible_width'] ?? slidingFrame['thickness'])
                        as num?)
                    ?.toDouble() ??
                0.0;

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
          final int slidingKitPairs = (sashes + 1) ~/ 2;
          final bool hasReinforcedLateral =
              zone.slidingMontantReinforced['lateral_0'] == true ||
              zone.slidingMontantReinforced['lateral_1'] == true ||
              zone.slidingMontantReinforced['lateral_left'] == true ||
              zone.slidingMontantReinforced['lateral_right'] == true;
          final bool hasReinforcedCentral = zone
              .slidingMontantReinforced
              .entries
              .any(
                (entry) =>
                    entry.key.startsWith('central_') && entry.value == true,
              );
          if (hasReinforcedLateral) {
            slidingTotalReinforcedLateralKits += slidingKitPairs;
          }
          if (hasReinforcedCentral) {
            // The reinforced central kit is sold as two kits per pair of
            // leaves (one kit for each central post).
            slidingTotalReinforcedCentralKits += slidingKitPairs * 2;
          }
          final configuredSashDeduction = window.slidingSashWidthDeduction(
            sashes,
          );
          double sashW = configuredSashDeduction != 0
              ? (wForCalc - configuredSashDeduction) / sashes
              : (wForCalc + ((sashes - 1) * 26.0)) / sashes;
          final configuredHeightDeduction = window.slidingSashHeightDeduction();
          final usableWindowHeight = math.max(
            0.0,
            window.height -
                (window.hasShutter && !window.isCaissonTunnel
                    ? window.shutterBoxHeight
                    : 0.0),
          );
          double sashH = configuredHeightDeduction != 0
              ? usableWindowHeight - configuredHeightDeduction
              : hForCalc + slidingOverlap * 2;
          bool hasThreePiece =
              !window.isSlidingPVC &&
              ((window.activeSlidingSeries?.hasThreePieceSash ?? false) ||
                  '${window.activeSlidingSeries?.name ?? ''}'
                      .toLowerCase()
                      .contains('tpr'));
          if (configuredHeightDeduction == 0 && window.isSlidingPVC) {
            sashH = hForCalc + slidingOverlap;
          }

          // Face-to-Face is a declared sliding-series role.  It is used only
          // at the central meeting: one profile for a three-leaf layout and
          // the two opposing profiles for four leaves on two tracks.  Do not
          // manufacture a fallback row when the series has no such rule.
          final faceSection = sashes >= 3
              ? (window.getConfiguredSectionForRole(
                      'face_to_face',
                      useSlidingSeries: true,
                    ) ??
                    window.getSlidingSectionByType('face_to_face') ??
                    window.getConfiguredSectionForRole(
                      'sash_central',
                      useSlidingSeries: true,
                    ) ??
                    window.getSlidingSectionByType('sash_central'))
              : null;
          final bool hasMeetingInCenter =
              zone.slidingFaceToFace &&
              isSlidingFaceToFaceLayout(
                trackCount: zone.slidingTrackCount,
                sashCount: sashes,
              );
          final faceEnabled = hasMeetingInCenter && faceSection != null;
          if (faceEnabled && sashes >= 4) {
            final faceCount = (sashes == 4 || sashes == 6) ? 2 : 1;
            slidingFaceToFacePieces.addAll(
              List<double>.filled(faceCount, sashH / 1000.0),
            );
          }
          if (hasThreePiece) {
            // New formula for 3-piece sash traverses in sliding systems (e.g. TPR / HPS)
            double tLen = 0.0;
            tLen = sashes == 3
                ? (window.width - 160.0) / 3.0
                : (window.width - 154.0) / 2.0;
            if (tLen < 0) tLen = 0.0;

            // Traverse pieces (2 pieces per sash: top and bottom)
            for (int s = 0; s < sashes; s++) {
              slidingSashTraversePieces.addAll([tLen / 1000.0, tLen / 1000.0]);
            }

            final int lateralCount = hasMeetingInCenter ? 4 : 2;
            final centralKeys = slidingCentralEdgeKeys(
              zone: zone,
              sashesCount: sashes,
            );

            // Lateral pieces (2 outer laterals, plus 2 meeting in center for 4 or 6 sashes)
            for (int i = 0; i < lateralCount; i++) {
              final legacyKey = i == 0
                  ? 'lateral_left'
                  : (i == (lateralCount == 4 ? 1 : lateralCount - 1)
                        ? 'lateral_right'
                        : 'lateral_$i');
              final reinforced =
                  zone.slidingMontantReinforced['lateral_$i'] ??
                  zone.slidingMontantReinforced[legacyKey] ??
                  false;
              if (reinforced &&
                  window.reinforcementMode ==
                      ReinforcementMode.independentScrewed) {
                // القسم الثالث: القطاع العادي يبقى كما هو + يركب عمود تدعيم مستقل ببراغي
                slidingSashLateralNormalPieces.add(sashH / 1000.0);
                slidingIndependentRenfortPieces.add(sashH / 1000.0);
              } else {
                (reinforced
                        ? slidingSashLateralReinforcedPieces
                        : slidingSashLateralNormalPieces)
                    .add(sashH / 1000.0);
              }
            }

            // Central / chicane pieces
            for (final key in centralKeys) {
              final s = int.tryParse(key.substring('central_'.length)) ?? 0;
              final legacyKey = s.isEven ? 'central_left' : 'central_right';
              final reinforced =
                  zone.slidingMontantReinforced[key] ??
                  zone.slidingMontantReinforced[legacyKey] ??
                  false;
              final isSlim = zone.slidingMontantSlim[key] ?? false;
              if (isSlim) {
                slidingSashCentralSlimPieces.add(sashH / 1000.0);
                slidingSlimCleatPieces.addAll([0.10, 0.10]);
              } else if (reinforced) {
                if (window.reinforcementMode ==
                    ReinforcementMode.independentScrewed) {
                  // القسم الثالث: القطاع العادي يبقى + عمود تدعيم مستقل
                  slidingSashCentralPieces.add(sashH / 1000.0);
                  slidingIndependentRenfortPieces.add(sashH / 1000.0);
                } else if (window.reinforcementMode ==
                    ReinforcementMode.chicaneCombination) {
                  // القسم الثاني: شيكان مدعمة + شيكان عادية (قطعة مدعمة وقطعة عادية)
                  if (s.isEven) {
                    slidingSashCentralReinforcedPieces.add(sashH / 1000.0);
                  } else {
                    slidingSashCentralPieces.add(sashH / 1000.0);
                  }
                } else {
                  // القسم الأول: تبديل كامل للقطاع إلى مدعم
                  slidingSashCentralReinforcedPieces.add(sashH / 1000.0);
                }
              } else {
                slidingSashCentralPieces.add(sashH / 1000.0);
              }
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
              final bool leftIsSlim =
                  s > 0 &&
                  (zone.slidingMontantSlim['central_${(s - 1) * 2 + 1}'] ??
                      false);
              final bool rightIsSlim =
                  s < (sashes - 1) &&
                  (zone.slidingMontantSlim['central_${s * 2}'] ?? false);

              if (leftIsSlim) {
                slidingSashCentralSlimPieces.add(sashH / 1000.0);
                slidingSlimCleatPieces.addAll([0.10, 0.10]);
              } else {
                slidingSashPieces.add(sashH / 1000.0);
                slidingSashPieceAngles.add('45/45');
              }

              if (rightIsSlim) {
                slidingSashCentralSlimPieces.add(sashH / 1000.0);
                slidingSlimCleatPieces.addAll([0.10, 0.10]);
              } else {
                slidingSashPieces.add(sashH / 1000.0);
                slidingSashPieceAngles.add('45/45');
              }

              // The top and bottom widths always belong to the sash profile.
              // Slim replaces only the selected vertical montant; it must not
              // move the sash widths to Complément haut/base or another row.
              if (leftIsSlim && rightIsSlim) {
                slidingSashPieces.addAll([sashW / 1000.0, sashW / 1000.0]);
                slidingSashPieceAngles.addAll(['90/90', '90/90']);
              } else if (leftIsSlim || rightIsSlim) {
                slidingSashPieces.addAll([sashW / 1000.0, sashW / 1000.0]);
                slidingSashPieceAngles.addAll(['45/90', '45/90']);
              } else {
                slidingSashPieces.addAll([sashW / 1000.0, sashW / 1000.0]);
                slidingSashPieceAngles.addAll(['45/45', '45/45']);
              }
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
          // Outer handles always carry their lock hardware.  The first
          // central handle is functional and carries one more set; the
          // optional mirrored central handle is visual-only.
          // A face-to-face four/six-leaf layout already draws and requires
          // one functional handle at the central meeting. Older drawings may
          // still have slidingCentralHandle=false even though the painter
          // correctly shows that handle. Do not let that stale flag remove
          // its Entrematique and strike from the BOM. The second central
          // handle remains decorative and adds a handle only.
          // A face-to-face layout physically has a functional handle at the
          // central meeting. Older saved drawings may still carry
          // slidingCentralHandle=false although the painter correctly draws
          // that handle. Counting only the stale flag produced 2
          // Entrematiques and 2 sliding strikes while 3 were visible.
          final bool hasCentralMain =
              hasMeetingInCenter &&
              (zone.slidingCentralHandle || zone.slidingFaceToFace);
          final bool hasCentralSecond =
              hasCentralMain && zone.slidingSecondCentralHandle;
          final functionalCentralHandle = hasCentralMain;
          slidingTotalEspagnolettes += 2 + (functionalCentralHandle ? 1 : 0);
          // Two outer leaves always have handles. When meeting in center,
          // central handles are added based on main functional handle and secondary decorative handle.
          slidingTotalHandles +=
              2 + (hasCentralMain ? 1 : 0) + (hasCentralSecond ? 1 : 0);
          void countHandle(String slot, {required bool functional}) {
            final type = window.slidingHandleTypeFor(zone, slot);
            slidingHandlesByType[type] = (slidingHandlesByType[type] ?? 0) + 1;
            if (functional && SlidingHandleType.needsEspagnolette(type)) {
              slidingEspagnolettesByType[type] =
                  (slidingEspagnolettesByType[type] ?? 0) + 1;
            }
          }

          countHandle(SlidingHandleType.left, functional: true);
          countHandle(SlidingHandleType.right, functional: true);
          if (hasCentralMain) {
            countHandle(SlidingHandleType.center, functional: true);
          }
          if (hasCentralSecond) {
            countHandle(SlidingHandleType.center, functional: false);
          }
          // One sliding-series kit serves one independent pair of leaves.
          // Count every sliding zone/frame separately and keep an additional
          // kit for an unpaired leaf in odd 3/5-leaf configurations.
          slidingTotalKits += (sashes + 1) ~/ 2;

          double h = hForCalc;
          final gachesPerEspagnolette = configuredGacheCount([
            'اسبانيولات المنزلق (Espagnolette)',
            'إسبانيوليت (Espagnolette)',
          ]);
          slidingTotalGacheCoulissant +=
              gachesPerEspagnolette * (2 + (functionalCentralHandle ? 1 : 0));

          bool excludeChicane =
              !window.isSlidingPVC &&
              ((window.system?.name.toLowerCase().contains('tpr') ?? false) ||
                  (window.system?.name.toLowerCase().contains('hps') ?? false));
          if (!excludeChicane) {
            final int piecesPerJunction = window.isSlidingPVC
                ? pvcChicanePiecesPerJunction
                : 2;
            final double chicaneLength = sashH;
            for (int j = 0; j < sashes - 1; j++) {
              final isSlim =
                  (zone.slidingMontantSlim['central_${j * 2}'] ?? false) ||
                  (zone.slidingMontantSlim['central_${j * 2 + 1}'] ?? false);
              if (isSlim) continue;

              final isJunctionReinforced =
                  (zone.slidingMontantReinforced['central_${j * 2}'] ??
                      false) ||
                  (zone.slidingMontantReinforced['central_${j * 2 + 1}'] ??
                      false);

              if (isJunctionReinforced &&
                  window.reinforcementMode ==
                      ReinforcementMode.chicaneCombination) {
                // القسم الثاني: شيكان مدعمة + شيكان عادية (قطعة مدعمة وقطعة عادية لكل وصلة)
                slidingChicaneRenforceePieces.add(chicaneLength / 1000.0);
                slidingChicanePieces.add(chicaneLength / 1000.0);
              } else if (isJunctionReinforced &&
                  window.reinforcementMode ==
                      ReinforcementMode.fullSubstitution) {
                // القسم الأول: القطاعات تتغير كلياً إلى شيكان مدعمة
                for (int c = 0; c < piecesPerJunction; c++) {
                  slidingChicaneRenforceePieces.add(chicaneLength / 1000.0);
                }
              } else if (isJunctionReinforced &&
                  window.reinforcementMode ==
                      ReinforcementMode.independentScrewed) {
                // القسم الثالث: الشيكان يبقى عادياً + يضاف عمود تدعيم مستقل
                for (int c = 0; c < piecesPerJunction; c++) {
                  slidingChicanePieces.add(chicaneLength / 1000.0);
                }
                slidingIndependentRenfortPieces.add(chicaneLength / 1000.0);
              } else {
                // شيكان عادي
                for (int c = 0; c < piecesPerJunction; c++) {
                  slidingChicanePieces.add(chicaneLength / 1000.0);
                }
              }
            }
          }

          double frameT = window.profileThickness;
          final frameSection = window.getSlidingBaseFrameSection();
          if (frameSection != null) {
            frameT = frameSection.visibleWidth > 0
                ? frameSection.visibleWidth
                : frameSection.thickness;
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
              : (() {
                  if (frameRects.isNotEmpty) {
                    for (final r in frameRects) {
                      if (r.contains(zone.boundary.center) ||
                          (r.left <= zone.boundary.left + 5.0 &&
                              r.right >= zone.boundary.right - 5.0 &&
                              r.top <= zone.boundary.top + 5.0 &&
                              r.bottom >= zone.boundary.bottom - 5.0)) {
                        return r.width;
                      }
                    }
                  }
                  return window.width.toDouble();
                })();
          // Rail length is the clear internal frame width. Apply the explicit
          // catalogue-rule correction last, so it has priority over inferred
          // geometry. The rule also controls whether one physical piece
          // represents one, two or three rails.
          double railLenMm =
              railFrameWidth -
              (frameT * 2.0) +
              window.slidingRailWidthAdjustmentMm;
          if (railLenMm < 0) railLenMm = 0;
          final railLen = railLenMm / 1000.0;
          final railPieceCount = window.slidingRailPieceCount(
            zone.slidingTrackCount,
          );
          slidingRailPieces.addAll(List.filled(railPieceCount, railLen));

          // Add the configured number of C-profile pieces after the base
          // frame. The series rule defines whether one C piece covers one,
          // two or three additional rails.
          final monorailSection = window.getSlidingFrameExtensionSection();
          final additionalTracks = window.slidingSingleTrackAdditionCount(
            zone.slidingTrackCount,
          );
          if (monorailSection != null && additionalTracks > 0) {
            // The extension repeats the physical cuts of its own frame. Do
            // not rely solely on `slidingOuterFramePieces`: in mixed or
            // nested drawings that shared list can be empty while the frame
            // cuts are correctly held by the per-rectangle map.
            List<double> extensionBaseCuts = const <double>[];
            for (final entry in frameCutsByRect.entries) {
              if (entry.key.contains(zone.boundary.center)) {
                extensionBaseCuts = entry.value;
                break;
              }
            }
            if (extensionBaseCuts.isEmpty &&
                slidingOuterFramePieces.isNotEmpty) {
              extensionBaseCuts = slidingOuterFramePieces;
            }
            if (extensionBaseCuts.isEmpty && framePieces.isNotEmpty) {
              extensionBaseCuts = framePieces;
            }
            if (extensionBaseCuts.isEmpty) {
              // Last-resort geometry fallback: an enabled two-track base and
              // a 3+ track drawing always need an extension, even during a
              // first asynchronous series load before cached frame cuts exist.
              final width = zone.boundary.width / 1000.0;
              final height = zone.boundary.height / 1000.0;
              extensionBaseCuts = window.hasBottomFrameForRect(zone.boundary)
                  ? <double>[width, width, height, height]
                  : <double>[width, height, height];
            }
            for (var copy = 0; copy < additionalTracks; copy++) {
              slidingFrameExtensionPieces.addAll(extensionBaseCuts);
              slidingFrameExtensionAngles.addAll(
                extensionBaseCuts.length >= 4
                    ? List<String>.filled(extensionBaseCuts.length, '45/45')
                    : const <String>['45/45', '45/90', '45/90'],
              );
            }
          }
        }
      }

      if (sashPiecesByProfile.isNotEmpty) {
        if (sashPiecesByProfile.length == 1) {
          final entry = sashPiecesByProfile.entries.first;
          items.add(
            createProfile(
              'الظلفة (Sash)',
              colorName,
              pieces: entry.value,
              pieceCutAngles: sashAnglesByProfile[entry.key],
              unit: 'قطاع',
              overrideMap:
                  sashOverrideByProfile[entry.key] ?? openingSashOverride,
              preferOverrideMap: sashOverrideByProfile[entry.key] != null,
            ),
          );
        } else {
          for (final entry in sashPiecesByProfile.entries) {
            final profileMap = sashOverrideByProfile[entry.key];
            final profileName =
                profileMap?['name']?.toString() ??
                profileMap?['code']?.toString() ??
                entry.key;
            items.add(
              createProfile(
                'الظلفة (Sash) - $profileName',
                colorName,
                pieces: entry.value,
                pieceCutAngles: sashAnglesByProfile[entry.key],
                unit: 'قطاع',
                overrideMap: profileMap ?? openingSashOverride,
                preferOverrideMap: true,
                roleKey: 'sash',
              ),
            );
          }
        }
      } else if (sashPieces.isNotEmpty) {
        items.add(
          createProfile(
            'الظلفة (Sash)',
            colorName,
            pieces: sashPieces,
            pieceCutAngles: sashPieceAngles,
            unit: 'قطاع',
            overrideMap: openingSashOverride,
          ),
        );
      }

      final plinthePieces = <double>[
        ...sashPlinthePieces,
        ...fixedPlinthePieces,
      ];
      if (plinthePieces.isNotEmpty) {
        items.add(
          createProfile(
            'بلانت (Plinthe)',
            colorName,
            pieces: plinthePieces,
            pieceCutAngles: uniformAngles(plinthePieces, '90/90'),
            unit: 'متر',
            // Plinthe is its own catalogue role. Never fall back to the
            // selected sash profile, otherwise a thick sash can replace the
            // plant when the drawing changes sash type.
            overrideMap:
                window.componentOverrides['بلانت (Plinthe)'] ??
                window.getSectionByType('plinthe')?.toMap(),
          ),
        );
        items.add(
          createProfile(
            'حامل الجوان (Porte-joint)',
            colorName,
            pieces: plinthePieces,
            pieceCutAngles: uniformAngles(plinthePieces, '90/90'),
            unit: 'متر',
            overrideMap: window.componentOverrides['حامل الجوان (Porte-joint)'],
            selectorType: 'porte_joint',
          ),
        );
        final porteJointLength = plinthePieces.fold<double>(
          0.0,
          (sum, piece) => sum + piece,
        );
        if (porteJointLength > 0) {
          items.add(
            createJoint(
              'جوان بروس (Joint Brosse)',
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
            pieceCutAngles:
                slidingSashPieceAngles.length == slidingSashPieces.length
                ? slidingSashPieceAngles
                : uniformAngles(slidingSashPieces, '45/45'),
            unit: 'قطاع',
            overrideMap:
                window.slidingSashOverride ??
                window.getSlidingSectionByType('sash')?.toMap(),
            preferOverrideMap: true,
            selectorType: 'sash',
            roleKey: 'sash',
          ),
        );
      }

      if (slidingSashTraverse4590Pieces.isNotEmpty) {
        final traverseOverride =
            window
                .getConfiguredSectionForRole(
                  'sash_traverse',
                  useSlidingSeries: true,
                )
                ?.toMap() ??
            window.getSlidingSectionByType('sash_traverse')?.toMap() ??
            window.getSlidingSectionByType('traverse')?.toMap();
        items.add(
          createProfile(
            'عارضة الضلفة المنزلقة 45°/90° (Traverse Sash 45°/90°)',
            colorName,
            pieces: slidingSashTraverse4590Pieces,
            pieceCutAngles: uniformAngles(
              slidingSashTraverse4590Pieces,
              '45/90',
            ),
            unit: 'قطاع',
            overrideMap: traverseOverride,
            preferOverrideMap: true,
            selectorType: 'sash_traverse',
            roleKey: 'sash_traverse',
          ),
        );
      }

      if (slidingSashTraverse9090Pieces.isNotEmpty) {
        final traverseOverride =
            window
                .getConfiguredSectionForRole(
                  'sash_traverse',
                  useSlidingSeries: true,
                )
                ?.toMap() ??
            window.getSlidingSectionByType('sash_traverse')?.toMap() ??
            window.getSlidingSectionByType('traverse')?.toMap();
        items.add(
          createProfile(
            'عارضة الضلفة المنزلقة 90°/90° (Traverse Sash 90°/90°)',
            colorName,
            pieces: slidingSashTraverse9090Pieces,
            pieceCutAngles: uniformAngles(
              slidingSashTraverse9090Pieces,
              '90/90',
            ),
            unit: 'قطاع',
            overrideMap: traverseOverride,
            preferOverrideMap: true,
            selectorType: 'sash_traverse',
            roleKey: 'sash_traverse',
          ),
        );
      }

      if (slidingSashTraversePieces.isNotEmpty) {
        items.add(
          createProfile(
            'سكة الظلفة (Sash Traverse)',
            colorName,
            pieces: slidingSashTraversePieces,
            pieceCutAngles: uniformAngles(slidingSashTraversePieces, '90/90'),
            unit: 'قطاع',
            overrideMap:
                slidingOverrideFor(['عرضي (Traverse)']) ??
                window.getSlidingSectionByType('sash_traverse')?.toMap() ??
                window.getSlidingSectionByType('traverse')?.toMap(),
            preferOverrideMap: true,
          ),
        );
      }

      // Keep legacy aggregate output when no per-side flag exists, but split
      // the BOM whenever the two lateral montants use different profiles.
      slidingSashLateralPieces = [
        ...slidingSashLateralNormalPieces,
        ...slidingSashLateralReinforcedPieces,
      ];
      if (slidingSashLateralNormalPieces.isNotEmpty) {
        const lateralName = 'قائم جانبي (Sash Lateral)';
        var baseLateral = slidingOverrideFor([
          lateralName,
          'قائم جانبي (Lateral)',
        ]);
        if (baseLateral != null &&
            window.isSlidingMontantReinforced(baseLateral, central: false)) {
          baseLateral = null;
        }
        baseLateral ??=
            window.getSlidingSectionByType('sash_lateral')?.toMap() ??
            window.getSlidingSectionByType('lateral')?.toMap();

        items.add(
          createProfile(
            lateralName,
            colorName,
            pieces: slidingSashLateralNormalPieces,
            pieceCutAngles: uniformAngles(
              slidingSashLateralNormalPieces,
              '90/90',
            ),
            unit: 'قطاع',
            overrideMap: baseLateral,
            preferOverrideMap: true,
            selectorType: 'sash_lateral',
            roleKey: 'sash_lateral',
          ),
        );
      }
      if (slidingSashLateralReinforcedPieces.isNotEmpty) {
        var reinforcedLateral = slidingOverrideFor([
          'قائم جانبي معزز (Sash Lateral Renforcé)',
        ]);
        if (reinforcedLateral != null &&
            !window.isSlidingMontantReinforced(
              reinforcedLateral,
              central: false,
            )) {
          reinforcedLateral = null;
        }
        reinforcedLateral ??= window
            .getSlidingSectionByType('sash_lateral_reinforced')
            ?.toMap();

        items.add(
          createProfile(
            'قائم جانبي معزز (Sash Lateral Renforcé)',
            colorName,
            pieces: slidingSashLateralReinforcedPieces,
            pieceCutAngles: uniformAngles(
              slidingSashLateralReinforcedPieces,
              '90/90',
            ),
            unit: 'قطاع',
            overrideMap: reinforcedLateral,
            preferOverrideMap: true,
            selectorType: 'sash_lateral_reinforced',
            roleKey: 'sash_lateral_reinforced',
          ),
        );
        items.add(
          createAccessory(
            'أغطية القائم الجانبي المعزز (Bouchons Montant Latéral Renforcé)',
            qty: slidingSashLateralReinforcedPieces.length * 2,
            roleKeyOverride: 'bouchon_montant_lateral_renforce',
            selectorTypeOverride: 'bouchon_montant_lateral_renforce',
            sliding: true,
          ),
        );
      }

      if (slidingSashCentralPieces.isNotEmpty) {
        const centralName = 'قائم وسطي (Sash Central)';
        var baseCentral = slidingOverrideFor([
          centralName,
          'قائم وسطي (Central)',
          'الشيكان (Chicane)',
        ]);
        if (baseCentral != null &&
            window.isSlidingMontantReinforced(baseCentral, central: true)) {
          baseCentral = null;
        }
        baseCentral ??=
            window.getSlidingSectionByType('sash_central')?.toMap() ??
            window.getSlidingSectionByType('central')?.toMap() ??
            window.getSlidingSectionByType('chicane')?.toMap();

        items.add(
          createProfile(
            centralName,
            colorName,
            pieces: slidingSashCentralPieces,
            pieceCutAngles: uniformAngles(slidingSashCentralPieces, '90/90'),
            unit: 'قطاع',
            overrideMap: baseCentral,
            preferOverrideMap: true,
            selectorType: 'sash_central',
            roleKey: 'sash_central',
          ),
        );
      }

      if (slidingSashCentralReinforcedPieces.isNotEmpty) {
        var reinforcedCentral = slidingOverrideFor([
          'قائم وسطي معزز (Sash Central Renforcé)',
          'شيكان معزز (Chicane Renforcée)',
        ]);
        if (reinforcedCentral != null &&
            !window.isSlidingMontantReinforced(
              reinforcedCentral,
              central: true,
            )) {
          reinforcedCentral = null;
        }
        reinforcedCentral ??=
            window
                .getSlidingSectionByType('sash_central_reinforced')
                ?.toMap() ??
            window.getSlidingSectionByType('chicane_renforcee')?.toMap();

        items.add(
          createProfile(
            'قائم وسطي معزز (Sash Central Renforcé)',
            colorName,
            pieces: slidingSashCentralReinforcedPieces,
            pieceCutAngles: uniformAngles(
              slidingSashCentralReinforcedPieces,
              '90/90',
            ),
            overrideMap: reinforcedCentral,
            preferOverrideMap: true,
            selectorType: 'sash_central_reinforced',
            roleKey: 'sash_central_reinforced',
          ),
        );
        items.add(
          createAccessory(
            'أغطية القائم الوسطي المعزز (Bouchons Montant Central Renforcé)',
            qty: slidingSashCentralReinforcedPieces.length * 2,
            roleKeyOverride: 'bouchon_montant_central_renforce',
            selectorTypeOverride: 'bouchon_montant_central_renforce',
            sliding: true,
          ),
        );
      }

      if (slidingSashCentralSlimPieces.isNotEmpty) {
        final slimOverride =
            window.selectedSlimMontantProfile ??
            slidingOverrideFor([
              'قائم وسطي سليم (Montant Slim)',
              'قائم وسطي سليم (Sash Central Slim)',
            ]) ??
            window.getSlidingSlimCandidates().firstOrNull;
        items.add(
          createProfile(
            'قائم وسطي (Montant Slim)',
            colorName,
            pieces: slidingSashCentralSlimPieces,
            pieceCutAngles: uniformAngles(
              slidingSashCentralSlimPieces,
              '90/90',
            ),
            unit: 'قطاع',
            overrideMap: slimOverride,
            preferOverrideMap: true,
            selectorType: 'montant_central_slim',
            roleKey: 'montant_central_slim',
          ),
        );
      }

      if (slidingFaceToFacePieces.isNotEmpty) {
        final faceOverride =
            (window.getConfiguredSectionForRole(
                      'face_to_face',
                      useSlidingSeries: true,
                    ) ??
                    window.getSlidingSectionByType('face_to_face'))
                ?.toMap();
        if (faceOverride != null) {
          items.add(
            createProfile(
              'قائم Face to Face (Face-to-Face)',
              colorName,
              pieces: slidingFaceToFacePieces,
              pieceCutAngles: uniformAngles(slidingFaceToFacePieces, '45/45'),
              unit: 'قطاع',
              overrideMap: faceOverride,
              preferOverrideMap: true,
              selectorType: 'face_to_face',
              roleKey: 'face_to_face',
            ),
          );
        }
      }

      if (slidingSlimCleatPieces.isNotEmpty) {
        final cleatOverride =
            // The 10 cm top/bottom complement is a series role, not a
            // name-based optional accessory. Resolving it by name made it
            // disappear for catalogues whose section uses a normal code/name.
            window
                .getConfiguredSectionForRole(
                  'complement_haut_base',
                  useSlidingSeries: true,
                )
                ?.toMap() ??
            slidingOverrideFor([
              'مكمل علوي وسفلي للمونتوسليم 10 سم (Complément haut et bas)',
              'قطاع وصلة المونتوسليم 10 سم (Taquet Slim 10cm)',
              'قطاع وصلة المونتوسليم 10 سم (Taquet Slim)',
            ]) ??
            (window.activeSlidingSeries ?? window.activeSeries)?.sections
                .firstWhereOrNull((s) {
                  final n = s.name.toLowerCase();
                  final t = s.type.toLowerCase();
                  final c = s.code.toLowerCase();
                  return n.contains('وصلة') ||
                      n.contains('taquet') ||
                      t.contains('taquet') ||
                      c.contains('taquet') ||
                      n.contains('cleat') ||
                      t.contains('cleat');
                })
                ?.toMap();
        items.add(
          createProfile(
            'قطاع وصلة مكمل علوي وسفلي للمونتوسليم 10 سم (Taquet / Complément haut et bas)',
            colorName,
            pieces: slidingSlimCleatPieces,
            pieceCutAngles: uniformAngles(slidingSlimCleatPieces, '90/90'),
            unit: 'قطاع',
            overrideMap: cleatOverride,
            preferOverrideMap: true,
            selectorType: 'complement_haut_base',
            roleKey: 'complement_haut_base',
          ),
        );
      }

      if (slidingTotalReinforcedLateralKits > 0) {
        items.add(
          createAccessory(
            'كيت العمود الجانبي المعزز (Kit Lateral Renforcé)',
            color: colorName,
            qty: slidingTotalReinforcedLateralKits,
            sliding: true,
          ),
        );
      }
      if (slidingTotalReinforcedCentralKits > 0) {
        items.add(
          createAccessory(
            'كيت العمود الوسطي المعزز (Kit Central Renforcé)',
            color: colorName,
            qty: slidingTotalReinforcedCentralKits,
            sliding: true,
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
            pieceCutAngles: uniformAngles(slidingChicanePieces, '90/90'),
            unit: 'قطاع',
            overrideMap: baseChicane,
            preferOverrideMap: true,
          ),
        );
      }

      if (slidingChicaneRenforceePieces.isNotEmpty) {
        final reinforcedChicane =
            slidingOverrideFor([
              'شيكان معزز (Chicane Renforcée)',
              'قائم وسطي معزز (Sash Central Renforcé)',
            ]) ??
            window.getSlidingSectionByType('chicane_renforcee')?.toMap() ??
            window.getSlidingSectionByType('sash_central_reinforced')?.toMap();
        items.add(
          createProfile(
            'شيكان معزز (Chicane Renforcée)',
            colorName,
            pieces: slidingChicaneRenforceePieces,
            pieceCutAngles: uniformAngles(
              slidingChicaneRenforceePieces,
              '90/90',
            ),
            unit: 'قطاع',
            overrideMap: reinforcedChicane,
            preferOverrideMap: true,
            selectorType: 'chicane_renforcee',
            roleKey: 'chicane_renforcee',
          ),
        );
      }

      if (slidingIndependentRenfortPieces.isNotEmpty) {
        final renfortOverride =
            slidingOverrideFor([
              'عمود تدعيم مستقل (Profilé de Renfort Rapporté)',
              'عمود مدعم مستقل (Profilé de Renfort Rapporté)',
              'حديد تدعيم (Renfort)',
              'renfort',
            ]) ??
            window.getSlidingSectionByType('independent_renfort')?.toMap() ??
            window.getSlidingSectionByType('renfort')?.toMap() ??
            window.getSectionByType('independent_renfort')?.toMap() ??
            window.getSectionByType('renfort')?.toMap();
        items.add(
          createProfile(
            'عمود تدعيم مستقل (Profilé de Renfort Rapporté)',
            colorName,
            pieces: slidingIndependentRenfortPieces,
            pieceCutAngles: uniformAngles(
              slidingIndependentRenfortPieces,
              '90/90',
            ),
            unit: 'قطاع',
            overrideMap: renfortOverride,
            preferOverrideMap: true,
            selectorType: 'independent_renfort',
            roleKey: 'independent_renfort',
          ),
        );

        // Screws: ((length_mm / 300).ceil() + 1) screws per piece
        int renfortScrewsCount = 0;
        for (final p in slidingIndependentRenfortPieces) {
          renfortScrewsCount += ((p * 1000.0 / 300.0).ceil() + 1);
        }
        items.add(
          createAccessory(
            'براغي تثبيت العمود المدعم 3.9×38 (Vis de Renfort 3.9×38)',
            qty: renfortScrewsCount,
          ),
        );

        // Caps: 2 per piece (top and bottom)
        items.add(
          createAccessory(
            'أغطية عمود التدعيم المستقل (Bouchons Renfort Rapporté)',
            qty: slidingIndependentRenfortPieces.length * 2,
            roleKeyOverride: 'bouchon_renfort_rapporte',
            selectorTypeOverride: 'bouchon_renfort_rapporte',
            sliding: true,
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
              pieceCutAngles: uniformAngles(slidingRailPieces, '90/90'),
              unit: 'قطاع',
              overrideMap: railOverride,
              preferOverrideMap: true,
            ),
          );
        }
      }

      // A frame extension is another physical frame profile added to the
      // selected base frame. It therefore repeats the exact base-frame cuts
      // (four sides, or three when the lower frame side is disabled), rather
      // than adding one unrelated horizontal rail cut.
      slidingMonorailPieces.addAll(slidingFrameExtensionPieces);
      if (slidingMonorailPieces.isNotEmpty) {
        final extensionSection = window.getSlidingFrameExtensionSection();
        if (extensionSection != null) {
          items.add(
            createProfile(
              'كومبليمو دورمو (Complément Dormant)',
              colorName,
              pieces: slidingMonorailPieces,
              pieceCutAngles:
                  slidingFrameExtensionAngles.length ==
                      slidingMonorailPieces.length
                  ? slidingFrameExtensionAngles
                  : uniformAngles(slidingMonorailPieces, '45/45'),
              unit: 'قطاع',
              overrideMap: extensionSection.toMap(),
              preferOverrideMap: true,
              selectorType: 'frame_extension',
              roleKey: 'frame_extension',
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
            pieceCutAngles: uniformAngles(
              internalSlidingSideCoverPieces,
              '90/90',
            ),
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
              pieceCutAngles: uniformAngles(renfortSashPieces, '90/90'),
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
              pieceCutAngles: uniformAngles(renfortSashMifsalPieces, '90/90'),
              unit: 'قطاع',
            ),
          );
        }
        int screwsAlong(double lengthMm) =>
            lengthMm <= 0 ? 0 : (lengthMm / 400.0).ceil() + 1;

        int totalRenfortScrews = 0;
        final frameWidthScrews = screwsAlong(window.width.toDouble());
        final frameHeightScrews = screwsAlong(netHeight);
        totalRenfortScrews += frameWidthScrews * 2 + frameHeightScrews * 2;

        for (var zone in window.zones) {
          if (zone.content == ZoneContent.singleSash) {
            double sashWidth = zone.boundary.width;
            double sashHeight = zone.boundary.height;
            final sashWidthScrews = screwsAlong(sashWidth);
            final sashHeightScrews = screwsAlong(sashHeight);
            totalRenfortScrews += sashWidthScrews * 2 + sashHeightScrews * 2;
          } else if (zone.content == ZoneContent.doubleSash) {
            double sashWidthLeft = zone.boundary.width * zone.doubleSashRatio;
            double sashWidthRight =
                zone.boundary.width * (1.0 - zone.doubleSashRatio);
            double sashHeight = zone.boundary.height;

            final leftWidthScrews = screwsAlong(sashWidthLeft);
            final leftHeightScrews = screwsAlong(sashHeight);
            final rightWidthScrews = screwsAlong(sashWidthRight);
            final rightHeightScrews = screwsAlong(sashHeight);

            totalRenfortScrews += leftWidthScrews * 2 + leftHeightScrews * 2;
            totalRenfortScrews += rightWidthScrews * 2 + rightHeightScrews * 2;
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

      // Batmo is an opening-system profile.  Use the same canonical override
      // key as the selector dialog; the old " Batment" label could not find
      // the selected profile and the BOM therefore marked it as missing.
      items.add(
        createProfile(
          'الباتمو (Batmo)',
          colorName,
          pieces: batmoPieces,
          pieceCutAngles: uniformAngles(batmoPieces, '90/90'),
          unit: 'قطاع',
          overrideMap: batmoSectionMap,
          preferOverrideMap: true,
          selectorType: 'batmo',
          roleKey: 'batmo',
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
        createAccessory(
          'براغي الباتمو 3.9*50',
          qty: batmoScrews * doubleSashCount,
          roleKeyOverride: 'batmo_screw',
          selectorTypeOverride: 'is_batmo_screw',
        ),
      );
      final bouchonOverride =
          window.componentOverrides['بوشون باتمو (Bouchon Batmo)'];
      final bouchonSection = window.getConfiguredSectionForRole(
        'bouchon_batmo',
        useSlidingSeries: false,
      );
      final configuredBouchonId = bouchonSection?.id;
      final overrideBouchonId = bouchonOverride is Map
          ? int.tryParse('${bouchonOverride['id'] ?? ''}')
          : null;
      final validBouchonOverride =
          configuredBouchonId != null &&
              overrideBouchonId == configuredBouchonId
          ? Map<String, dynamic>.from(bouchonOverride as Map)
          : bouchonSection?.toMap();
      final hasBouchonBatmo = bouchonSection != null;

      if (hasBouchonBatmo) {
        if (bouchonSection != null ||
            (bouchonOverride is Map &&
                bouchonOverride.containsKey('bar_length'))) {
          items.add(
            createProfile(
              'Bouchon Batmo',
              accessoryColorName,
              unit: 'قطعة',
              qty: doubleSashCount.toDouble(),
              overrideMap: validBouchonOverride,
              preferOverrideMap: true,
              ignoreSavedOverride: true,
              selectorType: 'bouchon_batmo',
              roleKey: 'bouchon_batmo',
            ),
          );
        } else {
          items.add(
            createAccessory(
              'بوشون باتمو (Bouchon Batmo)',
              qty: doubleSashCount,
              roleKeyOverride: 'bouchon_batmo',
              selectorTypeOverride: 'bouchon_batmo',
            ),
          );
        }
        items.add(
          createAccessory(
            'براغي بوشون باتمو',
            qty: (doubleSashCount * 2).toInt(),
            roleKeyOverride: 'bouchon_batmo_screw',
            selectorTypeOverride: 'is_bouchon_batmo_screw',
          ),
        );
      }
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
            groupExpandedItems: true,
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
    }

    if (hasSingleSash || hasDoubleSash || hasSlidingSash) {
      // Every normal window handle requires one espagnolette.  OB/Demi-OB
      // only changes whether the ordinary espagnolette is active; it must
      // never silently reduce its quantity.
      final bool isEspagnoletteActive = !isSystemObActive && !isDemiObActive;
      final int espagnoletteQty = totalHandles;

      // Espagnolette is an independent accessory role for opening windows,
      // not a PVC-only component. Aluminium series can define its own
      // espagnolette rule as well.
      if (espagnoletteQty > 0 && !hasSlidingSash) {
        final targetH = window.effectiveEspagnoletteHeightMm / 10.0;

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
            roleKeyOverride: 'espagnolette',
            selectorTypeOverride: 'espagnolette',
          ),
        );
      }

      // The strike is derived only after the actual espagnolette has been
      // selected for this series, material, height and shutter state. The
      // drawing decides its BOM role; the linked catalogue item and count
      // always come from that selected espagnolette.
      final espagnoletteOverride =
          window.componentOverrides['إسبانيوليت (Espagnolette)'];
      final usesMultiAccessoryLinks =
          espagnoletteOverride is Map &&
          espagnoletteOverride['linked_accessories'] is List &&
          (espagnoletteOverride['linked_accessories'] as List).isNotEmpty;
      if (!usesMultiAccessoryLinks && windowSingleSashCount > 0) {
        items.add(
          createRelatedAccessory(
            'إسبانيوليت (Espagnolette)',
            'قاش سامبل (Gache Simple Ouvrant)',
            qty: windowSingleSashCount * gacheQtyPerDoubleSash,
          ),
        );
      }
      // System OB — إما تفجير Kit أو عنصر واحد
      final systemObKey = getKitKey('System OB');
      if (systemObKey != null &&
          (kitBundleData[systemObKey]?.isNotEmpty ?? false)) {
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
            groupExpandedItems: true,
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
              groupExpandedItems: true,
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

      final bool isCremoneActive = !isSystemObActive && !isDemiObActive;
      if (useCremone && cremoneQty > 0) {
        final cremoneOverride =
            window.componentOverrides['كريمون (Cremone)'] ??
            window.componentOverrides['إسبانيوليت (Espagnolette)'];
        final triangleRule = cremoneOverride is Map
            ? Map<String, dynamic>.from(cremoneOverride)
            : const <String, dynamic>{};
        final triangleProfile =
            (window.componentOverrides['تراينغل الكريمون (Triangle)'] is Map
                ? Map<String, dynamic>.from(window.componentOverrides['تراينغل الكريمون (Triangle)'])
                : null) ??
            (window.componentOverrides['triangle'] is Map
                ? Map<String, dynamic>.from(window.componentOverrides['triangle'])
                : null) ??
            window.getConfiguredSectionForRole('triangle')?.toMap() ??
            window.getSectionByType('triangle')?.toMap() ??
            window.getSlidingSectionByType('triangle')?.toMap();
        // A Cremone always drives two Tringle cuts when the series has a
        // Tringle profile.  The manager configures only the total deduction;
        // the drawing supplies the real handle position.
        final useTriangle = triangleProfile != null;

        final isEspagnoletteOverride = window.componentOverrides.containsKey(
          'إسبانيوليت (Espagnolette)',
        );
        final cremoneName = isEspagnoletteOverride
            ? 'إسبانيوليت (Espagnolette)'
            : 'كريمون (Cremone)';
        items.add(
          createAccessory(
            cremoneName,
            color: accessoryColorName,
            qty: cremoneQty,
            isActive: isCremoneActive,
            roleKeyOverride: isEspagnoletteOverride
                ? 'espagnolette'
                : 'cremone',
          ),
        );
        if (useTriangle && isCremoneActive) {
          double numberFromRule(String key) {
            final value = triangleRule[key];
            return value is num
                ? value.toDouble()
                : double.tryParse(value?.toString() ?? '') ?? 0.0;
          }

          final triangleDeduction = math.max(
            0.0,
            numberFromRule('triangle_deduction_mm'),
          );
          final trianglePieces = <double>[];
          final triangleCutPairs = <String>[];
          for (final run in triangleDrawingRuns) {
            final drawingHeight = math
                .max(0.0, run['height_mm'] ?? 0.0)
                .toDouble();
            final handleRatio = (run['handle_ratio'] ?? 0.5)
                .clamp(0.0, 1.0)
                .toDouble();
            // Split the handle displacement equally between the two cuts.
            // Example: H=1200, D=200, handle=400 (200 below centre) gives
            // 400 mm below and 600 mm above, rather than 300/700.
            final cuts = cremoneTringleCutsMm(
              heightMm: drawingHeight,
              deductionMm: triangleDeduction,
              handleRatio: handleRatio,
            );
            final firstTrianglePiece = cuts[0];
            final secondTrianglePiece = cuts[1];
            triangleCutPairs.add(
              '${firstTrianglePiece.toStringAsFixed(0)} + '
              '${secondTrianglePiece.toStringAsFixed(0)}',
            );
            // [createProfile] expands every base cut by [window.quantity].
            // Keep only the two cuts for one physical window here; expanding
            // them here as well made Tringle quantities grow by quantity².
            trianglePieces.addAll([
              firstTrianglePiece / 1000.0,
              secondTrianglePiece / 1000.0,
            ]);
          }
          items.add(
            createProfile(
              'تراينغل الكريمون (Triangle)',
              colorName,
              pieces: trianglePieces,
              pieceCutAngles: uniformAngles(trianglePieces, '90/90'),
              unit: 'قطاع',
              overrideMap: triangleProfile,
              preferOverrideMap: true,
              selectorType: 'triangle',
              roleKey: 'triangle',
            ).copyWith(
              cuttingList:
                  'قطع القص: ${triangleCutPairs.join(' ؛ ')} مم لكل كريمون',
            ),
          );
        }
      }
      if (!usesMultiAccessoryLinks && windowDoubleSashCount > 0) {
        items.add(
          createRelatedAccessory(
            'إسبانيوليت (Espagnolette)',
            'قاش دوبل (Gache Double Ouvrant)',
            isActive: !isVerrouCentralActive,
            qty: windowDoubleSashCount * gacheQtyPerDoubleSash,
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
      if (encastreeHandles > 0 && window.systemMode != 'sliding') {
        items.add(
          createAccessory(
            SlidingHandleType.accessoryKey(SlidingHandleType.encastree),
            color: accessoryColorName,
            qty: encastreeHandles,
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
      // Cremone is the complete locking/handle assembly for this aluminium
      // opening. It must never be shown together with the standalone handle,
      // unless an explicit handle override was configured.
      final hasExplicitHandleOverride =
          window.componentOverrides.containsKey('مقبض نافذة (Poignée)') ||
          window.componentOverrides.containsKey('المقبض (Handle)') ||
          window.componentOverrides.containsKey('مقبض نافذة (Poignée Fenêtre)');
      // لا يُحسب مقبض الفتح إطلاقاً إذا كان عدد ظلفات الفتح صفراً (totalHandles == 0)
      final effectiveHandles = totalHandles;
      if (totalHandles > 0 &&
          effectiveHandles > 0 &&
          (!useCremone || hasExplicitHandleOverride) &&
          window.systemMode != 'sliding') {
        if (window.isPVC) {
          items.add(
            createAccessory(
              'مقبض نافذة (Poignée Fenêtre)',
              color: accessoryColorName,
              qty: totalHandles,
            ),
          );
        } else {
          final handleName =
              window.componentOverrides.containsKey('مقبض نافذة (Poignée)')
              ? 'مقبض نافذة (Poignée)'
              : 'المقبض (Handle)';
          items.add(
            createAccessory(
              handleName,
              color: accessoryColorName,
              qty: effectiveHandles,
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

      // Vis de pose belongs to the completed outer frame, not to hinges or
      // sliding leaves.  Count both vertical sides, then the bottom width;
      // the top width receives the same count only when there is no shutter.
      // The thresholds intentionally mirror the workshop rule: 2/3/4 screws
      // per vertical side (up to 1 m / 2 m / above 2 m), and 0/1/2 across a
      // horizontal side (up to 1 m / below 2 m / from 2 m).
      int installationVerticalScrewsPerSide(double heightMm) {
        if (heightMm <= 1000) return 2;
        if (heightMm <= 2000) return 3;
        return 4;
      }

      int installationHorizontalScrews(double widthMm) {
        if (widthMm <= 1000) return 0;
        if (widthMm < 2000) return 1;
        return 2;
      }

      final verticalScrewCountPerSide = installationVerticalScrewsPerSide(
        window.height.toDouble(),
      );
      final horizontalScrewCount = installationHorizontalScrews(
        window.width.toDouble(),
      );
      final installationScrewQty =
          (verticalScrewCountPerSide * 2) +
          horizontalScrewCount +
          (hasShutter ? 0 : horizontalScrewCount);
      if (installationScrewQty > 0) {
        items.add(
          createAccessory(
            'براغي التركيب (Vis de pose)',
            qty: installationScrewQty,
            // A pure sliding outer frame must use the selected sliding
            // series. Mixed/opening drawings keep the opening frame source.
            sliding: window.usesSlidingPrimaryProfiles,
          ),
        );
      }

      if (slidingTotalRoulettes > 0) {
        items.add(
          createAccessory(
            'عجلات المنزلق (Roulettes)',
            color: accessoryColorName,
            qty: slidingTotalRoulettes,
            sliding: true,
          ),
        );
        if (!window.isSlidingPVC && slidingTotalKits > 0) {
          final String seriesName =
              window.activeSlidingSeries?.name.toLowerCase() ?? '';
          String? kitKey;
          if (seriesName.contains('76000') || seriesName.contains('7600')) {
            kitKey = 'كيت 76000 (Kit 76000)';
          } else if (seriesName.contains('40000') ||
              seriesName.contains('4000')) {
            kitKey = 'كيت 40000 (Kit 40000)';
          } else if (seriesName.contains('67000') ||
              seriesName.contains('6700')) {
            kitKey = 'كيت 67000 (Kit 67000)';
          }
          if (kitKey != null) {
            items.add(
              createAccessory(
                kitKey,
                color: accessoryColorName,
                qty: slidingTotalKits,
                sliding: true,
              ),
            );
          }
        }
        final bool useEntrematique =
            !window.isSlidingPVC &&
            window.zones.any(
              (z) =>
                  z.content == ZoneContent.slidingSash &&
                  z.useClassicHandle != true,
            ) &&
            // Only add Entrematique to the BOM when the series has a confirmed
            // catalogue product for it (i.e. the user has selected one, or the
            // model carries an override).  If the series has no Entrematique
            // rule at all the BomEngine will silently drop it after filtering
            // available candidates, but we can avoid emitting a misleading
            // item altogether by checking the override map first.
            (window.componentOverrides.containsKey(
                  'أونتروماتيك (Entrematique)',
                ) ||
                window.componentOverrides.containsKey('entrematique'));

        final perPlaceHandles = window.zones.any(
          (z) =>
              z.content == ZoneContent.slidingSash &&
              z.slidingHandleTypes.isNotEmpty,
        );
        if (perPlaceHandles) {
          // Each handle place has its own type: one line per type, and an
          // espagnolette for every functional handle but an entrematique.
          final espagnolettes = slidingEspagnolettesByType.values.fold(
            0,
            (a, b) => a + b,
          );
          if (espagnolettes > 0) {
            items.add(
              createAccessory(
                'اسبانيولات المنزلق (Espagnolette)',
                color: accessoryColorName,
                qty: espagnolettes,
                sliding: true,
              ),
            );
          }
          for (final type in SlidingHandleType.values) {
            final qty = slidingHandlesByType[type] ?? 0;
            if (qty <= 0) continue;
            items.add(
              createAccessory(
                SlidingHandleType.accessoryKey(type),
                color: accessoryColorName,
                qty: qty,
                sliding: true,
              ),
            );
          }
        } else if (useEntrematique) {
          items.add(
            createAccessory(
              'أونتروماتيك (Entrematique)',
              color: accessoryColorName,
              qty: slidingTotalHandles,
              sliding: true,
            ),
          );
        } else {
          items.add(
            createAccessory(
              'اسبانيولات المنزلق (Espagnolette)',
              color: accessoryColorName,
              qty: slidingTotalEspagnolettes,
              sliding: true,
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
              sliding: true,
            ),
          );
        }
        // Demand belongs to the sliding geometry. An enabled sliding_lock
        // rule determines the product, including with an Entrematique handle.
        items.add(
          createAccessory(
            'كاش كوليسون (Gache coulissant)',
            qty: slidingTotalGacheCoulissant,
            sliding: true,
          ),
        );

        // Add Gache Porte (قاش بورت) if it is a door
        final isDoor =
            window.system?.name.toLowerCase().contains('porte') ?? false;
        if (isDoor) {
          items.add(
            createAccessory(
              'قاش بورت (Gache Porte)',
              color: accessoryColorName,
              qty: 2,
              sliding: true,
            ),
          );
        }

        // الصيغة الموحدة لا تحتاج تبديل خاص بـ PVC

        // 🟢 جوان بروس للظلفة: لا يُضاف تلقائياً لسلاسل الألمنيوم مثل TPR 67000
        // إلا إذا كان خيار جوان البروس مخصصاً ومحدداً صراحة لهذه السلسلة أو إذا كان النظام PVC
        if (slidingTotalJointBrosse > 0) {
          items.add(
            createJoint(
              'جوان بروس للظلفة (Joint Brosse Sash)',
              sliding: true,
              color: colorName,
              qty: slidingTotalJointBrosse,
              unit: 'متر',
            ),
          );
        }

        slidingGlassJoints.forEach((jointName, totalLength) {
          items.add(
            createJoint(
              jointName,
              sliding: true,
              qty: totalLength,
              unit: 'متر',
            ),
          );
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
        // Do not add a zero-quantity Cremone placeholder merely because a
        // selection is saved in componentOverrides. A dormant selection must
        // not appear beside the real standalone handle in the quantity table.
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
      final shutterSplits = window.effectiveShutterSplits;
      bool isMotorMechanism(String mechanism) =>
          mechanism == 'محرك' || mechanism.toLowerCase().contains('moteur');
      bool isCrankMechanism(String mechanism) =>
          mechanism == 'منايفال' ||
          mechanism == 'مانيفال' ||
          mechanism == 'مانيفر' ||
          mechanism.toLowerCase().contains('maniv');
      bool isBeltMechanism(String mechanism) =>
          mechanism == 'حزام' ||
          mechanism.toLowerCase().contains('sangle') ||
          mechanism.toLowerCase().contains('belt');
      String splitMechanism(ShutterSplitSection split) =>
          split.mechanism?.trim().isNotEmpty == true
          ? split.mechanism!.trim()
          : window.shutterMechanism;
      final motorSplitCount = shutterSplits
          .where((split) => isMotorMechanism(splitMechanism(split)))
          .length;
      final crankSplitCount = shutterSplits
          .where((split) => isCrankMechanism(splitMechanism(split)))
          .length;
      final beltSplitCount = shutterSplits
          .where((split) => isBeltMechanism(splitMechanism(split)))
          .length;
      final bool isMotor = motorSplitCount > 0;
      final bool isCrank = crankSplitCount > 0;
      final bool isBelt = beltSplitCount > 0;

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

      // Tunnel kits contain the support/tandem assembly.  They are not
      // standalone BOM choices for a tunnel drawing; the actual shutter
      // parts (motor, blades, axe, rails and caps) remain visible below.
      bool showIndividualOptions = !isTunnel && isExtrudedBlade;

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

      final int shutterSplitCount = shutterSplits.length;

      // ===== 1. الكيت (Kit) - أول مركب، فقط لغير النفق =====
      bool hasTunnelManoeuvreKit = false;
      void addAndExpandKit(
        String uiKey,
        String descriptionCode, {
        int? splitCount,
        String? mechanism,
        double? sectionWidthMm,
        double? sectionHeightMm,
        double? sectionWeightKg,
        bool filterAxeItems = true,
        bool sizeBound = true,
        bool showKitRow = true,
        List<String> preferredKitTokens = const [],
        List<String> requiredKitTokens = const [],
      }) {
        String? matchedKitName;
        // Only a KitBundles selection may override the bundle chosen below;
        // legacy values saved from ShutterComponents are ignored.
        final savedKitSelection = window.componentOverrides[uiKey];
        final selectedInCatalogue = selectedKitBundle(
          savedKitSelection,
          kitBundleMetadata.values,
        );
        if (savedKitSelection is Map &&
            savedKitSelection['catalog_source'] == 'KitBundles' &&
            selectedInCatalogue == null &&
            kitBundleMetadata.isNotEmpty) {
          // The chosen kit was deleted or deactivated: say so instead of
          // silently pricing another kit as if it had been chosen.
          window.reportCatalogIssue(
            'Kit "${savedKitSelection['name'] ?? ''}" not in catalogue',
            StateError('selected kit missing'),
          );
        }

        final candidates = compatibleKitBundles(
          kits: kitBundleMetadata.values,
          descriptionCode: descriptionCode,
          minimumSizeMm: sizeBound ? window.shutterBoxHeight : null,
          allowWithoutSize: !sizeBound,
        );
        final normalizedRequiredTokens = requiredKitTokens
            .map((token) => token.trim().toLowerCase())
            .where((token) => token.isNotEmpty)
            .toList(growable: false);
        final scopedCandidates = normalizedRequiredTokens.isEmpty
            ? candidates
            : candidates
                  .where((kit) {
                    final searchable = [
                      kit['name'],
                      kit['measurement'],
                      kit['description'],
                    ].whereType<Object>().join(' ').toLowerCase();
                    return normalizedRequiredTokens.any(
                      (token) => searchable.contains(token),
                    );
                  })
                  .toList(growable: false);
        final candidatePool = scopedCandidates.isNotEmpty
            ? scopedCandidates
            : candidates;
        final normalizedPreferredTokens = preferredKitTokens
            .map((token) => token.trim().toLowerCase())
            .where((token) => token.isNotEmpty)
            .toList(growable: false);
        final preferredCandidates = normalizedPreferredTokens.isEmpty
            ? const <Map<String, dynamic>>[]
            : candidatePool
                  .where((kit) {
                    final searchable = [
                      kit['name'],
                      kit['measurement'],
                      kit['description'],
                    ].whereType<Object>().join(' ').toLowerCase();
                    return normalizedPreferredTokens.any(
                      (token) => searchable.contains(token),
                    );
                  })
                  .toList(growable: false);
        final orderedCandidates = preferredCandidates.isNotEmpty
            ? preferredCandidates
            : candidatePool;
        final manual = selectedKitBundle(savedKitSelection, candidatePool);
        if (manual != null) {
          // The current catalogue name, which also keys the kit's items.
          matchedKitName = (manual['name'] ?? '').toString();
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
        if (isTunnel && descriptionCode == 'M') {
          hasTunnelManoeuvreKit = true;
        }
        final bool perLeaf = kitPerLeafMap[groupName] ?? false;
        final effectiveSplitCount = splitCount ?? shutterSplitCount;
        final effectiveMechanism = mechanism ?? window.shutterMechanism;
        final double kitQty =
            (perLeaf
                ? ((doubleSashCount * 2) + singleSashCount).toDouble()
                : 1.0) *
            effectiveSplitCount;

        // `isMotorized` describes the mechanism, but every kit uses the
        // same source: its KitBundles record and exact stored French name.
        // The tunnel kit is only a configuration container; its real child
        // parts are listed directly instead of creating a fictitious BOM row.
        final matchedKitItems = kitBundleData[groupName];
        // A configured KitBundles row is only a container for its selected
        // children. Never charge/display the parent KitBundle beside those
        // children. Keep the parent row only for an empty kit, which is a
        // legitimate standalone fallback.
        final hasConfiguredKitItems = matchedKitItems?.isNotEmpty == true;
        if (showKitRow && !hasConfiguredKitItems) {
          items.add(createKitBundle(uiKey, groupName, qty: kitQty));
        }

        if (hasConfiguredKitItems) {
          final String shutterVariant = isExtrudedBlade ? 'extruded' : 'normal';
          final int leafCount =
              (perLeaf ? ((doubleSashCount * 2) + singleSashCount) : 1) *
              effectiveSplitCount;
          var expandedItems = expandKitBundle(
            groupName,
            matchedKitItems!,
            leafHeightMm: sectionHeightMm ?? window.height.toDouble(),
            leafWidthMm: sectionWidthMm ?? window.width.toDouble(),
            shutterWeightKg: sectionWeightKg ?? shutterWeightKg,
            mechanismScope: shutterMechanismScope(effectiveMechanism),
            mechanismScopes: shutterMechanismScopes(
              effectiveMechanism,
              motorHasEmergencyCrank: motorHasEmergencyCrank,
            ),
            bladeScope: isExtrudedBlade ? 'extruded' : 'normal',
            isActive: true,
            // دائماً مفعَّل — لا تُشطَب عناصر الكيت
            leafCount: leafCount,
            category: 'shutter',
            variantValue: shutterVariant,
            // Keep the children attached to the Kit group. The quantity table
            // renders one collapsed Kit row and reveals these children only
            // after the user expands it.
            groupExpandedItems: true,
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
        // Every box section is an independent shutter. Expanding one section
        // at a time is important: kit ranges, motor capacity and accessories
        // must use that section's width/height/weight, not the full opening.
        for (final split in shutterSplits) {
          final mechanism = splitMechanism(split);
          final sectionHeight = split.customHeight ?? window.height.toDouble();
          final sectionWeight = shutterCurtainWeightKg(
            windowWidthMm: split.width,
            windowHeightMm: sectionHeight,
            shutterBoxHeightMm: window.shutterBoxHeight,
            isTunnel: false,
            bladeHeightMm: selectedBladeHeightMm,
            bladeWeightPerSqm: bladeWeightPerSqm,
            bladeEndCapThicknessMm: bladeCapThicknessMm,
          );
          if (isMotorMechanism(mechanism)) {
            addAndExpandKit(
              'كيت فولي موتور (Kit Volet Moteur)',
              'MT',
              splitCount: 1,
              mechanism: mechanism,
              sectionWidthMm: split.width,
              sectionHeightMm: sectionHeight,
              sectionWeightKg: sectionWeight,
              filterAxeItems: true,
            );
          } else if (isCrankMechanism(mechanism)) {
            addAndExpandKit(
              'كيت فولي مانيفر (Kit Volet Manivelle)',
              'V',
              splitCount: 1,
              mechanism: mechanism,
              sectionWidthMm: split.width,
              sectionHeightMm: sectionHeight,
              sectionWeightKg: sectionWeight,
            );
            addAndExpandKit(
              'كيت مانيفر (Kit Manivelle)',
              'M',
              splitCount: 1,
              mechanism: mechanism,
              sectionWidthMm: split.width,
              sectionHeightMm: sectionHeight,
              sectionWeightKg: sectionWeight,
              sizeBound: false,
            );
          } else {
            addAndExpandKit(
              'كيت فولي (Kit Volet)',
              'V',
              splitCount: 1,
              mechanism: mechanism,
              sectionWidthMm: split.width,
              sectionHeightMm: sectionHeight,
              sectionWeightKg: sectionWeight,
            );
          }
        }
        // براغي الكيت
        items.add(createShutter('براغي الكيت', qty: 8.0 * shutterSplitCount));
      } else {
        // Select the configured CT bundle matching the selected tunnel kit and
        // tunnel height when the catalogue contains more than one variant.
        final tunnelKitType =
            window.caissonPayload?['kitType']?.toString().toLowerCase() ?? '';
        final tunnelSize = window.caissonTunnelHeight.toInt().toString();
        for (final split in shutterSplits) {
          final mechanism = splitMechanism(split);
          final sectionHeight = split.customHeight ?? window.height.toDouble();
          final sectionWeight = shutterCurtainWeightKg(
            windowWidthMm: split.width,
            windowHeightMm: sectionHeight,
            shutterBoxHeightMm: window.shutterBoxHeight,
            isTunnel: true,
            bladeHeightMm: selectedBladeHeightMm,
            bladeWeightPerSqm: bladeWeightPerSqm,
            bladeEndCapThicknessMm: bladeCapThicknessMm,
          );
          final tunnelMechanismTokens = isMotorMechanism(mechanism)
              ? ['moteur', 'motor', 'محرك']
              : isCrankMechanism(mechanism)
              ? ['manoeuvre', 'manivelle', 'maniv', 'مانيف', 'منايف']
              : isBeltMechanism(mechanism)
              ? ['sangle', 'belt', 'حزام']
              : ['assemble', 'assembly', 'assemblage', 'تجميع'];
          addAndExpandKit(
            'كيت صندوق النفق (Kit Caisson Tunnel)',
            'CT',
            splitCount: 1,
            mechanism: mechanism,
            sectionWidthMm: split.width,
            sectionHeightMm: sectionHeight,
            sectionWeightKg: sectionWeight,
            sizeBound: false,
            filterAxeItems: false,
            showKitRow: true,
            preferredKitTokens: [tunnelKitType, tunnelSize],
            requiredKitTokens: tunnelMechanismTokens,
          );
          if (isCrankMechanism(mechanism)) {
            // A manoeuvre tunnel is made of two distinct kits: the tunnel
            // assembly itself and the separate manoeuvre kit.
            addAndExpandKit(
              'كيت مانيفر (Kit Manivelle)',
              'M',
              splitCount: 1,
              mechanism: mechanism,
              sectionWidthMm: split.width,
              sectionHeightMm: sectionHeight,
              sectionWeightKg: sectionWeight,
              sizeBound: false,
              preferredKitTokens: const ['manoeuvre', 'manivelle', 'maniv'],
            );
          }
        }
      }

      // The tunnel kit supplies the tunnel-specific profiles. The ordinary
      // shutter rows still have to be calculated from the actual shutter
      // width/height and selected blade, motor and rail catalogue entries.
      // Only the regular overhead caisson itself is omitted in tunnel mode;
      // it is represented by the configured CT kit above.
      // ===== 2. الصندوق وبراغيه =====
      if (!isTunnel) {
        List<double> caissonPieces = [window.width / 1000.0 - 0.01];
        if (window.isShutterSplit && window.effectiveShutterSplits.isNotEmpty) {
          caissonPieces = window.effectiveShutterSplits
              .map((s) => math.max(0.0, s.width / 1000.0 - 0.01))
              .toList();
        }
        items.add(
          createShutter(
            'الصندوق (Caisson)',
            color: shutterColorName,
            pieces: caissonPieces,
            unit: 'بارة',
          ),
        );
        items.add(
          createShutter('براغي الصندوق', qty: 10.0 * shutterSplitCount),
        );
      }

      // ===== 3. المحور (Axe) =====
      // The physical shutter always has an axis, whether it was selected
      // directly or supplied by a kit. Keep it as an explicit BOM row so its
      // quantity and official catalogue price never disappear.
      {
        List<double> axePieces = [(window.width - 75) / 1000.0];
        if (window.isShutterSplit && window.effectiveShutterSplits.isNotEmpty) {
          axePieces = window.effectiveShutterSplits
              .map((s) => math.max(0.0, (s.width - 75.0) / 1000.0))
              .toList();
        }
        items.add(
          createShutter('المحور (Axe)', pieces: axePieces, unit: 'بارة'),
        );
      }

      // ===== 4. المحرك/المانيفال - مباشرة بعد المحور =====
      if (crankSplitCount > 0 && (!isTunnel || !hasTunnelManoeuvreKit)) {
        items.add(
          createShutter(
            'المانيفال (Manivelle)',
            color: shutterColorName,
            qty: crankSplitCount.toDouble(),
          ),
        );
        items.add(
          createShutter(
            'براغي المانيفال',
            qty: (isTunnel ? 1.0 : 4.0) * crankSplitCount,
          ),
        );
      }
      if (motorSplitCount > 0) {
        // This is the selected shutter motor, not a KitBundle child.  Keep it
        // in the shutter section as an independent row.  Only rows emitted by
        // expandKitBundle are allowed to carry the tunnel kitGroupName.
        items.add(
          createShutter(
            'المحرك (Moteur)',
            color: shutterColorName,
            qty: motorSplitCount.toDouble(),
          ),
        );
        items.add(
          createShutter(
            'براغي المحرك',
            qty: (isTunnel ? 1.0 : 4.0) * motorSplitCount,
          ),
        );
      }
      if (motorSplitCount > 0) {
        if (window.motorHasInterrupteur) {
          items.add(
            createShutter(
              'قاطعة (Interrupteur)',
              qty: motorSplitCount.toDouble(),
            ),
          );
        }
        if (window.motorHasTelecommande) {
          items.add(
            createShutter(
              'جهاز تحكم (Télécommande)',
              qty: motorSplitCount.toDouble(),
            ),
          );
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
          : (double.tryParse(bladeHeightMatch.group(0)!.replaceAll(',', '.')) ??
                43.0);
      final safeBladeHeightMm = bladeHeightMm > 0 ? bladeHeightMm : 43.0;
      final frameRects = window.getFrameRects();
      final hasMultiFrames = frameRects.length > 1;

      final bladePieces = <double>[];
      int totalBladesCount = 0;
      final lameFinalePieces = <double>[];

      double capThick = 0.0;
      if (linkedBladeEndCap != null) {
        final rawThickness = linkedBladeEndCap['cap_thickness'];
        capThick = rawThickness is num
            ? rawThickness.toDouble()
            : double.tryParse(rawThickness?.toString() ?? '') ?? 0.0;
      }

      if (window.isShutterSplit && window.effectiveShutterSplits.isNotEmpty) {
        for (final split in window.effectiveShutterSplits) {
          final sWidth = split.width;
          final sHeight = split.customHeight ?? window.height;
          final sNumBlades =
              ((sHeight - window.shutterBoxHeight) / safeBladeHeightMm + 2)
                  .ceil()
                  .clamp(0, 100000)
                  .toInt();
          totalBladesCount += sNumBlades;

          double sBladeLengthM = math.max(0.0, (sWidth - 65.0)) / 1000.0;
          if (capThick > 0) {
            sBladeLengthM = math.max(
              0.0,
              sBladeLengthM - (2 * capThick) / 1000.0,
            );
          }
          bladePieces.addAll(List<double>.filled(sNumBlades, sBladeLengthM));

          double sLameFinaleM = math.max(0.0, (sWidth - 65.0)) / 1000.0;
          if (capThick > 0) {
            sLameFinaleM = math.max(
              0.0,
              sLameFinaleM - (2 * capThick) / 1000.0,
            );
          }
          lameFinalePieces.add(sLameFinaleM);
        }
      } else if (hasMultiFrames) {
        for (final rect in frameRects) {
          final fWidth = rect.width;
          final fHeight = rect.height;
          final fNumBlades =
              ((fHeight - window.shutterBoxHeight) / safeBladeHeightMm + 2)
                  .ceil()
                  .clamp(0, 100000)
                  .toInt();
          totalBladesCount += fNumBlades;

          double fBladeLengthM = math.max(0.0, (fWidth - 65.0)) / 1000.0;
          if (capThick > 0) {
            fBladeLengthM = math.max(
              0.0,
              fBladeLengthM - (2 * capThick) / 1000.0,
            );
          }
          bladePieces.addAll(List<double>.filled(fNumBlades, fBladeLengthM));

          double fLameFinaleM = math.max(0.0, (fWidth - 65.0)) / 1000.0;
          if (capThick > 0) {
            fLameFinaleM = math.max(
              0.0,
              fLameFinaleM - (2 * capThick) / 1000.0,
            );
          }
          lameFinalePieces.add(fLameFinaleM);
        }
      } else {
        final numBladesShutter =
            ((window.height - window.shutterBoxHeight) / safeBladeHeightMm + 2)
                .ceil()
                .clamp(0, 100000)
                .toInt();
        totalBladesCount = numBladesShutter;
        double bladeLengthM = math.max(0.0, (window.width - 65.0)) / 1000.0;
        if (capThick > 0) {
          bladeLengthM = math.max(0.0, bladeLengthM - (2 * capThick) / 1000.0);
        }
        bladePieces.addAll(List<double>.filled(numBladesShutter, bladeLengthM));

        double lameFinaleLengthM =
            math.max(0.0, (window.width - 65.0)) / 1000.0;
        if (capThick > 0) {
          lameFinaleLengthM = math.max(
            0.0,
            lameFinaleLengthM - (2 * capThick) / 1000.0,
          );
        }
        lameFinalePieces.add(lameFinaleLengthM);
      }

      items.add(
        createShutter(
          'الشرائح (Lames)',
          color: shutterColorName,
          pieces: bladePieces,
          unit: 'بارة',
        ),
      );

      // ===== 6. أغطية الشفرات (Bouchons Lames) =====
      // End caps are automatic and are shown only in the quantity/cost table.
      if (isBouchonLameActive) {
        final int bladeEndCapQty = totalBladesCount.isOdd
            ? totalBladesCount - 1
            : totalBladesCount;
        items.add(
          createShutter(
            'أغطية الشفرات (Bouchons Lames)',
            qty: math.max(0, bladeEndCapQty).toDouble(),
            unit: 'حبة',
          ),
        );
      }

      // ===== 7. الشريحة النهائية (Lame Finale) =====
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
      if (window.isShutterSplit && window.effectiveShutterSplits.isNotEmpty) {
        coulissePieces = [];
        for (final split in window.effectiveShutterSplits) {
          final sH = split.customHeight ?? window.height;
          final sLengthM =
              (window.isCaissonTunnel ? (sH + 20.0) : (sH - caissonSize)) /
              1000.0;
          final validLen = math.max(0.0, sLengthM);
          coulissePieces.add(validLen);
          coulissePieces.add(validLen);
        }
      }
      final double totalCoulisseLengthM = coulissePieces.fold(
        0.0,
        (sum, len) => sum + len,
      );

      items.add(
        createShutter(
          'السكك (Coulisses)',
          color: shutterColorName,
          pieces: coulissePieces,
          unit: 'بارة',
        ),
      );

      // ===== 9. جوان بروس (Joint Brosse) =====
      items.add(
        createJoint(
          'جوان بروس للستار (Joint Brosse Shutter)',
          qty: totalCoulisseLengthM * 2,
          unit: 'متر',
        ),
      );

      // ===== 10. أطاش (Attache) =====
      // Every active shutter kit contains two Attaches. Count the total from
      // shutter width, then list only the remaining standalone Attaches:
      // 2 below 1200 mm, 3 from 1200 mm, 4 from 1600 mm, and 5 from 2000 mm.
      int totalAttaches = 0;
      if (window.isShutterSplit && window.effectiveShutterSplits.isNotEmpty) {
        for (final split in window.effectiveShutterSplits) {
          final w = split.width;
          totalAttaches += w >= 2000
              ? 5
              : (w >= 1600 ? 4 : (w >= 1200 ? 3 : 2));
        }
      } else {
        totalAttaches = window.width >= 2000
            ? 5
            : (window.width >= 1600 ? 4 : (window.width >= 1200 ? 3 : 2));
      }
      final int attachesIncludedByKit = isKitActive
          ? (2 * shutterSplitCount)
          : 0;
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
                qty: shutterSplitCount.toDouble(),
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
                qty: shutterSplitCount.toDouble(),
                category: 'shutter',
              ),
            );
            items.add(
              createInteractiveAccessory(
                'سيبور رولمو (Support Roulement)',
                'roulement_group',
                isActive: isSupportRoulementActive,
                qty: shutterSplitCount.toDouble(),
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
                qty: shutterSplitCount.toDouble(),
                category: 'shutter',
              ),
            );
          }
        }
      }
    }

    // ===== 12. الموستيكير (Moustiquaire) =====
    if (window.hasMoustiquaireAddon) {
      // قياس الموستيكير: عرض الإطار - 2 ملم، وارتفاع الإطار - 2 ملم
      final double moustiquaireW = math.max(0.0, window.width - 2.0);
      final double moustiquaireH = math.max(0.0, window.height - 2.0);
      final double areaSqm = moustiquaireAddonAreaSqm(window);

      final rawPrice = window.componentOverrides['موستيكير (Moustiquaire)']?['price_per_sqm'] ??
          window.componentOverrides['موستيكير (Moustiquaire)']?['price'] ??
          window.componentOverrides['moustiquaire']?['price_per_sqm'] ??
          window.componentOverrides['moustiquaire']?['price'] ??
          0.0;
      final double pricePerSqm = rawPrice is num
          ? rawPrice.toDouble()
          : double.tryParse('$rawPrice') ?? 0.0;

      items.add(
        BomItem(
          category: 'moustiquaire',
          originalName: 'موستيكير (Moustiquaire)',
          name: 'موستيكير (Moustiquaire)',
          quantity: areaSqm > 0 ? areaSqm : 1.0,
          exactQuantity: areaSqm > 0 ? areaSqm : 1.0,
          unit: 'م²',
          length: moustiquaireW,
          glassHeight: moustiquaireH,
          unitPrice: pricePerSqm,
          overrideKey: 'moustiquaire',
          selectorCategory: 'moustiquaire',
          selectorType: 'moustiquaire',
          roleKey: 'moustiquaire',
        ),
      );
    }

    {
      int totalAccessoryScrews = 0;
      final linkedScrewTotals = <int, int>{};
      final linkedScrews = <int, Map<String, dynamic>>{};
      for (var item in items) {
        if (item.category == 'accessory') {
          int screwCount = 0;
          Map<String, dynamic>? override;
          final exactOverride = window.componentOverrides[item.originalName];
          if (exactOverride is Map) {
            override = Map<String, dynamic>.from(exactOverride);
          } else if (item.originalName.contains('Espagnolette')) {
            final genericOverride =
                window.componentOverrides['إسبانيوليت (Espagnolette)'];
            if (genericOverride is Map) {
              override = Map<String, dynamic>.from(genericOverride);
            }
          }
          final resolvedOverride = override;
          if (resolvedOverride != null &&
              resolvedOverride['screw_count'] != null) {
            screwCount = resolvedOverride['screw_count'] is int
                ? resolvedOverride['screw_count']
                : int.tryParse(resolvedOverride['screw_count'].toString()) ?? 0;
          }
          final linked = resolvedOverride?['screw_accessory'];
          if (linked is Map && linked['id'] != null) {
            final linkedId = linked['id'] is num
                ? (linked['id'] as num).toInt()
                : int.tryParse(linked['id'].toString());
            if (linkedId != null) {
              linkedScrewTotals[linkedId] =
                  (linkedScrewTotals[linkedId] ?? 0) +
                  (screwCount * item.quantity.toInt());
              linkedScrews[linkedId] = Map<String, dynamic>.from(linked);
            }
          } else {
            totalAccessoryScrews += screwCount * item.quantity.toInt();
          }
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
      for (final entry in linkedScrewTotals.entries) {
        final linked = linkedScrews[entry.key];
        if (linked == null || entry.value <= 0) continue;
        const linkedName = 'براغي الإكسسوارات';
        final linkedKey = 'linked-accessory:screw:${entry.key}';
        final relatedOverrides = Map<String, dynamic>.from(
          window.componentOverrides,
        )..[linkedKey] = linked;
        items.add(
          _createAccessory(
            relatedOverrides,
            linkedName,
            qty: entry.value,
            overrideKey: linkedKey,
            catalogItemId: linked['id'] is num
                ? (linked['id'] as num).toInt()
                : int.tryParse('${linked['id'] ?? ''}'),
            colorId: catalogueColorId(accessoryColorName, accessory: true),
            selectorCategory: 'accessory',
            selectorType: 'is_accessory_screw',
            roleKey: 'accessory_screw',
            sourceSeriesId: window.activeSeries?.id,
            materialType: window.isPVC ? 'pvc' : 'aluminium',
          ),
        );
      }
    }

    // =========================================================================
    // استخراج أبعاد العرض الظاهر
    // =========================================================================
    final selectedSashSection = window.getSectionByType('sash');
    final selectedSashOverride = window.usesSlidingPrimaryProfiles
        ? window.slidingSashOverride
        : window.sashOverride;
    double sw = selectedSashOverride != null
        ? (selectedSashOverride['visible_width'] ?? window.profileThickness)
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
        double sashW =
            (clearW + ((sashesCount - 1) * window.openingSashOverlap)) /
            sashesCount;
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

    // --- Slanted mullions: each bar is cut at its long point with the angle
    // shown on the drawing halved at both ends (workshop rule). Profile by
    // exact catalogue code when the division names one.
    final Map<String, List<double>> slantedPiecesByCode = {};
    final Map<String, List<String>> slantedAnglesByCode = {};
    for (final zone in window.zones) {
      if (zone.slantedDividers.isEmpty) continue;
      final geometry = window.slantedGeometryFor(zone);
      for (final d in geometry.dividers) {
        final length = geometry.cutLengthMm(d) / 1000.0;
        if (length <= 0) continue;
        final code = d.profileCode ?? '';
        slantedPiecesByCode.putIfAbsent(code, () => []).add(length);
        slantedAnglesByCode
            .putIfAbsent(code, () => [])
            .add(
              '${geometry.cutAngleDeg(d, atStart: true).toStringAsFixed(1)}/'
              '${geometry.cutAngleDeg(d, atStart: false).toStringAsFixed(1)}',
            );
        totalMullionLengthMeters += length;
      }
    }
    for (final entry in slantedPiecesByCode.entries) {
      Map<String, dynamic>? section;
      if (entry.key.isNotEmpty) {
        for (final s in window.activeSeries?.sections ?? const []) {
          if (s.code.trim() == entry.key) {
            section = s.toMap();
            break;
          }
        }
      }
      items.add(
        createProfile(
          section == null
              ? 'تقسيم مائل (Traverse inclinée)'
              : 'تقسيم مائل (Traverse inclinée) — ${entry.key}',
          colorName,
          pieces: entry.value,
          pieceCutAngles: slantedAnglesByCode[entry.key],
          unit: 'قطاع',
          overrideMap: section,
          preferOverrideMap: section != null,
        ),
      );
    }

    if (totalMullionLengthMeters > 0) {
      final allMullionPieces = <double>[
        ...mullionPieces,
        for (final pieces in selectedMullionPieces.values) ...pieces,
        for (final pieces in slantedPiecesByCode.values) ...pieces,
      ];

      if (mullionPieces.isNotEmpty) {
        items.add(
          createProfile(
            'تقسيم الزجاج (Mullion)',
            colorName,
            pieces: mullionPieces,
            pieceCutAngles: uniformAngles(mullionPieces, '90/90'),
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
            pieceCutAngles: uniformAngles(entry.value, '90/90'),
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
            pieceCutAngles: uniformAngles(allMullionPieces, '90/90'),
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
          items[index] = existing.copyWith(
            qty: existing.quantity + mullionRenfortScrews,
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
    final connectorQty = isTprSeries
        ? (tasso: 0, ekar: 0)
        : divisionConnectorQuantities(
            divisionPieceCount: divisionPieceCount,
            isPvc: isOuterFramePvc,
            // The regular caisson is drawn above the window.  A tunnel caisson is
            // installed behind it, so it must not receive the PVC Tasso pair.
            hasRegularCaissonAboveWindow: hasShutter && !window.isCaissonTunnel,
            selectedFrameHasIntegratedCover: integratedFrameCoverWidth > 0,
          );

    // Assembly screws are generated by BomEngineV2 from the enabled
    // series rules and linked physical profiles, including Montant Slim.
    if (connectorQty.tasso > 0) {
      items.add(
        createAccessory(
          'الطاسو (Tasso)',
          qty: connectorQty.tasso,
          isActive: true,
        ),
      );
    }
    if (connectorQty.ekar > 0) {
      items.add(
        createAccessory(
          'الإيكار (Ekar)',
          qty: connectorQty.ekar,
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
    final Map<String, List<double>> bardagePiecesByColor = {};
    final Map<String, String> bardageColorNames = {};
    final Map<String, Map<String, dynamic>?> bardageColorData = {};
    List<double> parcloseSimplePieces = [];
    List<double> parcloseDoublePieces = [];
    // Parallel to the opening parclose lists: true marks a horizontal
    // (width) piece. A 90° cut shortens one direction once the parclose
    // profile, and therefore its glass deduction, is resolved.
    // null marks a shaped piece that a 90° cut never shortens.
    final List<bool?> parcloseSimpleIsWidth = [];
    final List<bool?> parcloseDoubleIsWidth = [];
    // Cut angles aligned with the pieces; only sent to the cutting sheet
    // when a slanted-division cell made a shaped (non-rectangular) parclose.
    final List<String> parcloseSimpleAngles = [];
    final List<String> parcloseDoubleAngles = [];
    bool hasShapedParclose = false;
    // Glass polygon of the slanted-division cell being priced, if any.
    List<Offset>? shapedGlassCell;
    final String rectParcloseAngles = !window.isPVC && window.parcloseCutAt90
        ? '90/90'
        : '45/45';
    void addOpeningParcloseRect({
      required bool isDouble,
      required double widthMm,
      required double heightMm,
    }) {
      final pieces = isDouble ? parcloseDoublePieces : parcloseSimplePieces;
      final flags = isDouble ? parcloseDoubleIsWidth : parcloseSimpleIsWidth;
      final angles = isDouble ? parcloseDoubleAngles : parcloseSimpleAngles;
      final shape = shapedGlassCell;
      if (shape != null) {
        // One piece per side of the glass, mitred at half of each corner.
        hasShapedParclose = true;
        final n = shape.length;
        for (var i = 0; i < n; i++) {
          final j = (i + 1) % n;
          pieces.add((shape[j] - shape[i]).distance / 1000.0);
          flags.add(null);
          final a = SlantedDivisionGeometry.interiorAngleDeg(shape, i) / 2;
          final b = SlantedDivisionGeometry.interiorAngleDeg(shape, j) / 2;
          angles.add('${a.toStringAsFixed(1)}/${b.toStringAsFixed(1)}');
        }
        return;
      }
      pieces
        ..add(widthMm / 1000.0)
        ..add(widthMm / 1000.0)
        ..add(heightMm / 1000.0)
        ..add(heightMm / 1000.0);
      flags.addAll(const [true, true, false, false]);
      angles.addAll(List.filled(4, rectParcloseAngles));
    }

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

    final bool openingSashSkipsGlazingBead =
        profileSkipsGlazingBead(window.sashOverride) ||
        !window.hasGlazingBeadForContext(sliding: false);
    final bool slidingHasGlazingBead = window.hasGlazingBeadForContext(
      sliding: true,
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
    Map<String, dynamic>? bardageProfileOverride() {
      return window.getBardageProfileOverride();
    }

    double bardageProfileValue(String key) {
      final override = bardageProfileOverride();
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
      final activeZoneSash =
          (zone.content == ZoneContent.slidingSash ||
              window.usesSlidingPrimaryProfiles)
          ? (zone.slidingSashOverride ?? window.slidingSashOverride)
          : (zone.sashOverride ?? window.sashOverride);
      if (activeZoneSash != null) {
        glassDeduction =
            ((activeZoneSash['glass_deduction'] ??
                        activeZoneSash['glassDeduction'] ??
                        0.0)
                    as num)
                .toDouble();
      } else {
        final sashSec = window.getSectionByType('sash');
        if (sashSec != null) {
          glassDeduction = sashSec.glassDeduction;
        }
      }

      double zoneSw =
          zone.sashThickness ??
          (activeZoneSash != null
              ? ((activeZoneSash['visible_width'] as num?)?.toDouble() ?? sw)
              : sw);
      if (zoneSw <= 0) zoneSw = sw;

      // The glass starts from the exact sash-cut length. It loses the two
      // sash faces and the 10 mm safety clearance; PVC additionally loses
      // 5 mm once welded. With a 60 mm sash this is 135 mm, so a 570 mm
      // sash cut produces a 435 mm glass cut.
      final double sashGlassDeduction =
          (zoneSw * 2.0) + videVerre + (window.isPVC ? 5.0 : 0.0);

      if (zone.content == ZoneContent.fixedGlass ||
          zone.content == ZoneContent.empty) {
        // الزجاج الثابت أو الإطار الفارغ: يمتد داخل أخدود الإطار مباشرةً
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
              : (window.getConfiguredSectionForRole('plant')?.thickness ??
                    window.getConfiguredSectionForRole('plant')?.visibleWidth ??
                    0.0);
          baseGh += zoneSw;
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
          baseGh += zoneSw;
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
                    0.0
              : 0.0;
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
        final double sashCutW = configuredSashDeduction != 0
            ? (wForCalc - configuredSashDeduction) / sashes
            : (wForCalc + ((sashes - 1) * 26.0)) / sashes;
        final configuredGlassSafety = slidingRuleNumber('glass_w_deduction');
        final glassSafety = configuredGlassSafety > 0
            ? configuredGlassSafety
            : videVerre;
        baseGw = configuredSashDeduction != 0 || window.isSlidingPVC
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

          final selectedPanneauProduct = isPanneau
              ? window.getPanneauProductForSpec(cellGlass)
              : null;
          final panneauProductText = selectedPanneauProduct == null
              ? ''
              : '${selectedPanneauProduct['subtype'] ?? ''} '
                        '${selectedPanneauProduct['name'] ?? ''} '
                        '${selectedPanneauProduct['type'] ?? ''}'
                    .toLowerCase();
          final resolvedBardageProfile = bardageProfileOverride();
          int? intValue(Object? value) {
            if (value is num) return value.toInt();
            return int.tryParse(value?.toString() ?? '');
          }

          final selectedProductId = intValue(cellGlass.panneauProductId);
          final bardageProfileId = intValue(resolvedBardageProfile?['id']);
          final isBardage =
              isPanneau &&
              (isBardagePanelSubtype(cellGlass.panneauSubtype) ||
                  isBardagePanelSubtype(panneauProductText) ||
                  cellGlass.finishOuter == GlassFinish.bardage ||
                  cellGlass.finishInner == GlassFinish.bardage ||
                  (selectedProductId != null &&
                      selectedProductId == bardageProfileId));

          if (isBardage && resolvedBardageProfile != null) {
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
              for (int q = 0; q < pieceMultiplier * window.quantity; q++) {
                addBardagePiece(cellGlass, pieceLength);
              }
            }

            // The bardage profile's own thickness determines its parclose;
            // it must not inherit a sandwich/decor panel thickness.
            if (!(usesOpeningSashProfile && openingSashSkipsGlazingBead)) {
              final bool bardageNeedsDouble = getBardageThickness() > 10.0;
              if (bardageNeedsDouble) {
                requiredOpeningParcloseDoubleThickness = math.max(
                  requiredOpeningParcloseDoubleThickness,
                  getBardageThickness(),
                );
              }
              for (int q = 0; q < pieceMultiplier * window.quantity; q++) {
                addOpeningParcloseRect(
                  isDouble: bardageNeedsDouble,
                  widthMm: cellGw,
                  heightMm: cellGh,
                );
              }
            }
            return;
          }

          if (isBardage) {
            // A bardage must never fall through to the square-metre panneau
            // branch. If its series profile is not configured, expose the
            // missing profile explicitly so the configuration can be fixed.
            items.add(
              BomItem(
                category: 'profile',
                originalName: 'البارداج (Bardage)',
                name: 'قطاع البرداج غير محدد في قواعد السلسلة',
                quantity: 0,
                unit: 'قطعة',
                unitPrice: 0,
                isMissing: true,
                inventoryItemType: 'Section',
                overrideKey: 'البارداج (Bardage)',
                selectorCategory: 'profile',
                selectorType: 'bardage',
                roleKey: 'bardage',
              ),
            );
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
          final bool isSlidingSystem =
              zone.content == ZoneContent.slidingSash ||
              ((window.systemMode == 'sliding' ||
                      window.systemMode == 'coulissant' ||
                      window.systemMode == 'منزلق') &&
                  zone.content != ZoneContent.empty &&
                  zone.content != ZoneContent.fixedGlass);
          // Parclose matching uses the sealed glass/panel pack only. The
          // retaining joints are selected separately and must not inflate the
          // requested parclose capacity or the resulting Intercalaire.
          double cellThick = cellGlass.totalThickness(window.allGlassCache);
          if (cellGlass.structure == GlassStructure.double) {
            final spacerSizes =
                window.availableIntercalls
                    .map((item) {
                      final raw = item['thickness'];
                      return raw is num
                          ? raw.toDouble()
                          : double.tryParse(raw?.toString() ?? '');
                    })
                    .whereType<double>()
                    .where((value) => value > 0)
                    .toList()
                  ..sort();
            final minimumSpacer = spacerSizes.isEmpty ? 6.0 : spacerSizes.first;
            cellThick =
                (cellGlass.thicknessOuter ?? 4.0) +
                (cellGlass.thicknessInner ?? 4.0) +
                minimumSpacer;
          }
          final double rawCellGlassPackThickness =
              cellGlass.structure == GlassStructure.double
              ? (cellGlass.thicknessOuter ?? 4.0) +
                    (cellGlass.thicknessInner ?? 4.0) +
                    cellGlass.intercallThickness
              : (cellGlass.thicknessOuter ?? 4.0);
          // A closed/decorative panel is not "simple glass". Select its
          // parclose from the real installed pack thickness, otherwise a
          // 20 mm panel is incorrectly sent to the 12 mm/simple bead while
          // the compatibility message is checking the 24 mm pocket.
          final bool needsDoubleParclose =
              cellGlass.structure == GlassStructure.double ||
              (cellGlass.structure == GlassStructure.closed &&
                  cellThick > 14.0);
          final bool isPvcSlidingSystem =
              isSlidingSystem && window.isSlidingPVC;
          if (cellGlass.fittedJoints.isNotEmpty) {
            final perimeter = (cellGw * 2 + cellGh * 2) / 1000.0;
            for (var side = 0; side < cellGlass.fittedJoints.length; side++) {
              final joint = cellGlass.fittedJoints[side];
              final rule = joint['catalog_rule'] as Map?;
              final role =
                  rule?['role_key']?.toString() ??
                  (side == 0 ? 'joint_vitrage' : 'joint_bourrage');
              final jointLabel = role == 'joint_vitrage'
                  ? 'جوان الزجاج (Joint Vitrage)'
                  : 'جوان البوراج (Joint Bourrage)';
              final key =
                  'fitted-glass:${rule?['series_id']}:${joint['id']}:$side';
              window.componentOverrides[key] = Map<String, dynamic>.from(joint);
              items.add(
                createJoint(
                  '$jointLabel — ${side == 0 ? 'خارجي' : 'داخلي'}',
                  qty: perimeter * totalPieces / window.quantity,
                  unit: 'متر',
                  sliding: isSlidingSystem,
                  overrideKey: key,
                  roleKeyOverride: role,
                  selectorTypeOverride: role,
                  targetThicknessMm: double.tryParse('${joint['thickness']}'),
                ),
              );
            }
            if (!isSlidingSystem && !openingSashSkipsGlazingBead) {
              if (needsDoubleParclose) {
                fittedDoublePerimeter += perimeter * pieceMultiplier;
              } else {
                fittedSimplePerimeter += perimeter * pieceMultiplier;
              }
            }
          }
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
          // Build the geometric demand first. The catalogue resolver decides
          // whether this series has an enabled reducer, including roles that
          // are enabled for quantities but not loaded for drawing.
          // Reducer eligibility is controlled exclusively by the configured
          // series role; drawing mode or product name must not enable it.
          final reductionSeriesForGlass =
              window.activeSlidingSeries ?? window.activeSeries;
          // A reducer is never inferred from a product name or from missing
          // role metadata. It is valid only when the active series explicitly
          // assigns one of its own sections to the reducer role.
          final bool reducerAllowed =
              reductionSeriesForGlass != null &&
              window.seriesUsesReducer(reductionSeriesForGlass);

          void addReducteurPieces(int multiplier) {
            hasSimpleGlassReducerPieces = true;
            for (int q = 0; q < multiplier; q++) {
              reducteurPieces.add(cellGw / 1000.0);
              reducteurPieces.add(cellGw / 1000.0);
              reducteurPieces.add(cellGh / 1000.0);
              reducteurPieces.add(cellGh / 1000.0);
            }
          }

          void addSlidingBourrageJoint() {
            if (cellGlass.fittedJoints.isNotEmpty) return;
            // PVC sliding glazing uses its dedicated gasket rules; the
            // aluminium Bourrage profile must never be added to its BOM.
            if (isPvcSlidingSystem) return;
            final double perimeter = (cellGw * 2 + cellGh * 2) / 1000.0;
            final double sides = cellGlass.jointTwoSides ? 2.0 : 1.0;
            final double qty = perimeter * sides * totalPieces;
            // A sliding system uses Bourrage only. The catalogue rule for
            // `joint_bourrage` decides whether this physical demand appears;
            // do not introduce opening-only gasket roles here.
            const jointName = 'جوان البوراج (Joint Bourrage)';
            slidingGlassJoints[jointName] =
                (slidingGlassJoints[jointName] ?? 0.0) + qty;

            final sash =
                window.slidingSashOverride ??
                window.getSlidingSectionByType('sash_sliding')?.toMap() ??
                window.getSlidingSectionByType('sash')?.toMap();
            final rawCapacity = sash?['max_glass_thickness'];
            final capacity = rawCapacity is num
                ? rawCapacity.toDouble()
                : double.tryParse(rawCapacity?.toString() ?? '') ?? 0.0;
            final glassThickness = cellGlass.structure == GlassStructure.double
                ? (cellGlass.thicknessOuter ?? 4.0) +
                      (cellGlass.thicknessInner ?? 4.0) +
                      cellGlass.intercallThickness
                : (cellGlass.thicknessOuter ?? 4.0);
            if (capacity > glassThickness) {
              final perSide = (capacity - glassThickness) / sides;
              slidingBourrageTargetThickness = math.max(
                slidingBourrageTargetThickness,
                perSide,
              );
            }
          }

          if (isSlidingSystem) {
            if (isPvcSlidingSystem && slidingHasGlazingBead) {
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
                slidingHasGlazingBead &&
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
              addSlidingBourrageJoint();
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
              // The sash itself defines the pocket when this series has no
              // parclose. Never invent a 24 mm parclose capacity here.
              // 🟢 الفراغ الصافي للزجاج: إذا استعملنا reducteur يصبح مجرى الزجاج 15 مم
              // Even when legacy BS90 data has no usable capacity value, the
              // physical glazing gasket still exists. Emit the demand and let
              // the enabled catalogue role choose its default thickness; when
              // capacity is available, addSlidingBourrageJoint records the
              // exact remaining thickness for the resolver.
              addSlidingBourrageJoint();
            }
          } else {
            // Opening glazing with parclose is counted below in the
            // simple/double Bourrage rows. Only a sash without parclose needs
            // this direct gasket demand; adding both doubles its consumption.
            if (usesOpeningSashProfile &&
                openingSashSkipsGlazingBead &&
                cellGlass.fittedJoints.isEmpty &&
                !window.isPVC &&
                !isPanneau &&
                cellGlass.structure != GlassStructure.closed) {
              final double perimeter = (cellGw * 2 + cellGh * 2) / 1000.0;
              final double mult = cellGlass.jointTwoSides ? 2.0 : 1.0;
              final double gasketQty = perimeter * mult * totalPieces;
              String gName = 'جوان البوراج (Joint Bourrage)';
              openingGlassJoints[gName] =
                  (openingGlassJoints[gName] ?? 0.0) + gasketQty;
            }
            if (usesOpeningSashProfile && openingSashSkipsGlazingBead) {
              // This sash profile is explicitly configured without parclose.
              if (reducerAllowed &&
                  cellGlass.structure == GlassStructure.simple) {
                addReducteurPieces(pieceMultiplier);
              }
            } else if (needsDoubleParclose) {
              maxOpeningDoubleGlassPackThickness = math.max(
                maxOpeningDoubleGlassPackThickness,
                rawCellGlassPackThickness,
              );
              requiredOpeningParcloseDoubleThickness = math.max(
                requiredOpeningParcloseDoubleThickness,
                cellThick,
              );
              for (int q = 0; q < pieceMultiplier; q++) {
                addOpeningParcloseRect(
                  isDouble: true,
                  widthMm: cellGw,
                  heightMm: cellGh,
                );
              }
            } else {
              maxOpeningSimpleGlassPackThickness = math.max(
                maxOpeningSimpleGlassPackThickness,
                rawCellGlassPackThickness,
              );
              for (int q = 0; q < pieceMultiplier; q++) {
                addOpeningParcloseRect(
                  isDouble: false,
                  widthMm: cellGw,
                  heightMm: cellGh,
                );
              }
              if (reducerAllowed &&
                  cellGlass.structure == GlassStructure.simple) {
                addReducteurPieces(pieceMultiplier);
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
                pieceCount: totalPieces,
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
                pieceCount: totalPieces,
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

        // Fixed zone with slanted mullions: one glass per cell. The glass is
        // the clear cell less the usual 5 mm per side; it is ordered by its
        // real shape and priced as the rectangle along its longest side.
        if (zone.slantedDividers.isNotEmpty &&
            zone.content == ZoneContent.fixedGlass &&
            !isRightSash) {
          final cells = window.slantedGeometryFor(zone).cells();
          for (var i = 0; i < cells.length; i++) {
            final glass = SlantedDivisionGeometry.insetConvex(
              cells[i],
              videVerre / 2,
            );
            if (glass.length < 3) continue;
            final rect = SlantedDivisionGeometry.pricingRectangle(glass);
            final before = glassItems.length;
            shapedGlassCell = glass;
            try {
              addSingleGlassPiece(
                rect.width,
                rect.height,
                multiplier,
                'slant_cell_$i',
              );
            } finally {
              shapedGlassCell = null;
            }
            if (glassItems.length > before) {
              final sides = [
                for (var k = 0; k < glass.length; k++)
                  (glass[(k + 1) % glass.length] - glass[k]).distance
                      .toStringAsFixed(0),
              ].join(' / ');
              final corners = [
                for (var k = 0; k < glass.length; k++)
                  '${SlantedDivisionGeometry.interiorAngleDeg(glass, k).toStringAsFixed(1)}°',
              ].join(' / ');
              final last = glassItems.removeLast();
              glassItems.add(
                last.copyWith(
                  name:
                      '${last.name}\n- Forme / الشكل: ${glass.length} أضلاع '
                      '($sides مم) — $corners',
                ),
              );
            }
          }
          return;
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
      // Location labels (main/secondary sash or zone names) must not split
      // identical panels into separate rows. Keep genuinely different panel
      // products/types/colours separate, but aggregate the same material when
      // its cut dimensions and price are identical.
      final panneauIdentity = g.category == 'panneau'
          ? _panelAggregationIdentity(g)
          : '';
      String key =
          '${g.originalName}_'
          '${g.category == 'panneau' ? panneauIdentity : ''}_'
          '${g.length?.toStringAsFixed(1)}_'
          '${g.glassHeight?.toStringAsFixed(1)}_'
          '${g.unit}_'
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
          pieceCount: (existing.pieceCount ?? 0) + (g.pieceCount ?? 0),
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
    items.addAll(
      mergedGlass.values.map((glass) {
        final count = glass.pieceCount;
        if (count == null) return glass;
        return glass.copyWith(
          name: '${glass.name}\n- Quantité / الكمية: $count',
        );
      }),
    );

    // Sliding glass gaskets are discovered while glass cells are calculated,
    // so they must be appended after the glass loop.  The earlier accessory
    // section runs before this data exists.
    final pendingSlidingBourrageJoints = slidingGlassJoints.entries
        .where((entry) => _selectorTypeForJoint(entry.key) == 'joint bourrage')
        .toList();
    final modelQuantity = window.quantity <= 0 ? 1 : window.quantity;
    for (final entry in openingGlassJoints.entries) {
      if (entry.value > 0) {
        items.add(
          createJoint(entry.key, qty: entry.value / modelQuantity, unit: 'متر'),
        );
      }
    }
    for (final entry in pendingSlidingBourrageJoints) {
      if (entry.value > 0) {
        items.add(
          createJoint(
            entry.key,
            sliding: true,
            qty: entry.value / modelQuantity,
            unit: 'متر',
            // Bourrage fills the remaining groove after the actual glass
            // pack. If legacy data has no capacity, the enabled role's
            // default remains a valid fallback.
            targetThicknessMm: slidingBourrageTargetThickness > 0
                ? slidingBourrageTargetThickness
                : null,
          ),
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
      final configuredSections = window.getConfiguredSectionsForRole(
        'glazing_bead',
        useSlidingSeries: window.activeSlidingSeries?.id == series.id,
      );
      final configuredSimpleSections = window.getConfiguredSectionsForRole(
        'glazing_bead',
        useSlidingSeries: window.activeSlidingSeries?.id == series.id,
        showWhenGlass: 'simple',
      );
      final configuredDoubleSections = window.getConfiguredSectionsForRole(
        'glazing_bead',
        useSlidingSeries: window.activeSlidingSeries?.id == series.id,
        showWhenGlass: 'double',
      );
      // A configured role is authoritative. Only legacy series with no role
      // rows may use the historical code/type fallback below.
      if (configuredSections.isEmpty &&
          window.seriesHasConfiguredRoles(series)) {
        return {'simple': null, 'double': null};
      }
      final configuredIds = configuredSections
          .map((section) => section.id)
          .toSet();
      bool isParcloseSection(AluminumSection section) {
        final type = section.type.toLowerCase();
        final name = section.name.toLowerCase();
        final roleAllowsSection =
            configuredSections.isEmpty || configuredIds.contains(section.id);
        return roleAllowsSection &&
            (section.code.trim() == '514' ||
                type.contains('parclose') ||
                name.contains('parclose') ||
                type.contains('باكيت') ||
                name.contains('باكيت'));
      }

      final bool beadSliding = window.activeSlidingSeries?.id == series.id;
      AluminumSection? findSimpleParclose() {
        // The bead the drawer shows: the smallest one holding the pack.
        final fitted = window.glazingBeadForGlass(
          const GlassSpecification(structure: GlassStructure.simple),
          sliding: beadSliding,
          glassThickness: beadSliding
              ? null
              : (maxOpeningSimpleGlassPackThickness > 0
                    ? maxOpeningSimpleGlassPackThickness
                    : null),
        );
        if (fitted != null) return fitted;
        final allowedIds = configuredSimpleSections
            .map((section) => section.id)
            .toSet();
        final candidates = series.sections
            .where(
              (section) =>
                  isParcloseSection(section) &&
                  (configuredSections.isEmpty ||
                      allowedIds.contains(section.id)),
            )
            .toList();
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
        final fitted = window.glazingBeadForGlass(
          const GlassSpecification(structure: GlassStructure.double),
          sliding: beadSliding,
          glassThickness: requiredDoubleThickness > 0
              ? requiredDoubleThickness
              : null,
        );
        if (fitted != null) return fitted;
        final minimumCapacity = math.max(10.0, requiredDoubleThickness);
        final allowedIds = configuredDoubleSections
            .map((section) => section.id)
            .toSet();
        final candidates =
            series.sections
                .where(
                  (section) =>
                      isParcloseSection(section) &&
                      (configuredSections.isEmpty ||
                          allowedIds.contains(section.id)) &&
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
                      (configuredSections.isEmpty ||
                          allowedIds.contains(section.id)) &&
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
                (s) =>
                    configuredIds.contains(s.id) &&
                    s.id.toString() == chosenId.toString(),
              ));

      Map<String, dynamic>? simple;
      Map<String, dynamic>? doubled;
      if (chosenParclose != null && chosenBelongsToSeries) {
        final double maxG =
            (chosenParclose['max_glass_thickness'] as num?)?.toDouble() ?? 0.0;
        if (maxG > 10.0 && maxG >= requiredDoubleThickness) {
          // A saved bead is used for double glazing only when it is the bead
          // that holds the double pack; a large simple bead is not a double.
          final doubleSection = findDoubleParclose();
          doubled = doubleSection == null
              ? pricedOverride(chosenParclose)
              : pricedMap(doubleSection);
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
              if (configuredIds.contains(linkedSec.id) &&
                  linkedSec.maxGlassThickness >= requiredDoubleThickness) {
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

    Map<String, dynamic>? validParcloseOverride(
      Map<String, dynamic>? candidate,
      AluminumSeries? series, {
      required bool sliding,
      required String glassRule,
    }) {
      if (candidate == null || series == null) return null;
      final rawId = candidate['id'];
      final id = rawId is num
          ? rawId.toInt()
          : int.tryParse(rawId?.toString() ?? '');
      if (id == null || !series.sections.any((section) => section.id == id)) {
        return null;
      }
      final configured = window.getConfiguredSectionsForRole(
        'glazing_bead',
        useSlidingSeries: sliding,
        showWhenGlass: glassRule,
      );
      if (window.seriesHasConfiguredRoles(series) &&
          !configured.any((section) => section.id == id)) {
        return null;
      }
      return candidate;
    }

    final selectedParcloseSimple = validParcloseOverride(
      overrideMap('باكيت زجاج مفرد (Parclose Simple)'),
      window.activeSeries,
      sliding: false,
      glassRule: 'simple',
    );
    final selectedParcloseDouble = validParcloseOverride(
      overrideMap('باكيت زجاج مزدوج (Parclose Double)'),
      window.activeSeries,
      sliding: false,
      glassRule: 'double',
    );
    final selectedSlidingParcloseSimple = validParcloseOverride(
      overrideMap('باكيت زجاج منزلق مفرد (Parclose Simple Coulissant)'),
      window.activeSlidingSeries,
      sliding: true,
      glassRule: 'simple',
    );
    final selectedSlidingParcloseDouble = validParcloseOverride(
      overrideMap('باكيت زجاج منزلق مزدوج (Parclose Double Coulissant)'),
      window.activeSlidingSeries,
      sliding: true,
      glassRule: 'double',
    );

    bool genericParcloseMatches({required bool doubleGlass}) {
      final maxGlass =
          (chosenParclose?['max_glass_thickness'] as num?)?.toDouble() ?? 0.0;
      return chosenParclose != null &&
          (doubleGlass ? maxGlass > 10.0 : maxGlass <= 10.0);
    }

    // Aluminium only: a 90° parclose cut keeps one direction at the inner
    // glazing size and shortens the other by the parclose glass deduction on
    // both ends. A 45° cut (and every PVC window) keeps the mitred lengths.
    // The gasket perimeters below still use the unshortened lists.
    List<double> parclosePiecesForCut(
      List<double> pieces,
      List<bool?> isWidth,
      Map<String, dynamic>? parclose,
    ) {
      if (window.isPVC || !window.parcloseCutAt90 || parclose == null) {
        return pieces;
      }
      final rawDeduction = parclose['glass_deduction'];
      final deductionMm = rawDeduction is num
          ? rawDeduction.toDouble()
          : double.tryParse(rawDeduction?.toString() ?? '') ?? 0.0;
      if (deductionMm <= 0) return pieces;
      final bool shortenWidth = window.parcloseCutMode == '90_length';
      final double cut = 2 * deductionMm / 1000.0;
      return [
        for (var i = 0; i < pieces.length; i++)
          (i < isWidth.length && isWidth[i] == shortenWidth)
              ? math.max(0.0, pieces[i] - cut)
              : pieces[i],
      ];
    }

    if (parcloseSimplePieces.isNotEmpty) {
      final targetOverride =
          selectedParcloseSimple ??
          parcloseSimple ??
          (genericParcloseMatches(doubleGlass: false)
              ? validParcloseOverride(
                  chosenParclose,
                  window.activeSeries,
                  sliding: false,
                  glassRule: 'simple',
                )
              : null);
      items.add(
        createProfile(
          targetOverride == null
              ? 'لا توجد Parclose Simple مناسبة لهذا الزجاج'
              : 'باكيت زجاج مفرد (Parclose Simple)',
          colorName,
          pieces: parclosePiecesForCut(
            parcloseSimplePieces,
            parcloseSimpleIsWidth,
            targetOverride,
          ),
          pieceCutAngles: hasShapedParclose ? parcloseSimpleAngles : null,
          unit: 'قطاع',
          overrideMap: targetOverride,
          selectorType: 'parclose_simple',
          ignoreSavedOverride: true,
        ),
      );
    }

    if (parcloseDoublePieces.isNotEmpty) {
      final targetOverride =
          selectedParcloseDouble ??
          parcloseDouble ??
          (genericParcloseMatches(doubleGlass: true)
              ? validParcloseOverride(
                  chosenParclose,
                  window.activeSeries,
                  sliding: false,
                  glassRule: 'double',
                )
              : null);
      items.add(
        createProfile(
          targetOverride == null
              ? 'لا توجد Parclose Double مناسبة لهذا الزجاج'
              : 'باكيت زجاج مزدوج (Parclose Double)',
          colorName,
          pieces: parclosePiecesForCut(
            parcloseDoublePieces,
            parcloseDoubleIsWidth,
            targetOverride,
          ),
          pieceCutAngles: hasShapedParclose ? parcloseDoubleAngles : null,
          unit: 'قطاع',
          overrideMap: targetOverride,
          selectorType: 'parclose_double',
          ignoreSavedOverride: true,
        ),
      );
    }

    if (slidingParcloseSimplePieces.isNotEmpty) {
      final targetOverride =
          selectedSlidingParcloseSimple ??
          slidingParcloseSimple ??
          (genericParcloseMatches(doubleGlass: false)
              ? validParcloseOverride(
                  chosenParclose,
                  window.activeSlidingSeries,
                  sliding: true,
                  glassRule: 'simple',
                )
              : null);
      items.add(
        createProfile(
          targetOverride == null
              ? 'لا توجد Parclose Simple منزلقة مناسبة لهذا الزجاج'
              : 'باكيت زجاج منزلق مفرد (Parclose Simple Coulissant)',
          colorName,
          pieces: slidingParcloseSimplePieces,
          unit: 'قطاع',
          overrideMap: targetOverride,
          selectorType: 'sliding_parclose_simple',
          ignoreSavedOverride: true,
        ),
      );
    }

    if (slidingParcloseDoublePieces.isNotEmpty) {
      final targetOverride =
          selectedSlidingParcloseDouble ??
          slidingParcloseDouble ??
          (genericParcloseMatches(doubleGlass: true)
              ? validParcloseOverride(
                  chosenParclose,
                  window.activeSlidingSeries,
                  sliding: true,
                  glassRule: 'double',
                )
              : null);
      items.add(
        createProfile(
          targetOverride == null
              ? 'لا توجد Parclose Double منزلقة مناسبة لهذا الزجاج'
              : 'باكيت زجاج منزلق مزدوج (Parclose Double Coulissant)',
          colorName,
          pieces: slidingParcloseDoublePieces,
          unit: 'قطاع',
          overrideMap: targetOverride,
          selectorType: 'sliding_parclose_double',
          ignoreSavedOverride: true,
        ),
      );
    }

    double maxGlassCapacity(Map<String, dynamic>? profile) {
      return (profile?['max_glass_thickness'] as num?)?.toDouble() ?? 0.0;
    }

    final double vitrageJointThick = window.isPVC
        ? 0.0
        : window.selectedVitrageJointThickness(fallback: 2.0);

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
      final double simplePerim =
          parcloseSimplePieces.fold(0.0, (s, p) => s + p) -
          fittedSimplePerimeter; // Fitted cells already carry exact gasket rows.
      final double doublePerim =
          parcloseDoublePieces.fold(0.0, (s, p) => s + p) -
          fittedDoublePerimeter;
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
            'جوان سنترال (Joint Central)',
            qty: swingCentralFramePerim,
            unit: 'متر',
            selectorTypeOverride: 'joint_central',
            roleKeyOverride: 'joint_central',
          ),
        );
      }
    }

    // A mixed drawing may contain both simple and double glazing. Reducer
    // pieces are accumulated only for the simple-glass cells above, so the
    // presence of a separate double-glass cell must not hide those pieces.
    final bool hasReducerDemand =
        hasSimpleGlassReducerPieces && window.hasSimpleGlassForReducer;

    if (reducteurPieces.isNotEmpty && hasReducerDemand) {
      Map<String, dynamic>? reducteurOverride =
          window.componentOverrides['ريديكتور (Réducteur)'] ??
          window.componentOverrides['مخفض الزجاج (Réducteur)'];

      // Reducer demand is produced by sliding cells. In a mixed drawing the
      // outer frame belongs to the opening series, but Réducteure must still
      // be resolved against the selected sliding series.
      final reductionSeries = window.activeSlidingSeries ?? window.activeSeries;
      final configuredReducers = reductionSeries == null
          ? const <AluminumSection>[]
          : window.getConfiguredSectionsForRole(
              'reducer',
              useSlidingSeries:
                  window.activeSlidingSeries?.id == reductionSeries.id,
            );
      final configuredReducerIds = configuredReducers
          .map((section) => section.id)
          .toSet();
      final rawReducerId = reducteurOverride?['id'];
      final reducerId = rawReducerId is num
          ? rawReducerId.toInt()
          : int.tryParse(rawReducerId?.toString() ?? '');
      if (reducerId == null || !configuredReducerIds.contains(reducerId)) {
        reducteurOverride = configuredReducers.isEmpty
            ? null
            : window.sectionMapWithSelectedColorPrice(configuredReducers.first);
      }
      final bool reducerAllowedForSeries =
          reductionSeries != null && reducteurOverride != null;

      // The selected reducer must be one of the sections explicitly assigned
      // to this series. A stale manual selection from another series is never
      // allowed to leak into the BOM.
      if (reducerAllowedForSeries) {
        items.add(
          createProfile(
            'ريديكتور (Réducteur)',
            colorName,
            pieces: reducteurPieces,
            unit: 'قطاع',
            overrideMap: reducteurOverride,
            selectorType: '67114',
            roleKey: 'reducer',
            ignoreSavedOverride: true,
          ),
        );
      }
    }

    // =========================================================================
    // --- 4.6 البارداج كبروفيل (Bardage Profile) ---
    // =========================================================================
    if (bardagePiecesByColor.isNotEmpty && bardageProfileOverride() != null) {
      final rawBardageOverride = bardageProfileOverride();
      final usesSpecificBardageRole =
          window.componentOverrides['البارداج (Bardage)'] is Map;
      for (final entry in bardagePiecesByColor.entries) {
        final selectedName = bardageColorNames[entry.key] ?? colorName;
        final selectedColor = bardageColorData[entry.key];
        final pricedOverride = Map<String, dynamic>.from(rawBardageOverride!);
        pricedOverride['calculated_price'] = usesSpecificBardageRole
            ? window.getBardagePriceForColor(selectedColor, selectedName)
            : window.getPanneauProfilePriceForColor(
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
            // pricedOverride is the saved bardage selection with this
            // colour's price. Merging the saved selection over it again
            // restored one colour's price on every colour row.
            ignoreSavedOverride: usesSpecificBardageRole,
            priceByWholeBar: true,
            roleKey: usesSpecificBardageRole ? 'bardage' : 'panneau',
            selectorType: usesSpecificBardageRole ? 'bardage' : 'panneau',
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

    // Triangle is a profile, not an accessory.  A profile is generated only
    // when the accessory selected in the rules explicitly links to it.  This
    // also lets each accessory use its own quantity, deduction and cut point.
    // Cremone is handled above because its cut must follow the handle drawn on
    // every sash; all other linked accessories use the same configurable rule
    // with the real number of accessories already present in the BOM.
    final triangleProfileRows = <BomItem>[];
    final triangleProfileKeys = <String>{};
    final slidingSeriesId = window.activeSlidingSeries?.id;

    double triangleRuleNumber(Map<String, dynamic> rule, String key) {
      final value = rule[key];
      return value is num
          ? value.toDouble()
          : double.tryParse(value?.toString() ?? '') ?? 0.0;
    }

    Map<String, dynamic>? triangleRuleForAccessory(String key) {
      final direct = window.componentOverrides[key];
      if (direct is Map) return Map<String, dynamic>.from(direct);

      // Espagnolettes are displayed with their calculated size (30, 40,
      // 180…), whereas their rule is stored under the single base accessory.
      if (_textHasAny(key, const [
        'اسبانيوليت',
        'إسبانيوليت',
        'espagnolette',
      ])) {
        final canonical =
            window.componentOverrides['إسبانيوليت (Espagnolette)'] ??
            window.componentOverrides['اسبانيولات المنزلق (Espagnolette)'];
        if (canonical is Map) return Map<String, dynamic>.from(canonical);
      }
      return null;
    }

    // Expanded kits do not keep a visible parent row in [items].  Add an
    // internal source for the three locking kits so a Triangle rule assigned
    // to the kit itself still applies without adding a duplicate kit row.
    final triangleSources = List<BomItem>.from(items);
    void addExpandedKitTriangleSource(
      String key, {
      required bool active,
      required int count,
    }) {
      final hasDirectRow = triangleSources.any(
        (item) => item.overrideKey == key && item.isActive,
      );
      final hasExpandedKit = items.any(
        (item) => item.kitGroupName == key && item.isActive,
      );
      if (!active || hasDirectRow || !hasExpandedKit) return;
      triangleSources.add(
        BomItem(
          category: 'accessory',
          originalName: key,
          name: key,
          quantity: math.max(1, count).toDouble() * window.quantity,
          unit: 'حبة',
          unitPrice: 0,
          overrideKey: key,
        ),
      );
    }

    addExpandedKitTriangleSource(
      'System OB',
      active: isSystemObActive,
      count: 1,
    );
    addExpandedKitTriangleSource(
      'Demi System OB',
      active: isDemiObActive,
      count: 1,
    );
    addExpandedKitTriangleSource(
      'Verrou Central',
      active: isVerrouCentralActive,
      count: doubleSashCount,
    );

    for (final accessory in triangleSources) {
      if (accessory.category != 'accessory' ||
          !accessory.isActive ||
          accessory.quantity <= 0) {
        continue;
      }
      final key = accessory.overrideKey ?? accessory.originalName;
      final rule = triangleRuleForAccessory(key);
      if (rule == null) continue;
      final mode = '${rule['triangle_link_mode'] ?? 'none'}'.toLowerCase();
      if (mode != 'required' &&
          !(mode == 'optional' && window.useOptionalTriangle)) {
        continue;
      }
      // The cremone row above has the exact drawing-run calculation.
      if (_textHasAny(key, const ['كريمون', 'cremone', 'crémone'])) {
        continue;
      }

      final bool sliding =
          slidingSeriesId != null &&
          accessory.sourceSeriesId == slidingSeriesId;
      final triangleProfile =
          window
              .getConfiguredSectionForRole(
                'triangle',
                useSlidingSeries: sliding,
              )
              ?.toMap() ??
          (sliding
                  ? (window.getSlidingSectionByType('triangle') ??
                        window.getSectionByType('triangle'))
                  : (window.getSectionByType('triangle') ??
                        window.getSlidingSectionByType('triangle')))
              ?.toMap();
      if (triangleProfile == null) continue;

      final int multiplier = math
          .max(1, triangleRuleNumber(rule, 'triangle_quantity').round())
          .toInt();
      final int baseAccessoryCount = math
          .max(1, (accessory.quantity / math.max(1, window.quantity)).round())
          .toInt();
      final double deduction = math
          .max(0.0, triangleRuleNumber(rule, 'triangle_deduction_mm'))
          .toDouble();
      final positionMode = '${rule['triangle_position_mode'] ?? 'center'}'
          .toLowerCase();
      final pieces = <double>[];
      final cutPairs = <String>[];
      final sourceRuns = triangleDrawingRuns.isEmpty
          ? <Map<String, double>>[
              {'height_mm': math.max(0.0, window.height.toDouble())},
            ]
          : triangleDrawingRuns;

      final bool isObAccessory =
          key.contains('OB') || accessory.originalName.contains('OB');
      final bool isVerrouAccessory = _textHasAny(key, const [
        'فيلرو',
        'فيرو',
        'verrou',
        'Verrou',
      ]);
      final double rawUpperVerrou = triangleRuleNumber(rule, 'verrou_upper_mm');
      final double rawLowerVerrou = triangleRuleNumber(rule, 'verrou_lower_mm');
      final double rawWidthDeduction = triangleRuleNumber(
        rule,
        'triangle_width_deduction_mm',
      );

      for (var index = 0; index < baseAccessoryCount * multiplier; index++) {
        final run = sourceRuns[index % sourceRuns.length];
        final double total = math
            .max(
              0.0,
              (run['height_mm'] ?? window.height.toDouble()) - deduction,
            )
            .toDouble();

        double first;
        double second;

        if (isVerrouAccessory && (rawUpperVerrou > 0 || rawLowerVerrou > 0)) {
          final upOff = rawUpperVerrou > 0 ? rawUpperVerrou : 50.0;
          final lowOff = rawLowerVerrou > 0 ? rawLowerVerrou : 30.0;
          first = math.max(0.0, (total / 2.0) - upOff).toDouble();
          second = math.max(0.0, (total / 2.0) - lowOff).toDouble();
        } else if (positionMode == 'offset') {
          first = triangleRuleNumber(
            rule,
            'triangle_position_mm',
          ).clamp(0.0, total).toDouble();
          second = math.max(0.0, total - first).toDouble();
        } else {
          first = total / 2.0;
          second = math.max(0.0, total - first).toDouble();
        }
        pieces.addAll([first / 1000.0, second / 1000.0]);

        if (isObAccessory) {
          final sashW =
              run['width_mm'] ??
              (window.width.toDouble() / math.max(1, baseAccessoryCount));
          final double autoObWidthDeduction = sashW <= 650.0
              ? 180.0
              : (sashW <= 1000.0 ? 280.0 : 380.0);
          final double effectiveWidthDeduction = rawWidthDeduction > 0
              ? rawWidthDeduction
              : (deduction > 0 ? deduction : autoObWidthDeduction);
          final double third = math
              .max(0.0, sashW - effectiveWidthDeduction)
              .toDouble();
          if (third > 0) {
            pieces.add(third / 1000.0);
            cutPairs.add(' +  +  (أفقي)');
          } else {
            cutPairs.add(' + ');
          }
        } else {
          cutPairs.add(' + ');
        }
      }
      if (pieces.isEmpty) continue;

      final uniqueKey =
          '${accessory.catalogItemId ?? key}:${sliding ? 's' : 'o'}';
      if (!triangleProfileKeys.add(uniqueKey)) continue;
      triangleProfileRows.add(
        createProfile(
          'تراينغل - ${accessory.originalName}',
          colorName,
          pieces: pieces,
          pieceCutAngles: uniformAngles(pieces, '90/90'),
          unit: 'قطاع',
          overrideMap: triangleProfile,
          preferOverrideMap: true,
          selectorType: sliding ? 'triangle_sliding' : 'triangle',
          roleKey: 'triangle',
        ).copyWith(cuttingList: 'قطع القص: ${cutPairs.join(' ؛ ')} مم'),
      );
    }
    items.addAll(triangleProfileRows);

    // A catalogue accessory may require any other accessory, not only a
    // strike or a screw. Expand that explicit relation once for every source
    // row. Espagnolette strikes keep their dedicated simple/double drawing
    // role above.
    final linkedAccessoryRows = <BomItem>[];
    for (final sourceItem in List<BomItem>.from(items)) {
      final sourceRole = (sourceItem.roleKey ?? sourceItem.selectorType ?? '')
          .trim()
          .toLowerCase();
      if (sourceItem.category != 'accessory' ||
          sourceItem.roleKey == 'espagnolette' ||
          const {
            'kit',
            'sliding_kit',
            'sliding_kit_40000',
            'sliding_kit_67000',
            'clam',
            'clamp',
            'sliding_clamp',
            'frame_clamp',
            'sash_clamp',
          }.contains(sourceRole)) {
        continue;
      }
      final rawSource =
          window.componentOverrides[sourceItem.overrideKey] ??
          window.componentOverrides[sourceItem.originalName];
      if (rawSource is! Map) continue;
      if (rawSource['linked_accessories'] is List &&
          (rawSource['linked_accessories'] as List).isNotEmpty) {
        continue;
      }
      final linked = rawSource['linked_accessory'];
      if (linked is! Map || linked['id'] == null) continue;
      final rawCount = rawSource['linked_accessory_count'];
      final count = rawCount is num
          ? rawCount.toInt()
          : int.tryParse(rawCount?.toString() ?? '') ?? 0;
      if (count <= 0 || sourceItem.quantity <= 0) continue;
      final linkedId = linked['id'] is num
          ? (linked['id'] as num).toInt()
          : int.tryParse(linked['id'].toString());
      if (linkedId == null) continue;
      final linkedName =
          'أكسسوار مرتبط: ${linked['name'] ?? 'Accessory $linkedId'}';
      final linkedKey =
          'linked-accessory:${sourceItem.catalogItemId}:$linkedId';
      final relatedOverrides = Map<String, dynamic>.from(
        window.componentOverrides,
      )..[linkedKey] = Map<String, dynamic>.from(linked);
      linkedAccessoryRows.add(
        _createAccessory(
          relatedOverrides,
          linkedName,
          qty: count * sourceItem.quantity.round(),
          overrideKey: linkedKey,
          catalogItemId: linkedId,
          colorId: catalogueColorId(accessoryColorName, accessory: true),
          selectorCategory: 'accessory',
          selectorType: _selectorTypeForAccessory(
            linked['name']?.toString() ?? '',
          ),
          roleKey: _roleKeyForAccessorySelector(
            _selectorTypeForAccessory(linked['name']?.toString() ?? ''),
          ),
          sourceSeriesId: sourceItem.sourceSeriesId,
          materialType: sourceItem.materialType,
        ),
      );
    }
    items.addAll(linkedAccessoryRows);

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
            // The BOM item records the series that produced it. This is
            // essential for mixed drawings: an opening sash/frame and a
            // sliding sash may have the same semantic type but different
            // catalogue images and dimensions.
            final bool itemUsesSlidingSeries =
                window.systemMode == 'sliding' ||
                (item.sourceSeriesId != null &&
                    item.sourceSeriesId == window.activeSlidingSeries?.id);
            final sec = itemUsesSlidingSeries
                ? window.getSlidingSectionByType(type)
                : window.getSectionByType(type);
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

    items = _mergeIdenticalJoints(items);
    items = _mergeIdenticalSideCoverProfiles(items);
    items = _mergeIdenticalProfiles(items);

    if (window.isShutterOnly) {
      return items.where((item) => item.category == 'shutter').toList();
    }
    return items;
  }

  /// دمج الجوانات المتطابقة (من نفس النوع ونفس الكود/المعرف) في سطر واحد
  /// مع جمع أطوالها وكميات إطاراتها، بينما الجوانات ذات الأكواد المختلفة
  /// (مثل 52 0 34 مقابل 52 0 35) تبقى منفصلة.
  static List<BomItem> _mergeIdenticalJoints(List<BomItem> items) {
    if (items.isEmpty) return items;

    final result = <BomItem>[];
    final jointGroups = <String, List<BomItem>>{};
    final jointFirstIndex = <String, int>{};

    for (final item in items) {
      if (item.category != 'joint') {
        result.add(item);
        continue;
      }

      final normalizedCode = (item.profileCode ?? '')
          .replaceAll(RegExp(r'\s+'), '')
          .trim()
          .toUpperCase();
      final catId = item.catalogItemId;
      final color = (item.colorName ?? '').trim();
      final unit = item.unit.trim().toLowerCase();

      String key;
      if (catId != null && catId > 0) {
        key = 'id:' + catId.toString() + ':' + color + ':' + unit;
      } else if (normalizedCode.isNotEmpty) {
        key = 'code:' + normalizedCode + ':' + color + ':' + unit;
      } else {
        key =
            'name:' +
            item.originalName.trim().toLowerCase() +
            ':' +
            color +
            ':' +
            unit;
      }

      if (!jointGroups.containsKey(key)) {
        jointGroups[key] = [];
        jointFirstIndex[key] = result.length;
        result.add(item);
      }
      jointGroups[key]!.add(item);
    }

    for (final entry in jointGroups.entries) {
      final key = entry.key;
      final group = entry.value;
      final insertIndex = jointFirstIndex[key]!;

      if (group.length == 1) {
        result[insertIndex] = group.first;
        continue;
      }

      final first = group.first;
      double totalExact = 0.0;
      double totalQty = 0.0;
      final allPieces = <double>[];
      final roleNames = <String>[];
      String? catalogLine;

      for (final item in group) {
        final exact = item.exactQuantity ?? item.quantity;
        totalExact += exact;
        totalQty += item.quantity;
        if (item.pieces != null) {
          allPieces.addAll(item.pieces!);
        }

        final lines = item.name.split('\n');
        final role = lines.isNotEmpty ? lines[0].trim() : item.originalName;
        if (role.isNotEmpty && !roleNames.contains(role)) {
          roleNames.add(role);
        }

        if (catalogLine == null && lines.length > 1) {
          for (var i = 1; i < lines.length; i++) {
            final l = lines[i].trim();
            if (!l.contains('المطلوب الفعلي')) {
              catalogLine = l;
              break;
            }
          }
        }
      }

      totalExact = ((totalExact * 100).round()) / 100.0;
      final normalizedUnit = first.unit.toLowerCase().trim();
      final isLinear =
          normalizedUnit.contains('متر') ||
          normalizedUnit.contains('meter') ||
          normalizedUnit == 'm' ||
          normalizedUnit == 'ml';

      final finalQty = isLinear
          ? (totalExact <= 0 ? 0.0 : totalExact.ceilToDouble())
          : totalQty;

      final buffer = StringBuffer();
      buffer.write(roleNames.join(' + '));
      if (catalogLine != null && catalogLine.isNotEmpty) {
        buffer.write('\n' + catalogLine);
      }
      if (isLinear && totalExact > 0) {
        buffer.write(
          '\n(المطلوب الفعلي: ' +
              totalExact.toStringAsFixed(2) +
              ' ' +
              first.unit +
              ')',
        );
      }

      String? cuttingListText;
      if (allPieces.isNotEmpty) {
        final counts = <int, int>{};
        for (final p in allPieces) {
          final mm = (p * 1000).round();
          if (mm <= 0) continue;
          counts[mm] = (counts[mm] ?? 0) + 1;
        }
        final sortedMm = counts.keys.toList()..sort((a, b) => b.compareTo(a));
        final parts = <String>[];
        for (final mm in sortedMm) {
          parts.add(counts[mm].toString() + ' × ' + mm.toString() + ' مم');
        }
        cuttingListText = 'قطع القص: ' + parts.join(' ، ');
      }

      final merged = BomItem(
        category: 'joint',
        originalName: roleNames.join(' + '),
        profileCode: first.profileCode,
        name: buffer.toString(),
        imagePath: first.imagePath,
        colorName: first.colorName,
        length: first.length,
        quantity: finalQty,
        unit: first.unit,
        unitPrice: first.unitPrice,
        isMissing: group.every((item) => item.isMissing),
        isInteractive: first.isInteractive,
        isActive: group.any((item) => item.isActive),
        pieces: allPieces.isNotEmpty ? allPieces : null,
        cuttingList: cuttingListText ?? first.cuttingList,
        kitGroupName: first.kitGroupName,
        exactQuantity: totalExact,
        catalogItemId: first.catalogItemId,
        inventoryItemType: first.inventoryItemType,
        colorId: first.colorId,
        overrideKey: first.overrideKey,
        selectorCategory: first.selectorCategory,
        selectorType: first.selectorType,
        roleKey: first.roleKey,
        sourceSeriesId: first.sourceSeriesId,
        materialType: first.materialType,
        targetThicknessMm: first.targetThicknessMm,
      );

      result[insertIndex] = merged;
    }

    return result;
  }

  /// A single couvre-joint profile can be used by the outer frame, an inner
  /// sliding frame, and a custom side-cover layout.  Those calculation paths
  /// deliberately stay separate for geometry, but they are one stock profile
  /// in the quantity/cost table.  Merge them before the BOM reaches the
  /// resolver and optimise the combined cuts once.
  static List<BomItem> _mergeIdenticalSideCoverProfiles(List<BomItem> items) {
    bool isSideCover(BomItem item) {
      if (item.category != 'profile') return false;
      final role = (item.roleKey ?? item.selectorType ?? '')
          .trim()
          .toLowerCase();
      final name = '${item.originalName} ${item.name}'.toLowerCase();
      return role == 'side_cover' ||
          name.contains('couvre-joint') ||
          name.contains('couvre joint') ||
          name.contains('side cover') ||
          name.contains('الغطاء الجانبي');
    }

    final groups = <String, List<BomItem>>{};
    for (final item in items.where(isSideCover)) {
      final id = item.catalogItemId;
      if (id == null || id <= 0) continue;
      final color = (item.colorName ?? '').trim().toLowerCase();
      final unit = item.unit.trim().toLowerCase();
      groups.putIfAbsent('$id:$color:$unit', () => []).add(item);
    }
    if (groups.values.every((group) => group.length < 2)) return items;

    final mergedByFirst = <BomItem, BomItem>{};
    final absorbed = <BomItem>{};
    for (final group in groups.values.where((group) => group.length > 1)) {
      final first = group.first;
      final pieces = <double>[for (final item in group) ...?item.pieces];
      final pieceCutAngles = <String>[
        for (final item in group)
          for (var i = 0; i < (item.pieces?.length ?? 0); i++)
            if (item.pieceCutAngles != null && i < item.pieceCutAngles!.length)
              item.pieceCutAngles![i]
            else
              '',
      ];
      final roles = <String>[];
      for (final item in group) {
        final label = item.originalName.trim();
        if (label.isNotEmpty && !roles.contains(label)) roles.add(label);
      }

      final barLength = first.length ?? 0.0;
      final optimization = barLength > 0 && pieces.isNotEmpty
          ? optimizeCutting(pieces: pieces, barLength: barLength)
          : null;
      final exact =
          optimization?['exactBars'] as double? ??
          group.fold<double>(
            0.0,
            (total, item) => total + (item.exactQuantity ?? item.quantity),
          );
      final quantity = optimization?['optimizedBars'] as int?;
      final cuttingList = pieces.isEmpty
          ? first.cuttingList
          : 'قطع القص: ${_cuttingPiecesLabel(pieces)}';
      final catalogLines = first.name.split('\n');
      final catalogLabel = catalogLines.length > 1 ? catalogLines[1] : '';
      final displayName = [
        roles.join(' + '),
        if (catalogLabel.isNotEmpty) catalogLabel,
      ].join('\n');
      final productionNotes = group
          .map((item) => item.productionNote?.trim())
          .whereType<String>()
          .where((note) => note.isNotEmpty)
          .toSet();

      mergedByFirst[first] = BomItem(
        category: 'profile',
        originalName: roles.join(' + '),
        profileCode: first.profileCode,
        name: displayName,
        imagePath: first.imagePath,
        colorName: first.colorName,
        length: first.length,
        quantity:
            quantity?.toDouble() ??
            group.fold<double>(0.0, (total, item) => total + item.quantity),
        unit: first.unit,
        unitPrice: first.unitPrice,
        isMissing: group.every((item) => item.isMissing),
        isInteractive: first.isInteractive,
        isActive: group.any((item) => item.isActive),
        pieces: pieces.isEmpty ? null : pieces,
        pieceCutAngles: pieces.isEmpty ? null : pieceCutAngles,
        cuttingList: cuttingList,
        productionNote: productionNotes.isEmpty
            ? null
            : productionNotes.join('\n'),
        exactQuantity: exact,
        catalogItemId: first.catalogItemId,
        inventoryItemType: first.inventoryItemType,
        colorId: first.colorId,
        overrideKey: first.overrideKey,
        selectorCategory: first.selectorCategory,
        selectorType: first.selectorType,
        roleKey: first.roleKey,
        sourceSeriesId: first.sourceSeriesId,
        materialType: first.materialType,
      );
      absorbed.addAll(group.skip(1));
    }

    return [
      for (final item in items)
        if (!absorbed.contains(item)) mergedByFirst[item] ?? item,
    ];
  }

  /// دمج بروفيلات الألمنيوم المتطابقة (من نفس القطاع ونفس اللون ونفس الطول)
  /// مثل الإطار السفلي وإطار جهة بروفيل الزاوية أو أجزاء الحلق المختلفة،
  /// ليتم جمع قطع القص في سطر واحد وإعادة تحسين القص (Bar optimization) معاً.
  static List<BomItem> _mergeIdenticalProfiles(List<BomItem> items) {
    if (items.isEmpty) return items;

    bool isMergeableProfile(BomItem item) {
      if (item.category != 'profile') return false;
      final role = (item.roleKey ?? item.selectorType ?? '')
          .trim()
          .toLowerCase();
      final name = '${item.originalName} ${item.name}'.toLowerCase();
      if (role == 'side_cover' ||
          name.contains('couvre-joint') ||
          name.contains('couvre joint') ||
          name.contains('side cover') ||
          name.contains('الغطاء الجانبي')) {
        return false;
      }
      final id = item.catalogItemId;
      final code = item.profileCode?.trim() ?? '';
      return (id != null && id > 0) || code.isNotEmpty;
    }

    final groups = <String, List<BomItem>>{};
    for (final item in items.where(isMergeableProfile)) {
      final id = item.catalogItemId ?? 0;
      final code = (item.profileCode ?? '').trim().toLowerCase();
      final keyId = id > 0 ? 'id:$id' : 'code:$code';
      final color = (item.colorName ?? '').trim().toLowerCase();
      final unit = item.unit.trim().toLowerCase();
      final barLength = ((item.length ?? 0.0) * 100).round();
      groups.putIfAbsent('$keyId:$color:$unit:$barLength', () => []).add(item);
    }

    if (groups.values.every((group) => group.length < 2)) return items;

    final mergedByFirst = <BomItem, BomItem>{};
    final absorbed = <BomItem>{};

    for (final group in groups.values.where((group) => group.length > 1)) {
      final first = group.first;
      final pieces = <double>[for (final item in group) ...?item.pieces];
      final pieceCutAngles = <String>[
        for (final item in group)
          for (var i = 0; i < (item.pieces?.length ?? 0); i++)
            if (item.pieceCutAngles != null && i < item.pieceCutAngles!.length)
              item.pieceCutAngles![i]
            else
              '',
      ];
      final roles = <String>[];
      for (final item in group) {
        final lines = item.name.split('\n');
        final role = lines.isNotEmpty
            ? lines[0].trim()
            : item.originalName.trim();
        if (role.isNotEmpty && !roles.contains(role)) roles.add(role);
      }

      final barLength = first.length ?? 0.0;
      final optimization = barLength > 0 && pieces.isNotEmpty
          ? optimizeCutting(pieces: pieces, barLength: barLength)
          : null;
      final exact =
          optimization?['exactBars'] as double? ??
          group.fold<double>(
            0.0,
            (total, item) => total + (item.exactQuantity ?? item.quantity),
          );
      final quantity = optimization?['optimizedBars'] as int?;
      final cuttingList = pieces.isEmpty
          ? first.cuttingList
          : 'قطع القص: ${_cuttingPiecesLabel(pieces)}';

      final catalogLines = first.name.split('\n');
      String? catalogLabel;
      if (catalogLines.length > 1) {
        for (var i = 1; i < catalogLines.length; i++) {
          final l = catalogLines[i].trim();
          if (!l.contains('المطلوب الفعلي')) {
            catalogLabel = l;
            break;
          }
        }
      }

      final displayName = [
        roles.join(' + '),
        if (catalogLabel != null && catalogLabel.isNotEmpty) catalogLabel,
      ].join('\n');

      mergedByFirst[first] = BomItem(
        category: 'profile',
        originalName: roles.join(' + '),
        profileCode: first.profileCode,
        name: displayName,
        imagePath: first.imagePath,
        colorName: first.colorName,
        length: first.length,
        quantity:
            quantity?.toDouble() ??
            group.fold<double>(0.0, (total, item) => total + item.quantity),
        unit: first.unit,
        unitPrice: first.unitPrice,
        isMissing: group.every((item) => item.isMissing),
        isInteractive: first.isInteractive,
        isActive: group.any((item) => item.isActive),
        pieces: pieces.isEmpty ? null : pieces,
        pieceCutAngles: pieces.isEmpty ? null : pieceCutAngles,
        cuttingList: cuttingList,
        productionNote: first.productionNote,
        exactQuantity: exact,
        catalogItemId: first.catalogItemId,
        inventoryItemType: first.inventoryItemType,
        colorId: first.colorId,
        overrideKey: first.overrideKey,
        selectorCategory: first.selectorCategory,
        selectorType: first.selectorType,
        roleKey: first.roleKey,
        sourceSeriesId: first.sourceSeriesId,
        materialType: first.materialType,
        targetThicknessMm: first.targetThicknessMm,
      );
      absorbed.addAll(group.skip(1));
    }

    return [
      for (final item in items)
        if (!absorbed.contains(item)) mergedByFirst[item] ?? item,
    ];
  }

  static String _cuttingPiecesLabel(List<double> pieces) {
    final counts = <int, int>{};
    for (final piece in pieces) {
      final millimetres = (piece * 1000).round();
      if (millimetres > 0) {
        counts[millimetres] = (counts[millimetres] ?? 0) + 1;
      }
    }
    final lengths = counts.keys.toList()..sort((a, b) => b.compareTo(a));
    return lengths
        .map((length) => '${counts[length]} × $length مم')
        .join(' ، ');
  }

  /// دمج أسماء قطع الزجاج عند تشابه أبعادها:
  /// إذا كان الاسمان متطابقين → نبقيه كما هو.
  /// إذا كانا مختلفين (مثلاً ظلفة رئيسية / ثانوية) → نحذف التسمية ونبقي وصف الزجاج فقط.
  static String _mergeGlassName(String existingName, String newName) {
    if (existingName == newName) return existingName;

    final existingPanelMarker = existingName.indexOf('بانو (Panneau)');
    final newPanelMarker = newName.indexOf('بانو (Panneau)');
    if (existingPanelMarker >= 0 && newPanelMarker >= 0) {
      // Both rows already passed the strict panel identity key. Display the
      // common material description without a misleading zone/sash label.
      return existingName.substring(existingPanelMarker);
    }

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

  static String _panelAggregationIdentity(BomItem item) {
    var description = item.name;
    // Panel descriptions are preceded by an optional location label. Strip
    // that prefix so two equal cuts in different drawing zones share one BOM
    // row and their piece count/area are summed.
    final marker = description.indexOf('بانو (Panneau)');
    if (marker >= 0) description = description.substring(marker);
    description = description.replaceAll(RegExp(r'\s+'), ' ').trim();
    return '${item.catalogItemId ?? 'no-id'}|$description';
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
        if (isBardagePanelSubtype(s)) return 'بارداش';
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
          // المستخدم اختار — نحتفظ به فقط إذا كان يتحمل سمك الزجاج ونوعه فعليًا.
          final double chosenMax =
              (selectedParclose['max_glass_thickness'] as num?)?.toDouble() ??
              0.0;
          final bool isDoubleGlass = glass.structure == GlassStructure.double;
          final bool isDoubleParclose = chosenMax > 10.0;
          final bool chosenMatchesGlass =
              chosenMax >= totalT && (!isDoubleParclose || isDoubleGlass);

          if (chosenMatchesGlass) {
            matchingParclose = selectedParclose;
          } else {
            // المختار غير متوافق مع نوع وسماكة الزجاج — ننتقل إلى الأنسب داخل نفس السلسلة.
            matchingParclose =
                firstCapacityAtLeast(totalT) ??
                allParcloseSections.first.toMap();
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
        final fittedJointThickness = glass.fittedJoints.fold<double>(
          0.0,
          (sum, joint) =>
              sum + (double.tryParse('${joint['thickness']}') ?? 0.0),
        );
        final installedThickness = totalT + fittedJointThickness;
        if (installedThickness > maxG + 1.01) {
          result +=
              '\n⚠️ تنبيه: سماكة $label مع الجوانات ($installedThickness مم) أكبر من سعة البيركلوز (${matchingParclose['name']}) ($maxG مم)';
        } else if (glass.glazingFitValid == false) {
          result +=
              '\n⚠️ تنبيه: لا توجد جوانات متوافقة لملء الفرق بين سماكة $label ($totalT مم) وسعة البيركلوز (${matchingParclose['name']}) ($maxG مم)';
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
    List<String>? pieceCutAngles,
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
        : (overrideKey != null && overrides.containsKey(overrideKey)
            ? overrides[overrideKey] as Map<String, dynamic>?
            : null);
    final Map<String, dynamic>? selectedOverride = () {
      if (savedOverride != null && overrideMap != null) {
        final merged = Map<String, dynamic>.from(overrideMap);
        if (savedOverride.containsKey('price')) merged['price'] = savedOverride['price'];
        if (savedOverride.containsKey('calculated_price')) merged['calculated_price'] = savedOverride['calculated_price'];
        if (savedOverride.containsKey('price_dzd')) merged['price_dzd'] = savedOverride['price_dzd'];
        return merged;
      }
      return (preferOverrideMap && overrideMap != null)
          ? overrideMap
          : (savedOverride ?? overrideMap);
    }();
    bool isLinked = selectedOverride != null;
    double price = defaultPrice;
    double finalQty = qty;
    double? finalLength = length;
    String? cuttingListText;
    String? profileCode;
    String? imagePath;
    String subName = '';
    if (isLinked) {
      final ov = selectedOverride;
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
      double barLength = 0.0;
      if (isLinked) {
        final ov = selectedOverride;
        barLength = (ov['bar_length'] as num?)?.toDouble() ?? 0.0;
      }

      if (barLength > 0) {
        final optimization = optimizeCutting(
          pieces: pieces,
          barLength: barLength,
        );
        exactBars = optimization['exactBars'];
        finalQty = optimization['optimizedBars'].toDouble();
        finalLength = barLength;
      }

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
    if (isLinked && (finalLength == null || finalLength == 0.0)) {
      final ov = selectedOverride;
      finalLength = (ov['bar_length'] as num?)?.toDouble() ?? 0.0;
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
      pieceCutAngles: pieceCutAngles,
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
    List<double>? pieces,
    String? cuttingList,
    String unit = 'حبة',
  }) {
    String lookupKey = overrideKey ?? originalName;
    if (!overrides.containsKey(lookupKey) &&
        overrides.containsKey(originalName)) {
      lookupKey = originalName;
    }
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
      unit: unit,
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
      pieces: pieces,
      cuttingList: cuttingList,
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
    String? kitGroupName,
  }) {
    final keyToUse = overrideKey ?? originalName;
    final ov =
        overrides[keyToUse] ??
        overrides[originalName] ??
        (originalName.trim().toUpperCase() == 'N 245'
            ? overrides['جوان الوسط (Joint Central)']
            : null);
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
        (isLinked && ov['id'] is num
            ? (ov['id'] as num).toInt()
            : int.tryParse('${isLinked ? ov['id'] ?? '' : ''}'));
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
      kitGroupName: kitGroupName,
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
    Map<String, dynamic>? selectedOverride;
    final direct = overrides[originalName];
    if (direct is Map) {
      selectedOverride = Map<String, dynamic>.from(direct);
    } else {
      final targetSelector = _selectorTypeForShutter(originalName);
      for (final entry in overrides.entries) {
        if (entry.value is! Map) continue;
        if (_selectorTypeForShutter(entry.key) == targetSelector) {
          selectedOverride = Map<String, dynamic>.from(entry.value as Map);
          break;
        }
      }
    }
    final bool isLinked = selectedOverride != null;
    String name = originalName;
    double price = 0.0;
    double finalQty = qty;
    double? finalLength;
    double? finalExactQuantity;
    String? cuttingListText;
    String? profileCode;
    String? imagePath;

    if (isLinked) {
      final ov = selectedOverride!;
      profileCode = ov['code']?.toString();
      imagePath = ov['image_path']?.toString();
      var details = '${ov['code'] ?? ''} - ${ov['name']}'.trim();
      if (details.startsWith('- ')) details = details.substring(2);
      name = '$originalName\n$details';
      final rawPrice =
          ov['calculated_price'] ?? ov['price_dzd'] ?? ov['price'] ?? 0.0;
      price = rawPrice is num
          ? rawPrice.toDouble()
          : double.tryParse(rawPrice.toString()) ?? 0.0;
    }
    final linkedCatalogueId =
        catalogItemId ??
        (isLinked && selectedOverride!['id'] is num
            ? (selectedOverride['id'] as num).toInt()
            : int.tryParse('${isLinked ? selectedOverride!['id'] ?? '' : ''}'));

    bool isSqmOrLinear = false;
    String finalUnit = unit;
    if (isLinked) {
      final ov = selectedOverride!;
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
      double barLength = 0.0;
      if (isLinked) {
        final ov = selectedOverride!;
        double? dbLen =
            (ov['bar_length_m'] as num?)?.toDouble() ??
            (ov['bar_length'] as num?)?.toDouble();
        if ((dbLen == null || dbLen <= 0) && ov['max_width_mm'] is num) {
          dbLen = (ov['max_width_mm'] as num).toDouble() / 1000.0;
        }
        if (dbLen != null && dbLen > 0) barLength = dbLen;
      }

      if (barLength > 0) {
        final optimization = optimizeCutting(
          pieces: pieces,
          barLength: barLength,
        );
        double exactBars = optimization['exactBars'];
        int optimizedBars = optimization['optimizedBars'];

        if (!isSqmOrLinear) {
          finalQty = optimizedBars.toDouble();
          finalExactQuantity = exactBars;
        }
        finalLength = barLength;

      }

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
      final ov = selectedOverride!;
      finalLength =
          (ov['bar_length_m'] as num?)?.toDouble() ??
          (ov['bar_length'] as num?)?.toDouble() ??
          0.0;
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
    final linkedOverride = selectedOverride;
    final isAccessoryOverride =
        linkedOverride != null &&
        (linkedOverride['material_type'] != null ||
            linkedOverride['screw_count'] != null ||
            linkedOverride['is_kit_screw'] != null ||
            linkedOverride['is_caisson_screw'] != null ||
            linkedOverride['is_moteur_screw'] != null) &&
        linkedOverride['component_type'] == null;
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
