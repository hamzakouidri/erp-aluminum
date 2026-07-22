import 'dart:convert';
import 'package:database_data/Commande/Systeme/model.dart';
import 'package:database_data/Commande/Systeme/cutting_calculator.dart';
import 'package:database_data/Commande/Systeme/cutting_optimizer.dart';
import 'package:database_data/sql_database.dart';
import 'package:database_data/Commande/Systeme/model_serialization.dart';
import 'package:flutter/foundation.dart';

class ConsumptionReport {
  final List<CuttingItem> aluminumItems;
  final List<CuttingItem> glassItems;
  final List<CuttingItem> accessoryItems;

  // المؤشرات المالية الثلاثة (لوحة التحكم المالية)
  final double totalSellingPrice; // سعر البيع للزبون
  final double exactCost;         // التكلفة الصافية الدقيقة (مشاريع / شونطي)
  final double fullBarCost;       // التكلفة الإجمالية بفتح البارات (زبون فردي)
  final int totalScrewsCount;     // 🟢 إجمالي عدد البراغي المستهلكة في الطلبية

  ConsumptionReport({
    required this.aluminumItems,
    required this.glassItems,
    required this.accessoryItems,
    required this.totalSellingPrice,
    required this.exactCost,
    required this.fullBarCost,
    required this.totalScrewsCount,
  });
}

class ConsumptionManager {
  final SqlDatabase db;

  // سعر افتراضي للبرغي الواحد في حال لم يكن مسجلاً في قاعدة البيانات (مثلاً 2 دج للبرغي)
  static const double _defaultScrewCost = 2.0;
  static const double _defaultScrewSellingPrice = 3.0;

  // طول البار الافتراضي بالأمتار
  static const double _defaultBarLength = 5.8;

  ConsumptionManager(this.db);

