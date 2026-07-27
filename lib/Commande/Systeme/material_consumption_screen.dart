// ==========================================================================
// ملف: MaterialConsumptionScreen
// الوظيفة العامة: شاشة "الكمية والتكلفة" — تعرض جدول تفصيلي لكل مكونات النافذة
// (بروفيلات، زجاج، ستار/شتر، إكسسوارات) مع حساب التكلفة وسعر البيع، وتسمح
// بتبديل المكونات، تعديل الأسعار يدويًا، وتفعيل/تعطيل عناصر اختيارية (Kits...).
// ==========================================================================
import 'dart:math' as math; // لاستخدام math.max عند حساب سعر القطعة الواحدة
import 'package:flutter/material.dart';
import 'package:database_data/sql_database.dart'; // كائن الوصول لقاعدة بيانات SQLite
import 'package:database_data/Commande/Systeme/model.dart'; // نموذج بيانات النافذة (WindowModel)
import 'package:database_data/Commande/Systeme/calculate_component.dart'; // منطق توليد قائمة المكونات (BOM)
import 'package:database_data/Commande/window_painter.dart'; // رسّام يعرض شكل النافذة (Custom Painter)
import 'package:database_data/Commande/Systeme/profile_selector_dialog.dart'; // نافذة اختيار بروفيل/مكون بدي
import 'package:provider/provider.dart'; // لإدارة حالة الإعدادات العامة (اللغة...)
import 'package:database_data/settings/app_settings.dart';
import 'package:database_data/settings/localization.dart'; // دالة الترجمة حسب اللغة
import 'package:database_data/services/cloud_sync_service.dart';
import 'package:database_data/widgets/section_image.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart'; // نوع Database لاستعلامات SQL المباشرة
import 'package:shared_preferences/shared_preferences.dart'; // تخزين إعدادات التسعير محليًا (نسبة الربح...)
// الودجت الرئيسي: StatefulWidget لأن الشاشة تحتوي حالة كثيرة (تحديد الأسعار، توسعة الأقسام...)
class MaterialConsumptionScreen extends StatefulWidget {
  final WindowModel model; // نموذج النافذة الحالية اللي بنعرض تفاصيلها
  const MaterialConsumptionScreen({super.key, required this.model});
  @override
  State<MaterialConsumptionScreen> createState() =>
      _MaterialConsumptionScreenState();
}
class _MaterialConsumptionScreenState extends State<MaterialConsumptionScreen> {
  bool showCostPrice = true; // إظهار/إخفاء سعر التكلفة (TODO: لاحقًا يُربط بصلاحية المدير)
  final ScrollController _scrollController = ScrollController(); // للتحكم بتمرير الجدول أفقيًا ومعرفة موضع السكرول
  bool _isScrolled = false; // هل تم التمرير أفقيًا (لإظهار عمود ثابت "overlay")
  bool _isBottomBarExpanded = false; // هل شريط الإعدادات السفلي مفتوح أو مطوي
  // اختصار لجلب اللغة الحالية من الـ Provider بدون الاستماع لتغييراتها (listen:false)
  String get _lang => Provider.of<AppSettingsProvider>(context, listen: false).language.name;
  // دالة مساعدة: تتحقق إذا كان النص يحتوي حروف عربية (لتقرير هل نعرض الاسم الثانوي أو لا)
  bool _hasArabic(String text) {
    return RegExp(r'[\u0600-\u06FF]').hasMatch(text);
  }
  // ------------------ إعدادات التسعير (تُحمَّل من SharedPreferences وقاعدة البيانات) ------------------
  double _profitMargin = 0.0; // نسبة الربح % (طريقة الحساب بالنسبة المئوية)
  double _pricePerSqm = 0.0; // سعر المتر المربع (طريقة الحساب بالمتر المربع)
  double _torqueFactor = 1.5; // معامل عزم المحرك (لحساب قوة المحرك المطلوبة حسب وزن الستار)
  double _pricePerLinearMeterFromDb = 0.0; // سعر المتر الخطي القادم من جدول Series في قاعدة البيانات
  double? _pricePerLinearMeterOverride; // تعديل يدوي لسعر المتر الخطي (يتجاوز القيمة من قاعدة البيانات)
  double _shutterSqmPriceFromDb = 0.0; // سعر متر مربع الستار من جدول ShutterSqmPrices
  double? _shutterSqmPriceOverride; // تعديل يدوي لسعر متر الستار
  double _moteurInstallFee = 0.0; // أجرة تركيب المحرك
  double _obInstallFee = 0.0; // أجرة تركيب System OB
  double _demiObInstallFee = 0.0; // أجرة تركيب Demi System OB
  double _verrouInstallFee = 0.0; // أجرة تركيب Verrou Central
  CostMethod _costMethod = CostMethod.percentage; // طريقة احتساب سعر البيع الحالية (نسبة/متر مربع/متر خطي)
  Map<String, List<Map<String, dynamic>>> _kitBundleData = {}; // بيانات حزم الكيت (Kit Bundles) المحمّلة من القاعدة
  Map<String, bool> _kitPerLeafMap = {}; // يحدد لكل كيت هل الكمية تُحسب لكل ضلفة (per leaf) أو لا
  final Map<String, bool> _kitGroupExpanded = {}; // حالة توسعة/طي كل مجموعة كيت في الجدول
  // متحكمات حقول الإدخال (TextEditingController) لإعدادات التسعير
  late TextEditingController _profitMarginController;
  late TextEditingController _pricePerSqmController;
  late TextEditingController _pricePerLinearMeterController;
  late TextEditingController _shutterSqmPriceController;
  late TextEditingController _torqueFactorController;
  // ==========================================================================
  // دالة: _findShutterComponent
  // الغرض: البحث في جدول ShutterComponents عن مكوّن حسب النوع والـ subtype
  // (مثلاً: البحث عن "محور" بنوع "extruded")، مع خطة بديلة (fallback) لو ما
  // وجدت تطابق بالـ subtype، تبحث بدونه.
  // ==========================================================================
  Future<Map<String, dynamic>?> _findShutterComponent(
      String componentType,
      String subtype,
      ) async {
    final dbInstance = await SqlDatabase().db; // فتح اتصال قاعدة البيانات
    if (dbInstance == null) return null; // إذا فشل الاتصال، رجّع null
    // البحث الأساسي: نفس النوع ونفس subtype وعنصر نشط
    var queryRes = await dbInstance.query(
      'ShutterComponents',
      where:
      'component_type = ? AND shutter_subtype = ? AND (is_active = 1 OR is_active IS NULL)',
      whereArgs: [componentType, subtype],
      limit: 1,
    );
    if (queryRes.isEmpty) {
      // خطة بديلة: نفس النوع بس بدون شرط subtype
      queryRes = await dbInstance.query(
        'ShutterComponents',
        where: 'component_type = ? AND (is_active = 1 OR is_active IS NULL)',
        whereArgs: [componentType],
        limit: 1,
      );
    }
    if (queryRes.isNotEmpty) {
      final row = Map<String, dynamic>.from(queryRes.first); // نسخة قابلة للتعديل من النتيجة
      // حساب السعر المعروض: يفضّل price_dzd وإلا price
      row['calculated_price'] = _safeDouble(row['price_dzd'] ?? row['price']);
      return row;
    }
    return null; // لا يوجد مكوّن مطابق
  }
  // ==========================================================================
  // دالة: _findClosestFinalBlade
  // الغرض: إيجاد "الشريحة النهائية" (Final Blade) الأقرب حجمًا لمقاس الشريحة
  // العادية المختارة (targetSize)، ضمن نفس الـ subtype، مع خطة بديلة أوسع.
  // ==========================================================================
  Future<Map<String, dynamic>?> _findClosestFinalBlade(
      Database dbInstance,
      double targetSize,
      String subtype,
      ) async {
    // بحث عن كل الصفوف اللي اسمها يحتوي "final/finale/نهائي" وبنفس الـ subtype
    var finalBlades = await dbInstance.query(
      'ShutterComponents',
      where:
      "(LOWER(name) LIKE '%final%' OR LOWER(name) LIKE '%finale%' OR name LIKE '%نهائي%') "
          "AND shutter_subtype = ? AND (is_active = 1 OR is_active IS NULL)",
      whereArgs: [subtype],
    );
    if (finalBlades.isEmpty) {
      // خطة بديلة: نفس البحث بدون شرط subtype
      finalBlades = await dbInstance.query(
        'ShutterComponents',
        where:
        "(LOWER(name) LIKE '%final%' OR LOWER(name) LIKE '%finale%' OR name LIKE '%نهائي%') "
            "AND (is_active = 1 OR is_active IS NULL)",
      );
    }
    if (finalBlades.isEmpty) return null; // لا توجد شريحة نهائية أصلًا في القاعدة
    // دالة داخلية: تستخرج المقاس الرقمي من الصف (measurement أو من الاسم)
    double parseSize(Map<String, dynamic> component) {
      final sizeStr = getComponentSize(component) ?? '';
      return double.tryParse(sizeStr) ?? 0.0;
    }
    Map<String, dynamic>? closest; // أقرب شريحة نهائية للمقاس المطلوب
    double minDiff = double.infinity; // أصغر فرق تم إيجاده حتى الآن
    // المرور على كل الشرائح النهائية المتاحة لإيجاد الأقرب حجمًا
    for (final row in finalBlades) {
      final sz = parseSize(row);
      if (sz > 0) {
        final diff = (sz - targetSize).abs();
        if (diff < minDiff) {
          minDiff = diff;
          closest = row;
        }
      }
    }
    closest ??= finalBlades.first; // إذا كل المقاسات كانت 0 أو غير صالحة، خذ أول نتيجة كخيار أخير
    final row = Map<String, dynamic>.from(closest);
    row['calculated_price'] = _safeDouble(row['price_dzd'] ?? row['price']);
    return row;
  }
  // ==========================================================================
  // Map: activeVariants
  // يمثل حالة تفعيل كل عنصر اختياري في النافذة (كيتات، سيبورات، طانديم...).
  // القيمة true تعني أن العنصر مفعّل حاليًا ويظهر في الجدول ويُحتسب في السعر.
  // ==========================================================================
  Map<String, bool> activeVariants = {
    'Verrou Central': false,
    'System OB': false,
    'Demi System OB': false,
    'كيت (Kit)': false,
    'طانديم (Tandem)': false,
    'الامبو (Embout)': false,
    'سيبور رولمو (Support Roulement)': false,
    'سيبور موتور (Support Moteur)': false,
    'أغطية الشفرات (Bouchons Lames)': false,
  };
  String? _lastAlignedLameKey; // مفتاح تتبع (id+مقاس+subtype) لآخر "شريحة" تمت محاذاة الشريحة النهائية معها، لتفادي إعادة الحساب بلا داعٍ
  // ------------------ ثوابت أبعاد أعمدة الجدول (بالبكسل) ------------------
  static const double _rowHeight = 120; // ارتفاع الصف الأدنى
  static const double _wImg = 50; // عرض عمود الصورة
  static const double _wName = 220; // عرض عمود اسم المكوّن
  static const double _wColor = 100; // عرض عمود اللون
  static const double _wLen = 100; // عرض عمود الطول
  static const double _wQty = 80; // عرض عمود الكمية
  static const double _wPrice = 120; // عرض عمود سعر الوحدة
  static const double _wTotal = 120; // عرض عمود التكلفة الإجمالية للصف
  static const double _wCheck = 80; // عرض عمود مربع التفعيل (Checkbox)
  static const double _minW = // العرض الكلي الأدنى للجدول = مجموع كل الأعمدة
  _wImg + _wName + _wColor + _wLen + _wQty + _wPrice + _wTotal + _wCheck;
  // ==========================================================================
  // دالة: _fetchDefaults  ⭐ (الدالة الأهم في الملف)
  // الغرض: عند فتح الشاشة أو تغيير أي إعداد، تقوم "بالجلب الذكي" لكل المكونات
  // الافتراضية المرتبطة (حديد الدعم، البراغي، الأقفال، الكيتات، المحرك المناسب
  // حسب الوزن...)، وتضبط activeVariants حسب آلية الستار (محرك/مانيفيل/حزام)
  // وحالة الصندوق (تونيل أو لا).
  // ==========================================================================
// ==========================================================================
// دالة مساعدة: تبني شرط WHERE وقائمة args لفلترة الإكسسوارات حسب السلسلة النشطة
// نفس منطق الفلترة المستخدم في model.dart -> _loadAccessoryDefaults
// ==========================================================================
  Map<String, dynamic> _buildSeriesFilterClause() {
    final seriesId = widget.model.systemMode == 'sliding'
        ? widget.model.activeSlidingSeries?.id
        : widget.model.activeSeries?.id;
    if (seriesId == null) {
      return {'clause': '', 'args': <dynamic>[]};
    }
    return {
      'clause':
      ' AND (series_id = ? OR (series_ids IS NOT NULL AND series_ids != \'\' AND \',\' || series_ids || \',\' LIKE ?) OR ((series_id IS NULL OR series_id = 0) AND (series_ids IS NULL OR series_ids = \'\')))',
      'args': [seriesId, '%,' + seriesId.toString() + ',%'],
    };
  }
  Future<void> _fetchDefaults() async {
    await widget.model.updateShutterDefaultsIfNeeded(); // تحديث افتراضيات الستار داخل النموذج نفسه أولًا
    // قراءة حالة الآلية الحالية من النموذج لتحديد أي كيت/سيبور يجب أن يكون مفعّلاً
    final isTunnel = widget.model.isCaissonTunnel; // هل الصندوق نوع "تونيل"
    final isMotor = widget.model.shutterMechanism == 'محرك'; // هل الآلية محرك كهربائي
    final isCrank = // هل الآلية يدوية (مانيفيل)
    widget.model.shutterMechanism == 'منايفال' ||
        widget.model.shutterMechanism == 'مانيفال' ||
        widget.model.shutterMechanism == 'مانيفر';
    // ضبط تفعيل الكيتات المختلفة حسب نوع الآلية وحالة التونيل
    activeVariants['كيت (Kit)'] = false;
    activeVariants['كيت فولي موتور (Kit Volet Moteur)'] = isTunnel
        ? false
        : isMotor;
    activeVariants['كيت فولي مانيفر (Kit Volet Manivelle)'] = isTunnel
        ? false
        : isCrank;
    activeVariants['كيت مانيفر (Kit Manivelle)'] = isTunnel ? false : isCrank;
    activeVariants['كيت فولي (Kit Volet)'] = isTunnel
        ? false
        : (!isMotor && !isCrank); // الافتراضي (حزام) لو مو محرك ولا مانيفيل
    activeVariants['كيت حزام (Kit Sangle)'] = false;
    activeVariants['طانديم (Tandem)'] = isTunnel; // الطانديم يُفعّل تلقائيًا فقط في حالة التونيل
    // قطع المحرك (الامبو، سيبور رولمو، سيبور موتور) تُفعّل فقط لو الآلية محرك
    if (isMotor) {
      activeVariants['الامبو (Embout)'] = true;
      activeVariants['سيبور رولمو (Support Roulement)'] = true;
      activeVariants['سيبور موتور (Support Moteur)'] = true;
    } else {
      activeVariants['الامبو (Embout)'] = false;
      activeVariants['سيبور رولمو (Support Roulement)'] = false;
      activeVariants['سيبور موتور (Support Moteur)'] = isTunnel; // في التونيل قد يلزم سيبور موتور حتى بدون محرك
    }
    activeVariants['أغطية الشفرات (Bouchons Lames)'] = isTunnel || isMotor;
    // تنظيف الـ overrides اللي ما عادت منطقية (مثلاً قطع محرك محفوظة رغم إن الآلية تغيّرت لغير محرك)
    if (!isMotor) {
      widget.model.componentOverrides.remove('الامبو (Embout)');
      widget.model.componentOverrides.remove('سيبور رولمو (Support Roulement)');
      widget.model.componentOverrides.remove('المحرك (Moteur)');
      widget.model.componentOverrides.remove('براغي المحرك');
    }
    if (!isTunnel) {
      widget.model.componentOverrides.remove('طانديم (Tandem)');
    }
    if (!isMotor && !isTunnel) {
      widget.model.componentOverrides.remove('سيبور موتور (Support Moteur)');
      widget.model.componentOverrides.remove('أغطية الشفرات (Bouchons Lames)');
    }
    final db = await SqlDatabase().db; // اتصال قاعدة البيانات لباقي عمليات الجلب
    if (db == null) return; // بدون اتصال ما فيه داعي نكمل
    final Database dbInstance = db;
    try {
      final colorId = widget.model.selectedDbColor?['id']; // معرّف اللون المختار حاليًا (للأسعار الملونة)
      final sqlDb = SqlDatabase();
      // تنظيف ذاتي: إزالة أي "براغي" محفوظة غلط كأنها تخص "فيرو" (verrou) بدل نوعها الصحيح
      widget.model.componentOverrides.removeWhere((key, val) {
        if (key.contains('براغي') && val is Map) {
          final n = val['name'].toString().toLowerCase();
          final t = (val['type'] ?? '').toString().toLowerCase();
          return n.contains('verrou') ||
              t.contains('verrou') ||
              n.contains('verro') ||
              t.contains('verro') ||
              n.contains('gevisse') ||
              t.contains('gevisse');
        }
        return false;
      });
      // ------- محاذاة تلقائية للقياسات لتفادي عدم تطابق قديم (صندوق مع كيت، شرائح مع سكك...) -------
      try {
        final caisson = widget.model.componentOverrides['الصندوق (Caisson)']; // الصندوق الحالي المختار
        final isMotor = widget.model.shutterMechanism == 'محرك';
        final isCrank =
            widget.model.shutterMechanism == 'منايفال' ||
                widget.model.shutterMechanism == 'مانيفال' ||
                widget.model.shutterMechanism == 'مانيفر';
        List<String> activeKitKeys = []; // مفاتيح الكيتات النشطة حسب نوع الآلية
        if (isMotor) {
          activeKitKeys.add('كيت فولي موتور (Kit Volet Moteur)');
        } else if (isCrank) {
          activeKitKeys.addAll([
            'كيت فولي مانيفر (Kit Volet Manivelle)',
            'كيت مانيفر (Kit Manivelle)',
          ]);
        } else {
          // حزام
          activeKitKeys.add('كيت فولي (Kit Volet)');
        }
        // لكل كيت نشط: تحقق أن مقاسه يطابق مقاس الصندوق، وإن لم يطابق ابحث عن كيت بنفس مقاس الصندوق
        for (var kitKey in activeKitKeys) {
          final kit = widget.model.componentOverrides[kitKey];
          if (caisson != null && kit != null) {
            final caissonDigits = getComponentSize(caisson); // مقاس الصندوق
            final kitDigits = getComponentSize(kit); // مقاس الكيت الحالي
            if (caissonDigits != null &&
                kitDigits != null &&
                caissonDigits != kitDigits) {
              // البحث عن كل الكيتات المتاحة في القاعدة
              final compRes = await dbInstance.query(
                'ShutterComponents',
                where:
                "(LOWER(name) LIKE '%kit%' OR name LIKE '%كيت%') AND (is_active = 1 OR is_active IS NULL)",
              );
              for (var row in compRes) {
                final rowSize = getComponentSize(row);
                // دالة مقارنة مقاسين بمرونة (تقارن أول رقمين فقط إذا كان الطول كافيًا)
                bool isSameSize(String? size1, String? size2) {
                  if (size1 == null || size2 == null) return false;
                  final s1 = size1.replaceAll(RegExp(r'[^0-9]'), '').trim();
                  final s2 = size2.replaceAll(RegExp(r'[^0-9]'), '').trim();
                  if (s1.length >= 2 && s2.length >= 2) {
                    return s1.substring(0, 2) == s2.substring(0, 2);
                  }
                  return s1 == s2;
                }
                bool matches = isSameSize(rowSize, caissonDigits);
                if (matches) {
                  // وجدنا كيتًا يطابق مقاس الصندوق: نحفظه كـ override جديد
                  final matchedKit = Map<String, dynamic>.from(row);
                  matchedKit['calculated_price'] = _safeDouble(
                    matchedKit['price_dzd'] ?? matchedKit['price'],
                  );
                  widget.model.componentOverrides[kitKey] = matchedKit;
                  break; // اكتفينا بأول تطابق
                }
              }
            }
          }
        }
        // محاذاة السكك (Coulisses) مع مقاس الشرائح (Lames)
        final lames = widget.model.componentOverrides['الشرائح (Lames)'];
        final coulisses = widget.model.componentOverrides['السكك (Coulisses)'];
        if (lames != null && coulisses != null) {
          final lamesDigits = getComponentSize(lames);
          final coulissesDigits = getComponentSize(coulisses);
          if (lamesDigits != null &&
              coulissesDigits != null &&
              lamesDigits != coulissesDigits) {
            final compRes = await dbInstance.query(
              'ShutterComponents',
              where:
              "(LOWER(name) LIKE '%coulisse%' OR name LIKE '%سك%') AND (is_active = 1 OR is_active IS NULL)",
            );
            for (var row in compRes) {
              if (getComponentSize(row) == lamesDigits) {
                final matchedCoulisse = Map<String, dynamic>.from(row);
                matchedCoulisse['calculated_price'] = _safeDouble(
                  matchedCoulisse['price_dzd'] ?? matchedCoulisse['price'],
                );
                widget.model.componentOverrides['السكك (Coulisses)'] =
                    matchedCoulisse; // تحديث السكة لتطابق مقاس الشريحة
                break;
              }
            }
          }
        }
        // محاذاة "الشريحة النهائية" مع الشريحة العادية (الاسم/المقاس/subtype)
        final finale =
        widget.model.componentOverrides['الشريحة النهائية (Lame Finale)'];
        if (lames != null) {
          final targetSubtype =
              lames['shutter_subtype']?.toString() ?? 'normal'; // نوع الشريحة الحالي (extruded/normal)
          final currentLameKey = // مفتاح فريد يمثل الشريحة الحالية (لتتبع التغيير)
              "${lames['id']}_${getComponentSize(lames)}_$targetSubtype";
          // إعادة حساب الشريحة النهائية فقط إذا تغيّرت الشريحة الأساسية أو الـ subtype
          if (finale == null ||
              finale['shutter_subtype']?.toString() != targetSubtype ||
              currentLameKey != _lastAlignedLameKey) {
            final lamesSizeStr = getComponentSize(lames) ?? '';
            final lamesSize = double.tryParse(lamesSizeStr) ?? 0.0;
            if (lamesSize > 0) {
              // البحث عن أقرب شريحة نهائية لمقاس الشريحة الحالية
              final matchedFinale = await _findClosestFinalBlade(
                db,
                lamesSize,
                targetSubtype,
              );
              if (matchedFinale != null) {
                widget
                    .model
                    .componentOverrides['الشريحة النهائية (Lame Finale)'] =
                    matchedFinale;
              }
            } else {
              // لا يوجد مقاس رقمي معروف: خذ أي شريحة نهائية بنفس subtype
              final matched = await _findShutterComponent(
                'final_blade',
                targetSubtype,
              );
              if (matched != null) {
                widget
                    .model
                    .componentOverrides['الشريحة النهائية (Lame Finale)'] =
                    matched;
              }
            }
            _lastAlignedLameKey = currentLameKey; // تحديث مفتاح آخر محاذاة تمت
          }
          // دالة داخلية عامة: تحاذي مكوّنًا (uiKey) بنوعه من قاعدة البيانات (dbType) إذا لم يكن مطابقًا للـ subtype المطلوب
          Future<void> alignComponent(String uiKey, String dbType) async {
            final comp = widget.model.componentOverrides[uiKey];
            if (comp == null ||
                comp['shutter_subtype']?.toString() != targetSubtype) {
              final matched = await _findShutterComponent(
                dbType,
                targetSubtype,
              );
              if (matched != null) {
                widget.model.componentOverrides[uiKey] = matched;
              }
            }
          }
          // محاذاة كل القطع المرتبطة بالشريحة (المحور، الأطاش، سيبور موتور، الامبو...)
          await alignComponent('المحور (Axe)', 'laxe');
          await alignComponent('أطاش (Attache)', 'attache');
          await alignComponent(
            'سيبور موتور (Support Moteur)',
            'support_moteur',
          );
          await alignComponent('الامبو (Embout)', 'embout');
          await alignComponent(
            'سيبور رولمو (Support Roulement)',
            'support_roulement',
          );
          await alignComponent('طانديم (Tandem)', 'tandem');
          await alignComponent(
            'أغطية الشفرات (Bouchons Lames)',
            'bouchon_lame',
          );
          // -------- حساب المحرك المناسب تلقائيًا (حسب الوزن والعزم المطلوب) --------
          if (widget.model.shutterMechanism == 'محرك') {
            // 1. حساب معامل الوزن (كغ/م²) حسب نوع الشريحة ومقاسها
            final bladeSubtype =
                lames['shutter_subtype']?.toString() ?? 'normal';
            final isExtruded = bladeSubtype == 'extruded'; // شريحة إكسترودي (أثقل عادة)
            final bladeSizeStr = getComponentSize(lames) ?? '';
            final bladeSize = double.tryParse(bladeSizeStr) ?? 0.0;
            final is55OrMore = bladeSize >= 55.0; // شرائح كبيرة (55 مم فأكثر) أثقل
            double weightCoef = 0.0;
            // إذا كان معامل الوزن محفوظًا مباشرة في بيانات الشريحة، استخدمه
            if (lames.containsKey('weight_per_sqm') &&
                lames['weight_per_sqm'] != null) {
              weightCoef = (lames['weight_per_sqm'] as num).toDouble();
            }
            // وإلا استخدم قيمًا افتراضية حسب النوع والمقاس
            if (weightCoef <= 0.0) {
              if (isExtruded) {
                weightCoef = 12.0; // الإكسترودي أثقل بكثير
              } else if (is55OrMore) {
                weightCoef = 4.0; // إنجكتيد ≥ 55مم
              } else {
                weightCoef = 3.0; // إنجكتيد < 55مم
              }
            }
            // حساب وزن الستار الكلي = العرض(م) × الارتفاع(م) × معامل الوزن
            final double widthM = widget.model.width / 1000.0;
            final double heightM = widget.model.height / 1000.0;
            final double shutterWeight = widthM * heightM * weightCoef;
            // العزم المطلوب بالنيوتن متر = الوزن ÷ معامل العزم (كلما زاد المعامل قلّ العزم اللازم)
            final double requiredNm = shutterWeight / _torqueFactor;
            // 2. جلب كل المحركات النشطة (باستثناء الكيتات التي تحوي كلمة "kit")
            final motorRes = await dbInstance.query(
              'ShutterComponents',
              where:
              "(component_type = 'Moteur' OR (name LIKE '%moteur%' OR name LIKE '%محرك%')) "
                  "AND name NOT LIKE '%kit%' AND name NOT LIKE '%كيت%' "
                  "AND (is_active = 1 OR is_active IS NULL)",
            );
            Map<String, dynamic>? selectedMotor; // المحرك المختار نهائيًا
            double bestNmDifference = double.infinity; // أقل فرق عزم زائد عن الحاجة
            // دالة داخلية: تستخرج قيمة العزم (Nm) من حقل measurement أو من اسم المحرك
            double? parseTorque(Map<String, dynamic> item) {
              final name = item['name']?.toString() ?? '';
              final measurement = item['measurement']?.toString() ?? '';
              final measNum = double.tryParse(measurement);
              if (measNum != null) return measNum;
              final match = RegExp(
                r'(\d+)\s*(?:Nm|nm|N|n|نيوتن)',
              ).firstMatch(name);
              if (match != null) return double.tryParse(match.group(1)!);
              final numMatch = RegExp(r'\d+').firstMatch(name);
              if (numMatch != null) return double.tryParse(numMatch.group(0)!);
              return null;
            }
            // اختيار المحرك الأقرب من فوق (أصغر عزم يكفي الحاجة، وليس أقل منها)
            for (final row in motorRes) {
              final nm = parseTorque(row);
              if (nm != null) {
                if (nm >= requiredNm) { // المحرك يكفي (عزمه ≥ العزم المطلوب)
                  final diff = nm - requiredNm;
                  if (diff < bestNmDifference) { // نفضّل الأقرب لتفادي "مبالغة" في القوة
                    bestNmDifference = diff;
                    selectedMotor = row;
                  }
                }
              }
            }
            // خطة بديلة: إذا ما فيه محرك يكفي القوة المطلوبة، اختر الأقوى المتاح
            if (selectedMotor == null && motorRes.isNotEmpty) {
              double maxNm = -1;
              for (final row in motorRes) {
                final nm = parseTorque(row) ?? 0.0;
                if (nm > maxNm) {
                  maxNm = nm;
                  selectedMotor = row;
                }
              }
            }
            if (selectedMotor != null) {
              final matchedMotor = Map<String, dynamic>.from(selectedMotor);
              matchedMotor['calculated_price'] = _safeDouble(
                matchedMotor['price_dzd'] ?? matchedMotor['price'],
              );
              widget.model.componentOverrides['المحرك (Moteur)'] = matchedMotor;
              // 3. إيجاد المحور (Axe) المطابق لقطر المحرك المختار
              final motorDiameter = (matchedMotor['motor_diameter'] ?? '')
                  .toString()
                  .trim();
              final motorName = matchedMotor['name'].toString();
              String targetDia = motorDiameter;
              if (targetDia.isEmpty) {
                // إذا لم يوجد قطر مسجّل، حاول استخراجه من اسم المحرك (مثلاً "60mm")
                final diaMatch = RegExp(
                  r'(\d+)\s*(?:mm|ملم)',
                ).firstMatch(motorName);
                if (diaMatch != null) {
                  targetDia = diaMatch.group(1)!;
                } else {
                  // fallback أخير: تخمين القطر من أرقام شائعة موجودة بالاسم
                  if (motorName.contains('60')) {
                    targetDia = '60';
                  } else if (motorName.contains('40')) {
                    targetDia = '40';
                  }
                }
              }
              if (targetDia.isNotEmpty) {
                final axeRes = await dbInstance.query(
                  'ShutterComponents',
                  where:
                  "(component_type = 'Axe' OR name LIKE '%axe%' OR name LIKE '%محور%') AND (is_active = 1 OR is_active IS NULL)",
                );
                Map<String, dynamic>? selectedAxe;
                for (final row in axeRes) {
                  final axeName = row['name'].toString();
                  final axeDiameter = (row['motor_diameter'] ?? '')
                      .toString()
                      .trim();
                  // تطابق حسب حقل القطر أو ورود الرقم داخل الاسم
                  if (axeDiameter == targetDia || axeName.contains(targetDia)) {
                    selectedAxe = row;
                    break;
                  }
                }
                if (selectedAxe == null && axeRes.isNotEmpty) {
                  selectedAxe = axeRes.first; // fallback: أول محور متاح
                }
                if (selectedAxe != null) {
                  final matchedAxe = Map<String, dynamic>.from(selectedAxe);
                  matchedAxe['calculated_price'] = _safeDouble(
                    matchedAxe['price_dzd'] ?? matchedAxe['price'],
                  );
                  widget.model.componentOverrides['المحور (Axe)'] = matchedAxe;
                }
              }
            }
          }
        }
      } catch (e) {
        print("Error in self-healing alignment: $e"); // تسجيل أي خطأ أثناء المحاذاة الذاتية دون إيقاف التنفيذ
      }
      // 0. تحديث أسعار البروفيلات الرئيسية (الإطار/الظلفة/الغطاء الجانبي) حسب اللون المختار
      if (widget.model.frameOverride != null) {
        final fId = widget.model.frameOverride!['id'];
        double price = await sqlDb.getSectionPrice(fId, colorId); // سعر القسم (Section) حسب اللون
        widget.model.frameOverride!['calculated_price'] = price;
      }
      if (widget.model.sashOverride != null) {
        final sId = widget.model.sashOverride!['id'];
        double price = await sqlDb.getSectionPrice(sId, colorId);
        widget.model.sashOverride!['calculated_price'] = price;
      }
      if (widget.model.sideCoverOverride != null) {
        final scId = widget.model.sideCoverOverride!['id'];
        double price = await sqlDb.getSectionPrice(scId, colorId);
        widget.model.sideCoverOverride!['calculated_price'] = price;
      }
      if (widget.model.slidingFrameOverride != null) {
        final sfId = widget.model.slidingFrameOverride!['id'];
        double price = await sqlDb.getSectionPrice(sfId, colorId);
        widget.model.slidingFrameOverride!['calculated_price'] = price;
      }
      if (widget.model.slidingSashOverride != null) {
        final ssId = widget.model.slidingSashOverride!['id'];
        double price = await sqlDb.getSectionPrice(ssId, colorId);
        widget.model.slidingSashOverride!['calculated_price'] = price;
      }
      // Resolve and update prices for central, lateral, traverse, and chicane sash sections
      final typesAndKeys = {
        'sash_central': ['قائم وسطي (Sash Central)', 'قائم وسطي (Central)'],
        'sash_lateral': ['قائم جانبي (Sash Lateral)', 'قائم جانبي (Lateral)'],
        'sash_traverse': ['عرضي (Traverse)', 'سكة الظلفة (Sash Traverse)'],
        'chicane': ['الشيكان (Chicane)'],
        'sash_chicane': ['الشيكان (Chicane)'],
      };
      for (var entry in typesAndKeys.entries) {
        final type = entry.key;
        final keys = entry.value;
        final section = widget.model.getSectionByType(type);
        if (section != null) {
          final sId = section.id;
          double price = await sqlDb.getSectionPrice(sId, colorId);
          final secMap = section.toMap();
          secMap['calculated_price'] = price;
          for (var key in keys) {
            final existing = widget.model.componentOverrides[key];
            if (existing != null && existing is Map) {
              final mutable = Map<String, dynamic>.from(existing);
              mutable['calculated_price'] = price;
              widget.model.componentOverrides[key] = mutable;
            } else {
              widget.model.componentOverrides[key] = secMap;
            }
          }
        }
      }
      // تحديث أسعار كل الـ overrides الأخرى الموجودة (إكسسوارات/ستار/بروفيلات) حسب اللون
      for (var key in widget.model.componentOverrides.keys) {
        final override = widget.model.componentOverrides[key];
        if (override != null && override is Map) {
          final id = override['id'];
          if (id != null && colorId != null) {
            final mutable = Map<String, dynamic>.from(override);
            // محاولة 1: جدول أسعار الإكسسوارات حسب اللون
            final accPrice = await dbInstance.query(
              'AccessoryColorPrices',
              where: 'accessory_id = ? AND color_id = ?',
              whereArgs: [id, colorId],
            );
            if (accPrice.isNotEmpty) {
              final double p = _safeDouble(accPrice.first['price']);
              if (p > 0) {
                mutable['calculated_price'] = p;
                widget.model.componentOverrides[key] = mutable;
                continue; // انتقل للمفتاح التالي
              }
            }
            // محاولة 2: جدول أسعار مكونات الستار حسب اللون
            final shutPrice = await dbInstance.query(
              'ShutterColorPrices',
              where: 'shutter_component_id = ? AND color_id = ?',
              whereArgs: [id, colorId],
            );
            if (shutPrice.isNotEmpty) {
              mutable['calculated_price'] = _safeDouble(
                shutPrice.first['price'],
              );
              widget.model.componentOverrides[key] = mutable;
              continue;
            }
            // محاولة 3: جدول البروفيلات (Sections) - إذا كان id يعود لبروفيل
            final secRes = await dbInstance.query(
              'Sections',
              where: 'id = ?',
              whereArgs: [id],
            );
            if (secRes.isNotEmpty) {
              double price = await sqlDb.getSectionPrice(id, colorId);
              if (price > 0) {
                mutable['calculated_price'] = price;
                widget.model.componentOverrides[key] = mutable;
              }
            }
          }
        }
      }
      // دالة مساعدة: تتحقق هل مفتاح معيّن مرتبط فعليًا بسجل من قاعدة البيانات (له id)
      bool isLinked(String key) {
        final val = widget.model.componentOverrides[key];
        return val != null && val is Map && val['id'] != null;
      }
      // 1. جلب حديد الإطار الافتراضي المرتبط بالبروفيل المختار (linked_renfort_id)
      if (!isLinked('حديد الإطار (Renfort Frame)')) {
        // نحدد الإطار الفعّال حسب وضع النظام (منزلق/عادي)
        final activeFrameMap = widget.model.systemMode == 'sliding'
            ? widget.model.slidingFrameOverride
            : widget.model.frameOverride;
        if (activeFrameMap != null &&
            activeFrameMap['linked_renfort_id'] != null) {
          int rId = activeFrameMap['linked_renfort_id'] as int;
          final res = await dbInstance.query(
            'Sections',
            where: 'id = ?',
            whereArgs: [rId],
          );
          if (res.isNotEmpty) {
            final rMap = Map<String, dynamic>.from(res.first);
            double price = _safeDouble(rMap['price_dzd'] ?? rMap['price']);
            rMap['calculated_price'] = price;
            widget.model.componentOverrides['حديد الإطار (Renfort Frame)'] =
                rMap;
            if (mounted) setState(() {}); // تحديث فوري للواجهة بمجرد إيجاد الحديد
          }
        }
      }
      // 2. جلب حديد الظلفة الافتراضي المرتبط + بحث عن حديد المفاصل (Mifsal) الخاص
      if (!isLinked('حديد الظلفة (Renfort Sash)')) {
        final activeSashMap = widget.model.systemMode == 'sliding'
            ? widget.model.slidingSashOverride
            : widget.model.sashOverride;
        if (activeSashMap != null &&
            activeSashMap['linked_renfort_id'] != null) {
          int rId = activeSashMap['linked_renfort_id'] as int;
          final res = await dbInstance.query(
            'Sections',
            where: 'id = ?',
            whereArgs: [rId],
          );
          if (res.isNotEmpty) {
            final rMap = Map<String, dynamic>.from(res.first);
            double price = _safeDouble(rMap['price_dzd'] ?? rMap['price']);
            rMap['calculated_price'] = price;
            widget.model.componentOverrides['حديد الظلفة (Renfort Sash)'] =
                rMap;
            // البحث عن "حديد مفصل" خاص ضمن نفس السلسلة (يبحث بمرادفات عربي/فرنسي متعددة)
            final mifsalRes = await dbInstance.query(
              'Sections',
              where:
              'series_id = ? AND (name LIKE ? OR type LIKE ? OR name LIKE ? OR type LIKE ? OR name LIKE ? OR type LIKE ? OR name LIKE ? OR type LIKE ? OR name LIKE ? OR type LIKE ?)',
              whereArgs: [
                (widget.model.systemMode == 'sliding' &&
                    widget.model.activeSlidingSeries != null)
                    ? widget.model.activeSlidingSeries!.id
                    : widget.model.activeSeries?.id,
                '%مفصل%',
                '%مفصل%',
                '%مفاصل%',
                '%مفاصل%',
                '%mifsal%',
                '%mifsal%',
                '%paumelle%',
                '%paumelle%',
                '%pomelle%',
                '%pomelle%',
              ],
              limit: 1,
            );
            if (mifsalRes.isNotEmpty) {
              // وجد حديد مفصل خاص: يستخدمه بسعره الخاص حسب اللون
              final mifsalMap = Map<String, dynamic>.from(mifsalRes.first);
              double mPrice = 0.0;
              if (colorId != null) {
                mPrice = await sqlDb.getSectionPrice(
                  mifsalMap['id'] as int,
                  colorId,
                );
              } else {
                mPrice = _safeDouble(
                  mifsalMap['price_dzd'] ?? mifsalMap['price'],
                );
              }
              mifsalMap['calculated_price'] = mPrice;
              widget.model.componentOverrides['حديد الظلفة الخاص بالمفاصل'] =
                  mifsalMap;
            } else {
              // إذا ما وُجد حديد مفصل خاص، استخدم نفس حديد الظلفة العادي
              widget.model.componentOverrides['حديد الظلفة الخاص بالمفاصل'] =
                  rMap;
            }
            if (mounted) setState(() {}); // تحديث فوري
          }
        }
      }
      // 3. البراغي: دالة عامة تجلب برغيًا مناسبًا حسب عمود boolean في جدول Accessories (مثل is_moteur_screw)
      Future<void> assignScrew(String key, String dbColumn) async {
        if (!isLinked(key)) {
          try {
            List<Map<String, dynamic>> res = [];
            try {
              final matType = widget.model.isPVC ? 'PVC' : 'Aluminium';
              final seriesFilter = _buildSeriesFilterClause();
              res = await dbInstance.query(
                'Accessories',
                where:
                '$dbColumn = 1 AND (is_active = 1 OR is_active IS NULL) AND (material_type = ? OR material_type = "Both" OR material_type IS NULL OR material_type = "")${seriesFilter['clause']}',
                whereArgs: [matType, ...seriesFilter['args']],
                limit: 1,
              );
            } catch (_) {}// تجاهل خطأ إذا العمود غير موجود بقاعدة بيانات قديمة
            // ملاحظة مهمة: لا يوجد بحث احتياطي عشوائي للبراغي حتى لا يختلط برغي بنوع خاطئ
            if (res.isNotEmpty) {
              final mutableItem = Map<String, dynamic>.from(res.first);
              double price = 0.0;
              if (colorId != null) {
                // محاولة سعر خاص باللون أولًا
                final colorPriceRes = await dbInstance.query(
                  'AccessoryColorPrices',
                  where: 'accessory_id = ? AND color_id = ?',
                  whereArgs: [res.first['id'], colorId],
                );
                if (colorPriceRes.isNotEmpty &&
                    _safeDouble(colorPriceRes.first['price']) > 0) {
                  price = _safeDouble(colorPriceRes.first['price']);
                } else {
                  // وإلا استخدم السعر العام
                  price = _safeDouble(
                    res.first['price_dzd'] ??
                        res.first['price_per_meter'] ??
                        res.first['price'],
                  );
                }
              } else {
                price = _safeDouble(
                  res.first['price_dzd'] ??
                      res.first['price_per_meter'] ??
                      res.first['price'],
                );
              }
              mutableItem['calculated_price'] = price;
              widget.model.componentOverrides[key] = mutableItem;
              if (mounted) {
                setState(() {}); // إجبار الخانة على الظهور فورًا بدون تدخل المستخدم
              }
            }
          } catch (e) {
            print(''); // ملاحظة: طباعة فارغة (يبدو أنها كانت لتصحيح أخطاء سابق ولم تُزل)
          }
        }
      }
      // استدعاء assignScrew لكل نوع برغي محتمل (كل نوع مرتبط بعمود boolean مختلف)
      await assignScrew('براغي المحرك', 'is_moteur_screw');
      await assignScrew('براغي الصندوق', 'is_caisson_screw');
      await assignScrew('براغي الباتمو', 'is_batmo_screw');
      await assignScrew('براغي بوشون باتمو', 'is_bouchon_batmo_screw');
      await assignScrew('براغي حديد الدعم', 'is_renfort_screw');
      await assignScrew('براغي المانيفال', 'is_manivelle_screw');
      await assignScrew('براغي التجميع', 'is_assembly_screw');
      await assignScrew('براغي الإكسسوارات', 'is_accessory_screw');
      await assignScrew('براغي التركيب', 'is_installation_screw');
      await assignScrew('براغي الكيت', 'is_kit_screw');
      // 4. الأقفال والقاش (Gache): دالة عامة تجلب قفلًا/قاشًا حسب عمود boolean، مع بحث احتياطي بالكلمات المفتاحية
      Future<void> assignGache(String key, String dbColumn) async {
        if (!isLinked(key)) {
          try {
            final matType = widget.model.isPVC ? 'PVC' : 'Aluminium';
            final seriesFilter = _buildSeriesFilterClause();
            var res = await dbInstance.query(
              'Accessories',
              where:
              '$dbColumn = 1 AND (is_active = 1 OR is_active IS NULL) AND (material_type = ? OR material_type = "Both" OR material_type IS NULL OR material_type = "")${seriesFilter['clause']}',
              whereArgs: [matType, ...seriesFilter['args']],
              limit: 1,
            );
            if (res.isEmpty) {
              final allAcc = await dbInstance.query(
                'Accessories',
                where:
                '(is_active = 1 OR is_active IS NULL) AND (material_type = ? OR material_type = "Both" OR material_type IS NULL OR material_type = "")${seriesFilter['clause']}',
                whereArgs: [matType, ...seriesFilter['args']],
              );
              final filtered = allAcc.where((a) {
                final n = a['name'].toString().toLowerCase();
                final ty = a['type'].toString().toLowerCase();
                if (key.contains('قاش بورت') || key.contains('Gache Porte')) {
                  final bool containsGache = n.contains('gache') || n.contains('gâche') || n.contains('قاش') || n.contains('كاش') || n.contains('gage') ||
                                             ty.contains('gache') || ty.contains('gâche') || ty.contains('قاش') || ty.contains('كاش') || ty.contains('gage');
                  final bool containsPorte = n.contains('port') || n.contains('بورت') || n.contains('باب') ||
                                             ty.contains('port') || ty.contains('بورت') || ty.contains('باب');
                  return containsGache && containsPorte;
                }
                if (key.contains('مقبض الباب') && key.contains('Condamnation')) {
                  final bool containsHandle = n.contains('poignée') || n.contains('مقبض') || n.contains('handle') ||
                                              ty.contains('poignée') || ty.contains('مقبض') || ty.contains('handle');
                  final bool containsCond = n.contains('condamnation') || n.contains('حمام') || n.contains('بدون مفتاح') ||
                                            ty.contains('condamnation') || ty.contains('حمام') || ty.contains('بدون مفتاح');
                  return containsHandle && containsCond;
                }
                if (key.contains('مقبض الباب') && (key.contains('à Clé') || key.contains('Clef') || key.contains('Poignée Porte'))) {
                  final bool containsHandle = n.contains('poignée') || n.contains('مقبض') || n.contains('handle') ||
                                              ty.contains('poignée') || ty.contains('مقبض') || ty.contains('handle');
                  final bool containsKey = n.contains('clef') || n.contains('clé') || n.contains('مفتاح') ||
                                           ty.contains('clef') || ty.contains('clé') || ty.contains('مفتاح');
                  return containsHandle && containsKey;
                }
                if (key.contains('قفل الباب') && key.contains('Condamnation')) {
                  final bool containsLock = n.contains('serrure') || n.contains('lock') || n.contains('قفل') ||
                                            ty.contains('serrure') || ty.contains('lock') || ty.contains('قفل');
                  final bool containsCond = n.contains('condamnation') || n.contains('حمام') || n.contains('بدون مفتاح') ||
                                            ty.contains('condamnation') || ty.contains('حمام') || ty.contains('بدون مفتاح');
                  final bool containsExcludes = n.contains('poignée') || n.contains('مقبض') || n.contains('handle') ||
                                                ty.contains('poignée') || ty.contains('مقبض') || ty.contains('handle');
                  return containsLock && containsCond && !containsExcludes;
                }
                if (key.contains('قفل الباب') || key.contains('Serrure')) {
                  final bool containsLock = n.contains('serrure') || n.contains('lock') || n.contains('قفل') ||
                                            ty.contains('serrure') || ty.contains('lock') || ty.contains('قفل');
                  final bool containsKey = n.contains('clef') || n.contains('clé') || n.contains('مفتاح') ||
                                           ty.contains('clef') || ty.contains('clé') || ty.contains('مفتاح');
                  final bool containsExcludes = n.contains('canon') || n.contains('أسطوانة') || n.contains('اسطوانة') || n.contains('poignée') || n.contains('مقبض') || n.contains('handle') ||
                                                ty.contains('canon') || ty.contains('أسطوانة') || ty.contains('اسطوانة') || ty.contains('poignée') || ty.contains('مقبض') || ty.contains('handle');
                  return containsLock && containsKey && !containsExcludes;
                }
                // generic fallback
                String kw = '';
                if (key.contains('سامبل') || key.contains('Simple')) kw = 'simple';
                else if (key.contains('دوبل') || key.contains('Double')) kw = 'double';
                else if (key.contains('بورت') || key.contains('Porte')) kw = 'porte';
                else if (key.contains('مفتاح') || key.contains('Clef')) kw = 'clef';
                else if (key.contains('Condamnation')) kw = 'condamnation';
                if (kw.isNotEmpty) {
                  return (n.contains('gache') || n.contains('قاش') || ty.contains('gache') || ty.contains('قاش')) && (n.contains(kw) || ty.contains(kw));
                }
                return false;
              }).toList();
              if (filtered.isNotEmpty) {
                res = [filtered.first];
              }
            }
            if (res.isNotEmpty) {
              final mutableItem = Map<String, dynamic>.from(res.first);
              double price = 0.0;
              if (colorId != null) {
                final colorPriceRes = await dbInstance.query(
                  'AccessoryColorPrices',
                  where: 'accessory_id = ? AND color_id = ?',
                  whereArgs: [res.first['id'], colorId],
                );
                if (colorPriceRes.isNotEmpty &&
                    _safeDouble(colorPriceRes.first['price']) > 0) {
                  price = _safeDouble(colorPriceRes.first['price']);
                } else {
                  price = _safeDouble(
                    res.first['price_dzd'] ??
                        res.first['price_per_meter'] ??
                        res.first['price'],
                  );
                }
              } else {
                price = _safeDouble(
                  res.first['price_dzd'] ??
                      res.first['price_per_meter'] ??
                      res.first['price'],
                );
              }
              mutableItem['calculated_price'] = price;
              widget.model.componentOverrides[key] = mutableItem;
              if (mounted) setState(() {}); // إجبار الخانة على الظهور
            }
          } catch (e) {}
        }
      }
      // استدعاء assignGache لكل نوع قفل/قاش محتمل
      await assignGache('قاش سامبل (Gache Simple Ouvrant)', 'is_gache_simple');
      await assignGache('قاش دوبل (Gache Double Ouvrant)', 'is_gache_double');
      await assignGache('قاش بورت (Gache Porte)', 'is_gache_porte');
      await assignGache('قفل بمفتاح (Clef)', 'is_lock_clef');
      await assignGache('مقبض الباب (Poignée Porte à Clé)', 'is_lock_clef');
      await assignGache('قفل الباب (Serrure)', 'is_lock_clef');
      await assignGache('مقبض الباب Condamnation (Poignée Condamnation)', 'is_lock_condamnation');
      await assignGache('قفل الباب Condamnation (Serrure Condamnation)', 'is_lock_condamnation');
      await assignGache('قفل Condamnation', 'is_lock_condamnation');
      // Migration for backward compatibility
      if (widget.model.componentOverrides.containsKey('جوان بروس (Joint Brosse)')) {
        final oldVal = widget.model.componentOverrides['جوان بروس (Joint Brosse)'];
        if (!widget.model.componentOverrides.containsKey('جوان بروس للظلفة (Joint Brosse Sash)')) {
          widget.model.componentOverrides['جوان بروس للظلفة (Joint Brosse Sash)'] = oldVal;
        }
        if (!widget.model.componentOverrides.containsKey('جوان بروس للستار (Joint Brosse Shutter)')) {
          widget.model.componentOverrides['جوان بروس للستار (Joint Brosse Shutter)'] = oldVal;
        }
      }
      // 5. جلب Joint Brosse (جوان فرشاة) تلقائيًا: يبحث أولًا في جدول Joints ثم في Accessories كخطة بديلة
      Future<void> assignJointBrosse(String uiKey) async {
        if (!isLinked(uiKey)) {
          try {
            final seriesFilter = _buildSeriesFilterClause();
            var jointRes = await dbInstance.query(
              'Joints',
              where:
              "(LOWER(name) LIKE '%bross%' OR name LIKE '%بروس%' OR name LIKE '%برش%' OR name LIKE '%فرشا%' OR name LIKE '%فرشاة%' OR LOWER(name) LIKE '%brush%')${seriesFilter['clause']}",
              whereArgs: [...seriesFilter['args']],
              limit: 1,
            );
            final matType = widget.model.isPVC ? 'PVC' : 'Aluminium';
            if (jointRes.isEmpty) {
              jointRes = await dbInstance.query(
                'Accessories',
                where:
                "(LOWER(name) LIKE '%bross%' OR name LIKE '%بروس%' OR name LIKE '%برش%' OR name LIKE '%فرشا%' OR name LIKE '%فرشاة%' OR LOWER(name) LIKE '%brush%') AND (is_active = 1 OR is_active IS NULL) AND (material_type = ? OR material_type = 'Both' OR material_type IS NULL OR material_type = '')${seriesFilter['clause']}",
                whereArgs: [matType, ...seriesFilter['args']],
                limit: 1,
              );
            }
            if (jointRes.isEmpty) {
              // Fallback بدون فلتر سلسلة: نبحث عن أي جوان بروس عام فقط إذا لم يوجد شيء مطلقًا مطابق للسلسلة
              jointRes = await dbInstance.query(
                'Joints',
                where:
                "(LOWER(name) LIKE '%bross%' OR name LIKE '%بروس%' OR name LIKE '%برش%' OR name LIKE '%فرشا%' OR name LIKE '%فرشاة%' OR LOWER(name) LIKE '%brush%')",
                limit: 1,
              );
            }
            if (jointRes.isNotEmpty) {
              final mutableJoint = Map<String, dynamic>.from(jointRes.first);
              double jPrice = _safeDouble(
                mutableJoint['price_per_meter'] ??
                    mutableJoint['price_dzd'] ??
                    mutableJoint['price'],
              );
              mutableJoint['calculated_price'] = jPrice;
              widget.model.componentOverrides[uiKey] = mutableJoint;
            }
          } catch (e) {}
        }
      }
      await assignJointBrosse('جوان بروس للظلفة (Joint Brosse Sash)');
      await assignJointBrosse('جوان بروس للستار (Joint Brosse Shutter)');
      // 5.5 جلب "الطاسو" (Tasso/Tasseau/Equerre) تلقائيًا بالبحث بعدة مرادفات
      if (!isLinked('الطاسو (Tasso)')) {
        try {
          final matType = widget.model.isPVC ? 'PVC' : 'Aluminium';
          final tRes = await dbInstance.query(
            'Accessories',
            where:
            "(LOWER(name) LIKE '%tasso%' OR LOWER(name) LIKE '%tasseau%' OR name LIKE '%طاسو%' OR name LIKE '%طاصو%' OR LOWER(name) LIKE '%equerre%' OR LOWER(name) LIKE '%équerre%') AND (is_active = 1 OR is_active IS NULL) AND (material_type = ? OR material_type = 'Both' OR material_type IS NULL OR material_type = '')",
            whereArgs: [matType],
            limit: 1,
          );
          if (tRes.isNotEmpty) {
            final mutableItem = Map<String, dynamic>.from(tRes.first);
            double price = _safeDouble(
              mutableItem['price_dzd'] ?? mutableItem['price'],
            );
            mutableItem['calculated_price'] = price;
            widget.model.componentOverrides['الطاسو (Tasso)'] = mutableItem;
            if (mounted) setState(() {});
          }
        } catch (e) {}
      }
      // 5.6 جلب جوانات الزجاج المحددة بالسمك تلقائياً
      Future<void> assignVitrageJoint(String uiKey, List<String> kws) async {
        if (!isLinked(uiKey)) {
          try {
            String whereClause = "(gasket_type = 'جوان فيتراج' OR gasket_type = 'joint_vitrage' OR ((LOWER(name) LIKE '%joint%' OR LOWER(name) LIKE '%جوان%') AND (LOWER(name) LIKE '%vitrage%' OR LOWER(name) LIKE '%زجاج%')))";
            if (kws.isNotEmpty) {
              final kwStrings = kws.map((k) => "LOWER(name) LIKE '%$k%'").join(" OR ");
              whereClause = "($whereClause) AND ($kwStrings)";
            }
            var jointRes = await dbInstance.query(
              'Joints',
              where: whereClause,
              limit: 1,
            );
            if (jointRes.isEmpty) {
              final matType = widget.model.isPVC ? 'PVC' : 'Aluminium';
              jointRes = await dbInstance.query(
                'Accessories',
                where: "($whereClause) AND (is_active = 1 OR is_active IS NULL) AND (material_type = ? OR material_type = 'Both' OR material_type IS NULL OR material_type = '')",
                whereArgs: [matType],
                limit: 1,
              );
            }
            if (jointRes.isNotEmpty) {
              final mutableJoint = Map<String, dynamic>.from(jointRes.first);
              double jPrice = _safeDouble(
                mutableJoint['price_per_meter'] ??
                    mutableJoint['price_dzd'] ??
                    mutableJoint['price'],
              );
              mutableJoint['calculated_price'] = jPrice;
              widget.model.componentOverrides[uiKey] = mutableJoint;
              if (mounted) setState(() {});
            }
          } catch (e) {}
        }
      }
      await assignVitrageJoint('جوان الزجاج 2 ملم (Joint Vitrage 2mm)', ['2']);
      await assignVitrageJoint('جوان الزجاج 3-4 ملم (Joint Vitrage 3-4mm)', ['3', '4']);
      await assignVitrageJoint('جوان الزجاج 5-6 ملم (Joint Vitrage 5-6mm)', ['5', '6']);
      await assignVitrageJoint('جوان الزجاج 7-8 ملم (Joint Vitrage 7-8mm)', ['7', '8']);
      await assignVitrageJoint('جوان الزجاج (Joint Vitrage)', []);

      // 5.6b Auto-assign swing gaskets (Bourrage, Frappe, Central)
      Future<void> assignSwingGasket(String uiKey, String whereClause) async {
        if (!isLinked(uiKey)) {
          try {
            var jointRes = await dbInstance.query(
              'Joints',
              where: whereClause,
              limit: 1,
            );
            if (jointRes.isEmpty) {
              final matType = widget.model.isPVC ? 'PVC' : 'Aluminium';
              jointRes = await dbInstance.query(
                'Accessories',
                where: "($whereClause) AND (is_active = 1 OR is_active IS NULL) AND (material_type = ? OR material_type = 'Both' OR material_type IS NULL OR material_type = '')",
                whereArgs: [matType],
                limit: 1,
              );
            }
            if (jointRes.isNotEmpty) {
              final mutableJoint = Map<String, dynamic>.from(jointRes.first);
              double jPrice = _safeDouble(
                mutableJoint['price_per_meter'] ??
                    mutableJoint['price_dzd'] ??
                    mutableJoint['price'],
              );
              mutableJoint['calculated_price'] = jPrice;
              widget.model.componentOverrides[uiKey] = mutableJoint;
              if (mounted) setState(() {});
            }
          } catch (e) {}
        }
      }

      await assignSwingGasket(
        'جوان البوراج (Joint Bourrage)',
        "(gasket_type = 'جوان بوراج' OR gasket_type = 'جوان بار كلوز' OR gasket_type = 'جوان باركلوز' OR gasket_type = 'joint_bourrage' OR ((LOWER(name) LIKE '%joint%' OR LOWER(name) LIKE '%جوان%') AND (LOWER(name) LIKE '%bourrage%' OR LOWER(name) LIKE '%بوراج%' OR LOWER(name) LIKE '%parclose%' OR LOWER(name) LIKE '%بارك%')))"
      );
      await assignSwingGasket(
        'جوان الضرب (Joint Frappe)',
        "(gasket_type = 'جوان فراب' OR gasket_type = 'جوان فريب' OR gasket_type = 'joint_frappe' OR ((LOWER(name) LIKE '%joint%' OR LOWER(name) LIKE '%جوان%') AND (LOWER(name) LIKE '%frappe%' OR LOWER(name) LIKE '%ضرب%' OR LOWER(name) LIKE '%فراب%' OR LOWER(name) LIKE '%فريب%')))"
      );
      await assignSwingGasket(
        'جوان الوسط (Joint Central)',
        "(gasket_type = 'جوان سنترال' OR gasket_type = 'joint_central' OR ((LOWER(name) LIKE '%joint%' OR LOWER(name) LIKE '%جوان%') AND (LOWER(name) LIKE '%central%' OR LOWER(name) LIKE '%وسط%')))"
      );
      // 5.7 جلب صداد السكة (Arrêt) تلقائياً بالبحث بمرادفات والكود
      if (!isLinked('صداد السكة (Arrêt)')) {
        try {
          final matType = widget.model.isPVC ? 'PVC' : 'Aluminium';
          var aRes = await dbInstance.query(
            'Accessories',
            where: "(code = '80000' OR code = '116' OR LOWER(name) LIKE '%arrêt%' OR LOWER(name) LIKE '%arret%' OR LOWER(name) LIKE '%array%' OR name LIKE '%صداد%' OR name LIKE '%موقف%') AND (is_active = 1 OR is_active IS NULL) AND (material_type = ? OR material_type = 'Both' OR material_type IS NULL OR material_type = '')",
            whereArgs: [matType],
            limit: 1,
          );
          if (aRes.isNotEmpty) {
            final mutableItem = Map<String, dynamic>.from(aRes.first);
            double price = _safeDouble(
              mutableItem['price_dzd'] ?? mutableItem['price'],
            );
            mutableItem['calculated_price'] = price;
            widget.model.componentOverrides['صداد السكة (Arrêt)'] = mutableItem;
            if (mounted) setState(() {});
          }
        } catch (e) {}
      }
      // 6. تحميل بيانات حزم الكيت (Kit Bundles) من قاعدة البيانات مع أسعار كل عنصر داخلها
      final kitBundleData = <String, List<Map<String, dynamic>>>{};
      final kitPerLeafMap = <String, bool>{};
      try {
        final kits = await sqlDb.readKitBundles(); // قراءة كل حزم الكيت المعرّفة
        for (final kit in kits) {
          final kitName = kit['name'] as String? ?? '';
          final kitId = kit['id'] as int;
          final details = await sqlDb.readKitBundleItemsWithDetails(kitId); // عناصر هذا الكيت بالتفصيل
          final mutableDetails = <Map<String, dynamic>>[];
          for (final item in details) {
            final mutableItem = Map<String, dynamic>.from(item);
            // تحديث سعر كل "range" (نطاق سعري حسب المقاس مثلًا) داخل هذا العنصر
            final ranges = item['ranges'] as List? ?? [];
            final mutableRanges = <Map<String, dynamic>>[];
            for (final range in ranges) {
              final rangeMap = Map<String, dynamic>.from(range);
              final prodName = rangeMap['product_name'] as String? ?? '';
              if (prodName.isNotEmpty) {
                final resolvedPrice = await _resolveDynamicProductPrice(
                  db,
                  prodName,
                  colorId,
                );
                if (resolvedPrice != null) {
                  rangeMap['price'] = resolvedPrice;
                }
              }
              mutableRanges.add(rangeMap);
            }
            mutableItem['ranges'] = mutableRanges;
            // نفس المنطق لكن لـ "variants" (بدائل العنصر)
            final variants = item['variants'] as List? ?? [];
            final mutableVariants = <Map<String, dynamic>>[];
            for (final variant in variants) {
              final variantMap = Map<String, dynamic>.from(variant);
              final prodName = variantMap['product_name'] as String? ?? '';
              if (prodName.isNotEmpty) {
                final resolvedPrice = await _resolveDynamicProductPrice(
                  db,
                  prodName,
                  colorId,
                );
                if (resolvedPrice != null) {
                  variantMap['price'] = resolvedPrice;
                }
              }
              mutableVariants.add(variantMap);
            }
            mutableItem['variants'] = mutableVariants;
            // إذا كانت الكمية ثابتة (qty_mode == fixed)، حدّث سعر العنصر نفسه ديناميكيًا
            if (item['qty_mode'] == 'fixed') {
              final prodName = item['component_type'] as String? ?? '';
              if (prodName.isNotEmpty) {
                final resolvedPrice = await _resolveDynamicProductPrice(
                  db,
                  prodName,
                  colorId,
                );
                if (resolvedPrice != null) {
                  mutableItem['price'] = resolvedPrice;
                }
              }
            }
            mutableDetails.add(mutableItem);
          }
          kitBundleData[kitName] = mutableDetails; // تخزين تفاصيل الكيت مع أسعارها المحدّثة
          kitPerLeafMap[kitName] = (kit['per_leaf'] ?? 0) == 1; // هل الكمية تُحسب لكل ضلفة
        }
      } catch (_) {}
      _kitBundleData = kitBundleData; // حفظ في الحالة (State) لاستخدامها في بناء الجدول
      _kitPerLeafMap = kitPerLeafMap;
      // 7. توليد قائمة المكونات الكاملة (BOM) وإكمال أي عنصر "ناقص" (missing) بالبحث الذكي عنه في القاعدة
      final bomItems = ComponentCalculator.generateBom(
        widget.model,
        activeVariants,
        kitBundleData: kitBundleData,
        kitPerLeafMap: kitPerLeafMap,
      );
      for (var item in bomItems) {
        // نعالج فقط العناصر الناقصة التي لم يتم اختيار بديل لها يدويًا بعد
        if (item.isMissing &&
            !widget.model.componentOverrides.containsKey(item.originalName)) {
          try {
            // ---- حالة خاصة: الإسبانيوليت (نوع قفل طويل) ----
            if (item.originalName.contains('إسبانيوليت') ||
                item.originalName.contains('Espagnolette')) {
              try {
                // 1. استخراج المقاس المطلوب من الاسم (مثلاً 180)
                final match = RegExp(r'\d+').firstMatch(item.originalName);
                String targetSize = match != null ? match.group(0)! : '';
                final matType = widget.model.isPVC ? 'PVC' : 'Aluminium';
                var allEsp = await dbInstance.query(
                  'Accessories',
                  where:
                  "(type LIKE '%إسبانيوليت%' OR LOWER(name) LIKE '%esp%') AND (is_active = 1 OR is_active IS NULL) AND (material_type = ? OR material_type = 'Both' OR material_type IS NULL OR material_type = '')",
                  whereArgs: [matType],
                );
                if (allEsp.isNotEmpty) {
                  Map<String, dynamic>? selectedEsp;
                  // 3. محاولة العثور على إسبانيوليت بنفس المقاس المطلوب
                  if (targetSize.isNotEmpty) {
                    for (var e in allEsp) {
                      String n = e['name'].toString();
                      String ty = e['type'].toString();
                      if (n.contains(targetSize) || ty.contains(targetSize)) {
                        selectedEsp = e;
                        break;
                      }
                    }
                  }
                  // 4. إذا لم يجد نفس المقاس، يختار أول خيار متاح كبديل
                  selectedEsp ??= allEsp.first;
                  // 5. حفظ المكوّن وتحديث الشاشة فورًا
                  final mutableItem = Map<String, dynamic>.from(selectedEsp);
                  double price = 0.0;
                  if (colorId != null) {
                    final colorPriceRes = await dbInstance.query(
                      'AccessoryColorPrices',
                      where: 'accessory_id = ? AND color_id = ?',
                      whereArgs: [selectedEsp['id'], colorId],
                    );
                    if (colorPriceRes.isNotEmpty &&
                        _safeDouble(colorPriceRes.first['price']) > 0) {
                      price = _safeDouble(colorPriceRes.first['price']);
                    } else {
                      price = _safeDouble(
                        selectedEsp['price_dzd'] ?? selectedEsp['price'],
                      );
                    }
                  } else {
                    price = _safeDouble(
                      selectedEsp['price_dzd'] ?? selectedEsp['price'],
                    );
                  }
                  mutableItem['calculated_price'] = price;
                  widget.model.componentOverrides[item.originalName] =
                      mutableItem;
                  if (mounted) setState(() {});
                }
              } catch (e) {}
              continue; // انتقل للعنصر الناقص التالي (تم التعامل مع الإسبانيوليت بشكل خاص)
            }
            // ---- الحالة العامة: تحديد الجدول والكلمات المفتاحية (عربي/فرنسي) حسب فئة العنصر ----
            String? table; // اسم جدول قاعدة البيانات المستهدف للبحث
            String keywordAr = ''; // كلمة مفتاحية بالعربي
            String keywordFr = ''; // كلمة مفتاحية بالفرنسي/إنجليزي
            if (item.category == 'shutter') {
              table = 'ShutterComponents';
              // سلسلة شروط تحدد الكلمة المفتاحية المناسبة حسب اسم العنصر الناقص
              if (item.originalName.contains('Lames') ||
                  item.originalName.contains('الشرائح')) {
                keywordFr = 'lame';
                keywordAr = 'شريح';
              } else if (item.originalName.contains('Coulisses') ||
                  item.originalName.contains('السكك')) {
                keywordFr = 'coulisse';
                keywordAr = 'سك';
              } else if (item.originalName.contains('Axe') ||
                  item.originalName.contains('المحور')) {
                keywordFr = 'axe';
                keywordAr = 'محور';
              } else if (item.originalName.contains('Caisson') ||
                  item.originalName.contains('الصندوق')) {
                keywordFr = 'caisson';
                keywordAr = 'صندوق';
              } else if (item.originalName.contains('Moteur') ||
                  item.originalName.contains('المحرك')) {
                keywordFr = 'moteur';
                keywordAr = 'محرك';
              } else if (item.originalName.contains('Manivelle') ||
                  item.originalName.contains('المانيفال')) {
                keywordFr = 'manivelle';
                keywordAr = 'مانيفال';
              } else if (item.originalName.contains('Tandem') ||
                  item.originalName.contains('طانديم')) {
                keywordFr = 'tandem';
                keywordAr = 'طانديم';
              } else if (item.originalName.contains('Lame Finale') ||
                  item.originalName.contains('الشريحة النهائية')) {
                keywordFr = 'finale';
                keywordAr = 'نهائي';
              } else if (item.originalName.contains('Joint Brosse') ||
                  item.originalName.contains('Joint bross') ||
                  item.originalName.contains('جوان بروس')) {
                keywordFr = 'bross';
                keywordAr = 'بروس';
              } else if (item.originalName.contains('Kit') ||
                  item.originalName.contains('كيت')) {
                keywordFr = 'kit';
                keywordAr = 'كيت';
              } else if (item.originalName.contains('Attache') ||
                  item.originalName.contains('أطاش')) {
                keywordFr = 'attache';
                keywordAr = 'أطاش';
              } else if (item.originalName.contains('Support Moteur') ||
                  item.originalName.contains('سيبور موتور')) {
                keywordFr = 'support_moteur';
                keywordAr = 'سيبور موتور';
              } else if (item.originalName.contains('Embout') ||
                  item.originalName.contains('الامبو')) {
                keywordFr = 'embout';
                keywordAr = 'امبو';
              } else if (item.originalName.contains('Support Roulement') ||
                  item.originalName.contains('سيبور رولمو')) {
                keywordFr = 'support_roulement';
                keywordAr = 'سيبور رولمو';
              } else if (item.originalName.contains('Bouchons Lames') ||
                  item.originalName.contains('أغطية الشفرات')) {
                keywordFr = 'bouchon_lame';
                keywordAr = 'أغطية الشفرات';
              }
            } else if (item.category == 'accessory') {
              table = 'Accessories';
              if (item.originalName.contains('أوكتو') ||
                  item.originalName.toLowerCase().contains('octo')) {
                keywordFr = 'octo';
                keywordAr = 'أوكتو';
              } else if (item.originalName.contains('المقبض') ||
                  item.originalName.contains('مقبض') ||
                  item.originalName.contains('Handle')) {
                keywordFr = 'poign';
                keywordAr = 'مقبض';
              } else if (item.originalName.contains('المفاصل') ||
                  item.originalName.contains('Hinges')) {
                keywordFr = 'paumel';
                keywordAr = 'مفصل';
              } else if (item.originalName.contains('System OB')) {
                keywordFr = 'ob';
                keywordAr = 'ob';
              } else if ((item.originalName.contains('الفيرو') ||
                  item.originalName.contains('Verrou')) &&
                  !item.originalName.contains('Central')) {
                keywordFr = 'verrou';
                keywordAr = 'فيرو';
              } else if (item.originalName.contains('براغي') ||
                  item.originalName.toLowerCase().contains('screw')) {
                keywordFr = 'visse';
                keywordAr = 'براغي';
              } else if (item.originalName.contains('عجلات') ||
                  item.originalName.contains('Roulette')) {
                keywordFr = 'roulette';
                keywordAr = 'عجل';
              } else if (item.originalName.contains('أونتروماتيك') ||
                  item.originalName.contains('Entrematique') ||
                  item.originalName.contains('انتراميتيك') ||
                  item.originalName.toLowerCase().contains('intra')) {
                keywordFr = 'intra';
                keywordAr = 'انترام';
              } else if (item.originalName.contains('اسبانيولات') ||
                  item.originalName.contains('Espagnolette')) {
                keywordFr = 'espagnol';
                keywordAr = 'اسبانيول';
              } else if (item.originalName.contains('كاش كوليسون') ||
                  item.originalName.contains('Gache coulissant')) {
                keywordFr = 'gache';
                keywordAr = 'كاش';
              } else if (item.originalName.contains('صداد') ||
                  item.originalName.contains('Arrêt') ||
                  item.originalName.contains('Arret')) {
                keywordFr = 'arret';
                keywordAr = 'صداد';
              }
            } else if (item.category == 'joint') {
              table = 'Joints';
              if (item.originalName.contains('Joint Brosse') ||
                  item.originalName.contains('Joint bross') ||
                  item.originalName.contains('جوان بروس')) {
                keywordFr = 'bross';
                keywordAr = 'بروس';
              } else if (item.originalName.contains('2mm') || item.originalName.contains('2 ملم')) {
                keywordFr = '2';
                keywordAr = '2';
              } else if (item.originalName.contains('3-4mm') || item.originalName.contains('3-4 ملم')) {
                keywordFr = '3';
                keywordAr = '3';
              } else if (item.originalName.contains('5-6mm') || item.originalName.contains('5-6 ملم')) {
                keywordFr = '5';
                keywordAr = '5';
              } else if (item.originalName.contains('7-8mm') || item.originalName.contains('7-8 ملم')) {
                keywordFr = '7';
                keywordAr = '7';
              } else {
                keywordFr = 'joint';
                keywordAr = 'جوان';
              }
            } else if (item.category == 'profile') {
              table = 'Sections';
              if (item.originalName.contains('Sash Lateral') ||
                  item.originalName.contains('جانبي')) {
                final sId = widget.model.systemMode == 'sliding'
                    ? widget.model.activeSlidingSeries?.id
                    : widget.model.activeSeries?.id;
                bool isLateralReinforced = widget.model.zones.any((z) =>
                    z.slidingMontantReinforced['lateral_0'] == true ||
                    z.slidingMontantReinforced['lateral_1'] == true);
                final targetSuffix = isLateralReinforced ? '108' : '104';
                final secRes = await dbInstance.query(
                  'Sections',
                  where: 'series_id = ? AND code LIKE ?',
                  whereArgs: [sId, '%$targetSuffix'],
                  limit: 1,
                );
                if (secRes.isNotEmpty) {
                  final mutableItem = Map<String, dynamic>.from(secRes.first);
                  double price = 0.0;
                  if (colorId != null) {
                    price = await sqlDb.getSectionPrice(
                      secRes.first['id'] as int,
                      colorId,
                    );
                  } else {
                    price = _safeDouble(secRes.first['price_dzd'] ?? secRes.first['price']);
                  }
                  mutableItem['calculated_price'] = price;
                  widget.model.componentOverrides[item.originalName] = mutableItem;
                  if (mounted) setState(() {});
                  continue;
                }
              } else if (item.originalName.contains('Sash Central') ||
                  item.originalName.contains('وسطي')) {
                final sId = widget.model.systemMode == 'sliding'
                    ? widget.model.activeSlidingSeries?.id
                    : widget.model.activeSeries?.id;
                bool isCentralReinforced = widget.model.zones.any((z) =>
                    z.slidingMontantReinforced.entries.any((e) => e.key.startsWith('central_') && e.value == true));
                final targetSuffix = isCentralReinforced ? '107' : '105';
                final secRes = await dbInstance.query(
                  'Sections',
                  where: 'series_id = ? AND code LIKE ?',
                  whereArgs: [sId, '%$targetSuffix'],
                  limit: 1,
                );
                if (secRes.isNotEmpty) {
                  final mutableItem = Map<String, dynamic>.from(secRes.first);
                  double price = 0.0;
                  if (colorId != null) {
                    price = await sqlDb.getSectionPrice(
                      secRes.first['id'] as int,
                      colorId,
                    );
                  } else {
                    price = _safeDouble(secRes.first['price_dzd'] ?? secRes.first['price']);
                  }
                  mutableItem['calculated_price'] = price;
                  widget.model.componentOverrides[item.originalName] = mutableItem;
                  if (mounted) setState(() {});
                  continue;
                }
              } else if (item.originalName.contains('Chicane') ||
                  item.originalName.contains('شيكان')) {
                final sId = widget.model.systemMode == 'sliding'
                    ? widget.model.activeSlidingSeries?.id
                    : widget.model.activeSeries?.id;
                final secRes = await dbInstance.query(
                  'Sections',
                  where: 'series_id = ? AND code LIKE ?',
                  whereArgs: [sId, '%106'],
                  limit: 1,
                );
                if (secRes.isNotEmpty) {
                  final mutableItem = Map<String, dynamic>.from(secRes.first);
                  double price = 0.0;
                  if (colorId != null) {
                    price = await sqlDb.getSectionPrice(
                      secRes.first['id'] as int,
                      colorId,
                    );
                  } else {
                    price = _safeDouble(secRes.first['price_dzd'] ?? secRes.first['price']);
                  }
                  mutableItem['calculated_price'] = price;
                  widget.model.componentOverrides[item.originalName] = mutableItem;
                  if (mounted) setState(() {});
                  continue;
                }
              }
              if (item.originalName.contains('Batmo') ||
                  item.originalName.contains('الباتمو')) {
                keywordFr = 'batmo';
                keywordAr = 'باتمو';
              } else if (item.originalName.contains('Mullion') ||
                  item.originalName.contains('تقسيم الزجاج')) {
                // حالة خاصة: التقسيم (Mullion/Traverse) — يُبحث ضمن نفس السلسلة النشطة فقط
                final mullRes = await dbInstance.query(
                  'Sections',
                  where:
                  'series_id = ? AND (LOWER(type) LIKE ? OR LOWER(name) LIKE ? OR LOWER(type) LIKE ? OR LOWER(name) LIKE ? OR name LIKE ? OR type LIKE ?)',
                  whereArgs: [
                    widget.model.systemMode == 'sliding'
                        ? widget.model.activeSlidingSeries?.id
                        : widget.model.activeSeries?.id,
                    '%mullion%',
                    '%mullion%',
                    '%traverse%',
                    '%traverse%',
                    '%تقسيم%',
                    '%تقسيم%',
                  ],
                  limit: 1,
                );
                if (mullRes.isNotEmpty) {
                  final mutableItem = Map<String, dynamic>.from(mullRes.first);
                  double price = 0.0;
                  if (colorId != null) {
                    price = await sqlDb.getSectionPrice(
                      mullRes.first['id'] as int,
                      colorId,
                    );
                  } else {
                    price = _safeDouble(
                      mullRes.first['price_dzd'] ?? mullRes.first['price'],
                    );
                  }
                  mutableItem['calculated_price'] = price;
                  widget.model.componentOverrides[item.originalName] =
                      mutableItem;
                  if (mounted) setState(() {});
                  continue; // تخطَّ البحث العام أدناه لأننا وجدنا النتيجة هنا
                } else {
                  keywordFr = 'mullion';
                  keywordAr = 'تقسيم';
                }
              } else if (item.originalName.contains('Renfort') ||
                  item.originalName.contains('حديد')) {
                keywordFr = 'renfort';
                keywordAr = 'حديد';
              } else if (item.originalName.contains('Réducteur') ||
                  item.originalName.contains('ريديكتور') ||
                  item.originalName.contains('reducteur') ||
                  item.originalName.contains('مخفض')) {
                final sId = widget.model.systemMode == 'sliding'
                    ? widget.model.activeSlidingSeries?.id
                    : widget.model.activeSeries?.id;
                // البحث عن الريديكتور بالكود أو الاسم/النوع ضمن السلسلة النشطة
                final redResAll = await dbInstance.query(
                  'Sections',
                  where: 'series_id = ? AND (is_active = 1 OR is_active IS NULL)',
                  whereArgs: [sId],
                );
                final redMatches = redResAll.where((s) {
                  final t = (s['type'] ?? '').toString().toLowerCase();
                  final n = (s['name'] ?? '').toString().toLowerCase();
                  final c = (s['code'] ?? '').toString().toLowerCase();
                  return (c.contains('67114') ||
                          t.contains('reduct') ||
                          n.contains('reduct') ||
                          n.contains('مخفض') ||
                          n.contains('ريديكتور')) &&
                      !t.contains('rail') &&
                      !t.contains('cadre') &&
                      !t.contains('frame') &&
                      !n.contains('rail') &&
                      !n.contains('سكة') &&
                      !n.contains('cadre') &&
                      !n.contains('إطار');
                }).toList();
                final redRes = redMatches;
                if (redRes.isNotEmpty) {
                  final mutableItem = Map<String, dynamic>.from(redRes.first);
                  double price = 0.0;
                  if (colorId != null) {
                    price = await sqlDb.getSectionPrice(
                      redRes.first['id'] as int,
                      colorId,
                    );
                  } else {
                    price = _safeDouble(redRes.first['price_dzd'] ?? redRes.first['price']);
                  }
                  mutableItem['calculated_price'] = price;
                  widget.model.componentOverrides[item.originalName] = mutableItem;
                  if (mounted) setState(() {});
                }
                continue; // 🟢 عدم تنفيذ البحث العام البديل لمنع جلب قطاعات خاطئة مثل السكة Rail
              } else if (item.originalName.contains('Couvre') ||
                  item.originalName.contains('couvre') ||
                  item.originalName.contains('الغطاء الجانبي') ||
                  item.originalName.contains('Side Cover')) {
                final sId = widget.model.systemMode == 'sliding'
                    ? widget.model.activeSlidingSeries?.id
                    : widget.model.activeSeries?.id;
                final cjResAll = await dbInstance.query(
                  'Sections',
                  where: 'series_id = ? AND (is_active = 1 OR is_active IS NULL)',
                  whereArgs: [sId],
                );
                final cjMatches = cjResAll.where((s) {
                  final t = (s['type'] ?? '').toString().toLowerCase();
                  final n = (s['name'] ?? '').toString().toLowerCase();
                  return t.contains('couvre') || n.contains('couvre') || n.contains('غطاء') || t.contains('side_cover');
                }).toList();
                if (cjMatches.isNotEmpty) {
                  final mutableItem = Map<String, dynamic>.from(cjMatches.first);
                  double price = 0.0;
                  if (colorId != null) {
                    price = await sqlDb.getSectionPrice(
                      cjMatches.first['id'] as int,
                      colorId,
                    );
                  } else {
                    price = _safeDouble(cjMatches.first['price_dzd'] ?? cjMatches.first['price']);
                  }
                  mutableItem['calculated_price'] = price;
                  widget.model.componentOverrides[item.originalName] = mutableItem;
                  widget.model.sideCoverOverride = mutableItem;
                  if (mounted) setState(() {});
                }
                continue;
              } else if (item.originalName.contains('Latéral') ||
                  item.originalName.contains('lateral') ||
                  item.originalName.contains('جانبي')) {
                final sId = widget.model.systemMode == 'sliding'
                    ? widget.model.activeSlidingSeries?.id
                    : widget.model.activeSeries?.id;
                final latResAll = await dbInstance.query(
                  'Sections',
                  where: 'series_id = ? AND (is_active = 1 OR is_active IS NULL)',
                  whereArgs: [sId],
                );
                final bool isRenf = item.originalName.contains('معزز') || item.originalName.contains('Renforcé') ||
                    widget.model.zones.any((z) => z.slidingMontantReinforced.entries.any((e) => e.key.startsWith('lateral_') && e.value == true));
                final targetCode = isRenf ? '67108' : '67104';
                final targetSuffix = isRenf ? '108' : '104';

                final latMatches = latResAll.where((s) {
                  final c = (s['code'] ?? '').toString().toLowerCase();
                  return c.contains(targetCode) || c.endsWith(targetSuffix);
                }).toList();

                final fallbackMatches = latResAll.where((s) {
                  final n = (s['name'] ?? '').toString().toLowerCase();
                  final c = (s['code'] ?? '').toString().toLowerCase();
                  return (c.contains('104') || c.contains('108') || n.contains('latéral') || n.contains('lateral') || n.contains('جانبي')) &&
                      !n.contains('central') && !n.contains('وسطي') && !n.contains('chicane') && !c.contains('105');
                }).toList();

                final finalMatches = latMatches.isNotEmpty ? latMatches : fallbackMatches;

                if (finalMatches.isNotEmpty) {
                  final mutableItem = Map<String, dynamic>.from(finalMatches.first);
                  double price = 0.0;
                  if (colorId != null) {
                    price = await sqlDb.getSectionPrice(
                      finalMatches.first['id'] as int,
                      colorId,
                    );
                  } else {
                    price = _safeDouble(finalMatches.first['price_dzd'] ?? finalMatches.first['price']);
                  }
                  mutableItem['calculated_price'] = price;
                  widget.model.componentOverrides[item.originalName] = mutableItem;
                  if (mounted) setState(() {});
                }
                continue;
              } else if (item.originalName.contains('Central') ||
                  item.originalName.contains('chicane') ||
                  item.originalName.contains('وسطي')) {
                final sId = widget.model.systemMode == 'sliding'
                    ? widget.model.activeSlidingSeries?.id
                    : widget.model.activeSeries?.id;
                final cenResAll = await dbInstance.query(
                  'Sections',
                  where: 'series_id = ? AND (is_active = 1 OR is_active IS NULL)',
                  whereArgs: [sId],
                );
                final cenMatches = cenResAll.where((s) {
                  final n = (s['name'] ?? '').toString().toLowerCase();
                  final c = (s['code'] ?? '').toString().toLowerCase();
                  return (c.contains('105') || c.contains('107') || n.contains('central') || n.contains('وسطي') || n.contains('chicane')) &&
                      !n.contains('latéral') && !n.contains('جانبي') && !c.contains('104');
                }).toList();
                if (cenMatches.isNotEmpty) {
                  final mutableItem = Map<String, dynamic>.from(cenMatches.first);
                  double price = 0.0;
                  if (colorId != null) {
                    price = await sqlDb.getSectionPrice(
                      cenMatches.first['id'] as int,
                      colorId,
                    );
                  } else {
                    price = _safeDouble(cenMatches.first['price_dzd'] ?? cenMatches.first['price']);
                  }
                  mutableItem['calculated_price'] = price;
                  widget.model.componentOverrides[item.originalName] = mutableItem;
                  if (mounted) setState(() {});
                }
                continue;
              } else if (item.originalName.contains('Rail') ||
                  item.originalName.contains('سكة')) {
                final sId = widget.model.systemMode == 'sliding'
                    ? widget.model.activeSlidingSeries?.id
                    : widget.model.activeSeries?.id;
                final railRes = await dbInstance.query(
                  'Sections',
                  where: 'series_id = ? AND (LOWER(type) = ? OR LOWER(name) = ? OR LOWER(name) LIKE ?) AND LOWER(type) NOT LIKE ? AND LOWER(name) NOT LIKE ?',
                  whereArgs: [sId, 'rail', 'rail', 'rail%', '%frame%', '%cadre%'],
                  limit: 1,
                );
                if (railRes.isNotEmpty) {
                  final mutableItem = Map<String, dynamic>.from(railRes.first);
                  double price = 0.0;
                  if (colorId != null) {
                    price = await sqlDb.getSectionPrice(
                      railRes.first['id'] as int,
                      colorId,
                    );
                  } else {
                    price = _safeDouble(railRes.first['price_dzd'] ?? railRes.first['price']);
                  }
                  mutableItem['calculated_price'] = price;
                  widget.model.componentOverrides[item.originalName] = mutableItem;
                  if (mounted) setState(() {});
                }
                continue; // 🟢 عدم تنفيذ البحث العام البديل لمنع جلب قطاعات عشوائية
              }
            }
            // إذا حُدد جدول وكلمة مفتاحية، نفّذ البحث العام في قاعدة البيانات
            if (table != null) {
              List<Map<String, Object?>> res = [];
              if (keywordFr.isNotEmpty || keywordAr.isNotEmpty) {
                String sizeFilter = ''; // فلتر إضافي للمقاس (يُستخدم للصندوق/الكيت فقط)
                final activeSeriesIdForJoint = widget.model.systemMode == 'sliding'
                    ? widget.model.activeSlidingSeries?.id
                    : widget.model.activeSeries?.id;
                if (item.originalName.contains('Caisson') ||
                    item.originalName.contains('الصندوق') ||
                    item.originalName.contains('Kit') ||
                    item.originalName.contains('كيت')) {
                  // بناء صيغ متعددة لنفس المقاس (نقطة/فاصلة/مختصر) لزيادة فرصة التطابق النصي
                  String size = widget.model.shutterBoxHeight
                      .toInt()
                      .toString();
                  String sizeDot = size.length == 3
                      ? "${size.substring(0, 2)}.${size.substring(2)}"
                      : size;
                  String sizeComma = size.length == 3
                      ? "${size.substring(0, 2)},${size.substring(2)}"
                      : size;
                  String shortSize = size.length == 3
                      ? size.substring(0, 2)
                      : size;
                  sizeFilter =
                  " AND (name LIKE '%$size%' OR type LIKE '%$size%' OR name LIKE '%$sizeDot%' OR type LIKE '%$sizeDot%' OR name LIKE '%$sizeComma%' OR type LIKE '%$sizeComma%' OR name LIKE '%$shortSize%' OR type LIKE '%$shortSize%')";
                }
                final isSections = table == 'Sections';
                String whereClause;
                List<dynamic> queryArgs;
                if (table == 'Joints') {
                  if (activeSeriesIdForJoint != null) {
                    whereClause = '((LOWER(name) LIKE ? OR LOWER(type) LIKE ?) OR (name LIKE ? OR type LIKE ?)) AND '
                        '(series_id = ? OR (series_ids IS NOT NULL AND series_ids != \'\' AND \',\' || series_ids || \',\' LIKE ?) OR ((series_id IS NULL OR series_id = 0) AND (series_ids IS NULL OR series_ids = \'\')))'
                        ' AND (is_active = 1 OR is_active IS NULL)';
                    queryArgs = [
                      '%$keywordFr%',
                      '%$keywordFr%',
                      '%$keywordAr%',
                      '%$keywordAr%',
                      activeSeriesIdForJoint,
                      '%,' + activeSeriesIdForJoint.toString() + ',%',
                    ];
                  } else {
                    whereClause = '((LOWER(name) LIKE ? OR LOWER(type) LIKE ?) OR (name LIKE ? OR type LIKE ?)) AND (is_active = 1 OR is_active IS NULL)';
                    queryArgs = [
                      '%$keywordFr%',
                      '%$keywordFr%',
                      '%$keywordAr%',
                      '%$keywordAr%',
                    ];
                  }
                } else {
                  final seriesFilter = _buildSeriesFilterClause();
                  final bool applySeriesFilter = table == 'Accessories';
                  whereClause = isSections
                      ? '((LOWER(name) LIKE ? OR LOWER(type) LIKE ? OR LOWER(code) LIKE ?) OR (name LIKE ? OR type LIKE ? OR code LIKE ?)) $sizeFilter AND (is_active = 1 OR is_active IS NULL)'
                      : '((LOWER(name) LIKE ? OR LOWER(type) LIKE ?) OR (name LIKE ? OR type LIKE ?)) $sizeFilter${applySeriesFilter ? seriesFilter['clause'] : ''} AND (is_active = 1 OR is_active IS NULL)';
                  queryArgs = isSections
                      ? [
                          '%$keywordFr%',
                          '%$keywordFr%',
                          '%$keywordFr%',
                          '%$keywordAr%',
                          '%$keywordAr%',
                          //'%$keywordAr%',
                        ]
                      : [
                    '%$keywordFr%',
                    '%$keywordFr%',
                    '%$keywordAr%',
                    '%$keywordAr%',
                    if (applySeriesFilter) ...seriesFilter['args'],
                        ];
                }
                String? orderBy;
                if (table == 'Joints' && activeSeriesIdForJoint != null) {
                  orderBy = 'CASE WHEN series_id = $activeSeriesIdForJoint OR (series_ids IS NOT NULL AND series_ids != \'\' AND \',\' || series_ids || \',\' LIKE \'%,$activeSeriesIdForJoint,%\') THEN 0 ELSE 1 END ASC, id ASC';
                }
                // البحث الأساسي بالكلمة المفتاحية + فلتر المقاس (إن وُجد)
                res = await dbInstance.query(
                  table,
                  where: whereClause,
                  whereArgs: queryArgs,
                  orderBy: orderBy,
                  limit: 1,
                );
                // إذا لم يوجد تطابق مع فلتر المقاس، أعد البحث بدونه (نتيجة أعم)
                if (res.isEmpty && sizeFilter.isNotEmpty) {
                  final fallbackWhereClause = isSections
                      ? '((LOWER(name) LIKE ? OR LOWER(type) LIKE ? OR LOWER(code) LIKE ?) OR (name LIKE ? OR type LIKE ? OR code LIKE ?)) AND (is_active = 1 OR is_active IS NULL)'
                      : '((LOWER(name) LIKE ? OR LOWER(type) LIKE ?) OR (name LIKE ? OR type LIKE ?)) AND (is_active = 1 OR is_active IS NULL)';
                  res = await dbInstance.query(
                    table,
                    where: fallbackWhereClause,
                    whereArgs: queryArgs,
                    limit: 1,
                  );
                }
                // تصفية نتائج Sections حسب نوع العنصر (Rail vs Réducteur وغيرها)
                if (table == 'Sections' && res.isNotEmpty) {
                  final origLower = item.originalName.toLowerCase();
                  if (origLower.contains('rail') || origLower.contains('سكة') || origLower.contains('الري')) {
                    final railMatches = res.where((s) {
                      final t = (s['type'] ?? '').toString().toLowerCase();
                      final n = (s['name'] ?? '').toString().toLowerCase();
                      return (t == 'rail' || t.contains('rail') || n == 'rail' || n.startsWith('rail') || n.contains('سكة')) &&
                          !t.contains('frame') &&
                          !t.contains('cadre') &&
                          !n.contains('cadre') &&
                          !n.contains('إطار') &&
                          !n.contains('cadre 2 rail') &&
                          !n.contains('cadre 3 rail');
                    }).toList();
                    if (railMatches.isNotEmpty) res = railMatches;
                  } else if (origLower.contains('réducteur') ||
                      origLower.contains('ريديكتور') ||
                      origLower.contains('reducteur') ||
                      origLower.contains('مخفض')) {
                    final redMatches = res.where((s) {
                      final t = (s['type'] ?? '').toString().toLowerCase();
                      final n = (s['name'] ?? '').toString().toLowerCase();
                      final c = (s['code'] ?? '').toString().toLowerCase();
                      return (t.contains('reduct') ||
                              n.contains('reduct') ||
                              n.contains('مخفض') ||
                              n.contains('ريديكتور') ||
                              c.contains('67114')) &&
                          !t.contains('frame') &&
                          !t.contains('cadre') &&
                          !t.contains('rail') &&
                          !n.contains('cadre') &&
                          !n.contains('إطار') &&
                          !n.contains('rail') &&
                          !n.contains('سكة');
                    }).toList();
                    if (redMatches.isNotEmpty) {
                      res = redMatches;
                    } else {
                      final parcloseMatches = res.where((s) {
                        final t = (s['type'] ?? '').toString().toLowerCase();
                        final n = (s['name'] ?? '').toString().toLowerCase();
                        return (t.contains('parclose') || t.contains('reduct')) &&
                            !t.contains('frame') &&
                            !t.contains('cadre') &&
                            !t.contains('rail') &&
                            !n.contains('cadre') &&
                            !n.contains('إطار') &&
                            !n.contains('rail') &&
                            !n.contains('سكة');
                      }).toList();
                      if (parcloseMatches.isNotEmpty) res = parcloseMatches;
                    }
                  }
                }
              }
              if (res.isNotEmpty) {
                final mutableItem = Map<String, dynamic>.from(res.first);
                double price = 0.0;
                // حساب السعر حسب نوع الجدول (كل جدول له آلية تسعير حسب اللون مختلفة)
                if (table == 'Sections' && colorId != null) {
                  price = await SqlDatabase().getSectionPrice(
                    res.first['id'],
                    colorId,
                  );
                } else if (table == 'Accessories' && colorId != null) {
                  final colorPriceRes = await dbInstance.query(
                    'AccessoryColorPrices',
                    where: 'accessory_id = ? AND color_id = ?',
                    whereArgs: [res.first['id'], colorId],
                  );
                  if (colorPriceRes.isNotEmpty &&
                      _safeDouble(colorPriceRes.first['price']) > 0) {
                    price = _safeDouble(colorPriceRes.first['price']);
                  } else {
                    price = _safeDouble(
                      res.first['price_dzd'] ??
                          res.first['price_per_meter'] ??
                          res.first['price'],
                    );
                    if (price == 0) {
                      // إذا السعر ما زال صفر، ابحث عن أي سعر لوني آخر أكبر من صفر لهذا العنصر
                      final anyColorRes = await dbInstance.query(
                        'AccessoryColorPrices',
                        where: 'accessory_id = ? AND price > 0',
                        whereArgs: [res.first['id']],
                        limit: 1,
                      );
                      if (anyColorRes.isNotEmpty) {
                        price = _safeDouble(anyColorRes.first['price']);
                      }
                    }
                  }
                } else if (table == 'ShutterComponents' && colorId != null) {
                  final colorPriceRes = await dbInstance.query(
                    'ShutterColorPrices',
                    where: 'shutter_component_id = ? AND color_id = ?',
                    whereArgs: [res.first['id'], colorId],
                  );
                  if (colorPriceRes.isNotEmpty &&
                      _safeDouble(colorPriceRes.first['price']) > 0) {
                    price = _safeDouble(colorPriceRes.first['price']);
                  } else {
                    price = _safeDouble(
                      res.first['price_dzd'] ??
                          res.first['price_per_meter'] ??
                          res.first['price'],
                    );
                    if (price == 0) {
                      final anyColorRes = await dbInstance.query(
                        'ShutterColorPrices',
                        where: 'shutter_component_id = ? AND price > 0',
                        whereArgs: [res.first['id']],
                        limit: 1,
                      );
                      if (anyColorRes.isNotEmpty) {
                        price = _safeDouble(anyColorRes.first['price']);
                      }
                    }
                  }
                } else {
                  // لا يوجد لون محدد أو جدول Joints: استخدم السعر العام مباشرة
                  price = _safeDouble(
                    res.first['price_dzd'] ??
                        res.first['price_per_meter'] ??
                        res.first['price'],
                  );
                }
                mutableItem['calculated_price'] = price;
                widget.model.componentOverrides[item.originalName] =
                    mutableItem;
                if (mounted) setState(() {}); // إجبار الخانة على الظهور فورًا
              }
            }
          } catch (e) {} // تجاهل أي خطأ في معالجة عنصر ناقص واحد، وتابع البقية
        }
      }
      await _loadPricesFromDb(); // بعد كل ما سبق، أعد تحميل أسعار المتر الخطي/الستار من القاعدة
    } finally {
      if (mounted) {
        setState(() {}); // تحديث نهائي للواجهة بغض النظر عن نجاح أو فشل العمليات أعلاه
      }
    }
  }
  // ==========================================================================
  // initState: يُستدعى مرة واحدة عند إنشاء الشاشة
  // ==========================================================================
  @override
  void initState() {
    super.initState();
    // تهيئة كل متحكمات حقول النص
    _profitMarginController = TextEditingController();
    _pricePerSqmController = TextEditingController();
    _pricePerLinearMeterController = TextEditingController();
    _shutterSqmPriceController = TextEditingController();
    _torqueFactorController = TextEditingController();
    _loadCostSettings(); // تحميل إعدادات التسعير المحفوظة محليًا
    _loadPricesFromDb(); // تحميل الأسعار من قاعدة البيانات
    // تحديد الحالة الابتدائية للآلية (محرك/مانيفيل/حزام) والتونيل
    final isTunnel = widget.model.isCaissonTunnel;
    final isMotor = widget.model.shutterMechanism == 'محرك';
    final isCrankInit =
        widget.model.shutterMechanism == 'منايفال' ||
            widget.model.shutterMechanism == 'مانيفال' ||
            widget.model.shutterMechanism == 'مانيفر';
    // بناء الحالة الابتدائية لكل عناصر activeVariants دفعة واحدة
    activeVariants = {
      'Verrou Central': widget.model.useVerrouCentral,
      'System OB': widget.model.useSystemOB,
      'Demi System OB': widget.model.useDemiOB,
      'كيت (Kit)': false,
      'كيت فولي موتور (Kit Volet Moteur)': isTunnel ? false : isMotor,
      'كيت فولي مانيفر (Kit Volet Manivelle)': isTunnel ? false : isCrankInit,
      'كيت مانيفر (Kit Manivelle)': isTunnel ? false : isCrankInit,
      'كيت فولي (Kit Volet)': isTunnel ? false : (!isMotor && !isCrankInit),
      'كيت حزام (Kit Sangle)': false,
      'طانديم (Tandem)': isTunnel,
      'الامبو (Embout)': false,
      'سيبور رولمو (Support Roulement)': false,
      'سيبور موتور (Support Moteur)': isTunnel || isMotor,
      'أغطية الشفرات (Bouchons Lames)': isTunnel || isMotor,
    };
    // استدعاء الجلب الذكي فور فتح الشاشة (لملء كل المكونات المفقودة)
    _fetchDefaults();
    // الاستماع لأي تغيير في النموذج (مثلاً تغيير القياسات من شاشة أخرى) لإعادة رسم الواجهة
    widget.model.addListener(_onModelChanged);
    // مراقبة موضع التمرير الأفقي لإظهار/إخفاء العمود الثابت (overlay) عند التمرير أكثر من 150 بكسل
    _scrollController.addListener(() {
      final isScrolled = _scrollController.offset > 150;
      if (isScrolled != _isScrolled) {
        setState(() {
          _isScrolled = isScrolled;
        });
      }
    });
  }
  // دالة تُستدعى عند تغيّر النموذج من خارج هذه الشاشة، فقط تعيد بناء الواجهة
  void _onModelChanged() {
    if (mounted) {
      setState(() {});
    }
  }
  // ==========================================================================
  // dispose: تنظيف الموارد عند إغلاق الشاشة (إلغاء الاستماع، تحرير الكونترولرز)
  // ==========================================================================
  @override
  void dispose() {
    widget.model.removeListener(_onModelChanged);
    _scrollController.dispose();
    _profitMarginController.dispose();
    _pricePerSqmController.dispose();
    _pricePerLinearMeterController.dispose();
    _shutterSqmPriceController.dispose();
    _torqueFactorController.dispose();
    super.dispose();
  }
  // ==========================================================================
  // دالة: _loadCostSettings
  // تحميل إعدادات التسعير العامة (نسبة الربح، سعر المتر المربع، معامل العزم،
  // طريقة الحساب) من SharedPreferences، مع قيم افتراضية إن لم تكن محفوظة.
  // ==========================================================================
  Future<void> _loadCostSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _profitMargin = prefs.getDouble('app_profit_margin') ?? 0.0; // افتراضي 20%
      _pricePerSqm = prefs.getDouble('app_price_per_sqm') ?? 0.0; // افتراضي 00 دج/م²
      _torqueFactor = prefs.getDouble('shutter_torque_factor') ?? 1.5; // افتراضي 1.5
      // ملاحظة: سعر المتر الخطي يُحمَّل دائمًا من قاعدة البيانات وليس من SharedPreferences
      final methodIndex =
          prefs.getInt('app_cost_method') ?? CostMethod.percentage.index;
      _costMethod = CostMethod.values[methodIndex]; // تحويل الرقم المحفوظ إلى enum
      // مزامنة الكونترولرز مع القيم المحمّلة لعرضها في حقول الإدخال
      _profitMarginController.text = _profitMargin.toStringAsFixed(1);
      _pricePerSqmController.text = _pricePerSqm.toStringAsFixed(0);
      _pricePerLinearMeterController.text = '0';
      _torqueFactorController.text = _torqueFactor.toStringAsFixed(1);
    });
  }
  // ==========================================================================
  // دالة: _loadPricesFromDb
  // تحميل الأسعار الديناميكية من قاعدة البيانات: سعر المتر الخطي للسلسلة
  // النشطة، سعر متر مربع الستار (بمطابقة ذكية للاسم/النوع)، وأجور التركيب
  // الخاصة (محرك/OB/Demi OB/Verrou).
  // ==========================================================================
  Future<void> _loadPricesFromDb() async {
    final dbInstance = await SqlDatabase().db;
    if (dbInstance == null) return;
    double linearMeterPrice = 0.0;
    double shutterSqmPrice = 0.0;
    double moteurInstall = 0.0;
    double obInstall = 0.0;
    double demiObInstall = 0.0;
    double verrouInstall = 0.0;
    final colorId = widget.model.selectedDbColor?['id'] as int?;
    final seriesId = widget.model.systemMode == 'sliding'
        ? widget.model.activeSlidingSeries?.id
        : widget.model.activeSeries?.id;
    // 1. سعر المتر الخطي: أولًا من جدول أسعار السلسلة حسب اللون، وإلا من السعر العام في جدول Series
    if (seriesId != null) {
      if (colorId != null) {
        linearMeterPrice = await SqlDatabase().getSeriesColorPrice(
          seriesId,
          colorId,
        );
      }
      if (linearMeterPrice == 0.0) {
        final seriesRows = await dbInstance.query(
          'Series',
          columns: ['price_per_meter'],
          where: 'id = ?',
          whereArgs: [seriesId],
          limit: 1,
        );
        if (seriesRows.isNotEmpty) {
          linearMeterPrice =
              (seriesRows.first['price_per_meter'] as num?)?.toDouble() ?? 0.0;
        }
      }
      if (linearMeterPrice == 0.0 && colorId != null) {
        // Fallback: search SeriesColorPrices for ANY color price for this series
        final anyColorRes = await dbInstance.query(
          'SeriesColorPrices',
          where: 'series_id = ? AND price > 0',
          whereArgs: [seriesId],
          limit: 1,
        );
        if (anyColorRes.isNotEmpty) {
          linearMeterPrice = (anyColorRes.first['price'] as num?)?.toDouble() ?? 0.0;
        }
      }
    }
    // 2. سعر المتر المربع للستار — يحتاج مطابقة ذكية للاسم لتفادي مشكلة رجوع سعر صفر
    String actualBladeName = ''; // اسم الشريحة الفعلي المستخدم
    String subtype = 'normal'; // نوع الشريحة (extruded/normal)
    final lamesOverride = widget.model.componentOverrides['الشرائح (Lames)'];
    if (lamesOverride != null) {
      actualBladeName = (lamesOverride['name'] ?? '').toString();
      subtype = (lamesOverride['shutter_subtype'] ?? 'normal').toString();
    } else if (widget.model.shutterLame.isNotEmpty) {
      actualBladeName = widget.model.shutterLame;
    }
    if (actualBladeName.isNotEmpty || subtype.isNotEmpty) {
      // دالة داخلية: توحيد صيغة النص (حروف صغيرة، إزالة رموز فرنسية/عربية خاصة والمسافات) لتسهيل المقارنة
      String normalize(String s) {
        return s
            .toLowerCase()
            .replaceAll('é', 'e')
            .replaceAll('è', 'e')
            .replaceAll('ê', 'e')
            .replaceAll('أ', 'ا')
            .replaceAll('إ', 'ا')
            .replaceAll('آ', 'ا')
            .replaceAll(' ', '')
            .trim();
      }
      String normActualName = normalize(actualBladeName);
      String normSubtype = normalize(subtype);
      // جلب كل أسعار المتر المربع للستار من القاعدة، ثم مطابقتها يدويًا في Dart (أدق من SQL LIKE هنا)
      final allSqmPrices = await dbInstance.query('ShutterSqmPrices');
      double fallbackPrice = 0.0; // سعر احتياطي مبني على النوع فقط (لو ما وجد تطابق دقيق بالاسم)
      for (var row in allSqmPrices) {
        String dbBladeType = row['blade_type']?.toString() ?? '';
        String normDbBladeType = normalize(dbBladeType);
        int dbColorId = row['color_id'] as int? ?? 0;
        // اللون يطابق إذا: لا يوجد لون محدد، أو السعر عام (color_id=0)، أو نفس اللون بالضبط
        bool colorMatches =
            (colorId == null) || (dbColorId == 0) || (dbColorId == colorId);
        if (!colorMatches) continue;
        // مطابقة الاسم: تطابق تام أو احتواء جزئي في أي اتجاه
        bool nameMatches =
            normActualName == normDbBladeType ||
                normActualName.contains(normDbBladeType) ||
                normDbBladeType.contains(normActualName);
        bool subtypeMatches = normSubtype == normDbBladeType;
        if (nameMatches && normDbBladeType.isNotEmpty) {
          shutterSqmPrice = _safeDouble(row['price_per_sqm']);
          print("✅ [DEBUG] تم جلب سعر الشفرة الدقيق: $shutterSqmPrice");
          if (dbColorId != 0) break; // الأولوية للسعر المرتبط بلون محدد (نتوقف فورًا)
        } else if (subtypeMatches && fallbackPrice == 0.0) {
          fallbackPrice = _safeDouble(row['price_per_sqm']); // احفظه كخطة بديلة فقط
        }
      }
      // إذا لم يُوجد تطابق دقيق بالاسم، استخدم السعر الاحتياطي المبني على النوع (extruded/normal)
      if (shutterSqmPrice == 0.0 && fallbackPrice > 0.0) {
        shutterSqmPrice = fallbackPrice;
        print("⚠️ [DEBUG] استخدم سعر الخطة البديلة (النوع): $shutterSqmPrice");
      }
      if (shutterSqmPrice == 0.0) {
        // Fallback to the default price from ShutterComponents table
        final compRows = await dbInstance.query(
          'ShutterComponents',
          columns: ['price'],
          where: 'LOWER(name) = ? OR name = ?',
          whereArgs: [actualBladeName.toLowerCase(), actualBladeName],
          limit: 1,
        );
        if (compRows.isNotEmpty) {
          shutterSqmPrice = _safeDouble(compRows.first['price']);
          print("✅ [DEBUG] تم جلب السعر الافتراضي للشفرة من ShutterComponents: $shutterSqmPrice");
        }
      }
    }
    // 3. تحميل أجور التركيب الخاصة (تُخزَّن كصفوف خاصة داخل ShutterSqmPrices بـ blade_type مميز و color_id=0)
    final moteurRes = await dbInstance.query(
      'ShutterSqmPrices',
      columns: ['price_per_sqm'],
      where: 'blade_type = ? AND color_id = ?',
      whereArgs: ['Moteur_Install', 0],
      limit: 1,
    );
    if (moteurRes.isNotEmpty) {
      moteurInstall =
          (moteurRes.first['price_per_sqm'] as num?)?.toDouble() ?? 0.0;
    }
    final obRes = await dbInstance.query(
      'ShutterSqmPrices',
      columns: ['price_per_sqm'],
      where: 'blade_type = ? AND color_id = ?',
      whereArgs: ['OB_Install', 0],
      limit: 1,
    );
    if (obRes.isNotEmpty) {
      obInstall = (obRes.first['price_per_sqm'] as num?)?.toDouble() ?? 0.0;
    }
    final demiObRes = await dbInstance.query(
      'ShutterSqmPrices',
      columns: ['price_per_sqm'],
      where: 'blade_type = ? AND color_id = ?',
      whereArgs: ['DemiOB_Install', 0],
      limit: 1,
    );
    if (demiObRes.isNotEmpty) {
      demiObInstall =
          (demiObRes.first['price_per_sqm'] as num?)?.toDouble() ?? 0.0;
    }
    final verrouRes = await dbInstance.query(
      'ShutterSqmPrices',
      columns: ['price_per_sqm'],
      where: 'blade_type = ? AND color_id = ?',
      whereArgs: ['Verrou_Install', 0],
      limit: 1,
    );
    if (verrouRes.isNotEmpty) {
      verrouInstall =
          (verrouRes.first['price_per_sqm'] as num?)?.toDouble() ?? 0.0;
    }
    // تحديث الحالة (State) بكل الأسعار المحمّلة، وتحديث نصوص الحقول إذا لم يكن هناك تعديل يدوي (override)
    if (mounted) {
      setState(() {
        _pricePerLinearMeterFromDb = linearMeterPrice;
        _shutterSqmPriceFromDb = shutterSqmPrice; // ⭐️ التحديث الحاسم لسعر الستار
        _moteurInstallFee = moteurInstall;
        _obInstallFee = obInstall;
        _demiObInstallFee = demiObInstall;
        _verrouInstallFee = verrouInstall;
        if (_pricePerLinearMeterOverride == null) {
          _pricePerLinearMeterController.text = linearMeterPrice
              .toStringAsFixed(0);
        }
        if (_shutterSqmPriceOverride == null) {
          _shutterSqmPriceController.text = shutterSqmPrice.toStringAsFixed(0);
        }
      });
    }
  }
  // ==========================================================================
  // دالة: _handleKitSelection
  // تُستدعى عند اختيار المستخدم كيتًا مختلفًا يدويًا من القائمة المنسدلة.
  // تحدد نوع الآلية (محرك/مانيفيل/حزام) من اسم الكيت المختار، وتحدّث النموذج
  // والـ overrides بما يتوافق مع الكيت الجديد.
  // ==========================================================================
  Future<void> _handleKitSelection(Map<String, dynamic> selectedKit) async {
    final mutableSelected = Map<String, dynamic>.from(selectedKit);
    mutableSelected['calculated_price'] = _safeDouble(
      mutableSelected['price_dzd'] ?? mutableSelected['price'],
    );
    final selectedName = (mutableSelected['name'] ?? '')
        .toString()
        .toLowerCase();
    // Check if it is a sliding system kit
    final bool isSliding = widget.model.systemMode == 'sliding';
    if (isSliding) {
      String targetKey = 'كيت 67000 (Kit 67000)';
       if (selectedName.contains('40000')) {
        targetKey = 'كيت 40000 (Kit 40000)';
      } else if (selectedName.contains('67000')) {
        targetKey = 'كيت 67000 (Kit 67000)';
      } else {
        final String sName = widget.model.activeSlidingSeries?.name.toLowerCase() ?? '';
         if (sName.contains('40000')) {
          targetKey = 'كيت 40000 (Kit 40000)';
        } else {
          targetKey = 'كيت 67000 (Kit 67000)';
        }
      }
      final slidingKeys = [
        'كيت 67000 (Kit 67000)',
        'كيت 40000 (Kit 40000)',
      ];
      for (final k in slidingKeys) {
        widget.model.componentOverrides.remove(k);
      }
      widget.model.componentOverrides[targetKey] = mutableSelected;
      await _fetchDefaults();
      if (mounted) {
        setState(() {
          widget.model.refreshUI();
        });
      }
      return;
    }
    String newMech; // الآلية الجديدة المستنتجة من اسم الكيت
    String targetKitKey; // المفتاح الصحيح لحفظ هذا الكيت تحته في componentOverrides
    // استنتاج نوع الآلية من اسم الكيت (محرك/مانيفيل مع فولي أو بدون/حزام)
    if (selectedName.contains('moteur') || selectedName.contains('محرك')) {
      newMech = 'محرك';
      targetKitKey = 'كيت فولي موتور (Kit Volet Moteur)';
    } else if (selectedName.contains('manivelle') ||
        selectedName.contains('مانيفال') ||
        selectedName.contains('مانيفر')) {
      newMech = 'مانيفال';
      if (selectedName.contains('volet') || selectedName.contains('فولي')) {
        targetKitKey = 'كيت فولي مانيفر (Kit Volet Manivelle)';
      } else {
        targetKitKey = 'كيت مانيفر (Kit Manivelle)';
      }
    } else {
      newMech = 'حزام';
      if (selectedName.contains('sangle') || selectedName.contains('حزام')) {
        targetKitKey = 'كيت حزام (Kit Sangle)';
      } else {
        targetKitKey = 'كيت فولي (Kit Volet)';
      }
    }
    // تحديث آلية الستار في النموذج
    widget.model.shutterMechanism = newMech;
    // مسح كل الكيتات القديمة من الـ overrides (لتفادي بقاء كيت قديم متضارب)
    final kitKeys = [
      'كيت (Kit)',
      'كيت فولي موتور (Kit Volet Moteur)',
      'كيت فولي مانيفر (Kit Volet Manivelle)',
      'كيت مانيفر (Kit Manivelle)',
      'كيت فولي (Kit Volet)',
      'كيت حزام (Kit Sangle)',
    ];
    for (final k in kitKeys) {
      widget.model.componentOverrides.remove(k);
    }
    // حفظ الكيت المختار تحت المفتاح الصحيح الجديد
    widget.model.componentOverrides[targetKitKey] = mutableSelected;
    // إعادة حساب الافتراضيات (لأن تغيير الآلية يؤثر على مكونات أخرى كثيرة) وتحديث الواجهة
    await widget.model.updateShutterDefaultsIfNeeded();
    await _fetchDefaults();
    if (mounted) {
      setState(() {
        widget.model.refreshUI();
      });
    }
  }
  // ==========================================================================
  // دالة: _resolveDynamicProductPrice
  // تبحث عن سعر منتج بالاسم في جدولي Accessories ثم ShutterComponents،
  // مع مراعاة السعر الخاص باللون إن وُجد. تُستخدم لتحديث أسعار عناصر الكيت.
  // ==========================================================================
  Future<double?> _resolveDynamicProductPrice(
      Database db,
      String productName,
      int? colorId,
      ) async {
    // 1. البحث في جدول Accessories بالاسم بالضبط
    final accRows = await db.query(
      'Accessories',
      columns: ['id', 'price'],
      where: 'name = ? AND (is_active = 1 OR is_active IS NULL)',
      whereArgs: [productName],
      limit: 1,
    );
    if (accRows.isNotEmpty) {
      final accId = accRows.first['id'] as int;
      final defaultPrice = _safeDouble(accRows.first['price']);
      if (colorId != null) {
        final colorPriceRes = await db.query(
          'AccessoryColorPrices',
          columns: ['price'],
          where: 'accessory_id = ? AND color_id = ?',
          whereArgs: [accId, colorId],
          limit: 1,
        );
        if (colorPriceRes.isNotEmpty) {
          final p = _safeDouble(colorPriceRes.first['price']);
          if (p > 0) return p; // السعر اللوني له الأولوية إذا كان أكبر من صفر
        }
      }
      return defaultPrice;
    }
    // 2. إذا لم يوجد في Accessories، ابحث في جدول ShutterComponents
    final shutRows = await db.query(
      'ShutterComponents',
      columns: ['id', 'price'],
      where: 'name = ? AND (is_active = 1 OR is_active IS NULL)',
      whereArgs: [productName],
      limit: 1,
    );
    if (shutRows.isNotEmpty) {
      final shutId = shutRows.first['id'] as int;
      final defaultPrice = _safeDouble(shutRows.first['price']);
      if (colorId != null) {
        final colorPriceRes = await db.query(
          'ShutterColorPrices',
          columns: ['price'],
          where: 'shutter_component_id = ? AND color_id = ?',
          whereArgs: [shutId, colorId],
          limit: 1,
        );
        if (colorPriceRes.isNotEmpty) {
          final p = _safeDouble(colorPriceRes.first['price']);
          if (p > 0) return p;
        }
      }
      return defaultPrice;
    }
    return null; // المنتج غير موجود في أي من الجدولين
  }
  // حفظ إعداد تسعير رقمي واحد في SharedPreferences (بالمفتاح المعطى)
  Future<void> _saveCostSetting(String key, double value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(key, value);
  }
  // حفظ طريقة الحساب المختارة (percentage/squareMeter/linearMeter) في SharedPreferences
  Future<void> _saveCostMethod(CostMethod method) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('app_cost_method', method.index);
  }
  // ==========================================================================
  // دالة: _handleVariantToggle
  // تُستدعى عند تفعيل/تعطيل أي Checkbox لعنصر اختياري (كيت، سيبور، طانديم...).
  // تحتوي منطق "استبعاد متبادل" بين المجموعات (مثلاً تفعيل الطانديم يعطّل
  // الكيتات والامبو تلقائيًا لأنها غير متوافقة معه).
  // ==========================================================================
  void _handleVariantToggle(String name, String? group, bool value) {
    setState(() {
      activeVariants[name] = value; // تحديث الحالة الأساسية أولًا
      final isTunnel = widget.model.isCaissonTunnel;
      // تحقق: هل الاسم هو أحد مفاتيح الكيتات؟
      final isAnyKitKey =
          name == 'كيت (Kit)' ||
              name == 'كيت فولي موتور (Kit Volet Moteur)' ||
              name == 'كيت فولي مانيفر (Kit Volet Manivelle)' ||
              name == 'كيت مانيفر (Kit Manivelle)' ||
              name == 'كيت حزام (Kit Sangle)' ||
              name == 'كيت فولي (Kit Volet)';
      if (name == 'Verrou Central') {
        widget.model.toggleVerrouCentral(value); // تفويض المنطق لدالة النموذج نفسه
      } else if (name == 'System OB') {
        widget.model.toggleSystemOB(value);
      } else if (name == 'Demi System OB') {
        widget.model.toggleDemiOB(value);
      } else if (isAnyKitKey) {
        // تفعيل أي كيت يعطّل تلقائيًا: الامبو، سيبور رولمو، سيبور موتور، الطانديم (غير متوافقين)
        if (value) {
          activeVariants['الامبو (Embout)'] = false;
          activeVariants['سيبور رولمو (Support Roulement)'] = false;
          activeVariants['سيبور موتور (Support Moteur)'] = false;
          activeVariants['طانديم (Tandem)'] = false;
        }
      } else if (name == 'طانديم (Tandem)') {
        // تفعيل الطانديم يعطّل الامبو والسيبور رولمو وكل الكيتات
        if (value) {
          activeVariants['الامبو (Embout)'] = false;
          activeVariants['سيبور رولمو (Support Roulement)'] = false;
          activeVariants['كيت (Kit)'] = false;
          activeVariants['كيت فولي موتور (Kit Volet Moteur)'] = false;
          activeVariants['كيت فولي مانيفر (Kit Volet Manivelle)'] = false;
          activeVariants['كيت مانيفر (Kit Manivelle)'] = false;
          activeVariants['كيت حزام (Kit Sangle)'] = false;
          activeVariants['كيت فولي (Kit Volet)'] = false;
        }
      } else if (name == 'الامبو (Embout)' ||
          name == 'سيبور رولمو (Support Roulement)') {
        // الامبو وسيبور رولمو مرتبطان: تفعيل أحدهما يفعّل الآخر تلقائيًا ويعطّل الطانديم وكل الكيتات
        if (value) {
          activeVariants['الامبو (Embout)'] = true;
          activeVariants['سيبور رولمو (Support Roulement)'] = true;
          activeVariants['طانديم (Tandem)'] = false;
          activeVariants['كيت (Kit)'] = false;
          activeVariants['كيت فولي موتور (Kit Volet Moteur)'] = false;
          activeVariants['كيت فولي مانيفر (Kit Volet Manivelle)'] = false;
          activeVariants['كيت مانيفر (Kit Manivelle)'] = false;
          activeVariants['كيت حزام (Kit Sangle)'] = false;
          activeVariants['كيت فولي (Kit Volet)'] = false;
        } else {
          activeVariants['الامبو (Embout)'] = false;
          activeVariants['سيبور رولمو (Support Roulement)'] = false;
        }
      } else if (name == 'سيبور موتور (Support Moteur)') {
        // تفعيل سيبور موتور يعطّل كل الكيتات
        if (value) {
          activeVariants['كيت (Kit)'] = false;
          activeVariants['كيت فولي موتور (Kit Volet Moteur)'] = false;
          activeVariants['كيت فولي مانيفر (Kit Volet Manivelle)'] = false;
          activeVariants['كيت مانيفر (Kit Manivelle)'] = false;
          activeVariants['كيت حزام (Kit Sangle)'] = false;
          activeVariants['كيت فولي (Kit Volet)'] = false;
        }
      } else if (name == 'أغطية الشفرات (Bouchons Lames)') {
        // في حالة التونيل، أغطية الشفرات إلزامية دائمًا (لا يمكن تعطيلها)
        if (isTunnel) {
          activeVariants['أغطية الشفرات (Bouchons Lames)'] = true;
        }
      }
      // مزامنة نهائية: إعادة قراءة الحالة الفعلية من النموذج (احتياطًا لأي تعارض)
      activeVariants['Verrou Central'] = widget.model.useVerrouCentral;
      activeVariants['System OB'] = widget.model.useSystemOB;
      activeVariants['Demi System OB'] = widget.model.useDemiOB;
      if (isTunnel) {
        activeVariants['أغطية الشفرات (Bouchons Lames)'] = true;
      }
    });
  }
  // ==========================================================================
  // build: الدالة الرئيسية لبناء واجهة الشاشة كاملة
  // ==========================================================================
  @override
  Widget build(BuildContext context) {
    final lang = Provider.of<AppSettingsProvider>(context).language;
    // توليد قائمة المكونات (BOM) الحالية بناءً على النموذج والحالة النشطة
    final items = ComponentCalculator.generateBom(
      widget.model,
      activeVariants,
      kitBundleData: _kitBundleData,
      kitPerLeafMap: _kitPerLeafMap,
    );
    return Scaffold(
      appBar: AppBar(
        title: Text(
          Localization.translate('الالكمية والتكلفة', lang),
        ),
      ), // شريط العنوان العلوي
      body: SingleChildScrollView(
        scrollDirection: Axis.vertical, // تمرير رأسي لكامل محتوى الشاشة
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // تحذير ارتفاع الستار (إن وُجد) — يظهر فقط إذا كان هناك تحذير في النموذج
            if (widget.model.shutterHeightWarning != null) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  border: Border.all(color: Colors.red.shade200),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.warning_amber_rounded,
                      color: Colors.red.shade700,
                      size: 24,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        widget.model.shutterHeightWarning!, // نص التحذير القادم من النموذج
                        style: TextStyle(
                          color: Colors.red.shade900,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 10),
            // رسم شكل النافذة (CustomPaint) بحجم مصغّر لعرض بصري سريع
            Center(
              child: SizedBox(
                width: 250,
                height: 250,
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: FittedBox(
                    fit: BoxFit.contain,
                    child: CustomPaint(
                      painter: WindowPainter(model: widget.model), // الرسام المخصص
                      size: Size(
                        widget.model.width.toDouble(),
                        widget.model.height.toDouble(),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            const Divider(height: 1),
            // ---- شريط مؤشر توفر "لايت كيت" مع أبعاد النافذة (دالة فورية IIFE) ----
            (() {
              // هل توجد أي حزمة كيت اسمها يحتوي "light/لايت/ليت" ضمن الأنظمة العامة (kit bundles)
              final hasLightKitSystem = _kitBundleData.keys.any(
                    (key) =>
                key.toLowerCase().contains('light') ||
                    key.contains('لايت') ||
                    key.contains('ليت'),
              );
              // هل يوجد حاليًا كيت مفعّل من هذا النوع ضمن عناصر BOM الفعلية
              final activeKits = items
                  .where((i) => i.isActive && i.kitGroupName != null)
                  .map((i) => i.kitGroupName!)
                  .toSet();
              final isLightKitSystemActive = activeKits.any(
                    (name) =>
                name.toLowerCase().contains('light') ||
                    name.contains('لايت') ||
                    name.contains('ليت'),
              );
              // تحقق مماثل لكيتات الستار المباشرة (وليس أنظمة الكيت العامة)
              bool isShutterKitLight = false;
              bool isShutterKitActive = false;
              final isMotor = widget.model.shutterMechanism == 'محرك';
              final kitKeysToCheck = isMotor
                  ? ['كيت فولي موتور (Kit Volet Moteur)']
                  : [
                'كيت فولي مانيفر (Kit Volet Manivelle)',
                'كيت مانيفر (Kit Manivelle)',
              ];
              for (var key in kitKeysToCheck) {
                final shutterKit = widget.model.componentOverrides[key];
                if (shutterKit != null) {
                  final shutterKitName = shutterKit['name']?.toString() ?? '';
                  if (shutterKitName.toLowerCase().contains('light') ||
                      shutterKitName.contains('لايت') ||
                      shutterKitName.contains('ليت')) {
                    isShutterKitLight = true;
                  }
                }
                if (activeVariants[key] == true) {
                  isShutterKitActive = true;
                }
              }
              // تجميع النتيجة النهائية: هل يوجد لايت كيت أصلًا، وهل هو مفعّل حاليًا
              final isLightKitActive =
                  isLightKitSystemActive ||
                      (isShutterKitActive && isShutterKitLight);
              final hasLightKit = hasLightKitSystem || isShutterKitLight;
              // بناء الشريط نفسه: لون مختلف حسب الحالة (أخضر=مفعّل، أزرق=متاح، رمادي=غير متاح)
              final isDark = Theme.of(context).brightness == Brightness.dark;
              final lang = Provider.of<AppSettingsProvider>(context, listen: false).language;
              return Container(
                margin: const EdgeInsets.symmetric(
                  horizontal: 16.0,
                  vertical: 8.0,
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14.0,
                  vertical: 10.0,
                ),
                decoration: BoxDecoration(
                  color: isLightKitActive
                      ? (isDark ? Colors.green.shade900.withValues(alpha: 0.3) : Colors.green.shade50)
                      : (hasLightKit
                      ? (isDark ? Colors.blue.shade900.withValues(alpha: 0.3) : Colors.blue.shade50)
                      : (isDark ? Colors.blueGrey.shade900.withValues(alpha: 0.3) : Colors.blueGrey.shade50)),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isLightKitActive
                        ? (isDark ? Colors.green.shade700 : Colors.green.shade200)
                        : (hasLightKit
                        ? (isDark ? Colors.blue.shade700 : Colors.blue.shade200)
                        : (isDark ? Colors.blueGrey.shade700 : Colors.blueGrey.shade200)),
                  ),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // أيقونة وأبعاد النافذة (عرض × ارتفاع)
                        Icon(
                          Icons.straighten,
                          color: isDark ? Colors.white60 : Colors.blueGrey.shade500,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        RichText(
                          text: TextSpan(
                            style: TextStyle(
                              fontSize: 14,
                              color: isDark ? Colors.white70 : Colors.blueGrey.shade800,
                              fontWeight: FontWeight.bold,
                            ),
                            children: [
                              TextSpan(text: '${Localization.translate('العرض:', lang)} '),
                              TextSpan(
                                text: '${widget.model.width.toStringAsFixed(0)} mm',
                                style: TextStyle(
                                  color: isDark ? Colors.white : const Color(0xFF1A237E),
                                  fontSize: 15,
                                ),
                              ),
                              TextSpan(
                                text: '  ×  ',
                                style: TextStyle(
                                  color: Colors.blueGrey.shade400,
                                  fontWeight: FontWeight.normal,
                                ),
                              ),
                              TextSpan(text: '${Localization.translate('الارتفاع:', lang)} '),
                              TextSpan(
                                text:
                                '${widget.model.height.toStringAsFixed(0)} mm',
                                style: TextStyle(
                                  color: isDark ? Colors.white : const Color(0xFF1A237E),
                                  fontSize: 15,
                                ),
                              ),
                            ],
                          ),
                        ),
                        // مؤشر اللايت كيت (يظهر فقط إذا كان متاحًا أصلًا)
                        if (hasLightKit) ...[
                          const SizedBox(width: 12),
                          Container(
                            width: 1,
                            height: 20,
                            color: Colors.blueGrey.shade200,
                          ),
                          const SizedBox(width: 12),
                          Icon(
                            isLightKitActive
                                ? Icons.check_circle // أخضر = مفعّل فعليًا
                                : Icons.info_outline, // أزرق = متاح لكن غير مفعّل
                            color: isLightKitActive ? Colors.green : Colors.blue,
                            size: 18,
                          ),
                        ],
                      ],
                    ),
                    if (widget.model.systemMode == 'sliding') (() {
                      final hasSlidingSash = widget.model.zones.any((z) => z.content == ZoneContent.slidingSash);
                      if (!hasSlidingSash) return const SizedBox.shrink();
                      final useClassicHandle = widget.model.zones.any((z) => z.content == ZoneContent.slidingSash && z.useClassicHandle == true);
                      return Column(
                        children: [
                          const SizedBox(height: 6),
                          Container(
                            height: 1,
                            color: Colors.blueGrey.shade100.withValues(alpha: 0.5),
                          ),
                          const SizedBox(height: 6),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.lock_outline_rounded,
                                color: Colors.blueGrey.shade500,
                                size: 16,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                '${Localization.translate('نوع القفل:', lang)} ',
                                style: TextStyle(
                                  fontFamily: 'Cairo',
                                  fontSize: 12,
                                  color: Colors.blueGrey.shade700,
                                ),
                              ),
                              Text(
                                useClassicHandle
                                    ? Localization.translate('مقبض كلاسيكي (فتح)', lang)
                                    : '${Localization.translate('مقبض منزلق (جرار)', lang)} / ${Localization.translate('أودراماتيك', lang)}',
                                style: const TextStyle(
                                  fontFamily: 'Cairo',
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF1A237E),
                                ),
                              ),
                            ],
                          ),
                        ],
                      );
                    })(),
                  ],
                ),
              );
            })(), // استدعاء الدالة الفورية مباشرة
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 8.0,
                vertical: 8.0,
              ),
              child: _buildUnifiedTable(items), // بناء الجدول الرئيسي بكل الأقسام
            ),
            const SizedBox(height: 100), // مساحة فارغة أسفل الجدول حتى لا يغطيها الشريط السفلي
          ],
        ),
      ),
      bottomNavigationBar: _buildBottomBar(items), // الشريط السفلي الثابت (السعر النهائي وزر الحفظ)
    );
  }
  // ==========================================================================
  // دالة: _calculateTotals ⭐
  // الغرض: حساب مجاميع التكلفة وسعر البيع لكل قسم (بروفيلات/زجاج/ستار/إكسسوارات)
  // والمجموع الكلي، حسب طريقة الحساب المختارة (نسبة مئوية/متر مربع/متر خطي).
  // ==========================================================================
  Map<String, Map<String, double>> _calculateTotals(List<BomItem> items) {
    double profileCost = 0.0; // إجمالي تكلفة البروفيلات
    double glassCost = 0.0; // إجمالي تكلفة الزجاج
    double shutterCost = 0.0; // إجمالي تكلفة الستار وملحقاته
    double accessoryCost = 0.0; // إجمالي تكلفة الإكسسوارات
    double accessorySellingCost = 0.0; // جزء من تكلفة الإكسسوارات المحدد كـ "قابل للربح" (is_selling_calculated)
    double jointCost = 0.0; // إجمالي تكلفة الجوينات
    double mainProfileMeters = 0.0; // إجمالي الأمتار الخطية للبروفيلات الرئيسية (إطار/ظلفة/تقسيم/باتمو)
    double otherProfileCost = 0.0; // تكلفة البروفيلات الأخرى (غير محسوبة بالمتر الخطي)
    final activeItems = items.where((i) => i.isActive).toList(); // فقط العناصر المفعّلة تدخل الحساب
    // دالة داخلية: تحدد هل العنصر ملحق ستار عادي (وليس الشريحة نفسها أو غطاء الشفرات)
    bool isShutterAccessory(BomItem i) {
      if (i.category != 'shutter') return false;
      final nameLower = i.originalName.toLowerCase();
      if (i.originalName == 'الشرائح (Lames)') return false; // الشريحة نفسها تُستثنى من هذا التصنيف
      if (nameLower.contains('bouchons lames') ||
          nameLower.contains('bouchon lame') ||
          i.originalName.contains('أغطية الشفرات')) {
        return false; // غطاء الشفرات له معالجة خاصة أدناه
      }
      return true;
    }
    // دالة داخلية: تحدد هل العنصر هو "غطاء شفرات" تحديدًا
    bool isBouchonLame(BomItem i) =>
        i.originalName.contains('أغطية الشفرات') ||
            i.originalName.toLowerCase().contains('bouchons lames') ||
            i.originalName.toLowerCase().contains('bouchon lame');
    // الحلقة الرئيسية: تصنيف كل عنصر مفعّل حسب فئته وتجميع تكلفته في المتغيرات أعلاه
    for (var item in activeItems) {
      if (item.category == 'profile') {
        profileCost += item.total; // إضافة تكلفة كل بروفيل إلى الإجمالي العام
        final nameLower = item.originalName.toLowerCase();
        // تصنيف نوع البروفيل بالاعتماد على اسمه (عربي/فرنسي)
        final isFrame =
            nameLower.contains('إطار') ||
                nameLower.contains('cadre') ||
                nameLower.contains('frame');
        final isSash =
            nameLower.contains('درفة') ||
                nameLower.contains('ouvrant') ||
                nameLower.contains('sash');
        final isMullion =
            nameLower.contains('تقسيم') || nameLower.contains('mullion');
        final isBatmo =
            nameLower.contains('باتمو') ||
                nameLower.contains('batmo') ||
                nameLower.contains('batbo') ||
                nameLower.contains('باتبو');
        final isRenfort =
            nameLower.contains('حديد') || nameLower.contains('renfort');
        final isPareClose =
            nameLower.contains('pare-close') ||
                nameLower.contains('pareclose') ||
                nameLower.contains('pare close');
        if (isRenfort || isPareClose) {
          // الحديد والباركلوز يُضافان فقط لإجمالي التكلفة العامة (لا يدخلان حساب الأمتار الخطية الرئيسية)
        } else if (isFrame || isSash || isMullion || isBatmo) {
          // البروفيلات الرئيسية: نجمع أمتارها الخطية لاستخدامها لاحقًا في طريقة "سعر المتر الخطي"
          if (item.pieces != null) {
            mainProfileMeters += item.pieces!.fold<double>(
              0.0,
                  (sum, p) => sum + p,
            ); // جمع أطوال كل القطع المقصوصة لهذا العنصر
          } else if (item.length != null) {
            mainProfileMeters += (item.length! / 1000.0) * item.quantity; // تحويل من مم إلى متر × الكمية
          }
        } else {
          otherProfileCost += item.total; // بروفيلات أخرى غير مصنّفة كرئيسية
        }
      } else if (item.category == 'glass' || item.category == 'panneau') {
        glassCost += item.total;
      } else if (item.category == 'joint') {
        jointCost += item.total;
      } else if (item.category == 'shutter' ||
          isShutterAccessory(item) ||
          isBouchonLame(item)) {
        // كل ما يخص الستار (ملحقاته) يُجمع هنا ليظهر شريط الستار بشكل صحيح
        shutterCost += item.total;
      } else if (item.category == 'accessory' || item.category == 'other') {
        // كل الإكسسوارات العامة (مقابض، مفاصل...) تُجمع هنا
        accessoryCost += item.total;
        final override = widget.model.componentOverrides[item.originalName];
        // إذا كان العنصر معلَّمًا كـ "قابل لإضافة هامش ربح"، أضفه لتكلفة البيع القابلة للربح
        if (override != null && override['is_selling_calculated'] == 1) {
          accessorySellingCost += item.total;
        }
      }
    }
    // أجور تركيب خاصة (System OB, Demi OB, Verrou) تُضاف مرة واحدة لكل قطعة (× الكمية الكلية)
    double specialAccessoryInstallFees = 0.0;
    for (var item in activeItems) {
      if (item.category == 'accessory') {
        final nameLower = item.originalName.toLowerCase();
        if (nameLower.contains('system ob') ||
            item.originalName == 'System OB') {
          specialAccessoryInstallFees += _obInstallFee * widget.model.quantity;
        } else if (nameLower.contains('demi ob') ||
            item.originalName == 'Demi System OB') {
          specialAccessoryInstallFees +=
              _demiObInstallFee * widget.model.quantity;
        } else if (nameLower.contains('verrou') ||
            item.originalName == 'Verrou Central') {
          specialAccessoryInstallFees +=
              _verrouInstallFee * widget.model.quantity;
        }
      }
    }
    // أجرة تركيب المحرك تُضاف فقط إذا الآلية محرك ووُجد عنصر يخص المحرك مفعّل
    double motorCrankInstallFees = 0.0;
    final mech = widget.model.shutterMechanism;
    final isMotor = mech == 'محرك';
    for (var item in activeItems) {
      if (isShutterAccessory(item)) {
        final nameLower = item.originalName.toLowerCase();
        if ((nameLower.contains('moteur') || nameLower.contains('محرك')) &&
            isMotor) {
          motorCrankInstallFees += _moteurInstallFee * widget.model.quantity;
        }
      }
    }
    // متغيرات أسعار البيع لكل قسم (تُحسب حسب طريقة _costMethod أدناه)
    double profileSelling = 0.0;
    double glassSelling = 0.0;
    double shutterSelling = 0.0;
    double accessorySelling = 0.0;
    double jointSelling = 0.0;
    // السعر الفعلي لمتر مربع الستار (يدوي إن وُجد، وإلا من قاعدة البيانات)
    double effectiveShutterSqmPrice =
        _shutterSqmPriceOverride ?? _shutterSqmPriceFromDb;
    bool hasShutter = items.any(
          (item) => item.isActive && item.category == 'shutter',
    );
    double areaSqm = // مساحة النافذة بالمتر المربع
    (widget.model.width / 1000.0) * (widget.model.height / 1000.0);
    double shutterAreaPrice = hasShutter // سعر بيع الستار محسوبًا بالمتر المربع (يُستخدم في طريقتين من الثلاث)
        ? (effectiveShutterSqmPrice * areaSqm * widget.model.quantity)
        : 0.0;
    // ---- طريقة 1: النسبة المئوية — سعر البيع = التكلفة × (1 + نسبة الربح) ----
    if (_costMethod == CostMethod.percentage) {
      double factor = 1 + _profitMargin / 100;
      profileSelling = profileCost * factor;
      glassSelling =
          glassCost; // سعر بيع الزجاج يساوي دائمًا تكلفته (بدون هامش ربح إضافي)
      shutterSelling = shutterCost * factor;
      accessorySelling =
          (accessorySellingCost * factor) +
              specialAccessoryInstallFees +
              motorCrankInstallFees;
      jointSelling = jointCost * factor;
      // ---- طريقة 2: سعر المتر المربع الكلي للنافذة (يُطرح منه الزجاج ليبقى نصيب البروفيل) ----
    } else if (_costMethod == CostMethod.squareMeter) {
      double windowSellingPrice =
          _pricePerSqm * areaSqm * widget.model.quantity;
      glassSelling =
          glassCost; // الزجاج يبقى بسعر التكلفة
      profileSelling = windowSellingPrice - glassCost; // الباقي بعد طرح الزجاج يُنسب للبروفيل
      if (profileSelling < 0.0) profileSelling = 0.0; // حماية من قيمة سالبة
      shutterSelling = shutterAreaPrice;
      accessorySelling =
          accessorySellingCost +
              specialAccessoryInstallFees +
              motorCrankInstallFees;
      jointSelling = jointCost;
      // ---- طريقة 3: سعر المتر الخطي للبروفيلات الرئيسية + تكلفة البروفيلات الأخرى كما هي ----
    } else if (_costMethod == CostMethod.linearMeter) {
      profileSelling =
          (mainProfileMeters *
              (_pricePerLinearMeterOverride ?? _pricePerLinearMeterFromDb)) +
              otherProfileCost;
      glassSelling =
          glassCost;
      shutterSelling = shutterAreaPrice;
      accessorySelling =
          accessorySellingCost +
              specialAccessoryInstallFees +
              motorCrankInstallFees;
      jointSelling = jointCost;
    }
    // المجاميع الكلية للتكلفة وسعر البيع
    double totalCost = profileCost + glassCost + shutterCost + accessoryCost + jointCost;
    double totalSelling =
        profileSelling + glassSelling + shutterSelling + accessorySelling + jointSelling;
    // إرجاع كل القيم كخريطة مقسّمة حسب القسم (لكل قسم: cost و selling)
    return {
      'profile': {'cost': profileCost, 'selling': profileSelling},
      'glass': {'cost': glassCost, 'selling': glassSelling},
      'shutter': {'cost': shutterCost, 'selling': shutterSelling},
      'accessory': {'cost': accessoryCost, 'selling': accessorySelling},
      'joint': {'cost': jointCost, 'selling': jointSelling},
      'total': {'cost': totalCost, 'selling': totalSelling},
    };
  }
  // ==========================================================================
  // دالة: _buildCostMethodSelector
  // تبني بطاقة (Card) تحوي: اختيار طريقة الحساب، حقل الإدخال الخاص بها،
  // إعداد الكمية، وملخص التسعير النهائي (تكلفة بدون/مع هدر + سعر البيع).
  // ==========================================================================
  Widget _buildCostMethodSelector() {
    final lang = Provider.of<AppSettingsProvider>(
      context,
      listen: false,
    ).language;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final items = ComponentCalculator.generateBom( // إعادة توليد القائمة للحصول على أحدث المجاميع
      widget.model,
      activeVariants,
      kitBundleData: _kitBundleData,
      kitPerLeafMap: _kitPerLeafMap,
    );
    final totals = _calculateTotals(items);
    final double totalCostNoWaste = totals['total']?['cost'] ?? 0.0; // التكلفة الصافية بدون هدر
    final double totalCostWithWaste = totalCostNoWaste * 1.10; // إضافة هامش هدر ثابت 10%
    final double sellingPrice = totals['total']?['selling'] ?? 0.0;
    return Card(
      margin: const EdgeInsets.all(16.0),
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              Localization.translate('cost_calculation_method', lang),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            // أزرار اختيار طريقة الحساب (Chips) — عند الاختيار تُحفظ في SharedPreferences فورًا
            Wrap(
              spacing: 8.0,
              children: CostMethod.values.map((method) {
                final isSelected = _costMethod == method;
                String label = '';
                if (method == CostMethod.percentage) {
                  label = Localization.translate('percentage', lang);
                } else if (method == CostMethod.squareMeter) {
                  label = Localization.translate('square_meter', lang);
                } else if (method == CostMethod.linearMeter) {
                  label = Localization.translate('linear_meter', lang);
                }
                return ChoiceChip(
                  label: Text(label),
                  selected: isSelected,
                  onSelected: (selected) {
                    if (selected) {
                      setState(() => _costMethod = method);
                      _saveCostMethod(method);
                    }
                  },
                  selectedColor: isDark ? Colors.blue.shade900.withValues(alpha: 0.6) : Colors.blue.shade100,
                  checkmarkColor: isDark ? Colors.blue.shade100 : Colors.blue.shade800,
                  labelStyle: TextStyle(
                    color: isSelected
                        ? (isDark ? Colors.blue.shade100 : Colors.blue.shade900)
                        : (isDark ? Colors.white70 : Colors.black87),
                    fontWeight: isSelected
                        ? FontWeight.bold
                        : FontWeight.normal,
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            // حقل إدخال مختلف يظهر حسب طريقة الحساب المختارة حاليًا
            if (_costMethod == CostMethod.percentage)
              TextField(
                controller: _profitMarginController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: Localization.translate('نسبة الربح (%)', lang),
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.percent),
                ),
                onChanged: (val) {
                  final parsed = double.tryParse(val) ?? 0.0;
                  setState(() => _profitMargin = parsed);
                  _saveCostSetting('app_profit_margin', parsed);
                },
              )
            else if (_costMethod == CostMethod.squareMeter)
              TextField(
                controller: _pricePerSqmController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: Localization.translate('سعر المتر المربع (دج)', lang),
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.aspect_ratio),
                ),
                onChanged: (val) {
                  final parsed = double.tryParse(val) ?? 0.0;
                  setState(() => _pricePerSqm = parsed);
                  _saveCostSetting('app_price_per_sqm', parsed);
                },
              )
            else if (_costMethod == CostMethod.linearMeter) ...[
                TextField(
                  controller: _pricePerLinearMeterController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: Localization.translate('سعر المتر الخطي (دج) — تعديل يدوي', lang),
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(
                      Icons.linear_scale,
                      color: Colors.blue,
                    ),
                    // زر إلغاء التعديل اليدوي (يرجع للقيمة من قاعدة البيانات) أو زر إعادة تحميل إذا لا يوجد تعديل
                    suffixIcon: _pricePerLinearMeterOverride != null
                        ? IconButton(
                      icon: const Icon(Icons.clear, color: Colors.red),
                      onPressed: () {
                        setState(() {
                          _pricePerLinearMeterOverride = null;
                          _pricePerLinearMeterController.text =
                              _pricePerLinearMeterFromDb.toStringAsFixed(0);
                        });
                      },
                    )
                        : IconButton(
                      icon: const Icon(Icons.refresh, color: Colors.blue),
                      tooltip: Localization.translate('إعادة تحميل من قاعدة البيانات', lang),
                      onPressed: _loadPricesFromDb,
                    ),
                  ),
                  onChanged: (val) {
                    final parsed = double.tryParse(val);
                    setState(() {
                      _pricePerLinearMeterOverride = parsed; // أي تعديل يدوي هنا يتجاوز قيمة القاعدة
                    });
                  },
                ),
              ],
            // حقل سعر متر الستار وحقل معامل العزم — يظهران فقط إذا كان في النافذة ستار أصلًا
            if (widget.model.hasShutter) ...[
              const SizedBox(height: 10),
              TextField(
                controller: _shutterSqmPriceController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: Localization.translate('سعر المتر المربع للستار (دج) — تعديل يدوي', lang),
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(
                    Icons.view_quilt,
                    color: Colors.purple,
                  ),
                  suffixIcon: _shutterSqmPriceOverride != null
                      ? IconButton(
                    icon: const Icon(Icons.clear, color: Colors.red),
                    onPressed: () {
                      setState(() {
                        _shutterSqmPriceOverride = null;
                        _shutterSqmPriceController.text =
                            _shutterSqmPriceFromDb.toStringAsFixed(0);
                      });
                    },
                  )
                      : null,
                ),
                onChanged: (val) {
                  final parsed = double.tryParse(val);
                  setState(() {
                    _shutterSqmPriceOverride = parsed;
                  });
                },
              ),
              // حقل معامل عزم المحرك — يظهر فقط عند اختيار آلية "محرك"، وتغييره يعيد حساب المحرك المناسب فورًا
              if (widget.model.shutterMechanism == 'محرك') ...[
                const SizedBox(height: 10),
                TextField(
                  controller: _torqueFactorController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: Localization.translate(
                      'معامل عزم المحرك (وزن كغ لكل 1 نيوتن) (الافتراضي: 1.6)',
                      lang,
                    ),
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.bolt, color: Colors.orange),
                  ),
                  onChanged: (val) {
                    final parsed = double.tryParse(val) ?? 1.6;
                    setState(() {
                      _torqueFactor = parsed;
                    });
                    _saveCostSetting('shutter_torque_factor', parsed);
                    _fetchDefaults(); // إعادة اختيار المحرك المناسب فورًا بعد تغيير المعامل
                  },
                ),
              ],
            ],
            const SizedBox(height: 20),
            const Divider(),
            const SizedBox(height: 12),
            // حقل تعديل "الكمية" (عدد النوافذ المتطابقة المطلوبة)
            Row(
              children: [
                const Icon(
                  Icons.format_list_numbered,
                  color: Colors.blue,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  Localization.translate('الكمية:', lang),
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: isDark ? Colors.white70 : Colors.black87,
                  ),
                ),
                const SizedBox(width: 16),
                SizedBox(
                  width: 90,
                  child: TextFormField(
                    initialValue: '${widget.model.quantity}',
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    decoration: InputDecoration(
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        vertical: 8,
                        horizontal: 4,
                      ),
                      isDense: true,
                    ),
                    onChanged: (val) {
                      final parsed = int.tryParse(val);
                      if (parsed != null && parsed > 0) {
                        setState(() => widget.model.quantity = parsed);
                      }
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  Localization.translate('نافذة', lang),
                  style: TextStyle(
                    fontSize: 13,
                    color: isDark ? Colors.white54 : Colors.grey,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            // بطاقة ملخص التسعير النهائي (تكلفة بدون هدر / مع هدر / سعر البيع المقترح)
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E1E2C) : Colors.grey.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: isDark ? Colors.blue.withValues(alpha: 0.15) : Colors.grey.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    Localization.translate('ملخص تسعير', lang),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white70 : Colors.black54,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _priceRow(
                    Icons.monetization_on_outlined,
                    Localization.translate('سعر التكلفة بدون هدر', lang),
                    '${totalCostNoWaste.toStringAsFixed(0)} ${Localization.translate('دج', lang)}',
                    Colors.orange.shade700,
                  ),
                  const SizedBox(height: 8),
                  _priceRow(
                    Icons.warning_amber_rounded,
                    Localization.translate('سعر التكلفة مع هدر 10%', lang),
                    '${totalCostWithWaste.toStringAsFixed(0)} ${Localization.translate('دج', lang)}',
                    Colors.deepOrange,
                  ),
                  const SizedBox(height: 8),
                  const Divider(height: 1),
                  const SizedBox(height: 8),
                  _priceRow(
                    Icons.sell_rounded,
                    Localization.translate('سعر البيع المقترح', lang),
                    '${sellingPrice.toStringAsFixed(0)} ${Localization.translate('دج', lang)}',
                    Colors.green.shade700,
                    isBig: true, // خط أكبر لإبراز السعر النهائي
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
  // ودجت مساعد صغير: يبني صفًا موحد الشكل (أيقونة + نص + قيمة) لعرض عناصر ملخص التسعير
  Widget _priceRow(
      IconData icon,
      String label,
      String value,
      Color color, {
        bool isBig = false,
      }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Row(
      children: [
        Icon(icon, color: color, size: isBig ? 22 : 18),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: isBig ? 14 : 12,
              fontWeight: isBig ? FontWeight.bold : FontWeight.normal,
              color: isDark ? Colors.white70 : Colors.black87,
            ),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: isBig ? 18 : 13,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }
  // ==========================================================================
  // دالة: _buildKitDropdown
  // تبني قائمة منسدلة (PopupMenu) لترقية/تغيير كيت الستار الحالي، مع تطبيق
  // قاعدة "الترقية فقط" (لا يمكن اختيار كيت أصغر من الحد الأدنى المسموح
  // حسب ارتفاع النافذة أو حسب الكيت الحالي نفسه إن كان أكبر من الحد).
  // ==========================================================================
  Widget _buildKitDropdown(BomItem item) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: () async {
        // جلب كل الكيتات المتاحة من قاعدة البيانات (اسمها يحتوي kit/كيت)
        final dbInstance = await SqlDatabase().db;
        if (dbInstance == null) return <Map<String, dynamic>>[];
        final rows = await dbInstance.query(
          'ShutterComponents',
          where:
          "(LOWER(name) LIKE '%kit%' OR name LIKE '%كيت%') AND (is_active = 1 OR is_active IS NULL)",
        );
        return rows.map((r) => Map<String, dynamic>.from(r)).toList();
      }(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          // أثناء التحميل: مؤشر دوران صغير بدل الأيقونة
          return const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          );
        }
        final allKits = snapshot.data!;
        // تحديد الحد الأدنى المسموح لمقاس الكيت حسب ارتفاع النافذة (قاعدة عمل: كلما زاد الارتفاع زاد الحد الأدنى)
        final double currentHeight = widget.model.height;
        double minAllowedSize = 155.0;
        if (currentHeight > 1600 && currentHeight <= 2400) {
          minAllowedSize = 185.0;
        } else if (currentHeight > 2400) {
          minAllowedSize = 205.0;
        }
        // استخراج مقاس الكيت الحالي المختار (إن وُجد) وتوحيد صيغته
        final currentKit = widget.model.componentOverrides[item.originalName];
        double currentKitSize = 0.0;
        if (currentKit != null) {
          final currentSizeStr = getComponentSize(currentKit);
          if (currentSizeStr != null) {
            currentKitSize = double.tryParse(currentSizeStr) ?? 0.0;
            // تصحيح صيغ مقاسات مختصرة شائعة (15.5 → 155، 18.5 → 185 إلخ)
            if (currentKitSize == 15.5) currentKitSize = 155.0;
            if (currentKitSize == 18.5) currentKitSize = 185.0;
            if (currentKitSize == 20.5) currentKitSize = 205.0;
            if (currentKitSize == 15.0) currentKitSize = 150.0;
            if (currentKitSize == 18.0) currentKitSize = 180.0;
            if (currentKitSize == 20.0) currentKitSize = 200.0;
            if (currentKitSize < 100.0) {
              currentKitSize = currentKitSize * 10.0; // مقاسات صغيرة جدًا تُضرب ×10 لتصحيح الوحدة
            }
          }
        }
        // الحد الأدنى الفعلي = الأكبر بين (الحد حسب الارتفاع) و(مقاس الكيت الحالي) — لضمان عدم التراجع لمقاس أصغر
        final double finalMinSize = currentKitSize > minAllowedSize
            ? currentKitSize
            : minAllowedSize;
        // فلترة الكيتات المسموح عرضها فقط (مقاسها ≥ الحد الأدنى الفعلي)
        final allowedKits = allKits.where((k) {
          final sizeDigits = getComponentSize(k);
          if (sizeDigits != null) {
            double compSize = double.tryParse(sizeDigits) ?? 0.0;
            if (compSize == 15.5) compSize = 155.0;
            if (compSize == 18.5) compSize = 185.0;
            if (compSize == 20.5) compSize = 205.0;
            if (compSize == 15.0) compSize = 150.0;
            if (compSize == 18.0) compSize = 180.0;
            if (compSize == 20.0) compSize = 200.0;
            if (compSize < 100.0) {
              compSize = compSize * 10.0;
            }
            return compSize >= finalMinSize;
          }
          return true; // إذا ما قدرنا نحدد مقاسه، نعرضه احتياطًا
        }).toList();
        final currentKitId = currentKit?['id'];
        // بناء قائمة منسدلة (Popup Menu) مع علامة ✓ أمام الكيت الحالي
        return PopupMenuButton<Map<String, dynamic>>(
          icon: const Icon(
            Icons.arrow_drop_down_circle_outlined,
            color: Colors.blue,
            size: 20,
          ),
          tooltip: 'تغيير كيت الستار (ترقية فقط)',
          onSelected: (selectedKit) async {
            await _handleKitSelection(selectedKit); // تفويض المعالجة الفعلية لدالة _handleKitSelection
          },
          itemBuilder: (context) {
            return allowedKits.map((k) {
              final isCurrent = currentKitId == k['id'];
              return PopupMenuItem<Map<String, dynamic>>(
                value: k,
                child: Row(
                  children: [
                    if (isCurrent)
                      const Icon(Icons.check, color: Colors.green, size: 16)
                    else
                      const SizedBox(width: 16),
                    const SizedBox(width: 8),
                    Text(
                      '${k['name']} (${k['price']} دج)',
                      style: TextStyle(
                        fontWeight: isCurrent
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
              );
            }).toList();
          },
        );
      },
    );
  }
  // ==========================================================================
  // دالة: _buildKitGroups
  // تبني صفوف الجدول الخاصة بمجموعات الكيت (قابلة للطي/التوسعة)، حيث يظهر
  // رأس المجموعة كصف واحد قابل للنقر، وعناصره الفرعية تظهر فقط عند التوسعة.
  // ==========================================================================
  List<Widget> _buildKitGroups(List<BomItem> kitItems) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final lang = Provider.of<AppSettingsProvider>(context, listen: false).language;
    if (kitItems.isEmpty) return []; // لا شيء لعرضه
    // تجميع العناصر حسب اسم مجموعة الكيت (kitGroupName)
    final Map<String, List<BomItem>> grouped = {};
    for (final item in kitItems) {
      final group = item.kitGroupName ?? '';
      grouped.putIfAbsent(group, () => []);
      grouped[group]!.add(item);
    }
    final widgets = <Widget>[];
    for (final entry in grouped.entries) {
      final kitName = entry.key;
      final children = entry.value;
      final isExpanded = _kitGroupExpanded[kitName] ?? false; // حالة الطي/التوسعة الحالية
      final totalPrice = children.fold<double>(0, (sum, i) => sum + i.total); // مجموع تكلفة كل عناصر المجموعة
      // دالة داخلية: تحدد هل عنصر معين هو "رأس كيت" (وليس عنصرًا فرعيًا داخله)
      bool isKitItem(String name) =>
          name == 'كيت (Kit)' ||
              name == 'كيت فولي موتور (Kit Volet Moteur)' ||
              name == 'كيت فولي مانيفر (Kit Volet Manivelle)' ||
              name == 'كيت مانيفر (Kit Manivelle)' ||
              name == 'كيت حزام (Kit Sangle)' ||
              name == 'كيت فولي (Kit Volet)';
      // عدد العناصر المرئية الفعلية داخل المجموعة (باستثناء رأس الكيت وعناصر OB/Verrou الخاصة)
      final visibleCount = children
          .where(
            (c) =>
        !isKitItem(c.originalName) &&
            c.originalName != 'System OB' &&
            c.originalName != 'Demi System OB' &&
            c.originalName != 'Verrou Central',
      )
          .length;
      // دالة داخلية: تطابق مرن لاسم المجموعة مع مجموعة من الأسماء البديلة (aliases) بعد تطبيع النص
      bool isMatch(String baseName, List<String> aliases) {
        final normalizedKitName = kitName.toLowerCase().replaceAll(
          RegExp(r'[\s_-]'),
          '',
        );
        for (final alias in aliases) {
          final normalizedAlias = alias.toLowerCase().replaceAll(
            RegExp(r'[\s_-]'),
            '',
          );
          if (normalizedKitName == normalizedAlias) {
            return true;
          }
        }
        return false;
      }
      // تحديد نوع هذه المجموعة تحديدًا (Demi OB / System OB / Verrou Central / كيت ستار عادي)
      final isDemiOb = isMatch('Demi System OB', [
        'demi system ob',
        'demi_system_ob',
        'system_dim_ob',
        'system dim ob',
        'systemdimob',
        'demisystemob',
        'demisystemeob',
        'systemedimob',
      ]);
      final isSystemOb =
          !isDemiOb &&
              isMatch('System OB', ['system ob', 'system_ob', 'systemob']);
      final isVerrouCentral = isMatch('Verrou Central', [
        'verrou central',
        'verrou_central',
        'vero_central',
        'vero central',
        'verroucentral',
        'verocentral',
      ]);
      final isShutterKit = !isSystemOb && !isDemiOb && !isVerrouCentral;
      // العنصر الذي يمثل "رأس" هذه المجموعة (أول رأس كيت موجود، أو أول عنصر كخطة بديلة)
      final kitItem = children.firstWhere(
            (c) => isKitItem(c.originalName),
        orElse: () => children.first,
      );
      // هل المجموعة مفعّلة حاليًا؟ (تُحدد من activeVariants حسب نوعها)
      final isGroupActive = isSystemOb
          ? (activeVariants['System OB'] ?? false)
          : isDemiOb
          ? (activeVariants['Demi System OB'] ?? false)
          : isVerrouCentral
          ? (activeVariants['Verrou Central'] ?? false)
          : (activeVariants[kitItem.originalName] ?? false);
      // إخفاء المجموعة كليًا (بدون عرضها حتى كصف مطفأ) إذا كانت من النوع الخاص (OB/Demi/Verrou) وغير مفعّلة
      if (!isGroupActive && (isSystemOb || isDemiOb || isVerrouCentral)) {
        continue;
      }
      // ---- بناء صف "رأس" المجموعة القابل للنقر لفتح/طي العناصر الفرعية ----
      widgets.add(
        InkWell(
          onTap: () => setState(() => _kitGroupExpanded[kitName] = !isExpanded),
          child: Container(
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E1E2C) : Colors.white,
              border: Border(bottom: BorderSide(color: isDark ? Colors.blue.withValues(alpha: 0.15) : Colors.grey.shade200)),
            ),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // عمود الصورة: أيقونة صندوق عامة تمثل "كيت"
                  _cell(
                    Container(
                      height: 28,
                      color: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
                      child: Icon(
                        Icons.inventory_2_outlined,
                        color: isDark ? Colors.white54 : Colors.grey,
                        size: 16,
                      ),
                    ),
                    _wImg,
                  ),
                  // عمود الاسم: سهم توسعة/طي + اسم الكيت + قائمة تغيير الكيت إن كانت المجموعة كيت ستار مفعّلة
                  _cell(
                    Row(
                      children: [
                        Icon(
                          isExpanded
                              ? Icons.keyboard_arrow_up
                              : Icons.keyboard_arrow_down,
                          size: 20,
                          color: isDark ? Colors.purple.shade300 : Colors.deepPurple,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            isShutterKit
                                ? '📦 ${widget.model.componentOverrides[kitItem.originalName]?['name'] ?? kitName}'
                                : '📦 $kitName',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                              color: isDark ? Colors.purple.shade300 : Colors.deepPurple,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (isShutterKit && isGroupActive)
                          Padding(
                            padding: const EdgeInsets.only(right: 4.0),
                            child: _buildKitDropdown(kitItem), // زر تغيير الكيت فقط لكيتات الستار المفعّلة
                          ),
                      ],
                    ),
                    _wName,
                    backgroundColor: isDark
                        ? Colors.deepPurple.shade900.withValues(alpha: 0.3)
                        : Colors.deepPurple.shade100.withValues(alpha: 0.4),
                  ),
                  // عمود الكمية: يعرض عدد عناصر المجموعة بصيغة نصية (واحد/عنصران/عناصر)
                  _cell(
                    Text(
                      visibleCount == 1
                          ? Localization.translate('عنصر واحد', lang)
                          : visibleCount == 2
                          ? Localization.translate('عنصران', lang)
                          : (visibleCount >= 3 && visibleCount <= 10)
                          ? '$visibleCount ${Localization.translate('عناصر', lang)}'
                          : '$visibleCount ${Localization.translate('عنصر', lang)}',
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? Colors.white54 : Colors.grey,
                      ),
                    ),
                    _wQty,
                  ),
                  // عمود سعر الوحدة: لا معنى له لصف المجموعة، يُعرض "-"
                  _cell(
                    Text(
                      '-',
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? Colors.white54 : Colors.grey,
                      ),
                    ),
                    _wPrice,
                  ),
                  // عمود التكلفة الإجمالية للمجموعة (مع خط شطب إذا غير مفعّلة)
                  _cell(
                    Text(
                      '${totalPrice.toStringAsFixed(1)} ${Localization.translate('دج', lang)}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white70 : Colors.black87,
                        decoration: !isGroupActive
                            ? TextDecoration.lineThrough
                            : null,
                      ),
                    ),
                    _wTotal,
                  ),
                  _cell(
                    Text(
                      '-',
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? Colors.white54 : Colors.grey,
                      ),
                    ),
                    _wLen,
                  ),
                  _cell(
                    const Text(
                      '-',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    _wColor,
                  ),
                  // عمود التفعيل: Checkbox واحد يفعّل/يعطّل كل المجموعة دفعة واحدة
                  _cell(
                    Checkbox(
                      value: isGroupActive,
                      onChanged: (v) {
                        // توجيه التبديل حسب نوع المجموعة (OB/Demi/Verrou/كيت عادي)
                        if (isSystemOb) {
                          _handleVariantToggle(
                            'System OB',
                            'ob_group',
                            v ?? false,
                          );
                        } else if (isDemiOb) {
                          _handleVariantToggle(
                            'Demi System OB',
                            'ob_group',
                            v ?? false,
                          );
                        } else if (isVerrouCentral) {
                          _handleVariantToggle(
                            'Verrou Central',
                            'verrou_group',
                            v ?? false,
                          );
                        } else {
                          _handleVariantToggle(
                            kitItem.originalName,
                            null,
                            v ?? false,
                          );
                        }
                      },
                    ),
                    _wCheck,
                    isLast: true,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      // ---- عناصر المجموعة الفرعية: تُضاف فقط إذا كانت المجموعة موسّعة (isExpanded) ----
      if (isExpanded) {
        // نفس منطق فلترة visibleCount أعلاه بالضبط، لضمان توافق العدد المعروض مع العناصر الفعلية
        bool isKitHeader(String name) =>
            name == 'كيت (Kit)' ||
                name == 'كيت فولي موتور (Kit Volet Moteur)' ||
                name == 'كيت فولي مانيفر (Kit Volet Manivelle)' ||
                name == 'كيت مانيفر (Kit Manivelle)' ||
                name == 'كيت حزام (Kit Sangle)' ||
                name == 'كيت فولي (Kit Volet)';
        final visibleChildren = children
            .where(
              (c) =>
          !isKitHeader(c.originalName) &&
              c.originalName != 'System OB' &&
              c.originalName != 'Demi System OB' &&
              c.originalName != 'Verrou Central',
        )
            .toList();
        widgets.addAll(visibleChildren.map(_row)); // بناء صف عادي لكل عنصر فرعي عبر _row
      }
    }
    return widgets;
  }
  // ==========================================================================
  // دالة: _buildUnifiedTable
  // تبني الجدول الكامل: رأس الجدول + كل الأقسام (بروفيلات/إكسسوارات/ستار/زجاج)
  // مع عناوين الأقسام ومجاميعها، وتضيف عمودًا ثابتًا (overlay) عند التمرير أفقيًا.
  // ==========================================================================
  Widget _buildUnifiedTable(List<BomItem> items) {
    if (items.isEmpty) return const SizedBox.shrink(); // لا يوجد شيء لعرضه
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // دالة داخلية: تحدد هل العنصر "غطاء شفرات" (لأنه يُنقل من قسم accessory إلى قسم shutter في العرض)
    bool isBouchonLame(BomItem i) =>
        i.originalName.contains('أغطية الشفرات') ||
            i.originalName.toLowerCase().contains('bouchons lames') ||
            i.originalName.toLowerCase().contains('bouchon lame');
    // تقسيم كل العناصر إلى مجموعات حسب القسم الذي ستظهر فيه بالجدول
    final Map<String, List<BomItem>> groups = {
      'profile': items.where((i) => i.category == 'profile').toList(),
      'accessory': items
          .where((i) => (i.category == 'accessory' && !isBouchonLame(i)) || 
                        (i.category == 'other'))
          .toList(),
      'joint': items
          .where((i) => i.category == 'joint')
          .toList(),
      // كل مكونات الستار (ما عدا الجوانات) تُعرض معًا في قسم واحد
      'shutter': items
          .where(
            (i) =>
        i.category == 'shutter' ||
            (i.category == 'accessory' && isBouchonLame(i)),
      )
          .toList(),
      'glass': items.where((i) => i.category == 'glass' || i.category == 'panneau').toList(),
    };
    final totals = _calculateTotals(items); // حساب مجاميع كل قسم لعرضها في عناوين الأقسام
    return Stack( // Stack لوضع العمود الثابت (overlay) فوق الجدول عند التمرير
      children: [
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade300),
            borderRadius: BorderRadius.circular(4),
          ),
          child: SingleChildScrollView(
            controller: _scrollController, // نفس الكونترولر المستخدم لمراقبة موضع التمرير
            scrollDirection: Axis.horizontal, // تمرير أفقي لأن الجدول أعرض من الشاشة
            child: SizedBox(
              width: _minW, // عرض ثابت = مجموع عرض كل الأعمدة
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _header(), // صف رأس الجدول (أسماء الأعمدة)
                  // قسم البروفيلات (يظهر فقط إذا كان فيه عناصر)
                  if (groups['profile']!.isNotEmpty) ...[
                    _sectionTitle(
                      'البروفيلات',
                      Colors.blue.shade100,
                      cost: totals['profile']?['cost'],
                      selling: totals['profile']?['selling'],
                    ),
                    ...groups['profile']!.map(_row),
                  ],
                  // قسم الإكسسوارات (مقسّم إلى: عناصر كيت مجمّعة + عناصر عادية منفردة)
                  if (groups['accessory']!.isNotEmpty) ...[
                    _sectionTitle(
                      'الإكسسوارات',
                      Colors.orange.shade100,
                      cost: totals['accessory']?['cost'],
                      selling: totals['accessory']?['selling'],
                    ),
                    ..._buildKitGroups(
                      groups['accessory']!
                          .where((i) => i.kitGroupName != null)
                          .toList(),
                    ),
                    ...groups['accessory']!
                        .where((i) => i.kitGroupName == null)
                        .map(_row),
                  ],
                  // قسم مكوّنات الستار (نفس منطق التقسيم: كيت مجمّع + عناصر عادية)
                  if (groups['shutter']!.isNotEmpty) ...[
                    _sectionTitle(
                      'مكوّنات الستار',
                      Colors.purple.shade100,
                      cost: totals['shutter']?['cost'],
                      selling: totals['shutter']?['selling'],
                    ),
                    ..._buildKitGroups(
                      groups['shutter']!
                          .where((i) => i.kitGroupName != null)
                          .toList(),
                    ),
                    ...groups['shutter']!
                        .where((i) => i.kitGroupName == null)
                        .map(_row),
                  ],
                  // قسم الزجاج (بدون كيتات — كل عناصره عادية)
                  if (groups['glass']!.isNotEmpty) ...[
                    _sectionTitle(
                      'الزجاج',
                      Colors.teal.shade100,
                      cost: totals['glass']?['cost'],
                      selling: totals['glass']?['selling'],
                    ),
                    ...groups['glass']!.map(_row),
                  ],
                  // قسم الجوينات (Gaskets)
                  if (groups['joint'] != null && groups['joint']!.isNotEmpty) ...[
                    _sectionTitle(
                      'الجوينات',
                      Colors.purple.shade50,
                      cost: totals['joint']?['cost'],
                      selling: totals['joint']?['selling'],
                    ),
                    ...groups['joint']!.map(_row),
                  ],
                ],
              ),
            ),
          ),
        ),
        // العمود الثابت (overlay) يظهر فقط بعد التمرير أفقيًا، ليبقى اسم العنصر ظاهرًا دائمًا
        if (_isScrolled)
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            child: _buildMinimalOverlay(groups),
          ),
      ],
    );
  }
  // ==========================================================================
  // دالة: _buildMinimalOverlay
  // تبني عمودًا مصغّرًا (يحتوي فقط أسماء الأقسام والعناصر) يظهر ثابتًا على
  // يسار/يمين الشاشة عندما يكون المستخدم قد مرّر الجدول أفقيًا، لتبقى أسماء
  // العناصر مرئية دائمًا أثناء التمرير.
  // ==========================================================================
  List<Widget> _buildMinimalKitGroups(List<BomItem> kitItems) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final lang = Provider.of<AppSettingsProvider>(context, listen: false).language;
    if (kitItems.isEmpty) return [];
    final Map<String, List<BomItem>> grouped = {};
    for (final item in kitItems) {
      final group = item.kitGroupName ?? '';
      grouped.putIfAbsent(group, () => []);
      grouped[group]!.add(item);
    }
    final widgets = <Widget>[];
    for (final entry in grouped.entries) {
      final kitName = entry.key;
      final children = entry.value;
      final isExpanded = _kitGroupExpanded[kitName] ?? false;
      bool isKitItem(String name) =>
          name == 'كيت (Kit)' ||
              name == 'كيت فولي موتور (Kit Volet Moteur)' ||
              name == 'كيت فولي مانيفر (Kit Volet Manivelle)' ||
              name == 'كيت مانيفر (Kit Manivelle)' ||
              name == 'كيت حزام (Kit Sangle)' ||
              name == 'كيت فولي (Kit Volet)';
      bool isMatch(String baseName, List<String> aliases) {
        final normalizedKitName = kitName.toLowerCase().replaceAll(RegExp(r'[\s_-]'), '');
        for (final alias in aliases) {
          final normalizedAlias = alias.toLowerCase().replaceAll(RegExp(r'[\s_-]'), '');
          if (normalizedKitName == normalizedAlias) return true;
        }
        return false;
      }
      final isDemiOb = isMatch('Demi System OB', [
        'demi system ob', 'demi_system_ob', 'system_dim_ob', 'system dim ob', 'systemdimob', 'demisystemob', 'demisystemeob', 'systemedimob'
      ]);
      final isSystemOb = !isDemiOb && isMatch('System OB', ['system ob', 'system_ob', 'systemob']);
      final isVerrouCentral = isMatch('Verrou Central', [
        'verrou central', 'verrou_central', 'vero_central', 'vero central', 'verroucentral', 'verocentral'
      ]);
      final kitItem = children.firstWhere(
            (c) => isKitItem(c.originalName),
        orElse: () => children.first,
      );
      final isGroupActive = isSystemOb
          ? (activeVariants['System OB'] ?? false)
          : isDemiOb
          ? (activeVariants['Demi System OB'] ?? false)
          : isVerrouCentral
          ? (activeVariants['Verrou Central'] ?? false)
          : (activeVariants[kitItem.originalName] ?? false);
      if (!isGroupActive && (isSystemOb || isDemiOb || isVerrouCentral)) {
        continue;
      }
      widgets.add(
        InkWell(
          onTap: () => setState(() => _kitGroupExpanded[kitName] = !isExpanded),
          child: Container(
            height: _rowHeight + 1, // Added 1 pixel to match the main table row + border height!
            width: 140, // Match the narrow width
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E1E2C) : Colors.white,
              border: Border(bottom: BorderSide(color: isDark ? Colors.blue.withValues(alpha: 0.15) : Colors.grey.shade200)),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            alignment: Alignment.centerLeft,
            child: Row(
              children: [
                Icon(
                  isExpanded ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_right,
                  color: isDark ? Colors.purple.shade300 : Colors.grey,
                  size: 16,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    isSystemOb
                        ? 'System OB'
                        : isDemiOb
                        ? 'Demi System OB'
                        : isVerrouCentral
                        ? 'Verrou Central'
                        : kitName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.purple.shade300 : (isGroupActive ? Colors.deepPurple.shade900 : Colors.grey),
                      decoration: !isGroupActive ? TextDecoration.lineThrough : null,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      if (isExpanded) {
        final visibleChildren = children
            .where((c) =>
                !isKitItem(c.originalName) &&
                c.originalName != 'System OB' &&
                c.originalName != 'Demi System OB' &&
                c.originalName != 'Verrou Central')
            .toList();
        widgets.addAll(visibleChildren.map(_minimalRow));
      }
    }
    return widgets;
  }
Widget _buildMinimalOverlay(Map<String, List<BomItem>> groups) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final lang = Provider.of<AppSettingsProvider>(context, listen: false).language;
    return Container(
      width: 140, // Reduced width as requested
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF161622).withValues(alpha: 0.95) : Colors.white.withValues(alpha: 0.95), // شبه شفاف قليلًا حتى يبدو طبقة فوق الجدول
        border: Border(
          right: BorderSide(color: isDark ? Colors.blue.withValues(alpha: 0.35) : Colors.grey.shade400, width: 2),
        ),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(2, 0)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: _rowHeight, // Enforce strict fixed height (no bottom border on header)
            width: double.infinity,
            color: isDark ? Colors.blueGrey.shade900 : Colors.blueGrey.shade800,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            alignment: Alignment.centerRight,
            child: Text(
              Localization.translate('البيان', lang),
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
                color: Colors.white,
              ),
            ),
          ),
          if (groups['profile']!.isNotEmpty) ...[
            _minimalSectionTitle(Localization.translate('البروفيلات', lang), isDark ? Colors.blue.shade900.withValues(alpha: 0.4) : Colors.blue.shade100),
            ...groups['profile']!.map(_minimalRow),
          ],
          if (groups['accessory']!.isNotEmpty) ...[
            _minimalSectionTitle(Localization.translate('الإكسسوارات', lang), isDark ? Colors.orange.shade900.withValues(alpha: 0.4) : Colors.orange.shade100),
            ..._buildMinimalKitGroups(
              groups['accessory']!
                  .where((i) => i.kitGroupName != null)
                  .toList(),
            ),
            ...groups['accessory']!
                .where((i) => i.kitGroupName == null)
                .map(_minimalRow),
          ],
          if (groups['shutter']!.isNotEmpty) ...[
            _minimalSectionTitle(Localization.translate('ستار', lang), isDark ? Colors.purple.shade900.withValues(alpha: 0.4) : Colors.purple.shade100),
            ..._buildMinimalKitGroups(
              groups['shutter']!
                  .where((i) => i.kitGroupName != null)
                  .toList(),
            ),
            ...groups['shutter']!
                .where((i) => i.kitGroupName == null)
                .map(_minimalRow),
          ],
          if (groups['glass']!.isNotEmpty) ...[
            _minimalSectionTitle(Localization.translate('الزجاج', lang), isDark ? Colors.teal.shade900.withValues(alpha: 0.4) : Colors.teal.shade100),
            ...groups['glass']!.map(_minimalRow),
          ],
          if (groups['joint'] != null && groups['joint']!.isNotEmpty) ...[
            _minimalSectionTitle(Localization.translate('الجوينات', lang), isDark ? Colors.purple.shade900.withValues(alpha: 0.2) : Colors.purple.shade50),
            ...groups['joint']!.map(_minimalRow),
          ],
        ],
      ),
    );
  }
  // عنوان قسم مصغّر (بدون أرقام التكلفة) للعمود الثابت
  Widget _minimalSectionTitle(String title, Color color) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      height: 35,
      width: double.infinity,
      color: color,
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
      child: Text(
        title,
        style: TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 13,
          color: isDark ? Colors.white70 : Colors.black87,
        ),
      ),
    );
  }
  // صف مصغّر يعرض فقط اسم العنصر (وربما اسمه الفرعي وقائمة القص) في العمود الثابت
  Widget _minimalRow(BomItem item) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isScrews =
        item.name.contains('براغي') ||
            item.originalName.contains('حديد') ||
            item.originalName.contains('Renfort') ||
            item.name.contains('حديد') ||
            item.name.contains('Renfort');
    return Container(
      height: _rowHeight + 1, // Added 1 pixel to match the main table row + border height!
      width: 140, // Reduced width as requested
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      alignment: Alignment.centerLeft,
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: isDark ? Colors.blue.withValues(alpha: 0.15) : Colors.grey.shade200)),
      ),
      child: Text(
        item.getLocalizedName(_lang),
        maxLines: 3, // Allow up to 3 lines for name if it's long
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: isScrews ? Colors.orange : (isDark ? Colors.white70 : Colors.black87),
          decoration: !item.isActive ? TextDecoration.lineThrough : null,
        ),
      ),
    );
  }
  Future<int?> _showQuantityDialog(BuildContext context, int currentQty) async {
    final lang = Provider.of<AppSettingsProvider>(context, listen: false).language;
    final controller = TextEditingController(text: '$currentQty');
    return showDialog<int>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(Localization.translate('تعديل كمية النوافذ', lang)),
          content: TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            autofocus: true,
            decoration: InputDecoration(
              labelText: Localization.translate('الكمية المطلوبة', lang),
              border: const OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(Localization.translate('إلغاء', lang)),
            ),
            ElevatedButton(
              onPressed: () {
                final int? val = int.tryParse(controller.text);
                if (val != null && val > 0) {
                  Navigator.pop(dialogContext, val);
                }
              },
              child: Text(Localization.translate('تأكيد', lang)),
            ),
          ],
        );
      },
    );
  }
  // نافذة تعرض تفصيل أسعار البيع لكل قسم (بروفيلات/زجاج/ستار/إكسسوارات) + المجموع
  void _showCalculationDetails(
      double profileSelling,
      double glassSelling,
      double shutterSelling,
      double accessorySelling,
      double finalSellingPrice,
      ) {
    final lang = Provider.of<AppSettingsProvider>(context, listen: false).language;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(Localization.translate('تفاصيل الحساب', lang), textDirection: TextDirection.rtl),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _detailRow(Localization.translate('سعر البروفيلات:', lang), profileSelling),
              _detailRow(Localization.translate('سعر الزجاج:', lang), glassSelling),
              _detailRow(Localization.translate('سعر الستار:', lang), shutterSelling),
              _detailRow(Localization.translate('سعر الإكسسوارات:', lang), accessorySelling),
              const Divider(thickness: 2),
              _detailRow(Localization.translate('المجموع الإجمالي:', lang), finalSellingPrice, isBold: true),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(Localization.translate('إغلاق', lang)),
          ),
        ],
      ),
    );
  }
  // صف تفصيلي واحد في نافذة "تفاصيل الحساب" — يُخفى تلقائيًا إذا كانت القيمة صفر (وليس صفًا رئيسيًا)
  Widget _detailRow(String label, double price, {bool isBold = false}) {
    if (price == 0 && !isBold) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        textDirection: TextDirection.rtl,
        children: [
          Text(
            label,
            style: TextStyle(
              fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          Text(
            '${price.toStringAsFixed(2)} دج',
            style: TextStyle(
              fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
              color: isBold ? Colors.green.shade700 : null,
            ),
            textDirection: TextDirection.rtl,
          ),
        ],
      ),
    );
  }
  // ==========================================================================
  // دالة: _buildBottomBar
  // تبني الشريط السفلي الثابت: زر فتح/طي إعدادات السعر، زر "تفاصيل"، ملخص
  // موسّع اختياري (سعر التكلفة، السعر الإجمالي، بطاقة اختيار طريقة الحساب)،
  // وأخيرًا سعر القطعة الواحدة وزر "حفظ وإضافة للطلب".
  // ==========================================================================
  Widget _buildBottomBar(List<BomItem> items) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final lang = Provider.of<AppSettingsProvider>(context, listen: false).language;
    final currency = Localization.translate('دج', lang);
    final totals = _calculateTotals(items);
    final double totalCostWithWaste = totals['total']?['cost'] ?? 0.0;
    final double sellingPrice = totals['total']?['selling'] ?? 0.0;
    // سعر القطعة الواحدة = السعر الإجمالي ÷ الكمية (بحد أدنى 1 لتفادي القسمة على صفر)
    final double unitPrice = sellingPrice / math.max(1, widget.model.quantity);
    return SafeArea(
      child: AnimatedContainer( // تحريك سلس عند تغيّر ارتفاع الشريط (طي/توسعة)
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInOut,
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1E2C) : Colors.white,
          boxShadow: [
            BoxShadow(
              color: isDark ? Colors.black.withValues(alpha: 0.3) : Colors.black.withValues(alpha: 0.10),
              blurRadius: 12,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // صف علوي: زر طي/فتح إعدادات السعر + زر "تفاصيل"
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => setState(
                          () => _isBottomBarExpanded = !_isBottomBarExpanded,
                    ),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF2D2D44) : Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: isDark ? const Color(0xFF3D3D5C) : Colors.grey.shade300),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            _isBottomBarExpanded
                                ? Icons.keyboard_arrow_down
                                : Icons.keyboard_arrow_up,
                            color: isDark ? Colors.white70 : Colors.grey.shade700,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _isBottomBarExpanded ? Localization.translate('إخفاء', lang) : Localization.translate('إعدادات السعر', lang),
                            style: TextStyle(
                              color: isDark ? Colors.white70 : Colors.grey.shade800,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: () => _showCalculationDetails(
                      totals['profile']?['selling'] ?? 0.0,
                      totals['glass']?['selling'] ?? 0.0,
                      totals['shutter']?['selling'] ?? 0.0,
                      totals['accessory']?['selling'] ?? 0.0,
                      sellingPrice,
                    ),
                    icon: Icon(Icons.info_outline, color: isDark ? Colors.blue.shade300 : Colors.blue),
                    label: Text(
                      Localization.translate('تفاصيل', lang),
                      style: TextStyle(
                        color: isDark ? Colors.blue.shade300 : Colors.blue,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // القسم الموسّع: يظهر فقط إذا _isBottomBarExpanded == true
            if (_isBottomBarExpanded)
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.35, // حد أقصى للارتفاع (35% من الشاشة)
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // صف "سعر التكلفة" مع إمكانية إخفائه (زر عين) لحماية الخصوصية أمام الزبون
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 6,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          textDirection: TextDirection.rtl,
                          children: [
                            Row(
                              textDirection: TextDirection.rtl,
                              children: [
                                Text(
                                  Localization.translate('سعر التكلفة:', lang),
                                  style: const TextStyle(fontSize: 14, color: Colors.grey),
                                  textDirection: TextDirection.rtl,
                                ),
                                const SizedBox(width: 8),
                                IconButton(
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                  icon: Icon(
                                    showCostPrice
                                        ? Icons.visibility
                                        : Icons.visibility_off,
                                    color: isDark ? Colors.white60 : Colors.grey.shade600,
                                    size: 20,
                                  ),
                                  onPressed: () {
                                    setState(() {
                                      showCostPrice = !showCostPrice;
                                    });
                                  },
                                ),
                              ],
                            ),
                            Text(
                              showCostPrice
                                  ? '${totalCostWithWaste.toStringAsFixed(2)} $currency'
                                  : '*** $currency', // إخفاء الرقم بنجوم إذا showCostPrice == false
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: isDark ? Colors.white70 : Colors.grey.shade800,
                              ),
                              textDirection: TextDirection.rtl,
                            ),
                          ],
                        ),
                      ),
                      // صف "السعر الإجمالي" لكل الكمية المطلوبة
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 6,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          textDirection: TextDirection.rtl,
                          children: [
                            Text(
                              '${Localization.translate('السعر الإجمالي', lang)} (${widget.model.quantity} ${Localization.translate('قطع', lang)}):',
                              style: const TextStyle(fontSize: 14, color: Colors.grey),
                              textDirection: TextDirection.rtl,
                            ),
                            Text(
                              '${sellingPrice.toStringAsFixed(2)} $currency',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: isDark ? Colors.green.shade400 : Colors.green.shade700,
                              ),
                              textDirection: TextDirection.rtl,
                            ),
                          ],
                        ),
                      ),
                      // بطاقة اختيار طريقة الحساب كاملة (مضمّنة هنا)
                      Container(
                        padding: const EdgeInsets.all(16),
                        color: isDark ? const Color(0xFF25283D) : Colors.grey.shade50,
                        child: _buildCostMethodSelector(),
                      ),
                    ],
                  ),
                ),
              ),
            Container(height: 1, color: Colors.grey.shade200), // خط فاصل
            // الصف السفلي الأخير: سعر القطعة الواحدة + زر "حفظ وإضافة للطلب"
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                textDirection: TextDirection.rtl,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      textDirection: TextDirection.rtl,
                      children: [
                        Text(
                          Localization.translate('سعر القطعة الواحدة:', lang),
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                            fontWeight: FontWeight.w600,
                          ),
                          textDirection: TextDirection.rtl,
                        ),
                        Text(
                          '${unitPrice.toStringAsFixed(2)} $currency',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                          textDirection: TextDirection.rtl,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        // حفظ السعر النهائي للقطعة الواحدة في النموذج لمنع مضاعفته عند ضربه في الكمية في الفاتورة
                        widget.model.totalCost = unitPrice;
                        widget.model.manualPriceOverride = unitPrice;
                        Navigator.pop(context, true);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isDark ? Colors.blue.shade700 : const Color(0xFF1976D2),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        Localization.translate('حفظ وإضافة للطلب', lang),
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
  // رأس الجدول: صف ثابت يحمل عناوين كل الأعمدة (الصورة/البيان/الكمية/سعر الوحدة/التكلفة/الطول/اللون/تفعيل)
  Widget _header() {
    final lang = Provider.of<AppSettingsProvider>(context, listen: false).language;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const s = TextStyle(
      fontWeight: FontWeight.bold,
      fontSize: 13,
      color: Colors.white,
    );
    return Container(
      color: isDark ? const Color(0xFF1E1E2C) : Colors.blueGrey.shade800,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _cell(Text(Localization.translate('الصورة', lang), style: s), _wImg),
            _cell(Text(Localization.translate('البيان', lang), style: s), _wName),
            _cell(Text(Localization.translate('الكمية', lang), style: s), _wQty),
            _cell(Text(Localization.translate('سعر الوحدة', lang), style: s), _wPrice),
            _cell(Text(Localization.translate('التكلفة', lang), style: s), _wTotal),
            _cell(Text(Localization.translate('الطول', lang), style: s), _wLen),
            _cell(Text(Localization.translate('اللون', lang), style: s), _wColor),
            _cell(Text(Localization.translate('تفعيل', lang), style: s), _wCheck, isLast: true),
          ],
        ),
      ),
    );
  }
  // صف عنوان قسم في الجدول (البروفيلات/الإكسسوارات/الستار/الزجاج) مع عرض التكلفة والبيع الاختياريين
  Widget _sectionTitle(
      String title,
      Color color, {
        double? cost,
        double? selling,
      }) {
    final lang = Provider.of<AppSettingsProvider>(context, listen: false).language;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final translatedTitle = Localization.translate(title, lang);
    final currency = Localization.translate('دج', lang);
    return Container(
      color: isDark ? const Color(0xFF25283D) : color,
      width: double.infinity,
      height: 35,
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      child: Row(
        children: [
          Text(
            translatedTitle,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 14,
              color: isDark ? color : Colors.black87,
            ),
          ),
          const SizedBox(width: 12),
          // شارة صغيرة تعرض التكلفة الإجمالية للقسم (تظهر فقط إذا مُررت قيمة cost)
          if (cost != null)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 4),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: isDark ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '${Localization.translate('التكلفة:', lang)} ${cost.toStringAsFixed(0)} $currency',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white70 : Colors.black87,
                ),
              ),
            ),
          // شارة صغيرة تعرض سعر البيع الإجمالي للقسم
          if (selling != null)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 4),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: isDark ? Colors.green.shade900.withValues(alpha: 0.4) : Colors.green.shade700.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '${Localization.translate('البيع:', lang)} ${selling.toStringAsFixed(0)} $currency',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.green.shade300 : Colors.green.shade800,
                ),
              ),
            ),
        ],
      ),
    );
  }
  // ودجت مساعد عام: يبني خلية جدول واحدة بعرض ثابت وحد فاصل يمين (إلا إذا كانت آخر خلية isLast)
  Widget _cell(
      Widget child,
      double width, {
        bool isLast = false,
        Color? backgroundColor,
      }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: width,
      height: _rowHeight, // Enforce strict fixed height
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: backgroundColor,
        border: isLast
            ? null
            : BorderDirectional(end: BorderSide(color: isDark ? Colors.blue.withValues(alpha: 0.35) : Colors.grey.shade300)),
      ),
      alignment: Alignment.centerLeft,
      child: child,
    );
  }
  Widget _row(BomItem item) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final lang = Provider.of<AppSettingsProvider>(context, listen: false).language;
    final currency = Localization.translate('دج', lang);
    final inactive = !item.isActive; // العنصر معطّل حاليًا
    final warning = item.isMissing && item.isActive; // العنصر مفعّل لكنه "ناقص" (لم يُربط بمكوّن فعلي بعد)
    // تمييز البراغي/الحديد بلون برتقالي مميز
    final isScrews =
        item.originalName.contains('براغي') ||
            item.originalName.contains('حديد') ||
            item.originalName.contains('Renfort') ||
            item.name.contains('حديد') ||
            item.name.contains('Renfort');
    final bool isKitElement = item.kitGroupName != null; // هل هذا الصف عنصر فرعي داخل كيت
    return Container(
      decoration: BoxDecoration(
        color: inactive
            ? (isDark ? Colors.red.shade900.withValues(alpha: 0.3) : Colors.red.shade50) // خلفية حمراء خفيفة للعناصر المعطّلة
            : (isKitElement
            ? (isDark ? Colors.blue.shade900.withValues(alpha: 0.3) : Colors.blue.shade50.withValues(alpha: 0.5)) // خلفية زرقاء خفيفة لعناصر الكيت الفرعية
            : (isDark ? const Color(0xFF1E1E2C) : Colors.white)),
        border: Border(bottom: BorderSide(color: isDark ? Colors.blue.withValues(alpha: 0.15) : Colors.grey.shade200)),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // عمود الصورة: أيقونة مختلفة حسب كون العنصر جزءًا من كيت أو لا
            _cell(
              SectionImageWidget(
                code: item.profileCode,
                imagePath: item.imagePath,
                size: isKitElement ? 32.0 : 28.0,
                fallbackIcon: isKitElement ? Icons.extension : Icons.image,
                fallbackColor: isKitElement ? (isDark ? Colors.blue.shade300 : Colors.blue.shade700) : Colors.grey,
              ),
              _wImg,
            ),
            // عمود الاسم: أيقونة تحذير (إن كان ناقصًا) + الاسم + الاسم الثانوي/الكمية + قائمة القص + زر تبديل
            _cell(
              Row(
                children: [
                  if (warning)
                    const Icon(
                      Icons.warning_amber_rounded,
                      color: Colors.orange,
                      size: 14,
                    ),
                  if (warning) const SizedBox(width: 4),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          isKitElement ? item.name : item.getLocalizedName(_lang), // عناصر الكيت تعرض اسمها الأصلي دائمًا
                          style: TextStyle(
                            fontSize: isKitElement ? 13.5 : 12,
                            fontWeight: FontWeight.bold,
                            color: isScrews
                                ? Colors.orange
                                : (isKitElement
                                ? (isDark ? Colors.blue.shade300 : Colors.blue.shade900)
                                : (isDark ? Colors.white70 : Colors.black87)),
                            decoration: inactive
                                ? TextDecoration.lineThrough
                                : null,
                          ),
                        ),
                        // لعناصر الكيت: عرض الكمية والوحدة تحت الاسم مباشرة
                        if (isKitElement)
                          Text(
                            'الكمية: ${item.quantity % 1 == 0 ? item.quantity.toInt() : item.quantity} ${item.unit}',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: isDark ? Colors.blue.shade200 : Colors.blue.shade700,
                              decoration: inactive
                                  ? TextDecoration.lineThrough
                                  : null,
                            ),
                          )
                        // لغير عناصر الكيت: عرض الاسم الأصلي (الثانوي) إن اختلف عن الاسم المترجم
                        else if (item.name != item.originalName) ...[
                          (() {
                            final parts = item.name.split('\n');
                            final namePart = parts[0];
                            final subparts = parts.length > 1 ? parts.sublist(1) : <String>[];
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (namePart != item.originalName && (_lang == 'ar' || !_hasArabic(namePart)))
                                  Text(
                                    namePart,
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: item.category == 'glass'
                                          ? FontWeight.bold
                                          : FontWeight.normal,
                                      color: item.category == 'glass'
                                          ? (isDark ? Colors.white70 : Colors.black87)
                                          : (isDark ? Colors.white54 : Colors.grey.shade700),
                                      decoration: inactive
                                          ? TextDecoration.lineThrough
                                          : null,
                                    ),
                                  ),
                                ...subparts.map((subText) => Padding(
                                      padding: const EdgeInsets.only(top: 2.0),
                                      child: Text(
                                        subText,
                                        style: TextStyle(
                                          fontSize: 9.0,
                                          fontWeight: FontWeight.normal,
                                          color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                                          height: 1.1,
                                          decoration: inactive
                                              ? TextDecoration.lineThrough
                                              : null,
                                        ),
                                      ),
                                    )),
                              ],
                            );
                          })(),
                        ],
                        // قائمة القص (Cutting List) إن وُجدت
                        if (item.cuttingList != null &&
                            item.cuttingList!.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 2.0),
                            child: Text(
                              item.cuttingList!,
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: Colors.blueGrey,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  // زر التبديل: لعنصر "كيت (Kit)" القديم يظهر قائمة كيت، وإلا أيقونة تبديل عامة تفتح _showSwapDialog
                  if (item.isActive && !isKitElement)
                    Padding(
                      padding: const EdgeInsets.only(right: 4.0),
                      child: item.originalName == 'كيت (Kit)'
                          ? _buildKitDropdown(item)
                          : GestureDetector(
                        onTap: () => _showSwapDialog(item),
                        child: const Icon(
                          Icons.swap_horiz,
                          color: Colors.orange,
                          size: 18,
                        ),
                      ),
                    ),
                ],
              ),
              _wName,
            ),
            // عمود الكمية
            _cell(
              Text(
                '${item.quantity} ${item.unit}',
                style: TextStyle(fontSize: 12, color: isDark ? Colors.white70 : Colors.black87),
              ),
              _wQty,
            ),
            // عمود سعر الوحدة + زر تعديل السعر يدويًا (يفتح _showEditPriceDialog)
            _cell(
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${item.unitPrice} $currency',
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? Colors.white70 : Colors.black87,
                      ),
                    ),
                  ),
                  if (item.isActive)
                    Padding(
                      padding: const EdgeInsets.only(right: 8.0),
                      child: GestureDetector(
                        onTap: () => _showEditPriceDialog(item),
                        child: const Icon(
                          Icons.edit,
                          color: Colors.blue,
                          size: 16,
                        ),
                      ),
                    ),
                ],
              ),
              _wPrice,
            ),
            // عمود التكلفة الإجمالية للصف (مع خط شطب إن كان معطلًا)
            _cell(
              Text(
                '${item.total.toStringAsFixed(2)} $currency',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black87,
                  decoration: inactive ? TextDecoration.lineThrough : null,
                ),
              ),
              _wTotal,
            ),
            // عمود الطول: للزجاج يعرض "عرض × ارتفاع"، ولغيره الطول بالمتر، وإلا "-"
            _cell(
              Text(
                (item.category == 'glass' && item.glassHeight != null)
                    ? '${item.length?.toStringAsFixed(0)} × ${item.glassHeight?.toStringAsFixed(0)}'
                    : (item.length != null
                    ? '${item.length?.toStringAsFixed(1)}m'
                    : '-'),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: item.category == 'glass'
                      ? FontWeight.bold
                      : FontWeight.normal,
                  color: isDark ? Colors.white70 : Colors.black87,
                ),
                textAlign: TextAlign.center,
              ),
              _wLen,
            ),
            // عمود اللون (لا يُعرض للزجاج)
            _cell(
              Text(
                item.category == 'glass' ? '-' : (item.colorName ?? '-'),
                style: TextStyle(fontSize: 12, color: isDark ? Colors.white70 : Colors.black87),
              ),
              _wColor,
            ),
            // عمود التفعيل: Checkbox فقط إذا العنصر تفاعلي (isInteractive)، مع تعطيل خاص لغطاء الشفرات في حالة التونيل
            _cell(
              item.isInteractive
                  ? Checkbox(
                value: item.isActive,
                onChanged:
                (widget.model.isCaissonTunnel &&
                    item.originalName ==
                        'أغطية الشفرات (Bouchons Lames)')
                    ? null // معطّل تمامًا (إلزامي) في حالة التونيل
                    : (v) => _handleVariantToggle(
                  item.originalName,
                  item.exclusionGroup,
                  v ?? false,
                ),
              )
                  : const SizedBox.shrink(), // عنصر غير تفاعلي: لا يوجد Checkbox
              _wCheck,
              isLast: true,
            ),
          ],
        ),
      ),
    );
  }
  // ==========================================================================
  // دالة: _showSwapDialog ⭐ (دالة ضخمة ومعقدة)
  // الغرض: عند الضغط على زر التبديل بجانب أي عنصر، تفتح نافذة اختيار بديل
  // (ProfileSelectorDialog) بالنوع المناسب، وبعد الاختيار تُحدّث النموذج مع
  // كل "المكونات المرافقة" (companion components) التي يجب أن تتغيّر معها
  // تلقائيًا (مثل: تغيير الشريحة يستدعي تغيير المحور، الأطاش، السيبورات...).
  // ==========================================================================
  void _showSwapDialog(BomItem item) async {
    String pType = item.originalName; // النوع المبدئي المرسل لنافذة الاختيار (سيُعاد تعيينه أدناه حسب الفئة)
    String pCategory = item.category;
    bool isFrameClicked = false; // هل الزر المضغوط يخص "الإطار" تحديدًا (معالجة خاصة)
    bool isSashClicked = false; // هل يخص "الظلفة"
    bool isSideCoverClicked = false; // هل يخص "الغطاء الجانبي"
    // ---- التعرف على الإطار: إما بالاسم الثابت أو بمطابقة الاسم المعروض الحالي ----
    if (pType == 'الإطار (Frame)' || pType == 'الإطار (Cadre)') {
      isFrameClicked = true;
    } else if (widget.model.frameOverride != null) {
      String frameDisplay =
      '${widget.model.frameOverride!['code'] ?? ''} - ${widget.model.frameOverride!['name']}'
          .trim();
      if (frameDisplay.startsWith('- ')) {
        frameDisplay = frameDisplay.substring(2); // إزالة "- " إذا لم يكن هناك كود
      }
      if (pType == frameDisplay) isFrameClicked = true;
    }
    // ---- نفس المنطق للظلفة ----
    if (pType == 'الظلفة (Sash)') {
      isSashClicked = true;
    } else if (widget.model.sashOverride != null) {
      String sashDisplay =
      '${widget.model.sashOverride!['code'] ?? ''} - ${widget.model.sashOverride!['name']}'
          .trim();
      if (sashDisplay.startsWith('- ')) sashDisplay = sashDisplay.substring(2);
      if (pType == sashDisplay) isSashClicked = true;
    }
    // ---- نفس المنطق للغطاء الجانبي ----
    if (pType == 'الغطاء الجانبي (Side Cover)') {
      isSideCoverClicked = true;
    } else if (widget.model.sideCoverOverride != null) {
      String sideCoverDisplay =
      '${widget.model.sideCoverOverride!['code'] ?? ''} - ${widget.model.sideCoverOverride!['name']}'
          .trim();
      if (sideCoverDisplay.startsWith('- ')) {
        sideCoverDisplay = sideCoverDisplay.substring(2);
      }
      if (pType == sideCoverDisplay) isSideCoverClicked = true;
    }
    // ===================== حالة: ضغطة زر الإطار =====================
    if (isFrameClicked) {
      // فتح نافذة اختيار بروفيل من نوع "frame" ضمن السلسلة النشطة والمادة الصحيحة (PVC/ألمنيوم)
      final selected = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (context) => ProfileSelectorDialog(
          profileType: 'frame',
          category: 'profile',
          seriesId: widget.model.systemMode == 'sliding'
              ? widget.model.activeSlidingSeries?.id
              : widget.model.activeSeries?.id,
          materialType: widget.model.isPVC ? 'PVC' : 'Aluminium',
        ),
      );
      if (selected != null && mounted) {
        double price = 0.0;
        if (widget.model.selectedDbColor != null) {
          int colorId = widget.model.selectedDbColor!['id'];
          final db = SqlDatabase();
          price = await db.getSectionPrice(selected['id'], colorId); // جلب السعر حسب اللون
        }
        final mutableSelected = Map<String, dynamic>.from(selected);
        mutableSelected['calculated_price'] = price;
        // إذا كان الإطار الجديد مرتبطًا بحديد دعم (renfort)، اجلبه تلقائيًا
        if (mutableSelected['linked_renfort_id'] != null) {
          final dbInstance = await SqlDatabase().db;
          final rRes = await dbInstance!.query(
            'Sections',
            where: 'id = ?',
            whereArgs: [mutableSelected['linked_renfort_id']],
          );
          if (rRes.isNotEmpty) {
            final rMap = Map<String, dynamic>.from(rRes.first);
            rMap['calculated_price'] = _safeDouble(
              rMap['price_dzd'] ?? rMap['price'],
            );
            widget.model.componentOverrides['حديد الإطار (Renfort Frame)'] =
                rMap;
          }
        } else {
          // الإطار الجديد لا يحتاج حديدًا: احذف أي حديد قديم كان مرتبطًا بالإطار السابق
          widget.model.componentOverrides.remove('حديد الإطار (Renfort Frame)');
        }
        setState(() {
          // تحديث الإطار حسب وضع النظام (منزلق/عادي)
          if (widget.model.systemMode == 'sliding') {
            widget.model.slidingFrameOverride = mutableSelected;
          } else {
            widget.model.frameOverride = mutableSelected;
          }
          widget.model.updateProfileThickness(); // إعادة حساب السماكات المرتبطة بعد تغيير الإطار
          widget.model.refreshUI();
        });
      }
      return; // إنهاء الدالة هنا (لا تكمل باقي منطق التبديل العام)
    }
    // ===================== حالة: ضغطة زر الظلفة =====================
    if (isSashClicked) {
      final selected = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (context) => ProfileSelectorDialog(
          profileType: 'sash',
          category: 'profile',
          seriesId: widget.model.systemMode == 'sliding'
              ? widget.model.activeSlidingSeries?.id
              : widget.model.activeSeries?.id,
          materialType: widget.model.isPVC ? 'PVC' : 'Aluminium',
        ),
      );
      if (selected != null && mounted) {
        double price = 0.0;
        if (widget.model.selectedDbColor != null) {
          int colorId = widget.model.selectedDbColor!['id'];
          final db = SqlDatabase();
          price = await db.getSectionPrice(selected['id'], colorId);
        }
        final mutableSelected = Map<String, dynamic>.from(selected);
        mutableSelected['calculated_price'] = price;
        // إذا كانت الظلفة الجديدة مرتبطة بحديد دعم، اجلبه + ابحث عن حديد مفصل خاص (Mifsal) كما في _fetchDefaults
        if (mutableSelected['linked_renfort_id'] != null) {
          final dbInstance = await SqlDatabase().db;
          final rRes = await dbInstance!.query(
            'Sections',
            where: 'id = ?',
            whereArgs: [mutableSelected['linked_renfort_id']],
          );
          if (rRes.isNotEmpty) {
            final rMap = Map<String, dynamic>.from(rRes.first);
            rMap['calculated_price'] = _safeDouble(
              rMap['price_dzd'] ?? rMap['price'],
            );
            widget.model.componentOverrides['حديد الظلفة (Renfort Sash)'] =
                rMap;
            // بحث عن حديد المفاصل الخاص ضمن نفس السلسلة
            final mifsalRes = await dbInstance.query(
              'Sections',
              where:
              'series_id = ? AND (name LIKE ? OR type LIKE ? OR name LIKE ? OR type LIKE ? OR name LIKE ? OR type LIKE ? OR name LIKE ? OR type LIKE ? OR name LIKE ? OR type LIKE ?)',
              whereArgs: [
                (widget.model.systemMode == 'sliding' &&
                    widget.model.activeSlidingSeries != null)
                    ? widget.model.activeSlidingSeries!.id
                    : widget.model.activeSeries?.id,
                '%مفصل%',
                '%مفصل%',
                '%مفاصل%',
                '%مفاصل%',
                '%mifsal%',
                '%mifsal%',
                '%paumelle%',
                '%paumelle%',
                '%pomelle%',
                '%pomelle%',
              ],
              limit: 1,
            );
            if (mifsalRes.isNotEmpty) {
              final mifsalMap = Map<String, dynamic>.from(mifsalRes.first);
              mifsalMap['calculated_price'] = _safeDouble(
                mifsalMap['price_dzd'] ?? mifsalMap['price'],
              );
              widget.model.componentOverrides['حديد الظلفة الخاص بالمفاصل'] =
                  mifsalMap;
            } else {
              widget.model.componentOverrides['حديد الظلفة الخاص بالمفاصل'] =
                  rMap;
            }
          }
        } else {
          // إزالة أي حديد ظلفة قديم إذا الظلفة الجديدة لا تحتاجه
          widget.model.componentOverrides.remove('حديد الظلفة (Renfort Sash)');
          widget.model.componentOverrides.remove('حديد الظلفة الخاص بالمفاصل');
        }
        setState(() {
          if (widget.model.systemMode == 'sliding') {
            widget.model.slidingSashOverride = mutableSelected;
          } else {
            widget.model.sashOverride = mutableSelected;
          }
          widget.model.updateAllSashThicknesses(); // إعادة حساب سماكات كل الظلف بعد التغيير
          widget.model.refreshUI();
        });
      }
      return;
    }
    // ===================== حالة: ضغطة زر الغطاء الجانبي =====================
    if (isSideCoverClicked) {
      final selected = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (context) => ProfileSelectorDialog(
          profileType: 'side_cover',
          category: 'profile',
          seriesId: widget.model.systemMode == 'sliding'
              ? widget.model.activeSlidingSeries?.id
              : widget.model.activeSeries?.id,
          materialType: widget.model.isPVC ? 'PVC' : 'Aluminium',
        ),
      );
      if (selected != null && mounted) {
        double price = 0.0;
        if (widget.model.selectedDbColor != null) {
          int colorId = widget.model.selectedDbColor!['id'];
          final db = SqlDatabase();
          price = await db.getSectionPrice(selected['id'], colorId);
        }
        final mutableSelected = Map<String, dynamic>.from(selected);
        mutableSelected['calculated_price'] = price;
        setState(() {
          widget.model.sideCoverOverride = mutableSelected;
          widget.model.refreshUI();
        });
      }
      return;
    }
    // ===================== الحالة العامة: تحويل اسم العنصر إلى "نوع بحث" (pType) مناسب =====================
    // كل الحالات التالية تُغيّر pType/pCategory إلى صيغة يفهمها ProfileSelectorDialog للبحث
    // الجوانات (Joints)
    if (pType.contains('جوان') || pType.toLowerCase().contains('joint')) {
      pCategory = 'joint';
      if (pType.contains('بروس') || pType.toLowerCase().contains('bross')) {
        pType = ('Joint bross');
      }
      // البراغي: كل نوع برغي يُحوّل إلى اسم العمود المطابق في قاعدة البيانات
    } else if (pType.contains('براغي')) {
      pCategory = 'accessory';
      if (pType.contains('براغي حديد الدعم')) {
        pType = 'is_renfort_screw';
      } else if (pType.contains('براغي بوشون باتمو')) {
        pType = 'is_bouchon_batmo_screw';
      } else if (pType.contains('براغي الباتمو')) {
        pType = 'is_batmo_screw';
      } else if (pType.contains('براغي الكيت'))
        pType = 'is_kit_screw';
      else if (pType.contains('براغي المانيفال'))
        pType = 'is_manivelle_screw';
      else if (pType.contains('براغي المحرك'))
        pType = 'is_moteur_screw';
      else if (pType.contains('براغي الصندوق')) {
        pType = 'is_caisson_screw';
      } else if (pType.contains('براغي التجميع'))
        pType = 'is_assembly_screw';
      else if (pType.contains('براغي التركيب'))
        pType = 'is_installation_screw';
      else if (pType.contains('براغي الإكسسوارات'))
        pType = 'is_accessory_screw';
      // إكسسوارات عامة أخرى (قاش، إسبانيوليت، مفاصل، فيرو، مقبض، طاسو)
    } else if (pCategory == 'accessory') {
      if (pType.contains('قاش دوبل') || pType.contains('Gache Double')) {
        pType = 'is_gache_double';
      } else if (pType.contains('قاش سامبل') || pType.contains('Gache Simple')) {
        pType = 'is_gache_simple';
      } else if (pType.contains('قاش بورت') || pType.contains('Gache Porte') || pType.contains('Gâche Porte')) {
        pType = 'is_gache_porte';
      } else if (pType.contains('كاش كوليسون') ||
          pType.toLowerCase().contains('gache coulisse') ||
          pType.toLowerCase().contains('gâche coulisse') ||
          pType.toLowerCase().contains('gache coulissant') ||
          pType.toLowerCase().contains('gâche coulissant')) {
        pType = 'كاش كوليسون';
      } else if (pType.contains('مقبض الباب (Poignée Porte à Clé)')) {
        pType = 'is_poign_clef';
      } else if (pType.contains('مقبض الباب Condamnation')) {
        pType = 'is_poign_condamnation';
      } else if (pType.contains('الأسطوانة') || pType.contains('Canon')) {
        pType = 'is_canon';
      } else if (pType.contains('قفل بمفتاح') || pType.contains('Clef')) {
        pType = 'is_lock_clef';
      } else if (pType.contains('Serrure Condamnation') || pType.contains('قفل الباب Condamnation') || pType.contains('Condamnation')) {
        pType = 'is_lock_condamnation';
      } else if (pType.contains('قفل الباب') || pType.contains('Serrure')) {
        pType = 'is_lock_clef';
      } else if (pType.contains('اسبانيوليت') || pType.contains('إسبانيوليت')) {
        pType = 'اسبانيوليت';
      } else if (pType.contains('مفاصل') || pType.contains('Hinges')) {
        pType = 'مفاصل';
      } else if ((pType.contains('فيرو') || pType.contains('Verrou')) &&
          !pType.contains('Central')) {
        pType = 'فيرو';
      } else if (pType.contains('مقبض') ||
          pType.contains('Handle') ||
          pType.contains('Poignée')) {
        pType = 'مقبض';
      } else if (pType.contains('الطاسو') ||
          pType.toLowerCase().contains('tasso')) {
        pType = 'tasso';
      } else if (pType.contains('عجلات') ||
          pType.toLowerCase().contains('roulette')) {
        pType = 'roulette';
      } else if (pType.contains('أونتروماتيك') ||
          pType.contains('Entrematique') ||
          pType.contains('انتراميتيك') ||
          pType.toLowerCase().contains('intra')) {
        pType = 'entrematique';
      }
      // بروفيلات: تحديد النوع الفرعي (حديد/تقسيم/بوشون باتمو/باتمو/باركلوز/راي)
    } else if (pCategory == 'profile') {
      if (pType.toLowerCase().contains('renfort') ||
          pType.contains('renfore') ||
          pType.contains('الدعم') ||
          pType.contains('حديد')) {
        pType = 'renfort';
      } else if (pType.toLowerCase().contains('traverse') ||
          pType.contains('التقسيم')) {
        pType = 'mullion';
      } else if (pType.toLowerCase().contains('bouchon') ||
          pType.contains('بوشون') ||
          pType.toLowerCase().contains('bochon')) {
        pType = 'bouchon batmo';
      } else if (pType.toLowerCase().contains('batmo') ||
          pType.contains('باتمو')) {
        pType = 'batmo';
      } else if (pType.toLowerCase().contains('reducteur') ||
          pType.toLowerCase().contains('réducteur') ||
          pType.contains('ريديكتور') ||
          pType.contains('مخفض')) {
        pType = '67114';
      } else if (pType.toLowerCase().contains('parclose') ||
          pType.contains('باكيت') ||
          pType.contains('بيركلوز')) {
        pType = 'parclose';
      } else if (pType.toLowerCase().contains('rail') ||
          pType.contains('الري') ||
          pType.contains('سكة')) {
        pType = 'rail';
      }
      // مكونات الستار: تحديد نوعها الدقيق (مانيفال/محرك/صندوق/كيت/سكك/شريحة نهائية/شريحة/محور/أطاش...)
    } else if (pCategory == 'shutter') {
      if (pType.contains('مانيفال') ||
          pType.toLowerCase().contains('manivelle')) {
        pType = 'مانيفال';
      } else if (pType.contains('محرك') ||
          pType.toLowerCase().contains('moteur')) {
        pType = 'محرك';
      } else if (pType.contains('صندوق') ||
          pType.toLowerCase().contains('caisson')) {
        pType = 'صندوق';
      } else if (pType.contains('كيت') || pType.toLowerCase().contains('kit')) {
        pType = 'كيت';
      } else if (pType.contains('سكك') ||
          pType.toLowerCase().contains('coulisse')) {
        pType = 'سكك';
      } else if (pType.toLowerCase().contains('lame finale') ||
          pType.contains('النهائية') ||
          pType.contains('نهائية')) {
        pType = 'شريحة نهائية';
      } else if (pType.contains('شرائح') ||
          pType.toLowerCase().contains('lame')) {
        pType = 'شريحة';
      } else if (pType.contains('محور') ||
          pType.toLowerCase().contains('axe')) {
        pType = 'محور';
      } else if (pType.contains('أطاش') ||
          pType.toLowerCase().contains('attache')) {
        pType = 'أطاش';
      } else if (pType.contains('سيبور موتور') ||
          pType.toLowerCase().contains('support_moteur') ||
          pType.toLowerCase().contains('support moteur')) {
        pType = 'سيبور موتور';
      } else if (pType.contains('الامبو') ||
          pType.toLowerCase().contains('embout')) {
        pType = 'الامبو';
      } else if (pType.contains('سيبور رولمو') ||
          pType.toLowerCase().contains('support_roulement') ||
          pType.toLowerCase().contains('support roulement')) {
        pType = 'سيبور رولمو';
      } else if (pType.contains('أغطية الشفرات') ||
          pType.toLowerCase().contains('bouchons lames') ||
          pType.toLowerCase().contains('bouchon lame')) {
        pType = 'أغطية الشفرات';
      }
    }
    // إذا كانت الشريحة (Lames) مختارة، نمرر معرّفها (bladeId) لنافذة الاختيار لفلترة الخيارات المتوافقة معها
    final bladeObj = widget.model.componentOverrides['الشرائح (Lames)'];
    final int? bladeId = bladeObj != null ? bladeObj['id'] as int? : null;
    // فتح نافذة الاختيار العامة بالمعطيات المحسوبة أعلاه
    final selected = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => ProfileSelectorDialog(
        profileType: pType,
        category: pCategory,
        seriesId: widget.model.systemMode == 'sliding'
            ? widget.model.activeSlidingSeries?.id
            : widget.model.activeSeries?.id,
        materialType: widget.model.isPVC ? 'PVC' : 'Aluminium',
        windowHeight: widget.model.height,
        targetSize: widget.model.shutterBoxHeight,
        bladeId: bladeId,
      ),
    );
    if (selected != null && mounted) {
      try {
        double price = 0.0;
        final db = SqlDatabase();
        // حساب السعر: بروفيل حسب اللون، وإلا السعر العام المباشر
        if (pCategory == 'profile' && widget.model.selectedDbColor != null) {
          int colorId = widget.model.selectedDbColor!['id'];
          price = await db.getSectionPrice(selected['id'], colorId);
          if (price <= 0) {
            price = _safeDouble(selected['price_dzd'] ?? selected['price']);
          }
        } else {
          price = _safeDouble(selected['price_dzd'] ?? selected['price']);
        }
        final mutableSelected = Map<String, dynamic>.from(selected);
        if (price > 0) mutableSelected['calculated_price'] = price;
        final isKitItem =
            item.originalName.contains('Kit') ||
                item.originalName.contains('كيت');
        final isCaisson = item.originalName == 'الصندوق (Caisson)';
        // إذا كان العنصر المُبدَّل هو "الصندوق"، حدد وضع التونيل حسب id خاص (-999 يعني تونيل)
        if (isCaisson) {
          if (mutableSelected['id'] == -999) {
            widget.model.toggleCaissonTunnel(true);
          } else {
            widget.model.toggleCaissonTunnel(false);
          }
        }
        Map<String, dynamic>? companionCaissonToSet; // صندوق مرافق يجب ضبطه إذا اخترنا كيتًا
        // ---- محاذاة الصندوق مع الكيت المناسب (بالاتجاهين: صندوق→كيت أو كيت→صندوق) ----
        if (isCaisson || isKitItem) {
          final selectedDigits = getComponentSize(mutableSelected);
          if (selectedDigits != null) {
            final dbInstance = await db.db;
            if (dbInstance != null) {
              if (isCaisson) {
                // اخترنا صندوقًا جديدًا: ابحث عن الكيتات النشطة حسب الآلية الحالية وحدّثها لتطابق مقاس الصندوق
                final isMotor = widget.model.shutterMechanism == 'محرك';
                final isCrankSwap =
                    widget.model.shutterMechanism == 'منايفال' ||
                        widget.model.shutterMechanism == 'مانيفال' ||
                        widget.model.shutterMechanism == 'مانيفر';
                final List<String> activeKitKeys;
                if (isMotor) {
                  activeKitKeys = ['كيت فولي موتور (Kit Volet Moteur)'];
                } else if (isCrankSwap) {
                  activeKitKeys = [
                    'كيت فولي مانيفر (Kit Volet Manivelle)',
                    'كيت مانيفر (Kit Manivelle)',
                  ];
                } else {
                  activeKitKeys = ['كيت حزام (Kit Sangle)'];
                }
                for (var kitKey in activeKitKeys) {
                  // كلمات مفتاحية مختلفة للبحث حسب نوع الكيت المطلوب
                  List<String> keywords = [];
                  if (kitKey == 'كيت فولي موتور (Kit Volet Moteur)') {
                    keywords = [
                      'kit_moteur',
                      'Kit Moteur',
                      'kit moteur',
                      'كيت محرك',
                    ];
                  } else if (kitKey ==
                      'كيت فولي مانيفر (Kit Volet Manivelle)') {
                    keywords = [
                      'kit volet',
                      'Kit Volet',
                      'Kit Volée',
                      'Kit Shutter',
                      'كيت الستار',
                      'Kit',
                    ];
                  } else if (kitKey == 'كيت مانيفر (Kit Manivelle)') {
                    keywords = [
                      'kit_manivelle',
                      'Kit Manivelle',
                      'كيت مانيفال',
                      'kit manivelle',
                    ];
                  } else if (kitKey == 'كيت حزام (Kit Sangle)') {
                    keywords = [
                      'kit_sangle',
                      'Kit Sangle',
                      'kit sangle',
                      'كيت حزام',
                      'kit volet',
                      'Kit Volet',
                      'Kit',
                    ];
                  }
                  // بناء شرط WHERE ديناميكي (OR بين كل الكلمات المفتاحية على اسم أو نوع المكوّن)
                  String whereClause = keywords
                      .map((_) => 'name LIKE ? OR component_type LIKE ?')
                      .join(' OR ');
                  List<String> args = [];
                  for (var kw in keywords) {
                    args.addAll(['%$kw%', '%$kw%']);
                  }
                  final compRes = await dbInstance.query(
                    'ShutterComponents',
                    where:
                    "($whereClause) AND (is_active = 1 OR is_active IS NULL)",
                    whereArgs: args,
                  );
                  for (var row in compRes) {
                    if (getComponentSize(row) == selectedDigits) {
                      // وجدنا كيتًا بنفس مقاس الصندوق الجديد: نحفظه
                      final matchedCompanion = Map<String, dynamic>.from(row);
                      matchedCompanion['calculated_price'] = _safeDouble(
                        matchedCompanion['price_dzd'] ??
                            matchedCompanion['price'],
                      );
                      widget.model.componentOverrides[kitKey] =
                          matchedCompanion;
                      break;
                    }
                  }
                }
              } else {
                // اخترنا كيتًا جديدًا: ابحث عن الصندوق المرافق بنفس مقاسه
                final compRes = await dbInstance.query(
                  'ShutterComponents',
                  where:
                  "(LOWER(name) LIKE '%box%' OR name LIKE '%صندوق%' OR LOWER(name) LIKE '%caisson%') AND (is_active = 1 OR is_active IS NULL)",
                );
                for (var row in compRes) {
                  if (getComponentSize(row) == selectedDigits) {
                    companionCaissonToSet = Map<String, dynamic>.from(row);
                    companionCaissonToSet['calculated_price'] = _safeDouble(
                      companionCaissonToSet['price_dzd'] ??
                          companionCaissonToSet['price'],
                    );
                    break;
                  }
                }
              }
            }
          }
        }
        // متغيرات المكونات المرافقة للشرائح/السكك/الشريحة النهائية
        Map<String, dynamic>? companionLame;
        Map<String, dynamic>? companionCoulisse;
        Map<String, dynamic>? companionFinale;
        // إذا كان العنصر المُبدَّل هو الشريحة أو السكة أو الشريحة النهائية، احسب البقية تلقائيًا
        if (item.originalName == 'الشرائح (Lames)' ||
            item.originalName == 'السكك (Coulisses)' ||
            item.originalName == 'الشريحة النهائية (Lame Finale)') {
          final selectedDigits = getComponentSize(mutableSelected);
          if (selectedDigits != null) {
            final dbInstance = await db.db;
            if (dbInstance != null) {
              // 1. إيجاد "شريحة" مرافقة (بأقرب مقاس ونفس subtype) إذا لم يكن العنصر المُبدَّل هو الشريحة نفسها
              if (item.originalName != 'الشرائح (Lames)') {
                final targetSubtype =
                (item.originalName == 'الشريحة النهائية (Lame Finale)')
                    ? (mutableSelected['shutter_subtype']?.toString() ??
                    'normal')
                    : (widget
                    .model
                    .componentOverrides['الشرائح (Lames)']?['shutter_subtype']
                    ?.toString() ??
                    'normal');
                final res = await dbInstance.query(
                  'ShutterComponents',
                  where:
                  "(LOWER(name) LIKE '%lame%' OR name LIKE '%شريح%') AND shutter_subtype = ? AND (is_active = 1 OR is_active IS NULL)",
                  whereArgs: [targetSubtype],
                );
                final targetSize = double.tryParse(selectedDigits) ?? 0.0;
                if (res.isNotEmpty && targetSize > 0) {
                  Map<String, dynamic>? closestLame;
                  double minDiff = double.infinity;
                  for (var row in res) {
                    final rowName = row['name'].toString();
                    // استبعاد الشرائح النهائية من البحث عن شريحة عادية
                    if (rowName.toLowerCase().contains('final') ||
                        rowName.toLowerCase().contains('finale') ||
                        rowName.contains('نهائي')) {
                      continue;
                    }
                    final szStr = getComponentSize(row) ?? '';
                    final sz = double.tryParse(szStr) ?? 0.0;
                    if (sz > 0) {
                      final diff = (sz - targetSize).abs();
                      if (diff < minDiff) {
                        minDiff = diff;
                        closestLame = row;
                      }
                    }
                  }
                  if (closestLame != null) {
                    companionLame = Map<String, dynamic>.from(closestLame);
                    companionLame['calculated_price'] = _safeDouble(
                      companionLame['price_dzd'] ?? companionLame['price'],
                    );
                  }
                }
                // خطة بديلة: بحث بالمقاس الدقيق بدون شرط subtype
                if (companionLame == null) {
                  final resFallback = await dbInstance.query(
                    'ShutterComponents',
                    where:
                    "(LOWER(name) LIKE '%lame%' OR name LIKE '%شريح%') AND (is_active = 1 OR is_active IS NULL)",
                  );
                  for (var row in resFallback) {
                    final rowName = row['name'].toString();
                    if (rowName.toLowerCase().contains('final') ||
                        rowName.toLowerCase().contains('finale') ||
                        rowName.contains('نهائي')) {
                      continue;
                    }
                    if (getComponentSize(row) == selectedDigits) {
                      companionLame = Map<String, dynamic>.from(row);
                      companionLame['calculated_price'] = _safeDouble(
                        companionLame['price_dzd'] ?? companionLame['price'],
                      );
                      break;
                    }
                  }
                }
              }
              // 2. إيجاد سكة (Coulisse) مرافقة إذا العنصر المُبدَّل ليس السكة نفسها
              if (item.originalName != 'السكك (Coulisses)') {
                final res = await dbInstance.query(
                  'ShutterComponents',
                  where:
                  "(LOWER(name) LIKE '%coulisse%' OR name LIKE '%سك%') AND (is_active = 1 OR is_active IS NULL)",
                );
                for (var row in res) {
                  if (getComponentSize(row) == selectedDigits) {
                    companionCoulisse = Map<String, dynamic>.from(row);
                    companionCoulisse['calculated_price'] = _safeDouble(
                      companionCoulisse['price_dzd'] ??
                          companionCoulisse['price'],
                    );
                    break;
                  }
                }
              }
              // 3. إيجاد شريحة نهائية مرافقة إذا العنصر المُبدَّل ليس الشريحة النهائية نفسها
              if (item.originalName != 'الشريحة النهائية (Lame Finale)') {
                final targetSubtype = (item.originalName == 'الشرائح (Lames)')
                    ? (mutableSelected['shutter_subtype']?.toString() ??
                    'normal')
                    : (widget
                    .model
                    .componentOverrides['الشرائح (Lames)']?['shutter_subtype']
                    ?.toString() ??
                    'normal');
                final targetSize = double.tryParse(selectedDigits) ?? 0.0;
                if (targetSize > 0) {
                  companionFinale = await _findClosestFinalBlade(
                    dbInstance,
                    targetSize,
                    targetSubtype,
                  );
                }
              }
            }
          }
        }
        // متغيرات مكونات مرافقة إضافية عند تغيير الشريحة أو المحرك
        Map<String, dynamic>? companionAxe;
        Map<String, dynamic>? companionAttache;
        Map<String, dynamic>? companionSupportMoteur;
        Map<String, dynamic>? companionEmbout;
        Map<String, dynamic>? companionSupportRoulement;
        Map<String, dynamic>? companionTandem;
        Map<String, dynamic>? companionBouchonLame;
        // إذا تم تغيير "الشرائح" تحديدًا، أعد حساب كل القطع المرتبطة بها دفعة واحدة
        if (item.originalName == 'الشرائح (Lames)') {
          final targetSubtype =
              mutableSelected['shutter_subtype']?.toString() ?? 'normal';
          companionAxe = await _findShutterComponent('laxe', targetSubtype);
          if (companionFinale == null) {
            companionFinale = await _findShutterComponent(
              'final_blade',
              targetSubtype,
            );
          }
          companionAttache = await _findShutterComponent(
            'attache',
            targetSubtype,
          );
          companionSupportMoteur = await _findShutterComponent(
            'support_moteur',
            targetSubtype,
          );
          companionEmbout = await _findShutterComponent(
            'embout',
            targetSubtype,
          );
          companionSupportRoulement = await _findShutterComponent(
            'support_roulement',
            targetSubtype,
          );
          companionTandem = await _findShutterComponent(
            'tandem',
            targetSubtype,
          );
          companionBouchonLame = await _findShutterComponent(
            'bouchon_lame',
            targetSubtype,
          );
        }
        // إذا تم تغيير "المحرك" تحديدًا، أعد إيجاد المحور المطابق لقطر المحرك الجديد
        if (item.originalName == 'المحرك (Moteur)') {
          final motorDiameter = (mutableSelected['motor_diameter'] ?? '')
              .toString()
              .trim();
          final motorName = mutableSelected['name']?.toString() ?? '';
          String targetDia = motorDiameter;
          if (targetDia.isEmpty) {
            final diaMatch = RegExp(
              r'(\d+)\s*(?:mm|ملم)',
            ).firstMatch(motorName);
            if (diaMatch != null) {
              targetDia = diaMatch.group(1)!;
            } else {
              if (motorName.contains('60')) {
                targetDia = '60';
              } else if (motorName.contains('40')) {
                targetDia = '40';
              }
            }
          }
          if (targetDia.isNotEmpty) {
            final dbInstance = await db.db;
            if (dbInstance != null) {
              final axeRes = await dbInstance.query(
                'ShutterComponents',
                where:
                "(component_type = 'Axe' OR name LIKE '%axe%' OR name LIKE '%محور%') AND (is_active = 1 OR is_active IS NULL)",
              );
              for (final row in axeRes) {
                final axeName = row['name'].toString();
                final axeDiameter = (row['motor_diameter'] ?? '')
                    .toString()
                    .trim();
                if (axeDiameter == targetDia || axeName.contains(targetDia)) {
                  companionAxe = Map<String, dynamic>.from(row);
                  companionAxe['calculated_price'] = _safeDouble(
                    companionAxe['price_dzd'] ?? companionAxe['price'],
                  );
                  break;
                }
              }
            }
          }
        }
        // ---- تطبيق كل التغييرات: إما مسار الكيت (معالجة خاصة) أو المسار العام لتحديث componentOverrides ----
        if (isKitItem) {
          await _handleKitSelection(mutableSelected); // كيت: نمرر المعالجة كاملة لدالة مخصصة
        } else {
          setState(() {
            widget.model.componentOverrides[item.originalName] =
                mutableSelected; // حفظ الاختيار الجديد كـ override
            // Bidirectional synchronization between B.O.M. profile selection and drawer stiles/montants checkboxes
            if (item.originalName == 'قائم جانبي (Sash Lateral)' || item.originalName == 'قائم جانبي (Lateral)') {
              final String code = (mutableSelected['code'] ?? '').toString();
              final String name = (mutableSelected['name'] ?? '').toString().toLowerCase();
              final String type = (mutableSelected['type'] ?? '').toString().toLowerCase();
              bool isRenforce = code.endsWith('108') ||
                  name.contains('معزز') || name.contains('renforc') ||
                  type.contains('renforc');
              for (var zone in widget.model.zones) {
                if (zone.content == ZoneContent.slidingSash) {
                  zone.slidingMontantReinforced['lateral_0'] = isRenforce;
                  zone.slidingMontantReinforced['lateral_1'] = isRenforce;
                }
              }
            } else if (item.originalName == 'قائم وسطي (Sash Central)' || item.originalName == 'قائم وسطي (Central)') {
              final String code = (mutableSelected['code'] ?? '').toString();
              final String name = (mutableSelected['name'] ?? '').toString().toLowerCase();
              final String type = (mutableSelected['type'] ?? '').toString().toLowerCase();
              bool isRenforce = code.endsWith('107') ||
                  name.contains('معزز') || name.contains('renforc') ||
                  type.contains('renforc');
              for (var zone in widget.model.zones) {
                if (zone.content == ZoneContent.slidingSash) {
                  final int sashes = zone.slidingSashesCount > 0 ? zone.slidingSashesCount : 2;
                  final int centralCount = (sashes * 2) - 2;
                  for (int s = 0; s < centralCount; s++) {
                    zone.slidingMontantReinforced['central_$s'] = isRenforce;
                  }
                }
              }
            }
            widget.model.updateGlassGasket(); // تحديث جوان الزجاج (إن كان مرتبطًا بتغييرات البروفيل)
            // إذا كانت الشريحة الجديدة "extruded"، فرض الآلية على محرك (لأن الإكسترودي ثقيل ويحتاج محركًا)
            if (item.originalName == 'الشرائح (Lames)') {
              widget.model.shutterLame =
                  mutableSelected['name']?.toString() ?? '';
              final bladeSubtype =
              (mutableSelected['shutter_subtype']?.toString() ?? '')
                  .toLowerCase();
              final bladeName = (mutableSelected['name']?.toString() ?? '')
                  .toLowerCase();
              if (bladeSubtype == 'extruded' ||
                  bladeName.contains('extruded') ||
                  bladeName.contains('إكسترودي')) {
                widget.model.shutterMechanism = 'محرك';
              }
            }
            // تطبيق كل المكونات المرافقة المحسوبة أعلاه (إن وُجدت) على النموذج
            if (companionCaissonToSet != null) {
              widget.model.componentOverrides['الصندوق (Caisson)'] =
                  companionCaissonToSet;
            }
            if (companionLame != null) {
              widget.model.componentOverrides['الشرائح (Lames)'] =
                  companionLame;
            }
            if (companionCoulisse != null) {
              widget.model.componentOverrides['السكك (Coulisses)'] =
                  companionCoulisse;
            }
            if (companionFinale != null) {
              widget
                  .model
                  .componentOverrides['الشريحة النهائية (Lame Finale)'] =
                  companionFinale;
            }
            if (companionAxe != null) {
              widget.model.componentOverrides['المحور (Axe)'] = companionAxe;
            }
            if (companionAttache != null) {
              widget.model.componentOverrides['أطاش (Attache)'] =
                  companionAttache;
            }
            if (companionSupportMoteur != null) {
              widget.model.componentOverrides['سيبور موتور (Support Moteur)'] =
                  companionSupportMoteur;
            }
            if (companionEmbout != null) {
              widget.model.componentOverrides['الامبو (Embout)'] =
                  companionEmbout;
            }
            if (companionSupportRoulement != null) {
              widget
                  .model
                  .componentOverrides['سيبور رولمو (Support Roulement)'] =
                  companionSupportRoulement;
            }
            if (companionTandem != null) {
              widget.model.componentOverrides['طانديم (Tandem)'] =
                  companionTandem;
            }
            if (companionBouchonLame != null) {
              widget
                  .model
                  .componentOverrides['أغطية الشفرات (Bouchons Lames)'] =
                  companionBouchonLame;
            }
            // تحديث مفتاح تتبع آخر محاذاة للشريحة النهائية (لتفادي إعادة الحساب في _fetchDefaults لاحقًا)
            final lames = widget.model.componentOverrides['الشرائح (Lames)'];
            if (lames != null) {
              final targetSubtype =
                  lames['shutter_subtype']?.toString() ?? 'normal';
              _lastAlignedLameKey =
              "${lames['id']}_${getComponentSize(lames)}_$targetSubtype";
            }
          });
          // إعادة حساب الافتراضيات الشاملة (لأن التغيير قد يؤثر على المحرك المناسب حسب الوزن مثلًا)
          await _fetchDefaults();
        }
      } catch (e) {
        print("Error handling swap selection: $e"); // تسجيل الخطأ دون كسر الشاشة
      }
    }
  }
  // ==========================================================================
  // دالة: _updatePriceInDatabase
  // تحفظ سعرًا جديدًا "بشكل دائم" في قاعدة البيانات (وليس فقط كـ override
  // مؤقت في هذا الطلب)، مع منطق مختلف لكل فئة (بروفيل/إكسسوار/ستار/جوان/زجاج).
  // ==========================================================================
  Future<void> _updatePriceInDatabase(BomItem item, double newPrice) async {
    final db = await SqlDatabase().db;
    if (db == null) return;
    // البحث عن معرف العنصر في جميع المصادر الممكنة
    Map<String, dynamic>? override = widget.model.componentOverrides[item.originalName];
    // إذا لم يُوجد في componentOverrides، ابحث في frameOverride/sashOverride وما إلى ذلك
    if (override == null) {
      final origLower = item.originalName.toLowerCase();
      if (origLower.contains('إطار') || origLower.contains('frame') || origLower.contains('cadre')) {
        override = widget.model.frameOverride ?? widget.model.slidingFrameOverride;
      } else if (origLower.contains('ظلف') || origLower.contains('sash') || origLower.contains('ouvrant')) {
        override = widget.model.sashOverride ?? widget.model.slidingSashOverride;
      } else if (origLower.contains('side_cover') || origLower.contains('تغطية')) {
        override = widget.model.sideCoverOverride;
      }
    }
    final int? dbId = override?['id'] as int?; // معرّف السجل في قاعدة البيانات (إن كان مرتبطًا)
    final colorId = widget.model.selectedDbColor?['id'];
    String? errorMsg; // رسالة خطأ تُعرض للمستخدم إن فشلت العملية
    bool success = false;
    try {
      if (item.category == 'profile') {
        // البروفيلات: يجب أن يكون العنصر مرتبطًا بقاعدة بيانات وأن يكون هناك لون محدد (السعر لوني دائمًا)
        if (dbId != null && colorId != null) {
          await SqlDatabase().setSectionColorPrice(dbId, colorId, newPrice);
          success = true;
        } else {
          errorMsg = 'العنصر غير مرتبط بقاعدة البيانات أو لم يتم تحديد لون';
        }
      } else if (item.category == 'accessory') {
        if (dbId != null) {
          // تحقق: هل هذا الإكسسوار له أسعار لونية مسجّلة أصلًا؟
          final countRes = await db.rawQuery(
            'SELECT COUNT(*) as count FROM AccessoryColorPrices WHERE accessory_id = ?',
            [dbId],
          );
          final hasColorPrices = (countRes.first['count'] as int? ?? 0) > 0;
          if (hasColorPrices && colorId != null) {
            // إذا له نظام تسعير لوني، أضف/حدّث سعر هذا اللون تحديدًا
            await db.insert('AccessoryColorPrices', {
              'accessory_id': dbId,
              'color_id': colorId,
              'price': newPrice,
            }, conflictAlgorithm: ConflictAlgorithm.replace);
          } else {
            // وإلا حدّث السعر العام مباشرة في جدول Accessories
            await db.update(
              'Accessories',
              {'price': newPrice},
              where: 'id = ?',
              whereArgs: [dbId],
            );
          }
          success = true;
        } else {
          errorMsg = 'العنصر غير مرتبط بقاعدة البيانات';
        }
      } else if (item.category == 'shutter') {
        // نفس منطق الإكسسوارات لكن على جدولي ShutterColorPrices/ShutterComponents
        if (dbId != null) {
          final countRes = await db.rawQuery(
            'SELECT COUNT(*) as count FROM ShutterColorPrices WHERE shutter_component_id = ?',
            [dbId],
          );
          final hasColorPrices = (countRes.first['count'] as int? ?? 0) > 0;
          if (hasColorPrices && colorId != null) {
            await SqlDatabase().setShutterColorForComponent(
              shutterComponentId: dbId,
              colorId: colorId,
              enabled: true,
              price: newPrice,
            );
          } else {
            await db.update(
              'ShutterComponents',
              {'price': newPrice},
              where: 'id = ?',
              whereArgs: [dbId],
            );
          }
          success = true;
        } else {
          errorMsg = 'العنصر غير مرتبط بقاعدة البيانات';
        }
      } else if (item.category == 'joint') {
        // الجوانات: تُخزَّن كسعر لكل متر مباشرة (بدون نظام ألوان منفصل)
        if (dbId != null) {
          await db.update(
            'Joints',
            {'price_per_meter': newPrice},
            where: 'id = ?',
            whereArgs: [dbId],
          );
          success = true;
        } else {
          errorMsg = 'العنصر غير مرتبط بقاعدة البيانات';
        }
      } else if (item.category == 'glass' || item.category == 'panneau') {
        // الزجاج: عملية أكثر تعقيدًا — تحاول إيجاد سجل الزجاج المطابق بالضبط عبر التشطيب واللون
        if (widget.model.zones.isNotEmpty) {
          final glassSpec = widget.model.zones.first.glass;
          if (glassSpec.structure == GlassStructure.simple) {
            // زجاج بسيط (طبقة واحدة): نبحث عن السجل بمطابقة كلمات مفتاحية للتشطيب واللون
            final finishKws = widget.model.getFinishKeywords(
              glassSpec.finishOuter,
            );
            final colorKws = widget.model.getColorKeywords(
              glassSpec.colorOuter,
            );
            final glassList = await db.query('Glass');
            int? matchedGlassId;
            // المحاولة الأولى: تطابق التشطيب واللون معًا
            for (var g in glassList) {
              String t = g['type'].toString().toLowerCase();
              String n = g['name'].toString().toLowerCase();
              String c = (g['color'] ?? '').toString().toLowerCase();
              bool matchesFinish = finishKws.any(
                    (kw) => t.contains(kw) || n.contains(kw),
              );
              bool matchesColor = colorKws.any(
                    (kw) => kw.isEmpty ? c.isEmpty : (c == kw || c.contains(kw)),
              );
              if (matchesFinish && matchesColor) {
                matchedGlassId = g['id'] as int?;
                break;
              }
            }
            // المحاولة الثانية (بديلة): مطابقة التشطيب فقط إذا فشلت المطابقة الكاملة
            if (matchedGlassId == null) {
              for (var g in glassList) {
                String t = g['type'].toString().toLowerCase();
                String n = g['name'].toString().toLowerCase();
                bool matchesFinish = finishKws.any(
                      (kw) => t.contains(kw) || n.contains(kw),
                );
                if (matchesFinish) {
                  matchedGlassId = g['id'] as int?;
                  break;
                }
              }
            }
            if (matchedGlassId != null) {
              await db.update(
                'Glass',
                {'price_per_sqm': newPrice},
                where: 'id = ?',
                whereArgs: [matchedGlassId],
              );
              success = true;
            } else {
              errorMsg = 'لم يتم العثور على زجاج مطابق في قاعدة البيانات';
            }
          } else {
            // زجاج مزدوج (Double Glazing): لا يمكن تعديل سعره من هنا مباشرة، لأنه مكوّن من عدة أجزاء
            errorMsg =
            'لأن هذا زجاج مزدوج، يرجى تعديل أسعار مكوناته في إدارة الأسعار لتحديث قاعدة البيانات بشكل دائم';
          }
        } else {
          errorMsg = 'لا توجد مواصفات زجاج';
        }
      }
    } catch (e) {
      errorMsg = 'خطأ أثناء التحديث: $e'; // أي خطأ غير متوقع يُلتقط هنا
    }
    if (success) {
      CloudSyncService().notifyCatalogChange();
    }
    // عرض رسالة نجاح أو فشل للمستخدم عبر SnackBar
    if (mounted) {
      final lang = Provider.of<AppSettingsProvider>(
        context,
        listen: false,
      ).language;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            success
                ? Localization.translate(
              'تم تحديث السعر بنجاح في قاعدة البيانات',
              lang,
            )
                : Localization.translate(errorMsg ?? 'فشل التحديث', lang),
          ),
          backgroundColor: success ? Colors.green : Colors.red,
        ),
      );
    }
  }
  // ==========================================================================
  // دالة: _showEditPriceDialog
  // تفتح نافذة بسيطة لتعديل سعر عنصر واحد، مع خيار "حفظ في قاعدة البيانات
  // أيضًا" (وإلا فالتعديل يبقى محليًا لهذا الطلب فقط عبر componentOverrides).
  // ==========================================================================
  void _showEditPriceDialog(BomItem item) {
    final lang = Provider.of<AppSettingsProvider>(context, listen: false).language;
    final controller = TextEditingController(text: '${item.unitPrice}');
    bool saveToDb = false; // هل نحفظ التعديل بشكل دائم في قاعدة البيانات
    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (ctx, setStateDialog) {
            return AlertDialog(
              title: Text('${Localization.translate('تعديل سعر', lang)} ${Localization.translate(item.name, lang)}'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: controller,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: Localization.translate('السعر الجديد (دج)', lang),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  CheckboxListTile(
                    title: Text(
                      Localization.translate('حفظ في قاعدة البيانات أيضاً', lang),
                      style: const TextStyle(fontSize: 14),
                    ),
                    value: saveToDb,
                    onChanged: (val) {
                      setStateDialog(() {
                        saveToDb = val ?? false;
                      });
                    },
                    controlAffinity: ListTileControlAffinity.leading,
                    contentPadding: EdgeInsets.zero,
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: Text(Localization.translate('إلغاء', lang)),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final newPrice = double.tryParse(controller.text);
                    if (newPrice != null) {
                      setState(() {
                        // إذا العنصر ليس له override أصلًا، أنشئ واحدًا جديدًا بأقل بيانات ضرورية
                        if (!widget.model.componentOverrides.containsKey(
                          item.originalName,
                        )) {
                          widget.model.componentOverrides[item.originalName] = {
                            'name': item.name,
                            'price': newPrice,
                            'calculated_price': newPrice,
                          };
                        } else {
                          // وإلا، انسخ الـ override الحالي وحدّث السعر فيه فقط (بدون فقدان بقية بياناته)
                          final Map<String, dynamic> clone = Map.from(
                            widget.model.componentOverrides[item.originalName],
                          );
                          clone['price'] = newPrice;
                          clone['calculated_price'] = newPrice;
                          widget.model.componentOverrides[item.originalName] =
                              clone;
                        }
                      });
                      // إذا اختار المستخدم حفظه بشكل دائم، نفّذ التحديث الفعلي في قاعدة البيانات
                      if (saveToDb) {
                        await _updatePriceInDatabase(item, newPrice);
                      }
                    }
                    if (dialogContext.mounted) {
                      Navigator.pop(dialogContext);
                    }
                  },
                  child: Text(Localization.translate('حفظ', lang)),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
// ==========================================================================
// دالة عامة خارج الكلاس: _safeDouble
// تحويل آمن لأي قيمة (num/String/null) إلى double، بدون رمي استثناء أبدًا
// ==========================================================================
double _safeDouble(dynamic value) {
  if (value == null) return 0.0;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString()) ?? 0.0;
}
// دالة عامة: تستخرج أول رقم (صحيح أو عشري) موجود داخل نص، وتزيل النقطة العشرية من الناتج
String? extractSizeDigits(String name) {
  final regExp = RegExp(r'\d+(\.\d+)?');
  final match = regExp.firstMatch(name);
  if (match == null) return null;
  return match.group(0)!.replaceAll('.', '');
}
// دالة عامة: تستخرج "مقاس" مكوّن من حقل measurement إن وُجد، وإلا من اسمه مباشرة
String? getComponentSize(Map<String, dynamic> component) {
  final meas = (component['measurement'] ?? '').toString().trim();
  if (meas.isNotEmpty) {
    return meas.replaceAll('.', '').replaceAll(',', ''); // إزالة النقطة والفاصلة لتوحيد صيغة المقارنة
  }
  return extractSizeDigits(component['name'].toString());
}
