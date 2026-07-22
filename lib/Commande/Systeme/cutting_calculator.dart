import 'package:database_data/Commande/Systeme/model.dart';

enum CuttingItemType {
  glass,
  profileFrame, // إطار خارجي (Dormant)
  profileSash, // ضلفة (Ouvrant)
  shutter, // ستارة
  accessory, // إكسسوار (مواد)
  batmo, // باتمو
  parclose, // بيركلوز
}

class CuttingItem {
  final String name;
  final String description;
  final double width;
  final double height;
  final int quantity;
  final CuttingItemType type;
  bool isMissing;
  final double price; // 🟢 إضافة حقل السعر الفردي للقطعة أو المتر

  CuttingItem({
    required this.name,
    required this.description,
    required this.width,
    required this.height,
    required this.quantity,
    required this.type,
    this.isMissing = true,
    this.price = 0.0, // 🟢 قيمة افتراضية صفر
  });

  // 🟢 دالة مساعدة لحساب إجمالي تكلفة هذه المجموعة من القطع
  double get totalPrice => price * quantity;
}

class CuttingCalculator {
  /// توليد قائمة تقطيع لنموذج النافذة (حالياً مخصص لنظام الفتح Frappe سلسلة 60 / Prolex)
  static List<CuttingItem> calculate(WindowModel model) {
    List<CuttingItem> items = [];

    // استخراج المتغيرات الأساسية للتقطيع
    bool is103 = !model.isFrame140;
    double dormantThickness = model.getSectionThickness('frame', fallback: 60.0);
    
    double frameCutWidth = model.width;
    double frameCutHeight = model.height;

    if (is103) {
      // 103 Series (Applique) - إضافة عرض البروفيل والتلحيم
      frameCutWidth += (dormantThickness * 2);
      frameCutHeight += (dormantThickness * (model.hasBottomFrame ? 2 : 1));
      frameCutWidth += 5.0; // 5 ملم للتلحيم
      frameCutHeight += 5.0; // 5 ملم للتلحيم
    } else {
      // 140 Series (Monobloc)
      if (model.hasShutter) {
        frameCutHeight -= model.shutterBoxHeight; // خصم صندوق الستار
        if (model.selectedSideCover != null) {
          // إذا كان الغطاء 35ملم نخصم 0.5سم (5ملم)، وإلا (60ملم فأكثر) نخصم 1.5سم (15ملم)
          double visibleW = model.selectedSideCover!.couvreJointWidth;
          double sideCoverDeduction = (visibleW <= 35) ? 5.0 : 15.0;
          frameCutHeight -= sideCoverDeduction;
          
          // إضافة الغطاء الجانبي كقطعة إضافية للقص
          items.add(CuttingItem(
            name: "الغطاء الجانبي (Couvre Joint)",
            description: "غطاء الإطار 140 (ظاهر ${visibleW}ملم)",
            width: model.height - model.shutterBoxHeight, // طوله عادة من تحت الصندوق لأسفل النافذة
            height: 0,
            quantity: 2, // يمين ويسار
            type: CuttingItemType.profileFrame,
          ));
        }
      }
      frameCutWidth += 5.0; // 5 ملم للتلحيم
      frameCutHeight += 5.0; // 5 ملم للتلحيم
    }

    // 1. حسابات الألمنيوم - الإطار الخارجي (Dormant)
    items.add(
      CuttingItem(
        name: "الإطار الخارجي الثابت (Dormant) - أفقي",
        description: "القطعة العلوية والسفلية من الإطار الخارجي",
        width: frameCutWidth,
        height: 0,
        quantity: model.hasBottomFrame ? 2 : 1, 
        type: CuttingItemType.profileFrame,
      ),
    );

    items.add(
      CuttingItem(
        name: "الإطار الخارجي الثابت (Dormant) - عمودي",
        description: "القطعة اليمنى واليسرى من الإطار الخارجي",
        width: frameCutHeight,
        height: 0,
        quantity: 2,
        type: CuttingItemType.profileFrame,
      ),
    );

    // 2. تحليل الدرف (Zones) للزجاج والألمنيوم (Ouvrant)
    // هنا نجلب عرض الإطار الخارجي (الـ Dormant) من قاعدة البيانات (إذا لم نجده نستخدم 45 مم افتراضياً)
    // العرض والارتفاع الداخلي: يتم حسابه بطرح عرض الإطار الخارجي من الجهتين
    double innerWidth = model.width - (dormantThickness * 2);
    double innerHeight =
        model.height - (dormantThickness * (model.hasBottomFrame ? 2 : 1));

    // هنا نمر على كل الفراغات لتقطيع الضلف والزجاج حسب نوع الفتح
    for (var zone in model.zones) {
      if (zone.content == ZoneContent.singleSash) {
        // --- ضلفة واحدة ---
        // هنا نقوم بحساب ألمنيوم الضلفة بزيادة تداخل الضلفة (Recouvrement)
        double sashOverlap = model.activeSeries!.sections.firstWhere((s) => s.type == 'sash', orElse: () => AluminumSection(id: 0, seriesId: 0, code: '', name: '', type: '', thickness: 0, glassDeduction: 0, weightPerMeter: 0)).sashOverlap;
        double sashWidth = innerWidth + sashOverlap;
        double sashHeight = innerHeight + sashOverlap;

        items.add(
          CuttingItem(
            name: "الضلفة المتحركة (Ouvrant) - أفقي",
            description: "ألمنيوم الضلفة (ضلفة واحدة)",
            width: sashWidth,
            height: 0,
            quantity: 2,
            type: CuttingItemType.profileSash,
          ),
        );
        items.add(
          CuttingItem(
            name: "الضلفة المتحركة (Ouvrant) - عمودي",
            description: "ألمنيوم الضلفة (ضلفة واحدة)",
            width: sashHeight,
            height: 0,
            quantity: 2,
            type: CuttingItemType.profileSash,
          ),
        );

        // هنا نحسب مقاسات الزجاج بخصم قيمة ألمنيوم الضلفة (تقريباً 194 مم للعرض)
        // وإذا كانت هناك ستارة (Shutter) نخصم مساحة صندوق الستارة (349 مم بدلاً من 194 مم).
        double glassWidth = model.width - 194.0;
        double glassHeight = model.height - (model.hasShutter ? 349.0 : 194.0);

        items.add(
          CuttingItem(
            name:
                "زجاج (${zone.glass.structure == GlassStructure.double ? 'مزدوج' : 'مفرد'})",
            description: "زجاج ضلفة واحدة",
            width: glassWidth,
            height: glassHeight,
            quantity: 1,
            type: CuttingItemType.glass,
          ),
        );

        // --- إضافة بيركلوز لضلفة واحدة ---
        double sashVisibleWidth = model.activeSeries!.sections.firstWhere((s) => s.type == 'sash', orElse: () => AluminumSection(id: 0, seriesId: 0, code: '', name: '', type: '', thickness: 0, glassDeduction: 0, weightPerMeter: 0)).visibleWidth;
        double parcloseWidth = sashWidth - 5.0 - (sashVisibleWidth * 2);
        double parcloseHeight = sashHeight - 5.0 - (sashVisibleWidth * 2);
        items.add(
          CuttingItem(
            name: "بيركلوز أفقي (Parclose)",
            description: "بيركلوز لضلفة واحدة",
            width: parcloseWidth,
            height: 0,
            quantity: 2,
            type: CuttingItemType.parclose,
          ),
        );
        items.add(
          CuttingItem(
            name: "بيركلوز عمودي (Parclose)",
            description: "بيركلوز لضلفة واحدة",
            width: parcloseHeight,
            height: 0,
            quantity: 2,
            type: CuttingItemType.parclose,
          ),
        );
      } else if (zone.content == ZoneContent.doubleSash) {
        // --- ضلفتين ---
        // هنا نقوم بتقسيم العرض الداخلي على 2 (للضلفتين)، مع إضافة التداخل.
        double sashOverlap = model.activeSeries!.sections.firstWhere((s) => s.type == 'sash', orElse: () => AluminumSection(id: 0, seriesId: 0, code: '', name: '', type: '', thickness: 0, glassDeduction: 0, weightPerMeter: 0)).sashOverlap;
        double sashWidth = (innerWidth + sashOverlap) / 2;
        double sashHeight = innerHeight + sashOverlap;

        items.add(
          CuttingItem(
            name: "الضلفة المتحركة (Ouvrant) - أفقي",
            description: "ألمنيوم الضلفة (ضلفتين)",
            width: sashWidth,
            height: 0,
            quantity: 4, // 2 لكل ضلفة
            type: CuttingItemType.profileSash,
          ),
        );
        items.add(
          CuttingItem(
            name: "الضلفة المتحركة (Ouvrant) - عمودي",
            description: "ألمنيوم الضلفة (ضلفتين)",
            width: sashHeight,
            height: 0,
            quantity: 4,
            type: CuttingItemType.profileSash,
          ),
        );

        // زجاج (القياس من الخارج): (العرض - 324) / 2
        double glassWidth = (model.width - 324.0) / 2;
        double glassHeight = model.height - (model.hasShutter ? 349.0 : 194.0);

        items.add(
          CuttingItem(
            name:
                "زجاج (${zone.glass.structure == GlassStructure.double ? 'مزدوج' : 'مفرد'})",
            description: "زجاج الضلفتين",
            width: glassWidth,
            height: glassHeight,
            quantity: 2, // 1 لكل ضلفة
            type: CuttingItemType.glass,
          ),
        );

        // --- إضافة الباتمو (Batmo) للنافذة ذات الضلفتين ---
        double batmoDeduction = model.activeSeries!.sections.firstWhere((s) => s.type == 'batmo', orElse: () => AluminumSection(id: 0, seriesId: 0, code: '', name: '', type: '', thickness: 0, glassDeduction: 0, weightPerMeter: 0, cuttingDeduction: 55.0)).cuttingDeduction;
        if (!model.hasBottomFrame) {
          batmoDeduction = batmoDeduction / 2;
        }
        double batmoHeight = innerHeight - batmoDeduction;
        items.add(
          CuttingItem(
            name: "باتمو (Batmo)",
            description: "باتمو النافذة ذات الضلفتين",
            width: batmoHeight,
            height: 0,
            quantity: 1,
            type: CuttingItemType.batmo,
          ),
        );

        // --- إضافة بيركلوز للضلفتين ---
        double sashVisibleWidth = model.activeSeries!.sections.firstWhere((s) => s.type == 'sash', orElse: () => AluminumSection(id: 0, seriesId: 0, code: '', name: '', type: '', thickness: 0, glassDeduction: 0, weightPerMeter: 0)).visibleWidth;
        double parcloseWidth = sashWidth - 5.0 - (sashVisibleWidth * 2);
        double parcloseHeight = sashHeight - 5.0 - (sashVisibleWidth * 2);
        items.add(
          CuttingItem(
            name: "بيركلوز أفقي (Parclose)",
            description: "بيركلوز للضلفتين",
            width: parcloseWidth,
            height: 0,
            quantity: 4, // 2 لكل ضلفة
            type: CuttingItemType.parclose,
          ),
        );
        items.add(
          CuttingItem(
            name: "بيركلوز عمودي (Parclose)",
            description: "بيركلوز للضلفتين",
            width: parcloseHeight,
            height: 0,
            quantity: 4, // 2 لكل ضلفة
            type: CuttingItemType.parclose,
          ),
        );
      }
    }

    return items;
  }
}