  Future<ConsumptionReport> generateReport(int commandeId) async {
    final List<Map<String, dynamic>> details = await db.readCommandeDetails(commandeId);

    List<CuttingItem> allItems = [];

    double orderSellingPrice = 0.0;
    double orderExactCost = 0.0;
    double orderFullBarCost = 0.0;
    int orderTotalScrews = 0; // 🟢 عداد تراكمي للبراغي

    for (var detail in details) {
      if (detail['partitions_json'] != null && detail['partitions_json'].toString().isNotEmpty) {
        try {
          final Map<String, dynamic> data = jsonDecode(detail['partitions_json']);
          WindowModel window = WindowModel(db: db);
          applyWindowModelFromMap(window, data);

          int quantity = detail['quantite'] ?? 1;

          // 1. حساب القطع والإكسسوارات الديناميكية
          List<CuttingItem> windowItems = CuttingCalculator.calculate(window);
          List<CuttingItem> accessories = await _calculateAccessories(window);
          windowItems.addAll(accessories);

          // 2. جلب الأسعار الديناميكية من السلسلة النشطة بدلاً من القيم الثابتة
          double seriesSellingPricePerMeter = 0.0;
          double barCostPrice = 2000.0; // تكلفة شراء البار الكامل (قيمة افتراضية حذرة)

          if (window.activeSeries != null) {
            // جلب سعر بيع المتر المحدد في قاعدة البيانات لهذه السلسلة
            final dbClient = await db.db;
            final seriesRows = await dbClient!.query(
                'Series',
                columns: ['price_per_meter'],
                where: 'id = ?',
                whereArgs: [window.activeSeries!.id]
            );

            if (seriesRows.isNotEmpty) {
              seriesSellingPricePerMeter = (seriesRows.first['price_per_meter'] as num).toDouble();
            }
            // محاولة جلب السعر المخصص للون السلسلة إذا توفر
            if (window.selectedDbColor != null) {
              double customColorPrice = await db.getSeriesColorPrice(window.activeSeries!.id, window.selectedDbColor!['id']);
              if (customColorPrice > 0) {
                seriesSellingPricePerMeter = customColorPrice;
              }
            }
          }

          double costPerMeter = barCostPrice / _defaultBarLength;

          // جلب أسعار الزجاج من قاعدة البيانات بشكل ديناميكي إن وجد
          double glassSellingPricePerSqm = 3500.0;
          double glassCostPricePerSqm = 2800.0;
          final dbGlass = await db.readGlass();
          if (dbGlass.isNotEmpty) {
            // محاولة مطابقة نوع الزجاج
            var matchedGlass = dbGlass.first;
            glassCostPricePerSqm = (matchedGlass['price_per_sqm'] as num).toDouble();
            glassSellingPricePerSqm = glassCostPricePerSqm * 1.25; // هامش ربح 25% للزجاج
          }

          // 3. فصل وتصنيف القطع لحساب التكلفة والبراغي
          List<CuttingItem> aluItemsForThisWindow = [];

          for (var item in windowItems) {
            for (int i = 0; i < (item.quantity * quantity); i++) {
              CuttingItem singleItem = CuttingItem(
                name: item.name,
                description: item.description,
                width: item.width,
                height: item.height,
                quantity: 1,
                type: item.type,
                isMissing: item.isMissing,
              );

              if (item.type != CuttingItemType.accessory) {
                allItems.add(singleItem);
              }

              if (item.type == CuttingItemType.profileFrame || item.type == CuttingItemType.profileSash) {
                aluItemsForThisWindow.add(singleItem);

                double itemLengthInMeters = (item.width > 0 ? item.width : item.height) / 1000.0;
                orderSellingPrice += (itemLengthInMeters * seriesSellingPricePerMeter);
                orderExactCost += (itemLengthInMeters * costPerMeter);

              } else if (item.type == CuttingItemType.glass) {
                double sqm = (item.width / 1000.0) * (item.height / 1000.0);
                orderSellingPrice += (sqm * glassSellingPricePerSqm);
                orderExactCost += (sqm * glassCostPricePerSqm);
                orderFullBarCost += (sqm * glassCostPricePerSqm);

              } else if (item.type == CuttingItemType.accessory) {
                // استخراج البيانات المتقدمة من حقل الوصف المطور
                double accCost = _extractPriceFromDescription(item.description);
                int screwCountPerUnit = _extractScrewsFromDescription(item.description);

                // إضافة الإكسسوار الأصلي بدون حشو حقل السعر في القائمة النهائية
                allItems.add(CuttingItem(
                  name: item.name,
                  description: "المادة: ${item.description.split('|').first}",
                  width: item.width,
                  height: item.height,
                  quantity: 1,
                  type: item.type,
                  isMissing: item.isMissing,
                ));

                double accSelling = accCost * 1.3; // هامش ربح الإكسسوارات 30%

                orderSellingPrice += accSelling;
                orderExactCost += accCost;
                orderFullBarCost += accCost;

                // 🟢 حساب البراغي التراكمية المستهلكة لهذا الإكسسوار
                orderTotalScrews += screwCountPerUnit;
              }
            }
          }

          // 4. تشغيل خوارزمية التقطيع في الخلفية لمعرفة عدد البارات الحقيقية للورشة
          List<ProfileCuttingResult> optimizedBars = CuttingOptimizer.optimizeAll(aluItemsForThisWindow);
          int totalBarsNeeded = 0;
          for(var result in optimizedBars) {
            totalBarsNeeded += result.bars.length;
          }

          orderFullBarCost += (totalBarsNeeded * barCostPrice);

        } catch (e) {
          debugPrint('Error parsing window model for consumption: $e');
        }
      }
    }

    // 🟢 5. دمج كتل البراغي المستهلكة كعنصر مادي حقيقي في التقرير لحساب تكلفته وسعره
    if (orderTotalScrews > 0) {
      double screwsCost = orderTotalScrews * _defaultScrewCost;
      double screwsSelling = orderTotalScrews * _defaultScrewSellingPrice;

      orderExactCost += screwsCost;
      orderFullBarCost += screwsCost;
      orderSellingPrice += screwsSelling;

      allItems.add(CuttingItem(
        name: "براغي تثبيت وتجميع وتثبيت الكتالوج الصافي",
        description: "إجمالي استهلاك البراغي المخصصة للتركيب",
        width: 0,
        height: 0,
        quantity: orderTotalScrews,
        type: CuttingItemType.accessory,
        isMissing: false,
      ));
    }

    // 6. تجميع القطع المتشابهة لعرضها بشكل نظيف في القوائم
    List<CuttingItem> aggregated = _aggregateItems(allItems);

    return ConsumptionReport(
      aluminumItems: aggregated.where((i) => i.type == CuttingItemType.profileFrame || i.type == CuttingItemType.profileSash).toList(),
      glassItems: aggregated.where((i) => i.type == CuttingItemType.glass).toList(),
      accessoryItems: aggregated.where((i) => i.type == CuttingItemType.accessory).toList(),
      totalSellingPrice: orderSellingPrice,
      exactCost: orderExactCost,
      fullBarCost: orderFullBarCost,
      totalScrewsCount: orderTotalScrews, // إرجاع إجمالي عدد البراغي المستهلكة
    );
  }
  // 🟢 دالة جديدة تماماً لحساب التكلفة الفورية من الرسم مباشرة دون الحاجة لـ ID الطلبية
  Future<ConsumptionReport> generateReportFromLiveModel(WindowModel window, int quantity) async {
    List<CuttingItem> allItems = [];
    double orderSellingPrice = 0.0;
    double orderExactCost = 0.0;
    double orderFullBarCost = 0.0;
    int orderTotalScrews = 0;

    try {
      // 1. حساب القطع والإكسسوارات من الرسم مباشرة
      List<CuttingItem> windowItems = CuttingCalculator.calculate(window);
      List<CuttingItem> accessories = await _calculateAccessories(window);
      windowItems.addAll(accessories);

      // 2. جلب سعر السلسلة النشطة
      double seriesSellingPricePerMeter = 0.0;
      double barCostPrice = 2000.0; // تكلفة افتراضية للبار الكامل للورشة

      if (window.activeSeries != null) {
        final dbClient = await db.db;
        final seriesRows = await dbClient!.query(
            'Series',
            columns: ['price_per_meter'],
            where: 'id = ?',
            whereArgs: [window.activeSeries!.id]
        );
        if (seriesRows.isNotEmpty) {
          seriesSellingPricePerMeter = (seriesRows.first['price_per_meter'] as num).toDouble();
        }
      }

      double costPerMeter = barCostPrice / 5.8;
      double glassSellingPricePerSqm = 3500.0;
      double glassCostPricePerSqm = 2800.0;

      List<CuttingItem> aluItemsForThisWindow = [];

      for (var item in windowItems) {
        for (int i = 0; i < (item.quantity * quantity); i++) {
          CuttingItem singleItem = CuttingItem(
            name: item.name,
            description: item.description,
            width: item.width,
            height: item.height,
            quantity: 1,
            type: item.type,
            isMissing: item.isMissing,
          );

          if (item.type != CuttingItemType.accessory) {
            allItems.add(singleItem);
          }

          if (item.type == CuttingItemType.profileFrame || item.type == CuttingItemType.profileSash) {
            aluItemsForThisWindow.add(singleItem);
            double itemLengthInMeters = (item.width > 0 ? item.width : item.height) / 1000.0;
            orderSellingPrice += (itemLengthInMeters * seriesSellingPricePerMeter);
            orderExactCost += (itemLengthInMeters * costPerMeter);
          } else if (item.type == CuttingItemType.glass) {
            double sqm = (item.width / 1000.0) * (item.height / 1000.0);
            orderSellingPrice += (sqm * glassSellingPricePerSqm);
            orderExactCost += (sqm * glassCostPricePerSqm);
            orderFullBarCost += (sqm * glassCostPricePerSqm);
          } else if (item.type == CuttingItemType.accessory) {
            double accCost = _extractPriceFromDescription(item.description);
            int screwCountPerUnit = _extractScrewsFromDescription(item.description);

            allItems.add(CuttingItem(
              name: item.name,
              description: "المادة: ${item.description.split('|').first}",
              width: item.width,
              height: item.height,
              quantity: 1,
              type: item.type,
              isMissing: item.isMissing,
            ));

            orderSellingPrice += (accCost * 1.3);
            orderExactCost += accCost;
            orderFullBarCost += accCost;
            orderTotalScrews += screwCountPerUnit;
          }
        }
      }

      List<ProfileCuttingResult> optimizedBars = CuttingOptimizer.optimizeAll(aluItemsForThisWindow);
      int totalBarsNeeded = 0;
      for(var result in optimizedBars) {
        totalBarsNeeded += result.bars.length;
      }
      orderFullBarCost += (totalBarsNeeded * barCostPrice);

      if (orderTotalScrews > 0) {
        orderExactCost += (orderTotalScrews * 2.0);
        orderFullBarCost += (orderTotalScrews * 2.0);
        orderSellingPrice += (orderTotalScrews * 3.0);

        allItems.add(CuttingItem(
          name: "براغي التثبيت والتجميع الإجمالية",
          description: "استهلاك البراغي الفعلي",
          width: 0, height: 0, quantity: orderTotalScrews,
          type: CuttingItemType.accessory, isMissing: false,
        ));
      }
    } catch (e) {
      debugPrint("Error: $e");
    }

    List<CuttingItem> aggregated = _aggregateItems(allItems);
    return ConsumptionReport(
      aluminumItems: aggregated.where((i) => i.type == CuttingItemType.profileFrame || i.type == CuttingItemType.profileSash).toList(),
      glassItems: aggregated.where((i) => i.type == CuttingItemType.glass).toList(),
      accessoryItems: aggregated.where((i) => i.type == CuttingItemType.accessory).toList(),
      totalSellingPrice: orderSellingPrice,
      exactCost: orderExactCost,
      fullBarCost: orderFullBarCost,
      totalScrewsCount: orderTotalScrews,
    );
  }

