import 'dart:convert';
import 'dart:math' as math;

import '../Commande/Systeme/calculate_component.dart';
import '../Commande/Systeme/model.dart';
import '../Commande/Systeme/model_serialization.dart';
import '../sql_database.dart';

/// يمثل قطعة واحدة مطلوبة للتقطيع من اللوح
class SheetDemandPiece {
  final String id;
  final int orderId;
  final String orderName;
  final String windowName;
  final String materialType; // 'resine', 'alucobond', 'panneau_sandwich', 'plexyglass', 'glass'
  final String color;
  final double lengthMm;
  final double widthMm;
  final bool allowRotation;
  final int count;

  const SheetDemandPiece({
    required this.id,
    required this.orderId,
    this.orderName = '',
    required this.windowName,
    required this.materialType,
    this.color = '',
    required this.lengthMm,
    required this.widthMm,
    this.allowRotation = true,
    this.count = 1,
  });

  double get areaSqm => (lengthMm * widthMm) / 1000000.0;
  String get groupKey => '${materialType.trim().toLowerCase()}__${color.trim().toLowerCase()}';
}

/// يمثل موقع وضع القطعة داخل اللوح بعد الحساب
class PlacedSheetCut {
  final SheetDemandPiece piece;
  final double x;
  final double y;
  final double cutWidth;
  final double cutLength;
  final bool isRotated;

  const PlacedSheetCut({
    required this.piece,
    required this.x,
    required this.y,
    required this.cutWidth,
    required this.cutLength,
    required this.isRotated,
  });

  double get areaSqm => (cutWidth * cutLength) / 1000000.0;
}

/// يمثل مساحة فارغة أو فضلة داخل اللوح
class SheetFreeRect {
  double x;
  double y;
  double width;
  double length;

  SheetFreeRect({
    required this.x,
    required this.y,
    required this.width,
    required this.length,
  });

  double get areaSqm => (width * length) / 1000000.0;
}

/// لوح كامل (جديد أو فضلة سابقة) مع توزيع القطع والفضلات الناتجة
class OptimizedSheet {
  final int sheetIndex;
  final String materialType;
  final String color;
  final String sheetName;
  final double sheetLengthMm;
  final double sheetWidthMm;
  final bool isFromRemnant;
  final int? sourceRemnantId;
  final String? sourceRemnantTicket;
  final List<PlacedSheetCut> cuts;
  final List<SheetFreeRect> usableRemnants;
  final double kerfMm;

  const OptimizedSheet({
    required this.sheetIndex,
    required this.materialType,
    required this.color,
    required this.sheetName,
    required this.sheetLengthMm,
    required this.sheetWidthMm,
    this.isFromRemnant = false,
    this.sourceRemnantId,
    this.sourceRemnantTicket,
    required this.cuts,
    required this.usableRemnants,
    this.kerfMm = 3.0,
  });

  double get totalSheetAreaSqm => (sheetLengthMm * sheetWidthMm) / 1000000.0;

  double get usedAreaSqm =>
      cuts.fold<double>(0.0, (sum, cut) => sum + cut.areaSqm);

  double get usableRemnantsAreaSqm =>
      usableRemnants.fold<double>(0.0, (sum, rem) => sum + rem.areaSqm);

  double get wasteAreaSqm =>
      math.max(0.0, totalSheetAreaSqm - usedAreaSqm - usableRemnantsAreaSqm);

  double get efficiencyPercentage =>
      totalSheetAreaSqm > 0 ? (usedAreaSqm / totalSheetAreaSqm) * 100.0 : 0.0;

  double get wastePercentage =>
      totalSheetAreaSqm > 0 ? (wasteAreaSqm / totalSheetAreaSqm) * 100.0 : 0.0;
}

/// تقرير التقطيع الإجمالي لمادة ولون معينين
class SheetOptimizationGroupReport {
  final String materialType;
  final String color;
  final List<OptimizedSheet> sheets;
  final int requiredPiecesCount;
  final int placedPiecesCount;

  const SheetOptimizationGroupReport({
    required this.materialType,
    required this.color,
    required this.sheets,
    required this.requiredPiecesCount,
    required this.placedPiecesCount,
  });

