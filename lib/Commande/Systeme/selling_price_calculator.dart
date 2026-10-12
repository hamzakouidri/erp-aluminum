import 'package:database_data/Commande/Systeme/model.dart';
import 'package:database_data/Commande/Systeme/calculate_component.dart';
import 'package:database_data/settings/app_settings.dart';

/// Shared selling-price calculation for the material table and order edits.
Map<String, Map<String, double>> calculateSellingTotals({
  required WindowModel model,
  required List<BomItem> items,
  required CostMethod costMethod,
  required double profitMargin,
  required double pricePerSqm,
  required double linearMeterPrice,
  required double shutterSqmPrice,
  Map<int, Map<String, dynamic>> profileRules = const {},
  double obInstallFee = 0,
  double demiObInstallFee = 0,
  double verrouInstallFee = 0,
  double moteurInstallFee = 0,
}) {
  Map<String, dynamic>? _componentOverrideForBom(BomItem item) {
    final primaryKey = item.overrideKey ?? item.originalName;
    final direct = model.componentOverrides[primaryKey];
    if (direct is Map) return Map<String, dynamic>.from(direct);
    final fallback = model.componentOverrides[item.originalName];
    return fallback is Map ? Map<String, dynamic>.from(fallback) : null;
  }

  Map<String, dynamic>? _profileCalculationRuleFor(BomItem item) {
    final id = item.catalogItemId;
    return id == null ? null : profileRules[id];
  }

  bool _isExcludedFromPricing(BomItem item) {
    if (item.category != 'profile') return false;
    final rule = _profileCalculationRuleFor(item);
    return rule?['exclude_from_pricing'] == 1 ||
        rule?['exclude_from_pricing'] == true;
  }

  bool _profileUsesLinearMeter(BomItem item) {
    if (_isExcludedFromPricing(item)) return false;
    final mode = _profileCalculationRuleFor(
      item,
    )?['calculation_mode']?.toString().trim().toLowerCase();
    if (mode == 'linear_meter') return true;
    if (mode == 'base_price') return false;
    final role = (item.roleKey ?? item.selectorType ?? '').trim().toLowerCase();
    return role == 'frame' ||
        role == 'frame_extension' ||
        role.startsWith('sash') ||
        role == 'mullion' ||
        role == 'traverse' ||
        role == 'batmo' ||
        role == 'plant';
  }

  double _profileLinearMultiplier(BomItem item) {
    final rule = _profileCalculationRuleFor(item);
    final mode = rule?['calculation_mode']?.toString().trim().toLowerCase();
    if (mode == 'linear_meter') {
      final value = rule?['linear_meter_multiplier'];
      final parsed = value is num
          ? value.toDouble()
          : double.tryParse('$value');
      if (parsed != null && parsed.isFinite && parsed > 0) return parsed;
    }
    return item.linearMeterMultiplier;
  }

  double profileCost = 0.0; // إجمالي تكلفة البروفيلات
  double glassCost = 0.0; // إجمالي تكلفة الزجاج
  double shutterCost = 0.0; // إجمالي تكلفة الستار وملحقاته
  double accessoryCost = 0.0; // إجمالي تكلفة الإكسسوارات
  double accessorySellingCost =
      0.0; // جزء من تكلفة الإكسسوارات المحدد كـ "قابل للربح" (is_selling_calculated)
  double jointCost = 0.0; // إجمالي تكلفة الجوينات
  double mainProfileMeters =
      0.0; // إجمالي الأمتار الخطية للبروفيلات الرئيسية (مع البلانت ×2)
  double otherProfileCost =
      0.0; // تكلفة البروفيلات الأخرى (غير محسوبة بالمتر الخطي)
  final activeItems = items
      .where((i) => i.isActive)
      .toList(); // فقط العناصر المفعّلة تدخل الحساب
  // دالة داخلية: تحدد هل العنصر ملحق ستار عادي (وليس الشريحة نفسها أو غطاء الشفرات)
  bool isShutterAccessory(BomItem i) {
    if (i.category != 'shutter') return false;
    final nameLower = i.originalName.toLowerCase();
    if (i.originalName == 'الشرائح (Lames)')
      return false; // الشريحة نفسها تُستثنى من هذا التصنيف
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
      // The administrator may override the automatic role classification
      // from Price Management > Profile Prices > Calculation Rules.
      final role = (item.roleKey ?? item.selectorType ?? '')
          .trim()
          .toLowerCase();
      final rule = _profileCalculationRuleFor(item);
      if (rule?['exclude_from_pricing'] == 1 ||
          rule?['exclude_from_pricing'] == true) {
        continue;
      }
      profileCost += item.total;
      final ruleMode = rule?['calculation_mode']
          ?.toString()
          .trim()
          .toLowerCase();
      final isExplicitBasePrice = ruleMode == 'base_price';
      final isExplicitLinearMeter = ruleMode == 'linear_meter';
      final isFrame = role == 'frame' || role == 'frame_extension';
      final isSash = role.startsWith('sash');
      final isMullion = role == 'mullion' || role == 'traverse';
      final isBatmo = role == 'batmo';
      final isPlant = role == 'plant';
      final isRenfort = role == 'renfort' || role.contains('reinforced');
      final isPareClose = role == 'glazing_bead' || role == 'parclose';
      if (isExplicitBasePrice) {
        otherProfileCost += item.total;
      } else if (isExplicitLinearMeter ||
          (!isRenfort &&
              !isPareClose &&
              _profileUsesLinearMeter(item) &&
              (isFrame || isSash || isMullion || isBatmo || isPlant))) {
        // المتر الخطي: يمكن فرضه من صفحة القواعد حتى على بروفيل كان
        // مصنفًا سابقًا كحديد أو باركلوز.
        if (item.pieces != null) {
          mainProfileMeters +=
              item.pieces!.fold<double>(0.0, (sum, p) => sum + p) *
              _profileLinearMultiplier(item);
        } else if (item.length != null) {
          mainProfileMeters +=
              (item.length! / 1000.0) *
              item.quantity *
              _profileLinearMultiplier(item);
        }
      } else if (isRenfort || isPareClose) {
        // الحديد والباركلوز يُضافان فقط لإجمالي التكلفة العامة (لا يدخلان حساب الأمتار الخطية الرئيسية)
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
      final override = _componentOverrideForBom(item);
      // إذا كان العنصر معلَّمًا كـ "قابل لإضافة هامش ربح"، أضفه لتكلفة البيع القابلة للربح
      if (override != null && override['is_selling_calculated'] == 1) {
        accessorySellingCost += item.total;
      }
    }
  }
  // أجور تركيب خاصة (System OB, Demi OB, Verrou) تُضاف مرة واحدة لكل قطعة (× الكمية الكلية)
  double specialAccessoryInstallFees = 0.0;
  bool hasActiveKit(String exactName, List<String> prefixes) => activeItems.any(
    (item) =>
        item.isActive &&
        item.category == 'accessory' &&
        (item.originalName == exactName ||
            prefixes.any((prefix) => item.originalName.startsWith(prefix))),
  );
  if (hasActiveKit('System OB', const ['System OB_'])) {
    specialAccessoryInstallFees += obInstallFee * model.quantity;
  }
  if (hasActiveKit('Demi System OB', const ['Demi System OB_'])) {
    specialAccessoryInstallFees += demiObInstallFee * model.quantity;
  }
  if (hasActiveKit('Verrou Central', const ['Verrou Central_'])) {
    specialAccessoryInstallFees += verrouInstallFee * model.quantity;
  }
  // أجرة تركيب المحرك تُضاف فقط إذا الآلية محرك ووُجد عنصر يخص المحرك مفعّل
  double motorCrankInstallFees = 0.0;
  final mech = model.shutterMechanism;
  final isMotor = mech == 'محرك';
  for (var item in activeItems) {
    if (isShutterAccessory(item)) {
      final nameLower = item.originalName.toLowerCase();
      if ((nameLower.contains('moteur') || nameLower.contains('محرك')) &&
          isMotor) {
        motorCrankInstallFees += moteurInstallFee * model.quantity;
      }
    }
  }
  // متغيرات أسعار البيع لكل قسم (تُحسب حسب طريقة costMethod أدناه)
  double profileSelling = 0.0;
  double glassSelling = 0.0;
  double shutterSelling = 0.0;
  double accessorySelling = 0.0;
  double jointSelling = 0.0;
  // السعر الفعلي لمتر مربع الستار (يدوي إن وُجد، وإلا من قاعدة البيانات)
  double effectiveShutterSqmPrice = shutterSqmPrice;
  bool hasShutter = items.any(
    (item) => item.isActive && item.category == 'shutter',
  );
  double areaSqm = // مساحة النافذة بالمتر المربع
      (model.width / 1000.0) * (model.height / 1000.0);
  double shutterAreaPrice =
      hasShutter // سعر بيع الستار محسوبًا بالمتر المربع (يُستخدم في طريقتين من الثلاث)
      ? (effectiveShutterSqmPrice * areaSqm * model.quantity)
      : 0.0;
  // ---- طريقة 1: النسبة المئوية — سعر البيع = التكلفة × (1 + نسبة الربح) ----
  if (costMethod == CostMethod.percentage) {
    double factor = 1 + profitMargin / 100;
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
  } else if (costMethod == CostMethod.squareMeter) {
    if (model.isShutterOnly) {
      profileSelling = 0.0;
      glassSelling = 0.0;
    } else {
      double windowSellingPrice = pricePerSqm * areaSqm * model.quantity;
      glassSelling = glassCost; // الزجاج يبقى بسعر التكلفة
      profileSelling =
          windowSellingPrice -
          glassCost; // الباقي بعد طرح الزجاج يُنسب للبروفيل
      if (profileSelling < 0.0) profileSelling = 0.0; // حماية من قيمة سالبة
    }
    shutterSelling = shutterAreaPrice;
    accessorySelling =
        accessorySellingCost +
        specialAccessoryInstallFees +
        motorCrankInstallFees;
    jointSelling = jointCost;
    // ---- طريقة 3: سعر المتر الخطي للبروفيلات الرئيسية + تكلفة البروفيلات الأخرى كما هي ----
  } else if (costMethod == CostMethod.linearMeter) {
    profileSelling =
        (mainProfileMeters * (linearMeterPrice)) + otherProfileCost;
    glassSelling = glassCost;
    shutterSelling = shutterAreaPrice;
    accessorySelling =
        accessorySellingCost +
        specialAccessoryInstallFees +
        motorCrankInstallFees;
    jointSelling = jointCost;
  }
  // المجاميع الكلية للتكلفة وسعر البيع
  double totalCost =
      profileCost + glassCost + shutterCost + accessoryCost + jointCost;
  double totalSelling =
      profileSelling +
      glassSelling +
      shutterSelling +
      accessorySelling +
      jointSelling;
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