  // 🟢 جلب وحساب الإكسسوارات ومطابقتها مع الجودة وعدد البراغي المحددة
  Future<List<CuttingItem>> _calculateAccessories(WindowModel model) async {
    List<CuttingItem> items = [];
    int totalHinges = 0;
    int totalHandles = 0;
    int totalFlushBolts = 0;

    for (var zone in model.zones) {
      if (zone.content == ZoneContent.singleSash) {
        totalHinges += 2;
        totalHandles += 1;
      } else if (zone.content == ZoneContent.doubleSash) {
        totalHinges += 4;
        totalHandles += 1;
        totalFlushBolts += 1;
      }
    }

    if (totalHinges == 0 && totalHandles == 0 && totalFlushBolts == 0) return items;

    int? currentSeriesId = model.activeSeries?.id;
    int? currentColorId = model.selectedDbColor?['id'];
    List<Map<String, dynamic>> dbAccessories = await db.getAccessoriesWithPrices(currentSeriesId, currentColorId);

    if (totalHinges > 0) {
      var data = _findAccessoryByType(dbAccessories, 'Paumelle');
      // 🟢 إذا لم يجد الإكسسوار، السعر صفر، والاسم يوضح أنه مفقود
      double price = data != null ? (data['final_price'] ?? 0.0) : 0.0;
      int screws = data != null ? (data['screw_count'] ?? 0) : 0;
      items.add(CuttingItem(
        name: data != null ? data['name'] : "⚠️ مفصلة (غير مسجلة بالقاعدة)",
        description: "Price:$price|Screws:$screws",
        width: 0, height: 0, quantity: totalHinges, type: CuttingItemType.accessory, isMissing: data == null,
      ));
    }

    if (totalHandles > 0) {
      var data = _findAccessoryByType(dbAccessories, 'Poignee');
      double price = data != null ? (data['final_price'] ?? 0.0) : 0.0;
      int screws = data != null ? (data['screw_count'] ?? 0) : 0;
      items.add(CuttingItem(
        name: data != null ? data['name'] : "⚠️ مقبض (غير مسجل بالقاعدة)",
        description: "Price:$price|Screws:$screws",
        width: 0, height: 0, quantity: totalHandles, type: CuttingItemType.accessory, isMissing: data == null,
      ));
    }

    if (totalFlushBolts > 0) {
      var data = _findAccessoryByType(dbAccessories, 'Verrou');
      double price = data != null ? (data['final_price'] ?? 0.0) : 0.0;
      int screws = data != null ? (data['screw_count'] ?? 0) : 0;
      items.add(CuttingItem(
        name: data != null ? data['name'] : "⚠️ ترباس (غير مسجل بالقاعدة)",
        description: "Price:$price|Screws:$screws",
        width: 0, height: 0, quantity: totalFlushBolts, type: CuttingItemType.accessory, isMissing: data == null,
      ));
    }

    return items;
  }