  int get newSheetsUsedCount => sheets.where((s) => !s.isFromRemnant).length;
  int get remnantsUsedCount => sheets.where((s) => s.isFromRemnant).length;
  int get newRemnantsGeneratedCount =>
      sheets.fold<int>(0, (sum, s) => sum + s.usableRemnants.length);

  double get totalSheetAreaSqm =>
      sheets.fold<double>(0.0, (sum, s) => sum + s.totalSheetAreaSqm);

  double get totalUsedAreaSqm =>
      sheets.fold<double>(0.0, (sum, s) => sum + s.usedAreaSqm);

  double get totalWasteAreaSqm =>
      sheets.fold<double>(0.0, (sum, s) => sum + s.wasteAreaSqm);

  double get overallEfficiencyPercentage =>
      totalSheetAreaSqm > 0 ? (totalUsedAreaSqm / totalSheetAreaSqm) * 100.0 : 0.0;
}

/// تقرير متكامل لجميع المجموعات
class SheetOptimizationFullReport {
  final Map<String, SheetOptimizationGroupReport> groups;

  const SheetOptimizationFullReport({required this.groups});

  int get totalNewSheets =>
      groups.values.fold<int>(0, (sum, g) => sum + g.newSheetsUsedCount);

  int get totalRemnantsUsed =>
      groups.values.fold<int>(0, (sum, g) => sum + g.remnantsUsedCount);

  int get totalNewRemnants =>
      groups.values.fold<int>(0, (sum, g) => sum + g.newRemnantsGeneratedCount);

  double get totalUsedAreaSqm =>
      groups.values.fold<double>(0.0, (sum, g) => sum + g.totalUsedAreaSqm);

  double get totalWasteAreaSqm =>
      groups.values.fold<double>(0.0, (sum, g) => sum + g.totalWasteAreaSqm);
}

/// محرك خوارزمية التقطيع ثنائي الأبعاد للألواح والصفائح (2D Guillotine Sheet Cutter)
class SheetCuttingOptimizerEngine {
  /// سمك شفرة القص الافتراضية بالملم
  static const double defaultSawKerfMm = 3.0;

  /// الحد الأدنى لاعتبار الفضلة صالحة للتخزين وإعادة الاستعمال
  static const double minRemnantWidthMm = 250.0;
  static const double minRemnantLengthMm = 300.0;

