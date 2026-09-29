import 'dart:convert';
import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../services/pdf_font_cache.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:database_data/settings/app_settings.dart';
import 'package:database_data/sql_database.dart';
import 'package:database_data/Commande/Systeme/model.dart';
import 'package:database_data/Commande/Systeme/model_serialization.dart';
import 'package:database_data/Commande/Systeme/calculate_component.dart';
import 'package:database_data/Commande/Systeme/bom_engine_v2.dart';
import 'package:database_data/Commande/Systeme/cutting_settings.dart';
import 'package:database_data/Commande/window_painter.dart';
import 'package:database_data/Commande/capture_image.dart';
import 'package:database_data/widgets/section_image.dart';
import 'package:database_data/widgets/resizable_columns_table.dart';
import 'package:database_data/services/remnant_ticket_service.dart';
import 'package:database_data/settings/localization.dart';
import 'package:database_data/Screen/achat_details_screen.dart';
import 'package:database_data/Screen/app_workspace_shell.dart'
    show openAdaptiveScreen;

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

/// The order-line quantity is authoritative. Older measurement drafts often
/// contain one default instance with qty=1, even when the order asks for many
/// windows; treating that draft as the complete line underestimates every BOM
/// component. Keep measured variants, then add the unmeasured remainder using
/// the drawing's original dimensions.
List<Map<String, dynamic>> normalizeRequiredGoodsInstances({
  required List<Map<String, dynamic>> saved,
  required int orderedQuantity,
  required double defaultWidth,
  required double defaultHeight,
}) {
  int positiveInt(Object? value, {int fallback = 0}) {
    final parsed = value is num
        ? value.toInt()
        : int.tryParse(value?.toString().trim() ?? '');
    return parsed != null && parsed > 0 ? parsed : fallback;
  }

  double positiveDouble(Object? value, double fallback) {
    final parsed = value is num
        ? value.toDouble()
        : double.tryParse(value?.toString().trim() ?? '');
    return parsed != null && parsed > 0 ? parsed : fallback;
  }

  final normalized = saved
      .map(
        (raw) => <String, dynamic>{
          ...raw,
          'width': positiveDouble(raw['width'] ?? raw['largeur'], defaultWidth),
          'height': positiveDouble(
            raw['height'] ?? raw['hauteur'],
            defaultHeight,
          ),
          'qty': positiveInt(raw['qty'] ?? raw['quantity'], fallback: 1),
        },
      )
      .where((item) => (item['qty'] as int) > 0)
      .toList();
  final expected = orderedQuantity > 0 ? orderedQuantity : 1;

  if (normalized.isEmpty) {
    return [
      {'width': defaultWidth, 'height': defaultHeight, 'qty': expected},
    ];
  }

  // Measurements are a breakdown of the order line, never an independent
  // source of quantity. A stale draft can contain more measured instances
  // than the order currently requests; consuming all of them makes every
  // required-good and shortage row too large. Preserve their order and sizes,
  // but cap the final measured row so the sum is exactly the order quantity.
  var remaining = expected;
  final capped = <Map<String, dynamic>>[];
  for (final instance in normalized) {
    if (remaining <= 0) break;
    final quantity = instance['qty'] as int;
    final accepted = quantity > remaining ? remaining : quantity;
    if (accepted <= 0) continue;
    capped.add(<String, dynamic>{...instance, 'qty': accepted});
    remaining -= accepted;
  }
  normalized
    ..clear()
    ..addAll(capped);
  final represented = expected - remaining;

  if (represented < expected) {
    final missing = expected - represented;
    // A single qty=1 row is the common old draft. Updating that same row
    // keeps the breakdown compact; for genuine measured variants, keep their
    // dimensions and add the still-unmeasured order remainder separately.
    if (normalized.length == 1 && represented == 1) {
      normalized.single['qty'] = expected;
    } else {
      normalized.add({
        'width': defaultWidth,
        'height': defaultHeight,
        'qty': missing,
      });
    }
  }
  return normalized;
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

String _canonicalInventoryItemType(String? value) {
  final normalized = (value ?? '').trim().toLowerCase().replaceAll(' ', '');
  if (const {
    'profile',
    'profiles',
    'section',
    'sections',
  }.contains(normalized)) {
    return 'Section';
  }
  if (const {'accessory', 'accessories'}.contains(normalized)) {
    return 'Accessory';
  }
  if (const {
    'shuttercomponent',
    'shuttercomponents',
    'lame',
    'glissiere',
    'axe',
    'caisson',
  }.contains(normalized)) {
    return 'ShutterComponent';
  }
  if (const {'joint', 'joints'}.contains(normalized)) return 'Joints';
  if (normalized == 'glass') return 'Glass';
  return value?.trim() ?? '';
}

String requiredGoodsInventoryKey({
  required String? itemType,
  required int itemId,
  int? colorId,
}) => '${_canonicalInventoryItemType(itemType)}_${itemId}_${colorId ?? 0}';

bool bomUsesOrderLevelCutting(BomItem item) {
  final unit = item.unit.trim().toLowerCase();
  final isStockBar = const {'قطاع', 'بارة', 'bar', 'section'}.contains(unit);
  return isStockBar &&
      (item.length ?? 0) > 0 &&
      (item.pieces?.any((piece) => piece > 0) ?? false);
}

String _extractRoleLabel(String orig) {
  final trimmed = orig.trim();
  if (trimmed.startsWith('Cadre doublé') ||
      trimmed.startsWith('Cadre double') ||
      trimmed.startsWith('كادر دوبلي') ||
      trimmed.startsWith('كادر دبل')) {
    return 'كادر دوبلي';
  }
  if (trimmed.contains('الإطار (Frame)') ||
      trimmed == 'الإطار' ||
      trimmed == 'Frame' ||
      trimmed == 'Cadre') {
    return 'الإطار';
  }
  if (trimmed.contains('إطار منزلق') ||
      trimmed.contains('Cadre Coulissant')) {
    return 'إطار منزلق';
  }
  if (trimmed.contains('تقسيم الزجاج') ||
      trimmed.contains('Mullion') ||
      trimmed.contains('Traverse') ||
      trimmed.contains('تقسيم')) {
    return 'التقسيم';
  }
  if (trimmed.contains('ضلفة') ||
      trimmed.contains('دلفة') ||
      trimmed.contains('Sash') ||
      trimmed.contains('Ouvrant')) {
    return 'الضلفة';
  }
  if (trimmed.contains('باركلوز') || trimmed.contains('Parclose')) {
    return 'الباركلوز';
  }
  return trimmed;
}

String _cleanProfileName(BomItem item) {
  final lines = item.name
      .split('\n')
      .where((line) => !line.contains('المطلوب الفعلي'))
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty)
      .toList();

  String candidate = '';
  if (lines.length >= 2 && lines[1].isNotEmpty) {
    candidate = lines[1];
  } else if (lines.isNotEmpty) {
    candidate = lines[0];
  } else {
    candidate = item.originalName.trim();
  }

  candidate = candidate
      .replaceAll(
        RegExp(
          r'^(Cadre doublé|Cadre double|كادر دوبلي|كادر دبل)\s*[-—–:]*\s*',
          caseSensitive: false,
        ),
        '',
      )
      .replaceAll(
        RegExp(
          r'^(تقسيم الزجاج \(Mullion\)|تقسيم الزجاج|Mullion|Traverse|عارضة|قائم|تقسيم)\s*[-—–:]*\s*',
          caseSensitive: false,
        ),
        '',
      )
      .replaceAll(
        RegExp(
          r'^(الإطار \(Frame\)|إطار منزلق \(Cadre Coulissant\)|الإطار|إطار|Frame|Cadre)\s*[-—–:]*\s*',
          caseSensitive: false,
        ),
        '',
      )
      .trim();

  if (candidate.isEmpty) {
    if (item.profileCode != null && item.profileCode!.trim().isNotEmpty) {
      candidate = item.profileCode!.trim();
    } else {
      candidate = item.originalName.trim();
    }
  }
  return candidate;
}

String _extractCodeFromName(String text) {
  final match = RegExp(
    r'^([A-Za-z0-9_\-\.\/]+)\s*[-—–:]\s*',
  ).firstMatch(text.trim());
  if (match != null) {
    final code = match.group(1)!.trim();
    if (code.length >= 2 && !code.toLowerCase().startsWith('kit')) {
      return code.toUpperCase();
    }
  }
  return '';
}

String _normalizeHardwareKey(String name) {
  final lower = name.toLowerCase();
  if (lower.contains('تركيب') || lower.contains('pose')) {
    return 'vis_pose';
  }
  if (lower.contains('باتمو') || lower.contains('meneau') || lower.contains('batmo')) {
    return 'vis_batmo';
  }
  if (lower.contains('إكسسوارات') || lower.contains('accessoire')) {
    return 'vis_accessoires';
  }
  if (lower.contains('حديد الدعم') || lower.contains('renfort')) {
    return 'vis_renfort';
  }
  return '';
}

String _normalizeColorKey(BomItem item) {
  final name = (item.colorName ?? '').trim().toLowerCase();
  if (name.isNotEmpty) {
    return 'COLOR:$name';
  }
  final role = (item.roleKey ?? item.selectorType ?? '').toLowerCase();
  if (role.contains('screw') ||
      role.contains('vis') ||
      item.originalName.contains('براغي') ||
      item.name.contains('براغي') ||
      item.originalName.toLowerCase().contains('vis') ||
      item.name.toLowerCase().contains('vis')) {
    return 'COLOR:DEFAULT';
  }
  if (item.colorId != null && item.colorId! > 0) {
    return 'COLOR_ID:${item.colorId}';
  }
  return 'COLOR:DEFAULT';
}

String _normalizeColorKeyForAggregate(AggregatedGoodItem item) {
  final name = (item.colorName ?? '').trim().toLowerCase();
  if (name.isNotEmpty) {
    return 'COLOR:$name';
  }
  final orig = item.originalName.toLowerCase();
  final itemName = item.name.toLowerCase();
  if (orig.contains('براغي') ||
      orig.contains('vis') ||
      itemName.contains('براغي') ||
      itemName.contains('vis')) {
    return 'COLOR:DEFAULT';
  }
  if (item.colorId != null && item.colorId! > 0) {
    return 'COLOR_ID:${item.colorId}';
  }
  return 'COLOR:DEFAULT';
}

String requiredGoodsDisplayName(BomItem item) {
  final normCategory = item.category.trim().toLowerCase();
  final usesOrderCutting = bomUsesOrderLevelCutting(item);
  if (normCategory == 'profile' ||
      normCategory == 'frame' ||
      normCategory == 'mullion' ||
      normCategory == 'sash' ||
      usesOrderCutting) {
    final clean = _cleanProfileName(item);
    if (clean.isNotEmpty) return clean;
  }
  return item.name
      .split('\n')
      .where((line) => !line.contains('المطلوب الفعلي'))
      .join('\n')
      .trim();
}

String requiredGoodsAggregationKey(BomItem item, String category) {
  final normCategory = category.trim().toLowerCase();
  final usesOrderCutting = bomUsesOrderLevelCutting(item);
  final isProfile = normCategory == 'profile' ||
      normCategory == 'frame' ||
      normCategory == 'mullion' ||
      normCategory == 'sash' ||
      usesOrderCutting;

  if (isProfile) {
    final cleanName = _cleanProfileName(item);
    final code = (item.profileCode != null && item.profileCode!.trim().isNotEmpty)
        ? item.profileCode!.trim().replaceAll(RegExp(r'[\s_]'), '').toUpperCase()
        : _extractCodeFromName(cleanName);
    final idKey = code.isNotEmpty
        ? 'CODE:$code'
        : (item.catalogItemId != null && item.catalogItemId! > 0)
        ? 'CAT:${item.catalogItemId}'
        : 'NAME:${cleanName.toLowerCase()}';
    final colorKey = _normalizeColorKey(item);
    final lengthKey = (item.length ?? 0) > 0 ? (item.length!).toStringAsFixed(2) : '6.00';
    return 'PROFILE___${idKey}___${colorKey}___${item.unit.trim().toLowerCase()}___$lengthKey';
  }

  // Non-profile items: Accessories, Joints, Glass, Shutters, etc.
  final hwKey = _normalizeHardwareKey(item.originalName).isNotEmpty
      ? _normalizeHardwareKey(item.originalName)
      : _normalizeHardwareKey(item.name);
  final itemIdentifier = (item.catalogItemId != null && item.catalogItemId! > 0)
      ? '${item.inventoryItemType ?? normCategory}:${item.catalogItemId}'
      : (item.profileCode != null && item.profileCode!.trim().isNotEmpty)
      ? 'CODE:${item.profileCode!.trim().toUpperCase()}'
      : hwKey.isNotEmpty
      ? 'HW:$hwKey'
      : 'NAME:${requiredGoodsDisplayName(item).toLowerCase()}';

  final colorKey = _normalizeColorKey(item);
  final lengthKey = (item.length ?? 0) > 0 ? (item.length!).toStringAsFixed(2) : '';
  final heightKey = (item.glassHeight ?? 0) > 0 ? (item.glassHeight!).toStringAsFixed(2) : '';

  return '${normCategory}___${itemIdentifier}___'
      '${colorKey}___${item.unit.trim().toLowerCase()}___'
      '${lengthKey}___${heightKey}';
}