  Map<String, dynamic>? _findAccessoryByType(List<Map<String, dynamic>> accessories, String type) {
    try {
      return accessories.firstWhere((acc) => acc['type'].toString().toLowerCase().contains(type.toLowerCase()));
    } catch (_) { return null; }
  }

  // دالة مساعدة مطورة لاستخراج السعر الفعلي من السلسلة النصية للوصف
  double _extractPriceFromDescription(String description) {
    if (description.contains("Price:")) {
      try {
        String segment = description.split("Price:").last;
        String priceStr = segment.contains("|") ? segment.split("|").first : segment;
        return double.tryParse(priceStr.trim()) ?? 0.0;
      } catch (_) {
        return 0.0;
      }
    }
    return 0.0;
  }

  // 🟢 دالة مساعدة جديدة لاستخراج عدد البراغي الفعلي لكل قطعة إكسسوار
  int _extractScrewsFromDescription(String description) {
    if (description.contains("Screws:")) {
      try {
        String screwsStr = description.split("Screws:").last.trim();
        return int.tryParse(screwsStr) ?? 0;
      } catch (_) {
        return 0;
      }
    }
    return 0;
  }

  List<CuttingItem> _aggregateItems(List<CuttingItem> items) {
    Map<String, CuttingItem> map = {};
    for (var item in items) {
      String key = '${item.name}_${item.width.toStringAsFixed(1)}_${item.height.toStringAsFixed(1)}';
      if (map.containsKey(key)) {
        var existing = map[key]!;
        map[key] = CuttingItem(
          name: existing.name,
          description: existing.description,
          width: existing.width,
          height: existing.height,
          quantity: existing.quantity + item.quantity,
          type: existing.type,
          isMissing: existing.isMissing,
        );
      } else {
        map[key] = item;
      }
    }
    return map.values.toList();
  }
}
