import 'dart:io';

void main() {
  String dirPath = 'lib/Commande/Systeme';
  String path = '\$dirPath/cutting_optimizer.dart';

  if (!Directory(dirPath).existsSync()) {
    Directory(dirPath).createSync(recursive: true);
  }

  String content = '''import 'dart:math';
import 'package:flutter/foundation.dart';
import 'cutting_calculator.dart';

/// يمثل قطعة صغيرة مقصوصة
class CutPiece {
  final double length;
  final String label;

  CutPiece({required this.length, required this.label});
}

/// يمثل بار ألمنيوم واحد (مثلاً 5.8 متر)
class BarCutPlan {
  final double initialLength;
  final double sawThickness;
  List<CutPiece> pieces = [];

  BarCutPlan({
    required this.initialLength,
    this.sawThickness = 4.0, // 4 mm by default
  });

  /// المساحة المشغولة (القطع + سمك المنشار لكل قصة)
  double get usedLength {
    if (pieces.isEmpty) return 0;
    double totalPieces = pieces.fold(0, (sum, p) => sum + p.length);
    double totalSawWaste = pieces.length * sawThickness;
    return totalPieces + totalSawWaste;
  }

  /// المساحة المتبقية من البار
  double get remainingLength {
    return initialLength - usedLength;
  }

  /// هل يمكن إدخال قطعة معينة في هذا البار؟
  bool canFit(double length) {
    // نحتاج أن نضيف سمك المنشار للقطعة لكي نتأكد من إمكانية قصها
    return remainingLength >= (length + sawThickness);
  }

  void addPiece(double length, String label) {
    if (canFit(length)) {
      pieces.add(CutPiece(length: length, label: label));
    }
  }
}

/// النتيجة النهائية لخطة التقطيع لكل نوع من البروفيلات
class ProfileCuttingResult {
  final String profileName;
  final List<BarCutPlan> bars;
  final double totalWaste;
  final double totalEfficiency;

  ProfileCuttingResult({
    required this.profileName,
    required this.bars,
    required this.totalWaste,
    required this.totalEfficiency,
  });
}

class CuttingOptimizer {
  /// يقوم بتحسين التقطيع باستخدام خوارزمية (Best Fit Decreasing)
  /// inputItems: قائمة القطع المراد تقطيعها من نفس النوع (مثلاً Dormant)
  /// barLength: طول البار القياسي بالمليمتر (مثلاً 5800 ملم = 5.8 متر)
  /// sawThickness: سمك شفرة المنشار بالمليمتر
  static ProfileCuttingResult optimizeProfile(
    String profileName,
    List<CuttingItem> inputItems, {
    double barLength = 5800.0,
    double sawThickness = 4.0,
  }) {
    List<CutPiece> allCuts = [];

    // تحويل الـ CuttingItem إلى قائمة مسطحة من الأطوال (بالمليمتر)
    for (var item in inputItems) {
      // نأخذ طول القطعة (نعتبره width أو height حسب ما هو مسجل، عادة نستخدم العرض كـ طول للبروفيل)
      double length = (item.width > 0 ? item.width : item.height) * 1000.0; // تحويل إلى ملم
      for (int i = 0; i < item.quantity; i++) {
        allCuts.add(CutPiece(length: length, label: item.name));
      }
    }

    // ترتيب القطع تنازلياً (من الأطول للأقصر) -> Decreasing
    allCuts.sort((a, b) => b.length.compareTo(a.length));

    List<BarCutPlan> bars = [];

    for (var piece in allCuts) {
      // نمنع قص قطعة أطول من البار أساساً
      if (piece.length + sawThickness > barLength) {
        debugPrint('تحذير: قطعة طويلة جداً (\${piece.length}) تتجاوز طول البار.');
        continue;
      }

      int bestBarIndex = -1;
      double minRemaining = double.infinity;

      // نبحث عن أفضل بار (Best Fit) يترك أقل مساحة متبقية
      for (int i = 0; i < bars.length; i++) {
        if (bars[i].canFit(piece.length)) {
          double spaceLeft = bars[i].remainingLength - (piece.length + sawThickness);
          if (spaceLeft < minRemaining) {
            minRemaining = spaceLeft;
            bestBarIndex = i;
          }
        }
      }

      // إذا وجدنا باراً مناسباً، نضع القطعة فيه
      if (bestBarIndex != -1) {
        bars[bestBarIndex].addPiece(piece.length, piece.label);
      } else {
        // إذا لم نجد، نفتح باراً جديداً
        var newBar = BarCutPlan(initialLength: barLength, sawThickness: sawThickness);
        newBar.addPiece(piece.length, piece.label);
        bars.add(newBar);
      }
    }

    double totalWaste = 0;
    double totalUsed = 0;
    for (var bar in bars) {
      totalWaste += bar.remainingLength;
      totalUsed += bar.usedLength;
    }

    double totalBarSpace = bars.length * barLength;
    double efficiency = totalBarSpace > 0 ? (totalUsed / totalBarSpace) * 100 : 0;

    return ProfileCuttingResult(
      profileName: profileName,
      bars: bars,
      totalWaste: totalWaste,
      totalEfficiency: efficiency,
    );
  }

  /// تجميع قائمة الـ CuttingItems إلى خطط تقطيع مبنية على الأنواع
  static List<ProfileCuttingResult> optimizeAll(
    List<CuttingItem> allItems, {
    double barLength = 5800.0,
    double sawThickness = 4.0,
  }) {
    // تصفية فقط عناصر الألمنيوم (الزجاج والإكسسوارات لا يتم تقطيعها بهذه الخوارزمية)
    var aluminumItems = allItems.where((i) =>
        i.type == CuttingItemType.profileFrame ||
        i.type == CuttingItemType.profileSash).toList();

    // تجميع العناصر حسب نوع البروفيل (الاسم)
    Map<String, List<CuttingItem>> groupedByName = {};
    for (var item in aluminumItems) {
      if (!groupedByName.containsKey(item.name)) {
        groupedByName[item.name] = [];
      }
      groupedByName[item.name]!.add(item);
    }

    List<ProfileCuttingResult> results = [];
    groupedByName.forEach((name, itemsList) {
      var result = optimizeProfile(name, itemsList, barLength: barLength, sawThickness: sawThickness);
      if (result.bars.isNotEmpty) {
        results.add(result);
      }
    });

    return results;
  }
}
''';

  File(path).writeAsStringSync(content);
  print("Created cutting_optimizer.dart");
}
