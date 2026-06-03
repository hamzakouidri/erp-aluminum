import 'package:database_data/Commande/Systeme/model.dart';

enum CuttingItemType {
  glass,
  profileFrame, // إطار خارجي (Dormant)
  profileSash,  // درفة (Ouvrant)
  shutter,      // سيتار
  accessory,    // إكسسوار (Materiél)
}

class CuttingItem {
  final String name;
  final String description;
  final double width;
  final double height;
  final int quantity;
  final CuttingItemType type;

  CuttingItem({
    required this.name,
    required this.description,
    required this.width,
    required this.height,
    required this.quantity,
    required this.type,
  });
}

class CuttingCalculator {
  /// توليد قائمة تقطيع لنموذج النافذة (حالياً مخصص لنظام الفتح Frappe سلسلة 60 / Prolex)
  static List<CuttingItem> calculate(WindowModel model) {
    List<CuttingItem> items = [];

    // 1. حسابات الألمنيوم - الإطار الخارجي (Dormant)
    // الإطار الخارجي يُقص بنفس المقاسات الكلية للنافذة
    items.add(CuttingItem(
      name: "إطار خارجي (Dormant) - أفقي",
      description: "القطعة العلوية والسفلية من الإطار الخارجي",
      width: model.width,
      height: 0, // Profile width is the dimension we cut, height doesn't apply here for a linear profile length, but we can store it as length in `width` or `height`. Let's use `width` as the cut length.
      quantity: model.hasBottomFrame ? 2 : 1, // 2 if full frame, 1 if no bottom frame
      type: CuttingItemType.profileFrame,
    ));

    items.add(CuttingItem(
      name: "إطار خارجي (Dormant) - عمودي",
      description: "القطعة اليمنى واليسرى من الإطار الخارجي",
      width: model.height,
      height: 0,
      quantity: 2,
      type: CuttingItemType.profileFrame,
    ));

    // 2. تحليل الدرف (Zones) للزجاج والألمنيوم (Ouvrant)
    // عرض الإطار الخارجي الافتراضي للـ Frappe (الـ Dormant) - نفترض 45 ملم كمثال لحين ربطه بقاعدة البيانات
    double dormantThickness = 45.0; 
    
    // العرض والارتفاع الداخلي (داخل الإطار الخارجي)
    double innerWidth = model.width - (dormantThickness * 2);
    double innerHeight = model.height - (dormantThickness * (model.hasBottomFrame ? 2 : 1));

    for (var zone in model.zones) {
      if (zone.content == ZoneContent.singleSash) {
        // --- ضلفة واحدة ---
        // ألمنيوم (درفة): العرض الداخلي + 20 ملم
        double sashWidth = innerWidth + 20.0;
        double sashHeight = innerHeight + 20.0;

        items.add(CuttingItem(
          name: "درفة (Ouvrant) - أفقي",
          description: "ألمنيوم الدرفة (ضلفة واحدة)",
          width: sashWidth,
          height: 0,
          quantity: 2,
          type: CuttingItemType.profileSash,
        ));
        items.add(CuttingItem(
          name: "درفة (Ouvrant) - عمودي",
          description: "ألمنيوم الدرفة (ضلفة واحدة)",
          width: sashHeight,
          height: 0,
          quantity: 2,
          type: CuttingItemType.profileSash,
        ));

        // زجاج (القياس من الخارج): العرض - 194 ملم، الارتفاع - 194 (أو 349 مع السيتار)
        double glassWidth = model.width - 194.0;
        double glassHeight = model.height - (model.hasShutter ? 349.0 : 194.0);

        items.add(CuttingItem(
          name: "زجاج (${zone.glass.structure == GlassStructure.double ? 'مزدوج' : 'مفرد'})",
          description: "زجاج درفة واحدة",
          width: glassWidth,
          height: glassHeight,
          quantity: 1,
          type: CuttingItemType.glass,
        ));

      } else if (zone.content == ZoneContent.doubleSash) {
        // --- ضلفتين ---
        // ألمنيوم (درفة): (العرض الداخلي + 20) / 2
        double sashWidth = (innerWidth + 20.0) / 2;
        double sashHeight = innerHeight + 20.0;

        items.add(CuttingItem(
          name: "درفة (Ouvrant) - أفقي",
          description: "ألمنيوم الدرفة (ضلفتين)",
          width: sashWidth,
          height: 0,
          quantity: 4, // 2 لكل ضلفة
          type: CuttingItemType.profileSash,
        ));
        items.add(CuttingItem(
          name: "درفة (Ouvrant) - عمودي",
          description: "ألمنيوم الدرفة (ضلفتين)",
          width: sashHeight,
          height: 0,
          quantity: 4,
          type: CuttingItemType.profileSash,
        ));

        // زجاج (القياس من الخارج): (العرض - 324) / 2
        double glassWidth = (model.width - 324.0) / 2;
        double glassHeight = model.height - (model.hasShutter ? 349.0 : 194.0);

        items.add(CuttingItem(
          name: "زجاج (${zone.glass.structure == GlassStructure.double ? 'مزدوج' : 'مفرد'})",
          description: "زجاج الدرفتين",
          width: glassWidth,
          height: glassHeight,
          quantity: 2, // 1 لكل ضلفة
          type: CuttingItemType.glass,
        ));
      }
    }

    // 3. حساب الإكسسوارات (Accessories Estimation)
    // الإكسسوارات تم نقل حسابها إلى شاشة الاستهلاك
    
    return items;
  }
}
