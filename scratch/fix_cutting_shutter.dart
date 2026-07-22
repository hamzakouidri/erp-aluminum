import 'dart:io';

void main() {
  var file = File('lib/Commande/Systeme/cutting_calculator.dart');
  var content = file.readAsStringSync();

  content = content.replaceFirst(
'''
    double frameCutWidth = model.width;
    double frameCutHeight = model.height;
''',
'''
    double frameCutWidth = model.width;
    // The actual height of the window frame part
    double actualWindowHeight = model.hasShutter ? (model.height - model.shutterBoxHeight) : model.height;
    double frameCutHeight = actualWindowHeight;
'''
  );

  content = content.replaceFirst(
'''
      // 140 Series (Monobloc)
      if (model.hasShutter) {
        frameCutHeight -= model.shutterBoxHeight; // خصم صندوق الستار
''',
'''
      // 140 Series (Monobloc)
      if (model.hasShutter) {
        // frameCutHeight was already calculated from actualWindowHeight, so we don't subtract shutterBoxHeight again!
'''
  );

  content = content.replaceFirst(
'''
    // هنا نجلب عرض الإطار الخارجي (الـ Dormant) من قاعدة البيانات (إذا لم نجده نستخدم 45 مم افتراضياً)
    // العرض والارتفاع الداخلي: يتم حسابه بطرح عرض الإطار الخارجي من الجهتين
    double innerWidth = model.width - (dormantThickness * 2);
    double innerHeight =
        model.height - (dormantThickness * (model.hasBottomFrame ? 2 : 1));
''',
'''
    // هنا نجلب عرض الإطار الخارجي (الـ Dormant) من قاعدة البيانات (إذا لم نجده نستخدم 45 مم افتراضياً)
    // العرض والارتفاع الداخلي: يتم حسابه بطرح عرض الإطار الخارجي من الجهتين
    double innerWidth = model.width - (dormantThickness * 2);
    double innerHeight =
        actualWindowHeight - (dormantThickness * (model.hasBottomFrame ? 2 : 1));
'''
  );

  content = content.replaceFirst(
'''
        // وإذا كانت هناك ستارة (Shutter) نخصم مساحة صندوق الستارة (349 مم بدلاً من 194 مم).
        double glassWidth = model.width - 194.0;
        double glassHeight = model.height - (model.hasShutter ? 349.0 : 194.0);
''',
'''
        // وإذا كانت هناك ستارة (Shutter) نخصم مساحة صندوق الستارة
        double glassWidth = model.width - 194.0;
        double glassHeight = actualWindowHeight - 194.0;
'''
  );

  content = content.replaceFirst(
'''
        // زجاج (القياس من الخارج): (العرض - 324) / 2
        double glassWidth = (model.width - 324.0) / 2;
        double glassHeight = model.height - (model.hasShutter ? 349.0 : 194.0);
''',
'''
        // زجاج (القياس من الخارج): (العرض - 324) / 2
        double glassWidth = (model.width - 324.0) / 2;
        double glassHeight = actualWindowHeight - 194.0;
'''
  );

  file.writeAsStringSync(content);
}
