import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:database_data/settings/app_settings.dart';
import 'package:database_data/sql_database.dart';
import 'package:database_data/Commande/Systeme/model.dart';
import 'package:database_data/Commande/Systeme/model_serialization.dart';
import 'package:database_data/Commande/Systeme/calculate_component.dart';
import 'package:database_data/Commande/window_painter.dart';
import 'package:database_data/widgets/section_image.dart';
import 'package:database_data/services/remnant_ticket_service.dart';
import 'package:database_data/settings/localization.dart';
import 'package:database_data/Screen/achat_details_screen.dart';

bool isExplicitlyReplacedProduct(bool modelIsReplaced, dynamic savedValue) {
  if (modelIsReplaced || savedValue == true) return true;
  final normalized = savedValue?.toString().trim().toLowerCase();
  return normalized == 'true' || normalized == '1';
}

List<Map<String, dynamic>> parseRequiredGoodsInstances(dynamic raw) {
  if (raw == null) return const [];
  dynamic decoded = raw;
  if (raw is String) {
    final value = raw.trim();
    if (value.isEmpty) return const [];
    try {
      decoded = jsonDecode(value);
    } catch (_) {
      return const [];
    }
  }
  if (decoded is! List) return const [];
  return decoded.whereType<Map>().map(Map<String, dynamic>.from).toList();
}

String requiredGoodsCategoryForBom(BomItem item) {
  final category = item.category.trim().toLowerCase();
  final inventoryType = (item.inventoryItemType ?? '').trim().toLowerCase();
  if (inventoryType == 'section' ||
      const {'profile', 'frame', 'sash', 'mullion'}.contains(category)) {
    return 'profile';
  }
  if (inventoryType == 'shuttercomponent' ||
      const {'shutter', 'caisson_tunnel'}.contains(category)) {
    return 'shutter';
  }
  if (inventoryType == 'joints' || category == 'joint') return 'joint';
  if (inventoryType == 'glass' || category == 'glass') return 'glass';
  if (category == 'panneau') return 'panneau';
  return 'accessory';
}

bool bomUsesOrderLevelCutting(BomItem item) {
  final unit = item.unit.trim().toLowerCase();
  final isStockBar = const {'قطاع', 'بارة', 'bar', 'section'}.contains(unit);
  return isStockBar &&
      (item.length ?? 0) > 0 &&
      (item.pieces?.any((piece) => piece > 0) ?? false);
}

String requiredGoodsDisplayName(BomItem item) => item.name
    .split('\n')
    .where((line) => !line.contains('المطلوب الفعلي'))
    .join('\n')
    .trim();

String requiredGoodsAggregationKey(BomItem item, String category) {
  final usesOrderCutting = bomUsesOrderLevelCutting(item);
  final itemIdentifier =
      item.catalogItemId != null && item.inventoryItemType != null
      ? '${item.inventoryItemType}:${item.catalogItemId}'
      : (item.profileCode != null && item.profileCode!.isNotEmpty)
      ? 'CODE:${item.profileCode}'
      : usesOrderCutting
      ? 'CUT:${item.originalName}:${requiredGoodsDisplayName(item)}'
      : 'NAME:${item.name}';
  return '${category}___${itemIdentifier}___'
      '${item.colorId ?? item.colorName ?? ''}___${item.unit}___'
      '${item.length ?? ''}___${item.glassHeight ?? ''}';
}

/// A Kit is one configured bundle. Its contents can carry different colours,
/// but must still remain beneath that single Kit row in required goods.
String requiredGoodsKitAggregationKey(String category, String kitName) =>
    'KIT___${category}___${kitName.trim().toLowerCase()}';

/// Child rows are generated from the Kit page with this stable prefix. The
/// Kit header itself has a logical UI key instead and must never be rendered
/// again as one of its own components.
bool isRequiredGoodsKitHeader(BomItem item, String kitName) =>
    !item.originalName.trim().startsWith('${kitName.trim()}_');

/// The Kit page is the source of truth for the display name. Avoid turning an
/// already French-named bundle such as "Kit Volet 155" into "Kit Kit Volet".
String requiredGoodsKitDisplayName(String kitName) => kitName.trim();

class OrderCuttingPlan {
  const OrderCuttingPlan({
    required this.bars,
    required this.stockLength,
    required this.bladeWaste,
    this.oversizedPieces = const [],
  });

  final List<List<double>> bars;
  final double stockLength;
  final double bladeWaste;
  final List<double> oversizedPieces;

  int get barCount => bars.length;

  double get usedLength => bars.fold<double>(
    0,
    (sum, bar) => sum + bar.fold<double>(0, (barSum, piece) => barSum + piece),
  );

  double get wasteLength {
    final cutCount = bars.fold<int>(0, (sum, bar) => sum + bar.length);
    final waste =
        (barCount * stockLength) - usedLength - (cutCount * bladeWaste);
    return waste > 0 ? waste : 0;
  }
}

class AvailableRemnantPiece {
  const AvailableRemnantPiece({
    required this.id,
    required this.length,
    this.data = const {},
  });

  final int id;
  final double length;
  final Map<String, dynamic> data;
}

class RemnantCutUsage {
  const RemnantCutUsage({
    required this.remnant,
    required this.cuts,
    required this.remainingLength,
  });

  final AvailableRemnantPiece remnant;
  final List<double> cuts;
  final double remainingLength;
}

class InventoryAwareCuttingPlan {
  const InventoryAwareCuttingPlan({
    required this.remnantUsages,
    required this.fullBarPlan,
  });

  final List<RemnantCutUsage> remnantUsages;
  final OrderCuttingPlan fullBarPlan;
}

/// Uses the smallest matching stored remainder that can accept each cut, then
/// scientifically packs only the cuts still outstanding into full bars.
InventoryAwareCuttingPlan optimizeCuttingWithRemnants({
  required Iterable<double> pieces,
  required Iterable<AvailableRemnantPiece> remnants,
  required double stockLength,
  double bladeWaste = 0.004,
}) {
  final remainingPieces = pieces.where((piece) => piece > 0).toList()
    ..sort((a, b) => b.compareTo(a));
  final bins = remnants
      .where((piece) => piece.length > bladeWaste)
      .map(
        (piece) => <String, dynamic>{
          'piece': piece,
          'remaining': piece.length,
          'cuts': <double>[],
        },
      )
      .toList();
  final unallocated = <double>[];

  for (final cut in remainingPieces) {
    final needed = cut + bladeWaste;
    Map<String, dynamic>? selected;
    var bestRemainder = double.infinity;
    for (final bin in bins) {
      final available = bin['remaining'] as double;
      final after = available - needed;
      if (after >= -0.0000001 && after < bestRemainder) {
        selected = bin;
        bestRemainder = after;
      }
    }
    if (selected == null) {
      unallocated.add(cut);
      continue;
    }
    (selected['cuts'] as List<double>).add(cut);
    selected['remaining'] = bestRemainder < 0 ? 0.0 : bestRemainder;
  }

  final usages = bins
      .where((bin) => (bin['cuts'] as List<double>).isNotEmpty)
      .map(
        (bin) => RemnantCutUsage(
          remnant: bin['piece'] as AvailableRemnantPiece,
          cuts: List<double>.unmodifiable(bin['cuts'] as List<double>),
          remainingLength: bin['remaining'] as double,
        ),
      )
      .toList();
  return InventoryAwareCuttingPlan(
    remnantUsages: usages,
    fullBarPlan: optimizeRequiredGoodsCutting(
      pieces: unallocated,
      stockLength: stockLength,
      bladeWaste: bladeWaste,
    ),
  );
}

