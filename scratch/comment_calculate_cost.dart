import 'dart:io';

void main() {
  String path = 'lib/Commande/Systeme/cost_summary_screen.dart';
  String content = File(path).readAsStringSync();
  
  String oldCost1 = '''  void _calculateCost() {
    double cost = 0.0;

    // 1. Aluminum Cost (by Full Bars using SectionColorPrices or SeriesColorPrices)
    if (selectedSeries != null) {
      double priceMeter = 0.0;
      int colorId = selectedColor != null ? selectedColor!['id'] : -1;

      if (colorId != -1 &&
          seriesColorPrices.containsKey(selectedSeries!['id'])) {
        priceMeter = seriesColorPrices[selectedSeries!['id']]?[colorId] ?? 0.0;
      }''';
      
  String newCost1 = '''  void _calculateCost() {
    double cost = 0.0; // الإجمالي المبدئي للتكلفة

    // 1. حساب تكلفة الألمنيوم/الـ PVC (حساب البارات الكاملة بناءً على أسعار الأقسام أو أسعار السيستم)
    if (selectedSeries != null) {
      double priceMeter = 0.0; // سعر المتر الطولي للبروفيل
      int colorId = selectedColor != null ? selectedColor!['id'] : -1;

      // محاولة الحصول على سعر المتر للسيستم بهذا اللون تحديداً من قاعدة البيانات
      if (colorId != -1 &&
          seriesColorPrices.containsKey(selectedSeries!['id'])) {
        priceMeter = seriesColorPrices[selectedSeries!['id']]?[colorId] ?? 0.0;
      }''';
      
  content = content.replaceFirst(oldCost1, newCost1);
  
  String oldCost2 = '''    // 5. Accessory Cost (Calculated exactly from drawing)
    double accessoriesCost = 0.0;
    double handlePrice = _getPriceByType('مقبض');
    double hingePrice = _getPriceByType('مفاصل');
    double rollerPrice = _getPriceByType('عجلات');
    double tasseauPrice = _getPriceByType('الطاسو');
    double screwsPrice = _getPriceByType('البراغي');
    double screwsAssemblyPrice = _getPriceByType('التجميع');
    double screwsBoxPrice = _getPriceByType('تجميع الصندوق');
    double screwsShutterKitPrice = _getPriceByType('كيت الستار');
    double screwsAccessoriesPrice = _getPriceByType('إكسسوارات');
    double screwsRenfortPrice = _getPriceByType('حديد الدعم');
    double screwsFixationPrice = _getPriceByType('التثبيت');
    double screwsBatmoPrice = _getPriceByType('الباتمو');
    double obPrice = _getPriceByType('سيستم أو بي');
    double verrouPrice = _getPriceByType('فيرو سنترال');''';
    
  String newCost2 = '''    // 5. حساب تكلفة الإكسسوارات بناءً على الكميات التي تم استخراجها من الرسم
    double accessoriesCost = 0.0;
    // جلب سعر كل قطعة من قاعدة البيانات عبر الكلمة المفتاحية (نوعها أو اسمها)
    double handlePrice = _getPriceByType('مقبض');
    double hingePrice = _getPriceByType('مفاصل');
    double rollerPrice = _getPriceByType('عجلات');
    double tasseauPrice = _getPriceByType('الطاسو');
    double screwsPrice = _getPriceByType('البراغي'); // السعر الافتراضي للبراغي
    double screwsAssemblyPrice = _getPriceByType('التجميع');
    double screwsBoxPrice = _getPriceByType('تجميع الصندوق');
    double screwsShutterKitPrice = _getPriceByType('كيت الستار');
    double screwsAccessoriesPrice = _getPriceByType('إكسسوارات');
    double screwsRenfortPrice = _getPriceByType('حديد الدعم');
    double screwsFixationPrice = _getPriceByType('التثبيت');
    double screwsBatmoPrice = _getPriceByType('الباتمو');
    double obPrice = _getPriceByType('سيستم أو بي');
    double verrouPrice = _getPriceByType('فيرو سنترال');''';

  content = content.replaceFirst(oldCost2, newCost2);
  
  File(path).writeAsStringSync(content);
  print("Done commenting partial calculateCost");
}
