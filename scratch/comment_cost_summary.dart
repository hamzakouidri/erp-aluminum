import 'dart:io';

void main() {
  String path = 'lib/Commande/Systeme/cost_summary_screen.dart';
  String content = File(path).readAsStringSync();
  
  // Replace _calculateDimensions with commented version
  String oldDims = '''  void _calculateDimensions() {
    double w = widget.model.width / 1000;
    double h = widget.model.height / 1000;

    frameLength = (h * 2) + (widget.model.hasBottomFrame ? w * 2 : w);

    int sashes = 0;
    int hinges = 0;
    int handles = 0;
    int rollers = 0;

    double tempSashLength = 0;
    double tempGlassArea = 0;
    double tempJointPerimeter = 0;

    for (var z in widget.model.zones) {
      double zw = z.boundary.width / 1000;
      double zh = z.boundary.height / 1000;

      if (z.content == ZoneContent.empty) continue;

      // Calculate glass area roughly for the zone
      double zoneGlassArea = (zw - 0.12) * (zh - 0.12);
      if (zoneGlassArea > 0) tempGlassArea += zoneGlassArea;

      if (z.content == ZoneContent.singleSash) {
        sashes += 1;
        hinges += (zh > 1.5) ? 3 : 2; // 3 hinges if height > 1.5m
        handles += 1;
        tempSashLength += (zw * 2) + (zh * 2);
        tempJointPerimeter += (zw * 2) + (zh * 2);
      } else if (z.content == ZoneContent.doubleSash) {
        sashes += 2;
        hinges += (zh > 1.5) ? 6 : 4;
        handles += 1;
        tempSashLength += (zw * 2) + (zh * 4);
        tempJointPerimeter += (zw * 2) + (zh * 4);
      } else if (z.content == ZoneContent.slidingSash) {
        int count = z.slidingSashesCount > 0 ? z.slidingSashesCount : 2;
        sashes += count;
        handles += count;
        rollers += count * 2; // 2 rollers per sliding sash
        tempSashLength += (zw * 2) + (zh * count * 2);
        tempJointPerimeter += (zw * 2) + (zh * count * 2);
      } else if (z.content == ZoneContent.fixedGlass) {
        tempJointPerimeter += (zw * 2) + (zh * 2);
      }
    }

    sashLength = tempSashLength;
    glassArea = tempGlassArea;
    jointPerimeter = tempJointPerimeter + frameLength;
    totalAlumLength = frameLength + sashLength;
    shutterArea = widget.model.hasShutter ? (w * h) : 0;

    setState(() {
      exactSashesCount = sashes;
      exactHingesCount = hinges;
      exactHandlesCount = handles;
      exactRollersCount = rollers;
    });
  }''';

  String newDims = '''  void _calculateDimensions() {
    // نحول العرض والارتفاع من ميليمتر (mm) إلى متر (m) بالقسمة على 1000
    double w = widget.model.width / 1000;
    double h = widget.model.height / 1000;

    // حساب طول إطار النافذة (الكادر): الارتفاع مضروب في 2، زائد العرض (مرتين إذا كان هناك إطار سفلي، وإلا مرة واحدة)
    frameLength = (h * 2) + (widget.model.hasBottomFrame ? w * 2 : w);

    // تهيئة المتغيرات لعد الإكسسوارات
    int sashes = 0; // عدد الظلفات
    int hinges = 0; // عدد المفصلات
    int handles = 0; // عدد المقابض
    int rollers = 0; // عدد العجلات

    double tempSashLength = 0; // متغير مؤقت لحساب إجمالي أمتار البروفيل للظلفات
    double tempGlassArea = 0; // متغير مؤقت لحساب مساحة الزجاج
    double tempJointPerimeter = 0; // متغير مؤقت لحساب طول الجوان المطاطي

    // نمر على كل "منطقة" (Zone) داخل النافذة لحساب متطلباتها
    for (var z in widget.model.zones) {
      double zw = z.boundary.width / 1000; // عرض المنطقة بالمتر
      double zh = z.boundary.height / 1000; // ارتفاع المنطقة بالمتر

      if (z.content == ZoneContent.empty) continue; // إذا كانت المنطقة فارغة لا نحسب شيء

      // حساب مساحة الزجاج بشكل تقريبي (نطرح 12 سم تقريباً من العرض والطول لقيمة الإطار)
      double zoneGlassArea = (zw - 0.12) * (zh - 0.12);
      if (zoneGlassArea > 0) tempGlassArea += zoneGlassArea;

      if (z.content == ZoneContent.singleSash) {
        // نافذة بضلفة واحدة
        sashes += 1;
        hinges += (zh > 1.5) ? 3 : 2; // 3 مفصلات إذا كان الارتفاع أكبر من 1.5 متر، وإلا 2 مفصلة
        handles += 1;
        tempSashLength += (zw * 2) + (zh * 2); // محيط الضلفة (العرض مرتين والارتفاع مرتين)
        tempJointPerimeter += (zw * 2) + (zh * 2); // الجوان يحتاج نفس المحيط
      } else if (z.content == ZoneContent.doubleSash) {
        // نافذة بضلفتين
        sashes += 2;
        hinges += (zh > 1.5) ? 6 : 4; // الضعف لأنها ضلفتين
        handles += 1;
        tempSashLength += (zw * 2) + (zh * 4); // الارتفاع 4 مرات للضلفتين
        tempJointPerimeter += (zw * 2) + (zh * 4);
      } else if (z.content == ZoneContent.slidingSash) {
        // نافذة سحابة (Coulissant)
        int count = z.slidingSashesCount > 0 ? z.slidingSashesCount : 2;
        sashes += count;
        handles += count;
        rollers += count * 2; // عجلتين لكل ضلفة سحابة
        tempSashLength += (zw * 2) + (zh * count * 2);
        tempJointPerimeter += (zw * 2) + (zh * count * 2);
      } else if (z.content == ZoneContent.fixedGlass) {
        // زجاج ثابت (فيكس)
        tempJointPerimeter += (zw * 2) + (zh * 2); // نحتاج جوان فقط، بدون بروفيل ضلفة أو إكسسوارات
      }
    }

    // حفظ النتائج النهائية للمتغيرات العالمية للصفحة
    sashLength = tempSashLength;
    glassArea = tempGlassArea;
    jointPerimeter = tempJointPerimeter + frameLength; // الجوان للظلفات + جوان الإطار الخارجي
    totalAlumLength = frameLength + sashLength; // إجمالي أمتار البروفيل (الكادر + الظلفات)
    shutterArea = widget.model.hasShutter ? (w * h) : 0; // مساحة الستار إذا كان موجوداً

    setState(() {
      exactSashesCount = sashes;
      exactHingesCount = hinges;
      exactHandlesCount = handles;
      exactRollersCount = rollers;
    });
  }''';

  content = content.replaceFirst(oldDims, newDims);
  File(path).writeAsStringSync(content);
  print("Done commenting _calculateDimensions");
}