  /// تنفيذ عملية التحسين على مجموعة من القطع المطلوبة
  static SheetOptimizationFullReport optimize({
    required List<SheetDemandPiece> demandPieces,
    required List<Map<String, dynamic>> availableStandardSheets,
    List<Map<String, dynamic>> availableRemnants = const [],
    double sawKerfMm = defaultSawKerfMm,
    double minRemnantDimMm = 250.0,
  }) {
    // 1. فرز القطع حسب (المادة + اللون)
    final groupedPieces = <String, List<SheetDemandPiece>>{};
    for (final p in demandPieces) {
      groupedPieces.putIfAbsent(p.groupKey, () => []).add(p);
    }

    final groupReports = <String, SheetOptimizationGroupReport>{};

    for (final entry in groupedPieces.entries) {
      final key = entry.key;
      final piecesInGroup = entry.value;
      if (piecesInGroup.isEmpty) continue;

      final materialType = piecesInGroup.first.materialType;
      final color = piecesInGroup.first.color;

      // توسيع القطع حسب العدد (Quantity expansion)
      final flatPieces = <SheetDemandPiece>[];
      for (final p in piecesInGroup) {
        for (var i = 0; i < p.count; i++) {
          flatPieces.add(p);
        }
      }

      // فرز القطع تنازلياً حسب المساحة والأطول أولاً (MaxRects Decreasing)
      flatPieces.sort((a, b) {
        final cmpArea = b.areaSqm.compareTo(a.areaSqm);
        if (cmpArea != 0) return cmpArea;
        return math.max(b.lengthMm, b.widthMm).compareTo(math.max(a.lengthMm, a.widthMm));
      });

      // ترشيح الفضلات المتاحة المتوافقة مع هذا النوع واللون
      final matchingRemnants = availableRemnants.where((r) {
        final rType = r['material_type']?.toString().toLowerCase() ?? '';
        final rColor = r['color_name']?.toString().toLowerCase() ?? '';
        final matchesType = rType.isEmpty || rType == materialType.toLowerCase();
        final matchesColor = color.isEmpty || rColor.isEmpty || rColor == color.toLowerCase();
        final width = (r['width_mm'] as num?)?.toDouble() ?? 0.0;
        final length = (r['length_mm'] as num?)?.toDouble() ?? 0.0;
        return matchesType && matchesColor && width > minRemnantDimMm && length > minRemnantDimMm;
      }).toList();

      // ترشيح الألواح القياسية المتوافقة مع هذا النوع
      final matchingStandards = availableStandardSheets.where((s) {
        final sType = s['material_type']?.toString().toLowerCase() ?? '';
        return sType == materialType.toLowerCase();
      }).toList();

      final standardLength = matchingStandards.isNotEmpty
          ? (matchingStandards.first['length_mm'] as num).toDouble()
          : 2800.0;
      final standardWidth = matchingStandards.isNotEmpty
          ? (matchingStandards.first['width_mm'] as num).toDouble()
          : 1300.0;
      final standardName = matchingStandards.isNotEmpty
          ? matchingStandards.first['name']?.toString() ?? 'لوح قياسي'
          : 'لوح قياسي ($standardLength × $standardWidth مم)';
      final standardAllowRotation = matchingStandards.isNotEmpty
          ? ((matchingStandards.first['allow_rotation'] as num?)?.toInt() ?? 1) == 1
          : true;

      // ── البدء في تقطيع المجموعة ──
      final optimizedSheets = <OptimizedSheet>[];
      final unplacedPieces = List<SheetDemandPiece>.from(flatPieces);
      int sheetIndexCounter = 1;

      // أ) الأولوية القصوى: تجربة استغلال فضلات الورشة القديمة أولاً
      for (final rem in matchingRemnants) {
        if (unplacedPieces.isEmpty) break;

        final remLength = (rem['length_mm'] as num).toDouble();
        final remWidth = (rem['width_mm'] as num).toDouble();
        final remAllowRotation = ((rem['allow_rotation'] as num?)?.toInt() ?? 1) == 1;

        final packResult = _packPiecesIntoSheet(
          sheetLength: remLength,
          sheetWidth: remWidth,
          allowGlobalRotation: remAllowRotation,
          pieces: unplacedPieces,
          kerfMm: sawKerfMm,
          minRemnantDimMm: minRemnantDimMm,
        );

        if (packResult.placedCuts.isNotEmpty) {
          optimizedSheets.add(OptimizedSheet(
            sheetIndex: sheetIndexCounter++,
            materialType: materialType,
            color: color,
            sheetName: 'فضلة سابقة (${rem['ticket_code'] ?? 'Chute'})',
            sheetLengthMm: remLength,
            sheetWidthMm: remWidth,
            isFromRemnant: true,
            sourceRemnantId: rem['id'] as int?,
            sourceRemnantTicket: rem['ticket_code']?.toString(),
            cuts: packResult.placedCuts,
            usableRemnants: packResult.usableRemnants,
            kerfMm: sawKerfMm,
          ));

          // حذف القطع التي تم وضعها بنجاح
          for (final placed in packResult.placedCuts) {
            unplacedPieces.remove(placed.piece);
          }
        }
      }

      // ب) تقطيع الألواح الكاملة الجديدة للقطع المتبقية
      while (unplacedPieces.isNotEmpty) {
        final packResult = _packPiecesIntoSheet(
          sheetLength: standardLength,
          sheetWidth: standardWidth,
          allowGlobalRotation: standardAllowRotation,
          pieces: unplacedPieces,
          kerfMm: sawKerfMm,
          minRemnantDimMm: minRemnantDimMm,
        );

        if (packResult.placedCuts.isEmpty) {
          // قطعة واحدة أكبر من أبعاد اللوح بالكامل! نضعها كتنبيه ونخرج لتفادي التكرار اللانهائي
          break;
        }

        optimizedSheets.add(OptimizedSheet(
          sheetIndex: sheetIndexCounter++,
          materialType: materialType,
          color: color,
          sheetName: '$standardName #${optimizedSheets.where((s) => !s.isFromRemnant).length + 1}',
          sheetLengthMm: standardLength,
          sheetWidthMm: standardWidth,
          isFromRemnant: false,
          cuts: packResult.placedCuts,
          usableRemnants: packResult.usableRemnants,
          kerfMm: sawKerfMm,
        ));

        for (final placed in packResult.placedCuts) {
          unplacedPieces.remove(placed.piece);
        }
      }

      groupReports[key] = SheetOptimizationGroupReport(
        materialType: materialType,
        color: color,
        sheets: optimizedSheets,
        requiredPiecesCount: flatPieces.length,
        placedPiecesCount: flatPieces.length - unplacedPieces.length,
      );
    }

    return SheetOptimizationFullReport(groups: groupReports);
  }