/// A Kit is one configured bundle. Its contents can carry different colours,
/// but must still remain beneath that single Kit row in required goods.
String requiredGoodsKitAggregationKey(String category, String kitName, {int? seriesId}) =>
    'KIT___${category.trim().toLowerCase()}___${kitName.trim().toLowerCase()}';

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
  double? bladeWaste,
}) {
  final effectiveBladeWaste = bladeWaste ?? CuttingSettings.sawKerfMeters;
  final remainingPieces = pieces.where((piece) => piece > 0).toList()
    ..sort((a, b) => b.compareTo(a));
  final bins = remnants
      .where((piece) => piece.length > effectiveBladeWaste)
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
    final needed = cut + effectiveBladeWaste;
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
      bladeWaste: effectiveBladeWaste,
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
  double? bladeWaste,
}) {
  final effectiveBladeWaste = bladeWaste ?? CuttingSettings.sawKerfMeters;
  if (stockLength <= 0) {
    return OrderCuttingPlan(
      bars: const [],
      stockLength: stockLength,
      bladeWaste: effectiveBladeWaste,
      oversizedPieces: pieces.where((piece) => piece > 0).toList(),
    );
  }

  final stockMm = (stockLength * 1000).round();
  final kerfMm = (effectiveBladeWaste * 1000).round().clamp(0, stockMm);
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
      bladeWaste: effectiveBladeWaste,
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

  // Exact branch-and-bound is useful for small normal orders, while the node
  // and time caps keep large orders from delaying the required-goods page.
  // The best-fit plan remains valid if the exact proof reaches a cap.
  if (cutPieces.length <= 28 && bestAssignments.length > lowerBound) {
    const maxNodes = 25000;
    const maxElapsed = Duration(milliseconds: 45);
    final stopwatch = Stopwatch()..start();
    var visitedNodes = 0;
    var stopped = false;

    List<List<int>>? findPacking(int targetBars) {
      final remaining = List<int>.filled(targetBars, stockMm);
      final assignments = List.generate(targetBars, (_) => <int>[]);

      bool place(int index) {
        if (index == cutPieces.length) return true;
        visitedNodes++;
        if (visitedNodes > maxNodes ||
            (visitedNodes & 0x3ff == 0 && stopwatch.elapsed > maxElapsed)) {
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
    bladeWaste: effectiveBladeWaste,
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
  String name;
  String originalName;
  final String category;
  final String unit;
  String? imagePath;
  double unitPrice; // non-final to allow computing it later for kits
  double totalQuantity;
  double totalCost;
  String? profileCode;
  final String? colorName;
  double? stockLength;
  final double? glassHeight;
  int pieceCount;
  WindowModel? sourceModel;
  Uint8List? drawingSnapshot;
  int? catalogItemId;
  final String? inventoryItemType;
  int? colorId;
  bool isMissing;
  final List<double> cuttingPieces;
  OrderCuttingPlan? cuttingPlan;

  // 🟢 List of sub-items if this item is a grouped Kit
  final List<BomItem> kitSubItems;
  final String? kitGroupName;

  double? get length => stockLength;

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
    this.pieceCount = 0,
    this.sourceModel,
    this.drawingSnapshot,
    this.catalogItemId,
    this.inventoryItemType,
    this.colorId,
    this.isMissing = false,
    List<double> cuttingPieces = const [],
    this.cuttingPlan,
    this.kitSubItems = const [],
    this.kitGroupName,
  }) : cuttingPieces = List<double>.from(cuttingPieces);

  void mergeWith(
    BomItem bom,
    double purchaseQty,
    double bomCost,
    bool usesOrderCutting, {
    WindowModel? model,
  }) {
    totalCost += bomCost;
    totalQuantity += purchaseQty;
    if (bom.pieceCount != null && bom.pieceCount! > 0) {
      pieceCount += bom.pieceCount!;
    } else if (unit.trim().toLowerCase() == 'قطعة' ||
        unit.trim().toLowerCase() == 'piece') {
      pieceCount += purchaseQty.round();
    } else if (category == 'glass') {
      pieceCount += 1;
    }
    if (sourceModel == null && model != null) {
      sourceModel = model;
    } else if (model != null &&
        model.zones.any((z) =>
            z.glass.decorH > 0 ||
            z.glass.decorV > 0 ||
            z.glass.hasRosettes ||
            z.glass.decorBaguetteId != null ||
            z.glass.decorRosetteId != null)) {
      sourceModel = model;
    }
    if (usesOrderCutting && bom.pieces != null && bom.pieces!.isNotEmpty) {
      cuttingPieces.addAll(bom.pieces!);
    }
    if ((stockLength == null || stockLength! <= 0) &&
        (bom.length != null && bom.length! > 0)) {
      stockLength = bom.length;
    }
    if (catalogItemId == null && bom.catalogItemId != null) {
      catalogItemId = bom.catalogItemId;
    }
    if ((profileCode == null || profileCode!.trim().isEmpty) &&
        (bom.profileCode != null && bom.profileCode!.trim().isNotEmpty)) {
      profileCode = bom.profileCode;
    }
    if ((imagePath == null || imagePath!.trim().isEmpty) &&
        (bom.imagePath != null && bom.imagePath!.trim().isNotEmpty)) {
      imagePath = bom.imagePath;
    }
    if (colorId == null && bom.colorId != null) {
      colorId = bom.colorId;
    }
    if (unitPrice <= 0 && bom.unitPrice > 0) {
      unitPrice = bom.unitPrice;
    }
    if (isMissing && !bom.isMissing) {
      isMissing = false;
    }
    if (bom.catalogItemId != null && (catalogItemId == null || catalogItemId == bom.catalogItemId)) {
      if (bom.name.isNotEmpty && !bom.isMissing) {
        name = requiredGoodsDisplayName(bom);
      }
    }
    final role = _extractRoleLabel(bom.originalName);
    if (role.isNotEmpty && !originalName.contains(role)) {
      originalName = originalName.isEmpty ? role : '$originalName • $role';
    }
  }
}

class _ConvertGoodsToPurchaseDialog extends StatefulWidget {
  final List<Map<String, dynamic>> suppliers;
  final List<Map<String, dynamic>> locations;
  final String nextNumber;
  final List<AggregatedGoodItem> purchaseItems;
  final String Function(String key) t;

  const _ConvertGoodsToPurchaseDialog({
    required this.suppliers,
    required this.locations,
    required this.nextNumber,
    required this.purchaseItems,
    required this.t,
  });

  @override
  State<_ConvertGoodsToPurchaseDialog> createState() =>
      _ConvertGoodsToPurchaseDialogState();
}

class _ConvertGoodsToPurchaseDialogState
    extends State<_ConvertGoodsToPurchaseDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _numberController;
  int? _supplierId;
  int? _locationId;
  var _documentKind = _PurchaseDocumentKind.purchaseOrder;

  @override
  void initState() {
    super.initState();
    _numberController = TextEditingController(text: widget.nextNumber);
    _supplierId = widget.suppliers.first['id'] as int?;
    _locationId = widget.locations.first['id'] as int?;
  }

  @override
  void dispose() {
    _numberController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final glassItemsForDialog = widget.purchaseItems
        .where((item) => item.category == 'glass')
        .toList();
    final otherItemsForDialog = widget.purchaseItems
        .where((item) => item.category != 'glass')
        .toList();

    return AlertDialog(
      title: Text(widget.t('تحويل الكميات المطلوبة إلى شراء')),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              RadioListTile<_PurchaseDocumentKind>(
                value: _PurchaseDocumentKind.purchaseOrder,
                groupValue: _documentKind,
                onChanged: (value) {
                  if (value != null) {
                    setState(() => _documentKind = value);
                  }
                },
                title: Text(widget.t('طلب شراء (مسودة)')),
                subtitle: Text(
                  widget.t('يمكن مراجعته وتأكيده لاحقًا دون إدخال المخزون.'),
                ),
              ),
              RadioListTile<_PurchaseDocumentKind>(
                value: _PurchaseDocumentKind.purchaseInvoice,
                groupValue: _documentKind,
                onChanged: (value) {
                  if (value != null) {
                    setState(() => _documentKind = value);
                  }
                },
                title: Text(widget.t('فاتورة شراء')),
                subtitle: Text(
                  widget.t('تُنشأ بالعناصر المحسوبة وقابلة للتعديل.'),
                ),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _numberController,
                decoration: InputDecoration(
                  labelText: _documentKind == _PurchaseDocumentKind.purchaseOrder
                      ? widget.t('رقم طلب الشراء')
                      : widget.t('رقم فاتورة الشراء'),
                  border: const OutlineInputBorder(),
                ),
                validator: (value) => value == null || value.trim().isEmpty
                    ? widget.t('أدخل رقم الوثيقة')
                    : null,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                initialValue: _supplierId,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: widget.t('المورّد'),
                  border: const OutlineInputBorder(),
                ),
                items: widget.suppliers
                    .map(
                      (supplier) => DropdownMenuItem<int>(
                        value: supplier['id'] as int,
                        child: Text(supplier['name']?.toString() ?? ''),
                      ),
                    )
                    .toList(),
                onChanged: (value) => setState(() => _supplierId = value),
                validator: (value) =>
                    value == null ? widget.t('اختر المورّد') : null,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                initialValue: _locationId,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: widget.t('مكان التخزين'),
                  border: const OutlineInputBorder(),
                ),
                items: widget.locations
                    .map(
                      (location) => DropdownMenuItem<int>(
                        value: location['id'] as int,
                        child: Text(location['name']?.toString() ?? ''),
                      ),
                    )
                    .toList(),
                onChanged: (value) => setState(() => _locationId = value),
                validator: (value) =>
                    value == null ? widget.t('اختر مكان التخزين') : null,
              ),
              const SizedBox(height: 12),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  '${widget.purchaseItems.length} ${widget.t('صنف مرتبط سيُضاف إلى الوثيقة')}',
                  style: TextStyle(
                    color: Colors.grey.shade700,
                    fontSize: 12,
                  ),
                ),
              ),
              if (glassItemsForDialog.isNotEmpty &&
                  otherItemsForDialog.isNotEmpty) ...[
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.cyan.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Colors.cyan.withValues(alpha: 0.35),
                    ),
                  ),
                  child: Text(
                    '${widget.t('سيتم فصل الشراء تلقائيًا إلى وثيقتين:')} '
                    '${widget.t('الزجاج')} (${glassItemsForDialog.length})، '
                    '${widget.t('وباقي العناصر')} (${otherItemsForDialog.length}). '
                    '${widget.t('يمكن تعديل كل وثيقة بعد إنشائها.')}',
                    style: TextStyle(
                      color: Colors.cyan.shade900,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(widget.t('إلغاء')),
        ),
        ElevatedButton.icon(
          onPressed: () {
            if (!_formKey.currentState!.validate()) return;
            final supplier = widget.suppliers.firstWhere(
              (row) => row['id'] == _supplierId,
            );
            Navigator.pop(context, {
              'kind': _documentKind,
              'number': _numberController.text.trim(),
              'supplier_id': _supplierId,
              'supplier_name': supplier['name']?.toString() ?? '',
              'location_id': _locationId,
            });
          },
          icon: const Icon(Icons.shopping_cart_checkout),
          label: Text(widget.t('إنشاء')),
        ),
      ],
    );
  }
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
    this.issueAtManufacturingStart = false,
  });

  final bool issueAtManufacturingStart;

  @override
  State<OrderRequiredGoodsScreen> createState() =>
      _OrderRequiredGoodsScreenState();
}