/// Packs all cuts of one catalogue item/colour/stock length together.
/// Lengths are converted to millimetres before packing to avoid floating
/// point boundary errors. Best-fit decreasing supplies a fast upper bound;
/// for manageable batches a bounded exact search then proves or improves it.
OrderCuttingPlan optimizeRequiredGoodsCutting({
  required Iterable<double> pieces,
  required double stockLength,
  double bladeWaste = 0.004,
}) {
  if (stockLength <= 0) {
    return OrderCuttingPlan(
      bars: const [],
      stockLength: stockLength,
      bladeWaste: bladeWaste,
      oversizedPieces: pieces.where((piece) => piece > 0).toList(),
    );
  }

  final stockMm = (stockLength * 1000).round();
  final kerfMm = (bladeWaste * 1000).round().clamp(0, stockMm);
  final validPieces = pieces.where((piece) => piece > 0).toList();
  final oversizedPieces = validPieces
      .where((piece) => (piece * 1000).round() + kerfMm > stockMm)
      .toList();
  final cutPieces =
      validPieces
          .where((piece) => (piece * 1000).round() + kerfMm <= stockMm)
          .map(
            (piece) =>
                (original: piece, requiredMm: (piece * 1000).round() + kerfMm),
          )
          .toList()
        ..sort((a, b) => b.requiredMm.compareTo(a.requiredMm));

  if (cutPieces.isEmpty) {
    return OrderCuttingPlan(
      bars: const [],
      stockLength: stockLength,
      bladeWaste: bladeWaste,
      oversizedPieces: oversizedPieces,
    );
  }

  List<List<int>> bestFitAssignments = [];
  final bestFitRemaining = <int>[];
  for (var pieceIndex = 0; pieceIndex < cutPieces.length; pieceIndex++) {
    final required = cutPieces[pieceIndex].requiredMm;
    var bestBin = -1;
    var smallestRemainder = stockMm + 1;
    for (var bin = 0; bin < bestFitRemaining.length; bin++) {
      final remainder = bestFitRemaining[bin] - required;
      if (remainder >= 0 && remainder < smallestRemainder) {
        bestBin = bin;
        smallestRemainder = remainder;
      }
    }
    if (bestBin < 0) {
      bestFitRemaining.add(stockMm - required);
      bestFitAssignments.add([pieceIndex]);
    } else {
      bestFitRemaining[bestBin] -= required;
      bestFitAssignments[bestBin].add(pieceIndex);
    }
  }

  final totalRequiredMm = cutPieces.fold<int>(
    0,
    (sum, piece) => sum + piece.requiredMm,
  );
  final lowerBound = (totalRequiredMm / stockMm).ceil();
  var bestAssignments = bestFitAssignments;

  // Exact branch-and-bound is useful for normal window orders, while the node
  // cap keeps very large orders responsive. The best-fit plan remains valid
  // if the exact proof reaches that cap.
  if (cutPieces.length <= 40 && bestAssignments.length > lowerBound) {
    const maxNodes = 300000;
    var visitedNodes = 0;
    var stopped = false;

    List<List<int>>? findPacking(int targetBars) {
      final remaining = List<int>.filled(targetBars, stockMm);
      final assignments = List.generate(targetBars, (_) => <int>[]);

      bool place(int index) {
        if (index == cutPieces.length) return true;
        if (++visitedNodes > maxNodes) {
          stopped = true;
          return false;
        }
        final required = cutPieces[index].requiredMm;
        final seenRemainders = <int>{};
        for (var bin = 0; bin < targetBars; bin++) {
          if (remaining[bin] < required ||
              !seenRemainders.add(remaining[bin])) {
            continue;
          }
          remaining[bin] -= required;
          assignments[bin].add(index);
          if (place(index + 1)) return true;
          assignments[bin].removeLast();
          remaining[bin] += required;
          if (remaining[bin] == stockMm || stopped) break;
        }
        return false;
      }

      return place(0)
          ? assignments.where((bar) => bar.isNotEmpty).toList()
          : null;
    }

    for (var target = lowerBound; target < bestAssignments.length; target++) {
      final exact = findPacking(target);
      if (exact != null) {
        bestAssignments = exact;
        break;
      }
      if (stopped) break;
    }
  }

  final bars = bestAssignments
      .map(
        (assignment) => assignment
            .map((pieceIndex) => cutPieces[pieceIndex].original)
            .toList(),
      )
      .toList();
  for (final piece in oversizedPieces) {
    // Keep an explicit row in the plan so the required quantity is never
    // understated; the UI also warns that a longer stock length is required.
    bars.add([piece]);
  }

  return OrderCuttingPlan(
    bars: bars,
    stockLength: stockLength,
    bladeWaste: bladeWaste,
    oversizedPieces: oversizedPieces,
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// نموذج سلعة مجمّعة بعد الجمع من كل المنتجات
// ─────────────────────────────────────────────────────────────────────────────
class ProductBreakdown {
  final int index;
  final String name;
  final int qty;
  final double width;
  final double height;
  final WindowModel model;
  final List<BomItem> bomItems;

  ProductBreakdown({
    required this.index,
    required this.name,
    required this.qty,
    required this.width,
    required this.height,
    required this.model,
    required this.bomItems,
  });
}

enum _PurchaseDocumentKind { purchaseOrder, purchaseInvoice }

class AggregatedGoodItem {
  final String name;
  final String originalName;
  final String category;
  final String unit;
  final String? imagePath;
  double unitPrice; // non-final to allow computing it later for kits
  double totalQuantity;
  double totalCost;
  final String? profileCode;
  final String? colorName;
  final double? stockLength;
  final double? glassHeight;
  final int? catalogItemId;
  final String? inventoryItemType;
  final int? colorId;
  final bool isMissing;
  final List<double> cuttingPieces;
  OrderCuttingPlan? cuttingPlan;

  // 🟢 List of sub-items if this item is a grouped Kit
  final List<BomItem> kitSubItems;
  final String? kitGroupName;

  AggregatedGoodItem({
    required this.name,
    required this.originalName,
    required this.category,
    required this.unit,
    this.imagePath,
    required this.unitPrice,
    required this.totalQuantity,
    required this.totalCost,
    this.profileCode,
    this.colorName,
    this.stockLength,
    this.glassHeight,
    this.catalogItemId,
    this.inventoryItemType,
    this.colorId,
    this.isMissing = false,
    List<double> cuttingPieces = const [],
    this.cuttingPlan,
    this.kitSubItems = const [],
    this.kitGroupName,
  }) : cuttingPieces = List<double>.from(cuttingPieces);
}

// ─────────────────────────────────────────────────────────────────────────────
// الشاشة الرئيسية
// ─────────────────────────────────────────────────────────────────────────────
class OrderRequiredGoodsScreen extends StatefulWidget {
  final Map<String, dynamic> orderData;
  final SqlDatabase db;

  const OrderRequiredGoodsScreen({
    super.key,
    required this.orderData,
    required this.db,
  });

  @override
  State<OrderRequiredGoodsScreen> createState() =>
      _OrderRequiredGoodsScreenState();
}

class _OrderRequiredGoodsScreenState extends State<OrderRequiredGoodsScreen> {
  bool _isLoading = true;
  String? _errorMessage;
  List<AggregatedGoodItem> _aggregatedItems = [];
  int _productCount = 0;
  List<ProductBreakdown> _productBreakdowns = [];
  List<String> _processingWarnings = [];
  final Set<String> _expandedKits = {};
  final Set<String> _expandedCuttingPlans = {};
  bool _isCreatingPurchase = false;
  late AppLanguage _currentLang;

  @override
  void initState() {
    super.initState();
    _currentLang = Provider.of<AppSettingsProvider>(
      context,
      listen: false,
    ).language;
    _loadAndAggregate();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _currentLang = Provider.of<AppSettingsProvider>(context).language;
  }

  String _t(String key) => Localization.translate(key, _currentLang);

  // ─────────────────────────────────────────────────────────────────
  // الدالة الرئيسية: تقرأ كل منتجات الطلبية وتحسب وتجمع السلع
  // ─────────────────────────────────────────────────────────────────
  double _safeDouble(dynamic val) {
    if (val == null) return 0.0;
    if (val is num) return val.toDouble();
    return double.tryParse(val.toString()) ?? 0.0;
  }

  int _safePositiveInt(dynamic value, {int fallback = 1}) {
    final parsed = value is num
        ? value.toInt()
        : int.tryParse(value?.toString().trim() ?? '');
    return parsed != null && parsed > 0 ? parsed : fallback;
  }

  int? _safeInt(dynamic value) {
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString().trim() ?? '');
  }

  void _applyInstanceSize(WindowModel model, double width, double height) {
    if (width <= 0 || height <= 0) return;
    final oldWidth = model.width;
    final oldHeight = model.height;
    if (model.zones.isNotEmpty && oldWidth > 0 && oldHeight > 0) {
      if ((oldWidth - width).abs() > 0.01 ||
          (oldHeight - height).abs() > 0.01) {
        model.rescaleZones(oldWidth, oldHeight, width, height);
      }
      return;
    }
    model.width = width;
    model.height = height;
  }

  List<BomItem> _standaloneProductBom(WindowModel model) {
    final name = (model.manualNameOverride ?? model.description ?? 'منتج خاص')
        .trim();
    final color = model.selectedDbColor?['name']?.toString();
    final quantity = model.quantity > 0 ? model.quantity : 1;

    if (model.isGlassWork) {
      final areaPerPiece = (model.width / 1000) * (model.height / 1000);
      final totalArea = areaPerPiece > 0 ? areaPerPiece * quantity : 0.0;
      final pricePerSqm = areaPerPiece > 0
          ? (model.manualPriceOverride ?? 0.0) / areaPerPiece
          : 0.0;
      return [
        BomItem(
          category: 'glass',
          originalName: name.isEmpty ? 'عمل زجاجي' : name,
          name: name.isEmpty ? 'عمل زجاجي' : name,
          colorName: color,
          quantity: totalArea > 0 ? totalArea : quantity.toDouble(),
          unit: totalArea > 0 ? 'م²' : 'قطعة',
          unitPrice: pricePerSqm,
          isMissing: true,
          inventoryItemType: 'Glass',
        ),
      ];
    }

    final displayName = name.isEmpty
        ? (model.isMoustiquaire ? 'ناموسية' : 'منتج خاص')
        : name;
    return [
      BomItem(
        category: 'accessory',
        originalName: displayName,
        name: displayName,
        colorName: color,
        quantity: quantity.toDouble(),
        unit: 'قطعة',
        unitPrice: model.manualPriceOverride ?? 0.0,
        isMissing: true,
        inventoryItemType: 'Accessory',
      ),
    ];
  }

  Future<List<BomItem>> _resolveBomForModel(
    WindowModel model,
    Map<String, List<Map<String, dynamic>>> kitBundleData,
    Map<String, bool> kitPerLeafMap,
    Map<String, Map<String, dynamic>> kitBundleMetadata,
  ) async {
    // Products created outside the window drawing (mosquito screens, tempered
    // glass work and manual products) intentionally have no zones. Preserve
    // them as standalone required goods instead of silently returning no rows.
    if (model.isMoustiquaire || model.isGlassWork || model.isCustomProduct) {
      return _standaloneProductBom(model);
    }

    // Use the same automatic shutter links as the quantity/cost table before
    // generating any row (blade -> track -> exact linked blade cap).
    await model.updateShutterDefaultsIfNeeded();
    final activeVariants = _buildActiveVariants(model);
    final dbInstance = (await widget.db.db)!;
    final sqlDb = widget.db;
    // The grey colour is the shutter component base price.  This also moves
    // legacy standalone prices into the colour-price table before this BOM is
    // priced.
    final shutterGreyColorId = await sqlDb
        .ensureShutterComponentsUseGreyPrice();

    // Generate initial BOM
    final bomItems = ComponentCalculator.generateBom(
      model,
      activeVariants,
      kitBundleData: kitBundleData,
      kitPerLeafMap: kitPerLeafMap,
      kitBundleMetadata: kitBundleMetadata,
    );

    final colorId = _safeInt(model.selectedDbColor?['id']);
    final accessoryColorId =
        _safeInt(model.selectedAccessoryColor?['id']) ?? colorId;

    for (var item in bomItems) {
      if (item.isMissing &&
          !model.componentOverrides.containsKey(item.originalName)) {
        try {
          if (item.category == 'shutter' &&
              item.originalName == 'أغطية الشفرات (Bouchons Lames)') {
            final blade = model.componentOverrides['الشرائح (Lames)'];
            if (blade is Map) {
              final bladeName = (blade['name'] ?? '').toString().trim();
              if (bladeName.isNotEmpty) {
                final linkedCaps = await dbInstance.query(
                  'ShutterComponents',
                  where:
                      "LOWER(TRIM(component_type)) = 'bouchon_lame' AND LOWER(TRIM(shutter_subtype)) = LOWER(TRIM(?)) AND (is_active = 1 OR is_active IS NULL)",
                  whereArgs: [bladeName],
                  orderBy: 'id ASC',
                  limit: 1,
                );
                if (linkedCaps.isNotEmpty) {
                  model.componentOverrides[item.originalName] =
                      Map<String, dynamic>.from(linkedCaps.first);
                }
              }
            }
            continue;
          }
          // Espagnolette special case
          if (item.originalName.contains('إسبانيوليت') ||
              item.originalName.contains('Espagnolette')) {
            final match = RegExp(r'\d+').firstMatch(item.originalName);
            String targetSize = match != null ? match.group(0)! : '';
            final matType = model.isPVC ? 'PVC' : 'Aluminium';
            var allEsp = await dbInstance.query(
              'Accessories',
              where:
                  "(type LIKE '%إسبانيوليت%' OR LOWER(name) LIKE '%esp%') AND (is_active = 1 OR is_active IS NULL) AND (material_type = ? OR material_type = 'Both' OR material_type IS NULL OR material_type = '')",
              whereArgs: [matType],
            );
            if (allEsp.isNotEmpty) {
              Map<String, dynamic>? selectedEsp;
              if (targetSize.isNotEmpty) {
                for (var e in allEsp) {
                  String n = e['name'].toString();
                  String ty = e['type'].toString();
                  if (n.contains(targetSize) || ty.contains(targetSize)) {
                    selectedEsp = e;
                    break;
                  }
                }
              }
              selectedEsp ??= allEsp.first;
              final mutableItem = Map<String, dynamic>.from(selectedEsp);
              double price = 0.0;
              if (accessoryColorId != null) {
                final colorPriceRes = await dbInstance.query(
                  'AccessoryColorPrices',
                  where: 'accessory_id = ? AND color_id = ?',
                  whereArgs: [selectedEsp['id'], accessoryColorId],
                );
                if (colorPriceRes.isNotEmpty &&
                    _safeDouble(colorPriceRes.first['price']) > 0) {
                  price = _safeDouble(colorPriceRes.first['price']);
                } else {
                  price = _safeDouble(
                    selectedEsp['price_dzd'] ?? selectedEsp['price'],
                  );
                }
              } else {
                price = _safeDouble(
                  selectedEsp['price_dzd'] ?? selectedEsp['price'],
                );
              }
              mutableItem['calculated_price'] = price;
              model.componentOverrides[item.originalName] = mutableItem;
            }
            continue;
          }

          // General cases
          String? table;
          String keywordAr = '';
          String keywordFr = '';

          if (item.category == 'shutter') {
            table = 'ShutterComponents';
            if (item.originalName.contains('Lames') ||
                item.originalName.contains('الشرائح')) {
              keywordFr = 'lame';
              keywordAr = 'شريح';
            } else if (item.originalName.contains('Coulisses') ||
                item.originalName.contains('السكك')) {
              keywordFr = 'coulisse';
              keywordAr = 'سك';
            } else if (item.originalName.contains('Axe') ||
                item.originalName.contains('المحور')) {
              keywordFr = 'axe';
              keywordAr = 'محور';
            } else if (item.originalName.contains('Caisson') ||
                item.originalName.contains('الصندوق')) {
              keywordFr = 'caisson';
              keywordAr = 'صندوق';
            } else if (item.originalName.contains('Moteur') ||
                item.originalName.contains('المحرك')) {
              keywordFr = 'moteur';
              keywordAr = 'محرك';
            } else if (item.originalName.contains('Manivelle') ||
                item.originalName.contains('المانيفال')) {
              keywordFr = 'manivelle';
              keywordAr = 'مانيفال';
            } else if (item.originalName.contains('Tandem') ||
                item.originalName.contains('طانديم')) {
              keywordFr = 'tandem';
              keywordAr = 'طانديم';
            } else if (item.originalName.contains('Lame Finale') ||
                item.originalName.contains('الشريحة النهائية')) {
              keywordFr = 'finale';
              keywordAr = 'نهائي';
            } else if (item.originalName.contains('Joint Brosse') ||
                item.originalName.contains('جوان بروس')) {
              keywordFr = 'bross';
              keywordAr = 'بروس';
            } else if (item.originalName.contains('Kit') ||
                item.originalName.contains('كيت')) {
              keywordFr = 'kit';
              keywordAr = 'كيت';
            } else if (item.originalName.contains('Attache') ||
                item.originalName.contains('أطاش')) {
              keywordFr = 'attache';
              keywordAr = 'أطاش';
            } else if (item.originalName.contains('Support Moteur') ||
                item.originalName.contains('سيبور موتور')) {
              keywordFr = 'support_moteur';
              keywordAr = 'سيبور موتور';
            } else if (item.originalName.contains('Embout') ||
                item.originalName.contains('الامبو')) {
              keywordFr = 'embout';
              keywordAr = 'امبو';
            } else if (item.originalName.contains('Support Roulement') ||
                item.originalName.contains('سيبور رولمو')) {
              keywordFr = 'support_roulement';
              keywordAr = 'سيبور رولمو';
            } else if (item.originalName.contains('Bouchons Lames') ||
                item.originalName.contains('أغطية الشفرات')) {
              keywordFr = 'bouchon_lame';
              keywordAr = 'أغطية الشفرات';
            }
          } else if (item.category == 'accessory') {
            table = 'Accessories';
            if (item.originalName.contains('المقبض') ||
                item.originalName.contains('Handle')) {
              keywordFr = 'poign';
              keywordAr = 'مقبض';
            } else if (item.originalName.contains('المفاصل') ||
                item.originalName.contains('Hinges')) {
              keywordFr = 'paumel';
              keywordAr = 'مفصل';
            } else if (item.originalName.contains('System OB')) {
              keywordFr = 'ob';
              keywordAr = 'ob';
            } else if ((item.originalName.contains('الفيرو') ||
                    item.originalName.contains('Verrou')) &&
                !item.originalName.contains('Central')) {
              keywordFr = 'verrou';
              keywordAr = 'فيرو';
            } else if (item.originalName.contains('براغي') ||
                item.originalName.toLowerCase().contains('screw')) {
              keywordFr = 'visse';
              keywordAr = 'براغي';
            } else if (item.originalName.contains('عجلات') ||
                item.originalName.contains('Roulette')) {
              keywordFr = 'roulette';
              keywordAr = 'عجل';
            } else if (item.originalName.contains('أونتروماتيك') ||
                item.originalName.contains('Entrematique')) {
              keywordFr = 'intra';
              keywordAr = 'انترام';
            } else if (item.originalName.contains('اسبانيولات') ||
                item.originalName.contains('Espagnolette')) {
              keywordFr = 'espagnol';
              keywordAr = 'اسبانيول';
            } else if (item.originalName.contains('كاش كوليسون') ||
                item.originalName.contains('Gache coulissant')) {
              keywordFr = 'gache';
              keywordAr = 'كاش';
            } else if (item.originalName.contains('صداد') ||
                item.originalName.contains('Arrêt')) {
              keywordFr = 'arret';
              keywordAr = 'صداد';
            }
          } else if (item.category == 'joint') {
            table = 'Joints';
            if (item.originalName.contains('Joint Brosse') ||
                item.originalName.contains('جوان بروس')) {
              keywordFr = 'bross';
              keywordAr = 'بروس';
            } else if (item.originalName.contains('2mm') ||
                item.originalName.contains('2 ملم')) {
              keywordFr = '2';
              keywordAr = '2';
            } else if (item.originalName.contains('3-4mm') ||
                item.originalName.contains('3-4 ملم')) {
              keywordFr = '3';
              keywordAr = '3';
            } else if (item.originalName.contains('5-6mm') ||
                item.originalName.contains('5-6 ملم')) {
              keywordFr = '5';
              keywordAr = '5';
            } else if (item.originalName.contains('7-8mm') ||
                item.originalName.contains('7-8 ملم')) {
              keywordFr = '7';
              keywordAr = '7';
            } else {
              keywordFr = 'joint';
              keywordAr = 'جوان';
            }
          } else if (item.category == 'profile') {
            table = 'Sections';
            if (item.originalName.contains('Batmo') ||
                item.originalName.contains('الباتمو')) {
              keywordFr = 'batmo';
              keywordAr = 'باتمو';
            } else if (item.originalName.contains('Mullion') ||
                item.originalName.contains('تقسيم الزجاج')) {
              final mullRes = await dbInstance.query(
                'Sections',
                where:
                    'series_id = ? AND (LOWER(type) LIKE ? OR LOWER(name) LIKE ? OR LOWER(type) LIKE ? OR LOWER(name) LIKE ? OR name LIKE ? OR type LIKE ?)',
                whereArgs: [
                  model.activeSeries?.id,
                  '%mullion%',
                  '%mullion%',
                  '%traverse%',
                  '%traverse%',
                  '%تقسيم%',
                  '%تقسيم%',
                ],
                limit: 1,
              );
              if (mullRes.isNotEmpty) {
                final mutableItem = Map<String, dynamic>.from(mullRes.first);
                double price = await sqlDb.getSectionPrice(
                  mullRes.first['id'],
                  colorId,
                );
                if (price <= 0) {
                  price = _safeDouble(mullRes.first['price']);
                }
                mutableItem['calculated_price'] = price;
                model.componentOverrides[item.originalName] = mutableItem;
              }
              continue;
            } else if (item.originalName.contains('Plinthe') ||
                item.originalName.contains('بلانت')) {
              keywordFr = 'plinthe';
              keywordAr = 'بلانت';
            } else if (item.originalName.contains('Traverse') ||
                item.originalName.contains('عرضي')) {
              keywordFr = 'traverse';
              keywordAr = 'عرضي';
            } else if (item.originalName.contains('Sash Lateral') ||
                item.originalName.contains('قائم جانبي')) {
              keywordFr = 'sash';
              keywordAr = 'جانبي';
            } else if (item.originalName.contains('Sash Central') ||
                item.originalName.contains('قائم وسطي') ||
                item.originalName.contains('Chicane')) {
              keywordFr = 'sash';
              keywordAr = 'وسطي';
            } else if (item.originalName.contains('Renfort') ||
                item.originalName.contains('حديد التسليح')) {
              keywordFr = 'renfort';
              keywordAr = 'تسليح';
            } else if (item.originalName.contains('Rail') ||
                item.originalName.contains('سكة')) {
              keywordFr = 'rail';
              keywordAr = 'سكة';
            } else if (item.originalName.contains('Réducteur') ||
                item.originalName.contains('ريديكتور') ||
                item.originalName.contains('reducteur') ||
                item.originalName.contains('مخفض')) {
              keywordFr = '67114';
              keywordAr = '67114';
            } else if (item.originalName.contains('Parclose') ||
                item.originalName.contains('باكيت')) {
              keywordFr = 'parclose';
              keywordAr = 'باكيت';
            } else if (item.originalName.contains('الغطاء الجانبي') ||
                item.originalName.contains('Side Cover') ||
                item.originalName.contains('Couvre') ||
                item.originalName.contains('couvre')) {
              final sId = model.systemMode == 'sliding'
                  ? model.activeSlidingSeries?.id
                  : model.activeSeries?.id;
              final cjRes = await dbInstance.query(
                'Sections',
                where: 'series_id = ? AND (is_active = 1 OR is_active IS NULL)',
                whereArgs: [sId],
              );
              final cjMatches = cjRes.where((s) {
                final t = (s['type'] ?? '').toString().toLowerCase();
                final n = (s['name'] ?? '').toString().toLowerCase();
                return t.contains('couvre') ||
                    n.contains('couvre') ||
                    n.contains('غطاء') ||
                    t.contains('side_cover');
              }).toList();
              if (cjMatches.isNotEmpty) {
                final mutableItem = Map<String, dynamic>.from(cjMatches.first);
                double price = 0.0;
                if (colorId != null) {
                  price = await sqlDb.getSectionPrice(
                    cjMatches.first['id'] as int,
                    colorId,
                  );
                } else {
                  price = _safeDouble(
                    cjMatches.first['price_dzd'] ?? cjMatches.first['price'],
                  );
                }
                mutableItem['calculated_price'] = price;
                model.componentOverrides[item.originalName] = mutableItem;
                model.sideCoverOverride = mutableItem;
              }
              continue;
            }
          }

          if (table != null) {
            final matType = model.isPVC ? 'PVC' : 'Aluminium';
            var queryRes = await dbInstance.query(
              table,
              where:
                  "(LOWER(name) LIKE ? OR LOWER(type) LIKE ? OR name LIKE ? OR type LIKE ? OR code LIKE ?) AND (is_active = 1 OR is_active IS NULL) AND (material_type = ? OR material_type = 'Both' OR material_type IS NULL OR material_type = '')",
              whereArgs: [
                '%$keywordFr%',
                '%$keywordFr%',
                '%$keywordAr%',
                '%$keywordAr%',
                '%$keywordFr%',
                matType,
              ],
            );

            // 🟢 تصفية الجوانات حسب السلسلة الحالية (series_id / series_ids)
            // مهم جداً لضمان أن جوان البروس يخص السلسلة المختارة لا أي سلسلة أخرى
            if (table == 'Joints' &&
                queryRes.isNotEmpty &&
                model.activeSeries != null) {
              final sid = model.activeSeries!.id;
              final sidStr = sid.toString();
              // أولاً: تصفية بـ series_id المباشر
              final exactMatch = queryRes
                  .where((j) => j['series_id'] == sid)
                  .toList();
              if (exactMatch.isNotEmpty) {
                queryRes = exactMatch;
              } else {
                // ثانياً: تصفية بـ series_ids (قائمة مفصولة بفاصلة)
                final idsMatch = queryRes.where((j) {
                  final ids = (j['series_ids'] ?? '').toString();
                  return ids.split(',').map((e) => e.trim()).contains(sidStr);
                }).toList();
                if (idsMatch.isNotEmpty) {
                  queryRes = idsMatch;
                }
                // إذا لم يوجد تطابق بالسلسلة → نأخذ الجوانات العامة (series_id = null)
                else {
                  final globalJoints = queryRes.where((j) {
                    final s = j['series_id'];
                    final ids = (j['series_ids'] ?? '').toString().trim();
                    return s == null && ids.isEmpty;
                  }).toList();
                  if (globalJoints.isNotEmpty) queryRes = globalJoints;
                }
              }
            }

            if (table == 'Sections' && queryRes.isNotEmpty) {
              if (model.activeSeries != null) {
                final seriesSections = queryRes
                    .where((s) => s['series_id'] == model.activeSeries!.id)
                    .toList();
                if (seriesSections.isNotEmpty) {
                  queryRes = seriesSections;
                }
              }

              final origLower = item.originalName.toLowerCase();
              if (origLower.contains('rail') || origLower.contains('سكة')) {
                // استبعاد الإطارات Cadre 2 Rail / Cadre 3 Rail من نتائج السكة Rail
                final railMatches = queryRes.where((s) {
                  final t = (s['type'] ?? '').toString().toLowerCase();
                  final n = (s['name'] ?? '').toString().toLowerCase();
                  return (t == 'rail' ||
                          t.contains('rail') ||
                          n == 'rail' ||
                          n.startsWith('rail') ||
                          n.contains('سكة')) &&
                      !t.contains('frame') &&
                      !t.contains('cadre') &&
                      !n.contains('cadre') &&
                      !n.contains('إطار') &&
                      !n.contains('cadre 2 rail') &&
                      !n.contains('cadre 3 rail');
                }).toList();
                if (railMatches.isNotEmpty) {
                  queryRes = railMatches;
                }
              } else if (origLower.contains('réducteur') ||
                  origLower.contains('ريديكتور') ||
                  origLower.contains('reducteur') ||
                  origLower.contains('مخفض')) {
                // للريديكتور: البحث بكود 67114 أو reducteur أو مخفض واستبعاد الإطارات والسكك
                final redMatches = queryRes.where((s) {
                  final t = (s['type'] ?? '').toString().toLowerCase();
                  final n = (s['name'] ?? '').toString().toLowerCase();
                  final c = (s['code'] ?? '').toString().toLowerCase();
                  return (c.contains('67114') ||
                          t.contains('reduct') ||
                          n.contains('reduct') ||
                          n.contains('مخفض') ||
                          n.contains('ريديكتور')) &&
                      !t.contains('frame') &&
                      !t.contains('cadre') &&
                      !t.contains('rail') &&
                      !n.contains('cadre') &&
                      !n.contains('إطار') &&
                      !n.contains('rail') &&
                      !n.contains('سكة');
                }).toList();
                if (redMatches.isNotEmpty) {
                  queryRes = redMatches;
                }
              } else if (origLower.contains('latéral') ||
                  origLower.contains('lateral') ||
                  origLower.contains('قائم جانبي') ||
                  origLower.contains('sash lateral')) {
                // للقائم الجانبي: تصفية القوائم الجانبية فقط بكود 104 أو 108 أو lateral واستبعاد القائم الوسطي / الشيكان / 105
                final latMatches = queryRes.where((s) {
                  final n = (s['name'] ?? '').toString().toLowerCase();
                  final c = (s['code'] ?? '').toString().toLowerCase();
                  return (c.contains('104') ||
                          c.contains('108') ||
                          n.contains('latéral') ||
                          n.contains('lateral') ||
                          n.contains('جانبي')) &&
                      !n.contains('central') &&
                      !n.contains('وسطي') &&
                      !n.contains('chicane') &&
                      !c.contains('105');
                }).toList();
                if (latMatches.isNotEmpty) {
                  queryRes = latMatches;
                }
              } else if (origLower.contains('sash central') ||
                  origLower.contains('central') ||
                  origLower.contains('chicane') ||
                  origLower.contains('قائم وسطي')) {
                // للقائم الوسطي: تصفية القوائم الوسطية بكود 105 أو 107 أو central واستبعاد الجانبي 104
                final cenMatches = queryRes.where((s) {
                  final n = (s['name'] ?? '').toString().toLowerCase();
                  final c = (s['code'] ?? '').toString().toLowerCase();
                  return (c.contains('105') ||
                          c.contains('107') ||
                          n.contains('central') ||
                          n.contains('وسطي') ||
                          n.contains('chicane')) &&
                      !n.contains('latéral') &&
                      !n.contains('جانبي') &&
                      !c.contains('104');
                }).toList();
                if (cenMatches.isNotEmpty) {
                  queryRes = cenMatches;
                }
              }
            }

            if (queryRes.isNotEmpty) {
              final matched = queryRes.first;
              final mutableItem = Map<String, dynamic>.from(matched);
              double price = 0.0;

              if (table == 'Sections') {
                price = await sqlDb.getSectionPrice(matched['id'], colorId);
                if (price <= 0) {
                  price = _safeDouble(matched['price']);
                }
              } else if (table == 'Accessories') {
                if (accessoryColorId != null) {
                  final colorPriceRes = await dbInstance.query(
                    'AccessoryColorPrices',
                    where: 'accessory_id = ? AND color_id = ?',
                    whereArgs: [matched['id'], accessoryColorId],
                  );
                  if (colorPriceRes.isNotEmpty &&
                      _safeDouble(colorPriceRes.first['price']) > 0) {
                    price = _safeDouble(colorPriceRes.first['price']);
                  } else {
                    price = _safeDouble(
                      matched['price_dzd'] ?? matched['price'],
                    );
                  }
                } else {
                  price = _safeDouble(matched['price_dzd'] ?? matched['price']);
                }
              } else if (table == 'ShutterComponents') {
                final colorPrices = await dbInstance.query(
                  'ShutterColorPrices',
                  where: 'shutter_component_id = ?',
                  whereArgs: [matched['id']],
                );
                price = resolveShutterComponentUnitPrice(
                  component: Map<String, dynamic>.from(matched),
                  colorPrices: colorPrices,
                  selectedColorId: colorId,
                  fallbackColorId: shutterGreyColorId,
                );
              } else {
                price = _safeDouble(matched['price']);
              }

              mutableItem['calculated_price'] = price;
              model.componentOverrides[item.originalName] = mutableItem;
            }
          }
        } catch (_) {}
      }
    }

    final generatedBom = ComponentCalculator.generateBom(
      model,
      activeVariants,
      kitBundleData: kitBundleData,
      kitPerLeafMap: kitPerLeafMap,
      kitBundleMetadata: kitBundleMetadata,
    );

    // Kit rows are configured by name. Resolve their exact catalogue identity
    // without changing their quantity or cost, so a later stock comparison can
    // address the correct physical record instead of relying on display text.
    final resolvedBom = <BomItem>[];
    for (final item in generatedBom) {
      if (item.catalogItemId == null && item.kitGroupName != null) {
        final isShutterItem = item.category == 'shutter';
        final table = isShutterItem ? 'ShutterComponents' : 'Accessories';
        final matches = await dbInstance.query(
          table,
          columns: const ['id'],
          where:
              'LOWER(TRIM(name)) = LOWER(TRIM(?)) AND (is_active = 1 OR is_active IS NULL)',
          whereArgs: [item.name],
          orderBy: 'id ASC',
          limit: 1,
        );
        if (matches.isNotEmpty) {
          final rawId = matches.first['id'];
          final id = rawId is num ? rawId.toInt() : int.tryParse('$rawId');
          resolvedBom.add(
            item.copyWith(
              catalogItemId: id,
              inventoryItemType: isShutterItem
                  ? 'ShutterComponent'
                  : 'Accessory',
              colorId: isShutterItem ? colorId : accessoryColorId,
            ),
          );
          continue;
        }
      }
      resolvedBom.add(item);
    }

    // The series-configuration page is being redesigned.  Until the new
    // table rules are defined, the quantity table must use its direct
    // calculation without any configuration-page filter.
    return resolvedBom;
  }

  Future<void> _loadAndAggregate() async {
    try {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
        _processingWarnings = [];
      });

      final orderId = _safeInt(widget.orderData['id']);
      if (orderId == null) {
        throw StateError('رقم الطلبية غير صالح');
      }
      final rawItems = await widget.db.readCommandeDetails(orderId);

      // مخزن التجميع: مفتاح التجميع → السلعة المجمّعة
      // مفتاح التجميع = (originalName + unit + imagePath) لتمييز السلع الفريدة
      final Map<String, AggregatedGoodItem> aggregationMap = {};
      int successCount = 0;
      final List<ProductBreakdown> breakdownsTemp = [];
      final List<String> warnings = [];
      int skippedReplacedCount = 0;
      int itemNumber = 0;

      for (final item in rawItems) {
        itemNumber++;
        final jsonRaw = item['partitions_json'];
        final fallbackName = (item['game'] ?? item['window_type'] ?? '')
            .toString()
            .trim();
        final productLabel = fallbackName.isEmpty
            ? 'المنتج رقم $itemNumber'
            : fallbackName;
        if (jsonRaw == null || jsonRaw.toString().trim().isEmpty) {
          warnings.add('$productLabel: بيانات الرسم غير محفوظة.');
          continue;
        }

        try {
          Map<String, dynamic> modelMap = {};
          if (jsonRaw is Map<String, dynamic>) {
            modelMap = jsonRaw;
          } else if (jsonRaw is Map) {
            modelMap = Map<String, dynamic>.from(jsonRaw);
          } else {
            final str = jsonRaw.toString().trim();
            if (str.length >= 5) {
              final decoded = jsonDecode(str);
              if (decoded is Map) {
                modelMap = Map<String, dynamic>.from(decoded);
              }
            }
          }
          if (modelMap.isEmpty) {
            warnings.add('$productLabel: بيانات الرسم فارغة.');
            continue;
          }

          final model = WindowModel(db: widget.db);
          await applyWindowModelAndLoadCatalog(model, modelMap);

          // Only the explicit replacement flag cancels a product. Price zero
          // can mean a missing price or a free item and must not erase its BOM.
          if (isExplicitlyReplacedProduct(
            model.isReplaced,
            modelMap['isReplaced'],
          )) {
            skippedReplacedCount++;
            continue;
          }

          // جلب kit bundle data من قاعدة البيانات بشكل كامل وتثبيت خيار per_leaf الصحيح
          final kitBundleData = <String, List<Map<String, dynamic>>>{};
          final kitPerLeafMap = <String, bool>{};
          final kitBundleMetadata = <String, Map<String, dynamic>>{};
          try {
            final kits = await widget.db.readKitBundles();
            for (final kit in kits) {
              final kitName = kit['name']?.toString() ?? '';
              if (kitName.isEmpty) continue;
              final kitId = _safeInt(kit['id']);
              if (kitId == null) continue;
              final details = await widget.db.readKitBundleItemsWithDetails(
                kitId,
                topLevelOnly: true,
              );
              final mutableDetails = details
                  .map((e) => Map<String, dynamic>.from(e))
                  .toList();
              kitBundleData[kitName] = mutableDetails;
              kitPerLeafMap[kitName] = (kit['per_leaf'] ?? 0) == 1;
              kitBundleMetadata[kitName] = Map<String, dynamic>.from(kit);
            }
          } catch (_) {}

          // Read instances if they exist
          final instances = parseRequiredGoodsInstances(item['instances_json']);

          final List<BomItem> bomItems = [];
          final productName = productLabel;

          if (instances.isNotEmpty) {
            final double origW = model.width;
            final double origH = model.height;
            final int origQty = model.quantity;

            int instIdx = 1;
            for (final inst in instances) {
              final double w = _safeDouble(inst['width']);
              final double h = _safeDouble(inst['height']);
              final int qty = _safePositiveInt(
                inst['qty'] ?? inst['quantity'],
                fallback: _safePositiveInt(item['quantity']),
              );
              if ((w <= 0 || h <= 0) && !model.isCustomProduct) {
                warnings.add(
                  '$productName (القياس $instIdx): الطول أو العرض غير صالح.',
                );
                instIdx++;
                continue;
              }

              if (w > 0 && h > 0) {
                _applyInstanceSize(model, w, h);
              }
              model.quantity = qty;

              // Generate BOM for this specific instance using the new resolver
              final instBom = await _resolveBomForModel(
                model,
                kitBundleData,
                kitPerLeafMap,
                kitBundleMetadata,
              );
              bomItems.addAll(instBom);

              // Create a dedicated instance model for drawing and individual listing
              final instanceModel = WindowModel(db: widget.db);
              await applyWindowModelAndLoadCatalog(instanceModel, modelMap);
              if (w > 0 && h > 0) {
                _applyInstanceSize(instanceModel, w, h);
              }
              instanceModel.quantity = qty;

              breakdownsTemp.add(
                ProductBreakdown(
                  index: successCount + 1,
                  name: '$productName (#$instIdx)',
                  qty: qty,
                  width: w,
                  height: h,
                  model: instanceModel,
                  bomItems: instBom.where((b) => b.isActive).toList(),
                ),
              );
              instIdx++;
            }

            // Restore original values
            model.width = origW;
            model.height = origH;
            model.quantity = origQty;
          } else {
            // Force the window model quantity to match the actual order details quantity
            model.quantity = _safePositiveInt(
              item['quantity'],
              fallback: model.quantity > 0 ? model.quantity : 1,
            );

            final instBom = await _resolveBomForModel(
              model,
              kitBundleData,
              kitPerLeafMap,
              kitBundleMetadata,
            );
            bomItems.addAll(instBom);

            breakdownsTemp.add(
              ProductBreakdown(
                index: successCount + 1,
                name: productName,
                qty: model.quantity,
                width: model.width,
                height: model.height,
                model: model,
                bomItems: instBom.where((b) => b.isActive).toList(),
              ),
            );
          }

          final activeBomItems = bomItems
              .where((bom) => bom.isActive && bom.purchaseQuantity > 0)
              .toList();
          if (activeBomItems.isEmpty) {
            if (model.zones.isEmpty &&
                !model.isCustomProduct &&
                !model.isMoustiquaire &&
                !model.isGlassWork) {
              warnings.add(
                '$productName: الرسم المحفوظ لا يحتوي على مناطق نافذة قابلة للحساب.',
              );
            } else {
              warnings.add('$productName: لم ينتج عنه أي مقدار مطلوب.');
            }
            continue;
          }

          // إضافة وتجميع السلع (مع تجميع عناصر الـ kit تحت اسم واحد)
          for (final bom in activeBomItems) {
            final category = requiredGoodsCategoryForBom(bom);
            final usesOrderCutting = bomUsesOrderLevelCutting(bom);

            // `quantity` is the physical purchase quantity shown in the
            // quantity table. `exactQuantity` remains costing consumption.
            final double purchaseQty = usesOrderCutting
                ? 0
                : bom.purchaseQuantity;
            final double bomCost = usesOrderCutting ? 0 : bom.total;

            if (bom.kitGroupName != null && bom.kitGroupName!.isNotEmpty) {
              final String kitName = bom.kitGroupName!;
              final String kitKey = requiredGoodsKitAggregationKey(
                category,
                kitName,
              );
              final isKitHeader = isRequiredGoodsKitHeader(bom, kitName);
              final double kitQtyToAdd = isKitHeader ? purchaseQty : 0.0;
              // The header is a display group only. Its price is derived from
              // physical components configured on the Kit page, never added
              // a second time on top of them.
              final double kitCostToAdd = isKitHeader ? 0.0 : bomCost;

              if (aggregationMap.containsKey(kitKey)) {
                final agg = aggregationMap[kitKey]!;
                agg.totalQuantity += kitQtyToAdd;
                agg.totalCost += kitCostToAdd;

                if (!isKitHeader) {
                  final existingSubIndex = agg.kitSubItems.indexWhere(
                    (sub) =>
                        sub.originalName == bom.originalName &&
                        sub.unit == bom.unit &&
                        sub.colorId == bom.colorId,
                  );
                  if (existingSubIndex != -1) {
                    final existing = agg.kitSubItems[existingSubIndex];
                    agg.kitSubItems[existingSubIndex] = BomItem(
                      category: existing.category,
                      originalName: existing.originalName,
                      profileCode: existing.profileCode,
                      name: existing.name,
                      imagePath: existing.imagePath,
                      colorName: existing.colorName,
                      length: existing.length,
                      glassHeight: existing.glassHeight,
                      quantity: existing.purchaseQuantity + purchaseQty,
                      unit: existing.unit,
                      unitPrice: existing.unitPrice,
                      isMissing: existing.isMissing,
                      isActive: existing.isActive,
                      kitGroupName: existing.kitGroupName,
                      exactQuantity:
                          existing.requiredQuantity + bom.requiredQuantity,
                      catalogItemId:
                          existing.catalogItemId ?? bom.catalogItemId,
                      inventoryItemType:
                          existing.inventoryItemType ?? bom.inventoryItemType,
                      colorId: existing.colorId ?? bom.colorId,
                    );
                  } else {
                    agg.kitSubItems.add(bom);
                  }
                }
              } else {
                aggregationMap[kitKey] = AggregatedGoodItem(
                  name: requiredGoodsKitDisplayName(kitName),
                  originalName: kitName,
                  category: category,
                  unit: _currentLang == AppLanguage.french ? 'Kit' : 'طقم',
                  imagePath: null,
                  unitPrice: 0.0,
                  totalQuantity: kitQtyToAdd,
                  totalCost: kitCostToAdd,
                  profileCode: null,
                  kitSubItems: isKitHeader ? <BomItem>[] : [bom],
                  kitGroupName: kitName,
                );
              }
            } else {
              final aggregationKey = requiredGoodsAggregationKey(bom, category);

              if (aggregationMap.containsKey(aggregationKey)) {
                final aggregate = aggregationMap[aggregationKey]!;
                aggregate.totalCost += bomCost;
                aggregate.totalQuantity += purchaseQty;
                if (usesOrderCutting) {
                  aggregate.cuttingPieces.addAll(bom.pieces!);
                }
              } else {
                aggregationMap[aggregationKey] = AggregatedGoodItem(
                  name: usesOrderCutting
                      ? requiredGoodsDisplayName(bom)
                      : bom.name,
                  originalName: bom.originalName,
                  category: category,
                  unit: bom.unit,
                  imagePath: bom.imagePath,
                  unitPrice: bom.unitPrice,
                  totalQuantity: purchaseQty,
                  totalCost: bomCost,
                  profileCode: bom.profileCode,
                  colorName: bom.colorName,
                  stockLength: bom.length,
                  glassHeight: bom.glassHeight,
                  catalogItemId: bom.catalogItemId,
                  inventoryItemType: bom.inventoryItemType,
                  colorId: bom.colorId,
                  isMissing: bom.isMissing,
                  cuttingPieces: usesOrderCutting ? bom.pieces! : const [],
                  kitSubItems: const [],
                  kitGroupName: null,
                );
              }
            }
          }

          successCount++;
        } catch (e, stackTrace) {
          warnings.add('$productLabel: تعذر حسابه (${e.toString()}).');
          debugPrint('Error processing product "$productLabel": $e');
          debugPrintStack(stackTrace: stackTrace);
        }
      }

      if (skippedReplacedCount > 0) {
        warnings.add(
          'تم استبعاد $skippedReplacedCount منتج مشطوب أو مستبدل من الطلبية.',
        );
      }

      // Scientific order-level cutting: after every window has contributed
      // its raw cuts, optimize each identical catalogue item/colour/stock
      // length once. This reuses leftovers between products in the order.
      for (final item in aggregationMap.values) {
        if (item.cuttingPieces.isEmpty) continue;
        final stockLength = item.stockLength ?? 0;
        if (stockLength <= 0) continue;
        final plan = optimizeRequiredGoodsCutting(
          pieces: item.cuttingPieces,
          stockLength: stockLength,
        );
        item.cuttingPlan = plan;
        item.totalQuantity = plan.barCount.toDouble();
        item.totalCost = item.totalQuantity * item.unitPrice;
        if (plan.oversizedPieces.isNotEmpty) {
          warnings.add(
            '${item.originalName}: توجد ${plan.oversizedPieces.length} قطعة قص أطول من القطاع '
            '${(stockLength * 1000).round()} مم وتحتاج طول مخزون أكبر.',
          );
        }
      }

      // حساب سعر الوحدة الفعلي لكل طقم (Kit) كمجموع أسعار مكوناته
      for (final item in aggregationMap.values) {
        if (item.kitGroupName != null && item.totalQuantity > 0) {
          item.unitPrice = item.totalCost / item.totalQuantity;
        }
      }

      // ترتيب العرض: البروفيلات ثم الإكسسوارات ثم الزجاج. داخل كل فئة
      // ذات ألوان، تسبق الأبيضُ الخشبيَّ ثم الداكن فبقية الألوان.
      final sorted = aggregationMap.values.toList();
      sorted.sort((a, b) {
        const order = <String>[
          'profile',
          'accessory',
          'glass',
          'shutter',
          'joint',
          'panneau',
        ];
        final rawAi = order.indexOf(a.category);
        final rawBi = order.indexOf(b.category);
        final ai = rawAi < 0 ? order.length : rawAi;
        final bi = rawBi < 0 ? order.length : rawBi;
        if (ai != bi) return ai.compareTo(bi);
        if (a.category == 'profile' || a.category == 'accessory') {
          final colorComparison = _colourSortKey(
            a,
          ).compareTo(_colourSortKey(b));
          if (colorComparison != 0) return colorComparison;
        }
        return a.name.compareTo(b.name);
      });

      setState(() {
        _aggregatedItems = sorted;
        _productCount = successCount;
        _productBreakdowns = breakdownsTemp;
        _processingWarnings = warnings;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'حدث خطأ أثناء تحميل السلع: $e';
      });
    }
  }

  // ─────────────────────────────────────────────────────────────────
  // بناء activeVariants من الـ model (مطابق لـ _fetchDefaults في material_consumption_screen)
  // ─────────────────────────────────────────────────────────────────
  Map<String, bool> _buildActiveVariants(WindowModel model) {
    final isTunnel = model.isCaissonTunnel;
    final isMotor = model.shutterMechanism == 'محرك';
    final isCrank =
        model.shutterMechanism == 'منايفال' ||
        model.shutterMechanism == 'مانيفال' ||
        model.shutterMechanism == 'مانيفر';

    return {
      'Verrou Central': model.useVerrouCentral,
      'System OB': model.useSystemOB,
      'Demi System OB': model.useDemiOB,
      'كيت (Kit)': false,
      'طانديم (Tandem)': isTunnel,
      'الامبو (Embout)': isMotor,
      'سيبور رولمو (Support Roulement)': isMotor,
      'سيبور موتور (Support Moteur)': isMotor || isTunnel,
      'أغطية الشفرات (Bouchons Lames)': model.componentOverrides.containsKey(
        'أغطية الشفرات (Bouchons Lames)',
      ),
      'كيت فولي موتور (Kit Volet Moteur)': !isTunnel && isMotor,
      'كيت فولي مانيفر (Kit Volet Manivelle)': !isTunnel && isCrank,
      'كيت مانيفر (Kit Manivelle)': !isTunnel && isCrank,
      'كيت فولي (Kit Volet)': !isTunnel && !isMotor && !isCrank,
      'كيت حزام (Kit Sangle)': false,
    };
  }

  // ─────────────────────────────────────────────────────────────────
  // حساب مجموع التكاليف الكلية
  // ─────────────────────────────────────────────────────────────────
  double get _grandTotal =>
      _aggregatedItems.fold(0.0, (sum, item) => sum + item.totalCost);

  List<AggregatedGoodItem> _purchaseDocumentItems() {
    final itemsByKey = <String, AggregatedGoodItem>{};

    void add(AggregatedGoodItem item) {
      final itemId = item.catalogItemId;
      final itemType = item.inventoryItemType;
      if (itemId == null || itemType == null || item.totalQuantity <= 0) {
        return;
      }
      final key = '$itemType:$itemId:${item.colorId ?? ''}';
      final existing = itemsByKey[key];
      if (existing == null) {
        itemsByKey[key] = AggregatedGoodItem(
          name: item.name,
          originalName: item.originalName,
          category: item.category,
          unit: item.unit,
          imagePath: item.imagePath,
          unitPrice: item.unitPrice,
          totalQuantity: item.totalQuantity,
          totalCost: item.totalCost,
          profileCode: item.profileCode,
          colorName: item.colorName,
          stockLength: item.stockLength,
          glassHeight: item.glassHeight,
          catalogItemId: itemId,
          inventoryItemType: itemType,
          colorId: item.colorId,
          isMissing: false,
        );
        return;
      }

      existing.totalQuantity += item.totalQuantity;
      existing.totalCost += item.totalCost;
      if (existing.totalQuantity > 0) {
        existing.unitPrice = existing.totalCost / existing.totalQuantity;
      }
    }

    for (final item in _aggregatedItems) {
      final kitName = item.kitGroupName;
      if (kitName != null && kitName.isNotEmpty) {
        for (final child in item.kitSubItems) {
          // Kit headers are display-only. Purchase their physical components.
          if (!child.originalName.startsWith('${kitName}_')) continue;
          add(
            AggregatedGoodItem(
              name: requiredGoodsDisplayName(child),
              originalName: child.originalName,
              category: requiredGoodsCategoryForBom(child),
              unit: child.unit,
              imagePath: child.imagePath,
              unitPrice: child.unitPrice,
              totalQuantity: child.purchaseQuantity,
              totalCost: child.total,
              profileCode: child.profileCode,
              colorName: child.colorName,
              stockLength: child.length,
              glassHeight: child.glassHeight,
              catalogItemId: child.catalogItemId,
              inventoryItemType: child.inventoryItemType,
              colorId: child.colorId,
              isMissing: child.isMissing,
            ),
          );
        }
      } else {
        add(item);
      }
    }

    final result = itemsByKey.values.toList()
      ..sort((a, b) {
        final categoryComparison = _categorySortIndex(
          a.category,
        ).compareTo(_categorySortIndex(b.category));
        if (categoryComparison != 0) return categoryComparison;
        final colorComparison = _colourSortKey(a).compareTo(_colourSortKey(b));
        if (colorComparison != 0) return colorComparison;
        return a.name.compareTo(b.name);
      });
    return result;
  }

  Future<void> _convertRequiredGoodsToPurchase() async {
    if (_isCreatingPurchase) return;
    final settings = Provider.of<AppSettingsProvider>(context, listen: false);
    if (!settings.canAddPurchases()) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_t('ليس لديك صلاحية إنشاء المشتريات'))),
      );
      return;
    }

    final purchaseItems = _purchaseDocumentItems();
    if (purchaseItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _t('لا توجد سلع مرتبطة بقاعدة البيانات لتحويلها إلى شراء.'),
          ),
        ),
      );
      return;
    }

    final results = await Future.wait<dynamic>([
      widget.db.readSuppliers(),
      widget.db.readLocations(),
      widget.db.getNextAchatInvoiceNumber(),
    ]);
    if (!mounted) return;
    final suppliers = results[0] as List<Map<String, dynamic>>;
    final locations = results[1] as List<Map<String, dynamic>>;
    final nextNumber = results[2] as String;
    if (suppliers.isEmpty || locations.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_t('أضف مورّدًا ومكان تخزين قبل إنشاء طلب الشراء.')),
        ),
      );
      return;
    }

    final formKey = GlobalKey<FormState>();
    final numberController = TextEditingController(text: nextNumber);
    int? supplierId = suppliers.first['id'] as int?;
    int? locationId = locations.first['id'] as int?;
    var documentKind = _PurchaseDocumentKind.purchaseOrder;

    final request = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(_t('تحويل الكميات المطلوبة إلى شراء')),
          content: SizedBox(
            width: 420,
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  RadioListTile<_PurchaseDocumentKind>(
                    value: _PurchaseDocumentKind.purchaseOrder,
                    groupValue: documentKind,
                    onChanged: (value) =>
                        setDialogState(() => documentKind = value!),
                    title: Text(_t('طلب شراء (مسودة)')),
                    subtitle: Text(
                      _t('يمكن مراجعته وتأكيده لاحقًا دون إدخال المخزون.'),
                    ),
                  ),
                  RadioListTile<_PurchaseDocumentKind>(
                    value: _PurchaseDocumentKind.purchaseInvoice,
                    groupValue: documentKind,
                    onChanged: (value) =>
                        setDialogState(() => documentKind = value!),
                    title: Text(_t('فاتورة شراء')),
                    subtitle: Text(
                      _t('تُنشأ بالعناصر المحسوبة وقابلة للتعديل.'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: numberController,
                    decoration: InputDecoration(
                      labelText:
                          documentKind == _PurchaseDocumentKind.purchaseOrder
                          ? _t('رقم طلب الشراء')
                          : _t('رقم فاتورة الشراء'),
                      border: const OutlineInputBorder(),
                    ),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? _t('أدخل رقم الوثيقة')
                        : null,
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int>(
                    initialValue: supplierId,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: _t('المورّد'),
                      border: const OutlineInputBorder(),
                    ),
                    items: suppliers
                        .map(
                          (supplier) => DropdownMenuItem<int>(
                            value: supplier['id'] as int,
                            child: Text(supplier['name']?.toString() ?? ''),
                          ),
                        )
                        .toList(),
                    onChanged: (value) =>
                        setDialogState(() => supplierId = value),
                    validator: (value) =>
                        value == null ? _t('اختر المورّد') : null,
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int>(
                    initialValue: locationId,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: _t('مكان التخزين'),
                      border: const OutlineInputBorder(),
                    ),
                    items: locations
                        .map(
                          (location) => DropdownMenuItem<int>(
                            value: location['id'] as int,
                            child: Text(location['name']?.toString() ?? ''),
                          ),
                        )
                        .toList(),
                    onChanged: (value) =>
                        setDialogState(() => locationId = value),
                    validator: (value) =>
                        value == null ? _t('اختر مكان التخزين') : null,
                  ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(
                      '${purchaseItems.length} ${_t('صنف مرتبط سيُضاف إلى الوثيقة')}',
                      style: TextStyle(
                        color: Colors.grey.shade700,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(_t('إلغاء')),
            ),
            ElevatedButton.icon(
              onPressed: () {
                if (!formKey.currentState!.validate()) return;
                final supplier = suppliers.firstWhere(
                  (row) => row['id'] == supplierId,
                );
                Navigator.pop(dialogContext, {
                  'kind': documentKind,
                  'number': numberController.text.trim(),
                  'supplier_id': supplierId,
                  'supplier_name': supplier['name']?.toString() ?? '',
                  'location_id': locationId,
                });
              },
              icon: const Icon(Icons.shopping_cart_checkout),
              label: Text(_t('إنشاء')),
            ),
          ],
        ),
      ),
    );
    numberController.dispose();
    if (request == null || !mounted) return;

    setState(() => _isCreatingPurchase = true);
    try {
      final achatId = await widget.db.insertAchat(
        request['number'] as String,
        request['supplier_name'] as String,
        0,
        supplierId: request['supplier_id'] as int,
        locationId: request['location_id'] as int,
      );

      for (final item in purchaseItems) {
        await widget.db.insertAchatItem(
          achatId: achatId,
          itemCode: item.profileCode?.trim().isNotEmpty == true
              ? item.profileCode!.trim()
              : item.name.replaceAll('\n', ' ').trim(),
          itemName: item.name.replaceAll('\n', ' • ').trim(),
          itemType: item.inventoryItemType!,
          itemId: item.catalogItemId!,
          colorId: item.colorId,
          quantity: item.totalQuantity,
          price: item.unitPrice,
        );
      }
      await widget.db.updateAchatTotal(
        achatId,
        _purchaseDocumentItemsTotal(purchaseItems),
      );
      if (request['kind'] == _PurchaseDocumentKind.purchaseOrder) {
        await widget.db.updateAchatStatus(achatId, 'Draft');
      }
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => AchatDetailsScreen(
            achatId: achatId,
            invoiceNumber: request['number'] as String,
            supplierName: request['supplier_name'] as String,
          ),
        ),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${_t('تعذر إنشاء وثيقة الشراء:')} $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _isCreatingPurchase = false);
    }
  }

  double _purchaseDocumentItemsTotal(List<AggregatedGoodItem> items) =>
      items.fold(0.0, (sum, item) => sum + item.totalCost);

  // ─────────────────────────────────────────────────────────────────
  // ترجمة الفئة إلى نص عربي
  // ─────────────────────────────────────────────────────────────────
  String _categoryLabel(String category) {
    switch (category) {
      case 'profile':
        return '📐 ${_t('البروفيلات')}';
      case 'frame':
        return '🪟 ${_t('بروفيل الإطار')}';
      case 'sash':
        return '🔲 ${_t('بروفيل الكانة')}';
      case 'mullion':
        return '📐 ${_t('بروفيل الفاصل')}';
      case 'glass':
        return '🔷 ${_t('الزجاج')}';
      case 'panneau':
        return '🖼️ ${_t('بانو')}';
      case 'shutter':
        return '🎛️ ${_t('مكونات الستارة')}';
      case 'caisson_tunnel':
        return '📦 Caisson Tunnel';
      case 'accessory':
        return '🔩 ${_t('الإكسسوارات')}';
      case 'joint':
        return '🧵 ${_t('الجوانات')}';
      default:
        return '📦 ${_t('أخرى')}';
    }
  }

  Color _categoryColor(String category) {
    switch (category) {
      case 'profile':
        return Colors.blueGrey.shade700;
      case 'frame':
        return Colors.blue.shade700;
      case 'sash':
        return Colors.indigo.shade600;
      case 'mullion':
        return Colors.purple.shade600;
      case 'glass':
        return Colors.cyan.shade700;
      case 'panneau':
        return Colors.lightBlue.shade700;
      case 'shutter':
        return Colors.orange.shade700;
      case 'caisson_tunnel':
        return Colors.amber.shade900;
      case 'accessory':
        return Colors.teal.shade600;
      case 'joint':
        return Colors.brown.shade600;
      default:
        return Colors.grey.shade700;
    }
  }

  int _categorySortIndex(String category) {
    const order = <String>[
      'profile',
      'accessory',
      'glass',
      'shutter',
      'joint',
      'panneau',
    ];
    final index = order.indexOf(category);
    return index < 0 ? order.length : index;
  }

  String _normalisedColourName(String? value) => (value ?? '')
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[\s_\-]+'), ' ')
      .replaceAll('ى', 'ي');

  int _colourPriority(String? colorName) {
    final color = _normalisedColourName(colorName);
    if (color.isEmpty || color == 'خام' || color == 'raw') return 4;
    if (color.contains('أبيض') ||
        color.contains('white') ||
        color.contains('blanc')) {
      return 0;
    }
    if (color.contains('خشب') ||
        color.contains('wood') ||
        color.contains('bois') ||
        color.contains('oak') ||
        color.contains('desert') ||
        color.contains('ديزر') ||
        color.contains('walnut') ||
        color.contains('noiset')) {
      return 1;
    }
    if (color.contains('أسود') ||
        color.contains('black') ||
        color.contains('noir') ||
        color.contains('داكن') ||
        color.contains('dark') ||
        color.contains('fonc') ||
        color.contains('anthrac') ||
        color.contains('7016')) {
      return 2;
    }
    return 3;
  }

  String _colourSortKey(AggregatedGoodItem item) {
    final priority = _colourPriority(item.colorName);
    return '${priority.toString().padLeft(2, '0')}|${_normalisedColourName(item.colorName)}';
  }

  String _colourGroupKey(AggregatedGoodItem item) {
    final priority = _colourPriority(item.colorName);
    final color = item.colorName?.trim() ?? '';
    switch (priority) {
      case 0:
        return '00|أبيض';
      case 1:
        return '01|خشبي';
      case 2:
        return '02|ألوان داكنة';
      case 3:
        return '03|${color.isEmpty ? 'ألوان أخرى' : color}';
      default:
        return '04|بدون لون';
    }
  }

  List<MapEntry<String, List<AggregatedGoodItem>>> _colourGroupsFor(
    List<AggregatedGoodItem> items,
  ) {
    final groups = <String, List<AggregatedGoodItem>>{};
    for (final item in items) {
      groups.putIfAbsent(_colourGroupKey(item), () => []).add(item);
    }
    final entries = groups.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    for (final entry in entries) {
      entry.value.sort((a, b) => a.name.compareTo(b.name));
    }
    return entries;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final clientFirst = widget.orderData['firstname']?.toString() ?? '';
    final clientLast = widget.orderData['lastname']?.toString() ?? '';
    final clientNameJoined = '$clientFirst $clientLast'.trim();
    final clientDisplay = clientNameJoined.isNotEmpty
        ? clientNameJoined
        : (widget.orderData['client_name']?.toString() ??
              widget.orderData['client_display']?.toString() ??
              'عميل غير معروف');

    return Scaffold(
      backgroundColor: isDark
          ? const Color(0xFF121212)
          : const Color(0xFFF0F4FF),
      appBar: AppBar(
        title: Column(
          children: [
            Text(
              _t('كمية السلع المطلوبة'),
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            Text(
              clientDisplay,
              style: const TextStyle(fontSize: 12, color: Colors.white70),
            ),
          ],
        ),
        centerTitle: true,
        backgroundColor: isDark
            ? Theme.of(context).appBarTheme.backgroundColor
            : const Color(0xFF1A237E),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          if (!_isLoading &&
              _errorMessage == null &&
              _aggregatedItems.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.manage_search),
              tooltip: _t('إظهار النواقص'),
              onPressed: _showShortageReport,
            ),
          if (!_isLoading &&
              _errorMessage == null &&
              _cuttableCatalogItems.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.inventory_2_outlined),
              tooltip: _t('اعتماد القص والبقايا'),
              onPressed: _approveAndStoreCuttingRemainders,
            ),
          if (!_isLoading &&
              _errorMessage == null &&
              _aggregatedItems.isNotEmpty)
            IconButton(
              icon: _isCreatingPurchase
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.shopping_cart_checkout),
              tooltip: _t('تحويل إلى طلب أو فاتورة شراء'),
              onPressed: _isCreatingPurchase
                  ? null
                  : _convertRequiredGoodsToPurchase,
            ),
          if (!_isLoading &&
              _errorMessage == null &&
              _productBreakdowns.isNotEmpty)
            TextButton.icon(
              icon: const Icon(Icons.table_chart_outlined, color: Colors.white),
              label: Text(
                _t('تفاصيل كل منتج'),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
              onPressed: _showProductBreakdownDialog,
            ),
          if (!_isLoading && _errorMessage == null)
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: _t('إعادة الحساب'),
              onPressed: _loadAndAggregate,
            ),
        ],
      ),
      body: _buildBody(),
      bottomNavigationBar: _isLoading || _errorMessage != null
          ? null
          : _buildBottomSummary(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(color: Color(0xFF1A237E)),
            const SizedBox(height: 16),
            Text(
              _t('جاري حساب السلع المطلوبة لجميع المنتجات...'),
              style: const TextStyle(color: Colors.grey, fontSize: 14),
            ),
          ],
        ),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: Colors.red, size: 60),
              const SizedBox(height: 12),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.red),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _loadAndAggregate,
                icon: const Icon(Icons.refresh),
                label: Text(_t('إعادة المحاولة')),
              ),
            ],
          ),
        ),
      );
    }

    if (_aggregatedItems.isEmpty) {
      final explanation = _processingWarnings.isNotEmpty
          ? _processingWarnings.join('\n')
          : _t('لا تحتوي الطلبية على منتجات فعالة قابلة للحساب.');
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.inventory_2_outlined,
                size: 72,
                color: Colors.grey,
              ),
              const SizedBox(height: 12),
              Text(
                _t('لا توجد سلع محسوبة للطلبية'),
                style: const TextStyle(fontSize: 16, color: Colors.grey),
              ),
              const SizedBox(height: 8),
              Text(
                explanation,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 14),
              OutlinedButton.icon(
                onPressed: _loadAndAggregate,
                icon: const Icon(Icons.refresh),
                label: Text(_t('إعادة الحساب')),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        // شريط معلومات الملخص
        _buildInfoBanner(),
        if (_processingWarnings.isNotEmpty) _buildWarningsBanner(),
        // القائمة
        Expanded(child: _buildGroupedList()),
      ],
    );
  }

  Widget _buildWarningsBanner() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.amber.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.amber.shade700),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, color: Colors.amber.shade900, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _processingWarnings.join('\n'),
              style: TextStyle(color: Colors.amber.shade900, fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoBanner() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1A237E), Color(0xFF3949AB)],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.indigo.withValues(alpha: 0.25),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          const Icon(Icons.inventory_2, color: Colors.white, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${_t('إجمالي')} ${_aggregatedItems.length} ${_t('نوع سلعة من')} $_productCount ${_t('منتج')}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _t('مطابقة لجدول الكمية والتكلفة • القطاعات بأعداد كاملة'),
                  style: const TextStyle(color: Colors.white70, fontSize: 11),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                _t('التكلفة الإجمالية'),
                style: const TextStyle(color: Colors.white70, fontSize: 10),
              ),
              Text(
                '${_grandTotal.toStringAsFixed(2)} دج',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildGroupedList() {
    // تجميع العناصر حسب الفئة ثم اللون للبروفيلات والإكسسوارات.
    final Map<String, List<AggregatedGoodItem>> grouped = {};
    for (final item in _aggregatedItems) {
      grouped.putIfAbsent(item.category, () => []).add(item);
    }
    final categories = grouped.keys.toList()
      ..sort((a, b) => _categorySortIndex(a).compareTo(_categorySortIndex(b)));

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 90),
      children: [
        for (final category in categories) ...[
          Builder(
            builder: (context) {
              final items = grouped[category]!;
              final categoryColor = _categoryColor(category);
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: categoryColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: categoryColor.withValues(alpha: 0.4),
                        ),
                      ),
                      child: Text(
                        _categoryLabel(category),
                        style: TextStyle(
                          color: categoryColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '(${items.length} ${_t('صنف')})',
                      style: TextStyle(
                        color: Colors.grey.shade500,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          if (category == 'profile' || category == 'accessory')
            for (final colorGroup in _colourGroupsFor(grouped[category]!)) ...[
              Padding(
                padding: const EdgeInsetsDirectional.only(
                  start: 8,
                  end: 8,
                  bottom: 5,
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.palette_outlined,
                      size: 15,
                      color: _categoryColor(category),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      colorGroup.key.split('|').last,
                      style: TextStyle(
                        color: _categoryColor(category),
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              ...colorGroup.value.map((item) => _buildItemCard(item, category)),
            ]
          else
            ...grouped[category]!.map((item) => _buildItemCard(item, category)),
          const SizedBox(height: 4),
        ],
      ],
    );
  }

  Future<int?> _seriesIdFor(AggregatedGoodItem item) async {
    if (item.inventoryItemType != 'Section' || item.catalogItemId == null) {
      return null;
    }
    final database = await widget.db.db;
    final rows = await database?.query(
      'Sections',
      columns: const ['series_id'],
      where: 'id = ?',
      whereArgs: [item.catalogItemId],
      limit: 1,
    );
    return rows == null || rows.isEmpty
        ? null
        : (rows.first['series_id'] as num?)?.toInt();
  }

  double _barRemainder(OrderCuttingPlan plan, List<double> cuts) {
    final used = cuts.fold<double>(0, (sum, cut) => sum + cut);
    final value = plan.stockLength - used - cuts.length * plan.bladeWaste;
    return value > 0 ? value : 0;
  }

  List<AggregatedGoodItem> get _cuttableCatalogItems => _aggregatedItems
      .where(
        (item) =>
            item.cuttingPlan != null &&
            item.catalogItemId != null &&
            item.inventoryItemType != null,
      )
      .toList();

  String _cuttingPlanSignature() {
    final parts = <String>[];
    for (final item in _cuttableCatalogItems) {
      final plan = item.cuttingPlan!;
      parts.add(
        '${item.inventoryItemType}:${item.catalogItemId}:${item.colorId ?? 0}:'
        '${(plan.stockLength * 1000).round()}:'
        '${item.cuttingPieces.map((piece) => (piece * 1000).round()).join(',')}',
      );
    }
    parts.sort();
    return parts.join('|');
  }

  Future<void> _approveAndStoreCuttingRemainders() async {
    if (_cuttableCatalogItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_t('لا توجد قطاعات ذات خطة قص لاعتمادها.'))),
      );
      return;
    }
    final locations = await widget.db.readLocations();
    if (!mounted || locations.isEmpty) return;
    final configuredMinimum = await widget.db.readMinimumReusableLengthMm();
    if (!mounted) return;

    var selectedLocationId = (locations.first['id'] as num).toInt();
    final minimumController = TextEditingController(
      text: configuredMinimum?.round().toString() ?? '',
    );
    final rackController = TextEditingController();
    final shelfController = TextEditingController();
    final binController = TextEditingController();
    final approved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(_t('اعتماد القص وتخزين البقايا')),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _t(
                      'لن يُضاف شيء للمخزون قبل هذا الاعتماد. الباقي الذي يساوي الحد الأدنى أو يتجاوزه يُحفظ كقطعة قابلة للاستعمال، وما دونه يُسجل كهالك.',
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: minimumController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: _t('أقل طول نحتفظ به (مم)'),
                      prefixIcon: const Icon(Icons.straighten),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int>(
                    initialValue: selectedLocationId,
                    decoration: InputDecoration(
                      labelText: _t('المخزن / الموقع'),
                      prefixIcon: const Icon(Icons.warehouse_outlined),
                      border: const OutlineInputBorder(),
                    ),
                    items: locations
                        .map(
                          (location) => DropdownMenuItem<int>(
                            value: (location['id'] as num).toInt(),
                            child: Text(location['name']?.toString() ?? ''),
                          ),
                        )
                        .toList(),
                    onChanged: (value) => setDialogState(() {
                      if (value != null) selectedLocationId = value;
                    }),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: rackController,
                          decoration: InputDecoration(
                            labelText: _t('رقم الرف'),
                            border: const OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: shelfController,
                          decoration: InputDecoration(
                            labelText: _t('المستوى'),
                            border: const OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: binController,
                          decoration: InputDecoration(
                            labelText: _t('الصندوق / الخانة'),
                            border: const OutlineInputBorder(),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(_t('إلغاء')),
            ),
            FilledButton.icon(
              onPressed: () {
                final minimum = double.tryParse(
                  minimumController.text.trim().replaceAll(',', '.'),
                );
                if (minimum == null || minimum <= 0) {
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    SnackBar(
                      content: Text(
                        _t('أدخل أقل طول محفوظ بقيمة أكبر من صفر.'),
                      ),
                    ),
                  );
                  return;
                }
                Navigator.pop(dialogContext, true);
              },
              icon: const Icon(Icons.inventory_2_outlined),
              label: Text(_t('اعتماد وحفظ')),
            ),
          ],
        ),
      ),
    );
    if (approved != true || !mounted) return;

    final minimum = double.parse(
      minimumController.text.trim().replaceAll(',', '.'),
    );
    await widget.db.saveMinimumReusableLengthMm(minimum);
    final bars = <Map<String, dynamic>>[];
    var globalBarIndex = 0;
    for (final item in _cuttableCatalogItems) {
      final plan = item.cuttingPlan!;
      final seriesId = await _seriesIdFor(item);
      for (final cuts in plan.bars) {
        bars.add({
          'item_id': item.catalogItemId,
          'item_type': item.inventoryItemType,
          'series_id': seriesId,
          'color_id': item.colorId,
          'bar_index': globalBarIndex++,
          'remainder_mm': _barRemainder(plan, cuts) * 1000,
          'kerf_loss_mm': cuts.length * plan.bladeWaste * 1000,
        });
      }
    }
    final result = await widget.db.saveOrderCuttingRemainders(
      orderId: _safeInt(widget.orderData['id'])!,
      planSignature: _cuttingPlanSignature(),
      bars: bars,
      minimumReusableLengthMm: minimum,
      locationId: selectedLocationId,
      rackCode: rackController.text,
      shelfCode: shelfController.text,
      binCode: binController.text,
    );
    if (!mounted) return;
    if (result['already_saved'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _t('تم اعتماد مخطط قص هذه الطلبية سابقًا؛ لم تُكرر الكميات.'),
          ),
        ),
      );
      return;
    }
    final savedRemnants = List<Map<String, dynamic>>.from(
      result['remnants'] as List? ?? const [],
    );
    final enriched = await widget.db.readMaterialRemnantsForOrder(
      _safeInt(widget.orderData['id'])!,
    );
    if (!mounted) return;
    final print = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(_t('تم حفظ نتيجة القص')),
        content: Text(
          '${_t('تم حفظ نتيجة القص')}: ${savedRemnants.length} ${_t(savedRemnants.length == 1 ? 'قطعة قابلة للاستعمال' : 'قطع قابلة للاستعمال')}، '
          '${result['scrap_count'] ?? 0} ${_t((result['scrap_count'] as num? ?? 0) == 1 ? 'سجل هالك' : 'سجلات هالك')}. ${_t('هل تريد طباعة تيكيتات القطع الآن؟')}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(_t('لاحقًا')),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(dialogContext, true),
            icon: const Icon(Icons.print_outlined),
            label: Text(_t('طباعة التيكيتات')),
          ),
        ],
      ),
    );
    if (print == true) await RemnantTicketService.printTickets(enriched);
  }

  Future<void> _showShortageReport() async {
    List<Map<String, dynamic>> allocateStock(
      List<Map<String, dynamic>> rows,
      double required,
    ) {
      var remaining = required;
      final allocations = <Map<String, dynamic>>[];
      for (final row in rows) {
        if (remaining <= 0.000001) break;
        final available = (row['quantity'] as num?)?.toDouble() ?? 0;
        if (available <= 0) continue;
        final used = available < remaining ? available : remaining;
        allocations.add({
          ...row,
          'allocated_quantity': used,
          'available_quantity': available,
        });
        remaining -= used;
      }
      return allocations;
    }

    // A Kit is a display/cost group, not an inventory product.  Stock must be
    // checked against its expanded components from the Kits page.  Flatten
    // those components here and aggregate equal catalogue records before
    // reading stock so two Kits cannot both claim the same available piece.
    final stockItemsByKey = <String, AggregatedGoodItem>{};

    String stockKey(AggregatedGoodItem item) {
      final identity =
          item.catalogItemId != null && item.inventoryItemType != null
          ? '${item.inventoryItemType}:${item.catalogItemId}'
          : item.originalName;
      return '$identity:${item.colorId ?? item.colorName ?? ''}:${item.unit}:${item.stockLength ?? ''}';
    }

    AggregatedGoodItem fromBom(BomItem bom) => AggregatedGoodItem(
      name: requiredGoodsDisplayName(bom),
      originalName: bom.originalName,
      category: requiredGoodsCategoryForBom(bom),
      unit: bom.unit,
      imagePath: bom.imagePath,
      unitPrice: bom.unitPrice,
      totalQuantity: bom.purchaseQuantity,
      totalCost: bom.total,
      profileCode: bom.profileCode,
      colorName: bom.colorName,
      stockLength: bom.length,
      glassHeight: bom.glassHeight,
      catalogItemId: bom.catalogItemId,
      inventoryItemType: bom.inventoryItemType,
      colorId: bom.colorId,
      isMissing: bom.isMissing,
      cuttingPieces: bomUsesOrderLevelCutting(bom)
          ? bom.pieces ?? const []
          : const [],
    );

    void addStockItem(AggregatedGoodItem candidate) {
      final key = stockKey(candidate);
      final existing = stockItemsByKey[key];
      if (existing == null) {
        stockItemsByKey[key] = candidate;
        return;
      }
      existing.totalQuantity += candidate.totalQuantity;
      existing.totalCost += candidate.totalCost;
      existing.cuttingPieces.addAll(candidate.cuttingPieces);
    }

    for (final item in _aggregatedItems) {
      final kitName = item.kitGroupName;
      if (kitName != null && kitName.isNotEmpty) {
        for (final child in item.kitSubItems) {
          final isKitHeader = !child.originalName.startsWith('${kitName}_');
          if (!isKitHeader) addStockItem(fromBom(child));
        }
      } else {
        addStockItem(
          AggregatedGoodItem(
            name: item.name,
            originalName: item.originalName,
            category: item.category,
            unit: item.unit,
            imagePath: item.imagePath,
            unitPrice: item.unitPrice,
            totalQuantity: item.totalQuantity,
            totalCost: item.totalCost,
            profileCode: item.profileCode,
            colorName: item.colorName,
            stockLength: item.stockLength,
            glassHeight: item.glassHeight,
            catalogItemId: item.catalogItemId,
            inventoryItemType: item.inventoryItemType,
            colorId: item.colorId,
            isMissing: item.isMissing,
            cuttingPieces: item.cuttingPieces,
          ),
        );
      }
    }

    final reports = <Map<String, dynamic>>[];
    for (final item in stockItemsByKey.values) {
      final itemId = item.catalogItemId;
      final itemType = item.inventoryItemType;
      if (itemId == null || itemType == null) {
        reports.add({'item': item, 'unlinked': true});
        continue;
      }
      final stockRows = await widget.db.readStockAvailability(
        itemId: itemId,
        itemType: itemType,
        colorId: item.colorId,
      );
      final stockAvailable = stockRows.fold<double>(
        0,
        (sum, row) => sum + ((row['quantity'] as num?)?.toDouble() ?? 0),
      );

      if (item.cuttingPieces.isNotEmpty && (item.stockLength ?? 0) > 0) {
        final seriesId = await _seriesIdFor(item);
        final remnantRows = await widget.db.readAvailableMaterialRemnants(
          itemId: itemId,
          itemType: itemType,
          colorId: item.colorId,
          seriesId: seriesId,
        );
        final remnantPlan = optimizeCuttingWithRemnants(
          pieces: item.cuttingPieces,
          remnants: remnantRows.map(
            (row) => AvailableRemnantPiece(
              id: (row['id'] as num).toInt(),
              length: ((row['length_mm'] as num).toDouble()) / 1000,
              data: row,
            ),
          ),
          stockLength: item.stockLength!,
        );
        final neededBars = remnantPlan.fullBarPlan.barCount;
        final stockAllocations = allocateStock(
          stockRows,
          neededBars.toDouble(),
        );
        final stockUsed = stockAllocations.fold<double>(
          0,
          (sum, row) =>
              sum + ((row['allocated_quantity'] as num?)?.toDouble() ?? 0),
        );
        reports.add({
          'item': item,
          'stock_rows': stockAllocations,
          'stock_used': stockUsed,
          'missing': (neededBars - stockAvailable).clamp(0, double.infinity),
          'remnant_plan': remnantPlan,
        });
      } else {
        final stockAllocations = allocateStock(stockRows, item.totalQuantity);
        final stockUsed = stockAllocations.fold<double>(
          0,
          (sum, row) =>
              sum + ((row['allocated_quantity'] as num?)?.toDouble() ?? 0),
        );
        reports.add({
          'item': item,
          'stock_rows': stockAllocations,
          'stock_used': stockUsed,
          'missing': (item.totalQuantity - stockAvailable).clamp(
            0,
            double.infinity,
          ),
        });
      }
    }
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => _OrderShortageReportPage(
          orderId: _safeInt(widget.orderData['id'])!,
          reports: reports,
        ),
      ),
    );
  }

  Future<void> _showSectionSelectionDialog(
    AggregatedGoodItem item,
    String category,
  ) async {
    if (_productBreakdowns.isEmpty) return;
    final model = _productBreakdowns.first.model;
    final activeSeries = model.activeSlidingSeries ?? model.activeSeries;
    if (activeSeries == null) return;

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final dbInstance = await widget.db.db;
    if (dbInstance == null) return;

    final origLower = item.originalName.toLowerCase();

    // Fetch all active sections for the active series
    final rawSections = await dbInstance.query(
      'Sections',
      where: 'series_id = ? AND (is_active = 1 OR is_active IS NULL)',
      whereArgs: [activeSeries.id],
    );

    if (rawSections.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_t('لا توجد قطاعات متوفرة لهذه السلسلة'))),
      );
      return;
    }

    List<Map<String, dynamic>> filteredSections = [];

    if (origLower.contains('rail') || origLower.contains('سكة')) {
      // 1. السكة Rail: جلب نوع rail فقط واستبعاد الإطارات Cadre 2 Rail / Cadre 3 Rail
      filteredSections = rawSections.where((s) {
        final t = (s['type'] ?? '').toString().toLowerCase();
        final n = (s['name'] ?? '').toString().toLowerCase();
        return (t == 'rail' || t.contains('rail') || n.startsWith('rail')) &&
            !t.contains('frame') &&
            !t.contains('cadre') &&
            !n.contains('cadre') &&
            !n.contains('إطار');
      }).toList();
    } else if (origLower.contains('réducteur') ||
        origLower.contains('ريديكتور') ||
        origLower.contains('reducteur') ||
        origLower.contains('مخفض')) {
      // 2. الريديكتور Réducteur: جلب كود 67114 أو reducteur واستبعاد الإطارات والسكك
      filteredSections = rawSections.where((s) {
        final t = (s['type'] ?? '').toString().toLowerCase();
        final n = (s['name'] ?? '').toString().toLowerCase();
        final c = (s['code'] ?? '').toString().toLowerCase();
        return (c.contains('67114') ||
                t.contains('reduct') ||
                n.contains('reduct') ||
                n.contains('مخفض') ||
                n.contains('ريديكتور')) &&
            !t.contains('frame') &&
            !t.contains('cadre') &&
            !t.contains('rail') &&
            !n.contains('cadre') &&
            !n.contains('إطار') &&
            !n.contains('rail') &&
            !n.contains('سكة');
      }).toList();
    } else if (origLower.contains('side cover') ||
        origLower.contains('غطاء جانبي') ||
        origLower.contains('couvre')) {
      // 3. الغطاء الجانبي Couvre-joint
      filteredSections = rawSections.where((s) {
        final t = (s['type'] ?? '').toString().toLowerCase();
        final n = (s['name'] ?? '').toString().toLowerCase();
        return t.contains('couvre') ||
            t.contains('side_cover') ||
            n.contains('couvre') ||
            n.contains('جانبي') ||
            n.contains('غطاء');
      }).toList();
    } else if (origLower.contains('sash lateral') ||
        origLower.contains('قائم جانبي') ||
        origLower.contains('latéral') ||
        origLower.contains('lateral')) {
      // 4. القائم الجانبي Ouvrant Latéral: مطابقة الكود 67108 (المدعم) والكود 67104 (غير المدعم)
      filteredSections = rawSections.where((s) {
        final c = (s['code'] ?? '').toString().toLowerCase();
        final n = (s['name'] ?? '').toString().toLowerCase();
        final t = (s['type'] ?? '').toString().toLowerCase();
        return c.contains('67108') ||
            c.contains('67104') ||
            c.endsWith('108') ||
            c.endsWith('104') ||
            ((t.contains('sash') || t.contains('ouvrant')) &&
                (n.contains('latéral') ||
                    n.contains('lateral') ||
                    n.contains('جانبي')) &&
                !n.contains('central') &&
                !n.contains('chicane') &&
                !c.contains('105') &&
                !c.contains('107'));
      }).toList();
    } else if (origLower.contains('sash central') ||
        origLower.contains('قائم وسطي') ||
        origLower.contains('central') ||
        origLower.contains('chicane')) {
      // 5. القائم الوسطي Ouvrant Central: تصفية القوائم الوسطية واستبعاد الجانبي
      filteredSections = rawSections.where((s) {
        final t = (s['type'] ?? '').toString().toLowerCase();
        final n = (s['name'] ?? '').toString().toLowerCase();
        final c = (s['code'] ?? '').toString().toLowerCase();
        return (t.contains('sash') || t.contains('ouvrant')) &&
            (t.contains('central') ||
                n.contains('central') ||
                n.contains('وسطي') ||
                n.contains('chicane') ||
                c.contains('105') ||
                c.contains('107')) &&
            !n.contains('latéral') &&
            !n.contains('جانبي');
      }).toList();
    } else if (category == 'frame') {
      // الإطار Frame
      filteredSections = rawSections.where((s) {
        final t = (s['type'] ?? '').toString().toLowerCase();
        return t.contains('frame') || t.contains('cadre') || t.contains('إطار');
      }).toList();
    } else {
      filteredSections = List.from(rawSections);
    }

    if (filteredSections.isEmpty) {
      filteredSections = List.from(rawSections);
    }

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? const Color(0xFF1E1E2C) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'تغيير قطاع: ${item.name}',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const Divider(),
              Expanded(
                child: ListView.builder(
                  itemCount: filteredSections.length,
                  itemBuilder: (context, idx) {
                    final sec = filteredSections[idx];
                    final secName = sec['name'] ?? 'بدون اسم';
                    final secCode = sec['code'] ?? '';
                    final imagePath = sec['image_path']?.toString();
                    final displayLabel = secCode.toString().isNotEmpty
                        ? '$secCode - $secName'
                        : secName.toString();

                    return ListTile(
                      leading: SizedBox(
                        width: 36,
                        height: 36,
                        child: SectionImageWidget(
                          code: secCode.toString(),
                          imagePath: imagePath,
                          size: 32,
                        ),
                      ),
                      title: Text(
                        displayLabel,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                      trailing: const Icon(Icons.chevron_right, size: 20),
                      onTap: () async {
                        Navigator.pop(ctx);

                        final sqlDb = SqlDatabase();
                        int? colorId;
                        for (var pb in _productBreakdowns) {
                          if (pb.model.selectedDbColor != null) {
                            colorId = pb.model.selectedDbColor!['id'] as int?;
                            break;
                          }
                        }

                        double price = 0.0;
                        if (colorId != null && sec['id'] != null) {
                          price = await sqlDb.getSectionPrice(
                            sec['id'] as int,
                            colorId,
                          );
                        }
                        if (price <= 0) {
                          price = (sec['price'] as num?)?.toDouble() ?? 0.0;
                        }

                        final mutableSec = Map<String, dynamic>.from(sec);
                        mutableSec['calculated_price'] = price;

                        for (var pb in _productBreakdowns) {
                          pb.model.componentOverrides[item.originalName] =
                              mutableSec;
                          if (category == 'frame') {
                            pb.model.frameOverride = mutableSec;
                            pb.model.slidingFrameOverride = mutableSec;
                          } else if (origLower.contains('side cover') ||
                              origLower.contains('غطاء جانبي')) {
                            pb.model.sideCoverOverride = mutableSec;
                          }
                        }

                        _loadAndAggregate();
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildItemCard(AggregatedGoodItem item, String category) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = _categoryColor(category);
    final purchaseLabel = _purchaseQuantityLabel(item);
    final itemMeta = _itemMeta(item);

    final isKit = item.kitGroupName != null && item.kitGroupName!.isNotEmpty;
    final isExpanded = _expandedKits.contains(item.name);

    if (isKit) {
      return Container(
        margin: const EdgeInsets.only(bottom: 6),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.15)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          children: [
            InkWell(
              onTap: () {
                setState(() {
                  if (isExpanded) {
                    _expandedKits.remove(item.name);
                  } else {
                    _expandedKits.add(item.name);
                  }
                });
              },
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    // مؤشر الفئة (شريط جانبي ملون)
                    Container(
                      width: 4,
                      height: 44,
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(width: 10),
                    // أيقونة الطقم
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(Icons.inventory, color: color, size: 24),
                    ),
                    const SizedBox(width: 10),
                    // الاسم والتفاصيل
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _t(item.name),
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              color: isDark
                                  ? Colors.white
                                  : const Color(0xFF1A1A2E),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _currentLang == AppLanguage.arabic
                                ? 'يحتوي على ${item.kitSubItems.length} مكونات (انقر للعرض)'
                                : _currentLang == AppLanguage.french
                                ? 'Contient ${item.kitSubItems.length} composants (cliquez pour afficher)'
                                : 'Contains ${item.kitSubItems.length} components (click to view)',
                            style: TextStyle(
                              color: isDark
                                  ? Colors.white60
                                  : Colors.grey.shade500,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    // الكمية والتكلفة
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            purchaseLabel,
                            style: TextStyle(
                              color: color,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${item.totalCost.toStringAsFixed(2)} دج',
                          style: TextStyle(
                            color: isDark
                                ? Colors.white70
                                : Colors.grey.shade700,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      isExpanded ? Icons.expand_less : Icons.expand_more,
                      color: Colors.grey.shade500,
                      size: 20,
                    ),
                  ],
                ),
              ),
            ),
            if (isExpanded) ...[
              const Divider(height: 1),
              Container(
                color: isDark ? const Color(0xFF161616) : Colors.grey.shade50,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Column(
                  children: item.kitSubItems.map((sub) {
                    final subRoundedQty = _roundQuantity(
                      sub.purchaseQuantity,
                      sub.unit,
                    );
                    final subCost = sub.total;
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Icon(
                            Icons.subdirectory_arrow_left,
                            size: 14,
                            color: Colors.grey.shade400,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              _t(sub.name),
                              style: TextStyle(
                                fontSize: 12,
                                color: isDark ? Colors.white70 : Colors.black87,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Text(
                            '$subRoundedQty ${_t(sub.unit)}',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: isDark
                                  ? Colors.white60
                                  : Colors.grey.shade700,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            '${subCost.toStringAsFixed(2)} دج',
                            style: TextStyle(
                              fontSize: 11,
                              color: isDark
                                  ? Colors.white60
                                  : Colors.grey.shade700,
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ],
        ),
      );
    }

    final plan = item.cuttingPlan;
    final cuttingKey =
        '${item.inventoryItemType}:${item.catalogItemId}:${item.colorId}:${item.stockLength}:${item.originalName}';
    final isCuttingExpanded = _expandedCuttingPlans.contains(cuttingKey);

    final itemRow = Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.15)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: category == 'profile'
              ? () => _showSectionSelectionDialog(item, category)
              : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                // مؤشر الفئة (شريط جانبي ملون)
                Container(
                  width: 4,
                  height: 44,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(width: 10),
                // الصورة أو الأيقونة
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: SectionImageWidget(
                      code: item.profileCode,
                      imagePath: item.imagePath,
                      size: 32.0,
                      fallbackIcon: _categoryIcon(category),
                      fallbackColor: color,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                // الاسم والتفاصيل (العنوان الرئيسي عريض والتفاصيل بخط رقيق تحته)
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // الاسم الفعلي للصنف، مهم خصوصاً للإكسسوارات التي
                      // تشترك أدوارها الحسابية في اسم عام واحد.
                      Text(
                        _t(item.name),
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: isDark
                              ? Colors.white
                              : const Color(0xFF1A1A2E),
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (item.name != item.originalName) ...[
                        const SizedBox(height: 2),
                        Text(
                          '${_t('المكوّن المطلوب')}: ${_t(item.originalName)}',
                          style: TextStyle(
                            color: isDark
                                ? Colors.white60
                                : Colors.grey.shade600,
                            fontSize: 10.5,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      if (itemMeta.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          itemMeta,
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: isDark
                                ? Colors.white60
                                : Colors.grey.shade600,
                            fontSize: 10.5,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      const SizedBox(height: 3),
                      // السعر والوحدة؛ الاسم أعلاه هو اسم الصنف الفعلي.
                      Text(
                        item.unitPrice > 0
                            ? '${item.unitPrice.toStringAsFixed(2)} دج / ${_t(item.unit)}'
                            : category == 'profile'
                            ? '📌 ${_t('انقر هنا لاختيار القطاع المناسب')}'
                            : _t('السعر غير محدد'),
                        style: TextStyle(
                          fontWeight: FontWeight.w400,
                          color: isDark ? Colors.white60 : Colors.grey.shade700,
                          fontSize: 11,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                // الكمية والتكلفة
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        purchaseLabel,
                        style: TextStyle(
                          color: color,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${item.totalCost.toStringAsFixed(2)} دج',
                      style: TextStyle(
                        color: isDark ? Colors.white70 : Colors.grey.shade700,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (plan == null) return itemRow;

    return Column(
      children: [
        itemRow,
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: InkWell(
            onTap: () => setState(() {
              if (isCuttingExpanded) {
                _expandedCuttingPlans.remove(cuttingKey);
              } else {
                _expandedCuttingPlans.add(cuttingKey);
              }
            }),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: color.withValues(alpha: isDark ? 0.12 : 0.06),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.content_cut, size: 16, color: color),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'خطة التقطيع العلمية: ${plan.barCount} قطاع من طول '
                          '${(plan.stockLength * 1000).round()} مم',
                          style: TextStyle(
                            color: color,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      Icon(
                        isCuttingExpanded
                            ? Icons.expand_less
                            : Icons.expand_more,
                        color: color,
                        size: 18,
                      ),
                    ],
                  ),
                  if (isCuttingExpanded) ...[
                    const SizedBox(height: 8),
                    ...plan.bars.indexed.map((entry) {
                      final barNumber = entry.$1 + 1;
                      final cuts = entry.$2;
                      final used = cuts.fold<double>(
                        0,
                        (sum, cut) => sum + cut,
                      );
                      final remainder =
                          plan.stockLength -
                          used -
                          (cuts.length * plan.bladeWaste);
                      final cutText = cuts
                          .map((cut) => '${(cut * 1000).round()}')
                          .join(' + ');
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          'قطاع $barNumber: $cutText مم — الباقي '
                          '${(remainder > 0 ? remainder * 1000 : 0).round()} مم',
                          style: TextStyle(
                            fontSize: 10.5,
                            color: isDark ? Colors.white70 : Colors.black87,
                          ),
                        ),
                      );
                    }),
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBottomSummary() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.08),
            blurRadius: 10,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: SafeArea(
        child: Row(
          children: [
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${_aggregatedItems.length} ${_t('صنف من السلع')}',
                    style: TextStyle(
                      color: isDark ? Colors.white70 : Colors.grey.shade600,
                      fontSize: 12,
                    ),
                  ),
                  Text(
                    '${_grandTotal.toStringAsFixed(2)} دج',
                    style: TextStyle(
                      color: isDark ? Colors.white : const Color(0xFF1A237E),
                      fontWeight: FontWeight.bold,
                      fontSize: 20,
                    ),
                  ),
                ],
              ),
            ),
            ElevatedButton.icon(
              onPressed: _loadAndAggregate,
              icon: const Icon(Icons.refresh, size: 18),
              label: Text(_t('تحديث')),
              style: ElevatedButton.styleFrom(
                backgroundColor: isDark
                    ? Colors.black
                    : const Color(0xFF1A237E),
                foregroundColor: Colors.white,
                side: isDark
                    ? const BorderSide(color: Colors.white, width: 1.5)
                    : BorderSide.none,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                shape: isDark
                    ? RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      )
                    : RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────
  // دوال مساعدة
  // ─────────────────────────────────────────────────────────────────

  /// الوحدات المستمرة تبقى عشرية، أما وحدات الشراء العددية فتعرض أعدادًا كاملة.
  String _roundQuantity(double qty, String unit) {
    final unitLower = unit.toLowerCase();
    if (unitLower == 'ml' ||
        unitLower == 'م' ||
        unitLower == 'm²' ||
        unitLower == 'م²' ||
        unitLower == 'sqm' ||
        unitLower.contains('متر') ||
        unitLower.contains('meter') ||
        unitLower.contains('مساحة')) {
      return qty.toStringAsFixed(2);
    }
    // وحدات عدد: اعرض عددًا صحيحًا مع تقريب للأعلى
    final rounded = qty.ceil();
    return '$rounded';
  }

  String _purchaseQuantityLabel(AggregatedGoodItem item) {
    final formatted = _roundQuantity(item.totalQuantity, item.unit);
    final unit = item.unit.toLowerCase().trim();
    if (unit == 'قطاع' ||
        unit == 'بارة' ||
        unit == 'bar' ||
        unit == 'section') {
      return '$formatted ${_t('قطاع')}';
    }
    return '$formatted ${_t(item.unit)}';
  }

  String _itemMeta(AggregatedGoodItem item) {
    final parts = <String>[];
    if (item.profileCode != null && item.profileCode!.trim().isNotEmpty) {
      parts.add('${_t('الكود')}: ${item.profileCode}');
    }
    if (item.category != 'glass' &&
        item.category != 'panneau' &&
        item.colorName != null &&
        item.colorName!.trim().isNotEmpty) {
      parts.add('${_t('اللون')}: ${_t(item.colorName!)}');
    }
    if (item.category == 'glass' &&
        (item.stockLength ?? 0) > 0 &&
        (item.glassHeight ?? 0) > 0) {
      parts.add(
        '${_t('القياس')}: ${item.stockLength!.round()} × ${item.glassHeight!.round()} mm',
      );
      parts.add(
        '${_t('المساحة المطلوبة')}: ${_roundQuantity(item.totalQuantity, 'm²')} m²',
      );
    } else if (item.stockLength != null && item.stockLength! > 0) {
      final unit = item.category == 'profile' ? 'م' : '';
      final value = item.category == 'profile'
          ? item.stockLength!.toStringAsFixed(2)
          : item.stockLength!.toStringAsFixed(0);
      parts.add('${_t('القياس')}: $value ${_t(unit)}'.trim());
    }
    if (item.isMissing) {
      parts.add(_t('غير مرتبط بقاعدة البيانات'));
    }
    final plan = item.cuttingPlan;
    if (plan != null) {
      parts.add('تقطيع موحّد: ${item.cuttingPieces.length} قطعة');
      parts.add('الباقي: ${(plan.wasteLength * 1000).round()} مم');
    } else if (item.cuttingPieces.isNotEmpty) {
      final visiblePieces = item.cuttingPieces
          .take(5)
          .map((piece) => '${(piece * 1000).round()}')
          .join('، ');
      final suffix = item.cuttingPieces.length > 5
          ? ' (+${item.cuttingPieces.length - 5})'
          : '';
      parts.add('القصات: $visiblePieces مم$suffix');
    }
    return parts.join(' • ');
  }

  void _showProductBreakdownDialog() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => Scaffold(
          backgroundColor: isDark
              ? const Color(0xFF121212)
              : const Color(0xFFF0F4FF),
          appBar: AppBar(
            title: const Text(
              'تفاصيل حساب كل منتج',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            backgroundColor: isDark
                ? Theme.of(context).appBarTheme.backgroundColor
                : const Color(0xFF1A237E),
            foregroundColor: Colors.white,
          ),
          body: ListView.builder(
            padding: const EdgeInsets.all(16.0),
            itemCount: _productBreakdowns.length,
            itemBuilder: (context, index) {
              final pb = _productBreakdowns[index];
              return Card(
                elevation: 3,
                margin: const EdgeInsets.only(bottom: 24.0),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12.0),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // 1. Drawing thumbnail
                          Container(
                            width: 120,
                            height: 120,
                            decoration: BoxDecoration(
                              color: isDark
                                  ? Colors.grey.shade900
                                  : Colors.white,
                              borderRadius: BorderRadius.circular(8.0),
                              border: Border.all(
                                color: isDark
                                    ? Colors.grey.shade800
                                    : Colors.grey.shade300,
                              ),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8.0),
                              child: pb.model.isCaissonTunnel
                                  ? Image.asset(
                                      'Icon/caisson_tunnel.jpg',
                                      fit: BoxFit.contain,
                                      errorBuilder:
                                          (
                                            context,
                                            error,
                                            stackTrace,
                                          ) => Image.asset(
                                            'assets/Icon/caisson_tunnel.jpg',
                                            fit: BoxFit.contain,
                                          ),
                                    )
                                  : CustomPaint(
                                      painter: WindowPainter(model: pb.model),
                                    ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          // 2. Product basic info
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  pb.name,
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                    color: isDark
                                        ? Colors.white
                                        : const Color(0xFF1A237E),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  '${_t('المقاس')}: ${pb.width.toStringAsFixed(0)} mm × ${pb.height.toStringAsFixed(0)} mm',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: isDark
                                        ? Colors.white.withValues(alpha: 0.9)
                                        : Colors.black87,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${_t('الكمية')}: ${pb.qty} ${_t('حبة')}',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                    color: isDark
                                        ? Colors.white
                                        : Colors.black87,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${_t('السلسلة')}: ${pb.model.activeSeries?.name ?? pb.model.activeSlidingSeries?.name ?? _t('غير محدد')}',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: isDark
                                        ? Colors.white70
                                        : Colors.grey.shade700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const Divider(height: 24),
                      // 3. Materials List
                      Text(
                        _t('العناصر والمواد المحسوبة لهذا المنتج:'),
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: isDark ? Colors.white70 : Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Table(
                        border: TableBorder.symmetric(
                          inside: BorderSide(
                            color: isDark
                                ? Colors.grey.shade800
                                : Colors.grey.shade300,
                            width: 0.5,
                          ),
                        ),
                        columnWidths: const {
                          0: FlexColumnWidth(3),
                          1: FlexColumnWidth(1),
                          2: FlexColumnWidth(1),
                          3: FlexColumnWidth(1.2),
                        },
                        children: [
                          TableRow(
                            decoration: BoxDecoration(
                              color: isDark
                                  ? Colors.grey.shade900
                                  : Colors.grey.shade200,
                            ),
                            children: [
                              Padding(
                                padding: const EdgeInsets.all(6.0),
                                child: Text(
                                  _t('اسم العنصر'),
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                    color: isDark
                                        ? Colors.white.withValues(alpha: 0.87)
                                        : Colors.black87,
                                  ),
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.all(6.0),
                                child: Text(
                                  _t('الكمية'),
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                    color: isDark
                                        ? Colors.white.withValues(alpha: 0.87)
                                        : Colors.black87,
                                  ),
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.all(6.0),
                                child: Text(
                                  _t('الوحدة'),
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                    color: isDark
                                        ? Colors.white.withValues(alpha: 0.87)
                                        : Colors.black87,
                                  ),
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.all(6.0),
                                child: Text(
                                  _t('التكلفة'),
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                    color: isDark
                                        ? Colors.white.withValues(alpha: 0.87)
                                        : Colors.black87,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          ...pb.bomItems.map((bom) {
                            final double qty = bom.purchaseQuantity;
                            final double cost = bom.total;
                            return TableRow(
                              children: [
                                Padding(
                                  padding: const EdgeInsets.all(6.0),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      SectionImageWidget(
                                        code: bom.profileCode,
                                        imagePath: bom.imagePath,
                                        size: 18.0,
                                        fallbackIcon: _categoryIcon(
                                          bom.category,
                                        ),
                                        fallbackColor: Colors.grey,
                                      ),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Text(
                                          bom.name,
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: isDark
                                                ? Colors.white.withValues(
                                                    alpha: 0.9,
                                                  )
                                                : Colors.black87,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.all(6.0),
                                  child: Text(
                                    _roundQuantity(qty, bom.unit),
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: isDark
                                          ? Colors.white.withValues(alpha: 0.9)
                                          : Colors.black87,
                                    ),
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.all(6.0),
                                  child: Text(
                                    bom.unit,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: isDark
                                          ? Colors.white.withValues(alpha: 0.9)
                                          : Colors.black87,
                                    ),
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.all(6.0),
                                  child: Text(
                                    '${cost.toStringAsFixed(0)} د.ج',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: isDark
                                          ? Colors.white70
                                          : Colors.black87,
                                    ),
                                  ),
                                ),
                              ],
                            );
                          }),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  IconData _categoryIcon(String category) {
    switch (category) {
      case 'frame':
        return Icons.square_outlined;
      case 'sash':
        return Icons.open_in_new;
      case 'mullion':
        return Icons.horizontal_rule;
      case 'glass':
        return Icons.grid_on;
      case 'shutter':
        return Icons.layers;
      case 'caisson_tunnel':
        return Icons.dns_rounded;
      case 'accessory':
        return Icons.settings;
      default:
        return Icons.inventory_2;
    }
  }
}

class _OrderShortageReportPage extends StatelessWidget {
  const _OrderShortageReportPage({
    required this.orderId,
    required this.reports,
  });

  final int orderId;
  final List<Map<String, dynamic>> reports;

  String _quantity(double value) => value == value.roundToDouble()
      ? value.round().toString()
      : value.toStringAsFixed(2);

  String _address(Map<String, dynamic> row) =>
      RemnantTicketService.storageAddress(row);

  @override
  Widget build(BuildContext context) {
    final lang = Provider.of<AppSettingsProvider>(context).language;
    String t(String key) => Localization.translate(key, lang);
    final totalMissingKinds = reports.where((report) {
      if (report['unlinked'] == true) return true;
      return ((report['missing'] as num?)?.toDouble() ?? 0) > 0.000001;
    }).length;
    return Scaffold(
      appBar: AppBar(
        title: Text('${t('تقرير نواقص الطلبية')} #$orderId'),
        backgroundColor: const Color(0xFF1A237E),
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 40),
        children: [
          Card(
            color: totalMissingKinds == 0
                ? Colors.green.withValues(alpha: 0.1)
                : Colors.orange.withValues(alpha: 0.1),
            child: ListTile(
              leading: Icon(
                totalMissingKinds == 0
                    ? Icons.check_circle_outline
                    : Icons.warning_amber_rounded,
                color: totalMissingKinds == 0 ? Colors.green : Colors.orange,
              ),
              title: Text(
                totalMissingKinds == 0
                    ? t('كل السلع المرتبطة متوفرة')
                    : '$totalMissingKinds ${t(totalMissingKinds == 1 ? 'صنف يحتاج شراء أو ربطًا بقاعدة البيانات' : 'أصناف تحتاج شراء أو ربطًا بقاعدة البيانات')}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Text(
                t(
                  'هذا تقرير حسابي: يستخدم البقايا المطابقة أولًا ثم القطاعات الكاملة الموجودة في المخزون، ولا يخصم فعليًا قبل اعتماد الصرف.',
                ),
              ),
            ),
          ),
          ...reports.map((report) {
            final item = report['item'] as AggregatedGoodItem;
            final unlinked = report['unlinked'] == true;
            final missing = (report['missing'] as num?)?.toDouble() ?? 0;
            final stockUsed = (report['stock_used'] as num?)?.toDouble() ?? 0;
            final stockRows = List<Map<String, dynamic>>.from(
              report['stock_rows'] as List? ?? const [],
            );
            final remnantPlan =
                report['remnant_plan'] as InventoryAwareCuttingPlan?;
            final neededAfterRemnants =
                remnantPlan?.fullBarPlan.barCount.toDouble() ??
                item.totalQuantity;
            return Card(
              margin: const EdgeInsets.only(top: 10),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${item.profileCode == null ? '' : '[${item.profileCode}] '}${item.name}',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                        ),
                        Chip(
                          label: Text(
                            unlinked
                                ? t('غير مرتبط')
                                : missing > 0
                                ? '${t('الناقص')} ${_quantity(missing)}'
                                : t('متوفر'),
                          ),
                          backgroundColor: unlinked || missing > 0
                              ? Colors.red.withValues(alpha: 0.12)
                              : Colors.green.withValues(alpha: 0.12),
                        ),
                      ],
                    ),
                    if (item.colorName?.trim().isNotEmpty == true)
                      Text('${t('اللون')}: ${item.colorName}'),
                    if (unlinked)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          t(
                            'لا يمكن مقارنة هذا الصنف بالمخزون لأنه غير مرتبط بسجل كتالوج محدد.',
                          ),
                          style: const TextStyle(color: Colors.red),
                        ),
                      )
                    else ...[
                      const SizedBox(height: 8),
                      Text(
                        '${t('المطلوب بعد استعمال البقايا')}: ${_quantity(neededAfterRemnants)} ${item.unit}',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      if (remnantPlan != null &&
                          remnantPlan.remnantUsages.isNotEmpty) ...[
                        const Divider(),
                        Text(
                          t('بقايا مطابقة استُعملت في الحساب'),
                          style: const TextStyle(
                            color: Colors.teal,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        ...remnantPlan.remnantUsages.map((usage) {
                          final row = usage.remnant.data;
                          final cuts = usage.cuts
                              .map((cut) => '${(cut * 1000).round()} مم')
                              .join(' + ');
                          return ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(
                              Icons.recycling,
                              color: Colors.teal,
                            ),
                            title: Text(
                              '${row['ticket_code']} — ${t('طولها')} ${(usage.remnant.length * 1000).round()} ${t('مم')}',
                            ),
                            subtitle: Text(
                              '${t('القص')}: $cuts\n${_address(row)} — ${t('سيبقى')} ${(usage.remainingLength * 1000).round()} ${t('مم')}',
                            ),
                          );
                        }),
                      ],
                      if (stockUsed > 0) ...[
                        const Divider(),
                        Text(
                          '${t('من القطاعات/القطع الكاملة في المخزون')}: ${_quantity(stockUsed)}',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        ...stockRows.map(
                          (row) => Text(
                            '• ${row['location_name'] ?? t('موقع غير مسمى')}: ${t('استُعمل')} '
                            '${_quantity((row['allocated_quantity'] as num?)?.toDouble() ?? 0)} '
                            '${t('من أصل')} ${_quantity((row['available_quantity'] as num?)?.toDouble() ?? 0)}',
                          ),
                        ),
                      ],
                      if (missing > 0)
                        Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: Text(
                            '${t('الشراء المطلوب')}: ${_quantity(missing)} ${item.unit}',
                            style: const TextStyle(
                              color: Colors.red,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ),
                    ],
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}