  /// خوارزمية جيلوتين ثنائية الأبعاد (2D Guillotine Cut with Best-Fit-Area) للوح واحد
  static _SheetPackResult _packPiecesIntoSheet({
    required double sheetLength,
    required double sheetWidth,
    required bool allowGlobalRotation,
    required List<SheetDemandPiece> pieces,
    required double kerfMm,
    required double minRemnantDimMm,
  }) {
    final placedCuts = <PlacedSheetCut>[];
    final freeRects = <SheetFreeRect>[
      SheetFreeRect(x: 0, y: 0, width: sheetWidth, length: sheetLength),
    ];

    final remainingPieces = List<SheetDemandPiece>.from(pieces);

    for (final piece in pieces) {
      // البحث عن أفضل مستطيل متاح لوضع هذه القطعة (Best Area Fit)
      int bestRectIndex = -1;
      bool bestRotate = false;
      double bestFitScore = double.infinity;

      for (var rIdx = 0; rIdx < freeRects.length; rIdx++) {
        final rect = freeRects[rIdx];

        // 1. فحص الاتجاه الأصلي: (width <= rect.width && length <= rect.length)
        if (piece.widthMm <= rect.width && piece.lengthMm <= rect.length) {
          final score = (rect.width * rect.length) - (piece.widthMm * piece.lengthMm);
          if (score < bestFitScore) {
            bestFitScore = score;
            bestRectIndex = rIdx;
            bestRotate = false;
          }
        }

        // 2. فحص الاتجاه المعكوس مع التدوير 90 درجة (إن كان مسموحاً للمادة وللقطعة)
        final canRotate = allowGlobalRotation && piece.allowRotation;
        if (canRotate && piece.lengthMm <= rect.width && piece.widthMm <= rect.length) {
          final score = (rect.width * rect.length) - (piece.lengthMm * piece.widthMm);
          if (score < bestFitScore) {
            bestFitScore = score;
            bestRectIndex = rIdx;
            bestRotate = true;
          }
        }
      }

      if (bestRectIndex >= 0) {
        final targetRect = freeRects.removeAt(bestRectIndex);
        final placedW = bestRotate ? piece.lengthMm : piece.widthMm;
        final placedL = bestRotate ? piece.widthMm : piece.lengthMm;

        placedCuts.add(PlacedSheetCut(
          piece: piece,
          x: targetRect.x,
          y: targetRect.y,
          cutWidth: placedW,
          cutLength: placedL,
          isRotated: bestRotate,
        ));

        // تقسيم المستطيل المتبقي بطريقة Guillotine (Short-Axis Split)
        final remW = targetRect.width - placedW - kerfMm;
        final remL = targetRect.length - placedL - kerfMm;

        if (remW > 0 && remL > 0) {
          // خيار القص الأقصر لتقليل تشتت الفضلات
          if (remW > remL) {
            freeRects.add(SheetFreeRect(
              x: targetRect.x + placedW + kerfMm,
              y: targetRect.y,
              width: remW,
              length: targetRect.length,
            ));
            freeRects.add(SheetFreeRect(
              x: targetRect.x,
              y: targetRect.y + placedL + kerfMm,
              width: placedW,
              length: remL,
            ));
          } else {
            freeRects.add(SheetFreeRect(
              x: targetRect.x,
              y: targetRect.y + placedL + kerfMm,
              width: targetRect.width,
              length: remL,
            ));
            freeRects.add(SheetFreeRect(
              x: targetRect.x + placedW + kerfMm,
              y: targetRect.y,
              width: remW,
              length: placedL,
            ));
          }
        } else if (remW > 0) {
          freeRects.add(SheetFreeRect(
            x: targetRect.x + placedW + kerfMm,
            y: targetRect.y,
            width: remW,
            length: targetRect.length,
          ));
        } else if (remL > 0) {
          freeRects.add(SheetFreeRect(
            x: targetRect.x,
            y: targetRect.y + placedL + kerfMm,
            width: targetRect.width,
            length: remL,
          ));
        }

        remainingPieces.remove(piece);
      }
    }

    // فرز الفضلات الصالحة للاستعمال (التي تتجاوز الحد الأدنى)
    final usableRemnants = freeRects.where((r) {
      return (r.width >= minRemnantDimMm && r.length >= minRemnantDimMm) ||
             (r.width * r.length >= minRemnantDimMm * minRemnantDimMm * 1.5);
    }).toList();

    return _SheetPackResult(
      placedCuts: placedCuts,
      usableRemnants: usableRemnants,
    );
  }