class _OrderRequiredGoodsScreenState extends State<OrderRequiredGoodsScreen> {
  Future<void> _printRequiredGoods() async {
    final isFrench = _currentLang == AppLanguage.french;
    final detailed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isFrench ? 'Imprimer les besoins en matières' : 'طباعة الكمية المطلوبة'),
        content: Text(
          isFrench
              ? 'Comment souhaitez-vous afficher les Kits dans le rapport ?'
              : 'كيف تريد عرض الكيت في التقرير؟',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(isFrench ? 'Par nom de Kit' : 'باسم الكيت'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(isFrench ? 'Avec éléments détaillés' : 'بالعناصر المفصلة'),
          ),
        ],
      ),
    );
    if (detailed == null || !mounted) return;

    final fonts = await PdfFontCache.load();
    final isRtl = !isFrench;
    final textDir = isRtl ? pw.TextDirection.rtl : pw.TextDirection.ltr;

    final clientName = (widget.orderData['client_name'] ??
            widget.orderData['nom_client'] ??
            '')
        .toString()
        .trim();
    final orderDate = (widget.orderData['date'] ??
            widget.orderData['date_commande'] ??
            '')
        .toString()
        .trim();

    // Group items by category
    final profiles = _aggregatedItems.where((i) => i.category == 'profile').toList();
    final accessories = _aggregatedItems.where((i) => i.category == 'accessory').toList();
    final glassItems = _aggregatedItems.where((i) => i.category == 'glass').toList();
    final shutters = _aggregatedItems.where((i) => i.category == 'shutter').toList();
    final joints = _aggregatedItems.where((i) => i.category == 'joint').toList();
    final otherItems = _aggregatedItems
        .where((i) =>
            i.category != 'profile' &&
            i.category != 'accessory' &&
            i.category != 'glass' &&
            i.category != 'shutter' &&
            i.category != 'joint')
        .toList();

    // Capture glass drawings if available
    final glassImages = <String, Uint8List>{};
    for (final g in glassItems) {
      if (g.sourceModel != null) {
        final key = '${g.stockLength?.round()}_${g.glassHeight?.round()}';
        if (!glassImages.containsKey(key)) {
          try {
            final bytes = await captureWindowImage(
              g.sourceModel!,
              maxSide: 450,
              showDrawingDimensions: true,
            );
            glassImages[key] = bytes;
          } catch (_) {}
        }
      }
    }

    pw.Widget buildSectionHeader(String title, PdfColor color) {
      return pw.Container(
        margin: const pw.EdgeInsets.only(top: 14, bottom: 6),
        padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: pw.BoxDecoration(
          color: color,
          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
        ),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              title,
              style: pw.TextStyle(
                color: PdfColors.white,
                fontWeight: pw.FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ],
        ),
      );
    }

    final pdf = pw.Document();
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(24),
        textDirection: textDir,
        theme: pw.ThemeData.withFont(base: fonts.regular, bold: fonts.bold),
        build: (ctx) {
          final content = <pw.Widget>[];

          // Header
          content.add(
            pw.Container(
              padding: const pw.EdgeInsets.only(bottom: 10),
              decoration: const pw.BoxDecoration(
                border: pw.Border(
                  bottom: pw.BorderSide(color: PdfColors.grey400, width: 1.5),
                ),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Column(
                    crossAxisAlignment: isRtl
                        ? pw.CrossAxisAlignment.end
                        : pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        isFrench
                            ? 'Besoins en Matières - Commande N° ${widget.orderData['id']}'
                            : 'الكميات والمواد المطلوبة - الطلبية رقم ${widget.orderData['id']}',
                        style: pw.TextStyle(
                          fontSize: 16,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.indigo900,
                        ),
                      ),
                      pw.SizedBox(height: 4),
                      pw.Text(
                        isFrench
                            ? 'Client: ${clientName.isNotEmpty ? clientName : "-"}   •   Date: ${orderDate.isNotEmpty ? orderDate : "-"}'
                            : 'الزبون: ${clientName.isNotEmpty ? clientName : "-"}   •   التاريخ: ${orderDate.isNotEmpty ? orderDate : "-"}',
                        style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
                      ),
                    ],
                  ),
                  pw.Text(
                    '${_aggregatedItems.length} ${isFrench ? "articles" : "سلعة"}',
                    style: pw.TextStyle(
                      fontSize: 11,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.indigo700,
                    ),
                  ),
                ],
              ),
            ),
          );

          // 1. PROFILES SECTION
          if (profiles.isNotEmpty) {
            content.add(
              buildSectionHeader(
                isFrench ? '1. PROFILÉS ALUMINIUM' : '1. البروفيلات (قطاعات الألمنيوم)',
                PdfColors.blueGrey800,
              ),
            );
            final pRows = <List<String>>[];
            for (final p in profiles) {
              pRows.add([
                p.profileCode ?? '-',
                p.name,
                p.colorName ?? '-',
                _purchaseQuantityLabel(p),
                p.stockLength != null && p.stockLength! > 0
                    ? '${p.stockLength!.toStringAsFixed(2)} m'
                    : '-',
              ]);
            }
            content.add(
              pw.TableHelper.fromTextArray(
                headers: isFrench
                    ? ['Code', 'Désignation', 'Couleur', 'Quantité (Barres)', 'Longueur']
                    : ['الكود', 'اسم القطاع', 'اللون', 'كمية الشراء', 'طول القطاع'],
                data: pRows,
                headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9, color: PdfColors.white),
                headerDecoration: const pw.BoxDecoration(color: PdfColors.blueGrey700),
                cellStyle: const pw.TextStyle(fontSize: 8.5),
                cellPadding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
              ),
            );
          }

          // 2. ACCESSORIES SECTION
          if (accessories.isNotEmpty) {
            content.add(
              buildSectionHeader(
                isFrench ? '2. ACCESSOIRES & QUINCAILLERIE' : '2. الإكسسوارات والمستلزمات',
                PdfColors.teal800,
              ),
            );
            final aRows = <List<String>>[];
            for (final a in accessories) {
              aRows.add([
                a.profileCode ?? '-',
                a.name,
                a.colorName ?? '-',
                _roundQuantity(a.totalQuantity, a.unit),
                isFrench ? (a.unit == 'قطعة' ? 'U' : a.unit) : a.unit,
              ]);
              if (detailed && a.kitGroupName != null) {
                for (final sub in a.kitSubItems) {
                  aRows.add([
                    sub.profileCode ?? '',
                    '   • ${sub.name}',
                    sub.colorName ?? '-',
                    _roundQuantity(sub.purchaseQuantity, sub.unit),
                    isFrench ? (sub.unit == 'قطعة' ? 'U' : sub.unit) : sub.unit,
                  ]);
                }
              }
            }
            content.add(
              pw.TableHelper.fromTextArray(
                headers: isFrench
                    ? ['Réf / Code', 'Désignation', 'Couleur', 'Quantité', 'Unité']
                    : ['الكود / المرجع', 'اسم الملحق', 'اللون', 'الكمية', 'الوحدة'],
                data: aRows,
                headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9, color: PdfColors.white),
                headerDecoration: const pw.BoxDecoration(color: PdfColors.teal700),
                cellStyle: const pw.TextStyle(fontSize: 8.5),
                cellPadding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
              ),
            );
          }

          // 3. GLASS SECTION (Real cut dimensions, piece counts, decor & diagrams)
          if (glassItems.isNotEmpty) {
            content.add(
              buildSectionHeader(
                isFrench
                    ? '3. VITRAGE (DIMENSIONS RÉELLES DE COUPE & DÉCOR)'
                    : '3. الزجاج (مقاسات التقطيع الحقيقية والديكور الداخلي)',
                PdfColors.cyan900,
              ),
            );
            final gRows = <List<String>>[];
            for (final g in glassItems) {
              final dims = (g.stockLength != null && g.glassHeight != null && g.stockLength! > 0 && g.glassHeight! > 0)
                  ? '${g.stockLength!.round()} × ${g.glassHeight!.round()} mm'
                  : '-';
              final pieces = '${g.pieceCount > 0 ? g.pieceCount : 1}';
              final sqm = '${_roundQuantity(g.totalQuantity, 'm²')} m²';

              // Extract decor info
              String decorText = '-';
              if (g.sourceModel != null) {
                final decorZones = g.sourceModel!.zones.where((z) =>
                    z.glass.decorH > 0 ||
                    z.glass.decorV > 0 ||
                    z.glass.hasRosettes ||
                    z.glass.decorBaguetteId != null ||
                    z.glass.decorRosetteId != null).toList();
                if (decorZones.isNotEmpty) {
                  final dz = decorZones.first;
                  final h = dz.glass.decorH;
                  final v = dz.glass.decorV;
                  final hasRos = dz.glass.hasRosettes || dz.glass.decorRosetteId != null;
                  final parts = <String>[];
                  if (h > 0 || v > 0) {
                    parts.add(isFrench ? 'Baguette $h H × $v V (${dz.glass.decorThickness}mm)' : 'باجيت: $h أفقي × $v عمودي (${dz.glass.decorThickness}مم)');
                  }
                  if (hasRos) {
                    parts.add(isFrench ? '+ Rosettes' : '+ وردات ديكور');
                  }
                  decorText = parts.join(' • ');
                }
              }

              gRows.add([
                g.name,
                dims,
                pieces,
                sqm,
                decorText,
              ]);
            }
            content.add(
              pw.TableHelper.fromTextArray(
                headers: isFrench
                    ? ['Spécification / Type', 'Dimensions de coupe (L × H mm)', 'Nb Pièces', 'Surface (m²)', 'Décor (Baguettes / Rosettes)']
                    : ['مواصفات ونوع الزجاج', 'القياس الحقيقي للقص (عرض × ارتفاع مم)', 'عدد الألواح', 'المساحة (م²)', 'ملاحظات الديكور والتقسيمات'],
                data: gRows,
                headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9, color: PdfColors.white),
                headerDecoration: const pw.BoxDecoration(color: PdfColors.cyan800),
                cellStyle: const pw.TextStyle(fontSize: 8.5),
                cellPadding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
              ),
            );

            // Add glass drawing diagrams for the supplier if available
            if (glassImages.isNotEmpty) {
              content.add(pw.SizedBox(height: 8));
              content.add(
                pw.Text(
                  isFrench
                      ? 'Schémas des vitrages et disposition des décors pour le vitrier :'
                      : 'رسومات النوافذ ومواقع تقسيمات الديكور والوردات لمورد الزجاج:',
                  style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: PdfColors.cyan900),
                ),
              );
              content.add(pw.SizedBox(height: 4));
              final drawingWidgets = <pw.Widget>[];
              for (final entry in glassImages.entries) {
                drawingWidgets.add(
                  pw.Container(
                    width: 140,
                    height: 140,
                    margin: const pw.EdgeInsets.only(right: 8, bottom: 8),
                    padding: const pw.EdgeInsets.all(3),
                    decoration: pw.BoxDecoration(
                      border: pw.Border.all(color: PdfColors.cyan400, width: 1),
                      borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
                    ),
                    child: pw.Column(
                      children: [
                        pw.Expanded(
                          child: pw.Image(pw.MemoryImage(entry.value), fit: pw.BoxFit.contain),
                        ),
                        pw.SizedBox(height: 2),
                        pw.Text(
                          '${entry.key.replaceAll('_', ' × ')} mm',
                          style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                );
              }
              content.add(pw.Wrap(children: drawingWidgets));
            }
          }

          // 4. SHUTTERS SECTION
          if (shutters.isNotEmpty) {
            content.add(
              buildSectionHeader(
                isFrench ? '4. COMPOSANTS DE VOLET ROULANT' : '4. مكونات الستار (Volet Roulant)',
                PdfColors.orange900,
              ),
            );
            final sRows = <List<String>>[];
            for (final s in shutters) {
              sRows.add([
                s.profileCode ?? '-',
                s.name,
                _roundQuantity(s.totalQuantity, s.unit),
                isFrench ? (s.unit == 'قطعة' ? 'U' : s.unit) : s.unit,
              ]);
            }
            content.add(
              pw.TableHelper.fromTextArray(
                headers: isFrench
                    ? ['Code', 'Désignation', 'Quantité', 'Unité']
                    : ['الكود', 'العنصر', 'الكمية', 'الوحدة'],
                data: sRows,
                headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9, color: PdfColors.white),
                headerDecoration: const pw.BoxDecoration(color: PdfColors.orange800),
                cellStyle: const pw.TextStyle(fontSize: 8.5),
                cellPadding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
              ),
            );
          }

          // 5. JOINTS SECTION
          if (joints.isNotEmpty) {
            content.add(
              buildSectionHeader(
                isFrench ? '5. JOINTS D\'ÉTANCHÉITÉ' : '5. الجوانات ومواد الإحكام',
                PdfColors.brown700,
              ),
            );
            final jRows = <List<String>>[];
            for (final j in joints) {
              jRows.add([
                j.name,
                '${_roundQuantity(j.totalQuantity, j.unit)} ${isFrench ? (j.unit == "متر" ? "m" : j.unit) : j.unit}',
              ]);
            }
            content.add(
              pw.TableHelper.fromTextArray(
                headers: isFrench ? ['Désignation', 'Longueur'] : ['اسم الجوان', 'الكمية'],
                data: jRows,
                headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9, color: PdfColors.white),
                headerDecoration: const pw.BoxDecoration(color: PdfColors.brown600),
                cellStyle: const pw.TextStyle(fontSize: 8.5),
                cellPadding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
              ),
            );
          }

          // 6. OTHER ITEMS SECTION
          if (otherItems.isNotEmpty) {
            content.add(
              buildSectionHeader(
                isFrench ? '6. AUTRES ARTICLES / PANNEAUX' : '6. أصناف أخرى / ألواح الحشو',
                PdfColors.grey800,
              ),
            );
            final oRows = <List<String>>[];
            for (final o in otherItems) {
              oRows.add([
                o.name,
                _roundQuantity(o.totalQuantity, o.unit),
                o.unit,
              ]);
            }
            content.add(
              pw.TableHelper.fromTextArray(
                headers: isFrench ? ['Désignation', 'Quantité', 'Unité'] : ['العنصر', 'الكمية', 'الوحدة'],
                data: oRows,
                headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9, color: PdfColors.white),
                headerDecoration: const pw.BoxDecoration(color: PdfColors.grey700),
                cellStyle: const pw.TextStyle(fontSize: 8.5),
                cellPadding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
              ),
            );
          }

          return content;
        },
      ),
    );

    await Printing.layoutPdf(
      onLayout: (_) => pdf.save(),
      name: 'Required_goods_${widget.orderData['id']}.pdf',
    );
  }
  bool _isLoading = true;
  String? _errorMessage;
  List<AggregatedGoodItem> _aggregatedItems = [];
  int _productCount = 0;
  List<ProductBreakdown> _productBreakdowns = [];
  List<String> _processingWarnings = [];
  final Set<String> _expandedKits = {};
  final Set<String> _expandedCuttingPlans = {};
  bool _isCreatingPurchase = false;
  bool _manufacturingIssueRequested = false;
  late AppLanguage _currentLang;
  Future<int>? _shutterGreyColorIdFuture;
  String _selectedCategory = 'all';
  Map<String, double> _mainWarehouseStock = const {};
  String _mainWarehouseName = 'المستودع الرئيسي';
  bool _isStockReserved = false;

  Future<void> _refreshReservationStatus() async {
    final orderId = _safeInt(widget.orderData['id']);
    if (orderId == null) return;
    try {
      final reserved = await widget.db.isOrderStockReserved(orderId);
      if (mounted) {
        setState(() {
          _isStockReserved = reserved;
        });
      }
    } catch (_) {}
  }

  List<AggregatedGoodItem> get _visibleItems => _selectedCategory == 'all'
      ? _aggregatedItems
      : _aggregatedItems
            .where((item) => item.category == _selectedCategory)
            .toList();

  Future<(Map<String, double>, String)> _loadMainWarehouseStock() async {
    final locations = await widget.db.readLocations();
    if (locations.isEmpty)
      return (const <String, double>{}, 'المستودع الرئيسي');
    final mainLocations = locations.where((row) {
      final name = (row['name']?.toString() ?? '').trim();
      final type = (row['type']?.toString() ?? '').trim();
      return name == 'المستودع الرئيسي' || type == 'مستودع رئيسي';
    }).toList();
    final sourceLocations = mainLocations.isNotEmpty
        ? mainLocations
        : <Map<String, dynamic>>[locations.first];
    final locationIds = sourceLocations
        .map((location) => _safeInt(location['id']))
        .whereType<int>()
        .toSet()
        .toList();
    if (locationIds.isEmpty) {
      return (const <String, double>{}, 'المستودع الرئيسي');
    }
    final database = await widget.db.db;
    if (database == null) {
      return (const <String, double>{}, 'المستودع الرئيسي');
    }
    final rows = await database.query(
      'CurrentStock',
      where:
          'location_id IN (${List.filled(locationIds.length, '?').join(',')})',
      whereArgs: locationIds,
    );
    final quantities = <String, double>{};
    for (final row in rows) {
      final itemId = _safeInt(row['item_id']);
      if (itemId == null) continue;
      final key = requiredGoodsInventoryKey(
        itemType: row['item_type']?.toString(),
        itemId: itemId,
        colorId: _safeInt(row['color_id']),
      );
      quantities[key] = (quantities[key] ?? 0) + _safeDouble(row['quantity']);
    }
    return (
      quantities,
      sourceLocations.first['name']?.toString() ?? 'المستودع الرئيسي',
    );
  }

  double? _stockQuantityFor({
    required int? itemId,
    required String? itemType,
    int? colorId,
  }) {
    if (itemId == null || (itemType ?? '').trim().isEmpty) return null;
    return _mainWarehouseStock[requiredGoodsInventoryKey(
          itemType: itemType,
          itemId: itemId,
          colorId: colorId,
        )] ??
        _mainWarehouseStock[requiredGoodsInventoryKey(
          itemType: itemType,
          itemId: itemId,
          colorId: null,
        )] ??
        0;
  }

  String _stockLabel(double? quantity, String unit) =>
      quantity == null ? '—' : '${_roundQuantity(quantity, unit)} ${_t(unit)}';

  @override
  void initState() {
    super.initState();
    _currentLang = Provider.of<AppSettingsProvider>(
      context,
      listen: false,
    ).language;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadAndAggregate();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _currentLang = Provider.of<AppSettingsProvider>(context).language;
  }

  String _t(String key) {
    var result = Localization.translate(key, _currentLang);
    if (result != key || _currentLang == AppLanguage.arabic) return result;
    // Generated material descriptions combine catalogue names and UI labels.
    for (final label in ['الوجه الخارجي', 'الوجه الداخلي', 'شفاف/عادي', 'شفاف', 'المنتج رقم']) {
      result = result.replaceAll(label, Localization.translate(label, _currentLang));
    }
    return result;
  }

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

  Future<
    ({
      Map<String, List<Map<String, dynamic>>> data,
      Map<String, bool> perLeaf,
      Map<String, Map<String, dynamic>> metadata,
      Map<String, double> prices,
    })
  >
  _loadKitBundleCache() async {
    final kitBundleData = <String, List<Map<String, dynamic>>>{};
    final kitPerLeafMap = <String, bool>{};
    final kitBundleMetadata = <String, Map<String, dynamic>>{};
    final kitBundlePrices = <String, double>{};

    try {
      final kits = await widget.db.readKitBundles();
      await Future.wait(
        kits.map((kit) async {
          final kitName = kit['name']?.toString() ?? '';
          if (kitName.isEmpty) return;
          final kitId = _safeInt(kit['id']);
          if (kitId == null) return;
          final details = await widget.db.readKitBundleItemsWithDetails(
            kitId,
            topLevelOnly: true,
          );
          kitBundleData[kitName] = details
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
          kitPerLeafMap[kitName] = (kit['per_leaf'] ?? 0) == 1;
          kitBundleMetadata[kitName] = Map<String, dynamic>.from(kit);
          final rawPrice = kit['price'];
          if (rawPrice is num && rawPrice > 0) {
            kitBundlePrices[kitName] = rawPrice.toDouble();
          }
        }),
      );
    } catch (e) {
      debugPrint('Required goods kit cache load warning: $e');
    }

    return (
      data: kitBundleData,
      perLeaf: kitPerLeafMap,
      metadata: kitBundleMetadata,
      prices: kitBundlePrices,
    );
  }

  Future<int> _shutterGreyColorId() {
    return _shutterGreyColorIdFuture ??= widget.db
        .ensureShutterComponentsUseGreyPrice();
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

  String _catalogCacheToken(Map<String, dynamic>? value) {
    if (value == null) return '';
    final id = value['id']?.toString().trim() ?? '';
    if (id.isNotEmpty) return 'id:$id';
    return 'name:${(value['name'] ?? value['color_name'] ?? '').toString().trim().toLowerCase()}';
  }

  String _glassSpecCacheToken(GlassSpecification spec) {
    return [
      spec.structure.name,
      spec.finishOuter.name,
      spec.finishInner.name,
      spec.colorOuter.name,
      spec.colorInner.name,
      spec.processingOuter.name,
      spec.processingInner.name,
      spec.temperedOuter ? 'to' : '',
      spec.temperedInner ? 'ti' : '',
      spec.colorP.name,
      spec.hasGas ? 'gas' : '',
      spec.intercallThickness,
      spec.thicknessOuter ?? '',
      spec.thicknessInner ?? '',
      spec.laminatedColorOuter,
      spec.laminatedColorInner,
      spec.jointTwoSides ? 'joint2' : 'joint1',
    ].join(':');
  }

  String _catalogGlassSignature(WindowModel model) {
    final parts = <String>[];
    for (final zone in model.zones) {
      parts.add('${zone.content.name}:${_glassSpecCacheToken(zone.glass)}');
      final cellKeys = zone.cellGlassSpec.keys.toList()..sort();
      for (final key in cellKeys) {
        parts.add('$key:${_glassSpecCacheToken(zone.cellGlassSpec[key]!)}');
      }
    }
    return parts.join('|');
  }

  String _catalogCacheKey(WindowModel model) {
    return [
      model.systemMode ?? '',
      model.loadedSeriesId?.toString() ?? '',
      model.loadedSeriesName ?? '',
      model.loadedSlidingSeriesId?.toString() ?? '',
      model.loadedSlidingSeriesName ?? '',
      _catalogCacheToken(model.selectedDbColor),
      _catalogCacheToken(model.selectedAccessoryColor),
      _catalogGlassSignature(model),
    ].join('|');
  }

  Future<void> _applyWindowModelWithCatalogCache(
    WindowModel model,
    Map<String, dynamic> modelMap,
    Map<String, WindowModel> catalogCache,
  ) async {
    applyWindowModelFromMap(model, modelMap);
    final savedOverrides = Map<String, dynamic>.from(model.componentOverrides);
    final savedFrameOverride = model.frameOverride != null
        ? Map<String, dynamic>.from(model.frameOverride!)
        : null;
    final savedSlidingFrameOverride = model.slidingFrameOverride != null
        ? Map<String, dynamic>.from(model.slidingFrameOverride!)
        : null;
    final savedSashOverride = model.sashOverride != null
        ? Map<String, dynamic>.from(model.sashOverride!)
        : null;
    final savedSlidingSashOverride = model.slidingSashOverride != null
        ? Map<String, dynamic>.from(model.slidingSashOverride!)
        : null;

    final cacheKey = _catalogCacheKey(model);
    final cached = catalogCache[cacheKey];
    if (cached != null) {
      model.copyCatalogRuntimeFrom(cached);
    } else {
      await model.loadCatalogData(model.systemMode ?? '');
      final snapshot = WindowModel(db: widget.db);
      snapshot.copyCatalogRuntimeFrom(model, preserveCurrentSelections: false);
      catalogCache[cacheKey] = snapshot;
    }

    if (savedOverrides.isNotEmpty) {
      model.componentOverrides.addAll(savedOverrides);
    }
    if (savedFrameOverride != null) {
      model.frameOverride = savedFrameOverride;
    }
    if (savedSlidingFrameOverride != null) {
      model.slidingFrameOverride = savedSlidingFrameOverride;
    }
    if (savedSashOverride != null) {
      model.sashOverride = savedSashOverride;
    }
    if (savedSlidingSashOverride != null) {
      model.slidingSashOverride = savedSlidingSashOverride;
    }
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
    Map<String, double> kitBundlePrices,
  ) async {
    // Products created outside the window drawing (mosquito screens, tempered
    // glass work and manual products) intentionally have no zones. Preserve
    // them as standalone required goods instead of silently returning no rows.
    if (model.isMoustiquaire || model.isGlassWork || model.isCustomProduct) {
      return _standaloneProductBom(model);
    }

    // Use the same two-pass rule resolution as the quantity/cost table.
    // Do not infer extra products from names or legacy catalogue flags here.
    await model.updateShutterDefaultsIfNeeded();
    final activeVariants = _buildActiveVariants(model);
    final engine = BomEngineV2(database: widget.db);
    List<BomItem> generate() => ComponentCalculator.generateBom(
      model,
      activeVariants,
      kitBundleData: kitBundleData,
      kitPerLeafMap: kitPerLeafMap,
      kitBundleMetadata: kitBundleMetadata,
      kitBundlePrices: kitBundlePrices,
    );
    await engine.stabilizeSelections(window: model, items: generate());
    await engine.stabilizeSelections(window: model, items: generate());
    final raw = generate();
    final strict = await engine.filterItemsByAvailableCandidates(
      window: model,
      items: raw,
    );
    if (strict.isNotEmpty) {
      return strict;
    }
    return raw
        .where((i) =>
            i.isActive &&
            (i.requiredQuantity > 0 ||
                i.quantity > 0 ||
                (i.pieces != null && i.pieces!.isNotEmpty)))
        .toList();
  }

  Future<void> _loadAndAggregate() async {
    try {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
        _processingWarnings = [];
        // Never keep showing the previous calculation while the order rows
        // are being reread. The database rows are the source of truth after a
        // series, colour or glass change.
        _aggregatedItems = [];
        _productBreakdowns = [];
        _productCount = 0;
      });

      final orderId = _safeInt(widget.orderData['id']);
      if (orderId == null) {
        throw StateError('رقم الطلبية غير صالح');
      }
      final loaded = await Future.wait<dynamic>([
        widget.db.readCommandeDetails(orderId),
        _loadKitBundleCache(),
        widget.db.readSawKerfMm(),
      ]);
      final rawItems = loaded[0] as List<Map<String, dynamic>>;
      final kitCache =
          loaded[1]
              as ({
                Map<String, List<Map<String, dynamic>>> data,
                Map<String, bool> perLeaf,
                Map<String, Map<String, dynamic>> metadata,
                Map<String, double> prices,
              });
      final sawKerfMm = loaded[2] as double?;
      if (sawKerfMm != null) CuttingSettings.setSawKerfMm(sawKerfMm);
      final catalogCache = <String, WindowModel>{};

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
            ? '${_t('المنتج رقم')} $itemNumber'
            : fallbackName;
        if (jsonRaw == null || jsonRaw.toString().trim().isEmpty) {
          warnings.add('$productLabel: ${_t('بيانات الرسم غير محفوظة.')}');
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
            warnings.add('$productLabel: ${_t('بيانات الرسم فارغة.')}');
            continue;
          }

          final model = WindowModel(db: widget.db);
          await _applyWindowModelWithCatalogCache(
            model,
            modelMap,
            catalogCache,
          );

          // Only the explicit replacement flag cancels a product. Price zero
          // can mean a missing price or a free item and must not erase its BOM.
          if (isExplicitlyReplacedProduct(
            model.isReplaced,
            modelMap['isReplaced'],
          )) {
            skippedReplacedCount++;
            continue;
          }

          // The persisted order-line quantity takes precedence over a legacy
          // single-instance draft (which commonly stores qty=1).
          final orderedQuantity = _safePositiveInt(
            item['quantity'],
            fallback: model.quantity > 0 ? model.quantity : 1,
          );
          final instances = normalizeRequiredGoodsInstances(
            saved: parseRequiredGoodsInstances(item['instances_json']),
            orderedQuantity: orderedQuantity,
            defaultWidth: model.width,
            defaultHeight: model.height,
          );

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
                  '$productName (${_t('القياس')} $instIdx): ${_t('الطول أو العرض غير صالح.')}',
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
                kitCache.data,
                kitCache.perLeaf,
                kitCache.metadata,
                kitCache.prices,
              );
              bomItems.addAll(instBom);

              // Create a dedicated instance model for drawing and individual listing
              final instanceModel = WindowModel(db: widget.db);
              applyWindowModelFromMap(instanceModel, modelMap);
              instanceModel.copyCatalogRuntimeFrom(model);
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
            model.quantity = orderedQuantity;

            final instBom = await _resolveBomForModel(
              model,
              kitCache.data,
              kitCache.perLeaf,
              kitCache.metadata,
              kitCache.prices,
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
              .where(
                (bom) =>
                    bom.isActive &&
                    // A component can have an exact consumption before its
                    // purchase quantity is rounded or transformed into cuts.
                    // Do not silently drop it from the required-goods source
                    // merely because one of those derived values is zero.
                    (bom.requiredQuantity > 0 ||
                        bom.purchaseQuantity > 0 ||
                        (bom.pieces?.any((piece) => piece > 0) ?? false)),
              )
              .toList();
          if (activeBomItems.isEmpty) {
            if (model.zones.isEmpty &&
                !model.isCustomProduct &&
                !model.isMoustiquaire &&
                !model.isGlassWork) {
              warnings.add(
                '$productName: ${_t('الرسم المحفوظ لا يحتوي على مناطق نافذة قابلة للحساب.')}',
              );
            } else {
              warnings.add('$productName: ${_t('لم ينتج عنه أي مقدار مطلوب.')}');
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
                seriesId: bom.sourceSeriesId,
              );
              final isKitHeader = isRequiredGoodsKitHeader(bom, kitName);
              final double kitQtyToAdd = isKitHeader ? purchaseQty : 0.0;
              // If the kit has standalone pricing (no separate sub-items),
              // preserve the header's cost so it does not collapse to 0.
              final double kitCostToAdd = isKitHeader ? (bomCost > 0 ? bomCost : 0.0) : bomCost;

              if (aggregationMap.containsKey(kitKey)) {
                final agg = aggregationMap[kitKey]!;
                agg.totalQuantity += kitQtyToAdd;
                agg.totalCost += kitCostToAdd;

                if (!isKitHeader) {
                  final existingSubIndex = agg.kitSubItems.indexWhere(
                    (sub) =>
                        sub.originalName == bom.originalName &&
                        requiredGoodsDisplayName(sub) ==
                            requiredGoodsDisplayName(bom) &&
                        sub.unit == bom.unit &&
                        sub.colorId == bom.colorId &&
                        sub.catalogItemId == bom.catalogItemId &&
                        sub.profileCode == bom.profileCode &&
                        sub.imagePath == bom.imagePath,
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
                      overrideKey: existing.overrideKey ?? bom.overrideKey,
                      selectorCategory:
                          existing.selectorCategory ?? bom.selectorCategory,
                      selectorType: existing.selectorType ?? bom.selectorType,
                      roleKey: existing.roleKey ?? bom.roleKey,
                      sourceSeriesId:
                          existing.sourceSeriesId ?? bom.sourceSeriesId,
                      materialType: existing.materialType ?? bom.materialType,
                      targetThicknessMm:
                          existing.targetThicknessMm ?? bom.targetThicknessMm,
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

              String? matchingKey;
              if (aggregationMap.containsKey(aggregationKey)) {
                matchingKey = aggregationKey;
              } else {
                for (final entry in aggregationMap.entries) {
                  final existing = entry.value;
                  if (existing.kitGroupName != null) continue;
                  if (existing.category != category) continue;

                  final isProfile = category == 'profile' ||
                      category == 'frame' ||
                      category == 'mullion' ||
                      category == 'sash' ||
                      usesOrderCutting;
                  if (isProfile) {
                    final code = (bom.profileCode != null && bom.profileCode!.trim().isNotEmpty)
                        ? bom.profileCode!.trim().replaceAll(RegExp(r'[\s_]'), '').toUpperCase()
                        : _extractCodeFromName(_cleanProfileName(bom));
                    final existingCode = (existing.profileCode != null && existing.profileCode!.trim().isNotEmpty)
                        ? existing.profileCode!.trim().replaceAll(RegExp(r'[\s_]'), '').toUpperCase()
                        : _extractCodeFromName(existing.name);
                    final colorMatch = _normalizeColorKey(bom) == _normalizeColorKeyForAggregate(existing);
                    if (code.isNotEmpty && code == existingCode && colorMatch) {
                      matchingKey = entry.key;
                      break;
                    }
                  } else {
                    final hwBom = _normalizeHardwareKey(bom.originalName).isNotEmpty
                        ? _normalizeHardwareKey(bom.originalName)
                        : _normalizeHardwareKey(bom.name);
                    final hwEx = _normalizeHardwareKey(existing.originalName).isNotEmpty
                        ? _normalizeHardwareKey(existing.originalName)
                        : _normalizeHardwareKey(existing.name);
                    final colorMatch = _normalizeColorKey(bom) == _normalizeColorKeyForAggregate(existing);
                    if (colorMatch && hwBom.isNotEmpty && hwBom == hwEx) {
                      matchingKey = entry.key;
                      break;
                    }
                  }
                }
              }

              if (matchingKey != null) {
                final aggregate = aggregationMap[matchingKey]!;
                aggregate.mergeWith(
                  bom,
                  purchaseQty,
                  bomCost,
                  usesOrderCutting,
                  model: model,
                );
              } else {
                final isProfile = category == 'profile' ||
                    category == 'frame' ||
                    category == 'mullion' ||
                    category == 'sash' ||
                    usesOrderCutting;
                final cleanName = isProfile
                    ? _cleanProfileName(bom)
                    : (usesOrderCutting ? requiredGoodsDisplayName(bom) : bom.name);
                final displayName = cleanName.isNotEmpty
                    ? cleanName
                    : requiredGoodsDisplayName(bom);

                aggregationMap[aggregationKey] = AggregatedGoodItem(
                  name: displayName,
                  originalName: _extractRoleLabel(bom.originalName),
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
                  pieceCount: bom.pieceCount ??
                      (bom.unit.trim().toLowerCase() == 'قطعة'
                          ? purchaseQty.round()
                          : (category == 'glass' ? 1 : 0)),
                  sourceModel: model,
                  catalogItemId: bom.catalogItemId,
                  inventoryItemType: bom.inventoryItemType,
                  colorId: bom.colorId,
                  isMissing: bom.isMissing,
                  cuttingPieces: usesOrderCutting && bom.pieces != null
                      ? List<double>.from(bom.pieces!)
                      : const [],
                  kitSubItems: const [],
                  kitGroupName: null,
                );
              }
            }
          }

          successCount++;
        } catch (e, stackTrace) {
          warnings.add('$productLabel: ${_t('تعذر حسابه')} (${e.toString()}).');
          debugPrint('Error processing product "$productLabel": $e');
          debugPrintStack(stackTrace: stackTrace);
        }
      }

      if (skippedReplacedCount > 0) {
        warnings.add(
          _t('تم استبعاد {count} منتج مشطوب أو مستبدل من الطلبية.').replaceAll('{count}', '$skippedReplacedCount'),
        );
      }

      // Scientific order-level cutting: after every window has contributed
      // its raw cuts, optimize each identical catalogue item/colour/stock
      // length once. This reuses leftovers between products in the order.
      for (final item in aggregationMap.values) {
        if (item.cuttingPieces.isEmpty) continue;
        final stockLength = item.stockLength ?? 0;
        if (stockLength <= 0) continue;
        await Future<void>.delayed(Duration.zero);
        final plan = optimizeRequiredGoodsCutting(
          pieces: item.cuttingPieces,
          stockLength: stockLength,
        );
        item.cuttingPlan = plan;
        item.totalQuantity = plan.barCount.toDouble();
        item.totalCost = item.totalQuantity * item.unitPrice;
        if (plan.oversizedPieces.isNotEmpty) {
          warnings.add(
            '${_t(item.originalName)}: ${_t('توجد {count} قطعة قص أطول من القطاع {length} مم وتحتاج طول مخزون أكبر.').replaceAll('{count}', '${plan.oversizedPieces.length}').replaceAll('{length}', '${(stockLength * 1000).round()}')}',
          );
        }
      }

      // حساب سعر الوحدة الفعلي لكل طقم (Kit) كمجموع أسعار مكوناته
      for (final item in aggregationMap.values) {
        if (item.kitGroupName != null && item.totalQuantity > 0) {
          if (item.kitSubItems.isNotEmpty) {
            final subCost = item.kitSubItems.fold<double>(
              0.0,
              (sum, sub) => sum + (sub.quantity * sub.unitPrice),
            );
            if (subCost > 0) {
              item.totalCost = subCost;
              item.unitPrice = item.totalCost / item.totalQuantity;
            }
          } else if (item.unitPrice > 0 && item.totalCost == 0) {
            item.totalCost = item.totalQuantity * item.unitPrice;
          } else if (item.totalCost > 0 && item.unitPrice == 0) {
            item.unitPrice = item.totalCost / item.totalQuantity;
          }
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

      final stockSnapshot = await _loadMainWarehouseStock();
      final isReserved = await widget.db.isOrderStockReserved(orderId);
      setState(() {
        _aggregatedItems = sorted;
        _mainWarehouseStock = stockSnapshot.$1;
        _mainWarehouseName = stockSnapshot.$2;
        _productCount = successCount;
        _productBreakdowns = breakdownsTemp;
        _processingWarnings = warnings;
        _isStockReserved = isReserved;
        _isLoading = false;
      });
      if (widget.issueAtManufacturingStart &&
          !_manufacturingIssueRequested &&
          mounted) {
        _manufacturingIssueRequested = true;
        if (await widget.db.hasOrderInventoryIssue(orderId)) {
          if (mounted) Navigator.pop(context, true);
          return;
        }
        await _showShortageReport(autoApply: true);
      }
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
      'Verrou Central':
          model.canUseOpeningOnlyOptions && model.useVerrouCentral,
      'System OB': model.effectiveUseSystemOB,
      'Demi System OB': model.effectiveUseDemiOB,
      'كيت (Kit)': false,
      'طانديم (Tandem)': isTunnel,
      'الامبو (Embout)': isMotor,
      'سيبور رولمو (Support Roulement)': isMotor,
      'سيبور موتور (Support Moteur)': isMotor || isTunnel,
      'أغطية الشفرات (Bouchons Lames)': model.componentOverrides.containsKey(
        'أغطية الشفرات (Bouchons Lames)',
      ),
      'كيت صندوق النفق (Kit Caisson Tunnel)': isTunnel,
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
      final key = item.category == 'glass'
          ? '$itemType:$itemId:${item.length ?? ''}:${item.glassHeight ?? ''}:'
                '${item.unitPrice}:${item.name}'
          : '$itemType:$itemId:${item.colorId ?? ''}';
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

  String _purchaseItemCode(AggregatedGoodItem item) {
    final code = item.profileCode?.trim() ?? '';
    if (code.isNotEmpty) return code;
    if (item.category == 'glass' &&
        (item.length ?? 0) > 0 &&
        (item.glassHeight ?? 0) > 0) {
      return 'GL-${item.length!.round()}x${item.glassHeight!.round()}';
    }
    return item.name.replaceAll('\n', ' ').trim();
  }

  String _purchaseItemName(AggregatedGoodItem item) {
    final name = item.name.replaceAll('\n', ' • ').trim();
    if (item.category != 'glass') return name;
    final area = _roundQuantity(item.totalQuantity, 'm²');
    return '$name • Total: $area m²';
  }

  Future<int> _createAchatDocumentFromItems({
    required String number,
    required Map<String, dynamic> request,
    required List<AggregatedGoodItem> items,
  }) async {
    final achatId = await widget.db.insertAchat(
      number,
      request['supplier_name'] as String,
      0,
      supplierId: request['supplier_id'] as int,
      locationId: request['location_id'] as int,
    );

    for (final item in items) {
      await widget.db.insertAchatItem(
        achatId: achatId,
        itemCode: _purchaseItemCode(item),
        itemName: _purchaseItemName(item),
        itemType: item.inventoryItemType!,
        itemId: item.catalogItemId!,
        colorId: item.colorId,
        quantity: item.totalQuantity,
        price: item.unitPrice,
        allowDuplicateLine: item.category == 'glass',
      );
    }
    await widget.db.updateAchatTotal(
      achatId,
      _purchaseDocumentItemsTotal(items),
    );
    if (request['kind'] == _PurchaseDocumentKind.purchaseOrder) {
      await widget.db.updateAchatStatus(achatId, 'Draft');
    }
    return achatId;
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

    final request = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) => _ConvertGoodsToPurchaseDialog(
        suppliers: suppliers,
        locations: locations,
        nextNumber: nextNumber,
        purchaseItems: purchaseItems,
        t: _t,
      ),
    );
    if (request == null || !mounted) return;

    setState(() => _isCreatingPurchase = true);
    try {
      final glassItems = purchaseItems
          .where((item) => item.category == 'glass')
          .toList();
      final otherItems = purchaseItems
          .where((item) => item.category != 'glass')
          .toList();
      final baseNumber = request['number'] as String;

      int? firstAchatId;
      var firstInvoiceNumber = baseNumber;
      final createdDescriptions = <String>[];

      Future<String> resolveUniqueNumber(String requested) async {
        var candidate = requested;
        var suffix = 2;
        while (await widget.db.achatInvoiceNumberExists(candidate)) {
          candidate = '$requested-$suffix';
          suffix++;
        }
        return candidate;
      }

      if (otherItems.isNotEmpty) {
        final rawMaterialsNumber = glassItems.isEmpty
            ? baseNumber
            : '$baseNumber-M';
        final materialsNumber = await resolveUniqueNumber(rawMaterialsNumber);
        firstAchatId = await _createAchatDocumentFromItems(
          number: materialsNumber,
          request: request,
          items: otherItems,
        );
        firstInvoiceNumber = materialsNumber;
        createdDescriptions.add(
          '${_t('المواد')}: ${otherItems.length} ${_t('سطر')}',
        );
      }

      if (glassItems.isNotEmpty) {
        final rawGlassNumber = otherItems.isEmpty ? baseNumber : '$baseNumber-G';
        final glassNumber = await resolveUniqueNumber(rawGlassNumber);
        final glassAchatId = await _createAchatDocumentFromItems(
          number: glassNumber,
          request: request,
          items: glassItems,
        );
        firstAchatId ??= glassAchatId;
        if (firstAchatId == glassAchatId) firstInvoiceNumber = glassNumber;
        createdDescriptions.add(
          '${_t('الزجاج')}: ${glassItems.length} ${_t('سطر')} / '
          '${_roundQuantity(_purchaseDocumentItemsTotalArea(glassItems), 'm²')} m²',
        );
      }
      final achatId = firstAchatId;
      if (achatId == null) return;

      if (mounted && createdDescriptions.length > 1) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${_t('تم إنشاء وثائق الشراء:')} ${createdDescriptions.join('، ')}',
            ),
          ),
        );
      }
      if (!mounted) return;
      final docTitle = request['kind'] == _PurchaseDocumentKind.purchaseOrder
          ? '${_t('طلب شراء')} #$firstInvoiceNumber'
          : '${_t('فاتورة شراء')} #$firstInvoiceNumber';
      openAdaptiveScreen(
        context,
        title: docTitle,
        icon: Icons.receipt_long_outlined,
        screen: AchatDetailsScreen(
          achatId: achatId,
          invoiceNumber: firstInvoiceNumber,
          supplierName: request['supplier_name'] as String,
          db: widget.db,
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

  double _purchaseDocumentItemsTotalArea(List<AggregatedGoodItem> items) =>
      items.fold(0.0, (sum, item) => sum + item.totalQuantity);

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
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                _t('كمية السلع المطلوبة'),
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: Colors.white,
                ),
              ),
            ),
            if (clientDisplay.isNotEmpty)
              Text(
                clientDisplay,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11,
                  color: Colors.white70,
                  fontWeight: FontWeight.w500,
                ),
              ),
          ],
        ),
        centerTitle: false,
        backgroundColor: isDark
            ? (Theme.of(context).appBarTheme.backgroundColor ??
                  const Color(0xFF1A237E))
            : const Color(0xFF1A237E),
        foregroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.white),
        actionsIconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
        actions: [
          ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width > 700
                  ? 550
                  : MediaQuery.of(context).size.width * 0.62,
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!_isLoading && _errorMessage == null && _aggregatedItems.isNotEmpty)
                    IconButton(
                      icon: const Icon(Icons.print),
                      tooltip: 'طباعة الكمية المطلوبة',
                      onPressed: _printRequiredGoods,
                    ),
                  if (!_isLoading &&
                      _errorMessage == null &&
                      _aggregatedItems.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.amber.shade700,
                          foregroundColor: Colors.white,
                          elevation: 1,
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        icon: const Icon(Icons.analytics_outlined, size: 18),
                        label: Text(
                          _t('تقرير النواقص والمخزون'),
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        onPressed: _showShortageReport,
                      ),
                    ),
                  if (!_isLoading &&
                      _errorMessage == null &&
                      _cuttableCatalogItems.isNotEmpty)
                    IconButton(
                      icon: const Icon(Icons.inventory_2_outlined, color: Colors.white),
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
                          : const Icon(
                              Icons.shopping_cart_checkout,
                              color: Colors.white,
                            ),
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
                      icon: const Icon(Icons.refresh, color: Colors.white),
                      tooltip: _t('إعادة الحساب'),
                      onPressed: _loadAndAggregate,
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
      body: _buildBody(),
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
        _buildReservationStatusBanner(),
        // شريط معلومات الملخص
        _buildInfoBanner(),
        if (_processingWarnings.isNotEmpty) _buildWarningsBanner(),
        // القائمة
        Expanded(child: _buildGroupedList()),
      ],
    );
  }

  Widget _buildReservationStatusBanner() {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: _isStockReserved
            ? Colors.green.shade50
            : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: _isStockReserved ? Colors.green.shade600 : Colors.grey.shade400,
          width: 1.2,
        ),
      ),
      child: Row(
        children: [
          Icon(
            _isStockReserved ? Icons.check_circle : Icons.inventory_2_outlined,
            color: _isStockReserved ? Colors.green.shade700 : Colors.grey.shade700,
            size: 22,
          ),
          const SizedBox(width: 10),
          Text(
            _t('حالة حجز السلع بالمخزون:'),
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 13,
              color: Colors.grey.shade800,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
              color: _isStockReserved ? Colors.green.shade700 : Colors.grey.shade500,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _isStockReserved ? Icons.check : Icons.lock_open,
                  size: 13,
                  color: Colors.white,
                ),
                const SizedBox(width: 4),
                Text(
                  _isStockReserved ? _t('تم الحجز') : _t('لم يُحجز بعد'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const Spacer(),
          TextButton.icon(
            onPressed: _showShortageReport,
            icon: Icon(
              _isStockReserved ? Icons.edit_note : Icons.bookmark_add_outlined,
              size: 16,
              color: _isStockReserved ? Colors.green.shade800 : const Color(0xFF1A237E),
            ),
            label: Text(
              _isStockReserved ? _t('إدارة الحجز / النواقص') : _t('حجز السلع للطلبية'),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: _isStockReserved ? Colors.green.shade800 : const Color(0xFF1A237E),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryFilters() {
    const filters = <(String, String, IconData)>[
      ('all', 'الكل', Icons.apps_rounded),
      ('profile', 'البروفيلات', Icons.view_stream_outlined),
      ('accessory', 'الإكسسوارات', Icons.build_outlined),
      ('glass', 'الزجاج', Icons.grid_view_rounded),
      ('shutter', 'مكونات الستار', Icons.blinds_outlined),
      ('joint', 'الجوانات', Icons.horizontal_rule_rounded),
    ];
    return SizedBox(
      height: 40,
      child: ListView.separated(
        padding: EdgeInsets.zero,
        scrollDirection: Axis.horizontal,
        itemCount: filters.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final filter = filters[index];
          final selected = _selectedCategory == filter.$1;
          final color = filter.$1 == 'all'
              ? const Color(0xFF1A237E)
              : _categoryColor(filter.$1);
          return FilterChip(
            selected: selected,
            showCheckmark: false,
            avatar: Icon(
              filter.$3,
              size: 17,
              color: selected ? Colors.white : color,
            ),
            label: Text(_t(filter.$2)),
            labelStyle: TextStyle(
              color: selected ? Colors.white : color,
              fontWeight: FontWeight.w700,
            ),
            selectedColor: color,
            backgroundColor: Colors.white,
            side: BorderSide(color: color.withValues(alpha: 0.35)),
            onSelected: (_) => setState(() => _selectedCategory = filter.$1),
          );
        },
      ),
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
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * 0.2,
              ),
              child: SingleChildScrollView(
                child: Text(
                  _processingWarnings.join('\n'),
                  style: TextStyle(color: Colors.amber.shade900, fontSize: 11),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoBanner() {
    final summary = Tooltip(
      message: _t('مطابقة لجدول الكمية والتكلفة • القطاعات بأعداد كاملة'),
      child: Text(
        '${_t('إجمالي')} ${_aggregatedItems.length} ${_t('نوع سلعة من')} $_productCount ${_t('منتج')}',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 13,
        ),
      ),
    );
    final cost = Column(
      mainAxisSize: MainAxisSize.min,
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
            fontSize: 14,
          ),
        ),
      ],
    );
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1A237E), Color(0xFF3949AB)],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        borderRadius: BorderRadius.circular(10),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth >= 1000) {
            return Row(
              children: [
                SizedBox(width: 200, child: summary),
                const SizedBox(width: 12),
                Expanded(child: _buildCategoryFilters()),
                const SizedBox(width: 12),
                cost,
              ],
            );
          }
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(child: summary),
                  const SizedBox(width: 12),
                  Flexible(child: cost),
                ],
              ),
              const SizedBox(height: 4),
              _buildCategoryFilters(),
            ],
          );
        },
      ),
    );
  }

  Widget _buildGroupedList() {
    // تجميع العناصر حسب الفئة ثم اللون للبروفيلات والإكسسوارات.
    final Map<String, List<AggregatedGoodItem>> grouped = {};
    for (final item in _visibleItems) {
      grouped.putIfAbsent(item.category, () => []).add(item);
    }
    final categories = grouped.keys.toList()
      ..sort((a, b) => _categorySortIndex(a).compareTo(_categorySortIndex(b)));

    if (MediaQuery.sizeOf(context).width >= 900) {
      return _buildDesktopRequiredGoodsTable();
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
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

  Widget _buildDesktopRequiredGoodsTable() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final headerStyle = const TextStyle(
      color: Colors.white,
      fontWeight: FontWeight.bold,
      fontSize: 12,
    );
    final rows = <ResizableTableRow>[];

    // تجميع العناصر حسب الفئات لعرض أقسام مفصولة ومنظمة
    final Map<String, List<AggregatedGoodItem>> grouped = {};
    for (final item in _visibleItems) {
      grouped.putIfAbsent(item.category, () => []).add(item);
    }
    final categories = grouped.keys.toList()
      ..sort((a, b) => _categorySortIndex(a).compareTo(_categorySortIndex(b)));

    final showCategoryHeaders = _selectedCategory == 'all';

    for (final cat in categories) {
      final items = grouped[cat]!;
      if (showCategoryHeaders) {
        rows.add(_buildDesktopCategoryHeaderRow(cat, items, isDark));
      }

      for (final item in items) {
        rows.add(_buildDesktopRequiredGoodsRow(item, item.category, isDark));
        final kitName = item.kitGroupName;
        if (kitName != null &&
            kitName.isNotEmpty &&
            _expandedKits.contains(item.name)) {
          for (final child in item.kitSubItems) {
            if (!child.originalName.startsWith('${kitName}_')) continue;
            rows.add(_buildDesktopKitChildRow(child, isDark));
          }
        }

        final plan = item.cuttingPlan;
        if (plan != null &&
            _expandedCuttingPlans.contains(_cuttingKeyForItem(item))) {
          rows.addAll(_buildDesktopCuttingRows(item, plan, isDark));
        }
      }
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _t('⠿ اضغط مطولاً على الصف ثم اسحبه لإعادة ترتيب السلع وخطط التقطيع'),
            style: TextStyle(
              fontSize: 11,
              color: isDark ? Colors.white54 : Colors.blueGrey.shade600,
            ),
          ),
          const SizedBox(height: 5),
          Expanded(
            child: ResizableColumnsTable(
              key: ValueKey(
                'required-goods-$_selectedCategory-${_visibleItems.length}',
              ),
              persistenceKey: 'order_required_goods',
              headerColor: isDark
                  ? Colors.grey.shade900
                  : Colors.blueGrey.shade800,
              borderColor: isDark ? Colors.grey.shade800 : Colors.grey.shade300,
              rowColor: isDark ? const Color(0xFF171721) : Colors.white,
              headerMinHeight: 42,
              rowMinHeight: 54,
              cellPadding: const EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 6,
              ),
              // Kit children are attached to their header. Reordering flat
              // rows (including restored user order) splits that hierarchy.
              reorderableRows: false,
              columns: [
                ResizableTableColumn(
                  id: 'image',
                  label: Text(_t('الصورة'), style: headerStyle),
                  initialWidth: 72,
                  minWidth: 58,
                  maxWidth: 110,
                  alignment: Alignment.center,
                ),
                ResizableTableColumn(
                  id: 'category',
                  label: Text(_t('الفئة'), style: headerStyle),
                  initialWidth: 160,
                  minWidth: 120,
                  maxWidth: 240,
                ),
                ResizableTableColumn(
                  id: 'name',
                  label: Text(_t('Libellé / Description'), style: headerStyle),
                  initialWidth: 330,
                  minWidth: 220,
                  maxWidth: 620,
                ),
                ResizableTableColumn(
                  id: 'details',
                  label: Text(_t('التفاصيل'), style: headerStyle),
                  initialWidth: 300,
                  minWidth: 180,
                  maxWidth: 520,
                ),
                ResizableTableColumn(
                  id: 'actual',
                  label: Text(_t('المطلوب الفعلي'), style: headerStyle),
                  initialWidth: 140,
                  minWidth: 110,
                  maxWidth: 220,
                ),
                ResizableTableColumn(
                  id: 'purchase',
                  label: Text(_t('كمية الشراء'), style: headerStyle),
                  initialWidth: 140,
                  minWidth: 110,
                  maxWidth: 220,
                ),
                ResizableTableColumn(
                  id: 'stock',
                  label: Text(
                    '${_t('المخزون')} (${_t(_mainWarehouseName)})',
                    style: headerStyle,
                  ),
                  initialWidth: 165,
                  minWidth: 125,
                  maxWidth: 250,
                ),
                ResizableTableColumn(
                  id: 'unit_price',
                  label: Text(_t('سعر الوحدة'), style: headerStyle),
                  initialWidth: 130,
                  minWidth: 105,
                  maxWidth: 210,
                ),
                ResizableTableColumn(
                  id: 'estimated',
                  label: Text(_t('السعر التقديري'), style: headerStyle),
                  initialWidth: 150,
                  minWidth: 120,
                  maxWidth: 240,
                ),
                ResizableTableColumn(
                  id: 'actions',
                  label: Text(_t('إجراء'), style: headerStyle),
                  initialWidth: 110,
                  minWidth: 90,
                  maxWidth: 180,
                  alignment: Alignment.center,
                ),
              ],
              rows: rows,
            ),
          ),
        ],
      ),
    );
  }

  ResizableTableRow _buildDesktopCategoryHeaderRow(
    String category,
    List<AggregatedGoodItem> items,
    bool isDark,
  ) {
    final color = _categoryColor(category);
    final totalCatCost = items.fold<double>(0, (sum, it) => sum + it.totalCost);
    final isGlass = category == 'glass';
    final totalGlassPieces = isGlass
        ? items.fold<int>(
            0,
            (sum, it) => sum + (it.pieceCount > 0 ? it.pieceCount : 1),
          )
        : 0;
    final totalGlassArea = isGlass
        ? items.fold<double>(0, (sum, it) => sum + it.totalQuantity)
        : 0.0;

    return ResizableTableRow(
      reorderId: 'category-header:$category',
      color: isDark
          ? color.withValues(alpha: 0.22)
          : color.withValues(alpha: 0.12),
      cells: [
        Center(
          child: Icon(_categoryIcon(category), color: color, size: 20),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: color.withValues(alpha: 0.4)),
          ),
          child: Text(
            _categoryLabel(category),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
        ),
        Text(
          isGlass
              ? '${items.length} ${_t('مقاسات زجاج')} • $totalGlassPieces ${_t('قطع')}'
              : '${items.length} ${_t('أصناف مسجلة')}',
          style: TextStyle(
            color: isDark ? Colors.white : Colors.black87,
            fontWeight: FontWeight.bold,
            fontSize: 12,
          ),
        ),
        Text(
          isGlass
              ? '${_t('المساحة الإجمالية')}: ${totalGlassArea.toStringAsFixed(2)} m²'
              : '-',
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.w600,
            fontSize: 11,
          ),
        ),
        const SizedBox.shrink(),
        const SizedBox.shrink(),
        const SizedBox.shrink(),
        const SizedBox.shrink(),
        Text(
          '${totalCatCost.toStringAsFixed(2)} دج',
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.bold,
            fontSize: 12,
          ),
        ),
        const SizedBox.shrink(),
      ],
    );
  }

  ResizableTableRow _buildDesktopRequiredGoodsRow(
    AggregatedGoodItem item,
    String category,
    bool isDark,
  ) {
    final color = _categoryColor(category);
    final isKit = item.kitGroupName != null && item.kitGroupName!.isNotEmpty;
    final plan = item.cuttingPlan;
    final rowColor = isDark
        ? color.withValues(alpha: 0.08)
        : color.withValues(alpha: 0.035);
    final onTap = isKit
        ? () => _toggleKitExpansion(item.name)
        : category == 'profile'
        ? () => _showSectionSelectionDialog(item, category)
        : category == 'glass'
        ? () => _showGlassPreviewDialog(item)
        : null;

    return ResizableTableRow(
      reorderId: 'item:${_aggregatedGoodReorderKey(item, category)}',
      color: rowColor,
      onTap: onTap,
      cells: [
        Center(
          child: item.category == 'glass' && item.sourceModel != null
              ? Tooltip(
                  message: _t('عرض رسم النافذة ومقاسات الزجاج والديكور'),
                  child: InkWell(
                    onTap: () => _showGlassPreviewDialog(item),
                    child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.cyan.shade400, width: 1.5),
                      boxShadow: const [
                        BoxShadow(
                          color: Colors.black12,
                          blurRadius: 3,
                          offset: Offset(0, 1),
                        ),
                      ],
                    ),
                    padding: const EdgeInsets.all(2),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: CustomPaint(
                        painter: WindowPainter(
                          model: item.sourceModel!,
                          showDrawingDimensions: false,
                        ),
                      ),
                    ),
                  ),
                ),
              )
            : (isKit
                  ? Icon(Icons.inventory, color: color)
                  : SectionImageWidget(
                      code: item.profileCode,
                      name: item.name,
                      imagePath: item.imagePath,
                      size: _isPlintheItem(item.name, item.originalName) ? 40 : 34,
                      fallbackIcon: _categoryIcon(category),
                      fallbackColor: color,
                    )),
        ),
        _desktopCategoryCell(category, color, isDark),
        _desktopNameCell(
          title: _t(item.name),
          subtitle: item.name != item.originalName
              ? '${_t('المكوّن المطلوب')}: ${_t(item.originalName)}'
              : null,
          isDark: isDark,
          leading: item.isMissing
              ? Icon(
                  Icons.warning_amber_rounded,
                  color: Colors.orange.shade700,
                  size: 17,
                )
              : null,
        ),
        _desktopTextCell(_itemMeta(item), isDark: isDark, maxLines: 3),
        _desktopTextCell(
          _actualRequiredLabel(item),
          isDark: isDark,
          fontWeight: FontWeight.w700,
        ),
        _desktopTextCell(
          _purchaseQuantityLabel(item),
          isDark: isDark,
          color: color,
          fontWeight: FontWeight.w800,
        ),
        _desktopTextCell(
          _stockLabel(
            _stockQuantityFor(
              itemId: item.catalogItemId,
              itemType: item.inventoryItemType,
              colorId: item.colorId,
            ),
            item.unit,
          ),
          isDark: isDark,
          color: Colors.teal,
          fontWeight: FontWeight.w800,
        ),
        _desktopTextCell(
          item.unitPrice > 0
              ? '${item.unitPrice.toStringAsFixed(2)} دج / ${_t(item.unit)}'
              : _t('السعر غير محدد'),
          isDark: isDark,
        ),
        _desktopTextCell(
          '${item.totalCost.toStringAsFixed(2)} دج',
          isDark: isDark,
          fontWeight: FontWeight.w800,
        ),
        _desktopActionCell(item, category, plan, color),
      ],
    );
  }

  ResizableTableRow _buildDesktopKitChildRow(BomItem child, bool isDark) {
    final category = requiredGoodsCategoryForBom(child);
    final color = _categoryColor(category);
    final details = <String>[
      if ((child.profileCode ?? '').trim().isNotEmpty)
        '${_t('الكود')}: ${child.profileCode}',
      if ((child.colorName ?? '').trim().isNotEmpty)
        '${_t('اللون')}: ${_t(child.colorName!)}',
      if ((child.length ?? 0) > 0) '${_t('القياس')}: ${child.length}',
    ].join(' • ');

    return ResizableTableRow(
      reorderId:
          'kit-child:${child.kitGroupName ?? ''}:${child.originalName}:${child.catalogItemId ?? child.name}:${child.unit}',
      color: isDark
          ? Colors.white.withValues(alpha: 0.03)
          : Colors.grey.shade50,
      cells: [
        Icon(Icons.subdirectory_arrow_left, size: 18, color: color),
        _desktopCategoryCell(category, color, isDark),
        _desktopNameCell(
          title: requiredGoodsDisplayName(child),
          subtitle: _t('مكوّن داخل الكِت'),
          isDark: isDark,
        ),
        _desktopTextCell(details, isDark: isDark, maxLines: 2),
        _desktopTextCell(
          '${_roundQuantity(child.purchaseQuantity, child.unit)} ${_t(child.unit)}',
          isDark: isDark,
        ),
        _desktopTextCell(
          '${_roundQuantity(child.purchaseQuantity, child.unit)} ${_t(child.unit)}',
          isDark: isDark,
          color: color,
          fontWeight: FontWeight.w700,
        ),
        _desktopTextCell(
          _stockLabel(
            _stockQuantityFor(
              itemId: child.catalogItemId,
              itemType: child.inventoryItemType,
              colorId: child.colorId,
            ),
            child.unit,
          ),
          isDark: isDark,
          color: Colors.teal,
          fontWeight: FontWeight.w700,
        ),
        _desktopTextCell(
          '${child.unitPrice.toStringAsFixed(2)} دج / ${_t(child.unit)}',
          isDark: isDark,
        ),
        _desktopTextCell(
          '${child.total.toStringAsFixed(2)} دج',
          isDark: isDark,
          fontWeight: FontWeight.w700,
        ),
        const SizedBox.shrink(),
      ],
    );
  }

  List<ResizableTableRow> _buildDesktopCuttingRows(
    AggregatedGoodItem item,
    OrderCuttingPlan plan,
    bool isDark,
  ) {
    final color = _categoryColor(item.category);
    return plan.bars.indexed.map((entry) {
      final barNumber = entry.$1 + 1;
      final cuts = entry.$2;
      final cutText = cuts.map((cut) => '${(cut * 1000).round()}').join(' + ');
      final remainder = _barRemainder(plan, cuts);
      return ResizableTableRow(
        reorderId:
            'cut:${_aggregatedGoodReorderKey(item, item.category)}:$barNumber',
        color: isDark
            ? color.withValues(alpha: 0.04)
            : color.withValues(alpha: 0.025),
        cells: [
          Icon(Icons.content_cut, size: 18, color: color),
          _desktopTextCell(_t('خطة القص'), isDark: isDark),
          _desktopNameCell(
            title: '${_t('قطاع')} $barNumber',
            subtitle: _t(item.name),
            isDark: isDark,
          ),
          _desktopTextCell(
            '$cutText mm • ${_t('الباقي')}: ${(remainder * 1000).round()} mm',
            isDark: isDark,
            maxLines: 2,
          ),
          _desktopTextCell('-', isDark: isDark),
          _desktopTextCell('-', isDark: isDark),
          _desktopTextCell('-', isDark: isDark),
          _desktopTextCell('-', isDark: isDark),
          _desktopTextCell('-', isDark: isDark),
          const SizedBox.shrink(),
        ],
      );
    }).toList();
  }

  Widget _desktopCategoryCell(String category, Color color, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.18 : 0.1),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        _categoryLabel(category),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _desktopNameCell({
    required String title,
    required bool isDark,
    String? subtitle,
    Widget? leading,
  }) {
    return Row(
      children: [
        if (leading != null) ...[leading, const SizedBox(width: 5)],
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _t(title),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: isDark ? Colors.white : const Color(0xFF1A1A2E),
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
              if (subtitle != null && subtitle.trim().isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: isDark ? Colors.white60 : Colors.grey.shade600,
                    fontSize: 11,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _desktopTextCell(
    String text, {
    required bool isDark,
    Color? color,
    FontWeight fontWeight = FontWeight.w500,
    int maxLines = 2,
  }) {
    return Text(
      text.trim().isEmpty ? '-' : text,
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: color ?? (isDark ? Colors.white70 : Colors.grey.shade800),
        fontSize: 12,
        fontWeight: fontWeight,
      ),
    );
  }

  Widget _desktopActionCell(
    AggregatedGoodItem item,
    String category,
    OrderCuttingPlan? plan,
    Color color,
  ) {
    final isKit = item.kitGroupName != null && item.kitGroupName!.isNotEmpty;
    if (isKit) {
      final isExpanded = _expandedKits.contains(item.name);
      return IconButton(
        tooltip: _t(isExpanded ? 'إخفاء المكونات' : 'عرض المكونات'),
        onPressed: () => _toggleKitExpansion(item.name),
        icon: Icon(
          isExpanded ? Icons.expand_less : Icons.expand_more,
          color: color,
        ),
      );
    }
    if (category == 'glass') {
      return IconButton(
        tooltip: _t('معاينة تفاصيل الزجاج والديكور'),
        onPressed: () => _showGlassPreviewDialog(item),
        icon: Icon(Icons.visibility_outlined, color: color),
      );
    }
    if (category == 'profile' || plan != null) {
      final key = plan == null ? null : _cuttingKeyForItem(item);
      final isExpanded = key != null && _expandedCuttingPlans.contains(key);
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (category == 'profile')
            IconButton(
              tooltip: _t('تغيير القطاع'),
              onPressed: () => _showSectionSelectionDialog(item, category),
              icon: Icon(Icons.compare_arrows, color: color),
            ),
          if (key != null)
            IconButton(
              tooltip: _t(isExpanded ? 'إخفاء خطة القص' : 'عرض خطة القص'),
              onPressed: () => _toggleCuttingPlanExpansion(key),
              icon: Icon(
                isExpanded ? Icons.expand_less : Icons.content_cut,
                color: color,
              ),
            ),
        ],
      );
    }
    return const SizedBox.shrink();
  }

  void _toggleKitExpansion(String key) {
    setState(() {
      if (_expandedKits.contains(key)) {
        _expandedKits.remove(key);
      } else {
        _expandedKits.add(key);
      }
    });
  }

  String _aggregatedGoodReorderKey(AggregatedGoodItem item, String category) =>
      [
        category,
        item.catalogItemId ?? '',
        item.inventoryItemType ?? '',
        item.profileCode ?? '',
        item.originalName,
        item.name,
        item.unit,
        item.colorId ?? item.colorName ?? '',
        item.stockLength ?? '',
      ].join('|');

  String _cuttingKeyForItem(AggregatedGoodItem item) =>
      '${item.category}:${item.name}:${item.profileCode ?? ''}:${item.colorName ?? item.colorId ?? ''}:${item.stockLength}';

  void _toggleCuttingPlanExpansion(String key) {
    setState(() {
      if (_expandedCuttingPlans.contains(key)) {
        _expandedCuttingPlans.remove(key);
      } else {
        _expandedCuttingPlans.add(key);
      }
    });
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

  String _remnantThresholdKeyForItem(AggregatedGoodItem item) {
    final text = '${item.category} ${item.originalName} ${item.name}'
        .toLowerCase()
        .replaceAll('ـ', ' ');
    final hasSideCover =
        text.contains('غطاء جانبي') ||
        text.contains('الغطاء الجانبي') ||
        text.contains('side cover') ||
        text.contains('couvre-joint') ||
        text.contains('couvre joint') ||
        text.contains('couvre');
    if (hasSideCover) return 'frame_side_cover';

    final isProfile =
        item.category == 'profile' ||
        item.category == 'frame' ||
        item.category == 'mullion' ||
        item.category == 'sash';
    if (!isProfile) return '';
    if (text.contains('تقسيم') ||
        text.contains('فاصل') ||
        text.contains('عمود') ||
        text.contains('mullion') ||
        text.contains('partition') ||
        text.contains('traverse')) {
      return 'mullion';
    }
    if (text.contains('دلفة') ||
        text.contains('ضلفة') ||
        text.contains('كانة') ||
        text.contains('sash') ||
        text.contains('ouvrant')) {
      return 'sash';
    }
    if (text.contains('إطار') ||
        text.contains('اطار') ||
        text.contains('frame') ||
        text.contains('cadre') ||
        item.category == 'frame') {
      return 'frame';
    }
    return '';
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
    final configuredMinimums = await widget.db.readMinimumReusableLengthsMm();
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
      final thresholdKey = _remnantThresholdKeyForItem(item);
      final minimumForItem = configuredMinimums[thresholdKey] ?? minimum;
      for (final cuts in plan.bars) {
        bars.add({
          'item_id': item.catalogItemId,
          'item_type': item.inventoryItemType,
          'series_id': seriesId,
          'color_id': item.colorId,
          'bar_index': globalBarIndex++,
          'remainder_mm': _barRemainder(plan, cuts) * 1000,
          'kerf_loss_mm': cuts.length * plan.bladeWaste * 1000,
          'minimum_reusable_length_mm': minimumForItem,
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

  Future<void> _showShortageReport({bool autoApply = false}) async {
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
          'missing': (neededBars - stockUsed).clamp(0, double.infinity),
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
          'missing': (item.totalQuantity - stockUsed).clamp(0, double.infinity),
        });
      }
    }
    if (!mounted) return;
    final inventoryIssued = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => _OrderShortageReportPage(
          orderId: _safeInt(widget.orderData['id'])!,
          db: widget.db,
          reports: reports,
          customerName:
              widget.orderData['client_name']?.toString() ??
              widget.orderData['client_display']?.toString(),
          autoApply: autoApply,
        ),
      ),
    );
    if (mounted) {
      await _refreshReservationStatus();
    }
    // Propagate the completed issue through this intermediate page so the
    // order action can actually advance to the requested manufacturing stage.
    if (inventoryIssued == true &&
        widget.issueAtManufacturingStart &&
        mounted) {
      Navigator.pop(context, true);
    }
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

    final isAccessory = category.toLowerCase() == 'accessory';
    // Accessories are catalogue products, not aluminium Sections.  Looking
    // them up in Sections made the change sheet offer an unrelated profile;
    // the next BOM refresh then correctly discarded that invalid selection.
    final rawSections = isAccessory
        ? await dbInstance.query(
            'Accessories',
            where:
                '(is_active = 1 OR is_active IS NULL) AND '
                '(series_id = ? OR series_id IS NULL OR series_id = 0 OR '
                "(',' || REPLACE(COALESCE(series_ids, ''), ' ', '') || ',') LIKE ?)",
            whereArgs: [activeSeries.id, '%,${activeSeries.id},%'],
            orderBy: 'is_default DESC, id ASC',
          )
        : await dbInstance.query(
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

    if (isAccessory) {
      // The rule engine validates the saved choice. This list deliberately
      // contains only active products compatible with the selected series.
      filteredSections = List<Map<String, dynamic>>.from(rawSections);
    } else if (origLower.contains('rail') || origLower.contains('سكة')) {
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
                          name: secName.toString(),
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
                        if (isAccessory) {
                          // A replacement selected from this sheet is an
                          // explicit user decision. BomEngineV2 keeps it if
                          // it is active and compatible with this series.
                          mutableSec['manual_selection'] = true;
                        }

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
                            '${_t('المخزون')}: ${_stockLabel(_stockQuantityFor(itemId: sub.catalogItemId, itemType: sub.inventoryItemType, colorId: sub.colorId), sub.unit)}',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Colors.teal.shade600,
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
    final cuttingKey = _cuttingKeyForItem(item);
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
              : category == 'glass'
              ? () => _showGlassPreviewDialog(item)
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
                    child: item.category == 'glass' && item.sourceModel != null
                        ? CustomPaint(
                            painter: WindowPainter(
                              model: item.sourceModel!,
                              showDrawingDimensions: false,
                            ),
                          )
                        : SectionImageWidget(
                            code: item.profileCode,
                            name: item.name,
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
                    const SizedBox(height: 3),
                    Text(
                      '${_t('المخزون')}: ${_stockLabel(_stockQuantityFor(itemId: item.catalogItemId, itemType: item.inventoryItemType, colorId: item.colorId), item.unit)}',
                      style: TextStyle(
                        color: Colors.teal.shade600,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
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

  // ─────────────────────────────────────────────────────────────────
  // دوال مساعدة
  // ─────────────────────────────────────────────────────────────────

  /// الوحدات المستمرة تبقى عشرية، أما وحدات الشراء العددية فتعرض أعدادًا كاملة.
  String _roundQuantity(double qty, String unit) {
    final unitLower = unit.toLowerCase();
    if (qty == qty.roundToDouble()) return qty.round().toString();
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
    if (item.category == 'glass' &&
        (item.stockLength ?? 0) > 0 &&
        (item.glassHeight ?? 0) > 0) {
      final pieces =
          item.pieceCount > 0 ? '${item.pieceCount} ${_t('قطعة')}' : '';
      final dims =
          '${item.stockLength!.round()} × ${item.glassHeight!.round()} mm';
      final sqm = '${_roundQuantity(item.totalQuantity, 'm²')} m²';
      if (pieces.isNotEmpty) {
        return '$pieces ($dims)\n$sqm';
      }
      return '$dims ($sqm)';
    }
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

  String _actualRequiredLabel(AggregatedGoodItem item) {
    final isBardage =
        item.category == 'profile' &&
        (item.unit.trim().toLowerCase() == 'قطعة' ||
            isBardagePanelSubtype(item.originalName));
    if (isBardage) return _purchaseQuantityLabel(item);
    if (item.cuttingPieces.isNotEmpty) {
      final actualMeters = item.cuttingPieces.fold<double>(
        0,
        (sum, piece) => sum + piece,
      );
      return '${_roundQuantity(actualMeters, 'م')} ${_t('م')}';
    }
    if (item.category == 'glass' || item.unit.trim().toLowerCase() == 'm²') {
      if ((item.stockLength ?? 0) > 0 && (item.glassHeight ?? 0) > 0) {
        final pieces =
            item.pieceCount > 0 ? '${item.pieceCount} ${_t('قطعة')} ' : '';
        final dims =
            '${item.stockLength!.round()} × ${item.glassHeight!.round()} mm';
        final sqm = '${_roundQuantity(item.totalQuantity, 'm²')} m²';
        return '$pieces($dims)\n$sqm';
      }
      return '${_roundQuantity(item.totalQuantity, 'm²')} m²';
    }
    return _purchaseQuantityLabel(item);
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
      if (item.pieceCount > 0) {
        parts.add('${_t('العدد')}: ${item.pieceCount} ${_t('قطعة')}');
      }
      parts.add(
        '${_t('المساحة المطلوبة')}: ${_roundQuantity(item.totalQuantity, 'm²')} m²',
      );
      if (item.sourceModel != null) {
        final hasDecor = item.sourceModel!.zones.any((z) =>
            z.glass.decorH > 0 ||
            z.glass.decorV > 0 ||
            z.glass.hasRosettes ||
            z.glass.decorBaguetteId != null ||
            z.glass.decorRosetteId != null);
        if (hasDecor) {
          parts.add('🎨 ${_t('ديكور باجيت / وردات')}');
        }
      }
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

  void _showGlassPreviewDialog(AggregatedGoodItem item) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final model = item.sourceModel;
    final cutW = item.stockLength?.round() ?? 0;
    final cutH = item.glassHeight?.round() ?? 0;
    final pieces = item.pieceCount > 0 ? item.pieceCount : 1;
    final totalArea = item.totalQuantity;

    // Check decor
    String? decorInfo;
    if (model != null) {
      final decorZones = model.zones.where((z) =>
          z.glass.decorH > 0 ||
          z.glass.decorV > 0 ||
          z.glass.hasRosettes ||
          z.glass.decorBaguetteId != null ||
          z.glass.decorRosetteId != null).toList();
      if (decorZones.isNotEmpty) {
        final dz = decorZones.first;
        final h = dz.glass.decorH;
        final v = dz.glass.decorV;
        final hasRos = dz.glass.hasRosettes || dz.glass.decorRosetteId != null;
        final parts = <String>[];
        if (h > 0 || v > 0) {
          parts.add('${_t('تقسيمات باجيت')}: $h ${_t('أفقي')} × $v ${_t('عمودي')} (${dz.glass.decorThickness} ${_t('مم')} - ${_t(dz.glass.decorColor)})');
        }
        if (hasRos) {
          parts.add(_t('وردات ديكور مدمجة'));
        }
        decorInfo = parts.join(' • ');
      }
    }

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Container(
          width: 580,
          padding: const EdgeInsets.all(20),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.cyan.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.grid_view_rounded,
                        color: Colors.cyan,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _t('تفاصيل الزجاج والقياسات الحقيقية والديكور'),
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          Text(
                            _t('بيانات جاهزة للتحويل لمورد الزجاج'),
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (model != null) ...[
                  Container(
                    height: 280,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.cyan.shade200, width: 1.5),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    padding: const EdgeInsets.all(8),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: CustomPaint(
                        painter: WindowPainter(
                          model: model,
                          showDrawingDimensions: true,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                // Info badges
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF242424) : Colors.cyan.shade50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.cyan.shade200),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _dialogStatItem(
                            _t('مقاس القص الحقيقي'),
                            '$cutW × $cutH mm',
                            Icons.straighten,
                            Colors.cyan.shade800,
                          ),
                          _dialogStatItem(
                            _t('عدد الألواح'),
                            '$pieces ${_t('قطعة')}',
                            Icons.format_list_numbered,
                            Colors.indigo,
                          ),
                          _dialogStatItem(
                            _t('المساحة الإجمالية'),
                            '${totalArea.toStringAsFixed(2)} m²',
                            Icons.crop_square,
                            Colors.teal,
                          ),
                        ],
                      ),
                      if (decorInfo != null) ...[
                        const Divider(height: 16),
                        Row(
                          children: [
                            const Icon(
                              Icons.palette_outlined,
                              size: 18,
                              color: Colors.orange,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                decorInfo,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                  color: Colors.orange,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  _t('المواصفات والتركيب:'),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0xFF1E1E1E)
                        : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    item.name,
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.4,
                      color: isDark ? Colors.white70 : Colors.black87,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.cyan.shade800,
                    ),
                    onPressed: () => Navigator.pop(ctx),
                    icon: const Icon(Icons.check, size: 18),
                    label: Text(_t('إغلاق')),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _dialogStatItem(
    String label,
    String value,
    IconData icon,
    Color color,
  ) {
    return Column(
      children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 14,
            color: color,
          ),
        ),
        Text(
          label,
          style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
        ),
      ],
    );
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
            title: Text(
              _t('تفاصيل حساب كل منتج'),
              style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1A237E)),
            ),
            backgroundColor: Colors.white,
            surfaceTintColor: Colors.transparent,
            foregroundColor: const Color(0xFF1A237E),
            iconTheme: const IconThemeData(color: Color(0xFF1A237E)),
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
                              // The quantity breakdown must show the same
                              // drawing as the drawing page, including tunnel
                              // shutters; the official tunnel photo is only a
                              // system/catalogue icon.
                              child: CustomPaint(
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
                                  _t(pb.name),
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
                      _buildProductBomTable(pb, isDark),
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

  Widget _buildProductBomTable(ProductBreakdown pb, bool isDark) {
    final isDesktop = MediaQuery.sizeOf(context).width >= 900;
    final headerStyle = TextStyle(
      fontWeight: FontWeight.bold,
      fontSize: 12,
      color: isDesktop
          ? Colors.white
          : (isDark ? Colors.white.withValues(alpha: 0.87) : Colors.black87),
    );
    final bodyColor = isDark
        ? Colors.white.withValues(alpha: 0.9)
        : Colors.black87;

    if (isDesktop) {
      return ResizableColumnsTable(
        persistenceKey: 'order_required_goods_cutting',
        key: ValueKey('product-bom-${pb.index}'),
        headerColor: isDark ? Colors.grey.shade900 : Colors.blueGrey.shade800,
        borderColor: isDark ? Colors.grey.shade800 : Colors.grey.shade300,
        rowColor: isDark ? const Color(0xFF171721) : Colors.white,
        headerMinHeight: 38,
        rowMinHeight: 42,
        cellPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        maxBodyHeight: 360,
        columns: [
          ResizableTableColumn(
            id: 'name',
            label: Text(_t('اسم العنصر'), style: headerStyle),
            initialWidth: 360,
            minWidth: 220,
            maxWidth: 620,
          ),
          ResizableTableColumn(
            id: 'quantity',
            label: Text(_t('الكمية'), style: headerStyle),
            initialWidth: 120,
            minWidth: 90,
            maxWidth: 220,
          ),
          ResizableTableColumn(
            id: 'unit',
            label: Text(_t('الوحدة'), style: headerStyle),
            initialWidth: 110,
            minWidth: 80,
            maxWidth: 200,
          ),
          ResizableTableColumn(
            id: 'cost',
            label: Text(_t('التكلفة'), style: headerStyle),
            initialWidth: 140,
            minWidth: 100,
            maxWidth: 240,
          ),
        ],
        rows: pb.bomItems.map((bom) {
          final qty = bom.purchaseQuantity;
          final cost = bom.total;
          return ResizableTableRow(
            cells: [
              Row(
                children: [
                  SectionImageWidget(
                    code: bom.profileCode,
                    name: bom.name,
                    imagePath: bom.imagePath,
                    size: _isPlintheItem(bom.name, bom.originalName) ? 30 : 18,
                    fallbackIcon: _categoryIcon(bom.category),
                    fallbackColor: Colors.grey,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _t(bom.name),
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: bodyColor),
                    ),
                  ),
                ],
              ),
              Text(
                _roundQuantity(qty, bom.unit),
                style: TextStyle(fontSize: 12, color: bodyColor),
              ),
              Text(
                bom.unit,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: bodyColor),
              ),
              Text(
                '${cost.toStringAsFixed(0)} د.ج',
                style: TextStyle(
                  fontSize: 11,
                  color: isDark ? Colors.white70 : Colors.black87,
                ),
              ),
            ],
          );
        }).toList(),
      );
    }

    return Table(
      border: TableBorder.symmetric(
        inside: BorderSide(
          color: isDark ? Colors.grey.shade800 : Colors.grey.shade300,
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
            color: isDark ? Colors.grey.shade900 : Colors.grey.shade200,
          ),
          children: [
            _compactBomHeaderCell(_t('اسم العنصر'), headerStyle),
            _compactBomHeaderCell(_t('الكمية'), headerStyle),
            _compactBomHeaderCell(_t('الوحدة'), headerStyle),
            _compactBomHeaderCell(_t('التكلفة'), headerStyle),
          ],
        ),
        ...pb.bomItems.map((bom) {
          final qty = bom.purchaseQuantity;
          final cost = bom.total;
          return TableRow(
            children: [
              Padding(
                padding: const EdgeInsets.all(6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SectionImageWidget(
                      code: bom.profileCode,
                      name: bom.name,
                      imagePath: bom.imagePath,
                      size: _isPlintheItem(bom.name, bom.originalName)
                          ? 30
                          : 18,
                      fallbackIcon: _categoryIcon(bom.category),
                      fallbackColor: Colors.grey,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        _t(bom.name),
                        style: TextStyle(fontSize: 12, color: bodyColor),
                      ),
                    ),
                  ],
                ),
              ),
              _compactBomBodyCell(_roundQuantity(qty, bom.unit), bodyColor),
              _compactBomBodyCell(bom.unit, bodyColor),
              _compactBomBodyCell('${cost.toStringAsFixed(0)} د.ج', bodyColor),
            ],
          );
        }),
      ],
    );
  }

  Widget _compactBomHeaderCell(String text, TextStyle style) {
    return Padding(
      padding: const EdgeInsets.all(6),
      child: Text(text, style: style),
    );
  }

  Widget _compactBomBodyCell(String text, Color color) {
    return Padding(
      padding: const EdgeInsets.all(6),
      child: Text(text, style: TextStyle(fontSize: 12, color: color)),
    );
  }

  bool _isPlintheItem(String name, String originalName) {
    final value = '$name $originalName'.toLowerCase();
    return value.contains('بلانت') ||
        value.contains('plinthe') ||
        value.contains('plant');
  }
}

class _OrderShortageReportPage extends StatefulWidget {
  const _OrderShortageReportPage({
    required this.orderId,
    required this.db,
    required this.reports,
    this.customerName,
    this.autoApply = false,
  });

  final int orderId;
  final SqlDatabase db;
  final List<Map<String, dynamic>> reports;
  final String? customerName;
  final bool autoApply;

  @override
  State<_OrderShortageReportPage> createState() =>
      _OrderShortageReportPageState();
}

class _OrderShortageReportPageState extends State<_OrderShortageReportPage> {
  bool _automaticAttempted = false;
  bool _isStockReserved = false;

  int get orderId => widget.orderId;
  SqlDatabase get db => widget.db;
  List<Map<String, dynamic>> get reports => widget.reports;
  String? get customerName => widget.customerName;

  @override
  void initState() {
    super.initState();
    _loadReservationStatus();
    if (widget.autoApply) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_automaticAttempted) {
          _automaticAttempted = true;
          _applyInventoryIssue(context, automatic: true);
        }
      });
    }
  }

  Future<void> _loadReservationStatus() async {
    try {
      final reserved = await db.isOrderStockReserved(orderId);
      if (mounted) {
        setState(() {
          _isStockReserved = reserved;
        });
      }
    } catch (_) {}
  }

  Future<void> _toggleStockReservation(BuildContext context) async {
    final lang = Provider.of<AppSettingsProvider>(context, listen: false).language;
    String t(String key) => Localization.translate(key, lang);
    final newStatus = !_isStockReserved;
    final remnantIds = _usedRemnantIds();
    try {
      await db.setOrderStockReservation(
        orderId: orderId,
        reserved: newStatus,
        remnantIds: remnantIds,
      );
      if (!context.mounted) return;
      setState(() {
        _isStockReserved = newStatus;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            newStatus
                ? t('تم حجز سلع هذه الطلبية في المخزون بنجاح')
                : t('تم إلغاء حجز سلع هذه الطلبية في المخزون'),
          ),
          backgroundColor: newStatus ? Colors.green : Colors.orange,
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${t('تعذر تحديث الحجز')}: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  String _quantity(double value) => value == value.roundToDouble()
      ? value.round().toString()
      : value.toStringAsFixed(2);

  String _address(Map<String, dynamic> row) =>
      RemnantTicketService.storageAddress(row);

  List<int> _usedRemnantIds() {
    final ids = <int>{};
    for (final report in reports) {
      final plan = report['remnant_plan'] as InventoryAwareCuttingPlan?;
      if (plan == null) continue;
      for (final usage in plan.remnantUsages) {
        ids.add(usage.remnant.id);
      }
    }
    return ids.toList();
  }

  List<Map<String, dynamic>> _stockDeductions() {
    final rows = <Map<String, dynamic>>[];
    for (final report in reports) {
      if (report['unlinked'] == true) continue;
      final item = report['item'] as AggregatedGoodItem;
      final stockRows = List<Map<String, dynamic>>.from(
        report['stock_rows'] as List? ?? const [],
      );
      for (final row in stockRows) {
        final quantity = (row['allocated_quantity'] as num?)?.toDouble() ?? 0.0;
        if (quantity <= 0) continue;
        rows.add({
          'item_id': item.catalogItemId,
          'item_type': item.inventoryItemType,
          'color_id': item.colorId,
          'location_id': row['location_id'],
          'quantity': quantity,
        });
      }
    }
    return rows;
  }

  Future<void> _applyInventoryIssue(
    BuildContext context, {
    bool automatic = false,
  }) async {
    final lang = Provider.of<AppSettingsProvider>(
      context,
      listen: false,
    ).language;
    String t(String key) => Localization.translate(key, lang);
    final remnantIds = _usedRemnantIds();
    final stockDeductions = _stockDeductions();
    final missingRows = reports.where((report) {
      if (report['unlinked'] == true) return true;
      return ((report['missing'] as num?)?.toDouble() ?? 0) > 0.000001;
    }).toList();
    if (missingRows.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            t(
              'لا يمكن اعتماد الصرف قبل توفير كل النواقص. راجع تقرير النقص ثم سجّل الشراء أو الاستلام.',
            ),
          ),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    if (remnantIds.isEmpty && stockDeductions.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t('لا توجد كميات متاحة لاعتماد صرفها.'))),
      );
      return;
    }
    if (!automatic) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(t('اعتماد صرف المخزون')),
          content: Text(
            t(
              'سيتم خصم القطع الكاملة من المخزون وتغيير حالة الفضلات المستعملة إلى منتهية. لا يمكن اعتماد نفس الطلبية مرتين.',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(t('إلغاء')),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.pop(dialogContext, true),
              icon: const Icon(Icons.check_circle_outline),
              label: Text(t('اعتماد')),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    Map<String, dynamic> result;
    try {
      result = await db.applyOrderInventoryIssue(
        orderId: orderId,
        remnantIds: remnantIds,
        stockDeductions: stockDeductions,
        customerName: customerName,
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${t('تعذر اعتماد الصرف')}: $error'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    if (!context.mounted) return;
    final alreadyApplied = result['already_applied'] == true;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          alreadyApplied
              ? t('تم اعتماد صرف هذه الطلبية سابقاً.')
              : '${t('تم اعتماد الصرف')}: '
                    '${result['consumed_remnants'] ?? 0} ${t('فضلات')}، '
                    '${result['deducted_rows'] ?? 0} ${t('أسطر مخزون')}.',
        ),
        backgroundColor: alreadyApplied ? Colors.orange : Colors.green,
      ),
    );
    if ((automatic || widget.autoApply) && context.mounted) {
      Navigator.pop(context, true);
    }
  }

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
        actions: [
          TextButton.icon(
            onPressed: () => _applyInventoryIssue(context),
            icon: const Icon(Icons.inventory_2_outlined, color: Colors.white),
            label: Text(
              t('اعتماد الصرف'),
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 40),
        children: [
          Card(
            color: _isStockReserved
                ? Colors.green.withValues(alpha: 0.12)
                : Colors.grey.withValues(alpha: 0.08),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: BorderSide(
                color: _isStockReserved ? Colors.green.shade600 : Colors.grey.shade400,
                width: 1.5,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  Icon(
                    _isStockReserved ? Icons.check_circle : Icons.inventory_2_outlined,
                    color: _isStockReserved ? Colors.green.shade700 : Colors.grey.shade600,
                    size: 32,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              t('حالة حجز السلع بالمخزون:'),
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                              decoration: BoxDecoration(
                                color: _isStockReserved ? Colors.green.shade700 : Colors.grey.shade500,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    _isStockReserved ? Icons.check : Icons.lock_open,
                                    size: 13,
                                    color: Colors.white,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    _isStockReserved ? t('تم الحجز') : t('لم يُحجز بعد'),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 11.5,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _isStockReserved
                              ? t('تم حجز القطع والفواضل اللازمة لهذه الطلبية بالمخزون لمنع استهلاكها لطلبيات أخرى.')
                              : t('حجز السلع يربط القطع والفواضل المحددة بالطلبية ويضمن عدم استهلاكها لطلبيات أخرى.'),
                          style: TextStyle(fontSize: 11.5, color: Colors.grey.shade800),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: () => _toggleStockReservation(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _isStockReserved ? Colors.red.shade700 : Colors.green.shade700,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                    icon: Icon(_isStockReserved ? Icons.cancel_outlined : Icons.bookmark_add_outlined, size: 18),
                    label: Text(
                      _isStockReserved ? t('إلغاء الحجز') : t('حجز السلع للطلبية'),
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5),
                    ),
                  ),
                ],
              ),
            ),
          ),
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
