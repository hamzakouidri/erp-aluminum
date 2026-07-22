import 'dart:io';

void main() {
  String path = 'C:/Users/hp/.gemini/antigravity/brain/7af0fd0b-4fa0-4dfa-a76f-e68960420348/implementation_plan.md';
  String content = File(path).readAsStringSync();
  
  String newFeatures = '''
## 5. ميزات متقدمة (مخطط لها للمستقبل)
- **تنبيهات نقص المخزون (Low Stock Alerts):** إضافة حقل "حد التنبيه" (Threshold) للمواد التي تُشترى بكميات كبيرة (مثل البراغي)، ليقوم النظام بإرسال تنبيه (واتساب أو إشعار) عند اقتراب نفاذها.
- **إدارة الهدر (Waste / Scrap Adjustment):** واجهة مخصصة لتسجيل هدر التصنيع (مثلاً عامل أخطأ في القص). يمكن خصم بار إضافي كـ "هدر" مع إمكانية تحديد ما إذا كان قد تبقّى منه "شوت" أم تم إتلافه بالكامل.

''';

  content += '\\n' + newFeatures;
  File(path).writeAsStringSync(content);
  print("Updated implementation plan");
}