  /// استخراج قطع الألواح والصفائح المطلوبة من تفاصيل الطلبيات
  static List<SheetDemandPiece> extractPiecesFromOrderDetails({
    required List<Map<String, dynamic>> orderDetails,
    required SqlDatabase db,
    bool includeGlass = false,
  }) {
    final pieces = <SheetDemandPiece>[];

    for (final detail in orderDetails) {
      final rawJson = detail['partitions_json']?.toString() ?? '';
      if (rawJson.trim().isEmpty) continue;

      try {
        final data = jsonDecode(rawJson);
        if (data is! Map) continue;

        final window = WindowModel(db: db);
        applyWindowModelFromMap(window, Map<String, dynamic>.from(data));

        final rawQty = detail['quantity'] ?? detail['quantite'] ?? 1;
        final quantity = (rawQty is num ? rawQty.toInt() : int.tryParse('$rawQty') ?? 1).clamp(1, 1000);
        final detailId = (detail['id'] as num?)?.toInt() ?? 0;
        final windowName = detail['window_type'] ?? detail['type'] ?? 'عنصر $detailId';
        final orderId = (detail['commande_id'] as num?)?.toInt() ?? 0;

        final bom = ComponentCalculator.generateBom(window, const {});

        for (final item in bom) {
          if (!item.isActive) continue;
          final cat = item.category.toLowerCase();

          // 1. فحص ألواح البانو والريزين والأليكوبوند
          if (cat == 'panneau') {
            final nameLower = item.name.toLowerCase();

            // استبعاد بانو ديكوراتيف (قطعة واحدة) والبرداج (مقاطع)
            if (nameLower.contains('decor') || nameLower.contains('ديكور')) continue;
            if (nameLower.contains('bardage') || nameLower.contains('برداج') || nameLower.contains('بارداج')) continue;

            String matType = 'panneau_sandwich';
            if (nameLower.contains('resine') || nameLower.contains('ريزين')) {
              matType = 'resine';
            } else if (nameLower.contains('alucobond') || nameLower.contains('أليكوبوند') || nameLower.contains('اليكوبوند')) {
              matType = 'alucobond';
            } else if (nameLower.contains('plexy') || nameLower.contains('بيكسي')) {
              matType = 'plexyglass';
            }

            final w = item.length ?? 0.0;
            final h = item.glassHeight ?? 0.0;
            if (w > 0 && h > 0) {
              pieces.add(SheetDemandPiece(
                id: '${detailId}_pan_${w.round()}_${h.round()}',
                orderId: orderId,
                windowName: windowName,
                materialType: matType,
                color: item.colorName ?? '',
                lengthMm: math.max(w, h),
                widthMm: math.min(w, h),
                count: quantity,
              ));
            }
          }

          // 2. فحص الزجاج إذا اختار المستخدم تقطيعه في الورشة
          if (includeGlass && cat == 'glass') {
            final w = item.length ?? 0.0;
            final h = item.glassHeight ?? 0.0;
            if (w > 0 && h > 0) {
              pieces.add(SheetDemandPiece(
                id: '${detailId}_glass_${w.round()}_${h.round()}',
                orderId: orderId,
                windowName: windowName,
                materialType: 'glass',
                color: '${item.name} ${item.colorName ?? ''}'.trim(),
                lengthMm: math.max(w, h),
                widthMm: math.min(w, h),
                count: quantity,
              ));
            }
          }
        }
      } catch (e) {
        // تخطي أي عنصر به خطأ تنسيق
      }
    }

    return pieces;
  }
}

class _SheetPackResult {
  final List<PlacedSheetCut> placedCuts;
  final List<SheetFreeRect> usableRemnants;

  const _SheetPackResult({
    required this.placedCuts,
    required this.usableRemnants,
  });
}
